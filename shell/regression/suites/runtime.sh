#!/usr/bin/env bash

runRegressionRuntimeSuiteRoot() {
    if [[ "${PADM_REGRESSION_RUNTIME_RESOURCE_PROFILE:-}" == "all" ]]; then
        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_RUNTIME_LIGHT_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}" \
            runFrameworkParallelRegressionSelectorList "${TMP_DIR}/runtime-parallel-light-${BASHPID:-$$}" \
            listRegressionRuntimeLightChildSelectors
        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_RUNTIME_HEAVY_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-2}}" \
            runFrameworkParallelRegressionSelectorList "${TMP_DIR}/runtime-parallel-heavy-${BASHPID:-$$}" \
            listRegressionRuntimeHeavyChildSelectors
        return
    fi

    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/runtime-parallel-${BASHPID:-$$}" \
        listRegressionRuntimeChildSelectors
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

registerRegressionFunctionLeaf runtime-core runRuntimeAndRealityRegression
registerRegressionFunctionLeaf runtime-autoread-unset-auto-install runAutoReadUnsetAutoInstallRegression
registerRegressionFunctionLeaf runtime-auto-install-reality-route runAutoInstallRealityRouteRegression
registerRegressionFunctionLeaf runtime-tempdir runRuntimeTempDirRegression

registerRegressionAggregateRunner parallel runtime runRegressionRuntimeSuiteRoot \
    $(listRegressionRuntimeChildSelectors)
