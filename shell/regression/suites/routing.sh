#!/usr/bin/env bash

REGRESSION_ROUTING_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_ROUTING_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_ROUTING_SUITE_DIR}/../subscription_groups_legacy.sh"

runRegressionRoutingSuiteRoot() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    if [[ "${PADM_REGRESSION_ROUTING_RESOURCE_PROFILE:-}" == "all" ]]; then
        mapfile -t selectors < <(listRegressionRoutingCoreChildSelectors)
        selectorPairs=()
        for selector in "${selectors[@]}"; do
            selectorPairs+=("${selector}" "${selector}")
        done
        PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
            runFrameworkParallelRegressionSelectors "${TMP_DIR}/routing-parallel-core-${BASHPID:-$$}" \
            "${selectorPairs[@]}"

        mapfile -t selectors < <(listRegressionRoutingHeavyChildSelectors)
        selectorPairs=()
        for selector in "${selectors[@]}"; do
            selectorPairs+=("${selector}" "${selector}")
        done
        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_ROUTING_WAVE_PARALLEL_JOBS:-2}" \
            PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
            runFrameworkParallelRegressionSelectors "${TMP_DIR}/routing-parallel-heavy-${BASHPID:-$$}" \
            "${selectorPairs[@]}"

        mapfile -t selectors < <(listRegressionRoutingLightChildSelectors)
        selectorPairs=()
        for selector in "${selectors[@]}"; do
            selectorPairs+=("${selector}" "${selector}")
        done
        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_ROUTING_LIGHT_PARALLEL_JOBS:-${PADM_REGRESSION_ROUTING_WAVE_PARALLEL_JOBS:-4}}" \
            PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
            runFrameworkParallelRegressionSelectors "${TMP_DIR}/routing-parallel-light-${BASHPID:-$$}" \
            "${selectorPairs[@]}"
        return
    fi

    mapfile -t selectors < <(listRegressionRoutingChildSelectors)
    selectorPairs=()
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_ROUTING_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}" \
        PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/routing-parallel-${BASHPID:-$$}" \
        "${selectorPairs[@]}"
}

registerRegressionFunctionLeaf routing-socks5-udp-associate runSocks5UdpAssociateRegression
registerRegressionFunctionLeaf routing-core runRoutingRegression
registerRegressionFunctionLeaf routing-core-unsafe-config-dir runRoutingCoreRejectsUnsafeConfigDirRegression
registerRegressionFunctionLeaf routing-access-control-config-transaction runAccessControlConfigTransactionRegression
registerRegressionFunctionLeaf routing-access-control-unsafe-backup-dir runAccessControlRejectsUnsafeBackupDirRegression
registerRegressionFunctionLeaf routing-access-control-unsafe-config-dir runAccessControlRejectsUnsafeConfigDirRegression
registerRegressionFunctionLeaf routing-access-control-failure-return runAccessControlFailureReturnRegression
registerRegressionFunctionLeaf routing-bt-failure-return runBTRoutingFailureReturnRegression
registerRegressionFunctionLeaf routing-ipv6-failure-return runIPv6RoutingFailureReturnRegression
registerRegressionFunctionLeaf routing-warp-failure-return runWARPRoutingFailureReturnRegression
registerRegressionFunctionLeaf routing-socks5-failure-return runSocks5RoutingFailureReturnRegression
registerRegressionFunctionLeaf routing-dns-failure-return runDNSRoutingFailureReturnRegression
registerRegressionFunctionLeaf routing-dns-unsafe-backup-dir runDNSRoutingRejectsUnsafeBackupDirRegression
registerRegressionFunctionLeaf routing-dns-unsafe-config-dir runDNSRoutingRejectsUnsafeConfigDirRegression
registerRegressionFunctionLeaf routing-dns-restore-scope runDNSRoutingRestoreKeepsUnmanagedSingBoxFilesRegression
registerRegressionFunctionLeaf routing-port-panel runPortAndPanelHelperRegression

registerRegressionAggregateRunnerParallel routing runRegressionRoutingSuiteRoot \
    $(listRegressionRoutingChildSelectors)
