"""在一次性 ARM64 宿主集中验收正式 CLI 的入口、路由、中继和站点。"""

import argparse
import copy
import http.client
import http.server
import importlib.util
import json
import os
from pathlib import Path
import runpy
import shutil
import socket
import socketserver
import ssl
import struct
import threading
import time
import traceback
import urllib.parse
import uuid


BASE_PATH = Path(__file__).with_name("native-arm64-host-lifecycle.py")
loader = importlib.util.spec_from_file_location("lifecycle", BASE_PATH)
base = importlib.util.module_from_spec(loader)
loader.loader.exec_module(base)
ROOT, CLI, NEW = base.ROOT, base.CLI, base.NEW
require, digest = base.require, base.digest
DOMAIN, ORIGIN = base.DOMAIN, base.ORIGIN
PORTS = {"xray": 35466, "sing-box": 35467}
ALIAS, REPLACED, RELAY, RELAY_NEW = 35468, 35469, 38180, 38181


def client_config(password, local_port, remote_port, server_name=DOMAIN):
    result = base.trojan_client(password, local_port, server_name)
    result["outbounds"][0]["server_port"] = remote_port
    return result


def parse_dns(request):
    offset, labels = 12, []
    require(len(request) >= 17 and request[4:6] == b"\x00\x01", "invalid fixture DNS question")
    while request[offset]:
        size = request[offset]
        require(size <= 63 and offset + size + 1 < len(request), "invalid DNS label")
        labels.append(request[offset + 1:offset + size + 1].decode("ascii"))
        offset += size + 1
    end = offset + 5
    require(end <= len(request), "truncated DNS question")
    if end != len(request):
        require(request[10:12] == b"\x00\x01" and len(request) >= end + 11
                and request[end:end + 3] == b"\x00\x00\x29"
                and len(request) == end + 11 + int.from_bytes(request[end + 9:end + 11], "big"),
                "invalid DNS EDNS record")
    return ".".join(labels), struct.unpack("!HH", request[offset + 1:end])[0], end


class Dns(socketserver.BaseRequestHandler):
    def handle(self):
        request, channel = self.request
        name, kind, end = parse_dns(request)
        self.server.requests.append({"name": name, "kind": kind})
        failed = name.startswith("error-")
        value = socket.inet_aton(ORIGIN)
        answer = b"\xc0\x0c" + struct.pack("!HHIH", 1, 1, 1, 4) + value
        has_answer = kind == 1 and not failed
        header = request[:2] + struct.pack("!HHHHH", 0x8182 if failed else 0x8180, 1, int(has_answer), 0, 0)
        channel.sendto(header + request[12:end] + (answer if has_answer else b""), self.client_address)


class Acceptance(base.Acceptance):
    def __init__(self, work):
        super().__init__(work)
        self.inputs = Path("/root/.padm-arm64-specialties-" + uuid.uuid4().hex)
        self.inputs.mkdir(mode=0o700)
        self.servers = []
        self.clients = {}
        self.requests = []
        self.https_connections = []
        self.deferred_failures = []
        self.checks = []
        self.account_uuid = str(uuid.uuid4())
        self.record("specialties-identity", {
            "driver_sha256": digest(Path(__file__).read_bytes()),
            "base_driver_sha256": digest(BASE_PATH.read_bytes()),
            "release": NEW, "engine_reinstallation_requested": False,
            "scope": "native-arm64-ipv4-local-origin-two-cores",
        })

    def engine_bootstrap(self):
        require(os.environ.get("GITHUB_ACTIONS") == "true", "disposable Actions host required")
        require(os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted", "GitHub-hosted runner required")
        require(not self.objects("preflight-objects")["containers"], "preexisting containers refused")

    def server(self, instance):
        thread = threading.Thread(target=instance.serve_forever, daemon=True)
        thread.start()
        self.servers.append((instance, thread))
        return instance

    def secure_json(self, name, value):
        path = self.inputs / (name + ".json")
        require(not path.exists(), "input overwrite refused")
        path.write_text(json.dumps(value))
        path.chmod(0o600)
        return str(path)

    def public_bytes(self, name, raw):
        path = self.evidence / name
        require(not path.exists() and path.parent == self.evidence, "unsafe evidence path")
        path.write_bytes(raw)
        path.chmod(0o644)
        return {"file": name, "sha256": digest(raw), "bytes": len(raw)}

    def edit(self, *arguments, label, expected=0):
        raw = self.command(
            [CLI, "edit", *arguments, "--confirm", "PADM-DOCKER-EDIT"],
            label, timeout=900, allowed=(expected,),
        )
        if expected == 0:
            self.services(label)
        return raw

    def services(self, label):
        deadline = time.monotonic() + 120
        while True:
            ids = self.command(
                ["docker", "ps", "-aq", "--filter", "label=com.docker.compose.project=padm-docker"],
                label + "-service-list",
            ).decode().split()
            rows = self.json_command(["docker", "inspect", *ids], label + "-service-inspect") if ids else []
            result = {row["Config"]["Labels"]["com.docker.compose.service"]: row for row in rows}
            if len(rows) == 3 and set(result) == {"xray", "sing-box", "nginx"} and all(
                row["State"]["Running"] and row["State"].get("Health", {}).get("Status") == "healthy"
                for row in rows
            ):
                require(all(row["HostConfig"]["ReadonlyRootfs"] and not row["HostConfig"]["Privileged"] for row in rows),
                        "service isolation changed")
                return result
            require(time.monotonic() < deadline, "service health deadline exceeded")
            time.sleep(1)

    def configure(self):
        _, manifest, directory = self.releases[NEW["version"]]
        key, cert = self.private / "tls.key", self.private / "tls.crt"
        self.command(
            ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
             "-subj", "/CN=" + DOMAIN, "-addext", "subjectAltName=DNS:" + DOMAIN + ",IP:" + ORIGIN,
             "-keyout", str(key), "-out", str(cert)], "create-ca",
        )
        self.cli("tls", "install", "--domain", DOMAIN, "--cert", str(cert), "--key", str(key),
                 "--ops-image", manifest["images"]["ops"]["reference"], label="formal-tls")
        spec = {
            "schema_version": 3,
            "core": {"type": "xray", "secondary_type": "sing-box", "protocols": [
                {"id": 29, "core": "xray", "listener_id": "entry-fallback", "server": DOMAIN,
                 "public_port": PORTS["xray"], "address_families": ["ipv4"], "name": "arm64-fallback",
                 "uuid": self.core_credential,
                 "fallback_tls": {"domain": DOMAIN, "http_port": 31300, "http2_port": 31302,
                                  "alpn": ["h2", "http/1.1"]}},
                {"id": 28, "core": "sing-box", "listener_id": "entry-trojan", "server": DOMAIN,
                 "public_port": PORTS["sing-box"], "address_families": ["ipv4"], "name": "arm64-trojan",
                 "uuid": self.core_credential, "trojan": {"domain": DOMAIN}},
            ]},
            "accounts": [{"id": self.account, "name": "arm64-independent", "enabled": True,
                          "uuid": self.account_uuid, "password": self.managed_password,
                          "shadowsocks_password": None, "listeners": ["entry-fallback", "entry-trojan"]}],
            "tls": {"domain": DOMAIN}, "subscription": {"enabled": False, "token": uuid.uuid4().hex},
            "host_integrations": [], "site": {"mode": "default"},
        }
        path = self.secure_json("configure", base.expected_spec(spec, NEW, manifest))
        self.cli("configure", "--spec", path, "--manifest", str(directory / base.NAMES[0]),
                 "--bundle", str(directory / base.NAMES[1]), "--control-bundle", str(directory / base.NAMES[2]),
                 label="formal-configure")
        self.cli("traffic", "collect", label="initial-collect")
        self.cli("traffic", "limit", self.account, "1", label="account-quota")
        self.original = json.loads((ROOT / "config/spec.json").read_text())
        self.business = self.business_tree()
        self.last_ledger = self.ledger()
        require(set(self.last_ledger) == {self.account, self.core_credential}, "account identity mismatch")
        require(self.last_ledger[self.account]["limit_bytes"] == 1024 ** 3, "quota mismatch")
        self.command(["ip", "address", "add", ORIGIN + "/32", "dev", "lo"], "origin-add")
        self.origin_added = True
        route = self.json_command(["ip", "-j", "route", "get", ORIGIN], "origin-route")
        require(len(route) == 1 and route[0].get("type") == "local" and route[0]["dev"] == "lo", "origin not local")
        owner = self

        class Origin(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                body = (self.path.encode() + b"\n") * 4096
                owner.requests.append({"path": self.path, "peer": self.client_address[0]})
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_):
                pass

        self.origin = self.server(http.server.ThreadingHTTPServer((ORIGIN, 0), Origin))
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certfile=str(cert), keyfile=str(key))

        class HttpsOrigin(http.server.ThreadingHTTPServer):
            def get_request(self):
                connection, peer = super().get_request()
                owner.https_connections.append({"peer": peer[0]})
                try:
                    return context.wrap_socket(connection, server_side=True), peer
                except BaseException:
                    connection.close()
                    raise

        self.https_origin = HttpsOrigin((ORIGIN, 0), Origin)
        self.server(self.https_origin)
        self.start_clients()

    def start_clients(self):
        image = self.releases[NEW["version"]][1]["images"]["sing-box"]["reference"]
        for name, core, password, port in (
            ("xray", "xray", self.managed_password, PORTS["xray"]),
            ("sing-box", "sing-box", self.managed_password, PORTS["sing-box"]),
            ("alias", "sing-box", self.managed_password, ALIAS),
            ("replaced", "sing-box", self.managed_password, REPLACED),
            ("wrong", "xray", uuid.uuid4().hex, PORTS["xray"]),
            ("wrong-sni", "xray", self.managed_password, PORTS["xray"]),
        ):
            directory = self.private / ("client-" + name)
            directory.mkdir(mode=0o755)
            directory.chmod(0o755)
            shutil.copyfile(self.private / "tls.crt", directory / "ca.crt")
            (directory / "ca.crt").chmod(0o644)
            with socket.socket() as probe:
                probe.bind(("127.0.0.1", 0))
                local = probe.getsockname()[1]
            config = client_config(password, local, port, "wrong.padm.test" if name == "wrong-sni" else DOMAIN)
            (directory / "config.json").write_text(json.dumps(config))
            (directory / "config.json").chmod(0o644)
            identity = self.command(
                ["docker", "run", "-d", "--network", "host", "--read-only", "--cap-drop", "ALL",
                 "--security-opt", "no-new-privileges:true", "--user", "10001:10001",
                 "--mount", f"type=bind,src={directory},dst=/input,readonly",
                 "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=16m", image, "run", "-c", "/input/config.json"],
                "client-" + name,
            ).decode().strip()
            self.containers.add(identity)
            self.clients[name] = {"port": local, "container": identity, "core": core}
        deadline = time.monotonic() + 30
        for name, row in self.clients.items():
            while True:
                state = self.json_command(["docker", "inspect", "--format", "{{json .State}}", row["container"]],
                                          "client-state-" + name)
                require(state["Running"], "client exited")
                listening = self.command(["ss", "-lntHp", f'sport = :{row["port"]}'], "client-listener-" + name).decode()
                if f'pid={state["Pid"]},' in listening:
                    break
                require(time.monotonic() < deadline, "client listener deadline exceeded")
                time.sleep(0.2)

    def probe(self, name, label, accepted=True, host=ORIGIN, *, via=None, dns=None, http_host=None, auth_refusal=False):
        nonce = "/" + uuid.uuid4().hex
        before = len(self.requests)
        auth_before = via.auth if via else 0
        connects_before = via.connects if via else 0
        dns_before = len(dns.requests) if dns else 0
        output = self.command(
            ["curl", "--fail", "--silent", "--show-error", "--max-time", "6", "--noproxy", "",
             "--socks5-hostname", "127.0.0.1:" + str(self.clients[name]["port"]),
             *(["--header", "Host: " + http_host] if http_host else []),
             f"http://{host}:{self.origin.server_port}{nonce}"],
            label, timeout=10, allowed=tuple(range(126)),
        )
        code = self.commands[-1]["exit"]
        requests = self.requests[before:]
        expected = (nonce.encode() + b"\n") * 4096
        expected_peers = set()
        if accepted:
            require(code == 0 and output == expected and len(requests) == 1 and requests[0]["path"] == nonce,
                    "business payload or nonce mismatch")
            services = self.services(label)
            core = self.clients[name]["core"]
            peers = {row["IPAddress"] for row in services[core]["NetworkSettings"]["Networks"].values()
                     if row.get("IPAddress")}
            expected_peers = {ORIGIN} if via else peers
            require(requests[0]["peer"] in expected_peers, "unexpected origin peer")
        else:
            require(code != 0 and not output and not requests, "rejected business reached origin")
        delta = via.connects - connects_before if via else 0
        auth_delta = via.auth - auth_before if via else 0
        if via:
            require(delta == int(accepted) and auth_delta == int(accepted or auth_refusal), "SOCKS route mismatch")
        record = {
            "label": label, "client": name, "accepted": accepted, "curl_exit": code,
            "nonce": nonce, "body_bytes": len(output), "body_sha256": digest(output),
            "expected_bytes": len(expected), "expected_sha256": digest(expected),
            "origin_requests": requests, "socks_connects_delta": delta,
            "socks_auth_delta": auth_delta, "socks_auth_refusal": auth_refusal,
            "expected_origin_peers": sorted(expected_peers),
            "dns_requests": dns.requests[dns_before:] if dns else [],
            "http_host": http_host,
            "strict_tls": True, "local_origin": True,
            "tls_server_name": "wrong.padm.test" if name == "wrong-sni" else DOMAIN,
            "client_container": self.clients[name]["container"],
            "client_image": self.releases[NEW["version"]][1]["images"]["sing-box"]["reference"],
        }
        self.record(label, record)
        self.checks.append(label)
        return record

    def checkpoint(self, label, *, restored=False):
        services = self.services(label)
        _, manifest, _ = self.releases[NEW["version"]]
        images = self.image_proof(manifest, services, label)
        bundle = self.bundle_proof(NEW)
        current = self.ledger()
        base.preserved(self.last_ledger, current)
        if restored:
            require(json.loads((ROOT / "config/spec.json").read_text()) == self.original, "spec not restored")
            require(self.business_tree() == self.business, "business files not restored")
        before = current[self.account]
        for name in PORTS:
            self.probe(name, label + "-" + name)
        deadline = time.monotonic() + 20
        while True:
            self.cli("traffic", "collect", label=label + "-collect")
            after = self.ledger()
            base.preserved(current, after)
            if all(after[self.account][key] > before[key] for key in ("upload", "download")):
                break
            require(time.monotonic() < deadline, "independent account traffic did not increase")
            time.sleep(1)
        self.last_ledger = after
        self.record(label, {
            "passed": True, "bundle": bundle, "images": images,
            "ledger_before": self.public_ledger(current), "ledger_after": self.public_ledger(after),
            "spec_restored": restored, "business_restored": restored,
            "spec_sha256": digest((ROOT / "config/spec.json").read_bytes()),
            "spec_invariant_sha256": digest(json.dumps({
                key: value for key, value in json.loads((ROOT / "config/spec.json").read_text()).items()
                if key not in ("release", "images")
            }, sort_keys=True, separators=(",", ":")).encode()),
            "account_identity_sha256": digest(self.account.encode()),
            "business_tree": self.business_tree(),
            "services": {name: {"id": row["Id"], "image_id": row["Image"],
                                 "ipv4": sorted(item["IPAddress"] for item in row["NetworkSettings"]["Networks"].values()
                                                if item.get("IPAddress"))}
                         for name, row in services.items()},
        })
        self.phases.append(label)

    def aliases(self):
        listener = "entry-trojan"
        self.edit("--port-alias", listener, str(ALIAS), label="alias-add")
        self.probe("alias", "alias-added-positive")
        self.edit("--port-alias-default", listener, str(ALIAS), label="alias-default")
        self.share_port(ALIAS, "alias-default-share")
        self.edit("--port-alias-replace", listener, str(ALIAS), str(REPLACED), label="alias-replace")
        self.probe("replaced", "alias-replaced-positive")
        self.probe("alias", "alias-old-rejected", False)
        self.share_port(REPLACED, "alias-replaced-share")
        self.edit("--port-alias-default", listener, "base", label="alias-base")
        self.share_port(PORTS["sing-box"], "alias-base-share")
        self.edit("--port-alias-remove", listener, str(REPLACED), label="alias-remove")
        self.probe("replaced", "alias-removed-rejected", False)
        self.checkpoint("aliases-restored", restored=True)

    def share_port(self, port, label):
        raw = self.cli("share", "content", "--base", label=label)
        lines = [line for line in raw.decode().splitlines() if line.startswith("trojan://")]
        projection = []
        for line in lines:
            parsed = urllib.parse.urlsplit(line)
            projection.append({"scheme": parsed.scheme, "host": parsed.hostname, "port": parsed.port,
                               "name": urllib.parse.unquote(parsed.fragment),
                               "credential_sha256": digest(urllib.parse.unquote(parsed.username or "").encode())})
        expected = [
            {"name": name, "credential_sha256": digest(credential.encode())}
            for name, credential in (("arm64-trojan", self.core_credential),
                                     ("arm64-trojan-arm64-independent", self.managed_password))
        ]
        for item in expected:
            require(any(row == {"scheme": "trojan", "host": DOMAIN, "port": port, **item} for row in projection),
                    "default share port or credential missing")
        self.record(label, {"expected_port": port, "expected_accounts": expected,
                            "projection": projection, "private_output_sha256": digest(raw)})

    def routing(self):
        helpers_path = Path(__file__).parents[2] / "docker/tests/routing-socks5-real.py"
        helpers = runpy.run_path(str(helpers_path))
        upstream = helpers["Server"]((ORIGIN, 0), helpers["Socks"])
        upstream.auth = upstream.connects = 0
        upstream.reject = False
        upstream.destination_hosts = {ORIGIN}
        upstream.destination = self.origin.server_port
        upstream.destinations = []
        self.server(upstream)
        dns = socketserver.ThreadingUDPServer((ORIGIN, 0), Dns)
        dns.daemon_threads = True
        dns.requests = []
        self.server(dns)
        path = self.secure_json("socks", {"server": ORIGIN, "port": upstream.server_address[1],
                                       "username": "fixture-user", "password": "fixture-password"})
        self.edit("--socks5", path, label="socks-global")
        for name in PORTS:
            self.probe(name, "socks-global-" + name, via=upstream)
        upstream.reject = True
        for name in PORTS:
            self.probe(name, "socks-auth-rejected-" + name, False, via=upstream, auth_refusal=True)
        upstream.reject = False
        self.edit("--socks5-domains", "full:select.padm.test", label="socks-selective")
        for name in PORTS:
            self.probe(name, "socks-selective-direct-" + name)
            self.probe(name, "socks-selective-matched-" + name, via=upstream, http_host="select.padm.test")
        self.edit("--hosts-add", "hosts.padm.test", ORIGIN, label="hosts-add")
        for name in PORTS:
            self.probe(name, "hosts-positive-" + name, host="hosts.padm.test")
        self.edit("--dns-rules", ORIGIN, str(dns.server_address[1]),
                  "full:dns.padm.test,full:error-dns.padm.test", label="dns-enable")
        for name in PORTS:
            row = self.probe(name, "dns-positive-" + name, host="dns.padm.test", dns=dns)
            require(any(item["name"] == "dns.padm.test" and item["kind"] == 1 for item in row["dns_requests"]),
                    "configured DNS not queried")
            row = self.probe(name, "dns-error-rejected-" + name, False, host="error-dns.padm.test", dns=dns)
            require(any(item["name"] == "error-dns.padm.test" for item in row["dns_requests"]),
                    "DNS refusal not witnessed")
        self.edit("--block-domains", "full:hosts.padm.test", label="block-domain")
        for name in PORTS:
            self.probe(name, "block-domain-rejected-" + name, False, host="hosts.padm.test")
        self.edit("--direct-domains", "full:hosts.padm.test", label="direct-overlap")
        for name in PORTS:
            self.probe(name, "direct-over-block-" + name, host="hosts.padm.test")
        for flag in ("--direct-off", "--block-off", "--dns-off", "--hosts-off", "--socks5-off"):
            self.edit(flag, label="restore-" + flag[2:])
        self.record("routing-fixtures", {"socks_fixture_sha256": digest(helpers_path.read_bytes()),
                                        "dns_requests": dns.requests, "socks_auth": upstream.auth,
                                        "socks_connects": upstream.connects, "destinations": upstream.destinations})
        self.checkpoint("routing-restored", restored=True)

    def relay_probe(self, label, port, accepted, password="relay-password", *, https=False, expected_status=None):
        before = len(self.requests)
        connections_before = len(self.https_connections)
        nonce = "/" + uuid.uuid4().hex
        headers = self.private / (label + ".headers")
        origin = self.https_origin if https else self.origin
        output = self.command(
            ["curl", "--silent", "--show-error", "--fail", "--max-time", "6", "--noproxy", "",
             "--proxy", f"http://127.0.0.1:{port}", "--proxy-user", "relay-user:" + password,
             "--dump-header", str(headers), "--cacert", str(self.private / "tls.crt"),
             f'{"https" if https else "http"}://{ORIGIN}:{origin.server_port}{nonce}'],
            label, timeout=10, allowed=tuple(range(126)),
        )
        code = self.commands[-1]["exit"]
        requests = self.requests[before:]
        connections = self.https_connections[connections_before:]
        expected = (nonce.encode() + b"\n") * 4096
        statuses = [int(line.split()[1]) for line in headers.read_text().splitlines() if line.startswith("HTTP/")]
        self.record(label, {"accepted": accepted, "curl_exit": code, "nonce": nonce,
                            "origin_requests": requests, "body_sha256": digest(output),
                            "expected_sha256": digest(expected), "body_bytes": len(output),
                            "statuses": statuses, "strict_https_connect": https,
                            "https_origin_connections": connections,
                            "response_headers": self.public_bytes(label + ".headers", headers.read_bytes()),
                            "response_body": self.public_bytes(label + ".body", output)})
        require((code == 0 and output == expected and len(requests) == 1 and requests[0]["path"] == nonce
                 and len(connections) == int(https))
                if accepted else (code not in (0, 28) and not output and not requests and not connections),
                "relay result mismatch")
        if expected_status is not None:
            require(expected_status in statuses, "expected HTTP status not witnessed")
        if accepted and https:
            require(statuses == [200, 200], "HTTPS CONNECT tunnel or destination status mismatch")
        self.checks.append(label)

    def relay(self):
        path = self.secure_json("relay", {"core": "xray", "port": RELAY, "address_families": ["ipv4"],
                                        "username": "relay-user", "password": "relay-password",
                                        "source_ips": ["0.0.0.0/0"]})
        self.edit("--http-relay", path, label="relay-enable")
        self.relay_probe("relay-positive", RELAY, True)
        self.relay_probe("relay-connect-positive", RELAY, True, https=True)
        self.relay_probe("relay-wrong-auth", RELAY, False, password="wrong-password", expected_status=407)
        self.edit("--http-relay-port", str(RELAY_NEW), label="relay-port")
        self.relay_probe("relay-new-port", RELAY_NEW, True)
        self.relay_probe("relay-new-connect", RELAY_NEW, True, https=True)
        self.relay_probe("relay-old-port-rejected", RELAY, False)
        self.edit("--http-relay-sources", "198.18.1.2/32", label="relay-source-deny")
        spec = json.loads((ROOT / "config/spec.json").read_text())
        runtime = json.loads((ROOT / "config/xray/config.json").read_text())
        policy = runtime["routing"]["rules"][:2]
        require(spec["relay"]["http"]["source_ips"] == ["198.18.1.2/32"], "relay source edit not persisted")
        require(policy == [
            {"type": "field", "inboundTag": ["padm-relay-http"], "source": ["198.18.1.2/32"],
             "outboundTag": "padm-relay-http-direct"},
            {"type": "field", "inboundTag": ["padm-relay-http"], "outboundTag": "blocked"},
        ], "relay source policy mismatch")
        self.record("relay-source-policy", {"source_ips": spec["relay"]["http"]["source_ips"], "rules": policy})
        # 保留来源异常的失败判定，同时完成独立站点专项，避免重复整轮。
        for label, https in (("relay-source-connect-rejected", True), ("relay-source-rejected", False)):
            try:
                self.relay_probe(label, RELAY_NEW, False, https=https)
            except AssertionError:
                self.deferred_failures.append(label)
        self.edit("--http-relay-off", label="relay-off")
        self.relay_probe("relay-off-rejected", RELAY_NEW, False)
        self.checkpoint("relay-restored", restored=True)

    def website_negotiated(self, label, status, location, version):
        body = self.private / (label + ".body")
        headers = self.private / (label + ".headers")
        raw = self.command(
            ["curl", "--silent", "--show-error", "--max-time", "8", "--noproxy", "*",
             "--http2", "--cacert", str(self.private / "tls.crt"),
             "--resolve", f"{DOMAIN}:{PORTS['xray']}:127.0.0.1",
             "--output", str(body), "--dump-header", str(headers), "--write-out", "%{http_version}\t%{http_code}",
             f"https://{DOMAIN}:{PORTS['xray']}/"], label,
        ).decode()
        require(raw == f"{version}\t{status}", "negotiated fallback HTTP version mismatch")
        locations = [line.split(":", 1)[1].strip() for line in headers.read_text().splitlines()
                     if line.lower().startswith("location:")]
        require(locations == [location], "HTTP/2 redirect location mismatch")
        self.record(label, {"strict_tls": True, "http_version": version, "status": status, "location": location,
                            "body_sha256": digest(body.read_bytes()),
                            "response_headers": self.public_bytes(label + ".headers", headers.read_bytes()),
                            "response_body": self.public_bytes(label + ".body", body.read_bytes())})
        self.checks.append(label)

    def website(self, label, *, status=200, contains=None, body=None, location=None, alpn="http/1.1"):
        context = ssl.create_default_context(cafile=str(self.private / "tls.crt"))
        context.set_alpn_protocols([alpn])
        with socket.create_connection(("127.0.0.1", PORTS["xray"]), timeout=5) as raw:
            with context.wrap_socket(raw, server_hostname=DOMAIN) as connection:
                require(connection.selected_alpn_protocol() == alpn, "ALPN negotiation mismatch")
                connection.sendall(f"GET / HTTP/1.1\r\nHost: {DOMAIN}\r\nConnection: close\r\n\r\n".encode())
                response = http.client.HTTPResponse(connection)
                response.begin()
                output = response.read()
                response_headers = list(response.getheaders())
                require(response.status == status and response.getheader("Location") == location, "site status/location mismatch")
                if contains is not None:
                    require(contains in output, "site marker missing")
                if body is not None:
                    require(output == body, "site body mismatch")
        self.record(label, {"strict_tls": True, "alpn": alpn, "status": status, "location": location,
                            "body_sha256": digest(output), "body_bytes": len(output),
                            "normalized_headers": response_headers,
                            "response_body": self.public_bytes(label + ".body", output)})
        self.checks.append(label)

    def sites(self):
        for theme in ("notes", "photos", "docs"):
            self.edit("--site-template", theme, "--site-title", "ARM64 & <acceptance>", label="site-template-" + theme)
            self.website("site-template-" + theme + "-positive", contains=b"ARM64 &amp; &lt;acceptance&gt;")
        source = self.inputs / "static"
        source.mkdir(mode=0o700)
        body = b"<h1>ARM64 formal static acceptance</h1>\n"
        (source / "index.html").write_bytes(body)
        (source / "index.html").chmod(0o600)
        self.edit("--site-static", str(source), label="site-static")
        self.website("site-static-positive", body=body)
        url = "https://example.com/path?a=1&b=2#part"
        self.edit("--site-redirect", url, label="site-redirect")
        self.website("site-redirect-positive", status=302, location=url)
        for index, order in enumerate(("h2,http/1.1", "http/1.1,h2", "http/1.1")):
            self.edit("--alpn", "entry-fallback", order, label="site-alpn-" + str(index))
            self.website("site-alpn-positive-" + str(index), status=302, location=url)
            self.website_negotiated("site-negotiated-positive-" + str(index), 302, url,
                                    "2" if index == 0 else "1.1")
        self.edit("--alpn", "entry-fallback", "h2,http/1.1", label="site-alpn-restore")
        self.edit("--site-default", label="site-default")
        self.website("site-default-positive")
        current = json.loads((ROOT / "config/spec.json").read_text())
        baseline = copy.deepcopy(self.original)
        baseline.setdefault("site", {"mode": "default"})
        baseline["core"]["protocols"][0]["fallback_tls"]["alpn"] = ["h2", "http/1.1"]
        require(current == baseline, "site restore changed unrelated spec")
        self.record("site-final-spec", {"explicit_default_site": current.get("site"),
                                      "explicit_default_alpn": current["core"]["protocols"][0]["fallback_tls"].get("alpn"),
                                      "only_defaults_added": True})
        self.checkpoint("sites-default", restored=True)

    def run(self):
        self.preflight()
        self.assets(NEW)
        self.install(NEW, "formal-install")
        self.configure()
        self.checkpoint("configured", restored=True)
        self.probe("wrong", "wrong-password-rejected", False)
        self.probe("wrong-sni", "wrong-sni-rejected", False)
        self.aliases()
        self.routing()
        self.relay()
        self.sites()
        self.cli("restart", label="formal-restart")
        self.checkpoint("restarted")
        self.website("site-after-restart")
        self.record("specialties", {"passed": not self.deferred_failures,
                                    "failed_checks": self.deferred_failures,
                                    "checks": self.checks, "phases": self.phases,
                                    "version": NEW["version"], "source": NEW["commit"],
                                    "scope": "native-arm64-ipv4-local-origin-two-cores",
                                    "reboot_tested": False, "public_inbound_tested": False,
                                    "h2_requests_tested": True, "connect_https_tested": True})
        require(not self.deferred_failures, "relay source checks failed: " + ",".join(self.deferred_failures))

    def cleanup(self):
        for server, thread in self.servers:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)
        result = super().cleanup()
        require(self.inputs.parent == Path("/root") and self.inputs.name.startswith(".padm-arm64-specialties-"),
                "unsafe input cleanup path")
        shutil.rmtree(self.inputs)
        self.record("specialties-input-cleanup", {"passed": not self.inputs.exists()})
        return result


def selfcheck():
    for name, port in PORTS.items():
        config = client_config("secret", 12345, port)
        require(config["outbounds"][0]["server_port"] == port, "client destination mismatch")
        require("insecure" not in config["outbounds"][0]["tls"], "TLS bypass refused")
    question = b"\x01\x02\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x03dns\x04padm\x04test\x00\x00\x01\x00\x01"
    require(parse_dns(question) == ("dns.padm.test", 1, len(question)), "DNS parse mismatch")
    for invalid in (question[:-1], question + b"x", question[:12] + b"\xff"):
        try:
            parse_dns(invalid)
        except (AssertionError, IndexError):
            pass
        else:
            raise AssertionError("malformed DNS accepted")
    edns = question[:10] + b"\x00\x01" + question[12:] + b"\x00\x00\x29\x04\xd0\x00\x00\x00\x00\x00\x00"
    require(parse_dns(edns) == ("dns.padm.test", 1, len(question)), "EDNS question mismatch")
    dns = socketserver.ThreadingUDPServer(("127.0.0.1", 0), Dns)
    dns.requests = []
    thread = threading.Thread(target=dns.serve_forever, daemon=True)
    thread.start()
    try:
        for request, status, answers in (
            (question, 0, 1), (edns, 0, 1),
            (question[:12] + b"\x09error-dns" + question[16:], 2, 0),
            (question[:-4] + b"\x00\x1c\x00\x01", 0, 0),
        ):
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as channel:
                channel.settimeout(2)
                channel.sendto(request, dns.server_address)
                response = channel.recv(4096)
            require(response[:2] == request[:2] and response[3] & 15 == status
                    and int.from_bytes(response[6:8], "big") == answers, "DNS fixture response mismatch")
            if answers:
                require(response[-4:] == socket.inet_aton(ORIGIN), "DNS fixture address mismatch")
    finally:
        dns.shutdown()
        dns.server_close()
        thread.join(timeout=5)
    print("specialties-selfcheck=passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--selfcheck", action="store_true")
    parser.add_argument("--work", type=Path)
    args = parser.parse_args()
    if args.selfcheck:
        selfcheck()
        return 0
    require(args.work is not None, "--work required")
    acceptance = Acceptance(args.work)
    passed, cleanup, kind, message = False, False, None, None
    try:
        acceptance.run()
        passed = True
    except BaseException as error:
        kind, message = type(error).__name__, str(error)
        with (acceptance.private / "error.log").open("w") as stream:
            traceback.print_exc(file=stream)
        print("specialties-failed phase=" + acceptance.current + " error=" + kind + ": " + message, flush=True)
    finally:
        try:
            cleanup = acceptance.cleanup()
        except BaseException as error:
            with (acceptance.private / "cleanup-error.log").open("w") as stream:
                traceback.print_exc(file=stream)
            print("cleanup-failed " + type(error).__name__ + ": " + str(error), flush=True)
        acceptance.finish(passed, cleanup, kind, message)
    print(f"specialties_passed={passed} cleanup_passed={cleanup}", flush=True)
    return 0 if passed and cleanup else 1


if __name__ == "__main__":
    raise SystemExit(main())
