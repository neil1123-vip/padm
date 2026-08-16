#!/usr/bin/env bash

listRegressionSubscriptionOutputChildSelectors() {
    printf '%s\n' \
        subscription-output-profile-and-reality \
        subscription-output-publish-accounts-and-remote-hint \
        subscription-output-tls-vless-vmess-trojan \
        subscription-output-tls-any-hysteria-tuic-naive
}

listRegressionSubscriptionLightChildSelectors() {
    printf '%s\n' \
        subscription-output \
        subscription-state
}

listRegressionSubscriptionHeavyChildSelectors() {
    printf '%s\n' subscription-safety
}

listRegressionSubscriptionChildSelectors() {
    printf '%s\n' \
        subscription-output \
        subscription-state \
        subscription-safety
}

runSubscriptionSelectorListRegression() {
    local orchestrationLabel=$1
    local selectorListFn=$2
    local defaultJobs=${3:-}
    local overrideJobsVar=${4:-}
    local jobs=

    if [[ -n "${overrideJobsVar}" ]]; then
        jobs="${!overrideJobsVar:-}"
    fi
    if [[ -z "${jobs}" && -n "${defaultJobs}" ]]; then
        jobs="${PADM_REGRESSION_PARALLEL_JOBS:-${defaultJobs}}"
    fi

    runFrameworkParallelRegressionSelectorListWithJobs "${TMP_DIR}/${orchestrationLabel}-${BASHPID:-$$}" \
        "${selectorListFn}" \
        "${jobs}"
}

runRegressionSubscriptionSuiteRoot() {
    if [[ "${PADM_REGRESSION_SUBSCRIPTION_RESOURCE_PROFILE:-}" == "all" ]]; then
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-parallel-light-${BASHPID:-$$}" \
            listRegressionSubscriptionLightChildSelectors
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-parallel-heavy-${BASHPID:-$$}" \
            listRegressionSubscriptionHeavyChildSelectors
        return
    fi

    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-parallel-${BASHPID:-$$}" \
        listRegressionSubscriptionChildSelectors
}

runRegressionSubscriptionOutput() {
    local status

    set +e
    runSubscriptionSelectorListRegression \
        subscription-output-parallel \
        listRegressionSubscriptionOutputChildSelectors \
        2 \
        PADM_REGRESSION_SUBSCRIPTION_OUTPUT_PARALLEL_JOBS
    status=$?
    set -e
    if (( status != 0 )); then
        return "${status}"
    fi
    runRegressionStep subscription-remote-sources-no-reverse-decode runRemoteSubscribeSourcesAvoidReverseDecodeRegression
}

registerRegressionFunctionLeaf subscription-output runRegressionSubscriptionOutput
registerRegressionFunctionLeaf subscription-output-profile-and-reality runSubscriptionOutputProfileAndRealityRegression
registerRegressionFunctionLeaf subscription-output-publish-accounts-and-remote-hint runSubscriptionOutputPublishAccountsAndRemoteHintRegression
registerRegressionFunctionLeaf subscription-output-tls-vless-vmess-trojan runSubscriptionOutputTlsVlessVmessTrojanRegression
registerRegressionFunctionLeaf subscription-output-tls-any-hysteria-tuic-naive runSubscriptionOutputTlsAnyHysteriaTuicNaiveRegression
runRegressionSubscriptionSafety() (
    set -euo pipefail
    runSubscribeLocalRollbackRegression
    runSubscriptionGroupsBackupFailureRegression
)

registerRegressionFunctionLeaf subscription-safety runRegressionSubscriptionSafety
registerRegressionAggregateRunner parallel subscription runRegressionSubscriptionSuiteRoot \
    $(listRegressionSubscriptionChildSelectors)
