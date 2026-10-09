#!/usr/bin/env python3
import contextlib
import copy
import json
import os
from pathlib import Path
import runpy
import selectors
import signal
import socket
import socketserver
import struct
import subprocess
import sys
import threading
import time


ROOT = Path(__file__).resolve().parents[2]
helpers = runpy.run_path(str(Path(__file__).with_name("routing-dns-hosts-real.py")))
node = runpy.run_path(str(Path(__file__).with_name("control-two-node-real.py")))
Server, exact, request = (helpers[key] for key in ("Server", "exact", "request"))
run, namespace, stop = (node[key] for key in ("run", "namespace", "stop"))
BT = helpers["BT_HANDSHAKE"]
ORIGIN4, ORIGIN6 = "198.51.100.80", "2001:db8:80::80"
UDP4 = "198.51.100.81"
LOCAL, HTTP, UDP = 2080, 8088, 8089
DIRECT4, DIRECT6 = "192.0.2.1", "fd02::1"
TUNNEL4, TUNNEL6 = "172.16.0.2", "2606:4700:110:8a10::2"
HTTP_RESPONSE = (b"HTTP/1.1 200 OK\r\nContent-Length: 22\r\nConnection: close\r\n\r\n"
                 b"routing-destination-ok")
PROOF, LOCK = None, threading.Lock()


def event(kind, **values):
    with LOCK, (PROOF / "events.jsonl").open("a") as output:
        output.write(json.dumps(dict(kind=kind, monotonic_ms=time.monotonic_ns() // 1000000,
                                     **values)) + "\n")


class Origin(socketserver.BaseRequestHandler):
    def handle(self):
        event("tcp", source=self.client_address[0], destination=self.server.server_address[0])
        conn = self.request
        conn.settimeout(3)
        body = exact(conn, 1)
        if body == BT[:1]:
            body += exact(conn, len(BT) - 1)
            conn.sendall(BT)
        else:
            while b"\r\n\r\n" not in body:
                body += exact(conn, 1)
            assert body.startswith(b"GET /routing-check ")
            conn.sendall(HTTP_RESPONSE)


class Datagram(socketserver.BaseRequestHandler):
    def handle(self):
        body, channel = self.request
        event("udp", source=self.client_address[0], destination=self.server.server_address[0],
              size=len(body))
        channel.sendto(body, self.client_address)


class UdpServer(socketserver.ThreadingUDPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, handler):
        self.address_family = socket.AF_INET6 if ":" in address[0] else socket.AF_INET
        super().__init__(address, handler)


class Dns(socketserver.BaseRequestHandler):
    def handle(self):
        data, channel = self.request
        offset, parts = 12, []
        while size := data[offset]:
            offset += 1
            parts.append(data[offset:offset + size].decode("ascii"))
            offset += size
        end = offset + 5
        name, kind = ".".join(parts), struct.unpack("!HH", data[offset + 1:end])[0]
        event("dns", name=name, qtype=kind, server_port=self.server.server_address[1])
        family = int((PROOF / "family").read_text())
        if name in ("direct.warp.invalid", "unmatched.test", "proxy.test"):
            family = 4
        if name == "ipv6-first.warp.invalid":
            family = 6
        if name == "dual.warp.invalid":
            family = 4 if kind == 1 else 6
        value = socket.inet_pton(socket.AF_INET if family == 4 else socket.AF_INET6,
                                ORIGIN4 if family == 4 else ORIGIN6)
        answer = (b"\xc0\x0c" + struct.pack("!HHIH", kind, 1, 1, len(value)) + value
                  if kind == (1 if family == 4 else 28) else b"")
        channel.sendto(data[:2] + struct.pack("!HHHHH", 0x8180, 1, int(bool(answer)), 0, 0) +
                       data[12:end] + answer, self.client_address)


class Proxy(socketserver.BaseRequestHandler):
    def handle(self):
        conn = self.request
        conn.settimeout(3)
        try:
            version, count = exact(conn, 2)
            assert version == 5 and 2 in exact(conn, count)
            conn.sendall(b"\x05\x02")
            assert exact(conn, 1) == b"\x01"
            user, password = exact(conn, exact(conn, 1)[0]), exact(conn, exact(conn, 1)[0])
            assert (user, password) == (b"fixture-user", b"fixture-password")
            conn.sendall(b"\x01\x00")
            assert exact(conn, 4) == b"\x05\x01\x00\x03"
            name = exact(conn, exact(conn, 1)[0]).decode("ascii")
            assert struct.unpack("!H", exact(conn, 2))[0] == HTTP
            event("proxy", name=name)
            with socket.create_connection((ORIGIN4, HTTP), timeout=3) as target:
                conn.sendall(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
                target.sendall(conn.recv(4096))
                while data := target.recv(4096):
                    conn.sendall(data)
        except (EOFError, ConnectionResetError):
            return


def relay(stopping):
    # 测试适配器记录真实 reserved，再清零送给标准内核 Peer；不冒充 Cloudflare 协议验收。
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as inbound, \
            socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as peer, selectors.DefaultSelector() as selected:
        inbound.bind(("192.0.2.2", 2408))
        peer.connect(("127.0.0.1", 51820))
        selected.register(inbound, selectors.EVENT_READ)
        selected.register(peer, selectors.EVENT_READ)
        client = None
        while not stopping.is_set():
            for ready, _ in selected.select(0.05):
                if ready.fileobj is inbound:
                    data, client = inbound.recvfrom(65535)
                    assert len(data) >= 4 and data[0] in (1, 2, 3, 4)
                    event("wireguard", direction="client-to-peer", packet_type=data[0],
                          reserved=list(data[1:4]), size=len(data))
                    if not (PROOF / "peer-off").exists():
                        peer.send(data[:1] + b"\x00\x00\x00" + data[4:])
                else:
                    data = peer.recv(65535)
                    event("wireguard", direction="peer-to-client", packet_type=data[0],
                          reserved=list(data[1:4]), size=len(data))
                    if client is not None:
                        inbound.sendto(data, client)


def fixture(path):
    global PROOF
    PROOF = Path(path)
    stopping = threading.Event()
    signal.signal(signal.SIGTERM, lambda _number, _frame: stopping.set())
    with contextlib.ExitStack() as stack:
        # 只在私有 Peer 网络空间用 root 绑定 DNS 53，处理任何请求前立即降权。
        local_dns = stack.enter_context(UdpServer(("192.0.2.2", 53), Dns))
        os.setgroups([])
        os.setgid(10001)
        os.setuid(10001)
        servers = []
        for address in (ORIGIN4, ORIGIN6):
            servers += [stack.enter_context(Server((address, HTTP), Origin)),
                        stack.enter_context(UdpServer((address, UDP), Datagram))]
        servers += [stack.enter_context(UdpServer(("192.0.2.2", 5353), Dns)),
                    stack.enter_context(UdpServer((UDP4, UDP), Datagram)),
                    local_dns,
                    stack.enter_context(Server(("192.0.2.2", 1080), Proxy))]
        for server in servers:
            threading.Thread(target=server.serve_forever, kwargs=dict(poll_interval=0.05),
                             daemon=True).start()
        threading.Thread(target=relay, args=(stopping,), daemon=True).start()
        (PROOF / "ready").touch()
        stopping.wait()


def rows(path):
    return [json.loads(line) for line in (path / "events.jsonl").read_text().splitlines()]


def wait(probe, timeout=10):
    deadline = time.monotonic() + timeout
    while True:
        try:
            if probe():
                return
        except (OSError, AssertionError):
            pass
        assert time.monotonic() < deadline, "隔离服务就绪超时"
        time.sleep(0.02)


def listener():
    with socket.create_connection(("127.0.0.1", LOCAL), timeout=0.2):
        return True


def permissions(process):
    status = Path(f"/proc/{process.pid}/status").read_text()
    for line in ("Uid:\t10001\t10001\t10001\t10001", "Gid:\t10001\t10001\t10001\t10001",
                 "CapEff:\t0000000000000000", "CapPrm:\t0000000000000000",
                 "CapInh:\t0000000000000000", "CapAmb:\t0000000000000000"):
        assert line in status, "业务进程不是 10001:10001 零能力"


def links():
    return {item["ifname"] for item in json.loads(run(["ip", "-j", "link", "show"]))}


def accepted(target, path, source, core):
    before = len(rows(path))
    with socket.create_connection(("127.0.0.1", LOCAL), timeout=3) as conn:
        conn.sendall(b"\x05\x01\x00")
        assert exact(conn, 2) == b"\x05\x00"
        body = (b"GET /routing-check HTTP/1.1\r\nHost: " + target.encode("ascii") +
                b"\r\nConnection: close\r\n\r\n")
        conn.sendall(b"\x05\x01\x00" + helpers["socks_address"](target) + struct.pack("!H", HTTP) +
                     (body if core == "xray" else b""))
        header = exact(conn, 4)
        assert header[:3] == b"\x05\x00\x00"
        exact(conn, {1: 4, 4: 16}[header[3]] + 2)
        if core != "xray":
            conn.sendall(body)
        # 正例读完整固定响应即可；实际拒绝仍用原 request 等 EOF，不削弱阻断判定。
        assert exact(conn, len(HTTP_RESPONSE)) == HTTP_RESPONSE
    delta = rows(path)[before:]
    assert [row["source"] for row in delta if row["kind"] == "tcp"] == [source], (target, delta)
    return delta


def rejected(target, path, core, payload=None):
    before = len(rows(path))
    try:
        assert not request("127.0.0.1", LOCAL, HTTP, target, pipelined=core == "xray",
                           payload=payload), target
    except (EOFError, ConnectionResetError):
        pass
    except socket.timeout:
        raise AssertionError(f"{target}: 超时不是实际阻断")
    delta = rows(path)[before:]
    # 已有隧道的空 keepalive 与拒绝目标无关；有效载荷、握手及解析仍不可泄漏。
    assert not any(row["kind"] in ("tcp", "proxy", "dns") or
                   (row["kind"] == "wireguard" and
                    not (row["packet_type"] == 4 and row["size"] == 32))
                   for row in delta), delta


def udp(target):
    with socket.create_connection(("127.0.0.1", LOCAL), timeout=3) as control:
        control.sendall(b"\x05\x01\x00")
        assert exact(control, 2) == b"\x05\x00"
        control.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
        header = exact(control, 4)
        assert header[:2] == b"\x05\x00"
        address = socket.inet_ntop({1: socket.AF_INET, 4: socket.AF_INET6}[header[3]],
                                  exact(control, {1: 4, 4: 16}[header[3]]))
        port = struct.unpack("!H", exact(control, 2))[0]
        if address in ("0.0.0.0", "::"):
            address = "127.0.0.1"
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as channel:
            channel.settimeout(3)
            channel.sendto(b"\x00\x00\x00" + helpers["socks_address"](target) +
                           struct.pack("!H", UDP) + b"warp-udp-proof", (address, port))
            assert channel.recv(65535).endswith(b"warp-udp-proof")


def runtime(root, core, mode, private, public):
    value = json.loads((root / f"{core}.{mode}.json").read_text())
    address = ORIGIN6 if mode.endswith("6") else ORIGIN4
    if core == "xray":
        value["dns"]["hosts"]["full:hosts.warp.invalid"] = address
        for rule in value["routing"]["rules"]:
            if rule.get("ip") == ["198.51.100.199"]:
                rule["ip"] = [ORIGIN4]
        for outbound in value["outbounds"]:
            if outbound["tag"] == "padm-warp":
                outbound["settings"]["secretKey"] = private
                outbound["settings"]["peers"][0].update(publicKey=public, endpoint="192.0.2.2:2408")
                assert outbound["settings"]["noKernelTun"] is True
        if mode.startswith("selective"):
            value["routing"]["rules"].append(
                dict(type="field", ip=[UDP4, ORIGIN6], network="udp", outboundTag="padm-warp"))
        value["inbounds"].append(dict(protocol="socks", listen="127.0.0.1", port=LOCAL,
                                     tag="fixture-in", settings=dict(auth="noauth", udp=True),
                                     sniffing=copy.deepcopy(value["inbounds"][0]["sniffing"])))
    else:
        for server in value["dns"]["servers"]:
            if server["tag"] == "padm-hosts":
                server["predefined"]["hosts.warp.invalid"] = address
        for endpoint in value.get("endpoints", []):
            if endpoint["tag"] == "padm-warp":
                endpoint["private_key"] = private
                endpoint["peers"][0].update(public_key=public, address="192.0.2.2", port=2408)
                assert endpoint["system"] is False
        for rule in value["route"]["rules"]:
            for match in rule.get("rules", [rule]):
                if match.get("ip_cidr") == ["198.51.100.199"]:
                    match["ip_cidr"] = [ORIGIN4]
        if mode.startswith("selective"):
            value["route"]["rules"].append(
                dict(ip_cidr=[UDP4 + "/32", ORIGIN6 + "/128"], network="udp",
                     action="route", outbound="padm-warp"))
        value["inbounds"].append(dict(type="socks", tag="fixture-in", listen="127.0.0.1", listen_port=LOCAL))
    return value


def main(root):
    assert os.getuid() == 0 and sys.platform == "linux" and Path("/.dockerenv").is_file()
    assert links() == {"lo"}, "必须使用 network none，不操作已有网络"
    root.chmod(0o755)
    for path in (root / "events.jsonl", root / "family"):
        path.touch(mode=0o644)
        os.chown(path, 10001, 10001)
    os.chown(root, 10001, 10001)
    resolver = Path("/etc/resolv.conf")
    original_resolver = resolver.read_bytes()
    holder, server = None, None
    with (root / "fixture.log").open("wb") as fixture_log:
        try:
            holder = subprocess.Popen(["unshare", "--net", "--", sys.executable, "-c",
                                       "import time; time.sleep(3600)"], stderr=subprocess.PIPE)
            original_namespace = os.readlink("/proc/self/ns/net")
            wait(lambda: holder.poll() is None and os.readlink(f"/proc/{holder.pid}/ns/net") != original_namespace)
            peer = holder.pid
            run(["ip", "link", "add", "warp-client", "type", "veth", "peer", "name", "warp-peer"])
            run(["ip", "link", "set", "warp-peer", "netns", str(peer)])
            for pid, name, address4, address6 in ((None, "warp-client", DIRECT4, DIRECT6),
                                                (peer, "warp-peer", "192.0.2.2", "fd02::2")):
                run(["ip", "link", "set", "lo", "up"], pid)
                run(["ip", "address", "add", address4 + "/30", "dev", name], pid)
                run(["ip", "-6", "address", "add", address6 + "/64", "dev", name, "nodad"], pid)
                run(["ip", "link", "set", name, "up"], pid)
            run(["ip", "address", "add", ORIGIN4 + "/32", "dev", "lo"], peer)
            run(["ip", "address", "add", UDP4 + "/32", "dev", "lo"], peer)
            run(["ip", "-6", "address", "add", ORIGIN6 + "/128", "dev", "lo", "nodad"], peer)
            run(["ip", "route", "add", ORIGIN4 + "/32", "via", "192.0.2.2"])
            run(["ip", "route", "add", UDP4 + "/32", "via", "192.0.2.2"])
            run(["ip", "-6", "route", "add", ORIGIN6 + "/128", "via", "fd02::2"])
            # 默认接口仅指向私有 Peer，供 sing-box 自动探测；隔离空间没有公网出口。
            run(["ip", "route", "add", "default", "via", "192.0.2.2", "dev", "warp-client"])
            run(["ip", "-6", "route", "add", "default", "via", "fd02::2", "dev", "warp-client"])
            private, peer_private = run(["wg", "genkey"]), run(["wg", "genkey"])
            public, peer_public = (run(["wg", "pubkey"], content=value).decode().strip()
                                   for value in (private, peer_private))
            key = root / "peer.private"
            key.write_bytes(peer_private)
            key.chmod(0o600)
            run(["ip", "link", "add", "wg-padm", "type", "wireguard"], peer)
            run(["wg", "set", "wg-padm", "private-key", str(key), "listen-port", "51820",
                 "peer", public, "allowed-ips", TUNNEL4 + "/32," + TUNNEL6 + "/128"], peer)
            run(["ip", "link", "set", "wg-padm", "up"], peer)
            run(["ip", "route", "add", TUNNEL4 + "/32", "dev", "wg-padm"], peer)
            run(["ip", "-6", "route", "add", TUNNEL6 + "/128", "dev", "wg-padm"], peer)
            (root / "family").write_text("4")
            resolver.write_bytes(b"nameserver 192.0.2.2\noptions timeout:1 attempts:1\n")
            unprivileged = ["setpriv", "--reuid=10001", "--regid=10001", "--clear-groups",
                            "--bounding-set=-all", "--inh-caps=-all", "--ambient-caps=-all"]
            server = subprocess.Popen(namespace(peer) +
                                      [sys.executable, str(Path(__file__).resolve()), "fixture", str(root)],
                                      stdout=fixture_log, stderr=subprocess.STDOUT)
            wait(lambda: server.poll() is None and (root / "ready").is_file())
            permissions(server)
            expected_links = links()
            for core in ("xray", "sing-box"):
                for mode in ("control", "selective4", "selective6", "global4", "global6", "off"):
                    family = 6 if mode.endswith("6") else 4
                    (root / "family").write_text(str(family))
                    config = root / f"{core}.{mode}.runtime.json"
                    config.write_text(json.dumps(runtime(root, core, mode, private.decode().strip(), peer_public)))
                    config.chmod(0o640)
                    os.chown(config, 0, 10001)
                    validate = ["-test", "-config", str(config)] if core == "xray" else ["check", "-c", str(config)]
                    binary = f"/routing-cores/{core}"
                    run(unprivileged + [binary] + validate)
                    with (root / f"{core}.{mode}.log").open("wb") as output:
                        process = subprocess.Popen(unprivileged + [binary, "run", "-c", str(config)],
                                                   stdout=output, stderr=subprocess.STDOUT)
                        try:
                            wait(lambda: process.poll() is None and listener())
                            permissions(process)
                            assert links() == expected_links, "userspace 核心创建了宿主接口"
                            if mode in ("control", "off"):
                                delta = accepted("hosts.warp.invalid", root, DIRECT4, core)
                                assert not any(row["kind"] == "dns" for row in delta), delta
                                count = len(rows(root))
                                udp(UDP4)
                                assert [row["source"] for row in rows(root)[count:]
                                        if row["kind"] == "udp"] == [DIRECT4]
                            else:
                                target = ("default.warp.invalid" if mode.startswith("global")
                                          else "matched.warp.invalid")
                                before = rows(root)
                                source = TUNNEL4 if family == 4 else TUNNEL6
                                delta = accepted(target, root, source, core)
                                assert not any(row["kind"] == "proxy" for row in delta)
                                queries = [row for row in delta if row["kind"] == "dns"]
                                assert queries and all(row["server_port"] == 5353 for row in queries), delta
                                delta = accepted("dual.warp.invalid", root, source, core)
                                assert [row["destination"] for row in delta if row["kind"] == "tcp"] == [
                                    ORIGIN4 if family == 4 else ORIGIN6]
                                assert all(row["server_port"] == 5353 and
                                           row["qtype"] == (1 if family == 4 else 28)
                                           for row in delta if row["kind"] == "dns"), delta
                                delta = accepted("hosts.warp.invalid", root, source, core)
                                assert not any(row["kind"] == "dns" for row in delta), delta
                                accepted("ipv6-first.warp.invalid", root, DIRECT6, core)
                                accepted("direct.warp.invalid", root, DIRECT4, core)
                                rejected("blocked.warp.invalid", root, core)
                                rejected(ORIGIN4, root, core)
                                rejected(target, root, core, payload=BT)
                                delta = accepted("proxy.test", root, ORIGIN4, core)
                                assert [row["name"] for row in delta if row["kind"] == "proxy"] == ["proxy.test"]
                                if mode.startswith("global"):
                                    delta = accepted("matched.warp.invalid", root, ORIGIN4, core)
                                    assert any(row["kind"] == "proxy" for row in delta)
                                for udp_target in (UDP4 if family == 4 else ORIGIN6, target,
                                                   "dual.warp.invalid"):
                                    print(f"routing-warp-{core}-{mode}: UDP {udp_target}", flush=True)
                                    count = len(rows(root))
                                    udp(udp_target)
                                    delta = rows(root)[count:]
                                    assert [row["source"] for row in delta if row["kind"] == "udp"] == [source]
                                    if udp_target == "dual.warp.invalid":
                                        assert [row["destination"] for row in delta if row["kind"] == "udp"] == [
                                            ORIGIN4 if family == 4 else ORIGIN6]
                                    assert all(row["server_port"] == 5353 for row in delta
                                               if row["kind"] == "dns"), delta
                                packets = [row for row in rows(root)[len(before):]
                                           if row["kind"] == "wireguard" and
                                           row["direction"] == "client-to-peer"]
                                assert packets and all(row["reserved"] == [1, 2, 255] for row in packets)
                                counters = run(["wg", "show", "wg-padm", "transfer"], peer).split()
                                assert len(counters) == 3 and all(int(value) > 0 for value in counters[1:])
                                handshake = run(["wg", "show", "wg-padm", "latest-handshakes"], peer).split()
                                assert len(handshake) == 2 and int(handshake[1]) > 0
                            if not mode.startswith("global"):
                                accepted("unmatched.test", root, DIRECT4, core)
                            if mode == "selective4":
                                count = len(rows(root))
                                (root / "peer-off").touch()
                                try:
                                    result = request("127.0.0.1", LOCAL, HTTP, "failure.warp.invalid",
                                                     pipelined=core == "xray", timeout=1)
                                except (socket.timeout, EOFError, ConnectionResetError):
                                    result = False
                                # 失联只证明观测窗口不回退直连；核心退出前不恢复 Peer，防止迟到请求串场。
                                delta = rows(root)[count:]
                                assert not result and any(row["kind"] == "wireguard" for row in delta)
                                assert not any(row["kind"] in ("tcp", "proxy") for row in delta)
                                print(f"routing-warp-{core}-peer-off: no direct fallback in 1s window",
                                      flush=True)
                            assert process.poll() is None and links() == expected_links
                            print(f"routing-warp-{core}-{mode}: " +
                                  ("direct-positive-control/off-restore" if mode in ("control", "off")
                                   else "encrypted-peer/reserved/tunnel-address/TCP/UDP/priority") +
                                  " passed", flush=True)
                        finally:
                            stop(process)
                            (root / "peer-off").unlink(missing_ok=True)
            print("routing-warp-scope=local-peer-only; reserved header adapted for kernel fixture", flush=True)
        except BaseException:
            print("routing-warp failure events:", file=sys.stderr)
            for line in (root / "events.jsonl").read_text().splitlines()[-80:]:
                print(line, file=sys.stderr)
            if holder is not None and holder.poll() is None:
                for field in ("transfer", "latest-handshakes"):
                    result = subprocess.run(namespace(holder.pid) +
                                            ["wg", "show", "wg-padm", field],
                                            capture_output=True, text=True)
                    print(f"routing-warp peer {field} (exit {result.returncode}): " +
                          result.stdout + result.stderr, file=sys.stderr)
            for path in root.glob("*.log"):
                print(path.read_text(errors="replace")[-5000:], file=sys.stderr)
            raise
        finally:
            if server is not None:
                stop(server)
            resolver.write_bytes(original_resolver)
            if holder is not None:
                stop(holder)
            if "warp-client" in links():
                run(["ip", "link", "delete", "warp-client"])
            assert links() == {"lo"}


if __name__ == "__main__":
    if sys.argv[1] == "fixture":
        fixture(sys.argv[2])
    else:
        main(Path(sys.argv[1]))
