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
TRACEME, CONT, SYSCALL, SETOPTIONS, GETEVENTMSG, GETSIGINFO, GET_SYSCALL_INFO = (
    0, 7, 24, 0x4200, 0x4201, 0x4202, 0x420E
)
FORK, VFORK, CLONE, EXEC, EXIT = 1, 2, 3, 4, 6
OPTIONS = 0x1 | 0x2 | 0x4 | 0x8 | 0x10 | 0x40 | 0x00100000
WAIT_FLAGS = os.WNOHANG | 0x40000000
WAIT_ID_FLAGS = os.WEXITED | os.WSTOPPED | WAIT_FLAGS
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
        "tracer_pid": int(next(line.split(":", 1)[1] for line in status
                              if line.startswith("TracerPid:"))),
        "socket_fds": fds,
    }


def cleanup_identity(pid):
    root = Path(f"/proc/{pid}")
    fields = (root / "stat").read_text().rsplit(") ", 1)[1].split()
    status = dict(line.split(":", 1) for line in
                  (root / "status").read_text().splitlines() if ":" in line)
    result = {
        "pid": pid, "state": fields[0], "ppid": int(fields[1]),
        "starttime_ticks": int(fields[19]), "tracer_pid": int(status["TracerPid"]),
        "threads": int(status["Threads"]),
    }
    return result


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
        self.bootstrap_tasks = set()
        self.tracked = set()
        self.owned = {}
        self.stopped_tasks = {}
        self.unfixed_children = {}
        self.retired = {}
        self.registered = set()
        self.pending_children = {}
        self.early_stops = {}
        self.active_syscalls = {}
        self.first_syscall_exit = set()
        self.group_changes = {}
        self.creations = {}
        self.waiting_parent_exit = set()
        self.next_retirement_scan = 0
        self.evidence = {
            "authoritative": False, "jail_ready": False,
            "scope": "只用于可信 amd64 fork fixture；不支持任意 OpenSSH 或 arm64",
            "events": [], "first_stops": [], "continues": [], "cleanup": [],
            "creations": [], "syscall_stop_count": 0, "normal_resume_count": 0,
            "task_pins": [], "child_pin_failures": [], "wait_pidfd_count": 0,
            "expected_tuple": copy.deepcopy(expected_tuple),
        }

    def _check(self):
        self.ledger._check()

    def _pidfd_pid(self, descriptor):
        fields = dict(line.split(":", 1) for line in
                      Path(f"/proc/self/fdinfo/{descriptor}").read_text().splitlines()
                      if ":" in line)
        return int(fields.get("Pid", "-2"))

    def _retire_reaped(self, force=False):
        if not self.retired:
            return
        now = time.monotonic()
        if not force and now < self.next_retirement_scan:
            return
        self.next_retirement_scan = now + 0.01
        self._check()
        for pid, descriptor in list(self.retired.items()):
            held_pid = self._pidfd_pid(descriptor)
            if held_pid == pid:
                # tracer 终止通知不等于原父已 wait；不能夺取原父的回收。
                continue
            if held_pid != -1:
                raise Failure("受控 SSH 退役的原 pidfd 身份无效")
            identity = self.ledger.registry.get(pid)
            if identity is None or pid not in self.registered:
                raise Failure("受控 SSH 真回收 task 缺少登记身份")
            if (not identity["terminal"] or identity["pending"]
                    or pid in self.owned or pid in self.tracked or pid in self.stopped_tasks
                    or pid in self.creations or pid in self.group_changes
                    or pid in self.active_syscalls or pid in self.first_syscall_exit
                    or pid in self.waiting_parent_exit or pid in self.pending_children
                    or any(parent == pid for parent, _anchor in self.pending_children.values())
                    or any(creation.get("event_child") == pid or creation.get("exit_rval") == pid
                           for creation in self.creations.values())
                    or pid in self.early_stops
                    or any(frozen["process"]["ppid"] == pid
                           for _first, frozen in self.early_stops.values())
                    or pid in self.unfixed_children
                    or any(unresolved["summary"]["parent_pid"] == pid
                           for unresolved in self.unfixed_children.values())):
                continue
            row = self.ledger.retire_terminal(
                pid, identity["generation"], identity["held_pidfd"])
            os.close(descriptor)
            del self.retired[pid]
            self.registered.remove(pid)
            self.evidence["events"].append({
                "kind": "identity-retired", **row, "driver_pidfd": descriptor,
                "driver_pidfd_pid": -1, "retired_monotonic_ns": time.monotonic_ns(),
            })

    def _pin(self, pid, parent=None, source="run"):
        if type(pid) is not int or pid <= 0 or pid in self.owned or pid in self.retired:
            raise Failure("受控 SSH driver 拒绝重复或无效的原 task 身份")
        try:
            descriptor = os.pidfd_open(pid)
        except OSError:
            if parent is not None and pid in self.unfixed_children:
                self.unfixed_children[pid]["pidfd_open_errors"] += 1
            raise
        try:
            if self._pidfd_pid(descriptor) != pid:
                raise Failure("受控 SSH driver 固定的 pidfd 身份无效")
        except BaseException:
            os.close(descriptor)
            raise
        self.owned[pid] = descriptor
        self.tracked.add(pid)
        if parent is not None:
            parent_stop = self.stopped_tasks.get(parent)
            if parent_stop is None:
                raise Failure("受控 SSH 创建 child 缺少已消费的父停点")
            # pidfd 已固定后先绑定父创建停点，失败路径只能由 cleanup 复用原身份。
            parent_stop["child_pid"] = pid
            self._require_stop(parent)
            parent_process = process_snapshot(parent)
            first = process_snapshot(pid)
            confirmed = process_snapshot(pid)
            if (self._pidfd_pid(descriptor) != pid
                    or self.ledger._generation(first) != self.ledger._generation(confirmed)
                    or any(process["ppid"] != parent or process["tracer_pid"] != os.getpid()
                           or process["pid_ns"] != parent_process["pid_ns"]
                           or process["net_ns"] != parent_process["net_ns"]
                           or process["exe"] != parent_process["exe"]
                           for process in (first, confirmed))):
                raise Failure("受控 SSH 创建 child 的原 task、父链或 namespace 无效")
        row = {"pid": pid, "parent_pid": parent, "source": source,
               "pinned_monotonic_ns": time.monotonic_ns()}
        self.evidence["task_pins"].append(row)
        if source == "cleanup":
            self.evidence["cleanup"].append({"kind": "pin-child", **row})

    def _require_stop(self, pid):
        descriptor = self.owned.get(pid)
        if descriptor is None or pid not in self.stopped_tasks or self._pidfd_pid(descriptor) != pid:
            raise Failure("受控 SSH ptrace 缺少原 task 的 pidfd 或已消费停点")
        fields = Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1].split()
        if fields[0] != "t":
            raise Failure("受控 SSH ptrace 的原 task 不在真实停点")

    def _creation_child(self, pid, source="run"):
        self._require_stop(pid)
        stopped = self.stopped_tasks[pid]
        if stopped["status"] >> 16 not in (FORK, VFORK, CLONE):
            raise Failure("受控 SSH child 身份缺少原父创建停点")
        if "child_pid" not in stopped:
            child = stopped.get("unfixed_child_pid")
            if child is None:
                child = event_message(pid)
                if child <= 0:
                    raise Failure("受控 SSH 创建事件缺少有效 child PID")
                summary = {
                    "child_pid": child, "parent_pid": pid, "parent_pidfd": self.owned[pid],
                    "parent_status": stopped["status"],
                    "parent_generation": copy.deepcopy(
                        self.ledger.registry.get(pid, {}).get("generation")),
                    "discovered_monotonic_ns": time.monotonic_ns(), "attempts": 0,
                }
                # 未固定身份不授予正常运行权限；仅在原父停止屏障内尝试固定或终止。
                stopped["unfixed_child_pid"] = child
                self.unfixed_children[child] = {
                    "parent_stop": stopped, "summary": summary, "pidfd_open_errors": 0,
                }
            else:
                unresolved = self.unfixed_children[child]
                summary = unresolved["summary"]
                if source != "cleanup":
                    raise Failure("受控 SSH 未固定 child 仅允许清理")
                self._unfixed_parent(child)
            summary["attempts"] += 1
            try:
                self._pin(child, pid, source)
            except BaseException as caught:
                if child not in self.owned:
                    summary.update({"last_errno": getattr(caught, "errno", None),
                                    "last_error": str(caught)})
                    if "first_error" not in summary:
                        summary.update({"first_errno": summary["last_errno"],
                                        "first_error": summary["last_error"]})
                        self.evidence["child_pin_failures"].append(summary)
                raise
            finally:
                if child in self.owned:
                    del self.unfixed_children[child]
                    del stopped["unfixed_child_pid"]
                    if "first_error" in summary:
                        summary["resolved_monotonic_ns"] = time.monotonic_ns()
        return stopped["child_pid"]

    def _unfixed_parent(self, child):
        unresolved = self.unfixed_children[child]
        summary = unresolved["summary"]
        parent = summary["parent_pid"]
        self._require_stop(parent)
        stopped = self.stopped_tasks[parent]
        process = process_snapshot(parent)
        if (unresolved["parent_stop"] is not stopped
                or stopped.get("unfixed_child_pid") != child
                or summary["parent_pidfd"] != self.owned[parent]
                or summary["parent_status"] != stopped["status"]
                or summary["parent_generation"] is None
                or summary["parent_generation"] != self.ledger._generation(process)
                or event_message(parent) != child):
            raise Failure("受控 SSH 未固定 child 的原父创建停止屏障已改变")
        return process

    def _cleanup_unfixed_child(self, child, end):
        unresolved = self.unfixed_children[child]
        summary = unresolved["summary"]
        if unresolved["pidfd_open_errors"] != summary["attempts"]:
            raise Failure("受控 SSH 未固定 child 缺少真实 pidfd_open 失败证据")
        parent = self._unfixed_parent(child)
        first = cleanup_identity(child)
        unresolved["identity"] = first
        summary["cleanup_only"] = True

        def confirm():
            current = cleanup_identity(child)
            if (current["starttime_ticks"] != first["starttime_ticks"]
                    or current["ppid"] != summary["parent_pid"]
                    or current["tracer_pid"] != os.getpid()
                    or current["threads"] != 1):
                raise Failure("受控 SSH 未固定 child 的清理身份或停止状态已改变")
            return current

        while time.monotonic() < end:
            self._unfixed_parent(child)
            confirm()
            try:
                stopped = os.waitid(os.P_PID, child, os.WSTOPPED | WAIT_FLAGS)
            except ChildProcessError:
                # traced zombie 可能没有可等停点；ECHILD 只允许转为终局窥探。
                stopped = None
            if stopped is not None:
                if stopped.si_pid != child or stopped.si_code != os.CLD_TRAPPED:
                    raise Failure("受控 SSH 未固定 child 清理返回了未知停点")
                try:
                    if confirm()["state"] != "t":
                        raise ProcessLookupError()
                    if stopped.si_status == signal.SIGSTOP and "first_stop_monotonic_ns" not in summary:
                        root = Path(f"/proc/{child}/ns")
                        namespace = {name: os.readlink(root / entry)
                                     for name, entry in (("pid_ns", "pid"), ("net_ns", "net"))}
                        self._unfixed_parent(child)
                        buffer = ctypes.create_string_buffer(128)
                        ptrace(GETSIGINFO, child, ctypes.addressof(buffer))
                        signo, error, code = struct.unpack_from("=iii", buffer)
                        if signo != signal.SIGSTOP or error != 0:
                            raise Failure("受控 SSH 未固定 child 首停不是已验证的信号递送停点")
                        if any(namespace[name] != parent[name]
                               or namespace[name] != os.readlink(root / entry)
                               for name, entry in (("pid_ns", "pid"), ("net_ns", "net"))):
                            raise Failure("受控 SSH 未固定 child 首停的 namespace 已改变")
                        self._unfixed_parent(child)
                        if confirm()["state"] != "t":
                            raise ProcessLookupError()
                        summary.update({"first_stop_monotonic_ns": time.monotonic_ns(),
                                        "signal_info": {"signo": signo, "errno": error, "code": code},
                                        "first_identity": {**first, **namespace}})
                        ptrace(CONT, child, signal.SIGKILL)
                        kind = "unfixed-child-first-stop"
                    elif stopped.si_status == signal.SIGTRAP | (EXIT << 8):
                        self._unfixed_parent(child)
                        if confirm()["state"] != "t":
                            raise ProcessLookupError()
                        ptrace(CONT, child, 0)
                        kind = "unfixed-child-exit-stop"
                    else:
                        raise Failure("受控 SSH 未固定 child 清理拒绝未知 ptrace 停点")
                    self.evidence["cleanup"].append({
                        "kind": kind, "pid": child, "si_code": stopped.si_code,
                        "si_status": stopped.si_status, "normal": False,
                    })
                except (ProcessLookupError, FileNotFoundError):
                    # 外部 SIGKILL 可令刚消费的停点失效；只继续有界终局等待。
                    pass
            terminal = os.waitid(os.P_PID, child, os.WEXITED | os.WNOWAIT | WAIT_FLAGS)
            if terminal is not None:
                if terminal.si_pid != child:
                    raise Failure("受控 SSH 未固定 child 终局返回了其它 task")
                if terminal.si_code != os.CLD_TRAPPED:
                    if terminal.si_code != os.CLD_KILLED or terminal.si_status != signal.SIGKILL:
                        raise Failure("受控 SSH 未固定 child 缺少 SIGKILL 终局")
                    if confirm()["state"] != "Z":
                        raise Failure("受控 SSH 未固定 child 终局缺少保留的 zombie")
                    self._unfixed_parent(child)
                    unresolved["terminal"] = (terminal.si_pid, terminal.si_code, terminal.si_status)
                    summary["terminal_monotonic_ns"] = time.monotonic_ns()
                    self.evidence["cleanup"].append({
                        "kind": "unfixed-child-terminal-retained", "pid": child,
                        "si_code": terminal.si_code, "si_status": terminal.si_status,
                        "parent_pid": summary["parent_pid"], "normal": False,
                    })
                    return
            time.sleep(0.001)
        raise Failure(f"受控 SSH 未固定 child 清理终局超时：{child}")

    def _wait_original(self, pid):
        descriptor = self.owned[pid]
        result = os.waitid(os.P_PIDFD, descriptor, WAIT_ID_FLAGS)
        if result is None:
            return None
        if result.si_pid != pid:
            raise Failure("受控 SSH pidfd 等待返回了其它 task")
        if result.si_code == os.CLD_TRAPPED:
            # 内核 si_status 含 ptrace event 位，保留实测的 waitpid 状态编码。
            status = (result.si_status << 8) | 0x7F
            self.stopped_tasks[pid] = {"status": status}
            self._require_stop(pid)
            # 轮转原身份，避免持续产生 syscall 停点的父进程饿死 child。
            self.owned[pid] = self.owned.pop(pid)
        elif result.si_code in (os.CLD_EXITED, os.CLD_KILLED, os.CLD_DUMPED):
            status = (result.si_status << 8) if result.si_code == os.CLD_EXITED else (
                result.si_status | (0x80 if result.si_code == os.CLD_DUMPED else 0))
            self.retired[pid] = self.owned.pop(pid)
            self.stopped_tasks.pop(pid, None)
            self.tracked.discard(pid)
        else:
            raise Failure(f"受控 SSH pidfd 等待拒绝未知 si_code {result.si_code}")
        self.evidence["wait_pidfd_count"] += 1
        return pid, status

    def _wait(self, initial=False):
        while True:
            self._check()
            # 仅正常等待扫已处理终局的旧身份；cleanup 仍按原回收流程执行。
            self._retire_reaped()
            for pid in [self.master] if initial else list(self.owned):
                result = self._wait_original(pid)
                if result is not None:
                    return result
            time.sleep(0)

    def _sample(self, pid):
        self._check()
        self._require_stop(pid)
        process = process_snapshot(pid)
        if process["threads"] != 1 or process["state"] != "t":
            raise Failure("受控 SSH task 的单线程或真实停点无效")
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
        self._require_stop(pid)
        ptrace(SYSCALL, pid, delivered_signal)
        del self.stopped_tasks[pid]
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
        self._require_stop(pid)
        info = syscall_info(pid)
        self.evidence["syscall_stop_count"] += 1
        if info["op"] == 1:
            if pid in self.active_syscalls:
                raise Failure("受控 SSH syscall entry 重入或缺少 exit")
            self.first_syscall_exit.discard(pid)
            self.active_syscalls[pid] = info["nr"]
            if info["nr"] in (SYS_SETPGID, SYS_SETSID):
                current = self._sample(pid)
                self._registered_process(pid, current["process"])
                identity = self.ledger.registry[pid]
                row.update({
                    "kind": "group-change-entry", "syscall": copy.deepcopy(info),
                    "current": copy.deepcopy(current),
                    "before": {"pgrp": current["process"]["pgrp"], "sid": current["process"]["sid"]},
                    "generation": copy.deepcopy(identity["generation"]),
                    "epoch": identity["epoch"], "exe": identity["epoch_exe"],
                    "entry_monotonic_ns": time.monotonic_ns(),
                })
                if info["nr"] == SYS_SETPGID and info["args"][:2] != [0, 0]:
                    raise Failure("受控 SSH driver 仅支持当前 task 的 setpgid(0, 0)")
                if pid in self.group_changes:
                    raise Failure("受控 SSH 进程组改变缺少前次 exit 证明")
                self.group_changes[pid] = {
                    "entry": copy.deepcopy(info), "before": copy.deepcopy(row["before"]),
                    "generation": copy.deepcopy(identity["generation"]),
                    "epoch": identity["epoch"], "exe": identity["epoch_exe"],
                    "accepted_matches": copy.deepcopy(current["accepted_matches"]),
                    "entry_monotonic_ns": row["entry_monotonic_ns"],
                }
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
            group_change = self.group_changes.get(pid)
            if nr is None:
                if pid not in self.first_syscall_exit or info["rval"] != 0 or info["is_error"]:
                    raise Failure("受控 SSH syscall exit 缺少对应 entry")
                self.first_syscall_exit.discard(pid)
            if nr in (SYS_SETPGID, SYS_SETSID) and group_change is None:
                raise Failure("受控 SSH 进程组改变 exit 缺少对应 entry")
            if group_change is not None:
                row.update({
                    "kind": "group-change-exit", "syscall": copy.deepcopy(info),
                    "nr": nr, "before": copy.deepcopy(group_change["before"]),
                    "generation": copy.deepcopy(group_change["generation"]),
                    "epoch": group_change["epoch"], "exe": group_change["exe"],
                    "entry_monotonic_ns": group_change["entry_monotonic_ns"],
                    "exit_monotonic_ns": time.monotonic_ns(),
                })
                current = self._sample(pid)
                after = {"pgrp": current["process"]["pgrp"], "sid": current["process"]["sid"]}
                row.update({"current": copy.deepcopy(current), "after": after})
                self._registered_process(pid, current["process"])
                identity = self.ledger.registry[pid]
                if (nr != group_change["entry"]["nr"]
                        or self.ledger._generation(current["process"]) != group_change["generation"]
                        or identity["epoch"] != group_change["epoch"]
                        or identity["epoch_exe"] != group_change["exe"]
                        or current["accepted_matches"] != group_change["accepted_matches"]):
                    raise Failure("受控 SSH 进程组改变 exit 的代次或 accepted 锚点已改变")
                valid = ((nr == SYS_SETPGID and not info["is_error"] and info["rval"] == 0
                          and after["pgrp"] == pid and after["sid"] == group_change["before"]["sid"])
                         or (nr == SYS_SETSID and not info["is_error"] and info["rval"] == pid
                             and after["pgrp"] == pid and after["sid"] == pid)
                         or (info["is_error"] and after == group_change["before"]))
                if not valid:
                    raise Failure("受控 SSH 进程组改变返回值或终态无效")
                del self.group_changes[pid]
            elif pid in self.creations:
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
                if pid not in self.retired:
                    raise Failure("受控 SSH 退出 task 缺少原 pidfd 身份")
                self.tracked.discard(pid)
                self.active_syscalls.pop(pid, None)
                self.first_syscall_exit.discard(pid)
                return
            if not os.WIFSTOPPED(status):
                raise Failure("受控 SSH driver 拒绝未知 wait 状态")
            self.tracked.add(pid)
            if event in (FORK, VFORK, CLONE):
                child = self._creation_child(pid)
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
                if pid in self.group_changes:
                    raise Failure("受控 SSH 进程组改变未关联完成却发生 EXEC/EXIT")
                current = self._sample(pid)
                self._require_stop(pid)
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
        if self.bootstrap_tasks:
            raise Failure(f"受控 SSH 启动闸门仍有未回收 child：{sorted(self.bootstrap_tasks)}")
        end = time.monotonic() + 2
        stop_sent = set()

        def send(pid, delivered, kind):
            try:
                signal.pidfd_send_signal(self.owned[pid], delivered)
                self.evidence["cleanup"].append({"kind": kind, "pid": pid,
                                                "signal": delivered,
                                                "sent_monotonic_ns": time.monotonic_ns()})
            except ProcessLookupError:
                self.evidence["cleanup"].append({"kind": "original-task-already-exited", "pid": pid})
            if delivered == signal.SIGKILL:
                # SIGKILL 可唤醒旧停点；后续只能恢复重新消费的真实停点。
                self.stopped_tasks.pop(pid, None)

        # 先停止原 task 并消费创建事件，不能先杀父再丢掉尚未登记的 child。
        while self.owned and time.monotonic() < end:
            progressed = False
            for pid in list(self.owned):
                if pid not in self.stopped_tasks:
                    result = self._wait_original(pid)
                    if result is not None:
                        progressed = True
                    elif pid not in stop_sent:
                        send(pid, signal.SIGSTOP, "stop-original-task")
                        stop_sent.add(pid)
                if pid in self.stopped_tasks:
                    status = self.stopped_tasks[pid]["status"]
                    if status >> 16 in (FORK, VFORK, CLONE):
                        retrying = "unfixed_child_pid" in self.stopped_tasks[pid]
                        if retrying:
                            child = self.stopped_tasks[pid]["unfixed_child_pid"]
                            if "terminal" in self.unfixed_children[child]:
                                continue
                        try:
                            self._creation_child(pid, "cleanup")
                        except OSError:
                            if "unfixed_child_pid" not in self.stopped_tasks[pid]:
                                raise
                            if not retrying:
                                continue
                            child = self.stopped_tasks[pid]["unfixed_child_pid"]
                            self._cleanup_unfixed_child(child, end)
            if (all("terminal" in item for item in self.unfixed_children.values())
                    and all(pid in self.stopped_tasks for pid in self.owned)):
                break
            if not progressed:
                time.sleep(0.001)
        if any("terminal" not in item for item in self.unfixed_children.values()):
            raise Failure(f"受控 SSH 清理仍有未固定 child：{sorted(self.unfixed_children)}")
        if any(pid not in self.stopped_tasks for pid in self.owned):
            raise Failure("受控 SSH 清理无法在原 task 身份下完成停止屏障")
        for pid in list(self.owned):
            send(pid, signal.SIGKILL, "kill-original-task")

        def consume(pid, status):
            row = {"pid": pid, "status": status, "normal": False}
            if os.WIFEXITED(status) or os.WIFSIGNALED(status):
                if pid not in self.retired:
                    raise Failure("受控 SSH 清理终局缺少原 pidfd 身份")
                for unresolved in self.unfixed_children.values():
                    summary = unresolved["summary"]
                    if summary["parent_pid"] == pid:
                        if not os.WIFSIGNALED(status) or os.WTERMSIG(status) != signal.SIGKILL:
                            raise Failure("受控 SSH 未固定 child 的原父缺少 SIGKILL 终局")
                        summary["parent_terminal_monotonic_ns"] = time.monotonic_ns()
                row.update({"kind": "cleanup-retired-exit-observed",
                            "exit_code": os.waitstatus_to_exitcode(status)})
            elif os.WIFSTOPPED(status):
                if status >> 16 in (FORK, VFORK, CLONE):
                    child = self._creation_child(pid, "cleanup")
                    row["discovered_child"] = child
                    send(child, signal.SIGKILL, "kill-original-task")
                try:
                    self._require_stop(pid)
                    ptrace(CONT, pid, signal.SIGKILL)
                    del self.stopped_tasks[pid]
                    row.update({"kind": "cleanup-continue", "signal": signal.SIGKILL})
                except ProcessLookupError:
                    self.stopped_tasks.pop(pid, None)
                    row["kind"] = "cleanup-kill-in-progress"
            self.evidence["cleanup"].append(row)

        while (self.owned or self.retired or self.unfixed_children) and time.monotonic() < end:
            progressed = False
            for pid in list(self.owned):
                result = self._wait_original(pid)
                if result is not None:
                    progressed = True
                    consume(*result)
            for task, descriptor in list(self.retired.items()):
                held_pid = self._pidfd_pid(descriptor)
                if held_pid == -1:
                    for unresolved in self.unfixed_children.values():
                        summary = unresolved["summary"]
                        if summary["parent_pid"] == task:
                            if "parent_terminal_monotonic_ns" not in summary:
                                raise Failure("受控 SSH 未固定 child 的原父回收缺少终局证据")
                            summary["parent_reaped_monotonic_ns"] = time.monotonic_ns()
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
            for child, unresolved in list(self.unfixed_children.items()):
                summary = unresolved["summary"]
                if "parent_reaped_monotonic_ns" not in summary:
                    continue
                adopted = cleanup_identity(child)
                if (adopted["state"] != "Z" or adopted["ppid"] != os.getpid()
                        or adopted["tracer_pid"] != os.getpid()
                        or adopted["starttime_ticks"] != unresolved["identity"]["starttime_ticks"]):
                    raise Failure("受控 SSH 未固定 child 的收养身份或保留终局已改变")
                terminal = os.waitid(os.P_PID, child, os.WEXITED | os.WNOWAIT | WAIT_FLAGS)
                if terminal is None:
                    continue
                current = (terminal.si_pid, terminal.si_code, terminal.si_status)
                if current != unresolved["terminal"]:
                    raise Failure("受控 SSH 未固定 child 的收养终局与原终局不一致")
                reaped = os.waitid(os.P_PID, child, os.WEXITED | WAIT_FLAGS)
                if reaped is None:
                    continue
                if reaped.si_code in (os.CLD_EXITED, os.CLD_KILLED, os.CLD_DUMPED):
                    # 终局一旦消费立即撤销数字权限，错误返回也不能再次操作旧数字身份。
                    del self.unfixed_children[child]
                    summary["reaped_monotonic_ns"] = time.monotonic_ns()
                if (reaped.si_pid, reaped.si_code, reaped.si_status) != current:
                    summary["unexpected_reaped_terminal"] = {
                        "pid": reaped.si_pid, "si_code": reaped.si_code, "si_status": reaped.si_status,
                    }
                    raise Failure("受控 SSH 未固定 child 精确回收返回了未知终局")
                summary["resolved_monotonic_ns"] = summary["reaped_monotonic_ns"]
                self.evidence["cleanup"].append({
                    "kind": "unfixed-child-reaped", "pid": child,
                    "si_code": reaped.si_code, "si_status": reaped.si_status,
                    "adopted_identity": adopted, "normal": False,
                })
                progressed = True
            if not self.owned and not self.retired and not self.unfixed_children:
                break
            if not progressed:
                time.sleep(0.001)
        if self.unfixed_children:
            raise Failure(f"受控 SSH 清理仍有未固定 child：{sorted(self.unfixed_children)}")
        if self.owned or self.retired:
            raise Failure(f"受控 SSH 清理仍有未回收 task：{sorted(self.tracked | self.retired.keys())}")
        self.evidence["discarded_early_stops"] = sorted(self.early_stops)
        self.evidence["discarded_parent_confirmations"] = sorted(self.pending_children)
        self.early_stops.clear()
        self.pending_children.clear()
        self.evidence["discarded_creation_proofs"] = sorted(self.creations)
        self.creations.clear()
        self.evidence["discarded_syscall_tasks"] = sorted(self.active_syscalls)
        self.active_syscalls.clear()
        self.evidence["discarded_group_proofs"] = sorted(self.group_changes)
        self.group_changes.clear()
        self.first_syscall_exit.clear()
        self.waiting_parent_exit.clear()

    def run(self, child_main):
        if self.master is not None:
            raise Failure("受控 SSH driver 只能执行一次")
        baseline = len(os.listdir("/proc/self/fd"))
        error = None
        previous_subreaper = None
        gate_read = gate_write = None
        try:
            self._check()
            if process_snapshot(os.getpid())["threads"] != 1:
                raise Failure("受控 SSH tracer 必须单线程")
            if os.uname().machine != "x86_64":
                raise Failure("受控 SSH driver 仅验证原生 amd64")
            if signal.getsignal(signal.SIGCHLD) != signal.SIG_DFL:
                raise Failure("受控 SSH master 启动闸门要求默认 SIGCHLD 回收策略")
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
            # shortcut: 仅可信 fixture；排除原生 SIGCHLD flags、atfork、并发 reaper 与外部停止，需要普适保证时改为原子创建。
            gate_read, gate_write = socket.socketpair()
            self.master = os.fork()
            if self.master == 0:
                try:
                    gate_write.close()
                    # 父固定原 pidfd 前不能进入 TRACEME；EOF 或拒绝字节直接退出。
                    allowed = gate_read.recv(1)
                    gate_read.close()
                    if allowed != b"\x01":
                        os._exit(113)
                    self.receiver.close()
                    os.setpgid(0, 0)
                    ptrace(TRACEME, 0)
                    os.kill(os.getpid(), signal.SIGSTOP)
                    child_main()
                except BaseException:
                    os._exit(111)
                os._exit(0)
            gate_read.close()
            gate_read = None
            try:
                self._pin(self.master)
            except BaseException as caught:
                bootstrap = {"pid": self.master, "allowed": False, "pidfd_error": str(caught)}
                self.evidence["bootstrap"] = bootstrap
                gate_write.close()
                gate_write = None
                if self.master in self.owned:
                    raise
                # 尚未允许 ptrace，只在有界期限内精确回收本次直接 fork 的 child。
                self.bootstrap_tasks.add(self.master)
                deadline = time.monotonic() + 2
                while time.monotonic() < deadline:
                    try:
                        waited, status = os.waitpid(self.master, os.WNOHANG)
                    except ChildProcessError as wait_error:
                        bootstrap["wait_error"] = str(wait_error)
                        break
                    if waited:
                        if (waited != self.master
                                or not (os.WIFEXITED(status) or os.WIFSIGNALED(status))):
                            bootstrap["wait_error"] = "启动闸门返回未知或非终止 wait 状态"
                            break
                        self.bootstrap_tasks.discard(self.master)
                        bootstrap.update({"waited_pid": waited, "status": status,
                                          "exit_code": os.waitstatus_to_exitcode(status)})
                        break
                    time.sleep(0.001)
                if self.bootstrap_tasks:
                    bootstrap["unreaped"] = sorted(self.bootstrap_tasks)
                raise
            if gate_write.send(b"\x01", socket.MSG_NOSIGNAL) != 1:
                raise Failure("受控 SSH 启动闸门未送达完整许可字节")
            gate_write.close()
            gate_write = None
            self.evidence["bootstrap"] = {"pid": self.master, "allowed": True}
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
            self._require_stop(pid)
            ptrace(SETOPTIONS, pid, OPTIONS)
            self.evidence["exitkill_set_monotonic_ns"] = time.monotonic_ns()
            self._normal_continue(pid)
            while self.tracked:
                pid, status = self._wait()
                self._event(pid, status)
                self._retire_reaped(force=os.WIFEXITED(status) or os.WIFSIGNALED(status))
            if (self.early_stops or self.pending_children or self.creations
                    or self.active_syscalls or self.first_syscall_exit or self.waiting_parent_exit
                    or self.group_changes):
                raise Failure("受控 SSH driver 存在未完成的 syscall 或 child 关联")
            self.evidence["final_drain"] = copy.deepcopy(self.ledger.drain(self.receiver))
        except BaseException as caught:
            error = caught
            self.evidence["error"] = str(caught)
            self.evidence["failed_monotonic_ns"] = time.monotonic_ns()
            self.ledger.poisoned = True
        finally:
            for gate in (gate_read, gate_write):
                if gate is not None:
                    gate.close()
            self.ledger.close()
            try:
                self._cleanup()
            except BaseException as caught:
                self.evidence["cleanup_error"] = str(caught)
                if error is None:
                    error = caught
            finally:
                for descriptor in list(self.owned.values()) + list(self.retired.values()):
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
                "remaining_bootstrap_tasks": sorted(self.bootstrap_tasks),
                "remaining_owned_tasks": sorted(self.owned),
                "remaining_stopped_tasks": sorted(self.stopped_tasks),
                "remaining_unfixed_children": sorted(self.unfixed_children),
                "remaining_retired_tasks": sorted(self.retired),
                "remaining_early_stops": sorted(self.early_stops),
                "remaining_parent_confirmations": sorted(self.pending_children),
                "remaining_creation_proofs": sorted(self.creations),
                "remaining_syscall_tasks": sorted(self.active_syscalls),
                "remaining_group_changes": sorted(self.group_changes),
                "remaining_first_exit_tasks": sorted(self.first_syscall_exit),
                "remaining_waiting_parent_exit": sorted(self.waiting_parent_exit),
                "open_received_fds": sorted(self.ledger.open_received_fds),
                "fd_count_before": baseline, "fd_count_after": len(os.listdir("/proc/self/fd")),
            })
        if error is not None:
            raise Failure(f"受控 SSH driver 失败：{error}") from error
        return copy.deepcopy(self.evidence)
