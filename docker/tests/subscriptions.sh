#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-subscriptions.XXXXXX")
trap '[[ "${PADM_TEST_KEEP:-0}" == 1 ]] || rm -rf -- "${TEST_ROOT}"' EXIT
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || {
    printf 'docker-subscriptions-regression requires Linux root\n' >&2
    exit 1
}

export PADM_DOCKER_SKIP_CHOWN=1
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
mkdir -p "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data/subscription"

# 分享组只依赖已有的 Docker 规格和渲染器，宿主动作全部替换为无副作用夹具。
source "${PROJECT_ROOT}/install-docker.sh"
dockerHostPreflight() { :; }
dockerLockInstalledDeployment() { :; }
dockerReleaseDeploymentLock() { :; }
dockerSetupCleanup() { :; }
dockerCleanupStagedBundle() { :; }
dockerManifestCleanup() { :; }
dockerEntryCleanup() { :; }

fail() {
    printf 'docker-subscriptions-regression-fail: %s\n' "$*" >&2
    exit 1
}

reject() {
    local status=0
    "$@" >"${TEST_ROOT}/reject.out" 2>&1 || status=$?
    if [[ "${status}" -eq 0 ]]; then
        fail "应拒绝: $*"
    fi
    return 0
}

ALICE=11111111-1111-4111-8111-111111111111
BOB=22222222-2222-4222-8222-222222222222
ALICE_UUID=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
BOB_UUID=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb
MAIN_TOKEN=0123456789abcdef0123456789abcdef
MAIN_UUID=33333333-3333-4333-8333-333333333333
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"

jq -n --arg alice "${ALICE}" --arg bob "${BOB}" \
    --arg aliceUuid "${ALICE_UUID}" --arg bobUuid "${BOB_UUID}" \
    --arg token "${MAIN_TOKEN}" '
  {
    schema_version: 3,
    release: {version:"3.1.8", manifest_sha256:("1"*64), signature_identity:"fixture"},
    core: {type:"xray", secondary_type:null, protocols:[
      {id:1, core:"xray", server:"reality.example.com", public_port:443,
       address_families:["ipv4"], listener_id:"entry-reality", name:"Reality",
       uuid:"33333333-3333-4333-8333-333333333333",
       reality:{server_name:"reality.example.com", target_host:"reality.example.com",
         target_port:443, private_key:("A"*43), public_key:("B"*43), short_id:"1234abcd"}},
      {id:21, core:"xray", server:"ws.example.com", public_port:8443,
       address_families:["ipv4"], listener_id:"entry-ws", name:"WebSocket",
       uuid:"44444444-4444-4444-8444-444444444444",
        websocket:{domain:"ws.example.com", path:"padmtest",
         backend_port:31297, tls_port:8443}}
    ]},
    tls: {domain:"ws.example.com"},
    subscription: {enabled:true, token:$token},
    images: {
      xray:"ghcr.io/example/padm-xray:test@sha256:" + ("1"*64),
      "sing-box":"ghcr.io/example/padm-sing-box:test@sha256:" + ("1"*64),
      nginx:"ghcr.io/example/padm-nginx:test@sha256:" + ("1"*64),
      ops:"ghcr.io/example/padm-ops:test@sha256:" + ("1"*64),
      net:"ghcr.io/example/padm-net:test@sha256:" + ("1"*64)
    },
    host_integrations: [],
    accounts: [
      {id:$alice, name:"Alice", enabled:true, uuid:$aliceUuid,
       password:"Alice.-~@+=:Secret", shadowsocks_password:null,
       listeners:["entry-reality"]},
      {id:$bob, name:"Bob", enabled:true, uuid:$bobUuid,
       password:"Bob.-~@+=:Secret", shadowsocks_password:null,
       listeners:["entry-ws"]}
    ]
  }
' >"${SPEC}"
chmod 0600 "${SPEC}"
dockerConfigureSpecValidate "${SPEC}" || fail '初始订阅规格校验失败'
printf 'main subscription sentinel\n' >"${PADM_DOCKER_INSTALL_DIR}/data/subscription/${MAIN_TOKEN}"
chmod 0640 "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${MAIN_TOKEN}"
BASE_FILE="${TEST_ROOT}/base-subscription.txt"
dockerGenerateSubscription "${SPEC}" "${BASE_FILE}" || fail '主订阅生成失败'
grep -q "${MAIN_UUID}" "${BASE_FILE}" || fail '主订阅默认未包含入口 URI'

reject dockerSubscriptionCommand list --json extra
reject dockerSubscriptionCommand create --accounts "${ALICE},${ALICE}"
reject dockerSubscriptionCommand create --listeners entry-missing
reject dockerSubscriptionCommand create --accounts "${ALICE}" --listeners entry-ws
reject dockerSubscriptionCommand edit share-not-valid --name invalid

GROUP=$(dockerSubscriptionCommand create --name Team --accounts "${ALICE}" --listeners entry-reality)
GROUP_TOKEN=$(jq -er --arg id "${GROUP}" '.groups[] | select(.id == $id) | .token' \
    "${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json")
SHARE_FILE="${PADM_DOCKER_INSTALL_DIR}/data/subscription/${GROUP_TOKEN}"
[[ -f "${SHARE_FILE}" && ! -L "${SHARE_FILE}" ]] || fail '创建分享组未生成 token 文件'
[[ "$(stat -c '%a' "${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json")" == 600 ]] ||
    fail '分享组状态文件权限错误'
grep -q '^vless://' "${SHARE_FILE}" || fail '分享内容未生成 URI'
grep -q "${ALICE_UUID}" "${SHARE_FILE}" || fail '分享内容未包含选中账号'
! grep -q "${MAIN_UUID}" "${SHARE_FILE}" || fail '分享内容泄露主订阅自用 UUID'
! grep -q "${BOB_UUID}" "${SHARE_FILE}" || fail '分享内容包含未选账号'
grep -q 'reality.example.com' "${SHARE_FILE}" || fail '账号/入口过滤后内容缺失'
! grep -q 'ws.example.com' "${SHARE_FILE}" || fail '入口过滤未生效'
[[ "$(cat "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${MAIN_TOKEN}")" == 'main subscription sentinel' ]] ||
    fail '分享组操作改写了主订阅文件'

LIST_JSON=$(dockerSubscriptionCommand list --json)
jq -e --arg id "${GROUP}" '
  length == 1 and .[0].id == $id and
  (.[0] | has("token") | not) and
  .[0].account_ids == ["11111111-1111-4111-8111-111111111111"]
' <<<"${LIST_JSON}" >/dev/null || fail '分享组 JSON 列表泄露或内容错误'

CONTENT=$(dockerSubscriptionCommand content "${GROUP}")
[[ -n "${CONTENT}" ]] || fail '纯内容输出为空'
! grep -Eq '^(分享|https?://|[[:space:]]*$)' <<<"${CONTENT}" ||
    fail '纯内容输出混入说明或链接'
while IFS= read -r line; do
    [[ "${line}" =~ ^(vless|vmess|trojan|hysteria2|anytls|naive\+https|ss|tuic):// ]] ||
        fail "纯内容包含非 URI 行: ${line}"
done <<<"${CONTENT}"

LINK=$(dockerSubscriptionCommand links "${GROUP}")
[[ "${LINK}" == "https://ws.example.com/subscriptions/${GROUP_TOKEN}" ]] ||
    fail '分享 HTTPS 链接错误'

dockerSubscriptionCommand edit "${GROUP}" --name Team-Renamed --listeners entry-reality >/dev/null
jq -e --arg id "${GROUP}" '.groups[] | select(.id == $id and .name == "Team-Renamed")' \
    "${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json" >/dev/null || fail '编辑分享组失败'

dockerSubscriptionCommand rotate "${GROUP}" --yes >/dev/null
NEW_TOKEN=$(jq -er --arg id "${GROUP}" '.groups[] | select(.id == $id) | .token' \
    "${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json")
[[ "${NEW_TOKEN}" != "${GROUP_TOKEN}" && -f "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${NEW_TOKEN}" ]] ||
    fail '轮换没有生成新 token 文件'
[[ ! -e "${SHARE_FILE}" ]] || fail '轮换未删除旧 token 文件'
GROUP_TOKEN="${NEW_TOKEN}"

dockerSubscriptionCommand disable "${GROUP}" >/dev/null
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${GROUP_TOKEN}" ]] ||
    fail '停用未删除 token 文件'
dockerSubscriptionCommand edit "${GROUP}" --name Disabled >/dev/null
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${GROUP_TOKEN}" ]] ||
    fail '编辑停用组错误生成 token 文件'
reject dockerSubscriptionCommand content "${GROUP}"
reject dockerSubscriptionCommand links "${GROUP}"

dockerSubscriptionCommand enable "${GROUP}" >/dev/null
[[ -f "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${GROUP_TOKEN}" ]] ||
    fail '启用未重新生成 token 文件'

DISABLED=$(dockerSubscriptionCommand create --name Disabled --disabled --accounts "${BOB}" --listeners entry-ws)
DISABLED_TOKEN=$(jq -er --arg id "${DISABLED}" '.groups[] | select(.id == $id) | .token' \
    "${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json")
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${DISABLED_TOKEN}" ]] ||
    fail '禁用创建错误生成 token 文件'
dockerSubscriptionCommand delete "${DISABLED}" --yes >/dev/null
jq -e --arg id "${DISABLED}" 'any(.groups[]; .id == $id) | not' \
    "${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json" >/dev/null || fail '删除分享组失败'

rm -f -- "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${GROUP_TOKEN}"
ln -s "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${MAIN_TOKEN}" \
    "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${GROUP_TOKEN}"
reject dockerSubscriptionCommand disable "${GROUP}"
rm -f -- "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${GROUP_TOKEN}"

NGINX="${TEST_ROOT}/nginx.conf"
dockerGenerateNginxConfig "${SPEC}" "${NGINX}"
grep -qF 'location ~ ^/subscriptions/(?<padm_subscription_token>[A-Za-z0-9_-]{16,128})$ {' "${NGINX}" ||
    fail 'Nginx 未生成受限 token 路由'
grep -qF 'proxy_pass http://subscription:8081/$padm_subscription_token;' "${NGINX}" ||
    fail 'Nginx token 代理路径错误'

printf 'docker-subscriptions-regression-ok\n'
