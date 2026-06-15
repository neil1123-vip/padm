#!/usr/bin/env bash

# 读取 TLS 证书详情
readAcmeTLS() {
    local readAcmeDomain=
    if [[ -n "${currentHost}" ]]; then
        readAcmeDomain="${currentHost}"
    fi

    if [[ -n "${domain}" ]]; then
        readAcmeDomain="${domain}"
    fi

    dnsTLSDomain=$(echo "${readAcmeDomain}" | awk -F "." '{$1="";print $0}' | sed 's/^[[:space:]]*//' | sed 's/ /./g')
    if [[ -d "$HOME/.acme.sh/*.${dnsTLSDomain}_ecc" && -f "$HOME/.acme.sh/*.${dnsTLSDomain}_ecc/*.${dnsTLSDomain}.key" && -f "$HOME/.acme.sh/*.${dnsTLSDomain}_ecc/*.${dnsTLSDomain}.cer" ]]; then
        installedDNSAPIStatus=true
    fi
}

# 读取默认自定义端口
readCustomPort() {
    if [[ -n "${configPath}" && -z "${realityStatus}" && "${coreInstallType}" == "1" ]]; then
        local port=
        port=$(jq -r .inbounds[0].port "${configPath}${frontingType}.json")
        if [[ "${port}" != "443" ]]; then
            customPort=${port}
        fi
    fi
}

# 读取 Nginx 订阅端口
readNginxSubscribe() {
    local subscribeConfig="${nginxConfigPath}subscribe.conf"
    local -a subscribeFields
    subscribeType="https"
    if [[ -f "${subscribeConfig}" ]]; then
        mapfile -t subscribeFields < <(awk '
          /sing-box/ {
            hasSingBox = 1
          }
          /listen/ {
            for (i = 1; i <= NF; i++) {
              value = $i
              gsub(/;/, "", value)
              if (value == "ssl") {
                hasSsl = 1
              }
              if (port == "" && value ~ /^[0-9]+$/) {
                port = value
              }
              if (port == "" && value ~ /^\[::\]:[0-9]+$/) {
                sub(/^\[::\]:/, "", value)
                port = value
              }
            }
          }
          /server_name/ {
            domain = $2
            gsub(/;/, "", domain)
          }
          END {
            if (hasSingBox) {
              print port
              print domain
              print hasSsl ? "https" : ""
            }
          }
        ' "${subscribeConfig}")
        if [[ ${#subscribeFields[@]} -gt 0 ]]; then
            subscribePort=${subscribeFields[0]}
            subscribeDomain=${subscribeFields[1]}
            subscribeType=${subscribeFields[2]}
            if [[ -n "${currentHost}" && "${subscribeDomain}" != "${currentHost}" ]]; then
                subscribePort=
                subscribeType=
            fi
        fi
    fi
}

# 检测安装方式
readInstallType() {
    coreInstallType=
    configPath=
    singBoxConfigPath=

    if [[ -d "/etc/padm" ]]; then
        if [[ -f "/etc/padm/xray/xray" ]]; then
            # 检测 Xray-core
            if [[ -d "/etc/padm/xray/conf" ]] && [[ -f "/etc/padm/xray/conf/02_VLESS_TCP_inbounds.json" || -f "/etc/padm/xray/conf/02_trojan_TCP_inbounds.json" || -f "/etc/padm/xray/conf/07_VLESS_vision_reality_inbounds.json" || -f "/etc/padm/xray/conf/12_VLESS_XHTTP_inbounds.json" ]]; then
                configPath=/etc/padm/xray/conf/
                ctlPath=/etc/padm/xray/xray
                coreInstallType=1

                if [[ -f "${configPath}07_VLESS_vision_reality_inbounds.json" ]]; then
                    realityStatus=7
                fi
                if [[ -f "${configPath}12_VLESS_XHTTP_inbounds.json" ]]; then
                    realityStatus=12
                fi
                if [[ -f "/etc/padm/sing-box/sing-box" ]] && compgen -G "/etc/padm/sing-box/conf/config/*inbounds.json" >/dev/null; then
                    singBoxConfigPath=/etc/padm/sing-box/conf/config/
                fi
            fi
        elif [[ -f "/etc/padm/sing-box/sing-box" && -f "/etc/padm/sing-box/conf/config.json" ]]; then
            # 检测 sing-box
            ctlPath=/etc/padm/sing-box/sing-box
            coreInstallType=2
            configPath=/etc/padm/sing-box/conf/config/
            singBoxConfigPath=/etc/padm/sing-box/conf/config/
        fi
    fi
}

# 读取协议类型
readInstallProtocolType() {
    currentInstallProtocolType=
    frontingType=

    xrayVLESSRealityPort=
    xrayVLESSRealitySNI=

    xrayVLESSRealityXHTTPort=
    xrayVLESSRealityXHTTPSNI=

    currentRealityXHTTPPublicKey=

    currentRealityPrivateKey=
    currentRealityPublicKey=

    realityTargetHost=
    realityTargetPort=
    realityEntryHost=

    singBoxVLESSVisionPort=
    singBoxHysteria2Port=
    singBoxTrojanPort=

    frontingTypeReality=
    singBoxVLESSRealityVisionPort=
    singBoxVLESSRealityVisionSNI=
    singBoxVLESSRealityGRPCPort=
    singBoxVLESSRealityGRPCSNI=
    singBoxVLESSRealityPublicKey=
    singBoxAnyTLSPort=
    singBoxTuicPort=
    singBoxNaivePort=
    singBoxVMessWSPort=
    singBoxSocks5Port=

    while read -r row; do
        local protocolId=
        protocolId=$(xrayProtocolIdByFilename "${row}.json")
        protocolStateAdd "${protocolId}"
        if [[ "${row}" == *VLESS_TCP_inbounds* ]]; then
            frontingType=02_VLESS_TCP_inbounds
            if [[ "${coreInstallType}" == "2" ]]; then
                singBoxVLESSVisionPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if [[ "${row}" == *VLESS_WS_inbounds* ]]; then
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=03_VLESS_WS_inbounds
                singBoxVLESSWSPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if [[ "${row}" == *VLESS_XHTTP_inbounds* ]]; then
            xrayVLESSRealityXHTTPort=$(jq -r .inbounds[0].port "${row}.json")

            xrayVLESSRealityXHTTPSNI=$(jq -r .inbounds[0].streamSettings.realitySettings.serverNames[0] "${row}.json")

            currentRealityXHTTPPublicKey=$(jq -r .inbounds[0].streamSettings.realitySettings.publicKey "${row}.json")
        fi

        if [[ "${row}" == *VMess_WS_inbounds* ]]; then
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=05_VMess_WS_inbounds
                singBoxVMessWSPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if [[ "${row}" == *trojan_TCP_inbounds* ]]; then
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=04_trojan_TCP_inbounds
                singBoxTrojanPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if [[ "${row}" == *hysteria2_inbounds* ]]; then
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=06_hysteria2_inbounds
                singBoxHysteria2Port=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if [[ "${row}" == *VLESS_vision_reality_inbounds* ]]; then
            if [[ "${coreInstallType}" == "1" ]]; then
                xrayVLESSRealitySNI=$(jq -r .inbounds[1].streamSettings.realitySettings.serverNames[0] "${row}.json")
                realitySNI=${xrayVLESSRealitySNI}
                xrayVLESSRealityPort=$(jq -r .inbounds[0].port "${row}.json")

                local realityTarget
                realityTarget=$(jq -r .inbounds[1].streamSettings.realitySettings.target "${row}.json")
                realityTargetHost=${realityTarget%%:*}
                realityTargetPort=${realityTarget#*:}

                currentRealityPublicKey=$(jq -r .inbounds[1].streamSettings.realitySettings.publicKey "${row}.json")
                currentRealityPrivateKey=$(jq -r .inbounds[1].streamSettings.realitySettings.privateKey "${row}.json")

                currentRealityMldsa65Seed=$(jq -r .inbounds[1].streamSettings.realitySettings.mldsa65Seed "${row}.json")
                currentRealityMldsa65Verify=$(jq -r .inbounds[1].streamSettings.realitySettings.mldsa65Verify "${row}.json")

                frontingTypeReality=07_VLESS_vision_reality_inbounds

            elif [[ "${coreInstallType}" == "2" ]]; then
                frontingTypeReality=07_VLESS_vision_reality_inbounds
                singBoxVLESSRealityVisionPort=$(jq -r .inbounds[0].listen_port "${row}.json")
                singBoxVLESSRealityVisionSNI=$(jq -r .inbounds[0].tls.server_name "${row}.json")
                realityTargetHost=$(jq -r .inbounds[0].tls.reality.handshake.server "${row}.json")
                realityTargetPort=$(jq -r .inbounds[0].tls.reality.handshake.server_port "${row}.json")

                realitySNI=${singBoxVLESSRealityVisionSNI}
                if [[ -f "${configPath}reality_key" ]]; then
                    singBoxVLESSRealityPublicKey=$(grep "publicKey" <"${configPath}reality_key" | awk -F "[:]" '{print $2}')

                    currentRealityPrivateKey=$(jq -r .inbounds[0].tls.reality.private_key "${row}.json")
                    currentRealityPublicKey=$(grep "publicKey" <"${configPath}reality_key" | awk -F "[:]" '{print $2}')
                fi
            fi
        fi
        if [[ "${row}" == *VLESS_vision_gRPC_inbounds* ]]; then
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingTypeReality=08_VLESS_vision_gRPC_inbounds
                singBoxVLESSRealityGRPCPort=$(jq -r .inbounds[0].listen_port "${row}.json")
                singBoxVLESSRealityGRPCSNI=$(jq -r .inbounds[0].tls.server_name "${row}.json")
                realityTargetHost=$(jq -r .inbounds[0].tls.reality.handshake.server "${row}.json")
                realityTargetPort=$(jq -r .inbounds[0].tls.reality.handshake.server_port "${row}.json")
                if [[ -f "${configPath}reality_key" ]]; then
                    singBoxVLESSRealityPublicKey=$(grep "publicKey" <"${configPath}reality_key" | awk -F "[:]" '{print $2}')
                fi
            fi
        fi
        if [[ "${row}" == *tuic_inbounds* ]]; then
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=09_tuic_inbounds
                singBoxTuicPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if [[ "${row}" == *naive_inbounds* ]]; then
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=10_naive_inbounds
                singBoxNaivePort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if [[ "${row}" == *anytls_inbounds* ]]; then
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=13_anytls_inbounds
                singBoxAnyTLSPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if [[ "${row}" == *VMess_HTTPUpgrade_inbounds* ]]; then
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=11_VMess_HTTPUpgrade_inbounds
                singBoxVMessHTTPUpgradePort=$(grep 'listen' <${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf | awk '{print $2}')
            fi
        fi
        if [[ "${row}" == *socks5_inbounds* ]]; then
            protocolStateAdd 20
            singBoxSocks5Port=$(jq .inbounds[0].listen_port "${row}.json")
        fi

    done < <(find ${configPath} -name "*inbounds.json" | sort | awk -F "[.]" '{print $1}')

    if [[ "${coreInstallType}" == "1" && -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}06_hysteria2_inbounds.json" ]]; then
            protocolStateAdd 6
            singBoxHysteria2Port=$(jq .inbounds[0].listen_port "${singBoxConfigPath}06_hysteria2_inbounds.json")
        fi
        if [[ -f "${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json" ]]; then
            protocolStateAdd 8
            singBoxVLESSRealityGRPCPort=$(jq -r '.inbounds[0].listen_port' "${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json")
            singBoxVLESSRealityGRPCSNI=$(jq -r '.inbounds[0].tls.server_name // empty' "${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json")
            if [[ -z "${realityTargetHost:-}" || "${realityTargetHost}" == "null" ]]; then
                realityTargetHost=$(jq -r '.inbounds[0].tls.reality.handshake.server // empty' "${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json")
            fi
            if [[ -z "${realityTargetPort:-}" || "${realityTargetPort}" == "null" ]]; then
                realityTargetPort=$(jq -r '.inbounds[0].tls.reality.handshake.server_port // empty' "${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json")
            fi
            if [[ -z "${singBoxVLESSRealityPublicKey:-}" && -f "${singBoxConfigPath}reality_key" ]]; then
                singBoxVLESSRealityPublicKey=$(grep "publicKey" <"${singBoxConfigPath}reality_key" | awk -F "[:]" '{print $2}')
            fi
        fi
        if [[ -f "${singBoxConfigPath}09_tuic_inbounds.json" ]]; then
            protocolStateAdd 9
            singBoxTuicPort=$(jq .inbounds[0].listen_port "${singBoxConfigPath}09_tuic_inbounds.json")
        fi
        if [[ -f "${singBoxConfigPath}10_naive_inbounds.json" ]]; then
            protocolStateAdd 10
            singBoxNaivePort=$(jq -r '.inbounds[0].listen_port' "${singBoxConfigPath}10_naive_inbounds.json")
        fi
        if [[ -f "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json" ]]; then
            protocolStateAdd 11
            singBoxVMessHTTPUpgradePort=$(awk '
              /listen/ {
                for (i = 1; i <= NF; i++) {
                  value = $i
                  gsub(/;/, "", value)
                  if (value ~ /^[0-9]+$/) {
                    print value
                    exit
                  }
                }
              }
            ' "${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf" 2>/dev/null | head -n 1)
            if [[ -z "${singBoxVMessHTTPUpgradePort}" || "${singBoxVMessHTTPUpgradePort}" == "null" ]]; then
                singBoxVMessHTTPUpgradePort=$(jq -r '.inbounds[0].listen_port' "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json")
            fi
        fi
        if [[ -f "${singBoxConfigPath}13_anytls_inbounds.json" ]]; then
            protocolStateAdd 13
            singBoxAnyTLSPort=$(jq -r '.inbounds[0].listen_port' "${singBoxConfigPath}13_anytls_inbounds.json")
        fi
    fi
    if [[ "${currentInstallProtocolType:0:1}" != "," ]]; then
        currentInstallProtocolType=",${currentInstallProtocolType}"
    fi
}


# 读取Tuic配置
readSingBoxConfig() {
    tuicPort=
    hysteriaPort=
    if [[ -n "${singBoxConfigPath}" ]]; then

        if [[ -f "${singBoxConfigPath}09_tuic_inbounds.json" ]]; then
            tuicPort=$(jq -r '.inbounds[0].listen_port' "${singBoxConfigPath}09_tuic_inbounds.json")
            tuicAlgorithm=$(jq -r '.inbounds[0].congestion_control // "cubic"' "${singBoxConfigPath}09_tuic_inbounds.json")
            tuicAuthTimeout=$(jq -r '.inbounds[0].auth_timeout // "3s"' "${singBoxConfigPath}09_tuic_inbounds.json")
            tuicHeartbeat=$(jq -r '.inbounds[0].heartbeat // "10s"' "${singBoxConfigPath}09_tuic_inbounds.json")
            tuicZeroRttHandshake=$(jq -r '.inbounds[0].zero_rtt_handshake // false' "${singBoxConfigPath}09_tuic_inbounds.json")
        fi
        if [[ -f "${singBoxConfigPath}06_hysteria2_inbounds.json" ]]; then
            hysteriaPort=$(jq -r '.inbounds[0].listen_port' "${singBoxConfigPath}06_hysteria2_inbounds.json")
            hysteria2ClientUploadSpeed=$(jq -r '.inbounds[0].down_mbps' "${singBoxConfigPath}06_hysteria2_inbounds.json")
            hysteria2ClientDownloadSpeed=$(jq -r '.inbounds[0].up_mbps' "${singBoxConfigPath}06_hysteria2_inbounds.json")
        fi
    fi
}


# 显示上次安装配置摘要
showLastInstallationConfig() {
    readInstallProtocolType
    readConfigHostPathUUID
    readCustomPort
    readNginxSubscribe
    readSingBoxConfig

    echoContent title "\n┌─ 上次安装配置 ─────────────────────────────────────"
    if [[ "${coreInstallType}" == "1" ]]; then
        menuLine "内核：Xray-core"
    elif [[ "${coreInstallType}" == "2" ]]; then
        menuLine "内核：sing-box"
    fi

    if [[ -n "${currentInstallProtocolType}" ]]; then
        local protocolList=
        protocolList=$(xrayEnabledProtocolDisplayList)
        menuLine "协议：${protocolList}"
    fi

    if [[ -n "${currentHost}" ]]; then
        menuLine "域名：${currentHost}"
    fi
    if [[ -n "${currentDefaultPort}" ]]; then
        menuLine "TLS 类型协议入口端口：${currentDefaultPort}"
    elif [[ -n "${currentPort}" ]]; then
        menuLine "TLS 类型协议入口端口：${currentPort}"
    fi
    if [[ -n "${currentPath}" ]]; then
        menuLine "path：${currentPath}"
    fi
    if [[ -n "${currentUUID}" ]]; then
        menuLine "首个 UUID：${currentUUID}"
    fi
    if [[ -n "${currentCDNAddress}" && "${currentCDNAddress}" != "${currentHost}" ]]; then
        menuLine "CDN 地址：${currentCDNAddress}"
    fi
    if [[ -n "${subscribePort}" ]]; then
        menuLine "订阅：${subscribeType} 端口 ${subscribePort}"
    fi

    if [[ -n "${xrayVLESSRealityPort}" ]]; then
        menuLine "Xray Reality Vision 端口：${xrayVLESSRealityPort}"
    fi
    if [[ -n "${xrayVLESSRealityXHTTPort}" ]]; then
        menuLine "Xray Reality XHTTP 端口：${xrayVLESSRealityXHTTPort}"
    fi
    if [[ -n "${singBoxVLESSVisionPort}" ]]; then
        menuLine "sing-box VLESS Vision 端口：${singBoxVLESSVisionPort}"
    fi
    if [[ -n "${singBoxVLESSRealityVisionPort}" ]]; then
        menuLine "sing-box Reality Vision 端口：${singBoxVLESSRealityVisionPort}"
    fi
    if [[ -n "${singBoxVLESSRealityGRPCPort}" ]]; then
        menuLine "sing-box Reality gRPC 端口：${singBoxVLESSRealityGRPCPort}"
    fi
    if [[ -n "${singBoxHysteria2Port}" ]]; then
        menuLine "Hysteria2 端口：${singBoxHysteria2Port}"
    fi
    if [[ -n "${singBoxTuicPort}" ]]; then
        menuLine "Tuic 端口：${singBoxTuicPort}"
    fi
    if [[ -n "${singBoxSocks5Port}" ]]; then
        menuLine "Socks5 端口：${singBoxSocks5Port}"
    fi
    if [[ -n "${realitySNI}" ]]; then
        local entryHost="${realityEntryHost:-${currentHost}}"
        if [[ -z "${entryHost}" ]]; then
            entryHost=$(getPublicIP)
        fi
        menuLine "Reality 客户端入口地址：${entryHost}"
        menuLine "Reality 伪装目标：${realityTargetHost}:${realityTargetPort}"
        menuLine "Reality SNI：${realitySNI}"
    fi
    if [[ -n "${currentRealityPublicKey}" ]]; then
        menuLine "Reality PublicKey：${currentRealityPublicKey}"
    fi
    menuClose
}


# 清空上次安装配置
cleanLastInstallationConfig() {
    local oldPorts
    oldPorts=$(printf '%s\n' "${currentDefaultPort}" "${currentPort}" "${customPort}" "${xrayVLESSRealityPort}" "${xrayVLESSRealityXHTTPort}" "${singBoxVLESSVisionPort}" "${singBoxVLESSRealityVisionPort}" "${singBoxVLESSRealityGRPCPort}" "${singBoxHysteria2Port}" "${singBoxTuicPort}" "${singBoxSocks5Port}" "${hysteriaPort}" "${tuicPort}" | grep -E '^[0-9]+$' | sort -n | uniq)

    statusCard "安装配置" "清空上次安装配置"
    if ! runCoreServiceActionAllowFailure handleXray stop >/dev/null 2>&1; then
        errorCard "Xray 服务停止失败，已取消清空上次安装配置"
        return 1
    fi
    if ! runCoreServiceActionAllowFailure handleSingBox stop >/dev/null 2>&1; then
        errorCard "sing-box 服务停止失败，已取消清空上次安装配置"
        return 1
    fi
    if ! runCoreServiceActionAllowFailure handleNginx stop >/dev/null 2>&1; then
        errorCard "Nginx 服务停止失败，已取消清空上次安装配置"
        return 1
    fi

    if ! cleanAgentNginxConf; then
        errorCard "Nginx 配置清理失败，已取消清空上次安装配置"
        return 1
    fi
    if ! cleanDirectoryContent /etc/padm/xray/conf; then
        errorCard "Xray 配置目录清理失败，已取消清空上次安装配置"
        return 1
    fi
    if ! rm -rf /etc/padm/sing-box/conf/config.json >/dev/null 2>&1; then
        errorCard "sing-box 主配置清理失败，已取消清空上次安装配置"
        return 1
    fi
    if ! cleanDirectoryContent /etc/padm/sing-box/conf/config; then
        errorCard "sing-box 分片配置目录清理失败，已取消清空上次安装配置"
        return 1
    fi
    if ! cleanDirectoryContent /etc/padm/tls; then
        errorCard "TLS 目录清理失败，已取消清空上次安装配置"
        return 1
    fi
    if ! cleanDirectoryContent /etc/padm/subscribe; then
        errorCard "订阅发布目录清理失败，已取消清空上次安装配置"
        return 1
    fi
    if ! cleanDirectoryContent /etc/padm/subscribe_local; then
        errorCard "本地订阅目录清理失败，已取消清空上次安装配置"
        return 1
    fi
    if ! cleanDirectoryContent /etc/padm/subscribe_remote; then
        errorCard "远程订阅目录清理失败，已取消清空上次安装配置"
        return 1
    fi
    if ! rm -rf /etc/padm/warp/config >/dev/null 2>&1; then
        errorCard "WARP 配置清理失败，已取消清空上次安装配置"
        return 1
    fi
    if ! rm -f /etc/padm/cdn >/dev/null 2>&1; then
        errorCard "CDN 状态清理失败，已取消清空上次安装配置"
        return 1
    fi
    if ! rm -f /etc/padm/reality_entry_host >/dev/null 2>&1; then
        errorCard "Reality entry host 清理失败，已取消清空上次安装配置"
        return 1
    fi
    if ! rm -f "${nginxConfigPath}alone.conf" "${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf" "${nginxConfigPath}subscribe.conf" "${nginxConfigPath}checkPortOpen.conf" >/dev/null 2>&1; then
        errorCard "Nginx 残留配置清理失败，已取消清空上次安装配置"
        return 1
    fi
    if ! rm -f /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service >/dev/null 2>&1; then
        errorCard "核心服务文件清理失败，已取消清空上次安装配置"
        return 1
    fi
    if ! systemctl daemon-reload >/dev/null 2>&1; then
        errorCard "systemd 配置重载失败，已取消清空上次安装配置"
        return 1
    fi

    if [[ -n "${oldPorts}" ]]; then
        statusCard "端口释放检查" "检查上次安装端口释放状态"
        while read -r oldPort; do
            if lsof -i "tcp:${oldPort}" | grep -q LISTEN; then
                errorCard "${oldPort}端口仍被占用"
                lsof -nP -i "tcp:${oldPort}" | grep LISTEN
            else
                successCard "${oldPort}端口已释放"
            fi
        done <<<"${oldPorts}"
    fi

    if [[ -d "/root/.acme.sh" ]]; then
        echo
        autoRead clean_acme "是否清理acme证书和账号配置？[y/n]:" cleanAcmeStatus
        if [[ "${cleanAcmeStatus}" == "y" ]]; then
            rm -rf /root/.acme.sh >/dev/null 2>&1
            successCard "acme证书和账号配置已清理"
        fi
    fi

    if [[ -d "${nginxStaticPath}" && -f "${nginxStaticPath}/check" ]]; then
        rm -rf "${nginxStaticPath}" >/dev/null 2>&1
    fi

    currentPath=
    currentDefaultPort=
    currentUUID=
    currentClients=
    currentHost=
    currentPort=
    currentCDNAddress=
    customPort=
    hysteriaPort=
    tuicPort=
    tuicAlgorithm=
    tuicAuthTimeout=
    tuicHeartbeat=
    tuicZeroRttHandshake=
    realityPrivateKey=
    realityPublicKey=
    realitySNI=
    realityTargetHost=
    realityTargetPort=
    realityEntryHost=
    xrayVLESSRealityPort=
    xrayVLESSRealityXHTTPort=
    currentRealityPublicKey=
    currentRealityPrivateKey=
    currentRealityMldsa65Seed=
    currentRealityMldsa65Verify=
    currentInstallProtocolType=
    frontingType=
    frontingTypeReality=
    readInstallType
    if ! mkdirTools; then
        errorCard "初始化安装目录失败"
        return 1
    fi
    successCard "上次安装配置已清空"
}


# 读取上次安装的配置
readLastInstallationConfig() {
    if [[ -n "${configPath}" ]]; then
        showLastInstallationConfig
        autoRead reuse_last "是否使用以上上次安装配置？选择[n]会清空上次安装配置[y/n]:" lastInstallationConfigStatus
        if [[ "${lastInstallationConfigStatus}" == "y" ]]; then
            lastInstallationConfig=true
        else
            cleanLastInstallationConfig || return 1
        fi
    fi
}

# 检查文件目录以及path路径
readConfigHostPathUUID() {
    local realityEntryHostPath
    currentPath=
    currentDefaultPort=
    currentUUID=
    currentClients=
    currentHost=
    currentPort=
    currentCDNAddress=
    singBoxVMessWSPath=
    singBoxVLESSWSPath=
    singBoxVMessHTTPUpgradePath=

    if [[ "${coreInstallType}" == "1" ]]; then

        # 安装
        if [[ -n "${frontingType}" ]]; then
            currentHost=$(jq -r .inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile ${configPath}${frontingType}.json | awk -F '[t][l][s][/]' '{print $2}' | awk -F '[.][c][r][t]' '{print $1}')

            currentPort=$(jq .inbounds[0].port ${configPath}${frontingType}.json)

            local defaultPortFile=
            defaultPortFile=$(corePortDefaultFile)

            if [[ -n "${defaultPortFile}" ]]; then
                currentDefaultPort=$(basename "${defaultPortFile}" | awk -F [_] '{print $4}')
            else
                currentDefaultPort=$(jq -r .inbounds[0].port ${configPath}${frontingType}.json)
            fi
            currentUUID=$(jq -r .inbounds[0].settings.clients[0].id ${configPath}${frontingType}.json)
            currentClients=$(jq -r .inbounds[0].settings.clients ${configPath}${frontingType}.json)
        fi

        # reality
        if currentProtocolHas 7; then

            currentClients=$(jq -r .inbounds[1].settings.clients ${configPath}07_VLESS_vision_reality_inbounds.json)
            currentUUID=$(jq -r .inbounds[1].settings.clients[0].id ${configPath}07_VLESS_vision_reality_inbounds.json)
            xrayVLESSRealityVisionPort=$(jq -r .inbounds[0].port ${configPath}07_VLESS_vision_reality_inbounds.json)
            if [[ "${currentPort}" == "${xrayVLESSRealityVisionPort}" ]]; then
                xrayVLESSRealityVisionPort="${currentDefaultPort}"
            fi
        fi
        # reality xhttp
        if currentProtocolHas 12; then

            currentClients=$(jq -r .inbounds[0].settings.clients ${configPath}12_VLESS_XHTTP_inbounds.json)
            currentUUID=$(jq -r .inbounds[0].settings.clients[0].id ${configPath}12_VLESS_XHTTP_inbounds.json)
            xrayVLESSRealityXHTTPort=$(jq -r .inbounds[0].port ${configPath}12_VLESS_XHTTP_inbounds.json)
            if [[ "${currentPort}" == "${xrayVLESSRealityXHTTPort}" ]]; then
                xrayVLESSRealityXHTTPort="${currentDefaultPort}"
            fi
            currentPath=$(jq -r .inbounds[0].streamSettings.xhttpSettings.path ${configPath}12_VLESS_XHTTP_inbounds.json | awk -F "[/]" '{print $2}' | awk -F "[x][H][T][T][P]" '{print $1}')
        fi
    elif [[ "${coreInstallType}" == "2" ]]; then
        if [[ -n "${frontingType}" ]]; then
            currentHost=$(jq -r .inbounds[0].tls.server_name ${configPath}${frontingType}.json)
            if currentProtocolHas 11 && [[ "${currentHost}" == "null" ]]; then
                currentHost=$(grep 'server_name' <${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf | awk '{print $2}')
                currentHost=${currentHost//;/}
            fi
            currentUUID=$(jq -r .inbounds[0].users[0].uuid ${configPath}${frontingType}.json)
            currentClients=$(jq -r .inbounds[0].users ${configPath}${frontingType}.json)
        else
            currentUUID=$(jq -r .inbounds[0].users[0].uuid ${configPath}${frontingTypeReality}.json)
            currentClients=$(jq -r .inbounds[0].users ${configPath}${frontingTypeReality}.json)
        fi
    fi

    # 读取path
    if [[ -n "${configPath}" && -n "${frontingType}" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            local fallback
            fallback=$(jq -r -c '.inbounds[0].settings.fallbacks[]|select(.path)' ${configPath}${frontingType}.json | head -1)

            local path
            path=$(echo "${fallback}" | jq -r .path | awk -F "[/]" '{print $2}')

            if [[ $(echo "${fallback}" | jq -r .dest) == 31297 ]]; then
                currentPath=$(echo "${path}" | awk -F "[w][s]" '{print $1}')
            elif [[ $(echo "${fallback}" | jq -r .dest) == 31299 ]]; then
                currentPath=$(echo "${path}" | awk -F "[v][w][s]" '{print $1}')
            fi

            # 尝试读取alpn h2 Path
            if [[ -z "${currentPath}" ]]; then
                dest=$(jq -r -c '.inbounds[0].settings.fallbacks[]|select(.alpn)|.dest' ${configPath}${frontingType}.json | head -1)
                if [[ "${dest}" == "31302" || "${dest}" == "31304" ]]; then
                    # checkBTPanel
                    # check1Panel
                    if grep -q "trojangrpc {" <${nginxConfigPath}alone.conf; then
                        currentPath=$(grep "trojangrpc {" <${nginxConfigPath}alone.conf | awk -F "[/]" '{print $2}' | awk -F "[t][r][o][j][a][n]" '{print $1}')
                    elif grep -q "grpc {" <${nginxConfigPath}alone.conf; then
                        currentPath=$(grep "grpc {" <${nginxConfigPath}alone.conf | head -1 | awk -F "[/]" '{print $2}' | awk -F "[g][r][p][c]" '{print $1}')
                    fi
                fi
            fi
            if [[ -z "${currentPath}" && -f "${configPath}12_VLESS_XHTTP_inbounds.json" ]]; then
                currentPath=$(jq -r .inbounds[0].streamSettings.xhttpSettings.path "${configPath}12_VLESS_XHTTP_inbounds.json" | awk -F "[x][H][T][T][P]" '{print $1}' | awk -F "[/]" '{print $2}')
            fi
        elif [[ "${coreInstallType}" == "2" && -f "${singBoxConfigPath}05_VMess_WS_inbounds.json" ]]; then
            singBoxVMessWSPath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}05_VMess_WS_inbounds.json")
            currentPath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}05_VMess_WS_inbounds.json" | awk -F "[/]" '{print $2}')
        fi
        if [[ "${coreInstallType}" == "2" && -f "${singBoxConfigPath}03_VLESS_WS_inbounds.json" ]]; then
            singBoxVLESSWSPath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}03_VLESS_WS_inbounds.json")
            currentPath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}03_VLESS_WS_inbounds.json" | awk -F "[/]" '{print $2}')
            currentPath=${currentPath::-2}
        fi
        if [[ -n "${singBoxConfigPath}" && -f "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json" ]]; then
            singBoxVMessHTTPUpgradePath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json")
            if [[ -z "${currentPath}" || "${coreInstallType}" == "2" ]]; then
                currentPath=$(jq -r .inbounds[0].transport.path "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json" | awk -F "[/]" '{print $2}')
            fi
        fi
    fi
    if declare -F realityEntryHostFile >/dev/null 2>&1; then
        realityEntryHostPath=$(realityEntryHostFile)
    else
        realityEntryHostPath="${PADM_REALITY_ENTRY_HOST_FILE:-/etc/padm/reality_entry_host}"
    fi
    if [[ -f "${realityEntryHostPath}" ]]; then
        realityEntryHost=$(head -1 "${realityEntryHostPath}")
    fi
    if [[ -f "/etc/padm/cdn" ]] && [[ -n "$(head -1 /etc/padm/cdn)" ]]; then
        currentCDNAddress=$(head -1 /etc/padm/cdn)
    else
        currentCDNAddress="${currentHost}"
    fi
}


# 状态展示
showInstallStatus() {
    if [[ -n "${coreInstallType}" ]]; then
        if [[ "${coreInstallType}" == 1 ]]; then
            if [[ -n $(pgrep -f "xray/xray") ]]; then
                echoContent yellow "\n核心: Xray-core[运行中]"
            else
                echoContent yellow "\n核心: Xray-core[未运行]"
            fi

        elif [[ "${coreInstallType}" == 2 ]]; then
            if [[ -n $(pgrep -f "sing-box/sing-box") ]]; then
                echoContent yellow "\n核心: sing-box[运行中]"
            else
                echoContent yellow "\n核心: sing-box[未运行]"
            fi
        fi
        # 读取协议类型
        readInstallProtocolType

        if [[ -n ${currentInstallProtocolType} ]]; then
            echoContent yellow "已安装协议: \c"
        fi
        if currentProtocolHas 0; then
            echoContent yellow "VLESS+TCP[TLS_Vision] \c"
        fi

        if currentProtocolHas 1; then
            echoContent yellow "VLESS+WS[TLS] \c"
        fi

        if currentProtocolHas 2; then
            echoContent yellow "Trojan+gRPC[TLS] \c"
        fi

        if currentProtocolHas 3; then
            echoContent yellow "VMess+WS[TLS] \c"
        fi

        if currentProtocolHas 4; then
            echoContent yellow "Trojan+TCP[TLS] \c"
        fi

        if currentProtocolHas 5; then
            echoContent yellow "VLESS+gRPC[TLS] \c"
        fi
        if currentProtocolHas 6; then
            echoContent yellow "Hysteria2 \c"
        fi
        if currentProtocolHas 7; then
            echoContent yellow "VLESS+Reality+Vision \c"
        fi
        if currentProtocolHas 8; then
            echoContent yellow "VLESS+Reality+gRPC \c"
        fi
        if currentProtocolHas 9; then
            echoContent yellow "Tuic \c"
        fi
        if currentProtocolHas 10; then
            echoContent yellow "Naive \c"
        fi
        if currentProtocolHas 11; then
            echoContent yellow "VMess+TLS+HTTPUpgrade \c"
        fi
        if currentProtocolHas 12; then
            echoContent yellow "VLESS+Reality+XHTTP \c"
        fi
        if currentProtocolHas 13; then
            echoContent yellow "AnyTLS \c"
        fi
        if [[ -n ${currentInstallProtocolType} ]]; then
            echo
        fi
    fi
}
