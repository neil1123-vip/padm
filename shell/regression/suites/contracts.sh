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

runSubscriptionStateShimUsesSourceOnlyFullContract() {
    local stateShim="${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state.sh"

    ! grep -q 'sourceSubscriptionStateHotSection' "${stateShim}"
    ! grep -q 'awk ' "${stateShim}"
    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${SUBSCRIPTION_STATE_FULL_SCRIPT_PATH}"' "${stateShim}"
    grep -q 'if \[\[ "\${PADM_REGRESSION_SOURCE_ONLY:-}" == "1" \]\]; then' "${stateShim}"
}

runSubscriptionStateShimStaysThinContract() {
    local stateShim="${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state.sh"

    ! grep -q '^runParallelSubscriptionStateModes()' "${stateShim}" || return 1
    ! grep -q '^runRegressionSubscriptionStateCore()' "${stateShim}" || return 1
    ! grep -q '^runRegressionSubscriptionStateStructure()' "${stateShim}" || return 1
    ! grep -q '^runRegressionSubscriptionStateQuota()' "${stateShim}" || return 1
    ! grep -q '^runRegressionSubscriptionStateRemoteRestore()' "${stateShim}" || return 1
    ! grep -q '^runRegressionSubscriptionStateSupport()' "${stateShim}" || return 1
    ! grep -q '^runRegressionSubscriptionStateSyncRollback()' "${stateShim}" || return 1
    ! grep -Eq '^[[:space:]]*subscription-state\)$' "${stateShim}" || return 1
    ! grep -Eq '^[[:space:]]*subscription-state-core\)$' "${stateShim}" || return 1
    ! grep -Fq 'usage: %s [subscription-state|' "${stateShim}" || return 1
    ! grep -Fq '|subscription-state-core|' "${stateShim}" || return 1
    grep -q 'subscription-state-structure)' "${stateShim}"
    grep -q 'subscription-state-quota)' "${stateShim}"
    grep -q 'subscription-state-remote-restore)' "${stateShim}"
    grep -q 'subscription-state-support)' "${stateShim}"
    grep -q 'subscription-state-sync-rollback)' "${stateShim}"
    grep -q 'runRegressionStep "total:\${regressionName}" "\${regressionRunner}"' "${stateShim}"
}

runSubscriptionStateSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription_state.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state_full.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_SUBSCRIPTION_STATE_SUITE_DIR}/../subscription_groups_subscription_state_full.sh"' "${suiteFile}"
    grep -Eq '^runRegressionSubscriptionStateCore\(\)[[:space:]]*[({]' "${suiteFile}"
    grep -Eq '^runRegressionSubscriptionState\(\)[[:space:]]*[({]' "${suiteFile}"
    ! grep -Eq '^runRegressionSubscriptionStateCore\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionSubscriptionState\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionSubscriptionState\(\)[[:space:]]*[({]' "${legacyFile}"
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
    grep -q '^registerRegressionAggregateRunnerParallel subscription-state-core runRegressionSubscriptionStateCoreSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionSubscriptionStateCoreChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription-state-core"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["subscription-state-core"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["subscription-state-core"]:-}" == "runRegressionSubscriptionStateCoreSuiteRoot" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runSubscriptionStateAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription_state.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["subscription-state"]:-}

    ! grep -q '^registerRegressionFunctionLeaf subscription-state ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateParallel subscription-state \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-state runRegressionSubscriptionStateSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionSubscriptionStateChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription-state"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["subscription-state"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["subscription-state"]:-}" == "runRegressionSubscriptionStateSuiteRoot" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runSubscriptionStateFullUsesFrameworkParallelHelperContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription_state.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state_full.sh"
    local coreBody
    local stateBody

    ! grep -q 'PADM_SECTION_BEGIN: subscription-state-hot-regressions' "${scriptFile}"
    ! grep -q 'PADM_SECTION_END: subscription-state-hot-regressions' "${scriptFile}"
    ! grep -q '^runParallelSubscriptionStateModes()' "${scriptFile}"
    grep -q 'source "${REGRESSION_ENTRY_DIR}/regression/framework/runtime.sh"' "${scriptFile}"
    ! grep -Eq '^runRegressionSubscriptionStateCore\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionSubscriptionState\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^[[:space:]]*subscription-state\)$' "${scriptFile}"
    ! grep -Eq '^[[:space:]]*subscription-state-core\)$' "${scriptFile}"
    ! grep -Fq 'usage: %s [subscription-state|' "${scriptFile}"
    ! grep -Fq '|subscription-state-core|' "${scriptFile}"

    coreBody=$(sed -n '/^runRegressionSubscriptionStateCore() {$/,/^}$/p' "${suiteFile}")
    stateBody=$(sed -n '/^runRegressionSubscriptionState() {$/,/^}$/p' "${suiteFile}")

    grep -q 'runParallelRegressionRunners \\' <<<"${coreBody}"
    ! grep -q 'runParallelSubscriptionStateModes' <<<"${coreBody}"
    ! grep -q 'PADM_REGRESSION_INTERNAL_CLI=1 bash' <<<"${coreBody}"
    grep -q 'structure runRegressionSubscriptionStateStructure' <<<"${coreBody}"
    grep -q 'quota runRegressionSubscriptionStateQuota' <<<"${coreBody}"
    grep -q 'remote-restore runRegressionSubscriptionStateRemoteRestore' <<<"${coreBody}"

    grep -q 'runParallelRegressionRunners \\' <<<"${stateBody}"
    ! grep -q 'runParallelSubscriptionStateModes' <<<"${stateBody}"
    ! grep -q 'PADM_REGRESSION_INTERNAL_CLI=1 bash' <<<"${stateBody}"
    grep -q 'core runRegressionSubscriptionStateCore' <<<"${stateBody}"
    grep -q 'support runRegressionSubscriptionStateSupport' <<<"${stateBody}"
    grep -q 'sync-rollback runRegressionSubscriptionStateSyncRollback' <<<"${stateBody}"
}

runSubscriptionStateAggregatesSupportSourceOnlyExecutionContract() (
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription_state.sh"
    local callsFile="${TMP_DIR}/subscription-state-aggregate-runner-calls"
    local -a calls=()

    if ! declare -F runRegressionSubscriptionStateCore >/dev/null; then
        PADM_REGRESSION_SOURCE_ONLY=1 source "${suiteFile}"
    fi

    runParallelRegressionSelectors() {
        printf 'subscription-state aggregate should not require selector registry in source-only mode\n' >&2
        return 97
    }

    runParallelRegressionRunners() {
        printf '%s\n' "$*" >>"${callsFile}"
    }

    : >"${callsFile}"
    runRegressionSubscriptionStateCore
    runRegressionSubscriptionState

    mapfile -t calls <"${callsFile}"
    [[ "${#calls[@]}" -eq 2 ]]
    [[ "${calls[0]}" == "${TMP_DIR}/subscription-state-core structure runRegressionSubscriptionStateStructure quota runRegressionSubscriptionStateQuota remote-restore runRegressionSubscriptionStateRemoteRestore" ]]
    [[ "${calls[1]}" == "${TMP_DIR}/subscription-state-default core runRegressionSubscriptionStateCore support runRegressionSubscriptionStateSupport sync-rollback runRegressionSubscriptionStateSyncRollback" ]]
)

runRemoteControlSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/remote_control.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_remote_control.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_REMOTE_CONTROL_SUITE_DIR}/../subscription_groups_remote_control.sh"' "${suiteFile}"
    grep -Eq '^runRegressionRemoteControl\(\)[[:space:]]*[({]' "${suiteFile}"
    grep -Eq '^runRegressionRemoteControlSuiteRoot\(\)[[:space:]]*[({]' "${suiteFile}"
    ! grep -Eq '^runRegressionRemoteControl\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionRemoteControl\(\)[[:space:]]*[({]' "${legacyFile}"
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
    ! grep -q '^registerRegressionAggregateParallel remote-control \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel remote-control runRegressionRemoteControlSuiteRoot \\' "${suiteFile}"
    ! grep -q '^registerRegressionAlias remote-control-light remote-control$' "${suiteFile}"

    ! grep -q '^runParallelRemoteControlModes()' "${scriptFile}"
    ! grep -q '^runParallelRemoteControlTotals()' "${scriptFile}"
    ! grep -q 'PADM_REGRESSION_SUPPRESS_DONE=1 PADM_REGRESSION_INTERNAL_CLI=1 bash "\${REMOTE_CONTROL_SCRIPT_PATH}"' "${scriptFile}"
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
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    ! grep -q '^registerRegressionAlias remote-control-light remote-control$' "${suiteFile}"
    [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control-smoke"]:-}" == "aggregate" ]]
    [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control-contract"]:-}" == "aggregate" ]]
    [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control-deep"]:-}" == "function" ]]
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["remote-control-light"]:-}" ]]
    ! grep -Eq '^[[:space:]]*remote-control\)$' "${scriptFile}"
    ! grep -Eq '^[[:space:]]*remote-control-light\)$' "${scriptFile}"
    ! grep -Fq 'remote-control-light|' "${scriptFile}"
    ! grep -Fq 'usage: %s [remote-control|' "${scriptFile}"
    grep -Fq 'usage: %s [remote-control-smoke|remote-control-contract|remote-control-deep]' "${scriptFile}"
    ! grep -Eq '^[[:space:]]*remote-control\)$' "${legacyFile}"
}

runLegacyRetiresSuiteOwnedWrappersContract() {
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local status=0

    grep -Eq '^runRegressionSubscriptionState\(\)[[:space:]]*[({]' "${legacyFile}" && status=1
    grep -Eq '^runRegressionRemoteControl\(\)[[:space:]]*[({]' "${legacyFile}" && status=1
    grep -Eq '^[[:space:]]*subscription-state\)$' "${legacyFile}" && status=1
    grep -Eq '^[[:space:]]*remote-control\)$' "${legacyFile}" && status=1
    grep -Fq '|subscription-state|' "${legacyFile}" && status=1
    grep -Fq '|remote-control|' "${legacyFile}" && status=1

    return "${status}"
}

runRemoteControlAggregatesSupportSourceOnlyExecutionContract() (
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/remote_control.sh"
    local callsFile="${TMP_DIR}/remote-control-aggregate-runner-calls"
    local -a calls=()

    if ! declare -F runRegressionRemoteControl >/dev/null; then
        PADM_REGRESSION_SOURCE_ONLY=1 source "${suiteFile}"
    fi

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
    [[ "${calls[0]}" == "${TMP_DIR}/remote-control-default smoke runRegressionRemoteControlSmoke contract runRegressionRemoteControlContract deep runRegressionRemoteControlDeep" ]]
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
remote-control-deep
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
    grep -q '^registerRegressionAggregateRunnerParallel remote-control runRegressionRemoteControlSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionRemoteControlChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["remote-control"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["remote-control"]:-}" == "runRegressionRemoteControlSuiteRoot" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runFastSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/fast.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_fast.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_FAST_SUITE_DIR}/../subscription_groups_fast.sh"' "${suiteFile}"
    grep -q '^runRegressionFastSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionFastUiSmokeLightSuiteRoot() {$' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf fast ' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf fast runRegressionFastSuiteRoot$' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf fast-reality ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf fast-reality ' "${suiteFile}"
    grep -q '^runRegressionFastRealitySuiteRoot() {$' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential fast-reality runRegressionFastRealitySuiteRoot \\' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf platform-hot ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf platform-hot ' "${suiteFile}"
    ! grep -q 'declare -f runRegressionFast' "${suiteFile}"
    ! grep -q '^eval ' "${suiteFile}"
    grep -q 'runRegressionStep ui-smoke-light runRegressionFastUiSmokeLightSuiteRoot' "${suiteFile}"
    grep -q 'if \[\[ "\${PADM_REGRESSION_SOURCE_ONLY:-}" == "1" \]\]; then' "${scriptFile}"
}

runPlatformSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/platform.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_PLATFORM_SUITE_DIR}/../subscription_groups_fast.sh"' "${suiteFile}"
    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_PLATFORM_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    grep -q '^runRegressionPlatformSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionPlatformIoSuiteRoot() {$' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf platform-hot ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf platform-io ' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf platform-hot runRegressionPlatformSuiteRoot$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf platform-io runRegressionPlatformIoSuiteRoot$' "${suiteFile}"
    ! grep -q 'declare -f runRegressionPlatform' "${suiteFile}"
    ! grep -q 'declare -f runRegressionPlatformIo' "${suiteFile}"
    ! grep -q '^eval ' "${suiteFile}"
}

runPlatformPublicSelectorRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/platform.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^registerRegressionFunctionLeaf platform-hot runRegressionPlatformSuiteRoot$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf platform-io runRegressionPlatformIoSuiteRoot$' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf platform runRegressionPlatformSuiteRoot$' "${suiteFile}"
    ! grep -Eq '^runRegressionPlatform\(\)[[:space:]]*[({]' "${legacyFile}"
    ! grep -Eq '^runRegressionPlatformIo\(\)[[:space:]]*[({]' "${legacyFile}"
    ! grep -Eq '^[[:space:]]*platform\)$' "${legacyFile}"
    ! grep -Eq '^[[:space:]]*platform-hot\)$' "${legacyFile}"
    ! grep -Eq '^[[:space:]]*platform-io\)$' "${legacyFile}"
    ! grep -Fq '[platform-hot|' "${legacyFile}"
    ! grep -Fq '|platform-io|' "${legacyFile}"
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

runFastRealityLegacyRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/fast.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^registerRegressionAggregateRunnerSequential fast-reality runRegressionFastRealitySuiteRoot \\' "${suiteFile}" || return 1
    ! grep -Eq '^runRegressionFastReality\(\)[[:space:]]*[({]' "${legacyFile}" || return 1
    ! grep -Eq '^[[:space:]]*fast-reality\)$' "${legacyFile}" || return 1
    ! grep -Fq '|fast-reality|' "${legacyFile}" || return 1
}

runFastLegacyRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/fast.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^registerRegressionFunctionLeaf fast runRegressionFastSuiteRoot$' "${suiteFile}" || return 1
    ! grep -Eq '^runRegressionFast\(\)[[:space:]]*[({]' "${legacyFile}" || return 1
    ! grep -Eq '^[[:space:]]*fast\)$' "${legacyFile}" || return 1
    ! grep -Fq 'usage: %s [fast|' "${legacyFile}" || return 1
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
    ! declare -F _platform_hot_suite_def >/dev/null
    ! declare -F _platform_io_suite_def >/dev/null
    ! declare -F _fast_root_suite_def >/dev/null
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

runFastSuiteUsesSuiteLocalHelperContract() (
    local callLog="${TMP_DIR}/fast-suite-root-dispatch.log"

    : >"${callLog}"

    runMenuSmokeLightRegression() {
        printf 'legacy-ui-smoke-light\n' >>"${callLog}"
        return 97
    }

    runRegressionFastUiSmokeLightSuiteRoot() {
        printf 'suite-ui-smoke-light\n' >>"${callLog}"
    }

    runRegressionStep() {
        local label=$1
        local runner=$2

        if [[ "${label}" == "ui-smoke-light" ]]; then
            "${runner}"
            return $?
        fi

        return 0
    }

    runRegressionFastSuiteRoot

    grep -qx 'suite-ui-smoke-light' "${callLog}"
    ! grep -q '^legacy-ui-smoke-light$' "${callLog}"
)

runAllSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/all.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    ! grep -q 'subscription_groups_legacy\.sh' "${suiteFile}" || return 1
    grep -q 'source "\${REGRESSION_ALL_SUITE_DIR}/../framework/runtime.sh"' "${suiteFile}" || return 1
    grep -q '^REGRESSION_ENTRY_SCRIPT_PATH=' "${suiteFile}" || return 1
    grep -q '^runRegressionAllSelector() {$' "${suiteFile}" || return 1
    grep -q '^runRegressionAllSelectorSuiteRoot() {$' "${suiteFile}" || return 1
    grep -Eq '^runRegressionAll\(\) \($|^runRegressionAll\(\) {$' "${suiteFile}" || return 1
    grep -Eq '^runRegressionAllSuiteRoot\(\) \($|^runRegressionAllSuiteRoot\(\) {$' "${suiteFile}" || return 1
    grep -q 'PADM_REGRESSION_PARALLEL_SELECTOR_MODE=selectors' "${suiteFile}" || return 1
    grep -q 'runFrameworkParallelRegressionSelectors "${TMP_DIR}/all-parallel-' "${suiteFile}" || return 1
    ! grep -q '^runRegressionAllSelector() {$' "${legacyScriptFile}" || return 1
    ! grep -Eq '^runRegressionAll\(\) \($|^runRegressionAll\(\) {$' "${legacyScriptFile}" || return 1
    ! grep -q '^registerRegressionScriptLeaf all ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf all ' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerSequential all runRegressionAllSuiteRoot \\' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAlias full all$' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAlias ci all$' "${suiteFile}" || return 1
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
    grep -Fq '|all]' "${legacyFile}"
}

runLegacySuiteUsesFunctionRegistryContract() (
    set -euo pipefail
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local expectedChildren actualChildren

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_LEGACY_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateRunnerSequential transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateRunnerParallel transaction-system ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf platform-io ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf platform-io ' "${suiteFile}"
    grep -Eq '^[[:space:]]*registerRegressionScriptLeaf "\${selector}" "\${REGRESSION_LEGACY_SCRIPT}" "\${runner}"$' "${suiteFile}"
    grep -q 'if \[\[ "\${PADM_REGRESSION_SOURCE_ONLY:-}" == "1" \]\]; then' "${scriptFile}"
    declare -F listRegressionTransactionSystemChildSelectors >/dev/null
    declare -F listRegressionTransactionChildSelectors >/dev/null
    expectedChildren=$(listRegressionTransactionSystemChildSelectors)
    actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["transaction-system"]:-}
    [[ -n "${expectedChildren}" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
)

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

runTlsLegacyRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/tls.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^registerRegressionAggregateRunnerSequential tls runRegressionTlsSuiteRoot \\' "${suiteFile}" || return 1
    ! grep -Eq '^runRegressionTls\(\)[[:space:]]*[({]' "${legacyFile}" || return 1
    ! grep -Eq '^[[:space:]]*tls\)$' "${legacyFile}" || return 1
    ! grep -Fq '|tls|' "${legacyFile}" || return 1
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

    ! grep -q '^registerRegressionFunctionLeaf ' "${suiteFile}"
}

runCompositionLeafSelectorsUseSuiteLocalRegistryContract() {
    local status=0
    local selector
    local runner
    local suiteFile
    local legacySuiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    while read -r selector runner suiteFile; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}\$" "${suiteFile}" || status=1
        grep -Eq "^${runner}\\(\\)[[:space:]]*[({]" "${suiteFile}" || status=1
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${legacySuiteFile}" || status=1
        ! grep -q "^registerRegressionFunctionLeaf ${selector} " "${legacySuiteFile}" || status=1
        ! grep -Eq "^${runner}\\(\\)[[:space:]]*[({]" "${legacyScriptFile}" || status=1
        [[ "${PADM_REGRESSION_SELECTOR_KIND["${selector}"]:-}" == "function" ]] || status=1
    done <<EOF
regression-all-composition runRegressionAllCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/all.sh
regression-all-child-parallel-budget-composition runRegressionAllChildParallelBudgetCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/all.sh
regression-all-resource-layer-composition runRegressionAllResourceLayerCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/all.sh
regression-routing-parallel-composition runRegressionRoutingParallelCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/routing.sh
regression-runtime-parallel-composition runRegressionRuntimeParallelCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/runtime.sh
regression-transaction-core-parallel-composition runRegressionTransactionCoreParallelCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/transaction.sh
regression-transaction-system-parallel-composition runRegressionTransactionSystemParallelCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/transaction.sh
regression-ui-parallel-composition runRegressionUiParallelCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/ui.sh
regression-ui-long-tail-split-composition runRegressionUiLongTailSplitCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/ui.sh
regression-selector-dispatch-composition runRegressionSelectorDispatchCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/contracts.sh
regression-parallel-selector-limit-composition runRegressionParallelSelectorLimitCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/contracts.sh
regression-parallel-selector-slot-refill-composition runRegressionParallelSelectorSlotRefillCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/contracts.sh
EOF

    return "${status}"
}

runTransactionDirectLeafSelectorsUseFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local legacySuiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local status=0

    while read -r selector runner; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}\$" "${suiteFile}" || status=1
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${legacySuiteFile}" || status=1
        ! grep -q "^registerRegressionFunctionLeaf ${selector} " "${legacySuiteFile}" || status=1
        [[ "${PADM_REGRESSION_SELECTOR_KIND["${selector}"]:-}" == "function" ]] || status=1
    done <<'EOF'
transaction-subscription runRegressionTransactionSubscription
nginx-service-failure runNginxServiceFailureRegression
uninstall-nginx-cleanup runUninstallNginxCleanupRegression
clean-agent-nginx-managed-remove runCleanAgentNginxManagedRemovalRegression
fail2ban-managed-cleanup runFail2banManagedCleanupRegression
fail2ban-apply-transaction runFail2banApplyTransactionRegression
uninstall-wireguard-cleanup runUninstallWireGuardCleanupRegression
wireguard-key-transaction runWireGuardKeyTransactionRegression
wireguard-control-safe-dir runWireGuardControlSafeDirRegression
warp-config-safe-dir runWarpConfigSafeDirRegression
warp-config-file-cleanup runWarpConfigFileCleanupRegression
uninstall-service-stop-failure runUninstallServiceStopFailureRegression
clean-last-installation-failure runCleanLastInstallationConfigFailureRegression
clean-last-installation-acme-home runCleanLastInstallationConfigAcmeHomeFailureRegression
clean-last-installation-acme-relative-home runCleanLastInstallationConfigResolvesRelativeAcmeHomeRegression
alone-nginx-write-transaction runAloneNginxConfigWriteTransactionRegression
alone-nginx-update-transaction runAloneNginxUpdateTransactionRegression
EOF

    return "${status}"
}

runTransactionCoreDirectLeafSelectorsUseFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local legacySuiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local status=0

    while read -r selector runner; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}\$" "${suiteFile}" || status=1
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${legacySuiteFile}" || status=1
        ! grep -q "^registerRegressionFunctionLeaf ${selector} " "${legacySuiteFile}" || status=1
        [[ "${PADM_REGRESSION_SELECTOR_KIND["${selector}"]:-}" == "function" ]] || status=1
    done <<'EOF'
core-rollback-result-message runCoreRollbackResultMessageRegression
config-transaction runConfigTransactionRegression
core-port-file-transaction runCorePortFileTransactionRegression
core-port-unsafe-config-dir runCorePortRejectsUnsafeConfigDirRegression
entry-helper-config runEntryHelperConfigRegression
user-config-write runUserConfigWriteRegression
remove-user runRemoveUserRegression
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
sing-box-merge-config-transaction runSingBoxMergeConfigTransactionRegression
reload-core-propagation runReloadCorePropagationRegression
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
subscription-remote-unique runRemoteSubscribeFetchUniqueRegression
subscription-remote-rollback runRemoteSubscribeFetchRollbackRegression
subscription-remote-merge runRemoteSubscribeFetchMergeRegression
subscription-remote-controlled runRemoteSubscribeFetchControlledRegression
subscription-remote-append-failure runRemoteSubscribeFetchAppendFailureRegression
subscription-remote-commit-failure runRemoteSubscribeFetchCommitFailureRegression
subscription-remote-idempotent runRemoteSubscribeFetchIdempotentRegression
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
    local legacySuiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local status=0

    while read -r selector runner; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}\$" "${suiteFile}" || status=1
        grep -Eq "^${runner}\\(\\)[[:space:]]*[({]" "${suiteFile}" || status=1
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${legacySuiteFile}" || status=1
        ! grep -q "^registerRegressionFunctionLeaf ${selector} " "${legacySuiteFile}" || status=1
        ! grep -Eq "^${runner}\\(\\)[[:space:]]*[({]" "${legacyScriptFile}" || status=1
        [[ "${PADM_REGRESSION_SELECTOR_KIND["${selector}"]:-}" == "function" ]] || status=1
    done <<'EOF'
regression-subscription-parallel-composition runRegressionSubscriptionParallelCompositionRegression
regression-subscription-tx-parallel-composition runRegressionSubscriptionTxParallelCompositionRegression
regression-subscription-remote-parallel-composition runRegressionSubscriptionRemoteParallelCompositionRegression
EOF

    return "${status}"
}

runSubscriptionSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q 'source "\${REGRESSION_SUBSCRIPTION_SUITE_DIR}/../framework/runtime.sh"' "${suiteFile}"
    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_SUBSCRIPTION_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    grep -q '^runRegressionSubscription() {$' "${suiteFile}"
    grep -q '^runRegressionSubscriptionRemote() {$' "${suiteFile}"
    grep -q '^runRegressionSubscriptionTx() {$' "${suiteFile}"
    grep -q '^runRegressionSubscriptionSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionSubscriptionRemoteSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionSubscriptionTxSuiteRoot() {$' "${suiteFile}"
    grep -q 'PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs' "${suiteFile}"
    grep -q 'runFrameworkParallelRegressionSelectors "${TMP_DIR}/subscription-' "${suiteFile}"
    ! grep -q '^runRegressionSubscription() {$' "${legacyScriptFile}"
    ! grep -q '^runRegressionSubscriptionRemote() {$' "${legacyScriptFile}"
    ! grep -q '^runRegressionSubscriptionTx() {$' "${legacyScriptFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription-remote ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-remote ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription-tx ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-tx ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription-remote-fetch ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-remote-fetch ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-remote-fetch-' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription-write-transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-write-transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf regression-subscription-write-transaction-' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf subscription-output runRegressionSubscriptionOutput$' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-remote runRegressionSubscriptionRemoteSuiteRoot \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-tx runRegressionSubscriptionTxSuiteRoot \\' "${suiteFile}"
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
ui-smoke runRegressionUiSmokeSuiteRoot
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
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q 'source "\${REGRESSION_UI_SUITE_DIR}/../framework/runtime.sh"' "${suiteFile}" || return 1
    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_UI_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}" || return 1
    grep -q '^runRegressionMenuSmokeFull() {$' "${suiteFile}" || return 1
    grep -q '^listRegressionUiChildSelectors() {$' "${suiteFile}" || return 1
    grep -q '^listRegressionUiAllProfileChildSelectors() {$' "${suiteFile}" || return 1
    grep -q '^runRegressionUiSmokeSuiteRoot() {$' "${suiteFile}" || return 1
    grep -q '^runRegressionUiSuiteRoot() {$' "${suiteFile}" || return 1
    grep -q '^runRegressionUiParallelCompositionRegression() ' "${suiteFile}" || return 1
    grep -q '^runRegressionUiLongTailSplitCompositionRegression() ' "${suiteFile}" || return 1
    grep -q 'PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs' "${suiteFile}" || return 1
    grep -q 'runFrameworkParallelRegressionSelectors "${TMP_DIR}/ui-parallel-' "${suiteFile}" || return 1
    ! grep -q '^listRegressionUiChildSelectors() {$' "${legacyScriptFile}" || return 1
    ! grep -q '^listRegressionUiAllProfileChildSelectors() {$' "${legacyScriptFile}" || return 1
    ! grep -q '^runRegressionUi() {$' "${legacyScriptFile}" || return 1
    ! grep -q '^runRegressionUiParallelCompositionRegression() ' "${legacyScriptFile}" || return 1
    ! grep -q '^runRegressionUiLongTailSplitCompositionRegression() ' "${legacyScriptFile}" || return 1
    ! grep -q '^registerRegressionScriptLeaf ui ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf ui ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionScriptLeaf menu-smoke ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf menu-smoke ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionScriptLeaf menu-smoke-full ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf menu-smoke-full ' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf ui-smoke runRegressionUiSmokeSuiteRoot$' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf ui-full runRegressionMenuSmokeFull$' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel ui runRegressionUiSuiteRoot \\' "${suiteFile}" || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-smoke"]:-}" == "function" ]] || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-full"]:-}" == "function" ]] || return 1
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["menu-smoke"]:-}" ]] || return 1
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["menu-smoke-full"]:-}" ]] || return 1
}

runUiSmokeLegacyWrapperRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/ui.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^registerRegressionFunctionLeaf ui-smoke runRegressionUiSmokeSuiteRoot$' "${suiteFile}" || return 1
    ! grep -Eq '^runRegressionMenuSmoke\(\)[[:space:]]*[({]' "${legacyScriptFile}" || return 1
    ! grep -Eq '^[[:space:]]*ui-smoke\)$' "${legacyScriptFile}" || return 1
    ! grep -Fq '|ui-smoke|' "${legacyScriptFile}" || return 1
}

runUiFullLegacyWrapperRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/ui.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^runRegressionMenuSmokeFull() {$' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf ui-full runRegressionMenuSmokeFull$' "${suiteFile}" || return 1
    ! grep -Eq '^runRegressionMenuSmokeFull\(\)[[:space:]]*[({]' "${legacyScriptFile}" || return 1
    ! grep -Eq '^[[:space:]]*ui-full\)$' "${legacyScriptFile}" || return 1
    ! grep -Fq '|ui-full|' "${legacyScriptFile}" || return 1
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

runUiAggregateRunnerUsesFrameworkSelectorHelperContract() (
    local callLog="${TMP_DIR}/ui-framework-helper-dispatch.log"

    : >"${callLog}"

    listRegressionUiChildSelectors() {
        printf '%s\n' \
            ui-smoke \
            ui-full-core
    }

    listRegressionUiAllProfileChildSelectors() {
        printf '%s\n' \
            ui-smoke \
            wireguard-restore-runner
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:%s\n' "$*" >>"${callLog}"
    }

    runParallelRegressionSelectors() {
        printf 'legacy-helper:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runRegressionUiSuiteRoot
    PADM_REGRESSION_UI_RESOURCE_PROFILE=all runRegressionUiSuiteRoot

    grep -qx 'framework:'"${TMP_DIR}"'/ui-parallel-[0-9][0-9]* ui-smoke ui-smoke ui-full-core ui-full-core' "${callLog}"
    grep -qx 'framework:'"${TMP_DIR}"'/ui-parallel-[0-9][0-9]* ui-smoke ui-smoke wireguard-restore-runner wireguard-restore-runner' "${callLog}"
    ! grep -q '^legacy-helper:' "${callLog}"
)

runRoutingSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/routing.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local status=0

    grep -q 'source "\${REGRESSION_ROUTING_SUITE_DIR}/../framework/runtime.sh"' "${suiteFile}" || status=1
    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_ROUTING_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}" || status=1
    grep -q '^listRegressionRoutingCoreChildSelectors() {$' "${suiteFile}" || status=1
    grep -q '^listRegressionRoutingHeavyChildSelectors() {$' "${suiteFile}" || status=1
    grep -q '^listRegressionRoutingLightChildSelectors() {$' "${suiteFile}" || status=1
    grep -q '^listRegressionRoutingChildSelectors() {$' "${suiteFile}" || status=1
    grep -q '^runRegressionRoutingSuiteRoot() {$' "${suiteFile}" || status=1
    grep -q '^runRegressionRoutingParallelCompositionRegression() ' "${suiteFile}" || status=1
    grep -q 'PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs' "${suiteFile}" || status=1
    grep -q 'runFrameworkParallelRegressionSelectors "${TMP_DIR}/routing-parallel-' "${suiteFile}" || status=1
    ! grep -q '^listRegressionRoutingCoreChildSelectors() {$' "${legacyScriptFile}" || status=1
    ! grep -q '^listRegressionRoutingHeavyChildSelectors() {$' "${legacyScriptFile}" || status=1
    ! grep -q '^listRegressionRoutingLightChildSelectors() {$' "${legacyScriptFile}" || status=1
    ! grep -q '^listRegressionRoutingChildSelectors() {$' "${legacyScriptFile}" || status=1
    ! grep -q '^runRegressionRouting() {$' "${legacyScriptFile}" || status=1
    ! grep -q '^runRegressionRoutingParallelCompositionRegression() ' "${legacyScriptFile}" || status=1
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

runRoutingAggregateRunnerUsesFrameworkSelectorHelperContract() (
    local callLog="${TMP_DIR}/routing-framework-helper-dispatch.log"

    : >"${callLog}"

    listRegressionRoutingChildSelectors() {
        printf '%s\n' \
            routing-core \
            routing-port-panel
    }

    listRegressionRoutingCoreChildSelectors() {
        printf '%s\n' \
            routing-core
    }

    listRegressionRoutingHeavyChildSelectors() {
        printf '%s\n' \
            routing-access-control-config-transaction \
            routing-dns-failure-return
    }

    listRegressionRoutingLightChildSelectors() {
        printf '%s\n' \
            routing-port-panel \
            routing-core-unsafe-config-dir
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:jobs=%s:%s\n' "${PADM_REGRESSION_PARALLEL_JOBS:-}" "$*" >>"${callLog}"
    }

    runParallelRegressionSelectors() {
        printf 'legacy-helper:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runRegressionRoutingSuiteRoot
    PADM_REGRESSION_ROUTING_RESOURCE_PROFILE=all runRegressionRoutingSuiteRoot

    grep -qx 'framework:jobs='"${PADM_REGRESSION_ROUTING_PARALLEL_JOBS:-4}"':'"${TMP_DIR}"'/routing-parallel-[0-9][0-9]* routing-core routing-core routing-port-panel routing-port-panel' "${callLog}"
    grep -qx 'framework:jobs=:'"${TMP_DIR}"'/routing-parallel-core-[0-9][0-9]* routing-core routing-core' "${callLog}"
    grep -qx 'framework:jobs='"${PADM_REGRESSION_ROUTING_WAVE_PARALLEL_JOBS:-2}"':'"${TMP_DIR}"'/routing-parallel-heavy-[0-9][0-9]* routing-access-control-config-transaction routing-access-control-config-transaction routing-dns-failure-return routing-dns-failure-return' "${callLog}"
    grep -qx 'framework:jobs='"${PADM_REGRESSION_ROUTING_LIGHT_PARALLEL_JOBS:-${PADM_REGRESSION_ROUTING_WAVE_PARALLEL_JOBS:-4}}"':'"${TMP_DIR}"'/routing-parallel-light-[0-9][0-9]* routing-port-panel routing-port-panel routing-core-unsafe-config-dir routing-core-unsafe-config-dir' "${callLog}"
    ! grep -q '^legacy-helper:' "${callLog}"
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
    grep -q '^registerRegressionAggregateRunnerParallel transaction-core runRegressionTransactionCoreSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionTransactionCoreChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["transaction-core"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["transaction-core"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["transaction-core"]:-}" == "runRegressionTransactionCoreSuiteRoot" ]]
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

runTransactionAggregateRunnerRegistrationContract() (
    set -euo pipefail
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["transaction"]:-}

    ! grep -q '^registerRegressionScriptLeaf transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateSequential transaction \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential transaction runRegressionTransactionSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionTransactionChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["transaction"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["transaction"]:-}" == "sequential" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["transaction"]:-}" == "runRegressionTransactionSuiteRoot" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
)

runTransactionSystemAggregateRunnerRegistrationContract() (
    set -euo pipefail
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local expectedChildren
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["transaction-system"]:-}

    ! grep -q '^registerRegressionScriptLeaf transaction-system ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction-system ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateParallel transaction-system \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel transaction-system runRegressionTransactionSystemSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionTransactionSystemChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["transaction-system"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["transaction-system"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["transaction-system"]:-}" == "runRegressionTransactionSystemSuiteRoot" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
)

runTransactionSuiteUsesFunctionRegistryContract() (
    set -euo pipefail
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q 'source "\${REGRESSION_TRANSACTION_SUITE_DIR}/../framework/runtime.sh"' "${suiteFile}"
    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_TRANSACTION_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    grep -q '^listRegressionTransactionChildSelectors() {$' "${suiteFile}"
    grep -q '^runRegressionTransactionSubscription() {$' "${suiteFile}"
    grep -q '^listRegressionTransactionCoreSelectorEntries() {$' "${suiteFile}"
    grep -q '^listRegressionTransactionCoreSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionTransactionCoreChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionTransactionCoreHeavyChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionTransactionCoreMediumChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionTransactionCoreLightChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionTransactionSystemChildSelectors() {$' "${suiteFile}"
    grep -q '^runRegressionTransactionSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionTransactionCoreSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionTransactionSystemSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionTransactionCoreParallelCompositionRegression() ' "${suiteFile}"
    grep -q '^runRegressionTransactionSystemParallelCompositionRegression() ' "${suiteFile}"
    grep -q 'PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs' "${suiteFile}"
    grep -q 'runFrameworkParallelRegressionSelectors "${TMP_DIR}/transaction-core-parallel-' "${suiteFile}"
    grep -q 'runFrameworkParallelRegressionSelectors "${TMP_DIR}/transaction-system-parallel-' "${suiteFile}"
    ! grep -q '^runRegressionTransactionCore() {$' "${legacyScriptFile}"
    ! grep -q '^runRegressionTransactionSubscription() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionTransactionCoreSelectorEntries() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionTransactionCoreSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionTransactionCoreChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionTransactionCoreHeavyChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionTransactionCoreMediumChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionTransactionCoreLightChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionTransactionSystemChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^runRegressionTransactionSystem() {$' "${legacyScriptFile}"
    ! grep -q '^runRegressionTransactionCoreParallelCompositionRegression() ' "${legacyScriptFile}"
    ! grep -q '^runRegressionTransactionSystemParallelCompositionRegression() ' "${legacyScriptFile}"
    ! grep -q '^runRegressionTransaction() {$' "${legacyScriptFile}"
    ! grep -q '^registerRegressionScriptLeaf transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf transaction-core ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction-core ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf transaction-system ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction-system ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel transaction-core runRegressionTransactionCoreSuiteRoot \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel transaction-system runRegressionTransactionSystemSuiteRoot \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential transaction runRegressionTransactionSuiteRoot \\' "${suiteFile}"
)

runTransactionSuiteUsesSuiteLocalHelpersContract() (
    local callLog="${TMP_DIR}/transaction-suite-root-dispatch.log"

    : >"${callLog}"

    runRegressionTransaction() {
        printf 'legacy-transaction\n' >>"${callLog}"
        return 97
    }

    runRegressionTransactionSystem() {
        printf 'legacy-transaction-system\n' >>"${callLog}"
        return 97
    }

    runRegressionTransactionSuiteRoot() {
        printf 'suite-transaction\n' >>"${callLog}"
    }

    runRegressionTransactionCore() {
        printf 'legacy-transaction-core\n' >>"${callLog}"
        return 97
    }

    runRegressionTransactionCoreSuiteRoot() {
        printf 'suite-transaction-core\n' >>"${callLog}"
    }

    runRegressionTransactionSystemSuiteRoot() {
        printf 'suite-transaction-system\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain transaction
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain transaction-core
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain transaction-system

    grep -qx 'suite-transaction' "${callLog}"
    grep -qx 'suite-transaction-core' "${callLog}"
    grep -qx 'suite-transaction-system' "${callLog}"
    ! grep -q '^legacy-transaction$' "${callLog}"
    ! grep -q '^legacy-transaction-core$' "${callLog}"
    ! grep -q '^legacy-transaction-system$' "${callLog}"
)

runTransactionCoreAggregateRunnerUsesFrameworkSelectorHelperContract() (
    local callLog="${TMP_DIR}/transaction-core-framework-helper-dispatch.log"

    : >"${callLog}"

    listRegressionTransactionCoreChildSelectors() {
        printf '%s\n' \
            core-rollback-result-message \
            config-transaction
    }

    listRegressionTransactionCoreHeavyChildSelectors() {
        printf '%s\n' \
            core-install-service-action-failure \
            core-port-file-transaction
    }

    listRegressionTransactionCoreMediumChildSelectors() {
        printf '%s\n' \
            config-transaction \
            entry-helper-config
    }

    listRegressionTransactionCoreLightChildSelectors() {
        printf '%s\n' \
            core-rollback-result-message \
            service-queue-apply-propagation
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:jobs=%s:%s\n' "${PADM_REGRESSION_PARALLEL_JOBS:-}" "$*" >>"${callLog}"
    }

    runParallelRegressionSelectors() {
        printf 'legacy-helper:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runRegressionTransactionCoreSuiteRoot
    PADM_REGRESSION_TRANSACTION_CORE_RESOURCE_PROFILE=all runRegressionTransactionCoreSuiteRoot

    grep -qx 'framework:jobs=:'"${TMP_DIR}"'/transaction-core-parallel-[0-9][0-9]* core-rollback-result-message core-rollback-result-message config-transaction config-transaction' "${callLog}"
    grep -qx 'framework:jobs='"${PADM_REGRESSION_TRANSACTION_CORE_HEAVY_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-2}}"':'"${TMP_DIR}"'/transaction-core-parallel-heavy-[0-9][0-9]* core-install-service-action-failure core-install-service-action-failure core-port-file-transaction core-port-file-transaction' "${callLog}"
    grep -qx 'framework:jobs='"${PADM_REGRESSION_TRANSACTION_CORE_MEDIUM_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-3}}"':'"${TMP_DIR}"'/transaction-core-parallel-medium-[0-9][0-9]* config-transaction config-transaction entry-helper-config entry-helper-config' "${callLog}"
    grep -qx 'framework:jobs='"${PADM_REGRESSION_TRANSACTION_CORE_LIGHT_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}"':'"${TMP_DIR}"'/transaction-core-parallel-light-[0-9][0-9]* core-rollback-result-message core-rollback-result-message service-queue-apply-propagation service-queue-apply-propagation' "${callLog}"
    ! grep -q '^legacy-helper:' "${callLog}"
)

runTransactionAggregateRunnerUsesFrameworkSelectorHelperContract() (
    local callLog="${TMP_DIR}/transaction-framework-helper-dispatch.log"

    : >"${callLog}"

    listRegressionTransactionSystemChildSelectors() {
        printf '%s\n' \
            nginx-service-failure \
            fail2ban-apply-transaction
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:jobs=%s:%s\n' "${PADM_REGRESSION_PARALLEL_JOBS:-}" "$*" >>"${callLog}"
    }

    runParallelRegressionSelectors() {
        printf 'legacy-helper:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runRegressionTransactionSystemSuiteRoot

    grep -qx 'framework:jobs='"${PADM_REGRESSION_TRANSACTION_SYSTEM_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}"':'"${TMP_DIR}"'/transaction-system-parallel-[0-9][0-9]* nginx-service-failure nginx-service-failure fail2ban-apply-transaction fail2ban-apply-transaction' "${callLog}"
    ! grep -q '^legacy-helper:' "${callLog}"
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

    runFrameworkParallelRegressionSelectors() {
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

runFrameworkParallelSelectorSupportsSelectorOnlyLimitContract() (
    set -euo pipefail
    local callLog="${TMP_DIR}/framework-parallel-selector-limit.log"

    : >"${callLog}"

    runRegisteredRegressionMain() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        [[ "${selector}" == "first" ]] && sleep 0.1
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }
    PADM_REGRESSION_SELECTOR_KIND[second]=function
    PADM_REGRESSION_SELECTOR_KIND[fourth]=function

    PADM_REGRESSION_PARALLEL_JOBS=1 PADM_REGRESSION_PARALLEL_SELECTOR_MODE=selectors \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/framework-parallel-selector-limit" \
        first \
        second \
        third \
        fourth

    grep -qx 'first-start' "${callLog}"
    grep -qx 'first-finish' "${callLog}"
    grep -qx 'second-start' "${callLog}"
    grep -qx 'second-finish' "${callLog}"
    grep -qx 'third-start' "${callLog}"
    grep -qx 'third-finish' "${callLog}"
    grep -qx 'fourth-start' "${callLog}"
    grep -qx 'fourth-finish' "${callLog}"
    awk '
        $0 == "first-finish" { firstFinish = NR }
        $0 == "second-start" { secondStart = NR }
        $0 == "second-finish" { secondFinish = NR }
        $0 == "third-start" { thirdStart = NR }
        $0 == "third-finish" { thirdFinish = NR }
        $0 == "fourth-start" { fourthStart = NR }
        END { exit !(firstFinish && secondStart && secondFinish && thirdStart && thirdFinish && fourthStart && firstFinish < secondStart && secondFinish < thirdStart && thirdFinish < fourthStart) }
    ' "${callLog}"
)

runFrameworkParallelSelectorSupportsSelectorOnlySlotRefillContract() (
    set -euo pipefail
    local callLog="${TMP_DIR}/framework-parallel-selector-slot-refill.log"
    local thirdStarted="${TMP_DIR}/framework-parallel-selector-third-started"

    : >"${callLog}"
    rm -f "${thirdStarted}"

    runRegisteredRegressionMain() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        case "${selector}" in
        first)
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${thirdStarted}" ]] && break
                sleep 0.05
            done
            ;;
        second) sleep 0.02 ;;
        third) : >"${thirdStarted}" ;;
        esac
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_JOBS=2 PADM_REGRESSION_PARALLEL_SELECTOR_MODE=selectors \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/framework-parallel-selector-slot-refill" \
        first \
        second \
        third

    grep -qx 'first-start' "${callLog}"
    grep -qx 'first-finish' "${callLog}"
    grep -qx 'second-start' "${callLog}"
    grep -qx 'second-finish' "${callLog}"
    grep -qx 'third-start' "${callLog}"
    grep -qx 'third-finish' "${callLog}"
    awk '
        $0 == "first-finish" { firstFinish = NR }
        $0 == "second-finish" { secondFinish = NR }
        $0 == "third-start" { thirdStart = NR }
        END { exit !(secondFinish && thirdStart && firstFinish && secondFinish < thirdStart && thirdStart < firstFinish) }
    ' "${callLog}"
)

runRuntimeSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/runtime.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q 'source "\${REGRESSION_RUNTIME_SUITE_DIR}/../framework/runtime.sh"' "${suiteFile}"
    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_RUNTIME_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    grep -q '^listRegressionRuntimeLightChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionRuntimeHeavyChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionRuntimeChildSelectors() {$' "${suiteFile}"
    grep -q '^runRegressionRuntimeSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionRuntimeParallelCompositionRegression() ' "${suiteFile}"
    grep -q 'PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs' "${suiteFile}"
    grep -q 'runFrameworkParallelRegressionSelectors "${TMP_DIR}/runtime-parallel-' "${suiteFile}"
    ! grep -q '^listRegressionRuntimeLightChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionRuntimeHeavyChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionRuntimeChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^runRegressionRuntime() {$' "${legacyScriptFile}"
    ! grep -q '^runRegressionRuntimeParallelCompositionRegression() ' "${legacyScriptFile}"
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
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_REALITY_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    grep -Eq '^runRegressionRealityCandidates\(\)[[:space:]]*[({]' "${suiteFile}"
    grep -Eq '^runRegressionRealityStream\(\)[[:space:]]*[({]' "${suiteFile}"
    grep -q '^runRegressionRealityCandidatesSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionRealityStreamSuiteRoot() {$' "${suiteFile}"
    ! grep -Eq '^runRegressionRealityCandidates\(\)[[:space:]]*[({]' "${legacyScriptFile}"
    ! grep -Eq '^runRegressionRealityStream\(\)[[:space:]]*[({]' "${legacyScriptFile}"
    ! grep -q '^registerRegressionScriptLeaf reality-candidates ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-candidates ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf reality-stream ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-stream ' "${suiteFile}"
    grep -q 'registerRegressionFunctionLeaf "${selector}" "${runner}"' "${suiteFile}"
    grep -q '^reality-candidates-fast runRealityCandidateFastRegression$' "${suiteFile}"
    grep -q '^reality-asn-scan-plan runRealityAsnScanPlanRegression$' "${suiteFile}"
    grep -q '^reality-candidates-full runRealityCandidateFullRegression$' "${suiteFile}"
    grep -q '^reality-stream-enable runRealityStreamEnableRegression$' "${suiteFile}"
    grep -q '^reality-stream-disable runRealityStreamDisableRegression$' "${suiteFile}"
    grep -q '^reality-config runRealityConfigRegression$' "${suiteFile}"
    grep -q '^reality-profile-failure runRealityProfileFailureRegression$' "${suiteFile}"
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
    done < <(listRegressionSubscriptionRemoteChildSelectors) >"${actualSelectorsFile}"

    cat <<'EOF' >"${expectedSelectorsFile}"
subscription-remote-unique
subscription-remote-rollback
subscription-remote-merge
subscription-remote-controlled
subscription-remote-append-failure
subscription-remote-commit-failure
subscription-remote-idempotent
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
    done < <(listRegressionSubscriptionTxChildSelectors) >"${actualSelectorsFile}"

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
    ! grep -q '^registerRegressionFunctionLeaf subscription-remote-fetch-' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-remote runRegressionSubscriptionRemoteSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionSubscriptionRemoteChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription-remote"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["subscription-remote"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["subscription-remote"]:-}" == "runRegressionSubscriptionRemoteSuiteRoot" ]]
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
    ! grep -q '^registerRegressionFunctionLeaf regression-subscription-write-transaction-' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-tx runRegressionSubscriptionTxSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionSubscriptionTxChildSelectors)
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription-tx"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_MODE["subscription-tx"]:-}" == "parallel" ]]
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["subscription-tx"]:-}" == "runRegressionSubscriptionTxSuiteRoot" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
}

runTargetedSubscriptionRestoreRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^registerRegressionFunctionLeaf subscribe-user-output-transaction runSubscribeUserOutputTransactionRegression$' "${suiteFile}" || return 1
    ! grep -Eq '^runRegressionTargetedSubscriptionRestore\(\)[[:space:]]*[({]' "${legacyFile}" || return 1
    ! grep -Eq '^[[:space:]]*targeted-subscription-restore\)$' "${legacyFile}" || return 1
    ! grep -Fq '|targeted-subscription-restore|' "${legacyFile}" || return 1
}

runSubscriptionAggregateRunnersUseSuiteLocalHelpersContract() (
    local status=0
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local callLog="${TMP_DIR}/subscription-suite-root-dispatch.log"

    : >"${callLog}"

    grep -Eq '^runRegressionSubscription\(\)[[:space:]]*[({]' "${suiteFile}" || status=1
    grep -Eq '^runRegressionSubscriptionRemote\(\)[[:space:]]*[({]' "${suiteFile}" || status=1
    grep -Eq '^runRegressionSubscriptionTx\(\)[[:space:]]*[({]' "${suiteFile}" || status=1
    ! grep -Eq '^runRegressionSubscription\(\)[[:space:]]*[({]' "${legacyScriptFile}" || status=1
    ! grep -Eq '^runRegressionSubscriptionRemote\(\)[[:space:]]*[({]' "${legacyScriptFile}" || status=1
    ! grep -Eq '^runRegressionSubscriptionTx\(\)[[:space:]]*[({]' "${legacyScriptFile}" || status=1

    runRegressionSubscription() {
        printf 'legacy-subscription\n' >>"${callLog}"
        return 97
    }

    runRegressionSubscriptionRemote() {
        printf 'legacy-subscription-remote\n' >>"${callLog}"
        return 97
    }

    runRegressionSubscriptionTx() {
        printf 'legacy-subscription-tx\n' >>"${callLog}"
        return 97
    }

    runRegressionSubscriptionSuiteRoot() {
        printf 'suite-subscription\n' >>"${callLog}"
    }

    runRegressionSubscriptionRemoteSuiteRoot() {
        printf 'suite-subscription-remote\n' >>"${callLog}"
    }

    runRegressionSubscriptionTxSuiteRoot() {
        printf 'suite-subscription-tx\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain subscription
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain subscription-remote
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain subscription-tx

    grep -qx 'suite-subscription' "${callLog}" || status=1
    grep -qx 'suite-subscription-remote' "${callLog}" || status=1
    grep -qx 'suite-subscription-tx' "${callLog}" || status=1
    ! grep -q '^legacy-subscription$' "${callLog}" || status=1
    ! grep -q '^legacy-subscription-remote$' "${callLog}" || status=1
    ! grep -q '^legacy-subscription-tx$' "${callLog}" || status=1

    return "${status}"
)

runSubscriptionAggregateRunnersUseFrameworkSelectorHelperContract() (
    local callLog="${TMP_DIR}/subscription-framework-helper-dispatch.log"

    : >"${callLog}"

    listRegressionSubscriptionRemoteChildSelectors() {
        printf '%s\n' \
            subscription-remote-unique \
            subscription-remote-merge
    }

    listRegressionSubscriptionTxChildSelectors() {
        printf '%s\n' \
            sing-box-subscribe-write \
            subscribe-user-output-transaction
    }

    listRegressionSubscriptionLightChildSelectors() {
        printf '%s\n' \
            subscription-output \
            subscription-state
    }

    listRegressionSubscriptionHeavyChildSelectors() {
        printf '%s\n' \
            subscription-tx \
            subscription-remote
    }

    listRegressionSubscriptionChildSelectors() {
        printf '%s\n' \
            subscription-output \
            subscription-state \
            subscription-remote \
            subscription-tx
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:jobs=%s:%s\n' "${PADM_REGRESSION_PARALLEL_JOBS:-}" "$*" >>"${callLog}"
    }

    runParallelRegressionSelectors() {
        printf 'legacy-helper:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runRegressionSubscriptionRemoteSuiteRoot
    runRegressionSubscriptionTxSuiteRoot
    runRegressionSubscriptionSuiteRoot
    PADM_REGRESSION_SUBSCRIPTION_RESOURCE_PROFILE=all runRegressionSubscriptionSuiteRoot

    grep -qx 'framework:jobs='"${PADM_REGRESSION_SUBSCRIPTION_REMOTE_PARALLEL_JOBS:-4}"':'"${TMP_DIR}"'/subscription-remote-parallel-[0-9][0-9]* subscription-remote-unique subscription-remote-unique subscription-remote-merge subscription-remote-merge' "${callLog}"
    grep -qx 'framework:jobs=:'"${TMP_DIR}"'/subscription-tx-parallel-[0-9][0-9]* sing-box-subscribe-write sing-box-subscribe-write subscribe-user-output-transaction subscribe-user-output-transaction' "${callLog}"
    grep -qx 'framework:jobs=:'"${TMP_DIR}"'/subscription-parallel-[0-9][0-9]* subscription-output subscription-output subscription-state subscription-state subscription-remote subscription-remote subscription-tx subscription-tx' "${callLog}"
    grep -qx 'framework:jobs=:'"${TMP_DIR}"'/subscription-parallel-light-[0-9][0-9]* subscription-output subscription-output subscription-state subscription-state' "${callLog}"
    grep -qx 'framework:jobs=:'"${TMP_DIR}"'/subscription-parallel-heavy-[0-9][0-9]* subscription-tx subscription-tx subscription-remote subscription-remote' "${callLog}"
    ! grep -q '^legacy-helper:' "${callLog}"
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

runRuntimeAggregateRunnerUsesFrameworkSelectorHelperContract() (
    local callLog="${TMP_DIR}/runtime-framework-helper-dispatch.log"

    : >"${callLog}"

    listRegressionRuntimeLightChildSelectors() {
        printf '%s\n' \
            runtime-core \
            runtime-tempdir
    }

    listRegressionRuntimeHeavyChildSelectors() {
        printf '%s\n' \
            reality-candidates \
            reality-config
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:jobs=%s:%s\n' "${PADM_REGRESSION_PARALLEL_JOBS:-}" "$*" >>"${callLog}"
    }

    runParallelRegressionSelectors() {
        printf 'legacy-helper:%s\n' "$*" >>"${callLog}"
        return 97
    }

    PADM_REGRESSION_RUNTIME_RESOURCE_PROFILE=all runRegressionRuntimeSuiteRoot

    grep -qx 'framework:jobs='"${PADM_REGRESSION_RUNTIME_LIGHT_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}"':'"${TMP_DIR}"'/runtime-parallel-light-[0-9][0-9]* runtime-core runtime-core runtime-tempdir runtime-tempdir' "${callLog}"
    grep -qx 'framework:jobs='"${PADM_REGRESSION_RUNTIME_HEAVY_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-2}}"':'"${TMP_DIR}"'/runtime-parallel-heavy-[0-9][0-9]* reality-candidates reality-candidates reality-config reality-config' "${callLog}"
    ! grep -q '^legacy-helper:' "${callLog}"
)

runRealityAggregateRunnersUseSuiteLocalHelpersContract() (
    local status=0
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/reality.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local callLog="${TMP_DIR}/reality-aggregate-suite-root-dispatch.log"

    : >"${callLog}"

    grep -Eq '^runRegressionRealityCandidates\(\)[[:space:]]*[({]' "${suiteFile}" || status=1
    grep -Eq '^runRegressionRealityStream\(\)[[:space:]]*[({]' "${suiteFile}" || status=1
    ! grep -Eq '^runRegressionRealityCandidates\(\)[[:space:]]*[({]' "${legacyScriptFile}" || status=1
    ! grep -Eq '^runRegressionRealityStream\(\)[[:space:]]*[({]' "${legacyScriptFile}" || status=1

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

    grep -qx 'suite-reality-candidates' "${callLog}" || status=1
    grep -qx 'suite-reality-stream' "${callLog}" || status=1
    ! grep -q '^legacy-reality-candidates$' "${callLog}" || status=1
    ! grep -q '^legacy-reality-stream$' "${callLog}" || status=1
    return "${status}"
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

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:%s\n' "$*" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_JOBS=1 PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain transaction-system

    grep -q '^framework:'"${TMP_DIR}"'/transaction-system-parallel-[0-9][0-9]* ' "${callLog}"
    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        grep -q " ${selector} ${selector}\(\|$\)" "${callLog}"
        [[ "$(grep -o " ${selector} ${selector}" "${callLog}" | wc -l)" == "1" ]]
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

runRegressionSelectorDispatchCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-selector-dispatch-composition.log"

    : >"${callLog}"

    bash() {
        printf 'script=%s selector=%s suppress=%s\n' "$1" "$2" "${PADM_REGRESSION_SUPPRESS_DONE:-}" >>"${callLog}"
    }

    runRegressionAllSelector subscription-state
    runRegressionAllSelector remote-control
    runRegressionAllSelector routing

    grep -qx "script=${REGRESSION_ENTRY_SCRIPT_PATH} selector=subscription-state suppress=1" "${callLog}"
    grep -qx "script=${REGRESSION_ENTRY_SCRIPT_PATH} selector=remote-control suppress=1" "${callLog}"
    grep -qx "script=${REGRESSION_ENTRY_SCRIPT_PATH} selector=routing suppress=1" "${callLog}"
    ! grep -q "script=${REGRESSION_LEGACY_SCRIPT_PATH}" "${callLog}"
)

runRegressionParallelSelectorLimitCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-parallel-selector-limit-composition.log"

    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        [[ "${selector}" == "first" ]] && sleep 0.1
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_JOBS=1 runParallelRegressionSelectors "${TMP_DIR}/parallel-selector-limit-composition" \
        first \
        second \
        third

    grep -qx 'first-start' "${callLog}"
    grep -qx 'first-finish' "${callLog}"
    grep -qx 'second-start' "${callLog}"
    grep -qx 'second-finish' "${callLog}"
    grep -qx 'third-start' "${callLog}"
    grep -qx 'third-finish' "${callLog}"
    awk '
        $0 == "first-finish" { firstFinish = NR }
        $0 == "second-start" { secondStart = NR }
        $0 == "second-finish" { secondFinish = NR }
        $0 == "third-start" { thirdStart = NR }
        END { exit !(firstFinish && secondStart && secondFinish && thirdStart && firstFinish < secondStart && secondFinish < thirdStart) }
    ' "${callLog}"
)

runRegressionParallelSelectorSlotRefillCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-parallel-selector-slot-refill-composition.log"
    local thirdStarted="${TMP_DIR}/regression-parallel-selector-slot-refill-third-started"

    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        case "${selector}" in
        first)
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${thirdStarted}" ]] && break
                sleep 0.05
            done
            ;;
        second) sleep 0.02 ;;
        third) : >"${thirdStarted}" ;;
        esac
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_JOBS=2 runParallelRegressionSelectors "${TMP_DIR}/parallel-selector-slot-refill-composition" \
        first \
        second \
        third

    grep -qx 'first-start' "${callLog}"
    grep -qx 'first-finish' "${callLog}"
    grep -qx 'second-start' "${callLog}"
    grep -qx 'second-finish' "${callLog}"
    grep -qx 'third-start' "${callLog}"
    grep -qx 'third-finish' "${callLog}"
    awk '
        $0 == "first-finish" { firstFinish = NR }
        $0 == "second-finish" { secondFinish = NR }
        $0 == "third-start" { thirdStart = NR }
        END { exit !(secondFinish && thirdStart && firstFinish && secondFinish < thirdStart && thirdStart < firstFinish) }
    ' "${callLog}"
)

runRegressionDispatcherContracts() {
    runRegressionStep regression-dispatcher-registry-only runRegressionDispatcherRegistryOnlyContract &&
        runRegressionStep subscription-state-no-implicit-full-fallback runSubscriptionStateNoImplicitFullFallbackContract &&
        runRegressionStep subscription-state-shim-uses-source-only-full runSubscriptionStateShimUsesSourceOnlyFullContract &&
        runRegressionStep subscription-state-shim-stays-thin runSubscriptionStateShimStaysThinContract &&
        runRegressionStep legacy-regression-scripts-require-dispatcher runLegacyRegressionScriptsRequireDispatcherContract &&
        runRegressionStep subscription-state-suite-uses-function-registry runSubscriptionStateSuiteUsesFunctionRegistryContract &&
        runRegressionStep subscription-state-selector-helpers-stay-aligned runSubscriptionStateSelectorHelpersStayAlignedContract &&
        runRegressionStep subscription-state-core-aggregate-runner-registration runSubscriptionStateCoreAggregateRunnerRegistrationContract &&
        runRegressionStep subscription-state-aggregate-runner-registration runSubscriptionStateAggregateRunnerRegistrationContract &&
        runRegressionStep subscription-state-full-uses-framework-parallel-helper runSubscriptionStateFullUsesFrameworkParallelHelperContract &&
        runRegressionStep subscription-state-aggregates-support-source-only runSubscriptionStateAggregatesSupportSourceOnlyExecutionContract &&
        runRegressionStep remote-control-suite-uses-function-registry runRemoteControlSuiteUsesFunctionRegistryContract &&
        runRegressionStep remote-control-public-selector-retirement runRemoteControlPublicSelectorRetirementContract &&
        runRegressionStep legacy-retires-suite-owned-wrappers runLegacyRetiresSuiteOwnedWrappersContract &&
        runRegressionStep remote-control-aggregates-support-source-only runRemoteControlAggregatesSupportSourceOnlyExecutionContract &&
        runRegressionStep remote-control-selector-helpers-stay-aligned runRemoteControlSelectorHelpersStayAlignedContract &&
        runRegressionStep remote-control-aggregate-runner-registration runRemoteControlAggregateRunnerRegistrationContract &&
        runRegressionStep fast-suite-uses-function-registry runFastSuiteUsesFunctionRegistryContract &&
        runRegressionStep fast-legacy-retirement runFastLegacyRetirementContract &&
        runRegressionStep fast-reality-selector-helpers-stay-aligned runFastRealitySelectorHelpersStayAlignedContract &&
        runRegressionStep fast-reality-aggregate-runner-registration runFastRealityAggregateRunnerRegistrationContract &&
        runRegressionStep fast-reality-legacy-retirement runFastRealityLegacyRetirementContract &&
        runRegressionStep fast-reality-aggregate-runner-dispatches-children-in-order runFastRealityAggregateRunnerDispatchesChildrenInOrderContract &&
        runRegressionStep fast-suite-uses-suite-local-helper runFastSuiteUsesSuiteLocalHelperContract &&
        runRegressionStep platform-suite-uses-function-registry runPlatformSuiteUsesFunctionRegistryContract &&
        runRegressionStep platform-public-selector-retirement runPlatformPublicSelectorRetirementContract &&
        runRegressionStep all-suite-uses-function-registry runAllSuiteUsesFunctionRegistryContract &&
        runRegressionStep all-public-selector-retirement runAllPublicSelectorRetirementContract &&
        runRegressionStep framework-parallel-selector-supports-selector-only-limit runFrameworkParallelSelectorSupportsSelectorOnlyLimitContract &&
        runRegressionStep framework-parallel-selector-supports-selector-only-slot-refill runFrameworkParallelSelectorSupportsSelectorOnlySlotRefillContract &&
        runRegressionStep fast-platform-supports-source-only runFastPlatformSourceOnlyExecutionContract &&
        runRegressionStep legacy-suite-uses-function-registry runLegacySuiteUsesFunctionRegistryContract &&
        runRegressionStep platform-suite-uses-suite-local-helpers runPlatformSuiteUsesSuiteLocalHelpersContract &&
        runRegressionStep tls-suite-uses-function-registry runTlsSuiteUsesFunctionRegistryContract &&
        runRegressionStep tls-legacy-retirement runTlsLegacyRetirementContract &&
        runRegressionStep tls-selector-helpers-stay-aligned runTlsSelectorHelpersStayAlignedContract &&
        runRegressionStep tls-aggregate-runner-registration runTlsAggregateRunnerRegistrationContract &&
        runRegressionStep tls-aggregate-runner-uses-suite-local-helper runTlsAggregateRunnerUsesSuiteLocalHelperContract &&
        runRegressionStep legacy-direct-leaf-selectors-use-function-registry runLegacyDirectLeafSelectorsUseFunctionRegistryContract &&
        runRegressionStep composition-leaf-selectors-use-suite-local-registry runCompositionLeafSelectorsUseSuiteLocalRegistryContract &&
        runRegressionStep transaction-direct-leaf-selectors-use-function-registry runTransactionDirectLeafSelectorsUseFunctionRegistryContract &&
        runRegressionStep transaction-core-direct-leaf-selectors-use-function-registry runTransactionCoreDirectLeafSelectorsUseFunctionRegistryContract &&
        runRegressionStep subscription-direct-leaf-selectors-use-function-registry runSubscriptionDirectLeafSelectorsUseFunctionRegistryContract &&
        runRegressionStep subscription-composition-leaf-selectors-use-function-registry runSubscriptionCompositionLeafSelectorsUseFunctionRegistryContract &&
        runRegressionStep targeted-subscription-restore-retirement runTargetedSubscriptionRestoreRetirementContract &&
        runRegressionStep ui-suite-uses-function-registry runUiSuiteUsesFunctionRegistryContract &&
        runRegressionStep ui-smoke-legacy-wrapper-retirement runUiSmokeLegacyWrapperRetirementContract &&
        runRegressionStep ui-full-legacy-wrapper-retirement runUiFullLegacyWrapperRetirementContract &&
        runRegressionStep ui-public-selectors-use-function-registry runUiPublicSelectorsUseFunctionRegistryContract &&
        runRegressionStep ui-selector-helpers-stay-aligned runUiSelectorHelpersStayAlignedContract &&
        runRegressionStep ui-aggregate-runner-registration runUiAggregateRunnerRegistrationContract &&
        runRegressionStep ui-aggregate-runner-uses-suite-local-helper runUiAggregateRunnerUsesSuiteLocalHelperContract &&
        runRegressionStep ui-aggregate-runner-uses-framework-selector-helper runUiAggregateRunnerUsesFrameworkSelectorHelperContract &&
        runRegressionStep routing-suite-uses-function-registry runRoutingSuiteUsesFunctionRegistryContract &&
        runRegressionStep routing-selector-helpers-stay-aligned runRoutingSelectorHelpersStayAlignedContract &&
        runRegressionStep routing-aggregate-runner-registration runRoutingAggregateRunnerRegistrationContract &&
        runRegressionStep routing-aggregate-runner-uses-suite-local-helper runRoutingAggregateRunnerUsesSuiteLocalHelperContract &&
        runRegressionStep routing-aggregate-runner-uses-framework-selector-helper runRoutingAggregateRunnerUsesFrameworkSelectorHelperContract &&
        runRegressionStep transaction-suite-uses-function-registry runTransactionSuiteUsesFunctionRegistryContract &&
        runRegressionStep transaction-core-selector-helpers-stay-aligned runTransactionCoreSelectorHelpersStayAlignedContract &&
        runRegressionStep transaction-core-registered-child-selectors-aligned runTransactionCoreRegisteredChildSelectorsAlignedContract &&
        runRegressionStep transaction-core-aggregate-runner-registration runTransactionCoreAggregateRunnerRegistrationContract &&
        runRegressionStep transaction-selector-helpers-stay-aligned runTransactionSelectorHelpersStayAlignedContract &&
        runRegressionStep transaction-aggregate-runner-registration runTransactionAggregateRunnerRegistrationContract &&
        runRegressionStep transaction-system-aggregate-runner-registration runTransactionSystemAggregateRunnerRegistrationContract &&
        runRegressionStep transaction-suite-uses-suite-local-helpers runTransactionSuiteUsesSuiteLocalHelpersContract &&
        runRegressionStep transaction-core-aggregate-runner-uses-framework-selector-helper runTransactionCoreAggregateRunnerUsesFrameworkSelectorHelperContract &&
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
        runRegressionStep subscription-aggregate-runners-use-framework-selector-helper runSubscriptionAggregateRunnersUseFrameworkSelectorHelperContract &&
        runRegressionStep reality-suite-uses-function-registry runRealitySuiteUsesFunctionRegistryContract &&
        runRegressionStep reality-candidates-aggregate-runner-registration runRealityCandidatesAggregateRunnerRegistrationContract &&
        runRegressionStep reality-candidates-aggregate-runner-dispatches-children-in-order runRealityCandidatesAggregateRunnerDispatchesChildrenInOrderContract &&
        runRegressionStep reality-stream-aggregate-runner-registration runRealityStreamAggregateRunnerRegistrationContract &&
        runRegressionStep reality-stream-aggregate-runner-dispatches-children-in-order runRealityStreamAggregateRunnerDispatchesChildrenInOrderContract &&
        runRegressionStep runtime-suite-uses-function-registry runRuntimeSuiteUsesFunctionRegistryContract &&
        runRegressionStep runtime-selector-helpers-stay-aligned runRuntimeSelectorHelpersStayAlignedContract &&
        runRegressionStep runtime-aggregate-runner-registration runRuntimeAggregateRunnerRegistrationContract &&
        runRegressionStep runtime-aggregate-runner-uses-suite-local-helper runRuntimeAggregateRunnerUsesSuiteLocalHelperContract &&
        runRegressionStep runtime-aggregate-runner-uses-framework-selector-helper runRuntimeAggregateRunnerUsesFrameworkSelectorHelperContract &&
        runRegressionStep reality-aggregate-runners-use-suite-local-helpers runRealityAggregateRunnersUseSuiteLocalHelpersContract &&
        runRegressionStep parallel-selector-collects-exited-child-without-rc runParallelSelectorCollectsExitedChildWithoutRcContract &&
        runRegressionStep transaction-core-compatible-dispatcher-leaves-execute runTransactionCoreCompatibleDispatcherLeavesExecutionContract &&
        runRegressionStep transaction-system-aggregate-dispatches-children-once runTransactionSystemAggregateDispatchesChildrenExactlyOnceContract &&
        runRegressionStep legacy-reality-stubs-survive-suite-load runLegacyRealityStubsSurviveSuiteLoadContract
}

registerRegressionFunctionLeaf regression-dispatcher-contract runRegressionDispatcherContracts
registerRegressionFunctionLeaf regression-selector-dispatch-composition runRegressionSelectorDispatchCompositionRegression
registerRegressionFunctionLeaf regression-parallel-selector-limit-composition runRegressionParallelSelectorLimitCompositionRegression
registerRegressionFunctionLeaf regression-parallel-selector-slot-refill-composition runRegressionParallelSelectorSlotRefillCompositionRegression
