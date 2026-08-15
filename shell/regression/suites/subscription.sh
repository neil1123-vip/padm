#!/usr/bin/env bash

listRegressionSubscriptionOutputChildSelectors() {
    printf '%s\n' \
        subscription-output-profile-and-reality \
        subscription-output-publish-accounts-and-remote-hint \
        subscription-output-tls-vless-vmess-trojan \
        subscription-output-tls-any-hysteria-tuic-naive
}

listRegressionSubscriptionTxChildSelectors() {
    printf '%s\n' \
        sing-box-subscribe-write \
        cdn-address-write-transaction \
        subscribe-local-output-transaction \
        subscribe-salt-write-transaction \
        subscribe-server-name \
        subscribe-nginx-config-write \
        subscribe-nginx-service-failure \
        sing-box-port-failure \
        subscribe-user-output-transaction \
        subscribe-local-rollback \
        subscription-groups-backup-failure \
        refresh-local-subscriptions-rollback \
        subscribe-return-failure \
        remove-user-subscription-menu-failure \
        user-subscription-menu-mutation-failure
}

listRegressionSubscriptionLightChildSelectors() {
    printf '%s\n' \
        subscription-output \
        subscription-state
}

listRegressionSubscriptionHeavyChildSelectors() {
    printf '%s\n' subscription-tx
}

listRegressionSubscriptionChildSelectors() {
    printf '%s\n' \
        subscription-output \
        subscription-state \
        subscription-tx
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

runRegressionSubscriptionOutputParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-subscription-output-parallel-composition.log"

    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        if [[ "${selector}" == "subscription-output-profile-and-reality" ]]; then
            runFrameworkWaitForFile "${TMP_DIR}/subscription-output-publish-started"
        elif [[ "${selector}" == "subscription-output-publish-accounts-and-remote-hint" ]]; then
            : >"${TMP_DIR}/subscription-output-publish-started"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    runRemoteSubscribeSourcesAvoidReverseDecodeRegression() {
        printf 'subscription-remote-sources-no-reverse-decode-finish\n' >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector \
        PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain subscription-output

    runFrameworkAssertSelectorListLogged "${callLog}" listRegressionSubscriptionOutputChildSelectors
    awk '
        $0 == "subscription-output-profile-and-reality-start" { firstStart = NR }
        $0 == "subscription-output-publish-accounts-and-remote-hint-start" { secondStart = NR }
        $0 == "subscription-output-profile-and-reality-finish" { firstFinish = NR }
        END { exit !(firstStart && secondStart && firstFinish && secondStart < firstFinish) }
    ' "${callLog}"

    : >"${callLog}"
    rm -f "${TMP_DIR}/subscription-output-publish-started"
    PADM_REGRESSION_SUBSCRIPTION_OUTPUT_PARALLEL_JOBS=1 \
        PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector \
        PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain subscription-output
    awk '
        $0 == "subscription-output-profile-and-reality-finish" { firstFinish = NR }
        $0 == "subscription-output-publish-accounts-and-remote-hint-start" { secondStart = NR }
        $0 == "subscription-output-publish-accounts-and-remote-hint-finish" { secondFinish = NR }
        $0 == "subscription-output-tls-vless-vmess-trojan-start" { thirdStart = NR }
        END { exit !(firstFinish && secondStart && secondFinish && thirdStart && firstFinish < secondStart && secondFinish < thirdStart) }
    ' "${callLog}"
)

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

runRegressionSubscriptionTxParallelCompositionRegression() {
    runFrameworkParallelCompositionContract subscription-tx sing-box-subscribe-write \
        subscribe-user-output-transaction listRegressionSubscriptionTxChildSelectors
}

runRegressionSubscriptionParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-subscription-parallel-composition.log"

    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        if [[ "${selector}" == "subscription-output" ]]; then
            runFrameworkWaitForFile "${TMP_DIR}/subscription-state-started"
        elif [[ "${selector}" == "subscription-state" ]]; then
            : >"${TMP_DIR}/subscription-state-started"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionSubscriptionSuiteRoot

    runFrameworkAssertSelectorListLogged "${callLog}" listRegressionSubscriptionChildSelectors
    awk '
        $0 == "subscription-output-start" { outputStart = NR }
        $0 == "subscription-state-start" { stateStart = NR }
        $0 == "subscription-output-finish" { outputFinish = NR }
        END { exit !(outputStart && stateStart && outputFinish && stateStart < outputFinish) }
    ' "${callLog}"

    : >"${callLog}"
    rm -f "${TMP_DIR}/subscription-state-started"
    PADM_REGRESSION_SUBSCRIPTION_RESOURCE_PROFILE=all PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionSubscriptionSuiteRoot

    runFrameworkAssertSelectorListLogged "${callLog}" listRegressionSubscriptionChildSelectors
    awk '
        $0 == "subscription-output-start" { outputStart = NR }
        $0 == "subscription-state-start" { stateStart = NR }
        $0 == "subscription-output-finish" { outputFinish = NR }
        $0 == "subscription-state-finish" { stateFinish = NR }
        $0 == "subscription-tx-start" { writeStart = NR }
        END {
            exit !(outputStart && stateStart && outputFinish && stateFinish && writeStart &&
                stateStart < outputFinish &&
                outputFinish < writeStart && stateFinish < writeStart)
        }
    ' "${callLog}"
)

registerRegressionFunctionLeaf subscription-output runRegressionSubscriptionOutput
registerRegressionFunctionLeaf subscription-output-profile-and-reality runSubscriptionOutputProfileAndRealityRegression
registerRegressionFunctionLeaf subscription-output-publish-accounts-and-remote-hint runSubscriptionOutputPublishAccountsAndRemoteHintRegression
registerRegressionFunctionLeaf subscription-output-tls-vless-vmess-trojan runSubscriptionOutputTlsVlessVmessTrojanRegression
registerRegressionFunctionLeaf subscription-output-tls-any-hysteria-tuic-naive runSubscriptionOutputTlsAnyHysteriaTuicNaiveRegression
registerRegressionFunctionLeaf sing-box-subscribe-write runSingBoxSubscribeWriteRegression
registerRegressionFunctionLeaf subscribe-local-output-transaction runSubscribeLocalOutputTransactionRegression
registerRegressionFunctionLeaf sing-box-port-failure runSingBoxPortFailureRegression
registerRegressionFunctionLeaf subscribe-local-rollback runSubscribeLocalRollbackRegression
registerRegressionFunctionLeaf subscription-groups-backup-failure runSubscriptionGroupsBackupFailureRegression
registerRegressionFunctionLeaf refresh-local-subscriptions-rollback runRefreshLocalSubscriptionsRollbackRegression
registerRegressionFunctionLeaf subscribe-return-failure runSubscribeReturnFailureRegression
registerRegressionFunctionLeaf regression-subscription-parallel-composition runRegressionSubscriptionParallelCompositionRegression
registerRegressionFunctionLeaf regression-subscription-output-parallel-composition runRegressionSubscriptionOutputParallelCompositionRegression
registerRegressionFunctionLeaf regression-subscription-tx-parallel-composition runRegressionSubscriptionTxParallelCompositionRegression

registerRegressionParallelSelectorList subscription-tx runSubscriptionSelectorListRegression \
    subscription-tx-parallel listRegressionSubscriptionTxChildSelectors

registerRegressionAggregateRunner parallel subscription runRegressionSubscriptionSuiteRoot \
    $(listRegressionSubscriptionChildSelectors)
