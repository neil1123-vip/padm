#!/usr/bin/env python3
"""固定 Xray 的独立下行身份、TLS/h2/h3、共享会话及大流完整性。"""

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import runpy
import socket
import socketserver
import ssl
import subprocess
import sys
import threading
import urllib.parse


helpers = runpy.run_path(str(Path(__file__).with_name("xhttp-headers-real.py")))
transfers = runpy.run_path(str(Path(__file__).with_name("stream-integrity-real.py")))
unused_port, stop, ready, read_exact, xray_process = (
    helpers[name] for name in ("unused_port", "stop", "ready", "read_exact", "xray_process"))
USER = helpers["USER"]
MODES = ("auto", "stream-one", "packet-up", "stream-up")
PRIMARY_KEY = "dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo"
PRIMARY_PUBLIC = "hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo"
PRIMARY_SID, DOWN_SID = "6ba85179e30d4fc2", "7ca85179e30d4fc3"


class Echo(socketserver.BaseRequestHandler):
    def handle(self):
        while data := self.request.recv(65536):
            self.request.sendall(data)


def raw_front(port, backend, security, settings):
    return {"listen": "127.0.0.1", "port": port, "protocol": "dokodemo-door",
            "settings": {"address": "127.0.0.1", "port": backend, "network": "tcp"},
            "streamSettings": {"network": "raw", "security": security,
                               security + "Settings": settings}}


def projection(output, label, upload, download):
    spec = {"subscription": {"enabled": True}, "core": {"protocols": [{
        "id": 2, "listener_id": "entry-download", "server": "127.0.0.1", "uuid": USER,
        "name": label, "public_port": upload,
        "reality": {"server_name": "upload.padm.test", "public_key": PRIMARY_PUBLIC,
                    "private_key": PRIMARY_KEY, "short_id": PRIMARY_SID},
        "xhttp": {"path": "/shared/", "host": "upload.padm.test", "mode": "auto",
                  "scMaxEachPostBytes": 16384,
                  "download": download}}]}}
    spec_path, links_path = output / (label + ".spec.json"), output / (label + ".links")
    spec_path.write_text(json.dumps(spec))
    root = Path(__file__).resolve().parents[2]
    subprocess.run(["bash", "-e", "-c",
                    'DOCKER_BUNDLE_SOURCE_ROOT="$1"; source "$1/docker/lib/services.sh"; '
                    'dockerGenerateSubscription "$2" "$3"',
                    "_", str(root), str(spec_path), str(links_path)], check=True)
    uri = urllib.parse.urlsplit(links_path.read_text().strip())
    query = {key: value[0] for key, value in urllib.parse.parse_qs(uri.query).items()}
    assert uri.scheme == "vless" and uri.hostname == "127.0.0.1" and uri.port == upload
    assert uri.username == USER
    extra = json.loads(query["extra"])
    assert set(extra) == {"downloadSettings", "scMaxEachPostBytes"}, extra
    assert extra["scMaxEachPostBytes"] == 16384
    projected = extra["downloadSettings"]
    assert projected["address"] == download["address"] and projected["port"] == download["port"]
    assert projected["network"] == "xhttp" and projected["security"] == download["security"]
    assert projected["xhttpSettings"] == {
        "path": download["path"], "host": download["host"], "mode": download["mode"]}
    return {"network": query["type"], "security": query["security"],
            "realitySettings": {"serverName": query["sni"], "fingerprint": query["fp"],
                               "publicKey": query["pbk"], "shortId": query["sid"]},
            "xhttpSettings": {"path": query["path"], "host": query["host"], "mode": query["mode"],
                              "extra": extra}}


def exchange(binary, output, label, upload, stream, echo_port, success=True, bulk=False):
    socks_port = unused_port()
    config = {"log": {"loglevel": "debug"},
              "inbounds": [{"listen": "127.0.0.1", "port": socks_port, "protocol": "socks",
                            "settings": {"auth": "noauth", "udp": False}}],
              "outbounds": [{"protocol": "vless", "settings": {"vnext": [{
                  "address": "127.0.0.1", "port": upload,
                  "users": [{"id": USER, "encryption": "none"}]}]}, "streamSettings": stream}]}
    process, log = xray_process(binary, config, output / ("client-" + label))
    received = b""
    bulk_proofs = []
    try:
        ready(process, socks_port)
        try:
            with socket.create_connection(("127.0.0.1", socks_port), timeout=3) as socks:
                socks.settimeout(4 if success else 0.8)
                socks.sendall(b"\x05\x01\x00")
                assert read_exact(socks, 2) == b"\x05\x00"
                socks.sendall(b"\x05\x01\x00\x01\x7f\x00\x00\x01" + echo_port.to_bytes(2, "big"))
                response = read_exact(socks, 4)
                assert response[:2] == b"\x05\x00", response
                read_exact(socks, 6 if response[3] == 1 else 18)
                payload = ("padm-xhttp-download:" + label + ":").encode() * 1024
                socks.sendall(payload)
                # 负例只要泄漏一个业务字节就失败，避免部分正文后断连被误记为拒绝。
                received = read_exact(socks, len(payload)) if success else socks.recv(1)
                if success:
                    assert received == payload, (label, len(received))
                if bulk:
                    for size in (1048576, 8388608):
                        bulk_proofs.append(transfers["exchange"](socks, size))
        except (OSError, AssertionError) as error:
            if success:
                raise AssertionError(f"{label} 业务回显失败") from error
        if not success:
            assert not received, f"{label} 破坏下行后业务仍成功"
        print(f"docker-xhttp-download-observed={label} echo={success}", flush=True)
        return {"case": label, "echo": success, "transfers": bulk_proofs}
    finally:
        stop(process)
        log.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--xray", required=True)
    parser.add_argument("--out", type=Path, required=True)
    arguments = parser.parse_args()
    output = arguments.out
    output.mkdir(parents=True, exist_ok=True)
    certificate, key = output / "site.crt", output / "site.key"
    version = subprocess.check_output([arguments.xray, "version"]).decode()
    assert version.startswith("Xray 26.3.27 "), "Xray 版本不匹配"
    evidence = {"xray_version": version, "cases": [], "shared_backend": True}
    processes = []
    transfers["selfcheck"]()
    echo = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Echo)
    echo.daemon_threads = True
    threading.Thread(target=echo.serve_forever, daemon=True).start()
    try:
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                        "-subj", "/CN=download.padm.test", "-addext",
                        "subjectAltName=DNS:download.padm.test,DNS:upload.padm.test",
                        "-keyout", str(key), "-out", str(certificate)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        pair = subprocess.check_output([arguments.xray, "x25519"]).decode()
        values = [line.split(":", 1)[1].strip() for line in pair.splitlines() if ":" in line]
        assert len(values) >= 2
        down_key, down_public = values[:2]
        assert down_key != PRIMARY_KEY and down_public != PRIMARY_PUBLIC
        backend, upload, reality_down, tls_down, target = (unused_port() for _ in range(5))
        tls = {"alpn": ["h2"], "certificates": [
            {"certificateFile": str(certificate), "keyFile": str(key)}]}
        config = {"log": {"loglevel": "debug"},
                  "inbounds": [
                      {"listen": "127.0.0.1", "port": backend, "protocol": "vless",
                       "settings": {"clients": [{"id": USER}], "decryption": "none"},
                       "streamSettings": {"network": "xhttp", "security": "none",
                                          "xhttpSettings": {"path": "/shared/", "mode": "auto",
                                                            "scMaxEachPostBytes": 16384}}},
                      raw_front(target, echo.server_address[1], "tls", tls),
                      raw_front(upload, backend, "reality", {
                          "dest": f"127.0.0.1:{target}", "serverNames": ["upload.padm.test"],
                          "privateKey": PRIMARY_KEY, "shortIds": [PRIMARY_SID]}),
                      raw_front(reality_down, backend, "reality", {
                          "dest": f"127.0.0.1:{target}", "serverNames": ["download.padm.test"],
                          "privateKey": down_key, "shortIds": [DOWN_SID]})],
                  "outbounds": [{"protocol": "freedom"}]}
        server_config = output / "server.json"
        server_config.write_text(json.dumps(config))
        log = (output / "server.log").open("wb")
        # 固定核心的 dokodemo splice 会绕过 Reality 加密写入；前置夹具须保留 TLS 包装层。
        process = subprocess.Popen([arguments.xray, "run", "-c", str(server_config)],
                                   stdout=log, stderr=log,
                                   env=dict(os.environ, XRAY_BUF_SPLICE="disable"))
        processes.append((process, log))
        ready(process, upload)
        # TLS 前置把 HTTP/2 与 HTTP/3 都送入同一个 XHTTP handler，避免伪造独立会话成功。
        caddy = {"admin": {"disabled": True},
                 "apps": {"http": {"servers": {"edge": {
                     "listen": [f"127.0.0.1:{tls_down}"], "protocols": ["h1", "h2", "h3"],
                     "tls_connection_policies": [{}],
                     "routes": [{"handle": [{"handler": "reverse_proxy",
                         "flush_interval": -1, "upstreams": [{"dial": f"127.0.0.1:{backend}"}],
                         "transport": {"protocol": "http", "versions": ["h2c"]}}]}]}}},
                          "tls": {"certificates": {"load_files": [{
                              "certificate": str(certificate), "key": str(key)}]}}}}
        caddy_config = output / "caddy.json"
        caddy_config.write_text(json.dumps(caddy))
        caddy_log = (output / "caddy.log").open("wb")
        caddy_process = subprocess.Popen(["caddy", "run", "--config", str(caddy_config)],
                                         stdout=caddy_log, stderr=caddy_log)
        processes.append((caddy_process, caddy_log))
        ready(caddy_process, tls_down)
        certificate_hash = hashlib.sha256(
            ssl.PEM_cert_to_DER_cert(certificate.read_text())).hexdigest()
        for transport in ("reality", "h2", "h3"):
            download = {"address": "127.0.0.1", "port": reality_down if transport == "reality" else tls_down,
                        "security": "reality" if transport == "reality" else "tls",
                        "host": "download.padm.test", "path": "/shared/", "server_name": "download.padm.test"}
            if transport == "reality":
                download.update(public_key=down_public, short_id=DOWN_SID)
            else:
                download["alpn"] = [transport]
            for mode in MODES:
                download["mode"] = mode
                label = transport + "-" + mode
                stream = projection(output, label, upload, download)
                if transport != "reality":
                    # 仅为本地自签证书增加固定 pin；生产投影及身份校验保持启用。
                    stream["xhttpSettings"]["extra"]["downloadSettings"]["tlsSettings"][
                        "pinnedPeerCertSha256"] = certificate_hash
                evidence["cases"].append(exchange(arguments.xray, output, label,
                    upload, stream, echo.server_address[1],
                    bulk=mode in ("packet-up", "stream-up")))
                observed_log = (output / ("client-" + label + ".log")).read_text()
                expected_http = "3" if transport == "h3" else "2"
                assert f"HTTP version {expected_http}, host download.padm.test" in observed_log, observed_log[-4000:]
            broken = copy.deepcopy(stream)
            broken["xhttpSettings"]["extra"]["downloadSettings"]["port"] = 9
            evidence["cases"].append(exchange(arguments.xray, output, transport + "-broken-port",
                upload, broken, echo.server_address[1], success=False))
            if transport == "reality":
                for name, value in (("publicKey", PRIMARY_PUBLIC), ("shortId", PRIMARY_SID),
                                    ("serverName", "upload.padm.test")):
                    broken = copy.deepcopy(stream)
                    broken["xhttpSettings"]["extra"]["downloadSettings"]["realitySettings"][name] = value
                    evidence["cases"].append(exchange(arguments.xray, output, "reality-broken-" + name,
                        upload, broken, echo.server_address[1], success=False))
            else:
                broken = copy.deepcopy(stream)
                broken["xhttpSettings"]["extra"]["downloadSettings"]["tlsSettings"][
                    "pinnedPeerCertSha256"] = "00" * 32
                evidence["cases"].append(exchange(arguments.xray, output, transport + "-broken-certificate",
                    upload, broken, echo.server_address[1], success=False))
        bulk_cases = [item for item in evidence["cases"] if item["transfers"]]
        assert len(bulk_cases) == 6 and all(
            [proof["upload_bytes"] for proof in item["transfers"]] == [1048576, 8388608]
            and all(proof["upload_bytes"] == proof["download_bytes"] for proof in item["transfers"])
            for item in bulk_cases)
        evidence["passed"] = True
        print("docker-xhttp-download-real-ok: independent-reality=key/sid/sni tls=verified-h2/h3 "
              "download-modes=auto/stream-one/packet-up/stream-up backend=shared "
              f"echo=12 rejection=8 cases={len(evidence['cases'])} "
              "bulk=12 sizes=1MiB/8MiB packet-limit=16KiB digest=sha256", flush=True)
    except BaseException:
        for path in sorted(output.glob("*.log")):
            print(f"{path.name}:\n{path.read_text()[-4000:]}", file=sys.stderr)
        raise
    finally:
        for process, log in reversed(processes):
            stop(process)
            log.close()
        echo.shutdown()
        echo.server_close()
        (output / "download.json").write_text(json.dumps(evidence, indent=2))
        key.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
