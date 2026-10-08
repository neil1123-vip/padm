#!/usr/bin/env python3
import argparse
import copy
import hashlib
import json
import os
import stat
import sys

from control_api import API_VERSION, MAX_STATE_BYTES, exact_keys, stable_id, strict_object, validate_accounts


def read_input(path, maximum):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as source:
        metadata = os.fstat(source.fileno())
        if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0
                or stat.S_IMODE(metadata.st_mode) & ~0o600 or metadata.st_size > maximum):
            raise ValueError("同步输入不是 root 私有普通文件")
        content = source.read(maximum + 1)
    if len(content) > maximum:
        raise ValueError("同步输入超过大小限制")
    value = json.loads(content, object_pairs_hook=strict_object)
    if not isinstance(value, dict):
        raise ValueError("同步输入必须是单个 JSON 对象")
    return value


def canonical(accounts):
    return json.dumps(sorted(accounts, key=lambda account: account["id"]),
                      sort_keys=True, ensure_ascii=True, separators=(",", ":")).encode("ascii")


def build_draft(spec, desired):
    exact_keys(desired, "ok api_version controller_id node_id revision accounts")
    if desired["ok"] is not True or type(desired["api_version"]) is not int or desired["api_version"] != API_VERSION:
        raise ValueError("同步响应版本不支持")
    for key in ("controller_id", "node_id"):
        stable_id(desired[key])
    revision = desired["revision"]
    if type(revision) is not int or not 0 <= revision <= 9007199254740991:
        raise ValueError("同步版本序号不合法")
    validate_accounts(desired["accounts"])
    sync = spec["control_sync"]
    if (sync["role"] != "controlled" or sync["node_id"] == sync["controller_id"]
            or desired["controller_id"] != sync["controller_id"] or desired["node_id"] != sync["node_id"]):
        raise ValueError("同步响应来源或被控身份不匹配")
    previous = sync["managed_accounts"]
    current = spec.get("accounts", [])
    current_by_id = {account["id"]: account for account in current}
    if any(current_by_id.get(account["id"]) != account for account in previous):
        raise ValueError("受管账号已被本机修改，拒绝覆盖")
    listeners = sync["listener_ids"]
    entries = {entry["listener_id"]: entry for entry in spec["core"]["protocols"]}
    if not listeners or any(listener not in entries for listener in listeners):
        raise ValueError("同步入口映射不存在")
    if any(account["listeners"] != listeners for account in previous):
        raise ValueError("同步入口映射已改变")
    digest = hashlib.sha256(canonical(desired["accounts"])).hexdigest()
    if sync["last_revision"] is not None:
        if revision < sync["last_revision"]:
            raise ValueError("同步版本落后于已提交版本")
        if revision == sync["last_revision"] and digest != sync["last_digest"]:
            raise ValueError("同一同步版本的内容不一致")
    need_ss = any(entries[listener]["id"] == 30 for listener in listeners)
    managed = []
    for source in sorted(desired["accounts"], key=lambda account: account["id"]):
        account = copy.deepcopy(source)
        account["listeners"] = listeners.copy()
        if not need_ss:
            account["shadowsocks_password"] = None
        elif account["shadowsocks_password"] is None:
            raise ValueError("Shadowsocks 映射缺少账号凭据")
        managed.append(account)
    if revision == sync["last_revision"] and managed != previous:
        raise ValueError("同步归属与已提交内容不一致")
    owned_ids = {account["id"] for account in previous}
    local = [account for account in current if account["id"] not in owned_ids]
    # 不用覆盖解决碰撞；认证、身份与流量账目必须保持唯一。
    for remote in managed:
        for account in local:
            if ({remote["id"], remote["uuid"]} & {account["id"], account["uuid"]}
                    or remote["password"] == account["password"]
                    or remote["shadowsocks_password"] is not None
                    and remote["shadowsocks_password"] == account["shadowsocks_password"]):
                raise ValueError("同步账号与本机账号身份或凭据冲突")
        for entry in entries.values():
            ss = entry.get("shadowsocks", {})
            if (entry["uuid"] in (remote["id"], remote["uuid"], remote["password"])
                    or remote["shadowsocks_password"] is not None
                    and remote["shadowsocks_password"] in (ss.get("server_password"), ss.get("user_password"))):
                raise ValueError("同步账号与本机入口凭据冲突")
    if len(local) + len(managed) > 256:
        raise ValueError("同步后账号数量超过上限")
    if revision == sync["last_revision"]:
        # 本机新增账号可改变数组顺序；同版本重试不能因此重建服务。
        return copy.deepcopy(spec)
    draft = copy.deepcopy(spec)
    if local or managed:
        draft["accounts"] = local + managed
    else:
        draft.pop("accounts", None)
    draft["control_sync"].update(last_revision=revision, last_digest=digest,
                                 managed_accounts=copy.deepcopy(managed))
    return draft


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", required=True)
    parser.add_argument("--desired", required=True)
    args = parser.parse_args()
    try:
        draft = build_draft(read_input(args.spec, 16 * MAX_STATE_BYTES),
                            read_input(args.desired, MAX_STATE_BYTES))
        json.dump(draft, sys.stdout, ensure_ascii=True)
        sys.stdout.write("\n")
    except (OSError, ValueError, KeyError, TypeError, AttributeError, RecursionError):
        # 输入含账号凭据，不把解析异常或原文写入普通输出。
        parser.exit(78, "被控同步输入无效、归属漂移或版本/凭据冲突\n")


if __name__ == "__main__":
    main()
