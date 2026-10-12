#!/usr/bin/env python3
import fcntl
import itertools
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile


SCRIPT = Path(__file__).resolve()
ROOT = SCRIPT.parents[2]
TOKEN = "0123456789abcdef0123456789abcdef"
CHAIN = "padm-hop-" + TOKEN[:12]
COMMENT = "padm-hop:" + TOKEN
FAMILIES = ("iptables", "ip6tables")
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


def rules(family, single=False):
    address = "198.18.1.1/32" if family == "iptables" else "2001:db8:1::1/128"
    target = "198.18.1.1:35461" if family == "iptables" else "[2001:db8:1::1]:35461"
    selected = "36561" if single else "36561:36562"
    match = f"-d {address} -p udp -m udp --dport {selected} -m comment --comment {COMMENT}"
    return (
        f"-A PREROUTING {match} -j {CHAIN}",
        f"-A {CHAIN} {match} -j DNAT --to-destination {target}",
        f"-A {CHAIN} -m comment --comment {COMMENT} -j RETURN",
    )


def table(family, shape, single=False):
    value = BASE[family].copy()
    if shape == "none":
        return value
    hook, dnat, sentinel = rules(family, single)
    value.insert(4, "-N " + CHAIN)
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
        print("\n".join(fixture[family]))
        return
    if action not in {"-D", "-X", "-A"} or not arguments:
        sys.exit(99)
    current = fixture[family]
    if action == "-D":
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
        if "-N " + arguments[0] not in current:
            sys.exit(1)
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
    fixture_path.write_text(json.dumps(fixture))


def mutations(commands):
    return [row for row in commands if row[1:4] == ["-w", "-t", "nat"]
            and len(row) > 4 and row[4] != "-S"]


def expected_cleanup(family, shape, single=False):
    hook, dnat, sentinel = rules(family, single)
    lines = ([hook] if shape == "full" else [])
    lines += [dnat] if shape in {"full", "detached"} else []
    lines += [sentinel] if shape != "none" else []
    result = [[family, "-w", "-t", "nat", "-D", *shlex.split(line)[1:]]
              for line in lines]
    if shape != "none":
        result.append([family, "-w", "-t", "nat", "-X", CHAIN])
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
        for family in FAMILIES:
            binary = binaries / family
            binary.write_text(f'#!/bin/sh\nexec python3 "{SCRIPT}" tool "{family}" "$@"\n')
            binary.chmod(0o755)

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

        def invoke(paths, action, accepted, token=TOKEN):
            nonlocal count
            state_root, owner, inventory, commands = paths
            commands.write_text("")
            environment = dict(os.environ, PATH=f"{binaries}:{os.environ['PATH']}",
                               HOP_FIXTURE=str(inventory), HOP_COMMANDS=str(commands),
                               HOP_STATE=str(owner))
            result = subprocess.run(["sh", "-c",
                '. "$1"; STATE_ROOT=$2; port_hopping_resources "$3" "$4"',
                "test", str(functions), str(state_root), action, token],
                env=environment, capture_output=True, text=True, timeout=10)
            assert result.returncode == (0 if accepted else 1), (
                state_root.parent.name, action, result.returncode, result.stderr)
            assert not result.stdout, (action, result.stdout)
            if not accepted:
                assert result.stderr, (action, "failure without diagnostic")
            rows = [json.loads(line) for line in commands.read_text().splitlines()]
            for family, *args in rows:
                assert family in FAMILIES and (
                    args == ["--version"] or args == ["-w", "-t", "nat", "-S"] or
                    args[:4] in [["-w", "-t", "nat", flag] for flag in ("-D", "-X", "-A")]
                ), rows
            count += 1
            return rows

        def readonly(paths, action, accepted, token=TOKEN):
            state_root, owner, inventory, _ = paths
            metadata = owner.lstat()
            before = inventory.read_bytes(), owner.read_bytes(), (
                metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_uid,
                metadata.st_gid, metadata.st_size, metadata.st_nlink,
                metadata.st_mtime_ns, metadata.st_ctime_ns)
            lock = state_root / ".port-hopping.lock"
            lock_before = lock.lstat() if lock.exists() else None
            rows = invoke(paths, action, accepted, token)
            assert not mutations(rows), rows
            assert inventory.read_bytes() == before[0] and owner.read_bytes() == before[1]
            metadata = owner.lstat()
            assert (metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_uid,
                    metadata.st_gid, metadata.st_size, metadata.st_nlink,
                    metadata.st_mtime_ns, metadata.st_ctime_ns) == before[2]
            assert (lock.lstat() if lock.exists() else None) == lock_before

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
    print(f"docker-port-hopping-ownership-ok: {count} owner and cleanup cases")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "tool":
        tool()
    else:
        main()
