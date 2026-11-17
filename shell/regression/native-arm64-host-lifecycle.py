"""在一次性原生 ARM64 宿主验收正式安装、升级、回滚和卸载。"""

import argparse
import copy
import hashlib
import http.server
import ipaddress
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import signal
import socket
import stat
import subprocess
import tarfile
import threading
import time
import traceback
import uuid


IDENTITY = (
    "https://github.com/neil1123-vip/padm/"
    ".github/workflows/create_release.yml@refs/heads/main"
)
ISSUER = "https://token.actions.githubusercontent.com"
ROOT = Path("/etc/padm-docker")
CLI = "/usr/local/bin/padm-docker"
NAMES = (
    "release-manifest.json",
    "release-manifest.sigstore.json",
    "padm-docker-bundle.tar.gz",
)
OLD = {
    "version": "3.43.7",
    "commit": "2f17e6ac2159390f46265fa71e6131ac85da38f2",
    "assets": (
        ("9db18a00c85792d5b30745b77fab58abf707b9ce467a30ef8031e1249200b132", 3441),
        ("f17dbac6a236b45becda5902cb6517152c82443437558e5223af8cf72e11e189", 10255),
        ("4eb8cc7291d2ec96f54394cfe517bd93d1f48ff4655ccbaae1aca0f21de9b8f7", 3849441),
    ),
}
NEW = {
    "version": "3.43.8",
    "commit": "6e880813a92c6518678ec518d292d585c2cb775d",
    "assets": (
        ("e727c729cefa9b4a16aef67a456f9fee694593d0132e87c9884b95bd3c105963", 3439),
        ("4deb12e36da022a426719298b28907ded6088d9de3dcf215de7c7cb3e2caa953", 10159),
        ("abddb52299638ea62e1137dcde8889d22780aaa42e6ed51398cbb3ef985f00bd", 3926687),
    ),
}
DOMAIN = "arm64-lifecycle.padm.test"
ORIGIN = "93.184.216.34"
PUBLIC_PORT = 35466
BUSINESS_PATHS = (
    "config/xray",
    "config/nginx",
    "config/share-groups.json",
    "secrets/tls",
    "data/subscription",
    "data/acme",
    "secrets/renewal",
    "data/acme-webroot",
)


def digest(value):
    return hashlib.sha256(value).hexdigest()


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def expected_spec(original, release, manifest):
    result = copy.deepcopy(original)
    result["release"] = {
        "version": release["version"],
        "manifest_sha256": release["assets"][0][0],
        "signature_identity": IDENTITY,
    }
    result["images"] = {
        name: value["reference"] for name, value in manifest["images"].items()
    }
    return result


def preserved(before, after):
    require(set(before) == set(after), "traffic identity set changed")
    for account, row in before.items():
        require(row["limit_bytes"] == after[account]["limit_bytes"], "quota changed")
        require(
            all(after[account][key] >= row[key] for key in ("upload", "download")),
            "traffic total decreased",
        )


def parse_claim(output, rollback=False):
    prefix = "Docker 已回滚到" if rollback else "回滚快照"
    matches = re.findall(
        prefix + r": /etc/padm-docker/backups/(update\.[A-Za-z0-9]{6})",
        output.decode("utf-8", errors="replace"),
    )
    require(len(matches) == 1, "one current update snapshot must be claimed")
    return matches[0]


def safe_members(archive):
    result = []
    seen = set()
    for member in archive.getmembers():
        path = PurePosixPath(member.name)
        require(
            not path.is_absolute()
            and ".." not in path.parts
            and bool(path.parts)
            and (member.isfile() or member.isdir()),
            "unsafe release archive member",
        )
        name = str(path)
        require(name not in seen, "duplicate release archive member")
        seen.add(name)
        result.append(member)
    return result


class Acceptance:
    def __init__(self, work):
        require(work.is_absolute() and not work.exists(), "work must be new and absolute")
        self.work = work
        self.work.mkdir(mode=0o755, parents=True)
        self.work.chmod(0o755)
        self.private = work / "private"
        self.evidence = work / "evidence"
        self.private.mkdir(mode=0o700)
        self.evidence.mkdir(mode=0o755)
        self.evidence.chmod(0o755)
        (self.private / "tmp").mkdir(mode=0o700)
        self.env = os.environ.copy()
        for name in ("DOCKER_CONTEXT", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH"):
            self.env.pop(name, None)
        self.env.update(
            {
                "TMPDIR": str(self.private / "tmp"),
                "LANG": "C.UTF-8",
                "LC_ALL": "C.UTF-8",
                "DOCKER_HOST": "unix:///var/run/docker.sock",
            }
        )
        self.sequence = 0
        self.current = "initial"
        self.commands = []
        self.phases = []
        self.releases = {}
        self.platform_configs = {}
        self.source = {}
        self.original = None
        self.business = None
        self.last_ledger = None
        self.account = str(uuid.uuid4())
        self.core_uuid = str(uuid.uuid4())
        self.managed_uuid = str(uuid.uuid4())
        self.origin_added = False
        self.owns_root = False
        self.containers = set()
        self.initial_objects = None
        self.initial_images = None
        self.pulled_references = []
        self.record(
            "identity",
            {
                "script_sha256": digest(Path(__file__).read_bytes()),
                "github_sha": os.environ.get("GITHUB_SHA"),
                "github_run_id": os.environ.get("GITHUB_RUN_ID"),
                "github_run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
                "old": OLD,
                "new": NEW,
                "scope": "native-arm64-single-host-ipv4-local-origin",
                "reboot_tested": False,
                "public_inbound_tested": False,
                "docker_engine_installation_tested": False,
                "ipv6_tested": False,
            },
        )

    def record(self, name, value):
        path = self.evidence / (name + ".json")
        require(not path.exists(), "refusing to overwrite evidence")
        path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
        path.chmod(0o644)

    def command(self, arguments, label, *, timeout=300, allowed=(0,), content=None):
        self.current = label
        self.sequence += 1
        stem = f"{self.sequence:04d}-{label}"
        started = time.monotonic()
        try:
            process = subprocess.run(
                arguments,
                input=content,
                capture_output=True,
                timeout=timeout,
                env=self.env,
            )
            stdout, stderr, code = process.stdout, process.stderr, process.returncode
        except subprocess.TimeoutExpired as error:
            stdout, stderr, code = error.stdout or b"", error.stderr or b"", "timeout"
        (self.private / (stem + ".stdout")).write_bytes(stdout)
        (self.private / (stem + ".stderr")).write_bytes(stderr)
        row = {
            "sequence": self.sequence,
            "label": label,
            "executable": Path(arguments[0]).name,
            "exit": code,
            "started_at_unix": round(time.time() - (time.monotonic() - started), 3),
            "elapsed_seconds": round(time.monotonic() - started, 3),
            "stdout_sha256": digest(stdout),
            "stderr_sha256": digest(stderr),
            "stdout_bytes": len(stdout),
            "stderr_bytes": len(stderr),
        }
        self.commands.append(row)
        print(f'phase={label} exit={code} elapsed={row["elapsed_seconds"]}s', flush=True)
        require(code in allowed, "command failed; original logs retained privately")
        return stdout

    def json_command(self, arguments, label):
        return json.loads(self.command(arguments, label))

    def cli(self, *arguments, label, timeout=900):
        return self.command([CLI, *arguments], label, timeout=timeout)

    def objects(self, label):
        return {
            "containers": sorted(
                self.command(["docker", "ps", "-aq", "--no-trunc"], label + "-containers")
                .decode()
                .split()
            ),
            "networks": sorted(
                self.command(["docker", "network", "ls", "-q", "--no-trunc"], label + "-networks")
                .decode()
                .split()
            ),
            "volumes": sorted(
                self.command(["docker", "volume", "ls", "-q"], label + "-volumes")
                .decode()
                .split()
            ),
        }

    def image_ids(self, label):
        return set(
            self.command(["docker", "image", "ls", "-aq", "--no-trunc"], label)
            .decode()
            .split()
        )

    def preflight(self):
        require(os.geteuid() == 0, "root required")
        require(platform.system() == "Linux" and platform.machine() == "aarch64", "native arm64 required")
        require(Path("/proc/1/comm").read_text().strip() == "systemd", "host systemd required")
        for name in (
            "bash", "docker", "systemctl", "curl", "openssl", "ip", "ss",
            "tar", "sha256sum", "jq", "cosign",
        ):
            require(shutil.which(name), "missing required host tool")
        require(
            not ROOT.exists() and not ROOT.is_symlink()
            and not os.path.lexists(CLI) and not Path("/etc/padm").exists(),
            "preexisting padm deployment refused",
        )
        require(not list(Path("/etc/systemd/system").glob("padm-docker-*")), "preexisting padm units refused")
        for port in (PUBLIC_PORT, 31297, 8443):
            with socket.socket() as probe:
                probe.bind(("0.0.0.0", port))
        info = self.json_command(["docker", "info", "--format", "{{json .}}"], "host-docker")
        require(info["OSType"] == "linux" and info["Architecture"] in ("aarch64", "arm64"), "daemon architecture mismatch")
        require(not any("rootless" in item for item in info.get("SecurityOptions", [])), "rootless daemon refused")
        require(
            self.command(["systemctl", "is-active", "docker"], "docker-active").strip() == b"active"
            and self.command(["systemctl", "is-enabled", "docker"], "docker-enabled").strip() == b"enabled",
            "Docker systemd service required",
        )
        compose = self.command(["docker", "compose", "version", "--short"], "host-compose").decode().strip()
        require(re.match(r"v?2\.", compose), "Compose v2 required")
        buildx = self.command(["docker", "buildx", "version"], "host-buildx").decode().strip()
        addresses = self.json_command(["ip", "-j", "address", "show"], "host-addresses")
        require(
            all(row["local"] != ORIGIN for item in addresses for row in item["addr_info"]),
            "origin address already exists",
        )
        require(ipaddress.ip_address(ORIGIN).is_global, "origin fixture must avoid private target policy")
        self.initial_objects = self.objects("objects-before")
        self.initial_images = self.image_ids("images-before")
        self.record(
            "host",
            {
                "architecture": platform.machine(),
                "kernel": platform.release(),
                "os_release": Path("/etc/os-release").read_text(),
                "boot_id_sha256": digest(Path("/proc/sys/kernel/random/boot_id").read_bytes()),
                "pid1": "systemd",
                "systemd_state": self.command(
                    ["systemctl", "is-system-running"], "systemd-state", allowed=(0, 1)
                ).decode().strip(),
                "failed_units": self.command(
                    ["systemctl", "--failed", "--no-pager", "--plain", "--no-legend"],
                    "systemd-failed-units",
                ).decode().splitlines(),
                "docker_version": info["ServerVersion"],
                "docker_id_sha256": digest(info["ID"].encode()),
                "docker_driver": info["Driver"],
                "compose_version": compose,
                "buildx_version": buildx,
                "initial_objects": self.initial_objects,
                "initial_image_ids": sorted(self.initial_images),
                "disk_free_bytes": shutil.disk_usage(self.work).free,
            },
        )

    def assets(self, release):
        version = release["version"]
        directory = self.private / ("release-" + version)
        directory.mkdir()
        for name, (sha, size) in zip(NAMES, release["assets"]):
            target = directory / name
            url = f"https://github.com/neil1123-vip/padm/releases/download/v{version}/{name}"
            self.command(
                ["curl", "-L", "-fSs", "--proto", "=https", "--proto-redir", "=https",
                 "--retry", "3", "--connect-timeout", "20", "--max-time", "180",
                 "--output", str(target), url],
                "download-" + version + "-" + name,
                timeout=240,
            )
            require(target.stat().st_size == size and digest(target.read_bytes()) == sha, "formal asset mismatch")
        manifest = json.loads((directory / NAMES[0]).read_text())
        require(
            manifest["release"]["version"] == version
            and manifest["release"]["commit"] == release["commit"]
            and manifest["control"]["sha256"] == release["assets"][2][0],
            "signed release identity mismatch",
        )
        require(set(manifest["images"]) == {"xray", "sing-box", "nginx", "ops", "net"}, "five images required")
        self.command(
            ["cosign", "verify-blob", "--bundle", str(directory / NAMES[1]),
             "--certificate-identity", IDENTITY, "--certificate-oidc-issuer", ISSUER,
             str(directory / NAMES[0])],
            "cosign-" + version,
            timeout=180,
        )
        for original_name, evidence_name in (
            (NAMES[0], "release-manifest-" + version + ".json"),
            (NAMES[1], "release-signature-" + version + ".json"),
        ):
            target = self.evidence / evidence_name
            require(not target.exists(), "refusing to overwrite formal release evidence")
            target.write_bytes((directory / original_name).read_bytes())
            target.chmod(0o644)
        source = directory / "source"
        source.mkdir()
        with tarfile.open(directory / NAMES[2], "r:gz") as archive:
            members = safe_members(archive)
            archive.extractall(source, members=members)
        require((source / "install-docker.sh").is_file(), "formal installer missing")
        self.source[version] = source
        self.releases[version] = (release, manifest, directory)
        for name, image in manifest["images"].items():
            require(
                image["reference"].endswith("@" + image["index_digest"])
                and re.fullmatch(r"sha256:[0-9a-f]{64}", image["platforms"]["linux/arm64"]),
                "signed ARM64 image binding missing",
            )
            self.command(["docker", "pull", image["reference"]], "pull-" + version + "-" + name, timeout=900)
            self.pulled_references.append(image["reference"])
            repo = image["reference"].split("@")[0].rsplit(":", 1)[0]
            platform_raw = self.command(
                ["docker", "buildx", "imagetools", "inspect", "--raw",
                 repo + "@" + image["platforms"]["linux/arm64"]],
                "arm64-manifest-" + version + "-" + name,
            )
            require(
                "sha256:" + digest(platform_raw) == image["platforms"]["linux/arm64"],
                "ARM64 manifest bytes differ from signed digest",
            )
            raw_path = self.evidence / ("platform-manifest-" + version + "-" + name + ".json")
            require(not raw_path.exists(), "refusing to overwrite platform manifest")
            raw_path.write_bytes(platform_raw)
            raw_path.chmod(0o644)
            platform_manifest = json.loads(platform_raw)
            config_digest = platform_manifest["config"]["digest"]
            require(re.fullmatch(r"sha256:[0-9a-f]{64}", config_digest), "invalid platform image config")
            self.platform_configs[(version, name)] = config_digest
        self.record("assets-" + version, {"release": release, "cosign_identity": IDENTITY, "cosign_verified": True})

    def install(self, release, label):
        self.owns_root = True
        self.command(
            ["bash", str(self.source[release["version"]] / "install-docker.sh"),
             "install", "--source", str(self.source[release["version"]]),
             "--ref", release["commit"], "--no-menu"],
            label,
            timeout=1200,
            content=b"y\n",
        )
        require(Path(CLI).is_symlink() and ROOT.joinpath("mode").read_text().strip() == "docker", "formal install missing")

    def configure(self):
        _, manifest, directory = self.releases[OLD["version"]]
        key, cert = self.private / "tls.key", self.private / "tls.crt"
        self.command(
            ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
             "-subj", "/CN=" + DOMAIN, "-addext", "subjectAltName=DNS:" + DOMAIN,
             "-keyout", str(key), "-out", str(cert)],
            "create-test-ca",
        )
        self.cli(
            "tls", "install", "--domain", DOMAIN, "--cert", str(cert), "--key", str(key),
            "--ops-image", manifest["images"]["ops"]["reference"], label="formal-tls-install",
        )
        spec = {
            "schema_version": 3,
            "core": {
                "type": "xray", "secondary_type": None,
                "protocols": [{
                    "id": 21, "core": "xray", "listener_id": "entry-ws",
                    "server": DOMAIN, "public_port": PUBLIC_PORT,
                    "address_families": ["ipv4"], "name": "arm64-ws",
                    "uuid": self.core_uuid,
                    "websocket": {
                        "domain": DOMAIN, "path": "arm64-native",
                        "backend_port": 31297, "tls_port": 8443,
                    },
                }],
            },
            "accounts": [{
                "id": self.account, "name": "arm64-independent", "enabled": True,
                "uuid": self.managed_uuid, "password": uuid.uuid4().hex,
                "shadowsocks_password": None, "listeners": ["entry-ws"],
            }],
            "tls": {"domain": DOMAIN},
            "subscription": {"enabled": False, "token": uuid.uuid4().hex},
            "host_integrations": [],
        }
        spec = expected_spec(spec, OLD, manifest)
        spec_path = self.private / "input-spec.json"
        spec_path.write_text(json.dumps(spec))
        self.cli(
            "configure", "--spec", str(spec_path),
            "--manifest", str(directory / NAMES[0]), "--bundle", str(directory / NAMES[1]),
            "--control-bundle", str(directory / NAMES[2]), label="formal-configure",
        )
        self.cli("traffic", "collect", label="initial-collect")
        self.cli("traffic", "limit", self.account, "1", label="account-quota")
        self.original = json.loads((ROOT / "config/spec.json").read_text())
        self.business = self.business_tree()
        self.last_ledger = self.ledger()
        require(self.last_ledger[self.account]["limit_bytes"] == 1024 ** 3, "quota not installed")
        self.command(["ip", "address", "add", ORIGIN + "/32", "dev", "lo"], "origin-add")
        self.origin_added = True
        route = self.json_command(["ip", "-j", "route", "get", ORIGIN], "origin-route")
        require(len(route) == 1 and route[0].get("type") == "local" and route[0]["dev"] == "lo", "origin must be local")
        self.record("origin", {"address": ORIGIN, "local_fixture": True, "public_network_test": False})

    def business_tree(self):
        result = {}
        for name in BUSINESS_PATHS:
            start = ROOT / name
            if not start.exists():
                result[name] = {"absent": True}
                continue
            for path in [start, *sorted(start.rglob("*"))] if start.is_dir() else [start]:
                require(not path.is_symlink() and (path.is_file() or path.is_dir()), "unsafe business path")
                metadata = path.stat()
                result[str(path.relative_to(ROOT))] = {
                    "mode": stat.S_IMODE(metadata.st_mode),
                    "uid": metadata.st_uid,
                    "gid": metadata.st_gid,
                    **({"sha256": digest(path.read_bytes())} if path.is_file() else {}),
                }
        return result

    def ledger(self):
        result = json.loads((ROOT / "data/traffic/state.json").read_text())["accounts"]
        require(
            all(
                all(type(row.get(key)) is int and row[key] >= 0 for key in ("upload", "download", "limit_bytes"))
                for row in result.values()
            ),
            "invalid traffic ledger",
        )
        return result

    def public_ledger(self, ledger):
        return {
            digest(account.encode()): {key: row[key] for key in ("upload", "download", "limit_bytes")}
            for account, row in ledger.items()
        }

    def bundle_proof(self, release):
        bundle = ROOT / "bundle"
        require(bundle.is_symlink(), "installed bundle link required")
        require(bundle.resolve().is_relative_to(ROOT / ".bundles"), "bundle escaped managed root")
        require((bundle / ".padm-docker-bundle-ref").read_text().strip() == release["commit"], "installed source commit mismatch")
        lines = (bundle / ".padm-docker-bundle-manifest").read_text().splitlines()
        require(
            bundle.resolve().name == digest((bundle / ".padm-docker-bundle-manifest").read_bytes()),
            "installed bundle directory digest mismatch",
        )
        metadata = (bundle / ".padm-docker-bundle-manifest").stat()
        require(
            stat.S_IMODE(metadata.st_mode) == 0o640
            and metadata.st_uid == metadata.st_gid == 0,
            "installed manifest permissions changed",
        )
        files = {}
        source = self.source[release["version"]]
        for line in lines:
            require(re.fullmatch(r"[0-9a-f]{64}  .+", line), "invalid installed bundle manifest")
            sha, name = line[:64], line[66:]
            path = PurePosixPath(name)
            require(not path.is_absolute() and ".." not in path.parts and name not in files, "unsafe installed manifest")
            target = bundle / name
            require(target.is_file() and not target.is_symlink(), "installed payload file missing")
            require(digest(target.read_bytes()) == sha, "installed payload content mismatch")
            if name == ".padm-docker-bundle-ref":
                require(target.read_text().strip() == release["commit"], "payload source mismatch")
            else:
                require((source / name).is_file() and (source / name).read_bytes() == target.read_bytes(), "payload differs from formal archive")
            metadata = target.stat()
            require(
                stat.S_IMODE(metadata.st_mode) == (0o750 if name == "install-docker.sh" else 0o640)
                and metadata.st_uid == metadata.st_gid == 0,
                "installed payload permissions changed",
            )
            files[name] = sha
        actual = {str(path.relative_to(bundle)) for path in bundle.rglob("*") if path.is_file()}
        require(actual == set(files) | {".padm-docker-bundle-manifest"}, "installed payload set differs")
        source_files = {
            str(path.relative_to(source)) for path in source.rglob("*") if path.is_file()
        } - {"versions.lock", "docker-bake.hcl"}
        require(
            source_files == set(files) - {".padm-docker-bundle-ref"},
            "formal archive payload omitted from installed bundle",
        )
        for path in [bundle.resolve(), *(p for p in bundle.rglob("*") if p.is_dir())]:
            require(stat.S_IMODE(path.stat().st_mode) == 0o750 and path.stat().st_uid == path.stat().st_gid == 0, "bundle directory permissions changed")
        return {"file_count": len(files), "files": files, "manifest_sha256": digest((bundle / ".padm-docker-bundle-manifest").read_bytes())}

    def services(self, label):
        deadline = time.monotonic() + 120
        while True:
            ids = self.command(
                ["docker", "ps", "-aq", "--filter", "label=com.docker.compose.project=padm-docker"],
                label + "-service-list",
            ).decode().split()
            rows = self.json_command(["docker", "inspect", *ids], label + "-service-inspect") if ids else []
            services = {row["Config"]["Labels"]["com.docker.compose.service"]: row for row in rows}
            if set(services) == {"xray", "nginx"} and all(
                row["State"]["Running"] and row["State"].get("Health", {}).get("Status") == "healthy"
                for row in rows
            ):
                break
            require(time.monotonic() < deadline, "service health deadline exceeded")
            time.sleep(2)
        require(
            all(row["HostConfig"]["ReadonlyRootfs"] and not row["HostConfig"]["Privileged"] for row in rows),
            "service isolation mismatch",
        )
        return services

    def image_proof(self, manifest, services, label):
        proof = {}
        version = manifest["release"]["version"]
        for name, image in manifest["images"].items():
            rows = self.json_command(["docker", "image", "inspect", image["reference"]], label + "-image-" + name)
            require(len(rows) == 1 and rows[0]["Os"] == "linux" and rows[0]["Architecture"] == "arm64", "non-native image")
            row = rows[0]
            repo = image["reference"].split("@")[0].rsplit(":", 1)[0]
            require(
                repo + "@" + image["index_digest"] in row["RepoDigests"],
                "image index digest binding missing",
            )
            require(
                row["Id"] == self.platform_configs[(version, name)],
                "image config differs from signed ARM64 platform manifest",
            )
            if name in services:
                require(services[name]["Image"] == row["Id"] and services[name]["Config"]["Image"] == image["reference"], "service image binding mismatch")
            proof[name] = {
                "image_id": row["Id"], "reference": image["reference"],
                "signed_arm64_manifest": image["platforms"]["linux/arm64"],
                "repo_digests": row["RepoDigests"], "architecture": row["Architecture"],
            }
        return proof

    def traffic(self, credential, label, accepted, image, peers, *, server_name=DOMAIN):
        directory = self.private / ("client-" + label)
        directory.mkdir(mode=0o755)
        directory.chmod(0o755)
        ca = directory / "ca.crt"
        shutil.copyfile(self.private / "tls.crt", ca)
        ca.chmod(0o644)
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            socks_port = probe.getsockname()[1]
        config = {
            "inbounds": [{"type": "socks", "listen": "127.0.0.1", "listen_port": socks_port}],
            "outbounds": [{
                "type": "vless", "server": "127.0.0.1", "server_port": PUBLIC_PORT,
                "uuid": credential,
                "tls": {"enabled": True, "server_name": server_name, "certificate_path": "/input/ca.crt"},
                "transport": {"type": "ws", "path": "/arm64-nativews", "headers": {"Host": DOMAIN}},
            }],
        }
        config_path = directory / "config.json"
        config_path.write_text(json.dumps(config))
        config_path.chmod(0o644)
        payload, nonce = os.urandom(256 * 1024), uuid.uuid4().hex
        requests = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append({"path": self.path, "peer": self.client_address[0]})
                self.send_response(200)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, *args):
                pass

        origin = http.server.HTTPServer((ORIGIN, 0), Handler)
        origin_thread = threading.Thread(target=origin.serve_forever, daemon=True)
        origin_thread.start()
        client = None
        try:
            client = self.command(
                ["docker", "run", "-d", "--network", "host", "--read-only", "--cap-drop", "ALL",
                 "--security-opt", "no-new-privileges:true", "--user", "10001:10001",
                 "--mount", f"type=bind,src={directory},dst=/input,readonly",
                 "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=16m",
                 image, "run", "-c", "/input/config.json"],
                label + "-client-start",
            ).decode().strip()
            require(re.fullmatch(r"[0-9a-f]{64}", client), "invalid client container identity")
            self.containers.add(client)
            deadline = time.monotonic() + 30
            while True:
                state = self.json_command(
                    ["docker", "inspect", "--format", "{{json .State}}", client],
                    label + "-client-state",
                )
                require(state["Running"], "client exited before business probe")
                listening = self.command(
                    ["ss", "-lntHp", f"sport = :{socks_port}"],
                    label + "-client-listener",
                ).decode()
                if f'pid={state["Pid"]},' in listening:
                    break
                require(time.monotonic() < deadline, "client listener deadline exceeded")
                time.sleep(0.2)
            output = self.command(
                ["curl", "--fail", "--silent", "--show-error", "--max-time", "15", "--noproxy", "",
                 "--socks5-hostname", f"127.0.0.1:{socks_port}",
                 f"http://{ORIGIN}:{origin.server_port}/{nonce}"],
                label + "-business",
                timeout=25,
                allowed=tuple(range(126)),
            )
            code = self.commands[-1]["exit"]
            if accepted:
                require(
                    code == 0 and output == payload and len(requests) == 1
                    and requests[0]["path"] == "/" + nonce and requests[0]["peer"] in peers,
                    "strict TLS business response or origin identity mismatch",
                )
            else:
                require(code != 0 and not output and not requests, "wrong credential reached origin")
            self.record(
                label,
                {
                    "accepted": accepted, "curl_exit": code, "nonce": nonce,
                    "body_bytes": len(output), "body_sha256": digest(output),
                    "expected_bytes": len(payload), "expected_sha256": digest(payload),
                    "origin_requests": requests, "expected_origin_peers": sorted(peers),
                    "client_container": client, "client_image": image,
                    "client_config_sha256": digest(config_path.read_bytes()),
                    "strict_tls": True, "new_client": True, "local_origin": True,
                    "client_listener_pid_verified": True,
                    "tls_server_name": server_name,
                },
            )
        finally:
            try:
                if client:
                    self.command(["docker", "logs", client], label + "-client-logs", allowed=tuple(range(126)))
                    self.command(["docker", "rm", "-f", client], label + "-client-remove")
                    self.containers.discard(client)
            finally:
                origin.shutdown()
                origin.server_close()
                origin_thread.join(timeout=5)

    def phase(self, label, release):
        self.current = label
        _, manifest, _ = self.releases[release["version"]]
        expected = expected_spec(self.original, release, manifest)
        spec_path = ROOT / "config/spec.json"
        actual = json.loads(spec_path.read_text())
        require(actual == expected, "spec changed outside release and images")
        invariant = {key: value for key, value in actual.items() if key not in ("release", "images")}
        metadata = spec_path.stat()
        require(
            not spec_path.is_symlink() and stat.S_IMODE(metadata.st_mode) == 0o600
            and metadata.st_uid == metadata.st_gid == 0,
            "spec ownership or permissions changed",
        )
        tree = self.business_tree()
        require(tree == self.business, "business materials or permissions changed")
        current = self.ledger()
        preserved(self.last_ledger, current)
        services = self.services(label)
        images = self.image_proof(manifest, services, label)
        bundle = self.bundle_proof(release)
        timer = {
            key: self.command(["systemctl", key, "padm-docker-traffic.timer"], label + "-timer-" + key).decode().strip()
            for key in ("is-active", "is-enabled")
        }
        require(timer == {"is-active": "active", "is-enabled": "enabled"}, "traffic timer missing")
        peers = {
            row["IPAddress"] for row in services["xray"]["NetworkSettings"]["Networks"].values()
            if row.get("IPAddress")
        }
        require(peers, "xray bridge source missing")
        image = manifest["images"]["sing-box"]["reference"]
        self.traffic(self.core_uuid, label + "-core", True, image, peers)
        self.traffic(self.managed_uuid, label + "-account", True, image, peers)
        self.traffic(str(uuid.uuid4()), label + "-wrong", False, image, peers)
        if label == "installed-old":
            self.traffic(
                self.core_uuid, label + "-wrong-sni", False, image, peers,
                server_name="wrong-arm64.padm.test",
            )
        deadline = time.monotonic() + 15
        while True:
            self.cli("traffic", "collect", label=label + "-collect")
            after = self.ledger()
            preserved(current, after)
            if all(after[self.account][key] > current[self.account][key] for key in ("upload", "download")):
                break
            require(time.monotonic() < deadline, "independent account traffic did not increase")
            time.sleep(1)
        self.last_ledger = after
        self.record(
            label,
            {
                "passed": True, "version": release["version"], "source": release["commit"],
                "spec_sha256": digest((ROOT / "config/spec.json").read_bytes()),
                "spec_invariant_sha256": digest(json.dumps(
                    invariant, sort_keys=True, separators=(",", ":")
                ).encode()),
                "only_release_images_changed": True, "business_tree": tree,
                "spec_permissions": {"mode": 0o600, "uid": 0, "gid": 0},
                "business_tree_sha256": digest(json.dumps(tree, sort_keys=True).encode()),
                "bundle": bundle, "images": images,
                "services": {
                    name: {"id": row["Id"], "image_id": row["Image"], "started_at": row["State"]["StartedAt"]}
                    for name, row in services.items()
                },
                "timer": timer, "ledger_before": self.public_ledger(current),
                "ledger_after": self.public_ledger(after),
                "account_identity_sha256": digest(self.account.encode()),
                "independent_both_directions_increased": True,
                "identity_and_quota_preserved": True,
            },
        )
        self.phases.append(label)
        return services

    def stopped(self, label):
        require(
            not self.command(
                ["docker", "ps", "-aq", "--filter", "label=com.docker.compose.project=padm-docker"],
                label + "-containers",
            ).strip(),
            "managed containers remain after down",
        )
        active = self.command(
            ["systemctl", "is-active", "padm-docker-traffic.timer"],
            label + "-timer", allowed=(0, 3, 4),
        ).strip()
        require(active in (b"inactive", b"unknown"), "traffic timer remains active")
        require(
            not self.command(["ss", "-lntH", f"sport = :{PUBLIC_PORT}"], label + "-published-port").strip(),
            "published port still listening after down",
        )
        with socket.socket() as probe:
            probe.settimeout(2)
            require(probe.connect_ex(("127.0.0.1", PUBLIC_PORT)) != 0, "published port still accepts connections")
        require(self.business_tree() == self.business, "stop changed business materials")
        preserved(self.last_ledger, self.ledger())

    def update(self, label):
        _, _, directory = self.releases[NEW["version"]]
        output = self.cli(
            "update", "--manifest", str(directory / NAMES[0]), "--bundle", str(directory / NAMES[1]),
            "--control-bundle", str(directory / NAMES[2]), label=label,
        )
        return parse_claim(output)

    def run(self):
        self.preflight()
        self.assets(OLD)
        self.assets(NEW)
        self.install(OLD, "formal-install-old")
        self.configure()
        self.phase("installed-old", OLD)
        initial_backups = {path.name for path in (ROOT / "backups").iterdir()}
        first = self.update("formal-update")
        self.phase("updated-new", NEW)
        before_rollback = {path.name for path in (ROOT / "backups").iterdir()}
        output = self.cli("rollback", label="formal-rollback")
        require(parse_claim(output, rollback=True) == first, "rollback did not use current update snapshot")
        added = {path.name for path in (ROOT / "backups").iterdir()} - before_rollback
        require(len(added) == 1, "rollback safety snapshot missing")
        safety, = added
        require(re.fullmatch(r"rollback\.[A-Za-z0-9]{6}", safety), "unexpected rollback safety snapshot")
        saved = ROOT / "backups" / safety
        require(
            json.loads((saved / "config/spec.json").read_text())
            == expected_spec(self.original, NEW, self.releases[NEW["version"]][1]),
            "rollback safety snapshot did not preserve new spec",
        )
        target = (saved / "bundle.target").read_text().strip()
        require(re.fullmatch(r"\.bundles/[0-9a-f]{64}", target), "unsafe rollback bundle target")
        require((ROOT / target / ".padm-docker-bundle-ref").read_text().strip() == NEW["commit"], "rollback safety bundle changed")
        require(target == ".bundles/" + digest((ROOT / target / ".padm-docker-bundle-manifest").read_bytes()), "rollback safety manifest binding mismatch")
        self.phase("rolled-back-old", OLD)
        second = self.update("formal-update-again")
        require(first != second, "update reused earlier snapshot")
        self.phase("updated-again-new", NEW)
        require(
            {path.name for path in (ROOT / "backups").iterdir()} - initial_backups == {first, safety, second},
            "unexpected upgrade backup set",
        )
        self.record("snapshots", {"first_update": first, "rollback_safety": safety, "second_update": second, "bundle_target": target})
        before_restart = self.services("before-restart")
        self.cli("restart", label="formal-restart")
        after_restart = self.phase("restarted-new", NEW)
        require(
            all(before_restart[name]["Id"] == after_restart[name]["Id"]
                and before_restart[name]["State"]["StartedAt"] != after_restart[name]["State"]["StartedAt"]
                for name in before_restart),
            "restart did not restart existing service containers",
        )
        self.cli("down", label="formal-down")
        self.stopped("down")
        self.cli("up", label="formal-up")
        after_up = self.phase("up-new", NEW)
        require(all(after_up[name]["Id"] != after_restart[name]["Id"] for name in after_up), "up reused removed containers")
        self.record("lifecycle-transitions", {
            "restart_same_container_ids": True, "restart_started_at_changed": True,
            "down_published_port_closed": True, "up_new_container_ids": True,
            "reboot_tested": False,
        })
        before_uninstall = self.ledger()
        before_images = self.image_ids("before-preserve-image-ids")
        self.cli("uninstall", label="formal-uninstall-preserve")
        require(not os.path.lexists(CLI) and ROOT.is_dir(), "default uninstall preservation failed")
        self.stopped("uninstalled")
        preserved(before_uninstall, self.ledger())
        require(self.image_ids("after-preserve-image-ids") == before_images, "default uninstall removed images")
        self.image_proof(self.releases[NEW["version"]][1], {}, "uninstalled")
        self.record("uninstall-preserve", {"cli_removed": True, "business_unchanged": True, "state_retained": True, "ledger": self.public_ledger(self.ledger())})
        self.install(NEW, "formal-reinstall-new")
        self.cli("up", label="formal-reinstalled-up")
        self.phase("reinstalled-new", NEW)
        before_images = self.image_ids("before-purge-image-ids")
        self.cli("uninstall", "--purge", "--confirm", "PADM-DOCKER-PURGE", label="formal-purge")
        require(not ROOT.exists() and not ROOT.is_symlink() and not os.path.lexists(CLI), "purge left managed paths")
        require(self.image_ids("after-purge-image-ids") == before_images, "purge without remove-images removed images")
        self.image_proof(self.releases[NEW["version"]][1], {}, "purged")
        self.record("purge", {"managed_root_absent": True, "cli_absent": True, "images_preserved": True})

    def cleanup(self):
        failures = []

        def attempt(label, function):
            try:
                function()
            except BaseException:
                failures.append(label)
                with (self.private / "cleanup-errors.log").open("a") as stream:
                    traceback.print_exc(file=stream)

        for client in tuple(self.containers):
            attempt("client-remove", lambda client=client: self.command(["docker", "rm", "-f", client], "cleanup-client"))
        if self.owns_root and ROOT.exists():
            def purge():
                require(not ROOT.is_symlink() and (ROOT / "mode").read_text().strip() == "docker", "cleanup root ownership marker missing")
                installer = self.source[NEW["version"]] / "install-docker.sh"
                self.command(
                    ["bash", str(installer), "uninstall", "--purge", "--confirm", "PADM-DOCKER-PURGE"],
                    "cleanup-formal-purge", timeout=900,
                )
            attempt("formal-purge", purge)
        if self.origin_added:
            attempt("origin-remove", lambda: self.command(["ip", "address", "del", ORIGIN + "/32", "dev", "lo"], "origin-remove"))
        for index, reference in enumerate(dict.fromkeys(self.pulled_references)):
            def remove_image(reference=reference, index=index):
                rows = self.json_command(["docker", "image", "inspect", reference], f"cleanup-inspect-image-{index}")
                if rows[0]["Id"] not in self.initial_images:
                    self.command(["docker", "image", "rm", reference], f"cleanup-image-{index}")
            attempt("image-remove", remove_image)
        if self.initial_objects is not None:
            def verify():
                require(self.objects("objects-after") == self.initial_objects, "Docker objects differ after cleanup")
                require(self.image_ids("images-after") == self.initial_images, "new Docker images remain")
                require(not ROOT.exists() and not os.path.lexists(CLI), "managed install paths remain")
                require(not list(Path("/etc/systemd/system").glob("padm-docker-*")), "padm systemd unit files remain")
                addresses = self.json_command(["ip", "-j", "address", "show"], "cleanup-addresses")
                require(all(row["local"] != ORIGIN for item in addresses for row in item["addr_info"]), "origin address remains")
                require(self.command(["systemctl", "is-active", "docker"], "cleanup-docker-active").strip() == b"active", "Docker daemon not active")
            attempt("final-state", verify)
        self.record("cleanup", {"passed": not failures, "failed_steps": failures, "global_prune_used": False})
        return not failures

    def finish(self, passed, cleanup_passed, error_type, error_message):
        self.record("commands", self.commands)
        self.record(
            "result",
            {
                "passed": passed and cleanup_passed,
                "lifecycle_passed": passed,
                "cleanup_passed": cleanup_passed,
                "completed_phases": self.phases,
                "failure_phase": None if passed else self.current,
                "error_type": error_type,
                "error_message": error_message,
                "private_logs_uploaded": False,
                "reboot_tested": False,
                "public_inbound_tested": False,
                "docker_engine_installation_tested": False,
            },
        )
        index = {
            path.name: {"sha256": digest(path.read_bytes()), "bytes": path.stat().st_size}
            for path in sorted(self.evidence.iterdir())
        }
        self.record("sha256-index", index)


def selfcheck():
    original = {"release": {"version": "old"}, "images": {}, "accounts": [{"id": "private"}], "core": {"id": 21}}
    saved = copy.deepcopy(original)
    updated = expected_spec(original, NEW, {"images": {"xray": {"reference": "fixed"}}})
    require(original == saved and updated["accounts"] == original["accounts"], "spec copy failed")
    require(updated["images"] == {"xray": "fixed"} and updated["release"]["version"] == NEW["version"], "spec projection failed")
    baseline = {"a": {"upload": 3, "download": 4, "limit_bytes": 1024}}
    preserved(baseline, {"a": {"upload": 5, "download": 7, "limit_bytes": 1024}})
    rejected = 0
    for invalid in (
        {}, {"a": {"upload": 2, "download": 4, "limit_bytes": 1024}},
        {"a": {"upload": 3, "download": 4, "limit_bytes": 2048}},
    ):
        try:
            preserved(baseline, invalid)
        except AssertionError:
            rejected += 1
    require(rejected == 3, "ledger negative controls failed")
    require(parse_claim("回滚快照: /etc/padm-docker/backups/update.A1b2C3".encode()) == "update.A1b2C3", "snapshot parser failed")
    require(parse_claim("Docker 已回滚到: /etc/padm-docker/backups/update.A1b2C3".encode(), True) == "update.A1b2C3", "rollback parser failed")
    try:
        parse_claim(b"unrelated update.A1b2C3")
    except AssertionError:
        rejected += 1
    require(rejected == 4, "snapshot negative control failed")
    for unsafe in ("../outside", "/absolute", "safe/../../outside"):
        member = tarfile.TarInfo(unsafe)

        class Archive:
            def getmembers(self):
                return [member]

        try:
            safe_members(Archive())
        except AssertionError:
            rejected += 1
    require(rejected == 7, "archive negative controls failed")
    require(len({OLD["commit"], NEW["commit"]}) == 2, "release commits must differ")
    print(json.dumps({"selfcheck": "pass", "negative_controls": rejected, "network_used": False}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path)
    parser.add_argument("--selfcheck", action="store_true")
    arguments = parser.parse_args()
    if arguments.selfcheck:
        require(arguments.work is None, "selfcheck does not accept work")
        selfcheck()
        return 0
    require(arguments.work is not None, "--work required")
    os.umask(0o077)
    acceptance = Acceptance(arguments.work)
    passed, cleanup_passed, error_type, error_message = False, False, None, None
    failure_phase = None

    def interrupted(signum, frame):
        raise InterruptedError("lifecycle interrupted")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        acceptance.run()
        passed = True
    except BaseException as error:
        error_type = type(error).__name__
        if isinstance(error, AssertionError):
            error_message = str(error)
        failure_phase = acceptance.current
        with (acceptance.private / "failure.log").open("w") as stream:
            traceback.print_exc(file=stream)
        print("lifecycle failed; original details retained privately", flush=True)
    finally:
        cleanup_passed = acceptance.cleanup()
        if failure_phase:
            acceptance.current = failure_phase
        acceptance.finish(passed, cleanup_passed, error_type, error_message)
    print(f"lifecycle_passed={passed} cleanup_passed={cleanup_passed}", flush=True)
    return 0 if passed and cleanup_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
