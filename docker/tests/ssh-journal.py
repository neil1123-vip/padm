#!/usr/bin/env python3
import copy
import importlib.util
import ipaddress
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "padm_ssh_journal", ROOT / "docker/lib/ssh-journal.py"
)
journal = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(journal)
ssh = journal.ssh
UNIT = "padm-sshd.service"
GROUP = "/system.slice/" + UNIT
INVOCATION = "a" * 32
BOOT = "b" * 32
LOCAL = ipaddress.ip_address("198.51.100.10")
SOURCE = ipaddress.ip_address("192.0.2.20")
PORT = 22220
NONCE = "c" * 48
NETNS = "net:[4026532999]"


def unit_text(**changes):
    result = {
        "Id": UNIT, "LoadState": "loaded", "ActiveState": "active", "SubState": "running",
        "MainPID": "16", "InvocationID": INVOCATION, "ControlGroup": GROUP,
        "ExecMainStartTimestampMonotonic": "2541550000", "TriggeredBy": "",
    }
    result.update(changes)
    return "\n".join(f"{key}={value}" for key, value in result.items()) + "\n"


UNIT_STATE = journal.parse_unit(unit_text(), UNIT)
MASTER = {
    "pid": 16, "ppid": 1, "starttime": 254155, "uid": (0, 0, 0, 0),
    "exe": "/usr/sbin/sshd", "exe_identity": ("/usr/sbin/sshd", 1, 16, 40000, 1, 1, "d" * 64),
    "exec_generation": (1, 2, 3, 4, 5), "netns": NETNS, "boot_id": BOOT,
}
LISTENER = {
    "state": "LISTEN", "local": (str(LOCAL), PORT), "remote": ("0.0.0.0", None),
    "owners": ((16, 9),), "inode": 14338536,
}
SNAPSHOT = {"unit": UNIT_STATE, "master": {"process": MASTER, "socket": LISTENER}}
EMITTER = {**MASTER, "pid": 19, "ppid": 16, "exe": "/usr/lib/openssh/sshd-session"}
ACCEPTED = {
    "state": "ESTAB", "local": (str(LOCAL), PORT), "remote": (str(SOURCE), 41008),
    "owners": ((19, 7),), "inode": 14338538,
}
RECORD = {
    "_SYSTEMD_UNIT": UNIT, "_SYSTEMD_INVOCATION_ID": INVOCATION, "_SYSTEMD_CGROUP": GROUP,
    "_BOOT_ID": BOOT, "_TRANSPORT": "syslog", "_UID": "0", "_PID": "19",
    "_EXE": EMITTER["exe"], "__MONOTONIC_TIMESTAMP": "2541632562",
    "__CURSOR": "event-cursor",
    "MESSAGE": f"Invalid user padm-source-{NONCE} from {SOURCE} port 41008",
}
EVIDENCE = {
    "master": SNAPSHOT["master"], "record": RECORD,
    "event": {"pid": 19, "sport": 41008, "timestamp": 2541632562, "exe": EMITTER["exe"]},
    "emitter": EMITTER, "accepted": ACCEPTED, "cursor": "start-cursor",
    "fresh_us": 2541600000, "deadline": 5000,
}


class UnitContracts(unittest.TestCase):
    def test_cli_preserves_unit_scope_and_failure_status(self):
        args = [UNIT, str(LOCAL), str(PORT), str(SOURCE), NONCE]
        result = {
            "scope": "ssh-unit-source-only", "source_verified": True,
            "unit_verified": True, "runtime_configuration_verified": False,
            "jail_ready": False,
        }
        with patch.object(journal.os, "geteuid", return_value=0), \
                patch.object(journal.sys, "platform", "linux"), \
                patch.object(journal.shutil, "which", return_value="/usr/bin/tool"), \
                patch.object(journal, "unit_witness", return_value=result) as witness, \
                patch.object(journal.sys, "stdout", new_callable=io.StringIO) as output:
            self.assertEqual(journal.main(args), 0)
            witness.assert_called_once_with(UNIT, LOCAL, PORT, SOURCE, NONCE)
            self.assertEqual(json.loads(output.getvalue().removeprefix("source-verified=")), result)
        for error, status in ((journal.Failure("拒绝", 10), 10),
                              (journal.Failure("拒绝", 15), 15),
                              (KeyboardInterrupt(), 15), (OSError("private-stderr"), 15)):
            with self.subTest(error=error), \
                    patch.object(journal.os, "geteuid", return_value=0), \
                    patch.object(journal.sys, "platform", "linux"), \
                    patch.object(journal.shutil, "which", return_value="/usr/bin/tool"), \
                    patch.object(journal, "unit_witness", side_effect=error), \
                    patch.object(journal.sys, "stdout", new_callable=io.StringIO) as output, \
                    patch.object(journal.sys, "stderr", new_callable=io.StringIO) as stderr:
                self.assertEqual(journal.main(args), status)
                self.assertEqual(output.getvalue(), "")
                self.assertNotIn("private-stderr", stderr.getvalue())

    def test_cli_rejects_invalid_input_and_missing_host_tools_before_witness(self):
        args = [UNIT, str(LOCAL), str(PORT), str(SOURCE), NONCE]
        invalid = (args[:-1], args + ["extra"], ["../sshd.service", *args[1:]],
                   [UNIT, str(LOCAL), "0", str(SOURCE), NONCE])
        with patch.object(journal, "unit_witness") as witness, \
                patch.object(journal.sys, "stderr", new_callable=io.StringIO):
            for values in invalid:
                self.assertEqual(journal.main(values), 2)
            witness.assert_not_called()
        for tool in ("ip", "ss", "docker", "journalctl", "systemctl"):
            with self.subTest(tool=tool), \
                    patch.object(journal.os, "geteuid", return_value=0), \
                    patch.object(journal.sys, "platform", "linux"), \
                    patch.object(journal.shutil, "which",
                                 side_effect=lambda name: None if name == tool else "/usr/bin/tool"), \
                    patch.object(journal, "unit_witness") as witness, \
                    patch.object(journal.sys, "stderr", new_callable=io.StringIO):
                self.assertEqual(journal.main(args), 10)
                witness.assert_not_called()

    def test_strict_systemctl_fields_and_command(self):
        self.assertEqual(journal.parse_unit(unit_text(), UNIT), UNIT_STATE)
        with patch.object(ssh, "run_command", return_value=unit_text()) as command:
            self.assertEqual(journal.read_unit(UNIT, 5000), UNIT_STATE)
        args = command.call_args.args[0]
        self.assertEqual(args[-2:], ["--", UNIT])
        self.assertNotIn("--value", args)
        self.assertIn("--property=" + ",".join(journal.UNIT_PROPERTIES), args)

    def test_unit_requires_unambiguous_current_generation(self):
        candidates = [
            unit_text() + "MainPID=16\n", unit_text().replace("TriggeredBy=\n", ""),
            unit_text() + "Unknown=value\n", unit_text() + "\n", "malformed\n",
        ]
        candidates.extend(unit_text(**changes) for changes in (
            {"Id": "sshd.service"}, {"LoadState": "not-found"}, {"ActiveState": "inactive"},
            {"SubState": "exited"}, {"TriggeredBy": "sshd.socket"}, {"MainPID": "0"},
            {"MainPID": "16 17"}, {"MainPID": "2147483648"}, {"InvocationID": ""},
            {"InvocationID": "0" * 32}, {"InvocationID": "A" * 32},
            {"ExecMainStartTimestampMonotonic": "0"}, {"ExecMainStartTimestampMonotonic": "x"},
            {"ControlGroup": "/"}, {"ControlGroup": "../escape"}, {"ControlGroup": GROUP + "/"},
        ))
        for text in candidates:
            with self.subTest(text=text), self.assertRaises(journal.Failure):
                journal.parse_unit(text, UNIT)
        for name in ("--help", "sshd.socket", "x\n.service", "", "x service.service"):
            with self.subTest(name=name), self.assertRaises(journal.Failure):
                journal.unit_name(name)

    def test_cgroup_subtree_is_complete_bounded_and_direct(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "cgroup.controllers").write_text("cpu memory\n")
            unit = root / GROUP.lstrip("/")
            unit.mkdir(parents=True)
            (unit / "cgroup.procs").write_text("16\n19\n")
            child = unit / "auth"
            child.mkdir()
            (child / "cgroup.procs").write_text("23\n")
            with patch.object(journal, "CGROUP_ROOT", root):
                self.assertEqual(journal.cgroup_pids(GROUP), (16, 19, 23))
                for text in ("16\n", "0\n", "23\n23\n", "bad\n"):
                    (child / "cgroup.procs").write_text(text)
                    with self.subTest(text=text), self.assertRaises(journal.Failure):
                        journal.cgroup_pids(GROUP)
                (child / "cgroup.procs").write_text("23\n")
                with patch.object(journal, "MAX_PIDS", 2), self.assertRaises(journal.Failure):
                    journal.cgroup_pids(GROUP)
                with patch.object(journal, "MAX_CGROUPS", 1), self.assertRaises(journal.Failure):
                    journal.cgroup_pids(GROUP)
                (unit / "indirect").symlink_to(child, target_is_directory=True)
                with self.assertRaises(journal.Failure):
                    journal.cgroup_pids(GROUP)

    def test_low_privilege_members_only_require_stable_pid_cgroup_and_netns(self):
        raw = "23 (sshd-auth) S " + " ".join(["0"] * 18 + ["254158"])

        def read_text(path, *_args, **_kwargs):
            return raw if path.name == "stat" else "0::" + GROUP + "/auth\n"

        with patch.object(journal.Path, "read_text", read_text), \
                patch.object(journal.os, "readlink", return_value=NETNS), \
                patch.object(ssh, "read_process") as root_process:
            self.assertEqual(journal.member_snapshot(23, GROUP, NETNS),
                             (23, 254158, NETNS, GROUP + "/auth"))
        root_process.assert_not_called()
        for namespace, group in (("net:[different]", GROUP), (NETNS, GROUP + "-other")):
            with patch.object(journal.Path, "read_text", read_text), \
                    patch.object(journal.os, "readlink", return_value=namespace), \
                    patch.object(journal, "process_cgroup", return_value=group), \
                    self.assertRaises(journal.Failure):
                journal.member_snapshot(23, GROUP, NETNS)
        with patch.object(journal.Path, "read_text", read_text), \
                patch.object(journal.os, "readlink", side_effect=[NETNS, "net:[changed]"]), \
                self.assertRaises(journal.Failure):
            journal.member_snapshot(23, GROUP, NETNS)

    def listener_check(self, rows, pids=(16, 19, 23), final_pids=None):
        with patch.object(journal, "cgroup_pids", side_effect=[
                pids, pids if final_pids is None else final_pids]), \
                patch.object(journal, "member_snapshot", side_effect=lambda pid, *_: (
                    pid, 254155, NETNS, GROUP)), \
                patch.object(ssh, "run_command", side_effect=["family4", "family6"]) as commands, \
                patch.object(ssh, "parse_ss", side_effect=rows), \
                patch.object(ssh, "socket_fd") as held:
            result = journal.unit_listener(UNIT_STATE, MASTER, LOCAL, PORT)
        self.assertEqual([call.args[0][-1] for call in commands.call_args_list], ["-4", "-6"])
        held.assert_called_once_with(16, 9, LISTENER["inode"])
        return result

    def test_complete_listener_uses_both_families_and_all_unit_members(self):
        unrelated = {**LISTENER, "local": ("192.0.2.100", 80), "owners": ((90, 4),)}
        self.assertEqual(self.listener_check([[LISTENER, unrelated], []]), LISTENER)
        extra = {**LISTENER, "local": ("2001:db8::10", PORT), "owners": ((23, 5),)}
        failures = (
            [[{**LISTENER, "local": ("0.0.0.0", PORT)}], []],
            [[LISTENER, {**LISTENER, "local": (str(LOCAL), PORT + 1)}], []],
            [[LISTENER], [extra]],
            [[{**LISTENER, "owners": ((16, 9), (20, 7))}], []],
            [[{**LISTENER, "owners": ()}], []],
            [[LISTENER, {**unrelated, "owners": ()}], []],
            [[{**LISTENER, "owners": ((19, 9),)}], []],
            [[], []],
        )
        for rows in failures:
            with self.subTest(rows=rows), self.assertRaises(journal.Failure):
                self.listener_check(rows)
        with self.assertRaises(journal.Failure):
            self.listener_check([[LISTENER], []], final_pids=(16, 19))
        with self.assertRaises(journal.Failure):
            self.listener_check([[LISTENER], []], pids=(19, 23))

    def test_snapshot_rechecks_unit_and_master_generation(self):
        with patch.object(journal, "read_unit", return_value=UNIT_STATE), \
                patch.object(ssh, "read_process", return_value=MASTER), \
                patch.object(journal, "unit_listener", return_value=LISTENER):
            self.assertEqual(journal.unit_snapshot(UNIT, LOCAL, PORT), SNAPSHOT)
        for changed_unit, changed_master in (
            ({**UNIT_STATE, "invocation_id": "d" * 32}, MASTER),
            (UNIT_STATE, {**MASTER, "starttime": MASTER["starttime"] + 1}),
        ):
            with patch.object(journal, "read_unit", side_effect=[UNIT_STATE, changed_unit]), \
                    patch.object(ssh, "read_process", side_effect=[MASTER, changed_master]), \
                    patch.object(journal, "unit_listener", return_value=LISTENER), \
                    self.assertRaises(journal.Failure):
                journal.unit_snapshot(UNIT, LOCAL, PORT)

    def test_fresh_record_requires_trusted_single_unit_fields(self):
        self.assertEqual(journal.verify_unit_record(RECORD, SNAPSHOT, EVIDENCE),
                         {"cursor": "event-cursor", "mono": 2541632562})
        for key in ("_SYSTEMD_UNIT", "_SYSTEMD_INVOCATION_ID", "_SYSTEMD_CGROUP",
                    "_BOOT_ID", "_TRANSPORT", "_UID", "_PID", "_EXE"):
            for value in (None, "", [RECORD[key]], "wrong"):
                candidate = {**RECORD, key: value}
                with self.subTest(key=key, value=value), self.assertRaises(journal.Failure):
                    journal.verify_unit_record(candidate, SNAPSHOT, EVIDENCE)
        for changes in (
            {"__CURSOR": "start-cursor"}, {"__CURSOR": "with space"},
            {"__CURSOR": "\x00"}, {"__CURSOR": []}, {"__MONOTONIC_TIMESTAMP": "0"},
            {"__MONOTONIC_TIMESTAMP": []}, {"__MONOTONIC_TIMESTAMP": "2541632563"},
        ):
            with self.subTest(changes=changes), self.assertRaises(journal.Failure):
                journal.verify_unit_record({**RECORD, **changes}, SNAPSHOT, EVIDENCE)

    def witness_check(self, *, evidence=None, after=None, final=None, group=GROUP):
        evidence = copy.deepcopy(EVIDENCE if evidence is None else evidence)
        with patch.object(journal, "unit_snapshot", side_effect=[
                copy.deepcopy(SNAPSHOT), copy.deepcopy(SNAPSHOT if after is None else after)]), \
                patch.object(ssh, "witness_evidence", return_value=evidence) as fresh, \
                patch.object(ssh, "verify_event", return_value=(
                    (EMITTER, ACCEPTED) if final is None else final)) as live, \
                patch.object(journal, "process_cgroup", return_value=group), \
                patch.object(journal.time, "monotonic", return_value=3000):
            result = journal.unit_witness(UNIT, LOCAL, PORT, SOURCE, NONCE)
        fresh.assert_called_once_with(LOCAL, PORT, SOURCE, NONCE)
        self.assertEqual(live.call_args.args[-1], 5000)
        return result

    def test_unit_witness_keeps_active_socket_and_source_only_flags(self):
        result = self.witness_check()
        self.assertEqual(result["scope"], "ssh-unit-source-only")
        self.assertTrue(result["source_verified"])
        self.assertTrue(result["unit_verified"])
        self.assertFalse(result["runtime_configuration_verified"])
        self.assertFalse(result["jail_ready"])
        self.assertEqual(result["snapshot"], SNAPSHOT)
        self.assertNotIn("MESSAGE", result)
        self.assertNotIn("nonce", result)
        self.assertNotIn("accepted", result)

    def test_unit_witness_rejects_change_or_missing_live_connection(self):
        wrong_master = copy.deepcopy(EVIDENCE)
        wrong_master["master"]["process"]["pid"] = 17
        with self.assertRaises(journal.Failure):
            self.witness_check(evidence=wrong_master)
        changed = copy.deepcopy(SNAPSHOT)
        changed["unit"]["invocation_id"] = "d" * 32
        with self.assertRaises(journal.Failure):
            self.witness_check(after=changed)
        with self.assertRaises(journal.Failure):
            self.witness_check(final=(EMITTER, {**ACCEPTED, "inode": 1}))
        child = {**EMITTER, "pid": 23, "ppid": 19, "uid": (996,) * 4,
                 "exe": "/usr/lib/openssh/sshd-auth"}
        shared = copy.deepcopy(EVIDENCE)
        shared["accepted"] = {**ACCEPTED, "owners": ((19, 7), (23, 5)), "privsep": (child,)}
        self.assertEqual(self.witness_check(evidence=shared, final=(
            EMITTER, shared["accepted"]))["scope"], "ssh-unit-source-only")
        changed = {**shared["accepted"], "privsep": ({**child, "starttime": 254159},)}
        with self.assertRaises(journal.Failure):
            self.witness_check(evidence=shared, final=(EMITTER, changed))
        with self.assertRaises(journal.Failure):
            self.witness_check(group=GROUP + "/moved")
        with patch.object(journal, "unit_snapshot", side_effect=PermissionError), \
                self.assertRaises(journal.Failure):
            journal.unit_witness(UNIT, LOCAL, PORT, SOURCE, NONCE)


if __name__ == "__main__":
    unittest.main()
