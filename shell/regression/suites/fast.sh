#!/usr/bin/env bash

listRegressionFastOnlyOutputChildSelectors() {
    printf '%s\n' \
        fast-only-output-auto-install \
        fast-only-output-rest
}

listRegressionFastOnlyChildSelectors() {
    printf '%s\n' \
        fast-only-safety \
        fast-only-output
}

listRegressionFastChildSelectors() {
    printf '%s\n' \
        platform-hot \
        fast-only
}

registerRegressionFunctionLeaf fast-only-safety runRegressionFastOnlySafety
registerRegressionFunctionLeaf fast-only-output-auto-install runRegressionFastOnlyOutputAutoInstall
registerRegressionFunctionLeaf fast-only-output-rest runRegressionFastOnlyOutputRest

registerRegressionParallelSelectorList fast-only-output runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-only-output-parallel-${BASHPID:-$$}" listRegressionFastOnlyOutputChildSelectors
registerRegressionParallelSelectorList fast-only runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-only-parallel-${BASHPID:-$$}" listRegressionFastOnlyChildSelectors

registerRegressionParallelSelectorList fast runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-parallel-${BASHPID:-$$}" listRegressionFastChildSelectors
