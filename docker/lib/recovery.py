#!/usr/bin/env python3
"""受管部署输入归档、私密暂存及空目标恢复事务登记。"""

import argparse
import contextlib
import datetime
import hashlib
import io
import ipaddress
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
TRANSACTION = ".restore-pending"
TRANSACTION_CLEANING = ".restore-cleaning"
TRANSACTION_METADATA = "metadata.json"
TRANSACTION_NEXT = "metadata.next"
TRANSACTION_DIRECTORIES = ("config", "data", "secrets", "logs", "backups")
TRANSACTION_FILES = ("compose.json", "images.env", "deployment.json")
SCHEDULE_JOBS = {
    "traffic": ("padm-docker-traffic.service", "padm-docker-traffic.timer", "crontab"),
    "geo": ("padm-docker-geo.service", "padm-docker-geo.timer", "crontab"),
}
SCHEDULE_FILES = SCHEDULE_JOBS["traffic"]
TRANSACTION_STAGING = {
    name: set(files) | extra
    for job, files in SCHEDULE_JOBS.items()
    for name, extra in ((job + "-source", {"new.service", "new.timer"}),
                        (job + "-building", {TRANSACTION_METADATA}))
}
MAX_TRANSACTION_FILE = 16 * 1024 * 1024
MAX_TRANSACTION_METADATA = 64 * 1024
MAX_GEO_FILE = 128 * 1024 * 1024


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


def transaction_path(path):
    require(isinstance(path, str) and re.fullmatch(r"/[A-Za-z0-9._/-]+", path)
            and all(part and part not in (".", "..") for part in path.split("/")[1:]))
    return path


@contextlib.contextmanager
def transaction_root(root, project):
    transaction_path(root)
    require(os.geteuid() == 0 and isinstance(project, str)
            and re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,62}", project))
    with absolute_parent(root, private=True) as (parent, name):
        fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
    try:
        info = os.fstat(fd)
        require(info.st_uid == 0 and stat.S_IMODE(info.st_mode) & 0o7022 == 0)
        yield fd
    finally:
        os.close(fd)


@contextlib.contextmanager
def transaction_directory(parent, name, private=True):
    with opened(parent, name, os.O_RDONLY | os.O_DIRECTORY) as fd:
        info = os.fstat(fd)
        require(info.st_uid == 0 and (not private or (
            info.st_gid == 0 and stat.S_IMODE(info.st_mode) == 0o700)))
        require(stat.S_IMODE(info.st_mode) & 0o7022 == 0)
        yield fd


def transaction_read(parent, name, private=True, limit=MAX_TRANSACTION_FILE, source_mode=0o640):
    with opened(parent, name, os.O_RDONLY) as fd:
        before = os.fstat(fd)
        require(stat.S_ISREG(before.st_mode) and before.st_uid == 0
                and before.st_nlink == 1 and 0 <= before.st_size <= limit)
        mode = stat.S_IMODE(before.st_mode)
        if private:
            require(mode == 0o600 and before.st_gid == 0)
        else:
            require(mode & ~source_mode == 0)
        data = bytearray()
        while len(data) <= before.st_size:
            chunk = os.read(fd, min(CHUNK, before.st_size + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
        require(len(data) == before.st_size and signature(os.fstat(fd)) == signature(before))
        return bytes(data), {"size": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                             "mode": mode}


def transaction_write(parent, name, data):
    with opened(parent, name, os.O_WRONLY | os.O_CREAT | os.O_EXCL) as fd:
        os.fchmod(fd, 0o600)
        os.fchown(fd, 0, 0)
        with os.fdopen(os.dup(fd), "wb") as target:
            target.write(data)
            target.flush()
            os.fsync(fd)


def reality_host(value):
    if not 0 < len(value) <= 253:
        return False
    if re.fullmatch(r"[0-9]+(?:\.[0-9]+){3}", value):
        return all(len(part) <= 3 and int(part) <= 255 for part in value.split("."))
    return all(re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", part)
               for part in value.split("."))


def reality_records(name, data):
    text = data.decode("utf-8")
    require(all(char.isprintable() or char in "\t\n" for char in text))
    lines = text.split("\n")
    if lines[-1] == "":
        lines.pop()
    for line in lines:
        fields = line.split("|" if name == "blocked.tsv" else "\t")
        if name == "blocked.tsv":
            require(len(fields) == 4 and reality_host(fields[0]) and fields[2] != "")
            continue
        # 按列拆分保留中间和末尾空列；兼容历史 15 列，不去重或刷新探测结果。
        require(len(fields) in (15, 16))
        host, separator, port = fields[0].rpartition(":")
        require(separator == ":" and reality_host(host)
                and re.fullmatch(r"[0-9]{1,5}", port) and 1 <= int(port) <= 65535)
        require(reality_host(fields[1]))
        require(fields[4] in {"no", "unknown", "cdn_edge", "cloudflare_relay", "yes"})
        if fields[5] != "unknown":
            ipaddress.ip_address(fields[5])
        require(fields[6] == "unknown" or re.fullmatch(r"AS[0-9]+", fields[6]))
        require(fields[8] in {"same_asn", "same_provider", "different_network",
                              "scanner_local", "unknown", "auto_probe"})
        require(fields[9] in {"A", "B", "C", "FAIL", "unknown"})
        require(fields[10] in {"yes", "no", "unknown"})
        require(fields[11] == "unknown" or re.fullmatch(r"[0-9]+", fields[11]))
        require(fields[12] in {"yes", "no", "unknown"})
        require(re.fullmatch(r"[0-9]+", fields[13]))
    return len(lines)


def reality_inputs(directory, destination=None):
    payload = {}
    with absolute_parent(directory, private=True) as (parent, name):
        with transaction_directory(parent, name, private=False) as root_fd:
            manifest, _ = transaction_read(root_fd, MANIFEST, limit=MAX_MANIFEST)
            entries = validate_manifest(read_json(manifest))
            expected = {path.rsplit("/", 1)[1]: entry for path, entry in entries.items()
                        if path in {"data/reality-targets/results.tsv",
                                    "data/reality-targets/blocked.tsv"}}
            require(all(entry["type"] == "file" for entry in expected.values()))
            if "data" not in os.listdir(root_fd):
                require(not expected)
                return {"reality_results": 0, "reality_blocked": 0}
            with transaction_directory(root_fd, "data", private=False) as data_fd:
                if "reality-targets" not in os.listdir(data_fd):
                    require(not expected)
                    return {"reality_results": 0, "reality_blocked": 0}
                # 已观察到的库或文件消失必须报错，不能退化为合法缺库。
                with transaction_directory(data_fd, "reality-targets") as library_fd:
                    filenames = sorted(os.listdir(library_fd))
                    require(set(filenames) == set(expected))
                    for filename in filenames:
                        data, metadata = transaction_read(library_fd, filename)
                        require(all(metadata[key] == expected[filename][key]
                                    for key in ("size", "sha256")))
                        payload[filename] = (data, reality_records(filename, data))
    if destination is not None and payload:
        with absolute_parent(destination, private=True) as (parent, name):
            with transaction_directory(parent, name, private=False) as root_fd:
                with transaction_directory(root_fd, "data", private=False) as data_fd:
                    os.mkdir("reality-targets", 0o700, dir_fd=data_fd)
                    with transaction_directory(data_fd, "reality-targets") as library_fd:
                        for filename, (data, _) in payload.items():
                            transaction_write(library_fd, filename, data)
    return {"reality_results": payload.get("results.tsv", (None, 0))[1],
            "reality_blocked": payload.get("blocked.tsv", (None, 0))[1]}


def geo_stream(fd, size, target=None):
    os.lseek(fd, 0, os.SEEK_SET)
    digest = hashlib.sha256()
    consumed = 0
    while consumed <= size:
        data = os.read(fd, min(CHUNK, size + 1 - consumed))
        if not data:
            break
        digest.update(data)
        consumed += len(data)
        if target is not None:
            target.write(data)
    require(consumed == size)
    return digest.hexdigest()


def geo_inputs(directory, destination=None):
    filenames = {"state.json", "geoip.dat", "geosite.dat"}
    prefix = "config/xray/geo"
    with absolute_parent(directory, private=True) as (parent, name):
        with transaction_directory(parent, name, private=False) as root_fd:
            observed = [(parent, name, signature(os.fstat(root_fd)))]
            manifest_info = os.stat(MANIFEST, dir_fd=root_fd, follow_symlinks=False)
            manifest, _ = transaction_read(root_fd, MANIFEST, limit=MAX_MANIFEST)
            observed.append((root_fd, MANIFEST, signature(manifest_info)))
            entries = validate_manifest(read_json(manifest))
            expected = {path: entry for path, entry in entries.items()
                        if path == prefix or path.startswith(prefix + "/")}
            require(not expected or set(expected) == {prefix} | {
                prefix + "/" + filename for filename in filenames})
            require(not expected or expected[prefix]["type"] == "directory" and
                    all(expected[prefix + "/" + filename]["type"] == "file"
                        for filename in filenames))
            with transaction_directory(root_fd, "config", private=False) as config_fd:
                if "xray" not in os.listdir(config_fd):
                    require(not expected)
                    return {"geo_files": 0}
                with transaction_directory(config_fd, "xray", private=False) as xray_fd:
                    if "geo" not in os.listdir(xray_fd):
                        require(not expected)
                        return {"geo_files": 0}
                    with transaction_directory(xray_fd, "geo") as geo_fd:
                        require(expected and set(os.listdir(geo_fd)) == filenames)
                        observed.extend((owner, child, signature(os.fstat(fd))) for owner, child, fd in (
                            (root_fd, "config", config_fd), (config_fd, "xray", xray_fd),
                            (xray_fd, "geo", geo_fd)))
                        state_info = os.stat("state.json", dir_fd=geo_fd, follow_symlinks=False)
                        encoded, metadata = transaction_read(geo_fd, "state.json")
                        observed.append((geo_fd, "state.json", signature(state_info)))
                        require(all(metadata[key] == expected[prefix + "/state.json"][key]
                                    for key in ("size", "sha256")))
                        state = read_json(encoded)
                        require(isinstance(state, dict) and set(state) == {
                            "schema_version", "version", "enabled", "sha256"})
                        require(type(state["schema_version"]) is int and state["schema_version"] == 1
                                and type(state["enabled"]) is bool)
                        require(isinstance(state["version"], str) and len(state["version"]) <= 128
                                and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", state["version"])
                                and state["version"] != "latest")
                        require(isinstance(state["sha256"], dict)
                                and set(state["sha256"]) == filenames - {"state.json"}
                                and all(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value)
                                        for value in state["sha256"].values()))
                        with contextlib.ExitStack() as stack:
                            sources = {}
                            for filename in sorted(filenames - {"state.json"}):
                                fd = stack.enter_context(opened(geo_fd, filename, os.O_RDONLY))
                                info = os.fstat(fd)
                                require(stat.S_ISREG(info.st_mode) and info.st_uid == info.st_gid == 0
                                        and stat.S_IMODE(info.st_mode) == 0o600 and info.st_nlink == 1
                                        and 0 < info.st_size <= MAX_GEO_FILE)
                                observed.append((geo_fd, filename, signature(info)))
                                entry = expected[prefix + "/" + filename]
                                require(info.st_size == entry["size"] and
                                        geo_stream(fd, info.st_size) == entry["sha256"] ==
                                        state["sha256"][filename])
                                sources[filename] = (fd, info)

                            def stable():
                                require(set(os.listdir(geo_fd)) == filenames)
                                for owner, child, before in observed:
                                    require(signature(os.stat(child, dir_fd=owner,
                                                              follow_symlinks=False)) == before)
                                for fd, before in sources.values():
                                    require(signature(os.fstat(fd)) == signature(before))
                                with absolute_parent(directory, private=True) as (owner, child):
                                    require(signature(os.stat(child, dir_fd=owner,
                                                              follow_symlinks=False)) == observed[0][2])

                            stable()
                            if destination is not None:
                                with absolute_parent(destination, private=True) as (owner, child):
                                    with transaction_directory(owner, child, private=False) as target_fd:
                                        with transaction_directory(target_fd, "config/xray",
                                                                   private=False) as target_xray:
                                            os.mkdir("geo", 0o700, dir_fd=target_xray)
                                            with transaction_directory(target_xray, "geo") as target_geo:
                                                transaction_write(target_geo, "state.json", encoded)
                                                # 数据文件保持有界流式读写；候选失败由现有恢复清理统一回收。
                                                for filename, (fd, info) in sources.items():
                                                    with opened(target_geo, filename,
                                                                os.O_WRONLY | os.O_CREAT | os.O_EXCL) as output:
                                                        os.fchmod(output, 0o600)
                                                        os.fchown(output, 0, 0)
                                                        with os.fdopen(os.dup(output), "wb") as target:
                                                            require(geo_stream(fd, info.st_size, target) ==
                                                                    state["sha256"][filename])
                                                            target.flush()
                                                            os.fsync(output)
                            stable()
    return {"geo_files": 3}


def renewal_request(domain, data):
    request = read_json(data)
    require(isinstance(request, dict) and set(request) == {
        "schema_version", "domain", "email", "provider", "enabled"})
    require(request["domain"] == domain and request["enabled"] is False
            and type(request["schema_version"]) is int
            and isinstance(request["provider"], str) and isinstance(request["email"], str))
    require(re.fullmatch(r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}",
                         request["email"]))
    provider = request["provider"]
    require((request["schema_version"] == 1 and re.fullmatch(r"dns_[a-z0-9_]+", provider))
            or (request["schema_version"], provider) in {
                (2, "standalone"), (3, "webroot"), (4, "alpn")})
    return provider.startswith("dns_")


def renewal_credentials(data):
    names = set()
    for line in data.decode("utf-8").split("\n"):
        line = line.removesuffix("\r")
        if not line or line.startswith("#"):
            continue
        name, separator, _ = line.partition("=")
        require(separator and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name)
                and name not in names and name not in {
                    "PATH", "HOME", "ENV", "BASH_ENV", "IFS", "SHELLOPTS", "BASHOPTS",
                    "CDPATH", "GLOBIGNORE", "PS4", "DEBUG", "TMPDIR"}
                and not name.startswith(("PYTHON", "LD_", "PADM_", "LE_", "ACME_", "Le_")))
        require("\x00" not in line)
        names.add(name)
    require(names)


def renewal_inputs(directory, destination=None):
    prefix = "secrets/renewal"
    payload = {}
    total = 0
    with contextlib.ExitStack() as stack:
        parent, name = stack.enter_context(absolute_parent(directory, private=True))
        root_fd = stack.enter_context(transaction_directory(parent, name, private=False))
        observed = [(parent, name, signature(os.fstat(root_fd)))]
        manifest_info = os.stat(MANIFEST, dir_fd=root_fd, follow_symlinks=False)
        manifest, _ = transaction_read(root_fd, MANIFEST, limit=MAX_MANIFEST)
        observed.append((root_fd, MANIFEST, signature(manifest_info)))
        entries = validate_manifest(read_json(manifest))
        expected = {path: entry for path, entry in entries.items()
                    if path == prefix or path.startswith(prefix + "/")}
        if "secrets" not in os.listdir(root_fd):
            require(not expected)
            return {"renewal_registrations": 0}
        secrets_fd = stack.enter_context(transaction_directory(root_fd, "secrets", private=False))
        if "renewal" not in os.listdir(secrets_fd):
            require(not expected)
            return {"renewal_registrations": 0}
        registry_fd = stack.enter_context(transaction_directory(secrets_fd, "renewal"))
        observed.extend((owner, child, signature(os.fstat(fd))) for owner, child, fd in (
            (root_fd, "secrets", secrets_fd), (secrets_fd, "renewal", registry_fd)))
        require(prefix in expected and expected[prefix]["type"] == "directory")
        found = {prefix}
        domains = sorted(os.listdir(registry_fd))
        for domain in domains:
            require(len(domain) <= 253 and re.fullmatch(
                r"(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}", domain))
            domain_path = prefix + "/" + domain
            require(domain_path in expected and expected[domain_path]["type"] == "directory")
            domain_fd = stack.enter_context(transaction_directory(registry_fd, domain))
            observed.append((registry_fd, domain, signature(os.fstat(domain_fd))))
            found.add(domain_path)
            files = set(os.listdir(domain_fd))
            require(files in ({"request.json"}, {"request.json", "credentials.env"}))
            data = {}
            for filename in sorted(files):
                path = domain_path + "/" + filename
                require(path in expected and expected[path]["type"] == "file")
                info = os.stat(filename, dir_fd=domain_fd, follow_symlinks=False)
                encoded, metadata = transaction_read(domain_fd, filename, limit=(
                    64 * 1024 if filename == "request.json" else 1024 * 1024))
                require(all(metadata[key] == expected[path][key] for key in ("size", "sha256")))
                total += len(encoded)
                require(total <= MAX_TRANSACTION_FILE)
                observed.append((domain_fd, filename, signature(info)))
                data[filename] = encoded
                found.add(path)
            dns = renewal_request(domain, data["request.json"])
            require(dns == ("credentials.env" in data))
            if dns:
                renewal_credentials(data["credentials.env"])
            payload[domain] = data
        require(found == set(expected))

        def stable():
            require(set(os.listdir(registry_fd)) == set(domains))
            for owner, child, before in observed:
                require(signature(os.stat(child, dir_fd=owner, follow_symlinks=False)) == before)
            with absolute_parent(directory, private=True) as (owner, child):
                require(signature(os.stat(child, dir_fd=owner, follow_symlinks=False)) == observed[0][2])

        stable()
        if destination is not None:
            owner, child = stack.enter_context(absolute_parent(destination, private=True))
            target_fd = stack.enter_context(transaction_directory(owner, child, private=False))
            secrets_fd = stack.enter_context(transaction_directory(target_fd, "secrets", private=False))
            os.mkdir("renewal", 0o700, dir_fd=secrets_fd)
            target_registry = stack.enter_context(transaction_directory(secrets_fd, "renewal"))
            # 登记保持停用和原字节；账户执行配置与宿主调度不属于本阶段恢复范围。
            for domain, data in payload.items():
                os.mkdir(domain, 0o700, dir_fd=target_registry)
                with transaction_directory(target_registry, domain) as target_domain:
                    for filename, encoded in data.items():
                        transaction_write(target_domain, filename, encoded)
        stable()
    return {"renewal_registrations": len(payload)}


def transaction_encoded(metadata):
    data = json.dumps(metadata, ensure_ascii=True, separators=(",", ":")).encode()
    require(len(data) <= MAX_TRANSACTION_METADATA)
    return data


def transaction_directories(root_fd):
    result = {}
    for name in TRANSACTION_DIRECTORIES:
        try:
            with transaction_directory(root_fd, name, private=False) as fd:
                info = os.fstat(fd)
                require(not os.listdir(fd))
                result[name] = {"exists": True, "mode": stat.S_IMODE(info.st_mode),
                                "uid": info.st_uid, "gid": info.st_gid}
        except FileNotFoundError:
            result[name] = {"exists": False}
    return result


def transaction_validate_directories(directories):
    require(isinstance(directories, dict) and set(directories) == set(TRANSACTION_DIRECTORIES))
    for entry in directories.values():
        require(isinstance(entry, dict) and type(entry.get("exists")) is bool)
        if entry["exists"]:
            require(set(entry) == {"exists", "mode", "uid", "gid"}
                    and type(entry["mode"]) is int and 0 <= entry["mode"] <= 0o777
                    and entry["mode"] & 0o22 == 0 and type(entry["uid"]) is int
                    and entry["uid"] == 0 and type(entry["gid"]) is int
                    and 0 <= entry["gid"] < 2 ** 32 - 1)
        else:
            require(set(entry) == {"exists"})


def transaction_validate_files(directory_fd, files, names, required=True):
    require(isinstance(files, dict) and (set(files) == set(names) if required
                                        else set(files) <= set(names)))
    for name, entry in files.items():
        require(isinstance(entry, dict) and set(entry) == {"size", "sha256", "mode"}
                and type(entry["size"]) is int and 0 <= entry["size"] <= MAX_TRANSACTION_FILE
                and entry["mode"] == 0o600 and type(entry["mode"]) is int
                and isinstance(entry["sha256"], str)
                and re.fullmatch(r"[a-f0-9]{64}", entry["sha256"]))
        _, observed = transaction_read(directory_fd, name)
        require(observed == entry)


def transaction_schedule(directory_fd, root, project, job="traffic"):
    require(job in SCHEDULE_JOBS)
    if job + "-schedule" not in os.listdir(directory_fd):
        return None
    with transaction_directory(directory_fd, job + "-schedule") as schedule_fd:
        data, _ = transaction_read(schedule_fd, TRANSACTION_METADATA,
                                   limit=MAX_TRANSACTION_METADATA)
        metadata = read_json(data)
        require(isinstance(metadata, dict) and set(metadata) == {
            "schema_version", "root", "project", "unit_dir", "systemd_ready",
            "timer_enabled", "timer_active", "snapshot", "files"
        } and type(metadata["schema_version"]) is int and metadata["schema_version"] == 1
                and metadata["root"] == root and metadata["project"] == project)
        transaction_path(metadata["unit_dir"])
        require(isinstance(metadata["snapshot"], str)
                and (metadata["snapshot"] == job + "-source" or job == "traffic"
                     and re.fullmatch(r"traffic-schedule\.[A-Za-z0-9]{6}", metadata["snapshot"])))
        require(all(type(metadata[key]) is int and metadata[key] in (0, 1)
                    for key in ("systemd_ready", "timer_enabled", "timer_active")))
        transaction_validate_files(schedule_fd, metadata["files"], SCHEDULE_JOBS[job], required=False)
        require(set(os.listdir(schedule_fd)) == {TRANSACTION_METADATA} | set(metadata["files"]))
        return metadata


def transaction_staging(directory_fd):
    names = set(os.listdir(directory_fd))
    if TRANSACTION_NEXT in names:
        transaction_read(directory_fd, TRANSACTION_NEXT, limit=MAX_TRANSACTION_METADATA)
    for name, files in TRANSACTION_STAGING.items():
        if name not in names:
            continue
        with transaction_directory(directory_fd, name) as fd:
            entries = set(os.listdir(fd))
            require(entries <= files)
            for entry in entries:
                transaction_read(fd, entry, limit=MAX_TRANSACTION_METADATA
                                 if entry == TRANSACTION_METADATA else MAX_TRANSACTION_FILE)
    return names & ({TRANSACTION_NEXT} | set(TRANSACTION_STAGING))


def transaction_validate(directory_fd, root, project, metadata_name=TRANSACTION_METADATA):
    names = set(os.listdir(directory_fd))
    if metadata_name == TRANSACTION_METADATA and TRANSACTION_METADATA not in names:
        # 首次登记发布前尚未创建任何暂存，只回收空 marker 或有界半写元数据。
        require(names <= {TRANSACTION_NEXT})
        if TRANSACTION_NEXT in names:
            transaction_read(directory_fd, TRANSACTION_NEXT, limit=MAX_TRANSACTION_METADATA)
        return {"state": "unpublished"}, None
    data, _ = transaction_read(directory_fd, metadata_name, limit=MAX_TRANSACTION_METADATA)
    metadata = read_json(data)
    require(isinstance(metadata, dict) and set(metadata) == {
        "schema_version", "root", "project", "state", "directories", "files",
        "candidate", "input_stage"
    } and type(metadata["schema_version"]) is int and metadata["schema_version"] == 1
            and metadata["root"] == root and metadata["project"] == project
            and metadata["state"] in ("preparing", "active", "committed"))
    require(isinstance(metadata["candidate"], str)
            and re.fullmatch(r"\.candidate\.[A-Za-z0-9]{6}", metadata["candidate"]))
    require(metadata["input_stage"] is None or isinstance(metadata["input_stage"], str)
            and re.fullmatch(r"\.recovery\.[A-Za-z0-9]{6}", metadata["input_stage"]))
    transaction_validate_directories(metadata["directories"])
    if metadata["state"] == "preparing":
        require(metadata["files"] == {} and
                names <= {TRANSACTION_METADATA, TRANSACTION_NEXT} | set(TRANSACTION_FILES))
        for name in names - {TRANSACTION_METADATA}:
            transaction_read(directory_fd, name, limit=MAX_TRANSACTION_METADATA
                             if name == TRANSACTION_NEXT else MAX_TRANSACTION_FILE)
        return metadata, None
    transaction_validate_files(directory_fd, metadata["files"], TRANSACTION_FILES)
    schedules = {job: transaction_schedule(directory_fd, root, project, job)
                 for job in SCHEDULE_JOBS}
    staging = transaction_staging(directory_fd)
    require(set(os.listdir(directory_fd)) == {TRANSACTION_METADATA} | set(TRANSACTION_FILES)
            | {job + "-schedule" for job, saved in schedules.items() if saved is not None} | staging)
    return metadata, schedules["traffic"]


def transaction_begin(root, project, candidate=None, input_stage=None):
    with transaction_root(root, project) as root_fd:
        require(TRANSACTION not in os.listdir(root_fd))
        transaction_reap(root_fd)
        directories = transaction_directories(root_fd)
        if candidate is None:
            candidate = root + "/.candidate." + secrets.token_hex(3)
            input_stage = root + "/.recovery." + secrets.token_hex(3)
            require(all(os.path.basename(path) not in os.listdir(root_fd)
                        for path in (candidate, input_stage)))
        for path, pattern in ((candidate, r"\.candidate\.[A-Za-z0-9]{6}"),
                              (input_stage, r"\.recovery\.[A-Za-z0-9]{6}")):
            if path is not None:
                transaction_path(path)
                require(os.path.dirname(path) == root
                        and re.fullmatch(pattern, os.path.basename(path)))
        metadata = {"schema_version": 1, "root": root, "project": project,
                    "state": "preparing", "directories": directories, "files": {},
                    "candidate": os.path.basename(candidate),
                    "input_stage": os.path.basename(input_stage) if input_stage else None}
        # 固定 marker 先落盘；元数据发布后，调用者才能创建登记中的精确目录。
        os.mkdir(TRANSACTION, 0o700, dir_fd=root_fd)
        os.fsync(root_fd)
        with transaction_directory(root_fd, TRANSACTION) as fd:
            transaction_write(fd, TRANSACTION_NEXT, transaction_encoded(metadata))
            os.replace(TRANSACTION_NEXT, TRANSACTION_METADATA, src_dir_fd=fd, dst_dir_fd=fd)
            os.fsync(fd)
        os.fsync(root_fd)
    return metadata


def transaction_preparing_paths(root_fd, metadata):
    require(transaction_directories(root_fd) == metadata["directories"])

    def check_tree(parent, name, top=False, private=False):
        with opened(parent, name, os.O_RDONLY | os.O_DIRECTORY) as fd:
            info = os.fstat(fd)
            require(info.st_uid in ((0,) if top else (0, 10001))
                    and info.st_gid in (0, 10001) and stat.S_IMODE(info.st_mode) & 0o7022 == 0)
            if private:
                require(info.st_gid == 0 and stat.S_IMODE(info.st_mode) == 0o700)
            for child in os.listdir(fd):
                info = os.stat(child, dir_fd=fd, follow_symlinks=False)
                if stat.S_ISDIR(info.st_mode):
                    check_tree(fd, child)
                else:
                    require(stat.S_ISREG(info.st_mode) and info.st_uid in (0, 10001)
                            and info.st_gid in (0, 10001) and info.st_nlink == 1
                            and stat.S_IMODE(info.st_mode) & 0o7022 == 0)

    for key in ("candidate", "input_stage"):
        name = metadata[key]
        if name is not None and name in os.listdir(root_fd):
            check_tree(root_fd, name, top=True, private=key == "input_stage")


def transaction_remove_files(parent, name):
    # 仅清理本进程新建或完整校验后的固定文件集合，不递归跟随路径。
    with transaction_directory(parent, name) as fd:
        for item in os.listdir(fd):
            os.unlink(item, dir_fd=fd)
        os.fsync(fd)
    os.rmdir(name, dir_fd=parent)
    os.fsync(parent)


def transaction_reap(root_fd):
    if TRANSACTION_CLEANING not in os.listdir(root_fd):
        return False
    with transaction_directory(root_fd, TRANSACTION_CLEANING) as fd:
        names = set(os.listdir(fd))
        schedules = {job + "-schedule": set(files) for job, files in SCHEDULE_JOBS.items()}
        directories = set(schedules) | set(TRANSACTION_STAGING)
        require(names <= {TRANSACTION_METADATA, TRANSACTION_NEXT} | directories | set(TRANSACTION_FILES))
        for name in names - directories:
            transaction_read(fd, name, limit=MAX_TRANSACTION_METADATA
                             if name in (TRANSACTION_METADATA, TRANSACTION_NEXT) else MAX_TRANSACTION_FILE)
        for directory in names & directories:
            with transaction_directory(fd, directory) as schedule_fd:
                entries = set(os.listdir(schedule_fd))
                allowed_files = (TRANSACTION_STAGING[directory] if directory in TRANSACTION_STAGING
                                 else {TRANSACTION_METADATA} | schedules[directory])
                require(entries <= allowed_files)
                for name in entries:
                    transaction_read(schedule_fd, name, limit=MAX_TRANSACTION_METADATA
                                     if name == TRANSACTION_METADATA else MAX_TRANSACTION_FILE)
        for directory in names & directories:
            transaction_remove_files(fd, directory)
        for name in names - directories:
            os.unlink(name, dir_fd=fd)
        os.fsync(fd)
    os.rmdir(TRANSACTION_CLEANING, dir_fd=root_fd)
    os.fsync(root_fd)
    return True


def transaction_prepare(root, project, candidate, input_stage=None):
    transaction_path(candidate)
    require(os.path.dirname(candidate) == root
            and re.fullmatch(r"\.candidate\.[A-Za-z0-9]{6}", os.path.basename(candidate)))
    if input_stage is not None:
        transaction_path(input_stage)
        require(os.path.dirname(input_stage) == root
                and re.fullmatch(r"\.recovery\.[A-Za-z0-9]{6}", os.path.basename(input_stage)))
    started = False
    with transaction_root(root, project) as root_fd:
        if TRANSACTION not in os.listdir(root_fd):
            # 保留内部 helper 的单次 prepare 调用，失败只清本次登记，不接管来源目录。
            transaction_begin(root, project, candidate, input_stage)
            started = True
        try:
            if input_stage is not None:
                with transaction_directory(root_fd, os.path.basename(input_stage)):
                    pass
            with transaction_directory(root_fd, TRANSACTION) as pending_fd:
                saved, _ = transaction_validate(pending_fd, root, project)
                require(saved["state"] == "preparing"
                        and saved["candidate"] == os.path.basename(candidate)
                        and saved["input_stage"] ==
                        (os.path.basename(input_stage) if input_stage else None)
                        and transaction_directories(root_fd) == saved["directories"]
                        and set(os.listdir(pending_fd)) == {TRANSACTION_METADATA})
                with transaction_directory(root_fd, os.path.basename(candidate),
                                           private=False) as candidate_fd:
                    files = {}
                    for name in TRANSACTION_FILES:
                        source = "images.runtime.env" if name == "images.env" else name
                        data, _ = transaction_read(candidate_fd, source, private=False)
                        if name in ("compose.json", "deployment.json"):
                            value = read_json(data)
                            require(isinstance(value, dict))
                            require(value.get("name") == project if name == "compose.json" else
                                    isinstance(value.get("compose"), dict)
                                    and value["compose"].get("project") == project)
                        transaction_write(pending_fd, name, data)
                        files[name] = {"size": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                                       "mode": 0o600}
                    metadata = {**saved, "state": "active", "files": files}
                    transaction_write(pending_fd, TRANSACTION_NEXT, transaction_encoded(metadata))
                    transaction_validate(pending_fd, root, project, TRANSACTION_NEXT)
                    require(transaction_directories(root_fd) == saved["directories"])
                    os.replace(TRANSACTION_NEXT, TRANSACTION_METADATA,
                               src_dir_fd=pending_fd, dst_dir_fd=pending_fd)
                    os.fsync(pending_fd)
                os.fsync(root_fd)
        except BaseException:
            if started:
                transaction_remove_files(root_fd, TRANSACTION)
            raise
    return metadata


def transaction_check(root, project, job="traffic"):
    require(job in SCHEDULE_JOBS)
    with transaction_root(root, project) as root_fd:
        with transaction_directory(root_fd, TRANSACTION) as fd:
            metadata, schedule = transaction_validate(fd, root, project)
            if metadata["state"] == "preparing":
                transaction_preparing_paths(root_fd, metadata)
            if job != "traffic":
                schedule = transaction_schedule(fd, root, project, job)
            return metadata, schedule


def transaction_commit(root, project):
    with transaction_root(root, project) as root_fd:
        with transaction_directory(root_fd, TRANSACTION) as fd:
            metadata, _ = transaction_validate(fd, root, project)
            require(metadata["state"] in ("active", "committed"))
            if metadata["state"] == "committed":
                return
            metadata["state"] = "committed"
            # 半写只存在于已登记私密目录，不能成为提交依据或遗留到部署根。
            if TRANSACTION_NEXT in os.listdir(fd):
                os.unlink(TRANSACTION_NEXT, dir_fd=fd)
            try:
                transaction_write(fd, TRANSACTION_NEXT, transaction_encoded(metadata))
                os.replace(TRANSACTION_NEXT, TRANSACTION_METADATA, src_dir_fd=fd, dst_dir_fd=fd)
                os.fsync(fd)
                os.fsync(root_fd)
            finally:
                if TRANSACTION_NEXT in os.listdir(fd):
                    os.unlink(TRANSACTION_NEXT, dir_fd=fd)


def transaction_clean(root, project):
    with transaction_root(root, project) as root_fd:
        if TRANSACTION not in os.listdir(root_fd):
            require(transaction_reap(root_fd))
            return
        require(TRANSACTION_CLEANING not in os.listdir(root_fd))
        with transaction_directory(root_fd, TRANSACTION) as fd:
            metadata, _ = transaction_validate(fd, root, project)
        # 先原子移出有效登记，逐文件删除中断后只回收私密固定文件集合。
        os.rename(TRANSACTION, TRANSACTION_CLEANING, src_dir_fd=root_fd, dst_dir_fd=root_fd)
        os.fsync(root_fd)
        transaction_reap(root_fd)
    return metadata


def transaction_schedule_save(root, project, snapshot, unit_dir, systemd_ready,
                              timer_enabled, timer_active, job="traffic"):
    require(job in SCHEDULE_JOBS)
    transaction_path(snapshot)
    transaction_path(unit_dir)
    require(snapshot == root + "/" + TRANSACTION + "/" + job + "-source")
    require(all(type(value) is int and value in (0, 1)
                for value in (systemd_ready, timer_enabled, timer_active)))
    with transaction_root(root, project) as root_fd:
        with transaction_directory(root_fd, TRANSACTION) as fd:
            metadata, _ = transaction_validate(fd, root, project)
            require(metadata["state"] == "active"
                    and transaction_schedule(fd, root, project, job) is None)
            with transaction_directory(fd, job + "-source") as snapshot_fd:
                require(set(os.listdir(snapshot_fd)) <= set(SCHEDULE_JOBS[job]))
                temporary = job + "-building"
                os.mkdir(temporary, 0o700, dir_fd=fd)
                published = False
                try:
                    with transaction_directory(fd, temporary) as temporary_fd:
                        files = {}
                        for name in sorted(os.listdir(snapshot_fd)):
                            data, _ = transaction_read(snapshot_fd, name)
                            transaction_write(temporary_fd, name, data)
                            files[name] = {"size": len(data),
                                           "sha256": hashlib.sha256(data).hexdigest(),
                                           "mode": 0o600}
                        saved = {"schema_version": 1, "root": root, "project": project,
                                 "unit_dir": unit_dir, "systemd_ready": systemd_ready,
                                 "timer_enabled": timer_enabled, "timer_active": timer_active,
                                 "snapshot": os.path.basename(snapshot), "files": files}
                        transaction_write(temporary_fd, TRANSACTION_METADATA,
                                          transaction_encoded(saved))
                        os.fsync(temporary_fd)
                    os.rename(temporary, job + "-schedule", src_dir_fd=fd, dst_dir_fd=fd)
                    published = True
                    os.fsync(fd)
                finally:
                    if not published:
                        transaction_remove_files(fd, temporary)
    return saved


@contextlib.contextmanager
def transaction_unit_directory(pending_fd, schedule, job, install=False):
    needs_write = install or any(name.endswith((".service", ".timer"))
                                 for name in schedule["files"])
    with contextlib.ExitStack() as stack:
        try:
            parent, name = stack.enter_context(absolute_parent(schedule["unit_dir"], private=True))
            unit_fd = stack.enter_context(transaction_directory(parent, name, private=False))
        except FileNotFoundError:
            require(not needs_write)
            yield None
            return
        # 原子替换不跨文件系统，不能退回可能被硬杀截断的复制。
        require(not needs_write or os.fstat(unit_fd).st_dev == os.fstat(pending_fd).st_dev)
        for name in SCHEDULE_JOBS[job][:2]:
            try:
                os.stat(name + ".d", dir_fd=unit_fd, follow_symlinks=False)
            except FileNotFoundError:
                pass
            else:
                require(False)
            try:
                transaction_read(unit_fd, name, private=False, source_mode=0o644)
            except FileNotFoundError:
                pass
        yield unit_fd


def transaction_unit(root, project, job, kind=None, restore=False, install=False):
    require(job in SCHEDULE_JOBS and kind in (None, "service", "timer"))
    with transaction_root(root, project) as root_fd:
        with transaction_directory(root_fd, TRANSACTION) as pending_fd:
            metadata, _ = transaction_validate(pending_fd, root, project)
            schedule = transaction_schedule(pending_fd, root, project, job)
            require(metadata["state"] == "active" and schedule is not None)
            needs_install = install or kind is not None and not restore
            with transaction_unit_directory(pending_fd, schedule, job, needs_install) as unit_fd:
                if kind is None or unit_fd is None:
                    return
                name = "padm-docker-" + job + "." + kind
                if restore and name not in schedule["files"]:
                    try:
                        os.unlink(name, dir_fd=unit_fd)
                    except FileNotFoundError:
                        pass
                    os.fsync(unit_fd)
                    return
                source = job + "-source"
                if source not in os.listdir(pending_fd):
                    require(restore)
                    os.mkdir(source, 0o700, dir_fd=pending_fd)
                    os.fsync(pending_fd)
                with transaction_directory(pending_fd, source) as source_fd:
                    require(os.fstat(source_fd).st_dev == os.fstat(unit_fd).st_dev)
                    temporary = "new." + kind
                    if restore:
                        with transaction_directory(pending_fd, job + "-schedule") as schedule_fd:
                            data, _ = transaction_read(schedule_fd, name)
                        if temporary in os.listdir(source_fd):
                            os.unlink(temporary, dir_fd=source_fd)
                        transaction_write(source_fd, temporary, data)
                    transaction_read(source_fd, temporary)
                    with opened(source_fd, temporary, os.O_RDONLY) as new_fd:
                        os.fsync(new_fd)
                        os.replace(temporary, name, src_dir_fd=source_fd, dst_dir_fd=unit_fd)
                        # 暂存始终为 0600；替换后再放宽，硬杀只留下完整的旧或新文件。
                        os.fchmod(new_fd, 0o644)
                        os.fsync(new_fd)
                    os.fsync(unit_fd)
                    os.fsync(source_fd)


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
    reality = commands.add_parser("reality-inputs")
    reality.add_argument("--directory", required=True)
    reality.add_argument("--destination")
    geo = commands.add_parser("geo-inputs")
    geo.add_argument("--directory", required=True)
    geo.add_argument("--destination")
    renewal = commands.add_parser("renewal-inputs")
    renewal.add_argument("--directory", required=True)
    renewal.add_argument("--destination")
    for action in ("begin", "prepare", "check", "commit", "clean", "metadata",
                   "schedule-save", "schedule-metadata", "unit-check", "unit-publish"):
        command = commands.add_parser("transaction-" + action)
        command.add_argument("--root", required=True)
        command.add_argument("--project", required=True)
        if action in ("schedule-save", "schedule-metadata", "unit-check", "unit-publish"):
            command.add_argument("--job", choices=tuple(SCHEDULE_JOBS), default="traffic")
        if action == "prepare":
            command.add_argument("--candidate", required=True)
            command.add_argument("--input-stage")
        elif action == "schedule-save":
            command.add_argument("--snapshot", required=True)
            command.add_argument("--unit-dir", required=True)
            for option in ("systemd-ready", "timer-enabled", "timer-active"):
                command.add_argument("--" + option, type=int, choices=(0, 1), required=True)
        elif action == "unit-check":
            command.add_argument("--install", action="store_true")
        elif action == "unit-publish":
            command.add_argument("--kind", choices=("service", "timer"), required=True)
            command.add_argument("--restore", action="store_true")
    args = parser.parse_args()
    try:
        if args.action == "export":
            counts = export_archive(args.root, args.output)
            print("灾备归档已导出（{} 个文件，{} 字节）。".format(*counts))
        elif args.action == "verify":
            counts = verify_archive(args.archive)
            print("灾备归档完整性校验通过（{} 个文件，{} 字节；未验证来源或恢复能力）。".format(*counts))
        elif args.action == "extract":
            counts = extract_archive(args.archive, args.directory)
            print("灾备归档已校验并解包至私密暂存目录（{} 个文件，{} 字节）。".format(*counts))
        elif args.action == "reality-inputs":
            print(json.dumps(reality_inputs(args.directory, args.destination), separators=(",", ":")))
        elif args.action == "geo-inputs":
            print(json.dumps(geo_inputs(args.directory, args.destination), separators=(",", ":")))
        elif args.action == "renewal-inputs":
            print(json.dumps(renewal_inputs(args.directory, args.destination), separators=(",", ":")))
        elif args.action == "transaction-begin":
            print(json.dumps(transaction_begin(args.root, args.project), separators=(",", ":")))
        elif args.action == "transaction-prepare":
            transaction_prepare(args.root, args.project, args.candidate, args.input_stage)
        elif args.action == "transaction-commit":
            transaction_commit(args.root, args.project)
        elif args.action == "transaction-clean":
            transaction_clean(args.root, args.project)
        elif args.action == "transaction-schedule-save":
            transaction_schedule_save(args.root, args.project, args.snapshot, args.unit_dir,
                                      args.systemd_ready, args.timer_enabled, args.timer_active,
                                      args.job)
        elif args.action == "transaction-unit-check":
            transaction_unit(args.root, args.project, args.job, install=args.install)
        elif args.action == "transaction-unit-publish":
            transaction_unit(args.root, args.project, args.job, args.kind, args.restore)
        else:
            metadata, schedule = transaction_check(
                args.root, args.project,
                args.job if args.action == "transaction-schedule-metadata" else "traffic")
            result = (metadata if args.action == "transaction-metadata" else
                      schedule if args.action == "transaction-schedule-metadata" else
                      {"state": metadata["state"]})
            print(json.dumps(result, ensure_ascii=True, separators=(",", ":")))
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
