#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-accounts-cli.XXXXXX")
exec 3>&2
trap 'accountTestStatus=$?
    [[ "${accountTestStatus}" == 0 ]] ||
        printf "docker-accounts-cli-regression-exit: line=%s rc=%s\n" "${LINENO}" "${accountTestStatus}" >&3
    [[ "${PADM_TEST_KEEP:-0}" == 1 ]] || rm -rf -- "${TEST_ROOT}"' EXIT
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

# 只监测生产 CLI 的外部 jq 参数，测试断言和夹具构建不计入。
export ACCOUNT_REAL_JQ
ACCOUNT_REAL_JQ=$(command -v jq)
export ACCOUNT_JQ_ARGV_LOG="${TEST_ROOT}/jq-argv"
ACCOUNT_CREDENTIALS="${TEST_ROOT}/credentials"
mkdir -p "${TEST_ROOT}/bin"
cat >"${TEST_ROOT}/bin/jq" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${ACCOUNT_JQ_MONITOR:-0}" == 1 ]]; then
    printf '%s\0' "$@" >>"${ACCOUNT_JQ_ARGV_LOG}"
fi
exec "${ACCOUNT_REAL_JQ}" "$@"
SH
chmod 0700 "${TEST_ROOT}/bin/jq"
export PATH="${TEST_ROOT}/bin:${PATH}"

runAccount() {
    local expected=$1 status=0 errorLine
    shift
    cp -- "${SPEC}" "${TEST_ROOT}/before-command.json"
    ACCOUNT_JQ_MONITOR=1 dockerAccountCommand "$@" >"${TEST_ROOT}/command.log" 2>&1 || status=$?
    if [[ "${status}" != "${expected}" ]]; then
        errorLine=$(sed -nE 's/^.*: line ([0-9]+):.*$/\1/p' "${TEST_ROOT}/command.log" | head -n 1)
        fail "$1 返回 ${status}，预期 ${expected}，错误行 ${errorLine:-unknown}"
    fi
    [[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 -name '.account.*.json' -print -quit)" ]] ||
        fail "$1 遗留私密账号草稿"
    [[ "${status}" == 0 ]] || cmp -s "${SPEC}" "${TEST_ROOT}/before-command.json" ||
        fail "$1 失败后改变当前规格"
    jq -r '[.core.protocols[] | .uuid,
      .shadowsocks.server_password?, .shadowsocks.user_password?] +
      [.accounts[] | .uuid, .password, .shadowsocks_password] | .[] | select(type=="string")' \
        "${SPEC}" >>"${ACCOUNT_CREDENTIALS}"
}

assertOnlyAccountChanged() {
    jq -e --arg id "$1" --slurpfile before "${TEST_ROOT}/before-command.json" '
      (. | del(.accounts)) == ($before[0] | del(.accounts)) and
      (.accounts | map(select(.id != $id))) ==
        ($before[0].accounts | map(select(.id != $id)))
    ' "${SPEC}" >/dev/null || fail '账号变更改写了其它账号或部署规格'
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
    if [[ -f "${TEST_ROOT}/uuid-collision" ]]; then
        local value
        value=$(<"${TEST_ROOT}/uuid-collision")
        rm -f -- "${TEST_ROOT}/uuid-collision"
        printf '%s\n' "${value}"
        return
    fi
    local counter=0
    [[ ! -f "${ACCOUNT_COUNTER_FILE}" ]] || counter=$(<"${ACCOUNT_COUNTER_FILE}")
    counter=$((counter + 1))
    printf '%s\n' "${counter}" >"${ACCOUNT_COUNTER_FILE}"
    printf '00000000-0000-4000-8000-%012d\n' "${counter}"
}
dockerSetupRandomHex() {
    local image=$1 bytes=$2
    if [[ -f "${TEST_ROOT}/password-collision" ]]; then
        local value
        value=$(<"${TEST_ROOT}/password-collision")
        rm -f -- "${TEST_ROOT}/password-collision"
        printf '%s\n' "${value}"
        return
    fi
    local counter=0
    [[ ! -f "${ACCOUNT_COUNTER_FILE}" ]] || counter=$(<"${ACCOUNT_COUNTER_FILE}")
    counter=$((counter + 1))
    printf '%s\n' "${counter}" >"${ACCOUNT_COUNTER_FILE}"
    printf '%0*s\n' "$((bytes * 2))" "${counter}" | tr ' ' 'a'
}
docker() {
    [[ "$*" == *' --entrypoint openssl '* && "${*: -3}" == 'rand -base64 16' &&
        "${ACCOUNT_FAIL_SS_GENERATION:-0}" != 1 ]] || return 1
    local counter=0
    [[ ! -f "${ACCOUNT_COUNTER_FILE}" ]] || counter=$(<"${ACCOUNT_COUNTER_FILE}")
    counter=$((counter + 1))
    printf '%s\n' "${counter}" >"${ACCOUNT_COUNTER_FILE}"
    printf '%016d' "${counter}" | command openssl base64 -A
}
openssl() {
    [[ "${ACCOUNT_FAIL_SS_GENERATION:-0}" != 1 ]] || return 1
    command openssl "$@"
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
      address_families:["ipv4"], listener_id:"vless-reality", name:"main-reality",
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
      listeners:["vless-reality"]
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

printf '%s\n' "${ALICE_UUID}" >"${TEST_ROOT}/uuid-collision"
runAccount 0 create --name Bob --listeners vless-reality --disabled
[[ ! -e "${TEST_ROOT}/uuid-collision" ]] || fail 'UUID 碰撞候选未被测试'
BOB=$(jq -er --arg name Bob '.accounts[] | select(.name == $name) | .id' "${SPEC}")
assertOnlyAccountChanged "${BOB}"
jq -e --arg id "${BOB}" '
  .accounts | length == 2 and any(.[]; .id == $id and .enabled == false and
    .name == "Bob" and (.password | length) >= 16 and .uuid != $id)
' "${SPEC}" >/dev/null || fail '新建账号没有写入完整凭据'

runAccount 0 enable "${BOB}"
jq -e --arg id "${BOB}" 'any(.accounts[]; .id == $id and .enabled == true)' "${SPEC}" >/dev/null ||
    fail '启用账号未生效'

# SS 使用已有 Reality 地址和身份，不需要 TLS，也不自动扩展已有账号授权。
jq '.core.protocols[0] as $source |
  .core.secondary_type = "sing-box" |
  .core.protocols += [{
    id:30,core:"sing-box",listener_id:"entry-ss",name:"main-ss",
    server:$source.server,public_port:8443,address_families:$source.address_families,uuid:$source.uuid,
    shadowsocks:{method:"2022-blake3-aes-128-gcm",
      server_password:"AAECAwQFBgcICQoLDA0ODw==",user_password:"+/v7+/v7+/v7+/v7+/v7+w=="}
  }]' "${SPEC}" >"${TEST_ROOT}/ss.json"
cp -- "${TEST_ROOT}/ss.json" "${SPEC}"
dockerConfigureSpecValidate "${SPEC}" || fail '双核无 TLS 的 SS 账号规格校验失败'

runAccount 0 create --name SS-New --listeners vless-reality,entry-ss
SS_ID=$(jq -er '.accounts[] | select(.name=="SS-New") | .id' "${SPEC}")
assertOnlyAccountChanged "${SS_ID}"
jq -e --arg id "${SS_ID}" 'any(.accounts[]; .id==$id and
  .listeners==["vless-reality","entry-ss"] and (.shadowsocks_password | length)==24)' \
    "${SPEC}" >/dev/null || fail '新建 SS 账号没有独立密钥'

runAccount 0 edit "${BOB}" --name Bob-Renamed --listeners vless-reality,entry-ss
assertOnlyAccountChanged "${BOB}"
jq -e --arg id "${BOB}" --slurpfile before "${TEST_ROOT}/before-command.json" '
  (.accounts[] | select(.id==$id)) as $after |
  ($before[0].accounts[] | select(.id==$id)) as $before |
  $after.name=="Bob-Renamed" and $after.uuid==$before.uuid and $after.password==$before.password and
  ($after.shadowsocks_password | length)==24 and $before.shadowsocks_password==null
' "${SPEC}" >/dev/null || fail '已有账号新增 SS 授权没有生成密钥或改变原凭据'
for fields in name listeners; do
    if [[ "${fields}" == name ]]; then
        runAccount 0 edit "${BOB}" --name Bob-SS
    else
        runAccount 0 edit "${BOB}" --listeners vless-reality,entry-ss
    fi
    assertOnlyAccountChanged "${BOB}"
    jq -e --arg id "${BOB}" --slurpfile before "${TEST_ROOT}/before-command.json" '
      any(.accounts[]; .id==$id and .name=="Bob-SS") and
      (.accounts[] | select(.id==$id) | del(.name)) ==
        ($before[0].accounts[] | select(.id==$id) | del(.name))
    ' "${SPEC}" >/dev/null || fail '保留 SS 授权或改名时改变了凭据'
done

jq -r --arg id "${BOB}" '.accounts[] | select(.id==$id) | .password' \
    "${SPEC}" >"${TEST_ROOT}/password-collision"
runAccount 0 copy "${BOB}" --listeners vless-reality,entry-ss
[[ ! -e "${TEST_ROOT}/password-collision" ]] || fail '密码碰撞候选未被测试'
COPY_ID=$(jq -er --arg name Bob-SS-copy '.accounts[] | select(.name == $name) | .id' "${SPEC}")
assertOnlyAccountChanged "${COPY_ID}"
jq -e --arg source "${BOB}" --arg copy "${COPY_ID}" '
  (.accounts[] | select(.id == $source)) as $sourceAccount |
  (.accounts[] | select(.id == $copy)) as $copyAccount |
  ($copyAccount.id != $sourceAccount.id and
   $copyAccount.uuid != $sourceAccount.uuid and
   $copyAccount.password != $sourceAccount.password and
   $copyAccount.shadowsocks_password != $sourceAccount.shadowsocks_password and
   ($copyAccount.shadowsocks_password | length) == 24 and
   $copyAccount.listeners == $sourceAccount.listeners)
' "${SPEC}" >/dev/null || fail '复制账号没有生成独立凭据'

beforeRotate=$(jq -c --arg id "${BOB}" '.accounts[] | select(.id == $id)' "${SPEC}")
runAccount 0 rotate "${BOB}" --yes
assertOnlyAccountChanged "${BOB}"
afterRotate=$(jq -c --arg id "${BOB}" '.accounts[] | select(.id == $id)' "${SPEC}")
[[ "${beforeRotate}" != "${afterRotate}" ]] || fail '轮换没有改变凭据'
jq -e --arg id "${BOB}" --argjson before "${beforeRotate}" '
  (.accounts[] | select(.id == $id)) as $after |
  ($after.id == $before.id and $after.name == $before.name and $after.enabled == $before.enabled and
   $after.listeners == $before.listeners and $after.uuid != $before.uuid and
   $after.password != $before.password and
   $after.shadowsocks_password != $before.shadowsocks_password and
   ($after.shadowsocks_password | length) == 24)
' "${SPEC}" >/dev/null || fail '轮换改变了稳定字段或没有替换凭据'

runAccount 0 edit "${BOB}" --listeners vless-reality
assertOnlyAccountChanged "${BOB}"
jq -e --arg id "${BOB}" --slurpfile before "${TEST_ROOT}/before-command.json" '
  (.accounts[] | select(.id==$id)) as $after |
  ($before[0].accounts[] | select(.id==$id)) as $before |
  $after.shadowsocks_password==null and $after.listeners==["vless-reality"] and
  ($after | del(.listeners,.shadowsocks_password)) == ($before | del(.listeners,.shadowsocks_password))
' "${SPEC}" >/dev/null || fail '移除 SS 授权未清理密钥或改变其它字段'

runAccount 0 disable "${BOB}"
jq -e --arg id "${BOB}" 'any(.accounts[]; .id == $id and .enabled == false)' "${SPEC}" >/dev/null ||
    fail '停用账号未生效'

runAccount 0 delete "${COPY_ID}" --yes
if jq -e --arg id "${COPY_ID}" 'any(.accounts[]; .id == $id)' "${SPEC}" >/dev/null; then
    fail '删除账号未生效'
fi

# 提交失败不得留下半成品，也不能改写当前规格。
ACCOUNT_FAIL_SS_GENERATION=1 runAccount "${PADM_DOCKER_RC_STATE}" \
    create --name FailedSS --listeners entry-ss
ACCOUNT_FAIL_SS_GENERATION=1 runAccount "${PADM_DOCKER_RC_STATE}" \
    edit "${BOB}" --listeners vless-reality,entry-ss
dockerConfigureApply() {
    return 17
}
runAccount 17 create --name Failed --listeners vless-reality,entry-ss
runAccount 17 rotate "${SS_ID}" --yes

python3 - "${ACCOUNT_JQ_ARGV_LOG}" "${ACCOUNT_CREDENTIALS}" <<'PY'
from pathlib import Path
import sys

arguments = Path(sys.argv[1]).read_bytes().split(b"\0")
credentials = set(Path(sys.argv[2]).read_bytes().splitlines())
assert b"--rawfile" in arguments and b"/dev/stdin" in arguments and credentials
assert not any(secret in argument for secret in credentials for argument in arguments), \
    "认证凭据出现在外部 jq 参数中"
for index, argument in enumerate(arguments[:-2]):
    assert not (argument == b"--arg" and arguments[index + 1] in
                (b"uuid", b"password", b"ss")), "写入凭据经 argv 传递"
PY

printf 'docker-accounts-cli-regression-ok\n'
