#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
PYTHONDONTWRITEBYTECODE=1 python3 - "${PROJECT_ROOT}" <<'PY'
import contextlib
import copy
import importlib.util
import io
import fcntl
import os
import pathlib
import sys
import tempfile

spec = importlib.util.spec_from_file_location(
    "tun_resources", pathlib.Path(sys.argv[1]) / "docker/images/net/tun-resources.py")
tun = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tun)


def refused(action, reason):
    try:
        action()
    except (ValueError, RuntimeError):
        return
    raise AssertionError(f"TUN accepted {reason}")


# 自造小快照保留外来接口、路由和 nft 表；规则形状来自真实 v1.14.2 探针。
before = {
    "netns": "net:[42]", "boot_id": "11111111-1111-4111-8111-111111111111",
    "links": [{"ifindex": 2, "ifname": "eth0"}, {"ifindex": 3, "ifname": "foreign"}],
    "addresses": [{"ifindex": 2, "ifname": "eth0", "family": "inet",
                   "local": "192.0.2.10", "prefixlen": 24, "scope": "global"}],
    "routes4": [{"dst": "198.51.100.0/24", "dev": "foreign", "table": "242"}],
    "routes6": [], "rules4": [{"priority": 32766, "src": "all", "table": "254"}],
    "rules6": [{"priority": 32766, "src": "all", "table": "254"}],
    "nft": {"nftables": [{"table": {"family": "inet", "name": "foreign", "handle": 1}}]},
}
active = copy.deepcopy(before)
active["links"].append({
    "ifindex": 4, "ifname": "padm-tun", "mtu": 65535,
    "linkinfo": {"info_kind": "tun", "info_data": {
        "multi_queue": False, "persist": False, "pi": False, "type": "tun", "vnet_hdr": True}},
})
active["addresses"].append({"ifindex": 4, "ifname": "padm-tun", "family": "inet",
                            "local": "198.18.0.1", "prefixlen": 30, "scope": "global"})
active["routes4"].extend([
    {"dev": "eth0", "dst": "127.0.0.1", "flags": [], "scope": "254",
     "table": "1168658829", "type": "2"},
    {"dev": "padm-tun", "dst": "default", "flags": [], "gateway": "198.18.0.2", "table": "2022"},
    {"dev": "padm-tun", "dst": "198.18.0.0/30", "flags": [], "prefsrc": "198.18.0.1",
     "protocol": "2", "scope": "253"},
    {"dev": "padm-tun", "dst": "198.18.0.1", "flags": [], "prefsrc": "198.18.0.1",
     "protocol": "2", "scope": "254", "table": "255", "type": "2"},
    {"dev": "padm-tun", "dst": "198.18.0.3", "flags": [], "prefsrc": "198.18.0.1",
     "protocol": "2", "scope": "253", "table": "255", "type": "3"},
])
active["rules4"].extend([
    {"priority": 1, "src": "all", "table": "1168658829"},
    {"fwmark": "0x2024", "goto": 9002, "priority": 9000, "src": "all"},
    {"fwmark": "0x2023", "priority": 9001, "src": "all", "table": "2022"},
    {"nop": None, "priority": 9002, "src": "all"},
    {"fwmark": "0x2024", "not": None, "priority": 32768, "src": "all", "table": "2022"},
])
for handle, item in enumerate(tun.expected_nft(33341), start=10):
    item = copy.deepcopy(item)
    next(iter(item.values()))["handle"] = handle
    active["nft"]["nftables"].append(item)

tun.validate_conflicts(before)
owned = tun.owned_resources(before, active)
assert {key: owned[key] for key in ("ifindex", "route_table", "redirect_port")} == {
    "ifindex": 4, "route_table": "1168658829", "redirect_port": 33341}
tun.compare_active(owned, active)
tun.compare_clean(before, before)

# 固定核心可按出站和协议栈关闭 GSO；只允许 vnet_hdr 的两个布尔值。
for vnet_hdr in (False, True):
    tun_active = copy.deepcopy(active)
    tun_active["links"][-1]["linkinfo"]["info_data"]["vnet_hdr"] = vnet_hdr
    tun_owned = tun.owned_resources(before, tun_active)
    tun.compare_active(tun_owned, tun_active)
    tun_drift = copy.deepcopy(tun_active)
    tun_drift["links"][-1]["linkinfo"]["info_data"]["vnet_hdr"] = not vnet_hdr
    refused(lambda: tun.compare_active(tun_owned, tun_drift), "runtime vnet_hdr changed")
for field, value in [
    ("vnet_hdr", 0), ("vnet_hdr", 1), ("vnet_hdr", None), ("vnet_hdr", "false"),
    ("multi_queue", True), ("multi_queue", 0), ("persist", True), ("persist", 0),
    ("pi", True), ("pi", 0), ("type", "tap"), ("unexpected", False),
]:
    tun_drift = copy.deepcopy(active)
    tun_drift["links"][-1]["linkinfo"]["info_data"][field] = value
    refused(lambda: tun.owned_resources(before, tun_drift), f"TUN flag {field}/{value}")
for field in active["links"][-1]["linkinfo"]["info_data"]:
    tun_drift = copy.deepcopy(active)
    del tun_drift["links"][-1]["linkinfo"]["info_data"][field]
    refused(lambda: tun.owned_resources(before, tun_drift), f"missing TUN flag {field}")

# 实机 Docker 网桥的 gc_timer 从 194.47、27.62 递减，不能被认成新增接口。
bridge_before, bridge_active = copy.deepcopy(before), copy.deepcopy(active)
for index, name, timer in [(5, "docker0", 194.47), (6, "br-6bc87e0ba21a", 27.62)]:
    bridge = {"ifindex": index, "ifname": name, "mtu": 1500, "altnames": [],
              "flags": ["BROADCAST", "MULTICAST", "UP"], "linkinfo": {
                  "info_kind": "bridge", "info_data": {
                      "forward_delay": 1500, "hello_time": 200, "max_age": 2000,
                      "ageing_time": 30000, "stp_state": 0, "root_port": 0,
                      "hello_timer": 0.0, "tcn_timer": 0.0, "topology_change_timer": 0.0,
                      "gc_timer": timer, "mcast_membership_interval": 26000}}}
    bridge_before["links"].append(copy.deepcopy(bridge))
    for field in ("hello_timer", "tcn_timer", "topology_change_timer", "gc_timer"):
        bridge["linkinfo"]["info_data"][field] += 0.53
    bridge_active["links"].append(bridge)
bridge_owned = tun.owned_resources(bridge_before, bridge_active)
bridge_later = copy.deepcopy(bridge_active)
bridge_later["links"][-1]["linkinfo"]["info_data"]["gc_timer"] = 25.04
tun.compare_active(bridge_owned, bridge_later)
bridge_clean = copy.deepcopy(bridge_before)
bridge_clean["links"][-1]["linkinfo"]["info_data"]["gc_timer"] = 19.02
tun.compare_clean(bridge_before, bridge_clean)
assert bridge_before["links"][-1]["linkinfo"]["info_data"]["gc_timer"] == 27.62
for field, value in [("ifindex", 7), ("flags", ["BROADCAST"]), ("altnames", ["renamed"]),
                     ("root_port", 2), ("hello_time", 300), ("forward_delay", 1600),
                     ("ageing_time", 31000), ("mcast_membership_interval", 27000)]:
    drift = copy.deepcopy(bridge_active)
    target = drift["links"][-1]
    if field in target:
        target[field] = value
    else:
        target["linkinfo"]["info_data"][field] = value
    refused(lambda: tun.owned_resources(bridge_before, drift), f"bridge bind drift {field}")
    refused(lambda: tun.compare_active(bridge_owned, drift), f"bridge active drift {field}")
    drift_clean = copy.deepcopy(bridge_before)
    drift_clean["links"][-1] = copy.deepcopy(drift["links"][-1])
    refused(lambda: tun.compare_clean(bridge_before, drift_clean), f"bridge cleanup drift {field}")
# 全局规范化仍保留 nft 超时及非网桥同名字段的语义。
assert tun.stable({"timeout": 30, "gc_timer": 2}) != tun.stable({"timeout": 31, "gc_timer": 3})
assert tun.multiset([{"linkinfo": {"info_kind": "dummy", "info_data": {"gc_timer": 1}}}], "links") != (
    tun.multiset([{"linkinfo": {"info_kind": "dummy", "info_data": {"gc_timer": 2}}}], "links"))

# 实机 RA 路由的 expires 会倒数和刷新，但不能掩盖路由消失或身份变化。
ra_before, ra_active = copy.deepcopy(before), copy.deepcopy(active)
ra_route = {"dst": "default", "gateway": "fe80::5054:ff:fe0a:a44e", "dev": "eth0",
            "protocol": "9", "metric": 1024, "flags": [], "expires": 1636, "pref": "medium"}
ra_before["routes6"].append(copy.deepcopy(ra_route))
ra_active["routes6"].append(copy.deepcopy(ra_route))
ra_owned = tun.owned_resources(ra_before, ra_active)
for lifetime in (0, 1610, 1748):
    ra_later = copy.deepcopy(ra_active)
    ra_later["routes6"][-1]["expires"] = lifetime
    tun.owned_resources(ra_before, ra_later)
    tun.compare_active(ra_owned, ra_later)
    ra_clean = copy.deepcopy(ra_before)
    ra_clean["routes6"][-1]["expires"] = lifetime
    tun.compare_clean(ra_before, ra_clean)
assert ra_before["routes6"][-1]["expires"] == 1636
for field, value in [("gateway", "fe80::1"), ("dev", "foreign"), ("protocol", "2"),
                     ("metric", 1025), ("pref", "high"), ("expires", None),
                     ("expires", -1), ("expires", True), ("expires", "1748")]:
    drift = copy.deepcopy(ra_active)
    if value is None:
        del drift["routes6"][-1][field]
    else:
        drift["routes6"][-1][field] = value
    refused(lambda: tun.owned_resources(ra_before, drift), f"RA bind drift {field}/{value}")
    refused(lambda: tun.compare_active(ra_owned, drift), f"RA active drift {field}/{value}")
    drift_clean = copy.deepcopy(ra_before)
    drift_clean["routes6"] = copy.deepcopy(drift["routes6"])
    refused(lambda: tun.compare_clean(ra_before, drift_clean), f"RA cleanup drift {field}/{value}")
refused(lambda: tun.owned_resources(ra_before, active), "RA route disappeared during bind")
refused(lambda: tun.compare_active(ra_owned, active), "RA route disappeared while active")
refused(lambda: tun.compare_clean(ra_before, before), "RA route disappeared before cleanup")
for resource, protocol in [("routes4", "9"), ("routes6", "2")]:
    assert tun.multiset([{"protocol": protocol, "expires": 1}], resource) != (
        tun.multiset([{"protocol": protocol, "expires": 2}], resource))
assert tun.stable({"expires": 1, "timeout": 30}) != tun.stable({"expires": 2, "timeout": 31})

# 固定上游会在已有 DOCKER-USER 链首加两条兼容规则，原链规则仍须原位保留。
docker_before = copy.deepcopy(before)
docker_before["nft"]["nftables"].extend([
    {"table": {"family": "ip", "name": "filter", "handle": 2}},
    {"chain": {"family": "ip", "table": "filter", "name": "DOCKER-USER", "handle": 3}},
    {"rule": {"family": "ip", "table": "filter", "chain": "DOCKER-USER",
              "handle": 4, "expr": [{"return": None}]}},
])
compatibility = [{"rule": {
    "family": "ip", "table": "filter", "chain": "DOCKER-USER", "handle": handle,
    "comment": comment,
    "expr": [{"match": {"op": "==", "left": {"meta": {"key": key}}, "right": "padm-tun"}},
             {"counter": {"packets": 0, "bytes": 0}}, {"accept": None}],
}} for handle, key, comment in [
    (100, "iifname", "!sing-box: Docker compatibility input from tun"),
    (101, "oifname", "!sing-box: Docker compatibility output to tun"),
]]
docker_active = copy.deepcopy(active)
docker_active["nft"]["nftables"] = (
    copy.deepcopy(docker_before["nft"]["nftables"][:3]) + copy.deepcopy(compatibility)
    + copy.deepcopy(docker_before["nft"]["nftables"][3:]) + copy.deepcopy(active["nft"]["nftables"][1:]))
docker_owned = tun.owned_resources(docker_before, docker_active)
tun.compare_active(docker_owned, docker_active)
tun.compare_clean(docker_before, docker_before)


def docker_refused(drift, reason):
    refused(lambda: tun.owned_resources(docker_before, drift), f"Docker bind {reason}")
    refused(lambda: tun.compare_active(docker_owned, drift), f"Docker active {reason}")


for change in ("missing", "duplicate", "reverse", "late"):
    drift = copy.deepcopy(docker_active)
    items = drift["nft"]["nftables"]
    if change == "missing":
        del items[3]
    elif change == "duplicate":
        items.insert(3, copy.deepcopy(items[3]))
    elif change == "reverse":
        items[3], items[4] = items[4], items[3]
    else:
        items[4], items[5] = items[5], items[4]
    docker_refused(drift, change)
for field, value in [
    ("handle", 0), ("handle", True), ("handle", "100"), ("handle", 4), ("handle", 101),
    ("family", "ip6"), ("table", "other"), ("chain", "FORWARD"), ("comment", "forged"),
]:
    drift = copy.deepcopy(docker_active)
    drift["nft"]["nftables"][3]["rule"][field] = value
    docker_refused(drift, f"{field}/{value}")
for change in ("device", "direction", "verdict", "extra"):
    drift = copy.deepcopy(docker_active)
    expressions = drift["nft"]["nftables"][3]["rule"]["expr"]
    if change == "device":
        expressions[0]["match"]["right"] = "other"
    elif change == "direction":
        expressions[0]["match"]["left"]["meta"]["key"] = "oifname"
    elif change == "verdict":
        expressions[-1] = {"drop": None}
    else:
        expressions.append({"return": None})
    docker_refused(drift, change)
docker_counters = copy.deepcopy(docker_active)
for item in docker_counters["nft"]["nftables"][3:5]:
    item["rule"]["expr"][1]["counter"] = {"packets": 9, "bytes": 512}
tun.owned_resources(docker_before, docker_counters)
tun.compare_active(docker_owned, docker_counters)
for residue in (compatibility[:1], compatibility[1:], compatibility):
    dirty = copy.deepcopy(docker_before)
    dirty["nft"]["nftables"][3:3] = copy.deepcopy(residue)
    refused(lambda: tun.compare_clean(docker_before, dirty), "Docker compatibility cleanup residue")
    refused(lambda: tun.validate_conflicts(dirty), "pre-existing Docker compatibility ownership")

dynamic = copy.deepcopy(active)
for item in dynamic["nft"]["nftables"]:
    if "set" in item:
        item["set"]["elem"] = ["192.0.2.10", {"prefix": {"addr": "198.18.0.0", "len": 30}},
                              {"range": ["172.17.0.0", "172.18.255.255"]}]
    for expression in item.get("rule", {}).get("expr", []):
        if "counter" in expression:
            expression["counter"] = {"packets": 7, "bytes": 1024}
tun.owned_resources(before, dynamic)
tun.compare_active(owned, dynamic)
for element in [
    {"range": ["172.18.255.255", "172.17.0.0"]}, {"range": ["::1", "::2"]},
    {"range": ["172.17.0.0", "::1"]}, {"range": ["172.17.0.0"]},
    {"range": [1, 2]}, {"range": "172.17.0.0-172.18.255.255"},
    {"range": ["172.17.0.0", "172.18.255.255"], "extra": True},
]:
    drift = copy.deepcopy(active)
    for item in drift["nft"]["nftables"]:
        if "set" in item:
            item["set"]["elem"] = [element]
    refused(lambda: tun.owned_resources(before, drift), f"invalid IPv4 interval {element}")

for key, index, field, value in [
    ("links", 2, "ifindex", 5), ("addresses", 1, "local", "198.18.0.2"),
    ("routes4", 2, "gateway", "198.18.0.3"), ("rules4", 1, "table", "3662200283"),
]:
    drift = copy.deepcopy(active)
    drift[key][index][field] = value
    refused(lambda: tun.owned_resources(before, drift), f"bind drift {key}/{field}")
    refused(lambda: tun.compare_active(owned, drift), f"active drift {key}/{field}")
for key in ("links", "addresses", "routes4", "rules4", "nft"):
    residual = copy.deepcopy(before)
    if key == "nft":
        residual[key]["nftables"].append(copy.deepcopy(active[key]["nftables"][1]))
    else:
        residual[key].append(copy.deepcopy(active[key][-1]))
    refused(lambda: tun.compare_clean(before, residual), f"cleanup residue {key}")
for kind in ("handle", "expression", "foreign"):
    drift = copy.deepcopy(active)
    if kind == "handle":
        drift["nft"]["nftables"][-1]["rule"]["handle"] += 1000
        refused(lambda: tun.compare_active(owned, drift), "changed nft handle")
    elif kind == "expression":
        drift["nft"]["nftables"][-1]["rule"]["expr"].append({"drop": None})
        refused(lambda: tun.owned_resources(before, drift), "changed nft expression")
    else:
        drift["nft"]["nftables"][0]["table"]["name"] = "replacement"
        refused(lambda: tun.owned_resources(before, drift), "changed foreign nft table")
for mark in ("0x2023", 8227, "0x2000/0xff00"):
    conflict = copy.deepcopy(before)
    conflict["rules4"].append({"priority": 30222, "src": "all", "fwmark": mark, "table": "243"})
    refused(lambda: tun.validate_conflicts(conflict), f"existing mark {mark}")
# NFQUEUE 在同一网络命名空间共享；只拒绝覆盖队列 100 或无法静态证明的选择器。
for number, accepted in [
    (99, True), ({"range": [0, 99]}, True), ({"range": [101, 65535]}, True),
    (100, False), ({"range": [99, 101]}, False), ({"meta": {"key": "mark"}}, False),
]:
    conflict = copy.deepcopy(before)
    conflict["nft"]["nftables"].append({"rule": {
        "family": "inet", "table": "foreign", "chain": "forward",
        "expr": [{"queue": {"num": number}}],
    }})
    if accepted:
        tun.validate_conflicts(conflict)
    else:
        refused(lambda: tun.validate_conflicts(conflict), f"external NFQUEUE {number}")
conflict = copy.deepcopy(before)
conflict["links"].append(copy.deepcopy(active["links"][-1]))
refused(lambda: tun.validate_conflicts(conflict), "existing interface name")

# 使用真实安全状态文件读写，只替换内核快照；错误绑定和残留均保留现场。
cid, started = "b" * 64, "2026-10-14T03:00:00.123456789Z"
with tempfile.TemporaryDirectory(prefix="padm-tun-contract.", dir="/var/lib") as directory:
    tun.ROOT = directory
    tun.STATE_PATH = os.path.join(directory, "tun.state")
    current = copy.deepcopy(before)
    tun.snapshot = lambda: copy.deepcopy(current)
    tun.lock()
    try:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            tun.capture()
        token = output.getvalue().strip()
        assert len(token) == 32 and tun.read_state()["phase"] == "intent"
        state_before = pathlib.Path(tun.STATE_PATH).read_bytes()
        refused(lambda: tun.bind(cid, started, "0" * 32), "foreign capture token")
        assert pathlib.Path(tun.STATE_PATH).read_bytes() == state_before
        current = copy.deepcopy(active)
        tun.bind(cid, started, token)
        assert tun.read_state()["phase"] == "active"
        tun.audit(cid, started)
        for other_cid, other_started in [
            ("c" * 64, started), (cid, "2026-10-14T03:00:01Z"),
        ]:
            refused(lambda: tun.audit(other_cid, other_started), "foreign container binding")
        current["netns"] = "net:[43]"
        refused(lambda: tun.audit(cid, started), "changed network namespace")
        current = copy.deepcopy(active)
        refused(lambda: tun.clean(cid, started), "unclean active resources")
        assert os.path.exists(tun.STATE_PATH)
        current = copy.deepcopy(before)
        tun.clean(cid, started)
        assert not os.path.exists(tun.STATE_PATH)
        with contextlib.redirect_stdout(output):
            tun.capture()
        token = tun.read_state()["token"]
        current = copy.deepcopy(active)
        refused(lambda: tun.abort(token), "abort with kernel residue")
        assert tun.read_state()["phase"] == "intent"
        current = copy.deepcopy(before)
        tun.abort(token)
        assert not os.path.exists(tun.STATE_PATH)
    finally:
        os.close(tun.LOCK)
        tun.LOCK = None
    # 已有归属锁只读打开，确保候选的只读挂载仍能排他审计。
    tun.lock()
    try:
        assert fcntl.fcntl(tun.LOCK, fcntl.F_GETFL) & os.O_ACCMODE == os.O_RDONLY
    finally:
        os.close(tun.LOCK)
        tun.LOCK = None
print("docker-tun-resources-ok")
PY
