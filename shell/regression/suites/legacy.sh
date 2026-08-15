#!/usr/bin/env bash

REGRESSION_LEGACY_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_LEGACY_SUITE_DIR}/../subscription_groups_legacy.sh" --reuse
restoreLegacyRegressionContext

runRegressionTargetedBatchHelpers() {
    runParallelRegressionRunners "${TMP_DIR}/targeted-batch-helpers-parallel-${BASHPID:-$$}" \
        core-invalid-input-retry-menu runCoreInvalidInputRetryMenuRegression \
        core-selection-retry-action runCoreSelectionRetryActionRegression \
        configured-account-helpers runConfiguredAccountHelpersRegression \
        sync-append-local-user-batch runSubscriptionSyncAppendLocalUserBatchRegression \
        traffic-account-id-map-helper runTrafficAccountIdMapHelperRegression \
        subscription-remote-sources-no-reverse-decode runRemoteSubscribeSourcesAvoidReverseDecodeRegression \
        core-rollback-result-message runCoreRollbackResultMessageRegression \
        config-transaction runConfigTransactionRegression \
        padm-bbr-managed-cleanup runPadmBbrManagedCleanupRegression \
        alone-nginx-backup-manual-check runNginxBackupManualCheckRegression
}

registerRegressionFunctionLeaf targeted-batch-helpers runRegressionTargetedBatchHelpers
