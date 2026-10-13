#!/usr/bin/env python3
import concurrent.futures
import fcntl
import hashlib
import json
import os
from pathlib import Path
import runpy
import select
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time


SCRIPT = Path(__file__).resolve()
ROOT = SCRIPT.parents[2]
OWNERSHIP = runpy.run_path(str(SCRIPT.with_name("port-hopping-ownership.py")))
PROBE = runpy.run_path(str(SCRIPT.with_name("port-hopping-probe.py")))
HOST = PROBE["HOST"]
VALUES = OWNERSHIP["RUN_VALUES"]
FAMILIES = OWNERSHIP["FAMILIES"]
BASE = OWNERSHIP["BASE"]

def tool():
    value = json.loads(Path(os.environ["HOP_FIXTURE"]).read_text())
    if sys.argv[2:] == ["ip", "-j", "address", "show"] and value.get("missing_address"):
        with Path(os.environ["HOP_COMMANDS"]).open("a") as stream:
            stream.write(json.dumps(sys.argv[2:]) + "\n")
        print(json.dumps([{"addr_info": [{"local": VALUES[3]}]}]))
    else:
        OWNERSHIP["tool"]()


def python():
    arguments = sys.argv[2:]
    assert arguments[0] == "/dev/fd/3" and arguments[2] in {"guarded", "supervised"}, arguments
    body = Path(arguments[0]).read_text()
    namespace = {"__name__": "__main__"}
    socket.gethostname = lambda: HOST
    original_replace = os.replace
    if os.environ.get("HOP_FAST_TIMEOUT"):
        original_monotonic = time.monotonic
        # 只缩短协议时钟，真实工具超时和资源回收仍执行原实现。
        time.monotonic = lambda: original_monotonic() * 100

    def replace(stage, destination):
        original_replace(stage, destination)
        if os.fspath(destination) != os.environ["HOP_STATE"] or namespace.get("phase") != "active":
            return
        inventory = Path(os.environ["HOP_FIXTURE"])
        value = json.loads(inventory.read_text())
        kind = value.pop("active_injection", None)
        if kind:
            OWNERSHIP["post_change"](value, kind)
            inventory.write_text(json.dumps(value))

    os.replace = replace
    sys.argv = arguments
    exec(compile(body, "<port-hopping-guarded-fixture>", "exec"), namespace)


def main():
    source = (ROOT / "docker/images/net/entrypoint.sh").read_text()
    assert source.count("\nport-hopping-guarded)\n") == 1
    guarded_case = source.split("\nport-hopping-guarded)\n", 1)[1].split("\n    ;;", 1)[0]
    assert '    port_hopping_resources guarded "$@"' in guarded_case
    assert '    port_hopping_resources run "$@"' not in guarded_case
    assert source.count("\nport-hopping-supervised)\n") == 1
    supervised_case = source.split("\nport-hopping-supervised)\n", 1)[1].split("\n    ;;", 1)[0]
    assert '    port_hopping_resources supervised "$@"' in supervised_case
    with tempfile.TemporaryDirectory(prefix="padm-hopping-guarded.") as directory:
        work = Path(directory)
        functions = work / "functions.sh"
        functions.write_text(source.split('case "${1:-idle}" in')[0])
        binaries = work / "bin"
        binaries.mkdir()
        for name in (*FAMILIES, "ip", "nft", "ss"):
            binary = binaries / name
            driver = SCRIPT if name == "ip" else SCRIPT.with_name("port-hopping-ownership.py")
            binary.write_text(f'#!/bin/sh\nexec python3 "{driver}" tool "{name}" "$@"\n')
            binary.chmod(0o755)
        adapter = binaries / "python3"
        adapter.write_text(
            '#!/bin/sh\nif [ "${1:-}" = /dev/fd/3 ] && [ "${3:-}" = guarded -o "${3:-}" = supervised ]; then\n'
            f'    exec /usr/bin/python3 "{SCRIPT}" python "$@"\n'
            'fi\nexec /usr/bin/python3 "$@"\n')
        adapter.chmod(0o755)

        def run(name, point=None, fault=None, signum=None, injection=None, operation="guarded"):
            case = work / name
            case.mkdir()
            root = case / "state"
            root.mkdir(mode=0o700)
            state, lock = root / "port-hopping.state", root / ".port-hopping.lock"
            inventory, commands = case / "fixture.json", case / "commands.jsonl"
            inventory.write_text(json.dumps({**BASE, **(injection or {})}))
            commands.write_text("")
            environment = dict(os.environ, PATH=f"{binaries}:{os.environ['PATH']}",
                               HOP_FIXTURE=str(inventory), HOP_COMMANDS=str(commands),
                               HOP_STATE=str(state), HOP_FAST_TIMEOUT="1" if fault == "timeout" else "")
            process = subprocess.Popen(["sh", "-c",
                '. "$1"; STATE_ROOT=$2; operation=$3; shift 3; port_hopping_resources "$operation" "$@"',
                "test", str(functions), str(root), operation, *VALUES],
                env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, start_new_session=True)
            phases, nonces, sequences = [], [], []
            supervised = operation == "supervised"
            digest, request = None, None
            changed = signalled = replayed = False
            retained_lock = retained_state = retained_rules = None
            previous_response = None

            def send(value):
                raw = json.dumps(value, separators=(",", ":")).encode("ascii") + b"\n"
                process.stdin.write(raw)
                process.stdin.flush()
                return raw

            def change():
                nonlocal retained_lock, retained_state, retained_rules
                value = json.loads(inventory.read_text())
                if fault == "conflict":
                    OWNERSHIP["post_change"](value, "ip6tables")
                elif fault == "read-fail":
                    value["post_failure"] = "nft"
                elif fault == "address":
                    value["missing_address"] = True
                elif fault == "lock":
                    replacement = root / ".replacement"
                    replacement.touch(mode=0o600)
                    os.replace(replacement, lock)
                    retained_lock = (lock.stat().st_dev, lock.stat().st_ino)
                elif fault == "state":
                    replacement = root / ".replacement"
                    replacement.write_bytes(state.read_bytes())
                    replacement.chmod(0o600)
                    os.replace(replacement, state)
                    retained_state = (state.stat().st_dev, state.stat().st_ino, state.read_bytes())
                elif fault == "cleanup":
                    value["listing_failure"] = "iptables"
                elif fault == "cleanup-signal":
                    value["term_on_listing"] = "iptables"
                elif fault == "rules":
                    value["ip6tables"].append(value["ip6tables"][-1])
                    retained_rules = value["ip6tables"].copy()
                inventory.write_text(json.dumps(value))

            try:
                while True:
                    assert select.select([process.stdout], [], [], 8)[0], (name, phases)
                    raw = process.stdout.readline()
                    if not raw:
                        break
                    frame = json.loads(raw)
                    phase = frame["phase"]
                    phases.append(phase)
                    assert type(frame["v"]) is int and frame["v"] == 1
                    assert len(frame["nonce"]) == 64
                    if phase == "running":
                        assert supervised and type(frame["seq"]) is int
                        assert frame["seq"] == len(sequences) + 1, (name, frame, sequences)
                        sequences.append(frame["seq"])
                        assert set(frame) == {
                            "v", "phase", "nonce", "child_id", "request_sha256", "seq"}
                    elif phase != "challenge":
                        assert set(frame) == {"v", "phase", "nonce", "child_id", "request_sha256"}
                    if phase == "closed":
                        assert not supervised, (name, "supervised emitted finite closed")
                        assert not state.exists(), (name, "closed before cleanup")
                        assert frame["nonce"] == nonces[-1]
                        break
                    assert frame["nonce"] not in nonces
                    nonces.append(frame["nonce"])
                    if phase == "challenge":
                        assert frame["host"] == HOST and not state.exists()
                        request = PROBE["request"](frame)
                        digest = hashlib.sha256(json.dumps(
                            request, separators=(",", ":")).encode("ascii")).hexdigest()
                        response = request
                    else:
                        assert frame["child_id"] == request["child_id"]
                        assert frame["request_sha256"] == digest
                        response = {**frame, "phase": {
                            "ready": "write", "written": "finalize",
                            "active": "continue" if supervised else "close",
                            "running": "continue"}[phase]}
                    if replayed:
                        break
                    with lock.open("rb") as held:
                        try:
                            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        except BlockingIOError:
                            pass
                        else:
                            raise AssertionError((name, "gate released net flock"))
                    if phase in {"written", "active", "running"}:
                        owner = dict(line.split("=", 1) for line in state.read_text().splitlines())
                        assert owner["phase"] == ("intent" if phase == "written" else "active")
                        value = json.loads(inventory.read_text())
                        assert all(value[family] == OWNERSHIP["table"](
                            family, "full", owner=owner) for family in FAMILIES), (name, value)
                    else:
                        assert not state.exists()
                        assert not OWNERSHIP["mutations"]([
                            json.loads(row) for row in commands.read_text().splitlines()])
                    if (phase == point and not changed and
                            (fault != "seq-replay" or len(sequences) == 2)):
                        changed = True
                        if signum:
                            process.send_signal(signum)
                            signalled = True
                            process.wait(timeout=8)
                            break
                        if fault == "timeout":
                            process.wait(timeout=8)
                            break
                        if fault == "eof":
                            process.stdin.close()
                            process.stdin = None
                            break
                        if fault == "nonce":
                            response = {**response, "nonce": "0" * 64}
                        elif fault == "digest":
                            response = {**response, "request_sha256": "0" * 64}
                        elif fault == "seq":
                            response = {**response, "seq": frame["seq"] + 1}
                        elif fault == "seq-bool":
                            response = {**response, "seq": True}
                        elif fault == "seq-replay":
                            response = previous_response
                        elif fault == "half":
                            process.stdin.write(b"{")
                            process.stdin.flush()
                            process.stdin.close()
                            process.stdin = None
                            break
                        elif fault == "order":
                            response = {**response, "phase": "finalize" if phase == "ready" else "write"}
                        elif fault == "bool":
                            response = {**response, "v": True}
                        elif fault == "extra-key":
                            response = {**response, "extra": True}
                        elif fault == "oversized":
                            process.stdin.write(b"x" * 4097)
                            process.stdin.flush()
                            break
                        elif fault == "replay":
                            # 旧阶段 nonce 无法预先通过下一道新挑战。
                            send(response)
                            send(response)
                            replayed = True
                            continue
                        else:
                            change()
                    send(response)
                    previous_response = response
                    if supervised and phase == "running" and not point and len(sequences) == 4:
                        process.stdin.close()
                        process.stdin = None
                        break
                    if supervised and phase == "active" and fault == "window-eof":
                        process.stdin.close()
                        process.stdin = None
                        break
                    if phase == "active" and not supervised:
                        if fault == "tail":
                            process.stdin.write(b"{}\n")
                            process.stdin.flush()
                        # close 帧完整到达仍不能报告 closed，必须等待 EOF。
                        assert not select.select([process.stdout], [], [], 0.1)[0], (name, phases)
                        assert process.poll() is None
                        process.stdin.close()
                        process.stdin = None
                output, error = process.communicate(timeout=10)
                success = (name == "success" or (
                    point == "active" and fault in {"conflict", "address"})) if not supervised else (
                        fault == "window-eof" or not point or
                        point in {"active", "running"} and fault == "eof")
                expected = 128 + signum if signalled else (
                    143 if fault == "cleanup-signal" else 0 if success else 1)
                assert process.returncode == expected, (
                    name, process.returncode, phases, output, error)
                assert not output
                if success:
                    expected_phases = ["challenge", "ready", "written", "active"]
                    if supervised:
                        if point == "running":
                            expected_phases.append("running")
                        elif not point and fault != "window-eof":
                            expected_phases.extend(["running"] * 4)
                    else:
                        expected_phases.append("closed")
                    assert phases == expected_phases, (name, phases)
                    assert not error
                else:
                    assert "closed" not in phases and error, (name, phases, error)
                    if point:
                        assert changed, (name, point, phases)
                current = json.loads(inventory.read_text())
                if retained_lock or retained_state or retained_rules or fault == "cleanup" or (
                        injection and injection.get("active_injection") == "lock"):
                    assert state.exists(), (name, "lost ownership evidence")
                    if retained_lock:
                        assert (lock.stat().st_dev, lock.stat().st_ino) == retained_lock
                    if retained_state:
                        assert (state.stat().st_dev, state.stat().st_ino, state.read_bytes()) == retained_state
                    if retained_rules:
                        assert current["ip6tables"] == retained_rules
                else:
                    assert not state.exists(), (name, state.read_bytes() if state.exists() else b"")
                    for family in FAMILIES:
                        expected_table = BASE[family].copy()
                        if family == "ip6tables" and fault == "conflict":
                            expected_table.append("-A OUTPUT -p udp -m udp --dport 36561 -j DNAT "
                                                  "--to-destination 192.0.2.1:9")
                        if injection and injection.get("active_injection") == family:
                            expected_table.append("-A OUTPUT -p udp -m udp --dport 36561 -j DNAT "
                                                  "--to-destination 192.0.2.1:9")
                        assert current[family] == expected_table, (name, family, current[family])
                metadata = lock.stat()
                assert stat.S_IMODE(metadata.st_mode) == 0o600 and metadata.st_size == 0
            finally:
                (case / "gate.release").touch()
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                process.communicate(timeout=5)

        cases = [("success",)]
        for phase in ("challenge", "ready", "written", "active"):
            cases.extend([
                (f"{phase}-eof", phase, "eof"),
                (f"{phase}-nonce", phase, "nonce"),
                (f"{phase}-int", phase, None, signal.SIGINT),
                (f"{phase}-term", phase, None, signal.SIGTERM),
            ])
        for phase in ("ready", "written"):
            for fault in ("digest", "order", "bool", "extra-key", "replay", "oversized"):
                cases.append((f"{phase}-{fault}", phase, fault))
        for phase in ("written", "active"):
            for fault in ("conflict", "address", "lock", "state"):
                cases.append((f"{phase}-{fault}", phase, fault))
        cases.extend([
            ("tail", "active", "tail"),
            ("cleanup", "active", "cleanup"),
            ("cleanup-signal", "active", "cleanup-signal"),
        ])
        for family in FAMILIES:
            cases.extend([
                ("write-fail-" + family, None, None, None, {"fail_hook": family}),
                ("active-conflict-" + family, None, None, None, {"active_injection": family}),
            ])
        cases.extend([
            ("active-lock-replaced", None, None, None, {"active_injection": "lock"}),
            ("written-read-fail", "written", "read-fail"),
            ("written-timeout", "written", "timeout"),
        ])
        supervised_cases = [
            ("supervised-success", None, None),
            ("supervised-active-eof", "active", "eof"),
            ("supervised-window-eof", "active", "window-eof"),
            ("supervised-running-eof", "running", "eof"),
            ("supervised-ready-eof", "ready", "eof"),
            ("supervised-active-half", "active", "half"),
            ("supervised-window-replay", "active", "replay"),
        ]
        for fault in ("seq", "seq-bool", "seq-replay", "nonce", "digest", "half", "conflict",
                      "address", "lock", "state", "rules", "timeout", "cleanup", "cleanup-signal"):
            supervised_cases.append(("supervised-running-" + fault, "running", fault))
        cases.extend([(*arguments, None, None, "supervised") for arguments in supervised_cases])
        for signum in (signal.SIGINT, signal.SIGTERM):
            cases.append((f"supervised-running-signal-{signum}", "running", None,
                          signum, None, "supervised"))
        # 场景目录与进程组各自独立；固定两个 worker，不扩大本机回归槽位。
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            for result in pool.map(lambda arguments: run(*arguments), cases):
                assert result is None
    print(f"docker-port-hopping-guarded-ok: {len(cases)} finite/supervised gate and cleanup cases")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "tool":
        tool()
    elif len(sys.argv) > 1 and sys.argv[1] == "python":
        python()
    else:
        main()
