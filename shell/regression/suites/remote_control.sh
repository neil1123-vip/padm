#!/usr/bin/env bash

REGRESSION_REMOTE_CONTROL_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_REMOTE_CONTROL_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_REMOTE_CONTROL_SUITE_DIR}/../subscription_groups_remote_control.sh"

runRegressionRemoteControlLegacyLeafWithCompat() (
    # Re-source legacy remote-control fixtures in an isolated subshell so later
    # suite loads cannot leave source-time TMP_DIR-derived paths stale.
    PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_REMOTE_CONTROL_SUITE_DIR}/../subscription_groups_remote_control.sh"
    "$@"
)

runRegressionRemoteControlSuiteSelector() {
    case "$1" in
    remote-control-smoke) runRegressionRemoteControlSmoke ;;
    remote-control-contract) runRegressionRemoteControlContract ;;
    remote-control-smoke-core) runRemoteControlSmokeCoreCompatRegression ;;
    remote-control-smoke-refresh) runRegressionRemoteControlSmokeRefresh ;;
    remote-control-smoke-refresh-apply) runRegressionRemoteControlSmokeRefreshApply ;;
    remote-control-smoke-refresh-apply-basic) runRemoteControlSmokeRefreshApplyBasicCompatRegression ;;
    remote-control-smoke-refresh-apply-prepare) runRemoteControlSmokeRefreshApplyPrepareCompatRegression ;;
    remote-control-smoke-refresh-apply-failure) runRemoteControlSmokeRefreshApplyFailureCompatRegression ;;
    remote-control-smoke-refresh-restore) runRemoteControlSmokeRefreshRestoreCompatRegression ;;
    remote-control-smoke-refresh-reconcile) runRemoteControlSmokeRefreshReconcileCompatRegression ;;
    remote-control-contract-service-install) runRegressionRemoteControlContractServiceInstall ;;
    remote-control-contract-service-install-success) runRemoteControlContractServiceInstallSuccessCompatRegression ;;
    remote-control-contract-service-install-systemctl-fail) runRemoteControlContractServiceInstallSystemctlFailCompatRegression ;;
    remote-control-contract-service-install-health-fail) runRemoteControlContractServiceInstallHealthFailCompatRegression ;;
    remote-control-contract-service-install-health-rollback) runRemoteControlContractServiceInstallHealthRollbackCompatRegression ;;
    remote-control-contract-service-install-token-transaction) runRemoteControlContractServiceInstallTokenTransactionCompatRegression ;;
    remote-control-contract-server-response) runRemoteControlContractServerResponseCompatRegression ;;
    remote-control-deep) runRemoteControlDeepCompatRegression ;;
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

runRemoteControlSmokeCoreCompatRegression() { runRegressionRemoteControlLegacyLeafWithCompat runRegressionRemoteControlSmokeCore; }
runRemoteControlSmokeRefreshApplyBasicCompatRegression() { runRegressionRemoteControlLegacyLeafWithCompat runRegressionRemoteControlSmokeRefreshApplyBasic; }
runRemoteControlSmokeRefreshApplyPrepareCompatRegression() { runRegressionRemoteControlLegacyLeafWithCompat runRegressionRemoteControlSmokeRefreshApplyPrepare; }
runRemoteControlSmokeRefreshApplyFailureCompatRegression() { runRegressionRemoteControlLegacyLeafWithCompat runRegressionRemoteControlSmokeRefreshApplyFailure; }
runRemoteControlSmokeRefreshRestoreCompatRegression() { runRegressionRemoteControlLegacyLeafWithCompat runRegressionRemoteControlSmokeRefreshRestore; }
runRemoteControlSmokeRefreshReconcileCompatRegression() { runRegressionRemoteControlLegacyLeafWithCompat runRegressionRemoteControlSmokeRefreshReconcile; }
runRemoteControlContractServiceInstallSuccessCompatRegression() { runRegressionRemoteControlLegacyLeafWithCompat runRegressionRemoteControlContractServiceInstallSuccess; }
runRemoteControlContractServiceInstallSystemctlFailCompatRegression() { runRegressionRemoteControlLegacyLeafWithCompat runRegressionRemoteControlContractServiceInstallSystemctlFail; }
runRemoteControlContractServiceInstallHealthFailCompatRegression() { runRegressionRemoteControlLegacyLeafWithCompat runRegressionRemoteControlContractServiceInstallHealthFail; }
runRemoteControlContractServiceInstallHealthRollbackCompatRegression() { runRegressionRemoteControlLegacyLeafWithCompat runRegressionRemoteControlContractServiceInstallHealthRollback; }
runRemoteControlContractServiceInstallTokenTransactionCompatRegression() { runRegressionRemoteControlLegacyLeafWithCompat runRegressionRemoteControlContractServiceInstallTokenTransaction; }
runRemoteControlContractServerResponseCompatRegression() { runRegressionRemoteControlLegacyLeafWithCompat runRegressionRemoteControlContractServerResponse; }
runRemoteControlDeepCompatRegression() { runRegressionRemoteControlLegacyLeafWithCompat runRegressionRemoteControlDeep; }

runRegressionRemoteControlLegacyTmpDirIsolationRegression() (
    set -euo pipefail
    local originalTmpDir="${TMP_DIR}"

    # Simulate later suite loads re-sourcing bootstrap and drifting TMP_DIR.
    source "${REGRESSION_REMOTE_CONTROL_SUITE_DIR}/../bootstrap.sh"
    [[ "${TMP_DIR}" != "${originalTmpDir}" ]]

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain remote-control-contract-server-response
)

registerRegressionFunctionLeaf remote-control-smoke-core runRemoteControlSmokeCoreCompatRegression
registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-basic runRemoteControlSmokeRefreshApplyBasicCompatRegression
registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-prepare runRemoteControlSmokeRefreshApplyPrepareCompatRegression
registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-failure runRemoteControlSmokeRefreshApplyFailureCompatRegression
registerRegressionFunctionLeaf remote-control-smoke-refresh-restore runRemoteControlSmokeRefreshRestoreCompatRegression
registerRegressionFunctionLeaf remote-control-smoke-refresh-reconcile runRemoteControlSmokeRefreshReconcileCompatRegression
registerRegressionFunctionLeaf remote-control-contract-service-install-success runRemoteControlContractServiceInstallSuccessCompatRegression
registerRegressionFunctionLeaf remote-control-contract-service-install-systemctl-fail runRemoteControlContractServiceInstallSystemctlFailCompatRegression
registerRegressionFunctionLeaf remote-control-contract-service-install-health-fail runRemoteControlContractServiceInstallHealthFailCompatRegression
registerRegressionFunctionLeaf remote-control-contract-service-install-health-rollback runRemoteControlContractServiceInstallHealthRollbackCompatRegression
registerRegressionFunctionLeaf remote-control-contract-service-install-token-transaction runRemoteControlContractServiceInstallTokenTransactionCompatRegression
registerRegressionFunctionLeaf remote-control-contract-server-response runRemoteControlContractServerResponseCompatRegression
registerRegressionFunctionLeaf remote-control-deep runRemoteControlDeepCompatRegression
registerRegressionFunctionLeaf regression-remote-control-deep-state-rollback-normalization runRegressionRemoteControlDeepStateRollbackNormalizationRegression
registerRegressionFunctionLeaf regression-remote-control-legacy-tmpdir-isolation runRegressionRemoteControlLegacyTmpDirIsolationRegression

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
