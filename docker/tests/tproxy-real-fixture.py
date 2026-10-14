#!/usr/bin/env python3
"""TProxy 真实转发测试夹具：记录目标看到的来源并提供一次性探测。"""

import json
import signal
import socket
import socketserver
import sys
import threading
from pathlib import Path


def record(root: Path, kind: str, peer, payload: bytes) -> None:
    with (root / f"{kind}.jsonl").open("a", encoding="utf-8") as output:
        json.dump({"peer": peer[0], "port": peer[1], "payload": payload.decode()}, output)
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
    tcp = ThreadingTcpServer(("0.0.0.0", tcp_port), TcpHandler)
    udp = ThreadingUdpServer(("0.0.0.0", udp_port), UdpHandler)
    tcp.root = udp.root = root
    try:
        threading.Thread(target=tcp.serve_forever, daemon=True).start()
        threading.Thread(target=udp.serve_forever, daemon=True).start()
        (root / "ready").touch()
        signal.pause()
    finally:
        tcp.server_close()
        udp.server_close()


def client(kind: str, host: str, port: int) -> None:
    if kind == "tcp":
        with socket.create_connection((host, port), timeout=3) as stream:
            stream.sendall(b"tproxy-tcp-request")
            assert stream.recv(64) == b"tproxy-tcp-ok"
        return
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as stream:
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
