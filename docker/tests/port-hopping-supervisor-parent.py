#!/usr/bin/env python3
import json
import os
from pathlib import Path
import runpy
import signal
import socket
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace


SCRIPT = Path(__file__).resolve()
ROOT = SCRIPT.parents[2]
HELPER = ROOT / "docker/lib/port-hopping-supervisor.py"
MODULE = runpy.run_path(str(HELPER))
canonical = MODULE["canonical"]
digest = MODULE["digest"]
FRAME_LIMIT = MODULE["FRAME_LIMIT"]

def file_identity(path):
    metadata = path.lstat()
    # 解析链接或读内容可能更新 atime，仍严格保留 inode、权限及写入时间。
    return (*MODULE["path_identity"](metadata), metadata.st_size,
            metadata.st_mtime_ns, metadata.st_ctime_ns)


def init_barrier(phase):
    if os.environ.get("TEST_INIT_PHASE") != phase:
        return
    prefix = Path(os.environ["TEST_INIT_BARRIER"])
    ready = prefix.with_suffix(".ready")
    if ready.exists():
        return
    ready.write_text(str(os.getpid()) + "\n")
    deadline = time.monotonic() + 15
    while not prefix.with_suffix(".release").exists():
        assert time.monotonic() < deadline, ("初始化阻断未放行", phase)
        time.sleep(0.01)


def initialization_wrapper(arguments):
    namespace = MODULE["service"].__globals__
    namespace["__file__"] = str(SCRIPT)
    operation = arguments[0]
    prefix = Path(os.environ["TEST_INIT_BARRIER"])
    native_signal = signal.signal

    def tracked_signal(number, handler):
        if number in {signal.SIGINT, signal.SIGTERM} and callable(handler):
            original_handler = handler
            def received(signum, frame):
                Path(str(prefix) + f".caught-{os.getpid()}").touch()
                return original_handler(signum, frame)
            handler = received
        return native_signal(number, handler)

    signal.signal = tracked_signal
    if operation == "_service":
        native_challenge = namespace["challenge"]
        native_send = namespace["send"]
        native_popen = subprocess.Popen
        native_pin = namespace["pin"]
        native_write_owner = MODULE["Directory"].write_owner
        native_read_owner = MODULE["Directory"].read_owner
        native_cleanup = MODULE["Directory"].cleanup
        native_socket = socket.socket
        clock_shift = [0]
        native_monotonic = time.monotonic
        phase = os.environ["TEST_INIT_PHASE"]
        if phase.startswith("deadline-"):
            # 只推进本次服务的时钟；预算保持生产值，边界等待不用真实耗时。
            namespace["time"] = SimpleNamespace(
                monotonic=lambda: native_monotonic() + clock_shift[0])
        if phase == "deadline-stop":
            namespace["STOP_TIMEOUT"] = 0.05

        def challenged(*args, **kwargs):
            init_barrier("hello")
            return native_challenge(*args, **kwargs)

        def sent(peer, value):
            result = native_send(peer, value)
            if value.get("phase") == "challenge":
                init_barrier("commit")
            elif phase == "deadline-started-ack" and value.get("phase") == "continue":
                clock_shift[0] = MODULE["START_TIMEOUT"] + 1
            return result

        def created(*args, **kwargs):
            process = native_popen(*args, **kwargs)
            command = args[0]
            if len(command) > 3 and command[3] in {
                    "padm-hopping-owner", "padm-hopping-reservation"}:
                with (prefix.parent / "init-children").open("a") as stream:
                    stream.write(str(process.pid) + "\n")
                if command[3] == "padm-hopping-owner":
                    (prefix.parent / "init-owned-pid").write_text(str(process.pid) + "\n")
                    init_barrier("launch-created")
            return process

        def pinned(expected):
            recorded = prefix.parent / "init-owned-pid"
            owned = recorded.exists() and expected["pid"] == int(recorded.read_text())
            if owned and os.environ.get("TEST_INIT_PHASE") == "launch-pin-failed":
                init_barrier("launch-pin-failed")
                raise MODULE["Failure"]("测试 pidfd 绑定失败")
            descriptor = native_pin(expected)
            if owned:
                init_barrier("launch-pinned")
            return descriptor

        def written(directory, owner):
            result = native_write_owner(directory, owner)
            if owner["stage"] is not None:
                if phase == "deadline-ready":
                    clock_shift[0] = MODULE["START_TIMEOUT"] + 1
                elif phase == "deadline-started":
                    clock_shift[0] = MODULE["START_TIMEOUT"] + (
                        1 if owner["state"] == "active" else -1)
            elif owner["bash"] is None and (Path(directory.root) / "fixture-launches").exists():
                if phase in {"deadline-restart", "deadline-update", "deadline-rollback"}:
                    clock_shift[0] = (MODULE["START_TIMEOUT"] if phase == "deadline-restart"
                                      else MODULE["CHANGE_TIMEOUT"]) + 1
            if owner["bash"] is None:
                init_barrier("owner-written")
            elif owner["stage"] is not None:
                init_barrier("ready" if owner["state"] == "starting" else "started")
            return result

        def read(directory):
            owner = native_read_owner(directory)
            launches = Path(directory.root) / "fixture-launches"
            if (phase == "deadline-restart-gate" and launches.exists() and
                    len(launches.read_text().splitlines()) == 2 and owner["stage"] is None):
                clock_shift[0] = MODULE["START_TIMEOUT"] + 1
            return owner

        def cleaned(*args):
            result = native_cleanup(*args)
            if phase == "deadline-stop-cleanup":
                clock_shift[0] = MODULE["STOP_TIMEOUT"] + 1
            return result

        class InitializedSocket(native_socket):
            def bind(self, address):
                result = super().bind(address)
                if isinstance(address, str) and address.endswith("/control.sock"):
                    init_barrier("socket-bound")
                return result

        namespace["challenge"], namespace["send"], namespace["pin"] = challenged, sent, pinned
        MODULE["Directory"].write_owner = written
        MODULE["Directory"].read_owner = read
        MODULE["Directory"].cleanup = cleaned
        subprocess.Popen, socket.socket = created, InitializedSocket
    elif operation == "_reserve":
        native_session = MODULE["Directory"].session
        native_unlink, native_rmdir = os.unlink, os.rmdir
        native_check_signal = namespace["check_signal"]

        def checked(pending):
            caller = sys._getframe(1)
            directory = caller.f_locals.get("directory")
            if caller.f_code.co_name == "reserve" and directory is not None and directory.fd is None:
                init_barrier("marker-before")
            return native_check_signal(pending)

        def reserved(directory, create=False):
            result = native_session(directory, create)
            if create:
                init_barrier("marker-after")
            return result

        def unlinked(path, *args, **kwargs):
            result = native_unlink(path, *args, **kwargs)
            if path == "pid":
                init_barrier("pid-unlinked")
            return result

        def removed(path, *args, **kwargs):
            result = native_rmdir(path, *args, **kwargs)
            if path == "deployment.lock":
                init_barrier("lock-released")
            return result

        MODULE["Directory"].session = reserved
        os.unlink, os.rmdir = unlinked, removed
        namespace["check_signal"] = checked
    try:
        namespace["main"](arguments)
    except (MODULE["Failure"], ValueError, KeyError, TypeError, UnicodeError, OSError) as error:
        print("跳跃独立监督拒绝: " + str(error), file=sys.stderr)
        raise SystemExit(1)


DEPLOYMENT_BODY = r'''
source "$1"
shift
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { :; }
dockerDeploymentState() { printf 'installed\n'; }
dockerAssertInstallAllowed() { :; }
dockerPrepareInstallSource() { :; }
trap dockerReleaseDeploymentLock EXIT
if [[ -n "${TEST_GATE_CASE:-}" ]]; then
    mkdir() {
        local status=0 target="${@: -1}"
        command mkdir "$@" || status=$?
        if [[ "${target}" == "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" &&
            ( "${TEST_GATE_CASE}" == acquired && "${status}" == 0 ||
              "${TEST_GATE_CASE}" == waiting && "${status}" != 0 ) ]]; then
            command mkdir "${PADM_DOCKER_INSTALL_DIR}/data/net/.hopping-supervisor"
        fi
        return "${status}"
    }
fi
if [[ "${TEST_LIFECYCLE:-}" == true ]]; then
    dockerComposeFile() { printf '%s/compose.json\n' "$PADM_DOCKER_INSTALL_DIR"; }
    dockerTrafficBeforeChange() { printf 'traffic\n' >>"$PADM_DOCKER_INSTALL_DIR/actions"; }
    dockerRenewalScheduleRemove() { printf 'renewal\n' >>"$PADM_DOCKER_INSTALL_DIR/actions"; }
    dockerGeoScheduleRemove() { printf 'geo\n' >>"$PADM_DOCKER_INSTALL_DIR/actions"; }
    dockerControlLogScheduleRemove() { printf 'log\n' >>"$PADM_DOCKER_INSTALL_DIR/actions"; }
    dockerControlSyncScheduleRemove() { printf 'sync\n' >>"$PADM_DOCKER_INSTALL_DIR/actions"; }
    dockerTrafficScheduleRemove() { printf 'schedule\n' >>"$PADM_DOCKER_INSTALL_DIR/actions"; }
    dockerRemoveCli() { printf 'cli\n' >>"$PADM_DOCKER_INSTALL_DIR/actions"; }
    dockerComposeRun() {
        [[ "$#" -eq 1 && "$1" == down &&
            ! -e "$PADM_DOCKER_INSTALL_DIR/data/net/.hopping-supervisor" &&
            ! -e "$PADM_DOCKER_INSTALL_DIR/data/net/fixture-running" &&
            -d "$DOCKER_DEPLOYMENT_LOCK_DIR" ]] || return 1
        printf 'compose:down\n' >>"$PADM_DOCKER_INSTALL_DIR/actions"
    }
fi
"$@"
'''


def deployment_command(root, function, *arguments, accepted=False, boundary="",
                       lifecycle=False, usage=False):
    result = subprocess.run([
        "bash", "-Eeuo", "pipefail", "-c", DEPLOYMENT_BODY, "test",
        str(ROOT / "install-docker.sh"), function, *arguments],
        env=dict(os.environ, PADM_DOCKER_INSTALL_DIR=str(root), PADM_DOCKER_LOCK_TIMEOUT="30",
                 TEST_GATE_CASE=boundary, TEST_LIFECYCLE="true" if lifecycle else ""),
        capture_output=True, timeout=5)
    assert result.returncode == (2 if usage else 0 if accepted else 12), (
        function, result.returncode, result.stdout, result.stderr)
    if accepted and function == "dockerUninstallCommand":
        assert result.stdout.decode().strip() == "Docker 控制命令已卸载；状态、配置、数据、备份和镜像均已保留"
    else:
        assert not result.stdout
    if accepted:
        assert not result.stderr
    elif not usage:
        assert any(message.encode() in result.stderr for message in (
            "跳跃监督会话存在或停止未核验", "跳跃监督重启未确认",
            "跳跃监督会话未能通过原控制通道停止", "跳跃独立监督拒绝")), result.stderr


def deployment_gate_cases(base):
    count = 0
    commands = (
        ("dockerLifecycleCommand", ("up",)), ("dockerLifecycleCommand", ("restart",)),
        ("dockerLifecycleCommand", ("down",)), ("dockerUpdateCommand", ()),
        ("dockerRollbackCommand", ()), ("dockerUninstallCommand", ()),
        ("dockerInstallCommand", ("--source", str(ROOT), "--ref", "f" * 40, "--no-menu")),
    )
    for kind in ("directory", "file", "dangling-link"):
        root = base / kind
        (root / "data/net").mkdir(parents=True, mode=0o700)
        root.chmod(0o750)
        session = root / "data/net/.hopping-supervisor"
        if kind == "directory":
            session.mkdir(mode=0o700)
            (session / "owner.json").write_text("unverified owner\n")
        elif kind == "file":
            session.write_text("unknown session\n")
        else:
            session.symlink_to(root / "missing")
        before = file_identity(session)
        for function, arguments in commands:
            deployment_command(root, function, *arguments)
            assert file_identity(session) == before
            assert not (root / "locks").exists(), "拒绝前创建了部署锁目录"
            count += 1
        if kind == "directory":
            assert (session / "owner.json").read_text() == "unverified owner\n"
        elif kind == "file":
            assert session.read_text() == "unknown session\n"
        else:
            assert session.is_symlink() and not session.exists()
    for boundary in ("waiting", "acquired"):
        root = base / boundary
        (root / "data/net").mkdir(parents=True, mode=0o700)
        root.chmod(0o750)
        lock = root / "locks/deployment.lock"
        (root / "locks").mkdir(mode=0o750)
        if boundary == "waiting":
            lock.mkdir(mode=0o750)
            # 死 PID 也不能触发残留清理；会话恰在失败 mkdir 后出现。
            (lock / "pid").write_text("2147483647\n")
            before = file_identity(lock), file_identity(lock / "pid")
        deployment_command(root, "dockerLockInstalledDeployment", boundary=boundary)
        if boundary == "waiting":
            assert (file_identity(lock), file_identity(lock / "pid")) == before
            assert (lock / "pid").read_text() == "2147483647\n"
        else:
            assert not lock.exists(), "竞争拒绝后没有释放本次取得的锁"
        assert (root / "data/net/.hopping-supervisor").is_dir()
        count += 1
    root = base / "absent"
    (root / "data/net").mkdir(parents=True, mode=0o700)
    root.chmod(0o750)
    deployment_command(root, "dockerLockInstalledDeployment", accepted=True)
    assert not (root / "locks/deployment.lock").exists()
    return count + 1


def rollback_scope_cases(base):
    root = base / "rollback-scope"
    (root / "config").mkdir(parents=True)
    spec = {"schema_version": 3, "core": {"type": "sing-box", "secondary_type": None,
            "protocols": [{"listener_id": "hy2-main", "id": 3, "public_port": 27443,
                           "address_families": ["ipv4", "ipv6"], "hy2": {"domain": "fixture.test"}}]},
            "host_integrations": []}
    (root / "config/spec.json").write_text(json.dumps(spec))
    backup = root / "backup.json"
    body = r'''
source "$1"
dockerRollbackCommand() { dockerPortHoppingSupervisorChangeBundleCheck "$1" "$2"; }
dockerPortHoppingTargetSupervisedOwned() {
    local -a targets=(hy2-main)
    dockerRollbackCommand "$@"
}
dockerPortHoppingTargetSupervisedOwned "$2" "$3"
'''
    for case in ("valid", "multi", "schema", "port"):
        candidate = json.loads(json.dumps(spec))
        if case == "multi":
            candidate["core"]["protocols"].append(
                dict(candidate["core"]["protocols"][0], listener_id="other"))
        elif case == "schema":
            candidate["schema_version"] = 2
        elif case == "port":
            candidate["core"]["protocols"][0]["public_port"] += 1
        backup.write_text(json.dumps(candidate))
        result = subprocess.run(
            ["bash", "-Eeuo", "pipefail", "-c", body, "test", str(ROOT / "install-docker.sh"),
             str(ROOT), str(backup)], env=dict(os.environ, PADM_DOCKER_INSTALL_DIR=str(root)),
            capture_output=True, timeout=5)
        assert (result.returncode == 0) == (case == "valid"), (case, result.stderr)
        assert json.loads((root / "config/spec.json").read_text()) == spec
    saved = root / "backup"
    (saved / "config").mkdir(parents=True)
    (saved / "config/spec.json").write_text(json.dumps(spec))
    body = r'''
source "$1"
dockerHostPreflight() { :; }
dockerLockInstalledDeployment() { :; }
dockerComposeFile() { printf '%s/compose.json\n' "$PADM_DOCKER_INSTALL_DIR"; }
dockerLatestUpdateBackup() { printf '%s/backup\n' "$PADM_DOCKER_INSTALL_DIR"; }
dockerCurrentBundlePath() { printf '%s\n' "$TEST_CURRENT_BUNDLE"; }
dockerControlSyncRollbackCheck() { printf 'checked\n'; return 1; }
dockerPortHoppingTargetSupervisedOwned() {
    local -a targets=(hy2-main)
    dockerRollbackCommand
}
dockerPortHoppingTargetSupervisedOwned
'''
    result = subprocess.run(
        ["bash", "-Eeuo", "pipefail", "-c", body, "test", str(ROOT / "install-docker.sh")],
        env=dict(os.environ, PADM_DOCKER_INSTALL_DIR=str(root), TEST_CURRENT_BUNDLE=str(ROOT)),
        capture_output=True, timeout=5)
    assert result.returncode == 15 and result.stdout == b"checked\n", result.stderr
    assert not (saved / "bundle.target").exists()
    return 5


def fake_owned(fd, root, action="", arguments=None):
    peer = socket.socket(fileno=fd)
    installation = Path(root)
    lock = installation / "locks/deployment.lock"
    lock.mkdir(parents=True, mode=0o750)
    (lock / "pid").write_text(str(os.getpid()) + "\n")
    (lock / "pid").chmod(0o640)
    with (installation / "fixture-launches").open("a") as stream:
        stream.write(str(os.getpid()) + "\n")
    stage = installation / f".hopping-guarded.fixture.{os.getpid()}"
    child_id = f"{os.getpid():064x}"
    token = MODULE["identity"](os.getpid())
    marker = installation / "data/net/fixture-running"
    stopping = [False]
    signal.signal(signal.SIGTERM, lambda *_: stopping.__setitem__(0, True))
    value = {"target": {"listener_id": "hy2-main", "container_id": "d" * 64,
        "image_id": "sha256:" + "e" * 64,
        "started_at": f"2026-10-14T00:00:00.{os.getpid():09d}Z",
        "range_start": 36561, "range_end": 36562, "target_port": 27443,
        "ipv4": "198.18.1.1", "ipv6": "2001:db8:1::1"}, "running": {
        "v": 1, "phase": "running", "nonce": "2" * 64, "child_id": child_id,
        "request_sha256": "c" * 64, "seq": 2,
    }, "child": {"Id": child_id}, "directory": [["/", 1, 2, 0o755, 0, 0]],
    "stage": str(stage)}

    def gate(phase, payload=None):
        event = {"v": 1, "phase": phase, "nonce": os.urandom(32).hex(),
                 "payload": value if payload is None else payload}
        MODULE["send"](peer, event)
        try:
            response = MODULE["receive"](peer)
        except (MODULE["Failure"], OSError):
            if not os.environ.get("TEST_INIT_PHASE"):
                raise
            stopping[0] = True
            return
        if response == {"v": 1, "phase": "stop", "nonce": event["nonce"]} and os.environ.get(
                "TEST_INIT_PHASE"):
            stopping[0] = True
            return
        assert response == {"v": 1, "phase": "commit" if phase in {
            "ready", "restart", "update", "rollback", "changed"} else "continue",
                            "nonce": event["nonce"]} or stopping[0], response

    if action:
        current = subprocess.run([
            "bash", "-Eeuo", "pipefail", "-c", MODULE["LOCK_BODY"], "test",
            str(ROOT / "install-docker.sh"), str(installation), str(os.getpid())],
            capture_output=True, check=True)
        original = json.loads(current.stdout)
        if (installation / "invalid-restart-gate").exists() or (
                installation / "invalid-update-gate").exists():
            original = []
        gate(action, {"bash_pid": os.getpid(), "lock": original})
        if action in {"update", "rollback"}:
            (installation / "fixture-change").write_text(json.dumps([action, arguments]))
            changed = {"status": 11 if (installation / "change-failed").exists() else 0}
            if (installation / "invalid-changed").exists():
                changed["status"] = True
            gate("changed", changed)
            value["target"]["container_id"] = f"{os.getpid():064x}"
            value["target"]["image_id"] = "sha256:" + f"{os.getpid():064x}"
    # 只有新写门通过后才模拟核心与规则启用。
    stage.mkdir(mode=0o700)
    marker.write_text(str(os.getpid()))
    gate("ready")
    if not (stopping[0] and os.environ.get("TEST_INIT_PHASE")):
        gate("started")
    while not stopping[0]:
        time.sleep(0.1)
        if stopping[0]:
            break
        value["running"].update(seq=value["running"]["seq"] + 1, nonce=os.urandom(32).hex())
        gate("running")
    marker.unlink()
    stage.rmdir()
    if os.environ.get("TEST_INIT_PHASE") == "deadline-stop":
        # 已完成现场清理，故意卡住最终回执以验证监督者会回收残留子进程。
        time.sleep(10)
    try:
        MODULE["send"](peer, {"v": 1, "phase": "cleaned", "nonce": os.urandom(32).hex(), "payload": {
            "target": value["target"], "child_id": value["child"]["Id"], "stage": str(stage)}})
    except OSError:
        if not os.environ.get("TEST_INIT_PHASE"):
            raise
    (lock / "pid").unlink()
    lock.rmdir()
    finished = {"status": 143, "lock_released": True}
    if (installation / "invalid-finished").exists():
        finished["lock_released"] = 1
    try:
        MODULE["send"](peer, {"v": 1, "phase": "finished", "nonce": os.urandom(32).hex(),
                             "payload": finished})
    except OSError:
        if not os.environ.get("TEST_INIT_PHASE"):
            raise
    assert MODULE["identity"](os.getpid()) == token
    raise SystemExit(143)


def reservation_cases(base, entrypoint):
    count = 0
    installation = base / "reservation-wait"
    (installation / "data/net").mkdir(parents=True, mode=0o700)
    saved_values = ["hy2-main", "36561", "36562", "198.18.1.1", "2001:db8:1::1"]
    (installation / "saved-arguments.json").write_text(json.dumps(
        ["stale-entry", "35000", "35001", "198.18.1.2", "2001:db8:1::2"]))
    holder = subprocess.Popen([
        "bash", "-Eeuo", "pipefail", "-c",
        'source "$1"; trap dockerReleaseDeploymentLock EXIT; '
        'dockerAcquireDeploymentLock; printf "locked\\n"; read -r release; [[ "$release" == release ]]; '
        'printf "%s\\n" "$TEST_SAVED_VALUES" >"$PADM_DOCKER_INSTALL_DIR/saved-arguments.json"',
        "test", str(ROOT / "install-docker.sh")],
        env=dict(os.environ, PADM_DOCKER_INSTALL_DIR=str(installation),
                 TEST_SAVED_VALUES=json.dumps(saved_values)),
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    services, peers = [], []
    try:
        assert holder.stdout.readline() == b"locked\n"
        lock = installation / "locks/deployment.lock"
        before = file_identity(lock), file_identity(lock / "pid"), (lock / "pid").read_bytes()
        for index in range(2):
            caller, peer = socket.socketpair()
            waited = installation / f"reservation-waited-{index}"
            manager = subprocess.Popen([
                sys.executable, str(HELPER), "_service", str(peer.fileno()),
                str(installation), str(entrypoint)], pass_fds=(peer.fileno(),),
                env=dict(os.environ, TEST_RESERVATION_WAIT=str(waited)),
                start_new_session=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            peer.close()
            services.append(manager)
            peers.append(caller)
            MODULE["send"](caller, {"v": 1, "phase": "hello", "action": "start",
                                    "client_nonce": "e" * 64})
            proof = MODULE["receive"](caller)
            MODULE["send"](caller, {"v": 1, "phase": "commit", "action": "start",
                                    "nonce": proof["nonce"], "client_nonce": "e" * 64})
            deadline = time.monotonic() + 5
            while not waited.exists():
                assert manager.poll() is None and time.monotonic() < deadline
                time.sleep(0.01)
            # 两个预约都实际进入取锁等待；普通事务完成前没有 starting 目录。
            assert not (installation / "data/net/.hopping-supervisor").exists()
            assert (file_identity(lock), file_identity(lock / "pid"),
                    (lock / "pid").read_bytes()) == before
            count += 1
        output, error = holder.communicate(b"release\n", timeout=5)
        assert holder.returncode == 0 and not output and not error
        results = []
        for caller in peers:
            try:
                result = MODULE["receive"](caller, timeout=8)
            except MODULE["Failure"]:
                results.append(None)
            else:
                assert result["phase"] == "started"
                MODULE["owner_check"](result["owner"])
                results.append(result)
        assert sum(result is not None for result in results) == 1
        winner = next(result for result in results if result is not None)
        assert (installation / "selected-arguments").read_text().splitlines() == saved_values, (
            "保存启动采用了取锁前的旧参数")
        assert MODULE["control"]("status", str(installation))["owner"] == winner["owner"]
        deployment_command(installation, "dockerLockInstalledDeployment")
        stopped = MODULE["control"]("stop", str(installation))
        assert stopped["owner"] == winner["owner"] and stopped["finished"]["lock_released"]
        assert not (installation / "data/net/.hopping-supervisor").exists()
        assert not lock.exists()
        for index, manager in enumerate(services):
            output, error = manager.communicate(timeout=8)
            assert manager.returncode == (0 if results[index] else 1) and not output
            assert (not error) == bool(results[index]), error
        count += 1
    finally:
        for caller in peers:
            caller.close()
        for manager in services:
            if manager.poll() is None:
                manager.terminate()
            manager.communicate(timeout=8)
        if holder.poll() is None:
            holder.communicate(b"release\n", timeout=5)
    installation = base / "missing-saved"
    (installation / "data/net").mkdir(parents=True, mode=0o700)
    failed = subprocess.run([
        sys.executable, str(HELPER), "start", str(installation), str(entrypoint)],
        capture_output=True, timeout=8)
    assert failed.returncode == 1 and not failed.stdout and failed.stderr
    assert not (installation / "data/net/.hopping-supervisor").exists()
    assert not (installation / "locks/deployment.lock").exists()
    count += 1
    for fault in ("changed-pid", "occupied-lock", "replaced-session"):
        installation = base / fault
        (installation / "data/net").mkdir(parents=True, mode=0o700)
        failed = subprocess.run([
            sys.executable, str(HELPER), "start", str(installation), str(entrypoint),
            "hy2-main", "36561", "36562", "198.18.1.1", "2001:db8:1::1"],
            env=dict(os.environ, TEST_RESERVATION_FAULT=fault), capture_output=True, timeout=8)
        assert failed.returncode == 1 and not failed.stdout and failed.stderr
        session = installation / "data/net/.hopping-supervisor"
        lock = installation / "locks/deployment.lock"
        assert session.is_dir() and not (session / "owner.json").exists()
        assert not (installation / "data/net/fixture-running").exists()
        if fault == "changed-pid":
            assert (lock / "pid").read_text() == "2147483647\n"
        elif fault == "occupied-lock":
            assert (lock / "foreign").is_dir() and not (lock / "pid").exists()
        else:
            assert (lock / "pid").is_file()
            assert (installation / "data/net/.hopping-supervisor.previous").is_dir()
        evidence = file_identity(session), file_identity(lock) if lock.exists() else None
        deployment_command(installation, "dockerLockInstalledDeployment")
        assert (file_identity(session), file_identity(lock) if lock.exists() else None) == evidence
        count += 1
    for phase in ("before", "after"):
        installation = base / f"reservation-kill-{phase}"
        (installation / "data/net").mkdir(parents=True, mode=0o700)
        barrier = installation / "reservation-check"
        os.mkfifo(str(barrier) + ".fifo", 0o600)
        starting = subprocess.Popen([
            sys.executable, str(HELPER), "start", str(installation), str(entrypoint),
            "hy2-main", "36561", "36562", "198.18.1.1", "2001:db8:1::1"],
            env=dict(os.environ, TEST_RESERVATION_PAUSE=str(barrier),
                     TEST_RESERVATION_PHASE=phase),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        descriptor = None
        try:
            deadline = time.monotonic() + 5
            while not Path(str(barrier) + ".ready").exists():
                assert starting.poll() is None and time.monotonic() < deadline
                time.sleep(0.01)
            session = installation / "data/net/.hopping-supervisor"
            lock = installation / "locks/deployment.lock"
            assert session.exists() == (phase == "after")
            before = file_identity(lock), file_identity(lock / "pid"), (lock / "pid").read_bytes()
            # 真正终止 exec 后的锁 owner；只读见证子进程放行后也不能创建预约。
            descriptor = MODULE["pin"](MODULE["identity"](int((lock / "pid").read_text())))
            signal.pidfd_send_signal(descriptor, signal.SIGKILL)
            assert MODULE["select"].select([descriptor], [], [], 5)[0]
            with Path(str(barrier) + ".fifo").open("w") as stream:
                stream.write("continue\n")
            output, error = starting.communicate(timeout=8)
            assert starting.returncode == 1 and not output and error
            assert (file_identity(lock), file_identity(lock / "pid"),
                    (lock / "pid").read_bytes()) == before
            deployment_command(installation, "dockerLockInstalledDeployment", accepted=phase == "before")
            if phase == "before":
                assert not session.exists() and not lock.exists()
            else:
                assert session.is_dir() and not (session / "owner.json").exists()
                assert (file_identity(lock), file_identity(lock / "pid"),
                        (lock / "pid").read_bytes()) == before
            count += 1
        finally:
            if descriptor is not None:
                os.close(descriptor)
            if starting.poll() is None:
                starting.terminate()
                starting.communicate(timeout=8)
    return count


def initialization_signal_cases(base, entrypoint):
    count = 0
    phases = ("hello", "commit", "reservation-wait", "marker-before", "marker-after",
              "pid-unlinked", "lock-released", "socket-bound", "owner-written",
              "launch-created", "launch-pin-failed", "launch-pinned", "ready", "started")
    reserved_phases = {"marker-before", "marker-after", "pid-unlinked", "lock-released"}
    for number in (signal.SIGINT, signal.SIGTERM):
        for phase in phases:
            installation = base / f"initialization-{number}-{phase}"
            net = installation / "data/net"
            net.mkdir(parents=True, mode=0o700)
            prefix = installation / "init-barrier"
            evidence = installation / "foreign-evidence"
            evidence.write_bytes(b"unrelated installation evidence\n")
            preserved = [(evidence, file_identity(evidence), evidence.read_bytes())]
            if phase not in {"ready", "started"}:
                state = net / "port-hopping.state"
                state.write_bytes(b"unverified external state\n")
                preserved.append((state, file_identity(state), state.read_bytes()))
            lock = installation / "locks/deployment.lock"
            session = net / ".hopping-supervisor"
            holder = None
            manager = None
            descriptors = []
            caller, service = socket.socketpair()
            try:
                held = None
                if phase == "reservation-wait":
                    holder = subprocess.Popen([
                        "bash", "-Eeuo", "pipefail", "-c",
                        'source "$1"; trap dockerReleaseDeploymentLock EXIT; '
                        'dockerAcquireDeploymentLock; printf "locked\\n"; read -r release; '
                        '[[ "$release" == release ]]',
                        "test", str(ROOT / "install-docker.sh")],
                        env=dict(os.environ, PADM_DOCKER_INSTALL_DIR=str(installation)),
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    assert MODULE["select"].select([holder.stdout], [], [], 5)[0]
                    assert holder.stdout.readline() == b"locked\n"
                    held = file_identity(lock), file_identity(lock / "pid"), (lock / "pid").read_bytes()
                manager = subprocess.Popen([
                    sys.executable, str(SCRIPT), "_service", str(service.fileno()),
                    str(installation), str(entrypoint), "hy2-main", "36561", "36562",
                    "198.18.1.1", "2001:db8:1::1"], pass_fds=(service.fileno(),),
                    env=dict(os.environ, TEST_INIT_PHASE=phase, TEST_INIT_BARRIER=str(prefix)),
                    start_new_session=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                service.close()
                manager_fd = MODULE["pin"](MODULE["identity"](manager.pid))
                descriptors.append(manager_fd)
                if phase != "hello":
                    MODULE["send"](caller, {"v": 1, "phase": "hello", "action": "start",
                                            "client_nonce": "e" * 64})
                    proof = MODULE["receive"](caller, timeout=5)
                    if phase != "commit":
                        MODULE["send"](caller, {"v": 1, "phase": "commit", "action": "start",
                                                "nonce": proof["nonce"], "client_nonce": "e" * 64})
                deadline = time.monotonic() + 5
                while not prefix.with_suffix(".ready").exists():
                    assert manager.poll() is None and time.monotonic() < deadline, (
                        phase, manager.poll())
                    time.sleep(0.01)
                blocked_pid = int(prefix.with_suffix(".ready").read_text())
                blocked_fd = None
                if blocked_pid != manager.pid:
                    blocked_fd = MODULE["pin"](MODULE["identity"](blocked_pid))
                    descriptors.append(blocked_fd)
                children = installation / "init-children"
                for pid in set(map(int, children.read_text().splitlines())) if children.exists() else ():
                    if pid != blocked_pid:
                        try:
                            descriptors.append(MODULE["pin"](MODULE["identity"](pid)))
                        except (FileNotFoundError, MODULE["Failure"]):
                            pass
                session_id = MODULE["path_identity"](session.stat()) if session.exists() else None
                owner_path = session / "owner.json"
                original_owner = owner_path.read_bytes() if owner_path.exists() else None
                if phase in {"hello", "commit", "reservation-wait", "marker-before"}:
                    assert not session.exists()
                else:
                    assert session.is_dir()
                if phase == "reservation-wait":
                    assert (file_identity(lock), file_identity(lock / "pid"),
                            (lock / "pid").read_bytes()) == held
                if phase in {"marker-before", "marker-after"}:
                    assert (lock / "pid").read_text() == str(blocked_pid) + "\n"
                if phase == "pid-unlinked":
                    assert lock.is_dir() and not (lock / "pid").exists()
                if phase in {"lock-released", "socket-bound", "owner-written"}:
                    assert not lock.exists()
                if phase == "socket-bound":
                    assert (session / "control.sock").exists() and not owner_path.exists()
                if phase == "owner-written":
                    assert set(os.listdir(session)) == {"control.sock", "service.log", "owner.json"}
                    assert json.loads(original_owner)["bash"] is None
                if phase in {"ready", "started"}:
                    bound = json.loads(original_owner)
                    assert bound["stage"] is not None
                    assert bound["state"] == ("starting" if phase == "ready" else "active")
                    assert (net / "fixture-running").exists()
                # 先确认信号进入本代 handler，再放行阻断；预约 child 也必须收到终止或已退出。
                signal.pidfd_send_signal(manager_fd, number)
                deadline = time.monotonic() + 5
                caught = Path(str(prefix) + f".caught-{manager.pid}")
                while not caught.exists():
                    assert not MODULE["select"].select([manager_fd], [], [], 0)[0]
                    assert time.monotonic() < deadline, ("manager 未处理信号", phase, number)
                    time.sleep(0.01)
                if phase in reserved_phases:
                    child_caught = Path(str(prefix) + f".caught-{blocked_pid}")
                    while not child_caught.exists() and not MODULE["select"].select(
                            [blocked_fd], [], [], 0)[0]:
                        assert time.monotonic() < deadline, ("预约 child 未终止", phase, number)
                        time.sleep(0.01)
                prefix.with_suffix(".release").touch()
                output, error = manager.communicate(timeout=10)
                assert manager.returncode in {0, 1} and not output, (
                    phase, number, manager.returncode, output, error)
                for descriptor in descriptors:
                    assert MODULE["select"].select([descriptor], [], [], 5)[0], (
                        "初始化中断遗留真实子进程", phase, number)
                assert not (net / "fixture-running").exists(), (phase, number)
                assert not list(installation.glob(".hopping-guarded.fixture.*")), (phase, number)
                for path, identity, content in preserved:
                    assert (file_identity(path), path.read_bytes()) == (identity, content), (
                        "初始化中断更改外来证据", phase, number, path)
                if phase in {"hello", "commit"}:
                    assert not session.exists() and not (installation / "locks").exists()
                elif phase == "reservation-wait":
                    assert (file_identity(lock), file_identity(lock / "pid"),
                            (lock / "pid").read_bytes()) == held
                    output, error = holder.communicate(b"release\n", timeout=5)
                    assert holder.returncode == 0 and not output and not error
                    assert not lock.exists() and not session.exists(), "释放旧锁后孤儿预约继续写入"
                elif phase == "marker-before":
                    assert not session.exists()
                elif session.exists():
                    assert MODULE["path_identity"](session.stat()) == session_id
                    if phase in {"owner-written", "ready", "started"}:
                        assert owner_path.read_bytes() == original_owner
                    deployment_command(installation, "dockerLockInstalledDeployment")
                if phase in {"ready", "started"}:
                    assert not lock.exists()
                try:
                    frame = MODULE["receive"](caller, timeout=0.2)
                except (MODULE["Failure"], OSError):
                    pass
                else:
                    assert frame.get("phase") != "started", (
                        "信号已送达后仍确认启动", phase, number, frame)
                count += 1
            finally:
                prefix.with_suffix(".release").touch()
                caller.close()
                service.close()
                if manager is not None and manager.poll() is None:
                    manager.terminate()
                    manager.communicate(timeout=10)
                if holder is not None and holder.poll() is None:
                    holder.communicate(b"release\n", timeout=5)
                for descriptor in descriptors:
                    if not MODULE["select"].select([descriptor], [], [], 0)[0]:
                        signal.pidfd_send_signal(descriptor, signal.SIGKILL)
                        MODULE["select"].select([descriptor], [], [], 5)
                    os.close(descriptor)
    return count


def line(value):
    return canonical(value) + b"\n"


def deadline_cases():
    count = 0
    deadline = time.monotonic() + 0.05
    assert MODULE["remaining_time"](deadline) > 0
    time.sleep(0.06)
    try:
        MODULE["remaining_time"](deadline)
    except MODULE["Failure"] as error:
        assert "总时限" in str(error)
    else:
        raise AssertionError("过期监督总时限未拒绝")
    count += 1

    left, right = socket.socketpair()
    try:
        started = time.monotonic()
        try:
            MODULE["receive"](left, timeout=30, deadline=started + 0.05)
        except MODULE["Failure"] as error:
            assert "监督帧超时" in str(error)
            assert time.monotonic() - started < 0.5
        else:
            raise AssertionError("监督帧未受总时限约束")
    finally:
        left.close()
        right.close()
    count += 1

    with tempfile.TemporaryDirectory(prefix="padm-hopping-deadline.") as directory:
        pid_path = Path(directory) / "pid"
        pending = [0]
        try:
            MODULE["run_interruptible"](["touch", str(pid_path)], pending,
                                        deadline=time.monotonic() - 1)
        except MODULE["Failure"]:
            pass
        else:
            raise AssertionError("过期监督仍创建子进程")
        assert not pid_path.exists(), "过期监督子进程执行了写入"
        count += 1
        try:
            MODULE["run_interruptible"](
                ["bash", "-c", f"printf '%s\n' \"$BASHPID\" >'{pid_path}'; exec sleep 10"],
                pending, deadline=time.monotonic() + 0.05)
        except MODULE["Failure"] as error:
            assert "总时限" in str(error)
        else:
            raise AssertionError("监督子进程未受总时限约束")
        pid = int(pid_path.read_text())
        assert not Path(f"/proc/{pid}").exists(), "监督总时限后子进程未回收"
    count += 1
    return count


def service_deadline_cases(base, entrypoint):
    count = 0
    for phase in ("ready", "started", "restart", "update", "rollback", "stop",
                  "restart-gate", "started-ack", "stop-cleanup"):
        installation = base / f"deadline-{phase}"
        (installation / "data/net").mkdir(parents=True, mode=0o700)
        caller, peer = socket.socketpair()
        manager = subprocess.Popen([
            sys.executable, str(SCRIPT), "_service", str(peer.fileno()),
            str(installation), str(entrypoint), "hy2-main", "36561", "36562",
            "198.18.1.1", "2001:db8:1::1"], pass_fds=(peer.fileno(),),
            env=dict(os.environ, TEST_INIT_PHASE=f"deadline-{phase}",
                     TEST_INIT_BARRIER=str(installation / "deadline")),
            start_new_session=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        peer.close()
        try:
            if phase in {"ready", "started", "started-ack"}:
                try:
                    MODULE["client"](caller, "start")
                except (MODULE["Failure"], OSError):
                    pass
                else:
                    raise AssertionError(("时限到期后仍确认启动", phase))
            else:
                started = MODULE["client"](caller, "start")
                assert started["phase"] == "started"
                try:
                    MODULE["control"](phase.split("-")[0], str(installation))
                except (MODULE["Failure"], OSError):
                    pass
                else:
                    raise AssertionError(("时限到期后仍确认事务", phase))
            output, error = manager.communicate(timeout=5)
            assert not output and manager.returncode in {0, 1}, (phase, output, error)
            launches = (installation / "fixture-launches").read_text().splitlines()
            assert len(launches) == (2 if phase == "restart-gate" else 1), (
                "时限到期后创建了新 owner", phase, launches)
            if phase == "stop":
                # 故障夹具刻意晚于停止预算退出，单独观察其回收，不延长管理器时限。
                deadline = time.monotonic() + 1
                while any(Path(f"/proc/{pid}").exists() for pid in launches) and time.monotonic() < deadline:
                    time.sleep(0.01)
            assert all(not Path(f"/proc/{pid}").exists() for pid in launches), (phase, launches)
            assert not (installation / "data/net/fixture-running").exists()
            assert not list(installation.glob(".hopping-guarded.fixture.*"))
            session = installation / "data/net/.hopping-supervisor"
            if phase in {"ready", "started", "started-ack", "stop-cleanup"}:
                assert not session.exists() and not (installation / "locks/deployment.lock").exists()
            else:
                assert session.is_dir()
                owner = json.loads((session / "owner.json").read_text())
                assert owner["state"] == ("active" if phase == "stop" else "starting")
                deployment_command(installation, "dockerLockInstalledDeployment")
            count += 1
        finally:
            caller.close()
            if manager.poll() is None:
                manager.terminate()
                manager.communicate(timeout=5)
    return count


def receive(peer, timeout=3):
    peer.settimeout(timeout)
    raw = b""
    while not raw.endswith(b"\n"):
        byte = peer.recv(1)
        assert byte, "监督帧意外 EOF"
        raw += byte
        assert len(raw) <= FRAME_LIMIT
    return json.loads(raw[:-1])


def invoke(command, phase, payload, accepted=True, response=None):
    parent, child = socket.socketpair()
    process = subprocess.Popen(
        [sys.executable, str(HELPER), command, phase, json.dumps(payload)],
        stdin=child, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        pass_fds=(child.fileno(),), close_fds=True)
    child.close()
    try:
        frame = receive(parent)
        assert set(frame) == {"v", "phase", "nonce", "payload"}
        assert frame["v"] == 1 and frame["phase"] == phase and frame["payload"] == payload
        assert isinstance(frame["nonce"], str) and len(frame["nonce"]) == 64
        if response is not None:
            parent.sendall(line(response(frame)))
        process.wait(timeout=5)
        output, error = process.communicate(timeout=5)
        assert process.returncode == (0 if accepted else 1), (command, output, error)
        assert not output
        assert (not error) == accepted, (command, error)
        return frame
    finally:
        parent.close()
        if process.poll() is None:
            process.kill()
            process.wait()


def recovery_cases(base):
    namespace = MODULE["recover"].__globals__
    native_run = namespace["run_interruptible"]
    count = 0
    live = subprocess.Popen(
        [sys.executable, "-c", "import time; time.sleep(30)"], start_new_session=True)
    try:
        for case in ("preview", "clean", "live", "realm", "starting", "stage-hash",
                     "child", "malformed-lock", "stage-file", "owner-replaced", "stage-replaced",
                     "unknown", "busy"):
            root = base / case
            (root / "data/net").mkdir(parents=True, mode=0o700)
            root.chmod(0o750)
            (root / "locks").mkdir(mode=0o750)
            lock = root / "locks/deployment.lock"
            lock.mkdir(mode=0o750)
            original = MODULE["identity"](os.getpid())
            manager = dict(original, pid=2147483647, session_id=2147483647)
            bash = dict(original, pid=2147483646, session_id=2147483647)
            if case == "live":
                manager = MODULE["identity"](live.pid)
                bash = dict(manager)
            if case == "realm":
                manager["boot_id"] = "unknown-boot"
            (lock / "pid").write_text(str(bash["pid"]) + "\n")
            (lock / "pid").chmod(0o640)
            stage = root / ".hopping-guarded.Abc123"
            stage.mkdir(mode=0o700)
            entrypoint = base / "entrypoint.sh"
            entrypoint.write_text("dockerPortHoppingRecoveryInspect() { :; }\n")
            entrypoint.chmod(0o600)
            directory = MODULE["Directory"](str(root))
            try:
                paths = ["/", *[str(parent) for parent in reversed(root.parents) if str(parent) != "/"],
                         str(root), str(root / "data"), str(root / "data/net")]
                projection = [[path, *value] for path, value in zip(paths, directory.projection)]
                directory.session(create=True)
                lock_projection = [
                    [str(root / "locks"), *MODULE["path_identity"]((root / "locks").stat())[:5]],
                    [str(lock), *MODULE["path_identity"](lock.stat())[:5]],
                    [str(lock / "pid"), *file_identity(lock / "pid"), str(bash["pid"])],
                ]
                target = {"listener_id": "hy2-main", "startup_binding": {"lock": lock_projection}}
                if case == "malformed-lock":
                    target["startup_binding"]["lock"] = []
                audit = {"target": target, "child": {"Id": "b" * 64}, "directory": projection,
                         "stage": str(stage), "saved": {"listener_id": "hy2-main",
                         "range_start": 36561, "range_end": 36562,
                         "ipv4": "198.18.1.1", "ipv6": "2001:db8:1::1"}}
                owner = {"v": 1, "token": "a" * 64, "root": str(root), "manager": manager,
                         "bash": bash, "stage": str(stage), "stage_sha256": digest({
                             key: audit[key] for key in ("target", "child", "directory", "stage")}),
                         "state": "starting" if case == "starting" else "active"}
                if case == "stage-hash":
                    owner["stage_sha256"] = "f" * 64
                directory.write_owner(owner)
                control = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                control.bind(f"/proc/self/fd/{directory.fd}/control.sock")
                control.close()
                (root / "data/net/.hopping-supervisor/control.sock").chmod(0o600)
                (root / "data/net/.hopping-supervisor/service.log").touch(mode=0o600)
            finally:
                directory.close()
            for name, value in (("prepared.json", canonical(target)), ("cid", b"b" * 64 + b"\n"),
                                ("child.log", b""), ("supervised.json", b"{}\n")):
                (stage / name).write_bytes(value)
                (stage / name).chmod(0o600)
            if case == "stage-file":
                (stage / "prepared.json").unlink()
                (stage / "prepared.json").symlink_to(entrypoint)
            elif case == "unknown":
                (stage / "supervised.next").touch()
            elif case == "child":
                audit["child"]["Id"] = "c" * 64
            before = {str(path.relative_to(root)): file_identity(path)
                      for path in root.rglob("*")}
            calls, writes, child_exists = [], [], [True]

            def run(arguments, pending, deadline=None):
                MODULE["check_signal"](pending)
                calls.append(arguments)
                if arguments[0] == "bash":
                    if case in {"owner-replaced", "stage-replaced"} and len(calls) == 2:
                        path = (root / "data/net/.hopping-supervisor/owner.json"
                                if case == "owner-replaced" else stage / "prepared.json")
                        replacement = path.with_suffix(".replacement")
                        replacement.write_bytes(path.read_bytes())
                        replacement.chmod(0o600)
                        replacement.replace(path)
                    return subprocess.CompletedProcess(arguments, 0, canonical(audit), b"")
                if arguments[4:7] == ["docker", "container", "rm"]:
                    assert arguments[7:] == ["b" * 64] and child_exists[0], arguments
                    child_exists[0] = False
                    writes.append("rm")
                    return subprocess.CompletedProcess(arguments, 0, b"b" * 64 + b"\n", b"")
                assert arguments[4:7] == ["docker", "container", "ls"], arguments
                return subprocess.CompletedProcess(arguments, 0, b"b" * 64 if child_exists[0] else b"", b"")

            namespace["run_interruptible"] = run
            busy_fd = None
            try:
                if case == "busy":
                    busy_fd = os.open(root / "data/net/.hopping-supervisor/owner.json", os.O_RDONLY)
                    MODULE["fcntl"].flock(busy_fd, MODULE["fcntl"].LOCK_EX | MODULE["fcntl"].LOCK_NB)
                try:
                    result = MODULE["recover"](str(root), str(entrypoint), case != "preview")
                except (MODULE["Failure"], OSError):
                    assert case not in {"preview", "clean"}, case
                    assert not writes and child_exists[0], (case, writes)
                    assert (root / "data/net/.hopping-supervisor").is_dir() and lock.is_dir(), case
                    if case not in {"owner-replaced", "stage-replaced"}:
                        assert {str(path.relative_to(root)): file_identity(path)
                                for path in root.rglob("*")} == before, case
                else:
                    assert case in {"preview", "clean"}, case
                    assert result == {"state": "recoverable" if case == "preview" else "stopped",
                                      "saved": audit["saved"], "owner_sha256": digest(owner),
                                      "child_id": "b" * 64, "stage": str(stage)}
                    if case == "preview":
                        assert not writes and child_exists[0]
                        assert {str(path.relative_to(root)): file_identity(path)
                                for path in root.rglob("*")} == before
                    else:
                        assert writes == ["rm"] and not child_exists[0]
                        assert not stage.exists() and not lock.exists()
                        assert not (root / "data/net/.hopping-supervisor").exists()
                count += 1
            finally:
                if busy_fd is not None:
                    os.close(busy_fd)
                namespace["run_interruptible"] = native_run
    finally:
        namespace["run_interruptible"] = native_run
        live.terminate()
        live.wait(timeout=5)
    return count


def main():
    count = 0
    count += deadline_cases()
    with tempfile.TemporaryDirectory(prefix="padm-hopping-deployment-gate.") as directory:
        count += deployment_gate_cases(Path(directory))
        count += rollback_scope_cases(Path(directory))
        count += recovery_cases(Path(directory))
    payload = {"target": {"listener_id": "hy2-main"}, "running": {
        "v": 1, "phase": "running", "nonce": "a" * 64,
        "child_id": "b" * 64, "request_sha256": "c" * 64, "seq": 2,
    }, "child": {"Id": "b" * 64}, "directory": [["/", 1, 2, 0o755, 0, 0]],
    "stage": "/tmp/padm/data/net/.hopping-guarded.abc"}
    frame = invoke(
        "gate", "ready", payload, response=lambda value: {
            "v": 1, "phase": "commit", "nonce": value["nonce"]})
    count += 1
    invoke(
        "gate", "running", payload, response=lambda value: {
            "v": 1, "phase": "continue", "nonce": value["nonce"]})
    count += 1
    invoke(
        "gate", "restart", {"bash_pid": os.getpid(), "lock": []}, response=lambda value: {
            "v": 1, "phase": "commit", "nonce": value["nonce"]})
    count += 1
    invoke("notify", "cleaned", {"target": payload["target"], "child_id": "b" * 64,
                                 "stage": payload["stage"]})
    count += 1
    for response in (
        lambda value: {"v": 1, "phase": "commit", "nonce": "d" * 64},
        lambda value: {"v": 1, "phase": "commit", "nonce": value["nonce"], "extra": True},
        lambda value: {"v": 1, "phase": "continue", "nonce": value["nonce"]},
    ):
        invoke("gate", "ready", payload, accepted=False, response=response)
        count += 1
    invoke("notify", "running", payload, accepted=False)
    count += 1
    for response in (
        lambda value: {"v": 1, "phase": "commit", "nonce": "d" * 64},
        lambda value: {"v": 1, "phase": "continue", "nonce": value["nonce"]},
    ):
        invoke("gate", "restart", {"bash_pid": os.getpid(), "lock": []},
               accepted=False, response=response)
        count += 1
    with tempfile.TemporaryDirectory(prefix="padm-hopping-supervisor.") as directory:
        root = Path(directory)
        (root / "data/net").mkdir(parents=True, mode=0o700)
        module_directory = MODULE["Directory"](str(root))
        module_directory.session(create=True)
        assert module_directory.path == str(root / "data/net/.hopping-supervisor")
        owner = {
            "v": 1, "token": "e" * 64, "root": str(root), "manager": {
                "pid": os.getpid(), "starttime_ticks": 1, "boot_id": "fixed",
                "pid_ns": "pid:[1]", "net_ns": "net:[1]", "session_id": os.getsid(0),
            }, "bash": None, "stage": None, "stage_sha256": None, "state": "starting",
        }
        module_directory.write_owner(owner)
        assert module_directory.read_owner() == owner
        assert (root / "data/net/.hopping-supervisor/owner.json").stat().st_mode & 0o777 == 0o600
        assert digest(owner) == digest(json.loads(
            (root / "data/net/.hopping-supervisor/owner.json").read_text()))
        (root / "data/net/.hopping-supervisor/owner.json").unlink()
        (root / "data/net/.hopping-supervisor/owner.json").symlink_to("/etc/passwd")
        try:
            try:
                module_directory.read_owner()
            except Exception:
                count += 1
            else:
                raise AssertionError("符号链接 owner 未拒绝")
        finally:
            (root / "data/net/.hopping-supervisor/owner.json").unlink()
            module_directory.close()
    with tempfile.TemporaryDirectory(prefix="padm-hopping-service.") as directory:
        base = Path(directory)
        entrypoint = base / "entrypoint.sh"
        entrypoint.write_text(
            f'source "{ROOT / "install-docker.sh"}"\n'
            'dockerPortHoppingSavedArguments() {\n'
            '  [[ -d "$PADM_DOCKER_INSTALL_DIR/locks/deployment.lock" &&\n'
            '     "$(cat "$PADM_DOCKER_INSTALL_DIR/locks/deployment.lock/pid")" == "$$" ]] || return 1\n'
            '  jq -ec "." "$PADM_DOCKER_INSTALL_DIR/saved-arguments.json"\n'
            '}\n'
            'if [[ "$0" == padm-hopping-reservation && '
            '( -n "${TEST_RESERVATION_WAIT:-}" || "${TEST_INIT_PHASE:-}" == reservation-wait ) ]]; then\n'
            '  mkdir() {\n'
            '    local status=0 target="${@: -1}"\n'
            '    command mkdir "$@" || status=$?\n'
            '    if [[ "$target" == "$PADM_DOCKER_INSTALL_DIR/locks/deployment.lock" && '
            '"$status" != 0 ]]; then\n'
            '      if [[ -n "${TEST_RESERVATION_WAIT:-}" ]]; then : >"$TEST_RESERVATION_WAIT"; fi\n'
            '      if [[ "${TEST_INIT_PHASE:-}" == reservation-wait ]]; then\n'
            '        printf "%s\\n" "$$" >"$TEST_INIT_BARRIER.ready"\n'
            '      fi\n'
            '    fi\n'
            '    return "$status"\n'
            '  }\n'
            'fi\n'
            'if [[ "$0" == padm-hopping-reservation-check && -n "${TEST_RESERVATION_PAUSE:-}" ]]; then\n'
            '  if [[ "$TEST_RESERVATION_PHASE" == before && '
            '! -e "$PADM_DOCKER_INSTALL_DIR/data/net/.hopping-supervisor" || '
            '"$TEST_RESERVATION_PHASE" == after && '
            '-d "$PADM_DOCKER_INSTALL_DIR/data/net/.hopping-supervisor" ]]; then\n'
            '    printf "%s\\n" "$$" >"$TEST_RESERVATION_PAUSE.ready"\n'
            '    IFS= read -r token <"$TEST_RESERVATION_PAUSE.fifo"\n'
            '  fi\n'
            'fi\n'
            'if [[ "$0" == padm-hopping-reservation-check && '
            '-d "$PADM_DOCKER_INSTALL_DIR/data/net/.hopping-supervisor" ]]; then\n'
            '  case "${TEST_RESERVATION_FAULT:-}" in\n'
            '    changed-pid) printf "2147483647\\n" >"$PADM_DOCKER_INSTALL_DIR/locks/deployment.lock/pid" ;;\n'
            '    occupied-lock) mkdir "$PADM_DOCKER_INSTALL_DIR/locks/deployment.lock/foreign" ;;\n'
            '    replaced-session)\n'
            '      mv "$PADM_DOCKER_INSTALL_DIR/data/net/.hopping-supervisor" '
            '"$PADM_DOCKER_INSTALL_DIR/data/net/.hopping-supervisor.previous"\n'
            '      mkdir -m 700 "$PADM_DOCKER_INSTALL_DIR/data/net/.hopping-supervisor" ;;\n'
            '  esac\n'
            'fi\n'
            'dockerPortHoppingTargetSupervisedOwned() {\n'
            '  printf "%s\\n" "${@:2:5}" >"$PADM_DOCKER_INSTALL_DIR/selected-arguments"\n'
            f'  exec "{sys.executable}" "{SCRIPT}" fake-owned "$1" "$PADM_DOCKER_INSTALL_DIR" '
            '"${7:-}" "${@:8}"\n'
            '}\n')
        entrypoint.chmod(0o600)
        count += reservation_cases(base, entrypoint)
        count += initialization_signal_cases(base, entrypoint)
        count += service_deadline_cases(base, entrypoint)
        for case in ("clean", "ack-lost", "invalid-finished", "invalid-finished-restart",
                     "invalid-restart-gate", "precommit-eof", "lifecycle-down",
                     "lifecycle-uninstall", "invalid-finished-down", "invalid-finished-uninstall",
                     "changes", "change-failed", "invalid-update-gate", "invalid-changed"):
            installation = base / case
            (installation / "data/net").mkdir(parents=True, mode=0o700)
            installation.chmod(0o700)
            if case.startswith("invalid-finished"):
                (installation / "invalid-finished").touch()
            if case in {"change-failed", "invalid-update-gate", "invalid-changed"}:
                (installation / case).touch()
            manager = manager_fd = None
            if case in {"ack-lost", "precommit-eof"}:
                caller, service = socket.socketpair()
                manager = subprocess.Popen([
                    sys.executable, str(HELPER), "_service", str(service.fileno()),
                    str(installation), str(entrypoint), "hy2-main", "36561", "36562",
                    "198.18.1.1", "2001:db8:1::1"], pass_fds=(service.fileno(),),
                    start_new_session=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                service.close()
                MODULE["send"](caller, {"v": 1, "phase": "hello", "action": "start",
                                        "client_nonce": "e" * 64})
                proof = MODULE["receive"](caller)
                if case == "ack-lost":
                    MODULE["send"](caller, {"v": 1, "phase": "commit", "action": "start",
                                            "nonce": proof["nonce"], "client_nonce": "e" * 64})
                caller.close()
                if case == "precommit-eof":
                    output, error = manager.communicate(timeout=5)
                    assert manager.returncode == 1 and not output and error
                    assert not (installation / "data/net/fixture-running").exists()
                    assert not (installation / "data/net/.hopping-supervisor").exists()
                    assert not (installation / "locks").exists()
                    count += 1
                    continue
                deadline = time.monotonic() + 8
                while True:
                    try:
                        status = MODULE["control"]("status", str(installation))
                        break
                    except (OSError, MODULE["Failure"]):
                        assert time.monotonic() < deadline
                        time.sleep(0.05)
            else:
                status = MODULE["start"](
                    str(installation), str(entrypoint),
                    ["hy2-main", "36561", "36562", "198.18.1.1", "2001:db8:1::1"])
            try:
                owner = status["owner"]
                manager_fd = MODULE["pin"](owner["manager"])
                assert owner["manager"]["session_id"] == owner["manager"]["pid"]
                assert owner["bash"]["session_id"] == owner["manager"]["pid"]
                assert (installation / "data/net/fixture-running").exists()
                repeated = subprocess.run([
                    sys.executable, str(HELPER), "start", str(installation), str(entrypoint),
                    "hy2-main", "36561", "36562", "198.18.1.1", "2001:db8:1::1"],
                    capture_output=True, timeout=8)
                assert repeated.returncode == 1 and not repeated.stdout and repeated.stderr
                stale = subprocess.run([sys.executable, str(HELPER), "stop", str(installation), "f" * 64],
                                       capture_output=True, timeout=8)
                assert stale.returncode == 1 and not stale.stdout and stale.stderr
                current = MODULE["control"]("status", str(installation))
                assert current["owner"] == owner and current["payload"]["running"]["seq"] >= 2
                lock = installation / "locks/deployment.lock"
                original_pid = (lock / "pid").read_bytes()
                original_lock = file_identity(lock), file_identity(lock / "pid"), original_pid
                deployment_command(installation, "dockerLockInstalledDeployment")
                assert (file_identity(lock), file_identity(lock / "pid"),
                        (lock / "pid").read_bytes()) == original_lock
                assert MODULE["control"]("status", str(installation))["owner"] == owner
                count += 1
                if case in {"clean", "changes", "change-failed"}:
                    session = installation / "data/net/.hopping-supervisor"
                    session_id = MODULE["path_identity"](session.stat())
                    for action in (("restart", "restart") if case == "clean" else ("update", "rollback")):
                        previous = current
                        old_bash = MODULE["pin"](owner["bash"])
                        try:
                            arguments = ["--manifest", "/tmp/private manifest.json"] if action == "update" else []
                            restarted = MODULE["control"](action, str(installation), arguments=arguments)
                            assert set(restarted) == {
                                "v", "phase", "nonce", "client_nonce", "owner", "owner_sha256",
                                "payload", "previous_owner", "cleaned", "finished",
                                *({"change"} if action != "restart" else set())}
                            assert restarted["phase"] == {
                                "restart": "restarted", "update": "updated", "rollback": "rolled_back"}[action]
                            if action != "restart":
                                assert restarted["change"] == {
                                    "action": action, "arguments": arguments,
                                    "status": 11 if case == "change-failed" else 0}
                                assert json.loads((installation / "fixture-change").read_text()) == [
                                    action, arguments]
                            assert restarted["previous_owner"] == owner
                            assert restarted["finished"] == {"status": 143, "lock_released": True}
                            assert restarted["cleaned"] == {
                                "target": previous["payload"]["target"],
                                "child_id": previous["payload"]["child"]["Id"],
                                "stage": owner["stage"]}
                            assert MODULE["select"].select([old_bash], [], [], 0)[0]
                        finally:
                            os.close(old_bash)
                        new_owner = restarted["owner"]
                        assert new_owner["manager"] == owner["manager"]
                        assert all(new_owner[key] != owner[key] for key in (
                            "token", "bash", "stage", "stage_sha256"))
                        assert MODULE["path_identity"](session.stat()) == session_id
                        assert json.loads((session / "owner.json").read_text()) == new_owner
                        assert (restarted["payload"]["target"]["container_id"] ==
                                previous["payload"]["target"]["container_id"]) == (action == "restart")
                        assert restarted["payload"]["target"]["started_at"] != (
                            previous["payload"]["target"]["started_at"])
                        assert restarted["payload"]["child"]["Id"] != (
                            previous["payload"]["child"]["Id"])
                        assert (lock / "pid").read_text() == str(new_owner["bash"]["pid"]) + "\n"
                        for rejected_action in ("restart", "stop", "update", "rollback"):
                            if rejected_action in {"update", "rollback"}:
                                try:
                                    MODULE["control"](rejected_action, str(installation), owner["token"])
                                except MODULE["Failure"]:
                                    pass
                                else:
                                    raise AssertionError("旧 token 通过事务挑战")
                            else:
                                rejected = subprocess.run([
                                    sys.executable, str(HELPER), rejected_action, str(installation), owner["token"]],
                                    capture_output=True, timeout=8)
                                assert rejected.returncode == 1 and not rejected.stdout and rejected.stderr
                            assert json.loads((session / "owner.json").read_text()) == new_owner
                        owner = new_owner
                        current = MODULE["control"]("status", str(installation))
                        assert current["owner"] == owner and current["payload"]["running"]["seq"] >= 2
                        assert current["payload"]["target"] == restarted["payload"]["target"]
                        deployment_command(installation, "dockerLockInstalledDeployment")
                        count += 1
                    assert len((installation / "fixture-launches").read_text().splitlines()) == 3
                elif case.endswith(("-down", "-uninstall")):
                    uninstall = case.endswith("-uninstall")
                    function = "dockerUninstallCommand" if uninstall else "dockerLifecycleCommand"
                    arguments = () if uninstall else ("down",)
                    deployment_command(
                        installation, function, *(("--purge",) if uninstall else ("down", "extra")),
                        lifecycle=True, usage=True)
                    assert MODULE["control"]("status", str(installation))["owner"] == owner
                    assert not (installation / "actions").exists()
                    if uninstall:
                        (installation / "compose.json").write_text("{}")
                    valid = not case.startswith("invalid")
                    deployment_command(installation, function, *arguments,
                                       lifecycle=True, accepted=valid)
                    assert len((installation / "fixture-launches").read_text().splitlines()) == 1
                    assert not (installation / "data/net/fixture-running").exists()
                    assert not lock.exists()
                    if valid:
                        assert not (installation / "data/net/.hopping-supervisor").exists()
                        expected = (["traffic", "geo", "renewal", "log", "sync",
                                     "compose:down", "schedule", "cli"] if uninstall else
                                    ["renewal", "log", "sync", "traffic", "compose:down", "schedule"])
                        assert (installation / "actions").read_text().splitlines() == expected
                    else:
                        assert (installation / "data/net/.hopping-supervisor/owner.json").exists()
                        assert not (installation / "actions").exists()
                    count += 2
                    continue
                elif case in {"invalid-finished-restart", "invalid-restart-gate",
                              "invalid-update-gate", "invalid-changed"}:
                    session = installation / "data/net/.hopping-supervisor"
                    session_id = MODULE["path_identity"](session.stat())
                    if case == "invalid-restart-gate":
                        (installation / case).touch()
                    rejected = subprocess.run([
                        sys.executable, str(HELPER), "update" if case in {
                            "invalid-update-gate", "invalid-changed"} else "restart", str(installation)],
                        capture_output=True, timeout=12)
                    assert rejected.returncode == (12 if case in {
                        "invalid-update-gate", "invalid-changed"} else 1) and not rejected.stdout and rejected.stderr
                    assert MODULE["select"].select([manager_fd], [], [], 5)[0]
                    assert MODULE["path_identity"](session.stat()) == session_id
                    assert not (installation / "data/net/fixture-running").exists()
                    launches = (installation / "fixture-launches").read_text().splitlines()
                    if case == "invalid-finished-restart":
                        assert launches == [str(owner["bash"]["pid"])]
                        assert json.loads((session / "owner.json").read_text()) == owner
                        assert not lock.exists()
                    else:
                        assert len(launches) == 2 and launches[0] == str(owner["bash"]["pid"])
                        assert (lock / "pid").read_text().strip() == launches[1]
                        new_owner = json.loads((session / "owner.json").read_text())
                        assert new_owner["state"] == "starting" and new_owner["stage"] is None
                    deployment_command(installation, "dockerLockInstalledDeployment")
                    count += 1
                    continue
                stopped = subprocess.run([sys.executable, str(HELPER), "stop", str(installation)],
                                         capture_output=True, timeout=12)
                if case == "invalid-finished":
                    assert stopped.returncode == 1 and not stopped.stdout and stopped.stderr
                    assert (installation / "data/net/.hopping-supervisor/owner.json").exists()
                    deployment_command(installation, "dockerLockInstalledDeployment")
                    assert not lock.exists()
                else:
                    assert stopped.returncode == 0 and not stopped.stderr
                    result = json.loads(stopped.stdout)
                    assert result["phase"] == "stopped" and result["owner"] == owner
                    assert result["finished"] == {"status": 143, "lock_released": True}
                    assert not (installation / "data/net/.hopping-supervisor").exists()
                    assert not (installation / "locks/deployment.lock").exists()
                    deployment_command(installation, "dockerLockInstalledDeployment", accepted=True)
                assert not (installation / "data/net/fixture-running").exists()
                count += 1
            finally:
                if manager_fd is not None:
                    if not MODULE["select"].select([manager_fd], [], [], 0)[0]:
                        signal.pidfd_send_signal(manager_fd, signal.SIGTERM)
                        MODULE["select"].select([manager_fd], [], [], 5)
                    os.close(manager_fd)
                if manager is not None:
                    manager.communicate(timeout=5)
    # 明确拒绝单向管道，防止把继承的 fd 当作控制授权。
    read_fd, write_fd = os.pipe()
    try:
        result = subprocess.run(
            [sys.executable, str(HELPER), "gate", "ready", "{}"],
            stdin=read_fd, pass_fds=(read_fd,), capture_output=True, timeout=5)
        assert result.returncode == 1 and not result.stdout and result.stderr
        count += 1
    finally:
        os.close(read_fd)
        os.close(write_fd)
    print(f"docker-port-hopping-supervisor-parent-ok: {count} strict control and owner cases")


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "fake-owned":
        action = sys.argv[4].removeprefix("--") if len(sys.argv) >= 5 else ""
        assert action in {"", "restart", "update", "rollback"}
        fake_owned(int(sys.argv[2]), sys.argv[3], action, sys.argv[5:])
    elif sys.argv[1:2] in (["_service"], ["_reserve"]) and os.environ.get("TEST_INIT_PHASE"):
        initialization_wrapper(sys.argv[1:])
    else:
        main()
