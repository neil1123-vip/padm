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
