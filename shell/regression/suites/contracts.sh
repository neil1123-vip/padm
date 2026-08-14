#!/usr/bin/env bash

runRegressionRegistryRunnerArgsContract() (
    set -euo pipefail
    local callLog="${TMP_DIR}/registry-runner-args.log"
    local expectedLog="${TMP_DIR}/registry-runner-args.expected.log"

    : >"${callLog}"

    runContractFunctionFixture() {
        printf 'function:%s\n' "$*" >>"${callLog}"
    }

    runContractSequentialFixture() {
        printf 'sequential:%s\n' "$*" >>"${callLog}"
    }

    runContractParallelFixture() {
        printf 'parallel:%s\n' "$*" >>"${callLog}"
    }

    registerRegressionFunctionLeaf contract-runner-args-function runContractFunctionFixture alpha beta
    registerRegressionFunctionLeaf contract-runner-args-child-a true
    registerRegressionFunctionLeaf contract-runner-args-child-b true
    registerRegressionAggregateRunnerSequentialWithArgs \
        contract-runner-args-sequential \
        runContractSequentialFixture \
        one \
        two \
        -- \
        contract-runner-args-child-a \
        contract-runner-args-child-b
    registerRegressionAggregateRunnerParallelWithArgs \
        contract-runner-args-parallel \
        runContractParallelFixture \
        three \
        four \
        -- \
        contract-runner-args-child-a \
        contract-runner-args-child-b

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain contract-runner-args-function
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain contract-runner-args-sequential
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain contract-runner-args-parallel

    printf '%s\n' \
        'function:alpha beta' \
        'sequential:one two' \
        'parallel:three four' >"${expectedLog}"
    cmp -s "${expectedLog}" "${callLog}"
)

runRegressionSelectorDispatchCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-selector-dispatch-composition.log"
    local expectedLog="${TMP_DIR}/regression-selector-dispatch-composition.expected.log"

    : >"${callLog}"

    runRegisteredRegressionMain() {
        printf '%s suppress=%s\n' "$1" "${PADM_REGRESSION_SUPPRESS_DONE:-}" >>"${callLog}"
    }

    runRegressionAllSelectorSuiteRoot subscription-state
    runRegressionAllSelectorSuiteRoot remote-control
    runRegressionAllSelectorSuiteRoot routing

    printf '%s\n' \
        'subscription-state suppress=1' \
        'remote-control suppress=1' \
        'routing suppress=1' >"${expectedLog}"
    cmp -s "${expectedLog}" "${callLog}"
)

runRegressionParallelSelectorLimitCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-parallel-selector-limit-composition.log"

    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1

        printf '%s-start\n' "${selector}" >>"${callLog}"
        [[ "${selector}" == "first" ]] && sleep 0.1
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_JOBS=1 \
        PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector \
        PADM_REGRESSION_PARALLEL_SELECTOR_MODE=selectors \
        runParallelRegressionSelectors "${TMP_DIR}/parallel-selector-limit-composition" \
        first \
        second \
        third

    awk '
        $0 == "first-finish" { firstFinish = NR }
        $0 == "second-start" { secondStart = NR }
        $0 == "second-finish" { secondFinish = NR }
        $0 == "third-start" { thirdStart = NR }
        END {
            exit !(firstFinish && secondStart && secondFinish && thirdStart &&
                firstFinish < secondStart && secondFinish < thirdStart)
        }
    ' "${callLog}"
)

runRegressionParallelSelectorSlotRefillCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-parallel-selector-slot-refill-composition.log"
    local thirdStarted="${TMP_DIR}/regression-parallel-selector-slot-refill-third-started"

    : >"${callLog}"
    rm -f "${thirdStarted}"

    runRegressionAllSelector() {
        local selector=$1

        printf '%s-start\n' "${selector}" >>"${callLog}"
        case "${selector}" in
        first)
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${thirdStarted}" ]] && break
                sleep 0.05
            done
            ;;
        second) sleep 0.02 ;;
        third) : >"${thirdStarted}" ;;
        esac
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_JOBS=2 \
        PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector \
        PADM_REGRESSION_PARALLEL_SELECTOR_MODE=selectors \
        runParallelRegressionSelectors "${TMP_DIR}/parallel-selector-slot-refill-composition" \
        first \
        second \
        third

    awk '
        $0 == "first-finish" { firstFinish = NR }
        $0 == "second-finish" { secondFinish = NR }
        $0 == "third-start" { thirdStart = NR }
        END {
            exit !(secondFinish && thirdStart && firstFinish &&
                secondFinish < thirdStart && thirdStart < firstFinish)
        }
    ' "${callLog}"
)

runFrameworkParallelInterruptCleansChildrenContract() (
    set -euo pipefail
    local childPidFile="${TMP_DIR}/framework-parallel-interrupt-child.pid"
    local orchestrationPid=
    local childPid=
    local leafPid=
    local startSeconds=${SECONDS}
    local status=0

    cleanupInterruptFixture() {
        trap - EXIT INT TERM
        [[ -z "${orchestrationPid}" ]] || kill -TERM -- "-${orchestrationPid}" 2>/dev/null || true
        [[ -z "${orchestrationPid}" ]] || wait "${orchestrationPid}" 2>/dev/null || true
        [[ -z "${childPid}" ]] || kill -KILL "${childPid}" 2>/dev/null || true
        [[ -z "${leafPid}" ]] || kill -KILL "${leafPid}" 2>/dev/null || true
    }

    runRegisteredRegressionMain() {
        sleep 30 &
        printf '%s %s\n' "${BASHPID:-$$}" "$!" >"${childPidFile}"
        wait
    }

    trap cleanupInterruptFixture EXIT
    : >"${childPidFile}"
    set -m
    PADM_REGRESSION_PARALLEL_JOBS=1 PADM_REGRESSION_PARALLEL_SELECTOR_MODE=selectors \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/framework-parallel-interrupt" fixture &
    orchestrationPid=$!
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        [[ -s "${childPidFile}" ]] && break
        sleep 0.05
    done
    [[ -s "${childPidFile}" ]]
    read -r childPid leafPid <"${childPidFile}"

    kill -TERM -- "-${orchestrationPid}"
    set +e
    wait "${orchestrationPid}"
    status=$?
    set -e
    orchestrationPid=
    [[ "${status}" -eq 143 ]]
    (( SECONDS - startSeconds < 5 ))
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        ! kill -0 "${childPid}" 2>/dev/null && ! kill -0 "${leafPid}" 2>/dev/null && break
        sleep 0.05
    done
    ! kill -0 "${childPid}" 2>/dev/null
    ! kill -0 "${leafPid}" 2>/dev/null
    childPid=
    leafPid=
    trap - EXIT INT TERM
)

runParallelSelectorCollectsExitedChildWithoutRcContract() (
    set -euo pipefail
    local root="${TMP_DIR}/parallel-selector-exit-without-rc"
    local callLog="${root}/call.log"
    local runnerLog="${root}/runner.log"
    local status=0

    mkdir -p "${root}"
    : >"${callLog}"
    : >"${runnerLog}"

    runRegressionAllSelector() {
        local selector=$1

        printf '%s-start\n' "${selector}" >>"${callLog}"
        case "${selector}" in
        exit-fast) exit 1 ;;
        finish) sleep 0.1 ;;
        esac
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    set +e
    PADM_REGRESSION_PARALLEL_JOBS=2 \
        PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector \
        PADM_REGRESSION_PARALLEL_SELECTOR_MODE=selectors \
        runParallelRegressionSelectors "${root}/orchestration" exit-fast finish >"${runnerLog}" 2>&1
    status=$?
    set -e

    [[ "${status}" -eq 1 ]]
    grep -q '^regression-fail:exit-fast:' "${runnerLog}"
    grep -qx 'finish-finish' "${callLog}"
)

runTransactionSystemAggregateDispatchesChildrenExactlyOnceContract() (
    set -euo pipefail
    local callLog="${TMP_DIR}/transaction-system-aggregate-dispatch.log"
    local expectedLog="${TMP_DIR}/transaction-system-aggregate-dispatch.expected.log"
    local selector

    : >"${callLog}"

    runFrameworkParallelRegressionSelectors() {
        shift
        printf 'call\n' >>"${callLog}"
        printf 'selector:%s\n' "$@" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_JOBS=1 \
        PADM_REGRESSION_SUPPRESS_DONE=1 \
        runRegisteredRegressionMain transaction-system

    printf 'call\n' >"${expectedLog}"
    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        printf 'selector:%s\nselector:%s\n' "${selector}" "${selector}" >>"${expectedLog}"
    done < <(listRegressionTransactionSystemChildSelectors)
    cmp -s "${expectedLog}" "${callLog}"
)

runFrameworkParallelSelectorListWithJobsContract() (
    set -euo pipefail
    local callLog="${TMP_DIR}/framework-parallel-selector-list-with-jobs.log"

    listFrameworkParallelSelectorListWithJobsFixtures() {
        printf '%s\n' alpha beta
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'mode=%s jobs=%s %s\n' \
            "${PADM_REGRESSION_PARALLEL_SELECTOR_MODE:-}" \
            "${PADM_REGRESSION_PARALLEL_JOBS:-}" \
            "$*" >>"${callLog}"
    }

    : >"${callLog}"
    PADM_REGRESSION_PARALLEL_JOBS=9 \
        runFrameworkParallelRegressionSelectorListWithJobs \
        "${TMP_DIR}/framework-parallel-selector-list-with-jobs-root" \
        listFrameworkParallelSelectorListWithJobsFixtures \
        4
    runFrameworkParallelRegressionSelectorListWithJobs \
        "${TMP_DIR}/framework-parallel-selector-list-with-jobs-root" \
        listFrameworkParallelSelectorListWithJobsFixtures \
        4
    runFrameworkParallelRegressionSelectorListWithJobs \
        "${TMP_DIR}/framework-parallel-selector-list-with-jobs-root" \
        listFrameworkParallelSelectorListWithJobsFixtures

    grep -qx 'mode=pairs jobs=9 .* alpha alpha beta beta' "${callLog}"
    grep -qx 'mode=pairs jobs=4 .* alpha alpha beta beta' "${callLog}"
    grep -qx 'mode=pairs jobs= .* alpha alpha beta beta' "${callLog}"
    [[ "$(wc -l <"${callLog}")" -eq 3 ]]
)

runRegressionDispatcherContracts() {
    runRegressionStep registry-runner-args runRegressionRegistryRunnerArgsContract
    runRegressionStep selector-dispatch-composition runRegressionSelectorDispatchCompositionRegression
    runRegressionStep parallel-selector-limit runRegressionParallelSelectorLimitCompositionRegression
    runRegressionStep parallel-selector-slot-refill runRegressionParallelSelectorSlotRefillCompositionRegression
    runRegressionStep parallel-interrupt-cleans-children runFrameworkParallelInterruptCleansChildrenContract
    runRegressionStep parallel-collects-exited-child runParallelSelectorCollectsExitedChildWithoutRcContract
    runRegressionStep transaction-system-dispatches-children-once runTransactionSystemAggregateDispatchesChildrenExactlyOnceContract
    runRegressionStep parallel-selector-list-with-jobs runFrameworkParallelSelectorListWithJobsContract
}

registerRegressionFunctionLeaf regression-dispatcher-contract runRegressionDispatcherContracts
registerRegressionFunctionLeaf regression-selector-dispatch-composition runRegressionSelectorDispatchCompositionRegression
registerRegressionFunctionLeaf regression-parallel-selector-limit-composition runRegressionParallelSelectorLimitCompositionRegression
registerRegressionFunctionLeaf regression-parallel-selector-slot-refill-composition runRegressionParallelSelectorSlotRefillCompositionRegression
registerRegressionFunctionLeaf framework-parallel-selector-list-with-jobs runFrameworkParallelSelectorListWithJobsContract
