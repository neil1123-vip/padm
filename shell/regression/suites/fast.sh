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
    # XHTTP 分片优先调度，避免长事务排在完整回归尾部。
    printf '%s\n' \
        docker-xhttp-edit \
        docker-xhttp-rollback \
        docker-xhttp-validation \
        docker-phase3-edit \
        docker-phase3-entries \
        docker-traditional-tls-transports \
        docker-traditional-tls-base \
        docker-setup-transports \
        docker-setup-encrypted-udp \
        docker-phase4-maintenance \
        docker-routing-core-network-lifecycle \
        docker-reality \
        docker-setup-tls \
        docker-phase4-lifecycle \
        docker-reality-targets-direct \
        docker-reality-parameters \
        docker-sites \
        docker-routing-direct-block-ip-workflow \
        docker-routing-direct-block-csv-workflow \
        docker-routing-core-policy-lifecycle \
        docker-setup-core \
        docker-phase1 \
        docker-menu \
        docker-setup-encrypted-tcp \
        docker-routing-dns-hosts-workflow \
        docker-phase6 \
        docker-entry-port-alias \
        docker-cdn-entries \
        docker-fail2ban-ownership \
        docker-control-state \
        docker-reality-targets-selection \
        docker-reality-target-library \
        docker-control-client \
        docker-tproxy-ownership \
        docker-port-hopping-preflight \
        docker-routing-core-contracts \
        docker-http-relay \
        docker-control-cli \
        docker-release \
        docker-control-sync \
        docker-phase5 \
        docker-geo-data \
        docker-accounts \
        docker-traffic \
        docker-permissions \
        docker-fail2ban-source \
        docker-control-api \
        docker-wireguard-runtime \
        docker-subscriptions \
        docker-accounts-cli \
        docker-ssh-preflight \
        docker-ssh-driver \
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
    printf '%s\n' docker-sites docker-entry-port-alias docker-cdn-entries docker-menu docker-control-state
}

listRegressionDockerContractsFastRestChildSelectors() {
    # 回滚分片与安装合同先启动，避免短任务把长事务推到队尾。
    printf '%s\n' \
        docker-xhttp-rollback \
        docker-phase1 \
        docker-control-client \
        docker-tproxy-ownership \
        docker-port-hopping-preflight \
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
        docker-ssh-preflight \
        docker-ssh-driver \
        docker-permissions \
        docker-wireguard-runtime \
        docker-accounts-cli \
        docker-subscriptions \
        docker-control-api \
        docker-business \
        docker-phase2 \
        docker-xhttp-validation
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

listRegressionDockerContractsRealityMetadataChildSelectors() {
    printf '%s\n' docker-xhttp-edit docker-reality-parameters docker-reality-targets-selection docker-reality-target-library
}

listRegressionDockerContractsSetupBasicChildSelectors() {
    printf '%s\n' docker-traditional-tls-base docker-setup-core docker-setup-encrypted-tcp
}

listRegressionDockerContractsSystemLightChildSelectors() {
    printf '%s\n' docker-phase4-lifecycle docker-phase6
}

listRegressionDockerRoutingCoreNetworkChildSelectors() {
    printf '%s\n' docker-routing-core-contracts docker-routing-core-network-lifecycle
}

listRegressionDockerRoutingDnsCsvChildSelectors() {
    printf '%s\n' docker-routing-dns-hosts-workflow docker-routing-direct-block-csv-workflow
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
    PADM_DOCKER_XHTTP_SCOPE=edit runDockerXhttpRegression
}

runDockerXhttpRollbackRegression() {
    PADM_DOCKER_XHTTP_SCOPE=rollback runDockerXhttpRegression
}

runDockerTraditionalTlsBaseRegression() {
    PADM_DOCKER_TRADITIONAL_TLS_SCOPE=base runDockerTraditionalTlsRegression
}

runDockerTraditionalTlsTransportsRegression() {
    PADM_DOCKER_TRADITIONAL_TLS_SCOPE=transports runDockerTraditionalTlsRegression
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
    PADM_DOCKER_ROUTING_SCOPE=core-network-lifecycle bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerRoutingCorePolicyLifecycleRegression() {
    PADM_DOCKER_ROUTING_SCOPE=core-policy-lifecycle bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
}

runDockerPhase4MaintenanceRegression() {
    PADM_DOCKER_PHASE4_SCOPE=maintenance bash "${PROJECT_ROOT}/docker/tests/phase4.sh"
}

runDockerPhase3EditRegression() {
    PADM_DOCKER_PHASE3_SCOPE=edit bash "${PROJECT_ROOT}/docker/tests/phase3.sh"
}

runDockerPhase3EntriesRegression() {
    PADM_DOCKER_PHASE3_SCOPE=entries bash "${PROJECT_ROOT}/docker/tests/phase3.sh"
}

runDockerPhase4LifecycleRegression() {
    PADM_DOCKER_PHASE4_SCOPE=lifecycle bash "${PROJECT_ROOT}/docker/tests/phase4.sh"
}

runDockerRealityTargetsDirectRegression() {
    PADM_DOCKER_REALITY_TARGETS_SCOPE=direct runDockerRealityTargetsRegression
}

runDockerRealityTargetsSelectionRegression() {
    PADM_DOCKER_REALITY_TARGETS_SCOPE=selection runDockerRealityTargetsRegression
}

runDockerRoutingDnsHostsWorkflowRegression() {
    PADM_DOCKER_ROUTING_SCOPE=domains-dns-hosts bash "${PROJECT_ROOT}/docker/tests/routing-socks5.sh"
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
        bash "${PROJECT_ROOT}/docker/tests/control-join.sh" &&
        runDockerControlSyncScheduleRegression
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

runDockerControlLogCronRealRegression() {
    PYTHONDONTWRITEBYTECODE=1 python3 "${PROJECT_ROOT}/docker/tests/control-two-deployment-real.py" --log-schedule-cron-only
}

runDockerControlStateRegression() {
    bash "${PROJECT_ROOT}/docker/tests/control-state.sh"
}

runDockerControlCliRegression() {
    bash "${PROJECT_ROOT}/docker/tests/control-cli.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/control-invite.sh" &&
        runDockerControlLogScheduleRegression
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

runDockerWireGuardRuntimeRegression() {
    bash "${PROJECT_ROOT}/docker/tests/wireguard-runtime.sh"
}

runDockerTProxyOwnershipRegression() {
    bash "${PROJECT_ROOT}/docker/tests/tproxy-ownership.sh"
}

runDockerPortHoppingPreflightRegression() {
    python3 "${PROJECT_ROOT}/docker/tests/port-hopping-preflight.py" &&
        python3 "${PROJECT_ROOT}/docker/tests/port-hopping-ownership.py" &&
        runDockerPortHoppingTargetRegression
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
    bash "${PROJECT_ROOT}/docker/tests/port-hopping-target.sh" &&
        bash "${PROJECT_ROOT}/docker/tests/port-hopping-start.sh"
}

runDockerPortHoppingTargetRealRegression() {
    bash "${PROJECT_ROOT}/docker/tests/port-hopping-target-real.sh"
}

runDockerTProxyRealRegression() {
    PADM_NET_REAL_CASE=tproxy bash "${PROJECT_ROOT}/docker/tests/fail2ban-isolated-real.sh"
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
registerRegressionFunctionLeaf docker-release runDockerReleaseRegression
registerRegressionFunctionLeaf docker-setup runDockerSetupRegression
registerRegressionFunctionLeaf docker-setup-core runDockerSetupRegression core
registerRegressionFunctionLeaf docker-setup-encrypted runDockerSetupRegression encrypted
registerRegressionFunctionLeaf docker-setup-encrypted-udp runDockerSetupRegression encrypted-udp
registerRegressionFunctionLeaf docker-setup-encrypted-tcp runDockerSetupRegression encrypted-tcp
registerRegressionFunctionLeaf docker-setup-transports runDockerSetupRegression transports
registerRegressionFunctionLeaf docker-setup-tls runDockerSetupRegression tls
registerRegressionFunctionLeaf docker-protocol runDockerProtocolRegression
registerRegressionFunctionLeaf docker-reality runDockerRealityRegression
registerRegressionFunctionLeaf docker-reality-parameters runDockerRealityParametersRegression
registerRegressionFunctionLeaf docker-reality-targets runDockerRealityTargetsRegression
registerRegressionFunctionLeaf docker-reality-targets-direct runDockerRealityTargetsDirectRegression
registerRegressionFunctionLeaf docker-reality-targets-selection runDockerRealityTargetsSelectionRegression
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
registerRegressionFunctionLeaf docker-traditional-tls-base runDockerTraditionalTlsBaseRegression
registerRegressionFunctionLeaf docker-traditional-tls-transports runDockerTraditionalTlsTransportsRegression
registerRegressionFunctionLeaf docker-permissions runDockerPermissionsRegression
registerRegressionFunctionLeaf docker-tls runDockerTlsRegression
registerRegressionFunctionLeaf docker-renewal runDockerRenewalRegression
registerRegressionFunctionLeaf docker-phase2 runDockerPhase2Regression
registerRegressionFunctionLeaf docker-phase3 runDockerPhase3Regression
registerRegressionFunctionLeaf docker-phase3-edit runDockerPhase3EditRegression
registerRegressionFunctionLeaf docker-phase3-entries runDockerPhase3EntriesRegression
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
registerRegressionFunctionLeaf docker-control-log-schedule runDockerControlLogScheduleRegression
registerRegressionFunctionLeaf docker-control-client runDockerControlClientRegression
registerRegressionFunctionLeaf docker-control-sync-schedule runDockerControlSyncScheduleRegression
registerRegressionFunctionLeaf docker-control-two-node-real runDockerControlTwoNodeRealRegression
registerRegressionFunctionLeaf docker-control-two-deployment-real runDockerControlTwoDeploymentRealRegression
registerRegressionFunctionLeaf docker-control-log-cron-real runDockerControlLogCronRealRegression
registerRegressionFunctionLeaf docker-wireguard-runtime runDockerWireGuardRuntimeRegression
registerRegressionFunctionLeaf docker-tproxy-ownership runDockerTProxyOwnershipRegression
registerRegressionFunctionLeaf docker-port-hopping-preflight runDockerPortHoppingPreflightRegression
registerRegressionFunctionLeaf docker-port-hopping-target runDockerPortHoppingTargetRegression
registerRegressionFunctionLeaf docker-port-hopping-target-real runDockerPortHoppingTargetRealRegression
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
registerRegressionParallelSelectorList docker-contracts-reality-metadata runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-reality-metadata-parallel-${BASHPID:-$$}" listRegressionDockerContractsRealityMetadataChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-setup-basic runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-setup-basic-parallel-${BASHPID:-$$}" listRegressionDockerContractsSetupBasicChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-system-light runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-system-light-parallel-${BASHPID:-$$}" listRegressionDockerContractsSystemLightChildSelectors 2
registerRegressionParallelSelectorList docker-routing-core-network runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-routing-core-network-parallel-${BASHPID:-$$}" listRegressionDockerRoutingCoreNetworkChildSelectors 2
registerRegressionParallelSelectorList docker-routing-dns-csv runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-routing-dns-csv-parallel-${BASHPID:-$$}" listRegressionDockerRoutingDnsCsvChildSelectors 2
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
