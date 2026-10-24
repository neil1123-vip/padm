"""从真实 TLS 解密帧统计 XHTTP POST；禁止按业务字节推算次数。"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def fields(node, name):
    return [value for value in node.iter("field") if value.get("name") == name]


def one(node, name, default=None):
    values = fields(node, name)
    assert len(values) <= 1, f"字段重复：{name}"
    return values[0].get("show", values[0].get("value")) if values else default


def unique(headers, name):
    values = [value for key, value in headers if key == name]
    assert len(values) <= 1, f"伪首部重复：{name}"
    return values[0] if values else None


def parse(pdml, mode, path, port, success=True, maxpost=16384):
    assert mode in ("packet-up", "stream-up") and path.startswith("/")
    base = path.rstrip("/") + "/"
    root = ET.parse(pdml).getroot()
    packets = root.findall("packet")
    assert packets, "空抓包"
    streams, frames = {}, []
    for packet in packets:
        assert int(one(packet, "frame.cap_len")) == int(one(packet, "frame.len")), "抓包截断"
        assert not fields(packet, "_ws.malformed"), "畸形数据帧"
        for protocol in packet.findall("proto"):
            if protocol.get("name") != "http2":
                continue
            tcp = one(packet, "tcp.stream")
            source, target = one(packet, "tcp.srcport"), one(packet, "tcp.dstport")
            assert tcp is not None and (str(port) in (source, target)), "HTTP/2 连接归属不明"
            direction = "response" if source == str(port) else "request"
            for frame in protocol.findall("field"):
                if frame.get("name") != "http2.stream":
                    continue
                if fields(frame, "http2.magic"):
                    continue
                streamid = int(one(frame, "http2.streamid"))
                kind = int(one(frame, "http2.type"))
                if not streamid:
                    continue
                key = (int(tcp), streamid)
                record = streams.setdefault(key, {
                    "tcp_stream": key[0], "http2_stream": key[1],
                    "request_headers": [], "response_headers": [],
                    "request_data": [], "response_data": [],
                    "request_end_stream": False, "response_end_stream": False})
                header_pairs = []
                for header in fields(frame, "http2.header"):
                    name, value = one(header, "http2.header.name"), one(header, "http2.header.value")
                    assert name is not None and value is not None, "首部不完整"
                    header_pairs.append([name, value])
                record[direction + "_headers"].extend(header_pairs)
                data = fields(frame, "http2.data.data")
                assert len(data) <= 1, "同一 DATA 帧出现歧义正文"
                raw = bytes.fromhex(data[0].get("value", "")) if data else b""
                ended = one(frame, "http2.flags.end_stream", "False") in ("1", "True")
                wire_length = int(one(frame, "http2.length"))
                if kind == 0:
                    padded = one(frame, "http2.flags.padded", "False") in ("1", "True")
                    actual = wire_length - int(one(frame, "http2.pad_length", "0")) - int(padded)
                    assert actual >= 0, "DATA 填充长度无效"
                    if fields(frame, "http2.body.reassembled.length"):
                        # Wireshark 在结束帧挂载累计正文；只取本帧的实际尾部载荷。
                        assert len(raw) == int(one(frame, "http2.body.reassembled.length"))
                        fragments = fields(frame, "http2.body.fragment")
                        assert fragments and b"".join(
                            bytes.fromhex(item.get("value", "")) for item in fragments) == raw
                        assert ended and len(raw) >= actual, "累计正文挂载位置无效"
                        raw = raw[-actual:] if actual else b""
                    assert len(raw) == actual, "DATA 真实载荷长度不完整"
                detail = {
                    "frame_number": int(one(packet, "frame.number")),
                    "time_epoch": one(packet, "frame.time_epoch"),
                    "tcp_stream": key[0], "http2_stream": key[1],
                    "direction": direction, "type": kind,
                    "wire_payload_length": wire_length,
                    "end_stream": ended, "headers": header_pairs,
                    "reset_error": one(frame, "http2.rst_stream.error"),
                    "data_hex": raw.hex(), "data_bytes": len(raw)}
                frames.append(detail)
                if kind == 0:
                    # 填充长度可大于正文；只摘要真实 DATA 正文。
                    assert len(raw) <= detail["wire_payload_length"]
                    record[direction + "_data"].append(detail)
                if ended and kind in (0, 1):
                    assert not record[direction + "_end_stream"], "重复 END_STREAM"
                    record[direction + "_end_stream"] = True
    assert frames, "没有解密的 HTTP/2 帧"
    requests, sessions = [], {}
    for key, record in sorted(streams.items()):
        headers = record["request_headers"]
        method, uri = unique(headers, ":method"), unique(headers, ":path")
        if method is None:
            assert not record["request_data"], "正文缺少请求首部"
            continue
        assert method in ("GET", "POST") and uri and uri.startswith(base), "非本例 XHTTP 请求"
        suffix = uri[len(base):].split("?")[0].strip("/")
        parts = suffix.split("/")
        expected = 2 if mode == "packet-up" and method == "POST" else 1
        assert len(parts) == expected and re.fullmatch(r"[A-Za-z0-9_-]+", parts[0]), "会话路径无效"
        session = parts[0]
        seq = None
        if expected == 2:
            assert re.fullmatch(r"0|[1-9][0-9]*", parts[1]), "packet-up 序号无效"
            seq = int(parts[1])
            sessions.setdefault(session, []).append(seq)
        body = b"".join(bytes.fromhex(row["data_hex"]) for row in record["request_data"])
        status = unique(record["response_headers"], ":status")
        if success:
            assert status == "200", f"响应非 200：{key} {status}"
        if success and method == "POST":
            assert record["request_end_stream"], f"POST 缺少 END_STREAM：{key}"
            assert record["response_end_stream"], f"POST 响应缺少 END_STREAM：{key}"
        if method == "POST":
            assert body, f"POST 正文为空：{key}"
            if mode == "packet-up":
                assert len(body) <= maxpost, "packet-up 超过单次 POST 上限"
        requests.append({
            **record, "method": method, "path": uri, "session": session,
            "seq": seq, "status": status, "body_bytes": len(body),
            "body_sha256": hashlib.sha256(body).hexdigest()})
    posts = [row for row in requests if row["method"] == "POST"]
    gets = [row for row in requests if row["method"] == "GET"]
    assert posts and gets, "缺少实际 POST 或 GET"
    assert len({row["session"] for row in requests}) == 1, "跨会话混入"
    if mode == "packet-up":
        assert len(sessions) == 1
        sequences = next(iter(sessions.values()))
        assert len(set(sequences)) == len(sequences), "packet-up 序号重复"
        assert sorted(sequences) == list(range(len(sequences))), "packet-up 序号不连续"
    return {
        "schema": 1, "mode": mode, "success_expected": success,
        "packets": len(packets), "post_count": len(posts),
        "post_body_bytes": sum(row["body_bytes"] for row in posts),
        "tcp_connections": sorted({row["tcp_stream"] for row in requests}),
        "requests": requests, "frames": frames}


def observe(pcap, keylog, port, mode, path, output, success=True, maxpost=16384):
    pcap, keylog, output = Path(pcap), Path(keylog), Path(output)
    output.mkdir(parents=True, exist_ok=True)
    assert pcap.stat().st_size > 24, "空抓包"
    keys = keylog.read_text().splitlines()
    labels = {line.split()[0] for line in keys if re.fullmatch(
        r"[A-Z0-9_]+ [a-fA-F0-9]{64} [a-fA-F0-9]+", line)}
    assert {"CLIENT_TRAFFIC_SECRET_0", "SERVER_TRAFFIC_SECRET_0"} <= labels, "无可用 TLS 解密密钥"
    command = [
        "tshark", "-n", "-2", "-r", str(pcap), "-d", f"tcp.port=={port},tls",
        "-o", f"tls.keylog_file:{keylog}", "-o", "tcp.desegment_tcp_streams:TRUE",
        "-o", "tcp.reassemble_out_of_order:TRUE",
        "-o", "tls.desegment_ssl_records:TRUE",
        "-o", "tls.desegment_ssl_application_data:TRUE",
        "-J", "frame tcp http2", "-T", "pdml"]
    (output / "tshark-command.json").write_text(json.dumps(command))
    (output / "tshark-version.txt").write_bytes(subprocess.check_output(["tshark", "--version"]))
    with (output / "tshark.pdml").open("wb") as raw:
        result = subprocess.run(command, stdout=raw, stderr=subprocess.PIPE, timeout=120)
    (output / "tshark.stderr").write_bytes(result.stderr)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert not re.search(r"cut short|truncat|malformed|decryption failed",
                         result.stderr.decode(errors="replace"), re.I), "tshark 拒绝不完整抓包"
    proof = parse(output / "tshark.pdml", mode, path, port, success, maxpost)
    proof.update(pcap_sha256=sha(pcap), keylog_sha256=sha(keylog),
                 pdml_sha256=sha(output / "tshark.pdml"),
                 observer_sha256=sha(__file__), port=port, base_path=path)
    (output / "observation.json").write_text(json.dumps(proof, indent=2))
    return proof


def main():
    parser = argparse.ArgumentParser()
    for name in ("pcap", "keylog", "out"):
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--mode", required=True, choices=("packet-up", "stream-up"))
    parser.add_argument("--path", required=True)
    parser.add_argument("--reject", action="store_true")
    arguments = parser.parse_args()
    result = observe(arguments.pcap, arguments.keylog, arguments.port,
                     arguments.mode, arguments.path, arguments.out, not arguments.reject)
    print(json.dumps({key: result[key] for key in (
        "schema", "mode", "post_count", "post_body_bytes", "tcp_connections", "pcap_sha256")}))


if __name__ == "__main__":
    main()
