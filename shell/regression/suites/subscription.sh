#!/usr/bin/env bash

REGRESSION_SUBSCRIPTION_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_SUBSCRIPTION_SUITE_DIR}/../subscription_groups_legacy.sh"

runRegressionSubscriptionRemoteSuiteRoot() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    mapfile -t selectors < <(listRegressionSubscriptionRemoteChildSelectors)
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_SUBSCRIPTION_REMOTE_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}" \
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
            export PADM_REGRESSION_SUBSCRIPTION_REMOTE_PARALLEL_JOBS="${PADM_REGRESSION_SUBSCRIPTION_REMOTE_PARALLEL_JOBS:-2}"
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
registerRegressionFunctionLeaf subscription-remote-unique runRemoteSubscribeFetchUniqueRegression
registerRegressionFunctionLeaf subscription-remote-rollback runRemoteSubscribeFetchRollbackRegression
registerRegressionFunctionLeaf subscription-remote-merge runRemoteSubscribeFetchMergeRegression
registerRegressionFunctionLeaf subscription-remote-controlled runRemoteSubscribeFetchControlledRegression
registerRegressionFunctionLeaf subscription-remote-append-failure runRemoteSubscribeFetchAppendFailureRegression
registerRegressionFunctionLeaf subscription-remote-commit-failure runRemoteSubscribeFetchCommitFailureRegression
registerRegressionFunctionLeaf subscription-remote-idempotent runRemoteSubscribeFetchIdempotentRegression
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
registerRegressionFunctionLeaf regression-subscription-remote-parallel-composition runRegressionSubscriptionRemoteParallelCompositionRegression

registerRegressionAggregateRunnerParallel subscription-remote runRegressionSubscriptionRemoteSuiteRoot \
    $(listRegressionSubscriptionRemoteChildSelectors)

registerRegressionAggregateRunnerParallel subscription-tx runRegressionSubscriptionWriteTransactionSuiteRoot \
    $(listRegressionSubscriptionWriteTransactionChildSelectors)

registerRegressionAggregateRunnerParallel subscription runRegressionSubscriptionSuiteRoot \
    $(listRegressionSubscriptionChildSelectors)
