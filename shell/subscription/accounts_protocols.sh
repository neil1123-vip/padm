#!/usr/bin/env bash

subscriptionAccountProfile() {
    local user=$1
    jq -r '[
      ((.email // .name // .username // "") | tostring),
      ((.id // .uuid // "") | tostring),
      ((.password // "") | tostring),
      ((.username // .name // .email // "") | tostring),
      ((.name // .email // .username // "") | tostring),
      ((.uuid // .id // "") | tostring)
    ] | join("\u001f")' <<<"${user}"
}

showVlessTcpAccounts() {
    # VLESS TCP
    if currentProtocolHas 27; then

        subscribeSectionTitle "VLESS TCP TLS Vision" "传统 TLS 兼容方案"
        jq -c '(.inbounds[0].settings.clients // .inbounds[0].users)[]' ${configPath}02_VLESS_TCP_inbounds.json | while read -r user; do
            local email accountId
            IFS=$'\037' read -r email accountId _ _ _ _ <<<"$(subscriptionAccountProfile "${user}")"

            subscribeAccountTitle "${email}"
            echo
            defaultBase64Code vlesstcp "${currentDefaultPort:-${singBoxVLESSVisionPort}}" "${email}" "${accountId}" || return 1
        done
    fi

}

showVlessWsAccounts() {
    # VLESS WS
    if currentProtocolHas 21; then
        subscribeSectionTitle "VLESS WS TLS" "兼容旧客户端，不作为新手推荐"

        jq -c '(.inbounds[0].settings.clients // .inbounds[0].users)[]' ${configPath}03_VLESS_WS_inbounds.json | while read -r user; do
            local email accountId
            IFS=$'\037' read -r email accountId _ _ _ _ <<<"$(subscriptionAccountProfile "${user}")"

            local vlessWSPort=${currentDefaultPort}
            if [[ "${coreInstallType}" == "2" ]]; then
                vlessWSPort="${singBoxVLESSWSPort}"
            fi
            echo
            local path="${currentPath}ws"

            if [[ ${coreInstallType} == "1" ]]; then
                path="/${currentPath}ws"
            elif [[ "${coreInstallType}" == "2" ]]; then
                path="${singBoxVLESSWSPath}"
            fi

            local count=
            while read -r line; do
                subscribeAccountTitle "${email}${count}"
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vlessws "${vlessWSPort}" "${email}${count}" "${accountId}" "${line}" "${path}" || return 1
                    count=$((count + 1))
                    echo
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')
        done
    fi
}

showTrojanGrpcAccounts() {
    # trojan grpc
    if currentProtocolHas 25; then
        subscribeSectionTitle "Trojan gRPC TLS" "兼容旧客户端，不作为新手推荐"
        jq -c '.inbounds[0].settings.clients[]' ${configPath}04_trojan_GRPc_inbounds.json | while read -r user; do
            local email password
            IFS=$'\037' read -r email _ password _ _ _ <<<"$(subscriptionAccountProfile "${user}")"
            local count=
            while read -r line; do
                subscribeAccountTitle "${email}${count}"
                echo
                if [[ -n "${line}" ]]; then
                    defaultBase64Code trojangrpc "${currentDefaultPort}" "${email}${count}" "${password}" "${line}" || return 1
                    count=$((count + 1))
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')

        done
    fi
}

showVmessWsAccounts() {
    # VMess WS
    if currentProtocolHas 22; then
        subscribeSectionTitle "VMess WS TLS" "兼容旧客户端，不作为新手推荐"
        local path="${currentPath}vws"
        if [[ ${coreInstallType} == "1" ]]; then
            path="/${currentPath}vws"
        elif [[ "${coreInstallType}" == "2" ]]; then
            path="${singBoxVMessWSPath}"
        fi
        jq -c '(.inbounds[0].settings.clients // .inbounds[0].users)[]' ${configPath}05_VMess_WS_inbounds.json | while read -r user; do
            local email accountId
            IFS=$'\037' read -r email accountId _ _ _ _ <<<"$(subscriptionAccountProfile "${user}")"

            local vmessPort=${currentDefaultPort}
            if [[ "${coreInstallType}" == "2" ]]; then
                vmessPort="${singBoxVMessWSPort}"
            fi

            local count=
            while read -r line; do
                subscribeAccountTitle "${email}${count}"
                echo
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vmessws "${vmessPort}" "${email}${count}" "${accountId}" "${line}" "${path}" || return 1
                    count=$((count + 1))
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')
        done
    fi

}

showTrojanAccounts() {
    # trojan tcp
    if currentProtocolHas 28 || currentProtocolHas 29; then
        subscribeSectionTitle "Trojan TLS" "不推荐"
        if currentProtocolHas 28; then
            showTrojanAccountsFromConfig "${configPath}28_trojan_TCP_direct_inbounds.json" "${currentDefaultPort:-${singBoxTrojanPort}}" || return 1
            if [[ "${coreInstallType}" == "1" && -f "${singBoxConfigPath}28_trojan_TCP_direct_inbounds.json" ]]; then
                showTrojanAccountsFromConfig "${singBoxConfigPath}28_trojan_TCP_direct_inbounds.json" "${singBoxTrojanPort}" || return 1
            fi
        fi
        if currentProtocolHas 29; then
            showTrojanAccountsFromConfig "${configPath}04_trojan_TCP_inbounds.json" "${currentDefaultPort}" || return 1
        fi
    fi
}

showTrojanAccountsFromConfig() (
    set -o pipefail
    local trojanConfigFile=$1 port=$2
    [[ -f "${trojanConfigFile}" ]] || return 0
    jq -c '(.inbounds[0].settings.clients // .inbounds[0].users) | if type == "array" then .[] else error("invalid clients") end' "${trojanConfigFile}" | while read -r user; do
            local email password
            IFS=$'\037' read -r email _ password _ _ _ <<<"$(subscriptionAccountProfile "${user}")"
            subscribeAccountTitle "${email}"

            defaultBase64Code trojan "${port}" "${email}" "${password}" || return 1
        done
)

showVlessGrpcAccounts() {
    # VLESS grpc
    if currentProtocolHas 24; then
        subscribeSectionTitle "VLESS gRPC TLS" "兼容旧客户端，不作为新手推荐"
        jq -c '.inbounds[0].settings.clients[]' ${configPath}06_VLESS_GRPc_inbounds.json | while read -r user; do
            local email accountId
            IFS=$'\037' read -r email accountId _ _ _ _ <<<"$(subscriptionAccountProfile "${user}")"

            local count=
            while read -r line; do
                subscribeAccountTitle "${email}${count}"
                echo
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vlessgrpc "${currentDefaultPort}" "${email}${count}" "${accountId}" "${line}" || return 1
                    count=$((count + 1))
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')

        done
    fi
}

showHysteriaAccounts() {
    # hysteria2
    if currentProtocolHas 3 || [[ -n "${hysteriaPort:-}" ]]; then
        readPortHopping "hysteria2" "${singBoxHysteria2Port}" || return 1
        subscribeSectionTitle "Hysteria2 TLS" "UDP/移动网络可选"
        local configFile currentHost
        configFile=$(protocolConfigFile 3) || return 1
        if ! currentHost=$(jq -er '.inbounds[0].tls.server_name | select(type == "string" and length > 0)' "${configFile}") ||
            ! padmIsValidConnectAddress "${currentHost}"; then
            errorCard "Hysteria2 订阅生成失败" "协议配置缺少有效的 TLS 域名"
            return 1
        fi
        local hysteria2DefaultPort=
        if [[ -n "${hysteria2PortHoppingStart}" && -n "${hysteria2PortHoppingEnd}" ]]; then
            hysteria2DefaultPort="${hysteria2PortHopping}"
        else
            hysteria2DefaultPort=${singBoxHysteria2Port}
        fi

        jq -r -c '.inbounds[]|.users[]' "${configFile}" | while read -r user; do
            local name password
            IFS=$'\037' read -r _ _ password _ name _ <<<"$(subscriptionAccountProfile "${user}")"
            subscribeAccountTitle "${name}"
            echo
            defaultBase64Code hysteria "${hysteria2DefaultPort}" "${name}" "${password}" || return 1
        done

    fi

}

showVlessRealityAccounts() {
    # VLESS Reality Vision
    if currentProtocolHas 1; then
        subscribeSectionTitle "VLESS reality_vision" "推荐"
        local port=${xrayVLESSRealityVisionPort:-${xrayVLESSRealityPort:-}}
        [[ "${coreInstallType}" != 2 ]] || port=${singBoxVLESSRealityVisionPort}
        showVlessRealityAccountsFromConfig "${coreInstallType}" "${configPath}07_VLESS_vision_reality_inbounds.json" "${port}" || return 1
        if [[ "${coreInstallType}" == "1" && -f "${singBoxConfigPath}07_VLESS_vision_reality_inbounds.json" ]]; then
            showVlessRealityAccountsFromConfig 2 "${singBoxConfigPath}07_VLESS_vision_reality_inbounds.json" "${singBoxVLESSRealityVisionPort}" || return 1
        fi
    fi
}

showVlessRealityAccountsFromConfig() (
    set -eo pipefail
    local core=$1 configFile=$2 port=$3
    [[ -f "${configFile}" ]] || return 0
    coreInstallType=${core}
    configPath="$(dirname -- "${configFile}")/"
    local usersFilter='(.inbounds[1].settings.clients // .inbounds[0].users)'
    local realityVisionPort=${port}
    if [[ "${core}" == "1" ]]; then
        local streamPublicPort entryPort
        streamPublicPort=$(realityStreamPublicPortForProtocol vision) || return 1
        [[ -z "${streamPublicPort}" ]] || realityVisionPort=${streamPublicPort}
        entryPort=$(jq -r '.inbounds[0].port' "${configFile}") || return 1
        realityVisionPort=$(corePortSubscriptionPort "${entryPort}" "${realityVisionPort}") || return 1
    fi
    [[ "${core}" == "2" ]] && usersFilter='.inbounds[0].users'
    jq -c "${usersFilter} | if type == \"array\" then .[] else error(\"invalid clients\") end" "${configFile}" | while read -r user; do
            local email accountId
            IFS=$'\037' read -r email accountId _ _ _ _ <<<"$(subscriptionAccountProfile "${user}")"

            subscribeAccountTitle "${email}"
            echo
            defaultBase64Code vlessReality "${realityVisionPort}" "${email}" "${accountId}" || return 1
        done
)

showVlessRealityGrpcAccounts() {
    # VLESS Reality gRPC
    if currentProtocolHas 26; then
        subscribeSectionTitle "VLESS reality_gRPC" "推荐"
        if [[ "${coreInstallType}" == "2" ]]; then
            showVlessRealityGrpcAccountsFromConfig "${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json" "${singBoxVLESSRealityGRPCPort:-}" "${singBoxVLESSRealityGRPCSNI:-}" "${singBoxVLESSRealityPublicKey:-}" "" || return 1
        else
            showVlessRealityGrpcAccountsFromConfig "${configPath}08_VLESS_vision_gRPC_inbounds.json" "${xrayVLESSRealityGRPCPort:-}" "${xrayVLESSRealityGRPCSNI:-}" "${xrayVLESSRealityGRPCPublicKey:-${currentRealityPublicKey:-}}" "${xrayVLESSRealityGRPCMldsa65Verify:-}" || return 1
        fi
        if [[ "${coreInstallType}" == "1" && -n "${singBoxConfigPath}" && -f "${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json" ]]; then
            showVlessRealityGrpcAccountsFromConfig "${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json" "${singBoxVLESSRealityGRPCPort:-}" "${singBoxVLESSRealityGRPCSNI:-}" "${singBoxVLESSRealityPublicKey:-}" "" || return 1
        fi
    fi
}

showVlessRealityGrpcAccountsFromConfig() (
    set -o pipefail
    local configFile=$1
    local realityGRPCPort=$2
    local realityGRPCSNI=$3
    local realityGRPCPublicKey=$4
    local realityGRPCMldsa65Verify=$5
    [[ -f "${configFile}" ]] || return 0
    if jq -e '.inbounds[0].port' "${configFile}" >/dev/null 2>&1; then
        realityGRPCPort=$(corePortSubscriptionPort "$(jq -r '.inbounds[0].port' "${configFile}")" "${realityGRPCPort}") || return 1
    fi
    jq -c '(.inbounds[0].settings.clients // .inbounds[0].users) | if type == "array" then .[] else error("invalid clients") end' "${configFile}" | while read -r user; do
            local email accountId
            IFS=$'\037' read -r email accountId _ _ _ _ <<<"$(subscriptionAccountProfile "${user}")"

            subscribeAccountTitle "${email}"
            echo
            local xrayVLESSRealitySNI="${realityGRPCSNI}"
            local currentRealityPublicKey="${realityGRPCPublicKey}"
            local currentRealityMldsa65Verify="${realityGRPCMldsa65Verify}"
            local singBoxVLESSRealityGRPCSNI="${realityGRPCSNI}"
            local singBoxVLESSRealityPublicKey="${realityGRPCPublicKey}"
            defaultBase64Code vlessRealityGRPC "${realityGRPCPort}" "${email}" "${accountId}" || return 1
        done
)

showTuicAccounts() {
    # TUIC
    if currentProtocolHas 31 || [[ -n "${tuicPort:-}" ]]; then
        readPortHopping "tuic" "${singBoxTuicPort}" || return 1
        subscribeSectionTitle "Tuic TLS" "UDP/移动网络可选"
        local configFile currentHost
        configFile=$(protocolConfigFile 31) || return 1
        if ! currentHost=$(jq -er '.inbounds[0].tls.server_name | select(type == "string" and length > 0)' "${configFile}") ||
            ! padmIsValidConnectAddress "${currentHost}"; then
            errorCard "TUIC 订阅生成失败" "协议配置缺少有效的 TLS 域名"
            return 1
        fi
        local tuicDefaultPort=${singBoxTuicPort}
        if [[ -n "${tuicPortHoppingStart:-}" && -n "${tuicPortHoppingEnd:-}" ]]; then
            tuicDefaultPort="${tuicPortHopping}"
        fi
        jq -r -c '.inbounds[].users[]' "${configFile}" | while read -r user; do
            local name uuid password
            IFS=$'\037' read -r _ _ password _ name uuid <<<"$(subscriptionAccountProfile "${user}")"
            subscribeAccountTitle "${name}"
            echo
            defaultBase64Code tuic "${tuicDefaultPort}" "${name}" "${uuid}_${password}" || return 1
        done

    fi
}

showNaiveAccounts() {
    # Naive
    if currentProtocolHas 5 || [[ -n "${singBoxNaivePort:-}" ]]; then
        subscribeSectionTitle "naive TLS" "推荐，不支持ClashMeta"
        local path="${configPath}"
        if [[ "${coreInstallType}" == "1" && -n "${singBoxConfigPath}" && -f "${singBoxConfigPath}10_naive_inbounds.json" ]]; then
            path="${singBoxConfigPath}"
        fi
        jq -r -c '.inbounds[]|.users[]' "${path}10_naive_inbounds.json" | while read -r user; do
            local username password
            IFS=$'\037' read -r _ _ password username _ _ <<<"$(subscriptionAccountProfile "${user}")"
            subscribeAccountTitle "${username}"
            echo
            defaultBase64Code naive "${singBoxNaivePort}" "${username}" "${password}" || return 1
        done

    fi
}

showShadowsocksAccounts() {
    # Shadowsocks
    if currentProtocolHas 30; then
        subscribeSectionTitle "Shadowsocks" "高级兼容协议"
        local path="${configPath}"
        if [[ "${coreInstallType}" == "1" && -n "${singBoxConfigPath}" && -f "${singBoxConfigPath}30_shadowsocks_inbounds.json" ]]; then
            path="${singBoxConfigPath}"
        fi
        local serverPassword
        serverPassword=$(jq -r '.inbounds[0].password // empty' "${path}30_shadowsocks_inbounds.json")
        jq -r -c '.inbounds[]|.users[]' "${path}30_shadowsocks_inbounds.json" | while read -r user; do
            local name password
            IFS=$'\037' read -r _ _ password _ name _ <<<"$(subscriptionAccountProfile "${user}")"
            subscribeAccountTitle "${name}"
            echo
            defaultBase64Code shadowsocks "${singBoxShadowsocksPort}" "${name}" "${serverPassword}:${password}" || return 1
        done

    fi
}

showVmessHTTPUpgradeAccounts() {
    # VMess HTTPUpgrade
    if currentProtocolHas 23; then
        subscribeSectionTitle "VMess HTTPUpgrade TLS" "兼容旧客户端，不作为新手推荐"
        local path="${currentPath}vws" vmessHTTPUpgradePort="${currentDefaultPort}"
        if [[ ${coreInstallType} == "1" ]]; then
            path="/${currentPath}"
            if [[ -f "${configPath}11_VMess_HTTPUpgrade_inbounds.json" ]]; then
                path=$(jq -r '.inbounds[0].streamSettings.httpupgradeSettings.path // empty' "${configPath}11_VMess_HTTPUpgrade_inbounds.json")
                path=${path:-/${currentPath}}
            fi
        elif [[ "${coreInstallType}" == "2" ]]; then
            path="${singBoxVMessHTTPUpgradePath}"
            vmessHTTPUpgradePort="${singBoxVMessHTTPUpgradePort}"
        fi
        showVmessHTTPUpgradeAccountsFromConfig "${configPath}11_VMess_HTTPUpgrade_inbounds.json" "${vmessHTTPUpgradePort}" "${path}" || return 1
        if [[ "${coreInstallType}" == "1" && -n "${singBoxConfigPath}" && -f "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json" ]]; then
            local currentHost currentCDNAddress
            currentHost=$(awk '$1 == "server_name" { sub(/;$/, "", $2); print $2; exit }' "${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf") || return 1
            padmIsValidHostName "${currentHost}" || return 1
            currentCDNAddress=$(cdnStoredAddress) || return 1
            currentCDNAddress=${currentCDNAddress:-${currentHost}}
            showVmessHTTPUpgradeAccountsFromConfig "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json" "${singBoxVMessHTTPUpgradePort}" "${singBoxVMessHTTPUpgradePath}"
        fi
    fi
}

showVmessHTTPUpgradeAccountsFromConfig() (
    set -o pipefail
    local configFile=$1 vmessHTTPUpgradePort=$2 path=$3
    [[ -f "${configFile}" ]] || return 0
    jq -c '(.inbounds[0].settings.clients // .inbounds[0].users) | if type == "array" then .[] else error("invalid clients") end' "${configFile}" | while read -r user; do
            local email accountId
            IFS=$'\037' read -r email accountId _ _ _ _ <<<"$(subscriptionAccountProfile "${user}")"

            local count=
            while read -r line; do
                subscribeAccountTitle "${email}${count}"
                echo
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vmessHTTPUpgrade "${vmessHTTPUpgradePort}" "${email}${count}" "${accountId}" "${line}" "${path}" || return 1
                    count=$((count + 1))
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')
        done
)

showVlessRealityXHTTPAccounts() {
    # VLESS Reality XHTTP
    if currentProtocolHas 2; then
        subscribeSectionTitle "VLESS Reality XHTTP" "CDN推荐"

        local path xhttpPort streamPublicPort xhttpEntryPort
        path=$(xrayRealityXHTTPSetting path "/${currentPath}xHTTP")
        xhttpPort=${xrayVLESSRealityXHTTPort}
        streamPublicPort=$(realityStreamPublicPortForProtocol xhttp) || return 1
        [[ -z "${streamPublicPort}" ]] || xhttpPort=${streamPublicPort}
        xhttpEntryPort=$(jq -r '.inbounds[0].port' "${configPath}12_VLESS_XHTTP_inbounds.json") || return 1
        xhttpPort=$(corePortSubscriptionPort "${xhttpEntryPort}" "${xhttpPort}") || return 1
        jq -c '(.inbounds[0].settings.clients // .inbounds[0].users)[]' ${configPath}12_VLESS_XHTTP_inbounds.json | while read -r user; do
            local email accountId
            IFS=$'\037' read -r email accountId _ _ _ _ <<<"$(subscriptionAccountProfile "${user}")"
            echo

            local count=
            while read -r line; do
                subscribeAccountTitle "${email}${count}"
                if [[ -z "${line}" ]]; then
                    line=$(realityEntryHost)
                fi
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vlessXHTTP "${xhttpPort}" "${email}${count}" "${accountId}" "${line}" "${path}" || return 1
                    count=$((count + 1))
                    echo
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')
        done
    fi
}

showAnyTlsAccounts() {
    # AnyTLS
    if currentProtocolHas 4; then
        subscribeSectionTitle "AnyTLS" "TLS 兼容协议"
        local path="${configPath}"
        if [[ "${coreInstallType}" == "1" && -n "${singBoxConfigPath}" && -f "${singBoxConfigPath}13_anytls_inbounds.json" ]]; then
            path="${singBoxConfigPath}"
        fi
        jq -r -c '.inbounds[]|.users[]' "${path}13_anytls_inbounds.json" | while read -r user; do
            local name password
            IFS=$'\037' read -r _ _ password _ name _ <<<"$(subscriptionAccountProfile "${user}")"
            subscribeAccountTitle "${name}"
            echo
            defaultBase64Code anytls "${singBoxAnyTLSPort}" "${name}" "${password}" || return 1
        done

    fi
}
