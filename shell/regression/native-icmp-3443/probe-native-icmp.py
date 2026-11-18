import hashlib
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


def checksum(packet):
    if len(packet) % 2:
        packet += b"\0"
    total = sum(struct.unpack(f"!{len(packet) // 2}H", packet))
    while total >> 16:
        total = (total & 65535) + (total >> 16)
    return ~total & 65535


def serve(ready):
    with socket.socket() as tcp, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        tcp.bind((TARGET, PORT))
        tcp.listen()
        udp.bind((TARGET, PORT))
        selector = selectors.DefaultSelector()
        selector.register(tcp, selectors.EVENT_READ)
        selector.register(udp, selectors.EVENT_READ)
        pathlib.Path(ready).write_text(json.dumps({
            "netns": os.readlink("/proc/self/ns/net"),
            "pid1_netns": os.readlink("/proc/1/ns/net"),
            "pid": os.getpid(), "target": TARGET, "port": PORT,
        }) + "\n")
        while True:
            for key, _ in selector.select():
                if key.fileobj is tcp:
                    with tcp.accept()[0] as connection:
                        connection.settimeout(3)
                        packet = b""
                        while not packet.endswith(b"\n"):
                            data = connection.recv(256)
                            assert data, "incomplete TCP probe"
                            packet += data
                        connection.sendall(packet)
                else:
                    packet, address = udp.recvfrom(256)
                    udp.sendto(packet, address)


def decode(packet):
    if len(packet) < 28 or packet[0] >> 4 != 4 or packet[9] != socket.IPPROTO_ICMP:
        return None
    header = (packet[0] & 15) * 4
    if len(packet) < header + 8:
        return None
    return {
        "source": socket.inet_ntoa(packet[12:16]),
        "destination": socket.inet_ntoa(packet[16:20]),
        "type": packet[header], "code": packet[header + 1],
        "identifier": int.from_bytes(packet[header + 4:header + 6], "big"),
        "sequence": int.from_bytes(packet[header + 6:header + 8], "big"),
        "payload_hex": packet[header + 8:].hex(),
        "icmp_checksum": checksum(packet[header:]),
        "packet_hex": packet.hex(),
    }


def probe(mode):
    assert mode in ("direct", "filtered", "denied")
    os.setgroups([10001])
    os.setgid(10001)
    caller_netns = os.readlink("/proc/self/ns/net")
    host_netns = os.readlink("/proc/1/ns/net")
    assert caller_netns == host_netns
    nonce = ("padm-native-icmp-" + uuid.uuid4().hex).encode()
    counts = dict(tun_requests=0, wire_requests=0, wire_replies=0, echo_replies=0)
    captures, ping_received = [], []
    with (
        socket.socket(socket.AF_PACKET, socket.SOCK_DGRAM, socket.htons(3)) as tun,
        socket.socket(socket.AF_PACKET, socket.SOCK_DGRAM, socket.htons(3)) as wire,
        socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_ICMP) as ping,
    ):
        tun.bind(("padm-tun", 0))
        wire.bind(("icmp-uplink", 0))
        for connection in (tun, wire, ping):
            connection.setblocking(False)
        packet = struct.pack("!BBHHH", 8, 0, 0, 0, 1) + nonce
        packet = packet[:2] + struct.pack("!H", checksum(packet)) + packet[4:]
        ping.sendto(packet, (TARGET, 0))
        deadline = time.monotonic() + 2
        pending = [tun, wire, ping]
        while time.monotonic() < deadline:
            ready, _, _ = select.select(pending, [], [], max(0, deadline - time.monotonic()))
            for connection in ready:
                try:
                    received, address = connection.recvfrom(65535)
                except OSError as error:
                    if connection is ping:
                        ping_received.append({"errno": error.errno})
                        pending.remove(ping)
                        continue
                    raise
                if connection is ping:
                    ping_received.append({"packet_hex": received.hex(), "address": list(address)})
                    if received[:2] == b"\0\0" and received[8:] == nonce:
                        counts["echo_replies"] += 1
                    continue
                row = decode(received)
                if row is None or row["payload_hex"] != nonce.hex():
                    continue
                row.update(interface=address[0], protocol=address[1], packet_type=address[2],
                           hardware_type=address[3], hardware_address_hex=address[4].hex())
                captures.append(row)
                if row["type"] == 8 and row["code"] == 0 and row["destination"] == TARGET:
                    counts["tun_requests" if connection is tun else "wire_requests"] += 1
                elif connection is wire and row["type"] == 0 and row["code"] == 0 and row["source"] == TARGET:
                    counts["wire_replies"] += 1
    assert counts["tun_requests"] > 0, ("probe bypassed TUN", counts)
    expected = {
        "direct": dict(wire_requests=1, wire_replies=1, echo_replies=1),
        "filtered": dict(wire_requests=1, wire_replies=0, echo_replies=0),
        "denied": dict(wire_requests=0, wire_replies=0, echo_replies=0),
    }[mode]
    assert all(counts[key] == value for key, value in expected.items()), counts
    sent = nonce + b"\n"
    with socket.create_connection((TARGET, PORT), timeout=3) as tcp:
        tcp.sendall(sent)
        reply = b""
        while not reply.endswith(b"\n"):
            data = tcp.recv(256)
            assert data, "TCP ended before reply"
            reply += data
        assert reply == sent
        tcp_record = {"sent_hex": sent.hex(), "received_hex": reply.hex(),
                      "peer": list(tcp.getpeername()), "local": list(tcp.getsockname())}
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        udp.settimeout(3)
        udp.sendto(nonce, (TARGET, PORT))
        reply, peer = udp.recvfrom(256)
        assert reply == nonce
        udp_record = {"sent_hex": nonce.hex(), "received_hex": reply.hex(),
                      "peer": list(peer), "local": list(udp.getsockname())}
    return {
        "mode": mode, "nonce": nonce.decode(), "nonce_sha256": hashlib.sha256(nonce).hexdigest(),
        "caller_netns": caller_netns, "host_netns": host_netns,
        "uid": os.getuid(), "gid": os.getgid(), "groups": os.getgroups(),
        "probe_status": pathlib.Path("/proc/self/status").read_text(),
        "ping_group_range": pathlib.Path("/proc/sys/net/ipv4/ping_group_range").read_text(),
        "sent_icmp_hex": packet.hex(), "captures": captures, "ping_received": ping_received,
        "counts": counts, "tcp": tcp_record, "udp": udp_record, "passed": True,
    }


if __name__ == "__main__":
    if sys.argv[1] == "serve":
        serve(sys.argv[2])
    else:
        print(json.dumps(probe(sys.argv[1]), sort_keys=True))
