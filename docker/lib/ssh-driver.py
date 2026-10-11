#!/usr/bin/env python3
"""仅驱动自己创建的可信单线程 fixture，不接收外部 PID，不授权 collector 或 jail。"""

import copy
import ctypes
import importlib.util
import os
from pathlib import Path
import signal
import socket
import struct
import time


SPEC = importlib.util.spec_from_file_location(
    "padm_ssh_driver_ledger", Path(__file__).with_name("ssh-ledger.py")
)
ledger_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ledger_module)
Failure = ledger_module.Failure
TRACEME, CONT, SYSCALL, SETOPTIONS, GETEVENTMSG, GET_SYSCALL_INFO = 0, 7, 24, 0x4200, 0x4201, 0x420E
FORK, VFORK, CLONE, EXEC, EXIT = 1, 2, 3, 4, 6
OPTIONS = 0x1 | 0x2 | 0x4 | 0x8 | 0x10 | 0x40 | 0x00100000
WAIT_FLAGS = os.WNOHANG | 0x40000000
PR_SET_CHILD_SUBREAPER, PR_GET_CHILD_SUBREAPER = 36, 37
AUDIT_ARCH_X86_64, X32_BIT = 0xC000003E, 0x40000000
SYS_CLONE, SYS_FORK, SYS_VFORK, SYS_CLONE3 = 56, 57, 58, 435
SYS_SETPGID, SYS_SETSID = 109, 112
CHILD_CLEARTID, CHILD_SETTID = 0x00200000, 0x01000000
libc = ctypes.CDLL(None, use_errno=True)
libc.ptrace.argtypes = [ctypes.c_ulong, ctypes.c_ulong, ctypes.c_void_p, ctypes.c_void_p]
libc.ptrace.restype = ctypes.c_long


def ptrace(request, pid, data=0, address=0):
    result = libc.ptrace(request, pid, ctypes.c_void_p(address), ctypes.c_void_p(data))
    if result == -1:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))
    return result


def event_message(pid):
    value = ctypes.c_ulong()
    ptrace(GETEVENTMSG, pid, ctypes.addressof(value))
    return value.value


def syscall_info(pid):
    # 布局来自 Linux ptrace.h；仅解析内核实际返回的 entry/exit 字节。
    buffer = ctypes.create_string_buffer(88)
    size = ptrace(GET_SYSCALL_INFO, pid, ctypes.addressof(buffer), len(buffer))
    if size < 24 or size > len(buffer):
        raise Failure("受控 SSH syscall 信息长度无效")
    op, arch, instruction, stack = struct.unpack_from("=B3xIQQ", buffer)
    if arch != AUDIT_ARCH_X86_64 or op not in (1, 2):
        raise Failure("受控 SSH syscall ABI 或停点类型未验证")
    result = {"op": op, "arch": arch, "instruction_pointer": instruction, "stack_pointer": stack}
    if op == 1:
        if size < 80:
            raise Failure("受控 SSH syscall entry 信息不完整")
        nr, *args = struct.unpack_from("=7Q", buffer, 24)
        if nr & X32_BIT:
            raise Failure("受控 SSH driver 拒绝未验证的 x32 syscall")
        result.update({"nr": nr, "args": args})
    else:
        if size < 33:
            raise Failure("受控 SSH syscall exit 信息不完整")
        rval, is_error = struct.unpack_from("=qB", buffer, 24)
        if is_error not in (0, 1) or bool(is_error) != (-4095 <= rval < 0):
            raise Failure("受控 SSH syscall 返回值与错误标志不一致")
        result.update({"rval": rval, "is_error": bool(is_error)})
    return result


def process_snapshot(pid):
    root = Path(f"/proc/{pid}")
    fields = (root / "stat").read_text().rsplit(") ", 1)[1].split()
    status = (root / "status").read_text().splitlines()
    fds = []
    for entry in (root / "fd").iterdir():
        try:
            target = os.readlink(entry)
        except FileNotFoundError:
            # 进程可能在枚举期间关闭临时 FD；消失的条目不属于快照。
            continue
        if target.startswith("socket:["):
            fds.append([int(entry.name), target])
    return {
        "pid": pid, "ppid": int(fields[1]), "pgrp": int(fields[2]), "sid": int(fields[3]),
        "state": fields[0],
        "starttime_ticks": int(fields[19]), "exe": os.readlink(root / "exe"),
        "pid_ns": os.readlink(root / "ns/pid"), "net_ns": os.readlink(root / "ns/net"),
        "mount_ns": os.readlink(root / "ns/mnt"),
        "cgroup": (root / "cgroup").read_text().splitlines(),
        "threads": int(next(line.split(":", 1)[1] for line in status
                            if line.startswith("Threads:"))),
        "socket_fds": fds,
    }


def endpoint(token):
    address, port = token.split(":")
    return [socket.inet_ntoa(bytes.fromhex(address)[::-1]), int(port, 16)]


class ControlledDriver:
    """callback 必须可信；仅已验 amd64 创建 ABI，不能隔离任意 callback。"""

    def __init__(self, deadline, receiver, expected_tuple):
        self.ledger = ledger_module.Ledger(deadline)
        self.receiver = receiver
        self.expected_tuple = copy.deepcopy(expected_tuple)
        self.master = None
        self.tracked = set()
        self.retired = {}
        self.registered = set()
        self.pending_children = {}
        self.early_stops = {}
        self.active_syscalls = {}
        self.first_syscall_exit = set()
        self.creations = {}
        self.waiting_parent_exit = set()
        self.evidence = {
            "authoritative": False, "jail_ready": False,
            "scope": "只用于可信 amd64 fork fixture；不支持任意 OpenSSH 或 arm64",
            "events": [], "first_stops": [], "continues": [], "cleanup": [],
            "creations": [], "syscall_stop_count": 0, "normal_resume_count": 0,
            "expected_tuple": copy.deepcopy(expected_tuple),
        }

    def _check(self):
        self.ledger._check()

    def _wait(self, initial=False):
        while True:
            self._check()
            pid, status = os.waitpid(self.master if initial else -self.master, WAIT_FLAGS)
            if pid:
                return pid, status
            time.sleep(0)

    def _sample(self, pid):
        self._check()
        process = process_snapshot(pid)
        if process["threads"] != 1 or process["pgrp"] != self.master or process["state"] != "t":
            raise Failure("受控 SSH task 的单线程、进程组或真实停点无效")
        inodes = {value[8:-1] for _fd, value in process["socket_fds"]}
        rows = []
        for line in Path(f"/proc/{pid}/net/tcp").read_text().splitlines()[1:]:
            fields = line.split()
            if fields[9] in inodes:
                rows.append({
                    "inode": int(fields[9]), "local": endpoint(fields[1]),
                    "remote": endpoint(fields[2]), "state": fields[3],
                })
        accepted = [row for row in rows
                    if row["local"] == self.expected_tuple["local"]
                    and row["remote"] == self.expected_tuple["remote"] and row["state"] == "01"]
        self._check()
        return {"process": process, "accepted_matches": accepted, "owned_tcp": rows}

    def _normal_continue(self, pid, delivered_signal=0, record=True):
        if pid not in self.registered:
            raise Failure("受控 SSH driver 拒绝继续未登记 task")
        # finish_stop 返回后仍可能超时，实际恢复执行前再检查总期限。
        self._check()
        ptrace(SYSCALL, pid, delivered_signal)
        resumed = time.monotonic_ns()
        self.evidence["normal_resume_count"] += 1
        self.evidence["last_normal_resume_monotonic_ns"] = resumed
        if record:
            self.evidence["continues"].append({
                "pid": pid, "request": SYSCALL, "signal": delivered_signal, "normal": True,
                "returned_monotonic_ns": resumed,
            })
        return time.monotonic_ns()

    def _registered_process(self, pid, process):
        identity = self.ledger.registry[pid]
        if (self.ledger._generation(process) != identity["generation"]
                or process["exe"] != identity["epoch_exe"] or identity["terminal"]):
            raise Failure("受控 SSH 已登记 task 的代次或 exe 已改变")

    def _register_child(self, pid, parent, parent_anchor, first, frozen):
        current = self._sample(pid)
        process = current["process"]
        parent_process = parent_anchor["process"]
        parent_identity = self.ledger.registry[parent]
        creation = self.creations[parent]
        self.ledger._pidfd(parent_identity["held_pidfd"], parent)
        if (self.ledger._generation(parent_process) != parent_identity["generation"]
                or parent_process["exe"] != parent_identity["epoch_exe"]
                or creation.get("exit_rval") != pid or creation.get("event_child") != pid
                or creation["generation"] != parent_identity["generation"]
                or creation["epoch"] != parent_identity["epoch"]
                or current != frozen or process["ppid"] != parent
                or process["pid_ns"] != parent_process["pid_ns"]
                or process["net_ns"] != parent_process["net_ns"]
                or len(current["accepted_matches"]) != 1
                or len(parent_anchor["accepted_matches"]) != 1
                or current["accepted_matches"][0] != parent_anchor["accepted_matches"][0]):
            raise Failure("受控 SSH child 首停的父链、代次或 accepted 继承无效")
        self.ledger.register(process, current)
        self.registered.add(pid)
        self.first_syscall_exit.add(pid)
        row = {
            "pid": pid, "parent_pid": parent, "snapshot": copy.deepcopy(current),
            "first_stop": copy.deepcopy(first), "parent_fork_anchor": copy.deepcopy(parent_anchor),
            "creation": copy.deepcopy(creation),
            "registered_monotonic_ns": time.monotonic_ns(),
        }
        row["first_continue_monotonic_ns"] = self._normal_continue(pid)
        self.evidence["first_stops"].append(row)
        self.evidence["creations"].append(copy.deepcopy(creation))
        del self.creations[parent]
        self.waiting_parent_exit.discard(parent)
        self._normal_continue(parent)

    def _syscall(self, pid, row):
        if pid not in self.registered:
            raise Failure("受控 SSH syscall task 未登记")
        info = syscall_info(pid)
        self.evidence["syscall_stop_count"] += 1
        if info["op"] == 1:
            if pid in self.active_syscalls:
                raise Failure("受控 SSH syscall entry 重入或缺少 exit")
            self.first_syscall_exit.discard(pid)
            self.active_syscalls[pid] = info["nr"]
            if info["nr"] in (SYS_SETPGID, SYS_SETSID):
                row.update({"kind": "group-change-entry", "syscall": info})
                current = self._sample(pid)
                row["current"] = current
                self._registered_process(pid, current["process"])
                # 等待范围固定为自有进程组，脱组 syscall 必须在恢复执行前拒绝。
                raise Failure(f"受控 SSH driver 拒绝未支持的进程组或会话改变 syscall {info['nr']}")
            if info["nr"] in (SYS_CLONE, SYS_FORK, SYS_VFORK, SYS_CLONE3):
                row.update({"kind": "creation-entry", "syscall": info})
                if pid in self.creations:
                    raise Failure("受控 SSH 创建 syscall 缺少前次返回证据")
                if info["nr"] in (SYS_VFORK, SYS_CLONE3):
                    raise Failure(f"受控 SSH driver 拒绝未支持的创建 syscall {info['nr']}")
                if info["nr"] == SYS_CLONE:
                    flags, stack, parent_tid, child_tid, tls, _unused = info["args"]
                    if ((flags & 0xFF) != signal.SIGCHLD
                            or (flags & ~(0xFF | CHILD_SETTID | CHILD_CLEARTID))
                            or stack or parent_tid or tls
                            or (bool(child_tid) != bool(flags & (CHILD_SETTID | CHILD_CLEARTID)))):
                        raise Failure(f"受控 SSH driver 拒绝不安全 clone flags/参数 {flags:#x}")
                current = self._sample(pid)
                self._registered_process(pid, current["process"])
                if len(current["accepted_matches"]) != 1:
                    raise Failure("受控 SSH 创建 entry 缺少唯一 live accepted 锚点")
                identity = self.ledger.registry[pid]
                self.creations[pid] = {
                    "parent_pid": pid, "generation": copy.deepcopy(identity["generation"]),
                    "epoch": identity["epoch"], "exe": identity["epoch_exe"],
                    "entry": copy.deepcopy(info), "entry_anchor": copy.deepcopy(current),
                    "entry_monotonic_ns": time.monotonic_ns(),
                }
        else:
            nr = self.active_syscalls.pop(pid, None)
            if nr is None:
                if pid not in self.first_syscall_exit or info["rval"] != 0 or info["is_error"]:
                    raise Failure("受控 SSH syscall exit 缺少对应 entry")
                self.first_syscall_exit.discard(pid)
            if pid in self.creations:
                creation = self.creations[pid]
                row.update({"kind": "creation-exit", "syscall": info})
                if nr != creation["entry"]["nr"]:
                    raise Failure("受控 SSH 创建 syscall 的返回类型不匹配")
                if info["is_error"]:
                    if "event_child" in creation:
                        raise Failure("受控 SSH 创建失败却已有 FORK 事件")
                    creation.update({"exit_rval": info["rval"], "failed": True})
                    self.evidence["creations"].append(copy.deepcopy(creation))
                    del self.creations[pid]
                else:
                    if info["rval"] <= 0 or info["rval"] != creation.get("event_child"):
                        raise Failure("受控 SSH 创建返回 PID 与 FORK 事件不匹配")
                    current = self._sample(pid)
                    self._registered_process(pid, current["process"])
                    identity = self.ledger.registry[pid]
                    if (identity["generation"] != creation["generation"]
                            or identity["epoch"] != creation["epoch"]
                            or current["accepted_matches"] != creation["event_anchor"]["accepted_matches"]):
                        raise Failure("受控 SSH 创建返回停点的代次或 accepted 锚点已改变")
                    creation.update({"exit_rval": info["rval"],
                                     "exit_monotonic_ns": time.monotonic_ns()})
                    child = creation["event_child"]
                    self.waiting_parent_exit.add(pid)
                    if child in self.early_stops:
                        first, frozen = self.early_stops.pop(child)
                        self.pending_children.pop(child)
                        self._register_child(child, pid, creation["event_anchor"], first, frozen)
                    return
        self._normal_continue(pid, record=row["kind"] != "syscall-stop")

    def _event(self, pid, status):
        event = status >> 16 if os.WIFSTOPPED(status) else 0
        row = {"pid": pid, "status": status, "event": event,
               "wait_monotonic_ns": time.monotonic_ns()}
        try:
            if os.WIFEXITED(status) or os.WIFSIGNALED(status):
                if pid not in self.registered:
                    self.tracked.add(pid)
                    raise Failure("受控 SSH 退出 task 未登记")
                row.update({"kind": "reaped", "exit_code": os.waitstatus_to_exitcode(status)})
                # ptrace 通知不等于真正父进程已回收；独立 pidfd 跨账本关闭保留原 task 身份。
                if pid not in self.retired:
                    self.retired[pid] = os.dup(self.ledger.registry[pid]["held_pidfd"])
                self.tracked.discard(pid)
                self.active_syscalls.pop(pid, None)
                self.first_syscall_exit.discard(pid)
                return
            if not os.WIFSTOPPED(status):
                raise Failure("受控 SSH driver 拒绝未知 wait 状态")
            self.tracked.add(pid)
            if event in (FORK, VFORK, CLONE):
                child = event_message(pid)
                if child <= 0:
                    raise Failure("受控 SSH 创建事件缺少有效 child PID")
                self.tracked.add(child)
                row["child_pid"] = child
            # 已消费的 wait 结果必须先保留已知 task，超时不能丢失待清理 child。
            self._check()
            # 新 child 已纳入清理后再拒绝；未支持事件不能落入普通信号分支。
            if event != 0 and event not in (FORK, EXEC, EXIT):
                raise Failure(f"受控 SSH driver 拒绝未支持的 ptrace event {event}")
            if event == FORK:
                if pid not in self.registered or child in self.pending_children or child in self.registered:
                    raise Failure("受控 SSH fork 父链重复或未登记")
                parent_anchor = self._sample(pid)
                self._registered_process(pid, parent_anchor["process"])
                creation = self.creations.get(pid)
                if (creation is None or "event_child" in creation
                        or self.active_syscalls.get(pid) != creation["entry"]["nr"]
                        or creation["generation"] != self.ledger.registry[pid]["generation"]
                        or creation["epoch"] != self.ledger.registry[pid]["epoch"]
                        or parent_anchor["accepted_matches"] != creation["entry_anchor"]["accepted_matches"]):
                    raise Failure("受控 SSH FORK 事件缺少一致的创建 entry 证据")
                creation.update({"event_child": child, "event_anchor": copy.deepcopy(parent_anchor),
                                 "event_monotonic_ns": time.monotonic_ns()})
                row.update({"kind": "fork-parent-stop", "parent_fork_anchor": parent_anchor})
                self.pending_children[child] = (pid, copy.deepcopy(parent_anchor))
                row["continued_monotonic_ns"] = self._normal_continue(pid)
            elif event == 0 and os.WSTOPSIG(status) == (signal.SIGTRAP | 0x80):
                row["kind"] = "syscall-stop"
                self._syscall(pid, row)
            elif pid not in self.registered and event == 0 and os.WSTOPSIG(status) == signal.SIGSTOP:
                if pid in self.early_stops:
                    raise Failure("受控 SSH child 首停重复")
                current = self._sample(pid)
                row.update({"kind": "child-first-stop", "current": current})
                if pid in self.pending_children:
                    parent, parent_anchor = self.pending_children[pid]
                    if parent in self.waiting_parent_exit:
                        self.pending_children.pop(pid)
                        self._register_child(pid, parent, parent_anchor, row, current)
                    else:
                        row["held_without_continue"] = True
                        self.early_stops[pid] = (copy.deepcopy(row), copy.deepcopy(current))
                else:
                    row["held_without_continue"] = True
                    self.early_stops[pid] = (copy.deepcopy(row), copy.deepcopy(current))
            elif event in (EXEC, EXIT):
                if pid not in self.registered:
                    raise Failure("受控 SSH EXEC/EXIT task 未登记")
                if pid in self.creations:
                    raise Failure("受控 SSH 创建 syscall 未关联完成却发生 EXEC/EXIT")
                current = self._sample(pid)
                row.update({"kind": "exec-stop" if event == EXEC else "exit-stop",
                            "current": current, "event_message": event_message(pid)})
                row["ledger"] = copy.deepcopy(self.ledger.finish_stop(self.receiver, pid, event, current))
                row["finish_return_monotonic_ns"] = time.monotonic_ns()
                row["continued_monotonic_ns"] = self._normal_continue(pid)
            elif pid in self.registered and event == 0:
                current = self._sample(pid)
                self._registered_process(pid, current["process"])
                if os.WSTOPSIG(status) == signal.SIGSTOP and self.ledger.registry[pid]["anchor"] is not None:
                    row.update({"kind": "message-barrier", "current": current})
                    row["drain"] = copy.deepcopy(self.ledger.drain(self.receiver))
                    row["pending_at_barrier"] = copy.deepcopy(self.ledger.registry[pid]["pending"])
                    row["received_fds_at_barrier"] = sorted(self.ledger.open_received_fds)
                    row["drain_return_monotonic_ns"] = time.monotonic_ns()
                    row["continued_monotonic_ns"] = self._normal_continue(pid)
                else:
                    row.update({"kind": "signal-delivery-stop", "signal": os.WSTOPSIG(status)})
                    row["continued_monotonic_ns"] = self._normal_continue(pid, os.WSTOPSIG(status))
            else:
                raise Failure("受控 SSH driver 拒绝未知 child 停点")
        except BaseException as error:
            row.update({"rejection": str(error), "rejected_monotonic_ns": time.monotonic_ns()})
            raise
        finally:
            if row.get("kind") != "syscall-stop" or "rejection" in row:
                self.evidence["events"].append(copy.deepcopy(row))

    def _cleanup(self):
        if self.tracked:
            try:
                os.killpg(self.master, signal.SIGKILL)
                self.evidence["cleanup"].append({"kind": "kill-process-group", "pgrp": self.master})
            except ProcessLookupError:
                pass
        for pid in sorted(self.tracked):
            try:
                os.kill(pid, signal.SIGKILL)
                self.evidence["cleanup"].append({"kind": "kill-known-task", "pid": pid})
            except ProcessLookupError:
                self.evidence["cleanup"].append({"kind": "known-task-already-gone", "pid": pid})
        end = time.monotonic() + 2

        def consume(pid, status):
            row = {"pid": pid, "status": status, "normal": False}
            if os.WIFEXITED(status) or os.WIFSIGNALED(status):
                if pid in self.retired:
                    self.tracked.discard(pid)
                    row.update({"kind": "cleanup-retired-exit-observed",
                                "exit_code": os.waitstatus_to_exitcode(status)})
                    self.evidence["cleanup"].append(row)
                    return
                # ptrace 退出通知可能早于真实父进程回收；保留 task 直到 /proc 消失。
                missing = not Path(f"/proc/{pid}").exists()
                if missing:
                    self.tracked.discard(pid)
                row.update({"kind": "cleanup-reaped" if missing else "cleanup-exit-observed",
                            "exit_code": os.waitstatus_to_exitcode(status), "proc_missing": missing})
            elif os.WIFSTOPPED(status):
                self.tracked.add(pid)
                if status >> 16 in (FORK, VFORK, CLONE):
                    child = event_message(pid)
                    self.tracked.add(child)
                    row["discovered_child"] = child
                    try:
                        os.kill(child, signal.SIGKILL)
                    except ProcessLookupError:
                        row["child_already_gone"] = True
                try:
                    ptrace(CONT, pid, signal.SIGKILL)
                    row.update({"kind": "cleanup-continue", "signal": signal.SIGKILL})
                except ProcessLookupError:
                    row["kind"] = "cleanup-kill-in-progress"
            self.evidence["cleanup"].append(row)

        group_finished = not self.tracked
        while (self.tracked or self.retired or not group_finished) and time.monotonic() < end:
            progressed = False
            # 总期限可能在消费创建事件前到达；清理也要发现进程组内的新 task。
            if not group_finished:
                try:
                    pid, status = os.waitpid(-self.master, WAIT_FLAGS)
                    if pid:
                        consume(pid, status)
                        progressed = True
                except ChildProcessError:
                    group_finished = True
            for task in sorted(self.tracked):
                try:
                    pid, status = os.waitpid(task, WAIT_FLAGS)
                except ChildProcessError:
                    # 线程随其 thread group 回收后可能不再有独立 wait 结果。
                    if not Path(f"/proc/{task}").exists():
                        self.tracked.discard(task)
                        self.evidence["cleanup"].append({
                            "kind": "kernel-reaped-task", "pid": task, "proc_missing": True,
                        })
                        progressed = True
                    continue
                if not pid:
                    continue
                progressed = True
                consume(pid, status)
            for task, descriptor in list(self.retired.items()):
                fields = dict(line.split(":", 1) for line in
                              Path(f"/proc/self/fdinfo/{descriptor}").read_text().splitlines()
                              if ":" in line)
                held_pid = int(fields.get("Pid", "-2"))
                if held_pid == -1:
                    os.close(descriptor)
                    del self.retired[task]
                    self.evidence["cleanup"].append({
                        "kind": "retired-original-task-reaped", "pid": task, "pidfd_pid": -1,
                        "numeric_proc_exists": Path(f"/proc/{task}").exists(),
                    })
                    progressed = True
                    continue
                if held_pid != task:
                    raise Failure("受控 SSH 清理的 pidfd 身份无效")
                try:
                    result = os.waitid(os.P_PIDFD, descriptor, os.WEXITED | os.WNOHANG)
                except ChildProcessError:
                    # 真实父进程尚未退出时，原 task 还没有转交给本 subreaper。
                    continue
                if result is not None:
                    if (result.si_pid != task
                            or result.si_code not in (os.CLD_EXITED, os.CLD_KILLED, os.CLD_DUMPED)):
                        raise Failure("受控 SSH pidfd 回收返回了未知终局")
                    self.evidence["cleanup"].append({
                        "kind": "pidfd-reaped-task", "pid": task, "si_code": result.si_code,
                        "exit_code": result.si_status if result.si_code == os.CLD_EXITED
                        else -result.si_status,
                    })
                    progressed = True
            if not self.tracked and not self.retired and group_finished:
                break
            if not progressed:
                time.sleep(0.001)
        if self.tracked or self.retired or not group_finished:
            raise Failure(f"受控 SSH 清理仍有未回收 task：{sorted(self.tracked | self.retired.keys())}")
        self.evidence["discarded_early_stops"] = sorted(self.early_stops)
        self.evidence["discarded_parent_confirmations"] = sorted(self.pending_children)
        self.early_stops.clear()
        self.pending_children.clear()
        self.evidence["discarded_creation_proofs"] = sorted(self.creations)
        self.creations.clear()
        self.evidence["discarded_syscall_tasks"] = sorted(self.active_syscalls)
        self.active_syscalls.clear()
        self.first_syscall_exit.clear()
        self.waiting_parent_exit.clear()

    def run(self, child_main):
        if self.master is not None:
            raise Failure("受控 SSH driver 只能执行一次")
        baseline = len(os.listdir("/proc/self/fd"))
        error = None
        previous_subreaper = None
        try:
            self._check()
            if process_snapshot(os.getpid())["threads"] != 1:
                raise Failure("受控 SSH tracer 必须单线程")
            if os.uname().machine != "x86_64":
                raise Failure("受控 SSH driver 仅验证原生 amd64")
            previous = ctypes.c_int()
            if libc.prctl(PR_GET_CHILD_SUBREAPER, ctypes.byref(previous), 0, 0, 0) != 0:
                code = ctypes.get_errno()
                raise OSError(code, os.strerror(code))
            if libc.prctl(PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0) != 0:
                code = ctypes.get_errno()
                raise OSError(code, os.strerror(code))
            # 异常终止 master 后收养后代，保证本 driver 能完成真正的 wait/reap。
            previous_subreaper = previous.value
            self.evidence["subreaper_before"] = previous_subreaper
            self.master = os.fork()
            if self.master == 0:
                try:
                    self.receiver.close()
                    os.setpgid(0, 0)
                    ptrace(TRACEME, 0)
                    os.kill(os.getpid(), signal.SIGSTOP)
                    child_main()
                except BaseException:
                    os._exit(111)
                os._exit(0)
            self.tracked.add(self.master)
            pid, status = self._wait(initial=True)
            if (pid != self.master or not os.WIFSTOPPED(status)
                    or status >> 16 or os.WSTOPSIG(status) != signal.SIGSTOP
                    or os.getpgid(pid) != pid):
                raise Failure("受控 SSH master 首停或独立进程组无效")
            initial = self._sample(pid)
            if initial["process"]["ppid"] != os.getpid():
                raise Failure("受控 SSH master 不是本 driver 创建的子进程")
            self.evidence["initial_stop"] = copy.deepcopy(initial)
            self.ledger.register(initial["process"])
            self.registered.add(pid)
            self.first_syscall_exit.add(pid)
            ptrace(SETOPTIONS, pid, OPTIONS)
            self.evidence["exitkill_set_monotonic_ns"] = time.monotonic_ns()
            self._normal_continue(pid)
            while self.tracked:
                self._event(*self._wait())
            if (self.early_stops or self.pending_children or self.creations
                    or self.active_syscalls or self.first_syscall_exit or self.waiting_parent_exit):
                raise Failure("受控 SSH driver 存在未完成的 syscall 或 child 关联")
            self.evidence["final_drain"] = copy.deepcopy(self.ledger.drain(self.receiver))
        except BaseException as caught:
            error = caught
            self.evidence["error"] = str(caught)
            self.evidence["failed_monotonic_ns"] = time.monotonic_ns()
            self.ledger.poisoned = True
        finally:
            self.ledger.close()
            try:
                self._cleanup()
            except BaseException as caught:
                self.evidence["cleanup_error"] = str(caught)
                error = caught
            finally:
                for descriptor in self.retired.values():
                    os.close(descriptor)
            if previous_subreaper is not None:
                if libc.prctl(PR_SET_CHILD_SUBREAPER, previous_subreaper, 0, 0, 0) != 0:
                    code = ctypes.get_errno()
                    error = OSError(code, os.strerror(code))
                    self.evidence["cleanup_error"] = str(error)
                else:
                    self.evidence["subreaper_restored"] = True
            self.evidence.update({
                "messages": copy.deepcopy(self.ledger.messages), "ledger_closed": self.ledger.closed,
                "ledger_poisoned": self.ledger.poisoned, "remaining_tracees": sorted(self.tracked),
                "remaining_retired_tasks": sorted(self.retired),
                "remaining_early_stops": sorted(self.early_stops),
                "remaining_parent_confirmations": sorted(self.pending_children),
                "remaining_creation_proofs": sorted(self.creations),
                "remaining_syscall_tasks": sorted(self.active_syscalls),
                "remaining_first_exit_tasks": sorted(self.first_syscall_exit),
                "remaining_waiting_parent_exit": sorted(self.waiting_parent_exit),
                "open_received_fds": sorted(self.ledger.open_received_fds),
                "fd_count_before": baseline, "fd_count_after": len(os.listdir("/proc/self/fd")),
            })
        if error is not None:
            raise Failure(f"受控 SSH driver 失败：{error}") from error
        return copy.deepcopy(self.evidence)
