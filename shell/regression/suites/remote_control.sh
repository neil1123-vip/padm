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
        remote-control-traffic-contract \
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

registerRegressionFunctionLeaf remote-control-concurrency runRemoteControlConcurrencyRegression
registerRegressionFunctionLeaf remote-control-aggregation-failure runRemoteControlAggregationFailureRegression
registerRegressionFunctionLeaf remote-control-inline-aggregation-helpers runRemoteControlInlineAggregationHelpersRegression
registerRegressionFunctionLeaf remote-control-sources-parsed-once runRemoteControlSourcesParsedOnceRegression
registerRegressionFunctionLeaf remote-control-health runRemoteControlHealthRegression
registerRegressionFunctionLeaf remote-control-inline-request-helpers runRemoteControlInlineRequestHelpersRegression
registerRegressionFunctionLeaf remote-control-inline-wireguard-peer-helpers runRemoteControlInlineWireGuardPeerHelpersRegression
registerRegressionFunctionLeaf remote-control-inline-token-consumers runRemoteControlInlineTokenConsumersRegression
registerRegressionFunctionLeaf remote-control-traffic-contract runRemoteControlTrafficContractRegression
registerRegressionFunctionLeaf remote-control-inline-sync-runner runRemoteControlInlineSyncRunnerRegression
registerRegressionFunctionLeaf remote-control-inline-sync-parallel-runner runRemoteControlInlineSyncParallelRunnerRegression
registerRegressionFunctionLeaf remote-control-handle-inline-helpers runRemoteControlHandleInlineHelpersRegression
registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-basic runRemoteControlServerRefreshRegression light apply-basic
registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-prepare runRemoteControlServerRefreshRegression light apply-prepare
registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-failure runRemoteControlServerRefreshRegression light apply-failure
registerRegressionFunctionLeaf remote-control-smoke-refresh-restore runRemoteControlServerRefreshRegression light restore
registerRegressionFunctionLeaf remote-control-smoke-refresh-reconcile runRemoteControlServerRefreshRegression light reconcile
registerRegressionFunctionLeaf remote-control-contract-service-install-success runRegressionStep remote-control-service-install-success runSubscriptionControlServiceInstallRegression success
registerRegressionFunctionLeaf remote-control-contract-service-install-systemctl-fail runRegressionStep remote-control-service-install-systemctl-fail runSubscriptionControlServiceInstallRegression systemctl-fail
registerRegressionFunctionLeaf remote-control-contract-service-install-health-fail runRegressionStep remote-control-service-install-health-fail runSubscriptionControlServiceInstallRegression health-fail
registerRegressionFunctionLeaf remote-control-contract-service-install-health-rollback runRegressionStep remote-control-service-install-health-rollback runSubscriptionControlServiceInstallRegression health-rollback
registerRegressionFunctionLeaf remote-control-contract-service-install-token-transaction runRegressionStep remote-control-service-install-token-transaction runSubscriptionControlTokenTransactionRegression
registerRegressionFunctionLeaf remote-control-contract-server-response runRegressionStep remote-control-server-response runSubscriptionControlServerResponseRegression
registerRegressionFunctionLeaf remote-control-deep runRegressionStep remote-control-server-refresh-deep runRemoteControlServerRefreshRegression deep

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
