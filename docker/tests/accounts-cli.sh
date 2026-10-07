#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-accounts-cli.XXXXXX")
trap '[[ "${PADM_TEST_KEEP:-0}" == 1 ]] || rm -rf -- "${TEST_ROOT}"' EXIT
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || {
    printf 'docker-accounts-cli-regression requires Linux root\n' >&2
    exit 1
}

export PADM_DOCKER_SKIP_CHOWN=1
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
export PADM_DOCKER_SYSTEMD_DIR="${TEST_ROOT}/systemd"
mkdir -p "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_SYSTEMD_DIR}"

# 仅替换宿主动作；账号 CLI 仍使用生产规格校验和 jq 变更逻辑。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

fail() {
    printf 'docker-accounts-cli-regression-fail: %s\n' "$*" >&2
    exit 1
}

reject() {
    if "$@" >"${TEST_ROOT}/rejected.log" 2>&1; then
        fail "应拒绝: $*"
    fi
}

dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { :; }
dockerLockInstalledDeployment() { :; }
dockerConfigureReleaseReuseInstalled() { :; }
dockerReleaseDeploymentLock() { :; }
dockerComposeFile() { :; }
dockerConfigureReleaseReuseInstalled() { :; }
dockerTrafficRuntimeCheck() { :; }
dockerTrafficBeforeChange() { :; }
dockerEditBaselineValidate() { :; }
dockerSetupCleanup() { :; }
dockerCleanupConfigurationCandidate() { :; }
dockerCleanupStagedBundle() { :; }
dockerManifestCleanup() { :; }
dockerEntryCleanup() { :; }

APPLIED_SPEC="${TEST_ROOT}/applied.json"
dockerConfigureApply() {
    local source=$1
    cp -- "${source}" "${APPLIED_SPEC}" || return 1
    cp -- "${source}" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" || return 1
    chmod 0600 "${APPLIED_SPEC}" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    printf 'fixture configure apply\n'
}

# 生成器返回每次不同的确定性凭据，覆盖 ID/UUID/密码轮换及 SS 密钥分支。
ACCOUNT_COUNTER_FILE="${TEST_ROOT}/account-counter"
dockerManifestImageReference() {
    case "${1:-}" in
    xray) printf '%s\n' xray-fixture ;;
    ops) printf '%s\n' ops-fixture ;;
    sing-box) printf '%s\n' sing-box-fixture ;;
    *) return 1 ;;
    esac
}
dockerSetupTool() {
    [[ "${2:-}" == uuid ]] || return 1
    local counter=0
    [[ ! -f "${ACCOUNT_COUNTER_FILE}" ]] || counter=$(<"${ACCOUNT_COUNTER_FILE}")
    counter=$((counter + 1))
    printf '%s\n' "${counter}" >"${ACCOUNT_COUNTER_FILE}"
    printf '00000000-0000-4000-8000-%012d\n' "${counter}"
}
dockerSetupRandomHex() {
    local image=$1 bytes=$2
    local counter=0
    [[ ! -f "${ACCOUNT_COUNTER_FILE}" ]] || counter=$(<"${ACCOUNT_COUNTER_FILE}")
    counter=$((counter + 1))
    printf '%s\n' "${counter}" >"${ACCOUNT_COUNTER_FILE}"
    printf '%0*s\n' "$((bytes * 2))" "${counter}" | tr ' ' 'a'
}

SELF=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
ALICE=11111111-1111-4111-8111-111111111111
ALICE_UUID=44444444-4444-4444-8444-444444444444
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"

jq -n --arg self "${SELF}" --arg alice "${ALICE}" --arg aliceUuid "${ALICE_UUID}" '
  {
    schema_version: 3,
    release: {version:"3.1.8", manifest_sha256:("1"*64), signature_identity:"fixture"},
    core: {type:"xray", secondary_type:null, protocols:[{
      id:1, core:"xray", server:"reality.example.com", public_port:443,
      address_families:["ipv4"], listener_id:"entry-reality", name:"main-reality",
      uuid:$self,
      reality:{
        server_name:"reality.example.com", target_host:"reality.example.com",
        target_port:443, private_key:("A"*43), public_key:("B"*43), short_id:"1234abcd"
      }
    }]},
    tls: null,
    subscription: {enabled:false, token:"account-cli-token"},
    images: {
      xray:"ghcr.io/example/padm-xray:test@sha256:" + ("1"*64),
      "sing-box":"ghcr.io/example/padm-sing-box:test@sha256:" + ("1"*64),
      nginx:"ghcr.io/example/padm-nginx:test@sha256:" + ("1"*64),
      ops:"ghcr.io/example/padm-ops:test@sha256:" + ("1"*64),
      net:"ghcr.io/example/padm-net:test@sha256:" + ("1"*64)
    },
    host_integrations: [],
    accounts: [{
      id:$alice, name:"Alice", enabled:true, uuid:$aliceUuid,
      password:"Alice.-~@+=:Secret", shadowsocks_password:null,
      listeners:["entry-reality"]
    }]
  }
' >"${SPEC}"
chmod 0600 "${SPEC}"
dockerConfigureSpecValidate "${SPEC}" || fail '初始账号规格校验失败'

json=$(
    dockerAccountCommand list --json
)
jq -e --arg id "${ALICE}" '
  (if type == "array" then . else .accounts end) |
  type == "array" and length == 1 and .[0].id == $id and .[0].enabled == true
' <<<"${json}" >/dev/null || fail 'JSON 列表输出错误'

reject dockerAccountCommand list --json extra
reject dockerAccountCommand create --listeners entry-missing
reject dockerAccountCommand edit missing-account
reject dockerAccountCommand enable missing-account
reject dockerAccountCommand delete "${ALICE}"
reject dockerAccountCommand rotate "${ALICE}"

dockerAccountCommand create --name Bob --listeners entry-reality --disabled >/dev/null
BOB=$(jq -er --arg name Bob '.accounts[] | select(.name == $name) | .id' "${SPEC}")
jq -e --arg id "${BOB}" '
  .accounts | length == 2 and any(.[]; .id == $id and .enabled == false and
    .name == "Bob" and (.password | length) >= 16 and .uuid != $id)
' "${SPEC}" >/dev/null || fail '新建账号没有写入完整凭据'

dockerAccountCommand enable "${BOB}" >/dev/null
jq -e --arg id "${BOB}" 'any(.accounts[]; .id == $id and .enabled == true)' "${SPEC}" >/dev/null ||
    fail '启用账号未生效'

dockerAccountCommand edit "${BOB}" --name Bob-Renamed --listeners entry-reality >/dev/null
jq -e --arg id "${BOB}" 'any(.accounts[]; .id == $id and .name == "Bob-Renamed")' "${SPEC}" >/dev/null ||
    fail '编辑账号未生效'

dockerAccountCommand copy "${BOB}" --name Bob-Copy >/dev/null
COPY_ID=$(jq -er --arg name Bob-Copy '.accounts[] | select(.name == $name) | .id' "${SPEC}")
jq -e --arg source "${BOB}" --arg copy "${COPY_ID}" '
  (.accounts[] | select(.id == $source)) as $sourceAccount |
  (.accounts[] | select(.id == $copy)) as $copyAccount |
  ($copyAccount.id != $sourceAccount.id and
   $copyAccount.uuid != $sourceAccount.uuid and
   $copyAccount.password != $sourceAccount.password and
   $copyAccount.listeners == $sourceAccount.listeners)
' "${SPEC}" >/dev/null || fail '复制账号没有生成独立凭据'

beforeRotate=$(jq -c --arg id "${BOB}" '.accounts[] | select(.id == $id)' "${SPEC}")
dockerAccountCommand rotate "${BOB}" --yes >/dev/null
afterRotate=$(jq -c --arg id "${BOB}" '.accounts[] | select(.id == $id)' "${SPEC}")
[[ "${beforeRotate}" != "${afterRotate}" ]] || fail '轮换没有改变凭据'
jq -e --arg id "${BOB}" --argjson before "${beforeRotate}" '
  (.accounts[] | select(.id == $id)) as $after |
  ($after.id == $before.id and $after.name == $before.name and
   $after.listeners == $before.listeners and $after.uuid != $before.uuid and
   $after.password != $before.password)
' "${SPEC}" >/dev/null || fail '轮换改变了稳定字段或没有替换凭据'

dockerAccountCommand disable "${BOB}" >/dev/null
jq -e --arg id "${BOB}" 'any(.accounts[]; .id == $id and .enabled == false)' "${SPEC}" >/dev/null ||
    fail '停用账号未生效'

dockerAccountCommand delete "${COPY_ID}" --yes >/dev/null
if jq -e --arg id "${COPY_ID}" 'any(.accounts[]; .id == $id)' "${SPEC}" >/dev/null; then
    fail '删除账号未生效'
fi

# 提交失败不得留下半成品，也不能改写当前规格。
ORIGINAL=$(sha256sum "${SPEC}" | awk '{print $1}')
dockerConfigureApply() {
    return 17
}
reject dockerAccountCommand create --name Failed --listeners entry-reality
[[ "$(sha256sum "${SPEC}" | awk '{print $1}')" == "${ORIGINAL}" ]] ||
    fail '提交失败改写了当前规格'

printf 'docker-accounts-cli-regression-ok\n'
