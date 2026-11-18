import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import runpy
import shlex
import socket
import stat
import subprocess
import sys
import tarfile
import time
import traceback
import uuid

ROOT = Path("/etc/padm-docker")
INPUT = Path("/root/padm-icmp-input")
OUT = Path("/root/padm-icmp-evidence")
MANIFEST_SHA = "9f7756047a6c382294957b126a0d38c88ed05f98fa4797b3e604ff85705b8e4a"
BUNDLE_SHA = "37fc003d60bf3ba90cc800ef06f5381eec29853a654febd967eecade0a3e7ee8"
SIGNATURE_SHA = "02739816e299183c02c8934682cb9cbaedf4ff4d0854dee41965fcc0c90748d7"
COMMIT = "ba3c23666cb573ba99d87abe4dae8699fc0f1110"
REALITY_TARGET = "b.951101.xyz"
ASSET_ARGS = ("--manifest", str(INPUT / "assets/release-manifest.json"),
              "--bundle", str(INPUT / "assets/release-manifest.sigstore.json"),
              "--control-bundle", str(INPUT / "assets/padm-docker-bundle.tar.gz"))
REGISTRY_PROBE = ("curl", "--silent", "--show-error", "--max-time", "30",
                  "--output", "/dev/null", "--write-out", "%{http_code}\n", "https://ghcr.io/v2/")
SIGNATURE_PROBE = ("cosign", "verify-blob", "--bundle", ASSET_ARGS[3],
                   "--certificate-identity-regexp",
                   r"^https://github\.com/neil1123-vip/padm/\.github/workflows/create_release\.yml@refs/heads/main$",
                   "--certificate-oidc-issuer", "https://token.actions.githubusercontent.com", ASSET_ARGS[1])
NEGATIVE_SCRIPT = ('set +e; output=$(timeout --foreground -k 2 25 docker run --rm --network host '
                   '--read-only --cap-drop ALL --security-opt no-new-privileges "$1" '
                   'tls ping -ip 192.0.2.1 cloudflare.com:443 2>&1); code=$?; '
                   'printf "%s\\nPROBE_RC=%s\\n" "$output" "$code"; '
                   '[[ "$code" == 0 || "$code" == 1 || "$code" == 124 ]] && '
                   '[[ "$output" != *"Handshake succeeded"* ]]')
COMMANDS = []
RESULT = {"schema": 1, "passed": False, "scope": "formal-3.44.3-native-amd64-host-icmp-ipv4",
          "transparent_enabled_reboot": False, "production_access": False, "scenarios": {}}


def save(name, value):
    path = OUT / name
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    return name


def digest(content):
    return {"sha256": hashlib.sha256(content).hexdigest(), "bytes": len(content)}


def command(label, *arguments, timeout=600, check=True, private_output=False):
    sequence = len(COMMANDS) + 1
    stem = f"cmd-{sequence:04d}-{label}"
    started = time.time_ns()
    try:
        process = subprocess.run(arguments, capture_output=True, timeout=timeout)
        stdout, stderr, code = process.stdout, process.stderr, process.returncode
    except subprocess.TimeoutExpired as error:
        stdout, stderr, code = error.stdout or b"", error.stderr or b"", 124
    row = {"sequence": sequence, "label": label, "argv": list(arguments), "exit": code,
           "started_ns": started, "finished_ns": time.time_ns(),
           "stdout": digest(stdout), "stderr": digest(stderr), "private_output": private_output}
    if private_output:
        # Account CLI creates secrets; only its byte digest is exported.
        (INPUT / (stem + ".stdout")).write_bytes(stdout)
        (INPUT / (stem + ".stderr")).write_bytes(stderr)
    else:
        for stream, content in (("stdout", stdout), ("stderr", stderr)):
            name = stem + "." + stream
            (OUT / name).write_bytes(content)
            row[stream]["path"] = name
    COMMANDS.append(row)
    save("commands.json", COMMANDS)
    assert not check or code == 0, f"{label}: rc={code}, evidence={stem}"
    return stdout


def cli(label, *arguments, **kwargs):
    return command(label, "/usr/local/bin/padm-docker", *arguments, **kwargs)


def obj(label, *arguments, **kwargs):
    return json.loads(command(label, *arguments, **kwargs))


def file_record(path):
    metadata = path.lstat()
    assert stat.S_ISREG(metadata.st_mode) and not path.is_symlink(), str(path)
    return {**digest(path.read_bytes()), "mode": stat.S_IMODE(metadata.st_mode),
            "uid": metadata.st_uid, "gid": metadata.st_gid}


def owner():
    path = ROOT / "data/net/transparent/tun.state"
    if not path.exists():
        return None
    return {"record": file_record(path), "content_hex": path.read_bytes().hex()}


def materials():
    spec = json.loads((ROOT / "config/spec.json").read_text())
    ledger = json.loads((ROOT / "data/traffic/state.json").read_text())
    accounts = spec.get("accounts", [])
    secrets = {str(path.relative_to(ROOT)): file_record(path)
               for path in sorted((ROOT / "secrets").rglob("*")) if path.is_file()}
    return {"accounts": [{key: value for key, value in row.items()
                          if key not in ("uuid", "password", "shadowsocks_password")}
                         | {"credentials": {key: digest(json.dumps(row.get(key), sort_keys=True).encode())
                                            for key in ("uuid", "password", "shadowsocks_password")}}
                         for row in accounts],
            "account_semantics_sha256": hashlib.sha256(json.dumps(accounts, sort_keys=True).encode()).hexdigest(),
            "secrets": secrets, "ledger": ledger,
            "business_config_sha256": hashlib.sha256(json.dumps(
                {key: value for key, value in spec.items() if key != "host_integrations"},
                sort_keys=True).encode()).hexdigest()}


def network(label):
    values = {
        "links": obj(label + "-links", "ip", "-j", "-d", "link"),
        "addresses4": obj(label + "-addresses4", "ip", "-j", "-4", "address"),
        "addresses6": obj(label + "-addresses6", "ip", "-j", "-6", "address"),
        "routes4": obj(label + "-routes4", "ip", "-j", "-N", "-4", "route", "show", "table", "all"),
        "routes6": obj(label + "-routes6", "ip", "-j", "-N", "-6", "route", "show", "table", "all"),
        "rules4": obj(label + "-rules4", "ip", "-j", "-N", "-4", "rule"),
        "rules6": obj(label + "-rules6", "ip", "-j", "-N", "-6", "rule"),
        "nft": obj(label + "-nft", "nft", "-j", "-a", "list", "ruleset"),
        "iptables": command(label + "-iptables", "iptables", "-w", "-S").decode(),
        "ip6tables": command(label + "-ip6tables", "ip6tables", "-w", "-S").decode(),
        "sysctl": {name: (Path("/proc/sys/net/ipv4") / name).read_text()
                   for name in ("ping_group_range", "icmp_echo_ignore_all", "ip_forward")},
        "host_netns": os.readlink("/proc/1/ns/net"),
        "caller_netns": os.readlink("/proc/self/ns/net"), "owner": owner(),
    }
    assert values["host_netns"] == values["caller_netns"]
    save(label + ".json", values)
    return values


def normalized(snapshot, handles):
    helpers = runpy.run_path(str(ROOT / "bundle/docker/images/net/tun-resources.py"))
    value = copy.deepcopy(snapshot)
    result = {}
    for key, rows in value.items():
        if key in ("links", "routes6"):
            counts = helpers["multiset"](rows, key)
            result[key] = dict(sorted(counts.items()))
        elif key in ("addresses4", "addresses6"):
            for device in rows:
                for address in device.get("addr_info", []):
                    for lifetime in ("valid_life_time", "preferred_life_time"):
                        if lifetime in address:
                            assert type(address[lifetime]) is int and address[lifetime] >= 0
                            address[lifetime] = 0
            result[key] = helpers["stable"](rows, handles=handles)
        else:
            result[key] = helpers["stable"](rows, handles=handles)
    return result


def unchanged_material(previous, current):
    for key in ("accounts", "account_semantics_sha256", "secrets", "business_config_sha256"):
        assert current[key] == previous[key], ("business material changed", key)
    assert set(current["ledger"]["accounts"]) == set(previous["ledger"]["accounts"])
    for identifier, before in previous["ledger"]["accounts"].items():
        after = current["ledger"]["accounts"][identifier]
        assert after["limit_bytes"] == before["limit_bytes"]
        assert after["name"] == before["name"]
        assert after["upload"] >= before["upload"] and after["download"] >= before["download"]


def release_binding(manifest):
    files = {}
    with tarfile.open(INPUT / "assets/padm-docker-bundle.tar.gz", "r:gz") as archive:
        for member in archive:
            assert member.isfile() and not member.name.startswith("/") and ".." not in Path(member.name).parts
            assert member.name not in files
            files[member.name] = digest(archive.extractfile(member).read())
    for name in ("versions.lock", "docker-bake.hcl"):
        files.pop(name)
    installed = {}
    for path in sorted((ROOT / "bundle").rglob("*")):
        if path.is_file():
            installed[str(path.relative_to(ROOT / "bundle"))] = file_record(path)
    assert set(installed) == set(files) | {".padm-docker-bundle-ref", ".padm-docker-bundle-manifest"}
    assert all(all(installed[name][key] == row[key] for key in row) for name, row in files.items())
    assert (ROOT / "bundle/.padm-docker-bundle-ref").read_text().strip() == manifest["release"]["commit"]
    images = {}
    for name, value in manifest["images"].items():
        reference = value["reference"]
        row, = obj("image-inspect-" + name, "docker", "image", "inspect", reference)
        index_raw = (INPUT / "assets" / f"image-{name}-index.json").read_bytes()
        assert "sha256:" + hashlib.sha256(index_raw).hexdigest() == value["index_digest"]
        index = json.loads(index_raw)
        platform, = [item for item in index["manifests"]
                     if item.get("platform", {}).get("architecture") == "amd64"
                     and item["platform"].get("os") == "linux"]
        repository = reference.split("@")[0].rsplit(":", 1)[0]
        platform_reference = repository + "@" + platform["digest"]
        platform_raw = (INPUT / "assets" / f"image-{name}-amd64-manifest.json").read_bytes()
        assert "sha256:" + hashlib.sha256(platform_raw).hexdigest() == platform["digest"]
        image_manifest = json.loads(platform_raw)
        assert row["Architecture"] == "amd64" and row["Os"] == "linux"
        assert row["Id"] in (image_manifest["config"]["digest"], value["index_digest"],
                             platform["digest"])
        assert reference.split("@")[1] == value["index_digest"]
        images[name] = {"reference": reference, "image": row, "index": index, "platform": platform,
                        "platform_manifest": image_manifest, "platform_reference": platform_reference}
    spec = json.loads((ROOT / "config/spec.json").read_text())
    deployment = json.loads((ROOT / "deployment.json").read_text())
    assert spec["release"]["version"] == deployment["padm_version"] == "3.44.3"
    assert spec["release"]["manifest_sha256"] == deployment["manifest"]["sha256"] == MANIFEST_SHA
    assert spec["images"] == {name: value["reference"] for name, value in manifest["images"].items()}
    result = {"release": manifest["release"], "manifest_sha256": MANIFEST_SHA,
              "bundle_sha256": BUNDLE_SHA, "signature_sha256": SIGNATURE_SHA,
              "bundle_files": installed, "images": images, "deployment": deployment}
    save("release-binding.json", result)
    return result


def prepare(preflight_target):
    for name, sha in (("release-manifest.json", MANIFEST_SHA),
                      ("padm-docker-bundle.tar.gz", BUNDLE_SHA),
                      ("release-manifest.sigstore.json", SIGNATURE_SHA)):
        assert hashlib.sha256((INPUT / "assets" / name).read_bytes()).hexdigest() == sha
    manifest = json.loads((INPUT / "assets/release-manifest.json").read_text())
    assert manifest["release"]["version"] == "3.44.3" and manifest["release"]["commit"] == COMMIT
    assert manifest["control"]["sha256"] == BUNDLE_SHA
    initial = {
        "padm_absent": not ROOT.exists() and not Path("/usr/local/bin/padm-docker").exists(),
        "engine_absent": command("initial-engine", "systemctl", "show", "docker.service",
                                "-p", "LoadState").decode().strip() == "LoadState=not-found",
    }
    save("initial-scope.json", initial)
    assert all(initial.values()), "guest was already provisioned"
    command("install-cosign", "install", "-m", "0755", str(INPUT / "cosign"), "/usr/local/bin/cosign")
    command("verify-signature", "cosign", "verify-blob", "--bundle",
            str(INPUT / "assets/release-manifest.sigstore.json"), "--certificate-identity",
            "https://github.com/neil1123-vip/padm/.github/workflows/create_release.yml@refs/heads/main",
            "--certificate-oidc-issuer", "https://token.actions.githubusercontent.com",
            str(INPUT / "assets/release-manifest.json"))
    source = INPUT / "source"
    source.mkdir()
    command("extract-bundle", "tar", "-xzf", str(INPUT / "assets/padm-docker-bundle.tar.gz"), "-C", str(source))
    command("formal-install", "bash", "-ec",
            f"printf 'y\\n' | bash {source}/install-docker.sh install --source {source} --ref {COMMIT} --no-menu",
            timeout=1800)
    jq_version = command("distro-jq-version", "/usr/bin/jq", "--version").decode().strip()
    assert jq_version in ("jq-1.7", "jq-1.7.1")
    assert command("distro-jq-owner", "dpkg-query", "-S", "/usr/bin/jq").strip() == b"jq: /usr/bin/jq"
    assert not command("distro-jq-verify", "dpkg", "--verify", "jq").strip()
    assert not Path("/usr/local/bin/jq").exists()
    RESULT["distro_jq"] = {"version": jq_version, "path": "/usr/bin/jq", "package_verified": True}
    native = {
        "architecture": command("native-arch", "uname", "-m").decode().strip(),
        "kernel": command("native-kernel", "uname", "-r").decode().strip(),
        "pid1": Path("/proc/1/comm").read_text().strip(),
        "machine_id": Path("/etc/machine-id").read_text().strip(),
        "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
        "virtualization": command("native-virt", "systemd-detect-virt", "--vm").decode().strip(),
        "pid1_netns": os.readlink("/proc/1/ns/net"),
        "caller_netns": os.readlink("/proc/self/ns/net"),
        "engine": obj("native-engine", "docker", "info", "--format", "{{json .}}"),
    }
    assert native["architecture"] == "x86_64" and native["pid1"] == "systemd"
    assert native["virtualization"] == "kvm" and native["pid1_netns"] == native["caller_netns"]
    save("native.json", native)
    RESULT["native"] = native
    assert not (ROOT / "config/spec.json").exists(), "installer unexpectedly configured a deployment"
    assert not command("initial-containers", "docker", "ps", "-a", "--format", "{{json .}}").strip()
    units = command("initial-timers", "systemctl", "list-timers", "--all", "--no-pager").decode()
    for unit in ("padm-docker-update.timer", "padm-docker-auto-update.timer"):
        state = command("query-" + unit, "systemctl", "show", unit, "-p", "LoadState").decode()
        if state.strip() != "LoadState=not-found":
            command("stop-" + unit, "systemctl", "stop", unit)
    arguments = ASSET_ARGS
    command("egress-xray-pull", "docker", "pull", manifest["images"]["xray"]["reference"], timeout=900)
    command("guest-egress-negative", "bash", "-ec", NEGATIVE_SCRIPT, "bash",
            manifest["images"]["xray"]["reference"], timeout=50)
    key = "dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo"
    public_key = "hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo"
    target = preflight_target or REALITY_TARGET
    spec = {
        "schema_version": 3,
        "release": {"version": "3.44.3", "manifest_sha256": MANIFEST_SHA,
                    "signature_identity": "https://github.com/neil1123-vip/padm/.github/workflows/create_release.yml@refs/heads/main"},
        "core": {"type": "sing-box", "secondary_type": None, "protocols": [{
            "id": 1, "core": "sing-box", "listener_id": "entry-icmp", "server": "proxy.example.com",
            "public_port": 35441, "address_families": ["ipv4"], "name": "native-icmp",
            "uuid": str(uuid.uuid4()), "reality": {"server_name": target, "target_host": target,
                "target_port": 443, "private_key": key, "public_key": public_key, "short_id": "1234"}}]},
        "tls": None, "subscription": {"enabled": False, "token": uuid.uuid4().hex},
        "images": {name: item["reference"] for name, item in manifest["images"].items()},
        "host_integrations": [],
    }
    (INPUT / "spec.json").write_text(json.dumps(spec) + "\n")
    if preflight_target:
        link = ("ip", "-j", "-6", "route", "show", "table", "all", "dev", "wan")
        before = obj("wan-ipv6-before", *link)
        ipv4, = {row[4][0] for row in socket.getaddrinfo(target, 443, socket.AF_INET, socket.SOCK_STREAM)}
        route, = obj("preflight-wan", "ip", "-j", "-4", "route", "get", ipv4)
        assert route["dev"] == "wan"
        command("formal-reality-preflight", "bash", "-ec",
                'source "$1/docker/lib/bootstrap.sh"; source "$1/docker/lib/services.sh"; '
                'dockerRealityTargetsValidate "$2"',
                "bash", str(ROOT / "bundle"), str(INPUT / "spec.json"), timeout=360, check=False)
        preflight_exit = COMMANDS[-1]["exit"]
        after = obj("wan-ipv6-after", *link)
        assert before == after and all(row.get("dst") != "default" and row.get("protocol") != "ra" for row in after)
        assert not (ROOT / "config/spec.json").exists()
        assert not command("preflight-containers", "docker", "ps", "-aq").strip()
        RESULT["preflight"] = {"passed": preflight_exit == 0, "target": target, "ipv4": ipv4,
                               "wan_ipv6_stable": True, "exit": preflight_exit}
        assert preflight_exit == 0, f"formal-reality-preflight: rc={preflight_exit}"
        return
    cli("formal-configure", "configure", "--spec", str(INPUT / "spec.json"), *arguments, timeout=1800)
    configured = json.loads((ROOT / "config/spec.json").read_text())
    assert configured["host_integrations"] == [] and not configured.get("accounts")
    assert "control" not in configured and "control_sync" not in configured
    save("protocol-baseline.json", {"type": configured["core"]["type"],
         "secondary_type": configured["core"]["secondary_type"], "protocols": [
             {field: protocol[field] for field in ("id", "listener_id", "address_families")}
             | {"target": protocol["reality"]["target_host"]} for protocol in configured["core"]["protocols"]]})
    for name, row in manifest["images"].items():
        command("formal-pull-" + name, "docker", "pull", row["reference"], timeout=900)
    cli("account-create", "account", "create", "--name", "native-icmp",
        "--listeners", "entry-icmp", private_output=True)
    account, = json.loads((ROOT / "config/spec.json").read_text())["accounts"]
    cli("account-limit", "traffic", "limit", account["id"], "1")
    command("stop-traffic-timer", "systemctl", "stop", "padm-docker-traffic.timer")
    RESULT["release"] = release_binding(manifest)
    RESULT["initial_timers"] = units


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preflight-target")
    args = parser.parse_args()
    os.umask(0o077)
    OUT.mkdir(mode=0o700, exist_ok=False)
    target = None
    server_log = None
    original_ping_range = None
    target_created = False
    validation_route = None
    enabled = False
    hosts_original = None
    try:
        if args.preflight_target:
            RESULT["scope"] = "formal-3.44.3-native-amd64-reality-preflight"
            RESULT.pop("production_access")
        prepare(args.preflight_target)
        if args.preflight_target:
            return
        hosts = Path("/etc/hosts")
        RESULT["registry_hosts_before"] = file_record(hosts)
        hosts_original = hosts.read_bytes()
        assert all(name not in hosts_original for name in (b"ghcr.io", b"tuf-repo-cdn.sigstore.dev"))
        hosts.write_bytes(hosts_original + b"\n10.0.2.100 ghcr.io\n10.0.2.101 tuf-repo-cdn.sigstore.dev\n")
        resolved = command("registry-resolve", "getent", "ahostsv4", "ghcr.io").decode().splitlines()
        assert resolved and all(row.split()[0] == "10.0.2.100" for row in resolved)
        resolved = command("trust-resolve", "getent", "ahostsv4", "tuf-repo-cdn.sigstore.dev").decode().splitlines()
        assert resolved and all(row.split()[0] == "10.0.2.101" for row in resolved)
        assert command("registry-preflight", *REGISTRY_PROBE).strip() == b"401"
        command("trust-preflight", *SIGNATURE_PROBE)
        cli("baseline-down", "down")
        assert not command("baseline-container-set", "docker", "ps", "-aq").strip()
        original_ping_range = Path("/proc/sys/net/ipv4/ping_group_range").read_text()
        RESULT["initial_network"] = network("initial-network")
        RESULT["initial_material"] = materials()
        ip, = {row[4][0] for row in socket.getaddrinfo(REALITY_TARGET, 443, socket.AF_INET, socket.SOCK_STREAM)}
        route, = obj("validation-wan", "ip", "-j", "-4", "route", "get", ip)
        assert route["dev"] == "wan"
        # Keep the formal REALITY target check on WAN when the fixture owns the default route.
        path = [ip + "/32", "via", route["gateway"], "dev", route["dev"]]
        command("host-validation-route", "ip", "route", "add", *path)
        validation_route = path
        for index, prefix in enumerate(("0.0.0.0/1", "128.0.0.0/1")):
            command("control-plane-route-" + str(index), "ip", "route", "add", prefix,
                    "via", route["gateway"], "dev", "wan")
        command("target-netns", "ip", "netns", "add", "padm-icmp-target")
        target_created = True
        setup_commands = [
            ("target-veth", ["ip", "link", "add", "icmp-uplink", "type", "veth", "peer", "name", "icmp-peer"]),
            ("target-veth-move", ["ip", "link", "set", "icmp-peer", "netns", "padm-icmp-target"]),
            ("target-no-ipv6-host", ["ip", "link", "set", "icmp-uplink", "addrgenmode", "none"]),
            ("target-no-ipv6", ["ip", "netns", "exec", "padm-icmp-target", "ip", "link", "set", "icmp-peer", "addrgenmode", "none"]),
            ("host-uplink-address", ["ip", "addr", "add", "192.0.2.1/30", "dev", "icmp-uplink"]),
            ("host-uplink-up", ["ip", "link", "set", "icmp-uplink", "up"]),
            ("target-lo-up", ["ip", "netns", "exec", "padm-icmp-target", "ip", "link", "set", "lo", "up"]),
            ("target-address", ["ip", "netns", "exec", "padm-icmp-target", "ip", "addr", "add", "192.0.2.2/30", "dev", "icmp-peer"]),
            ("target-up", ["ip", "netns", "exec", "padm-icmp-target", "ip", "link", "set", "icmp-peer", "up"]),
            ("target-global-address", ["ip", "netns", "exec", "padm-icmp-target", "ip", "addr", "add", "203.0.113.200/32", "dev", "lo"]),
            ("host-target-route", ["ip", "route", "add", "203.0.113.200/32", "via", "192.0.2.2", "dev", "icmp-uplink"]),
            ("host-target-default", ["ip", "route", "add", "default", "via", "192.0.2.2", "dev", "icmp-uplink"]),
        ]
        for label, arguments in setup_commands:
            command(label, *arguments)
        server_log = (OUT / "target-server.log").open("xb")
        target_arguments = ["ip", "netns", "exec", "padm-icmp-target", "python3", "-B",
                            str(INPUT / "probe-native-icmp.py"), "serve", str(OUT / "target-ready.json")]
        target = subprocess.Popen(target_arguments, stdout=server_log, stderr=server_log)
        RESULT["target_argv"] = target_arguments
        for _ in range(50):
            if (OUT / "target-ready.json").exists():
                break
            assert target.poll() is None
            time.sleep(0.1)
        RESULT["target"] = json.loads((OUT / "target-ready.json").read_text())
        assert RESULT["target"]["netns"] != RESULT["native"]["pid1_netns"]
        for mode in ("direct", "filtered", "denied"):
            scenario = {"passed": False}
            RESULT["scenarios"][mode] = scenario
            Path("/proc/sys/net/ipv4/ping_group_range").write_text(
                "10001 10001\n" if mode == "denied" else "0 2147483647\n")
            scenario["ping_group_range"] = Path("/proc/sys/net/ipv4/ping_group_range").read_text()
            baseline = network(mode + "-baseline")
            scenario["baseline"] = baseline
            scenario["materials_before"] = materials()
            if mode == "filtered":
                for label, arguments in [
                    ("filter-table", ["nft", "add", "table", "inet", "icmp_target"]),
                    ("filter-chain", ["nft", "add", "chain", "inet", "icmp_target", "input",
                                      "{ type filter hook input priority 0; policy accept; }"]),
                    ("filter-rule", ["nft", "add", "rule", "inet", "icmp_target", "input",
                                     "ip", "daddr", "203.0.113.200", "icmp", "type", "echo-request",
                                     "counter", "drop"]),
                ]:
                    command(label, "ip", "netns", "exec", "padm-icmp-target", *arguments)
            scenario["enable_command"] = len(COMMANDS) + 1
            cli(mode + "-enable", "edit", "--tun-enable", "--confirm", "PADM-DOCKER-EDIT",
                *ASSET_ARGS, timeout=900)
            enabled = True
            command(mode + "-stop-traffic-timer", "systemctl", "stop", "padm-docker-traffic.timer")
            before = network(mode + "-diagnose-before")
            scenario["diagnose_before"] = before
            scenario["diagnose_command"] = len(COMMANDS) + 1
            diagnosis = json.loads(cli(mode + "-diagnose", "protocol", "tun-diagnose"))
            scenario["diagnosis"] = diagnosis
            after = network(mode + "-diagnose-after")
            scenario["diagnose_after"] = after
            assert before == after or normalized(before, True) == normalized(after, True), "diagnosis changed resources"
            assert before["owner"] is not None and before["owner"] == after["owner"]
            assert diagnosis["enabled"] and diagnosis["runtime"] == "observed"
            assert diagnosis["policy"] == "direct" and diagnosis["uid"] == diagnosis["gid"] == 0
            assert diagnosis["net_raw_effective"] is False
            assert diagnosis["ping_group_allowed"] == (mode != "denied")
            assert diagnosis["netns"] == RESULT["native"]["pid1_netns"]
            assert diagnosis["socket_probe"] == diagnosis["echo_roundtrip"] == "not_tested"
            assert diagnosis["capture"] == "not_verified"
            cid = diagnosis["container_id"]
            scenario["container"] = obj(mode + "-inspect", "docker", "inspect", cid)[0]
            assert scenario["container"]["HostConfig"]["NetworkMode"] == "host"
            running_image = RESULT["release"]["images"]["sing-box"]
            assert scenario["container"]["Config"]["Image"] == running_image["reference"]
            assert scenario["container"]["Image"] == running_image["image"]["Id"]
            status = command(mode + "-core-status", "docker", "exec", "--env", "LD_PRELOAD=", cid,
                             "sh", "-ec", 'cat /proc/1/status; printf "\\nNetNS: "; readlink /proc/1/ns/net').decode()
            scenario["core_status"] = status
            values = dict(line.split(":", 1) for line in status.splitlines() if ":" in line)
            assert not int(values["CapEff"].strip(), 16) & (1 << 13)
            assert int(values["Gid"].split()[1]) == 0 and 10001 not in map(int, values["Groups"].split())
            assert command(mode + "-registry-before", *REGISTRY_PROBE).strip() == b"401"
            scenario["traffic_before"] = network(mode + "-traffic-before")
            scenario["probe_command"] = len(COMMANDS) + 1
            scenario["probe"] = obj(mode + "-probe", "python3", "-B", str(INPUT / "probe-native-icmp.py"), mode)
            assert scenario["probe"]["caller_netns"] == RESULT["native"]["pid1_netns"]
            scenario["traffic_after"] = network(mode + "-traffic-after")
            assert scenario["traffic_before"] != scenario["traffic_after"]
            assert normalized(scenario["traffic_before"], True) == normalized(scenario["traffic_after"], True)
            if mode == "filtered":
                scenario["target_filter"] = obj(mode + "-target-filter", "ip", "netns", "exec",
                    "padm-icmp-target", "nft", "-j", "-a", "list", "table", "inet", "icmp_target")
                counters = [expression["counter"] for row in scenario["target_filter"]["nftables"]
                            if "rule" in row for expression in row["rule"]["expr"] if "counter" in expression]
                assert len(counters) == 1 and counters[0]["packets"] == 1
            logs = command(mode + "-core-log", "docker", "logs", cid)
            logs += (OUT / COMMANDS[-1]["stderr"]["path"]).read_bytes()
            logs = logs.decode()
            scenario["permission_error_observed"] = "permission denied" in logs.lower() or "operation not permitted" in logs.lower()
            if mode == "denied":
                assert scenario["permission_error_observed"], "denied Echo did not produce a core permission error"
            assert command(mode + "-registry", *REGISTRY_PROBE).strip() == b"401"
            command(mode + "-trust", *SIGNATURE_PROBE)
            scenario["off_command"] = len(COMMANDS) + 1
            cli(mode + "-off", "edit", "--tun-off", "--confirm", "PADM-DOCKER-EDIT",
                *ASSET_ARGS, timeout=900)
            enabled = False
            cli(mode + "-off-down", "down")
            assert not command(mode + "-off-container-set", "docker", "ps", "-aq").strip()
            scenario["after_off"] = network(mode + "-after-off")
            scenario["materials_after"] = materials()
            unchanged_material(scenario["materials_before"], scenario["materials_after"])
            assert normalized(scenario["after_off"], False) == normalized(baseline, False), "off changed baseline resources"
            assert scenario["after_off"]["owner"] is None
            scenario["off_status"] = json.loads(cli(mode + "-off-status", "protocol", "tun-status"))
            assert scenario["off_status"]["enabled"] is False
            if mode == "filtered":
                command("filter-remove", "ip", "netns", "exec", "padm-icmp-target",
                        "nft", "delete", "table", "inet", "icmp_target")
            scenario["passed"] = True
            save("mode-" + mode + ".json", scenario)
        RESULT["scenarios_passed"] = True
    except BaseException:
        RESULT["error"] = traceback.format_exc()
        raise
    finally:
        cleanup = {"passed": True}
        try:
            if enabled:
                cli("cleanup-tun-off", "edit", "--tun-off", "--confirm", "PADM-DOCKER-EDIT",
                    *ASSET_ARGS, timeout=900)
            if original_ping_range is not None:
                Path("/proc/sys/net/ipv4/ping_group_range").write_text(original_ping_range)
            if target is not None:
                target.terminate()
                target.wait(timeout=10)
                cleanup["target_exit"] = target.returncode
            if server_log is not None:
                server_log.close()
            if target_created:
                command("cleanup-veth", "ip", "link", "delete", "icmp-uplink")
                command("cleanup-netns", "ip", "netns", "delete", "padm-icmp-target")
            if validation_route is not None:
                command("cleanup-validation-route", "ip", "route", "delete", *validation_route)
                for index, prefix in enumerate(("0.0.0.0/1", "128.0.0.0/1")):
                    command("cleanup-control-plane-route-" + str(index), "ip", "route", "delete", prefix,
                            "via", route["gateway"], "dev", "wan")
            if "initial_network" in RESULT:
                RESULT["final_network"] = network("final-network")
                assert normalized(RESULT["initial_network"], False) == normalized(RESULT["final_network"], False), "final resources differ"
                RESULT["final_material"] = materials()
                unchanged_material(RESULT["initial_material"], RESULT["final_material"])
                assert Path("/proc/sys/kernel/random/boot_id").read_text().strip() == RESULT["native"]["boot_id"]
        except BaseException:
            cleanup.update(passed=False, error=traceback.format_exc())
        if hosts_original is not None:
            try:
                hosts.write_bytes(hosts_original)
                RESULT["registry_hosts_after"] = file_record(hosts)
                assert RESULT["registry_hosts_after"] == RESULT["registry_hosts_before"]
                cleanup["hosts_restored"] = True
            except BaseException:
                cleanup.update(passed=False, hosts_restored=False, hosts_error=traceback.format_exc())
        RESULT["cleanup"] = cleanup
        RESULT["passed"] = (RESULT.get("scenarios_passed", False) or
                            RESULT.get("preflight", {}).get("passed", False)) and cleanup["passed"] and "error" not in RESULT
        save("guest-result.json", RESULT)
        save("commands.json", COMMANDS)
        print(json.dumps({"passed": RESULT["passed"], "evidence": str(OUT),
                          "scenario_count": len(RESULT["scenarios"])}), flush=True)


if __name__ == "__main__":
    main()
