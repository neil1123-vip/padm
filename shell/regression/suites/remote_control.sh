#!/usr/bin/env bash

REGRESSION_REMOTE_CONTROL_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_REMOTE_CONTROL_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_REMOTE_CONTROL_SUITE_DIR}/../subscription_groups_remote_control.sh"

runRegressionRemoteControlSuiteSelector() {
    case "$1" in
    remote-control-smoke) runRegressionRemoteControlSmoke ;;
    remote-control-contract) runRegressionRemoteControlContract ;;
    remote-control-smoke-core) runRegressionRemoteControlSmokeCore ;;
    remote-control-smoke-refresh) runRegressionRemoteControlSmokeRefresh ;;
    remote-control-smoke-refresh-apply) runRegressionRemoteControlSmokeRefreshApply ;;
    remote-control-smoke-refresh-apply-basic) runRegressionRemoteControlSmokeRefreshApplyBasic ;;
    remote-control-smoke-refresh-apply-prepare) runRegressionRemoteControlSmokeRefreshApplyPrepare ;;
    remote-control-smoke-refresh-apply-failure) runRegressionRemoteControlSmokeRefreshApplyFailure ;;
    remote-control-smoke-refresh-restore) runRegressionRemoteControlSmokeRefreshRestore ;;
    remote-control-smoke-refresh-reconcile) runRegressionRemoteControlSmokeRefreshReconcile ;;
    remote-control-contract-service-install) runRegressionRemoteControlContractServiceInstall ;;
    remote-control-contract-service-install-success) runRegressionRemoteControlContractServiceInstallSuccess ;;
    remote-control-contract-service-install-systemctl-fail) runRegressionRemoteControlContractServiceInstallSystemctlFail ;;
    remote-control-contract-service-install-health-fail) runRegressionRemoteControlContractServiceInstallHealthFail ;;
    remote-control-contract-service-install-health-rollback) runRegressionRemoteControlContractServiceInstallHealthRollback ;;
    remote-control-contract-service-install-token-transaction) runRegressionRemoteControlContractServiceInstallTokenTransaction ;;
    remote-control-contract-server-response) runRegressionRemoteControlContractServerResponse ;;
    remote-control-deep) runRegressionRemoteControlDeep ;;
    *) return 2 ;;
    esac
}

runRegressionRemoteControl() {
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionRemoteControlSuiteSelector \
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-default-${BASHPID:-$$}" \
        listRegressionRemoteControlChildSelectors
}

runRegressionRemoteControlSuiteRoot() {
    runRegressionRemoteControl
}

listRegressionRemoteControlSmokeRefreshApplyChildSelectors() {
    printf '%s\n' \
        remote-control-smoke-refresh-apply-basic \
        remote-control-smoke-refresh-apply-prepare \
        remote-control-smoke-refresh-apply-failure
}

listRegressionRemoteControlSmokeRefreshChildSelectors() {
    printf '%s\n' \
        remote-control-smoke-refresh-apply \
        remote-control-smoke-refresh-restore \
        remote-control-smoke-refresh-reconcile
}

listRegressionRemoteControlSmokeChildSelectors() {
    printf '%s\n' \
        remote-control-smoke-core \
        remote-control-smoke-refresh
}

listRegressionRemoteControlContractServiceInstallChildSelectors() {
    printf '%s\n' \
        remote-control-contract-service-install-success \
        remote-control-contract-service-install-systemctl-fail \
        remote-control-contract-service-install-health-fail \
        remote-control-contract-service-install-health-rollback \
        remote-control-contract-service-install-token-transaction
}

listRegressionRemoteControlContractChildSelectors() {
    printf '%s\n' \
        remote-control-contract-service-install \
        remote-control-contract-server-response
}

runRegressionRemoteControlSmokeRefresh() {
    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-smoke-refresh" \
        listRegressionRemoteControlSmokeRefreshChildSelectors
}

runRegressionRemoteControlSmokeRefreshApply() {
    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-smoke-refresh-apply" \
        listRegressionRemoteControlSmokeRefreshApplyChildSelectors
}

runRegressionRemoteControlSmoke() {
    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-smoke" \
        listRegressionRemoteControlSmokeChildSelectors
}

runRegressionRemoteControlContract() {
    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-contract" \
        listRegressionRemoteControlContractChildSelectors
}

runRegressionRemoteControlContractServiceInstall() {
    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-contract-service-install" \
        listRegressionRemoteControlContractServiceInstallChildSelectors
}

runRegressionRemoteControlDeepStateRollbackNormalizationRegression() (
    set -euo pipefail
    local beforeFile="${TMP_DIR}/remote-control-deep-rollback-normalized.before.json"
    local afterFile="${TMP_DIR}/remote-control-deep-rollback-normalized.after.json"

    mkdir -p "$(dirname "$(subscriptionGroupsFile)")"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON

    normalizeSubscriptionGroupsState <"$(subscriptionGroupsFile)" | jq -S -c . >"${beforeFile}"
    subscriptionGroupsStateWrite '.groups |= .'
    normalizeSubscriptionGroupsState <"$(subscriptionGroupsFile)" | jq -S -c . >"${afterFile}"

    cmp -s "${beforeFile}" "${afterFile}"
)

registerRegressionFunctionLeaf remote-control-smoke-core runRegressionRemoteControlSmokeCore
registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-basic runRegressionRemoteControlSmokeRefreshApplyBasic
registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-prepare runRegressionRemoteControlSmokeRefreshApplyPrepare
registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-failure runRegressionRemoteControlSmokeRefreshApplyFailure
registerRegressionFunctionLeaf remote-control-smoke-refresh-restore runRegressionRemoteControlSmokeRefreshRestore
registerRegressionFunctionLeaf remote-control-smoke-refresh-reconcile runRegressionRemoteControlSmokeRefreshReconcile
registerRegressionFunctionLeaf remote-control-contract-service-install-success runRegressionRemoteControlContractServiceInstallSuccess
registerRegressionFunctionLeaf remote-control-contract-service-install-systemctl-fail runRegressionRemoteControlContractServiceInstallSystemctlFail
registerRegressionFunctionLeaf remote-control-contract-service-install-health-fail runRegressionRemoteControlContractServiceInstallHealthFail
registerRegressionFunctionLeaf remote-control-contract-service-install-health-rollback runRegressionRemoteControlContractServiceInstallHealthRollback
registerRegressionFunctionLeaf remote-control-contract-service-install-token-transaction runRegressionRemoteControlContractServiceInstallTokenTransaction
registerRegressionFunctionLeaf remote-control-contract-server-response runRegressionRemoteControlContractServerResponse
registerRegressionFunctionLeaf remote-control-deep runRegressionRemoteControlDeep
registerRegressionFunctionLeaf regression-remote-control-deep-state-rollback-normalization runRegressionRemoteControlDeepStateRollbackNormalizationRegression

listRegressionRemoteControlChildSelectors() {
    printf '%s\n' \
        remote-control-smoke \
        remote-control-contract \
        remote-control-deep
}

registerRegressionAggregateRunnerParallel remote-control-smoke-refresh-apply runRegressionRemoteControlSmokeRefreshApply \
    $(listRegressionRemoteControlSmokeRefreshApplyChildSelectors)
registerRegressionAggregateRunnerParallel remote-control-smoke-refresh runRegressionRemoteControlSmokeRefresh \
    $(listRegressionRemoteControlSmokeRefreshChildSelectors)
registerRegressionAggregateRunnerParallel remote-control-smoke runRegressionRemoteControlSmoke \
    $(listRegressionRemoteControlSmokeChildSelectors)
registerRegressionAggregateRunnerParallel remote-control-contract-service-install runRegressionRemoteControlContractServiceInstall \
    $(listRegressionRemoteControlContractServiceInstallChildSelectors)
registerRegressionAggregateRunnerParallel remote-control-contract runRegressionRemoteControlContract \
    $(listRegressionRemoteControlContractChildSelectors)
registerRegressionAggregateRunnerParallel remote-control runRegressionRemoteControlSuiteRoot \
    $(listRegressionRemoteControlChildSelectors)
