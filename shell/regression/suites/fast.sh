#!/usr/bin/env bash

REGRESSION_FAST_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_FAST_SUITE_DIR}/../subscription_groups_fast.sh"

runRegressionFastUiSmokeLightSuiteRoot() {
    runRegressionUiSmokeSuiteRoot
}

runRegressionFastSuiteRoot() {
    runRegressionStep platform runRegressionPlatformSuiteRoot &&
        runRegressionStep commit-generated-file-directory-target runCommitGeneratedFileRejectsDirectoryTargetRegression &&
        runRegressionStep restore-managed-file-directory-target runRestoreManagedFileFromBackupRejectsDirectoryTargetRegression &&
        runRegressionStep github-release-direct-fallback runGitHubReleaseAssetDirectFallbackRegression &&
        runRegressionStep download-arg-missing-value runDownloadArgumentMissingValueRegression &&
        runRegressionStep github-release-arg-missing-value runGitHubReleaseArgumentMissingValueRegression &&
        runRegressionStep remove-install-path-retry runRemoveInstallPathRetryRegression &&
        runRegressionStep remove-install-path-file-mode runRemoveInstallPathFileModeRegression &&
        runRegressionStep uninstall-padm-root-scope runUninstallPadmRootScopeRegression &&
        runRegressionStep remove-install-path-safety runRemoveInstallPathSafetyRegression &&
        runRegressionStep remove-nginx-default-conf-safety runRemoveNginxDefaultConfSafetyRegression &&
        runRegressionStep clean-agent-nginx-conf-safety runCleanAgentNginxConfSafetyRegression &&
        runRegressionStep uninstall-subscribe-nginx-path-safety runUninstallSubscribeNginxPathSafetyRegression &&
        runRegressionStep check-port-open-nginx-path-safety runCheckPortOpenNginxPathSafetyRegression &&
        runRegressionStep write-subscribe-nginx-path-safety runWriteSubscribeNginxPathSafetyRegression &&
        runRegressionStep write-alone-nginx-path-safety runWriteAloneNginxPathSafetyRegression &&
        runRegressionStep clean-last-installation-nginx-safety runCleanLastInstallationSkipsDuplicateNginxCleanupRegression &&
        runRegressionStep install-nginx-alpine-default-path-safety runInstallNginxAlpineDefaultPathSafetyRegression &&
        runRegressionStep install-nginx-static-unsafe-path runInstallNginxStaticRejectsUnsafePathRegression &&
        runRegressionStep install-nginx-static-unzip-failure runInstallNginxStaticPreservesLiveSiteOnUnzipFailureRegression &&
        runRegressionStep clean-last-installation-static-safety runCleanLastInstallationRejectsUnsafeStaticPathRegression &&
        runRegressionStep subscription-sync-path-safety runSubscriptionSyncPathSafetyRegression &&
        runRegressionStep subscription-sync-config-directory-target runSubscriptionSyncConfigRestoreRejectsDirectoryTargetRegression &&
        runRegressionStep subscription-sync-missing-restore-scope runSubscriptionSyncMissingRestoreScopeRegression &&
        runRegressionStep auto-install-generated-identity runAutoInstallGeneratedIdentityRegression &&
        runRegressionStep auto-install-empty-defaults runAutoInstallAllowsEmptyDefaultRegression &&
        runRegressionStep parse-install-args-missing-value runParseInstallArgsMissingValueRegression &&
        runRegressionStep client-name-suffix-preserves-random-prefix runClientNameSuffixPreservesRandomPrefixRegression &&
        runRegressionStep subscribe-local-cleanup runInitSubscribeLocalConfigCleansAllFormatsRegression &&
        runRegressionStep subscription-output-random-user runSubscriptionOutputRandomUserRegression &&
        runRegressionStep locale-unset-printN runLocaleEchoContentUnsetPrintNRegression &&
        runRegressionStep show-accounts-optional-step runShowAccountsOptionalStepRegression &&
        runRegressionStep show-accounts-xray-singbox-assist runShowAccountsXrayWithSingBoxAssistRegression &&
        runRegressionStep httpupgrade-incremental-starts-nginx runSingBoxHttpUpgradeIncrementalStartsNginxRegression &&
        runRegressionStep httpupgrade-rejects-unsafe-nginx-path runSingBoxHttpUpgradeRejectsUnsafeNginxPathRegression &&
        runRegressionStep allow-port-optional-protocol runAllowPortOptionalProtocolRegression &&
        runRegressionStep core-client-optional-args runCoreClientOptionalArgsRegression &&
        runRegressionStep singbox-mainpid-template runSingBoxServiceMainPidTemplateRegression &&
        runRegressionStep service-wait-state runServiceWaitForStateRegression &&
        runRegressionStep warp-config-generation-failure runWarpConfigGenerationFailureRegression &&
        runRegressionStep fail2ban-profile runFail2banProfileRegression &&
        runRegressionStep fail2ban-menu runFail2banMenuRegression &&
        runRegressionStep xray-strict-validation runXrayStrictValidationRegression &&
        runRegressionStep xray-compat-audit runXrayCompatibilityAuditRegression &&
        runRegressionStep xray-prerelease-dry-run runXrayPrereleaseDryRunRegression &&
        runRegressionStep singbox-compat-audit runSingBoxCompatibilityAuditRegression &&
        runRegressionStep singbox-prerelease-dry-run runSingBoxPrereleaseDryRunRegression &&
        runRegressionStep services-proc-race runServicesProcRaceRegression &&
        runRegressionStep singbox-ignore-client-proc runSingBoxRunningIgnoresClientProcessRegression &&
        runRegressionStep nginx-blog-auto-install runNginxBlogAutoInstallRegression &&
        runRegressionStep ui-smoke-light runRegressionFastUiSmokeLightSuiteRoot
}

runRegressionFastRealitySuiteRoot() {
    runRegressionFastSuiteRoot &&
        runRegressionStep reality-candidates-fast runRealityCandidateFastRegression
}

registerRegressionFunctionLeaf fast runRegressionFastSuiteRoot

listRegressionFastRealityChildSelectors() {
    printf '%s\n' \
        fast \
        reality-candidates-fast
}

registerRegressionAggregateRunnerSequential fast-reality runRegressionFastRealitySuiteRoot \
    $(listRegressionFastRealityChildSelectors)
