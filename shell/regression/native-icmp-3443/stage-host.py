"""Stage pinned formal assets and encrypt private disposable-VM evidence."""

import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tarfile
import urllib.request


ROOT = Path("/tmp/padm-icmp-kvm")
INPUT = ROOT / "input"
WORK = ROOT / "work"
PUBLIC = ROOT / "public"
FIXTURE = Path(__file__).resolve().parent
RECIPIENT_SHA = "4853934ca45f4fc9734e7aee452f8501ea64ec628c924fdd1dc304389fe15c11"
BASE_SHA512 = ("3247873136ba09b060fab45e9c115239f81c1d401fce00b8fa9b872013f7135d6a40b"
               "12462ab5ac03b9fa4ed5955dd0e8d1c900109a939ad7a0a4dafe7dea47b")


def download(url, path, expected=None, algorithm="sha256", headers=None):
    request = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(request, timeout=90) as response, path.open("xb") as output:
        shutil.copyfileobj(response, output)
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, algorithm).hexdigest()
    assert expected is None or digest == expected, path.name
    return digest


def stage():
    assert os.geteuid() == 0 and Path("/dev/kvm").is_char_device() and not ROOT.exists()
    os.umask(0o077)
    ROOT.mkdir()
    INPUT.mkdir()
    WORK.mkdir()
    assets = INPUT / "assets"
    assets.mkdir()
    values = runpy.run_path(str(FIXTURE / "guest-native-icmp.py"))
    for name, digest in (
        ("padm-docker-bundle.tar.gz", values["BUNDLE_SHA"]),
        ("release-manifest.json", values["MANIFEST_SHA"]),
        ("release-manifest.sigstore.json", values["SIGNATURE_SHA"]),
    ):
        download("https://github.com/neil1123-vip/padm/releases/download/v3.44.3/" + name,
                 assets / name, digest)
    manifest = json.loads((assets / "release-manifest.json").read_bytes())
    assert manifest["release"]["version"] == "3.44.3"
    assert manifest["release"]["commit"] == values["COMMIT"]
    for name, image in manifest["images"].items():
        package = "neil1123-vip/padm-" + name
        with urllib.request.urlopen(
            "https://ghcr.io/token?service=ghcr.io&scope=repository:" + package + ":pull", timeout=30
        ) as response:
            token = json.load(response)["token"]
        headers = {"Authorization": "Bearer " + token,
                   "Accept": "application/vnd.oci.image.index.v1+json"}
        index = assets / ("image-" + name + "-index.json")
        download("https://ghcr.io/v2/" + package + "/manifests/" + image["index_digest"],
                 index, image["index_digest"].removeprefix("sha256:"), headers=headers)
        platform, = [row for row in json.loads(index.read_bytes())["manifests"]
                     if row.get("platform", {}).get("os") == "linux"
                     and row["platform"].get("architecture") == "amd64"]
        assert image["platforms"]["linux/amd64"] == platform["digest"]
        headers["Accept"] = platform["mediaType"]
        download("https://ghcr.io/v2/" + package + "/manifests/" + platform["digest"],
                 assets / ("image-" + name + "-amd64-manifest.json"),
                 platform["digest"].removeprefix("sha256:"), headers=headers)
    for name in ("guest-native-icmp.py", "probe-native-icmp.py", "run-native-icmp.py",
                 "verify-native-icmp.py"):
        shutil.copyfile(FIXTURE / name, INPUT / name)
    cosign = shutil.which("cosign")
    assert cosign
    shutil.copyfile(cosign, WORK / "cosign")
    (WORK / "cosign").chmod(0o755)
    base = "debian-13-genericcloud-amd64-20261111-2659.qcow2"
    download("https://cloud.debian.org/images/cloud/trixie/20261111-2659/" + base,
             WORK / base, BASE_SHA512, "sha512")
    print("Pinned release inputs and Debian parent disk staged", flush=True)


def archive():
    assert ROOT.exists() and not PUBLIC.exists()
    os.umask(0o077)
    PUBLIC.mkdir()
    runs = sorted(WORK.glob("native-icmp-*"))
    assert len(runs) == 1, "Expected one experiment"
    run, = runs
    recipient = FIXTURE / "evidence-recipient.pem"
    assert hashlib.sha256(recipient.read_bytes()).hexdigest() == RECIPIENT_SHA
    plain = ROOT / "private-evidence.tar.gz"
    included = []
    with tarfile.open(plain, "w:gz") as bundle:
        for path in sorted(run.iterdir()):
            if path.name in {"host-result.json", "qemu.json", "disk.json", "console.log"} \
                    or path.suffix in {".stdout", ".stderr"}:
                assert path.is_file() and not path.is_symlink()
                included.append("evidence/" + path.name)
                bundle.add(path, arcname=included[-1])
        bundle.add(INPUT, arcname="sources")
        for path in sorted(FIXTURE.iterdir()):
            if path.suffix in {".py", ".pem"}:
                bundle.add(path, arcname="fixture/" + path.name)
    encrypted = PUBLIC / "private-evidence.cms"
    subprocess.run([
        "openssl", "cms", "-encrypt", "-aes-256-cbc", "-binary", "-in", str(plain),
        "-outform", "DER", "-out", str(encrypted), str(recipient),
    ], check=True)
    result_path = run / "host-result.json"
    host = json.loads(result_path.read_bytes()) if result_path.exists() else {}
    status = {
        "run_id": os.environ["GITHUB_RUN_ID"], "fixture_commit": os.environ["GITHUB_SHA"],
        "host_passed": host.get("passed", False), "functional_passed": host.get("functional_passed", False),
        "guest_exit": host.get("guest_exit"), "qemu_exit": host.get("qemu_exit"),
        "forced": host.get("forced"), "normal_poweroff_exit": host.get("poweroff_exit"),
        "private_members": included,
        "recipient_sha256": RECIPIENT_SHA,
        "ciphertext_sha256": hashlib.sha256(encrypted.read_bytes()).hexdigest(),
        "plaintext_sha256": hashlib.sha256(plain.read_bytes()).hexdigest(),
        "guest_archive_sha256": host.get("archive_sha256"),
        "independent_verification_pending": True,
    }
    (PUBLIC / "run-status.json").write_text(json.dumps(status, indent=2) + "\n")
    for file in PUBLIC.iterdir():
        file.chmod(0o644)
    PUBLIC.chmod(0o755)
    ROOT.chmod(0o755)
    print(json.dumps(status), flush=True)


if __name__ == "__main__":
    archive() if "--archive" in sys.argv else stage()
