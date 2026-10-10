#!/usr/bin/env python3
import argparse
import fcntl
import hashlib
import hmac
import http.client
import ipaddress
import json
import os
import re
import socket
import socketserver
import stat
import struct
import threading
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

API_VERSION = 1
MAX_STATE_BYTES = 1024 * 1024
MAX_HEALTH_BYTES = 256
HEALTH_TIMEOUT = 2
PRIVATE_NETWORKS = tuple(ipaddress.ip_network(value) for value in (
    "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
))


def private_address(value):
    address = ipaddress.IPv4Address(value)
    if str(address) != value or not any(address in network for network in PRIVATE_NETWORKS):
        raise ValueError("控制地址必须是明确的 RFC 1918 IPv4 地址")
    return address


def exact_keys(value, keys):
    if not isinstance(value, dict) or set(value) != set(keys.split()):
        raise ValueError("控制状态字段不匹配")


def stable_id(value):
    parsed = uuid.UUID(value)
    if str(parsed) != value or parsed.variant != uuid.RFC_4122 or parsed.version not in range(1, 6):
        raise ValueError("控制身份不是规范 UUID")


def strict_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("控制状态有重复 JSON 字段")
        result[key] = value
    return result


def validate_state(state):
    exact_keys(state, "schema_version role node_id listen peer revision accounts")
    if type(state["schema_version"]) is not int or state["schema_version"] != API_VERSION or state["role"] != "main":
        raise ValueError("控制状态版本或角色不支持")
    stable_id(state["node_id"])
    exact_keys(state["listen"], "interface address port")
    listen = state["listen"]
    if listen["interface"] != "wg-padm" or type(listen["port"]) is not int or not 1024 <= listen["port"] <= 65535:
        raise ValueError("控制监听接口或端口不支持")
    private_address(listen["address"])
    exact_keys(state["peer"], "id address enabled expires_at token_sha256")
    peer = state["peer"]
    stable_id(peer["id"])
    private_address(peer["address"])
    if peer["id"] == state["node_id"] or peer["address"] == listen["address"]:
        raise ValueError("控制节点不能引用自己")
    if type(peer["enabled"]) is not bool or type(peer["expires_at"]) is not int or not 0 < peer["expires_at"] <= 9007199254740991:
        raise ValueError("控制授权开关或有效期不合法")
    if not isinstance(peer["token_sha256"], str) or not re.fullmatch(r"[a-f0-9]{64}", peer["token_sha256"]):
        raise ValueError("控制 token 摘要不合法")
    if type(state["revision"]) is not int or not 0 <= state["revision"] <= 9007199254740991:
        raise ValueError("控制版本序号不合法")
    validate_accounts(state["accounts"])
    return state


def validate_accounts(accounts):
    if not isinstance(accounts, list) or len(accounts) > 256:
        raise ValueError("控制账号集合超出边界")
    ids, credentials, passwords, ss_keys = set(), set(), set(), set()
    for account in accounts:
        exact_keys(account, "id name enabled uuid password shadowsocks_password")
        stable_id(account["id"])
        stable_id(account["uuid"])
        if account["id"] in ids or account["uuid"] in credentials:
            raise ValueError("控制账号身份或凭据重复")
        ids.add(account["id"])
        credentials.add(account["uuid"])
        if type(account["enabled"]) is not bool:
            raise ValueError("控制账号开关不合法")
        name = account["name"]
        if not isinstance(name, str) or not 1 <= len(name) <= 64 or any(ord(c) < 32 or ord(c) == 127 for c in name):
            raise ValueError("控制账号名称不合法")
        password = account["password"]
        if not isinstance(password, str) or not re.fullmatch(r"[A-Za-z0-9._~@+=:-]{16,128}", password):
            raise ValueError("控制账号密码不合法")
        if password in passwords:
            raise ValueError("控制账号密码重复")
        passwords.add(password)
        ss = account["shadowsocks_password"]
        if ss is not None and (not isinstance(ss, str) or not re.fullmatch(r"[A-Za-z0-9+/]{21}[AQgw]==", ss)):
            raise ValueError("控制 Shadowsocks 凭据不合法")
        if ss is not None:
            if ss in ss_keys:
                raise ValueError("控制 Shadowsocks 凭据重复")
            ss_keys.add(ss)
    # 同账号可沿用旧 ID/UUID；不同账号不能占用彼此的身份。
    for account in accounts:
        if account["uuid"] in ids and account["uuid"] != account["id"]:
            raise ValueError("控制账号身份与其他认证 UUID 冲突")
    return accounts


def read_state(path):
    path = Path(path)
    if not path.is_absolute():
        raise ValueError("控制状态路径必须是绝对路径")
    for parent in path.parents:
        metadata = parent.lstat()
        if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != 0 or metadata.st_mode & 0o022:
            raise ValueError("控制状态目录不安全")
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as source:
        metadata = os.fstat(source.fileno())
        if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0
                or stat.S_IMODE(metadata.st_mode) & ~0o640):
            raise ValueError("控制状态文件权限不安全")
        if metadata.st_size > MAX_STATE_BYTES:
            raise ValueError("控制状态超过大小限制")
        content = source.read(MAX_STATE_BYTES + 1)
    if len(content) > MAX_STATE_BYTES:
        raise ValueError("控制状态超过大小限制")
    try:
        return validate_state(json.loads(content, object_pairs_hook=strict_object))
    except (KeyError, TypeError, AttributeError, RecursionError) as error:
        raise ValueError("控制状态类型不合法") from error


def require_wireguard_address(state):
    listen = state["listen"]
    # 只核对受管接口的实际地址；不创建接口，不改路由或防火墙。
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as descriptor:
        request = struct.pack("256s", listen["interface"].encode("ascii"))
        result = fcntl.ioctl(descriptor.fileno(), 0x8915, request)
    if socket.inet_ntoa(result[20:24]) != listen["address"]:
        raise ValueError("控制监听地址不属于 wg-padm")


def health_check(state):
    require_wireguard_address(state)
    listen = state["listen"]
    connection = http.client.HTTPConnection(listen["address"], listen["port"], timeout=HEALTH_TIMEOUT)
    try:
        connection.connect()
        transport = connection.sock

        def expire():
            try:
                transport.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

        # 无认证的固定拒绝响应证明服务在运行，不使健康依赖授权或泄露凭据。
        deadline = threading.Timer(HEALTH_TIMEOUT, expire)
        deadline.start()
        try:
            connection.request("GET", "/v1/health")
            with connection.getresponse() as response:
                if (response.status != 401
                        or response.headers.get_all("Content-Type") != ["application/json"]
                        or response.headers.get_all("Cache-Control") != ["no-store"]
                        or response.headers.get_all("Content-Length") != ["35"]
                        or response.headers.get_all("Transfer-Encoding") is not None
                        or response.read(MAX_HEALTH_BYTES + 1) != b'{"ok":false,"error":"unauthorized"}'):
                    raise ValueError("控制健康响应不匹配")
        finally:
            deadline.cancel()
            deadline.join()
    finally:
        connection.close()


def request_log_tuple(connection):
    try:
        peer, target = connection.getpeername(), connection.getsockname()
        for endpoint in (peer, target):
            if (not isinstance(endpoint, tuple) or len(endpoint) != 2
                    or not isinstance(endpoint[0], str)
                    or str(ipaddress.IPv4Address(endpoint[0])) != endpoint[0]
                    or type(endpoint[1]) is not int or not 1 <= endpoint[1] <= 65535):
                return None
        return peer[0], target[0], target[1]
    except (AttributeError, OSError, TypeError, ValueError):
        return None


def request_log_event(status, endpoints):
    if endpoints is None:
        return
    source, target, port = endpoints
    timestamp = datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    print(f"{timestamp} control-request status={status} source={source} target={target} port={port}", flush=True)


class ControlHandler(BaseHTTPRequestHandler):
    server_version = "padm-control/1"
    sys_version = ""

    def setup(self):
        super().setup()
        # 请求读完后连接可能被重置，响应日志保留已接受 socket 的真实三元组。
        self.log_endpoints = request_log_tuple(self.connection)

    def handle_one_request(self):
        super().handle_one_request()
        if getattr(self, "raw_requestline", None) == b"":
            request_log_event("connection_closed", self.log_endpoints)

    def do_GET(self):
        try:
            state = read_state(self.server.state_path)
            if state["listen"] != self.server.listen:
                raise ValueError("控制监听状态已改变，请重启受管服务")
        except (OSError, ValueError):
            self.reply(503, {"ok": False, "error": "invalid_state"})
            return
        peer = state["peer"]
        authorization = self.headers.get("Authorization", "")
        token = authorization.removeprefix("Bearer ")
        authorized = (
            len(self.headers.get_all("Authorization", [])) == 1
            and authorization.startswith("Bearer ")
            and re.fullmatch(r"[a-f0-9]{48}", token) is not None
            and hmac.compare_digest(hashlib.sha256(token.encode("ascii")).hexdigest(), peer["token_sha256"])
            and peer["enabled"] and peer["expires_at"] > time.time()
            and self.client_address[0] == peer["address"]
        )
        if not authorized:
            self.reply(401, {"ok": False, "error": "unauthorized"})
        elif self.headers.get_all("X-Padm-Control-Version", []) != [str(API_VERSION)]:
            self.reply(409, {"ok": False, "error": "api_version_mismatch", "api_version": API_VERSION})
        elif self.path not in ("/v1/health", "/v1/desired"):
            self.reply(404, {"ok": False, "error": "unknown_endpoint"})
        else:
            response = {
                "ok": True, "api_version": API_VERSION, "controller_id": state["node_id"],
                "node_id": peer["id"], "revision": state["revision"],
            }
            if self.path == "/v1/health":
                response["capabilities"] = ["health", "desired"]
            else:
                response["accounts"] = state["accounts"]
            self.reply(200, response)

    def reply(self, status_code, value):
        content = json.dumps(value, ensure_ascii=True, separators=(",", ":")).encode("ascii")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        self.wfile.write(content)

    def send_error(self, code, message=None, explain=None):
        # 不回显畸形请求，防止 URL 或请求行中的秘密进入错误和日志。
        self.reply(code, {"ok": False, "error": "invalid_request"})

    def log_request(self, code="-", size="-"):
        if isinstance(code, int) and not isinstance(code, bool) and 100 <= code <= 599:
            request_log_event(int(code), self.log_endpoints)

    def log_error(self, message_format, *args):
        # BaseHTTP 会吞掉读取超时，只按异常类型记录关闭，不读取异常原文。
        if len(args) == 1 and isinstance(args[0], TimeoutError):
            request_log_event("connection_closed", self.log_endpoints)

    def log_message(self, message_format, *args):
        # BaseHTTP 的格式参数可能含请求原文，日志只走固定状态与真实 socket。
        pass


class ControlServer(HTTPServer):
    # ponytail: 一主一被控串行读取；节点扩展后再按实测增加有界并发。
    request_timeout = 5

    def server_bind(self):
        # 私网字面地址无需反向 DNS，避免离线控制服务启动等待外部解析。
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]

    def get_request(self):
        connection, address = super().get_request()
        connection.settimeout(self.request_timeout)
        return connection, address

    def finish_request(self, connection, address):
        # 断连后 peer 查询可能失效，只保留本次真实 socket 的规范三元组。
        endpoints = request_log_tuple(connection)

        def expire():
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

        # 空闲超时不能阻止持续慢速发包，整个请求另设总时限。
        deadline = threading.Timer(self.request_timeout, expire)
        deadline.start()
        try:
            super().finish_request(connection, address)
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            request_log_event("connection_closed", endpoints)
        finally:
            deadline.cancel()
            deadline.join()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", action="version", version="padm-control/1")
    parser.add_argument("--state", required=True)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--health", action="store_true")
    args = parser.parse_args()
    try:
        state = read_state(args.state)
        if args.check:
            return
        if args.health:
            health_check(state)
            return
        require_wireguard_address(state)
        server = ControlServer((state["listen"]["address"], state["listen"]["port"]), ControlHandler)
        server.state_path = args.state
        server.listen = state["listen"]
        with server:
            server.serve_forever()
    except (OSError, ValueError, http.client.HTTPException) as error:
        if args.health:
            parser.exit(1, "控制服务健康检查失败\n")
        parser.exit(78, f"控制后端启动失败: {error}\n")


if __name__ == "__main__":
    main()
