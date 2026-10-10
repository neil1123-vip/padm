#!/usr/bin/env python3
"""独立客户端保持无凭据 SSH 挑战连接，主机公钥必须已可信登记。"""

import ipaddress
import json
import re
import socket
import sys
import time


def parameters(arguments):
    if len(arguments) != 4:
        raise ValueError()
    target, port, username, known_hosts = arguments
    address = ipaddress.ip_address(target)
    if "%" in target or address.is_unspecified or address.is_multicast or address.is_link_local:
        raise ValueError()
    if not re.fullmatch(r"[1-9][0-9]{0,4}", port) or int(port) > 65535:
        raise ValueError()
    if not re.fullmatch(r"padm-source-[a-f0-9]{48}", username):
        raise ValueError()
    if not known_hosts or known_hosts.startswith("-"):
        raise ValueError()
    return str(address), int(port), username, known_hosts


def probe(target, port, username, known_hosts, paramiko):
    hosts = paramiko.HostKeys()
    hosts.load(known_hosts)
    host = target if port == 22 else f"[{target}]:{port}"
    keys = hosts.lookup(host)
    if not keys:
        raise ValueError()
    client = socket.create_connection((target, port), timeout=5)
    transport = None
    try:
        transport = paramiko.Transport(client)
        transport.start_client(timeout=5)
        remote = transport.get_remote_server_key()
        expected = keys.get(remote.get_name())
        if expected is None or remote != expected:
            raise ValueError()
        try:
            transport.auth_none(username)
        except paramiko.AuthenticationException:
            pass
        else:
            raise ValueError()
        if not transport.is_active() or transport.is_authenticated():
            raise ValueError()
        print("ssh-source-held=" + json.dumps({
            "target": target, "port": port, "hold_seconds": 25,
        }, separators=(",", ":")), flush=True)
        started = time.monotonic()
        while time.monotonic() - started < 25:
            if not transport.is_active() or transport.is_authenticated():
                raise ValueError()
            time.sleep(0.1)
    finally:
        try:
            if transport is not None:
                transport.close()
        finally:
            client.close()


def main(arguments):
    try:
        values = parameters(arguments)
    except ValueError:
        print("用法: ssh-source-client.py <目标 IP> <端口> <挑战用户名> <可信 known_hosts>", file=sys.stderr)
        return 2
    try:
        import paramiko
    except ImportError:
        print("独立客户端缺少 Paramiko，请通过客户端系统官方软件源安装。", file=sys.stderr)
        return 10
    try:
        probe(*values, paramiko)
        return 0
    except KeyboardInterrupt:
        return 130
    except (OSError, ValueError, paramiko.SSHException):
        print("SSH 主机密钥、无凭据认证或保持连接检查失败。", file=sys.stderr)
        return 15


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
