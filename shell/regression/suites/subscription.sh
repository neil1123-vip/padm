#!/usr/bin/env bash

REGRESSION_SUBSCRIPTION_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_SUBSCRIPTION_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_SUBSCRIPTION_SUITE_DIR}/../subscription_groups_legacy.sh"

runRegressionSubscriptionLegacyLeafWithCompat() (
    # Re-source legacy subscription fixtures in an isolated subshell so later
    # suite loads cannot leave source-time TMP_DIR-derived paths stale.
    PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_SUBSCRIPTION_SUITE_DIR}/../subscription_groups_legacy.sh"
    "$@"
)

runRegressionSubscriptionOutputCompatRegression() { runRegressionSubscriptionLegacyLeafWithCompat runRegressionSubscriptionOutput; }
runRemoteSubscribeFetchUniqueCompatRegression() { runRegressionSubscriptionLegacyLeafWithCompat runRemoteSubscribeFetchUniqueRegression; }
runRemoteSubscribeFetchRollbackCompatRegression() { runRegressionSubscriptionLegacyLeafWithCompat runRemoteSubscribeFetchRollbackRegression; }
runRemoteSubscribeFetchMergeCompatRegression() { runRegressionSubscriptionLegacyLeafWithCompat runRemoteSubscribeFetchMergeRegression; }
runRemoteSubscribeFetchControlledCompatRegression() { runRegressionSubscriptionLegacyLeafWithCompat runRemoteSubscribeFetchControlledRegression; }
runRemoteSubscribeFetchAppendFailureCompatRegression() { runRegressionSubscriptionLegacyLeafWithCompat runRemoteSubscribeFetchAppendFailureRegression; }
runRemoteSubscribeFetchCommitFailureCompatRegression() { runRegressionSubscriptionLegacyLeafWithCompat runRemoteSubscribeFetchCommitFailureRegression; }
runRemoteSubscribeFetchIdempotentCompatRegression() { runRegressionSubscriptionLegacyLeafWithCompat runRemoteSubscribeFetchIdempotentRegression; }
runSingBoxSubscribeWriteCompatRegression() { runRegressionSubscriptionLegacyLeafWithCompat runSingBoxSubscribeWriteRegression; }

runRegressionSubscriptionRemoteSuiteRoot() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    mapfile -t selectors < <(listRegressionSubscriptionRemoteChildSelectors)
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_SUBSCRIPTION_REMOTE_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}" \
        PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/subscription-remote-parallel-${BASHPID:-$$}" \
        "${selectorPairs[@]}"
}

runRegressionSubscriptionTxSuiteRoot() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    mapfile -t selectors < <(listRegressionSubscriptionTxChildSelectors)
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/subscription-tx-parallel-${BASHPID:-$$}" \
        "${selectorPairs[@]}"
}

runRegressionSubscriptionSuiteRoot() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    if [[ "${PADM_REGRESSION_SUBSCRIPTION_RESOURCE_PROFILE:-}" == "all" ]]; then
        mapfile -t selectors < <(listRegressionSubscriptionLightChildSelectors)
        selectorPairs=()
        for selector in "${selectors[@]}"; do
            selectorPairs+=("${selector}" "${selector}")
        done
        PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
            runFrameworkParallelRegressionSelectors "${TMP_DIR}/subscription-parallel-light-${BASHPID:-$$}" \
            "${selectorPairs[@]}"
        (
            export PADM_REGRESSION_SUBSCRIPTION_REMOTE_PARALLEL_JOBS="${PADM_REGRESSION_SUBSCRIPTION_REMOTE_PARALLEL_JOBS:-2}"
            mapfile -t selectors < <(listRegressionSubscriptionHeavyChildSelectors)
            selectorPairs=()
            for selector in "${selectors[@]}"; do
                selectorPairs+=("${selector}" "${selector}")
            done
            PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
                runFrameworkParallelRegressionSelectors "${TMP_DIR}/subscription-parallel-heavy-${BASHPID:-$$}" \
                "${selectorPairs[@]}"
        )
        return
    fi

    mapfile -t selectors < <(listRegressionSubscriptionChildSelectors)
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/subscription-parallel-${BASHPID:-$$}" \
        "${selectorPairs[@]}"
}

runRegressionSubscriptionRemote() {
    runRegressionSubscriptionRemoteSuiteRoot
}

runRegressionSubscriptionTx() {
    runRegressionSubscriptionTxSuiteRoot
}

runRegressionSubscription() {
    runRegressionSubscriptionSuiteRoot
}

runRegressionSubscriptionOutput() {
    runRegressionStep subscription-output runSubscriptionOutputRegression &&
        runRegressionStep subscription-remote-sources-no-reverse-decode runRemoteSubscribeSourcesAvoidReverseDecodeRegression
}

runRegressionSubscriptionRemoteParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-subscription-remote-parallel-composition.log"

    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        if [[ "${selector}" == "subscription-remote-unique" ]]; then
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${TMP_DIR}/subscription-remote-merge-started" ]] && break
                sleep 0.05
            done
        elif [[ "${selector}" == "subscription-remote-merge" ]]; then
            : >"${TMP_DIR}/subscription-remote-merge-started"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionSubscriptionRemoteSuiteRoot

    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done < <(listRegressionSubscriptionRemoteChildSelectors)
    awk '
        $0 == "subscription-remote-unique-start" { uniqueStart = NR }
        $0 == "subscription-remote-merge-start" { mergeStart = NR }
        $0 == "subscription-remote-unique-finish" { uniqueFinish = NR }
        END { exit !(uniqueStart && mergeStart && uniqueFinish && mergeStart < uniqueFinish) }
    ' "${callLog}"
    ! grep -qx 'subscription-remote-start' "${callLog}"
    ! grep -qx 'subscription-remote-finish' "${callLog}"

    : >"${callLog}"
    rm -f "${TMP_DIR}/subscription-remote-merge-started"
    PADM_REGRESSION_SUBSCRIPTION_REMOTE_PARALLEL_JOBS=1 PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionSubscriptionRemoteSuiteRoot
    awk '
        $0 == "subscription-remote-unique-finish" { firstFinish = NR }
        $0 == "subscription-remote-rollback-start" { secondStart = NR }
        $0 == "subscription-remote-rollback-finish" { secondFinish = NR }
        $0 == "subscription-remote-merge-start" { thirdStart = NR }
        END { exit !(firstFinish && secondStart && secondFinish && thirdStart && firstFinish < secondStart && secondFinish < thirdStart) }
    ' "${callLog}"
)

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

    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionSubscriptionTxSuiteRoot

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
        $0 == "subscription-remote-start" { remoteStart = NR }
        END {
            exit !(outputStart && stateStart && outputFinish && stateFinish && writeStart && remoteStart &&
                stateStart < outputFinish &&
                outputFinish < writeStart && stateFinish < writeStart &&
                outputFinish < remoteStart && stateFinish < remoteStart)
        }
    ' "${callLog}"
)

registerRegressionFunctionLeaf subscription-output runRegressionSubscriptionOutputCompatRegression
registerRegressionFunctionLeaf subscription-remote-unique runRemoteSubscribeFetchUniqueCompatRegression
registerRegressionFunctionLeaf subscription-remote-rollback runRemoteSubscribeFetchRollbackCompatRegression
registerRegressionFunctionLeaf subscription-remote-merge runRemoteSubscribeFetchMergeCompatRegression
registerRegressionFunctionLeaf subscription-remote-controlled runRemoteSubscribeFetchControlledCompatRegression
registerRegressionFunctionLeaf subscription-remote-append-failure runRemoteSubscribeFetchAppendFailureCompatRegression
registerRegressionFunctionLeaf subscription-remote-commit-failure runRemoteSubscribeFetchCommitFailureCompatRegression
registerRegressionFunctionLeaf subscription-remote-idempotent runRemoteSubscribeFetchIdempotentCompatRegression
registerRegressionFunctionLeaf sing-box-subscribe-write runSingBoxSubscribeWriteCompatRegression
registerRegressionFunctionLeaf cdn-address-write-transaction runCdnAddressTransactionRegression
registerRegressionFunctionLeaf subscribe-local-output-transaction runSubscribeLocalOutputTransactionRegression
registerRegressionFunctionLeaf subscribe-salt-write-transaction runSubscribeSaltWriteTransactionRegression
registerRegressionFunctionLeaf subscribe-server-name runSubscribeServerNameRegression
registerRegressionFunctionLeaf subscribe-nginx-config-write runSubscribeNginxConfigWriteRegression
registerRegressionFunctionLeaf subscribe-nginx-service-failure runSubscribeNginxServiceFailureRegression
registerRegressionFunctionLeaf sing-box-port-failure runSingBoxPortFailureRegression
registerRegressionFunctionLeaf subscribe-user-output-transaction runSubscribeUserOutputTransactionRegression
registerRegressionFunctionLeaf subscribe-local-rollback runSubscribeLocalRollbackRegression
registerRegressionFunctionLeaf subscription-groups-migration-backup runSubscriptionGroupsMigrationBackupRegression
registerRegressionFunctionLeaf subscription-groups-backup-failure runSubscriptionGroupsBackupFailureRegression
registerRegressionFunctionLeaf refresh-local-subscriptions-rollback runRefreshLocalSubscriptionsRollbackRegression
registerRegressionFunctionLeaf subscribe-return-failure runSubscribeReturnFailureRegression
registerRegressionFunctionLeaf remove-user-subscription-menu-failure runRemoveUserSubscriptionMenuFailureRegression
registerRegressionFunctionLeaf user-subscription-menu-mutation-failure runUserSubscriptionMenuMutationFailureRegression
registerRegressionFunctionLeaf regression-subscription-parallel-composition runRegressionSubscriptionParallelCompositionRegression
registerRegressionFunctionLeaf regression-subscription-tx-parallel-composition runRegressionSubscriptionTxParallelCompositionRegression
registerRegressionFunctionLeaf regression-subscription-remote-parallel-composition runRegressionSubscriptionRemoteParallelCompositionRegression
registerRegressionFunctionLeaf regression-subscription-legacy-tmpdir-isolation runRegressionSubscriptionLegacyTmpDirIsolationRegression

registerRegressionAggregateRunnerParallel subscription-remote runRegressionSubscriptionRemoteSuiteRoot \
    $(listRegressionSubscriptionRemoteChildSelectors)

registerRegressionAggregateRunnerParallel subscription-tx runRegressionSubscriptionTxSuiteRoot \
    $(listRegressionSubscriptionTxChildSelectors)

registerRegressionAggregateRunnerParallel subscription runRegressionSubscriptionSuiteRoot \
    $(listRegressionSubscriptionChildSelectors)
