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
ui ui
routing routing
subscription subscription
runtime runtime
reality-candidates reality-candidates
reality-stream reality-stream
transaction-core transaction-core
EOF

registerRegressionFunctionLeaf platform-io runRegressionPlatformIo
registerRegressionFunctionLeaf tls runRegressionTls
registerRegressionFunctionLeaf ui-smoke runRegressionMenuSmoke
registerRegressionFunctionLeaf routing-socks5-udp-associate runSocks5UdpAssociateRegression
registerRegressionFunctionLeaf routing-core-unsafe-config-dir runRoutingCoreRejectsUnsafeConfigDirRegression
registerRegressionFunctionLeaf routing-access-control-config-transaction runAccessControlConfigTransactionRegression
registerRegressionFunctionLeaf routing-access-control-unsafe-backup-dir runAccessControlRejectsUnsafeBackupDirRegression
registerRegressionFunctionLeaf routing-access-control-unsafe-config-dir runAccessControlRejectsUnsafeConfigDirRegression
registerRegressionFunctionLeaf routing-access-control-failure-return runAccessControlFailureReturnRegression
registerRegressionFunctionLeaf routing-bt-failure-return runBTRoutingFailureReturnRegression
registerRegressionFunctionLeaf routing-ipv6-failure-return runIPv6RoutingFailureReturnRegression
registerRegressionFunctionLeaf routing-warp-failure-return runWARPRoutingFailureReturnRegression
registerRegressionFunctionLeaf routing-socks5-failure-return runSocks5RoutingFailureReturnRegression
registerRegressionFunctionLeaf subscription-remote-fetch runRegressionSubscriptionRemoteFetch
registerRegressionFunctionLeaf reality-candidates-fast runRealityCandidateFastRegression
registerRegressionFunctionLeaf runtime-auto-install-reality-route runAutoInstallRealityRouteRegression
registerRegressionFunctionLeaf transaction-system runRegressionTransactionSystem
registerRegressionFunctionLeaf transaction-subscription runRegressionTransactionSubscription
registerRegressionFunctionLeaf config-transaction runConfigTransactionRegression
registerRegressionFunctionLeaf core-port-unsafe-config-dir runCorePortRejectsUnsafeConfigDirRegression
registerRegressionFunctionLeaf check-port-open-nginx-directory-target runCheckPortOpenNginxRejectsDirectoryTargetRegression
registerRegressionFunctionLeaf alone-nginx-directory-target runAloneNginxRejectsDirectoryTargetRegression
registerRegressionFunctionLeaf sing-box-managed-cleanup runSingBoxManagedCleanupRegression
registerRegressionFunctionLeaf xray-reality-port-failure runXrayRealityPortFailureRegression
registerRegressionFunctionLeaf reality-profile-failure runRealityProfileFailureRegression
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
registerRegressionFunctionLeaf tls-failure-return runTlsFailureReturnRegression
registerRegressionFunctionLeaf tls-reinstall-rollback runTlsReinstallRollbackRegression
registerRegressionFunctionLeaf tls-renew-failure-propagation runTlsRenewalFailurePropagationRegression
registerRegressionFunctionLeaf wireguard-control-safe-dir runWireGuardControlSafeDirRegression
registerRegressionFunctionLeaf warp-config-safe-dir runWarpConfigSafeDirRegression
registerRegressionFunctionLeaf warp-config-file-cleanup runWarpConfigFileCleanupRegression
registerRegressionFunctionLeaf uninstall-nginx-cleanup runUninstallNginxCleanupRegression
registerRegressionFunctionLeaf clean-agent-nginx-managed-remove runCleanAgentNginxManagedRemovalRegression
registerRegressionFunctionLeaf fail2ban-managed-cleanup runFail2banManagedCleanupRegression
registerRegressionFunctionLeaf fail2ban-apply-transaction runFail2banApplyTransactionRegression
registerRegressionFunctionLeaf uninstall-wireguard-cleanup runUninstallWireGuardCleanupRegression
registerRegressionFunctionLeaf wireguard-key-transaction runWireGuardKeyTransactionRegression
registerRegressionFunctionLeaf uninstall-service-stop-failure runUninstallServiceStopFailureRegression
registerRegressionFunctionLeaf clean-last-installation-failure runCleanLastInstallationConfigFailureRegression
registerRegressionFunctionLeaf clean-last-installation-acme-home runCleanLastInstallationConfigAcmeHomeFailureRegression
registerRegressionFunctionLeaf clean-last-installation-acme-relative-home runCleanLastInstallationConfigResolvesRelativeAcmeHomeRegression
registerRegressionFunctionLeaf alone-nginx-write-transaction runAloneNginxConfigWriteTransactionRegression
registerRegressionFunctionLeaf alone-nginx-update-transaction runAloneNginxUpdateTransactionRegression
registerRegressionFunctionLeaf nginx-service-failure runNginxServiceFailureRegression
registerRegressionAggregateSequential transaction \
    transaction-core \
    transaction-subscription \
    transaction-system

registerRegressionAggregateSequential all \
    routing \
    subscription \
    runtime \
    transaction \
    remote-control \
    ui
registerRegressionAlias full all
registerRegressionAlias ci all
