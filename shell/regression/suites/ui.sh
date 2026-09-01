#!/usr/bin/env bash

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
    eval "$(declare -f selectCoreInstall | sed '1s/^selectCoreInstall /originalSelectCoreInstall /')"
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

    (
        local menuRenderLog="${TMP_DIR}/core-select-menu-render.log"
        echoContent() { printf '%s\n' "$*" >>"${menuRenderLog}"; }
        xrayCoreInstall() { recordMenuAction xrayCoreInstall; }
        singBoxInstall() { recordMenuAction singBoxInstall; }
        selectInstallType=1
        : >"${menuRenderLog}"
        resetMenuActions
        originalSelectCoreInstall <<< $'bad\n1'
        assertMenuAction 'errorCard:选择错误'
        assertMenuAction xrayCoreInstall
        [[ "$(wc -l <"${menuRenderLog}")" == "2" ]]
    )

    (
        local menuRenderLog="${TMP_DIR}/install-menu-render.log"
        echoContent() { printf '%s\n' "$*" >>"${menuRenderLog}"; }
        customXrayInstall() { recordMenuAction customXrayInstall; }
        customSingBoxInstall() { recordMenuAction customSingBoxInstall; }
        selectCoreInstall() { recordMenuAction selectCoreInstall; }
        : >"${menuRenderLog}"
        resetMenuActions
        installMenu <<< $'bad\n7'
        assertMenuAction 'errorCard:选择错误'
        ! assertMenuAction customXrayInstall
        ! assertMenuAction customSingBoxInstall
        ! assertMenuAction selectCoreInstall
        [[ "$(wc -l <"${menuRenderLog}")" == "2" ]]
    )

    (
        local menuRenderLog="${TMP_DIR}/top-level-menu-render.log"
        echoContent() { printf '%s\n' "$*" >>"${menuRenderLog}"; }
        updatePadm() { recordMenuAction updatePadm; }
        showPadmScriptInstallStatus() { recordMenuAction showPadmScriptInstallStatus; }
        manageFail2ban() { recordMenuAction manageFail2ban; }
        bbrInstall() { recordMenuAction bbrInstall; }
        unInstall() { recordMenuAction unInstall; }
        manageVlessEncryptionExperiment() { recordMenuAction manageVlessEncryptionExperiment; }
        : >"${menuRenderLog}"
        resetMenuActions
        systemScriptMenu <<< $'bad\n5'
        assertMenuAction 'errorCard:选择错误'
        [[ "$(wc -l <"${menuRenderLog}")" == "2" ]]
        : >"${menuRenderLog}"
        resetMenuActions
        advancedDangerMenu <<< $'bad\n3'
        assertMenuAction 'errorCard:选择错误'
        ! assertMenuAction unInstall
        ! assertMenuAction manageVlessEncryptionExperiment
        [[ "$(wc -l <"${menuRenderLog}")" == "2" ]]
    )

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

registerRegressionFunctionLeaf ui-smoke runRegressionUiSmokeSuiteRoot
registerRegressionFunctionLeaf ui-full-core runMenuSmokeRegression core
registerRegressionFunctionLeaf ui-full-subscription-main-entry runMenuSmokeRegression subscription-main-entry
registerRegressionFunctionLeaf ui-full-subscription-main-publish-service runMenuSmokeRegression subscription-main-publish-service
registerRegressionFunctionLeaf ui-full-subscription-main-publish-user-empty runMenuSmokeRegression subscription-main-publish-user-empty
registerRegressionFunctionLeaf ui-full-subscription-main-publish-user-create runMenuSmokeRegression subscription-main-publish-user-create
registerRegressionFunctionLeaf ui-full-subscription-main-publish-user-inspect runMenuSmokeRegression subscription-main-publish-user-inspect
registerRegressionFunctionLeaf ui-full-subscription-main-publish-sync-skip runMenuSmokeRegression subscription-main-publish-sync-skip
registerRegressionFunctionLeaf ui-full-subscription-main-publish-sync-enable runMenuSmokeRegression subscription-main-publish-sync-enable
registerRegressionFunctionLeaf ui-full-subscription-main-maintenance runMenuSmokeRegression subscription-main-maintenance
registerRegressionFunctionLeaf ui-full-subscription-controlled runMenuSmokeRegression subscription-controlled
registerRegressionFunctionLeaf ui-full-core-maintenance runMenuSmokeRegression core-maintenance
registerRegressionFunctionLeaf wireguard-menu-flow-bootstrap runSubscriptionWireGuardMenuFlowBootstrapRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-add-update runSubscriptionWireGuardMenuFlowRegression peer-add-update
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-apply-service runSubscriptionWireGuardMenuFlowRegression peer-rollback-apply-service
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-apply-restore runSubscriptionWireGuardMenuFlowRegression peer-rollback-apply-restore
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-source runSubscriptionWireGuardMenuFlowRegression peer-rollback-source
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-credential-write runSubscriptionWireGuardMenuFlowRegression peer-rollback-credential-write
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-credential-groups-restore runSubscriptionWireGuardMenuFlowRegression peer-rollback-credential-groups-restore
registerRegressionFunctionLeaf wireguard-menu-flow-peer-source-control-toggle runSubscriptionWireGuardMenuFlowRegression peer-source-control-toggle
registerRegressionFunctionLeaf wireguard-menu-flow-peer-source-control-status runSubscriptionWireGuardMenuFlowRegression peer-source-control-status
registerRegressionFunctionLeaf wireguard-menu-flow-control-restore runSubscriptionWireGuardMenuFlowRegression control-restore
registerRegressionFunctionLeaf wireguard-restore-runner runSubscriptionWireGuardRestoreRunnerRegression

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
