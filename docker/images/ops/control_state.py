#!/usr/bin/env python3
import argparse
import copy
import hashlib
import json
import sys

from control_api import MAX_STATE_BYTES, exact_keys, validate_state
from control_sync import canonical, read_input

MAX_REVISION = 9007199254740991


def desired_accounts(spec):
    return sorted(({key: value for key, value in account.items() if key != "listeners"}
                   for account in spec.get("accounts", [])), key=lambda account: account["id"])


def state_from_spec(spec):
    control = spec["control"]
    exact_keys(control, "schema_version role node_id listen peer revision last_digest")
    state = {key: copy.deepcopy(value) for key, value in control.items() if key != "last_digest"}
    state["accounts"] = desired_accounts(spec)
    validate_state(state)
    digest = control["last_digest"]
    if digest is not None and (not isinstance(digest, str) or len(digest) != 64
                               or any(c not in "0123456789abcdef" for c in digest)):
        raise ValueError("主控账号摘要不合法")
    if digest is None and control["revision"] != 0:
        raise ValueError("未发布主控版本不合法")
    return state


def account_digest(state):
    return hashlib.sha256(canonical(state["accounts"])).hexdigest()


def published_state(spec):
    state = state_from_spec(spec)
    if spec["control"]["last_digest"] != account_digest(state):
        raise ValueError("主控账号与已发布摘要不一致")
    return state


def build_plan(spec, previous=None, floors=()):
    result = copy.deepcopy(spec)
    state = state_from_spec(result)
    digest = account_digest(state)
    revision = state["revision"]
    versions = {}
    newest = None
    for old_spec in ([previous] if previous is not None and "control" in previous else []) + list(floors):
        old = published_state(old_spec)
        if old["node_id"] != state["node_id"]:
            raise ValueError("不能通过账号事务替换主控身份")
        old_digest = old_spec["control"]["last_digest"]
        if old["revision"] in versions and versions[old["revision"]] != old_digest:
            raise ValueError("同一主控版本的账号内容不一致")
        versions[old["revision"]] = old_digest
        if newest is None or old["revision"] > newest["control"]["revision"]:
            newest = old_spec
    if newest is not None:
        revision = max(revision, newest["control"]["revision"])
        if newest["control"]["last_digest"] != digest:
            revision += 1
    elif result["control"]["last_digest"] not in (None, digest):
        raise ValueError("主控账号变更缺少已发布版本")
    if revision > MAX_REVISION:
        raise ValueError("主控版本序号已耗尽")
    result["control"].update(revision=revision, last_digest=digest)
    state["revision"] = revision
    return {"spec": result, "state": state}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", required=True)
    parser.add_argument("--previous")
    parser.add_argument("--plan-floor", action="append", default=[])
    parser.add_argument("--check-state")
    args = parser.parse_args()
    try:
        spec = read_input(args.spec, 16 * MAX_STATE_BYTES)
        if args.check_state:
            expected = published_state(spec)
            if validate_state(read_input(args.check_state, MAX_STATE_BYTES)) != expected:
                raise ValueError("主控状态与私有规格不一致")
            return
        previous = read_input(args.previous, 16 * MAX_STATE_BYTES) if args.previous else None
        floors = []
        for path in args.plan_floor:
            plan = read_input(path, 16 * MAX_STATE_BYTES)
            exact_keys(plan, "spec state")
            if validate_state(plan["state"]) != published_state(plan["spec"]):
                raise ValueError("候选主控计划与已发布状态不一致")
            floors.append(plan["spec"])
        json.dump(build_plan(spec, previous, floors), sys.stdout, ensure_ascii=True)
        sys.stdout.write("\n")
    except (OSError, ValueError, KeyError, TypeError, AttributeError, RecursionError):
        # 输入含账号凭据，普通日志只报告合同失败。
        parser.exit(78, "主控状态、账号摘要或发布版本不一致\n")


if __name__ == "__main__":
    main()
