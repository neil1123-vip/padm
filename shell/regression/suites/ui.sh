#!/usr/bin/env bash

REGRESSION_UI_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_UI_SUITE_DIR}/../subscription_groups_legacy.sh"

runRegressionUiSuiteRoot() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    if [[ "${PADM_REGRESSION_UI_RESOURCE_PROFILE:-}" == "all" ]]; then
        mapfile -t selectors < <(listRegressionUiAllProfileChildSelectors)
        selectorPairs=()
        for selector in "${selectors[@]}"; do
            selectorPairs+=("${selector}" "${selector}")
        done
        runParallelRegressionSelectors "${TMP_DIR}/ui-parallel-${BASHPID:-$$}" \
            "${selectorPairs[@]}"
        return
    fi

    mapfile -t selectors < <(listRegressionUiChildSelectors)
    selectorPairs=()
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    runParallelRegressionSelectors "${TMP_DIR}/ui-parallel-${BASHPID:-$$}" \
        "${selectorPairs[@]}"
}

registerRegressionFunctionLeaf ui-smoke runRegressionMenuSmoke
registerRegressionFunctionLeaf ui-full runRegressionMenuSmokeFull
registerRegressionFunctionLeaf menu-smoke-full-core runMenuSmokeFullCoreRegression
registerRegressionFunctionLeaf menu-smoke-full-subscription-main runMenuSmokeFullSubscriptionMainRegression
registerRegressionFunctionLeaf menu-smoke-full-subscription-main-entry runMenuSmokeFullSubscriptionMainEntryRegression
registerRegressionFunctionLeaf menu-smoke-full-subscription-main-publish runMenuSmokeFullSubscriptionMainPublishRegression
registerRegressionFunctionLeaf menu-smoke-full-subscription-main-publish-service runMenuSmokeFullSubscriptionMainPublishServiceRegression
registerRegressionFunctionLeaf menu-smoke-full-subscription-main-publish-user runMenuSmokeFullSubscriptionMainPublishUserRegression
registerRegressionFunctionLeaf menu-smoke-full-subscription-main-publish-user-empty runMenuSmokeFullSubscriptionMainPublishUserEmptyRegression
registerRegressionFunctionLeaf menu-smoke-full-subscription-main-publish-user-create runMenuSmokeFullSubscriptionMainPublishUserCreateRegression
registerRegressionFunctionLeaf menu-smoke-full-subscription-main-publish-user-inspect runMenuSmokeFullSubscriptionMainPublishUserInspectRegression
registerRegressionFunctionLeaf menu-smoke-full-subscription-main-publish-sync runMenuSmokeFullSubscriptionMainPublishSyncRegression
registerRegressionFunctionLeaf menu-smoke-full-subscription-main-publish-sync-skip runMenuSmokeFullSubscriptionMainPublishSyncSkipRegression
registerRegressionFunctionLeaf menu-smoke-full-subscription-main-publish-sync-enable runMenuSmokeFullSubscriptionMainPublishSyncEnableRegression
registerRegressionFunctionLeaf menu-smoke-full-subscription-main-maintenance runMenuSmokeFullSubscriptionMainMaintenanceRegression
registerRegressionFunctionLeaf menu-smoke-full-subscription-controlled runMenuSmokeFullSubscriptionControlledRegression
registerRegressionFunctionLeaf menu-smoke-full-core-maintenance runMenuSmokeFullCoreMaintenanceRegression
registerRegressionFunctionLeaf wireguard-menu-flow runRegressionWireGuardMenuFlow
registerRegressionFunctionLeaf wireguard-menu-flow-bootstrap runSubscriptionWireGuardMenuFlowBootstrapRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-transaction runSubscriptionWireGuardMenuFlowPeerTransactionRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-add-update runSubscriptionWireGuardMenuFlowPeerAddUpdateRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback runSubscriptionWireGuardMenuFlowPeerRollbackRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-apply runSubscriptionWireGuardMenuFlowPeerRollbackApplyRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-apply-service runSubscriptionWireGuardMenuFlowPeerRollbackApplyServiceRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-apply-restore runSubscriptionWireGuardMenuFlowPeerRollbackApplyRestoreRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-source runSubscriptionWireGuardMenuFlowPeerRollbackSourceRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-credential runSubscriptionWireGuardMenuFlowPeerRollbackCredentialRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-credential-write runSubscriptionWireGuardMenuFlowPeerRollbackCredentialWriteRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-credential-groups-restore runSubscriptionWireGuardMenuFlowPeerRollbackCredentialGroupsRestoreRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-source-control runSubscriptionWireGuardMenuFlowPeerSourceControlRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-source-control-toggle runSubscriptionWireGuardMenuFlowPeerSourceControlToggleRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-source-control-clear-error runSubscriptionWireGuardMenuFlowPeerSourceControlClearErrorRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-source-control-status runSubscriptionWireGuardMenuFlowPeerSourceControlStatusRegression
registerRegressionFunctionLeaf wireguard-menu-flow-control-restore runSubscriptionWireGuardMenuFlowControlRestoreRegression
registerRegressionFunctionLeaf wireguard-restore-runner runSubscriptionWireGuardRestoreRunnerRegression

registerRegressionAggregateRunnerParallel ui runRegressionUiSuiteRoot \
    $(listRegressionUiChildSelectors)
