#!/usr/bin/env bash

REGRESSION_ALL_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_ALL_SUITE_DIR}/../framework/runtime.sh"

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

runRegressionAllSelector() {
    runRegressionAllSelectorSuiteRoot "$@"
}

runRegressionAll() {
    runRegressionAllSuiteRoot
}

runRegressionAllCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-all-composition.log"
    local selector

    : >"${callLog}"

    runRegressionSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        if [[ "${selector}" == "routing" ]]; then
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${TMP_DIR}/subscription-started" ]] && break
                sleep 0.05
            done
        elif [[ "${selector}" == "subscription" ]]; then
            : >"${TMP_DIR}/subscription-started"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    runRegressionRouting() { runRegressionSelector routing; }
    runRegressionSubscription() { runRegressionSelector subscription; }
    runRegressionRuntime() { runRegressionSelector runtime; }
    runRegressionTransaction() { runRegressionSelector transaction; }
    runRegressionTransactionCore() { runRegressionSelector transaction-core; }
    runRegressionTransactionSystem() { runRegressionSelector transaction-system; }
    runRegressionRemoteControlSmoke() { runRegressionSelector remote-control-smoke; }
    runRegressionRemoteControlContractServiceInstall() { runRegressionSelector remote-control-contract-service-install; }
    runRegressionRemoteControlContractServerResponse() { runRegressionSelector remote-control-contract-server-response; }
    runRegressionUi() { runRegressionSelector ui; }
    runRegressionAllSelector() {
        case "$1" in
        routing) runRegressionRouting ;;
        subscription) runRegressionSubscription ;;
        runtime) runRegressionRuntime ;;
        transaction-core) runRegressionTransactionCore ;;
        transaction-system) runRegressionTransactionSystem ;;
        remote-control-smoke) runRegressionRemoteControlSmoke ;;
        remote-control-contract-service-install) runRegressionRemoteControlContractServiceInstall ;;
        remote-control-contract-server-response) runRegressionRemoteControlContractServerResponse ;;
        ui) runRegressionUi ;;
        transaction) runRegressionTransaction ;;
        *) return 2 ;;
        esac
    }
    runRegressionAllSelectorSuiteRoot() {
        runRegressionAllSelector "$@"
    }

    runRegressionAll

    for selector in routing subscription runtime transaction-core transaction-system remote-control-smoke remote-control-contract-service-install remote-control-contract-server-response ui; do
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done
    awk '
        $0 == "routing-start" { routingStart = NR }
        $0 == "subscription-start" { subscriptionStart = NR }
        $0 == "routing-finish" { routingFinish = NR }
        END { exit !(routingStart && subscriptionStart && routingFinish && subscriptionStart < routingFinish) }
    ' "${callLog}"
    awk '
        $0 == "routing-finish" { routingFinish = NR }
        $0 == "subscription-finish" { subscriptionFinish = NR }
        $0 == "runtime-finish" { runtimeFinish = NR }
        $0 == "transaction-core-finish" { transactionCoreFinish = NR }
        $0 == "transaction-system-finish" { transactionSystemFinish = NR }
        $0 == "remote-control-smoke-finish" { remoteSmokeFinish = NR }
        $0 == "remote-control-contract-service-install-finish" { remoteServiceFinish = NR }
        $0 == "ui-finish" { uiFinish = NR }
        $0 == "remote-control-contract-server-response-start" { serverResponseStart = NR }
        END {
            exit !(routingFinish && subscriptionFinish && runtimeFinish && transactionCoreFinish && transactionSystemFinish &&
                remoteSmokeFinish && remoteServiceFinish && uiFinish && serverResponseStart &&
                routingFinish < serverResponseStart && subscriptionFinish < serverResponseStart &&
                runtimeFinish < serverResponseStart && transactionCoreFinish < serverResponseStart &&
                transactionSystemFinish < serverResponseStart && remoteSmokeFinish < serverResponseStart &&
                remoteServiceFinish < serverResponseStart && uiFinish < serverResponseStart)
        }
    ' "${callLog}"
    ! grep -qx 'transaction-start' "${callLog}"
    ! grep -qx 'transaction-finish' "${callLog}"
    ! grep -qx 'remote-control-start' "${callLog}"
    ! grep -qx 'remote-control-finish' "${callLog}"
)

runRegressionAllChildParallelBudgetCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-all-child-parallel-budget-composition.log"

    : >"${callLog}"

    runRegisteredRegressionMain() {
        printf 'selector=%s jobs=%s ui_profile=%s subscription_profile=%s routing_profile=%s runtime_profile=%s transaction_core_profile=%s suppress=%s\n' "$1" "${PADM_REGRESSION_PARALLEL_JOBS:-}" "${PADM_REGRESSION_UI_RESOURCE_PROFILE:-}" "${PADM_REGRESSION_SUBSCRIPTION_RESOURCE_PROFILE:-}" "${PADM_REGRESSION_ROUTING_RESOURCE_PROFILE:-}" "${PADM_REGRESSION_RUNTIME_RESOURCE_PROFILE:-}" "${PADM_REGRESSION_TRANSACTION_CORE_RESOURCE_PROFILE:-}" "${PADM_REGRESSION_SUPPRESS_DONE:-}" >>"${callLog}"
    }

    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 runRegressionAllSelector ui
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 PADM_REGRESSION_UI_CHILD_PARALLEL_JOBS=2 runRegressionAllSelector ui
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 PADM_REGRESSION_UI_RESOURCE_PROFILE=all runRegressionAllSelector ui
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 PADM_REGRESSION_SUBSCRIPTION_RESOURCE_PROFILE=all runRegressionAllSelector subscription
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 runRegressionAllSelector transaction-core
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 PADM_REGRESSION_TRANSACTION_CORE_RESOURCE_PROFILE=all runRegressionAllSelector transaction-core
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 runRegressionAllSelector transaction-system
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 PADM_REGRESSION_TRANSACTION_SYSTEM_CHILD_PARALLEL_JOBS=2 runRegressionAllSelector transaction-system
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 runRegressionAllSelector routing
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 PADM_REGRESSION_ROUTING_CHILD_PARALLEL_JOBS=2 runRegressionAllSelector routing
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 PADM_REGRESSION_ROUTING_RESOURCE_PROFILE=all runRegressionAllSelector routing
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 runRegressionAllSelector runtime
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 PADM_REGRESSION_RUNTIME_CHILD_PARALLEL_JOBS=2 runRegressionAllSelector runtime
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 PADM_REGRESSION_RUNTIME_RESOURCE_PROFILE=all runRegressionAllSelector runtime
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 runRegressionAllSelector remote-control-smoke

    grep -qx 'selector=ui jobs=4 ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'selector=ui jobs=2 ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'selector=ui jobs=4 ui_profile=all subscription_profile= routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'selector=subscription jobs=4 ui_profile= subscription_profile=all routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'selector=transaction-core jobs=4 ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'selector=transaction-core jobs=4 ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile=all suppress=1' "${callLog}"
    grep -qx 'selector=transaction-system jobs=4 ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'selector=transaction-system jobs=2 ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'selector=routing jobs=4 ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'selector=routing jobs=2 ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'selector=routing jobs=4 ui_profile= subscription_profile= routing_profile=all runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'selector=runtime jobs=4 ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'selector=runtime jobs=2 ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'selector=runtime jobs=4 ui_profile= subscription_profile= routing_profile= runtime_profile=all transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'selector=remote-control-smoke jobs=4 ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
)

runRegressionAllResourceLayerCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-all-resource-layer-composition.log"
    local firstWave="${TMP_DIR}/regression-all-resource-layer-first-wave.log"
    local expectedFirstWave="${TMP_DIR}/regression-all-resource-layer-expected-first-wave.log"

    : >"${callLog}"

    runRegisteredRegressionMain() {
        local selector=$1
        printf '%s-start jobs=%s ui_profile=%s subscription_profile=%s routing_profile=%s runtime_profile=%s transaction_core_profile=%s suppress=%s\n' "${selector}" "${PADM_REGRESSION_PARALLEL_JOBS:-}" "${PADM_REGRESSION_UI_RESOURCE_PROFILE:-}" "${PADM_REGRESSION_SUBSCRIPTION_RESOURCE_PROFILE:-}" "${PADM_REGRESSION_ROUTING_RESOURCE_PROFILE:-}" "${PADM_REGRESSION_RUNTIME_RESOURCE_PROFILE:-}" "${PADM_REGRESSION_TRANSACTION_CORE_RESOURCE_PROFILE:-}" "${PADM_REGRESSION_SUPPRESS_DONE:-}" >>"${callLog}"
        case "${selector}" in
        subscription | ui | transaction-core | routing | runtime)
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                grep -q '^subscription-start ' "${callLog}" &&
                    grep -q '^ui-start ' "${callLog}" &&
                    grep -q '^transaction-core-start ' "${callLog}" &&
                    grep -q '^routing-start ' "${callLog}" &&
                    grep -q '^runtime-start ' "${callLog}" && break
                sleep 0.05
            done
            ;;
        esac
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    runRegressionAll

    awk '
        /-start / {
            selector = $1
            sub(/-start$/, "", selector)
            print selector
            if (++count == 5) { exit }
        }
    ' "${callLog}" | sort >"${firstWave}"
    printf '%s\n' routing runtime subscription transaction-core ui | sort >"${expectedFirstWave}"
    cmp -s "${expectedFirstWave}" "${firstWave}"
    awk '
        /^subscription-start / { subscriptionStart = NR }
        /^ui-start / { uiStart = NR }
        /^transaction-core-start / { transactionCoreStart = NR }
        /^routing-start / { routingStart = NR }
        /^runtime-start / { runtimeStart = NR }
        $0 == "subscription-finish" || $0 == "ui-finish" || $0 == "transaction-core-finish" ||
            $0 == "routing-finish" || $0 == "runtime-finish" {
            if (!firstHeavyFinish) { firstHeavyFinish = NR }
        }
        END {
            exit !(subscriptionStart && uiStart && transactionCoreStart && routingStart && runtimeStart &&
                firstHeavyFinish &&
                subscriptionStart < firstHeavyFinish && uiStart < firstHeavyFinish &&
                transactionCoreStart < firstHeavyFinish && routingStart < firstHeavyFinish &&
                runtimeStart < firstHeavyFinish)
        }
    ' "${callLog}"

    grep -qx 'subscription-start jobs=2 ui_profile=all subscription_profile=all routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'transaction-system-start jobs=4 ui_profile=all subscription_profile=all routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'transaction-core-start jobs=3 ui_profile=all subscription_profile=all routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'ui-start jobs=3 ui_profile=all subscription_profile=all routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'routing-start jobs=1 ui_profile=all subscription_profile=all routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'runtime-start jobs=1 ui_profile=all subscription_profile=all routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'remote-control-smoke-start jobs=1 ui_profile=all subscription_profile=all routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'remote-control-contract-service-install-start jobs=1 ui_profile=all subscription_profile=all routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    awk '
        $0 == "subscription-finish" { subscriptionFinish = NR }
        $0 == "ui-finish" { uiFinish = NR }
        $0 == "transaction-core-finish" { transactionCoreFinish = NR }
        $0 == "routing-finish" { routingFinish = NR }
        $0 == "runtime-finish" { runtimeFinish = NR }
        $0 == "remote-control-smoke-finish" { remoteSmokeFinish = NR }
        $0 == "remote-control-contract-service-install-finish" { remoteServiceFinish = NR }
        $0 == "transaction-system-start jobs=4 ui_profile=all subscription_profile=all routing_profile= runtime_profile= transaction_core_profile= suppress=1" { transactionSystemStart = NR }
        END {
            exit !(subscriptionFinish && uiFinish && transactionCoreFinish && routingFinish && runtimeFinish &&
                remoteSmokeFinish && remoteServiceFinish && transactionSystemStart &&
                subscriptionFinish < transactionSystemStart && uiFinish < transactionSystemStart &&
                transactionCoreFinish < transactionSystemStart && routingFinish < transactionSystemStart &&
                runtimeFinish < transactionSystemStart && remoteSmokeFinish < transactionSystemStart &&
                remoteServiceFinish < transactionSystemStart)
        }
    ' "${callLog}"

    : >"${callLog}"
    PADM_REGRESSION_ALL_ROUTING_RESOURCE_PROFILE=all runRegressionAll
    grep -qx 'routing-start jobs=1 ui_profile=all subscription_profile=all routing_profile=all runtime_profile= transaction_core_profile= suppress=1' "${callLog}"

    : >"${callLog}"
    PADM_REGRESSION_ALL_RUNTIME_RESOURCE_PROFILE=all runRegressionAll
    grep -qx 'runtime-start jobs=1 ui_profile=all subscription_profile=all routing_profile= runtime_profile=all transaction_core_profile= suppress=1' "${callLog}"

    : >"${callLog}"
    PADM_REGRESSION_ALL_TRANSACTION_CORE_RESOURCE_PROFILE=all runRegressionAll
    grep -qx 'transaction-core-start jobs=3 ui_profile=all subscription_profile=all routing_profile= runtime_profile= transaction_core_profile=all suppress=1' "${callLog}"
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

registerRegressionFunctionLeaf regression-all-composition runRegressionAllCompositionRegression
registerRegressionFunctionLeaf regression-all-child-parallel-budget-composition runRegressionAllChildParallelBudgetCompositionRegression
registerRegressionFunctionLeaf regression-all-resource-layer-composition runRegressionAllResourceLayerCompositionRegression

registerRegressionAggregateRunnerSequential all runRegressionAllSuiteRoot \
    $(listRegressionAllChildSelectors)
