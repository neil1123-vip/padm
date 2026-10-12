#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(__file__).resolve()
helpers = runpy.run_path(str(SCRIPT.with_name("http-relay-published-real.py")))
command, stop, wait_ready, namespaces = (
    helpers[name] for name in ("command", "stop", "wait_ready", "namespaces"))


def tree(root):
    result = []
    for path in [root, *sorted(root.rglob("*"))]:
        metadata = path.lstat()
        row = [str(path.relative_to(root)), metadata.st_dev, metadata.st_ino,
               metadata.st_mode, metadata.st_uid, metadata.st_gid, metadata.st_nlink,
               metadata.st_size, metadata.st_mtime_ns, metadata.st_ctime_ns]
        if path.is_file():
            row.append(hashlib.sha256(path.read_bytes()).hexdigest())
        result.append(row)
    return result


def inspect(client, identity):
    return json.loads(command(client + ["container", "inspect", identity]))[0]


def witness(root, client, listener="entry-hy2", ipv4="198.18.1.1", ipv6="2001:db8:1::1"):
    environment = dict(os.environ, PADM_DOCKER_INSTALL_DIR=str(root),
                       DOCKER_HOST=client[-1])
    result = subprocess.run(["bash", "-Eeuo", "pipefail", "-c",
                            '. "$1"; dockerPortHoppingTargetWitness "$2" "$3" "$4"',
                            "test", str(ROOT / "install-docker.sh"), listener, ipv4, ipv6],
                            env=environment, capture_output=True, text=True, timeout=30)
    return result


def run(work):
    assert os.getuid() == 0 and sys.platform == "linux" and Path("/.dockerenv").is_file()
    assert {item["ifname"] for item in json.loads(command(["ip", "-j", "link", "show"]))} == {
        "lo"}, "不得借用宿主接口或已有网络"
    work = Path(work)
    inputs = json.loads(Path("/node-images.json").read_text())
    node = Path(tempfile.mkdtemp(prefix=".tmp-hopping-target-", dir="/n"))
    node.chmod(0o755)
    root = node / "state"
    docker = ["docker", "--host", f"unix://{node / 'docker.sock'}"]
    daemon = None
    clients = []
    started = time.monotonic()
    try:
        shutil.copytree(work / "state", root)
        for path in [root, *root.rglob("*")]:
            if path.is_dir():
                os.chown(path, 0, 10001)
                path.chmod(0o750)
            else:
                os.chown(path, 0, 10001)
                path.chmod(0o640)
        for name in ("config/spec.json", "config/sing-box/users.base", "data/traffic/state.json"):
            os.chown(root / name, 0, 0)
            (root / name).chmod(0o600)
        os.chown(root / "data/sing-box", 10001, 10001)
        # 生成材料与 bind 源均属于本次私有节点，保持完整生产 Compose。
        command(["env", "PADM_DOCKER_INSTALL_DIR=" + str(root),
                 "bash", "-Eeuo", "pipefail", "-c", """
. "$1"
bundle=$3
dockerCurrentBundlePath() { printf '%s\\n' "${bundle}"; }
dockerGenerateCompose "$2/config/spec.json" "$2/compose.json" "$2"
: >"$2/images.env"
dockerGenerateImagesEnv "$2/config/spec.json" "$2/images.env" "$2"
dockerGenerateDeployment "$2/config/spec.json" "$2/deployment.json"
dockerTlsRuntimePermissions "$2/secrets/tls"
""", "test", str(ROOT / "install-docker.sh"), str(root), str(work / "bundle")])
        with (node / "daemon.log").open("wb") as log:
            daemon = subprocess.Popen([
                "dockerd", "--host", docker[-1], "--data-root", str(node / "docker"),
                "--exec-root", str(node / "run"), "--pidfile", str(node / "daemon.pid"),
                "--feature", "containerd-snapshotter=true", "--storage-driver", "overlayfs",
                "--bip", "172.30.0.1/24"], stdout=log, stderr=log)
            wait_ready(lambda: subprocess.run(docker + ["info"],
                                               capture_output=True).returncode == 0, 30)
            command(docker + ["load", "--input", "/node-images.tar"], timeout=120)
            for item in inputs.values():
                actual = json.loads(command(docker + ["image", "inspect", item["reference"]]))[0]
                assert actual["Id"] == item["image_id"]
            clients = namespaces()
            compose = docker + ["compose", "--project-name", "padm-docker",
                                "--env-file", str(root / "images.env"),
                                "--file", str(root / "compose.json"),
                                "--profile", "core-sing-box"]
            command(compose + ["up", "-d", "--pull", "never"], timeout=45)
            identity = command(compose + ["ps", "-q", "sing-box"]).decode().strip()
            assert identity
            wait_ready(lambda: inspect(docker, identity)["State"].get("Health", {}).get(
                "Status") == "healthy", 45)
            value = inspect(docker, identity)
            assert value["State"]["Running"] and value["State"]["Health"]["Status"] == "healthy"
            assert value["Config"]["User"] == "10001:10001"
            assert value["HostConfig"]["ReadonlyRootfs"] and not value["HostConfig"]["Privileged"]
            before = tree(root)
            result = witness(root, docker)
            assert result.returncode == 0, result.stderr
            proof = json.loads(result.stdout)
            assert proof["listener_id"] == "entry-hy2" and proof["protocol_id"] == 3
            assert proof["core"] == "sing-box" and proof["container_id"] == value["Id"]
            assert proof["image_id"] == value["Image"] and proof["target_port"] == 27443
            assert proof["ipv4"] == "198.18.1.1" and proof["ipv6"] == "2001:db8:1::1"
            assert proof["enabled_accounts"] == 1
            assert tree(root) == before
            command(compose + ["restart", "sing-box"], timeout=45)
            wait_ready(lambda: inspect(docker, identity)["State"].get("Health", {}).get(
                "Status") == "healthy" and inspect(docker, identity)["State"]["StartedAt"]
                != proof["started_at"], 45)
            restarted = witness(root, docker)
            assert restarted.returncode == 0, restarted.stderr
            changed = json.loads(restarted.stdout)
            assert changed["container_id"] == proof["container_id"]
            assert (changed["started_at"], changed["restart_count"]) != (
                proof["started_at"], proof["restart_count"])
            assert tree(root) == before
            live = root / "config/sing-box/config.json"
            original = live.read_bytes()
            drift = json.loads(original)
            inbound = next(value for value in drift["inbounds"] if value["tag"] == "entry-hy2")
            inbound["users"][0]["password"] = "disk-drift-fixture"
            live.write_text(json.dumps(drift))
            drift_before = tree(root)
            rejected = witness(root, docker)
            assert rejected.returncode != 0 and not rejected.stdout
            assert tree(root) == drift_before
            live.write_bytes(original)
        command(compose + ["rm", "-s", "-f"], timeout=15)
        print("docker-port-hopping-target-real-snapshot=" + json.dumps(dict(
            initial=proof, restarted=changed, image=inputs["sing-box"],
            disk_drift_refused=True,
            elapsed=round(time.monotonic() - started, 3)), sort_keys=True))
    except BaseException:
        if daemon is not None and daemon.poll() is None:
            result = subprocess.run(docker + ["ps", "-aq"], capture_output=True, timeout=5)
            for identity in result.stdout.decode().split() if result.returncode == 0 else []:
                result = subprocess.run(docker + ["logs", identity], capture_output=True, timeout=5)
                (work / (identity[:12] + ".log")).write_bytes(result.stdout + result.stderr)
        if (node / "daemon.log").exists():
            shutil.copyfile(node / "daemon.log", work / "daemon.log")
        raise
    finally:
        try:
            for client in clients:
                stop(client)
            if daemon is not None:
                try:
                    result = subprocess.run(docker + ["ps", "-aq"], capture_output=True, timeout=5)
                    if result.returncode == 0 and result.stdout.strip():
                        command(docker + ["rm", "-f"] + result.stdout.decode().split(), timeout=15)
                finally:
                    stop(daemon)
        finally:
            assert node.parent == Path("/n") and node.name.startswith(".tmp-hopping-target-")
            # 容器删除失败也继续清理本轮私有 daemon 的残留挂载和目录。
            mounts = [line.split()[4] for line in Path("/proc/self/mountinfo").read_text().splitlines()
                      if line.split()[4].startswith(str(node) + "/")]
            for mount in sorted(mounts, key=lambda value: value.count("/"), reverse=True):
                command(["umount", "--lazy", "--", mount], timeout=5)
            shutil.rmtree(node)


if __name__ == "__main__":
    run(sys.argv[1])
