#!/usr/bin/env bash

# 自定义 UUID
customUUID() {
    autoRead custom_uuid "请输入合法的UUID，[回车]随机UUID:" currentCustomUUID
    echo
    if [[ -z "${currentCustomUUID}" ]]; then
        if [[ "${selectInstallType}" == "1" || "${coreInstallType}" == "1" ]]; then
            currentCustomUUID=$(${ctlPath} uuid)
        elif [[ "${selectInstallType}" == "2" || "${coreInstallType}" == "2" ]]; then
            currentCustomUUID=$(${ctlPath} generate uuid)
        fi

        echoContent yellow "uuid：${currentCustomUUID}\n"

    else
        local checkUUID=
        if [[ "${coreInstallType}" == "1" ]]; then
            checkUUID=$(jq -r --arg currentUUID "$currentCustomUUID" "(.inbounds[0].settings.clients // .inbounds[1].settings.clients)[]? | select(.id == \$currentUUID) | .email" ${configPath}${frontingType:-$frontingTypeReality}.json)
        elif [[ "${coreInstallType}" == "2" ]]; then
            checkUUID=$(jq -r --arg currentUUID "$currentCustomUUID" ".inbounds[0].users[] | select(.uuid == \$currentUUID) | .name//.username" ${configPath}${frontingType}.json)
        fi

        if [[ -n "${checkUUID}" ]]; then
            errorCard "UUID不可重复"
            exit 0
        fi
    fi
}


# 自定义 Email
customUserEmail() {
    autoRead custom_email "请输入合法的email，[回车]随机email:" currentCustomEmail
    echo
    if [[ -z "${currentCustomEmail}" ]]; then
        currentCustomEmail="${currentCustomUUID}"
        echoContent yellow "email: ${currentCustomEmail}\n"
    else
        local checkEmail=
        if [[ "${coreInstallType}" == "1" ]]; then
            local frontingTypeConfig="${frontingType}"
            if currentProtocolHasAll 7 8; then
                frontingTypeConfig="07_VLESS_vision_reality_inbounds"
            fi

            checkEmail=$(jq -r --arg currentEmail "$currentCustomEmail" "(.inbounds[0].settings.clients // .inbounds[1].settings.clients)[]? | select(.email == \$currentEmail) | .email" ${configPath}${frontingTypeConfig:-$frontingTypeReality}.json)
        elif
            [[ "${coreInstallType}" == "2" ]]
        then
            checkEmail=$(jq -r --arg currentEmail "$currentCustomEmail" ".inbounds[0].users[] | select(.name == \$currentEmail) | .name" ${configPath}${frontingType}.json)
        fi

        if [[ -n "${checkEmail}" ]]; then
            errorCard "email不可重复"
            exit 0
        fi
    fi
}


writeUserConfigJq() {
    local targetPath=$1
    local jqFilter=$2
    local tmpPath="${targetPath}.tmp"
    shift 2
    if ! jq -r "$@" "${jqFilter}" "${targetPath}" | jq . >"${tmpPath}"; then
        rm -f "${tmpPath}"
        return 1
    fi
    mv "${tmpPath}" "${targetPath}"
}

removeUserAccountName() {
    local label=$1
    echo "${label%%-*}"
}

removeUserFromConfigFile() {
    local targetPath=$1
    local userPath=$2
    local targetId=$3
    local targetAccount=$4
    local jqFilter=
    [[ -f "${targetPath}" ]] || return 0
    jqFilter="${userPath} = ((${userPath} // []) | map(select(((\$targetId == \"\") or ((.id // .uuid // .password // \"\") != \$targetId)) and ((\$targetAccount == \"\") or (((.email // .name // .username // \"\") | split(\"-\")[0]) != \$targetAccount)))))"
    writeUserConfigJq "${targetPath}" "${jqFilter}" --arg targetId "${targetId}" --arg targetAccount "${targetAccount}"
}

removeUserFromConfigFiles() {
    local targetId=$1
    local targetAccount=$2
    local configFile=
    removeUserFromConfigFile "${configPath}02_VLESS_TCP_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}"
    removeUserFromConfigFile "${configPath}03_VLESS_WS_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}"
    removeUserFromConfigFile "${configPath}04_trojan_gRPC_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}"
    removeUserFromConfigFile "${configPath}05_VMess_WS_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}"
    removeUserFromConfigFile "${configPath}06_VLESS_gRPC_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}"
    removeUserFromConfigFile "${configPath}04_trojan_TCP_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}"
    removeUserFromConfigFile "${configPath}07_VLESS_vision_reality_inbounds.json" ".inbounds[1].settings.clients" "${targetId}" "${targetAccount}"
    removeUserFromConfigFile "${configPath}08_VLESS_vision_gRPC_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}"
    removeUserFromConfigFile "${singBoxConfigPath}06_hysteria2_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}"
    removeUserFromConfigFile "${singBoxConfigPath}09_tuic_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}"
    removeUserFromConfigFile "${singBoxConfigPath}10_naive_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}"
    removeUserFromConfigFile "${configPath}11_VMess_HTTPUpgrade_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}"
    removeUserFromConfigFile "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}"
    removeUserFromConfigFile "${configPath}13_anytls_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}"
    removeUserFromConfigFile "${singBoxConfigPath}13_anytls_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}"
}

# 添加用户
addUser() {
    autoRead add_user_count "请输入要添加的用户数量:" userNum
    echo
    if [[ -z ${userNum} || ${userNum} -le 0 ]]; then
        errorCard "输入有误，请重新输入"
        exit 0
    fi
    local userConfig=
    if [[ "${coreInstallType}" == "1" ]]; then
        userConfig=".inbounds[0].settings.clients"
    elif [[ "${coreInstallType}" == "2" ]]; then
        userConfig=".inbounds[0].users"
    fi

    while [[ ${userNum} -gt 0 ]]; do
        readConfigHostPathUUID
        local users=
        ((userNum--)) || true

        customUUID
        customUserEmail

        uuid=${currentCustomUUID}
        email=${currentCustomEmail}

        # VLESS TCP
        if currentProtocolHas 0; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 0 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 0 "${uuid}" "${email}")
            fi
            writeUserConfigJq "${configPath}02_VLESS_TCP_inbounds.json" "${userConfig} = ${clients}"
        fi

        # VLESS WS
        if currentProtocolHas 1; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 1 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 1 "${uuid}" "${email}")
            fi

            writeUserConfigJq "${configPath}03_VLESS_WS_inbounds.json" "${userConfig} = ${clients}"
        fi

        # Trojan gRPC
        if currentProtocolHas 2; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 2 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 2 "${uuid}" "${email}")
            fi

            writeUserConfigJq "${configPath}04_trojan_gRPC_inbounds.json" "${userConfig} = ${clients}"
        fi
        # VMess WS
        if currentProtocolHas 3; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 3 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 3 "${uuid}" "${email}")
            fi

            writeUserConfigJq "${configPath}05_VMess_WS_inbounds.json" "${userConfig} = ${clients}"
        fi
        # Trojan TCP
        if currentProtocolHas 4; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 4 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 4 "${uuid}" "${email}")
            fi
            writeUserConfigJq "${configPath}04_trojan_TCP_inbounds.json" "${userConfig} = ${clients}"
        fi

        # VLESS gRPC
        if currentProtocolHas 5; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 5 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 5 "${uuid}" "${email}")
            fi
            writeUserConfigJq "${configPath}06_VLESS_gRPC_inbounds.json" "${userConfig} = ${clients}"
        fi

        # VLESS Reality Vision
        if currentProtocolHas 7; then
            local clients=
            local realityUserConfig=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 7 "${uuid}" "${email}")
                realityUserConfig=".inbounds[1].settings.clients"
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 7 "${uuid}" "${email}")
                realityUserConfig=".inbounds[0].users"
            fi
            writeUserConfigJq "${configPath}07_VLESS_vision_reality_inbounds.json" "${realityUserConfig} = ${clients}"
        fi

        # VLESS Reality gRPC
        if currentProtocolHas 8; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 8 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 8 "${uuid}" "${email}")
            fi
            writeUserConfigJq "${configPath}08_VLESS_vision_gRPC_inbounds.json" "${userConfig} = ${clients}"
        fi

        # hysteria2
        if currentProtocolHas 6; then
            local clients=

            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 6 "${uuid}" "${email}")
            elif [[ -n "${singBoxConfigPath}" ]]; then
                clients=$(initSingBoxClients 6 "${uuid}" "${email}")
            fi

            writeUserConfigJq "${singBoxConfigPath}06_hysteria2_inbounds.json" ".inbounds[0].users = ${clients}"
        fi

        # TUIC
        if currentProtocolHas 9; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 9 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 9 "${uuid}" "${email}")
            fi

            writeUserConfigJq "${singBoxConfigPath}09_tuic_inbounds.json" ".inbounds[0].users = ${clients}"
        fi
        # Naive
        if currentProtocolHas 10; then
            local clients=
            clients=$(initSingBoxClients 10 "${uuid}" "${email}")
            writeUserConfigJq "${singBoxConfigPath}10_naive_inbounds.json" ".inbounds[0].users = ${clients}"
        fi
        # VMess HTTPUpgrade
        if currentProtocolHas 11; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 11 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 11 "${uuid}" "${email}")
            fi

            writeUserConfigJq "${configPath}11_VMess_HTTPUpgrade_inbounds.json" "${userConfig} = ${clients}"
        fi
        # AnyTLS
        if currentProtocolHas 13; then
            local clients=
            clients=$(initSingBoxClients 13 "${uuid}" "${email}")

            writeUserConfigJq "${configPath}13_anytls_inbounds.json" "${userConfig} = ${clients}"
        fi
    done
    reloadCore
    successCard "添加完成"
    readNginxSubscribe
    if [[ -n "${subscribePort}" ]]; then
        subscribe false
    fi
    manageSubscription 1
}

# 移除用户
removeUser() {
    local userFile=
    local userPath=
    local userCount=
    local delUserIndex=
    local targetUser=
    local targetId=
    local targetLabel=
    local targetAccount=

    if [[ "${coreInstallType}" == "1" ]]; then
        userFile="${configPath}${frontingType:-$frontingTypeReality}.json"
        userPath=".inbounds[0].settings.clients // .inbounds[1].settings.clients"
        jq -r -c "${userPath}[]? | .email" "${userFile}" | awk '{print NR"":"$0}'
        autoRead delete_user_index "请选择要删除的用户编号[仅支持单个删除]:" delUserIndex
        userCount=$(jq -r "(${userPath})? | length" "${userFile}")
    elif [[ "${coreInstallType}" == "2" ]]; then
        userFile="${configPath}${frontingType:-$frontingTypeReality}.json"
        userPath=".inbounds[0].users"
        jq -r -c '.inbounds[0].users[]? | .name // .username' "${userFile}" | awk '{print NR"":"$0}'
        autoRead delete_user_index "请选择要删除的用户编号[仅支持单个删除]:" delUserIndex
        userCount=$(jq -r '.inbounds[0].users | length' "${userFile}")
    fi

    if [[ -z "${delUserIndex}" ]] || ! echo "${delUserIndex}" | grep -qE '^[0-9]+$' || [[ "${delUserIndex}" -lt 1 || "${delUserIndex}" -gt "${userCount}" ]]; then
        errorCard "选择错误"
        manageSubscription 1
        return 1
    fi

    delUserIndex=$((delUserIndex - 1))
    targetUser=$(jq -r -c "(${userPath})[${delUserIndex}]" "${userFile}")
    targetId=$(echo "${targetUser}" | jq -r '.id // .uuid // .password // ""')
    targetLabel=$(echo "${targetUser}" | jq -r '.email // .name // .username // ""')
    targetAccount=$(removeUserAccountName "${targetLabel}")

    removeUserFromConfigFiles "${targetId}" "${targetAccount}"
    reloadCore
    readNginxSubscribe
    if [[ -n "${subscribePort}" ]]; then
        subscribe false
    fi
    manageSubscription 1
}

# 订阅组本机账号同步
subscriptionSyncAccountName() {
    local id=$1
    id=${id//-/_}
    echo "sub_${id}"
}

subscriptionSyncGenerateUUID() {
    if [[ "${coreInstallType}" == "1" && -x "${ctlPath}" ]]; then
        ${ctlPath} uuid
    elif [[ "${coreInstallType}" == "2" && -x "${ctlPath}" ]]; then
        ${ctlPath} generate uuid
    elif command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr 'A-Z' 'a-z'
    elif [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        printf '%04x%04x-%04x-%04x-%04x-%04x%04x%04x\n' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM"
    fi
}

ensureUserSubscriptionUUID() {
    local id=$1
    local groupId
    local userUUID
    groupId=$(activeSubscriptionGroupId)
    userUUID=$(subscriptionGroupsStateRead -r --arg groupId "${groupId}" --arg id "${id}" '.groups[] | select(.id == $groupId) | .user_groups[]? | select(.id == $id) | .uuid // empty')
    if [[ -z "${userUUID}" ]]; then
        userUUID=$(subscriptionSyncGenerateUUID)
        subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg id "${id}" --arg uuid "${userUUID}" '.groups |= map(if .id == $groupId then .user_groups |= map(if .id == $id then .uuid = $uuid else . end) else . end)'
    fi
    echo "${userUUID}"
}

subscriptionSyncDesiredLocalUsers() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" '
      .groups[] | select(.id == $groupId) | .user_groups[]?
      | select(.enabled == true)
      | select((.allowed_sources | index("main")) or (.allowed_sources | index("*")))
      | .id'
}

subscriptionSyncCurrentManagedUsers() {
    local file=$1
    [[ -f "${file}" ]] || return
    jq -r '
      [(.inbounds[]?.settings.clients[]?), (.inbounds[]?.users[]?)][]
      | ((.email // .name // .username // "") | split("-")[0])
      | select(startswith("sub_"))' "${file}" 2>/dev/null | sort -u
}

subscriptionSyncConfigFiles() {
    local file
    for file in "${configPath}"*inbounds.json; do
        [[ -f "${file}" ]] && echo "${file}"
    done
    if [[ -n "${singBoxConfigPath}" && "${singBoxConfigPath}" != "${configPath}" ]]; then
        for file in "${singBoxConfigPath}"*inbounds.json; do
            [[ -f "${file}" ]] && echo "${file}"
        done
    fi
}

subscriptionSyncConfiguredManagedUsers() {
    local file
    while IFS= read -r file; do
        subscriptionSyncCurrentManagedUsers "${file}"
    done < <(subscriptionSyncConfigFiles) | sort -u
}

subscriptionSyncPlan() {
    local desiredAccounts
    local currentAccounts
    desiredAccounts=$(while IFS= read -r id; do subscriptionSyncAccountName "${id}"; done < <(subscriptionSyncDesiredLocalUsers) | sort -u)
    currentAccounts=$(subscriptionSyncConfiguredManagedUsers)
    jq -n --argjson desired "$(printf '%s\n' "${desiredAccounts}" | jq -R -s 'split("\n") | map(select(length > 0))')" --argjson current "$(printf '%s\n' "${currentAccounts}" | jq -R -s 'split("\n") | map(select(length > 0))')" '{create: ($desired - $current), remove: ($current - $desired)}'
}

subscriptionSyncRemoveAccountFromFile() {
    local file=$1
    local accountName=$2
    local tmpFile="${file}.tmp"
    [[ -f "${file}" ]] || return
    if ! jq -e --arg accountName "${accountName}" '
      [(.inbounds[]?.settings.clients[]?), (.inbounds[]?.users[]?)][]
      | select(((.email // .name // .username // "") | split("-")[0]) == $accountName)' "${file}" >/dev/null 2>&1; then
        return
    fi
    jq --arg accountName "${accountName}" '
      (.inbounds[]?.settings.clients? // empty) |= map(select(((.email // .name // .username // "") | split("-")[0]) != $accountName)) |
      (.inbounds[]?.users? // empty) |= map(select(((.email // .name // .username // "") | split("-")[0]) != $accountName))' "${file}" >"${tmpFile}" && mv "${tmpFile}" "${file}"
}

subscriptionSyncRemoveAccount() {
    local accountName=$1
    local file
    while IFS= read -r file; do
        subscriptionSyncRemoveAccountFromFile "${file}" "${accountName}"
    done < <(subscriptionSyncConfigFiles)
}

subscriptionSyncSetUsersInFile() {
    local file=$1
    local userPath=$2
    local users=$3
    local tmpFile="${file}.tmp"
    [[ -f "${file}" ]] || return
    jq --argjson users "${users}" "${userPath} = \$users" "${file}" >"${tmpFile}" && mv "${tmpFile}" "${file}"
}

subscriptionSyncUserPath() {
    local file=$1
    local preferredPath=$2
    if [[ -n "${preferredPath}" ]]; then
        echo "${preferredPath}"
    elif jq -e '.inbounds[1].settings.clients' "${file}" >/dev/null 2>&1; then
        echo '.inbounds[1].settings.clients'
    elif jq -e '.inbounds[0].settings.clients' "${file}" >/dev/null 2>&1; then
        echo '.inbounds[0].settings.clients'
    else
        echo '.inbounds[0].users'
    fi
}

subscriptionSyncAppendProtocolUser() {
    local protocolId=$1
    local file=$2
    local preferredPath=$3
    local uuid=$4
    local accountName=$5
    local clients=
    local userPath=
    [[ -f "${file}" ]] || return
    userPath=$(subscriptionSyncUserPath "${file}" "${preferredPath}")
    if jq -e --arg accountName "${accountName}" "${userPath}[]? | select(((.email // .name // .username // \"\") | split(\"-\")[0]) == \$accountName)" "${file}" >/dev/null 2>&1; then
        return
    fi
    currentClients=$(jq -r "${userPath} // []" "${file}")
    if [[ "${coreInstallType}" == "2" ]]; then
        clients=$(initSingBoxClients "${protocolId}" "${uuid}" "${accountName}")
    else
        clients=$(initXrayClients "${protocolId}" "${uuid}" "${accountName}")
    fi
    subscriptionSyncSetUsersInFile "${file}" "${userPath}" "${clients}"
}

subscriptionSyncAppendLocalUser() {
    local id=$1
    local accountName
    local uuid
    accountName=$(subscriptionSyncAccountName "${id}")
    uuid=$(ensureUserSubscriptionUUID "${id}")

    subscriptionSyncAppendProtocolUser 0 "${configPath}02_VLESS_TCP_inbounds.json" '' "${uuid}" "${accountName}"
    subscriptionSyncAppendProtocolUser 1 "${configPath}03_VLESS_WS_inbounds.json" '' "${uuid}" "${accountName}"
    subscriptionSyncAppendProtocolUser 2 "${configPath}04_trojan_gRPC_inbounds.json" '' "${uuid}" "${accountName}"
    subscriptionSyncAppendProtocolUser 3 "${configPath}05_VMess_WS_inbounds.json" '' "${uuid}" "${accountName}"
    subscriptionSyncAppendProtocolUser 4 "${configPath}04_trojan_TCP_inbounds.json" '' "${uuid}" "${accountName}"
    subscriptionSyncAppendProtocolUser 5 "${configPath}06_VLESS_gRPC_inbounds.json" '' "${uuid}" "${accountName}"
    subscriptionSyncAppendProtocolUser 7 "${configPath}07_VLESS_vision_reality_inbounds.json" '' "${uuid}" "${accountName}"
    subscriptionSyncAppendProtocolUser 8 "${configPath}08_VLESS_vision_gRPC_inbounds.json" '' "${uuid}" "${accountName}"
    subscriptionSyncAppendProtocolUser 11 "${configPath}11_VMess_HTTPUpgrade_inbounds.json" '' "${uuid}" "${accountName}"
    subscriptionSyncAppendProtocolUser 12 "${configPath}12_VLESS_XHTTP_inbounds.json" '' "${uuid}" "${accountName}"
    subscriptionSyncAppendProtocolUser 13 "${configPath}13_anytls_inbounds.json" '' "${uuid}" "${accountName}"
    if [[ "${singBoxConfigPath}" != "${configPath}" ]]; then
        subscriptionSyncAppendProtocolUser 6 "${singBoxConfigPath}06_hysteria2_inbounds.json" '' "${uuid}" "${accountName}"
        subscriptionSyncAppendProtocolUser 9 "${singBoxConfigPath}09_tuic_inbounds.json" '' "${uuid}" "${accountName}"
        subscriptionSyncAppendProtocolUser 10 "${singBoxConfigPath}10_naive_inbounds.json" '' "${uuid}" "${accountName}"
    fi
}

subscriptionSyncAccountId() {
    local accountName=$1
    accountName=${accountName#sub_}
    echo "${accountName//_/-}"
}

subscriptionSyncAppendLocalAccount() {
    local accountName=$1
    subscriptionSyncAppendLocalUser "$(subscriptionSyncAccountId "${accountName}")"
}

subscriptionSyncMarkResult() {
    local status=$1
    local failures=$2
    local groupId
    local now
    groupId=$(activeSubscriptionGroupId)
    now=$(date '+%Y-%m-%d %H:%M:%S')
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg now "${now}" --arg status "${status}" --argjson failures "${failures}" '.groups |= map(if .id == $groupId then .sync.last_run = $now | .sync.last_status = $status | .sync.failures = $failures else . end)'
}

runSubscriptionGroupSync() {
    local skipSubscribeRefresh=${1:-}
    local id
    local accountName
    local failures='[]'
    local remoteFailures='[]'
    local syncPlan
    local quotaPlan='[]'
    ensureSubscriptionGroupsState
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID

    if subscriptionGroupQuotaAutoApplyEnabled; then
        if collectSubscriptionTraffic; then
            quotaPlan=$(subscriptionQuotaDryRunPlan)
            if [[ "$(jq 'length' <<<"${quotaPlan}")" != "0" ]]; then
                applySubscriptionQuotaPlan "${quotaPlan}"
                applySubscriptionQuotaPlanAccounts "${quotaPlan}"
            fi
        else
            failures=$(jq '. + ["限额自动执行前流量统计刷新失败"]' <<<"${failures}")
        fi
    fi

    syncPlan=$(subscriptionSyncPlan)
    while IFS= read -r accountName; do
        subscriptionSyncRemoveAccount "${accountName}"
    done < <(echo "${syncPlan}" | jq -r '.remove[]?')

    while IFS= read -r accountName; do
        subscriptionSyncAppendLocalAccount "${accountName}"
    done < <(echo "${syncPlan}" | jq -r '.create[]?')

    if subscriptionGroupRemoteSyncEnabled; then
        remoteFailures=$(runSubscriptionRemoteSync)
        failures=$(jq -n --argjson failures "${failures}" --argjson remoteFailures "${remoteFailures}" '$failures + $remoteFailures')
    fi

    reloadCore
    readNginxSubscribe
    installSubscriptionControlService
    if ensureSubscriptionControlNginxLocation; then
        serviceQueueRestart nginx
        serviceQueueApply
    fi
    if [[ -n "${subscribePort}" && -z "${skipSubscribeRefresh}" ]]; then
        subscribe false
    fi

    collectSubscriptionTraffic

    if [[ "${failures}" == "[]" ]]; then
        subscriptionSyncMarkResult success "${failures}"
        successCard "自动同步完成"
    else
        subscriptionSyncMarkResult partial "${failures}"
        statusCard "订阅同步" "本机自动同步完成，被控服务器待后续通道同步"
    fi
}

# 订阅与用户入口
manageSubscription() {
    progressCard "1" "订阅与用户"
    if [[ -z "${configPath}" ]]; then
        errorCard "未安装"
        exit 0
    fi

    while true; do
        echoContent title "\n┌─ 订阅与用户 ───────────────────────────────────────"
        menuLine "先安装/更新订阅服务，再查看链接、给别人开订阅或配置主控/被控同步"
        menuLine "groups.json 是用户订阅、服务器源、同步计划和流量统计的状态真源"
        menuLine "常用路径：订阅服务 -> 我的订阅；共享给别人时走 给别人开订阅 -> 立即同步"
        menuItem 1 "订阅服务" "安装/更新订阅发布服务，确认链接入口可用"
        menuItem 2 "我的订阅" "自用链接、可用服务器和我的流量"
        menuItem 3 "给别人开订阅" "创建用户订阅、同步托管账号并查看链接"
        menuItem 4 "多服务器订阅" "本机作为主控，管理远端被控服务器、Token 和同步结果"
        menuItem 5 "流量与限额" "刷新/查看流量、查看和执行限额计划"
        menuItem 6 "自动同步与备份" "自动同步、手动同步、同步计划和状态备份"
        menuReturnItem 7 "返回主菜单" "回到 padm 管理面板"
        menuClose
        autoRead subscription_menu "请选择:" manageSubscriptionStatus
        case "${manageSubscriptionStatus}" in
        1) manageSubscriptionService ;;
        2) manageMySubscription ;;
        3) manageSharedSubscriptions ;;
        4) manageMultiServerSubscriptions ;;
        5) manageTrafficAndQuota ;;
        6) manageSubscriptionAutomation ;;
        7) menu; return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

manageSubscriptionService() {
    while true; do
        echoContent title "\n┌─ 订阅服务 ─────────────────────────────────────────"
        menuLine "订阅服务负责把订阅链接发布出去；未安装时，生成了链接也无法公网访问"
        menuLine "建议首次进入先安装/更新订阅发布服务，再查看自用或用户订阅链接"
        menuItem 1 "安装/更新订阅发布服务" "安装或刷新 Nginx 订阅发布配置"
        menuItem 2 "查看/刷新我的订阅链接" "重新生成并输出当前自用订阅"
        menuItem 3 "查看本机被控凭据" "本机被其他主控添加时复制给对方填写"
        menuItem 4 "查看订阅服务状态" "显示当前订阅发布端口和域名"
        menuReturnItem 5 "返回订阅与用户" "回到上级菜单"
        menuClose
        autoRead subscription_service_menu "请选择:" subscriptionServiceStatus
        case "${subscriptionServiceStatus}" in
        1) installSubscribe ;;
        2) subscribe ;;
        3) showSubscriptionControlToken ;;
        4) showSubscriptionServiceStatus ;;
        5) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

showSubscriptionControlToken() {
    local token
    local controlHost
    local credential
    token=$(subscriptionControlToken)
    readNginxSubscribe
    controlHost=${subscribeDomain:-${currentHost:-}}
    if [[ -n "${controlHost}" && -n "${subscribePort}" ]]; then
        credential=$(subscriptionControlCredentialEncode "${controlHost}" "${subscribePort}" "${token}")
        statusCard "本机被控凭据" "被控凭据：${credential}" "被控地址：${controlHost}:${subscribePort}" "主控端添加被控服务器时粘贴这串凭据，再设置别名" "凭据包含地址、订阅端口和 Token，请只复制给可信主控端"
    else
        statusCard "本机被控凭据" "被控凭据：暂不可生成" "Token：${token}" "未检测到订阅服务地址或端口，请先进入 订阅服务 -> 安装/更新订阅发布服务" "请只复制给可信主控端"
    fi
}

showSubscriptionServiceStatus() {
    readNginxSubscribe
    if [[ -n "${subscribePort}" ]]; then
        statusCard "订阅服务" "状态：已配置" "协议：${subscribeType:-https}" "域名：${subscribeDomain:-${currentHost:-未读取}}" "端口：${subscribePort}"
    else
        statusCard "订阅服务" "状态：未检测到可用订阅发布配置" "请先进入 订阅服务 -> 安装/更新订阅发布服务"
    fi
}

manageMySubscription() {
    while true; do
        echoContent title "\n┌─ 我的订阅 ────────────────────────────────────────"
        menuLine "这里是脚本安装账号/自用账号的订阅入口；查看链接会沿用当前 Salt"
        menuLine "如果要更换订阅链接路径，请使用刷新入口并重新设置 Salt"
        menuLine "如果订阅服务未安装，请先返回 订阅服务 安装发布入口"
        menuItem 1 "查看我的订阅链接" "沿用当前 Salt，输出当前自用订阅"
        menuItem 2 "重新生成我的订阅链接" "重新生成本地账号订阅，可选择沿用或更换 Salt"
        menuItem 3 "查看我的可用服务器" "查看可用服务器源"
        menuItem 4 "查看我的流量" "查看自用账号流量统计"
        menuReturnItem 5 "返回订阅与用户" "回到上级菜单"
        menuClose
        autoRead my_subscription_menu "请选择:" mySubscriptionStatus
        case "${mySubscriptionStatus}" in
        1) subscribe false ;;
        2) subscribe ;;
        3) showSubscriptionSources ;;
        4) showAdminSubscriptionTraffic ;;
        5) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

manageAdminSubscription() {
    manageMySubscription
}

manageSharedSubscriptions() {
    ensureSubscriptionGroupsState
    while true; do
        echoContent title "\n┌─ 给别人开订阅 ─────────────────────────────────────"
        menuLine "给别人发独立订阅链接：先创建一个订阅对象，再同步生成托管账号 sub_<ID>"
        menuLine "服务器范围只决定这个订阅里包含哪些节点；main 是本机，* 是全部已添加服务器"
        menuLine "首次使用请先确认 订阅服务 已安装；一键流程会同步后只刷新一次链接"
        menuItem 1 "一键创建并生成链接" "填写 ID/名称、节点范围、流量上限，然后同步并输出链接"
        menuItem 2 "查看已开的订阅" "列出已创建的分享订阅"
        menuItem 3 "管理已开的订阅" "改节点范围、流量、启停或删除"
        menuItem 4 "只执行同步" "只把已有订阅变更应用到本机和被控服务器"
        menuItem 5 "预览本机变更" "查看将创建/删除哪些 sub_ 托管账号"
        menuReturnItem 6 "返回订阅与用户" "回到上级菜单"
        menuClose
        autoRead shared_subscription_menu "请选择:" sharedSubscriptionStatus
        case "${sharedSubscriptionStatus}" in
        1) createAndSyncUserSubscriptionWizard ;;
        2) showUserSubscriptions ;;
        3) manageUserSubscriptionItem ;;
        4) runSubscriptionGroupSync ;;
        5)
            readInstallType
            readInstallProtocolType
            userJsonCard "本机同步计划" "$(subscriptionSyncPlan)"
            ;;
        6) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

manageUserSubscription() {
    manageSharedSubscriptions
}

userResultCard() {
    local title=$1
    echoContent title "\n┌─ ${title} ─────────────────────────────────────────"
}

userJsonCard() {
    local title=$1
    local json=$2
    userResultCard "${title}"
    printf '%s\n' "${json}" | jq .
    menuClose
}
showUserSubscriptions() {
    local groupId
    local output
    groupId=$(activeSubscriptionGroupId)
    ensureSubscriptionGroupsState
    output=$(subscriptionGroupsStateRead -r --arg groupId "${groupId}" '
      def quotaStatus($userGroup; $traffic):
        if ($userGroup.traffic_limit_gb // 0) <= 0 then
          "不限额"
        else
          ((($userGroup.traffic_limit_gb * 1024 * 1024 * 1024) | floor) as $limitBytes |
           (((($traffic.upload // 0) + ($traffic.download // 0)) * 100 / $limitBytes) | floor) as $percent |
           if $percent >= 100 then "已超限(" + ($percent | tostring) + "%)"
           elif $percent >= 80 then "接近上限(" + ($percent | tostring) + "%)"
           else "正常(" + ($percent | tostring) + "%)" end)
        end;
      .groups[] | select(.id == $groupId) |
      . as $group |
      .user_groups[]? |
      "\(.id):\(.name):\(.enabled):\(.allowed_sources | join(",")):\(.traffic_limit_gb):\(quotaStatus(.; $group.traffic.user_groups[.id] // {upload:0, download:0}))"')
    if [[ -z "${output}" ]]; then
        statusCard "用户订阅" "暂无用户订阅"
        return
    fi
    userResultCard "用户订阅列表"
    while IFS=: read -r id name enabled sources limit quota; do
        menuLine "ID：$(uiStyle value "${id}")"
        menuLine "名称：$(uiStyle value "${name}")"
        if [[ "${enabled}" == "true" ]]; then
            menuLine "状态：$(uiStyle ok "${enabled}")"
        else
            menuLine "状态：$(uiStyle warn "${enabled}")"
        fi
        menuLine "可用服务器：$(uiStyle value "${sources}")"
        menuLine "流量上限GB：$(uiStyle value "${limit}")"
        case "${quota}" in
        已超限*) menuLine "限额状态：$(uiStyle danger "${quota}")" ;;
        接近上限*) menuLine "限额状态：$(uiStyle warn "${quota}")" ;;
        正常*) menuLine "限额状态：$(uiStyle ok "${quota}")" ;;
        *) menuLine "限额状态：$(uiStyle muted "${quota}")" ;;
        esac
    done <<<"${output}"
    menuClose
}

createUserSubscription() {
    local id=
    local name=
    autoRead user_subscription_id "请输入分享订阅ID[只用于管理，例 team-a]:" id
    autoRead user_subscription_name "请输入显示名称[例 家人A/团队A]:" name
    if [[ -z "${id}" || -z "${name}" ]] || ! echo "${id}" | grep -qE '^[a-zA-Z0-9_-]+$'; then
        errorCard "输入有误，ID 只能包含英文、数字、下划线或短横线，名称不能为空"
        return 1
    fi
    addUserSubscriptionState "${id}" "${name}"
    successCard "用户订阅已创建"
}

createAndSyncUserSubscriptionWizard() {
    local id=
    local name=
    local sourceIds=main
    local sourceJson=
    local limit=0
    local confirm=
    local enableSync=
    autoRead user_subscription_id "请输入分享订阅ID[只用于管理，例 team-a]:" id
    autoRead user_subscription_name "请输入显示名称[例 家人A/团队A]:" name
    if [[ -z "${id}" || -z "${name}" ]] || ! echo "${id}" | grep -qE '^[a-zA-Z0-9_-]+$'; then
        errorCard "输入有误，ID 只能包含英文、数字、下划线或短横线，名称不能为空"
        return 1
    fi

    userResultCard "这个订阅可使用的服务器"
    menuLine "这里不是填写用户 ID，而是选择订阅里包含哪些节点"
    menuLine "main 表示本机；被控服务器需先在 多服务器订阅 中添加；* 表示全部已添加服务器"
    menuLine "多个服务器用英文逗号分隔，例如 main,remote-a"
    listSubscriptionSources
    menuClose
    autoRead user_subscription_sources "请输入服务器范围[回车默认 main]:" sourceIds
    sourceIds=${sourceIds:-main}
    sourceJson=$(printf '%s' "${sourceIds}" | jq -R 'split(",") | map(gsub("^ +| +$"; "")) | map(select(length > 0))')
    if [[ "$(jq 'length' <<<"${sourceJson}")" == "0" ]]; then
        errorCard "服务器范围不能为空；直接回车使用本机 main"
        return 1
    fi

    autoRead user_subscription_traffic_limit "请输入流量上限GB[回车/0为不限，只用于统计和限额策略]:" limit
    limit=${limit:-0}
    if ! echo "${limit}" | grep -qE '^[0-9]+$'; then
        errorCard "流量上限必须是数字"
        return 1
    fi

    addUserSubscriptionState "${id}" "${name}"
    setUserSubscriptionSources "${id}" "${sourceJson}"
    setUserSubscriptionTrafficLimit "${id}" "${limit}"
    statusCard "分享订阅已创建" "订阅ID：${id}" "显示名称：${name}" "实际托管账号：$(subscriptionSyncAccountName "${id}")" "服务器范围：${sourceIds}" "流量上限GB：${limit}"

    if ! subscriptionGroupSyncEnabled; then
        autoRead user_subscription_enable_auto_sync "是否开启后续自动同步？[yes/no，默认 yes]：" enableSync
        enableSync=${enableSync:-yes}
        if [[ "${enableSync}" == "yes" || "${enableSync}" == "y" ]]; then
            subscriptionGroupsStateWrite --arg groupId "$(activeSubscriptionGroupId)" '.groups |= map(if .id == $groupId then .sync.enabled = true else . end)'
            refreshSubscriptionGroupSyncCron
            successCard "自动同步已开启" "后续会按当前间隔自动同步；可在 自动同步与备份 -> 自动同步设置 中调整间隔"
        else
            statusCard "自动同步未开启" "本次仍可立即同步一次；后续变更需手动同步，或到 自动同步与备份 中开启"
        fi
    fi

    autoRead user_subscription_sync_now "现在同步并生成订阅链接？[yes/no，默认 yes]:" confirm
    confirm=${confirm:-yes}
    if [[ "${confirm}" == "yes" || "${confirm}" == "y" ]]; then
        runSubscriptionGroupSync skip-subscribe-refresh || return 1
        showUserSubscriptionLinks "${id}"
    else
        statusCard "稍后同步" "该订阅已保存；之后可在 给别人开订阅 -> 只执行同步 中生成托管账号和链接"
    fi
}

selectUserSubscriptionId() {
    local id=
    showUserSubscriptions
    autoRead select_user_subscription_id "请输入用户订阅ID:" id
    if [[ -z "${id}" ]]; then
        errorCard "用户订阅 ID 不可以为空"
        return 1
    fi
    echo "${id}"
}

showUserSubscriptionLinks() {
    local userSubscriptionId=$1
    local accountName
    accountName=$(subscriptionSyncAccountName "${userSubscriptionId}")
    subscribe false
    statusCard "用户订阅链接" "已刷新 ${accountName} 的订阅输出，请把上方该账号的链接发给对方" "如果上方没有该账号，先执行同步生成托管账号"
}

removeUserSubscriptionMenu() {
    local userSubscriptionId=$1
    local confirm=
    autoRead remove_user_subscription_confirm "删除订阅 ${userSubscriptionId} 会移除状态；同步后会删除对应 sub_ 托管账号。确认请输入 yes：" confirm
    if [[ "${confirm}" != "yes" ]]; then
        statusCard "已取消" "操作未执行"
        return 1
    fi
    removeUserSubscriptionState "${userSubscriptionId}"
    subscriptionSyncRemoveAccount "$(subscriptionSyncAccountName "${userSubscriptionId}")"
    reloadCore
    successCard "用户订阅已删除"
}

manageUserSubscriptionItem() {
    local userSubscriptionId
    userSubscriptionId=$(selectUserSubscriptionId) || return
    while true; do
        echoContent title "\n┌─ 管理已开的订阅 ───────────────────────────────────"
        menuLine "当前订阅: ${userSubscriptionId}"
        menuLine "改节点范围、启停或删除后，需要执行同步才会写入核心配置"
        menuItem 1 "刷新并查看链接" "重新生成订阅输出，显示该订阅的链接"
        menuItem 2 "设置节点范围" "选择 main、被控服务器 ID 或 *"
        menuItem 3 "查看流量与限额" "查看累计流量和限额状态"
        menuItem 4 "设置流量上限" "0 表示不限，只影响统计和限额策略"
        menuItem 5 "启用/停用" "停用后同步会移除对应托管账号"
        menuItem 6 "预览本机变更" "查看将创建/删除哪些 sub_ 托管账号"
        menuDangerItem 7 "删除订阅" "删除记录；同步后移除对应托管账号"
        menuReturnItem 8 "返回给别人开订阅" "回到上级菜单"
        menuClose
        autoRead user_subscription_item_menu "请选择:" userSubscriptionItemStatus
        case "${userSubscriptionItemStatus}" in
        1) showUserSubscriptionLinks "${userSubscriptionId}" ;;
        2) setUserSubscriptionSourcesMenu "${userSubscriptionId}" ;;
        3) showUserSubscriptionTraffic "${userSubscriptionId}" ;;
        4) setUserSubscriptionTrafficLimitMenu "${userSubscriptionId}" ;;
        5) toggleUserSubscriptionState "${userSubscriptionId}"; successCard "用户订阅状态已切换" ;;
        6)
            readInstallType
            readInstallProtocolType
            userJsonCard "本机同步计划" "$(subscriptionSyncPlan)"
            ;;
        7) removeUserSubscriptionMenu "${userSubscriptionId}" && return ;;
        8) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

setUserSubscriptionSourcesMenu() {
    local userSubscriptionId=$1
    local sourceIds=
    local sourceJson=
    local line=

    userResultCard "这个订阅可使用的服务器"
    menuLine "这里选择订阅里包含哪些节点，不是填写订阅 ID"
    menuLine "main 表示本机；被控服务器需先在 多服务器订阅 中添加凭据"
    menuLine "可输入 main、远程服务器 ID，或 * 表示全部已添加服务器"
    menuLine "多个服务器用英文逗号分隔，例如 main,remote-a"
    while IFS= read -r line; do
        menuLine "${line}"
    done < <(listSubscriptionSources)
    menuClose
    autoRead user_subscription_sources "请输入服务器范围，多个用逗号分隔:" sourceIds
    if [[ -z "${sourceIds}" ]]; then
        errorCard "服务器范围不能为空；直接回车使用本机 main"
        return 1
    fi
    sourceJson=$(printf '%s' "${sourceIds}" | jq -R 'split(",") | map(gsub("^ +| +$"; "")) | map(select(length > 0))')
    setUserSubscriptionSources "${userSubscriptionId}" "${sourceJson}"
    successCard "节点范围已更新"
}

setUserSubscriptionTrafficLimitMenu() {
    local userSubscriptionId=$1
    local limit=
    autoRead user_subscription_traffic_limit "请输入流量上限GB[0为不限，仅统计和策略使用]:" limit
    if [[ -z "${limit}" ]] || ! echo "${limit}" | grep -qE '^[0-9]+$'; then
        errorCard "流量上限必须是数字"
        return 1
    fi
    setUserSubscriptionTrafficLimit "${userSubscriptionId}" "${limit}"
    successCard "流量上限已更新"
}

ensureXrayTrafficStatsConfig() {
    local xrayConfigPath=${configPath:-/etc/padm/xray/conf/}
    local statsConfig=${xrayConfigPath}13_stats_api.json
    local policyConfig=${xrayConfigPath}12_policy.json
    local tmpFile=${statsConfig}.tmp
    local policyTmp=${policyConfig}.tmp
    local changed=
    [[ "${coreInstallType}" == "1" && -d "${xrayConfigPath}" ]] || return 0
    cat <<EOF >"${tmpFile}"
{
  "stats": {},
  "api": {
    "tag": "api",
    "services": [
      "StatsService"
    ]
  },
  "inbounds": [
    {
      "tag": "api",
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      }
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": [
          "api"
        ],
        "outboundTag": "api"
      }
    ]
  }
}
EOF
    if [[ -f "${statsConfig}" ]] && cmp -s "${tmpFile}" "${statsConfig}"; then
        rm -f "${tmpFile}"
    else
        mv "${tmpFile}" "${statsConfig}"
        changed=true
    fi

    if [[ ! -f "${policyConfig}" ]]; then
        cat <<EOF >"${policyConfig}"
{
  "policy": {
    "levels": {
      "0": {}
    },
    "system": {}
  }
}
EOF
        changed=true
    fi
    if ! jq '
      .policy.levels["0"].statsUserUplink = true |
      .policy.levels["0"].statsUserDownlink = true |
      .policy.system.statsInboundUplink = true |
      .policy.system.statsInboundDownlink = true |
      .policy.system.statsOutboundUplink = true |
      .policy.system.statsOutboundDownlink = true
    ' "${policyConfig}" >"${policyTmp}"; then
        rm -f "${policyTmp}"
        errorCard "Xray 流量统计策略配置生成失败"
        return 1
    fi
    if cmp -s "${policyTmp}" "${policyConfig}"; then
        rm -f "${policyTmp}"
    else
        mv "${policyTmp}" "${policyConfig}"
        changed=true
    fi

    if [[ -n "${changed}" && -n "${configPath}" ]]; then
        reloadCore
    fi
}

collectLocalTrafficAccounts() {
    local file
    while IFS= read -r file; do
        [[ -f "${file}" ]] || continue
        jq -r '[.inbounds[]?.settings.clients[]?, .inbounds[]?.users[]?][]? | .email // .name // .username // empty' "${file}" 2>/dev/null
    done < <(subscriptionSyncConfigFiles) | awk -F '-' 'NF {print $1}' | sort -u
}

collectXrayTrafficStatsSnapshot() {
    local accounts=$1
    local stats=
    local xrayBinary=${XRAY_STATS_BINARY:-/etc/padm/xray/xray}
    if [[ ! -x "${xrayBinary}" ]]; then
        return 1
    fi
    if ! stats=$("${xrayBinary}" api statsquery --server=127.0.0.1:10085 -pattern user 2>/dev/null); then
        return 1
    fi
    if [[ -z "${stats}" ]]; then
        return 1
    fi
    if jq empty <<<"${stats}" >/dev/null 2>&1; then
        jq --argjson accounts "${accounts}" '
          def accountName($name): ($name | split(">>>")[1] | split("-")[0]);
          def direction($name): if ($name | contains("downlink")) then "download" else "upload" end;
          [.stat[]? | {account: accountName(.name), direction: direction(.name), value: (.value // 0)} | . as $item | select($accounts | index($item.account))] as $stats |
          $accounts | map(. as $account | {account: $account, upload: ([$stats[] | select(.account == $account and .direction == "upload") | .value] | add // 0), download: ([$stats[] | select(.account == $account and .direction == "download") | .value] | add // 0)})
        ' <<<"${stats}"
    else
        awk -v accounts="$(jq -r 'join(" ")' <<<"${accounts}")" '
          BEGIN {
            split(accounts, allowed, " ")
            for (i in allowed) wanted[allowed[i]] = 1
          }
          /name:/ {
            name = $0
            sub(/^.*user>>>/, "", name)
            sub(/-.*/, "", name)
            account = name
            direction = ($0 ~ /downlink/) ? "download" : "upload"
          }
          /value: / {
            if (wanted[account]) totals[account SUBSEP direction] += $2
          }
          END {
            printf "["
            first = 1
            for (i in allowed) {
              account = allowed[i]
              if (account == "") continue
              if (!first) printf ","
              first = 0
              printf "{\"account\":\"%s\",\"upload\":%d,\"download\":%d}", account, totals[account SUBSEP "upload"] + 0, totals[account SUBSEP "download"] + 0
            }
            printf "]"
          }' <<<"${stats}"
    fi
}

collectLocalTrafficSnapshot() {
    local accounts
    local items
    accounts=$(collectLocalTrafficAccounts | jq -R -s 'split("\n") | map(select(length > 0))')
    if [[ "$(jq 'length' <<<"${accounts}")" == "0" ]]; then
        jq -n '{ok:true, items: []}'
        return
    fi
    if items=$(collectXrayTrafficStatsSnapshot "${accounts}"); then
        jq -n --argjson items "${items}" '{ok:true, items:$items}'
    else
        jq -n '{ok:false, items: []}'
    fi
}

writeSubscriptionTrafficSnapshot() {
    local snapshot=$1
    local groupId
    if ! jq -e '.ok == true' <<<"${snapshot}" >/dev/null 2>&1; then
        statusCard "流量统计" "采集失败，已保留上次统计"
        return 1
    fi
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --argjson snapshot "${snapshot}" '
      def addTraffic($items): reduce $items[] as $item ({upload:0, download:0}; .upload += ($item.upload // 0) | .download += ($item.download // 0));
      def sourceTotal($prev; $current):
        ($prev // {upload:0, download:0, counters:{}}) as $old |
        ($old.counters // {}) as $oldCounters |
        (reduce $current[] as $item ({upload:0, download:0, counters:{}};
          ($oldCounters[$item.account] // {upload:0, download:0}) as $counter |
          (($item.upload // 0) - ($counter.upload // 0)) as $uploadDelta |
          (($item.download // 0) - ($counter.download // 0)) as $downloadDelta |
          .upload += (if ($oldCounters | has($item.account)) and $uploadDelta > 0 then $uploadDelta else 0 end) |
          .download += (if ($oldCounters | has($item.account)) and $downloadDelta > 0 then $downloadDelta else 0 end) |
          .counters[$item.account] = {upload: ($item.upload // 0), download: ($item.download // 0)})) as $delta |
        {upload: (($old.upload // 0) + $delta.upload), download: (($old.download // 0) + $delta.download), counters: $delta.counters, updated_at: (now | strftime("%F %T"))};
      .groups |= map(if .id == $groupId then
        . as $group |
        ($snapshot.items | map(. + {id: ((.account | sub("^sub_"; "") | gsub("_"; "-")))})) as $items |
        ($items | map(select(.account | startswith("sub_")))) as $userItems |
        ($items | map(select((.account | startswith("sub_")) | not))) as $adminItems |
        (sourceTotal($group.traffic.sources.main; $items)) as $mainTraffic |
        (sourceTotal($group.traffic.admin.sources.main; $adminItems)) as $adminTraffic |
        (($group.traffic.sources // {}) | to_entries | map(select(.key != "main") | .value) | addTraffic(.)) as $remoteTraffic |
        .traffic.global = {upload: (($mainTraffic.upload // 0) + ($remoteTraffic.upload // 0)), download: (($mainTraffic.download // 0) + ($remoteTraffic.download // 0))} |
        .traffic.admin = (($group.traffic.admin // {}) + {upload: ($adminTraffic.upload // 0), download: ($adminTraffic.download // 0), sources: ((($group.traffic.admin.sources // {}) + {main: $adminTraffic}))}) |
        .traffic.user_groups = (reduce $group.user_groups[]? as $userGroup ({};
          ($userItems | map(select(.id == $userGroup.id))) as $groupItems |
          sourceTotal(($group.traffic.user_groups[$userGroup.id].sources.main // {}); $groupItems) as $groupTraffic |
          .[$userGroup.id] = (($group.traffic.user_groups[$userGroup.id] // {}) + {upload: ($groupTraffic.upload // 0), download: ($groupTraffic.download // 0), sources: ((($group.traffic.user_groups[$userGroup.id].sources // {}) + {main: $groupTraffic}))}))) |
        .traffic.sources = (($group.traffic.sources // {}) + {main: $mainTraffic})
      else . end)'
}

collectSubscriptionTraffic() {
    local snapshot
    ensureSubscriptionGroupsState
    readInstallType
    readInstallProtocolType
    if ! ensureXrayTrafficStatsConfig; then
        return 1
    fi
    snapshot=$(collectLocalTrafficSnapshot)
    if writeSubscriptionTrafficSnapshot "${snapshot}"; then
        successCard "流量统计已更新"
    else
        return 1
    fi
}

showUserSubscriptionQuotaStatus() {
    local userSubscriptionId=$1
    local groupId
    groupId=$(activeSubscriptionGroupId)
    ensureSubscriptionGroupsState
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" --arg id "${userSubscriptionId}" '
      .groups[] | select(.id == $groupId) |
      (.user_groups[]? | select(.id == $id)) as $userGroup |
      (.traffic.user_groups[$id] // {upload:0, download:0}) as $traffic |
      if ($userGroup.traffic_limit_gb // 0) <= 0 then
        "不限额"
      else
        ((($userGroup.traffic_limit_gb * 1024 * 1024 * 1024) | floor) as $limitBytes |
         (((($traffic.upload // 0) + ($traffic.download // 0)) * 100 / $limitBytes) | floor) as $percent |
         if $percent >= 100 then "已超限(" + ($percent | tostring) + "%)"
         elif $percent >= 80 then "接近上限(" + ($percent | tostring) + "%)"
         else "正常(" + ($percent | tostring) + "%)" end)
      end'
}

showUserSubscriptionQuota() {
    local userSubscriptionId=$1
    local groupId
    groupId=$(activeSubscriptionGroupId)
    ensureSubscriptionGroupsState
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" --arg id "${userSubscriptionId}" '
      .groups[] | select(.id == $groupId) |
      (.user_groups[]? | select(.id == $id)) as $userGroup |
      (.traffic.user_groups[$id] // {upload:0, download:0, sources:{}}) as $traffic |
      (((($traffic.upload // 0) + ($traffic.download // 0)) / 1024 / 1024) | floor) as $usedMb |
      "ID: \($userGroup.id)\n名称: \($userGroup.name)\n已用: \($usedMb) MB\n上限: \(if ($userGroup.traffic_limit_gb // 0) <= 0 then "不限" else (($userGroup.traffic_limit_gb | tostring) + " GB") end)\n状态: " +
      (if ($userGroup.traffic_limit_gb // 0) <= 0 then
        "不限额"
      else
        ((($userGroup.traffic_limit_gb * 1024 * 1024 * 1024) | floor) as $limitBytes |
         (((($traffic.upload // 0) + ($traffic.download // 0)) * 100 / $limitBytes) | floor) as $percent |
         if $percent >= 100 then "已超限(" + ($percent | tostring) + "%)"
         elif $percent >= 80 then "接近上限(" + ($percent | tostring) + "%)"
         else "正常(" + ($percent | tostring) + "%)" end)
      end)'
}

showAdminSubscriptionTraffic() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    userJsonCard "我的流量" "$(subscriptionGroupsStateRead -r --arg groupId "${groupId}" '.groups[] | select(.id == $groupId) | .traffic.admin')"
}

showUserSubscriptionTraffic() {
    local userSubscriptionId=$1
    local groupId
    local traffic
    groupId=$(activeSubscriptionGroupId)
    ensureSubscriptionGroupsState
    userResultCard "用户订阅流量"
    menuLine "用户订阅：${userSubscriptionId}"
    menuLine "限额状态：$(showUserSubscriptionQuotaStatus "${userSubscriptionId}")"
    traffic=$(subscriptionGroupsStateRead -r --arg groupId "${groupId}" --arg id "${userSubscriptionId}" '.groups[] | select(.id == $groupId) | .traffic.user_groups[$id] // {upload:0, download:0, sources:{}}')
    printf '%s\n' "${traffic}" | jq .
    menuClose
}

showSubscriptionSources() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" '
      .groups[] | select(.id == $groupId) | .sources[]? |
      "ID:\(.id)\n名称:\(.name)\n角色:\(.role)\n地址:\(.scheme)://\(.host):\(.port)\n启用:\(.enabled)\n同步状态:\(.sync_status)" +
      (if has("last_sync_changed") then "\n上次同步变更:" + (if .last_sync_changed then "是" else "否" end) else "" end) +
      (if .last_sync_plan? then "\n上次同步计划: 创建\((.last_sync_plan.create // []) | length)，删除\((.last_sync_plan.remove // []) | length)" else "" end) +
      (if .last_sync_error? then "\n上次同步错误:\(.last_sync_error.type) \(.last_sync_error.message)" else "" end) +
      "\n---"'
}

showSubscriptionSourceControlUrls() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" '
      .groups[] | select(.id == $groupId) | .sources[]? | select(.role != "main") |
      "ID:\(.id)\n名称:\(.name)\nHealth:\(.scheme)://\(.host):\(.port)/s/control/health\nSync:\(.scheme)://\(.host):\(.port)/s/control/sync\n---"'
}

showSubscriptionSourceSyncResults() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" '
      .groups[] | select(.id == $groupId) | .sources[]? |
      "ID:\(.id)\n名称:\(.name)\n同步状态:\(.sync_status)" +
      (if has("last_sync_changed") then "\n上次同步变更:" + (if .last_sync_changed then "是" else "否" end) else "" end) +
      (if .last_sync_plan? then "\n上次同步计划: 创建\((.last_sync_plan.create // []) | length)，删除\((.last_sync_plan.remove // []) | length)" else "" end) +
      (if .last_sync_error? then "\n上次同步错误:\(.last_sync_error.type) \(.last_sync_error.message)" else "" end) +
      "\n---"'
}

manageMultiServerSubscriptions() {
    while true; do
        echoContent title "\n┌─ 多服务器订阅 ─────────────────────────────────────"
        menuLine "本机是主控：负责生成同步计划，并主动调用远端被控服务器的 /s/control/ 接口"
        menuLine "远端是被控：需先安装订阅服务，在远端复制“本机被控凭据”，再回到这里添加或更新"
        menuLine "推荐流程：被控端安装订阅服务并复制凭据 -> 主控添加被控服务器 -> 测试连接 -> 同步"
        menuItem 1 "查看服务器源" "列出本机主控和远端被控服务器"
        menuItem 2 "添加/移除被控服务器" "主控端管理远端被控服务器"
        menuItem 3 "更新被控服务器凭据" "粘贴从被控端复制来的整串凭据"
        menuItem 4 "测试被控连接" "主控端请求被控端健康检查"
        menuItem 5 "查看被控控制 URL" "显示被控端 health/sync 地址"
        menuItem 6 "查看同步结果" "显示最近同步计划和错误"
        menuItem 7 "启用/停用被控服务器" "切换被控服务器源状态"
        menuItem 8 "清除同步错误" "清理最近同步错误"
        menuReturnItem 9 "返回订阅与用户" "回到上级菜单"
        menuClose
        autoRead multi_server_subscription_menu "请选择:" multiServerSubscriptionStatus
        case "${multiServerSubscriptionStatus}" in
        1) showSubscriptionSources ;;
        2) addSubscribeMenu 1 ;;
        3) setSubscriptionSourceControlTokenMenu ;;
        4) userJsonCard "被控服务器健康检查" "$(subscriptionRemoteControlHealthAll)" ;;
        5) showSubscriptionSourceControlUrls ;;
        6) showSubscriptionSourceSyncResults ;;
        7) toggleSubscriptionSourceMenu ;;
        8) clearSubscriptionSourceSyncErrorMenu ;;
        9) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

manageSubscriptionServers() {
    manageMultiServerSubscriptions
}

setSubscriptionSourceControlTokenMenu() {
    local credential=
    local credentialJson=
    local host=
    local port=
    local sourceId=
    local token=
    local matches=
    echoContent title "\n┌─ 更新被控服务器凭据 ───────────────────────────────"
    menuLine "在被控服务器进入 订阅服务 -> 查看本机被控凭据，复制整串被控凭据"
    menuLine "粘贴后会自动读取 HTTPS 地址、订阅端口和 Token，并更新已有被控服务器"
    menuClose
    autoRead subscription_control_credential "请粘贴被控凭据:" credential
    if [[ -z "${credential}" ]]; then
        errorCard "被控凭据不可为空"
        return 1
    fi
    credentialJson=$(subscriptionControlCredentialDecode "${credential}") || {
        errorCard "被控凭据无效，请复制被控端完整输出"
        return 1
    }
    host=$(jq -r '.host' <<<"${credentialJson}")
    port=$(jq -r '.port' <<<"${credentialJson}")
    token=$(jq -r '.token' <<<"${credentialJson}")
    matches=$(listSubscriptionSources | awk -F ':' -v host="${host}" -v port="${port}" '$3 != "main" && $5 == host && $6 == port {print $1}')
    if [[ -n "${matches}" ]] && [[ "$(printf '%s\n' "${matches}" | wc -l | tr -d ' ')" == "1" ]]; then
        sourceId=${matches}
    else
        listSubscriptionSources | awk -F ':' '$3 != "main" {print $1":"$2":"$4":"$5":"$6":"$8}'
        autoRead subscription_source_id "请输入要更新的被控服务器别名:" sourceId
    fi
    if [[ -z "${sourceId}" ]] || ! subscriptionSourceExists "${sourceId}" || subscriptionSourceIsMain "${sourceId}"; then
        errorCard "被控服务器别名无效"
        return 1
    fi
    if subscriptionRemoteSourceSelfReference "$(jq -n --arg host "${host}" --argjson port "${port}" --arg scheme https '{host:$host, port:$port, scheme:$scheme}')"; then
        errorCard "被控服务器指向当前主控订阅服务，已拒绝更新，避免递归同步"
        return 1
    fi
    setSubscriptionSourceCredential "${sourceId}" "${host}" "${port}" "${token}"
    successCard "被控服务器凭据已更新" "被控地址：${host}:${port}" "别名：${sourceId}" "Token 已保存，可继续测试被控连接"
}

toggleSubscriptionSourceMenu() {
    local sourceId=
    local sourceAction=
    listSubscriptionSources | awk -F ':' '$3 != "main" {print $1":"$2":启用="$7}'
    autoRead subscription_source_toggle_id "请输入被控服务器源ID:" sourceId
    if [[ -z "${sourceId}" ]] || ! subscriptionSourceExists "${sourceId}" || subscriptionSourceIsMain "${sourceId}"; then
        errorCard "服务器源 ID 无效"
        return 1
    fi
    autoRead subscription_source_action "请输入操作[enable/disable]:" sourceAction
    if [[ "${sourceAction}" == "enable" ]]; then
        setSubscriptionSourceEnabled "${sourceId}" true
        successCard "被控服务器已启用"
    elif [[ "${sourceAction}" == "disable" ]]; then
        setSubscriptionSourceEnabled "${sourceId}" false
        successCard "被控服务器已停用"
    else
        errorCard "操作无效"
        return 1
    fi
}

clearSubscriptionSourceSyncErrorMenu() {
    local sourceId=
    showSubscriptionSourceSyncResults
    autoRead subscription_clear_error_source "请输入要清除错误的被控服务器源ID:" sourceId
    if [[ -z "${sourceId}" ]] || ! subscriptionSourceExists "${sourceId}"; then
        errorCard "服务器源 ID 无效"
        return 1
    fi
    clearSubscriptionSourceSyncError "${sourceId}"
    successCard "同步错误已清除"
}

showSubscriptionTrafficJson() {
    local title=$1
    local filter=$2
    collectSubscriptionTraffic || return 1
    showSubscriptionTrafficJsonNoRefresh "${title}" "${filter}"
}

showSubscriptionTrafficJsonNoRefresh() {
    local title=$1
    local filter=$2
    local groupId
    groupId=$(activeSubscriptionGroupId)
    ensureSubscriptionGroupsState
    userJsonCard "${title}" "$(subscriptionGroupsStateRead -r --arg groupId "${groupId}" "${filter}")"
}

manageTrafficAndQuota() {
    while true; do
        echoContent title "\n┌─ 流量与限额 ───────────────────────────────────────"
        menuLine "刷新流量统计会读取 Xray stats API；查看动作只读 groups.json，不会隐式刷新"
        menuLine "首次刷新会建立计数基线，后续按增量累计；采集失败会保留上次统计"
        menuLine "限额状态只用于提示和策略执行，是否停用用户由限额计划决定"
        menuItem 1 "刷新流量统计" "读取当前流量并更新累计值"
        menuItem 2 "查看总流量" "查看全局累计流量"
        menuItem 3 "查看我的流量" "查看自用账号流量"
        menuItem 4 "查看用户订阅流量" "查看用户订阅流量"
        menuItem 5 "查看服务器流量" "查看服务器来源流量"
        menuItem 6 "查看限额计划" "预览超限用户处理"
        menuDangerItem 7 "执行限额计划" "停用超限用户并等待同步移除账号"
        menuReturnItem 8 "返回订阅与用户" "回到上级菜单"
        menuClose
        autoRead traffic_quota_menu "请选择:" trafficQuotaStatus
        case "${trafficQuotaStatus}" in
        1) collectSubscriptionTraffic ;;
        2) showSubscriptionTrafficJsonNoRefresh "总流量" '.groups[] | select(.id == $groupId) | .traffic.global' ;;
        3) showAdminSubscriptionTraffic ;;
        4) showSubscriptionTrafficJsonNoRefresh "用户订阅流量" '.groups[] | select(.id == $groupId) | .traffic.user_groups' ;;
        5) showSubscriptionTrafficJsonNoRefresh "服务器流量" '.groups[] | select(.id == $groupId) | .traffic.sources' ;;
        6) userJsonCard "限额计划" "$(subscriptionQuotaDryRunPlan)" ;;
        7) executeSubscriptionQuotaPlanMenu ;;
        8) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

manageSubscriptionTraffic() {
    manageTrafficAndQuota
}

manageSubscriptionStateBackups() {
    local backupFile
    local confirm
    while true; do
        echoContent title "\n┌─ 状态备份 ─────────────────────────────────────────"
        menuLine "备份对象是订阅组状态 groups.json，包含用户订阅、服务器源、同步状态和流量统计"
        menuLine "恢复会覆盖当前订阅组状态；不会自动回滚核心配置文件或证书"
        menuItem 1 "创建备份" "保存当前 groups.json"
        menuItem 2 "查看备份" "列出已有备份"
        menuDangerItem 3 "恢复备份" "用指定备份覆盖当前状态"
        menuReturnItem 4 "返回自动同步与备份" "回到上级菜单"
        menuClose
        autoRead subscription_backup_menu "请选择:" backupStatus
        case "${backupStatus}" in
        1)
            backupFile=$(createSubscriptionGroupsBackup)
            successCard "已创建备份: ${backupFile}"
            ;;
        2) listSubscriptionGroupsBackups ;;
        3)
            listSubscriptionGroupsBackups
            autoRead subscription_restore_backup "请输入要恢复的备份完整路径:" backupFile
            if [[ -z "${backupFile}" ]]; then
                errorCard "备份路径不可为空"
                continue
            fi
            autoRead subscription_restore_confirm "恢复会覆盖当前订阅组状态，确认请输入 yes：" confirm
            if [[ "${confirm}" != "yes" ]]; then
                statusCard "已取消" "操作未执行"
                continue
            fi
            if restoreSubscriptionGroupsBackup "${backupFile}"; then
                successCard "状态已恢复"
            else
                errorCard "状态恢复失败"
            fi
            ;;
        4) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

manageSubscriptionAutomation() {
    while true; do
        echoContent title "\n┌─ 自动同步与备份 ───────────────────────────────────"
        menuLine "自动同步会按用户订阅生成 sub_<ID> 托管账号，并同步本机和被控服务器"
        menuLine "建议改动前查看本机/远程同步计划；恢复状态前先确认备份内容"
        menuItem 1 "自动同步设置" "配置定时同步、远程同步和限额自动执行"
        menuItem 2 "立即执行同步" "立即应用同步计划"
        menuItem 3 "查看本机同步计划" "预览本机 create/remove"
        menuItem 4 "查看远程同步计划" "预览远端同步计划"
        menuItem 5 "状态备份与恢复" "创建、查看或恢复 groups.json 备份"
        menuReturnItem 6 "返回订阅与用户" "回到上级菜单"
        menuClose
        autoRead subscription_automation_menu "请选择:" subscriptionAutomationStatus
        case "${subscriptionAutomationStatus}" in
        1) manageSubscriptionSyncSettings ;;
        2) runSubscriptionGroupSync ;;
        3)
            readInstallType
            readInstallProtocolType
            userJsonCard "本机同步计划" "$(subscriptionSyncPlan)"
            ;;
        4) userJsonCard "远程同步计划" "$(subscriptionRemoteSyncPlan)" ;;
        5) manageSubscriptionStateBackups ;;
        6) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

manageSubscriptionSettings() {
    manageSubscriptionAutomation
}

managePublishingAndSync() {
    manageSubscriptionAutomation
}

subscriptionQuotaDryRunPlan() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    ensureSubscriptionGroupsState
    subscriptionGroupsStateRead --arg groupId "${groupId}" '
      .groups[] | select(.id == $groupId) |
      [
        .user_groups[]? as $userGroup |
        select($userGroup.enabled == true) |
        select(($userGroup.traffic_limit_gb // 0) > 0) |
        (.traffic.user_groups[$userGroup.id] // {upload:0, download:0}) as $traffic |
        (($traffic.upload // 0) + ($traffic.download // 0)) as $usedBytes |
        (($userGroup.traffic_limit_gb * 1024 * 1024 * 1024) | floor) as $limitBytes |
        select($usedBytes >= $limitBytes) |
        {
          action: "disable_user_group",
          id: $userGroup.id,
          name: $userGroup.name,
          used_bytes: $usedBytes,
          limit_bytes: $limitBytes,
          percent: (($usedBytes * 100 / $limitBytes) | floor),
          dry_run: true
        }
      ]'
}

applySubscriptionQuotaPlan() {
    local plan=$1
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --argjson plan "${plan}" '
      ($plan | map(select(.action == "disable_user_group") | .id)) as $disableIds |
      .groups |= map(if .id == $groupId then
        .user_groups |= map(if (.id as $id | $disableIds | index($id)) then .enabled = false else . end)
      else . end)'
}

executeSubscriptionQuotaPlanMenu() {
    local plan
    local confirm
    plan=$(subscriptionQuotaDryRunPlan)
    if [[ "$(jq 'length' <<<"${plan}")" == "0" ]]; then
        successCard "当前没有需要执行的限额计划"
        return
    fi
    echoContent title "\n┌─ 限额执行计划 ─────────────────────────────────────"
    menuLine "仅停用用户订阅状态，账号删除由同步流程处理"
    printf '%s\n' "${plan}" | jq .
    menuClose
    autoRead subscription_quota_execute_confirm "确认执行请输入 yes：" confirm
    if [[ "${confirm}" != "yes" ]]; then
        statusCard "已取消" "操作未执行"
        return
    fi
    if ! collectSubscriptionTraffic; then
        errorCard "流量统计刷新失败，已取消执行限额计划"
        return
    fi
    plan=$(subscriptionQuotaDryRunPlan)
    if [[ "$(jq 'length' <<<"${plan}")" == "0" ]]; then
        successCard "刷新后没有需要执行的限额计划"
        return
    fi
    applySubscriptionQuotaPlan "${plan}"
    successCard "限额计划已执行，请运行同步计划或立即同步以移除对应账号"
}

subscriptionGroupRemoteSyncEnabled() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateRead -e --arg groupId "${groupId}" '.groups[] | select(.id == $groupId) | (.sync.remote_enabled // true) == true' >/dev/null 2>&1
}

subscriptionGroupQuotaAutoApplyEnabled() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateRead -e --arg groupId "${groupId}" '.groups[] | select(.id == $groupId) | (.sync.quota_auto_apply // false) == true' >/dev/null 2>&1
}

subscriptionQuotaPlanAccountNames() {
    local plan=$1
    jq -r '.[]? | select(.action == "disable_user_group") | .id' <<<"${plan}" | while IFS= read -r id; do subscriptionSyncAccountName "${id}"; done
}

applySubscriptionQuotaPlanAccounts() {
    local plan=$1
    local accountName
    while IFS= read -r accountName; do
        [[ -n "${accountName}" ]] && subscriptionSyncRemoveAccount "${accountName}"
    done < <(subscriptionQuotaPlanAccountNames "${plan}")
}

subscriptionGroupSyncEnabled() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateRead -e --arg groupId "${groupId}" '.groups[] | select(.id == $groupId) | .sync.enabled == true' >/dev/null 2>&1
}

subscriptionGroupSyncInterval() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" '.groups[] | select(.id == $groupId) | .sync.interval_minutes // 10'
}

runSubscriptionGroupSyncCron() {
    local lockDir=/tmp/padm-subscription-sync.lock
    if ! mkdir "${lockDir}" 2>/dev/null; then
        userResultCard "订阅组自动同步"
        menuLine "订阅组同步正在执行，跳过本轮"
        menuClose
        return 0
    fi
    trap 'rmdir "${lockDir}" >/dev/null 2>&1' RETURN

    ensureSubscriptionGroupsState
    if ! subscriptionGroupSyncEnabled; then
        userResultCard "订阅组自动同步"
        menuLine "订阅组自动同步未开启，跳过本轮"
        menuClose
        return 0
    fi
    readInstallType
    readInstallProtocolType
    if [[ -z "${configPath}" ]]; then
        userResultCard "订阅组自动同步"
        menuLine "未检测到安装配置，跳过订阅组同步"
        menuClose
        return 0
    fi
    userResultCard "订阅组自动同步"
    menuLine "开始执行：$(date '+%Y-%m-%d %H:%M:%S')"
    menuClose
    runSubscriptionGroupSync
}

subscriptionGroupSyncInstallScript() {
    if [[ -f /etc/padm/install.sh ]]; then
        echo /etc/padm/install.sh
    else
        echo "${PROJECT_ROOT}/install.sh"
    fi
}

subscriptionGroupSyncCronFile() {
    echo /etc/padm/backup_crontab.cron
}

subscriptionGroupSyncIntervalValid() {
    [[ -n "$1" && "$1" =~ ^[0-9]+$ && "$1" -ge 1 && "$1" -le 59 ]]
}

installSubscriptionGroupSyncCron() {
    local interval
    local currentCron
    local syncCron
    local cronFile
    local scriptPath
    ensureSubscriptionGroupsState
    interval=$(subscriptionGroupSyncInterval)
    cronFile=$(subscriptionGroupSyncCronFile)
    scriptPath=$(subscriptionGroupSyncInstallScript)
    if ! subscriptionGroupSyncIntervalValid "${interval}"; then
        interval=10
    fi
    mkdir -p "$(dirname "${cronFile}")"
    currentCron=$(crontab -l 2>/dev/null | sed '/SyncSubscriptionGroups/d' || true)
    syncCron="*/${interval} * * * * /bin/bash ${scriptPath} SyncSubscriptionGroups >> /etc/padm/crontab_subscription_sync.log 2>&1"
    installUserCrontabContent "${currentCron}
${syncCron}"
}

removeSubscriptionGroupSyncCron() {
    local cronFile
    local currentCron
    cronFile=$(subscriptionGroupSyncCronFile)
    mkdir -p "$(dirname "${cronFile}")"
    currentCron=$(crontab -l 2>/dev/null | sed '/SyncSubscriptionGroups/d' || true)
    installUserCrontabContent "${currentCron}"
}

refreshSubscriptionGroupSyncCron() {
    ensureSubscriptionGroupsState
    if subscriptionGroupSyncEnabled; then
        installSubscriptionGroupSyncCron
    else
        removeSubscriptionGroupSyncCron
    fi
}

subscriptionGroupSyncCronStatus() {
    crontab -l 2>/dev/null | grep 'SyncSubscriptionGroups' || true
}

manageSubscriptionSyncSettings() {
    local groupId
    local syncStatus
    while true; do
        groupId=$(activeSubscriptionGroupId)
        syncStatus=$(subscriptionGroupsStateRead -r --arg groupId "${groupId}" '.groups[] | select(.id == $groupId) | .sync')
        echoContent title "\n┌─ 自动同步 ─────────────────────────────────────────"
        menuLine "自动同步会按用户订阅生成 sub_<ID> 托管账号，并删除不再期望的托管账号"
        menuLine "建议先看本机/远程同步计划，确认 create/remove 后再立即执行同步"
        menuLine "限额自动执行默认关闭；开启后超限用户会被停用并在同步中移除托管账号"
        userJsonCard "自动同步当前状态" "${syncStatus}"
        echoContent title "\n┌─ 自动同步操作 ─────────────────────────────────────"
        menuItem 1 "开启/关闭自动同步" "切换定时同步状态"
        menuItem 2 "设置自动同步间隔" "设置 1-59 分钟间隔"
        menuItem 3 "立即执行同步" "立即应用同步计划"
        menuItem 4 "查看本机同步计划" "预览本机 create/remove"
        menuItem 5 "查看远程同步计划" "预览远端同步计划"
        menuItem 6 "查看限额计划" "预览超限用户处理"
        menuDangerItem 7 "执行限额计划" "停用超限用户并等待同步移除账号"
        menuItem 8 "开启/关闭远程同步" "切换远端同步状态"
        menuItem 9 "开启/关闭限额自动执行" "切换自动执行超限策略"
        menuItem 10 "查看定时任务" "显示当前 cron 配置"
        menuReturnItem 11 "返回自动同步与备份" "回到上级菜单"
        menuClose
        autoRead sync_settings_menu "请选择:" syncSettingsStatus
        case "${syncSettingsStatus}" in
        1)
            subscriptionGroupsStateWrite --arg groupId "${groupId}" '.groups |= map(if .id == $groupId then .sync.enabled = (.sync.enabled | not) else . end)'
            refreshSubscriptionGroupSyncCron
            successCard "自动同步状态已切换"
            ;;
        2)
            local interval=
            autoRead sync_interval_minutes "请输入同步间隔分钟:" interval
            if ! subscriptionGroupSyncIntervalValid "${interval}"; then
                errorCard "输入有误，同步间隔需为 1-59 分钟"
                continue
            fi
            subscriptionGroupsStateWrite --arg groupId "${groupId}" --argjson interval "${interval}" '.groups |= map(if .id == $groupId then .sync.interval_minutes = $interval else . end)'
            refreshSubscriptionGroupSyncCron
            successCard "自动同步间隔已更新"
            ;;
        3) runSubscriptionGroupSync ;;
        4)
            readInstallType
            readInstallProtocolType
            userJsonCard "本机同步计划" "$(subscriptionSyncPlan)"
            ;;
        5) userJsonCard "远程同步计划" "$(subscriptionRemoteSyncPlan)" ;;
        6) userJsonCard "限额计划" "$(subscriptionQuotaDryRunPlan)" ;;
        7) executeSubscriptionQuotaPlanMenu ;;
        8)
            subscriptionGroupsStateWrite --arg groupId "${groupId}" '.groups |= map(if .id == $groupId then .sync.remote_enabled = ((.sync.remote_enabled // true) | not) else . end)'
            successCard "远程同步状态已切换"
            ;;
        9)
            subscriptionGroupsStateWrite --arg groupId "${groupId}" '.groups |= map(if .id == $groupId then .sync.quota_auto_apply = ((.sync.quota_auto_apply // false) | not) else . end)'
            successCard "限额自动执行状态已切换"
            ;;
        10) subscriptionGroupSyncCronStatus ;;
        11) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}
