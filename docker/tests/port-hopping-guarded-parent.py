#!/usr/bin/env python3
import copy
import hashlib
import json
import os
from pathlib import Path
import runpy
import signal
import subprocess
import sys
import tempfile
import time


SCRIPT = Path(__file__).resolve()
ROOT = SCRIPT.parents[2]
SHARED = runpy.run_path(str(SCRIPT.with_name("port-hopping-handshake.py")))
HELPER = SHARED["HELPER"]
CID, IMAGE, VALUES = (SHARED[key] for key in ("CID", "IMAGE", "VALUES"))
line = SHARED["line"]
NONCES = {"challenge": "1" * 64, "ready": "5" * 64,
          "written": "6" * 64, "active": "7" * 64}


def fake_docker():
    work = Path(os.environ["HOP_PARENT_WORK"])
    arguments = sys.argv[2:]
    case = os.environ["HOP_PARENT_SCENARIO"]
    with (work / "events.jsonl").open("a") as stream:
        stream.write(json.dumps({"event": "docker", "argv": arguments}) + "\n")
    if arguments[:2] == ["image", "inspect"]:
        if case == "image-query-timeout":
            time.sleep(8)
        print(json.dumps([{"Id": IMAGE}]))
        return
    inventory = work / "container.json"
    if arguments[:2] == ["container", "inspect"]:
        print(json.dumps([json.loads(inventory.read_text())]))
        return
    if arguments[:2] == ["container", "rm"]:
        value = json.loads(inventory.read_text())
        assert (value["State"]["Status"] == "exited" and not value["State"]["Running"]
                and type(value["State"]["ExitCode"]) is int and value["State"]["ExitCode"] == 0)
        (work / "removed").touch()
        if case.startswith("signal-cleanup-"):
            os.kill(int((work / "parent.pid").read_text()),
                    signal.SIGINT if case.endswith("-int") else signal.SIGTERM)
        return
    assert arguments[0] == "run", arguments
    assert arguments[-6:] == ["port-hopping-guarded", *VALUES], arguments
    value = json.loads((work / "template.json").read_text())
    host = arguments[arguments.index("--hostname") + 1]
    label = arguments[arguments.index("--label") + 1]
    assert label.startswith("io.padm.hopping-guarded="), label
    value["Config"].update(Hostname=host, Labels={label.split("=", 1)[0]: label.split("=", 1)[1]})
    inventory.write_text(json.dumps(value))
    Path(arguments[arguments.index("--cidfile") + 1]).write_text(CID)
    (work / "transport.pid").write_text(str(os.getpid()))
    residual = work / "installation/data/net/port-hopping.state"
    exit_code = 1

    def emit(phase, digest=None):
        if case == "binding-" + phase:
            (work / "binding.drift").touch()
        elif case == "child-" + phase:
            value["Config"]["User"] = "1:1"
            inventory.write_text(json.dumps(value))
        nonce = NONCES[phase]
        if case == "old-ready" and phase == "ready":
            nonce = NONCES["challenge"]
        elif case == "duplicate-written" and phase == "written":
            nonce = NONCES["ready"]
        frame = {"v": 1, "phase": phase, "nonce": nonce}
        if phase == "challenge":
            frame["host"] = host
        else:
            frame.update(child_id=CID, request_sha256=digest)
        sys.stdout.buffer.write(line(frame))
        sys.stdout.flush()
        (work / "phase").write_text(phase)
        return frame

    def receive():
        raw = sys.stdin.buffer.readline()
        if not raw:
            return None
        item = json.loads(raw)
        with (work / "requests.jsonl").open("a") as stream:
            stream.write(json.dumps(item) + "\n")
        return raw, item

    try:
        emit("challenge")
        incoming = receive()
        if incoming is None:
            raise SystemExit(exit_code)
        raw, request = incoming
        prepared = json.loads((work / "prepared.json").read_text())
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
        for phase, action in (("ready", "write"), ("written", "finalize"), ("active", "close")):
            if phase == "written" and case in {"signal-int", "signal-term"}:
                (work / "signal.waiting").touch()
                deadline = time.monotonic() + 8
                while not (work / "signal.release").exists():
                    assert time.monotonic() < deadline, "父信号夹具未释放"
                    time.sleep(0.01)
                raise SystemExit(exit_code)
            if phase == "written" and case == "cleanup-timeout":
                # 模拟容器仍运行，宿主 transport 退出也不能证明 NAT 已撤销。
                sys.stdout.buffer.write(b"{}\n")
                sys.stdout.flush()
                sys.stdin.buffer.read()
                while True:
                    time.sleep(0.05)
            frame = emit(phase, digest)
            if phase == "written" and case == "epipe-written":
                deadline = time.monotonic() + 8
                while not (work / "transport.release").exists():
                    assert time.monotonic() < deadline, "EPIPE 夹具未释放"
                    time.sleep(0.01)
                os.close(0)
                raise SystemExit(exit_code)
            incoming = receive()
            if incoming is None:
                raise SystemExit(exit_code)
            _, response = incoming
            assert response == {**frame, "phase": action}, (phase, response)
            if action == "write":
                (work / "written").touch()
                residual.write_text("fixture owner remains\n")
                residual.chmod(0o600)
        assert sys.stdin.buffer.read() == b"", "close 之后还有额外授权输入"
        exit_code = 1 if case == "nonzero-exit" else 0
        if exit_code == 0:
            residual.unlink()
        value["State"].update(Status="exited", Running=False, ExitCode=exit_code)
        inventory.write_text(json.dumps(value))
        if case != "missing-closed":
            closed = {"v": 1, "phase": "closed", "nonce": NONCES["active"],
                      "child_id": CID, "request_sha256": digest}
            (work / "closed.json").write_text(json.dumps(closed))
            sys.stdout.buffer.write(line(closed))
            if case == "duplicate-closed":
                sys.stdout.buffer.write(line(closed))
            elif case == "tail":
                sys.stdout.buffer.write(b"x")
            sys.stdout.flush()
        if case.startswith("signal-wait-"):
            # 子容器已正常关闭，但 Docker transport 在输出 EOF 后仍未退出。
            os.close(1)
            (work / "transport.waiting").touch()
            while True:
                time.sleep(0.05)
    finally:
        if case != "cleanup-timeout":
            value["State"].update(Status="exited", Running=False, ExitCode=exit_code)
            inventory.write_text(json.dumps(value))
    sys.exit(exit_code)


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
    seen = [NONCES["challenge"]]
    for phase in ("ready", "written", "active"):
        frame = {"v": 1, "phase": phase, "nonce": NONCES[phase],
                 "child_id": CID, "request_sha256": digest}
        arguments = ["guarded-frame", phase, CID, digest, *seen]
        assert json.loads(invoke(arguments, line(frame))) == frame
        for wrong in ({**frame, "nonce": seen[-1]}, {**frame, "v": True},
                      {**frame, "child_id": "8" * 64}, {**frame, "request_sha256": "9" * 64},
                      {**frame, "phase": "closed"}):
            invoke(arguments, line(wrong), False)
        seen.append(NONCES[phase])
    closed = {"v": 1, "phase": "closed", "nonce": NONCES["active"],
              "child_id": CID, "request_sha256": digest}
    arguments = ["guarded-frame", "closed", CID, digest, NONCES["active"]]
    assert json.loads(invoke(arguments, line(closed))) == closed
    for raw in (line({**closed, "nonce": NONCES["written"]}),
                line(closed) * 2, line(closed) + b"x"):
        invoke(arguments, raw, False)
    # 多帧一次到达也逐帧消费；closed 独立核验最终 EOF。
    reader, writer = os.pipe()
    try:
        frames = [{"v": 1, "phase": phase, "nonce": NONCES[phase],
                   "child_id": CID, "request_sha256": digest}
                  for phase in ("ready", "written", "active")]
        os.write(writer, b"".join(map(line, [*frames, closed])))
        os.close(writer)
        writer = None
        seen = [NONCES["challenge"]]
        for frame in frames:
            result = subprocess.run([sys.executable, str(HELPER), "guarded-frame",
                                     frame["phase"], CID, digest, *seen], stdin=reader,
                                    capture_output=True, timeout=5)
            assert result.returncode == 0 and json.loads(result.stdout) == frame and not result.stderr
            seen.append(frame["nonce"])
            count += 1
        result = subprocess.run([sys.executable, str(HELPER), *arguments], stdin=reader,
                                capture_output=True, timeout=5)
        assert result.returncode == 0 and json.loads(result.stdout) == closed and not result.stderr
        count += 1
    finally:
        if writer is not None:
            os.close(writer)
        os.close(reader)

    with tempfile.TemporaryDirectory(prefix="padm-hopping-guarded-parent.") as directory:
        directory = Path(directory)
        binaries = directory / "bin"
        binaries.mkdir()
        docker = binaries / "docker"
        docker.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{SCRIPT}" docker "$@"\n')
        docker.chmod(0o755)
        original_date = subprocess.check_output(["sh", "-c", "command -v date"], text=True).strip()
        date = binaries / "date"
        date.write_text(
            '#!/bin/sh\nif [ "$HOP_PARENT_SCENARIO" = cleanup-timeout ] && '
            '[ "$1" = +%s ]; then\n'
            '  n=0; [ ! -f "$HOP_PARENT_WORK/date.count" ] || n=$(cat "$HOP_PARENT_WORK/date.count")\n'
            '  n=$((n+30)); printf "%s" "$n" >"$HOP_PARENT_WORK/date.count"; printf "%s\\n" "$n"\n'
            f'else exec "{original_date}" "$@"; fi\n')
        date.chmod(0o755)
        original_timeout = subprocess.check_output(
            ["sh", "-c", "command -v timeout"], text=True).strip()
        timeout = binaries / "timeout"
        # 仅 wait 夹具直接 exec，避免 timeout 自身持有 stdout 写端。
        timeout.write_text(
            '#!/bin/sh\ncase "$HOP_PARENT_SCENARIO" in signal-wait-int|signal-wait-term)\n'
            '  if [ "$1" = -k ] && [ "$2" = 2 ] && [ "$3" = 150 ]; then\n'
            '    shift 3; exec "$@"\n'
            '  fi;; esac\n'
            f'exec "{original_timeout}" "$@"\n')
        timeout.chmod(0o755)
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
    if [[ "$HOP_PARENT_SCENARIO" == epipe-written ]]; then
        local number=0 childPid deadline=$((SECONDS + 8))
        [[ ! -f "$HOP_PARENT_WORK/binding.count" ]] || number=$(<"$HOP_PARENT_WORK/binding.count")
        printf '%s' "$((number + 1))" >"$HOP_PARENT_WORK/binding.count"
        if [[ "$number" == 3 ]]; then
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
dockerRemoveManagedTree() {
    [[ "$1" == "$HOP_PARENT_WORK/installation" && "$2" == "$1"/.hopping-guarded.* ]] || return 1
    rm -r -- "$2"
}
dockerError() { printf '%s\n' "$*" >&2; }
wait() {
    if [[ "$HOP_PARENT_SCENARIO" == signal-wait-* && ! -f "$HOP_PARENT_WORK/wait.started" ]]; then
        printf '%s' "$ph_transport" >"$HOP_PARENT_WORK/transport-job.pid"
        : >"$HOP_PARENT_WORK/wait.started"
    fi
    builtin wait "$@"
}
trap 'printf "INT\n" >>"$HOP_PARENT_WORK/original-traps-fired"' INT
trap 'printf "TERM\n" >>"$HOP_PARENT_WORK/original-traps-fired"' TERM
trap 'printf "PIPE\n" >>"$HOP_PARENT_WORK/original-traps-fired"' PIPE
trap -p INT TERM PIPE >"$HOP_PARENT_WORK/traps.before"
if [[ "$HOP_PARENT_SCENARIO" == subshell ]]; then
    output=$(dockerPortHoppingTargetGuarded hy2-main 36561 36562 198.18.1.1 2001:db8:1::1)
    status=$?
    trap -p INT TERM PIPE >"$HOP_PARENT_WORK/traps.after"
    printf '%s' "$output"
    exit "$status"
fi
dockerPortHoppingTargetGuarded hy2-main 36561 36562 198.18.1.1 2001:db8:1::1
status=$?
trap -p INT TERM PIPE >"$HOP_PARENT_WORK/traps.after"
exit "$status"
'''
        scenarios = ["success", "subshell", "old-ready", "duplicate-written",
                     "missing-closed", "duplicate-closed", "tail", "nonzero-exit",
                     "signal-int", "signal-term", "cleanup-timeout", "epipe-written",
                     "image-query-timeout", "signal-cleanup-int", "signal-cleanup-term",
                     "signal-wait-int", "signal-wait-term"]
        scenarios += [kind + "-" + phase for kind in ("binding", "child")
                      for phase in ("challenge", "ready", "written", "active")]
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
                    "Cmd": ["port-hopping-guarded", *VALUES], "Hostname": CID[:12], "User": "0:0",
                    "Healthcheck": {"Test": ["NONE"]}, "Labels": {"io.padm.hopping-guarded": "test"},
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
            if scenario == "success":
                arguments = ["guarded-container", str(installation), CID, IMAGE, "test",
                             *VALUES, CID[:12], "live"]
                invoke(arguments, line([template]))
                invoke(["container", *arguments[1:]], line([template]), False)
                probe = copy.deepcopy(template)
                probe["Config"].update(Cmd=["port-hopping-probe", *VALUES],
                                       Labels={"io.padm.hopping-probe": "test"})
                invoke(arguments, line([probe]), False)
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
            started = time.monotonic()
            process = subprocess.Popen(["bash", "-c", shell], env=environment,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       start_new_session=True)
            try:
                if scenario in {"signal-int", "signal-term"}:
                    deadline = time.monotonic() + 8
                    while not (work / "signal.waiting").exists() and process.poll() is None:
                        assert time.monotonic() < deadline, (scenario, "未到写后信号门")
                        time.sleep(0.01)
                    assert process.poll() is None and (work / "written").exists()
                    process.send_signal(signal.SIGINT if scenario == "signal-int" else signal.SIGTERM)
                    (work / "signal.release").touch()
                if scenario.startswith("signal-wait-"):
                    deadline = time.monotonic() + 8
                    while process.poll() is None:
                        if ((work / "wait.started").exists() and (work / "transport.waiting").exists() and
                                Path(f"/proc/{process.pid}/wchan").read_text().strip() == "do_wait"):
                            break
                        assert time.monotonic() < deadline, (scenario, "父端未进入 transport wait")
                        time.sleep(0.01)
                    assert process.poll() is None and (work / "transport.waiting").exists()
                    transport = int((work / "transport-job.pid").read_text())
                    assert transport == int((work / "transport.pid").read_text())
                    assert Path(f"/proc/{transport}").exists()
                    process.send_signal(signal.SIGINT if scenario.endswith("-int") else signal.SIGTERM)
                output, error = process.communicate(timeout=12)
                expected = {"success": 0, "signal-int": 130, "signal-term": 143,
                            "signal-cleanup-int": 130, "signal-cleanup-term": 143,
                            "signal-wait-int": 130, "signal-wait-term": 143}.get(scenario, 1)
                events = [json.loads(row) for row in (work / "events.jsonl").read_text().splitlines()]
                if scenario == "image-query-timeout":
                    assert (process.returncode > 0 and
                            process.returncode not in {130, 143, 128 + signal.SIGPIPE}), (
                                scenario, process.returncode, output, error, events)
                    elapsed = time.monotonic() - started
                    assert elapsed < 8, (scenario, "查询未在夹具结束前限时退出", elapsed)
                else:
                    assert process.returncode == expected, (
                        scenario, process.returncode, output, error, events)
                assert (work / "traps.before").read_bytes() == (work / "traps.after").read_bytes(), (
                    scenario, "调用方 INT/TERM/PIPE trap 未恢复")
                assert not (work / "original-traps-fired").exists(), (
                    scenario, "事务期间错误调用原 trap")
                if scenario.startswith("signal-wait-"):
                    assert not Path(f"/proc/{transport}").exists(), (
                        scenario, "transport 未回收", transport)
                calls = [row["argv"] for row in events if row["event"] == "docker"]
                assert not any(row[:2] in (["container", "stop"], ["container", "kill"])
                               for row in calls), (scenario, calls)
                prepares = [row["pid"] for row in events if row["event"] == "prepare"]
                assert prepares == ([] if scenario == "subshell" else [
                    int((work / "parent.pid").read_text())]), (scenario, prepares)
                if scenario == "success":
                    assert json.loads(output) == {
                        **prepared, "guarded_closed": json.loads((work / "closed.json").read_text())}
                    assert not error and not list(installation.glob(".hopping-guarded.*"))
                else:
                    assert not output, (scenario, output)
                    if scenario != "subshell":
                        assert error, (scenario, error)
                if scenario == "epipe-written":
                    assert (work / "epipe.ready").exists(), "未同步到真实关闭的管道读端"
                    assert b"Broken pipe" in error, error
                if scenario not in {"subshell", "image-query-timeout"}:
                    inventory = json.loads((work / "container.json").read_text())
                    state = inventory["State"]
                    retained = scenario.startswith("child-") or not (
                        state["Status"] == "exited" and state["Running"] is False and
                        type(state["ExitCode"]) is int and state["ExitCode"] == 0)
                    assert (work / "removed").exists() != retained, (scenario, calls, error)
                    if retained:
                        stages = list(installation.glob(".hopping-guarded.*"))
                        assert stages and (stages[0] / "cid").read_text() == CID
                        assert not any(row[:2] == ["container", "rm"] for row in calls)
                    if (work / "written").exists():
                        residual = net / "port-hopping.state"
                        assert residual.exists() == (scenario == "cleanup-timeout" or
                                                     state["ExitCode"] != 0), (scenario, state)
                    if state["Status"] == "exited":
                        assert state["ExitCode"] == (0 if scenario in {
                            "success", "missing-closed", "duplicate-closed", "tail",
                            "signal-cleanup-int", "signal-cleanup-term",
                            "signal-wait-int", "signal-wait-term"} else 1), (
                                scenario, state)
                    if scenario.startswith(("signal-cleanup-", "signal-wait-")):
                        stages = list(installation.glob(".hopping-guarded.*"))
                        assert stages and (stages[0] / "cid").read_text() == CID
                elif scenario == "image-query-timeout":
                    assert calls == [["image", "inspect", "fixture-net"]], calls
                    assert not (work / "removed").exists()
                    stages = list(installation.glob(".hopping-guarded.*"))
                    assert len(stages) == 1 and (stages[0] / "prepared.json").is_file()
                    assert not (stages[0] / "cid").exists()
                else:
                    assert not calls and not list(installation.glob(".hopping-guarded.*"))
                requests_path = work / "requests.jsonl"
                requests = ([json.loads(row) for row in requests_path.read_text().splitlines()]
                            if requests_path.exists() else [])
                if scenario.startswith(("binding-", "child-")):
                    phase = scenario.split("-", 1)[1]
                    expected_requests = {"challenge": [], "ready": [None],
                                         "written": [None, "write"],
                                         "active": [None, "write", "finalize"]}[phase]
                elif scenario in {"subshell", "image-query-timeout"}:
                    expected_requests = []
                elif scenario == "old-ready":
                    expected_requests = [None]
                elif scenario in {"duplicate-written", "signal-int", "signal-term",
                                  "cleanup-timeout", "epipe-written"}:
                    expected_requests = [None, "write"]
                else:
                    expected_requests = [None, "write", "finalize", "close"]
                assert [item.get("phase") for item in requests] == expected_requests, (
                    scenario, requests)
                count += 1
            finally:
                (work / "signal.release").touch()
                if process.poll() is None or scenario.startswith("signal-wait-"):
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                process.communicate(timeout=5)
    print(f"docker-port-hopping-guarded-parent-ok: {count} bound gate, frame and cleanup cases")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "docker":
        fake_docker()
    else:
        main()
