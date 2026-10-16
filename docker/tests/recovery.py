#!/usr/bin/env python3
"""灾备归档的真实字节、边界与失败原子性回归。"""

import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock


PROJECT_ROOT = Path(__file__).resolve().parents[2]
HELPER = PROJECT_ROOT / "docker/lib/recovery.py"
SPEC = importlib.util.spec_from_file_location("padm_recovery", HELPER)
recovery = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(recovery)
SECRET = b"private-test-marker-never-print"


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="padm-recovery-", dir=os.environ["TMPDIR"])
        self.addCleanup(self.directory.cleanup)
        self.base = Path(self.directory.name)
        self.root = self.base / "state"
        self.root.mkdir(mode=0o750)
        for name in recovery.REQUIRED:
            self.put(name, b"docker\n" if name == "mode" else b"{}\n")
        for name in (
            "config/xray/config.json", "config/xray/geo/state.json",
            "config/xray/geo/geoip.dat", "config/xray/geo/geosite.dat",
            "config/control/state.json", "config/share-groups.json",
            "data/traffic/state.json", "data/reality-targets/results.tsv",
            "data/reality-targets/blocked.tsv", "data/control-log/schedule.json",
            "data/subscription/users.base", "data/subscription/token1",
            "data/static/index.html", "secrets/tls/test.example.key",
            "secrets/renewal/test.example/request.json",
            "secrets/renewal/test.example/credentials.env",
            "secrets/control-sync/request.json", "secrets/control-sync/invite.json",
            "secrets/net/wireguard/wg-padm.conf",
            "data/acme/tmp.example.com/tmp.example.com.conf",
            "data/acme/log.example.com/log.example.com.key",
            "data/acme/lock.example.com/lock.example.com.key",
        ):
            self.put(name, SECRET)
        self.archive = self.base / "backup with spaces.tar"
        recovery.export_archive(str(self.root), str(self.archive))

    def put(self, name, data, mode=0o600):
        path = self.root / name
        path.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
        path.write_bytes(data)
        path.chmod(mode)
        return path

    def members(self):
        with tarfile.open(self.archive, "r:") as archive:
            return [(copy.copy(info), archive.extractfile(info).read() if info.isfile() else b"")
                    for info in archive]

    def packed(self, members):
        result = io.BytesIO()
        with tarfile.open(fileobj=result, mode="w", format=tarfile.USTAR_FORMAT) as archive:
            for info, data in members:
                archive.addfile(info, io.BytesIO(data) if info.isfile() else None)
        return result.getvalue()

    def rejected(self, data):
        with self.assertRaises((ValueError, OSError, tarfile.TarError)):
            recovery.verify_stream(io.BytesIO(data))

    def assert_no_staging(self):
        self.assertEqual(list(self.base.glob(".padm-recovery-*")), [])

    def test_round_trip_private_archive_and_exact_inputs(self):
        self.assertEqual(stat.S_IMODE(self.archive.stat().st_mode), 0o600)
        before = {path: path.stat() for path in self.root.rglob("*")}
        counts = recovery.verify_archive(str(self.archive))
        self.assertGreater(counts[0], 20)
        self.assertIn(b"\"scope\":\"managed-inputs\"", self.archive.read_bytes())
        members = self.members()
        payload = {info.name: data for info, data in members if info.isfile()}
        self.assertEqual(payload["secrets/net/wireguard/wg-padm.conf"], SECRET)
        self.assertEqual(payload["data/acme/tmp.example.com/tmp.example.com.conf"], SECRET)
        self.assertEqual(payload["data/acme/log.example.com/log.example.com.key"], SECRET)
        self.assertEqual(payload["data/acme/lock.example.com/lock.example.com.key"], SECRET)
        for path, info in before.items():
            self.assertEqual(recovery.signature(path.stat()), recovery.signature(info))

    def test_extract_exact_content_private_modes_and_validated_manifest(self):
        stage = self.base / "private stage"
        stage.mkdir(mode=0o700)
        previous_umask = os.umask(0o777)
        try:
            counts = recovery.extract_archive(str(self.archive), str(stage))
        finally:
            os.umask(previous_umask)
        self.assertEqual(counts, recovery.verify_archive(str(self.archive)))
        members = self.members()
        self.assertEqual({str(path.relative_to(stage)) for path in stage.rglob("*")},
                         {info.name for info, _ in members})
        for info, data in members:
            path = stage / info.name
            self.assertEqual(path.stat().st_uid, os.geteuid())
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o700 if info.isdir() else 0o600)
            if info.isfile():
                self.assertEqual(path.read_bytes(), data)
        manifest = recovery.read_json((stage / recovery.MANIFEST).read_bytes())
        recovery.validate_manifest(manifest)
        self.assertEqual(manifest["architecture"], {"x86_64": "amd64", "aarch64": "arm64"}[
            recovery.platform.machine()])

    def test_extract_rejects_nonprivate_nonempty_foreign_or_linked_stage(self):
        for kind in ("public", "nonempty", "foreign", "symlink", "parent-link", "missing"):
            with self.subTest(kind=kind):
                stage = self.base / ("stage-" + kind)
                if kind == "missing":
                    destination = stage
                else:
                    stage.mkdir(mode=0o700)
                    destination = stage
                    if kind == "public":
                        stage.chmod(0o750)
                    elif kind == "nonempty":
                        (stage / "sentinel").write_bytes(b"keep-existing")
                    elif kind == "foreign":
                        os.chown(stage, 65534, 65534)
                    elif kind == "symlink":
                        destination = self.base / "stage-alias"
                        destination.symlink_to(stage, target_is_directory=True)
                    else:
                        alias = self.base / "parent-alias"
                        alias.symlink_to(self.base, target_is_directory=True)
                        destination = alias / stage.name
                with self.assertRaises((ValueError, OSError)):
                    recovery.extract_archive(str(self.archive), str(destination))
                if kind != "missing":
                    self.assertEqual([path.name for path in stage.iterdir()],
                                     ["sentinel"] if kind == "nonempty" else [])
                else:
                    self.assertFalse(stage.exists())

    def test_extract_corruption_and_unsafe_members_cannot_publish_manifest_or_escape(self):
        sentinel = self.base / "escape"
        sentinel.write_bytes(b"keep-outside")
        for kind in ("corrupt", "trailer", "traversal", "symlink"):
            with self.subTest(kind=kind):
                stage = self.base / ("unverified-" + kind)
                stage.mkdir(mode=0o700)
                members = self.members()
                if kind == "corrupt":
                    index = next(i for i, (info, _) in enumerate(members) if info.isfile())
                    info, data = members[index]
                    members[index] = info, bytes([data[0] ^ 1]) + data[1:]
                elif kind == "traversal":
                    members.insert(-1, (recovery.tar_info("../escape", False, 1), b"x"))
                elif kind == "symlink":
                    info = recovery.tar_info("data/static/link", False)
                    info.type, info.linkname = tarfile.SYMTYPE, "../../escape"
                    members.insert(-1, (info, b""))
                damaged = self.packed(members)
                if kind == "trailer":
                    damaged += b"unexpected-trailer"
                archive = self.base / ("damaged-" + kind + ".tar")
                archive.write_bytes(damaged)
                archive.chmod(0o600)
                with self.assertRaises((ValueError, OSError, tarfile.TarError)):
                    recovery.extract_archive(str(archive), str(stage))
                self.assertFalse((stage / recovery.MANIFEST).exists())
                self.assertFalse(any(path.is_symlink() for path in stage.rglob("*")))
                self.assertEqual(sentinel.read_bytes(), b"keep-outside")

    def test_extract_changed_archive_cannot_publish_validated_manifest(self):
        stage = self.base / "changed-stage"
        stage.mkdir(mode=0o700)
        original = recovery.verify_stream

        def verify_and_change(source, directory_fd=None):
            result = original(source, directory_fd)
            info = self.archive.stat()
            os.utime(self.archive, ns=(info.st_atime_ns, info.st_mtime_ns + 1_000_000))
            return result

        with mock.patch.object(recovery, "verify_stream", side_effect=verify_and_change):
            with self.assertRaises(ValueError):
                recovery.extract_archive(str(self.archive), str(stage))
        self.assertTrue((stage / "config/spec.json").is_file())
        self.assertFalse((stage / recovery.MANIFEST).exists())

    def test_extract_cli_does_not_disclose_contents(self):
        stage = self.base / "cli-stage"
        stage.mkdir(mode=0o700)
        result = subprocess.run(
            [sys.executable, "-B", str(HELPER), "extract", "--archive", str(self.archive),
             "--directory", str(stage)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
            env={**os.environ, "TMPDIR": str(self.base / "does-not-exist")},
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertNotIn(SECRET, result.stdout + result.stderr)
        self.assertEqual((stage / "config/xray/config.json").read_bytes(), SECRET)
        self.assertTrue((stage / recovery.MANIFEST).is_file())
        self.assert_no_staging()

    def test_runtime_owned_private_keys_are_preserved(self):
        key = self.root / "secrets/tls/test.example.key"
        os.chown(key, 10001, 10001)
        target = self.base / "runtime.tar"
        recovery.export_archive(str(self.root), str(target))
        self.assertEqual(recovery.verify_archive(str(target)), recovery.verify_archive(str(self.archive)))

    def test_foreign_owned_source_is_rejected(self):
        os.chown(self.root / "secrets/tls/test.example.key", 65534, 65534)
        with self.assertRaises(ValueError):
            recovery.export_archive(str(self.root), str(self.base / "foreign.tar"))
        self.assert_no_staging()

    def test_runtime_state_and_known_acme_transients_are_excluded(self):
        for name in (
            "locks/deployment.lock/pid", "data/net/wireguard/wireguard.state",
            "data/net/.hopping-supervisor/pid", "data/control-source/token",
            "data/acme-webroot/token", "logs/acme/acme.log", "backups/old/spec.json",
            "data/acme/http.header", "data/acme/acme.log", "data/acme/.lock",
        ):
            self.put(name, b"runtime-only-marker")
        target = self.base / "filtered.tar"
        recovery.export_archive(str(self.root), str(target))
        self.assertNotIn(b"runtime-only-marker", target.read_bytes())
        recovery.verify_archive(str(target))

    def test_no_overwrite_and_failure_leaves_no_temp(self):
        self.archive.write_bytes(b"keep-existing")
        with self.assertRaises(FileExistsError):
            recovery.export_archive(str(self.root), str(self.archive))
        self.assertEqual(self.archive.read_bytes(), b"keep-existing")
        self.assert_no_staging()

    def test_rejects_untrusted_output_directory(self):
        public = self.base / "public"
        public.mkdir(mode=0o777)
        public.chmod(0o777)
        with self.assertRaises(ValueError):
            recovery.export_archive(str(self.root), str(public / "backup.tar"))
        self.assertEqual(list(public.iterdir()), [])

    def test_rejects_source_links_special_files_and_unsafe_modes(self):
        source = self.root / "config/xray/config.json"
        for kind in ("symlink", "hardlink", "fifo", "writable", "special", "public-key"):
            with self.subTest(kind=kind):
                source.unlink()
                if kind == "symlink":
                    source.symlink_to(self.root / "config/spec.json")
                elif kind == "hardlink":
                    os.link(self.root / "config/spec.json", source)
                elif kind == "fifo":
                    os.mkfifo(source, 0o600)
                else:
                    source.write_bytes(SECRET)
                    source.chmod({"writable": 0o620, "special": 0o4600, "public-key": 0o644}[kind])
                with self.assertRaises((ValueError, OSError)):
                    recovery.export_archive(str(self.root), str(self.base / "unsafe.tar"))
                source.unlink()
                self.put("config/xray/config.json", SECRET)
                self.assert_no_staging()

    def test_rejects_private_credentials_with_public_read_mode(self):
        key = self.root / "secrets/tls/test.example.key"
        key.chmod(0o644)
        with self.assertRaises(ValueError):
            recovery.export_archive(str(self.root), str(self.base / "public-secret.tar"))
        self.assert_no_staging()

    def test_rejects_symlinked_source_or_output_parent(self):
        alias = self.base / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        for root, output in ((alias, self.base / "alias.tar"), (self.root, alias / "out.tar")):
            with self.subTest(root=str(root), output=str(output)), self.assertRaises(OSError):
                recovery.export_archive(str(root), str(output))
        self.assert_no_staging()

    def test_changed_source_during_read_is_rejected(self):
        original = recovery.DigestReader.read
        changed = False

        def read_and_change(reader, size):
            nonlocal changed
            data = original(reader, size)
            if not changed:
                changed = True
                self.put("config/spec.json", b'{"changed":true}\n')
            return data

        target = self.base / "changed.tar"
        with mock.patch.object(recovery.DigestReader, "read", read_and_change):
            with self.assertRaises(ValueError):
                recovery.export_archive(str(self.root), str(target))
        self.assertFalse(target.exists())
        self.assert_no_staging()

    def test_new_selected_file_during_read_is_rejected(self):
        original = recovery.DigestReader.read
        changed = False

        def read_and_add(reader, size):
            nonlocal changed
            data = original(reader, size)
            if not changed:
                changed = True
                self.put("data/static/new.txt", b"new")
            return data

        with mock.patch.object(recovery.DigestReader, "read", read_and_add):
            with self.assertRaises(ValueError):
                recovery.export_archive(str(self.root), str(self.base / "new-file.tar"))
        self.assert_no_staging()

    def test_signal_cleans_partial_archive(self):
        with mock.patch.object(recovery.DigestReader, "read", side_effect=SystemExit(143)):
            with self.assertRaises(SystemExit):
                recovery.export_archive(str(self.root), str(self.base / "interrupted.tar"))
        self.assertFalse((self.base / "interrupted.tar").exists())
        self.assert_no_staging()

    def test_rejects_missing_required_source(self):
        (self.root / "config/spec.json").unlink()
        with self.assertRaises(ValueError):
            recovery.export_archive(str(self.root), str(self.base / "missing.tar"))

    def test_rejects_unsupported_static_paths_without_partial_output(self):
        for name in ("data/static/" + "a" * 101 + ".css", "data/static/中文.html"):
            path = self.put(name, b"content")
            with self.subTest(name=name), self.assertRaises(ValueError):
                recovery.export_archive(str(self.root), str(self.base / "unsupported.tar"))
            path.unlink()
            self.assert_no_staging()

    def test_corruption_missing_extra_duplicate_and_reordered_members(self):
        members = self.members()
        for kind in ("corrupt", "missing", "extra", "duplicate", "reordered", "no-manifest"):
            modified = copy.deepcopy(members)
            if kind == "corrupt":
                index = next(i for i, (info, _) in enumerate(modified) if info.isfile())
                info, data = modified[index]
                modified[index] = (info, bytes([data[0] ^ 1]) + data[1:])
            elif kind == "missing":
                modified.pop(0)
            elif kind == "extra":
                modified.insert(-1, (recovery.tar_info("data/static/extra.txt", False, 1), b"x"))
            elif kind == "duplicate":
                modified.insert(-1, copy.deepcopy(modified[0]))
            elif kind == "reordered":
                modified[0], modified[1] = modified[1], modified[0]
            else:
                modified.pop()
            with self.subTest(kind=kind):
                self.rejected(self.packed(modified))

    def test_rejects_unsafe_names_and_tar_extensions_before_payload(self):
        for name, type_code in (
            ("../escape", tarfile.REGTYPE), ("/etc/passwd", tarfile.REGTYPE),
            ("config//spec.json", tarfile.REGTYPE), ("config/./spec.json", tarfile.REGTYPE),
            ("config\\spec.json", tarfile.REGTYPE), ("C:/escape", tarfile.REGTYPE),
            ("config/xray/link", tarfile.SYMTYPE), ("config/xray/link", tarfile.LNKTYPE),
            ("config/xray/fifo", tarfile.FIFOTYPE), ("config/xray/device", tarfile.CHRTYPE),
            ("config/xray/pax", tarfile.XHDTYPE), ("config/xray/sparse", tarfile.GNUTYPE_SPARSE),
        ):
            info = recovery.tar_info(name, False)
            info.type = type_code
            with self.subTest(name=name, type_code=type_code):
                self.rejected(self.packed([(info, b"")]))

    def test_rejects_oversized_member_before_reading_body(self):
        info = recovery.tar_info("config/xray/oversized", False, recovery.MAX_FILE + 1)
        self.rejected(info.tobuf(tarfile.USTAR_FORMAT) + b"\0" * 1024)

    def test_rejects_malformed_manifest(self):
        for kind in ("version", "duplicate-key", "bool-version", "hash", "extra-key", "mode", "missing"):
            members = self.members()
            info, data = members[-1]
            manifest = json.loads(data)
            if kind == "version":
                manifest["schema_version"] = 99
            elif kind == "bool-version":
                manifest["schema_version"] = True
            elif kind == "hash":
                next(entry for entry in manifest["entries"] if entry["type"] == "file")["sha256"] = "0" * 64
            elif kind == "extra-key":
                manifest["run"] = "ignored-command"
            elif kind == "mode":
                next(entry for entry in manifest["entries"] if entry["type"] == "file")["mode"] = 0o666
            elif kind == "missing":
                manifest["entries"] = [entry for entry in manifest["entries"] if entry["path"] != "config/spec.json"]
            encoded = json.dumps(manifest).encode()
            if kind == "duplicate-key":
                encoded = b'{"format":"duplicate",' + encoded[1:]
            info.size = len(encoded)
            members[-1] = info, encoded
            with self.subTest(kind=kind):
                self.rejected(self.packed(members))

    def test_rejects_truncation_nonzero_padding_and_concatenated_archive(self):
        original = self.archive.read_bytes()
        self.rejected(original[:-10240])
        self.rejected(original + original)
        self.rejected(original + b"unexpected-trailer")
        offset = 0
        while True:
            member = tarfile.TarInfo.frombuf(original[offset:offset + 512], "ascii", "strict")
            if member.isfile() and member.size % 512:
                offset += 512 + member.size
                break
            offset += 512 + (member.size + 511) // 512 * 512
        damaged = bytearray(original)
        damaged[offset] = 1
        self.rejected(bytes(damaged))

    def test_verify_file_safety(self):
        for kind in ("symlink", "hardlink", "public"):
            with self.subTest(kind=kind):
                path = self.base / (kind + ".tar")
                if kind == "symlink":
                    path.symlink_to(self.archive)
                elif kind == "hardlink":
                    os.link(self.archive, path)
                else:
                    path.write_bytes(self.archive.read_bytes())
                    path.chmod(0o644)
                with self.assertRaises((ValueError, OSError)):
                    recovery.verify_archive(str(path))
                stage = self.base / ("unsafe-archive-" + kind)
                stage.mkdir(mode=0o700)
                with self.assertRaises((ValueError, OSError)):
                    recovery.extract_archive(str(path), str(stage))
                self.assertEqual(list(stage.iterdir()), [])
                path.unlink()

    def test_verify_cli_is_read_only_and_does_not_disclose_contents(self):
        before = self.base.stat().st_mtime_ns
        result = subprocess.run(
            ["python3", "-B", str(HELPER), "verify", "--archive", str(self.archive)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
            env={**os.environ, "TMPDIR": str(self.base / "does-not-exist")},
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertNotIn(SECRET, result.stdout + result.stderr)
        self.assertEqual(self.base.stat().st_mtime_ns, before)
        self.assert_no_staging()

    def test_verify_cli_works_without_root_or_docker(self):
        def unprivileged():
            os.setgroups([])
            os.setgid(65534)
            os.setuid(65534)

        # 回归 TMPDIR 的上层只允许 root 访问，非 root 夹具另放在可遍历的 /tmp。
        with tempfile.TemporaryDirectory(prefix="padm-recovery-nonroot-", dir="/tmp") as directory:
            Path(directory).chmod(0o711)
            path = Path(directory) / "nonroot.tar"
            path.write_bytes(self.archive.read_bytes())
            path.chmod(0o600)
            os.chown(path, 65534, 65534)
            result = subprocess.run(
                [sys.executable, "-B", str(HELPER), "verify", "--archive", str(path)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
                env={"PATH": "", "TMPDIR": str(self.base / "missing")},
                preexec_fn=unprivileged,
            )
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertNotIn(SECRET, result.stdout + result.stderr)
        self.assert_no_staging()

    def test_signal_handler_keeps_exit_status(self):
        with self.assertRaises(SystemExit) as raised:
            recovery.interrupted(signal.SIGTERM, None)
        self.assertEqual(raised.exception.code, 143)


if __name__ == "__main__":
    unittest.main()
