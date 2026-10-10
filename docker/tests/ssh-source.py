#!/usr/bin/env python3
import contextlib
import copy
import importlib.util
import io
import ipaddress
import json
from types import SimpleNamespace
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "padm_ssh_source", ROOT / "docker/lib/ssh-source.py"
)
ssh = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ssh)
BOOT = "b3067192f40d4081b172b6b6c5eb5a32"
NONCE = "a" * 48
USERNAME = "padm-source-" + NONCE
LOCAL = "198.51.100.10"
SOURCE = "192.0.2.20"
PORT = 22220
SPORT = 41008
MASTER_PID = 16
EMITTER_PID = 19
MASTER_EXE = "/usr/sbin/sshd"
EMITTER_EXE = "/usr/lib/openssh/sshd-session"
FRESH_US = 2541600000
EVENT_US = 2541632562


def record(**changes):
    result = {
        "_TRANSPORT": "syslog", "_PID": str(EMITTER_PID), "_UID": "0",
        "_GID": "0", "_COMM": "sshd-session", "_EXE": EMITTER_EXE,
        "SYSLOG_PID": str(EMITTER_PID), "SYSLOG_IDENTIFIER": "sshd-session",
        "_BOOT_ID": BOOT, "__CURSOR": "fresh-cursor",
        "__REALTIME_TIMESTAMP": "1791641976147850",
        "__MONOTONIC_TIMESTAMP": str(EVENT_US),
        "MESSAGE": f"Invalid user {USERNAME} from {SOURCE} port {SPORT}",
    }
    result.update(changes)
    return result


def process(pid, **changes):
    executable = MASTER_EXE if pid == MASTER_PID else EMITTER_EXE
    result = {
        "pid": pid, "ppid": 7 if pid == MASTER_PID else MASTER_PID,
        "starttime": 254155 if pid == MASTER_PID else 254158,
        "uid": (0, 0, 0, 0), "exe": executable,
        "exe_identity": (executable, 1, pid, 40000, 1000, 1000, "b" * 64),
        "exec_generation": (10000, 20000, 30000, 40000, 50000),
        "netns": "net:[4026532999]", "boot_id": BOOT,
    }
    result.update(changes)
    return result


def socket_record(state, local=LOCAL, port=PORT, source=SOURCE, sport=SPORT):
    return {
        "state": state, "local": (local, port),
        "remote": (source, sport) if state == "ESTAB" else ("0.0.0.0", None),
        "owners": ((EMITTER_PID, 7),) if state == "ESTAB" else ((MASTER_PID, 9),),
        "inode": 14338538 if state == "ESTAB" else 14338536,
    }


MASTER = {"socket": socket_record("LISTEN"), "process": process(MASTER_PID)}
ACCEPTED = socket_record("ESTAB")


class SourceContracts(unittest.TestCase):
    def test_exact_arguments_and_same_family(self):
        self.assertEqual(
            ssh.parse_args([LOCAL, str(PORT), SOURCE, NONCE]),
            (ipaddress.ip_address(LOCAL), PORT, ipaddress.ip_address(SOURCE), NONCE),
        )
        for args in (
            [], [LOCAL, str(PORT), SOURCE],
            [LOCAL, str(PORT), SOURCE, NONCE, "extra"],
            [LOCAL, "0", SOURCE, NONCE], [LOCAL, "65536", SOURCE, NONCE],
            [LOCAL, "22.0", SOURCE, NONCE], [LOCAL, "-22", SOURCE, NONCE],
            [LOCAL, str(PORT), "2001:db8::20", NONCE],
            [LOCAL, str(PORT), SOURCE, "a" * 47],
            [LOCAL, str(PORT), SOURCE, "A" * 48],
            [LOCAL, str(PORT), LOCAL, NONCE],
        ):
            with self.subTest(args=args), self.assertRaises(ssh.Failure):
                ssh.parse_args(args)

    def test_address_value_and_unsafe_inputs(self):
        self.assertEqual(str(ssh.parse_address(LOCAL)), LOCAL)
        self.assertEqual(str(ssh.parse_address("2001:0DB8:0:0::10")), "2001:db8::10")
        for value in ("", "--help", "192.0.2.20/32", "192.000.2.20", "0.0.0.0",
                      "127.0.0.1", "::", "::1", "::ffff:192.0.2.20",
                      "fe80::1%eth0", "fe80::1", "224.0.0.1", "ff02::1"):
            with self.subTest(value=value), self.assertRaises(ssh.Failure):
                ssh.parse_address(value)

    def test_strict_json_records(self):
        self.assertEqual(ssh.parse_json_lines(json.dumps(record()) + "\n"), [record()])
        for text in ('{"_PID":"19","_PID":"20"}', "[]", "null", "{", '{"MESSAGE":NaN}'):
            with self.subTest(text=text), self.assertRaises(ssh.Failure):
                ssh.parse_json_lines(text)

    def test_real_ss_two_ports_and_families(self):
        for family, local, remote in (
            (4, LOCAL, SOURCE), (6, "2001:db8::10", "2001:db8::20")
        ):
            endpoint = lambda address, port: (
                f"[{address}]:{port}" if family == 6 else f"{address}:{port}"
            )
            rows = []
            for port in (22220, 22221):
                rows.append(
                    f"ESTAB 0 80 {endpoint(local, port)} {endpoint(remote, SPORT)} "
                    'users:(("sshd-session",pid=19,fd=7)) '
                    "timer:(on,200ms,0) ino:14338538 sk:2001 cgroup:/ <->"
                )
            parsed = ssh.parse_ss("\n".join(rows), family)
            self.assertEqual([row["local"] for row in parsed], [(local, 22220), (local, 22221)])
            self.assertTrue(all(row["remote"] == (remote, SPORT) for row in parsed))
            self.assertTrue(all(row["owners"] == ((EMITTER_PID, 7),) for row in parsed))
            self.assertTrue(all(row["inode"] == 14338538 for row in parsed))

    def test_accepted_socket_requires_exact_endpoint_and_unique_connection(self):
        local = ipaddress.ip_address(LOCAL)
        source = ipaddress.ip_address(SOURCE)
        row = (
            f"ESTAB 0 80 {LOCAL}:{PORT} {SOURCE}:{SPORT} "
            'users:(("sshd-session",pid=19,fd=7)) ino:14338538 sk:2001'
        )
        with patch.object(ssh, "run_command", return_value=row):
            self.assertEqual(ssh.get_accepted(local, PORT, source, SPORT), ACCEPTED)
        for rows in (
            row.replace(f":{PORT}", ":22221"),
            row.replace(LOCAL, "198.51.100.11"),
            row.replace(SOURCE, "192.0.2.21"),
            row.replace(f":{SPORT}", ":41009"),
            row + "\n" + row,
            row.replace("ESTAB", "TIME-WAIT"),
        ):
            with self.subTest(rows=rows), patch.object(ssh, "run_command", return_value=rows), \
                    self.assertRaises(ssh.Failure):
                ssh.get_accepted(local, PORT, source, SPORT)

    def test_listener_rejects_ambiguous_master_and_tracks_inode(self):
        local = ipaddress.ip_address(LOCAL)
        row = (
            f"LISTEN 0 128 {LOCAL}:{PORT} 0.0.0.0:* "
            'users:(("sshd",pid=16,fd=9)) ino:14338536 sk:1002'
        )
        with patch.object(ssh, "run_command", return_value=row), \
                patch.object(ssh, "read_process", return_value=MASTER["process"]), \
                patch.object(ssh, "socket_fd") as held:
            self.assertEqual(ssh.get_listener(local, PORT), MASTER)
            held.assert_called_once_with(MASTER_PID, 9, 14338536)
        for rows in (
            row + "\n" + row.replace(LOCAL, "0.0.0.0"),
            row.replace(f":{PORT}", ":22221"),
            row.replace('pid=16,fd=9))', 'pid=16,fd=9),("sshd",pid=20,fd=9))'),
        ):
            with self.subTest(rows=rows), patch.object(ssh, "run_command", return_value=rows), \
                    self.assertRaises(ssh.Failure):
                ssh.get_listener(local, PORT)

    def test_trusted_nonce_event_and_ipv6_normalization(self):
        event = ssh.event_source(record(), USERNAME, ipaddress.ip_address(SOURCE), BOOT, FRESH_US)
        self.assertEqual(event, {
            "pid": EMITTER_PID, "sport": SPORT, "timestamp": EVENT_US, "exe": EMITTER_EXE,
        })
        ipv6 = "2001:db8::20"
        event = ssh.event_source(
            record(MESSAGE=f"Invalid user {USERNAME} from 2001:0DB8:0:0::20 port {SPORT}"),
            USERNAME, ipaddress.ip_address(ipv6), BOOT, FRESH_US,
        )
        self.assertEqual(event["sport"], SPORT)

    def test_untrusted_or_stale_events_do_not_prove_source(self):
        mutations = (
            {"_TRANSPORT": "journal"}, {"_UID": "1000"}, {"_PID": "0"},
            {"_EXE": "/usr/bin/logger"}, {"_BOOT_ID": "c" * 32},
            {"__MONOTONIC_TIMESTAMP": str(FRESH_US - 1)},
            {"MESSAGE": f"Invalid user old-{NONCE} from {SOURCE} port {SPORT}"},
            {"MESSAGE": f"Invalid user {USERNAME} from 192.0.2.21 port {SPORT}"},
            {"MESSAGE": f"Invalid user {USERNAME} from {SOURCE} port 0"},
            {"MESSAGE": f"Invalid user {USERNAME} from {SOURCE} port 65536"},
            {"MESSAGE": f"prefix Invalid user {USERNAME} from {SOURCE} port {SPORT}"},
            {"MESSAGE": f"Invalid user {USERNAME} from {SOURCE} port {SPORT} suffix"},
            {"_UID": ["0", "1000"]}, {"_PID": ["19", "20"]},
        )
        for changes in mutations:
            with self.subTest(changes=changes):
                try:
                    outcome = ssh.event_source(
                        record(**changes), USERNAME, ipaddress.ip_address(SOURCE), BOOT, FRESH_US
                    )
                except ssh.Failure:
                    continue
                self.assertIsNone(outcome)
        for field in ("_PID", "_UID", "_EXE", "_BOOT_ID", "__MONOTONIC_TIMESTAMP"):
            candidate = record()
            del candidate[field]
            with self.subTest(missing=field), self.assertRaises(ssh.Failure):
                ssh.event_source(candidate, USERNAME, ipaddress.ip_address(SOURCE), BOOT, FRESH_US)

    def verify_event(self, *, accepted=None, emitter=None, next_master=None, fd_error=False):
        event = ssh.event_source(
            record(), USERNAME, ipaddress.ip_address(SOURCE), BOOT, FRESH_US
        )
        emitter = process(EMITTER_PID) if emitter is None else emitter

        def snapshot(pid, *_args):
            if pid == EMITTER_PID:
                return copy.deepcopy(emitter)
            if pid == MASTER_PID:
                return copy.deepcopy(MASTER["process"])
            raise ssh.Failure("测试中的未知进程")

        with contextlib.ExitStack() as stack:
            stack.enter_context(patch.object(ssh, "read_process", side_effect=snapshot))
            stack.enter_context(patch.object(
                ssh, "get_accepted", return_value=copy.deepcopy(
                    ACCEPTED if accepted is None else accepted
                )
            ))
            stack.enter_context(patch.object(
                ssh, "get_listener", return_value=copy.deepcopy(
                    MASTER if next_master is None else next_master
                )
            ))
            stack.enter_context(patch.object(
                ssh, "socket_fd", side_effect=ssh.Failure("连接 inode 已变化") if fd_error else None
            ))
            stack.enter_context(patch.object(ssh.os, "sysconf", return_value=100))
            stack.enter_context(patch.object(ssh.time, "monotonic", return_value=3000))
            return ssh.verify_event(
                event, copy.deepcopy(MASTER), ipaddress.ip_address(LOCAL), PORT,
                ipaddress.ip_address(SOURCE), 5000,
            )

    def test_live_emitter_is_root_child_of_same_master(self):
        emitter, connection = self.verify_event()
        self.assertEqual(emitter["pid"], EMITTER_PID)
        self.assertEqual(connection, ACCEPTED)

    def test_process_reuse_namespace_ancestor_and_fd_drift_are_rejected(self):
        for emitter in (
            process(EMITTER_PID, ppid=999),
            process(EMITTER_PID, netns="net:[4026533000]"),
            process(EMITTER_PID, boot_id="c" * 32),
            process(EMITTER_PID, starttime=EVENT_US // 10000 + 100),
        ):
            with self.subTest(emitter=emitter), self.assertRaises(ssh.Failure):
                self.verify_event(emitter=emitter)
        accepted = copy.deepcopy(ACCEPTED)
        accepted["owners"] = ((20, 7),)
        with self.assertRaises(ssh.Failure):
            self.verify_event(accepted=accepted)
        master = copy.deepcopy(MASTER)
        master["process"]["starttime"] += 1
        with self.assertRaises(ssh.Failure):
            self.verify_event(next_master=master)
        with self.assertRaises(ssh.Failure):
            self.verify_event(fd_error=True)

    def test_proc_snapshot_reads_real_fields_and_rejects_uid_or_pid_reuse(self):
        raw = (
            "19 (sshd-session) S 16 19 19 0 -1 4194560 620 0 2 0 0 0 0 0 20 0 1 0 "
            "254158 17436672 2352 18446744073709551615 101827040346112 101827041050253 "
            "140727676566160 0 0 0 0 4096 8192 1 0 0 17 15 0 0 0 0 0 "
            "101827041400848 101827041416976 101827562893312 140727676567285 "
            "140727676567343 140727676567343 140727676567514 0\n"
        )
        status = "Name:\tsshd-session\nUid:\t0\t0\t0\t0\n"

        def check(*, uid_text=status, final=raw, executable=EMITTER_EXE, namespace=None):
            states = iter((raw, final))

            def read_text(path, *_args, **_kwargs):
                return next(states) if path.name == "stat" else uid_text

            def readlink(path):
                value = str(path)
                if value.endswith("/exe"):
                    return executable
                return namespace if namespace and "/19/" in value else "net:[4026532999]"

            with patch.object(ssh.Path, "read_text", read_text), \
                    patch.object(ssh.Path, "resolve", lambda path, **_kwargs: path), \
                    patch.object(ssh.Path, "stat", return_value=SimpleNamespace(st_dev=1, st_ino=19)), \
                    patch.object(ssh.os, "readlink", side_effect=readlink), \
                    patch.object(ssh, "boot_id", return_value=BOOT), \
                    patch.object(ssh, "safe_executable", return_value=process(19)["exe_identity"]):
                return ssh.read_process(19, ssh.EMITTER_EXES)

        actual = check()
        self.assertEqual((actual["pid"], actual["ppid"], actual["starttime"]), (19, 16, 254158))
        self.assertEqual(actual["uid"], (0, 0, 0, 0))
        for values in (
            {"uid_text": status.replace("0\t0\t0\t0", "0\t1000\t0\t0")},
            {"final": raw.replace("254158", "254159")},
            {"executable": "/usr/bin/logger"},
            {"namespace": "net:[4026533000]"},
        ):
            with self.subTest(values=values), self.assertRaises(ssh.Failure):
                check(**values)

    def test_cursor_boundary_and_overflow_fail_closed(self):
        with patch.object(ssh, "run_command", return_value=json.dumps(record())):
            self.assertEqual(ssh.checkpoint(BOOT), ("fresh-cursor", EVENT_US))
        for row in ({}, record(__CURSOR="invalid cursor"),
                    record(__MONOTONIC_TIMESTAMP=[]), record(_BOOT_ID="c" * 32)):
            with self.subTest(row=row), patch.object(
                ssh, "run_command", return_value=json.dumps(row)
            ), self.assertRaises(ssh.Failure):
                ssh.checkpoint(BOOT)
        with patch.object(
            ssh, "run_command", side_effect=[json.dumps(record()), json.dumps(record())]
        ) as command:
            self.assertEqual(ssh.journal_records(BOOT, "fresh-cursor", 5000), [record()])
            self.assertIn("--cursor=fresh-cursor", command.call_args_list[0].args[0])
            self.assertIn("--after-cursor=fresh-cursor", command.call_args_list[1].args[0])
        for responses in (
            [json.dumps(record(__CURSOR="changed-cursor"))],
            [json.dumps(record()), "\n".join(json.dumps(record()) for _ in range(257))],
        ):
            with self.subTest(responses=len(responses)), patch.object(
                ssh, "run_command", side_effect=responses
            ), self.assertRaises(ssh.Failure):
                ssh.journal_records(BOOT, "fresh-cursor", 5000)

    def test_witness_advances_cursor_and_keeps_proof_ephemeral(self):
        local, source = ipaddress.ip_address(LOCAL), ipaddress.ip_address(SOURCE)
        unrelated = record(MESSAGE="unrelated-event", __CURSOR="next-cursor",
                           __MONOTONIC_TIMESTAMP=str(FRESH_US + 1))
        output = io.StringIO()
        with patch.object(ssh, "verify_addresses"), \
                patch.object(ssh, "get_listener", return_value=copy.deepcopy(MASTER)), \
                patch.object(ssh, "checkpoint", return_value=("initial-cursor", FRESH_US)), \
                patch.object(ssh, "journal_records", side_effect=[[unrelated], [record()]]) as rows, \
                patch.object(ssh, "verify_event", return_value=(process(19), ACCEPTED)) as verified, \
                patch.object(ssh.time, "monotonic", return_value=3000), \
                patch.object(ssh.time, "sleep"), contextlib.redirect_stdout(output):
            result = ssh.witness(local, PORT, source, NONCE)
        self.assertEqual(rows.call_args_list[0].args[1], "initial-cursor")
        self.assertEqual(rows.call_args_list[1].args[1], "next-cursor")
        self.assertGreaterEqual(verified.call_count, 1)
        self.assertTrue(result["source_verified"])
        self.assertFalse(result["jail_ready"])
        self.assertFalse(result["runtime_configuration_verified"])
        challenge = json.loads(output.getvalue().removeprefix("source-challenge="))
        self.assertEqual(challenge["username"], USERNAME)
        self.assertEqual((challenge["target"], challenge["port"], challenge["source"]),
                         (LOCAL, PORT, SOURCE))
        self.assertNotIn("MESSAGE", result)

    def test_witness_requires_same_verified_generation_at_commit(self):
        local, source = ipaddress.ip_address(LOCAL), ipaddress.ip_address(SOURCE)
        first = (process(EMITTER_PID), ACCEPTED)
        changed = (process(EMITTER_PID, exec_generation=(1, 2, 3, 4, 5)), ACCEPTED)
        with patch.object(ssh, "verify_addresses"), \
                patch.object(ssh, "get_listener", return_value=copy.deepcopy(MASTER)), \
                patch.object(ssh, "checkpoint", return_value=("cursor", FRESH_US)), \
                patch.object(ssh, "journal_records", return_value=[record()]), \
                patch.object(ssh, "verify_event", side_effect=[first, changed]), \
                patch.object(ssh.time, "monotonic", return_value=3000), \
                contextlib.redirect_stdout(io.StringIO()), self.assertRaises(ssh.Failure):
            ssh.witness(local, PORT, source, NONCE)

    def test_deadline_prevents_late_proof(self):
        local, source = ipaddress.ip_address(LOCAL), ipaddress.ip_address(SOURCE)
        with patch.object(ssh, "verify_addresses"), \
                patch.object(ssh, "get_listener", return_value=MASTER), \
                patch.object(ssh, "checkpoint", return_value=("cursor", FRESH_US)), \
                patch.object(ssh.time, "monotonic", side_effect=[3000, 3031]), \
                patch.object(ssh, "journal_records") as rows, \
                contextlib.redirect_stdout(io.StringIO()), self.assertRaises(ssh.Failure):
            ssh.witness(local, PORT, source, NONCE)
        rows.assert_not_called()
        with patch.object(ssh.time, "monotonic", return_value=10), self.assertRaises(ssh.Failure):
            ssh.run_command(["unused-read-command"], deadline=9)

    def test_host_target_and_external_source_address_contract(self):
        local, source = ipaddress.ip_address(LOCAL), ipaddress.ip_address(SOURCE)
        network = {
            "Containers": {}, "Driver": "bridge",
            "IPAM": {"Config": [{"Subnet": "172.30.0.0/16", "Gateway": "172.30.0.1"}]},
        }
        addresses = [{"addr_info": [{"local": LOCAL}, {"local": "127.0.0.1"}]}]
        responses = [json.dumps(addresses), "a" * 64, json.dumps([network])]
        with patch.object(ssh, "run_command", side_effect=responses):
            ssh.verify_addresses(local, source)
        internal = copy.deepcopy(network)
        internal["Containers"] = {"container": {"IPv4Address": SOURCE + "/24"}}
        for fixture in (
            [json.dumps([{"addr_info": [{"local": SOURCE}]}])],
            [json.dumps([{"addr_info": [{"local": LOCAL}, {"local": SOURCE}]}])],
            [json.dumps(addresses), "a" * 64, json.dumps([internal])],
            [json.dumps(addresses), "a" * 64, json.dumps([{
                **network, "IPAM": {"Config": [{"Subnet": "192.0.2.0/24"}]},
            }])],
        ):
            with self.subTest(fixture=fixture), patch.object(
                ssh, "run_command", side_effect=fixture
            ), self.assertRaises(ssh.Failure):
                ssh.verify_addresses(local, source)


if __name__ == "__main__":
    unittest.main()
