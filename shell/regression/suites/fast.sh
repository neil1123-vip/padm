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
        docker-geo-data \
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
    listRegressionDockerContractsFastChildSelectors
    listRegressionDockerContractsSystemChildSelectors
    listRegressionDockerContractsRealityChildSelectors
    printf '%s\n' \
        docker-setup-core \
        docker-setup-encrypted \
        docker-setup-transports \
        docker-setup-tls \
        docker-traditional-tls
}

listRegressionDockerContractsFastChildSelectors() {
    # 长测试先入队，避免最后只剩单个主控事务占用一个槽位。
    printf '%s\n' \
        docker-menu \
        docker-control-state \
        docker-phase1 \
        docker-phase5 \
        docker-control-sync \
        docker-control-client \
        docker-release \
        docker-geo-data \
        docker-traffic \
        docker-accounts \
        docker-control-cli \
        docker-wireguard-runtime \
        docker-control-api \
        docker-permissions \
        docker-accounts-cli \
        docker-subscriptions \
        docker-business \
        docker-phase2
}

listRegressionDockerContractsSystemChildSelectors() {
    printf '%s\n' docker-phase3 docker-phase4 docker-phase6
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

registerRegressionFunctionLeaf install-module-manifest runInstallModuleManifestCompleteRegression
registerRegressionFunctionLeaf fast-only-safety runRegressionFastOnlySafety
registerRegressionFunctionLeaf fast-only-output-auto-install runRegressionFastOnlyOutputAutoInstall
registerRegressionFunctionLeaf fast-only-output-rest runRegressionFastOnlyOutputRest
registerRegressionFunctionLeaf fast-only-compatibility runSingBox114CompatibilityAuditRegression
registerRegressionFunctionLeaf fast-smoke runRegressionFastSmoke
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
registerRegressionFunctionLeaf docker-phase5 runDockerPhase5Regression
registerRegressionFunctionLeaf docker-phase6 runDockerPhase6Regression
registerRegressionFunctionLeaf docker-traffic runDockerTrafficRegression
registerRegressionFunctionLeaf docker-accounts runDockerAccountsRegression
registerRegressionFunctionLeaf docker-accounts-cli runDockerAccountsCliRegression
registerRegressionFunctionLeaf docker-subscriptions runDockerSubscriptionsRegression
registerRegressionFunctionLeaf docker-business runDockerBusinessRegression
registerRegressionFunctionLeaf docker-geo-data runDockerGeoRegression
registerRegressionFunctionLeaf docker-control-api runDockerControlApiRegression
registerRegressionFunctionLeaf docker-control-sync runDockerControlSyncRegression
registerRegressionFunctionLeaf docker-control-state runDockerControlStateRegression
registerRegressionFunctionLeaf docker-control-cli runDockerControlCliRegression
registerRegressionFunctionLeaf docker-control-client runDockerControlClientRegression
registerRegressionFunctionLeaf docker-wireguard-runtime runDockerWireGuardRuntimeRegression

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
registerRegressionParallelSelectorList docker-contracts runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-parallel-${BASHPID:-$$}" listRegressionDockerContractsChildSelectors 2
registerRegressionParallelSelectorList docker-contracts-fast runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/docker-contracts-fast-parallel-${BASHPID:-$$}" listRegressionDockerContractsFastChildSelectors 2
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
