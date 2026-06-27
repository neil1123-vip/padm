#!/usr/bin/env bash

REGRESSION_PLATFORM_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_PLATFORM_SUITE_DIR}/../subscription_groups_fast.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_PLATFORM_SUITE_DIR}/../subscription_groups_legacy.sh"

runRegressionPlatformSuiteRoot() {
    runRegressionStep release-workflow-version runReleaseWorkflowVersionRegression &&
        runRegressionStep version-helpers runVersionHelpersRegression &&
        runRegressionStep cleanup-trap runCleanupTrapRegression &&
        runRegressionStep cleanup-trap-relative-path runCleanupTrapRelativePathRegression &&
        runRegressionStep clean-directory-safety runCleanDirectoryContentSafetyRegression &&
        runRegressionStep check-log-backup-restore runCheckLogBackupMissingRestoreRegression &&
        runRegressionStep update-padm-version-prompt runUpdatePadmVersionPromptRegression &&
        runRegressionStep install-refresh-fallback-main runInstallRefreshFallbackMainRegression &&
        runRegressionStep install-refresh-keep-ref-on-lookup-fail runInstallRefreshKeepsRefWhenRemoteLookupFailsRegression &&
        runRegressionStep install-refresh-rejects-unsafe-script-dir runInstallRefreshRejectsUnsafeScriptDirRegression &&
        runRegressionStep install-refresh-rejects-unsafe-archive runInstallRefreshRejectsUnsafeArchiveRegression &&
        runRegressionStep install-refresh-rejects-unsupported-archive-entry runInstallRefreshRejectsUnsupportedArchiveEntriesRegression &&
        runRegressionStep install-refresh-rejects-protected-worktree runInstallRefreshRejectsProtectedWorktreeRegression &&
        runRegressionStep install-refresh-restore runInstallRefreshRestoresBackupRegression &&
        runRegressionStep install-refresh-single-archive-guard runInstallRefreshSingleArchiveGuardRegression &&
        runRegressionStep install-ensure-modules-rejects-protected-worktree runInstallEnsureModulesRejectsProtectedWorktreeRegression &&
        runRegressionStep regression-framework-exports-protected-worktree-env runRegressionFrameworkExportsProtectedWorktreeEnvRegression &&
        runRegressionStep remote-control-systemctl-stub-default-stop-disable runRemoteControlSystemctlStubDefaultStopDisableRegression &&
        runRegressionStep remote-control-function-stub-default-stop-disable runRemoteControlFunctionStubDefaultStopDisableRegression &&
        runRegressionStep tuic-protocol-single-default-branch runTuicProtocolSingleDefaultBranchRegression &&
        runRegressionStep tls-dns-api-single-default-branch runTlsDnsApiSingleDefaultBranchRegression &&
        runRegressionStep tls-ca-single-default-branch runTlsCaSingleDefaultBranchRegression &&
        runRegressionStep reality-target-single-default-branch runRealityTargetSingleDefaultBranchRegression &&
        runRegressionStep auto-install-type-single-custom-branch runAutoInstallTypeSingleCustomBranchRegression &&
        runRegressionStep subscription-menu-wrapper-count runSubscriptionMenuWrapperCountRegression &&
        runRegressionStep subscription-menu-dead-entry-count runSubscriptionMenuDeadEntryCountRegression &&
        runRegressionStep unused-helper-function-count runUnusedHelperFunctionCountRegression &&
        runRegressionStep legacy-users-module-removed runLegacyUsersModuleRemovedRegression &&
        runRegressionStep install-entry-refresh runInstallEnsureModulesRegression &&
        runRegressionStep install-module-paths runInstallModulePathsRegression &&
        runRegressionStep install-entry-symlink runInstallEntrySymlinkPathRegression &&
        runRegressionStep alias-install-metadata runAliasInstallMetadataCopyRegression &&
        runRegressionStep alias-install-same-target runAliasInstallSameTargetRegression &&
        runRegressionStep alias-install-rejects-unsafe-target runAliasInstallRejectsUnsafeTargetRegression &&
        runRegressionStep alias-install-rejects-unsafe-home runAliasInstallRejectsUnsafeHomeFallbackRegression &&
        runRegressionStep xray-stats-jq runXrayTrafficStatsJqCompatibilityRegression &&
        runRegressionStep local-traffic-accounts runLocalTrafficAccountsBatchRegression &&
        runRegressionStep dpkg-installed-pattern runDpkgInstalledPatternRegression &&
        runRegressionStep dpkg-query-installed-pattern runDpkgQueryInstalledPatternRegression &&
        runRegressionStep rhel-like-detection runRhelLikeDetectionRegression &&
        runRegressionStep fedora-detection runFedoraDetectionRegression &&
        runRegressionStep port-hopping-without-persistent runPortHoppingWithoutPersistentRegression
}

runRegressionPlatformIoSuiteRoot() {
    runRegressionStep install-tools-certificate-dependency runInstallToolsCertificateDependencyRegression &&
        runRegressionStep install-tools-acme-result-failure runInstallToolsAcmeResultFailureRegression &&
        runRegressionStep install-tools-acme-commit-failure runInstallToolsAcmeCommitFailureRegression &&
        runRegressionStep install-tools-configured-log runInstallToolsUsesConfiguredInstallLogRegression &&
        runRegressionStep install-tools-update-failure runInstallToolsUpdateFailureRegression &&
        runRegressionStep install-tools-release-info-failure runInstallToolsReleaseInfoFailureRegression &&
        runRegressionStep install-tools-nginx-reinstall-failure runInstallToolsNginxReinstallFailureRegression &&
        runRegressionStep apt-key-install-failure runAptKeyInstallFailureRegression &&
        runRegressionStep nginx-apt-refresh-rollback runNginxAptRepoRefreshRollbackRegression &&
        runRegressionStep nginx-alpine-default-conf-rollback runNginxAlpineDefaultConfRollbackRegression &&
        runRegressionStep nginx-yum-mainline-enable-failure runNginxYumMainlineEnableFailureRegression &&
        runRegressionStep base-package-batch runBasePackageBatchRegression &&
        runRegressionStep package-rollback-failure runPackageRollbackFailureRegression &&
        runRegressionStep package-command-stdin runPackageCommandStdinRegression &&
        runRegressionStep reality-scanner-unsafe-dir runRealityScannerRejectsUnsafeDirRegression &&
        runRegressionStep reality-scanner-binary runRealityScannerBinaryRegression &&
        runRegressionStep reality-scanner-download-failure runRealityScannerDownloadFailureKeepsExistingDirRegression
}

registerRegressionFunctionLeaf platform-hot runRegressionPlatformSuiteRoot
registerRegressionFunctionLeaf platform-io runRegressionPlatformIoSuiteRoot
