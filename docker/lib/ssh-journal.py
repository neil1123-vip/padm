#!/usr/bin/env python3
"""只读核验当次 SSH 新连接与当前 systemd unit，不授权历史日志或防护动作。"""

import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import time


SPEC = importlib.util.spec_from_file_location(
    "padm_ssh_source", Path(__file__).resolve().with_name("ssh-source.py")
)
ssh = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ssh)
Failure = ssh.Failure
UNIT_PROPERTIES = (
    "Id", "LoadState", "ActiveState", "SubState", "MainPID", "InvocationID",
    "ControlGroup", "ExecMainStartTimestampMonotonic", "TriggeredBy",
)
CGROUP_ROOT = Path("/sys/fs/cgroup")
MAX_CGROUPS = 256
MAX_PIDS = 4096


class MembersChanged(Failure):
    def __init__(self, listener=None):
        super().__init__("SSH unit 的 cgroup 成员在核验期间变化")
        self.listener = listener


def unit_name(value):
    if (not isinstance(value, str) or len(value) > 255
            or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.@:-]*\.service", value)):
        raise Failure("SSH unit 核验只接受明确的 service 名称", 2)
    return value


def cgroup_path(value):
    if (not isinstance(value, str) or not value.startswith("/") or value == "/"
            or len(value) > 4096 or any(c.isspace() or ord(c) < 32 or ord(c) == 127
                                        for c in value)
            or any(part in ("", ".", "..") for part in value.split("/")[1:])
            or str(PurePosixPath(value)) != value):
        raise Failure("SSH unit 的 cgroup 路径无效")
    return value


def parse_unit(text, requested):
    requested = unit_name(requested)
    values = {}
    for line in text.splitlines():
        if "=" not in line:
            raise Failure("SSH unit 的结构化属性无效")
        key, value = line.split("=", 1)
        if key not in UNIT_PROPERTIES or key in values:
            raise Failure("SSH unit 的属性重复或超出范围")
        values[key] = value
    if set(values) != set(UNIT_PROPERTIES):
        raise Failure("SSH unit 的属性不完整")
    if (values["Id"] != requested or values["LoadState"] != "loaded"
            or values["ActiveState"] != "active" or values["SubState"] != "running"
            or values["TriggeredBy"]):
        raise Failure("SSH unit 未处于明确运行状态或使用 socket activation")
    if (not re.fullmatch(r"[1-9][0-9]*", values["MainPID"])
            or not re.fullmatch(r"[0-9a-f]{32}", values["InvocationID"])
            or values["InvocationID"] == "0" * 32
            or not re.fullmatch(r"[1-9][0-9]*", values["ExecMainStartTimestampMonotonic"])):
        raise Failure("SSH unit 缺少可信进程或 invocation 代次")
    main_pid = int(values["MainPID"])
    start_mono = int(values["ExecMainStartTimestampMonotonic"])
    if main_pid > 2**31 - 1 or start_mono > 2**64 - 1:
        raise Failure("SSH unit 的进程或单调时间超出范围")
    return {
        "unit": values["Id"], "main_pid": main_pid,
        "invocation_id": values["InvocationID"],
        "control_group": cgroup_path(values["ControlGroup"]),
        "exec_start_mono": start_mono,
    }


def read_unit(requested, deadline=None):
    requested = unit_name(requested)
    text = ssh.run_command([
        "systemctl", "show", "--no-pager",
        "--property=" + ",".join(UNIT_PROPERTIES), "--", requested,
    ], deadline)
    return parse_unit(text, requested)


def check_deadline(deadline):
    if deadline is not None and time.monotonic() >= deadline:
        raise Failure("SSH unit 核验已超时")


def cgroup_pids(control_group, deadline=None):
    control_group = cgroup_path(control_group)
    if not (CGROUP_ROOT / "cgroup.controllers").is_file():
        raise Failure("SSH unit 核验需要可读取的 cgroup v2")
    root = CGROUP_ROOT / control_group.lstrip("/")
    if root.resolve(strict=True) != root or not root.is_dir():
        raise Failure("SSH unit 的 cgroup 不可直接核验")
    pending, seen, pids = [root], set(), set()
    while pending:
        check_deadline(deadline)
        directory = pending.pop()
        if directory in seen or len(seen) >= MAX_CGROUPS:
            raise Failure("SSH unit 的 cgroup 子树超出范围")
        seen.add(directory)
        for value in (directory / "cgroup.procs").read_text().splitlines():
            if not re.fullmatch(r"[1-9][0-9]*", value):
                raise Failure("SSH unit 的 cgroup 进程清单无效")
            pid = int(value)
            if pid in pids or pid > 2**31 - 1 or len(pids) >= MAX_PIDS:
                raise Failure("SSH unit 的 cgroup 进程清单不唯一或超出范围")
            pids.add(pid)
        for entry in directory.iterdir():
            if entry.is_symlink():
                raise Failure("SSH unit 的 cgroup 子树包含间接路径")
            if entry.is_dir():
                pending.append(entry)
    return tuple(sorted(pids))


def process_cgroup(pid):
    lines = (Path("/proc") / str(pid) / "cgroup").read_text().splitlines()
    if len(lines) != 1 or not lines[0].startswith("0::"):
        raise Failure("SSH unit 的进程不在明确的 cgroup v2 中")
    return cgroup_path(lines[0][3:])


def member_snapshot(pid, control_group, netns):
    root = Path("/proc") / str(pid)

    def current():
        raw = (root / "stat").read_text()
        fields = raw[raw.rindex(")") + 2:].split()
        if int(raw.split(" ", 1)[0]) != pid or len(fields) < 20:
            raise Failure("SSH unit 的进程代次无效")
        return int(fields[19]), os.readlink(root / "ns/net"), process_cgroup(pid)

    before = current()
    group = before[2]
    if (before[0] <= 0 or before[1] != netns
            or not (group == control_group or group.startswith(control_group + "/"))
            or current() != before):
        raise Failure("SSH unit 的进程或网络空间在核验期间变化")
    return pid, *before


def unit_listener(unit, master, local, port, deadline=None):
    pids = cgroup_pids(unit["control_group"], deadline)
    if master["pid"] != unit["main_pid"] or master["pid"] not in pids:
        raise Failure("SSH master 不是所选 unit 的 MainPID")
    def snapshot_members(listener=None):
        rows = []
        for pid in pids:
            try:
                rows.append(member_snapshot(pid, unit["control_group"], master["netns"]))
            except (FileNotFoundError, ProcessLookupError):
                if pid == master["pid"]:
                    raise
                current = cgroup_pids(unit["control_group"], deadline)
                if master["pid"] in current and pid not in current:
                    raise MembersChanged(listener) from None
                raise
        return tuple(rows)

    members = snapshot_members()
    listeners = []
    for family in (4, 6):
        check_deadline(deadline)
        rows = ssh.parse_ss(ssh.run_command(["ss", "-H", "-ltnpe", f"-{family}"],
                                           deadline), family)
        for row in rows:
            if row["state"] != "LISTEN":
                raise Failure("SSH unit 的完整监听清单无效")
            if not row["owners"]:
                raise Failure("SSH unit 无法排除所有者不可读的 TCP 监听")
            if any(pid in pids for pid, _fd in row["owners"]):
                listeners.append(row)
    if (len(listeners) != 1 or listeners[0]["local"] != (str(local), port)
            or len(listeners[0]["owners"]) != 1
            or listeners[0]["owners"][0][0] != master["pid"]):
        raise Failure("SSH unit 必须只有一个唯一显式 TCP 监听")
    listener = listeners[0]
    ssh.socket_fd(*listener["owners"][0], listener["inode"])
    current = cgroup_pids(unit["control_group"], deadline)
    if master["pid"] not in current:
        raise Failure("SSH master 已离开所选 unit 的 cgroup")
    if current != pids:
        raise MembersChanged(listener)
    if snapshot_members(listener) != members:
        raise Failure("SSH unit 的进程或网络空间在核验期间变化")
    return listener


def unit_snapshot(requested, local, port, deadline=None):
    unit = read_unit(requested, deadline)
    master = ssh.read_process(unit["main_pid"], ssh.MASTER_EXES)
    previous_listener = None
    # 认证子进程会自然进出；只重取一次完整证据，并固定原 unit、master 和已见监听。
    for attempt in range(2):
        listener = None
        try:
            listener = unit_listener(unit, master, local, port, deadline)
        except MembersChanged as error:
            if attempt:
                raise
            previous_listener = error.listener
        else:
            if previous_listener is not None and listener != previous_listener:
                raise Failure("SSH unit 的监听在重新核验期间变化")
        if (read_unit(requested, deadline) != unit
                or ssh.read_process(unit["main_pid"], ssh.MASTER_EXES) != master):
            raise Failure("SSH unit 或 MainPID 在核验期间变化")
        check_deadline(deadline)
        if listener is not None:
            return {"unit": unit, "master": {"process": master, "socket": listener}}


def verify_unit_record(record, snapshot, evidence):
    unit = snapshot["unit"]
    master = snapshot["master"]["process"]
    for key, value in (
        ("_SYSTEMD_UNIT", unit["unit"]),
        ("_SYSTEMD_INVOCATION_ID", unit["invocation_id"]),
        ("_SYSTEMD_CGROUP", unit["control_group"]),
        ("_BOOT_ID", master["boot_id"]), ("_TRANSPORT", "syslog"), ("_UID", "0"),
        ("_PID", str(evidence["emitter"]["pid"])),
        ("_EXE", evidence["emitter"]["exe"]),
    ):
        if record.get(key) != value:
            raise Failure("SSH 挑战日志缺少所选 unit 的可信归属")
    mono, cursor = record.get("__MONOTONIC_TIMESTAMP"), record.get("__CURSOR")
    if (not isinstance(mono, str) or not re.fullmatch(r"[0-9]+", mono)
            or int(mono) < unit["exec_start_mono"]
            or int(mono) != evidence["event"]["timestamp"]
            or int(mono) <= evidence["fresh_us"]
            or not isinstance(cursor, str) or not cursor or len(cursor) > 1024
            or any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in cursor)
            or cursor == evidence["cursor"]):
        raise Failure("SSH unit 的挑战日志缺少新鲜游标或单调时间")
    return {"cursor": cursor, "mono": int(mono)}


def unit_witness(requested, local, port, source, nonce):
    if ssh.sys.platform != "linux" or os.geteuid() != 0:
        raise Failure("SSH unit 核验需要原生 Linux root 环境", 10)
    requested = unit_name(requested)
    local, port, source, nonce = ssh.parse_args(
        [str(local), str(port), str(source), nonce]
    )
    try:
        before = unit_snapshot(requested, local, port)
        evidence = ssh.witness_evidence(local, port, source, nonce)
        if evidence["master"] != before["master"]:
            raise Failure("SSH fresh master 不属于所选 unit 的当前代次")
        journal = verify_unit_record(evidence["record"], before, evidence)
        after = unit_snapshot(requested, local, port, evidence["deadline"])
        if after != before:
            raise Failure("SSH unit、MainPID 或完整监听代次发生变化")
        # 归属仅限这次仍存活的连接；unit 字段不证明其它历史或未来日志的目的端口。
        final = ssh.verify_event(
            evidence["event"], evidence["master"], local, port, source,
            evidence["deadline"],
        )
        if final != (evidence["emitter"], evidence["accepted"]):
            raise Failure("SSH unit 的当次挑战连接已变化")
        if process_cgroup(evidence["emitter"]["pid"]) != before["unit"]["control_group"]:
            raise Failure("SSH 挑战进程已离开所选 unit cgroup")
        check_deadline(evidence["deadline"])
        return {
            "scope": "ssh-unit-source-only", "source_verified": True,
            "unit_verified": True, "runtime_configuration_verified": False,
            "jail_ready": False, "target": str(local), "port": port,
            "source": str(source), "snapshot": after, "journal": journal,
        }
    except (OSError, ValueError, KeyError, IndexError, TypeError):
        raise Failure("SSH unit 核验无法读取完整的宿主证据") from None


def main(args):
    try:
        if len(args) != 5:
            raise Failure("SSH unit 核验需要 service、本机地址、端口、外部来源和挑战码", 2)
        requested = unit_name(args[0])
        parsed = ssh.parse_args(args[1:])
        if sys.platform != "linux" or os.geteuid() != 0:
            raise Failure("SSH unit 核验需要原生 Linux 宿主 root 环境", 10)
        if any(shutil.which(tool) is None
               for tool in ("ip", "ss", "docker", "journalctl", "systemctl")):
            raise Failure("SSH unit 核验缺少宿主只读工具", 10)
        result = unit_witness(requested, *parsed)
        print("source-verified=" + json.dumps(result, separators=(",", ":")), flush=True)
        return 0
    except Failure as error:
        print(str(error), file=sys.stderr)
        return error.code
    except (OSError, ValueError, KeyError, IndexError, TypeError):
        print("SSH unit 核验无法完成宿主证据读取", file=sys.stderr)
        return 15
    except KeyboardInterrupt:
        print("SSH unit 核验已取消", file=sys.stderr)
        return 15


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
