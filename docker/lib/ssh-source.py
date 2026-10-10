#!/usr/bin/env python3
"""只读核验一次宿主 SSH 新连接的日志来源与实时端点。"""

import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import stat
import subprocess
import sys
import time


MASTER_EXES = ("/usr/sbin/sshd",)
EMITTER_EXES = MASTER_EXES + (
    "/usr/lib/openssh/sshd-session",
    "/usr/libexec/openssh/sshd-session",
    "/usr/lib/ssh/sshd-session",
)
TIMEOUT = 30
MAX_OUTPUT = 1024 * 1024


class Failure(Exception):
    def __init__(self, message, code=15):
        super().__init__(message)
        self.code = code


def parse_address(value):
    if not isinstance(value, str) or any(c in value for c in "%/[]"):
        raise Failure("SSH 来源核验只接受无作用域的 IP 字面地址", 2)
    try:
        address = ipaddress.ip_address(value)
    except ValueError:
        raise Failure("SSH 来源核验的 IP 地址无效", 2) from None
    if (address.is_unspecified or address.is_loopback or address.is_multicast
            or address.is_link_local or getattr(address, "ipv4_mapped", None)
            or (address.version == 4 and (int(address) >> 24 == 0 or int(address) >> 24 >= 224))):
        raise Failure("SSH 来源核验拒绝本地、链路或映射地址", 2)
    return address


def parse_args(args):
    if len(args) != 4:
        raise Failure("SSH 来源核验需要本机地址、端口、外部来源和挑战码", 2)
    local, port, source, nonce = args
    local, source = parse_address(local), parse_address(source)
    if (local.version != source.version or local == source
            or not re.fullmatch(r"[1-9][0-9]{0,4}", port)
            or not 1 <= int(port) <= 65535
            or not re.fullmatch(r"[0-9a-f]{48}", nonce)):
        raise Failure("SSH 来源核验的地址族、端口或挑战码无效", 2)
    return local, int(port), source, nonce


def run_command(args, deadline=None, limit=MAX_OUTPUT):
    end = min(time.monotonic() + 3, deadline or float("inf"))
    if end <= time.monotonic():
        raise Failure("SSH 来源核验已超时")
    process = None
    try:
        process = subprocess.Popen(
            args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            env={**os.environ, "LC_ALL": "C", "LANG": "C", "SYSTEMD_COLORS": "0"},
        )
        result = bytearray()
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while selector.get_map():
                remaining = end - time.monotonic()
                if remaining <= 0:
                    raise Failure("SSH 来源核验的只读命令超时")
                for key, _ in selector.select(remaining):
                    chunk = os.read(key.fileobj.fileno(), min(65536, limit + 1))
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    result.extend(chunk)
                    if len(result) > limit:
                        raise Failure("SSH 来源核验的只读结果超出上限")
        if process.wait(timeout=max(0.001, end - time.monotonic())) != 0:
            raise Failure("SSH 来源核验的只读命令失败")
        return result.decode("utf-8")
    except (OSError, UnicodeError, subprocess.TimeoutExpired):
        raise Failure("SSH 来源核验无法读取宿主证据") from None
    finally:
        if process is not None:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()


def parse_json_lines(text):
    def unique(pairs):
        row = {}
        for key, value in pairs:
            if key in row:
                raise ValueError("duplicate")
            row[key] = value
        return row

    def reject_constant(_value):
        raise ValueError("non-finite")

    try:
        rows = [json.loads(line, object_pairs_hook=unique, parse_constant=reject_constant)
                for line in text.splitlines() if line.strip()]
    except (ValueError, TypeError):
        raise Failure("SSH 来源核验的结构化证据无效") from None
    if any(not isinstance(row, dict) for row in rows):
        raise Failure("SSH 来源核验的结构化证据不是单条对象")
    return rows


def parse_ss(text, family):
    def endpoint(value):
        host, port = value.rsplit(":", 1)
        host = host.strip("[]")
        if host == "*":
            host = "0.0.0.0" if family == 4 else "::"
        address = ipaddress.ip_address(host)
        if address.version != family:
            raise ValueError("family")
        number = None if port == "*" else int(port)
        if number is not None and not 0 <= number <= 65535:
            raise ValueError("port")
        return str(address), number

    rows = []
    try:
        for line in text.splitlines():
            if not line.strip():
                continue
            columns = line.split()
            if columns[0] not in ("LISTEN", "ESTAB"):
                continue
            if len(columns) < 6 or not all(c.isdigit() for c in columns[1:3]):
                raise ValueError("columns")
            inodes = re.findall(r"\bino:([1-9][0-9]*)\b", line)
            if len(inodes) != 1:
                raise ValueError("inode")
            owner_blocks = re.findall(r'users:\(\((.*?)\)\)', line)
            owners = ()
            if owner_blocks:
                if len(owner_blocks) != 1 or not re.fullmatch(
                        r'"[^"]+",pid=[1-9][0-9]*,fd=[0-9]+'
                        r'(?:\),\("[^"]+",pid=[1-9][0-9]*,fd=[0-9]+)*',
                        owner_blocks[0]):
                    raise ValueError("owners")
                owners = tuple((int(pid), int(fd)) for pid, fd in re.findall(
                    r'pid=([1-9][0-9]*),fd=([0-9]+)', owner_blocks[0]))
            rows.append({
                "state": columns[0], "local": endpoint(columns[3]),
                "remote": endpoint(columns[4]), "owners": owners,
                "inode": int(inodes[0]),
            })
    except (ValueError, IndexError):
        raise Failure("SSH 来源核验无法解析实时 TCP 端点") from None
    return rows


def boot_id():
    value = Path("/proc/sys/kernel/random/boot_id").read_text().strip().replace("-", "")
    if not re.fullmatch(r"[0-9a-f]{32}", value):
        raise Failure("SSH 来源核验无法确认当前启动代次")
    return value


def safe_executable(path):
    path = Path(path)
    canonical = path.resolve(strict=True)
    for directory in set(path.parents) | set(canonical.parents):
        metadata = directory.stat()
        if (not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != 0
                or metadata.st_mode & 0o022):
            raise Failure("SSH 可执行文件的父目录不安全")
    with canonical.open("rb") as handle:
        before = os.fstat(handle.fileno())
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != 0
                or before.st_mode & 0o022 or not before.st_mode & 0o111):
            raise Failure("SSH 可执行文件的权限不安全")
        digest = hashlib.sha256()
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
        after = os.fstat(handle.fileno())
    identity = lambda item: (
        item.st_dev, item.st_ino, item.st_size, item.st_mtime_ns, item.st_ctime_ns,
    )
    if identity(before) != identity(after) or identity(after) != identity(canonical.stat()):
        raise Failure("SSH 可执行文件在核验期间发生变化")
    return str(canonical), *identity(after), digest.hexdigest()


def read_process(pid, allowed_exes):
    root = Path("/proc") / str(pid)
    before = (root / "stat").read_text()
    fields = before[before.rindex(")") + 2:].split()
    uid = re.search(r"^Uid:\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)$",
                    (root / "status").read_text(), re.MULTILINE)
    exe = os.readlink(root / "exe")
    allowed = {str(Path(value).resolve()) for value in allowed_exes}
    if (not uid or any(int(value) != 0 for value in uid.groups())
            or exe not in allowed or len(fields) < 47):
        raise Failure("SSH 进程身份或权限不可核验")
    executable = safe_executable(exe)
    actual = (root / "exe").stat()
    if (actual.st_dev, actual.st_ino) != executable[1:3]:
        raise Failure("SSH 进程未使用已核验的宿主可执行文件")
    netns = os.readlink(root / "ns/net")
    if netns != os.readlink("/proc/self/ns/net"):
        raise Failure("SSH 进程不在当前宿主网络命名空间")
    # exec 会改变映射地址；PID 和 starttime 单独不足以识别重新执行。
    generation = tuple(int(fields[index]) for index in (23, 24, 25, 45, 46))
    output = {
        "pid": pid, "ppid": int(fields[1]), "starttime": int(fields[19]),
        "uid": (0, 0, 0, 0), "exe": exe, "exe_identity": executable,
        "exec_generation": generation, "netns": netns, "boot_id": boot_id(),
    }
    final = (root / "stat").read_text()
    final_fields = final[final.rindex(")") + 2:].split()
    final_uid = re.search(
        r"^Uid:\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)$",
        (root / "status").read_text(), re.MULTILINE,
    )
    if (int(final_fields[19]) != output["starttime"]
            or int(final_fields[1]) != output["ppid"]
            or tuple(int(final_fields[i]) for i in (23, 24, 25, 45, 46)) != generation
            or os.readlink(root / "exe") != exe
            or os.readlink(root / "ns/net") != netns
            or not final_uid or any(int(value) != 0 for value in final_uid.groups())):
        raise Failure("SSH 进程在核验期间发生变化")
    return output


def socket_fd(pid, fd, inode):
    if os.readlink(f"/proc/{pid}/fd/{fd}") != f"socket:[{inode}]":
        raise Failure("SSH 进程不再持有核验的 TCP 套接字")


def get_listener(local, port, deadline=None):
    family = local.version
    rows = parse_ss(run_command(["ss", "-H", "-ltnpe", f"-{family}"], deadline), family)
    wildcard = "0.0.0.0" if family == 4 else "::"
    matching = [row for row in rows if row["state"] == "LISTEN"
                and row["local"][1] == port and row["local"][0] in (str(local), wildcard)]
    if len(matching) != 1 or len(matching[0]["owners"]) != 1:
        raise Failure("SSH 目标监听或进程所有者不唯一")
    listener = matching[0]
    pid, fd = listener["owners"][0]
    master = read_process(pid, MASTER_EXES)
    socket_fd(pid, fd, listener["inode"])
    return {"socket": listener, "process": master}


def get_accepted(local, port, source, sport, deadline=None):
    family = local.version
    rows = parse_ss(run_command(["ss", "-H", "-tnpe", f"-{family}"], deadline), family)
    matching = [row for row in rows if row["state"] == "ESTAB"
                and row["local"] == (str(local), port)
                and row["remote"] == (str(source), sport)]
    if len(matching) != 1 or len(matching[0]["owners"]) != 1:
        raise Failure("SSH 新连接的实时端点或所有者不唯一")
    return matching[0]


def verify_addresses(local, source, deadline=None):
    try:
        devices = json.loads(run_command(["ip", "-j", "address"], deadline))
        if not isinstance(devices, list):
            raise ValueError("devices")
        addresses = {ipaddress.ip_address(item["local"])
                     for device in devices for item in device["addr_info"]}
        if local not in addresses or source in addresses:
            raise Failure("SSH 来源必须来自宿主之外，目标必须是明确本机地址", 2)
        ids = run_command(["docker", "network", "ls", "--quiet", "--no-trunc"], deadline).split()
        if (len(ids) > 128 or len(set(ids)) != len(ids)
                or any(not re.fullmatch(r"[0-9a-f]{64}", value) for value in ids)):
            raise ValueError("ids")
        networks = []
        for offset in range(0, len(ids), 32):
            batch = json.loads(run_command(["docker", "network", "inspect",
                                           *ids[offset:offset + 32]], deadline))
            if not isinstance(batch, list) or len(batch) != len(ids[offset:offset + 32]):
                raise ValueError("networks")
            networks.extend(batch)
        for network in networks:
            for container in network["Containers"].values():
                for key in ("IPv4Address", "IPv6Address"):
                    value = container.get(key, "")
                    if value and source == ipaddress.ip_interface(value).ip:
                        raise Failure("SSH 来源不能是 Docker 容器地址", 2)
            if network["Driver"] != "bridge":
                continue
            for config in network["IPAM"]["Config"]:
                subnet = config.get("Subnet")
                gateway = config.get("Gateway")
                if ((subnet and source in ipaddress.ip_network(subnet, strict=False))
                        or (gateway and source == ipaddress.ip_address(gateway))):
                    raise Failure("SSH 来源不能位于 Docker 桥接网络", 2)
    except (ValueError, TypeError, KeyError, AttributeError):
        raise Failure("SSH 来源核验无法读取本机及 Docker 地址", 10) from None


def checkpoint(boot, deadline=None):
    rows = parse_json_lines(run_command([
        "journalctl", "--quiet", "--no-pager", f"--boot={boot}",
        "--output=json", "--lines=1",
    ], deadline))
    if (len(rows) != 1 or rows[0].get("_BOOT_ID") != boot
            or not isinstance(rows[0].get("__CURSOR"), str)
            or not isinstance(rows[0].get("__MONOTONIC_TIMESTAMP"), str)
            or not re.fullmatch(r"[0-9]+", rows[0]["__MONOTONIC_TIMESTAMP"])):
        raise Failure("SSH 来源核验无法建立当前 journal 游标", 10)
    cursor = rows[0]["__CURSOR"]
    if not cursor or len(cursor) > 1024 or any(c.isspace() for c in cursor):
        raise Failure("SSH 来源核验的 journal 游标无效", 10)
    return cursor, int(rows[0]["__MONOTONIC_TIMESTAMP"])


def journal_records(boot, cursor, deadline):
    common = ["journalctl", "--quiet", "--no-pager", f"--boot={boot}", "--output=json"]
    current = parse_json_lines(run_command(
        [*common, f"--cursor={cursor}", "--lines=1"], deadline))
    if (len(current) != 1 or current[0].get("__CURSOR") != cursor
            or current[0].get("_BOOT_ID") != boot):
        raise Failure("SSH 来源核验的 journal 游标已失效")
    rows = parse_json_lines(run_command(
        [*common, f"--after-cursor={cursor}", "--lines=257"], deadline))
    if len(rows) >= 257:
        raise Failure("SSH 来源核验的新 journal 记录超出上限")
    return rows


def event_source(record, username, source, boot, fresh_us):
    message = record.get("MESSAGE")
    if not isinstance(message, str):
        return None
    match = re.fullmatch(
        rf"Invalid user {re.escape(username)} from ([^ ]+) port ([1-9][0-9]{{0,4}})",
        message,
    )
    if not match:
        return None
    try:
        if ipaddress.ip_address(match[1]) != source:
            raise ValueError("source")
        sport = int(match[2])
        if sport > 65535:
            raise ValueError("sport")
        if (record.get("_TRANSPORT") != "syslog" or record.get("_UID") != "0"
                or record.get("_BOOT_ID") != boot
                or not isinstance(record.get("_EXE"), str)
                or record["_EXE"] not in EMITTER_EXES
                or not isinstance(record.get("_PID"), str)
                or not re.fullmatch(r"[1-9][0-9]*", record["_PID"])
                or not isinstance(record.get("__MONOTONIC_TIMESTAMP"), str)
                or not re.fullmatch(r"[0-9]+", record["__MONOTONIC_TIMESTAMP"])
                or int(record["__MONOTONIC_TIMESTAMP"]) <= fresh_us):
            raise ValueError("metadata")
        return {
            "pid": int(record["_PID"]), "sport": sport,
            "timestamp": int(record["__MONOTONIC_TIMESTAMP"]), "exe": record["_EXE"],
        }
    except ValueError:
        raise Failure("SSH 挑战记录缺少可信来源或新鲜证据") from None


def verify_event(event, master, local, port, source, deadline):
    emitter = read_process(event["pid"], EMITTER_EXES)
    parent = master["process"]
    ticks = os.sysconf("SC_CLK_TCK")
    if (emitter["exe"] != event["exe"] or emitter["ppid"] != parent["pid"]
            or emitter["boot_id"] != parent["boot_id"]
            or emitter["netns"] != parent["netns"]
            or emitter["starttime"] * 1000000 > event["timestamp"] * ticks):
        raise Failure("SSH 日志进程与目标监听进程不属于同一次连接")
    accepted = get_accepted(local, port, source, event["sport"], deadline)
    owner = accepted["owners"][0]
    if owner[0] != emitter["pid"]:
        raise Failure("SSH 日志进程没有持有挑战连接")
    socket_fd(*owner, accepted["inode"])
    if (get_listener(local, port, deadline) != master
            or read_process(event["pid"], EMITTER_EXES) != emitter
            or get_accepted(local, port, source, event["sport"], deadline) != accepted):
        raise Failure("SSH 监听、日志进程或挑战连接在核验期间变化")
    socket_fd(*owner, accepted["inode"])
    if time.monotonic() >= deadline:
        raise Failure("SSH 来源核验已超时")
    return emitter, accepted


def witness(local, port, source, nonce):
    try:
        verify_addresses(local, source)
        master = get_listener(local, port)
        boot = master["process"]["boot_id"]
        cursor, fresh_us = checkpoint(boot)
    except Failure as error:
        if error.code != 2:
            error.code = 10
        raise
    except (OSError, ValueError, KeyError, IndexError, TypeError):
        raise Failure("SSH 来源核验无法建立宿主证据起点", 10) from None
    username = "padm-source-" + nonce
    deadline = time.monotonic() + TIMEOUT
    print("source-challenge=" + json.dumps({
        "username": username, "target": str(local), "port": port, "source": str(source),
        "timeout_seconds": TIMEOUT,
    }, separators=(",", ":")), flush=True)
    print(
        f"请从指定外部来源运行：python3 -B docker/lib/ssh-source-client.py "
        f"{local} {port} {username} /client/known_hosts\n"
        "客户端需已有 Paramiko，known_hosts 须已可信登记；失败认证连接保持 25 秒。",
        file=sys.stderr, flush=True,
    )
    while time.monotonic() < deadline:
        rows = journal_records(boot, cursor, deadline)
        for row in rows:
            event = event_source(row, username, source, boot, fresh_us)
            if event is None:
                continue
            first_evidence = verify_event(event, master, local, port, source, deadline)
            verify_addresses(local, source, deadline)
            second_evidence = verify_event(event, master, local, port, source, deadline)
            if second_evidence != first_evidence:
                raise Failure("SSH 监听、日志进程或挑战连接代次发生变化")
            return {
                "scope": "ssh-source-only", "source_verified": True,
                "runtime_configuration_verified": False, "jail_ready": False,
                "target": str(local), "port": port, "source": str(source),
            }
        if rows:
            last = rows[-1]
            if (last.get("_BOOT_ID") != boot or not isinstance(last.get("__CURSOR"), str)
                    or not isinstance(last.get("__MONOTONIC_TIMESTAMP"), str)
                    or not re.fullmatch(r"[0-9]+", last["__MONOTONIC_TIMESTAMP"])
                    or not last["__CURSOR"] or len(last["__CURSOR"]) > 1024
                    or any(c.isspace() for c in last["__CURSOR"])):
                raise Failure("SSH 来源核验的 journal 新游标无效")
            cursor = last["__CURSOR"]
            fresh_us = max(fresh_us, int(last["__MONOTONIC_TIMESTAMP"]))
        time.sleep(min(0.2, max(0, deadline - time.monotonic())))
    raise Failure("SSH 来源核验超时，未获得完整的新连接证据")


def main(args):
    try:
        parsed = parse_args(args)
        if os.geteuid() != 0 or sys.platform != "linux":
            raise Failure("SSH 来源核验需要原生 Linux 宿主 root 环境", 10)
        if any(shutil.which(tool) is None for tool in ("ip", "ss", "docker", "journalctl")):
            raise Failure("SSH 来源核验缺少宿主只读工具", 10)
        result = witness(*parsed)
        print("source-verified=" + json.dumps(result, separators=(",", ":")), flush=True)
        return 0
    except Failure as error:
        print(str(error), file=sys.stderr)
        return error.code
    except (OSError, ValueError, KeyError, IndexError, TypeError):
        print("SSH 来源核验无法完成宿主证据读取", file=sys.stderr)
        return 15
    except KeyboardInterrupt:
        print("SSH 来源核验已取消", file=sys.stderr)
        return 15


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
