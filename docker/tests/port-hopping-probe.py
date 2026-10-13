#!/usr/bin/env python3
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import select
import signal
import socket
import stat
import subprocess
import sys
import tempfile


SCRIPT = Path(__file__).resolve()
ROOT = SCRIPT.parents[2]
HOST = "0123456789ab"
VALUES = ("36561", "36562", "35461", "198.18.1.1", "2001:db8:1::1")
BASE = {
    "iptables": "-P PREROUTING ACCEPT\n-P INPUT ACCEPT\n-P OUTPUT ACCEPT\n"
                "-P POSTROUTING ACCEPT",
    "ip6tables": "-P PREROUTING ACCEPT\n-P INPUT ACCEPT\n-P OUTPUT ACCEPT\n"
                 "-P POSTROUTING ACCEPT",
    "nft": {"nftables": []},
    "ss": "",
    "ip": [{"addr_info": [{"local": VALUES[3]}, {"local": VALUES[4]}]}],
}


def tool():
    current = json.loads(Path(os.environ["HOP_FIXTURE"]).read_text())
    name, *args = sys.argv[2:]
    with Path(os.environ["HOP_COMMANDS"]).open("a") as stream:
        stream.write(json.dumps([name, *args]) + "\n")
    if name in {"iptables", "ip6tables"}:
        if args == ["--version"]:
            print("iptables v1.8.11 (nf_tables)")
        elif args == ["-w", "-t", "nat", "-S"]:
            print(current[name])
        else:
            sys.exit(99)
    else:
        expected = {"ip": ["-j", "address", "show"], "nft": ["-j", "list", "ruleset"],
                    "ss": ["-H", "-u", "-a", "-n"]}
        if args != expected[name]:
            sys.exit(99)
        if name == "ss":
            sys.stdout.write(current[name])
        else:
            print(json.dumps(current[name]))


def python():
    arguments = sys.argv[2:]
    assert arguments[0] == "/dev/fd/3" and arguments[2] == "probe", arguments
    body = Path(arguments[0]).read_text()
    socket.gethostname = lambda: HOST
    sys.argv = arguments
    exec(compile(body, "<port-hopping-probe-fixture>", "exec"), {"__name__": "__main__"})


def request(challenge):
    return {
        "v": 1, "nonce": challenge["nonce"], "parent_pid": os.getpid(),
        "parent_lock_sha256": "a" * 64, "startup_sha256": "b" * 64,
        "child_id": HOST + "c" * 52, "image_id": "sha256:" + "d" * 64,
        "target": {
            "container_id": "e" * 64, "image_id": "sha256:" + "f" * 64,
            "started_at": "2026-10-13T05:00:00.123456789Z", "restart_count": 0,
            "listener_id": "hy2-main", "range_start": int(VALUES[0]),
            "range_end": int(VALUES[1]), "target_port": int(VALUES[2]),
            "ipv4": VALUES[3], "ipv6": VALUES[4],
        },
    }


def main():
    source = (ROOT / "docker/images/net/entrypoint.sh").read_text()
    assert 'exec python3 /dev/fd/3 "$STATE_ROOT" "$@"' in source
    count = 0
    with tempfile.TemporaryDirectory(prefix="padm-hopping-probe.") as directory:
        work = Path(directory)
        functions = work / "functions.sh"
        functions.write_text(source.split('case "${1:-idle}" in')[0])
        binaries = work / "bin"
        binaries.mkdir()
        for name in ("iptables", "ip6tables", "ip", "nft", "ss"):
            binary = binaries / name
            binary.write_text(f'#!/bin/sh\nexec python3 "{SCRIPT}" tool "{name}" "$@"\n')
            binary.chmod(0o755)
        adapter = binaries / "python3"
        adapter.write_text(
            '#!/bin/sh\nif [ "${1:-}" = /dev/fd/3 ] && [ "${3:-}" = probe ]; then\n'
            f'    exec /usr/bin/python3 "{SCRIPT}" python "$@"\n'
            'fi\nexec /usr/bin/python3 "$@"\n')
        adapter.chmod(0o755)

        def run(name, change=None, edit=None, values=VALUES, inventory=None, signum=None):
            nonlocal count
            case = work / name
            case.mkdir()
            state = case / "state"
            state.mkdir(mode=0o700)
            fixture, commands = case / "fixture.json", case / "commands.jsonl"
            fixture.write_text(json.dumps(inventory or BASE))
            commands.write_text("")
            environment = dict(os.environ, PATH=f"{binaries}:{os.environ['PATH']}",
                               HOP_FIXTURE=str(fixture), HOP_COMMANDS=str(commands))
            process = subprocess.Popen(["sh", "-c",
                '. "$1"; STATE_ROOT=$2; shift 2; port_hopping_resources probe "$@"',
                "test", str(functions), str(state), *values],
                env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, start_new_session=True)
            lock = state / ".port-hopping.lock"
            expected_ack = name.startswith("success")
            baseline = fixture.read_bytes()
            try:
                assert select.select([process.stdout], [], [], 8)[0], name
                line = process.stdout.readline()
                challenge = json.loads(line) if line else None
                if challenge:
                    assert set(challenge) == {"v", "phase", "nonce", "host"}
                    assert challenge["v"] == 1 and challenge["phase"] == "challenge"
                    assert challenge["host"] == HOST
                    assert re.fullmatch(r"[a-f0-9]{64}", challenge["nonce"])
                    metadata = lock.stat()
                    assert stat.S_IMODE(metadata.st_mode) == 0o600 and metadata.st_size == 0
                    with lock.open("rb") as held:
                        try:
                            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        except BlockingIOError:
                            pass
                        else:
                            raise AssertionError((name, "probe did not hold its lock"))
                    value = request(challenge)
                    if change:
                        change(value)
                    data = json.dumps(value, separators=(",", ":")).encode("ascii") + b"\n"
                    if edit:
                        data = edit(data)
                    if name == "state-appeared":
                        owner = state / "port-hopping.state"
                        owner.write_bytes(b"foreign owner\n")
                        owner.chmod(0o600)
                    elif name == "lock-replaced":
                        replacement = state / ".replacement"
                        replacement.touch(mode=0o600)
                        os.replace(replacement, lock)
                        metadata = lock.stat()
                    elif name == "conflict-appeared":
                        current = json.loads(fixture.read_text())
                        current["ip6tables"] += ("\n-A OUTPUT -p udp --dport 36561 "
                                                "-j DNAT --to-destination [2001:db8::1]:9")
                        fixture.write_text(json.dumps(current))
                        baseline = fixture.read_bytes()
                    process.stdin.write(data)
                    process.stdin.flush()
                    if signum is not None:
                        # 完整请求仍不关闭输入，验证 EOF 门禁和信号退出。
                        assert not select.select([process.stdout], [], [], 0.1)[0], name
                        process.send_signal(signum)
                    else:
                        process.stdin.close()
                        process.stdin = None
                output, error = process.communicate(timeout=8)
                expected = 128 + signum if signum else (0 if expected_ack else 1)
                assert process.returncode == expected, (name, process.returncode, output, error)
                if expected_ack:
                    ack = json.loads(output)
                    assert set(ack) == {"v", "phase", "nonce", "child_id", "request_sha256"}
                    assert ack == {
                        "v": 1, "phase": "ack", "nonce": challenge["nonce"],
                        "child_id": value["child_id"],
                        "request_sha256": hashlib.sha256(data[:-1]).hexdigest(),
                    }, ack
                    assert not error
                else:
                    assert not output and error, (name, output, error)
                if name in {"bad-ports", "nonlocal"}:
                    assert challenge is None and not lock.exists()
                else:
                    current = lock.stat()
                    assert (current.st_dev, current.st_ino) == (metadata.st_dev, metadata.st_ino)
                    assert current.st_size == 0 and stat.S_IMODE(current.st_mode) == 0o600
                assert fixture.read_bytes() == baseline
                assert sorted(path.name for path in state.iterdir()) == (
                    [".port-hopping.lock", "port-hopping.state"] if name == "state-appeared"
                    else [] if name in {"bad-ports", "nonlocal"} else [".port-hopping.lock"])
                if name == "state-appeared":
                    assert (state / "port-hopping.state").read_bytes() == b"foreign owner\n"
                allowed = {
                    "iptables": [["--version"], ["-w", "-t", "nat", "-S"]],
                    "ip6tables": [["--version"], ["-w", "-t", "nat", "-S"]],
                    "ip": [["-j", "address", "show"]],
                    "nft": [["-j", "list", "ruleset"]],
                    "ss": [["-H", "-u", "-a", "-n"]],
                }
                for row in commands.read_text().splitlines():
                    tool_name, *args = json.loads(row)
                    assert args in allowed[tool_name], row
                count += 1
            finally:
                if process.poll() is None:
                    process.kill()
                process.communicate(timeout=5)

        run("success")
        run("success-time-seconds", lambda value: value["target"].update(
            started_at="2026-10-13T05:00:00Z"))
        run("success-time-short", lambda value: value["target"].update(
            started_at="2026-10-13T05:00:00.1Z"))
        run("invalid-date", lambda value: value["target"].update(
            started_at="2026-02-30T05:00:00.1Z"))
        run("bad-ports", values=("036561", *VALUES[1:]))
        run("nonlocal", inventory={**BASE, "ip": [{"addr_info": [{"local": VALUES[3]}]}]})
        run("nonce", lambda value: value.update(nonce="0" * 64))
        run("child-id", lambda value: value.update(child_id="a" * 63))
        run("digest", lambda value: value.update(startup_sha256="0" * 63))
        run("tuple", lambda value: value["target"].update(range_start=True))
        run("duplicate-key", edit=lambda data: data.replace(b'{"v":1,', b'{"v":1,"v":1,', 1))
        run("nul", edit=lambda data: data[:-1] + b"\0\n")
        run("extra-key", lambda value: value.update(extra=1))
        run("missing-lf", edit=lambda data: data[:-1])
        run("extra-line", edit=lambda data: data + b"{}\n")
        run("oversized", edit=lambda data: data[:-1] + b" " * 4096 + b"\n")
        for name in ("state-appeared", "lock-replaced", "conflict-appeared"):
            run(name)
        run("interrupt", signum=signal.SIGINT)
        run("terminate", signum=signal.SIGTERM)
    print(f"docker-port-hopping-probe-ok: {count} read-only protocol and identity cases")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "tool":
        tool()
    elif len(sys.argv) > 1 and sys.argv[1] == "python":
        python()
    else:
        main()
