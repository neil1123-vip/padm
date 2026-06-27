#!/usr/bin/env bash

REGRESSION_RUNTIME_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_RUNTIME_SUITE_DIR}/../subscription_groups_legacy.sh"

runRegressionRuntimeSuiteRoot() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    if [[ "${PADM_REGRESSION_RUNTIME_RESOURCE_PROFILE:-}" == "all" ]]; then
        mapfile -t selectors < <(listRegressionRuntimeLightChildSelectors)
        selectorPairs=()
        for selector in "${selectors[@]}"; do
            selectorPairs+=("${selector}" "${selector}")
        done
        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_RUNTIME_LIGHT_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}" \
            runParallelRegressionSelectors "${TMP_DIR}/runtime-parallel-light-${BASHPID:-$$}" \
            "${selectorPairs[@]}"
        mapfile -t selectors < <(listRegressionRuntimeHeavyChildSelectors)
        selectorPairs=()
        for selector in "${selectors[@]}"; do
            selectorPairs+=("${selector}" "${selector}")
        done
        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_RUNTIME_HEAVY_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-2}}" \
            runParallelRegressionSelectors "${TMP_DIR}/runtime-parallel-heavy-${BASHPID:-$$}" \
            "${selectorPairs[@]}"
        return
    fi

    runRegressionStep runtime-core runRuntimeAndRealityRegression &&
        runRegressionStep runtime-autoread-unset-auto-install runAutoReadUnsetAutoInstallRegression &&
        runRegressionStep runtime-auto-install-reality-route runAutoInstallRealityRouteRegression &&
        runRegressionStep runtime-tempdir runRuntimeTempDirRegression &&
        runRegressionStep reality-candidates runRegressionRealityCandidates &&
        runRegressionStep reality-config runRealityConfigRegression
}

listRegressionRealityStreamChildSelectors() {
    printf '%s\n' \
        reality-stream-enable \
        reality-stream-disable
}

listRegressionRealityCandidatesChildSelectors() {
    printf '%s\n' \
        reality-candidates-fast \
        reality-asn-scan-plan \
        reality-candidates-full
}

listRegressionRuntimeLightChildSelectors() {
    printf '%s\n' \
        runtime-core \
        runtime-autoread-unset-auto-install \
        runtime-auto-install-reality-route \
        runtime-tempdir
}

listRegressionRuntimeHeavyChildSelectors() {
    printf '%s\n' \
        reality-candidates \
        reality-config
}

listRegressionRuntimeChildSelectors() {
    listRegressionRuntimeLightChildSelectors
    listRegressionRuntimeHeavyChildSelectors
}

registerRegressionFunctionLeaf reality-candidates-fast runRealityCandidateFastRegression
registerRegressionFunctionLeaf reality-asn-scan-plan runRealityAsnScanPlanRegression
registerRegressionFunctionLeaf reality-candidates-full runRealityCandidateFullRegression
registerRegressionFunctionLeaf reality-stream-enable runRealityStreamEnableRegression
registerRegressionFunctionLeaf reality-stream-disable runRealityStreamDisableRegression
registerRegressionFunctionLeaf runtime-core runRuntimeAndRealityRegression
registerRegressionFunctionLeaf runtime-autoread-unset-auto-install runAutoReadUnsetAutoInstallRegression
registerRegressionFunctionLeaf runtime-auto-install-reality-route runAutoInstallRealityRouteRegression
registerRegressionFunctionLeaf runtime-tempdir runRuntimeTempDirRegression
registerRegressionFunctionLeaf reality-config runRealityConfigRegression
registerRegressionFunctionLeaf reality-profile-failure runRealityProfileFailureRegression

registerRegressionAggregateRunnerSequential reality-candidates runRegressionRealityCandidates \
    $(listRegressionRealityCandidatesChildSelectors)
registerRegressionAggregateRunnerSequential reality-stream runRegressionRealityStream \
    $(listRegressionRealityStreamChildSelectors)
registerRegressionAggregateRunnerParallel runtime runRegressionRuntimeSuiteRoot \
    $(listRegressionRuntimeChildSelectors)
