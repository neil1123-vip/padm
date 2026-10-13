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
import signal
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


def automatic_hopping(node, work, root, docker, enter, password):
    def invoke(*arguments):
        return command(["env", "PADM_DOCKER_INSTALL_DIR=" + str(root), "DOCKER_HOST=" + docker[-1],
                        "bash", "-Eeuo", "pipefail", "-c",
                        '. "$1"; shift; trap dockerReleaseDeploymentLock EXIT; dockerMain "$@"',
                        "test", str(ROOT / "install-docker.sh"), *arguments],
                       timeout=100)

    tables = {"ipv4": "iptables", "ipv6": "ip6tables"}
    nat_before = {table: command([table, "-w", "-t", "nat", "-S"])
                  for table in tables.values()}
    config = dict(log=dict(level="warn"), inbounds=[], outbounds=[], route=dict(rules=[]))
    checks = []
    for family, address in helpers["HOSTS"].items():
        port = 24001 + len(checks)
        config["inbounds"].append(dict(type="socks", tag=family, listen="127.0.0.1",
                                       listen_port=port))
        config["outbounds"].append(dict(
            type="hysteria2", tag=family, server=address, server_ports=["30000:30001"],
            hop_interval="5s", password=password,
            tls=dict(enabled=True, server_name="target.padm.test", alpn=["h3"],
                     certificate_path=str(root / "secrets/tls/target.padm.test.crt"))))
        config["route"]["rules"].append(dict(inbound=[family], action="route", outbound=family))
        checks.append((port, True))
        # 只在客户端 netns 计数，不把服务端的转发或其它测试流量算作跳跃。
        command(enter + [tables[family], "-w", "-t", "mangle", "-N", "PADM_HOP_CLIENT"])
        for remote in (30000, 30001):
            command(enter + [tables[family], "-w", "-t", "mangle", "-A", "PADM_HOP_CLIENT",
                             "-p", "udp", "-d", address, "--dport", str(remote), "-j", "RETURN"])
        command(enter + [tables[family], "-w", "-t", "mangle", "-A", "OUTPUT",
                         "-p", "udp", "-d", address, "--dport", "30000:30001",
                         "-j", "PADM_HOP_CLIENT"])
    path = node / "client-auto.json"
    path.write_text(json.dumps(config))
    path.chmod(0o600)
    (node / "auth-probes.json").write_text(json.dumps(checks))
    binary = str(node / "sing-box")
    command([binary, "check", "-c", str(path)])
    process = None
    active = False
    try:
        assert invoke("port-hopping", "start").decode().strip() == "端口跳跃已启用。"
        active = True
        uri = invoke("port-hopping", "share").decode().strip()
        assert uri == (f"hysteria2://{password}@target.padm.test:30000-30001"
                       "?peer=target.padm.test&insecure=0&sni=target.padm.test"
                       "&alpn=h3#Hysteria2"), uri
        initial = json.loads(invoke("port-hopping", "status"))
        with (node / "client-auto.log").open("wb") as log:
            process = subprocess.Popen(enter + [binary, "run", "-c", str(path)],
                                       stdout=log, stderr=log)
        wait_ready(lambda: process.poll() is None and subprocess.run(
            enter + ["python3", "-c", "import socket; "
                     "socket.create_connection(('127.0.0.1',24001),.2).close()"],
            capture_output=True).returncode == 0)
        started = time.monotonic()
        (node / "events.jsonl").touch(exist_ok=True)
        before = len((node / "events.jsonl").read_text().splitlines())
        samples = []
        while True:
            assert process.poll() is None
            command(enter + ["python3", str(SCRIPT), "auth-probes", str(node)], timeout=8)
            counters = {}
            for family, table in tables.items():
                raw = command(enter + [table + "-save", "-c", "-t", "mangle"]).decode()
                counters[family] = {int(port): int(packets) for packets, port in re.findall(
                    r"^\[(\d+):\d+\] -A PADM_HOP_CLIENT .*--dport (\d+) -j RETURN$", raw, re.M)}
                assert set(counters[family]) == {30000, 30001}, raw
            samples.append(dict(elapsed=round(time.monotonic() - started, 3), counters=counters))
            if len(samples) >= 2 and all(all(row.values()) for row in counters.values()):
                break
            assert time.monotonic() - started < 40, samples
            time.sleep(5.1)
        assert process.poll() is None and json.loads(path.read_text()) == config
        client_pid = process.pid
        assert json.loads(invoke("port-hopping", "status")) == initial
        assert len((node / "events.jsonl").read_text().splitlines()) - before == 2 * len(samples)
        stop(process)
        process = None
        assert invoke("port-hopping", "stop").decode().strip() == "端口跳跃已停止；保存配置保留。"
        active = False
        assert all(command([table, "-w", "-t", "nat", "-S"]) == previous
                   for table, previous in nat_before.items())
        assert not (root / "data/net/port-hopping.state").exists()
        assert not (root / "data/net/.hopping-supervisor").exists()
        assert not (root / "locks/deployment.lock").exists()
        assert not list(root.glob(".hopping-guarded.*"))
        assert not command(docker + ["ps", "-aq", "--filter",
                                    "label=io.padm.hopping-supervised"]).strip()
        # 新进程形成新 QUIC 连接；不把既有 conntrack 会话的排空算作已验。
        authentication(node, root, enter, "auto-stopped", password, "wrong-password", (),
                       server_port=30000)
        evidence = dict(scope="supervised-hy2-client-auto-hopping", client_config=config,
                        client_pid=client_pid, same_client_alive=True,
                        samples=samples, dual_family_both_ports=True,
                        stopped_new_connections_refused=True, nat_restored=True,
                        native_host_verified=False, arm64_verified=False,
                        old_conntrack_revocation_verified=False)
        (work / "automatic-hopping.json").write_text(json.dumps(evidence, sort_keys=True))
        return evidence
    finally:
        if process is not None:
            stop(process)
        if active:
            invoke("port-hopping", "stop")


def guarded_resources(node, work, root, docker, image, target, nat_before, enter,
                      self_password, alice_password):
    # 仅运行内部有限子协议；这些测试摘要不证明真实同锁父端授权。
    source = """from pathlib import Path
import os
import sys
text = Path("/usr/local/bin/padm-entrypoint").read_text()
block = text.split("port_hopping_resources() {\\n", 1)[1]
assert block.startswith(
    '    if [ "${1:-}" = run ] || [ "${1:-}" = probe ] || [ "${1:-}" = guarded ] || '
    '[ "${1:-}" = supervised ]; then\\n'
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


def supervised_session(node, work, root, docker, image, nat_before, enter,
                       self_password, alice_password, drift=False):
    phase = "drift" if drift else "term"
    state, lock = (root / "data/net" / name for name in
                   ("port-hopping.state", ".port-hopping.lock"))
    stages = set(root.glob(".hopping-guarded.*"))
    environment = dict(os.environ, PADM_DOCKER_INSTALL_DIR=str(root), DOCKER_HOST=docker[-1])
    evidence = dict(scope="supervised-hopping-session", stop=phase,
                    detached_deployment_verified=False, old_conntrack_revocation_verified=False)
    log_path = work / f"supervised-{phase}.log"
    primary_error = None
    with log_path.open("wb") as log:
        process = subprocess.Popen(["bash", "-Eeuo", "pipefail", "-c", """
. "$1"
dockerAcquireDeploymentLock
trap dockerReleaseDeploymentLock EXIT
dockerPortHoppingTargetSupervised entry-hy2 30000 30001 198.18.1.1 2001:db8:1::1
""", "test", str(ROOT / "install-docker.sh")], env=environment,
                                   stdout=subprocess.PIPE, stderr=log)
        try:
            def receipt():
                current = set(root.glob(".hopping-guarded.*")) - stages
                if not current:
                    return None
                assert len(current) == 1, "supervised 本轮证据目录不唯一"
                stage = current.pop()
                path = stage / "supervised.json"
                metadata = path.lstat()
                assert (stat.S_ISREG(metadata.st_mode) and
                        stat.S_IMODE(metadata.st_mode) == 0o600 and
                        metadata.st_uid == metadata.st_gid == 0 and metadata.st_nlink == 1)
                value = json.loads(path.read_text())
                assert set(value) == {"target", "running"}
                frame = value["running"]
                assert set(frame) == {"v", "phase", "nonce", "child_id", "request_sha256", "seq"}
                assert type(frame["v"]) is int and frame["v"] == 1 and frame["phase"] == "running"
                assert type(frame["seq"]) is int and frame["seq"] >= 1
                assert all(re.fullmatch(r"[a-f0-9]{64}", frame[key])
                           for key in ("nonce", "child_id", "request_sha256"))
                return stage, value

            first = None

            def ready():
                nonlocal first
                if process.poll() is not None:
                    return True
                try:
                    first = receipt()
                    return first is not None
                except (OSError, json.JSONDecodeError):
                    return False

            wait_ready(ready, 90)
            assert process.poll() is None, "supervised 父端在 receipt 前退出"
            stage, initial = first
            frame, target = initial["running"], initial["target"]
            child = frame["child_id"]
            assert (stage / "cid").read_text().strip() == child
            assert target["range_start"] == 30000 and target["range_end"] == 30001
            assert target["enabled_accounts"] == 1
            child_before = inspect(docker, child)
            assert child_before["Image"] == image and child_before["State"]["Running"]
            assert child_before["Config"]["Entrypoint"] == ["/usr/local/bin/padm-entrypoint"]
            assert re.fullmatch(r"[a-f0-9]{64}",
                                child_before["Config"]["Labels"]["io.padm.hopping-supervised"])
            assert child_before["Config"]["Cmd"] == [
                "port-hopping-supervised", "30000", "30001", "27443",
                "198.18.1.1", "2001:db8:1::1"]
            projection = {key: child_before[key] for key in
                          ("Id", "Image", "Created", "Config", "HostConfig", "Mounts")} | {
                              "StartedAt": child_before["State"]["StartedAt"]}
            parent_pid = root / "locks/deployment.lock/pid"
            assert parent_pid.read_text() == str(process.pid) + "\n"
            parent_lock = tree(root / "locks/deployment.lock")
            net_lock = tree(lock)
            owner = state.read_text()
            owned = dict(line.split("=", 1) for line in owner.splitlines())
            token = owned["token"]
            assert re.fullmatch(r"[a-f0-9]{32}", token)
            assert owned == dict(schema_version="1", token=token,
                                 chain="padm-hop-" + token[:12], start="30000", end="30001",
                                 target_port="27443", ipv4="198.18.1.1",
                                 ipv6="2001:db8:1::1", phase="active")
            metadata = state.lstat()
            assert (stat.S_ISREG(metadata.st_mode) and stat.S_IMODE(metadata.st_mode) == 0o600
                    and metadata.st_uid == metadata.st_gid == 0 and metadata.st_nlink == 1)
            command(docker + ["exec", child, "/usr/local/bin/padm-entrypoint",
                              "port-hopping-health", token], timeout=10)
            active_nat = {tool: command([tool, "-w", "-t", "nat", "-S"], timeout=5).decode()
                          for tool in nat_before}
            started = time.monotonic()
            evidence.update(initial=initial, child=projection, parent_lock=parent_lock,
                            net_lock=net_lock, owner=owner,
                            active_nat=active_nat,
                            traffic_auto_collector_verified=False)
            if drift:
                live = root / "config/sing-box/config.json"
                metadata = live.stat()
                data = live.read_bytes()
                replacement = live.with_name(".tmp-supervised-live")
                replacement.write_bytes(data)
                os.chown(replacement, metadata.st_uid, metadata.st_gid)
                replacement.chmod(stat.S_IMODE(metadata.st_mode))
                os.utime(replacement, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
                replacement.replace(live)
                assert live.read_bytes() == data and live.stat().st_ino != metadata.st_ino
                evidence["live_same_bytes_replaced"] = True
            else:
                authentication(node, root, enter, "supervised-initial", self_password,
                               alice_password, "old", server_port=30000)
                previous, checks = frame, 0
                # 跨过两次完整帧租约，不能只把暂态 active 作为持续运行证据。
                while time.monotonic() - started <= 41:
                    assert process.poll() is None
                    _, current = receipt()
                    assert current["target"] == target
                    fresh = current["running"]
                    assert fresh["child_id"] == child
                    assert fresh["request_sha256"] == frame["request_sha256"]
                    assert fresh["seq"] >= previous["seq"]
                    if fresh["seq"] > previous["seq"]:
                        assert fresh["nonce"] != previous["nonce"]
                        checks += 1
                        value = inspect(docker, child)
                        assert value["State"]["Running"]
                        assert {key: value[key] for key in
                                ("Id", "Image", "Created", "Config", "HostConfig", "Mounts")} | {
                                    "StartedAt": value["State"]["StartedAt"]} == projection
                    else:
                        assert fresh == previous
                    previous = fresh
                    assert parent_pid.read_text() == str(process.pid) + "\n"
                    assert tree(root / "locks/deployment.lock") == parent_lock
                    assert tree(lock) == net_lock and state.read_text() == owner
                    time.sleep(0.5)
                assert checks >= 2 and previous["seq"] > frame["seq"]
                command(docker + ["exec", child, "/usr/local/bin/padm-entrypoint",
                                  "port-hopping-health", token], timeout=10)
                assert {tool: command([tool, "-w", "-t", "nat", "-S"], timeout=5).decode()
                        for tool in nat_before} == active_nat
                authentication(node, root, enter, "supervised-renewed", self_password,
                               alice_password, "old", server_port=30001)
                evidence.update(final_running=previous, observed_renewals=checks,
                                duration=round(time.monotonic() - started, 3),
                                fresh_dual_family_self_accepted=True, alice_revoked=True)
                process.send_signal(signal.SIGTERM)
            output, _ = process.communicate(timeout=45)
            assert process.returncode == (1 if drift else 143), process.returncode
            assert not output, "supervised 会话不得输出部署成功"
            assert not state.exists()
            assert tree(lock) == net_lock
            assert {tool: command([tool, "-w", "-t", "nat", "-S"], timeout=5)
                    for tool in nat_before} == nat_before
            assert not command(docker + [
                "ps", "-aq", "--filter", "label=io.padm.hopping-supervised"]).strip()
            assert stage.is_dir() and (stage / "cid").read_text().strip() == child
            assert (stage / "supervised.json").is_file()
            assert not (root / "locks/deployment.lock").exists()
            evidence.update(parent_returncode=process.returncode, stdout_empty=True,
                            nat_restored=True, state_removed=True, child_removed=True,
                            evidence_retained=True)
            return evidence
        except BaseException as error:
            primary_error = error
            evidence.update(failed=True, error=repr(error))
            raise
        finally:
            cleanup_errors = []
            if process.poll() is None:
                try:
                    process.send_signal(signal.SIGTERM)
                    process.communicate(timeout=45)
                except BaseException as error:
                    cleanup_errors.append(error)
                    process.kill()
                    process.communicate(timeout=5)
            if primary_error:
                evidence["cleanup_errors"] = [repr(error) for error in cleanup_errors]
                for error in cleanup_errors:
                    primary_error.add_note("supervised 父端回收失败: " + repr(error))
                for stage in set(root.glob(".hopping-guarded.*")) - stages:
                    child_log = stage / "child.log"
                    if child_log.exists():
                        shutil.copyfile(child_log, work / f"supervised-{phase}-child.log")
                    try:
                        evidence["latest_receipt"] = json.loads(
                            (stage / "supervised.json").read_text())
                    except (OSError, json.JSONDecodeError) as error:
                        evidence["receipt_diagnostic_error"] = repr(error)
                evidence["remaining_state"] = state.read_text() if state.exists() else None
                (work / f"supervised-{phase}-evidence.log").write_text(
                    json.dumps(evidence, sort_keys=True))
            elif cleanup_errors:
                raise cleanup_errors[0]


def independent_supervisor(node, work, root, docker, image, nat_before, enter,
                           self_password, alice_password):
    session = root / "data/net/.hopping-supervisor"
    state = root / "data/net/port-hopping.state"
    lock = root / "data/net/.port-hopping.lock"
    environment = dict(os.environ, PADM_DOCKER_INSTALL_DIR=str(root), DOCKER_HOST=docker[-1],
                       PADM_DOCKER_BIN_DIR=str(node / "bin"))
    evidence = dict(scope="independent-hopping-supervisor",
                    native_host_verified=False, systemd_reboot_verified=False,
                    hup_verified=False, arm64_verified=False,
                    old_conntrack_revocation_verified=False,
                    traffic_auto_collector_verified=False)
    stages = set(root.glob(".hopping-guarded.*"))
    descriptors = []
    active = False
    failed_owner_retained = False
    primary_error = None
    calls = []
    cron = None
    release = node / "hopping-release"
    release.mkdir(mode=0o700)
    control = release / "control.tar.gz"
    command(["tar", "-czf", str(control), "-C", str((root / "bundle").resolve()),
             "install-docker.sh", "docker", "shell", "assets"], timeout=30)
    configured = json.loads((root / "config/spec.json").read_text())
    saved_hopping = dict(listener_id="entry-hy2", range_start=30000, range_end=30001,
                        ipv4="198.18.1.1", ipv6="2001:db8:1::1")
    assert configured["port_hopping"] == saved_hopping
    manifest = dict(
        schema_version=1,
        release=dict(version="3.9.10", commit="a" * 40, created_at="2026-10-14T00:00:00Z"),
        control=dict(bundle_url="https://fixture.invalid/control.tar.gz",
                     sha256=hashlib.sha256(control.read_bytes()).hexdigest(), min_version="3.9.9"),
        images={key: dict(reference=value, index_digest=value.split("@")[-1],
                          platforms={"linux/amd64": value.split("@")[-1],
                                     "linux/arm64": "sha256:" + "a" * 64})
                for key, value in configured["images"].items()},
        upstream=dict(alpine="fixture", xray="fixture", sing_box="fixture",
                      nginx="fixture", acme_sh="fixture"),
        formats=dict(compose=1, config=1, data=1),
        compatibility=dict(host=["linux", "rootful-docker", "compose-v2"],
                           architectures=["amd64", "arm64"], profiles=["core-sing-box"],
                           features_version=1), migrations=[])
    manifest_path = release / "manifest.json"
    manifest_path.write_text(json.dumps(manifest))
    (release / "signature.json").write_text("{}")
    entrypoint = release / "install-docker.sh"
    entrypoint.write_text(
        f'source {shlex.quote(str(ROOT / "install-docker.sh"))}\n'
        'dockerPortHoppingSupervisorStart() {\n'
        '  python3 -B "$DOCKER_LIB_DIR/port-hopping-supervisor.py" start "$PADM_DOCKER_INSTALL_DIR" '
        f'{shlex.quote(str(entrypoint))} "$@"\n'
        '}\n'
        # 私有离线发布只核本轮固定内容；真实发布验签仍由独立合同负责。
        'dockerManifestVerifierCheck() { :; }\n'
        f'dockerManifestVerifySignature() {{ [[ "$(sha256sum "$1" | cut -d" " -f1)" == '
        f'{hashlib.sha256(manifest_path.read_bytes()).hexdigest()} ]]; }}\n'
        'dockerPullManifestImages() {\n'
        '  local name; for name in "${PADM_DOCKER_MANIFEST_IMAGE_NAMES[@]}"; do\n'
        '    docker image inspect "$(dockerManifestImageReference "$name")" >/dev/null || return 1\n'
        '  done\n'
        '}\n'
        'eval "$(declare -f dockerComposeRun | sed "1s/dockerComposeRun/hoppingFixtureComposeRun/")"\n'
        'dockerComposeRun() {\n'
        f'  if [[ "$1" == up && -e {shlex.quote(str(release / "fail-up"))} ]]; then\n'
        f'    rm -- {shlex.quote(str(release / "fail-up"))}; return 11\n'
        '  fi\n'
        '  hoppingFixtureComposeRun "$@"\n'
        '}\n')
    entrypoint.chmod(0o600)

    def admission(accepted):
        started_at = time.monotonic()
        result = subprocess.run([
            "bash", "-Eeuo", "pipefail", "-c",
            '. "$1"; trap dockerReleaseDeploymentLock EXIT; dockerAcquireDeploymentLock',
            "test", str(ROOT / "install-docker.sh")],
            env=dict(environment, PADM_DOCKER_LOCK_TIMEOUT="30"),
            capture_output=True, timeout=5)
        assert result.returncode == (0 if accepted else 1) and not result.stdout, (
            result.returncode, result.stdout, result.stderr)
        if accepted:
            assert not result.stderr
        else:
            assert "跳跃监督会话存在或停止未核验".encode() in result.stderr, result.stderr
        evidence.setdefault("deployment_admission", []).append(dict(
            accepted=accepted, elapsed_ms=round((time.monotonic() - started_at) * 1000),
            returncode=result.returncode, stderr=result.stderr.decode()))

    def invoke(function, *arguments, accepted=True, json_output=True, status=0):
        with (work / "independent-supervisor.log").open("ab") as log:
            process = subprocess.Popen([
                "bash", "-Eeuo", "pipefail", "-c",
                '. "$1"; shift; trap dockerReleaseDeploymentLock EXIT; "$@"',
                "test", str(entrypoint), function, *arguments],
                env=environment, stdout=subprocess.PIPE, stderr=log)
            try:
                output, _ = process.communicate(timeout=900)
            except BaseException:
                process.kill()
                process.communicate(timeout=5)
                raise
        calls.append(dict(function=function, arguments=list(arguments), caller_pid=process.pid,
                          returncode=process.returncode,
                          stdout=output[:512].decode(errors="replace"), stdout_bytes=len(output)))
        if not accepted:
            assert process.returncode != 0 and not output, calls[-1]
            return None
        assert process.returncode == status, calls[-1]
        return process.pid, json.loads(output) if json_output else output.decode()

    def alive(descriptor):
        poller = select.poll()
        poller.register(descriptor, select.POLLIN)
        return not poller.poll(0)

    def frame(value, minimum=2):
        assert set(value) == {"v", "phase", "nonce", "child_id", "request_sha256", "seq"}
        assert type(value["v"]) is int and value["v"] == 1 and value["phase"] == "running"
        assert type(value["seq"]) is int and value["seq"] >= minimum
        assert all(re.fullmatch(r"[a-f0-9]{64}", value[key])
                   for key in ("nonce", "child_id", "request_sha256"))
        return value

    def ack(value, phase, owner=None):
        assert set(value) == {
            "v", "phase", "nonce", "client_nonce", "owner", "owner_sha256",
            *({"cleaned", "finished"} if phase == "stopped" else
              {"payload", "previous_owner", "cleaned", "finished"} if phase == "restarted" else
              {"payload", "previous_owner", "cleaned", "finished", "change"} if phase in {
                  "updated", "rolled_back"} else
              {"payload"})}
        assert type(value["v"]) is int and value["v"] == 1 and value["phase"] == phase
        assert all(re.fullmatch(r"[a-f0-9]{64}", value[key])
                   for key in ("nonce", "client_nonce", "owner_sha256"))
        assert value["nonce"] != value["client_nonce"]
        current = value["owner"]
        assert set(current) == {"v", "token", "root", "manager", "bash", "stage",
                                "stage_sha256", "state"}
        assert type(current["v"]) is int and current["v"] == 1
        assert re.fullmatch(r"[a-f0-9]{64}", current["token"])
        assert current["root"] == str(root)
        assert current["state"] == "active"
        assert re.fullmatch(r"[a-f0-9]{64}", current["stage_sha256"])
        assert value["owner_sha256"] == hashlib.sha256(json.dumps(
            current, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        if owner is not None:
            assert current == owner, "实时挑战确认的 owner 发生变化"
        return current

    def process_identity(identity):
        assert set(identity) == {"pid", "starttime_ticks", "boot_id", "pid_ns",
                                 "net_ns", "session_id"}
        pid = identity["pid"]
        assert type(pid) is int and pid > 1
        assert type(identity["session_id"]) is int and identity["session_id"] > 1
        assert type(identity["starttime_ticks"]) is int and identity["starttime_ticks"] > 0
        parts = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        assert parts[0] not in ("Z", "X"), identity
        assert str(identity["starttime_ticks"]) == parts[19]
        assert identity["boot_id"] == Path("/proc/sys/kernel/random/boot_id").read_text().strip()
        assert identity["pid_ns"] == os.readlink(f"/proc/{pid}/ns/pid")
        assert identity["net_ns"] == os.readlink(f"/proc/{pid}/ns/net")
        assert identity["session_id"] == os.getsid(pid)
        descriptor = os.pidfd_open(pid)
        descriptors.append(descriptor)
        assert alive(descriptor)
        return descriptor

    def child_projection(value):
        assert value["Image"] == image and value["State"]["Running"]
        assert value["Config"]["Entrypoint"] == ["/usr/local/bin/padm-entrypoint"]
        assert re.fullmatch(r"[a-f0-9]{64}",
                            value["Config"]["Labels"]["io.padm.hopping-supervised"])
        assert value["Config"]["Cmd"] == [
            "port-hopping-supervised", "30000", "30001", "27443",
            "198.18.1.1", "2001:db8:1::1"]
        return {key: value[key] for key in
                ("Id", "Image", "Created", "Config", "HostConfig", "Mounts")} | {
                    "StartedAt": value["State"]["StartedAt"]}

    def lifecycle_stopped(manager_fd, bash_fd):
        wait_ready(lambda: not alive(manager_fd) and not alive(bash_fd), 5)
        assert not session.exists() and not state.exists()
        assert not (root / "locks/deployment.lock").exists()
        assert all(b"padm-hop-" not in command([tool, "-w", "-t", "nat", "-S"], timeout=5)
                   for tool in nat_before)
        assert not command(docker + [
            "ps", "-aq", "--filter", "label=io.padm.hopping-supervised"]).strip()
        assert not command(docker + [
            "ps", "-aq", "--filter", "label=com.docker.compose.project=padm-docker"]).strip()
        assert tree(lock) == net_lock and set(root.glob(".hopping-guarded.*")) == stages

    def lifecycle_resume(phase):
        invoke("dockerLifecycleCommand", "up", json_output=False)
        core_id = command(docker + [
            "compose", "--project-name", "padm-docker", "--env-file",
            str(root / "images.env"), "--file", str(root / "compose.json"),
            "ps", "-q", "sing-box"]).decode().strip()
        assert core_id
        wait_ready(lambda: inspect(docker, core_id)["State"].get("Health", {}).get(
            "Status") == "healthy", 45)
        authentication(node, root, enter, phase, self_password, alice_password, "old")
        # Compose down/up 可能重建 bridge；业务恢复后固定新的普通部署 NAT 基线。
        nat_before.update({tool: command([tool, "-w", "-t", "nat", "-S"], timeout=5)
                           for tool in nat_before})

    try:
        assert not session.exists() and not state.exists()
        # lifecycle 的调度前置也使用真实工具，cron 只在本次隔离容器内运行。
        with (work / "independent-supervisor.log").open("ab") as log:
            cron = subprocess.Popen(["cron", "-f"], stdin=subprocess.DEVNULL, stdout=log, stderr=log)
        wait_ready(lambda: cron.poll() is None and subprocess.run(
            ["pgrep", "-x", "cron"], capture_output=True).returncode == 0, 5)
        # 每次 CLI 均由短命调用者发起，调用者不取得独立 owner 持有的部署锁。
        _, stopped_status = invoke("dockerMain", "port-hopping", "status")
        assert stopped_status == dict(state="stopped", saved=saved_hopping)
        caller, output = invoke("dockerMain", "port-hopping", "start", json_output=False)
        assert output.strip() == "端口跳跃已启用。"
        active = True
        _, started = invoke("dockerPortHoppingSupervisorStatus")
        evidence["started"] = started
        evidence["caller_pid"] = caller
        assert not Path(f"/proc/{caller}").exists(), "启动调用者尚未退出"
        owner = ack(started, "status")
        _, public_status = invoke("dockerMain", "port-hopping", "status")
        assert public_status == dict(state="active", saved=saved_hopping)
        _, status_output = invoke("dockerMain", "status", json_output=False)
        assert "port_hopping=active" in status_output
        evidence["saved_public_start_status"] = True
        manager_fd = process_identity(owner["manager"])
        bash_fd = process_identity(owner["bash"])
        assert owner["manager"]["pid"] != owner["bash"]["pid"]
        assert owner["manager"]["session_id"] == owner["manager"]["pid"]
        assert owner["bash"]["session_id"] == owner["manager"]["session_id"]
        assert owner["manager"]["session_id"] != os.getsid(0)
        assert owner["manager"]["net_ns"] == os.readlink("/proc/self/ns/net")
        pidfd_targets = []
        for path in Path(f"/proc/{owner['manager']['pid']}/fd").iterdir():
            try:
                if os.readlink(path) == "anon_inode:[pidfd]":
                    info = Path(f"/proc/{owner['manager']['pid']}/fdinfo/{path.name}").read_text()
                    pidfd_targets.extend(re.findall(r"(?m)^Pid:\s+(\d+)$", info))
            except FileNotFoundError:
                continue
        assert str(owner["bash"]["pid"]) in pidfd_targets, "manager 未持有本轮 Bash pidfd"
        payload = started["payload"]
        assert set(payload) == {"target", "running", "child", "directory", "stage"}
        target, running = payload["target"], frame(payload["running"])
        assert payload["stage"] == owner["stage"]
        assert owner["stage_sha256"] == hashlib.sha256(json.dumps(
            {key: payload[key] for key in ("target", "child", "directory", "stage")},
            sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        assert isinstance(payload["directory"], list)
        for row in payload["directory"]:
            path, device, inode, mode, uid, gid = row
            metadata = Path(path).lstat()
            assert [metadata.st_dev, metadata.st_ino, metadata.st_mode,
                    metadata.st_uid, metadata.st_gid] == [device, inode, mode, uid, gid]
        assert target["range_start"] == 30000 and target["range_end"] == 30001
        assert target["enabled_accounts"] == 1
        projection = child_projection(inspect(docker, running["child_id"]))
        assert payload["child"] == projection
        stage = Path(owner["stage"])
        assert stage.parent == root and stage.name.startswith(".hopping-guarded.")
        assert (stage / "cid").read_text().strip() == running["child_id"]
        metadata = session.lstat()
        assert stat.S_ISDIR(metadata.st_mode) and stat.S_IMODE(metadata.st_mode) == 0o700
        assert metadata.st_uid == metadata.st_gid == 0
        metadata = (session / "owner.json").lstat()
        assert stat.S_ISREG(metadata.st_mode) and stat.S_IMODE(metadata.st_mode) == 0o600
        assert metadata.st_uid == metadata.st_gid == 0 and metadata.st_nlink == 1
        assert json.loads((session / "owner.json").read_text()) == owner
        assert stat.S_ISSOCK((session / "control.sock").lstat().st_mode)
        assert (root / "locks/deployment.lock/pid").read_text() == (
            str(owner["bash"]["pid"]) + "\n")
        parent_lock, net_lock = tree(root / "locks/deployment.lock"), tree(lock)
        state_text = state.read_text()
        owned = dict(line.split("=", 1) for line in state_text.splitlines())
        token = owned["token"]
        assert re.fullmatch(r"[a-f0-9]{32}", token)
        assert owned == dict(schema_version="1", token=token,
                             chain="padm-hop-" + token[:12], start="30000", end="30001",
                             target_port="27443", ipv4="198.18.1.1",
                             ipv6="2001:db8:1::1", phase="active")
        command(docker + ["exec", running["child_id"], "/usr/local/bin/padm-entrypoint",
                          "port-hopping-health", token], timeout=10)
        active_nat = {tool: command([tool, "-w", "-t", "nat", "-S"], timeout=5)
                      for tool in nat_before}
        owner_before = tree(session / "owner.json")
        session_inode = session.stat().st_ino
        invoke("dockerPortHoppingSupervisorStart", "entry-hy2", "30000", "30001",
               "198.18.1.1", "2001:db8:1::1", accepted=False)
        assert session.stat().st_ino == session_inode and tree(
            session / "owner.json") == owner_before, "重复启动覆盖了原会话"
        assert tree(root / "locks/deployment.lock") == parent_lock
        evidence["duplicate_start_refused"] = True
        admission(False)
        assert tree(root / "locks/deployment.lock") == parent_lock
        assert tree(session / "owner.json") == owner_before and state.read_text() == state_text
        signal.pidfd_send_signal(manager_fd, signal.SIGHUP)
        observed = time.monotonic()
        authentication(node, root, enter, "independent-initial", self_password,
                       alice_password, "old", server_port=30000)
        previous, challenges, checks = running, {
            started["nonce"], started["client_nonce"]}, 0
        # 调用者已退出后跨两次帧租约，只以新挑战 ACK 确认实时续期。
        while time.monotonic() - observed <= 41:
            _, status = invoke("dockerPortHoppingSupervisorStatus")
            ack(status, "status", owner)
            assert status["nonce"] not in challenges and status["client_nonce"] not in challenges
            challenges.update((status["nonce"], status["client_nonce"]))
            current = status["payload"]
            assert set(current) == set(payload)
            assert all(current[key] == payload[key] for key in
                       ("target", "child", "directory", "stage"))
            fresh = frame(current["running"])
            assert fresh["child_id"] == running["child_id"]
            assert fresh["request_sha256"] == running["request_sha256"]
            assert fresh["seq"] >= previous["seq"]
            if fresh["seq"] > previous["seq"]:
                assert fresh["nonce"] != previous["nonce"]
                checks += 1
                assert child_projection(inspect(docker, fresh["child_id"])) == projection
            else:
                assert fresh == previous
            previous = fresh
            assert alive(manager_fd) and alive(bash_fd)
            assert tree(root / "locks/deployment.lock") == parent_lock
            assert tree(lock) == net_lock and state.read_text() == state_text
            assert tree(session / "owner.json") == owner_before
            time.sleep(1)
        assert checks >= 2 and previous["seq"] > running["seq"]
        evidence["hup_verified"] = True
        authentication(node, root, enter, "independent-renewed", self_password,
                       alice_password, "old", server_port=30001)
        assert {tool: command([tool, "-w", "-t", "nat", "-S"], timeout=5)
                for tool in nat_before} == active_nat
        evidence.update(final_running=previous, observed_renewals=checks,
                        duration=round(time.monotonic() - observed, 3),
                        caller_exit_survived=True, fresh_dual_family_self_accepted=True,
                        alice_revoked=True)
        # 实际 lifecycle restart 贯穿同一会话；轮询部署门禁捕捉锁交接空档。
        pending_restart = [True]
        def check_restart_admission():
            count = 0
            while pending_restart[0]:
                admission(False)
                assert session.stat().st_ino == session_inode
                count += 1
                time.sleep(0.02)
            return count
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
            observed_admission = executor.submit(check_restart_admission)
            try:
                _, second = invoke("dockerLifecycleCommand", "restart")
            finally:
                pending_restart[0] = False
            assert observed_admission.result(timeout=5) > 1
        second_owner = ack(second, "restarted")
        assert second["previous_owner"] == owner
        assert second["finished"] == dict(status=143, lock_released=True)
        assert second["cleaned"] == dict(target=target, child_id=running["child_id"],
                                         stage=owner["stage"])
        assert second["nonce"] not in challenges and second["client_nonce"] not in challenges
        assert session.stat().st_ino == session_inode
        assert alive(manager_fd) and not alive(bash_fd)
        assert second_owner["token"] != owner["token"]
        assert second_owner["manager"] == owner["manager"]
        assert second_owner["bash"]["pid"] != owner["bash"]["pid"]
        assert second_owner["bash"]["starttime_ticks"] > owner["bash"]["starttime_ticks"]
        assert second_owner["stage"] != owner["stage"] and not stage.exists()
        second_manager = process_identity(second_owner["manager"])
        second_bash = process_identity(second_owner["bash"])
        second_frame = frame(second["payload"]["running"])
        assert second_frame["child_id"] != running["child_id"]
        assert second["payload"]["target"]["container_id"] == target["container_id"]
        assert second["payload"]["target"]["started_at"] != target["started_at"]
        assert second["payload"]["target"]["enabled_accounts"] == 1
        assert (root / "locks/deployment.lock/pid").read_text() == (
            str(second_owner["bash"]["pid"]) + "\n")
        authentication(node, root, enter, "independent-restarted", self_password,
                       alice_password, "old", server_port=30000)
        # 旧 token 只用于拒绝检查，不能借用旧 ACK 授权本轮停止。
        result = subprocess.run(
            ["python3", "-B", str(ROOT / "docker/lib/port-hopping-supervisor.py"), "restart",
             str(root), owner["token"]], env=environment, capture_output=True, timeout=60)
        with (work / "independent-supervisor.log").open("ab") as log:
            log.write(result.stderr)
        assert result.returncode != 0 and not result.stdout, result.stderr.decode()
        assert json.loads((session / "owner.json").read_text()) == second_owner
        assert alive(second_manager) and alive(second_bash)
        _, status = invoke("dockerPortHoppingSupervisorStatus")
        ack(status, "status", second_owner)
        assert frame(status["payload"]["running"])["child_id"] == second_frame["child_id"]
        # 同一真实会话完成更新、回滚及更新失败恢复，逐轮验证双族新连接。
        previous_change = second
        evidence["changes"] = []
        for operation, failure in (("update", False), ("rollback", False), ("update", True)):
            previous_owner = previous_change["owner"]
            previous_target = previous_change["payload"]["target"]
            previous_bash = process_identity(previous_owner["bash"])
            before_state = json.loads((root / "data/traffic/state.json").read_text())
            before_bundle = os.readlink(root / "bundle")
            if failure:
                (release / "fail-up").touch()
            arguments = (("--manifest", str(manifest_path), "--bundle", str(release / "signature.json"),
                          "--control-bundle", str(control)) if operation == "update" else ())
            _, changed = invoke("dockerUpdateCommand" if operation == "update" else "dockerRollbackCommand",
                                *arguments, status=14 if failure else 0)
            new_owner = ack(changed, "updated" if operation == "update" else "rolled_back")
            current_spec = json.loads((root / "config/spec.json").read_text())
            current_compose = json.loads((root / "compose.json").read_text())
            assert current_spec["port_hopping"] == saved_hopping
            assert current_compose["x-padm-port-hopping"] == saved_hopping
            assert json.loads((root / "deployment.json").read_text())["port_hopping"] == saved_hopping
            assert current_compose["services"]["sing-box"]["labels"]["io.padm.release"] == (
                current_spec["release"]["version"])
            assert changed["previous_owner"] == previous_owner
            assert changed["change"] == dict(action=operation, arguments=list(arguments),
                                             status=14 if failure else 0)
            assert changed["finished"] == dict(status=143, lock_released=True)
            assert changed["cleaned"] == dict(target=previous_target,
                child_id=previous_change["payload"]["child"]["Id"], stage=previous_owner["stage"])
            assert alive(second_manager) and not alive(previous_bash)
            assert new_owner["manager"] == second_owner["manager"]
            assert all(new_owner[key] != previous_owner[key] for key in ("token", "bash", "stage"))
            assert session.stat().st_ino == session_inode
            after_state = json.loads((root / "data/traffic/state.json").read_text())
            for account, counters in before_state["accounts"].items():
                for counter in ("upload", "download"):
                    assert after_state["accounts"][account][counter] >= counters[counter]
            assert changed["payload"]["target"]["container_id"] != previous_target["container_id"]
            assert changed["payload"]["target"]["enabled_accounts"] == 1
            if failure:
                assert os.readlink(root / "bundle") == before_bundle
            authentication(node, root, enter, f"independent-{operation}-{failure}", self_password,
                           alice_password, "old", server_port=30000)
            admission(False)
            evidence["changes"].append(changed)
            previous_change = changed
        second_owner = previous_change["owner"]
        second_bash = process_identity(second_owner["bash"])
        # 失败事务按约定保留证据 stage，后续 stop 只清理活动代次。
        stages = set(root.glob(".hopping-guarded.*")) - {Path(second_owner["stage"])}
        changed_lock = tree(lock)
        # 运行态 chown 合法改变 ctime，原 inode、权限、修改时间与内容仍须一致。
        assert [row[:9] + row[10:] for row in changed_lock] == (
            [row[:9] + row[10:] for row in net_lock])
        net_lock = changed_lock
        _, down_output = invoke("dockerLifecycleCommand", "down", json_output=False)
        assert not down_output
        lifecycle_stopped(second_manager, second_bash)
        active = False
        admission(True)
        assert (root / "config/spec.json").is_file() and (root / "bundle").is_symlink()
        evidence.update(second_started=second, lifecycle_down=True,
                        stale_token_refused=True, online_lifecycle_restart=True,
                        fresh_owner_restart=True, session_preserved=True,
                        nat_restored=True, state_removed=True, child_removed=True,
                        deployment_lock_released=True, session_removed=True)
        lifecycle_resume("lifecycle-down-resumed")
        _, stopped = invoke("dockerPortHoppingSupervisorStart")
        active = True
        stopped_owner = ack(stopped, "started")
        stopped_manager = process_identity(stopped_owner["manager"])
        stopped_bash = process_identity(stopped_owner["bash"])
        _, stop_output = invoke("dockerMain", "port-hopping", "stop", json_output=False)
        assert stop_output.strip() == "端口跳跃已停止；保存配置保留。"
        wait_ready(lambda: not alive(stopped_manager) and not alive(stopped_bash), 90)
        assert not session.exists() and not state.exists()
        assert not (root / "locks/deployment.lock").exists()
        assert json.loads((root / "config/spec.json").read_text())["port_hopping"] == saved_hopping
        assert tree(lock) == net_lock and set(root.glob(".hopping-guarded.*")) == stages
        evidence["saved_public_stop"] = True
        active = False
        _, terminated = invoke("dockerPortHoppingSupervisorStart")
        active = True
        term_owner = ack(terminated, "started")
        term_manager = process_identity(term_owner["manager"])
        term_bash = process_identity(term_owner["bash"])
        term_started = time.monotonic()
        signal.pidfd_send_signal(term_manager, signal.SIGTERM)
        wait_ready(lambda: not alive(term_manager) and not alive(term_bash), 90)
        assert not session.exists() and not state.exists()
        assert not (root / "locks/deployment.lock").exists()
        assert tree(lock) == net_lock and set(root.glob(".hopping-guarded.*")) == stages
        assert {tool: command([tool, "-w", "-t", "nat", "-S"], timeout=5)
                for tool in nat_before} == nat_before
        assert not command(docker + [
            "ps", "-aq", "--filter", "label=io.padm.hopping-supervised"]).strip()
        active = False
        evidence["manager_term"] = dict(
            owner=term_owner, elapsed=round(time.monotonic() - term_started, 3),
            child_removed=True, state_removed=True, nat_restored=True,
            deployment_lock_released=True, stage_removed=True, session_removed=True,
            uniform_revocation_deadline_verified=False)
        _, uninstalling = invoke("dockerPortHoppingSupervisorStart", "entry-hy2", "30000",
                                 "30001", "198.18.1.1", "2001:db8:1::1")
        active = True
        uninstall_owner = ack(uninstalling, "started")
        uninstall_manager = process_identity(uninstall_owner["manager"])
        uninstall_bash = process_identity(uninstall_owner["bash"])
        cli = node / "bin/padm-docker"
        assert cli.is_symlink()
        _, uninstall_output = invoke("dockerUninstallCommand", json_output=False)
        assert uninstall_output.strip() == (
            "Docker 控制命令已卸载；状态、配置、数据、备份和镜像均已保留")
        lifecycle_stopped(uninstall_manager, uninstall_bash)
        active = False
        assert not cli.exists() and not cli.is_symlink()
        assert (root / "config/spec.json").is_file() and (root / "bundle").is_symlink()
        invoke("dockerInstallCli", json_output=False)
        lifecycle_resume("lifecycle-uninstall-resumed")
        evidence.update(lifecycle_uninstall=True, uninstall_state_retained=True,
                        lifecycle_business_restored=True)
        _, killed = invoke("dockerPortHoppingSupervisorStart", "entry-hy2", "30000",
                           "30001", "198.18.1.1", "2001:db8:1::1")
        active = True
        kill_owner = ack(killed, "started")
        kill_manager = process_identity(kill_owner["manager"])
        kill_bash = process_identity(kill_owner["bash"])
        kill_stage = Path(kill_owner["stage"])
        kill_child = frame(killed["payload"]["running"])["child_id"]
        retained_owner = tree(session / "owner.json")
        retained_session = session.stat().st_ino
        killed_at = time.monotonic()
        signal.pidfd_send_signal(kill_manager, signal.SIGKILL)
        wait_ready(lambda: not alive(kill_manager) and not alive(kill_bash), 90)
        assert not state.exists() and not (root / "locks/deployment.lock").exists()
        assert tree(lock) == net_lock
        assert {tool: command([tool, "-w", "-t", "nat", "-S"], timeout=5)
                for tool in nat_before} == nat_before
        assert not command(docker + [
            "ps", "-aq", "--filter", "label=io.padm.hopping-supervised"]).strip()
        assert session.stat().st_ino == retained_session
        assert tree(session / "owner.json") == retained_owner
        assert json.loads((session / "owner.json").read_text()) == kill_owner
        assert set(root.glob(".hopping-guarded.*")) == stages | {kill_stage}
        assert (kill_stage / "cid").read_text().strip() == kill_child
        assert (kill_stage / "supervised.json").is_file()
        retained_stage = tree(kill_stage)
        admission(False)
        assert tree(kill_stage) == retained_stage and tree(session / "owner.json") == retained_owner
        assert not (root / "locks/deployment.lock").exists()
        # SIGKILL 后旧 active JSON 只作失败证据，不能授权查询、停止或新一代接管。
        for function, arguments in (
            ("dockerPortHoppingSupervisorStatus", ()),
            ("dockerPortHoppingSupervisorStop", ()),
            ("dockerLifecycleCommand", ("restart",)),
            ("dockerLifecycleCommand", ("down",)),
            ("dockerUninstallCommand", ()),
            ("dockerPortHoppingSupervisorStart",
             ("entry-hy2", "30000", "30001", "198.18.1.1", "2001:db8:1::1")),
        ):
            invoke(function, *arguments, accepted=False)
            assert session.stat().st_ino == retained_session
            assert tree(session / "owner.json") == retained_owner and kill_stage.is_dir()
            assert not state.exists() and not (root / "locks/deployment.lock").exists()
        evidence["manager_kill"] = dict(
            owner=kill_owner, elapsed=round(time.monotonic() - killed_at, 3),
            child_removed=True, state_removed=True, nat_restored=True,
            deployment_lock_released=True, session_retained=True, stage_retained=True,
            stale_status_stop_start_refused=True, automatic_recovery_verified=False,
            uniform_revocation_deadline_verified=False)
        active = False
        failed_owner_retained = True
        return evidence
    except BaseException as error:
        primary_error = error
        evidence.update(failed=True, error=repr(error))
        raise
    finally:
        if primary_error or failed_owner_retained:
            try:
                evidence["calls"] = calls
                if session.exists():
                    for path in session.iterdir():
                        if path.is_file():
                            shutil.copyfile(path, work / (
                                "independent-supervisor-" + path.name + ".log"))
                for stage in set(root.glob(".hopping-guarded.*")) - stages:
                    for name in ("child.log", "supervised.json"):
                        path = stage / name
                        if path.is_file():
                            shutil.copyfile(path, work / (
                                "independent-supervisor-" + stage.name + "-" + name + ".log"))
                evidence["remaining_state"] = state.read_text() if state.exists() else None
                (work / "independent-supervisor-evidence.log").write_text(
                    json.dumps(evidence, sort_keys=True))
            except BaseException as error:
                if primary_error:
                    primary_error.add_note("独立监督证据保存失败: " + repr(error))
                else:
                    raise
        try:
            if active or (session.exists() and not failed_owner_retained):
                try:
                    invoke("dockerPortHoppingSupervisorStop")
                except BaseException as error:
                    if primary_error:
                        primary_error.add_note("独立监督停止失败: " + repr(error))
                    else:
                        raise
        finally:
            for descriptor in descriptors:
                os.close(descriptor)
            if cron is not None:
                stop(cron)


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
    namespace_keepers = []
    started = time.monotonic()
    try:
        # Windows 归档不保留入口权限，仅规范容器私有源码快照，字节保持不变。
        entrypoint = ROOT / "install-docker.sh"
        entrypoint_bytes = entrypoint.read_bytes()
        entrypoint.chmod(0o750)
        assert entrypoint.read_bytes() == entrypoint_bytes
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
            configured["port_hopping"] = dict(
                listener_id="entry-hy2", range_start=30000, range_end=30001,
                ipv4="198.18.1.1", ipv6="2001:db8:1::1")
            spec.write_text(json.dumps(configured))
            # 生成材料与 bind 源均属于本次私有节点，保持完整生产 Compose。
            command(["env", "PADM_DOCKER_INSTALL_DIR=" + str(root),
                     "PADM_DOCKER_BIN_DIR=" + str(node / "bin"),
                     "bash", "-Eeuo", "pipefail", "-c", """
. "$1"
dockerInitializeStateRoot
dockerInstallBundle "$(dirname "$1")" ffffffffffffffffffffffffffffffffffffffff
dockerInstallCli
dockerGenerateCompose "$2/config/spec.json" "$2/compose.json" "$2"
: >"$2/images.env"
dockerGenerateImagesEnv "$2/config/spec.json" "$2/images.env" "$2"
dockerGenerateDeployment "$2/config/spec.json" "$2/deployment.json"
dockerEnsureRuntimeDataPermissions
""", "test", str(ROOT / "install-docker.sh"), str(root)])
            clients = namespaces()
            # 持续会话验收超过原 120 秒，保留现有 netns 而不重建网络夹具。
            for index, client in enumerate(clients):
                keeper = subprocess.Popen(["nsenter", "--target", str(client.pid),
                                           "--net", "--", "sleep", "600"])
                namespace_keepers.append(keeper)
                wait_ready(lambda: Path(f"/proc/{keeper.pid}/ns/net").readlink() ==
                           Path(f"/proc/{client.pid}/ns/net").readlink())
                clients[index] = keeper
                stop(client)
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
            if os.environ.get("PADM_DOCKER_HOPPING_AUTO_ONLY") == "1":
                automatic = automatic_hopping(node, work, root, docker, enter, old_password)
                print("docker-port-hopping-auto-real-snapshot=" + json.dumps(dict(
                    automatic_hopping=automatic,
                    elapsed=round(time.monotonic() - started, 3)), sort_keys=True))
                return
            if os.environ.get("PADM_DOCKER_HOPPING_CHANGE_ONLY") == "1":
                # 复用真实节点与全部生命周期断言，省去已验的配置漂移和额度前置。
                nat_before = {tool: command([tool, "-w", "-t", "nat", "-S"], timeout=5)
                              for tool in ("iptables", "ip6tables")}
                independent = independent_supervisor(
                    node, work, root, docker, net_image["Id"], nat_before, enter,
                    old_password, new_password)
                print("docker-port-hopping-change-real-snapshot=" + json.dumps(dict(
                    independent_supervisor=independent,
                    elapsed=round(time.monotonic() - started, 3)), sort_keys=True))
                return
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
            # 当前持锁 Bash 逐门授权；有限 closed 后必须恢复双族 NAT 与 state。
            result = command(["env", "PADM_DOCKER_INSTALL_DIR=" + str(root),
                              "DOCKER_HOST=" + docker[-1], "bash", "-Eeuo", "pipefail", "-c", """
. "$1"
dockerAcquireDeploymentLock
trap dockerReleaseDeploymentLock EXIT
dockerPortHoppingTargetGuarded entry-hy2 30000 30001 198.18.1.1 2001:db8:1::1
""", "test", str(ROOT / "install-docker.sh")], timeout=150)
            guarded_parent = json.loads(result)
            closed = guarded_parent["guarded_closed"]
            assert set(closed) == {"v", "phase", "nonce", "child_id", "request_sha256"}
            assert type(closed["v"]) is int and closed["v"] == 1 and closed["phase"] == "closed"
            assert all(re.fullmatch(r"[a-f0-9]{64}", closed[key])
                       for key in ("nonce", "child_id", "request_sha256"))
            assert guarded_parent["enabled_accounts"] == 1
            assert guarded_parent["container_id"] != quota_after["container_id"]
            assert not command(docker + ["ps", "-aq", "--filter",
                                        "label=io.padm.hopping-guarded"]).strip()
            assert not list(root.glob(".hopping-guarded.*"))
            assert not jumpstate.exists()
            assert {tool: command([tool, "-w", "-t", "nat", "-S"])
                    for tool in nat_before} == nat_before
            assert lock.lstat().st_ino == lock_metadata.st_ino and lock.read_bytes() == b""
            authentication(node, root, enter, "guarded-parent-closed", new_password,
                           alice_password, "old")
            supervised = supervised_session(node, work, root, docker, net_image["Id"],
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
            assert recovered["container_id"] != supervised["initial"]["target"]["container_id"]
            assert recovered["enabled_accounts"] == 1
            accumulated_after = json.loads(state.read_text())["accounts"][alice]
            assert (accumulated_after["upload"] + accumulated_after["download"] >=
                    accumulated["upload"] + accumulated["download"])
            authentication(node, root, enter, "quota-recovered", new_password, alice_password, "old")
            # 绑定漂移会替换 live inode，放在依赖原启动版本的故障恢复验收之后。
            supervised_drift = supervised_session(
                node, work, root, docker, net_image["Id"], nat_before, enter,
                new_password, alice_password, drift=True)
            # 外部替换后的 live inode 必须由新 StartedAt 重新加载，沿用真实重启见证。
            drift_target = supervised_drift["initial"]["target"]
            restart_witness(root, docker, compose, drift_target["container_id"], drift_target)
            # 独立监督最后保留 SIGKILL 证据，后续生产取锁必须拒绝。
            independent = independent_supervisor(
                node, work, root, docker, net_image["Id"], nat_before, enter,
                new_password, alice_password)
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
            guarded_parent_lock_gates_verified=True, guarded_parent_closed=closed,
            guarded_parent_child_removed=True, guarded_parent_nat_restored=True,
            guarded_parent_state_removed=True,
            supervised_session=supervised, supervised_binding_drift=supervised_drift,
            independent_supervisor=independent,
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
            for keeper in namespace_keepers:
                stop(keeper)
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
