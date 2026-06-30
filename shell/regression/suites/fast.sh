#!/usr/bin/env bash

REGRESSION_FAST_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_FAST_SUITE_DIR}/../subscription_groups_fast.sh"

listRegressionFastOnlyOutputChildSelectors() {
    printf '%s\n' \
        fast-only-output-auto-install \
        fast-only-output-rest
}

runRegressionFastOnlyOutputSuiteRoot() {
    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/fast-only-output-parallel-${BASHPID:-$$}" \
        listRegressionFastOnlyOutputChildSelectors
}

runRegressionFastOnlyCoreSuiteRoot() {
    runRegressionStep singbox-mainpid-template runSingBoxServiceMainPidTemplateRegression &&
        runRegressionStep check-gfw-status-service-wait runCheckGFWStatusServiceWaitRegression &&
        runRegressionStep service-wait-state runServiceWaitForStateRegression &&
        runRegressionStep core-running-service-state runCoreRunningFallsBackToServiceStateRegression &&
        runRegressionStep warp-config-generation-failure runWarpConfigGenerationFailureRegression &&
        runRegressionStep fail2ban-profile runFail2banProfileRegression &&
        runRegressionStep fail2ban-sshd-systemd-backend runFail2banSshdSystemdBackendRegression &&
        runRegressionStep fail2ban-menu runFail2banMenuRegression &&
        runRegressionStep xray-strict-validation runXrayStrictValidationRegression &&
        runRegressionStep xray-compat-audit runXrayCompatibilityAuditRegression &&
        runRegressionStep xray-prerelease-dry-run runXrayPrereleaseDryRunRegression &&
        runRegressionStep singbox-compat-audit runSingBoxCompatibilityAuditRegression &&
        runRegressionStep singbox-prerelease-dry-run runSingBoxPrereleaseDryRunRegression &&
        runRegressionStep services-proc-race runServicesProcRaceRegression &&
        runRegressionStep singbox-ignore-client-proc runSingBoxRunningIgnoresClientProcessRegression &&
        runRegressionStep nginx-blog-auto-install runNginxBlogAutoInstallRegression &&
        runRegressionStep ui-smoke-light runRegressionUiSmokeSuiteRoot
}

listRegressionFastOnlyChildSelectors() {
    printf '%s\n' \
        fast-only-safety \
        fast-only-output \
        fast-only-core
}

runRegressionFastOnlySuiteRoot() {
    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/fast-only-parallel-${BASHPID:-$$}" \
        listRegressionFastOnlyChildSelectors
}

listRegressionFastChildSelectors() {
    printf '%s\n' \
        platform-hot \
        fast-only
}

runRegressionFastSuiteRoot() {
    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/fast-parallel-${BASHPID:-$$}" \
        listRegressionFastChildSelectors
}

runRegressionFastParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-fast-parallel-composition.log"

    : >"${callLog}"

    runRegressionPlatformSuiteRoot() {
        printf 'platform-start\n' >>"${callLog}"
        while [[ ! -f "${TMP_DIR}/fast-only-started" ]]; do
            sleep 0.05
        done
        printf 'platform-finish\n' >>"${callLog}"
    }

    runRegressionFastOnlySuiteRoot() {
        printf 'fast-only-start\n' >>"${callLog}"
        : >"${TMP_DIR}/fast-only-started"
        printf 'fast-only-finish\n' >>"${callLog}"
    }

    runRegressionFastSuiteRoot
    grep -qx 'platform-start' "${callLog}"
    grep -qx 'fast-only-start' "${callLog}"
    awk '
        $0 == "platform-start" { platformStart = NR }
        $0 == "fast-only-start" { fastOnlyStart = NR }
        $0 == "platform-finish" { platformFinish = NR }
        END { exit !(platformStart && fastOnlyStart && platformFinish && fastOnlyStart < platformFinish) }
    ' "${callLog}"
)

runRegressionFastOnlyParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-fast-only-parallel-composition.log"

    : >"${callLog}"

    runRegressionFastOnlySafety() {
        printf 'safety-start\n' >>"${callLog}"
        while [[ ! -f "${TMP_DIR}/fast-only-output-started" ]]; do
            sleep 0.05
        done
        printf 'safety-finish\n' >>"${callLog}"
    }

    runRegressionFastOnlyOutputSuiteRoot() {
        printf 'output-start\n' >>"${callLog}"
        : >"${TMP_DIR}/fast-only-output-started"
        printf 'output-finish\n' >>"${callLog}"
    }

    runRegressionFastOnlyCoreSuiteRoot() {
        printf 'core\n' >>"${callLog}"
    }

    runRegressionFastOnlySuiteRoot
    grep -qx 'safety-start' "${callLog}"
    grep -qx 'output-start' "${callLog}"
    awk '
        $0 == "safety-start" { safetyStart = NR }
        $0 == "output-start" { outputStart = NR }
        $0 == "safety-finish" { safetyFinish = NR }
        END { exit !(safetyStart && outputStart && safetyFinish && outputStart < safetyFinish) }
    ' "${callLog}"
)

runRegressionFastOnlyOutputParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-fast-only-output-parallel-composition.log"

    : >"${callLog}"

    runRegressionFastOnlyOutputAutoInstall() {
        printf 'auto-install-start\n' >>"${callLog}"
        while [[ ! -f "${TMP_DIR}/fast-only-subscription-started" ]]; do
            sleep 0.05
        done
        printf 'auto-install-finish\n' >>"${callLog}"
    }

    runRegressionFastOnlyOutputRest() {
        printf 'rest-start\n' >>"${callLog}"
        : >"${TMP_DIR}/fast-only-subscription-started"
        printf 'rest-finish\n' >>"${callLog}"
    }

    runRegressionFastOnlyOutputSuiteRoot
    grep -qx 'auto-install-start' "${callLog}"
    grep -qx 'rest-start' "${callLog}"
    awk '
        $0 == "auto-install-start" { autoInstallStart = NR }
        $0 == "rest-start" { restStart = NR }
        $0 == "auto-install-finish" { autoInstallFinish = NR }
        END { exit !(autoInstallStart && restStart && autoInstallFinish && restStart < autoInstallFinish) }
    ' "${callLog}"
)

runRegressionFastRealitySuiteRoot() {
    runFrameworkSequentialRegressionSelectorList listRegressionFastRealityChildSelectors
}

registerRegressionFunctionLeaf fast-only-safety runRegressionFastOnlySafety
registerRegressionFunctionLeaf fast-only-output-auto-install runRegressionFastOnlyOutputAutoInstall
registerRegressionFunctionLeaf fast-only-output-rest runRegressionFastOnlyOutputRest
registerRegressionFunctionLeaf fast-only-core runRegressionFastOnlyCoreSuiteRoot
registerRegressionFunctionLeaf regression-fast-parallel-composition runRegressionFastParallelCompositionRegression
registerRegressionFunctionLeaf regression-fast-only-parallel-composition runRegressionFastOnlyParallelCompositionRegression
registerRegressionFunctionLeaf regression-fast-only-output-parallel-composition runRegressionFastOnlyOutputParallelCompositionRegression

registerRegressionAggregateRunnerParallel fast-only-output runRegressionFastOnlyOutputSuiteRoot \
    $(listRegressionFastOnlyOutputChildSelectors)

registerRegressionAggregateRunnerParallel fast-only runRegressionFastOnlySuiteRoot \
    $(listRegressionFastOnlyChildSelectors)

registerRegressionAggregateRunnerParallel fast runRegressionFastSuiteRoot \
    $(listRegressionFastChildSelectors)

listRegressionFastRealityChildSelectors() {
    printf '%s\n' \
        fast \
        reality-candidates-fast
}

registerRegressionAggregateRunnerSequential fast-reality runRegressionFastRealitySuiteRoot \
    $(listRegressionFastRealityChildSelectors)
