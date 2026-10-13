#!/usr/bin/env python3
import datetime
import json
import os
from pathlib import PurePosixPath
import re
import select
import stat
import sys
import time


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("重复 JSON 键")
        result[key] = value
    return result


def text(value, pattern):
    return isinstance(value, str) and re.fullmatch(pattern, value) is not None


def timestamp(value):
    if not text(value, r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z"):
        raise ValueError("容器启动时间格式无效")
    datetime.datetime.strptime(value[:19], "%Y-%m-%dT%H:%M:%S")


def frame(phase, *expected, mode="probe"):
    deadline = time.monotonic() + 20
    data = b""

    def byte():
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([0], [], [], remaining)[0]:
            raise ValueError("跳跃握手超时")
        return os.read(0, 1)

    # 逐字节保留下一帧；不能吞掉同批到达的额外输出。
    while not data.endswith(b"\n"):
        current = byte()
        if not current:
            raise ValueError("跳跃握手缺少完整帧")
        data += current
        if len(data) > 4096:
            raise ValueError("跳跃握手帧过长")
    if b"\0" in data or b"\r" in data:
        raise ValueError("跳跃握手帧含非法字节")
    value = json.loads(data[:-1].decode("ascii"), object_pairs_hook=unique)
    keys = {"v", "phase", "nonce", "host"} if phase == "challenge" else {
        "v", "phase", "nonce", "child_id", "request_sha256"}
    if mode == "supervised" and phase == "running":
        keys.add("seq")
    if (not isinstance(value, dict) or set(value) != keys or
            type(value["v"]) is not int or value["v"] != 1 or value["phase"] != phase or
            not text(value["nonce"], r"[a-f0-9]{64}")):
        raise ValueError("跳跃握手帧身份无效")
    if mode == "supervised":
        if (phase != "running" or len(expected) != 4 or
                any(not text(item, r"[a-f0-9]{64}") for item in expected[:3]) or
                not text(expected[3], r"[1-9][0-9]*") or
                value["child_id"] != expected[0] or value["request_sha256"] != expected[1] or
                value["nonce"] == expected[2] or type(value["seq"]) is not int or
                value["seq"] != int(expected[3])):
            raise ValueError("跳跃续期帧序号、nonce 或绑定无效")
    elif mode == "guarded":
        counts = {"ready": 3, "written": 4, "active": 5, "closed": 3}
        if (phase not in counts or len(expected) != counts[phase] or
                any(not text(item, r"[a-f0-9]{64}") for item in expected) or
                value["child_id"] != expected[0] or value["request_sha256"] != expected[1]):
            raise ValueError("跳跃写门帧阶段或绑定无效")
        seen = expected[2:]
        if (len(set(seen)) != len(seen) or
                (phase == "closed" and (value["nonce"] != seen[0] or byte() != b"")) or
                (phase != "closed" and value["nonce"] in seen)):
            raise ValueError("跳跃写门 nonce 重用、关闭帧不匹配或含额外输出")
    elif phase == "challenge":
        if expected or not text(value["host"], r"[a-f0-9]{12}"):
            raise ValueError("跳跃挑战主机名无效")
    elif phase == "ack":
        if (len(expected) != 3 or
                [value["nonce"], value["child_id"], value["request_sha256"]] != list(expected) or
                byte() != b""):
            raise ValueError("跳跃 ACK 不匹配或含额外输出")
    else:
        raise ValueError("跳跃握手阶段无效")
    return value


def directory(root):
    path = PurePosixPath(root)
    if str(path) != root or path.anchor != "/" or root == "/" or ".." in path.parts:
        raise ValueError("跳跃目录路径不规范")
    held, rows = [], []
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    try:
        descriptor = os.open("/", flags)
        held.append(descriptor)
        current = ""
        for part in ["", *path.parts[1:], "data", "net"]:
            if part:
                descriptor = os.open(part, flags, dir_fd=descriptor)
                held.append(descriptor)
                current += "/" + part
            metadata = os.fstat(descriptor)
            if current in {root, root + "/data", root + "/data/net"} and (
                    metadata.st_uid != 0 or stat.S_IMODE(metadata.st_mode) & 0o022):
                raise ValueError("跳跃受管目录身份或权限无效")
            rows.append([current or "/", metadata.st_dev, metadata.st_ino,
                         metadata.st_mode, metadata.st_uid, metadata.st_gid])
        return rows
    finally:
        for descriptor in reversed(held):
            os.close(descriptor)


def container(root, cid, image, label, start, end, target, ipv4, ipv6, host, mode,
              operation="probe"):
    items = json.load(sys.stdin, object_pairs_hook=unique)
    if (not isinstance(items, list) or len(items) != 1 or
            not text(cid, r"[a-f0-9]{64}") or not text(image, r"sha256:[a-f0-9]{64}")):
        raise ValueError("跳跃子容器身份无效")
    value = items[0]
    config, runtime, state = value["Config"], value["HostConfig"], value["State"]
    hostname = host
    command = "port-hopping-" + operation
    label_key = "io.padm.hopping-" + operation
    tmpfs = {"/tmp": "rw,nosuid,nodev,size=16m,mode=1777",
             "/run": "rw,nosuid,nodev,size=16m,mode=0755"}
    mounts = value["Mounts"]
    if (value["Id"] != cid or value["Image"] != image or
            config["Entrypoint"] != ["/usr/local/bin/padm-entrypoint"] or
            config["Cmd"] != [command, start, end, target, ipv4, ipv6] or
            not text(hostname, r"[a-f0-9]{12}") or config["Hostname"] != hostname or
            config["User"] != "0:0" or config["Healthcheck"]["Test"] != ["NONE"] or
            config["Labels"].get(label_key) != label or
            config["Tty"] is not False or config["OpenStdin"] is not True or
            runtime["NetworkMode"] != "host" or runtime["ReadonlyRootfs"] is not True or
            runtime["Privileged"] is not False or runtime["CapAdd"] != ["CAP_NET_ADMIN"] or
            runtime["CapDrop"] != ["ALL"] or runtime["SecurityOpt"] != ["no-new-privileges"] or
            runtime["PidMode"] != "" or runtime.get("UsernsMode", "") != "" or
            runtime.get("IpcMode") not in {"private", ""} or
            runtime.get("Devices") or runtime.get("DeviceRequests") or
            runtime.get("GroupAdd") or runtime.get("Links") or
            runtime["RestartPolicy"] != {"Name": "no", "MaximumRetryCount": 0} or
            runtime["Tmpfs"] != tmpfs or runtime.get("Binds") or
            runtime.get("VolumesFrom") or runtime.get("PortBindings") or
            runtime.get("Sysctls") or config.get("Volumes") or
            runtime["Mounts"] != [{"Type": "bind", "Source": root + "/data/net",
                                   "Target": "/var/lib/padm/net"}] or
            len(mounts) != 1 or mounts[0]["Type"] != "bind" or
            mounts[0]["Source"] != root + "/data/net" or
            mounts[0]["Destination"] != "/var/lib/padm/net" or
            mounts[0]["RW"] is not True or mounts[0]["Propagation"] != "rprivate" or
            type(value["RestartCount"]) is not int or value["RestartCount"] != 0 or
            state["Restarting"] is not False or
            state["Paused"] is not False or state["Dead"] is not False or
            mode not in {"live", "any"}):
        raise ValueError("跳跃子容器配置不匹配")
    timestamp(value["Created"])
    timestamp(state["StartedAt"])
    if mode == "live" and (state["Status"] != "running" or state["Running"] is not True):
        raise ValueError("跳跃子容器未运行")
    return {key: value[key] for key in ("Id", "Image", "Created", "Config", "HostConfig", "Mounts")} | {
        "StartedAt": state["StartedAt"]}


try:
    operation, *arguments = sys.argv[1:]
    if operation == "frame":
        result = frame(*arguments)
    elif operation == "guarded-frame":
        result = frame(*arguments, mode="guarded")
    elif operation == "supervised-frame":
        result = frame(*arguments, mode="supervised")
    elif operation == "directory" and len(arguments) == 1:
        result = directory(*arguments)
    elif operation == "container" and len(arguments) == 11:
        result = container(*arguments)
    elif operation == "guarded-container" and len(arguments) == 11:
        result = container(*arguments, operation="guarded")
    elif operation == "supervised-container" and len(arguments) == 11:
        result = container(*arguments, operation="supervised")
    else:
        raise ValueError("跳跃诊断参数无效")
    print(json.dumps(result, separators=(",", ":"), sort_keys=True))
except (ValueError, KeyError, TypeError, UnicodeError, OSError) as error:
    print("跳跃诊断拒绝: " + str(error), file=sys.stderr)
    sys.exit(1)
