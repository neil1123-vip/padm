#!/usr/bin/env bash

listRegressionFastOnlyOutputChildSelectors() {
    printf '%s\n' \
        fast-only-output-auto-install \
        fast-only-output-rest
}

listRegressionFastOnlyCoreChildSelectors() {
    printf '%s\n' \
        singbox-mainpid-template \
        check-gfw-status-service-wait \
        service-wait-state \
        core-running-service-state \
        warp-config-generation-failure \
        fail2ban-profile \
        fail2ban-sshd-systemd-backend \
        fail2ban-menu \
        xray-configured-service-path \
        xray-strict-validation \
        xray-compat-audit \
        xray-compat-trusted-xff \
        xray-configured-validation-path \
        xray-prerelease-dry-run \
        core-release-tags-pagination \
        core-rollback-selection \
        singbox-compat-audit \
        singbox-prerelease-dry-run \
        singbox-log-menu-disable-return \
        reality-stream-split-status-disabled-return \
        services-proc-race \
        singbox-ignore-client-proc \
        nginx-blog-auto-install \
        ui-smoke-light
}

listRegressionFastOnlyChildSelectors() {
    printf '%s\n' \
        fast-only-safety \
        fast-only-output \
        fast-only-core
}

listRegressionFastChildSelectors() {
    printf '%s\n' \
        platform-hot \
        fast-only
}

registerRegressionFunctionLeaf fast-only-safety runRegressionFastOnlySafety
registerRegressionFunctionLeaf fast-only-output-auto-install runRegressionFastOnlyOutputAutoInstall
registerRegressionFunctionLeaf fast-only-output-rest runRegressionFastOnlyOutputRest
registerRegressionFunctionLeaf singbox-mainpid-template runSingBoxServiceMainPidTemplateRegression
registerRegressionFunctionLeaf check-gfw-status-service-wait runCheckGFWStatusServiceWaitRegression
registerRegressionFunctionLeaf service-wait-state runServiceWaitForStateRegression
registerRegressionFunctionLeaf core-running-service-state runCoreRunningFallsBackToServiceStateRegression
registerRegressionFunctionLeaf read-install-type-keeps-sing-box-shards runReadInstallTypeKeepsSingBoxShardsRegression
registerRegressionFunctionLeaf check-log-backup-output-variable runCheckLogBackupOutputVariableRegression
registerRegressionFunctionLeaf warp-config-generation-failure runWarpConfigGenerationFailureRegression
registerRegressionFunctionLeaf fail2ban-profile runFail2banProfileRegression
registerRegressionFunctionLeaf fail2ban-sshd-systemd-backend runFail2banSshdSystemdBackendRegression
registerRegressionFunctionLeaf fail2ban-menu runFail2banMenuRegression
registerRegressionFunctionLeaf xray-configured-service-path runXrayConfiguredServicePathRegression
registerRegressionFunctionLeaf xray-strict-validation runXrayStrictValidationRegression
registerRegressionFunctionLeaf xray-compat-audit runXrayCompatibilityAuditRegression
registerRegressionFunctionLeaf xray-compat-trusted-xff runXrayCompatibilityTrustedXffRegression
registerRegressionFunctionLeaf xray-configured-validation-path runXrayConfiguredValidationPathRegression
registerRegressionFunctionLeaf xray-prerelease-dry-run runXrayPrereleaseDryRunRegression
registerRegressionFunctionLeaf core-release-tags-pagination runCoreReleaseTagsPaginationRegression
registerRegressionFunctionLeaf core-rollback-selection runCoreRollbackSelectionRegression
registerRegressionFunctionLeaf singbox-compat-audit runSingBoxCompatibilityAuditRegression
registerRegressionFunctionLeaf singbox-prerelease-dry-run runSingBoxPrereleaseDryRunRegression
registerRegressionFunctionLeaf singbox-log-menu-disable-return runSingBoxLogMenuDisableReturnRegression
registerRegressionFunctionLeaf reality-stream-split-status-disabled-return runRealityStreamSplitStatusDisabledReturnRegression
registerRegressionFunctionLeaf services-proc-race runServicesProcRaceRegression
registerRegressionFunctionLeaf singbox-ignore-client-proc runSingBoxRunningIgnoresClientProcessRegression
registerRegressionFunctionLeaf nginx-blog-auto-install runNginxBlogAutoInstallRegression
registerRegressionFunctionLeaf ui-smoke-light runRegressionUiSmokeSuiteRoot
registerRegressionFunctionLeaf regression-fast-parallel-composition runFrameworkParallelCompositionContract fast platform-hot fast-only
registerRegressionFunctionLeaf regression-fast-only-parallel-composition runFrameworkParallelCompositionContract fast-only fast-only-safety fast-only-output
registerRegressionFunctionLeaf regression-fast-only-output-parallel-composition runFrameworkParallelCompositionContract fast-only-output fast-only-output-auto-install fast-only-output-rest

registerRegressionParallelSelectorList fast-only-output runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-only-output-parallel-${BASHPID:-$$}" listRegressionFastOnlyOutputChildSelectors
registerRegressionParallelSelectorList fast-only runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-only-parallel-${BASHPID:-$$}" listRegressionFastOnlyChildSelectors

registerRegressionSequentialSelectorList fast-only-core listRegressionFastOnlyCoreChildSelectors

registerRegressionParallelSelectorList fast runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-parallel-${BASHPID:-$$}" listRegressionFastChildSelectors

listRegressionFastRealityChildSelectors() {
    printf '%s\n' \
        fast \
        reality-candidates-fast
}

registerRegressionSequentialSelectorList fast-reality listRegressionFastRealityChildSelectors
