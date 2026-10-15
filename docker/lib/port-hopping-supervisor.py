#!/usr/bin/env python3
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import select
import signal
import socket
import stat
import struct
import subprocess
import sys
import time


FRAME_LIMIT = 262144
SESSION = ".hopping-supervisor"
START_TIMEOUT = 120
CHANGE_TIMEOUT = 840
STOP_TIMEOUT = 90
BODY = r'''
source "$1"
shift
PADM_DOCKER_INSTALL_DIR=$1
export PADM_DOCKER_INSTALL_DIR
shift
if dockerPortHoppingTargetSupervisedOwned "$@"; then exit 0; else exit $?; fi
'''
RESERVE_BODY = r'''
source "$1"
PADM_DOCKER_INSTALL_DIR=$2
export PADM_DOCKER_INSTALL_DIR
owner=${BASHPID:-$$}
original=
current=
trap 'if [[ -n "${original}" ]] &&
    current=$(dockerPortHoppingTargetLockSnapshot "${owner}") &&
    [[ "${current}" == "${original}" ]]; then
        dockerReleaseDeploymentLock
    fi' EXIT
dockerAcquireDeploymentLock || exit "${PADM_DOCKER_RC_LOCK:-12}"
original=$(dockerPortHoppingTargetLockSnapshot "${owner}") || exit 1
if [[ "${5:-}" == --saved ]]; then
    values=$(dockerPortHoppingSavedArguments) || exit 1
    exec "$3" -B "$4" _reserve "${PADM_DOCKER_INSTALL_DIR}" "$1" "${original}" "${values}"
fi
exec "$3" -B "$4" _reserve "${PADM_DOCKER_INSTALL_DIR}" "$1" "${original}"
'''
LOCK_BODY = r'''
source "$1"
PADM_DOCKER_INSTALL_DIR=$2
DOCKER_DEPLOYMENT_LOCK_DIR=$2/locks/deployment.lock
export PADM_DOCKER_INSTALL_DIR
dockerPortHoppingTargetLockSnapshot "$3"
'''
RECOVER_BODY = r'''
source "$1"
PADM_DOCKER_INSTALL_DIR=$2
export PADM_DOCKER_INSTALL_DIR
dockerPortHoppingRecoveryInspect "$3"
'''


class Failure(Exception):
    pass


def stop_signals():
    pending = [0]
    # 信号只登记；Popen、原子替换和删锁操作结束后再检查，避免丢失本次归属。
    def record(number, _):
        pending[0] = 128 + number
    signal.signal(signal.SIGTERM, record)
    signal.signal(signal.SIGINT, record)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    return pending


def check_signal(pending):
    if pending[0]:
        raise Failure(f"监督初始化收到信号 {pending[0]}，停止后续写入并保留未核验现场")


def remaining_time(deadline):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise Failure("监督事务总时限已到，停止推进并保留未核验现场")
    return remaining


def run_interruptible(arguments, pending, deadline=None):
    check_signal(pending)
    if deadline is not None:
        remaining_time(deadline)
    process = subprocess.Popen(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        while True:
            check_signal(pending)
            try:
                output, error = process.communicate(
                    timeout=min(0.2, remaining_time(deadline)) if deadline is not None else 0.2)
                check_signal(pending)
                if deadline is not None:
                    remaining_time(deadline)
                return subprocess.CompletedProcess(arguments, process.returncode, output, error)
            except subprocess.TimeoutExpired:
                continue
    finally:
        if process.poll() is None:
            # 直接子进程未回收前 PID 不会复用；预约失败不能留下随后继续写入的 owner。
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        process.stdout.close()
        process.stderr.close()


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Failure("监督帧含重复键")
        result[key] = value
    return result


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("ascii")


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def nonce(value):
    return isinstance(value, str) and re.fullmatch(r"[a-f0-9]{64}", value) is not None


def shape(value, keys):
    if not isinstance(value, dict) or set(value) != set(keys):
        raise Failure("监督帧字段不匹配")
    if "v" in value and (type(value["v"]) is not int or value["v"] != 1):
        raise Failure("监督帧版本无效")
    return value


def send(peer, value):
    raw = canonical(value) + b"\n"
    if len(raw) > FRAME_LIMIT:
        raise Failure("监督帧过长")
    peer.sendall(raw)


def receive(peer, timeout=20, pending=None, deadline=None):
    frame_deadline = time.monotonic() + timeout
    deadline = min(frame_deadline, deadline) if deadline is not None else frame_deadline
    raw = b""
    while not raw.endswith(b"\n"):
        if pending is not None:
            check_signal(pending)
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise Failure("监督帧超时")
        if not select.select([peer], [], [], min(remaining, 0.2) if pending is not None else remaining)[0]:
            if pending is not None:
                continue
            raise Failure("监督帧超时")
        byte = peer.recv(1)
        if not byte:
            raise Failure("监督控制连接已关闭")
        raw += byte
        if len(raw) > FRAME_LIMIT or b"\r" in raw or b"\0" in raw:
            raise Failure("监督帧过长或含非法字节")
    try:
        return json.loads(raw[:-1].decode("ascii"), object_pairs_hook=unique)
    except (ValueError, UnicodeError) as error:
        raise Failure("监督帧 JSON 无效") from error


def peer_pid(peer):
    pid, uid, _ = struct.unpack("3i", peer.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
    if uid != 0:
        raise Failure("监督控制连接必须属于 root")
    return pid


def identity(pid):
    root = Path("/proc") / str(pid)
    raw = (root / "stat").read_text()
    fields = raw[raw.rfind(")") + 2:].split()
    value = {
        "pid": pid, "starttime_ticks": int(fields[19]),
        "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
        "pid_ns": os.readlink(root / "ns/pid"), "net_ns": os.readlink(root / "ns/net"),
        "session_id": int(fields[3]),
    }
    if fields[0] == "Z":
        raise Failure("监督进程已退出")
    final = (root / "stat").read_text()
    if int(final[final.rfind(")") + 2:].split()[19]) != value["starttime_ticks"]:
        raise Failure("读取监督进程时身份变化")
    return value


def pin(expected):
    descriptor = os.pidfd_open(expected["pid"])
    try:
        if identity(expected["pid"]) != expected or select.select([descriptor], [], [], 0)[0]:
            raise Failure("监督进程代次已变化")
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def path_identity(metadata):
    return (metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_uid,
            metadata.st_gid, metadata.st_nlink)


class Directory:
    def __init__(self, root):
        path = PurePosixPath(root)
        if str(path) != root or path.anchor != "/" or root == "/" or ".." in path.parts:
            raise Failure("监督根路径必须规范")
        self.root, self.path = root, root + "/data/net/" + SESSION
        self.held = []
        self.projection = []
        descriptor = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
        self.held.append(descriptor)
        self.projection.append(path_identity(os.fstat(descriptor))[:5])
        parts = path.parts[1:]
        for index, part in enumerate(parts):
            descriptor = self.open_dir(part, descriptor, strict=index == len(parts) - 1)
        self.root_fd = descriptor
        self.net_fd = self.open_dir("net", self.open_dir("data", descriptor, strict=True), strict=True)
        self.fd, self.created = None, False

    def open_dir(self, name, parent, strict=False):
        descriptor = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                             dir_fd=parent)
        self.held.append(descriptor)
        metadata = os.fstat(descriptor)
        if metadata.st_uid != 0 or (strict and metadata.st_mode & 0o022):
            raise Failure("监督目录 owner 或权限无效")
        self.projection.append(path_identity(metadata)[:5])
        return descriptor

    def session(self, create=False):
        if create:
            os.mkdir(SESSION, 0o700, dir_fd=self.net_fd)
            self.created = True
        self.fd = self.open_dir(SESSION, self.net_fd)
        metadata = os.fstat(self.fd)
        if stat.S_IMODE(metadata.st_mode) != 0o700:
            raise Failure("监督会话目录权限必须为 0700")
        self.original = path_identity(metadata)

    def check(self):
        current = os.stat(SESSION, dir_fd=self.net_fd, follow_symlinks=False)
        if path_identity(current) != self.original or path_identity(os.fstat(self.fd)) != self.original:
            raise Failure("监督会话目录身份变化")
        # 重新走完整目录链，不能仅信任已打开的旧 inode。
        other = Directory(self.root)
        try:
            if other.projection != self.projection[:len(other.projection)]:
                raise Failure("监督受管目录链身份变化")
        finally:
            other.close()

    def read_owner(self):
        self.check()
        descriptor = os.open("owner.json", os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                             dir_fd=self.fd)
        try:
            before = os.fstat(descriptor)
            if (not stat.S_ISREG(before.st_mode) or before.st_uid != 0 or
                    stat.S_IMODE(before.st_mode) != 0o600 or before.st_nlink != 1 or
                    before.st_size > FRAME_LIMIT):
                raise Failure("监督 owner 文件身份或权限无效")
            raw = b""
            while len(raw) <= FRAME_LIMIT:
                chunk = os.read(descriptor, FRAME_LIMIT + 1 - len(raw))
                if not chunk:
                    break
                raw += chunk
            after = os.fstat(descriptor)
            current = os.stat("owner.json", dir_fd=self.fd, follow_symlinks=False)
            if (len(raw) > FRAME_LIMIT or path_identity(after) != path_identity(current) or
                    (path_identity(before), before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (
                    path_identity(after), after.st_size, after.st_mtime_ns, after.st_ctime_ns)):
                raise Failure("监督 owner 在读取时变化")
            value = json.loads(raw.decode("ascii"), object_pairs_hook=unique)
            shape(value, ("v", "token", "root", "manager", "bash", "stage", "stage_sha256", "state"))
            if not nonce(value["token"]) or value["root"] != self.root:
                raise Failure("监督 owner 不属于当前会话")
            return value
        finally:
            os.close(descriptor)

    def write_owner(self, value):
        self.check()
        descriptor = os.open("owner.next", os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=self.fd)
        try:
            raw = canonical(value) + b"\n"
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(raw)
                stream.flush()
                os.fsync(stream.fileno())
        except BaseException:
            raise
        os.replace("owner.next", "owner.json", src_dir_fd=self.fd, dst_dir_fd=self.fd)
        self.check()

    def check_stopped(self, owner, socket_id, log_id):
        self.check()
        if self.read_owner() != owner or set(os.listdir(self.fd)) != {
                "owner.json", "control.sock", "service.log"}:
            raise Failure("监督会话清理时归属或文件集合变化")
        if (path_identity(os.stat("control.sock", dir_fd=self.fd, follow_symlinks=False)) != socket_id or
                path_identity(os.stat("service.log", dir_fd=self.fd, follow_symlinks=False)) != log_id):
            raise Failure("监督控制端或日志身份变化")
        for name in ("port-hopping.state",):
            try:
                os.stat(name, dir_fd=self.net_fd, follow_symlinks=False)
            except FileNotFoundError:
                pass
            else:
                raise Failure("监督规则 state 仍存在")
        locks = self.open_dir("locks", self.root_fd)
        try:
            try:
                os.stat("deployment.lock", dir_fd=locks, follow_symlinks=False)
            except FileNotFoundError:
                pass
            else:
                raise Failure("监督原部署锁未释放")
        finally:
            os.close(self.held.pop())
            self.projection.pop()

    def cleanup(self, owner, socket_id, log_id):
        self.check_stopped(owner, socket_id, log_id)
        for name in ("control.sock", "owner.json", "service.log"):
            os.unlink(name, dir_fd=self.fd)
        self.check()
        os.rmdir(SESSION, dir_fd=self.net_fd)

    def close(self):
        for descriptor in reversed(self.held):
            os.close(descriptor)
        self.held = []


def reserve(root, entrypoint, raw, saved=None):
    pending = stop_signals()
    check_signal(pending)
    original = json.loads(raw, object_pairs_hook=unique)
    owner = str(os.getpid())
    if (not isinstance(original, list) or len(original) < 4 or
            original[-1][0] != root + "/locks/deployment.lock/pid" or
            original[-1][-1] != owner):
        raise Failure("监督预约锁不属于当前进程")
    values = None if saved is None else json.loads(saved, object_pairs_hook=unique)
    if values is not None and (
            not isinstance(values, list) or len(values) != 5 or
            any(not isinstance(value, str) or not value for value in values)):
        raise Failure("监督预约保存参数无效")

    def unchanged():
        result = run_interruptible(
            ["bash", "-Eeuo", "pipefail", "-c", LOCK_BODY, "padm-hopping-reservation-check",
             entrypoint, root, owner], pending)
        if (result.returncode or
                json.loads(result.stdout.decode("ascii"), object_pairs_hook=unique) != original):
            raise Failure("监督预约原锁身份变化")

    directory = Directory(root)
    locks = lock = None
    try:
        unchanged()
        # exec 保持锁 PID；创建预约的进程退出前，普通入口不能按死 PID 清理原锁。
        check_signal(pending)
        directory.session(create=True)
        check_signal(pending)
        directory.check()
        unchanged()
        directory.check()
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
        locks = os.open("locks", flags, dir_fd=directory.root_fd)
        lock = os.open("deployment.lock", flags, dir_fd=locks)
        if ([root + "/locks", *path_identity(os.fstat(locks))[:5]] != original[-3] or
                [root + "/locks/deployment.lock", *path_identity(os.fstat(lock))[:5]] != original[-2]):
            raise Failure("监督预约释放时原锁目录变化")
        if (path_identity(os.stat("locks", dir_fd=directory.root_fd, follow_symlinks=False)) !=
                path_identity(os.fstat(locks)) or
                path_identity(os.stat("deployment.lock", dir_fd=locks, follow_symlinks=False)) !=
                path_identity(os.fstat(lock))):
            raise Failure("监督预约释放时原锁名址变化")
        metadata = os.stat("pid", dir_fd=lock, follow_symlinks=False)
        if ([root + "/locks/deployment.lock/pid", *path_identity(metadata), metadata.st_size,
             metadata.st_mtime_ns, metadata.st_ctime_ns, owner] != original[-1]):
            raise Failure("监督预约释放时原 pid 文件变化")
        check_signal(pending)
        os.unlink("pid", dir_fd=lock)
        check_signal(pending)
        os.rmdir("deployment.lock", dir_fd=locks)
        check_signal(pending)
        directory.check()
        try:
            os.stat("deployment.lock", dir_fd=locks, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise Failure("监督预约原锁未净释放")
        result = {"directory": directory.projection, "session": directory.original}
        if values is not None:
            result["values"] = values
        return result
    finally:
        for descriptor in (lock, locks):
            if descriptor is not None:
                os.close(descriptor)
        directory.close()


def challenge(peer, action, owner=None, pending=None, deadline=None):
    hello = shape(receive(peer, pending=pending, deadline=deadline),
                  ("v", "phase", "action", "client_nonce"))
    if hello["phase"] != "hello" or hello["action"] != action or not nonce(hello["client_nonce"]):
        raise Failure("监督 hello 无效")
    value = {"v": 1, "phase": "challenge", "nonce": os.urandom(32).hex(),
             "client_nonce": hello["client_nonce"], "owner_sha256": digest(owner) if owner else None}
    send(peer, value)
    expected = {"v": 1, "phase": "commit", "nonce": value["nonce"],
                "client_nonce": value["client_nonce"], "action": action}
    if owner:
        expected.update(token=owner["token"], manager_pid=owner["manager"]["pid"],
                        manager_starttime=owner["manager"]["starttime_ticks"],
                        stage_sha256=owner["stage_sha256"], owner_sha256=digest(owner))
    if shape(receive(peer, pending=pending, deadline=deadline), expected) != expected:
        raise Failure("监督 commit 身份或挑战不匹配")
    return value


def ack(phase, proof, owner, **payload):
    return {"v": 1, "phase": phase, "nonce": proof["nonce"],
            "client_nonce": proof["client_nonce"], "owner": owner,
            "owner_sha256": digest(owner), **payload}


def payload_check(value, previous=None, seq=2):
    shape(value, ("target", "running", "child", "directory", "stage"))
    running = shape(value["running"], ("v", "phase", "nonce", "child_id", "request_sha256", "seq"))
    if (running["phase"] != "running" or type(running["seq"]) is not int or running["seq"] != seq or
            not nonce(running["nonce"]) or not nonce(running["request_sha256"]) or
            not nonce(running["child_id"]) or not isinstance(value["target"], dict) or
            not isinstance(value["child"], dict) or value["child"].get("Id") != running["child_id"] or
            not isinstance(value["directory"], list) or not isinstance(value["stage"], str)):
        raise Failure("监督门 payload 身份或序号无效")
    if previous:
        for key in ("target", "child", "directory", "stage"):
            if value[key] != previous[key]:
                raise Failure("监督门原投影漂移")
        if (running["request_sha256"] != previous["running"]["request_sha256"] or
                running["nonce"] == previous["running"]["nonce"]):
            raise Failure("监督门请求摘要或 nonce 漂移")
    return value


def owner_check(value):
    shape(value, ("v", "token", "root", "manager", "bash", "stage", "stage_sha256", "state"))
    if not nonce(value["token"]) or value["state"] != "active" or not nonce(value["stage_sha256"]):
        raise Failure("监督 ACK owner 状态无效")
    for role in ("manager", "bash"):
        process = shape(value[role], ("pid", "starttime_ticks", "boot_id", "pid_ns", "net_ns", "session_id"))
        if any(type(process[key]) is not int or process[key] <= 0 for key in (
                "pid", "starttime_ticks", "session_id")):
            raise Failure("监督 ACK 进程身份无效")
        if any(not isinstance(process[key], str) or not process[key] for key in (
                "boot_id", "pid_ns", "net_ns")):
            raise Failure("监督 ACK namespace 身份无效")
    if (value["manager"]["session_id"] != value["manager"]["pid"] or
            value["bash"]["session_id"] != value["manager"]["session_id"] or
            not isinstance(value["stage"], str) or not isinstance(value["root"], str)):
        raise Failure("监督 ACK 会话身份无效")
    return value


def restarted_target(value, cleaned, action="restart"):
    target = value["target"]
    keys = ("listener_id", "range_start", "range_end", "target_port", "ipv4", "ipv6")
    if action == "restart":
        keys += ("container_id", "image_id")
    if (any(target.get(key) != cleaned["target"].get(key) for key in keys) or
            target.get("started_at") == cleaned["target"].get("started_at") or
            value["child"]["Id"] == cleaned["child_id"]):
        raise Failure("监督重启未证明新代次与原目标")


def change_arguments(action, arguments):
    if (not isinstance(arguments, list) or len(arguments) > 6 or
            any(not isinstance(value, str) or not value or "\0" in value for value in arguments) or
            len(arguments) % 2 or action == "rollback" and arguments):
        raise Failure("监督更新或回滚参数无效")
    if any(arguments[index] not in {"--manifest", "--bundle", "--control-bundle"}
           for index in range(0, len(arguments), 2)):
        raise Failure("监督更新选项无效")
    return arguments


def service(initial_fd, root, entrypoint, values):
    pending_signal = stop_signals()
    deadline, stop_deadline = time.monotonic() + START_TIMEOUT, None
    expired = False
    directory, listener, channel, process, process_fd, log = None, None, None, None, None, None
    initial = socket.socket(fileno=initial_fd)
    stopping, proof, ready, latest, cleaned, finished, stop_peer = (
        False, None, None, None, None, None, None)
    restarting, restart_receipt, restart_gate = False, None, False
    change_action, arguments, change_status = None, [], None

    def launch(action=None):
        nonlocal channel, process, process_fd
        check_signal(pending_signal)
        remaining_time(deadline)
        channel, child = socket.socketpair()
        try:
            process = subprocess.Popen(
                ["bash", "-c", BODY, "padm-hopping-owner", entrypoint, root,
                 str(child.fileno()), *values, *([f"--{action}", *arguments] if action else [])],
                pass_fds=(child.fileno(),), stdin=subprocess.DEVNULL, stdout=log, stderr=log)
        finally:
            child.close()
        owner["bash"] = identity(process.pid)
        process_fd = pin(owner["bash"])
        check_signal(pending_signal)
        directory.write_owner(owner)

    def request_stop():
        nonlocal stopping, stop_deadline
        if not stopping:
            try:
                signal.pidfd_send_signal(process_fd, signal.SIGTERM)
            except ProcessLookupError:
                pass
            stopping = True
            stop_deadline = time.monotonic() + STOP_TIMEOUT

    def check_progress():
        nonlocal expired, restarting
        if deadline is not None and time.monotonic() >= deadline and not expired:
            expired, restarting = True, False
            os.write(log, "监督事务总时限已到，等待原 Bash 净撤销\n".encode("utf-8"))
            request_stop()
        if stop_deadline is not None:
            remaining_time(stop_deadline)

    try:
        check_signal(pending_signal)
        if os.geteuid() != 0 or len(values) not in {0, 5}:
            raise Failure("监督服务仅支持 root、保存配置或内部五参数")
        peer_pid(initial)
        own = identity(os.getpid())
        if own["session_id"] != own["pid"]:
            raise Failure("监督服务必须属于独立会话")
        # 先完成挑战；等待普通部署锁不消耗 hello 帧预算，commit 前不创建会话。
        directory = Directory(root)
        directory.close()
        directory = None
        proof = challenge(initial, "start", pending=pending_signal, deadline=deadline)
        reservation = run_interruptible(
            ["bash", "-Eeuo", "pipefail", "-c", RESERVE_BODY, "padm-hopping-reservation",
             entrypoint, root, sys.executable, str(Path(__file__).resolve()),
             *(["--saved"] if not values else [])],
            # 保存模式在预约锁内读取参数，不采用调用端较早读取的元组。
            pending_signal, deadline=deadline)
        if reservation.returncode:
            raise Failure("监督会话预约失败: " + reservation.stderr.decode("utf-8", errors="replace"))
        reserved = shape(json.loads(reservation.stdout.decode("ascii"), object_pairs_hook=unique),
                         ("directory", "session", "values") if not values else ("directory", "session"))
        if not values:
            values = reserved.pop("values")
        check_signal(pending_signal)
        directory = Directory(root)
        directory.session()
        # 原锁只用于预约，不转交给监督 Bash；替换预约路径后保留证据并拒绝启动。
        if canonical(reserved) != canonical({
                "directory": directory.projection, "session": directory.original}):
            raise Failure("监督会话预约目录身份变化")
        directory.check()
        check_signal(pending_signal)
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        listener.bind(f"/proc/self/fd/{directory.fd}/control.sock")
        check_signal(pending_signal)
        os.chmod(directory.path + "/control.sock", 0o600)
        listener.listen(4)
        socket_id = path_identity(os.stat("control.sock", dir_fd=directory.fd, follow_symlinks=False))
        log = os.open("service.log", os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                      0o600, dir_fd=directory.fd)
        check_signal(pending_signal)
        log_id = path_identity(os.fstat(log))
        owner = {"v": 1, "token": os.urandom(32).hex(), "root": root, "manager": own,
                 "bash": None, "stage": None, "stage_sha256": None, "state": "starting"}
        directory.write_owner(owner)
        check_signal(pending_signal)
        # 独立 Bash 自取锁并 freshly bound；环境变量只提供安装路径，不提供授权。
        launch()
        last_gate = None
        while True:
            check_progress()
            if pending_signal[0]:
                request_stop()
            watched = [listener, process_fd] + ([channel] if finished is None else [])
            readable = select.select(watched, [], [], 0.2)[0]
            if channel in readable:
                event = shape(receive(channel, deadline=stop_deadline if stopping else deadline),
                              ("v", "phase", "nonce", "payload"))
                check_progress()
                if pending_signal[0]:
                    request_stop()
                if not nonce(event["nonce"]) or event["nonce"] == last_gate:
                    raise Failure("监督门 nonce 重复")
                last_gate = event["nonce"]
                phase, value = event["phase"], event["payload"]
                witness = latest or ready
                if stopping and phase in {"restart", "update", "rollback", "changed", "ready", "started", "running"}:
                    send(channel, {"v": 1, "phase": "stop", "nonce": event["nonce"]})
                elif (phase == change_action and restart_receipt is not None and
                      not restart_gate and ready is None and latest is None and not stopping):
                    shape(value, ("bash_pid", "lock"))
                    if type(value["bash_pid"]) is not int or value["bash_pid"] != process.pid:
                        raise Failure("监督重启写门 Bash 不匹配")
                    result = run_interruptible(
                        ["bash", "-Eeuo", "pipefail", "-c", LOCK_BODY, "padm-hopping-restart-check",
                         entrypoint, root, str(process.pid)], pending_signal, deadline=deadline)
                    if (result.returncode or
                            json.loads(result.stdout, object_pairs_hook=unique) != value["lock"] or
                            directory.read_owner() != owner or
                            select.select([process_fd], [], [], 0)[0]):
                        raise Failure("监督重启写门原锁或 owner 不匹配")
                    restart_gate = True
                    check_progress()
                    if pending_signal[0]:
                        request_stop()
                    send(channel, {"v": 1, "phase": "stop" if stopping else "commit",
                                   "nonce": event["nonce"]})
                elif (phase == "changed" and change_action in {"update", "rollback"} and
                      restart_gate and change_status is None and ready is None and not stopping):
                    shape(value, ("status",))
                    if type(value["status"]) is not int or not 0 <= value["status"] <= 255:
                        raise Failure("监督事务返回状态无效")
                    change_status = value["status"]
                    check_progress()
                    if pending_signal[0]:
                        request_stop()
                    send(channel, {"v": 1, "phase": "stop" if stopping else "commit",
                                   "nonce": event["nonce"]})
                elif phase == "ready" and ready is None and latest is None and not stopping:
                    if restart_receipt is not None and not restart_gate:
                        raise Failure("监督重启未经过新写门")
                    if change_action in {"update", "rollback"} and change_status is None:
                        raise Failure("监督更新或回滚没有事务回执")
                    ready = payload_check(value)
                    if restart_receipt is not None:
                        restarted_target(ready, restart_receipt["cleaned"], change_action)
                    if (PurePosixPath(ready["stage"]).parent != PurePosixPath(root) or
                            not PurePosixPath(ready["stage"]).name.startswith(".hopping-guarded.")):
                        raise Failure("监督 stage 超出受管根")
                    owner.update(stage=ready["stage"], stage_sha256=digest({
                        key: ready[key] for key in ("target", "child", "directory", "stage")}))
                    directory.write_owner(owner)
                    check_progress()
                    if pending_signal[0]:
                        request_stop()
                    send(channel, {"v": 1, "phase": "stop" if stopping else "commit",
                                   "nonce": event["nonce"]})
                elif phase == "started" and latest is None and value == ready and not stopping:
                    latest = ready
                    owner["state"] = "active"
                    directory.write_owner(owner)
                    check_progress()
                    if pending_signal[0]:
                        request_stop()
                    send(channel, {"v": 1, "phase": "stop" if stopping else "continue",
                                   "nonce": event["nonce"]})
                    check_progress()
                    if pending_signal[0]:
                        request_stop()
                    try:
                        if stopping:
                            pass
                        elif restart_receipt is None:
                            send(initial, ack("started", proof, owner, payload=latest))
                        else:
                            receipt = dict(restart_receipt)
                            if change_action in {"update", "rollback"}:
                                receipt["change"] = dict(action=change_action, arguments=arguments,
                                                         status=change_status)
                            send(stop_peer, ack({"restart": "restarted", "update": "updated",
                                                 "rollback": "rolled_back"}[change_action],
                                                proof, owner, payload=latest, **receipt))
                    except (BrokenPipeError, ConnectionResetError):
                        # commit 后调用者退出不撤销；之后只能按新挑战读取当前状态。
                        pass
                    if initial is not None:
                        initial.close()
                        initial = None
                    if stop_peer is not None:
                        stop_peer.close()
                        stop_peer = None
                    restart_receipt = None
                    change_action, arguments, change_status = None, [], None
                    deadline = None
                elif phase == "running" and latest is not None and not stopping:
                    latest = payload_check(value, latest, latest["running"]["seq"] + 1)
                    directory.check()
                    if directory.read_owner() != owner:
                        raise Failure("监督 owner 在运行中变化")
                    check_progress()
                    send(channel, {"v": 1, "phase": "stop" if stopping else "continue",
                                   "nonce": event["nonce"]})
                elif phase == "cleaned" and stopping and cleaned is None and witness is not None:
                    shape(value, ("target", "child_id", "stage"))
                    if value != {"target": witness["target"], "child_id": witness["child"]["Id"],
                                 "stage": witness["stage"]}:
                        raise Failure("监督净清理回执投影不匹配")
                    cleaned = value
                elif phase == "finished" and finished is None:
                    shape(value, ("status", "lock_released"))
                    if type(value["status"]) is not int or type(value["lock_released"]) is not bool:
                        raise Failure("监督退出回执类型无效")
                    finished = value
                else:
                    raise Failure("监督门阶段不匹配")
            if listener in readable and not stopping:
                peer, _ = listener.accept()
                try:
                    peer_pid(peer)
                    directory.check()
                    if latest is None or directory.read_owner() != owner:
                        raise Failure("监督尚未启用或 owner 已变化")
                    hello = receive(peer, timeout=2)
                    action = hello.get("action") if isinstance(hello, dict) else None
                    if action not in {"status", "stop", "restart", "update", "rollback"}:
                        raise Failure("监督控制动作无效")
                    keys = ("v", "phase", "action", "client_nonce")
                    shape(hello, (*keys, "arguments") if action in {"update", "rollback"} else keys)
                    requested = change_arguments(action, hello["arguments"]) if action in {
                        "update", "rollback"} else []
                    # 仅把已读取的 hello 交给同一挑战函数，连接没有重复读取。
                    control_proof = challenge_from_hello(peer, action, owner, hello)
                    directory.check()
                    if directory.read_owner() != owner or select.select([process_fd], [], [], 0)[0]:
                        raise Failure("监督控制提交后原 owner 或 Bash 已变化")
                    if action == "status":
                        send(peer, ack("status", control_proof, owner, payload=latest))
                    else:
                        deadline = time.monotonic() + (
                            CHANGE_TIMEOUT if action in {"update", "rollback"} else START_TIMEOUT)
                        expired = False
                        request_stop()
                        stop_peer, proof = peer, control_proof
                        restarting = action in {"restart", "update", "rollback"}
                        change_action, arguments = action, requested
                        peer = None
                except (Failure, OSError, ValueError) as error:
                    os.write(log, (str(error) + "\n").encode("utf-8"))
                finally:
                    if peer is not None:
                        peer.close()
            if process_fd in readable:
                # Bash 退出后先消费已排队的 notify；不能把 pidfd 终止当作净撤销。
                witness = latest or ready
                while finished is None and select.select([channel], [], [], 0)[0]:
                    event = shape(receive(channel, deadline=stop_deadline),
                                  ("v", "phase", "nonce", "payload"))
                    if not nonce(event["nonce"]) or event["nonce"] == last_gate:
                        raise Failure("监督退出通知 nonce 重复")
                    last_gate = event["nonce"]
                    if event["phase"] == "finished":
                        finished = shape(event["payload"], ("status", "lock_released"))
                        if (type(finished["status"]) is not int or
                                type(finished["lock_released"]) is not bool):
                            raise Failure("监督退出回执类型无效")
                    elif event["phase"] == "cleaned" and cleaned is None and stopping and witness is not None:
                        cleaned = shape(event["payload"], ("target", "child_id", "stage"))
                        if cleaned != {"target": witness["target"], "child_id": witness["child"]["Id"],
                                       "stage": witness["stage"]}:
                            raise Failure("监督净清理回执投影不匹配")
                    else:
                        raise Failure("监督退出后出现未知通知")
                status = process.wait(timeout=2)
                if (stopping and witness is not None and cleaned == {
                        "target": witness["target"], "child_id": witness["child"]["Id"],
                        "stage": witness["stage"]} and finished == {
                        "status": 143, "lock_released": True} and status == 143):
                    check_progress()
                    if restarting and not pending_signal[0] and not expired:
                        # 会话目录覆盖整个交接窗口；旧净停止回执不授权新 Bash 写入。
                        directory.check_stopped(owner, socket_id, log_id)
                        restart_receipt = dict(previous_owner=owner, cleaned=cleaned, finished=finished)
                        channel.close()
                        os.close(process_fd)
                        channel, process_fd = None, None
                        owner = {**owner, "token": os.urandom(32).hex(), "bash": None,
                                 "stage": None, "stage_sha256": None, "state": "starting"}
                        directory.write_owner(owner)
                        stopping, restarting, restart_gate = False, False, False
                        stop_deadline = None
                        ready, latest, cleaned, finished, last_gate = None, None, None, None, None
                        launch(action=change_action)
                        continue
                    directory.cleanup(owner, socket_id, log_id)
                    check_progress()
                    if stop_peer and not expired:
                        send(stop_peer, ack("stopped", proof, owner, cleaned=cleaned, finished=finished))
                    return
                raise Failure("监督未证明净撤销或原锁释放，保留会话")
    except BaseException as error:
        if log is not None:
            os.write(log, (str(error) + "\n").encode("utf-8"))
        raise
    finally:
        if channel is not None:
            channel.close()
        if process is not None and process.poll() is None:
            try:
                if process_fd is not None:
                    signal.pidfd_send_signal(process_fd, signal.SIGTERM)
                else:
                    process.terminate()
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=max(0, stop_deadline - time.monotonic())
                             if stop_deadline is not None else STOP_TIMEOUT)
            except subprocess.TimeoutExpired:
                pass
        if process_fd is not None:
            os.close(process_fd)
        for peer in (initial, stop_peer, listener):
            if peer is not None:
                peer.close()
        if log is not None:
            os.close(log)
        if directory is not None:
            directory.close()


def challenge_from_hello(peer, action, owner, hello):
    if hello["phase"] != "hello" or not nonce(hello["client_nonce"]):
        raise Failure("监督 hello 无效")
    proof = {"v": 1, "phase": "challenge", "nonce": os.urandom(32).hex(),
             "client_nonce": hello["client_nonce"], "owner_sha256": digest(owner)}
    send(peer, proof)
    expected = {"v": 1, "phase": "commit", "nonce": proof["nonce"],
                "client_nonce": proof["client_nonce"], "action": action, "token": owner["token"],
                "manager_pid": owner["manager"]["pid"],
                "manager_starttime": owner["manager"]["starttime_ticks"],
                "stage_sha256": owner["stage_sha256"], "owner_sha256": digest(owner)}
    if action in {"update", "rollback"}:
        expected["arguments"] = hello["arguments"]
    if shape(receive(peer, timeout=2), expected) != expected:
        raise Failure("监督 commit 身份或挑战不匹配")
    return proof


def client(peer, action, owner=None, token=None, arguments=None):
    changing = action in {"update", "rollback"}
    transitioning = action in {"restart", "update", "rollback"}
    deadline = time.monotonic() + (
        CHANGE_TIMEOUT if changing else START_TIMEOUT) + STOP_TIMEOUT
    hello = {"v": 1, "phase": "hello", "action": action, "client_nonce": os.urandom(32).hex()}
    if changing:
        hello["arguments"] = change_arguments(action, [] if arguments is None else arguments)
    send(peer, hello)
    proof = shape(receive(peer, deadline=deadline),
                  ("v", "phase", "nonce", "client_nonce", "owner_sha256"))
    if (proof["phase"] != "challenge" or not nonce(proof["nonce"]) or
            proof["nonce"] == hello["client_nonce"] or proof["client_nonce"] != hello["client_nonce"] or
            proof["owner_sha256"] != (digest(owner) if owner else None)):
        raise Failure("监督挑战不匹配")
    request = {"v": 1, "phase": "commit", "nonce": proof["nonce"],
               "client_nonce": proof["client_nonce"], "action": action}
    if owner:
        request.update(token=owner["token"] if token is None else token,
                       manager_pid=owner["manager"]["pid"],
                       manager_starttime=owner["manager"]["starttime_ticks"],
                       stage_sha256=owner["stage_sha256"], owner_sha256=digest(owner))
    if changing:
        request["arguments"] = hello["arguments"]
    send(peer, request)
    result = receive(peer, timeout=CHANGE_TIMEOUT + STOP_TIMEOUT if changing else
                     START_TIMEOUT + STOP_TIMEOUT, deadline=deadline)
    keys = ("v", "phase", "nonce", "client_nonce", "owner", "owner_sha256")
    shape(result, (*keys, "cleaned", "finished") if action == "stop" else
          (*keys, "payload", "previous_owner", "cleaned", "finished", "change") if changing else
          (*keys, "payload", "previous_owner", "cleaned", "finished") if transitioning else
          (*keys, "payload"))
    expected_phase = {"start": "started", "stop": "stopped", "restart": "restarted",
                      "update": "updated", "rollback": "rolled_back", "status": "status"}[action]
    if (result["phase"] != expected_phase or result["nonce"] != proof["nonce"] or
            result["client_nonce"] != proof["client_nonce"] or
            result["owner_sha256"] != digest(result["owner"]) or
            owner is not None and not transitioning and result["owner"] != owner):
        raise Failure("监督 ACK 不匹配")
    active_owner = owner_check(result["owner"])
    if action == "stop" or transitioning:
        finished = shape(result["finished"], ("status", "lock_released"))
        cleaned = shape(result["cleaned"], ("target", "child_id", "stage"))
        if (type(finished["status"]) is not int or finished["status"] != 143 or
                type(finished["lock_released"]) is not bool or not finished["lock_released"] or
                cleaned["stage"] != (owner if transitioning else active_owner)["stage"] or
                not nonce(cleaned["child_id"]) or
                not isinstance(cleaned["target"], dict)):
            raise Failure("监督停止 ACK 未证明净撤销")
    if action != "stop":
        value = payload_check(result["payload"], seq=result["payload"]["running"]["seq"])
        if (value["running"]["seq"] < 2 or value["stage"] != active_owner["stage"] or
                digest({key: value[key] for key in (
                    "target", "child", "directory", "stage")}) != active_owner["stage_sha256"]):
            raise Failure("监督 ACK 原 stage 投影不匹配")
        if transitioning:
            if (result["previous_owner"] != owner or
                    any(active_owner[key] != owner[key] for key in ("root", "manager")) or
                    any(active_owner[key] == owner[key] for key in ("token", "bash", "stage")) or
                    active_owner["bash"]["starttime_ticks"] <= owner["bash"]["starttime_ticks"]):
                raise Failure("监督重启 ACK 未证明新代次与原目标")
            restarted_target(value, cleaned, action)
    if changing:
        changed = shape(result["change"], ("action", "arguments", "status"))
        if (changed["action"] != action or changed["arguments"] != hello["arguments"] or
                type(changed["status"]) is not int or not 0 <= changed["status"] <= 255):
            raise Failure("监督事务 ACK 返回状态或参数不匹配")
    return result


def start(root, entrypoint, values):
    directory = Directory(root)
    directory.close()
    path = Path(entrypoint)
    if not path.is_absolute() or path.is_symlink():
        raise Failure("监督入口必须是安全绝对路径")
    metadata = path.stat()
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0 or metadata.st_mode & 0o022:
        raise Failure("监督入口身份或权限无效")
    caller, manager = socket.socketpair()
    process = subprocess.Popen(
        [sys.executable, "-B", str(Path(__file__).resolve()), "_service", str(manager.fileno()),
         root, entrypoint, *values], pass_fds=(manager.fileno(),), start_new_session=True,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    manager.close()
    process_fd = None
    try:
        expected = identity(process.pid)
        process_fd = pin(expected)
        result = client(caller, "start")
        if result["owner"]["manager"] != expected or select.select([process_fd], [], [], 0)[0]:
            raise Failure("监督启动 ACK 后管理进程已变化")
        return result
    finally:
        caller.close()
        if process_fd is not None:
            os.close(process_fd)


def control(action, root, token=None, arguments=None):
    directory = Directory(root)
    peer, descriptor = None, None
    try:
        directory.session()
        owner = directory.read_owner()
        descriptor = pin(owner["manager"])
        metadata = os.stat("control.sock", dir_fd=directory.fd, follow_symlinks=False)
        if (not stat.S_ISSOCK(metadata.st_mode) or metadata.st_uid != 0 or
                stat.S_IMODE(metadata.st_mode) != 0o600):
            raise Failure("监督控制 socket 身份或权限无效")
        peer = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        peer.connect(f"/proc/self/fd/{directory.fd}/control.sock")
        if peer_pid(peer) != owner["manager"]["pid"] or identity(owner["manager"]["pid"]) != owner["manager"]:
            raise Failure("监督控制 peer 代次无效")
        if path_identity(metadata) != path_identity(os.stat(
                "control.sock", dir_fd=directory.fd, follow_symlinks=False)):
            raise Failure("连接时监督 socket 被替换")
        result = client(peer, action, owner, token, arguments)
        if action in {"status", "restart", "update", "rollback"}:
            if (select.select([descriptor], [], [], 0)[0] or
                    directory.read_owner() != result["owner"]):
                raise Failure("监督状态 ACK 后身份变化")
        return result
    finally:
        if peer is not None:
            peer.close()
        if descriptor is not None:
            os.close(descriptor)
        directory.close()


def file_stamp(metadata):
    return (*path_identity(metadata), metadata.st_size, metadata.st_mtime_ns, metadata.st_ctime_ns)


def recovery_dead(owner):
    current = identity(os.getpid())
    for role in ("manager", "bash"):
        expected = owner[role]
        if any(expected[key] != current[key] for key in ("boot_id", "pid_ns", "net_ns")):
            raise Failure("恢复只支持同一 boot、PID 与网络 namespace")
        if expected["pid"] > 2147483647:
            raise Failure("恢复原 PID 超出范围")
        try:
            descriptor = os.pidfd_open(expected["pid"])
        except ProcessLookupError:
            continue
        try:
            if not select.select([descriptor], [], [], 0)[0]:
                raise Failure("恢复原 manager 或 Bash PID 仍在运行")
        finally:
            os.close(descriptor)


def recover(root, entrypoint, confirm=False):
    pending = stop_signals()
    directory = Directory(root)
    held = []
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC
    stage_names = {"prepared.json", "cid", "child.log", "supervised.json"}
    session_names = {"owner.json", "control.sock", "service.log"}
    lock_names = {"pid"}
    stage_removed, lock_removed = False, False
    deadline = time.monotonic() + START_TIMEOUT

    def opened(name, parent, is_dir=False, mode=None):
        descriptor = os.open(name, flags | (os.O_DIRECTORY if is_dir else 0), dir_fd=parent)
        held.append(descriptor)
        metadata = os.fstat(descriptor)
        if (metadata.st_uid != 0 or metadata.st_mode & 0o022 or
                not (stat.S_ISDIR(metadata.st_mode) if is_dir else stat.S_ISREG(metadata.st_mode)) or
                not is_dir and metadata.st_nlink != 1 or
                mode is not None and stat.S_IMODE(metadata.st_mode) != mode):
            raise Failure("恢复文件或目录 owner、类型、权限无效")
        return descriptor

    def regular(parent, name):
        descriptor = os.open(name, flags, dir_fd=parent)
        try:
            metadata = os.fstat(descriptor)
            if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0 or
                    metadata.st_nlink != 1 or metadata.st_mode & 0o022):
                raise Failure("恢复受管文件身份无效")
            if file_stamp(metadata) != file_stamp(os.stat(name, dir_fd=parent, follow_symlinks=False)):
                raise Failure("恢复受管文件在打开时变化")
            return file_stamp(metadata)
        finally:
            os.close(descriptor)

    def absent(parent, name):
        try:
            os.stat(name, dir_fd=parent, follow_symlinks=False)
        except FileNotFoundError:
            return
        raise Failure("恢复要求规则 state 或已删除路径保持不存在")

    try:
        path = Path(entrypoint)
        if not path.is_absolute() or path.is_symlink():
            raise Failure("恢复入口必须是安全绝对路径")
        entry_fd = opened(entrypoint, None)
        entry_stamp = file_stamp(os.fstat(entry_fd))
        directory.session()
        owner_fd = opened("owner.json", directory.fd, mode=0o600)
        # 同一原 owner inode 上排斥两个恢复者；普通部署仍由会话目录门禁阻断。
        fcntl.flock(owner_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        owner = owner_check(directory.read_owner())
        recovery_dead(owner)
        stage_path = PurePosixPath(owner["stage"])
        if (str(stage_path) != owner["stage"] or stage_path.parent != PurePosixPath(root) or
                not stage_path.name.startswith(".hopping-guarded.") or
                stage_path.name == ".hopping-guarded."):
            raise Failure("恢复 stage 超出受管根")
        stage_fd = opened(stage_path.name, directory.root_fd, True, 0o700)
        locks_fd = opened("locks", directory.root_fd, True, 0o750)
        lock_fd = opened("deployment.lock", locks_fd, True, 0o750)
        stage_id, locks_id, lock_id = (
            path_identity(os.fstat(item)) for item in (stage_fd, locks_fd, lock_fd))
        if (set(os.listdir(stage_fd)) != stage_names or
                set(os.listdir(directory.fd)) != session_names or set(os.listdir(lock_fd)) != lock_names):
            raise Failure("恢复 stage、会话或锁含未知文件")
        stage_files = {name: regular(stage_fd, name) for name in stage_names}
        session_files = {name: regular(directory.fd, name) for name in ("owner.json", "service.log")}
        socket_id = path_identity(os.stat("control.sock", dir_fd=directory.fd, follow_symlinks=False))
        if (not stat.S_ISSOCK(socket_id[2]) or socket_id[3] != 0 or
                stat.S_IMODE(socket_id[2]) != 0o600 or socket_id[-1] != 1):
            raise Failure("恢复控制 socket 身份无效")
        pid_stamp = regular(lock_fd, "pid")
        pid_fd = opened("pid", lock_fd, mode=0o640)
        expected_pid = (str(owner["bash"]["pid"]) + "\n").encode("ascii")
        if (os.read(pid_fd, len(expected_pid) + 1) != expected_pid or
                file_stamp(os.fstat(pid_fd)) != pid_stamp):
            raise Failure("恢复原锁 pid 不匹配")
        cid_fd = opened("cid", stage_fd)
        cid = os.read(cid_fd, 66).decode("ascii").strip()
        if not nonce(cid) or file_stamp(os.fstat(cid_fd)) != stage_files["cid"]:
            raise Failure("恢复原 child ID 无效")
        path_rows, current_path = ["/"], ""
        for part in PurePosixPath(root).parts[1:]:
            current_path += "/" + part
            path_rows.append(current_path)
        path_rows.extend((root + "/data", root + "/data/net"))
        projection = [[name, *value] for name, value in zip(path_rows, directory.projection[:-1])]

        def check():
            check_signal(pending)
            remaining_time(deadline)
            directory.check()
            recovery_dead(owner)
            if (file_stamp(os.stat(entrypoint, follow_symlinks=False)) != entry_stamp or
                    file_stamp(os.fstat(entry_fd)) != entry_stamp):
                raise Failure("恢复入口身份变化")
            current_locks = (*locks_id[:-1], locks_id[-1] - int(lock_removed))
            if (path_identity(os.stat("locks", dir_fd=directory.root_fd,
                                      follow_symlinks=False)) != current_locks or
                    path_identity(os.fstat(locks_fd)) != current_locks):
                raise Failure("恢复原 locks 目录变化")
            for removed, parent, name, descriptor, original, names, files in (
                    (stage_removed, directory.root_fd, stage_path.name, stage_fd,
                     stage_id, stage_names, stage_files),
                    (lock_removed, locks_fd, "deployment.lock", lock_fd,
                     lock_id, lock_names, {"pid": pid_stamp})):
                if removed:
                    absent(parent, name)
                    continue
                if (path_identity(os.stat(name, dir_fd=parent, follow_symlinks=False)) != original or
                        path_identity(os.fstat(descriptor)) != original or
                        set(os.listdir(descriptor)) != names):
                    raise Failure("恢复原 stage 或锁目录身份、文件集合变化")
                for item in names:
                    if regular(descriptor, item) != files[item]:
                        raise Failure("恢复原 stage 或锁文件变化")
            if set(os.listdir(directory.fd)) != session_names:
                raise Failure("恢复原会话文件集合变化")
            for name in session_names - {"control.sock"}:
                if regular(directory.fd, name) != session_files[name]:
                    raise Failure("恢复原 owner 或日志变化")
            if "owner.json" in session_names and (
                    file_stamp(os.fstat(owner_fd)) != session_files["owner.json"] or
                    directory.read_owner() != owner):
                raise Failure("恢复原 owner 已替换")
            if "control.sock" in session_names and path_identity(os.stat(
                    "control.sock", dir_fd=directory.fd, follow_symlinks=False)) != socket_id:
                raise Failure("恢复原控制 socket 已替换")
            absent(directory.net_fd, "port-hopping.state")

        def inspect():
            check()
            result = run_interruptible(
                ["bash", "-Eeuo", "pipefail", "-c", RECOVER_BODY, "padm-hopping-recovery",
                 entrypoint, root, canonical(owner).decode("ascii")], pending, deadline)
            if result.returncode:
                raise Failure("恢复现场审计失败: " + result.stderr.decode("utf-8", errors="replace"))
            audit = shape(json.loads(result.stdout.decode("ascii"), object_pairs_hook=unique),
                          ("target", "child", "directory", "stage", "saved"))
            if (audit["stage"] != owner["stage"] or not isinstance(audit["target"], dict) or
                    not isinstance(audit["child"], dict) or audit["child"].get("Id") != cid or
                    audit["directory"] != projection or not isinstance(audit["saved"], dict) or
                    digest({key: audit[key] for key in (
                        "target", "child", "directory", "stage")}) != owner["stage_sha256"]):
                raise Failure("恢复审计原 stage、child 或摘要不匹配")
            original = audit["target"]["startup_binding"]["lock"]
            if (not isinstance(original, list) or len(original) < 3 or
                    original[-3] != [root + "/locks", *locks_id[:5]] or
                    original[-2] != [root + "/locks/deployment.lock", *lock_id[:5]] or
                    original[-1] != [root + "/locks/deployment.lock/pid", *pid_stamp,
                                     str(owner["bash"]["pid"])]):
                raise Failure("恢复审计原锁与持有目录不匹配")
            check()
            return audit

        audit = inspect()
        result = {"state": "recoverable", "saved": audit["saved"], "owner_sha256": digest(owner),
                  "child_id": cid, "stage": owner["stage"]}
        if not confirm:
            return result
        if inspect() != audit:
            raise Failure("恢复确认复验时现场投影变化")
        check()
        removed = run_interruptible(
            ["timeout", "-k", "2", "10", "docker", "container", "rm", cid], pending, deadline)
        if removed.returncode:
            raise Failure("恢复不能移除已核验的退出 helper: " +
                          removed.stderr.decode("utf-8", errors="replace"))
        remaining = run_interruptible(
            ["timeout", "-k", "2", "5", "docker", "container", "ls", "-a", "--no-trunc",
             "--filter", "id=" + cid, "--format", "{{.ID}}"], pending, deadline)
        if remaining.returncode or remaining.stdout.strip():
            raise Failure("恢复未证明原 helper 已删除")
        check()
        for name in sorted(stage_names):
            check()
            os.unlink(name, dir_fd=stage_fd)
            stage_names.remove(name)
        check()
        os.rmdir(stage_path.name, dir_fd=directory.root_fd)
        stage_removed = True
        check()
        os.unlink("pid", dir_fd=lock_fd)
        lock_names.clear()
        check()
        os.rmdir("deployment.lock", dir_fd=locks_fd)
        lock_removed = True
        # 会话目录最后删除；部分清理或信号失败时继续阻挡普通部署操作。
        for name in ("control.sock", "service.log", "owner.json"):
            check()
            os.unlink(name, dir_fd=directory.fd)
            session_names.remove(name)
        check()
        os.rmdir(SESSION, dir_fd=directory.net_fd)
        return dict(result, state="stopped")
    finally:
        for descriptor in reversed(held):
            os.close(descriptor)
        directory.close()


def helper(command, phase, raw):
    peer = socket.socket(fileno=os.dup(0))
    try:
        peer_pid(peer)
        value = json.loads(raw, object_pairs_hook=unique)
        proof = {"v": 1, "phase": phase, "nonce": os.urandom(32).hex(), "payload": value}
        send(peer, proof)
        if command == "gate":
            if phase not in {"restart", "update", "rollback", "changed", "ready", "started", "running"}:
                raise Failure("监督 gate 阶段无效")
            response = shape(receive(peer), ("v", "phase", "nonce"))
            if response != {"v": 1, "phase": "commit" if phase in {
                    "ready", "restart", "update", "rollback", "changed"} else "continue",
                            "nonce": proof["nonce"]}:
                raise Failure("监督 gate 授权不匹配")
        elif phase not in {"cleaned", "finished"}:
            raise Failure("监督 notify 阶段无效")
    finally:
        peer.close()


def main(arguments):
    if not arguments or os.geteuid() != 0:
        raise Failure("监督入口仅支持 Linux root")
    operation, *args = arguments
    if operation in {"gate", "notify"} and len(args) == 2:
        helper(operation, *args)
        return
    if operation == "_service" and len(args) in {3, 8}:
        service(int(args[0]), args[1], args[2], args[3:])
        return
    if operation == "_reserve" and len(args) in {3, 4}:
        result = reserve(*args)
    elif operation == "start" and len(args) in {2, 7}:
        result = start(args[0], args[1], args[2:])
    elif operation == "recover" and (len(args) == 2 or len(args) == 3 and args[2] == "--confirm"):
        result = recover(args[0], args[1], len(args) == 3)
    elif operation == "status" and len(args) == 1:
        result = control("status", args[0])
    elif operation in {"stop", "restart"} and len(args) in {1, 2}:
        result = control(operation, args[0], args[1] if len(args) == 2 else None)
    elif operation in {"update", "rollback"} and args:
        changes = change_arguments(operation, args[1:])
        changes = [value if index % 2 == 0 or value.startswith("https://") else
                   os.path.abspath(value) for index, value in enumerate(changes)]
        result = control(operation, args[0], arguments=changes)
    else:
        raise Failure("监督入口参数无效")
    print(canonical(result).decode("ascii"))
    if operation in {"update", "rollback"}:
        raise SystemExit(result["change"]["status"])


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (Failure, ValueError, KeyError, TypeError, UnicodeError, OSError) as error:
        print("跳跃独立监督拒绝: " + str(error), file=sys.stderr)
        raise SystemExit(12 if sys.argv[1:2] in (["update"], ["rollback"]) else 1)
