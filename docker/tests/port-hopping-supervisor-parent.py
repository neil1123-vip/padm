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
"$@"
'''


def deployment_command(root, function, *arguments, accepted=False, boundary=""):
    result = subprocess.run([
        "bash", "-Eeuo", "pipefail", "-c", DEPLOYMENT_BODY, "test",
        str(ROOT / "install-docker.sh"), function, *arguments],
        env=dict(os.environ, PADM_DOCKER_INSTALL_DIR=str(root), PADM_DOCKER_LOCK_TIMEOUT="30",
                 TEST_GATE_CASE=boundary),
        capture_output=True, timeout=5)
    assert result.returncode == (0 if accepted else 12), (
        function, result.returncode, result.stdout, result.stderr)
    assert not result.stdout
    if accepted:
        assert not result.stderr
    else:
        assert "跳跃监督会话存在或停止未核验".encode() in result.stderr, result.stderr


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


def fake_owned(fd, root):
    peer = socket.socket(fileno=fd)
    installation = Path(root)
    lock = installation / "locks/deployment.lock"
    lock.mkdir(parents=True, mode=0o750)
    (lock / "pid").write_text(str(os.getpid()) + "\n")
    stage = installation / ".hopping-guarded.fixture"
    stage.mkdir(mode=0o700)
    token = MODULE["identity"](os.getpid())
    marker = installation / "data/net/fixture-running"
    marker.write_text(str(os.getpid()))
    stopping = [False]
    signal.signal(signal.SIGTERM, lambda *_: stopping.__setitem__(0, True))
    value = {"target": {"listener_id": "hy2-main"}, "running": {
        "v": 1, "phase": "running", "nonce": "2" * 64, "child_id": "b" * 64,
        "request_sha256": "c" * 64, "seq": 2,
    }, "child": {"Id": "b" * 64}, "directory": [["/", 1, 2, 0o755, 0, 0]],
    "stage": str(stage)}

    def gate(phase):
        event = {"v": 1, "phase": phase, "nonce": os.urandom(32).hex(), "payload": value}
        MODULE["send"](peer, event)
        response = MODULE["receive"](peer)
        assert response == {"v": 1, "phase": "commit" if phase == "ready" else "continue",
                            "nonce": event["nonce"]} or stopping[0], response

    gate("ready")
    gate("started")
    while not stopping[0]:
        time.sleep(0.1)
        if stopping[0]:
            break
        value["running"].update(seq=value["running"]["seq"] + 1, nonce=os.urandom(32).hex())
        gate("running")
    marker.unlink()
    stage.rmdir()
    MODULE["send"](peer, {"v": 1, "phase": "cleaned", "nonce": os.urandom(32).hex(), "payload": {
        "target": value["target"], "child_id": value["child"]["Id"], "stage": str(stage)}})
    (lock / "pid").unlink()
    lock.rmdir()
    finished = {"status": 143, "lock_released": True}
    if (installation / "invalid-finished").exists():
        finished["lock_released"] = 1
    MODULE["send"](peer, {"v": 1, "phase": "finished", "nonce": os.urandom(32).hex(),
                         "payload": finished})
    assert MODULE["identity"](os.getpid()) == token
    raise SystemExit(143)


def reservation_cases(base, entrypoint):
    count = 0
    installation = base / "reservation-wait"
    (installation / "data/net").mkdir(parents=True, mode=0o700)
    holder = subprocess.Popen([
        "bash", "-Eeuo", "pipefail", "-c",
        'source "$1"; trap dockerReleaseDeploymentLock EXIT; '
        'dockerAcquireDeploymentLock; printf "locked\\n"; read -r release; [[ "$release" == release ]]',
        "test", str(ROOT / "install-docker.sh")],
        env=dict(os.environ, PADM_DOCKER_INSTALL_DIR=str(installation)),
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
                str(installation), str(entrypoint), "hy2-main", "36561", "36562",
                "198.18.1.1", "2001:db8:1::1"], pass_fds=(peer.fileno(),),
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


def line(value):
    return canonical(value) + b"\n"


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


def main():
    count = 0
    with tempfile.TemporaryDirectory(prefix="padm-hopping-deployment-gate.") as directory:
        count += deployment_gate_cases(Path(directory))
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
            'if [[ "$0" == padm-hopping-reservation && -n "${TEST_RESERVATION_WAIT:-}" ]]; then\n'
            '  mkdir() {\n'
            '    local status=0 target="${@: -1}"\n'
            '    command mkdir "$@" || status=$?\n'
            '    if [[ "$target" == "$PADM_DOCKER_INSTALL_DIR/locks/deployment.lock" && '
            '"$status" != 0 ]]; then : >"$TEST_RESERVATION_WAIT"; fi\n'
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
            f'  exec "{sys.executable}" "{SCRIPT}" fake-owned "$1" "$PADM_DOCKER_INSTALL_DIR"\n'
            '}\n')
        entrypoint.chmod(0o600)
        count += reservation_cases(base, entrypoint)
        for case in ("clean", "ack-lost", "invalid-finished", "precommit-eof"):
            installation = base / case
            (installation / "data/net").mkdir(parents=True, mode=0o700)
            installation.chmod(0o700)
            if case == "invalid-finished":
                (installation / "invalid-finished").touch()
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
    if len(sys.argv) == 4 and sys.argv[1] == "fake-owned":
        fake_owned(int(sys.argv[2]), sys.argv[3])
    else:
        main()
