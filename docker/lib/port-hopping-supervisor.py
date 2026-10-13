#!/usr/bin/env python3
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
exec "$3" -B "$4" _reserve "${PADM_DOCKER_INSTALL_DIR}" "$1" "${original}"
'''
LOCK_BODY = r'''
source "$1"
PADM_DOCKER_INSTALL_DIR=$2
DOCKER_DEPLOYMENT_LOCK_DIR=$2/locks/deployment.lock
export PADM_DOCKER_INSTALL_DIR
dockerPortHoppingTargetLockSnapshot "$3"
'''


class Failure(Exception):
    pass


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


def receive(peer, timeout=20):
    deadline, raw = time.monotonic() + timeout, b""
    while not raw.endswith(b"\n"):
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([peer], [], [], remaining)[0]:
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


def reserve(root, entrypoint, raw):
    original = json.loads(raw, object_pairs_hook=unique)
    owner = str(os.getpid())
    if (not isinstance(original, list) or len(original) < 4 or
            original[-1][0] != root + "/locks/deployment.lock/pid" or
            original[-1][-1] != owner):
        raise Failure("监督预约锁不属于当前进程")

    def unchanged():
        result = subprocess.run(
            ["bash", "-Eeuo", "pipefail", "-c", LOCK_BODY, "padm-hopping-reservation-check",
             entrypoint, root, owner], capture_output=True)
        if (result.returncode or
                json.loads(result.stdout.decode("ascii"), object_pairs_hook=unique) != original):
            raise Failure("监督预约原锁身份变化")

    directory = Directory(root)
    locks = lock = None
    try:
        unchanged()
        # exec 保持锁 PID；创建预约的进程退出前，普通入口不能按死 PID 清理原锁。
        directory.session(create=True)
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
        os.unlink("pid", dir_fd=lock)
        os.rmdir("deployment.lock", dir_fd=locks)
        directory.check()
        try:
            os.stat("deployment.lock", dir_fd=locks, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise Failure("监督预约原锁未净释放")
        return {"directory": directory.projection, "session": directory.original}
    finally:
        for descriptor in (lock, locks):
            if descriptor is not None:
                os.close(descriptor)
        directory.close()


def challenge(peer, action, owner=None):
    hello = shape(receive(peer), ("v", "phase", "action", "client_nonce"))
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
    if shape(receive(peer), expected) != expected:
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


def restarted_target(value, cleaned):
    target = value["target"]
    if (any(target.get(key) != cleaned["target"].get(key) for key in (
            "container_id", "image_id", "listener_id", "range_start", "range_end",
            "target_port", "ipv4", "ipv6")) or
            target.get("started_at") == cleaned["target"].get("started_at") or
            value["child"]["Id"] == cleaned["child_id"]):
        raise Failure("监督重启未证明新代次与原目标")


def service(initial_fd, root, entrypoint, values):
    directory, listener, channel, process, process_fd, log = None, None, None, None, None, None
    initial = socket.socket(fileno=initial_fd)
    stopping, proof, ready, latest, cleaned, finished, stop_peer = (
        False, None, None, None, None, None, None)
    restarting, restart_receipt, restart_gate = False, None, False

    def launch(restart=False):
        nonlocal channel, process, process_fd
        channel, child = socket.socketpair()
        try:
            process = subprocess.Popen(
                ["bash", "-c", BODY, "padm-hopping-owner", entrypoint, root,
                 str(child.fileno()), *values, *(["--restart"] if restart else [])],
                pass_fds=(child.fileno(),), stdin=subprocess.DEVNULL, stdout=log, stderr=log)
        finally:
            child.close()
        owner["bash"] = identity(process.pid)
        process_fd = pin(owner["bash"])
        directory.write_owner(owner)

    try:
        if os.geteuid() != 0 or len(values) != 5:
            raise Failure("监督服务仅支持 root 和五参数")
        peer_pid(initial)
        own = identity(os.getpid())
        if own["session_id"] != own["pid"]:
            raise Failure("监督服务必须属于独立会话")
        # 先完成挑战；等待普通部署锁不消耗 hello 帧预算，commit 前不创建会话。
        directory = Directory(root)
        directory.close()
        directory = None
        proof = challenge(initial, "start")
        reservation = subprocess.run(
            ["bash", "-Eeuo", "pipefail", "-c", RESERVE_BODY, "padm-hopping-reservation",
             entrypoint, root, sys.executable, str(Path(__file__).resolve())],
            capture_output=True)
        if reservation.returncode:
            raise Failure("监督会话预约失败: " + reservation.stderr.decode("utf-8", errors="replace"))
        reserved = shape(json.loads(reservation.stdout.decode("ascii"), object_pairs_hook=unique),
                         ("directory", "session"))
        directory = Directory(root)
        directory.session()
        # 原锁只用于预约，不转交给监督 Bash；替换预约路径后保留证据并拒绝启动。
        if canonical(reserved) != canonical({
                "directory": directory.projection, "session": directory.original}):
            raise Failure("监督会话预约目录身份变化")
        directory.check()
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        listener.bind(f"/proc/self/fd/{directory.fd}/control.sock")
        os.chmod(directory.path + "/control.sock", 0o600)
        listener.listen(4)
        socket_id = path_identity(os.stat("control.sock", dir_fd=directory.fd, follow_symlinks=False))
        log = os.open("service.log", os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                      0o600, dir_fd=directory.fd)
        log_id = path_identity(os.fstat(log))
        owner = {"v": 1, "token": os.urandom(32).hex(), "root": root, "manager": own,
                 "bash": None, "stage": None, "stage_sha256": None, "state": "starting"}
        directory.write_owner(owner)
        # 独立 Bash 自取锁并 freshly bound；环境变量只提供安装路径，不提供授权。
        launch()
        last_gate = None
        pending_signal = [False]
        signal.signal(signal.SIGTERM, lambda *_: pending_signal.__setitem__(0, True))
        signal.signal(signal.SIGINT, lambda *_: pending_signal.__setitem__(0, True))
        signal.signal(signal.SIGHUP, signal.SIG_IGN)
        while True:
            if pending_signal[0] and not stopping:
                signal.pidfd_send_signal(process_fd, signal.SIGTERM)
                stopping = True
            watched = [listener, process_fd] + ([channel] if finished is None else [])
            readable = select.select(watched, [], [], 0.2)[0]
            if channel in readable:
                event = shape(receive(channel), ("v", "phase", "nonce", "payload"))
                if not nonce(event["nonce"]) or event["nonce"] == last_gate:
                    raise Failure("监督门 nonce 重复")
                last_gate = event["nonce"]
                phase, value = event["phase"], event["payload"]
                if stopping and phase in {"restart", "ready", "started", "running"}:
                    send(channel, {"v": 1, "phase": "stop", "nonce": event["nonce"]})
                elif (phase == "restart" and restart_receipt is not None and
                      not restart_gate and ready is None and latest is None and not stopping):
                    shape(value, ("bash_pid", "lock"))
                    if type(value["bash_pid"]) is not int or value["bash_pid"] != process.pid:
                        raise Failure("监督重启写门 Bash 不匹配")
                    result = subprocess.run(
                        ["bash", "-Eeuo", "pipefail", "-c", LOCK_BODY, "padm-hopping-restart-check",
                         entrypoint, root, str(process.pid)], capture_output=True)
                    if (result.returncode or
                            json.loads(result.stdout, object_pairs_hook=unique) != value["lock"] or
                            directory.read_owner() != owner or
                            select.select([process_fd], [], [], 0)[0]):
                        raise Failure("监督重启写门原锁或 owner 不匹配")
                    restart_gate = True
                    send(channel, {"v": 1, "phase": "commit", "nonce": event["nonce"]})
                elif phase == "ready" and ready is None and latest is None and not stopping:
                    if restart_receipt is not None and not restart_gate:
                        raise Failure("监督重启未经过新写门")
                    ready = payload_check(value)
                    if restart_receipt is not None:
                        restarted_target(ready, restart_receipt["cleaned"])
                    if (PurePosixPath(ready["stage"]).parent != PurePosixPath(root) or
                            not PurePosixPath(ready["stage"]).name.startswith(".hopping-guarded.")):
                        raise Failure("监督 stage 超出受管根")
                    owner.update(stage=ready["stage"], stage_sha256=digest({
                        key: ready[key] for key in ("target", "child", "directory", "stage")}))
                    directory.write_owner(owner)
                    send(channel, {"v": 1, "phase": "commit", "nonce": event["nonce"]})
                elif phase == "started" and latest is None and value == ready and not stopping:
                    latest = ready
                    owner["state"] = "active"
                    directory.write_owner(owner)
                    send(channel, {"v": 1, "phase": "continue", "nonce": event["nonce"]})
                    try:
                        if restart_receipt is None:
                            send(initial, ack("started", proof, owner, payload=latest))
                        else:
                            send(stop_peer, ack("restarted", proof, owner,
                                                payload=latest, **restart_receipt))
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
                elif phase == "running" and latest is not None and not stopping:
                    latest = payload_check(value, latest, latest["running"]["seq"] + 1)
                    directory.check()
                    if directory.read_owner() != owner:
                        raise Failure("监督 owner 在运行中变化")
                    send(channel, {"v": 1, "phase": "continue", "nonce": event["nonce"]})
                elif phase == "cleaned" and stopping and cleaned is None and latest is not None:
                    shape(value, ("target", "child_id", "stage"))
                    if value != {"target": latest["target"], "child_id": latest["child"]["Id"],
                                 "stage": latest["stage"]}:
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
                    hello = shape(receive(peer, timeout=2), ("v", "phase", "action", "client_nonce"))
                    if hello["action"] not in {"status", "stop", "restart"}:
                        raise Failure("监督控制动作无效")
                    # 仅把已读取的 hello 交给同一挑战函数，连接没有重复读取。
                    action = hello["action"]
                    control_proof = challenge_from_hello(peer, action, owner, hello)
                    directory.check()
                    if directory.read_owner() != owner or select.select([process_fd], [], [], 0)[0]:
                        raise Failure("监督控制提交后原 owner 或 Bash 已变化")
                    if action == "status":
                        send(peer, ack("status", control_proof, owner, payload=latest))
                    else:
                        signal.pidfd_send_signal(process_fd, signal.SIGTERM)
                        stopping, stop_peer, proof = True, peer, control_proof
                        restarting = action == "restart"
                        peer = None
                except (Failure, OSError, ValueError) as error:
                    os.write(log, (str(error) + "\n").encode("utf-8"))
                finally:
                    if peer is not None:
                        peer.close()
            if process_fd in readable:
                # Bash 退出后先消费已排队的 notify；不能把 pidfd 终止当作净撤销。
                while finished is None and select.select([channel], [], [], 0)[0]:
                    event = shape(receive(channel), ("v", "phase", "nonce", "payload"))
                    if not nonce(event["nonce"]) or event["nonce"] == last_gate:
                        raise Failure("监督退出通知 nonce 重复")
                    last_gate = event["nonce"]
                    if event["phase"] == "finished":
                        finished = shape(event["payload"], ("status", "lock_released"))
                        if (type(finished["status"]) is not int or
                                type(finished["lock_released"]) is not bool):
                            raise Failure("监督退出回执类型无效")
                    elif event["phase"] == "cleaned" and cleaned is None and stopping and latest is not None:
                        cleaned = shape(event["payload"], ("target", "child_id", "stage"))
                        if cleaned != {"target": latest["target"], "child_id": latest["child"]["Id"],
                                       "stage": latest["stage"]}:
                            raise Failure("监督净清理回执投影不匹配")
                    else:
                        raise Failure("监督退出后出现未知通知")
                status = process.wait(timeout=2)
                if (stopping and latest is not None and cleaned == {
                        "target": latest["target"], "child_id": latest["child"]["Id"],
                        "stage": latest["stage"]} and finished == {
                        "status": 143, "lock_released": True} and status == 143):
                    if restarting and not pending_signal[0]:
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
                        ready, latest, cleaned, finished, last_gate = None, None, None, None, None
                        launch(restart=True)
                        continue
                    directory.cleanup(owner, socket_id, log_id)
                    if stop_peer:
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
        if process_fd is not None:
            if process is not None and process.poll() is None:
                try:
                    signal.pidfd_send_signal(process_fd, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=90)
                except subprocess.TimeoutExpired:
                    pass
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
    if shape(receive(peer, timeout=2), expected) != expected:
        raise Failure("监督 commit 身份或挑战不匹配")
    return proof


def client(peer, action, owner=None, token=None):
    hello = {"v": 1, "phase": "hello", "action": action, "client_nonce": os.urandom(32).hex()}
    send(peer, hello)
    proof = shape(receive(peer), ("v", "phase", "nonce", "client_nonce", "owner_sha256"))
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
    send(peer, request)
    result = receive(peer, timeout=150)
    keys = ("v", "phase", "nonce", "client_nonce", "owner", "owner_sha256")
    shape(result, (*keys, "cleaned", "finished") if action == "stop" else
          (*keys, "payload", "previous_owner", "cleaned", "finished") if action == "restart" else
          (*keys, "payload"))
    expected_phase = {"start": "started", "stop": "stopped", "restart": "restarted",
                      "status": "status"}[action]
    if (result["phase"] != expected_phase or result["nonce"] != proof["nonce"] or
            result["client_nonce"] != proof["client_nonce"] or
            result["owner_sha256"] != digest(result["owner"]) or
            owner is not None and action != "restart" and result["owner"] != owner):
        raise Failure("监督 ACK 不匹配")
    active_owner = owner_check(result["owner"])
    if action in {"stop", "restart"}:
        finished = shape(result["finished"], ("status", "lock_released"))
        cleaned = shape(result["cleaned"], ("target", "child_id", "stage"))
        if (type(finished["status"]) is not int or finished["status"] != 143 or
                type(finished["lock_released"]) is not bool or not finished["lock_released"] or
                cleaned["stage"] != (owner if action == "restart" else active_owner)["stage"] or
                not nonce(cleaned["child_id"]) or
                not isinstance(cleaned["target"], dict)):
            raise Failure("监督停止 ACK 未证明净撤销")
    if action != "stop":
        value = payload_check(result["payload"], seq=result["payload"]["running"]["seq"])
        if (value["running"]["seq"] < 2 or value["stage"] != active_owner["stage"] or
                digest({key: value[key] for key in (
                    "target", "child", "directory", "stage")}) != active_owner["stage_sha256"]):
            raise Failure("监督 ACK 原 stage 投影不匹配")
        if action == "restart":
            if (result["previous_owner"] != owner or
                    any(active_owner[key] != owner[key] for key in ("root", "manager")) or
                    any(active_owner[key] == owner[key] for key in ("token", "bash", "stage")) or
                    active_owner["bash"]["starttime_ticks"] <= owner["bash"]["starttime_ticks"]):
                raise Failure("监督重启 ACK 未证明新代次与原目标")
            restarted_target(value, cleaned)
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


def control(action, root, token=None):
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
        result = client(peer, action, owner, token)
        if action in {"status", "restart"}:
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


def helper(command, phase, raw):
    peer = socket.socket(fileno=os.dup(0))
    try:
        peer_pid(peer)
        value = json.loads(raw, object_pairs_hook=unique)
        proof = {"v": 1, "phase": phase, "nonce": os.urandom(32).hex(), "payload": value}
        send(peer, proof)
        if command == "gate":
            if phase not in {"restart", "ready", "started", "running"}:
                raise Failure("监督 gate 阶段无效")
            response = shape(receive(peer), ("v", "phase", "nonce"))
            if response != {"v": 1, "phase": "commit" if phase in {"ready", "restart"} else "continue",
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
    if operation == "_service" and len(args) == 8:
        service(int(args[0]), args[1], args[2], args[3:])
        return
    if operation == "_reserve" and len(args) == 3:
        result = reserve(*args)
    elif operation == "start" and len(args) == 7:
        result = start(args[0], args[1], args[2:])
    elif operation == "status" and len(args) == 1:
        result = control("status", args[0])
    elif operation in {"stop", "restart"} and len(args) in {1, 2}:
        result = control(operation, args[0], args[1] if len(args) == 2 else None)
    else:
        raise Failure("监督入口参数无效")
    print(canonical(result).decode("ascii"))


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (Failure, ValueError, KeyError, TypeError, UnicodeError, OSError) as error:
        print("跳跃独立监督拒绝: " + str(error), file=sys.stderr)
        raise SystemExit(1)
