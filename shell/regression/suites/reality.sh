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

while read -r selector runner; do
    registerRegressionFunctionLeaf "${selector}" "${runner}"
done <<'EOF'
reality-candidates-fast runRealityCandidateFastRegression
reality-asn-scan-plan runRealityAsnScanPlanRegression
reality-candidates-full runRealityCandidateFullRegression
reality-stream-enable runRealityStreamEnableRegression
reality-stream-disable runRealityStreamDisableRegression
reality-config runRealityConfigRegression
reality-profile-failure runRealityProfileFailureRegression
EOF

registerRegressionAggregateRunnerSequential reality-candidates runRegressionRealityCandidatesSuiteRoot \
    $(listRegressionRealityCandidatesChildSelectors)
registerRegressionAggregateRunnerSequential reality-stream runRegressionRealityStreamSuiteRoot \
    $(listRegressionRealityStreamChildSelectors)
