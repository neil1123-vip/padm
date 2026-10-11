#!/usr/bin/env python3
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "padm_ssh_collector", ROOT / "docker/lib/ssh-collector.py"
)
collector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(collector)
UNIT = "padm-sshd.service"
BOOT = "a" * 32
INVOCATION = "b" * 32
GROUP = "/system.slice/" + UNIT
TARGET = "198.51.100.10"
SOURCE = "192.0.2.20"
SNAPSHOT = {
    "unit": {
        "unit": UNIT, "main_pid": 16, "invocation_id": INVOCATION,
        "control_group": GROUP, "exec_start_mono": 90,
    },
    "master": {"process": {"boot_id": BOOT}},
}
RECORD = {
    "_BOOT_ID": BOOT, "_SYSTEMD_UNIT": UNIT, "_SYSTEMD_INVOCATION_ID": INVOCATION,
    "_SYSTEMD_CGROUP": GROUP, "_TRANSPORT": "syslog", "_UID": "0",
    "_PID": "19", "_EXE": "/usr/sbin/sshd", "__CURSOR": "failed-1",
    "__MONOTONIC_TIMESTAMP": "101",
    "MESSAGE": f"Failed password for invalid user unknown from {SOURCE} port 41008 ssh2",
}


class CollectorContracts(unittest.TestCase):
    def new_collector(self):
        with patch.object(collector.journal, "unit_snapshot", return_value=SNAPSHOT), \
                patch.object(collector.journal, "cgroup_pids", return_value=(16,)), \
                patch.object(collector.ssh, "checkpoint", return_value=("initial", 100)):
            result = collector.Collector(UNIT, TARGET, 22220)
        return result

    def poll(self, instance, rows, final=None):
        with patch.object(collector.journal, "unit_snapshot", side_effect=[
                SNAPSHOT, SNAPSHOT if final is None else final]), \
                patch.object(collector.ssh, "journal_records", return_value=rows):
            return instance.poll()

    def test_distinct_cursors_at_same_mono_are_counted_and_replays_fail(self):
        instance = self.new_collector()
        rows = [RECORD, {**RECORD, "__CURSOR": "failed-2"}]
        self.assertEqual(self.poll(instance, rows), [{
            "source": SOURCE, "source_port": 41008, "cursor": row["__CURSOR"], "mono": 101,
        } for row in rows])
        self.assertEqual(instance.cursor, "failed-2")
        for row in ({**RECORD, "__CURSOR": "failed-1"},
                    {**RECORD, "__CURSOR": "older", "__MONOTONIC_TIMESTAMP": "100"}):
            with self.subTest(row=row), self.assertRaises(collector.Failure):
                self.poll(instance, [row])

    def test_startup_rejects_old_connection_children_before_and_after_checkpoint(self):
        for members in (((16, 19),), ((16,), (16, 19))):
            with self.subTest(members=members), \
                    patch.object(collector.journal, "unit_snapshot", return_value=SNAPSHOT), \
                    patch.object(collector.journal, "cgroup_pids", side_effect=members), \
                    patch.object(collector.ssh, "checkpoint", return_value=("initial", 100)), \
                    self.assertRaisesRegex(collector.Failure, "专用 service"):
                collector.Collector(UNIT, TARGET, 22220)

    def test_untrusted_identity_and_unit_drift_fail_without_committing_batch(self):
        changes = (
            {"_SYSTEMD_INVOCATION_ID": "c" * 32}, {"_SYSTEMD_CGROUP": GROUP + "/other"},
            {"_BOOT_ID": "c" * 32}, {"_TRANSPORT": "stdout"}, {"_UID": "1000"},
            {"_EXE": "/tmp/sshd"}, {"_PID": "0"}, {"__CURSOR": "bad\x00cursor"},
        )
        for change in changes:
            instance = self.new_collector()
            with self.subTest(change=change), self.assertRaises(collector.Failure):
                self.poll(instance, [{**RECORD, **change}])
            self.assertEqual((instance.cursor, instance.mono), ("initial", 100))
        instance = self.new_collector()
        changed = copy.deepcopy(SNAPSHOT)
        changed["unit"]["invocation_id"] = "c" * 32
        with self.assertRaises(collector.Failure):
            self.poll(instance, [RECORD], final=changed)
        self.assertEqual((instance.cursor, instance.mono), ("initial", 100))

    def test_unknown_or_injected_messages_never_become_sources(self):
        messages = (
            f"Failed password for user from {SOURCE} port 41008 ssh2\nsource=192.0.2.30",
            f"prefix Failed password for user from {SOURCE} port 41008 ssh2",
            f"Failed password for user from {SOURCE};touch/tmp/pwn port 41008 ssh2",
            f"Failed password for bad user from {SOURCE} port 41008 ssh2",
            f"Failed password for user from {SOURCE} port 65536 ssh2",
            f"Failed publickey for user from {SOURCE} port 41008 ssh2",
            f"Invalid user user from {SOURCE} port 41008",
            f"Accepted password for user from {SOURCE} port 41008 ssh2",
        )
        for message in messages:
            with self.subTest(message=message):
                instance = self.new_collector()
                self.assertEqual(self.poll(instance, [{**RECORD, "MESSAGE": message}]), [])
                self.assertEqual(instance.cursor, RECORD["__CURSOR"])
        instance = self.new_collector()
        self.assertEqual(self.poll(instance, [{**RECORD, "_SYSTEMD_UNIT": "other.service"}]), [])

    def test_cli_signals_ready_before_fixed_output_and_stops_normally(self):
        events = []

        def ready():
            events.append("ready")

        def poll():
            events.append("poll")
            return [{"source": SOURCE, "source_port": 41008, "cursor": "failed", "mono": 101}]

        with patch.object(collector.sys, "platform", "linux"), \
                patch.object(collector.os, "geteuid", return_value=0), \
                patch.object(collector.shutil, "which", return_value="/usr/bin/tool"), \
                patch.object(collector, "Collector") as implementation, \
                patch.object(collector, "Guard") as guard, \
                patch.object(collector, "notify_ready", side_effect=ready), \
                patch.object(collector.signal, "signal"), \
                patch.object(collector.time, "sleep", side_effect=KeyboardInterrupt), \
                patch.object(collector.sys, "stdout", new_callable=io.StringIO) as output:
            implementation.return_value.poll.side_effect = poll
            self.assertEqual(collector.main([UNIT, TARGET, "22220"]), 0)
        implementation.assert_called_once_with(UNIT, TARGET, "22220")
        guard.return_value.__enter__.return_value.write.assert_called_once_with(
            implementation.return_value
        )
        self.assertEqual(events, ["poll", "ready"])
        self.assertRegex(output.getvalue(),
                         rf"^[0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}} [0-9]{{2}}:[0-9]{{2}}:"
                         rf"[0-9]{{2}} padm-ssh source={SOURCE}\n$")

    def test_invalid_or_noncanonical_target_rejected_before_host_read(self):
        for target, port in ((TARGET, 0), (TARGET, "022220"), ("0.0.0.0", 22),
                             ("2001:db8::0010", 22)):
            with self.subTest(target=target, port=port), \
                    patch.object(collector.journal, "unit_snapshot") as snapshot, \
                    self.assertRaises(collector.Failure):
                collector.Collector(UNIT, target, port)
            snapshot.assert_not_called()

    def test_guard_is_private_atomic_and_only_removes_its_own_token(self):
        token = "c" * 32
        with tempfile.TemporaryDirectory(prefix="padm-ssh-collector-", dir="/root") as directory:
            path = Path(directory) / "guard.json"
            instance = self.new_collector()
            with collector.Guard(directory, token) as guard:
                guard.write(instance)
                result = json.loads(path.read_text())
                self.assertEqual(set(result), {
                    "schema", "token", "unit", "target", "port", "boot",
                    "invocation", "monotonic_ns",
                })
                self.assertEqual((result["token"], result["boot"], result["invocation"]),
                                 (token, BOOT, INVOCATION))
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
                self.assertGreater(result["monotonic_ns"], 0)
                with self.assertRaises(OSError):
                    collector.Guard(directory, "d" * 32)
            self.assertFalse(path.exists())
            with collector.Guard(directory, token) as guard:
                guard.write(instance)
                original = path.read_bytes()
                guard.token = "d" * 32
                with self.assertRaises(collector.Failure):
                    guard.write(instance)
                self.assertEqual(path.read_bytes(), original)
                guard.token = token
            self.assertFalse(path.exists())
            os.chmod(directory, 0o755)
            with self.assertRaises(collector.Failure):
                collector.Guard(directory, token)


if __name__ == "__main__":
    unittest.main()
