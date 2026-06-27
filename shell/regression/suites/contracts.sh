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

runRemoteControlSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/remote-control-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/remote-control-default-selectors.sorted.txt"
    local expectedDefaultSelectorsFile="${TMP_DIR}/remote-control-default-selectors.expected.txt"

    declare -F listRegressionRemoteControlChildSelectors >/dev/null

    listRegressionRemoteControlChildSelectors >"${defaultSelectorsFile}"

    cat <<'EOF' >"${expectedDefaultSelectorsFile}"
remote-control-smoke
remote-control-contract
EOF

    cmp -s "${expectedDefaultSelectorsFile}" "${defaultSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/remote-control-default-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/remote-control-default-selectors.unique.txt"
)

runRemoteControlAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/remote_control.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["remote-control"]:-}

    ! grep -q '^registerRegressionFunctionLeaf remote-control ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateParallel remote-control \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel remote-control runRegressionRemoteControl \\' "${suiteFile}"
    expectedChildren=$(listRegressionRemoteControlChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["remote-control"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["remote-control"]:-}" == "runRegressionRemoteControl" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

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
    local expectedChildren actualChildren

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_LEGACY_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf transaction ' "${suiteFile}"
    grep -q '^registerRegressionAggregateSequential transaction \\' "${suiteFile}"
    grep -q '^    transaction-core \\' "${suiteFile}"
    grep -q '^    transaction-subscription \\' "${suiteFile}"
    grep -q '^    transaction-system$' "${suiteFile}"
    grep -q '^registerRegressionAggregateParallel transaction-system \\' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction-system ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf platform-io ' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf platform-io runRegressionPlatformIo$' "${suiteFile}"
    grep -q '^registerRegressionScriptLeaf "\${selector}" "\${REGRESSION_LEGACY_SCRIPT}" "\${runner}"$' "${suiteFile}"
    grep -q 'if \[\[ "\${PADM_REGRESSION_SOURCE_ONLY:-}" == "1" \]\]; then' "${scriptFile}"
    declare -F listRegressionTransactionSystemChildSelectors >/dev/null
    expectedChildren=$(listRegressionTransactionSystemChildSelectors)
    actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["transaction-system"]:-}
    [[ -n "${expectedChildren}" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
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
routing-core runRoutingRegression
routing-core-unsafe-config-dir runRoutingCoreRejectsUnsafeConfigDirRegression
routing-access-control-config-transaction runAccessControlConfigTransactionRegression
routing-access-control-unsafe-backup-dir runAccessControlRejectsUnsafeBackupDirRegression
routing-access-control-unsafe-config-dir runAccessControlRejectsUnsafeConfigDirRegression
routing-access-control-failure-return runAccessControlFailureReturnRegression
routing-bt-failure-return runBTRoutingFailureReturnRegression
routing-ipv6-failure-return runIPv6RoutingFailureReturnRegression
routing-warp-failure-return runWARPRoutingFailureReturnRegression
routing-socks5-failure-return runSocks5RoutingFailureReturnRegression
routing-dns-failure-return runDNSRoutingFailureReturnRegression
routing-dns-unsafe-backup-dir runDNSRoutingRejectsUnsafeBackupDirRegression
routing-dns-unsafe-config-dir runDNSRoutingRejectsUnsafeConfigDirRegression
routing-dns-restore-scope runDNSRoutingRestoreKeepsUnmanagedSingBoxFilesRegression
routing-port-panel runPortAndPanelHelperRegression
reality-candidates-fast runRealityCandidateFastRegression
reality-asn-scan-plan runRealityAsnScanPlanRegression
reality-candidates-full runRealityCandidateFullRegression
reality-stream-enable runRealityStreamEnableRegression
reality-stream-disable runRealityStreamDisableRegression
runtime-core runRuntimeAndRealityRegression
runtime-autoread-unset-auto-install runAutoReadUnsetAutoInstallRegression
runtime-auto-install-reality-route runAutoInstallRealityRouteRegression
runtime-tempdir runRuntimeTempDirRegression
reality-config runRealityConfigRegression
transaction-subscription runRegressionTransactionSubscription
nginx-service-failure runNginxServiceFailureRegression
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
EOF

    return "${status}"
}

runSubscriptionDirectLeafSelectorsUseFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local status=0

    while read -r selector runner; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}\$" "${suiteFile}" || status=1
    done <<'EOF'
subscription-output runRegressionSubscriptionOutput
subscription-remote-fetch-unique runRemoteSubscribeFetchUniqueRegression
subscription-remote-fetch-rollback runRemoteSubscribeFetchRollbackRegression
subscription-remote-fetch-merge runRemoteSubscribeFetchMergeRegression
subscription-remote-fetch-controlled runRemoteSubscribeFetchControlledRegression
subscription-remote-fetch-append-failure runRemoteSubscribeFetchAppendFailureRegression
subscription-remote-fetch-commit-failure runRemoteSubscribeFetchCommitFailureRegression
subscription-remote-fetch-idempotent runRemoteSubscribeFetchIdempotentRegression
sing-box-subscribe-write runSingBoxSubscribeWriteRegression
cdn-address-write-transaction runCdnAddressTransactionRegression
subscribe-local-output-transaction runSubscribeLocalOutputTransactionRegression
subscribe-salt-write-transaction runSubscribeSaltWriteTransactionRegression
subscribe-server-name runSubscribeServerNameRegression
subscribe-nginx-config-write runSubscribeNginxConfigWriteRegression
subscribe-nginx-service-failure runSubscribeNginxServiceFailureRegression
sing-box-port-failure runSingBoxPortFailureRegression
subscribe-user-output-transaction runSubscribeUserOutputTransactionRegression
subscribe-local-rollback runSubscribeLocalRollbackRegression
subscription-groups-migration-backup runSubscriptionGroupsMigrationBackupRegression
subscription-groups-backup-failure runSubscriptionGroupsBackupFailureRegression
refresh-local-subscriptions-rollback runRefreshLocalSubscriptionsRollbackRegression
subscribe-return-failure runSubscribeReturnFailureRegression
remove-user-subscription-menu-failure runRemoveUserSubscriptionMenuFailureRegression
user-subscription-menu-mutation-failure runUserSubscriptionMenuMutationFailureRegression
EOF

    return "${status}"
}

runUiPublicSelectorsUseFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local status=0

    while read -r selector runner; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}\$" "${suiteFile}" || status=1
    done <<'EOF'
menu-smoke runRegressionMenuSmoke
menu-smoke-full runRegressionMenuSmokeFull
menu-smoke-full-core runMenuSmokeFullCoreRegression
menu-smoke-full-subscription-main runMenuSmokeFullSubscriptionMainRegression
menu-smoke-full-subscription-main-entry runMenuSmokeFullSubscriptionMainEntryRegression
menu-smoke-full-subscription-main-publish runMenuSmokeFullSubscriptionMainPublishRegression
menu-smoke-full-subscription-main-publish-service runMenuSmokeFullSubscriptionMainPublishServiceRegression
menu-smoke-full-subscription-main-publish-user runMenuSmokeFullSubscriptionMainPublishUserRegression
menu-smoke-full-subscription-main-publish-user-empty runMenuSmokeFullSubscriptionMainPublishUserEmptyRegression
menu-smoke-full-subscription-main-publish-user-create runMenuSmokeFullSubscriptionMainPublishUserCreateRegression
menu-smoke-full-subscription-main-publish-user-inspect runMenuSmokeFullSubscriptionMainPublishUserInspectRegression
menu-smoke-full-subscription-main-publish-sync runMenuSmokeFullSubscriptionMainPublishSyncRegression
menu-smoke-full-subscription-main-publish-sync-skip runMenuSmokeFullSubscriptionMainPublishSyncSkipRegression
menu-smoke-full-subscription-main-publish-sync-enable runMenuSmokeFullSubscriptionMainPublishSyncEnableRegression
menu-smoke-full-subscription-main-maintenance runMenuSmokeFullSubscriptionMainMaintenanceRegression
menu-smoke-full-subscription-controlled runMenuSmokeFullSubscriptionControlledRegression
menu-smoke-full-core-maintenance runMenuSmokeFullCoreMaintenanceRegression
wireguard-menu-flow runRegressionWireGuardMenuFlow
wireguard-menu-flow-bootstrap runSubscriptionWireGuardMenuFlowBootstrapRegression
wireguard-menu-flow-peer-transaction runSubscriptionWireGuardMenuFlowPeerTransactionRegression
wireguard-menu-flow-peer-add-update runSubscriptionWireGuardMenuFlowPeerAddUpdateRegression
wireguard-menu-flow-peer-rollback runSubscriptionWireGuardMenuFlowPeerRollbackRegression
wireguard-menu-flow-peer-rollback-apply runSubscriptionWireGuardMenuFlowPeerRollbackApplyRegression
wireguard-menu-flow-peer-rollback-apply-service runSubscriptionWireGuardMenuFlowPeerRollbackApplyServiceRegression
wireguard-menu-flow-peer-rollback-apply-restore runSubscriptionWireGuardMenuFlowPeerRollbackApplyRestoreRegression
wireguard-menu-flow-peer-rollback-source runSubscriptionWireGuardMenuFlowPeerRollbackSourceRegression
wireguard-menu-flow-peer-rollback-credential runSubscriptionWireGuardMenuFlowPeerRollbackCredentialRegression
wireguard-menu-flow-peer-rollback-credential-write runSubscriptionWireGuardMenuFlowPeerRollbackCredentialWriteRegression
wireguard-menu-flow-peer-rollback-credential-groups-restore runSubscriptionWireGuardMenuFlowPeerRollbackCredentialGroupsRestoreRegression
wireguard-menu-flow-peer-source-control runSubscriptionWireGuardMenuFlowPeerSourceControlRegression
wireguard-menu-flow-peer-source-control-toggle runSubscriptionWireGuardMenuFlowPeerSourceControlToggleRegression
wireguard-menu-flow-peer-source-control-clear-error runSubscriptionWireGuardMenuFlowPeerSourceControlClearErrorRegression
wireguard-menu-flow-peer-source-control-status runSubscriptionWireGuardMenuFlowPeerSourceControlStatusRegression
wireguard-menu-flow-control-restore runSubscriptionWireGuardMenuFlowControlRestoreRegression
wireguard-restore-runner runSubscriptionWireGuardRestoreRunnerRegression
EOF

    return "${status}"
}

runUiSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/ui-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/ui-default-selectors.sorted.txt"
    local allProfileSelectorsFile="${TMP_DIR}/ui-all-profile-selectors.txt"
    local allProfileSortedFile="${TMP_DIR}/ui-all-profile-selectors.sorted.txt"
    local expectedDefaultSelectorsFile="${TMP_DIR}/ui-default-selectors.expected.txt"
    local expectedAllProfileSelectorsFile="${TMP_DIR}/ui-all-profile-selectors.expected.txt"

    declare -F listRegressionUiChildSelectors >/dev/null
    declare -F listRegressionUiAllProfileChildSelectors >/dev/null

    listRegressionUiChildSelectors >"${defaultSelectorsFile}"
    listRegressionUiAllProfileChildSelectors >"${allProfileSelectorsFile}"

    cat <<'EOF' >"${expectedDefaultSelectorsFile}"
menu-smoke-full-subscription-main-publish-sync-enable
wireguard-menu-flow-peer-rollback-apply-service
wireguard-menu-flow-peer-rollback-credential-write
wireguard-menu-flow-peer-rollback-source
menu-smoke-full-subscription-main-publish-sync-skip
wireguard-menu-flow-peer-rollback-apply-restore
wireguard-menu-flow-peer-rollback-credential-groups-restore
menu-smoke-full-subscription-main-publish-user-inspect
wireguard-menu-flow-peer-source-control-toggle
menu-smoke-full-subscription-main-publish-user-create
menu-smoke-full-subscription-main-publish-service
wireguard-menu-flow-peer-add-update
wireguard-menu-flow-peer-source-control-clear-error
wireguard-menu-flow-peer-source-control-status
menu-smoke-full-subscription-main-publish-user-empty
menu-smoke-full-subscription-main-maintenance
wireguard-menu-flow-control-restore
wireguard-menu-flow-bootstrap
menu-smoke-full-subscription-main-entry
menu-smoke-full-subscription-controlled
menu-smoke-full-core
menu-smoke-full-core-maintenance
menu-smoke
wireguard-restore-runner
EOF

    cat <<'EOF' >"${expectedAllProfileSelectorsFile}"
menu-smoke-full-subscription-main-publish-sync
wireguard-menu-flow-peer-rollback-apply
wireguard-menu-flow-peer-rollback-credential
wireguard-menu-flow-peer-rollback-source
menu-smoke-full-subscription-main-publish-user
menu-smoke-full-subscription-main-publish-service
wireguard-menu-flow-peer-add-update
wireguard-menu-flow-peer-source-control
menu-smoke-full-subscription-main-maintenance
wireguard-menu-flow-control-restore
wireguard-menu-flow-bootstrap
menu-smoke-full-subscription-main-entry
menu-smoke-full-subscription-controlled
menu-smoke-full-core
menu-smoke-full-core-maintenance
menu-smoke
wireguard-restore-runner
EOF

    cmp -s "${expectedDefaultSelectorsFile}" "${defaultSelectorsFile}"
    cmp -s "${expectedAllProfileSelectorsFile}" "${allProfileSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/ui-default-selectors.unique.txt"
    sort "${allProfileSelectorsFile}" >"${allProfileSortedFile}"
    sort -u "${allProfileSelectorsFile}" >"${TMP_DIR}/ui-all-profile-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/ui-default-selectors.unique.txt"
    cmp -s "${allProfileSortedFile}" "${TMP_DIR}/ui-all-profile-selectors.unique.txt"
)

runUiAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["ui"]:-}

    ! grep -q '^ui ui$' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf ui ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel ui runRegressionUi \\' "${suiteFile}"
    expectedChildren=$(listRegressionUiChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["ui"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["ui"]:-}" == "runRegressionUi" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runRoutingSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/routing-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/routing-default-selectors.sorted.txt"
    local waveSelectorsFile="${TMP_DIR}/routing-wave-selectors.txt"
    local waveSortedFile="${TMP_DIR}/routing-wave-selectors.sorted.txt"

    declare -F listRegressionRoutingChildSelectors >/dev/null
    declare -F listRegressionRoutingCoreChildSelectors >/dev/null
    declare -F listRegressionRoutingHeavyChildSelectors >/dev/null
    declare -F listRegressionRoutingLightChildSelectors >/dev/null

    listRegressionRoutingChildSelectors >"${defaultSelectorsFile}"
    {
        listRegressionRoutingCoreChildSelectors
        listRegressionRoutingHeavyChildSelectors
        listRegressionRoutingLightChildSelectors
    } >"${waveSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/routing-default-selectors.unique.txt"
    sort "${waveSelectorsFile}" >"${waveSortedFile}"
    sort -u "${waveSelectorsFile}" >"${TMP_DIR}/routing-wave-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/routing-default-selectors.unique.txt"
    cmp -s "${waveSortedFile}" "${TMP_DIR}/routing-wave-selectors.unique.txt"
    cmp -s "${TMP_DIR}/routing-default-selectors.unique.txt" "${TMP_DIR}/routing-wave-selectors.unique.txt"
)

runRoutingAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["routing"]:-}

    ! grep -q '^registerRegressionScriptLeaf routing ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf routing ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel routing runRegressionRouting \\' "${suiteFile}"
    expectedChildren=$(listRegressionRoutingChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["routing"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["routing"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["routing"]:-}" == "runRegressionRouting" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runTransactionCoreSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/transaction-core-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/transaction-core-default-selectors.sorted.txt"
    local waveSelectorsFile="${TMP_DIR}/transaction-core-wave-selectors.txt"
    local waveSortedFile="${TMP_DIR}/transaction-core-wave-selectors.sorted.txt"

    declare -F listRegressionTransactionCoreChildSelectors >/dev/null
    declare -F listRegressionTransactionCoreHeavyChildSelectors >/dev/null
    declare -F listRegressionTransactionCoreMediumChildSelectors >/dev/null
    declare -F listRegressionTransactionCoreLightChildSelectors >/dev/null

    listRegressionTransactionCoreChildSelectors >"${defaultSelectorsFile}"
    {
        listRegressionTransactionCoreHeavyChildSelectors
        listRegressionTransactionCoreMediumChildSelectors
        listRegressionTransactionCoreLightChildSelectors
    } >"${waveSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/transaction-core-default-selectors.unique.txt"
    sort "${waveSelectorsFile}" >"${waveSortedFile}"
    sort -u "${waveSelectorsFile}" >"${TMP_DIR}/transaction-core-wave-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/transaction-core-default-selectors.unique.txt"
    cmp -s "${waveSortedFile}" "${TMP_DIR}/transaction-core-wave-selectors.unique.txt"
    cmp -s "${TMP_DIR}/transaction-core-default-selectors.unique.txt" "${TMP_DIR}/transaction-core-wave-selectors.unique.txt"
)

runTransactionCoreRegisteredChildSelectorsAlignedContract() (
    local expectedSelectorsFile="${TMP_DIR}/transaction-core-registered-child-selectors.expected.txt"
    local actualSelectorsFile="${TMP_DIR}/transaction-core-registered-child-selectors.actual.txt"
    local selector

    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        if [[ -n "${PADM_REGRESSION_SELECTOR_KIND["${selector}"]:-}" ]]; then
            printf '%s\n' "${selector}"
        fi
    done < <(listRegressionTransactionCoreChildSelectors) >"${actualSelectorsFile}"

    cat <<'EOF' >"${expectedSelectorsFile}"
core-rollback-result-message
config-transaction
core-port-file-transaction
core-port-unsafe-config-dir
entry-helper-config
check-port-open-nginx-directory-target
alone-nginx-directory-target
xray-reality-port-failure
reality-profile-failure
sing-box-reality-key-transaction
core-template-return-failure
core-template-managed-remove
core-binary-install-copy-failure
sing-box-cronet-rollback
finalize-sing-box-rollback
core-upgrade-directory-target
legacy-core-upgrade-keeps-existing
core-first-install-failure-clean
core-first-install-commit-rollback
core-install-unsafe-binary-path
sing-box-download-artifacts-cleanup
network-check-return-failure
tls-failure-return
tls-reinstall-rollback
tls-renew-failure-propagation
service-queue-apply-propagation
core-install-service-action-failure
sing-box-merge-start-failure
sing-box-merge-config-transaction
sing-box-uninstall-failure-propagation
sing-box-uninstall-rejects-unsafe-config-path
sing-box-managed-cleanup
sing-box-protocol-reload-failure
geo-update-reload-failure
core-cleanup-failure-propagation
reload-core-propagation
sing-box-log-transaction
user-config-write
remove-user
EOF

    cmp -s "${expectedSelectorsFile}" "${actualSelectorsFile}"
)

runTransactionCoreAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["transaction-core"]:-}

    ! grep -q '^registerRegressionScriptLeaf transaction-core ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction-core ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel transaction-core runRegressionTransactionCore \\' "${suiteFile}"
    expectedChildren=$(listRegressionTransactionCoreChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["transaction-core"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["transaction-core"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["transaction-core"]:-}" == "runRegressionTransactionCore" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runSubscriptionSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/subscription-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/subscription-default-selectors.sorted.txt"
    local waveSelectorsFile="${TMP_DIR}/subscription-wave-selectors.txt"
    local waveSortedFile="${TMP_DIR}/subscription-wave-selectors.sorted.txt"

    declare -F listRegressionSubscriptionChildSelectors >/dev/null
    declare -F listRegressionSubscriptionLightChildSelectors >/dev/null
    declare -F listRegressionSubscriptionHeavyChildSelectors >/dev/null

    listRegressionSubscriptionChildSelectors >"${defaultSelectorsFile}"
    {
        listRegressionSubscriptionLightChildSelectors
        listRegressionSubscriptionHeavyChildSelectors
    } >"${waveSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/subscription-default-selectors.unique.txt"
    sort "${waveSelectorsFile}" >"${waveSortedFile}"
    sort -u "${waveSelectorsFile}" >"${TMP_DIR}/subscription-wave-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/subscription-default-selectors.unique.txt"
    cmp -s "${waveSortedFile}" "${TMP_DIR}/subscription-wave-selectors.unique.txt"
    cmp -s "${TMP_DIR}/subscription-default-selectors.unique.txt" "${TMP_DIR}/subscription-wave-selectors.unique.txt"
)

runSubscriptionRemoteFetchRegisteredChildSelectorsAlignedContract() (
    local expectedSelectorsFile="${TMP_DIR}/subscription-remote-fetch-registered-child-selectors.expected.txt"
    local actualSelectorsFile="${TMP_DIR}/subscription-remote-fetch-registered-child-selectors.actual.txt"
    local selector

    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        if [[ -n "${PADM_REGRESSION_SELECTOR_KIND["${selector}"]:-}" ]]; then
            printf '%s\n' "${selector}"
        fi
    done < <(listRegressionSubscriptionRemoteFetchChildSelectors) >"${actualSelectorsFile}"

    cat <<'EOF' >"${expectedSelectorsFile}"
subscription-remote-fetch-unique
subscription-remote-fetch-rollback
subscription-remote-fetch-merge
subscription-remote-fetch-controlled
subscription-remote-fetch-append-failure
subscription-remote-fetch-commit-failure
subscription-remote-fetch-idempotent
EOF

    cmp -s "${expectedSelectorsFile}" "${actualSelectorsFile}"
)

runSubscriptionWriteTransactionRegisteredChildSelectorsAlignedContract() (
    local expectedSelectorsFile="${TMP_DIR}/subscription-write-transaction-registered-child-selectors.expected.txt"
    local actualSelectorsFile="${TMP_DIR}/subscription-write-transaction-registered-child-selectors.actual.txt"
    local selector

    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        if [[ -n "${PADM_REGRESSION_SELECTOR_KIND["${selector}"]:-}" ]]; then
            printf '%s\n' "${selector}"
        fi
    done < <(listRegressionSubscriptionWriteTransactionChildSelectors) >"${actualSelectorsFile}"

    cat <<'EOF' >"${expectedSelectorsFile}"
sing-box-subscribe-write
cdn-address-write-transaction
subscribe-local-output-transaction
subscribe-salt-write-transaction
subscribe-server-name
subscribe-nginx-config-write
subscribe-nginx-service-failure
sing-box-port-failure
subscribe-user-output-transaction
subscribe-local-rollback
subscription-groups-migration-backup
subscription-groups-backup-failure
refresh-local-subscriptions-rollback
subscribe-return-failure
remove-user-subscription-menu-failure
user-subscription-menu-mutation-failure
EOF

    cmp -s "${expectedSelectorsFile}" "${actualSelectorsFile}"
)

runSubscriptionAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["subscription"]:-}

    ! grep -q '^registerRegressionScriptLeaf subscription ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription runRegressionSubscription \\' "${suiteFile}"
    expectedChildren=$(listRegressionSubscriptionChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["subscription"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["subscription"]:-}" == "runRegressionSubscription" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runSubscriptionRemoteFetchAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["subscription-remote-fetch"]:-}

    ! grep -q '^registerRegressionScriptLeaf subscription-remote-fetch ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-remote-fetch ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-remote-fetch runRegressionSubscriptionRemoteFetch \\' "${suiteFile}"
    expectedChildren=$(listRegressionSubscriptionRemoteFetchChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription-remote-fetch"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["subscription-remote-fetch"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["subscription-remote-fetch"]:-}" == "runRegressionSubscriptionRemoteFetch" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runSubscriptionWriteTransactionAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["subscription-write-transaction"]:-}

    ! grep -q '^registerRegressionScriptLeaf subscription-write-transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-write-transaction ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-write-transaction runRegressionSubscriptionWriteTransaction \\' "${suiteFile}"
    expectedChildren=$(listRegressionSubscriptionWriteTransactionChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription-write-transaction"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["subscription-write-transaction"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["subscription-write-transaction"]:-}" == "runRegressionSubscriptionWriteTransaction" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runRealityCandidatesAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["reality-candidates"]:-}

    ! grep -q '^registerRegressionScriptLeaf reality-candidates ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-candidates ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential reality-candidates runRegressionRealityCandidates \\' "${suiteFile}"
    expectedChildren=$(listRegressionRealityCandidatesChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["reality-candidates"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["reality-candidates"]:-}" == "sequential" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["reality-candidates"]:-}" == "runRegressionRealityCandidates" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runRealityCandidatesAggregateRunnerDispatchesChildrenInOrderContract() (
    local callLog="${TMP_DIR}/reality-candidates-aggregate-dispatch.log"

    : >"${callLog}"

    runRealityCandidateFastRegression() {
        printf 'reality-candidates-fast\n' >>"${callLog}"
    }

    runRealityAsnScanPlanRegression() {
        printf 'reality-asn-scan-plan\n' >>"${callLog}"
    }

    runRealityCandidateFullRegression() {
        printf 'reality-candidates-full\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain reality-candidates

    grep -qx 'reality-candidates-fast' "${callLog}"
    grep -qx 'reality-asn-scan-plan' "${callLog}"
    grep -qx 'reality-candidates-full' "${callLog}"
    [[ "$(wc -l <"${callLog}")" -eq 3 ]]
    awk '
        $0 == "reality-candidates-fast" { fastLine = NR }
        $0 == "reality-asn-scan-plan" { asnLine = NR }
        $0 == "reality-candidates-full" { fullLine = NR }
        END { exit !(fastLine && asnLine && fullLine && fastLine < asnLine && asnLine < fullLine) }
    ' "${callLog}"
)

runRealityStreamAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["reality-stream"]:-}

    ! grep -q '^registerRegressionScriptLeaf reality-stream ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-stream ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential reality-stream runRegressionRealityStream \\' "${suiteFile}"
    expectedChildren=$(listRegressionRealityStreamChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["reality-stream"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["reality-stream"]:-}" == "sequential" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["reality-stream"]:-}" == "runRegressionRealityStream" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runRealityStreamAggregateRunnerDispatchesChildrenInOrderContract() (
    local callLog="${TMP_DIR}/reality-stream-aggregate-dispatch.log"

    : >"${callLog}"

    runRealityStreamEnableRegression() {
        printf 'reality-stream-enable\n' >>"${callLog}"
    }

    runRealityStreamDisableRegression() {
        printf 'reality-stream-disable\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain reality-stream

    grep -qx 'reality-stream-enable' "${callLog}"
    grep -qx 'reality-stream-disable' "${callLog}"
    [[ "$(wc -l <"${callLog}")" -eq 2 ]]
    awk '
        $0 == "reality-stream-enable" { enableLine = NR }
        $0 == "reality-stream-disable" { disableLine = NR }
        END { exit !(enableLine && disableLine && enableLine < disableLine) }
    ' "${callLog}"
)

runRuntimeSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/runtime-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/runtime-default-selectors.sorted.txt"
    local waveSelectorsFile="${TMP_DIR}/runtime-wave-selectors.txt"
    local waveSortedFile="${TMP_DIR}/runtime-wave-selectors.sorted.txt"

    declare -F listRegressionRuntimeChildSelectors >/dev/null
    declare -F listRegressionRuntimeLightChildSelectors >/dev/null
    declare -F listRegressionRuntimeHeavyChildSelectors >/dev/null

    listRegressionRuntimeChildSelectors >"${defaultSelectorsFile}"
    {
        listRegressionRuntimeLightChildSelectors
        listRegressionRuntimeHeavyChildSelectors
    } >"${waveSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/runtime-default-selectors.unique.txt"
    sort "${waveSelectorsFile}" >"${waveSortedFile}"
    sort -u "${waveSelectorsFile}" >"${TMP_DIR}/runtime-wave-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/runtime-default-selectors.unique.txt"
    cmp -s "${waveSortedFile}" "${TMP_DIR}/runtime-wave-selectors.unique.txt"
    cmp -s "${TMP_DIR}/runtime-default-selectors.unique.txt" "${TMP_DIR}/runtime-wave-selectors.unique.txt"
)

runRuntimeAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["runtime"]:-}

    ! grep -q '^registerRegressionScriptLeaf runtime ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf runtime ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel runtime runRegressionRuntime \\' "${suiteFile}"
    expectedChildren=$(listRegressionRuntimeChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["runtime"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["runtime"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["runtime"]:-}" == "runRegressionRuntime" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runParallelSelectorCollectsExitedChildWithoutRcContract() (
    local root="${TMP_DIR}/parallel-selector-exit-without-rc"
    local statusFile="${root}/status"
    local callLog="${root}/call.log"
    local workerPid=

    mkdir -p "${root}"
    : >"${callLog}"

    cleanupParallelSelectorExitWithoutRcContract() {
        if [[ -n "${workerPid}" ]]; then
            kill "${workerPid}" 2>/dev/null || true
            wait "${workerPid}" 2>/dev/null || true
        fi
    }
    trap cleanupParallelSelectorExitWithoutRcContract EXIT

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        case "${selector}" in
        exit-fast)
            exit 1
            ;;
        finish)
            sleep 0.1
            ;;
        esac
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    (
        set +e
        PADM_REGRESSION_PARALLEL_JOBS=2 runParallelRegressionSelectors "${root}/orchestration" exit-fast finish
        printf '%s\n' "$?" >"${statusFile}"
    ) &
    workerPid=$!

    for _ in $(seq 1 40); do
        [[ -f "${statusFile}" ]] && break
        sleep 0.05
    done

    [[ -f "${statusFile}" ]]
    wait "${workerPid}"
    workerPid=
    [[ "$(<"${statusFile}")" == "1" ]]
    grep -qx 'finish-start' "${callLog}"
    grep -qx 'finish-finish' "${callLog}"
)

runTransactionCoreCompatibleDispatcherLeavesExecutionContract() (
    local selector

    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain "${selector}"
    done <<'EOF'
core-rollback-result-message
core-port-file-transaction
entry-helper-config
user-config-write
remove-user
EOF
)

runTransactionSystemAggregateDispatchesChildrenExactlyOnceContract() (
    local callLog="${TMP_DIR}/transaction-system-aggregate-dispatch.log"
    local selector

    : >"${callLog}"

    runRegressionAllSelector() {
        printf '%s\n' "$1" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_JOBS=1 PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain transaction-system

    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        grep -qx "${selector}" "${callLog}"
        [[ "$(grep -c "^${selector}$" "${callLog}")" == "1" ]]
    done < <(listRegressionTransactionSystemChildSelectors)
)

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
        runRegressionStep remote-control-selector-helpers-stay-aligned runRemoteControlSelectorHelpersStayAlignedContract &&
        runRegressionStep remote-control-aggregate-runner-registration runRemoteControlAggregateRunnerRegistrationContract &&
        runRegressionStep fast-suite-uses-function-registry runFastSuiteUsesFunctionRegistryContract &&
        runRegressionStep fast-platform-supports-source-only runFastPlatformSourceOnlyExecutionContract &&
        runRegressionStep legacy-suite-uses-function-registry runLegacySuiteUsesFunctionRegistryContract &&
        runRegressionStep legacy-platform-io-supports-source-only runLegacyPlatformIoSupportsSourceOnlyExecutionContract &&
        runRegressionStep legacy-tls-uses-function-registry runLegacyTlsUsesFunctionRegistryContract &&
        runRegressionStep legacy-direct-leaf-selectors-use-function-registry runLegacyDirectLeafSelectorsUseFunctionRegistryContract &&
        runRegressionStep subscription-direct-leaf-selectors-use-function-registry runSubscriptionDirectLeafSelectorsUseFunctionRegistryContract &&
        runRegressionStep ui-public-selectors-use-function-registry runUiPublicSelectorsUseFunctionRegistryContract &&
        runRegressionStep ui-selector-helpers-stay-aligned runUiSelectorHelpersStayAlignedContract &&
        runRegressionStep ui-aggregate-runner-registration runUiAggregateRunnerRegistrationContract &&
        runRegressionStep routing-selector-helpers-stay-aligned runRoutingSelectorHelpersStayAlignedContract &&
        runRegressionStep routing-aggregate-runner-registration runRoutingAggregateRunnerRegistrationContract &&
        runRegressionStep transaction-core-selector-helpers-stay-aligned runTransactionCoreSelectorHelpersStayAlignedContract &&
        runRegressionStep transaction-core-registered-child-selectors-aligned runTransactionCoreRegisteredChildSelectorsAlignedContract &&
        runRegressionStep transaction-core-aggregate-runner-registration runTransactionCoreAggregateRunnerRegistrationContract &&
        runRegressionStep subscription-selector-helpers-stay-aligned runSubscriptionSelectorHelpersStayAlignedContract &&
        runRegressionStep subscription-remote-fetch-registered-child-selectors-aligned runSubscriptionRemoteFetchRegisteredChildSelectorsAlignedContract &&
        runRegressionStep subscription-write-transaction-registered-child-selectors-aligned runSubscriptionWriteTransactionRegisteredChildSelectorsAlignedContract &&
        runRegressionStep subscription-aggregate-runner-registration runSubscriptionAggregateRunnerRegistrationContract &&
        runRegressionStep subscription-remote-fetch-aggregate-runner-registration runSubscriptionRemoteFetchAggregateRunnerRegistrationContract &&
        runRegressionStep subscription-write-transaction-aggregate-runner-registration runSubscriptionWriteTransactionAggregateRunnerRegistrationContract &&
        runRegressionStep reality-candidates-aggregate-runner-registration runRealityCandidatesAggregateRunnerRegistrationContract &&
        runRegressionStep reality-candidates-aggregate-runner-dispatches-children-in-order runRealityCandidatesAggregateRunnerDispatchesChildrenInOrderContract &&
        runRegressionStep reality-stream-aggregate-runner-registration runRealityStreamAggregateRunnerRegistrationContract &&
        runRegressionStep reality-stream-aggregate-runner-dispatches-children-in-order runRealityStreamAggregateRunnerDispatchesChildrenInOrderContract &&
        runRegressionStep runtime-selector-helpers-stay-aligned runRuntimeSelectorHelpersStayAlignedContract &&
        runRegressionStep runtime-aggregate-runner-registration runRuntimeAggregateRunnerRegistrationContract &&
        runRegressionStep parallel-selector-collects-exited-child-without-rc runParallelSelectorCollectsExitedChildWithoutRcContract &&
        runRegressionStep transaction-core-compatible-dispatcher-leaves-execute runTransactionCoreCompatibleDispatcherLeavesExecutionContract &&
        runRegressionStep transaction-system-aggregate-dispatches-children-once runTransactionSystemAggregateDispatchesChildrenExactlyOnceContract &&
        runRegressionStep legacy-reality-stubs-survive-suite-load runLegacyRealityStubsSurviveSuiteLoadContract
}

registerRegressionFunctionLeaf regression-dispatcher-contract runRegressionDispatcherContracts
