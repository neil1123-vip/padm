#!/usr/bin/env python3
"""有界双向流完整性探针；并行收发避免大回显堵塞发送窗口。"""
import argparse
from contextlib import suppress
import hashlib
import json
import os
import socket
import socketserver
import threading
import time


class Echo(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(30)
        while data := self.request.recv(65536):
            self.request.sendall(data)


def exact(connection, size):
    result = bytearray()
    while len(result) < size:
        part = connection.recv(size - len(result))
        if not part:
            raise EOFError("流提前关闭")
        result.extend(part)
    return bytes(result)


def exchange(connection, size):
    assert type(size) is int and 0 < size <= 8 * 1024 * 1024
    block = os.urandom(min(size, 65536))
    uploaded, downloaded = hashlib.sha256(), hashlib.sha256()
    errors = []
    connection.settimeout(30)
    started = time.monotonic()

    def send():
        try:
            remaining = size
            while remaining:
                chunk = block[:min(remaining, len(block))]
                connection.sendall(chunk)
                uploaded.update(chunk)
                remaining -= len(chunk)
        except BaseException as error:
            errors.append(error)
            with suppress(OSError):
                connection.shutdown(socket.SHUT_RDWR)

    writer = threading.Thread(target=send, daemon=True)
    writer.start()
    try:
        remaining = size
        while remaining:
            chunk = connection.recv(min(remaining, 65536))
            if not chunk:
                raise EOFError("回显不足")
            downloaded.update(chunk)
            remaining -= len(chunk)
    finally:
        if remaining:
            with suppress(OSError):
                connection.shutdown(socket.SHUT_RDWR)
        writer.join(timeout=31)
    assert not writer.is_alive(), "上传线程没有结束"
    if errors:
        raise errors[0]
    assert uploaded.digest() == downloaded.digest(), "回显内容摘要不一致"
    return {"upload_bytes": size, "download_bytes": size, "sha256": downloaded.hexdigest(),
            "elapsed_seconds": round(time.monotonic() - started, 3)}


def connect(socks, target):
    connection = socket.create_connection(socks, timeout=10)
    try:
        connection.sendall(b"\x05\x01\x00")
        assert exact(connection, 2) == b"\x05\x00"
        host = target[0].encode("idna")
        assert 0 < len(host) < 256 and 0 < target[1] < 65536
        connection.sendall(b"\x05\x01\x00\x03" + bytes([len(host)]) + host
                           + target[1].to_bytes(2, "big"))
        head = exact(connection, 4)
        assert head[:3] == b"\x05\x00\x00" and head[3] in (1, 3, 4), "SOCKS 拒绝"
        length = exact(connection, 1)[0] if head[3] == 3 else (4 if head[3] == 1 else 16)
        exact(connection, length + 2)
        return connection
    except BaseException:
        connection.close()
        raise


def selfcheck():
    for corrupt in (False, True):
        client, peer = socket.socketpair()

        def echo():
            with peer:
                while data := peer.recv(65536):
                    peer.sendall(bytes([data[0] ^ 1]) + data[1:] if corrupt else data)

        worker = threading.Thread(target=echo, daemon=True)
        worker.start()
        rejected = False
        try:
            with client:
                proof = exchange(client, 1048576)
        except AssertionError:
            if not corrupt:
                raise
            rejected = True
        finally:
            client.close()
            worker.join(timeout=2)
            assert not worker.is_alive()
        assert rejected == corrupt, "损坏回显判定不符"
        if not corrupt:
            assert proof["upload_bytes"] == proof["download_bytes"] == 1048576
    print(json.dumps({"selfcheck": "pass", "corruption_rejected": True}))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--selfcheck", action="store_true")
    parser.add_argument("--serve", nargs=2, metavar=("HOST", "PORT"))
    parser.add_argument("--socks", nargs=2, metavar=("HOST", "PORT"))
    parser.add_argument("--target", nargs=2, metavar=("HOST", "PORT"))
    parser.add_argument("--sizes", nargs="+", type=int, default=[1048576, 8388608])
    arguments = parser.parse_args()
    if arguments.selfcheck:
        selfcheck()
    elif arguments.serve:
        with socketserver.ThreadingTCPServer(
                (arguments.serve[0], int(arguments.serve[1])), Echo) as server:
            server.daemon_threads = True
            server.serve_forever()
    else:
        assert arguments.socks and arguments.target
        proofs = []
        for size in arguments.sizes:
            with connect((arguments.socks[0], int(arguments.socks[1])),
                         (arguments.target[0], int(arguments.target[1]))) as connection:
                proofs.append(exchange(connection, size))
        print(json.dumps({"verified": True, "transfers": proofs}))


if __name__ == "__main__":
    main()
