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
    printf '%s\n' \
        fast-smoke \
        platform-refresh \
        install-module-manifest \
        subscription-output \
        subscription-state \
        core-safety-rollback \
        core-install-service-action-failure
}

listRegressionCiPrChildSelectors() {
    # PR 默认只跑不依赖大型状态夹具的安全门；订阅和 harness 变更由工作流按范围升级到 ci。
    printf '%s\n' \
        fast-smoke \
        platform-refresh \
        install-module-manifest \
        core-safety-rollback \
        core-install-service-action-failure
}

registerRegressionFunctionLeaf install-module-manifest runInstallModuleManifestCompleteRegression
registerRegressionFunctionLeaf fast-only-safety runRegressionFastOnlySafety
registerRegressionFunctionLeaf fast-only-output-auto-install runRegressionFastOnlyOutputAutoInstall
registerRegressionFunctionLeaf fast-only-output-rest runRegressionFastOnlyOutputRest
registerRegressionFunctionLeaf fast-only-compatibility runSingBox114CompatibilityAuditRegression
registerRegressionFunctionLeaf fast-smoke runRegressionFastSmoke
registerRegressionFunctionLeaf docker-phase1 runDockerPhase1Regression
registerRegressionFunctionLeaf docker-phase2 runDockerPhase2Regression
registerRegressionFunctionLeaf docker-phase3 runDockerPhase3Regression
registerRegressionFunctionLeaf docker-phase4 runDockerPhase4Regression
registerRegressionFunctionLeaf docker-phase5 runDockerPhase5Regression
registerRegressionFunctionLeaf docker-phase6 runDockerPhase6Regression

registerRegressionParallelSelectorList fast-only-output runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-only-output-parallel-${BASHPID:-$$}" listRegressionFastOnlyOutputChildSelectors
registerRegressionParallelSelectorList fast-only runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-only-parallel-${BASHPID:-$$}" listRegressionFastOnlyChildSelectors

registerRegressionParallelSelectorList fast-full runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-full-parallel-${BASHPID:-$$}" listRegressionFastFullChildSelectors
registerRegressionParallelSelectorList fast runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/fast-parallel-${BASHPID:-$$}" listRegressionFastChildSelectors
registerRegressionParallelSelectorList ci runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/ci-parallel-${BASHPID:-$$}" listRegressionCiChildSelectors 2
registerRegressionParallelSelectorList ci-pr runFrameworkParallelRegressionSelectorListWithJobs \
    "${TMP_DIR}/ci-pr-parallel-${BASHPID:-$$}" listRegressionCiPrChildSelectors 2
