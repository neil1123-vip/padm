import contextlib
import importlib.util
import json
from pathlib import Path
import re
import socket
import socketserver
import struct
import sys
import threading
import time


module_spec = importlib.util.spec_from_file_location(
    "routing_fixture", Path(__file__).with_name("routing-socks5-real.py"))
fixture = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(fixture)
UUID = b"11111111-1111-4111-8111-111111111111"
BODY = b"routing-destination-ok"
RESPONSE = (b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(BODY)).encode() +
            b"\r\nConnection: close\r\n\r\n" + BODY)


def clean_log(text):
    return re.sub(r"\x1b\[[0-9;]*m", "", text)


class Datagram(socketserver.BaseRequestHandler):
    def handle(self):
        data, stream = self.request
        self.server.received += 1
        stream.sendto(data, self.client_address)


class UdpServer(socketserver.ThreadingUDPServer):
    daemon_threads = True

    def __init__(self, host):
        self.address_family = socket.AF_INET6 if ":" in host else socket.AF_INET
        self.received = 0
        super().__init__((host, 0), Datagram)


def authenticate(stream, password=UUID):
    stream.sendall(b"\x05\x01\x02")
    assert fixture.exact(stream, 2) == b"\x05\x02"
    stream.sendall(b"\x01" + bytes([len(UUID)]) + UUID +
                   bytes([len(password)]) + password)
    return fixture.exact(stream, 2) == b"\x01\x00"


def bound(stream):
    header = fixture.exact(stream, 4)
    assert header[:3] == b"\x05\x00\x00", header
    family = {1: socket.AF_INET, 4: socket.AF_INET6}[header[3]]
    host = socket.inet_ntop(family, fixture.exact(stream, 4 if header[3] == 1 else 16))
    return host, struct.unpack("!H", fixture.exact(stream, 2))[0]


def tcp(host, source, listener, destination):
    with socket.create_connection((host, listener), timeout=1,
                                  source_address=(source, 0)) as stream:
        assert authenticate(stream)
        stream.sendall(b"\x05\x01\x00" + fixture.socks_address(host) +
                       struct.pack("!H", destination))
        try:
            header = fixture.exact(stream, 4)
            assert header[0] == 5 and header[2] == 0
            if header[1] != 0:
                return False
            fixture.exact(stream, {1: 4, 4: 16}[header[3]] + 2)
            stream.sendall(b"GET /routing-check HTTP/1.1\r\nHost: unmatched.padm.invalid\r\n\r\n")
            assert fixture.exact(stream, len(RESPONSE)) == RESPONSE
            return True
        except (EOFError, ConnectionResetError):
            return False


def udp(host, source, listener, destination, allowed):
    with socket.create_connection((host, listener), timeout=1,
                                  source_address=(source, 0)) as control:
        assert authenticate(control)
        control.sendall(b"\x05\x03\x00" +
                        fixture.socks_address("::" if ":" in host else "0.0.0.0") + b"\x00\x00")
        relay_host, relay_port = bound(control)
        assert relay_port, "UDP ASSOCIATE 未返回有效端口"
        if relay_host in ("0.0.0.0", "::"):
            relay_host = host
        family = socket.AF_INET6 if ":" in relay_host else socket.AF_INET
        with socket.socket(family, socket.SOCK_DGRAM) as stream:
            stream.bind((source, 0))
            stream.settimeout(1 if allowed else 0.15)
            packet = (b"\x00\x00\x00" + fixture.socks_address(host) +
                      struct.pack("!H", destination) + b"source-guard-proof")
            stream.sendto(packet, (relay_host, relay_port))
            try:
                response = stream.recv(4096)
                assert allowed and response.endswith(b"source-guard-proof"), response
            except socket.timeout:
                assert not allowed, "允许来源的 UDP 未收到回包"


def check(root, mode, servers):
    config = json.loads((root / f"{mode}.json").read_text())
    source_rules = [rule for rule in config["route"]["rules"]
                    if rule.get("action") == "reject" and rule.get("type") == "logical"]
    assert len(source_rules) == 1, "来源拒绝规则缺失或重复"
    assert config["route"]["rules"][0] == source_rules[0], "全局放行排在来源拒绝之前"
    source_rule = source_rules[0]
    normalized_rule = json.loads(json.dumps(source_rule))
    # sing-box merge 将单项 Listable 数组输出为字符串。
    for match in normalized_rule["rules"]:
        for key in ("inbound", "source_ip_cidr"):
            if isinstance(match.get(key), str):
                match[key] = [match[key]]
    expected_sources = ["127.0.0.1/32"] if mode == "ipv4-only" else ["127.0.0.1/32", "::1/128"]
    assert normalized_rule == dict(type="logical", mode="and", action="reject", rules=[
        dict(inbound=["socks5_inbound"]), dict(source_ip_cidr=expected_sources, invert=True)]), source_rule
    with contextlib.ExitStack() as stack:
        for label in ("old", "fixed"):
            current = json.loads(json.dumps(config))
            if label == "old":
                current["route"]["rules"].remove(source_rule)
            native_port, other_port = fixture.port("127.0.0.1"), fixture.port("127.0.0.1")
            while other_port == native_port:
                other_port = fixture.port("127.0.0.1")
            for inbound in current["inbounds"]:
                inbound["listen_port"] = native_port if inbound["tag"] == "socks5_inbound" else other_port
            path, log = root / f"{mode}.{label}.json", root / f"{mode}.{label}.log"
            fixture.write_config(path, current)
            process = stack.enter_context(fixture.running(
                ["/routing-cores/sing-box", "run", "-c"], path, "127.0.0.1", native_port, log))
            for host, source in (("127.0.0.1", "127.0.0.1"),
                                 ("127.0.0.1", "127.0.0.2"), ("::1", "::1")):
                destination, datagram = servers[host]
                allowed = label == "old" or (source != "127.0.0.2" and
                                             (mode != "ipv4-only" or host != "::1"))
                accepted, received = destination.accepted, datagram.received
                assert tcp(host, source, native_port, destination.server_address[1]) == allowed
                assert destination.accepted == accepted + int(allowed)
                log_size = log.stat().st_size
                udp(host, source, native_port, datagram.server_address[1], allowed)
                assert datagram.received == received + int(allowed)
                if not allowed:
                    # 无回包本身不是拒绝证据，必须同时看到核心的 reject 事件。
                    deadline = time.monotonic() + 1
                    while True:
                        recent = clean_log(log.read_text()[log_size:])
                        packet_ids = re.findall(
                            r"\[([0-9]+) [^\]]*\].*inbound packet connection to", recent)
                        if any(re.search(r"\[" + packet_id +
                                         r" [^\]]*\].*reject", recent, re.IGNORECASE)
                               for packet_id in packet_ids):
                            break
                        assert time.monotonic() < deadline, "UDP 没有实际 reject 证据:\n" + repr(recent)
                        time.sleep(0.01)
                assert tcp(host, source, other_port, destination.server_address[1])
                udp(host, source, other_port, datagram.server_address[1], True)
                assert process.poll() is None
            with socket.create_connection(("127.0.0.1", native_port), timeout=1) as stream:
                assert not authenticate(stream, b"wrong-password"), "错误认证被接受"
    print(f"native-socks-source-{mode}: old bypass/fixed TCP+UDP/sibling/auth passed", flush=True)


def main(root):
    root.chmod(0o755)
    servers = {}
    with contextlib.ExitStack() as stack:
        for host in ("127.0.0.1", "::1"):
            destination = stack.enter_context(fixture.Server((host, 0), fixture.Destination))
            destination.accepted = 0
            destination.received = []
            datagram = stack.enter_context(UdpServer(host))
            servers[host] = destination, datagram
            for server in (destination, datagram):
                thread = threading.Thread(target=server.serve_forever,
                                          kwargs=dict(poll_interval=0.02), daemon=True)
                thread.start()
                stack.callback(thread.join, 1)
                stack.callback(server.shutdown)
        for mode in ("all", "domains", "ipv4-only"):
            check(root, mode, servers)


if __name__ == "__main__":
    main(Path(sys.argv[1]))
