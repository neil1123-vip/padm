#!/usr/bin/env python3
"""直接记录固定 Xray 的 XHTTP 外层 TLS/h2 首部。"""

import argparse
import hashlib
import json
from pathlib import Path
import socket
import ssl
import subprocess
import sys
import threading
import time

import h2
from h2.config import H2Configuration
from h2.connection import H2Connection
from h2.events import DataReceived, RequestReceived, ResponseReceived


HOST = "headers.padm.test"
PATH = "/probe/"
USER = "11111111-1111-4111-8111-111111111111"
MODES = ("stream-one", "stream-up", "packet-up")
FLAGS = (("default", None), ("true", True), ("false", False))


def unused_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def stop(process):
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=3)


def ready(process, port):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        assert process.poll() is None, f"Xray 提前退出 {process.returncode}"
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                return
        except OSError:
            time.sleep(0.02)
    raise AssertionError("Xray 未监听")


def read_exact(connection, length):
    result = b""
    while len(result) < length:
        part = connection.recv(length - len(result))
        assert part, "SOCKS 提前关闭"
        result += part
    return result


def xray_process(binary, config, prefix):
    config_path = prefix.with_suffix(".json")
    config_path.write_text(json.dumps(config))
    log = prefix.with_suffix(".log").open("wb")
    process = subprocess.Popen([binary, "run", "-c", str(config_path)],
                               stdout=log, stderr=log)
    return process, log


class Recorder:
    def __init__(self, certificate, key):
        self.context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.context.load_cert_chain(certificate, key)
        self.context.set_alpn_protocols(["h2"])
        self.listener = socket.socket()
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen()
        self.listener.settimeout(0.2)
        self.port = self.listener.getsockname()[1]
        self.condition = threading.Condition()
        self.records = []
        self.failures = []
        self.connections = []
        self.closed = threading.Event()
        self.workers = []
        self.thread = threading.Thread(target=self.accept, daemon=True)
        self.thread.start()

    def accept(self):
        while not self.closed.is_set():
            try:
                connection, _ = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            worker = threading.Thread(target=self.record, args=(connection,), daemon=True)
            self.workers.append(worker)
            worker.start()

    def record(self, connection):
        try:
            with self.context.wrap_socket(connection, server_side=True) as tls:
                self.connections.append(tls)
                assert tls.selected_alpn_protocol() == "h2"
                tls.settimeout(0.2)
                protocol = H2Connection(H2Configuration(client_side=False, header_encoding="utf-8"))
                protocol.initiate_connection()
                tls.sendall(protocol.data_to_send())
                while not self.closed.is_set():
                    try:
                        data = tls.recv(65535)
                    except socket.timeout:
                        continue
                    if not data:
                        break
                    for event in protocol.receive_data(data):
                        if isinstance(event, RequestReceived):
                            headers = dict(event.headers)
                            with self.condition:
                                self.records.append(headers)
                                self.condition.notify_all()
                            # 仅返回握手所需首部，不解析或转发 VLESS 业务。
                            protocol.send_headers(event.stream_id, [
                                (":status", "200"), ("content-type", "text/event-stream")])
                        elif isinstance(event, DataReceived):
                            protocol.acknowledge_received_data(event.flow_controlled_length, event.stream_id)
                    outgoing = protocol.data_to_send()
                    if outgoing:
                        tls.sendall(outgoing)
        except Exception as error:
            if not self.closed.is_set():
                with self.condition:
                    self.failures.append(repr(error))
                    self.condition.notify_all()

    def wait_requests(self, mode):
        required = {"POST"} if mode == "stream-one" else {"POST", "GET"}
        with self.condition:
            complete = self.condition.wait_for(
                lambda: required <= {row[":method"] for row in self.records}, timeout=8)
            assert complete, f"{mode} 未收齐 {required}: {self.records}; {self.failures}"
            return list(self.records)

    def close(self):
        self.closed.set()
        self.listener.close()
        for connection in self.connections:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        self.thread.join(timeout=1)
        for worker in self.workers:
            worker.join(timeout=1)


def client_case(binary, output, certificate, key, mode, label, flag):
    recorder = Recorder(certificate, key)
    socks_port = unused_port()
    extra = {"xPaddingBytes": 16}
    if flag is not None:
        extra["noGRPCHeader"] = flag
    certificate_hash = hashlib.sha256(
        ssl.PEM_cert_to_DER_cert(certificate.read_text())).hexdigest()
    config = {"log": {"loglevel": "debug"},
              "inbounds": [{"listen": "127.0.0.1", "port": socks_port, "protocol": "socks",
                            "settings": {"auth": "noauth", "udp": False}}],
              "outbounds": [{"protocol": "vless", "settings": {"vnext": [{
                  "address": "127.0.0.1", "port": recorder.port,
                  "users": [{"id": USER, "encryption": "none"}]}]},
                  "streamSettings": {"network": "xhttp", "security": "tls",
                      "tlsSettings": {"serverName": HOST, "pinnedPeerCertSha256": certificate_hash, "alpn": ["h2"]},
                      "xhttpSettings": {"host": HOST, "path": PATH, "mode": mode, "extra": extra}}}]}
    process, log = xray_process(binary, config, output / f"client-{mode}-{label}")
    try:
        ready(process, socks_port)
        with socket.create_connection(("127.0.0.1", socks_port), timeout=8) as socks:
            socks.sendall(b"\x05\x01\x00")
            assert read_exact(socks, 2) == b"\x05\x00"
            socks.sendall(b"\x05\x01\x00\x01\x7f\x00\x00\x01\x00\x09")
            response = read_exact(socks, 4)
            assert response[:2] == b"\x05\x00", response
            read_exact(socks, 6 if response[3] == 1 else 18)
            socks.sendall(b"XHTTP-header-probe")
            records = recorder.wait_requests(mode)
        rows = []
        for headers in records:
            method = headers[":method"]
            content_type = headers.get("content-type")
            expected = "application/grpc" if method == "POST" and mode != "packet-up" and flag is not True else None
            assert content_type == expected, (mode, label, method, content_type, expected)
            rows.append({"method": method, "content_type": content_type})
        return {"side": "client", "mode": mode, "flag": label, "requests": rows}
    finally:
        stop(process)
        log.close()
        recorder.close()


def response_headers(port, method, path, certificate, packet=False):
    context = ssl.create_default_context(cafile=certificate)
    context.set_alpn_protocols(["h2"])
    with socket.create_connection(("127.0.0.1", port), timeout=5) as connection:
        with context.wrap_socket(connection, server_hostname=HOST) as tls:
            assert tls.selected_alpn_protocol() == "h2"
            protocol = H2Connection(H2Configuration(client_side=True, header_encoding="utf-8"))
            protocol.initiate_connection()
            headers = [(":method", method), (":scheme", "https"), (":authority", HOST),
                       (":path", path), ("referer", f"https://{HOST}{PATH}?x_padding=" + "X" * 16)]
            protocol.send_headers(1, headers, end_stream=method == "GET")
            if packet:
                protocol.send_data(1, b"probe", end_stream=True)
            tls.sendall(protocol.data_to_send())
            while True:
                data = tls.recv(65535)
                assert data, "XHTTP 服务端未返回响应 HEADERS"
                for event in protocol.receive_data(data):
                    if isinstance(event, ResponseReceived):
                        return dict(event.headers)


def server_case(binary, output, certificate, key, mode, label, flag):
    port = unused_port()
    extra = {"xPaddingBytes": 16}
    if flag is not None:
        extra["noSSEHeader"] = flag
    config = {"log": {"loglevel": "debug"},
              "inbounds": [{"listen": "127.0.0.1", "port": port, "protocol": "vless",
                  "settings": {"clients": [{"id": USER}], "decryption": "none"},
                  "streamSettings": {"network": "xhttp", "security": "tls",
                      "tlsSettings": {"alpn": ["h2"], "certificates": [
                          {"certificateFile": str(certificate), "keyFile": str(key)}]},
                      "xhttpSettings": {"host": HOST, "path": PATH, "mode": mode, "extra": extra}}}],
              "outbounds": [{"protocol": "blackhole"}]}
    process, log = xray_process(binary, config, output / f"server-{mode}-{label}")
    try:
        ready(process, port)
        session = "22222222-2222-4222-8222-222222222222"
        method = "POST" if mode == "stream-one" else "GET"
        path = PATH if mode == "stream-one" else PATH + session
        observed = response_headers(port, method, path, certificate)
        expected = None if flag is True else "text/event-stream"
        assert observed[":status"] == "200" and observed.get("content-type") == expected, observed
        rows = [{"method": method, "status": observed[":status"],
                 "content_type": observed.get("content-type")}]
        if mode != "stream-one":
            upload_path = PATH + "33333333-3333-4333-8333-333333333333"
            if mode == "packet-up":
                upload_path += "/0"
            observed = response_headers(port, "POST", upload_path, certificate, packet=mode == "packet-up")
            assert observed[":status"] == "200" and observed.get("content-type") != "text/event-stream", observed
            rows.append({"method": "POST", "status": observed[":status"],
                         "content_type": observed.get("content-type")})
        return {"side": "server", "mode": mode, "flag": label, "responses": rows}
    finally:
        stop(process)
        log.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--xray", required=True)
    parser.add_argument("--out", type=Path, required=True)
    arguments = parser.parse_args()
    arguments.out.mkdir(parents=True, exist_ok=True)
    certificate, key = arguments.out / "site.crt", arguments.out / "site.key"
    version = subprocess.check_output([arguments.xray, "version"]).decode()
    assert version.startswith("Xray 26.3.27 "), "Xray 版本不匹配"
    evidence = {"xray_version": version,
                "xray_sha256": hashlib.sha256(Path(arguments.xray).read_bytes()).hexdigest(),
                "h2_version": h2.__version__, "transport": "loopback TLS/h2", "cases": []}
    try:
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                        "-subj", f"/CN={HOST}", "-addext", f"subjectAltName=DNS:{HOST}",
                        "-keyout", str(key), "-out", str(certificate)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for mode in MODES:
            for label, flag in FLAGS:
                for function in (client_case, server_case):
                    row = function(arguments.xray, arguments.out, certificate, key, mode, label, flag)
                    evidence["cases"].append(row)
                    print("docker-xhttp-headers-observed=" + json.dumps(row), flush=True)
        assert len(evidence["cases"]) == 18
        evidence["passed"] = True
        print(f"docker-xhttp-headers-real-ok: cases=18 modes=stream-one/stream-up/packet-up "
              f"flags=default/true/false tls=verified-h2 h2={h2.__version__} "
              f"xray-sha256={evidence['xray_sha256']}", flush=True)
    except BaseException:
        for log in sorted(arguments.out.glob("*.log")):
            print(f"{log.name}:\n{log.read_text()[-3000:]}", file=sys.stderr)
        raise
    finally:
        (arguments.out / "headers.json").write_text(json.dumps(evidence, indent=2))
        key.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
