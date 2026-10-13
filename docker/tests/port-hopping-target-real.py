#!/usr/bin/env python3
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import select
import shlex
import shutil
import socket
import stat
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


def authentication(node, root, enter, phase, old_password, new_password, accepted_role,
                   server_port=27443):
    config = dict(log=dict(level="warn"), inbounds=[], outbounds=[], route=dict(rules=[]))
    checks = []
    for address in ("198.18.1.1", "2001:db8:1::1"):
        for role, password in (("old", old_password), ("new", new_password)):
            port = 24001 + len(checks)
            tag = f"auth-{port}"
            config["inbounds"].append(dict(type="socks", tag=tag, listen="127.0.0.1",
                                           listen_port=port))
            config["outbounds"].append(dict(
                type="hysteria2", tag=tag, server=address, server_port=server_port, password=password,
                tls=dict(enabled=True, server_name="target.padm.test", alpn=["h3"],
                         certificate_path=str(root / "secrets/tls/target.padm.test.crt"))))
            config["route"]["rules"].append(dict(inbound=[tag], action="route", outbound=tag))
            checks.append((port, role in accepted_role if isinstance(accepted_role, tuple)
                           else role == accepted_role))
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


def guarded_resources(node, work, root, docker, image, target, nat_before, enter,
                      self_password, alice_password):
    # 仅运行内部有限子协议；这些测试摘要不证明真实同锁父端授权。
    source = """from pathlib import Path
import os
import sys
text = Path("/usr/local/bin/padm-entrypoint").read_text()
block = text.split("port_hopping_resources() {\\n", 1)[1]
assert block.startswith(
    '    if [ "${1:-}" = run ] || [ "${1:-}" = probe ] || [ "${1:-}" = guarded ]; then\\n'
    '        set -- exec python3 /dev/fd/3 "$STATE_ROOT" "$@"\\n')
code = block.split('    "$@" 3<<\\'PY\\'\\n', 1)[1].split("\\nPY\\n", 1)[0]
assert os.getpid() == 1
sys.argv = [sys.argv[0], "/var/lib/padm/net", "guarded", *sys.argv[1:]]
exec(compile(code, "/usr/local/bin/padm-entrypoint:port_hopping_resources", "exec"))
"""
    arguments = ["30000", "30001", "27443", "198.18.1.1", "2001:db8:1::1"]
    hostname, label = os.urandom(6).hex(), os.urandom(32).hex()
    cidfile, state = node / "guarded.cid", root / "data/net/port-hopping.state"
    tmpfs = {"/tmp": "rw,nosuid,nodev,size=16m,mode=1777",
             "/run": "rw,nosuid,nodev,size=16m,mode=0755"}
    child = primary_error = None
    evidence = dict(scope="finite-guarded-child-protocol", production_authorization=False,
                    same_parent_lock_gate_verified=False, old_conntrack_revocation_verified=False,
                    standard_entrypoint_guarded_exec_declared=True, python_payload_pid1=True,
                    production_entrypoint_cmd_verified=False,
                    frames=[], states={})
    deadline = time.monotonic() + 100
    with (work / "guarded-child.log").open("wb") as log:
        process = subprocess.Popen(
            docker + ["run", "--interactive", "--pull", "never", "--cidfile", str(cidfile),
                      "--label", "io.padm.hopping-guarded=" + label, "--network", "host",
                      "--hostname", hostname, "--user", "0:0", "--read-only",
                      "--cap-drop", "ALL", "--cap-add", "NET_ADMIN",
                      "--security-opt", "no-new-privileges", "--no-healthcheck",
                      "--restart", "no", "--log-driver", "none",
                      *[part for name, options in tmpfs.items()
                        for part in ("--tmpfs", name + ":" + options)],
                      "--mount", f"type=bind,source={root}/data/net,target=/var/lib/padm/net",
                      "--entrypoint", "python3", image, "-c", source, *arguments],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, bufsize=0)
        try:
            def byte(until):
                remaining = min(until, deadline) - time.monotonic()
                assert remaining > 0 and select.select(
                    [process.stdout], [], [], remaining)[0], "guarded 子帧超时"
                return os.read(process.stdout.fileno(), 1)

            def receive(phase, previous=None):
                until, data = time.monotonic() + 20, b""
                while not data.endswith(b"\n"):
                    part = byte(until)
                    assert part, "guarded 子帧提前 EOF"
                    data += part
                    assert len(data) <= 4096, "guarded 子帧超过长度"
                assert b"\0" not in data and b"\r" not in data

                def unique(pairs):
                    result = {}
                    for key, value in pairs:
                        assert key not in result, "guarded 子帧重复 JSON 键"
                        result[key] = value
                    return result

                value = json.loads(data[:-1].decode("ascii"), object_pairs_hook=unique)
                assert type(value["v"]) is int and value["v"] == 1
                assert value["phase"] == phase and re.fullmatch(r"[a-f0-9]{64}", value["nonce"])
                if phase == "challenge":
                    assert set(value) == {"v", "phase", "nonce", "host"}
                    assert value["host"] == hostname
                else:
                    assert set(value) == {"v", "phase", "nonce", "child_id", "request_sha256"}
                    assert value["child_id"] == child and value["request_sha256"] == digest
                    assert (value["nonce"] == previous["nonce"] if phase == "closed" else
                            value["nonce"] not in {frame["nonce"] for frame in evidence["frames"]})
                evidence["frames"].append(value)
                return value

            def projection(running=True):
                value = json.loads(command(
                    docker + ["container", "inspect", child], timeout=5))[0]
                assert value["Image"] == image and value["Id"] == child
                assert value["RestartCount"] == 0 and not any(
                    value["State"][key] for key in ("Restarting", "Paused", "Dead"))
                assert value["State"]["Running"] is running
                assert value["State"]["Status"] == ("running" if running else "exited")
                if not running:
                    assert value["State"]["ExitCode"] == 0
                return {key: value[key] for key in
                        ("Id", "Image", "Created", "Config", "HostConfig", "Mounts")} | {
                            "StartedAt": value["State"]["StartedAt"]}

            def send(value):
                assert time.monotonic() < deadline, "guarded 子协议总时限"
                assert projection() == fixed, "guarded 子容器投影漂移"
                data = json.dumps(value, separators=(",", ":")).encode("ascii") + b"\n"
                assert len(data) <= 4096 and process.stdin.write(data) == len(data)

            def resources(phase):
                metadata = state.lstat()
                assert (stat.S_ISREG(metadata.st_mode) and
                        stat.S_IMODE(metadata.st_mode) == 0o600 and
                        metadata.st_uid == metadata.st_gid == 0 and metadata.st_nlink == 1)
                text = state.read_text()
                values = dict(line.split("=", 1) for line in text.splitlines())
                token, chain = values["token"], values["chain"]
                assert re.fullmatch(r"[a-f0-9]{32}", token) and chain == "padm-hop-" + token[:12]
                expected = dict(schema_version="1", token=token, chain=chain, start="30000",
                                end="30001", target_port="27443", ipv4="198.18.1.1",
                                ipv6="2001:db8:1::1", phase=phase)
                assert values == expected and text == "".join(
                    key + "=" + value + "\n" for key, value in expected.items())
                dumps = {}
                for tool, address, bits in (("iptables", arguments[3], 32),
                                            ("ip6tables", arguments[4], 128)):
                    dump = command([tool, "-w", "-t", "nat", "-S"], timeout=5)
                    rows = [shlex.split(line) for line in dump.decode().splitlines()]
                    base = ["-d", f"{address}/{bits}", "-p", "udp", "-m", "udp",
                            "--dport", "30000:30001", "-m", "comment",
                            "--comment", "padm-hop:" + token]
                    destination = f"{address}:27443" if bits == 32 else f"[{address}]:27443"
                    owned = [["-N", chain], ["-A", "PREROUTING", *base, "-j", chain],
                             ["-A", chain, *base, "-j", "DNAT", "--to-destination", destination],
                             ["-A", chain, "-m", "comment", "--comment",
                              "padm-hop:" + token, "-j", "RETURN"]]
                    assert all(rows.count(rule) == 1 for rule in owned)
                    assert [row for row in rows if row[:2] == ["-A", chain]] == owned[2:]
                    assert [row for row in rows if row[:2] == ["-A", "PREROUTING"]][0] == owned[1]
                    assert [row for row in rows if row not in owned] == [
                        shlex.split(line) for line in nat_before[tool].decode().splitlines()]
                    dumps[tool] = dump.decode()
                evidence["states"][phase] = dict(state=values, nat=dumps)
                return values

            challenge = receive("challenge")
            child = cidfile.read_text().strip()
            assert re.fullmatch(r"[a-f0-9]{64}", child)
            fixed = projection()
            config, runtime = fixed["Config"], fixed["HostConfig"]
            assert config["Hostname"] == hostname and config["User"] == "0:0"
            assert config["Entrypoint"] == ["python3"] and config["Cmd"] == [
                "-c", source, *arguments]
            assert config["Healthcheck"]["Test"] == ["NONE"]
            assert config["Labels"]["io.padm.hopping-guarded"] == label
            assert not config["Tty"] and config["OpenStdin"]
            assert runtime["NetworkMode"] == "host" and runtime["ReadonlyRootfs"]
            assert not runtime["Privileged"] and runtime["CapAdd"] == ["CAP_NET_ADMIN"]
            assert runtime["CapDrop"] == ["ALL"] and runtime["SecurityOpt"] == ["no-new-privileges"]
            assert runtime["RestartPolicy"] == {"Name": "no", "MaximumRetryCount": 0}
            assert runtime["Tmpfs"] == tmpfs
            assert not any(runtime.get(key) for key in (
                "PidMode", "UsernsMode", "Devices", "DeviceRequests", "GroupAdd", "Links",
                "Binds", "VolumesFrom", "PortBindings", "Sysctls"))
            assert runtime.get("IpcMode") in {"private", ""}
            assert not config.get("Volumes")
            assert runtime["Mounts"] == [dict(Type="bind", Source=str(root / "data/net"),
                                               Target="/var/lib/padm/net")]
            assert len(fixed["Mounts"]) == 1
            mount = fixed["Mounts"][0]
            assert mount["Type"] == "bind" and mount["Source"] == str(root / "data/net")
            assert mount["Destination"] == "/var/lib/padm/net"
            assert mount["RW"] and mount["Propagation"] == "rprivate"
            evidence["child"] = fixed
            binding = target["startup_binding"]
            request = dict(
                v=1, nonce=challenge["nonce"], parent_pid=os.getpid(),
                parent_lock_sha256=hashlib.sha256(json.dumps(
                    binding["lock"], separators=(",", ":")).encode()).hexdigest(),
                startup_sha256=hashlib.sha256(json.dumps(
                    binding, separators=(",", ":")).encode()).hexdigest(),
                child_id=child, image_id=image,
                target={key: target[key] for key in (
                    "container_id", "image_id", "started_at", "restart_count", "listener_id",
                    "range_start", "range_end", "target_port", "ipv4", "ipv6")})
            digest = hashlib.sha256(json.dumps(
                request, separators=(",", ":")).encode("ascii")).hexdigest()
            send(request)
            ready = receive("ready")
            assert not state.exists()
            assert {tool: command([tool, "-w", "-t", "nat", "-S"], timeout=5)
                    for tool in nat_before} == nat_before
            send({**ready, "phase": "write"})
            written = receive("written")
            written_state = resources("intent")
            send({**written, "phase": "finalize"})
            active = receive("active")
            active_state = resources("active")
            assert active_state == {**written_state, "phase": "active"}
            auth_started = time.monotonic()
            authentication(node, root, enter, "guarded-active", self_password, alice_password,
                           "old", server_port=30000)
            assert time.monotonic() - auth_started < 8, "guarded 新连接认证超出窗口"
            send({**active, "phase": "close"})
            process.stdin.close()
            receive("closed", active)
            assert byte(time.monotonic() + 20) == b"", "guarded closed 含尾随输出"
            assert process.wait(timeout=10) == 0
            log.flush()
            assert not (work / "guarded-child.log").read_bytes(), "guarded 成功仍输出 stderr"
            assert projection(False) == fixed
            assert not state.exists()
            assert {tool: command([tool, "-w", "-t", "nat", "-S"], timeout=5)
                    for tool in nat_before} == nat_before
            command(docker + ["rm", child], timeout=10)
            assert not command(docker + [
                "ps", "-aq", "--filter", "label=io.padm.hopping-guarded=" + label]).strip()
            evidence.update(dual_family_new_connections_verified=True, self_accepted=True,
                            alice_revoked=True, nat_restored=True, state_removed=True,
                            child_removed=True)
            return evidence
        except BaseException as error:
            primary_error = error
            evidence["failed"] = True
            evidence["error"] = repr(error)
            try:
                evidence["remaining_state"] = state.read_text() if state.exists() else None
            except OSError as diagnostic_error:
                evidence["state_diagnostic_error"] = repr(diagnostic_error)
            for name, args in (
                    ("inspect", docker + ["inspect", child]) if child else
                    ("containers", docker + ["ps", "-a"]),
                    *[(tool, [tool, "-w", "-t", "nat", "-S"]) for tool in nat_before]):
                try:
                    result = subprocess.run(args, capture_output=True, timeout=5)
                    evidence[name] = dict(returncode=result.returncode,
                                          stdout=result.stdout.decode(errors="replace"),
                                          stderr=result.stderr.decode(errors="replace"))
                except (OSError, subprocess.SubprocessError) as diagnostic_error:
                    evidence[name] = dict(diagnostic_error=repr(diagnostic_error))
            raise
        finally:
            cleanup_errors = []

            def cleanup(action):
                try:
                    action()
                except BaseException as error:
                    cleanup_errors.append(error)

            if child is None:
                try:
                    if cidfile.exists():
                        child = cidfile.read_text().strip()
                        assert re.fullmatch(r"[a-f0-9]{64}", child)
                except BaseException as error:
                    cleanup_errors.append(error)
                    child = None
            if process.poll() is None and child:
                # 保留正常 clean 的时间，只有超时才让外层私有 daemon 清理残留。
                cleanup(lambda: command(docker + ["kill", "--signal", "TERM", child], timeout=5))
                cleanup(lambda: process.wait(timeout=15))
            if process.poll() is None:
                cleanup(lambda: stop(process))
            if child and not evidence.get("child_removed"):
                cleanup(lambda: command(docker + ["rm", child], timeout=10))
            for stream in (process.stdin, process.stdout):
                if stream and not stream.closed:
                    cleanup(stream.close)
            cleanup(lambda: cidfile.unlink(missing_ok=True))
            if cleanup_errors:
                evidence["cleanup_errors"] = [repr(error) for error in cleanup_errors]
            if primary_error or cleanup_errors:
                # 外层失败清理会输出 *.log，保留首因与回收诊断。
                cleanup(lambda: (work / "guarded-protocol.log").write_text(
                    json.dumps(evidence, sort_keys=True)))
            if primary_error:
                for error in cleanup_errors:
                    primary_error.add_note("guarded 回收失败: " + repr(error))
            elif cleanup_errors:
                raise cleanup_errors[0]


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
        os.chown(root / "data/net", 0, 0)
        (root / "data/net").chmod(0o700)
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
            # shortcut: 复用离线基镜像依赖，只验当前标准入口；发布 Dockerfile 净构建另行验收。
            context = node / "net-image"
            context.mkdir(mode=0o700)
            shutil.copyfile(ROOT / "docker/images/net/entrypoint.sh", context / "entrypoint.sh")
            (context / "Dockerfile").write_text(
                f"FROM {inputs['net']['reference']}\n"
                "COPY --chmod=0755 entrypoint.sh /usr/local/bin/padm-entrypoint\n")
            net_tag = "padm-local/padm-net:hopping-probe-source"
            build = subprocess.run(
                ["env", "DOCKER_BUILDKIT=1", *docker, "build", "--pull=false",
                 "--network", "none", "--progress", "plain", "--tag", net_tag, str(context)],
                capture_output=True, timeout=120)
            (work / "net-image-build.log").write_bytes(build.stdout + build.stderr)
            assert build.returncode == 0, build.stderr.decode(errors="replace")
            net_image = json.loads(command(docker + ["image", "inspect", net_tag]))[0]
            net_digest = net_image["Descriptor"]["digest"]
            assert re.fullmatch(r"sha256:[a-f0-9]{64}", net_digest), net_image
            assert net_image["Config"]["Entrypoint"] == ["/usr/local/bin/padm-entrypoint"]
            assert net_image["Config"]["User"] == "0:0"
            net_reference = net_tag + "@" + net_digest
            assert json.loads(command(docker + ["image", "inspect", net_reference]))[0][
                "Id"] == net_image["Id"]
            spec = root / "config/spec.json"
            configured = json.loads(spec.read_text())
            configured["images"]["net"] = net_reference
            spec.write_text(json.dumps(configured))
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
            alice = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
            alice_password = "55555555-5555-4555-8555-555555555555"
            current["accounts"] = [dict(
                id=alice, name="Alice", enabled=True, uuid=alice_password,
                password=alice_password, shadowsocks_password=None,
                listeners=["entry-hy2"])]
            spec.write_text(json.dumps(current))
            state.write_text(json.dumps(dict(schema_version=1, accounts={
                new_password: dict(name="self", upload=1, download=0, limit_bytes=0, baseline={}),
                alice: dict(name="Alice", upload=0, download=0, limit_bytes=1, baseline={})})))
            command(["env", "PADM_DOCKER_INSTALL_DIR=" + str(root),
                     "bash", "-Eeuo", "pipefail", "-c", """
. "$1"
dockerGenerateSingBoxConfig "$2/config/spec.json" "$2/config/sing-box/users.base"
dockerTrafficRender sing-box "$2/config/sing-box/users.base" "$(dockerTrafficReadState)" \
    >"$2/config/sing-box/config.json"
dockerTlsRuntimePermissions "$2/secrets/tls"
""", "test", str(ROOT / "install-docker.sh"), str(root)])
            command(compose + ["up", "-d", "--force-recreate", "--no-deps", "sing-box"], timeout=45)
            identity = command(compose + ["ps", "-q", "sing-box"]).decode().strip()
            wait_ready(lambda: inspect(docker, identity)["State"].get("Health", {}).get(
                "Status") == "healthy", 45)
            authentication(node, root, enter, "quota-before", new_password, alice_password,
                           ("old", "new"))
            quota_before = checked_witness(root, docker, startup=True)
            nat_before = {tool: command([tool, "-w", "-t", "nat", "-S"])
                          for tool in ("iptables", "ip6tables")}
            jumpstate = root / "data/net/port-hopping.state"
            assert not jumpstate.exists()
            net_before = tree(root / "data/net")
            assert len(net_before) == 1
            result = command(["env", "PADM_DOCKER_INSTALL_DIR=" + str(root),
                              "DOCKER_HOST=" + docker[-1], "bash", "-Eeuo", "pipefail", "-c", """
. "$1"
dockerAcquireDeploymentLock
trap dockerReleaseDeploymentLock EXIT
dockerPortHoppingTargetProbe entry-hy2 30000 30001 198.18.1.1 2001:db8:1::1
""", "test", str(ROOT / "install-docker.sh")], timeout=90)
            quota_after = json.loads(result)
            assert quota_after["range_start"] == 30000 and quota_after["range_end"] == 30001
            ack = quota_after["probe_ack"]
            assert set(ack) == {"v", "phase", "nonce", "child_id", "request_sha256"}
            assert type(ack["v"]) is int and ack["v"] == 1 and ack["phase"] == "ack"
            assert all(re.fullmatch(r"[a-f0-9]{64}", ack[key])
                       for key in ("nonce", "child_id", "request_sha256"))
            assert not command(docker + ["ps", "-aq", "--filter",
                                        "label=io.padm.hopping-probe"]).strip()
            assert command(docker + ["ps", "-aq"]).decode().split() == [
                quota_after["container_id"][:12]], "握手没有回收本轮子容器"
            net_after = tree(root / "data/net")
            assert [row[0] for row in net_after] == [".", ".port-hopping.lock"]
            assert net_after[0][:6] == net_before[0][:6], "握手改变了 net 目录身份或权限"
            lock = root / "data/net/.port-hopping.lock"
            lock_metadata = lock.lstat()
            assert (stat.S_ISREG(lock_metadata.st_mode) and
                    stat.S_IMODE(lock_metadata.st_mode) == 0o600 and
                    lock_metadata.st_uid == lock_metadata.st_gid == 0 and
                    lock_metadata.st_nlink == 1 and lock.read_bytes() == b"")
            assert not list(root.glob(".hopping-probe.*")), "成功握手仍保留父端临时目录"
            binding = quota_after["startup_binding"]
            assert set(binding) == {"lock", "files", "state", "live"}
            current_files = {row[0]: row for row in tree(root)}
            assert binding["state"] == [current_files["data/traffic/state.json"]]
            assert [row for row in binding["live"] if len(row) == 11] == [
                current_files["config/sing-box/config.json"]]
            assert binding["lock"][-1][-1].isdigit()
            assert not jumpstate.exists()
            assert {tool: command([tool, "-w", "-t", "nat", "-S"])
                    for tool in nat_before} == nat_before, "启用准备改变了两族 NAT 正文"
            assert quota_after["container_id"] != quota_before["container_id"]
            assert quota_after["started_at"] != quota_before["started_at"]
            assert quota_after["enabled_accounts"] == 1
            accumulated = json.loads(state.read_text())["accounts"][alice]
            assert accumulated["upload"] + accumulated["download"] >= accumulated["limit_bytes"]
            authentication(node, root, enter, "quota-after", new_password, alice_password, "old")
            guarded = guarded_resources(node, work, root, docker, net_image["Id"], quota_after,
                                        nat_before, enter, new_password, alice_password)
            # 发布已删旧 CID 后故障，真实恢复仍只加载安全候选字节。
            result = subprocess.run([
                "env", "PADM_DOCKER_INSTALL_DIR=" + str(root), "DOCKER_HOST=" + docker[-1],
                "bash", "-Eeuo", "pipefail", "-c", """
. "$1"
eval "$(declare -f dockerComposeExecute | sed '1s/dockerComposeExecute/dockerComposeExecuteOriginal/')"
failed=false
dockerComposeExecute() {
    if [[ "$1" == up && "${failed}" == false ]]; then
        failed=true
        dockerComposeExecuteOriginal "$@" || return $?
        return 1
    fi
    dockerComposeExecuteOriginal "$@"
}
dockerAcquireDeploymentLock
trap dockerReleaseDeploymentLock EXIT
dockerPortHoppingTargetStartManaged entry-hy2 198.18.1.1 2001:db8:1::1
""", "test", str(ROOT / "install-docker.sh")], capture_output=True, timeout=90)
            assert result.returncode != 0 and not result.stdout, result.stderr.decode()
            recovered = checked_witness(root, docker, startup=True)
            assert recovered["container_id"] != quota_after["container_id"]
            assert recovered["enabled_accounts"] == 1
            accumulated_after = json.loads(state.read_text())["accounts"][alice]
            assert (accumulated_after["upload"] + accumulated_after["download"] >=
                    accumulated["upload"] + accumulated["download"])
            authentication(node, root, enter, "quota-recovered", new_password, alice_password, "old")
        command(compose + ["rm", "-s", "-f"], timeout=15)
        print("docker-port-hopping-target-real-snapshot=" + json.dumps(dict(
            initial=proof, restarted=changed, tls_restarted=tls_changed, image=inputs["sing-box"],
            disk_drift_refused=True, backdated_config_refused=True,
            fresh_dual_family_auth_reversed=True, backdated_tls_replacement_refused=True,
            traffic_state_update_allowed=True, locked_witness_tree_unchanged=True,
            managed_start_quota_revoked=True, failed_start_safe_recovered=True,
            activation_prepared=True, startup_file_versions_bound=True,
            parent_child_probe_verified=True, probe_child_removed=True,
            probe_empty_lock_only=True, probe_ack=ack,
            finite_guarded_child_protocol=True, guarded_same_parent_lock_verified=False,
            guarded_dual_family_new_connections=True, guarded_quota_revoked=True,
            guarded_nat_restored=True, guarded_state_removed=True, guarded_child_removed=True,
            guarded_old_conntrack_revocation_verified=False,
            guarded_protocol=guarded,
            net_image=dict(base=inputs["net"], reference=net_reference, image_id=net_image["Id"],
                           entrypoint_sha256=hashlib.sha256(
                               (context / "entrypoint.sh").read_bytes()).hexdigest()),
            probe_dual_family_nat_unchanged=True, probe_jumpstate_unchanged=True,
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
