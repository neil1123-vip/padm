#!/usr/bin/env python3
import contextlib
import copy
import io
import json
import os
from pathlib import Path
import runpy
import socket
import socketserver
import ssl
import subprocess
import tempfile
import threading
import time
import urllib.parse
from unittest.mock import MagicMock, patch


ROOT = Path(__file__).resolve().parents[2]
XRAY, MIHOMO = "/routing-cores/xray", "/uri-client/mihomo"
helpers = runpy.run_path(str(Path(__file__).with_name("routing-socks5-real.py")))
Server, Destination, port, connect = (
    helpers[name] for name in ("Server", "Destination", "port", "connect"))
UUID = "11111111-1111-4111-8111-111111111111"
PRIVATE_KEY = "dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo"
PUBLIC_KEY = "hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo"
SECRETS = [PRIVATE_KEY]
SHELL = r'''
source "$1/install-docker.sh"
dockerManifestImageReference() { printf '%s\n' fixture-image; }
dockerSetupTool() { /routing-cores/xray "${@:2}"; }
# 只替换容器调度，继续执行生产配对校验的原始静态 Python 与 stdin。
docker() {
    [[ "${1:-}" == run ]] || return 2
    while [[ "$#" -gt 0 && "$1" != --entrypoint ]]; do shift; done
    [[ "${2:-}" == python3 ]] || return 2
    shift 2
    [[ "${1:-}" == fixture-image && "${2:-}" == -c ]] || return 2
    shift
    python3 "$@"
}
case "$2" in
    generate) dockerEditVlessEncryptionGenerate "$3" "$4" ;;
    validate) dockerVlessEncryptionValidate "$3" fixture-image ;;
    render)
        dockerGenerateXrayConfig "$3" "$4"
        dockerGenerateSubscription "$3" "$5"
        ;;
    *) exit 2 ;;
esac
'''


def scrub(value):
    for secret in sorted(SECRETS, key=len, reverse=True):
        value = value.replace(secret, "<redacted>")
    return value


def checked(arguments, *, accepted=True):
    value = subprocess.run(arguments, capture_output=True, timeout=20)
    assert (value.returncode == 0) == accepted, scrub(
        (value.stdout + value.stderr).decode(errors="replace"))
    return value.stdout


def shell(action, *arguments, accepted=True):
    return checked(["bash", "-Eeuo", "pipefail", "-c", SHELL,
                    "test", str(ROOT), action, *map(str, arguments)], accepted=accepted)


def write(path, value):
    path.write_text(json.dumps(value), encoding="utf-8")
    path.chmod(0o600)


def wait_port(local, process, logfile):
    deadline = time.monotonic() + 5
    while True:
        assert process.poll() is None, scrub(logfile.read_text(errors="replace"))
        try:
            with socket.create_connection(("127.0.0.1", local), timeout=0.1):
                return
        except OSError:
            assert time.monotonic() < deadline, "核心监听超时"
            time.sleep(0.03)


@contextlib.contextmanager
def running(arguments, local, logfile):
    with logfile.open("wb") as stream:
        process = subprocess.Popen(arguments, stdout=stream, stderr=stream)
    try:
        wait_port(local, process, logfile)
        yield
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)


class Target(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            self.request.settimeout(3)
            with self.server.context.wrap_socket(self.request, server_side=True) as stream:
                stream.recv(4096)
                stream.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        except (OSError, ssl.SSLError):
            pass


def xray_client(uri, local):
    parsed = urllib.parse.urlsplit(uri)
    query = {key: values[0] for key, values in urllib.parse.parse_qs(parsed.query).items()}
    user = {"id": parsed.username, "encryption": query["encryption"]}
    if "flow" in query:
        user["flow"] = query["flow"]
    stream = {
        "network": query["type"], "security": query["security"],
        "realitySettings": {
            "serverName": query["sni"], "fingerprint": query["fp"],
            "publicKey": query["pbk"], "shortId": query["sid"],
        },
    }
    if query["type"] == "xhttp":
        stream["xhttpSettings"] = {key: query[key] for key in ("path", "host", "mode")}
        if "extra" in query:
            stream["xhttpSettings"]["extra"] = json.loads(query["extra"])
    return {
        "log": {"loglevel": "debug"},
        "inbounds": [{"listen": "127.0.0.1", "port": local, "protocol": "socks",
                      "settings": {"auth": "noauth", "udp": False}}],
        "outbounds": [{"protocol": "vless", "settings": {"vnext": [{
            "address": parsed.hostname, "port": parsed.port, "users": [user],
        }]}, "streamSettings": stream}],
    }


def client_projection_check():
    extra = {"noSSEHeader": True, "xmux": {"maxConcurrency": "16-32"}}
    query = {"encryption": "none", "type": "xhttp", "security": "reality",
             "sni": "target.padm.test", "fp": "chrome", "pbk": PUBLIC_KEY,
             "sid": "6ba85179e30d4fc2", "path": "/check", "host": "target.padm.test",
             "mode": "packet-up", "extra": json.dumps(extra)}
    uri = f"vless://{UUID}@127.0.0.1:2444?" + urllib.parse.urlencode(query)
    actual = xray_client(uri, 2080)["outbounds"][0]["streamSettings"]["xhttpSettings"]
    assert actual == {key: query[key] for key in ("path", "host", "mode")} | {"extra": extra}
    del query["extra"]
    uri = f"vless://{UUID}@127.0.0.1:2444?" + urllib.parse.urlencode(query)
    assert "extra" not in xray_client(uri, 2080)["outbounds"][0]["streamSettings"]["xhttpSettings"]


def connection_completion_check():
    for status, body, expected in ((200, b"routing-destination-ok", True),
                                   (503, b"routing-destination-ok", False),
                                   (200, b"wrong-body", False)):
        response = (f"HTTP/1.1 {status} Test\r\nContent-Length: {len(body)}\r\n\r\n".encode()
                    + body)
        connection = MagicMock()
        connection.__enter__.return_value = connection
        # 正文之后不返回 EOF，精确复现代理连接尚未关闭的误判。
        connection.recv.side_effect = [
            b"\x05\x00", b"\x05\x00\x00\x01", bytes(6), response, TimeoutError("no EOF")]
        connection.makefile.return_value = io.BytesIO(response)
        with patch.object(socket, "create_connection", return_value=connection):
            assert connect("127.0.0.1", 2080, 443) is expected
        assert connection.recv.call_count == 3, "HTTP 正文完成后仍等待 TCP EOF"


def probe(root, uri, client, name, origin, allowed):
    directory = root / name
    directory.mkdir(mode=0o700)
    local = port("127.0.0.1")
    config = directory / "config.json"
    source = directory / "provider.txt"
    if client == "xray":
        write(config, xray_client(uri, local))
        arguments = [XRAY, "run", "-c", str(config)]
        checked([XRAY, "run", "-test", "-c", str(config)])
    else:
        source.write_text(uri + "\n", encoding="utf-8")
        source.chmod(0o600)
        write(config, {
            "mode": "rule", "log-level": "debug", "ipv6": False,
            "proxy-providers": {"source": {
                "type": "file", "path": str(source), "health-check": {"enable": False},
                "override": {"ip-version": "ipv4"},
            }},
            "proxy-groups": [{"name": "entry", "type": "select", "use": ["source"]}],
            "listeners": [{"name": "entry", "type": "socks", "listen": "127.0.0.1",
                           "port": local, "proxy": "entry"}],
            "rules": ["MATCH,REJECT"],
        })
        arguments = [MIHOMO, "-d", str(directory), "-f", str(config)]
        checked([*arguments, "-t"])
    before = origin.accepted
    with running(arguments, local, directory / "client.log"):
        try:
            connected = connect("127.0.0.1", local, origin.server_address[1])
        except (OSError, EOFError, AssertionError):
            connected = False
    if connected != allowed:
        # 临时目录退出后即删除，失败时保留脱敏握手日志以区分配置错误与超时。
        logs = [directory / "client.log", *sorted(root.glob("*.log"))]
        diagnostic = "\n".join(path.name + ":\n" + scrub(path.read_text(errors="replace"))[-4000:]
                               for path in logs if path.is_file())
        raise AssertionError(name + " 实际连接结果不符\n" + diagnostic)
    assert origin.accepted == before + int(allowed), name + " 目标连接计数不符"
    if client == "mihomo":
        assert source.read_bytes() == (uri + "\n").encode(), "客户端修改了原始 URI"


def remember(spec):
    for item in spec["core"]["protocols"]:
        SECRETS.extend(item.get("vless_encryption", {}).values())


def render(root, spec_file, label):
    config_path, links = root / (label + ".json"), root / (label + ".txt")
    shell("render", spec_file, config_path, links)
    config = json.loads(config_path.read_text())
    config["log"] = {"loglevel": "debug"}
    write(config_path, config)
    checked([XRAY, "run", "-test", "-c", str(config_path)])
    uris = links.read_text().splitlines()
    assert len(uris) == 2 and all(uri.startswith("vless://") for uri in uris)
    return config_path, uris


def check(root):
    cert, key = root / "target.crt", root / "target.key"
    checked(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
             "-subj", "/CN=target.padm.test", "-addext", "subjectAltName=DNS:target.padm.test",
             "-keyout", str(key), "-out", str(cert)])
    target_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    target_context.minimum_version = ssl.TLSVersion.TLSv1_3
    target_context.set_alpn_protocols(["h2", "http/1.1"])
    target_context.load_cert_chain(str(cert), str(key))
    with Server(("127.0.0.1", 0), Target) as target, Server(("127.0.0.1", 0), Destination) as origin:
        target.context = target_context
        origin.accepted, origin.received = 0, []
        for server in (target, origin):
            threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.05},
                             daemon=True).start()
        try:
            ports = [port("127.0.0.1"), port("127.0.0.1")]
            assert len(set(ports)) == 2
            protocols = []
            for identifier, name, local in zip((1, 2), ("vision", "xhttp"), ports):
                item = {
                    "id": identifier, "core": "xray", "listener_id": "entry-" + name,
                    "server": "127.0.0.1", "public_port": local, "address_families": ["ipv4"],
                    "name": name, "uuid": UUID,
                    "reality": {"server_name": "target.padm.test", "target_host": "127.0.0.1",
                                "target_port": target.server_address[1], "private_key": PRIVATE_KEY,
                                "public_key": PUBLIC_KEY, "short_id": "6ba85179e30d4fc2"},
                }
                if name == "xhttp":
                    item["xhttp"] = {"path": "/padm-check", "host": "target.padm.test", "mode": "auto"}
                protocols.append(item)
            spec = {
                "schema_version": 3, "core": {"type": "xray", "secondary_type": None, "protocols": protocols},
                "tls": None, "subscription": {"enabled": True, "token": "0123456789abcdef"},
                "host_integrations": [],
            }
            spec_file = root / "spec.json"
            write(spec_file, spec)
            baseline_config, baseline_uris = render(root, spec_file, "baseline")
            with running([XRAY, "run", "-c", str(baseline_config)], ports[0], root / "baseline.log"):
                for index, uri in enumerate(baseline_uris):
                    for client in ("xray", "mihomo"):
                        probe(root, uri, client, f"baseline-{index}-{client}", origin, True)
            shell("generate", spec_file, "entry-vision")
            spec = json.loads(spec_file.read_text())
            remember(spec)
            assert "vless_encryption" not in spec["core"]["protocols"][1]
            shell("validate", spec_file)
            scoped_config, scoped_uris = render(root, spec_file, "one-entry")
            assert scoped_uris[1] == baseline_uris[1], "启用 Vision 改动了 XHTTP"
            with running([XRAY, "run", "-c", str(scoped_config)], ports[0], root / "one-entry.log"):
                for index, uri in enumerate(scoped_uris):
                    for client in ("xray", "mihomo"):
                        probe(root, uri, client, f"one-entry-{index}-{client}", origin, True)
            shell("generate", spec_file, "entry-xhttp")
            spec = json.loads(spec_file.read_text())
            remember(spec)
            shell("validate", spec_file)
            wrong_file = root / "wrong.json"
            wrong = copy.deepcopy(spec)
            wrong["core"]["protocols"][0]["vless_encryption"]["encryption"] = (
                wrong["core"]["protocols"][1]["vless_encryption"]["encryption"])
            write(wrong_file, wrong)
            shell("validate", wrong_file, accepted=False)
            encrypted_config, encrypted_uris = render(root, spec_file, "encrypted")
            with running([XRAY, "run", "-c", str(encrypted_config)], ports[0], root / "encrypted.log"):
                for index, uri in enumerate(encrypted_uris):
                    parsed = urllib.parse.urlsplit(uri)
                    query = urllib.parse.parse_qs(parsed.query)
                    query["encryption"] = [spec["core"]["protocols"][1 - index]["vless_encryption"]["encryption"]]
                    wrong_uri = urllib.parse.urlunsplit(parsed._replace(
                        query=urllib.parse.urlencode(query, doseq=True)))
                    for client in ("xray", "mihomo"):
                        probe(root, uri, client, f"encrypted-{index}-{client}", origin, True)
                        probe(root, wrong_uri, client, f"wrong-pair-{index}-{client}", origin, False)
                        probe(root, baseline_uris[index], client, f"old-none-{index}-{client}", origin, False)
            log = (root / "encrypted.log").read_text(errors="replace")
            assert "ML-KEM-768 handshake failed > chacha20poly1305: message authentication failed" in log
            for item in spec["core"]["protocols"]:
                del item["vless_encryption"]
            write(spec_file, spec)
            shell("validate", spec_file)
            restored_config, restored_uris = render(root, spec_file, "restored")
            assert json.loads(restored_config.read_text()) == json.loads(baseline_config.read_text())
            assert restored_uris == baseline_uris
            with running([XRAY, "run", "-c", str(restored_config)], ports[0], root / "restored.log"):
                for index, uri in enumerate(restored_uris):
                    for client in ("xray", "mihomo"):
                        probe(root, uri, client, f"restored-{index}-{client}", origin, True)
            assert origin.accepted == len(origin.received) == 16
        finally:
            for server in (target, origin):
                server.shutdown()


if __name__ == "__main__":
    try:
        client_projection_check()
        connection_completion_check()
        xray_version = checked([XRAY, "version"]).decode().splitlines()[0]
        mihomo_version = checked([MIHOMO, "-v"]).decode().splitlines()[0]
        assert "26.3.27" in xray_version and "d2758a0" in xray_version, xray_version
        assert "v1.19.28" in mihomo_version, mihomo_version
        print(xray_version, mihomo_version, sep="\n", flush=True)
        with tempfile.TemporaryDirectory(prefix="padm-vless-encryption-") as directory:
            check(Path(directory))
        print("VLESS Encryption 真实回归通过：16 个正例、8 个负例、逐入口生成/配对校验及关闭恢复")
    except Exception as error:
        raise SystemExit(scrub(str(error))) from None
