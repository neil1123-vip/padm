#!/usr/bin/env python3
import copy
import errno
import importlib.util
import json
import os
from pathlib import Path
import resource
import select
import signal
import socket
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("padm_ssh_driver", ROOT / "docker/lib/ssh-driver.py")
driver_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(driver_module)


class DriverContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix="padm-ssh-driver-build-")
        cls.helper = str(Path(cls.build.name) / "helper")
        try:
            subprocess.run(["cc", "-pthread", "-Wall", "-Wextra", "-Werror", "-O2",
                            str(ROOT / "docker/tests/fixtures/ssh-driver-helper.c"),
                            "-o", cls.helper], check=True, capture_output=True)
        except BaseException:
            cls.build.cleanup()
            raise

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def setUp(self):
        self.subreaper_before = driver_module.ctypes.c_int()
        if driver_module.libc.prctl(driver_module.PR_GET_CHILD_SUBREAPER,
                                   driver_module.ctypes.byref(self.subreaper_before), 0, 0, 0) != 0:
            raise OSError("不能读取测试 subreaper 状态")
        self.temp = tempfile.TemporaryDirectory(prefix="padm-ssh-driver-")
        self.path = str(Path(self.temp.name) / "receiver.sock")
        self.receiver = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        self.receiver.setsockopt(socket.SOL_SOCKET, socket.SO_PASSCRED, 1)
        self.receiver.setsockopt(socket.SOL_SOCKET, driver_module.ledger_module.SO_PASSPIDFD, 1)
        self.receiver.setblocking(False)
        self.receiver.bind(self.path)
        self.listener = socket.socket()
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(1)
        self.client = socket.socket()
        self.client.connect(self.listener.getsockname())
        self.expected = {"local": list(self.listener.getsockname()),
                         "remote": list(self.client.getsockname())}
        self.driver = None

    def tearDown(self):
        if self.driver is not None:
            self.driver.ledger.close()
        self.client.close()
        self.listener.close()
        self.receiver.close()
        self.temp.cleanup()

    def cross_exec(self, group_change=None, ignore_sigchld=False):
        self.client.close()
        accepted, _ = self.listener.accept()
        self.listener.close()
        accepted.set_inheritable(True)
        child = os.fork()
        if child == 0:
            if group_change is not None:
                if group_change == "setpgid":
                    os.setpgid(0, 0)
                else:
                    os.setsid()
                if ignore_sigchld:
                    signal.signal(signal.SIGCHLD, signal.SIG_IGN)
                grandchild = os.fork()
                if grandchild:
                    accepted.close()
                    _, status = os.waitpid(grandchild, 0)
                    os._exit(0 if os.WIFEXITED(status) and os.WEXITSTATUS(status) == 23 else 112)
            sender = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            sender.sendto(b"old-epoch-zero", self.path)
            sender.close()
            os.kill(os.getpid(), signal.SIGSTOP)
            os.execv(self.helper, [self.helper, "cross-exec", self.path, str(accepted.fileno())])
        accepted.close()
        _, status = os.waitpid(child, 0)
        expected = 0 if group_change is not None else 23
        os._exit(0 if os.WIFEXITED(status) and os.WEXITSTATUS(status) == expected else 112)

    def assert_clean(self, evidence):
        current = driver_module.ctypes.c_int()
        self.assertEqual(driver_module.libc.prctl(driver_module.PR_GET_CHILD_SUBREAPER,
                                                 driver_module.ctypes.byref(current), 0, 0, 0), 0)
        self.assertEqual(current.value, self.subreaper_before.value)
        self.assertEqual(evidence["subreaper_before"], self.subreaper_before.value)
        self.assertTrue(evidence["subreaper_restored"])
        self.assertFalse(evidence["remaining_tracees"])
        self.assertFalse(evidence["remaining_retired_tasks"])
        self.assertFalse(evidence["remaining_early_stops"])
        self.assertFalse(evidence["remaining_parent_confirmations"])
        self.assertFalse(evidence["remaining_creation_proofs"])
        self.assertFalse(evidence["remaining_group_changes"])
        self.assertFalse(evidence["remaining_syscall_tasks"])
        self.assertFalse(evidence["remaining_first_exit_tasks"])
        self.assertFalse(evidence["remaining_waiting_parent_exit"])
        self.assertFalse(evidence["remaining_owned_tasks"])
        self.assertFalse(evidence["remaining_stopped_tasks"])
        self.assertFalse(evidence["remaining_bootstrap_tasks"])
        self.assertFalse(evidence["remaining_unfixed_children"])
        self.assertFalse(evidence["open_received_fds"])
        self.assertEqual(evidence["fd_count_before"], evidence["fd_count_after"])
        self.assertFalse(evidence["authoritative"])
        self.assertFalse(evidence["jail_ready"])
        self.assertTrue(evidence["ledger_closed"])

    def assert_tasks_reaped(self, *pids):
        for pid in pids:
            self.assertFalse(Path(f"/proc/{pid}").exists(), f"task {pid} 仍未真正回收")
            with self.assertRaises(ChildProcessError):
                os.waitpid(pid, os.WNOHANG)

    def assert_exec_history(self, evidence, pid):
        old, new, closed = evidence["messages"]
        self.assertEqual([row["body"] for row in (old, new, closed)],
                         ["old-epoch-zero", "new-epoch-one", "closed-accepted-fd"])
        self.assertTrue(all(row["accepted"] for row in evidence["messages"]))
        self.assertTrue(all(row["sender_pid"] == pid for row in evidence["messages"]))
        self.assertEqual([row["exec_epoch"] for row in (old, new, closed)], [0, 1, 1])
        self.assertEqual(old["task_generation"], new["task_generation"])
        self.assertNotEqual(old["epoch_exe"], old["current_stop_exe"])
        self.assertEqual(old["current_stop_exe"], self.helper)
        self.assertEqual(new["epoch_exe"], self.helper)
        self.assertFalse(closed["owns_anchor_fd"])
        self.assertFalse(closed["established_tuple_live"])
        self.assertTrue(closed["historical_anchor"]["accepted_matches"])
        transitions = [row for row in evidence["events"]
                       if row["pid"] == pid and row.get("event") in (4, 6)]
        self.assertEqual([row["event"] for row in transitions], [4, 6])
        self.assertEqual(transitions[0]["ledger"]["order"],
                         ["drain-eagain", "pending-commit", "epoch-update"])
        self.assertEqual(transitions[1]["ledger"]["order"],
                         ["drain-eagain", "pending-commit", "epoch-terminal"])
        for row in transitions:
            self.assertTrue(row["ledger"]["drain"]["ended_with_eagain"])
            self.assertLess(row["finish_return_monotonic_ns"], row["continued_monotonic_ns"])
        return transitions

    def real_emfile_pidfd(self, open_pidfd, pid, *args, **kwargs):
        limits = resource.getrlimit(resource.RLIMIT_NOFILE)
        limit = max(int(value) for value in os.listdir("/proc/self/fd")) + 4
        if limits[0] != resource.RLIM_INFINITY:
            limit = min(limit, limits[0])
        dummy = []
        try:
            resource.setrlimit(resource.RLIMIT_NOFILE, (limit, limits[1]))
            for _ in range(limit):
                try:
                    dummy.append(os.open("/dev/null", os.O_RDONLY | os.O_CLOEXEC))
                except OSError as full:
                    if full.errno != errno.EMFILE:
                        raise
                    break
            return open_pidfd(pid, *args, **kwargs)
        finally:
            for opened in dummy:
                os.close(opened)
            resource.setrlimit(resource.RLIMIT_NOFILE, limits)

    def test_python_to_c_epoch_history_and_frozen_trace(self):
        self.driver = driver_module.ControlledDriver(time.monotonic() + 5, self.receiver, self.expected)
        original_wait = self.driver._wait
        early_child, forced_child_first_stop = {}, []

        def child_before_parent_exit(initial=False):
            creation = self.driver.creations.get(self.driver.master)
            if (not initial and creation and "event_child" not in creation
                    and not early_child):
                deadline = self.driver.ledger.deadline
                while time.monotonic() < deadline:
                    observed = os.waitid(
                        os.P_PIDFD, self.driver.owned[self.driver.master],
                        os.WSTOPPED | os.WNOHANG | os.WNOWAIT | 0x40000000)
                    if (observed and observed.si_code == os.CLD_TRAPPED
                            and observed.si_status >> 8 == driver_module.FORK):
                        child = driver_module.event_message(self.driver.master)
                        current = driver_module.process_snapshot(child)
                        if current["state"] == "t":
                            # 未消费父 FORK 前只观察真实首停，不等待未知 PID。
                            self.assertNotIn(child, self.driver.owned)
                            early_child.update({"pid": child, "snapshot": current,
                                                "observed_ns": time.monotonic_ns()})
                            break
                    time.sleep(0)
                else:
                    raise TimeoutError("真实 child 首停等待超时")
            if (not initial and early_child and not forced_child_first_stop
                    and creation and creation.get("event_child") == early_child["pid"]):
                child = early_child["pid"]
                self.assertIn(child, self.driver.owned)
                while time.monotonic() < self.driver.ledger.deadline:
                    result = self.driver._wait_original(child)
                    if result:
                        forced_child_first_stop.append(child)
                        return result
                    time.sleep(0)
                raise TimeoutError("已固定 child 的真实首停等待超时")
            return original_wait(initial)

        self.driver._wait = child_before_parent_exit
        evidence = self.driver.run(self.cross_exec)
        self.assert_clean(evidence)
        self.assertGreater(evidence["wait_pidfd_count"], 0)
        self.assertTrue(evidence["bootstrap"]["allowed"])
        self.assertEqual(len(evidence["first_stops"]), 1)
        self.assertTrue(early_child)
        self.assertTrue(forced_child_first_stop)
        first_stop_event = next(row for row in evidence["events"]
                                if row.get("kind") == "child-first-stop")
        self.assertTrue(first_stop_event["held_without_continue"])
        fork_event = next(row for row in evidence["events"] if row.get("kind") == "fork-parent-stop")
        pinned = next(row for row in evidence["task_pins"] if row["pid"] == early_child["pid"])
        self.assertLess(early_child["observed_ns"], fork_event["wait_monotonic_ns"])
        self.assertLess(fork_event["wait_monotonic_ns"], pinned["pinned_monotonic_ns"])
        self.assertLess(pinned["pinned_monotonic_ns"], first_stop_event["wait_monotonic_ns"])
        creation = evidence["creations"][0]
        self.assertIn(creation["entry"]["nr"], (driver_module.SYS_CLONE, driver_module.SYS_FORK))
        self.assertEqual(creation["event_child"], creation["exit_rval"])
        self.assertEqual(early_child["pid"], creation["event_child"])
        self.assertEqual(early_child["snapshot"]["starttime_ticks"],
                         evidence["first_stops"][0]["snapshot"]["process"]["starttime_ticks"])
        self.assertLess(creation["entry_monotonic_ns"], creation["event_monotonic_ns"])
        self.assertLess(creation["event_monotonic_ns"], creation["exit_monotonic_ns"])
        self.assertLess(creation["exit_monotonic_ns"],
                        evidence["first_stops"][0]["first_continue_monotonic_ns"])
        self.assertTrue(evidence["syscall_stop_count"])
        self.assertLess(len(evidence["events"]), evidence["syscall_stop_count"])
        child = evidence["first_stops"][0]["pid"]
        barriers = [row for row in evidence["events"] if row.get("kind") == "message-barrier"]
        self.assertEqual(len(barriers), 1)
        frozen = barriers[0]["pending_at_barrier"][0]
        self.assertTrue(frozen["pending"])
        self.assertFalse(frozen["accepted"])
        self.assertEqual(frozen["exec_epoch"], 0)
        self.assertEqual(len(barriers[0]["received_fds_at_barrier"]), 1)
        self.assert_exec_history(evidence, child)
        reaped = [row["exit_code"] for row in evidence["events"] if row.get("kind") == "reaped"]
        self.assertEqual(sorted(reaped), [0, 23])
        original = copy.deepcopy(evidence["events"])
        self.driver.ledger.messages[0]["body"] = "later-mutation"
        self.assertEqual(evidence["events"], original)
        print(json.dumps({
            "kind": "verified-creation-syscall",
            "creation_entry": {key: creation["entry"][key] for key in ("nr", "args", "arch")},
            "syscall_stop_count": evidence["syscall_stop_count"],
            "normal_resume_count": evidence["normal_resume_count"],
        }, sort_keys=True, separators=(",", ":")), flush=True)

    def test_master_pidfd_failure_denies_bootstrap_and_preserves_caller_stop(self):
        marker = Path(self.temp.name) / "bootstrap-callback-executed"
        original_pidfd_open, original_waitpid = os.pidfd_open, os.waitpid
        initial_limits = resource.getrlimit(resource.RLIMIT_NOFILE)
        for code in (errno.EMFILE, errno.EPERM, errno.ENOMEM):
            with self.subTest(errno=code):
                unrelated = os.fork()
                if unrelated == 0:
                    self.receiver.close()
                    self.listener.close()
                    self.client.close()
                    os.kill(os.getpid(), signal.SIGSTOP)
                    os._exit(29)
                descriptor = original_pidfd_open(unrelated)
                reaped = False
                try:
                    deadline = time.monotonic() + 3
                    while time.monotonic() < deadline:
                        stopped = os.waitid(os.P_PIDFD, descriptor,
                                            os.WSTOPPED | os.WNOHANG | os.WNOWAIT)
                        if stopped:
                            break
                        time.sleep(0.001)
                    self.assertIsNotNone(stopped)
                    self.assertEqual((stopped.si_pid, stopped.si_code, stopped.si_status),
                                     (unrelated, os.CLD_STOPPED, signal.SIGSTOP))
                    self.driver = driver_module.ControlledDriver(time.monotonic() + 5,
                                                                 self.receiver, self.expected)
                    injected, bootstrap_waits, before_pidfd = [], [], {}

                    def fail_master_pidfd(pid, *args, **kwargs):
                        if pid == self.driver.master and not injected:
                            process = driver_module.process_snapshot(pid)
                            self.assertEqual(process["tracer_pid"], 0)
                            self.assertNotIn(process["state"], ("t", "T", "Z"))
                            self.assertNotIn(pid, self.driver.owned)
                            before_pidfd.update({key: process[key] for key in
                                                 ("pid", "state", "tracer_pid")})
                            injected.append(pid)
                            if code == errno.EMFILE:
                                before_pidfd["real_syscall_failure"] = True
                                return self.real_emfile_pidfd(original_pidfd_open, pid, *args, **kwargs)
                            raise OSError(code, os.strerror(code))
                        return original_pidfd_open(pid, *args, **kwargs)

                    def exact_bootstrap_wait(pid, flags):
                        self.assertEqual((pid, flags), (self.driver.master, os.WNOHANG))
                        bootstrap_waits.append(pid)
                        return original_waitpid(pid, flags)

                    def child_main():
                        marker.touch()

                    # 首次固定失败时只收回屏障内的直接 child，不能动 caller 的等待状态。
                    with (
                        patch.object(driver_module.os, "pidfd_open", fail_master_pidfd),
                        patch.object(driver_module.os, "waitpid", exact_bootstrap_wait),
                        patch.object(driver_module.os, "waitid", side_effect=AssertionError(
                            "bootstrap 失败不应消费 pidfd 等待状态")),
                        patch.object(driver_module.os, "kill", side_effect=AssertionError(
                            "bootstrap 失败不应使用数字 PID 发信号")),
                        patch.object(driver_module.os, "killpg", side_effect=AssertionError(
                            "bootstrap 失败不应使用进程组发信号")),
                        patch.object(driver_module.signal, "pidfd_send_signal",
                                     side_effect=AssertionError("bootstrap 失败不应发送终止信号")),
                    ):
                        with self.assertRaises(driver_module.Failure) as failure:
                            self.driver.run(child_main)
                    self.assertIsInstance(failure.exception.__cause__, OSError)
                    self.assertEqual(failure.exception.__cause__.errno, code)
                    self.assertEqual(resource.getrlimit(resource.RLIMIT_NOFILE), initial_limits)
                    evidence = self.driver.evidence
                    self.assert_clean(evidence)
                    bootstrap = evidence["bootstrap"]
                    self.assertFalse(bootstrap["allowed"])
                    self.assertEqual((bootstrap["pid"], bootstrap["waited_pid"]),
                                     (self.driver.master, self.driver.master))
                    self.assertEqual(bootstrap["exit_code"], 113)
                    self.assertTrue(os.WIFEXITED(bootstrap["status"]))
                    self.assertEqual(os.WEXITSTATUS(bootstrap["status"]), 113)
                    self.assertEqual(injected, [self.driver.master])
                    self.assertTrue(bootstrap_waits)
                    self.assertEqual(set(bootstrap_waits), {self.driver.master})
                    self.assertFalse(marker.exists())
                    self.assertFalse(evidence["task_pins"])
                    self.assertNotIn("initial_stop", evidence)
                    self.assertNotIn("exitkill_set_monotonic_ns", evidence)
                    self.assertEqual(evidence["normal_resume_count"], 0)
                    self.assertEqual(evidence["wait_pidfd_count"], 0)
                    self.assertFalse(evidence["events"])
                    self.assertFalse(evidence["cleanup"])
                    self.assertNotIn("cleanup_error", evidence)
                    self.assertTrue(evidence["ledger_poisoned"])
                    self.assertFalse(Path(f"/proc/{self.driver.master}").exists())
                    with self.assertRaises(ChildProcessError):
                        original_waitpid(self.driver.master, os.WNOHANG)
                    stopped = os.waitid(os.P_PIDFD, descriptor, os.WSTOPPED | os.WNOHANG)
                    self.assertIsNotNone(stopped)
                    self.assertEqual((stopped.si_pid, stopped.si_code, stopped.si_status),
                                     (unrelated, os.CLD_STOPPED, signal.SIGSTOP))
                    signal.pidfd_send_signal(descriptor, signal.SIGCONT)
                    deadline = time.monotonic() + 2
                    while time.monotonic() < deadline:
                        terminal = os.waitid(os.P_PIDFD, descriptor, os.WEXITED | os.WNOHANG)
                        if terminal:
                            break
                        time.sleep(0.001)
                    self.assertIsNotNone(terminal)
                    self.assertEqual((terminal.si_pid, terminal.si_code, terminal.si_status),
                                     (unrelated, os.CLD_EXITED, 29))
                    reaped = True
                    print(json.dumps({
                        "kind": "master-pidfd-bootstrap-denied", "errno": code,
                        "master": self.driver.master, "bootstrap_exit": bootstrap["exit_code"],
                        "caller_pid": unrelated, "caller_exit": terminal.si_status,
                        "before_pidfd": before_pidfd,
                        "normal_resume_count": evidence["normal_resume_count"],
                        "wait_pidfd_count": evidence["wait_pidfd_count"],
                    }, sort_keys=True, separators=(",", ":")), flush=True)
                finally:
                    if not reaped:
                        try:
                            signal.pidfd_send_signal(descriptor, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        deadline = time.monotonic() + 2
                        while time.monotonic() < deadline:
                            try:
                                terminal = os.waitid(os.P_PIDFD, descriptor,
                                                     os.WEXITED | os.WNOHANG)
                            except ChildProcessError:
                                break
                            if terminal:
                                break
                            time.sleep(0.001)
                    os.close(descriptor)

    def test_bootstrap_wait_timeout_reports_unreaped_child(self):
        marker = Path(self.temp.name) / "bootstrap-timeout-callback"
        self.driver = driver_module.ControlledDriver(time.monotonic() + 5,
                                                     self.receiver, self.expected)
        original_pidfd_open, original_waitpid = os.pidfd_open, os.waitpid
        waits, injected = [], []
        started = time.monotonic()

        def unavailable_master_pidfd(pid, *args, **kwargs):
            if pid == self.driver.master and not injected:
                injected.append(pid)
                raise OSError(errno.EMFILE, os.strerror(errno.EMFILE))
            return original_pidfd_open(pid, *args, **kwargs)

        def no_bootstrap_result(pid, flags):
            self.assertEqual((pid, flags), (self.driver.master, os.WNOHANG))
            waits.append(pid)
            return 0, 0

        try:
            with (
                patch.object(driver_module.os, "pidfd_open", unavailable_master_pidfd),
                patch.object(driver_module.os, "waitpid", no_bootstrap_result),
                patch.object(driver_module.os, "waitid", side_effect=AssertionError(
                    "bootstrap 超时不应消费 pidfd 等待状态")),
                patch.object(driver_module.os, "kill", side_effect=AssertionError(
                    "bootstrap 超时不应使用数字 PID 发信号")),
                patch.object(driver_module.os, "killpg", side_effect=AssertionError(
                    "bootstrap 超时不应使用进程组发信号")),
                patch.object(driver_module.signal, "pidfd_send_signal",
                             side_effect=AssertionError("bootstrap 超时不应发送终止信号")),
            ):
                with self.assertRaises(driver_module.Failure) as failure:
                    self.driver.run(marker.touch)
            self.assertEqual(failure.exception.__cause__.errno, errno.EMFILE)
            evidence = self.driver.evidence
            self.assertTrue(waits)
            self.assertGreaterEqual(time.monotonic() - started, 2)
            self.assertFalse(evidence["bootstrap"]["allowed"])
            self.assertEqual(evidence["bootstrap"]["unreaped"], [self.driver.master])
            self.assertEqual(evidence["remaining_bootstrap_tasks"], [self.driver.master])
            self.assertIn("未回收 child", evidence["cleanup_error"])
            self.assertEqual(evidence["normal_resume_count"], 0)
            self.assertEqual(evidence["wait_pidfd_count"], 0)
            self.assertFalse(marker.exists())
            self.assertFalse(evidence["remaining_owned_tasks"])
            self.assertFalse(evidence["remaining_retired_tasks"])
            self.assertFalse(evidence["remaining_stopped_tasks"])
            self.assertEqual(evidence["fd_count_before"], evidence["fd_count_after"])
            self.assertTrue(evidence["subreaper_restored"])
            current = driver_module.ctypes.c_int()
            self.assertEqual(driver_module.libc.prctl(driver_module.PR_GET_CHILD_SUBREAPER,
                                                     driver_module.ctypes.byref(current), 0, 0, 0), 0)
            self.assertEqual(current.value, self.subreaper_before.value)
            print(json.dumps({
                "kind": "bootstrap-reap-timeout", "errno": failure.exception.__cause__.errno,
                "master": self.driver.master, "unreaped": evidence["remaining_bootstrap_tasks"],
                "cleanup_error": evidence["cleanup_error"], "callback_executed": marker.exists(),
            }, sort_keys=True, separators=(",", ":")), flush=True)
        finally:
            # 补丁只隐藏等待结果；真实 child 已因拒绝自退，由 caller 精确回收。
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                waited, status = original_waitpid(self.driver.master, os.WNOHANG)
                if waited:
                    break
                time.sleep(0.001)
            self.assertEqual(waited, self.driver.master)
            self.assertTrue(os.WIFEXITED(status))
            self.assertEqual(os.WEXITSTATUS(status), 113)
            self.assertFalse(Path(f"/proc/{self.driver.master}").exists())

    def test_unrelated_caller_child_in_same_group_keeps_wait_status(self):
        for index, (failed, stopped) in enumerate((
                (False, True), (False, False), (True, True), (True, False))):
            with self.subTest(failed=failed, stopped=stopped):
                if index:
                    self.client.close()
                    self.client = socket.socket()
                    self.client.connect(self.listener.getsockname())
                    self.expected["remote"] = list(self.client.getsockname())
                read_fd, write_fd = os.pipe()
                unrelated = os.fork()
                if unrelated == 0:
                    try:
                        os.close(write_fd)
                        self.receiver.close()
                        self.listener.close()
                        self.client.close()
                        group = int(os.read(read_fd, 64))
                        os.close(read_fd)
                        os.setpgid(0, group)
                        os.kill(os.getpid(), signal.SIGSTOP)
                        os._exit(29)
                    except BaseException:
                        os._exit(115)
                os.close(read_fd)
                descriptor = os.pidfd_open(unrelated)
                self.driver = driver_module.ControlledDriver(time.monotonic() + 5,
                                                             self.receiver, self.expected)
                original_wait = self.driver._wait
                original_continue = self.driver._normal_continue
                observed, injection = {}, {}
                reaped = False
                try:
                    def same_group_caller(initial=False):
                        result = original_wait(initial)
                        if initial:
                            os.write(write_fd, str(self.driver.master).encode())
                            while time.monotonic() < self.driver.ledger.deadline:
                                state = os.waitid(
                                    os.P_PIDFD, descriptor,
                                    os.WSTOPPED | os.WEXITED | os.WNOHANG | os.WNOWAIT)
                                if state:
                                    self.assertEqual(state.si_pid, unrelated)
                                    if state.si_code == os.CLD_STOPPED:
                                        self.assertEqual(os.getpgid(unrelated), self.driver.master)
                                        observed["pgrp"] = self.driver.master
                                    if not stopped and state.si_code == os.CLD_STOPPED:
                                        self.assertEqual(state.si_status, signal.SIGSTOP)
                                        os.waitid(os.P_PIDFD, descriptor, os.WSTOPPED | os.WNOHANG)
                                        signal.pidfd_send_signal(descriptor, signal.SIGCONT)
                                        continue
                                    self.assertEqual(state.si_code,
                                                     os.CLD_STOPPED if stopped else os.CLD_EXITED)
                                    self.assertEqual(state.si_status, signal.SIGSTOP if stopped else 29)
                                    self.assertEqual(observed["pgrp"], self.driver.master)
                                    observed.update({"si_code": state.si_code,
                                                     "si_status": state.si_status})
                                    break
                                time.sleep(0.001)
                            else:
                                raise TimeoutError("同组 caller child 未达到真实停点或退出状态")
                        return result

                    def fail_after_child_pin(pid, delivered_signal=0, record=True):
                        creation = self.driver.creations.get(pid)
                        if failed and creation and "event_child" in creation and not injection:
                            self.assertIn(creation["event_child"], self.driver.owned)
                            injection["at"] = time.monotonic_ns()
                            raise driver_module.Failure("测试注入已固定 child 后的失败")
                        return original_continue(pid, delivered_signal, record)

                    self.driver._wait = same_group_caller
                    self.driver._normal_continue = fail_after_child_pin
                    if failed:
                        with self.assertRaisesRegex(driver_module.Failure, "测试注入已固定 child"):
                            self.driver.run(self.cross_exec)
                        self.assertTrue(injection)
                    else:
                        self.driver.run(self.cross_exec)
                    evidence = self.driver.evidence
                    self.assert_clean(evidence)
                    self.assertTrue(observed)
                    self.assertFalse(any(row["pid"] == unrelated for row in evidence["events"]))
                    self.assertFalse(any(row.get("pid") == unrelated for row in evidence["cleanup"]))
                    # caller 的真实等待结果必须在 driver 正常或异常结束后仍未被消费。
                    state = os.waitid(os.P_PIDFD, descriptor, os.WSTOPPED | os.WEXITED | os.WNOHANG)
                    self.assertIsNotNone(state)
                    self.assertEqual(state.si_pid, unrelated)
                    self.assertEqual((state.si_code, state.si_status),
                                     (observed["si_code"], observed["si_status"]))
                    if stopped:
                        signal.pidfd_send_signal(descriptor, signal.SIGCONT)
                        while time.monotonic() < self.driver.ledger.deadline:
                            state = os.waitid(os.P_PIDFD, descriptor, os.WEXITED | os.WNOHANG)
                            if state:
                                break
                            time.sleep(0.001)
                        self.assertIsNotNone(state)
                        self.assertEqual((state.si_pid, state.si_code, state.si_status),
                                         (unrelated, os.CLD_EXITED, 29))
                    reaped = True
                    self.assertFalse(Path(f"/proc/{unrelated}").exists())
                    with self.assertRaises(ChildProcessError):
                        os.waitid(os.P_PIDFD, descriptor, os.WEXITED | os.WNOHANG)
                    print(json.dumps({
                        "kind": "unrelated-caller-wait-preserved", "failed": failed,
                        "stopped": stopped, "pid": unrelated, "master": self.driver.master,
                        **observed, "exit_code": state.si_status,
                    }, sort_keys=True, separators=(",", ":")), flush=True)
                finally:
                    if not reaped:
                        try:
                            signal.pidfd_send_signal(descriptor, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        end = time.monotonic() + 2
                        while time.monotonic() < end:
                            try:
                                state = os.waitid(os.P_PIDFD, descriptor, os.WEXITED | os.WNOHANG)
                            except ChildProcessError:
                                break
                            if state:
                                break
                            time.sleep(0.001)
                    os.close(descriptor)
                    os.close(write_fd)

    def test_parent_exits_without_reaping_child_restores_state(self):
        def unreaped_child_fixture():
            self.client.close()
            accepted, _ = self.listener.accept()
            self.listener.close()
            child = os.fork()
            if child == 0:
                os._exit(23)
            # 只观察终止，不回收 child；父退出后必须由 driver subreaper 真正回收。
            os.waitid(os.P_PID, child, os.WEXITED | os.WNOWAIT)
            os._exit(0)

        self.driver = driver_module.ControlledDriver(time.monotonic() + 5,
                                                     self.receiver, self.expected)
        try:
            evidence = self.driver.run(unreaped_child_fixture)
            self.assert_clean(evidence)
            child = evidence["creations"][0]["event_child"]
            reaped = [(row["pid"], row["exit_code"]) for row in evidence["events"]
                      if row.get("kind") == "reaped"]
            self.assertEqual(reaped, [(child, 23), (self.driver.master, 0)])
            pidfd_reaped = [row for row in evidence["cleanup"] if row["kind"] == "pidfd-reaped-task"]
            self.assertEqual([(row["pid"], row["exit_code"]) for row in pidfd_reaped], [(child, 23)])
            for pid in (child, self.driver.master):
                self.assertFalse(Path(f"/proc/{pid}").exists(), f"task {pid} 仍未真正回收")
                with self.assertRaises(ChildProcessError):
                    os.waitpid(pid, os.WNOHANG)
            self.assertFalse(Path(f"/proc/self/task/{os.getpid()}/children").read_text().strip())
            with self.assertRaises(ChildProcessError):
                os.waitpid(-1, os.WNOHANG)
        finally:
            # 红合同也要回收已退出 child，避免僵尸污染后续测试。
            for row in self.driver.evidence["creations"]:
                try:
                    os.waitpid(row["event_child"], os.WNOHANG)
                except ChildProcessError:
                    pass

    def test_runtime_identity_retirement_preserves_history_and_rejects_stale_pidfd(self):
        backlog = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        backlog.setsockopt(socket.SOL_SOCKET, socket.SO_PASSCRED, 1)
        backlog.setsockopt(socket.SOL_SOCKET, driver_module.ledger_module.SO_PASSPIDFD, 1)
        backlog.setblocking(False)
        backlog_path = str(Path(self.temp.name) / "backlog.sock")
        backlog.bind(backlog_path)
        self.driver = driver_module.ControlledDriver(time.monotonic() + 8,
                                                     self.receiver, self.expected)
        baseline = len(os.listdir("/proc/self/fd"))
        original_event, original_retire = self.driver._event, self.driver._retire_reaped
        captured, terminal_seen, released, fd_counts = {}, set(), [], []
        stale = None

        class DelayedMessage:
            def __init__(self, message):
                self.message = message

            def recvmsg(self, *_args):
                if self.message is None:
                    raise BlockingIOError(errno.EAGAIN, "已交付真实消息")
                message, self.message = self.message, None
                return message

        def observe(pid, status):
            nonlocal stale
            if (os.WIFSTOPPED(status) and status >> 16 == 0
                    and os.WSTOPSIG(status) == signal.SIGSTOP and pid in self.driver.registered):
                if pid != self.driver.master:
                    captured[pid] = backlog.recvmsg(4096, 1024, socket.MSG_CMSG_CLOEXEC)
                elif len(released) == 8:
                    self.assertEqual(len([row for row in self.driver.ledger.messages
                                         if row["accepted"]]), 8)
                    old_pid = released[0]
                    old = next(row for row in self.driver.evidence["events"]
                               if row.get("kind") == "identity-retired" and row["pid"] == old_pid)
                    current = self.driver._sample(pid)
                    for gate in ("still-live", "missing-Pid"):
                        ledger = driver_module.ledger_module.Ledger(time.monotonic() + 1)
                        ledger.register(current["process"], current)
                        identity = ledger.registry[pid]
                        identity["terminal"] = True
                        descriptor = identity["held_pidfd"]
                        try:
                            if gate == "missing-Pid":
                                with patch.object(driver_module.ledger_module.Path, "read_text",
                                                  return_value="pos:\t0\n"):
                                    with self.assertRaisesRegex(driver_module.Failure, "尚未真正回收"):
                                        ledger.retire_terminal(pid, identity["generation"], descriptor)
                            else:
                                with self.assertRaisesRegex(driver_module.Failure, "尚未真正回收"):
                                    ledger.retire_terminal(pid, identity["generation"], descriptor)
                            self.assertIn(pid, ledger.registry)
                            self.assertTrue(ledger.closed and ledger.poisoned)
                            with self.assertRaises(OSError) as error:
                                os.fstat(descriptor)
                            self.assertEqual(error.exception.errno, errno.EBADF)
                        finally:
                            ledger.close()
                    new = copy.deepcopy(current)
                    new["process"]["pid"] = old_pid
                    new["process"]["starttime_ticks"] = old["generation"]["starttime_ticks"] + 1
                    process = self.driver.ledger._process
                    verify_pidfd = self.driver.ledger._pidfd
                    open_pidfd = os.pidfd_open

                    def alias_process(number):
                        return copy.deepcopy(new["process"]) if number == old_pid else process(number)

                    def alias_pidfd(descriptor, number):
                        result = verify_pidfd(descriptor, pid if number == old_pid else number)
                        result["pid"] = number
                        return result

                    # 仅数值 PID 复用映射为模拟；新旧 pidfd 都由真实内核创建并保持原身份。
                    with (
                        patch.object(self.driver.ledger, "_process", alias_process),
                        patch.object(self.driver.ledger, "_pidfd", alias_pidfd),
                        patch.object(driver_module.os, "pidfd_open",
                                     lambda number: open_pidfd(pid if number == old_pid else number)),
                    ):
                        self.driver.ledger.register(new["process"], new)
                        self.assertNotEqual(self.driver.ledger.registry[old_pid]["generation"],
                                            old["generation"])
                        message, stale = stale, None
                        self.driver.ledger.drain(DelayedMessage(message))
                    self.fail("旧 pidfd 不得绑定重新登记的新代次")
            original_event(pid, status)
            if ((os.WIFEXITED(status) or os.WIFSIGNALED(status))
                    and pid != self.driver.master):
                identity = self.driver.ledger.registry[pid]
                descriptors = (self.driver.retired[pid], identity["held_pidfd"])
                self.assertTrue(identity["terminal"])
                self.assertFalse(identity["pending"])
                # 原父 WNOWAIT 保留真实 zombie，不能拿 ptrace 终局提前关掉两个原 FD。
                self.assertEqual([self.driver._pidfd_pid(fd) for fd in descriptors], [pid, pid])
                original_retire(force=True)
                self.assertIn(pid, self.driver.retired)
                self.assertIn(pid, self.driver.ledger.registry)
                terminal_seen.add(pid)
                (Path(self.temp.name) / f"reap-{pid}").touch()

        def retire(force=False):
            nonlocal stale
            candidates = {pid: (fd, self.driver.ledger.registry[pid]["held_pidfd"])
                          for pid, fd in self.driver.retired.items()}
            checked = False
            for pid, descriptors in candidates.items():
                if pid in terminal_seen and self.driver._pidfd_pid(descriptors[0]) == -1:
                    checked = True
                    identity = self.driver.ledger.registry[pid]
                    for field, value in (("terminal", False), ("pending", [object()])):
                        saved = identity[field]
                        identity[field] = value
                        try:
                            original_retire(force=True)
                            self.assertIn(pid, self.driver.retired)
                        finally:
                            identity[field] = saved
                    links = (
                        (self.driver.creations, pid, {}),
                        (self.driver.creations, self.driver.master, {"event_child": pid}),
                        (self.driver.group_changes, pid, {}),
                        (self.driver.pending_children, pid, (self.driver.master, {})),
                        (self.driver.pending_children, -1, (pid, {})),
                        (self.driver.early_stops, pid, ({}, {"process": {"ppid": -1}})),
                        (self.driver.early_stops, -1, ({}, {"process": {"ppid": pid}})),
                        (self.driver.unfixed_children, pid, {"summary": {"parent_pid": -1}}),
                        (self.driver.unfixed_children, -1, {"summary": {"parent_pid": pid}}),
                    )
                    for mapping, key, value in links:
                        self.assertNotIn(key, mapping)
                        mapping[key] = value
                        try:
                            original_retire(force=True)
                            self.assertIn(pid, self.driver.retired)
                        finally:
                            del mapping[key]
            # 负例已推进限频时钟，矩阵结束后只强制执行一次真实退役。
            original_retire(force or checked)
            for pid, descriptors in candidates.items():
                if pid not in self.driver.retired:
                    self.assertIn(pid, terminal_seen)
                    self.assertNotIn(pid, self.driver.registered)
                    self.assertNotIn(pid, self.driver.ledger.registry)
                    for descriptor in descriptors:
                        with self.assertRaises(OSError) as error:
                            os.fstat(descriptor)
                        self.assertEqual(error.exception.errno, errno.EBADF)
                    message = captured.pop(pid)
                    if not released:
                        body, ancillary, flags, address = message
                        duplicate = [(level, kind,
                                      driver_module.ledger_module.struct.pack(
                                          "i", os.dup(driver_module.ledger_module.struct.unpack(
                                              "i", payload)[0]))
                                      if kind == driver_module.ledger_module.SCM_PIDFD else payload)
                                     for level, kind, payload in ancillary]
                        stale = (body, duplicate, flags, address)
                    row, = self.driver.ledger.drain(DelayedMessage(message))["messages"]
                    self.assertEqual(row["rejection"], "unknown_sender")
                    self.assertFalse(row["accepted"] or row["pending"])
                    self.assertEqual(self.driver.registered, {self.driver.master})
                    self.assertEqual(set(self.driver.ledger.registry), {self.driver.master})
                    fd_counts.append(len(os.listdir("/proc/self/fd")))
                    self.assertEqual(fd_counts[-1], baseline + 3)
                    released.append(pid)
                    (Path(self.temp.name) / f"retired-{pid}").touch()

        def repeated_children():
            self.client.close()
            accepted, _ = self.listener.accept()
            self.listener.close()
            for index in range(8):
                child = os.fork()
                if child == 0:
                    sender = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
                    sender.sendto(f"retire-{index}".encode(), self.path)
                    sender.sendto(b"late-original", backlog_path)
                    os.kill(os.getpid(), signal.SIGSTOP)
                    sender.close()
                    accepted.close()
                    os._exit(23)
                os.waitid(os.P_PID, child, os.WEXITED | os.WNOWAIT)
                while not (Path(self.temp.name) / f"reap-{child}").exists():
                    time.sleep(0.001)
                waited, status = os.waitpid(child, 0)
                if waited != child or os.waitstatus_to_exitcode(status) != 23:
                    os._exit(112)
                while not (Path(self.temp.name) / f"retired-{child}").exists():
                    time.sleep(0.001)
            os.kill(os.getpid(), signal.SIGSTOP)
            accepted.close()
            os._exit(0)

        self.driver._event, self.driver._retire_reaped = observe, retire
        try:
            with self.assertRaisesRegex(driver_module.Failure, "pidfd task 已改变"):
                self.driver.run(repeated_children)
            evidence = self.driver.evidence
            self.assert_clean(evidence)
            self.assertEqual(len(released), 8)
            self.assertFalse(captured)
            self.assertEqual(len(set(fd_counts)), 1)
            retired = [row for row in evidence["events"] if row.get("kind") == "identity-retired"]
            self.assertEqual({row["pid"] for row in retired}, set(released))
            self.assertTrue(all(row["driver_pidfd_pid"] == row["held_pidfd_pid"] == -1
                                for row in retired))
            for previous, following in zip(retired, evidence["creations"][1:]):
                self.assertLess(previous["retired_monotonic_ns"], following["entry_monotonic_ns"])
            self.assertTrue(evidence["ledger_poisoned"])
            self.assertFalse(any(row["accepted"] or row["pending"] for row in evidence["messages"]))
        finally:
            for message in [*captured.values(), *([stale] if stale is not None else [])]:
                for level, kind, payload in message[1]:
                    if level == socket.SOL_SOCKET and kind == driver_module.ledger_module.SCM_PIDFD:
                        descriptor, = driver_module.ledger_module.struct.unpack("i", payload)
                        if descriptor >= 0:
                            os.close(descriptor)
            backlog.close()

    def test_real_pthread_creation_is_rejected_before_execution(self):
        def clone_fixture():
            self.client.close()
            accepted, _ = self.listener.accept()
            self.listener.close()
            os.execv(self.helper, [self.helper, "clone"])

        self.driver = driver_module.ControlledDriver(time.monotonic() + 5, self.receiver, self.expected)
        with self.assertRaisesRegex(driver_module.Failure, "创建 syscall 435|不安全 clone"):
            self.driver.run(clone_fixture)
        evidence = self.driver.evidence
        self.assert_clean(evidence)
        rejected = next(row for row in evidence["events"] if "rejection" in row)
        self.assertEqual(rejected["kind"], "creation-entry")
        self.assertTrue(evidence["ledger_poisoned"])
        self.assertFalse(any(row["returned_monotonic_ns"] >= rejected["rejected_monotonic_ns"]
                             for row in evidence["continues"]))
        self.assertFalse(any(row.get("event") in (1, 2, 3) for row in evidence["events"]))
        self.assertTrue(all(row.get("signal") == signal.SIGKILL
                            for row in evidence["cleanup"] if row["kind"] == "cleanup-continue"))

    def test_raw_fork_syscall_57_links_creation_and_reaps_real_child(self):
        marker = Path(self.temp.name) / "raw-fork-executed"

        def fixture():
            self.client.close()
            accepted, _ = self.listener.accept()
            self.listener.close()
            accepted.set_inheritable(True)
            os.execv(self.helper, [self.helper, "raw-fork", str(marker)])

        self.driver = driver_module.ControlledDriver(time.monotonic() + 5,
                                                     self.receiver, self.expected)
        evidence = self.driver.run(fixture)
        self.assert_clean(evidence)
        creation, = evidence["creations"]
        first, = evidence["first_stops"]
        child = first["pid"]
        self.assertEqual(creation["entry"]["nr"], driver_module.SYS_FORK)
        self.assertEqual(creation["entry"]["op"], 1)
        self.assertEqual(creation["entry"]["arch"], driver_module.AUDIT_ARCH_X86_64)
        self.assertEqual(creation["entry"]["args"], [0] * 6)
        self.assertEqual((creation["parent_pid"], creation["epoch"], creation["exe"]),
                         (self.driver.master, 1, self.helper))
        self.assertEqual((creation["event_child"], creation["exit_rval"]), (child, child))
        self.assertEqual((first["parent_pid"], first["snapshot"]["process"]["ppid"]),
                         (self.driver.master, self.driver.master))
        self.assertEqual(first["snapshot"]["process"]["exe"], self.helper)
        self.assertEqual(len(first["snapshot"]["accepted_matches"]), 1)
        self.assertEqual(first["snapshot"]["accepted_matches"],
                         creation["entry_anchor"]["accepted_matches"])
        self.assertEqual(first["snapshot"]["accepted_matches"],
                         first["parent_fork_anchor"]["accepted_matches"])
        fork_event, = [row for row in evidence["events"] if row.get("kind") == "fork-parent-stop"]
        self.assertEqual((fork_event["event"], fork_event["child_pid"]), (driver_module.FORK, child))
        ordering = [creation[key] for key in
                    ("entry_monotonic_ns", "event_monotonic_ns", "exit_monotonic_ns")]
        ordering.extend(first[key] for key in ("registered_monotonic_ns", "first_continue_monotonic_ns"))
        self.assertEqual(ordering, sorted(ordering))
        self.assertTrue(marker.exists())
        self.assertEqual(sorted((row["pid"], row["exit_code"]) for row in evidence["events"]
                                if row.get("kind") == "reaped"),
                         sorted(((self.driver.master, 0), (child, 23))))
        self.assert_tasks_reaped(child, self.driver.master)
        print(json.dumps({
            "kind": "raw-fork-57-verified", "master": self.driver.master, "child": child,
            "entry": creation["entry"], "parent_epoch": creation["epoch"],
            "creation_order": ordering, "marker_exists": marker.exists(),
        }, sort_keys=True, separators=(",", ":")), flush=True)

    def test_real_vfork_syscall_58_is_rejected_before_child_creation(self):
        marker = Path(self.temp.name) / "vfork-executed"
        subprocess.run([self.helper, "vfork", str(marker)], check=True,
                       capture_output=True, timeout=3)
        self.assertTrue(marker.exists())
        marker.unlink()

        def fixture():
            self.client.close()
            accepted, _ = self.listener.accept()
            self.listener.close()
            accepted.set_inheritable(True)
            os.execv(self.helper, [self.helper, "vfork", str(marker)])

        self.driver = driver_module.ControlledDriver(time.monotonic() + 5,
                                                     self.receiver, self.expected)
        with self.assertRaisesRegex(driver_module.Failure, "创建 syscall 58"):
            self.driver.run(fixture)
        evidence = self.driver.evidence
        self.assert_clean(evidence)
        rejected = next(row for row in evidence["events"] if "rejection" in row)
        self.assertEqual(rejected["kind"], "creation-entry")
        self.assertEqual((rejected["pid"], rejected["syscall"]["op"], rejected["syscall"]["nr"]),
                         (self.driver.master, 1, driver_module.SYS_VFORK))
        self.assertEqual(rejected["syscall"]["arch"], driver_module.AUDIT_ARCH_X86_64)
        self.assertFalse(any(row.get("event") in (driver_module.FORK, driver_module.VFORK, driver_module.CLONE)
                             for row in evidence["events"]))
        self.assertEqual([row["pid"] for row in evidence["task_pins"]], [self.driver.master])
        self.assertFalse(evidence["first_stops"])
        self.assertFalse(evidence["creations"])
        self.assertFalse(marker.exists())
        self.assertTrue(evidence["ledger_poisoned"])
        self.assertLess(evidence["last_normal_resume_monotonic_ns"], rejected["rejected_monotonic_ns"])
        self.assertFalse(any(row["returned_monotonic_ns"] >= rejected["rejected_monotonic_ns"]
                             for row in evidence["continues"]))
        self.assert_tasks_reaped(self.driver.master)
        print(json.dumps({
            "kind": "real-vfork-58-entry-rejection", "master": self.driver.master,
            "entry": rejected["syscall"], "baseline_marker": True, "marker_exists": marker.exists(),
            "remaining_owned_tasks": evidence["remaining_owned_tasks"],
        }, sort_keys=True, separators=(",", ":")), flush=True)

    def test_shared_untraced_clone_and_clone3_are_rejected_at_entry(self):
        marker = str(Path(self.temp.name) / "child-executed")
        baseline = subprocess.run([self.helper, "baseline-shared-clone", marker],
                                  check=True, capture_output=True, text=True, timeout=3)
        raw = json.loads(baseline.stdout)
        self.assertEqual(raw["event"], driver_module.FORK)
        self.assertEqual(raw["status"] >> 16, driver_module.FORK)
        self.assertEqual(raw["flags"], 0x100 | signal.SIGCHLD)
        self.assertGreater(raw["child"], 0)
        self.assertFalse(Path(marker).exists())
        print(json.dumps({"kind": "raw-shared-clone-baseline", **raw},
                         sort_keys=True, separators=(",", ":")), flush=True)
        for index, (mode, nr, flags) in enumerate((
                ("shared-clone", driver_module.SYS_CLONE, 0x111),
                ("untraced-clone", driver_module.SYS_CLONE, 0x800011),
                ("clone3", driver_module.SYS_CLONE3, None))):
            with self.subTest(mode=mode):
                if index:
                    self.client.close()
                    self.client = socket.socket()
                    self.client.connect(self.listener.getsockname())
                    self.expected["remote"] = list(self.client.getsockname())
                def fixture():
                    self.client.close()
                    accepted, _ = self.listener.accept()
                    self.listener.close()
                    os.execv(self.helper, [self.helper, mode, marker])

                self.driver = driver_module.ControlledDriver(time.monotonic() + 5,
                                                             self.receiver, self.expected)
                with self.assertRaisesRegex(driver_module.Failure, "创建 syscall 435|不安全 clone"):
                    self.driver.run(fixture)
                evidence = self.driver.evidence
                self.assert_clean(evidence)
                rejected = next(row for row in evidence["events"] if "rejection" in row)
                self.assertEqual(rejected["kind"], "creation-entry")
                self.assertEqual(rejected["syscall"]["nr"], nr)
                if flags is not None:
                    self.assertEqual(rejected["syscall"]["args"][0], flags)
                self.assertFalse(any(row.get("event") in (1, 2, 3) for row in evidence["events"]))
                self.assertLess(evidence["last_normal_resume_monotonic_ns"],
                                rejected["rejected_monotonic_ns"])
                self.assertFalse(Path(marker).exists())
                self.assertTrue(evidence["ledger_poisoned"])

    def test_missing_or_mismatched_creation_proof_refuses_child_resume(self):
        for index, mode in enumerate(("missing-entry", "wrong-event-pid")):
            with self.subTest(mode=mode):
                if index:
                    self.client.close()
                    self.client = socket.socket()
                    self.client.connect(self.listener.getsockname())
                    self.expected["remote"] = list(self.client.getsockname())
                self.driver = driver_module.ControlledDriver(time.monotonic() + 5,
                                                             self.receiver, self.expected)
                original = self.driver._wait
                injection = {}

                def corrupt(initial=False):
                    pid, status = original(initial)
                    creation = self.driver.creations.get(pid)
                    if creation and not injection:
                        if mode == "missing-entry" and status >> 16 == driver_module.FORK:
                            del self.driver.creations[pid]
                            injection["at"] = time.monotonic_ns()
                        elif (mode == "wrong-event-pid" and "event_child" in creation
                              and os.WIFSTOPPED(status)
                              and os.WSTOPSIG(status) == (signal.SIGTRAP | 0x80)):
                            creation["event_child"] += 1
                            injection["at"] = time.monotonic_ns()
                    return pid, status

                self.driver._wait = corrupt
                with self.assertRaisesRegex(driver_module.Failure, "entry 证据|PID 与 FORK"):
                    self.driver.run(self.cross_exec)
                evidence = self.driver.evidence
                self.assert_clean(evidence)
                self.assertTrue(injection)
                self.assertFalse(evidence["first_stops"])
                self.assertLess(evidence["last_normal_resume_monotonic_ns"], injection["at"])

    def test_failed_child_pin_validation_keeps_identity_for_cleanup(self):
        self.driver = driver_module.ControlledDriver(time.monotonic() + 5,
                                                     self.receiver, self.expected)
        original_snapshot = driver_module.process_snapshot
        samples, injection = {}, {}

        def changed_child_parent(pid):
            current = original_snapshot(pid)
            if pid != self.driver.master and current["ppid"] == self.driver.master:
                samples[pid] = samples.get(pid, 0) + 1
                if samples[pid] == 2 and not injection:
                    # pidfd 已固定后令首末父链校验失败，清理仍须保留该原身份。
                    self.assertIn(pid, self.driver.owned)
                    injection.update({"child": pid, "at": time.monotonic_ns()})
                    current["ppid"] += 1
            return current

        with patch.object(driver_module, "process_snapshot", changed_child_parent):
            with self.assertRaisesRegex(driver_module.Failure, "原 task、父链或 namespace 无效"):
                self.driver.run(self.cross_exec)
        self.assertTrue(injection)
        evidence = self.driver.evidence
        self.assert_clean(evidence)
        self.assertTrue(evidence["ledger_poisoned"])
        self.assertNotIn("cleanup_error", evidence)
        self.assertFalse(evidence["first_stops"])
        self.assertLess(evidence["last_normal_resume_monotonic_ns"], injection["at"])
        for pid in (injection["child"], self.driver.master):
            self.assertFalse(Path(f"/proc/{pid}").exists(), f"task {pid} 仍未真正回收")
            with self.assertRaises(ChildProcessError):
                os.waitpid(pid, os.WNOHANG)
        with self.assertRaises(ChildProcessError):
            os.waitpid(-1, os.WNOHANG)

    def test_child_pidfd_failure_cleanup_preserves_caller_stop(self):
        original_open, original_waitpid, original_waitid = os.pidfd_open, os.waitpid, os.waitid
        original_kill, original_signal = os.kill, signal.pidfd_send_signal
        limits = resource.getrlimit(resource.RLIMIT_NOFILE)
        tracer = os.getpid()
        unrelated = os.fork()
        if unrelated == 0:
            self.receiver.close()
            self.listener.close()
            self.client.close()
            original_kill(os.getpid(), signal.SIGSTOP)
            os._exit(29)
        caller_pidfd = original_open(unrelated)
        caller_reaped = False
        try:
            stopped = original_waitid(os.P_PIDFD, caller_pidfd, os.WSTOPPED | os.WNOWAIT)
            self.assertEqual((stopped.si_pid, stopped.si_code, stopped.si_status),
                             (unrelated, os.CLD_STOPPED, signal.SIGSTOP))
            cases = [(persistent, code) for persistent in (False, True)
                     for code in (errno.EMFILE, errno.EPERM, errno.ENOMEM)]
            for index, (persistent, code) in enumerate(cases):
                with self.subTest(errno=code, persistent=persistent):
                    if index:
                        self.client.close()
                        self.client = socket.socket()
                        self.client.connect(self.listener.getsockname())
                        self.expected["remote"] = list(self.client.getsockname())
                    self.driver = driver_module.ControlledDriver(time.monotonic() + 10,
                                                                 self.receiver, self.expected)
                    injected, reopened, signals, child_ptrace = {}, [], [], []
                    original_ptrace = driver_module.ptrace

                    def fail_grandchild_first_pin(pid, *args, **kwargs):
                        if not injected and pid != self.driver.master:
                            current = driver_module.process_snapshot(pid)
                            parent = current["ppid"]
                            if parent != self.driver.master and parent in self.driver.owned:
                                self.driver._require_stop(parent)
                                parent_stop = self.driver.stopped_tasks[parent]
                                self.assertEqual(parent_stop["status"] >> 16, driver_module.FORK)
                                self.assertEqual(driver_module.event_message(parent), pid)
                                self.assertNotIn(pid, self.driver.owned)
                                self.assertNotIn(pid, self.driver.registered)
                                self.assertEqual(current["tracer_pid"], tracer)
                                self.assertNotIn("exit_rval", self.driver.creations[parent])
                                injected.update({
                                    "child": pid, "parent": parent, "parent_pidfd": self.driver.owned[parent],
                                    "parent_status": parent_stop["status"], "stop_object": id(parent_stop),
                                    "creation": copy.deepcopy(self.driver.creations[parent]),
                                    "generation": self.driver.ledger._generation(current),
                                    "at": time.monotonic_ns(),
                                })
                        if injected and pid == injected["child"]:
                            retry = self.driver.ledger.closed
                            if retry:
                                self.assertFalse(reopened)
                                reopened.append(pid)
                                parent_stop = self.driver.stopped_tasks[injected["parent"]]
                                self.assertEqual((id(parent_stop), parent_stop["status"]),
                                                 (injected["stop_object"], injected["parent_status"]))
                                self.assertEqual(self.driver.owned[injected["parent"]], injected["parent_pidfd"])
                                self.assertEqual(driver_module.event_message(injected["parent"]), pid)
                                self.assertEqual(self.driver.creations[injected["parent"]], injected["creation"])
                                self.assertEqual(self.driver.ledger._generation(driver_module.process_snapshot(pid)),
                                                 injected["generation"])
                            if not retry or persistent:
                                if code == errno.EMFILE:
                                    return self.real_emfile_pidfd(original_open, pid, *args, **kwargs)
                                raise OSError(code, os.strerror(code))
                        return original_open(pid, *args, **kwargs)

                    def cleanup_child_ptrace(request, pid, data=0, address=0):
                        if pid == injected.get("child"):
                            self.assertNotIn(pid, self.driver.registered)
                            if persistent:
                                self.assertNotIn(pid, self.driver.owned)
                                self.assertNotEqual(request, driver_module.SYSCALL)
                                child_ptrace.append((request, data))
                        return original_ptrace(request, pid, data, address)

                    def original_task_wait(kind, descriptor, flags):
                        if os.getpid() == tracer:
                            if persistent and kind == os.P_PID:
                                self.assertEqual(descriptor, injected["child"])
                                self.assertTrue(flags & 0x40000000)
                                self.assertFalse(flags & os.WCONTINUED)
                            else:
                                self.assertEqual(kind, os.P_PIDFD)
                                self.assertNotEqual(descriptor, caller_pidfd)
                        return original_waitid(kind, descriptor, flags)

                    def fixture_waitpid(pid, flags):
                        if os.getpid() == tracer:
                            raise AssertionError("创建 child 失败清理不能消费数字 PID 等待状态")
                        return original_waitpid(pid, flags)

                    def fixture_stop(pid, delivered):
                        if os.getpid() != tracer and pid == os.getpid() and delivered == signal.SIGSTOP:
                            return original_kill(pid, delivered)
                        raise AssertionError("创建 child 失败清理禁止数字 PID 发信号")

                    def original_task_signal(descriptor, delivered, siginfo=None, flags=0):
                        self.assertNotEqual(descriptor, caller_pidfd)
                        pid = next(task for task, held in self.driver.owned.items() if held == descriptor)
                        self.assertEqual(self.driver._pidfd_pid(descriptor), pid)
                        signals.append((pid, delivered, time.monotonic_ns()))
                        return original_signal(descriptor, delivered, siginfo, flags)

                    with (
                        patch.object(driver_module.os, "pidfd_open", fail_grandchild_first_pin),
                        patch.object(driver_module.os, "waitid", original_task_wait),
                        patch.object(driver_module.os, "waitpid", fixture_waitpid),
                        patch.object(driver_module.os, "kill", fixture_stop),
                        patch.object(driver_module.os, "killpg",
                                     side_effect=AssertionError("创建 child 失败清理禁止进程组发信号")),
                        patch.object(driver_module.signal, "pidfd_send_signal", original_task_signal),
                        patch.object(driver_module, "ptrace", cleanup_child_ptrace),
                    ):
                        with self.assertRaises(driver_module.Failure) as failure:
                            self.driver.run(lambda: self.cross_exec("setsid", ignore_sigchld=persistent))
                    self.assertIsInstance(failure.exception.__cause__, OSError)
                    self.assertEqual(failure.exception.__cause__.errno, code)
                    self.assertEqual(resource.getrlimit(resource.RLIMIT_NOFILE), limits)
                    evidence = self.driver.evidence
                    self.assert_clean(evidence)
                    self.assertNotIn("cleanup_error", evidence)
                    self.assertTrue(injected)
                    child, parent = injected["child"], injected["parent"]
                    self.assertEqual(reopened, [child])
                    pin_failure, = evidence["child_pin_failures"]
                    expected = {"child_pid": child, "parent_pid": parent,
                                "parent_pidfd": injected["parent_pidfd"],
                                "parent_status": injected["parent_status"], "first_errno": code, "attempts": 2}
                    self.assertEqual({key: pin_failure[key] for key in expected}, expected)
                    self.assertTrue(pin_failure["first_error"])
                    self.assertEqual(pin_failure["last_errno"], code)
                    self.assertLess(injected["at"], pin_failure["resolved_monotonic_ns"])
                    self.assertLess(evidence["last_normal_resume_monotonic_ns"], injected["at"])
                    self.assertFalse(any(row["returned_monotonic_ns"] >= injected["at"]
                                         for row in evidence["continues"]))
                    self.assertEqual(len(evidence["first_stops"]), 1)
                    self.assertEqual(evidence["discarded_creation_proofs"], [parent])
                    self.assertFalse(evidence["messages"])
                    kills = [(pid, at) for pid, delivered, at in signals if delivered == signal.SIGKILL]
                    if persistent:
                        self.assertTrue(pin_failure["cleanup_only"])
                        self.assertFalse(any(row["pid"] == child for row in evidence["task_pins"]))
                        self.assertNotIn(child, self.driver.registered)
                        self.assertEqual({pid for pid, _ in kills}, {self.driver.master, parent})
                        self.assertTrue(any(request == driver_module.GETSIGINFO
                                            for request, _ in child_ptrace))
                        self.assertIn((driver_module.CONT, signal.SIGKILL), child_ptrace)
                        self.assertIn((driver_module.CONT, 0), child_ptrace)
                        self.assertEqual(pin_failure["signal_info"]["signo"], signal.SIGSTOP)
                        self.assertEqual(pin_failure["signal_info"]["errno"], 0)
                        child_cleanup = [row for row in evidence["cleanup"] if row.get("pid") == child]
                        self.assertEqual([row["kind"] for row in child_cleanup], [
                            "unfixed-child-first-stop", "unfixed-child-exit-stop",
                            "unfixed-child-terminal-retained", "unfixed-child-reaped"])
                        self.assertEqual(child_cleanup[-1]["adopted_identity"]["ppid"], tracer)
                        self.assertEqual(child_cleanup[-1]["adopted_identity"]["state"], "Z")
                        self.assertEqual(child_cleanup[-1]["adopted_identity"]["starttime_ticks"],
                                         injected["generation"]["starttime_ticks"])
                        self.assertLess(pin_failure["terminal_monotonic_ns"], min(at for _, at in kills))
                        order = [pin_failure[key] for key in (
                            "first_stop_monotonic_ns", "terminal_monotonic_ns",
                            "parent_terminal_monotonic_ns", "parent_reaped_monotonic_ns",
                            "reaped_monotonic_ns", "resolved_monotonic_ns")]
                        self.assertEqual(order, sorted(order))
                    else:
                        pinned = next(row for row in evidence["task_pins"] if row["pid"] == child)
                        self.assertEqual((pinned["source"], pinned["parent_pid"]), ("cleanup", parent))
                        self.assertEqual({pid for pid, _ in kills}, {self.driver.master, parent, child})
                        self.assertLess(pinned["pinned_monotonic_ns"], min(at for _, at in kills))
                    self.assert_tasks_reaped(child, parent, self.driver.master)
                    state = original_waitid(os.P_PIDFD, caller_pidfd,
                                            os.WSTOPPED | os.WNOHANG | os.WNOWAIT)
                    self.assertEqual((state.si_pid, state.si_code, state.si_status),
                                     (unrelated, os.CLD_STOPPED, signal.SIGSTOP))
                    print(json.dumps({
                        "kind": "child-first-pidfd-failure-cleanup-retry", "errno": code,
                        "persistent": persistent,
                        "child": child, "parent": parent, "master": self.driver.master,
                        "real_syscall_failure": code == errno.EMFILE,
                        "pin_failure": pin_failure, "pidfd_signals": signals,
                        "caller_stop_preserved": True,
                        "remaining_unfixed_children": evidence["remaining_unfixed_children"],
                    }, sort_keys=True, separators=(",", ":")), flush=True)
            original_waitid(os.P_PIDFD, caller_pidfd, os.WSTOPPED)
            original_signal(caller_pidfd, signal.SIGCONT)
            state = original_waitid(os.P_PIDFD, caller_pidfd, os.WEXITED)
            self.assertEqual((state.si_pid, state.si_code, state.si_status),
                             (unrelated, os.CLD_EXITED, 29))
            caller_reaped = True
        finally:
            if not caller_reaped:
                try:
                    original_signal(caller_pidfd, signal.SIGKILL)
                    original_waitid(os.P_PIDFD, caller_pidfd, os.WEXITED)
                except (ProcessLookupError, ChildProcessError):
                    pass
            os.close(caller_pidfd)

    def test_retired_identity_collision_cleanup_preserves_caller_stop(self):
        original_open, original_waitpid, original_waitid = os.pidfd_open, os.waitpid, os.waitid
        original_kill, original_signal, original_ptrace = (
            os.kill, signal.pidfd_send_signal, driver_module.ptrace)
        tracer = os.getpid()
        unrelated = os.fork()
        if unrelated == 0:
            self.receiver.close()
            self.listener.close()
            self.client.close()
            original_kill(os.getpid(), signal.SIGSTOP)
            os._exit(29)
        caller_pidfd = original_open(unrelated)
        caller_reaped = False
        try:
            stopped = original_waitid(os.P_PIDFD, caller_pidfd, os.WSTOPPED | os.WNOWAIT)
            self.assertEqual((stopped.si_pid, stopped.si_code, stopped.si_status),
                             (unrelated, os.CLD_STOPPED, signal.SIGSTOP))
            for index, changed_fd in enumerate((False, True)):
                with self.subTest(changed_retired_fd=changed_fd):
                    if index:
                        self.client.close()
                        self.client = socket.socket()
                        self.client.connect(self.listener.getsockname())
                        self.expected["remote"] = list(self.client.getsockname())
                    self.driver = driver_module.ControlledDriver(time.monotonic() + 8,
                                                                 self.receiver, self.expected)
                    original_pin, original_event, original_cleanup = (
                        self.driver._pin, self.driver._event, self.driver._cleanup)
                    old, injected, rescue = {}, {}, {}
                    opened, child_ptrace, signals = [], [], []
                    marker = Path(self.temp.name) / f"collision-child-ran-{index}"

                    def sequential_children():
                        self.client.close()
                        accepted, _ = self.listener.accept()
                        self.listener.close()
                        child = os.fork()
                        if child == 0:
                            os._exit(23)
                        waited, status = original_waitpid(child, 0)
                        if waited != child or not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 23:
                            os._exit(112)
                        time.sleep(0.02)
                        child = os.fork()
                        if child == 0:
                            marker.touch()
                            os._exit(31)
                        accepted.close()
                        original_waitpid(child, 0)

                    def observe_old(pid, status):
                        original_event(pid, status)
                        if (pid != self.driver.master
                                and (os.WIFEXITED(status) or os.WIFSIGNALED(status))):
                            identity = self.driver.ledger.registry[pid]
                            old.update({"pid": pid, "pidfd": self.driver.retired[pid],
                                        "identity": identity,
                                        "generation": copy.deepcopy(identity["generation"])})
                            self.assertTrue(identity["terminal"])
                            self.assertFalse(identity["pending"])
                            self.assertIn(self.driver._pidfd_pid(old["pidfd"]), (pid, -1))

                    def alias_retired_index(pid, parent=None, source="run"):
                        if old and not injected and parent == self.driver.master:
                            self.driver._require_stop(parent)
                            parent_stop = self.driver.stopped_tasks[parent]
                            self.assertEqual(parent_stop["status"] >> 16, driver_module.FORK)
                            self.assertEqual(driver_module.event_message(parent), pid)
                            self.assertEqual(parent_stop["unfixed_child_pid"], pid)
                            self.assertIn(pid, self.driver.unfixed_children)
                            self.assertEqual(self.driver._pidfd_pid(old["pidfd"]), -1)
                            self.assertNotEqual(pid, old["pid"])
                            current = driver_module.process_snapshot(pid)
                            injected.update({
                                "child": pid, "parent": parent, "parent_pidfd": self.driver.owned[parent],
                                "generation": self.driver.ledger._generation(current),
                                "actual_original_identity": copy.deepcopy(old["generation"]),
                                "at": time.monotonic_ns(),
                            })
                            # 只模拟数字索引碰撞；两代 task、原 pidfd、停点和回收都来自真实内核。
                            self.driver.retired[pid] = self.driver.retired.pop(old["pid"])
                            if changed_fd:
                                self.driver.retired[pid] = original_open(parent)
                            identity = self.driver.ledger.registry.pop(old["pid"])
                            identity["generation"]["pid"] = pid
                            self.driver.ledger.registry[pid] = identity
                            self.driver.registered.remove(old["pid"])
                            self.driver.registered.add(pid)
                            self.assertIs(identity, old["identity"])
                            self.assertNotEqual(identity["generation"], injected["generation"])
                        return original_pin(pid, parent, source)

                    def record_open(pid, *args, **kwargs):
                        if os.getpid() == tracer:
                            opened.append(pid)
                        return original_open(pid, *args, **kwargs)

                    def child_cleanup_ptrace(request, pid, data=0, address=0):
                        if pid == injected.get("child"):
                            self.assertNotIn(pid, self.driver.owned)
                            self.assertIs(self.driver.ledger.registry[pid], old["identity"])
                            self.assertTrue(self.driver.ledger.registry[pid]["terminal"])
                            self.assertNotEqual(self.driver.ledger.registry[pid]["generation"],
                                                injected["generation"])
                            unresolved = self.driver.unfixed_children[pid]
                            self.assertEqual(unresolved["pidfd_open_errors"], 0)
                            self.assertEqual(unresolved["retired_collision_errors"], 2)
                            self.assertNotEqual(request, driver_module.SYSCALL)
                            child_ptrace.append((request, data))
                        return original_ptrace(request, pid, data, address)

                    def exact_wait(kind, descriptor, flags):
                        if os.getpid() == tracer:
                            if kind == os.P_PID:
                                self.assertEqual(descriptor, injected["child"])
                                self.assertTrue(flags & 0x40000000)
                                self.assertFalse(flags & os.WCONTINUED)
                            else:
                                self.assertEqual(kind, os.P_PIDFD)
                                self.assertNotEqual(descriptor, caller_pidfd)
                        return original_waitid(kind, descriptor, flags)

                    def exact_signal(descriptor, delivered, siginfo=None, flags=0):
                        self.assertNotEqual(descriptor, caller_pidfd)
                        pid = next(task for task, held in self.driver.owned.items() if held == descriptor)
                        self.assertEqual(self.driver._pidfd_pid(descriptor), pid)
                        signals.append((pid, delivered, time.monotonic_ns()))
                        return original_signal(descriptor, delivered, siginfo, flags)

                    def no_numeric_wait(pid, flags):
                        if os.getpid() == tracer:
                            raise AssertionError("旧身份碰撞清理不能消费其它数字 PID 等待状态")
                        return original_waitpid(pid, flags)

                    def fixture_stop(pid, delivered):
                        if os.getpid() != tracer and pid == os.getpid() and delivered == signal.SIGSTOP:
                            return original_kill(pid, delivered)
                        raise AssertionError("旧身份碰撞清理禁止数字 PID 发信号")

                    def changed_original_fd():
                        if changed_fd:
                            rescue.update({task: os.dup(descriptor)
                                           for task, descriptor in self.driver.owned.items()})
                            collision = self.driver.unfixed_children[
                                injected["child"]]["summary"]["retired_collision"]
                            self.assertEqual(self.driver.retired[injected["child"]], collision["pidfd"])
                            injected["collision_pidfd_pid"] = self.driver._pidfd_pid(collision["pidfd"])
                            self.assertEqual(injected["collision_pidfd_pid"], injected["parent"])
                        return original_cleanup()

                    try:
                        with (
                            patch.object(self.driver, "_retire_reaped", lambda force=False: None),
                            patch.object(self.driver, "_event", observe_old),
                            patch.object(self.driver, "_pin", alias_retired_index),
                            patch.object(self.driver, "_cleanup", changed_original_fd),
                            patch.object(driver_module.os, "pidfd_open", record_open),
                            patch.object(driver_module.os, "waitid", exact_wait),
                            patch.object(driver_module.os, "waitpid", no_numeric_wait),
                            patch.object(driver_module.os, "kill", fixture_stop),
                            patch.object(driver_module.os, "killpg",
                                         side_effect=AssertionError("旧身份碰撞清理禁止进程组发信号")),
                            patch.object(driver_module.signal, "pidfd_send_signal", exact_signal),
                            patch.object(driver_module, "ptrace", child_cleanup_ptrace),
                        ):
                            with self.assertRaises(driver_module.Failure) as failure:
                                self.driver.run(sequential_children)
                        self.assertIsInstance(failure.exception.__cause__,
                                              driver_module.RetiredIdentityCollision)
                        evidence = copy.deepcopy(self.driver.evidence)
                        child, parent = injected["child"], injected["parent"]
                        self.assertNotIn(child, opened)
                        self.assertFalse(marker.exists())
                        self.assertFalse(any(row["pid"] == child for row in evidence["task_pins"]))
                        self.assertFalse(any(row["pid"] == child for row in evidence["first_stops"]))
                        self.assertFalse(evidence["messages"])
                        self.assertLess(evidence["last_normal_resume_monotonic_ns"], injected["at"])
                        self.assertFalse(any(row["returned_monotonic_ns"] >= injected["at"]
                                             for row in evidence["continues"]))
                        pin_failure, = evidence["child_pin_failures"]
                        unresolved = self.driver.unfixed_children.get(child)
                        self.assertEqual((pin_failure["first_errno"], pin_failure["last_errno"],
                                          pin_failure["attempts"]), (None, None, 2))
                        collision = pin_failure["retired_collision"]
                        self.assertTrue(collision["terminal"])
                        self.assertEqual(collision["generation"],
                                         {**old["generation"], "pid": child})
                        self.assertEqual(injected["actual_original_identity"]["pid"], old["pid"])
                        if changed_fd:
                            self.assertNotEqual(collision["pidfd"], old["pidfd"])
                            self.assertEqual(injected["collision_pidfd_pid"], parent)
                            self.assertRegex(evidence["cleanup_error"], "旧原身份碰撞证据已改变")
                            self.assertEqual(evidence["remaining_unfixed_children"], [child])
                            self.assertEqual(unresolved["pidfd_open_errors"], 0)
                            self.assertEqual(unresolved["retired_collision_errors"], 2)
                            self.assertNotIn("resolved_monotonic_ns", pin_failure)
                            self.assertFalse(child_ptrace)
                            self.assertFalse(signals)
                            self.assertTrue(Path(f"/proc/{child}").exists())
                        else:
                            self.assertEqual(collision["pidfd"], old["pidfd"])
                            self.assert_clean(evidence)
                            self.assertNotIn("cleanup_error", evidence)
                            self.assertTrue(pin_failure["cleanup_only"])
                            self.assertEqual(pin_failure["signal_info"]["signo"], signal.SIGSTOP)
                            self.assertEqual(pin_failure["signal_info"]["errno"], 0)
                            self.assertTrue(any(request == driver_module.GETSIGINFO
                                                for request, _ in child_ptrace))
                            self.assertIn((driver_module.CONT, signal.SIGKILL), child_ptrace)
                            self.assertIn((driver_module.CONT, 0), child_ptrace)
                            child_cleanup = [row for row in evidence["cleanup"]
                                             if row.get("pid") == child
                                             and row["kind"].startswith("unfixed-child-")]
                            self.assertEqual([row["kind"] for row in child_cleanup], [
                                "unfixed-child-first-stop", "unfixed-child-exit-stop",
                                "unfixed-child-terminal-retained", "unfixed-child-reaped"])
                            terminal, adopted = child_cleanup[-2:]
                            self.assertEqual((terminal["si_code"], terminal["si_status"]),
                                             (os.CLD_KILLED, signal.SIGKILL))
                            self.assertEqual(terminal["first_identity"], pin_failure["first_identity"])
                            self.assertEqual(adopted["adopted_identity"]["starttime_ticks"],
                                             injected["generation"]["starttime_ticks"])
                            self.assertEqual((adopted["adopted_identity"]["ppid"],
                                              adopted["adopted_identity"]["state"]), (tracer, "Z"))
                            retired = next(row for row in evidence["cleanup"]
                                           if row.get("pid") == child
                                           and row["kind"] == "retired-original-task-reaped")
                            self.assertEqual(retired["pidfd"], old["pidfd"])
                            self.assertEqual(retired["pidfd_pid"], -1)
                            self.assertEqual(retired["generation"], collision["generation"])
                            self.assertNotEqual(retired["generation"], injected["generation"])
                            with self.assertRaises(OSError) as closed:
                                os.fstat(old["pidfd"])
                            self.assertEqual(closed.exception.errno, errno.EBADF)
                            self.assertEqual({pid for pid, delivered, _ in signals
                                              if delivered == signal.SIGKILL}, {parent})
                            order = [pin_failure[key] for key in (
                                "first_stop_monotonic_ns", "terminal_monotonic_ns",
                                "parent_terminal_monotonic_ns", "parent_reaped_monotonic_ns",
                                "reaped_monotonic_ns", "resolved_monotonic_ns")]
                            self.assertEqual(order, sorted(order))
                            self.assert_tasks_reaped(old["pid"], child, parent)
                        state = original_waitid(os.P_PIDFD, caller_pidfd,
                                                os.WSTOPPED | os.WNOHANG | os.WNOWAIT)
                        self.assertEqual((state.si_pid, state.si_code, state.si_status),
                                         (unrelated, os.CLD_STOPPED, signal.SIGSTOP))
                        print(json.dumps({
                            "kind": "retired-index-collision-cleanup",
                            "numeric_pid_collision_simulated": True,
                            "actual_original_identity": injected["actual_original_identity"],
                            "new_original_identity": injected["generation"],
                            "changed_retired_fd": changed_fd, "pin_failure": pin_failure,
                            "collision_pidfd_pid_before_cleanup": injected.get("collision_pidfd_pid", -1),
                            "cleanup_error": evidence.get("cleanup_error"),
                            "remaining_unfixed_children": evidence["remaining_unfixed_children"],
                            "caller_stop_preserved": True,
                        }, sort_keys=True, separators=(",", ":")), flush=True)
                    finally:
                        if rescue:
                            # 仅测试救场：恢复备用原父 pidfd 和未关闭的旧原 fd，重走真实收容。
                            self.driver.owned.update(rescue)
                            self.driver.retired[injected["child"]] = old["pidfd"]
                            for unresolved in self.driver.unfixed_children.values():
                                summary = unresolved["summary"]
                                summary["parent_pidfd"] = rescue[summary["parent_pid"]]
                                summary["retired_collision"]["pidfd"] = old["pidfd"]
                            previous = driver_module.ctypes.c_int()
                            self.assertEqual(driver_module.libc.prctl(
                                driver_module.PR_GET_CHILD_SUBREAPER,
                                driver_module.ctypes.byref(previous), 0, 0, 0), 0)
                            self.assertEqual(driver_module.libc.prctl(
                                driver_module.PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0), 0)
                            try:
                                original_cleanup()
                            finally:
                                self.assertEqual(driver_module.libc.prctl(
                                    driver_module.PR_SET_CHILD_SUBREAPER, previous.value, 0, 0, 0), 0)
                                for descriptor in (*rescue.values(), old["pidfd"]):
                                    try:
                                        os.close(descriptor)
                                    except OSError as error:
                                        if error.errno != errno.EBADF:
                                            raise
                            self.assert_tasks_reaped(old["pid"], injected["child"], injected["parent"])
                            self.assertFalse(self.driver.unfixed_children)
                            self.assertFalse(self.driver.owned)
                            self.assertFalse(self.driver.retired)
                            self.assertEqual(len(os.listdir("/proc/self/fd")),
                                             self.driver.evidence["fd_count_before"])
            original_waitid(os.P_PIDFD, caller_pidfd, os.WSTOPPED)
            original_signal(caller_pidfd, signal.SIGCONT)
            state = original_waitid(os.P_PIDFD, caller_pidfd, os.WEXITED)
            self.assertEqual((state.si_pid, state.si_code, state.si_status),
                             (unrelated, os.CLD_EXITED, 29))
            caller_reaped = True
        finally:
            if not caller_reaped:
                try:
                    original_signal(caller_pidfd, signal.SIGKILL)
                    original_waitid(os.P_PIDFD, caller_pidfd, os.WEXITED)
                except (ProcessLookupError, ChildProcessError):
                    pass
            os.close(caller_pidfd)

    def test_child_pin_failure_changed_parent_barrier_reports_unfixed_child(self):
        self.driver = driver_module.ControlledDriver(time.monotonic() + 5,
                                                     self.receiver, self.expected)
        original_open, original_event = os.pidfd_open, driver_module.event_message
        injected, rescue = {}, {}

        def unavailable_child(pid, *args, **kwargs):
            if not injected and pid != self.driver.master:
                current = driver_module.process_snapshot(pid)
                parent = current["ppid"]
                if parent != self.driver.master and parent in self.driver.owned:
                    injected.update({"child": pid, "parent": parent, "at": time.monotonic_ns()})
                    rescue.update({task: os.dup(descriptor)
                                   for task, descriptor in self.driver.owned.items()})
                    raise OSError(errno.EPERM, os.strerror(errno.EPERM))
            return original_open(pid, *args, **kwargs)

        def changed_parent_event(pid):
            child = original_event(pid)
            if self.driver.ledger.closed and pid == injected.get("parent"):
                return child + 1
            return child

        try:
            with (
                patch.object(driver_module.os, "pidfd_open", unavailable_child),
                patch.object(driver_module, "event_message", changed_parent_event),
            ):
                with self.assertRaises(driver_module.Failure) as failure:
                    self.driver.run(lambda: self.cross_exec("setsid"))
            self.assertIsInstance(failure.exception.__cause__, OSError)
            self.assertEqual(failure.exception.__cause__.errno, errno.EPERM)
            evidence = copy.deepcopy(self.driver.evidence)
            child, parent = injected["child"], injected["parent"]
            self.assertEqual(evidence["remaining_unfixed_children"], [child])
            self.assertRegex(evidence["cleanup_error"], "停止屏障已改变")
            pin_failure, = evidence["child_pin_failures"]
            self.assertEqual((pin_failure["first_errno"], pin_failure["attempts"]), (errno.EPERM, 1))
            self.assertNotIn("resolved_monotonic_ns", pin_failure)
            self.assertFalse(any(row.get("signal") == signal.SIGKILL for row in evidence["cleanup"]))
            self.assertLess(evidence["last_normal_resume_monotonic_ns"], injected["at"])
            self.assertNotIn(child, self.driver.registered)
            self.assertNotIn(child, self.driver.owned)
            self.assertTrue(Path(f"/proc/{child}").exists())
            print(json.dumps({
                "kind": "changed-parent-barrier-unfixed-child", **injected,
                "cleanup_error": evidence["cleanup_error"],
                "remaining_unfixed_children": evidence["remaining_unfixed_children"],
            }, sort_keys=True, separators=(",", ":")), flush=True)
        finally:
            if rescue:
                # 仅测试救场：撤销故障后恢复备用原 pidfd，不能覆盖已被复用的 FD 槽。
                for task, descriptor in rescue.items():
                    self.assertEqual(self.driver._pidfd_pid(descriptor), task)
                    self.driver.owned[task] = descriptor
                for unresolved in self.driver.unfixed_children.values():
                    summary = unresolved["summary"]
                    summary["parent_pidfd"] = rescue[summary["parent_pid"]]
                previous = driver_module.ctypes.c_int()
                self.assertEqual(driver_module.libc.prctl(driver_module.PR_GET_CHILD_SUBREAPER,
                                                         driver_module.ctypes.byref(previous), 0, 0, 0), 0)
                self.assertEqual(driver_module.libc.prctl(driver_module.PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0), 0)
                try:
                    self.driver._cleanup()
                finally:
                    self.assertEqual(driver_module.libc.prctl(driver_module.PR_SET_CHILD_SUBREAPER,
                                                             previous.value, 0, 0, 0), 0)
                    for descriptor in rescue.values():
                        try:
                            os.close(descriptor)
                        except OSError as error:
                            if error.errno != errno.EBADF:
                                raise
                self.assert_tasks_reaped(injected["child"], injected["parent"], self.driver.master)
                self.assertFalse(self.driver.unfixed_children)

    def test_self_group_changes_preserve_multigeneration_exec_history(self):
        marker = Path(self.temp.name) / "group-change-executed"
        for index, (mode, nr) in enumerate((("setpgid", 109), ("setsid", 112))):
            with self.subTest(mode=mode):
                baseline = subprocess.run([self.helper, mode, str(marker)], check=True,
                                          capture_output=True, text=True, timeout=3)
                raw = json.loads(baseline.stdout)
                self.assertEqual(raw["nr"], nr)
                self.assertNotEqual(raw["before_group"], raw["pid"])
                self.assertEqual(raw["after_group"], raw["pid"])
                self.assertEqual(raw["after_session"],
                                 raw["pid"] if mode == "setsid" else raw["before_session"])
                self.assertTrue(marker.exists())
                marker.unlink()
                print(json.dumps({"kind": "raw-group-change-baseline", **raw},
                                 sort_keys=True, separators=(",", ":")), flush=True)
                if index:
                    self.client.close()
                    self.client = socket.socket()
                    self.client.connect(self.listener.getsockname())
                    self.expected["remote"] = list(self.client.getsockname())

                self.driver = driver_module.ControlledDriver(time.monotonic() + 10,
                                                             self.receiver, self.expected)
                evidence = self.driver.run(lambda: self.cross_exec(mode))
                self.assert_clean(evidence)
                self.assertEqual(len(evidence["first_stops"]), 2)
                child_stop, grandchild_stop = evidence["first_stops"]
                child, grandchild = child_stop["pid"], grandchild_stop["pid"]
                self.assertEqual(child_stop["parent_pid"], self.driver.master)
                self.assertEqual(grandchild_stop["parent_pid"], child)
                entry, exited = [row for row in evidence["events"]
                                 if row.get("kind") in ("group-change-entry", "group-change-exit")]
                self.assertEqual((entry["pid"], exited["pid"]), (child, child))
                self.assertEqual((entry["syscall"]["op"], exited["syscall"]["op"]), (1, 2))
                self.assertEqual(entry["syscall"]["arch"], driver_module.AUDIT_ARCH_X86_64)
                self.assertEqual((entry["syscall"]["nr"], exited["nr"]), (nr, nr))
                if mode == "setpgid":
                    self.assertEqual(entry["syscall"]["args"][:2], [0, 0])
                before = {"pgrp": self.driver.master,
                          "sid": child_stop["snapshot"]["process"]["sid"]}
                after = {"pgrp": child, "sid": child if mode == "setsid" else before["sid"]}
                self.assertEqual(entry["before"], before)
                self.assertEqual(exited["before"], before)
                self.assertEqual(exited["after"], after)
                self.assertEqual(exited["syscall"]["rval"], child if mode == "setsid" else 0)
                self.assertFalse(exited["syscall"]["is_error"])
                for key in ("generation", "epoch", "exe"):
                    self.assertEqual(entry[key], exited[key])
                self.assertEqual(entry["epoch"], 0)
                self.assertEqual(entry["generation"],
                                 self.driver.ledger._generation(child_stop["snapshot"]["process"]))
                self.assertEqual(entry["current"]["accepted_matches"],
                                 exited["current"]["accepted_matches"])
                self.assertEqual(len(exited["current"]["accepted_matches"]), 1)
                self.assertLess(entry["wait_monotonic_ns"], exited["entry_monotonic_ns"])
                self.assertEqual(entry["entry_monotonic_ns"], exited["entry_monotonic_ns"])
                self.assertLess(exited["entry_monotonic_ns"], exited["wait_monotonic_ns"])
                self.assertLess(exited["wait_monotonic_ns"], exited["exit_monotonic_ns"])
                self.assertLess(exited["exit_monotonic_ns"],
                                grandchild_stop["creation"]["entry_monotonic_ns"])
                for start, end in (
                        (entry["entry_monotonic_ns"], exited["wait_monotonic_ns"]),
                        (exited["exit_monotonic_ns"],
                         grandchild_stop["creation"]["entry_monotonic_ns"])):
                    resumes = [row for row in evidence["continues"] if row["pid"] == child
                               and start < row["returned_monotonic_ns"] < end]
                    self.assertEqual(len(resumes), 1)
                    self.assertTrue(resumes[0]["normal"])
                for first in (child_stop, grandchild_stop):
                    creation = first["creation"]
                    self.assertEqual((creation["event_child"], creation["exit_rval"]),
                                     (first["pid"], first["pid"]))
                    self.assertEqual(creation["parent_pid"], first["parent_pid"])
                    self.assertLess(creation["entry_monotonic_ns"], creation["event_monotonic_ns"])
                    self.assertLess(creation["event_monotonic_ns"], creation["exit_monotonic_ns"])
                    self.assertLess(creation["exit_monotonic_ns"],
                                    first["first_continue_monotonic_ns"])
                    self.assertEqual(len(first["snapshot"]["accepted_matches"]), 1)
                    self.assertEqual(first["snapshot"]["accepted_matches"],
                                     first["parent_fork_anchor"]["accepted_matches"])
                for snapshot in (grandchild_stop["snapshot"],
                                 grandchild_stop["parent_fork_anchor"]):
                    self.assertEqual({key: snapshot["process"][key] for key in ("pgrp", "sid")},
                                     after)
                self.assertNotEqual(after["pgrp"], self.driver.master)
                for row in self.assert_exec_history(evidence, grandchild):
                    self.assertEqual({key: row["current"]["process"][key]
                                      for key in ("pgrp", "sid")}, after)
                reaped = [row["exit_code"] for row in evidence["events"]
                          if row.get("kind") == "reaped"]
                self.assertEqual(sorted(reaped), [0, 0, 23])
                self.assertFalse(marker.exists())
                self.assert_tasks_reaped(grandchild, child, self.driver.master)
                print(json.dumps({
                    "kind": "self-group-change-exec-chain", "mode": mode, "pid": child,
                    "grandchild": grandchild, "master": self.driver.master,
                    "syscall": {key: entry["syscall"][key] for key in ("nr", "args", "arch")},
                    "before": before, "after": after, "rval": exited["syscall"]["rval"],
                    "epochs": [row["exec_epoch"] for row in evidence["messages"]],
                    "reaped": sorted(reaped), "remaining_group_changes": evidence["remaining_group_changes"],
                }, sort_keys=True, separators=(",", ":")), flush=True)

    def test_group_leader_setsid_eperm_preserves_identity_and_continues(self):
        def fixture():
            before = (os.getpgrp(), os.getsid(0))
            try:
                os.setsid()
            except OSError as error:
                if error.errno != errno.EPERM or (os.getpgrp(), os.getsid(0)) != before:
                    os._exit(116)
            else:
                os._exit(117)
            self.cross_exec()

        self.driver = driver_module.ControlledDriver(time.monotonic() + 5,
                                                     self.receiver, self.expected)
        evidence = self.driver.run(fixture)
        self.assert_clean(evidence)
        entry, exited = [row for row in evidence["events"]
                         if row.get("kind") in ("group-change-entry", "group-change-exit")]
        self.assertEqual((entry["pid"], exited["pid"]), (self.driver.master, self.driver.master))
        self.assertEqual((entry["syscall"]["op"], entry["syscall"]["nr"]), (1, 112))
        self.assertEqual((exited["syscall"]["op"], exited["nr"]), (2, 112))
        self.assertEqual(exited["syscall"]["rval"], -errno.EPERM)
        self.assertTrue(exited["syscall"]["is_error"])
        self.assertEqual(entry["before"]["pgrp"], self.driver.master)
        self.assertEqual(entry["before"], exited["before"])
        self.assertEqual(entry["before"], exited["after"])
        for key in ("generation", "epoch", "exe"):
            self.assertEqual(entry[key], exited[key])
        self.assertEqual(entry["current"]["accepted_matches"], exited["current"]["accepted_matches"])
        self.assertLess(exited["exit_monotonic_ns"],
                        evidence["first_stops"][0]["creation"]["entry_monotonic_ns"])
        self.assert_exec_history(evidence, evidence["first_stops"][0]["pid"])
        self.assertEqual(sorted(row["exit_code"] for row in evidence["events"]
                                if row.get("kind") == "reaped"), [0, 23])
        self.assert_tasks_reaped(evidence["first_stops"][0]["pid"], self.driver.master)
        print(json.dumps({
            "kind": "group-leader-setsid-eperm", "pid": self.driver.master,
            "before": entry["before"], "after": exited["after"],
            "rval": exited["syscall"]["rval"], "is_error": exited["syscall"]["is_error"],
            "continued_to_cross_exec": True,
        }, sort_keys=True, separators=(",", ":")), flush=True)

    def test_group_exit_invalid_return_keeps_proof_for_cleanup(self):
        self.driver = driver_module.ControlledDriver(time.monotonic() + 5,
                                                     self.receiver, self.expected)
        original_info = driver_module.syscall_info
        injected = {}

        def invalid_setsid_return(pid):
            info = original_info(pid)
            pending = self.driver.group_changes.get(pid)
            if (info["op"] == 2 and pending
                    and pending["entry"]["nr"] == driver_module.SYS_SETSID and not injected):
                self.driver._require_stop(pid)
                self.assertFalse(info["is_error"])
                self.assertEqual(info["rval"], pid)
                current = driver_module.process_snapshot(pid)
                self.assertEqual((current["pgrp"], current["sid"]), (pid, pid))
                injected.update({"pid": pid, "real_exit": copy.deepcopy(info),
                                 "observed": {"pgrp": current["pgrp"], "sid": current["sid"]},
                                 "at": time.monotonic_ns()})
                info = {**info, "rval": pid + 1}
            return info

        with patch.object(driver_module, "syscall_info", side_effect=invalid_setsid_return):
            with self.assertRaisesRegex(driver_module.Failure, "返回值或终态无效"):
                self.driver.run(lambda: self.cross_exec("setsid"))
        evidence = self.driver.evidence
        self.assert_clean(evidence)
        self.assertTrue(injected)
        child = injected["pid"]
        rejected = next(row for row in evidence["events"] if "rejection" in row)
        self.assertEqual((rejected["kind"], rejected["pid"], rejected["nr"]),
                         ("group-change-exit", child, driver_module.SYS_SETSID))
        self.assertEqual(rejected["syscall"]["rval"], child + 1)
        self.assertEqual(rejected["after"], {"pgrp": child, "sid": child})
        self.assertEqual(evidence["discarded_group_proofs"], [child])
        self.assertEqual(len(evidence["first_stops"]), 1)
        self.assertEqual(len(evidence["creations"]), 1)
        self.assertFalse(evidence["messages"])
        self.assertLess(evidence["last_normal_resume_monotonic_ns"], injected["at"])
        self.assertFalse(any(row["returned_monotonic_ns"] >= injected["at"]
                             for row in evidence["continues"]))
        self.assertTrue(evidence["ledger_poisoned"])
        self.assert_tasks_reaped(child, self.driver.master)
        print(json.dumps({
            "kind": "invalid-group-exit-proof-rejection", **injected,
            "injected_rval": rejected["syscall"]["rval"],
            "discarded_group_proofs": evidence["discarded_group_proofs"],
            "remaining_group_changes": evidence["remaining_group_changes"],
        }, sort_keys=True, separators=(",", ":")), flush=True)

    def test_other_process_or_group_setpgid_is_rejected_at_entry(self):
        marker = Path(self.temp.name) / "other-group-change-executed"
        for index, mode in enumerate(("other-process", "other-group")):
            with self.subTest(mode=mode):
                if index:
                    self.client.close()
                    self.client = socket.socket()
                    self.client.connect(self.listener.getsockname())
                    self.expected["remote"] = list(self.client.getsockname())

                def fixture():
                    self.client.close()
                    accepted, _ = self.listener.accept()
                    self.listener.close()
                    child = os.fork()
                    if child == 0:
                        try:
                            if mode == "other-process":
                                os.setpgid(os.getppid(), 0)
                            else:
                                os.setpgid(0, os.getpgrp())
                        except OSError:
                            pass
                        marker.write_text("executed")
                        os._exit(0)
                    accepted.close()
                    os.waitpid(child, 0)

                self.driver = driver_module.ControlledDriver(time.monotonic() + 5,
                                                             self.receiver, self.expected)
                with self.assertRaisesRegex(driver_module.Failure, "setpgid"):
                    self.driver.run(fixture)
                evidence = self.driver.evidence
                self.assert_clean(evidence)
                rejected = next(row for row in evidence["events"] if "rejection" in row)
                self.assertEqual(rejected["kind"], "group-change-entry")
                self.assertEqual((rejected["syscall"]["op"], rejected["syscall"]["nr"]), (1, 109))
                self.assertEqual(rejected["syscall"]["arch"], driver_module.AUDIT_ARCH_X86_64)
                args = [self.driver.master, 0] if mode == "other-process" else [0, self.driver.master]
                self.assertEqual(rejected["syscall"]["args"][:2], args)
                child = evidence["first_stops"][0]["pid"]
                self.assertEqual(rejected["pid"], child)
                self.assertEqual(rejected["current"]["process"]["pgrp"], self.driver.master)
                self.assertFalse(any(row.get("kind") == "group-change-exit"
                                     for row in evidence["events"]))
                self.assertLess(evidence["last_normal_resume_monotonic_ns"],
                                rejected["rejected_monotonic_ns"])
                self.assertFalse(any(row["returned_monotonic_ns"] >= rejected["rejected_monotonic_ns"]
                                     for row in evidence["continues"]))
                self.assertFalse(marker.exists())
                self.assertTrue(evidence["ledger_poisoned"])
                self.assert_tasks_reaped(child, self.driver.master)
                print(json.dumps({
                    "kind": "other-setpgid-entry-rejection", "mode": mode, "pid": child,
                    "syscall": {key: rejected["syscall"][key] for key in ("nr", "args", "arch")},
                    "marker_exists": marker.exists(),
                    "remaining_group_changes": evidence["remaining_group_changes"],
                }, sort_keys=True, separators=(",", ":")), flush=True)

    def test_detached_group_failure_reaps_pinned_grandchild(self):
        for index, mode in enumerate(("setpgid", "setsid")):
            with self.subTest(mode=mode):
                if index:
                    self.client.close()
                    self.client = socket.socket()
                    self.client.connect(self.listener.getsockname())
                    self.expected["remote"] = list(self.client.getsockname())
                self.driver = driver_module.ControlledDriver(time.monotonic() + 10,
                                                             self.receiver, self.expected)
                original_continue = self.driver._normal_continue
                original_kill = os.kill
                original_pidfd_signal = signal.pidfd_send_signal
                tracer, injection, sent = os.getpid(), {}, []

                def fail_after_grandchild_pin(pid, delivered_signal=0, record=True):
                    creation = self.driver.creations.get(pid)
                    if (pid != self.driver.master and creation and "event_child" in creation
                            and not injection):
                        grandchild = creation["event_child"]
                        self.assertIn(grandchild, self.driver.owned)
                        current = driver_module.process_snapshot(pid)
                        self.assertEqual(current["pgrp"], pid)
                        injection.update({"pid": pid, "grandchild": grandchild,
                                          "pgrp": current["pgrp"], "sid": current["sid"],
                                          "at": time.monotonic_ns()})
                        raise driver_module.Failure("测试注入脱组 grandchild 已固定后的失败")
                    return original_continue(pid, delivered_signal, record)

                def deny_driver_numeric_signal(pid, delivered):
                    # fixture 的自停仍由真实 syscall 产生，主 tracer 只能用原 pidfd 发信号。
                    if os.getpid() != tracer and pid == os.getpid() and delivered == signal.SIGSTOP:
                        return original_kill(pid, delivered)
                    raise AssertionError("脱组清理禁止数字 PID 发信号")

                def send_original_pidfd(descriptor, delivered, siginfo=None, flags=0):
                    pid = next(task for task, held in self.driver.owned.items() if held == descriptor)
                    self.assertEqual(self.driver._pidfd_pid(descriptor), pid)
                    sent.append({"pid": pid, "signal": delivered, "at": time.monotonic_ns()})
                    return original_pidfd_signal(descriptor, delivered, siginfo, flags)

                self.driver._normal_continue = fail_after_grandchild_pin
                with patch.object(driver_module.os, "kill", side_effect=deny_driver_numeric_signal), \
                        patch.object(driver_module.os, "killpg",
                                     side_effect=AssertionError("脱组清理禁止进程组发信号")), \
                        patch.object(driver_module.signal, "pidfd_send_signal",
                                     side_effect=send_original_pidfd):
                    with self.assertRaisesRegex(driver_module.Failure, "脱组 grandchild 已固定"):
                        self.driver.run(lambda: self.cross_exec(mode))
                evidence = self.driver.evidence
                self.assert_clean(evidence)
                self.assertTrue(injection)
                child, grandchild = injection["pid"], injection["grandchild"]
                self.assertNotEqual(injection["pgrp"], self.driver.master)
                exited = next(row for row in evidence["events"]
                              if row.get("kind") == "group-change-exit")
                self.assertEqual(injection["sid"], child if mode == "setsid" else exited["before"]["sid"])
                rejected = next(row for row in evidence["events"] if "rejection" in row)
                self.assertEqual((rejected["kind"], rejected["pid"], rejected["child_pid"]),
                                 ("fork-parent-stop", child, grandchild))
                pinned = next(row for row in evidence["task_pins"] if row["pid"] == grandchild)
                self.assertLess(exited["exit_monotonic_ns"], pinned["pinned_monotonic_ns"])
                self.assertLess(pinned["pinned_monotonic_ns"], injection["at"])
                self.assertLess(evidence["last_normal_resume_monotonic_ns"],
                                rejected["rejected_monotonic_ns"])
                self.assertFalse(any(row["returned_monotonic_ns"] >= injection["at"]
                                     for row in evidence["continues"]))
                kills = [row for row in sent if row["signal"] == signal.SIGKILL]
                self.assertEqual({row["pid"] for row in kills}, {self.driver.master, child, grandchild})
                self.assertLess(pinned["pinned_monotonic_ns"], min(row["at"] for row in kills))
                self.assertFalse(evidence["messages"])
                self.assert_tasks_reaped(grandchild, child, self.driver.master)
                print(json.dumps({
                    "kind": "detached-group-pinned-grandchild-cleanup", "mode": mode,
                    **injection, "master": self.driver.master, "pidfd_signals": sent,
                    "remaining_group_changes": evidence["remaining_group_changes"],
                }, sort_keys=True, separators=(",", ":")), flush=True)

    def test_real_x32_and_i386_abi_are_rejected(self):
        marker = str(Path(self.temp.name) / "unverified-abi-executed")
        for index, mode in enumerate(("x32", "i386")):
            with self.subTest(mode=mode):
                if index:
                    self.client.close()
                    self.client = socket.socket()
                    self.client.connect(self.listener.getsockname())
                    self.expected["remote"] = list(self.client.getsockname())

                def fixture():
                    self.client.close()
                    accepted, _ = self.listener.accept()
                    self.listener.close()
                    os.execv(self.helper, [self.helper, mode, marker])

                self.driver = driver_module.ControlledDriver(time.monotonic() + 5,
                                                             self.receiver, self.expected)
                with self.assertRaisesRegex(driver_module.Failure, "x32 syscall|ABI"):
                    self.driver.run(fixture)
                evidence = self.driver.evidence
                self.assert_clean(evidence)
                rejected = next(row for row in evidence["events"] if "rejection" in row)
                self.assertLess(evidence["last_normal_resume_monotonic_ns"],
                                rejected["rejected_monotonic_ns"])
                self.assertFalse(Path(marker).exists())

    def test_deadline_after_finish_refuses_continue_and_closes_fds(self):
        self.driver = driver_module.ControlledDriver(time.monotonic() + 1,
                                                     self.receiver, self.expected)
        original = self.driver._normal_continue
        injection, held_and_received = {}, set()

        def delayed(pid, delivered_signal=0, record=True):
            identity = self.driver.ledger.registry[pid]
            if identity["epoch"] == 1 and not injection:
                injection["before"] = time.monotonic()
                injection["deadline"] = self.driver.ledger.deadline
                self.assertLess(injection["before"], injection["deadline"])
                held_and_received.update(row["held_pidfd"] for row in self.driver.ledger.registry.values())
                held_and_received.update(row["pidfd"][0]["value"] for row in self.driver.ledger.messages)
                time.sleep(injection["deadline"] - time.monotonic() + 0.025)
                injection["after"] = time.monotonic()
            return original(pid, delivered_signal, record)

        self.driver._normal_continue = delayed
        with self.assertRaisesRegex(driver_module.Failure, "总窗口已超时"):
            self.driver.run(self.cross_exec)
        evidence = self.driver.evidence
        self.assert_clean(evidence)
        self.assertGreaterEqual(injection["after"], injection["deadline"])
        self.assertEqual(self.driver.ledger.deadline, injection["deadline"])
        self.assertTrue(evidence["ledger_poisoned"])
        self.assertFalse(any(row["accepted"] or row["pending"] for row in evidence["messages"]))
        self.assertLess(evidence["last_normal_resume_monotonic_ns"], int(injection["before"] * 1e9))
        for descriptor in held_and_received:
            with self.assertRaises(OSError) as error:
                os.fstat(descriptor)
            self.assertEqual(error.exception.errno, errno.EBADF)

    def test_consumed_fork_wait_timeout_keeps_new_child_for_cleanup(self):
        self.driver = driver_module.ControlledDriver(time.monotonic() + 1,
                                                     self.receiver, self.expected)
        original = self.driver._wait
        injection = {}

        def delayed(initial=False):
            pid, status = original(initial)
            if os.WIFSTOPPED(status) and status >> 16 == driver_module.FORK:
                injection["before"] = time.monotonic()
                injection["deadline"] = self.driver.ledger.deadline
                self.assertLess(injection["before"], injection["deadline"])
                time.sleep(injection["deadline"] - time.monotonic() + 0.025)
                injection["after"] = time.monotonic()
            return pid, status

        self.driver._wait = delayed
        with self.assertRaisesRegex(driver_module.Failure, "总窗口已超时"):
            self.driver.run(self.cross_exec)
        evidence = self.driver.evidence
        self.assert_clean(evidence)
        self.assertGreaterEqual(injection["after"], injection["deadline"])
        fork = next(row for row in evidence["events"] if row.get("event") == driver_module.FORK)
        self.assertGreater(fork["child_pid"], 0)
        self.assertFalse(Path(f"/proc/{fork['child_pid']}").exists())
        self.assertLess(evidence["last_normal_resume_monotonic_ns"], int(injection["before"] * 1e9))

    def test_unconsumed_fork_timeout_discovers_child_during_cleanup(self):
        self.driver = driver_module.ControlledDriver(time.monotonic() + 1,
                                                     self.receiver, self.expected)
        original = self.driver._wait
        injection = {}

        def delayed(initial=False):
            if (not initial and not injection
                    and self.driver.creations.get(self.driver.master)):
                ready_deadline = self.driver.ledger.deadline
                while time.monotonic() < ready_deadline:
                    children = Path(f"/proc/{self.driver.master}/task/{self.driver.master}/children").read_text()
                    if children.strip() and driver_module.process_snapshot(self.driver.master)["state"] == "t":
                        injection["child"] = int(children.split()[0])
                        break
                    time.sleep(0.001)
                self.assertIn("child", injection)
                injection["before"] = time.monotonic()
                injection["deadline"] = self.driver.ledger.deadline
                self.assertLess(injection["before"], injection["deadline"])
                self.assertNotIn(injection["child"], self.driver.tracked)
                self.assertNotIn(injection["child"], self.driver.owned)
                time.sleep(injection["deadline"] - time.monotonic() + 0.025)
                injection["after"] = time.monotonic()
            return original(initial)

        self.driver._wait = delayed
        with self.assertRaisesRegex(driver_module.Failure, "总窗口已超时"):
            self.driver.run(self.cross_exec)
        evidence = self.driver.evidence
        self.assert_clean(evidence)
        self.assertGreaterEqual(injection["after"], injection["deadline"])
        self.assertFalse(Path(f"/proc/{injection['child']}").exists())
        cleanup = evidence["cleanup"]
        pinned = next(index for index, row in enumerate(cleanup)
                      if row["kind"] == "pin-child" and row["pid"] == injection["child"])
        self.assertEqual(cleanup[pinned]["parent_pid"], self.driver.master)
        self.assertEqual(cleanup[pinned]["source"], "cleanup")
        killed = [index for index, row in enumerate(cleanup) if row["kind"] == "kill-original-task"]
        self.assertTrue(killed)
        self.assertLess(pinned, min(killed))
        reaped = {row.get("pid") for row in cleanup
                  if row["kind"] in ("pidfd-reaped-task", "retired-original-task-reaped")}
        self.assertIn(injection["child"], reaped)
        self.assertLess(evidence["last_normal_resume_monotonic_ns"], int(injection["before"] * 1e9))

    def test_running_tracer_exitkill_reaps_subtree(self):
        previous = driver_module.ctypes.c_int()
        if driver_module.libc.prctl(driver_module.PR_GET_CHILD_SUBREAPER,
                                   driver_module.ctypes.byref(previous), 0, 0, 0) != 0:
            raise OSError("不能读取测试 subreaper 状态")
        if driver_module.libc.prctl(driver_module.PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0) != 0:
            raise OSError("不能启用测试 subreaper")
        read_fd, write_fd = os.pipe()
        baseline = len(os.listdir("/proc/self/fd"))
        tracer = os.fork()
        if tracer == 0:
            os.close(read_fd)

            def running_fixture():
                self.client.close()
                accepted, _ = self.listener.accept()
                self.listener.close()
                child = os.fork()
                if child == 0:
                    os.write(write_fd, json.dumps(
                        {"child": os.getpid(), "master": os.getppid()}).encode() + b"\n")
                    os.close(write_fd)
                    while True:
                        time.sleep(0.01)
                accepted.close()
                os.close(write_fd)
                # 回收由外层 subreaper 负责，避免 master 与测试竞争 child 的退出状态。
                while True:
                    time.sleep(0.01)

            try:
                driver_module.ControlledDriver(time.monotonic() + 5, self.receiver,
                                               self.expected).run(running_fixture)
            finally:
                os._exit(113)
        os.close(write_fd)
        owned, descriptors, reaped = {tracer}, [], set()
        try:
            self.assertTrue(select.select([read_fd], [], [], 3)[0])
            info = json.loads(os.read(read_fd, 4096))
            owned.update((info["master"], info["child"]))
            running_deadline = time.monotonic() + 1
            while time.monotonic() < running_deadline:
                processes = [driver_module.process_snapshot(pid)
                             for pid in (info["master"], info["child"])]
                if all(process["state"] not in ("t", "T", "Z") for process in processes):
                    break
                time.sleep(0.001)
            else:
                self.fail("EXITKILL fixture 没有进入运行态")
            poller = select.poll()
            for pid, process in zip((info["master"], info["child"]), processes):
                self.assertNotIn(process["state"], ("t", "T", "Z"))
                self.assertEqual(process["pgrp"], info["master"])
                status = Path(f"/proc/{pid}/status").read_text()
                self.assertIn(f"TracerPid:\t{tracer}\n", status)
                descriptor = os.pidfd_open(pid)
                descriptors.append(descriptor)
                poller.register(descriptor, select.POLLIN)
            self.assertFalse(poller.poll(0))
            os.kill(tracer, signal.SIGKILL)
            self.assertEqual(os.waitpid(tracer, 0)[1], signal.SIGKILL)
            reaped.add(tracer)
            deadline = time.monotonic() + 2
            notified = set()
            while time.monotonic() < deadline and len(notified) < 2:
                notified.update(descriptor for descriptor, _mask in poller.poll(10))
            self.assertEqual(notified, set(descriptors))
            for pid in (info["master"], info["child"]):
                while time.monotonic() < deadline:
                    try:
                        waited, status = os.waitpid(pid, os.WNOHANG)
                    except ChildProcessError:
                        # pidfd 已通知退出，但后代可能尚未转交到本测试 subreaper。
                        waited = 0
                    if waited:
                        reaped.add(pid)
                        self.assertTrue(os.WIFSIGNALED(status))
                        self.assertEqual(os.WTERMSIG(status), signal.SIGKILL)
                        break
                    time.sleep(0.001)
                self.assertIn(pid, reaped,
                              f"EXITKILL task {pid}: proc_exists={Path(f'/proc/{pid}').exists()}")
                self.assertFalse(Path(f"/proc/{pid}").exists())
            with self.assertRaises(ChildProcessError):
                os.waitpid(-1, os.WNOHANG)
        finally:
            for pid in owned - reaped:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            cleanup_deadline = time.monotonic() + 2
            for pid in sorted(owned - reaped, key=lambda value: value != tracer):
                while time.monotonic() < cleanup_deadline:
                    try:
                        waited, _status = os.waitpid(pid, os.WNOHANG)
                    except ChildProcessError:
                        # 真实父退出后才转交 subreaper，ECHILD 不能直接判定清理完成。
                        if not Path(f"/proc/{pid}").exists():
                            break
                        waited = 0
                    if waited:
                        break
                    time.sleep(0.001)
            for descriptor in descriptors:
                os.close(descriptor)
            os.close(read_fd)
            if driver_module.libc.prctl(driver_module.PR_SET_CHILD_SUBREAPER,
                                       previous.value, 0, 0, 0) != 0:
                raise OSError("不能恢复测试 subreaper 状态")
        self.assertEqual(len(os.listdir("/proc/self/fd")), baseline - 2)


if __name__ == "__main__":
    unittest.main()
