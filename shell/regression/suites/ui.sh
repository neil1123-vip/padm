#!/usr/bin/env bash

REGRESSION_UI_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_UI_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_UI_SUITE_DIR}/../subscription_groups_legacy.sh"

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
    [[ "$(protocolMenuDescription 10)" == "TLS 指纹抗性优先；sing-box / tcp / tls" ]]
    [[ "$(protocolMenuDescription 13)" == "sing-box AnyTLS 按需；sing-box / tcp / tls" ]]
    coreInstallType="${oldCoreInstallType}"
}

runRegressionMenuSmokeFull() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    selectors=(
        ui-full-subscription-main-entry
        ui-full-subscription-main-publish-service
        ui-full-subscription-main-publish-user
        ui-full-subscription-main-publish-sync
        ui-full-subscription-main-maintenance
        ui-full-subscription-controlled
        ui-full-core
        ui-full-core-maintenance
    )
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/ui-full-parallel-${BASHPID:-$$}" \
        "${selectorPairs[@]}"
}

runRegressionWireGuardMenuFlow() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    selectors=(
        wireguard-menu-flow-bootstrap
        wireguard-menu-flow-peer-add-update
        wireguard-menu-flow-peer-rollback-apply
        wireguard-menu-flow-peer-rollback-source
        wireguard-menu-flow-peer-rollback-credential
        wireguard-menu-flow-peer-source-control
        wireguard-menu-flow-control-restore
    )
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/wireguard-menu-flow-parallel-${BASHPID:-$$}" \
        "${selectorPairs[@]}"
}

runSubscriptionWireGuardMenuFlowPeerTransactionRegression() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    selectors=(
        wireguard-menu-flow-peer-add-update
        wireguard-menu-flow-peer-rollback
        wireguard-menu-flow-peer-source-control
    )
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/wireguard-menu-flow-peer-transaction-parallel-${BASHPID:-$$}" \
        "${selectorPairs[@]}"
}

runSubscriptionWireGuardMenuFlowPeerRollbackRegression() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    selectors=(
        wireguard-menu-flow-peer-rollback-apply
        wireguard-menu-flow-peer-rollback-source
        wireguard-menu-flow-peer-rollback-credential
    )
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/wireguard-menu-flow-peer-rollback-parallel-${BASHPID:-$$}" \
        "${selectorPairs[@]}"
}

runSubscriptionWireGuardMenuFlowPeerRollbackApplyRegression() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    selectors=(
        wireguard-menu-flow-peer-rollback-apply-service
        wireguard-menu-flow-peer-rollback-apply-restore
    )
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_UI_LEAF_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-2}}" \
        PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/wireguard-menu-flow-peer-rollback-apply-parallel-${BASHPID:-$$}" \
        "${selectorPairs[@]}"
}

runSubscriptionWireGuardMenuFlowPeerRollbackCredentialRegression() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    selectors=(
        wireguard-menu-flow-peer-rollback-credential-write
        wireguard-menu-flow-peer-rollback-credential-groups-restore
    )
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_UI_LEAF_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-2}}" \
        PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/wireguard-menu-flow-peer-rollback-credential-parallel-${BASHPID:-$$}" \
        "${selectorPairs[@]}"
}

runSubscriptionWireGuardMenuFlowPeerSourceControlRegression() {
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    selectors=(
        wireguard-menu-flow-peer-source-control-toggle
        wireguard-menu-flow-peer-source-control-clear-error
        wireguard-menu-flow-peer-source-control-status
    )
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_UI_LEAF_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-3}}" \
        PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/wireguard-menu-flow-peer-source-control-parallel-${BASHPID:-$$}" \
        "${selectorPairs[@]}"
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
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    if [[ "${PADM_REGRESSION_UI_RESOURCE_PROFILE:-}" == "all" ]]; then
        mapfile -t selectors < <(listRegressionUiAllProfileChildSelectors)
        selectorPairs=()
        for selector in "${selectors[@]}"; do
            selectorPairs+=("${selector}" "${selector}")
        done
        PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
            runFrameworkParallelRegressionSelectors "${TMP_DIR}/ui-parallel-${BASHPID:-$$}" \
            "${selectorPairs[@]}"
        return
    fi

    mapfile -t selectors < <(listRegressionUiChildSelectors)
    selectorPairs=()
    for selector in "${selectors[@]}"; do
        selectorPairs+=("${selector}" "${selector}")
    done
    PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/ui-parallel-${BASHPID:-$$}" \
        "${selectorPairs[@]}"
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
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runMenuSmokeFullSubscriptionMainPublishUserRegression
    for selector in \
        ui-full-subscription-main-publish-user-empty \
        ui-full-subscription-main-publish-user-create \
        ui-full-subscription-main-publish-user-inspect; do
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done
    ! grep -q '^ui-full:subscription-main-publish-user-start$' "${callLog}"

    : >"${callLog}"
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runMenuSmokeFullSubscriptionMainPublishSyncRegression
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
    PADM_REGRESSION_UI_LEAF_PARALLEL_JOBS=1 PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runMenuSmokeFullSubscriptionMainPublishUserRegression
    awk '
        $0 == "ui-full-subscription-main-publish-user-empty-finish" { firstFinish = NR }
        $0 == "ui-full-subscription-main-publish-user-create-start" { secondStart = NR }
        $0 == "ui-full-subscription-main-publish-user-create-finish" { secondFinish = NR }
        $0 == "ui-full-subscription-main-publish-user-inspect-start" { thirdStart = NR }
        END { exit !(firstFinish && secondStart && secondFinish && thirdStart && firstFinish < secondStart && secondFinish < thirdStart) }
    ' "${callLog}"
)

registerRegressionFunctionLeaf ui-smoke runRegressionUiSmokeSuiteRoot
registerRegressionFunctionLeaf ui-full runRegressionMenuSmokeFull
registerRegressionFunctionLeaf ui-full-core runMenuSmokeFullCoreRegression
registerRegressionFunctionLeaf ui-full-subscription-main runMenuSmokeFullSubscriptionMainRegression
registerRegressionFunctionLeaf ui-full-subscription-main-entry runMenuSmokeFullSubscriptionMainEntryRegression
registerRegressionFunctionLeaf ui-full-subscription-main-publish runMenuSmokeFullSubscriptionMainPublishRegression
registerRegressionFunctionLeaf ui-full-subscription-main-publish-service runMenuSmokeFullSubscriptionMainPublishServiceRegression
registerRegressionFunctionLeaf ui-full-subscription-main-publish-user runMenuSmokeFullSubscriptionMainPublishUserRegression
registerRegressionFunctionLeaf ui-full-subscription-main-publish-user-empty runMenuSmokeFullSubscriptionMainPublishUserEmptyRegression
registerRegressionFunctionLeaf ui-full-subscription-main-publish-user-create runMenuSmokeFullSubscriptionMainPublishUserCreateRegression
registerRegressionFunctionLeaf ui-full-subscription-main-publish-user-inspect runMenuSmokeFullSubscriptionMainPublishUserInspectRegression
registerRegressionFunctionLeaf ui-full-subscription-main-publish-sync runMenuSmokeFullSubscriptionMainPublishSyncRegression
registerRegressionFunctionLeaf ui-full-subscription-main-publish-sync-skip runMenuSmokeFullSubscriptionMainPublishSyncSkipRegression
registerRegressionFunctionLeaf ui-full-subscription-main-publish-sync-enable runMenuSmokeFullSubscriptionMainPublishSyncEnableRegression
registerRegressionFunctionLeaf ui-full-subscription-main-maintenance runMenuSmokeFullSubscriptionMainMaintenanceRegression
registerRegressionFunctionLeaf ui-full-subscription-controlled runMenuSmokeFullSubscriptionControlledRegression
registerRegressionFunctionLeaf ui-full-core-maintenance runMenuSmokeFullCoreMaintenanceRegression
registerRegressionFunctionLeaf wireguard-menu-flow runRegressionWireGuardMenuFlow
registerRegressionFunctionLeaf wireguard-menu-flow-bootstrap runSubscriptionWireGuardMenuFlowBootstrapRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-transaction runSubscriptionWireGuardMenuFlowPeerTransactionRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-add-update runSubscriptionWireGuardMenuFlowPeerAddUpdateRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback runSubscriptionWireGuardMenuFlowPeerRollbackRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-apply runSubscriptionWireGuardMenuFlowPeerRollbackApplyRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-apply-service runSubscriptionWireGuardMenuFlowPeerRollbackApplyServiceRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-apply-restore runSubscriptionWireGuardMenuFlowPeerRollbackApplyRestoreRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-source runSubscriptionWireGuardMenuFlowPeerRollbackSourceRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-credential runSubscriptionWireGuardMenuFlowPeerRollbackCredentialRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-credential-write runSubscriptionWireGuardMenuFlowPeerRollbackCredentialWriteRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-credential-groups-restore runSubscriptionWireGuardMenuFlowPeerRollbackCredentialGroupsRestoreRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-source-control runSubscriptionWireGuardMenuFlowPeerSourceControlRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-source-control-toggle runSubscriptionWireGuardMenuFlowPeerSourceControlToggleRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-source-control-clear-error runSubscriptionWireGuardMenuFlowPeerSourceControlClearErrorRegression
registerRegressionFunctionLeaf wireguard-menu-flow-peer-source-control-status runSubscriptionWireGuardMenuFlowPeerSourceControlStatusRegression
registerRegressionFunctionLeaf wireguard-menu-flow-control-restore runSubscriptionWireGuardMenuFlowControlRestoreRegression
registerRegressionFunctionLeaf wireguard-restore-runner runSubscriptionWireGuardRestoreRunnerRegression
registerRegressionFunctionLeaf regression-ui-parallel-composition runRegressionUiParallelCompositionRegression
registerRegressionFunctionLeaf regression-ui-long-tail-split-composition runRegressionUiLongTailSplitCompositionRegression

registerRegressionAggregateRunnerParallel ui runRegressionUiSuiteRoot \
    $(listRegressionUiChildSelectors)
