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

runRegressionTransactionCoreSuiteRoot() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    if [[ "${PADM_REGRESSION_TRANSACTION_CORE_RESOURCE_PROFILE:-}" == "all" ]]; then
        mapfile -t selectors < <(listRegressionTransactionCoreHeavyChildSelectors)
        selectorPairs=()
        for selector in "${selectors[@]}"; do
            selectorPairs+=("${selector}" "${selector}")
        done
        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_TRANSACTION_CORE_HEAVY_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-2}}" \
            PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
            runFrameworkParallelRegressionSelectors "${TMP_DIR}/transaction-core-parallel-heavy-${BASHPID:-$$}" \
            "${selectorPairs[@]}"

        mapfile -t selectors < <(listRegressionTransactionCoreMediumChildSelectors)
        selectorPairs=()
        for selector in "${selectors[@]}"; do
            selectorPairs+=("${selector}" "${selector}")
        done
        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_TRANSACTION_CORE_MEDIUM_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-3}}" \
            PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
            runFrameworkParallelRegressionSelectors "${TMP_DIR}/transaction-core-parallel-medium-${BASHPID:-$$}" \
            "${selectorPairs[@]}"

        mapfile -t selectors < <(listRegressionTransactionCoreLightChildSelectors)
        selectorPairs=()
        for selector in "${selectors[@]}"; do
            selectorPairs+=("${selector}" "${selector}")
        done
        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_TRANSACTION_CORE_LIGHT_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}" \
            PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
            runFrameworkParallelRegressionSelectors "${TMP_DIR}/transaction-core-parallel-light-${BASHPID:-$$}" \
            "${selectorPairs[@]}"
        return
    fi

    mapfile -t selectors < <(listRegressionTransactionCoreChildSelectors)
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/transaction-core-parallel-${BASHPID:-$$}" \
        "${selectorPairs[@]}"
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
    runRegressionTransactionCoreSuiteRoot &&
        runRegressionTransactionSubscription &&
        runRegressionTransactionSystemSuiteRoot
}

registerRegressionFunctionLeaf regression-transaction-core-parallel-composition runRegressionTransactionCoreParallelCompositionRegression
registerRegressionFunctionLeaf regression-transaction-system-parallel-composition runRegressionTransactionSystemParallelCompositionRegression
registerRegressionFunctionLeaf transaction-subscription runRegressionTransactionSubscription
registerRegressionFunctionLeaf nginx-service-failure runNginxServiceFailureRegression
registerRegressionFunctionLeaf uninstall-nginx-cleanup runUninstallNginxCleanupRegression
registerRegressionFunctionLeaf clean-agent-nginx-managed-remove runCleanAgentNginxManagedRemovalRegression
registerRegressionFunctionLeaf fail2ban-managed-cleanup runFail2banManagedCleanupRegression
registerRegressionFunctionLeaf fail2ban-apply-transaction runFail2banApplyTransactionRegression
registerRegressionFunctionLeaf uninstall-wireguard-cleanup runUninstallWireGuardCleanupRegression
registerRegressionFunctionLeaf wireguard-key-transaction runWireGuardKeyTransactionRegression
registerRegressionFunctionLeaf wireguard-control-safe-dir runWireGuardControlSafeDirRegression
registerRegressionFunctionLeaf warp-config-safe-dir runWarpConfigSafeDirRegression
registerRegressionFunctionLeaf warp-config-file-cleanup runWarpConfigFileCleanupRegression
registerRegressionFunctionLeaf uninstall-service-stop-failure runUninstallServiceStopFailureRegression
registerRegressionFunctionLeaf clean-last-installation-failure runCleanLastInstallationConfigFailureRegression
registerRegressionFunctionLeaf clean-last-installation-acme-home runCleanLastInstallationConfigAcmeHomeFailureRegression
registerRegressionFunctionLeaf clean-last-installation-acme-relative-home runCleanLastInstallationConfigResolvesRelativeAcmeHomeRegression
registerRegressionFunctionLeaf alone-nginx-write-transaction runAloneNginxConfigWriteTransactionRegression
registerRegressionFunctionLeaf alone-nginx-update-transaction runAloneNginxUpdateTransactionRegression

registerRegressionAggregateRunnerParallel transaction-system runRegressionTransactionSystemSuiteRoot \
    $(listRegressionTransactionSystemChildSelectors)

registerRegressionAggregateRunnerParallel transaction-core runRegressionTransactionCoreSuiteRoot \
    $(listRegressionTransactionCoreChildSelectors)

registerRegressionAggregateRunnerSequential transaction runRegressionTransactionSuiteRoot \
    $(listRegressionTransactionChildSelectors)
