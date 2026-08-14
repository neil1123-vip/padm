#!/usr/bin/env bash

REGRESSION_SUBSCRIPTION_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_SUBSCRIPTION_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_SUBSCRIPTION_SUITE_DIR}/../subscription_groups_legacy.sh" --reuse

runRegressionSubscriptionLegacyLeafWithCompat() (
    # Re-source legacy subscription fixtures in an isolated subshell so later
    # suite loads cannot leave source-time TMP_DIR-derived paths stale.
    PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_SUBSCRIPTION_SUITE_DIR}/../subscription_groups_legacy.sh"
    "$@"
)

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
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${TMP_DIR}/subscription-output-publish-started" ]] && break
                sleep 0.05
            done
        elif [[ "${selector}" == "subscription-output-publish-accounts-and-remote-hint" ]]; then
            : >"${TMP_DIR}/subscription-output-publish-started"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    runRegressionSubscriptionLegacyLeafWithCompat() {
        "$@"
    }
    runRemoteSubscribeSourcesAvoidReverseDecodeRegression() {
        printf 'subscription-remote-sources-no-reverse-decode-finish\n' >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector \
        PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain subscription-output

    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done < <(listRegressionSubscriptionOutputChildSelectors)
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

runRegressionSubscriptionTxParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-subscription-tx-parallel-composition.log"

    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        if [[ "${selector}" == "sing-box-subscribe-write" ]]; then
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${TMP_DIR}/subscribe-user-output-started" ]] && break
                sleep 0.05
            done
        elif [[ "${selector}" == "subscribe-user-output-transaction" ]]; then
            : >"${TMP_DIR}/subscribe-user-output-started"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector \
        PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain subscription-tx

    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done < <(listRegressionSubscriptionTxChildSelectors)
    awk '
        $0 == "sing-box-subscribe-write-start" { singboxStart = NR }
        $0 == "subscribe-user-output-transaction-start" { userOutputStart = NR }
        $0 == "sing-box-subscribe-write-finish" { singboxFinish = NR }
        END { exit !(singboxStart && userOutputStart && singboxFinish && userOutputStart < singboxFinish) }
    ' "${callLog}"
)

runRegressionSubscriptionLegacyTmpDirIsolationRegression() (
    set -euo pipefail
    local originalTmpDir="${TMP_DIR}"

    # Simulate later suite loads re-sourcing bootstrap and drifting TMP_DIR.
    source "${REGRESSION_SUBSCRIPTION_SUITE_DIR}/../bootstrap.sh"
    [[ "${TMP_DIR}" != "${originalTmpDir}" ]]

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain sing-box-subscribe-write
)

runRegressionSubscriptionParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-subscription-parallel-composition.log"

    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        if [[ "${selector}" == "subscription-output" ]]; then
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${TMP_DIR}/subscription-state-started" ]] && break
                sleep 0.05
            done
        elif [[ "${selector}" == "subscription-state" ]]; then
            : >"${TMP_DIR}/subscription-state-started"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionSubscriptionSuiteRoot

    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done < <(listRegressionSubscriptionChildSelectors)
    awk '
        $0 == "subscription-output-start" { outputStart = NR }
        $0 == "subscription-state-start" { stateStart = NR }
        $0 == "subscription-output-finish" { outputFinish = NR }
        END { exit !(outputStart && stateStart && outputFinish && stateStart < outputFinish) }
    ' "${callLog}"

    : >"${callLog}"
    rm -f "${TMP_DIR}/subscription-state-started"
    PADM_REGRESSION_SUBSCRIPTION_RESOURCE_PROFILE=all PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionSubscriptionSuiteRoot

    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done < <(listRegressionSubscriptionChildSelectors)
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

registerRegressionFunctionLeaf subscription-output runRegressionSubscriptionLegacyLeafWithCompat runRegressionSubscriptionOutput
registerRegressionFunctionLeaf subscription-output-profile-and-reality runRegressionSubscriptionLegacyLeafWithCompat runSubscriptionOutputProfileAndRealityRegression
registerRegressionFunctionLeaf subscription-output-publish-accounts-and-remote-hint runRegressionSubscriptionLegacyLeafWithCompat runSubscriptionOutputPublishAccountsAndRemoteHintRegression
registerRegressionFunctionLeaf subscription-output-tls-vless-vmess-trojan runRegressionSubscriptionLegacyLeafWithCompat runSubscriptionOutputTlsVlessVmessTrojanRegression
registerRegressionFunctionLeaf subscription-output-tls-any-hysteria-tuic-naive runRegressionSubscriptionLegacyLeafWithCompat runSubscriptionOutputTlsAnyHysteriaTuicNaiveRegression
registerRegressionFunctionLeaf sing-box-subscribe-write runRegressionSubscriptionLegacyLeafWithCompat runSingBoxSubscribeWriteRegression
registerRegressionFunctionLeaf subscribe-local-output-transaction runSubscribeLocalOutputTransactionRegression
registerRegressionFunctionLeaf sing-box-port-failure runSingBoxPortFailureRegression
registerRegressionFunctionLeaf subscribe-local-rollback runSubscribeLocalRollbackRegression
registerRegressionFunctionLeaf subscription-groups-backup-failure runSubscriptionGroupsBackupFailureRegression
registerRegressionFunctionLeaf refresh-local-subscriptions-rollback runRefreshLocalSubscriptionsRollbackRegression
registerRegressionFunctionLeaf subscribe-return-failure runSubscribeReturnFailureRegression
registerRegressionFunctionLeaf regression-subscription-parallel-composition runRegressionSubscriptionParallelCompositionRegression
registerRegressionFunctionLeaf regression-subscription-output-parallel-composition runRegressionSubscriptionOutputParallelCompositionRegression
registerRegressionFunctionLeaf regression-subscription-tx-parallel-composition runRegressionSubscriptionTxParallelCompositionRegression
registerRegressionFunctionLeaf regression-subscription-legacy-tmpdir-isolation runRegressionSubscriptionLegacyTmpDirIsolationRegression

registerRegressionAggregateRunnerWithArgs parallel \
    subscription-tx \
    runSubscriptionSelectorListRegression \
    subscription-tx-parallel \
    listRegressionSubscriptionTxChildSelectors \
    -- \
    $(listRegressionSubscriptionTxChildSelectors)

registerRegressionAggregateRunner parallel subscription runRegressionSubscriptionSuiteRoot \
    $(listRegressionSubscriptionChildSelectors)
