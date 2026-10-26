#!/usr/bin/env python3
import json
import os
import pathlib
import select
import selectors
import socket
import struct
import sys
import time
import uuid


TARGET = "203.0.113.200"
PORT = 35991


def serve(ready):
    with socket.socket() as tcp, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        tcp.bind((TARGET, PORT))
        tcp.listen()
        udp.bind((TARGET, PORT))
        selector = selectors.DefaultSelector()
        selector.register(tcp, selectors.EVENT_READ)
        selector.register(udp, selectors.EVENT_READ)
        pathlib.Path(ready).write_text("ready\n")
        while True:
            for key, _ in selector.select():
                if key.fileobj is tcp:
                    with tcp.accept()[0] as conn:
                        conn.settimeout(3)
                        packet = b""
                        while not packet.endswith(b"\n"):
                            chunk = conn.recv(256)
                            if not chunk:
                                raise RuntimeError("incomplete TCP probe")
                            packet += chunk
                        conn.sendall(packet)
                else:
                    packet, address = udp.recvfrom(256)
                    udp.sendto(packet, address)


def checksum(packet):
    if len(packet) % 2:
        packet += b"\0"
    total = sum(struct.unpack(f"!{len(packet) // 2}H", packet))
    while total >> 16:
        total = (total & 0xFFFF) + (total >> 16)
    return ~total & 0xFFFF


def echo_matches(packet, nonce, echo_type):
    if len(packet) < 28 or packet[0] >> 4 != 4 or packet[9] != socket.IPPROTO_ICMP:
        return False
    header_length = (packet[0] & 0x0F) * 4
    return (
        socket.inet_ntoa(packet[12:16] if echo_type == 0 else packet[16:20]) == TARGET
        and packet[header_length:header_length + 2] == bytes((echo_type, 0))
        and packet[header_length + 8:] == nonce
    )


def probe(mode):
    nonce = ("padm-tun-icmp-" + uuid.uuid4().hex).encode()
    counts = {"tun_requests": 0, "wire_requests": 0, "wire_replies": 0, "echo_replies": 0}
    # ETH_P_ALL 才能接收发送方向抓包，随后按 IPv4、ICMP 和 nonce 筛选目标报文。
    with (
        socket.socket(socket.AF_PACKET, socket.SOCK_DGRAM, socket.htons(0x0003)) as tun,
        socket.socket(socket.AF_PACKET, socket.SOCK_DGRAM, socket.htons(0x0003)) as wire,
        socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_ICMP) as ping,
    ):
        tun.bind(("padm-tun", 0))
        wire.bind(("icmp-uplink", 0))
        for conn in (tun, wire, ping):
            conn.setblocking(False)
        packet = struct.pack("!BBHHH", 8, 0, 0, 0, 1) + nonce
        packet = packet[:2] + struct.pack("!H", checksum(packet)) + packet[4:]
        ping.sendto(packet, (TARGET, 0))
        deadline = time.monotonic() + 2
        pending = [tun, wire, ping]
        while time.monotonic() < deadline:
            ready, _, _ = select.select(pending, [], [], max(0, deadline - time.monotonic()))
            for conn in ready:
                try:
                    received = conn.recv(65535)
                except OSError:
                    if conn is ping:
                        pending.remove(ping)
                        continue
                    raise
                if conn is ping:
                    if received[:2] == b"\x00\x00" and received[8:] == nonce:
                        counts["echo_replies"] += 1
                elif echo_matches(received, nonce, 8):
                    counts["tun_requests" if conn is tun else "wire_requests"] += 1
                elif conn is wire and echo_matches(received, nonce, 0):
                    counts["wire_replies"] += 1
    assert counts["tun_requests"] > 0, ("probe bypassed TUN", counts)
    if mode == "direct":
        assert counts["echo_replies"] == counts["wire_requests"] == counts["wire_replies"] == 1, counts
    elif mode == "filtered":
        assert counts["wire_requests"] == 1, counts
        assert counts["echo_replies"] == counts["wire_replies"] == 0, counts
    else:
        assert mode == "denied", mode
        assert counts["echo_replies"] == counts["wire_requests"] == counts["wire_replies"] == 0, counts
    with socket.create_connection((TARGET, PORT), timeout=3) as tcp:
        tcp.sendall(nonce + b"\n")
        reply = b""
        while not reply.endswith(b"\n"):
            packet = tcp.recv(256)
            assert packet, "TCP probe closed before reply"
            reply += packet
        assert reply == nonce + b"\n", "TCP changed with ICMP permission"
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        udp.settimeout(3)
        udp.sendto(nonce, (TARGET, PORT))
        assert udp.recvfrom(256)[0] == nonce, "UDP changed with ICMP permission"
    print(json.dumps({"mode": mode, **counts, "tcp": True, "udp": True}, sort_keys=True))


if sys.argv[1] == "serve":
    serve(sys.argv[2])
else:
    # 探测者使用单独的组；缺权阶段只限制核心组，避免把调用者失败算作核心拒绝。
    os.setgroups([10001])
    os.setgid(10001)
    probe(sys.argv[1])
