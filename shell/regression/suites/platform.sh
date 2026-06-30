#!/usr/bin/env bash

REGRESSION_PLATFORM_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_PLATFORM_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_PLATFORM_SUITE_DIR}/../subscription_groups_fast.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_PLATFORM_SUITE_DIR}/../subscription_groups_legacy.sh"

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

runInstallToolsCertificateDependencyCompatRegression() { runRegressionPlatformLegacyLeafWithCompat runInstallToolsCertificateDependencyRegression; }
runInstallToolsAcmeResultFailureCompatRegression() { runRegressionPlatformLegacyLeafWithCompat runInstallToolsAcmeResultFailureRegression; }
runInstallToolsAcmeCommitFailureCompatRegression() { runRegressionPlatformLegacyLeafWithCompat runInstallToolsAcmeCommitFailureRegression; }
runInstallToolsConfiguredLogCompatRegression() { runRegressionPlatformLegacyLeafWithCompat runInstallToolsUsesConfiguredInstallLogRegression; }
runInstallToolsUpdateFailureCompatRegression() { runRegressionPlatformLegacyLeafWithCompat runInstallToolsUpdateFailureRegression; }
runInstallToolsReleaseInfoFailureCompatRegression() { runRegressionPlatformLegacyLeafWithCompat runInstallToolsReleaseInfoFailureRegression; }
runInstallToolsNginxReinstallFailureCompatRegression() { runRegressionPlatformLegacyLeafWithCompat runInstallToolsNginxReinstallFailureRegression; }
runAptKeyInstallFailureCompatRegression() { runRegressionPlatformLegacyLeafWithCompat runAptKeyInstallFailureRegression; }
runNginxAptRefreshRollbackCompatRegression() { runRegressionPlatformLegacyLeafWithCompat runNginxAptRepoRefreshRollbackRegression; }
runNginxAlpineDefaultConfRollbackCompatRegression() { runRegressionPlatformLegacyLeafWithCompat runNginxAlpineDefaultConfRollbackRegression; }
runNginxYumMainlineEnableFailureCompatRegression() { runRegressionPlatformLegacyLeafWithCompat runNginxYumMainlineEnableFailureRegression; }
runBasePackageBatchCompatRegression() { runRegressionPlatformLegacyLeafWithCompat runBasePackageBatchRegression; }
runPackageRollbackFailureCompatRegression() { runRegressionPlatformLegacyLeafWithCompat runPackageRollbackFailureRegression; }
runPackageCommandStdinCompatRegression() { runRegressionPlatformLegacyLeafWithCompat runPackageCommandStdinRegression; }
runRealityScannerUnsafeDirCompatRegression() { runRegressionPlatformLegacyLeafWithCompat runRealityScannerRejectsUnsafeDirRegression; }
runRealityScannerBinaryCompatRegression() { runRegressionPlatformLegacyLeafWithCompat runRealityScannerBinaryRegression; }
runRealityScannerDownloadFailureCompatRegression() { runRegressionPlatformLegacyLeafWithCompat runRealityScannerDownloadFailureKeepsExistingDirRegression; }

runRegressionPlatformUpdateSuiteRoot() {
    runRegressionPlatformFastLeafWithCompat runRegressionPlatformUpdate
}

runRegressionPlatformRefreshSuiteRoot() {
    runRegressionPlatformFastLeafWithCompat runRegressionPlatformRefresh
}

runRegressionPlatformRestSuiteRoot() {
    runRegressionPlatformFastLeafWithCompat runRegressionPlatformRest
}

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

runRegressionPlatformHotSuiteRoot() {
    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/platform-hot-parallel-${BASHPID:-$$}" \
        listRegressionPlatformHotChildSelectors
}

runRegressionPlatformSuiteRoot() {
    runRegressionPlatformFastLeafWithCompat runRegressionPlatform
}

runRegressionPlatformHotParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-platform-hot-parallel-composition.log"

    : >"${callLog}"

    runRegressionPlatformUpdateSuiteRoot() {
        printf 'update-start\n' >>"${callLog}"
        while [[ ! -f "${TMP_DIR}/platform-refresh-started" ]]; do
            sleep 0.05
        done
        printf 'update-finish\n' >>"${callLog}"
    }

    runRegressionPlatformRefreshSuiteRoot() {
        printf 'refresh-start\n' >>"${callLog}"
        : >"${TMP_DIR}/platform-refresh-started"
        printf 'refresh-finish\n' >>"${callLog}"
    }

    runRegressionPlatformRestSuiteRoot() {
        printf 'rest\n' >>"${callLog}"
    }

    runRegressionPlatformHotSuiteRoot
    grep -qx 'update-start' "${callLog}"
    grep -qx 'refresh-start' "${callLog}"
    awk '
        $0 == "update-start" { updateStart = NR }
        $0 == "refresh-start" { refreshStart = NR }
        $0 == "update-finish" { updateFinish = NR }
        END { exit !(updateStart && refreshStart && updateFinish && refreshStart < updateFinish) }
    ' "${callLog}"
)

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

runRegressionPlatformIoSuiteRoot() {
    runFrameworkSequentialRegressionSelectorList listRegressionPlatformIoChildSelectors
}

registerRegressionFunctionLeaf platform-update runRegressionPlatformUpdateSuiteRoot
registerRegressionFunctionLeaf platform-refresh runRegressionPlatformRefreshSuiteRoot
registerRegressionFunctionLeaf platform-rest runRegressionPlatformRestSuiteRoot
registerRegressionFunctionLeaf platform-io runRegressionPlatformIoSuiteRoot
registerRegressionFunctionLeaf install-tools-certificate-dependency runInstallToolsCertificateDependencyCompatRegression
registerRegressionFunctionLeaf install-tools-acme-result-failure runInstallToolsAcmeResultFailureCompatRegression
registerRegressionFunctionLeaf install-tools-acme-commit-failure runInstallToolsAcmeCommitFailureCompatRegression
registerRegressionFunctionLeaf install-tools-configured-log runInstallToolsConfiguredLogCompatRegression
registerRegressionFunctionLeaf install-tools-update-failure runInstallToolsUpdateFailureCompatRegression
registerRegressionFunctionLeaf install-tools-release-info-failure runInstallToolsReleaseInfoFailureCompatRegression
registerRegressionFunctionLeaf install-tools-nginx-reinstall-failure runInstallToolsNginxReinstallFailureCompatRegression
registerRegressionFunctionLeaf apt-key-install-failure runAptKeyInstallFailureCompatRegression
registerRegressionFunctionLeaf nginx-apt-refresh-rollback runNginxAptRefreshRollbackCompatRegression
registerRegressionFunctionLeaf nginx-alpine-default-conf-rollback runNginxAlpineDefaultConfRollbackCompatRegression
registerRegressionFunctionLeaf nginx-yum-mainline-enable-failure runNginxYumMainlineEnableFailureCompatRegression
registerRegressionFunctionLeaf base-package-batch runBasePackageBatchCompatRegression
registerRegressionFunctionLeaf package-rollback-failure runPackageRollbackFailureCompatRegression
registerRegressionFunctionLeaf package-command-stdin runPackageCommandStdinCompatRegression
registerRegressionFunctionLeaf reality-scanner-unsafe-dir runRealityScannerUnsafeDirCompatRegression
registerRegressionFunctionLeaf reality-scanner-binary runRealityScannerBinaryCompatRegression
registerRegressionFunctionLeaf reality-scanner-download-failure runRealityScannerDownloadFailureCompatRegression
registerRegressionFunctionLeaf regression-platform-hot-parallel-composition runRegressionPlatformHotParallelCompositionRegression
registerRegressionFunctionLeaf regression-platform-fast-helper-isolation runRegressionPlatformFastHelperIsolationRegression

registerRegressionAggregateRunnerParallel platform-hot runRegressionPlatformHotSuiteRoot \
    $(listRegressionPlatformHotChildSelectors)
