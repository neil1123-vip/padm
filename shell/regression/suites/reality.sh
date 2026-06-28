#!/usr/bin/env bash

REGRESSION_REALITY_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_REALITY_SUITE_DIR}/../subscription_groups_legacy.sh"

runRegressionRealityCandidatesSuiteRoot() {
    runRegressionStep reality-candidates-fast runRealityCandidateFastRegression &&
        runRegressionStep reality-asn-scan-plan runRealityAsnScanPlanRegression &&
        runRegressionStep reality-candidates-full runRealityCandidateFullRegression
}

runRegressionRealityStreamSuiteRoot() {
    runRegressionStep reality-stream-enable runRealityStreamEnableRegression &&
        runRegressionStep reality-stream-disable runRealityStreamDisableRegression
}

runRegressionRealityCandidates() {
    runRegressionRealityCandidatesSuiteRoot
}

runRegressionRealityStream() {
    runRegressionRealityStreamSuiteRoot
}

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

registerRegressionFunctionLeaf reality-candidates-fast runRealityCandidateFastRegression
registerRegressionFunctionLeaf reality-asn-scan-plan runRealityAsnScanPlanRegression
registerRegressionFunctionLeaf reality-candidates-full runRealityCandidateFullRegression
registerRegressionFunctionLeaf reality-stream-enable runRealityStreamEnableRegression
registerRegressionFunctionLeaf reality-stream-disable runRealityStreamDisableRegression
registerRegressionFunctionLeaf reality-config runRealityConfigRegression
registerRegressionFunctionLeaf reality-profile-failure runRealityProfileFailureRegression

registerRegressionAggregateRunnerSequential reality-candidates runRegressionRealityCandidatesSuiteRoot \
    $(listRegressionRealitySuiteCandidatesChildSelectors)
registerRegressionAggregateRunnerSequential reality-stream runRegressionRealityStreamSuiteRoot \
    $(listRegressionRealitySuiteStreamChildSelectors)
