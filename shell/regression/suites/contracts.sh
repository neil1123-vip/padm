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

runSubscriptionStateSelectorHelpersStayAlignedContract() (
    local coreSelectorsFile="${TMP_DIR}/subscription-state-core-selectors.txt"
    local coreSortedFile="${TMP_DIR}/subscription-state-core-selectors.sorted.txt"
    local expectedCoreSelectorsFile="${TMP_DIR}/subscription-state-core-selectors.expected.txt"
    local defaultSelectorsFile="${TMP_DIR}/subscription-state-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/subscription-state-default-selectors.sorted.txt"
    local expectedDefaultSelectorsFile="${TMP_DIR}/subscription-state-default-selectors.expected.txt"

    declare -F listRegressionSubscriptionStateCoreChildSelectors >/dev/null
    declare -F listRegressionSubscriptionStateChildSelectors >/dev/null

    listRegressionSubscriptionStateCoreChildSelectors >"${coreSelectorsFile}"
    listRegressionSubscriptionStateChildSelectors >"${defaultSelectorsFile}"

    cat <<'EOF' >"${expectedCoreSelectorsFile}"
subscription-state-structure
subscription-state-quota
subscription-state-remote-restore
EOF

    cat <<'EOF' >"${expectedDefaultSelectorsFile}"
subscription-state-core
subscription-state-support
subscription-state-sync-rollback
EOF

    cmp -s "${expectedCoreSelectorsFile}" "${coreSelectorsFile}"
    cmp -s "${expectedDefaultSelectorsFile}" "${defaultSelectorsFile}"

    sort "${coreSelectorsFile}" >"${coreSortedFile}"
    sort -u "${coreSelectorsFile}" >"${TMP_DIR}/subscription-state-core-selectors.unique.txt"
    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/subscription-state-default-selectors.unique.txt"

    cmp -s "${coreSortedFile}" "${TMP_DIR}/subscription-state-core-selectors.unique.txt"
    cmp -s "${defaultSortedFile}" "${TMP_DIR}/subscription-state-default-selectors.unique.txt"
)

runSubscriptionStateCoreAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription_state.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["subscription-state-core"]:-}

    ! grep -q '^registerRegressionFunctionLeaf subscription-state-core ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateParallel subscription-state-core \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-state-core runRegressionSubscriptionStateCore \\' "${suiteFile}"
    expectedChildren=$(listRegressionSubscriptionStateCoreChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription-state-core"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["subscription-state-core"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["subscription-state-core"]:-}" == "runRegressionSubscriptionStateCore" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runSubscriptionStateAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription_state.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["subscription-state"]:-}

    ! grep -q '^registerRegressionFunctionLeaf subscription-state ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateParallel subscription-state \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-state runRegressionSubscriptionState \\' "${suiteFile}"
    expectedChildren=$(listRegressionSubscriptionStateChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription-state"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["subscription-state"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["subscription-state"]:-}" == "runRegressionSubscriptionState" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
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
    ! grep -q '^registerRegressionAlias remote-control-light remote-control$' "${suiteFile}"

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

runRemoteControlPublicSelectorRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/remote_control.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_remote_control.sh"

    ! grep -q '^registerRegressionAlias remote-control-light remote-control$' "${suiteFile}"
    [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control-smoke"]:-}" == "aggregate" ]]
    [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control-contract"]:-}" == "aggregate" ]]
    [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control-deep"]:-}" == "function" ]]
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["remote-control-light"]:-}" ]]
    ! grep -Eq '^[[:space:]]*remote-control-light\)$' "${scriptFile}"
    ! grep -Fq 'remote-control-light|' "${scriptFile}"
    grep -Fq 'usage: %s [remote-control|remote-control-smoke|remote-control-contract|remote-control-deep]' "${scriptFile}"
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
    ! grep -q '^registerRegressionFunctionLeaf fast-reality ' "${suiteFile}"
    grep -q '^runRegressionFastRealitySuiteRoot() {$' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential fast-reality runRegressionFastRealitySuiteRoot \\' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf platform-hot ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf platform-hot ' "${suiteFile}"
    grep -q 'if \[\[ "\${PADM_REGRESSION_SOURCE_ONLY:-}" == "1" \]\]; then' "${scriptFile}"
}

runPlatformSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/platform.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_PLATFORM_SUITE_DIR}/../subscription_groups_fast.sh"' "${suiteFile}"
    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_PLATFORM_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf platform-hot ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf platform-io ' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf platform-hot runRegressionPlatformSuiteRoot$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf platform-io runRegressionPlatformIoSuiteRoot$' "${suiteFile}"
}

runPlatformPublicSelectorRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/platform.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^registerRegressionFunctionLeaf platform-hot runRegressionPlatformSuiteRoot$' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf platform runRegressionPlatformSuiteRoot$' "${suiteFile}"
    ! grep -Eq '^[[:space:]]*platform\)$' "${legacyFile}"
    grep -Eq '^[[:space:]]*platform-hot\)$' "${legacyFile}"
    ! grep -Fq 'usage: %s [fast|fast-reality|platform|platform-io|' "${legacyFile}"
    grep -Fq 'usage: %s [fast|fast-reality|platform-hot|platform-io|' "${legacyFile}"
}

runFastRealitySelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/fast-reality-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/fast-reality-default-selectors.sorted.txt"
    local expectedDefaultSelectorsFile="${TMP_DIR}/fast-reality-default-selectors.expected.txt"

    declare -F listRegressionFastRealityChildSelectors >/dev/null

    listRegressionFastRealityChildSelectors >"${defaultSelectorsFile}"

    cat <<'EOF' >"${expectedDefaultSelectorsFile}"
fast
reality-candidates-fast
EOF

    cmp -s "${expectedDefaultSelectorsFile}" "${defaultSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/fast-reality-default-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/fast-reality-default-selectors.unique.txt"
)

runFastRealityAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/fast.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["fast-reality"]:-}

    ! grep -q '^registerRegressionScriptLeaf fast-reality ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf fast-reality ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateSequential fast-reality \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential fast-reality runRegressionFastRealitySuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionFastRealityChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["fast-reality"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["fast-reality"]:-}" == "sequential" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["fast-reality"]:-}" == "runRegressionFastRealitySuiteRoot" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runFastPlatformSourceOnlyExecutionContract() (
    local platformSuite="${PROJECT_ROOT}/shell/regression/suites/platform.sh"
    local fastSuite="${PROJECT_ROOT}/shell/regression/suites/fast.sh"

    registerRegressionFunctionLeaf() { :; }
    registerRegressionAggregateRunnerSequential() { :; }
    registerRegressionAggregateRunnerParallel() { :; }
    registerRegressionAggregateSequential() { :; }
    registerRegressionAggregateParallel() { :; }
    registerRegressionAlias() { :; }

    PADM_REGRESSION_SOURCE_ONLY=1 source "${platformSuite}"
    PADM_REGRESSION_SOURCE_ONLY=1 source "${fastSuite}"
    declare -F runRegressionFastSuiteRoot >/dev/null
    declare -F runRegressionPlatformSuiteRoot >/dev/null
    declare -F runRegressionPlatformIoSuiteRoot >/dev/null
)

runFastRealityAggregateRunnerDispatchesChildrenInOrderContract() (
    local callLog="${TMP_DIR}/fast-reality-aggregate-dispatch.log"

    : >"${callLog}"

    runRegressionFastSuiteRoot() {
        printf 'fast\n' >>"${callLog}"
    }

    runRealityCandidateFastRegression() {
        printf 'reality-candidates-fast\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain fast-reality

    grep -qx 'fast' "${callLog}"
    grep -qx 'reality-candidates-fast' "${callLog}"
    [[ "$(wc -l <"${callLog}")" -eq 2 ]]
    awk '
        $0 == "fast" { fastLine = NR }
        $0 == "reality-candidates-fast" { candidateLine = NR }
        END { exit !(fastLine && candidateLine && fastLine < candidateLine) }
    ' "${callLog}"
)

runAllSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/all.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_ALL_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    grep -q '^runRegressionAllSelectorSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionAllSuiteRoot() {$' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf all ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf all ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential all runRegressionAllSuiteRoot \\' "${suiteFile}"
    ! grep -q '^registerRegressionAlias full all$' "${suiteFile}"
    ! grep -q '^registerRegressionAlias ci all$' "${suiteFile}"
}

runAllPublicSelectorRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/all.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    ! grep -q '^registerRegressionAlias full all$' "${suiteFile}"
    ! grep -q '^registerRegressionAlias ci all$' "${suiteFile}"
    [[ "${PADM_REGRESSION_SELECTOR_KIND["all"]:-}" == "aggregate-runner" ]]
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["full"]:-}" ]]
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["ci"]:-}" ]]
    ! grep -Eq '^[[:space:]]*all\|full\|ci\)$' "${legacyFile}"
    grep -Eq '^[[:space:]]*all\)$' "${legacyFile}"
    ! grep -Fq '|all|full|ci]' "${legacyFile}"
    grep -Fq '|remote-control|all]' "${legacyFile}"
}

runLegacySuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local expectedChildren actualChildren

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_LEGACY_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential transaction runRegressionTransaction \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel transaction-system runRegressionTransactionSystem \\' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf platform-io ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf platform-io ' "${suiteFile}"
    grep -q '^registerRegressionScriptLeaf "\${selector}" "\${REGRESSION_LEGACY_SCRIPT}" "\${runner}"$' "${suiteFile}"
    grep -q 'if \[\[ "\${PADM_REGRESSION_SOURCE_ONLY:-}" == "1" \]\]; then' "${scriptFile}"
    declare -F listRegressionTransactionSystemChildSelectors >/dev/null
    declare -F listRegressionTransactionChildSelectors >/dev/null
    expectedChildren=$(listRegressionTransactionSystemChildSelectors)
    actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["transaction-system"]:-}
    [[ -n "${expectedChildren}" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runPlatformSuiteUsesSuiteLocalHelpersContract() (
    local callLog="${TMP_DIR}/platform-suite-root-dispatch.log"

    : >"${callLog}"

    runRegressionPlatform() {
        printf 'legacy-platform-hot\n' >>"${callLog}"
        return 97
    }

    runRegressionPlatformSuiteRoot() {
        printf 'suite-platform-hot\n' >>"${callLog}"
    }

    runRegressionPlatformIo() {
        printf 'legacy-platform-io\n' >>"${callLog}"
        return 97
    }

    runRegressionPlatformIoSuiteRoot() {
        printf 'suite-platform-io\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain platform-hot
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain platform-io

    grep -qx 'suite-platform-hot' "${callLog}"
    grep -qx 'suite-platform-io' "${callLog}"
    ! grep -q '^legacy-platform-hot$' "${callLog}"
    ! grep -q '^legacy-platform-io$' "${callLog}"
)

runTlsSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/tls.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_TLS_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    grep -q '^runRegressionTlsSuiteRoot() {$' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf tls ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf tls ' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf tls-failure-return runTlsFailureReturnRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf tls-reinstall-rollback runTlsReinstallRollbackRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf tls-renew-failure-propagation runTlsRenewalFailurePropagationRegression$' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential tls runRegressionTlsSuiteRoot \\' "${suiteFile}"
}

runTlsSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/tls-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/tls-default-selectors.sorted.txt"
    local expectedDefaultSelectorsFile="${TMP_DIR}/tls-default-selectors.expected.txt"

    declare -F listRegressionTlsChildSelectors >/dev/null

    listRegressionTlsChildSelectors >"${defaultSelectorsFile}"

    cat <<'EOF' >"${expectedDefaultSelectorsFile}"
tls-failure-return
tls-reinstall-rollback
tls-renew-failure-propagation
EOF

    cmp -s "${expectedDefaultSelectorsFile}" "${defaultSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/tls-default-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/tls-default-selectors.unique.txt"
)

runTlsAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/tls.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["tls"]:-}

    ! grep -q '^registerRegressionScriptLeaf tls ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf tls ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateSequential tls \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential tls runRegressionTlsSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionTlsChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["tls"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["tls"]:-}" == "sequential" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["tls"]:-}" == "runRegressionTlsSuiteRoot" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runTlsAggregateRunnerUsesSuiteLocalHelperContract() (
    local callLog="${TMP_DIR}/tls-aggregate-suite-root-dispatch.log"

    : >"${callLog}"

    runRegressionTls() {
        printf 'legacy-tls\n' >>"${callLog}"
        return 97
    }

    runRegressionTlsSuiteRoot() {
        printf 'suite-tls\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain tls

    grep -qx 'suite-tls' "${callLog}"
    ! grep -q '^legacy-tls$' "${callLog}"
)

runLegacyDirectLeafSelectorsUseFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local status=0

    while read -r selector runner; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}\$" "${suiteFile}" || status=1
    done <<'EOF'
transaction-subscription runRegressionTransactionSubscription
nginx-service-failure runNginxServiceFailureRegression
config-transaction runConfigTransactionRegression
core-port-unsafe-config-dir runCorePortRejectsUnsafeConfigDirRegression
check-port-open-nginx-directory-target runCheckPortOpenNginxRejectsDirectoryTargetRegression
alone-nginx-directory-target runAloneNginxRejectsDirectoryTargetRegression
sing-box-managed-cleanup runSingBoxManagedCleanupRegression
xray-reality-port-failure runXrayRealityPortFailureRegression
sing-box-reality-key-transaction runSingBoxRealityKeyTransactionRegression
core-template-managed-remove runCoreTemplateManagedConfigRemovalRegression
core-template-return-failure runCoreTemplateReturnFailureRegression
core-binary-install-copy-failure runCoreBinaryInstallCopyFailureRegression
sing-box-cronet-rollback runSingBoxCronetRollbackRegression
finalize-sing-box-rollback runFinalizeSingBoxBinaryInstallRollbackRegression
service-queue-apply-propagation runServiceQueueApplyPropagationRegression
core-install-service-action-failure runCoreInstallServiceActionFailureRegression
sing-box-merge-start-failure runSingBoxMergeStartFailureRegression
sing-box-merge-config-transaction runSingBoxMergeConfigTransactionRegression
sing-box-uninstall-rejects-unsafe-config-path runSingBoxUninstallRejectsUnsafeConfigPathRegression
sing-box-uninstall-failure-propagation runSingBoxUninstallFailurePropagationRegression
sing-box-protocol-reload-failure runSingBoxProtocolReloadFailureRegression
geo-update-reload-failure runGeoUpdateReloadFailureRegression
core-cleanup-failure-propagation runCoreCleanupFailurePropagationRegression
reload-core-propagation runReloadCorePropagationRegression
sing-box-log-transaction runSingBoxLogTransactionRegression
core-upgrade-directory-target runCoreUpgradeRejectsDirectoryTargetRegression
legacy-core-upgrade-keeps-existing runLegacyCoreUpgradeKeepsExistingBinaryRegression
core-first-install-failure-clean runCoreFirstInstallLeavesNoLiveArtifactsOnFailureRegression
core-install-unsafe-binary-path runCoreInstallRejectsUnsafeBinaryPathRegression
core-first-install-commit-rollback runCoreFirstInstallCommitFailureRollbackRegression
sing-box-download-artifacts-cleanup runSingBoxDownloadArtifactsCleanupRegression
network-check-return-failure runNetworkCheckReturnFailureRegression
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
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
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

runSubscriptionCompositionLeafSelectorsUseFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local status=0

    while read -r selector runner; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}\$" "${suiteFile}" || status=1
    done <<'EOF'
regression-subscription-parallel-composition runRegressionSubscriptionParallelCompositionRegression
regression-subscription-write-transaction-parallel-composition runRegressionSubscriptionWriteTransactionParallelCompositionRegression
regression-subscription-remote-fetch-parallel-composition runRegressionSubscriptionRemoteFetchParallelCompositionRegression
EOF

    return "${status}"
}

runSubscriptionSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_SUBSCRIPTION_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    grep -q '^runRegressionSubscriptionSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionSubscriptionRemoteFetchSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionSubscriptionWriteTransactionSuiteRoot() {$' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription-remote ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-remote ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription-tx ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-tx ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription-remote-fetch ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-remote-fetch ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription-write-transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-write-transaction ' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf subscription-output runRegressionSubscriptionOutput$' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-remote runRegressionSubscriptionRemoteFetchSuiteRoot \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-tx runRegressionSubscriptionWriteTransactionSuiteRoot \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription runRegressionSubscriptionSuiteRoot \\' "${suiteFile}"
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription-remote"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription-tx"]:-}" == "aggregate-runner" ]]
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["subscription-remote-fetch"]:-}" ]]
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["subscription-write-transaction"]:-}" ]]
}

runUiPublicSelectorsUseFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/ui.sh"
    local status=0

    ! grep -q '^registerRegressionScriptLeaf menu-smoke ' "${suiteFile}" || status=1
    ! grep -q '^registerRegressionFunctionLeaf menu-smoke ' "${suiteFile}" || status=1
    ! grep -q '^registerRegressionScriptLeaf menu-smoke-full ' "${suiteFile}" || status=1
    ! grep -q '^registerRegressionFunctionLeaf menu-smoke-full ' "${suiteFile}" || status=1

    while read -r selector runner; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}\$" "${suiteFile}" || status=1
    done <<'EOF'
ui-smoke runRegressionMenuSmoke
ui-full runRegressionMenuSmokeFull
ui-full-core runMenuSmokeFullCoreRegression
ui-full-subscription-main runMenuSmokeFullSubscriptionMainRegression
ui-full-subscription-main-entry runMenuSmokeFullSubscriptionMainEntryRegression
ui-full-subscription-main-publish runMenuSmokeFullSubscriptionMainPublishRegression
ui-full-subscription-main-publish-service runMenuSmokeFullSubscriptionMainPublishServiceRegression
ui-full-subscription-main-publish-user runMenuSmokeFullSubscriptionMainPublishUserRegression
ui-full-subscription-main-publish-user-empty runMenuSmokeFullSubscriptionMainPublishUserEmptyRegression
ui-full-subscription-main-publish-user-create runMenuSmokeFullSubscriptionMainPublishUserCreateRegression
ui-full-subscription-main-publish-user-inspect runMenuSmokeFullSubscriptionMainPublishUserInspectRegression
ui-full-subscription-main-publish-sync runMenuSmokeFullSubscriptionMainPublishSyncRegression
ui-full-subscription-main-publish-sync-skip runMenuSmokeFullSubscriptionMainPublishSyncSkipRegression
ui-full-subscription-main-publish-sync-enable runMenuSmokeFullSubscriptionMainPublishSyncEnableRegression
ui-full-subscription-main-maintenance runMenuSmokeFullSubscriptionMainMaintenanceRegression
ui-full-subscription-controlled runMenuSmokeFullSubscriptionControlledRegression
ui-full-core-maintenance runMenuSmokeFullCoreMaintenanceRegression
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

    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-smoke"]:-}" == "function" ]] || status=1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-full"]:-}" == "function" ]] || status=1
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["menu-smoke"]:-}" ]] || status=1
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["menu-smoke-full"]:-}" ]] || status=1

    return "${status}"
}

runUiSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/ui.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_UI_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    grep -q '^runRegressionUiSuiteRoot() {$' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf ui ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf ui ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf menu-smoke ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf menu-smoke ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf menu-smoke-full ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf menu-smoke-full ' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf ui-smoke runRegressionMenuSmoke$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf ui-full runRegressionMenuSmokeFull$' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel ui runRegressionUiSuiteRoot \\' "${suiteFile}"
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-smoke"]:-}" == "function" ]]
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-full"]:-}" == "function" ]]
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["menu-smoke"]:-}" ]]
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["menu-smoke-full"]:-}" ]]
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
ui-full-subscription-main-publish-sync-enable
wireguard-menu-flow-peer-rollback-apply-service
wireguard-menu-flow-peer-rollback-credential-write
wireguard-menu-flow-peer-rollback-source
ui-full-subscription-main-publish-sync-skip
wireguard-menu-flow-peer-rollback-apply-restore
wireguard-menu-flow-peer-rollback-credential-groups-restore
ui-full-subscription-main-publish-user-inspect
wireguard-menu-flow-peer-source-control-toggle
ui-full-subscription-main-publish-user-create
ui-full-subscription-main-publish-service
wireguard-menu-flow-peer-add-update
wireguard-menu-flow-peer-source-control-clear-error
wireguard-menu-flow-peer-source-control-status
ui-full-subscription-main-publish-user-empty
ui-full-subscription-main-maintenance
wireguard-menu-flow-control-restore
wireguard-menu-flow-bootstrap
ui-full-subscription-main-entry
ui-full-subscription-controlled
ui-full-core
ui-full-core-maintenance
ui-smoke
wireguard-restore-runner
EOF

    cat <<'EOF' >"${expectedAllProfileSelectorsFile}"
ui-full-subscription-main-publish-sync
wireguard-menu-flow-peer-rollback-apply
wireguard-menu-flow-peer-rollback-credential
wireguard-menu-flow-peer-rollback-source
ui-full-subscription-main-publish-user
ui-full-subscription-main-publish-service
wireguard-menu-flow-peer-add-update
wireguard-menu-flow-peer-source-control
ui-full-subscription-main-maintenance
wireguard-menu-flow-control-restore
wireguard-menu-flow-bootstrap
ui-full-subscription-main-entry
ui-full-subscription-controlled
ui-full-core
ui-full-core-maintenance
ui-smoke
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
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/ui.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["ui"]:-}

    ! grep -q '^ui ui$' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf ui ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf menu-smoke ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf menu-smoke-full ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel ui runRegressionUiSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionUiChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["ui"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["ui"]:-}" == "runRegressionUiSuiteRoot" ]]
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-smoke"]:-}" == "function" ]]
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-full"]:-}" == "function" ]]
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["menu-smoke"]:-}" ]]
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["menu-smoke-full"]:-}" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runUiAggregateRunnerUsesSuiteLocalHelperContract() (
    local callLog="${TMP_DIR}/ui-aggregate-suite-root-dispatch.log"

    : >"${callLog}"

    runRegressionUi() {
        printf 'legacy-ui\n' >>"${callLog}"
        return 97
    }

    runRegressionUiSuiteRoot() {
        printf 'suite-ui\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain ui

    grep -qx 'suite-ui' "${callLog}"
    ! grep -q '^legacy-ui$' "${callLog}"
)

runRoutingSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/routing.sh"
    local status=0

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_ROUTING_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}" || status=1
    grep -q '^runRegressionRoutingSuiteRoot() {$' "${suiteFile}" || status=1
    ! grep -q '^registerRegressionScriptLeaf routing ' "${suiteFile}" || status=1
    ! grep -q '^registerRegressionFunctionLeaf routing ' "${suiteFile}" || status=1
    grep -q '^registerRegressionAggregateRunnerParallel routing runRegressionRoutingSuiteRoot \\' "${suiteFile}" || status=1

    while read -r selector runner; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}\$" "${suiteFile}" || status=1
    done <<'EOF'
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
EOF

    return "${status}"
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
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/routing.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["routing"]:-}

    ! grep -q '^registerRegressionScriptLeaf routing ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf routing ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel routing runRegressionRoutingSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionRoutingChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["routing"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["routing"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["routing"]:-}" == "runRegressionRoutingSuiteRoot" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runRoutingAggregateRunnerUsesSuiteLocalHelperContract() (
    local callLog="${TMP_DIR}/routing-aggregate-suite-root-dispatch.log"

    : >"${callLog}"

    runRegressionRouting() {
        printf 'legacy-routing\n' >>"${callLog}"
        return 97
    }

    runRegressionRoutingSuiteRoot() {
        printf 'suite-routing\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain routing

    grep -qx 'suite-routing' "${callLog}"
    ! grep -q '^legacy-routing$' "${callLog}"
)

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
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
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

runTransactionSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/transaction-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/transaction-default-selectors.sorted.txt"
    local expectedDefaultSelectorsFile="${TMP_DIR}/transaction-default-selectors.expected.txt"
    local systemSelectorsFile="${TMP_DIR}/transaction-system-selectors.txt"
    local systemSortedFile="${TMP_DIR}/transaction-system-selectors.sorted.txt"

    declare -F listRegressionTransactionChildSelectors >/dev/null
    declare -F listRegressionTransactionSystemChildSelectors >/dev/null

    listRegressionTransactionChildSelectors >"${defaultSelectorsFile}"
    listRegressionTransactionSystemChildSelectors >"${systemSelectorsFile}"

    cat <<'EOF' >"${expectedDefaultSelectorsFile}"
transaction-core
transaction-subscription
transaction-system
EOF

    cmp -s "${expectedDefaultSelectorsFile}" "${defaultSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/transaction-default-selectors.unique.txt"
    sort "${systemSelectorsFile}" >"${systemSortedFile}"
    sort -u "${systemSelectorsFile}" >"${TMP_DIR}/transaction-system-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/transaction-default-selectors.unique.txt"
    cmp -s "${systemSortedFile}" "${TMP_DIR}/transaction-system-selectors.unique.txt"
)

runTransactionAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["transaction"]:-}

    ! grep -q '^registerRegressionScriptLeaf transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateSequential transaction \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential transaction runRegressionTransaction \\' "${suiteFile}"
    expectedChildren=$(listRegressionTransactionChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["transaction"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["transaction"]:-}" == "sequential" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["transaction"]:-}" == "runRegressionTransaction" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runTransactionSystemAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["transaction-system"]:-}

    ! grep -q '^registerRegressionScriptLeaf transaction-system ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction-system ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateParallel transaction-system \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel transaction-system runRegressionTransactionSystem \\' "${suiteFile}"
    expectedChildren=$(listRegressionTransactionSystemChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["transaction-system"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["transaction-system"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["transaction-system"]:-}" == "runRegressionTransactionSystem" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runTransactionSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_TRANSACTION_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    grep -q '^listRegressionTransactionChildSelectors() {$' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf transaction-core ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction-core ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf transaction-system ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction-system ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel transaction-core runRegressionTransactionCore \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel transaction-system runRegressionTransactionSystem \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential transaction runRegressionTransaction \\' "${suiteFile}"
}

runTransactionSuiteUsesSuiteLocalHelpersContract() (
    local callLog="${TMP_DIR}/transaction-suite-root-dispatch.log"

    : >"${callLog}"

    runRegressionTransaction() {
        printf 'suite-transaction\n' >>"${callLog}"
    }

    runRegressionTransactionCore() {
        printf 'suite-transaction-core\n' >>"${callLog}"
    }

    runRegressionTransactionSystem() {
        printf 'suite-transaction-system\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain transaction
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain transaction-core
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain transaction-system

    grep -qx 'suite-transaction' "${callLog}"
    grep -qx 'suite-transaction-core' "${callLog}"
    grep -qx 'suite-transaction-system' "${callLog}"
)

runAllSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/all-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/all-default-selectors.sorted.txt"
    local expectedDefaultSelectorsFile="${TMP_DIR}/all-default-selectors.expected.txt"

    declare -F listRegressionAllChildSelectors >/dev/null

    listRegressionAllChildSelectors >"${defaultSelectorsFile}"

    cat <<'EOF' >"${expectedDefaultSelectorsFile}"
routing
subscription
runtime
transaction
remote-control
ui
EOF

    cmp -s "${expectedDefaultSelectorsFile}" "${defaultSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/all-default-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/all-default-selectors.unique.txt"
)

runAllAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/all.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["all"]:-}

    ! grep -q '^registerRegressionScriptLeaf all ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf all ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateSequential all \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential all runRegressionAllSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionAllChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["all"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["all"]:-}" == "sequential" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["all"]:-}" == "runRegressionAllSuiteRoot" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runAllAggregateRunnerUsesSuiteLocalDispatchHelperContract() (
    local callLog="${TMP_DIR}/all-aggregate-suite-root-dispatch.log"

    : >"${callLog}"

    runParallelRegressionSelectors() {
        printf 'parallel:%s\n' "$*" >>"${callLog}"
    }

    runRegressionAllSelector() {
        printf 'legacy-helper:%s\n' "$1" >>"${callLog}"
        return 97
    }

    runRegressionAllSelectorSuiteRoot() {
        printf 'suite-helper:%s\n' "$1" >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain all

    grep -qx 'parallel:'"${TMP_DIR}"'/all-parallel-[0-9][0-9]* subscription ui transaction-core routing runtime remote-control-smoke remote-control-contract-service-install' "${callLog}"
    grep -qx 'suite-helper:transaction-system' "${callLog}"
    grep -qx 'suite-helper:remote-control-contract-server-response' "${callLog}"
    ! grep -q '^legacy-helper:' "${callLog}"
)

runRuntimeSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/runtime.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_RUNTIME_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    grep -q '^runRegressionRuntimeSuiteRoot() {$' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf runtime ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf runtime ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel runtime runRegressionRuntimeSuiteRoot \\' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf runtime-core runRuntimeAndRealityRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf runtime-autoread-unset-auto-install runAutoReadUnsetAutoInstallRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf runtime-auto-install-reality-route runAutoInstallRealityRouteRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf runtime-tempdir runRuntimeTempDirRegression$' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-candidates-fast ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-asn-scan-plan ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-candidates-full ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-stream-enable ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-stream-disable ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-config ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-profile-failure ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateRunnerSequential reality-candidates ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateRunnerSequential reality-stream ' "${suiteFile}"
}

runRealitySuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/reality.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_REALITY_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    grep -q '^runRegressionRealityCandidatesSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionRealityStreamSuiteRoot() {$' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf reality-candidates ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-candidates ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf reality-stream ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-stream ' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf reality-candidates-fast runRealityCandidateFastRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf reality-asn-scan-plan runRealityAsnScanPlanRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf reality-candidates-full runRealityCandidateFullRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf reality-stream-enable runRealityStreamEnableRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf reality-stream-disable runRealityStreamDisableRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf reality-config runRealityConfigRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf reality-profile-failure runRealityProfileFailureRegression$' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential reality-candidates runRegressionRealityCandidatesSuiteRoot \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential reality-stream runRegressionRealityStreamSuiteRoot \\' "${suiteFile}"
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

runSubscriptionRemoteRegisteredChildSelectorsAlignedContract() (
    local expectedSelectorsFile="${TMP_DIR}/subscription-remote-registered-child-selectors.expected.txt"
    local actualSelectorsFile="${TMP_DIR}/subscription-remote-registered-child-selectors.actual.txt"
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

runSubscriptionTxRegisteredChildSelectorsAlignedContract() (
    local expectedSelectorsFile="${TMP_DIR}/subscription-tx-registered-child-selectors.expected.txt"
    local actualSelectorsFile="${TMP_DIR}/subscription-tx-registered-child-selectors.actual.txt"
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
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["subscription"]:-}

    ! grep -q '^registerRegressionScriptLeaf subscription ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription runRegressionSubscriptionSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionSubscriptionChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["subscription"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["subscription"]:-}" == "runRegressionSubscriptionSuiteRoot" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runSubscriptionRemoteAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["subscription-remote"]:-}

    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["subscription-remote-fetch"]:-}" ]]
    ! grep -q '^registerRegressionScriptLeaf subscription-remote ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-remote ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription-remote-fetch ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-remote-fetch ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-remote runRegressionSubscriptionRemoteFetchSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionSubscriptionRemoteFetchChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription-remote"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["subscription-remote"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["subscription-remote"]:-}" == "runRegressionSubscriptionRemoteFetchSuiteRoot" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runSubscriptionTxAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["subscription-tx"]:-}

    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["subscription-write-transaction"]:-}" ]]
    ! grep -q '^registerRegressionScriptLeaf subscription-tx ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-tx ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription-write-transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-write-transaction ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-tx runRegressionSubscriptionWriteTransactionSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionSubscriptionWriteTransactionChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription-tx"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["subscription-tx"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["subscription-tx"]:-}" == "runRegressionSubscriptionWriteTransactionSuiteRoot" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runSubscriptionAggregateRunnersUseSuiteLocalHelpersContract() (
    local callLog="${TMP_DIR}/subscription-suite-root-dispatch.log"

    : >"${callLog}"

    runRegressionSubscription() {
        printf 'legacy-subscription\n' >>"${callLog}"
        return 97
    }

    runRegressionSubscriptionRemoteFetch() {
        printf 'legacy-subscription-remote\n' >>"${callLog}"
        return 97
    }

    runRegressionSubscriptionWriteTransaction() {
        printf 'legacy-subscription-tx\n' >>"${callLog}"
        return 97
    }

    runRegressionSubscriptionSuiteRoot() {
        printf 'suite-subscription\n' >>"${callLog}"
    }

    runRegressionSubscriptionRemoteFetchSuiteRoot() {
        printf 'suite-subscription-remote\n' >>"${callLog}"
    }

    runRegressionSubscriptionWriteTransactionSuiteRoot() {
        printf 'suite-subscription-tx\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain subscription
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain subscription-remote
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain subscription-tx

    grep -qx 'suite-subscription' "${callLog}"
    grep -qx 'suite-subscription-remote' "${callLog}"
    grep -qx 'suite-subscription-tx' "${callLog}"
    ! grep -q '^legacy-subscription$' "${callLog}"
    ! grep -q '^legacy-subscription-remote$' "${callLog}"
    ! grep -q '^legacy-subscription-tx$' "${callLog}"
)

runRealityCandidatesAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/reality.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["reality-candidates"]:-}

    ! grep -q '^registerRegressionScriptLeaf reality-candidates ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-candidates ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential reality-candidates runRegressionRealityCandidatesSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionRealityCandidatesChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["reality-candidates"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["reality-candidates"]:-}" == "sequential" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["reality-candidates"]:-}" == "runRegressionRealityCandidatesSuiteRoot" ]]
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
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/reality.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["reality-stream"]:-}

    ! grep -q '^registerRegressionScriptLeaf reality-stream ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-stream ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential reality-stream runRegressionRealityStreamSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionRealityStreamChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["reality-stream"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["reality-stream"]:-}" == "sequential" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["reality-stream"]:-}" == "runRegressionRealityStreamSuiteRoot" ]]
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
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/runtime.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["runtime"]:-}

    ! grep -q '^registerRegressionScriptLeaf runtime ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf runtime ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel runtime runRegressionRuntimeSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionRuntimeChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["runtime"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["runtime"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["runtime"]:-}" == "runRegressionRuntimeSuiteRoot" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runRuntimeAggregateRunnerUsesSuiteLocalHelperContract() (
    local callLog="${TMP_DIR}/runtime-aggregate-suite-root-dispatch.log"

    : >"${callLog}"

    runRegressionRuntime() {
        printf 'legacy-runtime\n' >>"${callLog}"
        return 97
    }

    runRegressionRuntimeSuiteRoot() {
        printf 'suite-runtime\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain runtime

    grep -qx 'suite-runtime' "${callLog}"
    ! grep -q '^legacy-runtime$' "${callLog}"
)

runRealityAggregateRunnersUseSuiteLocalHelpersContract() (
    local callLog="${TMP_DIR}/reality-aggregate-suite-root-dispatch.log"

    : >"${callLog}"

    runRegressionRealityCandidates() {
        printf 'legacy-reality-candidates\n' >>"${callLog}"
        return 97
    }

    runRegressionRealityCandidatesSuiteRoot() {
        printf 'suite-reality-candidates\n' >>"${callLog}"
    }

    runRegressionRealityStream() {
        printf 'legacy-reality-stream\n' >>"${callLog}"
        return 97
    }

    runRegressionRealityStreamSuiteRoot() {
        printf 'suite-reality-stream\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain reality-candidates
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain reality-stream

    grep -qx 'suite-reality-candidates' "${callLog}"
    grep -qx 'suite-reality-stream' "${callLog}"
    ! grep -q '^legacy-reality-candidates$' "${callLog}"
    ! grep -q '^legacy-reality-stream$' "${callLog}"
)

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
        runRegressionStep subscription-state-selector-helpers-stay-aligned runSubscriptionStateSelectorHelpersStayAlignedContract &&
        runRegressionStep subscription-state-core-aggregate-runner-registration runSubscriptionStateCoreAggregateRunnerRegistrationContract &&
        runRegressionStep subscription-state-aggregate-runner-registration runSubscriptionStateAggregateRunnerRegistrationContract &&
        runRegressionStep remote-control-suite-uses-function-registry runRemoteControlSuiteUsesFunctionRegistryContract &&
        runRegressionStep remote-control-public-selector-retirement runRemoteControlPublicSelectorRetirementContract &&
        runRegressionStep remote-control-aggregates-support-source-only runRemoteControlAggregatesSupportSourceOnlyExecutionContract &&
        runRegressionStep remote-control-selector-helpers-stay-aligned runRemoteControlSelectorHelpersStayAlignedContract &&
        runRegressionStep remote-control-aggregate-runner-registration runRemoteControlAggregateRunnerRegistrationContract &&
        runRegressionStep fast-suite-uses-function-registry runFastSuiteUsesFunctionRegistryContract &&
        runRegressionStep fast-reality-selector-helpers-stay-aligned runFastRealitySelectorHelpersStayAlignedContract &&
        runRegressionStep fast-reality-aggregate-runner-registration runFastRealityAggregateRunnerRegistrationContract &&
        runRegressionStep fast-reality-aggregate-runner-dispatches-children-in-order runFastRealityAggregateRunnerDispatchesChildrenInOrderContract &&
        runRegressionStep platform-suite-uses-function-registry runPlatformSuiteUsesFunctionRegistryContract &&
        runRegressionStep platform-public-selector-retirement runPlatformPublicSelectorRetirementContract &&
        runRegressionStep all-suite-uses-function-registry runAllSuiteUsesFunctionRegistryContract &&
        runRegressionStep all-public-selector-retirement runAllPublicSelectorRetirementContract &&
        runRegressionStep fast-platform-supports-source-only runFastPlatformSourceOnlyExecutionContract &&
        runRegressionStep legacy-suite-uses-function-registry runLegacySuiteUsesFunctionRegistryContract &&
        runRegressionStep platform-suite-uses-suite-local-helpers runPlatformSuiteUsesSuiteLocalHelpersContract &&
        runRegressionStep tls-suite-uses-function-registry runTlsSuiteUsesFunctionRegistryContract &&
        runRegressionStep tls-selector-helpers-stay-aligned runTlsSelectorHelpersStayAlignedContract &&
        runRegressionStep tls-aggregate-runner-registration runTlsAggregateRunnerRegistrationContract &&
        runRegressionStep tls-aggregate-runner-uses-suite-local-helper runTlsAggregateRunnerUsesSuiteLocalHelperContract &&
        runRegressionStep legacy-direct-leaf-selectors-use-function-registry runLegacyDirectLeafSelectorsUseFunctionRegistryContract &&
        runRegressionStep subscription-direct-leaf-selectors-use-function-registry runSubscriptionDirectLeafSelectorsUseFunctionRegistryContract &&
        runRegressionStep subscription-composition-leaf-selectors-use-function-registry runSubscriptionCompositionLeafSelectorsUseFunctionRegistryContract &&
        runRegressionStep ui-suite-uses-function-registry runUiSuiteUsesFunctionRegistryContract &&
        runRegressionStep ui-public-selectors-use-function-registry runUiPublicSelectorsUseFunctionRegistryContract &&
        runRegressionStep ui-selector-helpers-stay-aligned runUiSelectorHelpersStayAlignedContract &&
        runRegressionStep ui-aggregate-runner-registration runUiAggregateRunnerRegistrationContract &&
        runRegressionStep ui-aggregate-runner-uses-suite-local-helper runUiAggregateRunnerUsesSuiteLocalHelperContract &&
        runRegressionStep routing-suite-uses-function-registry runRoutingSuiteUsesFunctionRegistryContract &&
        runRegressionStep routing-selector-helpers-stay-aligned runRoutingSelectorHelpersStayAlignedContract &&
        runRegressionStep routing-aggregate-runner-registration runRoutingAggregateRunnerRegistrationContract &&
        runRegressionStep routing-aggregate-runner-uses-suite-local-helper runRoutingAggregateRunnerUsesSuiteLocalHelperContract &&
        runRegressionStep transaction-suite-uses-function-registry runTransactionSuiteUsesFunctionRegistryContract &&
        runRegressionStep transaction-core-selector-helpers-stay-aligned runTransactionCoreSelectorHelpersStayAlignedContract &&
        runRegressionStep transaction-core-registered-child-selectors-aligned runTransactionCoreRegisteredChildSelectorsAlignedContract &&
        runRegressionStep transaction-core-aggregate-runner-registration runTransactionCoreAggregateRunnerRegistrationContract &&
        runRegressionStep transaction-selector-helpers-stay-aligned runTransactionSelectorHelpersStayAlignedContract &&
        runRegressionStep transaction-aggregate-runner-registration runTransactionAggregateRunnerRegistrationContract &&
        runRegressionStep transaction-system-aggregate-runner-registration runTransactionSystemAggregateRunnerRegistrationContract &&
        runRegressionStep transaction-suite-uses-suite-local-helpers runTransactionSuiteUsesSuiteLocalHelpersContract &&
        runRegressionStep all-selector-helpers-stay-aligned runAllSelectorHelpersStayAlignedContract &&
        runRegressionStep all-aggregate-runner-registration runAllAggregateRunnerRegistrationContract &&
        runRegressionStep all-aggregate-runner-uses-suite-local-dispatch-helper runAllAggregateRunnerUsesSuiteLocalDispatchHelperContract &&
        runRegressionStep subscription-suite-uses-function-registry runSubscriptionSuiteUsesFunctionRegistryContract &&
        runRegressionStep subscription-selector-helpers-stay-aligned runSubscriptionSelectorHelpersStayAlignedContract &&
        runRegressionStep subscription-remote-registered-child-selectors-aligned runSubscriptionRemoteRegisteredChildSelectorsAlignedContract &&
        runRegressionStep subscription-tx-registered-child-selectors-aligned runSubscriptionTxRegisteredChildSelectorsAlignedContract &&
        runRegressionStep subscription-aggregate-runner-registration runSubscriptionAggregateRunnerRegistrationContract &&
        runRegressionStep subscription-remote-aggregate-runner-registration runSubscriptionRemoteAggregateRunnerRegistrationContract &&
        runRegressionStep subscription-tx-aggregate-runner-registration runSubscriptionTxAggregateRunnerRegistrationContract &&
        runRegressionStep subscription-aggregate-runners-use-suite-local-helpers runSubscriptionAggregateRunnersUseSuiteLocalHelpersContract &&
        runRegressionStep reality-suite-uses-function-registry runRealitySuiteUsesFunctionRegistryContract &&
        runRegressionStep reality-candidates-aggregate-runner-registration runRealityCandidatesAggregateRunnerRegistrationContract &&
        runRegressionStep reality-candidates-aggregate-runner-dispatches-children-in-order runRealityCandidatesAggregateRunnerDispatchesChildrenInOrderContract &&
        runRegressionStep reality-stream-aggregate-runner-registration runRealityStreamAggregateRunnerRegistrationContract &&
        runRegressionStep reality-stream-aggregate-runner-dispatches-children-in-order runRealityStreamAggregateRunnerDispatchesChildrenInOrderContract &&
        runRegressionStep runtime-suite-uses-function-registry runRuntimeSuiteUsesFunctionRegistryContract &&
        runRegressionStep runtime-selector-helpers-stay-aligned runRuntimeSelectorHelpersStayAlignedContract &&
        runRegressionStep runtime-aggregate-runner-registration runRuntimeAggregateRunnerRegistrationContract &&
        runRegressionStep runtime-aggregate-runner-uses-suite-local-helper runRuntimeAggregateRunnerUsesSuiteLocalHelperContract &&
        runRegressionStep reality-aggregate-runners-use-suite-local-helpers runRealityAggregateRunnersUseSuiteLocalHelpersContract &&
        runRegressionStep parallel-selector-collects-exited-child-without-rc runParallelSelectorCollectsExitedChildWithoutRcContract &&
        runRegressionStep transaction-core-compatible-dispatcher-leaves-execute runTransactionCoreCompatibleDispatcherLeavesExecutionContract &&
        runRegressionStep transaction-system-aggregate-dispatches-children-once runTransactionSystemAggregateDispatchesChildrenExactlyOnceContract &&
        runRegressionStep legacy-reality-stubs-survive-suite-load runLegacyRealityStubsSurviveSuiteLoadContract
}

registerRegressionFunctionLeaf regression-dispatcher-contract runRegressionDispatcherContracts
