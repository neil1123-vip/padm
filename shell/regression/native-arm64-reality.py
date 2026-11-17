"""Disposable native ARM64 acceptance of formal Reality and VLESS Encryption."""

import argparse
import copy
import http.client
import http.server
import importlib.util
import json
import os
from pathlib import Path
import re
import runpy
import select
import shutil
import signal
import socket
import socketserver
import ssl
import threading
import time
import traceback
import urllib.parse
import uuid


SPECIALTIES_PATH = Path(__file__).with_name("native-arm64-specialties.py")
loader = importlib.util.spec_from_file_location("specialties", SPECIALTIES_PATH)
specialties = importlib.util.module_from_spec(loader)
loader.loader.exec_module(specialties)
base = specialties.base
ROOT, CLI, NEW = base.ROOT, base.CLI, base.NEW
require, digest = base.require, base.digest
DOMAIN, ORIGIN = base.DOMAIN, base.ORIGIN
PORTS = {"entry-vision": 35466, "entry-xhttp": 35467}
WS_PORT, RELAY_PORT = 35468, 8446
TARGET, WEBSITE, WEBSITE_IP = "pgxn.org", "b.951101.xyz", "23.185.168.63"
MIHOMO = {
    "reference": "metacubex/mihomo:v1.19.28@sha256:e6acd921addecfd59a8e2d38203f88356d635b54de6c0673db0e015139989312",
    "index_digest": "sha256:e6acd921addecfd59a8e2d38203f88356d635b54de6c0673db0e015139989312",
    "arm64_manifest": "sha256:003019de714f19a6f2530ef578fa2f91eaf031a6b6147c9fe1388b67fa97ea1a",
    "version": "v1.19.28",
}
ENCRYPTION_PHASES = (
    "configured", "vision-enabled", "both-enabled", "both-restarted", "encryption-restored",
)
TOPOLOGY_PHASES = tuple(
    "stream-" + entry + "-" + topology
    for entry in ("vision", "xhttp") for topology in ("managed", "host", "loopback")
)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def uri_parts(uri):
    parsed = urllib.parse.urlsplit(uri)
    require(parsed.scheme == "vless" and parsed.hostname and parsed.port and parsed.username,
            "invalid VLESS share")
    pairs = urllib.parse.parse_qs(parsed.query, keep_blank_values=True, strict_parsing=True)
    require(all(len(values) == 1 and values[0] for values in pairs.values()), "ambiguous VLESS query")
    return parsed, {key: values[0] for key, values in pairs.items()}


def mutate_uri(uri, *, credential=None, encryption=None):
    parsed, query = uri_parts(uri)
    if encryption is not None:
        query["encryption"] = encryption
    if credential is not None:
        parsed = parsed._replace(netloc=credential + "@" + parsed.netloc.rsplit("@", 1)[1])
    return urllib.parse.urlunsplit(parsed._replace(query=urllib.parse.urlencode(query)))


def uri_projection(uri, listener):
    parsed, query = uri_parts(uri)
    return {
        "scheme": parsed.scheme, "host": parsed.hostname, "port": parsed.port,
        "listener": listener, "uuid_sha256": digest(parsed.username.encode()),
        "query": {
            key: digest(value.encode()) if key in ("encryption", "pbk", "sid", "pqv") else value
            for key, value in query.items()
        },
    }


def xray_projection(uri, local, helper):
    result = helper(uri, local)
    _, query = uri_parts(uri)
    if "pqv" in query:
        result["outbounds"][0]["streamSettings"]["realitySettings"]["mldsa65Verify"] = query["pqv"]
    return result


def mihomo_projection(uri, local):
    parsed, query = uri_parts(uri)
    require("pqv" not in query, "fixed Mihomo ML-DSA projection is outside this acceptance")
    node = {
        "name": "entry", "type": "vless", "server": parsed.hostname, "port": parsed.port,
        "uuid": parsed.username, "tls": True, "encryption": query["encryption"],
        "network": query["type"], "ip-version": "ipv4",
        "client-fingerprint": query["fp"], "servername": query["sni"],
        "reality-opts": {"public-key": query["pbk"], "short-id": query["sid"],
                         "support-x25519mlkem768": True},
    }
    if "flow" in query:
        node["flow"] = query["flow"]
    if query["type"] == "xhttp":
        node["xhttp-opts"] = {key: query[key] for key in ("path", "host", "mode")}
        if "extra" in query:
            node["xhttp-opts"]["extra"] = json.loads(query["extra"])
    return {
        "mode": "rule", "log-level": "debug", "ipv6": False,
        "proxies": [node],
        "listeners": [{"name": "entry", "type": "socks", "listen": "127.0.0.1",
                       "port": local, "proxy": "entry"}],
        "rules": ["MATCH,REJECT"],
    }


def baseline_spec(protocols, core_credential, account, account_uuid, password, token):
    return {
        "schema_version": 3,
        "core": {"type": "xray", "secondary_type": None, "protocols": [
            *copy.deepcopy(protocols), {
                "id": 21, "core": "xray", "listener_id": "entry-website", "server": "127.0.0.1",
                "public_port": WS_PORT, "address_families": ["ipv4"], "name": "arm64-website",
                "uuid": core_credential,
                "websocket": {"domain": DOMAIN, "path": "arm64-ws",
                              "backend_port": 31297, "tls_port": 8443},
            },
        ]},
        "accounts": [{"id": account, "name": "arm64-independent", "enabled": True,
                      "uuid": account_uuid, "password": password, "shadowsocks_password": None,
                      "listeners": list(PORTS)}],
        "tls": {"domain": DOMAIN}, "subscription": {"enabled": False, "token": token},
        "host_integrations": [], "site": {"mode": "default"},
    }


def result_valid(row, body):
    if row["accepted"]:
        return (
            row["curl_exit"] == 0 and bool(body)
            and len(body) == row["expected_bytes"] and digest(body) == row["expected_sha256"]
            and len(row["origin_tcp"]) == len(row["origin_requests"]) == 1
            and row["origin_requests"][0]["path"] == row["nonce"]
            and row["origin_requests"][0]["peer"] in row["expected_origin_peers"]
            and row["origin_tcp"][0]["peer"] in row["expected_origin_peers"]
        )
    return row["curl_exit"] not in (0, 28, "timeout") and not body and not row["origin_tcp"] and not row["origin_requests"]


class Relay(socketserver.BaseRequestHandler):
    def handle(self):
        row = {"inbound_peer": list(self.client_address), "upstream": [WEBSITE_IP, 443],
               "upstream_peer": None, "upload": 0, "download": 0, "error_type": None, "completed": False}
        self.server.connections.append(row)
        try:
            with socket.create_connection((WEBSITE_IP, 443), timeout=8) as upstream:
                row["upstream_peer"] = list(upstream.getpeername())
                self.request.setblocking(False)
                upstream.setblocking(False)
                channels = {self.request: (upstream, "upload"), upstream: (self.request, "download")}
                deadline = time.monotonic() + 25
                while channels and time.monotonic() < deadline:
                    ready, _, _ = select.select(list(channels), [], [], 1)
                    for source in ready:
                        destination, counter = channels[source]
                        data = source.recv(65536)
                        if not data:
                            del channels[source]
                            try:
                                destination.shutdown(socket.SHUT_WR)
                            except OSError:
                                pass
                            continue
                        destination.setblocking(True)
                        destination.settimeout(8)
                        destination.sendall(data)
                        destination.setblocking(False)
                        row[counter] += len(data)
        except OSError as error:
            row["error_type"] = type(error).__name__
        finally:
            row["completed"] = True


class RelayServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


class Acceptance(specialties.Acceptance):
    def __init__(self, work):
        super().__init__(work)
        # 正式 Reality 探测拒绝临时路径中 runner 用户拥有的祖先目录。
        self.env["TMPDIR"] = "/tmp"
        temporary = Path(self.env["TMPDIR"]).stat()
        self.proxy_checks = []
        self.site_checks = []
        self.checkpoint_rows = {}
        self.origin_tcp = []
        self.known_secrets = [self.account, self.core_credential, self.account_uuid, self.managed_password]
        self.last_services = {}
        self.relay = None
        self.record("reality-identity", {
            "driver_sha256": digest(Path(__file__).read_bytes()),
            "specialties_driver_sha256": digest(SPECIALTIES_PATH.read_bytes()),
            "base_driver_sha256": digest(specialties.BASE_PATH.read_bytes()),
            "release": NEW, "scope": "native-arm64-ipv4-local-origin-reality-encryption",
            "clients": ["signed-release-xray", "pinned-mihomo-v1.19.28-explicit-hybrid"],
            "mihomo_original_uri_import_claimed": False,
            "cli_tmpdir": self.env["TMPDIR"],
            "cli_tmpdir_metadata": {"uid": temporary.st_uid, "gid": temporary.st_gid,
                                    "mode": temporary.st_mode & 0o7777},
            "engine_reinstallation_requested": False,
            "public_inbound_tested": False, "reboot_tested": False,
            "relay": {"listen": ["0.0.0.0", RELAY_PORT], "upstream": [WEBSITE_IP, 443],
                      "server_name": WEBSITE, "transparent_tcp": True, "local_tls_termination": False},
        })

    def spec(self):
        return json.loads((ROOT / "config/spec.json").read_text())

    def command(self, arguments, label, **options):
        previous = len(self.commands)
        try:
            return super().command(arguments, label, **options)
        finally:
            if len(self.commands) > previous and arguments[0] == CLI:
                self.commands[-1]["argv"] = [
                    "sha256:" + digest(value.encode()) if value in
                    (self.account, self.account_uuid, self.core_credential, self.managed_password)
                    else value.replace(str(self.private), "<private>").replace(str(self.inputs), "<private-input>")
                    for value in arguments
                ]

    def remember(self, spec):
        for entry in spec["core"]["protocols"]:
            self.known_secrets.extend(entry.get("reality", {}).values())
            self.known_secrets.extend(entry.get("vless_encryption", {}).values())
        self.known_secrets.append(spec["subscription"]["token"])

    def scrub(self, raw):
        value = raw.decode(errors="replace") if isinstance(raw, bytes) else raw
        secrets = {secret for secret in self.known_secrets if isinstance(secret, str) and secret}
        for secret in sorted(secrets, key=len, reverse=True):
            value = value.replace(secret, "<redacted>")
        value = re.sub(r"vless://\S+", "<private-uri>", value)
        return re.sub(r"[A-Za-z0-9_+/=-]{40,}", "<opaque-material>", value)

    def command_diagnostic(self, label):
        row = self.commands[-1]
        stem = f'{row["sequence"]:04d}-{row["label"]}'
        stdout = (self.private / (stem + ".stdout")).read_bytes()
        stderr = (self.private / (stem + ".stderr")).read_bytes()
        return {
            "command_sequence": row["sequence"], "exit": row["exit"],
            "stdout_sha256": row["stdout_sha256"], "stderr_sha256": row["stderr_sha256"],
            "diagnostic": self.scrub(stdout + stderr)[-5000:],
        }

    def services(self, label):
        spec = self.spec()
        stream = spec.get("reality_stream") or {}
        loopback = stream.get("host_website", {}).get("network_mode") == "host"
        expected = {"xray", "nginx"} | ({"nginx-stream"} if loopback else set())
        deadline = time.monotonic() + 120
        while True:
            ids = self.command(
                ["docker", "ps", "-aq", "--filter", "label=com.docker.compose.project=padm-docker"],
                label + "-service-list",
            ).decode().split()
            rows = self.json_command(["docker", "inspect", *ids], label + "-service-inspect") if ids else []
            result = {row["Config"]["Labels"]["com.docker.compose.service"]: row for row in rows}
            if len(rows) == len(expected) and set(result) == expected and all(
                row["State"]["Running"] and row["State"].get("Health", {}).get("Status") == "healthy"
                for row in rows
            ):
                break
            if time.monotonic() >= deadline:
                self.record(label + "-service-failure", {
                    name: {"state": row["State"], "image": row["Config"]["Image"]}
                    for name, row in result.items()
                })
                raise AssertionError("service health deadline exceeded")
            time.sleep(1)
        for name, row in result.items():
            host = row["HostConfig"]
            require(host["ReadonlyRootfs"] and not host["Privileged"] and host["CapDrop"] == ["ALL"],
                    "service isolation changed")
            require("no-new-privileges:true" in host["SecurityOpt"], "service privilege boundary changed")
            if name == "nginx-stream":
                isolated = (host["NetworkMode"] == "host" and row["Config"]["User"] == "0:0"
                            and {cap.removeprefix("CAP_") for cap in (host["CapAdd"] or [])}
                            == {"NET_BIND_SERVICE", "SETGID", "SETUID", "KILL"})
                if not isolated:
                    self.record(label + "-loopback-isolation-failure", {
                        "network_mode": host["NetworkMode"], "user": row["Config"]["User"],
                        "cap_add": host["CapAdd"], "cap_drop": host["CapDrop"],
                        "readonly_rootfs": host["ReadonlyRootfs"], "privileged": host["Privileged"],
                        "security_opt": host["SecurityOpt"],
                    })
                require(isolated, "loopback stream isolation mismatch")
            else:
                require(host["NetworkMode"] != "host" and set(row["NetworkSettings"]["Networks"]) == {"padm-docker"},
                        "service bridge network mismatch")
        self.last_services = result
        return result

    def image_proof(self, manifest, services, label):
        proof = super().image_proof(manifest, services, label)
        if "nginx-stream" in services:
            row = services["nginx-stream"]
            require(row["Image"] == proof["nginx"]["image_id"]
                    and row["Config"]["Image"] == proof["nginx"]["reference"],
                    "nginx-stream differs from signed nginx image")
        return proof

    def mihomo_asset(self):
        self.command(["docker", "pull", MIHOMO["reference"]], "mihomo-pull", timeout=900)
        self.pulled_references.append(MIHOMO["reference"])
        raw = self.command(["docker", "buildx", "imagetools", "inspect", "--raw", MIHOMO["reference"]],
                           "mihomo-index")
        index_file = self.public_bytes("mihomo-index.json", raw)
        index = json.loads(raw)
        rows = [item for item in index["manifests"]
                if item.get("platform", {}).get("os") == "linux"
                and item.get("platform", {}).get("architecture") == "arm64"]
        require("sha256:" + digest(raw) == MIHOMO["index_digest"]
                and len(rows) == 1 and rows[0]["digest"] == MIHOMO["arm64_manifest"],
                "Mihomo pinned ARM64 index mismatch")
        raw = self.command(["docker", "buildx", "imagetools", "inspect", "--raw",
                            "metacubex/mihomo@" + MIHOMO["arm64_manifest"]], "mihomo-arm64-manifest")
        platform_file = self.public_bytes("mihomo-arm64-manifest.json", raw)
        require("sha256:" + digest(raw) == MIHOMO["arm64_manifest"], "Mihomo ARM64 manifest mismatch")
        config = json.loads(raw)["config"]["digest"]
        image = self.json_command(["docker", "image", "inspect", MIHOMO["reference"]], "mihomo-inspect")[0]
        kind = base.image_id_kind(image["Id"], config, MIHOMO["index_digest"], self.containerd_image_store)
        require(image["Os"] == "linux" and image["Architecture"] == "arm64"
                and "metacubex/mihomo@" + MIHOMO["index_digest"] in image["RepoDigests"],
                "Mihomo native image mismatch")
        version = self.command(
            ["docker", "run", "--rm", "--network", "none", "--read-only", "--cap-drop", "ALL",
             "--security-opt", "no-new-privileges:true", "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=16m",
             MIHOMO["reference"], "-v"], "mihomo-version",
        ).decode().strip()
        self.mihomo_proof = {
            **MIHOMO, "image_id": image["Id"], "config_digest": config, "image_id_kind": kind,
            "architecture": image["Architecture"], "repo_digests": image["RepoDigests"],
            "version_output": version, "index_file": index_file, "platform_file": platform_file,
        }
        self.record("mihomo-image", self.mihomo_proof)
        require(MIHOMO["version"] in version, "Mihomo version mismatch")

    def tool(self, *arguments, label):
        image = self.releases[NEW["version"]][1]["images"]["xray"]["reference"]
        return self.command(
            ["docker", "run", "--rm", "--network", "none", "--read-only", "--cap-drop", "ALL",
             "--security-opt", "no-new-privileges:true", "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=8m",
             image, *arguments], label,
        )

    def configure(self):
        _, manifest, directory = self.releases[NEW["version"]]
        helper_path = self.source[NEW["version"]] / "docker/tests/vless-encryption-real.py"
        self.xray_helper = runpy.run_path(str(helper_path))["xray_client"]
        self.record("client-projection-source", {"file": "docker/tests/vless-encryption-real.py",
                                               "sha256": digest(helper_path.read_bytes()),
                                               "source": NEW["commit"], "helper_main_used": False,
                                               "pqv_field": "mldsa65Verify"})
        key, cert = self.private / "tls.key", self.private / "tls.crt"
        self.command(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
                      "-subj", "/CN=" + DOMAIN, "-addext", "subjectAltName=DNS:" + DOMAIN,
                      "-keyout", str(key), "-out", str(cert)], "create-managed-ca")
        self.cli("tls", "install", "--domain", DOMAIN, "--cert", str(cert), "--key", str(key),
                 "--ops-image", manifest["images"]["ops"]["reference"], label="formal-tls")
        protocols = []
        pairs = []
        for identifier, listener in enumerate(PORTS, 1):
            raw = self.tool("x25519", label="generate-reality-" + listener).decode()
            private = re.search(r"^PrivateKey:\s*(\S+)", raw, re.M)
            public = re.search(r"^(?:Password \(PublicKey\)|PublicKey):\s*(\S+)", raw, re.M)
            require(private and public, "Reality tool output incomplete")
            entry = {
                "id": identifier, "core": "xray", "listener_id": listener,
                "server": "127.0.0.1", "public_port": PORTS[listener], "address_families": ["ipv4"],
                "name": listener, "uuid": self.core_credential,
                "reality": {"server_name": TARGET, "target_host": TARGET, "target_port": 443,
                            "private_key": private[1], "public_key": public[1], "short_id": os.urandom(8).hex()},
            }
            if identifier == 2:
                entry["xhttp"] = {"path": "/arm64-reality-xhttp", "host": TARGET, "mode": "packet-up"}
            protocols.append(entry)
            raw = self.tool("vlessenc", label="generate-pair-" + listener).decode()
            heading = "Authentication: ML-KEM-768, Post-Quantum"
            require(raw.count(heading) == 1, "encryption tool heading mismatch")
            pair = dict(re.findall(r'^\s*"(decryption|encryption)"\s*:\s*"([^"\s]+)"\s*,?\s*$',
                                   raw.split(heading, 1)[1], re.M))
            require(set(pair) == {"decryption", "encryption"}, "encryption tool output incomplete")
            pairs.append(pair)
            self.known_secrets.extend(pair.values())
        spec = baseline_spec(protocols, self.core_credential, self.account, self.account_uuid,
                             self.managed_password, uuid.uuid4().hex)
        spec = base.expected_spec(spec, NEW, manifest)
        self.remember(spec)
        wrong = copy.deepcopy(spec)
        wrong["core"]["protocols"][0]["vless_encryption"] = {
            "decryption": pairs[0]["decryption"], "encryption": pairs[1]["encryption"],
        }
        before = sorted(path.name for pattern in (".setup.*", ".candidate.*") for path in ROOT.glob(pattern))
        wrong_path = self.secure_json("wrongpair-configure", wrong)
        self.command(
            [CLI, "configure", "--spec", wrong_path, "--manifest", str(directory / base.NAMES[0]),
             "--bundle", str(directory / base.NAMES[1]), "--control-bundle", str(directory / base.NAMES[2])],
            "wrongpair-configure-rejected", timeout=900, allowed=tuple(range(126)),
        )
        diagnostic = self.command_diagnostic("wrongpair")
        after = sorted(path.name for pattern in (".setup.*", ".candidate.*") for path in ROOT.glob(pattern))
        self.record("wrongpair-configure", {
            **diagnostic, "candidate_before": before, "candidate_after": after,
            "installed_spec_absent": not (ROOT / "config/spec.json").exists(),
            "runtime_absent": not (ROOT / "compose.json").exists(),
            "mismatched_encryption_sha256": digest(pairs[1]["encryption"].encode()),
            "decryption_pair_encryption_sha256": digest(pairs[0]["encryption"].encode()),
        })
        require(diagnostic["exit"] != 0 and "VLESS Encryption 配对校验失败" in diagnostic["diagnostic"]
                and before == after and not (ROOT / "config/spec.json").exists()
                and not (ROOT / "compose.json").exists(), "wrongpair failed at unexpected gate")
        path = self.secure_json("configure", spec)
        self.cli("configure", "--spec", path, "--manifest", str(directory / base.NAMES[0]),
                 "--bundle", str(directory / base.NAMES[1]), "--control-bundle", str(directory / base.NAMES[2]),
                 label="formal-configure")
        self.services("formal-configure")
        self.cli("traffic", "collect", label="initial-collect")
        self.cli("traffic", "limit", self.account, "1", label="account-quota")
        self.original = self.spec()
        self.business = self.business_tree()
        self.last_ledger = self.ledger()
        require(set(self.last_ledger) == {self.account, self.core_credential}, "account identity mismatch")
        require(self.last_ledger[self.account]["limit_bytes"] == 1024 ** 3, "quota mismatch")
        self.frozen_accounts = digest(canonical(self.original["accounts"]))
        self.frozen_token = digest(self.original["subscription"]["token"].encode())
        self.frozen_reality = self.reality_proof(self.original)
        self.frozen_material = self.material_hashes()
        self.command(["ip", "address", "add", ORIGIN + "/32", "dev", "lo"], "origin-add")
        self.origin_added = True
        route = self.json_command(["ip", "-j", "route", "get", ORIGIN], "origin-route")
        self.record("origin", {"address": ORIGIN, "route": route, "local_fixture": True,
                               "public_network_test": False})
        require(len(route) == 1 and route[0].get("type") == "local" and route[0]["dev"] == "lo",
                "nonce origin is not local")
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

        class OriginServer(http.server.ThreadingHTTPServer):
            daemon_threads = True

            def get_request(self):
                connection, peer = super().get_request()
                owner.origin_tcp.append({"peer": peer[0]})
                return connection, peer

        self.origin = self.server(OriginServer((ORIGIN, 0), Origin))
        self.relay = RelayServer(("0.0.0.0", RELAY_PORT), Relay)
        self.relay.connections = []
        self.server(self.relay)
        self.record("transparent-relay", {
            "pid": os.getpid(), "pid_starttime": Path("/proc/self/stat").read_text().split()[21],
            "listen": ["0.0.0.0", RELAY_PORT], "fixed_upstream": [WEBSITE_IP, 443],
            "server_name": WEBSITE, "transparent_tcp": True, "local_tls_termination": False,
            "listener_ss": self.command(["ss", "-lntHp", f"sport = :{RELAY_PORT}"], "relay-listener").decode(),
        })
        self.managed_body = self.tls_probe("managed-site-baseline", "configured", DOMAIN, "127.0.0.1",
                                           WS_PORT, local_ca=True, auxiliary=True)
        self.remote_body = self.tls_probe("remote-direct-baseline", "configured", WEBSITE, WEBSITE_IP,
                                          443, auxiliary=True)
        self.tls_probe("remote-relay-baseline", "configured", WEBSITE, "127.0.0.1", RELAY_PORT,
                       expected=self.remote_body, auxiliary=True)

    def material_hashes(self):
        return {name: row for name, row in self.business_tree().items()
                if name.startswith(("secrets/tls", "data/subscription", "config/share-groups.json"))}

    def reality_proof(self, spec):
        return {
            entry["listener_id"]: {
                key: digest(value.encode()) if key in
                ("private_key", "public_key", "short_id", "mldsa65_seed", "mldsa65_verify") else value
                for key, value in entry["reality"].items()
            }
            for entry in spec["core"]["protocols"] if entry["listener_id"] in PORTS
        }

    def links(self, phase):
        raw = self.cli("protocol", "links", label=phase + "-links")
        values = [value for value in raw.decode().splitlines() if value.startswith("vless://")]
        result = {}
        for uri in values:
            parsed, query = uri_parts(uri)
            if parsed.username != self.account_uuid or query.get("security") != "reality":
                continue
            listener = {"tcp": "entry-vision", "xhttp": "entry-xhttp"}.get(query["type"])
            require(listener in PORTS and listener not in result, "ambiguous account Reality share")
            result[listener] = uri
        projections = {listener: uri_projection(uri, listener) for listener, uri in result.items()}
        self.record(phase + "-links", {"phase": phase, "projection": projections,
                                      "private_output_sha256": digest(raw)})
        require(set(result) == set(PORTS), "independent account links missing")
        spec = self.spec()
        selected = (spec.get("reality_stream") or {}).get("listener_id")
        for listener, uri in result.items():
            parsed, query = uri_parts(uri)
            entry = next(row for row in spec["core"]["protocols"] if row["listener_id"] == listener)
            require(parsed.hostname == "127.0.0.1" and parsed.port == (443 if selected == listener else PORTS[listener]),
                    "share port projection mismatch")
            require(query["sni"] == TARGET and query["pbk"] == entry["reality"]["public_key"]
                    and query["sid"] == entry["reality"]["short_id"] and query["fp"] == "chrome"
                    and query["encryption"] == entry.get("vless_encryption", {}).get("encryption", "none"),
                    "share material projection mismatch")
            require(query.get("pqv") == entry["reality"].get("mldsa65_verify"), "ML-DSA share projection mismatch")
        return result

    def client_view(self, row):
        host = row["HostConfig"]
        return {
            "id": row["Id"], "image_id": row["Image"], "image": row["Config"]["Image"],
            "network_mode": host["NetworkMode"], "readonly": host["ReadonlyRootfs"],
            "cap_drop": host["CapDrop"], "cap_add": host["CapAdd"], "privileged": host["Privileged"],
            "security_opt": host["SecurityOpt"], "user": row["Config"]["User"],
            "tmpfs": host["Tmpfs"], "pid": row["State"]["Pid"],
        }

    def probe(self, uri, listener, client, phase, *, accepted=True, negative_kind=None):
        label = phase + "-" + listener + "-" + client + "-" + (negative_kind or "positive")
        directory = self.private / ("client-" + label)
        directory.mkdir(mode=0o755)
        directory.chmod(0o755)
        with socket.socket() as channel:
            channel.bind(("127.0.0.1", 0))
            local = channel.getsockname()[1]
        config = xray_projection(uri, local, self.xray_helper) if client == "xray" else mihomo_projection(uri, local)
        (directory / "config.json").write_text(json.dumps(config))
        (directory / "config.json").chmod(0o644)
        if client == "mihomo":
            # 固定版本的 URI 导入丢失 hybrid 参数，显式投影并保留原分享取证。
            (directory / "source-uri.txt").write_text(uri + "\n")
            (directory / "source-uri.txt").chmod(0o644)
        image = self.releases[NEW["version"]][1]["images"]["xray"]["reference"] if client == "xray" else MIHOMO["reference"]
        arguments = ["run", "-c", "/input/config.json"] if client == "xray" else ["-d", "/tmp", "-f", "/input/config.json"]
        isolation = [
            "--network", "host", "--read-only", "--cap-drop", "ALL", "--security-opt", "no-new-privileges:true",
            "--user", "10001:10001", "--mount", f"type=bind,src={directory},dst=/input,readonly",
            "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=32m",
        ]
        if client == "mihomo":
            isolation.extend(["--tmpfs", "/root/.config/mihomo:rw,noexec,nosuid,nodev,size=8m"])
        try:
            self.command(["docker", "run", "--rm", *isolation, image, *arguments,
                          *(["-test"] if client == "xray" else ["-t"])], label + "-config-test")
        except AssertionError:
            self.record(label + "-config-failure", {
                "kind": "client-config-failure", "label": label, "phase": phase,
                "listener": listener, "client": client, **self.command_diagnostic(label),
            })
            raise
        config_test_sequence = self.commands[-1]["sequence"]
        container = self.command(["docker", "run", "-d", *isolation, image, *arguments],
                                 label + "-client-start").decode().strip()
        self.containers.add(container)
        inspect = None
        try:
            deadline = time.monotonic() + 30
            while True:
                inspect = self.json_command(["docker", "inspect", container], label + "-client-inspect")[0]
                require(inspect["State"]["Running"], "client exited before runtime probe")
                listening = self.command(["ss", "-lntHp", f"sport = :{local}"], label + "-client-listener").decode()
                if f'pid={inspect["State"]["Pid"]},' in listening:
                    break
                require(time.monotonic() < deadline, "client listener deadline exceeded")
                time.sleep(0.2)
            tcp_before, request_before = len(self.origin_tcp), len(self.requests)
            nonce = "/" + uuid.uuid4().hex
            output = self.command(
                ["curl", "--fail", "--silent", "--show-error", "--max-time", "8", "--noproxy", "",
                 # 正反例都发送足够首包，避免旧 none 请求在 ML-KEM 校验前等到超时。
                 "--header", "X-Padm-Probe: " + "p" * 4096,
                 "--socks5-hostname", "127.0.0.1:" + str(local),
                 f"http://{ORIGIN}:{self.origin.server_port}{nonce}"],
                label + "-request", timeout=12, allowed=tuple(range(126)),
            )
            command = copy.deepcopy(self.commands[-1])
            expected = (nonce.encode() + b"\n") * 4096
            peers = sorted(row["IPAddress"] for row in
                           self.last_services["xray"]["NetworkSettings"]["Networks"].values() if row.get("IPAddress"))
            self.command(["docker", "logs", container], label + "-client-log", allowed=tuple(range(126)))
            log_command = self.command_diagnostic(label)
            row = {
                "kind": "proxy", "label": label, "phase": phase, "listener": listener, "client": client,
                "client_projection": "formal-uri-xray" if client == "xray" else "formal-uri-mihomo-explicit-hybrid",
                "accepted": accepted, "negative_kind": negative_kind, "curl_exit": command["exit"],
                "request_padding_bytes": 4096,
                "command_sequence": command["sequence"], "nonce": nonce,
                "response_body": self.public_bytes(label + ".body", output),
                "expected_sha256": digest(expected), "expected_bytes": len(expected),
                "origin_tcp": self.origin_tcp[tcp_before:], "origin_requests": self.requests[request_before:],
                "expected_origin_peers": peers, "uri_projection": uri_projection(uri, listener),
                "client_container": container, "client_image": image, "client_inspect": self.client_view(inspect),
                "client_config_sha256": digest((directory / "config.json").read_bytes()),
                "client_log": log_command, "local_origin": True,
                "config_test_passed": True, "config_test_command_sequence": config_test_sequence,
                "runtime_listener_ready": True,
            }
            self.record(label, row)
            self.proxy_checks.append(label)
            require(result_valid(row, output), "runtime proxy result mismatch: " + label)
            view = row["client_inspect"]
            require(view["network_mode"] == "host" and view["readonly"] and view["cap_drop"] == ["ALL"]
                    and not view["privileged"] and view["user"] == "10001:10001"
                    and "no-new-privileges:true" in view["security_opt"], "client isolation mismatch")
            if client == "mihomo":
                require((directory / "source-uri.txt").read_text() == uri + "\n", "original formal URI record changed")
            return label
        finally:
            if container:
                self.command(["docker", "rm", "-fv", container], label + "-client-remove")
                self.containers.discard(container)

    def tls_probe(self, label, phase, server_name, address, port, *, expected=None,
                  local_ca=False, accepted=True, auxiliary=False):
        context = ssl.create_default_context(cafile=str(self.private / "tls.crt")) if local_ca else ssl.create_default_context()
        context.set_alpn_protocols(["http/1.1"])
        body, response_headers, status, error_type, tls_version, alpn, certificate = b"", [], None, None, None, None, None
        before = len(self.relay.connections) if self.relay else 0
        try:
            with socket.create_connection((address, port), timeout=10) as raw:
                with context.wrap_socket(raw, server_hostname=server_name) as channel:
                    channel.settimeout(10)
                    tls_version, alpn = channel.version(), channel.selected_alpn_protocol()
                    certificate = digest(channel.getpeercert(binary_form=True))
                    channel.sendall(f"GET / HTTP/1.1\r\nHost: {server_name}\r\nConnection: close\r\n\r\n".encode())
                    response = http.client.HTTPResponse(channel)
                    response.begin()
                    status, response_headers = response.status, list(response.getheaders())
                    body = response.read()
                    # 完成 TLS 关闭握手，避免未读记录在 TCP close 时触发中继 RST。
                    channel.unwrap().close()
        except (OSError, http.client.HTTPException) as error:
            error_type = type(error).__name__
        deadline = time.monotonic() + 2
        while self.relay and any(not row["completed"] for row in self.relay.connections[before:]):
            if time.monotonic() >= deadline:
                break
            time.sleep(0.02)
        row = {
            "kind": "website-auxiliary" if auxiliary else "website", "label": label, "phase": phase,
            "accepted": accepted, "strict_tls": True, "server_name": server_name, "address": address,
            "port": port, "local_ca": local_ca, "status": status, "error_type": error_type,
            "tls_version": tls_version, "alpn": alpn, "certificate_sha256": certificate,
            "response_headers": response_headers, "response_body": self.public_bytes(label + ".body", body),
            "expected_sha256": digest(expected) if expected is not None else None,
            "relay_connections": copy.deepcopy(self.relay.connections[before:]) if self.relay else [],
        }
        self.record(label, row)
        if not auxiliary:
            self.site_checks.append(label)
        if accepted:
            require(error_type is None and status == 200 and bool(body) and alpn == "http/1.1"
                    and (expected is None or body == expected), "strict website result mismatch: " + label)
        else:
            require(error_type in ("SSLCertVerificationError", "SSLError")
                    and status is None and not body, "wrong SNI was not rejected by TLS")
        return body

    def topology_site(self, phase, topology):
        managed = topology == "managed"
        expected = self.managed_body if managed else self.remote_body
        name = DOMAIN if managed else WEBSITE
        if not managed:
            for kind, address, port in (("direct", WEBSITE_IP, 443), ("relay", "127.0.0.1", RELAY_PORT)):
                self.tls_probe(phase + "-" + kind + "-before", phase, WEBSITE, address, port,
                               expected=expected, auxiliary=True)
        self.tls_probe(phase + "-site", phase, name, "127.0.0.1", 443, expected=expected, local_ca=managed)
        self.tls_probe(phase + "-wrong-sni", phase, "wrong-arm64.padm.test", "127.0.0.1", 443,
                       local_ca=managed, accepted=False)
        if not managed:
            for kind, address, port in (("direct", WEBSITE_IP, 443), ("relay", "127.0.0.1", RELAY_PORT)):
                self.tls_probe(phase + "-" + kind + "-after", phase, WEBSITE, address, port,
                               expected=expected, auxiliary=True)

    def service_view(self, row):
        host = row["HostConfig"]
        return {
            **self.client_view(row), "started_at": row["State"]["StartedAt"],
            "health": row["State"].get("Health", {}).get("Status"),
            "port_bindings": host["PortBindings"],
            "ports": row["NetworkSettings"]["Ports"],
            "networks": {name: {"ipv4": value.get("IPAddress"), "network_id": value.get("NetworkID")}
                         for name, value in row["NetworkSettings"]["Networks"].items()},
        }

    def checkpoint(self, phase, *, clients=("xray",), restored=False, wrong_uuid=False):
        services = self.services(phase)
        spec = self.spec()
        self.remember(spec)
        _, manifest, _ = self.releases[NEW["version"]]
        images = self.image_proof(manifest, services, phase)
        bundle = self.bundle_proof(NEW)
        links = self.links(phase)
        current = self.ledger()
        base.preserved(self.last_ledger, current)
        probes = [self.probe(links[listener], listener, client, phase)
                  for listener in PORTS for client in clients]
        if phase == "both-enabled":
            for listener in PORTS:
                other = next(name for name in PORTS if name != listener)
                _, other_query = uri_parts(links[other])
                for client in clients:
                    probes.append(self.probe(self.baseline_links[listener], listener, client, phase,
                                             accepted=False, negative_kind="old-none"))
                    probes.append(self.probe(
                        mutate_uri(links[listener], encryption=other_query["encryption"]),
                        listener, client, phase, accepted=False, negative_kind="wrong-encryption",
                    ))
        if wrong_uuid:
            listener = spec["reality_stream"]["listener_id"]
            probes.append(self.probe(mutate_uri(links[listener], credential=str(uuid.uuid4())),
                                     listener, "xray", phase, accepted=False, negative_kind="wrong-uuid"))
        deadline = time.monotonic() + 25
        while True:
            self.cli("traffic", "collect", label=phase + "-collect")
            after = self.ledger()
            base.preserved(current, after)
            if all(after[self.account][key] > current[self.account][key] for key in ("upload", "download")):
                break
            require(time.monotonic() < deadline, "independent account traffic did not increase")
            time.sleep(1)
        self.last_ledger = after
        stream = spec.get("reality_stream")
        published = self.command(["ss", "-lntHp", "sport = :443"], phase + "-443-owner").decode()
        with socket.socket() as channel:
            channel.settimeout(2)
            connected = channel.connect_ex(("127.0.0.1", 443)) == 0
        encryption = {}
        for entry in spec["core"]["protocols"]:
            if entry["listener_id"] not in PORTS:
                continue
            pair = entry.get("vless_encryption")
            encryption[entry["listener_id"]] = {
                "enabled": pair is not None,
                "pair_sha256": digest(canonical(pair)) if pair else None,
                "encryption_sha256": digest(pair["encryption"].encode()) if pair else None,
                "decryption_sha256": digest(pair["decryption"].encode()) if pair else None,
            }
        row = {
            "kind": "checkpoint", "passed": True, "phase": phase,
            "version": NEW["version"], "source": NEW["commit"], "bundle": bundle, "images": images,
            "ledger_before": self.public_ledger(current), "ledger_after": self.public_ledger(after),
            "account_identity_sha256": digest(self.account.encode()),
            "account_material_sha256": digest(canonical(spec["accounts"])),
            "token_sha256": digest(spec["subscription"]["token"].encode()),
            "business_tree": self.business_tree(), "material_hashes": self.material_hashes(),
            "encryption": encryption, "reality": self.reality_proof(spec),
            "services": {name: self.service_view(value) for name, value in services.items()},
            "stream": stream, "ports": {"owner_443_ss": published, "accepts_443": connected},
            "probe_labels": probes, "spec_sha256": digest((ROOT / "config/spec.json").read_bytes()),
            "spec_semantic_sha256": digest(canonical(spec)),
            "spec_restored": spec == self.original, "business_restored": self.business_tree() == self.business,
            "uri_projections": {listener: uri_projection(uri, listener) for listener, uri in links.items()},
        }
        self.record(phase, row)
        self.checkpoint_rows[phase] = row
        self.phases.append(phase)
        require(row["account_material_sha256"] == self.frozen_accounts
                and row["token_sha256"] == self.frozen_token and row["material_hashes"] == self.frozen_material
                and row["reality"] == self.frozen_reality, "stable account/token/Reality materials changed")
        if restored:
            require(row["spec_restored"] and row["business_restored"], "formal off did not restore baseline")
        require(connected == bool(stream) and (bool(stream) or not published), "443 owner presence mismatch")
        if stream:
            owner = "nginx-stream" if stream.get("host_website", {}).get("network_mode") == "host" else "nginx"
            if owner == "nginx-stream":
                require(services[owner]["HostConfig"]["NetworkMode"] == "host", "443 host owner mismatch")
                selected = stream["listener_id"]
                binding = services["xray"]["HostConfig"]["PortBindings"][str(PORTS[selected]) + "/tcp"]
                require(binding == [{"HostIp": "127.0.0.1", "HostPort": "15443"}],
                        "loopback Reality backend exposure mismatch")
            else:
                require({"HostIp": "0.0.0.0", "HostPort": "443"} in
                        services[owner]["HostConfig"]["PortBindings"]["15443/tcp"], "443 bridge owner mismatch")
        if phase == "configured":
            self.baseline_links = links
        return row

    def encryption(self):
        self.checkpoint("configured", clients=("xray", "mihomo"), restored=True)
        self.edit("--vless-encryption", "entry-vision", "enable", label="formal-vision-enable")
        self.checkpoint("vision-enabled", clients=("xray", "mihomo"))
        self.edit("--vless-encryption", "entry-xhttp", "enable", label="formal-xhttp-enable")
        self.checkpoint("both-enabled", clients=("xray", "mihomo"))
        before = self.last_services
        self.cli("restart", label="formal-encryption-restart")
        self.checkpoint("both-restarted", clients=("xray", "mihomo"))
        self.restart_proof("encryption-restart", before, self.last_services)
        for listener in PORTS:
            self.edit("--vless-encryption", listener, "disable", label="formal-disable-" + listener)
        self.checkpoint("encryption-restored", clients=("xray", "mihomo"), restored=True)

    def restart_proof(self, label, before, after):
        row = {name: {"before_id": value["Id"], "after_id": after[name]["Id"],
                      "before_started": value["State"]["StartedAt"],
                      "after_started": after[name]["State"]["StartedAt"]} for name, value in before.items()}
        self.record(label, row)
        require(all(value["before_id"] == value["after_id"] and value["before_started"] != value["after_started"]
                    for value in row.values()), "formal restart did not restart existing services")

    def topologies(self):
        for listener in PORTS:
            for topology in ("managed", "host", "loopback"):
                phase = "stream-" + listener.removeprefix("entry-") + "-" + topology
                if topology == "managed":
                    arguments = ("--reality-stream", listener, "entry-website")
                elif topology == "host":
                    arguments = ("--reality-stream-host", listener, WEBSITE, ORIGIN, str(RELAY_PORT))
                else:
                    arguments = ("--reality-stream-loopback", listener, WEBSITE, "127.0.0.1", str(RELAY_PORT))
                self.edit(*arguments, label=phase + "-enable")
                self.checkpoint(phase, wrong_uuid=True)
                self.topology_site(phase, topology)
                if topology == "loopback":
                    before = self.last_services
                    self.cli("restart", label=phase + "-formal-restart")
                    self.checkpoint(phase + "-restarted", wrong_uuid=True)
                    self.restart_proof(phase + "-restart-proof", before, self.last_services)
                    self.topology_site(phase + "-restarted", topology)
                self.edit("--reality-stream", "off", label=phase + "-disable")
                self.checkpoint(phase + "-off", restored=True)

    def run(self):
        self.preflight()
        for port in (*PORTS.values(), WS_PORT, 443, 15443, RELAY_PORT):
            with socket.socket() as channel:
                channel.bind(("0.0.0.0", port))
        self.assets(NEW)
        self.mihomo_asset()
        self.install(NEW, "formal-install")
        self.configure()
        self.encryption()
        self.topologies()
        self.tls_probe("remote-direct-final", "final", WEBSITE, WEBSITE_IP, 443,
                       expected=self.remote_body, auxiliary=True)
        self.tls_probe("remote-relay-final", "final", WEBSITE, "127.0.0.1", RELAY_PORT,
                       expected=self.remote_body, auxiliary=True)
        self.record("relay-connections", copy.deepcopy(self.relay.connections))
        self.record("reality-summary", {
            "passed": True, "version": NEW["version"], "source": NEW["commit"],
            "phases": self.phases, "encryption_phases": list(ENCRYPTION_PHASES),
            "topology_phases": list(TOPOLOGY_PHASES), "checks": self.proxy_checks,
            "site_checks": self.site_checks, "proxy_count": len(self.proxy_checks),
            "site_count": len(self.site_checks), "checkpoint_count": len(self.phases),
            "scope": "native-arm64-ipv4-local-origin-reality-encryption",
            "clients": ["signed-release-xray", "pinned-mihomo-v1.19.28-explicit-hybrid"],
            "mihomo_original_uri_import_claimed": False,
            "prior_failed_full_matrix_run": "44135799536",
            "website_scope": "local-443-front-local-transparent-relay-public-A-https-backend",
            "public_inbound_tested": False, "reboot_tested": False, "ipv6_tested": False,
            "engine_installation_tested": False, "local_tls_termination_for_host_website": False,
            "production_private_key_transferred": False, "formal_runtime_modified": False,
            "mldsa65_claimed": False, "old_failures_reclassified": False,
        })
        require(len(self.phases) == 19 and len(self.proxy_checks) == 64 and len(self.site_checks) == 16,
                "acceptance matrix incomplete")

    def cleanup(self):
        if self.relay:
            self.record("relay-before-cleanup", copy.deepcopy(self.relay.connections))
        result = super().cleanup()
        if self.relay:
            with socket.socket() as channel:
                channel.settimeout(2)
                absent = channel.connect_ex(("127.0.0.1", RELAY_PORT)) != 0
            listening = self.command(["ss", "-lntHp", f"sport = :{RELAY_PORT}"],
                                     "relay-cleanup-listener").decode()
            self.record("relay-cleanup", {"passed": absent and not listening,
                                          "connect_refused": absent, "listener_ss": listening})
            require(absent and not listening, "transparent relay listener remains")
        return result


def selfcheck():
    acceptance = object.__new__(Acceptance)
    acceptance.known_secrets = ["private-material", 443, None, ""]
    require(acceptance.scrub("private-material:443") == "<redacted>:443", "mixed secret scrub failed")
    require(acceptance.scrub("failed vless://private-material@example.test?key=value\n" + "x" * 48)
            == "failed <private-uri>\n<opaque-material>", "client diagnostic scrub failed")
    helpers = runpy.run_path(str(Path(__file__).parents[2] / "docker/tests/vless-encryption-real.py"))
    query = {
        "encryption": "none", "security": "reality", "sni": TARGET, "fp": "chrome",
        "pbk": "public", "sid": "0123456789abcdef", "pqv": "verify", "type": "xhttp",
        "path": "/test", "host": TARGET, "mode": "packet-up", "extra": '{"noSSEHeader":true}',
    }
    uri = "vless://11111111-1111-4111-8111-111111111111@127.0.0.1:35467?" + urllib.parse.urlencode(query)
    config = xray_projection(uri, 2080, helpers["xray_client"])
    stream = config["outbounds"][0]["streamSettings"]
    require(stream["realitySettings"]["mldsa65Verify"] == "verify"
            and stream["xhttpSettings"] == {"path": "/test", "host": TARGET, "mode": "packet-up",
                                            "extra": {"noSSEHeader": True}}, "formal URI client projection mismatch")
    mihomo_query = {key: value for key, value in query.items() if key != "pqv"}
    parsed = urllib.parse.urlsplit(uri)
    mihomo_uri = urllib.parse.urlunsplit(parsed._replace(query=urllib.parse.urlencode(mihomo_query)))
    node = mihomo_projection(mihomo_uri, 2080)["proxies"][0]
    require(node["server"] == "127.0.0.1" and node["port"] == 35467
            and node["uuid"] == parsed.username and node["encryption"] == "none"
            and node["client-fingerprint"] == "chrome" and node["servername"] == TARGET
            and node["network"] == "xhttp" and node["ip-version"] == "ipv4"
            and node["reality-opts"] == {"public-key": "public", "short-id": "0123456789abcdef",
                                       "support-x25519mlkem768": True}
            and node["xhttp-opts"] == stream["xhttpSettings"], "Mihomo explicit hybrid projection mismatch")
    changed_node = mihomo_projection(mutate_uri(mihomo_uri, credential="wrong", encryption="other"), 2080)["proxies"][0]
    require(changed_node == {**node, "uuid": "wrong", "encryption": "other"},
            "Mihomo negative URI projection changed unrelated fields")
    try:
        mihomo_projection(uri, 2080)
    except AssertionError:
        pass
    else:
        raise AssertionError("unverified fixed Mihomo ML-DSA projection accepted")
    changed = mutate_uri(uri, credential="wrong", encryption="other")
    parsed, changed_query = uri_parts(changed)
    require(parsed.username == "wrong" and changed_query == {**query, "encryption": "other"},
            "negative URI changed unrelated parameters")
    projection = uri_projection(uri, "entry-xhttp")
    require(projection["query"]["pqv"] == digest(b"verify") and projection["query"]["pbk"] == digest(b"public")
            and projection["query"]["sid"] == digest(b"0123456789abcdef")
            and projection["query"]["encryption"] == digest(b"none"), "URI material hash projection mismatch")
    specimen = baseline_spec([], "core", "account", "account-uuid", "password", "token")
    website = specimen["core"]["protocols"][0]["websocket"]
    require(website == {"domain": DOMAIN, "path": "arm64-ws", "backend_port": 31297, "tls_port": 8443}
            and re.fullmatch(r"[A-Za-z0-9_-]{8,64}", website["path"]),
            "v3 website backend/TLS ports or path contract changed")
    valid = {"accepted": True, "curl_exit": 0, "expected_bytes": 2, "expected_sha256": digest(b"ok"),
             "nonce": "/nonce", "origin_tcp": [{"peer": "172.18.0.2"}],
             "origin_requests": [{"path": "/nonce", "peer": "172.18.0.2"}],
             "expected_origin_peers": ["172.18.0.2"]}
    require(result_valid(valid, b"ok"), "positive result selfcheck failed")
    negative = {**valid, "accepted": False, "curl_exit": 97, "origin_tcp": [], "origin_requests": []}
    require(result_valid(negative, b""), "runtime refusal selfcheck failed")
    rejected = 0
    for row, body in (
        ({**valid, "curl_exit": 28}, b"ok"),
        (valid, b"bad"),
        ({**valid, "origin_tcp": []}, b"ok"),
        ({**valid, "origin_requests": [{"path": "/wrong", "peer": "172.18.0.2"}]}, b"ok"),
        ({**negative, "curl_exit": 28}, b""),
        ({**negative, "curl_exit": "timeout"}, b""),
        ({**negative, "origin_tcp": [{"peer": "172.18.0.2"}]}, b""),
    ):
        require(not result_valid(row, body), "invalid runtime result accepted")
        rejected += 1
    require(len(ENCRYPTION_PHASES) == 5 and len(TOPOLOGY_PHASES) == 6, "phase matrix changed")
    acceptance.spec = lambda: {"reality_stream": {"host_website": {"network_mode": "host"}}}
    acceptance.command = lambda *args: b"xray nginx stream"
    failures = []
    acceptance.record = lambda label, row: failures.append((label, row))
    rows = [{
        "Config": {"Labels": {"com.docker.compose.service": name},
                   "User": "0:0" if name == "nginx-stream" else "10001:10001"},
        "State": {"Running": True, "Health": {"Status": "healthy"}},
        "HostConfig": {"ReadonlyRootfs": True, "Privileged": False, "CapDrop": ["ALL"],
                       "SecurityOpt": ["no-new-privileges:true"],
                       "NetworkMode": "host" if name == "nginx-stream" else "padm-docker",
                       "CapAdd": ["CAP_NET_BIND_SERVICE", "CAP_SETGID", "CAP_SETUID", "CAP_KILL"]
                       if name == "nginx-stream" else []},
        "NetworkSettings": {"Networks": {} if name == "nginx-stream" else {"padm-docker": {}}},
    } for name in ("xray", "nginx", "nginx-stream")]
    acceptance.json_command = lambda *args: rows
    acceptance.services("prefixed-capabilities")
    rows[-1]["HostConfig"]["CapAdd"] = ["NET_BIND_SERVICE", "SETGID", "SETUID", "KILL"]
    acceptance.services("unprefixed-capabilities")
    for section, key, value in (
        ("HostConfig", "CapAdd", ["CAP_NET_BIND_SERVICE", "CAP_SETGID", "CAP_SETUID", "CAP_KILL", "CAP_SYS_ADMIN"]),
        ("HostConfig", "CapAdd", ["CAP_NET_BIND_SERVICE", "CAP_SETGID", "CAP_SETUID"]),
        ("HostConfig", "NetworkMode", "padm-docker"),
        ("Config", "User", "10001:10001"),
    ):
        previous = rows[-1][section][key]
        rows[-1][section][key] = value
        try:
            acceptance.services("invalid-loopback-isolation")
        except AssertionError as error:
            require(str(error) == "loopback stream isolation mismatch", "unexpected isolation rejection")
            rejected += 1
        else:
            raise AssertionError("invalid loopback isolation accepted")
        rows[-1][section][key] = previous
    require(len(failures) == 4, "loopback isolation failure evidence missing")
    print(json.dumps({"reality_selfcheck": "pass", "negative_controls": rejected, "network_used": False}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selfcheck", action="store_true")
    parser.add_argument("--work", type=Path)
    args = parser.parse_args()
    if args.selfcheck:
        selfcheck()
        return 0
    require(args.work is not None, "--work required")
    os.umask(0o077)
    acceptance = Acceptance(args.work)
    passed, cleanup, kind, message, failure_phase = False, False, None, None, None

    def interrupted(signum, frame):
        raise InterruptedError("Reality acceptance interrupted")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        acceptance.run()
        passed = True
    except BaseException as error:
        kind, message = type(error).__name__, acceptance.scrub(str(error))
        failure_phase = acceptance.current
        with (acceptance.private / "error.log").open("w") as stream:
            traceback.print_exc(file=stream)
        acceptance.record("reality-failure", {"phase": failure_phase, "error_type": kind, "message": message})
        print("reality-failed phase=" + str(failure_phase) + " error=" + kind + ": " + message, flush=True)
    finally:
        try:
            cleanup = acceptance.cleanup()
        except BaseException as error:
            with (acceptance.private / "cleanup-error.log").open("w") as stream:
                traceback.print_exc(file=stream)
            print("cleanup-failed " + type(error).__name__, flush=True)
        if failure_phase:
            acceptance.current = failure_phase
        acceptance.finish(passed, cleanup, kind, message)
    print(f"reality_passed={passed} cleanup_passed={cleanup}", flush=True)
    return 0 if passed and cleanup else 1


if __name__ == "__main__":
    raise SystemExit(main())
