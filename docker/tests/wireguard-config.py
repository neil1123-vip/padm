#!/usr/bin/env python3
"""单 Peer WireGuard 私密准备的 Linux root 回归。"""

import base64
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


HELPER = Path(__file__).resolve().parents[1] / "lib/wireguard-config.py"
SPEC = importlib.util.spec_from_file_location("wireguard_config", HELPER)
wg = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(wg)
PRIVATE = base64.b64encode(bytes(range(32))).decode()
PUBLIC = base64.b64encode(bytes(range(32, 64))).decode()
PEER = base64.b64encode(bytes(range(64, 96))).decode()
ROTATED_PRIVATE = base64.b64encode(bytes(range(96, 128))).decode()
ROTATED_PUBLIC = base64.b64encode(bytes(range(128, 160))).decode()
ROTATED_PEER = base64.b64encode(bytes(range(160, 192))).decode()


class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="padm-wireguard-config-", dir="/root")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.directory = self.root / "prepared"
        self.private = self.root / "private-input"
        self.public = self.root / "public-input"
        for path, value in ((self.private, PRIVATE), (self.public, PUBLIC)):
            path.write_text(value + "\n")
            path.chmod(0o600)

    def prepare(self):
        return wg.prepare(str(self.directory), "10.90.0.1", 51820,
                          str(self.private), str(self.public))

    def peer(self, address="10.90.0.2", public=PEER, endpoint=None):
        return wg.peer(str(self.directory), address, public, endpoint)

    def snapshot(self):
        return {path.relative_to(self.root).as_posix():
                (path.lstat().st_mode, path.read_bytes() if path.is_file() else None)
                for path in self.root.rglob("*")}

    def rejected(self, function, *arguments, **keywords):
        with self.assertRaises((OSError, ValueError, TypeError, UnicodeError)):
            function(*arguments, **keywords)

    def migrate(self, destination=None, **changes):
        return wg.migrate(str(self.directory), str(destination or self.root / "candidate"), **changes)

    def test_prepare_and_peer_keep_private_modes_and_fixed_configuration(self):
        identity = self.prepare()
        self.assertEqual(set(path.name for path in self.directory.iterdir()),
                         {"identity.json", "private.key"})
        self.assertEqual(identity, {"schema_version": 1, "address": "10.90.0.1",
                                   "listen_port": 51820, "public_key": PUBLIC, "configured": False})
        self.assertEqual(wg.status(str(self.directory)), identity)
        self.assertTrue(self.peer(endpoint="198.18.0.2:51821")["configured"])
        self.assertEqual((self.directory / "wg-padm.conf").read_text(),
                         "[Interface]\nAddress = 10.90.0.1/32\nListenPort = 51820\n"
                         "PrivateKey = " + PRIVATE + "\n\n[Peer]\nPublicKey = " + PEER
                         + "\nAllowedIPs = 10.90.0.2/32\nEndpoint = 198.18.0.2:51821\n"
                         "PersistentKeepalive = 25\n")
        self.assertEqual(self.directory.stat().st_mode & 0o777, 0o700)
        for path in self.directory.iterdir():
            self.assertEqual(path.stat().st_uid, 0)
            self.assertEqual(path.stat().st_nlink, 1)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertTrue(wg.status(str(self.directory))["configured"])

    def test_peer_without_endpoint_and_duplicate_calls_do_not_overwrite(self):
        self.prepare()
        self.peer()
        before = self.snapshot()
        self.rejected(self.prepare)
        self.rejected(self.peer)
        self.assertEqual(self.snapshot(), before)
        self.assertNotIn("Endpoint", (self.directory / "wg-padm.conf").read_text())
        self.assertNotIn("PersistentKeepalive", (self.directory / "wg-padm.conf").read_text())

    def test_existing_empty_directory_is_not_replaced(self):
        self.directory.mkdir(mode=0o750)
        before = self.directory.stat().st_ino
        self.assertEqual(wg.status(str(self.directory)),
                         {"state": "absent", "configured": False})
        self.rejected(self.prepare)
        self.assertEqual(self.directory.stat().st_ino, before)
        self.assertEqual(self.directory.stat().st_mode & 0o777, 0o750)
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_absent_and_cli_status_never_emit_private_key(self):
        self.assertEqual(wg.status(str(self.directory)),
                         {"state": "absent", "configured": False})
        self.prepare()
        for configured in (False, True):
            if configured:
                self.peer()
            result = subprocess.run([sys.executable, "-B", str(HELPER), "status",
                                     "--directory", str(self.directory)], capture_output=True, check=True)
            self.assertEqual(json.loads(result.stdout)["configured"], configured)
            self.assertNotIn(PRIVATE.encode(), result.stdout + result.stderr)
            self.assertNotIn(b"PrivateKey", result.stdout + result.stderr)

    def test_only_canonical_rfc1918_addresses_and_valid_ports(self):
        for value in ("10.0.0.1", "172.16.0.1", "172.31.255.254", "192.168.255.254"):
            self.assertEqual(wg.address(value), value)
        for value in ("127.0.0.1", "169.254.0.1", "172.32.0.1", "192.0.2.1",
                      "224.0.0.1", "::1", "10.0.0.1/32", "010.0.0.1", "10.0.0.1\n"):
            self.rejected(wg.address, value)
        for value in (0, 1023, 65536, True, "51820"):
            self.rejected(wg.port, value)

    def test_invalid_peer_values_do_not_change_prepared_state(self):
        self.prepare()
        before = self.snapshot()
        for remote, public, target in (
            ("10.90.0.1", PEER, None), ("10.90.0.2", PUBLIC, None),
            ("203.0.113.1", PEER, None), ("10.90.0.2\nPostUp = evil", PEER, None),
            ("10.90.0.2", PEER + "\n", None), ("10.90.0.2", PEER[:-2] + "B=", None),
            ("10.90.0.2", PEER, "127.0.0.1:51820"),
            ("10.90.0.2", PEER, "224.0.0.1:51820"),
            ("10.90.0.2", PEER, "0.0.0.0:51820"),
            ("10.90.0.2", PEER, "0.1.2.3:51820"),
            ("10.90.0.2", PEER, "169.254.1.1:51820"),
            ("10.90.0.2", PEER, "240.0.0.1:51820"),
            ("10.90.0.2", PEER, "255.255.255.255:51820"),
            ("10.90.0.2", PEER, "host.example:51820"),
            ("10.90.0.2", PEER, "198.18.0.2:80"),
            ("10.90.0.2", PEER, "198.18.0.2:051820"),
            ("10.90.0.2", PEER, "198.18.0.2:51820\nPostUp = evil"),
        ):
            with self.subTest(remote=remote, target=target):
                self.rejected(self.peer, remote, public, target)
                self.assertEqual(self.snapshot(), before)

    def test_invalid_input_key_and_wide_file_permissions_are_rejected(self):
        for value in (PRIVATE + "\n\n", PRIVATE + "\0", PRIVATE[:-1], "x" * 1000,
                      "_" * 43 + "=", PRIVATE[:-2] + "B="):
            self.private.write_text(value)
            self.rejected(self.prepare)
            self.assertFalse(self.directory.exists())
        self.private.write_text(PRIVATE + "\n")
        self.private.chmod(0o640)
        self.rejected(self.prepare)
        self.assertFalse(self.directory.exists())

    def test_symlink_hardlink_and_writable_ancestor_are_rejected(self):
        alias = self.root / "alias"
        alias.symlink_to(self.private)
        self.rejected(wg.prepare, str(self.directory), "10.90.0.1", 51820,
                      str(alias), str(self.public))
        alias.unlink()
        os.link(self.private, alias)
        self.rejected(self.prepare)
        alias.unlink()
        parent = self.root / "parent"
        parent.mkdir(mode=0o777)
        parent.chmod(0o777)
        self.rejected(wg.prepare, str(parent / "prepared"), "10.90.0.1", 51820,
                      str(self.private), str(self.public))
        parent.chmod(0o700)
        alias.symlink_to(parent, target_is_directory=True)
        self.rejected(wg.status, str(alias / "prepared"))

    def test_nonroot_ownership_and_wide_prepared_modes_are_rejected(self):
        os.chown(self.private, 10001, 10001)
        self.rejected(self.prepare)
        os.chown(self.private, 0, 0)
        self.prepare()
        for path in (self.directory, self.directory / "identity.json", self.directory / "private.key"):
            original = path.stat().st_mode & 0o777
            path.chmod(0o750 if path.is_dir() else 0o640)
            self.rejected(wg.status, str(self.directory))
            self.rejected(self.peer)
            path.chmod(original)

    def test_unknown_links_and_duplicate_or_injected_json_are_rejected(self):
        self.prepare()
        identity = self.directory / "identity.json"
        original = identity.read_bytes()
        for value in (original[:-2] + b', "address":"10.90.0.1"}\n',
                      original.replace(b'"schema_version": 1', b'"schema_version": true'),
                      original.replace(b"10.90.0.1", b"10.90.0.1\\nPostUp = evil"),
                      original.replace(b"10.90.0.1", b"10.90.0.1\x00"),
                      b'{"unknown":1}', b"[]" ):
            identity.write_bytes(value)
            self.rejected(self.peer)
            self.rejected(wg.status, str(self.directory))
        identity.write_bytes(original)
        unknown = self.directory / "unexpected"
        unknown.write_text("keep")
        self.rejected(self.peer)
        unknown.unlink()
        os.link(self.directory / "private.key", unknown)
        self.rejected(wg.status, str(self.directory))
        unknown.unlink()

    def test_config_injection_and_symlink_are_rejected_without_output(self):
        self.prepare()
        self.peer()
        config = self.directory / "wg-padm.conf"
        original = config.read_bytes()
        for value in (original + b"PostUp = evil\n", original.replace(b"\n", b"\r\n"),
                      original + b"\0", b"PrivateKey = " + PRIVATE.encode()):
            config.write_bytes(value)
            result = subprocess.run([sys.executable, "-B", str(HELPER), "status",
                                     "--directory", str(self.directory)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn(PRIVATE.encode(), result.stdout + result.stderr)
        config.unlink()
        config.symlink_to(self.private)
        self.rejected(wg.status, str(self.directory))

    def test_failed_publication_cleans_only_its_temporary_files(self):
        for failing_call in ("write_file", "publish_directory"):
            with mock.patch.object(wg, failing_call, side_effect=OSError("injected")):
                self.rejected(self.prepare)
            self.assertEqual(set(path.name for path in self.root.iterdir()),
                             {"private-input", "public-input"})
        self.prepare()
        before = self.snapshot()
        with mock.patch.object(wg.os, "link", side_effect=OSError("injected")):
            self.rejected(self.peer)
        self.assertEqual(self.snapshot(), before)

    def test_atomic_directory_publication_does_not_replace_concurrent_empty_target(self):
        original = wg.publish_directory

        def racing_publish(parent, temporary, name):
            os.mkdir(name, 0o700, dir_fd=parent)
            original(parent, temporary, name)

        with mock.patch.object(wg, "publish_directory", side_effect=racing_publish):
            self.rejected(self.prepare)
        self.assertEqual(list(self.directory.iterdir()), [])
        self.assertEqual(set(path.name for path in self.root.iterdir()),
                         {"private-input", "public-input", "prepared"})

    def test_interruption_after_directory_publication_preserves_complete_state(self):
        original = wg.publish_directory

        def interrupted_publish(*arguments):
            original(*arguments)
            raise InterruptedError("injected")

        with mock.patch.object(wg, "publish_directory", side_effect=interrupted_publish):
            self.rejected(self.prepare)
        self.assertFalse(wg.status(str(self.directory))["configured"])
        self.assertEqual(set(path.name for path in self.root.iterdir()),
                         {"private-input", "public-input", "prepared"})

    def test_peer_publication_never_overwrites_a_concurrent_configuration(self):
        self.prepare()
        original = wg.os.link
        marker = b"concurrent-configuration\n"

        def racing_link(*arguments, **keywords):
            (self.directory / "wg-padm.conf").write_bytes(marker)
            original(*arguments, **keywords)

        with mock.patch.object(wg.os, "link", side_effect=racing_link):
            self.rejected(self.peer)
        self.assertEqual((self.directory / "wg-padm.conf").read_bytes(), marker)
        self.assertEqual(set(path.name for path in self.directory.iterdir()),
                         {"identity.json", "private.key", "wg-padm.conf"})

    def test_migrate_merges_changes_into_private_candidate_without_touching_source(self):
        self.prepare()
        self.peer(endpoint="198.18.0.2:51821")
        original = {path.name: path.read_bytes() for path in self.directory.iterdir()}
        result = self.migrate(own_address="10.91.0.1", listen_port=51900,
                              peer_address="10.91.0.2", peer_public_key=ROTATED_PEER,
                              peer_endpoint="198.18.0.3:51901")
        candidate = self.root / "candidate"
        self.assertEqual(result, {"schema_version": 1, "address": "10.91.0.1",
                                  "listen_port": 51900, "public_key": PUBLIC, "configured": True})
        expected = wg.configuration({key: value for key, value in result.items() if key != "configured"},
                                    PRIVATE, "10.91.0.2", ROTATED_PEER, "198.18.0.3:51901")
        self.assertEqual((candidate / "wg-padm.conf").read_bytes(), expected)
        self.assertEqual(candidate.stat().st_mode & 0o777, 0o700)
        self.assertEqual(candidate.stat().st_uid, 0)
        for path in candidate.iterdir():
            self.assertEqual((path.stat().st_uid, path.stat().st_nlink, path.stat().st_mode & 0o777),
                             (0, 1, 0o600))
        self.assertEqual({path.name: path.read_bytes() for path in self.directory.iterdir()}, original)
        self.assertNotIn(PRIVATE, json.dumps(result))
        self.assertEqual(wg.status(str(candidate)), result)

    def test_migrate_omissions_keep_values_and_none_clears_only_endpoint(self):
        self.prepare()
        self.peer(endpoint="198.18.0.2:51821")
        self.migrate()
        self.assertEqual({path.name: path.read_bytes() for path in (self.root / "candidate").iterdir()},
                         {path.name: path.read_bytes() for path in self.directory.iterdir()})
        self.migrate(self.root / "without-endpoint", peer_endpoint="none")
        changed = (self.root / "without-endpoint" / "wg-padm.conf").read_bytes()
        self.assertEqual(changed, (self.directory / "wg-padm.conf").read_bytes().split(b"Endpoint = ")[0])
        self.assertNotIn(b"PersistentKeepalive", changed)

    def test_migrate_rotation_requires_both_private_input_files(self):
        self.prepare()
        self.peer()
        rotated_private, rotated_public = self.root / "rotated-private", self.root / "rotated-public"
        for path, value in ((rotated_private, ROTATED_PRIVATE), (rotated_public, ROTATED_PUBLIC)):
            path.write_text(value + "\n")
            path.chmod(0o600)
        before = self.snapshot()
        for arguments in ({"private_key": str(rotated_private)}, {"public_key": str(rotated_public)}):
            self.rejected(self.migrate, **arguments)
            self.assertEqual(self.snapshot(), before)
        result = self.migrate(private_key=str(rotated_private), public_key=str(rotated_public))
        self.assertEqual(result["public_key"], ROTATED_PUBLIC)
        self.assertEqual((self.root / "candidate" / "private.key").read_text(), ROTATED_PRIVATE + "\n")
        self.assertIn("PrivateKey = " + ROTATED_PRIVATE, (self.root / "candidate" / "wg-padm.conf").read_text())
        self.assertEqual((self.directory / "private.key").read_text(), PRIVATE + "\n")
        self.assertNotIn(ROTATED_PRIVATE, json.dumps(result))
        before = self.snapshot()
        rotated_public.write_text(PEER + "\n")
        self.rejected(self.migrate, self.root / "self-peer",
                      private_key=str(rotated_private), public_key=str(rotated_public))
        self.assertFalse((self.root / "self-peer").exists())
        rotated_public.write_text(ROTATED_PUBLIC + "\n")
        self.assertEqual(self.snapshot(), before)

    def test_migrate_invalid_changes_leave_source_and_existing_target_unchanged(self):
        self.prepare()
        self.peer()
        before = self.snapshot()
        for arguments in ({"own_address": "10.90.0.2"}, {"peer_address": "10.90.0.1"},
                          {"peer_public_key": PUBLIC}, {"own_address": "192.0.2.1"},
                          {"listen_port": True}, {"listen_port": 80}, {"peer_public_key": "invalid"},
                          {"peer_endpoint": ""}, {"peer_endpoint": "None"},
                          {"peer_endpoint": "127.0.0.1:51820"}):
            self.rejected(self.migrate, **arguments)
            self.assertEqual(self.snapshot(), before)
        candidate = self.root / "candidate"
        for existing in ("directory", "file", "symlink"):
            if existing == "directory":
                candidate.mkdir(mode=0o700)
            elif existing == "file":
                candidate.write_text("keep")
            else:
                candidate.symlink_to(self.directory, target_is_directory=True)
            before = self.snapshot()
            self.rejected(self.migrate)
            self.assertEqual(self.snapshot(), before)
            candidate.rmdir() if existing == "directory" else candidate.unlink()
        self.rejected(self.migrate, self.directory)
        self.rejected(self.migrate, self.directory / "nested")

    def test_migrate_rejects_noncanonical_source_and_unsafe_rotation_paths(self):
        self.prepare()
        self.rejected(self.migrate)
        self.peer()
        unknown = self.directory / "unexpected"
        unknown.write_text("keep")
        before = self.snapshot()
        self.rejected(self.migrate)
        self.assertEqual(self.snapshot(), before)
        unknown.unlink()
        config = self.directory / "wg-padm.conf"
        config.write_bytes(config.read_bytes() + b"PostUp = evil\n")
        before = self.snapshot()
        self.rejected(self.migrate)
        self.assertEqual(self.snapshot(), before)
        config.write_bytes(config.read_bytes().removesuffix(b"PostUp = evil\n"))
        alias = self.root / "rotation-alias"
        alias.symlink_to(self.private)
        before = self.snapshot()
        self.rejected(self.migrate, private_key=str(alias), public_key=str(self.public))
        self.assertEqual(self.snapshot(), before)
        self.private.chmod(0o640)
        before = self.snapshot()
        self.rejected(self.migrate, private_key=str(self.private), public_key=str(self.public))
        self.assertEqual(self.snapshot(), before)

    def test_migrate_failure_and_interrupt_clean_only_owned_candidate(self):
        self.prepare()
        self.peer()
        before = self.snapshot()
        original_write, original_publish = wg.write_file, wg.publish_directory

        def failed_write(directory, name, data, publish=None):
            original_write(directory, name, data, publish)
            if name == "wg-padm.conf":
                raise OSError("injected")

        def interrupted_publish(*arguments):
            original_publish(*arguments)
            raise InterruptedError("injected")

        for target, failure in (("write_file", failed_write),
                                ("publish_directory", OSError("injected")),
                                ("publish_directory", interrupted_publish)):
            with self.subTest(target=target, failure=type(failure).__name__):
                with mock.patch.object(wg, target, side_effect=failure):
                    self.rejected(self.migrate)
                self.assertEqual(self.snapshot(), before)

        def racing_publish(parent, temporary, name):
            os.mkdir(name, 0o700, dir_fd=parent)
            original_publish(parent, temporary, name)

        with mock.patch.object(wg, "publish_directory", side_effect=racing_publish):
            self.rejected(self.migrate)
        candidate = self.root / "candidate"
        self.assertEqual(list(candidate.iterdir()), [])
        self.assertEqual({path.name for path in self.root.iterdir()},
                         {"private-input", "public-input", "prepared", "candidate"})

    def test_migrate_cli_rejects_duplicates_and_emits_only_public_identity(self):
        self.prepare()
        self.peer(endpoint="198.18.0.2:51821")
        candidate = self.root / "candidate"
        command = [sys.executable, "-B", str(HELPER), "migrate", "--directory", str(self.directory),
                   "--destination", str(candidate)]
        before = self.snapshot()
        for options in (["--address", "10.91.0.1", "--address=10.91.0.2"],
                        ["--endpoint", "none", "--endpoint", "198.18.0.3:51820"],
                        ["--private-key", str(self.private)],
                        ["--private-key", str(self.private), "--public-key", str(self.public),
                         "--public-key", str(self.public)]):
            result = subprocess.run(command + options, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn(PRIVATE.encode(), result.stdout + result.stderr)
            self.assertEqual(self.snapshot(), before)
        result = subprocess.run(command + ["--endpoint", "none"], capture_output=True, check=True)
        self.assertTrue(json.loads(result.stdout)["configured"])
        self.assertNotIn(PRIVATE.encode(), result.stdout + result.stderr)
        self.assertNotIn(b"PrivateKey", result.stdout + result.stderr)


if __name__ == "__main__":
    if sys.platform != "linux" or os.geteuid() != 0:
        raise SystemExit("WireGuard 配置回归需要 Linux root")
    unittest.main()
