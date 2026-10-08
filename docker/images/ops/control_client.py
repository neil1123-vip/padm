#!/usr/bin/env python3
import argparse
import copy
import http.client
import json
import re
import socket
import sys
import threading
import time

from control_api import API_VERSION, MAX_STATE_BYTES, exact_keys, private_address, require_wireguard_address, stable_id, strict_object
from control_sync import build_draft, read_input

INVITE_FORMAT = "padm-docker-control-invite"
INVITE_VERSION = 1
MAX_SAFE_INTEGER = 9007199254740991
REQUEST_TIMEOUT = 5
TOKEN_PATTERN = re.compile(r"[a-f0-9]{48}")


def _listen(value):
    exact_keys(value, "interface address port")
    if value["interface"] != "wg-padm" or type(value["port"]) is not int or not 1024 <= value["port"] <= 65535:
        raise ValueError("控制邀请监听不合法")
    if not isinstance(value["address"], str):
        raise ValueError("控制邀请地址不合法")
    private_address(value["address"])
    return value


def validate_invitation(invitation):
    exact_keys(invitation, "format schema_version controller_id node_id listen peer_address token expires_at")
    if invitation["format"] != INVITE_FORMAT or type(invitation["schema_version"]) is not int \
            or invitation["schema_version"] != INVITE_VERSION:
        raise ValueError("控制邀请版本不支持")
    for key in ("controller_id", "node_id"):
        if not isinstance(invitation[key], str):
            raise ValueError("控制邀请身份不合法")
        stable_id(invitation[key])
    _listen(invitation["listen"])
    if not isinstance(invitation["peer_address"], str):
        raise ValueError("控制邀请地址不合法")
    private_address(invitation["peer_address"])
    if invitation["controller_id"] == invitation["node_id"] \
            or invitation["listen"]["address"] == invitation["peer_address"]:
        raise ValueError("控制邀请不能引用自己")
    if not isinstance(invitation["token"], str) or TOKEN_PATTERN.fullmatch(invitation["token"]) is None:
        raise ValueError("控制邀请 token 不合法")
    if type(invitation["expires_at"]) is not int or not 0 < invitation["expires_at"] <= MAX_SAFE_INTEGER \
            or invitation["expires_at"] <= time.time():
        raise ValueError("控制邀请已过期或有效期不合法")
    return invitation


def _response(response):
    if response.status != 200:
        raise ValueError("控制同步 HTTP 状态不支持")
    if response.headers.get_all("Content-Type") != ["application/json"]:
        raise ValueError("控制同步响应类型不匹配")
    if response.headers.get_all("Cache-Control") != ["no-store"]:
        raise ValueError("控制同步响应缓存策略不匹配")
    if response.headers.get_all("Transfer-Encoding") is not None:
        raise ValueError("控制同步响应禁止分块传输")
    lengths = response.headers.get_all("Content-Length")
    if lengths is None or len(lengths) != 1:
        raise ValueError("控制同步响应长度不匹配")
    length = lengths[0]
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)", length):
        raise ValueError("控制同步响应长度不规范")
    length = int(length)
    if length > MAX_STATE_BYTES:
        raise ValueError("控制同步响应超过大小限制")
    content = response.read(length + 1)
    if len(content) != length:
        raise ValueError("控制同步响应长度不匹配")
    try:
        value = json.loads(content, object_pairs_hook=strict_object)
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError, ValueError) as error:
        raise ValueError("控制同步响应 JSON 不合法") from error
    if not isinstance(value, dict):
        raise ValueError("控制同步响应必须是 JSON 对象")
    return value


def fetch_desired(invitation):
    # 仅使用邀请中的 RFC1918 字面地址，并固定从受管 WireGuard 地址发起连接。
    require_wireguard_address({
        "listen": {"interface": "wg-padm", "address": invitation["peer_address"]}
    })
    deadline = time.monotonic() + REQUEST_TIMEOUT
    connection = http.client.HTTPConnection(
        invitation["listen"]["address"], invitation["listen"]["port"],
        timeout=REQUEST_TIMEOUT, source_address=(invitation["peer_address"], 0))
    try:
        connection.connect()
        transport = connection.sock
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("控制同步请求超时")
        transport.settimeout(remaining)

        def expire():
            try:
                transport.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

        timer = threading.Timer(remaining, expire)
        timer.start()
        try:
            connection.request("GET", "/v1/desired", headers={
                "Authorization": f"Bearer {invitation['token']}",
                "X-Padm-Control-Version": str(API_VERSION),
                "Connection": "close",
            })
            with connection.getresponse() as response:
                return _response(response)
        finally:
            timer.cancel()
            timer.join()
    finally:
        connection.close()


def _mapping(spec, listeners):
    if not isinstance(listeners, list) or not listeners:
        raise ValueError("控制同步入口映射数量不合法")
    if any(not isinstance(listener, str) for listener in listeners):
        raise ValueError("控制同步入口映射不合法")
    listeners = list(dict.fromkeys(listeners))
    if len(listeners) > 16:
        raise ValueError("控制同步入口映射数量不合法")
    entries = spec.get("core", {}).get("protocols", [])
    available = {entry.get("listener_id") for entry in entries if isinstance(entry, dict)}
    if any(listener not in available for listener in listeners):
        raise ValueError("控制同步入口映射不存在")
    return listeners


def _new_sync(spec, invitation, listeners):
    if type(spec.get("schema_version")) is not int or spec["schema_version"] != 3 \
            or "control" in spec or "control_sync" in spec:
        raise ValueError("加入被控节点要求未接入的 v3 配置")
    listeners = _mapping(spec, listeners)
    spec["control_sync"] = {
        "schema_version": 1, "role": "controlled",
        "node_id": invitation["node_id"], "controller_id": invitation["controller_id"],
        "listener_ids": listeners, "last_revision": None, "last_digest": None,
        "managed_accounts": [],
        "connection": {"listen": invitation["listen"].copy(), "peer_address": invitation["peer_address"]},
    }
    return spec


def _existing_sync(spec, invitation):
    if type(spec.get("schema_version")) is not int or spec["schema_version"] != 3 \
            or "control" in spec or not isinstance(spec.get("control_sync"), dict):
        raise ValueError("同步要求已有被控连接")
    sync = spec["control_sync"]
    exact_keys(sync, "schema_version role node_id controller_id listener_ids last_revision last_digest managed_accounts connection")
    if sync["role"] != "controlled" or type(sync["schema_version"]) is not int or sync["schema_version"] != 1:
        raise ValueError("同步角色不支持")
    if sync["node_id"] != invitation["node_id"] or sync["controller_id"] != invitation["controller_id"]:
        raise ValueError("同步邀请身份与本机状态不匹配")
    connection = sync["connection"]
    exact_keys(connection, "listen peer_address")
    _listen(connection["listen"])
    if connection["listen"] != invitation["listen"] or connection["peer_address"] != invitation["peer_address"]:
        raise ValueError("同步邀请连接与本机状态不匹配")
    _mapping(spec, sync["listener_ids"])
    return spec


def build_client_draft(spec, invitation, listeners=None):
    invitation = validate_invitation(invitation)
    spec = copy.deepcopy(spec)
    if listeners is not None:
        spec = _new_sync(spec, invitation, listeners)
    else:
        spec = _existing_sync(spec, invitation)
    desired = fetch_desired(invitation)
    return build_draft(spec, desired)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", required=True)
    parser.add_argument("--invite", required=True)
    parser.add_argument("--listener", action="append")
    args = parser.parse_args()
    try:
        spec = read_input(args.spec, 16 * MAX_STATE_BYTES)
        invitation = read_input(args.invite, MAX_STATE_BYTES)
        draft = build_client_draft(spec, invitation, args.listener)
        json.dump(draft, sys.stdout, ensure_ascii=True, separators=(",", ":"))
        sys.stdout.write("\n")
    except (OSError, ValueError, KeyError, TypeError, AttributeError, RecursionError, http.client.HTTPException):
        # 输入和授权材料含凭据，失败时只返回状态码，不把原文写入普通输出。
        parser.exit(78, "被控接入或同步输入无效、授权失配或网络响应不支持\n")


if __name__ == "__main__":
    main()
