#!/usr/bin/env bash

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
        remote-control-sources-parsed-once \
        remote-control-health \
        remote-control-inline-request-helpers \
        remote-control-inline-wireguard-peer-helpers \
        remote-control-inline-token-consumers \
        remote-control-inline-sync-runner \
        remote-control-inline-sync-parallel-runner \
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

runRegressionRemoteControlDeepStateRollbackStabilityRegression() (
    set -euo pipefail
    local beforeFile="${TMP_DIR}/remote-control-deep-rollback-stable.before.json"
    local afterFile="${TMP_DIR}/remote-control-deep-rollback-stable.after.json"

    mkdir -p "$(dirname "$(subscriptionGroupsFile)")"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON

    jq -S -c . "$(subscriptionGroupsFile)" >"${beforeFile}"
    subscriptionGroupsStateWrite '.groups |= .'
    jq -S -c . "$(subscriptionGroupsFile)" >"${afterFile}"

    cmp -s "${beforeFile}" "${afterFile}"
)

registerRegressionFunctionLeaf remote-control-concurrency runRemoteControlConcurrencyRegression
registerRegressionFunctionLeaf remote-control-aggregation-failure runRemoteControlAggregationFailureRegression
registerRegressionFunctionLeaf remote-control-inline-aggregation-helpers runRemoteControlInlineAggregationHelpersRegression
registerRegressionFunctionLeaf remote-control-sources-parsed-once runRemoteControlSourcesParsedOnceRegression
registerRegressionFunctionLeaf remote-control-health runRemoteControlHealthRegression
registerRegressionFunctionLeaf remote-control-inline-request-helpers runRemoteControlInlineRequestHelpersRegression
registerRegressionFunctionLeaf remote-control-inline-wireguard-peer-helpers runRemoteControlInlineWireGuardPeerHelpersRegression
registerRegressionFunctionLeaf remote-control-inline-token-consumers runRemoteControlInlineTokenConsumersRegression
registerRegressionFunctionLeaf remote-control-inline-sync-runner runRemoteControlInlineSyncRunnerRegression
registerRegressionFunctionLeaf remote-control-inline-sync-parallel-runner runRemoteControlInlineSyncParallelRunnerRegression
registerRegressionFunctionLeaf remote-control-handle-inline-helpers runRemoteControlHandleInlineHelpersRegression
registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-basic runRemoteControlServerRefreshLightApplyBasicRegression
registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-prepare runRemoteControlServerRefreshLightApplyPrepareRegression
registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-failure runRemoteControlServerRefreshLightApplyFailureRegression
registerRegressionFunctionLeaf remote-control-smoke-refresh-restore runRemoteControlServerRefreshLightRestoreRegression
registerRegressionFunctionLeaf remote-control-smoke-refresh-reconcile runRemoteControlServerRefreshLightReconcileRegression
registerRegressionFunctionLeaf remote-control-contract-service-install-success runRegressionStep remote-control-service-install-success runSubscriptionControlServiceInstallSuccessRegression
registerRegressionFunctionLeaf remote-control-contract-service-install-systemctl-fail runRegressionStep remote-control-service-install-systemctl-fail runSubscriptionControlServiceInstallSystemctlFailRegression
registerRegressionFunctionLeaf remote-control-contract-service-install-health-fail runRegressionStep remote-control-service-install-health-fail runSubscriptionControlServiceInstallHealthFailRegression
registerRegressionFunctionLeaf remote-control-contract-service-install-health-rollback runRegressionStep remote-control-service-install-health-rollback runSubscriptionControlServiceInstallHealthRollbackRegression
registerRegressionFunctionLeaf remote-control-contract-service-install-token-transaction runRegressionStep remote-control-service-install-token-transaction runSubscriptionControlTokenTransactionRegression
registerRegressionFunctionLeaf remote-control-contract-server-response runRegressionStep remote-control-server-response runSubscriptionControlServerResponseRegression
registerRegressionFunctionLeaf remote-control-deep runRegressionStep remote-control-server-refresh-deep runRemoteControlServerRefreshDeepRegression
registerRegressionFunctionLeaf regression-remote-control-deep-state-rollback-stability runRegressionRemoteControlDeepStateRollbackStabilityRegression

listRegressionRemoteControlChildSelectors() {
    printf '%s\n' \
        remote-control-smoke \
        remote-control-contract \
        remote-control-deep
}

registerRegressionParallelSelectorList remote-control-smoke-refresh-apply runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/remote-control-smoke-refresh-apply" listRegressionRemoteControlSmokeRefreshApplyChildSelectors
registerRegressionParallelSelectorList remote-control-smoke-refresh runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/remote-control-smoke-refresh" listRegressionRemoteControlSmokeRefreshChildSelectors
registerRegressionParallelSelectorList remote-control-smoke runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/remote-control-smoke" listRegressionRemoteControlSmokeChildSelectors
registerRegressionSequentialSelectorList remote-control-smoke-core listRegressionRemoteControlSmokeCoreChildSelectors
registerRegressionParallelSelectorList remote-control-contract-service-install runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/remote-control-contract-service-install" listRegressionRemoteControlContractServiceInstallChildSelectors
registerRegressionParallelSelectorList remote-control-contract runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/remote-control-contract" listRegressionRemoteControlContractChildSelectors
registerRegressionParallelSelectorList remote-control runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/remote-control-default-${BASHPID:-$$}" listRegressionRemoteControlChildSelectors
