#!/usr/bin/env bash

REGRESSION_TRANSACTION_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_TRANSACTION_SUITE_DIR}/../subscription_groups_legacy.sh"

listRegressionTransactionChildSelectors() {
    printf '%s\n' \
        transaction-core \
        transaction-subscription \
        transaction-system
}

registerRegressionAggregateRunnerParallel transaction-system runRegressionTransactionSystem \
    $(listRegressionTransactionSystemChildSelectors)

registerRegressionAggregateRunnerParallel transaction-core runRegressionTransactionCore \
    $(listRegressionTransactionCoreChildSelectors)

registerRegressionAggregateRunnerSequential transaction runRegressionTransaction \
    $(listRegressionTransactionChildSelectors)
