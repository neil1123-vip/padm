#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-port-alias.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-entry-port-alias-regression-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
for tool in bash shellcheck jq python3 stat chmod chown find sort sha256sum; do command -v "${tool}" >/dev/null; done
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_SKIP_CHOWN=0
export PADM_DOCKER_HEALTH_TIMEOUT=1 PADM_DOCKER_LOCK_TIMEOUT=1 PYTHONDONTWRITEBYTECODE=1
root=${PADM_DOCKER_INSTALL_DIR}
UUID=11111111-1111-4111-8111-111111111111
LOG=${TEST_ROOT}/command.log
MODE=ok
fail() {
    [[ ! -f "${LOG}" ]] || sed 's/^/  /' "${LOG}" >&2
    printf 'docker-entry-port-alias-regression-fail: %s\n' "$*" >&2
    exit 1
}
reject() { if "$@" >"${LOG}" 2>&1; then fail "应拒绝: $*"; fi; }
# 只桩化可信发布和服务启动，规格、生成、权限、锁、事务与回滚使用生产实现。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { :; }
dockerLockInstalledDeployment() { dockerAcquireDeploymentLock; }
dockerConfigureReleasePrepare() { :; }
dockerConfigureReleaseValidate() { :; }
dockerRealityTargetsValidate() { :; }
dockerSetupRealityPublicKey() {
    [[ "$(cat)" == dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo ]] || return 1
    printf '%s\n' hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo
}
dockerTrafficRuntimeCheck() { :; }
dockerTrafficBeforeChange() { :; }
dockerTrafficScheduleInstall() { :; }
dockerRenewalScheduleInstall() { :; }
dockerGeoScheduleInstall() { :; }
dockerTlsValidateCandidate() { :; }
dockerIPv6NetworkManage() { :; }
dockerManifestImageReference() {
    jq -er --arg image "$1" '.images[$image]' "${TEST_ROOT}/base.json"
}
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
dockerCandidateCompose() {
    [[ -d "$1" && -e "${root}/locks/deployment.lock" ]] || fail '候选未持有部署锁'
}
docker() {
    [[ "$*" != "ps -aq --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=net-fail2ban --filter label=com.docker.compose.oneoff=False" ]] || return 0
    command docker "$@"
}
dockerComposeRun() {
    [[ -e "${root}/locks/deployment.lock" ]] || fail '发布未持有部署锁'
    if [[ "${1:-}" == up && "${MODE}" == health-fail && ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"
        return 1
    fi
}
mkdir -p "${TEST_ROOT}/bundle/docker/contracts"
printf '%s\n' "$(printf 'a%.0s' {1..40})" >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
cp -- "${PROJECT_ROOT}/docker/contracts/configure.schema.json" "${TEST_ROOT}/bundle/docker/contracts/"
cp -- "${PROJECT_ROOT}/docker/contracts/features.json" "${TEST_ROOT}/bundle/docker/contracts/"
dockerInitializeStateRoot
jq -n --arg uuid "${UUID}" '
  def entry($core; $port): {
    id:1,core:$core,listener_id:("entry-"+$core),server:"proxy.example.com",
    public_port:$port,address_families:["ipv4","ipv6"],name:$core,uuid:$uuid,
    reality:{server_name:"www.debian.org",target_host:"www.debian.org",target_port:443,
      private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
      public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",short_id:"1234"}};
  {schema_version:3,release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"fixture"},
   core:{type:"xray",secondary_type:"sing-box",protocols:[entry("xray";35441),entry("sing-box";35442)]},
   tls:null,subscription:{enabled:false,token:"0123456789abcdef"},
   images:(["xray","sing-box","nginx","ops","net"] | map({key:.,value:
     ("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries),
   host_integrations:[]}
' >"${TEST_ROOT}/base.json"
jq '.port_aliases=[{listener_id:"entry-xray",public_port:36661}]' \
    "${TEST_ROOT}/base.json" >"${TEST_ROOT}/alias.json"

# Schema 保证字段边界；目标存在与发布资源冲突由生产 jq 校验。
python3 - "${PROJECT_ROOT}" "${TEST_ROOT}" <<'PY'
import copy
import json
import sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker

project, root = map(Path, sys.argv[1:])
base = json.loads((root / "base.json").read_text())
alias = json.loads((root / "alias.json").read_text())
schema = json.loads((project / "docker/contracts/configure.schema.json").read_text())
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema, format_checker=FormatChecker())
cases = []

def case(name, value, valid, schema_valid=None):
    assert validator.is_valid(value) == (valid if schema_valid is None else schema_valid), (
        name, [(list(error.path), error.message) for error in validator.iter_errors(value)])
    (root / f"{name}.json").write_text(json.dumps(value), encoding="utf-8")
    cases.append((name, int(valid)))

case("base", base, True)
case("alias", alias, True)
selected = copy.deepcopy(alias)
selected["port_aliases"][0]["share_default"] = True
case("selected", selected, True)
for index, bad in enumerate((False, None, 1, "true", [], {})):
    value = copy.deepcopy(selected)
    value["port_aliases"][0]["share_default"] = bad
    case(f"invalid-default-{index}", value, False)
value = copy.deepcopy(selected)
value["port_aliases"].append(
    {"listener_id": "entry-xray", "public_port": 36662, "share_default": True})
case("duplicate-default", value, False, True)
value = copy.deepcopy(selected)
value["port_aliases"].append(
    {"listener_id": "entry-sing-box", "public_port": 36662, "share_default": True})
case("independent-defaults", value, True)
value = copy.deepcopy(alias)
value["port_aliases"] = [
    {"listener_id": "entry-xray", "public_port": 37000 + n} for n in range(16)]
case("sixteen-aliases", value, True)
legacy = copy.deepcopy(base)
legacy["schema_version"] = 1
legacy["core"]["protocols"] = legacy["core"]["protocols"][:1]
del legacy["core"]["secondary_type"]
del legacy["core"]["protocols"][0]["core"]
del legacy["core"]["protocols"][0]["listener_id"]
case("legacy", legacy, True)
for index, bad in enumerate((None, {}, [], True, "36661", [36661],
                            [{"listener_id": "entry-xray"}],
                            [{"listener_id": "entry-xray", "public_port": 36661, "extra": True}],
                            alias["port_aliases"] * 2,
                            [{"listener_id": "entry-xray", "public_port": 37000 + n} for n in range(17)])):
    value = copy.deepcopy(alias)
    value["port_aliases"] = bad
    case(f"invalid-array-{index}", value, False)
for index, bad in enumerate((0, 65536, 1.5, "36661", True, None)):
    value = copy.deepcopy(alias)
    value["port_aliases"][0]["public_port"] = bad
    case(f"invalid-port-{index}", value, False)
for index, bad in enumerate(("", "relay-http", "alias-36661-tcp", "entry-no-such")):
    value = copy.deepcopy(alias)
    value["port_aliases"][0]["listener_id"] = bad
    case(f"invalid-target-{index}", value, False, bad == "entry-no-such")
value = copy.deepcopy(alias)
value["port_aliases"][0]["public_port"] = 35441
case("same-base-port", value, False, True)
value = copy.deepcopy(alias)
value["port_aliases"].append({"listener_id": "entry-sing-box", "public_port": 36661})
case("same-transport-port", value, False, True)
value = copy.deepcopy(alias)
value["core"]["protocols"] = value["core"]["protocols"][1:]
value["core"]["type"] = "sing-box"
value["core"]["secondary_type"] = None
case("deleted-target-with-alias", value, False, True)
mixed = copy.deepcopy(base)
mixed["tls"] = {"domain": "tls.example.com"}
mixed["core"]["protocols"][1] = {
    "id": 3, "core": "sing-box", "listener_id": "entry-hy2", "server": "proxy.example.com",
    "public_port": 35442, "address_families": ["ipv4", "ipv6"], "name": "hy2",
    "uuid": base["core"]["protocols"][1]["uuid"],
    "hy2": {"domain": "tls.example.com", "bandwidth_mode": "bbr", "up_mbps": 100,
            "down_mbps": 100, "obfs": None, "masquerade": ""}}
mixed["core"]["protocols"].append({
    "id": 30, "core": "sing-box", "listener_id": "entry-ss", "server": "proxy.example.com",
    "public_port": 35443, "address_families": ["ipv4", "ipv6"], "name": "ss",
    "uuid": base["core"]["protocols"][1]["uuid"],
    "shadowsocks": {"method": "2022-blake3-aes-128-gcm",
                   "server_password": "AAAAAAAAAAAAAAAAAAAAAA==", "user_password": "BBBBBBBBBBBBBBBBBBBBBA=="}})
mixed["port_aliases"] = [{"listener_id": "entry-xray", "public_port": 36661},
                         {"listener_id": "entry-hy2", "public_port": 36661},
                         {"listener_id": "entry-ss", "public_port": 36662}]
case("mixed", mixed, True)
value = copy.deepcopy(mixed)
value["port_aliases"] = [{"listener_id": "entry-xray", "public_port": 35442},
                         {"listener_id": "entry-hy2", "public_port": 35441}]
case("different-transport-base-port", value, True)
value = copy.deepcopy(mixed)
value["port_aliases"].append({"listener_id": "entry-hy2", "public_port": 36662})
case("conflict-dual-transport", value, False, True)
value = copy.deepcopy(alias)
value["port_aliases"][0]["public_port"] = 10085
case("private-container-port", value, True)
for version in (1, 2):
    value = copy.deepcopy(alias)
    value["schema_version"] = version
    case(f"invalid-version-{version}", value, False)
tls = copy.deepcopy(base)
tls["tls"] = {"domain": "tls.example.com"}
tls["core"]["protocols"][1] = {
    "id": 21, "core": "xray", "listener_id": "entry-tls", "server": "proxy.example.com",
    "public_port": 35442, "address_families": ["ipv4", "ipv6"], "name": "tls",
    "uuid": base["core"]["protocols"][1]["uuid"],
    "websocket": {"domain": "tls.example.com", "path": "fixture01", "backend_port": 31297, "tls_port": 8443}}
tls["core"]["secondary_type"] = None
tls["port_aliases"] = [{"listener_id": "entry-tls", "public_port": 36663}]
case("tls", tls, True)
value = copy.deepcopy(tls)
value["port_aliases"][0]["public_port"] = 31297
case("private-backend-port", value, True)
stream = copy.deepcopy(tls)
stream["reality_stream"] = {"listener_id": "entry-xray", "website_listener_id": "entry-tls"}
stream["port_aliases"] = [{"listener_id": "entry-xray", "public_port": 36664},
                          {"listener_id": "entry-tls", "public_port": 36665}]
case("stream", stream, True)
value = copy.deepcopy(stream)
value["port_aliases"][0]["share_default"] = True
case("stream-reality-default", value, True)
value["port_aliases"][1]["share_default"] = True
case("stream-both-defaults", value, True)
del value["port_aliases"][0]["share_default"]
case("stream-website-default", value, True)
value = copy.deepcopy(stream)
value["port_aliases"][0]["public_port"] = 443
case("stream-port-conflict", value, False, True)
value = copy.deepcopy(stream)
value["reality_stream"] = {"listener_id": "entry-xray", "host_website": {
    "domains": ["host.example.com"], "address": "127.0.0.1", "port": 8443, "network_mode": "host"}}
case("unsupported-host-stream", value, False)
value = copy.deepcopy(tls)
value["host_integrations"] = [{"type": "fail2ban", "profile": "net-fail2ban",
    "firewall_rules": ["DOCKER-USER"], "devices": [], "schedules": [],
    "settings": {"log_file": "access.log", "ports": [35442], "max_retry": 6,
                 "find_time": 600, "ban_time": 3600}}]
case("unsupported-fail2ban", value, False)
single = copy.deepcopy(alias)
single["core"]["secondary_type"] = None
single["core"]["protocols"] = single["core"]["protocols"][:1]
value = copy.deepcopy(single)
value["host_integrations"] = [{"type": "tproxy", "profile": "net-transparent",
    "firewall_rules": ["padm-tproxy"], "devices": [], "schedules": [],
    "settings": {"port": 31298, "mark": 129}}]
case("unsupported-tproxy", value, False)
value = copy.deepcopy(single)
value["core"]["type"] = value["core"]["protocols"][0]["core"] = "sing-box"
value["host_integrations"] = [{"type": "tun", "profile": "net-transparent",
    "firewall_rules": ["sing-box-auto-redirect"], "devices": ["/dev/net/tun"], "schedules": [],
    "settings": {"interface": "padm-tun", "address": "198.18.0.1/30"}}]
case("unsupported-tun", value, False)
value = copy.deepcopy(single)
value["host_integrations"] = [{"type": "wireguard", "profile": "net-wireguard",
    "firewall_rules": [], "devices": ["wg-padm"], "schedules": [],
    "settings": {"config_file": "wg-padm.conf", "interface": "wg-padm"}}]
case("wireguard-bridge-alias", value, True)
full = copy.deepcopy(base)
full["tls"] = {"domain": "tls.example.com"}
full["subscription"]["enabled"] = True
full["core"]["protocols"] = []
ids = [1, 2, 3, 4, 5, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]
for protocol in ids:
    entry = dict(id=protocol, core="sing-box" if protocol in (3, 4, 5, 30, 31) else "xray",
                 listener_id=f"entry-{protocol}", server="2001:db8::1",
                 public_port=30000 + protocol, address_families=["ipv4", "ipv6"],
                 name=f"protocol-{protocol}", uuid=base["core"]["protocols"][0]["uuid"])
    if protocol in (1, 2, 26):
        entry["reality"] = copy.deepcopy(base["core"]["protocols"][0]["reality"])
        if protocol == 2:
            entry["xhttp"] = dict(path="/alias-xhttp", host="www.debian.org", mode="auto")
        elif protocol == 26:
            entry["grpc"] = dict(service_name="alias-grpc")
    elif protocol in (21, 22, 23):
        entry["httpupgrade" if protocol == 23 else "websocket"] = dict(
            domain="tls.example.com", path=f"alias-path{protocol}",
            backend_port=40000 + protocol, tls_port=41000 + protocol)
    elif protocol in (24, 25):
        entry["grpc_tls"] = dict(domain="tls.example.com", service_name=f"alias{protocol}",
                                backend_port=40000 + protocol, tls_port=41000 + protocol)
    elif protocol in (27, 29):
        entry["fallback_tls"] = dict(domain="tls.example.com", http_port=42000 + protocol,
                                    http2_port=43000 + protocol)
    elif protocol == 28:
        entry["trojan"] = dict(domain="tls.example.com")
    elif protocol == 3:
        entry["hy2"] = copy.deepcopy(mixed["core"]["protocols"][1]["hy2"])
    elif protocol == 4:
        entry["anytls"] = dict(domain="tls.example.com")
    elif protocol == 5:
        entry.update(server="tls.example.com", naive=dict(domain="tls.example.com"))
    elif protocol == 30:
        entry["shadowsocks"] = copy.deepcopy(mixed["core"]["protocols"][2]["shadowsocks"])
    else:
        entry["tuic"] = dict(domain="tls.example.com", congestion_control="cubic",
                             auth_timeout="3s", heartbeat="10s", zero_rtt_handshake=False)
    full["core"]["protocols"].append(entry)
full["accounts"] = [
    dict(id="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", name="Alice", enabled=True,
         uuid="44444444-4444-4444-8444-444444444444", password="Alice.-~@+=:Secret",
         shadowsocks_password="AQEBAQEBAQEBAQEBAQEBAQ==",
         listeners=[entry["listener_id"] for entry in full["core"]["protocols"]])]
full["port_aliases"] = [
    dict(listener_id=entry["listener_id"], public_port=50000 + entry["id"])
    for entry in full["core"]["protocols"]]
case("full", full, True)
value = copy.deepcopy(full)
for item in value["port_aliases"]:
    item["share_default"] = True
case("full-defaults", value, True)
(root / "cases.tsv").write_text("".join(f"{name}\t{valid}\n" for name, valid in cases))
PY
while IFS=$'\t' read -r name valid; do
    actual=0
    dockerConfigureSpecValidate "${TEST_ROOT}/${name}.json" >"${LOG}" 2>&1 || actual=$?
    if [[ "${valid}" == 1 ]]; then
        [[ "${actual}" == 0 ]] || fail "生产校验拒绝正例: ${name}"
    else
        [[ "${actual}" != 0 ]] || fail "生产校验接受负例: ${name}"
    fi
done <"${TEST_ROOT}/cases.tsv"

dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/alias.json" || fail '当前 bundle 拒绝 alias'
jq 'del(."x-padm-port-aliases")' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/alias.json"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/base.json" || fail '旧包拒绝无 alias 规格'
cp -- "${PROJECT_ROOT}/docker/contracts/configure.schema.json" "${TEST_ROOT}/bundle/docker/contracts/"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/selected.json" || fail '当前 bundle 拒绝默认分享端口'
jq 'del(."x-padm-port-alias-default")' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/selected.json"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/alias.json" || fail '旧包拒绝未选默认的 alias'
cp -- "${PROJECT_ROOT}/docker/contracts/configure.schema.json" "${TEST_ROOT}/bundle/docker/contracts/"

assertShare() {
    python3 - "$1" "$2" "${3:-}" <<'PY'
import base64
import json
import sys
import urllib.parse
from pathlib import Path

spec = json.loads(Path(sys.argv[1]).read_text())
def decode(path):
    result = {}
    for line in Path(path).read_text().splitlines():
        if line.startswith("vmess://"):
            value = json.loads(base64.b64decode(line.removeprefix("vmess://")))
            name, port = value["ps"], int(value.pop("port"))
            identity, password, host = value["id"], None, value["add"]
        else:
            link = urllib.parse.urlsplit(line)
            name, port = urllib.parse.unquote(link.fragment), link.port
            identity = urllib.parse.unquote(link.username or "")
            password = urllib.parse.unquote(link.password) if link.password is not None else None
            host = link.hostname
            value = dict(scheme=link.scheme, identity=identity, password=password, host=host,
                         query=urllib.parse.parse_qs(link.query, keep_blank_values=True))
        assert name not in result, name
        result[name] = dict(port=port, identity=identity, password=password, host=host, value=value)
    return result

links = decode(sys.argv[2])
expected = set()
for entry in spec["core"]["protocols"]:
    accounts = ([None] if spec["subscription"].get("include_base") is not False else []) + [
        account for account in spec.get("accounts", [])
        if account["enabled"] and entry["listener_id"] in account["listeners"]]
    for account in accounts:
        name = entry["name"] + ("-" + account["name"] if account else "")
        expected.add(name)
        link = links[name]
        port = entry["public_port"]
        stream = spec.get("reality_stream", {})
        if entry["listener_id"] in (stream.get("listener_id"), stream.get("website_listener_id")):
            port = 443
        port = next((alias["public_port"] for alias in spec.get("port_aliases", [])
                     if alias["listener_id"] == entry["listener_id"] and alias.get("share_default")), port)
        assert link["port"] == port and link["host"] == entry["server"], (name, link["port"], port)
        uuid = account["uuid"] if account else entry["uuid"]
        password = account["password"] if account else entry["uuid"]
        protocol = entry["id"]
        identity = password if protocol in (3, 4, 25, 28, 29) else uuid
        if protocol == 5:
            identity = account["id"] if account else uuid
            assert link["password"] == password, name
        elif protocol == 30:
            identity = entry["shadowsocks"]["method"]
            user = account["shadowsocks_password"] if account else entry["shadowsocks"]["user_password"]
            assert link["password"] == entry["shadowsocks"]["server_password"] + ":" + user, name
        elif protocol == 31:
            assert link["password"] == password, name
        assert link["identity"] == identity, name
assert set(links) == expected, (set(links), expected)
if sys.argv[3]:
    before = decode(sys.argv[3])
    assert {name: link["value"] for name, link in links.items()} == {
        name: link["value"] for name, link in before.items()}, "端口以外的 URI 字段发生变化"
PY
}

# 所有协议复用同一分享端口覆盖；逐项核对账号身份、IPv6 和协议参数不变。
for fixture in full full-defaults; do
    spec="${TEST_ROOT}/${fixture}.json"
    dockerGenerateSubscription "${spec}" "${TEST_ROOT}/${fixture}.links"
    assertShare "${spec}" "${TEST_ROOT}/${fixture}.links"
    dockerGenerateCompose "${spec}" "${TEST_ROOT}/${fixture}.compose"
    dockerGenerateDeployment "${spec}" "${TEST_ROOT}/${fixture}.deployment"
    for core in xray sing-box; do
        if [[ "${core}" == xray ]]; then
            dockerGenerateXrayConfig "${spec}" "${TEST_ROOT}/${fixture}.${core}.base"
        else
            dockerGenerateSingBoxConfig "${spec}" "${TEST_ROOT}/${fixture}.${core}.base"
        fi
        dockerTrafficRender "${core}" "${TEST_ROOT}/${fixture}.${core}.base" \
            '{"schema_version":1,"accounts":{}}' >"${TEST_ROOT}/${fixture}.${core}.runtime"
    done
done
assertShare "${TEST_ROOT}/full-defaults.json" "${TEST_ROOT}/full-defaults.links" "${TEST_ROOT}/full.links"
for artifact in compose deployment xray.base sing-box.base xray.runtime sing-box.runtime; do
    cmp "${TEST_ROOT}/full.${artifact}" "${TEST_ROOT}/full-defaults.${artifact}" ||
        fail "默认选择改变非分享配置: ${artifact}"
done
jq -e --slurpfile features "${PROJECT_ROOT}/docker/contracts/features.json" '
  [.core.protocols[].id] | sort ==
    ([$features[0].protocols[] | select(.status=="supported") | .id] | sort)
' "${TEST_ROOT}/full.json" >/dev/null || fail '默认分享测试缺少支持的协议'
group='{"id":"share-aaaaaaaaaaaaaaaa","name":"alias-fixture","enabled":true,
  "token":"alias-group-token","account_ids":["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"],
  "listener_ids":["entry-1","entry-22","entry-30"]}'
for fixture in full full-defaults; do
    dockerSubscriptionRender "${TEST_ROOT}/${fixture}.json" "${group}" "${TEST_ROOT}/${fixture}.group"
    jq --argjson group "${group}" '.subscription.include_base=false |
      .core.protocols |= map(select(.listener_id as $id | ($group.listener_ids | index($id)) != null))' \
        "${TEST_ROOT}/${fixture}.json" >"${TEST_ROOT}/${fixture}.group.json"
    assertShare "${TEST_ROOT}/${fixture}.group.json" "${TEST_ROOT}/${fixture}.group"
done
assertShare "${TEST_ROOT}/full-defaults.group.json" "${TEST_ROOT}/full-defaults.group" "${TEST_ROOT}/full.group"
for fixture in stream stream-reality-default stream-both-defaults stream-website-default; do
    jq '.subscription.enabled=true' "${TEST_ROOT}/${fixture}.json" >"${TEST_ROOT}/${fixture}.links.json"
    dockerGenerateSubscription "${TEST_ROOT}/${fixture}.links.json" "${TEST_ROOT}/${fixture}.links"
    assertShare "${TEST_ROOT}/${fixture}.links.json" "${TEST_ROOT}/${fixture}.links"
done
for fixture in stream-reality-default stream-both-defaults stream-website-default; do
    assertShare "${TEST_ROOT}/${fixture}.links.json" "${TEST_ROOT}/${fixture}.links" "${TEST_ROOT}/stream.links"
done

for fixture in legacy mixed tls stream; do
    spec="${TEST_ROOT}/${fixture}.json"
    dockerGenerateCompose "${spec}" "${TEST_ROOT}/${fixture}.compose"
    dockerGenerateDeployment "${spec}" "${TEST_ROOT}/${fixture}.deployment"
    dockerDeploymentFileValidate "${TEST_ROOT}/${fixture}.deployment"
    dockerGenerateImagesEnv "${spec}" "${TEST_ROOT}/${fixture}.env" "${root}"
    dockerManagedSpecMatchesDeployment "${spec}" "${TEST_ROOT}/${fixture}.deployment" "${TEST_ROOT}/${fixture}.env"
done
# 部署 Schema 与 jq 都需认识别名资源，防止目标字段校验只存在于一份合同。
python3 - "${PROJECT_ROOT}" "${TEST_ROOT}" <<'PY'
import copy
import json
import sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker

project, root = map(Path, sys.argv[1:])
schema = json.loads((project / "docker/contracts/deployment.schema.json").read_text())
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema, format_checker=FormatChecker())
for name in ("legacy", "mixed", "tls", "stream"):
    validator.validate(json.loads((root / f"{name}.deployment").read_text()))
mixed = json.loads((root / "mixed.deployment").read_text())
missing_target = copy.deepcopy(mixed)
del next(item for item in missing_target["listeners"]
         if item["listener_id"].startswith("alias-"))["target_listener_id"]
base_target = copy.deepcopy(mixed)
next(item for item in base_target["listeners"]
     if not item["listener_id"].startswith("alias-"))["target_listener_id"] = "entry-xray"
for name, value in (("missing-alias-target", missing_target), ("unexpected-base-target", base_target)):
    assert not validator.is_valid(value), name
    (root / f"{name}.deployment").write_text(json.dumps(value), encoding="utf-8")
PY
reject dockerDeploymentFileValidate "${TEST_ROOT}/missing-alias-target.deployment"
reject dockerDeploymentFileValidate "${TEST_ROOT}/unexpected-base-target.deployment"
jq -e '
  (.services.xray.ports | index("0.0.0.0:36661:35441/tcp")) != null and
  (.services["sing-box"].ports | index("0.0.0.0:36661:35442/udp")) != null and
  (.services["sing-box"].ports | index("[::]:36662:35443/tcp")) != null and
  (.services["sing-box"].ports | index("[::]:36662:35443/udp")) != null
' "${TEST_ROOT}/mixed.compose" >/dev/null || fail 'TCP/UDP 同数字或双 transport 别名映射错误'
jq -e '(.services.nginx.ports | index("0.0.0.0:36663:8443/tcp")) != null' \
    "${TEST_ROOT}/tls.compose" >/dev/null || fail 'TLS alias 未映射 Nginx TLS 前端'
jq -e '
  (.services.nginx.ports | index("0.0.0.0:36664:15443/tcp")) != null and
  (.services.nginx.ports | index("0.0.0.0:36665:15443/tcp")) != null
' "${TEST_ROOT}/stream.compose" >/dev/null || fail 'stream alias 未继承完整 SNI 前端'
jq -e '[.listeners[] | select(.listener_id | startswith("alias-"))] | sort_by(.listener_id) |
  length == 4 and .[0].listener_id == "alias-36661-tcp" and .[0].target_listener_id == "entry-xray" and
  .[1].listener_id == "alias-36661-udp" and .[1].target_listener_id == "entry-hy2" and
  .[2].target_listener_id == "entry-ss" and .[3].target_listener_id == "entry-ss"' \
    "${TEST_ROOT}/mixed.deployment" >/dev/null
for change in \
    '(.listeners[] | select(.listener_id=="alias-36661-tcp")).target_listener_id="entry-ss"' \
    '(.listeners[] | select(.listener_id=="alias-36661-tcp")).container_port=1' \
    '.listeners |= map(select(.listener_id!="alias-36661-tcp"))'; do
    jq "${change}" "${TEST_ROOT}/mixed.deployment" >"${TEST_ROOT}/bad.deployment"
    reject dockerManagedSpecMatchesDeployment "${TEST_ROOT}/mixed.json" "${TEST_ROOT}/bad.deployment" "${TEST_ROOT}/mixed.env"
done
(
    dockerCurrentOwnsPort() { return 1; }
    dockerTcpPortIsListening() { [[ "$1" == 36661 ]]; }
    dockerUdpPortIsListening() { return 1; }
    docker() { :; }
    reject dockerConfigurePortsAvailable "${TEST_ROOT}/mixed.json"
    dockerTcpPortIsListening() { return 1; }
    dockerConfigurePortsAvailable "${TEST_ROOT}/mixed.json"
    dockerUdpPortIsListening() { [[ "$1" == 36661 ]]; }
    reject dockerConfigurePortsAvailable "${TEST_ROOT}/mixed.json"
)
dockerConfigurePortsAvailable() { :; }

snapshot() (
    cd "${root}"
    find config data secrets -type f -printf '%p %m %U %G %n\n' | LC_ALL=C sort
    find config data secrets -type f -print0 | sort -z | xargs -0 -r sha256sum
    for path in compose.json deployment.json deployment.previous.json images.env; do
        [[ ! -f "${path}" ]] || sha256sum "${path}"
    done
)
assertClean() {
    [[ ! -e "${root}/locks/deployment.lock" ]] || fail '事务遗留部署锁'
    [[ -z "$(find "${root}" -maxdepth 1 \( -name '.candidate.*' -o -name '.edit.*' -o -name '.protocol.*' \) -print -quit)" ]] ||
        fail '事务遗留候选'
}
captureEditOutputs() {
    jq -cS . "${root}/config/spec.json" >"${TEST_ROOT}/edit-spec.before"
    sha256sum "${root}/config/xray/"{config.json,users.base} \
        "${root}/config/sing-box/"{config.json,users.base} \
        "${root}/data/subscription/"* "${root}/data/traffic/state.json" >"${TEST_ROOT}/edit-outputs.before"
}
assertEditOutputs() {
    jq -cS . "${root}/config/spec.json" >"${TEST_ROOT}/edit-spec.after"
    cmp "${TEST_ROOT}/edit-spec.before" "${TEST_ROOT}/edit-spec.after" ||
        fail '重复确认改变规格语义'
    sha256sum "${root}/config/xray/"{config.json,users.base} \
        "${root}/config/sing-box/"{config.json,users.base} \
        "${root}/data/subscription/"* "${root}/data/traffic/state.json" >"${TEST_ROOT}/edit-outputs.after"
    cmp "${TEST_ROOT}/edit-outputs.before" "${TEST_ROOT}/edit-outputs.after" ||
        fail '重复确认改变账号、订阅或流量内容'
}
runEdit() {
    local expected=$1 actual=0
    shift
    (dockerMain edit "$@") >"${LOG}" 2>&1 || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "edit $*: 预期 ${expected}，实际 ${actual}"
    assertClean
}
jq --slurpfile tls "${TEST_ROOT}/tls.json" --slurpfile full "${TEST_ROOT}/full.json" '
  .tls=$tls[0].tls | .subscription.enabled=true |
  .core.protocols += [$tls[0].core.protocols[1] | .public_port=35445] |
  .accounts=[$full[0].accounts[0] | .listeners=["entry-xray","entry-tls"] | .shadowsocks_password=null]
' "${TEST_ROOT}/base.json" >"${TEST_ROOT}/installed.json"
mkdir -p "${root}/secrets/tls"
printf '%s\n' fixture-certificate >"${root}/secrets/tls/tls.example.com.crt"
printf '%s\n' fixture-private-key >"${root}/secrets/tls/tls.example.com.key"
chmod 0640 "${root}/secrets/tls/"*
transactionGroup='{"id":"share-bbbbbbbbbbbbbbbb","name":"alias-transaction","enabled":true,
  "token":"alias-transaction-token","account_ids":["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"],
  "listener_ids":["entry-sing-box","entry-xray"]}'
dockerSubscriptionStateWrite "${root}/config/share-groups.json" \
    "$(jq -cn --argjson group "${transactionGroup}" '{schema_version:1,groups:[$group]}')"
dockerSubscriptionStateValidate "${root}/config/share-groups.json" >"${LOG}" 2>&1 ||
    fail '分享组夹具不满足生产状态约束'
dockerConfigureSpecValidate "${TEST_ROOT}/installed.json" >"${LOG}" 2>&1 ||
    fail '合成 installed 夹具不满足生产规格约束'
assertInstalledShare() {
    assertShare "${root}/config/spec.json" "${root}/data/subscription/0123456789abcdef"
    jq --argjson group "${transactionGroup}" '.subscription.include_base=false |
      .core.protocols |= map(select(.listener_id as $id | ($group.listener_ids | index($id)) != null)) |
      .accounts |= map(select(.id as $id | ($group.account_ids | index($id)) != null))
    ' "${root}/config/spec.json" >"${TEST_ROOT}/installed.group.json"
    assertShare "${TEST_ROOT}/installed.group.json" "${root}/data/subscription/alias-transaction-token"
}
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/installed.json" '' '' configure
) >"${LOG}" 2>&1 || fail '初始化 alias 夹具失败'
assertClean
assertInstalledShare
jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{($uuid):{
  name:"business",upload:17,download:19,limit_bytes:0,baseline:{}}}}' | dockerTrafficWriteState
groupToken="${root}/data/subscription/alias-transaction-token"
cp -- "${groupToken}" "${TEST_ROOT}/group-token.before"
before=$(snapshot)
printf '%s\n' fixture-manual-change >"${groupToken}"
tampered=$(snapshot)
actual=0
(dockerMain protocol links) >"${LOG}" 2>&1 || actual=$?
[[ "${actual}" == 15 ]] || fail '手改 group token 后分享链接未拒绝'
runEdit 15 --port-alias-default entry-xray base --preview
[[ "$(snapshot)" == "${tampered}" ]] || fail '拒绝手改 group token 时改变在线部署'
cp -- "${TEST_ROOT}/group-token.before" "${groupToken}"
[[ "$(snapshot)" == "${before}" ]] || fail '恢复 group token 后快照不一致'
assertInstalledShare
(dockerMain protocol links) >"${TEST_ROOT}/links.before"
(dockerMain protocol port-alias-status) >"${LOG}"
jq -e '.=={enabled:false,aliases:[]}' "${LOG}" >/dev/null
before=$(snapshot)
runEdit 0 --port-alias entry-xray 36661 --preview
runEdit 2 --port-alias entry-xray
runEdit 2 --port-alias entry-xray 0 --preview
runEdit 2 --port-alias entry-xray 65536 --preview
runEdit 2 --port-alias entry-xray 36661 --port-alias-remove entry-xray 36661 --preview
runEdit 2 --port-alias entry-xray 36661 --socks5-off --preview
runEdit 2 --port-alias entry-xray 36661 --http-relay-off --preview
runEdit 2 --port-alias-default entry-xray
runEdit 2 --port-alias-default entry-xray 0 --preview
runEdit 2 --port-alias-default entry-xray 65536 --preview
runEdit 2 --port-alias-default entry-xray false --preview
runEdit 2 --port-alias-default entry-xray 36661 --port-alias-default entry-sing-box base --preview
runEdit 2 --port-alias-default entry-xray 36661 --port-alias entry-xray 36662 --preview
runEdit 2 --port-alias-default entry-xray 36661 --port-alias-remove entry-xray 36661 --preview
runEdit 2 --port-alias-default entry-xray 36661 --block-bt --preview
runEdit 2 --port-alias-default entry-xray 36661 --spec "${TEST_ROOT}/alias.json" --preview
runEdit 15 --port-alias-default entry-no-such base --preview
runEdit 15 --port-alias-default entry-xray 36661 --preview
runEdit 0 --port-alias-default entry-xray base --preview
runEdit 15 --port-alias entry-no-such 36661 --preview
runEdit 15 --port-alias entry-xray 35441 --preview
runEdit 15 --port-alias-remove entry-xray 36661 --preview
runEdit 15 --spec "${TEST_ROOT}/alias.json" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '预览或非法输入改变在线部署'
runEdit 0 --port-alias entry-xray 36661 --confirm PADM-DOCKER-EDIT
(dockerMain protocol port-alias-status) >"${LOG}"
jq -e '.=={enabled:true,aliases:[{listener_id:"entry-xray",core:"xray",public_port:36661,
  share_default:false,transport:["tcp"],address_families:["ipv4","ipv6"]}]}' "${LOG}" >/dev/null
assertClean
(dockerMain protocol links) >"${TEST_ROOT}/links.after"
cmp "${TEST_ROOT}/links.before" "${TEST_ROOT}/links.after" || fail 'alias 修改分享 URI 或业务身份'
dockerCurrentOwnsPort 36661 tcp || fail '部署记录未识别已有 alias 端口'
if dockerCurrentOwnsPort 36661 udp; then fail 'TCP alias 误占 UDP 端口'; fi
jq '.core.protocols[0].public_port=35444' "${root}/config/spec.json" >"${TEST_ROOT}/retarget.json"
runEdit 0 --spec "${TEST_ROOT}/retarget.json" --confirm PADM-DOCKER-EDIT
jq -e '(.services.xray.ports | index("0.0.0.0:36661:35444/tcp")) != null' \
    "${root}/compose.json" >/dev/null || fail 'base 端口变更后 alias 未跟随容器入口'
jq -e 'any(.listeners[]; .listener_id=="alias-36661-tcp" and .container_port==35444)' \
    "${root}/deployment.json" >/dev/null || fail 'base 端口变更后 alias 部署记录未跟随'
before=$(snapshot)
captureEditOutputs
runEdit 0 --port-alias entry-xray 36661 --confirm PADM-DOCKER-EDIT
assertEditOutputs
before=$(snapshot)
runEdit 0 --port-alias-default entry-xray 36661 --preview
runEdit 15 --port-alias-default entry-xray 36662 --preview
runEdit 15 --port-alias-default entry-sing-box 36661 --preview
jq '.port_aliases[0].share_default=true' "${root}/config/spec.json" >"${TEST_ROOT}/frozen-default.json"
runEdit 15 --spec "${TEST_ROOT}/frozen-default.json" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '默认预览或非法选择改变在线部署'
MODE=health-fail
runEdit 14 --port-alias-default entry-xray 36661 --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '默认选择失败未恢复主订阅、分享组 token 和业务文件'
MODE=ok
runEdit 0 --port-alias-default entry-xray 36661 --confirm PADM-DOCKER-EDIT
assertInstalledShare
(dockerMain protocol port-alias-status) >"${LOG}"
jq -e '.aliases | length==1 and .[0].share_default==true' "${LOG}" >/dev/null
(dockerMain protocol links) >"${TEST_ROOT}/links.selected"
assertShare "${root}/config/spec.json" "${TEST_ROOT}/links.selected" "${root}/data/subscription/0123456789abcdef"
captureEditOutputs
runEdit 0 --port-alias-default entry-xray 36661 --confirm PADM-DOCKER-EDIT
assertEditOutputs
before=$(snapshot)
jq '.port_aliases[0] |= del(.share_default)' "${root}/config/spec.json" >"${TEST_ROOT}/frozen-clear.json"
runEdit 15 --spec "${TEST_ROOT}/frozen-clear.json" --confirm PADM-DOCKER-EDIT
runEdit 0 --port-alias-default entry-xray base --preview
[[ "$(snapshot)" == "${before}" ]] || fail '清默认预览或普通规格修改影响在线部署'
runEdit 0 --port-alias-default entry-xray base --confirm PADM-DOCKER-EDIT
assertInstalledShare
jq -e 'all(.port_aliases[]; has("share_default")|not)' "${root}/config/spec.json" >/dev/null
runEdit 0 --port-alias-default entry-xray 36661 --confirm PADM-DOCKER-EDIT
runEdit 15 --spec "${TEST_ROOT}/base.json" --confirm PADM-DOCKER-EDIT
MODE=health-fail
rm -f -- "${TEST_ROOT}/failed-once"
before=$(snapshot)
runEdit 14 --port-alias-remove entry-xray 36661 --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '失败事务未恢复 alias、业务规格与流量'
MODE=ok
runEdit 0 --port-alias-remove entry-xray 36661 --confirm PADM-DOCKER-EDIT
jq -e 'has("port_aliases")|not' "${root}/config/spec.json" >/dev/null || fail '最后一个 alias 删除后保留空数组'
assertInstalledShare
runEdit 0 --port-alias entry-sing-box 36662 --confirm PADM-DOCKER-EDIT
runEdit 0 --port-alias-default entry-sing-box 36662 --confirm PADM-DOCKER-EDIT
jq '.core.protocols += [(.core.protocols[1] | .listener_id="entry-copy" | .public_port=35443 | .name="copy")]' \
    "${root}/config/spec.json" >"${TEST_ROOT}/copy.json"
runEdit 0 --spec "${TEST_ROOT}/copy.json" --confirm PADM-DOCKER-EDIT
jq -e 'all(.port_aliases[]; .listener_id!="entry-copy")' "${root}/config/spec.json" >/dev/null
assertInstalledShare
jq '.core.protocols |= map(select(.listener_id!="entry-sing-box")) |
  .port_aliases |= map(select(.listener_id!="entry-sing-box")) | del(.port_aliases)' \
    "${root}/config/spec.json" >"${TEST_ROOT}/delete.json"
runEdit 0 --spec "${TEST_ROOT}/delete.json" --confirm PADM-DOCKER-EDIT
jq -e 'has("port_aliases")|not' "${root}/config/spec.json" >/dev/null
assertInstalledShare
jq -e --arg uuid "${UUID}" '.accounts[$uuid].upload==17 and .accounts[$uuid].download==19' \
    "${root}/data/traffic/state.json" >/dev/null || fail 'alias 事务清空业务流量'
assertClean
for file in docker/lib/{bundle,lifecycle,menu,services,setup}.sh \
    docker/tests/{entry-port-alias,entry-port-alias-real,menu}.sh; do
    bash -n "${PROJECT_ROOT}/${file}"
    shellcheck --severity=error "${PROJECT_ROOT}/${file}"
done
python3 - "${PROJECT_ROOT}/docker/tests/entry-port-alias-real.py" <<'PY'
import ast
import sys
from pathlib import Path

for filename in sys.argv[1:]:
    ast.parse(Path(filename).read_text(encoding="utf-8"), filename=filename)
PY
printf 'docker-entry-port-alias-regression-ok\n'
