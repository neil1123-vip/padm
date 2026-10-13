#!/usr/bin/env python3
from contextlib import contextmanager
import fcntl
import itertools
import json
import os
from pathlib import Path
import shlex
import signal
import stat
import subprocess
import sys
import tempfile
import time


SCRIPT = Path(__file__).resolve()
ROOT = SCRIPT.parents[2]
TOKEN = "0123456789abcdef0123456789abcdef"
CHAIN = "padm-hop-" + TOKEN[:12]
COMMENT = "padm-hop:" + TOKEN
FAMILIES = ("iptables", "ip6tables")
RUN_VALUES = ("36561", "36562", "35461", "198.18.1.1", "2001:db8:1::1")
STATE = (
    f"schema_version=1\ntoken={TOKEN}\nchain={CHAIN}\n"
    "start=36561\nend=36562\ntarget_port=35461\n"
    "ipv4=198.18.1.1\nipv6=2001:db8:1::1\nphase=active\n"
)
BASE = {
    "iptables": [
        "-P PREROUTING ACCEPT", "-P INPUT ACCEPT", "-P OUTPUT ACCEPT",
        "-P POSTROUTING ACCEPT", "-N DOCKER",
        "-A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER",
        "-A DOCKER -p udp -m udp --dport 35461 -j DNAT "
        "--to-destination 172.18.0.2:35461",
        "-A POSTROUTING -s 172.18.0.0/16 ! -o br0 -j MASQUERADE",
    ],
    "ip6tables": [
        "-P PREROUTING ACCEPT", "-P INPUT ACCEPT", "-P OUTPUT ACCEPT",
        "-P POSTROUTING ACCEPT",
    ],
}


def rules(family, single=False, owner=None):
    owner = owner or dict(line.split("=", 1) for line in STATE.splitlines())
    chain, comment = owner["chain"], "padm-hop:" + owner["token"]
    ip = owner["ipv4"] if family == "iptables" else owner["ipv6"]
    address = ip + ("/32" if family == "iptables" else "/128")
    target = f"{ip}:{owner['target_port']}" if family == "iptables" else f"[{ip}]:{owner['target_port']}"
    selected = owner["start"] if single or owner["start"] == owner["end"] else (
        owner["start"] + ":" + owner["end"])
    match = f"-d {address} -p udp -m udp --dport {selected} -m comment --comment {comment}"
    return (
        f"-A PREROUTING {match} -j {chain}",
        f"-A {chain} {match} -j DNAT --to-destination {target}",
        f"-A {chain} -m comment --comment {comment} -j RETURN",
    )


def table(family, shape, single=False, owner=None):
    value = BASE[family].copy()
    if shape == "none":
        return value
    hook, dnat, sentinel = rules(family, single, owner)
    value.insert(4, "-N " + (owner["chain"] if owner else CHAIN))
    if shape == "empty":
        return value
    if shape == "full":
        first_rule = next((index for index, line in enumerate(value)
                           if line.startswith("-A PREROUTING ")), len(value))
        value.insert(first_rule, hook)
    if shape in {"full", "detached"}:
        value.append(dnat)
    value.append(sentinel)
    return value


def tool():
    fixture_path = Path(os.environ["HOP_FIXTURE"])
    fixture = json.loads(fixture_path.read_text())
    family, *args = sys.argv[2:]
    with Path(os.environ["HOP_COMMANDS"]).open("a") as output:
        output.write(json.dumps([family, *args]) + "\n")
    if family in {"ip", "nft", "ss"}:
        expected = {"ip": ["-j", "address", "show"], "nft": ["-j", "list", "ruleset"],
                    "ss": ["-H", "-u", "-a", "-n"]}
        if args != expected[family]:
            sys.exit(99)
        if family == "nft":
            scans = fixture.get("conflict_scans", 0) + 1
            fixture["conflict_scans"] = scans
            fixture_path.write_text(json.dumps(fixture))
        if fixture.get("post_failure") == family:
            print("fixture post-start inspection failed", file=sys.stderr)
            sys.exit(1)
        if family == "ip":
            print(json.dumps([{"ifindex": 1, "ifname": "eth0", "addr_info": [
                {"family": "inet", "local": RUN_VALUES[3], "prefixlen": 24},
                {"family": "inet6", "local": RUN_VALUES[4], "prefixlen": 64}]}]))
        elif family == "nft":
            print(json.dumps(fixture.get("nft", {"nftables": []})))
        else:
            sys.stdout.write(fixture.get("ss", ""))
            if fixture.get("conflict_scans", 0) >= 3:
                (fixture_path.parent / "post-ss.done").touch()
        return
    if family not in FAMILIES:
        sys.exit(99)
    if args == ["--version"]:
        print("iptables v1.8.11 (nf_tables)")
        return
    if args[:3] != ["-w", "-t", "nat"] or len(args) < 4:
        sys.exit(99)
    action, *arguments = args[3:]
    if action == "-S" and not arguments:
        if fixture.get("listing_failure") == family:
            print("fixture listing failed", file=sys.stderr)
            sys.exit(1)
        if fixture.get("listing_warning") == family:
            print("fixture listing incomplete", file=sys.stderr)
        if fixture.get("term_on_listing") == family:
            del fixture["term_on_listing"]
            fixture_path.write_text(json.dumps(fixture))
            os.kill(os.getppid(), signal.SIGTERM)
        print("\n".join(fixture[family]))
        if family == "ip6tables" and (fixture_path.parent / "post-ss.done").exists():
            (fixture_path.parent / "post-audit.done").touch()
        return
    if action not in {"-D", "-X", "-A", "-N", "-I"} or not arguments:
        sys.exit(99)
    current = fixture[family]
    if fixture.get("fail_hook") == family and action == "-I" and arguments[0] == "PREROUTING":
        del fixture["fail_hook"]
        fixture_path.write_text(json.dumps(fixture))
        print("fixture insert hook failed", file=sys.stderr)
        sys.exit(1)
    if action == "-N":
        if len(arguments) != 1 or "-N " + arguments[0] in current:
            sys.exit(1)
        current.insert(4, "-N " + arguments[0])
    elif action == "-D":
        wanted = ["-A", *arguments]
        indices = [index for index, line in enumerate(current)
                   if shlex.split(line) == wanted]
        if len(indices) != 1:
            print("fixture exact rule missing", file=sys.stderr)
            sys.exit(1)
        del current[indices[0]]
    elif action == "-X":
        chain = arguments[0]
        if len(arguments) != 1 or "-N " + chain not in current:
            sys.exit(1)
        if fixture.get("fail_x_once") == family:
            del fixture["fail_x_once"]
            fixture_path.write_text(json.dumps(fixture))
            print("fixture delete chain failed", file=sys.stderr)
            sys.exit(1)
        if any(line.startswith("-A " + chain + " ") or
               shlex.split(line)[-2:] == ["-j", chain] for line in current):
            sys.exit(1)
        current.remove("-N " + chain)
    else:
        chain = arguments[0]
        if "-N " + chain not in current and "-P " + chain + " ACCEPT" not in current:
            sys.exit(1)
        if action == "-I":
            if len(arguments) < 3 or arguments[1] != "1":
                sys.exit(99)
            fallback = next((index for index, line in enumerate(current)
                             if chain == "PREROUTING" and line.startswith("-A ")), len(current))
            position = next((index for index, line in enumerate(current)
                             if line.startswith("-A " + chain + " ")), fallback)
            current.insert(position, " ".join(["-A", chain, *arguments[2:]]))
        else:
            current.append(" ".join(["-A", *arguments]))
    if fixture.get("replace_state"):
        mode = fixture.pop("replace_state")
        state = Path(os.environ["HOP_STATE"])
        replacement = state.with_suffix(".replacement")
        value = state.read_text()
        if mode == "token":
            value = value.replace(TOKEN, "f" * 32)
        replacement.write_text(value)
        replacement.chmod(0o600)
        os.replace(replacement, state)
    if fixture.pop("replace_lock", False):
        state_root = Path(os.environ["HOP_STATE"]).parent
        replacement = state_root / ".lock-replacement"
        replacement.touch(mode=0o600)
        os.replace(replacement, state_root / ".port-hopping.lock")
    if action == "-I" and arguments[0] == "PREROUTING" and family == "ip6tables":
        if fixture.get("post_conflict") and not fixture.get("post_commit"):
            post_change(fixture, fixture["post_conflict"])
    gate = fixture.get("gate", {})
    paused = gate.get("family") == family and gate.get("action") == action and (
        arguments[0] == "PREROUTING" if gate.get("hook") else
        arguments[0].startswith("padm-hop-"))
    if paused:
        del fixture["gate"]
    fixture_path.write_text(json.dumps(fixture))
    if paused:
        # 门禁位于写入之后，信号测试不依赖机器速度推测启动位置。
        gate_root = fixture_path.parent
        (gate_root / "gate.entered").write_text(str(os.getpid()))
        deadline = time.monotonic() + 8
        while not (gate_root / "gate.release").exists():
            if time.monotonic() >= deadline:
                print("fixture gate timed out", file=sys.stderr)
                sys.exit(1)
            time.sleep(0.02)

def post_change(fixture, kind):
    if kind in FAMILIES:
        fixture[kind].append(
            "-A OUTPUT -p udp -m udp --dport 36561 -j DNAT --to-destination 192.0.2.1:9")
    elif kind == "udp":
        fixture["ss"] = "UNCONN 0 0 0.0.0.0:36562 0.0.0.0:*"
    elif kind == "nft":
        fixture["nft"] = {"nftables": [{"chain": {
            "family": "inet", "table": "foreign", "name": "foreign-nat",
            "type": "nat", "hook": "prerouting", "prio": -100}}]}
    elif kind == "read-fail":
        fixture["post_failure"] = "nft"
    elif kind == "lock":
        replacement = Path(os.environ["HOP_STATE"]).parent / ".post-lock"
        replacement.touch(mode=0o600)
        os.replace(replacement, replacement.parent / ".port-hopping.lock")
        metadata = (replacement.parent / ".port-hopping.lock").stat()
        replacement.parent.parent.joinpath("post-lock.json").write_text(
            json.dumps([metadata.st_dev, metadata.st_ino]))
    else:
        raise AssertionError(kind)


def run_python():
    arguments = sys.argv[2:]
    state_path = Path(os.environ["HOP_STATE"])
    fixture = json.loads(Path(os.environ["HOP_FIXTURE"]).read_text())
    fault = fixture.get("commit_failure")
    post_commit = fixture.get("post_commit")
    if (len(arguments) != 8 or arguments[:3] != ["-", str(state_path.parent), "run"]
            or not (fault or post_commit)):
        os.execv("/usr/bin/python3", ["python3", *arguments])
    body = sys.stdin.read()
    namespace = {"__name__": "__main__"}
    original_mkstemp, original_fsync, original_replace = tempfile.mkstemp, os.fsync, os.replace
    triggered = False

    def inject(point):
        nonlocal triggered
        if not fault or triggered or point != fault["point"] or namespace.get("phase") != fault["phase"]:
            return False
        triggered = True
        marker = Path(os.environ["HOP_FIXTURE"]).parent / "commit.fault.json"
        marker.write_text(json.dumps({
            **fault, "state": namespace["state_text"]().decode("ascii")}))
        return True

    def mkstemp(*args, **kwargs):
        if inject("create"):
            raise OSError("fixture state temporary creation failed")
        descriptor, stage = original_mkstemp(*args, **kwargs)
        if inject("write"):
            # 只替换本次临时文件描述符，使生产 write/flush 遇到真实 EBADF。
            readonly = os.open(stage, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
            os.close(descriptor)
            descriptor = readonly
        return descriptor, stage

    def fsync(descriptor):
        point = "directory-fsync" if stat.S_ISDIR(os.fstat(descriptor).st_mode) else "file-fsync"
        if inject(point):
            raise OSError("fixture state " + point + " failed")
        return original_fsync(descriptor)

    def replace(stage, destination):
        if os.fspath(destination) != str(state_path):
            return original_replace(stage, destination)
        if inject("replace"):
            raise OSError("fixture state replace failed")
        original_replace(stage, destination)
        if post_commit and namespace.get("phase") == "active":
            inventory = Path(os.environ["HOP_FIXTURE"])
            current = json.loads(inventory.read_text())
            owner = dict(line.split("=", 1) for line in namespace["state_text"]().decode().splitlines())
            assert all(current[family] == table(family, "full", owner=owner)
                       for family in FAMILIES), current
            post_change(current, current["post_conflict"])
            inventory.write_text(json.dumps(current))
            inventory.with_name("post-commit.done").touch()
        if inject("replace-state"):
            # 同字节替换仍改变 inode，读回不能把未知归属刷新为本轮 baseline。
            descriptor, replacement = original_mkstemp(
                prefix=".port-hopping-state.replaced.", dir=state_path.parent)
            try:
                with os.fdopen(descriptor, "wb") as stream:
                    stream.write(state_path.read_bytes())
                original_replace(replacement, state_path)
            finally:
                if os.path.lexists(replacement):
                    os.unlink(replacement)

    tempfile.mkstemp, os.fsync, os.replace = mkstemp, fsync, replace
    sys.argv = arguments
    exec(compile(body, "<port-hopping-fixture>", "exec"), namespace)


def mutations(commands):
    return [row for row in commands if row[1:4] == ["-w", "-t", "nat"]
            and len(row) > 4 and row[4] != "-S"]


def expected_cleanup(family, shape, single=False, owner=None):
    hook, dnat, sentinel = rules(family, single, owner)
    lines = ([hook] if shape == "full" else [])
    lines += [dnat] if shape in {"full", "detached"} else []
    lines += [sentinel] if shape in {"full", "detached", "sentinel"} else []
    result = [[family, "-w", "-t", "nat", "-D", *shlex.split(line)[1:]]
              for line in lines]
    if shape != "none":
        result.append([family, "-w", "-t", "nat", "-X", owner["chain"] if owner else CHAIN])
    return result


def expected_creation(owner):
    result = []
    for family in FAMILIES:
        hook, dnat, sentinel = [shlex.split(line) for line in rules(family, owner=owner)]
        result.extend([
            [family, "-w", "-t", "nat", "-N", owner["chain"]],
            [family, "-w", "-t", "nat", "-A", *sentinel[1:]],
            [family, "-w", "-t", "nat", "-I", owner["chain"], "1", *dnat[2:]],
            [family, "-w", "-t", "nat", "-I", "PREROUTING", "1", *hook[2:]],
        ])
    return result


def main():
    source = (ROOT / "docker/images/net/entrypoint.sh").read_text()
    count = 0
    with tempfile.TemporaryDirectory(prefix="padm-hopping-ownership.") as directory:
        work = Path(directory)
        functions = work / "functions.sh"
        functions.write_text(source.split('case "${1:-idle}" in')[0])
        binaries = work / "bin"
        binaries.mkdir()
        for family in (*FAMILIES, "ip", "nft", "ss"):
            binary = binaries / family
            binary.write_text(f'#!/bin/sh\nexec python3 "{SCRIPT}" tool "{family}" "$@"\n')
            binary.chmod(0o755)
        python = binaries / "python3"
        python.write_text(
            '#!/bin/sh\n'
            'if [ -n "${HOP_COMMIT_FAULT:-}" ] && [ "${1:-}" = - ] && [ "${3:-}" = run ]; then\n'
            f'    exec /usr/bin/python3 "{SCRIPT}" python "$@"\n'
            'fi\nexec /usr/bin/python3 "$@"\n')
        python.chmod(0o755)

        def fixture(name, shapes=("full", "full"), phase="active", single=False):
            case = work / name
            case.mkdir()
            state_root = case / "state"
            state_root.mkdir(mode=0o700)
            owner = state_root / "port-hopping.state"
            state = STATE.replace("phase=active", "phase=" + phase)
            owner.write_text(state.replace("end=36562", "end=36561") if single else state)
            owner.chmod(0o600)
            inventory = case / "fixture.json"
            inventory.write_text(json.dumps({
                family: table(family, shape, single)
                for family, shape in zip(FAMILIES, shapes)}))
            commands = case / "commands.jsonl"
            commands.write_text("")
            return state_root, owner, inventory, commands

        def environment(paths):
            return dict(os.environ, PATH=f"{binaries}:{os.environ['PATH']}",
                        HOP_FIXTURE=str(paths[2]), HOP_COMMANDS=str(paths[3]),
                        HOP_STATE=str(paths[1]), HOP_COMMIT_FAULT=(
                            "1" if any(json.loads(paths[2].read_text()).get(key)
                                       for key in ("commit_failure", "post_commit")) else ""))

        def command_rows(paths, running=False):
            rows = [json.loads(line) for line in paths[3].read_text().splitlines()]
            extra = {"ip": ["-j", "address", "show"],
                     "nft": ["-j", "list", "ruleset"], "ss": ["-H", "-u", "-a", "-n"]}
            flags = ("-D", "-X", "-A", "-N", "-I") if running else ("-D", "-X", "-A")
            for family, *args in rows:
                assert (family in FAMILIES and (
                    args == ["--version"] or args == ["-w", "-t", "nat", "-S"] or
                    args[:4] in [["-w", "-t", "nat", flag] for flag in flags])
                    or running and family in extra and args == extra[family]), rows
            return rows

        def invoke(paths, action, accepted, token=TOKEN, values=RUN_VALUES):
            nonlocal count
            state_root, owner, inventory, commands = paths
            commands.write_text("")
            result = subprocess.run(["sh", "-c",
                '. "$1"; STATE_ROOT=$2; shift 2; port_hopping_resources "$@"',
                "test", str(functions), str(state_root), action,
                *(values if action == "run" else (token,))],
                env=environment(paths), capture_output=True, text=True, timeout=10)
            assert result.returncode == (0 if accepted else 1), (
                state_root.parent.name, action, result.returncode, result.stderr)
            assert not result.stdout, (action, result.stdout)
            if not accepted:
                assert result.stderr, (action, "failure without diagnostic")
            rows = command_rows(paths, action == "run")
            count += 1
            return rows

        def readonly(paths, action, accepted, token=TOKEN, values=RUN_VALUES):
            state_root, owner, inventory, _ = paths
            metadata = owner.lstat()
            before = inventory.read_bytes(), owner.read_bytes(), (
                metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_uid,
                metadata.st_gid, metadata.st_size, metadata.st_nlink,
                metadata.st_mtime_ns, metadata.st_ctime_ns)
            lock = state_root / ".port-hopping.lock"
            lock_before = lock.lstat() if lock.exists() else None
            rows = invoke(paths, action, accepted, token, values)
            assert not mutations(rows), rows
            assert inventory.read_bytes() == before[0] and owner.read_bytes() == before[1]
            metadata = owner.lstat()
            assert (metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_uid,
                    metadata.st_gid, metadata.st_size, metadata.st_nlink,
                    metadata.st_mtime_ns, metadata.st_ctime_ns) == before[2]
            assert (lock.lstat() if lock.exists() else None) == lock_before

        def signal_group(process, signum):
            try:
                os.killpg(process.pid, signum)
            except ProcessLookupError:
                pass

        @contextmanager
        def running(paths, values=RUN_VALUES):
            paths[3].write_text("")
            value = json.loads(paths[2].read_text())
            value["conflict_scans"] = 0
            paths[2].write_text(json.dumps(value))
            for marker in ("post-ss.done", "post-audit.done"):
                (paths[2].parent / marker).unlink(missing_ok=True)
            process = subprocess.Popen(["sh", "-c",
                '. "$1"; STATE_ROOT=$2; shift 2; port_hopping_resources "$@"',
                "test", str(functions), str(paths[0]), "run", *values],
                env=environment(paths), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, start_new_session=True)
            try:
                yield process
            finally:
                # 无论断言是否成功，都释放门禁并回收本次创建的进程组。
                (paths[2].parent / "gate.release").touch()
                signal_group(process, signal.SIGTERM)
                try:
                    process.communicate(timeout=3)
                except subprocess.TimeoutExpired:
                    signal_group(process, signal.SIGKILL)
                    process.communicate(timeout=5)

        def wait_for(process, predicate, label):
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                try:
                    value = predicate()
                    if value:
                        assert process.poll() is None, label
                        return value
                except (FileNotFoundError, json.JSONDecodeError):
                    pass
                if process.poll() is not None:
                    output, error = process.communicate(timeout=5)
                    raise AssertionError((label, process.returncode, output, error))
                time.sleep(0.02)
            raise AssertionError((label, "timed out waiting for fixture"))

        def finish(process, accepted=True, signum=None, killed=False):
            nonlocal count
            if signum is not None:
                process.send_signal(signum)
            output, error = process.communicate(timeout=10)
            expected = -signal.SIGKILL if killed else (0 if accepted else 1)
            assert process.returncode == expected, (process.returncode, output, error)
            assert not output, output
            if not accepted and not killed:
                assert error, "failure without diagnostic"
            count += 1

        def owner_value(paths):
            return dict(line.split("=", 1) for line in paths[1].read_text().splitlines())

        def active(process, paths, values=RUN_VALUES, previous_token=None):
            def ready():
                owner = owner_value(paths)
                return owner if owner["phase"] == "active" and (
                    previous_token is None or owner["token"] != previous_token) and (
                    paths[2].parent / "post-audit.done").exists() else None
            owner = wait_for(process, ready, paths[0].parent.name)
            assert owner["schema_version"] == "1"
            assert len(owner["token"]) == 32 and all(
                character in "0123456789abcdef" for character in owner["token"])
            assert owner["chain"] == "padm-hop-" + owner["token"][:12]
            assert tuple(owner[key] for key in
                         ("start", "end", "target_port", "ipv4", "ipv6")) == tuple(values)
            value = json.loads(paths[2].read_text())
            assert all(value[family] == table(family, "full", owner=owner)
                       for family in FAMILIES), value
            metadata = paths[1].stat()
            assert metadata.st_uid == metadata.st_gid == 0
            assert metadata.st_mode & 0o7777 == 0o600
            return owner

        def fresh(name, **changes):
            paths = fixture(name, ("none", "none"))
            paths[1].unlink()
            value = json.loads(paths[2].read_text())
            value.update(changes)
            paths[2].write_text(json.dumps(value))
            return paths

        def cleaned(paths):
            value = json.loads(paths[2].read_text())
            assert all(value[family] == BASE[family] for family in FAMILIES), value
            assert not paths[1].exists()
            metadata = (paths[0] / ".port-hopping.lock").stat()
            assert metadata.st_uid == metadata.st_gid == 0
            assert metadata.st_mode & 0o7777 == 0o600

        def crash(process, paths):
            process.kill()
            (paths[2].parent / "gate.release").touch()
            signal_group(process, signal.SIGKILL)
            finish(process, killed=True)

        def clean(paths, shapes, single=False):
            state_root, owner, inventory, _ = paths
            rows = invoke(paths, "clean", True)
            written = mutations(rows)
            for family, shape in zip(FAMILIES, shapes):
                assert [row for row in written if row[0] == family] == expected_cleanup(
                    family, shape, single), written
            # 每次删除前重新读取两族，不能仅在清理开始时做一次归属判断。
            read_families = set()
            for row in rows:
                if row[1:] == ["-w", "-t", "nat", "-S"]:
                    read_families.add(row[0])
                elif row in written:
                    assert read_families == set(FAMILIES), rows
                    read_families.clear()
            value = json.loads(inventory.read_text())
            assert all(value[family] == BASE[family] for family in FAMILIES)
            assert not owner.exists()
            lock = state_root / ".port-hopping.lock"
            metadata = lock.stat()
            assert metadata.st_uid == metadata.st_gid == 0 and metadata.st_mode & 0o7777 == 0o600

        for index, shapes in enumerate(itertools.product(
                ("none", "sentinel", "detached", "full"), repeat=2)):
            paths = fixture(f"subset-{index}", shapes, "intent")
            readonly(paths, "audit", True)
        for shapes, phase, accepted in (
            (("full", "full"), "active", True),
            (("full", "full"), "intent", False),
            (("full", "detached"), "active", False),
            (("none", "none"), "active", False),
        ):
            paths = fixture(f"health-{count}", shapes, phase)
            readonly(paths, "health", accepted)
        for shapes in (("full", "full"), ("detached", "sentinel"),
                       ("none", "full"), ("none", "none")):
            paths = fixture(f"clean-{count}", shapes, "intent")
            unrelated = paths[0] / "unrelated.state"
            unrelated.write_text("foreign baseline\n")
            clean(paths, shapes)
            assert unrelated.read_text() == "foreign baseline\n"
        paths = fixture("single-port", single=True)
        readonly(paths, "audit", True)
        readonly(paths, "health", True)
        clean(paths, ("full", "full"), single=True)

        def drift(value, kind, family):
            hook, dnat, sentinel = rules(family)
            current = value[family]
            if kind == "empty":
                current.remove(hook)
                current.remove(dnat)
                current.remove(sentinel)
            elif kind == "no-sentinel":
                current.remove(sentinel)
            elif kind == "extra-reference":
                current.append(f"-A OUTPUT -j {CHAIN}")
            elif kind == "extra-rule":
                current.append(f"-A {CHAIN} -j DROP")
            elif kind == "duplicate-hook":
                current.insert(current.index(hook), hook)
            elif kind == "duplicate-dnat":
                current.insert(current.index(dnat), dnat)
            elif kind == "duplicate-sentinel":
                current.append(sentinel)
            elif kind == "wrong-order":
                current.remove(dnat)
                current.append(dnat)
            elif kind == "not-first-hook":
                current.remove(hook)
                current.append("-A PREROUTING -m addrtype --dst-type LOCAL -j ACCEPT")
                current.append(hook)
            elif kind == "foreign-owner":
                current[current.index(dnat)] = dnat.replace(COMMENT, "padm-hop:" + "f" * 32)
            elif kind == "other-hop":
                current.append("-N padm-hop-ffffffffffff")
            elif kind == "wrong-target":
                current[current.index(dnat)] = dnat.replace("35461", "35462")
            elif kind == "incomplete-listing":
                current.remove("-P INPUT ACCEPT")

        for index, (kind, family) in enumerate(itertools.product(
            ("empty", "no-sentinel", "extra-reference", "extra-rule", "duplicate-hook",
             "duplicate-dnat", "duplicate-sentinel", "wrong-order", "not-first-hook",
             "foreign-owner", "other-hop", "wrong-target", "incomplete-listing"),
            FAMILIES,
        )):
            paths = fixture(f"drift-{index}")
            value = json.loads(paths[2].read_text())
            drift(value, kind, family)
            paths[2].write_text(json.dumps(value))
            readonly(paths, "audit", False)
            before = paths[2].read_bytes(), paths[1].read_bytes()
            rows = invoke(paths, "clean", False)
            assert not mutations(rows) and (paths[2].read_bytes(), paths[1].read_bytes()) == before

        for name in ("symlink", "hardlink", "mode", "uid", "gid", "directory",
                     "directory-gid", "oversize"):
            paths = fixture("metadata-" + name)
            state_root, owner, inventory, _ = paths
            if name == "symlink":
                external = owner.with_name("external.state")
                owner.rename(external)
                owner.symlink_to(external)
            elif name == "hardlink":
                os.link(owner, owner.with_name("other.state"))
            elif name == "mode":
                owner.chmod(0o640)
            elif name == "uid":
                os.chown(owner, 1, 0)
            elif name == "gid":
                os.chown(owner, 0, 1)
            elif name == "directory":
                state_root.chmod(0o770)
            elif name == "directory-gid":
                os.chown(state_root, 0, 1)
            else:
                owner.write_text(STATE + " " * 512)
            readonly(paths, "audit", False)
            rows = invoke(paths, "clean", False)
            assert not mutations(rows)
            assert json.loads(inventory.read_text()) == {family: table(family, "full")
                                                        for family in FAMILIES}

        for index, content in enumerate((
            STATE.replace("schema_version=1", "schema_version=2"),
            STATE.replace(TOKEN, "x" * 32),
            STATE.replace(CHAIN, "padm-hop-ffffffffffff"),
            STATE.replace("phase=active", "phase=unknown"),
            STATE + f"token={TOKEN}\n",
            STATE.replace("phase=active\n", ""),
            STATE + "extra=value\n",
            STATE.rstrip("\n"),
            STATE + "\x00",
            STATE.replace("start=36561", "start=036561"),
            STATE.replace("start=36561", "start=36563"),
            STATE.replace("target_port=35461", "target_port=36562"),
            STATE.replace("ipv4=198.18.1.1", "ipv4=127.0.0.1"),
            STATE.replace("ipv6=2001:db8:1::1", "ipv6=2001:0db8:1::1"),
            STATE.replace("phase=active", "phase=\u4e3b\u52a8"),
        )):
            paths = fixture(f"format-{index}")
            paths[1].write_text(content)
            readonly(paths, "audit", False)
        readonly(fixture("wrong-expected-token"), "audit", False, "f" * 32)
        for kind in ("listing_failure", "listing_warning"):
            paths = fixture(kind)
            value = json.loads(paths[2].read_text())
            value[kind] = "ip6tables"
            paths[2].write_text(json.dumps(value))
            readonly(paths, "audit", False)

        for mode in ("same", "token"):
            paths = fixture("replace-state-" + mode)
            value = json.loads(paths[2].read_text())
            value["replace_state"] = mode
            paths[2].write_text(json.dumps(value))
            rows = invoke(paths, "clean", False)
            assert len(mutations(rows)) == 1 and paths[1].exists(), rows
            assert mutations(rows)[0] == expected_cleanup(mutations(rows)[0][0], "full")[0]

        paths = fixture("replace-lock")
        value = json.loads(paths[2].read_text())
        value["replace_lock"] = True
        paths[2].write_text(json.dumps(value))
        rows = invoke(paths, "clean", False)
        assert len(mutations(rows)) == 1 and paths[1].read_text() == STATE, rows

        for name in ("symlink", "hardlink", "mode", "uid", "gid", "nonempty"):
            paths = fixture("lock-" + name)
            lock = paths[0] / ".port-hopping.lock"
            lock.touch(mode=0o600)
            if name == "symlink":
                external = lock.with_name("external.lock")
                lock.rename(external)
                lock.symlink_to(external)
            elif name == "hardlink":
                os.link(lock, lock.with_name("other.lock"))
            elif name == "mode":
                lock.chmod(0o640)
            elif name == "uid":
                os.chown(lock, 1, 0)
            elif name == "gid":
                os.chown(lock, 0, 1)
            else:
                lock.write_text("foreign lock\n")
            before = paths[2].read_bytes(), paths[1].read_bytes()
            rows = invoke(paths, "clean", False)
            assert not mutations(rows) and (paths[2].read_bytes(), paths[1].read_bytes()) == before

        paths = fixture("delete-chain-failed")
        value = json.loads(paths[2].read_text())
        value["fail_x_once"] = "iptables"
        paths[2].write_text(json.dumps(value))
        rows = invoke(paths, "clean", False)
        assert paths[1].read_text() == STATE
        assert mutations(rows) == expected_cleanup("iptables", "full") + [
            ["iptables", "-w", "-t", "nat", "-A", *shlex.split(rules("iptables")[2])[1:]]
        ], rows
        assert json.loads(paths[2].read_text())["iptables"] == table("iptables", "sentinel")
        readonly(paths, "audit", True)
        clean(paths, ("sentinel", "full"))

        paths = fixture("lock-contention")
        lock = paths[0] / ".port-hopping.lock"
        lock.touch(mode=0o600)
        with lock.open("r+") as held:
            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
            before = paths[2].read_bytes(), paths[1].read_bytes()
            rows = invoke(paths, "clean", False)
            assert not mutations(rows) and (paths[2].read_bytes(), paths[1].read_bytes()) == before

        for name, values, signum in (
            ("run-term", RUN_VALUES, signal.SIGTERM),
            ("run-single-int", (RUN_VALUES[0], RUN_VALUES[0], *RUN_VALUES[2:]), signal.SIGINT),
        ):
            paths = fresh(name)
            unrelated = paths[0] / "unrelated.state"
            unrelated.write_text("foreign baseline\n")
            unknown_stage = paths[0] / ".port-hopping-state.foreign"
            unknown_stage.write_text("unknown staged owner\n")
            with running(paths, values) as process:
                owner = active(process, paths, values)
                assert mutations(command_rows(paths, True)) == expected_creation(owner)
                readonly(paths, "health", True, owner["token"])
                if name == "run-term":
                    readonly(paths, "run", False)
                    readonly(paths, "clean", False, owner["token"])
                paths[3].write_text("")
                finish(process, signum=signum)
            assert mutations(command_rows(paths, True)) == sum(
                (expected_cleanup(family, "full", owner=owner) for family in FAMILIES), [])
            cleaned(paths)
            assert unrelated.read_text() == "foreign baseline\n"
            assert unknown_stage.read_text() == "unknown staged owner\n"

        paths = fresh("run-second-hook-failed", fail_hook="ip6tables")
        with running(paths) as process:
            finish(process, accepted=False)
        rows = mutations(command_rows(paths, True))
        creation = rows[:8]
        token = creation[1][creation[1].index("--comment") + 1].removeprefix("padm-hop:")
        owner = dict(line.split("=", 1) for line in STATE.replace(TOKEN, token).replace(
            CHAIN, "padm-hop-" + token[:12]).splitlines())
        assert creation == expected_creation(owner), rows
        assert rows[8:] == (expected_cleanup("iptables", "full", owner=owner)
                            + expected_cleanup("ip6tables", "detached", owner=owner)), rows
        cleaned(paths)

        # 外来冲突不改变精确归属，拒绝启用后仍可回收本轮资源。
        for kind in (*FAMILIES, "udp", "nft", "read-fail", "lock"):
            paths = fresh("run-post-" + kind, post_conflict=kind)
            with running(paths) as process:
                finish(process, accepted=False)
            value = json.loads(paths[2].read_text())
            if kind == "lock":
                assert paths[1].exists() and owner_value(paths)["phase"] == "intent"
                assert all(value[family] == table(family, "full", owner=owner_value(paths))
                           for family in FAMILIES), value
                metadata = (paths[0] / ".port-hopping.lock").stat()
                assert [metadata.st_dev, metadata.st_ino] == json.loads(
                    (paths[2].parent / "post-lock.json").read_text())
            else:
                assert not paths[1].exists()
                for family in FAMILIES:
                    expected = BASE[family].copy()
                    if kind == family:
                        expected.append("-A OUTPUT -p udp -m udp --dport 36561 "
                                        "-j DNAT --to-destination 192.0.2.1:9")
                    assert value[family] == expected, value
        for kind in (*FAMILIES, "udp", "nft", "read-fail", "lock"):
            paths = fresh("run-commit-post-" + kind, post_conflict=kind, post_commit=True)
            with running(paths) as process:
                finish(process, accepted=False)
            value = json.loads(paths[2].read_text())
            assert (paths[2].parent / "post-commit.done").exists()
            if kind == "lock":
                assert paths[1].exists() and owner_value(paths)["phase"] == "active"
                assert all(value[family] == table(family, "full", owner=owner_value(paths))
                           for family in FAMILIES), value
                metadata = (paths[0] / ".port-hopping.lock").stat()
                assert [metadata.st_dev, metadata.st_ino] == json.loads(
                    (paths[2].parent / "post-lock.json").read_text())
            else:
                assert not paths[1].exists()
                for family in FAMILIES:
                    expected = BASE[family].copy()
                    if kind == family:
                        expected.append("-A OUTPUT -p udp -m udp --dport 36561 "
                                        "-j DNAT --to-destination 192.0.2.1:9")
                    assert value[family] == expected, value

        stages = (("-N", False, "empty"), ("-A", False, "sentinel"),
                  ("-I", False, "detached"), ("-I", True, "full"))
        for family_index, family in enumerate(FAMILIES):
            for stage_index, (action, hook, shape) in enumerate(stages):
                paths = fresh(f"run-term-{family}-{stage_index}", gate={
                    "family": family, "action": action, "hook": hook})
                with running(paths) as process:
                    wait_for(process, lambda: (paths[2].parent / "gate.entered").exists(),
                             paths[0].parent.name)
                    owner = owner_value(paths)
                    assert owner["phase"] == "intent"
                    shapes = ("full", shape) if family_index else (shape, "none")
                    value = json.loads(paths[2].read_text())
                    assert all(value[current] == table(current, current_shape, owner=owner)
                               for current, current_shape in zip(FAMILIES, shapes)), value
                    process.send_signal(signal.SIGTERM)
                    (paths[2].parent / "gate.release").touch()
                    finish(process)
                rows = mutations(command_rows(paths, True))
                prefix = 4 * family_index + stage_index + 1
                assert rows[:prefix] == expected_creation(owner)[:prefix], rows
                assert rows[prefix:] == sum((expected_cleanup(current, current_shape, owner=owner)
                                            for current, current_shape in zip(FAMILIES, shapes)), []), rows
                cleaned(paths)

        for phase, shapes in (("intent", ("full", "none")), ("active", ("full", "full"))):
            gate = {"gate": {"family": "iptables", "action": "-I", "hook": True}} if (
                phase == "intent") else {}
            paths = fresh("run-recover-" + phase, **gate)
            with running(paths) as process:
                if phase == "intent":
                    wait_for(process, lambda: (paths[2].parent / "gate.entered").exists(),
                             paths[0].parent.name)
                    old = owner_value(paths)
                    assert old["phase"] == "intent"
                else:
                    old = active(process, paths)
                crash(process, paths)
            with running(paths) as process:
                owner = active(process, paths, previous_token=old["token"])
                assert owner["token"] != old["token"]
                expected = sum((expected_cleanup(family, shape, owner=old)
                                for family, shape in zip(FAMILIES, shapes)), [])
                assert mutations(command_rows(paths, True)) == expected + expected_creation(owner)
                finish(process, signum=signal.SIGTERM)
            cleaned(paths)

        for phase, shapes in (("active", ("full", "full")), ("intent", ("detached", "none"))):
            paths = fixture("recover-term-" + phase, shapes, phase)
            value = json.loads(paths[2].read_text())
            value["term_on_listing"] = "ip6tables"
            paths[2].write_text(json.dumps(value))
            with running(paths) as process:
                finish(process)
            assert mutations(command_rows(paths, True)) == sum(
                (expected_cleanup(family, shape) for family, shape in zip(FAMILIES, shapes)), [])
            cleaned(paths)

        paths = fresh("run-crash-empty", gate={"family": "iptables", "action": "-N"})
        with running(paths) as process:
            wait_for(process, lambda: (paths[2].parent / "gate.entered").exists(),
                     paths[0].parent.name)
            owner = owner_value(paths)
            crash(process, paths)
        assert owner["phase"] == "intent"
        value = json.loads(paths[2].read_text())
        assert value["iptables"] == table("iptables", "empty", owner=owner)
        assert value["ip6tables"] == BASE["ip6tables"]
        readonly(paths, "run", False)

        for phase, shapes in (("active", ("full", "full")), ("intent", ("full", "none"))):
            for index, changed in enumerate(("36560", "36563", "35462",
                                             "198.18.1.2", "2001:db8:1::2")):
                paths = fixture(f"run-tuple-{phase}-{index}", shapes, phase)
                (paths[0] / ".port-hopping.lock").touch(mode=0o600)
                values = list(RUN_VALUES)
                values[index] = changed
                readonly(paths, "run", False, values=values)

        for kind in ("replace_state", "replace_lock"):
            paths = fresh("run-" + kind, **{kind: "same" if kind == "replace_state" else True})
            with running(paths) as process:
                finish(process, accepted=False)
            owner = owner_value(paths)
            assert owner["phase"] == "intent"
            assert mutations(command_rows(paths, True)) == expected_creation(owner)[:1]
            value = json.loads(paths[2].read_text())
            assert value["iptables"] == table("iptables", "empty", owner=owner)
            assert value["ip6tables"] == BASE["ip6tables"]
            readonly(paths, "run", False)

        for phase, point in (
            ("intent", "create"), ("intent", "write"), ("intent", "file-fsync"),
            ("intent", "replace"), ("intent", "directory-fsync"),
            ("active", "replace"), ("active", "directory-fsync"), ("active", "replace-state"),
        ):
            paths = fresh(f"commit-{phase}-{point}", commit_failure={"phase": phase, "point": point})
            unknown_stage = paths[0] / ".port-hopping-state.foreign"
            unknown_stage.write_text("unknown staged owner\n")
            with running(paths) as process:
                finish(process, accepted=False)
            marker = json.loads((paths[2].parent / "commit.fault.json").read_text())
            assert (marker["phase"], marker["point"]) == (phase, point), marker
            owner = dict(line.split("=", 1) for line in marker["state"].splitlines())
            rows = mutations(command_rows(paths, True))
            if phase == "intent":
                assert not rows, rows
                cleaned(paths)
            elif point == "replace-state":
                assert rows == expected_creation(owner), rows
                assert paths[1].read_text() == marker["state"]
                value = json.loads(paths[2].read_text())
                assert all(value[family] == table(family, "full", owner=owner)
                           for family in FAMILIES), value
            else:
                assert rows == expected_creation(owner) + sum(
                    (expected_cleanup(family, "full", owner=owner) for family in FAMILIES), []), rows
                cleaned(paths)
            assert unknown_stage.read_text() == "unknown staged owner\n"
            assert sorted(path.name for path in paths[0].iterdir()) == sorted(
                [".port-hopping.lock", unknown_stage.name]
                + (["port-hopping.state"] if point == "replace-state" else []))
    print(f"docker-port-hopping-ownership-ok: {count} owner, cleanup and lifecycle cases")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "tool":
        tool()
    elif len(sys.argv) > 1 and sys.argv[1] == "python":
        run_python()
    else:
        main()
