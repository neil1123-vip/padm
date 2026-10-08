import contextlib
import copy
import json
import os
from pathlib import Path
import select
import socket
import socketserver
import struct
import subprocess
import sys
import threading
import time


def exact(stream, size):
    data = b""
    while len(data) < size:
        part = stream.recv(size - len(data))
        if not part:
            raise EOFError
        data += part
    return data


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, address, handler):
        self.address_family = socket.AF_INET6 if ":" in address[0] else socket.AF_INET
        super().__init__(address, handler)


class Destination(socketserver.BaseRequestHandler):
    def handle(self):
        self.server.accepted += 1
        self.request.settimeout(2)
        data = self.request.recv(4096)
        if data.startswith(b"GET /routing-check "):
            self.server.received.append(data)
            body = b"routing-destination-ok"
            self.request.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: " +
                                 str(len(body)).encode() + b"\r\nConnection: close\r\n\r\n" + body)


class Socks(socketserver.BaseRequestHandler):
    def handle(self):
        conn = self.request
        conn.settimeout(2)
        try:
            version, count = exact(conn, 2)
            assert version == 5 and 2 in exact(conn, count)
            conn.sendall(b"\x05\x02")
            assert exact(conn, 1) == b"\x01"
            user = exact(conn, exact(conn, 1)[0])
            password = exact(conn, exact(conn, 1)[0])
            assert user == b"fixture-user" and password == b"fixture-password"
            self.server.auth += 1
            if self.server.reject:
                conn.sendall(b"\x01\x01")
                return
            conn.sendall(b"\x01\x00")
            version, command, reserved, kind = exact(conn, 4)
            assert (version, command, reserved) == (5, 1, 0)
            if kind == 1:
                host = socket.inet_ntop(socket.AF_INET, exact(conn, 4))
            elif kind == 4:
                host = socket.inet_ntop(socket.AF_INET6, exact(conn, 16))
            else:
                assert kind == 3
                host = exact(conn, exact(conn, 1)[0]).decode("ascii")
            port = struct.unpack("!H", exact(conn, 2))[0]
            assert host in self.server.destination_hosts and port == self.server.destination
            self.server.connects += 1
            with socket.create_connection((host, port), timeout=2) as target:
                conn.sendall(b"\x05\x00\x00" + socks_address(host) + b"\x00\x00")
                while True:
                    ready, _, _ = select.select([conn, target], [], [], 2)
                    if not ready:
                        return
                    for source in ready:
                        data = source.recv(65536)
                        if not data:
                            return
                        (target if source is conn else conn).sendall(data)
        except (EOFError, OSError):
            return


def socks_address(host):
    try:
        family = socket.AF_INET6 if ":" in host else socket.AF_INET
        return bytes([4 if family == socket.AF_INET6 else 1]) + socket.inet_pton(family, host)
    except OSError:
        name = host.encode("ascii")
        return b"\x03" + bytes([len(name)]) + name


def port(host):
    with socket.socket(socket.AF_INET6 if ":" in host else socket.AF_INET) as conn:
        conn.bind((host, 0))
        return conn.getsockname()[1]


def connect(host, address, destination, http_host="fixture", destination_host=None):
    with socket.create_connection((host, address), timeout=2) as conn:
        conn.sendall(b"\x05\x01\x00")
        assert exact(conn, 2) == b"\x05\x00"
        conn.sendall(b"\x05\x01\x00" + socks_address(destination_host or host) +
                     struct.pack("!H", destination))
        header = exact(conn, 4)
        if header[1] != 0:
            return False
        assert header[0] == 5 and header[2] == 0
        exact(conn, {1: 4, 4: 16}[header[3]] + 2)
        conn.sendall(b"GET /routing-check HTTP/1.1\r\nHost: " + http_host.encode("ascii") +
                     b"\r\nConnection: close\r\n\r\n")
        result = b""
        while part := conn.recv(4096):
            result += part
        return result.endswith(b"routing-destination-ok")


def udp(host, address, destination, destination_host=None):
    with socket.create_connection((host, address), timeout=2) as control:
        control.sendall(b"\x05\x01\x00")
        assert exact(control, 2) == b"\x05\x00"
        control.sendall(b"\x05\x03\x00" +
                        socks_address("::" if ":" in host else "0.0.0.0") + b"\x00\x00")
        header = exact(control, 4)
        assert header[1] == 0, "测试入站必须成功建立 UDP 中继"
        relay_host = socket.inet_ntop({1: socket.AF_INET, 4: socket.AF_INET6}[header[3]],
                                    exact(control, {1: 4, 4: 16}[header[3]]))
        relay = struct.unpack("!H", exact(control, 2))[0]
        assert relay != 0, "UDP 中继端口无效"
        if relay_host in ("0.0.0.0", "::"):
            relay_host = host
        with socket.socket(socket.AF_INET6 if ":" in relay_host else socket.AF_INET,
                           socket.SOCK_DGRAM) as conn:
            packet = (b"\x00\x00\x00" + socks_address(destination_host or host) +
                      struct.pack("!H", destination) + b"udp-leak")
            conn.sendto(packet, (relay_host, relay))
            conn.settimeout(0.2)
            with contextlib.suppress(socket.timeout):
                assert not conn.recv(4096), "UDP 被意外转发"


@contextlib.contextmanager
def running(command, path, host, local, logfile):
    least = ["setpriv", "--reuid=10001", "--regid=10001", "--clear-groups",
             "--bounding-set=-all", "--no-new-privs"]
    with logfile.open("wb") as log:
        process = subprocess.Popen(least + command + [str(path)], stdout=log, stderr=log,
                                   env=dict(os.environ, XRAY_LOCATION_ASSET=str(path.parent)))
        try:
            deadline = time.monotonic() + 4
            while True:
                assert process.poll() is None, logfile.read_text()
                try:
                    with socket.create_connection((host, local), timeout=0.1):
                        break
                except OSError:
                    assert time.monotonic() < deadline, "核心监听超时"
                    time.sleep(0.05)
            yield process
        finally:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def domain_names(family):
    suffix = "v6" if family == "ipv6" else "v4"
    return [f"only-keyword-{suffix}.padm.invalid", f"full-{suffix}.padm.invalid",
            f"sub.suffix-{suffix}.padm.invalid", f"geo-{suffix}.padm.invalid"]


@contextlib.contextmanager
def fixture_hosts():
    marker = f"# padm-routing-{os.getpid()}"
    lines = [f"{host} {' '.join(domain_names(family) + [f'unmatched-{family}.padm.invalid'])} {marker}\n"
             for family, host in (("ipv4", "127.0.0.1"), ("ipv6", "::1"))]
    hosts = Path("/etc/hosts")
    # 只追加隔离容器本轮的精确映射；退出时保留其它任务写入的内容。
    with hosts.open("a", encoding="utf-8") as target:
        target.write("\n" + "".join(lines))
    try:
        yield
    finally:
        with hosts.open("r+", encoding="utf-8") as target:
            retained = [line for line in target.readlines() if line not in lines]
            target.seek(0)
            target.writelines(retained)
            target.truncate()


def fixture_assets(root):
    names = [domain_names(family)[3] for family in ("ipv4", "ipv6")]
    # 单一 TEST GeoSite 的 protobuf：Domain.full=3，由真实 Xray 解析，不代替官方数据验收。
    entries = []
    for name in names:
        value = name.encode("ascii")
        domain = b"\x08\x03\x12" + bytes([len(value)]) + value
        entries.append(b"\x12" + bytes([len(domain)]) + domain)
    site = b"\x0a\x04TEST" + b"".join(entries)
    assert len(site) < 128
    (root / "geosite.dat").write_bytes(b"\x0a" + bytes([len(site)]) + site)
    source = root / "test-rule-set.json"
    source.write_text(json.dumps(dict(version=3, rules=[dict(domain=names)])))
    subprocess.run(["/routing-cores/sing-box", "rule-set", "compile", "--output",
                    str(root / "test.srs"), str(source)], check=True, stdout=subprocess.DEVNULL)
    (root / "geosite.dat").chmod(0o644)
    (root / "test.srs").chmod(0o644)


def write_config(path, config):
    path.write_text(json.dumps(config))
    path.chmod(0o644)


def runtime_config(root, core, mode, host, local, upstream, resource):
    config = json.loads((root / f"{core}.{mode}.json").read_text())
    outbound = next(item for item in config["outbounds"] if item["tag"] == "padm-socks5")
    if core == "xray":
        assert config["routing"]["rules"][0]["outboundTag"] == "padm-traffic-api"
        assert config["outbounds"][0]["tag"] == ("direct" if mode == "selective" else "padm-socks5")
        outbound["settings"]["servers"][0].update(address=host, port=upstream.server_address[1])
        sniffing = copy.deepcopy(next(item["sniffing"] for item in config["inbounds"]
                                      if item["tag"] != "padm-traffic-api"))
        assert sniffing["enabled"] and sniffing["routeOnly"]
        config["inbounds"].append(dict(listen=host, port=local, tag="fixture-in",
                                      protocol="socks", settings=dict(auth="noauth", udp=True),
                                      sniffing=sniffing))
        if mode == "global":
            assert config["routing"]["rules"][1] == dict(type="field", network="udp", outboundTag="blocked")
    else:
        assert config["route"]["final"] == ("direct" if mode == "selective" else "padm-socks5")
        outbound.update(server=host, server_port=upstream.server_address[1])
        config["inbounds"].append(dict(type="socks", tag="fixture-in", listen=host, listen_port=local))
        if mode == "global":
            assert config["route"]["rules"] == [dict(network="udp", action="reject")]
        else:
            assert config["route"]["rules"][0]["action"] == "sniff"
            for item in config["route"]["rule_set"]:
                assert item["url"] == "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-test.srs"
                assert item["type"] == "remote" and item["format"] == "binary"
                assert item["http_client"] == {"engine": "go"} and "download_detour" not in item
                # 保留生成器的 remote 结构；仅将资源 URL 换成隔离回环 HTTP。
                item["url"] = f"http://127.0.0.1:{resource.server_address[1]}/test.srs"
    return config


def failed_start(command, path, logfile, asset_root, expected_resource, expected_error):
    least = ["setpriv", "--reuid=10001", "--regid=10001", "--clear-groups",
             "--bounding-set=-all", "--no-new-privs"]
    with logfile.open("wb") as log:
        process = subprocess.Popen(least + command + [str(path)], stdout=log, stderr=log,
                                   env=dict(os.environ, XRAY_LOCATION_ASSET=str(asset_root)))
        try:
            assert process.wait(timeout=5) != 0, "缺失路由资源被静默当作直连"
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    output = logfile.read_text(errors="replace")
    print(f"routing-resource-negative-{logfile.stem}:\n{output}", file=sys.stderr, flush=True)
    assert "implicit default http client" not in output.lower(), output
    assert expected_resource in output and expected_error in output.lower(), (
        f"核心失败原因与资源负测不符: {expected_resource}/{expected_error}\n{output}")


class RuleResource(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(2)
        request = self.request.recv(4096)
        self.server.requests += 1
        if request.startswith(b"GET /test.srs "):
            body = self.server.body
            self.server.successes += 1
            status = b"200 OK"
        else:
            body = b""
            status = b"404 Not Found"
        self.request.sendall(b"HTTP/1.1 " + status + b"\r\nContent-Length: " +
                             str(len(body)).encode() + b"\r\nConnection: close\r\n\r\n" + body)


def missing_assets(root, core, config, command, destination):
    missing = copy.deepcopy(config)
    path = root / f"{core}.missing.json"
    absent = root / "absent-assets"
    absent.mkdir(exist_ok=True)
    absent.chmod(0o755)
    if core == "sing-box":
        item = missing["route"]["rule_set"][0]
        item.clear()
        item.update(type="local", tag="padm-geosite-test", format="binary",
                    path=str(absent / "test.srs"))
    write_config(path, missing)
    accepted = destination.accepted
    failed_start(command, path, root / f"{core}.missing.log", absent,
                 "geosite.dat" if core == "xray" else "test.srs", "no such file")
    assert destination.accepted == accepted
    if core == "sing-box":
        with Server(("127.0.0.1", 0), RuleResource) as server:
            server.requests = 0
            thread = threading.Thread(target=server.serve_forever, kwargs=dict(poll_interval=0.05),
                                      daemon=True)
            thread.start()
            try:
                remote = copy.deepcopy(config)
                item = remote["route"]["rule_set"][0]
                item["url"] = f"http://127.0.0.1:{server.server_address[1]}/missing.srs"
                write_config(path, remote)
                failed_start(command, path, root / f"{core}.404.log", root, "rule-set", "404")
                assert server.requests > 0, "远程资源负测没有触达 HTTP 404"
                assert destination.accepted == accepted
            finally:
                server.shutdown()
                thread.join(timeout=2)


def check_mode(root, core, family, host, mode):
    names = domain_names(family)
    unmatched = f"unmatched-{family}.padm.invalid"
    resource_context = (Server(("127.0.0.1", 0), RuleResource)
                        if core == "sing-box" and mode == "selective" else contextlib.nullcontext(None))
    with (Server((host, 0), Destination) as destination, Server((host, 0), Socks) as upstream,
          resource_context as resource):
        destination.received = []
        destination.accepted = 0
        upstream.destination_hosts = [host] + names + [unmatched]
        upstream.destination = destination.server_address[1]
        upstream.auth = upstream.connects = 0
        upstream.reject = False
        servers = [destination, upstream]
        if resource is not None:
            resource.requests = resource.successes = 0
            resource.body = (root / "test.srs").read_bytes()
            servers.append(resource)
        threads = [threading.Thread(target=server.serve_forever, kwargs=dict(poll_interval=0.05),
                                    daemon=True)
                   for server in servers]
        for thread in threads:
            thread.start()
        try:
            with socket.socket(socket.AF_INET6 if family == "ipv6" else socket.AF_INET,
                               socket.SOCK_DGRAM) as datagram:
                datagram.bind((host, 0))
                # selective sniff 最长 1 秒，漏包观察必须晚于该动作的超时。
                datagram.settimeout(1.25 if mode == "selective" else 0.25)
                local = port(host)
                config = runtime_config(root, core, mode, host, local, upstream, resource)
                command = [f"/routing-cores/{core}", "run", "-c"]
                validate = ([f"/routing-cores/{core}", "run", "-test", "-c"] if core == "xray"
                            else [f"/routing-cores/{core}", "check", "-c"])
                path = root / f"{core}.{family}.{mode}.runtime.json"
                write_config(path, config)
                least = ["setpriv", "--reuid=10001", "--regid=10001", "--clear-groups",
                         "--bounding-set=-all", "--no-new-privs"]
                subprocess.run(least + validate + [str(path)], check=True, stdout=subprocess.DEVNULL,
                               env=dict(os.environ, XRAY_LOCATION_ASSET=str(root)))
                if mode == "global":
                    # 复用一个直连对照进程证明字面 IP 和所有域名 UDP 都能抵达。
                    direct = copy.deepcopy(config)
                    direct["outbounds"] = [item for item in direct["outbounds"] if item["tag"] != "padm-socks5"]
                    if core == "xray":
                        direct["routing"]["rules"] = direct["routing"]["rules"][:1]
                    else:
                        direct["route"].update(final="direct", rules=[])
                    control = root / f"{core}.{family}.direct.json"
                    write_config(control, direct)
                    with running(command, control, host, local, root / f"{core}.{family}.direct.log"):
                        for target in [host] + names + [unmatched]:
                            udp(host, local, datagram.getsockname()[1], target)
                            assert datagram.recv(4096) == b"udp-leak", f"UDP 正向对照没有到达: {target}"
                elif family == "ipv4":
                    missing_assets(root, core, config, command, destination)
                with running(command, path, host, local, root / f"{core}.{family}.{mode}.log") as process:
                    if resource is not None:
                        assert resource.successes > 0, "remote 规则集未下载真实二进制资源"
                        assert upstream.auth == 0, "remote 规则集下载不得经过 SOCKS5"
                    targets = names if mode == "selective" else ["fixture"]
                    for target in targets:
                        received, connects = len(destination.received), upstream.connects
                        assert connect(host, local, upstream.destination, target), f"TCP 匹配失败: {target}"
                        assert upstream.connects == connects + 1, f"匹配 TCP 未走认证 SOCKS5: {target}"
                        assert len(destination.received) == received + 1
                    if mode == "selective":
                        connects = upstream.connects
                        assert connect(host, local, upstream.destination, unmatched)
                        assert upstream.connects == connects, "未匹配 TCP 不应走 SOCKS5"
                        # 同时验证 SOCKS ATYP3 域名与 IP 目的的 HTTP Host sniff。
                        assert connect(host, local, upstream.destination, names[1], names[1])
                        assert upstream.connects == connects + 1
                    accepted, received, auth = destination.accepted, len(destination.received), upstream.auth
                    upstream.reject = True
                    target = names[1] if mode == "selective" else "fixture"
                    for _ in range(2):
                        try:
                            assert not connect(host, local, upstream.destination, target), "认证失败回退直连"
                        except (OSError, EOFError):
                            pass
                    time.sleep(0.05)
                    assert upstream.auth == auth + 2, "认证失败用例没有触达真实上游"
                    assert len(destination.received) == received and destination.accepted == accepted
                    upstream.reject = False
                    assert connect(host, local, upstream.destination, target)
                    auth = upstream.auth
                    for target in names if mode == "selective" else [host]:
                        udp(host, local, datagram.getsockname()[1], target)
                        with contextlib.suppress(socket.timeout):
                            raise AssertionError(f"匹配 UDP 直连泄漏: {datagram.recv(4096)!r}")
                    assert upstream.auth == auth, "被阻断的 UDP 不应连接 SOCKS5 上游"
                    if mode == "selective":
                        udp(host, local, datagram.getsockname()[1], unmatched)
                        assert datagram.recv(4096) == b"udp-leak", "未匹配 UDP 未直达"
                        assert upstream.auth == auth
                    accepted, received = destination.accepted, len(destination.received)
                    # 停止接受而非延迟响应，验证真实上游连接失败不回退。
                    upstream.shutdown()
                    upstream.server_close()
                    try:
                        target = names[1] if mode == "selective" else "fixture"
                        assert not connect(host, local, destination.server_address[1], target), "上游断开回退直连"
                    except (OSError, EOFError):
                        pass
                    time.sleep(0.05)
                    assert process.poll() is None, "上游断开后核心意外退出"
                    assert len(destination.received) == received and destination.accepted == accepted
                    if mode == "selective":
                        assert connect(host, local, destination.server_address[1], unmatched)
                        udp(host, local, datagram.getsockname()[1], unmatched)
                        assert datagram.recv(4096) == b"udp-leak", "上游停机影响了未匹配 UDP"
                print(f"routing-socks5-real-{core}-{family}-{mode}: CONNECT/auth/UDP/upstream checks passed",
                      flush=True)
        finally:
            for server in servers:
                server.shutdown()
            for thread in threads:
                thread.join(timeout=2)


root = Path(sys.argv[1])
os.chmod(root, 0o755)
fixture_assets(root)
with fixture_hosts():
    for family, host in (("ipv4", "127.0.0.1"), ("ipv6", "::1")):
        for core in ("xray", "sing-box"):
            for mode in ("global", "selective"):
                check_mode(root, core, family, host, mode)
