#!/usr/bin/env bash

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
        subscription-state-structure-sync-cron
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
        subscription-state-quota-traffic-remote \
        subscription-state-quota-traffic-invalid-input \
        subscription-state-quota-traffic-apply
}

listRegressionSubscriptionStateQuotaMenuTransactionChildSelectors() {
    printf '%s\n' \
        subscription-state-quota-menu-preview-fail \
        subscription-state-quota-menu-tx-rollback \
        subscription-state-quota-menu-tx-recheck
}

listRegressionSubscriptionStateQuotaPartialSyncChildSelectors() {
    printf '%s\n' \
        subscription-state-quota-partial-sync-apply-failure \
        subscription-state-quota-partial-sync-plan \
        subscription-state-quota-partial-sync-config
}

listRegressionSubscriptionStateSupportChildSelectors() {
    printf '%s\n' \
        subscription-sync-tempdir \
        subscription-sync-process-substitution-failure \
        subscription-sync-missing-protocol-plan \
        subscription-sync-restore-pair-failure-message \
        subscription-sync-append-restore-failure-detail \
        subscription-sync-single-restore-result-message \
        subscription-sync-rollback-result-message \
        subscription-sync-find-user-enabled-projection \
        subscription-sync-ensure-user-uuids-batch \
        subscription-sync-append-preserves-clients \
        subscription-sync-remove-account-file \
        subscription-user-removal-transaction-lock \
        subscription-state-maintenance-rollback \
        subscription-state-maintenance-removed-source-cleanup \
        subscription-source-removal-preflight \
        subscription-mutation-sync-rollback \
        subscription-mutation-sync-rollback-local-restore \
        subscription-mutation-sync-state-restore-failure \
        subscription-sync-reconcile-early-exit \
        subscription-group-sync-publish-refresh-inline \
        subscription-group-sync-single-config-backup \
        subscription-group-sync-traffic-reload-order \
        subscription-groups-lock-timeout \
        subscription-groups-restore-failure
}

runRegressionSubscriptionStateSupport() {
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runSubscriptionStateParallelChildRegressionIsolatedSelector \
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-support" \
            listRegressionSubscriptionStateSupportChildSelectors
}

listRegressionSubscriptionStateRemoteRestoreSelfReferenceChildSelectors() {
    printf '%s\n' \
        subscription-state-remote-restore-self-reference-plan \
        subscription-state-remote-restore-self-reference-sync
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

registerRegressionFunctionLeaf subscription-state-structure-foundation-add-remove runRegressionStep subscription-state-structure-foundation-add-remove runSubscriptionGroupStateStructureFoundationAddRemoveRegression
registerRegressionFunctionLeaf subscription-state-structure-foundation-credential runRegressionStep subscription-state-structure-foundation-credential runSubscriptionGroupStateStructureFoundationCredentialRegression
registerRegressionFunctionLeaf subscription-state-structure-foundation-normalize runRegressionStep subscription-state-structure-foundation-normalize runSubscriptionGroupStateStructureFoundationNormalizeRegression
registerRegressionFunctionLeaf subscription-state-structure-foundation-init-transaction runRegressionStep subscription-state-structure-foundation-init-transaction runSubscriptionGroupStateStructureFoundationInitTransactionRegression
registerRegressionSequentialSelectorList subscription-state-structure-validation listRegressionSubscriptionStateStructureValidationChildSelectors
registerRegressionFunctionLeaf subscription-state-structure-validation-serial runRegressionStep subscription-state-structure-validation-serial runSubscriptionGroupStateStructureValidationRegression
registerRegressionSequentialSelectorList subscription-state-structure-source listRegressionSubscriptionStateStructureSourceChildSelectors
registerRegressionFunctionLeaf subscription-state-structure-source-credential runRegressionStep subscription-state-structure-source-credential runSubscriptionGroupStateStructureSourceCredentialRegression
registerRegressionFunctionLeaf subscription-state-structure-source-status runRegressionStep subscription-state-structure-source-status runSubscriptionGroupStateStructureSourceStatusRegression
registerRegressionFunctionLeaf subscription-state-structure-source-remove runRegressionStep subscription-state-structure-source-remove runSubscriptionGroupStateStructureSourceRemoveRegression
registerRegressionFunctionLeaf subscription-state-structure-sync-cron runRegressionStep subscription-state-structure-sync-cron runSubscriptionGroupStateStructureSyncCronRegression
registerRegressionFunctionLeaf subscription-state-quota-traffic-summary runRegressionStep subscription-state-quota-traffic-summary runSubscriptionGroupStateQuotaTrafficSummaryRegression
registerRegressionFunctionLeaf subscription-state-quota-traffic-remote runRegressionStep subscription-state-quota-traffic-remote runSubscriptionGroupStateQuotaTrafficRemoteRegression
registerRegressionFunctionLeaf subscription-state-quota-traffic-invalid-input runRegressionStep subscription-state-quota-traffic-invalid-input runSubscriptionGroupStateQuotaTrafficInvalidInputRegression
registerRegressionFunctionLeaf subscription-state-quota-traffic-apply runRegressionStep subscription-state-quota-traffic-apply runSubscriptionGroupStateQuotaTrafficApplyRegression
registerRegressionFunctionLeaf subscription-state-quota-menu-preview-fail runRegressionStep subscription-state-quota-menu-preview-fail runSubscriptionGroupStateQuotaMenuPreviewFailureRegression
registerRegressionFunctionLeaf subscription-state-quota-menu-tx-rollback runRegressionStep subscription-state-quota-menu-tx-rollback runSubscriptionGroupStateQuotaTransactionRollbackRegression
registerRegressionFunctionLeaf subscription-state-quota-menu-tx-recheck runRegressionStep subscription-state-quota-menu-tx-recheck runSubscriptionGroupStateQuotaTransactionRecheckRegression
registerRegressionFunctionLeaf subscription-state-quota-partial-sync-apply-failure runRegressionStep subscription-state-quota-partial-sync-apply-failure runSubscriptionGroupStateQuotaPartialSyncApplyFailureRegression
registerRegressionFunctionLeaf subscription-state-quota-partial-sync-plan runRegressionStep subscription-state-quota-partial-sync-plan runSubscriptionGroupStateQuotaPartialSyncPlanRegression
registerRegressionFunctionLeaf subscription-state-quota-partial-sync-config runRegressionStep subscription-state-quota-partial-sync-config runSubscriptionGroupStateQuotaPartialSyncConfigRegression
registerRegressionSequentialSelectorList subscription-state-remote-restore-self-reference listRegressionSubscriptionStateRemoteRestoreSelfReferenceChildSelectors
registerRegressionFunctionLeaf subscription-state-remote-restore-self-reference-plan runRegressionStep subscription-state-remote-restore-self-reference-plan runSubscriptionGroupStateRemoteRestoreSelfReferencePlanRegression
registerRegressionFunctionLeaf subscription-state-remote-restore-self-reference-sync runRegressionStep subscription-state-remote-restore-self-reference-sync runSubscriptionGroupStateRemoteRestoreSelfReferenceSyncRegression
registerRegressionFunctionLeaf subscription-state-remote-restore-state-write runRegressionStep subscription-state-remote-restore-state-write runSubscriptionGroupStateRemoteRestoreStateWriteRegression
registerRegressionFunctionLeaf subscription-state-remote-restore-legacy-menu runRegressionStep subscription-state-remote-restore-legacy-menu runSubscriptionGroupStateRemoteRestoreLegacyMenuRegression
registerRegressionSequentialSelectorList subscription-state-quota-traffic listRegressionSubscriptionStateQuotaTrafficChildSelectors
registerRegressionSequentialSelectorList subscription-state-quota-menu-tx listRegressionSubscriptionStateQuotaMenuTransactionChildSelectors
registerRegressionSequentialSelectorList subscription-state-quota-partial-sync listRegressionSubscriptionStateQuotaPartialSyncChildSelectors
registerRegressionAggregateRunner parallel subscription-state-support runRegressionSubscriptionStateSupport \
    $(listRegressionSubscriptionStateSupportChildSelectors)
registerRegressionFunctionLeaf subscription-sync-tempdir runRegressionStep subscription-sync-tempdir runSubscriptionSyncTempDirRegression
registerRegressionFunctionLeaf subscription-sync-process-substitution-failure runRegressionStep subscription-sync-process-substitution-failure runSubscriptionSyncProcessSubstitutionFailureRegression
registerRegressionFunctionLeaf subscription-sync-missing-protocol-plan runRegressionStep subscription-sync-missing-protocol-plan runSubscriptionSyncMissingProtocolPlanRegression
registerRegressionFunctionLeaf subscription-sync-restore-pair-failure-message runSubscriptionSyncRestorePairFailureMessageRegression
registerRegressionFunctionLeaf subscription-sync-append-restore-failure-detail runSubscriptionSyncAppendRestoreFailureDetailRegression
registerRegressionFunctionLeaf subscription-sync-single-restore-result-message runSubscriptionSyncSingleRestoreResultMessageRegression
registerRegressionFunctionLeaf subscription-sync-rollback-result-message runSubscriptionSyncRollbackResultMessageRegression
registerRegressionFunctionLeaf subscription-sync-find-user-enabled-projection runSubscriptionSyncFindUserEnabledProjectionRegression
registerRegressionFunctionLeaf subscription-sync-ensure-user-uuids-batch runRegressionStep subscription-sync-ensure-user-uuids-batch runSubscriptionSyncEnsureEnabledUserUUIDsBatchRegression
registerRegressionFunctionLeaf subscription-sync-append-preserves-clients runRegressionStep subscription-sync-append-preserves-clients runSubscriptionSyncAppendProtocolUserPreservesClientsRegression
registerRegressionFunctionLeaf subscription-sync-remove-account-file runRegressionStep subscription-sync-remove-account-file runSubscriptionSyncRemoveAccountFromFileRegression
registerRegressionFunctionLeaf subscription-user-removal-transaction-lock runRegressionStep subscription-user-removal-transaction-lock runSubscriptionUserRemovalTransactionLockRegression
registerRegressionFunctionLeaf subscription-state-maintenance-rollback runRegressionStep subscription-state-maintenance-rollback runSubscriptionStateMaintenanceRollbackRegression
registerRegressionFunctionLeaf subscription-state-maintenance-removed-source-cleanup runRegressionStep subscription-state-maintenance-removed-source-cleanup runSubscriptionStateMaintenanceRemovedSourceCleanupRegression
registerRegressionFunctionLeaf subscription-source-removal-preflight runRegressionStep subscription-source-removal-preflight runSubscriptionSourceRemovalPreflightRegression
registerRegressionFunctionLeaf subscription-mutation-sync-rollback runRegressionStep subscription-mutation-sync-rollback runSubscriptionMutationSyncRollbackRegression
registerRegressionFunctionLeaf subscription-mutation-sync-rollback-local-restore runRegressionStep subscription-mutation-sync-rollback-local-restore runSubscriptionMutationSyncRollbackLocalRestoreRegression
registerRegressionFunctionLeaf subscription-mutation-sync-state-restore-failure runRegressionStep subscription-mutation-sync-state-restore-failure runSubscriptionMutationSyncStateRestoreFailureRegression
registerRegressionFunctionLeaf subscription-sync-rollback-config-restore-failure runRegressionStep subscription-sync-rollback-config-restore-failure runSubscriptionSyncRollbackConfigRestoreFailureRegression
registerRegressionFunctionLeaf subscription-sync-restore-dir-failure runRegressionStep subscription-sync-restore-dir-failure runSubscriptionSyncRollbackRestoreDirFailureRegression
registerRegressionFunctionLeaf subscription-sync-reload-rollback runRegressionStep subscription-sync-reload-rollback runSubscriptionSyncRollbackReloadRollbackRegression
registerRegressionFunctionLeaf subscription-group-sync-rollback runRegressionStep subscription-group-sync-rollback runSubscriptionGroupSyncRollbackSerialRegression
registerRegressionFunctionLeaf subscription-group-sync-publish-refresh-inline runSubscriptionGroupSyncPublishRefreshInlineRegression
registerRegressionFunctionLeaf subscription-group-sync-single-config-backup runSubscriptionGroupSyncSingleConfigBackupRegression
registerRegressionFunctionLeaf subscription-group-sync-traffic-reload-order runRegressionStep subscription-group-sync-traffic-reload-order runSubscriptionGroupSyncTrafficReloadOrderRegression
registerRegressionFunctionLeaf subscription-groups-lock-timeout runRegressionStep subscription-groups-lock-timeout runSubscriptionGroupsLockTimeoutRegression
registerRegressionFunctionLeaf subscription-group-sync-apply-failure runRegressionStep subscription-group-sync-apply-failure runSubscriptionGroupSyncApplyFailureRegression
registerRegressionFunctionLeaf subscription-group-sync-reconcile-rollback runRegressionStep subscription-group-sync-reconcile-rollback runSubscriptionGroupSyncReconcileRollbackRegression
registerRegressionFunctionLeaf subscription-group-sync-remote-failure runRegressionStep subscription-group-sync-remote-failure runSubscriptionGroupSyncRemoteFailureRegression
registerRegressionFunctionLeaf subscription-group-sync-state-lock runRegressionStep subscription-group-sync-state-lock runSubscriptionGroupSyncUsesStateLockRegression
registerRegressionFunctionLeaf subscription-sync-reconcile-early-exit runRegressionStep subscription-sync-reconcile-early-exit runSubscriptionSyncReconcileEarlyExitRegression
registerRegressionFunctionLeaf subscription-groups-restore-failure runRegressionStep subscription-groups-restore-failure runSubscriptionGroupsRestoreFailureRegression

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

registerRegressionParallelSelectorList subscription-state-structure-foundation runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/subscription-state-structure-foundation" listRegressionSubscriptionStateStructureFoundationChildSelectors

registerRegressionAggregateRunner parallel subscription-state-structure runRegressionSubscriptionStateStructure \
    $(listRegressionSubscriptionStateStructureChildSelectors)

registerRegressionAggregateRunner parallel subscription-state-quota runRegressionSubscriptionStateQuota \
    $(listRegressionSubscriptionStateQuotaChildSelectors)

registerRegressionAggregateRunner parallel subscription-state-remote-restore runRegressionSubscriptionStateRemoteRestore \
    $(listRegressionSubscriptionStateRemoteRestoreChildSelectors)

registerRegressionAggregateRunner parallel subscription-state-sync-rollback runRegressionSubscriptionStateSyncRollback \
    $(listRegressionSubscriptionStateSyncRollbackFailureChildSelectors)

registerRegressionParallelSelectorList subscription-state-core runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/subscription-state-core-${BASHPID:-$$}" listRegressionSubscriptionStateCoreChildSelectors
registerRegressionParallelSelectorList subscription-state runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/subscription-state-default-${BASHPID:-$$}" listRegressionSubscriptionStateChildSelectors
