#!/usr/bin/env bash

REGRESSION_REALITY_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_REALITY_SUITE_DIR}/../subscription_groups_legacy.sh"

runRegressionRealityLegacyLeafWithCompat() (
    # Re-source legacy reality fixtures in an isolated subshell so later suite
    # loads cannot leave source-time TMP_DIR-derived paths stale.
    PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_REALITY_SUITE_DIR}/../subscription_groups_legacy.sh"
    "$@"
)

runRegressionRealityCandidatesSuiteRoot() {
    runFrameworkSequentialRegressionSelectorList listRegressionRealitySuiteCandidatesChildSelectors
}

runRegressionRealityStreamSuiteRoot() {
    runFrameworkSequentialRegressionSelectorList listRegressionRealitySuiteStreamChildSelectors
}

runRegressionRealityLegacyTmpDirIsolationRegression() (
    set -euo pipefail
    local originalTmpDir="${TMP_DIR}"

    # Simulate later suite loads re-sourcing bootstrap and drifting TMP_DIR.
    source "${REGRESSION_REALITY_SUITE_DIR}/../bootstrap.sh"
    [[ "${TMP_DIR}" != "${originalTmpDir}" ]]

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain reality-config
)

listRegressionRealitySuiteStreamChildSelectors() {
    printf '%s\n' \
        reality-stream-enable \
        reality-stream-disable
}

listRegressionRealitySuiteCandidatesChildSelectors() {
    printf '%s\n' \
        reality-candidates-fast \
        reality-asn-scan-plan \
        reality-candidates-full
}

registerRegressionFunctionLeaf reality-candidates-fast runRegressionRealityLegacyLeafWithCompat runRealityCandidateFastRegression
registerRegressionFunctionLeaf reality-asn-scan-plan runRegressionRealityLegacyLeafWithCompat runRealityAsnScanPlanRegression
registerRegressionFunctionLeaf reality-candidates-full runRegressionRealityLegacyLeafWithCompat runRealityCandidateFullRegression
registerRegressionFunctionLeaf reality-stream-enable runRegressionRealityLegacyLeafWithCompat runRealityStreamEnableRegression
registerRegressionFunctionLeaf reality-stream-disable runRegressionRealityLegacyLeafWithCompat runRealityStreamDisableRegression
registerRegressionFunctionLeaf reality-config runRegressionRealityLegacyLeafWithCompat runRealityConfigRegression
registerRegressionFunctionLeaf reality-profile-failure runRegressionRealityLegacyLeafWithCompat runRealityProfileFailureRegression
registerRegressionFunctionLeaf regression-reality-legacy-tmpdir-isolation runRegressionRealityLegacyTmpDirIsolationRegression

registerRegressionAggregateRunnerSequential reality-candidates runRegressionRealityCandidatesSuiteRoot \
    $(listRegressionRealitySuiteCandidatesChildSelectors)
registerRegressionAggregateRunnerSequential reality-stream runRegressionRealityStreamSuiteRoot \
    $(listRegressionRealitySuiteStreamChildSelectors)
