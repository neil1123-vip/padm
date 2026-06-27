#!/usr/bin/env bash

REGRESSION_SUBSCRIPTION_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_SUBSCRIPTION_SUITE_DIR}/../subscription_groups_legacy.sh"

runRegressionSubscriptionRemoteFetchSuiteRoot() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    mapfile -t selectors < <(listRegressionSubscriptionRemoteFetchChildSelectors)
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_SUBSCRIPTION_REMOTE_FETCH_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}" \
        runParallelRegressionSelectors "${TMP_DIR}/subscription-remote-parallel-${BASHPID:-$$}" \
        "${selectorPairs[@]}"
}

runRegressionSubscriptionWriteTransactionSuiteRoot() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    mapfile -t selectors < <(listRegressionSubscriptionWriteTransactionChildSelectors)
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    runParallelRegressionSelectors "${TMP_DIR}/subscription-tx-parallel-${BASHPID:-$$}" \
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
        runParallelRegressionSelectors "${TMP_DIR}/subscription-parallel-light-${BASHPID:-$$}" \
            "${selectorPairs[@]}"
        (
            export PADM_REGRESSION_SUBSCRIPTION_REMOTE_FETCH_PARALLEL_JOBS="${PADM_REGRESSION_SUBSCRIPTION_REMOTE_FETCH_PARALLEL_JOBS:-2}"
            mapfile -t selectors < <(listRegressionSubscriptionHeavyChildSelectors)
            selectorPairs=()
            for selector in "${selectors[@]}"; do
                selectorPairs+=("${selector}" "${selector}")
            done
            runParallelRegressionSelectors "${TMP_DIR}/subscription-parallel-heavy-${BASHPID:-$$}" \
                "${selectorPairs[@]}"
        )
        return
    fi

    mapfile -t selectors < <(listRegressionSubscriptionChildSelectors)
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    runParallelRegressionSelectors "${TMP_DIR}/subscription-parallel-${BASHPID:-$$}" \
        "${selectorPairs[@]}"
}

registerRegressionFunctionLeaf subscription-output runRegressionSubscriptionOutput
registerRegressionFunctionLeaf subscription-remote-fetch-unique runRemoteSubscribeFetchUniqueRegression
registerRegressionFunctionLeaf subscription-remote-fetch-rollback runRemoteSubscribeFetchRollbackRegression
registerRegressionFunctionLeaf subscription-remote-fetch-merge runRemoteSubscribeFetchMergeRegression
registerRegressionFunctionLeaf subscription-remote-fetch-controlled runRemoteSubscribeFetchControlledRegression
registerRegressionFunctionLeaf subscription-remote-fetch-append-failure runRemoteSubscribeFetchAppendFailureRegression
registerRegressionFunctionLeaf subscription-remote-fetch-commit-failure runRemoteSubscribeFetchCommitFailureRegression
registerRegressionFunctionLeaf subscription-remote-fetch-idempotent runRemoteSubscribeFetchIdempotentRegression
registerRegressionFunctionLeaf sing-box-subscribe-write runSingBoxSubscribeWriteRegression
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
registerRegressionFunctionLeaf regression-subscription-write-transaction-parallel-composition runRegressionSubscriptionWriteTransactionParallelCompositionRegression
registerRegressionFunctionLeaf regression-subscription-remote-fetch-parallel-composition runRegressionSubscriptionRemoteFetchParallelCompositionRegression

registerRegressionAggregateRunnerParallel subscription-remote runRegressionSubscriptionRemoteFetchSuiteRoot \
    $(listRegressionSubscriptionRemoteFetchChildSelectors)

registerRegressionAggregateRunnerParallel subscription-tx runRegressionSubscriptionWriteTransactionSuiteRoot \
    $(listRegressionSubscriptionWriteTransactionChildSelectors)

registerRegressionAggregateRunnerParallel subscription runRegressionSubscriptionSuiteRoot \
    $(listRegressionSubscriptionChildSelectors)
