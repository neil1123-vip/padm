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

registerRegressionFunctionLeaf platform-update runRegressionPlatformUpdateSuiteRoot
registerRegressionFunctionLeaf platform-refresh runRegressionPlatformRefreshSuiteRoot
registerRegressionFunctionLeaf platform-rest runRegressionPlatformRestSuiteRoot
registerRegressionFunctionLeaf platform-io runRegressionPlatformIoSuiteRoot
registerRegressionFunctionLeaf regression-platform-hot-parallel-composition runRegressionPlatformHotParallelCompositionRegression
registerRegressionFunctionLeaf regression-platform-fast-helper-isolation runRegressionPlatformFastHelperIsolationRegression

registerRegressionAggregateRunnerParallel platform-hot runRegressionPlatformHotSuiteRoot \
    $(listRegressionPlatformHotChildSelectors)
