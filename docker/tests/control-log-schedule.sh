#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${PROJECT_ROOT}/.tmp-control-log-schedule.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-control-log-schedule-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
export PYTHONDONTWRITEBYTECODE=1
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
export PADM_DOCKER_SYSTEMD_DIR="${TEST_ROOT}/systemd"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin"

# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

fail() { printf 'docker-control-log-schedule-fail: %s\n' "$*" >&2; exit 1; }
reject() {
    local status=0
    "$@" >"${TEST_ROOT}/rejected.log" 2>&1 || status=$?
    [[ "${status}" -ne 0 ]] || fail "应拒绝: $*"
}
expectCode() {
    local expected=$1 status=0
    shift
    "$@" >"${TEST_ROOT}/result.log" 2>&1 || status=$?
    [[ "${status}" == "${expected}" ]] || fail "退出码 ${status} != ${expected}: $*"
}

root=${PADM_DOCKER_INSTALL_DIR}
dockerInitializeStateRoot
mkdir -p "${PADM_DOCKER_SYSTEMD_DIR}" "${PADM_DOCKER_BIN_DIR}" "${root}/config/control" \
    "${root}/logs/control" "${root}/data/control-source"
chmod 0750 "${root}/logs/control" "${root}/data/control-source"
chown 0:10001 "${root}/logs/control" "${root}/data/control-source"
printf '{"control":{"role":"main"}}\n' >"${root}/config/spec.json"
printf '{}\n' >"${root}/config/control/state.json"
printf '{}\n' >"${root}/deployment.json"
printf '{}\n' >"${root}/compose.json"
printf 'fixture\n' >"${root}/images.env"
printf 'trusted-source-receipt\n' >"${root}/logs/control/source.receipt"
: >"${root}/logs/control/auth.log"
: >"${root}/logs/control/auth.lock"
chmod 0640 "${root}/logs/control/"*
chown 10001:10001 "${root}/logs/control/auth.log" "${root}/logs/control/source.receipt"
chown 0:10001 "${root}/logs/control/auth.lock"
printf '# unrelated job\n' >"${TEST_ROOT}/crontab"
: >"${TEST_ROOT}/schedule.log"
: >"${TEST_ROOT}/writer.log"

# 角色与运行来源的既有大合同由 control-cli 覆盖；本合同执行生产调度和真实日志轮转。
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { :; }
dockerAccountSpecFile() {
    jq -e 'type == "object" and (.control.role == "main" or .role == "standalone")' \
        "${root}/config/spec.json" >/dev/null || return 1
    printf '%s\n' "${root}/config/spec.json"
}
dockerManagedSpecMatchesDeployment() { [[ ! -e "${TEST_ROOT}/deployment-drift" ]]; }
dockerControlStateCheck() { [[ ! -e "${TEST_ROOT}/state-drift" ]]; }
dockerControlSourceSnapshot() {
    printf 'snapshot\n' >>"${TEST_ROOT}/writer.log"
    [[ "${ROLE:-main}" == main && "${CONTAINERS:-running}" == running &&
        ! -e "${TEST_ROOT}/source-drift" ]] || return 1
    printf 'same-source\n'
}
dockerControlRecoveryCheck() { [[ ! -e "${TEST_ROOT}/recovery-drift" ]]; }
dockerAccountImage() { printf 'fixture-ops\n'; }

BACKEND=systemd
MODE=normal
FRAGMENT_OVERRIDE=
DROPIN_OVERRIDE=
systemctl() {
    printf '%s\n' "$*" >>"${TEST_ROOT}/schedule.log"
    case "$1" in
    show-environment) [[ "${BACKEND}" == systemd ]]; return $? ;;
    show)
        case "$2" in
        --property=FragmentPath) printf '%s\n' "${FRAGMENT_OVERRIDE}" ;;
        --property=DropInPaths) printf '%s\n' "${DROPIN_OVERRIDE}" ;;
        *) return 1 ;;
        esac
        return 0
        ;;
    is-enabled) [[ -f "${TEST_ROOT}/enabled" ]]; return $? ;;
    is-active) [[ -f "${TEST_ROOT}/active" ]]; return $? ;;
    esac
    if [[ "${MODE}" == failure && ( "$1" == enable || "$1" == disable ) &&
        ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"
        return 1
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
        : >"${TEST_ROOT}/failed-once"
        kill -TERM "${BASHPID}"
    fi
}
crontab() {
    if [[ "$1" == -l ]]; then cat "${TEST_ROOT}/crontab"; return 0; fi
    [[ "$1" == - ]] || return 1
    if [[ "${MODE}" == failure && ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"
        return 1
    fi
    cat >"${TEST_ROOT}/crontab"
    if [[ "${MODE}" == signal && ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"
        kill -TERM "${BASHPID}"
    fi
}
pgrep() { [[ "${BACKEND}" == cron && "$*" == '-x cron' ]]; }
mv() {
    if [[ "${!#}" == "${root}/data/control-log/schedule.json" &&
        "${MODE}" == publish-failure && ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"
        return 1
    fi
    command mv "$@" || return $?
    if [[ "${!#}" == "${root}/data/control-log/schedule.json" &&
        "${MODE}" == publish-signal && ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"
        kill -TERM "${BASHPID}"
    fi
}

CONTAINERS=running
ROLE=main
cid="$(printf 3%.0s {1..64})"
docker() {
    case "$1" in
    ps)
        if [[ "${CONTAINERS}" == stopped ]]; then return 0; fi
        if [[ "${CONTAINERS}" == half && "$*" == *net-wireguard* ]]; then return 0; fi
        printf '%s\n' "${cid}"
        ;;
    create)
        [[ " $* " == *' --rotate-access-log '* && " $* " == *' --network none '* ]] || return 1
        printf 'create\n' >>"${TEST_ROOT}/writer.log"
        printf '%s\n' "${cid}"
        ;;
    start)
        [[ "$*" == "start ${cid}" && -d "${root}/locks/deployment.lock" ]] || return 1
        PYTHONPATH="${PROJECT_ROOT}/docker/images/ops" python3 -c '
import sys
from control_api import rotate_access_log
print(rotate_access_log(sys.argv[1], sys.argv[2]))
' "${root}/logs/control/auth.log" "${root}/logs/control/auth.lock" >"${TEST_ROOT}/rotation.log"
        ;;
    inspect) printf '{"Running":false,"Status":"exited","ExitCode":0}\n' ;;
    rm) [[ "$*" == "rm ${cid}" && -d "${root}/locks/deployment.lock" ]] ;;
    *) return 1 ;;
    esac
}

state="${root}/data/control-log/schedule.json"
service="${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-control-log.service"
timer="${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-control-log.timer"
expectCode 2 dockerControlCommand log-schedule enable
expectCode 2 dockerControlCommand log-schedule status --yes
expectCode 2 dockerControlCommand auto-log-rotate --yes
dockerControlCommand log-schedule status >"${TEST_ROOT}/status.json"
jq -e '. == {backend:"none",installed:false,active:false,enabled:false}' "${TEST_ROOT}/status.json" >/dev/null
[[ ! -e "${state}" && ! -e "${service}" ]]
[[ -z "$(find "${root}/locks" -mindepth 1 -print -quit)" ]]
beforeWriter=$(sha256sum "${TEST_ROOT}/writer.log")
dockerControlCommand auto-log-rotate
[[ "$(sha256sum "${TEST_ROOT}/writer.log")" == "${beforeWriter}" ]]
dockerControlLogScheduleBundleCheck "${TEST_ROOT}/old-bundle"
(
    unsafeRoot=$(mktemp -d '/tmp/.tmp-control-log-unsafe.XXXXXX')
    trap 'rm -rf -- "${unsafeRoot}"' EXIT
    mkdir -p "${unsafeRoot}/logs/control" "${unsafeRoot}/data/control-source"
    chmod 0750 "${unsafeRoot}/logs/control" "${unsafeRoot}/data/control-source"
    chown 0:10001 "${unsafeRoot}/logs/control" "${unsafeRoot}/data/control-source"
    for file in auth.log auth.lock source.receipt; do : >"${unsafeRoot}/logs/control/${file}"; done
    # 严格祖先校验拒绝 /tmp sticky 目录，不能让启用后的每次轮转都失败。
    reject dockerControlLogInputsCheck "${unsafeRoot}"
)

for BACKEND in systemd cron; do
    dockerControlCommand log-schedule enable --yes
    dockerControlCommand log-schedule enable --yes
    [[ "$(stat -c '%u:%g:%a:%h' "${state}")" == 0:0:600:1 &&
        "$(stat -c '%u:%g:%a' "${root}/data/control-log")" == 0:0:700 ]]
    jq -e '. == {schema_version:1,enabled:true}' "${state}" >/dev/null
    reject dockerControlLogScheduleBundleCheck "${TEST_ROOT}/old-bundle"
    dockerControlLogScheduleBundleCheck "${PROJECT_ROOT}"
    dockerControlCommand log-schedule status >"${TEST_ROOT}/status.json"
    jq -e --arg backend "${BACKEND}" \
        '. == {backend:$backend,installed:true,active:true,enabled:true}' "${TEST_ROOT}/status.json" >/dev/null
    if [[ "${BACKEND}" == systemd ]]; then
        grep -qxF 'TimeoutStartSec=0' "${service}"
        grep -qxF 'TimeoutStopSec=0' "${service}"
        grep -qxF 'SuccessExitStatus=12' "${service}"
        grep -qxF 'OnCalendar=*-*-* *:19:00' "${timer}"
    else
        [[ "$(grep -c '控制认证日志自动轮转' "${TEST_ROOT}/crontab")" == 1 ]]
        grep -q '^19 \* \* \* \* ' "${TEST_ROOT}/crontab"
    fi
    beforeState=$(sha256sum "${state}")
    beforeCron=$(sha256sum "${TEST_ROOT}/crontab")
    if [[ -f "${service}" ]]; then cp "${service}" "${TEST_ROOT}/service.previous"; fi
    if [[ -f "${timer}" ]]; then cp "${timer}" "${TEST_ROOT}/timer.previous"; fi
    for MODE in failure signal publish-failure publish-signal; do
        rm -f "${TEST_ROOT}/failed-once"
        reject dockerControlCommand log-schedule disable --yes
        [[ "$(sha256sum "${state}")" == "${beforeState}" &&
            "$(sha256sum "${TEST_ROOT}/crontab")" == "${beforeCron}" ]]
        [[ ! -f "${service}" ]] || cmp -s "${service}" "${TEST_ROOT}/service.previous"
        [[ ! -f "${timer}" ]] || cmp -s "${timer}" "${TEST_ROOT}/timer.previous"
        [[ -z "$(find "${root}/locks" -mindepth 1 -print -quit)" ]]
    done
    MODE=normal
    dockerControlCommand log-schedule disable --yes
    dockerControlCommand log-schedule status >"${TEST_ROOT}/status.json"
    jq -e '. == {backend:"none",installed:false,active:false,enabled:false}' "${TEST_ROOT}/status.json" >/dev/null
    [[ ! -e "${service}" && ! -e "${timer}" &&
        "$(cat "${TEST_ROOT}/crontab")" == '# unrelated job' ]]
done

BACKEND=systemd
dockerControlCommand log-schedule enable --yes
beforeState=$(sha256sum "${state}")
beforeService=$(sha256sum "${service}")
beforeTimer=$(sha256sum "${timer}")
dockerControlCommand log-schedule status >/dev/null
[[ "$(sha256sum "${state}")" == "${beforeState}" &&
    "$(sha256sum "${service}")" == "${beforeService}" &&
    "$(sha256sum "${timer}")" == "${beforeTimer}" ]]
tail -n 6 "${TEST_ROOT}/schedule.log" | grep -Eq 'daemon-reload|^enable|^disable|^stop|^start' &&
    fail '状态查询修改了调度'
printf 'OnCalendar=*-*-* *:*:00\n' >>"${timer}"
reject dockerControlCommand log-schedule status
reject dockerControlCommand log-schedule disable --yes
head -n -1 "${timer}" >"${TEST_ROOT}/timer.clean"
cp "${TEST_ROOT}/timer.clean" "${timer}"
DROPIN_OVERRIDE=/etc/systemd/system/unknown.conf
reject dockerControlCommand log-schedule status
DROPIN_OVERRIDE=
mkdir "${service}.d"
reject dockerControlCommand log-schedule disable --yes
rmdir "${service}.d"
FRAGMENT_OVERRIDE=/etc/systemd/system/foreign.service
reject dockerControlCommand log-schedule disable --yes
FRAGMENT_OVERRIDE=

beforeWriter=$(sha256sum "${TEST_ROOT}/writer.log")
dockerAcquireDeploymentLock
expectCode 12 dockerControlCommand auto-log-rotate
dockerReleaseDeploymentLock
[[ "$(sha256sum "${TEST_ROOT}/writer.log")" == "${beforeWriter}" ]]
CONTAINERS=stopped
dockerControlCommand auto-log-rotate
[[ "$(sha256sum "${TEST_ROOT}/writer.log")" == "${beforeWriter}" ]]
CONTAINERS=half
expectCode 15 dockerControlCommand auto-log-rotate
CONTAINERS=running
touch "${TEST_ROOT}/source-drift"
expectCode 15 dockerControlCommand auto-log-rotate
reject dockerControlCommand log-schedule enable --yes
rm "${TEST_ROOT}/source-drift"

receipt=$(stat -c '%d:%i:%a:%u:%g:%h' "${root}/logs/control/source.receipt")
receiptHash=$(sha256sum "${root}/logs/control/source.receipt")
truncate -s 10485761 "${root}/logs/control/auth.log"
dockerControlCommand auto-log-rotate
[[ "$(cat "${TEST_ROOT}/rotation.log")" == rotated &&
    "$(stat -c %s "${root}/logs/control/auth.log")" == 0 &&
    "$(stat -c %s "${root}/logs/control/auth.log.1")" == 10485761 &&
    "$(stat -c '%d:%i:%a:%u:%g:%h' "${root}/logs/control/source.receipt")" == "${receipt}" &&
    "$(sha256sum "${root}/logs/control/source.receipt")" == "${receiptHash}" ]]
dockerControlCommand log-schedule disable --yes
beforeWriter=$(sha256sum "${TEST_ROOT}/writer.log")
dockerControlCommand auto-log-rotate
[[ "$(sha256sum "${TEST_ROOT}/writer.log")" == "${beforeWriter}" ]]

dockerControlCommand log-schedule enable --yes
printf '{"role":"standalone"}\n' >"${root}/config/spec.json"
ROLE=standalone
beforeWriter=$(sha256sum "${TEST_ROOT}/writer.log")
dockerControlCommand auto-log-rotate
dockerControlLogScheduleInstall
[[ ! -e "${service}" && ! -e "${timer}" &&
    "$(sha256sum "${TEST_ROOT}/writer.log")" == "${beforeWriter}" ]]
jq -e '.enabled == true' "${state}" >/dev/null
printf '{"corrupt":true}\n' >"${root}/config/spec.json"
expectCode 15 dockerControlCommand auto-log-rotate
reject dockerControlLogScheduleInstall
printf '{"control":{"role":"main"}}\n' >"${root}/config/spec.json"
ROLE=main
touch "${TEST_ROOT}/deployment-drift"
expectCode 15 dockerControlCommand auto-log-rotate
rm "${TEST_ROOT}/deployment-drift"
dockerControlLogScheduleInstall

cp "${state}" "${TEST_ROOT}/state.previous"
(
    # 工具输出了完整元数据后失败，也不能授权调度状态。
    stat() {
        command stat "$@" || return $?
        [[ "${!#}" != "${state}" ]]
    }
    reject dockerControlLogScheduleValidate "${root}"
)
printf '{"schema_version":1,"enabled":true,"command":"foreign"}\n' >"${state}"
expectCode 15 dockerControlCommand auto-log-rotate
reject dockerControlCommand log-schedule disable --yes
cp "${TEST_ROOT}/state.previous" "${state}"
chmod 0640 "${state}"
reject dockerControlLogScheduleInstall
chmod 0600 "${state}"
ln "${state}" "${TEST_ROOT}/hardlink"
reject dockerControlLogScheduleBundleCheck "${PROJECT_ROOT}"
rm "${TEST_ROOT}/hardlink"
mv "${state}" "${TEST_ROOT}/saved-state"
ln -s "${TEST_ROOT}/saved-state" "${state}"
expectCode 15 dockerControlCommand auto-log-rotate
rm "${state}"
mv "${TEST_ROOT}/saved-state" "${state}"
dockerControlCommand log-schedule enable --yes
mkdir "${TEST_ROOT}/core.previous"
cp "${root}/config/control/state.json" "${TEST_ROOT}/core.previous/control.json"
for relative in config/spec.json deployment.json compose.json images.env; do
    mv "${root}/${relative}" "${TEST_ROOT}/core.previous/${relative##*/}"
done
beforeWriter=$(sha256sum "${TEST_ROOT}/writer.log")
beforeService=$(sha256sum "${service}")
beforeTimer=$(sha256sum "${timer}")
expectCode 15 dockerControlCommand auto-log-rotate
reject dockerControlLogScheduleInstall
[[ "$(sha256sum "${TEST_ROOT}/writer.log")" == "${beforeWriter}" &&
    "$(sha256sum "${service}")" == "${beforeService}" &&
    "$(sha256sum "${timer}")" == "${beforeTimer}" ]]
rm "${root}/config/control/state.json"
dockerControlCommand auto-log-rotate
dockerControlLogScheduleInstall
[[ ! -e "${service}" && ! -e "${timer}" &&
    "$(sha256sum "${TEST_ROOT}/writer.log")" == "${beforeWriter}" ]]
jq -e '.enabled == true' "${state}" >/dev/null
for relative in config/spec.json deployment.json compose.json images.env; do
    mv "${TEST_ROOT}/core.previous/${relative##*/}" "${root}/${relative}"
done
mv "${TEST_ROOT}/core.previous/control.json" "${root}/config/control/state.json"
dockerControlCommand log-schedule disable --yes
[[ -z "$(find "${root}/locks" -mindepth 1 -print -quit)" ]]
printf 'docker-control-log-schedule-regression-ok\n'
