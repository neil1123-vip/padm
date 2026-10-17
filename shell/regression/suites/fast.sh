#!/usr/bin/env bash

listRegressionFastOnlyOutputChildSelectors() {
    printf '%s\n' \
        fast-only-output-auto-install \
        fast-only-output-rest
}

listRegressionFastOnlyChildSelectors() {
    printf '%s\n' \
        fast-only-safety \
        static-sites \
        fast-only-output \
        fast-only-compatibility
}

listRegressionFastChildSelectors() {
    printf '%s\n' \
        platform-smoke \
        fast-smoke
}

listRegressionFastFullChildSelectors() {
    printf '%s\n' \
        platform-hot \
        fast-only
}

listRegressionCiChildSelectors() {
    # platform-refresh 已覆盖 fast 中三项安装检查，完整性检查单独补齐，避免重复夹具并发。
    # 先启动耗时最长的独立任务，避免服务失败回归排到队尾。
    printf '%s\n' \
        core-install-service-action-failure \
        core-install-signal-rollback \
        subscription-state \
        fast-smoke \
        platform-refresh \
        install-module-manifest \
        static-sites \
        subscription-output \
        core-safety-rollback
}

listRegressionCiPrChildSelectors() {
    # PR 默认只跑不依赖大型状态夹具的安全门；订阅和 harness 变更由工作流按范围升级到 ci。
    printf '%s\n' \
        core-install-service-action-failure \
        core-install-signal-rollback \
        fast-smoke \
        platform-refresh \
        install-module-manifest \
        core-safety-rollback
}

listRegressionDockerTlsFocusedChildSelectors() {
    printf '%s\n' \
        docker-tls \
        docker-renewal
}

listRegressionDockerContractsChildSelectors() {
    # 日常合同保留高频核心门禁；恢复故障注入、升级及功能矩阵在 full 与 CI 执行。
    # 所有权与密钥长任务先启动，避免最后只剩一个长任务。
    printf '%s\n' \
        docker-port-hopping-preflight \
        docker-tproxy-ownership \
        docker-redirect-focused \
        docker-reality \
        docker-shadowsocks-rotation \
        docker-phase4-maintenance \
        docker-vless-encryption \
        docker-reality-parameters \
        docker-phase4-lifecycle \
        docker-xhttp-rollback \
        docker-recovery-preview \
        docker-fail2ban-ownership \
        docker-control-state \
        docker-tun-management \
        docker-release \
        docker-control-cli \
        docker-routing-core-contracts \
        docker-subscriptions \
        docker-phase5 \
        docker-xhttp-validation \
        docker-backup \
        docker-control-sync \
        docker-geo-data \
        docker-ssh-driver \
        docker-ssh-preflight \
        docker-traffic \
        docker-accounts \
        docker-permissions \
        docker-fail2ban-source \
        docker-control-api \
        docker-accounts-cli \
        docker-wireguard-runtime \
        docker-business \
        docker-phase2
}

listRegressionDockerContractsFullChildSelectors() {
    # 按完整回归实测耗时先启动长任务，避免恢复故障矩阵独占收尾。
    printf '%s\n' \
        docker-phase3-entries-management-tls \
        docker-phase3-entries-management-tls-reinstall \
        docker-recovery-apply \
        docker-xhttp-edit \
        docker-port-hopping-preflight \
        docker-tproxy-ownership \
        docker-redirect-focused \
        docker-phase3-entries-management-protocol \
        docker-reality \
        docker-sites \
        docker-shadowsocks-rotation \
        docker-phase4-maintenance \
        docker-setup-encrypted-udp \
        docker-reality-targets-direct \
        docker-menu \
        docker-setup-tls \
        docker-vless-encryption \
        docker-phase3-entries-topology \
        docker-reality-parameters \
        docker-routing-core-network-lifecycle \
        docker-control-client \
        docker-setup-core \
        docker-phase4-lifecycle \
        docker-entry-port-alias \
        docker-phase3-edit \
        docker-recovery-preview \
        docker-phase6 \
        docker-cdn-entries \
        docker-routing-dns-hosts-workflow \
        docker-routing-direct-block-csv-workflow \
        docker-traditional-tls-base \
        docker-routing-core-policy-lifecycle \
        docker-routing-direct-block-ip-workflow \
        docker-traditional-tls-transports \
        docker-xhttp-rollback \
        docker-phase1 \
        docker-setup-transports \
        docker-reality-targets-selection \
        docker-fail2ban-ownership \
        docker-control-state \
        docker-http-relay \
        docker-tun-management \
        docker-setup-encrypted-tcp \
        docker-reality-target-library \
        docker-control-cli \
        docker-release \
        docker-routing-core-contracts \
        docker-subscriptions \
        docker-routing-hosts-input \
        docker-backup \
        docker-routing-block-ips-resolved \
        docker-xhttp-validation \
        docker-phase5 \
        docker-control-sync \
        docker-geo-data \
        docker-ssh-driver \
        docker-ssh-preflight \
        docker-traffic \
        docker-accounts \
        docker-permissions \
        docker-fail2ban-source \
        docker-control-api \
        docker-accounts-cli \
        docker-wireguard-runtime \
        docker-business \
        docker-phase2
}

runRegressionDockerContracts() {
    # 完整集合与协议分片都独立覆盖共同祖先合同，派生测试只初始化夹具。
    PADM_DOCKER_CONTRACTS_SHARED_CHECKS=1 \
        runFrameworkParallelRegressionSelectorListWithJobs "$@"
}

listRegressionDockerContractsFastChildSelectors() {
    listRegressionDockerContractsFastHeavyChildSelectors
    listRegressionDockerContractsFastSitesChildSelectors
    listRegressionDockerContractsFastRestChildSelectors
    listRegressionDockerContractsRecoveryChildSelectors
    printf '%s\n' docker-port-hopping-preflight docker-tproxy-ownership docker-redirect-focused \
        docker-cdn-entries docker-http-relay docker-control-cli docker-routing-block-ips-resolved
}

listRegressionDockerContractsFastHeavyChildSelectors() {
    printf '%s\n' docker-menu docker-entry-port-alias
}

listRegressionDockerContractsFastSitesChildSelectors() {
    printf '%s\n' docker-sites docker-wireguard-runtime docker-control-state
}

listRegressionDockerContractsFastRestChildSelectors() {
    # 按 CI 实测优先启动长事务；恢复测试独立，避免尾部只剩故障注入。
    printf '%s\n' \
        docker-control-client \
        docker-xhttp-rollback \
        docker-fail2ban-ownership \
        docker-tun-management \
        docker-subscriptions \
        docker-phase5 \
        docker-xhttp-validation \
        docker-control-sync \
        docker-geo-data \
        docker-ssh-driver \
        docker-traffic \
        docker-accounts \
        docker-ssh-preflight \
        docker-fail2ban-source \
        docker-permissions \
        docker-accounts-cli \
        docker-control-api \
        docker-business \
        docker-phase2
}

listRegressionDockerContractsRecoveryChildSelectors() {
    printf '%s\n' docker-recovery-apply docker-phase1 docker-recovery-preview docker-release docker-backup
}

listRegressionDockerContractsSystemChildSelectors() {
    printf '%s\n' docker-phase3 docker-phase4-maintenance docker-phase4-lifecycle docker-phase6
}

listRegressionDockerContractsRoutingChildSelectors() {
    printf '%s\n' \
        docker-routing-core-contracts \
        docker-routing-core-network-lifecycle \
        docker-routing-core-policy-lifecycle \
        docker-routing-dns-hosts-workflow \
        docker-routing-direct-block-ip-workflow \
        docker-routing-direct-block-csv-workflow
}

listRegressionDockerContractsProtocolChildSelectors() {
    printf '%s\n' docker-traditional-tls-base docker-traditional-tls-transports docker-reality
}

listRegressionDockerCoreAssessmentChildSelectors() {
    printf '%s\n' docker-phase1 docker-release docker-menu docker-phase3 docker-phase6
}

listRegressionDockerGeoChildSelectors() {
    printf '%s\n' docker-geo-data docker-menu docker-phase3 docker-phase6 docker-renewal
}

listRegressionDockerContractsRealityChildSelectors() {
    printf '%s\n' docker-reality-parameters docker-reality-targets-direct \
        docker-reality-targets-selection docker-reality-target-library
}

listRegressionDockerVlessEncryptionChildSelectors() {
    printf '%s\n' docker-vless-encryption docker-vless-encryption-real
}

listRegressionDockerSubscriptionPublicationChildSelectors() {
    printf '%s\n' docker-subscriptions docker-spec-validation docker-setup-transports docker-setup-tls
}

listRegressionDockerContractsRealityMetadataChildSelectors() {
    printf '%s\n' docker-reality-parameters docker-vless-encryption \
        docker-reality-targets-selection docker-reality-target-library
}

listRegressionDockerContractsRealityRotationChildSelectors() {
    printf '%s\n' docker-shadowsocks-rotation docker-reality
}

listRegressionDockerContractsSetupBasicChildSelectors() {
    printf '%s\n' docker-setup-core docker-traditional-tls-base docker-setup-tls
}

listRegressionDockerContractsSetupTransportsChildSelectors() {
    printf '%s\n' docker-setup-encrypted-udp docker-setup-transports \
        docker-traditional-tls-transports
}

listRegressionDockerContractsSystemLightChildSelectors() {
    printf '%s\n' docker-phase4-maintenance docker-phase4-lifecycle docker-phase6
}

listRegressionDockerContractsPhase3TlsChildSelectors() {
    printf '%s\n' docker-phase3-entries-management-tls docker-phase3-entries-management-tls-reinstall \
        docker-phase1 docker-setup-encrypted-tcp
}

listRegressionDockerContractsPhase3ProtocolChildSelectors() {
    printf '%s\n' docker-phase3-entries-management-protocol docker-phase3-edit docker-control-cli
}

listRegressionDockerContractsPhase3TopologyChildSelectors() {
    printf '%s\n' docker-phase3-entries-topology docker-reality-targets-direct docker-http-relay
}

listRegressionDockerContractsPolicyChildSelectors() {
    printf '%s\n' docker-routing-core-policy-lifecycle docker-cdn-entries
}

listRegressionDockerRoutingIpOwnershipChildSelectors() {
    printf '%s\n' docker-tproxy-ownership docker-routing-direct-block-ip-workflow
}

listRegressionDockerRoutingCoreNetworkChildSelectors() {
    printf '%s\n' docker-redirect-focused docker-routing-core-network-lifecycle docker-routing-core-contracts \
        docker-routing-block-ips-resolved
}

listRegressionDockerRoutingDnsCsvChildSelectors() {
    printf '%s\n' docker-routing-dns-hosts-workflow docker-routing-direct-block-csv-workflow \
        docker-recovery-preview docker-routing-hosts-input docker-release docker-backup
}

runDockerTrafficRegression() {
    bash "${PROJECT_ROOT}/docker/tests/traffic.sh"
}

runDockerRoutingSocks5Regression() {
    bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerMenuRoutingRegression() {
    PADM_DOCKER_MENU_SCOPE=routing runDockerMenuRegression
}

runDockerMenuPortAliasRegression() {
    PADM_DOCKER_MENU_SCOPE=port-alias runDockerMenuRegression
}

runDockerMenuTunRegression() {
    PADM_DOCKER_MENU_SCOPE=tun runDockerMenuRegression
}

runDockerMenuXhttpRegression() {
    PADM_DOCKER_MENU_SCOPE=xhttp runDockerMenuRegression
}

runDockerMenuMaintenanceRegression() {
    PADM_DOCKER_MENU_SCOPE=maintenance runDockerMenuRegression
}

runDockerHttpRelayRegression() {
    bash "${PROJECT_ROOT}/docker/tests/http-relay.sh"
}

runDockerHttpRelayRealRegression() {
    bash "${PROJECT_ROOT}/docker/tests/http-relay-real.sh"
}

runDockerHttpRelayPublishedRealRegression() {
    bash "${PROJECT_ROOT}/docker/tests/http-relay-published-real.sh"
}

runDockerEntryPortAliasRegression() {
    bash "${PROJECT_ROOT}/docker/tests/entry-port-alias.sh"
}

runDockerCdnEntriesRegression() {
    bash "${PROJECT_ROOT}/docker/tests/cdn-entries.sh"
}

runDockerCdnEntriesRealRegression() {
    bash "${PROJECT_ROOT}/docker/tests/cdn-entries-real.sh"
}

runDockerAlpnRealRegression() {
    local file
    for file in cdn-entries-real vmess-real; do
        bash -n "${PROJECT_ROOT}/docker/tests/${file}.sh"
    done
    shellcheck --severity=error "${PROJECT_ROOT}/docker/tests/"{cdn-entries-real,vmess-real}.sh
    PADM_TEST_ALPN_ORDERS=1 bash "${PROJECT_ROOT}/docker/tests/cdn-entries-real.sh"
}

runDockerXhttpRegression() {
    bash -n "${PROJECT_ROOT}/docker/tests/xhttp.sh"
    shellcheck --severity=error "${PROJECT_ROOT}/docker/tests/xhttp.sh"
    bash "${PROJECT_ROOT}/docker/tests/xhttp.sh"
}

runDockerXhttpValidationRegression() {
    PADM_DOCKER_XHTTP_SCOPE=validation runDockerXhttpRegression
}

runDockerXhttpEditRegression() {
    bash -n "${PROJECT_ROOT}/docker/tests/xhttp.sh" &&
        shellcheck --severity=error "${PROJECT_ROOT}/docker/tests/xhttp.sh" &&
        PADM_REGRESSION_PARALLEL_JOBS=5 runParallelRegressionRunners \
            "${TMP_DIR}/xhttp-edit-${BASHPID:-$$}" \
            xhttp-preset runDockerXhttpPresetRegression \
            xhttp-padding runDockerXhttpPaddingRegression \
            xhttp-headers runDockerXhttpHeadersRegression \
            xhttp-limits runDockerXhttpLimitsRegression \
            xhttp-download runDockerXhttpDownloadRegression
}

runDockerXhttpPresetRegression() {
    PADM_DOCKER_XHTTP_SCOPE=edit-preset bash "${PROJECT_ROOT}/docker/tests/xhttp.sh"
}

runDockerXhttpPaddingRegression() {
    PADM_DOCKER_XHTTP_SCOPE=edit-padding bash "${PROJECT_ROOT}/docker/tests/xhttp.sh"
}

runDockerXhttpHeadersRegression() {
    PADM_DOCKER_XHTTP_SCOPE=edit-headers bash "${PROJECT_ROOT}/docker/tests/xhttp.sh"
}

runDockerXhttpLimitsRegression() {
    PADM_DOCKER_XHTTP_SCOPE=edit-limits bash "${PROJECT_ROOT}/docker/tests/xhttp.sh"
}

runDockerXhttpDownloadRegression() {
    PADM_DOCKER_XHTTP_SCOPE=edit-download bash "${PROJECT_ROOT}/docker/tests/xhttp.sh"
}

runDockerXhttpRollbackRegression() {
    PADM_DOCKER_XHTTP_SCOPE=rollback runDockerXhttpRegression
}

runDockerTraditionalTlsBaseRegression() {
    if [[ "${PADM_DOCKER_CONTRACTS_SHARED_CHECKS:-0}" != 1 ]]; then
        PADM_DOCKER_TRADITIONAL_TLS_SCOPE=base runDockerTraditionalTlsRegression
        return
    fi
    PADM_REGRESSION_PARALLEL_JOBS=3 runParallelRegressionRunners \
        "${TMP_DIR}/traditional-tls-base-${BASHPID:-$$}" \
        tls-hy2-anytls runDockerTraditionalTlsHy2AnyTlsRegression \
        tls-naive-shadowsocks runDockerTraditionalTlsNaiveShadowsocksRegression \
        tls-tuic-trojan runDockerTraditionalTlsTuicTrojanRegression
}

runDockerTraditionalTlsHy2AnyTlsRegression() {
    PADM_DOCKER_TRADITIONAL_TLS_SCOPE=base \
        PADM_DOCKER_TRADITIONAL_TLS_BASE_GROUP=hy2-anytls runDockerTraditionalTlsRegression
}

runDockerTraditionalTlsNaiveShadowsocksRegression() {
    PADM_DOCKER_TRADITIONAL_TLS_SCOPE=base \
        PADM_DOCKER_TRADITIONAL_TLS_BASE_GROUP=naive-shadowsocks runDockerTraditionalTlsRegression
}

runDockerTraditionalTlsTuicTrojanRegression() {
    PADM_DOCKER_TRADITIONAL_TLS_SCOPE=base \
        PADM_DOCKER_TRADITIONAL_TLS_BASE_GROUP=tuic-trojan runDockerTraditionalTlsRegression
}

runDockerTraditionalTlsTransportsRegression() {
    PADM_DOCKER_TRADITIONAL_TLS_SCOPE=transports runDockerTraditionalTlsRegression
}

runDockerSetupTransportsRegression() {
    if [[ "${PADM_DOCKER_CONTRACTS_SHARED_CHECKS:-0}" != 1 ]]; then
        runDockerSetupRegression transports
        return
    fi
    PADM_REGRESSION_PARALLEL_JOBS=3 runParallelRegressionRunners \
        "${TMP_DIR}/setup-transports-${BASHPID:-$$}" \
        setup-ws-vmess runDockerSetupWsVmessRegression \
        setup-trojan runDockerSetupTrojanRegression \
        setup-httpupgrade runDockerSetupHttpupgradeRegression
}

runDockerSetupWsVmessRegression() {
    PADM_DOCKER_SETUP_TRANSPORT_GROUP=ws-vmess runDockerSetupRegression transports
}

runDockerSetupTrojanRegression() {
    PADM_DOCKER_SETUP_TRANSPORT_GROUP=trojan runDockerSetupRegression transports
}

runDockerSetupHttpupgradeRegression() {
    PADM_DOCKER_SETUP_TRANSPORT_GROUP=httpupgrade runDockerSetupRegression transports
}

runDockerXhttpRealRegression() {
    bash -n "${PROJECT_ROOT}/docker/tests/xhttp-real.sh"
    shellcheck --severity=error "${PROJECT_ROOT}/docker/tests/xhttp-real.sh"
    python3 - "${PROJECT_ROOT}/docker/tests/xhttp-headers-real.py" <<'PY'
import ast
from pathlib import Path
import sys

source = Path(sys.argv[1])
ast.parse(source.read_text(), filename=str(source))
PY
    bash "${PROJECT_ROOT}/docker/tests/xhttp-real.sh"
}

runDockerHy2SitesRealRegression() {
    local file
    for file in hysteria2-real hy2-sites-real; do
        bash -n "${PROJECT_ROOT}/docker/tests/${file}.sh"
    done
    shellcheck --severity=error "${PROJECT_ROOT}/docker/tests/"{hysteria2-real,hy2-sites-real}.sh
    bash "${PROJECT_ROOT}/docker/tests/hy2-sites-real.sh"
}

runDockerEntryPortAliasRealRegression() {
    bash "${PROJECT_ROOT}/docker/tests/entry-port-alias-real.sh"
}

runDockerRoutingBlockBtRegression() {
    PADM_DOCKER_ROUTING_SCOPE=bt bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingRegionRegression() {
    PADM_DOCKER_ROUTING_SCOPE=region bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingDomainsWorkflowRegression() {
    PADM_DOCKER_ROUTING_SCOPE=domains-workflow bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingCoreWorkflowRegression() {
    PADM_DOCKER_ROUTING_SCOPE=core-workflow bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingCoreContractsRegression() {
    PADM_DOCKER_ROUTING_SCOPE=core-contracts bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingCoreLifecycleRegression() {
    PADM_DOCKER_ROUTING_SCOPE=core-lifecycle bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingCoreNetworkLifecycleRegression() {
    PADM_REGRESSION_PARALLEL_JOBS=2 runParallelRegressionRunners \
        "${TMP_DIR}/routing-network-${BASHPID:-$$}" \
        routing-warp runDockerRoutingWarpLifecycleRegression \
        routing-ipv6 runDockerRoutingIpv6LifecycleRegression
}

runDockerRoutingCorePolicyLifecycleRegression() {
    PADM_REGRESSION_PARALLEL_JOBS=3 runParallelRegressionRunners \
        "${TMP_DIR}/routing-policy-${BASHPID:-$$}" \
        routing-region runDockerRoutingRegionLifecycleRegression \
        routing-bt runDockerRoutingBtLifecycleRegression \
        routing-socks5 runDockerRoutingSocks5LifecycleRegression
}

runDockerRoutingWarpLifecycleRegression() {
    PADM_DOCKER_ROUTING_SCOPE=core-network-lifecycle PADM_DOCKER_ROUTING_BRANCH=warp \
        bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingIpv6LifecycleRegression() {
    PADM_DOCKER_ROUTING_SCOPE=core-network-lifecycle PADM_DOCKER_ROUTING_BRANCH=ipv6 \
        bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingRegionLifecycleRegression() {
    PADM_DOCKER_ROUTING_SCOPE=core-policy-lifecycle PADM_DOCKER_ROUTING_BRANCH=region \
        bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingBtLifecycleRegression() {
    PADM_DOCKER_ROUTING_SCOPE=core-policy-lifecycle PADM_DOCKER_ROUTING_BRANCH=bt \
        bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingSocks5LifecycleRegression() {
    PADM_DOCKER_ROUTING_SCOPE=core-policy-lifecycle PADM_DOCKER_ROUTING_BRANCH=socks5 \
        bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingSocks5InputRegression() {
    PADM_DOCKER_ROUTING_SCOPE=socks5-input bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingWarpInputRegression() {
    PADM_DOCKER_ROUTING_SCOPE=warp-input bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingHostsInputRegression() {
    PADM_DOCKER_ROUTING_SCOPE=hosts-input bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerPhase4MaintenanceRegression() {
    PADM_DOCKER_PHASE4_SCOPE=maintenance bash "${PROJECT_ROOT}/docker/tests/phase4.sh"
}

runDockerPhase3EditRegression() {
    PADM_DOCKER_PHASE3_SCOPE=edit bash "${PROJECT_ROOT}/docker/tests/phase3.sh"
}

runDockerPhase3EntriesRegression() {
    PADM_DOCKER_PHASE3_SCOPE=entries PADM_DOCKER_PHASE3_ENTRIES_BRANCH="${1:-all}" \
        PADM_DOCKER_PHASE3_MANAGEMENT_GROUP="${2:-all}" \
        bash "${PROJECT_ROOT}/docker/tests/phase3.sh"
}

runDockerPhase3EntriesTopologyRegression() {
    runDockerPhase3EntriesRegression topology
}

runDockerPhase3EntriesManagementRegression() {
    runDockerPhase3EntriesRegression management
}

runDockerPhase3EntriesManagementProtocolRegression() {
    runDockerPhase3EntriesRegression management protocol
}

runDockerPhase3EntriesManagementTlsRegression() {
    runDockerPhase3EntriesRegression management tls
}

runDockerPhase3EntriesManagementTlsReinstallRegression() {
    runDockerPhase3EntriesRegression management tls-reinstall
}

runDockerPhase4LifecycleRegression() {
    PADM_REGRESSION_PARALLEL_JOBS=3 runParallelRegressionRunners \
        "${TMP_DIR}/phase4-lifecycle-${BASHPID:-$$}" \
        lifecycle-settings runDockerPhase4SettingsRegression \
        lifecycle-port runDockerPhase4PortRegression \
        lifecycle-recovery runDockerPhase4RecoveryRegression
}

runDockerPhase4SettingsRegression() {
    PADM_DOCKER_PHASE4_SCOPE=lifecycle PADM_DOCKER_PHASE4_BRANCH=settings \
        bash "${PROJECT_ROOT}/docker/tests/phase4.sh"
}

runDockerPhase4PortRegression() {
    PADM_DOCKER_PHASE4_SCOPE=lifecycle PADM_DOCKER_PHASE4_BRANCH=port \
        bash "${PROJECT_ROOT}/docker/tests/phase4.sh"
}

runDockerPhase4RecoveryRegression() {
    PADM_DOCKER_PHASE4_SCOPE=lifecycle PADM_DOCKER_PHASE4_BRANCH=recovery \
        bash "${PROJECT_ROOT}/docker/tests/phase4.sh"
}

runDockerRealityTargetsDirectRegression() {
    PADM_DOCKER_REALITY_TARGETS_SCOPE=direct runDockerRealityTargetsRegression
}

runDockerRealityTargetsSelectionRegression() {
    PADM_DOCKER_REALITY_TARGETS_SCOPE=selection runDockerRealityTargetsRegression
}

runDockerRoutingDnsHostsWorkflowRegression() {
    PADM_REGRESSION_PARALLEL_JOBS=2 runParallelRegressionRunners \
        "${TMP_DIR}/routing-dns-hosts-${BASHPID:-$$}" \
        routing-dns runDockerRoutingDnsWorkflowRegression \
        routing-hosts runDockerRoutingHostsWorkflowRegression
}

runDockerRoutingDnsWorkflowRegression() {
    PADM_DOCKER_ROUTING_SCOPE=domains-dns-hosts PADM_DOCKER_ROUTING_BRANCH=dns \
        bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingHostsWorkflowRegression() {
    PADM_DOCKER_ROUTING_SCOPE=domains-dns-hosts PADM_DOCKER_ROUTING_BRANCH=hosts \
        bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingDirectBlockWorkflowRegression() {
    PADM_DOCKER_ROUTING_SCOPE=domains-direct-block bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingDirectBlockIpWorkflowRegression() {
    PADM_DOCKER_ROUTING_SCOPE=domains-direct-block-ip bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingDirectBlockCsvWorkflowRegression() {
    PADM_DOCKER_ROUTING_SCOPE=domains-direct-block-csv bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingIPv6Regression() {
    PADM_DOCKER_ROUTING_SCOPE=ipv6 bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingIPv6RealRegression() {
    bash "${PROJECT_ROOT}/docker/tests/routing-ipv6-real.sh"
}

runDockerFail2banRealRegression() {
    bash "${PROJECT_ROOT}/docker/tests/fail2ban-isolated-real.sh"
}

runDockerFail2banSourceRealRegression() {
    bash "${PROJECT_ROOT}/docker/tests/fail2ban-source-real.sh"
}

runDockerControlFail2banRealRegression() {
    PYTHONDONTWRITEBYTECODE=1 python3 "${PROJECT_ROOT}/docker/tests/control-fail2ban-real.py"
}

runDockerFail2banOwnershipRegression() {
    bash "${PROJECT_ROOT}/docker/tests/fail2ban-ownership.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/control-fail2ban.sh"
}

runDockerFail2banSourceRegression() {
    bash "${PROJECT_ROOT}/docker/tests/fail2ban-source.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/fail2ban-start.sh"
}

runDockerRoutingWarpRegression() {
    PADM_DOCKER_ROUTING_SCOPE=warp bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingWarpRealRegression() {
    bash "${PROJECT_ROOT}/docker/tests/routing-warp-real.sh"
}

runDockerRoutingSocks5RealRegression() {
    bash "${PROJECT_ROOT}/docker/tests/routing-socks5-real.sh"
}

runDockerRoutingDnsHostsRealRegression() {
    bash "${PROJECT_ROOT}/docker/tests/routing-dns-hosts-real.sh"
}

runDockerRoutingBlockIpsRealRegression() {
    PADM_ROUTING_REAL_SCOPE=ips bash "${PROJECT_ROOT}/docker/tests/routing-dns-hosts-real.sh"
}

runDockerRoutingBlockIpsResolvedRegression() {
    PADM_DOCKER_ROUTING_SCOPE=block-ips-resolved bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
    PADM_DOCKER_MENU_SCOPE=block-ips-resolved bash "${PROJECT_ROOT}/docker/tests/menu.sh"
}

runDockerRoutingBlockIpsResolvedRealRegression() {
    PADM_ROUTING_REAL_SCOPE=ips-resolved bash "${PROJECT_ROOT}/docker/tests/routing-dns-hosts-real.sh"
}

runDockerRoutingBlockIpsResolvedEgressRealRegression() {
    PADM_ROUTING_REAL_SCOPE=ips-resolved bash "${PROJECT_ROOT}/docker/tests/routing-warp-real.sh"
}

runDockerRoutingBlockBtRealRegression() {
    PADM_ROUTING_REAL_SCOPE=bt bash "${PROJECT_ROOT}/docker/tests/routing-dns-hosts-real.sh"
}

runDockerRoutingRegionRealRegression() {
    PADM_ROUTING_REAL_SCOPE=region bash "${PROJECT_ROOT}/docker/tests/routing-dns-hosts-real.sh"
}

runDockerAccountsRegression() {
    bash "${PROJECT_ROOT}/docker/tests/accounts.sh"
}

runDockerAccountsCliRegression() {
    bash "${PROJECT_ROOT}/docker/tests/accounts-cli.sh"
}

runDockerSubscriptionsRegression() {
    bash -n "${PROJECT_ROOT}/docker/tests/subscriptions.sh" &&
        shellcheck --severity=error "${PROJECT_ROOT}/docker/lib/"{bundle,services,setup,subscriptions}.sh \
            "${PROJECT_ROOT}/docker/tests/subscriptions.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/subscriptions.sh"
}

runDockerBusinessRegression() {
    bash "${PROJECT_ROOT}/docker/tests/business.sh"
}

runDockerBackupRegression() {
    local file
    for file in install-docker.sh docker/lib/{bundle,lifecycle,menu}.sh docker/tests/recovery.sh; do
        bash -n "${PROJECT_ROOT}/${file}" || return 1
    done
    shellcheck --severity=error "${PROJECT_ROOT}/docker/lib/"{bundle,lifecycle,menu}.sh \
        "${PROJECT_ROOT}/docker/tests/recovery.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/recovery.sh"
}

listRegressionDockerBackupChildSelectors() {
    printf '%s\n' docker-backup docker-menu docker-phase1
}

listRegressionDockerBundleChildSelectors() {
    printf '%s\n' docker-phase6 docker-phase1 docker-setup-core docker-release
}

runDockerRecoveryPreviewRegression() {
    bash -n "${PROJECT_ROOT}/docker/tests/recovery-preview.sh" &&
        shellcheck --severity=error "${PROJECT_ROOT}/docker/lib/"{lifecycle,services}.sh \
            "${PROJECT_ROOT}/docker/tests/recovery-preview.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/recovery-preview.sh"
}

runDockerRecoveryApplyRegression() {
    bash -n "${PROJECT_ROOT}/docker/tests/recovery-apply.sh" &&
        shellcheck --severity=error "${PROJECT_ROOT}/docker/lib/"{bootstrap,lifecycle,schedule,services}.sh \
            "${PROJECT_ROOT}/docker/tests/recovery-apply.sh" || return 1
    if [[ "${PADM_DOCKER_RECOVERY_SCOPE:-all}" != all ]]; then
        bash "${PROJECT_ROOT}/docker/tests/recovery-apply.sh"
        return
    fi
    PADM_REGRESSION_PARALLEL_JOBS=3 runParallelRegressionRunners \
        "${TMP_DIR}/recovery-apply-${BASHPID:-$$}" \
        recovery-core runDockerRecoveryCoreApplyRegression \
        recovery-atomic runDockerRecoveryAtomicApplyRegression \
        recovery-variants runDockerRecoveryVariantsApplyRegression
}

runDockerRecoveryCoreApplyRegression() {
    PADM_DOCKER_RECOVERY_SCOPE=core bash "${PROJECT_ROOT}/docker/tests/recovery-apply.sh"
}

runDockerRecoveryAtomicApplyRegression() {
    PADM_DOCKER_RECOVERY_SCOPE=atomic bash "${PROJECT_ROOT}/docker/tests/recovery-apply.sh"
}

runDockerRecoveryVariantsApplyRegression() {
    PADM_DOCKER_RECOVERY_SCOPE=variants bash "${PROJECT_ROOT}/docker/tests/recovery-apply.sh"
}

runDockerWireGuardRecoveryApplyRegression() {
    PADM_DOCKER_RECOVERY_SCOPE=wireguard runDockerRecoveryApplyRegression
}

runDockerWebrootRecoveryApplyRegression() {
    PADM_DOCKER_RECOVERY_SCOPE=webroot runDockerRecoveryApplyRegression
}

runDockerAlpnRecoveryApplyRegression() {
    PADM_DOCKER_RECOVERY_SCOPE=alpn runDockerRecoveryApplyRegression
}

runDockerAlpnRecoveryRealRegression() {
    PADM_ACME_RECOVERY_REAL_SCOPE=alpn runDockerAcmeRecoveryRealRegression
}

listRegressionDockerAlpnRecoveryChildSelectors() {
    printf '%s\n' docker-recovery-preview docker-alpn-recovery-apply
}

runDockerControllerRecoveryApplyRegression() {
    PADM_DOCKER_RECOVERY_SCOPE=controller runDockerRecoveryApplyRegression
}

runDockerControllerRecoveryRealRegression() {
    python3 "${PROJECT_ROOT}/docker/tests/control-two-deployment-real.py" --controller-recovery-only
}

listRegressionDockerControllerRecoveryChildSelectors() {
    printf '%s\n' docker-backup docker-menu-maintenance docker-controller-recovery-apply
}

runDockerWebrootRecoveryRealRegression() {
    PADM_ACME_RECOVERY_REAL_SCOPE=webroot runDockerAcmeRecoveryRealRegression
}

listRegressionDockerWebrootRecoveryChildSelectors() {
    printf '%s\n' docker-backup docker-recovery-preview docker-webroot-recovery-apply
}

listRegressionDockerRecoveryChildSelectors() {
    printf '%s\n' docker-recovery-apply docker-recovery-preview docker-backup docker-business regression-dispatcher-contract
}

runDockerSitesRegression() {
    bash "${PROJECT_ROOT}/docker/tests/sites.sh"
}

runDockerGeoRegression() {
    bash "${PROJECT_ROOT}/docker/tests/geo.sh"
}

runDockerControlApiRegression() {
    PYTHONDONTWRITEBYTECODE=1 python3 "${PROJECT_ROOT}/docker/tests/control.py"
}

runDockerControlSyncRegression() {
    bash "${PROJECT_ROOT}/docker/tests/control-sync.sh"
}

runDockerControlClientRegression() {
    PYTHONDONTWRITEBYTECODE=1 python3 "${PROJECT_ROOT}/docker/tests/control-client.py" &&
        bash "${PROJECT_ROOT}/docker/tests/control-join.sh" &&
        runDockerControlSyncScheduleRegression &&
        PADM_DOCKER_MENU_SCOPE=control runDockerMenuRegression
}

runDockerControlSyncScheduleRegression() {
    bash "${PROJECT_ROOT}/docker/tests/control-sync-schedule.sh"
}

runDockerControlTwoNodeRealRegression() {
    PYTHONDONTWRITEBYTECODE=1 python3 "${PROJECT_ROOT}/docker/tests/control-two-node-real.py"
}

runDockerControlTwoDeploymentRealRegression() {
    PYTHONDONTWRITEBYTECODE=1 python3 "${PROJECT_ROOT}/docker/tests/control-two-deployment-real.py"
}

runDockerControlRemapRealRegression() {
    PYTHONDONTWRITEBYTECODE=1 python3 "${PROJECT_ROOT}/docker/tests/control-two-deployment-real.py" --remap-only
}

runDockerControlRebindRealRegression() {
    PYTHONDONTWRITEBYTECODE=1 python3 "${PROJECT_ROOT}/docker/tests/control-two-deployment-real.py" --rebind-only
}

runDockerControlLogCronRealRegression() {
    PYTHONDONTWRITEBYTECODE=1 python3 "${PROJECT_ROOT}/docker/tests/control-two-deployment-real.py" --log-schedule-cron-only
}

runDockerWireGuardCliRealRegression() {
    PYTHONDONTWRITEBYTECODE=1 python3 "${PROJECT_ROOT}/docker/tests/control-two-deployment-real.py" --wireguard-only
}

runDockerWireGuardPeersRealRegression() {
    PYTHONDONTWRITEBYTECODE=1 python3 "${PROJECT_ROOT}/docker/tests/control-two-deployment-real.py" --wireguard-peers-only
}

runDockerControlPeersRealRegression() {
    PYTHONDONTWRITEBYTECODE=1 python3 "${PROJECT_ROOT}/docker/tests/control-two-deployment-real.py" --control-peers-only
}

runDockerWireGuardControlRealRegression() {
    PYTHONDONTWRITEBYTECODE=1 python3 "${PROJECT_ROOT}/docker/tests/control-two-deployment-real.py" --wireguard-control-only
}

runDockerWireGuardAddressRealRegression() {
    PYTHONDONTWRITEBYTECODE=1 python3 "${PROJECT_ROOT}/docker/tests/control-two-deployment-real.py" --wireguard-address-only
}

runDockerWireGuardRecoveryRealRegression() {
    PYTHONDONTWRITEBYTECODE=1 python3 "${PROJECT_ROOT}/docker/tests/control-two-deployment-real.py" --wireguard-recovery-only
}

runDockerControlStateRegression() {
    bash "${PROJECT_ROOT}/docker/tests/fail2ban-metadata.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/control-state.sh"
}

runDockerControlCliRegression() {
    bash "${PROJECT_ROOT}/docker/tests/control-cli.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/control-invite.sh" &&
        runDockerControlLogScheduleRegression
}

runDockerControlMenuRegression() {
    PADM_DOCKER_MENU_SCOPE=control runDockerMenuRegression
}

runDockerControlLogScheduleRegression() {
    bash "${PROJECT_ROOT}/docker/tests/control-log-schedule.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/control-log-lifecycle.sh"
}

runDockerSshPreflightRegression() {
    bash "${PROJECT_ROOT}/docker/tests/ssh-preflight.sh" &&
        python3 -B "${PROJECT_ROOT}/docker/tests/ssh-source.py" &&
        python3 -B "${PROJECT_ROOT}/docker/tests/ssh-journal.py" &&
        python3 -B "${PROJECT_ROOT}/docker/tests/ssh-ledger.py" &&
        python3 -B "${PROJECT_ROOT}/docker/tests/ssh-collector.py" &&
        python3 -B "${PROJECT_ROOT}/docker/tests/ssh-runtime.py" &&
        bash "${PROJECT_ROOT}/docker/tests/ssh-fail2ban.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/ssh-menu.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/ssh-start.sh" &&
        python3 -B "${PROJECT_ROOT}/docker/tests/ssh-source-client.py"
}

runDockerSshDriverRegression() {
    python3 -B "${PROJECT_ROOT}/docker/tests/ssh-driver.py"
}

runDockerWireGuardConfigRegression() {
    python3 -B "${PROJECT_ROOT}/docker/tests/wireguard-config.py"
}

runDockerWireGuardRuntimeRegression() {
    bash -n "${PROJECT_ROOT}/docker/lib/wireguard.sh" \
        "${PROJECT_ROOT}/docker/tests/"wireguard-{cli,management,menu,migration}.sh &&
        shellcheck --severity=error "${PROJECT_ROOT}/docker/lib/wireguard.sh" \
            "${PROJECT_ROOT}/docker/tests/"wireguard-{cli,management,menu,migration}.sh &&
        bash "${PROJECT_ROOT}/docker/tests/wireguard-management.sh" &&
        runDockerWireGuardMigrationRegression &&
        bash "${PROJECT_ROOT}/docker/tests/wireguard-runtime.sh"
}

runDockerWireGuardMigrationRegression() {
    bash -n "${PROJECT_ROOT}/docker/lib/"{control,lifecycle,services}.sh &&
        python3 -B "${PROJECT_ROOT}/docker/tests/wireguard-config.py" &&
        bash "${PROJECT_ROOT}/docker/tests/wireguard-cli.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/wireguard-migration.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/wireguard-menu.sh"
}

runDockerTProxyOwnershipRegression() {
    bash "${PROJECT_ROOT}/docker/tests/tproxy-ownership.sh" &&
        runDockerTProxyManagementRegression
}

runDockerRedirectOwnershipRegression() {
    bash -n "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" \
        "${PROJECT_ROOT}/docker/tests/redirect-ownership.sh" \
        "${PROJECT_ROOT}/docker/tests/redirect-real.sh" \
        "${PROJECT_ROOT}/docker/tests/redirect-management.sh" &&
        shellcheck --severity=error "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" \
            "${PROJECT_ROOT}/docker/lib/setup.sh" "${PROJECT_ROOT}/docker/lib/menu.sh" \
            "${PROJECT_ROOT}/docker/lib/services.sh" "${PROJECT_ROOT}/docker/lib/lifecycle.sh" \
            "${PROJECT_ROOT}/docker/tests/redirect-ownership.sh" \
            "${PROJECT_ROOT}/docker/tests/redirect-management.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/redirect-ownership.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/redirect-management.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/redirect-menu.sh"
}

runDockerRedirectRealRegression() {
    PADM_NET_REAL_CASE=redirect bash "${PROJECT_ROOT}/docker/tests/fail2ban-isolated-real.sh"
}

runDockerPortHoppingPreflightRegression() {
    runRegressionStep hopping-read-only python3 "${PROJECT_ROOT}/docker/tests/port-hopping-preflight.py" &&
        PADM_REGRESSION_PARALLEL_JOBS=4 runParallelRegressionRunners \
            "${TMP_DIR}/hopping-preflight-${BASHPID:-$$}" \
            hopping-target runDockerPortHoppingTargetRegression \
            hopping-guarded runDockerPortHoppingGuardedRegression \
            hopping-config runDockerPortHoppingConfigRegression \
            hopping-ownership runDockerPortHoppingOwnershipRegression \
            hopping-probe runDockerPortHoppingProbeRegression
}

runDockerPortHoppingConfigRegression() {
    shellcheck --severity=error "${PROJECT_ROOT}/docker/lib/menu.sh" \
        "${PROJECT_ROOT}/docker/lib/setup.sh" "${PROJECT_ROOT}/docker/lib/bundle.sh" \
        "${PROJECT_ROOT}/docker/lib/services.sh" "${PROJECT_ROOT}/docker/lib/lifecycle.sh" \
        "${PROJECT_ROOT}/docker/tests/port-hopping-config.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/port-hopping-config.sh"
}

runDockerPortHoppingOwnershipRegression() {
    python3 "${PROJECT_ROOT}/docker/tests/port-hopping-ownership.py"
}

runDockerPortHoppingGuardedRegression() {
    sh -n "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" &&
        bash -n "${PROJECT_ROOT}/docker/lib/lifecycle.sh" &&
        shellcheck --severity=error "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" &&
        shellcheck --severity=error "${PROJECT_ROOT}/docker/lib/lifecycle.sh" &&
        python3 - "${PROJECT_ROOT}/docker/lib/port-hopping-probe.py" \
            "${PROJECT_ROOT}/docker/lib/port-hopping-supervisor.py" <<'PY' &&
import ast
from pathlib import Path
import sys
for path in sys.argv[1:]:
    ast.parse(Path(path).read_text(), filename=path)
PY
        runRegressionStep hopping-guarded-cases python3 "${PROJECT_ROOT}/docker/tests/port-hopping-guarded.py" &&
        PADM_REGRESSION_PARALLEL_JOBS=2 runParallelRegressionRunners \
            "${TMP_DIR}/hopping-parent-${BASHPID:-$$}" \
            hopping-finite-parent runDockerPortHoppingGuardedParentRegression \
            hopping-supervised-parent runDockerPortHoppingSupervisedParentRegression \
            hopping-supervisor-parent runDockerPortHoppingSupervisorParentRegression
}

runDockerPortHoppingGuardedParentRegression() {
    python3 "${PROJECT_ROOT}/docker/tests/port-hopping-guarded-parent.py"
}

runDockerPortHoppingSupervisedParentRegression() {
    python3 "${PROJECT_ROOT}/docker/tests/port-hopping-supervised-parent.py"
}

runDockerPortHoppingSupervisorParentRegression() {
    python3 "${PROJECT_ROOT}/docker/tests/port-hopping-supervisor-parent.py"
}

runDockerPortHoppingProbeRegression() {
    bash -n "${PROJECT_ROOT}/docker/lib/lifecycle.sh" &&
        shellcheck --severity=error "${PROJECT_ROOT}/docker/lib/lifecycle.sh" &&
        runRegressionStep hopping-probe-cases python3 "${PROJECT_ROOT}/docker/tests/port-hopping-probe.py" &&
        runRegressionStep hopping-handshake python3 "${PROJECT_ROOT}/docker/tests/port-hopping-handshake.py"
}

runDockerPortHoppingTargetRegression() {
    bash -n "${PROJECT_ROOT}/docker/lib/services.sh" &&
        bash -n "${PROJECT_ROOT}/docker/lib/lifecycle.sh" &&
        bash -n "${PROJECT_ROOT}/docker/tests/port-hopping-target.sh" &&
        bash -n "${PROJECT_ROOT}/docker/tests/port-hopping-start.sh" &&
        bash -n "${PROJECT_ROOT}/docker/tests/port-hopping-target-real.sh" &&
        shellcheck --severity=error "${PROJECT_ROOT}/docker/lib/services.sh" \
            "${PROJECT_ROOT}/docker/lib/lifecycle.sh" \
            "${PROJECT_ROOT}/docker/tests/port-hopping-target.sh" \
            "${PROJECT_ROOT}/docker/tests/port-hopping-start.sh" \
            "${PROJECT_ROOT}/docker/tests/port-hopping-target-real.sh" &&
        python3 - "${PROJECT_ROOT}/docker/tests/port-hopping-target-real.py" <<'PY' || return 1
import ast
from pathlib import Path
import sys

path = Path(sys.argv[1])
ast.parse(path.read_text(), filename=str(path))
PY
    PADM_REGRESSION_PARALLEL_JOBS=2 runParallelRegressionRunners \
        "${TMP_DIR}/hopping-target-${BASHPID:-$$}" \
        hopping-target-cases runDockerPortHoppingTargetCasesRegression \
        hopping-start runDockerPortHoppingStartRegression
}

runDockerPortHoppingTargetCasesRegression() {
    bash "${PROJECT_ROOT}/docker/tests/port-hopping-target.sh"
}

runDockerPortHoppingStartRegression() {
    bash "${PROJECT_ROOT}/docker/tests/port-hopping-start.sh"
}

runDockerPortHoppingTargetRealRegression() {
    bash "${PROJECT_ROOT}/docker/tests/port-hopping-target-real.sh"
}

runDockerTProxyRealRegression() {
    PADM_NET_REAL_CASE=tproxy bash "${PROJECT_ROOT}/docker/tests/fail2ban-isolated-real.sh"
}

runDockerTunRealRegression() {
    PADM_NET_REAL_CASE=tun bash "${PROJECT_ROOT}/docker/tests/fail2ban-isolated-real.sh"
}

runDockerTProxyManagementRegression() {
    bash -n "${PROJECT_ROOT}/docker/lib/setup.sh" "${PROJECT_ROOT}/docker/lib/menu.sh" \
        "${PROJECT_ROOT}/docker/lib/services.sh" "${PROJECT_ROOT}/docker/lib/lifecycle.sh" &&
        shellcheck --severity=error "${PROJECT_ROOT}/docker/lib/setup.sh" "${PROJECT_ROOT}/docker/lib/menu.sh" \
            "${PROJECT_ROOT}/docker/lib/services.sh" "${PROJECT_ROOT}/docker/lib/lifecycle.sh" \
            "${PROJECT_ROOT}/docker/tests/tproxy-management.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/tproxy-management.sh"
}

runDockerTunManagementRegression() {
    bash -n "${PROJECT_ROOT}/docker/lib/setup.sh" "${PROJECT_ROOT}/docker/lib/menu.sh" \
        "${PROJECT_ROOT}/docker/lib/services.sh" "${PROJECT_ROOT}/docker/lib/lifecycle.sh" \
        "${PROJECT_ROOT}/docker/tests/tun-management.sh" &&
        shellcheck --severity=error "${PROJECT_ROOT}/docker/lib/setup.sh" "${PROJECT_ROOT}/docker/lib/menu.sh" \
            "${PROJECT_ROOT}/docker/lib/services.sh" "${PROJECT_ROOT}/docker/lib/lifecycle.sh" \
            "${PROJECT_ROOT}/docker/tests/tun-management.sh" &&
        runDockerTunResourcesRegression &&
        bash "${PROJECT_ROOT}/docker/tests/tun-management.sh"
}

runDockerTunResourcesRegression() {
    bash "${PROJECT_ROOT}/docker/tests/tun-resources.sh"
}

registerRegressionFunctionLeaf install-module-manifest runInstallModuleManifestCompleteRegression
registerRegressionFunctionLeaf static-sites runStaticSitesRegression
registerRegressionFunctionLeaf fast-only-safety runRegressionFastOnlySafety
registerRegressionFunctionLeaf fast-only-output-auto-install runRegressionFastOnlyOutputAutoInstall
registerRegressionFunctionLeaf fast-only-output-rest runRegressionFastOnlyOutputRest
registerRegressionFunctionLeaf fast-only-compatibility runSingBox114CompatibilityAuditRegression
registerRegressionFunctionLeaf fast-smoke runRegressionFastSmoke
registerRegressionFunctionLeaf update-padm-signal-rollback runUpdatePadmSignalRollbackRegression
registerRegressionFunctionLeaf install-sync-signal-rollback runInstallSyncSignalRollbackRegression
registerRegressionFunctionLeaf docker-phase1 runDockerPhase1Regression
registerRegressionFunctionLeaf docker-menu runDockerMenuRegression
registerRegressionFunctionLeaf docker-menu-routing runDockerMenuRoutingRegression
registerRegressionFunctionLeaf docker-menu-port-alias runDockerMenuPortAliasRegression
registerRegressionFunctionLeaf docker-menu-tun runDockerMenuTunRegression
registerRegressionFunctionLeaf docker-menu-xhttp runDockerMenuXhttpRegression
registerRegressionFunctionLeaf docker-menu-maintenance runDockerMenuMaintenanceRegression
registerRegressionFunctionLeaf docker-release runDockerReleaseRegression
registerRegressionFunctionLeaf docker-setup runDockerSetupRegression
registerRegressionFunctionLeaf docker-setup-core runDockerSetupRegression core
registerRegressionFunctionLeaf docker-setup-encrypted runDockerSetupRegression encrypted
registerRegressionFunctionLeaf docker-setup-encrypted-udp runDockerSetupRegression encrypted-udp
registerRegressionFunctionLeaf docker-setup-encrypted-tcp runDockerSetupRegression encrypted-tcp
registerRegressionFunctionLeaf docker-setup-transports runDockerSetupTransportsRegression
registerRegressionFunctionLeaf docker-setup-tls runDockerSetupRegression tls
registerRegressionFunctionLeaf docker-protocol runDockerProtocolRegression
registerRegressionFunctionLeaf docker-reality runDockerRealityRegression
registerRegressionFunctionLeaf docker-reality-parameters runDockerRealityParametersRegression
registerRegressionFunctionLeaf docker-vless-encryption runDockerVlessEncryptionRegression
registerRegressionFunctionLeaf docker-vless-encryption-real runDockerVlessEncryptionRealRegression
registerRegressionFunctionLeaf docker-reality-targets runDockerRealityTargetsRegression
registerRegressionFunctionLeaf docker-reality-targets-direct runDockerRealityTargetsDirectRegression
registerRegressionFunctionLeaf docker-reality-targets-selection runDockerRealityTargetsSelectionRegression
registerRegressionFunctionLeaf docker-reality-target-library runDockerRealityTargetLibraryRegression
registerRegressionFunctionLeaf docker-hysteria2 runDockerHysteria2Regression
registerRegressionFunctionLeaf docker-anytls runDockerAnyTlsRegression
registerRegressionFunctionLeaf docker-naive runDockerNaiveRegression
registerRegressionFunctionLeaf docker-shadowsocks runDockerShadowsocksRegression
registerRegressionFunctionLeaf docker-shadowsocks-rotation runDockerShadowsocksRotationRegression
registerRegressionFunctionLeaf docker-shadowsocks-real runDockerShadowsocksRealRegression
registerRegressionFunctionLeaf docker-tuic runDockerTuicRegression
registerRegressionFunctionLeaf docker-trojan runDockerTrojanRegression
registerRegressionFunctionLeaf docker-vmess runDockerVmessRegression
registerRegressionFunctionLeaf docker-httpupgrade runDockerHttpupgradeRegression
registerRegressionFunctionLeaf docker-grpc-tls runDockerGrpcTlsRegression
registerRegressionFunctionLeaf docker-traditional-tls runDockerTraditionalTlsRegression
registerRegressionFunctionLeaf docker-traditional-tls-base runDockerTraditionalTlsBaseRegression
registerRegressionFunctionLeaf docker-traditional-tls-transports runDockerTraditionalTlsTransportsRegression
registerRegressionFunctionLeaf docker-permissions runDockerPermissionsRegression
registerRegressionFunctionLeaf docker-tls runDockerTlsRegression
registerRegressionFunctionLeaf docker-renewal runDockerRenewalRegression
registerRegressionFunctionLeaf docker-phase2 runDockerPhase2Regression
registerRegressionFunctionLeaf docker-phase3 runDockerPhase3Regression
registerRegressionFunctionLeaf docker-phase3-edit runDockerPhase3EditRegression
registerRegressionFunctionLeaf docker-phase3-entries-topology runDockerPhase3EntriesTopologyRegression
registerRegressionFunctionLeaf docker-phase3-entries-management runDockerPhase3EntriesManagementRegression
registerRegressionFunctionLeaf docker-phase3-entries-management-protocol runDockerPhase3EntriesManagementProtocolRegression
registerRegressionFunctionLeaf docker-phase3-entries-management-tls runDockerPhase3EntriesManagementTlsRegression
registerRegressionFunctionLeaf docker-phase3-entries-management-tls-reinstall runDockerPhase3EntriesManagementTlsReinstallRegression
registerRegressionFunctionLeaf docker-phase4 runDockerPhase4Regression
registerRegressionFunctionLeaf docker-fail2ban-real runDockerFail2banRealRegression
registerRegressionFunctionLeaf docker-fail2ban-source-real runDockerFail2banSourceRealRegression
registerRegressionFunctionLeaf docker-control-fail2ban-real runDockerControlFail2banRealRegression
registerRegressionFunctionLeaf docker-fail2ban-ownership runDockerFail2banOwnershipRegression
registerRegressionFunctionLeaf docker-fail2ban-source runDockerFail2banSourceRegression
registerRegressionFunctionLeaf docker-ssh-preflight runDockerSshPreflightRegression
registerRegressionFunctionLeaf docker-ssh-driver runDockerSshDriverRegression
registerRegressionFunctionLeaf docker-phase5 runDockerPhase5Regression
registerRegressionFunctionLeaf docker-phase6 runDockerPhase6Regression
registerRegressionFunctionLeaf docker-traffic runDockerTrafficRegression
registerRegressionFunctionLeaf docker-routing-socks5 runDockerRoutingSocks5Regression
registerRegressionFunctionLeaf docker-routing-socks5-input runDockerRoutingSocks5InputRegression
registerRegressionFunctionLeaf docker-routing-socks5-real runDockerRoutingSocks5RealRegression
registerRegressionFunctionLeaf docker-http-relay runDockerHttpRelayRegression
registerRegressionFunctionLeaf docker-http-relay-real runDockerHttpRelayRealRegression
registerRegressionFunctionLeaf docker-http-relay-published-real runDockerHttpRelayPublishedRealRegression
registerRegressionFunctionLeaf docker-entry-port-alias runDockerEntryPortAliasRegression
registerRegressionFunctionLeaf docker-cdn-entries runDockerCdnEntriesRegression
registerRegressionFunctionLeaf docker-cdn-entries-real runDockerCdnEntriesRealRegression
registerRegressionFunctionLeaf docker-alpn-real runDockerAlpnRealRegression
registerRegressionFunctionLeaf docker-xhttp runDockerXhttpRegression
registerRegressionFunctionLeaf docker-xhttp-validation runDockerXhttpValidationRegression
registerRegressionFunctionLeaf docker-xhttp-edit runDockerXhttpEditRegression
registerRegressionFunctionLeaf docker-xhttp-headers runDockerXhttpHeadersRegression
registerRegressionFunctionLeaf docker-xhttp-limits runDockerXhttpLimitsRegression
registerRegressionFunctionLeaf docker-xhttp-download runDockerXhttpDownloadRegression
registerRegressionFunctionLeaf docker-xhttp-rollback runDockerXhttpRollbackRegression
registerRegressionFunctionLeaf docker-xhttp-real runDockerXhttpRealRegression
registerRegressionFunctionLeaf docker-hy2-sites-real runDockerHy2SitesRealRegression
registerRegressionFunctionLeaf docker-entry-port-alias-real runDockerEntryPortAliasRealRegression
registerRegressionFunctionLeaf docker-routing-dns-hosts runDockerRoutingSocks5Regression
registerRegressionFunctionLeaf docker-routing-dns-hosts-real runDockerRoutingDnsHostsRealRegression
registerRegressionFunctionLeaf docker-routing-direct-block runDockerRoutingSocks5Regression
registerRegressionFunctionLeaf docker-routing-direct-block-real runDockerRoutingDnsHostsRealRegression
registerRegressionFunctionLeaf docker-routing-block-ips runDockerRoutingSocks5Regression
registerRegressionFunctionLeaf docker-routing-block-ips-real runDockerRoutingBlockIpsRealRegression
registerRegressionFunctionLeaf docker-routing-block-ips-resolved runDockerRoutingBlockIpsResolvedRegression
registerRegressionFunctionLeaf docker-routing-block-ips-resolved-real runDockerRoutingBlockIpsResolvedRealRegression
registerRegressionFunctionLeaf docker-routing-block-ips-resolved-egress-real runDockerRoutingBlockIpsResolvedEgressRealRegression
registerRegressionFunctionLeaf docker-routing-block-bt runDockerRoutingBlockBtRegression
registerRegressionFunctionLeaf docker-routing-block-bt-real runDockerRoutingBlockBtRealRegression
registerRegressionFunctionLeaf docker-routing-region runDockerRoutingRegionRegression
registerRegressionFunctionLeaf docker-routing-region-real runDockerRoutingRegionRealRegression
registerRegressionFunctionLeaf docker-routing-domains-workflow runDockerRoutingDomainsWorkflowRegression
registerRegressionFunctionLeaf docker-routing-core-workflow runDockerRoutingCoreWorkflowRegression
registerRegressionFunctionLeaf docker-routing-core-contracts runDockerRoutingCoreContractsRegression
registerRegressionFunctionLeaf docker-routing-core-lifecycle runDockerRoutingCoreLifecycleRegression
registerRegressionFunctionLeaf docker-routing-core-network-lifecycle runDockerRoutingCoreNetworkLifecycleRegression
registerRegressionFunctionLeaf docker-routing-core-policy-lifecycle runDockerRoutingCorePolicyLifecycleRegression
registerRegressionFunctionLeaf docker-phase4-maintenance runDockerPhase4MaintenanceRegression
registerRegressionFunctionLeaf docker-phase4-lifecycle runDockerPhase4LifecycleRegression
registerRegressionFunctionLeaf docker-routing-dns-hosts-workflow runDockerRoutingDnsHostsWorkflowRegression
registerRegressionFunctionLeaf docker-routing-direct-block-workflow runDockerRoutingDirectBlockWorkflowRegression
registerRegressionFunctionLeaf docker-routing-direct-block-ip-workflow runDockerRoutingDirectBlockIpWorkflowRegression
registerRegressionFunctionLeaf docker-routing-direct-block-csv-workflow runDockerRoutingDirectBlockCsvWorkflowRegression
registerRegressionFunctionLeaf docker-routing-ipv6 runDockerRoutingIPv6Regression
registerRegressionFunctionLeaf docker-routing-ipv6-real runDockerRoutingIPv6RealRegression
registerRegressionFunctionLeaf docker-routing-warp runDockerRoutingWarpRegression
registerRegressionFunctionLeaf docker-routing-warp-input runDockerRoutingWarpInputRegression
registerRegressionFunctionLeaf docker-routing-hosts-input runDockerRoutingHostsInputRegression
registerRegressionFunctionLeaf docker-routing-warp-real runDockerRoutingWarpRealRegression
registerRegressionFunctionLeaf docker-accounts runDockerAccountsRegression
registerRegressionFunctionLeaf docker-accounts-cli runDockerAccountsCliRegression
registerRegressionFunctionLeaf docker-subscriptions runDockerSubscriptionsRegression
registerRegressionFunctionLeaf docker-subscription-publication-real runDockerSubscriptionPublicationRealRegression
registerRegressionFunctionLeaf docker-subscription-site-real runDockerSubscriptionSiteRealRegression
registerRegressionFunctionLeaf docker-acme-recovery-real runDockerAcmeRecoveryRealRegression
registerRegressionFunctionLeaf docker-webroot-recovery-real runDockerWebrootRecoveryRealRegression
registerRegressionFunctionLeaf docker-business runDockerBusinessRegression
registerRegressionFunctionLeaf docker-backup runDockerBackupRegression
registerRegressionFunctionLeaf docker-recovery-preview runDockerRecoveryPreviewRegression
registerRegressionFunctionLeaf docker-recovery-apply runDockerRecoveryApplyRegression
registerRegressionFunctionLeaf docker-wireguard-recovery-apply runDockerWireGuardRecoveryApplyRegression
registerRegressionFunctionLeaf docker-webroot-recovery-apply runDockerWebrootRecoveryApplyRegression
registerRegressionFunctionLeaf docker-alpn-recovery-apply runDockerAlpnRecoveryApplyRegression
registerRegressionFunctionLeaf docker-alpn-recovery-real runDockerAlpnRecoveryRealRegression
registerRegressionParallelSelectorList docker-alpn-recovery-focused runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-alpn-recovery-focused-${BASHPID:-$$}" listRegressionDockerAlpnRecoveryChildSelectors 2
registerRegressionFunctionLeaf docker-controller-recovery-apply runDockerControllerRecoveryApplyRegression
registerRegressionFunctionLeaf docker-controller-recovery-real runDockerControllerRecoveryRealRegression
registerRegressionParallelSelectorList docker-controller-recovery-focused runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-controller-recovery-focused-${BASHPID:-$$}" listRegressionDockerControllerRecoveryChildSelectors 2
registerRegressionParallelSelectorList docker-webroot-recovery-focused runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-webroot-recovery-focused-${BASHPID:-$$}" listRegressionDockerWebrootRecoveryChildSelectors 2
registerRegressionParallelSelectorList docker-recovery-focused runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-recovery-focused-${BASHPID:-$$}" listRegressionDockerRecoveryChildSelectors 2
registerRegressionParallelSelectorList docker-backup-focused runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-backup-focused-${BASHPID:-$$}" listRegressionDockerBackupChildSelectors 2
registerRegressionParallelSelectorList docker-bundle-focused runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-bundle-focused-${BASHPID:-$$}" listRegressionDockerBundleChildSelectors 2
registerRegressionFunctionLeaf docker-sites runDockerSitesRegression
registerRegressionFunctionLeaf docker-geo-data runDockerGeoRegression
registerRegressionFunctionLeaf docker-control-api runDockerControlApiRegression
registerRegressionFunctionLeaf docker-control-sync runDockerControlSyncRegression
registerRegressionFunctionLeaf docker-control-state runDockerControlStateRegression
registerRegressionFunctionLeaf docker-control-cli runDockerControlCliRegression
registerRegressionFunctionLeaf docker-menu-control runDockerControlMenuRegression
registerRegressionFunctionLeaf docker-control-log-schedule runDockerControlLogScheduleRegression
registerRegressionFunctionLeaf docker-control-client runDockerControlClientRegression
registerRegressionFunctionLeaf docker-control-sync-schedule runDockerControlSyncScheduleRegression
registerRegressionFunctionLeaf docker-control-two-node-real runDockerControlTwoNodeRealRegression
registerRegressionFunctionLeaf docker-control-two-deployment-real runDockerControlTwoDeploymentRealRegression
registerRegressionFunctionLeaf docker-control-remap-real runDockerControlRemapRealRegression
registerRegressionFunctionLeaf docker-control-rebind-real runDockerControlRebindRealRegression
registerRegressionFunctionLeaf docker-control-log-cron-real runDockerControlLogCronRealRegression
registerRegressionFunctionLeaf docker-wireguard-config runDockerWireGuardConfigRegression
registerRegressionFunctionLeaf docker-wireguard-runtime runDockerWireGuardRuntimeRegression
registerRegressionFunctionLeaf docker-wireguard-migration-focused runDockerWireGuardMigrationRegression
registerRegressionFunctionLeaf docker-wireguard-cli-real runDockerWireGuardCliRealRegression
registerRegressionFunctionLeaf docker-wireguard-peers-real runDockerWireGuardPeersRealRegression
registerRegressionFunctionLeaf docker-control-peers-real runDockerControlPeersRealRegression
registerRegressionFunctionLeaf docker-wireguard-control-real runDockerWireGuardControlRealRegression
registerRegressionFunctionLeaf docker-wireguard-address-real runDockerWireGuardAddressRealRegression
registerRegressionFunctionLeaf docker-wireguard-recovery-real runDockerWireGuardRecoveryRealRegression
registerRegressionFunctionLeaf docker-tproxy-ownership runDockerTProxyOwnershipRegression
registerRegressionFunctionLeaf docker-redirect-focused runDockerRedirectOwnershipRegression
registerRegressionFunctionLeaf docker-redirect-real runDockerRedirectRealRegression
registerRegressionFunctionLeaf docker-port-hopping-preflight runDockerPortHoppingPreflightRegression
registerRegressionFunctionLeaf docker-port-hopping-probe runDockerPortHoppingProbeRegression
registerRegressionFunctionLeaf docker-port-hopping-guarded runDockerPortHoppingGuardedRegression
registerRegressionFunctionLeaf docker-port-hopping-supervisor runDockerPortHoppingSupervisorParentRegression
registerRegressionFunctionLeaf docker-port-hopping-target runDockerPortHoppingTargetRegression
registerRegressionFunctionLeaf docker-port-hopping-target-real runDockerPortHoppingTargetRealRegression
runDockerPortHoppingChangeRealRegression() {
    PADM_DOCKER_HOPPING_CHANGE_ONLY=1 runDockerPortHoppingTargetRealRegression
}
registerRegressionFunctionLeaf docker-port-hopping-change-real runDockerPortHoppingChangeRealRegression
runDockerPortHoppingAutoRealRegression() {
    PADM_DOCKER_HOPPING_AUTO_ONLY=1 runDockerPortHoppingTargetRealRegression
}
registerRegressionFunctionLeaf docker-port-hopping-auto-real runDockerPortHoppingAutoRealRegression
runDockerPortHoppingTuicRealRegression() {
    PADM_DOCKER_HOPPING_TUIC_ONLY=1 runDockerPortHoppingTargetRealRegression
}
registerRegressionFunctionLeaf docker-port-hopping-tuic-real runDockerPortHoppingTuicRealRegression
runDockerPortHoppingRecoveryRealRegression() {
    PADM_DOCKER_HOPPING_TUIC_ONLY=1 PADM_DOCKER_HOPPING_RECOVERY_ONLY=1 \
        runDockerPortHoppingTargetRealRegression
}
registerRegressionFunctionLeaf docker-port-hopping-recovery-real runDockerPortHoppingRecoveryRealRegression
runDockerPortHoppingShareRealRegression() {
    # 各场景独享 netns、daemon 与数据目录；沿用入口 Jobs，避免串行等待随机跳跃。
    runParallelRegressionRunners "${TMP_DIR}/hopping-share-${BASHPID:-$$}" \
        hy2-salamander runDockerPortHoppingShareSalamanderRealRegression \
        hy2-gecko runDockerPortHoppingShareGeckoRealRegression \
        tuic runDockerPortHoppingShareTuicRealRegression
}
runDockerPortHoppingShareSalamanderRealRegression() {
    PADM_DOCKER_HOPPING_SHARE_ONLY=1 PADM_DOCKER_HOPPING_SHARE_OBFS=salamander \
        unshare --net bash "${PROJECT_ROOT}/docker/tests/port-hopping-target-real.sh"
}
runDockerPortHoppingShareGeckoRealRegression() {
    PADM_DOCKER_HOPPING_SHARE_ONLY=1 PADM_DOCKER_HOPPING_SHARE_OBFS=gecko \
        unshare --net bash "${PROJECT_ROOT}/docker/tests/port-hopping-target-real.sh"
}
runDockerPortHoppingShareTuicRealRegression() {
    PADM_DOCKER_HOPPING_SHARE_ONLY=1 PADM_DOCKER_HOPPING_TUIC_ONLY=1 \
        unshare --net bash "${PROJECT_ROOT}/docker/tests/port-hopping-target-real.sh"
}
registerRegressionFunctionLeaf docker-port-hopping-share-real runDockerPortHoppingShareRealRegression
registerRegressionFunctionLeaf docker-tproxy-real runDockerTProxyRealRegression
registerRegressionFunctionLeaf docker-tun-real runDockerTunRealRegression
registerRegressionFunctionLeaf docker-tproxy-management runDockerTProxyManagementRegression
registerRegressionFunctionLeaf docker-tun-management runDockerTunManagementRegression
registerRegressionFunctionLeaf docker-tun-resources runDockerTunResourcesRegression

listRegressionDockerTunChildSelectors() {
    printf '%s\n' docker-tun-management docker-menu-tun
}
registerRegressionParallelSelectorList docker-tun-focused runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-tun-focused-${BASHPID:-$$}" listRegressionDockerTunChildSelectors 2

listRegressionDockerTProxyChildSelectors() {
    printf '%s\n' docker-tproxy-ownership docker-menu-routing
}
registerRegressionParallelSelectorList docker-tproxy-focused runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-tproxy-focused-${BASHPID:-$$}" listRegressionDockerTProxyChildSelectors 2

listRegressionDockerFail2banChildSelectors() {
    printf '%s\n' docker-fail2ban-ownership docker-phase4
}
registerRegressionParallelSelectorList docker-fail2ban-focused runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-fail2ban-focused-${BASHPID:-$$}" listRegressionDockerFail2banChildSelectors 2

listRegressionDockerWireGuardChildSelectors() {
    printf '%s\n' docker-wireguard-runtime docker-phase4
}
registerRegressionParallelSelectorList docker-wireguard-focused runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-wireguard-focused-${BASHPID:-$$}" listRegressionDockerWireGuardChildSelectors 2

listRegressionDockerControlPeersChildSelectors() {
    printf '%s\n' docker-control-state docker-control-cli docker-wireguard-migration-focused \
        docker-menu-control docker-backup
}
registerRegressionParallelSelectorList docker-control-peers-focused runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-control-peers-focused-${BASHPID:-$$}" listRegressionDockerControlPeersChildSelectors 2

registerRegressionParallelSelectorList docker-tls-focused runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/docker-tls-focused-parallel-${BASHPID:-$$}" listRegressionDockerTlsFocusedChildSelectors
registerRegressionParallelSelectorList docker-core-assessment runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-core-assessment-parallel-${BASHPID:-$$}" listRegressionDockerCoreAssessmentChildSelectors 2
registerRegressionParallelSelectorList docker-geo runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-geo-parallel-${BASHPID:-$$}" listRegressionDockerGeoChildSelectors 2
listRegressionDockerPhase3EntriesChildSelectors() {
    printf '%s\n' docker-phase3-entries-management-tls docker-phase3-entries-management-protocol \
        docker-phase3-entries-management-tls-reinstall \
        docker-phase3-entries-topology
}
registerRegressionParallelSelectorList docker-phase3-entries runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-phase3-entries-${BASHPID:-$$}" listRegressionDockerPhase3EntriesChildSelectors 2
registerRegressionParallelSelectorList docker-contracts runRegressionDockerContracts \
    "${TMP_DIR}/docker-contracts-parallel-${BASHPID:-$$}" listRegressionDockerContractsChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-full runRegressionDockerContracts \
    "${TMP_DIR}/docker-contracts-full-parallel-${BASHPID:-$$}" listRegressionDockerContractsFullChildSelectors 2
registerRegressionParallelSelectorList docker-vless-encryption-focused runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-vless-encryption-parallel-${BASHPID:-$$}" listRegressionDockerVlessEncryptionChildSelectors 2
registerRegressionParallelSelectorList docker-subscription-publication-focused runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-subscription-publication-parallel-${BASHPID:-$$}" listRegressionDockerSubscriptionPublicationChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-fast runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-fast-parallel-${BASHPID:-$$}" listRegressionDockerContractsFastChildSelectors 4
registerRegressionParallelSelectorList docker-contracts-fast-heavy runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-fast-heavy-parallel-${BASHPID:-$$}" listRegressionDockerContractsFastHeavyChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-fast-sites runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-fast-sites-parallel-${BASHPID:-$$}" listRegressionDockerContractsFastSitesChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-fast-rest runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-fast-rest-parallel-${BASHPID:-$$}" listRegressionDockerContractsFastRestChildSelectors 4
registerRegressionParallelSelectorList docker-contracts-recovery runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-recovery-parallel-${BASHPID:-$$}" listRegressionDockerContractsRecoveryChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-routing runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-routing-parallel-${BASHPID:-$$}" listRegressionDockerContractsRoutingChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-protocol runRegressionDockerContracts \
    "${TMP_DIR}/docker-contracts-protocol-parallel-${BASHPID:-$$}" listRegressionDockerContractsProtocolChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-system runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-system-parallel-${BASHPID:-$$}" listRegressionDockerContractsSystemChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-reality runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-reality-parallel-${BASHPID:-$$}" listRegressionDockerContractsRealityChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-reality-metadata runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-reality-metadata-parallel-${BASHPID:-$$}" listRegressionDockerContractsRealityMetadataChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-reality-rotation runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-reality-rotation-parallel-${BASHPID:-$$}" listRegressionDockerContractsRealityRotationChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-setup-basic runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-setup-basic-parallel-${BASHPID:-$$}" listRegressionDockerContractsSetupBasicChildSelectors 3
registerRegressionParallelSelectorList docker-contracts-setup-transports runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-setup-transports-parallel-${BASHPID:-$$}" listRegressionDockerContractsSetupTransportsChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-system-light runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-system-light-parallel-${BASHPID:-$$}" listRegressionDockerContractsSystemLightChildSelectors 3
registerRegressionParallelSelectorList docker-contracts-phase3-tls runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-phase3-tls-${BASHPID:-$$}" listRegressionDockerContractsPhase3TlsChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-phase3-protocol runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-phase3-protocol-${BASHPID:-$$}" listRegressionDockerContractsPhase3ProtocolChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-phase3-topology runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-phase3-topology-${BASHPID:-$$}" listRegressionDockerContractsPhase3TopologyChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-policy runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-policy-${BASHPID:-$$}" listRegressionDockerContractsPolicyChildSelectors 2
registerRegressionParallelSelectorList docker-routing-ip-ownership runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-routing-ip-ownership-${BASHPID:-$$}" listRegressionDockerRoutingIpOwnershipChildSelectors 2
registerRegressionParallelSelectorList docker-routing-core-network runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-routing-core-network-parallel-${BASHPID:-$$}" listRegressionDockerRoutingCoreNetworkChildSelectors 2
registerRegressionParallelSelectorList docker-routing-dns-csv runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-routing-dns-csv-parallel-${BASHPID:-$$}" listRegressionDockerRoutingDnsCsvChildSelectors 3
registerRegressionParallelSelectorList fast-only-output runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-only-output-parallel-${BASHPID:-$$}" listRegressionFastOnlyOutputChildSelectors
registerRegressionParallelSelectorList fast-only runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-only-parallel-${BASHPID:-$$}" listRegressionFastOnlyChildSelectors

registerRegressionParallelSelectorList fast-full runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-full-parallel-${BASHPID:-$$}" listRegressionFastFullChildSelectors
registerRegressionParallelSelectorList fast runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-parallel-${BASHPID:-$$}" listRegressionFastChildSelectors
# Ubuntu runner 实测 3 个顶层 worker 的原生门槛最快，4 个 worker 没有缩短完整 CI。
registerRegressionParallelSelectorList ci runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/ci-parallel-${BASHPID:-$$}" listRegressionCiChildSelectors "${PADM_REGRESSION_CI_PARALLEL_JOBS:-3}"
registerRegressionParallelSelectorList ci-pr runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/ci-pr-parallel-${BASHPID:-$$}" listRegressionCiPrChildSelectors "${PADM_REGRESSION_CI_PARALLEL_JOBS:-3}"

runDockerSpecValidationRegression() {
    bash -n "${PROJECT_ROOT}/docker/lib/services.sh" "${PROJECT_ROOT}/docker/tests/spec-validation.sh"
    shellcheck --severity=error "${PROJECT_ROOT}/docker/lib/services.sh" \
        "${PROJECT_ROOT}/docker/tests/spec-validation.sh"
    bash "${PROJECT_ROOT}/docker/tests/spec-validation.sh"
}
registerRegressionFunctionLeaf docker-spec-validation runDockerSpecValidationRegression
registerRegressionFunctionLeaf docker-port-hopping-config runDockerPortHoppingConfigRegression

runDockerGenerationMetadataRegression() {
    bash -n "${PROJECT_ROOT}/docker/tests/generation-metadata.sh"
    shellcheck --severity=error "${PROJECT_ROOT}/docker/tests/generation-metadata.sh"
    bash "${PROJECT_ROOT}/docker/tests/generation-metadata.sh"
}
registerRegressionFunctionLeaf docker-generation-metadata runDockerGenerationMetadataRegression
