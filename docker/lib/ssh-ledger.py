#!/usr/bin/env python3
"""仅供可信 ptrace driver 使用的有限窗口消息账本，不授权 collector 或 jail。"""

import array
import copy
import errno
import importlib.util
import math
import os
from pathlib import Path
import select
import socket
import struct
import time


SPEC = importlib.util.spec_from_file_location(
    "padm_ssh_source_ledger", Path(__file__).with_name("ssh-source.py")
)
source = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(source)
Failure = source.Failure
SO_PASSPIDFD, SCM_PIDFD = 76, 4
GENERATION = ("pid", "starttime_ticks", "pid_ns", "net_ns")


class Ledger:
    """首停、父链与完整事件观察由 driver 保证，state 字符串不证明真实停点。"""

    def __init__(self, deadline):
        self.deadline = deadline
        self.registry = {}
        self.messages = []
        self.open_received_fds = set()
        self.received_count = 0
        self._fds = set()
        self.closed = False
        self.poisoned = False
        self._check()

    def _fail(self, message):
        self.poisoned = True
        self.close()
        raise Failure(message)

    def _check(self):
        if self.closed:
            raise Failure("SSH 消息账本已关闭")
        if (type(self.deadline) not in (int, float) or not math.isfinite(self.deadline)
                or time.monotonic() >= self.deadline):
            self._fail("SSH 消息账本的总窗口已超时")

    def _drop(self, descriptor):
        if descriptor in self._fds:
            self._fds.remove(descriptor)
            self.open_received_fds.discard(descriptor)
            os.close(descriptor)

    def _pidfd(self, descriptor, pid):
        self._check()
        text = Path(f"/proc/self/fdinfo/{descriptor}").read_text()
        fields = dict(line.split(":", 1) for line in text.splitlines() if ":" in line)
        poller = select.poll()
        poller.register(descriptor, select.POLLIN)
        result = {"pid": int(fields.get("Pid", "-1")), "poll": poller.poll(0)}
        self._check()
        if result["pid"] != pid or result["poll"]:
            raise Failure("SSH 消息账本的 pidfd task 已改变")
        return result

    def _process(self, pid):
        self._check()
        root = Path(f"/proc/{pid}")
        fields = (root / "stat").read_text().rsplit(") ", 1)[1].split()
        self._check()
        status = (root / "status").read_text().splitlines()
        self._check()
        result = {
            "pid": pid, "starttime_ticks": int(fields[19]),
            "threads": int(next(line.split(":", 1)[1] for line in status
                                if line.startswith("Threads:"))),
            "exe": os.readlink(root / "exe"),
        }
        for name, entry in (("pid_ns", "pid"), ("net_ns", "net")):
            self._check()
            result[name] = os.readlink(root / "ns" / entry)
        self._check()
        return result

    def _generation(self, snapshot):
        return {name: snapshot[name] for name in GENERATION}

    def register(self, snapshot, accepted_anchor=None):
        self._check()
        try:
            snapshot = copy.deepcopy(snapshot)
            pid = snapshot["pid"]
            if type(pid) is not int or pid <= 0 or pid in self.registry:
                raise Failure("SSH 消息账本拒绝重复或无效的 PID 登记")
            generation = self._generation(snapshot)
            current = self._process(pid)
            if (generation != self._generation(current) or snapshot["threads"] != 1
                    or current["threads"] != 1 or snapshot["exe"] != current["exe"]):
                raise Failure("SSH 消息账本首停的代次或单线程条件无效")
            anchor = copy.deepcopy(accepted_anchor)
            if anchor is not None:
                matches = anchor["accepted_matches"]
                if (self._generation(anchor["process"]) != generation or len(matches) != 1
                        or matches[0]["state"] != "01" or int(matches[0]["inode"]) <= 0):
                    raise Failure("SSH 消息账本首停的 accepted 锚点无效")
                if (anchor["process"]["exe"] != snapshot["exe"]
                        or anchor["process"]["threads"] != 1
                        or not any(value == f'socket:[{matches[0]["inode"]}]'
                                   for _fd, value in snapshot["socket_fds"])
                        or anchor["process"]["socket_fds"] != snapshot["socket_fds"]):
                    raise Failure("SSH 消息账本首停的 accepted FD 锚点不一致")
            self._check()
            descriptor = os.pidfd_open(pid)
            self._fds.add(descriptor)
            self._pidfd(descriptor, pid)
            confirmed = self._process(pid)
            if (self._generation(confirmed) != generation or confirmed["threads"] != 1
                    or confirmed["exe"] != snapshot["exe"]):
                raise Failure("SSH 消息账本登记期间 task 已改变")
            self._pidfd(descriptor, pid)
            self.registry[pid] = {
                "generation": generation, "snapshot": snapshot,
                "held_pidfd": descriptor, "epoch": 0, "epoch_exe": snapshot["exe"],
                "anchor": anchor, "terminal": False, "pending": [],
            }
            return {"pid": pid, "generation": copy.deepcopy(generation),
                    "authoritative": False, "jail_ready": False}
        except Exception as error:
            self._fail(f"SSH 消息账本登记失败：{error}")

    def _receive(self, sock):
        data, ancillary, flags, _ = sock.recvmsg(
            4096, 1024, socket.MSG_DONTWAIT | socket.MSG_CMSG_CLOEXEC
        )
        installed = set()
        try:
            # 先登记全部已安装 FD，后续正文或 proc 解析失败也不能泄漏附件。
            for level, kind, payload in ancillary:
                if level == socket.SOL_SOCKET and kind in (SCM_PIDFD, socket.SCM_RIGHTS):
                    values = array.array("i")
                    values.frombytes(payload[:len(payload) - len(payload) % values.itemsize])
                    installed.update(value for value in values if value >= 0)
            self._fds.update(installed)
            self.received_count += 1
            self._check()
            if self.received_count > 32:
                self._fail("SSH 消息账本的总消息数超过 32 条")
            credentials = [payload for level, kind, payload in ancillary
                           if level == socket.SOL_SOCKET and kind == socket.SCM_CREDENTIALS]
            pidfds = [payload for level, kind, payload in ancillary
                      if level == socket.SOL_SOCKET and kind == SCM_PIDFD]
            row = {"body_bytes": data, "flags": flags, "accepted": False,
                   "pending": False, "rejection": None}
            rejection = None
            if flags & (socket.MSG_TRUNC | socket.MSG_CTRUNC):
                rejection = "truncated"
            elif any(level != socket.SOL_SOCKET or kind not in (
                    socket.SCM_CREDENTIALS, SCM_PIDFD) for level, kind, _ in ancillary):
                rejection = "unexpected_control"
            elif len(credentials) != 1 or len(credentials[0]) != 12:
                rejection = "invalid_credentials"
            elif len(pidfds) != 1 or len(pidfds[0]) != 4:
                rejection = "invalid_pidfd"
            else:
                pid, uid, gid = struct.unpack("3i", credentials[0])
                descriptor = struct.unpack("i", pidfds[0])[0]
                row.update({"credentials": [pid, uid, gid], "pidfd": [{"value": descriptor}]})
                identity = self.registry.get(pid)
                if descriptor < 0:
                    rejection = "invalid_pidfd"
                elif uid != 0 or gid != 0:
                    rejection = "not_root_sender"
                elif identity is None:
                    rejection = "unknown_sender"
                elif identity["terminal"]:
                    rejection = "terminal_sender"
                elif identity["anchor"] is None:
                    rejection = "missing_accepted_anchor"
                else:
                    row["received_pidfd_before"] = self._pidfd(descriptor, pid)
                    row["held_pidfd_before"] = self._pidfd(identity["held_pidfd"], pid)
            try:
                row["body"] = data.decode("utf-8")
            except UnicodeDecodeError:
                rejection = rejection or "invalid_utf8"
            if rejection is None:
                row.update({
                    "sender_pid": pid, "exec_epoch": identity["epoch"],
                    "epoch_exe": identity["epoch_exe"],
                    "historical_anchor": copy.deepcopy(identity["anchor"]),
                    "task_generation": copy.deepcopy(identity["generation"]),
                    "registered_held_pidfd": identity["held_pidfd"],
                    "pending": True, "epoch_source": "enqueue-frozen-ptrace-ledger",
                })
                row["received_pidfd_after"] = self._pidfd(descriptor, pid)
                row["held_pidfd_after"] = self._pidfd(identity["held_pidfd"], pid)
                identity["pending"].append(row)
                installed.remove(descriptor)
                self.open_received_fds.add(descriptor)
            row["rejection"] = rejection
            self.messages.append(row)
            return row
        finally:
            for descriptor in installed:
                self._drop(descriptor)

    def drain(self, sock):
        self._check()
        rows = []
        try:
            while True:
                self._check()
                try:
                    rows.append(self._receive(sock))
                except BlockingIOError as error:
                    if error.errno not in (errno.EAGAIN, errno.EWOULDBLOCK):
                        raise
                    self._check()
                    return {"messages": rows, "ended_with_eagain": True, "errno": error.errno}
        except Exception as error:
            self._fail(f"SSH 消息账本排空失败：{error}")

    def finish_stop(self, sock, pid, event, current_snapshot):
        self._check()
        try:
            batch = self.drain(sock)
            identity = self.registry[pid]
            current = copy.deepcopy(current_snapshot)
            process = current["process"]
            confirmed = self._process(pid)
            self._pidfd(identity["held_pidfd"], pid)
            if (event not in (4, 6) or identity["terminal"]
                    or self._generation(process) != identity["generation"]
                    or self._generation(confirmed) != identity["generation"]
                    or process["threads"] != 1 or confirmed["threads"] != 1
                    or process["exe"] != confirmed["exe"]):
                raise Failure("SSH 消息账本 EXEC/EXIT 停点的代次或单线程条件无效")
            committed = []
            for row in identity["pending"]:
                self._check()
                descriptor = row["pidfd"][0]["value"]
                if (row["task_generation"] != identity["generation"]
                        or row["registered_held_pidfd"] != identity["held_pidfd"]
                        or row["exec_epoch"] != identity["epoch"]
                        or row["epoch_exe"] != identity["epoch_exe"]
                        or row["historical_anchor"] != identity["anchor"]):
                    raise Failure("SSH 消息账本 pending 的代次或 epoch 已改变")
                row["commit_received_pidfd_before"] = self._pidfd(descriptor, pid)
                row["commit_held_pidfd_before"] = self._pidfd(identity["held_pidfd"], pid)
                inodes = {str(match["inode"]) for match in row["historical_anchor"]["accepted_matches"]}
                owned = any(value == f"socket:[{inode}]"
                            for _fd, value in process["socket_fds"] for inode in inodes)
                # 当前持有 FD 与 TCP ESTAB 各自记录，历史锚点不能冒充当前套接字。
                live = owned and any(
                    all(match.get(key) == saved.get(key) for key in ("inode", "local", "remote", "peer"))
                    and match.get("state") == "01"
                    for match in current["accepted_matches"]
                    for saved in row["historical_anchor"]["accepted_matches"])
                row.update({
                    "current_stop_exe": process["exe"],
                    "historical_connection_provenance": copy.deepcopy(row["historical_anchor"]),
                    "current_accepted_matches": copy.deepcopy(current["accepted_matches"]),
                    "owns_anchor_fd": owned, "live_socket_verified": live,
                    "authoritative": False, "jail_ready": False,
                })
                row["established_tuple_live"] = row["live_socket_verified"]
                row["commit_received_pidfd_after"] = self._pidfd(descriptor, pid)
                row["commit_held_pidfd_after"] = self._pidfd(identity["held_pidfd"], pid)
                committed.append(row)
            confirmed = self._process(pid)
            if (self._generation(confirmed) != identity["generation"] or confirmed["threads"] != 1
                    or confirmed["exe"] != process["exe"]):
                raise Failure("SSH 消息账本提交期间 task 已改变")
            self._pidfd(identity["held_pidfd"], pid)
            order = ["drain-eagain", "pending-commit"]
            for row in committed:
                row.update({"accepted": True, "pending": False})
                self._drop(row["pidfd"][0]["value"])
            identity["pending"] = []
            if event == 4:
                identity["epoch"] += 1
                identity["epoch_exe"] = process["exe"]
                order.append("epoch-update")
            else:
                identity["terminal"] = True
                order.append("epoch-terminal")
            self._check()
            return {"pid": pid, "event": event, "drain": batch, "committed_pending": committed,
                    "order": order, "epoch_after": identity["epoch"],
                    "authoritative": False, "jail_ready": False}
        except Exception as error:
            self._fail(f"SSH 消息账本停点提交失败：{error}")

    def retire_terminal(self, pid, generation, held_pidfd):
        self._check()
        try:
            identity = self.registry[pid]
            if (not identity["terminal"] or identity["pending"]
                    or identity["generation"] != generation
                    or identity["held_pidfd"] != held_pidfd or held_pidfd not in self._fds):
                raise Failure("SSH 消息账本退役缺少完整终结身份")
            fields = dict(line.split(":", 1) for line in
                          Path(f"/proc/self/fdinfo/{held_pidfd}").read_text().splitlines()
                          if ":" in line)
            if int(fields.get("Pid", "-2")) != -1:
                raise Failure("SSH 消息账本原 task 尚未真正回收")
            self._check()
            row = {"pid": pid, "generation": copy.deepcopy(identity["generation"]),
                   "epoch": identity["epoch"], "epoch_exe": identity["epoch_exe"],
                   "held_pidfd": held_pidfd, "held_pidfd_pid": -1,
                   "authoritative": False, "jail_ready": False}
            # 历史消息仍由 poison 撤销；这里只释放已真回收的身份，不重置 epoch 或预算。
            self._drop(held_pidfd)
            del self.registry[pid]
            return row
        except Exception as error:
            self._fail(f"SSH 消息账本身份退役失败：{error}")

    def close(self):
        if self.closed:
            return
        self.closed = True
        for row in self.messages:
            if row.get("pending") or self.poisoned:
                row.update({"pending": False, "accepted": False,
                            "rejection": row["rejection"] or "ledger_closed"})
        for identity in self.registry.values():
            identity["pending"] = []
        for descriptor in list(self._fds):
            self._drop(descriptor)
