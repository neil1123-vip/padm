import contextlib
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
            assert host == self.server.destination_host and port == self.server.destination
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
    family = socket.AF_INET6 if ":" in host else socket.AF_INET
    return bytes([4 if family == socket.AF_INET6 else 1]) + socket.inet_pton(family, host)


def port(host):
    with socket.socket(socket.AF_INET6 if ":" in host else socket.AF_INET) as conn:
        conn.bind((host, 0))
        return conn.getsockname()[1]


def connect(host, address, destination):
    with socket.create_connection((host, address), timeout=2) as conn:
        conn.sendall(b"\x05\x01\x00")
        assert exact(conn, 2) == b"\x05\x00"
        conn.sendall(b"\x05\x01\x00" + socks_address(host) + struct.pack("!H", destination))
        header = exact(conn, 4)
        if header[1] != 0:
            return False
        assert header[0] == 5 and header[2] == 0
        exact(conn, {1: 4, 4: 16}[header[3]] + 2)
        conn.sendall(b"GET /routing-check HTTP/1.1\r\nHost: fixture\r\nConnection: close\r\n\r\n")
        result = b""
        while part := conn.recv(4096):
            result += part
        return result.endswith(b"routing-destination-ok")


def udp(host, address, destination):
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
            packet = b"\x00\x00\x00" + socks_address(host) + struct.pack("!H", destination) + b"udp-leak"
            conn.sendto(packet, (relay_host, relay))
            conn.settimeout(0.2)
            with contextlib.suppress(socket.timeout):
                assert not conn.recv(4096), "UDP 被意外转发"


@contextlib.contextmanager
def running(command, path, host, local, logfile):
    least = ["setpriv", "--reuid=10001", "--regid=10001", "--clear-groups",
             "--bounding-set=-all", "--no-new-privs"]
    with logfile.open("wb") as log:
        process = subprocess.Popen(least + command + [str(path)], stdout=log, stderr=log)
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


root = Path(sys.argv[1])
os.chmod(root, 0o755)
for family, host in (("ipv4", "127.0.0.1"), ("ipv6", "::1")):
    destination = Server((host, 0), Destination)
    destination.received = []
    destination.accepted = 0
    upstream = Server((host, 0), Socks)
    upstream.destination_host = host
    upstream.destination = destination.server_address[1]
    upstream.auth = upstream.connects = 0
    upstream.reject = False
    for server in (destination, upstream):
        threading.Thread(target=server.serve_forever, daemon=True).start()
    with socket.socket(socket.AF_INET6 if family == "ipv6" else socket.AF_INET,
                       socket.SOCK_DGRAM) as datagram:
        datagram.bind((host, 0))
        datagram.settimeout(0.25)
        try:
            for core in ("xray", "sing-box"):
                config = json.loads((root / f"{core}.json").read_text())
                local = port(host)
                outbound = config["outbounds"][0]
                if core == "xray":
                    assert outbound["tag"] == "padm-socks5"
                    assert config["routing"]["rules"][0]["outboundTag"] == "padm-traffic-api"
                    assert config["routing"]["rules"][1] == dict(type="field", network="udp", outboundTag="blocked")
                    outbound["settings"]["servers"][0].update(address=host, port=upstream.server_address[1])
                    config["inbounds"].append(dict(listen=host, port=local, tag="fixture-in",
                                                   protocol="socks", settings=dict(auth="noauth", udp=True)))
                    command = ["/routing-cores/xray", "run", "-c"]
                    validate = ["/routing-cores/xray", "run", "-test", "-c"]
                else:
                    assert config["route"]["final"] == "padm-socks5"
                    assert config["route"]["rules"] == [dict(network="udp", action="reject")]
                    outbound.update(server=host, server_port=upstream.server_address[1])
                    config["inbounds"].append(dict(type="socks", tag="fixture-in", listen=host,
                                                   listen_port=local))
                    command = ["/routing-cores/sing-box", "run", "-c"]
                    validate = ["/routing-cores/sing-box", "check", "-c"]
                path = root / f"{core}.{family}.runtime.json"
                path.write_text(json.dumps(config))
                path.chmod(0o644)
                least = ["setpriv", "--reuid=10001", "--regid=10001", "--clear-groups",
                         "--bounding-set=-all", "--no-new-privs"]
                subprocess.run(least + validate + [str(path)], check=True, stdout=subprocess.DEVNULL)
                # 同一核心、入站和地址族先证明 UDP 可直达，不能把坏入站当作阻断成功。
                direct = json.loads(json.dumps(config))
                direct["outbounds"] = [item for item in direct["outbounds"] if item["tag"] != "padm-socks5"]
                if core == "xray":
                    direct["routing"]["rules"] = direct["routing"]["rules"][:1]
                else:
                    direct["route"].update(final="direct", rules=[])
                control = root / f"{core}.{family}.direct.json"
                control.write_text(json.dumps(direct))
                control.chmod(0o644)
                with running(command, control, host, local, root / f"{core}.{family}.direct.log"):
                    udp(host, local, datagram.getsockname()[1])
                    assert datagram.recv(4096) == b"udp-leak", "UDP 直连正向对照没有到达"
                with running(command, path, host, local, root / f"{core}.{family}.log") as process:
                    received = len(destination.received)
                    connects = upstream.connects
                    assert connect(host, local, upstream.destination)
                    assert upstream.connects == connects + 1 and len(destination.received) == received + 1
                    accepted = destination.accepted
                    auth = upstream.auth
                    upstream.reject = True
                    for _ in range(2):
                        try:
                            assert not connect(host, local, upstream.destination), "认证失败回退直连"
                        except (OSError, EOFError):
                            pass
                    time.sleep(0.05)
                    assert upstream.auth == auth + 2, "认证失败用例没有触达真实上游"
                    assert len(destination.received) == received + 1 and destination.accepted == accepted
                    upstream.reject = False
                    assert connect(host, local, upstream.destination)
                    received, accepted = len(destination.received), destination.accepted
                    auth = upstream.auth
                    udp(host, local, datagram.getsockname()[1])
                    with contextlib.suppress(socket.timeout):
                        raise AssertionError(f"UDP 直连泄漏: {datagram.recv(4096)!r}")
                    assert upstream.auth == auth, "被阻断的 UDP 不应连接 SOCKS5 上游"
                    # 停止接受而非延迟响应，验证真实上游连接失败不回退。
                    upstream.shutdown()
                    upstream.server_close()
                    try:
                        assert not connect(host, local, destination.server_address[1]), "上游断开回退直连"
                    except (OSError, EOFError):
                        pass
                    time.sleep(0.05)
                    assert process.poll() is None, "上游断开后核心意外退出"
                    assert len(destination.received) == received and destination.accepted == accepted
                print(f"routing-socks5-real-{core}-{family}: CONNECT/auth/UDP/upstream checks passed")
                if core == "xray":
                    upstream = Server((host, 0), Socks)
                    upstream.destination_host = host
                    upstream.destination = destination.server_address[1]
                    upstream.auth = upstream.connects = 0
                    upstream.reject = False
                    threading.Thread(target=upstream.serve_forever, daemon=True).start()
        finally:
            destination.shutdown()
            destination.server_close()
            upstream.shutdown()
            upstream.server_close()
