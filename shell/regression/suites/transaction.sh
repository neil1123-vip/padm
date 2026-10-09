#!/usr/bin/env bash

listRegressionTransactionChildSelectors() {
    printf '%s\n' \
        transaction-core \
        transaction-system
}

listRegressionTransactionCoreSelectorEntries() {
    printf '%s\n' \
        'light sing-box-custom-paths' \
        'light sing-box-stats-build' \
        'heavy core-install-service-action-failure' \
        'light core-template-return-failure' \
        'medium core-install-signal-rollback' \
        'light reality-profile-failure' \
        'medium config-transaction' \
        'heavy core-port-file-transaction' \
        'medium entry-helper-config' \
        'light core-safety-rollback' \
        'light sing-box-reality-key-transaction' \
        'light tls-failure-return' \
        'light tls-reinstall-rollback' \
        'medium tls-renew-failure-propagation' \
        'medium sing-box-merge-config-transaction' \
        'light sing-box-uninstall-failure-propagation' \
        'light sing-box-protocol-reload-failure' \
        'light sing-box-protocol-output-rollback' \
        'light geo-update-reload-failure' \
        'medium reload-core-propagation' \
        'medium sing-box-log-transaction'
}

listRegressionTransactionCoreSelectors() {
    local profile=${1:-default}
    local wave selector

    case "${profile}" in
    heavy)
        printf '%s\n' core-install-service-action-failure core-port-file-transaction
        return
        ;;
    medium)
        printf '%s\n' config-transaction entry-helper-config reload-core-propagation \
            sing-box-log-transaction sing-box-merge-config-transaction tls-renew-failure-propagation \
            core-install-signal-rollback
        return
        ;;
    default | light) ;;
    *)
        printf 'unknown transaction-core selector profile: %s\n' "${profile}" >&2
        return 2
        ;;
    esac

    while read -r wave selector; do
        [[ -n "${selector}" ]] || continue
        if [[ "${profile}" == "default" || "${wave}" == "${profile}" ]]; then
            printf '%s\n' "${selector}"
        fi
    done < <(listRegressionTransactionCoreSelectorEntries)
}

listRegressionTransactionCoreChildSelectors() {
    listRegressionTransactionCoreSelectors default
}

listRegressionTransactionCoreMainChildSelectors() {
    printf '%s\n' \
        core-safety-rollback \
        config-transaction \
        core-port-file-transaction \
        entry-helper-config \
        sing-box-reality-key-transaction \
        sing-box-merge-config-transaction \
        reload-core-propagation
}

listRegressionTransactionCoreHeavyChildSelectors() {
    listRegressionTransactionCoreSelectors heavy
}

listRegressionTransactionCoreMediumChildSelectors() {
    listRegressionTransactionCoreSelectors medium
}

listRegressionTransactionCoreLightChildSelectors() {
    listRegressionTransactionCoreSelectors light
}

listRegressionTransactionSystemChildSelectors() {
    printf '%s\n' \
        nginx-service-failure \
        nginx-service-refresh \
        uninstall-nginx-cleanup \
        clean-agent-nginx-managed-remove \
        fail2ban-managed-cleanup \
        fail2ban-apply-transaction \
        uninstall-wireguard-cleanup \
        wireguard-key-transaction \
        wireguard-control-safe-dir \
        warp-config-safe-dir \
        warp-config-file-cleanup \
        uninstall-service-stop-failure \
        xray-install-stop-failure \
        alone-nginx-write-transaction \
        alone-nginx-update-transaction
}

runRegressionTransactionCoreSuiteRoot() {
    if [[ "${PADM_REGRESSION_TRANSACTION_CORE_RESOURCE_PROFILE:-}" == "all" ]]; then
        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_TRANSACTION_CORE_HEAVY_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-2}}" \
            runFrameworkParallelRegressionSelectorList "${TMP_DIR}/transaction-core-parallel-heavy-${BASHPID:-$$}" \
            listRegressionTransactionCoreHeavyChildSelectors

        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_TRANSACTION_CORE_MEDIUM_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-3}}" \
            runFrameworkParallelRegressionSelectorList "${TMP_DIR}/transaction-core-parallel-medium-${BASHPID:-$$}" \
            listRegressionTransactionCoreMediumChildSelectors

        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_TRANSACTION_CORE_LIGHT_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}" \
            runFrameworkParallelRegressionSelectorList "${TMP_DIR}/transaction-core-parallel-light-${BASHPID:-$$}" \
            listRegressionTransactionCoreLightChildSelectors
        return
    fi

    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/transaction-core-parallel-${BASHPID:-$$}" \
        listRegressionTransactionCoreChildSelectors
}

runRegressionTransactionSystemSuiteRoot() {
    PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_TRANSACTION_SYSTEM_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}" \
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/transaction-system-parallel-${BASHPID:-$$}" \
        listRegressionTransactionSystemChildSelectors
}

registerRegressionFunctionLeaf sing-box-custom-paths runSingBoxCustomPathsRegression
registerRegressionFunctionLeaf sing-box-stats-build runSingBoxStatsBuildRegression
registerRegressionFunctionLeaf config-transaction runConfigTransactionRegression
registerRegressionFunctionLeaf core-port-file-transaction runCorePortFileTransactionRegression
registerRegressionFunctionLeaf entry-helper-config runEntryHelperConfigRegression
runRegressionCoreSafetyRollback() (
    set -euo pipefail
    runCoreReleaseArchiveRejectsRegression unsafe-path
    runCoreReleaseArchiveRejectsRegression symlink-payload
    runCoreFirstInstallCommitFailureRollbackRegression
    runCoreUpgradePendingStartRollbackRegression
    runCoreInstallRejectsUnsafeBinaryPathRegression
    runCoreCleanupFailurePropagationRegression
)

registerRegressionFunctionLeaf core-safety-rollback runRegressionCoreSafetyRollback
registerRegressionFunctionLeaf sing-box-reality-key-transaction runSingBoxRealityKeyTransactionRegression
registerRegressionFunctionLeaf core-template-return-failure runCoreTemplateReturnFailureRegression
registerRegressionFunctionLeaf core-install-signal-rollback runCoreInstallSignalRollbackRegression
registerRegressionFunctionLeaf core-install-service-action-failure runCoreInstallServiceActionFailureRegression
registerRegressionFunctionLeaf sing-box-uninstall-failure-propagation runSingBoxUninstallFailurePropagationRegression
registerRegressionFunctionLeaf sing-box-protocol-reload-failure runSingBoxProtocolReloadFailureRegression
registerRegressionFunctionLeaf sing-box-protocol-output-rollback runSingBoxProtocolOutputRollbackRegression
registerRegressionFunctionLeaf geo-update-reload-failure runGeoUpdateReloadFailureRegression
registerRegressionFunctionLeaf sing-box-log-transaction runSingBoxLogTransactionRegression
registerRegressionFunctionLeaf sing-box-merge-config-transaction runSingBoxMergeConfigTransactionRegression
registerRegressionFunctionLeaf reload-core-propagation runReloadCorePropagationRegression

registerRegressionFunctionLeaf nginx-service-failure runNginxServiceFailureRegression
registerRegressionFunctionLeaf nginx-service-refresh runNginxServiceRefreshRegression
registerRegressionFunctionLeaf uninstall-nginx-cleanup runUninstallNginxCleanupRegression
registerRegressionFunctionLeaf clean-agent-nginx-managed-remove runCleanAgentNginxManagedRemovalRegression
registerRegressionFunctionLeaf fail2ban-managed-cleanup runFail2banManagedCleanupRegression
registerRegressionFunctionLeaf fail2ban-apply-transaction runFail2banApplyTransactionRegression
registerRegressionFunctionLeaf uninstall-wireguard-cleanup runUninstallWireGuardCleanupRegression
registerRegressionFunctionLeaf wireguard-key-transaction runWireGuardKeyTransactionRegression
registerRegressionFunctionLeaf wireguard-control-safe-dir runWireGuardControlSafeDirRegression
registerRegressionFunctionLeaf warp-config-safe-dir runWarpConfigSafeDirRegression
registerRegressionFunctionLeaf warp-config-file-cleanup runWarpConfigFileCleanupRegression
registerRegressionFunctionLeaf uninstall-service-stop-failure runUninstallServiceStopFailureRegression
registerRegressionFunctionLeaf xray-install-stop-failure runXrayInstallStopFailureRegression
registerRegressionFunctionLeaf alone-nginx-write-transaction runAloneNginxConfigWriteTransactionRegression
registerRegressionFunctionLeaf alone-nginx-update-transaction runAloneNginxUpdateTransactionRegression

registerRegressionAggregateRunner parallel transaction-system runRegressionTransactionSystemSuiteRoot \
    $(listRegressionTransactionSystemChildSelectors)

registerRegressionAggregateRunner parallel transaction-core runRegressionTransactionCoreSuiteRoot \
    $(listRegressionTransactionCoreChildSelectors)

registerRegressionParallelSelectorList transaction-core-main runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/transaction-core-main-${BASHPID:-$$}" listRegressionTransactionCoreMainChildSelectors

registerRegressionSequentialSelectorList transaction listRegressionTransactionChildSelectors
