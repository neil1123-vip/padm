#!/usr/bin/env bash
set -euo pipefail

REGRESSION_ENTRY_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SUBSCRIPTION_STATE_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SUBSCRIPTION_STATE_SCRIPT_PATH="${SUBSCRIPTION_STATE_SCRIPT_DIR}/$(basename -- "${BASH_SOURCE[0]}")"
SUBSCRIPTION_STATE_FULL_SCRIPT_PATH="${SUBSCRIPTION_STATE_SCRIPT_DIR}/subscription_groups_subscription_state_full.sh"
# shellcheck source=/dev/null
source "${REGRESSION_ENTRY_DIR}/regression/bootstrap.sh"

sourceSubscriptionStateHotSection() {
    local section=$1
    local tmpFile

    tmpFile=$(mktemp "${TMP_DIR}/subscription-state-hot.${section}.XXXXXX")
    if ! awk -v start="# PADM_SECTION_BEGIN: ${section}" -v end="# PADM_SECTION_END: ${section}" '
        $0 == start { inSection=1; foundStart=1; next }
        $0 == end { foundEnd=1; exit }
        inSection { print }
        END {
            if (!foundStart || !foundEnd) {
                exit 1
            }
        }
    ' "${SUBSCRIPTION_STATE_FULL_SCRIPT_PATH}" >"${tmpFile}"; then
        rm -f "${tmpFile}"
        printf 'missing subscription-state hot section: %s\n' "${section}" >&2
        return 1
    fi
    # shellcheck source=/dev/null
    source "${tmpFile}"
    rm -f "${tmpFile}"
}

sourceSubscriptionStateHotSection subscription-state-hot-regressions

runParallelSubscriptionStateModes() {
    local orchestrationRoot=$1
    shift
    local -a labels=()
    local -a modes=()
    local -a logs=()
    local -a pids=()
    local -a statuses=()
    local i

    mkdir -p "${orchestrationRoot}"
    while [[ $# -gt 0 ]]; do
        labels+=("$1")
        modes+=("$2")
        logs+=("${orchestrationRoot}/$1.log")
        shift 2
    done

    set +e
    for i in "${!modes[@]}"; do
        PADM_REGRESSION_SUPPRESS_DONE=1 bash "${SUBSCRIPTION_STATE_SCRIPT_PATH}" "${modes[$i]}" >"${logs[$i]}" 2>&1 &
        pids[$i]=$!
    done
    for i in "${!pids[@]}"; do
        wait "${pids[$i]}"
        statuses[$i]=$?
    done
    set -e

    for i in "${!logs[@]}"; do
        cat "${logs[$i]}"
    done
    for i in "${!statuses[@]}"; do
        [[ "${statuses[$i]}" -eq 0 ]]
    done
}

runRegressionSubscriptionStateStructure() {
    runRegressionStep subscription-state-structure runSubscriptionGroupStateStructureRegression
}

runRegressionSubscriptionStateStructureFoundation() {
    runRegressionStep subscription-state-structure-foundation runSubscriptionGroupStateStructureFoundationRegression
}

runRegressionSubscriptionStateStructureFoundationAddRemove() {
    runRegressionStep subscription-state-structure-foundation-add-remove runSubscriptionGroupStateStructureFoundationAddRemoveRegression
}

runRegressionSubscriptionStateStructureFoundationCredential() {
    runRegressionStep subscription-state-structure-foundation-credential runSubscriptionGroupStateStructureFoundationCredentialRegression
}

runRegressionSubscriptionStateStructureFoundationNormalize() {
    runRegressionStep subscription-state-structure-foundation-normalize runSubscriptionGroupStateStructureFoundationNormalizeRegression
}

runRegressionSubscriptionStateStructureFoundationInitTransaction() {
    runRegressionStep subscription-state-structure-foundation-init-transaction runSubscriptionGroupStateStructureFoundationInitTransactionRegression
}

runRegressionSubscriptionStateStructureFoundationSerial() {
    runRegressionStep subscription-state-structure-foundation-serial runSubscriptionGroupStateStructureFoundationSerialRegression
}

runRegressionSubscriptionStateStructureMigration() {
    runRegressionStep subscription-state-structure-migration runSubscriptionGroupStateStructureMigrationRegression
}

runRegressionSubscriptionStateStructureSource() {
    runRegressionStep subscription-state-structure-source runSubscriptionGroupStateStructureSourceRegression
}

runRegressionSubscriptionStateStructureSourceCredential() {
    runRegressionStep subscription-state-structure-source-credential runSubscriptionGroupStateStructureSourceCredentialRegression
}

runRegressionSubscriptionStateStructureSourceStatus() {
    runRegressionStep subscription-state-structure-source-status runSubscriptionGroupStateStructureSourceStatusRegression
}

runRegressionSubscriptionStateStructureSourceRemove() {
    runRegressionStep subscription-state-structure-source-remove runSubscriptionGroupStateStructureSourceRemoveRegression
}

runRegressionSubscriptionStateStructureSourceSerial() {
    runRegressionStep subscription-state-structure-source-serial runSubscriptionGroupStateStructureSourceSerialRegression
}

runRegressionSubscriptionStateStructureSerial() {
    runRegressionStep subscription-state-structure-serial runSubscriptionGroupStateStructureSerialRegression
}

runRegressionSubscriptionStateQuota() {
    runRegressionStep subscription-state-quota runSubscriptionGroupStateQuotaRegression
}

runRegressionSubscriptionStateQuotaTraffic() {
    runRegressionStep subscription-state-quota-traffic runSubscriptionGroupStateQuotaTrafficRegression
}

runRegressionSubscriptionStateQuotaTrafficSummary() {
    runRegressionStep subscription-state-quota-traffic-summary runSubscriptionGroupStateQuotaTrafficSummaryRegression
}

runRegressionSubscriptionStateQuotaTrafficInvalidInput() {
    runRegressionStep subscription-state-quota-traffic-invalid-input runSubscriptionGroupStateQuotaTrafficInvalidInputRegression
}

runRegressionSubscriptionStateQuotaTrafficApply() {
    runRegressionStep subscription-state-quota-traffic-apply runSubscriptionGroupStateQuotaTrafficApplyRegression
}

runRegressionSubscriptionStateQuotaTrafficSerial() {
    runRegressionStep subscription-state-quota-traffic-serial runSubscriptionGroupStateQuotaTrafficSerialRegression
}

runRegressionSubscriptionStateQuotaMenuPreviewFailure() {
    runRegressionStep subscription-state-quota-menu-preview-fail runSubscriptionGroupStateQuotaMenuPreviewFailureRegression
}

runRegressionSubscriptionStateQuotaTransactionRollback() {
    runRegressionStep subscription-state-quota-menu-tx-rollback runSubscriptionGroupStateQuotaTransactionRollbackRegression
}

runRegressionSubscriptionStateQuotaMenuTransaction() {
    runRegressionStep subscription-state-quota-menu-tx runSubscriptionGroupStateQuotaMenuTransactionRegression
}

runRegressionSubscriptionStateQuotaMenuTransactionSerial() {
    runRegressionStep subscription-state-quota-menu-tx-serial runSubscriptionGroupStateQuotaMenuTransactionSerialRegression
}

runRegressionSubscriptionStateQuotaPartialSyncApplyFailure() {
    runRegressionStep subscription-state-quota-partial-sync-apply-failure runSubscriptionGroupStateQuotaPartialSyncApplyFailureRegression
}

runRegressionSubscriptionStateQuotaPartialSyncPlan() {
    runRegressionStep subscription-state-quota-partial-sync-plan runSubscriptionGroupStateQuotaPartialSyncPlanRegression
}

runRegressionSubscriptionStateQuotaPartialSyncConfig() {
    runRegressionStep subscription-state-quota-partial-sync-config runSubscriptionGroupStateQuotaPartialSyncConfigRegression
}

runRegressionSubscriptionStateQuotaPartialSync() {
    runRegressionStep subscription-state-quota-partial-sync runSubscriptionGroupStateQuotaPartialSyncRegression
}

runRegressionSubscriptionStateQuotaPartialSyncSerial() {
    runRegressionStep subscription-state-quota-partial-sync-serial runSubscriptionGroupStateQuotaPartialSyncSerialRegression
}

runRegressionSubscriptionStateQuotaSerial() {
    runRegressionStep subscription-state-quota-serial runSubscriptionGroupStateQuotaSerialRegression
}

runRegressionSubscriptionStateRemoteRestore() {
    runRegressionStep subscription-state-remote-restore runSubscriptionGroupStateRemoteRestoreRegression
}

runRegressionSubscriptionStateRemoteRestoreSelfReference() {
    runRegressionStep subscription-state-remote-restore-self-reference runSubscriptionGroupStateRemoteRestoreSelfReferenceRegression
}

runRegressionSubscriptionStateRemoteRestoreSelfReferencePlan() {
    runRegressionStep subscription-state-remote-restore-self-reference-plan runSubscriptionGroupStateRemoteRestoreSelfReferencePlanRegression
}

runRegressionSubscriptionStateRemoteRestoreSelfReferenceSync() {
    runRegressionStep subscription-state-remote-restore-self-reference-sync runSubscriptionGroupStateRemoteRestoreSelfReferenceSyncRegression
}

runRegressionSubscriptionStateRemoteRestoreSelfReferenceSerial() {
    runRegressionStep subscription-state-remote-restore-self-reference-serial runSubscriptionGroupStateRemoteRestoreSelfReferenceSerialRegression
}

runRegressionSubscriptionStateRemoteRestoreStateWrite() {
    runRegressionStep subscription-state-remote-restore-state-write runSubscriptionGroupStateRemoteRestoreStateWriteRegression
}

runRegressionSubscriptionStateRemoteRestoreLegacyMenu() {
    runRegressionStep subscription-state-remote-restore-legacy-menu runSubscriptionGroupStateRemoteRestoreLegacyMenuRegression
}

runRegressionSubscriptionStateRemoteRestoreSerial() {
    runRegressionStep subscription-state-remote-restore-serial runSubscriptionGroupStateRemoteRestoreSerialRegression
}

runRegressionSubscriptionStateCore() {
    runParallelSubscriptionStateModes \
        "${TMP_DIR}/subscription-state-core" \
        structure subscription-state-structure \
        quota subscription-state-quota \
        remote-restore subscription-state-remote-restore
}

runRegressionSubscriptionState() {
    runParallelSubscriptionStateModes \
        "${TMP_DIR}/subscription-state-default" \
        core subscription-state-core \
        support subscription-state-support \
        sync-rollback subscription-state-sync-rollback
}

regressionName=${1:-subscription-state}
case "${regressionName}" in
subscription-state)
    regressionRunner=runRegressionSubscriptionState
    ;;
subscription-state-core)
    regressionRunner=runRegressionSubscriptionStateCore
    ;;
subscription-state-structure)
    regressionRunner=runRegressionSubscriptionStateStructure
    ;;
subscription-state-structure-foundation)
    regressionRunner=runRegressionSubscriptionStateStructureFoundation
    ;;
subscription-state-structure-foundation-add-remove)
    regressionRunner=runRegressionSubscriptionStateStructureFoundationAddRemove
    ;;
subscription-state-structure-foundation-credential)
    regressionRunner=runRegressionSubscriptionStateStructureFoundationCredential
    ;;
subscription-state-structure-foundation-normalize)
    regressionRunner=runRegressionSubscriptionStateStructureFoundationNormalize
    ;;
subscription-state-structure-foundation-init-transaction)
    regressionRunner=runRegressionSubscriptionStateStructureFoundationInitTransaction
    ;;
subscription-state-structure-foundation-serial)
    regressionRunner=runRegressionSubscriptionStateStructureFoundationSerial
    ;;
subscription-state-structure-migration)
    regressionRunner=runRegressionSubscriptionStateStructureMigration
    ;;
subscription-state-structure-source)
    regressionRunner=runRegressionSubscriptionStateStructureSource
    ;;
subscription-state-structure-source-credential)
    regressionRunner=runRegressionSubscriptionStateStructureSourceCredential
    ;;
subscription-state-structure-source-status)
    regressionRunner=runRegressionSubscriptionStateStructureSourceStatus
    ;;
subscription-state-structure-source-remove)
    regressionRunner=runRegressionSubscriptionStateStructureSourceRemove
    ;;
subscription-state-structure-source-serial)
    regressionRunner=runRegressionSubscriptionStateStructureSourceSerial
    ;;
subscription-state-structure-serial)
    regressionRunner=runRegressionSubscriptionStateStructureSerial
    ;;
subscription-state-quota)
    regressionRunner=runRegressionSubscriptionStateQuota
    ;;
subscription-state-quota-traffic)
    regressionRunner=runRegressionSubscriptionStateQuotaTraffic
    ;;
subscription-state-quota-traffic-summary)
    regressionRunner=runRegressionSubscriptionStateQuotaTrafficSummary
    ;;
subscription-state-quota-traffic-invalid-input)
    regressionRunner=runRegressionSubscriptionStateQuotaTrafficInvalidInput
    ;;
subscription-state-quota-traffic-apply)
    regressionRunner=runRegressionSubscriptionStateQuotaTrafficApply
    ;;
subscription-state-quota-traffic-serial)
    regressionRunner=runRegressionSubscriptionStateQuotaTrafficSerial
    ;;
subscription-state-quota-menu-preview-fail)
    regressionRunner=runRegressionSubscriptionStateQuotaMenuPreviewFailure
    ;;
subscription-state-quota-menu-tx)
    regressionRunner=runRegressionSubscriptionStateQuotaMenuTransaction
    ;;
subscription-state-quota-menu-tx-rollback)
    regressionRunner=runRegressionSubscriptionStateQuotaTransactionRollback
    ;;
subscription-state-quota-menu-tx-serial)
    regressionRunner=runRegressionSubscriptionStateQuotaMenuTransactionSerial
    ;;
subscription-state-quota-partial-sync)
    regressionRunner=runRegressionSubscriptionStateQuotaPartialSync
    ;;
subscription-state-quota-partial-sync-apply-failure)
    regressionRunner=runRegressionSubscriptionStateQuotaPartialSyncApplyFailure
    ;;
subscription-state-quota-partial-sync-plan)
    regressionRunner=runRegressionSubscriptionStateQuotaPartialSyncPlan
    ;;
subscription-state-quota-partial-sync-config)
    regressionRunner=runRegressionSubscriptionStateQuotaPartialSyncConfig
    ;;
subscription-state-quota-partial-sync-serial)
    regressionRunner=runRegressionSubscriptionStateQuotaPartialSyncSerial
    ;;
subscription-state-quota-serial)
    regressionRunner=runRegressionSubscriptionStateQuotaSerial
    ;;
subscription-state-remote-restore)
    regressionRunner=runRegressionSubscriptionStateRemoteRestore
    ;;
subscription-state-remote-restore-self-reference)
    regressionRunner=runRegressionSubscriptionStateRemoteRestoreSelfReference
    ;;
subscription-state-remote-restore-self-reference-plan)
    regressionRunner=runRegressionSubscriptionStateRemoteRestoreSelfReferencePlan
    ;;
subscription-state-remote-restore-self-reference-sync)
    regressionRunner=runRegressionSubscriptionStateRemoteRestoreSelfReferenceSync
    ;;
subscription-state-remote-restore-self-reference-serial)
    regressionRunner=runRegressionSubscriptionStateRemoteRestoreSelfReferenceSerial
    ;;
subscription-state-remote-restore-state-write)
    regressionRunner=runRegressionSubscriptionStateRemoteRestoreStateWrite
    ;;
subscription-state-remote-restore-legacy-menu)
    regressionRunner=runRegressionSubscriptionStateRemoteRestoreLegacyMenu
    ;;
subscription-state-remote-restore-serial)
    regressionRunner=runRegressionSubscriptionStateRemoteRestoreSerial
    ;;
*)
    exec bash "${SUBSCRIPTION_STATE_FULL_SCRIPT_PATH}" "$@"
    ;;
esac

runRegressionStep "total:${regressionName}" "${regressionRunner}"
if [[ "${PADM_REGRESSION_SUPPRESS_DONE:-}" != "1" ]]; then
    echo "subscription-groups-regression-ok:${regressionName}"
fi
