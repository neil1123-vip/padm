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

runRegressionRoutingLegacyLeafWithCompat() (
    # Re-source legacy routing fixtures in an isolated subshell so later suite
    # loads cannot overwrite routing leaf dependencies like readInstallType.
    PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_ROUTING_SUITE_DIR}/../subscription_groups_legacy.sh"
    "$@"
)

runRegressionRoutingLegacyReadInstallTypeIsolationRegression() (
    set -euo pipefail

    readInstallType() {
        coreInstallType=
        configPath=
        singBoxConfigPath=
    }

    runRegressionRoutingLegacyLeafWithCompat runRegressionRoutingLegacyReadInstallTypeIsolationProbe
)

runRegressionRoutingLegacyReadInstallTypeIsolationProbe() {
    local configPath="${TMP_DIR}/routing-legacy-read-install-type/"
    mkdir -p "${configPath}"
    coreInstallType=1
    cat >"${configPath}02_sniffing_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{}}]}
JSON
    installSniffing
    jq -e '
      .inbounds[0].sniffing.enabled == true and
      (.inbounds[0].sniffing.destOverride | sort) == ["http", "quic", "tls"]
    ' "${configPath}02_sniffing_inbounds.json" >/dev/null
}

runRoutingCoreCompatRegression() { runRegressionRoutingLegacyLeafWithCompat runRoutingRegression; }
runRoutingCoreUnsafeConfigDirCompatRegression() { runRegressionRoutingLegacyLeafWithCompat runRoutingCoreRejectsUnsafeConfigDirRegression; }
runRoutingSocks5UdpAssociateCompatRegression() { runRegressionRoutingLegacyLeafWithCompat runSocks5UdpAssociateRegression; }
runRoutingAccessControlFailureReturnCompatRegression() { runRegressionRoutingLegacyLeafWithCompat runAccessControlFailureReturnRegression; }
runRoutingAccessControlConfigTransactionCompatRegression() { runRegressionRoutingLegacyLeafWithCompat runAccessControlConfigTransactionRegression; }
runRoutingAccessControlUnsafeBackupDirCompatRegression() { runRegressionRoutingLegacyLeafWithCompat runAccessControlRejectsUnsafeBackupDirRegression; }
runRoutingAccessControlUnsafeConfigDirCompatRegression() { runRegressionRoutingLegacyLeafWithCompat runAccessControlRejectsUnsafeConfigDirRegression; }
runRoutingBTFailureReturnCompatRegression() { runRegressionRoutingLegacyLeafWithCompat runBTRoutingFailureReturnRegression; }
runRoutingIPv6FailureReturnCompatRegression() { runRegressionRoutingLegacyLeafWithCompat runIPv6RoutingFailureReturnRegression; }
runRoutingWarpFailureReturnCompatRegression() { runRegressionRoutingLegacyLeafWithCompat runWARPRoutingFailureReturnRegression; }
runRoutingSocks5FailureReturnCompatRegression() { runRegressionRoutingLegacyLeafWithCompat runSocks5RoutingFailureReturnRegression; }
runRoutingDNSFailureReturnCompatRegression() { runRegressionRoutingLegacyLeafWithCompat runDNSRoutingFailureReturnRegression; }
runRoutingDNSUnsafeBackupDirCompatRegression() { runRegressionRoutingLegacyLeafWithCompat runDNSRoutingRejectsUnsafeBackupDirRegression; }
runRoutingDNSUnsafeConfigDirCompatRegression() { runRegressionRoutingLegacyLeafWithCompat runDNSRoutingRejectsUnsafeConfigDirRegression; }
runRoutingDNSRestoreScopeCompatRegression() { runRegressionRoutingLegacyLeafWithCompat runDNSRoutingRestoreKeepsUnmanagedSingBoxFilesRegression; }
runRoutingPortPanelCompatRegression() { runRegressionRoutingLegacyLeafWithCompat runPortAndPanelHelperRegression; }

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
    runRoutingCoreCompatRegression() { runRegressionAllSelector routing-core; }
    runRoutingCoreUnsafeConfigDirCompatRegression() { runRegressionAllSelector routing-core-unsafe-config-dir; }
    runRoutingSocks5UdpAssociateCompatRegression() { runRegressionAllSelector routing-socks5-udp-associate; }
    runRoutingAccessControlFailureReturnCompatRegression() { runRegressionAllSelector routing-access-control-failure-return; }
    runRoutingAccessControlConfigTransactionCompatRegression() { runRegressionAllSelector routing-access-control-config-transaction; }
    runRoutingAccessControlUnsafeBackupDirCompatRegression() { runRegressionAllSelector routing-access-control-unsafe-backup-dir; }
    runRoutingAccessControlUnsafeConfigDirCompatRegression() { runRegressionAllSelector routing-access-control-unsafe-config-dir; }
    runRoutingBTFailureReturnCompatRegression() { runRegressionAllSelector routing-bt-failure-return; }
    runRoutingIPv6FailureReturnCompatRegression() { runRegressionAllSelector routing-ipv6-failure-return; }
    runRoutingWarpFailureReturnCompatRegression() { runRegressionAllSelector routing-warp-failure-return; }
    runRoutingSocks5FailureReturnCompatRegression() { runRegressionAllSelector routing-socks5-failure-return; }
    runRoutingDNSFailureReturnCompatRegression() { runRegressionAllSelector routing-dns-failure-return; }
    runRoutingDNSUnsafeBackupDirCompatRegression() { runRegressionAllSelector routing-dns-unsafe-backup-dir; }
    runRoutingDNSUnsafeConfigDirCompatRegression() { runRegressionAllSelector routing-dns-unsafe-config-dir; }
    runRoutingDNSRestoreScopeCompatRegression() { runRegressionAllSelector routing-dns-restore-scope; }
    runRoutingPortPanelCompatRegression() { runRegressionAllSelector routing-port-panel; }

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

registerRegressionFunctionLeaf routing-socks5-udp-associate runRoutingSocks5UdpAssociateCompatRegression
registerRegressionFunctionLeaf routing-core runRoutingCoreCompatRegression
registerRegressionFunctionLeaf routing-core-unsafe-config-dir runRoutingCoreUnsafeConfigDirCompatRegression
registerRegressionFunctionLeaf routing-access-control-config-transaction runRoutingAccessControlConfigTransactionCompatRegression
registerRegressionFunctionLeaf routing-access-control-unsafe-backup-dir runRoutingAccessControlUnsafeBackupDirCompatRegression
registerRegressionFunctionLeaf routing-access-control-unsafe-config-dir runRoutingAccessControlUnsafeConfigDirCompatRegression
registerRegressionFunctionLeaf routing-access-control-failure-return runRoutingAccessControlFailureReturnCompatRegression
registerRegressionFunctionLeaf routing-bt-failure-return runRoutingBTFailureReturnCompatRegression
registerRegressionFunctionLeaf routing-ipv6-failure-return runRoutingIPv6FailureReturnCompatRegression
registerRegressionFunctionLeaf routing-warp-failure-return runRoutingWarpFailureReturnCompatRegression
registerRegressionFunctionLeaf routing-socks5-failure-return runRoutingSocks5FailureReturnCompatRegression
registerRegressionFunctionLeaf routing-dns-failure-return runRoutingDNSFailureReturnCompatRegression
registerRegressionFunctionLeaf routing-dns-unsafe-backup-dir runRoutingDNSUnsafeBackupDirCompatRegression
registerRegressionFunctionLeaf routing-dns-unsafe-config-dir runRoutingDNSUnsafeConfigDirCompatRegression
registerRegressionFunctionLeaf routing-dns-restore-scope runRoutingDNSRestoreScopeCompatRegression
registerRegressionFunctionLeaf routing-port-panel runRoutingPortPanelCompatRegression
registerRegressionFunctionLeaf regression-routing-parallel-composition runRegressionRoutingParallelCompositionRegression
registerRegressionFunctionLeaf regression-routing-legacy-read-install-type-isolation runRegressionRoutingLegacyReadInstallTypeIsolationRegression

registerRegressionAggregateRunnerParallel routing runRegressionRoutingSuiteRoot \
    $(listRegressionRoutingChildSelectors)
