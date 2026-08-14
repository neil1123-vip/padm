#!/usr/bin/env bash

REGRESSION_FAST_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_FAST_SUITE_DIR}/../subscription_groups_fast.sh"

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
registerRegressionFunctionLeaf regression-fast-parallel-composition runRegressionFastParallelCompositionRegression
registerRegressionFunctionLeaf regression-fast-only-parallel-composition runRegressionFastOnlyParallelCompositionRegression
registerRegressionFunctionLeaf regression-fast-only-output-parallel-composition runRegressionFastOnlyOutputParallelCompositionRegression

registerRegressionAggregateRunnerWithArgs parallel \
    fast-only-output \
    runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-only-output-parallel-${BASHPID:-$$}" \
    listRegressionFastOnlyOutputChildSelectors \
    -- \
    $(listRegressionFastOnlyOutputChildSelectors)

registerRegressionAggregateRunnerWithArgs parallel \
    fast-only \
    runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-only-parallel-${BASHPID:-$$}" \
    listRegressionFastOnlyChildSelectors \
    -- \
    $(listRegressionFastOnlyChildSelectors)

registerRegressionAggregateRunnerWithArgs sequential \
    fast-only-core \
    runFrameworkSequentialRegressionSelectorList \
    listRegressionFastOnlyCoreChildSelectors \
    -- \
    $(listRegressionFastOnlyCoreChildSelectors)

registerRegressionAggregateRunnerWithArgs parallel \
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

registerRegressionAggregateRunnerWithArgs sequential \
    fast-reality \
    runFrameworkSequentialRegressionSelectorList \
    listRegressionFastRealityChildSelectors \
    -- \
    $(listRegressionFastRealityChildSelectors)
