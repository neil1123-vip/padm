#!/usr/bin/env bash
set -euo pipefail

SUBSCRIPTION_STATE_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SUBSCRIPTION_STATE_FULL_SCRIPT_PATH="${SUBSCRIPTION_STATE_SCRIPT_DIR}/subscription_groups_subscription_state_full.sh"
# shellcheck source=/dev/null
PADM_REGRESSION_SOURCE_ONLY=1 source "${SUBSCRIPTION_STATE_FULL_SCRIPT_PATH}"

if [[ "${PADM_REGRESSION_SOURCE_ONLY:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

if [[ "${PADM_REGRESSION_INTERNAL_CLI:-}" != "1" ]]; then
    printf 'use shell/subscription_groups_regression.sh <selector>\n' >&2
    exit 2
fi

regressionName=${1:-subscription-state-structure}
case "${regressionName}" in
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
subscription-state-support)
    regressionRunner=runRegressionSubscriptionStateSupport
    ;;
subscription-state-sync-rollback)
    regressionRunner=runRegressionSubscriptionStateSyncRollback
    ;;
subscription-state-sync-rollback-serial)
    regressionRunner=runRegressionSubscriptionStateSyncRollbackSerial
    ;;
subscription-sync-tempdir)
    regressionRunner=runRegressionSubscriptionSyncTempDir
    ;;
subscription-sync-rollback-failure)
    regressionRunner=runRegressionSubscriptionStateSyncRollback
    ;;
subscription-sync-rollback-failure-serial)
    regressionRunner=runRegressionSubscriptionStateSyncRollbackSerial
    ;;
subscription-sync-rollback-config-restore-failure)
    regressionRunner=runRegressionSubscriptionSyncRollbackConfigRestoreFailure
    ;;
subscription-sync-restore-dir-failure)
    regressionRunner=runRegressionSubscriptionSyncRollbackRestoreDirFailure
    ;;
subscription-sync-reload-rollback)
    regressionRunner=runRegressionSubscriptionSyncRollbackReloadRollback
    ;;
subscription-group-sync-rollback)
    regressionRunner=runRegressionSubscriptionGroupSyncRollback
    ;;
subscription-group-sync-rollback-serial)
    regressionRunner=runRegressionSubscriptionGroupSyncRollbackSerial
    ;;
subscription-group-sync-apply-failure)
    regressionRunner=runRegressionSubscriptionGroupSyncApplyFailure
    ;;
subscription-group-sync-reconcile-rollback)
    regressionRunner=runRegressionSubscriptionGroupSyncReconcileRollback
    ;;
subscription-group-sync-remote-failure)
    regressionRunner=runRegressionSubscriptionGroupSyncRemoteFailure
    ;;
subscription-sync-reconcile-early-exit)
    regressionRunner=runRegressionSubscriptionSyncReconcileEarlyExit
    ;;
subscription-groups-restore-failure)
    regressionRunner=runRegressionSubscriptionGroupsRestoreFailure
    ;;
*)
    printf 'usage: %s [subscription-state-structure|subscription-state-structure-foundation|subscription-state-structure-foundation-add-remove|subscription-state-structure-foundation-credential|subscription-state-structure-foundation-normalize|subscription-state-structure-foundation-init-transaction|subscription-state-structure-foundation-serial|subscription-state-structure-migration|subscription-state-structure-source|subscription-state-structure-source-credential|subscription-state-structure-source-status|subscription-state-structure-source-remove|subscription-state-structure-source-serial|subscription-state-structure-serial|subscription-state-quota|subscription-state-quota-traffic|subscription-state-quota-traffic-summary|subscription-state-quota-traffic-invalid-input|subscription-state-quota-traffic-apply|subscription-state-quota-traffic-serial|subscription-state-quota-menu-preview-fail|subscription-state-quota-menu-tx|subscription-state-quota-menu-tx-rollback|subscription-state-quota-menu-tx-serial|subscription-state-quota-partial-sync|subscription-state-quota-partial-sync-apply-failure|subscription-state-quota-partial-sync-plan|subscription-state-quota-partial-sync-config|subscription-state-quota-partial-sync-serial|subscription-state-quota-serial|subscription-state-remote-restore|subscription-state-remote-restore-self-reference|subscription-state-remote-restore-self-reference-plan|subscription-state-remote-restore-self-reference-sync|subscription-state-remote-restore-self-reference-serial|subscription-state-remote-restore-state-write|subscription-state-remote-restore-legacy-menu|subscription-state-remote-restore-serial]\n' "$0" >&2
    exit 2
    ;;
esac

runRegressionStep "total:${regressionName}" "${regressionRunner}"
if [[ "${PADM_REGRESSION_SUPPRESS_DONE:-}" != "1" ]]; then
    echo "subscription-groups-regression-ok:${regressionName}"
fi
