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


class RealityInputTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="padm-reality-recovery-",
                                                     dir=os.environ["TMPDIR"])
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.source = self.root / "source"
        self.library = self.source / "data/reality-targets"
        self.library.mkdir(parents=True, mode=0o700)
        for name in recovery.REQUIRED:
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"docker\n" if name == "mode" else b"{}\n")
            path.chmod(0o600)
        self.destination = self.root / "candidate"
        (self.destination / "data").mkdir(parents=True)
        self.row = ["Example.COM:00443", "Example.COM", "", "custom", "no", "unknown",
                    "AS12345678901234567890", "", "auto_probe", "A", "unknown",
                    "unknown", "unknown", "0", ""]
        self.seal()

    def seal(self):
        archive = self.root / "source.tar"
        if archive.exists():
            archive.unlink()
        recovery.export_archive(str(self.source), str(archive))
        with tarfile.open(archive, "r:") as source:
            path = self.source / recovery.MANIFEST
            path.write_bytes(source.extractfile(recovery.MANIFEST).read())
            path.chmod(0o600)

    def put(self, name, data):
        path = self.library / name
        path.write_bytes(data)
        path.chmod(0o600)
        self.seal()
        return path

    def test_legacy_empty_columns_duplicates_custom_reason_and_exact_private_copy(self):
        old = "\t".join(self.row)
        new = "\t".join(self.row + ["Somewhere, Country"])
        payload = {"results.tsv": (old + "\n" + new + "\n" + old).encode(),
                   "blocked.tsv": "blocked.example||自定义原因|说明\n".encode()}
        for name, data in payload.items():
            self.put(name, data)
        counts = recovery.reality_inputs(str(self.source), str(self.destination))
        self.assertEqual(counts, {"reality_results": 3, "reality_blocked": 1})
        target = self.destination / "data/reality-targets"
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o700)
        for name, data in payload.items():
            path = target / name
            self.assertEqual(path.read_bytes(), data)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual((path.stat().st_uid, path.stat().st_gid), (0, 0))
        with self.assertRaises(FileExistsError):
            recovery.reality_inputs(str(self.source), str(self.destination))

    def test_empty_missing_and_historical_enum_values(self):
        self.library.rmdir()
        self.library.parent.rmdir()
        self.assertEqual(recovery.reality_inputs(str(self.source)),
                         {"reality_results": 0, "reality_blocked": 0})
        for risk in ("no", "yes", "unknown", "cdn_edge", "cloudflare_relay"):
            row = self.row.copy()
            row[4], row[5], row[9], row[10], row[11], row[12] = risk, "::1", "FAIL", "no", "0", "no"
            self.assertEqual(recovery.reality_records("results.tsv", "\t".join(row).encode()), 1)
        self.library.mkdir(parents=True, mode=0o700)
        self.put("results.tsv", b"")
        recovery.reality_inputs(str(self.source), str(self.destination))
        self.assertEqual((self.destination / "data/reality-targets/results.tsv").read_bytes(), b"")

    def test_invalid_rows_fail_before_any_destination_write(self):
        invalid = [b"\xff", b"\n", b"bad\trow\n", b"bad\rrow\n", b"bad\x00row"]
        for index, value in ((0, "host:0"), (0, "host:65536"), (0, "[::1]:443"),
                             (0, "999.1.1.1:443"), (1, "bad host"), (4, "invalid"),
                             (5, "not-an-ip"), (6, "AS-1"), (8, "invalid"),
                             (9, "D"), (10, "true"), (11, "-1"), (12, "true"), (13, "-1")):
            row = self.row.copy()
            row[index] = value
            invalid.append("\t".join(row).encode())
        for data in invalid:
            self.put("results.tsv", data)
            with self.subTest(data=data), self.assertRaises(ValueError):
                recovery.reality_inputs(str(self.source), str(self.destination))
            self.assertFalse((self.destination / "data/reality-targets").exists())
        self.put("results.tsv", "\t".join(self.row).encode())
        for data in (b"a|b|c", b"a|b||d", b"bad host|b|c|d", b"a|b|c|d|e"):
            self.put("blocked.tsv", data)
            with self.subTest(data=data), self.assertRaises(ValueError):
                recovery.reality_inputs(str(self.source), str(self.destination))
            self.assertFalse((self.destination / "data/reality-targets").exists())

    def test_unsafe_files_directories_and_changed_read_are_rejected(self):
        path = self.put("results.tsv", "\t".join(self.row).encode())
        path.chmod(0o640)
        with self.assertRaises(ValueError):
            recovery.reality_inputs(str(self.source))
        path.chmod(0o600)
        self.library.chmod(0o750)
        with self.assertRaises(ValueError):
            recovery.reality_inputs(str(self.source))
        self.library.chmod(0o700)
        outside = self.root / "outside"
        path.rename(outside)
        path.symlink_to(outside)
        with self.assertRaises(OSError):
            recovery.reality_inputs(str(self.source))
        path.unlink()
        os.link(outside, path)
        with self.assertRaises(ValueError):
            recovery.reality_inputs(str(self.source))
        path.unlink()
        self.put("results.tsv", outside.read_bytes())
        target_inode = path.stat().st_ino
        original = os.read
        def changing_read(fd, size):
            data = original(fd, size)
            if data and os.fstat(fd).st_ino == target_inode:
                path.write_bytes(b"changed")
            return data
        with mock.patch.object(recovery.os, "read", side_effect=changing_read):
            with self.assertRaises(ValueError):
                recovery.reality_inputs(str(self.source), str(self.destination))
        self.assertFalse((self.destination / "data/reality-targets").exists())

    def test_observed_library_disappearance_is_not_treated_as_missing(self):
        path = self.put("results.tsv", "\t".join(self.row).encode())
        original = recovery.transaction_read

        def disappearing_read(parent, name, *args, **kwargs):
            if name == "results.tsv":
                path.unlink()
                self.library.rmdir()
            return original(parent, name, *args, **kwargs)

        with mock.patch.object(recovery, "transaction_read", side_effect=disappearing_read):
            with self.assertRaises(FileNotFoundError):
                recovery.reality_inputs(str(self.source), str(self.destination))
        self.assertFalse((self.destination / "data/reality-targets").exists())

    def test_manifest_rejects_missing_extra_or_changed_inputs_between_calls(self):
        data = "\t".join(self.row).encode()
        path = self.put("results.tsv", data)
        recovery.reality_inputs(str(self.source))
        path.unlink()
        self.library.rmdir()
        with self.assertRaises(ValueError):
            recovery.reality_inputs(str(self.source), str(self.destination))
        self.library.mkdir(mode=0o700)
        path.write_bytes(data.replace(b"custom", b"change"))
        path.chmod(0o600)
        with self.assertRaises(ValueError):
            recovery.reality_inputs(str(self.source), str(self.destination))
        path.write_bytes(data)
        extra = self.library / "blocked.tsv"
        extra.write_bytes(b"")
        extra.chmod(0o600)
        with self.assertRaises(ValueError):
            recovery.reality_inputs(str(self.source), str(self.destination))
        self.assertFalse((self.destination / "data/reality-targets").exists())


class RenewalInputTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="padm-renewal-recovery-",
                                                     dir=os.environ["TMPDIR"])
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.source = self.root / "source"
        self.registry = self.source / "secrets/renewal"
        self.domain = "dns.example.com"
        self.entry = self.registry / self.domain
        self.entry.mkdir(parents=True, mode=0o700)
        self.registry.chmod(0o700)
        for name in recovery.REQUIRED:
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"docker\n" if name == "mode" else b"{}\n")
            path.chmod(0o600)
        self.destination = self.root / "candidate"
        (self.destination / "secrets").mkdir(parents=True)
        self.credentials = self.entry / "credentials.env"
        self.credentials.write_bytes(b"# DNS provider\r\nDNS_Token=" + SECRET + b"\r\n")
        self.credentials.chmod(0o600)
        self.request = {"schema_version": 1, "domain": self.domain,
                        "email": "admin@example.com", "provider": "dns_cf", "enabled": False}
        self.put_request(self.request)

    def seal(self):
        archive = self.root / "source.tar"
        if archive.exists():
            archive.unlink()
        recovery.export_archive(str(self.source), str(archive))
        with tarfile.open(archive, "r:") as source:
            path = self.source / recovery.MANIFEST
            path.write_bytes(source.extractfile(recovery.MANIFEST).read())
            path.chmod(0o600)

    def put_request(self, request):
        path = self.entry / "request.json"
        path.write_bytes(request if isinstance(request, bytes) else
                         (json.dumps(request, indent=3) + "\n\n").encode())
        path.chmod(0o600)
        self.seal()

    def rejected(self):
        with self.assertRaises((ValueError, OSError)):
            recovery.renewal_inputs(str(self.source), str(self.destination))
        self.assertFalse((self.destination / "secrets/renewal").exists())

    def test_exact_private_copy_all_disabled_providers_and_cli_summary(self):
        for schema, provider in ((2, "standalone"), (4, "alpn")):
            domain = provider + ".example.com"
            entry = self.registry / domain
            entry.mkdir(mode=0o700)
            path = entry / "request.json"
            path.write_bytes((json.dumps(dict(self.request, schema_version=schema,
                                              domain=domain, provider=provider)) + "\n").encode())
            path.chmod(0o600)
        self.seal()
        result = recovery.renewal_inputs(str(self.source), str(self.destination))
        self.assertEqual(result, {"renewal_registrations": 3})
        target = self.destination / "secrets/renewal"
        for path in [self.registry] + list(self.registry.rglob("*")):
            copied = target / path.relative_to(self.registry)
            self.assertEqual(stat.S_IMODE(copied.stat().st_mode), 0o700 if path.is_dir() else 0o600)
            self.assertEqual((copied.stat().st_uid, copied.stat().st_gid), (0, 0))
            if path.is_file():
                self.assertEqual(copied.read_bytes(), path.read_bytes())
        with self.assertRaises(FileExistsError):
            recovery.renewal_inputs(str(self.source), str(self.destination))
        result = subprocess.run([sys.executable, "-B", str(HELPER), "renewal-inputs",
                                 "--directory", str(self.source)], capture_output=True, check=True)
        self.assertEqual(json.loads(result.stdout), {"renewal_registrations": 3})
        self.assertEqual(result.stderr, b"")
        self.assertNotIn(SECRET, result.stdout)

    def test_absent_and_empty_registry_compatibility(self):
        self.credentials.unlink()
        (self.entry / "request.json").unlink()
        self.entry.rmdir()
        self.seal()
        self.assertEqual(recovery.renewal_inputs(str(self.source)), {"renewal_registrations": 0})
        self.registry.rmdir()
        self.seal()
        self.assertEqual(recovery.renewal_inputs(str(self.source), str(self.destination)),
                         {"renewal_registrations": 0})
        self.assertFalse((self.destination / "secrets/renewal").exists())

    def test_request_schema_enabled_and_http01_boundaries(self):
        invalid = [dict(self.request, **{key: value}) for key, value in (
            ("enabled", True), ("enabled", 0), ("schema_version", True),
            ("schema_version", 2), ("provider", "dns_CF"), ("provider", "webroot"),
            ("domain", "other.example.com"), ("email", "bad"), ("email", "a@example.com\n"))]
        invalid.extend([dict(self.request, schema_version=3, provider="webroot"),
                        dict(self.request, extra="unexpected"), b"[]", b"",
                        b'{"enabled":false,"enabled":false}'])
        for request in invalid:
            with self.subTest(request=request):
                self.put_request(request)
                self.rejected()

    def test_credentials_reject_duplicate_dangerous_names_and_invalid_lines(self):
        invalid = [b"", b"# only comments\n", b"invalid\n", b"DNS_Token=a\nDNS_Token=b\n",
                   b"DNS_Token=a\x00b", b"1TOKEN=a", b"export DNS_Token=a", b"\xff"]
        invalid.extend(name.encode() + b"=private\n" for name in (
            "PATH", "HOME", "ENV", "BASH_ENV", "IFS", "SHELLOPTS", "BASHOPTS", "CDPATH",
            "GLOBIGNORE", "PS4", "DEBUG", "TMPDIR", "PYTHONPATH", "LD_PRELOAD",
            "PADM_FLAG", "LE_FLAG", "ACME_FLAG", "Le_Flag"))
        for data in invalid:
            with self.subTest(data=data):
                self.credentials.write_bytes(data)
                self.seal()
                self.rejected()

    def test_missing_extra_or_changed_manifest_inputs_are_rejected(self):
        self.credentials.write_bytes(b"DNS_Token=changed\n")
        self.rejected()
        self.credentials.unlink()
        self.rejected()
        self.seal()
        self.rejected()
        self.credentials.write_bytes(b"DNS_Token=valid\n")
        self.credentials.chmod(0o600)
        self.seal()
        extra = self.entry / "extra"
        extra.write_bytes(b"not allowed")
        extra.chmod(0o600)
        self.rejected()
        self.seal()
        self.rejected()
        extra.unlink()
        self.credentials.unlink()
        self.put_request(dict(self.request, schema_version=2, provider="standalone"))
        self.credentials.write_bytes(b"DNS_Token=unexpected\n")
        self.credentials.chmod(0o600)
        self.seal()
        self.rejected()

    def test_unsafe_permissions_ownership_links_and_size_limits(self):
        for path, mode in ((self.registry, 0o750), (self.entry, 0o750),
                           (self.credentials, 0o640)):
            original = stat.S_IMODE(path.stat().st_mode)
            path.chmod(mode)
            self.rejected()
            path.chmod(original)
        os.chown(self.credentials, 10001, 10001)
        self.rejected()
        os.chown(self.credentials, 0, 0)
        outside = self.root / "outside"
        self.credentials.rename(outside)
        self.credentials.symlink_to(outside)
        self.rejected()
        self.credentials.unlink()
        os.link(outside, self.credentials)
        self.rejected()
        self.credentials.unlink()
        self.credentials.write_bytes(b"DNS_Token=valid\n")
        self.credentials.chmod(0o600)
        for path, limit in ((self.credentials, 1024 * 1024), (self.entry / "request.json", 64 * 1024)):
            data = path.read_bytes()
            os.truncate(path, limit + 1)
            self.rejected()
            path.write_bytes(data)

    def test_read_mutation_and_registry_replacement_fail_before_copy(self):
        inode = self.credentials.stat().st_ino
        original = os.read

        def changed_read(fd, size):
            data = original(fd, size)
            if data and os.fstat(fd).st_ino == inode:
                self.credentials.write_bytes(b"DNS_Token=changed\n")
            return data

        with mock.patch.object(recovery.os, "read", side_effect=changed_read):
            self.rejected()
        self.seal()
        original_read = recovery.transaction_read

        def replaced_read(parent, name, *args, **kwargs):
            result = original_read(parent, name, *args, **kwargs)
            if name == "request.json":
                self.registry.rename(self.source / "secrets/old-renewal")
                self.registry.mkdir(mode=0o700)
            return result

        with mock.patch.object(recovery, "transaction_read", side_effect=replaced_read):
            self.rejected()

    def test_cli_rejection_does_not_expose_private_input(self):
        self.credentials.write_bytes(b"PATH=" + SECRET)
        self.seal()
        result = subprocess.run([sys.executable, "-B", str(HELPER), "renewal-inputs",
                                 "--directory", str(self.source)], capture_output=True)
        self.assertEqual(result.returncode, 15)
        self.assertEqual(result.stdout, b"")
        self.assertNotIn(SECRET, result.stderr)


class GeoInputTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="padm-geo-recovery-",
                                                     dir=os.environ["TMPDIR"])
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.source = self.root / "source"
        self.geo = self.source / "config/xray/geo"
        self.geo.mkdir(parents=True, mode=0o700)
        for name in recovery.REQUIRED:
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"docker\n" if name == "mode" else b"{}\n")
            path.chmod(0o600)
        self.destination = self.root / "candidate"
        (self.destination / "config/xray").mkdir(parents=True)
        self.payload = {"geoip.dat": b"\x00\xffip\n", "geosite.dat": b"\x00\xfesite\n"}
        for name, data in self.payload.items():
            path = self.geo / name
            path.write_bytes(data)
            path.chmod(0o600)
        self.state = {"schema_version": 1, "version": "202610170001", "enabled": False,
                      "sha256": {name: recovery.hashlib.sha256(data).hexdigest()
                                 for name, data in self.payload.items()}}
        self.put_state(self.state)

    def seal(self):
        archive = self.root / "source.tar"
        if archive.exists():
            archive.unlink()
        recovery.export_archive(str(self.source), str(archive))
        with tarfile.open(archive, "r:") as source:
            path = self.source / recovery.MANIFEST
            path.write_bytes(source.extractfile(recovery.MANIFEST).read())
            path.chmod(0o600)

    def put_state(self, state):
        path = self.geo / "state.json"
        path.write_bytes(state if isinstance(state, bytes) else
                         (json.dumps(state, indent=3) + "\n\n").encode())
        path.chmod(0o600)
        self.seal()

    def rejected(self):
        with self.assertRaises((ValueError, OSError)):
            recovery.geo_inputs(str(self.source), str(self.destination))
        self.assertFalse((self.destination / "config/xray/geo").exists())

    def test_exact_private_copy_streaming_and_cli_summary(self):
        payload = b"\x00\xff" * (recovery.CHUNK + 17)
        (self.geo / "geoip.dat").write_bytes(payload)
        self.state["sha256"]["geoip.dat"] = recovery.hashlib.sha256(payload).hexdigest()
        self.put_state(self.state)
        original = os.read

        def bounded_read(fd, size):
            self.assertLessEqual(size, recovery.CHUNK)
            return original(fd, size)

        with mock.patch.object(recovery.os, "read", side_effect=bounded_read):
            self.assertEqual(recovery.geo_inputs(str(self.source), str(self.destination)),
                             {"geo_files": 3})
        target = self.destination / "config/xray/geo"
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o700)
        for path in self.geo.iterdir():
            copied = target / path.name
            self.assertEqual(copied.read_bytes(), path.read_bytes())
            self.assertEqual(stat.S_IMODE(copied.stat().st_mode), 0o600)
            self.assertEqual((copied.stat().st_uid, copied.stat().st_gid), (0, 0))
        with self.assertRaises(FileExistsError):
            recovery.geo_inputs(str(self.source), str(self.destination))
        result = subprocess.run([sys.executable, "-B", str(HELPER), "geo-inputs",
                                 "--directory", str(self.source)], capture_output=True, check=True)
        self.assertEqual(json.loads(result.stdout), {"geo_files": 3})
        self.assertEqual(result.stderr, b"")

    def test_absent_geo_compatibility_and_exact_manifest_files(self):
        for path in self.geo.iterdir():
            path.unlink()
        self.geo.rmdir()
        self.geo.parent.rmdir()
        self.seal()
        self.assertEqual(recovery.geo_inputs(str(self.source), str(self.destination)), {"geo_files": 0})
        self.geo.mkdir(parents=True, mode=0o700)
        self.rejected()
        self.seal()
        self.rejected()

    def test_state_schema_fixed_version_disabled_schedule_and_digest_contract(self):
        invalid = []
        for key, value in (("schema_version", True), ("enabled", True), ("enabled", 0),
                           ("version", "latest"), ("version", ""), ("version", "bad/tag"),
                           ("version", "x" * 129), ("sha256", {}),
                           ("sha256", {"geoip.dat": "A" * 64, "geosite.dat": "0" * 64})):
            state = copy.deepcopy(self.state)
            state[key] = value
            invalid.append(state)
        invalid.extend([dict(self.state, extra="unexpected"),
                        b'{"schema_version":1,"schema_version":1}', b"[]", b""])
        for state in invalid:
            with self.subTest(state=state):
                self.put_state(state)
                self.rejected()
        self.put_state(self.state)
        (self.geo / "geoip.dat").write_bytes(b"changed")
        self.seal()
        self.rejected()

    def test_missing_extra_empty_and_changed_manifest_data_rejected(self):
        path = self.geo / "geoip.dat"
        path.write_bytes(b"changed")
        self.rejected()
        path.write_bytes(self.payload[path.name])
        path.unlink()
        self.rejected()
        path.write_bytes(b"")
        path.chmod(0o600)
        self.state["sha256"][path.name] = recovery.hashlib.sha256(b"").hexdigest()
        self.put_state(self.state)
        self.rejected()
        path.write_bytes(self.payload[path.name])
        self.state["sha256"][path.name] = recovery.hashlib.sha256(path.read_bytes()).hexdigest()
        self.put_state(self.state)
        extra = self.geo / "extra"
        extra.write_bytes(b"extra")
        extra.chmod(0o600)
        self.rejected()
        self.seal()
        self.rejected()

    def test_size_boundaries_are_checked_before_streaming(self):
        path = self.geo / "geoip.dat"
        os.truncate(path, recovery.MAX_GEO_FILE + 1)
        with mock.patch.object(recovery, "geo_stream", side_effect=AssertionError("超限文件被读取")):
            self.rejected()
        path.write_bytes(self.payload[path.name])
        path = self.geo / "state.json"
        os.truncate(path, recovery.MAX_TRANSACTION_FILE + 1)
        inode = path.stat().st_ino
        original = os.read

        def bounded_read(fd, size):
            self.assertNotEqual(os.fstat(fd).st_ino, inode, "超限 state 被读取")
            return original(fd, size)

        with mock.patch.object(recovery.os, "read", side_effect=bounded_read):
            self.rejected()

    def test_unsafe_files_directories_and_links_rejected(self):
        path = self.geo / "geoip.dat"
        path.chmod(0o640)
        self.rejected()
        path.chmod(0o600)
        self.geo.chmod(0o750)
        self.rejected()
        self.geo.chmod(0o700)
        outside = self.root / "outside"
        path.rename(outside)
        path.symlink_to(outside)
        self.rejected()
        path.unlink()
        os.link(outside, path)
        self.rejected()
        path.unlink()
        path.mkdir()
        self.rejected()

    def test_stream_mutation_and_path_replacement_rejected_before_destination(self):
        path = self.geo / "geoip.dat"
        inode = path.stat().st_ino
        original = os.read

        def changed_read(fd, size):
            data = original(fd, size)
            if data and os.fstat(fd).st_ino == inode:
                path.write_bytes(b"changed")
            return data

        with mock.patch.object(recovery.os, "read", side_effect=changed_read):
            self.rejected()
        path.write_bytes(self.payload[path.name])
        self.seal()
        original_stream = recovery.geo_stream

        def replaced_stream(fd, size, target=None):
            digest = original_stream(fd, size, target)
            if os.fstat(fd).st_ino == inode and target is None:
                path.rename(self.root / "moved.dat")
                path.write_bytes(self.payload[path.name])
                path.chmod(0o600)
            return digest

        with mock.patch.object(recovery, "geo_stream", side_effect=replaced_stream):
            self.rejected()


class RecoveryTransactionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="padm-transaction-", dir=os.environ["TMPDIR"])
        self.addCleanup(self.directory.cleanup)
        self.base = Path(self.directory.name)
        self.root = self.base / "state"
        self.root.mkdir(mode=0o750)
        self.project = "padm-test"
        self.candidate = self.root / ".candidate.Abc123"
        self.candidate.mkdir(mode=0o750)
        self.source = {
            "compose.json": json.dumps({"name": self.project}).encode(),
            "images.runtime.env": b"XRAY_IMAGE=" + SECRET + b"\n",
            "deployment.json": json.dumps({"compose": {"project": self.project}}).encode(),
        }
        for name, data in self.source.items():
            path = self.candidate / name
            path.write_bytes(data)
            path.chmod(0o640)
        self.pending = self.root / recovery.TRANSACTION

    def prepare(self, stage=None):
        return recovery.transaction_prepare(str(self.root), self.project, str(self.candidate),
                                            str(stage) if stage is not None else None)

    def check(self):
        return recovery.transaction_check(str(self.root), self.project)

    def cli(self, action, *arguments):
        return subprocess.run(
            [sys.executable, "-B", str(HELPER), "transaction-" + action,
             "--root", str(self.root), "--project", self.project, *arguments],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
            env={**os.environ, "TMPDIR": str(self.base / "missing")},
        )

    def write_metadata(self, metadata, directory=None):
        path = (directory or self.pending) / recovery.TRANSACTION_METADATA
        path.write_bytes(recovery.transaction_encoded(metadata))

    def snapshot(self):
        snapshot = self.pending / "traffic-source"
        snapshot.mkdir(mode=0o700)
        return snapshot

    def save_schedule(self, snapshot):
        return recovery.transaction_schedule_save(
            str(self.root), self.project, str(snapshot), "/etc/systemd/system", 1, 0, 1,
        )

    def test_prepare_persists_private_copies_and_original_directory_metadata(self):
        (self.root / "config").mkdir(mode=0o750)
        (self.root / "secrets").mkdir(mode=0o700)
        stage = self.root / ".recovery.Def456"
        stage.mkdir(mode=0o700)
        metadata = self.prepare(stage)
        self.assertEqual(metadata["directories"]["config"],
                         {"exists": True, "mode": 0o750, "uid": 0, "gid": 0})
        self.assertEqual(metadata["directories"]["data"], {"exists": False})
        self.assertEqual(metadata["input_stage"], stage.name)
        self.assertEqual(self.check(), (metadata, None))
        self.assertEqual(stat.S_IMODE(self.pending.stat().st_mode), 0o700)
        for path in self.pending.iterdir():
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual((path.stat().st_uid, path.stat().st_gid, path.stat().st_nlink),
                             (0, 0, 1))
        self.assertEqual((self.pending / "images.env").read_bytes(), self.source["images.runtime.env"])
        for path in self.candidate.iterdir():
            path.unlink()
        self.candidate.rmdir()
        result = self.cli("check")
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(json.loads(result.stdout), {"state": "active"})
        result = self.cli("metadata")
        self.assertEqual(json.loads(result.stdout), metadata)
        self.assertNotIn(SECRET, result.stdout + result.stderr)

    def test_commit_is_atomic_idempotent_and_clean_removes_registration(self):
        self.prepare()
        original = recovery.transaction_write

        def interrupted_write(parent, name, data):
            original(parent, name, data)
            raise SystemExit(143)

        with mock.patch.object(recovery, "transaction_write", side_effect=interrupted_write):
            with self.assertRaises(SystemExit):
                recovery.transaction_commit(str(self.root), self.project)
        self.assertEqual(self.check()[0]["state"], "active")
        self.assertFalse((self.pending / recovery.TRANSACTION_NEXT).exists())
        self.assertEqual(list(self.root.glob(".restore-metadata-*")), [])
        recovery.transaction_commit(str(self.root), self.project)
        before = (self.pending / recovery.TRANSACTION_METADATA).stat().st_mtime_ns
        recovery.transaction_commit(str(self.root), self.project)
        self.assertEqual((self.pending / recovery.TRANSACTION_METADATA).stat().st_mtime_ns, before)
        self.assertEqual(self.check()[0]["state"], "committed")
        recovery.transaction_clean(str(self.root), self.project)
        self.assertFalse(self.pending.exists())
        self.assertTrue(self.candidate.is_dir())

    def test_sigkill_keeps_partial_writes_registered_and_cross_process_cleanable(self):
        script = """
import importlib.util
import os
import signal
import sys

spec = importlib.util.spec_from_file_location("recovery", sys.argv[1])
recovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recovery)
root, project, phase = sys.argv[2:]
write = recovery.transaction_write
replace = recovery.os.replace
rename = recovery.os.rename

def kill():
    os.kill(os.getpid(), signal.SIGKILL)

def interrupted_write(parent, name, data):
    if phase == "commit-partial" and name == recovery.TRANSACTION_NEXT:
        write(parent, name, data[:len(data) // 2])
        kill()
    if phase == "schedule-partial" and name == "crontab":
        write(parent, name, data[:len(data) // 2])
        kill()
    write(parent, name, data)
    if (phase == "commit-written" and name == recovery.TRANSACTION_NEXT
            or phase == "schedule-written" and name == recovery.TRANSACTION_METADATA):
        kill()

def interrupted_replace(*arguments, **keywords):
    replace(*arguments, **keywords)
    kill()

def interrupted_rename(*arguments, **keywords):
    rename(*arguments, **keywords)
    kill()

recovery.transaction_write = interrupted_write
if phase == "commit-published":
    recovery.os.replace = interrupted_replace
if phase == "schedule-published":
    recovery.os.rename = interrupted_rename
if phase.startswith("commit-"):
    recovery.transaction_commit(root, project)
else:
    recovery.transaction_schedule_save(root, project, root + "/.restore-pending/traffic-source",
                                       "/etc/systemd/system", 1, 0, 1)
raise AssertionError("kill point was not reached")
"""
        for phase in ("commit-partial", "commit-written", "commit-published",
                      "schedule-partial", "schedule-written", "schedule-published"):
            with self.subTest(phase=phase):
                self.prepare()
                if phase.startswith("schedule-"):
                    snapshot = self.snapshot()
                    for name in recovery.SCHEDULE_FILES:
                        path = snapshot / name
                        path.write_bytes(SECRET + name.encode())
                        path.chmod(0o600)
                result = subprocess.run(
                    [sys.executable, "-B", "-c", script, str(HELPER), str(self.root),
                     self.project, phase], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    check=False,
                )
                self.assertEqual(result.returncode, -signal.SIGKILL, result.stderr.decode())
                checked = self.cli("check")
                self.assertEqual(checked.returncode, 0, checked.stderr.decode())
                self.assertEqual(json.loads(checked.stdout),
                                 {"state": "committed" if phase == "commit-published" else "active"})
                schedule = self.cli("schedule-metadata")
                self.assertEqual(schedule.returncode, 0, schedule.stderr.decode())
                self.assertEqual(json.loads(schedule.stdout) is not None,
                                 phase == "schedule-published")
                if phase in ("commit-partial", "commit-written"):
                    self.assertTrue((self.pending / recovery.TRANSACTION_NEXT).is_file())
                if phase in ("schedule-partial", "schedule-written"):
                    self.assertTrue((self.pending / "traffic-building").is_dir())
                cleaned = self.cli("clean")
                self.assertEqual(cleaned.returncode, 0, cleaned.stderr.decode())
                self.assertFalse(self.pending.exists())
                self.assertFalse((self.root / recovery.TRANSACTION_CLEANING).exists())
                self.assertEqual(list(self.root.glob(".restore-*")), [])
                self.assertEqual(list((self.root / "locks").glob("*")), [])
                self.assertEqual((self.candidate / "images.runtime.env").read_bytes(),
                                 self.source["images.runtime.env"])
                self.assertNotIn(SECRET, result.stdout + result.stderr + checked.stdout
                                 + checked.stderr + schedule.stdout + schedule.stderr
                                 + cleaned.stdout + cleaned.stderr)

    def test_staging_rejects_unsafe_files_before_any_cleanup(self):
        self.prepare()
        metadata = (self.pending / recovery.TRANSACTION_METADATA).read_bytes()
        for staging in (recovery.TRANSACTION_NEXT, "traffic-source", "traffic-building"):
            directory = self.pending if staging == recovery.TRANSACTION_NEXT else self.pending / staging
            if directory != self.pending:
                directory.mkdir(mode=0o700)
            name = recovery.TRANSACTION_NEXT if directory == self.pending else "crontab"
            path = directory / name
            for kind in ("public", "owner", "hardlink", "symlink", "directory", "oversize"):
                with self.subTest(staging=staging, kind=kind):
                    path.write_bytes(SECRET)
                    path.chmod(0o600)
                    alias = self.base / "staging-alias"
                    if kind == "public":
                        path.chmod(0o640)
                    elif kind == "owner":
                        os.chown(path, 65534, 65534)
                    elif kind == "hardlink":
                        os.link(path, alias)
                    elif kind == "symlink":
                        path.unlink()
                        path.symlink_to(self.candidate / "images.runtime.env")
                    elif kind == "directory":
                        path.unlink()
                        path.mkdir(mode=0o700)
                    else:
                        limit = (recovery.MAX_TRANSACTION_METADATA if directory == self.pending
                                 else recovery.MAX_TRANSACTION_FILE)
                        with path.open("r+b") as target:
                            target.truncate(limit + 1)
                    before = path.lstat()
                    for action in (self.check, lambda: recovery.transaction_clean(str(self.root),
                                                                                self.project)):
                        with self.assertRaises((ValueError, OSError)):
                            action()
                        self.assertEqual((self.pending / recovery.TRANSACTION_METADATA).read_bytes(),
                                         metadata)
                        self.assertEqual(recovery.signature(path.lstat()),
                                         recovery.signature(before))
                    if alias.exists():
                        alias.unlink()
                    path.rmdir() if kind == "directory" else path.unlink()
            if directory != self.pending:
                extra = directory / "unregistered"
                extra.write_bytes(SECRET)
                extra.chmod(0o600)
                with self.assertRaises(ValueError):
                    self.check()
                extra.unlink()
                for kind in ("public", "owner", "symlink"):
                    with self.subTest(staging=staging, kind=kind):
                        if kind == "public":
                            directory.chmod(0o750)
                        elif kind == "owner":
                            os.chown(directory, 65534, 65534)
                        else:
                            directory.rmdir()
                            directory.symlink_to(self.candidate, target_is_directory=True)
                        with self.assertRaises((ValueError, OSError)):
                            self.check()
                        if kind == "symlink":
                            directory.unlink()
                            directory.mkdir(mode=0o700)
                        directory.chmod(0o700)
                        os.chown(directory, 0, 0)
                directory.rmdir()
        recovery.transaction_clean(str(self.root), self.project)

    def test_prepare_rejects_existing_registration_without_changing_it(self):
        self.prepare()
        before = {path.name: path.read_bytes() for path in self.pending.iterdir()}
        with self.assertRaises(ValueError):
            self.prepare()
        self.assertEqual({path.name: path.read_bytes() for path in self.pending.iterdir()}, before)

    def test_clean_retries_every_partial_unlink_without_touching_candidate(self):
        original = recovery.os.unlink
        cleaning = self.root / recovery.TRANSACTION_CLEANING
        for interrupted_after in range(1, 12):
            with self.subTest(interrupted_after=interrupted_after):
                self.prepare()
                snapshot = self.snapshot()
                for name in recovery.SCHEDULE_FILES:
                    path = snapshot / name
                    path.write_bytes(SECRET)
                    path.chmod(0o600)
                self.save_schedule(snapshot)
                count = 0

                def interrupted_unlink(*arguments, **keywords):
                    nonlocal count
                    original(*arguments, **keywords)
                    count += 1
                    if count == interrupted_after:
                        raise SystemExit(137)

                with mock.patch.object(recovery.os, "unlink", side_effect=interrupted_unlink):
                    with self.assertRaises(SystemExit):
                        recovery.transaction_clean(str(self.root), self.project)
                self.assertFalse(self.pending.exists())
                self.assertTrue(cleaning.is_dir())
                result = self.cli("clean")
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                self.assertFalse(cleaning.exists())
                self.assertEqual((self.candidate / "images.runtime.env").read_bytes(),
                                 self.source["images.runtime.env"])

    def test_prepare_reaps_interrupted_cleaning_before_new_registration(self):
        self.prepare()
        original = recovery.os.unlink

        def interrupted_unlink(*arguments, **keywords):
            original(*arguments, **keywords)
            raise SystemExit(137)

        with mock.patch.object(recovery.os, "unlink", side_effect=interrupted_unlink):
            with self.assertRaises(SystemExit):
                recovery.transaction_clean(str(self.root), self.project)
        self.prepare()
        self.assertEqual(self.check()[0]["state"], "active")
        self.assertFalse((self.root / recovery.TRANSACTION_CLEANING).exists())

    def test_clean_rejects_unsafe_tombstone_before_removing_anything(self):
        self.prepare()
        cleaning = self.root / recovery.TRANSACTION_CLEANING
        self.pending.rename(cleaning)
        path = cleaning / "images.env"
        original = path.read_bytes()
        for kind in ("public", "foreign", "hardlink", "symlink", "extra", "directory"):
            with self.subTest(kind=kind):
                if kind == "public":
                    path.chmod(0o640)
                elif kind == "foreign":
                    os.chown(path, 65534, 65534)
                elif kind == "hardlink":
                    os.link(path, self.base / "clean-alias")
                elif kind == "symlink":
                    path.unlink()
                    path.symlink_to(self.candidate / "images.runtime.env")
                elif kind == "extra":
                    (cleaning / "unregistered").write_bytes(SECRET)
                else:
                    path.unlink()
                    path.mkdir(mode=0o700)
                with self.assertRaises((ValueError, OSError)):
                    recovery.transaction_clean(str(self.root), self.project)
                self.assertEqual((cleaning / "compose.json").read_bytes(),
                                 self.source["compose.json"])
                if kind == "hardlink":
                    (self.base / "clean-alias").unlink()
                if kind == "extra":
                    (cleaning / "unregistered").unlink()
                if kind == "directory":
                    path.rmdir()
                if path.is_symlink():
                    path.unlink()
                path.write_bytes(original)
                path.chmod(0o600)
                os.chown(path, 0, 0)
        recovery.transaction_clean(str(self.root), self.project)
        with self.assertRaises(ValueError):
            recovery.transaction_clean(str(self.root), self.project)

    def test_prepare_rejects_nonempty_or_unsafe_skeleton(self):
        for kind in ("nonempty", "symlink", "public", "foreign"):
            with self.subTest(kind=kind):
                path = self.root / "data"
                if kind == "symlink":
                    path.symlink_to(self.candidate, target_is_directory=True)
                else:
                    path.mkdir(mode=0o750)
                    if kind == "nonempty":
                        (path / "sentinel").write_bytes(SECRET)
                    elif kind == "public":
                        path.chmod(0o777)
                    else:
                        os.chown(path, 65534, 65534)
                with self.assertRaises((ValueError, OSError)):
                    self.prepare()
                self.assertFalse(self.pending.exists())
                if kind == "nonempty":
                    self.assertEqual((path / "sentinel").read_bytes(), SECRET)
                    (path / "sentinel").unlink()
                path.unlink() if path.is_symlink() else path.rmdir()

    def test_prepare_rejects_unsafe_source_files_without_publishing(self):
        path = self.candidate / "images.runtime.env"
        for kind in ("symlink", "hardlink", "fifo", "public", "foreign", "oversize"):
            with self.subTest(kind=kind):
                path.unlink()
                alias = self.base / "source-alias"
                if kind == "symlink":
                    path.symlink_to(self.candidate / "compose.json")
                elif kind == "fifo":
                    os.mkfifo(path, 0o600)
                else:
                    path.write_bytes(SECRET)
                    path.chmod(0o640)
                    if kind == "hardlink":
                        os.link(path, alias)
                    elif kind == "public":
                        path.chmod(0o644)
                    elif kind == "foreign":
                        os.chown(path, 65534, 65534)
                    else:
                        with path.open("r+b") as target:
                            target.truncate(recovery.MAX_TRANSACTION_FILE + 1)
                with self.assertRaises((ValueError, OSError)):
                    self.prepare()
                self.assertFalse(self.pending.exists())
                self.assertEqual(list(self.root.glob(".restore-building-*")), [])
                if alias.exists():
                    alias.unlink()

    def test_prepare_rejects_wrong_candidate_project_and_escaping_paths(self):
        path = self.candidate / "compose.json"
        path.write_bytes(b'{"name":"another-project"}')
        with self.assertRaises(ValueError):
            self.prepare()
        path.write_bytes(self.source[path.name])
        for candidate in (self.base / self.candidate.name, self.root / ".." / self.candidate.name,
                          self.root / ".candidate.too-long"):
            with self.subTest(candidate=candidate):
                with self.assertRaises((ValueError, OSError)):
                    recovery.transaction_prepare(str(self.root), self.project, str(candidate))
        for stage in (self.candidate, self.base / ".recovery.Abc123"):
            with self.assertRaises(ValueError):
                self.prepare(stage)
        self.assertFalse(self.pending.exists())

    def test_prepare_failure_or_signal_never_publishes_partial_registration(self):
        original = recovery.transaction_write
        for failure in (ValueError("injected"), SystemExit(143)):
            count = 0

            def interrupted_write(parent, name, data):
                nonlocal count
                original(parent, name, data)
                count += 1
                if count == 2:
                    raise failure

            with self.subTest(failure=type(failure).__name__):
                with mock.patch.object(recovery, "transaction_write", side_effect=interrupted_write):
                    with self.assertRaises(type(failure)):
                        self.prepare()
                self.assertFalse(self.pending.exists())
                self.assertEqual(list(self.root.glob(".restore-building-*")), [])

    def test_prepare_rechecks_empty_skeleton_before_publish(self):
        original = recovery.transaction_validate

        def populate_skeleton(directory, root, project):
            result = original(directory, root, project)
            (self.root / "data").mkdir(mode=0o750)
            (self.root / "data/sentinel").write_bytes(SECRET)
            return result

        with mock.patch.object(recovery, "transaction_validate", side_effect=populate_skeleton):
            with self.assertRaises(ValueError):
                self.prepare()
        self.assertFalse(self.pending.exists())
        self.assertEqual((self.root / "data/sentinel").read_bytes(), SECRET)

    def test_check_rejects_malformed_or_mismatched_metadata(self):
        original = self.prepare()
        for key, value in (("schema_version", True), ("schema_version", 2),
                           ("root", "/other"), ("project", "other"), ("state", "unknown"),
                           ("candidate", "../escape"), ("input_stage", "bad"),
                           ("directories", {}), ("files", {}), ("unexpected", "value")):
            metadata = copy.deepcopy(original)
            metadata[key] = value
            self.write_metadata(metadata)
            with self.subTest(key=key, value=value):
                with self.assertRaises(ValueError):
                    self.check()
        self.write_metadata(original)
        path = self.pending / recovery.TRANSACTION_METADATA
        path.write_bytes(b'{"schema_version":1,' + path.read_bytes()[1:])
        with self.assertRaises(ValueError):
            self.check()

    def test_check_rejects_copy_tampering_and_unregistered_contents(self):
        metadata = self.prepare()
        path = self.pending / "images.env"
        original = path.read_bytes()
        for kind in ("content", "mode", "owner", "hardlink", "symlink", "extra"):
            with self.subTest(kind=kind):
                if kind == "content":
                    path.write_bytes(b"tampered")
                elif kind == "mode":
                    path.chmod(0o640)
                elif kind == "owner":
                    os.chown(path, 65534, 65534)
                elif kind == "hardlink":
                    os.link(path, self.base / "copy-alias")
                elif kind == "symlink":
                    path.unlink()
                    path.symlink_to(self.candidate / "images.runtime.env")
                else:
                    (self.pending / "extra").write_bytes(SECRET)
                with self.assertRaises((ValueError, OSError)):
                    self.check()
                if kind == "hardlink":
                    (self.base / "copy-alias").unlink()
                if kind == "extra":
                    (self.pending / "extra").unlink()
                if path.is_symlink():
                    path.unlink()
                path.write_bytes(original)
                path.chmod(0o600)
                os.chown(path, 0, 0)
        self.assertEqual(self.check()[0], metadata)

    def test_schedule_snapshot_is_private_persistent_and_single_use(self):
        self.prepare()
        result = self.cli("schedule-metadata")
        self.assertEqual(json.loads(result.stdout), None)
        snapshot = self.snapshot()
        for name in recovery.SCHEDULE_FILES:
            path = snapshot / name
            path.write_bytes(SECRET + name.encode())
            path.chmod(0o600)
        saved = self.save_schedule(snapshot)
        self.assertEqual(self.check()[1], saved)
        self.assertEqual(saved["snapshot"], snapshot.name)
        for name in recovery.SCHEDULE_FILES:
            path = self.pending / "traffic-schedule" / name
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(path.read_bytes(), SECRET + name.encode())
            (snapshot / name).unlink()
        snapshot.rmdir()
        self.assertEqual(json.loads(self.cli("schedule-metadata").stdout), saved)
        with self.assertRaises(ValueError):
            self.save_schedule(snapshot)
        recovery.transaction_clean(str(self.root), self.project)
        self.assertFalse(self.pending.exists())

    def test_schedule_empty_snapshot_and_committed_save_gate(self):
        self.prepare()
        snapshot = self.snapshot()
        saved = self.save_schedule(snapshot)
        self.assertEqual(saved["files"], {})
        recovery.transaction_commit(str(self.root), self.project)
        self.assertEqual(self.check()[1], saved)
        with self.assertRaises(ValueError):
            self.save_schedule(snapshot)

    def test_schedule_keeps_legacy_random_snapshot_metadata_readable(self):
        self.prepare()
        saved = self.save_schedule(self.snapshot())
        saved["snapshot"] = "traffic-schedule.Abc123"
        self.write_metadata(saved, self.pending / "traffic-schedule")
        self.assertEqual(self.check()[1], saved)
        recovery.transaction_clean(str(self.root), self.project)

    def test_schedule_rejects_unsafe_snapshot_or_tampered_registration(self):
        self.prepare()
        snapshot = self.snapshot()
        path = snapshot / "crontab"
        path.write_bytes(SECRET)
        path.chmod(0o666)
        with self.assertRaises(ValueError):
            self.save_schedule(snapshot)
        path.chmod(0o600)
        self.assertIsNone(self.check()[1])
        with self.assertRaises(ValueError):
            self.save_schedule(self.base / snapshot.name)
        self.save_schedule(snapshot)
        schedule = self.pending / "traffic-schedule"
        metadata = self.check()[1]
        metadata["timer_active"] = True
        self.write_metadata(metadata, schedule)
        with self.assertRaises(ValueError):
            self.check()

    def test_cli_rejection_does_not_disclose_private_contents(self):
        self.prepare()
        (self.pending / "images.env").write_bytes(SECRET + b"tampered")
        result = self.cli("check")
        self.assertEqual(result.returncode, 15)
        self.assertNotIn(SECRET, result.stdout + result.stderr)
        self.assertEqual(result.stdout, b"")


if __name__ == "__main__":
    unittest.main()
