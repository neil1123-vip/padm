#!/usr/bin/env bash

listRegressionPlatformHotChildSelectors() {
    printf '%s\n' \
        platform-update \
        platform-refresh \
        platform-rest
}

listRegressionPlatformIoChildSelectors() {
    printf '%s\n' \
        install-tools-certificate-dependency \
        install-tools-acme-result-failure \
        install-tools-acme-commit-failure \
        install-tools-acme-download-bounds \
        install-tools-configured-log \
        install-tools-update-failure \
        install-tools-release-info-failure \
        install-tools-nginx-reinstall-failure \
        apt-key-install-failure \
        nginx-apt-refresh-rollback \
        nginx-alpine-default-conf-rollback \
        nginx-yum-mainline-enable-failure \
        base-package-batch \
        package-rollback-failure \
        package-command-stdin \
        reality-scanner-unsafe-dir \
        reality-scanner-binary \
        reality-scanner-download-failure
}

registerRegressionFunctionLeaf platform-update runRegressionPlatformUpdate
registerRegressionFunctionLeaf platform-refresh runRegressionPlatformRefresh
registerRegressionFunctionLeaf platform-rest runRegressionPlatformRest
registerRegressionFunctionLeaf install-tools-certificate-dependency runInstallToolsCertificateDependencyRegression
registerRegressionFunctionLeaf install-tools-acme-result-failure runInstallToolsAcmeResultFailureRegression
registerRegressionFunctionLeaf install-tools-acme-commit-failure runInstallToolsAcmeCommitFailureRegression
registerRegressionFunctionLeaf install-tools-acme-download-bounds runInstallToolsAcmeDownloadBoundsRegression
registerRegressionFunctionLeaf install-tools-configured-log runInstallToolsUsesConfiguredInstallLogRegression
registerRegressionFunctionLeaf install-tools-update-failure runInstallToolsRefreshFailureRegression update
registerRegressionFunctionLeaf install-tools-release-info-failure runInstallToolsRefreshFailureRegression release-info
registerRegressionFunctionLeaf install-tools-nginx-reinstall-failure runInstallToolsNginxReinstallFailureRegression
registerRegressionFunctionLeaf apt-key-install-failure runAptKeyInstallFailureRegression
registerRegressionFunctionLeaf nginx-apt-refresh-rollback runNginxAptRepoRefreshRollbackRegression
registerRegressionFunctionLeaf nginx-alpine-default-conf-rollback runNginxAlpineDefaultConfRollbackRegression
registerRegressionFunctionLeaf nginx-yum-mainline-enable-failure runNginxYumMainlineEnableFailureRegression
registerRegressionFunctionLeaf base-package-batch runBasePackageBatchRegression
registerRegressionFunctionLeaf package-rollback-failure runPackageRollbackFailureRegression
registerRegressionFunctionLeaf package-command-stdin runPackageCommandStdinRegression
registerRegressionFunctionLeaf reality-scanner-unsafe-dir runRealityScannerRejectsUnsafeDirRegression
registerRegressionFunctionLeaf reality-scanner-binary runRealityScannerBinaryRegression
registerRegressionFunctionLeaf reality-scanner-download-failure runRealityScannerDownloadFailureKeepsExistingDirRegression
registerRegressionFunctionLeaf regression-platform-hot-parallel-composition runFrameworkParallelCompositionContract platform-hot platform-update platform-refresh

registerRegressionSequentialSelectorList platform-io listRegressionPlatformIoChildSelectors

registerRegressionParallelSelectorList platform-hot runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/platform-hot-parallel-${BASHPID:-$$}" listRegressionPlatformHotChildSelectors
