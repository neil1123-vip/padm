"""Probe a disposable Linux runner before attempting formal native ICMP."""

import hashlib
import json
import os
from pathlib import Path
import platform
import re
import socket
import subprocess
import tarfile
import traceback
import urllib.request


ROOT = Path("/tmp/padm-icmp-preflight")
PUBLIC = ROOT / "public"
SOURCE = ROOT / "source"
TARGET = "b.951101.xyz"
COMMIT = "b8c22dba010f127f01bce04b00b2c024323b3496"
HASHES = {
    "padm-docker-bundle.tar.gz": "cda1c2f20cbfdcbdbd0454ecdfd4fd0299cba9c54695e30b73457834a944dd4f",
    "release-manifest.json": "de7c32979710cdeddda9cb8ad465c66d33baa0b54b91c92e8647d93cdcfc3edc",
    "release-manifest.sigstore.json": "51f6564d9ecd403a949b94439dbb12a26149abde7fbc67052947e472f953e8ce",
}
RESULT = {
    "passed": False, "scope": "formal-v3.44.1-independent-egress-preflight",
    "run_id": os.environ.get("GITHUB_RUN_ID"), "fixture_commit": os.environ.get("GITHUB_SHA"),
    "release_commit": COMMIT, "target": TARGET, "commands": [],
    "deployment_started": False, "icmp_echo_tested": False,
}


def command(label, *argv, timeout=180):
    try:
        done = subprocess.run(argv, capture_output=True, timeout=timeout)
        code, stdout, stderr = done.returncode, done.stdout, done.stderr
    except subprocess.TimeoutExpired as error:
        code, stdout, stderr = 124, error.stdout or b"", error.stderr or b""
    row = {"label": label, "argv": argv, "exit": code}
    for name, raw in (("stdout", stdout), ("stderr", stderr)):
        filename = label + "." + name
        (PUBLIC / filename).write_bytes(raw)
        row[name] = {"path": filename, "sha256": hashlib.sha256(raw).hexdigest()}
    RESULT["commands"].append(row)
    print(f"{label}: rc={code}", flush=True)
    return code, stdout.decode("utf-8", "replace") + stderr.decode("utf-8", "replace")


def tls_state(output):
    match = re.search(r"Pinging with SNI(.*)", output, re.S)
    if not match:
        return "unknown"
    return ("success" if "Handshake succeeded" in match[1]
            else "rejected" if "Handshake failure" in match[1] else "unknown")


def main():
    assert os.geteuid() == 0 and not ROOT.exists()
    os.umask(0o077)
    ROOT.mkdir()
    PUBLIC.mkdir()
    SOURCE.mkdir()
    try:
        RESULT["native"] = {
            "architecture": platform.machine(), "kernel": platform.release(),
            "os_release": Path("/etc/os-release").read_text(),
            "pid1": Path("/proc/1/comm").read_text().strip(),
            "pid1_netns": os.readlink("/proc/1/ns/net"),
            "caller_netns": os.readlink("/proc/self/ns/net"),
            "kvm_character_device": Path("/dev/kvm").is_char_device(),
        }
        assert RESULT["native"]["architecture"] == "x86_64"
        assert RESULT["native"]["pid1"] == "systemd"
        assert RESULT["native"]["pid1_netns"] == RESULT["native"]["caller_netns"]
        initial_code, initial = command("initial-containers", "docker", "ps", "-aq")
        assert initial_code == 0 and not initial.strip()
        assert command("virtualization", "systemd-detect-virt", "--vm")[0] == 0
        assert command("docker", "docker", "info", "--format", "{{json .}}")[0] == 0
        for name, digest in HASHES.items():
            with urllib.request.urlopen(
                "https://github.com/neil1123-vip/padm/releases/download/v3.44.1/" + name,
                timeout=90,
            ) as response:
                raw = response.read()
            assert hashlib.sha256(raw).hexdigest() == digest, name
            (ROOT / name).write_bytes(raw)
        manifest = json.loads((ROOT / "release-manifest.json").read_bytes())
        assert manifest["release"]["commit"] == COMMIT
        assert manifest["release"]["version"] == "3.44.1"
        assert command(
            "manifest-signature", "cosign", "verify-blob", "--bundle",
            str(ROOT / "release-manifest.sigstore.json"), "--certificate-identity",
            "https://github.com/neil1123-vip/padm/.github/workflows/create_release.yml@refs/heads/main",
            "--certificate-oidc-issuer", "https://token.actions.githubusercontent.com",
            str(ROOT / "release-manifest.json"),
        )[0] == 0
        with tarfile.open(ROOT / "padm-docker-bundle.tar.gz") as archive:
            members = archive.getmembers()
            assert len(members) == 315 and len({entry.name for entry in members}) == 315
            assert all(entry.isfile() and not entry.name.startswith("/")
                       and ".." not in Path(entry.name).parts for entry in members)
            archive.extractall(SOURCE, filter="data")
        for image in ("xray", "ops"):
            reference = manifest["images"][image]["reference"]
            assert command(
                image + "-signature", "cosign", "verify", reference,
                "--certificate-identity",
                "https://github.com/neil1123-vip/padm/.github/workflows/build-images.yml@refs/heads/main",
                "--certificate-oidc-issuer", "https://token.actions.githubusercontent.com",
            )[0] == 0
            assert command(image + "-pull", "docker", "pull", reference)[0] == 0
        xray = manifest["images"]["xray"]["reference"]
        # 同时保留退出码和原始文本；探针超时本身不能替代正例。
        code, output = command(
            "test-net-negative", "timeout", "--foreground", "-k", "2", "25",
            "docker", "run", "--rm", "--network", "host", "--read-only",
            "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
            xray, "tls", "ping", "-ip", "192.0.2.1", "cloudflare.com:443", timeout=40,
        )
        RESULT["test_net"] = {"exit": code, "sni_state": tls_state(output)}
        assert code in (0, 1, 124) and tls_state(output) != "success", "TEST-NET was accepted"
        addresses = sorted({row[4][0] for row in socket.getaddrinfo(TARGET, 443)})
        RESULT["target_addresses"] = addresses
        assert addresses == ["23.185.168.63"], "Target DNS differs from the intended fixture"
        code, output = command(
            "target-tls-positive", "timeout", "--foreground", "-k", "2", "30",
            "docker", "run", "--rm", "--network", "host", "--read-only",
            "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
            xray, "tls", "ping", "-ip", addresses[0], TARGET + ":443", timeout=45,
        )
        RESULT["target_tls"] = {"exit": code, "sni_state": tls_state(output)}
        assert code == 0 and tls_state(output) == "success", "Target TLS positive failed"
        spec = {
            "core": {"protocols": [{"id": 1, "reality": {
                "server_name": TARGET, "target_host": TARGET, "target_port": 443,
            }}]},
            "images": {key: value["reference"] for key, value in manifest["images"].items()},
        }
        spec_path = ROOT / "spec.json"
        spec_path.write_text(json.dumps(spec))
        code, _ = command(
            "formal-risk-preflight", "bash", "-ec",
            'source "$1/docker/lib/bootstrap.sh"; source "$1/docker/lib/services.sh"; '
            'dockerRealityTargetsValidate "$2"',
            "bash", str(SOURCE), str(spec_path), timeout=420,
        )
        RESULT["formal_preflight_exit"] = code
        assert code == 0, "The unmodified release target gate rejected the fixture"
        RESULT["passed"] = True
    except BaseException:
        RESULT["error"] = traceback.format_exc()
        raise
    finally:
        code, final = command("final-containers", "docker", "ps", "-aq")
        RESULT["container_set_restored"] = code == 0 and not final.strip()
        RESULT["passed"] = RESULT["passed"] and RESULT["container_set_restored"]
        (PUBLIC / "result.json").write_text(json.dumps(RESULT, indent=2) + "\n")
        (PUBLIC / "sha256-index.json").write_text(json.dumps({
            file.name: hashlib.sha256(file.read_bytes()).hexdigest()
            for file in sorted(PUBLIC.iterdir()) if file.is_file()
        }, indent=2) + "\n")
        for file in PUBLIC.iterdir():
            file.chmod(0o644)
        PUBLIC.chmod(0o755)
        ROOT.chmod(0o755)
        print(json.dumps({"passed": RESULT["passed"], "public": str(PUBLIC)}), flush=True)
    return 0 if RESULT["passed"] else 1


if __name__ == "__main__":
    import sys
    if "--self-check" in sys.argv:
        assert tls_state("Pinging without SNI\nHandshake succeeded\nPinging with SNI\nHandshake failure") == "rejected"
        assert tls_state("Pinging with SNI\nHandshake succeeded") == "success"
        assert tls_state("timeout") == "unknown"
        print("TLS state self-check passed")
    else:
        raise SystemExit(main())
