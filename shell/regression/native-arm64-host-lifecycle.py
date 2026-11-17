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
    "version": "3.43.8",
    "commit": "6e880813a92c6518678ec518d292d585c2cb775d",
    "assets": (
        ("e727c729cefa9b4a16aef67a456f9fee694593d0132e87c9884b95bd3c105963", 3439),
        ("4deb12e36da022a426719298b28907ded6088d9de3dcf215de7c7cb3e2caa953", 10159),
        ("abddb52299638ea62e1137dcde8889d22780aaa42e6ed51398cbb3ef985f00bd", 3926687),
    ),
}
NEW = {
    "version": "3.44.0",
    "commit": "da7905877b1ee59abbf632ad866963a02da94bf7",
    "assets": (
        ("a7062401256e5cb454a66927ddcfd8a14c07d11a4250d07395d8be6e95513e25", 3439),
        ("9844fe61a6b4c04c9a23e202740bdeb603564720d9af643f81cf668a248db917", 10307),
        ("6f168923336d5f09a9e5a2984cc4b5d2b25e3e5c74e0439735e60a5161b5d028", 3933824),
    ),
}
DOMAIN = "arm64-lifecycle.padm.test"
ORIGIN = "93.184.216.34"
PUBLIC_PORT = 35466
BUSINESS_PATHS = (
    "config/sing-box",
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


def trojan_client(password, socks_port, server_name=DOMAIN):
    return {
        "inbounds": [{"type": "socks", "listen": "127.0.0.1", "listen_port": socks_port}],
        "outbounds": [{
            "type": "trojan", "server": "127.0.0.1", "server_port": PUBLIC_PORT,
            "password": password,
            "tls": {
                "enabled": True, "server_name": server_name, "alpn": ["http/1.1"],
                "certificate_path": "/input/ca.crt",
            },
        }],
    }


def trojan_runtime(config, core_credential, account, managed_password):
    inbounds = config.get("inbounds", [])
    require(len(inbounds) == 1, "pure Trojan must have exactly one inbound")
    inbound = inbounds[0]
    require(
        inbound.get("type") == "trojan" and inbound.get("tag") == "entry-trojan"
        and inbound.get("listen") == "::" and inbound.get("listen_port") == PUBLIC_PORT
        and "transport" not in inbound,
        "pure sing-box Trojan listener mismatch",
    )
    require(
        inbound.get("tls") == {
            "enabled": True, "server_name": DOMAIN, "alpn": ["http/1.1"],
            "certificate_path": f"/etc/padm/secrets/tls/{DOMAIN}.crt",
            "key_path": f"/etc/padm/secrets/tls/{DOMAIN}.key",
        },
        "Trojan direct TLS configuration mismatch",
    )
    require(
        inbound.get("users") == [
            {"name": core_credential, "password": core_credential},
            {"name": account, "password": managed_password},
        ],
        "Trojan password or stable statistics identity mismatch",
    )
    api = config.get("experimental", {}).get("v2ray_api", {})
    stats = api.get("stats", {})
    require(
        api.get("listen") == "127.0.0.1:10087" and stats.get("enabled") is True
        and len(stats.get("users", [])) == 2
        and set(stats["users"]) == {core_credential, account},
        "sing-box traffic API account binding mismatch",
    )
    return {
        "core": "sing-box", "protocol_id": 28, "listener_id": "entry-trojan",
        "direct_tls": True, "authentication": "password",
        "tls_server_name": DOMAIN, "tls_alpn": ["http/1.1"],
        "statistics_api": "127.0.0.1:10087",
        "statistics_identity_sha256": sorted(digest(value.encode()) for value in stats["users"]),
    }


def image_id_kind(image_id, config_digest, index_digest, containerd_image_store):
    if image_id == config_digest:
        return "config"
    require(
        containerd_image_store and image_id == index_digest,
        "image differs from signed ARM64 config and permitted containerd index",
    )
    return "containerd-index"


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


def replaceable_engine(objects, networks):
    require(not objects["containers"] and not objects["volumes"], "preexisting workloads refuse Engine replacement")
    require(set(networks) == {"bridge", "host", "none"}, "custom networks refuse Engine replacement")


def docker_repository_input(path, raw):
    text = raw.decode()
    active = [line.strip() for line in text.splitlines()
              if line.strip() and not line.lstrip().startswith("#")]
    require(
        path.suffix == ".list" and active and all(re.fullmatch(
            r"deb \[[^\]\n]+\] https://download\.docker\.com/linux/ubuntu noble stable",
            line,
        ) for line in active),
        "refuse mixed or unknown Docker APT repository input",
    )
    return {"path": str(path), "sha256": digest(raw), "bytes": len(raw), "content": text}


def engine_selfcheck():
    empty = {"containers": [], "volumes": []}
    defaults = ["bridge", "host", "none"]
    replaceable_engine(empty, defaults)
    rejected = 0
    for objects, networks in (
        ({"containers": ["existing"], "volumes": []}, defaults),
        ({"containers": [], "volumes": ["existing"]}, defaults),
        (empty, [*defaults, "existing"]),
    ):
        try:
            replaceable_engine(objects, networks)
        except AssertionError:
            rejected += 1
    repository = b"deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable\n"
    require(docker_repository_input(Path("/tmp/docker.list"), repository)["sha256"] == digest(repository), "APT input proof mismatch")
    for name, raw in (
        ("/tmp/docker.sources", repository),
        ("/tmp/docker.list", repository + b"deb https://unrelated.example noble main\n"),
        ("/tmp/docker.list", repository.replace(b"noble", b"unknown")),
    ):
        try:
            docker_repository_input(Path(name), raw)
        except AssertionError:
            rejected += 1
    require(rejected == 6, "Engine replacement negative controls failed")
    print(json.dumps({"engine_selfcheck": "pass", "negative_controls": rejected, "network_used": False}))


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
        self.core_credential = str(uuid.uuid4())
        self.managed_password = uuid.uuid4().hex
        self.origin_added = False
        self.owns_root = False
        self.containers = set()
        self.initial_objects = None
        self.initial_images = None
        self.pulled_references = []
        self.engine_installation_attempted = False
        self.engine_installation_verified = False
        self.engine_replacement_started = False
        self.containerd_image_store = False
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
                "docker_engine_installation_requested": True,
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
            "tar", "sha256sum", "jq", "cosign", "apt-get", "apt-cache", "dpkg-query", "nsenter",
        ):
            require(shutil.which(name), "missing required host tool")
        require(
            not ROOT.exists() and not ROOT.is_symlink()
            and not os.path.lexists(CLI) and not Path("/etc/padm").exists(),
            "preexisting padm deployment refused",
        )
        require(not list(Path("/etc/systemd/system").glob("padm-docker-*")), "preexisting padm units refused")
        tools = self.private / "tools"
        tools.mkdir(mode=0o700)
        require(Path("/usr/bin/curl").is_file(), "official host curl missing")
        curl_version = self.command(["/usr/bin/curl", "--version"], "official-curl-version").decode()
        require(
            any(line.startswith("Features:") and "HTTP2" in line.split()
                for line in curl_version.splitlines()),
            "sing-box traffic collection requires host curl HTTP2",
        )
        (tools / "curl").symlink_to("/usr/bin/curl")
        self.env["PATH"] = str(tools) + os.pathsep + self.env["PATH"]
        for port in (PUBLIC_PORT,):
            with socket.socket() as probe:
                probe.bind(("0.0.0.0", port))
        self.engine_bootstrap()
        info = self.json_command(["docker", "info", "--format", "{{json .}}"], "host-docker")
        require(info["OSType"] == "linux" and info["Architecture"] in ("aarch64", "arm64"), "daemon architecture mismatch")
        require(not any("rootless" in item for item in info.get("SecurityOptions", [])), "rootless daemon refused")
        require(
            self.command(["systemctl", "is-active", "docker"], "docker-active").strip() == b"active"
            and self.command(["systemctl", "is-enabled", "docker"], "docker-enabled").strip() == b"enabled",
            "Docker systemd service required",
        )
        self.containerd_image_store = (
            info["Driver"] == "overlayfs"
            and ["driver-type", "io.containerd.snapshotter.v1"] in info.get("DriverStatus", [])
        )
        compose = self.command(["docker", "compose", "version", "--short"], "host-compose").decode().strip()
        compose_major = re.match(r"v?([0-9]+)\.", compose)
        require(compose_major and int(compose_major[1]) >= 2, "Compose CLI v2 or newer required")
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
                "docker_driver_status": info.get("DriverStatus", []),
                "compose_version": compose,
                "buildx_version": buildx,
                "initial_objects": self.initial_objects,
                "initial_image_ids": sorted(self.initial_images),
                "curl_version": curl_version, "selected_curl": "/usr/bin/curl",
                "disk_free_bytes": shutil.disk_usage(self.work).free,
            },
        )

    def release_files(self, release):
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
        self.record("assets-" + version, {"release": release, "cosign_identity": IDENTITY, "cosign_verified": True})

    def engine_bootstrap(self):
        require(
            os.environ.get("GITHUB_ACTIONS") == "true"
            and os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted",
            "Engine replacement is restricted to disposable GitHub-hosted runners",
        )
        os_release = Path("/etc/os-release").read_text()
        require('ID=ubuntu\n' in os_release and platform.machine() == "aarch64", "fixed Ubuntu ARM64 bootstrap required")
        before = self.objects("engine-original-objects")
        networks = self.command(
            ["docker", "network", "ls", "--format", "{{.Name}}"], "engine-original-networks"
        ).decode().split()
        replaceable_engine(before, networks)
        packages = (
            "docker-ce", "docker-ce-cli", "containerd.io",
            "docker-buildx-plugin", "docker-compose-plugin",
        )
        package_format = "${Package}\t${Status}\t${Version}\n"
        packages_before = self.command(
            ["dpkg-query", "-W", "-f", package_format, *packages],
            "engine-packages-before", allowed=(0, 1),
        ).decode()
        installed_before = {
            line.split("\t")[0] for line in packages_before.splitlines()
            if "\tinstall ok installed\t" in line
        }
        require(
            {"docker-ce", "docker-ce-cli", "containerd.io"} <= installed_before <= set(packages),
            "fixed runner core Docker package set required",
        )
        plugins = self.json_command(
            ["docker", "info", "--format", "{{json .ClientInfo.Plugins}}"], "engine-original-plugins",
        )
        plugin_before = []
        for name in ("buildx", "compose"):
            selected = [plugin for plugin in plugins if plugin["Name"] == name]
            require(len(selected) == 1, "one selected runner Docker plugin required")
            path = Path(selected[0]["Path"])
            require(
                path.name == "docker-" + name and path.is_file() and not path.is_symlink()
                and path.parent in {
                    Path("/usr/libexec/docker/cli-plugins"), Path("/usr/lib/docker/cli-plugins"),
                    Path("/usr/local/libexec/docker/cli-plugins"), Path("/usr/local/lib/docker/cli-plugins"),
                },
                "unknown or symlinked runner Docker plugin refuses replacement",
            )
            plugin_before.append({"name": name, "path": str(path), "sha256": digest(path.read_bytes())})
        self.release_files(NEW)
        repository_inputs = []
        apt_main = Path("/etc/apt/sources.list")
        require(not apt_main.exists() or b"download.docker.com" not in apt_main.read_bytes(), "mixed main APT source refuses replacement")
        for pattern in ("*.list", "*.sources"):
            for path in sorted(Path("/etc/apt/sources.list.d").glob(pattern)):
                raw = path.read_bytes()
                if b"download.docker.com" not in raw:
                    continue
                require(not path.is_symlink(), "symlinked APT source refuses replacement")
                repository_inputs.append(docker_repository_input(path, raw))
        self.record("engine-before", {
            "packages": packages_before, "objects": before, "networks": sorted(networks),
            "selected_plugins": plugin_before,
            "docker_repositories": repository_inputs, "initial_condition": "preinstalled-packages-removed",
        })
        self.engine_replacement_started = True
        self.command(
            ["systemctl", "stop", "docker.socket", "docker.service", "containerd.service"],
            "engine-stop",
        )
        self.command(
            ["apt-get", "remove", "-y", *sorted(installed_before)],
            "engine-remove-packages", timeout=900,
        )
        for plugin in plugin_before:
            path = Path(plugin["path"])
            if path.exists():
                require(
                    path.is_file() and not path.is_symlink() and digest(path.read_bytes()) == plugin["sha256"],
                    "runner Docker plugin changed before removal",
                )
                path.unlink()
        for repository in repository_inputs:
            path = Path(repository["path"])
            require(digest(path.read_bytes()) == repository["sha256"], "repository changed before removal")
            path.unlink()
        require(shutil.which("docker") is None, "Docker executable still available after package removal")
        self.command(
            ["bash", "-c", "if command -v docker; then exit 1; fi; printf 'docker-executable-absent\\n'"],
            "engine-executable-absence",
        )
        inactive = self.command(
            ["systemctl", "is-active", "docker.service"], "engine-absent-service", allowed=(3, 4)
        ).decode().strip()
        require(inactive in ("inactive", "unknown"), "old Docker daemon remains active")
        self.record("engine-absent", {
            "docker_executable_absent": True, "docker_service": inactive,
            "removed_packages": sorted(installed_before), "removed_plugin_paths": [
                row["path"] for row in plugin_before
            ], "removed_repository_paths": [
                row["path"] for row in repository_inputs
            ],
        })
        self.engine_installation_attempted = True
        self.install(NEW, "formal-engine-auto-install")
        packages_after = self.command(
            ["dpkg-query", "-W", "-f", package_format, *packages], "engine-packages-after"
        ).decode()
        require(
            {line.split("\t")[0] for line in packages_after.splitlines()
             if "\tinstall ok installed\t" in line} == set(packages),
            "formal entry did not install all official Docker packages",
        )
        versions = {
            line.split("\t")[0]: line.split("\t")[2] for line in packages_after.splitlines()
            if "\tinstall ok installed\t" in line
        }
        repository_versions = self.command(
            ["apt-cache", "madison", *packages], "engine-package-origins",
        ).decode()
        origins = {}
        for package, version in versions.items():
            candidates = [line.split("|") for line in repository_versions.splitlines()]
            matching = [
                fields[2].strip() for fields in candidates
                if len(fields) == 3 and fields[0].strip() == package and fields[1].strip() == version
                and fields[2].strip() == "https://download.docker.com/linux/ubuntu noble/stable arm64 Packages"
            ]
            require(matching, "installed Docker package version not present in official ARM64 APT source")
            origins[package] = {"version": version, "source": matching[0]}
        selected_plugins = self.json_command(
            ["docker", "info", "--format", "{{json .ClientInfo.Plugins}}"], "engine-installed-plugins",
        )
        plugin_after = []
        for name, package in (("buildx", "docker-buildx-plugin"), ("compose", "docker-compose-plugin")):
            selected = [plugin for plugin in selected_plugins if plugin["Name"] == name]
            require(len(selected) == 1, "installed Docker plugin selection ambiguous")
            path = Path(selected[0]["Path"])
            require(path.is_file() and not path.is_symlink(), "installed Docker plugin is not a regular file")
            owner = self.command(
                ["dpkg-query", "-S", str(path)], "engine-plugin-owner-" + name,
            ).decode().strip()
            require(
                len(owner.splitlines()) == 1 and ": " in owner
                and owner.split(": ", 1)[0].split(":")[0] == package
                and owner.split(": ", 1)[1] == str(path),
                "selected Docker plugin is not owned by its official installed package",
            )
            plugin_after.append({
                "name": name, "path": str(path), "sha256": digest(path.read_bytes()), "package": package,
            })
        engine = self.json_command(["docker", "info", "--format", "{{json .}}"], "engine-installed-info")
        require(engine["Architecture"] in ("arm64", "aarch64") and engine["OSType"] == "linux", "installed Engine is not native ARM64")
        require(self.command(["systemctl", "is-active", "docker.service"], "engine-installed-active").strip() == b"active", "installed Engine inactive")
        require(self.command(["systemctl", "is-enabled", "docker.service"], "engine-installed-enabled").strip() == b"enabled", "installed Engine not enabled")
        compose = self.command(["docker", "compose", "version", "--short"], "engine-installed-compose").decode().strip()
        apt_source = Path("/etc/apt/sources.list.d/padm-docker.list")
        require(apt_source.is_file() and not apt_source.is_symlink(), "formal Docker APT source missing")
        require(
            "https://download.docker.com/linux/ubuntu noble stable" in apt_source.read_text()
            and "signed-by=/etc/apt/keyrings/padm-docker.gpg" in apt_source.read_text(),
            "formal signed Docker APT source mismatch",
        )
        self.cli(
            "uninstall", "--purge", "--confirm", "PADM-DOCKER-PURGE",
            label="engine-bootstrap-purge",
        )
        require(not ROOT.exists() and not os.path.lexists(CLI), "bootstrap PADM root not purged")
        self.engine_installation_verified = True
        self.record("engine-installation", {
            "passed": True, "release": NEW["version"], "source": NEW["commit"],
            "installer_sha256": digest((self.source[NEW["version"]] / "install-docker.sh").read_bytes()),
            "packages": packages_after, "architecture": engine["Architecture"],
            "package_origins": origins, "selected_plugins": plugin_after,
            "docker_version": engine["ServerVersion"], "docker_driver": engine["Driver"],
            "compose_version": compose, "apt_source": apt_source.read_text(),
            "service_active_enabled": True, "bootstrap_padm_root_purged": True,
            "bare_os_test": False, "reboot_tested": False,
        })

    def assets(self, release):
        version = release["version"]
        if version not in self.releases:
            self.release_files(release)
        _, manifest, _ = self.releases[version]
        for name, image in manifest["images"].items():
            require(
                image["reference"].endswith("@" + image["index_digest"])
                and re.fullmatch(r"sha256:[0-9a-f]{64}", image["platforms"]["linux/arm64"]),
                "signed ARM64 image binding missing",
            )
            self.command(["docker", "pull", image["reference"]], "pull-" + version + "-" + name, timeout=900)
            self.pulled_references.append(image["reference"])
            repo = image["reference"].split("@")[0].rsplit(":", 1)[0]
            index_raw = self.command(
                ["docker", "buildx", "imagetools", "inspect", "--raw", image["reference"]],
                "index-manifest-" + version + "-" + name,
            )
            require("sha256:" + digest(index_raw) == image["index_digest"], "image index bytes differ from signed digest")
            descriptors = [
                item for item in json.loads(index_raw)["manifests"]
                if item.get("platform", {}).get("os") == "linux"
                and item.get("platform", {}).get("architecture") == "arm64"
            ]
            require(
                len(descriptors) == 1 and descriptors[0]["digest"] == image["platforms"]["linux/arm64"],
                "signed ARM64 descriptor differs from actual image index",
            )
            index_path = self.evidence / ("platform-index-" + version + "-" + name + ".json")
            require(not index_path.exists(), "refusing to overwrite image index")
            index_path.write_bytes(index_raw)
            index_path.chmod(0o644)
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

    def install(self, release, label):
        self.owns_root = True
        self.command(
            ["bash", str(self.source[release["version"]] / "install-docker.sh"),
             "install", "--source", str(self.source[release["version"]]),
             "--ref", release["commit"], "--no-menu"],
            label,
            timeout=1500,
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
                "type": "sing-box", "secondary_type": None,
                "protocols": [{
                    "id": 28, "core": "sing-box", "listener_id": "entry-trojan",
                    "server": DOMAIN, "public_port": PUBLIC_PORT,
                    "address_families": ["ipv4"], "name": "arm64-trojan",
                    "uuid": self.core_credential,
                    "trojan": {"domain": DOMAIN},
                }],
            },
            "accounts": [{
                "id": self.account, "name": "arm64-independent", "enabled": True,
                "uuid": str(uuid.uuid4()), "password": self.managed_password,
                "shadowsocks_password": None, "listeners": ["entry-trojan"],
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
        require(
            set(self.last_ledger) == {self.core_credential, self.account},
            "pure Trojan statistics identity set mismatch",
        )
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
            if set(services) == {"sing-box"} and len(rows) == 1 and all(
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
            config_digest = self.platform_configs[(version, name)]
            kind = image_id_kind(
                row["Id"], config_digest, image["index_digest"], self.containerd_image_store,
            )
            if name in services:
                require(services[name]["Image"] == row["Id"] and services[name]["Config"]["Image"] == image["reference"], "service image binding mismatch")
            proof[name] = {
                "image_id": row["Id"], "reference": image["reference"],
                "image_id_kind": kind, "config_digest": config_digest,
                "index_digest": image["index_digest"],
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
        config = trojan_client(credential, socks_port, server_name)
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
                    "tls_alpn": ["http/1.1"], "protocol": "trojan",
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
        require(
            not any(
                "sha256" in row for path, row in tree.items()
                if path.startswith(("config/xray/", "config/nginx/"))
            ),
            "pure sing-box scenario generated another core or frontend",
        )
        runtime_path = ROOT / "config/sing-box/config.json"
        runtime = trojan_runtime(
            json.loads(runtime_path.read_text()), self.core_credential,
            self.account, self.managed_password,
        )
        deployment_path = ROOT / "deployment.json"
        deployment = json.loads(deployment_path.read_text())
        require(
            deployment["core"] == {
                "type": "sing-box", "secondary_type": None, "protocol_ids": [28],
            }
            and deployment["compose"]["profiles"] == ["core-sing-box"]
            and deployment["listeners"] == [{
                "service": "sing-box", "public_port": PUBLIC_PORT,
                "container_port": PUBLIC_PORT, "transport": "tcp",
                "address_families": ["ipv4"], "listener_id": "entry-trojan",
            }],
            "pure sing-box deployment listener or profile mismatch",
        )
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
            row["IPAddress"] for row in services["sing-box"]["NetworkSettings"]["Networks"].values()
            if row.get("IPAddress")
        }
        require(peers, "sing-box bridge source missing")
        image = manifest["images"]["sing-box"]["reference"]
        self.traffic(self.core_credential, label + "-core", True, image, peers)
        self.traffic(self.managed_password, label + "-account", True, image, peers)
        self.traffic(str(uuid.uuid4()), label + "-wrong", False, image, peers)
        if label == "installed-old":
            self.traffic(
                self.core_credential, label + "-wrong-sni", False, image, peers,
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
                "runtime": runtime, "runtime_sha256": digest(runtime_path.read_bytes()),
                "deployment_sha256": digest(deployment_path.read_bytes()),
                "deployment_profiles": deployment["compose"]["profiles"],
                "deployment_listeners": deployment["listeners"],
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
        if self.engine_replacement_started:
            def engine_state():
                require(self.engine_installation_verified, "Engine bootstrap did not complete")
                require(
                    self.command(["systemctl", "is-active", "docker"], "engine-cleanup-active").strip() == b"active",
                    "installed Docker daemon is not active",
                )
                self.command(["docker", "info", "--format", "{{.Architecture}}"], "engine-cleanup-available")
            attempt("engine-final-state", engine_state)
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
                "docker_engine_installation_tested": self.engine_installation_attempted,
                "docker_engine_installation_verified": self.engine_installation_verified,
            },
        )
        index = {
            path.name: {"sha256": digest(path.read_bytes()), "bytes": path.stat().st_size}
            for path in sorted(self.evidence.iterdir())
        }
        self.record("sha256-index", index)


def selfcheck():
    original = {
        "release": {"version": "old"}, "images": {}, "accounts": [{"id": "private"}],
        "core": {"type": "sing-box", "secondary_type": None, "protocols": [{"id": 28}]},
    }
    saved = copy.deepcopy(original)
    updated = expected_spec(original, NEW, {"images": {"sing-box": {"reference": "fixed"}}})
    require(original == saved and updated["accounts"] == original["accounts"], "spec copy failed")
    require(updated["images"] == {"sing-box": "fixed"} and updated["release"]["version"] == NEW["version"], "spec projection failed")
    core, account, password = "test-core-password", "test-account-id", "test-account-password"
    client = trojan_client(password, 1080)
    require(
        client["outbounds"] == [{
            "type": "trojan", "server": "127.0.0.1", "server_port": PUBLIC_PORT,
            "password": password, "tls": {
                "enabled": True, "server_name": DOMAIN, "alpn": ["http/1.1"],
                "certificate_path": "/input/ca.crt",
            },
        }]
        and trojan_client(core, 1081, "wrong-arm64.padm.test")["outbounds"][0]["tls"]["server_name"]
        == "wrong-arm64.padm.test",
        "strict Trojan client projection failed",
    )
    runtime = {
        "inbounds": [{
            "type": "trojan", "tag": "entry-trojan", "listen": "::", "listen_port": PUBLIC_PORT,
            "users": [{"name": core, "password": core}, {"name": account, "password": password}],
            "tls": {
                "enabled": True, "server_name": DOMAIN, "alpn": ["http/1.1"],
                "certificate_path": f"/etc/padm/secrets/tls/{DOMAIN}.crt",
                "key_path": f"/etc/padm/secrets/tls/{DOMAIN}.key",
            },
        }],
        "experimental": {
            "v2ray_api": {"listen": "127.0.0.1:10087", "stats": {"enabled": True, "users": [account, core]}},
        },
    }
    proof = trojan_runtime(runtime, core, account, password)
    require(
        proof["protocol_id"] == 28 and proof["core"] == "sing-box"
        and core not in json.dumps(proof) and password not in json.dumps(proof),
        "Trojan runtime proof exposed private credentials",
    )
    runtime_rejected = 0
    invalid_runtimes = [copy.deepcopy(runtime) for _ in range(6)]
    invalid_runtimes[0]["inbounds"].append(copy.deepcopy(runtime["inbounds"][0]))
    invalid_runtimes[1]["inbounds"][0]["type"] = "vmess"
    invalid_runtimes[2]["inbounds"][0]["tls"]["enabled"] = False
    invalid_runtimes[3]["inbounds"][0]["users"][1]["password"] = core
    invalid_runtimes[4]["inbounds"][0]["transport"] = {"type": "ws"}
    invalid_runtimes[5]["experimental"]["v2ray_api"]["stats"]["users"] = [core, core]
    for invalid in invalid_runtimes:
        try:
            trojan_runtime(invalid, core, account, password)
        except AssertionError:
            runtime_rejected += 1
    require(runtime_rejected == len(invalid_runtimes), "Trojan runtime negative controls failed")
    config_id, index_id, unrelated_id = "sha256:" + "1" * 64, "sha256:" + "2" * 64, "sha256:" + "3" * 64
    require(image_id_kind(config_id, config_id, index_id, False) == "config", "config image ID binding failed")
    require(image_id_kind(index_id, config_id, index_id, True) == "containerd-index", "containerd image ID binding failed")
    image_rejected = 0
    for candidate, containerd in ((index_id, False), (unrelated_id, False), (unrelated_id, True)):
        try:
            image_id_kind(candidate, config_id, index_id, containerd)
        except AssertionError:
            image_rejected += 1
    require(image_rejected == 3, "image ID negative controls failed")
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
    print(json.dumps({
        "selfcheck": "pass", "negative_controls": rejected,
        "trojan_negative_controls": runtime_rejected, "image_id_negative_controls": image_rejected,
        "pure_sing_box_trojan": True, "network_used": False,
    }))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path)
    parser.add_argument("--selfcheck", action="store_true")
    arguments = parser.parse_args()
    if arguments.selfcheck:
        require(arguments.work is None, "selfcheck does not accept work")
        selfcheck()
        engine_selfcheck()
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
