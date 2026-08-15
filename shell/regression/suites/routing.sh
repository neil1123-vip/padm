#!/usr/bin/env bash

listRegressionRoutingCoreChildSelectors() {
    printf '%s\n' \
        routing-core
}

listRegressionRoutingHeavyChildSelectors() {
    printf '%s\n' \
        routing-access-control-config-transaction \
        routing-dns-failure-return \
        routing-socks5-udp-associate
}

listRegressionRoutingLightChildSelectors() {
    printf '%s\n' \
        routing-core-unsafe-config-dir \
        routing-access-control-failure-return
}

listRegressionRoutingChildSelectors() {
    listRegressionRoutingCoreChildSelectors
    listRegressionRoutingHeavyChildSelectors
    listRegressionRoutingLightChildSelectors
}

runRegressionRoutingSuiteRoot() {
    if [[ "${PADM_REGRESSION_ROUTING_RESOURCE_PROFILE:-}" == "all" ]]; then
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/routing-parallel-core-${BASHPID:-$$}" \
            listRegressionRoutingCoreChildSelectors

        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_ROUTING_WAVE_PARALLEL_JOBS:-2}" \
            runFrameworkParallelRegressionSelectorList "${TMP_DIR}/routing-parallel-heavy-${BASHPID:-$$}" \
            listRegressionRoutingHeavyChildSelectors

        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_ROUTING_LIGHT_PARALLEL_JOBS:-${PADM_REGRESSION_ROUTING_WAVE_PARALLEL_JOBS:-4}}" \
            runFrameworkParallelRegressionSelectorList "${TMP_DIR}/routing-parallel-light-${BASHPID:-$$}" \
            listRegressionRoutingLightChildSelectors
        return
    fi

    PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_ROUTING_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}" \
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/routing-parallel-${BASHPID:-$$}" \
        listRegressionRoutingChildSelectors
}

registerRegressionFunctionLeaf routing-socks5-udp-associate runSocks5UdpAssociateRegression
registerRegressionFunctionLeaf routing-core runRoutingRegression
registerRegressionFunctionLeaf routing-core-unsafe-config-dir runRoutingCoreRejectsUnsafeConfigDirRegression
registerRegressionFunctionLeaf routing-access-control-config-transaction runAccessControlConfigTransactionRegression
registerRegressionFunctionLeaf routing-access-control-failure-return runAccessControlFailureReturnRegression
registerRegressionFunctionLeaf routing-dns-failure-return runDNSRoutingFailureReturnRegression

registerRegressionAggregateRunner parallel routing runRegressionRoutingSuiteRoot \
    $(listRegressionRoutingChildSelectors)
