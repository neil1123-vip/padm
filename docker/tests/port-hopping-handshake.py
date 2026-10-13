#!/usr/bin/env python3
import copy
import hashlib
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "docker/lib/port-hopping-probe.py"
NONCE = "1" * 64
CID = "2" * 64
DIGEST = "3" * 64
IMAGE = "sha256:" + "4" * 64
LABEL = "padm-hopping-probe-test"
VALUES = ("36561", "36562", "35461", "198.18.1.1", "2001:db8:1::1")
CHALLENGE = {"v": 1, "phase": "challenge", "nonce": NONCE, "host": CID[:12]}
ACK = {"v": 1, "phase": "ack", "nonce": NONCE, "child_id": CID,
       "request_sha256": DIGEST}
SCRIPT = Path(__file__).resolve()


def line(value):
    return json.dumps(value, separators=(",", ":")).encode("ascii") + b"\n"


def fake_docker():
    work = Path(os.environ["HOP_PARENT_WORK"])
    arguments = sys.argv[2:]
    with (work / "events.jsonl").open("a") as stream:
        stream.write(json.dumps({"event": "docker", "argv": arguments}) + "\n")
    if arguments[:2] == ["image", "inspect"]:
        print(json.dumps([{"Id": IMAGE}]))
        return
    inventory = work / "container.json"
    if arguments[:2] == ["container", "inspect"]:
        print(json.dumps([json.loads(inventory.read_text())]))
        return
    if arguments[:2] == ["container", "stop"]:
        value = json.loads(inventory.read_text())
        value["State"].update(Status="exited", Running=False)
        inventory.write_text(json.dumps(value))
        return
    if arguments[:2] == ["container", "rm"]:
        (work / "removed").touch()
        return
    assert arguments[0] == "run", arguments
    case = os.environ["HOP_PARENT_SCENARIO"]
    value = json.loads((work / "template.json").read_text())
    host = arguments[arguments.index("--hostname") + 1]
    label = arguments[arguments.index("--label") + 1].split("=", 1)[1]
    value["Config"].update(Hostname=host, Labels={"io.padm.hopping-probe": label})
    inventory.write_text(json.dumps(value))
    cid = Path(arguments[arguments.index("--cidfile") + 1])
    cid.write_text(CID)
    (work / "transport.pid").write_text(str(os.getpid()))
    if case == "directory-replaced":
        net = work / "installation/data/net"
        net.rename(net.with_name("net.saved"))
        net.mkdir(mode=0o700)
    if case.startswith("no-challenge"):
        if case.endswith("replaced"):
            value["Config"]["User"] = "1:1"
        value["State"].update(Status="exited", Running=False, ExitCode=1)
        inventory.write_text(json.dumps(value))
        sys.exit(1)
    sys.stdout.buffer.write(line({**CHALLENGE, "host": host}))
    sys.stdout.flush()
    raw = sys.stdin.buffer.read()
    if not raw:
        sys.exit(1)
    request = json.loads(raw)
    prepared = json.loads((work / "prepared.json").read_text())
    expected = {
        "v", "nonce", "parent_pid", "parent_lock_sha256", "startup_sha256",
        "child_id", "image_id", "target",
    }
    assert set(request) == expected and request["nonce"] == NONCE
    assert request["parent_pid"] == int((work / "parent.pid").read_text())
    assert request["child_id"] == CID and request["image_id"] == IMAGE
    assert request["parent_lock_sha256"] == hashlib.sha256(b'{"token":"fixed"}').hexdigest()
    assert request["startup_sha256"] == hashlib.sha256(
        json.dumps(prepared["startup_binding"], separators=(",", ":")).encode("ascii")).hexdigest()
    assert request["target"] == {key: prepared[key] for key in (
        "container_id", "image_id", "started_at", "restart_count", "listener_id",
        "range_start", "range_end", "target_port", "ipv4", "ipv6")}
    (work / "request.json").write_bytes(raw)
    if case.startswith("signal-"):
        (work / "ack.waiting").touch()
        deadline = time.monotonic() + 8
        while not (work / "ack.release").exists():
            if time.monotonic() > deadline:
                raise AssertionError("signal fixture not released")
            time.sleep(0.01)
        value["State"].update(Status="exited", Running=False, ExitCode=1)
        inventory.write_text(json.dumps(value))
        sys.exit(1)
    value["State"].update(Status="exited", Running=False, ExitCode=0)
    inventory.write_text(json.dumps(value))
    ack = {**ACK, "request_sha256": hashlib.sha256(raw[:-1]).hexdigest()}
    if case == "wrong-nonce":
        ack["nonce"] = "5" * 64
    sys.stdout.buffer.write(line(ack) + (b"{}\n" if case == "extra-ack" else b""))
    sys.stdout.flush()


def main():
    count = 0

    def invoke(arguments, value=b"", accepted=True):
        nonlocal count
        result = subprocess.run([sys.executable, str(HELPER), *arguments], input=value,
                                capture_output=True, timeout=5)
        assert result.returncode == (0 if accepted else 1), (
            arguments, result.returncode, result.stdout, result.stderr)
        if accepted:
            assert result.stdout and not result.stderr, (arguments, result.stderr)
        else:
            assert not result.stdout and result.stderr, arguments
        count += 1
        return result.stdout

    for kind, value in (("challenge", CHALLENGE), ("ack", ACK)):
        arguments = ["frame", kind, *([] if kind == "challenge" else [NONCE, CID, DIGEST])]
        assert json.loads(invoke(arguments, line(value))) == value
        invalid = []
        for key, replacement in (("v", True), ("phase", "other"), ("nonce", "A" * 64)):
            current = copy.deepcopy(value)
            current[key] = replacement
            invalid.append(line(current))
        invalid.extend([
            line({**value, "extra": True}),
            line(value).replace(b'{"v":1,', b'{"v":1,"v":1,', 1),
            line(value)[:-1],
            line(value).replace(b"\n", b"\r\n"),
            line(value)[:-1] + b"\0\n",
            b"null\n",
            b"{}\n",
            line(value)[:-1] + b" " * 4096 + b"\n",
        ])
        if kind == "challenge":
            invalid.append(line({**value, "host": "friendly-hostname"}))
        else:
            invalid.extend([
                line({**value, "child_id": "5" * 64}),
                line({**value, "request_sha256": "6" * 64}),
                line(value) + b"{}\n",
                line(value) + b"x",
            ])
        for raw in invalid:
            invoke(arguments, raw, False)

        process = subprocess.Popen([sys.executable, str(HELPER), *arguments],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE)
        try:
            for byte in line(value):
                process.stdin.write(bytes([byte]))
                process.stdin.flush()
            if kind == "ack":
                # ACK 读到完整行后仍须等 EOF；旧 nonce 和完整行都不能绕过关闭输入。
                assert not select.select([process.stdout], [], [], 0.1)[0]
                assert process.poll() is None
                process.stdin.close()
                process.stdin = None
            else:
                assert select.select([process.stdout], [], [], 5)[0]
                process.stdin.close()
                process.stdin = None
            output, error = process.communicate(timeout=5)
            assert process.returncode == 0 and not error
            assert json.loads(output) == value
            count += 1
        finally:
            if process.poll() is None:
                process.send_signal(signal.SIGKILL)
            process.communicate(timeout=5)

    for noise in (b"", b"x\n"):
        reader, writer = os.pipe()
        try:
            os.write(writer, line(CHALLENGE) + noise + line(ACK))
            os.close(writer)
            writer = None
            for kind, expected in (("challenge", CHALLENGE), ("ack", ACK)):
                arguments = ["frame", kind, *(
                    [] if kind == "challenge" else [NONCE, CID, DIGEST])]
                result = subprocess.run([sys.executable, str(HELPER), *arguments], stdin=reader,
                                        capture_output=True, timeout=5)
                accepted = kind == "challenge" or not noise
                assert result.returncode == (0 if accepted else 1)
                if accepted:
                    assert json.loads(result.stdout) == expected and not result.stderr
                else:
                    assert not result.stdout and result.stderr
                count += 1
        finally:
            if writer is not None:
                os.close(writer)
            os.close(reader)

    with tempfile.TemporaryDirectory(prefix="padm-hopping-handshake.") as directory:
        installation = Path(directory) / "installation"
        net = installation / "data/net"
        net.mkdir(parents=True, mode=0o700)
        installation.chmod(0o700)
        net.parent.chmod(0o700)
        baseline = json.loads(invoke(["directory", str(installation)]))
        assert json.loads(invoke(["directory", str(installation)])) == baseline
        net.rename(net.with_name("net.saved"))
        net.mkdir(mode=0o700)
        replaced = json.loads(invoke(["directory", str(installation)]))
        assert replaced != baseline
        net.chmod(0o770)
        invoke(["directory", str(installation)], accepted=False)
        net.chmod(0o700)
        net.rmdir()
        net.symlink_to(net.with_name("net.saved"), target_is_directory=True)
        invoke(["directory", str(installation)], accepted=False)
        net.unlink()
        net.with_name("net.saved").rename(net)

        command = ["port-hopping-probe", *VALUES]
        value = {
            "Id": CID, "Image": IMAGE, "Created": "2026-10-13T05:00:00Z", "RestartCount": 0,
            "Config": {
                "Entrypoint": ["/usr/local/bin/padm-entrypoint"], "Cmd": command,
                "Hostname": CID[:12], "User": "0:0", "Healthcheck": {"Test": ["NONE"]},
                "Labels": {"io.padm.hopping-probe": LABEL}, "Tty": False, "OpenStdin": True,
                "Env": ["PATH=/usr/sbin:/usr/bin:/sbin:/bin"],
            },
            "HostConfig": {
                "NetworkMode": "host", "ReadonlyRootfs": True, "Privileged": False,
                "CapAdd": ["CAP_NET_ADMIN"], "CapDrop": ["ALL"],
                "SecurityOpt": ["no-new-privileges"], "PidMode": "", "UsernsMode": "",
                "IpcMode": "private", "RestartPolicy": {"Name": "no", "MaximumRetryCount": 0},
                "Tmpfs": {"/tmp": "rw,nosuid,nodev,size=16m,mode=1777",
                          "/run": "rw,nosuid,nodev,size=16m,mode=0755"},
                "Mounts": [{"Type": "bind", "Source": str(net), "Target": "/var/lib/padm/net"}],
            },
            "Mounts": [{"Type": "bind", "Source": str(net), "Destination": "/var/lib/padm/net",
                        "RW": True, "Propagation": "rprivate"}],
            "State": {
                "Status": "running", "Running": True, "Restarting": False, "Paused": False,
                "Dead": False, "StartedAt": "2026-10-13T05:00:01.123Z", "ExitCode": 0,
            },
        }
        arguments = ["container", str(installation), CID, IMAGE, LABEL, *VALUES, CID[:12], "live"]
        projection = json.loads(invoke(arguments, line([value])))
        assert projection == {
            **{key: value[key] for key in ("Id", "Image", "Created", "Config", "HostConfig", "Mounts")},
            "StartedAt": value["State"]["StartedAt"],
        }
        assert json.loads(invoke([*arguments[:-1], "any"], line([value]))) == projection
        other_host = copy.deepcopy(value)
        other_host["Config"]["Hostname"] = "0123456789ab"
        assert json.loads(invoke([*arguments[:-2], "0123456789ab", "any"], line([other_host])))[
            "Config"]["Hostname"] == "0123456789ab"
        stopped = copy.deepcopy(value)
        stopped["State"].update(Status="exited", Running=False)
        invoke(arguments, line([stopped]), False)
        assert json.loads(invoke([*arguments[:-1], "any"], line([stopped]))) == projection

        changes = [
            (("Id",), "5" * 64), (("Image",), "sha256:" + "5" * 64),
            (("RestartCount",), 1), (("RestartCount",), False),
            (("Created",), "2026-02-30T05:00:00Z"),
            (("Config", "Cmd"), ["port-hopping", *VALUES]),
            (("Config", "Entrypoint"), ["/bin/sh"]),
            (("Config", "Hostname"), "friendly-host"),
            (("Config", "Labels"), {}), (("Config", "User"), "root"),
            (("Config", "OpenStdin"), False), (("Config", "Tty"), True),
            (("Config", "Healthcheck"), {"Test": ["CMD", "true"]}),
            (("HostConfig", "NetworkMode"), "bridge"),
            (("HostConfig", "ReadonlyRootfs"), False),
            (("HostConfig", "Privileged"), True), (("HostConfig", "CapAdd"), ["SYS_ADMIN"]),
            (("HostConfig", "CapDrop"), []), (("HostConfig", "SecurityOpt"), []),
            (("HostConfig", "PidMode"), "host"),
            (("HostConfig", "RestartPolicy"), {"Name": "always", "MaximumRetryCount": 0}),
            (("HostConfig", "Tmpfs"), {}),
            (("HostConfig", "Mounts"), [
                {"Type": "bind", "Source": str(net), "Target": "/var/lib/padm/net"},
                {"Type": "bind", "Source": "/var/run/docker.sock", "Target": "/var/run/docker.sock"}]),
            (("HostConfig", "Binds"), ["/var/run/docker.sock:/var/run/docker.sock"]),
            (("Mounts",), [{**value["Mounts"][0], "RW": False}]),
            (("State", "StartedAt"), "2026-10-13T05:00:00.1234567890Z"),
            (("State", "Paused"), True),
        ]
        for path, replacement in changes:
            current = copy.deepcopy(value)
            parent = current
            for key in path[:-1]:
                parent = parent[key]
            parent[path[-1]] = replacement
            invoke(arguments, line([current]), False)
        invoke(arguments, line([]), False)
        invoke(arguments, line([value, value]), False)
        invoke([*arguments[:-2], "wrong", "live"], line([value]), False)
        for path, replacement in (
            (("Created",), "2026-10-13T05:00:00.1Z"),
            (("State", "StartedAt"), "2026-10-13T05:00:02Z"),
            (("Config", "Env"), ["PATH=/changed"]),
            (("HostConfig", "LogConfig"), {"Type": "json-file", "Config": {}}),
            (("Mounts",), [{**value["Mounts"][0], "Driver": "foreign"}]),
        ):
            current = copy.deepcopy(value)
            parent = current
            for key in path[:-1]:
                parent = parent[key]
            parent[path[-1]] = replacement
            changed = json.loads(invoke(arguments, line([current])))
            assert changed != projection, path
            top = "StartedAt" if path[0] == "State" else path[0]
            assert changed[top] == (
                current["State"]["StartedAt"] if top == "StartedAt" else current[top])

        binaries = Path(directory) / "bin"
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
    case "$HOP_PARENT_SCENARIO" in
        prepare-int) return 130 ;;
        prepare-term) return 143 ;;
    esac
    cat "$HOP_PARENT_WORK/prepared.json"
}
dockerPortHoppingTargetBindingCheck() {
    local number=0
    [[ ! -f "$HOP_PARENT_WORK/binding.count" ]] || number=$(<"$HOP_PARENT_WORK/binding.count")
    printf '%s' "$((number + 1))" >"$HOP_PARENT_WORK/binding.count"
    [[ "$HOP_PARENT_SCENARIO" != binding-drift || "$number" -lt 1 ]]
}
dockerPortHoppingTargetStartLockCheck() { return 0; }
dockerRemoveManagedTree() {
    [[ "$1" == "$HOP_PARENT_WORK/installation" && "$2" == "$1"/.hopping-probe.* ]] || return 1
    rm -r -- "$2"
}
dockerError() { printf '%s\n' "$*" >&2; }
if [[ "$HOP_PARENT_SCENARIO" == subshell ]]; then
    output=$(dockerPortHoppingTargetProbe hy2-main 36561 36562 198.18.1.1 2001:db8:1::1)
    status=$?
    printf '%s' "$output"
    exit "$status"
fi
dockerPortHoppingTargetProbe hy2-main 36561 36562 198.18.1.1 2001:db8:1::1
exit $?
'''
        for scenario in ("success", "subshell", "prepare-lock-drift", "prepare-int", "prepare-term",
                         "binding-drift", "directory-replaced",
                         "wrong-nonce", "extra-ack", "no-challenge", "no-challenge-replaced",
                         "signal-int", "signal-term"):
            work = Path(directory) / ("parent-" + scenario)
            work.mkdir(mode=0o700)
            installation = work / "installation"
            net = installation / "data/net"
            net.mkdir(parents=True, mode=0o700)
            installation.chmod(0o700)
            net.parent.chmod(0o700)
            template = copy.deepcopy(value)
            template["HostConfig"]["Mounts"][0]["Source"] = str(net)
            template["Mounts"][0]["Source"] = str(net)
            (work / "template.json").write_text(json.dumps(template))
            prepared = {
                "container_id": "e" * 64, "image_id": "sha256:" + "f" * 64,
                "started_at": "2026-10-13T05:00:00.1Z", "restart_count": 0,
                "listener_id": "hy2-main", "range_start": int(VALUES[0]),
                "range_end": int(VALUES[1]), "target_port": int(VALUES[2]),
                "ipv4": VALUES[3], "ipv6": VALUES[4],
                "startup_binding": {"generation": "fixed", "lock": {"token": "fixed"}},
            }
            if scenario == "prepare-lock-drift":
                prepared["startup_binding"]["lock"]["token"] = "foreign"
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
                    deadline = time.monotonic() + 8
                    while not (work / "ack.waiting").exists() and process.poll() is None:
                        assert time.monotonic() < deadline, (scenario, "no ACK gate")
                        time.sleep(0.01)
                    assert process.poll() is None, scenario
                    process.send_signal(signal.SIGINT if scenario == "signal-int" else signal.SIGTERM)
                    (work / "ack.release").touch()
                output, error = process.communicate(timeout=10)
                expected = {"success": 0, "signal-int": 130, "signal-term": 143,
                            "prepare-int": 130, "prepare-term": 143}.get(scenario, 1)
                assert process.returncode == expected, (
                    scenario, process.returncode, output, error, (work / "events.jsonl").read_text())
                events = [json.loads(row) for row in (work / "events.jsonl").read_text().splitlines()]
                prepares = [row["pid"] for row in events if row["event"] == "prepare"]
                parent_pid = int((work / "parent.pid").read_text())
                assert prepares == ([] if scenario == "subshell" else [parent_pid]), events
                calls = [row["argv"] for row in events if row["event"] == "docker"]
                if scenario == "success":
                    assert json.loads(output) == {**prepared, "probe_ack": json.loads(
                        line({**ACK, "request_sha256": hashlib.sha256(
                            (work / "request.json").read_bytes()[:-1]).hexdigest()}))}
                    assert not error
                    assert not list(installation.glob(".hopping-probe.*"))
                else:
                    assert not output, (scenario, output)
                if scenario in {"subshell", "prepare-lock-drift", "prepare-int", "prepare-term"}:
                    assert not calls and not (work / "removed").exists()
                elif scenario == "no-challenge-replaced":
                    assert not (work / "removed").exists()
                    assert not any(row[:2] in (["container", "stop"], ["container", "rm"])
                                   for row in calls)
                    assert json.loads((work / "container.json").read_text())["Config"]["User"] == "1:1"
                else:
                    assert (work / "removed").exists(), (scenario, calls, error)
                    assert sum(row[:2] == ["container", "stop"] for row in calls) == 1
                    assert sum(row[:2] == ["container", "rm"] for row in calls) == 1
                if scenario in {"binding-drift", "directory-replaced"}:
                    assert not (work / "request.json").exists()
                pidfile = work / "transport.pid"
                if pidfile.exists():
                    assert not Path(f"/proc/{pidfile.read_text()}").exists(), scenario
                count += 1
            finally:
                (work / "ack.release").touch()
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                process.communicate(timeout=5)

    print(f"docker-port-hopping-handshake-ok: {count} frame, directory, container and parent cases")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "docker":
        fake_docker()
    else:
        main()
