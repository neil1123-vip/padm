#!/usr/bin/env bash

REGRESSION_ROUTING_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_ROUTING_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_ROUTING_SUITE_DIR}/../subscription_groups_legacy.sh" --reuse

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
            runFrameworkWaitForFile "${TMP_DIR}/routing-core-unsafe-config-dir-started"
        elif [[ "${selector}" == "routing-access-control-config-transaction" || "${selector}" == "routing-dns-failure-return" ]]; then
            runFrameworkWaitForFile "${TMP_DIR}/routing-socks5-udp-associate-started"
        elif [[ "${selector}" == "routing-core-unsafe-config-dir" ]]; then
            : >"${TMP_DIR}/routing-core-unsafe-config-dir-started"
        elif [[ "${selector}" == "routing-socks5-udp-associate" ]]; then
            : >"${TMP_DIR}/routing-socks5-udp-associate-started"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionRoutingSuiteRoot

    runFrameworkAssertSelectorListLogged "${callLog}" listRegressionRoutingChildSelectors
    awk '
        $0 == "routing-core-start" { coreStart = NR }
        $0 == "routing-core-unsafe-config-dir-start" { unsafeStart = NR }
        $0 == "routing-core-finish" { coreFinish = NR }
        END { exit !(coreStart && unsafeStart && coreFinish && unsafeStart < coreFinish) }
    ' "${callLog}"

    : >"${callLog}"
    rm -f "${TMP_DIR}/routing-core-unsafe-config-dir-started"
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector PADM_REGRESSION_ROUTING_PARALLEL_JOBS=1 runRegressionRoutingSuiteRoot
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
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector PADM_REGRESSION_ROUTING_RESOURCE_PROFILE=all runRegressionRoutingSuiteRoot
    runFrameworkAssertSelectorListLogged "${callLog}" listRegressionRoutingChildSelectors
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

registerRegressionFunctionLeaf routing-socks5-udp-associate runRegressionRoutingLegacyLeafWithCompat runSocks5UdpAssociateRegression
registerRegressionFunctionLeaf routing-core runRegressionRoutingLegacyLeafWithCompat runRoutingRegression
registerRegressionFunctionLeaf routing-core-unsafe-config-dir runRegressionRoutingLegacyLeafWithCompat runRoutingCoreRejectsUnsafeConfigDirRegression
registerRegressionFunctionLeaf routing-access-control-config-transaction runRegressionRoutingLegacyLeafWithCompat runAccessControlConfigTransactionRegression
registerRegressionFunctionLeaf routing-access-control-unsafe-backup-dir runRegressionRoutingLegacyLeafWithCompat runAccessControlRejectsUnsafeBackupDirRegression
registerRegressionFunctionLeaf routing-access-control-unsafe-config-dir runRegressionRoutingLegacyLeafWithCompat runAccessControlRejectsUnsafeConfigDirRegression
registerRegressionFunctionLeaf routing-access-control-failure-return runRegressionRoutingLegacyLeafWithCompat runAccessControlFailureReturnRegression
registerRegressionFunctionLeaf routing-bt-failure-return runRegressionRoutingLegacyLeafWithCompat runBTRoutingFailureReturnRegression
registerRegressionFunctionLeaf routing-ipv6-failure-return runRegressionRoutingLegacyLeafWithCompat runIPv6RoutingFailureReturnRegression
registerRegressionFunctionLeaf routing-warp-failure-return runRegressionRoutingLegacyLeafWithCompat runWARPRoutingFailureReturnRegression
registerRegressionFunctionLeaf routing-socks5-failure-return runRegressionRoutingLegacyLeafWithCompat runSocks5RoutingFailureReturnRegression
registerRegressionFunctionLeaf routing-dns-failure-return runRegressionRoutingLegacyLeafWithCompat runDNSRoutingFailureReturnRegression
registerRegressionFunctionLeaf routing-dns-unsafe-backup-dir runRegressionRoutingLegacyLeafWithCompat runDNSRoutingRejectsUnsafeBackupDirRegression
registerRegressionFunctionLeaf routing-dns-unsafe-config-dir runRegressionRoutingLegacyLeafWithCompat runDNSRoutingRejectsUnsafeConfigDirRegression
registerRegressionFunctionLeaf routing-dns-restore-scope runRegressionRoutingLegacyLeafWithCompat runDNSRoutingRestoreKeepsUnmanagedSingBoxFilesRegression
registerRegressionFunctionLeaf routing-port-panel runRegressionRoutingLegacyLeafWithCompat runPortAndPanelHelperRegression
registerRegressionFunctionLeaf regression-routing-parallel-composition runRegressionRoutingParallelCompositionRegression
registerRegressionFunctionLeaf regression-routing-legacy-read-install-type-isolation runRegressionRoutingLegacyReadInstallTypeIsolationRegression

registerRegressionAggregateRunner parallel routing runRegressionRoutingSuiteRoot \
    $(listRegressionRoutingChildSelectors)
