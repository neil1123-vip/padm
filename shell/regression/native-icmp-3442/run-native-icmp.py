"""Run the ICMP acceptance in a new child of the official Debian cloud image."""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys
import tarfile
import time


ROOT = Path("/tmp/padm-icmp-kvm/work")
SOURCE = Path("/tmp/padm-icmp-kvm/input")
GUEST_INPUT = "/root/padm-icmp-input"
BASE = ROOT / "debian-13-genericcloud-amd64-20261111-2659.qcow2"
BASE_SHA512 = (
    "3247873136ba09b060fab45e9c115239f81c1d401fce00b8fa9b872013f7135d6a40b"
    "12462ab5ac03b9fa4ed5955dd0e8d1c900109a939ad7a0a4dafe7dea47b"
)
MAC = "52:54:00:91:00:11"


def digest(path, algorithm="sha256"):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, algorithm).hexdigest()


def seed(run):
    for name in ("client", "host"):
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(run / name)], check=True)
    host = (run / "host.pub").read_text().strip()
    (run / "known_hosts").write_text(f"[127.0.0.1]:2221 {host}\n")
    (run / "meta-data").write_text(json.dumps({"instance-id": run.name, "local-hostname": "padm-native-icmp"}))
    (run / "user-data").write_text("#cloud-config\n" + json.dumps({
        "disable_root": False, "ssh_pwauth": False,
        "users": [{"name": "root", "ssh_authorized_keys": [(run / "client.pub").read_text().strip()]}],
        "ssh_keys": {"ed25519_private": (run / "host").read_text(), "ed25519_public": host},
    }))
    (run / "network-config").write_text(json.dumps({
        "version": 2, "ethernets": {"wan": {"match": {"macaddress": MAC}, "set-name": "wan", "dhcp4": True}},
    }))
    subprocess.run(["genisoimage", "-quiet", "-output", str(run / "seed.iso"), "-volid", "cidata",
                    "-joliet", "-rock", *(str(run / name) for name in
                                          ("user-data", "meta-data", "network-config"))], check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preflight-target")
    args = parser.parse_args()
    os.umask(0o077)
    run = ROOT / f"native-icmp-{time.time_ns()}"
    run.mkdir()
    print(f"private_run={run}", flush=True)
    assert digest(BASE, "sha512") == BASE_SHA512
    base_sha = digest(BASE)
    seed(run)
    child = run / "guest.qcow2"
    result = {"passed": False, "functional_passed": False, "base": str(BASE),
              "base_sha256": base_sha, "base_sha512": BASE_SHA512,
              "accelerator": "kvm", "outer_kernel": os.uname().release,
              "drivers": {name: digest(SOURCE / name) for name in
                          ("guest-native-icmp.py", "probe-native-icmp.py", "run-native-icmp.py")}}
    if args.preflight_target:
        result["preflight_target"] = args.preflight_target
    options = [
        "ssh", "-T", "-i", str(run / "client"), "-p", "2221",
        "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "ConnectTimeout=3",
        "-o", "StrictHostKeyChecking=yes", "-o", "UserKnownHostsFile=" + str(run / "known_hosts"),
        "root@127.0.0.1",
    ]

    def ssh(label, command, *, data=None, timeout=120, expected=0):
        with (run / (label + ".stdout")).open("xb") as out, (run / (label + ".stderr")).open("xb") as err:
            call = subprocess.run(options + [command], input=data, stdout=out, stderr=err, timeout=timeout)
        print(f"{label}: rc={call.returncode}", flush=True)
        if expected is not None:
            assert call.returncode == expected, f"{label} rc={call.returncode}"
        return call.returncode

    subprocess.run(["qemu-img", "create", "-f", "qcow2", "-F", "qcow2", "-b", str(BASE), str(child), "24G"],
                   check=True, capture_output=True)
    disk = subprocess.check_output(["qemu-img", "info", "--output=json", "--backing-chain", str(child)])
    (run / "disk.json").write_bytes(disk)
    chain = json.loads(disk)
    assert len(chain) == 2 and chain[0]["full-backing-filename"] == chain[1]["filename"] == str(BASE)
    launch = [
        "qemu-system-x86_64", "-machine", "q35", "-accel", "kvm", "-cpu", "host",
        "-smp", "2", "-m", "2048", "-display", "none", "-monitor", "none", "-serial", "stdio",
        "-no-reboot", "-drive", f"file={child},if=virtio,format=qcow2", "-cdrom", str(run / "seed.iso"),
        "-netdev", "user,id=wan,ipv6=off,hostfwd=tcp:127.0.0.1:2221-:22,"
                   "guestfwd=tcp:10.0.2.100:443-cmd:socat - TCP:ghcr.io:443",
        "-device", f"virtio-net-pci,netdev=wan,mac={MAC}",
    ]
    (run / "qemu.json").write_text(json.dumps(launch) + "\n")
    with (run / "console.log").open("xb") as console:
        vm = subprocess.Popen(launch, stdout=console, stderr=console)
        ready = False
        forced = False
        try:
            deadline = time.monotonic() + 180
            while not ready:
                assert vm.poll() is None, "QEMU exited before SSH readiness"
                assert time.monotonic() < deadline, "guest SSH readiness timed out"
                attempt = subprocess.run(options + ["true"], capture_output=True, timeout=6)
                ready = attempt.returncode == 0
                if not ready:
                    time.sleep(2)
            ssh("cloud-ready", "cloud-init status --wait", timeout=420)
            payload = io.BytesIO()
            with tarfile.open(fileobj=payload, mode="w") as archive:
                archive.add(SOURCE / "assets", arcname="assets")
                archive.add(ROOT / "cosign", arcname="cosign")
                for name in ("guest-native-icmp.py", "probe-native-icmp.py"):
                    archive.add(SOURCE / name, arcname=name)
            ssh("inputs", f"umask 077; mkdir -m 0700 {GUEST_INPUT} && tar -xf - -C {GUEST_INPUT}",
                data=payload.getvalue())
            invocation = ["python3", "-B", GUEST_INPUT + "/guest-native-icmp.py"]
            if args.preflight_target:
                invocation.extend(("--preflight-target", args.preflight_target))
            result["guest_exit"] = ssh("guest", shlex.join(invocation),
                                       timeout=3300, expected=None)
            result["archive_exit"] = ssh("guest-evidence",
                "tar -C /root/padm-icmp-evidence -cf - .", timeout=180, expected=None)
            assert result["archive_exit"] == 0, "no guest evidence archive"
            archive = run / "guest-evidence.stdout"
            result["archive_sha256"] = digest(archive)
            with tarfile.open(archive) as evidence:
                guest = json.load(evidence.extractfile("./guest-result.json"))
            assert result["guest_exit"] == 0 and guest["passed"] is True, "guest acceptance failed"
            if args.preflight_target:
                assert guest["scope"] == "formal-3.44.2-native-amd64-reality-preflight"
                assert guest["preflight"]["target"] == args.preflight_target
                assert guest["scenarios"] == {} and guest["preflight"]["passed"] is True
                result["preflight_passed"] = True
            else:
                result["functional_passed"] = True
        finally:
            if ready and vm.poll() is None:
                try:
                    result["poweroff_exit"] = ssh("poweroff", "systemctl poweroff", timeout=15, expected=None)
                except subprocess.TimeoutExpired:
                    result["poweroff_exit"] = 124
            try:
                vm.wait(timeout=90)
            except subprocess.TimeoutExpired:
                forced = True
                vm.terminate()
                try:
                    vm.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    vm.kill()
                    vm.wait()
            result.update(qemu_exit=vm.returncode, forced=forced, base_final_sha256=digest(BASE))
            result["passed"] = ((result.get("preflight_passed", False) or result.get("functional_passed", False))
                                and result.get("poweroff_exit") == 0
                                and vm.returncode == 0 and not forced
                                and result["base_final_sha256"] == base_sha)
            (run / "host-result.json").write_text(json.dumps(result, indent=2) + "\n")
            print(f"passed={result['passed']} qemu_exit={vm.returncode} forced={forced}", flush=True)
    return 0 if result["passed"] else 1


def interrupted(*_):
    raise KeyboardInterrupt


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, interrupted)
    sys.exit(main())
