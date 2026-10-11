#!/usr/bin/env python3
"""管理专用 SSH collector 的 transient unit；未知归属保留并拒绝接管。"""

import importlib.util
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import shlex
import stat
import subprocess
import sys
import time


SPEC = importlib.util.spec_from_file_location(
    "padm_ssh_collector", Path(__file__).resolve().with_name("ssh-collector.py")
)
collector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(collector)
Failure = collector.Failure
OWNER_KEYS = {
    "schema", "token", "service", "unit", "target", "port", "invocation",
    "python", "script",
}
GUARD_KEYS = {
    "schema", "token", "unit", "target", "port", "boot", "invocation",
    "monotonic_ns",
}
PROPERTIES = (
    "LoadState", "ActiveState", "SubState", "Description", "Transient",
    "FragmentPath", "InvocationID", "MainPID", "ExecStart", "Environment",
    "User", "Type", "StandardOutput",
)


def command(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise Failure("SSH collector 的受管 systemd 操作失败")
    return result.stdout


class Directory:
    def __init__(self, path, create=False):
        if (not isinstance(path, str) or not re.fullmatch(r"/[A-Za-z0-9_./-]+", path)
                or any(part in ("", ".", "..") for part in path.split("/")[1:])):
            raise Failure("SSH collector 路径必须是规范且不含空白的绝对路径")
        self.path = path
        self.fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            parts = path.split("/")[1:]
            for index, part in enumerate(parts):
                current = os.fstat(self.fd)
                if current.st_uid != 0 or current.st_mode & 0o022:
                    raise Failure("SSH collector 父目录不安全")
                if create and index == len(parts) - 1:
                    try:
                        os.mkdir(part, 0o700, dir_fd=self.fd)
                    except FileExistsError:
                        pass
                next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                  dir_fd=self.fd)
                os.close(self.fd)
                self.fd = next_fd
            current = os.fstat(self.fd)
            if current.st_uid != 0 or stat.S_IMODE(current.st_mode) != 0o700:
                raise Failure("SSH collector 目录必须为 root 0700")
        except BaseException:
            os.close(self.fd)
            raise

    def read(self, name, optional=False):
        try:
            fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=self.fd)
        except FileNotFoundError:
            if optional:
                return None
            raise
        with os.fdopen(fd, "r", encoding="utf-8") as handle:
            current = os.fstat(handle.fileno())
            if (not stat.S_ISREG(current.st_mode) or current.st_uid != 0
                    or stat.S_IMODE(current.st_mode) != 0o600
                    or current.st_nlink != 1 or not 1 <= current.st_size <= 4096):
                raise Failure("SSH collector 的受管文件权限或大小无效")
            rows = collector.ssh.parse_json_lines(handle.read(4097))
        if len(rows) != 1:
            raise Failure("SSH collector 的受管 JSON 无效")
        return rows[0]

    def write_owner(self, owner):
        temporary = ".owner-" + owner["token"]
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                     0o600, dir_fd=self.fd)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(owner, handle, separators=(",", ":"))
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, "owner.json", src_dir_fd=self.fd, dst_dir_fd=self.fd)
        finally:
            try:
                os.unlink(temporary, dir_fd=self.fd)
            except FileNotFoundError:
                pass

    def close(self):
        os.close(self.fd)


def owner_read(directory):
    owner = directory.read("owner.json", optional=True)
    if owner is None:
        if os.listdir(directory.fd):
            raise Failure("SSH collector 目录有未知残留，拒绝接管")
        return None
    if (set(owner) != OWNER_KEYS or type(owner["schema"]) is not int
            or owner["schema"] != 1 or not isinstance(owner["token"], str)
            or not re.fullmatch(r"[0-9a-f]{32}", owner["token"])
            or owner["service"] != "padm-ssh-collector-" + owner["token"] + ".service"
            or owner["invocation"] is not None and
            not re.fullmatch(r"[0-9a-f]{32}", str(owner["invocation"]))
            or type(owner["port"]) is not int or not 1 <= owner["port"] <= 65535):
        raise Failure("SSH collector 的 owner 格式无效")
    collector.journal.unit_name(owner["unit"])
    if str(collector.ssh.parse_address(owner["target"])) != owner["target"]:
        raise Failure("SSH collector 的 owner 地址不规范")
    for key in ("python", "script"):
        if not re.fullmatch(r"/[A-Za-z0-9_./-]+", str(owner[key])):
            raise Failure("SSH collector 的 owner 执行路径无效")
    if (owner["python"] != str(Path(sys.executable).resolve())
            or owner["script"] != str(Path(__file__).resolve().with_name("ssh-collector.py"))):
        raise Failure("SSH collector 不属于当前控制脚本，拒绝迁移或接管")
    return owner


def unit_state(owner, directory):
    text = command([
        "systemctl", "show", "--no-pager",
        "--property=" + ",".join(PROPERTIES), "--", owner["service"],
    ])
    values = {}
    for line in text.splitlines():
        key, separator, value = line.partition("=")
        if not separator or key not in PROPERTIES or key in values:
            raise Failure("SSH collector 的 systemd 属性无效")
        values[key] = value
    if values.get("LoadState") == "not-found":
        if values.get("ActiveState") != "inactive" or values.get("MainPID") != "0":
            raise Failure("SSH collector 的缺失 unit 状态不一致")
        return values
    if set(values) != set(PROPERTIES):
        raise Failure("SSH collector 的 systemd 属性不完整")
    expected = " ".join([
        owner["python"], "-B", owner["script"], owner["unit"],
        owner["target"], str(owner["port"]),
    ])
    expected_env = [
        "PADM_SSH_COLLECTOR_DIR=" + directory.path,
        "PADM_SSH_COLLECTOR_TOKEN=" + owner["token"],
    ]
    fragment = Path("/run/systemd/transient") / owner["service"]
    metadata = fragment.lstat()
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0
            or metadata.st_mode & 0o022 or metadata.st_nlink != 1
            or fragment.read_text().splitlines().count(
                "StandardOutput=append:" + directory.path + "/auth.log") != 1):
        raise Failure("SSH collector 的 transient 日志路径已变化")
    if (values["Description"] != "padm SSH collector " + owner["token"]
            or values["Transient"] != "yes"
            or values["FragmentPath"] != "/run/systemd/transient/" + owner["service"]
            or "argv[]=" + expected + " ;" not in values["ExecStart"]
            or "path=" + owner["python"] + " ;" not in values["ExecStart"]
            or sorted(shlex.split(values["Environment"])) != sorted(expected_env)
            or values["User"] != "root" or values["Type"] != "notify"
            or values["StandardOutput"] != "append"
            or owner["invocation"] is not None
            and values["InvocationID"] != owner["invocation"]):
        raise Failure("SSH collector 的 transient unit 归属已变化")
    return values


def guard_check(directory, owner):
    guard = directory.read("guard.json")
    boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip().replace("-", "")
    if (set(guard) != GUARD_KEYS or type(guard["schema"]) is not int
            or guard["schema"] != 1
            or any(guard[key] != owner[key] for key in ("token", "unit", "target", "port"))
            or guard["boot"] != boot or not isinstance(guard["invocation"], str)
            or not re.fullmatch(r"[0-9a-f]{32}", guard["invocation"])
            or type(guard["monotonic_ns"]) is not int
            or not 0 <= time.monotonic_ns() - guard["monotonic_ns"] <= 10_000_000_000):
        raise Failure("SSH collector 的健康凭证不匹配或已过期")
    snapshot = collector.journal.unit_snapshot(
        owner["unit"], collector.ssh.parse_address(owner["target"]), owner["port"]
    )
    if (snapshot["unit"]["invocation_id"] != guard["invocation"]
            or snapshot["master"]["process"]["boot_id"] != guard["boot"]):
        raise Failure("SSH collector 的目标 unit 代次已变化")
    return guard


def check(directory, owner, container=None):
    if owner is None:
        raise Failure("SSH collector 尚未受管启动")
    state = unit_state(owner, directory)
    if (state["LoadState"] != "loaded" or state["ActiveState"] != "active"
            or state["SubState"] != "running" or owner["invocation"] is None):
        raise Failure("SSH collector 的受管 unit 未运行")
    pid = state["MainPID"]
    if not re.fullmatch(r"[1-9][0-9]*", pid):
        raise Failure("SSH collector 缺少 MainPID")
    expected = [owner["python"], "-B", owner["script"], owner["unit"],
                owner["target"], str(owner["port"])]
    actual = (Path("/proc") / pid / "cmdline").read_bytes().split(b"\0")
    if actual != [item.encode() for item in expected] + [b""]:
        raise Failure("SSH collector 的主进程命令已变化")
    if os.readlink(Path("/proc") / pid / "fd/1") != directory.path + "/auth.log":
        raise Failure("SSH collector 的实际输出文件已变化")
    guard_check(directory, owner)
    if container:
        details = json.loads(command(["docker", "inspect", "--", container]))
        expected_env = {
            "PADM_SSH_COLLECTOR_TOKEN": owner["token"],
            "PADM_SSH_COLLECTOR_UNIT": owner["unit"],
            "PADM_SSH_COLLECTOR_TARGET": owner["target"],
            "PADM_SSH_COLLECTOR_PORT": str(owner["port"]),
        }
        if len(details) != 1:
            raise Failure("SSH collector 对应容器不唯一")
        env = details[0]["Config"]["Env"]
        for key, value in expected_env.items():
            if [item for item in env if item.startswith(key + "=")] != [key + "=" + value]:
                raise Failure("SSH collector 与 jail 容器的本次凭证不一致")
    return owner["token"]


def start(directory, args):
    if owner_read(directory) is not None:
        raise Failure("SSH collector 已有 owner，请先经受管入口停用")
    if len(args) != 3:
        raise Failure("SSH collector 启动需要 service、本机地址和端口", 2)
    unit = collector.journal.unit_name(args[0])
    target = collector.ssh.parse_address(args[1])
    if (str(target) != args[1] or not re.fullmatch(r"[1-9][0-9]{0,4}", args[2])
            or int(args[2]) > 65535):
        raise Failure("SSH collector 启动地址或端口不规范", 2)
    token = os.urandom(16).hex()
    python = str(Path(sys.executable).resolve())
    script = str(Path(__file__).resolve().with_name("ssh-collector.py"))
    if not all(re.fullmatch(r"/[A-Za-z0-9_./-]+", value) for value in (python, script)):
        raise Failure("SSH collector 不支持含空白的执行路径")
    collector.ssh.safe_executable(python)
    files = [Path(script).with_name(name) for name in (
        "ssh-collector.py", "ssh-journal.py", "ssh-source.py",
    )]
    for path in (*files, *Path(script).parents):
        metadata = path.lstat()
        if (metadata.st_uid != 0 or metadata.st_mode & 0o022
                or path in files and not stat.S_ISREG(metadata.st_mode)
                or path not in files and not stat.S_ISDIR(metadata.st_mode)):
            raise Failure("SSH collector 的控制脚本路径不安全")
    owner = {
        "schema": 1, "token": token, "service": "padm-ssh-collector-" + token + ".service",
        "unit": unit, "target": str(target), "port": int(args[2]), "invocation": None,
        "python": python, "script": script,
    }
    fd = os.open("auth.log", os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                 0o600, dir_fd=directory.fd)
    os.close(fd)
    directory.write_owner(owner)
    command([
        "systemd-run", "--quiet", "--unit=" + owner["service"],
        "--description=padm SSH collector " + token,
        "--property=Type=notify", "--property=NotifyAccess=main",
        "--property=User=root", "--property=UMask=0077",
        "--property=Restart=no", "--property=KillMode=control-group",
        "--property=TimeoutStartSec=20", "--property=TimeoutStopSec=10",
        "--property=StandardOutput=append:" + directory.path + "/auth.log",
        "--property=StandardError=journal",
        "--setenv=PADM_SSH_COLLECTOR_DIR=" + directory.path,
        "--setenv=PADM_SSH_COLLECTOR_TOKEN=" + token,
        "--", python, "-B", script, unit, str(target), args[2],
    ])
    state = unit_state(owner, directory)
    if not re.fullmatch(r"[0-9a-f]{32}", state["InvocationID"]):
        raise Failure("SSH collector 未取得运行代次")
    owner["invocation"] = state["InvocationID"]
    directory.write_owner(owner)
    return check(directory, owner)


def stop(directory, owner):
    if owner is None:
        return
    state = unit_state(owner, directory)
    if state["LoadState"] != "not-found":
        command(["systemctl", "stop", "--", owner["service"]])
        state = unit_state(owner, directory)
        if state["ActiveState"] not in ("inactive", "failed") or state["MainPID"] != "0":
            raise Failure("SSH collector 未完成停止，保留 owner")
        if state["LoadState"] != "not-found" and state["ActiveState"] == "failed":
            command(["systemctl", "reset-failed", "--", owner["service"]])
            if unit_state(owner, directory)["LoadState"] != "not-found":
                raise Failure("SSH collector 的失败 transient unit 未退役，保留 owner")
    current = owner_read(directory)
    if current != owner:
        raise Failure("SSH collector 停止期间 owner 已变化")
    guard = directory.read("guard.json", optional=True)
    if guard is not None:
        if guard.get("token") != owner["token"]:
            raise Failure("SSH collector 的残留 guard 属于其它 owner")
        os.unlink("guard.json", dir_fd=directory.fd)
    # 仅在 unit 已停且本次 owner 未变后删除私有日志和凭证。
    try:
        fd = os.open("auth.log", os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory.fd)
    except FileNotFoundError:
        fd = None
    if fd is not None:
        current = os.fstat(fd)
        os.close(fd)
        if (not stat.S_ISREG(current.st_mode) or current.st_uid != 0
                or stat.S_IMODE(current.st_mode) != 0o600 or current.st_nlink != 1):
            raise Failure("SSH collector 日志归属不安全，保留 owner")
        os.unlink("auth.log", dir_fd=directory.fd)
    os.unlink("owner.json", dir_fd=directory.fd)


def main(args):
    directory = None
    lock_fd = None
    try:
        if len(args) < 2 or args[0] not in ("start", "check", "stop"):
            raise Failure("SSH collector runtime 参数无效", 2)
        if sys.platform != "linux" or os.geteuid() != 0:
            raise Failure("SSH collector 需要原生 Linux root systemd 宿主", 10)
        if (not Path("/run/systemd/system").is_dir()
                or any(shutil.which(tool) is None for tool in ("systemctl", "systemd-run"))):
            raise Failure("SSH collector 需要可用的宿主 systemd 管理工具", 10)
        directory = Directory(args[1], create=args[0] == "start")
        # 管理锁与 collector 的目录锁分开，防止 start/stop 相互穿插。
        lock_fd = os.open(directory.path + ".lock",
                          os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        metadata = os.fstat(lock_fd)
        if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0
                or stat.S_IMODE(metadata.st_mode) != 0o600 or metadata.st_nlink != 1):
            raise Failure("SSH collector 管理锁不安全")
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args[0] == "start":
            print(start(directory, args[2:]), flush=True)
        elif args[0] == "check":
            if len(args) not in (2, 3):
                raise Failure("SSH collector check 参数无效", 2)
            print(check(directory, owner_read(directory), args[2] if len(args) == 3 else None))
        else:
            if len(args) != 2:
                raise Failure("SSH collector stop 参数无效", 2)
            stop(directory, owner_read(directory))
        return 0
    except Failure as error:
        print(str(error), file=sys.stderr)
        return error.code
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        print("SSH collector 无法完成受管操作，保留现场凭证供核对", file=sys.stderr)
        return 15
    finally:
        if directory is not None:
            directory.close()
        if lock_fd is not None:
            os.close(lock_fd)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
