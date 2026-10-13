#!/usr/bin/env python3
import copy
import hashlib
import json
import os
from pathlib import Path
import runpy
import signal
import stat
import subprocess
import sys
import tempfile
import time


SCRIPT = Path(__file__).resolve()
SHARED = runpy.run_path(str(SCRIPT.with_name("port-hopping-guarded-parent.py")))
ROOT, HELPER, CID, IMAGE, VALUES, NONCES, line = (
    SHARED[key] for key in ("ROOT", "HELPER", "CID", "IMAGE", "VALUES", "NONCES", "line"))


def await_file(path, predicate=lambda value: True):
    deadline = time.monotonic() + 8
    while True:
        if path.exists():
            value = path.read_text()
            if predicate(value):
                return value
        assert time.monotonic() < deadline, ("夹具同步未完成", path)
        time.sleep(0.01)


def fake_docker():
    work = Path(os.environ["HOP_PARENT_WORK"])
    case, arguments = os.environ["HOP_PARENT_SCENARIO"], sys.argv[2:]
    with (work / "events.jsonl").open("a") as stream:
        stream.write(json.dumps({"event": "docker", "argv": arguments}) + "\n")
    inventory = work / "container.json"
    if arguments[:2] == ["image", "inspect"]:
        print(json.dumps([{"Id": IMAGE}]))
        return
    if arguments[:2] == ["container", "inspect"]:
        print(json.dumps([json.loads(inventory.read_text())]))
        return
    if arguments[:2] == ["container", "rm"]:
        value = json.loads(inventory.read_text())
        assert value["State"] == {**value["State"], "Status": "exited",
                                  "Running": False, "ExitCode": 0}
        (work / "removed").touch()
        return
    assert arguments[0] == "run", arguments
    assert arguments[-6:] == ["port-hopping-supervised", *VALUES], arguments
    value = json.loads((work / "template.json").read_text())
    host = arguments[arguments.index("--hostname") + 1]
    label = arguments[arguments.index("--label") + 1]
    assert label.startswith("io.padm.hopping-supervised="), label
    value["Config"].update(Hostname=host, Labels={label.split("=", 1)[0]: label.split("=", 1)[1]})
    inventory.write_text(json.dumps(value))
    Path(arguments[arguments.index("--cidfile") + 1]).write_text(CID)
    (work / "transport.pid").write_text(str(os.getpid()))
    prepared = json.loads((work / "prepared.json").read_text())
    residual = work / "installation/data/net/port-hopping.state"
    exit_code = 0

    def receive():
        raw = sys.stdin.buffer.readline()
        if not raw:
            return None
        item = json.loads(raw)
        with (work / "requests.jsonl").open("a") as stream:
            stream.write(json.dumps(item) + "\n")
        return raw, item

    def emit(frame):
        sys.stdout.buffer.write(line(frame))
        sys.stdout.flush()

    try:
        emit({"v": 1, "phase": "challenge", "nonce": NONCES["challenge"], "host": host})
        incoming = receive()
        if incoming is None:
            return
        raw, request = incoming
        assert set(request) == {"v", "nonce", "parent_pid", "parent_lock_sha256",
                                "startup_sha256", "child_id", "image_id", "target"}
        assert request["nonce"] == NONCES["challenge"] and request["child_id"] == CID
        assert request["image_id"] == IMAGE
        assert request["parent_pid"] == int((work / "parent.pid").read_text())
        assert request["parent_lock_sha256"] == hashlib.sha256(b'{"token":"fixed"}').hexdigest()
        assert request["startup_sha256"] == hashlib.sha256(
            json.dumps(prepared["startup_binding"], separators=(",", ":")).encode("ascii")).hexdigest()
        assert request["target"] == {key: prepared[key] for key in (
            "container_id", "image_id", "started_at", "restart_count", "listener_id",
            "range_start", "range_end", "target_port", "ipv4", "ipv6")}
        digest = hashlib.sha256(raw[:-1]).hexdigest()
        for phase, action in (("ready", "write"), ("written", "finalize"), ("active", "continue")):
            if case == "binding-" + phase:
                (work / "binding.drift").touch()
            frame = {"v": 1, "phase": phase, "nonce": NONCES[phase],
                     "child_id": CID, "request_sha256": digest}
            emit(frame)
            incoming = receive()
            if incoming is None:
                return
            assert incoming[1] == {**frame, "phase": action}, (phase, incoming)
            if action == "write":
                residual.write_text("fixture owner remains\n")
                residual.chmod(0o600)
                (work / "written").touch()
        previous = None
        for seq in range(1, 4):
            if seq == 2:
                if case == "binding-running":
                    (work / "binding.drift").touch()
                elif case == "child-running":
                    value["Config"]["User"] = "1:1"
                    inventory.write_text(json.dumps(value))
                elif case == "directory-running":
                    net = residual.parent
                    net.rename(net.with_name("net.saved"))
                    net.mkdir(mode=0o700)
                    residual = net.with_name("net.saved") / residual.name
                elif case.startswith("signal-"):
                    (work / "signal.waiting").touch()
                    await_file(work / "signal.release")
                elif case == "nonzero-cleanup":
                    exit_code = 1
                    sys.stdout.buffer.write(b"{}\n")
                    sys.stdout.flush()
                    assert sys.stdin.buffer.read() == b""
                    raise SystemExit(exit_code)
            frame = {"v": 1, "phase": "running", "nonce": f"{seq + 7:x}" * 64,
                     "child_id": CID, "request_sha256": digest, "seq": seq}
            if seq == 2:
                if case == "seq-gap":
                    frame["seq"] = 3
                elif case == "replay-previous":
                    frame["nonce"] = previous["nonce"]
                elif case == "replay-initial":
                    frame["nonce"] = NONCES["active"]
                elif case == "wrong-digest":
                    frame["request_sha256"] = "f" * 64
            emit(frame)
            if seq == 2 and case == "epipe-running":
                await_file(work / "transport.release")
                os.close(0)
                exit_code = 1
                raise SystemExit(exit_code)
            incoming = receive()
            if incoming is None:
                return
            assert incoming[1] == {**frame, "phase": "continue"}, (seq, incoming)
            stages = list((work / "installation").glob(".hopping-guarded.*"))
            assert len(stages) == 1, stages
            receipt = stages[0] / "supervised.json"
            raw = await_file(receipt, lambda text: json.loads(text)["running"]["seq"] == seq)
            assert json.loads(raw) == {"target": prepared, "running": frame}
            assert not receipt.is_symlink() and stat.S_IMODE(receipt.stat().st_mode) == 0o600
            assert not (stages[0] / "supervised.next").exists()
            with (work / "receipts.jsonl").open("a") as stream:
                stream.write(raw.strip() + "\n")
            previous = frame
        # 完成三轮后故意发非法帧，验证父端失败关闭输入、子端自行撤销。
        sys.stdout.buffer.write(b"{}\n")
        sys.stdout.flush()
        assert sys.stdin.buffer.read() == b""
    finally:
        if exit_code == 0:
            residual.unlink(missing_ok=True)
        value["State"].update(Status="exited", Running=False, ExitCode=exit_code)
        inventory.write_text(json.dumps(value))
    raise SystemExit(exit_code)


def main():
    count = 0

    def invoke(arguments, value, accepted=True):
        nonlocal count
        result = subprocess.run([sys.executable, str(HELPER), *arguments], input=value,
                                capture_output=True, timeout=5)
        assert result.returncode == (0 if accepted else 1), (
            arguments, result.returncode, result.stdout, result.stderr)
        assert bool(result.stdout) == accepted and bool(result.stderr) != accepted
        count += 1
        return result.stdout

    digest = "3" * 64
    frame = {"v": 1, "phase": "running", "nonce": "8" * 64,
             "child_id": CID, "request_sha256": digest, "seq": 1}
    arguments = ["supervised-frame", "running", CID, digest, NONCES["active"], "1"]
    assert json.loads(invoke(arguments, line(frame))) == frame
    for wrong in ({**frame, "v": True}, {**frame, "seq": True},
                  {**frame, "seq": 0}, {**frame, "seq": 2}, {**frame, "seq": "1"},
                  {**frame, "nonce": NONCES["active"]}, {**frame, "nonce": "A" * 64},
                  {**frame, "child_id": "b" * 64}, {**frame, "request_sha256": "c" * 64},
                  {**frame, "phase": "active"}, {**frame, "extra": 1},
                  {key: value for key, value in frame.items() if key != "seq"}):
        invoke(arguments, line(wrong), False)
    for raw in (line(frame).replace(b'{"v":1,', b'{"v":1,"v":1,', 1),
                line(frame)[:-1], line(frame).replace(b"\n", b"\r\n"),
                line(frame)[:-1] + b"\0\n", b"null\n", b"x" * 4096 + b"\n"):
        invoke(arguments, raw, False)
    reader, writer = os.pipe()
    try:
        second = {**frame, "nonce": "9" * 64, "seq": 2}
        os.write(writer, line(frame) + line(second))
        os.close(writer)
        writer = None
        for current, previous in ((frame, NONCES["active"]), (second, frame["nonce"])):
            result = subprocess.run([
                sys.executable, str(HELPER), "supervised-frame", "running", CID, digest,
                previous, str(current["seq"])], stdin=reader, capture_output=True, timeout=5)
            assert result.returncode == 0 and json.loads(result.stdout) == current and not result.stderr
            count += 1
    finally:
        if writer is not None:
            os.close(writer)
        os.close(reader)
    # 模拟等待超时返回，避免每轮回归为同一失败分支空等 20 秒。
    result = subprocess.run([
        sys.executable, "-c",
        'import runpy,select,sys; select.select=lambda *args: ([],[],[]); '
        'sys.argv=sys.argv[1:]; runpy.run_path(sys.argv[0],run_name="__main__")',
        str(HELPER), *arguments], input=b"", capture_output=True, timeout=5)
    assert result.returncode == 1 and not result.stdout and "超时".encode() in result.stderr
    count += 1

    with tempfile.TemporaryDirectory(prefix="padm-hopping-supervised-parent.") as directory:
        directory = Path(directory)
        binaries = directory / "bin"
        binaries.mkdir()
        docker = binaries / "docker"
        docker.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{SCRIPT}" docker "$@"\n')
        docker.chmod(0o755)
        shell = r'''
source "$HOP_PARENT_SOURCE/docker/lib/lifecycle.sh"
export HOP_PARENT_PID=$BASHPID
printf '%s' "$BASHPID" >"$HOP_PARENT_WORK/parent.pid"
DOCKER_LIB_DIR="$HOP_PARENT_SOURCE/docker/lib"
dockerInstallRoot() { printf '%s\n' "$HOP_PARENT_WORK/installation"; }
dockerPortHoppingTargetLockSnapshot() {
    [[ "$1" == "$HOP_PARENT_PID" ]] || return 1
    printf '%s' '{"token":"fixed"}'
}
dockerPortHoppingTargetPrepareActivation() {
    printf '{"event":"prepare","pid":%s}\n' "$BASHPID" >>"$HOP_PARENT_WORK/events.jsonl"
    [[ "$BASHPID" == "$HOP_PARENT_PID" && "$6" == bound ]] || return 1
    cat "$HOP_PARENT_WORK/prepared.json"
}
dockerPortHoppingTargetBindingCheck() {
    printf '{"event":"binding"}\n' >>"$HOP_PARENT_WORK/events.jsonl"
    [[ "$2" == "$(jq -c '.startup_binding' "$HOP_PARENT_WORK/prepared.json")" ]] || return 1
    if [[ "$HOP_PARENT_SCENARIO" == epipe-running ]]; then
        local number=0 childPid deadline=$((SECONDS + 8))
        [[ ! -f "$HOP_PARENT_WORK/binding.count" ]] || number=$(<"$HOP_PARENT_WORK/binding.count")
        printf '%s' "$((number + 1))" >"$HOP_PARENT_WORK/binding.count"
        if [[ "$number" == 6 ]]; then
            : >"$HOP_PARENT_WORK/transport.release"
            childPid=$(<"$HOP_PARENT_WORK/transport.pid")
            while [[ -e "/proc/$childPid/fd/0" || -e "/proc/$ph_transport/fd/0" ]]; do
                [[ "$SECONDS" -lt "$deadline" ]] || return 1
                sleep 0.01
            done
            : >"$HOP_PARENT_WORK/epipe.ready"
        fi
    fi
    [[ ! -f "$HOP_PARENT_WORK/binding.drift" ]]
}
dockerPortHoppingTargetStartLockCheck() { return 0; }
dockerError() { printf '%s\n' "$*" >&2; }
trap 'printf "INT\n" >>"$HOP_PARENT_WORK/original-traps-fired"' INT
trap 'printf "TERM\n" >>"$HOP_PARENT_WORK/original-traps-fired"' TERM
trap 'printf "PIPE\n" >>"$HOP_PARENT_WORK/original-traps-fired"' PIPE
trap -p INT TERM PIPE >"$HOP_PARENT_WORK/traps.before"
if [[ "$HOP_PARENT_SCENARIO" == subshell ]]; then
    output=$(dockerPortHoppingTargetSupervised hy2-main 36561 36562 198.18.1.1 2001:db8:1::1)
    status=$?
    printf '%s' "$output"
else
    dockerPortHoppingTargetSupervised hy2-main 36561 36562 198.18.1.1 2001:db8:1::1
    status=$?
fi
trap -p INT TERM PIPE >"$HOP_PARENT_WORK/traps.after"
exit "$status"
'''
        scenarios = ["multi-renewal", "subshell", "seq-gap", "replay-previous", "replay-initial",
                     "wrong-digest", "binding-running", "child-running", "directory-running",
                     "nonzero-cleanup", "epipe-running", "signal-int", "signal-term",
                     "binding-ready", "binding-written", "binding-active"]
        for scenario in scenarios:
            work = directory / scenario
            work.mkdir(mode=0o700)
            installation = work / "installation"
            net = installation / "data/net"
            net.mkdir(parents=True, mode=0o700)
            installation.chmod(0o700)
            net.parent.chmod(0o700)
            template = {
                "Id": CID, "Image": IMAGE, "Created": "2026-10-13T05:00:00Z", "RestartCount": 0,
                "Config": {
                    "Entrypoint": ["/usr/local/bin/padm-entrypoint"],
                    "Cmd": ["port-hopping-supervised", *VALUES], "Hostname": CID[:12], "User": "0:0",
                    "Healthcheck": {"Test": ["NONE"]}, "Labels": {"io.padm.hopping-supervised": "test"},
                    "Tty": False, "OpenStdin": True,
                },
                "HostConfig": {
                    "NetworkMode": "host", "ReadonlyRootfs": True, "Privileged": False,
                    "CapAdd": ["CAP_NET_ADMIN"], "CapDrop": ["ALL"], "SecurityOpt": ["no-new-privileges"],
                    "PidMode": "", "UsernsMode": "", "IpcMode": "private",
                    "RestartPolicy": {"Name": "no", "MaximumRetryCount": 0},
                    "Tmpfs": {"/tmp": "rw,nosuid,nodev,size=16m,mode=1777",
                              "/run": "rw,nosuid,nodev,size=16m,mode=0755"},
                    "Mounts": [{"Type": "bind", "Source": str(net), "Target": "/var/lib/padm/net"}],
                },
                "Mounts": [{"Type": "bind", "Source": str(net), "Destination": "/var/lib/padm/net",
                            "RW": True, "Propagation": "rprivate"}],
                "State": {"Status": "running", "Running": True, "Restarting": False,
                          "Paused": False, "Dead": False, "StartedAt": "2026-10-13T05:00:01Z",
                          "ExitCode": 0},
            }
            if scenario == "multi-renewal":
                container_arguments = ["supervised-container", str(installation), CID, IMAGE, "test",
                                       *VALUES, CID[:12], "live"]
                invoke(container_arguments, line([template]))
                invoke(["guarded-container", *container_arguments[1:]], line([template]), False)
                wrong = copy.deepcopy(template)
                wrong["Config"].update(Cmd=["port-hopping-guarded", *VALUES],
                                       Labels={"io.padm.hopping-guarded": "test"})
                invoke(container_arguments, line([wrong]), False)
            (work / "template.json").write_text(json.dumps(template))
            prepared = {
                "container_id": "e" * 64, "image_id": "sha256:" + "f" * 64,
                "started_at": "2026-10-13T05:00:00.1Z", "restart_count": 0,
                "listener_id": "hy2-main", "range_start": int(VALUES[0]),
                "range_end": int(VALUES[1]), "target_port": int(VALUES[2]),
                "ipv4": VALUES[3], "ipv6": VALUES[4],
                "startup_binding": {"generation": "fixed", "lock": {"token": "fixed"}},
            }
            (work / "prepared.json").write_text(json.dumps(prepared))
            (installation / "config").mkdir(mode=0o700)
            (installation / "config/spec.json").write_text(json.dumps({
                "core": {"protocols": [{"listener_id": "hy2-main", "hy2": {"domain": "example.test"}}]},
                "images": {"net": "fixture-net"},
            }))
            (work / "events.jsonl").write_text("")
            environment = dict(os.environ, PATH=f"{binaries}:{os.environ['PATH']}",
                               HOP_PARENT_WORK=str(work), HOP_PARENT_SCENARIO=scenario,
                               HOP_PARENT_SOURCE=str(ROOT))
            process = subprocess.Popen(["bash", "-c", shell], env=environment,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       start_new_session=True)
            try:
                if scenario.startswith("signal-"):
                    await_file(work / "signal.waiting")
                    assert process.poll() is None and (work / "written").exists()
                    process.send_signal(signal.SIGINT if scenario.endswith("-int") else signal.SIGTERM)
                    (work / "signal.release").touch()
                output, error = process.communicate(timeout=12)
                expected = {"signal-int": 130, "signal-term": 143}.get(scenario, 1)
                assert process.returncode == expected and not output, (
                    scenario, process.returncode, output, error)
                assert error or scenario == "subshell", (scenario, error)
                assert (work / "traps.before").read_bytes() == (work / "traps.after").read_bytes()
                assert not (work / "original-traps-fired").exists()
                events = [json.loads(row) for row in (work / "events.jsonl").read_text().splitlines()]
                prepares = [row["pid"] for row in events if row["event"] == "prepare"]
                assert prepares == ([] if scenario == "subshell" else [
                    int((work / "parent.pid").read_text())]), (scenario, prepares)
                calls = [row["argv"] for row in events if row["event"] == "docker"]
                assert not any(row[:2] in (["container", "stop"], ["container", "kill"]) for row in calls)
                requests_path = work / "requests.jsonl"
                requests = ([json.loads(row) for row in requests_path.read_text().splitlines()]
                            if requests_path.exists() else [])
                phases = [item.get("phase") for item in requests]
                if scenario == "subshell":
                    assert not calls and not list(installation.glob(".hopping-guarded.*"))
                    assert not requests
                    count += 1
                    continue
                expected_phases = {
                    "binding-ready": [None], "binding-written": [None, "write"],
                    "binding-active": [None, "write", "finalize"],
                }.get(scenario, [None, "write", "finalize", "continue", "continue"])
                if scenario == "multi-renewal":
                    expected_phases += ["continue", "continue"]
                assert phases == expected_phases, (scenario, requests)
                stages = list(installation.glob(".hopping-guarded.*"))
                assert len(stages) == 1 and (stages[0] / "cid").read_text() == CID
                receipt = stages[0] / "supervised.json"
                if scenario.startswith("binding-") and scenario != "binding-running":
                    assert not receipt.exists(), (scenario, receipt)
                else:
                    current = json.loads(receipt.read_text())
                    assert set(current) == {"target", "running"} and current["target"] == prepared
                    assert current["running"]["seq"] == (3 if scenario == "multi-renewal" else 1)
                    assert stat.S_IMODE(receipt.stat().st_mode) == 0o600
                    rows = [json.loads(row) for row in (work / "receipts.jsonl").read_text().splitlines()]
                    assert [row["running"]["seq"] for row in rows] == (
                        [1, 2, 3] if scenario == "multi-renewal" else [1])
                retained = scenario in {"child-running", "nonzero-cleanup", "epipe-running"}
                assert (work / "removed").exists() != retained, (scenario, calls, error)
                state = json.loads((work / "container.json").read_text())["State"]
                assert state["Status"] == "exited" and state["ExitCode"] == (
                    1 if scenario in {"nonzero-cleanup", "epipe-running"} else 0), (scenario, state)
                residual = (net.with_name("net.saved") if scenario == "directory-running" else net
                            ) / "port-hopping.state"
                assert residual.exists() == (state["ExitCode"] != 0), (scenario, state)
                if scenario == "epipe-running":
                    assert (work / "epipe.ready").exists() and b"Broken pipe" in error, error
                count += 1
            finally:
                (work / "signal.release").touch()
                if process.poll() is None:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                process.communicate(timeout=5)
    print(f"docker-port-hopping-supervised-parent-ok: {count} renewal, receipt and failure cases")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "docker":
        fake_docker()
    else:
        main()
