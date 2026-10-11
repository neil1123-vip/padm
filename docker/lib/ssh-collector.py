#!/usr/bin/env python3
"""收集单个受信 OpenSSH unit 的新认证失败，不证明历史连接的原子归属。"""

from datetime import datetime
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import stat
import sys
import time


SPEC = importlib.util.spec_from_file_location(
    "padm_ssh_journal", Path(__file__).resolve().with_name("ssh-journal.py")
)
journal = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(journal)
ssh = journal.ssh
Failure = ssh.Failure
MAX_SAME_MONO = 1024
FAILED_PASSWORD = re.compile(
    r"Failed password for (?:invalid user )?[^\s\x00-\x1f\x7f]+"
    r" from ([^\s\x00-\x1f\x7f]+) port ([1-9][0-9]{0,4}) ssh2"
)


def position(record, boot):
    cursor, mono = record.get("__CURSOR"), record.get("__MONOTONIC_TIMESTAMP")
    if (record.get("_BOOT_ID") != boot or not isinstance(cursor, str)
            or not cursor or len(cursor) > 1024
            or any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in cursor)
            or not isinstance(mono, str) or not re.fullmatch(r"[0-9]{1,20}", mono)
            or int(mono) > 2**64 - 1):
        raise Failure("SSH collector 的 journal 游标或单调时间无效")
    return cursor, int(mono)


def failed_source(record, snapshot):
    if record.get("_SYSTEMD_UNIT") != snapshot["unit"]["unit"]:
        return None
    message = record.get("MESSAGE")
    match = FAILED_PASSWORD.fullmatch(message) if isinstance(message, str) else None
    if not match:
        return None
    unit = snapshot["unit"]
    for key, value in (
        ("_SYSTEMD_INVOCATION_ID", unit["invocation_id"]),
        ("_SYSTEMD_CGROUP", unit["control_group"]), ("_TRANSPORT", "syslog"),
        ("_UID", "0"),
    ):
        if record.get(key) != value:
            raise Failure("SSH collector 的认证失败缺少可信 unit 归属")
    pid = record.get("_PID")
    if (record.get("_EXE") not in ssh.EMITTER_EXES or not isinstance(pid, str)
            or not re.fullmatch(r"[1-9][0-9]{0,9}", pid)
            or int(pid) > 2**31 - 1):
        raise Failure("SSH collector 的认证失败缺少 root OpenSSH 身份")
    try:
        source = ssh.parse_address(match[1])
    except Failure:
        return None
    if str(source) != match[1] or int(match[2]) > 65535:
        return None
    return source, int(match[2])


class Collector:
    def __init__(self, unit, target, port):
        self.unit = journal.unit_name(unit)
        self.target = ssh.parse_address(str(target))
        value = str(port)
        if (str(self.target) != str(target)
                or not re.fullmatch(r"[1-9][0-9]{0,4}", value)
                or int(value) > 65535):
            raise Failure("SSH collector 需要规范本机地址和端口", 2)
        self.port = int(value)
        self.snapshot = journal.unit_snapshot(self.unit, self.target, self.port)
        self.boot = self.snapshot["master"]["process"]["boot_id"]
        self.check_startup()
        cursor, mono = ssh.checkpoint(self.boot)
        self.cursor, self.mono = position({
            "_BOOT_ID": self.boot, "__CURSOR": cursor,
            "__MONOTONIC_TIMESTAMP": str(mono),
        }, self.boot)
        self.same_mono = {cursor}
        self.check_startup()

    def check_snapshot(self):
        if journal.unit_snapshot(self.unit, self.target, self.port) != self.snapshot:
            raise Failure("SSH collector 的 unit、MainPID 或监听已变化")

    def check_startup(self):
        self.check_snapshot()
        # 存量认证子进程可能保留 reload 前的端点，不能归到当前唯一监听。
        if journal.cgroup_pids(self.snapshot["unit"]["control_group"]) != (
                self.snapshot["unit"]["main_pid"],):
            raise Failure("SSH collector 只支持无存量会话的专用 service；"
                          "请从控制台或其它管理通道启用，禁止 reload")

    def poll(self):
        self.check_snapshot()
        rows = ssh.journal_records(self.boot, self.cursor, None)
        cursor, mono, same_mono = self.cursor, self.mono, set(self.same_mono)
        events = []
        for record in rows:
            next_cursor, next_mono = position(record, self.boot)
            if next_mono < mono or next_cursor in same_mono:
                raise Failure("SSH collector 的 journal 游标重复或倒退")
            if next_mono > mono:
                same_mono.clear()
            same_mono.add(next_cursor)
            if len(same_mono) > MAX_SAME_MONO:
                raise Failure("SSH collector 的同时间 journal 游标超出上限")
            cursor, mono = next_cursor, next_mono
            found = failed_source(record, self.snapshot)
            if found is None:
                continue
            if mono < self.snapshot["unit"]["exec_start_mono"]:
                raise Failure("SSH collector 的认证失败早于当前 unit 代次")
            source, source_port = found
            if source.version != self.target.version or source == self.target:
                continue
            events.append({
                "source": str(source), "source_port": source_port,
                "cursor": cursor, "mono": mono,
            })
        self.check_snapshot()
        self.cursor, self.mono, self.same_mono = cursor, mono, same_mono
        return events


class Guard:
    def __init__(self, directory, token):
        if (not isinstance(directory, str) or not directory.startswith("/")
                or len(directory) > 4096 or str(Path(directory)) != directory
                or any(part in ("", ".", "..") for part in directory.split("/")[1:])
                or not isinstance(token, str) or not re.fullmatch(r"[0-9a-f]{32}", token)):
            raise Failure("SSH collector 需要受保护目录和本次 token", 2)
        self.token = token
        self.fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            for part in directory.split("/")[1:]:
                current = os.fstat(self.fd)
                if current.st_uid != 0 or current.st_mode & 0o022:
                    raise Failure("SSH collector 的 guard 父目录不安全")
                next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                  dir_fd=self.fd)
                os.close(self.fd)
                self.fd = next_fd
            current = os.fstat(self.fd)
            if current.st_uid != 0 or stat.S_IMODE(current.st_mode) != 0o700:
                raise Failure("SSH collector 的 guard 目录必须为 root 0700")
            fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.read()
        except BaseException:
            os.close(self.fd)
            raise

    def read(self):
        try:
            fd = os.open("guard.json", os.O_RDONLY | os.O_NOFOLLOW, dir_fd=self.fd)
        except FileNotFoundError:
            return None
        with os.fdopen(fd, "r", encoding="utf-8") as handle:
            metadata = os.fstat(handle.fileno())
            if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0
                    or stat.S_IMODE(metadata.st_mode) != 0o600
                    or metadata.st_nlink != 1 or not 1 <= metadata.st_size <= 4096):
                raise Failure("SSH collector 的 guard 文件不安全")
            rows = ssh.parse_json_lines(handle.read(4097))
        if (len(rows) != 1 or rows[0].get("schema") != 1
                or rows[0].get("token") != self.token):
            raise Failure("SSH collector 拒绝接管其它 token 的 guard")
        return rows[0]

    def write(self, collector):
        self.read()
        row = {
            "schema": 1, "token": self.token, "unit": collector.unit,
            "target": str(collector.target), "port": collector.port,
            "boot": collector.boot,
            "invocation": collector.snapshot["unit"]["invocation_id"],
            "monotonic_ns": time.monotonic_ns(),
        }
        temporary = ".guard-" + self.token
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                     0o600, dir_fd=self.fd)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(row, handle, separators=(",", ":"))
                handle.write("\n")
            self.read()
            os.replace(temporary, "guard.json", src_dir_fd=self.fd, dst_dir_fd=self.fd)
        finally:
            try:
                os.unlink(temporary, dir_fd=self.fd)
            except FileNotFoundError:
                pass

    def __enter__(self):
        return self

    def __exit__(self, *_exception):
        try:
            if self.read() is not None:
                os.unlink("guard.json", dir_fd=self.fd)
        finally:
            os.close(self.fd)


def notify_ready():
    address = os.environ.get("NOTIFY_SOCKET")
    if address:
        if address.startswith("@"):
            address = "\0" + address[1:]
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as connection:
            connection.sendto(b"READY=1", address)


def main(args):
    previous = None
    try:
        if len(args) != 3:
            raise Failure("SSH collector 需要 service、本机地址和端口", 2)
        if sys.platform != "linux" or os.geteuid() != 0:
            raise Failure("SSH collector 需要原生 Linux 宿主 root 环境", 10)
        if any(shutil.which(tool) is None for tool in ("ss", "journalctl", "systemctl")):
            raise Failure("SSH collector 缺少宿主只读工具", 10)

        def stop(_signal, _frame):
            raise KeyboardInterrupt

        previous = signal.signal(signal.SIGTERM, stop)
        with Guard(os.environ.get("PADM_SSH_COLLECTOR_DIR"),
                   os.environ.get("PADM_SSH_COLLECTOR_TOKEN")) as guard:
            collector = Collector(*args)
            ready = False
            while True:
                events = collector.poll()
                guard.write(collector)
                if not ready:
                    notify_ready()
                    ready = True
                for event in events:
                    print(datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                          + " padm-ssh source=" + event["source"], flush=True)
                time.sleep(1)
    except KeyboardInterrupt:
        return 0
    except Failure as error:
        print(str(error), file=sys.stderr)
        return error.code
    except (OSError, ValueError, KeyError, IndexError, TypeError):
        print("SSH collector 无法完成可信宿主证据读取", file=sys.stderr)
        return 15
    finally:
        if previous is not None:
            signal.signal(signal.SIGTERM, previous)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
