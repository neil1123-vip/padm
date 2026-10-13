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
            'dockerPortHoppingTargetSupervisedOwned() {\n'
            f'  exec "{sys.executable}" "{SCRIPT}" fake-owned "$1" "$PADM_DOCKER_INSTALL_DIR"\n'
            '}\n')
        entrypoint.chmod(0o600)
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
                    assert (installation / "data/net/.hopping-supervisor/owner.json").is_file()
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
                stopped = subprocess.run([sys.executable, str(HELPER), "stop", str(installation)],
                                         capture_output=True, timeout=12)
                if case == "invalid-finished":
                    assert stopped.returncode == 1 and not stopped.stdout and stopped.stderr
                    assert (installation / "data/net/.hopping-supervisor/owner.json").exists()
                else:
                    assert stopped.returncode == 0 and not stopped.stderr
                    result = json.loads(stopped.stdout)
                    assert result["phase"] == "stopped" and result["owner"] == owner
                    assert result["finished"] == {"status": 143, "lock_released": True}
                    assert not (installation / "data/net/.hopping-supervisor").exists()
                    assert not (installation / "locks/deployment.lock").exists()
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
