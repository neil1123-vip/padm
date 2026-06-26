#!/usr/bin/env bash

runRegressionDispatcherRegistryOnlyContract() {
    local dispatcherFile="${PROJECT_ROOT}/shell/subscription_groups_regression.sh"

    ! grep -q 'subscription_groups_legacy\.sh' "${dispatcherFile}"
    ! grep -q 'subscription_groups_fast\.sh' "${dispatcherFile}"
    ! grep -q 'subscription_groups_remote_control\.sh' "${dispatcherFile}"
    ! grep -q 'subscription_groups_subscription_state\.sh' "${dispatcherFile}"
    grep -q 'regression/framework/env\.sh' "${dispatcherFile}"
    grep -q 'regression/framework/runtime\.sh' "${dispatcherFile}"
    grep -q 'regression/framework/registry\.sh' "${dispatcherFile}"
    grep -q 'runRegisteredRegressionMain' "${dispatcherFile}"
}

runSubscriptionStateNoImplicitFullFallbackContract() {
    local stateShim="${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state.sh"

    ! grep -q 'exec bash "\${SUBSCRIPTION_STATE_FULL_SCRIPT_PATH}" "\$@"' "${stateShim}"
}

runSubscriptionStateSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription_state.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_SUBSCRIPTION_STATE_SUITE_DIR}/../subscription_groups_subscription_state_full.sh"' "${suiteFile}"
    ! grep -q 'registerRegressionScriptLeaf .*subscription_groups_subscription_state_full\.sh' "${suiteFile}"
    grep -q 'registerRegressionFunctionLeaf "\${selector}" "\${runner}"' "${suiteFile}"
    grep -q '^subscription-state-structure runRegressionSubscriptionStateStructure$' "${suiteFile}"
    grep -q '^subscription-state-support runRegressionSubscriptionStateSupport$' "${suiteFile}"
    grep -q '^subscription-state-sync-rollback runRegressionSubscriptionStateSyncRollback$' "${suiteFile}"
}

runRemoteControlSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/remote_control.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_remote_control.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_REMOTE_CONTROL_SUITE_DIR}/../subscription_groups_remote_control.sh"' "${suiteFile}"
    ! grep -q 'registerRegressionScriptLeaf .*subscription_groups_remote_control\.sh' "${suiteFile}"
    grep -q 'registerRegressionFunctionLeaf "\${selector}" "\${runner}"' "${suiteFile}"
    grep -q '^remote-control-smoke-core runRegressionRemoteControlSmokeCore$' "${suiteFile}"
    grep -q '^remote-control-smoke-refresh-apply-basic runRegressionRemoteControlSmokeRefreshApplyBasic$' "${suiteFile}"
    grep -q '^remote-control-smoke-refresh-apply-prepare runRegressionRemoteControlSmokeRefreshApplyPrepare$' "${suiteFile}"
    grep -q '^remote-control-smoke-refresh-apply-failure runRegressionRemoteControlSmokeRefreshApplyFailure$' "${suiteFile}"
    grep -q '^remote-control-smoke-refresh-restore runRegressionRemoteControlSmokeRefreshRestore$' "${suiteFile}"
    grep -q '^remote-control-smoke-refresh-reconcile runRegressionRemoteControlSmokeRefreshReconcile$' "${suiteFile}"
    grep -q '^remote-control-contract-service-install-success runRegressionRemoteControlContractServiceInstallSuccess$' "${suiteFile}"
    grep -q '^remote-control-contract-service-install-systemctl-fail runRegressionRemoteControlContractServiceInstallSystemctlFail$' "${suiteFile}"
    grep -q '^remote-control-contract-service-install-health-fail runRegressionRemoteControlContractServiceInstallHealthFail$' "${suiteFile}"
    grep -q '^remote-control-contract-service-install-health-rollback runRegressionRemoteControlContractServiceInstallHealthRollback$' "${suiteFile}"
    grep -q '^remote-control-contract-service-install-token-transaction runRegressionRemoteControlContractServiceInstallTokenTransaction$' "${suiteFile}"
    grep -q '^remote-control-contract-server-response runRegressionRemoteControlContractServerResponse$' "${suiteFile}"
    grep -q '^remote-control-deep runRegressionRemoteControlDeep$' "${suiteFile}"
    grep -q 'registerRegressionAggregateParallel remote-control-smoke \\' "${suiteFile}"
    grep -q 'registerRegressionAggregateParallel remote-control-contract \\' "${suiteFile}"
    grep -q 'registerRegressionAggregateParallel remote-control \\' "${suiteFile}"
    grep -q '^registerRegressionAlias remote-control-light remote-control$' "${suiteFile}"

    ! grep -q '^runParallelRemoteControlModes()' "${scriptFile}"
    ! grep -q '^runParallelRemoteControlTotals()' "${scriptFile}"
    ! grep -q 'PADM_REGRESSION_SUPPRESS_DONE=1 PADM_REGRESSION_INTERNAL_CLI=1 bash "\${REMOTE_CONTROL_SCRIPT_PATH}"' "${scriptFile}"
    grep -q 'smoke runRegressionRemoteControlSmoke' "${scriptFile}"
    grep -q 'contract runRegressionRemoteControlContract' "${scriptFile}"
    grep -q 'apply runRegressionRemoteControlSmokeRefreshApply' "${scriptFile}"
    grep -q 'reconcile runRegressionRemoteControlSmokeRefreshReconcile' "${scriptFile}"
    grep -q 'service-install runRegressionRemoteControlContractServiceInstall' "${scriptFile}"
    grep -q 'server-response runRegressionRemoteControlContractServerResponse' "${scriptFile}"
    grep -q 'remote-control-contract-service-install-success runRegressionRemoteControlContractServiceInstallSuccess' "${scriptFile}"
    grep -q 'remote-control-contract-service-install-token-transaction runRegressionRemoteControlContractServiceInstallTokenTransaction' "${scriptFile}"
}

runRemoteControlAggregatesSupportSourceOnlyExecutionContract() (
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_remote_control.sh"
    local callsFile="${TMP_DIR}/remote-control-aggregate-runner-calls"
    local -a calls=()

    PADM_REGRESSION_SOURCE_ONLY=1 source "${scriptFile}"

    runParallelRegressionSelectors() {
        printf 'remote-control aggregate should not require selector registry in source-only mode\n' >&2
        return 97
    }

    runParallelRegressionRunners() {
        printf '%s\n' "$*" >>"${callsFile}"
    }

    : >"${callsFile}"
    runRegressionRemoteControl
    runRegressionRemoteControlSmokeRefresh
    runRegressionRemoteControlSmokeRefreshApply
    runRegressionRemoteControlSmoke
    runRegressionRemoteControlContract
    runRegressionRemoteControlContractServiceInstall

    mapfile -t calls <"${callsFile}"
    [[ "${#calls[@]}" -eq 6 ]]
    [[ "${calls[0]}" == "${TMP_DIR}/remote-control-default smoke runRegressionRemoteControlSmoke contract runRegressionRemoteControlContract" ]]
    [[ "${calls[1]}" == "${TMP_DIR}/remote-control-smoke-refresh apply runRegressionRemoteControlSmokeRefreshApply restore runRegressionRemoteControlSmokeRefreshRestore reconcile runRegressionRemoteControlSmokeRefreshReconcile" ]]
    [[ "${calls[2]}" == "${TMP_DIR}/remote-control-smoke-refresh-apply basic runRegressionRemoteControlSmokeRefreshApplyBasic prepare runRegressionRemoteControlSmokeRefreshApplyPrepare failure runRegressionRemoteControlSmokeRefreshApplyFailure" ]]
    [[ "${calls[3]}" == "${TMP_DIR}/remote-control-smoke smoke-core runRegressionRemoteControlSmokeCore smoke-refresh runRegressionRemoteControlSmokeRefresh" ]]
    [[ "${calls[4]}" == "${TMP_DIR}/remote-control-contract service-install runRegressionRemoteControlContractServiceInstall server-response runRegressionRemoteControlContractServerResponse" ]]
    [[ "${calls[5]}" == "${TMP_DIR}/remote-control-contract-service-install remote-control-contract-service-install-success runRegressionRemoteControlContractServiceInstallSuccess remote-control-contract-service-install-systemctl-fail runRegressionRemoteControlContractServiceInstallSystemctlFail remote-control-contract-service-install-health-fail runRegressionRemoteControlContractServiceInstallHealthFail remote-control-contract-service-install-health-rollback runRegressionRemoteControlContractServiceInstallHealthRollback remote-control-contract-service-install-token-transaction runRegressionRemoteControlContractServiceInstallTokenTransaction" ]]
)

runFastSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/fast.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_fast.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_FAST_SUITE_DIR}/../subscription_groups_fast.sh"' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf fast ' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf fast runRegressionFastSuiteRoot$' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf fast-reality ' "${suiteFile}"
    grep -q '^registerRegressionAggregateSequential fast-reality \\' "${suiteFile}"
    grep -q '^    fast \\' "${suiteFile}"
    grep -q '^    reality-candidates-fast$' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf platform-hot ' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf platform-hot runRegressionPlatformSuiteRoot$' "${suiteFile}"
    grep -q 'if \[\[ "\${PADM_REGRESSION_SOURCE_ONLY:-}" == "1" \]\]; then' "${scriptFile}"
}

runFastPlatformSourceOnlyExecutionContract() (
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_fast.sh"

    PADM_REGRESSION_SOURCE_ONLY=1 source "${scriptFile}"
    local platformDef fastDef
    platformDef=$(declare -f runRegressionPlatform)
    platformDef="${platformDef/runRegressionPlatform/runRegressionPlatformSuiteRoot}"
    eval "${platformDef}"
    fastDef=$(declare -f runRegressionFast)
    fastDef="${fastDef/runRegressionFast/runRegressionFastSuiteRoot}"
    fastDef="${fastDef/runRegressionPlatform/runRegressionPlatformSuiteRoot}"
    eval "${fastDef}"
    declare -F runRegressionFastSuiteRoot >/dev/null
    declare -F runRegressionPlatformSuiteRoot >/dev/null
)

runLegacySuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_LEGACY_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf transaction ' "${suiteFile}"
    grep -q '^registerRegressionAggregateSequential transaction \\' "${suiteFile}"
    grep -q '^    transaction-core \\' "${suiteFile}"
    grep -q '^    transaction-subscription \\' "${suiteFile}"
    grep -q '^    transaction-system$' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf platform-io ' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf platform-io runRegressionPlatformIo$' "${suiteFile}"
    grep -q '^registerRegressionScriptLeaf "\${selector}" "\${REGRESSION_LEGACY_SCRIPT}" "\${runner}"$' "${suiteFile}"
    grep -q 'if \[\[ "\${PADM_REGRESSION_SOURCE_ONLY:-}" == "1" \]\]; then' "${scriptFile}"
}

runLegacyPlatformIoSupportsSourceOnlyExecutionContract() (
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    PADM_REGRESSION_SOURCE_ONLY=1 source "${scriptFile}"
    declare -F runRegressionPlatformIo >/dev/null
)

runLegacyTlsUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"

    ! grep -q '^registerRegressionScriptLeaf tls ' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf tls runRegressionTls$' "${suiteFile}"
}

runLegacyDirectLeafSelectorsUseFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local status=0

    while read -r selector runner; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}\$" "${suiteFile}" || status=1
    done <<'EOF'
ui-smoke runRegressionMenuSmoke
routing-socks5-udp-associate runSocks5UdpAssociateRegression
routing-core-unsafe-config-dir runRoutingCoreRejectsUnsafeConfigDirRegression
routing-access-control-config-transaction runAccessControlConfigTransactionRegression
routing-access-control-unsafe-backup-dir runAccessControlRejectsUnsafeBackupDirRegression
routing-access-control-unsafe-config-dir runAccessControlRejectsUnsafeConfigDirRegression
routing-access-control-failure-return runAccessControlFailureReturnRegression
routing-bt-failure-return runBTRoutingFailureReturnRegression
routing-ipv6-failure-return runIPv6RoutingFailureReturnRegression
routing-warp-failure-return runWARPRoutingFailureReturnRegression
routing-socks5-failure-return runSocks5RoutingFailureReturnRegression
subscription-remote-fetch runRegressionSubscriptionRemoteFetch
reality-candidates-fast runRealityCandidateFastRegression
runtime-auto-install-reality-route runAutoInstallRealityRouteRegression
transaction-system runRegressionTransactionSystem
transaction-subscription runRegressionTransactionSubscription
config-transaction runConfigTransactionRegression
core-port-unsafe-config-dir runCorePortRejectsUnsafeConfigDirRegression
check-port-open-nginx-directory-target runCheckPortOpenNginxRejectsDirectoryTargetRegression
alone-nginx-directory-target runAloneNginxRejectsDirectoryTargetRegression
sing-box-managed-cleanup runSingBoxManagedCleanupRegression
xray-reality-port-failure runXrayRealityPortFailureRegression
reality-profile-failure runRealityProfileFailureRegression
sing-box-reality-key-transaction runSingBoxRealityKeyTransactionRegression
core-template-managed-remove runCoreTemplateManagedConfigRemovalRegression
core-template-return-failure runCoreTemplateReturnFailureRegression
core-binary-install-copy-failure runCoreBinaryInstallCopyFailureRegression
sing-box-cronet-rollback runSingBoxCronetRollbackRegression
finalize-sing-box-rollback runFinalizeSingBoxBinaryInstallRollbackRegression
service-queue-apply-propagation runServiceQueueApplyPropagationRegression
core-install-service-action-failure runCoreInstallServiceActionFailureRegression
sing-box-merge-start-failure runSingBoxMergeStartFailureRegression
sing-box-uninstall-rejects-unsafe-config-path runSingBoxUninstallRejectsUnsafeConfigPathRegression
sing-box-uninstall-failure-propagation runSingBoxUninstallFailurePropagationRegression
sing-box-protocol-reload-failure runSingBoxProtocolReloadFailureRegression
geo-update-reload-failure runGeoUpdateReloadFailureRegression
core-cleanup-failure-propagation runCoreCleanupFailurePropagationRegression
sing-box-log-transaction runSingBoxLogTransactionRegression
core-upgrade-directory-target runCoreUpgradeRejectsDirectoryTargetRegression
legacy-core-upgrade-keeps-existing runLegacyCoreUpgradeKeepsExistingBinaryRegression
core-first-install-failure-clean runCoreFirstInstallLeavesNoLiveArtifactsOnFailureRegression
core-install-unsafe-binary-path runCoreInstallRejectsUnsafeBinaryPathRegression
core-first-install-commit-rollback runCoreFirstInstallCommitFailureRollbackRegression
sing-box-download-artifacts-cleanup runSingBoxDownloadArtifactsCleanupRegression
network-check-return-failure runNetworkCheckReturnFailureRegression
tls-failure-return runTlsFailureReturnRegression
tls-reinstall-rollback runTlsReinstallRollbackRegression
tls-renew-failure-propagation runTlsRenewalFailurePropagationRegression
wireguard-control-safe-dir runWireGuardControlSafeDirRegression
warp-config-safe-dir runWarpConfigSafeDirRegression
warp-config-file-cleanup runWarpConfigFileCleanupRegression
uninstall-nginx-cleanup runUninstallNginxCleanupRegression
clean-agent-nginx-managed-remove runCleanAgentNginxManagedRemovalRegression
fail2ban-managed-cleanup runFail2banManagedCleanupRegression
fail2ban-apply-transaction runFail2banApplyTransactionRegression
uninstall-wireguard-cleanup runUninstallWireGuardCleanupRegression
wireguard-key-transaction runWireGuardKeyTransactionRegression
uninstall-service-stop-failure runUninstallServiceStopFailureRegression
clean-last-installation-failure runCleanLastInstallationConfigFailureRegression
clean-last-installation-acme-home runCleanLastInstallationConfigAcmeHomeFailureRegression
clean-last-installation-acme-relative-home runCleanLastInstallationConfigResolvesRelativeAcmeHomeRegression
alone-nginx-write-transaction runAloneNginxConfigWriteTransactionRegression
alone-nginx-update-transaction runAloneNginxUpdateTransactionRegression
nginx-service-failure runNginxServiceFailureRegression
EOF

    return "${status}"
}

runLegacyRealityStubsSurviveSuiteLoadContract() {
    declare -f realityTargetDetector | grep -q "fake-xray"
    declare -f currentRealityNetworkProfile | grep -q "203.0.113.10"
    declare -f resolveRealityTargetIPv4 | grep -q "192.0.2.1"
    declare -f lookupRealityTargetAsn | grep -q "AS64501"
}

runLegacyRegressionScriptsRequireDispatcherContract() {
    local root="${TMP_DIR}/legacy-entry-contract"
    local scriptPath
    local outputFile
    local status

    mkdir -p "${root}"
    while IFS= read -r scriptPath; do
        outputFile="${root}/$(basename -- "${scriptPath}").log"
        set +e
        bash "${scriptPath}" "__contract__" >"${outputFile}" 2>&1
        status=$?
        set -e
        [[ "${status}" -eq 2 ]]
        grep -q 'use shell/subscription_groups_regression.sh <selector>' "${outputFile}"
    done <<EOF
${PROJECT_ROOT}/shell/regression/subscription_groups_fast.sh
${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh
${PROJECT_ROOT}/shell/regression/subscription_groups_remote_control.sh
${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state.sh
${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state_full.sh
EOF
}

runRegressionDispatcherContracts() {
    runRegressionStep regression-dispatcher-registry-only runRegressionDispatcherRegistryOnlyContract &&
        runRegressionStep subscription-state-no-implicit-full-fallback runSubscriptionStateNoImplicitFullFallbackContract &&
        runRegressionStep legacy-regression-scripts-require-dispatcher runLegacyRegressionScriptsRequireDispatcherContract &&
        runRegressionStep subscription-state-suite-uses-function-registry runSubscriptionStateSuiteUsesFunctionRegistryContract &&
        runRegressionStep remote-control-suite-uses-function-registry runRemoteControlSuiteUsesFunctionRegistryContract &&
        runRegressionStep remote-control-aggregates-support-source-only runRemoteControlAggregatesSupportSourceOnlyExecutionContract &&
        runRegressionStep fast-suite-uses-function-registry runFastSuiteUsesFunctionRegistryContract &&
        runRegressionStep fast-platform-supports-source-only runFastPlatformSourceOnlyExecutionContract &&
        runRegressionStep legacy-suite-uses-function-registry runLegacySuiteUsesFunctionRegistryContract &&
        runRegressionStep legacy-platform-io-supports-source-only runLegacyPlatformIoSupportsSourceOnlyExecutionContract &&
        runRegressionStep legacy-tls-uses-function-registry runLegacyTlsUsesFunctionRegistryContract &&
        runRegressionStep legacy-direct-leaf-selectors-use-function-registry runLegacyDirectLeafSelectorsUseFunctionRegistryContract &&
        runRegressionStep legacy-reality-stubs-survive-suite-load runLegacyRealityStubsSurviveSuiteLoadContract
}

registerRegressionFunctionLeaf regression-dispatcher-contract runRegressionDispatcherContracts
