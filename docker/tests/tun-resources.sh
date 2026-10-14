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

dynamic = copy.deepcopy(active)
for item in dynamic["nft"]["nftables"]:
    if "set" in item:
        item["set"]["elem"] = ["192.0.2.10", {"prefix": {"addr": "198.18.0.0", "len": 30}}]
    for expression in item.get("rule", {}).get("expr", []):
        if "counter" in expression:
            expression["counter"] = {"packets": 7, "bytes": 1024}
tun.owned_resources(before, dynamic)
tun.compare_active(owned, dynamic)

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
