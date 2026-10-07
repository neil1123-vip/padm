#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-business.XXXXXX")
trap '[[ "${PADM_TEST_KEEP:-0}" == 1 ]] || rm -rf -- "${TEST_ROOT}"' EXIT
[[ "$(uname -s)" == Linux && "$(id -u)" -eq 0 ]] || {
    printf 'docker-business-regression requires Linux root\n' >&2
    exit 1
}

export PADM_DOCKER_SKIP_CHOWN=1
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
mkdir -p "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data/traffic"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

fail() { printf 'docker-business-regression-fail: %s\n' "$*" >&2; exit 1; }
reject() {
    local status=0
    "$@" >"${TEST_ROOT}/reject.log" 2>&1 || status=$?
    [[ "${status}" -ne 0 ]] || fail "应拒绝: $*"
}

# 只替换宿主动作；业务备份仍走真实校验、合并和流量路径。
dockerHostPreflight() { :; }
dockerLockInstalledDeployment() { :; }
dockerReleaseDeploymentLock() { :; }
dockerConfigurationInterrupted() { :; }
dockerConfigureReleaseReuseInstalled() { :; }
dockerTrafficBeforeChange() { :; }
dockerTrafficRuntimeCheck() { :; }
dockerCleanupConfigurationCandidate() { :; }
dockerRemoveManagedTree() { rm -rf -- "$2"; }

ALICE=11111111-1111-4111-8111-111111111111
BOB=22222222-2222-4222-8222-222222222222
ALICE_UUID=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
BOB_UUID=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb
MAIN_TOKEN=0123456789abcdef0123456789abcdef
SHARE_TOKEN=abcdef0123456789
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
SHARES="${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json"
TRAFFIC="${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json"

jq -n --arg alice "${ALICE}" --arg bob "${BOB}" \
    --arg aliceUuid "${ALICE_UUID}" --arg bobUuid "${BOB_UUID}" \
    --arg token "${MAIN_TOKEN}" '
  {schema_version:3, release:{version:"3.1.8",manifest_sha256:("1"*64),signature_identity:"fixture"},
   core:{type:"xray",secondary_type:null,protocols:[
    {id:1,core:"xray",server:"reality.example.com",public_port:443,address_families:["ipv4"],
     listener_id:"entry-reality",name:"Reality",uuid:"33333333-3333-4333-8333-333333333333",
     reality:{server_name:"reality.example.com",target_host:"reality.example.com",target_port:443,
       private_key:("A"*43),public_key:("B"*43),short_id:"1234abcd"}},
    {id:21,core:"xray",server:"ws.example.com",public_port:8443,address_families:["ipv4"],
     listener_id:"entry-ws",name:"WebSocket",uuid:"44444444-4444-4444-8444-444444444444",
     websocket:{domain:"ws.example.com",path:"padmtest",backend_port:31297,tls_port:8443}}]},
   tls:{domain:"ws.example.com"},subscription:{enabled:true,token:$token},
   images:{xray:"ghcr.io/example/padm-xray:test@sha256:" + ("1"*64),
           "sing-box":"ghcr.io/example/padm-sing-box:test@sha256:" + ("1"*64),
           nginx:"ghcr.io/example/padm-nginx:test@sha256:" + ("1"*64),
           ops:"ghcr.io/example/padm-ops:test@sha256:" + ("1"*64),
           net:"ghcr.io/example/padm-net:test@sha256:" + ("1"*64)},
   host_integrations:[],
   accounts:[
    {id:$alice,name:"Alice",enabled:true,uuid:$aliceUuid,password:"Alice.-~@+=:Secret",
     shadowsocks_password:null,listeners:["entry-reality"]},
    {id:$bob,name:"Bob",enabled:true,uuid:$bobUuid,password:"Bob.-~@+=:Secret",
     shadowsocks_password:null,listeners:["entry-ws"]}]}
' >"${SPEC}"
chmod 0600 "${SPEC}"
dockerConfigureSpecValidate "${SPEC}" || fail '初始规格校验失败'

jq -n --arg alice "${ALICE}" --arg token "${SHARE_TOKEN}" '
 {schema_version:1,groups:[{id:"share-0123456789abcdef",name:"Team",enabled:true,
   token:$token,account_ids:[$alice],listener_ids:["entry-reality"]}]}
' >"${SHARES}"
chmod 0600 "${SHARES}"
jq -n --arg alice "${ALICE}" --arg bob "${BOB}" '
 {schema_version:1,accounts:{
   ($alice):{name:"Alice",upload:900,download:100,limit_bytes:1000,baseline:{}},
   ($bob):{name:"Bob",upload:5,download:7,limit_bytes:0,baseline:{}}}}
' >"${TRAFFIC}"
chmod 0600 "${TRAFFIC}"
dockerSubscriptionStateValidate "${SHARES}" || fail '分享组夹具无效'
dockerTrafficReadState >/dev/null || fail '流量夹具无效'

BACKUP="${TEST_ROOT}/business.json"
dockerBusinessExport "${BACKUP}" "${SPEC}" >/dev/null || fail '业务备份失败'
[[ "$(stat -c '%a' "${BACKUP}")" == 600 ]] || fail '备份权限不是 600'
jq -e '.format == "padm-docker-business" and .schema_version == 1' "${BACKUP}" >/dev/null ||
    fail '备份格式错误'
jq -e '(.listeners | length == 2 and any(.[]; .listener_id == "entry-reality")) and
  (.accounts | length == 2 and .[0].password != null) and
  .subscription.enabled == true and (.shares.groups | length == 1)' "${BACKUP}" >/dev/null ||
    fail '备份内容不完整'
jq -e '(.traffic.accounts | to_entries | all(.value.baseline == {}))' "${BACKUP}" >/dev/null ||
    fail '备份带入 baseline'

BAD="${TEST_ROOT}/bad.json"
printf '{"format":"padm-docker-business","schema_version":99}\n' >"${BAD}"
chmod 600 "${BAD}"
reject dockerBusinessCommand preview "${BAD}" --strategy merge
ln -s "${BACKUP}" "${TEST_ROOT}/link.json"
reject dockerBusinessCommand preview "${TEST_ROOT}/link.json" --strategy merge
cp -- "${BACKUP}" "${TEST_ROOT}/duplicate.json"
printf '\n{}\n' >>"${TEST_ROOT}/duplicate.json"
chmod 600 "${TEST_ROOT}/duplicate.json"
reject dockerBusinessCommand preview "${TEST_ROOT}/duplicate.json" --strategy merge
jq '.listeners[0].listener_id = "entry-missing"' "${BACKUP}" >"${TEST_ROOT}/topology.json"
chmod 600 "${TEST_ROOT}/topology.json"
reject dockerBusinessCommand preview "${TEST_ROOT}/topology.json" --strategy merge

CURRENT_SPEC_HASH=$(sha256sum "${SPEC}" | awk '{print $1}')
CURRENT_SHARES_HASH=$(sha256sum "${SHARES}" | awk '{print $1}')
mkdir -p "${TEST_ROOT}/merge"
dockerBusinessBuildDraft "${BACKUP}" "${SPEC}" merge "${TEST_ROOT}/merge" ||
    fail 'merge 草稿生成失败'
jq -e --arg alice "${ALICE}" --arg bob "${BOB}" '
 .spec.accounts | length == 2 and any(.[]; .id == $alice) and any(.[]; .id == $bob)
' "${TEST_ROOT}/merge/business.json" >/dev/null || fail 'merge 丢失账号'
jq -e '.shares.groups | length == 1' "${TEST_ROOT}/merge/business.json" >/dev/null ||
    fail 'merge 丢失分享组'
[[ "$(sha256sum "${SPEC}" | awk '{print $1}')" == "${CURRENT_SPEC_HASH}" ]] ||
    fail 'merge 草稿改写当前规格'
[[ "$(sha256sum "${SHARES}" | awk '{print $1}')" == "${CURRENT_SHARES_HASH}" ]] ||
    fail 'merge 草稿改写当前分享状态'

mkdir -p "${TEST_ROOT}/replace"
dockerBusinessBuildDraft "${BACKUP}" "${SPEC}" replace "${TEST_ROOT}/replace" ||
    fail 'replace 草稿生成失败'
jq -e --arg alice "${ALICE}" --arg bob "${BOB}" '
 .spec.accounts | length == 2 and any(.[]; .id == $alice) and any(.[]; .id == $bob)
' "${TEST_ROOT}/replace/business.json" >/dev/null || fail 'replace 账号错误'

MERGED_TRAFFIC=$(dockerBusinessMergeTraffic \
    '{"schema_version":1,"accounts":{"11111111-1111-4111-8111-111111111111":{"name":"Alice","upload":1,"download":9999,"limit_bytes":10,"baseline":{"xray":{"upload":{"generation":"old","value":1},"download":{"generation":"old","value":1}}}}}}' \
    '{"schema_version":1,"accounts":{"11111111-1111-4111-8111-111111111111":{"name":"Alice","upload":900,"download":100,"limit_bytes":1000,"baseline":{"xray":{"upload":{"generation":"new","value":2},"download":{"generation":"new","value":2}}}}}}') ||
    fail '流量合并失败'
jq -e '.accounts["11111111-1111-4111-8111-111111111111"] |
  .upload == 900 and .download == 9999 and .limit_bytes == 1000 and
  .baseline.xray.upload.generation == "new"' <<<"${MERGED_TRAFFIC}" >/dev/null ||
    fail '流量累计未取 max 或额度/baseline策略错误'

# preview 必须只校验候选，不提交；restore 则把业务源传给配置事务。
APPLY_MODE=''
APPLY_BUSINESS=''
dockerConfigureApply() {
    APPLY_MODE=${4:-}
    APPLY_BUSINESS=${5:-}
    printf '%s\n' "${4:-}" >"${TEST_ROOT}/apply-mode"
    [[ "${APPLY_MODE}" != configure ]] || return 23
    return 0
}
dockerBusinessCommand preview "${BACKUP}" --strategy merge >/dev/null ||
    fail 'preview 失败'
[[ "$(cat "${TEST_ROOT}/apply-mode")" == preview ]] || fail 'preview 未进入候选事务'
[[ "$(sha256sum "${SPEC}" | awk '{print $1}')" == "${CURRENT_SPEC_HASH}" ]] ||
    fail 'preview 改写规格'

reject dockerBusinessCommand restore "${BACKUP}" --strategy merge
printf 'docker-business-regression-ok\n'
