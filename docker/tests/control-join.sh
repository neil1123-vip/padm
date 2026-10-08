#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-control-join.XXXXXX")
INVITE_ROOT=$(mktemp -d /root/.padm-control-join-test.XXXXXX)
trap 'rm -rf -- "${TEST_ROOT}" "${INVITE_ROOT}"' EXIT
trap 'printf "docker-control-join-fail: line %s, rc=%s, callers=%s\n" "${LINENO}" "$?" "${BASH_LINENO[*]}" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
export PYTHONDONTWRITEBYTECODE=1
root=${PADM_DOCKER_INSTALL_DIR}
spec="${root}/config/spec.json"
invite="${INVITE_ROOT}/invite.json"
mkdir -p "${root}/config" "${root}/backups" "${root}/secrets/net/wireguard" "${root}/.bundles"
chmod 0700 "${root}" "${INVITE_ROOT}"

# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
fail() { printf 'docker-control-join-fail: %s\n' "$*" >&2; exit 1; }
reject() {
    local status=0
    "$@" >"${TEST_ROOT}/rejected.log" 2>&1 || status=$?
    [[ "${status}" -ne 0 ]] || fail "应拒绝: $*"
}
check_clean() {
    [[ -z "$(find "${root}" -maxdepth 1 \( -name '.control-client.*' -o \
        -name '.control-join.*' -o -name '.control-sync.*' -o -name '.candidate.*' \) -print -quit)" ]]
}
up_count() { grep -c '^up ' "${TEST_ROOT}/compose.log" || true; }

jq -n '{
  schema_version:3,
  release:{version:"3.1.8",manifest_sha256:("1"*64),signature_identity:"fixture"},
  core:{type:"xray",secondary_type:null,protocols:[{
    id:1,core:"xray",server:"reality.example.com",public_port:443,
    address_families:["ipv4"],listener_id:"entry-reality",name:"main",
    uuid:"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    reality:{server_name:"reality.example.com",target_host:"reality.example.com",
      target_port:443,private_key:("A"*43),public_key:("B"*43),short_id:"1234abcd"}
  }]},
  tls:null,subscription:{enabled:false,token:"join-subscription-secret"},
  images:(["xray","sing-box","nginx","ops","net"] |
    map({key:.,value:("ghcr.io/example/padm-" + . + ":test@sha256:" + ("1"*64))}) | from_entries),
  host_integrations:[{type:"wireguard",profile:"net-wireguard",firewall_rules:[],
    devices:["wg-padm"],schedules:[],settings:{config_file:"wg-padm.conf",interface:"wg-padm"}}],
  accounts:[{id:"11111111-1111-4111-8111-111111111111",name:"本机账号",enabled:true,
    uuid:"22222222-2222-4222-8222-222222222222",password:"Local.-~@+=:Secret",
    shadowsocks_password:null,listeners:["entry-reality"]}]
}' >"${spec}"
chmod 0600 "${spec}"
cp -- "${spec}" "${TEST_ROOT}/standalone.json"
jq -n --argjson expires "$(( $(date +%s) + 3600 ))" '{
  format:"padm-docker-control-invite",schema_version:1,
  controller_id:"33333333-3333-4333-8333-333333333333",
  node_id:"44444444-4444-4444-8444-444444444444",
  listen:{interface:"wg-padm",address:"10.77.0.1",port:18443},
  peer_address:"10.77.0.2",token:("c"*48),expires_at:$expires
}' >"${invite}"
chmod 0600 "${invite}"
cp -- "${invite}" "${TEST_ROOT}/server-invite.json"
jq -n '{
  ok:true,api_version:1,controller_id:"33333333-3333-4333-8333-333333333333",
  node_id:"44444444-4444-4444-8444-444444444444",revision:7,
  accounts:[{id:"55555555-5555-4555-8555-555555555555",name:"主控账号",enabled:true,
    uuid:"66666666-6666-4666-8666-666666666666",password:"Remote.-~@+=:Secret",
    shadowsocks_password:null}]
}' >"${TEST_ROOT}/desired.json"
chmod 0600 "${TEST_ROOT}/server-invite.json" "${TEST_ROOT}/desired.json"
printf '[Interface]\nPrivateKey = %s\nListenPort = 51820\nAddress = 10.77.0.2/32\n[Peer]\nPublicKey = %s\nAllowedIPs = 10.77.0.1/32\n' \
    "$(printf A%.0s {1..43})=" "$(printf B%.0s {1..43})=" >"${root}/secrets/net/wireguard/wg-padm.conf"
chmod 0600 "${root}/secrets/net/wireguard/wg-padm.conf"
export CONTROL_WG_CONFIG="${root}/secrets/net/wireguard/wg-padm.conf"
export CONTROL_TEST_ROOT="${TEST_ROOT}"
export CONTROL_PEER_KEY="$(printf B%.0s {1..43})="
wg-quick() { [[ "$1" == strip ]] && cat -- "${CONTROL_WG_CONFIG}"; }
wg() {
    [[ "$*" == 'show wg-padm allowed-ips' ]] || return 1
    if [[ -f "${CONTROL_TEST_ROOT}/bad-peer" ]]; then
        printf '%s\t10.77.0.2/32\n' "${CONTROL_PEER_KEY}"
    else
        printf '%s\t10.77.0.1/32\n' "${CONTROL_PEER_KEY}"
    fi
}
ip() {
    [[ "$*" == '-4 route get 10.77.0.1 from 10.77.0.2' ]] || return 1
    if [[ -f "${CONTROL_TEST_ROOT}/bad-route" ]]; then
        printf '10.77.0.1 from 10.77.0.2 dev eth0\n'
    elif [[ -f "${CONTROL_TEST_ROOT}/bad-source" ]]; then
        printf '10.77.0.1 from 10.77.0.9 dev wg-padm\n'
    else
        printf '10.77.0.1 from 10.77.0.2 dev wg-padm\n'
    fi
}
export -f wg wg-quick ip

# 网络使用桩；私有文件、生产客户端规划器和配置候选/备份/恢复均实际执行。
dockerHostPreflight() { printf 'host\n' >>"${TEST_ROOT}/host.log"; }
dockerLockInstalledDeployment() { printf 'lock\n' >>"${TEST_ROOT}/host.log"; }
dockerReleaseDeploymentLock() { printf 'unlock\n' >>"${TEST_ROOT}/host.log"; }
dockerRequireInstalledBundle() { :; }
dockerConfigureReleaseReuseInstalled() { :; }
dockerConfigureReleaseValidate() { :; }
dockerManifestImageReference() {
    jq -er --arg image "$1" '.images[$image]' "${spec}"
}
dockerManagedSpecMatchesDeployment() { [[ ! -f "${TEST_ROOT}/bad-deployment" ]]; }
dockerCurrentOwnsHostIntegration() { [[ "$1" == wireguard && ! -f "${TEST_ROOT}/unowned" ]]; }
dockerRealityTargetsValidate() { :; }
dockerConfigurePortsAvailable() { :; }
dockerValidateHostIntegrations() { :; }
dockerTrafficRuntimeCheck() { :; }
dockerTrafficBeforeChange() { printf 'sample\n' >>"${TEST_ROOT}/traffic.log"; }
dockerTrafficScheduleInstall() { :; }
dockerRenewalScheduleInstall() { :; }
dockerGeoScheduleInstall() { :; }
dockerComposeRun() {
    printf '%s\n' "$*" >>"${TEST_ROOT}/compose.log"
    if [[ "$1" == exec ]]; then
        [[ "${DOCKER_COMPOSE_TIMEOUT:-}" == 10 && "$2" == -T && "$3" == net-wireguard ]] || return 1
        if [[ "$4" == /usr/local/bin/padm-entrypoint ]]; then
            [[ "$*" == 'exec -T net-wireguard /usr/local/bin/padm-entrypoint wireguard-health wg-padm' &&
                ! -f "${TEST_ROOT}/bad-health" ]]
        else
            shift 3
            "$@"
        fi
        return $?
    fi
    if [[ "$1" == up && -f "${TEST_ROOT}/interrupt-up" ]]; then
        local signal
        signal=$(<"${TEST_ROOT}/interrupt-up")
        rm -- "${TEST_ROOT}/interrupt-up"
        kill -s "${signal}" "${BASHPID}"
    fi
    if [[ "$1" == up && -f "${TEST_ROOT}/fail-up" ]]; then
        rm -- "${TEST_ROOT}/fail-up"
        return 1
    fi
}
docker() { :; }
dockerRealityProbeRun() {
    local previous= directory= argument
    local -a listeners=()
    [[ " $* " == *' --network host '* && " $* " == *' --user 0:0 '* &&
        " $* " == *' --log-driver none '* && " $* " == *' /opt/padm/control_client.py '* ]] || return 1
    for argument in "$@"; do
        if [[ "${previous}" == --mount ]]; then
            directory=${argument#type=bind,src=}
            directory=${directory%,dst=/input,readonly}
        elif [[ "${previous}" == --listener ]]; then
            listeners+=("${argument}")
        fi
        previous=${argument}
    done
    [[ -n "${directory}" && "$(stat -c '%a:%u' "${directory}")" == 700:0 &&
        "$(stat -c '%a:%u' "${directory}/spec.json")" == 600:0 &&
        "$(stat -c '%a:%u' "${directory}/invite.json")" == 600:0 ]] || return 1
    printf 'client\n' >>"${TEST_ROOT}/client.log"
    if [[ -f "${TEST_ROOT}/interrupt-client" ]]; then
        kill -s "$(<"${TEST_ROOT}/interrupt-client")" "${BASHPID}"
    fi
    python3 - "${PROJECT_ROOT}" "${TEST_ROOT}" "${directory}" "${listeners[@]}" <<'PY'
import json
import sys
from pathlib import Path

project, test, directory = map(Path, sys.argv[1:4])
sys.path.insert(0, str(project / "docker/images/ops"))
import control_client as client

def address(state):
    if state["listen"]["address"] != "10.77.0.2" or (test / "bad-address").exists():
        raise ValueError("本机 WireGuard 地址不匹配")

def desired(invitation):
    address({"listen": {"address": invitation["peer_address"]}})
    current = json.loads((test / "server-invite.json").read_text())
    if invitation["token"] != current["token"] or (test / "fail-client").exists():
        raise ValueError("私网请求失败")
    return json.loads((test / "desired.json").read_text())

client.require_wireguard_address = address
client.fetch_desired = desired
listeners = sys.argv[4:]
sys.argv = ["control_client.py", "--spec", str(directory / "spec.json"),
            "--invite", str(directory / "invite.json")]
for listener in listeners:
    sys.argv.extend(("--listener", listener))
client.main()
PY
}

dockerInstallBundle "${PROJECT_ROOT}" "$(printf a%.0s {1..40})"
dockerConfigureApply "${TEST_ROOT}/standalone.json" >/dev/null
mkdir -p "${root}/data/traffic"
printf '{"schema_version":1,"accounts":{"11111111-1111-4111-8111-111111111111":{"name":"本机账号","upload":12,"download":34,"limit_bytes":100,"baseline":{}}}}\n' \
    >"${root}/data/traffic/state.json"
chmod 0600 "${root}/data/traffic/state.json"
traffic=$(sha256sum "${root}/data/traffic/state.json")
original=$(sha256sum "${spec}")
args=(--invite "${invite}" --listener entry-reality --yes)
rm -f -- "${TEST_ROOT}/host.log"

reject dockerControlCommand join
reject dockerControlCommand join --invite "${invite}" --yes
reject dockerControlCommand join --listener entry-reality --yes
reject dockerControlCommand join "${args[@]}" --invite "${invite}"
reject dockerControlCommand join "${args[@]}" --yes
reject dockerControlCommand join "${args[@]}" --unknown
reject dockerControlCommand join --invite "${invite}" --listener
reject dockerControlCommand join --invite "${invite}" --listener entry-reality
reject dockerControlCommand sync
reject dockerControlCommand sync --invite "${invite}" --yes
reject dockerControlCommand sync --invite "${invite}" --listener entry-reality
reject dockerControlCommand sync --invite "${invite}" --invite "${invite}"
[[ ! -f "${TEST_ROOT}/host.log" ]] || fail '参数错误触及宿主'

for bad in relative.json "${root}/inside.json" "${INVITE_ROOT}/missing.json" "${INVITE_ROOT}//invite.json"; do
    reject dockerControlCommand join --invite "${bad}" --listener entry-reality --yes
done
cp -- "${invite}" "${root}/inside.json"
chmod 0600 "${root}/inside.json"
reject dockerControlCommand join --invite "${root}/inside.json" --listener entry-reality --yes
rm -- "${root}/inside.json"
for mode in 0640 0660 0700; do
    chmod "${mode}" "${invite}"
    reject dockerControlCommand join "${args[@]}"
done
chmod 0600 "${invite}"
chmod 0770 "${INVITE_ROOT}"
reject dockerControlCommand join "${args[@]}"
chmod 0700 "${INVITE_ROOT}"
ln -s "${invite}" "${INVITE_ROOT}/link.json"
reject dockerControlCommand join --invite "${INVITE_ROOT}/link.json" --listener entry-reality --yes
rm -- "${INVITE_ROOT}/link.json"
truncate -s 1048577 "${INVITE_ROOT}/large.json"
chmod 0600 "${INVITE_ROOT}/large.json"
reject dockerControlCommand join --invite "${INVITE_ROOT}/large.json" --listener entry-reality --yes
chown 10001:10001 "${invite}"
reject dockerControlCommand join "${args[@]}"
chown 0:0 "${invite}"
for directory in "${root}" "${root}/config"; do
    mode=$(stat -c '%a' "${directory}")
    chmod 0770 "${directory}"
    reject dockerControlCommand join "${args[@]}"
    chmod "${mode}" "${directory}"
done
reject dockerControlCommand join --invite "${invite}" --listener entry-missing --yes
reject dockerControlCommand sync --invite "${invite}"
for marker in bad-deployment unowned bad-health bad-peer bad-route bad-source bad-address fail-client; do
    touch "${TEST_ROOT}/${marker}"
    reject dockerControlCommand join "${args[@]}"
    rm -- "${TEST_ROOT}/${marker}"
    [[ "$(sha256sum "${spec}")" == "${original}" &&
        "$(sha256sum "${root}/data/traffic/state.json")" == "${traffic}" ]]
    check_clean
done
[[ "$(tail -n 1 "${TEST_ROOT}/host.log")" == unlock ]]
touch "${TEST_ROOT}/fail-up"
reject dockerControlCommand join "${args[@]}"
[[ "$(sha256sum "${spec}")" == "${original}" &&
    "$(sha256sum "${root}/data/traffic/state.json")" == "${traffic}" ]]
check_clean

dockerControlCommand join "${args[@]}" --listener entry-reality >"${TEST_ROOT}/join.log"
jq -e '.control_sync.role == "controlled" and .control_sync.last_revision == 7 and
  .control_sync.listener_ids == ["entry-reality"] and
  .control_sync.connection == {
    listen:{interface:"wg-padm",address:"10.77.0.1",port:18443},peer_address:"10.77.0.2"} and
  (.accounts | length) == 2 and
  .accounts[0].id == "11111111-1111-4111-8111-111111111111"' "${spec}" >/dev/null
[[ "$(stat -c '%a:%u:%g' "${spec}")" == 600:0:0 &&
    "$(sha256sum "${root}/data/traffic/state.json")" == "${traffic}" ]]
for file in "${spec}" "${TEST_ROOT}/join.log"; do
    ! grep -Fq "$(printf c%.0s {1..48})" "${file}" || fail '邀请 token 写入规格或日志'
done
before=$(sha256sum "${spec}")
dockerBackupConfiguration update
oldUpdate=${DOCKER_CONFIG_BACKUP}
upBefore=$(up_count)
reject dockerControlCommand join "${args[@]}"
dockerControlCommand sync --invite "${invite}" >"${TEST_ROOT}/sync.log"
[[ "$(up_count)" == "${upBefore}" && "$(sha256sum "${spec}")" == "${before}" ]]
cp -- "${invite}" "${INVITE_ROOT}/old.json"
jq '.token = ("d"*48)' "${invite}" >"${INVITE_ROOT}/next.json"
mv -- "${INVITE_ROOT}/next.json" "${invite}"
chmod 0600 "${invite}" "${INVITE_ROOT}/old.json"
cp -- "${invite}" "${TEST_ROOT}/server-invite.json"
reject dockerControlCommand sync --invite "${INVITE_ROOT}/old.json"
dockerControlCommand sync --invite "${invite}" >/dev/null
[[ "$(up_count)" == "${upBefore}" && "$(sha256sum "${spec}")" == "${before}" ]]

for mutation in '.controller_id = "77777777-7777-4777-8777-777777777777"' \
    '.node_id = "77777777-7777-4777-8777-777777777777"' \
    '.listen.address = "10.77.0.3"' '.listen.port = 19443' '.peer_address = "10.77.0.4"'; do
    jq "${mutation}" "${invite}" >"${INVITE_ROOT}/changed.json"
    chmod 0600 "${INVITE_ROOT}/changed.json"
    reject dockerControlCommand sync --invite "${INVITE_ROOT}/changed.json"
    [[ "$(sha256sum "${spec}")" == "${before}" ]]
done
jq '.control_sync.connection.listen.port = 19443' "${spec}" >"${TEST_ROOT}/edited.json"
reject dockerControlSyncTransitionValidate "${TEST_ROOT}/edited.json"
reject dockerConfigureApply "${TEST_ROOT}/edited.json"
reject dockerAccountCommand disable 55555555-5555-4555-8555-555555555555
mkdir -p "${TEST_ROOT}/old-bundle/docker/contracts"
cp -- "$(dockerFeatureMatrixFile)" "${TEST_ROOT}/old-bundle/docker/contracts/features.json"
for capability in x-padm-control-client x-padm-control-sync-rollback; do
    jq --arg capability "${capability}" 'del(.[$capability])' "$(dockerConfigureSchemaFile)" \
        >"${TEST_ROOT}/old-bundle/docker/contracts/configure.schema.json"
    reject dockerBundleSupportsSpec "${TEST_ROOT}/old-bundle" "${spec}"
done
dockerBundleSupportsSpec "${TEST_ROOT}/old-bundle" "${TEST_ROOT}/standalone.json"

jq '.revision = 8 | .accounts[0].name = "主控更新"' "${TEST_ROOT}/desired.json" >"${TEST_ROOT}/next-desired.json"
mv -- "${TEST_ROOT}/next-desired.json" "${TEST_ROOT}/desired.json"
touch "${TEST_ROOT}/fail-client"
reject dockerControlCommand sync --invite "${invite}"
rm -- "${TEST_ROOT}/fail-client"
touch "${TEST_ROOT}/fail-up"
reject dockerControlCommand sync --invite "${invite}"
[[ "$(sha256sum "${spec}")" == "${before}" &&
    "$(sha256sum "${root}/data/traffic/state.json")" == "${traffic}" ]]
for stage in client up; do
    for signal in INT TERM; do
        printf '%s\n' "${signal}" >"${TEST_ROOT}/interrupt-${stage}"
        status=0
        dockerControlCommand sync --invite "${invite}" >"${TEST_ROOT}/signal.log" 2>&1 || status=$?
        [[ "${signal}:${status}" == INT:130 || "${signal}:${status}" == TERM:143 ]] ||
            fail "信号退出码错误: ${stage}:${signal}:${status}"
        rm -f -- "${TEST_ROOT}/interrupt-${stage}"
        [[ "$(sha256sum "${spec}")" == "${before}" &&
            "$(sha256sum "${root}/data/traffic/state.json")" == "${traffic}" ]]
        [[ "$(tail -n 1 "${TEST_ROOT}/host.log")" == unlock ]]
        check_clean
    done
done
dockerControlCommand sync --invite "${invite}" >/dev/null
jq -e '.control_sync.last_revision == 8 and .accounts[0].name == "本机账号" and
  .accounts[1].name == "主控更新"' "${spec}" >/dev/null
[[ "$(sha256sum "${root}/data/traffic/state.json")" == "${traffic}" ]]
check_clean

# 显式回滚不能降低已提交同步版本；普通失败/信号恢复已在前面验证。
before=$(sha256sum "${spec}")
composeBefore=$(sha256sum "${TEST_ROOT}/compose.log")
sampleBefore=$(sha256sum "${TEST_ROOT}/traffic.log")
backupsBefore=$(find "${root}/backups" -mindepth 1 -maxdepth 1 -type d | sort)
reject dockerRollbackCommand
[[ "$(sha256sum "${spec}")" == "${before}" &&
    "$(sha256sum "${root}/data/traffic/state.json")" == "${traffic}" &&
    "$(sha256sum "${TEST_ROOT}/compose.log")" == "${composeBefore}" &&
    "$(sha256sum "${TEST_ROOT}/traffic.log")" == "${sampleBefore}" &&
    "$(find "${root}/backups" -mindepth 1 -maxdepth 1 -type d | sort)" == "${backupsBefore}" ]]

checkBackup="${root}/backups/control-check"
mkdir -p "${checkBackup}/config"
cp -- "${spec}" "${TEST_ROOT}/current.json"
for mutation in \
    '.control_sync.last_revision = 7' \
    '.control_sync.last_revision = null | .control_sync.last_digest = null |
        .control_sync.managed_accounts = []' \
    '.control_sync.last_digest = ("a"*64)' \
    '.control_sync.managed_accounts[0].name = "历史账号" |
        .accounts[1].name = "历史账号"' \
    '.control_sync.node_id = "77777777-7777-4777-8777-777777777777"' \
    '.control_sync.controller_id = "77777777-7777-4777-8777-777777777777"' \
    '.control_sync.connection.listen.port = 19443' \
    'del(.control_sync)'; do
    jq "${mutation}" "${TEST_ROOT}/current.json" >"${checkBackup}/config/spec.json"
    chmod 0600 "${checkBackup}/config/spec.json"
    reject dockerControlSyncRollbackCheck "${checkBackup}"
done
cp -- "${spec}" "${checkBackup}/config/spec.json"
dockerControlSyncRollbackCheck "${checkBackup}"
jq '.control_sync.last_revision = 9' "${spec}" >"${checkBackup}/config/spec.json"
dockerControlSyncRollbackCheck "${checkBackup}"
cp -- "${spec}" "${checkBackup}/config/spec.json"
chmod 0640 "${spec}"
reject dockerControlSyncRollbackCheck "${checkBackup}"
chmod 0600 "${spec}"
mv -- "${spec}" "${TEST_ROOT}/live.json"
reject dockerControlSyncRollbackCheck "${checkBackup}"
ln -s "${TEST_ROOT}/live.json" "${spec}"
reject dockerControlSyncRollbackCheck "${checkBackup}"
rm -- "${spec}"
printf '{\n' >"${spec}"
chmod 0600 "${spec}"
reject dockerControlSyncRollbackCheck "${checkBackup}"
cp -- "${TEST_ROOT}/live.json" "${spec}"
jq 'del(.control_sync)' "${spec}" >"${TEST_ROOT}/standalone-now.json"
cp -- "${TEST_ROOT}/standalone-now.json" "${spec}"
reject dockerControlSyncRollbackCheck "${checkBackup}"
cp -- "${TEST_ROOT}/live.json" "${spec}"
chmod 0600 "${spec}"
jq 'del(.control_sync.connection)' "${spec}" >"${checkBackup}/config/spec.json"
reject dockerControlSyncRollbackCheck "${checkBackup}"
cp -- "${spec}" "${checkBackup}/config/spec.json"
jq '.control_sync.listener_ids = ["entry-other"]' "${spec}" >"${checkBackup}/config/spec.json"
reject dockerControlSyncRollbackCheck "${checkBackup}"
cp -- "${spec}" "${checkBackup}/config/spec.json"

# 同步状态未变的发行版快照可回滚；执行失败仍恢复当前完整状态。
touch -d @1 "${oldUpdate}"
dockerBackupConfiguration update
upBefore=$(up_count)
touch "${TEST_ROOT}/fail-up"
reject dockerRollbackCommand
[[ "$(up_count)" -eq $((upBefore + 2)) && "$(sha256sum "${spec}")" == "${before}" &&
    "$(sha256sum "${root}/data/traffic/state.json")" == "${traffic}" ]]
dockerRollbackCommand >"${TEST_ROOT}/rollback.log"
[[ "$(sha256sum "${spec}")" == "${before}" &&
    "$(sha256sum "${root}/data/traffic/state.json")" == "${traffic}" ]]
check_clean
printf 'docker-control-join-regression-ok\n'
