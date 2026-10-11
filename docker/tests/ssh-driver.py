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
        self.assertFalse(evidence["remaining_syscall_tasks"])
        self.assertFalse(evidence["remaining_first_exit_tasks"])
        self.assertFalse(evidence["remaining_waiting_parent_exit"])
        self.assertFalse(evidence["open_received_fds"])
        self.assertEqual(evidence["fd_count_before"], evidence["fd_count_after"])
        self.assertFalse(evidence["authoritative"])
        self.assertFalse(evidence["jail_ready"])
        self.assertTrue(evidence["ledger_closed"])

    def test_python_to_c_epoch_history_and_frozen_trace(self):
        self.driver = driver_module.ControlledDriver(time.monotonic() + 5, self.receiver, self.expected)
        original_wait = self.driver._wait
        forced_child_first_stop = []

        def child_before_parent_exit(initial=False):
            creation = self.driver.creations.get(self.driver.master)
            if (not initial and creation and "event_child" not in creation
                    and not forced_child_first_stop):
                deadline = self.driver.ledger.deadline
                while time.monotonic() < deadline:
                    children = Path(
                        f"/proc/{self.driver.master}/task/{self.driver.master}/children"
                    ).read_text().split()
                    if children:
                        pid, status = os.waitpid(int(children[0]), driver_module.WAIT_FLAGS)
                        if pid:
                            forced_child_first_stop.append(pid)
                            return pid, status
                    time.sleep(0)
                raise TimeoutError("真实 child 首停等待超时")
            return original_wait(initial)

        self.driver._wait = child_before_parent_exit
        evidence = self.driver.run(self.cross_exec)
        self.assert_clean(evidence)
        self.assertEqual(len(evidence["first_stops"]), 1)
        self.assertTrue(forced_child_first_stop)
        first_stop_event = next(row for row in evidence["events"]
                                if row.get("kind") == "child-first-stop")
        self.assertTrue(first_stop_event["held_without_continue"])
        fork_event = next(row for row in evidence["events"] if row.get("kind") == "fork-parent-stop")
        self.assertLess(first_stop_event["wait_monotonic_ns"], fork_event["wait_monotonic_ns"])
        creation = evidence["creations"][0]
        self.assertIn(creation["entry"]["nr"], (driver_module.SYS_CLONE, driver_module.SYS_FORK))
        self.assertEqual(creation["event_child"], creation["exit_rval"])
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
        print(json.dumps({
            "kind": "verified-creation-syscall",
            "creation_entry": {key: creation["entry"][key] for key in ("nr", "args", "arch")},
            "syscall_stop_count": evidence["syscall_stop_count"],
            "normal_resume_count": evidence["normal_resume_count"],
        }, sort_keys=True, separators=(",", ":")), flush=True)

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
        self.assertFalse(any(row["event"] in (1, 2, 3) for row in evidence["events"]))
        self.assertTrue(all(row.get("signal") == signal.SIGKILL
                            for row in evidence["cleanup"] if row["kind"] == "cleanup-continue"))

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
                self.assertFalse(any(row["event"] in (1, 2, 3) for row in evidence["events"]))
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

    def test_child_process_group_and_session_changes_are_rejected_at_entry(self):
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

                def fixture():
                    self.client.close()
                    accepted, _ = self.listener.accept()
                    self.listener.close()
                    accepted.set_inheritable(True)
                    child = os.fork()
                    if child == 0:
                        os.execv(self.helper, [self.helper, mode, str(marker)])
                    accepted.close()
                    os.waitpid(child, 0)

                self.driver = driver_module.ControlledDriver(time.monotonic() + 2,
                                                             self.receiver, self.expected)
                try:
                    self.driver.run(fixture)
                except driver_module.Failure as error:
                    print(json.dumps({"kind": "group-change-driver-result", "mode": mode,
                                      "error": str(error)}, sort_keys=True,
                                     separators=(",", ":")), flush=True)
                    self.assertRegex(str(error), "未支持的进程组或会话改变")
                else:
                    self.fail("受控 child 的进程组或会话改变未被拒绝")
                evidence = self.driver.evidence
                self.assert_clean(evidence)
                rejected = next(row for row in evidence["events"] if "rejection" in row)
                self.assertEqual(rejected["kind"], "group-change-entry")
                self.assertEqual(rejected["syscall"]["op"], 1)
                self.assertEqual(rejected["syscall"]["arch"], driver_module.AUDIT_ARCH_X86_64)
                self.assertEqual(rejected["syscall"]["nr"], nr)
                self.assertEqual(rejected["syscall"]["args"], [0] * 6)
                first = evidence["first_stops"][0]
                child = first["pid"]
                self.assertEqual(rejected["pid"], child)
                self.assertNotEqual(child, self.driver.master)
                self.assertEqual(len(first["snapshot"]["accepted_matches"]), 1)
                self.assertEqual(rejected["current"]["process"]["pgrp"], self.driver.master)
                self.assertEqual(rejected["current"]["process"]["sid"],
                                 first["snapshot"]["process"]["sid"])
                self.assertLess(evidence["last_normal_resume_monotonic_ns"],
                                rejected["rejected_monotonic_ns"])
                self.assertFalse(marker.exists())
                self.assertTrue(evidence["ledger_poisoned"])
                for pid in (child, self.driver.master):
                    self.assertFalse(Path(f"/proc/{pid}").exists(), f"task {pid} 仍未真正回收")
                    with self.assertRaises(ChildProcessError):
                        os.waitpid(pid, os.WNOHANG)
                self.assertFalse(Path(f"/proc/self/task/{os.getpid()}/children").read_text().strip())
                with self.assertRaises(ChildProcessError):
                    os.waitpid(-1, os.WNOHANG)
                print(json.dumps({
                    "kind": "group-change-entry-rejection", "mode": mode,
                    "pid": child, "master": self.driver.master,
                    "syscall": {key: rejected["syscall"][key] for key in ("nr", "args", "arch")},
                    "pgrp": rejected["current"]["process"]["pgrp"],
                    "sid": rejected["current"]["process"]["sid"],
                    "first_sid": first["snapshot"]["process"]["sid"],
                    "marker_exists": marker.exists(), "ledger_poisoned": evidence["ledger_poisoned"],
                    "remaining_tracees": evidence["remaining_tracees"],
                    "remaining_retired_tasks": evidence["remaining_retired_tasks"],
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
        fork = next(row for row in evidence["events"] if row["event"] == driver_module.FORK)
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
            if driver_module.libc.prctl(driver_module.PR_SET_CHILD_SUBREAPER,
                                       previous.value, 0, 0, 0) != 0:
                raise OSError("不能恢复测试 subreaper 状态")
        self.assertEqual(len(os.listdir("/proc/self/fd")), baseline - 2)


if __name__ == "__main__":
    unittest.main()
