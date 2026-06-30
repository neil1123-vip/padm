#!/usr/bin/env bash

REGRESSION_UI_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_UI_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_UI_SUITE_DIR}/../subscription_groups_legacy.sh"

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
    unInstallSubscribe() { recordMenuAction unInstallSubscribe; }
    handleNginx() { recordMenuAction "handleNginx:$*"; }
    serviceQueueRestart() { recordMenuAction "serviceQueueRestart:$*"; }
    serviceQueueApply() { recordMenuAction serviceQueueApply; }
    subscriptionWireGuardControlEnabled() { return 0; }
    refreshSubscriptionWireGuardNginxControl() { recordMenuAction refreshSubscriptionWireGuardNginxControl; }
    installXrayReality
    assertMenuAction 'handleNginx:stop'
    assertMenuAction refreshSubscriptionWireGuardNginxControl
    assertMenuAction serviceQueueApply

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

runRegressionMenuSmokeFull() {
    runUiSelectorListRegression \
        "${TMP_DIR}/ui-full-parallel-${BASHPID:-$$}" \
        listRegressionUiFullChildSelectors
}

runUiSelectorListRegression() {
    local orchestrationRoot=$1
    local selectorListFn=$2

    runFrameworkParallelRegressionSelectorList "${orchestrationRoot}" "${selectorListFn}"
}

runUiLeafSelectorListRegression() {
    local orchestrationRoot=$1
    local selectorListFn=$2
    local defaultJobs=$3

    PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_UI_LEAF_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-${defaultJobs}}}" \
        runUiSelectorListRegression "${orchestrationRoot}" "${selectorListFn}"
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

runRegressionWireGuardMenuFlow() {
    runUiSelectorListRegression \
        "${TMP_DIR}/wireguard-menu-flow-parallel-${BASHPID:-$$}" \
        listRegressionWireGuardMenuFlowChildSelectors
}

runSubscriptionWireGuardMenuFlowPeerTransactionRegression() {
    runUiSelectorListRegression \
        "${TMP_DIR}/wireguard-menu-flow-peer-transaction-parallel-${BASHPID:-$$}" \
        listRegressionWireGuardMenuFlowPeerTransactionChildSelectors
}

runSubscriptionWireGuardMenuFlowPeerRollbackRegression() {
    runUiSelectorListRegression \
        "${TMP_DIR}/wireguard-menu-flow-peer-rollback-parallel-${BASHPID:-$$}" \
        listRegressionWireGuardMenuFlowPeerRollbackChildSelectors
}

runSubscriptionWireGuardMenuFlowPeerRollbackApplyRegression() {
    runUiLeafSelectorListRegression \
        "${TMP_DIR}/wireguard-menu-flow-peer-rollback-apply-parallel-${BASHPID:-$$}" \
        listRegressionWireGuardMenuFlowPeerRollbackApplyChildSelectors \
        2
}

runSubscriptionWireGuardMenuFlowPeerRollbackCredentialRegression() {
    runUiLeafSelectorListRegression \
        "${TMP_DIR}/wireguard-menu-flow-peer-rollback-credential-parallel-${BASHPID:-$$}" \
        listRegressionWireGuardMenuFlowPeerRollbackCredentialChildSelectors \
        2
}

runSubscriptionWireGuardMenuFlowPeerSourceControlRegression() {
    runUiLeafSelectorListRegression \
        "${TMP_DIR}/wireguard-menu-flow-peer-source-control-parallel-${BASHPID:-$$}" \
        listRegressionWireGuardMenuFlowPeerSourceControlChildSelectors \
        3
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

runRegressionUiFullSubscriptionMain() {
    runUiSelectorListRegression \
        "${TMP_DIR}/ui-full-subscription-main-parallel-${BASHPID:-$$}" \
        listRegressionUiFullSubscriptionMainChildSelectors
}

runRegressionUiFullSubscriptionMainPublish() {
    runUiSelectorListRegression \
        "${TMP_DIR}/ui-full-subscription-main-publish-parallel-${BASHPID:-$$}" \
        listRegressionUiFullSubscriptionMainPublishChildSelectors
}

runRegressionUiFullSubscriptionMainPublishUser() {
    runUiLeafSelectorListRegression \
        "${TMP_DIR}/ui-full-subscription-main-publish-user-parallel-${BASHPID:-$$}" \
        listRegressionUiFullSubscriptionMainPublishUserChildSelectors \
        3
}

runRegressionUiFullSubscriptionMainPublishSync() {
    runUiLeafSelectorListRegression \
        "${TMP_DIR}/ui-full-subscription-main-publish-sync-parallel-${BASHPID:-$$}" \
        listRegressionUiFullSubscriptionMainPublishSyncChildSelectors \
        2
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
        ui-full-subscription-main-publish-sync \
        wireguard-menu-flow-peer-rollback-apply \
        wireguard-menu-flow-peer-rollback-credential \
        wireguard-menu-flow-peer-rollback-source \
        ui-full-subscription-main-publish-user \
        ui-full-subscription-main-publish-service \
        wireguard-menu-flow-peer-add-update \
        wireguard-menu-flow-peer-source-control \
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

runRegressionUiSuiteRoot() {
    if [[ "${PADM_REGRESSION_UI_RESOURCE_PROFILE:-}" == "all" ]]; then
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/ui-parallel-${BASHPID:-$$}" \
            listRegressionUiAllProfileChildSelectors
        return
    fi

    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/ui-parallel-${BASHPID:-$$}" \
        listRegressionUiChildSelectors
}

runRegressionUiParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-ui-parallel-composition.log"

    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        if [[ "${selector}" == "ui-full-subscription-main-publish-sync-enable" ]]; then
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${TMP_DIR}/wireguard-menu-flow-peer-rollback-apply-service-started" ]] && break
                sleep 0.05
            done
        elif [[ "${selector}" == "wireguard-menu-flow-peer-rollback-apply-service" ]]; then
            : >"${TMP_DIR}/wireguard-menu-flow-peer-rollback-apply-service-started"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionUiSuiteRoot

    for selector in \
        ui-full-subscription-main-entry \
        ui-full-subscription-main-publish-service \
        ui-full-subscription-main-publish-user-empty \
        ui-full-subscription-main-publish-user-create \
        ui-full-subscription-main-publish-user-inspect \
        ui-full-subscription-main-publish-sync-skip \
        ui-full-subscription-main-publish-sync-enable \
        ui-full-subscription-main-maintenance \
        wireguard-menu-flow-bootstrap \
        wireguard-menu-flow-peer-add-update \
        wireguard-menu-flow-peer-rollback-apply-service \
        wireguard-menu-flow-peer-rollback-apply-restore \
        wireguard-menu-flow-peer-rollback-source \
        wireguard-menu-flow-peer-rollback-credential-write \
        wireguard-menu-flow-peer-rollback-credential-groups-restore \
        wireguard-menu-flow-peer-source-control-toggle \
        wireguard-menu-flow-peer-source-control-clear-error \
        wireguard-menu-flow-peer-source-control-status \
        wireguard-menu-flow-control-restore \
        ui-full-subscription-controlled \
        ui-full-core \
        ui-full-core-maintenance \
        ui-smoke \
        wireguard-restore-runner; do
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done
    awk '
        $0 == "ui-full-subscription-main-publish-sync-enable-start" { smokeStart = NR }
        $0 == "wireguard-menu-flow-peer-rollback-apply-service-start" { wireguardStart = NR }
        $0 == "ui-full-subscription-main-publish-sync-enable-finish" { smokeFinish = NR }
        END { exit !(smokeStart && wireguardStart && smokeFinish && wireguardStart < smokeFinish) }
    ' "${callLog}"
    ! grep -qx 'ui-full-subscription-main-publish-start' "${callLog}"
    ! grep -qx 'ui-full-subscription-main-publish-finish' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-finish' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-transaction-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-transaction-finish' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-rollback-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-rollback-finish' "${callLog}"
    ! grep -qx 'ui-full-subscription-main-start' "${callLog}"
    ! grep -qx 'ui-full-subscription-main-finish' "${callLog}"
    ! grep -qx 'ui-full-start' "${callLog}"
    ! grep -qx 'ui-full-finish' "${callLog}"
    ! grep -qx 'ui-full-subscription-main-publish-user-start' "${callLog}"
    ! grep -qx 'ui-full-subscription-main-publish-user-finish' "${callLog}"
    ! grep -qx 'ui-full-subscription-main-publish-sync-start' "${callLog}"
    ! grep -qx 'ui-full-subscription-main-publish-sync-finish' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-rollback-apply-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-rollback-apply-finish' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-rollback-credential-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-rollback-credential-finish' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-source-control-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-source-control-finish' "${callLog}"

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
)

runRegressionUiLongTailSplitCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-ui-long-tail-split-composition.log"

    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        if [[ "${selector}" == "ui-full-subscription-main-publish-sync-enable" ]]; then
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${TMP_DIR}/wireguard-menu-flow-peer-rollback-apply-service-started" ]] && break
                sleep 0.05
            done
        elif [[ "${selector}" == "wireguard-menu-flow-peer-rollback-apply-service" ]]; then
            : >"${TMP_DIR}/wireguard-menu-flow-peer-rollback-apply-service-started"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionUiSuiteRoot

    for selector in \
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
        wireguard-menu-flow-peer-add-update \
        wireguard-menu-flow-peer-source-control-clear-error \
        ui-full-subscription-main-publish-service \
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
        wireguard-restore-runner; do
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done
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
    for selector in \
        ui-full-subscription-main-publish-sync \
        wireguard-menu-flow-peer-rollback-apply \
        wireguard-menu-flow-peer-rollback-credential \
        wireguard-menu-flow-peer-rollback-source \
        ui-full-subscription-main-publish-user \
        ui-full-subscription-main-publish-service \
        wireguard-menu-flow-peer-add-update \
        wireguard-menu-flow-peer-source-control \
        ui-full-subscription-main-maintenance \
        wireguard-menu-flow-control-restore \
        wireguard-menu-flow-bootstrap \
        ui-full-subscription-main-entry \
        ui-full-subscription-controlled \
        ui-full-core \
        ui-full-core-maintenance \
        ui-smoke \
        wireguard-restore-runner; do
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done
    ! grep -qx 'ui-full-subscription-main-publish-sync-enable-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-rollback-apply-service-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-rollback-credential-write-start' "${callLog}"
    ! grep -qx 'wireguard-menu-flow-peer-source-control-toggle-start' "${callLog}"

    : >"${callLog}"
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionUiFullSubscriptionMainPublishUser
    for selector in \
        ui-full-subscription-main-publish-user-empty \
        ui-full-subscription-main-publish-user-create \
        ui-full-subscription-main-publish-user-inspect; do
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done
    ! grep -q '^ui-full:subscription-main-publish-user-start$' "${callLog}"

    : >"${callLog}"
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionUiFullSubscriptionMainPublishSync
    for selector in \
        ui-full-subscription-main-publish-sync-skip \
        ui-full-subscription-main-publish-sync-enable; do
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done

    : >"${callLog}"
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runSubscriptionWireGuardMenuFlowPeerRollbackApplyRegression
    for selector in \
        wireguard-menu-flow-peer-rollback-apply-service \
        wireguard-menu-flow-peer-rollback-apply-restore; do
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done

    : >"${callLog}"
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runSubscriptionWireGuardMenuFlowPeerRollbackCredentialRegression
    for selector in \
        wireguard-menu-flow-peer-rollback-credential-write \
        wireguard-menu-flow-peer-rollback-credential-groups-restore; do
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done

    : >"${callLog}"
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runSubscriptionWireGuardMenuFlowPeerSourceControlRegression
    for selector in \
        wireguard-menu-flow-peer-source-control-toggle \
        wireguard-menu-flow-peer-source-control-clear-error \
        wireguard-menu-flow-peer-source-control-status; do
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done

    : >"${callLog}"
    PADM_REGRESSION_UI_LEAF_PARALLEL_JOBS=1 PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionUiFullSubscriptionMainPublishUser
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

runMenuSmokeFullCoreCompatRegression() { runRegressionUiLegacyLeafWithCompat runMenuSmokeFullCoreRegression; }
runMenuSmokeFullSubscriptionMainEntryCompatRegression() { runRegressionUiLegacyLeafWithCompat runMenuSmokeFullSubscriptionMainEntryRegression; }
runMenuSmokeFullSubscriptionMainPublishServiceCompatRegression() { runRegressionUiLegacyLeafWithCompat runMenuSmokeFullSubscriptionMainPublishServiceRegression; }
runMenuSmokeFullSubscriptionMainPublishUserEmptyCompatRegression() { runRegressionUiLegacyLeafWithCompat runMenuSmokeFullSubscriptionMainPublishUserEmptyRegression; }
runMenuSmokeFullSubscriptionMainPublishUserCreateCompatRegression() { runRegressionUiLegacyLeafWithCompat runMenuSmokeFullSubscriptionMainPublishUserCreateRegression; }
runMenuSmokeFullSubscriptionMainPublishUserInspectCompatRegression() { runRegressionUiLegacyLeafWithCompat runMenuSmokeFullSubscriptionMainPublishUserInspectRegression; }
runMenuSmokeFullSubscriptionMainPublishSyncSkipCompatRegression() { runRegressionUiLegacyLeafWithCompat runMenuSmokeFullSubscriptionMainPublishSyncSkipRegression; }
runMenuSmokeFullSubscriptionMainPublishSyncEnableCompatRegression() { runRegressionUiLegacyLeafWithCompat runMenuSmokeFullSubscriptionMainPublishSyncEnableRegression; }
runMenuSmokeFullSubscriptionMainMaintenanceCompatRegression() { runRegressionUiLegacyLeafWithCompat runMenuSmokeFullSubscriptionMainMaintenanceRegression; }
runMenuSmokeFullSubscriptionControlledCompatRegression() { runRegressionUiLegacyLeafWithCompat runMenuSmokeFullSubscriptionControlledRegression; }
runMenuSmokeFullCoreMaintenanceCompatRegression() { runRegressionUiLegacyLeafWithCompat runMenuSmokeFullCoreMaintenanceRegression; }
runSubscriptionWireGuardMenuFlowBootstrapCompatRegression() { runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowBootstrapRegression; }
runSubscriptionWireGuardMenuFlowPeerAddUpdateCompatRegression() { runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowPeerAddUpdateRegression; }
runSubscriptionWireGuardMenuFlowPeerRollbackApplyServiceCompatRegression() { runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowPeerRollbackApplyServiceRegression; }
runSubscriptionWireGuardMenuFlowPeerRollbackApplyRestoreCompatRegression() { runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowPeerRollbackApplyRestoreRegression; }
runSubscriptionWireGuardMenuFlowPeerRollbackSourceCompatRegression() { runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowPeerRollbackSourceRegression; }
runSubscriptionWireGuardMenuFlowPeerRollbackCredentialWriteCompatRegression() { runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowPeerRollbackCredentialWriteRegression; }
runSubscriptionWireGuardMenuFlowPeerRollbackCredentialGroupsRestoreCompatRegression() { runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowPeerRollbackCredentialGroupsRestoreRegression; }
runSubscriptionWireGuardMenuFlowPeerSourceControlToggleCompatRegression() { runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowPeerSourceControlToggleRegression; }
runSubscriptionWireGuardMenuFlowPeerSourceControlClearErrorCompatRegression() { runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowPeerSourceControlClearErrorRegression; }
runSubscriptionWireGuardMenuFlowPeerSourceControlStatusCompatRegression() { runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowPeerSourceControlStatusRegression; }
runSubscriptionWireGuardMenuFlowControlRestoreCompatRegression() { runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardMenuFlowControlRestoreRegression; }
runSubscriptionWireGuardRestoreRunnerCompatRegression() { runRegressionUiLegacyLeafWithCompat runSubscriptionWireGuardRestoreRunnerRegression; }

registerRegressionFunctionLeaf ui-smoke runRegressionUiSmokeSuiteRoot
registerRegressionFunctionLeaf ui-full-core runMenuSmokeFullCoreCompatRegression
registerRegressionFunctionLeaf ui-full-subscription-main-entry runMenuSmokeFullSubscriptionMainEntryCompatRegression
registerRegressionFunctionLeaf ui-full-subscription-main-publish-service runMenuSmokeFullSubscriptionMainPublishServiceCompatRegression
registerRegressionFunctionLeaf ui-full-subscription-main-publish-user-empty runMenuSmokeFullSubscriptionMainPublishUserEmptyCompatRegression
registerRegressionFunctionLeaf ui-full-subscription-main-publish-user-create runMenuSmokeFullSubscriptionMainPublishUserCreateCompatRegression
registerRegressionFunctionLeaf ui-full-subscription-main-publish-user-inspect runMenuSmokeFullSubscriptionMainPublishUserInspectCompatRegression
registerRegressionFunctionLeaf ui-full-subscription-main-publish-sync-skip runMenuSmokeFullSubscriptionMainPublishSyncSkipCompatRegression
registerRegressionFunctionLeaf ui-full-subscription-main-publish-sync-enable runMenuSmokeFullSubscriptionMainPublishSyncEnableCompatRegression
registerRegressionFunctionLeaf ui-full-subscription-main-maintenance runMenuSmokeFullSubscriptionMainMaintenanceCompatRegression
registerRegressionFunctionLeaf ui-full-subscription-controlled runMenuSmokeFullSubscriptionControlledCompatRegression
registerRegressionFunctionLeaf ui-full-core-maintenance runMenuSmokeFullCoreMaintenanceCompatRegression
registerRegressionFunctionLeaf wireguard-menu-flow-bootstrap runSubscriptionWireGuardMenuFlowBootstrapCompatRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-add-update runSubscriptionWireGuardMenuFlowPeerAddUpdateCompatRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-apply-service runSubscriptionWireGuardMenuFlowPeerRollbackApplyServiceCompatRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-apply-restore runSubscriptionWireGuardMenuFlowPeerRollbackApplyRestoreCompatRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-source runSubscriptionWireGuardMenuFlowPeerRollbackSourceCompatRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-credential-write runSubscriptionWireGuardMenuFlowPeerRollbackCredentialWriteCompatRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-credential-groups-restore runSubscriptionWireGuardMenuFlowPeerRollbackCredentialGroupsRestoreCompatRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-source-control-toggle runSubscriptionWireGuardMenuFlowPeerSourceControlToggleCompatRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-source-control-clear-error runSubscriptionWireGuardMenuFlowPeerSourceControlClearErrorCompatRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-source-control-status runSubscriptionWireGuardMenuFlowPeerSourceControlStatusCompatRegression
registerRegressionFunctionLeaf wireguard-menu-flow-control-restore runSubscriptionWireGuardMenuFlowControlRestoreCompatRegression
registerRegressionFunctionLeaf wireguard-restore-runner runSubscriptionWireGuardRestoreRunnerCompatRegression
registerRegressionFunctionLeaf regression-ui-legacy-tmpdir-isolation runRegressionUiLegacyTmpDirIsolationRegression
registerRegressionFunctionLeaf regression-ui-parallel-composition runRegressionUiParallelCompositionRegression
registerRegressionFunctionLeaf regression-ui-long-tail-split-composition runRegressionUiLongTailSplitCompositionRegression

registerRegressionAggregateRunnerParallel ui-full runRegressionMenuSmokeFull \
    $(listRegressionUiFullChildSelectors)

registerRegressionAggregateRunnerParallel ui-full-subscription-main runRegressionUiFullSubscriptionMain \
    $(listRegressionUiFullSubscriptionMainChildSelectors)

registerRegressionAggregateRunnerParallel ui-full-subscription-main-publish runRegressionUiFullSubscriptionMainPublish \
    $(listRegressionUiFullSubscriptionMainPublishChildSelectors)

registerRegressionAggregateRunnerParallel ui-full-subscription-main-publish-user runRegressionUiFullSubscriptionMainPublishUser \
    $(listRegressionUiFullSubscriptionMainPublishUserChildSelectors)

registerRegressionAggregateRunnerParallel ui-full-subscription-main-publish-sync runRegressionUiFullSubscriptionMainPublishSync \
    $(listRegressionUiFullSubscriptionMainPublishSyncChildSelectors)

registerRegressionAggregateRunnerParallel wireguard-menu-flow runRegressionWireGuardMenuFlow \
    $(listRegressionWireGuardMenuFlowChildSelectors)

registerRegressionAggregateRunnerParallel wireguard-menu-flow-peer-transaction runSubscriptionWireGuardMenuFlowPeerTransactionRegression \
    $(listRegressionWireGuardMenuFlowPeerTransactionChildSelectors)

registerRegressionAggregateRunnerParallel wireguard-menu-flow-peer-rollback runSubscriptionWireGuardMenuFlowPeerRollbackRegression \
    $(listRegressionWireGuardMenuFlowPeerRollbackChildSelectors)

registerRegressionAggregateRunnerParallel wireguard-menu-flow-peer-rollback-apply runSubscriptionWireGuardMenuFlowPeerRollbackApplyRegression \
    $(listRegressionWireGuardMenuFlowPeerRollbackApplyChildSelectors)

registerRegressionAggregateRunnerParallel wireguard-menu-flow-peer-rollback-credential runSubscriptionWireGuardMenuFlowPeerRollbackCredentialRegression \
    $(listRegressionWireGuardMenuFlowPeerRollbackCredentialChildSelectors)

registerRegressionAggregateRunnerParallel wireguard-menu-flow-peer-source-control runSubscriptionWireGuardMenuFlowPeerSourceControlRegression \
    $(listRegressionWireGuardMenuFlowPeerSourceControlChildSelectors)

registerRegressionAggregateRunnerParallel ui runRegressionUiSuiteRoot \
    $(listRegressionUiChildSelectors)
