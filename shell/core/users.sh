#!/usr/bin/env bash

# 自定义uuid
customUUID() {
    read -r -p "请输入合法的UUID，[回车]随机UUID:" currentCustomUUID
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
            echoContent red " ---> UUID不可重复"
            exit 0
        fi
    fi
}


# 自定义email
customUserEmail() {
    read -r -p "请输入合法的email，[回车]随机email:" currentCustomEmail
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
            echoContent red " ---> email不可重复"
            exit 0
        fi
    fi
}


# 添加用户
addUser() {
    read -r -p "请输入要添加的用户数量:" userNum
    echo
    if [[ -z ${userNum} || ${userNum} -le 0 ]]; then
        echoContent red " ---> 输入有误，请重新输入"
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
            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}02_VLESS_TCP_inbounds.json)
            echo "${clients}" | jq . >${configPath}02_VLESS_TCP_inbounds.json
        fi

        # VLESS WS
        if currentProtocolHas 1; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 1 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 1 "${uuid}" "${email}")
            fi

            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}03_VLESS_WS_inbounds.json)
            echo "${clients}" | jq . >${configPath}03_VLESS_WS_inbounds.json
        fi

        # trojan grpc
        if currentProtocolHas 2; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 2 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 2 "${uuid}" "${email}")
            fi

            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}04_trojan_gRPC_inbounds.json)
            echo "${clients}" | jq . >${configPath}04_trojan_gRPC_inbounds.json
        fi
        # VMess WS
        if currentProtocolHas 3; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 3 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 3 "${uuid}" "${email}")
            fi

            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}05_VMess_WS_inbounds.json)
            echo "${clients}" | jq . >${configPath}05_VMess_WS_inbounds.json
        fi
        # trojan tcp
        if currentProtocolHas 4; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 4 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 4 "${uuid}" "${email}")
            fi
            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}04_trojan_TCP_inbounds.json)
            echo "${clients}" | jq . >${configPath}04_trojan_TCP_inbounds.json
        fi

        # vless grpc
        if currentProtocolHas 5; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 5 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 5 "${uuid}" "${email}")
            fi
            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}06_VLESS_gRPC_inbounds.json)
            echo "${clients}" | jq . >${configPath}06_VLESS_gRPC_inbounds.json
        fi

        # vless reality vision
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
            clients=$(jq -r "${realityUserConfig} = ${clients}" ${configPath}07_VLESS_vision_reality_inbounds.json)
            echo "${clients}" | jq . >${configPath}07_VLESS_vision_reality_inbounds.json
        fi

        # vless reality grpc
        if currentProtocolHas 8; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 8 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 8 "${uuid}" "${email}")
            fi
            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}08_VLESS_vision_gRPC_inbounds.json)
            echo "${clients}" | jq . >${configPath}08_VLESS_vision_gRPC_inbounds.json
        fi

        # hysteria2
        if currentProtocolHas 6; then
            local clients=

            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 6 "${uuid}" "${email}")
            elif [[ -n "${singBoxConfigPath}" ]]; then
                clients=$(initSingBoxClients 6 "${uuid}" "${email}")
            fi

            clients=$(jq -r ".inbounds[0].users = ${clients}" "${singBoxConfigPath}06_hysteria2_inbounds.json")
            echo "${clients}" | jq . >"${singBoxConfigPath}06_hysteria2_inbounds.json"
        fi

        # tuic
        if currentProtocolHas 9; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 9 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 9 "${uuid}" "${email}")
            fi

            clients=$(jq -r ".inbounds[0].users = ${clients}" "${singBoxConfigPath}09_tuic_inbounds.json")

            echo "${clients}" | jq . >"${singBoxConfigPath}09_tuic_inbounds.json"
        fi
        # naive
        if currentProtocolHas 10; then
            local clients=
            clients=$(initSingBoxClients 10 "${uuid}" "${email}")
            clients=$(jq -r ".inbounds[0].users = ${clients}" "${singBoxConfigPath}10_naive_inbounds.json")

            echo "${clients}" | jq . >"${singBoxConfigPath}10_naive_inbounds.json"
        fi
        # VMess WS
        if currentProtocolHas 11; then
            local clients=
            if [[ "${coreInstallType}" == "1" ]]; then
                clients=$(initXrayClients 11 "${uuid}" "${email}")
            elif [[ "${coreInstallType}" == "2" ]]; then
                clients=$(initSingBoxClients 11 "${uuid}" "${email}")
            fi

            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}11_VMess_HTTPUpgrade_inbounds.json)
            echo "${clients}" | jq . >${configPath}11_VMess_HTTPUpgrade_inbounds.json
        fi
        # anytls
        if currentProtocolHas 13; then
            local clients=
            clients=$(initSingBoxClients 13 "${uuid}" "${email}")

            clients=$(jq -r "${userConfig} = ${clients}" ${configPath}13_anytls_inbounds.json)
            echo "${clients}" | jq . >${configPath}13_anytls_inbounds.json
        fi
    done
    reloadCore
    echoContent green " ---> 添加完成"
    readNginxSubscribe
    if [[ -n "${subscribePort}" ]]; then
        subscribe false
    fi
    manageSubscription 1
}

# 移除用户
removeUser() {

    local uuid=
    if [[ "${coreInstallType}" == "1" ]]; then
        jq -r -c '(.inbounds[0].settings.clients // .inbounds[1].settings.clients)[]?|.email' ${configPath}${frontingType:-$frontingTypeReality}.json | awk '{print NR""":"$0}'
        read -r -p "请选择要删除的用户编号[仅支持单个删除]:" delUserIndex
        if [[ $(jq -r '(.inbounds[0].settings.clients // .inbounds[1].settings.clients)?|length' ${configPath}${frontingType:-$frontingTypeReality}.json) -lt ${delUserIndex} ]]; then
            echoContent red " ---> 选择错误"
        else
            delUserIndex=$((delUserIndex - 1))
        fi
    elif [[ "${coreInstallType}" == "2" ]]; then
        jq -r -c .inbounds[0].users[].name//.inbounds[0].users[].username ${configPath}${frontingType:-$frontingTypeReality}.json | awk '{print NR""":"$0}'
        read -r -p "请选择要删除的用户编号[仅支持单个删除]:" delUserIndex
        if [[ $(jq -r '.inbounds[0].users|length' ${configPath}${frontingType:-$frontingTypeReality}.json) -lt ${delUserIndex} ]]; then
            echoContent red " ---> 选择错误"
        else
            delUserIndex=$((delUserIndex - 1))
        fi
    fi

    if [[ -n "${delUserIndex}" ]]; then

        if currentProtocolHas 0; then
            local vlessVision
            vlessVision=$(jq -r 'del(.inbounds[0].settings.clients['"${delUserIndex}"']//.inbounds[0].users['"${delUserIndex}"'])' ${configPath}02_VLESS_TCP_inbounds.json)
            echo "${vlessVision}" | jq . >${configPath}02_VLESS_TCP_inbounds.json
        fi
        if currentProtocolHas 1; then
            local vlessWSResult
            vlessWSResult=$(jq -r 'del(.inbounds[0].settings.clients['"${delUserIndex}"']//.inbounds[0].users['"${delUserIndex}"'])' ${configPath}03_VLESS_WS_inbounds.json)
            echo "${vlessWSResult}" | jq . >${configPath}03_VLESS_WS_inbounds.json
        fi

        if currentProtocolHas 2; then
            local trojangRPCUsers
            trojangRPCUsers=$(jq -r 'del(.inbounds[0].settings.clients['"${delUserIndex}"']//.inbounds[0].users['"${delUserIndex}"')' ${configPath}04_trojan_gRPC_inbounds.json)
            echo "${trojangRPCUsers}" | jq . >${configPath}04_trojan_gRPC_inbounds.json
        fi

        if currentProtocolHas 3; then
            local vmessWSResult
            vmessWSResult=$(jq -r 'del(.inbounds[0].settings.clients['"${delUserIndex}"']//.inbounds[0].users['"${delUserIndex}"'])' ${configPath}05_VMess_WS_inbounds.json)
            echo "${vmessWSResult}" | jq . >${configPath}05_VMess_WS_inbounds.json
        fi

        if currentProtocolHas 5; then
            local vlessGRPCResult
            vlessGRPCResult=$(jq -r 'del(.inbounds[0].settings.clients['"${delUserIndex}"']//.inbounds[0].users['"${delUserIndex}"'])' ${configPath}06_VLESS_gRPC_inbounds.json)
            echo "${vlessGRPCResult}" | jq . >${configPath}06_VLESS_gRPC_inbounds.json
        fi

        if currentProtocolHas 4; then
            local trojanTCPResult
            trojanTCPResult=$(jq -r 'del(.inbounds[0].settings.clients['"${delUserIndex}"']//.inbounds[0].users['"${delUserIndex}"'])' ${configPath}04_trojan_TCP_inbounds.json)
            echo "${trojanTCPResult}" | jq . >${configPath}04_trojan_TCP_inbounds.json
        fi

        if currentProtocolHas 6; then
            local hysteriaResult
            hysteriaResult=$(jq -r 'del(.inbounds[0].users['"${delUserIndex}"'])' "${singBoxConfigPath}06_hysteria2_inbounds.json")
            echo "${hysteriaResult}" | jq . >"${singBoxConfigPath}06_hysteria2_inbounds.json"
        fi
        if currentProtocolHas 7; then
            local vlessRealityResult
            vlessRealityResult=$(jq -r 'del(.inbounds[1].settings.clients['"${delUserIndex}"']//.inbounds[0].users['"${delUserIndex}"'])' ${configPath}07_VLESS_vision_reality_inbounds.json)
            echo "${vlessRealityResult}" | jq . >${configPath}07_VLESS_vision_reality_inbounds.json
        fi
        if currentProtocolHas 8; then
            local vlessRealityGRPCResult
            vlessRealityGRPCResult=$(jq -r 'del(.inbounds[0].settings.clients['"${delUserIndex}"']//.inbounds[0].users['"${delUserIndex}"'])' ${configPath}08_VLESS_vision_gRPC_inbounds.json)
            echo "${vlessRealityGRPCResult}" | jq . >${configPath}08_VLESS_vision_gRPC_inbounds.json
        fi

        if currentProtocolHas 9; then
            local tuicResult
            tuicResult=$(jq -r 'del(.inbounds[0].users['"${delUserIndex}"'])' "${singBoxConfigPath}09_tuic_inbounds.json")
            echo "${tuicResult}" | jq . >"${singBoxConfigPath}09_tuic_inbounds.json"
        fi
        if currentProtocolHas 10; then
            local naiveResult
            naiveResult=$(jq -r 'del(.inbounds[0].users['"${delUserIndex}"'])' "${singBoxConfigPath}10_naive_inbounds.json")
            echo "${naiveResult}" | jq . >"${singBoxConfigPath}10_naive_inbounds.json"
        fi
        # VMess HTTPUpgrade
        if currentProtocolHas 11; then
            local vmessHTTPUpgradeResult
            vmessHTTPUpgradeResult=$(jq -r 'del(.inbounds[0].users['"${delUserIndex}"'])' "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json")
            echo "${vmessHTTPUpgradeResult}" | jq . >"${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json"
            echo "${vmessHTTPUpgradeResult}" | jq . >${configPath}11_VMess_HTTPUpgrade_inbounds.json
        fi
        # AnyTLS
        if currentProtocolHas 13; then
            local anyTLSResult
            anyTLSResult=$(jq -r 'del(.inbounds[0].users['"${delUserIndex}"'])' "${singBoxConfigPath}13_anytls_inbounds.json")
            echo "${anyTLSResult}" | jq . >"${singBoxConfigPath}13_anytls_inbounds.json"
        fi
        reloadCore
        readNginxSubscribe
        if [[ -n "${subscribePort}" ]]; then
            subscribe false
        fi
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
    if [[ -n "${subscribePort}" ]]; then
        subscribe false
    fi

    collectSubscriptionTraffic

    if [[ "${failures}" == "[]" ]]; then
        subscriptionSyncMarkResult success "${failures}"
        echoContent green " ---> 自动同步完成"
    else
        subscriptionSyncMarkResult partial "${failures}"
        echoContent yellow " ---> 本机自动同步完成，远程服务器源待后续通道同步"
    fi
}

# 订阅管理
manageSubscription() {
    echoContent skyBlue "\n功能 1/${totalProgress} : 订阅管理"
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装"
        exit 0
    fi

    echoContent skyBlue "\n┌─ 订阅管理 ─────────────────────────────────────────"
    menuLine "groups.json 是用户、服务器、同步和流量的状态真源"
    menuLine "新人路径：先看 我的订阅；给别人使用时再创建 用户订阅"
    menuLine "多服务器：添加服务器源 -> 设置控制 Token -> 查看计划并同步"
    menuItem 1 "我的订阅（管理员）" "查看管理员订阅链接、可用服务器和我的流量"
    menuItem 2 "用户订阅" "创建独立订阅、授权服务器和设置流量上限"
    menuItem 3 "服务器" "管理本机/远程服务器源、控制 Token、连接测试和同步结果"
    menuItem 4 "流量" "刷新并查看总流量、管理员、用户订阅和服务器来源流量"
    menuItem 5 "设置" "安装订阅服务、配置自动同步、限额策略和状态备份"
    menuClose
    read -r -p "请输入:" manageSubscriptionStatus
    if [[ "${manageSubscriptionStatus}" == "1" ]]; then
        manageAdminSubscription
    elif [[ "${manageSubscriptionStatus}" == "2" ]]; then
        manageUserSubscription
    elif [[ "${manageSubscriptionStatus}" == "3" ]]; then
        manageSubscriptionServers
    elif [[ "${manageSubscriptionStatus}" == "4" ]]; then
        manageSubscriptionTraffic
    elif [[ "${manageSubscriptionStatus}" == "5" ]]; then
        manageSubscriptionSettings
    else
        echoContent red " ---> 选择错误"
    fi
}

manageAdminSubscription() {
    echoContent red "\n===================== 我的订阅 ====================="
    echoContent yellow "说明：这里是管理员自己的订阅入口，适合自用或检查当前节点输出"
    echoContent yellow "如果要给别人独立订阅，请返回选择 用户订阅，避免共用管理员链接"
    echoContent yellow "1.查看订阅链接"
    echoContent yellow "2.查看可用服务器"
    echoContent yellow "3.服务器源管理"
    echoContent yellow "4.查看我的流量"
    echoContent yellow "5.重置我的订阅"
    echoContent red "===================================================="
    read -r -p "请输入:" adminSubscriptionStatus
    if [[ "${adminSubscriptionStatus}" == "1" ]]; then
        subscribe
    elif [[ "${adminSubscriptionStatus}" == "2" ]]; then
        showSubscriptionSources
    elif [[ "${adminSubscriptionStatus}" == "3" ]]; then
        addSubscribeMenu 1
    elif [[ "${adminSubscriptionStatus}" == "4" ]]; then
        echoContent yellow " ---> 流量统计将在订阅组模型落地后启用"
    elif [[ "${adminSubscriptionStatus}" == "5" ]]; then
        showAccounts 1
    else
        echoContent red " ---> 选择错误"
    fi
}

manageUserSubscription() {
    ensureSubscriptionGroupsState
    echoContent red "\n===================== 用户订阅 ====================="
    echoContent yellow "说明：用户订阅会生成托管账号 sub_<ID>，同步后写入核心配置并输出独立订阅"
    echoContent yellow "推荐流程：新建用户订阅 -> 设置可用服务器 -> 查看本机同步计划 -> 立即执行同步"
    echoContent yellow "流量上限为只读统计与策略执行依据；0 表示不限额"
    echoContent yellow "1.查看用户订阅"
    echoContent yellow "2.新建用户订阅"
    echoContent yellow "3.管理用户订阅"
    echoContent red "===================================================="
    read -r -p "请输入:" userSubscriptionStatus
    if [[ "${userSubscriptionStatus}" == "1" ]]; then
        showUserSubscriptions
    elif [[ "${userSubscriptionStatus}" == "2" ]]; then
        createUserSubscription
    elif [[ "${userSubscriptionStatus}" == "3" ]]; then
        manageUserSubscriptionItem
    else
        echoContent red " ---> 选择错误"
    fi
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
        echoContent yellow " ---> 暂无用户订阅"
        return
    fi
    echoContent skyBlue "\nID:名称:状态:可用服务器:流量上限GB:限额状态"
    while IFS= read -r line; do
        echoContent green "${line}"
    done <<<"${output}"
}

createUserSubscription() {
    local id=
    local name=
    read -r -p "请输入用户订阅ID[英文/数字/短横线，例 team-a]:" id
    read -r -p "请输入用户订阅名称[例 家人A/团队A]:" name
    if [[ -z "${id}" || -z "${name}" ]] || ! echo "${id}" | grep -qE '^[a-zA-Z0-9_-]+$'; then
        echoContent red " ---> 输入有误"
        exit 0
    fi
    addUserSubscriptionState "${id}" "${name}"
    echoContent green " ---> 用户订阅已创建"
}

selectUserSubscriptionId() {
    local id=
    showUserSubscriptions
    read -r -p "请输入用户订阅ID:" id
    if [[ -z "${id}" ]]; then
        echoContent red " ---> 不可以为空"
        exit 0
    fi
    echo "${id}"
}


manageUserSubscriptionItem() {
    local userSubscriptionId
    userSubscriptionId=$(selectUserSubscriptionId)
    echoContent yellow " ---> 当前用户订阅: ${userSubscriptionId}"
    echoContent red "\n===================== 用户订阅管理 ====================="
    echoContent yellow "1.查看订阅链接"
    echoContent yellow "2.设置可用服务器"
    echoContent yellow "3.查看流量"
    echoContent yellow "4.设置流量上限"
    echoContent yellow "5.启用/停用"
    echoContent yellow "6.重置订阅"
    echoContent yellow "7.删除订阅"
    echoContent red "========================================================"
    read -r -p "请输入:" userSubscriptionItemStatus
    if [[ "${userSubscriptionItemStatus}" == "1" ]]; then
        subscribe
    elif [[ "${userSubscriptionItemStatus}" == "2" ]]; then
        setUserSubscriptionSourcesMenu "${userSubscriptionId}"
    elif [[ "${userSubscriptionItemStatus}" == "3" ]]; then
        showUserSubscriptionTraffic "${userSubscriptionId}"
    elif [[ "${userSubscriptionItemStatus}" == "4" ]]; then
        setUserSubscriptionTrafficLimitMenu "${userSubscriptionId}"
    elif [[ "${userSubscriptionItemStatus}" == "5" ]]; then
        toggleUserSubscriptionState "${userSubscriptionId}"
        echoContent green " ---> 用户订阅状态已切换"
    elif [[ "${userSubscriptionItemStatus}" == "6" ]]; then
        echoContent yellow " ---> 重置订阅将在 token 模型落地后启用"
    elif [[ "${userSubscriptionItemStatus}" == "7" ]]; then
        removeUserSubscriptionState "${userSubscriptionId}"
        removeUser
    else
        echoContent red " ---> 选择错误"
    fi
}

setUserSubscriptionSourcesMenu() {
    local userSubscriptionId=$1
    local sourceIds=
    local sourceJson=
    local line=

    echoContent skyBlue "\n可用服务器:"
    echoContent yellow "说明：main 表示本机；远程服务器源需先在 服务器 菜单添加并配置控制Token"
    echoContent yellow "可输入 main、远程服务器ID，或 * 表示允许全部服务器，多个用英文逗号分隔"
    while IFS= read -r line; do
        echoContent green "${line}"
    done < <(listSubscriptionSources)
    read -r -p "请输入授权服务器ID，多个用逗号分隔:" sourceIds
    if [[ -z "${sourceIds}" ]]; then
        echoContent red " ---> 不可以为空"
        exit 0
    fi
    sourceJson=$(printf '%s' "${sourceIds}" | jq -R 'split(",") | map(gsub("^ +| +$"; "")) | map(select(length > 0))')
    setUserSubscriptionSources "${userSubscriptionId}" "${sourceJson}"
    echoContent green " ---> 可用服务器已更新"
}

setUserSubscriptionTrafficLimitMenu() {
    local userSubscriptionId=$1
    local limit=
    read -r -p "请输入流量上限GB[0为不限，仅统计和策略使用]:" limit
    if [[ -z "${limit}" ]] || ! echo "${limit}" | grep -qE '^[0-9]+$'; then
        echoContent red " ---> 输入有误"
        exit 0
    fi
    setUserSubscriptionTrafficLimit "${userSubscriptionId}" "${limit}"
    echoContent green " ---> 流量上限已更新"
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
        echoContent red " ---> Xray 流量统计策略配置生成失败"
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
          (reduce .stat[]? as $stat ({};
            accountName($stat.name) as $account |
            if ($accounts | index($account)) then
              .[$account][direction($stat.name)] += ($stat.value // 0)
            else . end) as $totals |
          $accounts | map({account: ., upload: (. as $account | $totals[$account].upload // 0), download: (. as $account | $totals[$account].download // 0)})
        ) ' <<<"${stats}"
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
        echoContent yellow " ---> 流量统计采集失败，已保留上次统计"
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
        echoContent green " ---> 流量统计已更新"
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

showUserSubscriptionTraffic() {
    local userSubscriptionId=$1
    local groupId
    groupId=$(activeSubscriptionGroupId)
    ensureSubscriptionGroupsState
    showUserSubscriptionQuota "${userSubscriptionId}"
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" --arg id "${userSubscriptionId}" '.groups[] | select(.id == $groupId) | .traffic.user_groups[$id] // {upload:0, download:0, sources:{}}'
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

manageSubscriptionServers() {
    echoContent red "\n======================= 服务器 ======================="
    echoContent yellow "说明：main 是本机服务器源，不可删除或停用；secondary 是远程服务器源"
    echoContent yellow "远程同步需要对端订阅服务暴露 /s/control/，并在本机为该服务器源保存控制Token"
    echoContent yellow "推荐流程：服务器源管理 -> 设置控制Token -> 测试连接 -> 查看远程同步计划 -> 立即执行同步"
    echoContent yellow "1.查看服务器"
    echoContent yellow "2.服务器源管理"
    echoContent yellow "3.测试连接"
    echoContent yellow "4.设置控制Token"
    echoContent yellow "5.查看控制URL"
    echoContent yellow "6.查看同步结果"
    echoContent yellow "7.启用/停用服务器"
    echoContent yellow "8.清除同步错误"
    echoContent red "======================================================"
    read -r -p "请输入:" subscriptionServersStatus
    if [[ "${subscriptionServersStatus}" == "1" ]]; then
        showSubscriptionSources
    elif [[ "${subscriptionServersStatus}" == "2" ]]; then
        addSubscribeMenu 1
    elif [[ "${subscriptionServersStatus}" == "3" ]]; then
        subscriptionRemoteControlHealthAll | jq .
    elif [[ "${subscriptionServersStatus}" == "4" ]]; then
        local sourceId=
        local token=
        listSubscriptionSources | awk -F ':' '$3 != "main" {print $1":"$2":"$4":"$5":"$6":"$8}'
        read -r -p "请输入服务器源ID:" sourceId
        if [[ -z "${sourceId}" ]]; then
            echoContent red " ---> 服务器源ID不可为空"
            exit 0
        fi
        read -r -p "请输入控制Token:" token
        if [[ -z "${token}" ]]; then
            echoContent red " ---> 控制Token不可为空"
            exit 0
        fi
        setSubscriptionSourceControlToken "${sourceId}" "${token}"
        echoContent green " ---> 控制Token已保存"
    elif [[ "${subscriptionServersStatus}" == "5" ]]; then
        showSubscriptionSourceControlUrls
    elif [[ "${subscriptionServersStatus}" == "6" ]]; then
        showSubscriptionSourceSyncResults
    elif [[ "${subscriptionServersStatus}" == "7" ]]; then
        local sourceId=
        local sourceAction=
        listSubscriptionSources | awk -F ':' '$3 != "main" {print $1":"$2":启用="$7}'
        read -r -p "请输入服务器源ID:" sourceId
        if [[ -z "${sourceId}" ]] || ! subscriptionSourceExists "${sourceId}" || subscriptionSourceIsMain "${sourceId}"; then
            echoContent red " ---> 服务器源ID无效"
            exit 0
        fi
        read -r -p "请输入操作[enable/disable]:" sourceAction
        if [[ "${sourceAction}" == "enable" ]]; then
            setSubscriptionSourceEnabled "${sourceId}" true
            echoContent green " ---> 服务器源已启用"
        elif [[ "${sourceAction}" == "disable" ]]; then
            setSubscriptionSourceEnabled "${sourceId}" false
            echoContent green " ---> 服务器源已停用"
        else
            echoContent red " ---> 操作无效"
        fi
    elif [[ "${subscriptionServersStatus}" == "8" ]]; then
        local sourceId=
        showSubscriptionSourceSyncResults
        read -r -p "请输入要清除错误的服务器源ID:" sourceId
        if [[ -z "${sourceId}" ]] || ! subscriptionSourceExists "${sourceId}"; then
            echoContent red " ---> 服务器源ID无效"
            exit 0
        fi
        clearSubscriptionSourceSyncError "${sourceId}"
        echoContent green " ---> 同步错误已清除"
    else
        echoContent red " ---> 选择错误"
    fi
}

manageSubscriptionTraffic() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    echoContent red "\n======================= 流量 ======================="
    echoContent yellow "说明：流量统计优先读取 Xray stats API；首次刷新会建立计数基线，后续按增量累计"
    echoContent yellow "如果采集失败会保留上次统计，不会写入 0 覆盖历史用量"
    echoContent yellow "限额状态只用于提示和策略执行，是否停用用户由限额计划决定"
    echoContent yellow "1.刷新并查看总流量"
    echoContent yellow "2.刷新并查看我的流量"
    echoContent yellow "3.刷新并查看用户订阅流量"
    echoContent yellow "4.刷新并查看服务器流量"
    echoContent red "===================================================="
    read -r -p "请输入:" subscriptionTrafficStatus
    if [[ "${subscriptionTrafficStatus}" =~ ^[1-4]$ ]]; then
        collectSubscriptionTraffic
    fi
    if [[ "${subscriptionTrafficStatus}" == "1" ]]; then
        subscriptionGroupsStateRead -r --arg groupId "${groupId}" '.groups[] | select(.id == $groupId) | .traffic.global'
    elif [[ "${subscriptionTrafficStatus}" == "2" ]]; then
        subscriptionGroupsStateRead -r --arg groupId "${groupId}" '.groups[] | select(.id == $groupId) | .traffic.admin'
    elif [[ "${subscriptionTrafficStatus}" == "3" ]]; then
        subscriptionGroupsStateRead -r --arg groupId "${groupId}" '.groups[] | select(.id == $groupId) | .traffic.user_groups'
    elif [[ "${subscriptionTrafficStatus}" == "4" ]]; then
        subscriptionGroupsStateRead -r --arg groupId "${groupId}" '.groups[] | select(.id == $groupId) | .traffic.sources'
    else
        echoContent red " ---> 选择错误"
    fi
}

manageSubscriptionStateBackups() {
    local backupFile
    local confirm
    echoContent red "\n======================= 状态备份 ======================="
    echoContent yellow "说明：备份对象是订阅组状态 groups.json，包含用户订阅、服务器源、同步状态和流量统计"
    echoContent yellow "恢复会覆盖当前订阅组状态；不会自动回滚核心配置文件或证书"
    echoContent yellow "1.创建备份"
    echoContent yellow "2.查看备份"
    echoContent yellow "3.恢复备份"
    echoContent red "========================================================"
    read -r -p "请输入:" backupStatus
    if [[ "${backupStatus}" == "1" ]]; then
        backupFile=$(createSubscriptionGroupsBackup)
        echoContent green " ---> 已创建备份: ${backupFile}"
    elif [[ "${backupStatus}" == "2" ]]; then
        listSubscriptionGroupsBackups
    elif [[ "${backupStatus}" == "3" ]]; then
        listSubscriptionGroupsBackups
        read -r -p "请输入要恢复的备份完整路径:" backupFile
        if [[ -z "${backupFile}" ]]; then
            echoContent red " ---> 备份路径不可为空"
            exit 0
        fi
        read -r -p "恢复会覆盖当前订阅组状态，确认请输入 yes:" confirm
        if [[ "${confirm}" != "yes" ]]; then
            echoContent yellow " ---> 已取消"
            return
        fi
        if restoreSubscriptionGroupsBackup "${backupFile}"; then
            echoContent green " ---> 状态已恢复"
        else
            echoContent red " ---> 状态恢复失败"
        fi
    else
        echoContent red " ---> 选择错误"
    fi
}

manageSubscriptionSettings() {
    echoContent red "\n======================= 设置 ======================="
    echoContent yellow "说明：订阅服务负责发布链接；自动同步负责把用户订阅写入本机和远程服务器"
    echoContent yellow "改动远程同步、限额自动执行或恢复备份前，建议先创建状态备份"
    echoContent yellow "1.订阅服务"
    echoContent yellow "2.自动同步"
    echoContent yellow "3.状态备份"
    echoContent red "===================================================="
    read -r -p "请输入:" subscriptionSettingsStatus
    if [[ "${subscriptionSettingsStatus}" == "1" ]]; then
        installSubscribe
    elif [[ "${subscriptionSettingsStatus}" == "2" ]]; then
        manageSubscriptionSyncSettings
    elif [[ "${subscriptionSettingsStatus}" == "3" ]]; then
        manageSubscriptionStateBackups
    else
        echoContent red " ---> 选择错误"
    fi
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
        echoContent green " ---> 当前没有需要执行的限额计划"
        return
    fi
    echoContent yellow " ---> 将执行以下限额计划，仅停用用户订阅状态，账号删除由同步流程处理"
    echo "${plan}" | jq .
    read -r -p "确认执行请输入 yes:" confirm
    if [[ "${confirm}" != "yes" ]]; then
        echoContent yellow " ---> 已取消"
        return
    fi
    if ! collectSubscriptionTraffic; then
        echoContent red " ---> 流量统计刷新失败，已取消执行限额计划"
        return
    fi
    plan=$(subscriptionQuotaDryRunPlan)
    if [[ "$(jq 'length' <<<"${plan}")" == "0" ]]; then
        echoContent green " ---> 刷新后没有需要执行的限额计划"
        return
    fi
    applySubscriptionQuotaPlan "${plan}"
    echoContent green " ---> 限额计划已执行，请运行同步计划或立即同步以移除对应账号"
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
        echoContent yellow " ---> 订阅组同步正在执行，跳过本轮"
        return 0
    fi
    trap 'rmdir "${lockDir}" >/dev/null 2>&1' RETURN

    ensureSubscriptionGroupsState
    if ! subscriptionGroupSyncEnabled; then
        echoContent yellow " ---> 订阅组自动同步未开启，跳过本轮"
        return 0
    fi
    readInstallType
    readInstallProtocolType
    if [[ -z "${configPath}" ]]; then
        echoContent yellow " ---> 未检测到安装配置，跳过订阅组同步"
        return 0
    fi
    echoContent skyBlue " ---> 开始执行订阅组自动同步: $(date '+%Y-%m-%d %H:%M:%S')"
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
    currentCron=$(crontab -l 2>/dev/null | sed '/SyncSubscriptionGroups/d')
    syncCron="*/${interval} * * * * /bin/bash ${scriptPath} SyncSubscriptionGroups >> /etc/padm/crontab_subscription_sync.log 2>&1"
    printf '%s\n%s\n' "${currentCron}" "${syncCron}" | sed '/^$/d' >"${cronFile}"
    crontab "${cronFile}"
}

removeSubscriptionGroupSyncCron() {
    local cronFile
    cronFile=$(subscriptionGroupSyncCronFile)
    mkdir -p "$(dirname "${cronFile}")"
    crontab -l 2>/dev/null | sed '/SyncSubscriptionGroups/d' >"${cronFile}"
    crontab "${cronFile}"
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
    groupId=$(activeSubscriptionGroupId)
    syncStatus=$(subscriptionGroupsStateRead -r --arg groupId "${groupId}" '.groups[] | select(.id == $groupId) | .sync')
    echoContent skyBlue "\n当前自动同步状态:"
    echoContent yellow "说明：自动同步会按用户订阅生成 sub_<ID> 托管账号，并删除不再期望的托管账号"
    echoContent yellow "建议先看本机/远程同步计划，确认 create/remove 后再立即执行同步"
    echoContent yellow "限额自动执行默认关闭；开启后超限用户会被停用并在同步中移除托管账号"
    echo "${syncStatus}" | jq .
    echoContent yellow "1.开启/关闭自动同步"
    echoContent yellow "2.设置自动同步间隔"
    echoContent yellow "3.立即执行同步"
    echoContent yellow "4.查看本机同步计划"
    echoContent yellow "5.查看远程同步计划"
    echoContent yellow "6.查看限额计划"
    echoContent yellow "7.执行限额计划"
    echoContent yellow "8.开启/关闭远程同步"
    echoContent yellow "9.开启/关闭限额自动执行"
    echoContent yellow "10.查看定时任务"
    read -r -p "请输入:" syncSettingsStatus
    if [[ "${syncSettingsStatus}" == "1" ]]; then
        subscriptionGroupsStateWrite --arg groupId "${groupId}" '.groups |= map(if .id == $groupId then .sync.enabled = (.sync.enabled | not) else . end)'
        refreshSubscriptionGroupSyncCron
        echoContent green " ---> 自动同步状态已切换"
    elif [[ "${syncSettingsStatus}" == "2" ]]; then
        local interval=
        read -r -p "请输入同步间隔分钟:" interval
        if ! subscriptionGroupSyncIntervalValid "${interval}"; then
            echoContent red " ---> 输入有误，同步间隔需为1-59分钟"
            exit 0
        fi
        subscriptionGroupsStateWrite --arg groupId "${groupId}" --argjson interval "${interval}" '.groups |= map(if .id == $groupId then .sync.interval_minutes = $interval else . end)'
        refreshSubscriptionGroupSyncCron
        echoContent green " ---> 自动同步间隔已更新"
    elif [[ "${syncSettingsStatus}" == "3" ]]; then
        runSubscriptionGroupSync
    elif [[ "${syncSettingsStatus}" == "4" ]]; then
        readInstallType
        readInstallProtocolType
        subscriptionSyncPlan | jq .
    elif [[ "${syncSettingsStatus}" == "5" ]]; then
        subscriptionRemoteSyncPlan | jq .
    elif [[ "${syncSettingsStatus}" == "6" ]]; then
        subscriptionQuotaDryRunPlan | jq .
    elif [[ "${syncSettingsStatus}" == "7" ]]; then
        executeSubscriptionQuotaPlanMenu
    elif [[ "${syncSettingsStatus}" == "8" ]]; then
        subscriptionGroupsStateWrite --arg groupId "${groupId}" '.groups |= map(if .id == $groupId then .sync.remote_enabled = ((.sync.remote_enabled // true) | not) else . end)'
        echoContent green " ---> 远程同步状态已切换"
    elif [[ "${syncSettingsStatus}" == "9" ]]; then
        subscriptionGroupsStateWrite --arg groupId "${groupId}" '.groups |= map(if .id == $groupId then .sync.quota_auto_apply = ((.sync.quota_auto_apply // false) | not) else . end)'
        echoContent green " ---> 限额自动执行状态已切换"
    elif [[ "${syncSettingsStatus}" == "10" ]]; then
        subscriptionGroupSyncCronStatus
    else
        echoContent red " ---> 选择错误"
    fi
}
