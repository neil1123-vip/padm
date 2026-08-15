#!/usr/bin/env bash

listRegressionPlatformHotChildSelectors() {
    printf '%s\n' \
        platform-update \
        platform-refresh \
        platform-rest
}

registerRegressionFunctionLeaf platform-update runRegressionPlatformUpdate
registerRegressionFunctionLeaf platform-refresh runRegressionPlatformRefresh
registerRegressionFunctionLeaf platform-rest runRegressionPlatformRest
registerRegressionParallelSelectorList platform-hot runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/platform-hot-parallel-${BASHPID:-$$}" listRegressionPlatformHotChildSelectors
