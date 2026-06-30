#!/usr/bin/env bash

REGRESSION_SUBSCRIPTION_STATE_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_SUBSCRIPTION_STATE_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_SUBSCRIPTION_STATE_SUITE_DIR}/../subscription_groups_subscription_state_full.sh"

runRegressionSubscriptionStateCore() {
    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-core-${BASHPID:-$$}" \
        listRegressionSubscriptionStateCoreChildSelectors
}

runRegressionSubscriptionStateCoreSuiteRoot() {
    runRegressionSubscriptionStateCore
}

runRegressionSubscriptionState() {
    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-default-${BASHPID:-$$}" \
        listRegressionSubscriptionStateChildSelectors
}

runRegressionSubscriptionStateSuiteRoot() {
    runRegressionSubscriptionState
}

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

listRegressionSubscriptionStateStructureFoundationChildSelectors() {
    printf '%s\n' \
        subscription-state-structure-foundation-add-remove \
        subscription-state-structure-foundation-credential \
        subscription-state-structure-foundation-normalize \
        subscription-state-structure-foundation-init-transaction
}

runRegressionSubscriptionStateStructureFoundation() {
    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-structure-foundation" \
        listRegressionSubscriptionStateStructureFoundationChildSelectors
}

runRegressionSubscriptionStateStructureFoundationIsolated() {
    runSubscriptionStateParallelChildRegressionIsolated subscription-state-structure-foundation runRegressionSubscriptionStateStructureFoundation
}

runRegressionSubscriptionStateStructureMigration() {
    runRegressionStep subscription-state-structure-migration runSubscriptionGroupStateStructureMigrationRegression
}

runRegressionSubscriptionStateStructureMigrationIsolated() {
    runSubscriptionStateParallelChildRegressionIsolated subscription-state-structure-migration runRegressionSubscriptionStateStructureMigration
}

listRegressionSubscriptionStateStructureSourceChildSelectors() {
    printf '%s\n' \
        subscription-state-structure-source-credential \
        subscription-state-structure-source-status \
        subscription-state-structure-source-remove \
        subscription-state-structure-source-serial
}

runRegressionSubscriptionStateStructureSource() {
    runFrameworkSequentialRegressionSelectorList listRegressionSubscriptionStateStructureSourceChildSelectors
}

runRegressionSubscriptionStateStructureSourceIsolated() {
    runSubscriptionStateParallelChildRegressionIsolated subscription-state-structure-source runRegressionSubscriptionStateStructureSource
}

listRegressionSubscriptionStateStructureChildSelectors() {
    printf '%s\n' \
        subscription-state-structure-foundation \
        subscription-state-structure-migration \
        subscription-state-structure-source
}

runRegressionSubscriptionStateStructureSelector() {
    case "$1" in
    subscription-state-structure-foundation) runRegressionSubscriptionStateStructureFoundationIsolated ;;
    subscription-state-structure-migration) runRegressionSubscriptionStateStructureMigrationIsolated ;;
    subscription-state-structure-source) runRegressionSubscriptionStateStructureSourceIsolated ;;
    *) return 2 ;;
    esac
}

runRegressionSubscriptionStateStructure() {
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionSubscriptionStateStructureSelector \
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-structure" \
            listRegressionSubscriptionStateStructureChildSelectors
}

listRegressionSubscriptionStateQuotaChildSelectors() {
    printf '%s\n' \
        subscription-state-quota-traffic \
        subscription-state-quota-menu-tx \
        subscription-state-quota-partial-sync
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

runRegressionSubscriptionStateQuotaTraffic() {
    runFrameworkSequentialRegressionSelectorList listRegressionSubscriptionStateQuotaTrafficChildSelectors
}

runRegressionSubscriptionStateQuotaMenuTransaction() {
    runFrameworkSequentialRegressionSelectorList listRegressionSubscriptionStateQuotaMenuTransactionChildSelectors
}

runRegressionSubscriptionStateQuotaPartialSync() {
    runFrameworkSequentialRegressionSelectorList listRegressionSubscriptionStateQuotaPartialSyncChildSelectors
}

runRegressionSubscriptionStateQuota() {
    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-quota" \
        listRegressionSubscriptionStateQuotaChildSelectors
}

runRegressionSubscriptionStateRemoteRestoreSelfReferenceIsolated() {
    runSubscriptionStateParallelChildRegressionIsolated subscription-state-remote-restore-self-reference runRegressionSubscriptionStateRemoteRestoreSelfReference
}

runRegressionSubscriptionStateRemoteRestoreStateWriteIsolated() {
    runSubscriptionStateParallelChildRegressionIsolated subscription-state-remote-restore-state-write runRegressionSubscriptionStateRemoteRestoreStateWrite
}

runRegressionSubscriptionStateRemoteRestoreLegacyMenuIsolated() {
    runSubscriptionStateParallelChildRegressionIsolated subscription-state-remote-restore-legacy-menu runRegressionSubscriptionStateRemoteRestoreLegacyMenu
}

listRegressionSubscriptionStateRemoteRestoreChildSelectors() {
    printf '%s\n' \
        subscription-state-remote-restore-self-reference \
        subscription-state-remote-restore-state-write \
        subscription-state-remote-restore-legacy-menu
}

runRegressionSubscriptionStateRemoteRestoreSelector() {
    case "$1" in
    subscription-state-remote-restore-self-reference) runRegressionSubscriptionStateRemoteRestoreSelfReferenceIsolated ;;
    subscription-state-remote-restore-state-write) runRegressionSubscriptionStateRemoteRestoreStateWriteIsolated ;;
    subscription-state-remote-restore-legacy-menu) runRegressionSubscriptionStateRemoteRestoreLegacyMenuIsolated ;;
    *) return 2 ;;
    esac
}

runRegressionSubscriptionStateRemoteRestore() {
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionSubscriptionStateRemoteRestoreSelector \
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-remote-restore" \
            listRegressionSubscriptionStateRemoteRestoreChildSelectors
}

runRegressionSubscriptionSyncRollbackConfigRestoreFailureIsolated() {
    runSubscriptionStateParallelChildRegressionIsolated subscription-sync-rollback-config-restore-failure runRegressionSubscriptionSyncRollbackConfigRestoreFailure
}

runRegressionSubscriptionSyncRollbackRestoreDirFailureIsolated() {
    runSubscriptionStateParallelChildRegressionIsolated subscription-sync-restore-dir-failure runRegressionSubscriptionSyncRollbackRestoreDirFailure
}

runRegressionSubscriptionSyncRollbackReloadRollbackIsolated() {
    runSubscriptionStateParallelChildRegressionIsolated subscription-sync-reload-rollback runRegressionSubscriptionSyncRollbackReloadRollback
}

runRegressionSubscriptionGroupSyncRollbackIsolated() {
    runSubscriptionStateParallelChildRegressionIsolated subscription-group-sync-rollback runRegressionSubscriptionGroupSyncRollback
}

listRegressionSubscriptionStateSyncRollbackFailureChildSelectors() {
    printf '%s\n' \
        subscription-sync-rollback-config-restore-failure \
        subscription-sync-restore-dir-failure \
        subscription-sync-reload-rollback \
        subscription-group-sync-rollback
}

runRegressionSubscriptionStateSyncRollbackFailureSelector() {
    case "$1" in
    subscription-sync-rollback-config-restore-failure) runRegressionSubscriptionSyncRollbackConfigRestoreFailureIsolated ;;
    subscription-sync-restore-dir-failure) runRegressionSubscriptionSyncRollbackRestoreDirFailureIsolated ;;
    subscription-sync-reload-rollback) runRegressionSubscriptionSyncRollbackReloadRollbackIsolated ;;
    subscription-group-sync-rollback) runRegressionSubscriptionGroupSyncRollbackIsolated ;;
    *) return 2 ;;
    esac
}

runRegressionSubscriptionStateSyncRollback() {
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionSubscriptionStateSyncRollbackFailureSelector \
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-sync-rollback-failure" \
            listRegressionSubscriptionStateSyncRollbackFailureChildSelectors
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

    runRegressionSubscriptionStateRemoteRestore

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

    runRegressionSubscriptionStateStructure

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

runRegressionSubscriptionStateSyncRollbackParallelIsolationCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-subscription-state-sync-rollback-parallel-isolation-composition.log"
    local startMarker="${TMP_DIR}/subscription-state-sync-rollback-reload-started"

    : >"${callLog}"
    rm -f "${startMarker}"

    runRegressionSubscriptionStateSyncRollbackParallelIsolationProbe() {
        local selector=$1

        printf '%s|start|tmp=%s|groups=%s\n' \
            "${selector}" "${TMP_DIR}" "${PADM_SUBSCRIPTION_GROUPS_DIR:-}" >>"${callLog}"
        if [[ "${selector}" == "sync-rollback-config-restore-failure" ]]; then
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${startMarker}" ]] && break
                sleep 0.05
            done
        elif [[ "${selector}" == "sync-reload-rollback" ]]; then
            : >"${startMarker}"
        fi
        printf '%s|finish|tmp=%s|groups=%s\n' \
            "${selector}" "${TMP_DIR}" "${PADM_SUBSCRIPTION_GROUPS_DIR:-}" >>"${callLog}"
    }

    runRegressionSubscriptionSyncRollbackConfigRestoreFailure() {
        runRegressionSubscriptionStateSyncRollbackParallelIsolationProbe sync-rollback-config-restore-failure
    }

    runRegressionSubscriptionSyncRollbackRestoreDirFailure() {
        runRegressionSubscriptionStateSyncRollbackParallelIsolationProbe sync-restore-dir-failure
    }

    runRegressionSubscriptionSyncRollbackReloadRollback() {
        runRegressionSubscriptionStateSyncRollbackParallelIsolationProbe sync-reload-rollback
    }

    runRegressionSubscriptionGroupSyncRollback() {
        runRegressionSubscriptionStateSyncRollbackParallelIsolationProbe group-sync-rollback
    }

    runRegressionSubscriptionStateSyncRollback

    for selector in \
        sync-rollback-config-restore-failure \
        sync-restore-dir-failure \
        sync-reload-rollback \
        group-sync-rollback; do
        grep -q "^${selector}|start|" "${callLog}"
        grep -q "^${selector}|finish|" "${callLog}"
    done
    awk -F'[|=]' '
        $1 == "sync-rollback-config-restore-failure" && $2 == "start" { firstStart = NR }
        $1 == "sync-reload-rollback" && $2 == "start" { reloadStart = NR }
        $1 == "sync-rollback-config-restore-failure" && $2 == "finish" { firstFinish = NR }
        END { exit !(firstStart && reloadStart && firstFinish && reloadStart < firstFinish) }
    ' "${callLog}"
    awk -F'[|=]' '
        $2 == "start" {
            tmp[$4] = 1
            groups[$6] = 1
            if (index($6, $4 "/groups") != 1) {
                bad = 1
            }
        }
        END { exit !(length(tmp) == 4 && length(groups) == 4 && !bad) }
    ' "${callLog}"
)

registerRegressionFunctionLeaf subscription-state-serial runRegressionSubscriptionStateSerial
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
registerRegressionFunctionLeaf subscription-state-remote-restore-self-reference runRegressionSubscriptionStateRemoteRestoreSelfReference
registerRegressionFunctionLeaf subscription-state-remote-restore-self-reference-plan runRegressionSubscriptionStateRemoteRestoreSelfReferencePlan
registerRegressionFunctionLeaf subscription-state-remote-restore-self-reference-sync runRegressionSubscriptionStateRemoteRestoreSelfReferenceSync
registerRegressionFunctionLeaf subscription-state-remote-restore-self-reference-serial runRegressionSubscriptionStateRemoteRestoreSelfReferenceSerial
registerRegressionFunctionLeaf subscription-state-remote-restore-state-write runRegressionSubscriptionStateRemoteRestoreStateWrite
registerRegressionFunctionLeaf subscription-state-remote-restore-legacy-menu runRegressionSubscriptionStateRemoteRestoreLegacyMenu
registerRegressionFunctionLeaf subscription-state-remote-restore-serial runRegressionSubscriptionStateRemoteRestoreSerial
registerRegressionFunctionLeaf subscription-state-support runRegressionSubscriptionStateSupport
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
registerRegressionFunctionLeaf regression-subscription-state-sync-rollback-parallel-isolation-composition runRegressionSubscriptionStateSyncRollbackParallelIsolationCompositionRegression

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

registerRegressionAggregateRunnerParallel subscription-state-structure-foundation runRegressionSubscriptionStateStructureFoundation \
    $(listRegressionSubscriptionStateStructureFoundationChildSelectors)

registerRegressionAggregateRunnerParallel subscription-state-structure runRegressionSubscriptionStateStructure \
    $(listRegressionSubscriptionStateStructureChildSelectors)

registerRegressionAggregateRunnerParallel subscription-state-quota runRegressionSubscriptionStateQuota \
    $(listRegressionSubscriptionStateQuotaChildSelectors)

registerRegressionAggregateRunnerParallel subscription-state-remote-restore runRegressionSubscriptionStateRemoteRestore \
    $(listRegressionSubscriptionStateRemoteRestoreChildSelectors)

registerRegressionAggregateRunnerParallel subscription-state-sync-rollback runRegressionSubscriptionStateSyncRollback \
    $(listRegressionSubscriptionStateSyncRollbackFailureChildSelectors)

registerRegressionAggregateRunnerParallel subscription-state-core runRegressionSubscriptionStateCoreSuiteRoot \
    $(listRegressionSubscriptionStateCoreChildSelectors)
registerRegressionAggregateRunnerParallel subscription-state runRegressionSubscriptionStateSuiteRoot \
    $(listRegressionSubscriptionStateChildSelectors)
