#!/usr/bin/env python3
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import socket
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(__file__).resolve()
helpers = runpy.run_path(str(SCRIPT.with_name("http-relay-published-real.py")))
command, stop, wait_ready, namespaces = (
    helpers[name] for name in ("command", "stop", "wait_ready", "namespaces"))
exact, headers = (helpers[name] for name in ("exact", "headers"))


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


def witness(root, client, listener="entry-hy2", ipv4="198.18.1.1", ipv6="2001:db8:1::1",
            startup=False):
    environment = dict(os.environ, PADM_DOCKER_INSTALL_DIR=str(root),
                       DOCKER_HOST=client[-1])
    function = "dockerPortHoppingTargetStartupWitness" if startup else "dockerPortHoppingTargetWitness"
    result = subprocess.run(["bash", "-Eeuo", "pipefail", "-c",
                            '. "$1"; "$5" "$2" "$3" "$4"',
                            "test", str(ROOT / "install-docker.sh"), listener, ipv4, ipv6, function],
                            env=environment, capture_output=True, text=True, timeout=30)
    return result


def checked_witness(root, client, *, startup=False, accepted=True):
    before = tree(root)
    result = witness(root, client, startup=startup)
    assert tree(root) == before, "目标见证不得修改受管树"
    if accepted:
        assert result.returncode == 0, result.stderr
        return json.loads(result.stdout)
    assert result.returncode != 0 and not result.stdout


def auth_probe(item):
    port, expected = item
    accepted = False
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=2) as stream:
            stream.settimeout(2)
            stream.sendall(b"\x05\x01\x00")
            assert exact(stream, 2) == b"\x05\x00"
            stream.sendall(b"\x05\x01\x00\x01" + socket.inet_aton("198.18.1.1") +
                           (18080).to_bytes(2, "big"))
            reply = exact(stream, 4)
            assert reply[:1] == b"\x05" and reply[2] == 0
            if reply[1] == 0:
                size = {1: 4, 4: 16}[reply[3]]
                exact(stream, size + 2)
                stream.sendall(b"GET /published-check HTTP/1.1\r\nHost: fixture\r\n"
                               b"Connection: close\r\n\r\n")
                response = headers(stream)
                accepted = (response.startswith(b"HTTP/1.1 200 ") and
                            exact(stream, len(helpers["BODY"])) == helpers["BODY"])
    except (OSError, EOFError):
        pass
    assert accepted == expected, (port, expected, accepted)


def authentication(node, root, enter, phase, old_password, new_password, accepted_role):
    config = dict(log=dict(level="warn"), inbounds=[], outbounds=[], route=dict(rules=[]))
    checks = []
    for address in ("198.18.1.1", "2001:db8:1::1"):
        for role, password in (("old", old_password), ("new", new_password)):
            port = 24001 + len(checks)
            tag = f"auth-{port}"
            config["inbounds"].append(dict(type="socks", tag=tag, listen="127.0.0.1",
                                           listen_port=port))
            config["outbounds"].append(dict(
                type="hysteria2", tag=tag, server=address, server_port=27443, password=password,
                tls=dict(enabled=True, server_name="target.padm.test", alpn=["h3"],
                         certificate_path=str(root / "secrets/tls/target.padm.test.crt"))))
            config["route"]["rules"].append(dict(inbound=[tag], action="route", outbound=tag))
            checks.append((port, role == accepted_role))
    path = node / "client.json"
    path.write_text(json.dumps(config))
    path.chmod(0o600)
    (node / "auth-probes.json").write_text(json.dumps(checks))
    binary = str(node / "sing-box")
    command([binary, "check", "-c", str(path)])
    with (node / f"client-{phase}.log").open("wb") as log:
        process = subprocess.Popen(enter + [binary, "run", "-c", str(path)],
                                   stdout=log, stderr=log)
    try:
        wait_ready(lambda: process.poll() is None and subprocess.run(
            enter + ["python3", "-c", "import socket; "
                     "socket.create_connection(('127.0.0.1',24001),.2).close()"],
            capture_output=True).returncode == 0)
        # 每轮新进程保证新建 QUIC 连接，不能借用重启前已经认证的会话。
        command(enter + ["python3", str(SCRIPT), "auth-probes", str(node)], timeout=8)
        assert process.poll() is None
    finally:
        stop(process)


def restart_witness(root, docker, compose, identity, previous):
    command(compose + ["restart", "sing-box"], timeout=45)
    wait_ready(lambda: (value := inspect(docker, identity))["State"].get("Health", {}).get(
        "Status") == "healthy" and value["State"]["StartedAt"] != previous["started_at"], 45)
    changed = checked_witness(root, docker, startup=True)
    assert changed["container_id"] == previous["container_id"]
    assert changed["started_at"] != previous["started_at"]
    return changed


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
    origin = None
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
            proof = checked_witness(root, docker)
            assert proof["listener_id"] == "entry-hy2" and proof["protocol_id"] == 3
            assert proof["core"] == "sing-box" and proof["container_id"] == value["Id"]
            assert proof["image_id"] == value["Image"] and proof["target_port"] == 27443
            assert proof["ipv4"] == "198.18.1.1" and proof["ipv6"] == "2001:db8:1::1"
            assert proof["enabled_accounts"] == 1
            assert checked_witness(root, docker, startup=True) == proof
            command(["env", "PADM_DOCKER_INSTALL_DIR=" + str(root), "DOCKER_HOST=" + docker[-1],
                     "bash", "-Eeuo", "pipefail", "-c", """
. "$1"
dockerAcquireDeploymentLock
python3 "$3" tree "$2" >"$4/locked-before.json"
dockerPortHoppingTargetLockedWitness entry-hy2 198.18.1.1 2001:db8:1::1 >"$4/locked.json"
python3 "$3" tree "$2" >"$4/locked-after.json"
cmp "$4/locked-before.json" "$4/locked-after.json"
dockerReleaseDeploymentLock
""", "test", str(ROOT / "install-docker.sh"), str(root), str(SCRIPT), str(work)], timeout=30)
            assert json.loads((work / "locked.json").read_text()) == proof
            image_container = command(docker + ["create", inputs["sing-box"]["image_id"]]).decode().strip()
            command(docker + ["cp", image_container + ":/usr/local/bin/sing-box",
                              str(node / "sing-box")])
            command(docker + ["rm", image_container])
            (node / "sing-box").chmod(0o755)
            with (node / "origin.log").open("wb") as log:
                origin = subprocess.Popen(["python3", str(SCRIPT.with_name(
                    "http-relay-published-real.py")), "fixture", str(node)], stdout=log, stderr=log)
            wait_ready(lambda: (node / "ready").is_file())
            enter = ["nsenter", "--target", str(clients[0].pid), "--net", "--"]
            spec = root / "config/spec.json"
            baseline = root / "config/sing-box/users.base"
            live = root / "config/sing-box/config.json"
            current = json.loads(spec.read_text())
            old_password = current["core"]["protocols"][0]["uuid"]
            new_password = "44444444-4444-4444-8444-444444444444"
            authentication(node, root, enter, "initial", old_password, new_password, "old")
            times = {path: (path.stat().st_atime_ns, path.stat().st_mtime_ns)
                     for path in (spec, baseline, live)}
            current["core"]["protocols"][0]["uuid"] = new_password
            spec.write_text(json.dumps(current))
            command(["env", "PADM_DOCKER_INSTALL_DIR=" + str(root),
                     "bash", "-Eeuo", "pipefail", "-c", """
. "$1"
dockerGenerateSingBoxConfig "$2/config/spec.json" "$2/config/sing-box/users.base"
dockerTrafficRender sing-box "$2/config/sing-box/users.base" "$(dockerTrafficReadState)" \
    >"$2/config/sing-box/config.json"
""", "test", str(ROOT / "install-docker.sh"), str(root)])
            for path, saved_times in times.items():
                os.utime(path, ns=saved_times)
            assert checked_witness(root, docker) == proof
            checked_witness(root, docker, startup=True, accepted=False)
            authentication(node, root, enter, "changed-disk", old_password, new_password, "old")
            changed = restart_witness(root, docker, compose, identity, proof)
            authentication(node, root, enter, "restarted", old_password, new_password, "new")
            for name in ("target.padm.test.crt", "target.padm.test.key"):
                path = root / "secrets/tls" / name
                metadata = path.stat()
                replacement = path.with_name(".tmp-" + name)
                replacement.write_bytes(path.read_bytes())
                os.chown(replacement, metadata.st_uid, metadata.st_gid)
                replacement.chmod(metadata.st_mode & 0o777)
                os.utime(replacement, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
                replacement.replace(path)
            assert checked_witness(root, docker) == changed
            checked_witness(root, docker, startup=True, accepted=False)
            tls_changed = restart_witness(root, docker, compose, identity, changed)
            state = root / "data/traffic/state.json"
            state.write_text(json.dumps(dict(
                schema_version=1, accounts={new_password: dict(
                    name="self", upload=1, download=0, limit_bytes=0, baseline={})})))
            assert checked_witness(root, docker, startup=True) == tls_changed
            original = live.read_bytes()
            drift = json.loads(original)
            inbound = next(value for value in drift["inbounds"] if value["tag"] == "entry-hy2")
            inbound["users"][0]["password"] = "disk-drift-fixture"
            live.write_text(json.dumps(drift))
            checked_witness(root, docker, accepted=False)
            checked_witness(root, docker, startup=True, accepted=False)
            live.write_bytes(original)
        command(compose + ["rm", "-s", "-f"], timeout=15)
        print("docker-port-hopping-target-real-snapshot=" + json.dumps(dict(
            initial=proof, restarted=changed, tls_restarted=tls_changed, image=inputs["sing-box"],
            disk_drift_refused=True, backdated_config_refused=True,
            fresh_dual_family_auth_reversed=True, backdated_tls_replacement_refused=True,
            traffic_state_update_allowed=True, locked_witness_tree_unchanged=True,
            elapsed=round(time.monotonic() - started, 3)), sort_keys=True))
    except BaseException:
        if daemon is not None and daemon.poll() is None:
            result = subprocess.run(docker + ["ps", "-aq"], capture_output=True, timeout=5)
            for identity in result.stdout.decode().split() if result.returncode == 0 else []:
                result = subprocess.run(docker + ["logs", identity], capture_output=True, timeout=5)
                (work / (identity[:12] + ".log")).write_bytes(result.stdout + result.stderr)
        if (node / "daemon.log").exists():
            shutil.copyfile(node / "daemon.log", work / "daemon.log")
        for path in node.glob("client-*.log"):
            shutil.copyfile(path, work / path.name)
        if (node / "origin.log").exists():
            shutil.copyfile(node / "origin.log", work / "origin.log")
        raise
    finally:
        try:
            if origin is not None:
                stop(origin)
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
    if sys.argv[1] == "tree":
        print(json.dumps(tree(Path(sys.argv[2])), separators=(",", ":")))
    elif sys.argv[1] == "auth-probes":
        checks = json.loads((Path(sys.argv[2]) / "auth-probes.json").read_text())
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(checks)) as pool:
            list(pool.map(auth_probe, checks))
    else:
        run(sys.argv[1])
