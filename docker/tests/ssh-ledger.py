#!/usr/bin/env python3
import array
import copy
import importlib.util
import os
from pathlib import Path
import signal
import socket
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "padm_ssh_ledger", ROOT / "docker/lib/ssh-ledger.py"
)
ledger_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ledger_module)
Ledger = ledger_module.Ledger


def process_snapshot(pid):
    root = Path(f"/proc/{pid}")
    fields = (root / "stat").read_text().rsplit(") ", 1)[1].split()
    status = (root / "status").read_text().splitlines()
    socket_fds = []
    for fd in (root / "fd").iterdir():
        try:
            target = os.readlink(fd)
        except OSError:
            continue
        if target.startswith("socket:["):
            socket_fds.append([int(fd.name), target])
    return {
        "pid": pid, "ppid": int(fields[1]), "starttime_ticks": int(fields[19]),
        "exe": os.readlink(root / "exe"),
        "pid_ns": os.readlink(root / "ns/pid"),
        "net_ns": os.readlink(root / "ns/net"),
        "mount_ns": os.readlink(root / "ns/mnt"),
        "cgroup": (root / "cgroup").read_text().splitlines(),
        "threads": int(next(line.split(":", 1)[1] for line in status
                            if line.startswith("Threads:"))),
        "socket_fds": socket_fds,
    }


class LedgerContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="padm-ledger-")
        self.path = Path(self.temp.name) / "receiver.sock"
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_PASSCRED, 1)
        self.sock.setsockopt(socket.SOL_SOCKET, ledger_module.SO_PASSPIDFD, 1)
        self.sock.setblocking(False)
        self.sock.bind(str(self.path))
        self.ledger = None
        self.children = set()
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        self.client = socket.socket()
        self.client.connect(listener.getsockname())
        self.accepted, _ = listener.accept()
        listener.close()

    def tearDown(self):
        if self.ledger is not None:
            self.ledger.close()
        for pid in self.children:
            try:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            except ProcessLookupError:
                pass
        self.accepted.close()
        self.client.close()
        self.sock.close()
        self.temp.cleanup()

    def anchor(self, snapshot):
        inode = next(value[8:-1] for fd, value in snapshot["socket_fds"]
                     if fd == self.accepted.fileno())
        for line in Path(f"/proc/{snapshot['pid']}/net/tcp").read_text().splitlines()[1:]:
            fields = line.split()
            if fields[9] == inode:
                self.assertEqual(fields[3], "01")
                return {
                    "process": snapshot, "accepted_matches": [{
                        "inode": int(inode), "state": "01",
                        "local": fields[1], "remote": fields[2],
                    }],
                }
        self.fail("受控 accepted FD 缺少真实 TCP 行")

    def sender(self, bodies, with_rights=False):
        pid = os.fork()
        if pid == 0:
            try:
                sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
                for index, body in enumerate(bodies):
                    ancillary = []
                    opened = None
                    if with_rights and index == 0:
                        opened = os.open("/dev/null", os.O_RDONLY)
                        ancillary.append((
                            socket.SOL_SOCKET, socket.SCM_RIGHTS,
                            array.array("i", [opened]).tobytes(),
                        ))
                    sock.sendmsg([body], ancillary, 0, str(self.path))
                    if opened is not None:
                        os.close(opened)
                    os.kill(os.getpid(), signal.SIGSTOP)
                sock.close()
                os._exit(0)
            except BaseException:
                os._exit(111)
        self.children.add(pid)
        _, status = os.waitpid(pid, os.WUNTRACED)
        self.assertTrue(os.WIFSTOPPED(status))
        return pid

    def continue_sender(self, pid):
        os.kill(pid, signal.SIGCONT)
        _, status = os.waitpid(pid, os.WUNTRACED)
        self.assertTrue(os.WIFSTOPPED(status))

    def reap(self, pid):
        os.kill(pid, signal.SIGKILL)
        _, status = os.waitpid(pid, 0)
        self.assertTrue(os.WIFSIGNALED(status))
        self.children.discard(pid)

    def test_exec_exit_epoch_and_pending_fd_cleanup(self):
        pid = self.sender([b"old-epoch", b"new-epoch"])
        snapshot = process_snapshot(pid)
        self.ledger = Ledger(time.monotonic() + 5)
        accepted_anchor = self.anchor(snapshot)
        self.ledger.register(snapshot, accepted_anchor)
        accepted_anchor["accepted_matches"][0]["inode"] += 1
        snapshot["exe"] = "caller-mutation"
        frozen = self.ledger.registry[pid]
        self.assertNotEqual(frozen["snapshot"]["exe"], snapshot["exe"])
        pending = self.ledger.drain(self.sock)["messages"][0]
        message_fd = pending["pidfd"][0]["value"]
        self.assertTrue(pending["pending"])
        self.assertFalse(os.get_inheritable(message_fd))
        os.fstat(message_fd)
        current = {"process": process_snapshot(pid), "accepted_matches": []}
        first = self.ledger.finish_stop(self.sock, pid, 4, current)
        self.assertEqual(first["committed_pending"][0]["exec_epoch"], 0)
        self.assertEqual(first["committed_pending"][0]["epoch_exe"], frozen["snapshot"]["exe"])
        self.assertEqual(first["epoch_after"], 1)
        self.assertEqual(first["order"], ["drain-eagain", "pending-commit", "epoch-update"])
        self.assertFalse(self.ledger.open_received_fds)
        with self.assertRaises(OSError):
            os.fstat(message_fd)
        self.continue_sender(pid)
        current = {"process": process_snapshot(pid), "accepted_matches": []}
        second = self.ledger.finish_stop(self.sock, pid, 6, current)
        self.assertEqual(second["committed_pending"][0]["exec_epoch"], 1)
        self.assertEqual(second["epoch_after"], 1)
        self.assertFalse(second["committed_pending"][0]["live_socket_verified"])
        self.assertEqual(second["committed_pending"][0]["current_accepted_matches"], [])
        self.assertTrue(second["committed_pending"][0]["owns_anchor_fd"])
        self.assertTrue(self.ledger.registry[pid]["terminal"])
        self.reap(pid)

    def test_unknown_reaped_truncated_non_utf8_and_rights_rejected(self):
        for body, expected, with_rights in (
            (b"unknown", "unknown_sender", False),
            (b"x" * 5000, "truncated", False),
            (b"\xffinvalid", "invalid_utf8", False),
            (b"rights", "unexpected_control", True),
        ):
            with self.subTest(expected=expected):
                pid = self.sender([body], with_rights=with_rights)
                ledger = Ledger(time.monotonic() + 5)
                self.ledger = ledger
                if expected == "invalid_utf8":
                    snapshot = process_snapshot(pid)
                    ledger.register(snapshot, self.anchor(snapshot))
                before = len(os.listdir("/proc/self/fd"))
                row = ledger.drain(self.sock)["messages"][0]
                after = len(os.listdir("/proc/self/fd"))
                self.assertFalse(row["accepted"])
                self.assertEqual(row["rejection"], expected)
                self.assertEqual(before, after)
                ledger.close()
                self.reap(pid)

        pid = self.sender([b"reaped"])
        os.kill(pid, signal.SIGCONT)
        _, status = os.waitpid(pid, 0)
        self.assertTrue(os.WIFEXITED(status))
        self.children.discard(pid)
        ledger = Ledger(time.monotonic() + 5)
        self.ledger = ledger
        row = ledger.drain(self.sock)["messages"][0]
        self.assertEqual(row["rejection"], "invalid_pidfd")
        ledger.close()

    def test_close_is_idempotent_and_deadline_poison_closes_held_pidfd(self):
        pid = self.sender([b"deadline"])
        snapshot = process_snapshot(pid)
        self.ledger = Ledger(time.monotonic() + 5)
        ledger = self.ledger
        ledger.register(snapshot, self.anchor(snapshot))
        pending = ledger.drain(self.sock)["messages"][0]
        held = ledger.registry[pid]["held_pidfd"]
        received = pending["pidfd"][0]["value"]
        ledger.close()
        ledger.close()
        for descriptor in (held, received):
            with self.assertRaises(OSError):
                os.fstat(descriptor)
        self.assertFalse(pending["pending"])
        self.reap(pid)

        for deadline in (time.monotonic() - 1, float("nan"), float("inf"), "5"):
            with self.subTest(deadline=deadline), self.assertRaises(ledger_module.Failure):
                Ledger(deadline)

    def test_generation_epoch_and_timeout_fail_closed(self):
        for field in ("generation", "epoch", "deadline", "duplicate_pid"):
            with self.subTest(field=field):
                pid = self.sender([field.encode()])
                snapshot = process_snapshot(pid)
                self.ledger = Ledger(time.monotonic() + 5)
                self.ledger.register(snapshot, self.anchor(snapshot))
                row = self.ledger.drain(self.sock)["messages"][0]
                held = self.ledger.registry[pid]["held_pidfd"]
                received = row["pidfd"][0]["value"]
                if field == "generation":
                    changed = copy.deepcopy(snapshot)
                    changed["starttime_ticks"] += 1
                else:
                    changed = process_snapshot(pid)
                if field == "epoch":
                    self.ledger.registry[pid]["epoch"] += 1
                elif field == "deadline":
                    self.ledger.deadline = time.monotonic() - 1
                with self.assertRaises(ledger_module.Failure):
                    if field == "duplicate_pid":
                        self.ledger.register(snapshot, self.anchor(snapshot))
                    else:
                        self.ledger.finish_stop(self.sock, pid, 4, {
                            "process": changed, "accepted_matches": [],
                        })
                self.assertTrue(self.ledger.poisoned)
                self.assertTrue(self.ledger.closed)
                self.assertFalse(row["accepted"])
                self.assertFalse(row["pending"])
                for descriptor in (held, received):
                    with self.assertRaises(OSError):
                        os.fstat(descriptor)
                with self.assertRaises(ledger_module.Failure):
                    self.ledger.drain(self.sock)
                self.reap(pid)

    def test_total_bound_terminal_and_missing_anchor(self):
        pid = self.sender([b"pending-before-bound"])
        snapshot = process_snapshot(pid)
        self.ledger = Ledger(time.monotonic() + 5)
        self.ledger.register(snapshot, self.anchor(snapshot))
        pending = self.ledger.drain(self.sock)["messages"][0]
        held = self.ledger.registry[pid]["held_pidfd"]
        received = pending["pidfd"][0]["value"]
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sender:
            for _ in range(31):
                sender.sendto(b"bounded-unknown", str(self.path))
                self.assertTrue(self.ledger.drain(self.sock)["ended_with_eagain"])
            sender.sendto(b"message-33", str(self.path))
            with self.assertRaises(ledger_module.Failure):
                self.ledger.drain(self.sock)
        self.assertTrue(self.ledger.poisoned)
        self.assertTrue(self.ledger.closed)
        self.assertEqual(self.ledger.received_count, 33)
        self.assertFalse(pending["pending"])
        self.assertFalse(pending["accepted"])
        self.assertFalse(self.ledger._fds)
        self.assertFalse(self.ledger.open_received_fds)
        for descriptor in (held, received):
            with self.assertRaises(OSError):
                os.fstat(descriptor)
        self.reap(pid)

        for terminal in (False, True):
            pid = self.sender([b"restricted"])
            snapshot = process_snapshot(pid)
            self.ledger = Ledger(time.monotonic() + 5)
            self.ledger.register(snapshot, self.anchor(snapshot) if terminal else None)
            self.ledger.registry[pid]["terminal"] = terminal
            before = len(os.listdir("/proc/self/fd"))
            row = self.ledger.drain(self.sock)["messages"][0]
            self.assertEqual(row["rejection"],
                             "terminal_sender" if terminal else "missing_accepted_anchor")
            self.assertFalse(self.ledger.open_received_fds)
            self.assertEqual(before, len(os.listdir("/proc/self/fd")))
            self.ledger.close()
            self.reap(pid)


if __name__ == "__main__":
    unittest.main()
