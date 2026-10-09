import contextlib
import copy
from http.server import BaseHTTPRequestHandler
import json
import os
from pathlib import Path
import runpy
import socket
import socketserver
import struct
import subprocess
import sys
import threading


helpers = runpy.run_path(str(Path(__file__).with_name("routing-socks5-real.py")))
Server, Destination, Socks = (helpers[name] for name in ("Server", "Destination", "Socks"))
port, running, write_config = (helpers[name] for name in ("port", "running", "write_config"))
exact, socks_address = (helpers[name] for name in ("exact", "socks_address"))
fixture_assets = helpers["fixture_assets"]


class RuleResource(BaseHTTPRequestHandler):
    def do_GET(self):
        self.server.requests += 1
        body = self.server.resources.get(self.path)
        self.send_response(200 if body is not None else 404)
        self.send_header("Content-Length", str(len(body or b"")))
        self.end_headers()
        if body is not None:
            self.server.successes += 1
            self.wfile.write(body)

    def log_message(self, *_):
        pass


def block_names(family):
    suffix = "v6" if family == "ipv6" else "v4"
    return [f"only-block-keyword-{suffix}.padm.invalid", f"block-full-{suffix}.padm.invalid",
            f"sub.block-suffix-{suffix}.padm.invalid", f"block-geo-{suffix}.padm.invalid"]


def policy_assets(root):
    names = [block_names(family)[3] for family in ("ipv4", "ipv6")]
    entries = []
    for name in names:
        value = name.encode("ascii")
        domain = b"\x08\x03\x12" + bytes([len(value)]) + value
        entries.append(b"\x12" + bytes([len(domain)]) + domain)
    # 第二个真实 protobuf 分类与 TEST 独立，保证 Block 不被 Direct 分类放行。
    site = b"\x0a\x05BLOCK" + b"".join(entries)
    assert len(site) < 128
    path = root / "geosite.dat"
    path.write_bytes(path.read_bytes() + b"\x0a" + bytes([len(site)]) + site)
    source = root / "block-rule-set.json"
    source.write_text(json.dumps(dict(version=3, rules=[dict(domain=names)])))
    subprocess.run(["/routing-cores/sing-box", "rule-set", "compile", "--output",
                    str(root / "block.srs"), str(source)], check=True, stdout=subprocess.DEVNULL)
    (root / "block.srs").chmod(0o644)


class DnsServer(socketserver.ThreadingUDPServer):
    daemon_threads = True

    def __init__(self, address):
        self.address_family = socket.AF_INET6 if ":" in address[0] else socket.AF_INET
        super().__init__(address, Dns)
        self.requests = []


class Dns(socketserver.BaseRequestHandler):
    def handle(self):
        request, channel = self.request
        offset, parts = 12, []
        while size := request[offset]:
            offset += 1
            parts.append(request[offset:offset + size].decode("ascii"))
            offset += size
        end = offset + 5
        name = ".".join(parts)
        kind, _ = struct.unpack("!HH", request[offset + 1:end])
        self.server.requests.append(name)
        if name.startswith("timeout-"):
            return
        status = 2 if name.startswith("error-") else 0
        answer = b""
        if status == 0 and kind == self.server.answer_kind:
            family = socket.AF_INET if kind == 1 else socket.AF_INET6
            address = "127.0.0.1" if kind == 1 else "::1"
            value = socket.inet_pton(family, address)
            answer = b"\xc0\x0c" + struct.pack("!HHIH", kind, 1, 30, len(value)) + value
        header = request[:2] + struct.pack("!HHHHH", 0x8180 | status, 1, int(bool(answer)), 0, 0)
        channel.sendto(header + request[12:end] + answer, self.client_address)


def request(host, local, destination, target, http_host=None, timeout=3):
    with socket.create_connection((host, local), timeout=timeout) as conn:
        conn.sendall(b"\x05\x01\x00")
        assert exact(conn, 2) == b"\x05\x00"
        conn.sendall(b"\x05\x01\x00" + socks_address(target) + struct.pack("!H", destination))
        header = exact(conn, 4)
        if header[1]:
            return False
        exact(conn, {1: 4, 4: 16}[header[3]] + 2)
        conn.sendall(b"GET /routing-check HTTP/1.1\r\nHost: " +
                     (http_host or target).encode("ascii") + b"\r\nConnection: close\r\n\r\n")
        data = b""
        while part := conn.recv(4096):
            data += part
        return data.endswith(b"routing-destination-ok")


@contextlib.contextmanager
def system_hosts(family, host):
    suffix = "v6" if family == "ipv6" else "v4"
    names = [f"{prefix}-{suffix}.padm.invalid" for prefix in ("unmatched", "proxy", "error", "timeout")]
    path = Path("/etc/hosts")
    address_names = names + helpers["domain_names"](family) + block_names(family) + [
        f"hosts-{suffix}.padm.invalid"]
    line = f"{host} {' '.join(address_names)} # padm-dns-{os.getpid()}-{family}\n"
    # 只给隔离容器增加可解析诱饵，负测若误回退系统解析就会抵达 HTTP 目的。
    with path.open("a") as target:
        target.write(line)
    try:
        yield names
    finally:
        with path.open("r+") as target:
            retained = [item for item in target.readlines() if item != line]
            target.seek(0)
            target.writelines(retained)
            target.truncate()


def runtime(root, core, family, host, local, dns, upstream, resource, mode="selective"):
    variant = "" if mode == "selective" else "." + mode
    config = json.loads((root / f"{core}.{family}{variant}.json").read_text())
    suffix = "v6" if family == "ipv6" else "v4"
    mapped = f"hosts-{suffix}.padm.invalid"
    mapped_address = "127.0.0.1" if family == "ipv6" else "::1"
    if core == "xray":
        config["dns"]["hosts"]["full:" + mapped] = mapped_address
        if mode.startswith("policy"):
            config["dns"]["hosts"]["full:" + f"proxy-{suffix}.padm.invalid"] = mapped_address
            config["dns"]["hosts"]["full:" + f"block-full-{suffix}.padm.invalid"] = mapped_address
        server = config["dns"]["servers"][0]
        # 仅缩短夹具超时；仍由真实核心决定失败，生产超时保持原值。
        server.update(address=host, port=dns.server_address[1], timeoutMs=250)
        outbound = next((item for item in config["outbounds"] if item["tag"] == "padm-socks5"), None)
        if outbound is not None:
            outbound["settings"]["servers"][0].update(address=host, port=upstream.server_address[1])
        inbound = dict(listen=host, port=local, tag="fixture-in", protocol="socks",
                       settings=dict(auth="noauth", udp=True))
        if mode in ("selective", "policy", "policy-global"):
            sniff = copy.deepcopy(next(item["sniffing"] for item in config["inbounds"]
                                       if item["tag"] != "padm-traffic-api"))
            assert sniff["routeOnly"], "DNS/hosts 不得将 sniff-only Host 改成实际连接目的"
            inbound["sniffing"] = sniff
        config["inbounds"].append(inbound)
    else:
        config["dns"]["timeout"] = "250ms"
        servers = {item["tag"]: item for item in config["dns"]["servers"]}
        servers["padm-hosts"]["predefined"][mapped] = mapped_address
        if mode.startswith("policy"):
            servers["padm-hosts"]["predefined"][f"proxy-{suffix}.padm.invalid"] = mapped_address
            servers["padm-hosts"]["predefined"][f"block-full-{suffix}.padm.invalid"] = mapped_address
        servers["padm-dns"].update(server=host, server_port=dns.server_address[1])
        outbound = next((item for item in config["outbounds"] if item["tag"] == "padm-socks5"), None)
        if outbound is not None:
            outbound.update(server=host, server_port=upstream.server_address[1])
        config["inbounds"].append(dict(type="socks", tag="fixture-in", listen=host, listen_port=local))
        for item in config["route"]["rule_set"]:
            assert item["http_client"] == {"engine": "go"}
            asset = "block" if item["tag"] == "padm-geosite-block" else "test"
            item["url"] = f"http://127.0.0.1:{resource.server_address[1]}/{asset}.srs"
    return config


def check(root, core, family, host):
    suffix = "v6" if family == "ipv6" else "v4"
    names = helpers["domain_names"](family)
    mapped = f"hosts-{suffix}.padm.invalid"
    resource_context = (Server(("127.0.0.1", 0), RuleResource) if core == "sing-box"
                        else contextlib.nullcontext(None))
    with (Server((host, 0), Destination) as destination, DnsServer((host, 0)) as dns,
          Server((host, 0), Socks) as upstream, resource_context as resource,
          system_hosts(family, host) as fallback):
        destination.received = []
        destination.accepted = 0
        dns.answer_kind = 28 if family == "ipv6" else 1
        mapped_address = "127.0.0.1" if family == "ipv6" else "::1"
        mapped_destination = Server((mapped_address, destination.server_address[1]), Destination)
        mapped_destination.received = []
        mapped_destination.accepted = 0
        upstream.destination_hosts = fallback + names + block_names(family) + [mapped]
        upstream.destination = destination.server_address[1]
        upstream.auth = upstream.connects = 0
        upstream.reject = False
        servers = [destination, mapped_destination, dns, upstream]
        if resource is not None:
            resource.requests = resource.successes = 0
            resource.resources = {f"/{asset}.srs": (root / f"{asset}.srs").read_bytes()
                                  for asset in ("test", "block")}
            servers.append(resource)
        threads = [threading.Thread(target=server.serve_forever, kwargs=dict(poll_interval=0.05),
                                    daemon=True) for server in servers]
        for thread in threads:
            thread.start()
        try:
            local = port(host)
            config = runtime(root, core, family, host, local, dns, upstream, resource)
            path = root / f"{core}.{family}.runtime.json"
            write_config(path, config)
            binary = f"/routing-cores/{core}"
            validate = [binary, "run", "-test", "-c"] if core == "xray" else [binary, "check", "-c"]
            least = ["setpriv", "--reuid=10001", "--regid=10001", "--clear-groups",
                     "--bounding-set=-all", "--no-new-privs"]
            subprocess.run(least + validate + [str(path)], check=True, stdout=subprocess.DEVNULL,
                           env=dict(os.environ, XRAY_LOCATION_ASSET=str(root)))
            with running([binary, "run", "-c"], path, host, local,
                         root / f"{core}.{family}.dns.log") as process:
                for name in names:
                    before = len(dns.requests)
                    assert request(host, local, destination.server_address[1], name), name
                    assert name in dns.requests[before:], f"{name}: 没有触达指定 UDP DNS"
                before = len(dns.requests)
                accepted = mapped_destination.accepted
                assert request(host, local, destination.server_address[1], mapped)
                assert mapped_destination.accepted == accepted + 1, "hosts 没有解析到覆盖地址"
                assert len(dns.requests) == before, "hosts 与 DNS 同域名时仍发出 DNS query"
                assert request(host, local, destination.server_address[1], fallback[0])
                assert len(dns.requests) == before, "未匹配域名误走专用 DNS"
                accepted, covered = destination.accepted, mapped_destination.accepted
                assert request(host, local, destination.server_address[1], host, mapped)
                assert destination.accepted == accepted + 1 and mapped_destination.accepted == covered, (
                    "IP 目的被 sniff-only hosts 覆盖地址替换")
                assert request(host, local, destination.server_address[1], host, names[1])
                assert len(dns.requests) == before, "IP 目的被 sniff-only hosts/DNS 替换"
                connects = upstream.connects
                assert request(host, local, destination.server_address[1], fallback[1])
                assert upstream.connects == connects + 1, "SOCKS5 与 DNS/hosts 重叠时没有交给上游"
                assert len(dns.requests) == before, "SOCKS5 目的在本地 DNS 解析"
                for name in fallback[2:3] + (fallback[3:] if family == "ipv4" else []):
                    before = len(dns.requests)
                    accepted = destination.accepted
                    result = "eof"
                    try:
                        result = request(host, local, destination.server_address[1], name, timeout=20)
                        if result:
                            print(json.dumps(dict(
                                negative=name, connected=result, dns_queries=dns.requests[before:],
                                accepted_before=accepted, accepted_after=destination.accepted,
                                dns=config["dns"],
                                direct=[item for item in config["outbounds"] if item["tag"] == "direct"],
                            )), flush=True)
                        assert not result, (
                            f"{name}: DNS 失败回退系统解析")
                    except EOFError:
                        pass
                    except socket.timeout:
                        raise AssertionError(f"{name}: 没有等到核心返回失败，负测证据不足")
                    assert name in dns.requests[before:], f"{name}: 负测没有触达 DNS fixture"
                    assert destination.accepted == accepted, f"{name}: DNS 失败直连泄漏"
                    assert process.poll() is None, "DNS 失败导致核心退出"
                    print(f"routing-dns-negative-{core}-{family}: {name} result={result} "
                          f"queries={len(dns.requests) - before} destination_delta=0", flush=True)
                assert request(host, local, destination.server_address[1], mapped)
            if family == "ipv4":
                # 两个组合分支复用服务，只启动真实生成模板，不重跑双栈负测矩阵。
                with (socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as datagram,
                      socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as mapped_datagram):
                    datagram.bind((host, 0))
                    mapped_datagram.bind((mapped_address, datagram.getsockname()[1]))
                    for channel in (datagram, mapped_datagram):
                        channel.settimeout(0.3)
                    for mode in ("global", "resolve"):
                        config = runtime(root, core, family, host, local, dns, upstream, resource, mode)
                        path = root / f"{core}.{family}.{mode}.runtime.json"
                        write_config(path, config)
                        subprocess.run(least + validate + [str(path)], check=True,
                                       stdout=subprocess.DEVNULL,
                                       env=dict(os.environ, XRAY_LOCATION_ASSET=str(root)))
                        with running([binary, "run", "-c"], path, host, local,
                                     root / f"{core}.{family}.{mode}.dns.log"):
                            before, connects = len(dns.requests), upstream.connects
                            if mode == "global":
                                for target in fallback[1:3]:
                                    assert request(host, local, destination.server_address[1], target)
                                assert upstream.connects == connects + 2, (
                                    "全局 SOCKS5 被 DNS/hosts 解析覆盖")
                                auth = upstream.auth
                                helpers["udp"](host, local, datagram.getsockname()[1], names[1])
                                with contextlib.suppress(socket.timeout):
                                    raise AssertionError(f"全局 SOCKS5 UDP 泄漏: {datagram.recv(4096)!r}")
                                assert len(dns.requests) == before, "全局 SOCKS5 UDP 触发本地 DNS"
                                assert upstream.auth == auth, "全局被阻断 UDP 连接了 SOCKS5 上游"
                            else:
                                for target, channel in ((fallback[0], datagram), (names[1], datagram),
                                                        (mapped, mapped_datagram)):
                                    helpers["udp"](host, local, datagram.getsockname()[1], target)
                                    assert channel.recv(4096) == b"udp-leak", (
                                        f"DNS/hosts-only UDP 没有直达对应目的: {target}")
                                assert names[1] in dns.requests[before:], "UDP 未触达指定 DNS"
                            assert upstream.connects == connects + (2 if mode == "global" else 0)
                        print(f"routing-dns-hosts-real-{core}-{family}-{mode}: "
                              "generated-priority/UDP checks passed", flush=True)
            print(f"routing-dns-hosts-real-{core}-{family}: DNS/hosts/SOCKS5/no-fallback checks passed",
                  flush=True)
            with (socket.socket(socket.AF_INET6 if family == "ipv6" else socket.AF_INET,
                                socket.SOCK_DGRAM) as datagram,
                  socket.socket(socket.AF_INET if family == "ipv6" else socket.AF_INET6,
                                socket.SOCK_DGRAM) as mapped_datagram):
                datagram.bind((host, 0))
                datagram.settimeout(0.3)
                mapped_datagram.bind((mapped_address, datagram.getsockname()[1]))
                mapped_datagram.settimeout(0.3)
                blocked = block_names(family)
                modes = ["policy-control", "policy"]
                if family == "ipv4":
                    modes.append("policy-global")
                for mode in modes:
                    config = runtime(root, core, family, host, local, dns, upstream, resource, mode)
                    path = root / f"{core}.{family}.{mode}.runtime.json"
                    write_config(path, config)
                    subprocess.run(least + validate + [str(path)], check=True,
                                   stdout=subprocess.DEVNULL,
                                   env=dict(os.environ, XRAY_LOCATION_ASSET=str(root)))
                    with running([binary, "run", "-c"], path, host, local,
                                 root / f"{core}.{family}.{mode}.dns.log") as process:
                        if mode == "policy-control":
                            # 相同目的先以无策略模板证明 TCP/UDP 可达，之后才接受阻断证据。
                            for name in blocked:
                                assert request(host, local, destination.server_address[1], name), (
                                    f"Block TCP 对照不可达: {name}")
                            helpers["udp"](host, local, datagram.getsockname()[1], blocked[0])
                            assert datagram.recv(4096) == b"udp-leak", "Block UDP 对照不可达"
                            continue
                        for name in names:
                            before, auth, connects = len(dns.requests), upstream.auth, upstream.connects
                            accepted = destination.accepted
                            assert request(host, local, destination.server_address[1], name), name
                            assert destination.accepted == accepted + 1, "Direct 没有到达直连目的"
                            assert upstream.auth == auth and upstream.connects == connects, (
                                "Direct 被 SOCKS5 规则覆盖")
                            assert name in dns.requests[before:], "Direct 没有保留指定 DNS"
                        for name in (mapped, fallback[1]):
                            before, auth, connects = len(dns.requests), upstream.auth, upstream.connects
                            accepted = mapped_destination.accepted
                            assert request(host, local, destination.server_address[1], name), name
                            assert mapped_destination.accepted == accepted + 1, "Direct 没有保留 hosts"
                            assert len(dns.requests) == before and upstream.auth == auth and (
                                upstream.connects == connects)
                        auth = upstream.auth
                        helpers["udp"](host, local, datagram.getsockname()[1], names[1])
                        assert datagram.recv(4096) == b"udp-leak", (
                            "Direct UDP 被重叠 Block/SOCKS5 阻断")
                        assert upstream.auth == auth, "Direct UDP 连接了 SOCKS5 上游"
                        if mode == "policy-global":
                            before, auth, connects = len(dns.requests), upstream.auth, upstream.connects
                            helpers["udp"](host, local, datagram.getsockname()[1], mapped)
                            assert mapped_datagram.recv(4096) == b"udp-leak", (
                                "Direct hosts UDP 被全局 SOCKS5 阻断或覆盖地址未生效")
                            assert before == len(dns.requests) and auth == upstream.auth and (
                                connects == upstream.connects), "Direct hosts UDP 解析或代理泄漏"
                        accepted, covered = destination.accepted, mapped_destination.accepted
                        assert request(host, local, destination.server_address[1], host, mapped)
                        assert destination.accepted == accepted + 1 and mapped_destination.accepted == covered, (
                            "Direct sniff-only 覆写 IP 目的")
                        for name in blocked:
                            before = (destination.accepted, mapped_destination.accepted,
                                      len(dns.requests), upstream.auth, upstream.connects)
                            try:
                                assert not request(host, local, destination.server_address[1], name), (
                                    f"Block 没有拒绝 TCP: {name}")
                            except EOFError:
                                pass
                            except socket.timeout:
                                raise AssertionError(f"Block TCP 未实际拒绝，仅客户端超时: {name}")
                            assert before == (destination.accepted, mapped_destination.accepted,
                                              len(dns.requests), upstream.auth, upstream.connects), (
                                f"Block 在拒绝前解析、代理或直达目的: {name}")
                            assert process.poll() is None, "Block 导致核心退出"
                        before = (len(dns.requests), upstream.auth, upstream.connects)
                        helpers["udp"](host, local, datagram.getsockname()[1], blocked[0])
                        datagram.settimeout(1.25)
                        with contextlib.suppress(socket.timeout):
                            raise AssertionError(f"Block UDP 泄漏: {datagram.recv(4096)!r}")
                        assert before == (len(dns.requests), upstream.auth, upstream.connects)
                        assert request(host, local, destination.server_address[1], fallback[0]), (
                            "Block 影响了未匹配正向请求")
                    print(f"routing-direct-block-real-{core}-{family}-{mode}: "
                          "four-matchers/priority/reject/no-leak checks passed", flush=True)
        finally:
            for server in servers:
                server.shutdown()
            mapped_destination.server_close()
            for thread in threads:
                thread.join(timeout=2)


if __name__ == "__main__":
    root = Path(sys.argv[1])
    root.chmod(0o755)
    fixture_assets(root)
    policy_assets(root)
    for family, host in (("ipv4", "127.0.0.1"), ("ipv6", "::1")):
        for core in ("xray", "sing-box"):
            check(root, core, family, host)
