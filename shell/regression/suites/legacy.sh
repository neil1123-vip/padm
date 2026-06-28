#!/usr/bin/env bash

REGRESSION_LEGACY_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_LEGACY_SUITE_DIR}/../subscription_groups_legacy.sh"

restoreLegacyRealityRegressionStubs() {
    realityTargetDetector() {
        printf '%s\n' fake-xray
    }

    currentRealityNetworkProfile() {
        printf '203.0.113.10\tAS64500\tExampleNet\n'
    }

    resolveRealityTargetIPv4() {
        printf '192.0.2.1\n'
    }

    lookupRealityTargetAsn() {
        case "$1" in
        198.51.100.*)
            printf 'AS64501\tRemoteNet\n'
            ;;
        *)
            printf 'AS64500\tExampleNet\n'
            ;;
        esac
    }
}

restoreLegacyRealityRegressionStubs

runRegressionTargetedBatchHelpers() {
    runRegressionStep core-invalid-input-retry-menu runCoreInvalidInputRetryMenuRegression &&
        runRegressionStep core-selection-retry-action runCoreSelectionRetryActionRegression &&
        runRegressionStep sync-configured-managed-users-helper runSyncConfiguredManagedUsersHelperRegression &&
        runRegressionStep sync-append-local-user-batch runSubscriptionSyncAppendLocalUserBatchRegression &&
        runRegressionStep traffic-configured-accounts-helper runTrafficConfiguredAccountsHelperRegression &&
        runRegressionStep traffic-account-id-map-helper runTrafficAccountIdMapHelperRegression &&
        runRegressionStep subscription-remote-sources-no-reverse-decode runRemoteSubscribeSourcesAvoidReverseDecodeRegression &&
        runRegressionStep core-rollback-result-message runCoreRollbackResultMessageRegression &&
        runRegressionStep config-transaction runConfigTransactionRegression &&
        runRegressionStep padm-bbr-managed-cleanup runPadmBbrManagedCleanupRegression &&
        runRegressionStep alone-nginx-backup-manual-check runNginxBackupManualCheckRegression
}

registerRegressionFunctionLeaf targeted-batch-helpers runRegressionTargetedBatchHelpers
