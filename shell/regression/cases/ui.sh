#!/usr/bin/env bash

runSubscriptionWireGuardMenuFlowRegression() (
    local wireGuardMenuPart="${1:-all}"
    local parentTmpDir="${TMP_DIR}"
    local TMP_DIR="${parentTmpDir}/wireguard-menu-flow-${BASHPID:-$$}"
    local PADM_SUBSCRIPTION_GROUPS_DIR="${TMP_DIR}/subscribe_groups"
    local oldWireGuardDir="${PADM_WIREGUARD_CONTROL_DIR:-}"
    local oldCurrentHost="${currentHost:-}"
    local oldNginxConfigPath="${nginxConfigPath:-}"
    local PADM_WIREGUARD_NGINX_SYSTEMD_DROPIN_FILE="${TMP_DIR}/menu-smoke-nginx/10-padm-wg.conf"
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
    local sourceStateWriteShouldFail='' remoteApplyShouldFail=''
    local stopShouldFail=
    local stopAllowMissingBackend=
    local actions= healthCallCount=0

    # Restore the real subscription functions because earlier UI smoke tests
    # define menu stubs with global Bash function scope.
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/core/state.sh"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/subscription/groups.sh"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/subscription/control.sh"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/subscription/wireguard_control.sh"
    subscriptionWireGuardNginxSystemdDaemonReload() { return 0; }
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
        IFS= read -r readValue || {
            printf -v "${targetVar}" '%s' ""
            return 1
        }
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
    eval "$(declare -f subscriptionWireGuardReadState | sed '1s/^subscriptionWireGuardReadState/originalSubscriptionWireGuardReadState/')"
    # Menu transaction cases share validation coverage with the bootstrap leaf;
    # keep reads parse-only so Windows does not spawn jq validators repeatedly.
    subscriptionWireGuardReadState() {
        local stateFile
        stateFile=$(subscriptionWireGuardStateFile) || return 1
        if [[ ! -f "${stateFile}" ]]; then
            originalSubscriptionWireGuardReadState
            return
        fi
        jq -e -c '.' "${stateFile}"
    }
    subscriptionGroupsStateRead() {
        jq "$@" "$(subscriptionGroupsFile)"
    }
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
    eval "$(declare -f setSubscriptionSourceEnabled | sed '1s/^setSubscriptionSourceEnabled/originalSetSubscriptionSourceEnabled/')"
    addSubscriptionSourceState() {
        [[ "${addSourceShouldFail}" == "true" ]] && return 1
        originalAddSubscriptionSourceState "$@"
    }
    setSubscriptionSourceCredential() {
        [[ "${setCredentialShouldFail}" == "true" ]] && return 1
        originalSetSubscriptionSourceCredential "$@"
    }
    setSubscriptionSourceEnabled() {
        [[ "${sourceStateWriteShouldFail}" == "true" ]] && return 1
        originalSetSubscriptionSourceEnabled "$@"
    }
    subscriptionRemoteApplyDesiredUsersForSource() {
        local sourceId
        sourceId=$(jq -r '.id' <<<"$1") || return 1
        recordMenuAction "subscriptionRemoteApplyDesiredUsersForSource:${sourceId}:$(jq -c . <<<"$2")"
        if [[ "${remoteApplyShouldFail}" == "true" ]]; then
            SUBSCRIPTION_REMOTE_SOURCE_ERROR="模拟远端用户同步失败"
            return 1
        fi
    }
    subscriptionRemoteControlHealthAll() { printf '[{"id":"edge-a","ok":true}]\n'; }
    subscriptionRemoteControlHealth() { healthCallCount=$((healthCallCount + 1)); printf '{"ok":true}\n'; }
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
        sourceStateWriteShouldFail=
        remoteApplyShouldFail=
        stopShouldFail=
        stopAllowMissingBackend=
        healthCallCount=0
        actions=
        rm -rf "${PADM_WIREGUARD_CONTROL_DIR}" "${PADM_SUBSCRIPTION_GROUPS_DIR}"
        mkdir -p "${nginxConfigPath}"
        ensureSubscriptionGroupsState
    }

    wireGuardMenuInitializeMain() {
        wireGuardMenuResetFixture
        resetMenuActions
        manageSubscriptionLocalHome <<<"7
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
        local itemChoices=${1:-8}
        resetMenuActions
        if subscriptionWireGuardCreateInvite main reservedInvite >/dev/null 2>&1; then
            return 1
        fi
        assertMenuAction 'errorCard:main 是保留源 ID，不能作为被控服务器别名'
        subscriptionWireGuardReadState | jq -e 'any(.peers[]?; .id == "main") | not' >/dev/null
        wireGuardMenuCreateReceiptJson edge-a "${controlledPublicKey}" "${controlledToken}" receiptJson
        receiptCredential=$(subscriptionWireGuardCredentialEncode receipt "$(jq -c 'del(.version,.kind)' <<<"${receiptJson}")")
        resetMenuActions
        manageSubscriptionServers <<<"2
${receiptCredential}
${itemChoices}
6"
        [[ "${healthCallCount}" == "0" ]]
        assertMenuAction 'runSubscriptionGroupSync:'
        subscriptionWireGuardReadState | jq -e --arg publicKey "${controlledPublicKey}" '.peers[] | select(.id == "edge-a" and .address == "10.77.0.2/24" and .public_key == $publicKey and .endpoint == "")' >/dev/null
        subscriptionGroupsStateRead -e --arg token "${controlledToken}" '.sources[] | select(.id == "edge-a" and .scheme == "wireguard" and .transport == "wireguard" and .host == "10.77.0.2" and .port == 39778 and .control_token == $token)' >/dev/null
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
        (
            local healthLog="${TMP_DIR}/completed-peer-health.log"
            local sourceSelectCount=0
            : >"${healthLog}"
            subscriptionRemoteControlHealth() {
                jq -r '.id' <<<"$1" >>"${healthLog}"
                printf '{"ok":true}\n'
            }
            selectSubscriptionSourceId() { sourceSelectCount=$((sourceSelectCount + 1)); return 99; }
            wireGuardMenuAddEdgePeer $'3\n8'
            [[ "${sourceSelectCount}" == "0" && "$(<"${healthLog}")" == edge-a ]]
            [[ "$(grep -cxF 'runSubscriptionGroupSync:' <<<"${actions}")" == "1" ]]
        )

        resetMenuActions
        setSubscriptionSourceControlTokenMenu <<<"${updatedCredential}
edge-a"
        assertMenuAction 'runSubscriptionGroupSync:'
        subscriptionWireGuardReadState | jq -e --arg publicKey "${updatedPublicKey}" '.peers[] | select(.id == "edge-a" and .address == "10.77.0.3/24" and .public_key == $publicKey and .endpoint == "")' >/dev/null
        subscriptionGroupsStateRead -e '.sources[] | select(.id == "edge-a" and .host == "10.77.0.3" and .port == 48779 and .control_token == "token-b")' >/dev/null
        (
            local expectedSource expectedPeer credentialJson sourceChange currentState currentGroups
            local baselineState baselineGroups
            baselineState=$(subscriptionWireGuardReadState)
            baselineGroups=$(subscriptionGroupsStateRead -c '.')
            expectedSource=$(subscriptionActiveGroupRead -c 'first(.sources[] | select(.id == "edge-a"))')
            expectedPeer=$(subscriptionWireGuardReadState | jq -c 'first(.peers[] | select(.id == "edge-a") | {id,address,public_key})')
            credentialJson=$(subscriptionWireGuardCredentialDecode "${updatedCredential}")
            for sourceChange in '.control_token = "rotated-token"' '.enabled = false'; do
                (
                    subscriptionActiveGroupWrite ".sources |= map(if .id == \"edge-a\" then ${sourceChange} else . end)"
                    currentState=$(subscriptionWireGuardReadState)
                    currentGroups=$(subscriptionGroupsStateRead -c '.')
                    resetMenuActions
                    regressionExpectStatus 1 setSubscriptionRemoteSourceEnabled edge-a false "${expectedSource}"
                    regressionExpectStatus 1 subscriptionWireGuardUpdatePeerAndCredential edge-a "${credentialJson}" "${expectedSource}" "${expectedPeer}"
                    regressionExpectStatus 1 subscriptionWireGuardRemovePeerAndSource edge-a "${expectedSource}" "${expectedPeer}"
                    [[ "${SUBSCRIPTION_WIREGUARD_SOURCE_REMOVE_ERROR}" == "state" ]]
                    [[ "$(subscriptionWireGuardReadState)" == "${currentState}" && "$(subscriptionGroupsStateRead -c '.')" == "${currentGroups}" ]]
                    ! grep -q '^subscriptionRemoteApplyDesiredUsersForSource:' <<<"${actions}"
                    ! assertMenuAction applySubscriptionWireGuardService
                    subscriptionGroupsStateWrite --argjson baseline "${baselineGroups}" '$baseline'
                )
            done
            subscriptionWireGuardWriteState --arg publicKey "${failingPublicKey}" \
                '.peers |= map(if .id == "edge-a" then .public_key = $publicKey else . end)'
            currentState=$(subscriptionWireGuardReadState)
            currentGroups=$(subscriptionGroupsStateRead -c '.')
            resetMenuActions
            regressionExpectStatus 1 subscriptionWireGuardUpdatePeerAndCredential edge-a "${credentialJson}" "${expectedSource}" "${expectedPeer}"
            regressionExpectStatus 1 subscriptionWireGuardRemovePeerAndSource edge-a "${expectedSource}" "${expectedPeer}"
            [[ "${SUBSCRIPTION_WIREGUARD_SOURCE_REMOVE_ERROR}" == "state" ]]
            regressionExpectStatus 1 subscriptionWireGuardRemovePeerAndSourceLocalOnly edge-a "${expectedSource}" "${expectedPeer}"
            [[ "${SUBSCRIPTION_WIREGUARD_SOURCE_REMOVE_ERROR}" == "state" ]]
            [[ "$(subscriptionWireGuardReadState)" == "${currentState}" && "$(subscriptionGroupsStateRead -c '.')" == "${currentGroups}" ]]
            ! grep -q '^subscriptionRemoteApplyDesiredUsersForSource:' <<<"${actions}"
            ! assertMenuAction applySubscriptionWireGuardService
            subscriptionWireGuardWriteState --argjson baseline "${baselineState}" '$baseline'
            subscriptionGroupsStateWrite --argjson baseline "${baselineGroups}" '$baseline'
        )
        (
            local expectedSource expectedPeer credentialJson baselineGroups
            baselineGroups=$(subscriptionGroupsStateRead -c '.')
            expectedSource=$(subscriptionActiveGroupRead -c 'first(.sources[] | select(.id == "edge-a"))')
            expectedPeer=$(subscriptionWireGuardReadState | jq -c 'first(.peers[] | select(.id == "edge-a") | {id,address,public_key})')
            credentialJson=$(subscriptionWireGuardCredentialDecode "${updatedCredential}")
            subscriptionActiveGroupWrite '
              .sources |= map(if .id == "edge-a" then .sync_status = "failed" | .sync_failure_count = 2 else . end) |
              .traffic.sources["edge-a"] = {upload:50,download:20}
            '
            resetMenuActions
            setSubscriptionRemoteSourceEnabled edge-a true "${expectedSource}"
            subscriptionWireGuardUpdatePeerAndCredential edge-a "${credentialJson}" "${expectedSource}" "${expectedPeer}"
            assertMenuAction applySubscriptionWireGuardService
            ! grep -q '^subscriptionRemoteApplyDesiredUsersForSource:' <<<"${actions}"
            subscriptionGroupsStateWrite --argjson baseline "${baselineGroups}" '$baseline'
        )
        (
            local explicitId= expectedSource expectedPeer baselineGroups
            local updateCount=0 sourceSelectCount=0
            baselineGroups=$(subscriptionGroupsStateRead -c '.')
            addSubscriptionSourceState edge-b "Edge B" 10.77.0.9 48779
            subscriptionActiveGroupWrite '
              .sources |= map(if .id == "edge-a" then .host = "10.77.0.2"
                elif .id == "edge-b" then .host = "10.77.0.3" else . end)
            '
            expectedSource=$(subscriptionActiveGroupRead -c 'first(.sources[] | select(.id == "edge-a"))')
            expectedPeer=$(subscriptionWireGuardReadState | jq -c 'first(.peers[] | select(.id == "edge-a") | {id,address,public_key})')
            subscriptionWireGuardUpdatePeerAndCredential() { explicitId=$1; updateCount=$((updateCount + 1)); }
            selectSubscriptionSourceId() { sourceSelectCount=$((sourceSelectCount + 1)); return 99; }
            resetMenuActions
            setSubscriptionSourceControlTokenMenu edge-a "${expectedSource}" "${expectedPeer}" <<<"invalid
$(subscriptionWireGuardCredentialEncode receipt "$(jq -cn --arg key "${controlledPublicKey}" --arg token "${controlledToken}" \
    '{invite_id:("a"*64),public_key:$key,control_port:39778,token:$token}')")
${updatedCredential}"
            [[ "${explicitId}" == "edge-a" && "${updateCount}" == "1" && "${sourceSelectCount}" == "0" ]]
            assertMenuAction 'errorCard:被控接入凭据无效，请复制完整内容后重试'
            assertMenuAction 'errorCard:请粘贴被控接入凭据'
            assertMenuAction 'runSubscriptionGroupSync:'
            [[ "$(grep -cxF 'runSubscriptionGroupSync:' <<<"${actions}")" == "1" ]]
            regressionExpectStatus 1 setSubscriptionSourceControlTokenMenu edge-a "${expectedSource}" "${expectedPeer}" <<<""
            regressionExpectStatus 1 setSubscriptionSourceControlTokenMenu edge-a "${expectedSource}" "${expectedPeer}" </dev/null
            regressionExpectStatus 1 setSubscriptionSourceControlTokenMenu edge-a "${expectedSource}" "${expectedPeer}" < <(printf '%s' "${updatedCredential}")
            [[ "${updateCount}" == "1" && "${sourceSelectCount}" == "0" ]]
            subscriptionGroupsStateWrite --argjson baseline "${baselineGroups}" '$baseline'
        )
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
        if subscriptionGroupsStateRead -e 'any(.sources[]?; .id == "edge-fail")' >/dev/null 2>&1; then
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
        if subscriptionGroupsStateRead -e 'any(.sources[]?; .id == "edge-addfail")' >/dev/null 2>&1; then
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
        if subscriptionGroupsStateRead -e 'any(.sources[]?; .id == "edge-setfail")' >/dev/null 2>&1; then
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
        subscriptionGroupsStateRead -e 'any(.sources[]?; .id == "edge-groups-restore-fail")' >/dev/null
        if subscriptionWireGuardReadState | jq -e 'any(.peers[]?; .id == "edge-groups-restore-fail")' >/dev/null 2>&1; then
            return 1
        fi
    fi

    if wireGuardMenuPartSelected peer-source-control || wireGuardMenuPartSelected peer-source-control-toggle || wireGuardMenuPartSelected peer-source-control-status; then
        wireGuardMenuInitializeMain
        wireGuardMenuAddEdgePeer

        if wireGuardMenuPartSelected peer-source-control || wireGuardMenuPartSelected peer-source-control-toggle; then
            resetMenuActions
            resetMenuActions
            changeSubscriptionSourceEnabledMenu <<<"edge-a
y"
            subscriptionGroupsStateRead -e '.sources[] | select(.id == "edge-a" and .enabled == false)' >/dev/null
            assertMenuAction 'subscriptionRemoteApplyDesiredUsersForSource:edge-a:{"edge-a":[]}'
            assertMenuAction 'runSubscriptionGroupSync:'
            resetMenuActions
            changeSubscriptionSourceEnabledMenu <<<"edge-a
y"
            subscriptionGroupsStateRead -e '.sources[] | select(.id == "edge-a" and .enabled == true)' >/dev/null
            if assertMenuAction 'subscriptionRemoteApplyDesiredUsersForSource:edge-a:{"edge-a":[]}'; then
                return 1
            fi
            assertMenuAction 'runSubscriptionGroupSync:'

            sourceStateWriteShouldFail=true
            resetMenuActions
            if changeSubscriptionSourceEnabledMenu <<<"edge-a
y"; then
                sourceStateWriteShouldFail=
                return 1
            fi
            sourceStateWriteShouldFail=
            subscriptionGroupsStateRead -e '.sources[] | select(.id == "edge-a" and .enabled == true)' >/dev/null
            [[ "$(grep -c '^subscriptionRemoteApplyDesiredUsersForSource:edge-a:' <<<"${actions}")" == "2" ]]

            remoteApplyShouldFail=true
            resetMenuActions
            if changeSubscriptionSourceEnabledMenu <<<"edge-a
y"; then
                remoteApplyShouldFail=
                return 1
            fi
            remoteApplyShouldFail=
            subscriptionGroupsStateRead -e '.sources[] | select(.id == "edge-a" and .enabled == true)' >/dev/null
            assertMenuAction 'errorCard:模拟远端用户同步失败'
        fi

        if wireGuardMenuPartSelected peer-source-control || wireGuardMenuPartSelected peer-source-control-status; then
            resetMenuActions
            local multiServerStatusOutput
            multiServerStatusOutput=$(showSubscriptionSources; showSubscriptionRemoteHealthPlan)
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
        manageSubscriptionMainControlDetails <<<"3
4
5"
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

runSubscriptionWireGuardInviteCreateRegression() (
    local root="${TMP_DIR}/wireguard-invite-create" mainPublicKey
    local processLog="${root}/invite-processes.log" credential decoded invalid field
    local allocationState allocationGroups allocationPending
    local -a processes=()
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/subscription/control.sh"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/subscription/groups.sh"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/subscription/wireguard_control.sh"
    PADM_SUBSCRIPTION_GROUPS_DIR="${root}/file-groups"
    PADM_WIREGUARD_CONTROL_DIR="${root}/file-wireguard"
    mkdir -p "${PADM_SUBSCRIPTION_GROUPS_DIR}" "${PADM_WIREGUARD_CONTROL_DIR}"
    mainPublicKey=$(printf '0123456789abcdefghijklmnopqrstuv' | base64 -w 0)
    writeDefaultSubscriptionGroupsState "$(subscriptionGroupsFile)"
    command jq -cn --arg publicKey "${mainPublicKey}" \
        '{enabled:true,role:"main",interface:"wg-padm",network:"10.77.0.0/24",listen_port:51820,control_port:39778,firewall_owned:false,address:"10.77.0.1/24",endpoint_host:"main.example.com",public_key:$publicKey,peers:[]}' \
        >"$(subscriptionWireGuardStateFile)"
    jq() { printf '%s\n' "${FUNCNAME[1]}" >>"${processLog}"; command jq "$@"; }
    : >"${processLog}"
    subscriptionWireGuardCreateInvite b credential
    mapfile -t processes <"${processLog}"
    ((${#processes[@]} <= 30)) || { printf 'invite-create: expected <=30 jq calls, got %s\n' "${#processes[@]}" >&2; return 1; }
    decoded=$(subscriptionWireGuardCredentialDecode "${credential}")
    jq -e '.alias == "b" and .address == "10.77.0.2/24"' <<<"${decoded}" >/dev/null
    subscriptionWireGuardReadState | jq -e '.pending_invites | length == 1' >/dev/null
    (
        local kind payload kindCredential wrongCredential credentialJson=stale readErrors=
        local mainCredential invalidCredential
        errorCard() { readErrors+="$1"$'\n'; }
        mainCredential=$(subscriptionWireGuardCredentialEncode main "$(jq -c \
            '{endpoint_host,listen_port,network,address:.main_address,public_key:.main_public_key}' <<<"${decoded}")")
        invalidCredential=$(subscriptionWireGuardCredentialEncode invite "$(jq -c '.alias = ""' <<<"${decoded}")")
        for kind in invite main controlled receipt; do
            case "${kind}" in
            invite) kindCredential=${credential}; wrongCredential=${mainCredential} ;;
            main) kindCredential=${mainCredential}; wrongCredential=${credential} ;;
            controlled)
                payload=$(jq -c '{address,public_key:.main_public_key,control_port:39778,token:("A"*64)}' <<<"${decoded}")
                kindCredential=$(subscriptionWireGuardCredentialEncode controlled "${payload}")
                wrongCredential=${credential}
                ;;
            receipt)
                payload=$(jq -c '{invite_id,public_key:.main_public_key,control_port:39778,token:("A"*64)}' <<<"${decoded}")
                kindCredential=$(subscriptionWireGuardCredentialEncode receipt "${payload}")
                wrongCredential=${credential}
                ;;
            esac
            readErrors=
            subscriptionWireGuardReadCredential "${kind}" "测试凭据" credentialJson <<<"${invalidCredential}
${wrongCredential}
${kindCredential}"
            jq -e --arg kind "${kind}" '.kind == $kind' <<<"${credentialJson}" >/dev/null
            [[ "${readErrors}" == $'测试凭据无效，请复制完整内容后重试\n请粘贴测试凭据\n' ]]
        done
        readErrors=
        credentialJson=stale
        regressionExpectStatus 1 subscriptionWireGuardReadCredential invite "主控邀请" credentialJson <<<""
        [[ -z "${credentialJson}" ]]
        credentialJson=stale
        regressionExpectStatus 1 subscriptionWireGuardReadCredential invite "主控邀请" credentialJson </dev/null
        [[ -z "${credentialJson}" ]]
        credentialJson=stale
        regressionExpectStatus 1 subscriptionWireGuardReadCredential invite "主控邀请" credentialJson < <(printf '%s' "${credential}")
        [[ -z "${credentialJson}" && -z "${readErrors}" ]]
    )

    : >"${processLog}"
    subscriptionWireGuardValidateInviteCredentialJson "${decoded}"
    mapfile -t processes <"${processLog}"
    ((${#processes[@]} == 1))
    for field in invite_id alias address network main_address endpoint_host main_public_key; do
        invalid=$(jq -c --arg field "${field}" '.[$field] += "\nignored"' <<<"${decoded}")
        regressionExpectStatus 1 subscriptionWireGuardValidateInviteCredentialJson "${invalid}"
        invalid=$(jq -c --arg field "${field}" '.[$field] = ""' <<<"${decoded}")
        regressionExpectStatus 1 subscriptionWireGuardValidateInviteCredentialJson "${invalid}"
    done
    for invalid in \
        "$(jq -c '.listen_port = 1.5' <<<"${decoded}")" \
        "$(jq -c '.expires_at = "tomorrow"' <<<"${decoded}")" \
        "$(jq -c '.address = .main_address' <<<"${decoded}")" \
        "{} ${decoded}" "${decoded} {}"; do
        regressionExpectStatus 1 subscriptionWireGuardValidateInviteCredentialJson "${invalid}"
    done

    allocationState='{"network":"10.77.0.0/24","address":"10.77.0.1/24","peers":[{"address":"10.77.0.2/32"}],"pending_invites":[{"address":"10.77.0.5/24"}]}'
    allocationGroups='{"sources":[{"role":"secondary","host":"10.77.0.3"},{"role":"secondary","host":"edge.example.com"}]}'
    allocationPending='[{"address":"10.77.0.4/24"}]'
    : >"${processLog}"
    [[ "$(subscriptionWireGuardAllocateInviteAddress "${allocationState}" "${allocationGroups}" "${allocationPending}")" == "10.77.0.5/24" ]]
    mapfile -t processes <"${processLog}"
    ((${#processes[@]} == 1))
    allocationPending=$(jq -cn '[range(2;255) | {address:("10.77.0.\(.)/24")}]')
    regressionExpectStatus 1 subscriptionWireGuardAllocateInviteAddress "${allocationState}" "${allocationGroups}" "${allocationPending}"
)

runSubscriptionWireGuardInviteReceiptRegression() (
    runSubscriptionWireGuardInviteCreateRegression
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
    local inviteCredentialA inviteCredentialB inviteCredentialC cancelInviteCredential joinCredential
    local inviteJsonA inviteJsonB inviteJsonC cancelInviteJson joinJson receiptJson receiptCredential controlledCredentialJson completedAlias
    local stateBefore groupsBefore pendingJson readSecretValue= secretOutput staleInviteId
    local credentialStatusLog="${root}/credential-status.log"
    local testWireGuardState testWireGuardStateValidated=false testGroupsState
    local remoteApplyLog="${root}/remote-apply.log"

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
    statusCard() { printf '%s\n' "$@" >>"${credentialStatusLog}"; }
    successCard() { return 0; }
    warnCard() { return 0; }
    subscriptionRemoteApplyDesiredUsersForSource() {
        printf '%s\t%s\n' "$(jq -r '.id' <<<"$1")" "$(jq -c . <<<"$2")" >>"${remoteApplyLog}"
    }
    subscriptionWireGuardConfigFile() { printf '%s\n' "${wireGuardConfig}"; }
    subscriptionWireGuardStateFile() { printf '%s\n' "${stateMarker}"; }
    subscriptionWireGuardReadState() {
        if [[ "${testWireGuardStateValidated}" != true ]]; then
            subscriptionWireGuardValidateState "${testWireGuardState}" || return 1
        fi
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
        testWireGuardStateValidated=true
        printf '%s\n' "${testWireGuardState}" >"${stateMarker}"
    }
    normalizeTestGroupsState() {
        jq -c '
          if (.groups | type) == "array" and (.groups | length) == 1 then
            .groups[0] as $group |
            {version:6, id:$group.id, name:$group.name, sources:$group.sources,
             user_groups:$group.user_groups, sync:$group.sync,
             traffic:{admin:{sources:(($group.traffic.admin.sources // {}))},
                      user_groups:(($group.traffic.user_groups // {}) | with_entries(.value={sources:(.value.sources // {})})),
                      sources:($group.traffic.sources // {})}}
          else . end
        ' <<<"${testGroupsState}"
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
    testGroupsState=$(normalizeTestGroupsState)
    testWireGuardState=$(jq -cn --arg publicKey "${mainPublicKey}" '{enabled:true,role:"main",interface:"wg-padm",network:"10.77.0.0/24",listen_port:51820,control_port:39778,firewall_owned:false,address:"10.77.0.1/24",endpoint_host:"main.example.com",public_key:$publicKey,peers:[]}')
    subscriptionWireGuardValidateState "${testWireGuardState}" || return 1
    testWireGuardStateValidated=true
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
    pendingJson=$(subscriptionWireGuardListPendingInvites true)
    jq -e --arg inviteId "$(jq -r '.invite_id' <<<"${inviteJsonA}")" \
        'length == 2 and any(.[]; .alias == "hk-1" and .invite_id == $inviteId)' <<<"${pendingJson}" >/dev/null
    (
        local oldInvite newInvite oldInviteId newInviteJson errorText=
        local stateWrites=0 groupWrites=0 drains=0 applies=0
        local stateMarker="${root}/stale-cancel-state.json" wireGuardConfig="${root}/stale-cancel-wg.conf"
        subscriptionWireGuardCreateInvite stale-cancel oldInvite
        oldInviteId=$(subscriptionWireGuardCredentialDecode "${oldInvite}" | jq -r '.invite_id')
        subscriptionWireGuardCancelInvite stale-cancel
        subscriptionWireGuardCreateInvite stale-cancel newInvite
        newInviteJson=$(subscriptionWireGuardCredentialDecode "${newInvite}")
        subscriptionWireGuardWriteState --arg address "$(jq -r '.address' <<<"${newInviteJson}")" \
            --arg key "${controlledPublicKeyC}" \
            '.peers += [{id:"stale-cancel",name:"stale-cancel",address:$address,public_key:$key,endpoint:"",enabled:true}]'
        addSubscriptionSourceState stale-cancel stale-cancel \
            "$(subscriptionWireGuardAddressHost "$(jq -r '.address' <<<"${newInviteJson}")")" 39778
        stateBefore=$(subscriptionWireGuardReadState)
        groupsBefore=$(subscriptionGroupsStateRead -c '.')
        eval "$(declare -f subscriptionWireGuardWriteState | sed '1s/^subscriptionWireGuardWriteState/originalStaleCancelStateWrite/')"
        eval "$(declare -f subscriptionGroupsStateWrite | sed '1s/^subscriptionGroupsStateWrite/originalStaleCancelGroupsWrite/')"
        subscriptionWireGuardWriteState() { stateWrites=$((stateWrites + 1)); originalStaleCancelStateWrite "$@"; }
        subscriptionGroupsStateWrite() { groupWrites=$((groupWrites + 1)); originalStaleCancelGroupsWrite "$@"; }
        subscriptionRemoteDrainSource() { drains=$((drains + 1)); return 99; }
        applySubscriptionWireGuardService() { applies=$((applies + 1)); return 99; }
        errorCard() { errorText=$1; }
        regressionExpectStatus 1 subscriptionWireGuardCancelInvite stale-cancel "${oldInviteId}"
        [[ "${errorText}" == "待完成邀请已变化，请刷新后重试" &&
            "${stateWrites}" == "0" && "${groupWrites}" == "0" && "${drains}" == "0" && "${applies}" == "0" ]]
        [[ "$(subscriptionWireGuardReadState)" == "${stateBefore}" &&
            "$(subscriptionGroupsStateRead -c '.')" == "${groupsBefore}" ]]
        jq -e --arg oldId "${oldInviteId}" 'any(.pending_invites[]; .alias == "stale-cancel" and .invite_id != $oldId) and
            any(.peers[]; .id == "stale-cancel")' <<<"${stateBefore}" >/dev/null
    )

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
    subscriptionGroupsStateRead -e --arg token "${receiptToken}" '.sources[] | select(.id == "hk-2" and .host == "10.77.0.3" and .control_token == $token)' >/dev/null
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
    subscriptionGroupsStateRead -e '.sources[] | select(.id == "hk-3" and .control_token != "")' >/dev/null

    subscriptionWireGuardCreateInvite cancel-edge cancelInviteCredential
    cancelInviteJson=$(subscriptionWireGuardCredentialDecode "${cancelInviteCredential}")
    addSubscriptionSourceState cancel-edge cancel-edge "$(subscriptionWireGuardAddressHost "$(jq -r '.address' <<<"${cancelInviteJson}")")" 39778
    : >"${remoteApplyLog}"
    subscriptionWireGuardCancelInvite cancel-edge
    subscriptionGroupsStateRead -e 'any(.sources[]?; .id == "cancel-edge") | not' >/dev/null
    subscriptionWireGuardReadState | jq -e 'any(.pending_invites[]?; .alias == "cancel-edge") | not' >/dev/null
    [[ "$(wc -l <"${remoteApplyLog}" | tr -d ' ')" == "1" ]]

    stateBefore=$(subscriptionWireGuardReadState)
    groupsBefore=$(subscriptionGroupsStateRead -c '.')
    : >"${remoteApplyLog}"
    applyFailNext=true
    if subscriptionWireGuardRemovePeerAndSource hk-2 >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(subscriptionWireGuardReadState)" == "${stateBefore}" ]]
    [[ "$(subscriptionGroupsStateRead -c '.')" == "${groupsBefore}" ]]
    [[ "$(wc -l <"${remoteApplyLog}" | tr -d ' ')" == "2" ]]
    : >"${remoteApplyLog}"
    subscriptionWireGuardRemovePeerAndSource hk-2
    subscriptionWireGuardReadState | jq -e 'any(.peers[]?; .id == "hk-2") | not' >/dev/null
    subscriptionGroupsStateRead -e 'any(.sources[]?; .id == "hk-2") | not' >/dev/null
    [[ "$(wc -l <"${remoteApplyLog}" | tr -d ' ')" == "1" ]]

    stateBefore=$(subscriptionWireGuardReadState)
    staleInviteId=$(printf '%064x' 100)
    subscriptionWireGuardWriteState --arg inviteId "${staleInviteId}" --argjson expiresAt "$((testNow - 1))" '.network = "10.77.0.0/16" | .address = "10.77.0.1/16" | .pending_invites = [{invite_id:$inviteId,alias:"expired-edge",address:"10.77.0.4/24",expires_at:$expiresAt}]'
    if subscriptionWireGuardCreateInvite unsupported inviteCredentialA >/dev/null 2>&1; then
        return 1
    fi
    subscriptionWireGuardReadState | jq -e '(.pending_invites | length) == 0' >/dev/null
    testWireGuardState=${stateBefore}
    testWireGuardStateValidated=true
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
    testGroupsState=$(normalizeTestGroupsState)
    subscriptionWireGuardValidateState "${testWireGuardState}" || return 1
    testWireGuardStateValidated=true
    printf '%s\n' "${testWireGuardState}" >"${stateMarker}"
    subscriptionWireGuardJoinInvite "${joinJson}" false
    subscriptionWireGuardReadState | jq -e --arg inviteId "$(jq -r '.invite_id' <<<"${joinJson}")" '.role == "controlled" and .address == $address and .join_invite_id == $inviteId and (.peers | length) == 1 and .peers[0].id == "main"' --arg address "$(jq -r '.address' <<<"${joinJson}")" >/dev/null
    subscriptionWireGuardJoinReceiptCredential receiptCredential
    subscriptionWireGuardCredentialDecode "${receiptCredential}" | jq -e --arg inviteId "$(jq -r '.invite_id' <<<"${joinJson}")" --arg token "${receiptToken}" '.kind == "receipt" and .invite_id == $inviteId and .token == $token' >/dev/null
    : >"${credentialStatusLog}"
    showSubscriptionWireGuardControlledAccessCredential
    grep -qx '本机被控接入凭据' "${credentialStatusLog}"
    ! grep -qx '被控接入回执' "${credentialStatusLog}"
    controlledCredential=$(sed -n '2s/^被控接入凭据：//p' "${credentialStatusLog}")
    controlledCredentialJson=$(subscriptionWireGuardCredentialDecode "${controlledCredential}")
    jq -e --arg address "$(jq -r '.address' <<<"${testWireGuardState}")" --arg publicKey "$(jq -r '.public_key' <<<"${testWireGuardState}")" --arg token "${receiptToken}" \
        '.kind == "controlled" and .address == $address and .public_key == $publicKey and .control_port == 39778 and .token == $token' \
        <<<"${controlledCredentialJson}" >/dev/null
    stateBefore=$(subscriptionWireGuardReadState)
    subscriptionWireGuardWriteState --arg publicKey "${controlledPublicKeyB}" '.peers += [{id:"main",name:"重复主控",address:"10.77.0.9/24",public_key:$publicKey,endpoint:"backup.example.com:51820",enabled:true}]'
    if subscriptionWireGuardJoinReceiptCredential receiptCredential >/dev/null 2>&1; then
        return 1
    fi
    testWireGuardState=${stateBefore}
    testWireGuardStateValidated=true
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

    : >"${helperLog}"
    subscriptionWireGuardRestoreStateAndGroupsOrReport() { printf 'local\n' >>"${helperLog}"; return 1; }
    subscriptionRemoteRestoreSourceUsersIfEnabled() { printf 'remote\n' >>"${helperLog}"; return 0; }
    regressionExpectStatus 1 subscriptionWireGuardRestoreSourceMutationOrReport '{}' '{}' '{"enabled":true}' '{"edge":[]}' "来源删除失败"
    [[ "$(<"${helperLog}")" == $'local\nremote' ]]
)

runCoreSelectionRetryActionRegression() (
    local actions=
    local -a expectedCounts=(
        'shell/core/menu.sh|0'
        'shell/core/cores.sh|0'
        'shell/core/routing_access_control.sh|0'
        'shell/core/manage.sh|0'
        'shell/core/fail2ban.sh|0'
        'shell/core/entry_helpers.sh|0'
        'shell/core/routing_bt.sh|0'
        'shell/core/routing_socks.sh|0'
        'shell/core/protocol_runtime.sh|0'
        'shell/core/routing_ipv6.sh|0'
    )
    local -a expectedPatterns=()
    local -a removedPatterns=(
        'shell/core/cores.sh|coreSelectionRetryAction selectCoreInstall'
        'shell/core/routing_access_control.sh|coreSelectionErrorCard; removeAccessControlMenu; return'
        'shell/core/manage.sh|coreSelectionRetryAction manageVlessEncryptionExperiment'
        'shell/core/manage.sh|coreSelectionRetryAction checkBTPanel'
        'shell/core/manage.sh|coreSelectionErrorCard; manageXHTTPPresets'
        'shell/core/manage.sh|coreSelectionRetryAction manageTuic'
        'shell/core/fail2ban.sh|coreSelectionRetryAction manageFail2ban'
        'shell/core/entry_helpers.sh|coreSelectionRetryAction bbrInstall'
        'shell/core/routing_socks.sh|coreSelectionRetryAction socks5Routing'
        'shell/core/routing_ipv6.sh|coreSelectionRetryAction ipv6Routing'
        'shell/core/menu.sh|coreSelectionRetryAction routingAccessMenu'
        'shell/core/menu.sh|coreSelectionRetryAction protocolEntryMenu'
        'shell/core/menu.sh|coreSelectionRetryAction siteCertificateMenu'
        'shell/core/menu.sh|coreSelectionRetryAction systemScriptMenu'
        'shell/core/menu.sh|coreSelectionRetryAction advancedDangerMenu'
        'shell/core/menu.sh|coreSelectionRetryAction installMenu'
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
        file=${entry%%|*}
        pattern=${entry#*|}
        grep -qF "${pattern}" "${PROJECT_ROOT}/${file}"
    done
    for entry in "${removedPatterns[@]}"; do
        file=${entry%%|*}
        pattern=${entry#*|}
        ! grep -qF -- "${pattern}" "${PROJECT_ROOT}/${file}"
    done
)

runMenuSmokeRegression() {
    local actions=
    local output= menuItems= menuNumbers=
    local mainMenuShowStatusCount=0 mainMenuWgetCount=0
    local mainMenuMkdirCount=0 mainMenuAliasCount=0 mainMenuStatusArgs=
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
        menuNumbers=
    }
    eval "$(declare -f menu | sed '1s/^menu /originalCoreMainMenu /')"
    eval "$(declare -f manageSubscriptionPendingInvites | sed '1s/^manageSubscriptionPendingInvites /originalManageSubscriptionPendingInvites /')"
    eval "$(declare -f addOtherSubscribe | sed '1s/^addOtherSubscribe /originalMenuSmokeAddOtherSubscribe /')"
    eval "$(declare -f createSubscriptionWireGuardInviteMenu | sed '1s/^createSubscriptionWireGuardInviteMenu /originalMenuSmokeCreateInvite /')"
    eval "$(declare -f importSubscriptionWireGuardMainCredential | sed '1s/^importSubscriptionWireGuardMainCredential /originalMenuSmokeImportMainCredential /')"
    eval "$(declare -f subscriptionWireGuardCredentialDecode | sed '1s/^subscriptionWireGuardCredentialDecode /originalMenuSmokeCredentialDecode /')"
    eval "$(declare -f changeSubscriptionSourceEnabledMenu | sed '1s/^changeSubscriptionSourceEnabledMenu /originalChangeSubscriptionSourceEnabledMenu /')"
    eval "$(declare -f removeSubscriptionControlledServerMenu | sed '1s/^removeSubscriptionControlledServerMenu /originalRemoveSubscriptionControlledServerMenu /')"
    eval "$(declare -f showXrayGeoStatus | sed '1s/^showXrayGeoStatus /originalMenuShowXrayGeoStatus /')"
    menu() { recordMenuAction menu; }
    uiStyle() { printf '%s' "$2"; }
    menuLine() { output+="$*"$'\n'; }
    menuMutedLine() { output+="$*"$'\n'; }
    menuSection() { output+="$*"$'\n'; }
    menuItem() { output+="$2 ${3:-}"$'\n'; menuItems+="$2"$'\n'; menuNumbers+="$1"$'\n'; }
    menuDangerItem() { output+="$2 ${3:-}"$'\n'; menuItems+="$2"$'\n'; menuNumbers+="$1"$'\n'; }
    menuClose() { return 0; }
    menuRecommendedItem() { output+="$2 ${3:-}"$'\n'; menuItems+="$2"$'\n'; menuNumbers+="$1"$'\n'; }
    menuReturnItem() { output+="$2 ${3:-}"$'\n'; menuItems+="$2"$'\n'; menuNumbers+="$1:return"$'\n'; }
    statusCard() { recordMenuAction "statusCard:$1"; }
    warnCard() { recordMenuAction "warnCard:$1"; }
    errorCard() { recordMenuAction "errorCard:$1"; }
    successCard() { recordMenuAction "successCard:$1"; }
    if menuSmokePartSelected core; then
        local cardFn cardArg expectedAction
        while IFS='|' read -r cardFn cardArg expectedAction; do
            [[ -n "${cardFn}" ]] || continue
            if [[ -n "${cardArg}" ]]; then
                "${cardFn}" "${cardArg}"
            else
                "${cardFn}"
            fi
            assertMenuAction "${expectedAction}"
            resetMenuActions
        done <<'EOF'
coreSelectionErrorCard||errorCard:选择错误，请重新选择
coreInvalidInputErrorCard||errorCard:输入有误，请重新输入
coreCancelledStatusCard|操作未执行|statusCard:已取消
coreRuleExistsStatusCard|example.com 已存在，跳过|statusCard:规则已存在
corePortInputErrorCard||errorCard:端口输入错误
aloneNginxConfigRecoveredErrorCard||errorCard:Nginx 配置检测失败，已恢复旧 alone.conf
nginxStartFailureCard|请查看下方日志|statusCard:Nginx 启动失败
coreNotInstalledErrorCard||errorCard:未安装，请使用脚本安装
coreDomainRequiredErrorCard||errorCard:域名不可为空
coreIPRequiredErrorCard||errorCard:IP不可为空
xrayConfigValidationFailureCard|已取消启动|statusCard:Xray 配置校验失败
xrayPrereleaseCompatibilityCard|通过|statusCard:Xray 预发布版试跑
singBoxPrereleaseCompatibilityCard|通过|statusCard:sing-box 预发布版试跑
xrayConfigValidationCard|通过|statusCard:Xray 当前配置检查
singBoxConfigValidationCard|通过|statusCard:sing-box 当前配置检查
skipTlsCertificateStatusCard|检测到宝塔面板/1Panel|statusCard:跳过 TLS 证书
protocolPortInputStatusCard|端口不合法|statusCard:端口输入
protocolPortHoppingRangeStatusCard|范围不合法|statusCard:端口跳跃范围
protocolPortHoppingStatusCard|删除成功|statusCard:端口跳跃
tuicAlgorithmStatusCard|cubic|statusCard:Tuic 算法
tlsCertificateCard|重新生成证书|statusCard:TLS 证书
tlsCertificateStatusCard|未检测到本机 TLS 证书|statusCard:TLS 证书状态
EOF
    fi
    progressCard() { return 0; }
    showInstallStatus() {
        mainMenuShowStatusCount=$((mainMenuShowStatusCount + 1))
        mainMenuStatusArgs+="${1:-none}"$'\n'
    }
    checkWgetShowProgress() { mainMenuWgetCount=$((mainMenuWgetCount + 1)); return 0; }
    mkdirTools() { mainMenuMkdirCount=$((mainMenuMkdirCount + 1)); return 0; }
    aliasInstall() { mainMenuAliasCount=$((mainMenuAliasCount + 1)); return 0; }
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
    showSubscriptionWireGuardMainCredential() { recordMenuAction showSubscriptionWireGuardMainCredential; }
    showSubscriptionWireGuardControlledCredential() { recordMenuAction showSubscriptionWireGuardControlledCredential; }
    showSubscriptionWireGuardControlledAccessCredential() { recordMenuAction showSubscriptionWireGuardControlledAccessCredential; }
    showSubscriptionWireGuardJoinReceipt() { recordMenuAction showSubscriptionWireGuardJoinReceipt; }
    createSubscriptionWireGuardInviteMenu() { recordMenuAction createSubscriptionWireGuardInviteMenu; }
    addOtherSubscribe() { recordMenuAction addOtherSubscribe; }
    manageSubscriptionPendingInvites() { recordMenuAction manageSubscriptionPendingInvites; }
    removeSubscriptionControlledServerMenu() {
        subscriptionRequireMainRole || return 1
        recordMenuAction removeSubscriptionControlledServerMenu
    }
    changeSubscriptionSourceEnabledMenu() {
        subscriptionRequireMainRole || return 1
        recordMenuAction changeSubscriptionSourceEnabledMenu
    }
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
    showPublishedSubscriptionLinks() { recordMenuAction "showPublishedSubscriptionLinks:$*"; }
    installSubscribe() { recordMenuAction installSubscribe; }
    runSubscriptionGroupSync() {
        recordMenuAction "runSubscriptionGroupSync:$*"
        SUBSCRIPTION_SYNC_PUBLISHED=true
    }
    subscriptionSyncPlan() { recordMenuAction subscriptionSyncPlan; jq -n '{create:[], remove:[]}'; }
    subscriptionRemoteControlHealthAll() { recordMenuAction subscriptionRemoteControlHealthAll; jq -n '[{id:"edge-a", ok:true}]'; }
    subscriptionRemoteSyncPlan() { recordMenuAction subscriptionRemoteSyncPlan; jq -n '[{source_id:"edge-a", status:"success", response:{plan:{create:[], remove:[]}}}]'; }
    subscriptionQuotaDryRunPlan() { recordMenuAction subscriptionQuotaDryRunPlan; printf '[]\n'; }
    showSubscriptionLocalSyncPlan() { recordMenuAction showSubscriptionLocalSyncPlan; subscriptionSyncPlan >/dev/null; }
    showSubscriptionRemoteHealthPlan() { recordMenuAction showSubscriptionRemoteHealthPlan; subscriptionRemoteControlHealthAll >/dev/null; }
    showSubscriptionRemoteSyncPlan() { recordMenuAction showSubscriptionRemoteSyncPlan; subscriptionRemoteSyncPlan >/dev/null; }
    executeSubscriptionQuotaPlanMenu() { recordMenuAction executeSubscriptionQuotaPlanMenu; }
    setSubscriptionSourceControlTokenMenu() {
        subscriptionRequireMainRole || return 1
        recordMenuAction setSubscriptionSourceControlTokenMenu
    }
    showAdminSubscriptionTraffic() { recordMenuAction showAdminSubscriptionTraffic; }
    collectSubscriptionTraffic() { recordMenuAction collectSubscriptionTraffic; return 0; }
    showSubscriptionTrafficOverview() { recordMenuAction showSubscriptionTrafficOverview; }
    showSubscriptionGroupsStateSummary() { recordMenuAction showSubscriptionGroupsStateSummary; }
    createSubscriptionGroupsBackupMenu() { recordMenuAction createSubscriptionGroupsBackupMenu; }
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
    mkdir -p "${geoOverviewDir}/bin" "${geoOverviewDir}/settings/conf"
    printf '#!/usr/bin/env bash\ncase "$1" in --version) printf "Xray 1.0.0 test\\n" ;; -test) exit 0 ;; *) exit 1 ;; esac\n' >"${geoOverviewDir}/bin/xray"
    chmod +x "${geoOverviewDir}/bin/xray"
    printf 'geoip' >"${geoOverviewDir}/bin/geoip.dat"
    printf 'geosite' >"${geoOverviewDir}/bin/geosite.dat"
    printf 'v20260513' >"${geoOverviewDir}/bin/geo.version"
    output=
    if menuSmokePartSelected core; then
        resetMenuActions
        resetMenuRender
        PADM_XRAY_CONF_DIR="${geoOverviewDir}/settings/conf" PADM_XRAY_BINARY="${geoOverviewDir}/bin/xray" PADM_SINGBOX_BINARY="${geoOverviewDir}/missing-sing-box" showCoreStatusOverview
        [[ "${output}" == *"Xray Geo:"*"版本 v20260513"* ]]
        [[ "${output}" == *"sing-box 用户统计能力: 无法检查"* ]]
        ! assertMenuAction unexpected-network-version-fetch
        (
            statusCard() { printf '%s\n' "$*"; }
            local geoStatusOutput
            geoStatusOutput=$(PADM_XRAY_CONF_DIR="${geoOverviewDir}/settings/conf" PADM_XRAY_BINARY="${geoOverviewDir}/bin/xray" originalMenuShowXrayGeoStatus)
            [[ "${geoStatusOutput}" == *"geoip.dat：已安装"*"geosite.dat：已安装"*"版本 v20260513"* ]]
        )

        (
            local apiCapability
            singBoxV2rayApiCapability() { printf '%s\n' "${apiCapability}"; }
            for apiCapability in supported unsupported unknown; do
                resetMenuRender
                showCoreStatusOverview
                case "${apiCapability}" in
                supported) [[ "${output}" == *"sing-box 用户统计能力: 支持"* ]] ;;
                unsupported) [[ "${output}" == *"sing-box 用户统计能力: 不支持，需升级统计版"* ]] ;;
                unknown) [[ "${output}" == *"sing-box 用户统计能力: 无法检查"* ]] ;;
                esac
            done
            ! assertMenuAction unexpected-network-version-fetch
        )

        (
            local serviceProbeLog="${TMP_DIR}/core-status-service-probes.log"
            serviceInstalled() {
                printf 'installed:%s\n' "$1" >>"${serviceProbeLog}"
                [[ "${serviceInstalledState}" == "true" ]]
            }
            serviceRunning() {
                printf 'running:%s\n' "$1" >>"${serviceProbeLog}"
                case "$1" in
                xray) [[ "${xrayRunningState}" == "true" ]] ;;
                sing-box) [[ "${singBoxRunningState}" == "true" ]] ;;
                nginx) [[ "${nginxRunningState}" == "true" ]] ;;
                *) return 1 ;;
                esac
            }
            nginxReasonsMock=
            : >"${serviceProbeLog}"
            showCoreStatusOverview
            [[ "$(grep -c '^installed:nginx$' "${serviceProbeLog}")" == "1" ]]
            [[ "$(grep -c '^running:nginx$' "${serviceProbeLog}")" == "1" ]]
        )

        (
            local routingToolsRenderLog="${TMP_DIR}/routing-tools-render.log"
            echoContent() { printf '%s\n' "$*" >>"${routingToolsRenderLog}"; }
            routingAccessMenu() { recordMenuAction routingAccessMenu; }
            : >"${routingToolsRenderLog}"
            resetMenuActions
            routingToolsMenu <<<"6"
            ! assertMenuAction routingAccessMenu
            [[ "$(wc -l <"${routingToolsRenderLog}")" == "1" ]]
            : >"${routingToolsRenderLog}"
            resetMenuActions
            routingToolsMenu <<< $'bad\n6'
            assertMenuAction 'errorCard:选择错误'
            [[ "$(wc -l <"${routingToolsRenderLog}")" == "2" ]]
            ! assertMenuAction routingAccessMenu

            warpRoutingMenu() {
                recordMenuAction warpRoutingMenu
                IFS= read -r _
            }
            : >"${routingToolsRenderLog}"
            resetMenuActions
            routingToolsMenu <<< $'1\n6'
            assertMenuAction warpRoutingMenu
            [[ "$(wc -l <"${routingToolsRenderLog}")" == "2" ]]

            singBoxConfigPath=/tmp/menu-smoke-sing-box/
            sniRouting() { recordMenuAction sniRouting; }
            : >"${routingToolsRenderLog}"
            resetMenuActions
            routingToolsMenu <<< $'5\n6'
            assertMenuAction sniRouting
            ! assertMenuAction 'errorCard:此功能不支持Hysteria2、Tuic'
            [[ "$(wc -l <"${routingToolsRenderLog}")" == "2" ]]
        )

        (
            local routingAccessRenderLog="${TMP_DIR}/routing-access-render.log"
            echoContent() { printf '%s\n' "$*" >>"${routingAccessRenderLog}"; }
            routingToolsMenu() { recordMenuAction routingToolsMenu; }
            btTools() { recordMenuAction btTools; }
            accessControlMenu() { recordMenuAction accessControlMenu; }
            : >"${routingAccessRenderLog}"
            resetMenuActions
            routingAccessMenu <<< $'bad\n4'
            assertMenuAction 'errorCard:选择错误'
            ! assertMenuAction routingToolsMenu
            ! assertMenuAction btTools
            ! assertMenuAction accessControlMenu
            [[ "$(wc -l <"${routingAccessRenderLog}")" == "2" ]]

            routingToolsMenu() {
                recordMenuAction routingToolsMenu
                IFS= read -r _
            }
            : >"${routingAccessRenderLog}"
            resetMenuActions
            routingAccessMenu <<< $'1\n6\n4'
            assertMenuAction routingToolsMenu
            [[ "$(wc -l <"${routingAccessRenderLog}")" == "2" ]]
        )

        (
            local routingMenuRenderLog="${TMP_DIR}/routing-child-render.log"
            configPath="${TMP_DIR}/menu-smoke-routing-config/"
            setUnlockDNS() { recordMenuAction setUnlockDNS; }
            removeUnlockDNS() { recordMenuAction removeUnlockDNS; }
            setUnlockSNI() { recordMenuAction setUnlockSNI; }
            removeUnlockSNI() { recordMenuAction removeUnlockSNI; }
            routingToolsMenu() { recordMenuAction routingToolsMenu; }
            echoContent() { printf '%s\n' "$*" >>"${routingMenuRenderLog}"; }
            : >"${routingMenuRenderLog}"
            resetMenuActions
            dnsRouting <<< $'bad\n3'
            assertMenuAction 'errorCard:选择错误'
            ! assertMenuAction routingToolsMenu
            [[ "$(wc -l <"${routingMenuRenderLog}")" == "2" ]]
            (
                configPath=
                singBoxConfigPath=/tmp/menu-smoke-sing-box/
                coreNotInstalledErrorCard() { recordMenuAction coreNotInstalledErrorCard; }
                resetMenuActions
                dnsRouting <<< $'1\n3'
                assertMenuAction setUnlockDNS
                ! assertMenuAction coreNotInstalledErrorCard
                resetMenuActions
                sniRouting <<< $'1\n3'
                assertMenuAction setUnlockSNI
                ! assertMenuAction coreNotInstalledErrorCard
            )
            : >"${routingMenuRenderLog}"
            resetMenuActions
            sniRouting <<< $'bad\n3'
            assertMenuAction 'errorCard:选择错误'
            ! assertMenuAction routingToolsMenu
            [[ "$(wc -l <"${routingMenuRenderLog}")" == "2" ]]
            : >"${routingMenuRenderLog}"
            resetMenuActions
            warpRoutingReg() { recordMenuAction "warpRoutingReg:$*"; }
            warpRoutingMenu <<< $'bad\n3'
            assertMenuAction 'errorCard:选择错误'
            ! assertMenuAction routingToolsMenu
            [[ "$(wc -l <"${routingMenuRenderLog}")" == "2" ]]

            (
                coreInstallType=1
                singBoxConfigPath=
                readInstallType() { :; }
                hasIPv6Connectivity() { return 0; }
                routingAccessMenu() { recordMenuAction routingAccessMenu; }
                : >"${routingMenuRenderLog}"
                resetMenuActions
                btTools <<< $'bad\n4'
                assertMenuAction 'errorCard:选择错误'
                ! assertMenuAction routingAccessMenu
                [[ "$(wc -l <"${routingMenuRenderLog}")" == "2" ]]

                : >"${routingMenuRenderLog}"
                resetMenuActions
                ipv6Routing <<< $'bad\n5'
                assertMenuAction 'errorCard:选择错误'
                ! assertMenuAction routingAccessMenu
                [[ "$(wc -l <"${routingMenuRenderLog}")" == "2" ]]

                (
                    local connectivityAvailable=false ipv6Choice domainList=keep.example
                    hasIPv6Connectivity() {
                        recordMenuAction hasIPv6Connectivity
                        [[ "${connectivityAvailable}" == true ]]
                    }
                    showIPv6Routing() { recordMenuAction showIPv6Routing; }
                    routingConfigApplyTransaction() { recordMenuAction "ipv6-transaction:$4:${5:-}"; }
                    warnCard() { recordMenuAction "warnCard:$*"; }
                    for ipv6Choice in 1 4 5; do
                        resetMenuActions
                        ipv6Routing <<<"${ipv6Choice}" || return 1
                        ! assertMenuAction hasIPv6Connectivity || return 1
                        case "${ipv6Choice}" in
                        1) assertMenuAction showIPv6Routing || return 1 ;;
                        4) assertMenuAction 'ipv6-transaction:removeIPv6RoutingConfig:' || return 1 ;;
                        5) [[ -z "${actions}" ]] || return 1 ;;
                        esac
                    done
                    resetMenuActions
                    regressionExpectStatus 1 ipv6Routing <<<"2" || return 1
                    assertMenuAction hasIPv6Connectivity || return 1
                    ! grep -q '^ipv6-transaction:' <<<"${actions}" || return 1
                    resetMenuActions
                    regressionExpectStatus 1 ipv6Routing <<< $'3\ny' || return 1
                    assertMenuAction hasIPv6Connectivity || return 1
                    assertMenuAction 'warnCard:会删除所有设置的分流规则 会删除 IPv6 之外的所有出站规则' || return 1
                    ! grep -q '^ipv6-transaction:' <<<"${actions}" || return 1
                    resetMenuActions
                    ipv6Routing <<< $'3\nn' || return 1
                    ! assertMenuAction hasIPv6Connectivity || return 1
                    ! grep -q '^ipv6-transaction:' <<<"${actions}" || return 1
                    connectivityAvailable=true
                    autoRead() { IFS= read -r "$3"; }
                    resetMenuActions
                    ipv6Routing < <(printf '2\nmust-not-write.example') || return 1
                    ! grep -q '^ipv6-transaction:' <<<"${actions}" || return 1
                    [[ "${domainList}" == keep.example ]] || return 1
                    resetMenuActions
                    ipv6Routing <<< $'2\nexample.com' || return 1
                    assertMenuAction 'ipv6-transaction:addIPv6RoutingConfig:example.com' || return 1
                    [[ "${domainList}" == keep.example ]] || return 1
                    resetMenuActions
                    ipv6Routing <<< $'3\ny' || return 1
                    assertMenuAction 'ipv6-transaction:setIPv6GlobalRoutingConfig:' || return 1
                ) || return 1
            )
        )

        (
            local socksMenuRenderLog="${TMP_DIR}/socks-menu-render.log"
            local oldCoreInstallType="${coreInstallType:-}"
            coreInstallType=1
            : >"${socksMenuRenderLog}"
            echoContent() { printf '%s\n' "$*" >>"${socksMenuRenderLog}"; }

            (
                routingToolsMenu() { recordMenuAction routingToolsMenu; }
                socks5OutboundRoutingMenu() { recordMenuAction socks5OutboundRoutingMenu; }
                socks5InboundRoutingMenu() { recordMenuAction socks5InboundRoutingMenu; }
                removeSocks5Routing() { recordMenuAction removeSocks5Routing; }
                resetMenuActions
                socks5Routing <<< $'bad\n4'
                assertMenuAction 'errorCard:选择错误'
                ! assertMenuAction routingToolsMenu
                [[ "$(wc -l <"${socksMenuRenderLog}")" == "2" ]]
            )

            (
                readInstallType() { :; }
                socks5Routing() { recordMenuAction socks5Routing; }
                resetMenuActions
                socks5InboundRoutingMenu <<< $'bad\n5'
                assertMenuAction 'errorCard:选择错误'
                ! assertMenuAction socks5Routing
                [[ "$(wc -l <"${socksMenuRenderLog}")" == "4" ]]
            )

            (
                socks5Routing() { recordMenuAction socks5Routing; }
                resetMenuActions
                socks5OutboundRoutingMenu <<< $'bad\n5'
                assertMenuAction 'errorCard:选择错误'
                ! assertMenuAction socks5Routing
                [[ "$(wc -l <"${socksMenuRenderLog}")" == "6" ]]
            )

            (
                socks5Routing() { recordMenuAction socks5Routing; }
                resetMenuActions
                removeSocks5Routing <<< $'bad\n4'
                assertMenuAction 'errorCard:选择错误'
                ! assertMenuAction socks5Routing
                [[ "$(wc -l <"${socksMenuRenderLog}")" == "8" ]]
            )
            coreInstallType="${oldCoreInstallType}"
        )

        (
            local accessMenuRenderLog="${TMP_DIR}/access-menu-render.log"
            local oldConfigPath="${configPath:-}"
            configPath="${TMP_DIR}/menu-smoke-access-config/"
            : >"${accessMenuRenderLog}"
            echoContent() { printf '%s\n' "$*" >>"${accessMenuRenderLog}"; }
            routingAccessMenu() { recordMenuAction routingAccessMenu; }
            eval "$(declare -f accessControlMenu | sed '1s/^accessControlMenu /originalAccessControlMenu /')"
            accessControlMenu() { recordMenuAction accessControlMenu; }

            (
                resetMenuActions
                originalAccessControlMenu <<< $'bad\n7'
                assertMenuAction 'errorCard:选择错误'
                ! assertMenuAction routingAccessMenu
                [[ "$(wc -l <"${accessMenuRenderLog}")" == "2" ]]
            )

            (
                resetMenuActions
                manageRegionalBlockPolicy <<< $'bad\n4'
                assertMenuAction 'errorCard:选择错误'
                ! assertMenuAction accessControlMenu
                [[ "$(wc -l <"${accessMenuRenderLog}")" == "4" ]]
            )

            (
                resetMenuActions
                removeAccessControlMenu <<< $'bad\n6'
                assertMenuAction 'errorCard:选择错误'
                ! assertMenuAction accessControlMenu
                [[ "$(wc -l <"${accessMenuRenderLog}")" == "6" ]]
            )
            configPath="${oldConfigPath}"
        )

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
        mainMenuShowStatusCount=0
        mainMenuWgetCount=0
        mainMenuMkdirCount=0
        mainMenuAliasCount=0
        mainMenuStatusArgs=
        PADM_INSTALL_STATUS_READY=1
        local menuSmokePwd=$PWD
        originalCoreMainMenu <<<'6
6'
        cd "${menuSmokePwd}" || return 1
        [[ "$(grep -c '^安装与重装$' <<<"${menuItems}")" == "2" ]]
        [[ "${mainMenuShowStatusCount}" == "2" ]]
        [[ "${mainMenuWgetCount}" == "1" ]]
        [[ "${mainMenuMkdirCount}" == "1" ]]
        [[ "${mainMenuAliasCount}" == "1" ]]
        [[ "${mainMenuStatusArgs}" == $'cached\nnone\n' ]]
        ! assertMenuAction unexpected-network-version-fetch

        resetMenuRender
        customSingBoxInstall() { recordMenuAction "customSingBoxInstall:$*"; }
        installMenu <<<"7"
        ! assertMenuAction menu
        resetMenuActions
        installMenu <<<"4"
        assertMenuAction "customSingBoxInstall:5"
        resetMenuActions
        installMenu <<<"5"
        assertMenuAction selectCoreInstall
        resetMenuActions
        protocolEntryMenu <<<"7"
        ! assertMenuAction menu
        (
            local protocolMenuRenderLog="${TMP_DIR}/protocol-menu-render.log"
            echoContent() { printf '%s\n' "$*" >>"${protocolMenuRenderLog}"; }
            manageReality() { recordMenuAction manageReality; }
            manageXHTTP() { recordMenuAction manageXHTTP; }
            manageHysteria() { recordMenuAction manageHysteria; }
            manageTuic() { recordMenuAction manageTuic; }
            addCorePort() { recordMenuAction addCorePort; }
            manageCDN() { recordMenuAction manageCDN; }
            : >"${protocolMenuRenderLog}"
            resetMenuActions
            protocolEntryMenu <<< $'bad\n7'
            assertMenuAction 'errorCard:选择错误'
            ! assertMenuAction manageReality
            ! assertMenuAction manageXHTTP
            ! assertMenuAction manageHysteria
            ! assertMenuAction manageTuic
            ! assertMenuAction addCorePort
            ! assertMenuAction manageCDN
            [[ "$(wc -l <"${protocolMenuRenderLog}")" == "2" ]]
        )
        (
            local siteMenuRenderLog="${TMP_DIR}/site-menu-render.log"
            echoContent() { printf '%s\n' "$*" >>"${siteMenuRenderLog}"; }
            manageTraditionalTlsFallback() { recordMenuAction manageTraditionalTlsFallback; }
            manageTLSCertificates() { recordMenuAction manageTLSCertificates; }
            : >"${siteMenuRenderLog}"
            resetMenuActions
            siteCertificateMenu <<< $'bad\n3'
            assertMenuAction 'errorCard:选择错误'
            ! assertMenuAction manageTraditionalTlsFallback
            ! assertMenuAction manageTLSCertificates
            [[ "$(wc -l <"${siteMenuRenderLog}")" == "2" ]]
        )
        resetMenuActions
        output=
        local realityMenuNetworkMarker="${TMP_DIR}/menu-smoke-reality-network"
        rm -f "${realityMenuNetworkMarker}"
        resolveRealityTargetIPv4() { : >"${realityMenuNetworkMarker}"; return 1; }
        lookupRealityTargetAsn() { : >"${realityMenuNetworkMarker}"; return 1; }
        currentRealityNetworkProfile() { : >"${realityMenuNetworkMarker}"; return 1; }
        protocolEntryMenu <<<"1
2
10
6
7"
        grep -q "检测当前目标" <<<"${output}"
        grep -q "目标 ASN（缓存）" <<<"${output}"
        grep -q "网络关系（缓存）" <<<"${output}"
        [[ "$(grep -cF '重新生成 Reality 参数' <<<"${output}")" == "2" ]]
        [[ ! -e "${realityMenuNetworkMarker}" ]]
        ! assertMenuAction menu
        if assertMenuAction 'errorCard:选择错误'; then
            printf 'menu-smoke failed: protocol entry reality target flow returned unexpected selection error\n' >&2
            return 1
        fi
    fi

    if menuSmokePartSelected subscription-main-entry; then
        (
            configPath=
            resetMenuActions
            manageSubscription
            [[ "$?" == "0" ]]
            assertMenuAction 'errorCard:未安装'
        )
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        (
            local roleSummaryJqLog="${TMP_DIR}/role-summary-jq.log"
            jq() {
                printf 'jq\n' >>"${roleSummaryJqLog}"
                command jq "$@"
            }
            subscriptionWireGuardReadState() {
                printf '%s\n' '{"enabled":true,"role":"main","address":"10.77.0.1/24","peers":[{"id":"edge-a"}]}'
            }
            : >"${roleSummaryJqLog}"
            showSubscriptionServerRoleSummary
            [[ "$(wc -l <"${roleSummaryJqLog}")" == "1" ]]
        )
        (
            local sourceReadLog="${TMP_DIR}/user-source-menu-read.log"
            local observedPrompt= selectedSources= sourcesChanged=
            subscriptionActiveGroupRead() {
                printf 'read\n' >>"${sourceReadLog}"
                [[ "${*: -1}" == ".sources" ]]
                printf '%s\n' '[{"id":"edge-a","name":"边缘 A","enabled":true}]'
            }
            autoRead() {
                observedPrompt=$2
                printf -v "$3" '%s' ''
            }
            : >"${sourceReadLog}"
            selectUserSubscriptionSources edit_user_subscription_sources \
                "请选择节点范围[回车保留当前范围]:" selectedSources '["edge-a"]' "" sourcesChanged
            [[ "$(wc -l <"${sourceReadLog}")" == "1" ]]
            [[ "${selectedSources}" == '["edge-a"]' && "${sourcesChanged}" == "false" ]]
            [[ "${observedPrompt}" == *'回车保留当前范围'* ]]
        )
        (
            local sourceReadLog="${TMP_DIR}/source-toggle-menu-read.log"
            local warning=
            subscriptionRequireMainRole() { return 0; }
            subscriptionActiveGroupRead() {
                printf 'read\n' >>"${sourceReadLog}"
                printf '%s\n' '[{"id":"edge-a","name":"边缘 A","role":"secondary","scheme":"wireguard","host":"10.77.0.2","port":39778,"enabled":false,"sync_status":"pending"}]'
            }
            autoRead() {
                if [[ "$1" == "subscription_source_enabled_confirm" ]]; then
                    printf -v "$3" '%s' n
                else
                    printf -v "$3" '%s' edge-a
                fi
            }
            warnCard() { warning=$*; }
            setSubscriptionRemoteSourceEnabled() { return 0; }
            runSubscriptionSyncAfterMutation() { return 0; }
            : >"${sourceReadLog}"
            originalChangeSubscriptionSourceEnabledMenu
            [[ "$(wc -l <"${sourceReadLog}")" == "1" ]]
            [[ "${warning}" == *'启用后立即同步并更新公网发布'* ]]
        )
        (
            local sourceReadLog="${TMP_DIR}/source-remove-menu-read.log"
            subscriptionRequireMainRole() { return 0; }
            subscriptionActiveGroupRead() {
                printf 'read\n' >>"${sourceReadLog}"
                printf '%s\n' '[{"id":"edge-a","name":"边缘 A","role":"secondary","scheme":"wireguard","host":"10.77.0.2","port":39778,"enabled":true,"sync_status":"pending"}]'
            }
            autoRead() {
                if [[ "$1" == "delete_subscription_source_confirm" ]]; then
                    printf -v "$3" '%s' yes
                else
                    printf -v "$3" '%s' edge-a
                fi
            }
            subscriptionWireGuardRemovePeerAndSource() { return 0; }
            runSubscriptionSyncAfterMutation() { return 0; }
            : >"${sourceReadLog}"
            originalRemoveSubscriptionControlledServerMenu
            [[ "$(wc -l <"${sourceReadLog}")" == "1" ]]
        )
        setMenuSmokeRole uninitialized
        resetMenuActions
        resetMenuRender
        manageSubscription <<<"9" || true
        [[ "${menuNumbers}" == $'1\n2\n3\n4\n5\n6\n7\n8\n9:return\n' ]]
        ! assertMenuAction menu
        grep -q "多服务器角色：.*未启用；可直接使用本机订阅" <<<"${output}"
        grep -q "启用主控协同" <<<"${output}"
        grep -q "接入主控" <<<"${output}"
        if grep -q "本机单独使用" <<<"${output}" || grep -q "这台作为主控" <<<"${output}" || grep -q "这台作为被控" <<<"${output}"; then
            printf 'menu-smoke failed: uninitialized top-level still shows role-selection entries\n' >&2
            return 1
        fi
        resetMenuActions
        output=
        manageSubscriptionLocalHome <<<"7
n"
        assertMenuAction initSubscriptionWireGuardMain
        assertMenuAction 'statusCard:主控建链已完成'
        if assertMenuAction showSubscriptionWireGuardMainCredential || assertMenuAction createSubscriptionWireGuardInviteMenu; then
            return 1
        fi
        resetMenuActions
        setMenuSmokeRole uninitialized
        output=
        manageSubscriptionLocalHome <<<"9"
        grep -q "返回主菜单" <<<"${output}"
        grep -q "查看当前订阅链接" <<<"${output}"
        resetMenuActions
        output=
        manageSubscriptionLocalHome <<<"9"
        [[ -z "${actions}" ]]
        resetMenuActions
        manageSubscriptionLocalHome <<<"6
9"
        [[ "${actions}" == $'installSubscribe\nshowSubscriptionServiceStatus\n' ]]
        resetMenuActions
        manageSubscriptionLocalHome <<< $'10\n9'
        [[ "${actions}" == $'errorCard:选择错误，请重新选择\n' ]]
        (
            resetMenuActions
            initSubscriptionWireGuardMain() { recordMenuAction init-failed; return 1; }
            manageSubscription <<< $'7\n1\n9'
            [[ "${actions}" == $'init-failed\nshowPublishedSubscriptionLinks:\n' ]]
        )
        (
            resetMenuActions
            manageSubscription <<< $'8\ninvalid-invite\n\n1\n9'
            [[ "${actions}" == $'errorCard:主控邀请无效，请复制完整内容后重试\nshowPublishedSubscriptionLinks:\n' ]]
            [[ "$(subscriptionCurrentRoleNormalized)" == uninitialized ]]
        )
        (
            local joinCount=0 credentialJson=stale
            local credentialStderr="${TMP_DIR}/credential-read-stderr.log"
            subscriptionWireGuardCredentialDecode() {
                case "$1" in
                valid-invite) printf '{"kind":"invite","invite_id":"test-id"}\n' ;;
                wrong-kind) printf '{"kind":"receipt"}\n' ;;
                *) printf 'credential-must-not-leak\n' >&2; return 1 ;;
                esac
            }
            subscriptionWireGuardJoinInvite() { joinCount=$((joinCount + 1)); recordMenuAction join-invite; }
            setMenuSmokeRole uninitialized
            resetMenuActions
            runSubscriptionControlledWizard <<< $'invalid-invite\nwrong-kind\nvalid-invite' 2>"${credentialStderr}"
            [[ "${joinCount}" == "1" && ! -s "${credentialStderr}" ]]
            [[ "${actions}" == $'errorCard:主控邀请无效，请复制完整内容后重试\nerrorCard:请粘贴主控邀请\njoin-invite\nsuccessCard:被控已按邀请完成初始化\nshowSubscriptionWireGuardJoinReceipt\nshowSubscriptionWireGuardStatus\n' ]]
            resetMenuActions
            regressionExpectStatus 1 runSubscriptionControlledWizard <<<""
            regressionExpectStatus 1 runSubscriptionControlledWizard </dev/null
            regressionExpectStatus 1 runSubscriptionControlledWizard < <(printf 'valid-invite')
            [[ "${joinCount}" == "1" && -z "${actions}" ]]
            regressionExpectStatus 1 subscriptionWireGuardReadCredential invite "主控邀请" credentialJson <<<""
            [[ -z "${credentialJson}" ]]
        )
        (
            setMenuSmokeRole uninitialized
            resetMenuActions
            output=
            manageSubscription <<< $'7\nn\n1\n9'
            assertMenuAction initSubscriptionWireGuardMain
            assertMenuAction 'showPublishedSubscriptionLinks:'
            [[ "$(subscriptionCurrentRoleNormalized)" == main ]]
            grep -q "管理被控服务器" <<<"${output}"
        )
        (
            setMenuSmokeRole uninitialized
            resetMenuActions
            output=
            manageSubscription <<< $'8\ninvite-credential\n2\n8'
            assertMenuAction subscriptionWireGuardJoinInvite
            [[ "$(grep -cxF showSubscriptionWireGuardStatus <<<"${actions}")" == "2" ]]
            [[ "$(subscriptionCurrentRoleNormalized)" == controlled ]]
            grep -q "显示被控更新凭据" <<<"${output}"
        )
        (
            local readCount=0
            setMenuSmokeRole uninitialized
            resetMenuActions
            autoRead() {
                readCount=$((readCount + 1))
                IFS= read -r "$3"
            }
            manageSubscription <<< $'7\nn'
            [[ "${readCount}" == "2" && "$(subscriptionCurrentRoleNormalized)" == main ]]
        )
        (
            local currentRole=uninitialized
            resetMenuActions
            subscriptionCurrentRoleNormalized() { printf '%s\n' "${currentRole}"; }
            manageSubscriptionLocalHome() { recordMenuAction local-home; currentRole=main; return 1; }
            manageSubscriptionMainHome() { recordMenuAction main-home; return 7; }
            regressionExpectStatus 7 manageSubscription </dev/null
            [[ "${actions}" == $'local-home\nmain-home\n' ]]
        )
        (
            local currentRole=uninitialized
            resetMenuActions
            subscriptionCurrentRoleNormalized() {
                [[ "${currentRole}" != invalid ]] || return 1
                printf '%s\n' "${currentRole}"
            }
            manageSubscriptionLocalHome() { recordMenuAction local-home; currentRole=invalid; }
            manageSubscriptionMainHome() { recordMenuAction main-home; }
            regressionExpectStatus 1 manageSubscription </dev/null
            [[ "${actions}" == $'local-home\nerrorCard:WireGuard 控制面状态损坏或不可读\n' ]]
            resetMenuActions
            regressionExpectStatus 1 manageSubscription </dev/null
            [[ "${actions}" == $'errorCard:WireGuard 控制面状态损坏或不可读\n' ]]
        )
        resetMenuActions
        output=
        setMenuSmokeRole uninitialized
        manageSubscriptionLocalHome <<<"8
invite-credential"
        assertMenuAction subscriptionWireGuardJoinInvite
        assertMenuAction showSubscriptionWireGuardJoinReceipt
        assertMenuAction showSubscriptionWireGuardStatus
        setMenuSmokeRole main
        resetMenuActions
        output=
        manageSubscription <<<"9"
        grep -q "查看当前订阅链接" <<<"${output}"
        grep -q "订阅同步" <<<"${output}"
        grep -q "管理被控服务器" <<<"${output}"
        grep -q "维护本机控制面" <<<"${output}"
        ! grep -q "协同与控制" <<<"${output}"
        ! grep -q "服务器与协同" <<<"${output}"
        ! grep -q "控制面与连接" <<<"${output}"
        if grep -q '^发布订阅 ' <<<"${output}" || grep -q '^多服务器协同 ' <<<"${output}" || grep -q '^主控维护与排障 ' <<<"${output}" || grep -q '^被控维护与排障 ' <<<"${output}"; then
            printf 'menu-smoke failed: main top-level still exposes grouped submenus\n' >&2
            return 1
        fi
        ! assertMenuAction menu
    fi

    if menuSmokePartSelected subscription-main-publish-service; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        resetMenuActions
        resetMenuRender
        manageSubscriptionMainHome <<<"9"
        [[ "${menuNumbers}" == $'1\n2\n3\n4\n5\n6\n7\n8\n9:return\n' ]]
        grep -q "查看当前订阅链接" <<<"${output}"
        ! grep -q "新建并发布订阅" <<<"${output}"
        ! grep -q "刷新并查看我的订阅链接" <<<"${output}"
        ! grep -q "查看并处理已有订阅" <<<"${output}"
        grep -q "管理被控服务器" <<<"${output}"
        grep -q "维护本机控制面" <<<"${output}"
        ! grep -q "协同与控制" <<<"${output}"
        ! grep -q "服务器与协同" <<<"${output}"
        ! grep -q "控制面与连接" <<<"${output}"
        if grep -q "同步订阅变更" <<<"${output}" || grep -q "预览同步变更" <<<"${output}" || grep -q "查看我的可用服务器" <<<"${output}"; then
            printf 'menu-smoke failed: main menu still shows duplicate leaf entries\n' >&2
            return 1
        fi
        resetMenuActions
        manageSubscriptionMainHome <<<"6
9"
        assertMenuAction installSubscribe
        assertMenuAction showSubscriptionServiceStatus
        resetMenuActions
        manageSubscriptionMainHome <<<"1
9"
        [[ "${actions}" == $'showPublishedSubscriptionLinks:\n' ]]
        resetMenuActions
        manageSubscriptionMainHome <<<"4
9"
        [[ "${actions}" == $'runSubscriptionGroupSync:\nshowPublishedSubscriptionLinks:\n' ]]
        ! assertMenuAction installSubscribe
        ! assertMenuAction subscribe
        (
            resetMenuActions
            runSubscriptionGroupSync() { recordMenuAction 'runSubscriptionGroupSync:'; }
            readNginxSubscribe() { recordMenuAction readNginxSubscribe; return 99; }
            installSubscribe() { recordMenuAction installSubscribe; return 99; }
            SUBSCRIPTION_SYNC_PUBLISHED=true
            manageSubscriptionMainHome <<< $'4\n9'
            [[ "${actions}" == $'runSubscriptionGroupSync:\nstatusCard:账号同步已完成，未发布订阅链接\n' ]]
            [[ "${SUBSCRIPTION_SYNC_PUBLISHED}" == false ]]
        )
        resetMenuActions
        manageSubscriptionMainHome <<<"3
7
9"
        [[ "${actions}" == $'showSubscriptionTrafficOverview\n' ]]
        resetMenuActions
        output=
        manageSubscriptionMainHome <<<"5
5
9"
        grep -q "立即完整同步" <<<"${output}"
        [[ -z "${actions}" ]]
        resetMenuActions
        output=
        manageSubscriptionMainHome <<<"9"
        grep -q "本机自用订阅来自协议配置" <<<"${output}"
        grep -q "查看当前订阅链接" <<<"${output}"
        grep -q "立即完整同步" <<<"${output}"
        grep -q "安装/更新发布服务" <<<"${output}"
        ! grep -q "发布与链接" <<<"${output}"
        grep -q "分享订阅" <<<"${output}"
        grep -q "流量与限额" <<<"${output}"
        grep -q "返回主菜单" <<<"${output}"
        resetMenuActions
        output=
        manageSubscriptionMainHome <<<"9"
        grep -q "安装/更新发布服务" <<<"${output}"
        grep -q "查看当前订阅链接" <<<"${output}"
        resetMenuActions
        output=
        manageSubscriptionMainHome <<<"2

9"
        grep -q "暂无分享订阅" <<<"${output}"
        ! grep -q "输入编号或订阅 ID" <<<"${output}"
        [[ -z "${actions}" ]]
        resetMenuActions
    fi

    if menuSmokePartSelected subscription-main-publish-user || menuSmokePartSelected subscription-main-publish-user-empty; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        resetMenuActions
        manageSubscriptionMainHome <<<"2

1
9" || true
        subscriptionGroupsStateRead -e '((.user_groups // []) | length) == 0' >/dev/null
        [[ "${actions}" == $'showPublishedSubscriptionLinks:\n' ]]
    fi

    if menuSmokePartSelected subscription-main-publish-user || menuSmokePartSelected subscription-main-publish-user-create; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        resetMenuActions
        manageSubscriptionMainHome <<<"2
demo-user
main
0
9
1
9"
        subscriptionGroupsStateRead -e 'any(.user_groups[]?; .id == "demo-user" and .name == "demo-user")' >/dev/null
        assertMenuAction 'showPublishedSubscriptionLinks:'
        ! assertMenuAction 'errorCard:用户订阅选择无效，请输入列表编号、完整 ID 或菜单中的选择项'
        local duplicateSideEffectMarker="${TMP_DIR}/duplicate-user-side-effect"
        rm -f "${duplicateSideEffectMarker}"
        (
            readNginxSubscribe() { : >"${duplicateSideEffectMarker}"; subscribePort=; }
            installSubscribe() { : >"${duplicateSideEffectMarker}"; }
            if createAndSyncUserSubscriptionWizard <<<"demo-user"; then
                return 1
            fi
        )
        [[ ! -e "${duplicateSideEffectMarker}" ]]
    fi

    if menuSmokePartSelected subscription-main-publish-user || menuSmokePartSelected subscription-main-publish-user-inspect; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        if [[ "${menuSmokePart}" == "subscription-main-publish-user-inspect" ]]; then
            manageSubscriptionMainHome <<<"2
demo-user
main
0
9
9"
        fi
        resetMenuActions
        output=
        manageSubscriptionMainHome <<<"2
2
3
3
2
6
9
1
9"
        grep -q "查看当前已发布链接" <<<"${output}"
        grep -q "立即同步并更新链接" <<<"${output}"
        grep -q "查看当前流量" <<<"${output}"
        grep -q "返回上级菜单" <<<"${output}"
        ! grep -q "输入编号或订阅 ID" <<<"${output}"
        subscriptionGroupsStateRead -e 'any(.user_groups[]?; .id == "demo-user" and .traffic_limit_gb == 2)' >/dev/null
        assertMenuAction 'runSubscriptionGroupSync:'
        assertMenuAction 'showPublishedSubscriptionLinks:'
        ! assertMenuAction 'errorCard:用户订阅选择无效，请输入列表编号、完整 ID 或菜单中的选择项'
        resetMenuActions
    fi

    if menuSmokePartSelected subscription-main-publish-sync || menuSmokePartSelected subscription-main-publish-sync-skip; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        resetMenuActions
        subscriptionGroupsStateWrite '.user_groups = [] | .sync.enabled = false'
        manageSubscriptionMainHome <<<"2
team-a
*
0
9
9"
        subscriptionGroupsStateRead -e 'any(.user_groups[]?; .id == "team-a" and .name == "team-a")' >/dev/null
        subscriptionGroupsStateRead -e '.sync.enabled == false' >/dev/null
        assertMenuAction 'runSubscriptionGroupSync:'
        ! assertMenuAction refreshSubscriptionGroupSyncCron
    fi

    if menuSmokePartSelected subscription-main-publish-sync || menuSmokePartSelected subscription-main-publish-sync-enable; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        resetMenuActions
        rm -rf "${PADM_SUBSCRIPTION_GROUPS_DIR}"
        ensureSubscriptionGroupsState
        subscriptionGroupsStateWrite '.sync.enabled = true'
        manageSubscriptionMainHome <<<"2
team-b
main
0
9
9"
        ! assertMenuAction refreshSubscriptionGroupSyncCron
        assertMenuAction 'runSubscriptionGroupSync:'
        subscriptionGroupsStateRead -e '.sync.enabled == true' >/dev/null
    fi

    if menuSmokePartSelected subscription-main-maintenance; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        (
            runSubscriptionGroupSync() {
                recordMenuAction "forced-sync:${SUBSCRIPTION_SYNC_FORCE_RETRY:-false}"
                return 1
            }
            resetMenuActions
            manageSubscriptionSyncDiagnostics <<< $'7\n2\n8'
            assertMenuAction 'forced-sync:true' || return 1
            assertMenuAction showSubscriptionServiceStatus || return 1
            [[ "${SUBSCRIPTION_SYNC_FORCE_RETRY:-false}" != "true" ]]
        ) || return 1
        resetMenuActions
        resetMenuRender
        manageSubscriptionSyncSettings <<<"5"
        [[ "${menuNumbers}" == $'1\n2\n3\n4\n5:return\n' ]]
        ! grep -q "立即完整同步" <<<"${output}"
        grep -q "开启/关闭自动同步" <<<"${output}"
        grep -q "设置同步间隔" <<<"${output}"
        grep -q "状态与排障" <<<"${output}"
        grep -q "状态备份与恢复" <<<"${output}"
        ! grep -q "流量与限额" <<<"${output}"
        if grep -q "事件同步" <<<"${output}" || grep -q "开启/关闭远程同步" <<<"${output}"; then
            printf 'menu-smoke failed: unified sync menu still exposes legacy toggles\n' >&2
            return 1
        fi
        resetMenuActions
        manageSubscriptionSyncSettings <<< $'6\n5'
        [[ "${actions}" == $'errorCard:选择错误，请重新选择\n' ]]
        resetMenuActions
        (
            local syncEnabled=true syncInterval=10
            local settingWrites=0 cronWrites=0 cronShouldFail=false
            subscriptionActiveGroupRead() {
                case "${@: -1}" in
                '.sync.enabled == true') printf '%s\n' "${syncEnabled}" ;;
                '.sync.interval_minutes') printf '%s\n' "${syncInterval}" ;;
                *)
                    command jq -cn --argjson enabled "${syncEnabled}" --argjson interval "${syncInterval}" \
                        '{enabled:$enabled,interval_minutes:$interval,last_run:"",last_status:"pending",failure_count:0}'
                    ;;
                esac
            }
            setSubscriptionGroupSyncEnabled() {
                [[ "${SUBSCRIPTION_GROUPS_LOCK_HELD:-}" == "1" ]] || return 1
                settingWrites=$((settingWrites + 1))
                syncEnabled=$1
            }
            setSubscriptionGroupSyncInterval() {
                [[ "${SUBSCRIPTION_GROUPS_LOCK_HELD:-}" == "1" ]] || return 1
                settingWrites=$((settingWrites + 1))
                syncInterval=$1
            }
            refreshSubscriptionGroupSyncCron() {
                [[ "${SUBSCRIPTION_GROUPS_LOCK_HELD:-}" == "1" ]] || return 1
                cronWrites=$((cronWrites + 1))
                [[ "${cronShouldFail}" != "true" || "${cronWrites}" != "1" ]]
            }
            autoRead() { read -r "$3"; }
            resetMenuActions
            manageSubscriptionSyncSettings <<< $'2\n\n5'
            manageSubscriptionSyncSettings <<< $'2\n10\n5'
            manageSubscriptionSyncSettings < <(printf '2\n20')
            [[ "${settingWrites}" == "0" && "${cronWrites}" == "0" && "${syncInterval}" == "10" ]]
            manageSubscriptionSyncSettings <<< $'2\ninvalid\n60\n17\n5'
            [[ "${settingWrites}" == "1" && "${cronWrites}" == "1" && "${syncInterval}" == "17" ]]
            setSubscriptionGroupSyncIntervalWithCron 17
            [[ "${settingWrites}" == "2" && "${cronWrites}" == "2" ]]

            (
                local settingWrites=0 cronWrites=0
                eval "$(declare -f menuReadChoice | sed '1s/^menuReadChoice/originalSyncMenuReadChoice/')"
                menuReadChoice() {
                    originalSyncMenuReadChoice "$@" || return $?
                    if [[ "$1" == "sync_settings_menu" && "${!3}" == "1" ]]; then
                        syncEnabled=false
                    fi
                }
                resetMenuActions
                manageSubscriptionSyncSettings <<< $'1\n5'
                [[ "${settingWrites}" == "0" && "${cronWrites}" == "0" && "${syncEnabled}" == "false" ]]
                assertMenuAction 'errorCard:同步设置已变化，请重新读取后重试'
            )
            settingWrites=0
            cronWrites=0
            cronShouldFail=true
            regressionExpectStatus 1 setSubscriptionGroupSyncEnabledWithCron false true
            [[ "${settingWrites}" == "2" && "${cronWrites}" == "2" && "${syncEnabled}" == "true" ]]
        ) || return 1
        (
            local syncStatusJqLog="${TMP_DIR}/sync-status-jq.log"
            subscriptionCurrentRoleNormalized() { printf 'main\n'; }
            subscriptionActiveGroupRead() {
                printf '%s\n' '{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failure_count":0}'
            }
            jq() {
                printf 'jq\n' >>"${syncStatusJqLog}"
                command jq "$@"
            }
            : >"${syncStatusJqLog}"
            manageSubscriptionSyncSettings <<<"5"
            [[ "$(wc -l <"${syncStatusJqLog}")" == "1" ]]
        )
        (
            local pendingInviteJqLog="${TMP_DIR}/pending-invite-jq.log"
            local cancelCalled=
            subscriptionWireGuardListPendingInvites() {
                [[ "${1:-}" == true ]] || return 99
                printf '%s\n' '[{"invite_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","alias":"edge-a","address":"10.77.0.2/24","expires_at":1770000000,"remaining_seconds":3600,"status":"pending"}]'
            }
            autoRead() {
                printf -v "$3" '%s' ''
                return 1
            }
            subscriptionWireGuardCancelInvite() { cancelCalled=true; }
            jq() {
                printf 'jq\n' >>"${pendingInviteJqLog}"
                command jq "$@"
            }
            : >"${pendingInviteJqLog}"
            output=
            originalManageSubscriptionPendingInvites
            grep -q '别名：edge-a' <<<"${output}"
            [[ "$(wc -l <"${pendingInviteJqLog}")" == "1" ]]
            [[ -z "${cancelCalled}" ]]
        )
        (
            local pendingState initialPending listLog="${TMP_DIR}/pending-menu-reads.log"
            local cancelLog= cancelCount=0 cancelShouldFail=false pendingStdout="${TMP_DIR}/pending-menu-stdout.log"
            local inviteIdA='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
            local inviteIdB='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
            initialPending=$(command jq -cn --arg idA "${inviteIdA}" --arg idB "${inviteIdB}" '
              [{invite_id:$idA,alias:"edge-a",address:"10.77.0.2/24",expires_at:1770000000,remaining_seconds:3600,status:"pending"},
               {invite_id:$idB,alias:"2",address:"10.77.0.3/24",expires_at:1770000000,remaining_seconds:3600,status:"incomplete",token:"never-print-token"}]')
            pendingState=${initialPending}
            subscriptionWireGuardListPendingInvites() {
                [[ "${1:-}" == true ]] || return 99
                printf 'read\n' >>"${listLog}"
                printf '%s\n' "${pendingState}"
            }
            subscriptionWireGuardCancelInvite() {
                cancelCount=$((cancelCount + 1))
                cancelLog+="$1:$2"$'\n'
                [[ "${cancelShouldFail}" != true ]] || return 1
                pendingState=$(command jq -c --arg alias "$1" --arg id "$2" '
                  [.[] | select(.alias != $alias or .invite_id != $id)]' <<<"${pendingState}")
            }
            statusCard() { output+="$*"$'\n'; recordMenuAction "statusCard:$1"; }
            warnCard() { output+="$*"$'\n'; recordMenuAction "warnCard:$1"; }
            successCard() { output+="$*"$'\n'; recordMenuAction "successCard:$1"; }
            errorCard() { output+="$*"$'\n'; recordMenuAction "errorCard:$1"; }
            : >"${listLog}"
            resetMenuActions
            output=
            originalManageSubscriptionPendingInvites >"${pendingStdout}" <<< $'invalid\nedge-a\nn\nedge-a\ny\n2\ny'
            [[ "${cancelCount}" == "2" && "${cancelLog}" == "edge-a:${inviteIdA}"$'\n'"2:${inviteIdB}"$'\n' &&
                "${pendingState}" == '[]' && "$(wc -l <"${listLog}")" == "4" ]]
            assertMenuAction 'errorCard:待完成邀请别名无效，请重新输入'
            assertMenuAction 'statusCard:已保留待完成邀请'
            [[ "$(grep -cxF 'successCard:待完成邀请已取消' <<<"${actions}")" == "2" ]]
            grep -q '当前没有待完成邀请' <<<"${output}"
            ! grep -qE "${inviteIdA}|${inviteIdB}|never-print-token" <<<"${output}"
            ! grep -qE "${inviteIdA}|${inviteIdB}|never-print-token" "${pendingStdout}"
            pendingState=${initialPending}
            cancelCount=0
            cancelLog=
            originalManageSubscriptionPendingInvites <<<""
            originalManageSubscriptionPendingInvites </dev/null
            originalManageSubscriptionPendingInvites < <(printf edge-a)
            originalManageSubscriptionPendingInvites < <(printf 'edge-a\n')
            originalManageSubscriptionPendingInvites < <(printf 'edge-a\ny')
            [[ "${cancelCount}" == "0" && -z "${cancelLog}" && "${pendingState}" == "${initialPending}" ]]
            : >"${listLog}"
            cancelShouldFail=true
            resetMenuActions
            regressionExpectStatus 1 originalManageSubscriptionPendingInvites <<< $'edge-a\ny\n2\ny'
            [[ "${cancelCount}" == "1" && "${cancelLog}" == "edge-a:${inviteIdA}"$'\n' &&
                "$(wc -l <"${listLog}")" == "1" && "${pendingState}" == "${initialPending}" ]]
            ! assertMenuAction 'successCard:待完成邀请已取消'
        )
        resetMenuActions
        output=
        manageSubscriptionSyncSettings <<<"4
5
5"
        grep -q "返回订阅同步" <<<"${output}"
        resetMenuActions
        manageSubscriptionSyncSettings <<<"3
1
8
5"
        assertMenuAction showSubscriptionGroupsStateSummary
        assertMenuAction showSubscriptionSources
        resetMenuActions
        manageSubscriptionSyncDiagnostics <<<"2
8"
        assertMenuAction showSubscriptionServiceStatus
        resetMenuActions
        manageSubscriptionSyncDiagnostics <<<"3
8"
        assertMenuAction showSubscriptionLocalSyncPlan
        assertMenuAction subscriptionSyncPlan
        resetMenuActions
        manageSubscriptionSyncDiagnostics <<<"4
8"
        assertMenuAction showSubscriptionRemoteSyncPlan
        assertMenuAction subscriptionRemoteSyncPlan
        resetMenuActions
        manageSubscriptionSyncDiagnostics <<<"5
8"
        assertMenuAction showSubscriptionRemoteHealthPlan
        assertMenuAction subscriptionRemoteControlHealthAll
        resetMenuActions
        resetMenuRender
        manageSubscriptionSyncDiagnostics <<<"8"
        [[ "${menuNumbers}" == $'1\n2\n3\n4\n5\n6\n7\n8:return\n' ]]
        resetMenuRender
        manageTrafficAndQuota <<<"1
7"
        [[ "${actions}" == $'showSubscriptionTrafficOverview\ncollectSubscriptionTraffic\nshowSubscriptionTrafficOverview\n' ]]
        grep -q "返回订阅首页" <<<"${output}"
        resetMenuActions
        (
            local trafficActions=
            showSubscriptionTrafficOverview() { trafficActions+="overview"$'\n'; }
            collectSubscriptionTraffic() { trafficActions+="collect"$'\n'; return 0; }
            resetMenuRender
            manageTrafficAndQuota <<<"7"
            [[ "${trafficActions}" == $'overview\n' ]]
            [[ "${menuNumbers}" == $'1\n2\n3\n4\n5\n6\n7:return\n' ]]
        )
        resetMenuActions
        local trafficCommitted
        for trafficCommitted in true false; do
            (
                local trafficActions=
                showSubscriptionTrafficOverview() { trafficActions+="overview"$'\n'; }
                collectSubscriptionTraffic() {
                    trafficActions+="collect"$'\n'
                    SUBSCRIPTION_TRAFFIC_LOCAL_COMMITTED=${trafficCommitted}
                    return 1
                }
                manageTrafficAndQuota <<<"1
7"
                [[ "${trafficActions}" == $'overview\ncollect\noverview\n' ]]
            )
        done
        (
            local trafficActions=
            showSubscriptionTrafficOverview() { trafficActions+="overview"$'\n'; return 1; }
            collectSubscriptionTraffic() { trafficActions+="collect"$'\n'; return 1; }
            manageTrafficAndQuota <<<"1
7"
            [[ "${trafficActions}" == $'overview\ncollect\noverview\n' ]]
            [[ "${actions}" == $'errorCard:流量总览暂不可读\nwarnCard:流量未完整刷新\nerrorCard:流量总览暂不可读\n' ]]
        )
        resetMenuActions
        manageTrafficAndQuota <<<"3
7"
        assertMenuAction showAdminSubscriptionTraffic
        (
            resetMenuActions
            manageSharedSubscriptions() { recordMenuAction manageSharedSubscriptions; }
            showSubscriptionSourcesTraffic() { recordMenuAction showSubscriptionSourcesTraffic; }
            showUserSubscriptions() { recordMenuAction showUserSubscriptions; }
            output=
            manageTrafficAndQuota <<<"2
4
8
7"
            [[ "${actions}" == $'showSubscriptionTrafficOverview\nmanageSharedSubscriptions\nshowSubscriptionTrafficOverview\nshowSubscriptionSourcesTraffic\nshowSubscriptionTrafficOverview\nerrorCard:选择错误，请重新选择\nshowSubscriptionTrafficOverview\n' ]]
            grep -q '管理分享订阅与额度' <<<"${output}"
            ! grep -q '分享订阅概览' <<<"${output}"
        )
        (
            local savedLimit=1
            resetMenuActions
            showSubscriptionTrafficOverview() { recordMenuAction "overview:${savedLimit}"; }
            manageSharedSubscriptions() { recordMenuAction edit-limit; savedLimit=2; }
            collectSubscriptionTraffic() { recordMenuAction collect; return 99; }
            manageTrafficAndQuota <<< $'2\n7'
            [[ "${actions}" == $'overview:1\nedit-limit\noverview:2\n' ]]
        )
        resetMenuActions
        manageTrafficAndQuota <<<"5
7"
        assertMenuAction executeSubscriptionQuotaPlanMenu
        resetMenuActions
        manageTrafficAndQuota <<<"6
7"
        assertMenuAction 'successCard:限额自动执行状态已更新'
        subscriptionGroupsStateRead -e '.sync.quota_auto_apply == true' >/dev/null
        (
            local menuReadCount=0 quotaToggleCount=0
            autoRead() {
                menuReadCount=$((menuReadCount + 1))
                if [[ "${menuReadCount}" == "1" ]]; then
                    printf -v "$3" '%s' 6
                    return 0
                fi
                printf -v "$3" '%s' 6
                return 1
            }
            subscriptionActiveGroupRead() {
                printf '%s\n' false
            }
            toggleSubscriptionGroupQuotaAutoApplyEnabled() {
                [[ "$1" == "false" && "$2" == "true" ]]
                quotaToggleCount=$((quotaToggleCount + 1))
                return 0
            }
            manageTrafficAndQuota
            [[ "${menuReadCount}" == "2" ]]
            [[ "${quotaToggleCount}" == "1" ]]
        )
        resetMenuActions
        manageSubscriptionMainControlDetails <<<"1
5"
        assertMenuAction showSubscriptionWireGuardMainCredential
        resetMenuActions
        manageSubscriptionMainControlDetails <<<"2
5"
        assertMenuAction showSubscriptionWireGuardPeers
        assertMenuAction showSubscriptionSourceControlUrls
        for wgAction in "3:restartSubscriptionWireGuardControl" "4:disableSubscriptionWireGuardControl"; do
            wgChoice=${wgAction%%:*}
            resetMenuActions
            manageSubscriptionMainControlDetails <<<"${wgChoice}
5"
            assertMenuAction "${wgAction#*:}"
        done
        resetMenuActions
        output=
        manageSubscriptionMainHome <<<"7
6
9"
        [[ -z "${actions}" ]]
        grep -q "管理被控服务器" <<<"${output}"
        grep -q "维护本机控制面" <<<"${output}"
        ! grep -q "查看协同状态" <<<"${output}"
        resetMenuActions
        manageSubscriptionMainHome <<<"8
5
9"
        assertMenuAction showSubscriptionWireGuardStatus
        resetMenuRender
        manageSubscriptionServers <<<"6"
        [[ "${menuNumbers}" == $'1\n2\n3\n4\n5\n6:return\n' ]]
        resetMenuActions
        manageSubscriptionServers <<< $'7\n8\n6'
        [[ "${actions}" == $'errorCard:选择错误，请重新选择\nerrorCard:选择错误，请重新选择\n' ]]
        for wgAction in \
            "1:createSubscriptionWireGuardInviteMenu" \
            "2:addOtherSubscribe" \
            "3:manageSubscriptionPendingInvites" \
            "5:showSubscriptionSources"; do
            wgChoice=${wgAction%%:*}
            resetMenuActions
            manageSubscriptionServers <<<"${wgChoice}
6"
            assertMenuAction "${wgAction#*:}"
        done
        (
            local syncStatus=0 completionShouldFail=false completedId=stale
            addOtherSubscribe() { originalMenuSmokeAddOtherSubscribe "$@"; }
            subscriptionWireGuardCredentialDecode() {
                case "$1" in
                valid-receipt) printf '{"kind":"receipt"}\n' ;;
                not-receipt) printf '{"kind":"invite"}\n' ;;
                *) return 1 ;;
                esac
            }
            subscriptionWireGuardCompleteInvite() {
                recordMenuAction complete-invite
                [[ "${completionShouldFail}" != true ]] || return 1
                printf -v "$2" '%s' edge-new
            }
            runSubscriptionSyncAfterMutation() {
                [[ "${3:-}" == true ]] || return 99
                recordMenuAction forced-sync
                return "${syncStatus}"
            }
            manageSubscriptionServerItem() { recordMenuAction "server-detail:${1:-}"; }
            resetMenuActions
            manageSubscriptionServers <<< $'2\nvalid-receipt\n6'
            [[ "${actions}" == $'complete-invite\nsuccessCard:被控接入已完成\nforced-sync\nserver-detail:edge-new\n' ]]
            syncStatus=1
            resetMenuActions
            manageSubscriptionServers <<< $'2\ninvalid-receipt\nnot-receipt\nvalid-receipt\n2\ninvalid-receipt\n\n2'
            [[ "${actions}" == $'errorCard:接入回执无效，请复制完整内容后重试\nerrorCard:请粘贴接入回执\ncomplete-invite\nsuccessCard:被控接入已完成\nforced-sync\nserver-detail:edge-new\nerrorCard:接入回执无效，请复制完整内容后重试\n' ]]
            completionShouldFail=true
            resetMenuActions
            manageSubscriptionServers <<< $'2\nvalid-receipt\n6'
            [[ "${actions}" == $'complete-invite\n' ]]
            completionShouldFail=false
            regressionExpectStatus 1 addOtherSubscribe completedId <<<valid-receipt
            [[ "${completedId}" == edge-new ]]
            regressionExpectStatus 1 addOtherSubscribe completedId </dev/null
            [[ -z "${completedId}" ]]
            completedId=stale
            regressionExpectStatus 1 addOtherSubscribe completedId <<<""
            [[ -z "${completedId}" ]]
            completedId=stale
            regressionExpectStatus 1 addOtherSubscribe completedId < <(printf valid-receipt)
            [[ -z "${completedId}" ]]
            regressionExpectStatus 1 addOtherSubscribe <<<valid-receipt
        )
        (
            local inviteCreateCount=0 invitedAlias=
            subscriptionWireGuardCreateInvite() {
                inviteCreateCount=$((inviteCreateCount + 1))
                invitedAlias=$1
                printf -v "$2" '%s' valid-created-invite
            }
            resetMenuActions
            regressionExpectStatus 1 originalMenuSmokeCreateInvite </dev/null
            regressionExpectStatus 1 originalMenuSmokeCreateInvite <<<""
            regressionExpectStatus 1 originalMenuSmokeCreateInvite < <(printf must-not-create)
            [[ "${inviteCreateCount}" == "0" && -z "${actions}" ]]
            originalMenuSmokeCreateInvite <<<edge-once
            [[ "${inviteCreateCount}" == "1" && "${invitedAlias}" == edge-once ]]
            [[ "${actions}" == $'statusCard:正在创建被控邀请\nstatusCard:被控邀请已创建\n' ]]
        )
        (
            manageSubscriptionServerItem() { recordMenuAction manageSubscriptionServerItem; }
            resetMenuActions
            manageSubscriptionServers <<<"4
5
6"
            [[ "${actions}" == $'manageSubscriptionServerItem\nshowSubscriptionSources\n' ]]
        )
        (
            local PADM_SUBSCRIPTION_GROUPS_DIR="${TMP_DIR}/server-item-groups"
            local serverActionLog="${TMP_DIR}/server-item-actions.log"
            local serverStdoutLog="${TMP_DIR}/server-item-stdout.log"
            local serverCardLog="${TMP_DIR}/server-item-cards.log"
            local serverSelectCount=0
            local serverSourcesJson=
            local serverHealthOk=true
            local serverHealthObjectError=false
            errorCard() {
                recordMenuAction "errorCard:$1"
                printf '%s\n' "$*" >>"${serverCardLog}"
            }
            mkdir -p "${PADM_SUBSCRIPTION_GROUPS_DIR}"
            writeDefaultSubscriptionGroupsState "$(subscriptionGroupsFile)"
            addSubscriptionSourceState edge-a "Edge A" 10.77.0.2 39778
            addSubscriptionSourceState edge-b "Edge B" 10.77.0.3 39778
            subscriptionActiveGroupWrite '
              .sources |= map(if .role != "main" then .control_token = "secret-server-token" else . end)
            '
            eval "$(declare -f selectSubscriptionSourceId | sed '1s/^selectSubscriptionSourceId/originalServerItemSelectSubscriptionSourceId/')"
            selectSubscriptionSourceId() {
                serverSelectCount=$((serverSelectCount + 1))
                originalServerItemSelectSubscriptionSourceId "$@"
            }
            setSubscriptionSourceControlTokenMenu() {
                command jq -e --arg id "$1" '.id == $id' <<<"$2" >/dev/null
                printf 'update:%s\n' "$1" >>"${serverActionLog}"
                return 1
            }
            changeSubscriptionSourceEnabledMenu() {
                command jq -e --arg id "$1" '.id == $id and .enabled == true' <<<"$2" >/dev/null
                [[ "$3" == "false" ]]
                printf 'enabled:%s:%s\n' "$1" "$3" >>"${serverActionLog}"
            }
            subscriptionRemoteControlHealth() {
                local checkedId
                checkedId=$(command jq -r '.id' <<<"$1")
                printf 'health:%s\n' "${checkedId}" >>"${serverActionLog}"
                command jq -cn --arg id "${checkedId}" --argjson ok "${serverHealthOk}" --argjson objectError "${serverHealthObjectError}" \
                    '{id:$id,ok:$ok,capabilities:["health","sync","traffic"],control_token:"secret-health-token",status:"unauthorized",status_code:401,error:"remote secret-health-token",error_detail:{type:"unauthorized",message:"remote secret-health-token"}} |
                     if $objectError then .error = {control_token:"secret-health-token"} |
                       .error_detail.message = .error | .status_code = "secret-health-token" else . end'
            }
            runSubscriptionGroupSync() { printf 'sync\n' >>"${serverActionLog}"; }
            : >"${serverActionLog}"
            resetMenuRender
            manageSubscriptionServerItem edge-a <<<"8"
            [[ "${menuNumbers}" == $'1\n2\n3\n4\n5\n6\n7\n8:return\n' ]]
            [[ "${serverSelectCount}" == "0" && ! -s "${serverActionLog}" ]]
            serverSourcesJson=$(subscriptionActiveGroupRead -c '.sources')
            (
                subscriptionActiveGroupWrite '.sources |= map(select(.id != "edge-b"))'
                resetMenuActions
                resetMenuRender
                manageSubscriptionServerItem <<<"7
3
8"
                [[ "${serverSelectCount}" == "0" && "$(<"${serverActionLog}")" == 'health:edge-a' ]]
                assertMenuAction 'statusCard:没有其他被控服务器'
                grep -qF '名称：Edge A（edge-a）' <<<"${output}"
            )
            : >"${serverActionLog}"
            (
                subscriptionActiveGroupWrite '.sources |= map(select(.role == "main"))'
                manageSubscriptionServerItem </dev/null
                [[ "${serverSelectCount}" == "1" && ! -s "${serverActionLog}" ]]
            )
            subscriptionActiveGroupWrite --argjson sources "${serverSourcesJson}" '.sources = $sources'
            output=
            manageSubscriptionServerItem >"${serverStdoutLog}" <<<"edge-a
1
2
3
4
5
7
1
8"
            [[ "${serverSelectCount}" == "1" ]]
            [[ "$(<"${serverActionLog}")" == $'update:edge-a\nenabled:edge-a:false\nhealth:edge-a\nsync\nupdate:edge-b' ]]
            ! grep -qF 'secret-server-token' <<<"${output}"
            ! grep -qF 'secret-health-token' "${serverStdoutLog}"
            assertMenuAction 'successCard:被控服务器连接正常'
            : >"${serverActionLog}"
            manageSubscriptionServerItem edge-a </dev/null
            [[ "${serverSelectCount}" == "1" && ! -s "${serverActionLog}" ]]
            (
                addSubscriptionSourceState edge-c "Edge C" 10.77.0.4 39778
                manageSubscriptionServerItem edge-a <<<"7

3
8"
                [[ "${serverSelectCount}" == "2" && "$(<"${serverActionLog}")" == 'health:edge-a' ]]
            )
            subscriptionActiveGroupWrite --argjson sources "${serverSourcesJson}" '.sources = $sources'
            : >"${serverActionLog}"
            serverHealthOk=false
            resetMenuActions
            manageSubscriptionServerItem edge-a >"${serverStdoutLog}" <<<"3
8"
            serverHealthObjectError=true
            manageSubscriptionServerItem edge-a >>"${serverStdoutLog}" <<<"3
8"
            [[ "$(<"${serverActionLog}")" == $'health:edge-a\nhealth:edge-a' ]]
            assertMenuAction 'errorCard:被控服务器连接检查失败'
            ! grep -qF 'secret-health-token' "${serverStdoutLog}"
            ! grep -qF 'secret-health-token' "${serverCardLog}"
            grep -qF '控制 Token 验证失败（HTTP 401）' "${serverCardLog}"
        )
        (
            local PADM_SUBSCRIPTION_GROUPS_DIR="${TMP_DIR}/server-item-remove-groups"
            local serverActionLog="${TMP_DIR}/server-item-remove-actions.log"
            local sourceSnapshot=
            mkdir -p "${PADM_SUBSCRIPTION_GROUPS_DIR}"
            writeDefaultSubscriptionGroupsState "$(subscriptionGroupsFile)"
            addSubscriptionSourceState edge-a "Edge A" 10.77.0.2 39778
            sourceSnapshot=$(subscriptionActiveGroupRead -c 'first(.sources[] | select(.id == "edge-a"))')
            autoRead() { read -r "$3"; }
            setSubscriptionRemoteSourceEnabled() {
                printf 'enabled:%s:%s\n' "$1" "$2" >>"${serverActionLog}"
            }
            subscriptionWireGuardRemovePeerAndSource() {
                command jq -e --arg id "$1" '.id == $id' <<<"$2" >/dev/null
                printf 'remove:%s\n' "$1" >>"${serverActionLog}"
                subscriptionActiveGroupWrite --arg id "$1" '.sources |= map(select(.id != $id))'
            }
            runSubscriptionSyncAfterMutation() {
                [[ "${3:-}" == "true" ]]
                printf 'sync\n' >>"${serverActionLog}"
                return 1
            }
            subscriptionRemoteControlHealth() {
                printf 'health\n' >>"${serverActionLog}"
                printf '{"ok":true}\n'
            }
            removeSubscriptionControlledServerMenu() { originalRemoveSubscriptionControlledServerMenu "$@"; }
            : >"${serverActionLog}"
            regressionExpectStatus 1 originalChangeSubscriptionSourceEnabledMenu edge-a "${sourceSnapshot}" false </dev/null
            regressionExpectStatus 1 originalChangeSubscriptionSourceEnabledMenu edge-a "${sourceSnapshot}" false < <(printf y)
            regressionExpectStatus 1 originalRemoveSubscriptionControlledServerMenu edge-a "${sourceSnapshot}" </dev/null
            regressionExpectStatus 1 originalRemoveSubscriptionControlledServerMenu edge-a "${sourceSnapshot}" < <(printf yes)
            [[ ! -s "${serverActionLog}" ]]
            manageSubscriptionServerItem edge-a <<<"6
yes
3"
            [[ "$(<"${serverActionLog}")" == $'remove:edge-a\nsync' ]]
            subscriptionActiveGroupRead -e 'all(.sources[]; .id != "edge-a")' >/dev/null
        )
        resetMenuActions
        manageSubscriptionStateBackups <<<"1
5"
        assertMenuAction showSubscriptionGroupsStateSummary
        resetMenuActions
        manageSubscriptionStateBackups <<<"2
5"
        assertMenuAction createSubscriptionGroupsBackupMenu
        resetMenuActions
        manageSubscriptionStateBackups <<<"3
5"
        assertMenuAction restoreSubscriptionGroupsBackupMenu
        resetMenuActions
        manageSubscriptionStateBackups <<<"4
5"
        assertMenuAction resetSubscriptionGroupsStateMenu
        (
            local menuReadCount=0 backupActionCount=0
            autoRead() {
                menuReadCount=$((menuReadCount + 1))
                printf -v "$3" '%s' 4
                return 1
            }
            resetSubscriptionGroupsStateMenu() {
                backupActionCount=$((backupActionCount + 1))
            }
            manageSubscriptionStateBackups
            [[ "${menuReadCount}" == "1" ]]
            [[ "${backupActionCount}" == "0" ]]
        )
    fi

    if menuSmokePartSelected subscription-controlled; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole controlled
        resetMenuActions
        output=
        manageSubscription <<<"8"
        grep -q "接入主控" <<<"${output}"
        grep -q "查看本机状态" <<<"${output}"
        grep -q "导入/更新主控接入凭据" <<<"${output}"
        grep -q "查看控制面与 Peer 细节" <<<"${output}"
        if grep -q "发布订阅" <<<"${output}" || grep -q "多服务器协同" <<<"${output}" || grep -q "主控维护与排障" <<<"${output}"; then
            printf 'menu-smoke failed: controlled top-level still shows main entries\n' >&2
            return 1
        fi
        ! assertMenuAction menu
        resetMenuActions
        manageSubscriptionControlledHome <<<"1
invite-credential
y
8"
        assertMenuAction subscriptionWireGuardJoinInvite
        assertMenuAction showSubscriptionWireGuardJoinReceipt
        assertMenuAction showSubscriptionWireGuardStatus
        (
            local importCount=0 importedJson= mainCredential wrongCredential importStatus=0
            mainCredential=$(subscriptionWireGuardCredentialEncode main \
                '{"endpoint_host":"main.example.com","listen_port":51820,"network":"10.77.0.0/24","address":"10.77.0.1/24","public_key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="}')
            wrongCredential=$(subscriptionWireGuardCredentialEncode controlled \
                '{"address":"10.77.0.2/24","control_port":39778,"public_key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","token":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}')
            subscriptionWireGuardCredentialDecode() { originalMenuSmokeCredentialDecode "$@"; }
            subscriptionWireGuardImportMainCredentialJson() {
                importCount=$((importCount + 1))
                importedJson=$1
                return "${importStatus}"
            }
            resetMenuActions
            originalMenuSmokeImportMainCredential <<<"invalid
${wrongCredential}
${mainCredential}"
            [[ "${importCount}" == "1" ]]
            jq -e '.kind == "main" and .endpoint_host == "main.example.com"' <<<"${importedJson}" >/dev/null
            [[ "${actions}" == $'errorCard:主控接入凭据无效，请复制完整内容后重试\nerrorCard:请粘贴主控接入凭据\nsuccessCard:主控接入凭据已导入\n' ]]
            resetMenuActions
            regressionExpectStatus 1 originalMenuSmokeImportMainCredential <<<"${wrongCredential}

"
            [[ "${actions}" == $'errorCard:请粘贴主控接入凭据\n' ]]
            resetMenuActions
            regressionExpectStatus 1 originalMenuSmokeImportMainCredential <<<""
            regressionExpectStatus 1 originalMenuSmokeImportMainCredential </dev/null
            regressionExpectStatus 1 originalMenuSmokeImportMainCredential < <(printf '%s' "${mainCredential}")
            [[ "${importCount}" == "1" && -z "${actions}" ]]
            importStatus=1
            regressionExpectStatus 1 originalMenuSmokeImportMainCredential <<<"${mainCredential}
${mainCredential}"
            [[ "${importCount}" == "2" && -z "${actions}" ]]
        )
        resetMenuActions
        output=
        manageSubscriptionControlledHome <<<"2
8"
        grep -q "当前服务器角色：" <<<"${output}"
        if assertMenuAction showSubscriptionWireGuardControlledCredential || assertMenuAction showSubscriptionWireGuardJoinReceipt; then
            return 1
        fi
        assertMenuAction showSubscriptionWireGuardStatus
        resetMenuActions
        manageSubscriptionServers <<<"3" || true
        assertMenuAction 'errorCard:当前机器已初始化为被控'
        resetMenuActions
        setSubscriptionSourceControlTokenMenu <<<"" || true
        assertMenuAction 'errorCard:当前机器已初始化为被控'
        resetMenuActions
        changeSubscriptionSourceEnabledMenu <<<"" || true
        assertMenuAction 'errorCard:当前机器已初始化为被控'
        resetMenuActions
        manageSubscriptionMainHome <<<"8" || true
        assertMenuAction 'errorCard:当前机器已初始化为被控'
        resetMenuActions
        setMenuSmokeRole main
        manageSubscriptionControlledHome <<<"4" || true
        assertMenuAction 'errorCard:当前机器已初始化为主控'
        resetMenuActions
        output=
        manageSubscriptionMainHome <<<"9"
        grep -q "查看当前订阅链接" <<<"${output}"
        resetMenuActions
        output=
        manageTrafficAndQuota <<<"7"
        grep -q "刷新并显示总览" <<<"${output}"
        resetMenuActions
        setMenuSmokeRole controlled
        manageTrafficAndQuota <<<"7" || true
        assertMenuAction 'errorCard:当前机器已初始化为被控'
        resetMenuActions
        manageSubscriptionStateBackups <<<"5" || true
        assertMenuAction 'errorCard:当前机器已初始化为被控'
        resetMenuActions
        manageSubscriptionSyncSettings <<<"5" || true
        assertMenuAction 'errorCard:当前机器已初始化为被控'
        resetMenuActions
        setMenuSmokeRole uninitialized
        manageTrafficAndQuota <<<"7"
        [[ "${actions}" == $'showSubscriptionTrafficOverview\n' ]]
        resetMenuActions
        manageSubscriptionStateBackups <<<"5"
        [[ -z "${actions}" ]]
        resetMenuActions
        output=
        manageSubscriptionSyncSettings <<<"5"
        ! grep -q "立即完整同步" <<<"${output}"
        grep -q "状态与排障" <<<"${output}"
        grep -q "状态备份与恢复" <<<"${output}"
        ! grep -q "流量与限额" <<<"${output}"
        if grep -q "远端同步计划" <<<"${output}" || grep -q "事件同步" <<<"${output}"; then
            printf 'menu-smoke failed: local sync menu exposes main-only or legacy actions\n' >&2
            return 1
        fi
        [[ -z "${actions}" ]]
        resetMenuRender
        manageSubscriptionSyncDiagnostics <<<"5"
        [[ "${menuNumbers}" == $'1\n2\n3\n4\n5:return\n' ]]
        resetMenuActions
        manageSubscriptionSyncDiagnostics <<< $'6\n7\n5'
        [[ "${actions}" == $'errorCard:选择错误，请重新选择\nerrorCard:选择错误，请重新选择\n' ]]
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

        (
            coreReleaseTags() { printf 'v1.2.3\nv1.2.2\n'; }
            resetMenuActions
            xrayVersionManageMenu <<<$'3\n2\n7'
            assertMenuAction 'upgradeXrayCore:false v1.2.2'
            resetMenuActions
            singBoxVersionManageMenu <<<$'3\n2\n7'
            assertMenuAction 'upgradeSingBoxCore:false v1.2.2'
        )

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
        coreVersionManageMenu <<<"6"
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

        (
            local controlServiceProbeLog="${TMP_DIR}/core-service-control-probes.log"
            serviceInstalled() {
                printf 'installed:%s\n' "$1" >>"${controlServiceProbeLog}"
                return 0
            }
            serviceRunning() {
                printf 'running:%s\n' "$1" >>"${controlServiceProbeLog}"
                return 0
            }
            nginxReasonsMock="订阅发布"
            : >"${controlServiceProbeLog}"
            coreServiceControlMenu nginx <<<"5"
            [[ "$(grep -c '^running:nginx$' "${controlServiceProbeLog}")" == "1" ]]
        )

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
