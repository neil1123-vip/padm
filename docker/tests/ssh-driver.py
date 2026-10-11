#!/usr/bin/env python3
import copy
import errno
import importlib.util
import json
import os
from pathlib import Path
import select
import signal
import socket
import subprocess
import tempfile
import time
import unittest


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

    def cross_exec(self):
        self.client.close()
        accepted, _ = self.listener.accept()
        self.listener.close()
        accepted.set_inheritable(True)
        child = os.fork()
        if child == 0:
            sender = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            sender.sendto(b"old-epoch-zero", self.path)
            sender.close()
            os.kill(os.getpid(), signal.SIGSTOP)
            os.execv(self.helper, [self.helper, "cross-exec", self.path, str(accepted.fileno())])
        accepted.close()
        _, status = os.waitpid(child, 0)
        os._exit(0 if os.WIFEXITED(status) and os.WEXITSTATUS(status) == 23 else 112)

    def assert_clean(self, evidence):
        self.assertFalse(evidence["remaining_tracees"])
        self.assertFalse(evidence["remaining_early_stops"])
        self.assertFalse(evidence["remaining_parent_confirmations"])
        self.assertFalse(evidence["open_received_fds"])
        self.assertEqual(evidence["fd_count_before"], evidence["fd_count_after"])
        self.assertFalse(evidence["authoritative"])
        self.assertFalse(evidence["jail_ready"])
        self.assertTrue(evidence["ledger_closed"])

    def test_python_to_c_epoch_history_and_frozen_trace(self):
        self.driver = driver_module.ControlledDriver(time.monotonic() + 5, self.receiver, self.expected)
        evidence = self.driver.run(self.cross_exec)
        self.assert_clean(evidence)
        self.assertEqual(len(evidence["first_stops"]), 1)
        child = evidence["first_stops"][0]["pid"]
        barriers = [row for row in evidence["events"] if row.get("kind") == "message-barrier"]
        self.assertEqual(len(barriers), 1)
        frozen = barriers[0]["pending_at_barrier"][0]
        self.assertTrue(frozen["pending"])
        self.assertFalse(frozen["accepted"])
        self.assertEqual(frozen["exec_epoch"], 0)
        self.assertEqual(len(barriers[0]["received_fds_at_barrier"]), 1)
        old, new, closed = evidence["messages"]
        self.assertEqual([row["body"] for row in (old, new, closed)],
                         ["old-epoch-zero", "new-epoch-one", "closed-accepted-fd"])
        self.assertTrue(all(row["accepted"] for row in evidence["messages"]))
        self.assertEqual([row["exec_epoch"] for row in evidence["messages"]], [0, 1, 1])
        self.assertNotEqual(old["epoch_exe"], old["current_stop_exe"])
        self.assertEqual(old["current_stop_exe"], self.helper)
        self.assertEqual(new["epoch_exe"], self.helper)
        self.assertFalse(closed["owns_anchor_fd"])
        self.assertFalse(closed["established_tuple_live"])
        self.assertTrue(closed["historical_anchor"]["accepted_matches"])
        self.assertEqual(old["task_generation"], new["task_generation"])
        transitions = [row for row in evidence["events"]
                       if row["pid"] == child and row["event"] in (4, 6)]
        self.assertEqual([row["event"] for row in transitions], [4, 6])
        for row in transitions:
            self.assertTrue(row["ledger"]["drain"]["ended_with_eagain"])
            self.assertLess(row["finish_return_monotonic_ns"], row["continued_monotonic_ns"])
        self.assertEqual(transitions[0]["ledger"]["order"],
                         ["drain-eagain", "pending-commit", "epoch-update"])
        self.assertEqual(transitions[1]["ledger"]["order"],
                         ["drain-eagain", "pending-commit", "epoch-terminal"])
        reaped = [row["exit_code"] for row in evidence["events"] if row.get("kind") == "reaped"]
        self.assertEqual(sorted(reaped), [0, 23])
        original = copy.deepcopy(evidence["events"])
        self.driver.ledger.messages[0]["body"] = "later-mutation"
        self.assertEqual(evidence["events"], original)

    def test_real_clone_is_rejected_before_any_normal_continue(self):
        def clone_fixture():
            self.client.close()
            accepted, _ = self.listener.accept()
            self.listener.close()
            os.execv(self.helper, [self.helper, "clone"])

        self.driver = driver_module.ControlledDriver(time.monotonic() + 5, self.receiver, self.expected)
        with self.assertRaisesRegex(driver_module.Failure, "event 3"):
            self.driver.run(clone_fixture)
        evidence = self.driver.evidence
        self.assert_clean(evidence)
        rejected = next(row for row in evidence["events"] if row["event"] == 3)
        self.assertGreater(rejected["child_pid"], 0)
        self.assertTrue(evidence["ledger_poisoned"])
        self.assertFalse(any(row["returned_monotonic_ns"] >= rejected["rejected_monotonic_ns"]
                             for row in evidence["continues"]))
        cleanup_pids = {row.get("pid") for row in evidence["cleanup"]
                        if row["kind"] in ("cleanup-reaped", "kernel-reaped-task")}
        self.assertIn(rejected["child_pid"], cleanup_pids)
        self.assertFalse(Path(f"/proc/{rejected['child_pid']}").exists())
        self.assertTrue(all(row.get("signal") == signal.SIGKILL
                            for row in evidence["cleanup"] if row["kind"] == "cleanup-continue"))

    def test_deadline_after_finish_refuses_continue_and_closes_fds(self):
        self.driver = driver_module.ControlledDriver(time.monotonic() + 1,
                                                     self.receiver, self.expected)
        original = self.driver._normal_continue
        injection, held_and_received = {}, set()

        def delayed(pid, delivered_signal=0):
            identity = self.driver.ledger.registry[pid]
            if identity["epoch"] == 1 and not injection:
                injection["before"] = time.monotonic()
                injection["deadline"] = self.driver.ledger.deadline
                self.assertLess(injection["before"], injection["deadline"])
                held_and_received.update(row["held_pidfd"] for row in self.driver.ledger.registry.values())
                held_and_received.update(row["pidfd"][0]["value"] for row in self.driver.ledger.messages)
                time.sleep(injection["deadline"] - time.monotonic() + 0.025)
                injection["after"] = time.monotonic()
            return original(pid, delivered_signal)

        self.driver._normal_continue = delayed
        with self.assertRaisesRegex(driver_module.Failure, "总窗口已超时"):
            self.driver.run(self.cross_exec)
        evidence = self.driver.evidence
        self.assert_clean(evidence)
        self.assertGreaterEqual(injection["after"], injection["deadline"])
        self.assertEqual(self.driver.ledger.deadline, injection["deadline"])
        self.assertTrue(evidence["ledger_poisoned"])
        self.assertFalse(any(row["accepted"] or row["pending"] for row in evidence["messages"]))
        self.assertFalse(any(row["returned_monotonic_ns"] >= int(injection["before"] * 1e9)
                             for row in evidence["continues"]))
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
        fork = next(row for row in evidence["events"] if row["event"] == driver_module.FORK)
        self.assertGreater(fork["child_pid"], 0)
        self.assertFalse(Path(f"/proc/{fork['child_pid']}").exists())
        self.assertFalse(any(row["returned_monotonic_ns"] >= int(injection["before"] * 1e9)
                             for row in evidence["continues"]))

    def test_unconsumed_fork_timeout_discovers_child_during_cleanup(self):
        self.driver = driver_module.ControlledDriver(time.monotonic() + 1,
                                                     self.receiver, self.expected)
        original = self.driver._wait
        injection = {}

        def delayed(initial=False):
            if not initial and not injection:
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
        cleanup_pids = {row.get("pid") for row in evidence["cleanup"]
                        if row["kind"] in ("cleanup-reaped", "kernel-reaped-task")}
        self.assertIn(injection["child"], cleanup_pids)
        self.assertFalse(any(row["returned_monotonic_ns"] >= int(injection["before"] * 1e9)
                             for row in evidence["continues"]))

    def test_running_tracer_exitkill_reaps_subtree(self):
        previous = driver_module.ctypes.c_int()
        if driver_module.libc.prctl(37, driver_module.ctypes.byref(previous), 0, 0, 0) != 0:
            raise OSError("不能读取测试 subreaper 状态")
        if driver_module.libc.prctl(36, 1, 0, 0, 0) != 0:
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
                os.waitpid(child, 0)

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
                    waited, status = os.waitpid(pid, os.WNOHANG)
                    if waited:
                        reaped.add(pid)
                        self.assertTrue(os.WIFSIGNALED(status))
                        self.assertEqual(os.WTERMSIG(status), signal.SIGKILL)
                        break
                    time.sleep(0.001)
                self.assertIn(pid, reaped)
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
                        break
                    if waited:
                        break
                    time.sleep(0.001)
            for descriptor in descriptors:
                os.close(descriptor)
            os.close(read_fd)
            if driver_module.libc.prctl(36, previous.value, 0, 0, 0) != 0:
                raise OSError("不能恢复测试 subreaper 状态")
        self.assertEqual(len(os.listdir("/proc/self/fd")), baseline - 2)


if __name__ == "__main__":
    unittest.main()
