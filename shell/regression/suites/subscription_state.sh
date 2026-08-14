#!/usr/bin/env bash

REGRESSION_SUBSCRIPTION_STATE_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_SUBSCRIPTION_STATE_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_SUBSCRIPTION_STATE_SUITE_DIR}/../subscription_groups_subscription_state_full.sh"

runSubscriptionStateParallelChildRegressionIsolated() (
    local isolatedLabel=$1
    shift
    local isolatedRoot="${TMP_DIR}/${isolatedLabel}"

    unset PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER
    unset PADM_REGRESSION_PARALLEL_SELECTOR_MODE
    TMP_DIR="${isolatedRoot}"
    TMPDIR="${isolatedRoot}/tmp"
    export PADM_SUBSCRIPTION_GROUPS_DIR="${isolatedRoot}/groups"
    mkdir -p "${TMP_DIR}" "${TMPDIR}" "${PADM_SUBSCRIPTION_GROUPS_DIR}"
    "$@"
)

runSubscriptionStateParallelChildRegressionIsolatedSelector() {
    local selector=$1

    runSubscriptionStateParallelChildRegressionIsolated "${selector}" \
        runRegisteredRegressionMain "${selector}"
}

listRegressionSubscriptionStateStructureFoundationChildSelectors() {
    printf '%s\n' \
        subscription-state-structure-foundation-add-remove \
        subscription-state-structure-foundation-credential \
        subscription-state-structure-foundation-normalize \
        subscription-state-structure-foundation-init-transaction
}

listRegressionSubscriptionStateStructureValidationChildSelectors() {
    printf '%s\n' \
        subscription-state-structure-validation-serial
}

listRegressionSubscriptionStateStructureSourceChildSelectors() {
    printf '%s\n' \
        subscription-state-structure-source-credential \
        subscription-state-structure-source-status \
        subscription-state-structure-source-remove \
        subscription-state-structure-source-serial
}

listRegressionSubscriptionStateStructureChildSelectors() {
    printf '%s\n' \
        subscription-state-structure-foundation \
        subscription-state-structure-validation \
        subscription-state-structure-source
}

runRegressionSubscriptionStateStructure() {
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runSubscriptionStateParallelChildRegressionIsolatedSelector \
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-structure" \
            listRegressionSubscriptionStateStructureChildSelectors
}

listRegressionSubscriptionStateQuotaChildSelectors() {
    printf '%s\n' \
        subscription-state-quota-traffic \
        subscription-state-quota-menu-tx \
        subscription-state-quota-partial-sync
}

runRegressionSubscriptionStateQuota() {
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runSubscriptionStateParallelChildRegressionIsolatedSelector \
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-quota" \
            listRegressionSubscriptionStateQuotaChildSelectors
}

listRegressionSubscriptionStateQuotaTrafficChildSelectors() {
    printf '%s\n' \
        subscription-state-quota-traffic-summary \
        subscription-state-quota-traffic-invalid-input \
        subscription-state-quota-traffic-apply \
        subscription-state-quota-traffic-serial
}

listRegressionSubscriptionStateQuotaMenuTransactionChildSelectors() {
    printf '%s\n' \
        subscription-state-quota-menu-preview-fail \
        subscription-state-quota-menu-tx-rollback \
        subscription-state-quota-menu-tx-serial
}

listRegressionSubscriptionStateQuotaPartialSyncChildSelectors() {
    printf '%s\n' \
        subscription-state-quota-partial-sync-apply-failure \
        subscription-state-quota-partial-sync-plan \
        subscription-state-quota-partial-sync-config \
        subscription-state-quota-partial-sync-serial
}

listRegressionSubscriptionStateSupportChildSelectors() {
    printf '%s\n' \
        subscription-sync-tempdir \
        subscription-sync-restore-pair-failure-message \
        subscription-sync-append-restore-failure-detail \
        subscription-sync-single-restore-result-message \
        subscription-sync-rollback-result-message \
        subscription-sync-find-user-enabled-projection \
        subscription-sync-reconcile-early-exit \
        subscription-group-sync-publish-refresh-inline \
        subscription-group-sync-single-config-backup \
        subscription-groups-restore-failure
}

listRegressionSubscriptionStateSerialChildSelectors() {
    printf '%s\n' \
        subscription-state \
        subscription-sync-tempdir \
        subscription-sync-restore-pair-failure-message \
        subscription-sync-append-restore-failure-detail \
        subscription-sync-single-restore-result-message \
        subscription-sync-rollback-result-message \
        subscription-sync-rollback-failure-serial \
        subscription-sync-reconcile-early-exit \
        subscription-groups-restore-failure
}

listRegressionSubscriptionStateRemoteRestoreSelfReferenceChildSelectors() {
    printf '%s\n' \
        subscription-state-remote-restore-self-reference-plan \
        subscription-state-remote-restore-self-reference-sync
}

listRegressionSubscriptionStateRemoteRestoreSerialChildSelectors() {
    printf '%s\n' \
        subscription-state-remote-restore-self-reference \
        subscription-state-remote-restore-state-write \
        subscription-state-remote-restore-legacy-menu
}

listRegressionSubscriptionStateRemoteRestoreChildSelectors() {
    printf '%s\n' \
        subscription-state-remote-restore-self-reference \
        subscription-state-remote-restore-state-write \
        subscription-state-remote-restore-legacy-menu
}

runRegressionSubscriptionStateRemoteRestore() {
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runSubscriptionStateParallelChildRegressionIsolatedSelector \
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-remote-restore" \
            listRegressionSubscriptionStateRemoteRestoreChildSelectors
}

listRegressionSubscriptionStateSyncRollbackFailureSerialChildSelectors() {
    printf '%s\n' \
        subscription-sync-rollback-config-restore-failure \
        subscription-sync-restore-dir-failure \
        subscription-sync-reload-rollback \
        subscription-group-sync-rollback-serial
}

listRegressionSubscriptionStateSyncRollbackFailureChildSelectors() {
    printf '%s\n' \
        subscription-sync-rollback-config-restore-failure \
        subscription-sync-restore-dir-failure \
        subscription-sync-reload-rollback \
        subscription-group-sync-rollback
}

runRegressionSubscriptionStateSyncRollback() {
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runSubscriptionStateParallelChildRegressionIsolatedSelector \
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-sync-rollback-failure" \
            listRegressionSubscriptionStateSyncRollbackFailureChildSelectors
}

runRegressionSubscriptionStateParallelIsolationCompositionContract() (
    set -euo pipefail
    local contractName=$1
    local suiteRunner=$2
    local selectorListFn=$3
    local selectorPrefix=$4
    local waitingSelector=$5
    local signalingSelector=$6
    local callLog="${TMP_DIR}/regression-subscription-state-${contractName}-parallel-isolation-composition.log"
    local startMarker="${TMP_DIR}/subscription-state-${contractName}-parallel-started"
    local fullSelector selector
    local -a selectors=()

    mapfile -t selectors < <("${selectorListFn}")
    : >"${callLog}"
    rm -f "${startMarker}"

    runRegressionSubscriptionStateParallelIsolationProbe() {
        local selector=$1

        printf '%s|start|tmp=%s|groups=%s\n' \
            "${selector}" "${TMP_DIR}" "${PADM_SUBSCRIPTION_GROUPS_DIR:-}" >>"${callLog}"
        if [[ "${selector}" == "${waitingSelector}" ]]; then
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${startMarker}" ]] && break
                sleep 0.05
            done
        elif [[ "${selector}" == "${signalingSelector}" ]]; then
            : >"${startMarker}"
        fi
        printf '%s|finish|tmp=%s|groups=%s\n' \
            "${selector}" "${TMP_DIR}" "${PADM_SUBSCRIPTION_GROUPS_DIR:-}" >>"${callLog}"
    }

    runRegisteredRegressionMain() {
        runRegressionSubscriptionStateParallelIsolationProbe "${1#"${selectorPrefix}"}"
    }

    "${suiteRunner}"

    for fullSelector in "${selectors[@]}"; do
        selector=${fullSelector#"${selectorPrefix}"}
        grep -q "^${selector}|start|" "${callLog}"
        grep -q "^${selector}|finish|" "${callLog}"
    done
    awk -F'[|=]' -v waiting="${waitingSelector}" -v signaling="${signalingSelector}" '
        $1 == waiting && $2 == "start" { waitingStart = NR }
        $1 == signaling && $2 == "start" { signalingStart = NR }
        $1 == waiting && $2 == "finish" { waitingFinish = NR }
        END { exit !(waitingStart && signalingStart && waitingFinish && signalingStart < waitingFinish) }
    ' "${callLog}"
    awk -F'[|=]' -v expected="${#selectors[@]}" '
        $2 == "start" {
            tmp[$4] = 1
            groups[$6] = 1
            if (index($6, $4 "/groups") != 1) {
                bad = 1
            }
        }
        END { exit !(length(tmp) == expected && length(groups) == expected && !bad) }
    ' "${callLog}"
)

registerRegressionFunctionLeaf subscription-state-structure-foundation-add-remove runRegressionSubscriptionStateStructureFoundationAddRemove
registerRegressionFunctionLeaf subscription-state-structure-foundation-credential runRegressionSubscriptionStateStructureFoundationCredential
registerRegressionFunctionLeaf subscription-state-structure-foundation-normalize runRegressionSubscriptionStateStructureFoundationNormalize
registerRegressionFunctionLeaf subscription-state-structure-foundation-init-transaction runRegressionSubscriptionStateStructureFoundationInitTransaction
registerRegressionFunctionLeaf subscription-state-structure-foundation-serial runRegressionSubscriptionStateStructureFoundationSerial
registerRegressionAggregateRunnerWithArgs sequential \
    subscription-state-structure-validation \
    runFrameworkSequentialRegressionSelectorList \
    listRegressionSubscriptionStateStructureValidationChildSelectors \
    -- \
    $(listRegressionSubscriptionStateStructureValidationChildSelectors)
registerRegressionFunctionLeaf subscription-state-structure-validation-serial runRegressionSubscriptionStateStructureValidationSerial
registerRegressionAggregateRunnerWithArgs sequential \
    subscription-state-structure-source \
    runFrameworkSequentialRegressionSelectorList \
    listRegressionSubscriptionStateStructureSourceChildSelectors \
    -- \
    $(listRegressionSubscriptionStateStructureSourceChildSelectors)
registerRegressionFunctionLeaf subscription-state-structure-source-credential runRegressionSubscriptionStateStructureSourceCredential
registerRegressionFunctionLeaf subscription-state-structure-source-status runRegressionSubscriptionStateStructureSourceStatus
registerRegressionFunctionLeaf subscription-state-structure-source-remove runRegressionSubscriptionStateStructureSourceRemove
registerRegressionFunctionLeaf subscription-state-structure-source-serial runRegressionSubscriptionStateStructureSourceSerial
registerRegressionFunctionLeaf subscription-state-structure-serial runRegressionSubscriptionStateStructureSerial
registerRegressionFunctionLeaf subscription-state-quota-traffic-summary runRegressionSubscriptionStateQuotaTrafficSummary
registerRegressionFunctionLeaf subscription-state-quota-traffic-invalid-input runRegressionSubscriptionStateQuotaTrafficInvalidInput
registerRegressionFunctionLeaf subscription-state-quota-traffic-apply runRegressionSubscriptionStateQuotaTrafficApply
registerRegressionFunctionLeaf subscription-state-quota-traffic-serial runRegressionSubscriptionStateQuotaTrafficSerial
registerRegressionFunctionLeaf subscription-state-quota-menu-preview-fail runRegressionSubscriptionStateQuotaMenuPreviewFailure
registerRegressionFunctionLeaf subscription-state-quota-menu-tx-rollback runRegressionSubscriptionStateQuotaTransactionRollback
registerRegressionFunctionLeaf subscription-state-quota-menu-tx-serial runRegressionSubscriptionStateQuotaMenuTransactionSerial
registerRegressionFunctionLeaf subscription-state-quota-partial-sync-apply-failure runRegressionSubscriptionStateQuotaPartialSyncApplyFailure
registerRegressionFunctionLeaf subscription-state-quota-partial-sync-plan runRegressionSubscriptionStateQuotaPartialSyncPlan
registerRegressionFunctionLeaf subscription-state-quota-partial-sync-config runRegressionSubscriptionStateQuotaPartialSyncConfig
registerRegressionFunctionLeaf subscription-state-quota-partial-sync-serial runRegressionSubscriptionStateQuotaPartialSyncSerial
registerRegressionFunctionLeaf subscription-state-quota-serial runRegressionSubscriptionStateQuotaSerial
registerRegressionAggregateRunnerWithArgs sequential \
    subscription-state-remote-restore-self-reference \
    runFrameworkSequentialRegressionSelectorList \
    listRegressionSubscriptionStateRemoteRestoreSelfReferenceChildSelectors \
    -- \
    $(listRegressionSubscriptionStateRemoteRestoreSelfReferenceChildSelectors)
registerRegressionFunctionLeaf subscription-state-remote-restore-self-reference-plan runRegressionSubscriptionStateRemoteRestoreSelfReferencePlan
registerRegressionFunctionLeaf subscription-state-remote-restore-self-reference-sync runRegressionSubscriptionStateRemoteRestoreSelfReferenceSync
registerRegressionFunctionLeaf subscription-state-remote-restore-self-reference-serial runRegressionSubscriptionStateRemoteRestoreSelfReferenceSerial
registerRegressionFunctionLeaf subscription-state-remote-restore-state-write runRegressionSubscriptionStateRemoteRestoreStateWrite
registerRegressionFunctionLeaf subscription-state-remote-restore-legacy-menu runRegressionSubscriptionStateRemoteRestoreLegacyMenu
registerRegressionAggregateRunnerWithArgs sequential \
    subscription-state-serial \
    runFrameworkSequentialRegressionSelectorList \
    listRegressionSubscriptionStateSerialChildSelectors \
    -- \
    $(listRegressionSubscriptionStateSerialChildSelectors)
registerRegressionAggregateRunnerWithArgs sequential \
    subscription-state-quota-traffic \
    runFrameworkSequentialRegressionSelectorList \
    listRegressionSubscriptionStateQuotaTrafficChildSelectors \
    -- \
    $(listRegressionSubscriptionStateQuotaTrafficChildSelectors)
registerRegressionAggregateRunnerWithArgs sequential \
    subscription-state-quota-menu-tx \
    runFrameworkSequentialRegressionSelectorList \
    listRegressionSubscriptionStateQuotaMenuTransactionChildSelectors \
    -- \
    $(listRegressionSubscriptionStateQuotaMenuTransactionChildSelectors)
registerRegressionAggregateRunnerWithArgs sequential \
    subscription-state-quota-partial-sync \
    runFrameworkSequentialRegressionSelectorList \
    listRegressionSubscriptionStateQuotaPartialSyncChildSelectors \
    -- \
    $(listRegressionSubscriptionStateQuotaPartialSyncChildSelectors)
registerRegressionAggregateRunnerWithArgs sequential \
    subscription-state-remote-restore-serial \
    runFrameworkSequentialRegressionSelectorList \
    listRegressionSubscriptionStateRemoteRestoreSerialChildSelectors \
    -- \
    $(listRegressionSubscriptionStateRemoteRestoreSerialChildSelectors)
registerRegressionAggregateRunnerWithArgs sequential \
    subscription-state-support \
    runFrameworkSequentialRegressionSelectorList \
    listRegressionSubscriptionStateSupportChildSelectors \
    -- \
    $(listRegressionSubscriptionStateSupportChildSelectors)
registerRegressionAggregateRunnerWithArgs sequential \
    subscription-state-sync-rollback-serial \
    runFrameworkSequentialRegressionSelectorList \
    listRegressionSubscriptionStateSyncRollbackFailureSerialChildSelectors \
    -- \
    $(listRegressionSubscriptionStateSyncRollbackFailureSerialChildSelectors)
registerRegressionAggregateRunnerWithArgs sequential \
    subscription-sync-rollback-failure-serial \
    runFrameworkSequentialRegressionSelectorList \
    listRegressionSubscriptionStateSyncRollbackFailureSerialChildSelectors \
    -- \
    $(listRegressionSubscriptionStateSyncRollbackFailureSerialChildSelectors)
registerRegressionFunctionLeaf subscription-sync-tempdir runRegressionSubscriptionSyncTempDir
registerRegressionFunctionLeaf subscription-sync-restore-pair-failure-message runSubscriptionSyncRestorePairFailureMessageRegression
registerRegressionFunctionLeaf subscription-sync-append-restore-failure-detail runSubscriptionSyncAppendRestoreFailureDetailRegression
registerRegressionFunctionLeaf subscription-sync-single-restore-result-message runSubscriptionSyncSingleRestoreResultMessageRegression
registerRegressionFunctionLeaf subscription-sync-rollback-result-message runSubscriptionSyncRollbackResultMessageRegression
registerRegressionFunctionLeaf subscription-sync-find-user-enabled-projection runSubscriptionSyncFindUserEnabledProjectionRegression
registerRegressionFunctionLeaf subscription-sync-rollback-failure runRegressionSubscriptionStateSyncRollback
registerRegressionFunctionLeaf subscription-sync-rollback-config-restore-failure runRegressionSubscriptionSyncRollbackConfigRestoreFailure
registerRegressionFunctionLeaf subscription-sync-restore-dir-failure runRegressionSubscriptionSyncRollbackRestoreDirFailure
registerRegressionFunctionLeaf subscription-sync-reload-rollback runRegressionSubscriptionSyncRollbackReloadRollback
registerRegressionFunctionLeaf subscription-group-sync-rollback runRegressionSubscriptionGroupSyncRollback
registerRegressionFunctionLeaf subscription-group-sync-rollback-serial runRegressionSubscriptionGroupSyncRollbackSerial
registerRegressionFunctionLeaf subscription-group-sync-publish-refresh-inline runSubscriptionGroupSyncPublishRefreshInlineRegression
registerRegressionFunctionLeaf subscription-group-sync-single-config-backup runSubscriptionGroupSyncSingleConfigBackupRegression
registerRegressionFunctionLeaf subscription-group-sync-apply-failure runRegressionSubscriptionGroupSyncApplyFailure
registerRegressionFunctionLeaf subscription-group-sync-reconcile-rollback runRegressionSubscriptionGroupSyncReconcileRollback
registerRegressionFunctionLeaf subscription-group-sync-remote-failure runRegressionSubscriptionGroupSyncRemoteFailure
registerRegressionFunctionLeaf subscription-group-sync-state-lock runRegressionSubscriptionGroupSyncUsesStateLock
registerRegressionFunctionLeaf subscription-sync-reconcile-early-exit runRegressionSubscriptionSyncReconcileEarlyExit
registerRegressionFunctionLeaf subscription-groups-restore-failure runRegressionSubscriptionGroupsRestoreFailure
registerRegressionFunctionLeaf \
    regression-subscription-state-remote-restore-parallel-isolation-composition \
    runRegressionSubscriptionStateParallelIsolationCompositionContract \
    remote-restore \
    runRegressionSubscriptionStateRemoteRestore \
    listRegressionSubscriptionStateRemoteRestoreChildSelectors \
    subscription-state- \
    remote-restore-self-reference \
    remote-restore-state-write
registerRegressionFunctionLeaf \
    regression-subscription-state-structure-parallel-isolation-composition \
    runRegressionSubscriptionStateParallelIsolationCompositionContract \
    structure \
    runRegressionSubscriptionStateStructure \
    listRegressionSubscriptionStateStructureChildSelectors \
    subscription-state- \
    structure-foundation \
    structure-source
registerRegressionFunctionLeaf \
    regression-subscription-state-sync-rollback-parallel-isolation-composition \
    runRegressionSubscriptionStateParallelIsolationCompositionContract \
    sync-rollback \
    runRegressionSubscriptionStateSyncRollback \
    listRegressionSubscriptionStateSyncRollbackFailureChildSelectors \
    subscription- \
    sync-rollback-config-restore-failure \
    sync-reload-rollback

listRegressionSubscriptionStateCoreChildSelectors() {
    printf '%s\n' \
        subscription-state-structure \
        subscription-state-quota \
        subscription-state-remote-restore
}

listRegressionSubscriptionStateChildSelectors() {
    printf '%s\n' \
        subscription-state-core \
        subscription-state-support \
        subscription-state-sync-rollback
}

registerRegressionAggregateRunnerWithArgs parallel \
    subscription-state-structure-foundation \
    runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/subscription-state-structure-foundation" \
    listRegressionSubscriptionStateStructureFoundationChildSelectors \
    -- \
    $(listRegressionSubscriptionStateStructureFoundationChildSelectors)

registerRegressionAggregateRunner parallel subscription-state-structure runRegressionSubscriptionStateStructure \
    $(listRegressionSubscriptionStateStructureChildSelectors)

registerRegressionAggregateRunner parallel subscription-state-quota runRegressionSubscriptionStateQuota \
    $(listRegressionSubscriptionStateQuotaChildSelectors)

registerRegressionAggregateRunner parallel subscription-state-remote-restore runRegressionSubscriptionStateRemoteRestore \
    $(listRegressionSubscriptionStateRemoteRestoreChildSelectors)

registerRegressionAggregateRunner parallel subscription-state-sync-rollback runRegressionSubscriptionStateSyncRollback \
    $(listRegressionSubscriptionStateSyncRollbackFailureChildSelectors)

registerRegressionAggregateRunnerWithArgs parallel \
    subscription-state-core \
    runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/subscription-state-core-${BASHPID:-$$}" \
    listRegressionSubscriptionStateCoreChildSelectors \
    -- \
    $(listRegressionSubscriptionStateCoreChildSelectors)
registerRegressionAggregateRunnerWithArgs parallel \
    subscription-state \
    runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/subscription-state-default-${BASHPID:-$$}" \
    listRegressionSubscriptionStateChildSelectors \
    -- \
    $(listRegressionSubscriptionStateChildSelectors)
