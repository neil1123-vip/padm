#!/usr/bin/env bash

REGRESSION_SUBSCRIPTION_STATE_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_SUBSCRIPTION_STATE_SUITE_DIR}/../subscription_groups_subscription_state_full.sh"

runRegressionSubscriptionStateCore() {
    runParallelRegressionRunners \
        "${TMP_DIR}/subscription-state-core" \
        structure runRegressionSubscriptionStateStructure \
        quota runRegressionSubscriptionStateQuota \
        remote-restore runRegressionSubscriptionStateRemoteRestore
}

runRegressionSubscriptionStateCoreSuiteRoot() {
    runRegressionSubscriptionStateCore
}

runRegressionSubscriptionState() {
    runParallelRegressionRunners \
        "${TMP_DIR}/subscription-state-default" \
        core runRegressionSubscriptionStateCore \
        support runRegressionSubscriptionStateSupport \
        sync-rollback runRegressionSubscriptionStateSyncRollback
}

runRegressionSubscriptionStateSuiteRoot() {
    runRegressionSubscriptionState
}

runRegressionSubscriptionStateRemoteRestoreParallelIsolationCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-subscription-state-remote-restore-parallel-isolation-composition.log"
    local startMarker="${TMP_DIR}/subscription-state-remote-restore-state-write-started"

    : >"${callLog}"
    rm -f "${startMarker}"

    runRegressionSubscriptionStateRemoteRestoreParallelIsolationProbe() {
        local selector=$1

        printf '%s|start|tmp=%s|groups=%s\n' \
            "${selector}" "${TMP_DIR}" "${PADM_SUBSCRIPTION_GROUPS_DIR:-}" >>"${callLog}"
        if [[ "${selector}" == "remote-restore-self-reference" ]]; then
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${startMarker}" ]] && break
                sleep 0.05
            done
        elif [[ "${selector}" == "remote-restore-state-write" ]]; then
            : >"${startMarker}"
        fi
        printf '%s|finish|tmp=%s|groups=%s\n' \
            "${selector}" "${TMP_DIR}" "${PADM_SUBSCRIPTION_GROUPS_DIR:-}" >>"${callLog}"
    }

    runRegressionSubscriptionStateRemoteRestoreSelfReference() {
        runRegressionSubscriptionStateRemoteRestoreParallelIsolationProbe remote-restore-self-reference
    }

    runRegressionSubscriptionStateRemoteRestoreStateWrite() {
        runRegressionSubscriptionStateRemoteRestoreParallelIsolationProbe remote-restore-state-write
    }

    runRegressionSubscriptionStateRemoteRestoreLegacyMenu() {
        runRegressionSubscriptionStateRemoteRestoreParallelIsolationProbe remote-restore-legacy-menu
    }

    runSubscriptionGroupStateRemoteRestoreRegression

    for selector in remote-restore-self-reference remote-restore-state-write remote-restore-legacy-menu; do
        grep -q "^${selector}|start|" "${callLog}"
        grep -q "^${selector}|finish|" "${callLog}"
    done
    awk -F'[|=]' '
        $1 == "remote-restore-self-reference" && $2 == "start" { selfStart = NR }
        $1 == "remote-restore-state-write" && $2 == "start" { stateWriteStart = NR }
        $1 == "remote-restore-self-reference" && $2 == "finish" { selfFinish = NR }
        END { exit !(selfStart && stateWriteStart && selfFinish && stateWriteStart < selfFinish) }
    ' "${callLog}"
    awk -F'[|=]' '
        $2 == "start" {
            tmp[$4] = 1
            groups[$6] = 1
            if (index($6, $4 "/groups") != 1) {
                bad = 1
            }
        }
        END { exit !(length(tmp) == 3 && length(groups) == 3 && !bad) }
    ' "${callLog}"
)

runRegressionSubscriptionStateStructureParallelIsolationCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-subscription-state-structure-parallel-isolation-composition.log"
    local startMarker="${TMP_DIR}/subscription-state-structure-source-started"

    : >"${callLog}"
    rm -f "${startMarker}"

    runRegressionSubscriptionStateStructureParallelIsolationProbe() {
        local selector=$1

        printf '%s|start|tmp=%s|groups=%s\n' \
            "${selector}" "${TMP_DIR}" "${PADM_SUBSCRIPTION_GROUPS_DIR:-}" >>"${callLog}"
        if [[ "${selector}" == "structure-foundation" ]]; then
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${startMarker}" ]] && break
                sleep 0.05
            done
        elif [[ "${selector}" == "structure-source" ]]; then
            : >"${startMarker}"
        fi
        printf '%s|finish|tmp=%s|groups=%s\n' \
            "${selector}" "${TMP_DIR}" "${PADM_SUBSCRIPTION_GROUPS_DIR:-}" >>"${callLog}"
    }

    runRegressionSubscriptionStateStructureFoundation() {
        runRegressionSubscriptionStateStructureParallelIsolationProbe structure-foundation
    }

    runRegressionSubscriptionStateStructureMigration() {
        runRegressionSubscriptionStateStructureParallelIsolationProbe structure-migration
    }

    runRegressionSubscriptionStateStructureSource() {
        runRegressionSubscriptionStateStructureParallelIsolationProbe structure-source
    }

    runSubscriptionGroupStateStructureRegression

    for selector in structure-foundation structure-migration structure-source; do
        grep -q "^${selector}|start|" "${callLog}"
        grep -q "^${selector}|finish|" "${callLog}"
    done
    awk -F'[|=]' '
        $1 == "structure-foundation" && $2 == "start" { foundationStart = NR }
        $1 == "structure-source" && $2 == "start" { sourceStart = NR }
        $1 == "structure-foundation" && $2 == "finish" { foundationFinish = NR }
        END { exit !(foundationStart && sourceStart && foundationFinish && sourceStart < foundationFinish) }
    ' "${callLog}"
    awk -F'[|=]' '
        $2 == "start" {
            tmp[$4] = 1
            groups[$6] = 1
            if (index($6, $4 "/groups") != 1) {
                bad = 1
            }
        }
        END { exit !(length(tmp) == 3 && length(groups) == 3 && !bad) }
    ' "${callLog}"
)

registerRegressionFunctionLeaf subscription-state-serial runRegressionSubscriptionStateSerial
registerRegressionFunctionLeaf subscription-state-structure runRegressionSubscriptionStateStructure
registerRegressionFunctionLeaf subscription-state-structure-foundation runRegressionSubscriptionStateStructureFoundation
registerRegressionFunctionLeaf subscription-state-structure-foundation-add-remove runRegressionSubscriptionStateStructureFoundationAddRemove
registerRegressionFunctionLeaf subscription-state-structure-foundation-credential runRegressionSubscriptionStateStructureFoundationCredential
registerRegressionFunctionLeaf subscription-state-structure-foundation-normalize runRegressionSubscriptionStateStructureFoundationNormalize
registerRegressionFunctionLeaf subscription-state-structure-foundation-init-transaction runRegressionSubscriptionStateStructureFoundationInitTransaction
registerRegressionFunctionLeaf subscription-state-structure-foundation-serial runRegressionSubscriptionStateStructureFoundationSerial
registerRegressionFunctionLeaf subscription-state-structure-migration runRegressionSubscriptionStateStructureMigration
registerRegressionFunctionLeaf subscription-state-structure-source runRegressionSubscriptionStateStructureSource
registerRegressionFunctionLeaf subscription-state-structure-source-credential runRegressionSubscriptionStateStructureSourceCredential
registerRegressionFunctionLeaf subscription-state-structure-source-status runRegressionSubscriptionStateStructureSourceStatus
registerRegressionFunctionLeaf subscription-state-structure-source-remove runRegressionSubscriptionStateStructureSourceRemove
registerRegressionFunctionLeaf subscription-state-structure-source-serial runRegressionSubscriptionStateStructureSourceSerial
registerRegressionFunctionLeaf subscription-state-structure-serial runRegressionSubscriptionStateStructureSerial
registerRegressionFunctionLeaf subscription-state-quota runRegressionSubscriptionStateQuota
registerRegressionFunctionLeaf subscription-state-quota-traffic runRegressionSubscriptionStateQuotaTraffic
registerRegressionFunctionLeaf subscription-state-quota-traffic-summary runRegressionSubscriptionStateQuotaTrafficSummary
registerRegressionFunctionLeaf subscription-state-quota-traffic-invalid-input runRegressionSubscriptionStateQuotaTrafficInvalidInput
registerRegressionFunctionLeaf subscription-state-quota-traffic-apply runRegressionSubscriptionStateQuotaTrafficApply
registerRegressionFunctionLeaf subscription-state-quota-traffic-serial runRegressionSubscriptionStateQuotaTrafficSerial
registerRegressionFunctionLeaf subscription-state-quota-menu-preview-fail runRegressionSubscriptionStateQuotaMenuPreviewFailure
registerRegressionFunctionLeaf subscription-state-quota-menu-tx runRegressionSubscriptionStateQuotaMenuTransaction
registerRegressionFunctionLeaf subscription-state-quota-menu-tx-rollback runRegressionSubscriptionStateQuotaTransactionRollback
registerRegressionFunctionLeaf subscription-state-quota-menu-tx-serial runRegressionSubscriptionStateQuotaMenuTransactionSerial
registerRegressionFunctionLeaf subscription-state-quota-partial-sync runRegressionSubscriptionStateQuotaPartialSync
registerRegressionFunctionLeaf subscription-state-quota-partial-sync-apply-failure runRegressionSubscriptionStateQuotaPartialSyncApplyFailure
registerRegressionFunctionLeaf subscription-state-quota-partial-sync-plan runRegressionSubscriptionStateQuotaPartialSyncPlan
registerRegressionFunctionLeaf subscription-state-quota-partial-sync-config runRegressionSubscriptionStateQuotaPartialSyncConfig
registerRegressionFunctionLeaf subscription-state-quota-partial-sync-serial runRegressionSubscriptionStateQuotaPartialSyncSerial
registerRegressionFunctionLeaf subscription-state-quota-serial runRegressionSubscriptionStateQuotaSerial
registerRegressionFunctionLeaf subscription-state-remote-restore runRegressionSubscriptionStateRemoteRestore
registerRegressionFunctionLeaf subscription-state-remote-restore-self-reference runRegressionSubscriptionStateRemoteRestoreSelfReference
registerRegressionFunctionLeaf subscription-state-remote-restore-self-reference-plan runRegressionSubscriptionStateRemoteRestoreSelfReferencePlan
registerRegressionFunctionLeaf subscription-state-remote-restore-self-reference-sync runRegressionSubscriptionStateRemoteRestoreSelfReferenceSync
registerRegressionFunctionLeaf subscription-state-remote-restore-self-reference-serial runRegressionSubscriptionStateRemoteRestoreSelfReferenceSerial
registerRegressionFunctionLeaf subscription-state-remote-restore-state-write runRegressionSubscriptionStateRemoteRestoreStateWrite
registerRegressionFunctionLeaf subscription-state-remote-restore-legacy-menu runRegressionSubscriptionStateRemoteRestoreLegacyMenu
registerRegressionFunctionLeaf subscription-state-remote-restore-serial runRegressionSubscriptionStateRemoteRestoreSerial
registerRegressionFunctionLeaf subscription-state-support runRegressionSubscriptionStateSupport
registerRegressionFunctionLeaf subscription-state-sync-rollback runRegressionSubscriptionStateSyncRollback
registerRegressionFunctionLeaf subscription-state-sync-rollback-serial runRegressionSubscriptionStateSyncRollbackSerial
registerRegressionFunctionLeaf subscription-sync-tempdir runRegressionSubscriptionSyncTempDir
registerRegressionFunctionLeaf subscription-sync-rollback-failure runRegressionSubscriptionStateSyncRollback
registerRegressionFunctionLeaf subscription-sync-rollback-failure-serial runRegressionSubscriptionStateSyncRollbackSerial
registerRegressionFunctionLeaf subscription-sync-rollback-config-restore-failure runRegressionSubscriptionSyncRollbackConfigRestoreFailure
registerRegressionFunctionLeaf subscription-sync-restore-dir-failure runRegressionSubscriptionSyncRollbackRestoreDirFailure
registerRegressionFunctionLeaf subscription-sync-reload-rollback runRegressionSubscriptionSyncRollbackReloadRollback
registerRegressionFunctionLeaf subscription-group-sync-rollback runRegressionSubscriptionGroupSyncRollback
registerRegressionFunctionLeaf subscription-group-sync-rollback-serial runRegressionSubscriptionGroupSyncRollbackSerial
registerRegressionFunctionLeaf subscription-group-sync-apply-failure runRegressionSubscriptionGroupSyncApplyFailure
registerRegressionFunctionLeaf subscription-group-sync-reconcile-rollback runRegressionSubscriptionGroupSyncReconcileRollback
registerRegressionFunctionLeaf subscription-group-sync-remote-failure runRegressionSubscriptionGroupSyncRemoteFailure
registerRegressionFunctionLeaf subscription-sync-reconcile-early-exit runRegressionSubscriptionSyncReconcileEarlyExit
registerRegressionFunctionLeaf subscription-groups-restore-failure runRegressionSubscriptionGroupsRestoreFailure
registerRegressionFunctionLeaf regression-subscription-state-remote-restore-parallel-isolation-composition runRegressionSubscriptionStateRemoteRestoreParallelIsolationCompositionRegression
registerRegressionFunctionLeaf regression-subscription-state-structure-parallel-isolation-composition runRegressionSubscriptionStateStructureParallelIsolationCompositionRegression

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

registerRegressionAggregateRunnerParallel subscription-state-core runRegressionSubscriptionStateCoreSuiteRoot \
    $(listRegressionSubscriptionStateCoreChildSelectors)
registerRegressionAggregateRunnerParallel subscription-state runRegressionSubscriptionStateSuiteRoot \
    $(listRegressionSubscriptionStateChildSelectors)
