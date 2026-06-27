#!/usr/bin/env bash

REGRESSION_TRANSACTION_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_TRANSACTION_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_TRANSACTION_SUITE_DIR}/../subscription_groups_legacy.sh"

listRegressionTransactionChildSelectors() {
    printf '%s\n' \
        transaction-core \
        transaction-subscription \
        transaction-system
}

runRegressionTransactionSystemSuiteRoot() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    mapfile -t selectors < <(listRegressionTransactionSystemChildSelectors)
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_TRANSACTION_SYSTEM_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}" \
        PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/transaction-system-parallel-${BASHPID:-$$}" \
        "${selectorPairs[@]}"
}

runRegressionTransactionSuiteRoot() {
    runRegressionTransactionCore &&
        runRegressionTransactionSubscription &&
        runRegressionTransactionSystemSuiteRoot
}

registerRegressionAggregateRunnerParallel transaction-system runRegressionTransactionSystemSuiteRoot \
    $(listRegressionTransactionSystemChildSelectors)

registerRegressionAggregateRunnerParallel transaction-core runRegressionTransactionCore \
    $(listRegressionTransactionCoreChildSelectors)

registerRegressionAggregateRunnerSequential transaction runRegressionTransactionSuiteRoot \
    $(listRegressionTransactionChildSelectors)
