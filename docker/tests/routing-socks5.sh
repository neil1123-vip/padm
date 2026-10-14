#!/usr/bin/env bash
set -Eeuo pipefail

ROUTING_BRANCH=${PADM_DOCKER_ROUTING_BRANCH:-}
case "${PADM_DOCKER_ROUTING_SCOPE:-}:${ROUTING_BRANCH}" in
*:) ;;
core-network-lifecycle:warp|core-network-lifecycle:ipv6|\
core-policy-lifecycle:region|core-policy-lifecycle:bt|core-policy-lifecycle:socks5|\
domains-dns-hosts:dns|domains-dns-hosts:hosts) ;;
*)
    printf 'docker-routing-socks5-regression-fail: invalid scope/branch: %s/%s\n' \
        "${PADM_DOCKER_ROUTING_SCOPE:-}" "${ROUTING_BRANCH}" >&2
    exit 1
    ;;
esac
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-routing-socks5.XXXXXX")
PRIVATE_ROOT=
trap 'rm -rf -- "${TEST_ROOT}"; [[ -z "${PRIVATE_ROOT}" ]] || rm -rf -- "${PRIVATE_ROOT}"' EXIT
trap 'printf "docker-routing-socks5-regression-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || {
    printf 'docker-routing-socks5-regression-fail: Linux root is required\n' >&2
    exit 1
}
for tool in jq python3 stat chmod chown find sort sha256sum mkfifo timeout; do
    command -v "${tool}" >/dev/null || exit 1
done
PRIVATE_ROOT=$(mktemp -d /root/.padm-routing-socks5.XXXXXX)
chmod 0700 "${PRIVATE_ROOT}"
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_SKIP_CHOWN=0
export PADM_DOCKER_HEALTH_TIMEOUT=1 PADM_DOCKER_LOCK_TIMEOUT=1 PYTHONDONTWRITEBYTECODE=1
root=${PADM_DOCKER_INSTALL_DIR}
UUID=11111111-1111-4111-8111-111111111111
DOMAIN=routing.example.com
USERNAME=routing-user-secret-marker
PASSWORD=routing-password-secret-marker
MODE=ok
LOG=${TEST_ROOT}/command.log
COMPOSE_LOG=${TEST_ROOT}/compose.log
INPUT=${PRIVATE_ROOT}/socks5.json
DOMAINS_INPUT=${PRIVATE_ROOT}/socks5-domains.json
DOMAINS='["full:exact.example.com","full:other.example.com","domain:example.net","keyword:video","geosite:cn","geosite:category-ads-all"]'
DOMAINS_CSV=' Full:Exact.Example.Com , FULL:Other.Example.Com , Example.NET , KEYWORD:Video , geosite:CN , geosite:category-ads-all , example.net , Full:Exact.Example.Com '
DNS_INPUT=${PRIVATE_ROOT}/dns.json
HOSTS_INPUT=${PRIVATE_ROOT}/hosts.json
DNS='{"server":"203.0.113.53","port":5353,"domains":["full:dns.example.com","domain:dns.example.net","keyword:dns-video","geosite:cn"]}'
DNS_CSV=' Full:DNS.Example.Com , DNS.Example.NET , KEYWORD:DNS-Video , GEOSITE:CN , dns.example.net , geosite:cn '
HOSTS='{"exact.example.com":"203.0.113.10","ipv6.example.com":"2001:db8::10"}'
DIRECT_INPUT=${PRIVATE_ROOT}/direct.json
BLOCK_INPUT=${PRIVATE_ROOT}/block.json
BLOCK_IPS_INPUT=${PRIVATE_ROOT}/block-ips.json
IP_DELTA_INPUT=${PRIVATE_ROOT}/block-ips-delta.json
BLOCK_IPS='{"ips":["192.0.2.10","2001:db8::10","198.51.100.0/24","2001:db8::/64","geoip:cn"]}'
REGION_ALLOW='["full:exact.example.com","domain:apple.com","full:custom-region.example.com"]'
REGION_DEFAULTS='["domain:dl.google.com","domain:apple.com","domain:bing.com","domain:microsoft.com","domain:gstatic.com","domain:xn--ngstr-lra8j.com","domain:googleapis.com","domain:googleapis.cn"]'
IPV6_DOMAINS='["full:exact.example.com","domain:example.net","keyword:video","geosite:cn"]'
WARP_INPUT=${PRIVATE_ROOT}/warp.json
WARP_PRIVATE='AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA='
WARP_PUBLIC='ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A='

fail() {
    [[ ! -f "${LOG}" ]] || sed 's/^/  /' "${LOG}" >&2
    printf 'docker-routing-socks5-regression-fail: %s\n' "$*" >&2
    exit 1
}
reject() { if "$@" >"${LOG}" 2>&1; then fail "应拒绝: $*"; fi; }
# 仅核心、宿主和发布使用桩；路由生成、权限、锁与恢复走生产代码。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
docker() {
    if [[ "$*" == "ps -aq --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=net-fail2ban --filter label=com.docker.compose.oneoff=False" ||
        "$*" == "ps -aq --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=net-fail2ban-control --filter label=com.docker.compose.oneoff=False" ||
        "$*" == "ps -aq --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=net-fail2ban-ssh --filter label=com.docker.compose.oneoff=False" ||
        "$*" == "ps -aq --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=net-transparent --filter label=com.docker.compose.oneoff=False" ]]; then
        return 0
    fi
    # 合同夹具没有 daemon；真实辅助网络归属和删除由 bridge 专项验收。
    if [[ "$#" -eq 5 && "$1" == network && "$2" == ls && "$3" == -q &&
        "$4" == --filter && "$5" == 'name=^padm-docker-ipv6$' ]]; then
        return 0
    fi
    command docker "$@"
}
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { :; }
dockerLockInstalledDeployment() { dockerAcquireDeploymentLock; }
dockerConfigureReleasePrepare() { :; }
dockerConfigureReleaseValidate() { :; }
dockerRealityTargetsValidate() { :; }
dockerConfigurePortsAvailable() { :; }
dockerTrafficRuntimeCheck() { :; }
dockerTrafficBeforeChange() { :; }
dockerTrafficScheduleInstall() { :; }
dockerRenewalScheduleInstall() { :; }
dockerGeoScheduleInstall() { :; }
dockerTlsValidateCandidate() { :; }
dockerManifestImageReference() {
    jq -er --arg image "$1" '.images[$image]' "${TEST_ROOT}/base.json"
}
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
mkdir -p "${TEST_ROOT}/bundle/docker/contracts"
printf '%s\n' "$(printf 'a%.0s' {1..40})" >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
cp -- "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
cp -- "${PROJECT_ROOT}/docker/contracts/features.json" \
    "${TEST_ROOT}/bundle/docker/contracts/features.json"
dockerCandidateCompose() {
    local candidate=$1
    shift
    [[ -d "${candidate}" && -e "${root}/locks/deployment.lock" ]] ||
        fail '候选校验没有持有部署锁'
    printf 'candidate:%s\n' "$*" >>"${COMPOSE_LOG}"
}
dockerComposeRun() {
    [[ -e "${root}/locks/deployment.lock" ]] || fail '部署未持有部署锁'
    printf 'live:%s\n' "$*" >>"${COMPOSE_LOG}"
    if [[ "${1:-}" == up && "${MODE}" != ok && ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"
        case "${MODE}" in
        health-fail) return 1 ;;
        int) kill -INT "${BASHPID}" ;;
        term) kill -TERM "${BASHPID}" ;;
        esac
    fi
}
# 恢复已过 owner 门禁后直接执行 Compose，沿用当前作用域的锁、故障和停服断言。
dockerComposeExecute() { dockerComposeRun "$@"; }
dockerInitializeStateRoot
mkdir -p "${root}/secrets/tls"
printf 'fixture-cert\n' >"${root}/secrets/tls/${DOMAIN}.crt"
printf 'fixture-key\n' >"${root}/secrets/tls/${DOMAIN}.key"
dockerTlsRuntimePermissions "${root}/secrets/tls"
jq -n --arg domain "${DOMAIN}" --arg uuid "${UUID}" '
  {schema_version:3,release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"fixture"},
   core:{type:"xray",secondary_type:"sing-box",protocols:[
     {id:28,core:"xray",listener_id:"entry-xray",server:"proxy.example.com",public_port:24443,
      address_families:["ipv4","ipv6"],name:"xray",uuid:$uuid,trojan:{domain:$domain}},
     {id:4,core:"sing-box",listener_id:"entry-sing",server:"proxy.example.com",public_port:24444,
      address_families:["ipv4","ipv6"],name:"sing",uuid:$uuid,anytls:{domain:$domain}}]},
   tls:{domain:$domain},subscription:{enabled:false,token:"routing-regression-token"},
   images:(["xray","sing-box","nginx","ops","net"] |
     map({key:.,value:("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries),
   host_integrations:[]}
' >"${TEST_ROOT}/base.json"
jq -n --arg username "${USERNAME}" --arg password "${PASSWORD}" '
  {server:"203.0.113.9",port:1080,username:$username,password:$password}
' >"${INPUT}"
chmod 0600 "${INPUT}"
jq --slurpfile socks "${INPUT}" '.routing = {socks5:$socks[0]}' \
    "${TEST_ROOT}/base.json" >"${TEST_ROOT}/routed.json"
jq --argjson domains "${DOMAINS}" '. + {domains:$domains}' "${INPUT}" >"${DOMAINS_INPUT}"
chmod 0600 "${DOMAINS_INPUT}"
jq --slurpfile socks "${DOMAINS_INPUT}" '.routing = {socks5:$socks[0]}' \
    "${TEST_ROOT}/base.json" >"${TEST_ROOT}/domains.json"
printf '%s\n' "${DNS}" >"${DNS_INPUT}"
printf '%s\n' "${HOSTS}" >"${HOSTS_INPUT}"
chmod 0600 "${DNS_INPUT}" "${HOSTS_INPUT}"
jq --argjson dns "${DNS}" '.routing = {dns:$dns}' "${TEST_ROOT}/base.json" >"${TEST_ROOT}/dns-only.json"
jq --argjson hosts "${HOSTS}" '.routing = {hosts:$hosts}' "${TEST_ROOT}/base.json" >"${TEST_ROOT}/hosts-only.json"
jq --argjson dns "${DNS}" --argjson hosts "${HOSTS}" '.routing += {dns:$dns,hosts:$hosts}' \
    "${TEST_ROOT}/domains.json" >"${TEST_ROOT}/routing-all.json"
jq 'del(.routing.socks5.domains)' "${TEST_ROOT}/routing-all.json" >"${TEST_ROOT}/routing-all-global.json"
for kind in direct block; do
    jq -n --argjson domains "${DOMAINS}" '{domains:$domains}' >"${PRIVATE_ROOT}/${kind}.json"
    chmod 0600 "${PRIVATE_ROOT}/${kind}.json"
    jq --arg kind "${kind}" --argjson domains "${DOMAINS}" '.routing = {($kind):{domains:$domains}}' \
        "${TEST_ROOT}/base.json" >"${TEST_ROOT}/${kind}-only.json"
done
jq --argjson domains "${DOMAINS}" '.routing += {direct:{domains:$domains},block:{domains:$domains}}' \
    "${TEST_ROOT}/routing-all-global.json" >"${TEST_ROOT}/routing-policy.json"
printf '%s\n' "${BLOCK_IPS}" >"${BLOCK_IPS_INPUT}"
chmod 0600 "${BLOCK_IPS_INPUT}"
jq --argjson block_ips "${BLOCK_IPS}" '.routing = {block_ips:$block_ips}' \
    "${TEST_ROOT}/base.json" >"${TEST_ROOT}/block-ips-only.json"
jq --argjson block_ips "${BLOCK_IPS}" '.routing.block_ips = $block_ips' \
    "${TEST_ROOT}/routing-policy.json" >"${TEST_ROOT}/routing-ip-policy.json"
jq '.routing = {block_bt:true}' "${TEST_ROOT}/base.json" >"${TEST_ROOT}/block-bt-only.json"
jq '.routing.block_bt = true' "${TEST_ROOT}/routing-ip-policy.json" \
    >"${TEST_ROOT}/routing-bt-policy.json"
for mode in both domain ip; do
    jq --arg mode "${mode}" --argjson allow "${REGION_ALLOW}" \
        '.routing = {region:{mode:$mode,allow_domains:$allow}}' "${TEST_ROOT}/base.json" \
        >"${TEST_ROOT}/region-${mode}.json"
done
jq --argjson allow "${REGION_ALLOW}" '.routing.region = {mode:"both",allow_domains:$allow}' \
    "${TEST_ROOT}/routing-bt-policy.json" >"${TEST_ROOT}/region-owner.json"
for mode in selective global; do
    jq --arg mode "${mode}" --argjson domains "${IPV6_DOMAINS}" '
      .routing = {ipv6:{mode:$mode,domains:(if $mode == "selective" then $domains else [] end)}}
    ' "${TEST_ROOT}/base.json" >"${TEST_ROOT}/ipv6-${mode}.json"
done
jq --argjson domains "${IPV6_DOMAINS}" \
    '.routing.ipv6 = {mode:"selective",domains:$domains}' \
    "${TEST_ROOT}/routing-bt-policy.json" >"${TEST_ROOT}/ipv6-owner.json"
jq --argjson domains "${DOMAINS}" \
    '.routing.ipv6 = {mode:"global",domains:[]} | .routing.socks5.domains = $domains' \
    "${TEST_ROOT}/routing-bt-policy.json" >"${TEST_ROOT}/ipv6-global-owner.json"
jq -n --arg private "${WARP_PRIVATE}" --arg peer "${WARP_PUBLIC}" --argjson domains "${IPV6_DOMAINS}" '
  {mode:"selective",family:"ipv4",private_key:$private,peer_public_key:$peer,
   ipv6_address:"2606:4700:110:8a10::2",reserved:[1,2,255],domains:$domains}
' >"${WARP_INPUT}"
chmod 0600 "${WARP_INPUT}"
for mode in selective global; do
    jq --slurpfile warp "${WARP_INPUT}" --arg mode "${mode}" '
      .routing = {warp:($warp[0] | .mode=$mode |
        if $mode == "global" then .domains=[] else . end)}
    ' "${TEST_ROOT}/base.json" >"${TEST_ROOT}/warp-${mode}.json"
done
jq --slurpfile warp "${WARP_INPUT}" '.routing.warp = $warp[0]' \
    "${TEST_ROOT}/ipv6-owner.json" >"${TEST_ROOT}/warp-owner.json"
jq '.routing.warp.family = "ipv6"' "${TEST_ROOT}/warp-owner.json" \
    >"${TEST_ROOT}/warp-owner6.json"
jq --slurpfile warp "${WARP_INPUT}" '.routing.warp = ($warp[0] | .mode="global" | .domains=[])' \
    "${TEST_ROOT}/domains.json" >"${TEST_ROOT}/warp-global-owner.json"

# 域名工作流定向复用夹具，完整入口仍执行全部独立矩阵。
if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-workflow &&
    "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-dns-hosts &&
    "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-direct-block &&
    "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-direct-block-ip &&
    "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-direct-block-csv &&
    "${PADM_DOCKER_ROUTING_SCOPE:-}" != core-lifecycle &&
    "${PADM_DOCKER_ROUTING_SCOPE:-}" != core-network-lifecycle &&
    "${PADM_DOCKER_ROUTING_SCOPE:-}" != core-policy-lifecycle ]]; then
# 同批正反输入由两份校验合同独立判断，避免 Schema 与生产校验分歧。
python3 - "${PROJECT_ROOT}" "${TEST_ROOT}" <<'PY'
import copy
import json
import sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker

project, root = map(Path, sys.argv[1:])
base = json.loads((root / "base.json").read_text())
routed = json.loads((root / "routed.json").read_text())
domains = json.loads((root / "domains.json").read_text())
dns = json.loads((root / "dns-only.json").read_text())
hosts = json.loads((root / "hosts-only.json").read_text())
schema = json.loads((project / "docker/contracts/configure.schema.json").read_text())
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema, format_checker=FormatChecker())
cases = []

def case(name, value, valid):
    assert validator.is_valid(value) == valid, name
    (root / f"{name}.json").write_text(json.dumps(value), encoding="utf-8")
    cases.append((name, int(valid)))

case("legacy-v3", base, True)
case("valid-dual", routed, True)
case("valid-domains", domains, True)
case("dns-only", dns, True)
case("hosts-only", hosts, True)
case("routing-all", json.loads((root / "routing-all.json").read_text()), True)
case("routing-all-global", json.loads((root / "routing-all-global.json").read_text()), True)
case("routing-policy", json.loads((root / "routing-policy.json").read_text()), True)
ip_block = json.loads((root / "block-ips-only.json").read_text())
case("block-ips-only", ip_block, True)
case("routing-ip-policy", json.loads((root / "routing-ip-policy.json").read_text()), True)
bt_block = json.loads((root / "block-bt-only.json").read_text())
case("block-bt-only", bt_block, True)
case("routing-bt-policy", json.loads((root / "routing-bt-policy.json").read_text()), True)
for index, bad in enumerate((False, None, 0, 1, "true", "false", [], {})):
    value = copy.deepcopy(bt_block)
    value["routing"]["block_bt"] = bad
    case(f"invalid-block-bt-{index}", value, False)
region = json.loads((root / "region-both.json").read_text())
for mode in ("both", "domain", "ip"):
    case(f"region-{mode}", json.loads((root / f"region-{mode}.json").read_text()), True)
case("region-owner", json.loads((root / "region-owner.json").read_text()), True)
for count in (0, 256):
    value = copy.deepcopy(region)
    value["routing"]["region"]["allow_domains"] = [f"full:allow-{n}.example.com" for n in range(count)]
    case(f"region-allow-{count}", value, True)
for index, bad in enumerate((
        None, [], {}, {"mode": "both"}, {"allow_domains": []},
        {"mode": "all", "allow_domains": []}, {"mode": "Both", "allow_domains": []},
        {"mode": True, "allow_domains": []}, {"mode": "both", "allow_domains": None},
        {"mode": "both", "allow_domains": ["full:Example.com"]},
        {"mode": "both", "allow_domains": ["regexp:.*"]},
        {"mode": "both", "allow_domains": ["full:a.example.com"] * 2},
        {"mode": "both", "allow_domains": [True]},
        {"mode": "both", "allow_domains": [f"full:allow-{n}.example.com" for n in range(257)]},
        {"mode": "both", "allow_domains": [], "extra": True})):
    value = copy.deepcopy(region)
    value["routing"]["region"] = bad
    case(f"invalid-region-{index}", value, False)
ipv6 = json.loads((root / "ipv6-selective.json").read_text())
for name in ("ipv6-selective", "ipv6-global", "ipv6-owner", "ipv6-global-owner"):
    case(name, json.loads((root / f"{name}.json").read_text()), True)
value = copy.deepcopy(ipv6)
value["routing"]["ipv6"]["domains"] = [f"full:v6-{n}.example.com" for n in range(256)]
case("ipv6-domain-boundary", value, True)
for index, bad in enumerate((
        None, [], {}, {"mode": "selective"}, {"domains": []},
        {"mode": "all", "domains": []}, {"mode": "Selective", "domains": ["full:a.example.com"]},
        {"mode": True, "domains": []}, {"mode": "selective", "domains": []},
        {"mode": "global", "domains": ["full:a.example.com"]},
        {"mode": "global", "domains": None},
        {"mode": "selective", "domains": ["full:Example.com"]},
        {"mode": "selective", "domains": ["regexp:.*"]},
        {"mode": "selective", "domains": ["full:a.example.com"] * 2},
        {"mode": "selective", "domains": [True]},
        {"mode": "selective", "domains": [f"full:v6-{n}.example.com" for n in range(257)]},
        {"mode": "global", "domains": [], "extra": True})):
    value = copy.deepcopy(ipv6)
    value["routing"]["ipv6"] = bad
    case(f"invalid-ipv6-{index}", value, False)
value = copy.deepcopy(json.loads((root / "ipv6-global-owner.json").read_text()))
del value["routing"]["socks5"]["domains"]
case("invalid-ipv6-global-socks", value, False)
warp = json.loads((root / "warp-selective.json").read_text())
for name in ("warp-selective", "warp-global", "warp-owner", "warp-owner6", "warp-global-owner"):
    case(name, json.loads((root / f"{name}.json").read_text()), True)
for family in ("ipv4", "ipv6"):
    value = copy.deepcopy(warp)
    value["routing"]["warp"]["family"] = family
    case(f"warp-{family}", value, True)
for count in (1, 256):
    value = copy.deepcopy(warp)
    value["routing"]["warp"]["domains"] = [f"full:warp-{n}.example.com" for n in range(count)]
    case(f"warp-domains-{count}", value, True)
for field, invalid in (
        ("mode", [None, True, "Selective", "all"]),
        ("family", [None, True, "IPv4", "both", "ipv6_only"]),
        ("private_key", ["", "a" * 44, "A" * 43 + "B",
                         warp["routing"]["warp"]["private_key"] + "\n", None, []]),
        ("peer_public_key", ["", "a" * 44, "A" * 43 + "B",
                             warp["routing"]["warp"]["peer_public_key"] + "\n", None]),
        ("ipv6_address", ["192.0.2.1", "::", "::1", "fe80::1", "ff02::1",
                          "2001:db8::2/128", "[2001:db8::2]", "2001:db8::2%eth0", None]),
        ("reserved", [[], [1, 2], [1, 2, 3, 4], [1, 2, 256], [-1, 2, 3],
                      [True, 2, 3], [1.1, 2, 3], None]),
        ("domains", [[], ["regexp:.*"], ["full:Example.com"], ["full:a.example.com"] * 2,
                     [True], [f"full:warp-{n}.example.com" for n in range(257)]])):
    for index, bad in enumerate(invalid):
        value = copy.deepcopy(warp)
        value["routing"]["warp"][field] = bad
        case(f"invalid-warp-{field}-{index}", value, False)
for field in warp["routing"]["warp"]:
    value = copy.deepcopy(warp)
    del value["routing"]["warp"][field]
    case(f"invalid-warp-missing-{field}", value, False)
value = copy.deepcopy(warp)
value["routing"]["warp"]["extra"] = True
case("invalid-warp-extra", value, False)
value = copy.deepcopy(json.loads((root / "warp-global.json").read_text()))
value["routing"]["warp"]["domains"] = ["full:a.example.com"]
case("invalid-warp-global-domains", value, False)
for other in ("socks5", "ipv6"):
    value = copy.deepcopy(json.loads((root / "warp-global.json").read_text()))
    value["routing"][other] = (routed["routing"]["socks5"] if other == "socks5"
                               else dict(mode="global", domains=[]))
    case(f"invalid-warp-global-{other}", value, False)
for index, rules in enumerate((
        ["0.0.0.0", "127.0.0.1", "255.255.255.255", "::", "::1", "FFFF:FFFF::1"],
        ["0.0.0.0/0", "127.0.0.1/32", "::/0", "::1/128", "192.0.2.10/24", "2001:db8::10/64"],
        [f"192.0.2.{n}" for n in range(256)])):
    value = copy.deepcopy(ip_block)
    value["routing"]["block_ips"]["ips"] = rules
    case(f"valid-block-ips-{index}", value, True)
for index, bad in enumerate((
        None, [], {}, {"ips": []}, {"ips": ["192.0.2.1", "192.0.2.1"]},
        {"ips": [1]}, {"ips": [None]}, {"ips": ["example.com"]}, {"ips": ["01.2.3.4"]},
        {"ips": ["256.2.3.4"]}, {"ips": ["192.0.2.1/33"]}, {"ips": ["192.0.2.1/255.255.255.0"]},
        {"ips": ["192.0.2.1/-1"]}, {"ips": ["192.0.2.1/1.5"]}, {"ips": ["192.0.2.1/"]},
        {"ips": ["192.0.2.1/01"]}, {"ips": ["2001:db8::1/064"]},
        {"ips": ["2001:db8::1/129"]}, {"ips": ["2001:db8::1::2"]},
        {"ips": ["2001:db8::1%eth0"]}, {"ips": ["[2001:db8::1]"]},
        {"ips": ["::ffff:192.0.2.1"]}, {"ips": ["geoip:us"]}, {"ips": ["geoip:CN"]},
        {"ips": ["geosite:cn"]}, {"ips": ["!geoip:cn"]}, {"ips": [" 192.0.2.1"]},
        {"ips": ["192.0.2.1"], "extra": True},
        {"ips": [f"192.0.{n // 256}.{n % 256}" for n in range(257)]})):
    value = copy.deepcopy(ip_block)
    value["routing"]["block_ips"] = bad
    case(f"invalid-block-ips-{index}", value, False)
for kind in ("direct", "block"):
    template = json.loads((root / f"{kind}-only.json").read_text())
    case(f"{kind}-only", template, True)
    value = copy.deepcopy(template)
    value["routing"][kind]["domains"] = [f"full:host-{n}.example.com" for n in range(256)]
    case(f"valid-{kind}-boundary", value, True)
    for index, bad in enumerate(({}, None, [], {"domains": []},
                                {"domains": ["full:Example.com"]},
                                {"domains": ["full:a.example.com"] * 2},
                                {"domains": ["regexp:.*"]},
                                {"domains": ["keyword:a:b"]},
                                {"domains": [f"full:host-{n}.example.com" for n in range(257)]},
                                {"domains": ["full:a.example.com"], "extra": True})):
        value = copy.deepcopy(template)
        value["routing"][kind] = bad
        case(f"invalid-{kind}-{index}", value, False)
for name, template in (("dns", dns), ("hosts", hosts),
                       ("direct", json.loads((root / "direct-only.json").read_text())),
                       ("block", json.loads((root / "block-only.json").read_text())),
                       ("block-ips", ip_block), ("block-bt", bt_block), ("region", region),
                       ("ipv6", ipv6), ("warp", warp)):
    for version in (1, 2):
        value = copy.deepcopy(template)
        value["schema_version"] = version
        value["core"] = dict(type="xray", protocols=[value["core"]["protocols"][0]])
        del value["core"]["protocols"][0]["core"]
        if version == 1:
            del value["core"]["protocols"][0]["listener_id"]
        case(f"invalid-{name}-v{version}", value, False)
for index, changed in enumerate((
        dict(server="2001:db8::53", port=65535, domains=["full:dns.example.com"]),
        dict(server="1.1.1.1", port=1,
             domains=[f"full:host-{n}.example.com" for n in range(256)]))):
    value = copy.deepcopy(dns)
    value["routing"]["dns"] = changed
    case(f"valid-dns-boundary-{index}", value, True)
for field, bad in (("server", "127.0.0.1"), ("server", "resolver.example.com"),
                   ("port", 0), ("port", True), ("domains", []),
                   ("domains", ["full:a.example.com"] * 2),
                   ("domains", ["domain:Example.com"]),
                   ("domains", ["keyword:a:b"]),
                   ("domains", [f"full:host-{n}.example.com" for n in range(257)])):
    value = copy.deepcopy(dns)
    value["routing"]["dns"][field] = bad
    case(f"invalid-dns-{len(cases)}", value, False)
for field in ("server", "port", "domains"):
    value = copy.deepcopy(dns)
    del value["routing"]["dns"][field]
    case(f"invalid-dns-missing-{field}", value, False)
value = copy.deepcopy(dns)
value["routing"]["dns"]["extra"] = True
case("invalid-dns-extra", value, False)
value = copy.deepcopy(hosts)
value["routing"]["hosts"] = {f"host-{n}.example.com": "192.0.2.10" for n in range(256)}
case("valid-hosts-boundary", value, True)
for index, changed in enumerate((
        {}, [], None, {"Example.com": "192.0.2.10"}, {"full:example.com": "192.0.2.10"},
        {"example.com.": "192.0.2.10"}, {"-bad.example.com": "192.0.2.10"},
        {"example.com": "127.0.0.1"}, {"example.com": "host.docker.internal"},
        {"example.com": ["192.0.2.10"]}, {"example.com": "2001:db8::10%eth0"},
        {f"host-{n}.example.com": "192.0.2.10" for n in range(257)})):
    value = copy.deepcopy(hosts)
    value["routing"]["hosts"] = changed
    case(f"invalid-hosts-{index}", value, False)
hostname = ".".join(("a" * 63, "b" * 63, "c" * 63, "d" * 61))
for index, rules in enumerate((
        ["full:" + hostname, "domain:" + hostname],
        ["keyword:" + "a" * 253, "keyword:video_1.-"],
        ["geosite:" + "a" * 64, "geosite:0_a-b"],
        [f"full:host-{n}.example.com" for n in range(256)])):
    value = copy.deepcopy(domains)
    value["routing"]["socks5"]["domains"] = rules
    case(f"valid-domains-boundary-{index}", value, True)
for index, rules in enumerate((
        None, "", {}, False, [], [1], [None], ["domain:example.com", "domain:example.com"],
        ["DOMAIN:example.com"], ["full:Example.com"], ["geosite:CN"], ["example.com"],
        ["full:"], ["domain:"], ["keyword:"], ["geosite:"], ["regexp:.*"], ["geoip:cn"],
        ["full:-bad.example.com"], ["domain:bad-.example.com"], ["domain:a..example.com"],
        ["full:example.com."], ["full:" + "a" * 64 + ".com"],
        ["domain:" + hostname + "e"], ["keyword:" + "a" * 254],
        ["keyword:a b"], ["keyword:a/b"], ["keyword:a:b"], ["keyword:a*"],
        ["keyword:a\n"], ["keyword:\u00e9"], ["geosite:-cn"], ["geosite:a.b"],
        ["geosite:" + "a" * 65], [f"full:host-{n}.example.com" for n in range(257)])):
    value = copy.deepcopy(domains)
    value["routing"]["socks5"]["domains"] = rules
    case(f"invalid-domains-{index}", value, False)
for core in ("xray", "sing-box"):
    value = copy.deepcopy(routed)
    value["core"] = dict(type=core, secondary_type=None,
                         protocols=[p for p in value["core"]["protocols"] if p["core"] == core])
    case(f"valid-{core}", value, True)
for version in (1, 2):
    value = copy.deepcopy(base)
    value["schema_version"] = version
    value["core"] = dict(type="xray", protocols=[value["core"]["protocols"][0]])
    entry = value["core"]["protocols"][0]
    del entry["core"]
    del entry["trojan"]
    entry.update(id=21, websocket=dict(domain=base["tls"]["domain"], path="routingws",
                                      backend_port=31297, tls_port=8443))
    if version == 1:
        del entry["listener_id"]
        del entry["websocket"]["backend_port"]
        del entry["websocket"]["tls_port"]
    case(f"legacy-v{version}", value, True)
    value["routing"] = routed["routing"]
    case(f"invalid-v{version}", value, False)
for index, server in enumerate(("1.1.1.1", "10.1.2.3", "172.16.1.9", "192.168.1.9",
                                "2001:db8::9", "2001:db8:0:0:0:0:0:9", "fd00::9", "fc00::9")):
    value = copy.deepcopy(routed)
    value["routing"]["socks5"]["server"] = server
    case(f"valid-server-{index}", value, True)
for index, server in enumerate(("", None, 1, "proxy.example.com", "host.docker.internal", "localhost",
                                "0.0.0.0", "0.1.2.3", "127.0.0.1", "127.255.255.255",
                                "169.254.1.9", "224.0.0.1", "255.255.255.255", "01.2.3.4",
                                "1.2.3.256", "::", "::1", "fe80::9", "ff02::1", "2001:db8:::9",
                                "2001:db8::1::9", "2001:db8:1:2:3:4:5:6:7", "[2001:db8::9]",
                                "fd00::9%eth0", "::ffff:127.0.0.1")):
    value = copy.deepcopy(routed)
    value["routing"]["socks5"]["server"] = server
    case(f"invalid-server-{index}", value, False)
for index, routing in enumerate((None, {}, [], False, {"socks5": None}, {"socks5": []},
                                  dict(routed["routing"], extra=True))):
    value = copy.deepcopy(routed)
    value["routing"] = routing
    case(f"invalid-routing-{index}", value, False)
for field in ("server", "port", "username", "password"):
    value = copy.deepcopy(routed)
    del value["routing"]["socks5"][field]
    case(f"invalid-missing-{field}", value, False)
value = copy.deepcopy(routed)
value["routing"]["socks5"]["extra"] = True
case("invalid-socks-extra", value, False)
for index, port in enumerate((1, 65535)):
    value = copy.deepcopy(routed)
    value["routing"]["socks5"]["port"] = port
    case(f"valid-port-{index}", value, True)
for index, port in enumerate((0, 65536, -1, 1080.5, "1080", None, True)):
    value = copy.deepcopy(routed)
    value["routing"]["socks5"]["port"] = port
    case(f"invalid-port-{index}", value, False)
for field in ("username", "password"):
    value = copy.deepcopy(routed)
    value["routing"]["socks5"][field] = "".join(chr(i) for i in range(33, 127))
    case(f"valid-ascii-{field}", value, True)
    value["routing"]["socks5"][field] = "!" * 255
    case(f"valid-max-{field}", value, True)
    for index, credential in enumerate(("", "!" * 256, "a b", "a\n", "a\t", "\x00", "\x7f",
                                        "\u00e9", None, 1, [], {})):
        value = copy.deepcopy(routed)
        value["routing"]["socks5"][field] = credential
        case(f"invalid-credential-{field}-{index}", value, False)
for integration in ("tun", "tproxy"):
    value = copy.deepcopy(routed)
    core = "sing-box" if integration == "tun" else "xray"
    entry = copy.deepcopy(value["core"]["protocols"][0])
    del entry["trojan"]
    entry.update(id=1, core=core, reality=dict(server_name="www.example.com",
                 target_host="www.example.com", target_port=443, private_key="A" * 43,
                 public_key="B" * 43, short_id="1234abcd"))
    value["core"] = dict(type=core, secondary_type=None, protocols=[entry])
    value["tls"] = None
    value["host_integrations"] = [dict(
        type=integration, profile="net-transparent", schedules=[],
        firewall_rules=["sing-box-auto-redirect" if integration == "tun" else "padm-tproxy"],
        devices=["/dev/net/tun"] if integration == "tun" else [],
        settings=dict(interface="padm-tun", address="198.18.0.1/30") if integration == "tun"
        else dict(port=12345, mark=1))]
    legacy = copy.deepcopy(value)
    del legacy["routing"]
    case(f"valid-integration-{integration}", legacy, True)
    case(f"invalid-integration-{integration}", value, False)
    value["routing"] = ipv6["routing"]
    case(f"invalid-ipv6-integration-{integration}", value, False)
    value["routing"] = warp["routing"]
    case(f"invalid-warp-integration-{integration}", value, False)
    if integration == "tun":
        for version in (1, 2):
            value = copy.deepcopy(legacy)
            value["schema_version"] = version
            value["host_integrations"] = []
            del value["core"]["secondary_type"]
            del value["core"]["protocols"][0]["core"]
            if version == 1:
                del value["core"]["protocols"][0]["listener_id"]
            case(f"legacy-sing-v{version}", value, True)
(root / "cases.tsv").write_text("".join(f"{name}\t{valid}\n" for name, valid in cases))
PY
while IFS=$'\t' read -r name valid; do
    actual=0
    dockerConfigureSpecValidate "${TEST_ROOT}/${name}.json" >"${LOG}" 2>&1 || actual=$?
    if [[ "${valid}" == 1 ]]; then
        [[ "${actual}" == 0 ]] || fail "生产校验拒绝 Schema 有效输入: ${name}"
    else
        [[ "${actual}" != 0 ]] || fail "生产校验接受 Schema 无效输入: ${name}"
    fi
done <"${TEST_ROOT}/cases.tsv"

# 只有显式路由需要新版 bundle；无 routing 的旧规格保持兼容。
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/routed.json" ||
    fail '当前 bundle 拒绝 SOCKS5 路由能力'
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/domains.json" ||
    fail '当前 bundle 拒绝 SOCKS5 域名路由能力'
cp -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved"
jq 'del(."x-padm-routing-socks5")' \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/routed.json"
reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/domains.json"
for version in 1 2 3; do
    dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/legacy-v${version}.json" ||
        fail "v${version}: 无 routing 规格被新版能力门禁误拒绝"
done
mv -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
cp -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved"
jq 'del(."x-padm-routing-domains")' \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/domains.json"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/routed.json" ||
    fail '旧 SOCKS5 bundle 被域名规则能力门禁误拒绝'
for version in 1 2 3; do
    dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/legacy-v${version}.json" ||
        fail "v${version}: 无 routing 被域名规则能力门禁误拒绝"
done
mv -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"

for fixture in ipv6-selective ipv6-global ipv6-owner ipv6-global-owner; do
    dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/${fixture}.json" ||
        fail "${fixture}: 当前 bundle 拒绝 IPv6 路由"
done
for fixture in warp-selective warp-global warp-owner warp-owner6 warp-global-owner; do
    dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/${fixture}.json" ||
        fail "${fixture}: 当前 bundle 拒绝 WARP 路由"
done
cp -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved"
jq 'del(."x-padm-routing-warp")' \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
for fixture in warp-selective warp-global; do
    reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/${fixture}.json"
done
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/ipv6-global.json" ||
    fail 'WARP marker 缺失误拒绝旧 IPv6 路由'
mv -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
cp -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved"
for marker in 'del(."x-padm-routing-ipv6")' '."x-padm-routing-ipv6" = false'; do
    jq "${marker}" "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
        >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
    reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/ipv6-selective.json"
    reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/ipv6-global-owner.json"
    dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/routing-bt-policy.json" ||
        fail 'IPv6 marker 拒绝旧路由'
done
jq 'del(."x-padm-routing-socks5", ."x-padm-routing-domains", ."x-padm-routing-dns-hosts",
  ."x-padm-routing-direct-block", ."x-padm-routing-block-ips", ."x-padm-routing-block-bt",
  ."x-padm-routing-region")' "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/ipv6-global.json" ||
    fail 'IPv6-only 规格依赖其它路由 marker'
mv -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"

for fixture in region-both region-domain region-ip region-owner; do
    dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/${fixture}.json" ||
        fail "${fixture}: 当前 bundle 拒绝区域策略"
done
cp -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved"
for marker in 'del(."x-padm-routing-region")' '."x-padm-routing-region" = false'; do
    jq "${marker}" "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
        >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
    reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/region-owner.json"
    reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/region-both.json"
    dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/routing-bt-policy.json" ||
        fail '区域 marker 拒绝旧路由'
done
jq 'del(."x-padm-routing-socks5", ."x-padm-routing-domains", ."x-padm-routing-dns-hosts",
  ."x-padm-routing-direct-block", ."x-padm-routing-block-ips", ."x-padm-routing-block-bt")' \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/region-both.json" ||
    fail '纯区域策略依赖其它路由 marker'
mv -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"

for fixture in block-bt-only routing-bt-policy; do
    dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/${fixture}.json" ||
        fail "${fixture}: 当前 bundle 拒绝 BT 阻断"
done
cp -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved"
jq 'del(."x-padm-routing-block-bt")' \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
for fixture in block-bt-only routing-bt-policy; do
    reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/${fixture}.json"
done
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/routing-ip-policy.json" ||
    fail 'BT marker 缺失误拒绝旧路由'
jq 'del(."x-padm-routing-socks5", ."x-padm-routing-domains", ."x-padm-routing-dns-hosts",
  ."x-padm-routing-direct-block", ."x-padm-routing-block-ips")' \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/block-bt-only.json" ||
    fail 'BT-only 规格错误依赖其它路由 marker'
mv -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"

for fixture in block-ips-only routing-ip-policy; do
    dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/${fixture}.json" ||
        fail "${fixture}: 当前 bundle 拒绝 IP/CIDR/GeoIP 阻断"
done
cp -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved"
jq 'del(."x-padm-routing-block-ips")' \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
for fixture in block-ips-only routing-ip-policy; do
    reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/${fixture}.json"
done
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/routing-policy.json" ||
    fail 'IP 阻断 marker 拒绝旧路由'
jq 'del(."x-padm-routing-socks5", ."x-padm-routing-domains", ."x-padm-routing-dns-hosts",
  ."x-padm-routing-direct-block")' \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/block-ips-only.json" ||
    fail 'IP-only 规格依赖其它路由 marker'
mv -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"

for fixture in direct-only block-only routing-policy; do
    dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/${fixture}.json" ||
        fail "${fixture}: 当前 bundle 拒绝 Direct/Block"
done
cp -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved"
jq 'del(."x-padm-routing-direct-block")' \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
for fixture in direct-only block-only routing-policy; do
    reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/${fixture}.json"
done
for fixture in routed domains dns-only hosts-only; do
    dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/${fixture}.json" ||
        fail "${fixture}: Direct/Block marker 拒绝旧路由"
done
jq 'del(."x-padm-routing-socks5", ."x-padm-routing-domains", ."x-padm-routing-dns-hosts")' \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
for fixture in direct-only block-only; do
    dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/${fixture}.json" ||
        fail "${fixture}: Direct/Block-only 错误依赖旧路由 marker"
done
mv -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"

for fixture in dns-only hosts-only routing-all; do
    dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/${fixture}.json" ||
        fail "${fixture}: 当前 bundle 拒绝 DNS/hosts 能力"
done
cp -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved"
jq 'del(."x-padm-routing-dns-hosts")' \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
for fixture in dns-only hosts-only routing-all; do
    reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/${fixture}.json"
done
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/routed.json" ||
    fail 'DNS/hosts 能力门禁误拒绝旧 SOCKS5'
jq 'del(."x-padm-routing-socks5", ."x-padm-routing-domains")' \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
for fixture in dns-only hosts-only; do
    dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/${fixture}.json" ||
        fail "${fixture}: 无 SOCKS5 的规格依赖旧 SOCKS5 marker"
done
mv -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"

for version in 1 2 3; do
    dockerGenerateXrayConfig "${TEST_ROOT}/legacy-v${version}.json" "${TEST_ROOT}/legacy-v${version}-xray.json"
    jq -e '.outbounds == [{protocol:"freedom",tag:"direct"},{protocol:"blackhole",tag:"blocked"}] and
      (has("routing") | not)' "${TEST_ROOT}/legacy-v${version}-xray.json" >/dev/null ||
        fail "v${version}: 无 routing 改变旧 Xray 默认出站"
done
dockerGenerateSingBoxConfig "${TEST_ROOT}/base.json" "${TEST_ROOT}/legacy-sing-box.json"
jq -e '.outbounds == [{type:"direct",tag:"direct"}] and
  .route == {final:"direct",auto_detect_interface:true}' "${TEST_ROOT}/legacy-sing-box.json" >/dev/null ||
    fail '无 routing 改变旧 sing-box 默认出站'
for version in 1 2; do
    dockerGenerateSingBoxConfig "${TEST_ROOT}/legacy-sing-v${version}.json" \
        "${TEST_ROOT}/legacy-sing-v${version}-core.json"
    jq -e '.outbounds == [{type:"direct",tag:"direct"}] and
      .route == {final:"direct",auto_detect_interface:true}' \
        "${TEST_ROOT}/legacy-sing-v${version}-core.json" >/dev/null ||
        fail "v${version}: 无 routing 改变旧 sing-box 默认出站"
done
for fixture in routed domains dns-only hosts-only routing-all routing-all-global direct-only block-only routing-policy block-ips-only routing-ip-policy block-bt-only routing-bt-policy region-both region-domain region-ip region-owner ipv6-selective ipv6-global ipv6-owner ipv6-global-owner warp-selective warp-global warp-ipv6 warp-owner warp-owner6 warp-global-owner; do
    for core in xray sing-box; do
        if [[ "${core}" == xray ]]; then
            dockerGenerateXrayConfig "${TEST_ROOT}/${fixture}.json" "${TEST_ROOT}/${fixture}-${core}.json"
        else
            dockerGenerateSingBoxConfig "${TEST_ROOT}/${fixture}.json" "${TEST_ROOT}/${fixture}-${core}.json"
        fi
        dockerTrafficRender "${core}" "${TEST_ROOT}/${fixture}-${core}.json" \
            '{"schema_version":1,"accounts":{}}' >"${TEST_ROOT}/runtime-${fixture}-${core}.json"
    done
done
jq -en --slurpfile old "${TEST_ROOT}/legacy-v3-xray.json" \
    --slurpfile new "${TEST_ROOT}/routed-xray.json" --slurpfile socks "${INPUT}" '
  $new[0].outbounds[0] == {protocol:"socks",tag:"padm-socks5",settings:{servers:[{
    address:$socks[0].server,port:$socks[0].port,
    users:[{user:$socks[0].username,pass:$socks[0].password}]}]}} and
  $new[0].routing.rules == [{type:"field",network:"udp",outboundTag:"blocked"}] and
  ($new[0] | .outbounds |= .[1:] | del(.routing)) == $old[0]
' >/dev/null || fail 'Xray SOCKS5 首出站或 UDP 拒绝合同改变其它配置'
jq -en --slurpfile old "${TEST_ROOT}/legacy-sing-box.json" \
    --slurpfile new "${TEST_ROOT}/routed-sing-box.json" --slurpfile socks "${INPUT}" '
  $new[0].outbounds[0] == {type:"socks",tag:"padm-socks5",server:$socks[0].server,
    server_port:$socks[0].port,version:"5",username:$socks[0].username,password:$socks[0].password} and
  $new[0].route.final == "padm-socks5" and
  $new[0].route.rules == [{network:"udp",action:"reject"}] and
  ($new[0] | .outbounds |= .[1:] | .route.final = "direct" | del(.route.rules)) == $old[0]
' >/dev/null || fail 'sing-box SOCKS5 默认出站或 UDP 拒绝合同改变其它配置'
jq -en --argjson domains "${DOMAINS}" --slurpfile old "${TEST_ROOT}/legacy-v3-xray.json" \
    --slurpfile new "${TEST_ROOT}/domains-xray.json" --slurpfile global "${TEST_ROOT}/routed-xray.json" '
  ($domains | map(if startswith("keyword:") then ltrimstr("keyword:") else . end)) as $xrayDomains |
  $new[0].outbounds[0] == {protocol:"freedom",tag:"direct"} and
  ($new[0].outbounds | map(select(.tag == "padm-socks5"))) == [$global[0].outbounds[0]] and
  $new[0].routing.rules == [
    {type:"field",domain:$xrayDomains,network:"udp",outboundTag:"blocked"},
    {type:"field",domain:$xrayDomains,network:"tcp",outboundTag:"padm-socks5"}] and
  all($new[0].inbounds[]; .sniffing.enabled == true and .sniffing.routeOnly == true and
    (.sniffing.destOverride | index("http") != null and index("tls") != null)) and
  ($new[0] | .outbounds |= map(select(.tag != "padm-socks5")) | del(.routing) |
    .inbounds |= map(del(.sniffing))) == $old[0]
' >/dev/null || fail 'Xray 选择性路由没有保留域名 OR、未匹配直连或路由专用嗅探'
jq -en --slurpfile new "${TEST_ROOT}/domains-sing-box.json" \
    --slurpfile global "${TEST_ROOT}/routed-sing-box.json" '
  $new[0].route.final == "direct" and
  ($new[0].outbounds | map(select(.tag == "padm-socks5"))) == [$global[0].outbounds[0]] and
  $new[0].route.rules[0].action == "sniff" and
  ($new[0].route.rule_set | map(.tag) | sort) ==
    ["padm-geosite-category-ads-all","padm-geosite-cn"]
' >/dev/null || fail 'sing-box 选择性路由没有保持认证出站、直连或规则集'
jq -en --slurpfile dns "${TEST_ROOT}/dns-only-xray.json" \
    --slurpfile hosts "${TEST_ROOT}/hosts-only-xray.json" \
    --slurpfile both "${TEST_ROOT}/routing-all-xray.json" '
  ($dns[0].dns.disableFallbackIfMatch == true and
   ($dns[0].dns.servers | length) == 2 and
   $dns[0].dns.servers[0].address == "203.0.113.53" and
   $dns[0].dns.servers[0].skipFallback == true and
   $dns[0].dns.servers[0].finalQuery == true and
   $dns[0].dns.servers[1] == "localhost" and
   ($dns[0].routing.rules | index({type:"field",inboundTag:["padm-dns"],outboundTag:"direct"})) != null and
   all($dns[0].outbounds[] | select(.tag == "direct"); .settings.domainStrategy == "ForceIP")) and
  (($hosts[0].dns.servers | length) == 1 and $hosts[0].dns.servers[0] == "localhost") and
  (($both[0].dns.servers | map(if type == "object" then .address else . end) | index("203.0.113.53")) != null)
' >/dev/null || fail 'Xray DNS/hosts 解析器、直连策略或入站规则合同错误'
jq -en --slurpfile dns "${TEST_ROOT}/dns-only-sing-box.json" \
    --slurpfile hosts "${TEST_ROOT}/hosts-only-sing-box.json" \
    --slurpfile both "${TEST_ROOT}/routing-all-sing-box.json" '
  ($dns[0].dns.servers | map(.tag) | sort) == ["padm-dns","padm-local"] and
  ($dns[0].route.final == "direct" and $dns[0].dns.final == "padm-local" and
   $dns[0].route.default_domain_resolver == "padm-local") and
  ($dns[0].route.rules | map(select(.action == "resolve" and .server == "padm-dns")) | length) >= 1 and
  ($hosts[0].dns.servers | map(.tag) | sort) == ["padm-hosts","padm-local"] and
  ($both[0].route.rules | map(select(.action == "route" and .outbound == "padm-socks5")) | length) >= 1
' >/dev/null || fail 'sing-box DNS/hosts 解析器、直连最终出站或 SOCKS5 优先级合同错误'
jq -en --slurpfile xray "${TEST_ROOT}/routing-all-global-xray.json" \
    --slurpfile sing "${TEST_ROOT}/routing-all-global-sing-box.json" '
  $xray[0].outbounds[0].tag == "padm-socks5" and
  $xray[0].routing.rules == [
    {type:"field",inboundTag:["padm-dns"],outboundTag:"direct"},
    {type:"field",network:"udp",outboundTag:"blocked"}] and
  $sing[0].route.final == "padm-socks5" and
  $sing[0].route.rules[:2] == [
    {network:"udp",action:"reject"},
    {network:"tcp",action:"route",outbound:"padm-socks5"}] and
  all($sing[0].route.rules[2:][]; .action == "resolve" or .outbound == "direct")
' >/dev/null || fail '全局 SOCKS5 没有优先于 DNS/hosts 解析或改变 UDP 阻断'
jq -en --argjson domains "${DOMAINS}" --slurpfile direct "${TEST_ROOT}/direct-only-xray.json" \
    --slurpfile block "${TEST_ROOT}/block-only-xray.json" \
    --slurpfile policy "${TEST_ROOT}/routing-policy-xray.json" '
  ($domains | map(if startswith("keyword:") then ltrimstr("keyword:") else . end)) as $match |
  $direct[0].routing.rules == [{type:"field",domain:$match,outboundTag:"direct"}] and
  $block[0].routing.rules == [{type:"field",domain:$match,outboundTag:"blocked"}] and
  $policy[0].routing.rules == [
    {type:"field",inboundTag:["padm-dns"],outboundTag:"direct"},
    {type:"field",domain:$match,outboundTag:"direct"},
    {type:"field",domain:$match,outboundTag:"blocked"},
    {type:"field",network:"udp",outboundTag:"blocked"}] and
  all($policy[0].inbounds[]; .sniffing.routeOnly == true)
' >/dev/null || fail 'Xray Direct/Block 优先级、四类 OR 或路由专用嗅探错误'
jq -en --slurpfile direct "${TEST_ROOT}/direct-only-sing-box.json" \
    --slurpfile block "${TEST_ROOT}/block-only-sing-box.json" \
    --slurpfile policy "${TEST_ROOT}/routing-policy-sing-box.json" '
  $direct[0].route.rules[0].action == "sniff" and
  ($direct[0].route.rules[1:] | length) == 4 and
  all($direct[0].route.rules[1:][]; .action == "route" and .outbound == "direct") and
  $block[0].route.rules[0].action == "sniff" and
  ($block[0].route.rules[1:] | length) == 4 and
  all($block[0].route.rules[1:][]; .action == "reject") and
  ($policy[0].route.rules | map(select(.action == "reject")) |
    all(.[]; .type == "logical" and .mode == "and" and
      .rules[1].mode == "or" and .rules[1].invert == true and (.rules[1].rules | length) == 4)) and
  ($policy[0].route.rule_set | map(.tag) | sort) ==
    ["padm-geosite-category-ads-all","padm-geosite-cn"]
' >/dev/null || fail 'sing-box Direct/Block OR、排除 Direct 或共享分类去重错误'
jq -en --argjson input "${BLOCK_IPS}" --slurpfile only "${TEST_ROOT}/block-ips-only-xray.json" \
    --slurpfile policy "${TEST_ROOT}/routing-ip-policy-xray.json" '
  $only[0].routing == {domainStrategy:"AsIs",
    rules:[{type:"field",ip:$input.ips,outboundTag:"blocked"}]} and
  $policy[0].routing.domainStrategy == "AsIs" and
  $policy[0].routing.rules[0].inboundTag == ["padm-dns"] and
  $policy[0].routing.rules[1].outboundTag == "direct" and
  $policy[0].routing.rules[3] == {type:"field",ip:$input.ips,outboundTag:"blocked"}
' >/dev/null || fail 'Xray IP 阻断未保持 AsIs、Direct 例外或内置 DNS 标签优先'
jq -en --argjson input "${BLOCK_IPS}" --slurpfile only "${TEST_ROOT}/block-ips-only-sing-box.json" \
    --slurpfile policy "${TEST_ROOT}/routing-ip-policy-sing-box.json" '
  $only[0].route.rules == [
    {action:"sniff",timeout:"1s"},
    {ip_cidr:($input.ips | map(select(. != "geoip:cn"))),action:"reject"},
    {rule_set:["padm-geoip-cn"],action:"reject"}] and
  ($only[0].route.rule_set | map(.tag)) == ["padm-geoip-cn"] and
  $only[0].route.rule_set[0].url ==
    "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs" and
  $only[0].route.rule_set[0].http_client == {engine:"go"} and
  all($policy[0].route.rules[] | select(.action == "reject"); .type == "logical") and
  ($policy[0].route.rule_set | map(.tag) | sort) ==
    ["padm-geoip-cn","padm-geosite-category-ads-all","padm-geosite-cn"]
' >/dev/null || fail 'sing-box IP/CIDR/GeoIP OR、Direct 例外或远程资源合同错误'
jq -en --slurpfile only "${TEST_ROOT}/block-bt-only-xray.json" \
    --slurpfile policy "${TEST_ROOT}/routing-bt-policy-xray.json" '
  $only[0].routing.rules == [{type:"field",protocol:["bittorrent"],outboundTag:"blocked"}] and
  all($only[0].inbounds[]; .sniffing.enabled == true and .sniffing.routeOnly == true and
    .sniffing.destOverride == ["http","tls","quic"]) and
  $policy[0].routing.rules[0].inboundTag == ["padm-dns"] and
  $policy[0].routing.rules[1].outboundTag == "direct" and
  $policy[0].routing.rules[4] == {type:"field",protocol:["bittorrent"],outboundTag:"blocked"} and
  $policy[0].routing.rules[5] == {type:"field",network:"udp",outboundTag:"blocked"}
' >/dev/null || fail 'Xray BT 嗅探或 Direct/BT/SOCKS 优先级错误'
jq -en --slurpfile only "${TEST_ROOT}/block-bt-only-sing-box.json" \
    --slurpfile policy "${TEST_ROOT}/routing-bt-policy-sing-box.json" '
  ($policy[0].route.rules | map(select(.rules[0].protocol? == ["bittorrent"]))) as $bt |
  $only[0].route.rules == [
    {action:"sniff",timeout:"1s"},{protocol:["bittorrent"],action:"reject"}] and
  ($bt | length) == 1 and
  $bt[0] == {type:"logical",mode:"and",rules:[
    {protocol:["bittorrent"]},
    {type:"logical",mode:"or",invert:true,rules:[
      {domain:["exact.example.com","other.example.com"]},{domain_suffix:["example.net"]},
      {domain_keyword:["video"]},{rule_set:["padm-geosite-cn","padm-geosite-category-ads-all"]}]}],
    action:"reject"} and
  ($policy[0].route.rules | index($bt[0])) <
    ($policy[0].route.rules | map(.action) | index("resolve"))
' >/dev/null || fail 'sing-box BT 协议匹配、Direct 例外或解析前拒绝错误'
[[ "${PADM_DOCKER_REGION_DEFAULT_DOMAINS}" == "${REGION_DEFAULTS}" ]] ||
    fail '固定区域默认例外合同改变'
for mode in both domain ip; do
    jq -en --arg mode "${mode}" --argjson defaults "${REGION_DEFAULTS}" --argjson allow "${REGION_ALLOW}" \
        --slurpfile config "${TEST_ROOT}/region-${mode}-xray.json" '
      (($defaults + $allow) | unique) as $direct |
      $config[0].routing.rules == (
        [{type:"field",domain:$direct,outboundTag:"direct"}] +
        (if $mode == "ip" then [] else [
          {type:"field",domain:["geosite:cn"],outboundTag:"blocked"}] end) +
        (if $mode == "domain" then [] else [
          {type:"field",ip:["geoip:cn"],outboundTag:"blocked"}] end)) and
      ($config[0].outbounds | map(.tag)) == ["direct","blocked"] and
      all($config[0].inbounds[]; .sniffing.enabled == true and .sniffing.routeOnly == true)
    ' >/dev/null || fail "${mode}: Xray 区域模式或默认/自定义例外错误"
    jq -en --arg mode "${mode}" --argjson defaults "${REGION_DEFAULTS}" --argjson allow "${REGION_ALLOW}" \
        --slurpfile config "${TEST_ROOT}/region-${mode}-sing-box.json" '
      (($defaults + $allow) | unique) as $domains |
      [{domain:[$domains[] | select(startswith("full:")) | ltrimstr("full:")]},
       {domain_suffix:[$domains[] | select(startswith("domain:")) | ltrimstr("domain:")]}] as $direct |
      $config[0].route.rules[0] == {action:"sniff",timeout:"1s"} and
      ($config[0].route.rule_set | map(.tag) | sort) ==
        (if $mode == "both" then ["padm-geoip-cn","padm-geosite-cn"]
         elif $mode == "domain" then ["padm-geosite-cn"] else ["padm-geoip-cn"] end) and
      all($config[0].route.rules[] | select(.action == "reject");
        .type == "logical" and .mode == "and" and
        .rules[1] == {type:"logical",mode:"or",invert:true,rules:$direct}) and
      ($config[0].route.rules | map(select(.action == "reject")) | length) ==
        (if $mode == "both" then 2 else 1 end) and
      $config[0].route.rules[-2:] == ($direct | map(. + {action:"route",outbound:"direct"})) and
      $config[0].route.final == "direct"
    ' >/dev/null || fail "${mode}: sing-box 区域模式或 Direct 排除合同错误"
done
jq -en --argjson defaults "${REGION_DEFAULTS}" --argjson allow "${REGION_ALLOW}" \
    --argjson domains "${DOMAINS}" --slurpfile old "${TEST_ROOT}/routing-bt-policy-xray.json" \
    --slurpfile new "${TEST_ROOT}/region-owner-xray.json" '
  def ordered_rules:
    map(if has("domain") then .domain |= sort elif has("ip") then .ip |= sort else . end);
  (($defaults + $allow + $domains) | unique |
    map(if startswith("keyword:") then ltrimstr("keyword:") else . end)) as $direct |
  $new[0].routing.rules[1] == {type:"field",domain:$direct,outboundTag:"direct"} and
  ($new[0].routing.rules[2:] | ordered_rules) == ($old[0].routing.rules[2:] | ordered_rules) and
  $new[0].outbounds == $old[0].outbounds
' >/dev/null || fail 'Xray 区域合并重复 CN、改变 generic 或 BT/SOCKS 优先级'
jq -en --slurpfile old "${TEST_ROOT}/routing-bt-policy-sing-box.json" \
    --slurpfile new "${TEST_ROOT}/region-owner-sing-box.json" '
  $new[0].route.rule_set == $old[0].route.rule_set and
  ($new[0].route.rules | length) == ($old[0].route.rules | length) and
  $new[0].outbounds == $old[0].outbounds and
  all($new[0].route.rules[] | select(.action == "reject");
    .rules[1].invert == true and
    (.rules[1].rules | map(.domain_suffix // []) | add | index("apple.com")) != null)
' >/dev/null || fail 'sing-box 区域重复分类、generic 或默认例外未合并'
jq -en --argjson domains "${IPV6_DOMAINS}" \
    --slurpfile selective "${TEST_ROOT}/ipv6-selective-xray.json" \
    --slurpfile global "${TEST_ROOT}/ipv6-global-xray.json" \
    --slurpfile owner "${TEST_ROOT}/ipv6-owner-xray.json" '
  ($domains | map(if startswith("keyword:") then ltrimstr("keyword:") else . end)) as $match |
  {protocol:"freedom",tag:"padm-ipv6",settings:{domainStrategy:"ForceIPv6"}} as $v6 |
  ($selective[0].outbounds | index($v6)) != null and
  $selective[0].outbounds[0] == {protocol:"freedom",tag:"direct"} and
  $selective[0].routing.rules == [
    {type:"field",inboundTag:["padm-dns"],outboundTag:"direct"},
    {type:"field",domain:$match,outboundTag:"padm-ipv6"}] and
  $global[0].outbounds[0] == $v6 and
  $global[0].routing.rules == [{type:"field",inboundTag:["padm-dns"],outboundTag:"direct"}] and
  $owner[0].routing.rules[4].protocol == ["bittorrent"] and
  $owner[0].routing.rules[5] == {type:"field",domain:$match,outboundTag:"padm-ipv6"} and
  $owner[0].routing.rules[6].network == "udp" and
  $owner[0].dns.hosts["full:ipv6.example.com"] == "2001:db8::10" and
  $owner[0].dns.servers[0].finalQuery == true and
  $owner[0].dns.disableFallbackIfMatch == true
' >/dev/null || fail 'Xray IPv6 默认/选择性出站、AAAA 来源或策略优先级错误'
jq -en --slurpfile selective "${TEST_ROOT}/ipv6-selective-sing-box.json" \
    --slurpfile global "${TEST_ROOT}/ipv6-global-sing-box.json" \
    --slurpfile owner "${TEST_ROOT}/ipv6-owner-sing-box.json" \
    --slurpfile global_owner "${TEST_ROOT}/ipv6-global-owner-sing-box.json" '
  {type:"direct",tag:"padm-ipv6",
    domain_resolver:{server:"padm-local",strategy:"ipv6_only"}} as $v6 |
  ($selective[0].outbounds | index($v6)) != null and
  $selective[0].route.final == "direct" and
  $selective[0].route.rules[-1] == {type:"logical",mode:"or",rules:[
    {domain:["exact.example.com"]},{domain_suffix:["example.net"]},
    {domain_keyword:["video"]},{rule_set:["padm-geosite-cn"]}],
    action:"route",outbound:"padm-ipv6"} and
  $global[0].route.final == "padm-ipv6" and
  $global[0].route.rules[-1] == {network:["tcp","udp"],action:"route",outbound:"padm-ipv6"} and
  ($owner[0].route.rules | map(.outbound) | index("padm-ipv6")) <
    ($owner[0].route.rules | map(.outbound) | index("padm-socks5")) and
  ($global_owner[0].route.rules | map(.outbound) | index("padm-socks5")) <
    ($global_owner[0].route.rules | map(.outbound) | index("padm-ipv6")) and
  all($owner[0].route.rules[] | select(.outbound == "padm-ipv6");
    .type == "logical" and .rules[1].invert == true) and
  ([$owner[0].route.rules[] | select(.action == "resolve" and .strategy == "ipv6_only") |
    .server] | sort) == ["padm-dns","padm-dns","padm-dns","padm-dns","padm-hosts"] and
  $owner[0].dns.final == "padm-local" and
  ($owner[0].route.rules | map(.action) | index("reject")) <
    ($owner[0].route.rules | map(.outbound) | index("padm-ipv6"))
' >/dev/null || fail 'sing-box IPv6 OR、Direct 例外、同源解析或 SOCKS 优先级错误'
jq -en --slurpfile selective "${TEST_ROOT}/warp-selective-xray.json" \
    --slurpfile global "${TEST_ROOT}/warp-global-xray.json" \
    --slurpfile ipv6 "${TEST_ROOT}/warp-ipv6-xray.json" \
    --slurpfile owner "${TEST_ROOT}/warp-owner-xray.json" \
    --arg private "${WARP_PRIVATE}" --arg public "${WARP_PUBLIC}" '
  ($selective[0].outbounds[] | select(.tag == "padm-warp")) as $warp |
  $warp == {protocol:"wireguard",tag:"padm-warp",targetStrategy:"ForceIPv4",settings:{
    secretKey:$private,address:["172.16.0.2/32"],mtu:1280,noKernelTun:true,reserved:[1,2,255],
    peers:[{publicKey:$public,allowedIPs:["0.0.0.0/0","::/0"],endpoint:"162.159.192.1:2408"}]}} and
  ($ipv6[0].outbounds[] | select(.tag == "padm-warp")) ==
    ($warp | .targetStrategy = "ForceIPv6" | .settings.address = ["2606:4700:110:8a10::2/128"]) and
  $selective[0].outbounds[0].tag == "direct" and $global[0].outbounds[0] == $warp and
  $owner[0].routing.rules[4].protocol == ["bittorrent"] and
  $owner[0].routing.rules[5].outboundTag == "padm-ipv6" and
  $owner[0].routing.rules[6].outboundTag == "padm-warp" and
  $owner[0].routing.rules[7].network == "udp"
' >/dev/null || fail 'Xray WARP userspace、同族预解析、固定端点、地址或优先级错误'
jq -en --slurpfile selective "${TEST_ROOT}/warp-selective-sing-box.json" \
    --slurpfile global "${TEST_ROOT}/warp-global-sing-box.json" \
    --slurpfile ipv6 "${TEST_ROOT}/warp-ipv6-sing-box.json" \
    --slurpfile owner "${TEST_ROOT}/warp-owner-sing-box.json" \
    --slurpfile owner6 "${TEST_ROOT}/warp-owner6-sing-box.json" \
    --slurpfile global_owner "${TEST_ROOT}/warp-global-owner-sing-box.json" \
    --arg private "${WARP_PRIVATE}" --arg public "${WARP_PUBLIC}" '
  def warp_span($config):
    ($config.route.rules | map(.outbound) | rindex("padm-ipv6")) as $first |
    ($config.route.rules | map(.outbound) | index("padm-socks5")) as $last |
    $config.route.rules[($first + 1):$last];
  def warp_resolves($config): warp_span($config) | map(select(.action == "resolve"));
  def resolve_routes_paired($config):
    warp_span($config) as $rules |
    all(range(0; $rules | length); . as $i |
      if $rules[$i].action == "resolve" then $rules[$i + 1] ==
        ($rules[$i] | del(.server,.strategy) | .action = "route" | .outbound = "padm-warp")
      else true end);
  $selective[0].endpoints == [{type:"wireguard",tag:"padm-warp",system:false,mtu:1280,
    address:["172.16.0.2/32"],private_key:$private,peers:[{address:"162.159.192.1",port:2408,
      public_key:$public,reserved:[1,2,255],allowed_ips:["0.0.0.0/0","::/0"]}]}] and
  $ipv6[0].endpoints == ($selective[0].endpoints |
    .[0].address = ["2606:4700:110:8a10::2/128"]) and
  ($selective[0].route.rules[-2] | {action,server,strategy}) ==
    {action:"resolve",server:"padm-local",strategy:"ipv4_only"} and
  ($ipv6[0].route.rules[-2] | {action,server,strategy}) ==
    {action:"resolve",server:"padm-local",strategy:"ipv6_only"} and
  (warp_resolves($owner[0]) | map(.server) | unique) == ["padm-dns","padm-hosts","padm-local"] and
  all(warp_resolves($owner[0])[]; .strategy == "ipv4_only") and
  (warp_resolves($owner6[0]) | map(.server) | unique) == ["padm-dns","padm-hosts","padm-local"] and
  all(warp_resolves($owner6[0])[]; .strategy == "ipv6_only") and
  resolve_routes_paired($owner[0]) and resolve_routes_paired($owner6[0]) and
  $selective[0].route.final == "direct" and $global[0].route.final == "padm-warp" and
  ($owner[0].route.rules | map(.outbound) | index("padm-ipv6")) <
    ($owner[0].route.rules | map(.outbound) | index("padm-warp")) and
  ($owner[0].route.rules | map(.outbound) | index("padm-warp")) <
    ($owner[0].route.rules | map(.outbound) | index("padm-socks5")) and
  ($global_owner[0].route.rules | map(.outbound) | index("padm-socks5")) <
    ($global_owner[0].route.rules | map(.outbound) | index("padm-warp")) and
  all($owner[0].route.rules[] | select(.outbound == "padm-warp");
    .type == "logical" and .rules[1].invert == true) and
  $owner[0].dns.final == "padm-local"
' >/dev/null || fail 'sing-box WARP endpoint、同源解析或 OR/Direct/default 优先级错误'
# 用核心的匹配语义检查每类独立命中，防止不同 matcher 被错误组合成 AND。
python3 - "${TEST_ROOT}/domains-sing-box.json" <<'PY'
import json
import sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text())
keys = {"domain", "domain_suffix", "domain_keyword", "rule_set"}

def matches(rule, domain, sets, network):
    checks = []
    if "network" in rule:
        checks.append(network in ([rule["network"]] if isinstance(rule["network"], str)
                                   else rule["network"]))
    if rule.get("type") == "logical":
        children = [matches(child, domain, sets, network) for child in rule["rules"]]
        checks.append(any(children) if rule["mode"] == "or" else all(children))
    for key in keys & rule.keys():
        values = rule[key]
        if key == "domain":
            checks.append(domain in values)
        elif key == "domain_suffix":
            checks.append(any(domain == suffix or domain.endswith("." + suffix.lstrip("."))
                              for suffix in values))
        elif key == "domain_keyword":
            checks.append(any(keyword in domain for keyword in values))
        else:
            checks.append(bool(sets & set(values)))
    return bool(checks) and all(checks)

def route(domain, sets, network):
    for rule in config["route"]["rules"]:
        if rule.get("action") == "sniff":
            continue
        if matches(rule, domain, sets, network):
            return "blocked" if rule.get("action") == "reject" else rule.get("outbound")
    return config["route"]["final"]

requests = [
    ("exact.example.com", set()), ("other.example.com", set()),
    ("example.net", set()), ("sub.example.net", set()), ("myvideo.example.org", set()),
    ("geo.example.org", {"padm-geosite-cn"}),
    ("ads.example.org", {"padm-geosite-category-ads-all"}),
]
for domain, sets in requests:
    assert route(domain, sets, "tcp") == "padm-socks5", (domain, "tcp")
    assert route(domain, sets, "udp") == "blocked", (domain, "udp")
for domain in ("sub.exact.example.com", "notexample.net", "unmatched.example.org"):
    for network in ("tcp", "udp"):
        assert route(domain, set(), network) == "direct", (domain, network)
rule_sets = config["route"]["rule_set"]
assert all(rule["type"] == "remote" and rule["format"] == "binary" and
           rule["url"].startswith("https://raw.githubusercontent.com/SagerNet/sing-geosite/") and
           rule["url"].endswith("/geosite-" + rule["tag"].removeprefix("padm-geosite-") + ".srs") and
           rule["http_client"] == {"engine": "go"} and "download_detour" not in rule
           for rule in rule_sets)
PY
for fixture in routed domains routing-all-global direct-only block-only routing-policy block-ips-only routing-ip-policy block-bt-only routing-bt-policy region-both region-domain region-ip region-owner ipv6-selective ipv6-global ipv6-owner ipv6-global-owner warp-selective warp-global warp-ipv6 warp-owner warp-owner6 warp-global-owner; do
    jq -en --slurpfile source "${TEST_ROOT}/${fixture}-xray.json" \
        --slurpfile runtime "${TEST_ROOT}/runtime-${fixture}-xray.json" '
      $runtime[0].outbounds == $source[0].outbounds and
      $runtime[0].routing.rules == [{type:"field",inboundTag:["padm-traffic-api"],
        outboundTag:"padm-traffic-api"}] + $source[0].routing.rules
    ' >/dev/null || fail "${fixture}: Xray API 规则没有优先于域名路由"
    jq -en --slurpfile source "${TEST_ROOT}/${fixture}-sing-box.json" \
        --slurpfile runtime "${TEST_ROOT}/runtime-${fixture}-sing-box.json" '
      $runtime[0].outbounds == $source[0].outbounds and $runtime[0].route == $source[0].route
    ' >/dev/null || fail "${fixture}: sing-box 流量渲染改变路由"
done
for generator in dockerGenerateCompose dockerGenerateDeployment; do
    "${generator}" "${TEST_ROOT}/base.json" "${TEST_ROOT}/legacy-generated.json"
    for fixture in routed domains dns-only hosts-only routing-all routing-all-global direct-only block-only routing-policy block-ips-only routing-ip-policy block-bt-only routing-bt-policy region-both region-domain region-ip region-owner warp-selective warp-global warp-global-owner; do
        "${generator}" "${TEST_ROOT}/${fixture}.json" "${TEST_ROOT}/routed-generated.json"
        cmp -s "${TEST_ROOT}/legacy-generated.json" "${TEST_ROOT}/routed-generated.json" ||
            fail "${generator}: ${fixture} 意外改变容器能力或宿主端口"
    done
done
dockerGenerateCompose "${TEST_ROOT}/base.json" "${TEST_ROOT}/legacy-compose.json"
dockerGenerateDeployment "${TEST_ROOT}/base.json" "${TEST_ROOT}/legacy-deployment.json"
for fixture in ipv6-selective ipv6-global ipv6-owner ipv6-global-owner; do
    dockerGenerateCompose "${TEST_ROOT}/${fixture}.json" "${TEST_ROOT}/ipv6-compose.json"
    jq -en --slurpfile legacy "${TEST_ROOT}/legacy-compose.json" \
        --slurpfile ipv6 "${TEST_ROOT}/ipv6-compose.json" '
      $ipv6[0].networks.ipv6 == {name:"padm-docker-ipv6",enable_ipv6:true,
        labels:{"io.padm.mode":"docker","io.padm.project":"padm-docker",
          "io.padm.component":"routing-ipv6"}} and
      $ipv6[0].services.xray.networks == ["default","ipv6"] and
      $ipv6[0].services["sing-box"].networks == ["default","ipv6"] and
      ($ipv6[0] | del(.networks.ipv6,.services.xray.networks,
        .services["sing-box"].networks)) == $legacy[0]
    ' >/dev/null || fail "${fixture}: IPv6 编排改变默认网络、辅助服务或容器权限"
    dockerGenerateDeployment "${TEST_ROOT}/${fixture}.json" "${TEST_ROOT}/ipv6-deployment.json"
    cmp -s "${TEST_ROOT}/legacy-deployment.json" "${TEST_ROOT}/ipv6-deployment.json" ||
        fail "${fixture}: IPv6 意外改变部署权限或宿主集成"
done
# API 失败不是“网络不存在”，不能继续清理或吞掉原始错误。
(
    docker() {
        case "$1 $2" in
        'network ls')
            if [[ "${NETWORK_FAILURE}" == list ]]; then
                printf 'fixture-network-list-failed\n' >&2
                return 1
            fi
            printf 'aaaaaaaaaaaa\n'
            ;;
        'network inspect')
            printf 'fixture-network-inspect-failed\n' >&2
            return 1
            ;;
        *) fail '网络查询失败后仍调用删除或其它命令' ;;
        esac
    }
    for NETWORK_FAILURE in list inspect; do
        for action in check cleanup; do
            if dockerIPv6NetworkManage "${action}" >"${LOG}" 2>&1; then
                fail "${action}: 网络 ${NETWORK_FAILURE} 失败被当作成功"
            fi
            grep -Fxq "fixture-network-${NETWORK_FAILURE}-failed" "${LOG}" ||
                fail "${action}: 网络 ${NETWORK_FAILURE} 原始错误丢失"
        done
    done
)
fi

if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" == core-lifecycle ||
    "${PADM_DOCKER_ROUTING_SCOPE:-}" == core-network-lifecycle ||
    "${PADM_DOCKER_ROUTING_SCOPE:-}" == core-policy-lifecycle ]]; then
    # 生命周期只复用关闭后的预期模板，全部独立生成合同由 core-contracts 覆盖。
    if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" != core-network-lifecycle ]]; then
        dockerGenerateXrayConfig "${TEST_ROOT}/base.json" "${TEST_ROOT}/legacy-v3-xray.json"
        dockerGenerateSingBoxConfig "${TEST_ROOT}/base.json" "${TEST_ROOT}/legacy-sing-box.json"
    fi
    for fixture in ipv6-owner routing-bt-policy dns-only; do
        [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" != core-policy-lifecycle || "${fixture}" != ipv6-owner ]] ||
            continue
        [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" != core-network-lifecycle || "${fixture}" != dns-only ]] ||
            continue
        for core in xray sing-box; do
            if [[ "${core}" == xray ]]; then
                dockerGenerateXrayConfig "${TEST_ROOT}/${fixture}.json" \
                    "${TEST_ROOT}/${fixture}-${core}.json"
            else
                dockerGenerateSingBoxConfig "${TEST_ROOT}/${fixture}.json" \
                    "${TEST_ROOT}/${fixture}-${core}.json"
            fi
            dockerTrafficRender "${core}" "${TEST_ROOT}/${fixture}-${core}.json" \
                '{"schema_version":1,"accounts":{}}' \
                >"${TEST_ROOT}/runtime-${fixture}-${core}.json"
        done
    done
fi

snapshot() (
    cd "${root}"
    find config data secrets -type f -printf '%p %m %U %G %n\n' | LC_ALL=C sort
    find config data secrets -type f -print0 | sort -z | xargs -0 -r sha256sum
    for path in compose.json deployment.json deployment.previous.json images.env; do
        [[ ! -f "${path}" ]] || sha256sum "${path}"
    done
)
assertClean() {
    [[ ! -e "${root}/locks/deployment.lock" ]] || fail '路由事务遗留部署锁'
    [[ -z "$(find "${root}" -maxdepth 1 \( -name '.candidate.*' -o -name '.edit.*' -o -name '.protocol.*' \) -print -quit)" ]] ||
        fail '路由事务遗留候选'
}
runEdit() {
    local expected=$1 actual=0
    shift
    (dockerMain edit "$@") >"${LOG}" 2>&1 || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "edit $*: 预期 ${expected}，实际 ${actual}"
    assertClean
    ! grep -Fq "${USERNAME}" "${LOG}" && ! grep -Fq "${PASSWORD}" "${LOG}" ||
        fail '路由编辑泄露 SOCKS5 凭据'
    ! grep -Fq "${WARP_PRIVATE}" "${LOG}" || fail '路由编辑泄露 WARP 私钥'
    ! grep -Fq 'routing-regression-token' "${LOG}" || fail '路由编辑泄露订阅 token'
}
runStatus() {
    local expected=$1 actual=0
    shift
    (dockerMain protocol routing-status "$@") >"${LOG}" 2>"${TEST_ROOT}/status.stderr" || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "routing-status: 预期 ${expected}，实际 ${actual}"
    assertClean
    ! grep -Fq -e "${USERNAME}" -e "${PASSWORD}" -e "${UUID}" -e "${WARP_PRIVATE}" \
        "${LOG}" "${TEST_ROOT}/status.stderr" || fail '路由诊断泄露认证信息'
}
upstreamEditCheck() {
    local kind option oldServer oldPort before composeBefore failure expected trafficBefore
    for kind in dns socks5; do
        runEdit 15 "--${kind}-upstream" 2001:db8::54 5354 --preview
    done
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/warp-owner.json" '' '' configure
    ) >"${LOG}" 2>&1 || fail '初始化上游编辑组合夹具失败'
    assertClean
    for kind in dns socks5; do
        option="--${kind}-upstream"
        cp -- "${root}/config/spec.json" "${TEST_ROOT}/upstream.before"
        oldServer=$(jq -r --arg kind "${kind}" '.routing[$kind].server' "${TEST_ROOT}/upstream.before")
        oldPort=$(jq -r --arg kind "${kind}" '.routing[$kind].port' "${TEST_ROOT}/upstream.before")
        before=$(snapshot)
        trafficBefore=$(sha256sum "${root}/data/traffic/state.json")
        composeBefore=$(cat "${COMPOSE_LOG}")
        runEdit 2 "${option}"
        runEdit 2 "${option}" 2001:db8::54 --preview
        for port in 0 65536 -1 53.5; do
            runEdit 2 "${option}" 2001:db8::54 "${port}" --preview
        done
        runEdit 2 "${option}" 2001:db8::54 5354 --dns-off --preview
        runEdit 2 "${option}" 2001:db8::54 5354 --socks5-off --preview
        runEdit 2 "${option}" 2001:db8::54 5354 --spec "${TEST_ROOT}/upstream.before" --preview
        runEdit 2 "${option}" 2001:db8::54 5354 "${option}" 203.0.113.54 5354 --preview
        for server in proxy.example.com host.docker.internal 127.0.0.1 ::1 '2001:db8::54%eth0'; do
            runEdit 15 "${option}" "${server}" 5354 --preview
        done
        runEdit 15 "${option}" "${oldServer}" "${oldPort}" --preview
        [[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
            fail "${kind}: 拒绝上游输入改变部署或调用 Compose"
        runEdit 0 "${option}" 2001:db8::54 05354 --preview
        [[ "$(snapshot)" == "${before}" ]] || fail "${kind}: 上游预览改变部署"
        failure=health-fail expected=14
        [[ "${kind}" != socks5 ]] || { failure=term expected=143; }
        MODE=${failure}
        rm -f -- "${TEST_ROOT}/failed-once"
        runEdit "${expected}" "${option}" 2001:db8::54 5354 --confirm PADM-DOCKER-EDIT
        MODE=ok
        [[ "$(snapshot)" == "${before}" ]] || fail "${kind}: 上游编辑失败未恢复完整部署"
        runEdit 0 "${option}" 2001:0DB8::54 05354 --confirm PADM-DOCKER-EDIT
        jq -en --arg kind "${kind}" --slurpfile old "${TEST_ROOT}/upstream.before" \
            --slurpfile new "${root}/config/spec.json" '
          $new[0] == ($old[0] | .routing[$kind].server="2001:0DB8::54" | .routing[$kind].port=5354)
        ' >/dev/null || fail "${kind}: 上游编辑改变名单、私有参数或其它规格"
        runStatus 0
        jq -e --arg kind "${kind}" '
          (if $kind == "dns" then .dns else . end) |
          .server == "2001:0DB8::54" and .port == 5354
        ' "${LOG}" >/dev/null || fail "${kind}: 上游状态未显示实际地址和端口"
        runEdit 0 "${option}" "${oldServer}" "${oldPort}" --confirm PADM-DOCKER-EDIT
        cmp -s "${root}/config/spec.json" "${TEST_ROOT}/upstream.before" &&
            [[ "$(sha256sum "${root}/data/traffic/state.json")" == "${trafficBefore}" ]] ||
            fail "${kind}: 上游往返未保留完整规格和累计"
    done
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/base.json" '' '' configure
    ) >"${LOG}" 2>&1 || fail '恢复上游编辑前基线失败'
    assertClean
    printf 'docker-routing-upstreams-regression-ok\n'
}
# 重叠与域名覆盖诊断复用生产只读入口，只在核心合同分片运行一次。
if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" == core-contracts || -z "${PADM_DOCKER_ROUTING_SCOPE:-}" ]]; then
    jq '.routing.direct.domains = ["full:all.example.com","full:suffix.example.net","geosite:category-ads-all"] |
      .routing.block.domains = ["full:all.example.com","full:block.example.com","domain:apple.com",
        "full:region.example.com","domain:suffix.example.net","keyword:standalone"] |
      .routing.ipv6.domains = ["full:all.example.com","full:block.example.com","full:ipv6.example.com"] |
      .routing.warp.domains = ["full:all.example.com","full:block.example.com","full:ipv6.example.com","full:warp.example.com"] |
      .routing.socks5.domains = ["full:all.example.com","full:block.example.com","full:ipv6.example.com",
        "full:warp.example.com","geosite:cn"] |
      .routing.region = {mode:"both",allow_domains:["full:region.example.com","domain:apple.com"]}
    ' "${TEST_ROOT}/warp-owner.json" >"${TEST_ROOT}/overlap-both.json"
    jq '.routing.region.mode = "ip"' "${TEST_ROOT}/overlap-both.json" >"${TEST_ROOT}/overlap-ip.json"
    jq '.routing.direct.domains = ["full:edge.example.net","domain:api.example.net",
        "domain:same.example.org","full:same.example.org","full:notexample.net",
        "full:example.net.evil","keyword:example","geosite:category-ads-all"] |
      .routing.block.domains = ["domain:example.net","domain:private.example.net","full:login.apple.com"] |
      .routing.ipv6.domains = ["full:node.api.example.net"] |
      .routing.warp.domains = ["domain:private.example.net"] |
      .routing.socks5.domains = ["full:client.private.example.net"] |
      .routing.region = {mode:"both",allow_domains:["full:custom.apple.com"]}
    ' "${TEST_ROOT}/warp-owner.json" >"${TEST_ROOT}/coverage.json"
    jq '.routing.direct.domains = ["full:ads.example.net","domain:video.example.net",
        "keyword:advert","keyword:same","full:same.example.org"] |
      .routing.block.domains = ["keyword:ads","keyword:ad","keyword:video","geosite:cn"] |
      .routing.ipv6.domains = ["keyword:vert"] |
      .routing.warp.domains = ["domain:notads.example.org"] |
      .routing.socks5.domains = ["full:videos.example.org","full:unrelated.example.org"] |
      del(.routing.region)
    ' "${TEST_ROOT}/warp-owner.json" >"${TEST_ROOT}/keyword-coverage.json"
    for fixture in base overlap-both overlap-ip coverage keyword-coverage routed ipv6-global warp-global; do
        (
            trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
            dockerAcquireDeploymentLock
            dockerConfigureApply "${TEST_ROOT}/${fixture}.json" '' '' configure
        ) >"${LOG}" 2>&1 || fail "${fixture}: 初始化诊断夹具失败"
        assertClean
        if [[ "${fixture}" == base ]]; then
            jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{($uuid):{
              name:"routing",upload:17,download:19,limit_bytes:100,baseline:{}}}}' | dockerTrafficWriteState
        fi
        before=$(snapshot)
        runStatus 0
        if [[ "${fixture}" == overlap-* ]]; then
            jq -e --arg fixture "${fixture}" '
              .direct_block_overlaps == ["full:all.example.com"] and
              .domain_rule_overlaps == ([
                {rule:"domain:apple.com",policies:["direct","block"],winner:"direct"},
                {rule:"full:all.example.com",policies:["direct","block","ipv6","warp","socks5"],winner:"direct"},
                {rule:"full:block.example.com",policies:["block","ipv6","warp","socks5"],winner:"block"},
                {rule:"full:ipv6.example.com",policies:["ipv6","warp","socks5"],winner:"ipv6"},
                {rule:"full:region.example.com",policies:["direct","block"],winner:"direct"},
                {rule:"full:warp.example.com",policies:["warp","socks5"],winner:"warp"}
              ] + if $fixture == "overlap-both" then
                [{rule:"geosite:cn",policies:["block","socks5"],winner:"block"}] else [] end)
            ' "${LOG}" >/dev/null || fail "${fixture}: 精确重叠、优先级或区域合成错误"
            jq -e '.domain_rule_coverages == [{
              narrow_rule:"full:suffix.example.net",broad_rule:"domain:suffix.example.net",
              policies:["direct","block"],winner:"direct"}]' "${LOG}" >/dev/null ||
                fail "${fixture}: 精确域名与后缀覆盖未被诊断"
        elif [[ "${fixture}" == keyword-coverage ]]; then
            jq -e '
              .domain_rule_overlaps == [] and .domain_rule_coverages == [] and
              .domain_rule_keyword_coverages == ([
                {narrow_rule:"domain:notads.example.org",broad_rule:"keyword:ad",
                  policies:["block","warp"],winner:"block"},
                {narrow_rule:"domain:notads.example.org",broad_rule:"keyword:ads",
                  policies:["block","warp"],winner:"block"},
                {narrow_rule:"domain:video.example.net",broad_rule:"keyword:video",
                  policies:["direct","block"],winner:"direct"},
                {narrow_rule:"full:ads.example.net",broad_rule:"keyword:ad",
                  policies:["direct","block"],winner:"direct"},
                {narrow_rule:"full:ads.example.net",broad_rule:"keyword:ads",
                  policies:["direct","block"],winner:"direct"},
                {narrow_rule:"full:videos.example.org",broad_rule:"keyword:video",
                  policies:["block","socks5"],winner:"block"},
                {narrow_rule:"keyword:advert",broad_rule:"keyword:ad",
                  policies:["direct","block"],winner:"direct"},
                {narrow_rule:"keyword:advert",broad_rule:"keyword:vert",
                  policies:["direct","ipv6"],winner:"direct"}
              ] | sort_by(.narrow_rule,.broad_rule))
            ' "${LOG}" >/dev/null || fail 'keyword 包含、跨策略优先级或同策略排除错误'
        elif [[ "${fixture}" == coverage ]]; then
            jq -e '
              .domain_rule_overlaps == [{rule:"domain:private.example.net",
                policies:["block","warp"],winner:"block"}] and
              .domain_rule_coverages == ([
                {narrow_rule:"domain:api.example.net",broad_rule:"domain:example.net",
                  policies:["direct","block"],winner:"direct"},
                {narrow_rule:"domain:private.example.net",broad_rule:"domain:example.net",
                  policies:["block","warp"],winner:"block"},
                {narrow_rule:"full:client.private.example.net",broad_rule:"domain:example.net",
                  policies:["block","socks5"],winner:"block"},
                {narrow_rule:"full:client.private.example.net",broad_rule:"domain:private.example.net",
                  policies:["block","warp","socks5"],winner:"block"},
                {narrow_rule:"full:edge.example.net",broad_rule:"domain:example.net",
                  policies:["direct","block"],winner:"direct"},
                {narrow_rule:"full:login.apple.com",broad_rule:"domain:apple.com",
                  policies:["direct","block"],winner:"direct"},
                {narrow_rule:"full:node.api.example.net",broad_rule:"domain:api.example.net",
                  policies:["direct","ipv6"],winner:"direct"},
                {narrow_rule:"full:node.api.example.net",broad_rule:"domain:example.net",
                  policies:["block","ipv6"],winner:"block"}
              ] | sort_by(.narrow_rule,.broad_rule))
            ' "${LOG}" >/dev/null ||
                fail '域名层级、五策略、区域默认例外、边界或同策略去重诊断错误'
        else
            jq -e '.domain_rule_overlaps == [] and .domain_rule_coverages == [] and
              .domain_rule_keyword_coverages == []' "${LOG}" >/dev/null ||
                fail "${fixture}: 关闭或全局出站被误报为域名重叠或覆盖"
        fi
        [[ "$(snapshot)" == "${before}" ]] || fail "${fixture}: 只读诊断改变部署"
    done
    if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" == core-contracts ]]; then
        printf 'docker-routing-core-contracts-regression-ok\n'
        exit 0
    fi
fi
# 域名名单共用原位替换检查，结束后还原现有夹具，不另建生命周期。
domainsReplaceCheck() {
    local kind=$1 option="--${1}-domains-replace" original="${TEST_ROOT}/${1}-replace.before"
    local replacement="${TEST_ROOT}/${1}-replace.json" field=domains addOption removeOption
    local oldRule oldInput firstRule before composeBefore
    local failure expected core dataBefore
    local newInput=' Full:Replacement.Example.ORG ' newRule='full:replacement.example.org'
    if [[ "${kind}" == region ]]; then
        option=--region-allow-replace field=allow_domains
        addOption=--region-allow-add removeOption=--region-allow-remove
    else
        addOption="--${kind}-domains-add" removeOption="--${kind}-domains-remove"
    fi
    cp -- "${root}/config/spec.json" "${original}"
    oldRule=$(jq -er --arg kind "${kind}" --arg field "${field}" \
        '.routing[$kind][$field][1]' "${original}")
    firstRule=$(jq -er --arg kind "${kind}" --arg field "${field}" \
        '.routing[$kind][$field][0]' "${original}")
    oldInput=${oldRule#domain:}
    oldInput=" ${oldInput^^} "
    jq --arg kind "${kind}" --arg field "${field}" --arg new "${newRule}" \
        '.routing[$kind][$field][1]=$new' \
        "${original}" >"${replacement}"
    before=$(snapshot)
    composeBefore=$(cat "${COMPOSE_LOG}")
    runEdit 2 "${option}"
    runEdit 2 "${option}" "${oldRule}" --preview
    runEdit 2 "${option}" '' "${newInput}" --preview
    runEdit 2 "${option}" "${oldInput}" '' --preview
    runEdit 2 "${option}" "${oldInput}" "${newInput}"
    runEdit 2 "${option}" "${oldInput}" "${newInput}" --confirm invalid
    runEdit 2 "${option}" 'regexp:.*' "${newInput}" --preview
    runEdit 2 "${option}" "${oldInput}" 'regexp:.*' --preview
    runEdit 2 "${option}" "${oldRule},${oldRule}" "${newInput}" --preview
    runEdit 2 "${option}" "${oldInput}" "${newRule},${newRule}" --preview
    runEdit 2 "${option}" "${oldRule},${firstRule}" "${newInput}" --preview
    runEdit 2 "${option}" "${oldInput}" "${newRule},other.example.org" --preview
    runEdit 2 "${option}" "${oldInput}," "${newInput}" --preview
    runEdit 2 "${option}" "${oldInput}" ",${newInput}" --preview
    runEdit 2 "${option}" "${oldInput}" "${newInput}" "${option}" "${oldInput}" "${newInput}" --preview
    runEdit 2 "${option}" "${oldInput}" "${newInput}" "${addOption}" 'other.example.org' --preview
    runEdit 2 "${addOption}" 'other.example.org' "${option}" "${oldInput}" "${newInput}" --preview
    runEdit 2 "${option}" "${oldInput}" "${newInput}" "${removeOption}" "${oldRule}" --preview
    runEdit 2 "${option}" "${oldInput}" "${newInput}" --dns-off --preview
    runEdit 2 --dns-off "${option}" "${oldInput}" "${newInput}" --preview
    runEdit 2 "${option}" "${oldInput}" "${newInput}" --spec "${original}" --preview
    runEdit 2 "${option}" "${oldInput}" "${newInput}" --http01 enable --preview
    runEdit 15 "${option}" 'missing.example.org' "${newInput}" --confirm PADM-DOCKER-EDIT
    runEdit 15 "${option}" "${firstRule#full:}" "${newInput}" --confirm PADM-DOCKER-EDIT
    runEdit 15 "${option}" "${oldInput}" "${firstRule^^}" --confirm PADM-DOCKER-EDIT
    runEdit 15 "${option}" "${oldInput}" "${oldInput}" --confirm PADM-DOCKER-EDIT
    if [[ "${kind}" == region ]]; then
        runEdit 15 "${option}" 'dl.google.com' "${newInput}" --confirm PADM-DOCKER-EDIT
        runEdit 2 "${option}" "${oldInput}" "${newInput}" --region domain --preview
        runEdit 2 --region domain "${option}" "${oldInput}" "${newInput}" --preview
        runEdit 2 "${option}" "${oldInput}" "${newInput}" --region-allow other.example.org --preview
        runEdit 2 "${option}" "${oldInput}" "${newInput}" --region-off --preview
        runEdit 2 "${option}" "${oldInput}" "${newInput}" --block-bt-off --preview
        runEdit 2 "${option}" "${oldInput}" "${newInput}" --warp-global --preview
    fi
    [[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
        fail "${kind}: 单项替换参数、缺旧、重复新或同值拒绝改变部署或调用 Compose"
    runEdit 0 "${option}" "${oldInput}" "${newInput}" --preview
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerSetupRead() { printf -v "$1" '%s' n; }
        dockerAcquireDeploymentLock
        dockerConfigureApply "${replacement}" '' '' interactive
    ) >"${LOG}" 2>&1 || fail "${kind}: 单项替换确认取消失败"
    assertClean
    [[ "$(snapshot)" == "${before}" ]] || fail "${kind}: 单项替换预览或取消改变部署"
    # 每类仅注入一个故障，合计覆盖健康失败及两种中断，保留完整恢复证据。
    case "${kind}" in
    dns|warp|region) failure=health-fail; expected=14 ;;
    direct) failure=int; expected=130 ;;
    block|ipv6|socks5) failure=term; expected=143 ;;
    esac
    MODE=${failure}
    rm -f -- "${TEST_ROOT}/failed-once"
    runEdit "${expected}" "${option}" "${oldInput}" "${newInput}" --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] ||
        fail "${kind}/${failure}: 单项替换未恢复完整规格、私有字段、运行配置与非空流量"
    MODE=ok
    for core in xray sing-box; do
        cp -- "${root}/config/${core}/config.json" "${TEST_ROOT}/${kind}-replace-${core}.before"
    done
    (dockerMain protocol links) >"${TEST_ROOT}/${kind}-replace-links.before"
    dataBefore=$(find "${root}/data" -type f -print0 | sort -z | xargs -0 -r sha256sum)
    runEdit 0 "${option}" "${oldInput}" "${newInput}" --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile expected "${replacement}" --slurpfile actual "${root}/config/spec.json" \
        '$actual==$expected' >/dev/null ||
        fail "${kind}: 单项替换没有规范化中间项、保持顺序或改写其它完整规格"
    runStatus 0
    jq -e --arg kind "${kind}" --arg field "${field}" --slurpfile expected "${replacement}" \
        --argjson defaults "${REGION_DEFAULTS}" '
      (if $kind=="socks5" then .domain_rules
       elif $kind=="dns" then .dns.domain_rules
       elif $kind=="direct" or $kind=="block" then .[$kind].domain_rules
       else .[$kind][$field] end) == $expected[0].routing[$kind][$field] and
      (if $kind=="region" then
         .region.mode==$expected[0].routing.region.mode and .region.default_allow_domains==$defaults
       else true end)
    ' "${LOG}" >/dev/null || fail "${kind}: 单项替换状态未投影有序名单"
    for core in xray sing-box; do
        jq -en --arg core "${core}" --slurpfile old "${TEST_ROOT}/${kind}-replace-${core}.before" \
            --slurpfile new "${root}/config/${core}/config.json" '
          if $core=="xray" then ($old[0]|del(.routing,.dns))==($new[0]|del(.routing,.dns))
          else ($old[0]|del(.route,.dns))==($new[0]|del(.route,.dns)) end
        ' >/dev/null || fail "${kind}/${core}: 单项替换改写核心监听、认证或 WARP 私有字段"
        if [[ "${kind}" == region ]]; then
            jq -e --arg core "${core}" --argjson defaults "${REGION_DEFAULTS}" '
              if $core=="xray" then
                (.routing.rules | map(select(.outboundTag=="direct").domain // []) | add) as $direct |
                all($defaults[]; . as $rule | ($direct | index($rule)) != null)
              else
                ([.. | objects | .domain_suffix? // empty | .[]]) as $direct |
                all($defaults[] | ltrimstr("domain:"); . as $rule | ($direct | index($rule)) != null)
              end
            ' "${root}/config/${core}/config.json" >/dev/null ||
                fail "region/${core}: 替换默认同名自定义副本改变固定八条例外"
        fi
    done
    (dockerMain protocol links) >"${TEST_ROOT}/${kind}-replace-links.after"
    cmp -s "${TEST_ROOT}/${kind}-replace-links.before" "${TEST_ROOT}/${kind}-replace-links.after" &&
        [[ "$(find "${root}/data" -type f -print0 | sort -z | xargs -0 -r sha256sum)" == "${dataBefore}" ]] ||
        fail "${kind}: 单项替换改变分享 URI、订阅或累计流量"
    runEdit 0 "${option}" "${newRule}" "${oldRule}" --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile old "${original}" --slurpfile actual "${root}/config/spec.json" \
        '$actual==$old' >/dev/null || fail "${kind}: 单项替换没有还原原组合规格"
    printf 'docker-routing-%s-domains-replace-regression-ok\n' "${kind}"
}
# 选择性出站共用增量合同，SOCKS5 以非空域名数组表示选择性模式。
selectiveDomainsIncrementalCheck() {
    local kind=$1 retained=$2 option action csv domains failure expected before composeBefore core allCsv
    local original="${TEST_ROOT}/${kind}-incremental.before"
    local addCsv=' Full:Exact.Example.COM , Example.NET , KEYWORD:Video , GEOSITE:CN , Full:New.Example.ORG , New.Example.ORG , Keyword:Next_Video , geosite:category-ads-all , full:new.example.org '
    local added='["full:exact.example.com","domain:example.net","keyword:video","geosite:cn","full:new.example.org","domain:new.example.org","keyword:next_video","geosite:category-ads-all"]'
    local removeCsv=' Full:New.Example.ORG , Example.NET , KEYWORD:Video , GEOSITE:CN , full:new.example.org '
    local remaining='["full:exact.example.com","domain:new.example.org","keyword:next_video","geosite:category-ads-all"]'
    local boundaryCsv overlimitCsv
    boundaryCsv=$(jq -nr '[range(0;252) | "selective-boundary-\(.).example.org"] | join(",")')
    overlimitCsv=$(jq -nr '[range(0;257) | "selective-boundary-\(.).example.org"] | join(",")')
    cp -- "${root}/config/spec.json" "${original}"
    jq -e --arg kind "${kind}" --argjson domains "${IPV6_DOMAINS}" '
      .routing[$kind].domains==$domains and
      (if $kind=="socks5" then .routing.dns != null else
        .routing[$kind].mode=="selective" and
        (.routing.direct.domains | index("full:other.example.com")) != null end)
    ' "${original}" >/dev/null || fail "${kind}: 增量合同没有使用既有 selective 组合夹具"
    domainsReplaceCheck "${kind}"
    before=$(snapshot)
    composeBefore=$(cat "${COMPOSE_LOG}")
    for action in add remove; do
        option="--${kind}-domains-${action}"
        runEdit 2 "${option}"
        runEdit 2 "${option}" '' --preview
        runEdit 2 "${option}" 'regexp:.*' --preview
        runEdit 2 "${option}" "${overlimitCsv}" --preview
        runEdit 2 "${option}" 'example.net' "--${kind}-off" --preview
        runEdit 2 "${option}" 'example.net' "${option}" 'example.org' --preview
        runEdit 2 "${option}" 'example.net' --dns-off --preview
        if [[ "${kind}" == socks5 ]]; then
            runEdit 2 "${option}" 'example.net' --spec "${original}" --preview
            runEdit 2 "${option}" 'example.net' --http01 enable --preview
            runEdit 2 "${option}" 'example.net' --socks5 "${INPUT}" --preview
            runEdit 2 --socks5 "${INPUT}" "${option}" 'example.net' --preview
        fi
    done
    [[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
        fail "${kind}: 无效增量参数改变部署或调用 Compose"
    for action in add remove; do
        option="--${kind}-domains-${action}"
        csv=${addCsv}
        [[ "${action}" != remove ]] || csv=${removeCsv}
        before=$(snapshot)
        runEdit 0 "${option}" "${csv}" --preview
        domains=${added}
        [[ "${action}" != remove ]] || domains=${remaining}
        jq --arg kind "${kind}" --argjson domains "${domains}" '.routing[$kind].domains=$domains' \
            "${original}" >"${TEST_ROOT}/${kind}-incremental-cancel.json"
        (
            trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
            dockerSetupRead() { printf -v "$1" '%s' n; }
            dockerAcquireDeploymentLock
            dockerConfigureApply "${TEST_ROOT}/${kind}-incremental-cancel.json" '' '' interactive
        ) >"${LOG}" 2>&1 || fail "${kind}/${action}: 确认取消失败"
        assertClean
        [[ "$(snapshot)" == "${before}" ]] || fail "${kind}/${action}: 预览或取消改变部署"
        if [[ "${action}" == remove ]]; then
            composeBefore=$(cat "${COMPOSE_LOG}")
            runEdit 15 "${option}" 'exact.example.com' --confirm PADM-DOCKER-EDIT
            runEdit 15 "${option}" "${csv},full:other.example.com" --confirm PADM-DOCKER-EDIT
            [[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
                fail "${kind}: 缺项/部分跨 owner 缺项删除停服或把 full 当作 domain 规则"
        fi
        for failure in health-fail int term; do
            # SOCKS5 两个动作和替换合同各验一种故障，避免重复整套恢复。
            [[ "${kind}" != socks5 || ( "${action}" == add && "${failure}" == health-fail ) ||
                ( "${action}" == remove && "${failure}" == int ) ]] || continue
            MODE=${failure}
            rm -f -- "${TEST_ROOT}/failed-once"
            expected=14
            [[ "${failure}" != int ]] || expected=130
            [[ "${failure}" != term ]] || expected=143
            runEdit "${expected}" "${option}" "${csv}" --confirm PADM-DOCKER-EDIT
            [[ "$(snapshot)" == "${before}" ]] ||
                fail "${kind}/${action}/${failure}: 未恢复私有字段、其它路由、编排与非空流量"
        done
        MODE=ok
        runEdit 0 "${option}" "${csv}" --confirm PADM-DOCKER-EDIT
        [[ "${action}" != add ]] || runEdit 0 "${option}" "${csv}" --confirm PADM-DOCKER-EDIT
        jq -en --arg kind "${kind}" --argjson domains "${domains}" --slurpfile old "${original}" \
            --slurpfile actual "${root}/config/spec.json" '
          $actual[0] == ($old[0] | .routing[$kind].domains=$domains)
        ' >/dev/null || fail "${kind}/${action}: 未保持四类规则稳定次序、完整身份或改写模式/私有字段"
        runStatus 0
        jq -e --arg kind "${kind}" --argjson domains "${domains}" '
          if $kind=="socks5" then .mode=="domains" and .domain_rules==$domains
          else .[$kind].mode=="selective" and .[$kind].domains==$domains end
        ' "${LOG}" >/dev/null || fail "${kind}/${action}: 状态没有投影剩余有序规则"
    done
    runEdit 0 "--${kind}-domains-add" "${boundaryCsv}" --confirm PADM-DOCKER-EDIT
    jq -e --arg kind "${kind}" --argjson domains "${remaining}" '
      .routing[$kind].domains == ($domains +
        [range(0;252) | "domain:selective-boundary-\(.).example.org"])
    ' "${root}/config/spec.json" >/dev/null || fail "${kind}: 合并 256 项未保留历史次序"
    before=$(snapshot)
    runEdit 0 "--${kind}-domains-add" 'FULL:EXACT.EXAMPLE.COM,selective-boundary-251.example.org' --preview
    composeBefore=$(cat "${COMPOSE_LOG}")
    runEdit 15 "--${kind}-domains-add" 'selective-boundary-252.example.org' --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
        fail "${kind}: 合并超过 256 项改变部署或调用 Compose"
    allCsv=$(jq -r --arg kind "${kind}" '.routing[$kind].domains | join(",")' "${root}/config/spec.json")
    runEdit 0 "--${kind}-domains-remove" "${allCsv}" --confirm PADM-DOCKER-EDIT
    jq -en --arg kind "${kind}" --slurpfile old "${original}" \
        --slurpfile actual "${root}/config/spec.json" '
      $actual[0] == ($old[0] | del(.routing[$kind]))
    ' >/dev/null || fail "${kind}: 删空没有关闭该子项或改变其它策略"
    runStatus 0
    jq -e --arg kind "${kind}" '
      if $kind=="socks5" then .mode=="direct" and .domain_rules==[] and .server==null and .port==null
      else has($kind) | not end
    ' "${LOG}" >/dev/null ||
        fail "${kind}: 删空后状态仍保留对应子项"
    for core in xray sing-box; do
        cmp -s "${root}/config/${core}/config.json" "${TEST_ROOT}/runtime-${retained}-${core}.json" ||
            fail "${kind}/${core}: 删空遗留核心规则、出站或改变其它路由"
    done
    if [[ "${kind}" == socks5 ]]; then
        runEdit 0 --socks5 "${PRIVATE_ROOT}/socks5-selective.json" --confirm PADM-DOCKER-EDIT
    elif [[ "${kind}" == warp ]]; then
        runEdit 0 --warp "${WARP_INPUT}" --confirm PADM-DOCKER-EDIT
    else
        runEdit 0 --ipv6 selective --ipv6-domains 'full:exact.example.com,example.net,keyword:video,geosite:cn' \
            --confirm PADM-DOCKER-EDIT
    fi
    cmp -s "${root}/config/spec.json" "${original}" ||
        fail "${kind}: 增量合同没有恢复原组合规格"
    printf 'docker-routing-%s-domains-incremental-regression-ok\n' "${kind}"
}
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    # CSV 定向入口直接安装 IP 段结束后的组合夹具，保留原 TLS 和非空流量。
    if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" == domains-direct-block-csv ]]; then
        dockerConfigureApply "${TEST_ROOT}/routing-ip-policy.json" '' '' configure
    else
        dockerConfigureApply "${TEST_ROOT}/base.json" '' '' configure
    fi
) >"${LOG}" 2>&1 || fail '初始化路由夹具失败'
assertClean
jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{($uuid):{
  name:"routing",upload:17,download:19,limit_bytes:0,baseline:{}}}}' | dockerTrafficWriteState
if [[ -z "${PADM_DOCKER_ROUTING_SCOPE:-}" || "${PADM_DOCKER_ROUTING_SCOPE:-}" == core-workflow ||
    ( "${PADM_DOCKER_ROUTING_SCOPE:-}" == core-policy-lifecycle && "${ROUTING_BRANCH}" == socks5 ) ]]; then
    upstreamEditCheck
fi
# 域名工作流保留非空流量和原事务断言，只跳过其它能力的生命周期。
if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-workflow &&
    "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-dns-hosts &&
    "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-direct-block &&
    "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-direct-block-ip &&
    "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-direct-block-csv ]]; then
if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" != core-policy-lifecycle &&
    ( -z "${ROUTING_BRANCH}" || "${ROUTING_BRANCH}" == ipv6 ) ]]; then
# 中继交接恢复只 stop 部分服务，没有 Compose down，仍须清理 IPv6→off 的空辅助网络。
(
    trap 'dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerBackupConfiguration ipv6-restore
    restoreLog="${TEST_ROOT}/ipv6-restore.log"
    dockerRealityStreamStopServices() { printf 'stop:%s\n' "$*" >>"${restoreLog}"; }
    dockerComposeRun() {
        [[ "$1" == up ]] || fail '中继恢复意外走 Compose down'
        printf 'compose:%s\n' "$1" >>"${restoreLog}"
    }
    dockerIPv6NetworkManage() {
        [[ "$#" -eq 1 && "$1" == cleanup ]] || fail '恢复调用了错误网络动作或项目'
        jq -e '.routing.ipv6 == null' "${root}/config/spec.json" >/dev/null &&
            jq -e '.networks.ipv6 == null' "${root}/compose.json" >/dev/null ||
            fail '尚未恢复 off 编排就清理网络'
        printf 'network:cleanup\n' >>"${restoreLog}"
    }
    for mode in off ipv6; do
        : >"${restoreLog}"
        if [[ "${mode}" == ipv6 ]]; then
            dockerGenerateCompose "${TEST_ROOT}/ipv6-global.json" "${root}/compose.json"
        fi
        DOCKER_CONFIG_SWITCHED=1 DOCKER_CONFIG_STREAM_TRANSITION=1
        dockerRestoreConfiguration
        [[ "${DOCKER_CONFIG_SWITCHED}" == 0 && "${DOCKER_CONFIG_STREAM_TRANSITION}" == 0 ]] ||
            fail '恢复后没有清除切换标记'
        printf 'stop:nginx xray\ncompose:up\n' >"${TEST_ROOT}/ipv6-restore.expected"
        [[ "${mode}" != ipv6 ]] || printf 'network:cleanup\n' >>"${TEST_ROOT}/ipv6-restore.expected"
        cmp -s "${restoreLog}" "${TEST_ROOT}/ipv6-restore.expected" ||
            fail "${mode}→off: 部分服务恢复顺序或网络清理触达错误"
    done
)
assertClean
fi
if [[ ( -z "${PADM_DOCKER_ROUTING_SCOPE:-}" || "${PADM_DOCKER_ROUTING_SCOPE:-}" == warp ||
    "${PADM_DOCKER_ROUTING_SCOPE:-}" == core-workflow ||
    "${PADM_DOCKER_ROUTING_SCOPE:-}" == core-lifecycle ||
    "${PADM_DOCKER_ROUTING_SCOPE:-}" == core-network-lifecycle ) &&
    ( -z "${ROUTING_BRANCH}" || "${ROUTING_BRANCH}" == warp ) ]]; then
    before=$(snapshot)
    runEdit 0 --warp "${WARP_INPUT}" --preview
    runEdit 0 --warp-off --preview
    runEdit 2 --warp
    runEdit 2 --warp "${WARP_INPUT}"
    runEdit 2 --warp "${WARP_INPUT}" --confirm invalid
    runEdit 2 --warp "${WARP_INPUT}" --warp-off --preview
    runEdit 2 --warp-off --warp-off --preview
    runEdit 2 --warp "${WARP_INPUT}" --warp "${WARP_INPUT}" --preview
    runEdit 2 --warp "${WARP_INPUT}" --socks5-off --preview
    runEdit 2 --warp "${WARP_INPUT}" --spec "${TEST_ROOT}/base.json" --preview
    runEdit 2 --warp "${WARP_INPUT}" --http01 enable --preview
    runEdit 2 --warp-domains
    runEdit 2 --warp-domains '' --preview
    runEdit 2 --warp-domains 'regexp:.*' --preview
    runEdit 2 --warp-domains 'example.net'
    runEdit 2 --warp-family
    runEdit 2 --warp-family both --preview
    runEdit 2 --warp-global --warp-off --preview
    runEdit 2 --warp-off --warp-family ipv6 --preview
    runEdit 2 --warp-domains 'example.net' --warp "${WARP_INPUT}" --preview
    runEdit 2 --warp-global --socks5-global --preview
    runEdit 2 --warp-family ipv6 --http01 enable --preview
    runEdit 2 --warp-global --spec "${TEST_ROOT}/base.json" --preview
    runEdit 15 --warp-domains 'example.net' --preview
    runEdit 15 --warp-global --preview
    runEdit 15 --warp-family ipv6 --preview
    composeBefore=$(cat "${COMPOSE_LOG}")
    for action in add remove; do
        runEdit 15 "--warp-domains-${action}" 'example.net' --confirm PADM-DOCKER-EDIT
    done
    runEdit 15 --warp-domains-replace 'example.net' 'replacement.example.org' --confirm PADM-DOCKER-EDIT
    [[ "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] || fail '未启用 WARP 域名增删调用 Compose'
    runEdit 15 --spec "${TEST_ROOT}/warp-global.json" --confirm PADM-DOCKER-EDIT
    cp -- "${WARP_INPUT}" "${PRIVATE_ROOT}/warp-bad.json"
    chmod 0640 "${PRIVATE_ROOT}/warp-bad.json"
    runEdit 15 --warp "${PRIVATE_ROOT}/warp-bad.json" --preview
    chmod 0600 "${PRIVATE_ROOT}/warp-bad.json"
    jq '.reserved = [1,2,256]' "${WARP_INPUT}" >"${PRIVATE_ROOT}/warp-bad.json"
    runEdit 15 --warp "${PRIVATE_ROOT}/warp-bad.json" --preview
    ln -s "${WARP_INPUT}" "${PRIVATE_ROOT}/warp-link.json"
    runEdit 15 --warp "${PRIVATE_ROOT}/warp-link.json" --preview
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerSetupRead() { printf -v "$1" '%s' n; }
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/warp-selective.json" '' '' interactive
    ) >"${LOG}" 2>&1 || fail 'WARP 取消失败'
    assertClean
    [[ "$(snapshot)" == "${before}" ]] || fail 'WARP 预览、取消或非法输入改变完整部署'
    runEdit 0 --warp "${WARP_INPUT}" --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile expected "${TEST_ROOT}/warp-selective.json" --slurpfile actual "${root}/config/spec.json" \
        '$actual == $expected' >/dev/null || fail 'WARP 导入改变其它规格'
    runEdit 0 --warp-domains-remove 'full:exact.example.com,example.net,keyword:video,geosite:cn' \
        --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile old "${TEST_ROOT}/base.json" --slurpfile actual "${root}/config/spec.json" \
        '$actual==$old' >/dev/null || fail '删空唯一 WARP 域名没有关闭并清理空 routing'
    runStatus 0
    jq -e 'has("warp") | not' "${LOG}" >/dev/null || fail '唯一 WARP 删空后状态仍保留子项'
    runEdit 0 --warp "${WARP_INPUT}" --confirm PADM-DOCKER-EDIT
    runStatus 0
    jq -e --argjson domains "${IPV6_DOMAINS}" '
      .warp == {mode:"selective",family:"ipv4",domains:$domains}
    ' "${LOG}" >/dev/null || fail 'WARP 状态未按无秘密合同投影'
    before=$(snapshot)
    runEdit 2 --warp-domains 'full:changed.example.com' --warp-global --preview
    runEdit 2 --warp-family ipv4 --warp-family ipv6 --preview
    runEdit 2 --warp-family IPv6 --preview
    runEdit 0 --warp-domains ' Full:Changed.Example.Com , domain:example.net ' --preview
    runEdit 0 --warp-family ipv6 --preview
    runEdit 0 --warp-global --preview
    jq '.routing.warp.mode = "global" | .routing.warp.domains = []' \
        "${root}/config/spec.json" >"${TEST_ROOT}/warp-daily-cancel.json"
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerSetupRead() { printf -v "$1" '%s' n; }
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/warp-daily-cancel.json" '' '' interactive
    ) >"${LOG}" 2>&1 || fail 'WARP 日常编辑取消失败'
    assertClean
    [[ "$(snapshot)" == "${before}" ]] || fail 'WARP 日常编辑预览、取消或参数拒绝改变完整部署'
    runEdit 0 --warp-domains ' Full:Changed.Example.Com , domain:example.net ' --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile before "${TEST_ROOT}/warp-selective.json" --slurpfile actual "${root}/config/spec.json" '
      ($before[0] | .routing.warp.mode = "selective" |
        .routing.warp.domains = ["full:changed.example.com","domain:example.net"]) == $actual[0]
    ' >/dev/null || fail 'WARP 域名日常编辑未保留私有字段或规范化列表'
    cp -- "${root}/config/spec.json" "${TEST_ROOT}/warp-daily-before.json"
    runEdit 0 --warp-family ipv6 --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile before "${TEST_ROOT}/warp-daily-before.json" \
        --slurpfile actual "${root}/config/spec.json" '
      ($before[0] | .routing.warp.family = "ipv6") == $actual[0]
    ' >/dev/null || fail 'WARP 地址族日常编辑改写模式、域名或其它规格'
    cp -- "${root}/config/spec.json" "${TEST_ROOT}/warp-daily-before.json"
    runEdit 0 --warp-global --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile before "${TEST_ROOT}/warp-daily-before.json" \
        --slurpfile actual "${root}/config/spec.json" '
      ($before[0] | .routing.warp.mode = "global" | .routing.warp.domains = []) == $actual[0]
    ' >/dev/null || fail 'WARP 全局日常编辑改写地址族或其它规格'
    cp -- "${root}/config/spec.json" "${TEST_ROOT}/warp-daily-before.json"
    runEdit 0 --warp-family ipv4 --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile before "${TEST_ROOT}/warp-daily-before.json" \
        --slurpfile actual "${root}/config/spec.json" '
      ($before[0] | .routing.warp.family = "ipv4") == $actual[0]
    ' >/dev/null || fail 'WARP 全局地址族编辑意外改变模式或域名'
    cp -- "${root}/config/spec.json" "${TEST_ROOT}/warp-daily-before.json"
    runEdit 0 --warp-domains 'Example.NET,Full:Changed.Example.Com,example.net' --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile before "${TEST_ROOT}/warp-daily-before.json" \
        --slurpfile actual "${root}/config/spec.json" '
      ($before[0] | .routing.warp.mode = "selective" |
        .routing.warp.domains = ["domain:example.net","full:changed.example.com"]) == $actual[0]
    ' >/dev/null || fail 'WARP 全局转域名未稳定去重或保留其它规格'
    [[ "$(snapshot)" != "${before}" ]] || fail 'WARP 日常编辑未产生预期配置变化'
    runEdit 0 --warp "${WARP_INPUT}" --confirm PADM-DOCKER-EDIT
    before=$(snapshot)
    runEdit 15 --spec "${TEST_ROOT}/base.json" --confirm PADM-DOCKER-EDIT
    runEdit 15 --spec "${TEST_ROOT}/warp-global.json" --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail '普通 --spec 绕过 WARP 冻结'
    jq '.mode="global" | .domains=[] | .family="ipv6"' "${WARP_INPUT}" >"${PRIVATE_ROOT}/warp-global.json"
    chmod 0600 "${PRIVATE_ROOT}/warp-global.json"
    runEdit 0 --warp "${PRIVATE_ROOT}/warp-global.json" --confirm PADM-DOCKER-EDIT
    jq -e '.routing.warp.mode == "global" and .routing.warp.family == "ipv6" and
      .routing.warp.domains == []' "${root}/config/spec.json" >/dev/null ||
        fail 'WARP 替换没有替换模式、地址族或列表'
    before=$(snapshot)
    composeBefore=$(cat "${COMPOSE_LOG}")
    for action in add remove; do
        runEdit 15 "--warp-domains-${action}" 'example.net' --confirm PADM-DOCKER-EDIT
    done
    runEdit 15 --warp-domains-replace 'example.net' 'replacement.example.org' --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
        fail '全局 WARP 域名增删未拒绝或触发 Compose'
    runEdit 0 --warp-off --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile old "${TEST_ROOT}/base.json" --slurpfile new "${root}/config/spec.json" \
        '$new == $old' >/dev/null || fail '关闭最后 WARP 没有恢复无 routing 规格'
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/ipv6-owner.json" '' '' configure
    ) >"${LOG}" 2>&1 || fail '初始化 WARP 组合夹具失败'
    assertClean
    before=$(snapshot)
    runEdit 15 --warp "${PRIVATE_ROOT}/warp-global.json" --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail '重复默认出站的 WARP 导入改变部署'
    runEdit 0 --warp "${WARP_INPUT}" --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile expected "${TEST_ROOT}/warp-owner.json" --slurpfile actual "${root}/config/spec.json" \
        '$actual == $expected' >/dev/null || fail '选择性 WARP 未保留 IPv6/generic 路由'
    selectiveDomainsIncrementalCheck warp ipv6-owner
    before=$(snapshot)
    runEdit 15 --warp-global --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail 'WARP 组合的默认出口竞争改变部署'
    for failure in health-fail int term; do
        MODE=${failure}
        rm -f -- "${TEST_ROOT}/failed-once"
        case "${failure}" in
        health-fail) runEdit 14 --warp "${WARP_INPUT}" --confirm PADM-DOCKER-EDIT ;;
        int) runEdit 130 --warp-off --confirm PADM-DOCKER-EDIT ;;
        term) runEdit 143 --warp-off --confirm PADM-DOCKER-EDIT ;;
        esac
        [[ "$(snapshot)" == "${before}" ]] || fail "${failure}: WARP 未恢复全部规则、编排与流量"
    done
    for failure in health-fail term; do
        MODE=${failure}
        rm -f -- "${TEST_ROOT}/failed-once"
        if [[ "${failure}" == health-fail ]]; then
            runEdit 14 --warp-family ipv6 --confirm PADM-DOCKER-EDIT
        else
            runEdit 143 --warp-domains 'full:changed.example.com' --confirm PADM-DOCKER-EDIT
        fi
        [[ "$(snapshot)" == "${before}" ]] || fail "${failure}: WARP 日常编辑未恢复全部规则、编排与流量"
    done
    MODE=ok
    runEdit 0 --warp-off --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile expected "${TEST_ROOT}/ipv6-owner.json" --slurpfile actual "${root}/config/spec.json" \
        '$actual == $expected' >/dev/null || fail 'WARP 关闭删除其它路由'
    for core in xray sing-box; do
        cmp -s "${root}/config/${core}/config.json" "${TEST_ROOT}/runtime-ipv6-owner-${core}.json" ||
            fail "${core}: WARP 关闭没有恢复原运行配置"
    done
    runStatus 0
    jq -e 'has("warp") | not' "${LOG}" >/dev/null || fail 'WARP 关闭仍显示有效配置'
    jq -e --arg uuid "${UUID}" '.accounts[$uuid].upload == 17 and .accounts[$uuid].download == 19' \
        "${root}/data/traffic/state.json" >/dev/null || fail 'WARP 事务清空流量'
    [[ "$(stat -c '%a %u %h' "${root}/config/spec.json")" == '600 0 1' ]] ||
        fail 'WARP 改变私有规格权限'
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/base.json" '' '' configure
    ) >"${LOG}" 2>&1 || fail '重置 WARP 夹具失败'
    assertClean
    if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" == warp || "${ROUTING_BRANCH}" == warp ]]; then
        printf 'docker-routing-warp-regression-ok\n'
        exit 0
    fi
fi
if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" != bt && "${PADM_DOCKER_ROUTING_SCOPE:-}" != region &&
    "${PADM_DOCKER_ROUTING_SCOPE:-}" != warp &&
    "${PADM_DOCKER_ROUTING_SCOPE:-}" != core-policy-lifecycle &&
    ( -z "${ROUTING_BRANCH}" || "${ROUTING_BRANCH}" == ipv6 ) ]]; then
    before=$(snapshot)
    runEdit 0 --ipv6 selective --ipv6-domains 'example.net' --preview
    runEdit 0 --ipv6-domains 'example.net' --ipv6 selective --preview
    runEdit 0 --ipv6 global --preview
    runEdit 0 --ipv6 global --ipv6-domains '' --preview
    runEdit 0 --ipv6-domains '' --ipv6 global --preview
    runEdit 0 --ipv6-off --preview
    runEdit 2 --ipv6
    runEdit 2 --ipv6 Global --preview
    runEdit 2 --ipv6 selective --preview
    runEdit 2 --ipv6 selective --ipv6-domains '' --preview
    runEdit 2 --ipv6 global --ipv6-domains 'example.net' --preview
    runEdit 2 --ipv6-domains 'example.net' --ipv6 global --preview
    runEdit 2 --ipv6-domains 'example.net' --preview
    runEdit 2 --ipv6-domains '' --ipv6-off --preview
    runEdit 2 --ipv6-off --ipv6-domains '' --preview
    runEdit 2 --ipv6 global --ipv6 selective --preview
    runEdit 2 --ipv6-off --ipv6-off --preview
    runEdit 2 --ipv6 global --ipv6-off --preview
    runEdit 2 --ipv6-off --ipv6 global --preview
    runEdit 2 --ipv6 selective --ipv6-domains 'example.net' --ipv6-domains 'example.org' --preview
    runEdit 2 --ipv6 selective --ipv6-domains 'regexp:.*' --preview
    runEdit 2 --ipv6 global --block-bt --preview
    runEdit 2 --ipv6-off --direct-off --preview
    runEdit 2 --ipv6 global --spec "${TEST_ROOT}/base.json" --preview
    runEdit 2 --ipv6 global --http01 enable --preview
    runEdit 2 --ipv6 global --confirm invalid
    runEdit 2 --ipv6 global
    runEdit 15 --spec "${TEST_ROOT}/ipv6-global.json" --confirm PADM-DOCKER-EDIT
    composeBefore=$(cat "${COMPOSE_LOG}")
    for action in add remove; do
        runEdit 15 "--ipv6-domains-${action}" 'example.net' --confirm PADM-DOCKER-EDIT
    done
    runEdit 15 --ipv6-domains-replace 'example.net' 'replacement.example.org' --confirm PADM-DOCKER-EDIT
    [[ "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] || fail '未启用 IPv6 域名增删调用 Compose'
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerSetupRead() { printf -v "$1" '%s' n; }
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/ipv6-selective.json" '' '' interactive
    ) >"${LOG}" 2>&1 || fail 'IPv6 确认取消失败'
    assertClean
    [[ "$(snapshot)" == "${before}" ]] || fail 'IPv6 预览、非法参数或取消改变完整部署'
    runEdit 0 --ipv6-domains ' Full:Exact.Example.Com , Example.NET , KEYWORD:Video , geosite:CN , example.net ' \
        --ipv6 selective --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile expected "${TEST_ROOT}/ipv6-selective.json" --slurpfile actual "${root}/config/spec.json" \
        '$actual == $expected' >/dev/null || fail 'IPv6 选择性没有 trim/lower/dedupe 或改变其它规格'
    runEdit 0 --ipv6-domains-remove 'full:exact.example.com,example.net,keyword:video,geosite:cn' \
        --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile old "${TEST_ROOT}/base.json" --slurpfile actual "${root}/config/spec.json" \
        '$actual==$old' >/dev/null || fail '删空唯一 IPv6 域名没有关闭并清理空 routing'
    runStatus 0
    jq -e 'has("ipv6") | not' "${LOG}" >/dev/null || fail '唯一 IPv6 删空后状态仍保留子项'
    runEdit 0 --ipv6 selective --ipv6-domains 'full:exact.example.com,example.net,keyword:video,geosite:cn' \
        --confirm PADM-DOCKER-EDIT
    runStatus 0
    jq -e --argjson domains "${IPV6_DOMAINS}" '
      .enabled == true and .ipv6 == {mode:"selective",domains:$domains} and .mode == "direct"
    ' "${LOG}" >/dev/null || fail 'IPv6 状态没有投影规范化规则'
    [[ "$(stat -c '%a %u %h' "${root}/config/spec.json")" == '600 0 1' ]] ||
        fail 'IPv6 规格没有保留私有权限'
    before=$(snapshot)
    runEdit 15 --spec "${TEST_ROOT}/base.json" --confirm PADM-DOCKER-EDIT
    runEdit 15 --spec "${TEST_ROOT}/ipv6-global.json" --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail '普通 --spec 绕过 IPv6 专项冻结'
    runEdit 0 --ipv6 global --ipv6-domains '' --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile expected "${TEST_ROOT}/ipv6-global.json" --slurpfile actual "${root}/config/spec.json" \
        '$actual == $expected' >/dev/null || fail 'IPv6 全局模式没有替换选择性列表'
    before=$(snapshot)
    composeBefore=$(cat "${COMPOSE_LOG}")
    for action in add remove; do
        runEdit 15 "--ipv6-domains-${action}" 'example.net' --confirm PADM-DOCKER-EDIT
    done
    runEdit 15 --ipv6-domains-replace 'example.net' 'replacement.example.org' --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
        fail '全局 IPv6 域名增删未拒绝或触发 Compose'
    runStatus 0
    jq -e '.ipv6 == {mode:"global",domains:[]}' "${LOG}" >/dev/null ||
        fail 'IPv6 全局状态错误'
    runEdit 0 --ipv6-off --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile old "${TEST_ROOT}/base.json" --slurpfile new "${root}/config/spec.json" \
        '$new == $old' >/dev/null || fail 'IPv6-only 关闭后没有恢复无 routing 规格'
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/routing-bt-policy.json" '' '' configure
    ) >"${LOG}" 2>&1 || fail '初始化 IPv6 组合夹具失败'
    assertClean
    before=$(snapshot)
    runEdit 15 --ipv6 global --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail '全局 SOCKS/IPv6 冲突改变在线部署'
    runEdit 0 --ipv6 selective --ipv6-domains 'full:exact.example.com,example.net,keyword:video,geosite:cn' \
        --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile expected "${TEST_ROOT}/ipv6-owner.json" --slurpfile actual "${root}/config/spec.json" \
        '$actual == $expected' >/dev/null || fail 'IPv6 开启覆盖 generic 路由子项'
    selectiveDomainsIncrementalCheck ipv6 routing-bt-policy
    before=$(snapshot)
    for failure in health-fail int term; do
        MODE=${failure}
        rm -f -- "${TEST_ROOT}/failed-once"
        case "${failure}" in
        health-fail) runEdit 14 --ipv6 selective --ipv6-domains 'replacement.example.org' --confirm PADM-DOCKER-EDIT ;;
        int) runEdit 130 --ipv6-off --confirm PADM-DOCKER-EDIT ;;
        term) runEdit 143 --ipv6-off --confirm PADM-DOCKER-EDIT ;;
        esac
        [[ "$(snapshot)" == "${before}" ]] || fail "${failure}: IPv6 未恢复全部路由、编排与流量"
    done
    MODE=ok
    runEdit 0 --ipv6-off --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile expected "${TEST_ROOT}/routing-bt-policy.json" --slurpfile actual "${root}/config/spec.json" \
        '$actual == $expected' >/dev/null || fail 'IPv6 关闭删除 generic 路由子项'
    for core in xray sing-box; do
        cmp -s "${root}/config/${core}/config.json" "${TEST_ROOT}/runtime-routing-bt-policy-${core}.json" ||
            fail "${core}: 关闭 IPv6 未恢复旧运行配置"
    done
    runStatus 0
    jq -e 'has("ipv6") | not' "${LOG}" >/dev/null || fail 'IPv6 关闭仍显示有效规则'
    jq -e --arg uuid "${UUID}" '.accounts[$uuid].upload == 17 and .accounts[$uuid].download == 19' \
        "${root}/data/traffic/state.json" >/dev/null || fail 'IPv6 事务清空流量累计'
    if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" == core-network-lifecycle ]]; then
        printf 'docker-routing-%s-regression-ok\n' "${PADM_DOCKER_ROUTING_SCOPE}"
        exit 0
    fi
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/base.json" '' '' configure
    ) >"${LOG}" 2>&1 || fail '重置 IPv6 夹具失败'
    assertClean
    if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" == ipv6 ]]; then
        printf 'docker-routing-%s-regression-ok\n' "${PADM_DOCKER_ROUTING_SCOPE}"
        exit 0
    fi
fi
if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" != bt &&
    ( -z "${ROUTING_BRANCH}" || "${ROUTING_BRANCH}" == region ) ]]; then
    before=$(snapshot)
    runEdit 0 --region both --preview
    runEdit 0 --region ip --region-allow '' --preview
    runEdit 0 --region-off --preview
    runEdit 2 --region
    runEdit 2 --region all --preview
    runEdit 2 --region Both --preview
    runEdit 2 --region both
    runEdit 2 --region both --confirm invalid
    runEdit 2 --region both --region ip --preview
    runEdit 2 --region both --region-off --preview
    runEdit 2 --region-off --region-off --preview
    runEdit 2 --region-allow example.com --preview
    runEdit 2 --region both --region-allow example.com --region-allow other.com --preview
    runEdit 2 --region both --region-allow 'regexp:.*' --preview
    runEdit 2 --region both --block-bt --preview
    runEdit 2 --region-off --direct-off --preview
    runEdit 2 --region both --spec "${TEST_ROOT}/base.json" --preview
    runEdit 2 --region both --http01 enable --preview
    runEdit 15 --region-mode domain --preview
    runEdit 2 --region-mode
    runEdit 2 --region-mode '' --preview
    runEdit 2 --region-mode Both --preview
    runEdit 2 --region-mode domain
    runEdit 2 --region-mode domain --confirm invalid
    runEdit 2 --region-mode domain --region-mode ip --preview
    runEdit 2 --region-mode domain --region both --preview
    runEdit 2 --region both --region-mode domain --preview
    runEdit 2 --region-mode domain --region-allow '' --preview
    runEdit 2 --region-mode domain --region-allow-add example.com --preview
    runEdit 2 --region-mode domain --region-off --preview
    runEdit 2 --region-mode domain --direct-off --preview
    runEdit 2 --region-mode domain --spec "${TEST_ROOT}/base.json" --preview
    runEdit 2 --region-mode domain --http01 enable --preview
    runEdit 15 --region-allow-replace apple.com replacement.example.org --preview
    for option in --region-allow-add --region-allow-remove; do
        runEdit 15 "${option}" example.com --preview
        runEdit 2 "${option}"
        runEdit 2 "${option}" '' --preview
        runEdit 2 "${option}" 'regexp:.*' --preview
        runEdit 2 "${option}" example.com
        runEdit 2 "${option}" example.com --confirm invalid
        runEdit 2 "${option}" example.com "${option}" other.com --preview
        runEdit 2 "${option}" example.com --region both --preview
        runEdit 2 --region both "${option}" example.com --preview
        runEdit 2 "${option}" example.com --region-allow other.com --preview
        runEdit 2 "${option}" example.com --direct-off --preview
        runEdit 2 "${option}" example.com --warp-global --preview
        runEdit 2 "${option}" example.com --spec "${TEST_ROOT}/base.json" --preview
        runEdit 2 "${option}" example.com --http01 enable --preview
    done
    runEdit 2 --region-allow-add example.com --region-allow-remove example.com --preview
    runEdit 15 --spec "${TEST_ROOT}/region-both.json" --confirm PADM-DOCKER-EDIT
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerSetupRead() { printf -v "$1" '%s' n; }
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/region-both.json" '' '' interactive
    ) >"${LOG}" 2>&1 || fail '区域确认取消失败'
    assertClean
    [[ "$(snapshot)" == "${before}" ]] || fail '区域预览、非法输入或取消改变部署'
    runEdit 0 --region both --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile old "${TEST_ROOT}/base.json" --slurpfile actual "${root}/config/spec.json" \
        '$actual[0] == ($old[0] + {routing:{region:{mode:"both",allow_domains:[]}}})' >/dev/null ||
        fail '区域无自定义例外时没有独立保留空列表'
    before=$(snapshot)
    runEdit 15 --spec "${TEST_ROOT}/base.json" --confirm PADM-DOCKER-EDIT
    runEdit 15 --region-allow-replace apple.com replacement.example.org --preview
    [[ "$(snapshot)" == "${before}" ]] || fail '普通 --spec 绕过区域专项冻结'
    runEdit 0 --region domain --region-allow ' Full:Exact.Example.Com , APPLE.COM , full:custom-region.example.com , apple.com ' \
        --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile expected "${TEST_ROOT}/region-domain.json" --slurpfile actual "${root}/config/spec.json" \
        '$actual == $expected' >/dev/null || fail '区域模式替换或 CSV 归一化、去重错误'
    runStatus 0
    jq -e --argjson allow "${REGION_ALLOW}" --argjson defaults "${REGION_DEFAULTS}" '
      .region == {mode:"domain",allow_domains:$allow,default_allow_domains:$defaults}
    ' "${LOG}" >/dev/null || fail '区域状态混淆默认和自定义例外'
    runEdit 0 --region ip --region-allow '' --confirm PADM-DOCKER-EDIT
    jq -e '.routing == {region:{mode:"ip",allow_domains:[]}}' "${root}/config/spec.json" >/dev/null ||
        fail '区域切换累加旧模式或空字符串未清空自定义例外'
    [[ "$(stat -c '%a %u %h' "${root}/config/spec.json")" == '600 0 1' ]] ||
        fail '区域规格未保持私有权限'
    runEdit 0 --region-off --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile expected "${TEST_ROOT}/base.json" --slurpfile actual "${root}/config/spec.json" \
        '$actual == $expected' >/dev/null || fail '区域最后项关闭没有删除空 routing'
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/routing-bt-policy.json" '' '' configure
    ) >"${LOG}" 2>&1 || fail '初始化区域所有权夹具失败'
    assertClean
    runEdit 0 --region both --region-allow 'full:exact.example.com,domain:apple.com,full:custom-region.example.com' \
        --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile expected "${TEST_ROOT}/region-owner.json" --slurpfile actual "${root}/config/spec.json" \
        '$actual == $expected' >/dev/null || fail '区域展开写回或覆盖 generic 同规则'
    before=$(snapshot)
    runEdit 15 --region-mode both --confirm PADM-DOCKER-EDIT
    runEdit 0 --region-mode domain --preview
    [[ "$(snapshot)" == "${before}" ]] || fail '区域模式同值拒绝或预览改变部署'
    for regionMode in domain ip both; do
        runEdit 0 --region-mode "${regionMode}" --confirm PADM-DOCKER-EDIT
        jq -en --arg mode "${regionMode}" --slurpfile old "${TEST_ROOT}/region-owner.json" \
            --slurpfile actual "${root}/config/spec.json" '
          $actual[0] == ($old[0] | .routing.region.mode=$mode)
        ' >/dev/null || fail '区域模式切换改变自定义例外、顺序或其它配置'
        runStatus 0
        jq -e --arg mode "${regionMode}" --argjson allow "${REGION_ALLOW}" \
            --argjson defaults "${REGION_DEFAULTS}" '
          .region == {mode:$mode,allow_domains:$allow,default_allow_domains:$defaults}
        ' "${LOG}" >/dev/null || fail '区域模式状态未保留自定义和固定例外'
    done
    before=$(snapshot)
    for failure in health-fail int term; do
        MODE=${failure}
        rm -f -- "${TEST_ROOT}/failed-once"
        case "${failure}" in
        health-fail) runEdit 14 --region-mode domain --confirm PADM-DOCKER-EDIT ;;
        int) runEdit 130 --region-off --confirm PADM-DOCKER-EDIT ;;
        term) runEdit 143 --region-off --confirm PADM-DOCKER-EDIT ;;
        esac
        [[ "$(snapshot)" == "${before}" ]] || fail "${failure}: 区域未恢复完整部署及流量"
    done
    MODE=ok
    domainsReplaceCheck region
    regionAddCsv=' FULL:EXACT.EXAMPLE.COM , APPLE.COM , Exact.Example.COM , keyword:Video , geosite:CN , domain:exact.example.com '
    regionAdded='["full:exact.example.com","domain:apple.com","full:custom-region.example.com","domain:exact.example.com","keyword:video","geosite:cn"]'
    before=$(snapshot)
    runEdit 0 --region-allow-add "${regionAddCsv}" --preview
    jq --argjson domains "${regionAdded}" '.routing.region.allow_domains=$domains' \
        "${root}/config/spec.json" >"${TEST_ROOT}/region-allow-import.json"
    runEdit 15 --spec "${TEST_ROOT}/region-allow-import.json" --confirm PADM-DOCKER-EDIT
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerSetupRead() { printf -v "$1" '%s' n; }
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/region-allow-import.json" '' '' interactive
    ) >"${LOG}" 2>&1 || fail '区域自定义例外确认取消失败'
    assertClean
    [[ "$(snapshot)" == "${before}" ]] || fail '区域追加预览、普通导入或取消改变部署'
    runEdit 0 --region-allow-add "${regionAddCsv}" --confirm PADM-DOCKER-EDIT
    runEdit 0 --region-allow-add "${regionAddCsv}" --confirm PADM-DOCKER-EDIT
    jq -en --argjson domains "${regionAdded}" --slurpfile old "${TEST_ROOT}/region-owner.json" \
        --slurpfile new "${root}/config/spec.json" '
      $new[0] == ($old[0] | .routing.region.allow_domains=$domains)
    ' >/dev/null || fail '区域追加未稳定去重或改变模式、其它策略和规格'
    regionRemoval=' Full:Exact.Example.Com , APPLE.COM , KEYWORD:Video , apple.com '
    regionRemaining='["full:custom-region.example.com","domain:exact.example.com","geosite:cn"]'
    before=$(snapshot)
    runEdit 0 --region-allow-remove "${regionRemoval}" --preview
    runEdit 15 --region-allow-remove "${regionRemoval},missing.example.com" --confirm PADM-DOCKER-EDIT
    runEdit 15 --region-allow-remove dl.google.com --confirm PADM-DOCKER-EDIT
    for failure in health-fail term; do
        MODE=${failure}
        rm -f -- "${TEST_ROOT}/failed-once"
        case "${failure}" in
        health-fail) runEdit 14 --region-allow-add replacement.example.org --confirm PADM-DOCKER-EDIT ;;
        term) runEdit 143 --region-allow-remove "${regionRemoval}" --confirm PADM-DOCKER-EDIT ;;
        esac
        [[ "$(snapshot)" == "${before}" ]] || fail "${failure}: 区域自定义例外未恢复完整部署及流量"
    done
    MODE=ok
    [[ "$(snapshot)" == "${before}" ]] || fail '区域删除预览或整批缺项拒绝改变部署'
    runEdit 0 --region-allow-remove "${regionRemoval}" --confirm PADM-DOCKER-EDIT
    jq -en --argjson domains "${regionRemaining}" --slurpfile old "${TEST_ROOT}/region-owner.json" \
        --slurpfile new "${root}/config/spec.json" '
      $new[0] == ($old[0] | .routing.region.allow_domains=$domains)
    ' >/dev/null || fail '区域删除混淆 full/domain、丢失次序或改变模式和其它策略'
    runStatus 0
    jq -e --argjson allow "${regionRemaining}" --argjson defaults "${REGION_DEFAULTS}" '
      .region == {mode:"both",allow_domains:$allow,default_allow_domains:$defaults}
    ' "${LOG}" >/dev/null || fail '删除同名自定义例外改变固定默认例外'
    regionBoundaryCsv=$(jq -nr '[range(0;253) | "region-boundary-\(.).example.com"] | join(",")')
    regionOverlimitCsv=$(jq -nr '[range(0;257) | "region-overlimit-\(.).example.com"] | join(",")')
    before=$(snapshot)
    runEdit 15 --region-allow-add "${regionBoundaryCsv},region-boundary-253.example.com" --preview
    runEdit 2 --region-allow-add "${regionOverlimitCsv}" --preview
    runEdit 2 --region-allow-remove "${regionOverlimitCsv}" --preview
    [[ "$(snapshot)" == "${before}" ]] || fail '区域自定义例外超限改变部署'
    runEdit 0 --region-allow-add "${regionBoundaryCsv}" --confirm PADM-DOCKER-EDIT
    jq -en --argjson domains "${regionRemaining}" --slurpfile old "${TEST_ROOT}/region-owner.json" \
        --slurpfile new "${root}/config/spec.json" '
      $new[0] == ($old[0] | .routing.region.allow_domains =
        ($domains + [range(0;253) | "domain:region-boundary-\(.).example.com"]))
    ' >/dev/null || fail '区域自定义例外 256 项上界未保留历史次序与完整规格'
    before=$(snapshot)
    runEdit 0 --region-allow-add 'FULL:CUSTOM-REGION.EXAMPLE.COM,region-boundary-252.example.com' --preview
    runEdit 15 --region-allow-add region-boundary-253.example.com --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail '区域上界重复预览或新增超限改变部署'
    runEdit 0 --region-allow-remove "${regionBoundaryCsv}" --confirm PADM-DOCKER-EDIT
    runEdit 0 --region-allow-remove 'full:custom-region.example.com,exact.example.com,geosite:cn' \
        --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile old "${TEST_ROOT}/region-owner.json" --slurpfile new "${root}/config/spec.json" '
      $new[0] == ($old[0] | .routing.region.allow_domains=[])
    ' >/dev/null || fail '删除末条区域自定义例外未保留空列表、模式和其它策略'
    before=$(snapshot)
    runEdit 15 --region-allow-remove exact.example.com --confirm PADM-DOCKER-EDIT
    runEdit 15 --region-allow-replace apple.com replacement.example.org --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail '区域重复删除改变部署'
    runEdit 0 --region-mode domain --confirm PADM-DOCKER-EDIT
    jq -e '.routing.region == {mode:"domain",allow_domains:[]}' "${root}/config/spec.json" >/dev/null ||
        fail '空自定义例外的区域模式切换改变名单'
    runEdit 0 --region-mode both --confirm PADM-DOCKER-EDIT
    runEdit 0 --region-allow-add 'full:exact.example.com,apple.com,full:custom-region.example.com' \
        --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile expected "${TEST_ROOT}/region-owner.json" --slurpfile actual "${root}/config/spec.json" \
        '$actual == $expected' >/dev/null || fail '区域增删未恢复已有自定义名单'
    runEdit 0 --region-off --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile expected "${TEST_ROOT}/routing-bt-policy.json" --slurpfile actual "${root}/config/spec.json" \
        '$actual == $expected' >/dev/null || fail '区域关闭删除 generic 同 CN 或其它子项'
    before=$(snapshot)
    runEdit 15 --region-mode domain --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail '区域模式切换重新启用已关闭策略'
    for core in xray sing-box; do
        cmp -s "${root}/config/${core}/config.json" "${TEST_ROOT}/runtime-routing-bt-policy-${core}.json" ||
            fail "${core}: 区域关闭未精确恢复 generic 生成"
    done
    runStatus 0
    jq -e 'has("region") | not' "${LOG}" >/dev/null || fail '区域关闭后仍显示有效预设'
    jq -e --arg uuid "${UUID}" '.accounts[$uuid].upload == 17 and .accounts[$uuid].download == 19' \
        "${root}/data/traffic/state.json" >/dev/null || fail '区域事务清空累计流量'
    # 组合撤销只跑一次完整事务矩阵，复用已有全部出站与解析夹具。
    jq --argjson allow "${REGION_ALLOW}" '.routing.region = {mode:"both",allow_domains:$allow}' \
        "${TEST_ROOT}/warp-owner6.json" >"${TEST_ROOT}/access-control-before.json"
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/access-control-before.json" '' '' configure
    ) >"${LOG}" 2>&1 || fail '初始化访问控制组合夹具失败'
    assertClean
    jq '.routing |= {socks5,dns,hosts,block_bt,ipv6,warp}' \
        "${TEST_ROOT}/access-control-before.json" >"${TEST_ROOT}/access-control-after.json"
    (dockerMain protocol links) >"${TEST_ROOT}/access-control-links.before"
    dataBefore=$(find "${root}/data" -type f -print0 | sort -z | xargs -0 -r sha256sum)
    before=$(snapshot)
    composeBefore=$(grep '^live:' "${COMPOSE_LOG}" || true)
    runEdit 0 --access-control-off --preview
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerSetupRead() { printf -v "$1" '%s' n; }
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/access-control-after.json" '' '' interactive
    ) >"${LOG}" 2>&1 || fail '访问控制确认取消失败'
    assertClean
    [[ "$(snapshot)" == "${before}" && "$(grep '^live:' "${COMPOSE_LOG}" || true)" == "${composeBefore}" ]] ||
        fail '访问控制预览或取消改变受管文件或触发部署'
    composeBefore=$(cat "${COMPOSE_LOG}")
    runEdit 2 --access-control-off
    runEdit 2 --access-control-off --confirm invalid
    runEdit 2 --access-control-off --access-control-off --preview
    runEdit 2 --access-control-off --region-off --preview
    runEdit 2 --direct-off --access-control-off --preview
    runEdit 2 --access-control-off --socks5-off --preview
    runEdit 2 --access-control-off --spec "${TEST_ROOT}/base.json" --preview
    [[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
        fail '访问控制非法组合改变受管文件或调用 Compose'
    (
        routingKind=access_control routingAction=disable
        dockerEditCompatibilityValidate "${TEST_ROOT}/access-control-before.json" \
            "${TEST_ROOT}/access-control-after.json" || exit $?
        for change in '.routing.block_bt=false' '.routing.dns.port=53' \
            '.routing.warp.family="ipv4"' '.core.protocols[0].public_port=12345' \
            '.routing.direct={domains:["domain:replacement.example.com"]}'; do
            jq "${change}" "${TEST_ROOT}/access-control-after.json" >"${TEST_ROOT}/access-control-tampered.json"
            reject dockerEditCompatibilityValidate "${TEST_ROOT}/access-control-before.json" \
                "${TEST_ROOT}/access-control-tampered.json"
        done
    ) || fail '访问控制专项放宽其它字段冻结或允许重新添加规则'
    for failure in health-fail int term; do
        MODE=${failure}
        rm -f -- "${TEST_ROOT}/failed-once"
        case "${failure}" in
        health-fail) expected=14 ;;
        int) expected=130 ;;
        term) expected=143 ;;
        esac
        runEdit "${expected}" --access-control-off --confirm PADM-DOCKER-EDIT
        [[ "$(snapshot)" == "${before}" ]] || fail "${failure}: 访问控制组合未完整恢复"
    done
    MODE=ok
    runEdit 0 --access-control-off --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile expected "${TEST_ROOT}/access-control-after.json" \
        --slurpfile actual "${root}/config/spec.json" '$actual == $expected' >/dev/null ||
        fail '访问控制组合移除不完整或改变其它规格'
    for core in xray sing-box; do
        if [[ "${core}" == xray ]]; then
            dockerGenerateXrayConfig "${TEST_ROOT}/access-control-after.json" "${TEST_ROOT}/access-control-${core}.json"
        else
            dockerGenerateSingBoxConfig "${TEST_ROOT}/access-control-after.json" "${TEST_ROOT}/access-control-${core}.json"
        fi
        dockerTrafficRender "${core}" "${TEST_ROOT}/access-control-${core}.json" \
            '{"schema_version":1,"accounts":{}}' >"${TEST_ROOT}/access-control-runtime-${core}.json"
        cmp -s "${root}/config/${core}/config.json" "${TEST_ROOT}/access-control-runtime-${core}.json" ||
            fail "${core}: 访问控制撤销未同步运行配置"
    done
    (dockerMain protocol links) >"${TEST_ROOT}/access-control-links.after"
    cmp -s "${TEST_ROOT}/access-control-links.before" "${TEST_ROOT}/access-control-links.after" &&
        [[ "$(find "${root}/data" -type f -print0 | sort -z | xargs -0 -r sha256sum)" == "${dataBefore}" ]] ||
        fail '访问控制撤销改变分享、私有数据或累计流量'
    before=$(snapshot)
    composeBefore=$(cat "${COMPOSE_LOG}")
    runEdit 15 --access-control-off --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
        fail '重复撤销无访问控制的部署触发重启'
    runEdit 0 --region ip --confirm PADM-DOCKER-EDIT
    runEdit 0 --access-control-off --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile expected "${TEST_ROOT}/access-control-after.json" \
        --slurpfile actual "${root}/config/spec.json" '$actual == $expected' >/dev/null ||
        fail '仅区域预设撤销改变无关出站'
    printf 'docker-routing-access-control-off-regression-ok\n'
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/base.json" '' '' configure
    ) >"${LOG}" 2>&1 || fail '恢复区域前基线失败'
    assertClean
    runEdit 0 --region domain --confirm PADM-DOCKER-EDIT
    runEdit 0 --access-control-off --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile expected "${TEST_ROOT}/base.json" --slurpfile actual "${root}/config/spec.json" \
        '$actual == $expected' >/dev/null || fail '访问控制最后项撤销未删除空 routing'
    if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" == region || "${ROUTING_BRANCH}" == region ]]; then
        printf 'docker-routing-region-regression-ok\n'
        exit 0
    fi
fi
if [[ -z "${ROUTING_BRANCH}" || "${ROUTING_BRANCH}" == bt ]]; then
before=$(snapshot)
runEdit 0 --block-bt --preview
runEdit 0 --block-bt-off --preview
for args in on-on off-off on-off; do
    case "${args}" in
    on-on) runEdit 2 --block-bt --block-bt --preview ;;
    off-off) runEdit 2 --block-bt-off --block-bt-off --preview ;;
    on-off) runEdit 2 --block-bt --block-bt-off --preview ;;
    esac
done
runEdit 2 --block-bt
runEdit 2 --block-bt --confirm invalid
runEdit 2 --block-bt unexpected --preview
runEdit 2 --block-bt --socks5-off --preview
runEdit 2 --block-bt --dns "${DNS_INPUT}" --preview
runEdit 2 --block-bt --block-ips-off --preview
runEdit 2 --block-bt-off --direct-off --preview
runEdit 2 --block-bt --spec "${TEST_ROOT}/base.json" --preview
runEdit 2 --block-bt --http01 enable --preview
runEdit 15 --spec "${TEST_ROOT}/block-bt-only.json" --confirm PADM-DOCKER-EDIT
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerSetupRead() { printf -v "$1" '%s' n; }
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/block-bt-only.json" '' '' interactive
) >"${LOG}" 2>&1 || fail 'BT 开启确认取消失败'
assertClean
[[ "$(snapshot)" == "${before}" ]] || fail 'BT 预览、无效参数或取消改变完整部署'
runEdit 0 --block-bt --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/block-bt-only.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail 'BT 独立开启改变其它规格'
[[ "$(stat -c '%a %u %h' "${root}/config/spec.json")" == '600 0 1' ]] ||
    fail 'BT 规格未保持私有权限'
runStatus 0
jq -e '.enabled == true and .block_bt == true and .tcp == "direct" and .udp == "direct"' \
    "${LOG}" >/dev/null || fail 'BT 启用状态没有显式投影'
before=$(snapshot)
runEdit 15 --spec "${TEST_ROOT}/base.json" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '普通 --spec 绕过 BT 专项冻结'
runEdit 0 --block-bt-off --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/base.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail 'BT 最后一项关闭未删除空 routing'
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/routing-ip-policy.json" '' '' configure
) >"${LOG}" 2>&1 || fail '初始化 BT 组合夹具失败'
assertClean
before=$(snapshot)
runEdit 0 --block-bt --preview
[[ "$(snapshot)" == "${before}" ]] || fail 'BT 组合预览改变旧路由'
runEdit 0 --block-bt --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/routing-bt-policy.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail 'BT 开启覆盖旧路由字段'
before=$(snapshot)
for failure in health-fail int term; do
    MODE=${failure}
    rm -f -- "${TEST_ROOT}/failed-once"
    case "${failure}" in
    health-fail) runEdit 14 --block-bt-off --confirm PADM-DOCKER-EDIT ;;
    int) runEdit 130 --block-bt-off --confirm PADM-DOCKER-EDIT ;;
    term) runEdit 143 --block-bt-off --confirm PADM-DOCKER-EDIT ;;
    esac
    [[ "$(snapshot)" == "${before}" ]] || fail "${failure}: BT 未恢复全部路由和流量"
done
MODE=ok
runEdit 0 --block-bt-off --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/routing-ip-policy.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail 'BT 关闭改变旧路由字段'
runStatus 0
jq -e 'has("block_bt") | not' "${LOG}" >/dev/null || fail 'BT 关闭仍显示有效策略'
jq -e --arg uuid "${UUID}" '.accounts[$uuid].upload == 17 and .accounts[$uuid].download == 19' \
    "${root}/data/traffic/state.json" >/dev/null || fail 'BT 事务清空累计流量'
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/base.json" '' '' configure
) >"${LOG}" 2>&1 || fail '恢复 BT 前基线失败'
assertClean
(
    dockerMenuRun() { printf '%s\n' "$*" >>"${TEST_ROOT}/bt-menu.log"; }
    dockerMenuRouting < <(printf '16\n17\n0\n')
) >"${LOG}" 2>&1
printf 'edit --block-bt\nedit --block-bt-off\n' >"${TEST_ROOT}/bt-menu.expected"
cmp -s "${TEST_ROOT}/bt-menu.log" "${TEST_ROOT}/bt-menu.expected" ||
    fail 'BT 菜单没有映射到专项 CLI 事务'
if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" == bt || "${ROUTING_BRANCH}" == bt ]]; then
    printf 'docker-routing-block-bt-regression-ok\n'
    exit 0
fi
fi
before=$(snapshot)
runStatus 0
jq -e '. == {enabled:false,server:null,port:null,tcp:"direct",udp:"direct",mode:"direct",domain_rules:[],
  direct_block_overlaps:[],domain_rule_overlaps:[],domain_rule_coverages:[],domain_rule_keyword_coverages:[],http_relay:{enabled:false}}' "${LOG}" >/dev/null ||
    fail '关闭路由诊断合同错误'
runStatus 2 unexpected
runEdit 0 --socks5 "${INPUT}" --preview
runEdit 0 --socks5 "${DOMAINS_INPUT}" --preview
runEdit 15 --socks5-domains 'example.net' --preview
runEdit 15 --socks5-global --preview
for option in --socks5-domains-add --socks5-domains-remove --socks5-domains-replace; do
    args=('example.net')
    [[ "${option}" != *-replace ]] || args+=('replacement.example.org')
    runEdit 15 "${option}" "${args[@]}" --preview
    for originalOption in --socks5-global --socks5-off; do
        runEdit 2 "${option}" "${args[@]}" "${originalOption}" --preview
        runEdit 2 "${originalOption}" "${option}" "${args[@]}" --preview
    done
    runEdit 2 "${option}" "${args[@]}" --socks5-domains example.org --preview
    runEdit 2 --socks5-domains example.org "${option}" "${args[@]}" --preview
done
runEdit 2 --socks5 "${INPUT}" --socks5-off --preview
runEdit 2 --socks5 "${INPUT}" --spec "${TEST_ROOT}/routed.json" --preview
runEdit 2 --socks5 "${INPUT}" --http01 enable --preview
runEdit 2 --socks5 "${INPUT}" --socks5 "${INPUT}" --preview
runEdit 2 --socks5-off --socks5-off --preview
runEdit 2 --socks5 "${INPUT}" --confirm invalid
runEdit 2 --socks5 "${INPUT}"
runEdit 2 --socks5-domains
runEdit 2 --socks5-domains 'example.net'
runEdit 2 --socks5-domains 'example.net' --socks5-global --preview
runEdit 2 --socks5-domains 'example.net' --socks5 "${INPUT}" --preview
runEdit 2 --socks5-domains 'example.net' --socks5-off --preview
runEdit 2 --socks5-domains 'example.net' --spec "${TEST_ROOT}/routed.json" --preview
runEdit 2 --socks5-domains 'example.net' --http01 enable --preview
runEdit 2 --socks5-domains 'example.net' --socks5-domains 'example.org' --preview
runEdit 2 --socks5-global --socks5-global --preview
runEdit 2 --socks5-global --socks5-off --preview
runEdit 2 --socks5-global --socks5 "${INPUT}" --preview
runEdit 2 --socks5-global --http01 enable --preview
runEdit 2 --socks5-global --confirm invalid
runEdit 2 --socks5-global
for csv in '' ' ' ',example.net' 'example.net,' 'example.net,,cn' 'keyword:' \
    'keyword:a b' 'keyword:a/b' 'full:-bad.example.com' 'geosite:a.b' 'unknown:example.net' \
    'CN' 'category-ads-all'; do
    runEdit 2 --socks5-domains "${csv}" --preview
done
runEdit 15 --spec "${TEST_ROOT}/routed.json" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '路由预览、诊断或非法参数改变部署'
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerSetupRead() { printf -v "$1" '%s' n; }
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/domains.json" '' '' interactive
) >"${LOG}" 2>&1 || fail '路由确认取消失败'
assertClean
[[ "$(snapshot)" == "${before}" ]] || fail '路由取消改变规格、核心、凭据或流量'

# 文件边界先拒绝不安全来源，不读取 FIFO 或将凭据放进诊断输出。
cp -- "${INPUT}" "${PRIVATE_ROOT}/bad.json"
chmod 0640 "${PRIVATE_ROOT}/bad.json"
runEdit 15 --socks5 "${PRIVATE_ROOT}/bad.json" --preview
chmod 0600 "${PRIVATE_ROOT}/bad.json"
chown 10001:10001 "${PRIVATE_ROOT}/bad.json"
runEdit 15 --socks5 "${PRIVATE_ROOT}/bad.json" --preview
chown 0:0 "${PRIVATE_ROOT}/bad.json"
ln "${PRIVATE_ROOT}/bad.json" "${PRIVATE_ROOT}/hardlink.json"
runEdit 15 --socks5 "${PRIVATE_ROOT}/bad.json" --preview
rm -- "${PRIVATE_ROOT}/hardlink.json"
ln -s "${INPUT}" "${PRIVATE_ROOT}/link.json"
runEdit 15 --socks5 "${PRIVATE_ROOT}/link.json" --preview
runEdit 15 --socks5 "${PRIVATE_ROOT}/missing.json" --preview
mkdir "${PRIVATE_ROOT}/ancestor"
cp -- "${INPUT}" "${PRIVATE_ROOT}/ancestor/input.json"
chmod 0600 "${PRIVATE_ROOT}/ancestor/input.json"
chmod 0770 "${PRIVATE_ROOT}/ancestor"
runEdit 15 --socks5 "${PRIVATE_ROOT}/ancestor/input.json" --preview
chmod 0700 "${PRIVATE_ROOT}/ancestor"
chown 10001:10001 "${PRIVATE_ROOT}/ancestor"
runEdit 15 --socks5 "${PRIVATE_ROOT}/ancestor/input.json" --preview
chown 0:0 "${PRIVATE_ROOT}/ancestor"
ln -s "${PRIVATE_ROOT}/ancestor" "${PRIVATE_ROOT}/ancestor-link"
runEdit 15 --socks5 "${PRIVATE_ROOT}/ancestor-link/input.json" --preview
runEdit 15 --socks5 "${PRIVATE_ROOT}/ancestor" --preview
cp -- "${INPUT}" "${TEST_ROOT}/insecure-ancestor.json"
chmod 0600 "${TEST_ROOT}/insecure-ancestor.json"
runEdit 15 --socks5 "${TEST_ROOT}/insecure-ancestor.json" --preview
mkfifo "${PRIVATE_ROOT}/fifo.json"
chmod 0600 "${PRIVATE_ROOT}/fifo.json"
actual=0
timeout -k 1 5 bash -c '
  source "$1"
  dockerEditPrivateInputCopy "$2" "$3" socks5
' _ "${PROJECT_ROOT}/install-docker.sh" "${PRIVATE_ROOT}/fifo.json" \
    "${TEST_ROOT}/fifo-copy.json" >"${LOG}" 2>&1 || actual=$?
[[ "${actual}" == 1 ]] || fail "FIFO 应在读取前拒绝而非阻塞: ${actual}"
[[ ! -e "${TEST_ROOT}/fifo-copy.json" ]] || fail 'FIFO 输入生成了凭据副本'
for content in empty invalid multiple extra oversize; do
    case "${content}" in
    empty) : >"${PRIVATE_ROOT}/bad.json" ;;
    invalid) printf '{\n' >"${PRIVATE_ROOT}/bad.json" ;;
    multiple) cat "${INPUT}" "${INPUT}" >"${PRIVATE_ROOT}/bad.json" ;;
    extra) jq '.extra = true' "${INPUT}" >"${PRIVATE_ROOT}/bad.json" ;;
    oversize) head -c 65537 /dev/zero >"${PRIVATE_ROOT}/bad.json" ;;
    esac
    chmod 0600 "${PRIVATE_ROOT}/bad.json"
    runEdit 15 --socks5 "${PRIVATE_ROOT}/bad.json" --preview
done
cp -- "${INPUT}" "${PRIVATE_ROOT}/padded.json"
padding=$((65536 - $(stat -c '%s' "${INPUT}")))
head -c "${padding}" /dev/zero | tr '\0' ' ' >>"${PRIVATE_ROOT}/padded.json"
chmod 0600 "${PRIVATE_ROOT}/padded.json"
runEdit 0 --socks5 "${PRIVATE_ROOT}/padded.json" --preview
printf '\n' >>"${PRIVATE_ROOT}/padded.json"
runEdit 15 --socks5 "${PRIVATE_ROOT}/padded.json" --preview
[[ "$(snapshot)" == "${before}" ]] || fail '拒绝不安全凭据输入后改变在线部署'
runEdit 0 --socks5 "${INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/base.json" --slurpfile new "${root}/config/spec.json" \
    --slurpfile socks "${INPUT}" '$new[0] == ($old[0] + {routing:{socks5:$socks[0]}})' >/dev/null ||
    fail '开启 SOCKS5 改变路由之外的规格'
[[ "$(stat -c '%a %u %h' "${root}/config/spec.json")" == '600 0 1' ]] ||
    fail '包含 SOCKS5 凭据的受管规格权限错误'
before=$(snapshot)
runEdit 15 --spec "${TEST_ROOT}/base.json" --confirm PADM-DOCKER-EDIT
jq '.routing.socks5.server = "203.0.113.10" | .routing.socks5.port = 1081' \
    "${TEST_ROOT}/routed.json" >"${TEST_ROOT}/routing-replacement.json"
runEdit 15 --spec "${TEST_ROOT}/routing-replacement.json" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '普通 --spec 绕过路由专项冻结'
runStatus 0
jq -e '. == {enabled:true,server:"203.0.113.9",port:1080,tcp:"socks5",udp:"blocked",mode:"global",domain_rules:[],
  direct_block_overlaps:[],domain_rule_overlaps:[],domain_rule_coverages:[],domain_rule_keyword_coverages:[],http_relay:{enabled:false}}' \
    "${LOG}" >/dev/null || fail '开启路由诊断合同错误'
before=$(snapshot)
for option in --socks5-domains-add --socks5-domains-remove --socks5-domains-replace; do
    args=('example.net')
    [[ "${option}" != *-replace ]] || args+=('replacement.example.org')
    runEdit 15 "${option}" "${args[@]}" --preview
done
[[ "$(snapshot)" == "${before}" ]] || fail '全局 SOCKS5 被名单编辑改变'
runEdit 0 --socks5 "${DOMAINS_INPUT}" --preview
[[ "$(snapshot)" == "${before}" ]] || fail '选择性启用预览改变在线部署'
runEdit 0 --socks5 "${DOMAINS_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/domains.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail '私有文件选择性启用没有保留域名规则或其它规格'
runStatus 0
jq -e --argjson domains "${DOMAINS}" '
  . == {enabled:true,server:"203.0.113.9",port:1080,tcp:"matched-socks5",
        udp:"matched-blocked",mode:"domains",domain_rules:$domains,direct_block_overlaps:[],domain_rule_overlaps:[],domain_rule_coverages:[],domain_rule_keyword_coverages:[],http_relay:{enabled:false}}
' "${LOG}" >/dev/null || fail '选择性路由诊断合同错误'
before=$(snapshot)
runEdit 15 --spec "${TEST_ROOT}/routed.json" --confirm PADM-DOCKER-EDIT
replacementCsv=' Full:Exact.Example.Com , Example.NET , KEYWORD:Video , geosite:CN , geosite:category-ads-all , example.net '
replacementDomains='["full:exact.example.com","domain:example.net","keyword:video","geosite:cn","geosite:category-ads-all"]'
runEdit 0 --socks5-domains "${replacementCsv}" --preview
runEdit 0 --socks5-global --preview
runEdit 0 --socks5-off --preview
[[ "$(snapshot)" == "${before}" ]] || fail '规则替换、全局、关闭预览或只读诊断改变在线部署'
runEdit 0 --socks5-domains "${replacementCsv}" --confirm PADM-DOCKER-EDIT
jq -en --argjson domains "${replacementDomains}" --slurpfile old "${TEST_ROOT}/routed.json" \
    --slurpfile new "${root}/config/spec.json" '
  $new[0] == ($old[0] | .routing.socks5.domains = $domains)
' >/dev/null || fail '规则替换没有 trim/lower/dedupe、裸域名归一化或改变凭据'
[[ "$(stat -c '%a %u %h' "${root}/config/spec.json")" == '600 0 1' ]] ||
    fail '替换域名规则改变私有规格权限'
runStatus 0
jq -e --argjson domains "${replacementDomains}" '
  . == {enabled:true,server:"203.0.113.9",port:1080,tcp:"matched-socks5",
        udp:"matched-blocked",mode:"domains",domain_rules:$domains,direct_block_overlaps:[],domain_rule_overlaps:[],domain_rule_coverages:[],domain_rule_keyword_coverages:[],http_relay:{enabled:false}}
' "${LOG}" >/dev/null || fail '规则替换后状态没有返回规范化数组'
before=$(snapshot)
for failure in health-fail int term; do
    MODE=${failure}
    rm -f -- "${TEST_ROOT}/failed-once"
    expected=14
    [[ "${failure}" != int ]] || expected=130
    [[ "${failure}" != term ]] || expected=143
    case "${failure}" in
    health-fail) runEdit "${expected}" --socks5-domains 'replacement.example.org' --confirm PADM-DOCKER-EDIT ;;
    int) runEdit "${expected}" --socks5-global --confirm PADM-DOCKER-EDIT ;;
    term) runEdit "${expected}" --socks5-off --confirm PADM-DOCKER-EDIT ;;
    esac
    [[ "$(snapshot)" == "${before}" ]] || fail "${failure}: 路由事务未恢复完整部署及非空流量"
done
MODE=ok
runEdit 0 --socks5-global --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/routed.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail '切换全局没有仅删除 domains 或改变凭据'
runStatus 0
jq -e '. == {enabled:true,server:"203.0.113.9",port:1080,tcp:"socks5",udp:"blocked",mode:"global",domain_rules:[],
  direct_block_overlaps:[],domain_rule_overlaps:[],domain_rule_coverages:[],domain_rule_keyword_coverages:[],http_relay:{enabled:false}}' \
    "${LOG}" >/dev/null || fail '切换全局后状态合同错误'
runEdit 0 --socks5-domains 'example.net' --confirm PADM-DOCKER-EDIT
runEdit 0 --socks5-domains-remove 'example.net' --confirm PADM-DOCKER-EDIT
jq -e 'has("routing") | not' "${root}/config/spec.json" >/dev/null ||
    fail '关闭 SOCKS5 没有删除可选 routing 字段'
runStatus 0
jq -e '.mode == "direct" and .domain_rules == [] and .enabled == false' "${LOG}" >/dev/null ||
    fail '关闭选择性路由后诊断没有恢复直连'
for core in xray sing-box; do
    source="${TEST_ROOT}/legacy-sing-box.json"
    [[ "${core}" != xray ]] || source="${TEST_ROOT}/legacy-v3-xray.json"
    dockerTrafficRender "${core}" "${source}" \
        '{"schema_version":1,"accounts":{}}' >"${TEST_ROOT}/legacy-${core}-runtime.json"
    cmp -s "${root}/config/${core}/config.json" "${TEST_ROOT}/legacy-${core}-runtime.json" ||
        fail "${core}: 关闭 SOCKS5 未恢复旧默认运行配置"
done
jq -e --arg uuid "${UUID}" '.accounts[$uuid].upload == 17 and .accounts[$uuid].download == 19' \
    "${root}/data/traffic/state.json" >/dev/null || fail '路由编辑清空流量累计'
jq --argjson domains "${IPV6_DOMAINS}" '.domains=$domains' "${INPUT}" >"${PRIVATE_ROOT}/socks5-selective.json"
chmod 0600 "${PRIVATE_ROOT}/socks5-selective.json"
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/dns-only.json" '' '' configure
) >"${LOG}" 2>&1 || fail '初始化 SOCKS5 选择性增量组合失败'
assertClean
runEdit 0 --socks5 "${PRIVATE_ROOT}/socks5-selective.json" --confirm PADM-DOCKER-EDIT
selectiveDomainsIncrementalCheck socks5 dns-only
runEdit 0 --socks5-off --confirm PADM-DOCKER-EDIT
if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" == core-policy-lifecycle ]]; then
    printf 'docker-routing-%s-regression-ok\n' "${PADM_DOCKER_ROUTING_SCOPE}"
    exit 0
fi
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/base.json" '' '' configure
) >"${LOG}" 2>&1 || fail '恢复 SOCKS5 增量前基线失败'
assertClean
fi

# 核心入口在生命周期结束退出，域名子项由独立事务夹具覆盖。
if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" == core-workflow ||
    "${PADM_DOCKER_ROUTING_SCOPE:-}" == core-lifecycle ]]; then
    printf 'docker-routing-%s-regression-ok\n' "${PADM_DOCKER_ROUTING_SCOPE}"
    exit 0
fi

# 路由子项共用私有文件与候选事务，每次编辑只替换自己的字段。
if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-direct-block &&
    "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-direct-block-ip &&
    "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-direct-block-csv ]]; then
if [[ "${ROUTING_BRANCH}" != hosts ]]; then
before=$(snapshot)
for kind in dns hosts direct block block-ips; do
    input="${PRIVATE_ROOT}/${kind}.json"
    runEdit 0 "--${kind}" "${input}" --preview
    runEdit 0 "--${kind}-off" --preview
    runEdit 2 "--${kind}"
    runEdit 2 "--${kind}" "${input}"
    runEdit 2 "--${kind}" "${input}" "--${kind}-off" --preview
    runEdit 2 "--${kind}" "${input}" "--${kind}" "${input}" --preview
    runEdit 2 "--${kind}-off" "--${kind}-off" --preview
    runEdit 2 "--${kind}" "${input}" --socks5-off --preview
    runEdit 2 "--${kind}" "${input}" --spec "${TEST_ROOT}/base.json" --preview
    runEdit 2 "--${kind}" "${input}" --http01 enable --preview
    runEdit 2 "--${kind}" "${input}" --confirm invalid
    cp -- "${input}" "${PRIVATE_ROOT}/bad.json"
    chmod 0640 "${PRIVATE_ROOT}/bad.json"
    runEdit 15 "--${kind}" "${PRIVATE_ROOT}/bad.json" --preview
    chmod 0600 "${PRIVATE_ROOT}/bad.json"
    printf '{}\n' >"${PRIVATE_ROOT}/bad.json"
    runEdit 15 "--${kind}" "${PRIVATE_ROOT}/bad.json" --preview
done
boundaryCsv=$(jq -nr '[range(0;256) | "boundary-\(.).example.com"] | join(",")')
overlimitCsv="${boundaryCsv},boundary-256.example.com"
duplicateBoundaryCsv="${boundaryCsv},BOUNDARY-0.EXAMPLE.COM"
runEdit 0 --dns-rules 203.0.113.53 05353 "${DNS_CSV}" --preview
runEdit 0 --dns-rules 2001:db8::53 65535 "${boundaryCsv}" --preview
runEdit 2 --dns-rules
runEdit 2 --dns-rules 203.0.113.53
runEdit 2 --dns-rules 203.0.113.53 53
runEdit 2 --dns-rules '' 53 "${DNS_CSV}" --preview
runEdit 2 --dns-rules 203.0.113.53 53 '' --preview
runEdit 2 --dns-rules 203.0.113.53 53 --preview
runEdit 2 --dns-rules 203.0.113.53 53 'regexp:.*' --preview
runEdit 2 --dns-rules 203.0.113.53 53 "${overlimitCsv}" --preview
for port in 0 65536 -1 1.5 invalid 000053; do
    runEdit 2 --dns-rules 203.0.113.53 "${port}" "${DNS_CSV}" --preview
done
for server in 127.0.0.1 0.0.0.0 resolver.example.com 2001:db8::1::53 '[2001:db8::53]'; do
    runEdit 15 --dns-rules "${server}" 53 "${DNS_CSV}" --preview
done
runEdit 2 --dns-rules 203.0.113.53 53 "${DNS_CSV}" --dns-rules 2001:db8::53 53 "${DNS_CSV}" --preview
runEdit 2 --dns-rules 203.0.113.53 53 "${DNS_CSV}" --dns "${DNS_INPUT}" --preview
runEdit 2 --dns "${DNS_INPUT}" --dns-rules 203.0.113.53 53 "${DNS_CSV}" --preview
runEdit 2 --dns-rules 203.0.113.53 53 "${DNS_CSV}" --dns-off --preview
runEdit 2 --dns-off --dns-rules 203.0.113.53 53 "${DNS_CSV}" --preview
runEdit 2 --dns-rules 203.0.113.53 53 "${DNS_CSV}" --hosts "${HOSTS_INPUT}" --preview
runEdit 2 --hosts "${HOSTS_INPUT}" --dns-rules 203.0.113.53 53 "${DNS_CSV}" --preview
runEdit 2 --dns-rules 203.0.113.53 53 "${DNS_CSV}" --socks5-off --preview
runEdit 2 --socks5-off --dns-rules 203.0.113.53 53 "${DNS_CSV}" --preview
runEdit 2 --dns-rules 203.0.113.53 53 "${DNS_CSV}" --spec "${TEST_ROOT}/base.json" --preview
runEdit 2 --dns-rules 203.0.113.53 53 "${DNS_CSV}" --http01 enable --preview
runEdit 2 --dns-rules 203.0.113.53 53 "${DNS_CSV}" --http-relay-off --preview
runEdit 2 --dns-rules 203.0.113.53 53 "${DNS_CSV}" --port-alias-default entry-xray base --preview
for kind in direct block; do
    option="--${kind}-domains"
    runEdit 0 "${option}" "${DOMAINS_CSV}" --preview
    runEdit 0 "${option}" "${boundaryCsv}" --preview
    runEdit 0 "${option}" "${duplicateBoundaryCsv}" --preview
    runEdit 2 "${option}"
    runEdit 2 "${option}" 'example.net'
    runEdit 2 "${option}" --preview
    runEdit 2 "${option}" "${DOMAINS_CSV}" --confirm invalid
    for csv in '' ' ' ',' ',example.net' 'example.net,' 'example.net,,other.example.net' \
        'CN' 'keyword:' 'keyword:a b' 'keyword:a/b' 'keyword:a:b' 'regexp:.*' 'geoip:cn' \
        'full:-bad.example.com' 'domain:a..example.com' 'full:example.com.' 'geosite:a.b' \
        "${overlimitCsv}"; do
        runEdit 2 "${option}" "${csv}" --preview
    done
    for other in '--direct-domains' '--block-domains'; do
        runEdit 2 "${option}" "${DOMAINS_CSV}" "${other}" 'other.example.net' --preview
    done
    runEdit 2 "${option}" "${DOMAINS_CSV}" "--${kind}" "${PRIVATE_ROOT}/${kind}.json" --preview
    runEdit 2 "--${kind}" "${PRIVATE_ROOT}/${kind}.json" "${option}" "${DOMAINS_CSV}" --preview
    runEdit 2 "${option}" "${DOMAINS_CSV}" "--${kind}-off" --preview
    runEdit 2 "--${kind}-off" "${option}" "${DOMAINS_CSV}" --preview
    runEdit 2 "${option}" "${DOMAINS_CSV}" --dns "${DNS_INPUT}" --preview
    runEdit 2 "${option}" "${DOMAINS_CSV}" --socks5-off --preview
    runEdit 2 --socks5-off "${option}" "${DOMAINS_CSV}" --preview
    runEdit 2 "${option}" "${DOMAINS_CSV}" --spec "${TEST_ROOT}/base.json" --preview
    runEdit 2 "${option}" "${DOMAINS_CSV}" --http01 enable --preview
    runEdit 2 "${option}" "${DOMAINS_CSV}" --http-relay-off --preview
    runEdit 2 "${option}" "${DOMAINS_CSV}" --port-alias-default entry-xray base --preview
    addOption="${option}-add"
    runEdit 0 "${addOption}" "${DOMAINS_CSV}" --preview
    runEdit 2 "${addOption}"
    runEdit 2 "${addOption}" '' --preview
    runEdit 2 "${addOption}" --preview
    runEdit 2 "${addOption}" 'regexp:.*' --preview
    runEdit 2 "${addOption}" "${DOMAINS_CSV}" "${addOption}" 'other.example.net' --preview
    runEdit 2 "${addOption}" "${DOMAINS_CSV}" "${option}" 'other.example.net' --preview
    runEdit 2 "${option}" "${DOMAINS_CSV}" "${addOption}" 'other.example.net' --preview
    runEdit 2 "${addOption}" "${DOMAINS_CSV}" "--${kind}" "${PRIVATE_ROOT}/${kind}.json" --preview
    runEdit 2 "${addOption}" "${DOMAINS_CSV}" "--${kind}-off" --preview
    runEdit 2 "${addOption}" "${DOMAINS_CSV}" --direct-domains-add 'other.example.net' --preview
    runEdit 2 "${addOption}" "${DOMAINS_CSV}" --block-domains-add 'other.example.net' --preview
    runEdit 2 "${addOption}" "${DOMAINS_CSV}" --socks5-off --preview
    runEdit 2 "${addOption}" "${DOMAINS_CSV}" --spec "${TEST_ROOT}/base.json" --preview
    runEdit 2 "${addOption}" "${DOMAINS_CSV}" --http01 enable --preview
    removeOption="${option}-remove"
    runEdit 15 "${removeOption}" "${DOMAINS_CSV}" --preview
    runEdit 2 "${removeOption}"
    runEdit 2 "${removeOption}" '' --preview
    runEdit 2 "${removeOption}" --preview
    runEdit 2 "${removeOption}" 'regexp:.*' --preview
    runEdit 2 "${removeOption}" "${DOMAINS_CSV}" "${removeOption}" 'other.example.net' --preview
    runEdit 2 "${removeOption}" "${DOMAINS_CSV}" "${addOption}" 'other.example.net' --preview
    runEdit 2 "${removeOption}" "${DOMAINS_CSV}" "--${kind}-off" --preview
    runEdit 2 "${removeOption}" "${DOMAINS_CSV}" --socks5-off --preview
    runEdit 2 "${removeOption}" "${DOMAINS_CSV}" --spec "${TEST_ROOT}/base.json" --preview
done
runEdit 2 --dns "${DNS_INPUT}" --hosts "${HOSTS_INPUT}" --preview
runEdit 2 --dns-off --hosts-off --preview
runEdit 2 --direct "${DIRECT_INPUT}" --block "${BLOCK_INPUT}" --preview
runEdit 2 --direct-off --block-off --preview
runEdit 2 --block-ips "${BLOCK_IPS_INPUT}" --direct-off --preview
runEdit 2 --block-ips-off --block-off --preview
runEdit 15 --spec "${TEST_ROOT}/dns-only.json" --confirm PADM-DOCKER-EDIT
runEdit 15 --spec "${TEST_ROOT}/hosts-only.json" --confirm PADM-DOCKER-EDIT
runEdit 15 --spec "${TEST_ROOT}/direct-only.json" --confirm PADM-DOCKER-EDIT
runEdit 15 --spec "${TEST_ROOT}/block-only.json" --confirm PADM-DOCKER-EDIT
runEdit 15 --spec "${TEST_ROOT}/block-ips-only.json" --confirm PADM-DOCKER-EDIT
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerSetupRead() { printf -v "$1" '%s' n; }
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/routing-ip-policy.json" '' '' interactive
) >"${LOG}" 2>&1 || fail 'DNS/hosts 确认取消失败'
assertClean
[[ "$(snapshot)" == "${before}" ]] || fail '路由子项预览、无效输入或取消改变完整部署'

# DNS 域名增删只能操作已启用的分流，参数错误和未启用拒绝都不得触发 Compose。
before=$(snapshot)
composeBefore=$(cat "${COMPOSE_LOG}")
for action in add remove; do
    option="--dns-domains-${action}"
    runEdit 15 "${option}" "${DNS_CSV}" --confirm PADM-DOCKER-EDIT
    runEdit 2 "${option}"
    runEdit 2 "${option}" '' --preview
    runEdit 2 "${option}" 'regexp:.*' --preview
    runEdit 2 "${option}" "${overlimitCsv}" --preview
    runEdit 2 "${option}" "${DNS_CSV}" --dns-off --preview
    runEdit 2 "${option}" "${DNS_CSV}" "${option}" 'example.net' --preview
done
runEdit 15 --dns-domains-replace 'dns.example.net' 'replacement.example.org' --confirm PADM-DOCKER-EDIT
runEdit 15 --hosts-replace Exact.Example.Com 203.0.113.11 --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
    fail 'DNS/hosts 未启用管理或无效参数改变部署或调用 Compose'
runEdit 0 --dns-rules 203.0.113.53 05353 "${DNS_CSV}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/base.json" --slurpfile new "${root}/config/spec.json" \
    --argjson dns "${DNS}" '$new[0] == ($old[0] + {routing:{dns:$dns}})' >/dev/null ||
    fail 'DNS 直接新建未保留字面 IP、规范化端口和 CSV，或改变其它规格'
runStatus 0
jq -e --argjson dns "${DNS}" '
  . == {enabled:true,server:null,port:null,tcp:"direct",udp:"direct",mode:"direct",
        domain_rules:[],dns:{server:$dns.server,port:$dns.port,domain_rules:$dns.domains},
        direct_block_overlaps:[],domain_rule_overlaps:[],domain_rule_coverages:[],domain_rule_keyword_coverages:[],http_relay:{enabled:false}}
' "${LOG}" >/dev/null || fail 'DNS 独立状态合同错误'
before=$(snapshot)
runEdit 15 --spec "${TEST_ROOT}/base.json" --confirm PADM-DOCKER-EDIT
runEdit 15 --spec "${TEST_ROOT}/routing-all.json" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '普通 --spec 绕过 DNS/hosts 冻结'
runEdit 0 --hosts "${HOSTS_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/dns-only.json" --slurpfile new "${root}/config/spec.json" \
    --argjson hosts "${HOSTS}" '$new[0] == ($old[0] | .routing.hosts=$hosts)' >/dev/null ||
    fail 'hosts 开启覆盖已有 DNS 或其它规格'
runStatus 0
jq -e --argjson hosts "${HOSTS}" '.hosts == $hosts and .dns.server == "203.0.113.53"' \
    "${LOG}" >/dev/null || fail 'DNS/hosts 状态缺少有效配置'
[[ "$(stat -c '%a %u %h' "${root}/config/spec.json")" == '600 0 1' ]] ||
    fail 'DNS/hosts 规格没有保留 root 私有文件权限'
before=$(snapshot)
dnsReplacement='{"server":"2001:db8::53","port":53,"domains":["geosite:cn","full:replacement.example.com","domain:replacement.example.net","keyword:dns-video"]}'
dnsReplacementCsv=' GEOSITE:CN , Full:Replacement.Example.COM , Replacement.Example.NET , Keyword:DNS-Video , full:replacement.example.com '
cp -- "${root}/config/spec.json" "${TEST_ROOT}/dns-rules.before"
jq --argjson dns "${dnsReplacement}" '.routing.dns=$dns' "${root}/config/spec.json" \
    >"${TEST_ROOT}/dns-rules-replacement.json"
runEdit 0 --dns-rules 2001:db8::53 00053 "${dnsReplacementCsv}" --preview
runEdit 15 --spec "${TEST_ROOT}/dns-rules-replacement.json" --confirm PADM-DOCKER-EDIT
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerSetupRead() { printf -v "$1" '%s' n; }
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/dns-rules-replacement.json" '' '' interactive
) >"${LOG}" 2>&1 || fail 'DNS 直接替换确认取消失败'
assertClean
[[ "$(snapshot)" == "${before}" ]] || fail 'DNS 直接替换预览、普通 spec 或取消改变部署'
runEdit 0 --dns-rules 2001:db8::53 00053 "${dnsReplacementCsv}" --confirm PADM-DOCKER-EDIT
jq -en --argjson dns "${dnsReplacement}" --slurpfile old "${TEST_ROOT}/dns-rules.before" \
    --slurpfile new "${root}/config/spec.json" '$new[0]==($old[0]|.routing.dns=$dns)' >/dev/null ||
    fail 'DNS IPv6 整组替换未规范化端口/CSV 或改变其它子项'
runStatus 0
jq -e --argjson dns "${dnsReplacement}" --argjson hosts "${HOSTS}" '
  .dns=={server:$dns.server,port:$dns.port,domain_rules:$dns.domains} and .hosts==$hosts
' "${LOG}" >/dev/null || fail 'DNS IPv6 直接录入状态未保留规范化值和 hosts'
before=$(snapshot)
for failure in health-fail int term; do
    MODE=${failure}
    rm -f -- "${TEST_ROOT}/failed-once"
    case "${failure}" in
    health-fail) runEdit 14 --dns-rules 203.0.113.54 1 'failure.example.net' --confirm PADM-DOCKER-EDIT ;;
    int) runEdit 130 --dns-rules 203.0.113.54 1 'failure.example.net' --confirm PADM-DOCKER-EDIT ;;
    term) runEdit 143 --dns-rules 203.0.113.54 1 'failure.example.net' --confirm PADM-DOCKER-EDIT ;;
    esac
    [[ "$(snapshot)" == "${before}" ]] || fail "${failure}: DNS 直接录入未恢复完整部署和流量"
done
MODE=ok
runEdit 0 --dns "${DNS_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/dns-rules.before" --slurpfile actual "${root}/config/spec.json" \
    '$actual==$expected' >/dev/null || fail 'DNS JSON 接口未恢复原 DNS/hosts 或改变其它规格'
runEdit 0 --socks5 "${DOMAINS_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/routing-all.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail '开启 SOCKS5 丢弃 DNS/hosts'
domainsReplaceCheck dns
fi
if [[ "${ROUTING_BRANCH}" == hosts ]]; then
    # hosts 分支安装原 DNS 前置结束后的组合规格，保留真实事务和非空流量。
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/routing-all.json" '' '' configure
    ) >"${LOG}" 2>&1 || fail '初始化独立 hosts 组合夹具失败'
    assertClean
fi
if [[ "${ROUTING_BRANCH}" != dns ]]; then
# hosts 单键替换复用已有组合夹具，保留其它映射、路由、私有字段与非空流量。
cp -- "${root}/config/spec.json" "${TEST_ROOT}/hosts-replace-resume.json"
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/warp-owner.json" '' '' configure
) >"${LOG}" 2>&1 || fail '初始化 hosts 替换组合夹具失败'
assertClean
cp -- "${root}/config/spec.json" "${TEST_ROOT}/hosts-replace.before"
before=$(snapshot)
composeBefore=$(cat "${COMPOSE_LOG}")
runEdit 2 --hosts-replace
runEdit 2 --hosts-replace exact.example.com --preview
runEdit 2 --hosts-replace '' 203.0.113.11 --preview
runEdit 2 --hosts-replace exact.example.com '' --preview
runEdit 2 --hosts-replace exact.example.com 203.0.113.11
runEdit 2 --hosts-replace exact.example.com 203.0.113.11 --confirm invalid
for host in 'regexp:bad' 'full:exact.example.com' 'domain:exact.example.com' \
    'exact.example.com,ipv6.example.com' 'exact.example.com.' '-bad.example.com' \
    'exact example.com' ' exact.example.com' $'exact.example.com\n' $'\u212A.example.com'; do
    runEdit 2 --hosts-replace "${host}" 203.0.113.11 --preview
done
for address in 127.0.0.1 0.0.0.0 169.254.1.1 224.0.0.1 203.0.113.999 203.0.113.011 \
    203.0.113.11/32 resolver.example.com host.docker.internal ::1 fe80::10 \
    2001:db8::1::10 '[2001:db8::10]' '2001:db8::10%eth0' '203.0.113.11,203.0.113.12' \
    $'203.0.113.11\n' $'2001:db8::10\n'; do
    runEdit 2 --hosts-replace exact.example.com "${address}" --preview
done
runEdit 2 --hosts-replace exact.example.com 203.0.113.11 --hosts-replace ipv6.example.com 203.0.113.12 --preview
runEdit 2 --hosts-replace exact.example.com 203.0.113.11 --hosts "${HOSTS_INPUT}" --preview
runEdit 2 --hosts "${HOSTS_INPUT}" --hosts-replace exact.example.com 203.0.113.11 --preview
runEdit 2 --hosts-replace exact.example.com 203.0.113.11 --hosts-off --preview
runEdit 2 --hosts-off --hosts-replace exact.example.com 203.0.113.11 --preview
runEdit 2 --hosts-replace exact.example.com 203.0.113.11 --dns-off --preview
runEdit 2 --hosts-replace exact.example.com 203.0.113.11 --socks5-off --preview
runEdit 2 --hosts-replace exact.example.com 203.0.113.11 --warp-global --preview
runEdit 2 --hosts-replace exact.example.com 203.0.113.11 --ipv6 global --preview
runEdit 2 --hosts-replace exact.example.com 203.0.113.11 --spec "${TEST_ROOT}/hosts-replace.before" --preview
runEdit 2 --hosts-replace exact.example.com 203.0.113.11 --http01 enable --preview
runEdit 2 --hosts-replace exact.example.com 203.0.113.11 --http-relay-off --preview
runEdit 15 --hosts-replace missing.example.com 203.0.113.11 --confirm PADM-DOCKER-EDIT
runEdit 15 --hosts-replace Exact.Example.Com 203.0.113.10 --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
    fail 'hosts 替换参数、格式、缺键或同值拒绝改变部署或调用 Compose'
runEdit 0 --hosts-replace Exact.Example.Com 203.0.113.11 --preview
[[ "$(snapshot)" == "${before}" ]] || fail 'hosts 替换预览改变完整部署'
# 本动作只分配三次故障，分别证明健康失败、INT 和 TERM 的完整恢复。
for failure in health-fail int term; do
    MODE=${failure}
    rm -f -- "${TEST_ROOT}/failed-once"
    expected=14
    [[ "${failure}" != int ]] || expected=130
    [[ "${failure}" != term ]] || expected=143
    runEdit "${expected}" --hosts-replace Exact.Example.Com 203.0.113.11 --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] ||
        fail "${failure}: hosts 单键替换未恢复完整规格、私有字段、运行配置与非空流量"
done
MODE=ok
for core in xray sing-box; do
    cp -- "${root}/config/${core}/config.json" "${TEST_ROOT}/hosts-replace-${core}.before"
done
(dockerMain protocol links) >"${TEST_ROOT}/hosts-replace-links.before"
hostsReplaceDataBefore=$(find "${root}/data" -type f -print0 | sort -z | xargs -0 -r sha256sum)
for address in 203.0.113.11 2001:0DB8::10; do
    runEdit 0 --hosts-replace Exact.Example.Com "${address}" --confirm PADM-DOCKER-EDIT
    jq -en --arg ip "${address}" --slurpfile old "${TEST_ROOT}/hosts-replace.before" \
        --slurpfile actual "${root}/config/spec.json" '
      $actual[0] == ($old[0] | .routing.hosts["exact.example.com"]=$ip)
    ' >/dev/null || fail 'hosts 单键替换未小写域名、保留地址原文或改写其它完整规格'
    runStatus 0
    jq -e --arg ip "${address}" --slurpfile old "${TEST_ROOT}/hosts-replace.before" '
      .hosts == ($old[0].routing.hosts | .["exact.example.com"]=$ip)
    ' "${LOG}" >/dev/null || fail 'hosts 单键替换状态改变其它映射或地址原文'
    for core in xray sing-box; do
        jq -en --arg core "${core}" --arg ip "${address}" \
            --slurpfile old "${TEST_ROOT}/hosts-replace-${core}.before" \
            --slurpfile actual "${root}/config/${core}/config.json" '
          if $core=="xray" then
            $actual[0] == ($old[0] | .dns.hosts["full:exact.example.com"]=$ip)
          else
            $actual[0] == ($old[0] | .dns.servers |= map(
              if .tag=="padm-hosts" then .predefined["exact.example.com"]=$ip else . end))
          end
        ' >/dev/null || fail "${core}: hosts 替换生成未仅修改目标地址"
    done
    (dockerMain protocol links) >"${TEST_ROOT}/hosts-replace-links.after"
    cmp -s "${TEST_ROOT}/hosts-replace-links.before" "${TEST_ROOT}/hosts-replace-links.after" &&
        [[ "$(find "${root}/data" -type f -print0 | sort -z | xargs -0 -r sha256sum)" == "${hostsReplaceDataBefore}" ]] ||
        fail 'hosts 单键替换改变分享 URI、订阅或累计流量'
done
runEdit 0 --hosts-replace Exact.Example.Com 203.0.113.10 --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/hosts-replace.before" --slurpfile actual "${root}/config/spec.json" \
    '$actual==$old' >/dev/null || fail 'hosts 反向替换未还原原组合规格'
for core in xray sing-box; do
    cmp -s "${TEST_ROOT}/hosts-replace-${core}.before" "${root}/config/${core}/config.json" ||
        fail "${core}: hosts 反向替换未精确恢复原生成"
done
# 单键增删沿用组合夹具，只允许映射及其派生的精确域名名单变化。
before=$(snapshot)
composeBefore=$(cat "${COMPOSE_LOG}")
runEdit 2 --hosts-add
runEdit 2 --hosts-add added.example.com --preview
runEdit 2 --hosts-add '' 203.0.113.12 --preview
runEdit 2 --hosts-add added.example.com '' --preview
runEdit 2 --hosts-remove
runEdit 2 --hosts-remove '' --preview
runEdit 2 --hosts-remove exact.example.com 203.0.113.10 --preview
for host in 'full:exact.example.com' 'exact.example.com,ipv6.example.com' \
    ' exact.example.com' $'exact.example.com\n' $'\u212A.example.com'; do
    runEdit 2 --hosts-add "${host}" 203.0.113.12 --preview
    runEdit 2 --hosts-remove "${host}" --preview
done
runEdit 2 --hosts-add exact.example.com 127.0.0.1 --preview
runEdit 2 --hosts-add added.example.com '203.0.113.12,203.0.113.13' --preview
runEdit 2 --hosts-add added.example.com $'203.0.113.12\n' --preview
runEdit 2 --hosts-add added.example.com 203.0.113.12 --hosts-remove exact.example.com --preview
runEdit 2 --hosts-remove exact.example.com --hosts-add added.example.com 203.0.113.12 --preview
runEdit 2 --hosts-remove exact.example.com --hosts-off --preview
runEdit 15 --hosts-add Exact.Example.Com 203.0.113.10 --confirm PADM-DOCKER-EDIT
runEdit 15 --hosts-add exact.example.com 203.0.113.12 --confirm PADM-DOCKER-EDIT
runEdit 15 --hosts-remove missing.example.com --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
    fail 'hosts 增删参数、格式、重复键或缺键拒绝改变部署或调用 Compose'
runEdit 0 --hosts-add Added-V4.Example.Com 203.0.113.12 --preview
[[ "$(snapshot)" == "${before}" ]] || fail 'hosts 追加预览改变完整部署'
MODE=int
rm -f -- "${TEST_ROOT}/failed-once"
runEdit 130 --hosts-add Added-V4.Example.Com 203.0.113.12 --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail 'INT: hosts 追加未恢复完整部署和流量'
MODE=ok
hostsIncremental=${HOSTS}
for action in add remove; do
    if [[ "${action}" == remove ]]; then
        before=$(snapshot)
        runEdit 0 --hosts-remove Added-V4.Example.Com --preview
        [[ "$(snapshot)" == "${before}" ]] || fail 'hosts 删除预览改变完整部署'
        MODE=term
        rm -f -- "${TEST_ROOT}/failed-once"
        runEdit 143 --hosts-remove Added-V4.Example.Com --confirm PADM-DOCKER-EDIT
        [[ "$(snapshot)" == "${before}" ]] || fail 'TERM: hosts 删除未恢复完整部署和流量'
        MODE=ok
    fi
    for host in added-v4.example.com added-v6.example.com; do
        address=203.0.113.12
        [[ "${host}" != added-v6.example.com ]] || address=2001:0DB8::12
        if [[ "${action}" == add ]]; then
            runEdit 0 --hosts-add "${host^^}" "${address}" --confirm PADM-DOCKER-EDIT
            hostsIncremental=$(jq -cn --argjson hosts "${hostsIncremental}" --arg host "${host}" \
                --arg ip "${address}" '$hosts + {($host):$ip}')
        else
            runEdit 0 --hosts-remove "${host^^}" --confirm PADM-DOCKER-EDIT
            hostsIncremental=$(jq -cn --argjson hosts "${hostsIncremental}" --arg host "${host}" \
                '$hosts | del(.[$host])')
        fi
        jq -en --argjson hosts "${hostsIncremental}" --slurpfile old "${TEST_ROOT}/hosts-replace.before" \
            --slurpfile actual "${root}/config/spec.json" '$actual[0]==($old[0]|.routing.hosts=$hosts)' \
            >/dev/null || fail 'hosts 增删未小写域名、保留 IP 原文或改变其它完整规格'
        runStatus 0
        jq -e --argjson hosts "${hostsIncremental}" '.hosts==$hosts' "${LOG}" >/dev/null ||
            fail 'hosts 增删状态未投影精确完整映射'
        for core in xray sing-box; do
            jq -en --arg core "${core}" --argjson hosts "${hostsIncremental}" --argjson old_hosts "${HOSTS}" \
                --slurpfile old "${TEST_ROOT}/hosts-replace-${core}.before" \
                --slurpfile actual "${root}/config/${core}/config.json" '
              $actual[0] == ($old[0] | if $core=="xray" then
                .dns.hosts = ($hosts | with_entries(.key = "full:" + .key))
              else
                .dns.servers |= map(if .tag=="padm-hosts" then .predefined=$hosts else . end) |
                walk(if type=="object" then
                  if .domain==($old_hosts|keys) then .domain=($hosts|keys) else . end
                else . end)
              end)
            ' >/dev/null || fail "${core}: hosts 增删改变映射和派生名单之外的生成"
        done
        (dockerMain protocol links) >"${TEST_ROOT}/hosts-replace-links.after"
        cmp -s "${TEST_ROOT}/hosts-replace-links.before" "${TEST_ROOT}/hosts-replace-links.after" &&
            [[ "$(find "${root}/data" -type f -print0 | sort -z | xargs -0 -r sha256sum)" == "${hostsReplaceDataBefore}" ]] ||
            fail 'hosts 增删改变分享 URI、订阅或非空累计流量'
    done
done
jq -n '[range(0;255) | {key:"boundary-\(.).example.com",value:"203.0.113.10"}] | from_entries' \
    >"${PRIVATE_ROOT}/hosts-boundary.json"
chmod 0600 "${PRIVATE_ROOT}/hosts-boundary.json"
runEdit 0 --hosts "${PRIVATE_ROOT}/hosts-boundary.json" --confirm PADM-DOCKER-EDIT
runEdit 0 --hosts-add boundary-255.example.com 203.0.113.12 --confirm PADM-DOCKER-EDIT
jq -e '(.routing.hosts|length)==256 and .routing.hosts["boundary-255.example.com"]=="203.0.113.12"' \
    "${root}/config/spec.json" >/dev/null || fail 'hosts 追加第 256 键被拒绝或未精确保留'
before=$(snapshot)
composeBefore=$(cat "${COMPOSE_LOG}")
runEdit 15 --hosts-add boundary-256.example.com 203.0.113.12 --confirm PADM-DOCKER-EDIT
runEdit 2 --hosts-add boundary-256.example.com 127.0.0.1 --preview
[[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
    fail 'hosts 第 257 键或非法地址拒绝改变部署或调用 Compose'
runEdit 0 --hosts "${HOSTS_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/hosts-replace.before" --slurpfile actual "${root}/config/spec.json" \
    '$actual==$old' >/dev/null || fail 'hosts 增删和边界合同未还原原组合规格'
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/hosts-replace-resume.json" '' '' configure
) >"${LOG}" 2>&1 || fail 'hosts 替换合同未恢复原 DNS/hosts 流程'
assertClean
printf 'docker-routing-hosts-replace-regression-ok\n'
fi
if [[ "${ROUTING_BRANCH}" != hosts ]]; then
# dns-hosts 定向入口执行这组增量事务，不重复已有 DNS 生成器和真实 UDP 矩阵。
dnsAddCsv=' GEOSITE:CN , Full:DNS.Example.COM , DNS.Example.NET , Full:Added.Example.ORG , Added.Example.ORG , KEYWORD:Next_DNS , full:added.example.org '
dnsAdded='["full:dns.example.com","domain:dns.example.net","keyword:dns-video","geosite:cn","full:added.example.org","domain:added.example.org","keyword:next_dns"]'
dnsRemoveCsv=' Full:Added.Example.ORG , DNS.Example.NET , GEOSITE:CN , full:added.example.org '
dnsRemaining='["full:dns.example.com","keyword:dns-video","domain:added.example.org","keyword:next_dns"]'
cp -- "${root}/config/spec.json" "${TEST_ROOT}/dns-incremental.before"
before=$(snapshot)
runEdit 0 --dns-domains-add "${dnsAddCsv}" --preview
[[ "$(snapshot)" == "${before}" ]] || fail 'DNS 域名追加预览改变部署'
runEdit 0 --dns-domains-add "${dnsAddCsv}" --confirm PADM-DOCKER-EDIT
runEdit 0 --dns-domains-add "${dnsAddCsv}" --confirm PADM-DOCKER-EDIT
jq -en --argjson domains "${dnsAdded}" --slurpfile old "${TEST_ROOT}/dns-incremental.before" \
    --slurpfile actual "${root}/config/spec.json" '
  $actual[0] == ($old[0] | .routing.dns.domains=$domains)
' >/dev/null || fail 'DNS 追加未规范化、稳定去重或改变 server/port、hosts 与其它路由'
runStatus 0
jq -e --argjson domains "${dnsAdded}" --argjson hosts "${HOSTS}" '
  .dns == {server:"203.0.113.53",port:5353,domain_rules:$domains} and .hosts==$hosts
' "${LOG}" >/dev/null || fail 'DNS 追加状态未保留原上游、端口、hosts 和有序名单'
before=$(snapshot)
runEdit 0 --dns-domains-remove "${dnsRemoveCsv}" --preview
previewCompose=$(cat "${COMPOSE_LOG}")
runEdit 15 --dns-domains-remove 'dns.example.com' --confirm PADM-DOCKER-EDIT
runEdit 15 --dns-domains-remove "${dnsRemoveCsv},missing.example.net" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${previewCompose}" ]] ||
    fail 'DNS 删除缺项或部分缺项改变部署、停服或把 full 规则当作裸域名'
for action in add remove; do
    csv=failure.example.net
    [[ "${action}" != remove ]] || csv=${dnsRemoveCsv}
    for failure in health-fail int term; do
        MODE=${failure}
        rm -f -- "${TEST_ROOT}/failed-once"
        expected=14
        [[ "${failure}" != int ]] || expected=130
        [[ "${failure}" != term ]] || expected=143
        runEdit "${expected}" "--dns-domains-${action}" "${csv}" --confirm PADM-DOCKER-EDIT
        [[ "$(snapshot)" == "${before}" ]] ||
            fail "${action}/${failure}: DNS 增量未恢复上游、端口、其它路由及非空流量"
    done
done
MODE=ok
runEdit 0 --dns-domains-remove "${dnsRemoveCsv}" --confirm PADM-DOCKER-EDIT
jq -en --argjson domains "${dnsRemaining}" --slurpfile old "${TEST_ROOT}/dns-incremental.before" \
    --slurpfile actual "${root}/config/spec.json" '
  $actual[0] == ($old[0] | .routing.dns.domains=$domains)
' >/dev/null || fail 'DNS 删除未精确匹配完整规则、保留其余次序或改变上游与其它路由'
before=$(snapshot)
composeBefore=$(cat "${COMPOSE_LOG}")
runEdit 15 --dns-domains-remove "${dnsRemoveCsv}" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
    fail '重复 DNS 删除改变部署或调用 Compose'
dnsBoundaryCsv=$(jq -nr '[range(0;252) | "dns-boundary-\(.).example.org"] | join(",")')
runEdit 0 --dns-domains-add "${dnsBoundaryCsv}" --confirm PADM-DOCKER-EDIT
jq -e --argjson domains "${dnsRemaining}" '
  .routing.dns.domains == ($domains + [range(0;252) | "domain:dns-boundary-\(.).example.org"])
' "${root}/config/spec.json" >/dev/null || fail 'DNS 联合 256 项没有保留历史次序'
before=$(snapshot)
runEdit 0 --dns-domains-add 'FULL:DNS.EXAMPLE.COM,dns-boundary-251.example.org' --preview
composeBefore=$(cat "${COMPOSE_LOG}")
runEdit 15 --dns-domains-add 'dns-boundary-252.example.org' --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
    fail 'DNS 联合超过 256 项改变部署或调用 Compose'
dnsAllCsv=$(jq -r '.routing.dns.domains | join(",")' "${root}/config/spec.json")
runEdit 0 --dns-domains-remove "${dnsAllCsv}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/dns-incremental.before" --slurpfile actual "${root}/config/spec.json" \
    '$actual[0] == ($old[0] | del(.routing.dns))' >/dev/null ||
    fail 'DNS 删空未删除完整上游设置或破坏其它路由子项'
runEdit 0 --dns "${DNS_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/routing-all.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual==$expected' >/dev/null || fail 'DNS 增量合同未恢复原 DNS 与其它路由夹具'
fi
if [[ "${ROUTING_BRANCH}" != dns ]]; then
runEdit 0 --hosts-off --confirm PADM-DOCKER-EDIT
jq -e --argjson dns "${DNS}" --argjson domains "${DOMAINS}" '
  .routing == {dns:$dns,socks5:{server:"203.0.113.9",port:1080,
    username:"routing-user-secret-marker",password:"routing-password-secret-marker",domains:$domains}}
' "${root}/config/spec.json" >/dev/null || fail '关闭 hosts 破坏 DNS/SOCKS5'
cp -- "${root}/config/spec.json" "${TEST_ROOT}/hosts-absent.before"
before=$(snapshot)
composeBefore=$(cat "${COMPOSE_LOG}")
runEdit 15 --hosts-remove exact.example.com --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
    fail '未启用 hosts 的删除改变部署或调用 Compose'
runEdit 0 --hosts-add Added.Example.Com 2001:0DB8::12 --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/hosts-absent.before" --slurpfile actual "${root}/config/spec.json" \
    '$actual[0]==($old[0]|.routing.hosts={"added.example.com":"2001:0DB8::12"})' >/dev/null ||
    fail '缺省 hosts 追加未创建单键或改变已有 DNS/SOCKS5'
runEdit 0 --hosts-remove Added.Example.Com --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/hosts-absent.before" --slurpfile actual "${root}/config/spec.json" \
    '$actual==$old' >/dev/null || fail 'hosts 删空未清理 hosts 或破坏共存 routing'
runEdit 0 --hosts "${HOSTS_INPUT}" --confirm PADM-DOCKER-EDIT
runEdit 0 --socks5-off --confirm PADM-DOCKER-EDIT
jq -e --argjson dns "${DNS}" --argjson hosts "${HOSTS}" '.routing == {dns:$dns,hosts:$hosts}' \
    "${root}/config/spec.json" >/dev/null || fail '关闭 SOCKS5 丢弃 DNS/hosts'
runEdit 0 --dns-off --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/hosts-only.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail '关闭 DNS 破坏 hosts 或其它规格'
runStatus 0
jq -e --argjson hosts "${HOSTS}" '.enabled == true and .mode == "direct" and .hosts == $hosts and
  (has("dns") | not)' "${LOG}" >/dev/null || fail 'hosts 独立状态或 DNS 关闭合同错误'
runEdit 0 --hosts-off --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/base.json" --slurpfile new "${root}/config/spec.json" \
    '$new == $old' >/dev/null || fail '关闭最后一个路由字段未恢复无 routing 规格'
for core in xray sing-box; do
    cp -- "${root}/config/${core}/config.json" "${TEST_ROOT}/hosts-empty-${core}.before"
done
runEdit 0 --hosts-add Last.Example.Com 203.0.113.12 --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/base.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual[0]==($old[0]|.routing={hosts:{"last.example.com":"203.0.113.12"}})' >/dev/null ||
    fail '无 routing 时 hosts 追加未创建精确规格'
before=$(snapshot)
MODE=health-fail
rm -f -- "${TEST_ROOT}/failed-once"
runEdit 14 --hosts-remove Last.Example.Com --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '健康失败: hosts 末键删除未恢复完整部署和流量'
MODE=ok
runEdit 0 --hosts-remove Last.Example.Com --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/base.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual==$old' >/dev/null || fail 'hosts 末键删除没有清理空 routing'
runStatus 0
jq -e '.enabled==false and (has("hosts")|not)' "${LOG}" >/dev/null ||
    fail 'hosts 末键删除后状态未关闭 hosts'
for core in xray sing-box; do
    cmp -s "${TEST_ROOT}/hosts-empty-${core}.before" "${root}/config/${core}/config.json" ||
        fail "${core}: hosts 末键删除未恢复无 DNS/hosts 的原生成"
done
printf 'docker-routing-hosts-incremental-regression-ok\n'
fi
if [[ "${ROUTING_BRANCH}" != hosts ]]; then
if [[ "${ROUTING_BRANCH}" == dns ]]; then
    # DNS 分支恢复原 hosts 末键删除后的基线，再验证 DNS 删除清空 routing。
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/base.json" '' '' configure
    ) >"${LOG}" 2>&1 || fail '恢复独立 DNS 末项删除前基线失败'
    assertClean
fi
runEdit 0 --dns "${DNS_INPUT}" --confirm PADM-DOCKER-EDIT
runEdit 0 --dns-domains-remove "${DNS_CSV}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/base.json" --slurpfile new "${root}/config/spec.json" \
    '$new == $old' >/dev/null || fail '删除最后 DNS 名单没有清理空 routing'
printf 'docker-routing-dns-domains-incremental-regression-ok\n'
fi
jq -e --arg uuid "${UUID}" '.accounts[$uuid].upload == 17 and .accounts[$uuid].download == 19' \
    "${root}/data/traffic/state.json" >/dev/null || fail 'DNS/hosts 事务清空流量'
if [[ "${ROUTING_BRANCH}" == hosts ]]; then
    printf 'docker-routing-hosts-regression-ok\n'
    exit 0
fi

fi
# Direct/Block 沿用相同事务，同时验证同域规则允许共存并保留其它路由子项。
if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-dns-hosts ]]; then
if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-direct-block-csv ]]; then
before=$(snapshot)
composeBefore=$(cat "${COMPOSE_LOG}")
for kind in direct block; do
    runEdit 15 "--${kind}-domains-replace" 'example.net' 'replacement.example.org' --confirm PADM-DOCKER-EDIT
done
[[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
    fail '未启用 Direct/Block 的单项替换改变部署或调用 Compose'
runEdit 0 --direct-domains-add "${DOMAINS_CSV}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/direct-only.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail 'Direct CSV 追加缺项未创建规范化规则或改变其它规格'
runStatus 0
jq -e --argjson domains "${DOMAINS}" '.enabled == true and .direct == {domain_rules:$domains} and
  .direct_block_overlaps == [] and (has("block") | not)' "${LOG}" >/dev/null || fail 'Direct 状态投影错误'
before=$(snapshot)
runEdit 15 --spec "${TEST_ROOT}/base.json" --confirm PADM-DOCKER-EDIT
runEdit 15 --spec "${TEST_ROOT}/block-only.json" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '普通 --spec 绕过 Direct/Block 冻结'
runEdit 0 --block-domains-add "${DOMAINS_CSV}" --confirm PADM-DOCKER-EDIT
before=$(snapshot)
runStatus 0
jq -e --argjson domains "${DOMAINS}" '.direct == {domain_rules:$domains} and
  .block == {domain_rules:$domains} and .direct_block_overlaps == $domains' \
    "${LOG}" >/dev/null || fail 'Direct/Block 同域状态未保留两项或遗漏精确交集'
[[ "$(snapshot)" == "${before}" ]] || fail 'Direct/Block 精确交集诊断改变部署'
[[ "$(stat -c '%a %u %h' "${root}/config/spec.json")" == '600 0 1' ]] ||
    fail 'Direct/Block 规格未保留 root 私有权限'
before=$(snapshot)
for failure in health-fail int term; do
    MODE=${failure}
    rm -f -- "${TEST_ROOT}/failed-once"
    case "${failure}" in
    health-fail) runEdit 14 --direct-off --confirm PADM-DOCKER-EDIT ;;
    int) runEdit 130 --block-off --confirm PADM-DOCKER-EDIT ;;
    term) runEdit 143 --direct-off --confirm PADM-DOCKER-EDIT ;;
    esac
    [[ "$(snapshot)" == "${before}" ]] || fail "${failure}: Direct/Block 没有恢复完整部署和流量"
done
MODE=ok
runEdit 0 --dns "${DNS_INPUT}" --confirm PADM-DOCKER-EDIT
runEdit 0 --hosts "${HOSTS_INPUT}" --confirm PADM-DOCKER-EDIT
runEdit 0 --socks5 "${INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/routing-policy.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail '开启旧子项丢弃 Direct/Block'
before=$(snapshot)
composeBefore=$(cat "${COMPOSE_LOG}")
runEdit 15 --block-ips-replace 192.0.2.10 203.0.113.20 --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
    fail '未启用手工 IP 阻断时单项替换改变部署或调用 Compose'
runEdit 0 --block-ips-add "${BLOCK_IPS_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/routing-ip-policy.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail 'IP 追加未创建缺失名单或改变已有子项'
[[ "$(stat -c '%a %u %h' "${root}/config/spec.json")" == '600 0 1' ]] ||
    fail 'IP 阻断规格未保留私有权限'
# 此段同样由 Direct/Block 的 IP 定向入口执行，不依赖上方被跳过的旧输入矩阵。
ipAdded='["192.0.2.10","2001:db8::10","198.51.100.0/24","2001:db8::/64","geoip:cn","2001:DB8::10","2001:db8:0:0:0:0:0:10","198.51.100.17/24","203.0.113.9"]'
ipRemaining='["192.0.2.10","2001:db8::/64","geoip:cn","2001:DB8::10","2001:db8:0:0:0:0:0:10","198.51.100.17/24","203.0.113.9"]'
printf '%s\n' '{"ips":["192.0.2.10","2001:DB8::10","2001:db8:0:0:0:0:0:10","198.51.100.17/24","203.0.113.9"]}' \
    >"${IP_DELTA_INPUT}"
chmod 0600 "${IP_DELTA_INPUT}"
before=$(snapshot)
runEdit 0 --block-ips-add "${IP_DELTA_INPUT}" --preview
[[ "$(snapshot)" == "${before}" ]] || fail 'IP 追加预览改变在线部署'
runEdit 0 --block-ips-add "${IP_DELTA_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --argjson ips "${ipAdded}" --slurpfile old "${TEST_ROOT}/routing-ip-policy.json" \
    --slurpfile actual "${root}/config/spec.json" '
  $actual[0] == ($old[0] | .routing.block_ips.ips=$ips)
' >/dev/null || fail 'IP 追加未保持首次次序、去除已有项或保留 IPv6/CIDR 完整字符串身份'
runStatus 0
jq -e --argjson ips "${ipAdded}" '.block_ips.ip_rules==$ips' "${LOG}" >/dev/null ||
    fail 'IP 增量状态未投影有序手工名单'
before=$(snapshot)
composeBefore=$(cat "${COMPOSE_LOG}")
for action in add remove; do
    runEdit 2 "--block-ips-${action}"
    runEdit 2 "--block-ips-${action}" "${IP_DELTA_INPUT}" --block-ips-off --preview
    chmod 0640 "${IP_DELTA_INPUT}"
    runEdit 15 "--block-ips-${action}" "${IP_DELTA_INPUT}" --preview
    chmod 0600 "${IP_DELTA_INPUT}"
    ln -s "${IP_DELTA_INPUT}" "${PRIVATE_ROOT}/ip-delta-link.json"
    runEdit 15 "--block-ips-${action}" "${PRIVATE_ROOT}/ip-delta-link.json" --preview
    rm -- "${PRIVATE_ROOT}/ip-delta-link.json"
    for invalid in '{"ips":[]}' '{"ips":["192.0.2.10","192.0.2.10"]}' \
        '{"ips":["geoip:CN"]}' '{"ips":["198.51.100.0/33"]}' '{"ips":["2001:db8:::1"]}' \
        '{"ips":["192.0.2.10"],"extra":true}'; do
        printf '%s\n' "${invalid}" >"${IP_DELTA_INPUT}"
        runEdit 15 "--block-ips-${action}" "${IP_DELTA_INPUT}" --preview
    done
done
# 合法请求中有一项缺失时整组拒绝，不能先删除已存在的项或停服。
printf '%s\n' '{"ips":["2001:db8::10","203.0.113.250"]}' >"${IP_DELTA_INPUT}"
runEdit 15 --block-ips-remove "${IP_DELTA_INPUT}" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
    fail 'IP 坏输入、私有文件边界或部分缺项拒绝改变部署或调用 Compose'
for action in add remove; do
    if [[ "${action}" == add ]]; then
        printf '%s\n' '{"ips":["203.0.113.250"]}' >"${IP_DELTA_INPUT}"
    else
        printf '%s\n' '{"ips":["2001:db8::10","198.51.100.0/24"]}' >"${IP_DELTA_INPUT}"
    fi
    for failure in health-fail int term; do
        MODE=${failure}
        rm -f -- "${TEST_ROOT}/failed-once"
        expected=14
        [[ "${failure}" != int ]] || expected=130
        [[ "${failure}" != term ]] || expected=143
        runEdit "${expected}" "--block-ips-${action}" "${IP_DELTA_INPUT}" --confirm PADM-DOCKER-EDIT
        [[ "$(snapshot)" == "${before}" ]] ||
            fail "${action}/${failure}: IP 增量未恢复路由、核心、订阅和非空流量"
    done
done
MODE=ok
runEdit 0 --block-ips-remove "${IP_DELTA_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --argjson ips "${ipRemaining}" --slurpfile old "${TEST_ROOT}/routing-ip-policy.json" \
    --slurpfile actual "${root}/config/spec.json" '
  $actual[0] == ($old[0] | .routing.block_ips.ips=$ips)
' >/dev/null || fail 'IP 删除未精确匹配字符串、保留其余次序或改动其它策略'
before=$(snapshot)
composeBefore=$(cat "${COMPOSE_LOG}")
runEdit 15 --block-ips-remove "${IP_DELTA_INPUT}" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
    fail '重复 IP 删除改变部署或调用 Compose'
jq -n '{ips:[range(0;249) | "203.0.114.\(.)"]}' >"${IP_DELTA_INPUT}"
runEdit 0 --block-ips-add "${IP_DELTA_INPUT}" --confirm PADM-DOCKER-EDIT
jq -e --argjson ips "${ipRemaining}" '
  .routing.block_ips.ips == ($ips + [range(0;249) | "203.0.114.\(.)"])
' "${root}/config/spec.json" >/dev/null || fail 'IP 联合 256 项未保留历史和追加次序'
before=$(snapshot)
runEdit 0 --block-ips-add "${IP_DELTA_INPUT}" --preview
composeBefore=$(cat "${COMPOSE_LOG}")
printf '%s\n' '{"ips":["203.0.114.249"]}' >"${IP_DELTA_INPUT}"
runEdit 15 --block-ips-add "${IP_DELTA_INPUT}" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
    fail 'IP 合并超过 256 项时改变部署或调用 Compose'
runEdit 0 --block-ips "${BLOCK_IPS_INPUT}" --confirm PADM-DOCKER-EDIT
runEdit 0 --region ip --confirm PADM-DOCKER-EDIT
cp -- "${root}/config/spec.json" "${TEST_ROOT}/ip-region.before"
# 单项替换只改手工名单；IPv6 写法和 CIDR 宿主位保留原文，不编辑区域合成。
ipReplaceOld=2001:db8::10 ipReplaceNew=2001:DB8:0:0:0:0:0:10
before=$(snapshot)
composeBefore=$(cat "${COMPOSE_LOG}")
runEdit 2 --block-ips-replace
runEdit 2 --block-ips-replace "${ipReplaceOld}" --preview
runEdit 2 --block-ips-replace "${ipReplaceOld}" "${ipReplaceNew}"
runEdit 2 --block-ips-replace "${ipReplaceOld}" "${ipReplaceNew}" --confirm invalid
for invalid in '' 'geoip:cn' 'geoip:CN' '192.0.2.256' '192.0.2.01' '2001:db8:::1' \
    '198.51.100.0/33' '2001:db8::/129' '198.51.100.0/24/1' 'example.com' 'domain:example.com' \
    ' 2001:db8::10' '2001:db8::10 ' '2001:db8::10,2001:db8::10' \
    '192.0.2.10,203.0.113.20' ',192.0.2.10' '192.0.2.10,'; do
    runEdit 2 --block-ips-replace "${invalid}" "${ipReplaceNew}" --preview
    runEdit 2 --block-ips-replace "${ipReplaceOld}" "${invalid}" --preview
done
runEdit 2 --block-ips-replace "${ipReplaceOld}" "${ipReplaceNew}" --block-ips-off --preview
runEdit 2 --block-ips-off --block-ips-replace "${ipReplaceOld}" "${ipReplaceNew}" --preview
runEdit 2 --block-ips-replace "${ipReplaceOld}" "${ipReplaceNew}" --block-ips "${BLOCK_IPS_INPUT}" --preview
runEdit 2 --block-ips-replace "${ipReplaceOld}" "${ipReplaceNew}" --block-ips-add "${BLOCK_IPS_INPUT}" --preview
runEdit 2 --block-ips-replace "${ipReplaceOld}" "${ipReplaceNew}" --block-ips-remove "${BLOCK_IPS_INPUT}" --preview
runEdit 2 --block-ips-replace "${ipReplaceOld}" "${ipReplaceNew}" \
    --block-ips-replace "${ipReplaceOld}" "${ipReplaceNew}" --preview
runEdit 2 --block-ips-replace "${ipReplaceOld}" "${ipReplaceNew}" --region ip --preview
runEdit 2 --block-ips-replace "${ipReplaceOld}" "${ipReplaceNew}" --direct-off --preview
runEdit 2 --block-ips-replace "${ipReplaceOld}" "${ipReplaceNew}" --spec "${TEST_ROOT}/ip-region.before" --preview
runEdit 2 --block-ips-replace "${ipReplaceOld}" "${ipReplaceNew}" --http01 enable --preview
runEdit 15 --block-ips-replace 203.0.113.250 "${ipReplaceNew}" --confirm PADM-DOCKER-EDIT
runEdit 15 --block-ips-replace "${ipReplaceNew}" 203.0.113.20 --confirm PADM-DOCKER-EDIT
runEdit 15 --block-ips-replace 2001:DB8::10 203.0.113.20 --confirm PADM-DOCKER-EDIT
runEdit 15 --block-ips-replace 2001:db8:0:0:0:0:0:10 203.0.113.20 --confirm PADM-DOCKER-EDIT
runEdit 15 --block-ips-replace 198.51.100.17/24 203.0.113.0/24 --confirm PADM-DOCKER-EDIT
runEdit 15 --block-ips-replace "${ipReplaceOld}" 192.0.2.10 --confirm PADM-DOCKER-EDIT
runEdit 15 --block-ips-replace "${ipReplaceOld}" "${ipReplaceOld}" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
    fail 'IP 单项替换双侧非法、缺旧、同地址异文、重复新或同值拒绝改变部署或调用 Compose'
jq --arg ip "${ipReplaceNew}" '.routing.block_ips.ips[1]=$ip' "${TEST_ROOT}/ip-region.before" \
    >"${TEST_ROOT}/ip-replace-cancel.json"
runEdit 0 --block-ips-replace "${ipReplaceOld}" "${ipReplaceNew}" --preview
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerSetupRead() { printf -v "$1" '%s' n; }
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/ip-replace-cancel.json" '' '' interactive
) >"${LOG}" 2>&1 || fail 'IP 单项替换确认取消失败'
assertClean
[[ "$(snapshot)" == "${before}" ]] || fail 'IP 单项替换预览或取消改变完整部署'
MODE=health-fail
rm -f -- "${TEST_ROOT}/failed-once"
runEdit 14 --block-ips-replace "${ipReplaceOld}" "${ipReplaceNew}" --confirm PADM-DOCKER-EDIT
MODE=ok
[[ "$(snapshot)" == "${before}" ]] || fail 'IP 单项替换健康失败未恢复完整配置、区域规则和非空流量'
for core in xray sing-box; do
    cp -- "${root}/config/${core}/config.json" "${TEST_ROOT}/ip-replace-${core}.before"
done
(dockerMain protocol links) >"${TEST_ROOT}/ip-replace-links.before"
ipReplaceDataBefore=$(find "${root}/data" -type f -print0 | sort -z | xargs -0 -r sha256sum)
for ipReplaceKind in ipv6 cidr; do
    ipReplaceIndex=1 ipReplaceOld=2001:db8::10 ipReplaceNew=2001:DB8:0:0:0:0:0:10
    if [[ "${ipReplaceKind}" == cidr ]]; then
        ipReplaceIndex=2 ipReplaceOld=198.51.100.0/24 ipReplaceNew=198.51.100.17/24
    fi
    runEdit 0 --block-ips-replace "${ipReplaceOld}" "${ipReplaceNew}" --confirm PADM-DOCKER-EDIT
    jq -en --argjson index "${ipReplaceIndex}" --arg ip "${ipReplaceNew}" \
        --slurpfile old "${TEST_ROOT}/ip-region.before" --slurpfile actual "${root}/config/spec.json" '
      $actual[0] == ($old[0] | .routing.block_ips.ips[$index]=$ip)
    ' >/dev/null || fail "${ipReplaceKind}: 单项替换未保留原文、原位置或改变其它完整规格"
    runStatus 0
    jq -e --argjson index "${ipReplaceIndex}" --arg ip "${ipReplaceNew}" \
        --slurpfile old "${TEST_ROOT}/ip-region.before" '
      .block_ips.ip_rules == ($old[0].routing.block_ips.ips | .[$index]=$ip) and
      .region.mode=="ip"
    ' "${LOG}" >/dev/null || fail "${ipReplaceKind}: 单项替换状态改变原文、顺序或区域策略"
    for core in xray sing-box; do
        jq -en --arg core "${core}" --slurpfile old "${TEST_ROOT}/ip-replace-${core}.before" \
            --slurpfile new "${root}/config/${core}/config.json" '
          if $core=="xray" then ($old[0]|del(.routing))==($new[0]|del(.routing))
          else ($old[0]|del(.route))==($new[0]|del(.route)) end
        ' >/dev/null || fail "${ipReplaceKind}/${core}: 单项替换改变核心认证、监听或其它配置"
    done
    (dockerMain protocol links) >"${TEST_ROOT}/ip-replace-links.after"
    cmp -s "${TEST_ROOT}/ip-replace-links.before" "${TEST_ROOT}/ip-replace-links.after" &&
        [[ "$(find "${root}/data" -type f -print0 | sort -z | xargs -0 -r sha256sum)" == "${ipReplaceDataBefore}" ]] ||
        fail "${ipReplaceKind}: 单项替换改变分享 URI、订阅或累计流量"
    runEdit 0 --block-ips-replace "${ipReplaceNew}" "${ipReplaceOld}" --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile old "${TEST_ROOT}/ip-region.before" --slurpfile actual "${root}/config/spec.json" \
        '$actual==$old' >/dev/null || fail "${ipReplaceKind}: 反向单项替换未还原原组合规格"
done
printf 'docker-routing-block-ips-replace-regression-ok\n'
runEdit 0 --block-ips-remove "${BLOCK_IPS_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/ip-region.before" --slurpfile actual "${root}/config/spec.json" \
    '$actual[0] == ($old[0] | del(.routing.block_ips))' >/dev/null ||
    fail '删除全部手工 IP 未清理子项或改变区域策略和其它路由'
jq -e 'any(.routing.rules[]; .ip==["geoip:cn"] and .outboundTag=="blocked")' \
    "${root}/config/xray/config.json" >/dev/null || fail '删空手工 IP 误删区域合成 GeoIP 阻断'
before=$(snapshot)
composeBefore=$(cat "${COMPOSE_LOG}")
printf '%s\n' '{"ips":["geoip:cn"]}' >"${IP_DELTA_INPUT}"
runEdit 15 --block-ips-remove "${IP_DELTA_INPUT}" --confirm PADM-DOCKER-EDIT
runEdit 15 --block-ips-replace 192.0.2.10 203.0.113.20 --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" && "$(cat "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
    fail 'IP 删除把区域合成项当作手工名单或调用 Compose'
runEdit 0 --block-ips-add "${BLOCK_IPS_INPUT}" --confirm PADM-DOCKER-EDIT
runEdit 0 --region-off --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/routing-ip-policy.json" \
    --slurpfile actual "${root}/config/spec.json" '$actual==$expected' >/dev/null ||
    fail 'IP 增量合同结束没有恢复原路由夹具'
printf 'docker-routing-block-ips-incremental-regression-ok\n'
fi
if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-direct-block-ip ]]; then
# CSV 是整组替换；其它子项、核心身份、分享内容与累计流量保持原样。
csvReplacement=' geosite:CN , KEYWORD:Next_Video , Full:New.Example.ORG , New.Example.NET , full:new.example.org '
csvReplacementDomains='["geosite:cn","keyword:next_video","full:new.example.org","domain:new.example.net"]'
csvAppendedDomains='["geosite:cn","keyword:next_video","full:new.example.org","domain:new.example.net","full:exact.example.com","full:other.example.com","domain:example.net","keyword:video","geosite:category-ads-all"]'
csvRemoval=' Full:Exact.Example.Com , Example.NET , KEYWORD:Video , geosite:CN , example.net , FULL:EXACT.EXAMPLE.COM '
csvRemovedDomains='["keyword:next_video","full:new.example.org","domain:new.example.net","full:other.example.com","geosite:category-ads-all","domain:exact.example.com"]'
runEdit 0 --region domain --region-allow 'exact.example.com,full:exact.example.com' --confirm PADM-DOCKER-EDIT
for kind in direct block; do
    domainsReplaceCheck "${kind}"
    option="--${kind}-domains"
    before=$(snapshot)
    runEdit 0 "${option}" "${csvReplacement}" --preview
    jq --arg kind "${kind}" --argjson domains "${csvReplacementDomains}" \
        '.routing[$kind].domains=$domains' "${root}/config/spec.json" >"${TEST_ROOT}/csv-import.json"
    runEdit 15 --spec "${TEST_ROOT}/csv-import.json" --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail "${kind}: CSV 预览或普通 spec 导入改变部署"
    cp -- "${root}/config/spec.json" "${TEST_ROOT}/csv-before.json"
    for core in xray sing-box; do
        cp -- "${root}/config/${core}/config.json" "${TEST_ROOT}/csv-${core}.before"
    done
    (dockerMain protocol links) >"${TEST_ROOT}/csv-links.before"
    sha256sum "${root}/data/traffic/state.json" >"${TEST_ROOT}/csv-traffic.before"
    find "${root}/data/subscription" -type f -print0 | sort -z | xargs -0 -r sha256sum \
        >"${TEST_ROOT}/csv-subscription.before"
    runEdit 0 "${option}" "${csvReplacement}" --confirm PADM-DOCKER-EDIT
    jq -en --arg kind "${kind}" --argjson domains "${csvReplacementDomains}" \
        --slurpfile old "${TEST_ROOT}/csv-before.json" --slurpfile new "${root}/config/spec.json" '
      $new[0] == ($old[0] | .routing[$kind].domains=$domains)
    ' >/dev/null || fail "${kind}: CSV 没有整组替换或改写其它路由、核心及订阅规格"
    runStatus 0
    jq -e --arg kind "${kind}" --argjson domains "${csvReplacementDomains}" \
        '.[$kind].domain_rules==$domains' "${LOG}" >/dev/null ||
        fail "${kind}: CSV 状态不是规范化后的有序数组"
    addOption="${option}-add"
    before=$(snapshot)
    runEdit 0 "${addOption}" "${DOMAINS_CSV}" --preview
    jq --arg kind "${kind}" --argjson domains "${csvAppendedDomains}" \
        '.routing[$kind].domains=$domains' "${root}/config/spec.json" >"${TEST_ROOT}/csv-add-import.json"
    runEdit 15 --spec "${TEST_ROOT}/csv-add-import.json" --confirm PADM-DOCKER-EDIT
    if [[ "${kind}" == direct ]]; then
        (
            trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
            dockerSetupRead() { printf -v "$1" '%s' n; }
            dockerAcquireDeploymentLock
            dockerConfigureApply "${TEST_ROOT}/csv-add-import.json" '' '' interactive
        ) >"${LOG}" 2>&1 || fail 'CSV 追加确认取消失败'
        assertClean
    fi
    [[ "$(snapshot)" == "${before}" ]] ||
        fail "${kind}: CSV 追加预览、普通 spec 导入或取消改变部署"
    runEdit 0 "${addOption}" "${DOMAINS_CSV}" --confirm PADM-DOCKER-EDIT
    runEdit 0 "${addOption}" "${DOMAINS_CSV}" --confirm PADM-DOCKER-EDIT
    jq -en --arg kind "${kind}" --argjson domains "${csvAppendedDomains}" \
        --slurpfile old "${TEST_ROOT}/csv-before.json" --slurpfile new "${root}/config/spec.json" '
      $new[0] == ($old[0] | .routing[$kind].domains=$domains)
    ' >/dev/null || fail "${kind}: 追加丢失历史、改变首次次序、重复追加或改写其它子项"
    runStatus 0
    jq -e --arg kind "${kind}" --argjson domains "${csvAppendedDomains}" \
        '.[$kind].domain_rules==$domains' "${LOG}" >/dev/null ||
        fail "${kind}: 追加状态未保留历史和新值的稳定次序"
    # 删除只匹配手工列表的完整规则；同域的 full/domain 与区域例外各自保留。
    runEdit 0 "${addOption}" 'Exact.Example.COM' --confirm PADM-DOCKER-EDIT
    if [[ "${kind}" == direct ]]; then
        before=$(snapshot)
        runStatus 0
        jq -e '.direct_block_overlaps == ["geosite:cn","full:exact.example.com","full:other.example.com",
          "domain:example.net","keyword:video","geosite:category-ads-all"]' "${LOG}" >/dev/null ||
            fail '精确交集未保持 Direct 次序或把同主机 full/domain 误报为交集'
        [[ "$(snapshot)" == "${before}" ]] || fail '有区域策略的精确交集诊断改变部署'
    fi
    removeOption="${option}-remove"
    cp -- "${root}/config/spec.json" "${TEST_ROOT}/csv-remove-before.json"
    before=$(snapshot)
    runEdit 0 "${removeOption}" "${csvRemoval}" --preview
    runEdit 15 "${removeOption}" 'missing.example.com' --confirm PADM-DOCKER-EDIT
    runEdit 15 "${removeOption}" "${csvRemoval},missing.example.com" --confirm PADM-DOCKER-EDIT
    jq --arg kind "${kind}" --argjson domains "${csvRemovedDomains}" \
        '.routing[$kind].domains=$domains' "${root}/config/spec.json" >"${TEST_ROOT}/csv-remove-import.json"
    runEdit 15 --spec "${TEST_ROOT}/csv-remove-import.json" --confirm PADM-DOCKER-EDIT
    if [[ "${kind}" == direct ]]; then
        (
            trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
            dockerSetupRead() { printf -v "$1" '%s' n; }
            dockerAcquireDeploymentLock
            dockerConfigureApply "${TEST_ROOT}/csv-remove-import.json" '' '' interactive
        ) >"${LOG}" 2>&1 || fail 'CSV 删除确认取消失败'
        assertClean
        MODE=health-fail
        rm -f -- "${TEST_ROOT}/failed-once"
        runEdit 14 "${removeOption}" "${csvRemoval}" --confirm PADM-DOCKER-EDIT
        MODE=ok
    fi
    [[ "$(snapshot)" == "${before}" ]] ||
        fail "${kind}: CSV 删除预览、缺项、部分缺项、普通导入、取消或健康失败改变部署"
    runEdit 0 "${removeOption}" "${csvRemoval}" --confirm PADM-DOCKER-EDIT
    jq -en --arg kind "${kind}" --argjson domains "${csvRemovedDomains}" \
        --slurpfile old "${TEST_ROOT}/csv-remove-before.json" --slurpfile new "${root}/config/spec.json" '
      $new[0] == ($old[0] | .routing[$kind].domains=$domains)
    ' >/dev/null || fail "${kind}: CSV 删除未精确匹配、保留次序与同域 domain 规则，或改变其它策略"
    before=$(snapshot)
    runStatus 0
    jq -e --arg kind "${kind}" --argjson domains "${csvRemovedDomains}" \
        '.[$kind].domain_rules==$domains' "${LOG}" >/dev/null ||
        fail "${kind}: CSV 删除状态未反映剩余有序规则"
    if [[ "${kind}" == direct ]]; then
        jq -e '.direct_block_overlaps == ["full:other.example.com","geosite:category-ads-all"]' \
            "${LOG}" >/dev/null || fail '删除后精确交集未更新或混入区域合成、同主机 full/domain 规则'
    fi
    [[ "$(snapshot)" == "${before}" ]] || fail "${kind}: 删除后的精确交集诊断改变部署"
    before=$(snapshot)
    runEdit 15 "${removeOption}" "${csvRemoval}" --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail "${kind}: 重复删除改变部署"
    for core in xray sing-box; do
        jq -en --arg core "${core}" --slurpfile old "${TEST_ROOT}/csv-${core}.before" \
            --slurpfile new "${root}/config/${core}/config.json" '
          if $core == "xray" then ($old[0]|del(.routing)) == ($new[0]|del(.routing))
          else ($old[0]|del(.route)) == ($new[0]|del(.route)) end
        ' >/dev/null || fail "${kind}: ${core} CSV 替换、追加或删除改变核心认证、监听或其它模板字段"
    done
    (dockerMain protocol links) >"${TEST_ROOT}/csv-links.after"
    cmp -s "${TEST_ROOT}/csv-links.before" "${TEST_ROOT}/csv-links.after" ||
        fail "${kind}: CSV 替换、追加或删除改变分享 URI"
    sha256sum -c "${TEST_ROOT}/csv-traffic.before" >/dev/null ||
        fail "${kind}: CSV 替换、追加或删除改变流量累计"
    find "${root}/data/subscription" -type f -print0 | sort -z | xargs -0 -r sha256sum \
        >"${TEST_ROOT}/csv-subscription.after"
    cmp -s "${TEST_ROOT}/csv-subscription.before" "${TEST_ROOT}/csv-subscription.after" ||
        fail "${kind}: CSV 替换、追加或删除改变已发布订阅"
    before=$(snapshot)
    for failure in health-fail int term; do
        MODE=${failure}
        rm -f -- "${TEST_ROOT}/failed-once"
        expected=14
        [[ "${failure}" != int ]] || expected=130
        [[ "${failure}" != term ]] || expected=143
        runEdit "${expected}" "${addOption}" 'replacement.example.org' --confirm PADM-DOCKER-EDIT
        [[ "$(snapshot)" == "${before}" ]] ||
            fail "${kind}/${failure}: CSV 追加未恢复路由、核心、订阅和流量快照"
    done
    MODE=ok
    runEdit 0 "--${kind}" "${PRIVATE_ROOT}/${kind}.json" --confirm PADM-DOCKER-EDIT
    if [[ "${kind}" == direct ]]; then
        jointBoundaryCsv=$(jq -nr '[range(0;250) | "boundary-\(.).example.com"] | join(",")')
        before=$(snapshot)
        runEdit 15 "${addOption}" "${jointBoundaryCsv},boundary-250.example.com" --preview
        [[ "$(snapshot)" == "${before}" ]] || fail 'CSV 联合超过 256 项时改变部署'
        runEdit 0 "${addOption}" "${jointBoundaryCsv}" --confirm PADM-DOCKER-EDIT
        jq -e --argjson history "${DOMAINS}" '
          .routing.direct.domains == ($history + [range(0;250) | "domain:boundary-\(.).example.com"])
        ' "${root}/config/spec.json" >/dev/null || fail 'CSV 联合 256 项上界没有保留历史顺序'
        before=$(snapshot)
        runEdit 0 "${addOption}" 'FULL:EXACT.EXAMPLE.COM,boundary-249.example.com' --preview
        runEdit 15 "${addOption}" 'boundary-250.example.com' --confirm PADM-DOCKER-EDIT
        [[ "$(snapshot)" == "${before}" ]] || fail 'CSV 联合上界预览或超限确认改变部署'
        runEdit 0 "--${kind}" "${PRIVATE_ROOT}/${kind}.json" --confirm PADM-DOCKER-EDIT
    fi
done
runEdit 0 --region-off --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/routing-ip-policy.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail 'CSV 替换后原 JSON 管理接口未恢复规则集合'
before=$(snapshot)
runEdit 15 --spec "${TEST_ROOT}/routing-policy.json" --confirm PADM-DOCKER-EDIT
for failure in health-fail int term; do
    MODE=${failure}
    rm -f -- "${TEST_ROOT}/failed-once"
    case "${failure}" in
    health-fail) runEdit 14 --block-ips-off --confirm PADM-DOCKER-EDIT ;;
    int) runEdit 130 --block-ips-off --confirm PADM-DOCKER-EDIT ;;
    term) runEdit 143 --block-ips-off --confirm PADM-DOCKER-EDIT ;;
    esac
    [[ "$(snapshot)" == "${before}" ]] || fail "${failure}: IP 阻断未恢复全部子项及流量"
done
MODE=ok
runEdit 0 --block-ips-off --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/routing-policy.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail '关闭 IP 阻断删除其它路由子项'
runEdit 0 --direct-domains-remove "${DOMAINS_CSV}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/routing-policy.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual[0] == ($expected[0] | del(.routing.direct))' >/dev/null ||
    fail '删除全部 Direct 规则未清理该子项或删除其它路由子项'
runEdit 0 --socks5-off --confirm PADM-DOCKER-EDIT
runEdit 0 --dns-off --confirm PADM-DOCKER-EDIT
runEdit 0 --hosts-off --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/block-only.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail '关闭其它路由子项删除 Block'
runEdit 0 --block-domains-remove "${DOMAINS_CSV}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/base.json" --slurpfile new "${root}/config/spec.json" \
    '$new == $old' >/dev/null || fail '删除全部 Block 规则没有删除空 routing'
before=$(snapshot)
runEdit 15 --block-domains-remove "${DOMAINS_CSV}" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '未启用 Block 删除规则改变部署'
jq -e --arg uuid "${UUID}" '.accounts[$uuid].upload == 17 and .accounts[$uuid].download == 19' \
    "${root}/data/traffic/state.json" >/dev/null || fail 'Direct/Block 事务清空流量'
runEdit 0 --block-ips-add "${BLOCK_IPS_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/block-ips-only.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail '独立 IP 阻断开启改变其它规格'
runStatus 0
jq -e --argjson input "${BLOCK_IPS}" '.enabled == true and .block_ips.ip_rules == $input.ips' \
    "${LOG}" >/dev/null || fail 'IP 阻断状态没有保留有效列表'
runEdit 0 --block-ips-remove "${BLOCK_IPS_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/base.json" --slurpfile new "${root}/config/spec.json" \
    '$new == $old' >/dev/null || fail '关闭最后 IP 阻断没有删除空 routing'
runStatus 0
jq -e 'has("block_ips") | not' "${LOG}" >/dev/null || fail 'IP 阻断关闭仍显示有效规则'
fi
fi

if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-direct-block &&
    "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-direct-block-ip &&
    "${PADM_DOCKER_ROUTING_SCOPE:-}" != domains-direct-block-csv ]]; then
menuLog="${TEST_ROOT}/routing-menu.log"
(
    dockerMenuRun() { printf '%s\n' "$*" >>"${menuLog}"; }
    dockerMenuRouting < <(printf '6\n0\n8\n0\n0\n')
) >"${LOG}" 2>&1
[[ ! -e "${menuLog}" ]] || fail 'DNS/hosts 菜单路径取消仍调用编辑'
(
    dockerMenuRun() { printf '%s\n' "$*" >>"${menuLog}"; }
    dockerMenuRouting < <(printf '6\n203.0.113.53\n\n%s\n7\n8\n%s\n9\n0\n' "${DNS_CSV}" "${HOSTS_INPUT}")
) >"${LOG}" 2>&1
printf 'edit --dns-rules 203.0.113.53 53 %s\nedit --dns-off\nedit --hosts %s\nedit --hosts-off\n' \
    "${DNS_CSV}" "${HOSTS_INPUT}" >"${TEST_ROOT}/routing-menu.expected"
cmp -s "${menuLog}" "${TEST_ROOT}/routing-menu.expected" ||
    fail 'DNS/hosts 菜单没有映射到 CLI 事务'
fi
if [[ "${ROUTING_BRANCH}" == dns ]]; then
    printf 'docker-routing-dns-regression-ok\n'
    exit 0
fi
printf 'docker-routing-socks5-regression-ok\n'
