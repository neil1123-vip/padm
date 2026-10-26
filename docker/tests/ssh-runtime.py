#!/usr/bin/env python3
"""SSH collector 管理只接受当前 owner，失败保留现场。"""

import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("padm_ssh_runtime", ROOT / "docker/lib/ssh-runtime.py")
runtime = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runtime)


class RuntimeTests(unittest.TestCase):
    def owner(self):
        token = "a" * 32
        return {
            "schema": 1, "token": token,
            "service": "padm-ssh-collector-" + token + ".service",
            "unit": "ssh.service", "target": "192.0.2.10", "port": 2222,
            "invocation": "b" * 32,
            "python": str(Path(runtime.sys.executable).resolve()),
            "script": str(ROOT / "docker/lib/ssh-collector.py"),
        }

    def directory(self, path):
        os.chmod(path, 0o700)
        directory = runtime.Directory(path)
        self.addCleanup(directory.close)
        return directory

    def test_unknown_residue_and_changed_bundle_rejected(self):
        with tempfile.TemporaryDirectory(dir="/root") as path:
            directory = self.directory(path)
            self.assertIsNone(runtime.owner_read(directory))
            Path(path, "unknown").write_text("keep")
            with self.assertRaises(runtime.Failure):
                runtime.owner_read(directory)
            Path(path, "unknown").unlink()
            owner = self.owner()
            directory.write_owner(owner)
            self.assertEqual(runtime.owner_read(directory), owner)
            owner["script"] = "/another-bundle/ssh-collector.py"
            directory.write_owner(owner)
            with self.assertRaises(runtime.Failure):
                runtime.owner_read(directory)

    def test_changed_transient_binding_rejected_before_stop(self):
        with tempfile.TemporaryDirectory(dir="/root") as path:
            directory = self.directory(path)
            owner = self.owner()
            directory.write_owner(owner)
            fields = {key: "" for key in runtime.PROPERTIES}
            fields.update({
                "LoadState": "loaded", "ActiveState": "active", "SubState": "running",
                "Description": "padm SSH collector " + owner["token"], "Transient": "yes",
                "FragmentPath": "/run/systemd/transient/" + owner["service"],
                "InvocationID": owner["invocation"], "MainPID": "123",
                "ExecStart": "{ path=" + owner["python"] + " ; argv[]=" + " ".join([
                    owner["python"], "-B", owner["script"], owner["unit"],
                    owner["target"], str(owner["port"]),
                ]) + " ; ignore_errors=no ; }",
                "Environment": "PADM_SSH_COLLECTOR_DIR=" + path
                               + " PADM_SSH_COLLECTOR_TOKEN=" + owner["token"],
                "Type": "notify", "User": "root", "StandardOutput": "append",
            })
            def text():
                return "\n".join(key + "=" + value for key, value in fields.items())
            metadata = os.stat_result((stat.S_IFREG | 0o600, 1, 1, 1, 0, 0, 1, 0, 0, 0))
            with patch.object(runtime, "command", return_value=text()), \
                    patch.object(Path, "lstat", return_value=metadata), \
                    patch.object(Path, "read_text", return_value="StandardOutput=append:" + path + "/auth.log"):
                self.assertEqual(runtime.unit_state(owner, directory)["MainPID"], "123")
            for key, value in (
                ("Description", "another owner"), ("InvocationID", "c" * 32),
                ("Environment", "PADM_SSH_COLLECTOR_DIR=/another"),
                ("User", "nobody"),
                ("Type", "simple"),
            ):
                old = fields[key]
                fields[key] = value
                with patch.object(runtime, "command", return_value=text()) as command, \
                        patch.object(Path, "lstat", return_value=metadata), \
                        patch.object(Path, "read_text", return_value="StandardOutput=append:" + path + "/auth.log"):
                    with self.assertRaises(runtime.Failure):
                        runtime.stop(directory, owner)
                    self.assertEqual(command.call_count, 1)
                    self.assertTrue(Path(path, "owner.json").exists())
                fields[key] = old

    def test_unit_gone_cleans_only_same_owner(self):
        with tempfile.TemporaryDirectory(dir="/root") as path:
            directory = self.directory(path)
            owner = self.owner()
            directory.write_owner(owner)
            log = Path(path, "auth.log")
            log.touch(mode=0o600)
            fields = {key: "" for key in runtime.PROPERTIES}
            fields.update(LoadState="not-found", ActiveState="inactive", MainPID="0")
            text = "\n".join(key + "=" + value for key, value in fields.items())
            guard = Path(path, "guard.json")
            guard.write_text(json.dumps({"schema": 1, "token": "c" * 32}))
            guard.chmod(0o600)
            with patch.object(runtime, "command", return_value=text):
                with self.assertRaises(runtime.Failure):
                    runtime.stop(directory, owner)
                self.assertTrue(log.exists())
                guard.unlink()
                runtime.stop(directory, owner)
            self.assertEqual(os.listdir(path), [])

    def test_check_stop_do_not_create_missing_directory(self):
        with tempfile.TemporaryDirectory(dir="/root") as path:
            missing = str(Path(path, "missing"))
            with self.assertRaises(FileNotFoundError):
                runtime.Directory(missing)
            self.assertFalse(Path(missing).exists())

    def test_guard_read_retries_only_one_atomic_replacement(self):
        with tempfile.TemporaryDirectory(dir="/root") as path:
            directory = self.directory(path)
            guard = Path(path, "guard.json")
            payload = {"schema": 1, "token": "a" * 32}
            guard.write_text(json.dumps(payload))
            guard.chmod(0o600)
            original_open = os.open
            for replacements in (1, 2):
                remaining = replacements
                def replace_after_open(*args, **kwargs):
                    nonlocal remaining
                    descriptor = original_open(*args, **kwargs)
                    if args[0] == "guard.json" and remaining:
                        temporary = Path(path, ".guard-next")
                        temporary.write_text(json.dumps(payload))
                        temporary.chmod(0o600)
                        os.replace(temporary, guard)
                        remaining -= 1
                    return descriptor
                with self.subTest(replacements=replacements), \
                        patch.object(runtime.os, "open", side_effect=replace_after_open):
                    if replacements == 1:
                        self.assertEqual(directory.read("guard.json"), payload)
                    else:
                        with self.assertRaises(runtime.Failure):
                            directory.read("guard.json")
            guard.chmod(0o644)
            with self.assertRaises(runtime.Failure):
                directory.read("guard.json")
            guard.chmod(0o600)
            os.link(guard, Path(path, "guard-link"))
            with self.assertRaises(runtime.Failure):
                directory.read("guard.json")


if __name__ == "__main__":
    unittest.main()
