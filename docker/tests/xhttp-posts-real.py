"""固定 Xray 的 TLS/Reality 实际回显与离线 POST 观察自检。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import signal
import socket
import socketserver
import ssl
import subprocess
import sys
import threading
import time
import uuid
import xml.etree.ElementTree as ET


USER = "11111111-1111-4111-8111-111111111111"
PRIVATE = "dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo"
PUBLIC = "hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo"
SID = "6ba85179e30d4fc2"
observer = runpy.run_path(str(Path(__file__).with_name("xhttp-post-observe.py")))
transfer = runpy.run_path(str(Path(__file__).with_name("stream-integrity-real.py")))


def port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def stop(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=4)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=4)


def launch(binary, config, prefix):
    prefix.with_suffix(".json").write_text(json.dumps(config, indent=2))
    log = prefix.with_suffix(".log").open("wb")
    process = subprocess.Popen([binary, "run", "-c", str(prefix.with_suffix(".json"))],
                               stdout=log, stderr=log,
                               env=dict(os.environ, XRAY_BUF_SPLICE="disable"))
    return process, log


def ready(process, listen):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        assert process.poll() is None, "Xray 启动失败"
        try:
            socket.create_connection(("127.0.0.1", listen), timeout=.1).close()
            return
        except OSError:
            time.sleep(.05)
    raise AssertionError("监听没有就绪")


def negative_checks(case):
    original = case / "decoded/tshark.pdml"
    report = json.loads((case / "case.json").read_text())
    rejected = []

    def expect(name, mutate):
        tree = ET.parse(original)
        mutate(tree)
        path = case / ("negative-" + name + ".pdml")
        tree.write(path)
        try:
            observer["parse"](path, report["mode"], report["path"], report["port"])
        except (AssertionError, ValueError):
            rejected.append(name)
        else:
            raise AssertionError("负控未拒绝：" + name)
        finally:
            path.unlink()

    def truncate(tree):
        item = observer["fields"](tree.getroot(), "frame.cap_len")[0]
        item.set("show", "1")

    def missing_end(tree):
        for item in observer["fields"](tree.getroot(), "http2.flags.end_stream"):
            item.set("show", "0")

    def response(tree):
        for item in observer["fields"](tree.getroot(), "http2.header"):
            if observer["one"](item, "http2.header.name") == ":status":
                observer["fields"](item, "http2.header.value")[0].set("show", "403")

    expect("truncated", truncate)
    expect("missing-end-stream", missing_end)
    expect("non-200", response)
    if report["mode"] == "packet-up":
        def sequence(tree):
            changed = 0
            for item in observer["fields"](tree.getroot(), "http2.header"):
                if observer["one"](item, "http2.header.name") == ":path":
                    value = observer["fields"](item, "http2.header.value")[0]
                    if value.get("show", "").rstrip("/").endswith("/1"):
                        value.set("show", value.get("show")[:-1] + "0")
                        changed += 1
            assert changed
        expect("duplicate-sequence", sequence)
    else:
        def reassembled(tree):
            changed = 0
            for frame in observer["fields"](tree.getroot(), "http2.stream"):
                if observer["fields"](frame, "http2.body.reassembled.length"):
                    value = observer["fields"](frame, "http2.data.data")[0]
                    value.set("value", value.get("value") + "00")
                    changed += 1
            assert changed
        expect("reassembled-body-corrupt", reassembled)
    return rejected


def verify_business(observed, proof, destination):
    posts = [row for row in observed["requests"] if row["method"] == "POST"]
    if observed["mode"] == "packet-up":
        posts.sort(key=lambda row: row["seq"])
    upstream = b"".join(bytes.fromhex(frame["data_hex"])
                        for row in posts for frame in row["request_data"])
    expected = (b"\x00" + uuid.UUID(USER).bytes + b"\x00\x01"
                + destination[1].to_bytes(2, "big") + b"\x01" + socket.inet_aton(destination[0]))
    assert upstream[:len(expected)] == expected, "真实 POST 的 VLESS 身份或目标不匹配"
    upload = upstream[len(expected):]
    assert len(upload) == proof["upload_bytes"], "真实 POST 的业务长度不匹配"
    assert hashlib.sha256(upload).hexdigest() == proof["sha256"], "真实 POST 的业务摘要不匹配"
    downloads = [row for row in observed["requests"] if row["method"] == "GET"]
    assert len(downloads) == 1
    downstream = b"".join(bytes.fromhex(frame["data_hex"])
                          for frame in downloads[0]["response_data"])
    assert downstream[:2] == b"\x00\x00", "VLESS 下行响应头不匹配"
    assert downstream[2:] == upload, "真实 HTTP/2 下行与上传字节不一致"


def negative_inputs(case, port):
    rejected = []
    pcap, keylog = case / "capture.pcap", case / "master.keys"
    for name in ("empty-pcap", "truncated-pcap", "missing-keylog"):
        artifact = case / ("negative-" + name)
        artifact.write_bytes(pcap.read_bytes()[:-1] if name == "truncated-pcap" else b"")
        try:
            observer["observe"](artifact if name != "missing-keylog" else pcap,
                                artifact if name == "missing-keylog" else keylog,
                                port, "packet-up", "/observe/", case / name)
        except AssertionError:
            rejected.append(name)
        else:
            raise AssertionError("真实输入负控未拒绝：" + name)
        finally:
            artifact.unlink()
    return rejected


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--xray", required=True)
    parser.add_argument("--out", type=Path, required=True)
    arguments = parser.parse_args()
    output = arguments.out
    output.mkdir(parents=True, exist_ok=True)
    output.chmod(0o700)
    os.umask(0o077)
    started = time.monotonic()
    version = subprocess.check_output([arguments.xray, "version"]).decode()
    assert version.startswith("Xray 26.3.27 ")
    cert, key = output / "target.crt", output / "target.key"
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                    "-days", "1", "-subj", "/CN=observe.padm.test",
                    "-addext", "subjectAltName=DNS:observe.padm.test",
                    "-keyout", str(key), "-out", str(cert)], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    context.set_alpn_protocols(["h2"])
    context.load_cert_chain(cert, key)

    class Target(socketserver.BaseRequestHandler):
        def handle(self):
            try:
                with context.wrap_socket(self.request, server_side=True) as connection:
                    connection.settimeout(2)
                    connection.recv(1)
            except (OSError, ssl.SSLError):
                pass

    echo = socketserver.ThreadingTCPServer(("127.0.0.1", 0), transfer["Echo"])
    target = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Target)
    for server in (echo, target):
        server.daemon_threads = True
        threading.Thread(target=server.serve_forever, daemon=True).start()
    proofs = []
    try:
        for security in ("reality", "tls"):
            for mode in ("packet-up", "stream-up"):
                case = output / (security + "-" + mode)
                case.mkdir(mode=0o700)
                public, socks = port(), port()
                path = "/observe/"
                keylog, pcap = case / "master.keys", case / "capture.pcap"
                settings = {"alpn": ["h2"], "certificates": [{
                    "certificateFile": str(cert), "keyFile": str(key)}]} if security == "tls" else {
                    "dest": "127.0.0.1:" + str(target.server_address[1]),
                    "serverNames": ["observe.padm.test"], "privateKey": PRIVATE, "shortIds": [SID]}
                server_config = {"log": {"loglevel": "debug"}, "inbounds": [{
                    "listen": "127.0.0.1", "port": public, "protocol": "vless",
                    "settings": {"clients": [{"id": USER}], "decryption": "none"},
                    "streamSettings": {"network": "xhttp", "security": security,
                        security + "Settings": settings,
                        "xhttpSettings": {"path": path, "mode": "auto",
                                          "scMaxEachPostBytes": 16384}}}],
                    "outbounds": [{"protocol": "freedom"}]}
                client_settings = {"serverName": "observe.padm.test", "masterKeyLog": str(keylog)}
                if security == "tls":
                    client_settings.update(alpn=["h2"], pinnedPeerCertSha256=hashlib.sha256(
                        ssl.PEM_cert_to_DER_cert(cert.read_text())).hexdigest())
                else:
                    client_settings.update(fingerprint="chrome", publicKey=PUBLIC, shortId=SID)
                client_config = {"log": {"loglevel": "debug"}, "inbounds": [{
                    "listen": "127.0.0.1", "port": socks, "protocol": "socks",
                    "settings": {"auth": "noauth", "udp": False}}], "outbounds": [{
                    "protocol": "vless", "settings": {"vnext": [{"address": "127.0.0.1",
                    "port": public, "users": [{"id": USER, "encryption": "none"}]}]},
                    "streamSettings": {"network": "xhttp", "security": security,
                    security + "Settings": client_settings, "xhttpSettings": {
                        "host": "observe.padm.test", "path": path, "mode": mode,
                        "extra": {"scMaxEachPostBytes": 16384}}}}]}
                processes = []
                capture = None
                capture_log = (case / "tcpdump.log").open("wb")
                try:
                    server, log = launch(arguments.xray, server_config, case / "server")
                    processes.append((server, log))
                    ready(server, public)
                    capture = subprocess.Popen(["tcpdump", "-i", "lo", "-U", "-B", "16384", "-s", "0",
                        "-w", str(pcap), "tcp", "port", str(public)],
                        stdout=capture_log, stderr=capture_log)
                    time.sleep(2)
                    assert capture.poll() is None
                    client, log = launch(arguments.xray, client_config, case / "client")
                    processes.append((client, log))
                    ready(client, socks)
                    with transfer["connect"](("127.0.0.1", socks), echo.server_address) as connection:
                        proof = transfer["exchange"](connection, 1048576)
                        connection.shutdown(socket.SHUT_WR)
                        connection.settimeout(5)
                        assert connection.recv(1) == b"", "回显结束后有额外字节"
                    time.sleep(.3)
                finally:
                    for process, log in reversed(processes):
                        stop(process)
                        log.close()
                    if capture is not None:
                        time.sleep(1)
                        capture.send_signal(signal.SIGINT)
                        capture.wait(timeout=5)
                    capture_log.close()
                assert re.search(r"^0 packets dropped by kernel$", (case / "tcpdump.log").read_text(),
                                 re.M), "抓包丢包"
                binding = {"security": security, "mode": mode, "port": public, "path": path,
                           "xray_sha256": observer["sha"](arguments.xray), "xray_version": version,
                           "client_config_sha256": observer["sha"](case / "client.json"),
                           "server_config_sha256": observer["sha"](case / "server.json"), **proof}
                (case / "case.json").write_text(json.dumps(binding, indent=2))
                observed = observer["observe"](pcap, keylog, public, mode, path, case / "decoded")
                verify_business(observed, proof, echo.server_address)
                if mode == "packet-up":
                    assert observed["post_count"] > 1
                else:
                    assert max(row["body_bytes"] for row in observed["requests"]) > 16384
                rejected = negative_checks(case)
                if security == "reality" and mode == "packet-up":
                    rejected.extend(negative_inputs(case, public))
                proofs.append({"case": case.name, "post_count": observed["post_count"],
                               "post_body_bytes": observed["post_body_bytes"],
                               "tcp_connections": observed["tcp_connections"], "negative_checks": rejected})
                print(json.dumps(proofs[-1]), flush=True)
        result = {"passed": True, "xray_version": version,
                  "xray_sha256": observer["sha"](arguments.xray), "cases": proofs,
                  "elapsed_seconds": round(time.monotonic() - started, 3)}
        (output / "selfcheck.json").write_text(json.dumps(result, indent=2))
        print(json.dumps(result), flush=True)
    except BaseException:
        for logfile in sorted(case.glob("*.log")):
            print(f"{logfile.name}:\n{logfile.read_text()[-2000:]}", file=sys.stderr)
        raise
    finally:
        for server in (echo, target):
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    main()
