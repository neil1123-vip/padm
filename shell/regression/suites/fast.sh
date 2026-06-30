#!/usr/bin/env bash

REGRESSION_FAST_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_FAST_SUITE_DIR}/../subscription_groups_fast.sh"

listRegressionFastOnlyOutputChildSelectors() {
    printf '%s\n' \
        fast-only-output-auto-install \
        fast-only-output-rest
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

listRegressionFastChildSelectors() {
    printf '%s\n' \
        platform-hot \
        fast-only
}

runRegressionFastParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-fast-parallel-composition.log"

    : >"${callLog}"
    rm -f "${TMP_DIR}/fast-only-started"

    runRegressionAllSelector() {
        local selector=$1

        printf '%s-start\n' "${selector}" >>"${callLog}"
        if [[ "${selector}" == "platform-hot" ]]; then
            printf 'platform-start\n' >>"${callLog}"
        elif [[ "${selector}" == "fast-only" ]]; then
            printf 'fast-only-start\n' >>"${callLog}"
            : >"${TMP_DIR}/fast-only-started"
        fi
        while [[ ! -f "${TMP_DIR}/fast-only-started" ]]; do
            sleep 0.05
            [[ "${selector}" == "platform-hot" ]] || break
        done
        if [[ "${selector}" == "platform-hot" ]]; then
            printf 'platform-finish\n' >>"${callLog}"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegisteredRegressionMain fast
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
    rm -f "${TMP_DIR}/fast-only-output-started"

    runRegressionAllSelector() {
        local selector=$1

        printf '%s-start\n' "${selector}" >>"${callLog}"
        if [[ "${selector}" == "fast-only-safety" ]]; then
            printf 'safety-start\n' >>"${callLog}"
        elif [[ "${selector}" == "fast-only-output" ]]; then
            printf 'output-start\n' >>"${callLog}"
            : >"${TMP_DIR}/fast-only-output-started"
        fi
        while [[ ! -f "${TMP_DIR}/fast-only-output-started" ]]; do
            sleep 0.05
            [[ "${selector}" == "fast-only-safety" ]] || break
        done
        if [[ "${selector}" == "fast-only-safety" ]]; then
            printf 'safety-finish\n' >>"${callLog}"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegisteredRegressionMain fast-only
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
    rm -f "${TMP_DIR}/fast-only-subscription-started"

    runRegressionAllSelector() {
        local selector=$1

        printf '%s-start\n' "${selector}" >>"${callLog}"
        if [[ "${selector}" == "fast-only-output-auto-install" ]]; then
            printf 'auto-install-start\n' >>"${callLog}"
        elif [[ "${selector}" == "fast-only-output-rest" ]]; then
            printf 'rest-start\n' >>"${callLog}"
            : >"${TMP_DIR}/fast-only-subscription-started"
        fi
        while [[ ! -f "${TMP_DIR}/fast-only-subscription-started" ]]; do
            sleep 0.05
            [[ "${selector}" == "fast-only-output-auto-install" ]] || break
        done
        if [[ "${selector}" == "fast-only-output-auto-install" ]]; then
            printf 'auto-install-finish\n' >>"${callLog}"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegisteredRegressionMain fast-only-output
    grep -qx 'auto-install-start' "${callLog}"
    grep -qx 'rest-start' "${callLog}"
    awk '
        $0 == "auto-install-start" { autoInstallStart = NR }
        $0 == "rest-start" { restStart = NR }
        $0 == "auto-install-finish" { autoInstallFinish = NR }
        END { exit !(autoInstallStart && restStart && autoInstallFinish && restStart < autoInstallFinish) }
    ' "${callLog}"
)

registerRegressionFunctionLeaf fast-only-safety runRegressionFastOnlySafety
registerRegressionFunctionLeaf fast-only-output-auto-install runRegressionFastOnlyOutputAutoInstall
registerRegressionFunctionLeaf fast-only-output-rest runRegressionFastOnlyOutputRest
registerRegressionFunctionLeaf fast-only-core runRegressionFastOnlyCoreSuiteRoot
registerRegressionFunctionLeaf regression-fast-parallel-composition runRegressionFastParallelCompositionRegression
registerRegressionFunctionLeaf regression-fast-only-parallel-composition runRegressionFastOnlyParallelCompositionRegression
registerRegressionFunctionLeaf regression-fast-only-output-parallel-composition runRegressionFastOnlyOutputParallelCompositionRegression

registerRegressionAggregateRunnerParallelWithArgs \
    fast-only-output \
    runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-only-output-parallel-${BASHPID:-$$}" \
    listRegressionFastOnlyOutputChildSelectors \
    -- \
    $(listRegressionFastOnlyOutputChildSelectors)

registerRegressionAggregateRunnerParallelWithArgs \
    fast-only \
    runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-only-parallel-${BASHPID:-$$}" \
    listRegressionFastOnlyChildSelectors \
    -- \
    $(listRegressionFastOnlyChildSelectors)

registerRegressionAggregateRunnerParallelWithArgs \
    fast \
    runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-parallel-${BASHPID:-$$}" \
    listRegressionFastChildSelectors \
    -- \
    $(listRegressionFastChildSelectors)

listRegressionFastRealityChildSelectors() {
    printf '%s\n' \
        fast \
        reality-candidates-fast
}

registerRegressionAggregateRunnerSequentialWithArgs \
    fast-reality \
    runFrameworkSequentialRegressionSelectorList \
    listRegressionFastRealityChildSelectors \
    -- \
    $(listRegressionFastRealityChildSelectors)
