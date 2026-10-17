#!/usr/bin/env python3
"""单 Peer WireGuard 的私密准备与固定配置生成。"""

import argparse
import base64
import binascii
from contextlib import contextmanager
import ctypes
import errno
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import signal
import stat
import sys


IDENTITY_FIELDS = {"schema_version", "address", "listen_port", "public_key"}
PRIVATE_NETWORKS = tuple(ipaddress.IPv4Network(value) for value in
                         ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"))


def require(condition):
    if not condition:
        raise ValueError("WireGuard 准备输入或私密状态无效")


def key(value):
    require(isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9+/]{43}=", value))
    try:
        decoded = base64.b64decode(value, validate=True)
    except binascii.Error as error:
        raise ValueError("WireGuard 密钥编码无效") from error
    require(len(decoded) == 32 and base64.b64encode(decoded).decode("ascii") == value)
    return value


def address(value):
    parsed = ipaddress.IPv4Address(value)
    require(str(parsed) == value and any(parsed in network for network in PRIVATE_NETWORKS))
    return value


def port(value):
    require(type(value) is int and 1024 <= value <= 65535)
    return value


def endpoint(value):
    host, separator, number = value.rpartition(":")
    require(separator and re.fullmatch(r"[1-9][0-9]{3,4}", number))
    parsed = ipaddress.IPv4Address(host)
    require(str(parsed) == host and not parsed.is_loopback and not parsed.is_multicast
            and not parsed.is_link_local and int(parsed) >> 24 != 0
            and int(parsed) < int(ipaddress.IPv4Address("224.0.0.0")))
    port(int(number))
    return value


def checked_directory(fd, private=False):
    info = os.fstat(fd)
    require(stat.S_ISDIR(info.st_mode) and info.st_uid == 0
            and stat.S_IMODE(info.st_mode) & 0o22 == 0)
    require(not private or stat.S_IMODE(info.st_mode) == 0o700)


@contextmanager
def parent_directory(value):
    require(os.geteuid() == 0 and isinstance(value, str) and "\0" not in value)
    path = Path(value)
    require(path.is_absolute() and str(path) == value and len(path.parts) > 1
            and all(part not in (".", "..") for part in path.parts))
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        checked_directory(fd)
        for part in path.parts[1:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
            checked_directory(fd)
        yield fd, path.name
    finally:
        os.close(fd)


def read_file(directory, name, limit):
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    try:
        info = os.fstat(fd)
        require(stat.S_ISREG(info.st_mode) and info.st_uid == 0 and info.st_nlink == 1
                and stat.S_IMODE(info.st_mode) == 0o600 and 0 < info.st_size <= limit)
        data = os.read(fd, limit + 1)
        require(len(data) == info.st_size and b"\0" not in data)
        return data
    finally:
        os.close(fd)


def read_key(path):
    with parent_directory(path) as (parent, name):
        return key(read_file(parent, name, 45).decode("ascii").removesuffix("\n"))


def unique_fields(pairs):
    result = {}
    for name, value in pairs:
        require(name not in result)
        result[name] = value
    return result


def peer_values(identity, peer_address, peer_public_key, peer_endpoint):
    address(peer_address)
    key(peer_public_key)
    require(peer_address != identity["address"] and peer_public_key != identity["public_key"])
    if peer_endpoint is not None:
        endpoint(peer_endpoint)


def configuration(identity, private, peer_address, peer_public_key, peer_endpoint):
    peer_values(identity, peer_address, peer_public_key, peer_endpoint)
    text = ("[Interface]\nAddress = {address}/32\nListenPort = {listen_port}\n"
            "PrivateKey = {private}\n\n[Peer]\nPublicKey = {public}\n"
            "AllowedIPs = {peer}/32\n").format(**identity, private=private,
                                             public=peer_public_key, peer=peer_address)
    if peer_endpoint is not None:
        text += "Endpoint = " + peer_endpoint + "\nPersistentKeepalive = 25\n"
    return text.encode("ascii")


def load(directory, include_peer=False):
    checked_directory(directory, private=True)
    names = set(os.listdir(directory))
    require({"identity.json", "private.key"} <= names
            and names <= {"identity.json", "private.key", "wg-padm.conf"})
    identity = json.loads(read_file(directory, "identity.json", 4096),
                          object_pairs_hook=unique_fields)
    require(isinstance(identity, dict) and set(identity) == IDENTITY_FIELDS
            and type(identity["schema_version"]) is int and identity["schema_version"] == 1)
    address(identity["address"])
    port(identity["listen_port"])
    key(identity["public_key"])
    private = key(read_file(directory, "private.key", 45).decode("ascii").removesuffix("\n"))
    remote_values = None
    if "wg-padm.conf" in names:
        data = read_file(directory, "wg-padm.conf", 4096)
        match = re.search(rb"\nPublicKey = ([A-Za-z0-9+/]{43}=)\nAllowedIPs = ([0-9.]+)/32\n"
                          rb"(?:Endpoint = ([^\n]+)\nPersistentKeepalive = 25\n)?$", data)
        require(match is not None)
        public, remote, target = (part.decode("ascii") if part is not None else None
                                  for part in match.groups())
        require(data == configuration(identity, private, remote, public, target))
        remote_values = remote, public, target
    result = identity, private, "wg-padm.conf" in names
    return result + (remote_values,) if include_peer else result


def write_file(directory, name, data, publish=None):
    fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                 0o600, dir_fd=directory)
    try:
        with os.fdopen(fd, "wb") as output:
            os.fchmod(output.fileno(), 0o600)
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        if publish is not None:
            # link 的目标必须不存在，发布后仅清理本次排他创建的临时名称。
            os.link(name, publish, src_dir_fd=directory, dst_dir_fd=directory,
                    follow_symlinks=False)
    finally:
        if publish is not None:
            os.unlink(name, dir_fd=directory)


def publish_directory(parent, temporary, name):
    # Linux 的不覆盖重命名避免并发创建空目标时被普通 rename 覆盖。
    try:
        rename = ctypes.CDLL(None, use_errno=True).renameat2
    except AttributeError as error:
        raise OSError(errno.ENOSYS, "需要 Linux renameat2") from error
    rename.argtypes = (ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint)
    rename.restype = ctypes.c_int
    if rename(parent, os.fsencode(temporary), parent, os.fsencode(name), 1) != 0:
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code))


def prepare(directory, own_address, listen_port, private_key, public_key):
    identity = {"schema_version": 1, "address": address(own_address),
                "listen_port": port(listen_port), "public_key": read_key(public_key)}
    private = read_key(private_key)
    with parent_directory(directory) as (parent, name):
        try:
            os.stat(name, dir_fd=parent, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise FileExistsError("WireGuard 准备目录已经存在")
        temporary = ".wireguard-" + secrets.token_hex(12)
        os.mkdir(temporary, 0o700, dir_fd=parent)
        stage = os.open(temporary, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        try:
            os.fchmod(stage, 0o700)
            write_file(stage, "private.key", (private + "\n").encode("ascii"))
            write_file(stage, "identity.json", (json.dumps(identity, sort_keys=True) + "\n").encode())
            os.fsync(stage)
            publish_directory(parent, temporary, name)
            temporary = None
            os.fsync(parent)
        finally:
            if temporary is not None:
                try:
                    remaining = os.stat(temporary, dir_fd=parent, follow_symlinks=False)
                except FileNotFoundError:
                    remaining = None
                if remaining is not None:
                    require(remaining.st_ino == os.fstat(stage).st_ino)
                    for file in ("private.key", "identity.json"):
                        try:
                            os.unlink(file, dir_fd=stage)
                        except FileNotFoundError:
                            pass
                    os.rmdir(temporary, dir_fd=parent)
            os.close(stage)
    return {**identity, "configured": False}


def peer(directory, peer_address, peer_public_key, peer_endpoint=None):
    with parent_directory(directory) as (parent, name):
        fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        try:
            identity, private, configured = load(fd)
            require(not configured)
            data = configuration(identity, private, peer_address, peer_public_key, peer_endpoint)
            write_file(fd, ".wireguard-" + secrets.token_hex(12), data, "wg-padm.conf")
            os.fsync(fd)
        finally:
            os.close(fd)
    return {**identity, "configured": True}


def migrate(directory, destination, own_address=None, listen_port=None, peer_address=None,
            peer_public_key=None, peer_endpoint=None, private_key=None, public_key=None):
    require((private_key is None) == (public_key is None))
    with parent_directory(directory) as (parent, name):
        require(Path(directory) != Path(destination) and Path(directory) not in Path(destination).parents)
        source = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        try:
            identity, private, configured, remote = load(source, include_peer=True)
            require(configured)
        finally:
            os.close(source)
    identity = dict(identity)
    if own_address is not None:
        identity["address"] = address(own_address)
    if listen_port is not None:
        identity["listen_port"] = port(listen_port)
    if private_key is not None:
        private, identity["public_key"] = read_key(private_key), read_key(public_key)
    remote_address, remote_public, remote_endpoint = remote
    if peer_address is not None:
        remote_address = peer_address
    if peer_public_key is not None:
        remote_public = peer_public_key
    if peer_endpoint is not None:
        remote_endpoint = None if peer_endpoint == "none" else peer_endpoint
    data = configuration(identity, private, remote_address, remote_public, remote_endpoint)
    with parent_directory(destination) as (parent, name):
        try:
            os.stat(name, dir_fd=parent, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise FileExistsError("WireGuard 迁移候选目录已经存在")
        temporary = ".wireguard-" + secrets.token_hex(12)
        stage, created, completed = None, None, False
        try:
            # 建立目录与持有其描述符之间不响应信号，异常清理才有精确归属凭据。
            blocked = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT, signal.SIGTERM})
            try:
                os.mkdir(temporary, 0o700, dir_fd=parent)
                created = os.stat(temporary, dir_fd=parent, follow_symlinks=False)
                stage = os.open(temporary, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
            finally:
                signal.pthread_sigmask(signal.SIG_SETMASK, blocked)
            os.fchmod(stage, 0o700)
            write_file(stage, "private.key", (private + "\n").encode("ascii"))
            write_file(stage, "identity.json", (json.dumps(identity, sort_keys=True) + "\n").encode())
            write_file(stage, "wg-padm.conf", data)
            os.fsync(stage)
            publish_directory(parent, temporary, name)
            os.fsync(parent)
            completed = True
        finally:
            blocked = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT, signal.SIGTERM})
            try:
                if stage is None and created is not None:
                    remaining = os.stat(temporary, dir_fd=parent, follow_symlinks=False)
                    require((remaining.st_dev, remaining.st_ino) == (created.st_dev, created.st_ino))
                    os.rmdir(temporary, dir_fd=parent)
                elif stage is not None:
                    if not completed:
                        # 发布后抛错也只回收同 inode 的候选，不删除并发产生的目标。
                        for candidate in (temporary, name):
                            try:
                                remaining = os.stat(candidate, dir_fd=parent, follow_symlinks=False)
                            except FileNotFoundError:
                                continue
                            owned = os.fstat(stage)
                            if (remaining.st_dev, remaining.st_ino) != (owned.st_dev, owned.st_ino):
                                continue
                            require(set(os.listdir(stage)) <= {"private.key", "identity.json", "wg-padm.conf"})
                            for file in ("private.key", "identity.json", "wg-padm.conf"):
                                try:
                                    os.unlink(file, dir_fd=stage)
                                except FileNotFoundError:
                                    pass
                            os.rmdir(candidate, dir_fd=parent)
            finally:
                try:
                    if stage is not None:
                        os.close(stage)
                finally:
                    signal.pthread_sigmask(signal.SIG_SETMASK, blocked)
    return {**identity, "configured": True}


def status(directory):
    with parent_directory(directory) as (parent, name):
        try:
            fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        except FileNotFoundError:
            return {"state": "absent", "configured": False}
        try:
            checked_directory(fd)
            if not os.listdir(fd):
                return {"state": "absent", "configured": False}
            identity, _, configured = load(fd)
            return {**identity, "configured": configured}
        finally:
            os.close(fd)


def interrupted(_number, _frame):
    raise InterruptedError("WireGuard 准备已中断")


def main():
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    commands = parser.add_subparsers(dest="action", required=True)
    setup = commands.add_parser("prepare", allow_abbrev=False)
    setup.add_argument("--directory", required=True)
    setup.add_argument("--address", required=True)
    setup.add_argument("--listen-port", type=int, required=True)
    setup.add_argument("--private-key", required=True)
    setup.add_argument("--public-key", required=True)
    remote = commands.add_parser("peer", allow_abbrev=False)
    remote.add_argument("--directory", required=True)
    remote.add_argument("--peer-address", required=True)
    remote.add_argument("--peer-public-key", required=True)
    remote.add_argument("--endpoint")
    migration = commands.add_parser("migrate", allow_abbrev=False)
    migration.add_argument("--directory", required=True)
    migration.add_argument("--destination", required=True)
    migration.add_argument("--address")
    migration.add_argument("--listen-port", type=int)
    migration.add_argument("--peer-address")
    migration.add_argument("--peer-public-key")
    migration.add_argument("--endpoint")
    migration.add_argument("--private-key")
    migration.add_argument("--public-key")
    commands.add_parser("status", allow_abbrev=False).add_argument("--directory", required=True)
    options = [value.partition("=")[0] for value in sys.argv[1:] if value.startswith("--")]
    if len(options) != len(set(options)):
        parser.error("WireGuard 参数不能重复")
    arguments = vars(parser.parse_args())
    action = arguments.pop("action")
    if action in ("prepare", "migrate"):
        arguments["own_address"] = arguments.pop("address")
    if action in ("peer", "migrate"):
        arguments["peer_endpoint"] = arguments.pop("endpoint")
    try:
        result = globals()[action](**arguments)
    except (OSError, ValueError, TypeError, UnicodeError):
        print("WireGuard 准备失败：输入、私密路径或现有状态无效，未覆盖已有文件", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    signal.signal(signal.SIGINT, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    sys.exit(main())
