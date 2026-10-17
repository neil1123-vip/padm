#!/usr/bin/env python3
"""WireGuard 的私密准备与规范 Peer 配置生成。"""

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
    return configuration_peers(identity, private, [{
        "address": peer_address, "public_key": peer_public_key, "endpoint": peer_endpoint}])


def configuration_peers(identity, private, peers):
    require(isinstance(peers, list) and len(peers) > 0)
    addresses, keys = set(), set()
    for remote in peers:
        require(isinstance(remote, dict) and set(remote) == {"address", "public_key", "endpoint"})
        peer_values(identity, remote["address"], remote["public_key"], remote["endpoint"])
        require(remote["address"] not in addresses and remote["public_key"] not in keys)
        addresses.add(remote["address"])
        keys.add(remote["public_key"])
    text = ("[Interface]\nAddress = {address}/32\nListenPort = {listen_port}\n"
            "PrivateKey = {private}\n").format(**identity, private=private)
    for remote in sorted(peers, key=lambda item: int(ipaddress.IPv4Address(item["address"]))):
        text += "\n[Peer]\nPublicKey = {public_key}\nAllowedIPs = {address}/32\n".format(**remote)
        if remote["endpoint"] is not None:
            text += "Endpoint = " + remote["endpoint"] + "\nPersistentKeepalive = 25\n"
    data = text.encode("ascii")
    require(len(data) <= 4096)
    return data


def load(directory, include_peer=False, include_peers=False):
    require(not (include_peer and include_peers))
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
    remote_values = []
    if "wg-padm.conf" in names:
        data = read_file(directory, "wg-padm.conf", 4096)
        sections = data.split(b"\n[Peer]\n")
        require(len(sections) > 1)
        for section in sections[1:]:
            match = re.fullmatch(rb"PublicKey = ([A-Za-z0-9+/]{43}=)\nAllowedIPs = ([0-9.]+)/32\n"
                                 rb"(?:Endpoint = ([^\n]+)\nPersistentKeepalive = 25\n)?", section)
            require(match is not None)
            public, remote, target = (part.decode("ascii") if part is not None else None
                                      for part in match.groups())
            remote_values.append({"address": remote, "public_key": public, "endpoint": target})
        require(data == configuration_peers(identity, private, remote_values))
    result = identity, private, "wg-padm.conf" in names
    if include_peer:
        # 旧迁移和灾备入口只能读取单项，不能隐式选择多 Peer 中的第一项。
        require(len(remote_values) <= 1)
        remote = remote_values[0] if remote_values else None
        return result + ((remote["address"], remote["public_key"], remote["endpoint"])
                         if remote else None,)
    return result + (remote_values,) if include_peers else result


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
            peer_public_key=None, peer_endpoint=None, private_key=None, public_key=None,
            peer_action=None):
    require((private_key is None) == (public_key is None))
    require(peer_action in (None, "add", "update", "remove"))
    with parent_directory(directory) as (parent, name):
        require(Path(directory) != Path(destination) and Path(directory) not in Path(destination).parents)
        source = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        try:
            identity, private, configured, remotes = load(source, include_peers=True)
            require(configured)
            if peer_action is not None:
                identity_data = read_file(source, "identity.json", 4096)
                private_data = read_file(source, "private.key", 45)
        finally:
            os.close(source)
    identity = dict(identity)
    if peer_action is None:
        # 旧迁移仍限定单项，不能把未选定的 Peer 当作修改目标。
        require(len(remotes) == 1)
        if own_address is not None:
            identity["address"] = address(own_address)
        if listen_port is not None:
            identity["listen_port"] = port(listen_port)
        if private_key is not None:
            private, identity["public_key"] = read_key(private_key), read_key(public_key)
        remote = remotes[0]
        if peer_address is not None:
            remote["address"] = peer_address
        if peer_public_key is not None:
            remote["public_key"] = peer_public_key
        if peer_endpoint is not None:
            remote["endpoint"] = None if peer_endpoint == "none" else peer_endpoint
    else:
        # Peer 集合变更不承载本机身份迁移，必须按地址精确选中已有项。
        require(own_address is None and listen_port is None and private_key is None)
        address(peer_address)
        selected = next((item for item in remotes if item["address"] == peer_address), None)
        if peer_action == "add":
            require(selected is None and peer_public_key is not None)
            remotes.append({"address": peer_address, "public_key": peer_public_key,
                            "endpoint": None if peer_endpoint == "none" else peer_endpoint})
        elif peer_action == "update":
            require(selected is not None and (peer_public_key is not None or peer_endpoint is not None))
            if peer_public_key is not None:
                selected["public_key"] = peer_public_key
            if peer_endpoint is not None:
                selected["endpoint"] = None if peer_endpoint == "none" else peer_endpoint
        else:
            require(selected is not None and len(remotes) > 1
                    and peer_public_key is None and peer_endpoint is None)
            remotes.remove(selected)
    data = configuration_peers(identity, private, remotes)
    if peer_action is None:
        identity_data = (json.dumps(identity, sort_keys=True) + "\n").encode()
        private_data = (private + "\n").encode("ascii")
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
            write_file(stage, "private.key", private_data)
            write_file(stage, "identity.json", identity_data)
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


def addresses(directory):
    with parent_directory(directory) as (parent, name):
        fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        try:
            identity, _, configured, remote = load(fd, include_peer=True)
            require(configured)
            return {"address": identity["address"], "peer_address": remote[0]}
        finally:
            os.close(fd)


def peers(directory):
    with parent_directory(directory) as (parent, name):
        fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        try:
            identity, _, configured, remotes = load(fd, include_peers=True)
            require(configured)
            return {"address": identity["address"], "peers": remotes}
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
    migration.add_argument("--peer-action", choices=("add", "update", "remove"))
    commands.add_parser("status", allow_abbrev=False).add_argument("--directory", required=True)
    commands.add_parser("addresses", allow_abbrev=False).add_argument("--directory", required=True)
    commands.add_parser("peers", allow_abbrev=False).add_argument("--directory", required=True)
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
