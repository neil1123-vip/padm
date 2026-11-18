import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import time
import urllib.parse
import uuid


BASE = Path(sys.argv[1]).resolve()
WORK = BASE / "private"
EVIDENCE = BASE / "evidence"
WORK.mkdir(exist_ok=False)
EVIDENCE.mkdir(exist_ok=True)
SOURCE = BASE / "v3.44.4/source"
ARCH = {"aarch64": "arm64", "x86_64": "amd64"}[platform.machine()]
assert ARCH == "arm64"
XRAY = "ghcr.io/neil1123-vip/padm-xray@sha256:df12fc6d46f9269599eefdbff4ced350c82f708c352796f55b70da3f59697b63"
MIHOMO = "metacubex/mihomo@sha256:fbe0d1193040e80322796c8e2f8d8bc42e1236f822ca7f5a621b307cfb8c7c89"
TOOLS = "ghcr.io/neil1123-vip/padm-ops@sha256:7760d008f7a3d8ee620a87bc08770d52b872de107337c12fdf625fe170517dc3"
NET = "ghcr.io/neil1123-vip/padm-net@sha256:aac0a35808e1968f9f89b4c3e27900f9341ceaeee31e61b5fff76e12dd735eaf"
TEST = "padm-arm64-uri-" + uuid.uuid4().hex[:12]
SNI = "reality-target.padm.test"
TARGET = """
import socketserver, ssl
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_3
context.load_cert_chain('/input/target-cert.pem', '/input/target-key.pem')
context.set_alpn_protocols(['h2'])
class Target(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            self.request.settimeout(4)
            with context.wrap_socket(self.request, server_side=True) as tls:
                while tls.recv(65536):
                    pass
        except OSError:
            pass
class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True
with Server(('127.0.0.1', 8443), Target) as server:
    print('target-ready', flush=True)
    server.serve_forever()
"""
ORIGIN = (
    "import http.server,json,ssl\n"
    "class Handler(http.server.BaseHTTPRequestHandler):\n"
    " def do_GET(self):\n"
    "  body=(self.path+'\\n').encode()*4096\n"
    "  print(json.dumps({'path':self.path,'peer':self.client_address[0]}),flush=True)\n"
    "  self.send_response(200);self.send_header('Content-Length',str(len(body)));"
    "self.end_headers();self.wfile.write(body)\n"
    " def log_message(self,*args): pass\n"
    "class Server(http.server.HTTPServer):\n"
    " def get_request(self):\n"
    "  sock,peer=super().get_request();print(json.dumps({'tcp':peer[0]}),flush=True);return sock,peer\n"
    "server=Server(('93.184.216.34',18080),Handler)\n"
    "context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)\n"
    "context.load_cert_chain('/input/origin-cert.pem','/input/origin-key.pem')\n"
    "server.socket=context.wrap_socket(server.socket,server_side=True)\n"
    "print('origin-ready',flush=True)\n"
    "server.serve_forever()\n"
)
commands, results, containers = [], [], []
secrets = []


def scrub(value):
    if isinstance(value, bytes):
        value = value.decode(errors="replace")
    for secret in sorted(secrets, key=len, reverse=True):
        value = value.replace(secret, "<redacted>")
    value = re.sub(r"vless://\S+|[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}", "<redacted>", value)
    return re.sub(r"[A-Za-z0-9_+/=-]{40,}", "<opaque>", value)


def command(label, arguments, allowed=(0,), timeout=60, keep=True):
    if arguments[:2] == ["docker", "run"]:
        arguments[2:2] = ["--pull=never", "--label", "io.padm.test=" + TEST]
    result = subprocess.run(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    commands.append({
        "label": label, "exit": result.returncode,
        "argv": [scrub(item) for item in arguments],
        "stdout_sha256": hashlib.sha256(result.stdout).hexdigest(),
        "stderr_sha256": hashlib.sha256(result.stderr).hexdigest(),
    })
    if keep:
        (EVIDENCE / (label + ".log")).write_text(scrub(result.stdout + result.stderr), encoding="utf-8")
    assert result.returncode in allowed, (label, result.returncode, scrub(result.stderr))
    return result


def image_tool(label, image, *arguments, keep=True):
    return command(label, [
        "docker", "run", "--rm", "--network", "none", "--read-only", "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges:true", image, *arguments,
    ], keep=keep).stdout.decode()


def provider_projection(local):
    return {
        "mode": "rule", "log-level": "debug", "ipv6": False,
        "proxy-providers": {"source": {
            "type": "file", "path": "/input/provider.txt", "health-check": {"enable": False},
            "override": {"ip-version": "ipv4"},
        }},
        "proxy-groups": [{"name": "entry", "type": "select", "use": ["source"]}],
        "listeners": [{"name": "entry", "type": "socks", "listen": "127.0.0.1", "port": local, "proxy": "entry"}],
        "rules": ["MATCH,REJECT"],
    }


def exported_uri(directory, entry, baseline=False):
    spec = {"core": {"type": "xray", "protocols": [entry]},
            "subscription": {"include_base": True}, "port_aliases": [], "cdn_entries": []}
    (directory / "source-spec.private.json").write_text(json.dumps(spec), encoding="utf-8")
    source = BASE / "v3.44.3/source" if baseline else SOURCE
    command(directory.name + "-export", [
        "bash", "-ec", 'DOCKER_BUNDLE_SOURCE_ROOT=$1; source "$1/docker/lib/services.sh"; '
        'dockerGenerateSubscription "$2/source-spec.private.json" "$2/provider.txt" local',
        "padm-fixture", str(source), str(directory),
    ], keep=False)
    (directory / "provider.txt").chmod(0o644)
    return (directory / "provider.txt").read_text().strip()


def stop(container, label):
    command(label + "-remove", ["docker", "rm", "-f", "-v", container])
    containers.remove(container)


def start(label, image, directory, *arguments, network=None, entrypoint=None):
    argv = [
        "docker", "run", "-d", "--read-only", "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges:true",
        "--user", "0:0" if entrypoint == "python3" else "10001:10001",
        "--mount", f"type=bind,src={directory},dst=/input,readonly",
        "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=32m",
    ]
    argv += ["--network", "container:" + network if network else "none"]
    if image == MIHOMO:
        argv += ["--env", "SAFE_PATHS=/input",
                 "--tmpfs", "/root/.config/mihomo:rw,noexec,nosuid,nodev,size=8m"]
    if entrypoint:
        argv += ["--entrypoint", entrypoint]
    container = command(label + "-start", [*argv, image, *arguments]).stdout.decode().strip()
    containers.append(container)
    time.sleep(0.5)
    state = json.loads(command(label + "-inspect", ["docker", "inspect", container], keep=False).stdout)[0]
    assert state["State"]["Running"] and not state["HostConfig"]["PortBindings"], label
    assert state["HostConfig"]["NetworkMode"] == ("container:" + network if network else "none"), label
    return container


try:
    release = BASE / "v3.44.4"
    manifest = json.loads((release / "release-manifest.json").read_text())
    assert manifest["release"]["commit"] == "25d99b1143d116da951c8eb9e6c47540bb22d898"
    for name, image in (("xray", XRAY), ("ops", TOOLS), ("net", NET)):
        assert manifest["images"][name]["platforms"]["linux/arm64"] == image.split("@")[1], name
    generator = SOURCE / "docker/lib/services.sh"
    assert hashlib.sha256(generator.read_bytes()).hexdigest() == "93bb791ce74f21b87fcfbe970a58b5c221856a41623f5b9b6fc231601afafa19"
    bundle = release / "padm-docker-bundle.tar.gz"
    assert hashlib.sha256(bundle.read_bytes()).hexdigest() == manifest["control"]["sha256"]
    images = {}
    for label, image in (("xray", XRAY), ("mihomo", MIHOMO), ("ops", TOOLS), ("net", NET)):
        command(label + "-pull", ["docker", "pull", "--platform", "linux/arm64", image], timeout=180)
        raw = command(label + "-manifest", ["docker", "buildx", "imagetools", "inspect", "--raw", image], keep=False).stdout
        assert hashlib.sha256(raw).hexdigest() == image.rsplit(":", 1)[1], label
        (EVIDENCE / (label + "-manifest.json")).write_bytes(raw)
        inspected = json.loads(command(label + "-image-inspect", ["docker", "image", "inspect", image], keep=False).stdout)[0]
        assert inspected["Architecture"] == ARCH and inspected["Os"] == "linux"
        assert inspected["Id"] == json.loads(raw)["config"]["digest"] and image in inspected["RepoDigests"], label
        images[label] = {
            "reference": image, "id": inspected["Id"], "repo_digests": inspected["RepoDigests"],
            "architecture": inspected["Architecture"],
            "version": image_tool(label + "-version", image, "version" if label == "xray" else "-v")
                if label in ("xray", "mihomo") else None,
        }
    assert "26." in images["xray"]["version"]
    assert "v1.19.31" in images["mihomo"]["version"]
    command("origin-certificate", [
        "docker", "run", "--rm", "--network", "none", "--read-only", "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges:true",
        "--mount", f"type=bind,src={WORK},dst=/output", "--entrypoint", "openssl", TOOLS,
        "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
        "-subj", "/CN=93.184.216.34", "-addext", "subjectAltName=IP:93.184.216.34",
        "-keyout", "/output/origin-key.pem", "-out", "/output/origin-cert.pem",
    ])
    command("target-certificate", [
        "docker", "run", "--rm", "--network", "none", "--read-only", "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges:true",
        "--mount", f"type=bind,src={WORK},dst=/output", "--entrypoint", "openssl", TOOLS,
        "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
        "-subj", "/CN=" + SNI, "-addext",
        "subjectAltName=" + ",".join(["DNS:" + SNI] + [f"DNS:padding-{i:03}.padm.test" for i in range(160)]),
        "-keyout", "/output/target-key.pem", "-out", "/output/target-cert.pem",
    ])
    key = image_tool("generate-reality-key", XRAY, "x25519", keep=False)
    private = re.search(r"^PrivateKey:\s*(\S+)", key, re.M)[1]
    public = re.search(r"^(?:Password \(PublicKey\)|PublicKey):\s*(\S+)", key, re.M)[1]
    account, short_id = str(uuid.uuid4()), "0123456789abcdef"
    secrets.extend((private, public, account, short_id))
    pairs = {}
    for transport in ("vision", "xhttp"):
        raw = image_tool("generate-" + transport, XRAY, "vlessenc", keep=False)
        heading = "Authentication: ML-KEM-768, Post-Quantum"
        assert raw.count(heading) == 1
        pairs[transport] = dict(re.findall(r'^\s*"(decryption|encryption)"\s*:\s*"([^"\s]+)"\s*,?\s*$',
                                          raw.split(heading, 1)[1], re.M))
        assert set(pairs[transport]) == {"decryption", "encryption"}
        secrets.extend(pairs[transport].values())
    server_directory = WORK / "server"
    server_directory.mkdir(exist_ok=True)
    service, path = "padm-grpc", "/padm-xhttp"
    scenarios = [
        ("vision-none", "vision", 1, 35464, False), ("xhttp-none", "xhttp", 2, 35465, False),
        ("vision-encrypted", "vision", 1, 35466, True), ("xhttp-encrypted", "xhttp", 2, 35467, True),
        ("grpc-none", "grpc", 26, 35468, False),
    ]
    inbounds = []
    for _, transport, _, port, encrypted in scenarios:
        stream = {"network": "tcp" if transport == "vision" else transport, "security": "reality",
            "realitySettings": {"show": True, "dest": "127.0.0.1:8443", "xver": 0,
                "serverNames": [SNI], "privateKey": private, "shortIds": [short_id]}}
        if transport == "grpc":
            stream["grpcSettings"] = {"serviceName": service}
        if transport == "xhttp":
            stream["xhttpSettings"] = {"path": path, "host": SNI, "mode": "packet-up"}
        user = {"id": account, **({"flow": "xtls-rprx-vision"} if transport == "vision" else {})}
        inbounds.append({"listen": "127.0.0.1", "port": port, "protocol": "vless", "streamSettings": stream,
            "settings": {"clients": [user], "decryption": pairs[transport]["decryption"] if encrypted else "none"}})
    (server_directory / "config.json").write_text(json.dumps({
        "log": {"loglevel": "debug"},
        "inbounds": inbounds,
        "outbounds": [{"protocol": "freedom"}],
    }), encoding="utf-8")
    server = start("server", XRAY, server_directory, "run", "-c", "/input/config.json")
    command("origin-alias", [
        "docker", "run", "--rm", "--network", "container:" + server, "--read-only",
        "--user", "0:0", "--cap-drop", "ALL", "--cap-add", "NET_ADMIN", "--entrypoint", "/usr/sbin/ip", NET,
        "address", "add", "93.184.216.34/32", "dev", "lo",
    ])
    target = start("reality-target", TOOLS, WORK, "-u", "-c", TARGET, network=server, entrypoint="python3")
    origin = start("origin", TOOLS, WORK, "-u", "-c", ORIGIN, network=server, entrypoint="python3")
    for role, cid in (("target", target), ("origin", origin)):
        assert (role + "-ready").encode() in command(role + "-ready", ["docker", "logs", cid]).stdout
    cases = [(scenario, transport, ident, port, encrypted, control)
             for scenario, transport, ident, port, encrypted in scenarios
             for control in ("positive", "missing-hybrid", "wrong-uuid", "wrong-sni") +
                 (("old-none",) if encrypted else (("wrong-service",) if transport == "grpc" else ()))]
    for scenario, transport, ident, port, encrypted, control in cases:
        case = scenario + "-" + control
        entry = {"id": ident, "core": "xray", "listener_id": "entry-" + transport, "name": "entry", "uuid": account,
                 "server": "127.0.0.1", "public_port": port,
                 "reality": {"server_name": SNI, "public_key": public, "short_id": short_id}}
        if transport == "grpc":
            entry["grpc"] = {"service_name": service}
        if transport == "xhttp":
            entry["xhttp"] = {"path": path, "host": SNI, "mode": "packet-up"}
        if encrypted:
            entry["vless_encryption"] = {"encryption": pairs[transport]["encryption"]}
        directory = WORK / case
        directory.mkdir()
        uri = exported_uri(directory, entry, baseline=control == "missing-hybrid")
        parsed = urllib.parse.urlsplit(uri)
        query = dict(urllib.parse.parse_qsl(parsed.query))
        assert query["type"] == ("tcp" if transport == "vision" else transport)
        assert transport != "grpc" or query["serviceName"] == service
        assert query.get("support-x25519mlkem768") == (None if control == "missing-hybrid" else "true")
        original = (directory / "provider.txt").read_bytes()
        if control == "wrong-uuid":
            uri = urllib.parse.urlunsplit(parsed._replace(netloc=f"{uuid.uuid4()}@{parsed.hostname}:{parsed.port}"))
        elif control in ("wrong-sni", "wrong-service", "old-none"):
            field = {"wrong-sni": "sni", "wrong-service": "serviceName", "old-none": "encryption"}[control]
            query[field] = "none" if control == "old-none" else "wrong.padm.test"
            if control == "wrong-service":
                query["path"] = query["serviceName"]
            uri = urllib.parse.urlunsplit(parsed._replace(query=urllib.parse.urlencode(query)))
        mutated = control.startswith("wrong-") or control == "old-none"
        if mutated:
            (directory / "provider.txt").write_bytes((uri + "\n").encode())
        provider = (directory / "provider.txt").read_bytes()
        assert mutated == (provider != original)
        secrets.append(uri)
        (directory / "config.json").write_text(json.dumps(provider_projection(2080)), encoding="utf-8")
        (EVIDENCE / (case + "-provider.json")).write_bytes((directory / "config.json").read_bytes())
        client = start(case, MIHOMO, directory, "-d", "/tmp", "-f", "/input/config.json", network=server)
        nonce = "/" + uuid.uuid4().hex
        expected = (nonce.encode() + b"\n") * 4096
        before = command(case + "-origin-before", ["docker", "logs", origin]).stdout
        server_before = command(case + "-server-before", ["docker", "logs", server], keep=False).stdout
        curl = command(case + "-request", [
            "docker", "run", "--rm", "--network", "container:" + server,
            "--read-only", "--cap-drop", "ALL", "--security-opt", "no-new-privileges:true",
            "--mount", f"type=bind,src={WORK},dst=/input,readonly",
            "--entrypoint", "curl", TOOLS, "--fail", "--silent", "--show-error", "--max-time", "8",
            "--noproxy", "", "--header", "X-Padm-Negative: " + "x" * 4096,
            "--cacert", "/input/origin-cert.pem",
            "--socks5-hostname", "127.0.0.1:2080", "https://93.184.216.34:18080" + nonce,
        ], allowed=tuple(range(126)), timeout=18)
        log = command(case + "-client-log", ["docker", "logs", client]).stdout
        server_after = command(case + "-server-log", ["docker", "logs", server], keep=False).stdout
        assert server_after.startswith(server_before)
        server_fresh = server_after[len(server_before):]
        (EVIDENCE / (case + "-server-delta.log")).write_text(scrub(server_fresh), encoding="utf-8")
        after = command(case + "-origin-log", ["docker", "logs", origin]).stdout
        assert after.startswith(before)
        fresh = after[len(before):]
        row = {
            "case": case, "control": control, "exit": curl.returncode, "body_bytes": len(curl.stdout),
            "body_sha256": hashlib.sha256(curl.stdout).hexdigest(), "nonce": nonce,
            "origin_nonce_count": fresh.count(nonce.encode()), "origin_new_tcp": fresh.count(b'"tcp":'),
            "reality_auth_true": b"REALITY Authentication: true" in log,
            "legacy_tls_fallback": b"for TLS' communication: false" in log
                and b"certificate signed by unknown authority" in log
                and ("forwarded SNI: " + SNI).encode() in server_fresh,
            "wrong_sni_forwarded": b"forwarded SNI: wrong.padm.test" in server_fresh,
            "invalid_uuid_rejected": b"invalid request user id:" in server_fresh,
            "source_uri_sha256": hashlib.sha256(original).hexdigest(),
            "provider_uri_sha256": hashlib.sha256(provider).hexdigest(),
        }
        row["passed"] = (curl.returncode == 0 and curl.stdout == expected and
            row["origin_nonce_count"] == 1 and row["origin_new_tcp"] == 1 and row["reality_auth_true"]
        ) if control.startswith("positive") else (
            curl.returncode in (35, 56, 97) and not curl.stdout and not fresh and
            (control != "missing-hybrid" or (not row["reality_auth_true"] and row["legacy_tls_fallback"])) and
            (control != "wrong-sni" or (not row["reality_auth_true"] and row["wrong_sni_forwarded"])) and
            (control != "wrong-uuid" or encrypted or row["invalid_uuid_rejected"]) and
            (control not in ("wrong-uuid", "wrong-service") or row["reality_auth_true"])
        )
        results.append(row)
        (EVIDENCE / "partial-results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
        print(json.dumps(row), flush=True)
        stop(client, case)
    assert len(results) == 23 and all(row["passed"] for row in results), "ARM64 raw URI matrix failed"
    summary = {
        "passed": True,
        "scope": "formal-reality-raw-uri-native-arm64-network-none-strict-tls",
        "source": os.environ["GITHUB_SHA"], "run": os.environ["GITHUB_RUN_ID"], "arch": platform.machine(),
        "target": "127.0.0.1:8443", "sni": SNI, "fingerprint": "chrome", "test_label": TEST,
        "formal_version": manifest["release"], "bundle_sha256": manifest["control"]["sha256"],
        "images": images, "results": results,
        "candidate_services_sha256": hashlib.sha256((SOURCE / "docker/lib/services.sh").read_bytes()).hexdigest(),
        "baseline_services_sha256": hashlib.sha256((BASE / "v3.44.3/source/docker/lib/services.sh").read_bytes()).hexdigest(),
    }
    (EVIDENCE / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
finally:
    for index, container in enumerate(list(reversed(containers))):
        stop(container, "cleanup-" + str(index))
    remaining = command("cleanup-inspect", ["docker", "ps", "-aq", "--filter", "label=io.padm.test=" + TEST]).stdout.splitlines()
    (EVIDENCE / "commands.json").write_text(json.dumps(commands, indent=2), encoding="utf-8")
    for path in (WORK / "origin-key.pem", WORK / "target-key.pem", WORK / "server/config.json"):
        path.unlink(missing_ok=True)
    (EVIDENCE / "cleanup.json").write_text(json.dumps({"containers_remaining": len(remaining)}), encoding="utf-8")
    assert not remaining
