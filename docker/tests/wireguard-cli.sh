#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
if [[ "${1:-}" == --cancel ]]; then
    TEST_ROOT=$2
else
    TEST_ROOT=$(mktemp -d /root/padm-wireguard-cli.XXXXXX)
    trap 'rm -rf -- "${TEST_ROOT}"' EXIT
fi
trap 'printf "wireguard-cli-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_SKIP_CHOWN=0
export PADM_DOCKER_LOCK_TIMEOUT=1 PYTHONDONTWRITEBYTECODE=1
root=${PADM_DOCKER_INSTALL_DIR}
LOG="${TEST_ROOT}/command.log"
CALLS="${TEST_ROOT}/calls.log"
MODE=ok
CASES=0
PRIVATE=$(printf '%032d' 1 | base64 -w0)
PUBLIC=$(printf '%032d' 2 | base64 -w0)
PEER=$(printf '%032d' 3 | base64 -w0)
fail() { cat "${LOG}" >&2; printf 'wireguard-cli-fail: %s\n' "$*" >&2; exit 1; }

# 规格、私密文件和命令使用生产路径，只隔离宿主、工具容器与配置事务的提交边界。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/control.sh"
dockerHostPreflight() { printf 'preflight\n' >>"${CALLS}"; }
dockerLockInstalledDeployment() { dockerAcquireDeploymentLock; }
dockerManagedSpecMatchesDeployment() { [[ "${MODE}" != drift ]]; }
dockerConfigureReleaseReuseInstalled() { printf 'release\n' >>"${CALLS}"; }
dockerConfigureReleaseValidate() { [[ "${MODE}" != release-fail ]]; }
dockerCurrentOwnsHostIntegration() {
    jq -e --arg type "$1" 'any(.host_integrations[]; .type == $type)' "${root}/config/spec.json" >/dev/null
}
dockerRealityProbeRun() {
    local directory
    if [[ "${16:-}" == 'wg pubkey < /input/private.key' ]]; then
        [[ "$#" == 16 && "${11}" == "type=bind,src=${root}/secrets/net/wireguard,dst=/input,readonly" &&
            "${14}" == "$(jq -r '.images.net' "${root}/config/spec.json")" ]] ||
            fail '迁移身份核验没有只读挂载当前私密目录'
        printf '%s\n' "${CURRENT_PUBLIC}"
        [[ "${MODE}" != pair-fail ]]
        return
    fi
    [[ "$#" == 16 && "$1 $2 $3 $4 $5 $6 $7 $8 $9 ${10}" == \
        '10 --pull never --user 0:0 --network none --log-driver none --mount' &&
        "${12} ${13}" == '--entrypoint sh' && "${15}" == -ec &&
        "${14}" == "$(jq -r '.images.net' "${root}/config/spec.json")" &&
        "${16}" == 'umask 077; wg genkey > /input/private.key; wg pubkey < /input/private.key > /input/public.key' ]] ||
        fail 'WireGuard 密钥工具容器参数不受限'
    directory=${11#type=bind,src=}
    directory=${directory%,dst=/input}
    [[ "${11}" == "type=bind,src=${directory},dst=/input" && "${directory}" == "${root}/.wireguard."* &&
        "$(stat -c '%u:%g:%a' "${directory}")" == 0:0:700 ]] ||
        fail '密钥工具容器没有使用本次私密暂存'
    printf 'keygen\n' >>"${CALLS}"
    (umask 077; printf '%s\n' "${PRIVATE}" >"${directory}/private.key")
    [[ "${MODE}" != key-fail ]] || return 1
    (umask 077; printf '%s\n' "${PUBLIC}" >"${directory}/public.key")
}
dockerAccountApplyDraft() {
    local draft=$1
    [[ -e "${root}/locks/deployment.lock" ]] || fail '首次启用没有持有部署锁'
    jq -en --slurpfile before "${root}/config/spec.json" --slurpfile next "${draft}" '
      ($next[0] | del(.host_integrations)) == ($before[0] | del(.host_integrations)) and
      $next[0].host_integrations == ($before[0].host_integrations + [{
        type:"wireguard",profile:"net-wireguard",firewall_rules:[],devices:["wg-padm"],
        schedules:[],settings:{config_file:"wg-padm.conf",interface:"wg-padm"}
      }])' >/dev/null || fail '首次启用改变其它规格或没有使用固定宿主集成'
    dockerConfigureSpecValidate "${draft}" || fail '首次启用生成了无效规格'
    printf 'apply\n' >>"${CALLS}"
    [[ "${MODE}" != apply-fail ]] || return "${PADM_DOCKER_RC_COMPOSE}"
    cp -- "${draft}" "${root}/config/spec.json"
    chmod 0600 "${root}/config/spec.json"
}

if [[ "${1:-}" == --cancel ]]; then
    dockerWireGuardCommand prepare --address 10.90.0.1 --listen-port 51820
    exit $?
fi

dockerInitializeStateRoot
jq -n '
  {schema_version:3,release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"fixture"},
   core:{type:"sing-box",secondary_type:null,protocols:[{
     id:1,core:"sing-box",listener_id:"entry-main",server:"proxy.example.com",public_port:35441,
     address_families:["ipv4"],name:"WireGuard-CLI",uuid:"11111111-1111-4111-8111-111111111111",
     reality:{server_name:"www.debian.org",target_host:"www.debian.org",target_port:443,
       private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
       public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",short_id:"1234"}}]},
   tls:null,subscription:{enabled:false,token:"0123456789abcdef"},
   images:(["xray","sing-box","nginx","ops","net"] | map({key:.,value:
     ("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries),
   host_integrations:[]}
' >"${root}/config/spec.json"
chmod 0600 "${root}/config/spec.json"
cp -- "${root}/config/spec.json" "${TEST_ROOT}/base.json"
dockerConfigureSpecValidate "${root}/config/spec.json" || fail '基础规格夹具无效'
: >"${CALLS}"

snapshot() (
    cd -- "${root}"
    find config secrets -type f -printf '%p %m %U %G %n\n' | LC_ALL=C sort
    find config secrets -type f -print0 | sort -z | xargs -0 -r sha256sum
)
assert_clean() {
    [[ ! -e "${root}/locks/deployment.lock" &&
        -z "$(find "${root}" -maxdepth 1 -name '.wireguard.*' -print -quit)" ]] ||
        fail '命令残留部署锁或密钥暂存'
    ! grep -qF -- "${PRIVATE}" "${LOG}" || fail '命令输出泄露 WireGuard 私钥'
}
run_case() {
    local expected=$1 actual=0
    shift
    (dockerWireGuardCommand "$@") >"${LOG}" 2>&1 || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "$*: 退出码 ${actual}，预期 ${expected}"
    assert_clean
    CASES=$((CASES + 1))
}
before=$(snapshot)
for arguments in \
    'prepare --address 10.90.0.1 --listen-port 51820' \
    'prepare --address 10.90.0.1 --address 10.90.0.2 --listen-port 51820 --yes' \
    'prepare --address 10.90.0.1 --listen-port 51820 --yes --yes' \
    'prepare --address 127.0.0.1 --listen-port 51820 --yes' \
    'prepare --address 10.90.0.1 --listen-port 80 --yes' \
    'peer --peer-address 10.90.0.2 --peer-public-key missing --yes' \
    'status --yes' \
    'peers list --yes' \
    'peers list --peer-address 10.90.0.2' \
    'peers unknown --yes' \
    'peers add --peer-address 10.90.0.2 --yes' \
    'peers update --peer-address 10.90.0.2 --yes' \
    'peers remove --peer-address 10.90.0.2 --endpoint none --yes' \
    'peers remove --peer-address 10.90.0.2 --peer-address 10.90.0.3 --yes' \
    'peers remove --peer-address 10.90.0.2 --rotate-key --yes'; do
    read -r -a options <<<"${arguments}"
    run_case "${PADM_DOCKER_RC_USAGE}" "${options[@]}"
done
[[ ! -s "${CALLS}" && "$(snapshot)" == "${before}" ]] ||
    fail '未确认或非法参数访问后端或改变已有输入'

# 真实 TTY 回答 n，确认取消发生在预检、锁和密钥生成之前。
python3 -B - "${BASH_SOURCE[0]}" "${TEST_ROOT}" "${LOG}" <<'PY'
import os
from pathlib import Path
import select
import signal
import sys
import time

pid, master = os.forkpty()
if pid == 0:
    os.execvp("bash", ["bash", sys.argv[1], "--cancel", sys.argv[2]])
output, sent, code = b"", False, None
try:
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if select.select([master], [], [], 0.1)[0]:
            try:
                chunk = os.read(master, 4096)
            except OSError:
                chunk = b""
            output += chunk
            if not sent and "确认 WireGuard".encode() in output:
                os.write(master, b"n\n")
                sent = True
        finished, status = os.waitpid(pid, os.WNOHANG)
        if finished:
            code = os.waitstatus_to_exitcode(status)
            break
    assert sent and code == 2, (sent, code, output)
finally:
    if code is None:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    os.close(master)
    Path(sys.argv[3]).write_bytes(output)
PY
CASES=$((CASES + 1))
assert_clean
[[ ! -s "${CALLS}" && "$(snapshot)" == "${before}" ]] || fail '取消仍执行了后端或修改'

for MODE in drift release-fail key-fail; do
    expected=${PADM_DOCKER_RC_STATE}
    [[ "${MODE}" != release-fail ]] || expected=${PADM_DOCKER_RC_MANIFEST}
    [[ "${MODE}" != key-fail ]] || expected=${PADM_DOCKER_RC_HOST}
    run_case "${expected}" prepare --address 10.90.0.1 --listen-port 51820 --yes
    [[ "$(snapshot)" == "${before}" ]] || fail "${MODE}: 失败改变已有输入"
done
MODE=ok
run_case 0 status
jq -e '.state == "absent" and .configured == false and .enabled == false' "${LOG}" >/dev/null
run_case 0 prepare --address 10.90.0.1 --listen-port 51820 --yes
jq -e --arg key "${PUBLIC}" '.public_key == $key and .configured == false' "${LOG}" >/dev/null
run_case 0 status
jq -e '.configured == false and .enabled == false and .address == "10.90.0.1"' "${LOG}" >/dev/null
before=$(snapshot)
run_case "${PADM_DOCKER_RC_CONFLICT}" prepare --address 10.90.0.3 --listen-port 51821 --yes
run_case "${PADM_DOCKER_RC_STATE}" peer --peer-address 10.90.0.1 --peer-public-key "${PEER}" --yes
[[ "$(snapshot)" == "${before}" ]] || fail '重复准备或自身 Peer 改变已有输入'
run_case 0 peer --peer-address 10.90.0.2 --peer-public-key "${PEER}" --endpoint 198.18.0.2:51821 --yes
before=$(snapshot)
run_case "${PADM_DOCKER_RC_CONFLICT}" peers add --peer-address 10.90.0.3 \
    --peer-public-key "${PUBLIC}" --yes
run_case "${PADM_DOCKER_RC_STATE}" peer --peer-address 10.90.0.3 --peer-public-key "${PEER}" --yes
[[ "$(snapshot)" == "${before}" ]] || fail '重复 Peer 改变已有输入'
MODE=apply-fail
run_case "${PADM_DOCKER_RC_COMPOSE}" start --yes
[[ "$(snapshot)" == "${before}" ]] || fail '首次启用失败覆盖了已有规格或密钥'
MODE=ok
run_case 0 start --yes
run_case 0 status
jq -e '.configured == true and .enabled == true' "${LOG}" >/dev/null
before=$(snapshot)
run_case "${PADM_DOCKER_RC_CONFLICT}" prepare --address 10.90.0.1 --listen-port 51820 --yes
run_case "${PADM_DOCKER_RC_CONFLICT}" peer --peer-address 10.90.0.2 --peer-public-key "${PEER}" --yes
[[ "$(snapshot)" == "${before}" ]] || fail '启用后重复准备或 Peer 改变已有输入'

# 命令保持在线输入不动，完整私密候选只能作为原配置事务的第十个参数提交。
CURRENT_PUBLIC=${PUBLIC}
EXPECT_ROLE_ADDRESS=0
EXPECT_PEER_CHANGE=0
dockerWireGuardContainer() {
    [[ "$#" == 1 && "$1" == running && "${MODE}" != owner-fail ]] || return 1
    printf '%064d\n' 1
}
dockerConfigureApply() {
    local candidate=${10}
    [[ "$#" == 10 && "$2$3$4$5$6$7$8$9" == configure &&
        "${candidate}" == "${root}/.wireguard."*/wireguard &&
        "$(snapshot)" == "${before}" &&
        "${DOCKER_CONTROL_TRANSACTION:-0}" == 0 &&
        "${DOCKER_CONTROL_SYNC_TRANSACTION:-0}" == 0 ]] ||
        fail '迁移未通过原事务、提前改写在线输入或自行绕过角色门禁'
    if [[ "${EXPECT_ROLE_ADDRESS}" == 1 ]]; then
        [[ "$1" == "${candidate%/wireguard}/spec.json" &&
            "$(stat -c '%u:%g:%a:%h' "$1")" == 0:0:600:1 ]] ||
            fail '角色地址候选没有使用同一私密暂存中的受限规格'
        jq -en --arg address "${EXPECTED_ADDRESS}" --arg peer "${EXPECTED_PEER_ADDRESS}" \
            --slurpfile current "${root}/config/spec.json" --slurpfile next "$1" '
          $current[0] as $c | $next[0] as $n |
          if $c.control.role == "main" then
            ($c | del(.control.listen.address,.control.peer.address,
              .control.peer.enabled,.control.peer.expires_at)) ==
            ($n | del(.control.listen.address,.control.peer.address,
              .control.peer.enabled,.control.peer.expires_at)) and
            $n.control.listen.address == $address and $n.control.peer.address == $peer and
            $n.control.peer.enabled == false and $n.control.peer.expires_at == 1
          else
            ($c | del(.control_sync.connection.peer_address,.control_sync.connection.listen.address)) ==
            ($n | del(.control_sync.connection.peer_address,.control_sync.connection.listen.address)) and
            $n.control_sync.connection.peer_address == $address and
            $n.control_sync.connection.listen.address == $peer
          end' >/dev/null || fail '角色地址映射、主控撤权或其余字段保持不正确'
        dockerConfigureSpecValidate "$1" || fail '角色迁移候选规格无效'
    else
        [[ "$1" == "${root}/config/spec.json" && ! -e "${candidate%/wireguard}/spec.json" ]] ||
            fail '非角色地址迁移没有沿用原规格路径'
    fi
    python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" status --directory "${candidate}" >/dev/null ||
        fail '迁移没有完整私密候选'
    if [[ "${EXPECT_PEER_CHANGE}" == 1 ]]; then
        for file in identity.json private.key; do
            cmp -s -- "${root}/secrets/net/wireguard/${file}" "${candidate}/${file}" ||
                fail 'Peer 变更改变了本机身份或密钥'
        done
    fi
    printf 'migrate-apply\n' >>"${CALLS}"
    [[ "${MODE}" != apply-fail ]] || return "${PADM_DOCKER_RC_COMPOSE}"
    [[ "${MODE}" != int ]] || { kill -INT "${BASHPID}"; return 1; }
    [[ "${MODE}" != term ]] || { kill -TERM "${BASHPID}"; return 1; }
    cp -- "${candidate}/"{identity.json,private.key,wg-padm.conf} "${root}/secrets/net/wireguard/"
    if [[ "$1" != "${root}/config/spec.json" ]]; then
        cp -- "$1" "${root}/config/spec.json"
        chmod 0600 "${root}/config/spec.json"
    fi
}
run_case "${PADM_DOCKER_RC_USAGE}" migrate --rotate-key --rotate-key --yes
run_case "${PADM_DOCKER_RC_USAGE}" migrate --address 10.91.0.1 --address 10.91.0.2 --yes
run_case "${PADM_DOCKER_RC_USAGE}" migrate --listener entry-xray --yes
for MODE in owner-fail pair-fail apply-fail int term; do
    expected=${PADM_DOCKER_RC_STATE}
    [[ "${MODE}" != apply-fail ]] || expected=${PADM_DOCKER_RC_COMPOSE}
    [[ "${MODE}" != int ]] || expected=130
    [[ "${MODE}" != term ]] || expected=143
    run_case "${expected}" migrate --endpoint none --yes
    [[ "$(snapshot)" == "${before}" ]] || fail "${MODE}: 迁移失败改变了在线输入"
done
MODE=ok
: >"${CALLS}"
run_case 0 migrate --yes
! grep -qF migrate-apply "${CALLS}" || fail '同配置迁移仍提交事务'
run_case 0 migrate --address 10.91.0.1 --listen-port 51821 --peer-address 10.91.0.2 \
    --endpoint none --yes
grep -qFx 'Address = 10.91.0.1/32' "${root}/secrets/net/wireguard/wg-padm.conf" &&
    grep -qFx 'AllowedIPs = 10.91.0.2/32' "${root}/secrets/net/wireguard/wg-padm.conf" &&
    ! grep -q Endpoint "${root}/secrets/net/wireguard/wg-padm.conf" ||
    fail '迁移未更新选定字段'
before=$(snapshot)
PRIVATE=$(printf '%032d' 4 | base64 -w0)
PUBLIC=$(printf '%032d' 5 | base64 -w0)
run_case 0 migrate --rotate-key --yes
[[ "$(<"${root}/secrets/net/wireguard/private.key")" == "${PRIVATE}" ]] ||
    fail '迁移未采用新密钥'
CURRENT_PUBLIC=${PUBLIC}

# 集合变更按地址选择，沿用同一事务，并在多项时拒绝旧迁移的隐式选择。
before=$(snapshot)
EXPECT_PEER_CHANGE=1
SECOND_PEER=$(printf '%032d' 6 | base64 -w0)
UPDATED_PEER=$(printf '%032d' 7 | base64 -w0)
run_case 0 peers
jq -e '.address == "10.91.0.1" and (.peers | length) == 1 and
    .peers[0].address == "10.91.0.2"' "${LOG}" >/dev/null
for address in 10.91.0.1 10.91.0.2; do
    run_case "${PADM_DOCKER_RC_STATE}" peers add --peer-address "${address}" \
        --peer-public-key "${SECOND_PEER}" --yes
done
run_case "${PADM_DOCKER_RC_STATE}" peers add --peer-address 10.91.0.3 \
    --peer-public-key "${PEER}" --yes
run_case "${PADM_DOCKER_RC_STATE}" peers add --peer-address 10.91.0.3 \
    --peer-public-key "${SECOND_PEER}" --endpoint 127.0.0.1:51821 --yes
run_case "${PADM_DOCKER_RC_STATE}" peers update --peer-address 10.91.0.4 --endpoint none --yes
[[ "$(snapshot)" == "${before}" ]] || fail '非法 Peer 变更改变了在线输入'
for MODE in owner-fail pair-fail apply-fail int term; do
    expected=${PADM_DOCKER_RC_STATE}
    [[ "${MODE}" != apply-fail ]] || expected=${PADM_DOCKER_RC_COMPOSE}
    [[ "${MODE}" != int ]] || expected=130
    [[ "${MODE}" != term ]] || expected=143
    run_case "${expected}" peers add --peer-address 10.91.0.3 \
        --peer-public-key "${SECOND_PEER}" --yes
    [[ "$(snapshot)" == "${before}" ]] || fail "${MODE}: Peer 变更失败改变了在线输入"
done
MODE=ok
run_case 0 peers add --peer-address 10.91.0.3 --peer-public-key "${SECOND_PEER}" \
    --endpoint 198.18.0.3:51821 --yes
before=$(snapshot)
run_case 0 peers list
jq -e '.peers | map(.address) == ["10.91.0.2","10.91.0.3"]' "${LOG}" >/dev/null
run_case "${PADM_DOCKER_RC_CONFLICT}" migrate --rotate-key --yes
run_case "${PADM_DOCKER_RC_STATE}" peers remove --peer-address 10.91.0.4 --yes
run_case "${PADM_DOCKER_RC_STATE}" peers update --peer-address 10.91.0.3 \
    --peer-public-key "${PEER}" --yes
[[ "$(snapshot)" == "${before}" ]] || fail '多 Peer 拒绝路径改变了在线输入'
run_case 0 peers update --peer-address 10.91.0.3 --peer-public-key "${UPDATED_PEER}" \
    --endpoint 198.18.0.3:51822 --yes
before=$(snapshot)
run_case 0 peers update --peer-address 10.91.0.3 --endpoint none --yes
before=$(snapshot)
: >"${CALLS}"
run_case 0 peers update --peer-address 10.91.0.3 --endpoint none --yes
! grep -qF migrate-apply "${CALLS}" || fail '同配置 Peer 更新仍提交事务'
run_case 0 peers list
jq -e --arg first "${PEER}" --arg second "${UPDATED_PEER}" '
    .peers == [{address:"10.91.0.2",public_key:$first,endpoint:null},
               {address:"10.91.0.3",public_key:$second,endpoint:null}]' "${LOG}" >/dev/null
[[ "$(snapshot)" == "${before}" ]] || fail '列表或幂等更新改变了在线输入'
run_case 0 peers remove --peer-address 10.91.0.2 --yes
before=$(snapshot)
run_case 0 peers list
jq -e --arg key "${UPDATED_PEER}" '.peers ==
    [{address:"10.91.0.3",public_key:$key,endpoint:null}]' "${LOG}" >/dev/null
run_case "${PADM_DOCKER_RC_CONFLICT}" peers remove --peer-address 10.91.0.3 --yes
grep -qF '不能移除最后一个 Peer' "${LOG}" || fail '最后一项拒绝没有清晰提示'
[[ "$(snapshot)" == "${before}" ]] || fail '移除最后一项改变了在线输入'
EXPECT_PEER_CHANGE=0

# 真实角色规格覆盖地址映射及仅允许的字段变化，失败时在线规格和隧道均保持原样。
cp -- "${root}/config/spec.json" "${TEST_ROOT}/standalone.json"
for role in main controlled; do
    addresses=$(python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" addresses \
        --directory "${root}/secrets/net/wireguard")
    jq --arg role "${role}" --argjson addresses "${addresses}" '
      def account($number):
        {id:("0000000" + $number + "-1111-4111-8111-00000000000" + $number),
         name:("账号" + $number),enabled:true,
         uuid:("0000010" + $number + "-1111-4111-8111-00000000010" + $number),
         password:("MigrationPassword.000" + $number),shadowsocks_password:null,
         listeners:["entry-main"]};
      .accounts = [account("3"),account("4")] |
      if $role == "main" then
        .control = {schema_version:1,role:"main",
          node_id:"00000001-1111-4111-8111-000000000001",
          listen:{interface:"wg-padm",address:$addresses.address,port:18080},
          peer:{id:"00000002-1111-4111-8111-000000000002",address:$addresses.peer_address,
            enabled:true,expires_at:2000000000,token_sha256:("a"*64)},
          revision:7,last_digest:("d"*64)}
      else
        .control_sync = {schema_version:1,role:"controlled",
          node_id:"00000002-1111-4111-8111-000000000002",
          controller_id:"00000001-1111-4111-8111-000000000001",
          listener_ids:["entry-main"],last_revision:7,last_digest:("d"*64),
          managed_accounts:[.accounts[1]],
          connection:{listen:{interface:"wg-padm",address:$addresses.peer_address,port:18080},
            peer_address:$addresses.address}}
      end' "${TEST_ROOT}/standalone.json" >"${root}/config/spec.json"
    chmod 0600 "${root}/config/spec.json"
    dockerConfigureSpecValidate "${root}/config/spec.json" || fail "${role}: 角色夹具无效"
    cp -- "${root}/config/spec.json" "${TEST_ROOT}/role.json"
    address=$(jq -r '.address' <<<"${addresses}")
    peerAddress=$(jq -r '.peer_address' <<<"${addresses}")
    before=$(snapshot)
    : >"${CALLS}"
    run_case 0 peers list
    run_case "${PADM_DOCKER_RC_CONFLICT}" peers add --peer-address 10.91.0.4 \
        --peer-public-key "${SECOND_PEER}" --yes
    run_case "${PADM_DOCKER_RC_CONFLICT}" peers update --peer-address "${peerAddress}" \
        --endpoint none --yes
    run_case "${PADM_DOCKER_RC_CONFLICT}" peers remove --peer-address "${peerAddress}" --yes
    [[ "$(snapshot)" == "${before}" ]] || fail "${role}: Peer 集合拒绝改变了在线输入"
    run_case 0 migrate --address "${address}" --peer-address "${peerAddress}" --yes
    ! grep -qF migrate-apply "${CALLS}" || fail "${role}: 同地址幂等仍提交事务"
    port=51822
    [[ "${role}" != controlled ]] || port=51823
    run_case 0 migrate --listen-port "${port}" --yes
    [[ "$(jq -S . "${root}/config/spec.json")" == "$(jq -S . "${TEST_ROOT}/role.json")" ]] ||
        fail "${role}: 仅修改 WireGuard 端口改变了角色规格"
    before=$(snapshot)
    run_case "${PADM_DOCKER_RC_STATE}" migrate --address 198.18.0.1 --yes
    run_case "${PADM_DOCKER_RC_STATE}" migrate --peer-address 127.0.0.1 --yes
    run_case "${PADM_DOCKER_RC_STATE}" migrate --address "${peerAddress}" --yes
    run_case "${PADM_DOCKER_RC_STATE}" migrate --peer-address "${address}" --yes
    [[ "$(snapshot)" == "${before}" ]] || fail "${role}: 非法地址改变在线输入"
    jq 'if has("control") then .control.listen.address = "10.254.0.1"
        else .control_sync.connection.peer_address = "10.254.0.1" end' \
        "${TEST_ROOT}/role.json" >"${root}/config/spec.json"
    chmod 0600 "${root}/config/spec.json"
    before=$(snapshot)
    run_case "${PADM_DOCKER_RC_CONFLICT}" migrate --address 10.254.0.2 --yes
    [[ "$(snapshot)" == "${before}" ]] || fail "${role}: 旧 tuple 漂移仍改写在线输入"
    cp -- "${TEST_ROOT}/role.json" "${root}/config/spec.json"
    before=$(snapshot)
    EXPECT_ROLE_ADDRESS=1
    EXPECTED_ADDRESS=10.92.0.1
    EXPECTED_PEER_ADDRESS=10.92.0.2
    [[ "${role}" != controlled ]] || {
        EXPECTED_ADDRESS=10.93.0.1
        EXPECTED_PEER_ADDRESS=10.93.0.2
    }
    for MODE in apply-fail int term; do
        expected=${PADM_DOCKER_RC_COMPOSE}
        [[ "${MODE}" != int ]] || expected=130
        [[ "${MODE}" != term ]] || expected=143
        run_case "${expected}" migrate --address "${EXPECTED_ADDRESS}" \
            --peer-address "${EXPECTED_PEER_ADDRESS}" --yes
        [[ "$(snapshot)" == "${before}" ]] || fail "${role}/${MODE}: 迁移失败改变在线输入"
    done
    MODE=ok
    run_case 0 migrate --address "${EXPECTED_ADDRESS}" --peer-address "${EXPECTED_PEER_ADDRESS}" --yes
    grep -q '重新签发邀请' "${LOG}" || fail "${role}: 地址改变未提醒重新邀请和来源核验"
    before=$(snapshot)
    EXPECTED_ADDRESS=10.94.0.1
    [[ "${role}" != controlled ]] || EXPECTED_ADDRESS=10.95.0.1
    run_case 0 migrate --address "${EXPECTED_ADDRESS}" --yes
    before=$(snapshot)
    EXPECTED_PEER_ADDRESS=10.94.0.2
    [[ "${role}" != controlled ]] || EXPECTED_PEER_ADDRESS=10.95.0.2
    run_case 0 migrate --peer-address "${EXPECTED_PEER_ADDRESS}" --yes
    EXPECT_ROLE_ADDRESS=0
done

# 不完整角色规格仍在准备、设置 Peer 和迁移前拒绝。
for role in control control_sync; do
    jq --arg role "${role}" '. + {($role):{role:"fixture"}}' "${TEST_ROOT}/base.json" \
        >"${root}/config/spec.json"
    chmod 0600 "${root}/config/spec.json"
    before=$(snapshot)
    (
        dockerAccountSpecFile() { printf '%s\n' "${root}/config/spec.json"; }
        run_case "${PADM_DOCKER_RC_CONFLICT}" prepare --address 10.90.0.1 --listen-port 51820 --yes
        run_case "${PADM_DOCKER_RC_CONFLICT}" peer --peer-address 10.90.0.2 --peer-public-key "${PEER}" --yes
        run_case "${PADM_DOCKER_RC_CONFLICT}" migrate --rotate-key --yes
    )
    CASES=$((CASES + 3))
    [[ "$(snapshot)" == "${before}" ]] || fail "${role}: 拒绝时改变了已有输入"
done
printf 'wireguard-cli-ok: %s cases\n' "${CASES}"
