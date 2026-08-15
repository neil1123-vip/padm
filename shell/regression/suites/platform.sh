#!/usr/bin/env bash

REGRESSION_PLATFORM_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_PLATFORM_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_PLATFORM_SUITE_DIR}/../subscription_groups_fast.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_PLATFORM_SUITE_DIR}/../subscription_groups_legacy.sh" --reuse

runRegressionPlatformFastLeafWithCompat() (
    # Re-source fast platform fixtures in an isolated subshell so later suite
    # loads cannot overwrite fast-only platform leaf dependencies.
    PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_PLATFORM_SUITE_DIR}/../subscription_groups_fast.sh"
    "$@"
)

runRegressionPlatformLegacyLeafWithCompat() (
    # Re-source legacy platform fixtures in an isolated subshell so later suite
    # loads cannot leave source-time TMP_DIR-derived paths stale.
    PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_PLATFORM_SUITE_DIR}/../subscription_groups_legacy.sh"
    "$@"
)

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

runRegressionPlatformFastHelperIsolationRegression() (
    set -euo pipefail
    local legacyBody fastBody

    capturePlatformUpdateRunnerBody() {
        declare -f runUpdatePadmVersionPromptRegression
    }

    legacyBody=$(capturePlatformUpdateRunnerBody)
    fastBody=$(runRegressionPlatformFastLeafWithCompat capturePlatformUpdateRunnerBody)

    grep -Fq 'successLog="${TMP_DIR}/update-padm-success.log"' <<<"${legacyBody}"
    grep -Fq 'replaceFailureDir="${TMP_DIR}/update-padm-replace-restore-failure"' <<<"${legacyBody}"
    grep -Fq 'outputLog="${TMP_DIR}/update-padm-output.log"' <<<"${fastBody}"
    grep -Fq 'replaceFailureDir="${TMP_DIR}/update-padm-replace-failure"' <<<"${fastBody}"
)

registerRegressionFunctionLeaf platform-update runRegressionPlatformFastLeafWithCompat runRegressionPlatformUpdate
registerRegressionFunctionLeaf platform-refresh runRegressionPlatformFastLeafWithCompat runRegressionPlatformRefresh
registerRegressionFunctionLeaf platform-rest runRegressionPlatformFastLeafWithCompat runRegressionPlatformRest
registerRegressionFunctionLeaf install-tools-certificate-dependency runRegressionPlatformLegacyLeafWithCompat runInstallToolsCertificateDependencyRegression
registerRegressionFunctionLeaf install-tools-acme-result-failure runRegressionPlatformLegacyLeafWithCompat runInstallToolsAcmeResultFailureRegression
registerRegressionFunctionLeaf install-tools-acme-commit-failure runRegressionPlatformLegacyLeafWithCompat runInstallToolsAcmeCommitFailureRegression
registerRegressionFunctionLeaf install-tools-acme-download-bounds runRegressionPlatformLegacyLeafWithCompat runInstallToolsAcmeDownloadBoundsRegression
registerRegressionFunctionLeaf install-tools-configured-log runRegressionPlatformLegacyLeafWithCompat runInstallToolsUsesConfiguredInstallLogRegression
registerRegressionFunctionLeaf install-tools-update-failure runRegressionPlatformLegacyLeafWithCompat runInstallToolsRefreshFailureRegression update
registerRegressionFunctionLeaf install-tools-release-info-failure runRegressionPlatformLegacyLeafWithCompat runInstallToolsRefreshFailureRegression release-info
registerRegressionFunctionLeaf install-tools-nginx-reinstall-failure runRegressionPlatformLegacyLeafWithCompat runInstallToolsNginxReinstallFailureRegression
registerRegressionFunctionLeaf apt-key-install-failure runRegressionPlatformLegacyLeafWithCompat runAptKeyInstallFailureRegression
registerRegressionFunctionLeaf nginx-apt-refresh-rollback runRegressionPlatformLegacyLeafWithCompat runNginxAptRepoRefreshRollbackRegression
registerRegressionFunctionLeaf nginx-alpine-default-conf-rollback runRegressionPlatformLegacyLeafWithCompat runNginxAlpineDefaultConfRollbackRegression
registerRegressionFunctionLeaf nginx-yum-mainline-enable-failure runRegressionPlatformLegacyLeafWithCompat runNginxYumMainlineEnableFailureRegression
registerRegressionFunctionLeaf base-package-batch runRegressionPlatformLegacyLeafWithCompat runBasePackageBatchRegression
registerRegressionFunctionLeaf package-rollback-failure runRegressionPlatformLegacyLeafWithCompat runPackageRollbackFailureRegression
registerRegressionFunctionLeaf package-command-stdin runRegressionPlatformLegacyLeafWithCompat runPackageCommandStdinRegression
registerRegressionFunctionLeaf reality-scanner-unsafe-dir runRegressionPlatformLegacyLeafWithCompat runRealityScannerRejectsUnsafeDirRegression
registerRegressionFunctionLeaf reality-scanner-binary runRegressionPlatformLegacyLeafWithCompat runRealityScannerBinaryRegression
registerRegressionFunctionLeaf reality-scanner-download-failure runRegressionPlatformLegacyLeafWithCompat runRealityScannerDownloadFailureKeepsExistingDirRegression
registerRegressionFunctionLeaf regression-platform-hot-parallel-composition runFrameworkParallelCompositionContract platform-hot platform-update platform-refresh
registerRegressionFunctionLeaf regression-platform-fast-helper-isolation runRegressionPlatformFastHelperIsolationRegression

registerRegressionAggregateRunnerWithArgs sequential \
    platform-io \
    runFrameworkSequentialRegressionSelectorList \
    listRegressionPlatformIoChildSelectors \
    -- \
    $(listRegressionPlatformIoChildSelectors)

registerRegressionAggregateRunnerWithArgs parallel \
    platform-hot \
    runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/platform-hot-parallel-${BASHPID:-$$}" \
    listRegressionPlatformHotChildSelectors \
    -- \
    $(listRegressionPlatformHotChildSelectors)
