#!/usr/bin/env python3
"""TProxy 真实转发测试夹具：记录目标看到的来源并提供一次性探测。"""

import json
import ipaddress
import signal
import socket
import socketserver
import sys
import threading
from pathlib import Path


def record(root: Path, kind: str, peer, payload: bytes) -> None:
    address = ipaddress.ip_address(peer[0])
    with (root / f"{kind}.jsonl").open("a", encoding="utf-8") as output:
        json.dump({"peer": str(getattr(address, "ipv4_mapped", None) or address),
                   "port": peer[1], "payload": payload.decode()}, output)
        output.write("\n")


class TcpHandler(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(3)
        payload = self.request.recv(4096)
        record(self.server.root, "tcp", self.client_address, payload)
        self.request.sendall(b"tproxy-tcp-ok")


class UdpHandler(socketserver.BaseRequestHandler):
    def handle(self):
        payload, stream = self.request
        record(self.server.root, "udp", self.client_address, payload)
        stream.sendto(b"tproxy-udp-ok", self.client_address)


class ThreadingTcpServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


class ThreadingUdpServer(socketserver.ThreadingUDPServer):
    allow_reuse_address = True
    daemon_threads = True


def target(root: Path, tcp_port: int, udp_port: int) -> None:
    servers = []
    for family, host in ((socket.AF_INET, "0.0.0.0"), (socket.AF_INET6, "::")):
        for server_type, handler, port in (
            (ThreadingTcpServer, TcpHandler, tcp_port),
            (ThreadingUdpServer, UdpHandler, udp_port),
        ):
            family_server = type("FamilyServer", (server_type,), {"address_family": family})
            server = family_server((host, port), handler, bind_and_activate=False)
            if family == socket.AF_INET6:
                server.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            server.server_bind()
            server.server_activate()
            server.root = root
            servers.append(server)
    try:
        for server in servers:
            threading.Thread(target=server.serve_forever, daemon=True).start()
        (root / "ready").touch()
        signal.pause()
    finally:
        for server in servers:
            server.server_close()


def client(kind: str, host: str, port: int) -> None:
    if kind == "tcp":
        with socket.create_connection((host, port), timeout=3) as stream:
            stream.sendall(b"tproxy-tcp-request")
            assert stream.recv(64) == b"tproxy-tcp-ok"
        return
    with socket.socket(socket.AF_INET6 if ":" in host else socket.AF_INET, socket.SOCK_DGRAM) as stream:
        stream.settimeout(3)
        stream.sendto(b"tproxy-udp-request", (host, port))
        payload, _ = stream.recvfrom(64)
        assert payload == b"tproxy-udp-ok"


def main() -> None:
    mode = sys.argv[1]
    if mode == "target":
        target(Path(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]))
    elif mode == "client":
        client(sys.argv[2], sys.argv[3], int(sys.argv[4]))
    else:
        raise SystemExit(f"unknown fixture mode: {mode}")


if __name__ == "__main__":
    main()
