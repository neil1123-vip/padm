#!/usr/bin/env bash
set -Eeuo pipefail

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
DNS_INPUT=${PRIVATE_ROOT}/dns.json
HOSTS_INPUT=${PRIVATE_ROOT}/hosts.json
DNS='{"server":"203.0.113.53","port":5353,"domains":["full:dns.example.com","domain:dns.example.net","keyword:dns-video","geosite:cn"]}'
HOSTS='{"exact.example.com":"203.0.113.10","ipv6.example.com":"2001:db8::10"}'
DIRECT_INPUT=${PRIVATE_ROOT}/direct.json
BLOCK_INPUT=${PRIVATE_ROOT}/block.json
BLOCK_IPS_INPUT=${PRIVATE_ROOT}/block-ips.json
BLOCK_IPS='{"ips":["192.0.2.10","2001:db8::10","198.51.100.0/24","2001:db8::/64","geoip:cn"]}'

fail() {
    [[ ! -f "${LOG}" ]] || sed 's/^/  /' "${LOG}" >&2
    printf 'docker-routing-socks5-regression-fail: %s\n' "$*" >&2
    exit 1
}
reject() { if "$@" >"${LOG}" 2>&1; then fail "应拒绝: $*"; fi; }
# 仅核心、宿主和发布使用桩；路由生成、权限、锁与恢复走生产代码。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
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
                       ("block-ips", ip_block), ("block-bt", bt_block)):
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
for fixture in routed domains dns-only hosts-only routing-all routing-all-global direct-only block-only routing-policy block-ips-only routing-ip-policy block-bt-only routing-bt-policy; do
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
for fixture in routed domains routing-all-global direct-only block-only routing-policy block-ips-only routing-ip-policy block-bt-only routing-bt-policy; do
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
    for fixture in routed domains dns-only hosts-only routing-all routing-all-global direct-only block-only routing-policy block-ips-only routing-ip-policy block-bt-only routing-bt-policy; do
        "${generator}" "${TEST_ROOT}/${fixture}.json" "${TEST_ROOT}/routed-generated.json"
        cmp -s "${TEST_ROOT}/legacy-generated.json" "${TEST_ROOT}/routed-generated.json" ||
            fail "${generator}: ${fixture} 意外改变容器能力或宿主端口"
    done
done

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
}
runStatus() {
    local expected=$1 actual=0
    shift
    (dockerMain protocol routing-status "$@") >"${LOG}" 2>"${TEST_ROOT}/status.stderr" || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "routing-status: 预期 ${expected}，实际 ${actual}"
    assertClean
    for output in "${LOG}" "${TEST_ROOT}/status.stderr"; do
        ! grep -Fq "${USERNAME}" "${output}" && ! grep -Fq "${PASSWORD}" "${output}" &&
            ! grep -Fq "${UUID}" "${output}" || fail '路由诊断泄露认证信息'
    done
}
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/base.json" '' '' configure
) >"${LOG}" 2>&1 || fail '初始化路由夹具失败'
assertClean
jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{($uuid):{
  name:"routing",upload:17,download:19,limit_bytes:0,baseline:{}}}}' | dockerTrafficWriteState
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
if [[ "${PADM_DOCKER_ROUTING_SCOPE:-}" == bt ]]; then
    printf 'docker-routing-block-bt-regression-ok\n'
    exit 0
fi
before=$(snapshot)
runStatus 0
jq -e '. == {enabled:false,server:null,port:null,tcp:"direct",udp:"direct",mode:"direct",domain_rules:[]}' "${LOG}" >/dev/null ||
    fail '关闭路由诊断合同错误'
runStatus 2 unexpected
runEdit 0 --socks5 "${INPUT}" --preview
runEdit 0 --socks5 "${DOMAINS_INPUT}" --preview
runEdit 15 --socks5-domains 'example.net' --preview
runEdit 15 --socks5-global --preview
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
jq -e '. == {enabled:true,server:"203.0.113.9",port:1080,tcp:"socks5",udp:"blocked",mode:"global",domain_rules:[]}' \
    "${LOG}" >/dev/null || fail '开启路由诊断合同错误'
runEdit 0 --socks5 "${DOMAINS_INPUT}" --preview
[[ "$(snapshot)" == "${before}" ]] || fail '选择性启用预览改变在线部署'
runEdit 0 --socks5 "${DOMAINS_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/domains.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail '私有文件选择性启用没有保留域名规则或其它规格'
runStatus 0
jq -e --argjson domains "${DOMAINS}" '
  . == {enabled:true,server:"203.0.113.9",port:1080,tcp:"matched-socks5",
        udp:"matched-blocked",mode:"domains",domain_rules:$domains}
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
        udp:"matched-blocked",mode:"domains",domain_rules:$domains}
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
jq -e '. == {enabled:true,server:"203.0.113.9",port:1080,tcp:"socks5",udp:"blocked",mode:"global",domain_rules:[]}' \
    "${LOG}" >/dev/null || fail '切换全局后状态合同错误'
runEdit 0 --socks5-domains 'example.net' --confirm PADM-DOCKER-EDIT
runEdit 0 --socks5-off --confirm PADM-DOCKER-EDIT
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

# 路由子项共用私有文件与候选事务，每次编辑只替换自己的字段。
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

runEdit 0 --dns "${DNS_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/base.json" --slurpfile new "${root}/config/spec.json" \
    --argjson dns "${DNS}" '$new[0] == ($old[0] + {routing:{dns:$dns}})' >/dev/null ||
    fail 'DNS 独立开启改变其它规格'
runStatus 0
jq -e --argjson dns "${DNS}" '
  . == {enabled:true,server:null,port:null,tcp:"direct",udp:"direct",mode:"direct",
        domain_rules:[],dns:{server:$dns.server,port:$dns.port,domain_rules:$dns.domains}}
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
for failure in health-fail int term; do
    MODE=${failure}
    rm -f -- "${TEST_ROOT}/failed-once"
    case "${failure}" in
    health-fail) runEdit 14 --dns-off --confirm PADM-DOCKER-EDIT ;;
    int) runEdit 130 --hosts-off --confirm PADM-DOCKER-EDIT ;;
    term) runEdit 143 --dns-off --confirm PADM-DOCKER-EDIT ;;
    esac
    [[ "$(snapshot)" == "${before}" ]] || fail "${failure}: DNS/hosts 未恢复完整部署和流量"
done
MODE=ok
runEdit 0 --socks5 "${DOMAINS_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/routing-all.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail '开启 SOCKS5 丢弃 DNS/hosts'
runEdit 0 --hosts-off --confirm PADM-DOCKER-EDIT
jq -e --argjson dns "${DNS}" --argjson domains "${DOMAINS}" '
  .routing == {dns:$dns,socks5:{server:"203.0.113.9",port:1080,
    username:"routing-user-secret-marker",password:"routing-password-secret-marker",domains:$domains}}
' "${root}/config/spec.json" >/dev/null || fail '关闭 hosts 破坏 DNS/SOCKS5'
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
jq -e --arg uuid "${UUID}" '.accounts[$uuid].upload == 17 and .accounts[$uuid].download == 19' \
    "${root}/data/traffic/state.json" >/dev/null || fail 'DNS/hosts 事务清空流量'

# Direct/Block 沿用相同事务，同时验证同域规则允许共存并保留其它路由子项。
runEdit 0 --direct "${DIRECT_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/direct-only.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail '独立 Direct 开启改变其它规格'
runStatus 0
jq -e --argjson domains "${DOMAINS}" '.enabled == true and .direct == {domain_rules:$domains} and
  (has("block") | not)' "${LOG}" >/dev/null || fail 'Direct 状态投影错误'
before=$(snapshot)
runEdit 15 --spec "${TEST_ROOT}/base.json" --confirm PADM-DOCKER-EDIT
runEdit 15 --spec "${TEST_ROOT}/block-only.json" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '普通 --spec 绕过 Direct/Block 冻结'
runEdit 0 --block "${BLOCK_INPUT}" --confirm PADM-DOCKER-EDIT
runStatus 0
jq -e --argjson domains "${DOMAINS}" '.direct == {domain_rules:$domains} and
  .block == {domain_rules:$domains}' "${LOG}" >/dev/null || fail 'Direct/Block 同域状态未保留两项'
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
runEdit 0 --block-ips "${BLOCK_IPS_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/routing-ip-policy.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail '开启 IP 阻断改变已有子项'
[[ "$(stat -c '%a %u %h' "${root}/config/spec.json")" == '600 0 1' ]] ||
    fail 'IP 阻断规格未保留私有权限'
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
runEdit 0 --direct-off --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/routing-policy.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual[0] == ($expected[0] | del(.routing.direct))' >/dev/null ||
    fail '关闭 Direct 删除其它路由子项'
runEdit 0 --socks5-off --confirm PADM-DOCKER-EDIT
runEdit 0 --dns-off --confirm PADM-DOCKER-EDIT
runEdit 0 --hosts-off --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/block-only.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail '关闭其它路由子项删除 Block'
runEdit 0 --block-off --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/base.json" --slurpfile new "${root}/config/spec.json" \
    '$new == $old' >/dev/null || fail '关闭最后 Block 没有删除空 routing'
jq -e --arg uuid "${UUID}" '.accounts[$uuid].upload == 17 and .accounts[$uuid].download == 19' \
    "${root}/data/traffic/state.json" >/dev/null || fail 'Direct/Block 事务清空流量'
runEdit 0 --block-ips "${BLOCK_IPS_INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/block-ips-only.json" --slurpfile actual "${root}/config/spec.json" \
    '$actual == $expected' >/dev/null || fail '独立 IP 阻断开启改变其它规格'
runStatus 0
jq -e --argjson input "${BLOCK_IPS}" '.enabled == true and .block_ips.ip_rules == $input.ips' \
    "${LOG}" >/dev/null || fail 'IP 阻断状态没有保留有效列表'
runEdit 0 --block-ips-off --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/base.json" --slurpfile new "${root}/config/spec.json" \
    '$new == $old' >/dev/null || fail '关闭最后 IP 阻断没有删除空 routing'
runStatus 0
jq -e 'has("block_ips") | not' "${LOG}" >/dev/null || fail 'IP 阻断关闭仍显示有效规则'

menuLog="${TEST_ROOT}/routing-menu.log"
(
    dockerMenuRun() { printf '%s\n' "$*" >>"${menuLog}"; }
    dockerMenuRouting < <(printf '6\n0\n8\n0\n0\n')
) >"${LOG}" 2>&1
[[ ! -e "${menuLog}" ]] || fail 'DNS/hosts 菜单路径取消仍调用编辑'
(
    dockerMenuRun() { printf '%s\n' "$*" >>"${menuLog}"; }
    dockerMenuRouting < <(printf '6\n%s\n7\n8\n%s\n9\n0\n' "${DNS_INPUT}" "${HOSTS_INPUT}")
) >"${LOG}" 2>&1
printf 'edit --dns %s\nedit --dns-off\nedit --hosts %s\nedit --hosts-off\n' \
    "${DNS_INPUT}" "${HOSTS_INPUT}" >"${TEST_ROOT}/routing-menu.expected"
cmp -s "${menuLog}" "${TEST_ROOT}/routing-menu.expected" ||
    fail 'DNS/hosts 菜单没有映射到 CLI 事务'
printf 'docker-routing-socks5-regression-ok\n'
