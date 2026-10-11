#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${PROJECT_ROOT}/.tmp-control-sync-schedule.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-control-sync-schedule-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
export PYTHONDONTWRITEBYTECODE=1
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
export PADM_DOCKER_SYSTEMD_DIR="${TEST_ROOT}/systemd"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

fail() { printf 'docker-control-sync-schedule-fail: %s\n' "$*" >&2; exit 1; }
expectCode() {
    local expected=$1 status=0
    shift
    "$@" >"${TEST_ROOT}/result.log" 2>&1 || status=$?
    [[ "${status}" == "${expected}" ]] || fail "退出码 ${status} != ${expected}: $*"
}
reject() {
    local status=0
    "$@" >"${TEST_ROOT}/rejected.log" 2>&1 || status=$?
    [[ "${status}" -ne 0 ]] || fail "应拒绝: $*"
}
check_clean() {
    [[ -z "$(find "${root}/locks" -mindepth 1 -print -quit)" &&
        -z "$(find "${root}" -maxdepth 1 -name '.control-client.*' -print -quit)" ]]
}
root=${PADM_DOCKER_INSTALL_DIR}
dockerInitializeStateRoot
mkdir -p "${PADM_DOCKER_SYSTEMD_DIR}" "${PADM_DOCKER_BIN_DIR}" "${TEST_ROOT}/private"
chmod 0700 "${TEST_ROOT}" "${TEST_ROOT}/private"
spec="${root}/config/spec.json"
invite="${TEST_ROOT}/private/invite.json"
directory="${root}/secrets/control-sync"
service="${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-control-sync.service"
timer="${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-control-sync.timer"
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
  tls:null,subscription:{enabled:false,token:"sync-subscription-secret"},
  images:(["xray","sing-box","nginx","ops","net"] |
    map({key:.,value:("ghcr.io/example/padm-" + . + ":test@sha256:" + ("1"*64))}) | from_entries),
  host_integrations:[{type:"wireguard",profile:"net-wireguard",firewall_rules:[],
    devices:["wg-padm"],schedules:[],settings:{config_file:"wg-padm.conf",interface:"wg-padm"}}],
  accounts:[],
  control_sync:{schema_version:1,role:"controlled",
    controller_id:"33333333-3333-4333-8333-333333333333",
    node_id:"44444444-4444-4444-8444-444444444444",listener_ids:["entry-reality"],
    last_revision:null,last_digest:null,managed_accounts:[],
    connection:{listen:{interface:"wg-padm",address:"10.77.0.1",port:18443},peer_address:"10.77.0.2"}}
}' >"${spec}"
jq -n --argjson expires "$(( $(date +%s) + 3600 ))" '{
  format:"padm-docker-control-invite",schema_version:1,
  controller_id:"33333333-3333-4333-8333-333333333333",
  node_id:"44444444-4444-4444-8444-444444444444",
  listen:{interface:"wg-padm",address:"10.77.0.1",port:18443},
  peer_address:"10.77.0.2",token:("c"*48),expires_at:$expires
}' >"${invite}"
jq -n '{
  ok:true,api_version:1,controller_id:"33333333-3333-4333-8333-333333333333",
  node_id:"44444444-4444-4444-8444-444444444444",revision:7,
  accounts:[{id:"55555555-5555-4555-8555-555555555555",name:"主控账号",enabled:true,
    uuid:"66666666-6666-4666-8666-666666666666",password:"Remote.-~@+=:Secret",
    shadowsocks_password:null}]
}' >"${TEST_ROOT}/desired.json"
chmod 0600 "${spec}" "${invite}" "${TEST_ROOT}/desired.json"
cp -- "${invite}" "${TEST_ROOT}/server-invite.json"
cp -- "${spec}" "${TEST_ROOT}/initial.json"
printf '{"services":{"xray":{"profiles":["core-xray"],"healthcheck":{}},"net-wireguard":{"profiles":["net-wireguard"],"healthcheck":{}},"acme":{"profiles":["acme"]}}}\n' >"${root}/compose.json"
printf '{"compose":{"profiles":["core-xray","net-wireguard"]}}\n' >"${root}/deployment.json"
printf 'fixture\n' >"${root}/images.env"
printf '# unrelated job\n' >"${TEST_ROOT}/crontab"
for log in schedule client runtime apply; do : >"${TEST_ROOT}/${log}.log"; done

# 文件、安全边界、调度和客户端规划实际执行；宿主与 Compose 的既有合同由 join/real 覆盖。
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { :; }
dockerAccountSpecFile() {
    dockerControlSyncSpecValidate "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" || return 1
    printf '%s\n' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
}
dockerManagedSpecMatchesDeployment() { [[ ! -e "${TEST_ROOT}/deployment-drift" ]]; }
dockerControlStateCheck() { :; }
dockerControlRecoveryCheck() { [[ ! -e "${TEST_ROOT}/recovery-drift" ]]; }
dockerConfigureSpecMigrate() { cp -- "$1" "$2"; chmod 0600 "$2"; }
dockerConfigureSpecValidate() { dockerControlSyncSpecValidate "$1"; }
dockerConfigurationInterrupted() { :; }
dockerAccountImage() { printf 'fixture-ops\n'; }
dockerControlClientRuntimeCheck() {
    printf 'runtime\n' >>"${TEST_ROOT}/runtime.log"
    [[ ! -e "${TEST_ROOT}/network-down" ]] || return 10
}
dockerAccountApplyDraft() {
    [[ "${DOCKER_CONTROL_SYNC_TRANSACTION:-}" == 1 && -d "${root}/locks/deployment.lock" ]] || return 1
    printf 'apply\n' >>"${TEST_ROOT}/apply.log"
    [[ ! -e "${TEST_ROOT}/apply-failure" ]] || return 14
    cp -- "$1" "${spec}"
    chmod 0600 "${spec}"
}
dockerRealityProbeRun() {
    local previous= directory= argument
    [[ " $* " == *' --network host '* && " $* " == *' --user 0:0 '* &&
        " $* " == *' --log-driver none '* && " $* " == *' /opt/padm/control_client.py '* ]] || return 1
    for argument in "$@"; do
        if [[ "${previous}" == --mount ]]; then
            directory=${argument#type=bind,src=}
            directory=${directory%,dst=/input,readonly}
        fi
        previous=${argument}
    done
    [[ -n "${directory}" && "$(stat -c '%u:%a' "${directory}")" == 0:700 &&
        "$(stat -c '%u:%a' "${directory}/invite.json")" == 0:600 &&
        "$(stat -c '%u:%a' "${directory}/spec.json")" == 0:600 ]] || return 1
    printf 'client\n' >>"${TEST_ROOT}/client.log"
    python3 - "${PROJECT_ROOT}" "${TEST_ROOT}" "${directory}" <<'PY'
import json
import sys
from pathlib import Path

project, test, directory = map(Path, sys.argv[1:])
sys.path.insert(0, str(project / "docker/images/ops"))
import control_client as client

def desired(invitation):
    current = json.loads((test / "server-invite.json").read_text())
    if invitation["token"] != current["token"] or (test / "revoked").exists():
        raise ValueError("授权无效")
    return json.loads((test / "desired.json").read_text())

client.fetch_desired = desired
sys.argv = ["control_client.py", "--spec", str(directory / "spec.json"),
            "--invite", str(directory / "invite.json")]
client.main()
PY
}

BACKEND=systemd MODE=normal EXEC_OVERRIDE= DROPIN_OVERRIDE= STALE=no ENV_OVERRIDE= CONTAINERS=running
systemctl() {
    printf '%s\n' "$*" >>"${TEST_ROOT}/schedule.log"
    case "$1" in
    show-environment) [[ "${BACKEND}" == systemd ]]; return $? ;;
    show)
        case "$2" in
        --property=FragmentPath) [[ ! -f "${PADM_DOCKER_SYSTEMD_DIR}/${!#}" ]] ||
            printf '%s\n' "${PADM_DOCKER_SYSTEMD_DIR}/${!#}" ;;
        --property=DropInPaths) printf '%s\n' "${DROPIN_OVERRIDE}" ;;
        --property=NeedDaemonReload) printf '%s\n' "${STALE}" ;;
        --property=Environment) printf '%s\n' "${ENV_OVERRIDE:-PADM_DOCKER_INSTALL_DIR=${root}}" ;;
        --property=ExecStart)
            if [[ -n "${EXEC_OVERRIDE}" ]]; then printf '%s\n' "${EXEC_OVERRIDE}";
            else printf '{ path=%s ; argv[]=%s %s/padm-docker control auto-sync ; ignore_errors=no ; pid=0 ; }\n' \
                "$(command -v bash)" "$(command -v bash)" "${PADM_DOCKER_BIN_DIR}"; fi ;;
        *) return 1 ;;
        esac
        return 0 ;;
    is-enabled) [[ -e "${TEST_ROOT}/enabled" ]]; return $? ;;
    is-active) [[ -e "${TEST_ROOT}/active" ]]; return $? ;;
    esac
    if [[ ( "${MODE}" == failure && ( "$1" == enable || "$1" == disable ) ||
        "${MODE}" == enable-failure && "$1" == enable ) &&
        ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"; return 1
    fi
    case "$1" in
    enable) : >"${TEST_ROOT}/enabled"; [[ "$*" != *--now* ]] || : >"${TEST_ROOT}/active" ;;
    disable) rm -f "${TEST_ROOT}/enabled"; [[ "$*" != *--now* ]] || rm -f "${TEST_ROOT}/active" ;;
    start) : >"${TEST_ROOT}/active" ;;
    stop|daemon-reload) : ;;
    *) return 1 ;;
    esac
    if [[ "${MODE}" == signal && ( "$1" == enable || "$1" == disable ) &&
        ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"; kill -TERM "${BASHPID}"
    fi
}
crontab() {
    if [[ "$1" == -l ]]; then cat "${TEST_ROOT}/crontab"; return 0; fi
    [[ "$1" == - ]] || return 1
    if [[ "${MODE}" == failure && ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"; return 1
    fi
    cat >"${TEST_ROOT}/crontab"
    if [[ "${MODE}" == signal && ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"; kill -TERM "${BASHPID}"
    fi
}
pgrep() { [[ "${BACKEND}" == cron && "$*" == '-x cron' ]]; }
mv() {
    if [[ "${!#}" == "${directory}" && "${MODE}" == publish-failure &&
        ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"; return 1
    fi
    command mv "$@" || return $?
    if [[ "${!#}" == "${directory}" && "${MODE}" == publish-signal &&
        ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"; kill -TERM "${BASHPID}"
    fi
}
docker() {
    local first="$(printf a%.0s {1..64})" second="$(printf b%.0s {1..64})"
    case "$1" in
    ps)
        [[ "${CONTAINERS}" != down ]] || return 0
        printf '%s\n' "${first}"
        [[ "${CONTAINERS}" == half ]] || printf '%s\n' "${second}"
        ;;
    container)
        [[ "$2" == inspect ]] || return 1
        jq -cn --arg root "${root}" --arg first "${first}" --arg second "${second}" \
            --arg mode "${CONTAINERS}" '
          ["xray","net-wireguard"] | map(. as $service |
            {Id:(if $service == "xray" then $first else $second end),
             State:{Status:"running",Running:true,Paused:($mode == "paused"),Restarting:false,Dead:false,
               Health:{Status:(if $mode == "unhealthy" then "unhealthy" else "healthy" end)}},
             Config:{Labels:{"com.docker.compose.service":$service,
               "com.docker.compose.project":"padm-docker","com.docker.compose.project.working_dir":
                 (if $mode == "owner" then "/foreign" else $root end),
               "com.docker.compose.project.config_files":($root+"/compose.json"),
               "com.docker.compose.oneoff":"False","io.padm.mode":"docker","io.padm.project":"padm-docker"}}}) |
          if $mode == "half" then .[:1] else . end'
        ;;
    *) return 1 ;;
    esac
}

args=(enable --invite "${invite}" --yes)
for invalid in 'enable' 'disable --invite x --yes' 'status --yes' 'enable --yes --yes' \
    "enable --invite ${invite}" "enable --invite ${invite} --invite ${invite} --yes"; do
    read -ra arguments <<<"${invalid}"
    expectCode 2 dockerControlCommand sync-schedule "${arguments[@]}"
done
expectCode 2 dockerControlCommand auto-sync --yes
dockerControlCommand sync-schedule status >"${TEST_ROOT}/status.json"
jq -e '. == {backend:"none",installed:false,active:false,enabled:false}' "${TEST_ROOT}/status.json" >/dev/null
dockerControlCommand auto-sync
[[ ! -s "${TEST_ROOT}/client.log" && ! -s "${TEST_ROOT}/runtime.log" ]]
original=$(sha256sum "${spec}")
for BACKEND in systemd cron; do
    for MODE in failure signal; do
        rm -f -- "${TEST_ROOT}/failed-once"
        reject dockerControlCommand sync-schedule "${args[@]}"
        [[ ! -e "${directory}" && ! -e "${service}" && ! -e "${timer}" ]]
        check_clean
    done
    MODE=normal
    dockerControlCommand sync-schedule "${args[@]}"
    dockerControlCommand sync-schedule "${args[@]}"
    [[ "$(sha256sum "${spec}")" == "${original}" && ! -s "${TEST_ROOT}/apply.log" ]]
    [[ "$(stat -c '%u:%g:%a' "${directory}")" == 0:0:700 &&
        "$(stat -c '%u:%g:%a:%h' "${directory}/request.json")" == 0:0:600:1 &&
        "$(stat -c '%u:%g:%a:%h' "${directory}/invite.json")" == 0:0:600:1 ]]
    ! grep -qF "$(jq -r .token "${invite}")" "${directory}/request.json"
    dockerControlCommand sync-schedule status >"${TEST_ROOT}/status.json"
    jq -e --arg backend "${BACKEND}" \
        '. == {backend:$backend,installed:true,active:true,enabled:true}' "${TEST_ROOT}/status.json" >/dev/null
    if [[ "${BACKEND}" == systemd ]]; then
        grep -qxF 'OnCalendar=*-*-* *:0/5:15' "${timer}"
        grep -qxF 'AccuracySec=1s' "${timer}"
        grep -qxF 'TimeoutStopSec=0' "${service}"
        grep -qxF 'SuccessExitStatus=12' "${service}"
        beforeSchedule=$(sha256sum "${TEST_ROOT}/schedule.log")
        dockerControlSyncScheduleInstall
        [[ "$(tail -n 1 "${TEST_ROOT}/schedule.log")" == 'is-active --quiet padm-docker-control-sync.timer' ]]
        EXEC_OVERRIDE='{ path=/usr/bin/false ; argv[]=/usr/bin/false ; ignore_errors=no ; pid=0 ; }'
        reject dockerControlSyncScheduleInstall
        EXEC_OVERRIDE=
        DROPIN_OVERRIDE=/foreign/override.conf
        reject dockerControlSyncScheduleInstall
        DROPIN_OVERRIDE=
        STALE=yes
        reject dockerControlSyncScheduleInstall
        STALE=no
        ENV_OVERRIDE=PADM_DOCKER_INSTALL_DIR=/foreign
        reject dockerControlSyncScheduleInstall
        ENV_OVERRIDE=
        [[ "$(sha256sum "${spec}")" == "${original}" ]]
        cp -- "${timer}" "${TEST_ROOT}/new.timer"
        sed 's/:0\/5:15$/:0\/5:00/' "${timer}" >"${TEST_ROOT}/old.timer"
        cp -- "${TEST_ROOT}/old.timer" "${timer}"
        beforeUnits=$(sha256sum "${service}" "${timer}")
        : >"${TEST_ROOT}/schedule.log"
        MODE=enable-failure
        rm -f -- "${TEST_ROOT}/failed-once"
        reject dockerControlSyncScheduleInstall
        [[ "$(sha256sum "${service}" "${timer}")" == "${beforeUnits}" &&
            -e "${TEST_ROOT}/enabled" && -e "${TEST_ROOT}/active" ]] ||
            fail '旧同步 timer 迁移失败没有恢复原模板和启用状态'
        ! grep -qxF 'stop padm-docker-control-sync.service' "${TEST_ROOT}/schedule.log" ||
            fail '旧同步 timer 失败恢复停止当前同步 service'
        check_clean
        MODE=normal
        dockerControlSyncScheduleInstall
        cmp -- "${TEST_ROOT}/new.timer" "${timer}"
        ! grep -qxF 'stop padm-docker-control-sync.service' "${TEST_ROOT}/schedule.log" ||
            fail '旧同步 timer 同 backend 迁移停止当前同步 service'
        cp -- "${TEST_ROOT}/old.timer" "${timer}"
        sed 's/:0\/5:00$/:0\/5:14/' "${timer}" >"${TEST_ROOT}/bad.timer"
        cp -- "${TEST_ROOT}/bad.timer" "${timer}"
        reject dockerControlSyncScheduleInstall
        cp -- "${TEST_ROOT}/old.timer" "${timer}"
        sed "s|# padm-docker root=${root}|# padm-docker root=/foreign|" \
            "${timer}" >"${TEST_ROOT}/bad.timer"
        cp -- "${TEST_ROOT}/bad.timer" "${timer}"
        reject dockerControlSyncScheduleInstall
        cp -- "${TEST_ROOT}/old.timer" "${timer}"
    else
        newCron=$(grep -F 'control auto-sync' "${TEST_ROOT}/crontab")
        grep -qF "*/5 * * * * $(command -v sleep) 15 && PADM_DOCKER_INSTALL_DIR=" "${TEST_ROOT}/crontab"
        # 执行生成的 cron 命令，短暂占锁必须先结束，CLI 仍只尝试一次且收到正确 root。
        cat >"${PADM_DOCKER_BIN_DIR}/padm-docker" <<EOF
#!/usr/bin/env bash
[[ "\$*" == 'control auto-sync' ]] || exit 2
source "${PROJECT_ROOT}/install-docker.sh"
PADM_DOCKER_LOCK_TIMEOUT=0 dockerAcquireDeploymentLock || exit 12
dockerReleaseDeploymentLock || exit 12
printf '%s %s\n' "\$(date +%s)" "\${PADM_DOCKER_INSTALL_DIR}" >"${TEST_ROOT}/delayed-cli.log"
EOF
        chmod 0700 "${PADM_DOCKER_BIN_DIR}/padm-docker"
        (
            trap 'dockerReleaseDeploymentLock' EXIT
            dockerAcquireDeploymentLock
            : >"${TEST_ROOT}/traffic-ready"
            sleep 2
        ) &
        trafficPid=$!
        while [[ ! -e "${TEST_ROOT}/traffic-ready" ]]; do sleep 0.1; done
        delayedStarted=$(date +%s)
        env PADM_DOCKER_INSTALL_DIR=/foreign /bin/sh -c "${newCron#'*/5 * * * * '}"
        wait "${trafficPid}"
        read -r delayedExecuted delayedRoot <"${TEST_ROOT}/delayed-cli.log"
        [[ "${delayedRoot}" == "${root}" ]] && ((delayedExecuted - delayedStarted >= 15)) ||
            fail '生成的同步 cron 未延迟 15 秒、绕开短暂占锁或传入正确 root'
        oldCron=${newCron/"$(command -v sleep) 15 && "/}
        printf '# unrelated job\n%s\n' "${oldCron}" >"${TEST_ROOT}/crontab"
        beforeCron=$(sha256sum "${TEST_ROOT}/crontab")
        MODE=signal
        rm -f -- "${TEST_ROOT}/failed-once"
        reject dockerControlSyncScheduleInstall
        [[ "$(sha256sum "${TEST_ROOT}/crontab")" == "${beforeCron}" ]] ||
            fail '旧同步 cron 迁移中断没有恢复原作业'
        check_clean
        MODE=normal
        dockerControlSyncScheduleInstall
        [[ "$(grep -F 'control auto-sync' "${TEST_ROOT}/crontab")" == "${newCron}" ]] ||
            fail '旧同步 cron 没有迁移成固定 15 秒延迟'
        beforeCron=$(sha256sum "${TEST_ROOT}/crontab")
        dockerControlSyncScheduleInstall
        [[ "$(sha256sum "${TEST_ROOT}/crontab")" == "${beforeCron}" ]] ||
            fail '新同步 cron 重装不幂等'
        for badCron in "${newCron/' 15 && '/' 14 && '}" \
            "${oldCron/PADM_DOCKER_INSTALL_DIR=${root}/PADM_DOCKER_INSTALL_DIR=/foreign}"; do
            printf '# unrelated job\n%s\n' "${badCron}" >"${TEST_ROOT}/crontab"
            reject dockerControlSyncScheduleInstall
        done
        # 混存的已知新旧行都归同 root，停用时不能遗留任一份。
        printf '# unrelated job\n%s\n%s\n' "${oldCron}" "${newCron}" >"${TEST_ROOT}/crontab"
    fi
    reject dockerControlSyncScheduleBundleCheck "${TEST_ROOT}/old-bundle"
    dockerControlSyncScheduleBundleCheck "${PROJECT_ROOT}"
    beforeClient=$(sha256sum "${TEST_ROOT}/client.log")
    : >"${TEST_ROOT}/network-down"
    dockerControlCommand sync-schedule status >/dev/null
    dockerControlCommand sync-schedule disable --yes >/dev/null
    rm "${TEST_ROOT}/network-down"
    [[ "$(sha256sum "${TEST_ROOT}/client.log")" == "${beforeClient}" && ! -e "${directory}" ]]
    ! grep -qF 'control auto-sync' "${TEST_ROOT}/crontab"
    if [[ "${BACKEND}" == systemd ]]; then
        grep -qxF 'stop padm-docker-control-sync.service' "${TEST_ROOT}/schedule.log" ||
            fail '明确停用调度没有停止受管同步 service'
    fi
    check_clean
done

BACKEND=cron
dockerControlCommand sync-schedule "${args[@]}" >/dev/null
beforeApply=$(sha256sum "${TEST_ROOT}/apply.log")
dockerControlCommand auto-sync
[[ "$(sha256sum "${TEST_ROOT}/apply.log")" != "${beforeApply}" ]]
beforeApply=$(sha256sum "${TEST_ROOT}/apply.log")
dockerControlCommand auto-sync
[[ "$(sha256sum "${TEST_ROOT}/apply.log")" == "${beforeApply}" ]]
dockerAcquireDeploymentLock
expectCode 12 dockerControlCommand auto-sync
dockerReleaseDeploymentLock
for CONTAINERS in half paused owner unhealthy; do expectCode 15 dockerControlCommand auto-sync; done
CONTAINERS=down
beforeClient=$(sha256sum "${TEST_ROOT}/client.log")
beforeRuntime=$(sha256sum "${TEST_ROOT}/runtime.log")
dockerControlCommand auto-sync
[[ "$(sha256sum "${TEST_ROOT}/client.log")" == "${beforeClient}" &&
    "$(sha256sum "${TEST_ROOT}/runtime.log")" == "${beforeRuntime}" ]]
CONTAINERS=running
: >"${TEST_ROOT}/network-down"
expectCode 10 dockerControlCommand auto-sync
rm "${TEST_ROOT}/network-down"
: >"${TEST_ROOT}/revoked"
expectCode 11 dockerControlCommand auto-sync
rm "${TEST_ROOT}/revoked"
saved=$(sha256sum "${directory}/request.json" "${directory}/invite.json")
cp -- "${invite}" "${TEST_ROOT}/good-invite.json"
printf '{"token":"duplicate",%s\n' "$(tail -c +2 "${invite}")" >"${invite}"
expectCode 11 dockerControlCommand sync-schedule "${args[@]}"
[[ "$(sha256sum "${directory}/request.json" "${directory}/invite.json")" == "${saved}" ]]
cp -- "${TEST_ROOT}/good-invite.json" "${invite}"
jq '.expires_at = 1' "${directory}/invite.json" >"${TEST_ROOT}/expired.json"
cp -- "${TEST_ROOT}/expired.json" "${directory}/invite.json"
expectCode 11 dockerControlCommand auto-sync
dockerControlCommand sync-schedule status >/dev/null
dockerControlCommand sync-schedule disable --yes >/dev/null
dockerControlCommand sync-schedule "${args[@]}" >/dev/null
for field in node_id controller_id connection listener_ids; do
    cp -- "${spec}" "${TEST_ROOT}/saved-spec.json"
    jq --arg field "${field}" '.control_sync[$field] =
      (if $field == "listener_ids" then ["entry-other"]
       elif $field == "connection" then .control_sync.connection + {peer_address:"10.77.0.3"}
       else "88888888-8888-4888-8888-888888888888" end)' "${spec}" >"${TEST_ROOT}/drift.json"
    reject dockerControlSyncScheduleSpecCheck "${TEST_ROOT}/drift.json"
    cp -- "${TEST_ROOT}/saved-spec.json" "${spec}"
done
cp -- "${spec}" "${TEST_ROOT}/saved-spec.json"
jq '.host_integrations += [{type:"fail2ban-ssh"}]' "${spec}" >"${TEST_ROOT}/drift.json"
reject dockerControlSyncScheduleSpecCheck "${TEST_ROOT}/drift.json"
for mode in 0640 0700; do
    chmod "${mode}" "${directory}/invite.json"
    expectCode 15 dockerControlCommand auto-sync
done
chmod 0600 "${directory}/invite.json"
ln -s invite.json "${directory}/extra"
expectCode 15 dockerControlCommand auto-sync
rm -- "${directory}/extra"
cp -- "${directory}/invite.json" "${TEST_ROOT}/saved-invite.json"
rm -- "${directory}/invite.json"
ln -s "${TEST_ROOT}/saved-invite.json" "${directory}/invite.json"
expectCode 15 dockerControlCommand auto-sync
rm -- "${directory}/invite.json"
cp -- "${TEST_ROOT}/saved-invite.json" "${directory}/invite.json"
saved=$(sha256sum "${directory}/request.json" "${directory}/invite.json")
for file in request.json invite.json; do
    cp -- "${directory}/${file}" "${TEST_ROOT}/saved-json"
    if [[ "${file}" == request.json ]]; then duplicate='"enabled":true,';
    else duplicate='"token":"cccccccccccccccccccccccccccccccccccccccccccccccc",'; fi
    printf '{%s%s\n' "${duplicate}" "$(tail -c +2 "${TEST_ROOT}/saved-json")" >"${directory}/${file}"
    expectCode 15 dockerControlCommand auto-sync
    cp -- "${TEST_ROOT}/saved-json" "${directory}/${file}"
done
cp -- "${directory}/request.json" "${TEST_ROOT}/saved-json"
printf '{"connection":%s,%s\n' "$(jq -c '.connection' "${TEST_ROOT}/saved-json")" \
    "$(tail -c +2 "${TEST_ROOT}/saved-json")" >"${directory}/request.json"
expectCode 15 dockerControlCommand auto-sync
cp -- "${TEST_ROOT}/saved-json" "${directory}/request.json"

# 邀请轮换不提交业务配置，失败或 TERM 必须恢复旧登记和旧作业。
jq '.token = ("d"*48)' "${invite}" >"${TEST_ROOT}/rotated.json"
cp -- "${TEST_ROOT}/rotated.json" "${invite}"
cp -- "${invite}" "${TEST_ROOT}/server-invite.json"
for MODE in publish-failure publish-signal; do
    rm -f -- "${TEST_ROOT}/failed-once"
    if [[ "${MODE}" == publish-signal ]]; then
        expectCode 143 dockerControlCommand sync-schedule "${args[@]}"
    else
        expectCode 15 dockerControlCommand sync-schedule "${args[@]}"
    fi
    [[ "$(sha256sum "${directory}/request.json" "${directory}/invite.json")" == "${saved}" ]]
    grep -qF 'control auto-sync' "${TEST_ROOT}/crontab"
    check_clean
done
MODE=normal
dockerControlCommand sync-schedule "${args[@]}" >/dev/null
cmp -- "${invite}" "${directory}/invite.json"
beforeClient=$(sha256sum "${TEST_ROOT}/client.log")
for MODE in failure signal; do
    rm -f -- "${TEST_ROOT}/failed-once"
    reject dockerControlCommand sync-schedule disable --yes
    cmp -- "${invite}" "${directory}/invite.json"
    grep -qF 'control auto-sync' "${TEST_ROOT}/crontab"
    check_clean
done
MODE=normal
dockerControlCommand sync-schedule disable --yes >/dev/null
[[ "$(sha256sum "${TEST_ROOT}/client.log")" == "${beforeClient}" && ! -e "${directory}" ]]
dockerControlCommand auto-sync
check_clean
for json in '{"a":1,"a":2}' '{"a":{"b":1},"a":{"c":2}}' '{"a":1,"a":{"b":2}}' \
    '{"a":[],"a":{"b":2}}' '{"a":{"b":1,"b":2}}'; do
    printf '%s\n' "${json}" >"${TEST_ROOT}/json-check"
    reject dockerControlSyncScheduleJsonCheck "${TEST_ROOT}/json-check"
done
printf '{"a":{"b":1,"c":[{"x":2},{"x":2},[],{}]},"d":null}\n' >"${TEST_ROOT}/json-check"
dockerControlSyncScheduleJsonCheck "${TEST_ROOT}/json-check"
for token in "$(printf c%.0s {1..48})" "$(printf d%.0s {1..48})"; do
    ! grep -qF "${token}" "${TEST_ROOT}/result.log" "${TEST_ROOT}/rejected.log" \
        "${TEST_ROOT}/client.log" "${TEST_ROOT}/runtime.log" "${TEST_ROOT}/schedule.log"
done
printf 'docker-control-sync-schedule-ok\n'
