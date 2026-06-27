#!/usr/bin/env bash

REGRESSION_LEGACY_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REGRESSION_LEGACY_SCRIPT="${REGRESSION_LEGACY_SUITE_DIR}/../subscription_groups_legacy.sh"
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

while read -r selector runner; do
    registerRegressionScriptLeaf "${selector}" "${REGRESSION_LEGACY_SCRIPT}" "${runner}"
done <<'EOF'
EOF

registerRegressionFunctionLeaf core-rollback-result-message runCoreRollbackResultMessageRegression
registerRegressionFunctionLeaf config-transaction runConfigTransactionRegression
registerRegressionFunctionLeaf core-port-file-transaction runCorePortFileTransactionRegression
registerRegressionFunctionLeaf core-port-unsafe-config-dir runCorePortRejectsUnsafeConfigDirRegression
registerRegressionFunctionLeaf entry-helper-config runEntryHelperConfigRegression
registerRegressionFunctionLeaf user-config-write runUserConfigWriteRegression
registerRegressionFunctionLeaf remove-user runRemoveUserRegression
registerRegressionFunctionLeaf check-port-open-nginx-directory-target runCheckPortOpenNginxRejectsDirectoryTargetRegression
registerRegressionFunctionLeaf alone-nginx-directory-target runAloneNginxRejectsDirectoryTargetRegression
registerRegressionFunctionLeaf sing-box-managed-cleanup runSingBoxManagedCleanupRegression
registerRegressionFunctionLeaf xray-reality-port-failure runXrayRealityPortFailureRegression
registerRegressionFunctionLeaf sing-box-reality-key-transaction runSingBoxRealityKeyTransactionRegression
registerRegressionFunctionLeaf core-template-managed-remove runCoreTemplateManagedConfigRemovalRegression
registerRegressionFunctionLeaf core-template-return-failure runCoreTemplateReturnFailureRegression
registerRegressionFunctionLeaf core-binary-install-copy-failure runCoreBinaryInstallCopyFailureRegression
registerRegressionFunctionLeaf sing-box-cronet-rollback runSingBoxCronetRollbackRegression
registerRegressionFunctionLeaf finalize-sing-box-rollback runFinalizeSingBoxBinaryInstallRollbackRegression
registerRegressionFunctionLeaf service-queue-apply-propagation runServiceQueueApplyPropagationRegression
registerRegressionFunctionLeaf core-install-service-action-failure runCoreInstallServiceActionFailureRegression
registerRegressionFunctionLeaf sing-box-merge-start-failure runSingBoxMergeStartFailureRegression
registerRegressionFunctionLeaf sing-box-uninstall-rejects-unsafe-config-path runSingBoxUninstallRejectsUnsafeConfigPathRegression
registerRegressionFunctionLeaf sing-box-uninstall-failure-propagation runSingBoxUninstallFailurePropagationRegression
registerRegressionFunctionLeaf sing-box-protocol-reload-failure runSingBoxProtocolReloadFailureRegression
registerRegressionFunctionLeaf geo-update-reload-failure runGeoUpdateReloadFailureRegression
registerRegressionFunctionLeaf core-cleanup-failure-propagation runCoreCleanupFailurePropagationRegression
registerRegressionFunctionLeaf sing-box-log-transaction runSingBoxLogTransactionRegression
registerRegressionFunctionLeaf core-upgrade-directory-target runCoreUpgradeRejectsDirectoryTargetRegression
registerRegressionFunctionLeaf legacy-core-upgrade-keeps-existing runLegacyCoreUpgradeKeepsExistingBinaryRegression
registerRegressionFunctionLeaf core-first-install-failure-clean runCoreFirstInstallLeavesNoLiveArtifactsOnFailureRegression
registerRegressionFunctionLeaf core-install-unsafe-binary-path runCoreInstallRejectsUnsafeBinaryPathRegression
registerRegressionFunctionLeaf core-first-install-commit-rollback runCoreFirstInstallCommitFailureRollbackRegression
registerRegressionFunctionLeaf sing-box-download-artifacts-cleanup runSingBoxDownloadArtifactsCleanupRegression
registerRegressionFunctionLeaf network-check-return-failure runNetworkCheckReturnFailureRegression
registerRegressionFunctionLeaf sing-box-merge-config-transaction runSingBoxMergeConfigTransactionRegression
registerRegressionFunctionLeaf reload-core-propagation runReloadCorePropagationRegression
