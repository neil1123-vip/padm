#!/usr/bin/env bash

REGRESSION_ROUTING_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_ROUTING_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_ROUTING_SUITE_DIR}/../subscription_groups_legacy.sh"

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
        routing-access-control-failure-return \
        routing-access-control-unsafe-backup-dir \
        routing-access-control-unsafe-config-dir \
        routing-bt-failure-return \
        routing-ipv6-failure-return \
        routing-warp-failure-return \
        routing-socks5-failure-return \
        routing-dns-unsafe-backup-dir \
        routing-dns-unsafe-config-dir \
        routing-dns-restore-scope \
        routing-port-panel
}

listRegressionRoutingChildSelectors() {
    listRegressionRoutingCoreChildSelectors
    listRegressionRoutingHeavyChildSelectors
    listRegressionRoutingLightChildSelectors
}

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

runRegressionRoutingParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-routing-parallel-composition.log"

    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        if [[ "${selector}" == "routing-core" ]]; then
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${TMP_DIR}/routing-core-unsafe-config-dir-started" ]] && break
                sleep 0.05
            done
        elif [[ "${selector}" == "routing-access-control-config-transaction" ]]; then
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${TMP_DIR}/routing-socks5-udp-associate-started" ]] && break
                sleep 0.05
            done
        elif [[ "${selector}" == "routing-dns-failure-return" ]]; then
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${TMP_DIR}/routing-socks5-udp-associate-started" ]] && break
                sleep 0.05
            done
        elif [[ "${selector}" == "routing-core-unsafe-config-dir" ]]; then
            : >"${TMP_DIR}/routing-core-unsafe-config-dir-started"
        elif [[ "${selector}" == "routing-socks5-udp-associate" ]]; then
            : >"${TMP_DIR}/routing-socks5-udp-associate-started"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }
    runRoutingRegression() { runRegressionAllSelector routing-core; }
    runRoutingCoreRejectsUnsafeConfigDirRegression() { runRegressionAllSelector routing-core-unsafe-config-dir; }
    runSocks5UdpAssociateRegression() { runRegressionAllSelector routing-socks5-udp-associate; }
    runAccessControlFailureReturnRegression() { runRegressionAllSelector routing-access-control-failure-return; }
    runAccessControlConfigTransactionRegression() { runRegressionAllSelector routing-access-control-config-transaction; }
    runAccessControlRejectsUnsafeBackupDirRegression() { runRegressionAllSelector routing-access-control-unsafe-backup-dir; }
    runAccessControlRejectsUnsafeConfigDirRegression() { runRegressionAllSelector routing-access-control-unsafe-config-dir; }
    runBTRoutingFailureReturnRegression() { runRegressionAllSelector routing-bt-failure-return; }
    runIPv6RoutingFailureReturnRegression() { runRegressionAllSelector routing-ipv6-failure-return; }
    runWARPRoutingFailureReturnRegression() { runRegressionAllSelector routing-warp-failure-return; }
    runSocks5RoutingFailureReturnRegression() { runRegressionAllSelector routing-socks5-failure-return; }
    runDNSRoutingFailureReturnRegression() { runRegressionAllSelector routing-dns-failure-return; }
    runDNSRoutingRejectsUnsafeBackupDirRegression() { runRegressionAllSelector routing-dns-unsafe-backup-dir; }
    runDNSRoutingRejectsUnsafeConfigDirRegression() { runRegressionAllSelector routing-dns-unsafe-config-dir; }
    runDNSRoutingRestoreKeepsUnmanagedSingBoxFilesRegression() { runRegressionAllSelector routing-dns-restore-scope; }
    runPortAndPanelHelperRegression() { runRegressionAllSelector routing-port-panel; }

    runRegressionRoutingSuiteRoot

    for selector in \
        routing-core \
        routing-core-unsafe-config-dir \
        routing-socks5-udp-associate \
        routing-access-control-failure-return \
        routing-access-control-config-transaction \
        routing-access-control-unsafe-backup-dir \
        routing-access-control-unsafe-config-dir \
        routing-bt-failure-return \
        routing-ipv6-failure-return \
        routing-warp-failure-return \
        routing-socks5-failure-return \
        routing-dns-failure-return \
        routing-dns-unsafe-backup-dir \
        routing-dns-unsafe-config-dir \
        routing-dns-restore-scope \
        routing-port-panel; do
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done
    awk '
        $0 == "routing-core-start" { coreStart = NR }
        $0 == "routing-core-unsafe-config-dir-start" { unsafeStart = NR }
        $0 == "routing-core-finish" { coreFinish = NR }
        END { exit !(coreStart && unsafeStart && coreFinish && unsafeStart < coreFinish) }
    ' "${callLog}"

    : >"${callLog}"
    rm -f "${TMP_DIR}/routing-core-unsafe-config-dir-started"
    PADM_REGRESSION_ROUTING_PARALLEL_JOBS=1 runRegressionRoutingSuiteRoot
    awk '
        $0 == "routing-core-finish" { firstFinish = NR }
        $0 == "routing-access-control-config-transaction-start" { accessConfigStart = NR }
        $0 == "routing-access-control-config-transaction-finish" { accessConfigFinish = NR }
        $0 == "routing-dns-failure-return-start" { dnsFailureStart = NR }
        $0 == "routing-dns-failure-return-finish" { dnsFailureFinish = NR }
        $0 == "routing-socks5-udp-associate-start" { socksStart = NR }
        $0 == "routing-socks5-udp-associate-finish" { socksFinish = NR }
        $0 == "routing-core-unsafe-config-dir-start" { unsafeStart = NR }
        END {
            exit !(firstFinish && accessConfigStart && accessConfigFinish &&
                dnsFailureStart && dnsFailureFinish && socksStart && socksFinish &&
                unsafeStart && firstFinish < accessConfigStart &&
                accessConfigFinish < dnsFailureStart &&
                dnsFailureFinish < socksStart &&
                socksFinish < unsafeStart)
        }
    ' "${callLog}"

    : >"${callLog}"
    rm -f "${TMP_DIR}/routing-core-unsafe-config-dir-started"
    rm -f "${TMP_DIR}/routing-socks5-udp-associate-started"
    PADM_REGRESSION_ROUTING_RESOURCE_PROFILE=all runRegressionRoutingSuiteRoot
    for selector in \
        routing-core \
        routing-core-unsafe-config-dir \
        routing-socks5-udp-associate \
        routing-access-control-failure-return \
        routing-access-control-config-transaction \
        routing-access-control-unsafe-backup-dir \
        routing-access-control-unsafe-config-dir \
        routing-bt-failure-return \
        routing-ipv6-failure-return \
        routing-warp-failure-return \
        routing-socks5-failure-return \
        routing-dns-failure-return \
        routing-dns-unsafe-backup-dir \
        routing-dns-unsafe-config-dir \
        routing-dns-restore-scope \
        routing-port-panel; do
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done
    awk '
        $0 == "routing-core-finish" { coreFinish = NR }
        $0 == "routing-access-control-config-transaction-start" { accessConfigStart = NR }
        $0 == "routing-dns-failure-return-start" { dnsFailureStart = NR }
        $0 == "routing-socks5-udp-associate-start" { socksStart = NR }
        $0 == "routing-access-control-config-transaction-finish" { accessConfigFinish = NR }
        $0 == "routing-dns-failure-return-finish" { dnsFailureFinish = NR }
        $0 == "routing-socks5-udp-associate-finish" { socksFinish = NR }
        $0 == "routing-core-unsafe-config-dir-start" { lightStart = NR }
        END {
            exit !(coreFinish && accessConfigStart && dnsFailureStart && socksStart &&
                accessConfigFinish && dnsFailureFinish && socksFinish && lightStart &&
                coreFinish < accessConfigStart && coreFinish < dnsFailureStart && coreFinish < socksStart &&
                accessConfigFinish < lightStart && dnsFailureFinish < lightStart && socksFinish < lightStart)
        }
    ' "${callLog}"
)

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
registerRegressionFunctionLeaf regression-routing-parallel-composition runRegressionRoutingParallelCompositionRegression

registerRegressionAggregateRunnerParallel routing runRegressionRoutingSuiteRoot \
    $(listRegressionRoutingChildSelectors)
