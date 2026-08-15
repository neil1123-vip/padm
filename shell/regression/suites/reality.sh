#!/usr/bin/env bash

listRegressionRealitySuiteCandidatesChildSelectors() {
    printf '%s\n' \
        reality-candidates-fast \
        reality-asn-scan-plan \
        reality-candidates-full
}

registerRegressionFunctionLeaf reality-candidates-fast runRealityCandidateFastRegression
registerRegressionFunctionLeaf reality-asn-scan-plan runRealityAsnScanPlanRegression
registerRegressionFunctionLeaf reality-candidates-full runRealityCandidateFullRegression
registerRegressionFunctionLeaf reality-config runRealityConfigRegression
registerRegressionFunctionLeaf reality-profile-failure runRealityProfileFailureRegression

registerRegressionSequentialSelectorList reality-candidates listRegressionRealitySuiteCandidatesChildSelectors
