#!/usr/bin/env python3
"""sing-box TUN 资源归属与审计。"""

import copy
import fcntl
import ipaddress
import json
import os
import re
import secrets
import stat
import subprocess
import sys
import tempfile
from collections import Counter


ROOT = "/var/lib/padm/net"
STATE_PATH = os.path.join(ROOT, "tun.state")
STATE_KEYS = {"schema_version", "token", "phase", "cid", "started_at",
              "netns", "boot_id", "before", "owned"}
SNAPSHOT_KEYS = {"netns", "boot_id", "links", "addresses", "routes4", "routes6",
                 "rules4", "rules6", "nft"}
CID_RE = re.compile(r"^[0-9a-f]{64}$")
STARTED_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?Z$")
TUN_NAME = "padm-tun"
FIXED_RULE_PRIORITIES = {9000, 9001, 9002, 32768}
FIXED_TABLE = "2022"
LOCK = None
STATE_DATA = None
STATE_IDENTITY = None


def fail(message):
    raise ValueError(message)


def command(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=8)
    if result.returncode or result.stderr.strip():
        raise RuntimeError(result.stderr.strip() or f"command failed: {' '.join(args)}")
    return result.stdout


def json_command(args):
    try:
        return json.loads(command(args))
    except (json.JSONDecodeError, UnicodeError) as error:
        raise ValueError(f"invalid {' '.join(args)} output") from error


def safe_root():
    current = "/"
    for component in ROOT.strip("/").split("/"):
        current = os.path.join(current, component)
        metadata = os.lstat(current)
        if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != 0 or metadata.st_gid != 0:
            fail("unsafe TUN ownership directory")
        if metadata.st_mode & 0o022:
            fail("writable TUN ownership directory")


def file_identity(metadata):
    return (metadata.st_dev, metadata.st_ino, metadata.st_size,
            metadata.st_mtime_ns, metadata.st_ctime_ns)


def private_file(metadata, maximum):
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0
            or metadata.st_gid != 0 or stat.S_IMODE(metadata.st_mode) != 0o600
            or metadata.st_nlink != 1 or metadata.st_size > maximum):
        fail("unsafe TUN ownership file")


def lock():
    global LOCK
    safe_root()
    path = os.path.join(ROOT, ".tun.lock")
    # 候选配置只读挂载在线归属目录；已有锁只读打开也能取得 Linux 排他 flock。
    flags = os.O_RDONLY if os.path.lexists(path) else os.O_RDWR | os.O_CREAT | os.O_EXCL
    descriptor = os.open(path, flags | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    try:
        private_file(os.fstat(descriptor), 0)
        if file_identity(os.fstat(descriptor)) != file_identity(os.lstat(path)):
            fail("TUN ownership lock was replaced")
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BaseException:
        os.close(descriptor)
        raise
    LOCK = descriptor


def state_metadata():
    safe_root()
    if not os.path.lexists(STATE_PATH):
        return None
    metadata = os.lstat(STATE_PATH)
    private_file(metadata, 8 * 1024 * 1024)
    return metadata


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            fail("duplicate TUN state field")
        result[key] = value
    return result


def state_bytes(state):
    return json.dumps(state, sort_keys=True, separators=(",", ":")).encode("utf-8") + b"\n"


def read_state():
    global STATE_DATA, STATE_IDENTITY
    metadata = state_metadata()
    if metadata is None:
        STATE_DATA = STATE_IDENTITY = None
        return None
    descriptor = os.open(STATE_PATH, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    try:
        first = os.fstat(descriptor)
        private_file(first, 8 * 1024 * 1024)
        with os.fdopen(os.dup(descriptor), "rb") as stream:
            data = stream.read(8 * 1024 * 1024 + 1)
        last = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    current = os.lstat(STATE_PATH)
    if file_identity(metadata) != file_identity(first) or (
            file_identity(first) != file_identity(last) or file_identity(last) != file_identity(current)):
        fail("TUN ownership state changed while reading")
    try:
        state = json.loads(data.decode("utf-8"), object_pairs_hook=unique_object)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("invalid TUN ownership state") from error
    if not isinstance(state, dict) or set(state) != STATE_KEYS or data != state_bytes(state):
        fail("unknown TUN ownership state fields")
    if type(state["schema_version"]) is not int or state["schema_version"] != 1 or (
            not isinstance(state["token"], str) or not re.fullmatch(r"[0-9a-f]{32}", state["token"])):
        fail("invalid TUN ownership state identity")
    if state["phase"] not in {"intent", "active"}:
        fail("invalid TUN ownership state phase")
    if state["phase"] == "intent":
        if state["cid"] or state["started_at"] or state["owned"] is not None:
            fail("invalid TUN intent state")
    else:
        validate_binding(state["cid"], state["started_at"])
        if not isinstance(state["owned"], dict) or set(state["owned"]) != {
                "ifindex", "route_table", "redirect_port", "snapshot"}:
            fail("missing TUN owned snapshot")
        validate_snapshot(state["owned"]["snapshot"])
    validate_snapshot(state["before"])
    if (state["netns"] != state["before"]["netns"] or state["boot_id"] != state["before"]["boot_id"]):
        fail("invalid TUN baseline identity")
    STATE_DATA, STATE_IDENTITY = data, file_identity(current)
    return state


def owner_unchanged():
    safe_root()
    if LOCK is not None:
        path = os.path.join(ROOT, ".tun.lock")
        if file_identity(os.fstat(LOCK)) != file_identity(os.lstat(path)):
            fail("TUN ownership lock was replaced")
    metadata = state_metadata()
    if STATE_IDENTITY is None:
        if metadata is not None:
            fail("TUN ownership appeared before commit")
        return
    if metadata is None or file_identity(metadata) != STATE_IDENTITY:
        fail("TUN ownership was replaced")
    descriptor = os.open(STATE_PATH, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    with os.fdopen(descriptor, "rb") as stream:
        if stream.read(8 * 1024 * 1024 + 1) != STATE_DATA:
            fail("TUN ownership contents changed")


def write_state(state):
    global STATE_DATA, STATE_IDENTITY
    owner_unchanged()
    expected = state_bytes(state)
    if len(expected) > 8 * 1024 * 1024:
        fail("TUN ownership snapshot is too large")
    descriptor, stage = tempfile.mkstemp(prefix=".tun-state.", dir=ROOT)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(expected)
            stream.flush()
            os.fsync(stream.fileno())
        owner_unchanged()
        os.replace(stage, STATE_PATH)
        STATE_DATA, STATE_IDENTITY = expected, file_identity(os.lstat(STATE_PATH))
        descriptor = os.open(ROOT, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    finally:
        if os.path.lexists(stage):
            os.unlink(stage)


def validate_binding(cid, started_at):
    if not isinstance(cid, str) or not CID_RE.fullmatch(cid):
        fail("invalid TUN container identity")
    if not isinstance(started_at, str) or not STARTED_RE.fullmatch(started_at):
        fail("invalid TUN start timestamp")


def namespace():
    try:
        with open("/proc/sys/kernel/random/boot_id", encoding="ascii") as stream:
            boot_id = stream.read().strip()
        netns = os.readlink("/proc/self/ns/net")
    except OSError as error:
        raise RuntimeError("cannot read network namespace identity") from error
    if not re.fullmatch(r"[0-9a-f-]{36}", boot_id) or not re.fullmatch(r"net:\[[0-9]+\]", netns):
        fail("invalid network namespace identity")
    return netns, boot_id


def snapshot():
    netns, boot_id = namespace()
    addresses = []
    for link in json_command(["ip", "-j", "address", "show"]):
        for address in link.get("addr_info", []):
            value = {key: item for key, item in address.items()
                     if key not in {"valid_life_time", "preferred_life_time", "tentative"}}
            value.update({"ifindex": link["ifindex"], "ifname": link["ifname"]})
            addresses.append(value)
    return {
        "netns": netns,
        "boot_id": boot_id,
        "links": json_command(["ip", "-j", "-d", "link", "show"]),
        "addresses": addresses,
        "routes4": json_command(["ip", "-j", "-N", "-4", "route", "show", "table", "all"]),
        "routes6": json_command(["ip", "-j", "-N", "-6", "route", "show", "table", "all"]),
        "rules4": json_command(["ip", "-j", "-N", "-4", "rule", "show"]),
        "rules6": json_command(["ip", "-j", "-N", "-6", "rule", "show"]),
        "nft": json_command(["nft", "-j", "-a", "list", "ruleset"]),
    }


def validate_snapshot(value):
    if not isinstance(value, dict) or set(value) != SNAPSHOT_KEYS:
        fail("unknown TUN snapshot fields")
    if not isinstance(value["netns"], str) or not re.fullmatch(r"net:\[[0-9]+\]", value["netns"]):
        fail("invalid TUN network namespace")
    if not isinstance(value["boot_id"], str) or not re.fullmatch(r"[0-9a-f-]{36}", value["boot_id"]):
        fail("invalid TUN boot identity")
    for key in ("links", "addresses", "routes4", "routes6", "rules4", "rules6"):
        if not isinstance(value[key], list) or any(not isinstance(item, dict) for item in value[key]):
            fail("invalid TUN resource listing")
    if not isinstance(value["nft"], dict) or set(value["nft"]) != {"nftables"} or (
            not isinstance(value["nft"]["nftables"], list)):
        fail("invalid TUN nft listing")


def stable(value, handles=True):
    if isinstance(value, dict):
        result = {}
        for key, item in sorted(value.items()):
            if key in {"stats", "stats64"} or key == "handle" and not handles:
                continue
            if key == "counter" and isinstance(item, dict) and set(item) == {"packets", "bytes"}:
                result[key] = {"packets": 0, "bytes": 0}
            else:
                result[key] = stable(item, handles)
        return result
    if isinstance(value, list):
        return [stable(item, handles) for item in value]
    return value


def item_key(value):
    return json.dumps(stable(value), sort_keys=True, separators=(",", ":"))


def multiset(values, resource=None):
    if resource == "links":
        values = copy.deepcopy(values)
        for link in values:
            info = link.get("linkinfo", {})
            if info.get("info_kind") == "bridge":
                # 网桥倒计时会随观测时间变化；接口身份、拓扑和配置仍须精确一致。
                data = info.get("info_data", {})
                for timer in ("hello_timer", "tcn_timer", "topology_change_timer", "gc_timer"):
                    data.pop(timer, None)
    elif resource == "routes6":
        values = copy.deepcopy(values)
        for route in values:
            if route.get("protocol") == "9" and "expires" in route:
                if type(route["expires"]) is not int or route["expires"] < 0:
                    fail("invalid IPv6 RA route lifetime")
                # RA 自动刷新剩余寿命；到期字段和完整路由身份仍须保留。
                route["expires"] = 0
    return Counter(item_key(value) for value in values)


def without(values, predicate):
    return [value for value in values if not predicate(value)]


def table_value(value):
    return str(value)


def rule_owned(rule):
    priority = rule.get("priority")
    if priority in FIXED_RULE_PRIORITIES or str(priority) in {str(item) for item in FIXED_RULE_PRIORITIES}:
        return True
    return priority == 1 or priority == "1" or table_value(rule.get("table")) == FIXED_TABLE


def nft_item_owned(item):
    table = item.get("table", {})
    if table.get("family") == "inet" and table.get("name") == "sing-box":
        return True
    for key in ("chain", "set", "rule"):
        value = item.get(key, {})
        if value.get("family") == "inet" and value.get("table") == "sing-box":
            return True
    return False


def nft_without_dynamic(value):
    value = copy.deepcopy(value)
    for item in value.get("nftables", []):
        if nft_item_owned(item) and "set" in item and item["set"].get("name") == "inet4_local_address_set":
            item["set"].pop("elem", None)
    return stable(value)


def validate_conflicts(base):
    validate_snapshot(base)
    if any(link.get("ifname") == TUN_NAME for link in base["links"]):
        fail("TUN interface name is already in use")
    for item in base["nft"].get("nftables", []):
        rule = item.get("rule", {})
        if (rule.get("family") == "ip" and rule.get("table") == "filter"
                and rule.get("chain") == "DOCKER-USER"
                and isinstance(rule.get("comment"), str)
                and rule["comment"].startswith("!sing-box: Docker compatibility ")):
            fail("TUN Docker compatibility rule is already in use")
        table = item.get("table", {})
        if table.get("family") == "inet" and table.get("name") == "sing-box":
            fail("sing-box nft table is already in use")
    for rules in (base["rules4"], base["rules6"]):
        for rule in rules:
            if rule_owned(rule):
                fail("TUN policy rule is already in use")
    for routes in (base["routes4"], base["routes6"]):
        if any(table_value(route.get("table", "254")) == FIXED_TABLE for route in routes):
            fail("TUN route table is already in use")
    for rules in (base["rules4"], base["rules6"]):
        for rule in rules:
            if "fwmark" not in rule:
                continue
            raw = str(rule["fwmark"]).split("/")
            mark = int(raw[0], 0) if raw[0].startswith("0x") else int(raw[0])
            mask = int(raw[1], 0) if len(raw) == 2 else int(str(rule.get("fwmask", "0xffffffff")), 0)
            if any((own & mask) == (mark & mask) for own in (8227, 8228, 8229)):
                fail("TUN mark intersects an existing policy rule")
    for item in base["nft"]["nftables"]:
        for expression in item.get("rule", {}).get("expr", []):
            if "queue" in expression:
                # NFQUEUE 按 network namespace 共享，外来规则不能交给本核心的固定消费者。
                queue = expression["queue"]
                if not isinstance(queue, dict) or not {"num"} <= set(queue) <= {"num", "flags"}:
                    fail("unverified external NFQUEUE selector")
                number = queue["num"]
                if type(number) is int:
                    first = last = number
                elif isinstance(number, dict) and set(number) == {"range"} and (
                        isinstance(number["range"], list) and len(number["range"]) == 2):
                    first, last = number["range"]
                else:
                    fail("unverified external NFQUEUE selector")
                if (type(first) is not int or type(last) is not int or not 0 <= first <= last <= 65535
                        or not isinstance(queue.get("flags", []), list)
                        or any(flag not in {"bypass", "fanout"} for flag in queue.get("flags", []))):
                    fail("invalid external NFQUEUE selector")
                if first <= 100 <= last:
                    fail("external NFQUEUE selector intersects TUN queue 100")
            selected = expression.get("match", {})
            target = expression.get("mangle", {})
            if '"key": "mark"' in json.dumps(selected.get("left", {})) or (
                    '"key": "mark"' in json.dumps(target.get("key", {}))):
                mark = selected.get("right", target.get("value"))
                if type(mark) is not int or mark in {8227, 8228, 8229}:
                    fail("nft mark layout conflicts with TUN")


def added(before, after, key):
    return [json.loads(value) for value in (multiset(after[key], key) - multiset(before[key], key)).elements()]


def removed(before, after, key):
    return [json.loads(value) for value in (multiset(before[key], key) - multiset(after[key], key)).elements()]


def expected_nft(redirect_port):
    meta = lambda key: {"meta": {"key": key}}
    ct = lambda key: {"ct": {"key": key}}
    payload = lambda protocol, field: {"payload": {"protocol": protocol, "field": field}}
    match = lambda left, right, op="==": {"match": {"left": left, "op": op, "right": right}}
    mangle = lambda key, value: {"mangle": {"key": key, "value": value}}
    counter = {"counter": {"packets": 0, "bytes": 0}}
    ret = {"return": None}
    counted_return = lambda *expr: [*expr, counter, ret]
    output, inbound = 8228, 8227
    local = match(payload("ip", "daddr"), "@inet4_local_address_set")
    tun = match(meta("iifname"), TUN_NAME)
    ipv6 = match(meta("nfproto"), "ipv6")
    ipv6_reject = [ipv6, counter, {"reject": {"type": "icmpv6", "expr": "no-route"}}]
    marked_return = lambda left, value: counted_return(match(left, value))
    prematch = [[match(ct("direction"), "reply"), ret]]
    for mark in (output, inbound):
        prematch.extend([
            counted_return(match(meta("mark"), mark), mangle(ct("mark"), meta("mark"))),
            counted_return(match(ct("mark"), mark), mangle(meta("mark"), ct("mark"))),
        ])
    prematch.extend([
        [ipv6, ret],
        [match(meta("l4proto"), {"set": ["icmp", "tcp", "udp", "ipv6-icmp"]}, "!="), ret],
        [match({"&": [payload("tcp", "flags"), {"|": ["syn", "ack"]}]}, "syn", "!="), ret],
        [match(meta("l4proto"), "tcp"), match(meta("mark"), 8229), counter,
         {"reject": {"type": "tcp reset"}}],
    ])
    queue = lambda *expr: [*expr, counter, {"queue": {"num": 100, "flags": ["bypass"]}}]
    queued = [
        queue(match(meta("l4proto"), "tcp")),
        queue(match(meta("l4proto"), "udp")),
        queue(match(payload("icmp", "type"), "echo-request"), match(payload("icmp", "code"), 0)),
        queue(match(payload("icmpv6", "type"), "echo-request"), match(payload("icmpv6", "code"), 0)),
    ]
    redirect = [
        match(meta("nfproto"), "ipv4"), match(meta("l4proto"), "tcp"), counter,
        {"redirect": {"port": redirect_port}}, ret,
    ]
    mark_inbound = [
        mangle(meta("mark"), inbound), mangle(ct("mark"), meta("mark")), counter, ret,
    ]
    mptcp = [match({"tcp option": {"name": "mptcp"}}, True), counter, {"drop": None}]
    expressions = {
        "prerouting_prematch": [[tun, ret], *prematch, counted_return(tun),
                                counted_return(local), *queued],
        "output_prematch": [*prematch, counted_return(local), *queued],
        "output": [marked_return(meta("mark"), output), marked_return(ct("mark"), output),
                   marked_return(ct("mark"), inbound), counted_return(local), mptcp, ipv6_reject, redirect],
        "output_udp_icmp": [
            [match(meta("l4proto"), {"set": ["icmp", "udp", "ipv6-icmp"]}, "!="), ret],
            marked_return(meta("mark"), output), marked_return(ct("mark"), output),
            counted_return(local), ipv6_reject, mark_inbound,
        ],
        "input": [[match(payload("tcp", "dport"), redirect_port), match(ct("status"), "dnat", "!"),
                   counter, {"reject": {"type": "tcp reset"}}]],
        "prerouting": [marked_return(ct("mark"), output), marked_return(ct("mark"), inbound),
                       counted_return(tun), counted_return(local), mptcp, ipv6_reject, redirect, mark_inbound],
        "prerouting_udp_icmp": [
            [match(meta("l4proto"), {"set": ["icmp", "udp", "ipv6-icmp"]}, "!="), ret],
            counted_return(tun),
            [match(meta("iifname"), TUN_NAME, "!="), match(ct("mark"), inbound),
             mangle(meta("mark"), ct("mark")), counter],
            [match(ct("mark"), inbound, "!="), mangle(meta("mark"), output),
             mangle(ct("mark"), meta("mark")), counter],
        ],
    }
    definitions = [
        ("prerouting_prematch", "filter", "prerouting", -101),
        ("output_prematch", "route", "output", -149),
        ("output", "nat", "output", -148),
        ("output_udp_icmp", "route", "output", -148),
        ("input", "filter", "input", 0),
        ("prerouting", "nat", "prerouting", -98),
        ("prerouting_udp_icmp", "filter", "prerouting", -97),
    ]
    base = {"family": "inet", "table": "sing-box"}
    items = [{"table": {"family": "inet", "name": "sing-box"}}]
    items.extend({"chain": {**base, "name": name, "type": kind, "hook": hook,
                            "prio": priority, "policy": "accept"}}
                 for name, kind, hook, priority in definitions)
    items.append({"set": {**base, "name": "inet4_local_address_set",
                           "type": "ipv4_addr", "flags": ["interval"]}})
    items.extend({"rule": {**base, "chain": name, "expr": expression}}
                 for name, _, _, _ in definitions for expression in expressions[name])
    return items


def expected_docker_nft():
    return [{"rule": {
        "family": "ip", "table": "filter", "chain": "DOCKER-USER",
        "expr": [{"match": {"op": "==", "left": {"meta": {"key": key}}, "right": TUN_NAME}},
                 {"counter": {"packets": 0, "bytes": 0}}, {"accept": None}],
        "comment": f"!sing-box: Docker compatibility {direction}",
    }} for key, direction in [("iifname", "input from tun"), ("oifname", "output to tun")]]


def validate_nft(before, after):
    old = [item for item in before["nft"]["nftables"] if not nft_item_owned(item)]
    external = [item for item in after["nft"]["nftables"] if not nft_item_owned(item)]
    if any(item.get("chain", {}).get("family") == "ip"
           and item["chain"].get("table") == "filter" and item["chain"].get("name") == "DOCKER-USER"
           for item in old):
        indices = [index for index, item in enumerate(external)
                   if item.get("rule", {}).get("family") == "ip"
                   and item["rule"].get("table") == "filter" and item["rule"].get("chain") == "DOCKER-USER"]
        compatibility = [external[index] for index in indices[:2]]
        handles = [item["rule"].get("handle") for item in compatibility]
        baseline_handles = {item["rule"].get("handle") for item in old
                            if item.get("rule", {}).get("family") == "ip"
                            and item["rule"].get("table") == "filter"}
        if len(compatibility) != 2 or any(type(handle) is not int or handle < 1 for handle in handles) or (
                len(set(handles)) != 2 or any(handle in baseline_handles for handle in handles)):
            fail("unverified TUN Docker compatibility handles")
        normalized = copy.deepcopy(compatibility)
        for item in normalized:
            item["rule"].pop("handle")
        # 固定上游在已有链首插入 input/output；其余外部规则、位置与句柄完整保留。
        if stable(normalized) != expected_docker_nft():
            fail("unverified TUN Docker compatibility rules")
        external = [item for index, item in enumerate(external) if index not in indices[:2]]
    if stable(old) != stable(external):
        fail("TUN changed external nft resources")
    items = [item for item in after["nft"]["nftables"] if nft_item_owned(item)]
    redirect_ports = [expression["redirect"].get("port") for item in items
                      for expression in item.get("rule", {}).get("expr", []) if "redirect" in expression]
    if len(redirect_ports) != 2 or len(set(redirect_ports)) != 1 or (
            type(redirect_ports[0]) is not int or not 1 <= redirect_ports[0] <= 65535):
        fail("unverified TUN redirect listener")
    seen_handles = set()
    for item in items:
        if len(item) != 1:
            fail("unverified TUN nft resource")
        kind, value = next(iter(item.items()))
        handle = value.get("handle")
        if type(handle) is not int or handle < 1 or (kind, handle) in seen_handles:
            fail("unverified TUN nft handle")
        seen_handles.add((kind, handle))
        if kind == "set":
            for element in value.get("elem", []):
                if isinstance(element, dict) and set(element) == {"range"}:
                    endpoints = element["range"]
                    if (not isinstance(endpoints, list) or len(endpoints) != 2
                            or any(not isinstance(endpoint, str) for endpoint in endpoints)):
                        fail("invalid TUN local address range")
                    first, last = map(ipaddress.ip_address, endpoints)
                    # nft 可把相邻网段合并为 interval；只接受有序的 IPv4 闭区间。
                    if first.version != 4 or last.version != 4 or first > last:
                        fail("unexpected TUN local address range")
                    continue
                prefix = element.get("prefix") if isinstance(element, dict) else None
                address = f"{prefix['addr']}/{prefix['len']}" if isinstance(prefix, dict) else element
                if ipaddress.ip_network(address, strict=False).version != 4:
                    fail("unexpected TUN local address element")
    normalized = copy.deepcopy(items)
    for item in normalized:
        if "set" in item:
            item["set"].pop("elem", None)
    if stable(normalized, handles=False) != stable(expected_nft(redirect_ports[0]), handles=False):
        fail("sing-box nft resource closure is unverified")
    return redirect_ports[0]


def tun_linklocal(item):
    if item.get("dev", item.get("ifname")) != TUN_NAME:
        return False
    destination = item.get("local", item.get("dst", ""))
    try:
        return ipaddress.ip_interface(destination).ip.is_link_local
    except ValueError:
        return False


def owned_resources(before, after):
    validate_snapshot(before)
    validate_snapshot(after)
    validate_conflicts(before)
    if after["netns"] != before["netns"] or after["boot_id"] != before["boot_id"]:
        fail("TUN network namespace changed during bind")
    if len(added(before, after, "links")) != 1:
        fail("TUN bind changed an unexpected interface set")
    tun_links = [link for link in added(before, after, "links") if link.get("ifname") == TUN_NAME]
    tun_data = tun_links[0].get("linkinfo", {}).get("info_data") if len(tun_links) == 1 else None
    if len(tun_links) != 1 or (
            tun_links[0].get("linkinfo", {}).get("info_kind") != "tun"
            or not isinstance(tun_data, dict)
            or any(type(tun_data.get(key)) is not bool for key in ("multi_queue", "persist", "pi", "vnet_hdr"))
            # v1.14.2 按出站和协议栈选择可选 GSO；该布尔位仍写入完整快照审计。
            or tun_data != {
                "multi_queue": False, "persist": False, "pi": False, "type": "tun",
                "vnet_hdr": tun_data.get("vnet_hdr")}
            or tun_links[0].get("mtu") != 65535
            or type(tun_links[0].get("ifindex")) is not int or tun_links[0]["ifindex"] < 1):
        fail("TUN interface identity is not verified")
    if removed(before, after, "links"):
        fail("TUN bind removed an existing interface")

    new_addresses = added(before, after, "addresses")
    if removed(before, after, "addresses"):
        fail("TUN bind removed an existing address")
    for address in new_addresses:
        if address.get("ifname") != TUN_NAME or address.get("ifindex") != tun_links[0]["ifindex"] or (
                address.get("dadfailed") or not (tun_linklocal(address) or
                address.get("local") == "198.18.0.1" and address.get("prefixlen") == 30)):
            fail("TUN bind added an unexpected address")
    if sum(address.get("local") == "198.18.0.1" and address.get("prefixlen") == 30
           for address in new_addresses) != 1:
        fail("TUN IPv4 address is missing")

    for key in ("rules4", "rules6"):
        if removed(before, after, key):
            fail("TUN bind removed an existing rule")
    rules4 = added(before, after, "rules4")
    dynamic = [rule for rule in rules4 if rule.get("priority") == 1]
    if len(dynamic) != 1 or set(dynamic[0]) != {"priority", "src", "table"} or dynamic[0]["src"] != "all":
        fail("unverified TUN dynamic policy rule")
    dynamic_table = dynamic[0]["table"]
    if not isinstance(dynamic_table, str) or not dynamic_table.isdecimal() or (
            not 256 <= int(dynamic_table) <= 0xffffffff or dynamic_table == FIXED_TABLE):
        fail("invalid TUN dynamic route table")
    expected_rules = [
        {"priority": 1, "src": "all", "table": dynamic_table},
        {"fwmark": "0x2024", "goto": 9002, "priority": 9000, "src": "all"},
        {"fwmark": "0x2023", "priority": 9001, "src": "all", "table": FIXED_TABLE},
        {"nop": None, "priority": 9002, "src": "all"},
        {"fwmark": "0x2024", "not": None, "priority": 32768, "src": "all", "table": FIXED_TABLE},
    ]
    if multiset(rules4) != multiset(expected_rules) or added(before, after, "rules6"):
        fail("TUN policy rule closure is unverified")
    if any(table_value(route.get("table", "254")) == dynamic_table
           for key in ("routes4", "routes6") for route in before[key]):
        fail("TUN dynamic route table collides with baseline")
    for key in ("routes4", "routes6"):
        if removed(before, after, key):
            fail("TUN bind removed an existing route")
    routes4 = added(before, after, "routes4")
    dynamic_routes = [route for route in routes4 if table_value(route.get("table")) == dynamic_table]
    devices = {link["ifname"] for link in before["links"]}
    for route in dynamic_routes:
        if route != {"dev": route.get("dev"), "dst": "127.0.0.1", "flags": [],
                     "scope": "254", "table": dynamic_table, "type": "2"} or route["dev"] not in devices:
            fail("unverified TUN dynamic local route")
    expected_routes = [
        {"dev": TUN_NAME, "dst": "default", "flags": [], "gateway": "198.18.0.2", "table": FIXED_TABLE},
        {"dev": TUN_NAME, "dst": "198.18.0.0/30", "flags": [], "prefsrc": "198.18.0.1",
         "protocol": "2", "scope": "253"},
        {"dev": TUN_NAME, "dst": "198.18.0.1", "flags": [], "prefsrc": "198.18.0.1",
         "protocol": "2", "scope": "254", "table": "255", "type": "2"},
        {"dev": TUN_NAME, "dst": "198.18.0.3", "flags": [], "prefsrc": "198.18.0.1",
         "protocol": "2", "scope": "253", "table": "255", "type": "3"},
    ]
    if multiset(routes4) != multiset([*expected_routes, *dynamic_routes]):
        fail("TUN IPv4 route closure is unverified")
    for route in added(before, after, "routes6"):
        common = {"dev": TUN_NAME, "flags": [], "pref": "medium", "protocol": "2"}
        if route not in [
            {**common, "dst": "fe80::/64", "metric": 256},
            {**common, "dst": "ff00::/8", "metric": 256, "table": "255", "type": "5"},
            {**common, "dst": route.get("dst"), "metric": 0, "table": "255", "type": "2"},
        ] or not (route["dst"] in {"fe80::/64", "ff00::/8"} or tun_linklocal(route)):
            fail("unverified TUN IPv6 local route")
    port = validate_nft(before, after)
    return {"ifindex": tun_links[0]["ifindex"], "route_table": dynamic_table,
            "redirect_port": port, "snapshot": after}


def compare_active(expected, current):
    after = expected["snapshot"]
    if current["netns"] != after["netns"] or current["boot_id"] != after["boot_id"]:
        fail("TUN network namespace changed")
    for key in ("links", "addresses", "routes4", "routes6", "rules4", "rules6"):
        original, observed = after[key], current[key]
        # 仅允许新接口的 IPv6 DAD 和已绑定随机表的 local 地址路由更新。
        if key in {"addresses", "routes6"}:
            original = without(original, tun_linklocal)
            observed = without(observed, tun_linklocal)
        elif key == "routes4":
            original = without(original, lambda item: item.get("table") == expected["route_table"])
            observed = without(observed, lambda item: item.get("table") == expected["route_table"])
        if multiset(original, key) != multiset(observed, key):
            fail(f"TUN {key} drifted")
    if nft_without_dynamic(current["nft"]) != nft_without_dynamic(after["nft"]):
        fail("TUN nft resources drifted")


def compare_clean(before, current):
    if current["netns"] != before["netns"] or current["boot_id"] != before["boot_id"]:
        fail("TUN network namespace changed before cleanup")
    for key in ("links", "addresses", "routes4", "routes6", "rules4", "rules6"):
        if multiset(current[key], key) != multiset(before[key], key):
            fail(f"TUN {key} was not fully cleaned")
    if nft_without_dynamic(current["nft"]) != nft_without_dynamic(before["nft"]):
        fail("TUN nft resources were not fully cleaned")


def load_active(cid=None, started_at=None):
    state = read_state()
    if state is None or state["phase"] != "active":
        fail("active TUN ownership is unavailable")
    if cid is not None or started_at is not None:
        validate_binding(cid, started_at)
        if state["cid"] != cid or state["started_at"] != started_at:
            fail("TUN ownership binding does not match")
    return state


def preflight():
    state = read_state()
    current = snapshot()
    if state is None:
        validate_conflicts(current)
        return
    if state["phase"] != "active":
        fail("unfinished TUN intent requires abort")
    owned_resources(state["before"], current)
    compare_active(state["owned"], current)


def capture():
    if read_state() is not None:
        fail("TUN ownership state already exists")
    current = snapshot()
    validate_conflicts(current)
    token = secrets.token_hex(16)
    write_state({
        "schema_version": 1, "token": token, "phase": "intent",
        "cid": "", "started_at": "", "netns": current["netns"],
        "boot_id": current["boot_id"], "before": current, "owned": None,
    })
    print(token)


def bind(cid, started_at, token):
    validate_binding(cid, started_at)
    state = read_state()
    if state is None or state["phase"] != "intent" or state["token"] != token:
        fail("TUN intent does not match bind")
    current = snapshot()
    owned = owned_resources(state["before"], current)
    state.update({"phase": "active", "cid": cid, "started_at": started_at, "owned": owned})
    write_state(state)


def audit(cid, started_at):
    state = load_active(cid, started_at)
    current = snapshot()
    owned = owned_resources(state["before"], current)
    if any(owned[key] != state["owned"][key] for key in ("ifindex", "route_table", "redirect_port")):
        fail("TUN owned resource identities changed")
    compare_active(state["owned"], current)
    owner_unchanged()


def clean(cid, started_at):
    state = load_active(cid, started_at)
    compare_clean(state["before"], snapshot())
    owner_unchanged()
    os.unlink(STATE_PATH)


def abort(token):
    state = read_state()
    if state is None or state["phase"] != "intent" or state["token"] != token:
        fail("TUN intent does not match abort")
    compare_clean(state["before"], snapshot())
    owner_unchanged()
    os.unlink(STATE_PATH)


def usage():
    raise ValueError("usage: tun-resources preflight|capture|bind|audit|clean|abort")


def main(argv):
    global LOCK
    if not argv:
        usage()
    operation = argv[0]
    lock()
    try:
        if operation == "preflight" and len(argv) == 1:
            preflight()
        elif operation == "capture" and len(argv) == 1:
            capture()
        elif operation == "bind" and len(argv) == 4:
            bind(argv[1], argv[2], argv[3])
        elif operation == "audit" and len(argv) == 3:
            audit(argv[1], argv[2])
        elif operation == "clean" and len(argv) == 3:
            clean(argv[1], argv[2])
        elif operation == "abort" and len(argv) == 2:
            abort(argv[1])
        else:
            usage()
    finally:
        os.close(LOCK)
        LOCK = None


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (KeyError, TypeError, OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f"padm-net: TUN resources refused: {error}", file=sys.stderr)
        sys.exit(1)
