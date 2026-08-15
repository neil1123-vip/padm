#!/usr/bin/env bash

listRegressionAllParallelChildSelectors() {
    printf '%s\n' \
        subscription \
        ui \
        transaction-core \
        routing \
        runtime \
        remote-control-smoke \
        remote-control-contract-service-install
}

runRegressionAllSelectorSuiteRoot() (
    local selector=$1
    local childParallelJobs=

    regressionChildParallelJobsForSelector() {
        case "$1" in
        subscription) printf '%s\n' "${PADM_REGRESSION_SUBSCRIPTION_CHILD_PARALLEL_JOBS:-${PADM_REGRESSION_CHILD_PARALLEL_JOBS:-}}" ;;
        transaction-system) printf '%s\n' "${PADM_REGRESSION_TRANSACTION_SYSTEM_CHILD_PARALLEL_JOBS:-${PADM_REGRESSION_CHILD_PARALLEL_JOBS:-}}" ;;
        transaction-core) printf '%s\n' "${PADM_REGRESSION_TRANSACTION_CORE_CHILD_PARALLEL_JOBS:-${PADM_REGRESSION_CHILD_PARALLEL_JOBS:-}}" ;;
        ui) printf '%s\n' "${PADM_REGRESSION_UI_CHILD_PARALLEL_JOBS:-${PADM_REGRESSION_CHILD_PARALLEL_JOBS:-}}" ;;
        routing) printf '%s\n' "${PADM_REGRESSION_ROUTING_CHILD_PARALLEL_JOBS:-${PADM_REGRESSION_LIGHT_CHILD_PARALLEL_JOBS:-${PADM_REGRESSION_CHILD_PARALLEL_JOBS:-}}}" ;;
        runtime) printf '%s\n' "${PADM_REGRESSION_RUNTIME_CHILD_PARALLEL_JOBS:-${PADM_REGRESSION_LIGHT_CHILD_PARALLEL_JOBS:-${PADM_REGRESSION_CHILD_PARALLEL_JOBS:-}}}" ;;
        remote-control-smoke | remote-control-contract-service-install | remote-control-contract-server-response)
            printf '%s\n' "${PADM_REGRESSION_LIGHT_CHILD_PARALLEL_JOBS:-${PADM_REGRESSION_CHILD_PARALLEL_JOBS:-}}"
            ;;
        *) printf '%s\n' "${PADM_REGRESSION_CHILD_PARALLEL_JOBS:-}" ;;
        esac
    }

    childParallelJobs=$(regressionChildParallelJobsForSelector "${selector}")
    export PADM_REGRESSION_SUPPRESS_DONE=1

    # Child suite roots should use their own selector runners instead of
    # inheriting the top-level `all` helper as a nested parallel selector runner.
    unset PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER
    unset PADM_REGRESSION_PARALLEL_SELECTOR_MODE

    if [[ -n "${childParallelJobs}" ]]; then
        export PADM_REGRESSION_PARALLEL_JOBS="${childParallelJobs}"
    fi

    runRegisteredRegressionMain "${selector}"
)

runRegressionAllSuiteRoot() (
    PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_ALL_PARALLEL_JOBS:-5}"
    PADM_REGRESSION_CHILD_PARALLEL_JOBS="${PADM_REGRESSION_ALL_CHILD_PARALLEL_JOBS:-2}"
    PADM_REGRESSION_UI_CHILD_PARALLEL_JOBS="${PADM_REGRESSION_ALL_UI_CHILD_PARALLEL_JOBS:-3}"
    PADM_REGRESSION_UI_RESOURCE_PROFILE="${PADM_REGRESSION_ALL_UI_RESOURCE_PROFILE:-all}"
    PADM_REGRESSION_SUBSCRIPTION_CHILD_PARALLEL_JOBS="${PADM_REGRESSION_ALL_SUBSCRIPTION_CHILD_PARALLEL_JOBS:-2}"
    PADM_REGRESSION_SUBSCRIPTION_RESOURCE_PROFILE="${PADM_REGRESSION_ALL_SUBSCRIPTION_RESOURCE_PROFILE:-all}"
    PADM_REGRESSION_TRANSACTION_SYSTEM_CHILD_PARALLEL_JOBS="${PADM_REGRESSION_ALL_TRANSACTION_SYSTEM_CHILD_PARALLEL_JOBS:-4}"
    PADM_REGRESSION_TRANSACTION_CORE_CHILD_PARALLEL_JOBS="${PADM_REGRESSION_ALL_TRANSACTION_CORE_CHILD_PARALLEL_JOBS:-3}"
    PADM_REGRESSION_TRANSACTION_CORE_RESOURCE_PROFILE="${PADM_REGRESSION_ALL_TRANSACTION_CORE_RESOURCE_PROFILE:-}"
    PADM_REGRESSION_ROUTING_CHILD_PARALLEL_JOBS="${PADM_REGRESSION_ALL_ROUTING_CHILD_PARALLEL_JOBS:-1}"
    PADM_REGRESSION_ROUTING_RESOURCE_PROFILE="${PADM_REGRESSION_ALL_ROUTING_RESOURCE_PROFILE:-}"
    PADM_REGRESSION_RUNTIME_CHILD_PARALLEL_JOBS="${PADM_REGRESSION_ALL_RUNTIME_CHILD_PARALLEL_JOBS:-1}"
    PADM_REGRESSION_RUNTIME_RESOURCE_PROFILE="${PADM_REGRESSION_ALL_RUNTIME_RESOURCE_PROFILE:-}"
    PADM_REGRESSION_LIGHT_CHILD_PARALLEL_JOBS="${PADM_REGRESSION_ALL_LIGHT_CHILD_PARALLEL_JOBS:-1}"

    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelectorSuiteRoot \
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/all-parallel-${BASHPID:-$$}" \
        listRegressionAllParallelChildSelectors
    runRegressionStep transaction-system runRegressionAllSelectorSuiteRoot transaction-system
    runRegressionStep remote-control-contract-server-response runRegressionAllSelectorSuiteRoot remote-control-contract-server-response
)

listRegressionAllChildSelectors() {
    printf '%s\n' \
        routing \
        subscription \
        runtime \
        transaction \
        remote-control \
        ui
}


registerRegressionAggregateRunner sequential all runRegressionAllSuiteRoot \
    $(listRegressionAllChildSelectors)
