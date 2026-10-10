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

    unset PADM_REGRESSION_PARALLEL_JOBS
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
    [[ "$(wc -l <"${callLog}")" -eq 3 ]] || return 1

    # Geo 需要 root，仅由 Docker 合同覆盖，不能进入普通用户运行的原生 CI。
    ! listRegressionCiChildSelectors | grep -qx docker-geo-data || return 1
    ! listRegressionCiPrChildSelectors | grep -qx docker-geo-data || return 1
    listRegressionDockerContractsFastChildSelectors | grep -qx docker-geo-data || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND[docker-geo-data]}" == function ]]
)

runRegressionDockerContractsAggregateContract() (
    set -euo pipefail
    local callLog="${TMP_DIR}/docker-contracts-aggregate.log"
    local expectedLog="${TMP_DIR}/docker-contracts-aggregate.expected.log"
    local status=0 selector
    local -a expectedSelectors=(
        docker-reality docker-traditional-tls docker-routing-core-contracts docker-routing-core-lifecycle
        docker-routing-dns-hosts-workflow docker-routing-direct-block-workflow
        docker-phase3 docker-setup-encrypted docker-setup-transports docker-reality-targets
        docker-setup-tls docker-reality-parameters docker-setup-core docker-sites docker-phase6
        docker-menu docker-reality-target-library docker-control-state docker-phase4 docker-control-client
        docker-phase1 docker-phase5 docker-control-cli docker-control-sync docker-release docker-geo-data docker-traffic
        docker-http-relay docker-entry-port-alias
        docker-accounts docker-permissions docker-wireguard-runtime docker-tproxy-ownership docker-fail2ban-ownership
        docker-fail2ban-source
        docker-control-api docker-subscriptions
        docker-accounts-cli docker-business docker-phase2
    )

    runFrameworkParallelRegressionSelectors() {
        [[ "${PADM_REGRESSION_PARALLEL_SELECTOR_MODE:-}" == pairs &&
            "${PADM_REGRESSION_PARALLEL_JOBS:-}" == 2 &&
            "${PADM_DOCKER_CONTRACTS_SHARED_CHECKS:-0}" == 1 ]] || return 8
        shift
        printf '%s\n' "$@" >"${callLog}"
        return 7
    }

    : >"${expectedLog}"
    for selector in "${expectedSelectors[@]}"; do
        printf '%s\n%s\n' "${selector}" "${selector}" >>"${expectedLog}"
    done
    unset PADM_REGRESSION_PARALLEL_JOBS
    set +e
    (PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain docker-contracts) >/dev/null 2>&1
    status=$?
    set -e
    [[ "${status}" -eq 7 ]]
    cmp -s "${expectedLog}" "${callLog}"

    # 工作流分片与本机全量套件必须恰好覆盖同一组叶子，不能漏测或重复执行。
    local workflow="${PROJECT_ROOT}/.github/workflows/docker-contracts.yml"
    local actual="${TMP_DIR}/docker-contract-shards.actual"
    local expected="${TMP_DIR}/docker-contract-shards.expected"
    local kind children
    : >"${actual}"
    while IFS= read -r selector; do
        kind=${PADM_REGRESSION_SELECTOR_KIND[${selector}]:-}
        case "${kind}" in
        function) printf '%s\n' "${selector}" >>"${actual}" ;;
        aggregate-runner)
            children=${PADM_REGRESSION_SELECTOR_CHILDREN[${selector}]:-}
            [[ -n "${children}" ]] || return 1
            printf '%s\n' "${children}" >>"${actual}"
            ;;
        *) return 1 ;;
        esac
    done < <(awk '
        /^        selector:$/ {inside = 1; next}
        inside && /^          - / {sub(/^          - /, ""); print; next}
        inside {exit}
    ' "${workflow}")
    printf '%s\n' "${expectedSelectors[@]}" | sort >"${expected}"
    sort -o "${actual}" "${actual}"
    cmp -s "${expected}" "${actual}"

    runDockerSetupRegression() { printf '%s\n' "$*" >>"${callLog}"; }
    : >"${callLog}"
    for selector in core encrypted transports tls; do
        PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain "docker-setup-${selector}"
    done
    printf '%s\n' core encrypted transports tls >"${expectedLog}"
    cmp -s "${expectedLog}" "${callLog}"

    # 独立 selector 仍执行祖先合同，只有完整集合或 CI 矩阵才共享它们。
    runFrameworkParallelRegressionSelectors() {
        [[ "${PADM_DOCKER_CONTRACTS_SHARED_CHECKS:-0}" == 0 ]]
    }
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain docker-contracts-reality
    bash() {
        printf '%s:%s\n' "${PADM_DOCKER_TEST_FIXTURE_ONLY:-0}" "${1##*/}" >>"${callLog}"
    }
    : >"${callLog}"
    unset PADM_DOCKER_CONTRACTS_SHARED_CHECKS
    runDockerRealityParametersRegression
    runDockerRealityTargetsRegression
    runDockerTraditionalTlsRegression
    runDockerRealityRegression
    PADM_DOCKER_CONTRACTS_SHARED_CHECKS=1 runDockerRealityParametersRegression
    PADM_DOCKER_CONTRACTS_SHARED_CHECKS=1 runDockerRealityTargetsRegression
    PADM_DOCKER_CONTRACTS_SHARED_CHECKS=1 runDockerTraditionalTlsRegression
    PADM_DOCKER_CONTRACTS_SHARED_CHECKS=1 runDockerRealityRegression
    printf '%s\n' 0:reality-parameters.sh 0:reality-targets.sh 0:traditional-tls.sh 0:reality.sh \
        1:reality-parameters.sh 1:reality-targets.sh 1:traditional-tls.sh 0:reality.sh >"${expectedLog}"
    cmp -s "${expectedLog}" "${callLog}"
    [[ -z "${PADM_DOCKER_CONTRACTS_SHARED_CHECKS:-}" ]]

    # 注册集合相同还不够，新旧路由入口都必须把正确 scope 传给原脚本。
    bash() { printf '%s:%s\n' "${PADM_DOCKER_ROUTING_SCOPE:-full}" "${1##*/}" >>"${callLog}"; }
    : >"${callLog}"
    unset PADM_DOCKER_ROUTING_SCOPE
    runDockerRoutingSocks5Regression
    runDockerRoutingCoreWorkflowRegression
    runDockerRoutingDomainsWorkflowRegression
    runDockerRoutingCoreContractsRegression
    runDockerRoutingCoreLifecycleRegression
    runDockerRoutingDnsHostsWorkflowRegression
    runDockerRoutingDirectBlockWorkflowRegression
    printf '%s\n' full:routing-socks5.sh core-workflow:routing-socks5.sh \
        domains-workflow:routing-socks5.sh core-contracts:routing-socks5.sh \
        core-lifecycle:routing-socks5.sh domains-dns-hosts:routing-socks5.sh \
        domains-direct-block:routing-socks5.sh >"${expectedLog}"
    cmp -s "${expectedLog}" "${callLog}"
)

runRegressionTargetedBatchHelpers() (
    local captureState=
    regressionCaptureFixture() { captureState=changed; return 7; }
    regressionExpectStatus 7 regressionCaptureFixture
    [[ "${captureState}" == "changed" ]]
    regressionExpectFailure false
    regressionExpectStatus 1 regressionExpectFailure true

    runParallelRegressionRunners "${TMP_DIR}/targeted-batch-helpers-parallel-${BASHPID:-$$}" \
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
        shared fast protocol_capabilities platform routing runtime reality tls ui menu_workflow subscription
        transaction_core transaction_system remote_control subscription_state
    )
    local -a casePaths=()
    local -a runnerArgv=()

    [[ "$(grep -Fxc 'source "${SCRIPT_DIR}/regression/cases/load.sh"' "${entry}")" -eq 1 ]] || return 1
    ! grep -Eq 'source .*regression/cases/(shared|fast|protocol_capabilities|platform|routing|runtime|reality|tls|ui|menu_workflow|subscription|transaction_core|transaction_system|remote_control|subscription_state)[.]sh' "${entry}" || return 1
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
    runRegressionStep docker-contracts-aggregate runRegressionDockerContractsAggregateContract
}

registerRegressionFunctionLeaf regression-dispatcher-contract runRegressionDispatcherContracts
registerRegressionFunctionLeaf framework-parallel-selector-list-with-jobs runFrameworkParallelSelectorListWithJobsContract
registerRegressionFunctionLeaf targeted-batch-helpers runRegressionTargetedBatchHelpers
registerRegressionFunctionLeaf regression-case-loader-contract runRegressionCaseLoaderContract
