#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-control-log-lifecycle.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-control-log-lifecycle-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
for tool in jq stat find sha256sum wc; do command -v "${tool}" >/dev/null; done

export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
export PADM_DOCKER_SKIP_CHOWN=1
export PADM_DOCKER_HEALTH_TIMEOUT=1
lifecycleRoot=${PADM_DOCKER_INSTALL_DIR}
mkdir -p "${lifecycleRoot}/backups" "${lifecycleRoot}/data/control-log" "${lifecycleRoot}/bundles/valid/docker/lib"
chmod 0700 "${lifecycleRoot}" "${lifecycleRoot}/data/control-log"
printf '%s\n' '{"schema_version":1,"enabled":true}' >"${lifecycleRoot}/data/control-log/schedule.json"
chmod 0600 "${lifecycleRoot}/data/control-log/schedule.json"

# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
eval "$(declare -f dockerValidateConfigurationBackup | sed '1s/dockerValidateConfigurationBackup/dockerProductionValidateConfigurationBackup/')"
eval "$(declare -f dockerBackupConfiguration | sed '1s/dockerBackupConfiguration/dockerProductionBackupConfiguration/')"
eval "$(declare -f dockerComposeFile | sed '1s/dockerComposeFile/dockerProductionComposeFile/')"

calls="${TEST_ROOT}/calls.log"
: >"${calls}"
record() { printf '%s\n' "$*" >>"${calls}"; }
fail() { printf 'docker-control-log-lifecycle-fail: %s\n' "$*" >&2; exit 1; }
reset_calls() { : >"${calls}"; }
has_call() { grep -Fxq -- "$1" "${calls}"; }

dockerHostPreflight() { record host-preflight; }
dockerLockInstalledDeployment() { record lock; }
dockerReleaseDeploymentLock() { record unlock; }
dockerComposeFile() {
    if [[ "${REAL_COMPOSE_GUARD:-0}" == 1 ]]; then
        dockerProductionComposeFile
        return $?
    fi
    [[ "${FAIL_COMPOSE:-0}" != 1 ]] || return 1
    printf '%s\n' "${lifecycleRoot}/compose.json"
}
dockerRealityStreamDeploymentCheck() { record reality; }
dockerFail2banSourceInputsPrepare() { record fail2ban-source; }
dockerFail2banSourceInputsCheck() { :; }
dockerTrafficRuntimeCheck() { record traffic-runtime; }
dockerTrafficBeforeChange() { record traffic-before; }
dockerTrafficScheduleInstall() { record traffic-install; }
dockerTrafficScheduleRemove() { record traffic-remove; }
dockerRenewalScheduleInstall() { record renewal-install; }
dockerRenewalScheduleRemove() { record renewal-remove; }
dockerGeoScheduleInstall() { record geo-install; }
dockerGeoScheduleRemove() { record geo-remove; }
dockerControlLogScheduleInstall() { record control-log-install; }
dockerControlLogScheduleRemove() { record control-log-remove; }
dockerControlSyncScheduleInstall() { record control-sync-install; }
dockerControlSyncScheduleRemove() { record control-sync-remove; }
dockerControlSyncScheduleValidate() { record control-sync-validate; }
dockerControlSyncScheduleSpecCheck() { record control-sync-binding; [[ "${FAIL_SYNC_SPEC:-0}" != 1 ]]; }
dockerControlSyncScheduleBundleCheck() { record control-sync-bundle; [[ "${FAIL_SYNC_BUNDLE:-0}" != 1 ]]; }
dockerComposeRun() { record "compose:$*"; }
dockerComposeExecute() { record "compose-execute:$*"; }
dockerDeploymentState() { printf '%s\n' installed; }
dockerRemoveCli() { record remove-cli; }
dockerControlRecoveryCheck() { :; }
dockerControlAccessLogEnsure() { :; }
dockerControlRestorePrepare() { :; }
dockerTProxyDisablePrepare() { jq -e '.host_integrations == []' "$1" >/dev/null; }
dockerFail2banDisablePrepare() { :; }
dockerControlFail2banDisablePrepare() { :; }
dockerSshFail2banDisablePrepare() { :; }
dockerRealityStreamStopServices() { :; }
dockerRemoveConfigurationTargets() { :; }
dockerTlsRuntimePermissions() { :; }
dockerEnsureRuntimeDataPermissions() { :; }
dockerTrafficPrepareCandidate() { :; }
dockerValidateConfigurationBackup() { :; }
dockerError() { record "error:$*"; }
dockerBundleSupportsSpec() { :; }
dockerManagedSpecMatchesDeployment() { :; }
dockerDeploymentFileValidate() { :; }
dockerControlStateCheck() { :; }
currentBundle="${lifecycleRoot}/bundles/valid"
printf '%s\n' 'readonly PADM_DOCKER_CONTROL_LOG_SCHEDULE_SCHEMA=1' >"${currentBundle}/docker/lib/control.sh"
dockerCurrentBundlePath() { printf '%s\n' "${currentBundle}"; }
registration=$(stat -c '%d:%i:%u:%g:%a:%h' "${lifecycleRoot}/data/control-log/schedule.json"; sha256sum "${lifecycleRoot}/data/control-log/schedule.json")
assert_registration() {
    [[ "$(stat -c '%d:%i:%u:%g:%a:%h' "${lifecycleRoot}/data/control-log/schedule.json"; sha256sum "${lifecycleRoot}/data/control-log/schedule.json")" == "${registration}" ]] ||
        fail '生命周期改变本机调度登记'
}

# 旧 bundle 缺少控制日志调度能力时，升级必须在停服前拒绝。
mkdir -p "${TEST_ROOT}/bundles/old/docker/lib"
printf '%s\n' '# legacy control bundle' >"${TEST_ROOT}/bundles/old/docker/lib/control.sh"
reset_calls
DOCKER_STAGED_BUNDLE_PATH="${TEST_ROOT}/bundles/old"
if dockerControlLogScheduleBundleCheck "${DOCKER_STAGED_BUNDLE_PATH}"; then
    fail '旧 bundle enabled 门禁被绕过'
fi
if has_call 'compose:down' || has_call control-log-remove; then
    fail '旧 bundle 拒绝前已停止服务或删除调度'
fi
mkdir -p "${lifecycleRoot}/config"
printf '%s\n' '{"host_integrations":[]}' >"${lifecycleRoot}/config/spec.json"
chmod 0600 "${lifecycleRoot}/config/spec.json"
dockerManifestPrepare() { record manifest; }
dockerStageReleaseBundle() { DOCKER_STAGED_BUNDLE_PATH="${TEST_ROOT}/bundles/old"; record stage; }
dockerRenewalBundleCheck() { :; }
dockerGeoBundleCheck() { :; }
dockerPullManifestImages() { record pull; return 1; }
reset_calls
status=0
dockerUpdateCommand || status=$?
[[ "${status}" == "${PADM_DOCKER_RC_BUNDLE}" ]] || fail '升级入口未拒绝旧调度 bundle'
! grep -Eq '^(compose:|compose-execute:|pull$|control-log-remove$)' "${calls}" ||
    fail '旧 bundle 升级拒绝前执行了部署或调度动作'
assert_registration

# 配置备份只收录业务目录，本机调度登记必须留在原位置且不能进入快照。
printf '%s\n' '{"services":{}}' >"${lifecycleRoot}/compose.json"
printf '%s\n' '{"schema_version":1,"mode":"docker","compose":{"project":"padm-docker","profiles":[]},"host_integrations":[]}' >"${lifecycleRoot}/deployment.json"
: >"${lifecycleRoot}/images.env"
reset_calls
for prefix in configure business; do
    dockerBackupConfiguration "${prefix}"
    backup=${DOCKER_CONFIG_BACKUP}
    [[ "${prefix}" != configure ]] || configureBackup=${backup}
    [[ ! -e "${backup}/data/control-log" ]] || fail '本机调度登记进入业务备份'
    assert_registration
done
backup=${configureBackup}
dockerProductionValidateConfigurationBackup "${backup}"

# 安装和恢复共享同一能力门禁；不能先切 bundle 或停止在线 Compose。
dockerStageBundle() { DOCKER_STAGED_BUNDLE_PATH="${TEST_ROOT}/bundles/old"; record stage-bundle; }
dockerActivateStagedBundle() { record activate-bundle; }
reset_calls
if dockerInstallBundle "${PROJECT_ROOT}"; then fail '安装入口接受旧调度 bundle'; fi
! has_call activate-bundle || fail '安装旧 bundle 拒绝前已切换指针'
(
    dockerValidateConfigurationBackup() { dockerProductionValidateConfigurationBackup "$@"; }
    currentBundle="${TEST_ROOT}/bundles/old"
    DOCKER_CONFIG_BACKUP="${backup}"
    DOCKER_CONFIG_SWITCHED=1
    reset_calls
    if dockerRestoreConfiguration; then fail '恢复入口接受旧调度 bundle'; fi
    ! grep -Eq '^(compose:|compose-execute:|activate-bundle$)' "${calls}" ||
        fail '旧 bundle 恢复拒绝前已启停或切换'
    cp -a -- "${backup}" "${lifecycleRoot}/backups/update.legacy"
    if dockerRollbackCommand; then fail '回滚入口接受旧调度 bundle'; fi
    ! grep -Eq '^(compose:|compose-execute:|activate-bundle$)' "${calls}" ||
        fail '旧 bundle 回滚拒绝前已启停或切换'
)
assert_registration

# 无原始规格的旧备份也必须校验本机登记，target 和 current 两条选择路径都不能漏。
legacy="${lifecycleRoot}/backups/update.no-spec"
cp -a -- "${backup}" "${legacy}"
rm -- "${legacy}/config/spec.json"
sed '/^config\/spec.json$/d' "${legacy}/present" >"${TEST_ROOT}/legacy.present"
cp -- "${TEST_ROOT}/legacy.present" "${legacy}/present"
(
    dockerValidateConfigurationBackup() { dockerProductionValidateConfigurationBackup "$@"; }
    dockerBundlePathForTarget() {
        [[ "$1" == .bundles/legacy ]] || return 1
        printf '%s\n' "${TEST_ROOT}/bundles/old"
    }
    currentBundle="${TEST_ROOT}/bundles/old"
    for route in target current; do
        if [[ "${route}" == target ]]; then
            printf '%s\n' .bundles/legacy >"${legacy}/bundle.target"
        else
            rm -- "${legacy}/bundle.target"
        fi
        reset_calls
        if dockerProductionValidateConfigurationBackup "${legacy}"; then
            fail '无规格旧备份漏过 enabled 调度能力门禁'
        fi
        grep -Fq 'error:目标控制 bundle 不支持已启用的控制日志调度' "${calls}" ||
            fail '无规格旧备份被其它校验拒绝，未证明调度门禁'
        DOCKER_CONFIG_BACKUP="${legacy}"
        DOCKER_CONFIG_SWITCHED=1
        if dockerRestoreConfiguration; then fail '恢复入口接受无规格旧调度 bundle'; fi
        ! grep -Eq '^(compose:|compose-execute:|activate-bundle$)' "${calls}" ||
            fail '无规格旧 bundle 恢复拒绝前已启停或切换'
        printf '%s\n' '{"schema_version":1,"enabled":false}' >"${lifecycleRoot}/data/control-log/schedule.json"
        dockerProductionValidateConfigurationBackup "${legacy}" ||
            fail '已关闭调度仍拒绝无规格旧备份'
        printf '%s\n' '{"schema_version":1,"enabled":true}' >"${lifecycleRoot}/data/control-log/schedule.json"
    done
)
assert_registration

# up/restart/down/uninstall 都必须调用控制日志调度 helper。
reset_calls
dockerLifecycleCommand up
has_call control-log-install || fail 'up 未安装控制日志调度'
has_call control-sync-install || fail 'up 未安装自动同步调度'
has_call 'compose:up -d' || fail 'up 未启动 Compose'

# 跳跃监督会话存在时，普通 up 必须保留现场并拒绝启动，不能绕过恢复门禁。
mkdir -p "${lifecycleRoot}/data/net"
: >"${lifecycleRoot}/data/net/.hopping-supervisor"
reset_calls
status=0
dockerLifecycleCommand up || status=$?
[[ "${status}" == "${PADM_DOCKER_RC_LOCK}" ]] || fail 'up 绕过跳跃残留门禁'
has_call 'error:跳跃监督会话仍在运行或残留，已拒绝普通启动；请先停止或核验清理' ||
    fail 'up 残留门禁未给出恢复提示'
! grep -Eq '^(compose:|traffic-|.*-install$)' "${calls}" ||
    fail 'up 残留门禁拒绝前已修改服务'
rm -f -- "${lifecycleRoot}/data/net/.hopping-supervisor"

# 断链符号链接也属于残留，不能被普通存在性检查绕过。
ln -s -- "${lifecycleRoot}/data/net/.missing-supervisor" \
    "${lifecycleRoot}/data/net/.hopping-supervisor"
reset_calls
status=0
dockerLifecycleCommand up || status=$?
[[ "${status}" == "${PADM_DOCKER_RC_LOCK}" ]] || fail 'up 绕过跳跃断链残留门禁'
! grep -Eq '^(compose:|traffic-|.*-install$)' "${calls}" ||
    fail 'up 断链残留门禁拒绝前已修改服务'
rm -f -- "${lifecycleRoot}/data/net/.hopping-supervisor"

reset_calls
dockerLifecycleCommand restart
has_call control-log-install || fail 'restart 未安装控制日志调度'
has_call control-sync-install || fail 'restart 未安装自动同步调度'
has_call 'compose:restart' || fail 'restart 未重启 Compose'

reset_calls
dockerLifecycleCommand down
has_call control-log-remove || fail 'down 未移除控制日志调度'
has_call control-sync-remove || fail 'down 未移除自动同步调度'
has_call 'compose:down' || fail 'down 未停止 Compose'

# Compose 状态损坏时，卸载必须在任何调度或服务动作前拒绝。
reset_calls
printf '%s\n' '{"services":[]}' >"${lifecycleRoot}/compose.json"
REAL_COMPOSE_GUARD=1
status=0
dockerUninstallCommand || status=$?
unset REAL_COMPOSE_GUARD
printf '%s\n' '{"services":{}}' >"${lifecycleRoot}/compose.json"
unset FAIL_COMPOSE
[[ "${status}" == "${PADM_DOCKER_RC_STATE}" ]] || fail 'Compose 状态损坏时卸载未拒绝'
! grep -Eq '^(geo-remove|renewal-remove|control-log-remove|control-sync-remove|compose:down)$' "${calls}" ||
    fail 'Compose 状态损坏时卸载已修改调度或服务'
has_call 'error:Docker Compose 状态不完整，已拒绝卸载' ||
    fail 'Compose 状态损坏时卸载未提示原因'
assert_registration

reset_calls
rm -f -- "${lifecycleRoot}/images.env"
REAL_COMPOSE_GUARD=1
status=0
dockerUninstallCommand || status=$?
unset REAL_COMPOSE_GUARD
printf '%s\n' 'placeholder' >"${lifecycleRoot}/images.env"
[[ "${status}" == "${PADM_DOCKER_RC_STATE}" ]] || fail 'images.env 缺失时卸载未拒绝'
! grep -Eq '^(geo-remove|renewal-remove|control-log-remove|control-sync-remove|compose:down)$' "${calls}" ||
    fail 'images.env 缺失时卸载已修改调度或服务'
has_call 'error:images.env 缺失或不安全，已拒绝卸载' ||
    fail 'images.env 缺失时卸载未提示原因'
assert_registration

reset_calls
printf '%s\n' '{"schema_version":1,"mode":"docker","compose":{"project":"padm-docker","profiles":[]},"host_integrations":null}' \
    >"${lifecycleRoot}/deployment.json"
REAL_COMPOSE_GUARD=1
status=0
dockerUninstallCommand || status=$?
unset REAL_COMPOSE_GUARD
printf '%s\n' '{"schema_version":1,"mode":"docker","compose":{"project":"padm-docker","profiles":[]},"host_integrations":[]}' \
    >"${lifecycleRoot}/deployment.json"
[[ "${status}" == "${PADM_DOCKER_RC_STATE}" ]] || fail '部署状态损坏时卸载未拒绝'
! grep -Eq '^(geo-remove|renewal-remove|control-log-remove|control-sync-remove|compose:down)$' "${calls}" ||
    fail '部署状态损坏时卸载已修改调度或服务'
has_call 'error:Docker 部署状态不完整，已拒绝卸载' ||
    fail '部署状态损坏时卸载未提示原因'
assert_registration

reset_calls
printf '%s\n' '{"host_integrations":null}' >"${lifecycleRoot}/config/spec.json"
REAL_COMPOSE_GUARD=1
status=0
dockerUninstallCommand || status=$?
unset REAL_COMPOSE_GUARD
printf '%s\n' '{"host_integrations":[]}' >"${lifecycleRoot}/config/spec.json"
[[ "${status}" == "${PADM_DOCKER_RC_STATE}" ]] || fail '配置状态损坏时卸载未拒绝'
! grep -Eq '^(geo-remove|renewal-remove|control-log-remove|control-sync-remove|compose:down)$' "${calls}" ||
    fail '配置状态损坏时卸载已修改调度或服务'
has_call 'error:Docker 配置状态不完整，已拒绝卸载' ||
    fail '配置状态损坏时卸载未提示原因'
assert_registration

reset_calls
dockerUninstallCommand
has_call control-log-remove || fail 'uninstall 未移除控制日志调度'
has_call control-sync-remove || fail 'uninstall 未移除自动同步调度'
has_call 'compose:down' || fail 'uninstall 未停止 Compose'
assert_registration

# configure 提交和 restore 完成后都重新安装登记；登记不参与恢复快照复制。
spec="${TEST_ROOT}/request.json"
printf '%s\n' '{"core":{"type":"xray","secondary_type":null},"host_integrations":[]}' >"${spec}"
dockerCreateConfigurationCandidate() {
    DOCKER_CONFIG_CANDIDATE="${lifecycleRoot}/.candidate.lifecycle"
    mkdir -p "${DOCKER_CONFIG_CANDIDATE}"
}
dockerGenerateCandidate() {
    mkdir -p "$2/config"
    cp -- "$1" "$2/config/spec.json"
}
dockerValidateCandidate() { :; }
dockerConfigureSpecValidate() { :; }
dockerAcmeWebrootTransitionValidate() { :; }
dockerControlSyncTransitionValidate() { :; }
dockerControlTransitionValidate() { :; }
dockerConfigureReleaseValidate() { :; }
dockerRealityTargetsValidate() { :; }
dockerHostIntegrationInputsValidate() { :; }
dockerConfigurePortsAvailable() { :; }
dockerFail2banSourceInputsPrepare() { :; }
dockerBackupConfiguration() { DOCKER_CONFIG_BACKUP="${lifecycleRoot}/backups/configure.lifecycle"; mkdir -p "${DOCKER_CONFIG_BACKUP}"; }
dockerInstallCandidate() { DOCKER_CONFIG_SWITCHED=1; }
dockerCleanupConfigurationCandidate() { :; }
reset_calls
dockerConfigureApply "${spec}" '' '' configure
has_call control-log-install || fail 'configure 提交后未安装控制日志调度'
has_call control-sync-install || fail 'configure 提交后未安装自动同步调度'

backup="${lifecycleRoot}/backups/restore.lifecycle"
mkdir -p "${backup}"
: >"${backup}/present"
DOCKER_CONFIG_BACKUP="${backup}"
DOCKER_CONFIG_SWITCHED=1
reset_calls
dockerRestoreConfiguration
has_call control-log-install || fail 'restore 完成后未安装控制日志调度'
has_call control-sync-install || fail 'restore 完成后未安装自动同步调度'
assert_registration

# 同步绑定和能力检查失败须发生在流量采集、停服或切换之前。
FAIL_SYNC_SPEC=1
reset_calls
DOCKER_CONFIG_SWITCHED=1
if dockerRestoreConfiguration; then fail '空恢复点绕过自动同步绑定门禁'; fi
! grep -Eq '^(compose:|compose-execute:|traffic-before$)' "${calls}" ||
    fail '空恢复点同步绑定拒绝前已采集或修改服务'
for action in up restart; do
    reset_calls
    status=0
    dockerLifecycleCommand "${action}" || status=$?
    [[ "${status}" == "${PADM_DOCKER_RC_STATE}" ]] || fail '生命周期漏过自动同步绑定门禁'
    ! grep -Eq '^(compose:|traffic-before$|control-sync-install$)' "${calls}" ||
        fail '同步绑定拒绝前已采集或修改服务'
done
reset_calls
status=0
dockerConfigureApply "${spec}" '' '' configure || status=$?
[[ "${status}" == "${PADM_DOCKER_RC_CONFLICT}" ]] || fail '配置漏过自动同步候选绑定门禁'
! grep -Eq '^(compose:|traffic-before$|control-sync-install$)' "${calls}" ||
    fail '同步候选绑定拒绝前已采集或修改服务'
FAIL_SYNC_SPEC=0
FAIL_SYNC_BUNDLE=1
dockerStageReleaseBundle() { DOCKER_STAGED_BUNDLE_PATH="${currentBundle}"; record stage; }
dockerStageBundle() { DOCKER_STAGED_BUNDLE_PATH="${currentBundle}"; record stage-bundle; }
reset_calls
status=0
dockerUpdateCommand || status=$?
[[ "${status}" == "${PADM_DOCKER_RC_BUNDLE}" ]] || fail '更新漏过自动同步能力门禁'
! grep -Eq '^(compose:|traffic-before$|pull$|control-sync-install$)' "${calls}" ||
    fail '同步能力拒绝前已采集或修改服务'
reset_calls
if dockerInstallBundle "${PROJECT_ROOT}"; then fail '安装漏过自动同步能力门禁'; fi
! has_call activate-bundle || fail '同步能力拒绝前已切换 bundle'

# 本机邀请不进入配置或业务快照；有登记时无规格恢复点必须拒绝。
syncDirectory="${lifecycleRoot}/secrets/control-sync"
mkdir -p "${syncDirectory}"
chmod 0700 "${syncDirectory}"
printf '%s\n' '{"schema_version":1,"enabled":true}' >"${syncDirectory}/request.json"
printf '%s\n' '{"token":"private-test-token"}' >"${syncDirectory}/invite.json"
chmod 0600 "${syncDirectory}/request.json" "${syncDirectory}/invite.json"
syncRegistration=$(sha256sum "${syncDirectory}/request.json" "${syncDirectory}/invite.json")
reset_calls
if dockerProductionValidateConfigurationBackup "${legacy}"; then fail '同步登记接受无规格恢复点'; fi
! grep -Eq '^(compose:|compose-execute:)' "${calls}" || fail '无规格恢复点拒绝前已修改服务'
FAIL_SYNC_BUNDLE=0
for prefix in configure business; do
    dockerProductionBackupConfiguration "${prefix}"
    [[ ! -e "${DOCKER_CONFIG_BACKUP}/secrets/control-sync" ]] || fail '自动同步邀请进入备份'
done
[[ "$(sha256sum "${syncDirectory}/request.json" "${syncDirectory}/invite.json")" == "${syncRegistration}" ]] ||
    fail '生命周期改动本机邀请'
assert_registration

printf 'docker-control-log-lifecycle-ok\n'
