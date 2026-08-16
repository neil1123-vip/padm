#!/usr/bin/env bash

runSubscriptionWireGuardMenuFlowRegression() (
    local wireGuardMenuPart="${1:-all}"
    local parentTmpDir="${TMP_DIR}"
    local TMP_DIR="${parentTmpDir}/wireguard-menu-flow-${BASHPID:-$$}"
    local PADM_SUBSCRIPTION_GROUPS_DIR="${TMP_DIR}/subscribe_groups"
    local oldWireGuardDir="${PADM_WIREGUARD_CONTROL_DIR:-}"
    local oldCurrentHost="${currentHost:-}"
    local oldNginxConfigPath="${nginxConfigPath:-}"
    local oldPath="${PATH}"
    local updatedCredential failingReceiptJson completedAlias
    local mainPublicKey controlledPublicKey updatedPublicKey failingPublicKey
    local controlledToken='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    local failingToken='BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
    local bootstrapInvite bootstrapInviteJson
    local nginxFakeBin nginxTarget
    local mainStateSnapshot
    local wireGuardApplyShouldFail= installControlShouldFail= refreshControlShouldFail= serviceQueueShouldFail=
    local addSourceShouldFail= setCredentialShouldFail= restoreStateWriteShouldFail= restoreGroupsWriteShouldFail=
    local disableStateWriteShouldFail=
    local stopShouldFail=
    local stopAllowMissingBackend=
    local actions=

    # Restore the real subscription functions because earlier UI smoke tests
    # define menu stubs with global Bash function scope.
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/core/state.sh"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/subscription/groups.sh"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/subscription/wireguard_control.sh"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/subscription/menu.sh"

    mainPublicKey=$(printf '0123456789abcdefghijklmnopqrstuv' | base64 -w 0)
    controlledPublicKey=$(printf 'abcdefghijklmnopqrstuvwxyz123456' | base64 -w 0)
    updatedPublicKey=$(printf 'ABCDEFGHIJKLMNOPQRSTUVWXYZ123456' | base64 -w 0)
    failingPublicKey=$(printf '01234567890123456789012345678901' | base64 -w 0)
    updatedCredential=$(subscriptionWireGuardCredentialEncode controlled "$(jq -cn --arg publicKey "${updatedPublicKey}" '{address:"10.77.0.3/24",public_key:$publicKey,control_port:48779,token:"token-b"}')")

    recordMenuAction() {
        actions+="$1"$'\n'
    }
    assertMenuAction() {
        grep -qxF "$1" <<<"${actions}"
    }
    resetMenuActions() {
        actions=
    }
    autoRead() {
        local targetVar=$3
        local readValue=
        IFS= read -r readValue || readValue=
        printf -v "${targetVar}" '%s' "${readValue}"
    }
    echoContent() { return 0; }
    menuSection() { return 0; }
    menuLine() { return 0; }
    menuItem() { return 0; }
    menuReturnItem() { return 0; }
    menuDangerItem() { return 0; }
    menuClose() { return 0; }
    statusCard() { recordMenuAction "statusCard:$1"; }
    warnCard() { recordMenuAction "warnCard:$1"; }
    errorCard() { recordMenuAction "errorCard:$1"; }
    successCard() { recordMenuAction "successCard:$1"; }
    runSubscriptionGroupSync() { recordMenuAction "runSubscriptionGroupSync:$*"; }

    PADM_WIREGUARD_CONTROL_DIR="${TMP_DIR}/menu-smoke-wireguard"
    currentHost="main.example.com"
    nginxConfigPath="${TMP_DIR}/menu-smoke-nginx/"
    subscriptionWireGuardConfigFile() { echo "${TMP_DIR}/menu-smoke-wireguard/wg-padm.conf"; }
    rm -rf "${PADM_WIREGUARD_CONTROL_DIR}" "${PADM_SUBSCRIPTION_GROUPS_DIR}"
    mkdir -p "${nginxConfigPath}"
    ensureSubscriptionGroupsState

    initSubscriptionWireGuardMain() {
        recordMenuAction initSubscriptionWireGuardMain
        local endpointHost=
        autoRead wg_main_endpoint_host "请输入主控公网地址或域名[用于被控连接 WireGuard]:" endpointHost
        subscriptionWireGuardWriteState --arg endpointHost "${endpointHost}" --arg publicKey "${mainPublicKey}" '.enabled = true | .role = "main" | .address = "10.77.0.1/24" | .endpoint_host = $endpointHost | .public_key = $publicKey | .listen_port = 51820 | .control_port = 39778'
        applySubscriptionWireGuardService
    }
    eval "$(declare -f disableSubscriptionWireGuardControl | sed '1s/^disableSubscriptionWireGuardControl/originalDisableSubscriptionWireGuardControl/')"
    disableSubscriptionWireGuardControl() { recordMenuAction disableSubscriptionWireGuardControl; subscriptionWireGuardWriteState '.enabled = false'; }
    installSubscriptionWireGuardTools() { return 0; }
    subscriptionWireGuardEnsureKeys() {
        mkdir -p "$(subscriptionWireGuardDir)"
        printf 'private-key\n' >"$(subscriptionWireGuardPrivateKeyFile)"
        printf 'public-key\n' >"$(subscriptionWireGuardPublicKeyFile)"
    }
    subscriptionWireGuardPublicKey() { printf '%s\n' "${validPublicKey:-MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=}"; }
    writeSubscriptionWireGuardConfig() {
        mkdir -p "$(dirname "$(subscriptionWireGuardConfigFile)")"
        printf 'Address = %s\n' "$(subscriptionWireGuardReadState | jq -r '.address')" >"$(subscriptionWireGuardConfigFile)"
    }
    applySubscriptionWireGuardService() {
        recordMenuAction applySubscriptionWireGuardService
        [[ "${wireGuardApplyShouldFail}" == "true" ]] && return 1
        writeSubscriptionWireGuardConfig
    }
    subscriptionWireGuardWaitForAddress() { return 0; }
    eval "$(declare -f subscriptionWireGuardWriteState | sed '1s/^subscriptionWireGuardWriteState/originalSubscriptionWireGuardWriteState/')"
    subscriptionWireGuardWriteState() {
        if [[ "${restoreStateWriteShouldFail}" == "true" && "${*: -1}" == '$previousState' ]]; then
            return 1
        fi
        if [[ "${disableStateWriteShouldFail}" == "true" && "${*: -1}" == ".enabled = false | .firewall_owned = false" ]]; then
            return 1
        fi
        originalSubscriptionWireGuardWriteState "$@"
    }
    eval "$(declare -f subscriptionGroupsStateWrite | sed '1s/^subscriptionGroupsStateWrite/originalSubscriptionGroupsStateWrite/')"
    subscriptionGroupsStateWrite() {
        if [[ "${restoreGroupsWriteShouldFail}" == "true" && "${*: -1}" == '$previousGroupsState' ]]; then
            return 1
        fi
        originalSubscriptionGroupsStateWrite "$@"
    }
    installSubscriptionControlService() {
        recordMenuAction installSubscriptionControlService
        [[ "${installControlShouldFail}" == "true" ]] && return 1
        return 0
    }
    refreshSubscriptionWireGuardNginxControl() {
        recordMenuAction refreshSubscriptionWireGuardNginxControl
        [[ "${refreshControlShouldFail}" == "true" ]] && return 1
        if [[ "${refreshWritesNewConfig}" == "true" ]]; then
            printf 'new-nginx-control\n' >"$(subscriptionWireGuardNginxConfigFile)"
        fi
        return 0
    }
    serviceQueueRestart() { recordMenuAction "serviceQueueRestart:$*"; }
    serviceQueueApply() {
        recordMenuAction serviceQueueApply
        [[ "${serviceQueueShouldFail}" == "true" ]] && return 1
        return 0
    }
    stopSubscriptionWireGuardControlService() {
        recordMenuAction "stopSubscriptionWireGuardControlService:${1:-}"
        if [[ "${stopShouldFail}" == "true" ]]; then
            [[ "${1:-}" == "true" && "${stopAllowMissingBackend}" == "true" ]] && return 0
            return 1
        fi
        return 0
    }
    eval "$(declare -f addSubscriptionSourceState | sed '1s/^addSubscriptionSourceState/originalAddSubscriptionSourceState/')"
    eval "$(declare -f setSubscriptionSourceCredential | sed '1s/^setSubscriptionSourceCredential/originalSetSubscriptionSourceCredential/')"
    addSubscriptionSourceState() {
        [[ "${addSourceShouldFail}" == "true" ]] && return 1
        originalAddSubscriptionSourceState "$@"
    }
    setSubscriptionSourceCredential() {
        [[ "${setCredentialShouldFail}" == "true" ]] && return 1
        originalSetSubscriptionSourceCredential "$@"
    }
    subscriptionRemoteControlHealthAll() { printf '[{"id":"edge-a","ok":true}]\n'; }
    subscriptionRemoteControlHealth() { printf '{"ok":true}\n'; }
    userJsonCard() { recordMenuAction "userJsonCard:$1"; }
    subscribe() { recordMenuAction subscribe; }

    wireGuardMenuPartSelected() {
        [[ "${wireGuardMenuPart}" == "all" || "${wireGuardMenuPart}" == "$1" ]]
    }

    wireGuardMenuResetFixture() {
        PATH="${oldPath}"
        wireGuardApplyShouldFail=
        installControlShouldFail=
        refreshControlShouldFail=
        refreshWritesNewConfig=
        serviceQueueShouldFail=
        addSourceShouldFail=
        setCredentialShouldFail=
        restoreStateWriteShouldFail=
        restoreGroupsWriteShouldFail=
        disableStateWriteShouldFail=
        stopShouldFail=
        stopAllowMissingBackend=
        actions=
        rm -rf "${PADM_WIREGUARD_CONTROL_DIR}" "${PADM_SUBSCRIPTION_GROUPS_DIR}"
        mkdir -p "${nginxConfigPath}"
        ensureSubscriptionGroupsState
    }

    wireGuardMenuInitializeMain() {
        wireGuardMenuResetFixture
        resetMenuActions
        manageSubscriptionRoleSelection <<<"2
main.example.com
3"
        assertMenuAction initSubscriptionWireGuardMain
        subscriptionWireGuardReadState | jq -e '.role == "main" and .enabled == true and .endpoint_host == "main.example.com" and .address == "10.77.0.1/24"' >/dev/null
        grep -q 'Address = 10.77.0.1/24' "$(subscriptionWireGuardConfigFile)"
        mainStateSnapshot=$(subscriptionWireGuardReadState)
    }

    wireGuardMenuCreateReceiptJson() {
        local alias=$1
        local publicKey=$2
        local token=$3
        local outputVar=$4
        local inviteCredential inviteJson __receiptJson
        subscriptionWireGuardCreateInvite "${alias}" inviteCredential || return 1
        inviteJson=$(subscriptionWireGuardCredentialDecode "${inviteCredential}") || return 1
        __receiptJson=$(jq -cn \
            --arg inviteId "$(jq -r '.invite_id' <<<"${inviteJson}")" \
            --arg publicKey "${publicKey}" \
            --arg token "${token}" \
            '{version:1,kind:"receipt",invite_id:$inviteId,public_key:$publicKey,control_port:39778,token:$token}') || return 1
        printf -v "${outputVar}" '%s' "${__receiptJson}"
    }

    wireGuardMenuAddEdgePeer() {
        local receiptJson receiptCredential reservedInvite
        resetMenuActions
        if subscriptionWireGuardCreateInvite main reservedInvite >/dev/null 2>&1; then
            return 1
        fi
        assertMenuAction 'errorCard:main 是保留源 ID，不能作为被控服务器别名'
        subscriptionWireGuardReadState | jq -e 'any(.peers[]?; .id == "main") | not' >/dev/null
        wireGuardMenuCreateReceiptJson edge-a "${controlledPublicKey}" "${controlledToken}" receiptJson
        receiptCredential=$(subscriptionWireGuardCredentialEncode receipt "$(jq -c 'del(.version,.kind)' <<<"${receiptJson}")")
        resetMenuActions
        manageSubscriptionMultiServer <<<"2
2
${receiptCredential}
6
5"
        assertMenuAction 'runSubscriptionGroupSync:'
        subscriptionWireGuardReadState | jq -e --arg publicKey "${controlledPublicKey}" '.peers[] | select(.id == "edge-a" and .address == "10.77.0.2/24" and .public_key == $publicKey and .endpoint == "")' >/dev/null
        subscriptionGroupsStateRead -e --arg token "${controlledToken}" '.groups[0].sources[] | select(.id == "edge-a" and .scheme == "wireguard" and .transport == "wireguard" and .host == "10.77.0.2" and .port == 39778 and .control_token == $token)' >/dev/null
    }

    if wireGuardMenuPartSelected bootstrap; then
        wireGuardMenuInitializeMain

        jq '.endpoint_host = ""' <<<"${mainStateSnapshot}" >"$(subscriptionWireGuardStateFile)"
        if showSubscriptionWireGuardMainCredential >/dev/null 2>&1; then
            return 1
        fi
        printf '%s\n' "${mainStateSnapshot}" >"$(subscriptionWireGuardStateFile)"

        nginxFakeBin="${TMP_DIR}/wg-nginx-fail-bin"
        mkdir -p "${nginxFakeBin}"
        cat >"${nginxFakeBin}/nginx" <<'SH'
#!/usr/bin/env bash
exit 1
SH
        chmod +x "${nginxFakeBin}/nginx"
        nginxStaticPath="${TMP_DIR}/static"
        nginxTarget=$(subscriptionWireGuardNginxConfigFile)
        printf 'old config\n' >"${nginxTarget}"
        PATH="${nginxFakeBin}:${PATH}"
        if ensureSubscriptionWireGuardNginxConfig >/dev/null 2>&1; then
            PATH="${oldPath}"
            return 1
        fi
        PATH="${oldPath}"
        grep -qxF 'old config' "${nginxTarget}"
        ! regressionFindHasMatches "$(dirname "${nginxTarget}")" -maxdepth 1 \( -name '.padm-control-wg.conf.nginx.*' -o -name '.padm-control-wg.conf.backup.*' \)

        subscriptionWireGuardCreateInvite bootstrap-edge bootstrapInvite
        bootstrapInviteJson=$(subscriptionWireGuardCredentialDecode "${bootstrapInvite}")
        wireGuardMenuResetFixture
        refreshControlShouldFail=true
        resetMenuActions
        if subscriptionWireGuardJoinInvite "${bootstrapInviteJson}" false >/dev/null 2>&1; then
            refreshControlShouldFail=
            return 1
        fi
        refreshControlShouldFail=
        assertMenuAction refreshSubscriptionWireGuardNginxControl
        if assertMenuAction installSubscriptionControlService; then
            return 1
        fi
        subscriptionWireGuardReadState | jq -e '.role == "uninitialized" and .enabled == false' >/dev/null
    fi

    if wireGuardMenuPartSelected peer-add-update; then
        wireGuardMenuInitializeMain
        if subscriptionWireGuardWriteState --arg publicKey "${controlledPublicKey}" \
            '.peers += [{id:"invalid", name:"invalid", address:"10.77.0.9/24", public_key:$publicKey, enabled:true}]'; then
            return 1
        fi
        [[ "$(subscriptionWireGuardReadState)" == "${mainStateSnapshot}" ]]
        wireGuardMenuAddEdgePeer

        resetMenuActions
        manageSubscriptionMultiServer <<<"3
${updatedCredential}
edge-a
5"
        assertMenuAction 'runSubscriptionGroupSync:'
        subscriptionWireGuardReadState | jq -e --arg publicKey "${updatedPublicKey}" '.peers[] | select(.id == "edge-a" and .address == "10.77.0.3/24" and .public_key == $publicKey and .endpoint == "")' >/dev/null
        subscriptionGroupsStateRead -e '.groups[0].sources[] | select(.id == "edge-a" and .host == "10.77.0.3" and .port == 48779 and .control_token == "token-b")' >/dev/null
    fi

    if wireGuardMenuPartSelected peer-rollback-apply || wireGuardMenuPartSelected peer-rollback-apply-service; then
        wireGuardMenuInitializeMain
        wireGuardMenuAddEdgePeer

        if subscriptionWireGuardCreateInvite "bad alias" bootstrapInvite >/dev/null 2>&1; then
            return 1
        fi
        wireGuardMenuCreateReceiptJson edge-fail "${failingPublicKey}" "${failingToken}" failingReceiptJson
        wireGuardApplyShouldFail=true
        if subscriptionWireGuardCompleteInvite "${failingReceiptJson}" completedAlias >/dev/null 2>&1; then
            wireGuardApplyShouldFail=
            return 1
        fi
        wireGuardApplyShouldFail=
        if subscriptionGroupsStateRead -e 'any(.groups[0].sources[]?; .id == "edge-fail")' >/dev/null 2>&1; then
            return 1
        fi
        if subscriptionWireGuardReadState | jq -e 'any(.peers[]?; .id == "edge-fail")' >/dev/null 2>&1; then
            return 1
        fi
    fi

    if wireGuardMenuPartSelected peer-rollback-apply || wireGuardMenuPartSelected peer-rollback-apply-restore; then
        wireGuardMenuInitializeMain
        wireGuardMenuAddEdgePeer

        wireGuardMenuCreateReceiptJson edge-restore-fail "${failingPublicKey}" "${failingToken}" failingReceiptJson
        wireGuardApplyShouldFail=true
        restoreStateWriteShouldFail=true
        resetMenuActions
        if subscriptionWireGuardCompleteInvite "${failingReceiptJson}" completedAlias >/dev/null 2>&1; then
            wireGuardApplyShouldFail=
            restoreStateWriteShouldFail=
            return 1
        fi
        wireGuardApplyShouldFail=
        restoreStateWriteShouldFail=
        assertMenuAction 'errorCard:WireGuard 被控服务器服务应用失败，且旧状态恢复失败'
        subscriptionWireGuardReadState | jq -e 'any(.peers[]?; .id == "edge-restore-fail")' >/dev/null
    fi

    if wireGuardMenuPartSelected peer-rollback-source; then
        wireGuardMenuInitializeMain
        wireGuardMenuAddEdgePeer

        wireGuardMenuCreateReceiptJson edge-addfail "${failingPublicKey}" "${failingToken}" failingReceiptJson
        addSourceShouldFail=true
        if subscriptionWireGuardCompleteInvite "${failingReceiptJson}" completedAlias >/dev/null 2>&1; then
            addSourceShouldFail=
            return 1
        fi
        addSourceShouldFail=
        if subscriptionGroupsStateRead -e 'any(.groups[0].sources[]?; .id == "edge-addfail")' >/dev/null 2>&1; then
            return 1
        fi
    fi

    if wireGuardMenuPartSelected peer-rollback-credential || wireGuardMenuPartSelected peer-rollback-credential-write; then
        wireGuardMenuInitializeMain
        wireGuardMenuAddEdgePeer

        wireGuardMenuCreateReceiptJson edge-setfail "${failingPublicKey}" "${failingToken}" failingReceiptJson
        setCredentialShouldFail=true
        if subscriptionWireGuardCompleteInvite "${failingReceiptJson}" completedAlias >/dev/null 2>&1; then
            setCredentialShouldFail=
            return 1
        fi
        setCredentialShouldFail=
        if subscriptionGroupsStateRead -e 'any(.groups[0].sources[]?; .id == "edge-setfail")' >/dev/null 2>&1; then
            return 1
        fi
        if subscriptionWireGuardReadState | jq -e 'any(.peers[]?; .id == "edge-setfail")' >/dev/null 2>&1; then
            return 1
        fi
    fi

    if wireGuardMenuPartSelected peer-rollback-credential || wireGuardMenuPartSelected peer-rollback-credential-groups-restore; then
        wireGuardMenuInitializeMain
        wireGuardMenuAddEdgePeer

        wireGuardMenuCreateReceiptJson edge-groups-restore-fail "${failingPublicKey}" "${failingToken}" failingReceiptJson
        setCredentialShouldFail=true
        restoreGroupsWriteShouldFail=true
        resetMenuActions
        if subscriptionWireGuardCompleteInvite "${failingReceiptJson}" completedAlias >/dev/null 2>&1; then
            setCredentialShouldFail=
            restoreGroupsWriteShouldFail=
            return 1
        fi
        setCredentialShouldFail=
        restoreGroupsWriteShouldFail=
        assertMenuAction 'errorCard:订阅来源凭据写入失败，且旧状态恢复失败'
        subscriptionGroupsStateRead -e 'any(.groups[0].sources[]?; .id == "edge-groups-restore-fail")' >/dev/null
        if subscriptionWireGuardReadState | jq -e 'any(.peers[]?; .id == "edge-groups-restore-fail")' >/dev/null 2>&1; then
            return 1
        fi
    fi

    if wireGuardMenuPartSelected peer-source-control || wireGuardMenuPartSelected peer-source-control-toggle || wireGuardMenuPartSelected peer-source-control-clear-error || wireGuardMenuPartSelected peer-source-control-status; then
        wireGuardMenuInitializeMain
        wireGuardMenuAddEdgePeer

        if wireGuardMenuPartSelected peer-source-control || wireGuardMenuPartSelected peer-source-control-toggle; then
            resetMenuActions
            resetMenuActions
            changeSubscriptionSourceEnabledMenu <<<"edge-a
y"
            subscriptionGroupsStateRead -e '.groups[0].sources[] | select(.id == "edge-a" and .enabled == false)' >/dev/null
            assertMenuAction 'runSubscriptionGroupSync:'
            resetMenuActions
            changeSubscriptionSourceEnabledMenu <<<"edge-a
y"
            subscriptionGroupsStateRead -e '.groups[0].sources[] | select(.id == "edge-a" and .enabled == true)' >/dev/null
            assertMenuAction 'runSubscriptionGroupSync:'
        fi

        if wireGuardMenuPartSelected peer-source-control || wireGuardMenuPartSelected peer-source-control-clear-error; then
            setSubscriptionSourceSyncFailure edge-a remote_error old-error
            resetMenuActions
            clearSubscriptionSourceSyncErrorMenu() {
                subscriptionRequireMainRole || return 1
                recordMenuAction clearSubscriptionSourceSyncErrorMenu
                local sourceId=
                autoRead subscription_clear_error_source "请输入要清除错误的被控服务器源ID:" sourceId
                clearSubscriptionSourceSyncError "${sourceId}"
            }
            clearSubscriptionSourceSyncErrorMenu <<<"edge-a"
            subscriptionGroupsStateRead -e '(.groups[0].sources[] | select(.id == "edge-a") | has("last_sync_error")) | not' >/dev/null
        fi

        if wireGuardMenuPartSelected peer-source-control || wireGuardMenuPartSelected peer-source-control-status; then
            resetMenuActions
            local multiServerStatusOutput
            multiServerStatusOutput=$(manageSubscriptionMultiServer <<<"4
5")
            grep -q '^ID:edge-a$' <<<"${multiServerStatusOutput}"
            if grep -Eq 'padmwg1:|token-a' <<<"${multiServerStatusOutput}"; then
                return 1
            fi
        fi
    fi

    if wireGuardMenuPartSelected control-restore; then
        wireGuardMenuInitializeMain

        subscriptionWireGuardWriteState '.enabled = false'
        resetMenuActions
        restartSubscriptionWireGuardControl >/dev/null 2>&1
        subscriptionWireGuardReadState | jq -e '.enabled == true' >/dev/null
        assertMenuAction installSubscriptionControlService
        assertMenuAction applySubscriptionWireGuardService

        installControlShouldFail=true
        if restartSubscriptionWireGuardControl >/dev/null 2>&1; then
            installControlShouldFail=
            return 1
        fi
        installControlShouldFail=
        wireGuardApplyShouldFail=true
        if restartSubscriptionWireGuardControl >/dev/null 2>&1; then
            wireGuardApplyShouldFail=
            return 1
        fi
        wireGuardApplyShouldFail=
        refreshControlShouldFail=true
        if restartSubscriptionWireGuardControl >/dev/null 2>&1; then
            refreshControlShouldFail=
            return 1
        fi
        refreshControlShouldFail=
        nginxTarget=$(subscriptionWireGuardNginxConfigFile)
        printf 'old-nginx-control\n' >"${nginxTarget}"
        refreshWritesNewConfig=true
        serviceQueueShouldFail=true
        if restartSubscriptionWireGuardControl >/dev/null 2>&1; then
            refreshWritesNewConfig=
            serviceQueueShouldFail=
            return 1
        fi
        refreshWritesNewConfig=
        serviceQueueShouldFail=
        grep -qxF 'old-nginx-control' "${nginxTarget}"

        resetMenuActions
        manageSubscriptionMainControlDetails <<<"5
6
7"
        assertMenuAction installSubscriptionControlService
        assertMenuAction refreshSubscriptionWireGuardNginxControl
        subscriptionWireGuardReadState | jq -e '.enabled == false' >/dev/null

        subscriptionWireGuardWriteState --argjson previousState "${mainStateSnapshot}" '$previousState'
        printf 'keep-config\n' >"$(subscriptionWireGuardConfigFile)"
        stopShouldFail=true
        resetMenuActions
        if originalDisableSubscriptionWireGuardControl >/dev/null 2>&1; then
            stopShouldFail=
            return 1
        fi
        stopShouldFail=
        assertMenuAction 'errorCard:WireGuard 控制面停用失败'
        subscriptionWireGuardReadState | jq -e '.enabled == true' >/dev/null
        grep -qxF 'keep-config' "$(subscriptionWireGuardConfigFile)"

        subscriptionWireGuardWriteState --argjson previousState "${mainStateSnapshot}" '$previousState'
        disableStateWriteShouldFail=true
        resetMenuActions
        if originalDisableSubscriptionWireGuardControl >/dev/null 2>&1; then
            disableStateWriteShouldFail=
            return 1
        fi
        disableStateWriteShouldFail=
        assertMenuAction 'errorCard:WireGuard 控制面状态写入失败'
        subscriptionWireGuardReadState | jq -e '.enabled == true' >/dev/null
        grep -q 'Address = 10.77.0.1/24' "$(subscriptionWireGuardConfigFile)"

        local restoreStopState='{"enabled":false,"role":"uninitialized","interface":"wg-padm","network":"10.77.0.0/24","listen_port":51820,"control_port":39778,"firewall_owned":false,"address":"","endpoint_host":"","public_key":"","peers":[]}'
        printf 'keep-config\n' >"$(subscriptionWireGuardConfigFile)"
        stopShouldFail=true
        if subscriptionWireGuardRestoreStateAndConfig "${restoreStopState}" >/dev/null 2>&1; then
            stopShouldFail=
            return 1
        fi
        stopShouldFail=
        grep -qxF 'keep-config' "$(subscriptionWireGuardConfigFile)"

        printf 'keep-config\n' >"$(subscriptionWireGuardConfigFile)"
        stopShouldFail=true
        stopAllowMissingBackend=true
        resetMenuActions
        nginxTarget=$(subscriptionWireGuardNginxConfigFile)
        printf 'keep-nginx-control\n' >"${nginxTarget}"
        subscriptionWireGuardRestoreStateAndConfig "${restoreStopState}" >/dev/null 2>&1 || {
            stopShouldFail=
            stopAllowMissingBackend=
            return 1
        }
        stopShouldFail=
        stopAllowMissingBackend=
        assertMenuAction 'stopSubscriptionWireGuardControlService:true'
        [[ ! -e "$(subscriptionWireGuardConfigFile)" ]]
        [[ ! -e "${nginxTarget}" ]]

        local disabledConfiguredState
        subscriptionWireGuardWriteState --argjson previousState "${mainStateSnapshot}" '$previousState | .enabled = false'
        disabledConfiguredState=$(subscriptionWireGuardReadState)
        subscriptionWireGuardWriteState --arg peerPublicKey "${controlledPublicKey}" '.enabled = true | .peers += [{id:"edge-b", name:"Edge B", address:"10.77.0.3/24", public_key:$peerPublicKey, endpoint:"", enabled:true}]'
        printf 'new-config\n' >"$(subscriptionWireGuardConfigFile)"
        nginxTarget=$(subscriptionWireGuardNginxConfigFile)
        printf 'keep-nginx-control\n' >"${nginxTarget}"
        resetMenuActions
        subscriptionWireGuardRestoreStateAndConfig "${disabledConfiguredState}"
        assertMenuAction 'stopSubscriptionWireGuardControlService:true'
        if assertMenuAction applySubscriptionWireGuardService; then
            return 1
        fi
        subscriptionWireGuardReadState | jq -e '.enabled == false and .role == "main" and .address == "10.77.0.1/24" and (.peers | length) == 0' >/dev/null
        grep -qx 'Address = 10.77.0.1/24' "$(subscriptionWireGuardConfigFile)"
        grep -qx 'keep-nginx-control' "${nginxTarget}"
    fi

    if [[ -n "${oldWireGuardDir}" ]]; then PADM_WIREGUARD_CONTROL_DIR="${oldWireGuardDir}"; else unset PADM_WIREGUARD_CONTROL_DIR; fi
    currentHost="${oldCurrentHost}"
    nginxConfigPath="${oldNginxConfigPath}"
)

runSubscriptionWireGuardInviteReceiptRegression() (
    local root="${TMP_DIR}/wireguard-invite-receipt"
    local mainWireGuardDir="${root}/main-wireguard"
    local controlledWireGuardDir="${root}/controlled-wireguard"
    local mainGroupsDir="${root}/main-groups"
    local controlledGroupsDir="${root}/controlled-groups"
    local wireGuardConfig="${root}/main-wg.conf"
    local stateMarker="${root}/control.json"
    local counterFile="${root}/invite-counter"
    local testNow=1770000000
    local applyFailNext=false
    local mainPublicKey controlledPublicKeyA controlledPublicKeyB controlledPublicKeyC
    local receiptToken='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789AB'
    local inviteCredentialA inviteCredentialB inviteCredentialC joinCredential
    local inviteJsonA inviteJsonB inviteJsonC joinJson receiptJson receiptCredential controlledCredentialJson completedAlias
    local stateBefore groupsBefore pendingJson readSecretValue= secretOutput staleInviteId
    local testWireGuardState testGroupsState

    # Restore production functions because other legacy UI tests install global stubs.
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/core/state.sh"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/subscription/groups.sh"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/subscription/control.sh"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/subscription/wireguard_control.sh"

    rm -rf "${root}"
    mkdir -p "${root}"
    PADM_WIREGUARD_CONTROL_DIR="${mainWireGuardDir}"
    PADM_SUBSCRIPTION_GROUPS_DIR="${mainGroupsDir}"
    mainPublicKey=$(printf '0123456789abcdefghijklmnopqrstuv' | base64 -w 0)
    controlledPublicKeyA=$(printf 'abcdefghijklmnopqrstuvwxyz123456' | base64 -w 0)
    controlledPublicKeyB=$(printf 'ABCDEFGHIJKLMNOPQRSTUVWXYZ123456' | base64 -w 0)
    controlledPublicKeyC=$(printf '01234567890123456789012345678901' | base64 -w 0)

    errorCard() { return 0; }
    statusCard() { return 0; }
    successCard() { return 0; }
    warnCard() { return 0; }
    subscriptionWireGuardConfigFile() { printf '%s\n' "${wireGuardConfig}"; }
    subscriptionWireGuardStateFile() { printf '%s\n' "${stateMarker}"; }
    subscriptionWireGuardReadState() {
        subscriptionWireGuardValidateState "${testWireGuardState}" || return 1
        printf '%s\n' "${testWireGuardState}"
    }
    subscriptionWireGuardWriteState() {
        local filter candidate
        local jqArgs=()
        while (($# > 1)); do
            jqArgs+=("$1")
            shift
        done
        filter=$1
        candidate=$(jq -c "${jqArgs[@]}" "${filter}" <<<"${testWireGuardState}") || return 1
        subscriptionWireGuardValidateState "${candidate}" || return 1
        testWireGuardState=${candidate}
        printf '%s\n' "${testWireGuardState}" >"${stateMarker}"
    }
    subscriptionGroupsStateRead() { jq "$@" <<<"${testGroupsState}"; }
    subscriptionGroupsStateWrite() {
        local candidate
        candidate=$(jq -c "$@" <<<"${testGroupsState}") || return 1
        testGroupsState=${candidate}
    }
    subscriptionGroupsWithLock() {
        local SUBSCRIPTION_GROUPS_LOCK_HELD=1
        "$@"
    }
    subscriptionWireGuardNow() { printf '%s\n' "${testNow}"; }
    subscriptionWireGuardRandomInviteId() {
        local counter=0
        [[ -f "${counterFile}" ]] && counter=$(<"${counterFile}")
        counter=$((counter + 1))
        printf '%s\n' "${counter}" >"${counterFile}"
        printf '%064x\n' "${counter}"
    }
    applySubscriptionWireGuardService() {
        if [[ "${applyFailNext}" == "true" ]]; then
            applyFailNext=false
            return 1
        fi
        mkdir -p "$(dirname "${wireGuardConfig}")"
        printf 'Address = %s\n' "$(subscriptionWireGuardReadState | jq -r '.address')" >"${wireGuardConfig}"
    }
    subscriptionWireGuardWaitForAddress() { return 0; }
    subscriptionWireGuardInstallControlPlane() { return 0; }
    installSubscriptionWireGuardTools() { return 0; }
    subscriptionWireGuardEnsureKeys() { return 0; }
    subscriptionControlledTransitionPreflight() { return 0; }
    subscriptionWireGuardPublicKey() { printf '%s\n' "${controlledPublicKeyA}"; }
    subscriptionControlEnsureToken() { return 0; }
    subscriptionControlToken() { printf '%s\n' "${receiptToken}"; }
    testGroupsState=$(jq -cn '{version:2,active_group:"default",groups:[{id:"default",name:"Default",admin:{id:"admin",name:"Admin",enabled:true,allowed_sources:["*"],traffic_limit_gb:0,token:""},sources:[{id:"main",name:"Main",role:"main",scheme:"local",transport:"local",host:"127.0.0.1",port:0,enabled:true,sync_status:"local"}],user_groups:[],sync:{enabled:true,interval_minutes:10,last_run:"",last_status:"pending",failures:[],quota_auto_apply:false},traffic:{global:{upload:0,download:0},admin:{upload:0,download:0,sources:{}},user_groups:{},sources:{}}}]}')
    testWireGuardState=$(jq -cn --arg publicKey "${mainPublicKey}" '{enabled:true,role:"main",interface:"wg-padm",network:"10.77.0.0/24",listen_port:51820,control_port:39778,firewall_owned:false,address:"10.77.0.1/24",endpoint_host:"main.example.com",public_key:$publicKey,peers:[]}')
    printf '%s\n' "${testWireGuardState}" >"${stateMarker}"
    printf 'keep-config\n' >"${wireGuardConfig}"

    subscriptionWireGuardCreateInvite hk-1 inviteCredentialA
    inviteJsonA=$(subscriptionWireGuardCredentialDecode "${inviteCredentialA}")
    jq -e '.kind == "invite" and .alias == "hk-1" and .address == "10.77.0.2/24" and .expires_at == 1770086400' <<<"${inviteJsonA}" >/dev/null
    subscriptionWireGuardReadState | jq -e '(.peers | length) == 0 and (.pending_invites | length) == 1' >/dev/null
    grep -qxF 'keep-config' "${wireGuardConfig}"

    subscriptionWireGuardCreateInvite hk-2 inviteCredentialB
    inviteJsonB=$(subscriptionWireGuardCredentialDecode "${inviteCredentialB}")
    jq -e '.address == "10.77.0.3/24"' <<<"${inviteJsonB}" >/dev/null
    pendingJson=$(subscriptionWireGuardListPendingInvites)
    jq -e 'length == 2 and all(.[]; has("invite_id") | not)' <<<"${pendingJson}" >/dev/null
    if grep -q "$(jq -r '.invite_id' <<<"${inviteJsonA}")" <<<"${pendingJson}"; then
        return 1
    fi

    subscriptionWireGuardCancelInvite hk-1
    subscriptionWireGuardCreateInvite hk-3 inviteCredentialC
    inviteJsonC=$(subscriptionWireGuardCredentialDecode "${inviteCredentialC}")
    jq -e '.address == "10.77.0.2/24"' <<<"${inviteJsonC}" >/dev/null
    if subscriptionWireGuardCreateInvite hk-3 inviteCredentialA >/dev/null 2>&1; then
        return 1
    fi
    staleInviteId=$(printf '%064x' 99)
    subscriptionWireGuardWriteState --arg inviteId "${staleInviteId}" --argjson expiresAt "$((testNow - 1))" '.pending_invites += [{invite_id:$inviteId,alias:"stale-edge",address:"10.77.0.4/24",expires_at:$expiresAt}]'

    receiptJson=$(jq -cn --arg inviteId "$(jq -r '.invite_id' <<<"${inviteJsonB}")" --arg publicKey "${controlledPublicKeyB}" --arg token "${receiptToken}" '{version:1,kind:"receipt",invite_id:$inviteId,public_key:$publicKey,control_port:39778,token:$token}')
    subscriptionWireGuardCompleteInvite "${receiptJson}" completedAlias
    [[ "${completedAlias}" == "hk-2" ]]
    subscriptionWireGuardReadState | jq -e --arg publicKey "${controlledPublicKeyB}" 'any(.peers[]?; .id == "hk-2" and .address == "10.77.0.3/24" and .public_key == $publicKey and .endpoint == "") and (.pending_invites | length) == 1 and .pending_invites[0].alias == "hk-3"' >/dev/null
    subscriptionGroupsStateRead -e --arg token "${receiptToken}" '.groups[0].sources[] | select(.id == "hk-2" and .host == "10.77.0.3" and .control_token == $token)' >/dev/null
    stateBefore=$(subscriptionWireGuardReadState)
    groupsBefore=$(subscriptionGroupsStateRead -c '.')
    if subscriptionWireGuardCompleteInvite "${receiptJson}" completedAlias >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(subscriptionWireGuardReadState)" == "${stateBefore}" ]]
    [[ "$(subscriptionGroupsStateRead -c '.')" == "${groupsBefore}" ]]

    receiptJson=$(jq -cn --arg inviteId "$(jq -r '.invite_id' <<<"${inviteJsonC}")" --arg publicKey "${controlledPublicKeyC}" --arg token "${receiptToken}" '{version:1,kind:"receipt",invite_id:$inviteId,public_key:$publicKey,control_port:39778,token:$token}')
    stateBefore=$(subscriptionWireGuardReadState)
    groupsBefore=$(subscriptionGroupsStateRead -c '.')
    applyFailNext=true
    if subscriptionWireGuardCompleteInvite "${receiptJson}" completedAlias >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(subscriptionWireGuardReadState)" == "${stateBefore}" ]]
    [[ "$(subscriptionGroupsStateRead -c '.')" == "${groupsBefore}" ]]

    subscriptionWireGuardWriteState --arg id hk-3 --arg address "$(jq -r '.address' <<<"${inviteJsonC}")" --arg publicKey "${controlledPublicKeyC}" '.peers += [{id:$id,name:$id,address:$address,public_key:$publicKey,endpoint:"",enabled:true}]'
    subscriptionWireGuardCompleteInvite "${receiptJson}" completedAlias
    [[ "${completedAlias}" == "hk-3" ]]
    subscriptionGroupsStateRead -e '.groups[0].sources[] | select(.id == "hk-3" and .control_token != "")' >/dev/null

    stateBefore=$(subscriptionWireGuardReadState)
    staleInviteId=$(printf '%064x' 100)
    subscriptionWireGuardWriteState --arg inviteId "${staleInviteId}" --argjson expiresAt "$((testNow - 1))" '.network = "10.77.0.0/16" | .address = "10.77.0.1/16" | .pending_invites = [{invite_id:$inviteId,alias:"expired-edge",address:"10.77.0.4/24",expires_at:$expiresAt}]'
    if subscriptionWireGuardCreateInvite unsupported inviteCredentialA >/dev/null 2>&1; then
        return 1
    fi
    subscriptionWireGuardReadState | jq -e '(.pending_invites | length) == 0' >/dev/null
    testWireGuardState=${stateBefore}
    printf '%s\n' "${testWireGuardState}" >"${stateMarker}"

    controlledCredentialJson=$(jq -cn --arg publicKey "${controlledPublicKeyA}" --arg token "${receiptToken}" '{version:1,kind:"controlled",address:"10.77.0.10/24",public_key:$publicKey,control_port:39778,token:$token}')
    stateBefore=$(subscriptionWireGuardReadState)
    groupsBefore=$(subscriptionGroupsStateRead -c '.')
    if subscriptionWireGuardUpdatePeerAndCredential missing-edge "${controlledCredentialJson}" >/dev/null 2>&1 ||
        subscriptionWireGuardRemovePeerAndSource missing-edge >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(subscriptionWireGuardReadState)" == "${stateBefore}" ]]
    [[ "$(subscriptionGroupsStateRead -c '.')" == "${groupsBefore}" ]]

    subscriptionWireGuardCreateInvite join-edge joinCredential
    joinJson=$(subscriptionWireGuardCredentialDecode "${joinCredential}")
    PADM_WIREGUARD_CONTROL_DIR="${controlledWireGuardDir}"
    PADM_SUBSCRIPTION_GROUPS_DIR="${controlledGroupsDir}"
    wireGuardConfig="${root}/controlled-wg.conf"
    stateMarker="${root}/controlled-control.json"
    testWireGuardState=$(jq -cn '{enabled:false,role:"uninitialized",interface:"wg-padm",network:"10.77.0.0/24",listen_port:51820,control_port:39778,firewall_owned:false,address:"",endpoint_host:"",public_key:"",peers:[]}')
    testGroupsState=$(jq -cn '{version:2,active_group:"default",groups:[{id:"default",name:"Default",admin:{id:"admin",name:"Admin",enabled:true,allowed_sources:["*"],traffic_limit_gb:0,token:""},sources:[{id:"main",name:"Main",role:"main",scheme:"local",transport:"local",host:"127.0.0.1",port:0,enabled:true,sync_status:"local"}],user_groups:[],sync:{enabled:true,interval_minutes:10,last_run:"",last_status:"pending",failures:[],quota_auto_apply:false},traffic:{global:{upload:0,download:0},admin:{upload:0,download:0,sources:{}},user_groups:{},sources:{}}}]}')
    printf '%s\n' "${testWireGuardState}" >"${stateMarker}"
    subscriptionWireGuardJoinInvite "${joinJson}" false
    subscriptionWireGuardReadState | jq -e --arg inviteId "$(jq -r '.invite_id' <<<"${joinJson}")" '.role == "controlled" and .address == $address and .join_invite_id == $inviteId and (.peers | length) == 1 and .peers[0].id == "main"' --arg address "$(jq -r '.address' <<<"${joinJson}")" >/dev/null
    subscriptionWireGuardJoinReceiptCredential receiptCredential
    subscriptionWireGuardCredentialDecode "${receiptCredential}" | jq -e --arg inviteId "$(jq -r '.invite_id' <<<"${joinJson}")" --arg token "${receiptToken}" '.kind == "receipt" and .invite_id == $inviteId and .token == $token' >/dev/null
    stateBefore=$(subscriptionWireGuardReadState)
    subscriptionWireGuardWriteState --arg publicKey "${controlledPublicKeyB}" '.peers += [{id:"main",name:"重复主控",address:"10.77.0.9/24",public_key:$publicKey,endpoint:"backup.example.com:51820",enabled:true}]'
    if subscriptionWireGuardJoinReceiptCredential receiptCredential >/dev/null 2>&1; then
        return 1
    fi
    testWireGuardState=${stateBefore}
    printf '%s\n' "${testWireGuardState}" >"${stateMarker}"
    stateBefore=$(subscriptionWireGuardReadState)
    if subscriptionWireGuardJoinInvite "$(jq -c '.address = "10.77.0.9/24"' <<<"${joinJson}")" false >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(subscriptionWireGuardReadState)" == "${stateBefore}" ]]

    joinJson=$(jq -c '.invite_id = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" | .address = "10.77.0.8/24"' <<<"${joinJson}")
    if subscriptionWireGuardJoinInvite "${joinJson}" false >/dev/null 2>&1; then
        return 1
    fi
    subscriptionWireGuardJoinInvite "${joinJson}" true
    subscriptionWireGuardReadState | jq -e '.address == "10.77.0.8/24" and .join_invite_id == "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' >/dev/null

    joinJson=$(jq -cn --arg publicKey "${mainPublicKey}" '{version:1,kind:"main",endpoint_host:"main.example.com",listen_port:51820,network:"10.77.0.0/24",address:"10.77.0.1/24",public_key:$publicKey}')
    subscriptionWireGuardImportMainCredentialJson "${joinJson}"
    subscriptionWireGuardReadState | jq -e 'has("join_invite_id") | not' >/dev/null

    secretOutput="${root}/secret-output"
    subscriptionWireGuardReadSecret readSecretValue "secret:" <<<"hidden-value" >"${secretOutput}" 2>&1
    [[ "${readSecretValue}" == "hidden-value" ]]
    if grep -q 'hidden-value' "${secretOutput}"; then
        return 1
    fi
)

runSubscriptionWireGuardMenuFlowBootstrapRegression() {
    local validPublicKey
    local peerPublicKey
    local newPeerPublicKey
    local duplicateAddressState
    local duplicateKeyState
    local outsideNetworkState
    local validState
    local baseState mainDisabledState mainEnabledState controlledState invalidState
    validPublicKey=$(printf '01234567890123456789012345678901' | base64 -w 0)
    peerPublicKey=$(printf 'abcdefghijklmnopqrstuvwxyz123456' | base64 -w 0)
    newPeerPublicKey=$(printf 'ABCDEFGHIJKLMNOPQRSTUVWXYZ123456' | base64 -w 0)
    subscriptionWireGuardValidPublicKeyValue "${validPublicKey}"
    ! subscriptionWireGuardValidPublicKeyValue 'not-a-wireguard-key'
    ! subscriptionWireGuardValidPublicKeyValue 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    baseState=$(jq -n --arg interface "$(subscriptionWireGuardInterface)" '{enabled:false,role:"uninitialized",interface:$interface,network:"10.77.0.0/24",listen_port:51820,control_port:39778,firewall_owned:false,address:"",endpoint_host:"",public_key:"",peers:[]}')
    subscriptionWireGuardValidateState "${baseState}"
    invalidState=$(jq '.enabled = true' <<<"${baseState}")
    ! subscriptionWireGuardValidateState "${invalidState}"
    invalidState=$(jq 'del(.role)' <<<"${baseState}")
    ! subscriptionWireGuardValidateState "${invalidState}"
    invalidState=$(jq '.enabled = "false"' <<<"${baseState}")
    ! subscriptionWireGuardValidateState "${invalidState}"

    mainDisabledState=$(jq --arg publicKey "${validPublicKey}" '.role = "main" | .address = "10.77.0.1/24" | .endpoint_host = "main.example.com" | .public_key = $publicKey' <<<"${baseState}")
    mainEnabledState=$(jq '.enabled = true' <<<"${mainDisabledState}")
    controlledState=$(jq --arg publicKey "${validPublicKey}" '.role = "controlled" | .address = "10.77.0.2/24" | .public_key = $publicKey' <<<"${baseState}")
    subscriptionWireGuardValidateState "${mainDisabledState}"
    subscriptionWireGuardValidateState "${mainEnabledState}"
    subscriptionWireGuardValidateState "${controlledState}"
    validState=$(jq -n --arg publicKey "${validPublicKey}" --arg peerPublicKey "${peerPublicKey}" '{network:"10.77.0.0/24",address:"10.77.0.1/24",listen_port:51820,public_key:$publicKey,peers:[{id:"a",name:"A",address:"10.77.0.2/24",public_key:$peerPublicKey,endpoint:"",enabled:true}]}')
    subscriptionWireGuardValidateStateForConfig "${validState}" || return 1
    subscriptionWireGuardPeerIdentityAvailable "${validState}" "b" "10.77.0.3/24" "${newPeerPublicKey}" || return 1
    if subscriptionWireGuardPeerIdentityAvailable "${validState}" "b" "10.77.0.2/24" "${newPeerPublicKey}"; then
        return 1
    fi
    duplicateAddressState=$(jq -n --arg publicKey "${validPublicKey}" --arg peerPublicKey "${peerPublicKey}" --arg newPeerPublicKey "${newPeerPublicKey}" '{network:"10.77.0.0/24",address:"10.77.0.1/24",listen_port:51820,public_key:$publicKey,peers:[{id:"a",name:"A",address:"10.77.0.2/24",public_key:$peerPublicKey,endpoint:"",enabled:true},{id:"b",name:"B",address:"10.77.0.2/32",public_key:$newPeerPublicKey,endpoint:"",enabled:true}]}')
    if subscriptionWireGuardValidateStateForConfig "${duplicateAddressState}" >/dev/null 2>&1; then
        return 1
    fi
    duplicateKeyState=$(jq -n --arg publicKey "${validPublicKey}" --arg peerPublicKey "${peerPublicKey}" '{network:"10.77.0.0/24",address:"10.77.0.1/24",listen_port:51820,public_key:$publicKey,peers:[{id:"a",name:"A",address:"10.77.0.2/24",public_key:$peerPublicKey,endpoint:"",enabled:true},{id:"b",name:"B",address:"10.77.0.3/24",public_key:$peerPublicKey,endpoint:"",enabled:true}]}')
    if subscriptionWireGuardValidateStateForConfig "${duplicateKeyState}" >/dev/null 2>&1; then
        return 1
    fi
    outsideNetworkState=$(jq -n --arg publicKey "${validPublicKey}" --arg peerPublicKey "${peerPublicKey}" '{network:"10.77.0.0/24",address:"10.77.0.1/24",listen_port:51820,public_key:$publicKey,peers:[{id:"a",name:"A",address:"10.78.0.2/24",public_key:$peerPublicKey,endpoint:"",enabled:true}]}')
    if subscriptionWireGuardValidateStateForConfig "${outsideNetworkState}" >/dev/null 2>&1; then
        return 1
    fi
    (
        local callLog="${TMP_DIR}/wireguard-role-shared-entry.log"
        local stateFile
        PADM_WIREGUARD_CONTROL_DIR="${TMP_DIR}/wireguard-role-shared-entry"
        mkdir -p "${PADM_WIREGUARD_CONTROL_DIR}"
        stateFile=$(subscriptionWireGuardStateFile)
        padmRunPortAllowTransaction() { printf 'install\n' >>"${callLog}"; }
        subscriptionGroupsWithLock() { printf 'sync\n' >>"${callLog}"; }

        : >"${callLog}"
        printf '%s\n' "${controlledState}" >"${stateFile}"
        if installSubscribe >/dev/null 2>&1 || runSubscriptionGroupSync >/dev/null 2>&1; then
            return 1
        fi
        [[ ! -s "${callLog}" ]]

        printf '%s\n' "${invalidState}" >"${stateFile}"
        if installSubscribe >/dev/null 2>&1 || runSubscriptionGroupSync >/dev/null 2>&1; then
            return 1
        fi
        [[ ! -s "${callLog}" ]]

        printf '%s\n' "${mainDisabledState}" >"${stateFile}"
        if subscriptionRemoteScopeEnabled; then
            return 1
        fi
        installSubscribe
        runSubscriptionGroupSync
        [[ "$(<"${callLog}")" == $'install\nsync' ]]

        : >"${callLog}"
        rm -f "${stateFile}"
        if subscriptionRemoteScopeEnabled; then
            return 1
        fi
        installSubscribe
        runSubscriptionGroupSync
        [[ "$(<"${callLog}")" == $'install\nsync' ]]

        printf '%s\n' "${mainEnabledState}" >"${stateFile}"
        subscriptionRemoteScopeEnabled
    )
    runSubscriptionWireGuardMenuFlowRegression bootstrap
    runSubscriptionWireGuardInviteReceiptRegression
}

runSubscriptionWireGuardRestoreRunnerRegression() (
    local errorLog="${TMP_DIR}/subscription-wireguard-restore-runner-error.log"
    local helperLog="${TMP_DIR}/subscription-wireguard-restore-runner-helper.log"
    : >"${errorLog}"
    : >"${helperLog}"
    errorCard() { printf '%s\n' "$@" >>"${errorLog}"; }
    subscriptionWireGuardStateFile() { printf '%s\n' "/tmp/wg-state.json"; }
    subscriptionWireGuardConfigFile() { printf '%s\n' "/tmp/wg.conf"; }
    subscriptionGroupsFile() { printf '%s\n' "/tmp/groups.json"; }
    subscriptionWireGuardAppendManualCheckLine() {
        printf "manual-check:%s|%s\n" "$2" "$3" >>"${helperLog}"
        printf -v "$1" '%s' "${2}：${3}"
    }

    subscriptionWireGuardRestoreStateAndConfig() { return 1; }
    regressionExpectStatus 1 subscriptionWireGuardRunRestoreSteps '{}' "" "WireGuard 主控服务启动失败"
    grep -q '^WireGuard 主控服务启动失败，且旧状态恢复失败$' "${errorLog}"
    grep -q 'WireGuard 状态文件' "${errorLog}"
    grep -q 'WireGuard 配置文件' "${errorLog}"
    grep -q 'manual-check:请手动检查 WireGuard 状态文件|/tmp/wg-state.json' "${helperLog}"
    grep -q 'manual-check:请手动检查 WireGuard 配置文件|/tmp/wg.conf' "${helperLog}"

    : >"${errorLog}"
    : >"${helperLog}"
    subscriptionWireGuardRestoreStateAndConfig() { return 0; }
    subscriptionWireGuardRestoreGroupsState() { return 1; }
    regressionExpectStatus 1 subscriptionWireGuardRunRestoreSteps '{}' '{}' "订阅来源凭据写入失败"
    grep -q '^订阅来源凭据写入失败，且旧状态恢复失败$' "${errorLog}"
    grep -q '订阅组状态文件' "${errorLog}"
    grep -q 'manual-check:请手动检查订阅组状态文件|/tmp/groups.json' "${helperLog}"
)

runCoreInvalidInputRetryMenuRegression() (
    local actions=
    local menuHandler

    recordMenuAction() {
        actions+="$1"$'\n'
    }
    assertMenuAction() {
        grep -qxF "$1" <<<"${actions}"
    }
    errorCard() {
        recordMenuAction "errorCard:$1"
    }
    sampleMenu() {
        recordMenuAction "sampleMenu:$*"
    }

    declare -F coreInvalidInputRetryMenu >/dev/null
    coreInvalidInputRetryMenu sampleMenu alpha beta
    assertMenuAction 'errorCard:输入有误，请重新输入'
    assertMenuAction 'sampleMenu:alpha beta'

    for menuHandler in \
        xrayVersionManageMenu \
        singBoxVersionManageMenu \
        coreServiceControlMenu \
        coreConfigMaintenanceMenu \
        coreLogsMenu \
        coreAllServicesMenu \
        coreVersionManageMenu; do
        [[ "$(grep -cE "^${menuHandler}\\(\\)" "${PROJECT_ROOT}/shell/core/menu.sh")" == "1" ]]
        ! grep -qE "^${menuHandler}\\(\\)" "${PROJECT_ROOT}/shell/core/cores.sh"
        ! grep -qE "coreInvalidInputRetryMenu[[:space:]]+${menuHandler}" \
            "${PROJECT_ROOT}/shell/core/menu.sh" "${PROJECT_ROOT}/shell/core/cores.sh"
    done
    [[ "$(grep -cE '^xrayGeoDataMenu\(\)' "${PROJECT_ROOT}/shell/core/menu.sh")" == "1" ]]
)

runCoreSelectionRetryActionRegression() (
    local actions=
    local -a expectedCounts=(
        'shell/core/menu.sh|7'
        'shell/core/cores.sh|1'
        'shell/core/routing_access_control.sh|3'
        'shell/core/manage.sh|18'
        'shell/core/fail2ban.sh|1'
        'shell/core/entry_helpers.sh|1'
        'shell/core/routing_socks.sh|4'
        'shell/core/routing_ipv6.sh|1'
    )
    local -a expectedPatterns=(
        'shell/core/menu.sh|coreSelectionRetryAction menu'
        'shell/core/cores.sh|coreSelectionRetryAction selectCoreInstall'
        'shell/core/routing_access_control.sh|coreSelectionRetryAction removeAccessControlMenu'
        'shell/core/manage.sh|coreSelectionRetryAction manageTraditionalTlsFallback "$@"'
        'shell/core/manage.sh|coreSelectionRetryAction checkBTPanel'
        'shell/core/manage.sh|coreSelectionRetryAction manageXHTTPPresets'
        'shell/core/manage.sh|coreSelectionRetryAction manageTuic'
        'shell/core/fail2ban.sh|coreSelectionRetryAction manageFail2ban'
        'shell/core/entry_helpers.sh|coreSelectionRetryAction bbrInstall'
        'shell/core/routing_socks.sh|coreSelectionRetryAction socks5Routing'
        'shell/core/routing_ipv6.sh|coreSelectionRetryAction ipv6Routing'
    )
    local -a removedPatterns=(
        'shell/core/menu.sh|coreSelectionErrorCard
        menu'
        'shell/core/cores.sh|coreSelectionErrorCard
        selectCoreInstall'
        'shell/core/routing_access_control.sh|coreSelectionErrorCard; removeAccessControlMenu; return'
        'shell/core/manage.sh|coreSelectionErrorCard
        manageTraditionalTlsFallback "$@"'
        'shell/core/manage.sh|coreSelectionErrorCard
        checkBTPanel'
        'shell/core/manage.sh|coreSelectionErrorCard; manageXHTTPPresets'
        'shell/core/manage.sh|coreSelectionErrorCard
        manageTuic'
        'shell/core/fail2ban.sh|coreSelectionErrorCard
        manageFail2ban'
        'shell/core/entry_helpers.sh|coreSelectionErrorCard
        bbrInstall'
        'shell/core/routing_socks.sh|coreSelectionErrorCard
        socks5Routing'
        'shell/core/routing_ipv6.sh|coreSelectionErrorCard
        ipv6Routing'
    )
    local entry file pattern expectedCount actualCount

    recordMenuAction() {
        actions+="$1"$'\n'
    }
    assertMenuAction() {
        grep -qxF "$1" <<<"${actions}"
    }
    errorCard() {
        recordMenuAction "errorCard:$1"
    }
    sampleAction() {
        recordMenuAction "sampleAction:$*"
    }

    declare -F coreSelectionRetryAction >/dev/null
    coreSelectionRetryAction sampleAction alpha beta
    assertMenuAction 'errorCard:选择错误，请重新选择'
    assertMenuAction 'sampleAction:alpha beta'

    for entry in "${expectedCounts[@]}"; do
        IFS='|' read -r file expectedCount <<<"${entry}"
        actualCount=$(grep -cF 'coreSelectionRetryAction ' "${PROJECT_ROOT}/${file}")
        [[ "${actualCount}" == "${expectedCount}" ]]
    done
    for entry in "${expectedPatterns[@]}"; do
        IFS='|' read -r file pattern <<<"${entry}"
        grep -qF "${pattern}" "${PROJECT_ROOT}/${file}"
    done
    for entry in "${removedPatterns[@]}"; do
        IFS='|' read -r file pattern <<<"${entry}"
        ! grep -qF "${pattern}" "${PROJECT_ROOT}/${file}"
    done
)

runMenuSmokeRegression() {
    local actions=
    local output= menuItems=
    local menuSmokePart="${1:-all}"
    local parentTmpDir="${TMP_DIR}"
    local TMP_DIR="${parentTmpDir}/menu-smoke-${BASHPID:-$$}"
    local PADM_SUBSCRIPTION_GROUPS_DIR="${TMP_DIR}/subscribe_groups"
    local PADM_WIREGUARD_CONTROL_DIR="${TMP_DIR}/wireguard"
    local oldConfigPath="${configPath:-}"
    local oldCoreInstallType="${coreInstallType:-}"
    local oldRealityPageSize="${REALITY_TARGET_PAGE_SIZE:-}"
    local serviceQueueShouldFail=
    local serviceActionShouldFail=
    local checkActionShouldFail=
    local xrayInstalledState=true singBoxInstalledState=true serviceInstalledState=true
    local xrayRunningState=true singBoxRunningState=false nginxRunningState=true
    local nginxReasonsMock="当前协议入口"
    local wgChoice
    local wgAction
    coreInstallType=${coreInstallType:-}

    menuSmokePartSelected() {
        [[ "${menuSmokePart}" == "all" || "${menuSmokePart}" == "$1" ]]
    }
    recordMenuAction() {
        actions+="$1"$'\n'
    }
    assertMenuAction() {
        grep -qxF "$1" <<<"${actions}"
    }
    resetMenuActions() {
        actions=
    }
    resetMenuRender() {
        output=
        menuItems=
    }
    eval "$(declare -f menu | sed '1s/^menu /originalCoreMainMenu /')"
    menu() { recordMenuAction menu; }
    uiStyle() { printf '%s' "$2"; }
    menuLine() { output+="$*"$'\n'; }
    menuMutedLine() { output+="$*"$'\n'; }
    menuSection() { output+="$*"$'\n'; }
    menuItem() { output+="$2 $3"$'\n'; menuItems+="$2"$'\n'; }
    menuDangerItem() { output+="$2 $3"$'\n'; menuItems+="$2"$'\n'; }
    menuClose() { return 0; }
    menuRecommendedItem() { output+="$2 $3"$'\n'; menuItems+="$2"$'\n'; }
    menuReturnItem() { output+="$2 $3"$'\n'; menuItems+="$2"$'\n'; }
    statusCard() { recordMenuAction "statusCard:$1"; }
    warnCard() { recordMenuAction "warnCard:$1"; }
    errorCard() { recordMenuAction "errorCard:$1"; }
    successCard() { recordMenuAction "successCard:$1"; }
    if menuSmokePartSelected core; then
        coreSelectionErrorCard
        assertMenuAction 'errorCard:选择错误，请重新选择'
        resetMenuActions
        coreInvalidInputErrorCard
        assertMenuAction 'errorCard:输入有误，请重新输入'
        resetMenuActions
        coreCancelledStatusCard "操作未执行"
        assertMenuAction 'statusCard:已取消'
        resetMenuActions
        coreRuleExistsStatusCard "example.com 已存在，跳过"
        assertMenuAction 'statusCard:规则已存在'
        resetMenuActions
        corePortInputErrorCard
        assertMenuAction 'errorCard:端口输入错误'
        resetMenuActions
        aloneNginxConfigRecoveredErrorCard
        assertMenuAction 'errorCard:Nginx 配置检测失败，已恢复旧 alone.conf'
        resetMenuActions
        nginxStartFailureCard "请查看下方日志"
        assertMenuAction 'statusCard:Nginx 启动失败'
        resetMenuActions
        coreNotInstalledErrorCard
        assertMenuAction 'errorCard:未安装，请使用脚本安装'
        resetMenuActions
        coreDomainRequiredErrorCard
        assertMenuAction 'errorCard:域名不可为空'
        resetMenuActions
        coreIPRequiredErrorCard
        assertMenuAction 'errorCard:IP不可为空'
        resetMenuActions
        xrayConfigValidationFailureCard "已取消启动"
        assertMenuAction 'statusCard:Xray 配置校验失败'
        resetMenuActions
        xrayPrereleaseCompatibilityCard "通过"
        assertMenuAction 'statusCard:Xray 预发布版试跑'
        resetMenuActions
        singBoxPrereleaseCompatibilityCard "通过"
        assertMenuAction 'statusCard:sing-box 预发布版试跑'
        resetMenuActions
        xrayConfigValidationCard "通过"
        assertMenuAction 'statusCard:Xray 当前配置检查'
        resetMenuActions
        singBoxConfigValidationCard "通过"
        assertMenuAction 'statusCard:sing-box 当前配置检查'
        resetMenuActions
        skipTlsCertificateStatusCard "检测到宝塔面板/1Panel"
        assertMenuAction 'statusCard:跳过 TLS 证书'
        resetMenuActions
        protocolPortInputStatusCard "端口不合法"
        assertMenuAction 'statusCard:端口输入'
        resetMenuActions
        protocolPortHoppingRangeStatusCard "范围不合法"
        assertMenuAction 'statusCard:端口跳跃范围'
        resetMenuActions
        protocolPortHoppingStatusCard "删除成功"
        assertMenuAction 'statusCard:端口跳跃'
        resetMenuActions
        tuicAlgorithmStatusCard "cubic"
        assertMenuAction 'statusCard:Tuic 算法'
        resetMenuActions
        tlsCertificateCard "重新生成证书"
        assertMenuAction 'statusCard:TLS 证书'
        resetMenuActions
        tlsCertificateStatusCard "未检测到本机 TLS 证书"
        assertMenuAction 'statusCard:TLS 证书状态'
        resetMenuActions
    fi
    progressCard() { return 0; }
    showInstallStatus() { return 0; }
    checkWgetShowProgress() { return 0; }
    mkdirTools() { return 0; }
    aliasInstall() { return 0; }
    getScriptVersion() { printf 'test\n'; }
    autoRead() {
        local targetVar=$3
        local input=
        if ! IFS= read -r input; then
            printf -v "${targetVar}" '%s' ""
            return 1
        fi
        printf -v "${targetVar}" '%s' "${input}"
    }
    autoConfirm() {
        local targetVar=$4
        local input=
        IFS= read -r input || input=$3
        [[ -z "${input}" ]] && input=$3
        printf -v "${targetVar}" '%s' "${input}"
    }
    selectCoreInstall() { recordMenuAction selectCoreInstall; }
    manageXHTTP() { recordMenuAction manageXHTTP; }
    manageHysteria() { recordMenuAction manageHysteria; }
    manageTuic() { recordMenuAction manageTuic; }
    addCorePort() { recordMenuAction addCorePort; }
    manageCDN() { recordMenuAction manageCDN; }
    readInstallProtocolType() { coreInstallType=1; }
    readConfigHostPathUUID() {
        realityTargetHost=www.ibm.com
        realityTargetPort=443
        realitySNI=www.ibm.com
    }
    readCustomPort() { return 0; }
    readSingBoxConfig() { return 0; }
    currentProtocolHasAny() { return 0; }
    regenerateRealityProfile() { recordMenuAction regenerateRealityProfile; }
    configureRealityStreamSplit() { recordMenuAction configureRealityStreamSplit; }
    showRealityStreamSplitStatus() { recordMenuAction showRealityStreamSplitStatus; }
    disableRealityStreamSplit() { recordMenuAction disableRealityStreamSplit; }
    changeInstalledRealityTarget() { recordMenuAction "changeReality:$*"; }
    subscribe() { recordMenuAction subscribe; }
    showSubscriptionServiceStatus() { recordMenuAction showSubscriptionServiceStatus; }
    showSubscriptionSources() { recordMenuAction showSubscriptionSources; }
    showSubscriptionSourceControlUrls() { recordMenuAction showSubscriptionSourceControlUrls; }
    showSubscriptionSourceSyncResults() { recordMenuAction showSubscriptionSourceSyncResults; }
    showSubscriptionWireGuardMainCredential() { recordMenuAction showSubscriptionWireGuardMainCredential; }
    showSubscriptionWireGuardControlledCredential() { recordMenuAction showSubscriptionWireGuardControlledCredential; }
    showSubscriptionWireGuardControlledAccessCredential() { recordMenuAction showSubscriptionWireGuardControlledAccessCredential; }
    showSubscriptionWireGuardJoinReceipt() { recordMenuAction showSubscriptionWireGuardJoinReceipt; }
    createSubscriptionWireGuardInviteMenu() { recordMenuAction createSubscriptionWireGuardInviteMenu; }
    importSubscriptionWireGuardMainCredential() { recordMenuAction importSubscriptionWireGuardMainCredential; }
    subscriptionWireGuardImportMainCredentialJson() { recordMenuAction importSubscriptionWireGuardMainCredential; }
    subscriptionWireGuardCredentialDecode() {
        [[ "$1" == "invite-credential" ]] || return 1
        jq -n '{version:1,kind:"invite",invite_id:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",alias:"edge-a",address:"10.77.0.2/24",network:"10.77.0.0/24",main_address:"10.77.0.1/24",endpoint_host:"main.example.com",listen_port:51820,main_public_key:"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",expires_at:1770000000}'
    }
    initSubscriptionWireGuardMain() {
        recordMenuAction initSubscriptionWireGuardMain
        subscriptionWireGuardReadState() {
            jq -n '{enabled:true, role:"main", address:"10.77.0.1/24", peers:[{id:"edge-a"}]}'
        }
    }
    subscriptionWireGuardJoinInvite() {
        recordMenuAction subscriptionWireGuardJoinInvite
        subscriptionWireGuardReadState() {
            jq -n '{enabled:true, role:"controlled", address:"10.77.0.2/24", join_invite_id:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", peers:[{id:"main"}]}'
        }
    }
    showSubscriptionWireGuardPeers() { recordMenuAction showSubscriptionWireGuardPeers; }
    testSubscriptionWireGuardControl() { recordMenuAction testSubscriptionWireGuardControl; }
    restartSubscriptionWireGuardControl() { recordMenuAction restartSubscriptionWireGuardControl; }
    disableSubscriptionWireGuardControl() { recordMenuAction disableSubscriptionWireGuardControl; }
    showSubscriptionWireGuardStatus() { recordMenuAction showSubscriptionWireGuardStatus; }
    subscriptionWireGuardReadState() {
        jq -n '{enabled:false, role:"uninitialized", address:"", peers:[]}'
    }
    setMenuSmokeRole() {
        local role=$1
        case "${role}" in
        main)
            subscriptionWireGuardReadState() {
                jq -n '{enabled:true, role:"main", address:"10.77.0.1/24", peers:[{id:"edge-a"}]}'
            }
            ;;
        controlled)
            subscriptionWireGuardReadState() {
                jq -n '{enabled:true, role:"controlled", address:"10.77.0.2/24", peers:[{id:"main"}]}'
            }
            ;;
        *)
            subscriptionWireGuardReadState() {
                jq -n '{enabled:false, role:"uninitialized", address:"", peers:[]}'
            }
            ;;
        esac
    }
    eval "$(declare -f subscriptionGroupsStateRead | sed '1s/^subscriptionGroupsStateRead/originalSubscriptionGroupsStateRead/')"
    subscriptionWireGuardConfigFile() { echo "${TMP_DIR}/menu-smoke-wireguard/wg-padm.conf"; }
    readNginxSubscribe() { subscribePort=39778; subscribeDomain=main.example.com; subscribeType=https; }
    showAccounts() { recordMenuAction showAccounts; }
    installSubscribe() { recordMenuAction installSubscribe; }
    runSubscriptionGroupSync() { recordMenuAction "runSubscriptionGroupSync:$*"; }
    subscriptionSyncPlan() { recordMenuAction subscriptionSyncPlan; jq -n '{create:[], remove:[]}'; }
    subscriptionRemoteControlHealthAll() { recordMenuAction subscriptionRemoteControlHealthAll; jq -n '[{id:"edge-a", ok:true}]'; }
    subscriptionRemoteSyncPlan() { recordMenuAction subscriptionRemoteSyncPlan; jq -n '[{source_id:"edge-a", status:"success", response:{plan:{create:[], remove:[]}}}]'; }
    subscriptionQuotaDryRunPlan() { recordMenuAction subscriptionQuotaDryRunPlan; printf '[]\n'; }
    showSubscriptionLocalSyncPlan() { recordMenuAction showSubscriptionLocalSyncPlan; subscriptionSyncPlan >/dev/null; }
    showSubscriptionRemoteHealthPlan() { recordMenuAction showSubscriptionRemoteHealthPlan; subscriptionRemoteControlHealthAll >/dev/null; }
    showSubscriptionRemoteSyncPlan() { recordMenuAction showSubscriptionRemoteSyncPlan; subscriptionRemoteSyncPlan >/dev/null; }
    showSubscriptionQuotaPlan() { recordMenuAction showSubscriptionQuotaPlan; subscriptionQuotaDryRunPlan >/dev/null; }
    executeSubscriptionQuotaPlanMenu() { recordMenuAction executeSubscriptionQuotaPlanMenu; }
    setSubscriptionSourceControlTokenMenu() {
        subscriptionRequireMainRole || return 1
        recordMenuAction setSubscriptionSourceControlTokenMenu
    }
    clearSubscriptionSourceSyncErrorMenu() {
        subscriptionRequireMainRole || return 1
        recordMenuAction clearSubscriptionSourceSyncErrorMenu
    }
    showAdminSubscriptionTraffic() { recordMenuAction showAdminSubscriptionTraffic; }
    collectSubscriptionTraffic() { recordMenuAction collectSubscriptionTraffic; return 0; }
    showSubscriptionTrafficOverview() { recordMenuAction showSubscriptionTrafficOverview; }
    showSubscriptionGroupsStateSummary() { recordMenuAction showSubscriptionGroupsStateSummary; }
    createSubscriptionGroupsBackupMenu() { recordMenuAction createSubscriptionGroupsBackupMenu; }
    showSubscriptionGroupsBackups() { recordMenuAction showSubscriptionGroupsBackups; }
    restoreSubscriptionGroupsBackupMenu() { recordMenuAction restoreSubscriptionGroupsBackupMenu; }
    resetSubscriptionGroupsStateMenu() { recordMenuAction resetSubscriptionGroupsStateMenu; }
    refreshSubscriptionGroupSyncCron() { recordMenuAction refreshSubscriptionGroupSyncCron; }
    subscriptionGroupSyncCronStatus() { recordMenuAction subscriptionGroupSyncCronStatus; }
    installUserCrontabContent() { return 0; }
    xrayInstalled() { [[ "${xrayInstalledState}" == "true" ]]; }
    singBoxInstalled() { [[ "${singBoxInstalledState}" == "true" ]]; }
    getSingBoxCurrentVersion() {
        if singBoxInstalled; then
            printf 'v1.0.0\n'
        else
            printf '未安装\n'
        fi
    }
    xrayRunning() { [[ "${xrayRunningState}" == "true" ]]; }
    singBoxRunning() { [[ "${singBoxRunningState}" == "true" ]]; }
    serviceInstalled() { [[ "${serviceInstalledState}" == "true" ]]; }
    serviceRunning() {
        case "$1" in
        xray) [[ "${xrayRunningState}" == "true" ]] ;;
        sing-box) [[ "${singBoxRunningState}" == "true" ]] ;;
        nginx) [[ "${nginxRunningState}" == "true" ]] ;;
        *) return 1 ;;
        esac
    }
    nginxRuntimeReasons() {
        [[ -n "${nginxReasonsMock}" ]] || return 0
        printf '%s\n' "${nginxReasonsMock}"
    }
    runServiceAction() {
        recordMenuAction "runServiceAction:$1:$2"
        [[ "${serviceActionShouldFail}" != "$1:$2" ]]
    }
    upgradeXrayCore() { recordMenuAction "upgradeXrayCore:$*"; }
    upgradeSingBoxCore() { recordMenuAction "upgradeSingBoxCore:$*"; }
    showXrayConfigHealthCheck() {
        recordMenuAction showXrayConfigHealthCheck
        [[ "${checkActionShouldFail}" != "showXrayConfigHealthCheck" ]]
    }
    showXrayCompatibilityAudit() {
        recordMenuAction showXrayCompatibilityAudit
        [[ "${checkActionShouldFail}" != "showXrayCompatibilityAudit" ]]
    }
    checkXrayPrereleaseCompatibility() {
        recordMenuAction checkXrayPrereleaseCompatibility
        [[ "${checkActionShouldFail}" != "checkXrayPrereleaseCompatibility" ]]
    }
    showSingBoxConfigValidation() {
        recordMenuAction showSingBoxConfigValidation
        [[ "${checkActionShouldFail}" != "showSingBoxConfigValidation" ]]
    }
    showSingBoxCompatibilityAudit() {
        recordMenuAction showSingBoxCompatibilityAudit
        [[ "${checkActionShouldFail}" != "showSingBoxCompatibilityAudit" ]]
    }
    checkSingBoxPrereleaseCompatibility() {
        recordMenuAction checkSingBoxPrereleaseCompatibility
        [[ "${checkActionShouldFail}" != "checkSingBoxPrereleaseCompatibility" ]]
    }
    updateGeoSite() { recordMenuAction updateGeoSite; }
    showXrayGeoStatus() { recordMenuAction showXrayGeoStatus; }
    installCronUpdateGeo() { recordMenuAction installCronUpdateGeo; }
    checkLog() { recordMenuAction "checkLog:$*"; }
    singBoxLog() { recordMenuAction "singBoxLog:$*"; }
    checkNginxConfig() { recordMenuAction checkNginxConfig; }
    validateXrayConfigWithBinary() { return 0; }
    singBoxConfigInstalled() { return 1; }
    crontab() { return 1; }
    coreReleaseTags() { recordMenuAction "unexpected-network-version-fetch"; printf 'v1.2.3\n'; }
    downloadXrayReleaseBinaryToTemp() {
        local version=$1
        local outVar=$2
        local tmpDirVar=${3:-}
        local releaseDir="${TMP_DIR}/menu-smoke-xray-release-${version#v}"
        mkdir -p "${releaseDir}" || return 1
        printf '#!/usr/bin/env bash\nexit 0\n' >"${releaseDir}/xray"
        chmod +x "${releaseDir}/xray"
        printf -v "${outVar}" '%s' "${releaseDir}/xray"
        if [[ -n "${tmpDirVar}" ]]; then
            printf -v "${tmpDirVar}" '%s' "${releaseDir}"
        fi
    }
    serviceQueueStart() { recordMenuAction "serviceQueueStart:$*"; }
    serviceQueueStop() { recordMenuAction "serviceQueueStop:$*"; }
    serviceQueueRestart() { recordMenuAction "serviceQueueRestart:$*"; }
    serviceQueueApply() {
        recordMenuAction serviceQueueApply
        [[ "${serviceQueueShouldFail}" == "true" ]] && return 1
        return 0
    }
    subscriptionGroupsStateRead() {
        if [[ "$1" == "-r" ]]; then
            recordMenuAction "subscriptionGroupsStateRead:$*"
        fi
        originalSubscriptionGroupsStateRead "$@"
    }
    local geoOverviewDir="${TMP_DIR}/menu-smoke-xray-geo"
    mkdir -p "${geoOverviewDir}/conf"
    printf '#!/usr/bin/env bash\ncase "$1" in --version) printf "Xray 1.0.0 test\\n" ;; -test) exit 0 ;; *) exit 1 ;; esac\n' >"${geoOverviewDir}/xray"
    chmod +x "${geoOverviewDir}/xray"
    printf 'geoip' >"${geoOverviewDir}/geoip.dat"
    printf 'geosite' >"${geoOverviewDir}/geosite.dat"
    printf 'v20260513' >"${geoOverviewDir}/geo.version"
    output=
    if menuSmokePartSelected core; then
        resetMenuActions
        resetMenuRender
        PADM_XRAY_DIR="${geoOverviewDir}" PADM_XRAY_BINARY="${geoOverviewDir}/xray" PADM_SINGBOX_BINARY="${geoOverviewDir}/missing-sing-box" showCoreStatusOverview
        [[ "${output}" == *"Xray Geo:"*"版本 v20260513"* ]]
        ! assertMenuAction unexpected-network-version-fetch

        xrayInstalledState=false
        singBoxInstalledState=false
        serviceInstalledState=false
        resetMenuActions
        resetMenuRender
        PADM_XRAY_DIR="${TMP_DIR}/missing-xray" \
            PADM_XRAY_BINARY="${TMP_DIR}/missing-xray/xray" \
            PADM_SINGBOX_BINARY="${TMP_DIR}/missing-sing-box" \
            coreVersionManageMenu <<<"6"
        [[ "${menuItems}" == $'Xray-core 生命周期\nsing-box 生命周期\n服务运行态\n日志与诊断\nXray Geo 数据\n返回主菜单\n' ]]
        ! grep -qxF '安装与重装' <<<"${menuItems}"
        ! grep -qF '配置健康与兼容' <<<"${menuItems}"
        ! assertMenuAction unexpected-network-version-fetch
        xrayInstalledState=true
        singBoxInstalledState=true
        serviceInstalledState=true

        resetMenuActions
        resetMenuRender
        local menuSmokePwd=$PWD
        originalCoreMainMenu <<<'6
6'
        cd "${menuSmokePwd}" || return 1
        [[ "$(grep -c '^安装与重装$' <<<"${menuItems}")" == "2" ]]
        ! assertMenuAction unexpected-network-version-fetch

        resetMenuRender
        customSingBoxInstall() { recordMenuAction "customSingBoxInstall:$*"; }
        installMenu <<<"7"
        assertMenuAction menu
        resetMenuActions
        installMenu <<<"4"
        assertMenuAction "customSingBoxInstall:5"
        resetMenuActions
        installMenu <<<"5"
        assertMenuAction selectCoreInstall
        resetMenuActions
        protocolEntryMenu <<<"7"
        assertMenuAction menu
        resetMenuActions
        output=
        local realityMenuNetworkMarker="${TMP_DIR}/menu-smoke-reality-network"
        rm -f "${realityMenuNetworkMarker}"
        resolveRealityTargetIPv4() { : >"${realityMenuNetworkMarker}"; return 1; }
        lookupRealityTargetAsn() { : >"${realityMenuNetworkMarker}"; return 1; }
        currentRealityNetworkProfile() { : >"${realityMenuNetworkMarker}"; return 1; }
        protocolEntryMenu <<<"1
2
9
6
7"
        grep -q "实时查看目标质量" <<<"${output}"
        grep -q "目标 ASN（缓存）" <<<"${output}"
        grep -q "网络关系（缓存）" <<<"${output}"
        [[ "$(grep -cF '重新生成 Reality 参数' <<<"${output}")" == "2" ]]
        [[ ! -e "${realityMenuNetworkMarker}" ]]
        assertMenuAction menu
        if assertMenuAction 'errorCard:选择错误'; then
            printf 'menu-smoke failed: protocol entry reality target flow returned unexpected selection error\n' >&2
            return 1
        fi
    fi

    if menuSmokePartSelected subscription-main-entry; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole uninitialized
        resetMenuActions
        output=
        manageSubscription <<<"4" || true
        assertMenuAction menu
        grep -q "多服务器角色：.*未启用；可直接使用本机订阅" <<<"${output}"
        grep -q "本机单独使用" <<<"${output}"
        grep -q "这台作为主控" <<<"${output}"
        grep -q "这台作为被控" <<<"${output}"
        if grep -q "快速开始" <<<"${output}" || grep -q "发布订阅" <<<"${output}" || grep -q "多服务器协同" <<<"${output}" || grep -q "高级诊断" <<<"${output}"; then
            printf 'menu-smoke failed: uninitialized top-level still shows post-init entries\n' >&2
            return 1
        fi
        resetMenuActions
        output=
        manageSubscriptionRoleSelection <<<"2
n"
        assertMenuAction initSubscriptionWireGuardMain
        assertMenuAction 'statusCard:主控建链已完成'
        if assertMenuAction showSubscriptionWireGuardMainCredential || assertMenuAction createSubscriptionWireGuardInviteMenu; then
            return 1
        fi
        resetMenuActions
        output=
        manageSubscriptionRoleSelection <<<"3
invite-credential"
        assertMenuAction subscriptionWireGuardJoinInvite
        assertMenuAction showSubscriptionWireGuardJoinReceipt
        assertMenuAction showSubscriptionWireGuardStatus
        setMenuSmokeRole main
        resetMenuActions
        output=
        manageSubscription <<<"4"
        grep -q "发布订阅" <<<"${output}"
        grep -q "多服务器协同" <<<"${output}"
        grep -q "主控维护与排障" <<<"${output}"
        if grep -q "我自己用" <<<"${output}" || grep -q "给别人用" <<<"${output}" || grep -q "运行与维护" <<<"${output}" || grep -q "高级诊断" <<<"${output}" || grep -q "被控维护与排障" <<<"${output}"; then
            printf 'menu-smoke failed: main top-level still shows removed or controlled entries\n' >&2
            return 1
        fi
        assertMenuAction menu
    fi

    if menuSmokePartSelected subscription-main-publish-service; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        resetMenuActions
        output=
        manageSubscriptionPublishSubscriptions <<<"7"
        grep -q "安装/更新订阅服务" <<<"${output}"
        grep -q "刷新并查看我的订阅链接" <<<"${output}"
        grep -q "新建并发布订阅" <<<"${output}"
        grep -q "查看并处理已有订阅" <<<"${output}"
        grep -q "查看我的可用服务器" <<<"${output}"
        grep -q "查看我的流量" <<<"${output}"
        if grep -q "同步订阅变更" <<<"${output}" || grep -q "预览同步变更" <<<"${output}"; then
            printf 'menu-smoke failed: publish menu still shows batch sync entries\n' >&2
            return 1
        fi
        resetMenuActions
        manageSubscriptionPublishSubscriptions <<<"1
7"
        assertMenuAction installSubscribe
        assertMenuAction showSubscriptionServiceStatus
        resetMenuActions
        manageSubscriptionPublishSubscriptions <<<"2
7"
        assertMenuAction subscribe
        resetMenuActions
    fi

    if menuSmokePartSelected subscription-main-publish-user || menuSmokePartSelected subscription-main-publish-user-empty; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        resetMenuActions
        manageSubscriptionPublishSubscriptions <<<"4
7" || true
        subscriptionGroupsStateRead -e '.groups[] | select(.id == "default") | ((.user_groups // []) | length) == 0' >/dev/null
    fi

    if menuSmokePartSelected subscription-main-publish-user || menuSmokePartSelected subscription-main-publish-user-create; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        resetMenuActions
        manageSubscriptionPublishSubscriptions <<<"3
demo-user
main
0
7"
        subscriptionGroupsStateRead -e '.groups[] | select(.id == "default") | any(.user_groups[]?; .id == "demo-user" and .name == "demo-user")' >/dev/null
    fi

    if menuSmokePartSelected subscription-main-publish-user || menuSmokePartSelected subscription-main-publish-user-inspect; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        if [[ "${menuSmokePart}" == "subscription-main-publish-user-inspect" ]]; then
            manageSubscriptionPublishSubscriptions <<<"3
demo-user
main
0
7"
        fi
        resetMenuActions
        output=
        manageSubscriptionPublishSubscriptions <<<"4
demo-user
3
9
7"
        grep -q "查看并处理已有订阅" <<<"${output}"
        grep -q "查看当前用量" <<<"${output}"
        resetMenuActions
    fi

    if menuSmokePartSelected subscription-main-publish-sync || menuSmokePartSelected subscription-main-publish-sync-skip; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        resetMenuActions
        subscriptionGroupsStateWrite --arg groupId "default" '.groups |= map(if .id == $groupId then .sync.enabled = false else . end)'
        manageSubscriptionPublishSubscriptions <<<"3
team-a
*
0
n
7"
        subscriptionGroupsStateRead -e '.groups[] | select(.id == "default") | any(.user_groups[]?; .id == "team-a" and .name == "team-a")' >/dev/null
        subscriptionGroupsStateRead -e '.groups[] | select(.id == "default") | .sync.enabled == false' >/dev/null
        if assertMenuAction 'runSubscriptionGroupSync:'; then
            printf 'menu-smoke failed: disabled auto sync still ran a full sync\n' >&2
            return 1
        fi
        assertMenuAction 'statusCard:订阅变更已保存'
    fi

    if menuSmokePartSelected subscription-main-publish-sync || menuSmokePartSelected subscription-main-publish-sync-enable; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        resetMenuActions
        rm -rf "${PADM_SUBSCRIPTION_GROUPS_DIR}"
        ensureSubscriptionGroupsState
        subscriptionGroupsStateWrite --arg groupId "default" '.groups |= map(if .id == $groupId then .sync.enabled = false else . end)'
        manageSubscriptionPublishSubscriptions <<<"3
team-b
main
0

7"
        assertMenuAction refreshSubscriptionGroupSyncCron
        assertMenuAction 'runSubscriptionGroupSync:'
        subscriptionGroupsStateRead -e '.groups[] | select(.id == "default") | .sync.enabled == true' >/dev/null
    fi

    if menuSmokePartSelected subscription-main-maintenance; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        resetMenuActions
        output=
        manageSubscriptionMultiServer <<<"5"
        grep -q "主控建链向导" <<<"${output}"
        grep -q "添加/移除被控服务器" <<<"${output}"
        grep -q "更新被控服务器凭据" <<<"${output}"
        grep -q "查看协同状态" <<<"${output}"
        if grep -q "多服务器细项" <<<"${output}"; then
            printf 'menu-smoke failed: main multi-server still shows advanced submenu\n' >&2
            return 1
        fi
        resetMenuActions
        manageSubscriptionMultiServer <<<"1
n
5"
        assertMenuAction initSubscriptionWireGuardMain
        resetMenuActions
        manageSubscriptionMultiServer <<<"3
5"
        assertMenuAction setSubscriptionSourceControlTokenMenu
        resetMenuActions
        manageSubscriptionMultiServer <<<"4
5"
        if assertMenuAction showSubscriptionWireGuardMainCredential; then
            return 1
        fi
        assertMenuAction showSubscriptionSources
        assertMenuAction showSubscriptionRemoteHealthPlan
        assertMenuAction subscriptionRemoteControlHealthAll
        assertMenuAction showSubscriptionSourceSyncResults
        resetMenuActions
        output=
        manageSubscriptionMainMaintenance <<<"4"
        grep -q "订阅同步" <<<"${output}"
        grep -q "状态备份与恢复" <<<"${output}"
        grep -q "控制面与连接细节" <<<"${output}"
        if grep -q "立即完整同步" <<<"${output}" || grep -q "用量与限额" <<<"${output}" || grep -q "清除同步错误" <<<"${output}"; then
            printf 'menu-smoke failed: main maintenance still duplicates sync actions\n' >&2
            return 1
        fi
        resetMenuActions
        manageSubscriptionMainMaintenance <<<"1
1
6
4"
        assertMenuAction 'runSubscriptionGroupSync:'
        resetMenuActions
        output=
        manageSubscriptionSyncSettings <<<"6"
        grep -q "立即完整同步" <<<"${output}"
        grep -q "开启/关闭自动同步" <<<"${output}"
        grep -q "设置同步间隔" <<<"${output}"
        grep -q "状态与排障" <<<"${output}"
        grep -q "用量与限额" <<<"${output}"
        if grep -q "事件同步" <<<"${output}" || grep -q "开启/关闭远程同步" <<<"${output}"; then
            printf 'menu-smoke failed: unified sync menu still exposes legacy toggles\n' >&2
            return 1
        fi
        resetMenuActions
        manageSubscriptionSyncSettings <<<"4
1
8
6"
        assertMenuAction showSubscriptionGroupsStateSummary
        assertMenuAction showSubscriptionSourceSyncResults
        resetMenuActions
        manageSubscriptionSyncDiagnostics <<<"2
8"
        assertMenuAction showSubscriptionServiceStatus
        resetMenuActions
        manageSubscriptionSyncDiagnostics <<<"3
8"
        assertMenuAction showSubscriptionRemoteHealthPlan
        assertMenuAction subscriptionRemoteControlHealthAll
        resetMenuActions
        manageSubscriptionSyncDiagnostics <<<"4
8"
        assertMenuAction showSubscriptionLocalSyncPlan
        assertMenuAction subscriptionSyncPlan
        resetMenuActions
        manageSubscriptionSyncDiagnostics <<<"5
8"
        assertMenuAction showSubscriptionRemoteSyncPlan
        assertMenuAction subscriptionRemoteSyncPlan
        resetMenuActions
        manageSubscriptionSyncDiagnostics <<<"7
8"
        assertMenuAction clearSubscriptionSourceSyncErrorMenu
        resetMenuActions
        manageTrafficAndQuota <<<"1
9"
        assertMenuAction collectSubscriptionTraffic
        assertMenuAction showSubscriptionTrafficOverview
        resetMenuActions
        manageTrafficAndQuota <<<"6
9"
        assertMenuAction showSubscriptionQuotaPlan
        assertMenuAction subscriptionQuotaDryRunPlan
        resetMenuActions
        manageTrafficAndQuota <<<"7
9"
        assertMenuAction executeSubscriptionQuotaPlanMenu
        resetMenuActions
        manageTrafficAndQuota <<<"8
9"
        assertMenuAction 'successCard:限额自动执行状态已切换'
        subscriptionGroupsStateRead -e '.groups[] | select(.id == "default") | .sync.quota_auto_apply == true' >/dev/null
        resetMenuActions
        manageSubscriptionMainControlDetails <<<"1
7"
        assertMenuAction showSubscriptionWireGuardMainCredential
        for wgAction in "2:showSubscriptionWireGuardPeers" "4:showSubscriptionSourceControlUrls" "5:restartSubscriptionWireGuardControl" "6:disableSubscriptionWireGuardControl"; do
            wgChoice=${wgAction%%:*}
            resetMenuActions
            manageSubscriptionMainControlDetails <<<"${wgChoice}
7"
            assertMenuAction "${wgAction#*:}"
        done
        resetMenuActions
        manageSubscriptionMainControlDetails <<<"3
7"
        assertMenuAction showSubscriptionRemoteHealthPlan
        assertMenuAction subscriptionRemoteControlHealthAll
        resetMenuActions
        manageSubscriptionStateBackups <<<"1
6"
        assertMenuAction showSubscriptionGroupsStateSummary
        resetMenuActions
        manageSubscriptionStateBackups <<<"2
6"
        assertMenuAction createSubscriptionGroupsBackupMenu
        resetMenuActions
        manageSubscriptionStateBackups <<<"3
6"
        assertMenuAction showSubscriptionGroupsBackups
        resetMenuActions
        manageSubscriptionStateBackups <<<"4
6"
        assertMenuAction restoreSubscriptionGroupsBackupMenu
        resetMenuActions
        manageSubscriptionStateBackups <<<"5
6"
        assertMenuAction resetSubscriptionGroupsStateMenu
    fi

    if menuSmokePartSelected subscription-controlled; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole controlled
        resetMenuActions
        output=
        manageSubscription <<<"4"
        grep -q "接入主控" <<<"${output}"
        grep -q "查看本机状态" <<<"${output}"
        grep -q "被控维护与排障" <<<"${output}"
        if grep -q "发布订阅" <<<"${output}" || grep -q "多服务器协同" <<<"${output}" || grep -q "主控维护与排障" <<<"${output}"; then
            printf 'menu-smoke failed: controlled top-level still shows main entries\n' >&2
            return 1
        fi
        assertMenuAction menu
        resetMenuActions
        manageSubscriptionControlledHome <<<"1
invite-credential
y
4"
        assertMenuAction subscriptionWireGuardJoinInvite
        assertMenuAction showSubscriptionWireGuardJoinReceipt
        assertMenuAction showSubscriptionWireGuardStatus
        resetMenuActions
        output=
        manageSubscriptionControlledHome <<<"2
4"
        grep -q "当前服务器角色：" <<<"${output}"
        if assertMenuAction showSubscriptionWireGuardControlledCredential || assertMenuAction showSubscriptionWireGuardJoinReceipt; then
            return 1
        fi
        assertMenuAction showSubscriptionWireGuardStatus
        assertMenuAction showSubscriptionSourceSyncResults
        resetMenuActions
        output=
        manageSubscriptionControlledMaintenance <<<"6"
        grep -q "导入/更新主控接入凭据" <<<"${output}"
        grep -q "显示接入回执/旧版被控凭据" <<<"${output}"
        grep -q "查看控制面与 Peer 细节" <<<"${output}"
        grep -q "重写配置并重启被控控制面" <<<"${output}"
        grep -q "关闭被控控制面" <<<"${output}"
        if grep -q "查看本机主控接入凭据" <<<"${output}" || grep -q "初始化本机为主控" <<<"${output}"; then
            printf 'menu-smoke failed: controlled maintenance still shows main-only actions\n' >&2
            return 1
        fi
        resetMenuActions
        manageSubscriptionControlledMaintenance <<<"1
6"
        assertMenuAction importSubscriptionWireGuardMainCredential
        resetMenuActions
        manageSubscriptionControlledMaintenance <<<"2
6"
        assertMenuAction showSubscriptionWireGuardControlledAccessCredential
        resetMenuActions
        manageSubscriptionControlledMaintenance <<<"3
6"
        assertMenuAction showSubscriptionWireGuardStatus
        assertMenuAction showSubscriptionWireGuardPeers
        resetMenuActions
        manageSubscriptionControlledMaintenance <<<"4
6"
        assertMenuAction restartSubscriptionWireGuardControl
        resetMenuActions
        manageSubscriptionControlledMaintenance <<<"5
6"
        assertMenuAction disableSubscriptionWireGuardControl
        resetMenuActions
        addSubscribeMenu <<<"3" || true
        assertMenuAction 'errorCard:当前机器已初始化为被控'
        resetMenuActions
        setSubscriptionSourceControlTokenMenu <<<"" || true
        assertMenuAction 'errorCard:当前机器已初始化为被控'
        resetMenuActions
        changeSubscriptionSourceEnabledMenu <<<"" || true
        assertMenuAction 'errorCard:当前机器已初始化为被控'
        resetMenuActions
        clearSubscriptionSourceSyncErrorMenu <<<"" || true
        assertMenuAction 'errorCard:当前机器已初始化为被控'
        resetMenuActions
        manageSubscriptionMainHome <<<"4" || true
        assertMenuAction 'errorCard:当前机器已初始化为被控'
        resetMenuActions
        setMenuSmokeRole main
        manageSubscriptionControlledHome <<<"4" || true
        assertMenuAction 'errorCard:当前机器已初始化为主控'
        resetMenuActions
        output=
        manageSubscriptionPublishSubscriptions <<<"7"
        grep -q "安装/更新订阅服务" <<<"${output}"
        resetMenuActions
        output=
        manageSubscriptionPublishSubscriptions <<<"7"
        grep -q "查看并处理已有订阅" <<<"${output}"
        resetMenuActions
        output=
        manageTrafficAndQuota <<<"9"
        grep -q "查看用量总览" <<<"${output}"
        resetMenuActions
        setMenuSmokeRole controlled
        manageTrafficAndQuota <<<"9" || true
        assertMenuAction 'errorCard:当前机器已初始化为被控'
        resetMenuActions
        manageSubscriptionStateBackups <<<"6" || true
        assertMenuAction 'errorCard:当前机器已初始化为被控'
        resetMenuActions
        manageSubscriptionSyncSettings <<<"6" || true
        assertMenuAction 'errorCard:当前机器已初始化为被控'
        resetMenuActions
        setMenuSmokeRole uninitialized
        manageTrafficAndQuota <<<"9"
        [[ -z "${actions}" ]]
        resetMenuActions
        manageSubscriptionStateBackups <<<"6"
        [[ -z "${actions}" ]]
        resetMenuActions
        output=
        manageSubscriptionSyncSettings <<<"6"
        grep -q "立即完整同步" <<<"${output}"
        grep -q "状态与排障" <<<"${output}"
        grep -q "用量与限额" <<<"${output}"
        if grep -q "远端同步计划" <<<"${output}" || grep -q "事件同步" <<<"${output}"; then
            printf 'menu-smoke failed: local sync menu exposes main-only or legacy actions\n' >&2
            return 1
        fi
        [[ -z "${actions}" ]]
    fi

    if menuSmokePartSelected core-maintenance; then
        local expectedLifecycleItems=$'升级稳定版\n升级预发布版\n回退稳定版\n检查当前配置\n扫描升级风险\n试跑预发布版\n返回核心与服务\n'
        local xrayLifecycleItems=

        resetMenuActions
        resetMenuRender
        xrayVersionManageMenu <<<"7"
        xrayLifecycleItems=${menuItems}
        [[ "${xrayLifecycleItems}" == "${expectedLifecycleItems}" ]]
        ! grep -Eq '普通模式|严格模式' <<<"${output}"
        [[ -z "${actions}" ]]

        resetMenuActions
        resetMenuRender
        singBoxVersionManageMenu <<<"7"
        [[ "${menuItems}" == "${xrayLifecycleItems}" ]]
        [[ -z "${actions}" ]]

        resetMenuActions
        resetMenuRender
        xrayVersionManageMenu <<<'4
5
6
7'
        assertMenuAction showXrayConfigHealthCheck
        assertMenuAction showXrayCompatibilityAudit
        assertMenuAction checkXrayPrereleaseCompatibility

        resetMenuActions
        resetMenuRender
        singBoxVersionManageMenu <<<'4
5
6
7'
        assertMenuAction showSingBoxConfigValidation
        assertMenuAction showSingBoxCompatibilityAudit
        assertMenuAction checkSingBoxPrereleaseCompatibility

        checkActionShouldFail=showXrayConfigHealthCheck
        resetMenuActions
        resetMenuRender
        xrayVersionManageMenu <<<'4
7'
        checkActionShouldFail=
        assertMenuAction showXrayConfigHealthCheck
        [[ "$(grep -c '^升级稳定版$' <<<"${menuItems}")" == "2" ]]

        resetMenuActions
        resetMenuRender
        xrayVersionManageMenu <<<'invalid
still-invalid
7'
        [[ "$(grep -cF 'errorCard:输入有误，请重新输入' <<<"${actions}")" == "2" ]]
        [[ "$(grep -c '^升级稳定版$' <<<"${menuItems}")" == "3" ]]
        xrayVersionManageMenu </dev/null

        xrayInstalledState=false
        resetMenuActions
        resetMenuRender
        xrayVersionManageMenu <<<'1
5
6
7'
        ! grep -q '^upgradeXrayCore:' <<<"${actions}"
        assertMenuAction 'statusCard:Xray-core 生命周期'
        assertMenuAction showXrayCompatibilityAudit
        assertMenuAction checkXrayPrereleaseCompatibility
        xrayInstalledState=true

        resetMenuActions
        resetMenuRender
        coreConfigMaintenanceMenu <<<"6"
        [[ "${menuItems}" == $'Xray-core 生命周期\nsing-box 生命周期\n服务运行态\n日志与诊断\nXray Geo 数据\n返回主菜单\n' ]]
        ! assertMenuAction showXrayCompatibilityAudit
        ! assertMenuAction checkXrayPrereleaseCompatibility
        ! assertMenuAction showSingBoxCompatibilityAudit
        ! assertMenuAction checkSingBoxPrereleaseCompatibility
        ! assertMenuAction unexpected-network-version-fetch

        resetMenuActions
        resetMenuRender
        coreServiceControlMenu xray <<<'3
4'
        assertMenuAction 'runServiceAction:xray:restart'

        serviceActionShouldFail=sing-box:restart
        resetMenuActions
        resetMenuRender
        coreServiceControlMenu sing-box <<<'3
4'
        serviceActionShouldFail=
        assertMenuAction 'runServiceAction:sing-box:restart'
        assertMenuAction 'errorCard:sing-box 服务重启失败'
        [[ "$(grep -c '^启动$' <<<"${menuItems}")" == "2" ]]

        resetMenuActions
        resetMenuRender
        coreServiceControlMenu xray <<<'2

4'
        assertMenuAction 'statusCard:已取消'
        ! assertMenuAction 'runServiceAction:xray:stop'

        nginxReasonsMock=
        resetMenuActions
        resetMenuRender
        coreAllServicesMenu <<<'3
4'
        assertMenuAction 'statusCard:Nginx 服务'
        ! grep -q '^runServiceAction:nginx:' <<<"${actions}"

        nginxReasonsMock="订阅发布"
        nginxRunningState=false
        resetMenuActions
        resetMenuRender
        coreServiceControlMenu nginx <<<'4
5'
        assertMenuAction 'statusCard:Nginx reload'
        ! assertMenuAction 'runServiceAction:nginx:reload'
        grep -q '^reload（不可用）$' <<<"${menuItems}"

        nginxRunningState=true
        resetMenuActions
        resetMenuRender
        coreServiceControlMenu nginx <<<'4
5'
        assertMenuAction 'runServiceAction:nginx:reload'

        resetMenuActions
        resetMenuRender
        coreLogsMenu <<<'4
5'
        assertMenuAction checkNginxConfig

        resetMenuActions
        resetMenuRender
        xrayGeoDataMenu <<<'1
2
3
4'
        assertMenuAction updateGeoSite
        assertMenuAction showXrayGeoStatus
        assertMenuAction installCronUpdateGeo
        [[ "$(grep -c '^更新 Xray Geo 数据$' <<<"${menuItems}")" == "4" ]]
    fi

    configPath="${oldConfigPath}"
    coreInstallType="${oldCoreInstallType}"
    if [[ -n "${oldRealityPageSize}" ]]; then
        REALITY_TARGET_PAGE_SIZE="${oldRealityPageSize}"
    else
        unset REALITY_TARGET_PAGE_SIZE
    fi
}
