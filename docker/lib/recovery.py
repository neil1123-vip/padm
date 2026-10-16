#!/usr/bin/env python3
"""受管部署输入的版本化归档与私密暂存；不执行部署恢复或信任判定。"""

import argparse
import contextlib
import datetime
import hashlib
import io
import json
import os
import platform
import re
import secrets
import signal
import stat
import sys
import tarfile


FORMAT = "padm-docker-recovery"
MANIFEST = "manifest.json"
MAX_ENTRIES = 16384
MAX_MANIFEST = 8 * 1024 * 1024
MAX_FILE = 512 * 1024 * 1024
MAX_TOTAL = 2 * 1024 * 1024 * 1024
CHUNK = 1024 * 1024
REQUIRED = {"mode", "deployment.json", "images.env", "compose.json", "config/spec.json"}
FILES = REQUIRED | {
    "config/share-groups.json",
    "data/traffic/state.json",
    "data/control-log/schedule.json",
    "data/reality-targets/blocked.tsv",
    "data/reality-targets/results.tsv",
    "secrets/net/wireguard/wg-padm.conf",
}
TREES = {
    "config/xray", "config/sing-box", "config/nginx", "config/net", "config/control",
    "data/subscription", "data/static", "data/acme",
    "secrets/tls", "secrets/renewal", "secrets/control-sync",
}


def require(condition):
    if not condition:
        raise ValueError("归档结构、范围、权限或内容校验失败")


def canonical(path):
    require(isinstance(path, str) and 0 < len(path) <= 255)
    require(all(32 <= ord(char) < 127 and char not in "\\:" for char in path))
    parts = path.split("/")
    require(all(part and part not in (".", "..") for part in parts))
    require(len(parts[-1]) <= 100 and len("/".join(parts[:-1])) <= 155)
    return path


def allowed(path, directory=False):
    canonical(path)
    if directory and any(item.startswith(path + "/") for item in FILES | TREES):
        return True
    return path in FILES or any(path == tree or path.startswith(tree + "/") for tree in TREES)


def excluded(path):
    # ACME 的账户和证书是输入；调用日志、锁与临时响应不是恢复输入。
    return path in {
        "data/acme/http.header", "data/acme/http.err", "data/acme/acme.log",
        "data/acme/acme.sh.log", "data/acme/.lock", "data/acme/acme.sh.lock",
    }


def safe_mode(path, directory, mode):
    if type(mode) is not int or not 0 <= mode <= 0o777 or mode & 0o22:
        return False
    if directory or path.startswith("data/static/"):
        return True
    private = path in {
        "config/spec.json", "config/share-groups.json", "data/traffic/state.json",
        "data/control-log/schedule.json", "data/reality-targets/results.tsv",
        "data/reality-targets/blocked.tsv", "data/subscription/users.base",
        "secrets/net/wireguard/wg-padm.conf",
    } or path.startswith(("data/acme/", "secrets/renewal/", "secrets/control-sync/"))
    private = private or path.startswith("secrets/tls/") and path.endswith(".key")
    return mode & ~(0o600 if private else 0o640) == 0


def no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result)
        result[key] = value
    return result


def read_json(data):
    return json.loads(data, object_pairs_hook=no_duplicates)


def signature(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_gid,
            info.st_size, info.st_mtime_ns, info.st_ctime_ns, info.st_nlink)


@contextlib.contextmanager
def opened(root_fd, relative, flags):
    parts = relative.split("/")
    parent = os.dup(root_fd)
    try:
        for part in parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
            os.close(parent)
            parent = child
        fd = os.open(parts[-1], flags | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600, dir_fd=parent)
        try:
            yield fd
        finally:
            os.close(fd)
    finally:
        os.close(parent)


@contextlib.contextmanager
def absolute_parent(path, private=False):
    require(isinstance(path, str) and path.startswith("/") and path != "/")
    parts = path.split("/")[1:]
    require(all(part and part not in (".", "..") for part in parts))
    # 遍历父路径只需搜索权限；O_RDONLY 会错误拒绝合法的 0711 私有父目录。
    parent = os.open("/", os.O_PATH | os.O_DIRECTORY)
    try:
        for part in parts[:-1]:
            child = os.open(part, os.O_PATH | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
            os.close(parent)
            parent = child
            if private:
                info = os.fstat(parent)
                require(info.st_uid == os.geteuid() and (
                    info.st_mode & 0o22 == 0 or
                    info.st_uid == 0 and info.st_mode & stat.S_ISVTX
                ))
        if private:
            info = os.fstat(parent)
            require(info.st_uid == os.geteuid() and info.st_mode & 0o22 == 0)
        yield parent, parts[-1]
    finally:
        os.close(parent)


def inventory(root_fd):
    records = {}
    total = 0

    def visit(path):
        nonlocal total
        if path in records or excluded(path):
            return
        canonical(path)
        try:
            with opened(root_fd, path, os.O_RDONLY) as fd:
                info = os.fstat(fd)
                directory = stat.S_ISDIR(info.st_mode)
                require(directory or stat.S_ISREG(info.st_mode))
                require(allowed(path, directory))
                require(info.st_uid in (0, 10001) and info.st_gid in (0, 10001))
                require(safe_mode(path, directory, stat.S_IMODE(info.st_mode)))
                require(directory or info.st_nlink == 1)
                require(directory or info.st_size <= MAX_FILE)
                names = sorted(os.listdir(fd)) if directory else []
        except FileNotFoundError:
            return
        records[path] = info
        require(len(records) <= MAX_ENTRIES)
        if not directory:
            total += info.st_size
            require(total <= MAX_TOTAL)
        for name in names:
            visit(path + "/" + name)

    for path in sorted(FILES | TREES):
        visit(path)
    require(REQUIRED <= records.keys())
    for path in list(records):
        parent = path.rpartition("/")[0]
        while parent:
            if parent not in records:
                with opened(root_fd, parent, os.O_RDONLY | os.O_DIRECTORY) as fd:
                    info = os.fstat(fd)
                require(info.st_uid in (0, 10001) and info.st_gid in (0, 10001))
                require(stat.S_IMODE(info.st_mode) & 0o7022 == 0)
                records[parent] = info
            parent = parent.rpartition("/")[0]
    require(len(records) <= MAX_ENTRIES)
    return records


class DigestReader:
    def __init__(self, source):
        self.source = source
        self.digest = hashlib.sha256()

    def read(self, size):
        data = self.source.read(size)
        self.digest.update(data)
        return data


def tar_info(path, directory, size=0, mode=0o600):
    info = tarfile.TarInfo(path)
    info.type = tarfile.DIRTYPE if directory else tarfile.REGTYPE
    info.mode = mode
    info.size = size
    return info


def export_archive(root, output):
    with absolute_parent(root) as (parent, name):
        root_fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
    try:
        records = inventory(root_fd)
        with absolute_parent(output, private=True) as (output_fd, output_name):
            try:
                os.stat(output_name, dir_fd=output_fd, follow_symlinks=False)
            except FileNotFoundError:
                pass
            else:
                raise FileExistsError("归档目标已存在")
            # 暂存文件以随机名在同目录创建，硬链接发布保证现有目标不会被覆盖。
            temporary = ".padm-recovery-" + secrets.token_hex(12)
            fd = os.open(temporary, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o600, dir_fd=output_fd)
            try:
                entries = []
                with os.fdopen(fd, "w+b") as target:
                    os.fchmod(target.fileno(), 0o600)
                    with tarfile.open(fileobj=target, mode="w", format=tarfile.USTAR_FORMAT) as archive:
                        for path, before in sorted(records.items()):
                            directory = stat.S_ISDIR(before.st_mode)
                            entry = {"path": path, "type": "directory" if directory else "file",
                                     "mode": stat.S_IMODE(before.st_mode), "size": 0,
                                     "sha256": None}
                            if directory:
                                archive.addfile(tar_info(path, True, mode=entry["mode"]))
                            else:
                                with opened(root_fd, path, os.O_RDONLY) as source_fd:
                                    require(signature(os.fstat(source_fd)) == signature(before))
                                    with os.fdopen(os.dup(source_fd), "rb") as source:
                                        reader = DigestReader(source)
                                        archive.addfile(tar_info(path, False, before.st_size,
                                                                 entry["mode"]), reader)
                                    require(signature(os.fstat(source_fd)) == signature(before))
                                entry.update(size=before.st_size, sha256=reader.digest.hexdigest())
                            entries.append(entry)
                        after = inventory(root_fd)
                        require(records.keys() == after.keys())
                        require(all(signature(before) == signature(after[path])
                                    for path, before in records.items()))
                        architecture = {"x86_64": "amd64", "aarch64": "arm64"}.get(platform.machine())
                        require(architecture is not None)
                        manifest = {"format": FORMAT, "schema_version": 1,
                                    "scope": "managed-inputs", "architecture": architecture,
                                    "created_at": datetime.datetime.now(datetime.timezone.utc).strftime(
                                        "%Y-%m-%dT%H:%M:%SZ"), "entries": entries}
                        encoded = json.dumps(manifest, ensure_ascii=True, separators=(",", ":")).encode()
                        require(len(encoded) <= MAX_MANIFEST)
                        # 清单在正文后写入，摘要来自实际归档字节，不重复读取大型 Geo 文件。
                        archive.addfile(tar_info(MANIFEST, False, len(encoded)), io.BytesIO(encoded))
                    target.flush()
                    os.fsync(target.fileno())
                    target.seek(0)
                    counts = verify_stream(target)
                    require(signature(os.stat(temporary, dir_fd=output_fd, follow_symlinks=False))
                            == signature(os.fstat(target.fileno())))
                    os.link(temporary, output_name, src_dir_fd=output_fd, dst_dir_fd=output_fd,
                            follow_symlinks=False)
            finally:
                os.unlink(temporary, dir_fd=output_fd)
    finally:
        os.close(root_fd)
    return counts


def validate_manifest(manifest):
    require(isinstance(manifest, dict) and set(manifest) == {
        "format", "schema_version", "scope", "architecture", "created_at", "entries"
    })
    require(manifest["format"] == FORMAT and type(manifest["schema_version"]) is int
            and manifest["schema_version"] == 1 and manifest["scope"] == "managed-inputs"
            and manifest["architecture"] in ("amd64", "arm64"))
    require(isinstance(manifest["created_at"], str)
            and re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", manifest["created_at"]))
    entries = manifest["entries"]
    require(isinstance(entries, list) and 0 < len(entries) <= MAX_ENTRIES)
    expected = {}
    total = 0
    for entry in entries:
        require(isinstance(entry, dict) and set(entry) == {"path", "type", "mode", "size", "sha256"})
        path = canonical(entry["path"])
        require(path not in expected and entry["type"] in ("file", "directory"))
        directory = entry["type"] == "directory"
        require(allowed(path, directory) and not excluded(path))
        require(safe_mode(path, directory, entry["mode"]))
        require(type(entry["size"]) is int and 0 <= entry["size"] <= MAX_FILE)
        require((directory and entry["size"] == 0 and entry["sha256"] is None) or
                (not directory and isinstance(entry["sha256"], str)
                 and re.fullmatch("[a-f0-9]{64}", entry["sha256"])))
        total += entry["size"]
        require(total <= MAX_TOTAL)
        expected[path] = entry
    require(list(expected) == sorted(expected) and REQUIRED <= expected.keys())
    require(all(expected[path]["type"] == "file" for path in REQUIRED))
    for path in expected:
        parent = path.rpartition("/")[0]
        require(not parent or parent in expected and expected[parent]["type"] == "directory")
    return expected


def read_exact(source, size):
    data = source.read(size)
    require(len(data) == size)
    return data


def next_header(source):
    header = read_exact(source, 512)
    if header == b"\0" * 512:
        tail = source.read(10240)
        require(512 <= len(tail) <= 10240 and len(tail) % 512 == 0 and not any(tail)
                and not source.read(1))
        return None
    # 只接受有界 USTAR；在读取正文前拒绝 PAX/GNU 扩展、稀疏文件、链接和设备。
    require(header[257:265] == b"ustar\00000")
    member = tarfile.TarInfo.frombuf(header, "ascii", "strict")
    require(member.type in (tarfile.REGTYPE, tarfile.DIRTYPE)
            and member.uid == 0 and member.gid == 0 and not member.uname and not member.gname
            and not member.linkname and member.mtime == 0)
    return member


def read_payload(source, size, digest=None, target=None):
    remaining = size
    while remaining:
        data = read_exact(source, min(remaining, CHUNK))
        if digest is not None:
            digest.update(data)
        if target is not None:
            target.write(data)
        remaining -= len(data)
    require(not any(read_exact(source, -size % 512)))


def verify_stream(source, directory_fd=None):
    observed = {}
    total = 0
    while True:
        member = next_header(source)
        require(member is not None)
        if member.name == MANIFEST:
            require(member.isfile() and member.mode == 0o600 and 0 < member.size <= MAX_MANIFEST)
            encoded = read_exact(source, member.size)
            expected = validate_manifest(read_json(encoded))
            require(not any(read_exact(source, -member.size % 512)))
            require(list(observed) == list(expected) and observed == expected)
            break
        directory = member.isdir()
        path = member.name[:-1] if directory and member.name.endswith("/") else member.name
        canonical(path)
        require(path not in observed and allowed(path, directory) and not excluded(path)
                and safe_mode(path, directory, member.mode)
                and 0 <= member.size <= MAX_FILE and (not directory or member.size == 0))
        total += member.size
        require(len(observed) < MAX_ENTRIES and total <= MAX_TOTAL)
        digest = hashlib.sha256()
        if directory_fd is None:
            read_payload(source, member.size, digest)
        else:
            parent, _, name = path.rpartition("/")
            require(not parent or parent in observed and observed[parent]["type"] == "directory")
            with (opened(directory_fd, parent, os.O_RDONLY | os.O_DIRECTORY) if parent
                  else contextlib.nullcontext(directory_fd)) as parent_fd:
                if directory:
                    os.mkdir(name, 0o700, dir_fd=parent_fd)
                else:
                    with opened(parent_fd, name, os.O_WRONLY | os.O_CREAT | os.O_EXCL) as fd:
                        with os.fdopen(os.dup(fd), "wb") as target:
                            read_payload(source, member.size, digest, target)
        observed[path] = {"path": path, "type": "directory" if directory else "file",
                          "mode": member.mode, "size": member.size,
                          "sha256": None if directory else digest.hexdigest()}
    require(next_header(source) is None)
    counts = (sum(entry["type"] == "file" for entry in expected.values()),
              sum(entry["size"] for entry in expected.values()))
    return counts if directory_fd is None else (counts, encoded)


def verify_archive(path, directory_fd=None):
    with absolute_parent(path) as (parent, name):
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
    with os.fdopen(fd, "rb") as source:
        before = os.fstat(source.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_uid == os.geteuid()
                and stat.S_IMODE(before.st_mode) & ~0o600 == 0 and before.st_nlink == 1
                and before.st_size <= MAX_TOTAL + MAX_MANIFEST + MAX_ENTRIES * 1024 + 10240)
        result = verify_stream(source, directory_fd)
        require(signature(os.fstat(source.fileno())) == signature(before))
        if directory_fd is None:
            return result
        counts, encoded = result
        # 清单只在完整归档及源文件稳定性校验通过后发布，失败暂存不能冒充已验证输入。
        with opened(directory_fd, MANIFEST, os.O_WRONLY | os.O_CREAT | os.O_EXCL) as fd:
            try:
                with os.fdopen(os.dup(fd), "wb") as target:
                    target.write(encoded)
            except BaseException:
                os.unlink(MANIFEST, dir_fd=directory_fd)
                raise
        return counts


def extract_archive(path, directory):
    with absolute_parent(directory) as (parent, name):
        directory_fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
    previous_umask = os.umask(0o077)
    try:
        info = os.fstat(directory_fd)
        require(info.st_uid == os.geteuid() and stat.S_IMODE(info.st_mode) == 0o700
                and not os.listdir(directory_fd))
        return verify_archive(path, directory_fd)
    finally:
        os.umask(previous_umask)
        os.close(directory_fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    export = commands.add_parser("export")
    export.add_argument("--root", required=True)
    export.add_argument("--output", required=True)
    verify = commands.add_parser("verify")
    verify.add_argument("--archive", required=True)
    extract = commands.add_parser("extract")
    extract.add_argument("--archive", required=True)
    extract.add_argument("--directory", required=True)
    args = parser.parse_args()
    try:
        if args.action == "export":
            counts = export_archive(args.root, args.output)
            print("灾备归档已导出（{} 个文件，{} 字节）。".format(*counts))
        elif args.action == "verify":
            counts = verify_archive(args.archive)
            print("灾备归档完整性校验通过（{} 个文件，{} 字节；未验证来源或恢复能力）。".format(*counts))
        else:
            counts = extract_archive(args.archive, args.directory)
            print("灾备归档已校验并解包至私密暂存目录（{} 个文件，{} 字节）。".format(*counts))
        return 0
    except (OSError, ValueError, TypeError, KeyError, RecursionError, tarfile.TarError):
        print("灾备归档拒绝：输入不安全、文件变化、归档损坏或范围不支持。", file=sys.stderr)
        return 15


def interrupted(signum, _frame):
    raise SystemExit(128 + signum)


if __name__ == "__main__":
    signal.signal(signal.SIGINT, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    sys.exit(main())
