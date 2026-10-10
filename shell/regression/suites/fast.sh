#!/usr/bin/env bash

listRegressionFastOnlyOutputChildSelectors() {
    printf '%s\n' \
        fast-only-output-auto-install \
        fast-only-output-rest
}

listRegressionFastOnlyChildSelectors() {
    printf '%s\n' \
        fast-only-safety \
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
    # 完整合同按历史耗时全局长任务优先，减少尾部空等。
    printf '%s\n' \
        docker-reality \
        docker-traditional-tls \
        docker-routing-core-workflow \
        docker-routing-domains-workflow \
        docker-phase3 \
        docker-setup-encrypted \
        docker-setup-transports \
        docker-reality-targets \
        docker-setup-tls \
        docker-reality-parameters \
        docker-setup-core \
        docker-sites \
        docker-phase6 \
        docker-menu \
        docker-reality-target-library \
        docker-control-state \
        docker-phase4 \
        docker-control-client \
        docker-phase1 \
        docker-phase5 \
        docker-control-cli \
        docker-control-sync \
        docker-release \
        docker-geo-data \
        docker-traffic \
        docker-http-relay \
        docker-entry-port-alias \
        docker-accounts \
        docker-permissions \
        docker-wireguard-runtime \
        docker-tproxy-ownership \
        docker-fail2ban-ownership \
        docker-fail2ban-source \
        docker-control-api \
        docker-subscriptions \
        docker-accounts-cli \
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
    listRegressionDockerContractsFastRestChildSelectors
}

listRegressionDockerContractsFastHeavyChildSelectors() {
    printf '%s\n' docker-sites docker-entry-port-alias
}

listRegressionDockerContractsFastRestChildSelectors() {
    # 按云端实测长任务优先，站点与入口别名由另一个隔离分片执行。
    printf '%s\n' \
        docker-phase1 \
        docker-menu \
        docker-control-state \
        docker-control-client \
        docker-tproxy-ownership \
        docker-http-relay \
        docker-control-cli \
        docker-phase5 \
        docker-fail2ban-ownership \
        docker-control-sync \
        docker-release \
        docker-geo-data \
        docker-accounts \
        docker-traffic \
        docker-fail2ban-source \
        docker-permissions \
        docker-wireguard-runtime \
        docker-accounts-cli \
        docker-subscriptions \
        docker-control-api \
        docker-business \
        docker-phase2
}

listRegressionDockerContractsSystemChildSelectors() {
    printf '%s\n' docker-phase3 docker-phase4 docker-phase6
}

listRegressionDockerContractsRoutingChildSelectors() {
    printf '%s\n' docker-routing-core-workflow docker-routing-domains-workflow
}

listRegressionDockerContractsProtocolChildSelectors() {
    printf '%s\n' docker-traditional-tls docker-reality
}

listRegressionDockerCoreAssessmentChildSelectors() {
    printf '%s\n' docker-phase1 docker-release docker-menu docker-phase3 docker-phase6
}

listRegressionDockerGeoChildSelectors() {
    printf '%s\n' docker-geo-data docker-menu docker-phase3 docker-phase6 docker-renewal
}

listRegressionDockerContractsRealityChildSelectors() {
    printf '%s\n' docker-reality-parameters docker-reality-targets docker-reality-target-library
}

runDockerTrafficRegression() {
    bash "${PROJECT_ROOT}/docker/tests/traffic.sh"
}

runDockerRoutingSocks5Regression() {
    bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
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

runDockerFail2banOwnershipRegression() {
    bash "${PROJECT_ROOT}/docker/tests/fail2ban-ownership.sh"
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
    bash "${PROJECT_ROOT}/docker/tests/subscriptions.sh"
}

runDockerBusinessRegression() {
    bash "${PROJECT_ROOT}/docker/tests/business.sh"
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
        bash "${PROJECT_ROOT}/docker/tests/control-join.sh"
}

runDockerControlTwoNodeRealRegression() {
    PYTHONDONTWRITEBYTECODE=1 python3 "${PROJECT_ROOT}/docker/tests/control-two-node-real.py"
}

runDockerControlTwoDeploymentRealRegression() {
    PYTHONDONTWRITEBYTECODE=1 python3 "${PROJECT_ROOT}/docker/tests/control-two-deployment-real.py"
}

runDockerControlStateRegression() {
    bash "${PROJECT_ROOT}/docker/tests/control-state.sh"
}

runDockerControlCliRegression() {
    bash "${PROJECT_ROOT}/docker/tests/control-cli.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/control-invite.sh"
}

runDockerWireGuardRuntimeRegression() {
    bash "${PROJECT_ROOT}/docker/tests/wireguard-runtime.sh"
}

runDockerTProxyOwnershipRegression() {
    bash "${PROJECT_ROOT}/docker/tests/tproxy-ownership.sh"
}

runDockerTProxyRealRegression() {
    PADM_NET_REAL_CASE=tproxy bash "${PROJECT_ROOT}/docker/tests/fail2ban-isolated-real.sh"
}

registerRegressionFunctionLeaf install-module-manifest runInstallModuleManifestCompleteRegression
registerRegressionFunctionLeaf fast-only-safety runRegressionFastOnlySafety
registerRegressionFunctionLeaf fast-only-output-auto-install runRegressionFastOnlyOutputAutoInstall
registerRegressionFunctionLeaf fast-only-output-rest runRegressionFastOnlyOutputRest
registerRegressionFunctionLeaf fast-only-compatibility runSingBox114CompatibilityAuditRegression
registerRegressionFunctionLeaf fast-smoke runRegressionFastSmoke
registerRegressionFunctionLeaf update-padm-signal-rollback runUpdatePadmSignalRollbackRegression
registerRegressionFunctionLeaf docker-phase1 runDockerPhase1Regression
registerRegressionFunctionLeaf docker-menu runDockerMenuRegression
registerRegressionFunctionLeaf docker-release runDockerReleaseRegression
registerRegressionFunctionLeaf docker-setup runDockerSetupRegression
registerRegressionFunctionLeaf docker-setup-core runDockerSetupRegression core
registerRegressionFunctionLeaf docker-setup-encrypted runDockerSetupRegression encrypted
registerRegressionFunctionLeaf docker-setup-transports runDockerSetupRegression transports
registerRegressionFunctionLeaf docker-setup-tls runDockerSetupRegression tls
registerRegressionFunctionLeaf docker-protocol runDockerProtocolRegression
registerRegressionFunctionLeaf docker-reality runDockerRealityRegression
registerRegressionFunctionLeaf docker-reality-parameters runDockerRealityParametersRegression
registerRegressionFunctionLeaf docker-reality-targets runDockerRealityTargetsRegression
registerRegressionFunctionLeaf docker-reality-target-library runDockerRealityTargetLibraryRegression
registerRegressionFunctionLeaf docker-hysteria2 runDockerHysteria2Regression
registerRegressionFunctionLeaf docker-anytls runDockerAnyTlsRegression
registerRegressionFunctionLeaf docker-naive runDockerNaiveRegression
registerRegressionFunctionLeaf docker-shadowsocks runDockerShadowsocksRegression
registerRegressionFunctionLeaf docker-tuic runDockerTuicRegression
registerRegressionFunctionLeaf docker-trojan runDockerTrojanRegression
registerRegressionFunctionLeaf docker-vmess runDockerVmessRegression
registerRegressionFunctionLeaf docker-httpupgrade runDockerHttpupgradeRegression
registerRegressionFunctionLeaf docker-grpc-tls runDockerGrpcTlsRegression
registerRegressionFunctionLeaf docker-traditional-tls runDockerTraditionalTlsRegression
registerRegressionFunctionLeaf docker-permissions runDockerPermissionsRegression
registerRegressionFunctionLeaf docker-tls runDockerTlsRegression
registerRegressionFunctionLeaf docker-renewal runDockerRenewalRegression
registerRegressionFunctionLeaf docker-phase2 runDockerPhase2Regression
registerRegressionFunctionLeaf docker-phase3 runDockerPhase3Regression
registerRegressionFunctionLeaf docker-phase4 runDockerPhase4Regression
registerRegressionFunctionLeaf docker-fail2ban-real runDockerFail2banRealRegression
registerRegressionFunctionLeaf docker-fail2ban-source-real runDockerFail2banSourceRealRegression
registerRegressionFunctionLeaf docker-fail2ban-ownership runDockerFail2banOwnershipRegression
registerRegressionFunctionLeaf docker-fail2ban-source runDockerFail2banSourceRegression
registerRegressionFunctionLeaf docker-phase5 runDockerPhase5Regression
registerRegressionFunctionLeaf docker-phase6 runDockerPhase6Regression
registerRegressionFunctionLeaf docker-traffic runDockerTrafficRegression
registerRegressionFunctionLeaf docker-routing-socks5 runDockerRoutingSocks5Regression
registerRegressionFunctionLeaf docker-routing-socks5-real runDockerRoutingSocks5RealRegression
registerRegressionFunctionLeaf docker-http-relay runDockerHttpRelayRegression
registerRegressionFunctionLeaf docker-http-relay-real runDockerHttpRelayRealRegression
registerRegressionFunctionLeaf docker-http-relay-published-real runDockerHttpRelayPublishedRealRegression
registerRegressionFunctionLeaf docker-entry-port-alias runDockerEntryPortAliasRegression
registerRegressionFunctionLeaf docker-entry-port-alias-real runDockerEntryPortAliasRealRegression
registerRegressionFunctionLeaf docker-routing-dns-hosts runDockerRoutingSocks5Regression
registerRegressionFunctionLeaf docker-routing-dns-hosts-real runDockerRoutingDnsHostsRealRegression
registerRegressionFunctionLeaf docker-routing-direct-block runDockerRoutingSocks5Regression
registerRegressionFunctionLeaf docker-routing-direct-block-real runDockerRoutingDnsHostsRealRegression
registerRegressionFunctionLeaf docker-routing-block-ips runDockerRoutingSocks5Regression
registerRegressionFunctionLeaf docker-routing-block-ips-real runDockerRoutingBlockIpsRealRegression
registerRegressionFunctionLeaf docker-routing-block-bt runDockerRoutingBlockBtRegression
registerRegressionFunctionLeaf docker-routing-block-bt-real runDockerRoutingBlockBtRealRegression
registerRegressionFunctionLeaf docker-routing-region runDockerRoutingRegionRegression
registerRegressionFunctionLeaf docker-routing-region-real runDockerRoutingRegionRealRegression
registerRegressionFunctionLeaf docker-routing-domains-workflow runDockerRoutingDomainsWorkflowRegression
registerRegressionFunctionLeaf docker-routing-core-workflow runDockerRoutingCoreWorkflowRegression
registerRegressionFunctionLeaf docker-routing-ipv6 runDockerRoutingIPv6Regression
registerRegressionFunctionLeaf docker-routing-ipv6-real runDockerRoutingIPv6RealRegression
registerRegressionFunctionLeaf docker-routing-warp runDockerRoutingWarpRegression
registerRegressionFunctionLeaf docker-routing-warp-real runDockerRoutingWarpRealRegression
registerRegressionFunctionLeaf docker-accounts runDockerAccountsRegression
registerRegressionFunctionLeaf docker-accounts-cli runDockerAccountsCliRegression
registerRegressionFunctionLeaf docker-subscriptions runDockerSubscriptionsRegression
registerRegressionFunctionLeaf docker-business runDockerBusinessRegression
registerRegressionFunctionLeaf docker-sites runDockerSitesRegression
registerRegressionFunctionLeaf docker-geo-data runDockerGeoRegression
registerRegressionFunctionLeaf docker-control-api runDockerControlApiRegression
registerRegressionFunctionLeaf docker-control-sync runDockerControlSyncRegression
registerRegressionFunctionLeaf docker-control-state runDockerControlStateRegression
registerRegressionFunctionLeaf docker-control-cli runDockerControlCliRegression
registerRegressionFunctionLeaf docker-control-client runDockerControlClientRegression
registerRegressionFunctionLeaf docker-control-two-node-real runDockerControlTwoNodeRealRegression
registerRegressionFunctionLeaf docker-control-two-deployment-real runDockerControlTwoDeploymentRealRegression
registerRegressionFunctionLeaf docker-wireguard-runtime runDockerWireGuardRuntimeRegression
registerRegressionFunctionLeaf docker-tproxy-ownership runDockerTProxyOwnershipRegression
registerRegressionFunctionLeaf docker-tproxy-real runDockerTProxyRealRegression

listRegressionDockerTProxyChildSelectors() {
    printf '%s\n' docker-tproxy-ownership docker-phase4
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

registerRegressionParallelSelectorList docker-tls-focused runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/docker-tls-focused-parallel-${BASHPID:-$$}" listRegressionDockerTlsFocusedChildSelectors
registerRegressionParallelSelectorList docker-core-assessment runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-core-assessment-parallel-${BASHPID:-$$}" listRegressionDockerCoreAssessmentChildSelectors 2
registerRegressionParallelSelectorList docker-geo runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-geo-parallel-${BASHPID:-$$}" listRegressionDockerGeoChildSelectors 2
registerRegressionParallelSelectorList docker-contracts runRegressionDockerContracts \
    "${TMP_DIR}/docker-contracts-parallel-${BASHPID:-$$}" listRegressionDockerContractsChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-fast runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-fast-parallel-${BASHPID:-$$}" listRegressionDockerContractsFastChildSelectors 4
registerRegressionParallelSelectorList docker-contracts-fast-heavy runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-fast-heavy-parallel-${BASHPID:-$$}" listRegressionDockerContractsFastHeavyChildSelectors 4
registerRegressionParallelSelectorList docker-contracts-fast-rest runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-fast-rest-parallel-${BASHPID:-$$}" listRegressionDockerContractsFastRestChildSelectors 4
registerRegressionParallelSelectorList docker-contracts-routing runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-routing-parallel-${BASHPID:-$$}" listRegressionDockerContractsRoutingChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-protocol runRegressionDockerContracts \
    "${TMP_DIR}/docker-contracts-protocol-parallel-${BASHPID:-$$}" listRegressionDockerContractsProtocolChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-system runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-system-parallel-${BASHPID:-$$}" listRegressionDockerContractsSystemChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-reality runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-reality-parallel-${BASHPID:-$$}" listRegressionDockerContractsRealityChildSelectors 2
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
