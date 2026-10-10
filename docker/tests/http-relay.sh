#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-http-relay.XXXXXX")
PRIVATE_ROOT=$(mktemp -d /root/.padm-http-relay.XXXXXX)
trap 'rm -rf -- "${TEST_ROOT}" "${PRIVATE_ROOT}"' EXIT
trap 'printf "docker-http-relay-regression-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
for tool in jq python3 stat chmod chown find sort sha256sum; do command -v "${tool}" >/dev/null; done
chmod 0700 "${PRIVATE_ROOT}"
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_SKIP_CHOWN=0
export PADM_DOCKER_HEALTH_TIMEOUT=1 PADM_DOCKER_LOCK_TIMEOUT=1 PYTHONDONTWRITEBYTECODE=1
root=${PADM_DOCKER_INSTALL_DIR}
UUID=11111111-1111-4111-8111-111111111111
USERNAME=http-relay-user-secret-marker
PASSWORD=http-relay-password-secret-marker
INPUT=${PRIVATE_ROOT}/http.json
LOG=${TEST_ROOT}/command.log
MODE=ok
fail() {
    [[ ! -f "${LOG}" ]] || sed 's/^/  /' "${LOG}" >&2
    printf 'docker-http-relay-regression-fail: %s\n' "$*" >&2
    exit 1
}
reject() { if "$@" >"${LOG}" 2>&1; then fail "应拒绝: $*"; fi; }
# 仅发布与宿主检查使用桩，规格、生成、权限、锁、候选和回滚走生产路径。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { :; }
dockerLockInstalledDeployment() { dockerAcquireDeploymentLock; }
dockerConfigureReleasePrepare() { :; }
dockerConfigureReleaseValidate() { :; }
dockerRealityTargetsValidate() { :; }
dockerConfigurePortsAvailable() { :; }
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
    [[ "$*" != "ps -aq --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=net-fail2ban --filter label=com.docker.compose.oneoff=False" &&
        "$*" != "ps -aq --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=net-fail2ban-control --filter label=com.docker.compose.oneoff=False" ]] || return 0
    command docker "$@"
}
dockerComposeRun() {
    [[ -e "${root}/locks/deployment.lock" ]] || fail '发布未持有部署锁'
    if [[ "${1:-}" == up && "${MODE}" == health-fail && ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"
        return 1
    fi
}
dockerComposeExecute() {
    [[ "$*" == down ]] || fail "意外恢复启停参数: $*"
    dockerComposeRun "$@"
}
mkdir -p "${TEST_ROOT}/bundle/docker/contracts"
printf '%s\n' "$(printf 'a%.0s' {1..40})" >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
cp -- "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
cp -- "${PROJECT_ROOT}/docker/contracts/features.json" \
    "${TEST_ROOT}/bundle/docker/contracts/features.json"
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
   host_integrations:[],routing:{socks5:{server:"203.0.113.9",port:1080,
     username:"upstream-user",password:"upstream-password"},block_ips:{ips:["192.0.2.1"]}}}
' >"${TEST_ROOT}/base.json"
jq -n --arg username "${USERNAME}" --arg password "${PASSWORD}" '
  {core:"xray",port:36080,address_families:["ipv4","ipv6"],username:$username,password:$password,
   source_ips:["127.0.0.1/32","::1/128"]}
' >"${INPUT}"
chmod 0600 "${INPUT}"
jq --slurpfile relay "${INPUT}" '.relay={http:$relay[0]}' \
    "${TEST_ROOT}/base.json" >"${TEST_ROOT}/relay.json"

# 两份独立校验器判断同批输入，不让 Schema 与 jq 生产合同悄悄分叉。
python3 - "${PROJECT_ROOT}" "${TEST_ROOT}" <<'PY'
import copy
import json
import sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker

project, root = map(Path, sys.argv[1:])
base = json.loads((root / "base.json").read_text())
relay = json.loads((root / "relay.json").read_text())
schema = json.loads((project / "docker/contracts/configure.schema.json").read_text())
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema, format_checker=FormatChecker())
cases = []

def case(name, value, valid, schema_valid=None):
    assert validator.is_valid(value) == (valid if schema_valid is None else schema_valid), name
    (root / f"{name}.json").write_text(json.dumps(value), encoding="utf-8")
    cases.append((name, int(valid)))

case("base", base, True)
case("valid-xray", relay, True)
for index, sources in enumerate((["192.0.2.1"], ["2001:db8::1"], ["0.0.0.0/0", "::/0"],
                                 ["192.0.2.10/24", "2001:db8::10/64"],
                                 [f"192.0.2.{n}" for n in range(256)])):
    value = copy.deepcopy(relay)
    value["relay"]["http"]["source_ips"] = sources
    case(f"valid-sources-{index}", value, True)
for field, invalid in (
        ("core", ["sing-box", "other", "", None, True]),
        ("port", [0, 65536, 1.5, "36080", True, None]),
        ("address_families", [[], ["ipv4", "ipv4"], ["IPv4"], ["ipv7"], None]),
        ("username", ["", "a" * 256, "a b", "a\nb", "a:b", "\u00e9", None]),
        ("password", ["", "a" * 256, "a b", "a\nb", "\u00e9", None]),
        ("source_ips", [[], ["127.0.0.1"] * 2, ["example.com"], ["01.2.3.4"],
                        ["256.2.3.4"], ["192.0.2.1/33"], ["::1/129"], ["::1%lo"],
                        ["[::1]"], ["::ffff:192.0.2.1"], ["geoip:cn"], [True],
                        [" 192.0.2.1"], [f"192.0.{n // 256}.{n % 256}" for n in range(257)]])):
    for index, bad in enumerate(invalid):
        value = copy.deepcopy(relay)
        value["relay"]["http"][field] = bad
        case(f"invalid-{field}-{index}", value, False)
for field in relay["relay"]["http"]:
    value = copy.deepcopy(relay)
    del value["relay"]["http"][field]
    case(f"missing-{field}", value, False)
for name, bad in (("null", None), ("empty", {}), ("array", []),
                  ("extra", dict(http=relay["relay"]["http"], extra=True))):
    value = copy.deepcopy(relay)
    value["relay"] = bad
    case(f"invalid-relay-{name}", value, False)
for field in ("domains", "family", "udp", "extra"):
    value = copy.deepcopy(relay)
    value["relay"]["http"][field] = True
    case(f"unknown-{field}", value, False)
value = copy.deepcopy(relay)
value["core"]["secondary_type"] = None
value["core"]["type"] = "sing-box"
value["core"]["protocols"] = value["core"]["protocols"][1:]
value["relay"]["http"]["core"] = "xray"
case("unmanaged-core", value, False, True)
for port in (35441, 35442, 10085, 10087):
    value = copy.deepcopy(relay)
    value["relay"]["http"]["port"] = port
    case(f"conflicting-port-{port}", value, False, True)
for version in (1, 2):
    value = copy.deepcopy(relay)
    value["schema_version"] = version
    case(f"invalid-version-{version}", value, False)
(root / "cases.tsv").write_text("".join(f"{name}\t{valid}\n" for name, valid in cases))
PY
while IFS=$'\t' read -r name valid; do
    actual=0
    dockerConfigureSpecValidate "${TEST_ROOT}/${name}.json" >"${LOG}" 2>&1 || actual=$?
    if [[ "${valid}" == 1 ]]; then
        [[ "${actual}" == 0 ]] || fail "生产校验拒绝 Schema 正例: ${name}"
    else
        [[ "${actual}" != 0 ]] || fail "生产校验接受 Schema 负例: ${name}"
    fi
done <"${TEST_ROOT}/cases.tsv"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/relay.json" || fail '当前 bundle 拒绝 HTTP relay'
cp -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json" "${TEST_ROOT}/schema.saved"
for marker in 'del(."x-padm-relay-http")' '."x-padm-relay-http"=false'; do
    jq "${marker}" "${TEST_ROOT}/schema.saved" >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
    reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/relay.json"
    dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/base.json" || fail '旧包拒绝无 relay 规格'
done
cp -- "${TEST_ROOT}/schema.saved" "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"

for core in xray; do
    spec="${TEST_ROOT}/valid-${core}.json"
    dockerGenerateXrayConfig "${spec}" "${TEST_ROOT}/${core}.base"
    jq -e --arg username "${USERNAME}" --arg password "${PASSWORD}" '
      [.inbounds[] | select(.tag=="padm-relay-http")] as $relay |
      $relay|length==1 and .[0].protocol=="http" and .[0].port==36080 and
      .[0].settings.userLevel==1 and .[0].settings.accounts==[{user:$username,pass:$password}]
    ' "${TEST_ROOT}/${core}.base" >/dev/null
    jq -e '
      [.routing.rules[] | select((.inboundTag//[])|index("padm-relay-http"))] as $rules |
      .routing.rules[:2]==$rules and
      ($rules|length==2 and .[0].source==["127.0.0.1/32","::1/128"] and
      .[0].outboundTag=="padm-relay-http-direct" and .[1].outboundTag!="padm-relay-http-direct")
    ' "${TEST_ROOT}/${core}.base" >/dev/null
    dockerTrafficRender "${core}" "${TEST_ROOT}/${core}.base" \
        '{"schema_version":1,"accounts":{}}' >"${TEST_ROOT}/${core}.runtime"
    jq -e '
      .policy.levels["0"].statsUserUplink==true and .policy.levels["0"].statsUserDownlink==true and
      .policy.levels["1"].statsUserUplink==false and .policy.levels["1"].statsUserDownlink==false
    ' "${TEST_ROOT}/${core}.runtime" >/dev/null || fail 'relay 与业务统计等级混淆'
    jq -en --slurpfile base "${TEST_ROOT}/${core}.base" --slurpfile runtime "${TEST_ROOT}/${core}.runtime" '
      [$base[0].inbounds[]|select(.tag=="padm-relay-http")] ==
      [$runtime[0].inbounds[]|select(.tag=="padm-relay-http")]
    ' >/dev/null || fail "${core}: traffic 渲染改变 HTTP relay 认证或加 name"
    jq -e --arg secret "${USERNAME}" '
      all(..|objects; .name? != $secret and .email? != $secret) and
      ((.experimental.v2ray_api.stats.users//[])|index($secret)|not)
    ' "${TEST_ROOT}/${core}.runtime" >/dev/null || fail "${core}: relay 虚报业务流量用户"
    dockerGenerateCompose "${spec}" "${TEST_ROOT}/${core}.compose"
    jq -e --arg core "${core}" '
      [.services[$core].ports[]|select(endswith(":36080:36080/tcp"))]|sort ==
        ["0.0.0.0:36080:36080/tcp","[::]:36080:36080/tcp"]
    ' "${TEST_ROOT}/${core}.compose" >/dev/null
    dockerGenerateDeployment "${spec}" "${TEST_ROOT}/${core}.deployment"
    jq -e --arg core "${core}" '
      [.listeners[]|select(.listener_id=="relay-http")] as $relay |
      $relay|length==1 and .[0].service==$core and .[0].public_port==36080
    ' "${TEST_ROOT}/${core}.deployment" >/dev/null
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
    [[ ! -e "${root}/locks/deployment.lock" ]] || fail '事务遗留部署锁'
    [[ -z "$(find "${root}" -maxdepth 1 \( -name '.candidate.*' -o -name '.edit.*' \) -print -quit)" ]] ||
        fail '事务遗留候选'
}
runEdit() {
    local expected=$1 actual=0
    shift
    (dockerMain edit "$@") >"${LOG}" 2>&1 || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "edit $*: 预期 ${expected}，实际 ${actual}"
    assertClean
    ! grep -Fq "${USERNAME}" "${LOG}" && ! grep -Fq "${PASSWORD}" "${LOG}" || fail '编辑输出泄露 relay 凭据'
}
runStatus() {
    (dockerMain protocol routing-status) >"${LOG}" 2>"${TEST_ROOT}/status.stderr" || fail 'routing-status 失败'
    for output in "${LOG}" "${TEST_ROOT}/status.stderr"; do
        ! grep -Fq "${USERNAME}" "${output}" && ! grep -Fq "${PASSWORD}" "${output}" || fail '诊断泄露 relay 凭据'
    done
    assertClean
}
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/base.json" '' '' configure
) >"${LOG}" 2>&1 || fail '初始化 HTTP relay 夹具失败'
assertClean
jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{($uuid):{
  name:"business",upload:17,download:19,limit_bytes:0,baseline:{}}}}' | dockerTrafficWriteState
before=$(snapshot)
runStatus
jq -e '.http_relay=={enabled:false}' "${LOG}" >/dev/null
runEdit 0 --http-relay "${INPUT}" --preview
runEdit 0 --http-relay-off --preview
for args in missing duplicate mixed; do
    case "${args}" in
    missing) runEdit 2 --http-relay ;;
    duplicate) runEdit 2 --http-relay "${INPUT}" --http-relay-off --preview ;;
    mixed) runEdit 2 --http-relay "${INPUT}" --socks5-off --preview ;;
    esac
done
runEdit 15 --spec "${TEST_ROOT}/relay.json" --confirm PADM-DOCKER-EDIT
cp -- "${INPUT}" "${PRIVATE_ROOT}/bad.json"
chmod 0640 "${PRIVATE_ROOT}/bad.json"
runEdit 15 --http-relay "${PRIVATE_ROOT}/bad.json" --preview
chmod 0600 "${PRIVATE_ROOT}/bad.json"
chown 10001:10001 "${PRIVATE_ROOT}/bad.json"
runEdit 15 --http-relay "${PRIVATE_ROOT}/bad.json" --preview
chown 0:0 "${PRIVATE_ROOT}/bad.json"
ln "${PRIVATE_ROOT}/bad.json" "${PRIVATE_ROOT}/hardlink.json"
runEdit 15 --http-relay "${PRIVATE_ROOT}/bad.json" --preview
rm -- "${PRIVATE_ROOT}/hardlink.json"
ln -s "${INPUT}" "${PRIVATE_ROOT}/link.json"
runEdit 15 --http-relay "${PRIVATE_ROOT}/link.json" --preview
printf '{}\n' >"${PRIVATE_ROOT}/bad.json"
runEdit 15 --http-relay "${PRIVATE_ROOT}/bad.json" --preview
[[ "$(snapshot)" == "${before}" ]] || fail '预览或非法输入改变在线部署'
runEdit 0 --http-relay "${INPUT}" --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/relay.json" --slurpfile actual "${root}/config/spec.json" \
    '$expected==$actual' >/dev/null || fail '开启 relay 改变非目标 routing/account'
[[ "$(stat -c '%a %u %h' "${root}/config/spec.json")" == '600 0 1' ]] || fail 'relay 私有规格权限错误'
runStatus
jq -e '.http_relay=={enabled:true,core:"xray",port:36080,
  address_families:["ipv4","ipv6"],source_ips:["127.0.0.1/32","::1/128"]}' "${LOG}" >/dev/null
before=$(snapshot)
runEdit 15 --spec "${TEST_ROOT}/base.json" --confirm PADM-DOCKER-EDIT
MODE=health-fail
runEdit 14 --http-relay-off --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '失败事务未恢复 relay、业务规格和流量'
MODE=ok
runEdit 0 --http-relay-off --confirm PADM-DOCKER-EDIT
jq -en --slurpfile expected "${TEST_ROOT}/base.json" --slurpfile actual "${root}/config/spec.json" \
    '$expected==$actual' >/dev/null || fail '关闭 relay 删除其它 routing/account'
jq -e --arg uuid "${UUID}" '.accounts[$uuid].upload==17 and .accounts[$uuid].download==19' \
    "${root}/data/traffic/state.json" >/dev/null || fail 'relay 编辑清空业务流量'
for core in xray sing-box; do
    jq -e '[.inbounds[]|select(.tag=="padm-relay-http")]|length==0' \
        "${root}/config/${core}/config.json" >/dev/null || fail '关闭后 relay 入站残留'
done
runStatus
jq -e '.http_relay=={enabled:false}' "${LOG}" >/dev/null
printf 'docker-http-relay-regression-ok\n'
