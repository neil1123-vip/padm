#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-tun-icmp.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
export PYTHONDONTWRITEBYTECODE=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
fail() { printf 'tun-icmp-fail: %s\n' "$*" >&2; exit 1; }

jq '
  .schema_version = 3 | .core.type = "sing-box" | .core.secondary_type = null |
  .core.protocols |= map(.core = "sing-box" | .listener_id = "entry-main" |
    .address_families = ["ipv4"])
' "${PROJECT_ROOT}/docker/configure.example.json" >"${TEST_ROOT}/plain.json"
jq '.host_integrations = [{type:"tun",profile:"net-transparent",schedules:[],
  firewall_rules:["sing-box-auto-redirect"],devices:["/dev/net/tun"],
  settings:{interface:"padm-tun",address:"198.18.0.1/30"}}]' \
    "${TEST_ROOT}/plain.json" >"${TEST_ROOT}/tun.json"

for kind in plain tun; do
    dockerConfigureSpecValidate "${TEST_ROOT}/${kind}.json"
    dockerGenerateSingBoxConfig "${TEST_ROOT}/${kind}.json" "${TEST_ROOT}/${kind}.config.json"
    dockerGenerateCompose "${TEST_ROOT}/${kind}.json" "${TEST_ROOT}/${kind}.compose.json" "${TEST_ROOT}"
done
jq -e '.route.final == "direct" and
  .route.rules == [{inbound:["tun-in"],network:"icmp",action:"route",outbound:"direct"}] and
  ([.inbounds[] | select(.type == "tun")] | length) == 1 and
  all(.route.rules[]; .action != "bypass" and .method != "reply")' \
    "${TEST_ROOT}/tun.config.json" >/dev/null || fail 'TUN Echo 未明确交给 direct'
jq -e 'all(.route.rules[]?; .network != "icmp")' \
    "${TEST_ROOT}/plain.config.json" >/dev/null || fail '普通代理增加了 ICMP 规则'
jq -e '.services["sing-box"].cap_drop == ["ALL"] and
  .services["sing-box"].cap_add == ["NET_ADMIN","NET_BIND_SERVICE","DAC_OVERRIDE"] and
  all(.services[]; ((.cap_add // []) | index("NET_RAW")) == null)' \
    "${TEST_ROOT}/tun.compose.json" >/dev/null || fail 'ICMP 意外扩大权限'

# 两套入口都拒绝尚未支持的路由组合，不能用生成器试跑冒充已开放 TUN 分流。
for mode in global selective warp ipv6; do
    jq --arg mode "${mode}" '
      .routing = {socks5:{server:"192.0.2.9",port:1080,username:"fixture",password:"fixture"}} |
      if $mode != "global" then .routing.socks5.domains = ["domain:example.com"] else . end |
      if $mode == "warp" then .routing.warp = {
        mode:"global",family:"ipv4",domains:[],
        private_key:"AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=",
        peer_public_key:"ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A=",
        ipv6_address:"2606:4700:110:8a10::2",reserved:[1,2,255]}
      elif $mode == "ipv6" then .routing.ipv6 = {mode:"global",domains:[]}
      else . end
    ' "${TEST_ROOT}/tun.json" >"${TEST_ROOT}/${mode}.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/${mode}.json" >"${TEST_ROOT}/reject.log" 2>&1; then
        fail "TUN 接受不支持的 ${mode} 路由"
    fi
done
python3 - "${PROJECT_ROOT}" "${TEST_ROOT}" <<'PY'
import json
import pathlib
import sys

import jsonschema

project, root = map(pathlib.Path, sys.argv[1:])
validator = jsonschema.Draft202012Validator(
    json.loads((project / "docker/contracts/configure.schema.json").read_text()),
    format_checker=jsonschema.FormatChecker())
errors = list(validator.iter_errors(json.loads((root / "tun.json").read_text())))
assert not errors, "\n".join(f"{list(error.absolute_path)}: {error.message}" for error in errors)
for mode in ("global", "selective", "warp", "ipv6"):
    errors = list(validator.iter_errors(json.loads((root / f"{mode}.json").read_text())))
    assert any("host_integrations" in error.absolute_path for error in errors), mode
PY
printf 'docker-tun-icmp-ok: route=explicit-direct unsupported-routing=rejected net-raw=absent\n'
