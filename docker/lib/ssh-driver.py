#!/usr/bin/env python3
"""仅驱动自己创建的可信单线程 fixture，不接收外部 PID，不授权 collector 或 jail。"""

import copy
import ctypes
import importlib.util
import os
from pathlib import Path
import signal
import socket
import time


SPEC = importlib.util.spec_from_file_location(
    "padm_ssh_driver_ledger", Path(__file__).with_name("ssh-ledger.py")
)
ledger_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ledger_module)
Failure = ledger_module.Failure
TRACEME, CONT, SETOPTIONS, GETEVENTMSG = 0, 7, 0x4200, 0x4201
FORK, VFORK, CLONE, EXEC, EXIT = 1, 2, 3, 4, 6
OPTIONS = 0x2 | 0x4 | 0x8 | 0x10 | 0x40 | 0x00100000
WAIT_FLAGS = os.WNOHANG | 0x40000000
libc = ctypes.CDLL(None, use_errno=True)
libc.ptrace.argtypes = [ctypes.c_ulong, ctypes.c_ulong, ctypes.c_void_p, ctypes.c_void_p]
libc.ptrace.restype = ctypes.c_long


def ptrace(request, pid, data=0):
    result = libc.ptrace(request, pid, None, ctypes.c_void_p(data))
    if result == -1:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))
    return result


def event_message(pid):
    value = ctypes.c_ulong()
    ptrace(GETEVENTMSG, pid, ctypes.addressof(value))
    return value.value


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
        "pid": pid, "ppid": int(fields[1]), "pgrp": int(fields[2]), "state": fields[0],
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
    """callback 必须可信；event 1 和 Threads=1 不证明 fork/clone flags 安全。"""

    def __init__(self, deadline, receiver, expected_tuple):
        self.ledger = ledger_module.Ledger(deadline)
        self.receiver = receiver
        self.expected_tuple = copy.deepcopy(expected_tuple)
        self.master = None
        self.tracked = set()
        self.registered = set()
        self.pending_children = {}
        self.early_stops = {}
        self.evidence = {
            "authoritative": False, "jail_ready": False,
            "scope": "只用于可信普通 fork fixture；未审计创建 flags，不支持任意 OpenSSH",
            "events": [], "first_stops": [], "continues": [], "cleanup": [],
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
            time.sleep(0.001)

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

    def _normal_continue(self, pid, delivered_signal=0):
        if pid not in self.registered:
            raise Failure("受控 SSH driver 拒绝继续未登记 task")
        # finish_stop 返回后仍可能超时，实际 CONT 前再检查总期限。
        self._check()
        ptrace(CONT, pid, delivered_signal)
        self.evidence["continues"].append({
            "pid": pid, "signal": delivered_signal, "normal": True,
            "returned_monotonic_ns": time.monotonic_ns(),
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
        self.ledger._pidfd(parent_identity["held_pidfd"], parent)
        if (self.ledger._generation(parent_process) != parent_identity["generation"]
                or parent_process["exe"] != parent_identity["epoch_exe"]
                or current != frozen or process["ppid"] != parent
                or process["pid_ns"] != parent_process["pid_ns"]
                or process["net_ns"] != parent_process["net_ns"]
                or len(current["accepted_matches"]) != 1
                or len(parent_anchor["accepted_matches"]) != 1
                or current["accepted_matches"][0] != parent_anchor["accepted_matches"][0]):
            raise Failure("受控 SSH child 首停的父链、代次或 accepted 继承无效")
        self.ledger.register(process, current)
        self.registered.add(pid)
        row = {
            "pid": pid, "parent_pid": parent, "snapshot": copy.deepcopy(current),
            "first_stop": copy.deepcopy(first), "parent_fork_anchor": copy.deepcopy(parent_anchor),
            "registered_monotonic_ns": time.monotonic_ns(),
        }
        row["first_continue_monotonic_ns"] = self._normal_continue(pid)
        self.evidence["first_stops"].append(row)

    def _event(self, pid, status):
        event = status >> 16 if os.WIFSTOPPED(status) else 0
        row = {"pid": pid, "status": status, "event": event,
               "wait_monotonic_ns": time.monotonic_ns()}
        try:
            if os.WIFEXITED(status) or os.WIFSIGNALED(status):
                row.update({"kind": "reaped", "exit_code": os.waitstatus_to_exitcode(status)})
                self.tracked.discard(pid)
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
                if len(parent_anchor["accepted_matches"]) != 1:
                    raise Failure("受控 SSH fork 停点缺少唯一 live accepted 锚点")
                row.update({"kind": "fork-parent-stop", "parent_fork_anchor": parent_anchor})
                self.pending_children[child] = (pid, copy.deepcopy(parent_anchor))
                if child in self.early_stops:
                    first, current = self.early_stops.pop(child)
                    self.pending_children.pop(child)
                    self._register_child(child, pid, parent_anchor, first, current)
                row["continued_monotonic_ns"] = self._normal_continue(pid)
            elif pid not in self.registered and event == 0 and os.WSTOPSIG(status) == signal.SIGSTOP:
                if pid in self.early_stops:
                    raise Failure("受控 SSH child 首停重复")
                current = self._sample(pid)
                row.update({"kind": "child-first-stop", "current": current})
                if pid in self.pending_children:
                    parent, parent_anchor = self.pending_children.pop(pid)
                    self._register_child(pid, parent, parent_anchor, row, current)
                else:
                    row["held_without_continue"] = True
                    self.early_stops[pid] = (copy.deepcopy(row), copy.deepcopy(current))
            elif event in (EXEC, EXIT):
                if pid not in self.registered:
                    raise Failure("受控 SSH EXEC/EXIT task 未登记")
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
            self.evidence["events"].append(copy.deepcopy(row))

    def _cleanup(self):
        if not self.tracked:
            return
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
                self.tracked.discard(pid)
                row.update({"kind": "cleanup-reaped", "exit_code": os.waitstatus_to_exitcode(status)})
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

        group_finished = False
        while time.monotonic() < end:
            progressed = False
            # 总期限可能在消费创建事件前到达；清理也要发现进程组内的新 task。
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
            if not self.tracked and group_finished:
                break
            if not progressed:
                time.sleep(0.001)
        if self.tracked or not group_finished:
            raise Failure(f"受控 SSH 清理仍有未回收 task：{sorted(self.tracked)}")
        self.evidence["discarded_early_stops"] = sorted(self.early_stops)
        self.evidence["discarded_parent_confirmations"] = sorted(self.pending_children)
        self.early_stops.clear()
        self.pending_children.clear()

    def run(self, child_main):
        if self.master is not None:
            raise Failure("受控 SSH driver 只能执行一次")
        baseline = len(os.listdir("/proc/self/fd"))
        error = None
        try:
            self._check()
            if process_snapshot(os.getpid())["threads"] != 1:
                raise Failure("受控 SSH tracer 必须单线程")
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
            ptrace(SETOPTIONS, pid, OPTIONS)
            self.evidence["exitkill_set_monotonic_ns"] = time.monotonic_ns()
            self._normal_continue(pid)
            while self.tracked:
                self._event(*self._wait())
            if self.early_stops or self.pending_children:
                raise Failure("受控 SSH driver 存在未确认的 child 首停")
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
            self.evidence.update({
                "messages": copy.deepcopy(self.ledger.messages), "ledger_closed": self.ledger.closed,
                "ledger_poisoned": self.ledger.poisoned, "remaining_tracees": sorted(self.tracked),
                "remaining_early_stops": sorted(self.early_stops),
                "remaining_parent_confirmations": sorted(self.pending_children),
                "open_received_fds": sorted(self.ledger.open_received_fds),
                "fd_count_before": baseline, "fd_count_after": len(os.listdir("/proc/self/fd")),
            })
        if error is not None:
            raise Failure(f"受控 SSH driver 失败：{error}") from error
        return copy.deepcopy(self.evidence)
