#!/usr/bin/env bash

REGRESSION_UI_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_UI_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_UI_SUITE_DIR}/../subscription_groups_legacy.sh" --reuse

runRegressionUiLegacyLeafWithCompat() (
    # Re-source legacy UI fixtures in an isolated subshell so parallel menu-smoke
    # leaves do not share source-time TMP_DIR-derived state directories.
    PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_UI_SUITE_DIR}/../subscription_groups_legacy.sh"
    "$@"
)

runRegressionUiSmokeSuiteRoot() {
    local actions=
    local output=
    local oldCoreInstallType="${coreInstallType:-}"
    coreInstallType=
    recordMenuAction() {
        actions+="$1"$'\n'
    }
    assertMenuAction() {
        grep -qxF "$1" <<<"${actions}"
    }
    resetMenuActions() {
        actions=
    }
    menu() { recordMenuAction menu; }
    menuLine() { output+="$*"$'\n'; }
    menuItem() { output+="$2 $3"$'\n'; }
    menuRecommendedItem() { output+="$2 $3"$'\n'; }
    menuReturnItem() { output+="$2 $3"$'\n'; }
    statusCard() { recordMenuAction "statusCard:$1"; }
    errorCard() { recordMenuAction "errorCard:$1"; }
    successCard() { recordMenuAction "successCard:$1"; }
    autoRead() {
        local targetVar=$3
        local input=
        IFS= read -r input || input=
        printf -v "${targetVar}" '%s' "${input}"
    }
    selectCoreInstall() { recordMenuAction selectCoreInstall; }
    manageXHTTP() { recordMenuAction manageXHTTP; }
    manageHysteria() { recordMenuAction manageHysteria; }
    manageTuic() { recordMenuAction manageTuic; }
    addCorePort() { recordMenuAction addCorePort; }
    manageCDN() { recordMenuAction manageCDN; }
    manageFail2ban() { recordMenuAction manageFail2ban; }
    updatePadm() { recordMenuAction "updatePadm:$*"; }
    showPadmScriptInstallStatus() { recordMenuAction showPadmScriptInstallStatus; }
    bbrInstall() { recordMenuAction bbrInstall; }

    installMenu <<<"6"
    assertMenuAction selectCoreInstall
    grep -q "不知道怎么选时，建议直接选 1" <<<"${output}"
    grep -q "entry 是客户端连接地址" <<<"${output}"

    resetMenuActions
    installXray() { recordMenuAction installXray; }
    installXrayService() { recordMenuAction installXrayService; }
    initXrayConfig() { recordMenuAction initXrayConfig; }
    cleanUp() { recordMenuAction cleanUp; }
    checkGFWStatue() { recordMenuAction checkGFWStatue; }
    showAccounts() { recordMenuAction showAccounts; }
    installTools() { recordMenuAction installTools; }
    readLastInstallationConfig() { recordMenuAction readLastInstallationConfig; }
    collectEntryProfile() { realityEntryHost=smoke.example.com; recordMenuAction collectEntryProfile; }
    persistRealityEntryProfile() { recordMenuAction persistRealityEntryProfile; }
    unInstallSubscribe() { recordMenuAction unInstallSubscribe; }
    handleNginx() { recordMenuAction "handleNginx:$*"; }
    serviceQueueRestart() { recordMenuAction "serviceQueueRestart:$*"; }
    serviceQueueApply() { recordMenuAction serviceQueueApply; }
    subscriptionWireGuardControlEnabled() { return 0; }
    refreshSubscriptionWireGuardNginxControl() { recordMenuAction refreshSubscriptionWireGuardNginxControl; }
    installXrayReality
    ! grep -q '^handleNginx:' <<<"${actions}"
    ! assertMenuAction refreshSubscriptionWireGuardNginxControl
    assertMenuAction serviceQueueApply
    assertMenuAction persistRealityEntryProfile
    [[ "${actions}" == *$'serviceQueueApply\npersistRealityEntryProfile\ncheckGFWStatue\ncleanUp\nshowAccounts\n'* ]]

    resetMenuActions
    output=
    systemScriptMenu <<<"3"
    assertMenuAction manageFail2ban
    grep -q "Fail2ban 防护" <<<"${output}"
    resetMenuActions
    systemScriptMenu <<<"1"
    assertMenuAction 'updatePadm:1'
    resetMenuActions
    systemScriptMenu <<<"2"
    assertMenuAction showPadmScriptInstallStatus
    resetMenuActions
    systemScriptMenu <<<"4"
    assertMenuAction bbrInstall
    [[ "$(protocolMenuDescription 5)" == "推荐；sing-box / tcp / tls" ]]
    [[ "$(protocolMenuDescription 4)" == "推荐；sing-box / tcp / tls" ]]
    coreInstallType="${oldCoreInstallType}"
}

runUiLeafSelectorListRegression() {
    local orchestrationRoot=$1
    local selectorListFn=$2
    local defaultJobs=$3

    runFrameworkParallelRegressionSelectorListWithJobs \
        "${orchestrationRoot}" \
        "${selectorListFn}" \
        "${PADM_REGRESSION_UI_LEAF_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-${defaultJobs}}}"
}

listRegressionUiFullChildSelectors() {
    printf '%s\n' \
        ui-full-subscription-main-entry \
        ui-full-subscription-main-publish-service \
        ui-full-subscription-main-publish-user \
        ui-full-subscription-main-publish-sync \
        ui-full-subscription-main-maintenance \
        ui-full-subscription-controlled \
        ui-full-core \
        ui-full-core-maintenance
}

listRegressionUiFullSubscriptionMainChildSelectors() {
    printf '%s\n' \
        ui-full-subscription-main-entry \
        ui-full-subscription-main-publish-service \
        ui-full-subscription-main-publish-user \
        ui-full-subscription-main-publish-sync \
        ui-full-subscription-main-maintenance
}

listRegressionUiFullSubscriptionMainPublishChildSelectors() {
    printf '%s\n' \
        ui-full-subscription-main-publish-service \
        ui-full-subscription-main-publish-user \
        ui-full-subscription-main-publish-sync
}

listRegressionUiFullSubscriptionMainPublishUserChildSelectors() {
    printf '%s\n' \
        ui-full-subscription-main-publish-user-empty \
        ui-full-subscription-main-publish-user-create \
        ui-full-subscription-main-publish-user-inspect
}

listRegressionUiFullSubscriptionMainPublishSyncChildSelectors() {
    printf '%s\n' \
        ui-full-subscription-main-publish-sync-skip \
        ui-full-subscription-main-publish-sync-enable
}

listRegressionWireGuardMenuFlowChildSelectors() {
    printf '%s\n' \
        wireguard-menu-flow-bootstrap \
        wireguard-menu-flow-peer-add-update \
        wireguard-menu-flow-peer-rollback-apply \
        wireguard-menu-flow-peer-rollback-source \
        wireguard-menu-flow-peer-rollback-credential \
        wireguard-menu-flow-peer-source-control \
        wireguard-menu-flow-control-restore
}

listRegressionWireGuardMenuFlowPeerTransactionChildSelectors() {
    printf '%s\n' \
        wireguard-menu-flow-peer-add-update \
        wireguard-menu-flow-peer-rollback \
        wireguard-menu-flow-peer-source-control
}

listRegressionWireGuardMenuFlowPeerRollbackChildSelectors() {
    printf '%s\n' \
        wireguard-menu-flow-peer-rollback-apply \
        wireguard-menu-flow-peer-rollback-source \
        wireguard-menu-flow-peer-rollback-credential
}

listRegressionWireGuardMenuFlowPeerRollbackApplyChildSelectors() {
    printf '%s\n' \
        wireguard-menu-flow-peer-rollback-apply-service \
        wireguard-menu-flow-peer-rollback-apply-restore
}

listRegressionWireGuardMenuFlowPeerRollbackCredentialChildSelectors() {
    printf '%s\n' \
        wireguard-menu-flow-peer-rollback-credential-write \
        wireguard-menu-flow-peer-rollback-credential-groups-restore
}

listRegressionWireGuardMenuFlowPeerSourceControlChildSelectors() {
    printf '%s\n' \
        wireguard-menu-flow-peer-source-control-toggle \
        wireguard-menu-flow-peer-source-control-clear-error \
        wireguard-menu-flow-peer-source-control-status
}

listRegressionUiChildSelectors() {
    printf '%s\n' \
        ui-full-subscription-main-publish-sync-enable \
        wireguard-menu-flow-peer-rollback-apply-service \
        wireguard-menu-flow-peer-rollback-credential-write \
        wireguard-menu-flow-peer-rollback-source \
        ui-full-subscription-main-publish-sync-skip \
        wireguard-menu-flow-peer-rollback-apply-restore \
        wireguard-menu-flow-peer-rollback-credential-groups-restore \
        ui-full-subscription-main-publish-user-inspect \
        wireguard-menu-flow-peer-source-control-toggle \
        ui-full-subscription-main-publish-user-create \
        ui-full-subscription-main-publish-service \
        wireguard-menu-flow-peer-add-update \
        wireguard-menu-flow-peer-source-control-clear-error \
        wireguard-menu-flow-peer-source-control-status \
        ui-full-subscription-main-publish-user-empty \
        ui-full-subscription-main-maintenance \
        wireguard-menu-flow-control-restore \
        wireguard-menu-flow-bootstrap \
        ui-full-subscription-main-entry \
        ui-full-subscription-controlled \
        ui-full-core \
        ui-full-core-maintenance \
        ui-smoke \
        wireguard-restore-runner
}

listRegressionUiAllProfileChildSelectors() {
    printf '%s\n' \
        wireguard-menu-flow-peer-rollback-credential \
        wireguard-menu-flow-peer-rollback-apply \
        wireguard-menu-flow-peer-rollback-source \
        wireguard-menu-flow-bootstrap \
        wireguard-menu-flow-peer-add-update \
        wireguard-menu-flow-peer-source-control \
        wireguard-menu-flow-control-restore \
        ui-full-subscription-main-publish-sync \
        ui-full-subscription-main-maintenance \
        ui-full-subscription-main-publish-user \
        ui-full-subscription-controlled \
        ui-full-subscription-main-publish-service \
        ui-smoke \
        ui-full-subscription-main-entry \
        ui-full-core \
        ui-full-core-maintenance \
        wireguard-restore-runner
}

runRegressionUiSuiteRoot() {
    if [[ "${PADM_REGRESSION_UI_RESOURCE_PROFILE:-}" == "all" ]]; then
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/ui-parallel-${BASHPID:-$$}" \
            listRegressionUiAllProfileChildSelectors
        return
    fi

    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/ui-parallel-${BASHPID:-$$}" \
        listRegressionUiChildSelectors
}

runRegressionUiLongTailSplitCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-ui-long-tail-split-composition.log"

    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        if [[ "${selector}" == "ui-full-subscription-main-publish-sync-enable" ]]; then
            runFrameworkWaitForFile "${TMP_DIR}/wireguard-menu-flow-peer-rollback-apply-service-started"
        elif [[ "${selector}" == "wireguard-menu-flow-peer-rollback-apply-service" ]]; then
            : >"${TMP_DIR}/wireguard-menu-flow-peer-rollback-apply-service-started"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionUiSuiteRoot

    runFrameworkAssertSelectorListLogged "${callLog}" listRegressionUiChildSelectors
    awk '
        $0 == "ui-full-subscription-main-publish-sync-enable-start" { syncStart = NR }
        $0 == "wireguard-menu-flow-peer-rollback-apply-service-start" { applyStart = NR }
        $0 == "ui-full-subscription-main-publish-sync-enable-finish" { syncFinish = NR }
        END { exit !(syncStart && applyStart && syncFinish && applyStart < syncFinish) }
    ' "${callLog}"
    ! grep -qx 'ui-full-subscription-main-publish-sync-start' "${callLog}"
    ! grep -qx 'ui-full-subscription-main-publish-sync-finish' "${callLog}"
    ! grep -qx 'ui-full-subscription-main-publish-user-start' "${callLog}"
    ! grep -qx 'ui-full-subscription-main-publish-user-finish' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-rollback-apply-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-rollback-apply-finish' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-rollback-credential-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-rollback-credential-finish' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-source-control-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-source-control-finish' "${callLog}"

    : >"${callLog}"
    PADM_REGRESSION_UI_RESOURCE_PROFILE=all PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionUiSuiteRoot
    runFrameworkAssertSelectorListLogged "${callLog}" listRegressionUiAllProfileChildSelectors
    ! grep -qx 'ui-full-subscription-main-publish-sync-enable-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-rollback-apply-service-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-rollback-credential-write-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-source-control-toggle-start' "${callLog}"
    ! grep -qx 'ui-full-subscription-main-publish-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-transaction-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-rollback-start' "${callLog}"
    ! grep -qx 'ui-full-subscription-main-start' "${callLog}"
    ! grep -qx 'ui-full-start' "${callLog}"

    : >"${callLog}"
    PADM_REGRESSION_PARALLEL_JOBS=4 PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionUiSuiteRoot
    awk '
        /-start$/ {
            starts++
            if ($0 == "ui-full-subscription-main-publish-sync-enable-start") { publishStart = starts }
            if ($0 == "wireguard-menu-flow-peer-rollback-apply-service-start") { peerRollbackStart = starts }
        }
        END { exit !(publishStart && peerRollbackStart && publishStart <= 4 && peerRollbackStart <= 4) }
    ' "${callLog}"

    : >"${callLog}"
    PADM_REGRESSION_SUPPRESS_DONE=1 \
        PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector \
        runRegisteredRegressionMain ui-full-subscription-main-publish-user
    runFrameworkAssertSelectorListLogged "${callLog}" listRegressionUiFullSubscriptionMainPublishUserChildSelectors
    ! grep -q '^ui-full:subscription-main-publish-user-start$' "${callLog}"

    : >"${callLog}"
    PADM_REGRESSION_SUPPRESS_DONE=1 \
        PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector \
        runRegisteredRegressionMain ui-full-subscription-main-publish-sync
    runFrameworkAssertSelectorListLogged "${callLog}" listRegressionUiFullSubscriptionMainPublishSyncChildSelectors

    : >"${callLog}"
    PADM_REGRESSION_SUPPRESS_DONE=1 \
        PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector \
        runRegisteredRegressionMain wireguard-menu-flow-peer-rollback-apply
    runFrameworkAssertSelectorListLogged "${callLog}" listRegressionWireGuardMenuFlowPeerRollbackApplyChildSelectors

    : >"${callLog}"
    PADM_REGRESSION_SUPPRESS_DONE=1 \
        PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector \
        runRegisteredRegressionMain wireguard-menu-flow-peer-rollback-credential
    runFrameworkAssertSelectorListLogged "${callLog}" listRegressionWireGuardMenuFlowPeerRollbackCredentialChildSelectors

    : >"${callLog}"
    PADM_REGRESSION_SUPPRESS_DONE=1 \
        PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector \
        runRegisteredRegressionMain wireguard-menu-flow-peer-source-control
    runFrameworkAssertSelectorListLogged "${callLog}" listRegressionWireGuardMenuFlowPeerSourceControlChildSelectors

    : >"${callLog}"
    PADM_REGRESSION_SUPPRESS_DONE=1 \
        PADM_REGRESSION_UI_LEAF_PARALLEL_JOBS=1 \
        PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector \
        runRegisteredRegressionMain ui-full-subscription-main-publish-user
    awk '
        $0 == "ui-full-subscription-main-publish-user-empty-finish" { firstFinish = NR }
        $0 == "ui-full-subscription-main-publish-user-create-start" { secondStart = NR }
        $0 == "ui-full-subscription-main-publish-user-create-finish" { secondFinish = NR }
        $0 == "ui-full-subscription-main-publish-user-inspect-start" { thirdStart = NR }
        END { exit !(firstFinish && secondStart && secondFinish && thirdStart && firstFinish < secondStart && secondFinish < thirdStart) }
    ' "${callLog}"
)

runRegressionUiLegacyTmpDirIsolationRegression() (
    set -euo pipefail
    local originalTmpDir="${TMP_DIR}"

    # Simulate later suite loads re-sourcing bootstrap and drifting TMP_DIR.
    source "${REGRESSION_UI_SUITE_DIR}/../bootstrap.sh"
    [[ "${TMP_DIR}" != "${originalTmpDir}" ]]

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain ui-full-subscription-main-entry
)

registerRegressionFunctionLeaf ui-smoke runRegressionUiSmokeSuiteRoot
registerRegressionFunctionLeaf ui-full-core runRegressionUiLegacyLeafWithCompat runMenuSmokeRegression core
registerRegressionFunctionLeaf ui-full-subscription-main-entry runRegressionUiLegacyLeafWithCompat runMenuSmokeRegression subscription-main-entry
registerRegressionFunctionLeaf ui-full-subscription-main-publish-service runRegressionUiLegacyLeafWithCompat runMenuSmokeRegression subscription-main-publish-service
registerRegressionFunctionLeaf ui-full-subscription-main-publish-user-empty runRegressionUiLegacyLeafWithCompat runMenuSmokeRegression subscription-main-publish-user-empty
registerRegressionFunctionLeaf ui-full-subscription-main-publish-user-create runRegressionUiLegacyLeafWithCompat runMenuSmokeRegression subscription-main-publish-user-create
registerRegressionFunctionLeaf ui-full-subscription-main-publish-user-inspect runRegressionUiLegacyLeafWithCompat runMenuSmokeRegression subscription-main-publish-user-inspect
registerRegressionFunctionLeaf ui-full-subscription-main-publish-sync-skip runRegressionUiLegacyLeafWithCompat runMenuSmokeRegression subscription-main-publish-sync-skip
registerRegressionFunctionLeaf ui-full-subscription-main-publish-sync-enable runRegressionUiLegacyLeafWithCompat runMenuSmokeRegression subscription-main-publish-sync-enable
registerRegressionFunctionLeaf ui-full-subscription-main-maintenance runRegressionUiLegacyLeafWithCompat runMenuSmokeRegression subscription-main-maintenance
registerRegressionFunctionLeaf ui-full-subscription-controlled runRegressionUiLegacyLeafWithCompat runMenuSmokeRegression subscription-controlled
registerRegressionFunctionLeaf ui-full-core-maintenance runRegressionUiLegacyLeafWithCompat runMenuSmokeRegression core-maintenance
registerRegressionFunctionLeaf wireguard-menu-flow-bootstrap runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowBootstrapRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-add-update runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowRegression peer-add-update
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-apply-service runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowRegression peer-rollback-apply-service
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-apply-restore runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowRegression peer-rollback-apply-restore
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-source runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowRegression peer-rollback-source
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-credential-write runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowRegression peer-rollback-credential-write
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-credential-groups-restore runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowRegression peer-rollback-credential-groups-restore
registerRegressionFunctionLeaf wireguard-menu-flow-peer-source-control-toggle runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowRegression peer-source-control-toggle
registerRegressionFunctionLeaf wireguard-menu-flow-peer-source-control-clear-error runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowRegression peer-source-control-clear-error
registerRegressionFunctionLeaf wireguard-menu-flow-peer-source-control-status runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowRegression peer-source-control-status
registerRegressionFunctionLeaf wireguard-menu-flow-control-restore runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowRegression control-restore
registerRegressionFunctionLeaf wireguard-restore-runner runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardRestoreRunnerRegression
registerRegressionFunctionLeaf regression-ui-legacy-tmpdir-isolation runRegressionUiLegacyTmpDirIsolationRegression
registerRegressionFunctionLeaf regression-ui-long-tail-split-composition runRegressionUiLongTailSplitCompositionRegression
registerRegressionFunctionLeaf regression-ui-parallel-composition runRegressionUiLongTailSplitCompositionRegression

registerRegressionParallelSelectorList ui-full runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/ui-full-parallel-${BASHPID:-$$}" listRegressionUiFullChildSelectors
registerRegressionParallelSelectorList ui-full-subscription-main runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/ui-full-subscription-main-parallel-${BASHPID:-$$}" listRegressionUiFullSubscriptionMainChildSelectors
registerRegressionParallelSelectorList ui-full-subscription-main-publish runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/ui-full-subscription-main-publish-parallel-${BASHPID:-$$}" listRegressionUiFullSubscriptionMainPublishChildSelectors
registerRegressionParallelSelectorList ui-full-subscription-main-publish-user runUiLeafSelectorListRegression \
    "${TMP_DIR}/ui-full-subscription-main-publish-user-parallel-${BASHPID:-$$}" listRegressionUiFullSubscriptionMainPublishUserChildSelectors 3
registerRegressionParallelSelectorList ui-full-subscription-main-publish-sync runUiLeafSelectorListRegression \
    "${TMP_DIR}/ui-full-subscription-main-publish-sync-parallel-${BASHPID:-$$}" listRegressionUiFullSubscriptionMainPublishSyncChildSelectors 2
registerRegressionParallelSelectorList wireguard-menu-flow runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/wireguard-menu-flow-parallel-${BASHPID:-$$}" listRegressionWireGuardMenuFlowChildSelectors
registerRegressionParallelSelectorList wireguard-menu-flow-peer-transaction runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/wireguard-menu-flow-peer-transaction-parallel-${BASHPID:-$$}" listRegressionWireGuardMenuFlowPeerTransactionChildSelectors
registerRegressionParallelSelectorList wireguard-menu-flow-peer-rollback runFrameworkParallelRegressionSelectorList \
    "${TMP_DIR}/wireguard-menu-flow-peer-rollback-parallel-${BASHPID:-$$}" listRegressionWireGuardMenuFlowPeerRollbackChildSelectors
registerRegressionParallelSelectorList wireguard-menu-flow-peer-rollback-apply runUiLeafSelectorListRegression \
    "${TMP_DIR}/wireguard-menu-flow-peer-rollback-apply-parallel-${BASHPID:-$$}" listRegressionWireGuardMenuFlowPeerRollbackApplyChildSelectors 2
registerRegressionParallelSelectorList wireguard-menu-flow-peer-rollback-credential runUiLeafSelectorListRegression \
    "${TMP_DIR}/wireguard-menu-flow-peer-rollback-credential-parallel-${BASHPID:-$$}" listRegressionWireGuardMenuFlowPeerRollbackCredentialChildSelectors 2
registerRegressionParallelSelectorList wireguard-menu-flow-peer-source-control runUiLeafSelectorListRegression \
    "${TMP_DIR}/wireguard-menu-flow-peer-source-control-parallel-${BASHPID:-$$}" listRegressionWireGuardMenuFlowPeerSourceControlChildSelectors 3

registerRegressionAggregateRunner parallel ui runRegressionUiSuiteRoot \
    $(listRegressionUiChildSelectors)
