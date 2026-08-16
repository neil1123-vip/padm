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
    registerRegressionAggregateRunnerWithArgs sequential \
        contract-runner-args-sequential \
        runContractSequentialFixture \
        one \
        two \
        -- \
        contract-runner-args-child-a \
        contract-runner-args-child-b
    registerRegressionAggregateRunnerWithArgs parallel \
        contract-runner-args-parallel \
        runContractParallelFixture \
        three \
        four \
        -- \
        contract-runner-args-child-a \
        contract-runner-args-child-b

    if registerRegressionAggregateRunnerWithArgs sequential \
        contract-runner-args-sequential \
        runContractSequentialFixture \
        one \
        two \
        -- \
        contract-runner-args-child-a 2>/dev/null; then
        return 1
    fi

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain contract-runner-args-function
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain contract-runner-args-sequential
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain contract-runner-args-parallel

    printf '%s\n' \
        'function:alpha beta' \
        'sequential:one two' \
        'parallel:three four' >"${expectedLog}"
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
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/parallel-selector-limit-composition" \
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
        runFrameworkParallelRegressionSelectors "${root}/orchestration" exit-fast finish >"${runnerLog}" 2>&1
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

runRegressionTargetedBatchHelpers() (
    local captureState=
    regressionCaptureFixture() { captureState=changed; return 7; }
    regressionExpectStatus 7 regressionCaptureFixture
    [[ "${captureState}" == "changed" ]]

    runParallelRegressionRunners "${TMP_DIR}/targeted-batch-helpers-parallel-${BASHPID:-$$}" \
        core-invalid-input-retry-menu runCoreInvalidInputRetryMenuRegression \
        core-selection-retry-action runCoreSelectionRetryActionRegression \
        configured-account-helpers runConfiguredAccountHelpersRegression \
        sync-append-local-user-batch runSubscriptionSyncAppendLocalUserBatchRegression \
        traffic-account-id-map-helper runTrafficAccountIdMapHelperRegression \
        subscription-remote-sources-no-reverse-decode runRemoteSubscribeSourcesAvoidReverseDecodeRegression \
        config-transaction runConfigTransactionRegression \
        padm-bbr-managed-cleanup runPadmBbrManagedCleanupRegression \
        alone-nginx-backup-manual-check runNginxBackupManualCheckRegression
)

runRegressionCaseLoaderContract() (
    set -euo pipefail
    local entry="${PROJECT_ROOT}/shell/subscription_groups_regression.sh"
    local casesDir="${PROJECT_ROOT}/shell/regression/cases"
    local load="${casesDir}/load.sh"
    local sourceLog="${TMP_DIR}/regression-case-loader-top-level-source.log"
    local compatibilityPattern='LegacyLeafWith''Compat|FastLeafWith''Compat|PADM_REGRESSION_LEGACY_FIXTURES_''LOADED|--re''use([[:space:]]|$)'
    local suiteFile caseFile selector runner runnerArgs
    local -a expectedCases=(
        shared fast protocol_capabilities platform routing runtime reality tls ui subscription
        transaction_core transaction_subscription transaction_system remote_control subscription_state
    )
    local -a casePaths=()
    local -a runnerArgv=()

    [[ "$(grep -Fxc 'source "${SCRIPT_DIR}/regression/cases/load.sh"' "${entry}")" -eq 1 ]] || return 1
    ! grep -Eq 'source .*regression/cases/(shared|fast|protocol_capabilities|platform|routing|runtime|reality|tls|ui|subscription|transaction_core|transaction_subscription|transaction_system|remote_control|subscription_state)[.]sh' "${entry}" || return 1
    [[ "$(grep -Ec '^source "\$\{REGRESSION_CASES_DIR\}/[^/]+[.]sh"$' "${load}")" -eq "${#expectedCases[@]}" ]] || return 1
    for caseFile in "${expectedCases[@]}"; do
        [[ "$(grep -Fxc "source \"\${REGRESSION_CASES_DIR}/${caseFile}.sh\"" "${load}")" -eq 1 ]] || return 1
        casePaths+=("${casesDir}/${caseFile}.sh")
    done
    : >"${sourceLog}"
    runRegressionCaseLoadBoundaryProbe \
        "${PROJECT_ROOT}" "${sourceLog}" "${casePaths[@]}" || return 1
    [[ ! -s "${sourceLog}" ]] || return 1
    for suiteFile in "${PROJECT_ROOT}"/shell/regression/suites/*.sh; do
        ! grep -Eq '^[[:space:]]*(PADM_REGRESSION_SOURCE_ONLY=1[[:space:]]+)?source[[:space:]]' "${suiteFile}" || return 1
    done
    ! grep -R -E -- "${compatibilityPattern}" \
        "${PROJECT_ROOT}/shell/regression" "${entry}" || return 1

    validateRegressionRegistry || return 1
    for selector in "${PADM_REGRESSION_REGISTERED_SELECTORS[@]}"; do
        [[ "${PADM_REGRESSION_SELECTOR_KIND[${selector}]}" == function ]] || continue
        runner=${PADM_REGRESSION_SELECTOR_RUNNER[${selector}]}
        declare -F "${runner}" >/dev/null || return 1
        [[ "${runner}" == runRegressionStep ]] || continue
        runnerArgs=${PADM_REGRESSION_SELECTOR_RUNNER_ARGS[${selector}]:-}
        runnerArgv=()
        mapfile -t runnerArgv <<<"${runnerArgs}"
        [[ "${#runnerArgv[@]}" -ge 2 ]] || return 1
        declare -F "${runnerArgv[1]}" >/dev/null || return 1
    done
)

runRegressionDispatcherContracts() {
    runRegressionStep registry-runner-args runRegressionRegistryRunnerArgsContract
    runRegressionStep parallel-selector-limit runRegressionParallelSelectorLimitCompositionRegression
    runRegressionStep parallel-interrupt-cleans-children runFrameworkParallelInterruptCleansChildrenContract
    runRegressionStep parallel-collects-exited-child runParallelSelectorCollectsExitedChildWithoutRcContract
    runRegressionStep transaction-system-dispatches-children-once runTransactionSystemAggregateDispatchesChildrenExactlyOnceContract
    runRegressionStep parallel-selector-list-with-jobs runFrameworkParallelSelectorListWithJobsContract
}

registerRegressionFunctionLeaf regression-dispatcher-contract runRegressionDispatcherContracts
registerRegressionFunctionLeaf framework-parallel-selector-list-with-jobs runFrameworkParallelSelectorListWithJobsContract
registerRegressionFunctionLeaf targeted-batch-helpers runRegressionTargetedBatchHelpers
registerRegressionFunctionLeaf regression-case-loader-contract runRegressionCaseLoaderContract
