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

runRegressionRemoteControl() {
    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-default-${BASHPID:-$$}" \
        listRegressionRemoteControlChildSelectors
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

listRegressionRemoteControlSmokeCoreChildSelectors() {
    printf '%s\n' \
        remote-control-concurrency \
        remote-control-aggregation-failure \
        remote-control-inline-aggregation-helpers \
        remote-control-health \
        remote-control-inline-request-helpers \
        remote-control-inline-wireguard-peer-helpers \
        remote-control-inline-token-consumers \
        remote-control-inline-sync-runner \
        remote-control-handle-inline-helpers
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

runRegressionRemoteControlSmokeCore() {
    runFrameworkSequentialRegressionSelectorList listRegressionRemoteControlSmokeCoreChildSelectors
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

runRegressionRemoteControlConcurrency() {
    runRegressionStep remote-control-concurrency runRemoteControlConcurrencyRegression
}

runRegressionRemoteControlAggregationFailure() {
    runRegressionStep remote-control-aggregation-failure runRemoteControlAggregationFailureRegression
}

runRegressionRemoteControlInlineAggregationHelpers() {
    runRegressionStep remote-control-inline-aggregation-helpers runRemoteControlInlineAggregationHelpersRegression
}

runRegressionRemoteControlHealth() {
    runRegressionStep remote-control-health runRemoteControlHealthRegression
}

runRegressionRemoteControlInlineRequestHelpers() {
    runRegressionStep remote-control-inline-request-helpers runRemoteControlInlineRequestHelpersRegression
}

runRegressionRemoteControlInlineWireGuardPeerHelpers() {
    runRegressionStep remote-control-inline-wireguard-peer-helpers runRemoteControlInlineWireGuardPeerHelpersRegression
}

runRegressionRemoteControlInlineTokenConsumers() {
    runRegressionStep remote-control-inline-token-consumers runRemoteControlInlineTokenConsumersRegression
}

runRegressionRemoteControlInlineSyncRunner() {
    runRegressionStep remote-control-inline-sync-runner runRemoteControlInlineSyncRunnerRegression
}

runRegressionRemoteControlHandleInlineHelpers() {
    runRegressionStep remote-control-handle-inline-helpers runRemoteControlHandleInlineHelpersRegression
}

runRegressionRemoteControlSmokeRefreshApplyBasic() {
    runRegressionStep remote-control-server-refresh-light-apply-basic runRemoteControlServerRefreshLightApplyBasicRegression
}

runRegressionRemoteControlSmokeRefreshApplyPrepare() {
    runRegressionStep remote-control-server-refresh-light-apply-prepare runRemoteControlServerRefreshLightApplyPrepareRegression
}

runRegressionRemoteControlSmokeRefreshApplyFailure() {
    runRegressionStep remote-control-server-refresh-light-apply-failure runRemoteControlServerRefreshLightApplyFailureRegression
}

runRegressionRemoteControlSmokeRefreshRestore() {
    runRegressionStep remote-control-server-refresh-light-restore runRemoteControlServerRefreshLightRestoreRegression
}

runRegressionRemoteControlSmokeRefreshReconcile() {
    runRegressionStep remote-control-server-refresh-light-reconcile runRemoteControlServerRefreshLightReconcileRegression
}

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

registerRegressionFunctionLeaf remote-control-smoke-core runRegressionRemoteControlSmokeCore
registerRegressionFunctionLeaf remote-control-concurrency runRegressionRemoteControlConcurrency
registerRegressionFunctionLeaf remote-control-aggregation-failure runRegressionRemoteControlAggregationFailure
registerRegressionFunctionLeaf remote-control-inline-aggregation-helpers runRegressionRemoteControlInlineAggregationHelpers
registerRegressionFunctionLeaf remote-control-health runRegressionRemoteControlHealth
registerRegressionFunctionLeaf remote-control-inline-request-helpers runRegressionRemoteControlInlineRequestHelpers
registerRegressionFunctionLeaf remote-control-inline-wireguard-peer-helpers runRegressionRemoteControlInlineWireGuardPeerHelpers
registerRegressionFunctionLeaf remote-control-inline-token-consumers runRegressionRemoteControlInlineTokenConsumers
registerRegressionFunctionLeaf remote-control-inline-sync-runner runRegressionRemoteControlInlineSyncRunner
registerRegressionFunctionLeaf remote-control-handle-inline-helpers runRegressionRemoteControlHandleInlineHelpers
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
registerRegressionAggregateRunnerParallel remote-control runRegressionRemoteControl \
    $(listRegressionRemoteControlChildSelectors)
