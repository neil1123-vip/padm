#!/usr/bin/env bash

REGRESSION_FAST_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_FAST_SUITE_DIR}/../subscription_groups_fast.sh"

_fast_root_suite_def=$(declare -f runRegressionFast)
_fast_root_suite_def="${_fast_root_suite_def/runRegressionFast/runRegressionFastSuiteRoot}"
_fast_root_suite_def="${_fast_root_suite_def/runRegressionPlatform/runRegressionPlatformSuiteRoot}"
eval "${_fast_root_suite_def}"

unset _fast_root_suite_def

runRegressionFastRealitySuiteRoot() {
    runRegressionFastSuiteRoot &&
        runRegressionStep reality-candidates-fast runRealityCandidateFastRegression
}

registerRegressionFunctionLeaf fast runRegressionFastSuiteRoot

listRegressionFastRealityChildSelectors() {
    printf '%s\n' \
        fast \
        reality-candidates-fast
}

registerRegressionAggregateRunnerSequential fast-reality runRegressionFastRealitySuiteRoot \
    $(listRegressionFastRealityChildSelectors)
