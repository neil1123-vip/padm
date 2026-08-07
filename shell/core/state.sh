#!/usr/bin/env bash

acmeHomeDir() {
    local homeDir="${HOME:-/root}"
    printf '%s\n' "${homeDir%/}/.acme.sh"
}

acmeSafeHomeDir() {
    local acmeDir
    local resolvedPath=
    acmeDir=$(acmeHomeDir)
    [[ -n "${acmeDir}" ]] || return 1
    if [[ "${acmeDir}" == /* ]]; then
        padmIsSafeAbsolutePath "${acmeDir%/}" || return 1
        printf '%s\n' "${acmeDir%/}"
        return 0
    fi
    if [[ "${acmeDir}" == "." || "${acmeDir}" == ".." ||
        "${acmeDir}" == */./* || "${acmeDir}" == */. ||
        "${acmeDir}" == */../* || "${acmeDir}" == */.. ]]; then
        return 1
    fi
    resolvedPath=$(padmResolveCleanupPath "${acmeDir}" 2>/dev/null || true)
    [[ -n "${resolvedPath}" ]] || return 1
    padmIsSafeAbsolutePath "${resolvedPath%/}" || return 1
    printf '%s\n' "${resolvedPath%/}"
}

# 读取 TLS 证书详情
readAcmeTLS() {
    local readAcmeDomain=
    installedDNSAPIStatus=
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
    local subscribeConfig
    local normalizedConfig
    local tlsDir
    local listenEntry listenPort listenSsl
    local -a listenEntries serverNames certificateFiles keyFiles
    subscribePort=
    subscribeDomain=
    subscribeType=
    subscribeCertificateFile=
    subscribeKeyFile=
    subscribeConfigState=missing
    subscribeConfig=$(nginxConfigFilePath subscribe.conf) || {
        subscribeConfigState=invalid
        return 1
    }
    if [[ ! -e "${subscribeConfig}" && ! -L "${subscribeConfig}" ]]; then
        return 0
    fi
    if [[ ! -f "${subscribeConfig}" ]]; then
        subscribeConfigState=invalid
        return 1
    fi
    normalizedConfig=$(sed 's/;/;\n/g' "${subscribeConfig}") || {
        subscribeConfigState=invalid
        return 1
    }
    [[ "$(grep -Ec '^[[:space:]]*server[[:space:]]*\{' <<<"${normalizedConfig}")" == "1" ]] || {
        subscribeConfigState=invalid
        return 1
    }
    mapfile -t listenEntries < <(awk '
      $1 == "listen" {
        value = $2
        gsub(/;/, "", value)
        sub(/^.*:/, "", value)
        ssl = 0
        for (i = 3; i <= NF; i++) {
          token = $i
          gsub(/;/, "", token)
          if (token == "ssl") ssl = 1
        }
        print value "|" ssl
      }
    ' <<<"${normalizedConfig}")
    mapfile -t serverNames < <(awk '$1 == "server_name" { gsub(/;/, "", $2); if (NF == 2) print $2; else print "" }' <<<"${normalizedConfig}")
    mapfile -t certificateFiles < <(awk '$1 == "ssl_certificate" { gsub(/;/, "", $2); if (NF == 2) print $2; else print "" }' <<<"${normalizedConfig}")
    mapfile -t keyFiles < <(awk '$1 == "ssl_certificate_key" { gsub(/;/, "", $2); if (NF == 2) print $2; else print "" }' <<<"${normalizedConfig}")
    if [[ ${#listenEntries[@]} -eq 0 || ${#serverNames[@]} -ne 1 ||
        ${#certificateFiles[@]} -ne 1 || ${#keyFiles[@]} -ne 1 ]] ||
        ! grep -Fq 'sing-box_profiles' <<<"${normalizedConfig}"; then
        subscribeConfigState=invalid
        return 1
    fi
    subscribeDomain=${serverNames[0]}
    subscribeCertificateFile=${certificateFiles[0]}
    subscribeKeyFile=${keyFiles[0]}
    tlsDomainNameIsSafe "${subscribeDomain}" || {
        subscribeConfigState=invalid
        return 1
    }
    for listenEntry in "${listenEntries[@]}"; do
        IFS='|' read -r listenPort listenSsl <<<"${listenEntry}"
        if ! validPortNumber "${listenPort}" || [[ "${listenSsl}" != "1" ]]; then
            subscribeConfigState=invalid
            return 1
        fi
        if [[ -n "${subscribePort}" && "${subscribePort}" != "${listenPort}" ]]; then
            subscribeConfigState=invalid
            return 1
        fi
        subscribePort=${listenPort}
    done
    tlsDir=$(tlsManagedDir) || {
        subscribeConfigState=invalid
        return 1
    }
    if [[ "${subscribeCertificateFile}" != "${tlsDir}/${subscribeDomain}.crt" ||
        "${subscribeKeyFile}" != "${tlsDir}/${subscribeDomain}.key" ]]; then
        subscribeConfigState=invalid
        return 1
    fi
    subscribeType=https
    subscribeConfigState=valid
}

# 检测安装方式
readInstallType() {
    coreInstallType=
    configPath=
    singBoxConfigPath=
    local configFile
    local xrayBinary="${PADM_XRAY_BINARY:-/etc/padm/xray/xray}"
    local xrayConfigDir="${PADM_XRAY_CONF_DIR:-/etc/padm/xray/conf}"
    local singBoxBinary="${PADM_SINGBOX_BINARY:-/etc/padm/sing-box/sing-box}"
    local singBoxConfigDir="${PADM_SINGBOX_CONFIG_DIR:-/etc/padm/sing-box/conf/config}"
    local singBoxMergedFile="$(dirname -- "${singBoxConfigDir%/}")/config.json"

    if [[ -f "${xrayBinary}" && -d "${xrayConfigDir}" ]]; then
        # 检测 Xray-core
        for configFile in $(protocolCapabilityIdsByProjectCore xray | tr ',' ' '); do
            configFile=$(protocolCapabilityMeta "${configFile}" config_file 2>/dev/null || true)
            [[ -n "${configFile}" && -f "${xrayConfigDir%/}/${configFile}" ]] || continue
            coreInstallType=1
            break
        done
        if [[ "${coreInstallType}" == "1" ]]; then
            configPath=${xrayConfigDir%/}/
            ctlPath=${xrayBinary}

            if [[ -f "${configPath}07_VLESS_vision_reality_inbounds.json" ]]; then
                realityStatus=7
            fi
            if [[ -f "${configPath}12_VLESS_XHTTP_inbounds.json" ]]; then
                realityStatus=12
            fi
            if [[ -f "${singBoxBinary}" ]] && compgen -G "${singBoxConfigDir%/}/*inbounds.json" >/dev/null; then
                singBoxConfigPath=${singBoxConfigDir%/}/
            fi
        fi
    fi
    if [[ "${coreInstallType}" != "1" ]] &&
        [[ -f "${singBoxBinary}" ]] &&
        { [[ -f "${singBoxMergedFile}" ]] || compgen -G "${singBoxConfigDir%/}/*.json" >/dev/null; }; then
        # 检测 sing-box；分片配置仍然有效，即使合并文件暂时不存在。
        ctlPath=${singBoxBinary}
        coreInstallType=2
        configPath=${singBoxConfigDir%/}/
        singBoxConfigPath=${singBoxConfigDir%/}/
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
    xrayVLESSRealityGRPCPort=
    xrayVLESSRealityGRPCSNI=

    currentRealityXHTTPPublicKey=
    xrayVLESSRealityGRPCPublicKey=
    xrayVLESSRealityGRPCMldsa65Verify=

    currentRealityPrivateKey=
    currentRealityPublicKey=
    currentRealityMldsa65Seed=
    currentRealityMldsa65Verify=

    realityTargetHost=
    realityTargetPort=
    realityEntryHost=

    singBoxVLESSVisionPort=
    singBoxHysteria2Port=
    singBoxTrojanPort=
    singBoxShadowsocksPort=

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

    local xrayBinary="${PADM_XRAY_BINARY:-/etc/padm/xray/xray}"
    local derivePublicKeyFromPrivateKey
    derivePublicKeyFromPrivateKey() {
        local privateKey=$1
        [[ -n "${privateKey}" && -x "${xrayBinary}" ]] || return 1
        "${xrayBinary}" x25519 -i "${privateKey}" 2>/dev/null | awk '/Password \(PublicKey\):/ { print $3; exit }'
    }

    while read -r row; do
        row=${row%.json}
        local protocolId=
        protocolId=$(protocolCapabilityIdByConfigFile "${row##*/}.json" 2>/dev/null || true)
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
            realitySNI=${xrayVLESSRealityXHTTPSNI}

            local realityXHTTPTarget
            realityXHTTPTarget=$(jq -r '.inbounds[0].streamSettings.realitySettings.target // empty' "${row}.json")
            realityTargetHost=${realityXHTTPTarget%%:*}
            realityTargetPort=${realityXHTTPTarget#*:}

            currentRealityXHTTPPublicKey=$(jq -r .inbounds[0].streamSettings.realitySettings.publicKey "${row}.json")
            currentRealityPublicKey=${currentRealityXHTTPPublicKey}
            currentRealityPrivateKey=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey // empty' "${row}.json")
        fi

        if [[ "${row}" == *VMess_WS_inbounds* ]]; then
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=05_VMess_WS_inbounds
                singBoxVMessWSPort=$(jq .inbounds[0].listen_port "${row}.json")
            fi
        fi
        if [[ "${row}" == *28_trojan_TCP_direct_inbounds* ]]; then
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=28_trojan_TCP_direct_inbounds
                singBoxTrojanPort=$(jq .inbounds[0].listen_port "${row}.json")
            elif [[ "${coreInstallType}" == "1" ]]; then
                frontingType=28_trojan_TCP_direct_inbounds
                currentPort=$(jq .inbounds[0].port "${row}.json")
            fi
        fi
        if [[ "${row}" == *04_trojan_TCP_inbounds* ]]; then
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=04_trojan_TCP_inbounds
                singBoxTrojanPort=$(jq .inbounds[0].listen_port "${row}.json")
            elif [[ "${coreInstallType}" == "1" ]]; then
                [[ -n "${frontingType}" ]] || frontingType=04_trojan_TCP_inbounds
                currentPort=$(jq .inbounds[0].port "${row}.json")
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

                currentRealityMldsa65Seed=$(jq -r '.inbounds[1].streamSettings.realitySettings.mldsa65Seed // empty' "${row}.json")
                currentRealityMldsa65Verify=$(jq -r '.inbounds[1].streamSettings.realitySettings.mldsa65Verify // empty' "${row}.json")

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
            if [[ "${coreInstallType}" == "1" ]]; then
                frontingTypeReality=08_VLESS_vision_gRPC_inbounds
                xrayVLESSRealityGRPCPort=$(jq -r .inbounds[0].port "${row}.json")
                xrayVLESSRealityGRPCSNI=$(jq -r .inbounds[0].streamSettings.realitySettings.serverNames[0] "${row}.json")
                realitySNI=${xrayVLESSRealityGRPCSNI}
                local realityGrpcTarget
                realityGrpcTarget=$(jq -r .inbounds[0].streamSettings.realitySettings.target "${row}.json")
                realityTargetHost=${realityGrpcTarget%%:*}
                realityTargetPort=${realityGrpcTarget#*:}
                xrayVLESSRealityGRPCPublicKey=$(jq -r .inbounds[0].streamSettings.realitySettings.publicKey "${row}.json")
                xrayVLESSRealityGRPCMldsa65Verify=$(jq -r '.inbounds[0].streamSettings.realitySettings.mldsa65Verify // empty' "${row}.json")
                currentRealityPublicKey=${xrayVLESSRealityGRPCPublicKey}
                currentRealityPrivateKey=$(jq -r .inbounds[0].streamSettings.realitySettings.privateKey "${row}.json")
            elif [[ "${coreInstallType}" == "2" ]]; then
                frontingTypeReality=08_VLESS_vision_gRPC_inbounds
                singBoxVLESSRealityGRPCPort=$(jq -r .inbounds[0].listen_port "${row}.json")
                singBoxVLESSRealityGRPCSNI=$(jq -r .inbounds[0].tls.server_name "${row}.json")
                realityTargetHost=$(jq -r .inbounds[0].tls.reality.handshake.server "${row}.json")
                realityTargetPort=$(jq -r .inbounds[0].tls.reality.handshake.server_port "${row}.json")
                currentRealityPrivateKey=$(jq -r '.inbounds[0].tls.reality.private_key // empty' "${row}.json")
                if [[ -f "${configPath}reality_key" ]]; then
                    singBoxVLESSRealityPublicKey=$(grep "publicKey" <"${configPath}reality_key" | awk -F "[:]" '{print $2}')
                fi
                if [[ -z "${singBoxVLESSRealityPublicKey:-}" && -n "${currentRealityPrivateKey:-}" ]]; then
                    singBoxVLESSRealityPublicKey=$(derivePublicKeyFromPrivateKey "${currentRealityPrivateKey}" || true)
                fi
                if [[ -n "${singBoxVLESSRealityPublicKey:-}" ]]; then
                    currentRealityPublicKey=${singBoxVLESSRealityPublicKey}
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
        if [[ "${row}" == *shadowsocks_inbounds* ]]; then
            if [[ "${coreInstallType}" == "2" ]]; then
                frontingType=30_shadowsocks_inbounds
                singBoxShadowsocksPort=$(jq .inbounds[0].listen_port "${row}.json")
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

    done < <(
        if [[ -n "${configPath}" && -d "${configPath}" ]]; then
            find "${configPath}" -name "*inbounds.json" -print | sort
        fi
    )

    if [[ "${coreInstallType}" == "1" && -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}06_hysteria2_inbounds.json" ]]; then
            protocolStateAdd 3
            singBoxHysteria2Port=$(jq .inbounds[0].listen_port "${singBoxConfigPath}06_hysteria2_inbounds.json")
        fi
        if [[ -f "${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json" ]]; then
            protocolStateAdd 26
            singBoxVLESSRealityGRPCPort=$(jq -r '.inbounds[0].listen_port' "${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json")
            singBoxVLESSRealityGRPCSNI=$(jq -r '.inbounds[0].tls.server_name // empty' "${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json")
            currentRealityPrivateKey=$(jq -r '.inbounds[0].tls.reality.private_key // empty' "${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json")
            if [[ -z "${realityTargetHost:-}" || "${realityTargetHost}" == "null" ]]; then
                realityTargetHost=$(jq -r '.inbounds[0].tls.reality.handshake.server // empty' "${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json")
            fi
            if [[ -z "${realityTargetPort:-}" || "${realityTargetPort}" == "null" ]]; then
                realityTargetPort=$(jq -r '.inbounds[0].tls.reality.handshake.server_port // empty' "${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json")
            fi
            if [[ -z "${singBoxVLESSRealityPublicKey:-}" && -f "${singBoxConfigPath}reality_key" ]]; then
                singBoxVLESSRealityPublicKey=$(grep "publicKey" <"${singBoxConfigPath}reality_key" | awk -F "[:]" '{print $2}')
            fi
            if [[ -z "${singBoxVLESSRealityPublicKey:-}" && -n "${currentRealityPrivateKey:-}" ]]; then
                singBoxVLESSRealityPublicKey=$(derivePublicKeyFromPrivateKey "${currentRealityPrivateKey}" || true)
            fi
            if [[ -z "${currentRealityPublicKey:-}" && -n "${singBoxVLESSRealityPublicKey:-}" ]]; then
                currentRealityPublicKey=${singBoxVLESSRealityPublicKey}
            fi
        fi
        if [[ -f "${singBoxConfigPath}09_tuic_inbounds.json" ]]; then
            protocolStateAdd 31
            singBoxTuicPort=$(jq .inbounds[0].listen_port "${singBoxConfigPath}09_tuic_inbounds.json")
        fi
        if [[ -f "${singBoxConfigPath}10_naive_inbounds.json" ]]; then
            protocolStateAdd 5
            singBoxNaivePort=$(jq -r '.inbounds[0].listen_port' "${singBoxConfigPath}10_naive_inbounds.json")
        fi
        if [[ -f "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json" ]]; then
            protocolStateAdd 23
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
            protocolStateAdd 4
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
            hysteria2ClientUploadSpeed=$(jq -r '.inbounds[0].up_mbps' "${singBoxConfigPath}06_hysteria2_inbounds.json")
            hysteria2ClientDownloadSpeed=$(jq -r '.inbounds[0].down_mbps' "${singBoxConfigPath}06_hysteria2_inbounds.json")
            hysteria2Masquerade=$(jq -r '.inbounds[0].masquerade // empty | if type == "string" then . else empty end' "${singBoxConfigPath}06_hysteria2_inbounds.json")
        fi
    fi
}


# 显示上次安装配置摘要
showLastInstallationConfig() {
    readInstallProtocolType
    readConfigHostPathUUID || return 1
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
        while IFS='|' read -r protocolId _ _; do
            if [[ " ${currentInstallProtocolType} " == *",${protocolId},"* ]]; then
                protocolList="${protocolList} $(xrayProtocolName "${protocolId}")"
            fi
        done < <(protocolCapabilityRegistry)
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

    local visionInternalPort= visionPublicPort= xhttpInternalPort= xhttpPublicPort=
    if declare -F realityStreamSplitEnabled >/dev/null 2>&1 && realityStreamSplitEnabled; then
        visionInternalPort=$(realityStreamInternalPortForProtocol vision)
        visionPublicPort=$(realityStreamPublicPortForProtocol vision)
        xhttpInternalPort=$(realityStreamInternalPortForProtocol xhttp)
        xhttpPublicPort=$(realityStreamPublicPortForProtocol xhttp)
    fi

    if [[ -n "${xrayVLESSRealityPort}" ]]; then
        if [[ -n "${visionInternalPort}" && "${xrayVLESSRealityPort}" == "${visionInternalPort}" ]]; then
            menuLine "Xray Reality Vision 客户端公网端口：${visionPublicPort:-443}；共存内部端口：${xrayVLESSRealityPort}"
        else
            menuLine "Xray Reality Vision 客户端连接端口：${xrayVLESSRealityPort}"
        fi
    fi
    if [[ -n "${xrayVLESSRealityXHTTPort}" ]]; then
        if [[ -n "${xhttpInternalPort}" && "${xrayVLESSRealityXHTTPort}" == "${xhttpInternalPort}" ]]; then
            menuLine "Xray Reality XHTTP 客户端公网端口：${xhttpPublicPort:-443}；共存内部端口：${xrayVLESSRealityXHTTPort}"
        else
            menuLine "Xray Reality XHTTP 客户端连接端口：${xrayVLESSRealityXHTTPort}"
        fi
    fi
    if [[ -n "${singBoxVLESSVisionPort}" ]]; then
        menuLine "sing-box VLESS Vision 端口：${singBoxVLESSVisionPort}"
    fi
    if [[ -n "${singBoxVLESSRealityVisionPort}" ]]; then
        if [[ -n "${visionInternalPort}" && "${singBoxVLESSRealityVisionPort}" == "${visionInternalPort}" ]]; then
            menuLine "sing-box Reality Vision 客户端公网端口：${visionPublicPort:-443}；共存内部端口：${singBoxVLESSRealityVisionPort}"
        else
            menuLine "sing-box Reality Vision 客户端连接端口：${singBoxVLESSRealityVisionPort}"
        fi
    fi
    if [[ -n "${singBoxVLESSRealityGRPCPort}" ]]; then
        menuLine "sing-box Reality gRPC 客户端连接端口：${singBoxVLESSRealityGRPCPort}"
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
    local nginxWasRunning=false
    local cleanStatus=0
    nginxRunning && nginxWasRunning=true
    cleanLastInstallationConfigApply "$@" || cleanStatus=$?
    if [[ "${nginxWasRunning}" == "true" ]] && ! nginxRunning; then
        local restoreErrorLog
        restoreErrorLog=$(padmTmpFilePath padm-nginx-clean-restore.log)
        if ! PADM_NGINX_ERROR_LOG="${restoreErrorLog}" runCoreServiceActionAllowFailure handleNginx start restore; then
            rm -f -- "${restoreErrorLog}" >/dev/null 2>&1 || true
            errorCard "清空配置后 Nginx 原运行状态恢复失败，请手动检查 Nginx 服务"
            return 1
        fi
        rm -f -- "${restoreErrorLog}" >/dev/null 2>&1 || true
    fi
    return "${cleanStatus}"
}

cleanLastInstallationConfigApply() {
    local oldPorts
    local xrayOpenRcServiceFile=${PADM_XRAY_OPENRC_SERVICE_FILE:-/etc/init.d/xray}
    local singBoxOpenRcServiceFile=${PADM_SINGBOX_OPENRC_SERVICE_FILE:-/etc/init.d/sing-box}
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
    if ! removeManagedFileIfPresent /etc/padm/sing-box/conf/config.json; then
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
    if ! removeManagedFileIfPresent /etc/padm/warp/config; then
        errorCard "WARP 配置清理失败，已取消清空上次安装配置"
        return 1
    fi
    if ! removeManagedFileIfPresent /etc/padm/cdn; then
        errorCard "CDN 状态清理失败，已取消清空上次安装配置"
        return 1
    fi
    if ! removeManagedFileIfPresent /etc/padm/reality_entry_host; then
        errorCard "Reality entry host 清理失败，已取消清空上次安装配置"
        return 1
    fi
    if [[ "${release:-}" == "alpine" ]]; then
        if [[ "${coreInstallType:-}" == "1" || -e "${xrayOpenRcServiceFile}" || -L "${xrayOpenRcServiceFile}" ]] && ! rc-update del xray default >/dev/null 2>&1; then
            errorCard "Xray OpenRC 开机自启清理失败，已取消清空上次安装配置"
            return 1
        fi
        if [[ "${coreInstallType:-}" == "2" || -e "${singBoxOpenRcServiceFile}" || -L "${singBoxOpenRcServiceFile}" ]] && ! rc-update del sing-box default >/dev/null 2>&1; then
            errorCard "sing-box OpenRC 开机自启清理失败，已取消清空上次安装配置"
            return 1
        fi
        if ! removeManagedFilesIfPresent "${xrayOpenRcServiceFile}" "${singBoxOpenRcServiceFile}"; then
            errorCard "核心 OpenRC 服务文件清理失败，已取消清空上次安装配置"
            return 1
        fi
    else
        if ! removeManagedFilesIfPresent /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service; then
            errorCard "核心服务文件清理失败，已取消清空上次安装配置"
            return 1
        fi
        if ! systemctl daemon-reload >/dev/null 2>&1; then
            errorCard "systemd 配置重载失败，已取消清空上次安装配置"
            return 1
        fi
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

    local acmeDir
    acmeDir=$(acmeHomeDir)
    if [[ -d "${acmeDir}" ]]; then
        echo
        autoRead clean_acme "是否清理acme证书和账号配置？[y/n]:" cleanAcmeStatus
        if [[ "${cleanAcmeStatus}" == "y" ]]; then
            if ! acmeDir=$(acmeSafeHomeDir); then
                errorCard "acme证书和账号配置目录异常"
                return 1
            fi
            if rm -rf -- "${acmeDir}" >/dev/null 2>&1; then
                successCard "acme证书和账号配置已清理"
            else
                errorCard "acme证书和账号配置清理失败"
                return 1
            fi
        fi
    fi

    if [[ -d "${nginxStaticPath}" && -f "${nginxStaticPath}/check" ]]; then
        local staticPath
        if ! staticPath=$(nginxStaticSafePath); then
            errorCard "静态站点目录异常，已取消清空上次安装配置"
            return 1
        fi
        if ! rm -rf -- "${staticPath}" >/dev/null 2>&1; then
            errorCard "静态站点清理失败，已取消清空上次安装配置"
            return 1
        fi
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
    xrayVLESSRealityGRPCPort=
    xrayVLESSRealityGRPCSNI=
    xrayVLESSRealityGRPCPublicKey=
    xrayVLESSRealityGRPCMldsa65Verify=
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
        showLastInstallationConfig || return 1
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
    local configDir configFile
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

    for configDir in "${configPath:-}" "${singBoxConfigPath:-}"; do
        [[ -n "${configDir}" && -d "${configDir}" ]] || continue
        for configFile in "${configDir%/}"/*.json; do
            [[ -f "${configFile}" ]] || continue
            jq empty "${configFile}" >/dev/null 2>&1 || return 1
        done
    done

    if [[ "${coreInstallType}" == "1" ]]; then

        # 安装
        if [[ -n "${frontingType}" ]]; then
            currentHost=$(jq -r .inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile ${configPath}${frontingType}.json | awk -F '[t][l][s][/]' '{print $2}' | awk -F '[.][c][r][t]' '{print $1}')
            if [[ -z "${currentHost}" || "${currentHost}" == "null" ]]; then
                currentHost=$(resolveInstalledTLSDomain 2>/dev/null || true)
            fi

            currentPort=$(jq .inbounds[0].port ${configPath}${frontingType}.json)

            local defaultPortFile=
            defaultPortFile=$(corePortDefaultFile)

            if [[ -n "${defaultPortFile}" ]]; then
                currentDefaultPort=$(basename "${defaultPortFile}" | awk -F [_] '{print $4}')
            else
                currentDefaultPort=$(jq -r .inbounds[0].port ${configPath}${frontingType}.json)
            fi
            if [[ -z "${currentDefaultPort}" || "${currentDefaultPort}" == "null" ]]; then
                currentDefaultPort=${currentPort}
            fi
            currentUUID=$(jq -r .inbounds[0].settings.clients[0].id ${configPath}${frontingType}.json)
            currentClients=$(jq -r .inbounds[0].settings.clients ${configPath}${frontingType}.json)
        fi

        # reality
        if currentProtocolHas 1; then

            currentClients=$(jq -r .inbounds[1].settings.clients ${configPath}07_VLESS_vision_reality_inbounds.json)
            currentUUID=$(jq -r .inbounds[1].settings.clients[0].id ${configPath}07_VLESS_vision_reality_inbounds.json)
            xrayVLESSRealityVisionPort=$(jq -r .inbounds[0].port ${configPath}07_VLESS_vision_reality_inbounds.json)
            if [[ "${currentPort}" == "${xrayVLESSRealityVisionPort}" ]]; then
                xrayVLESSRealityVisionPort="${currentDefaultPort}"
            fi
        fi
        # reality xhttp
        if currentProtocolHas 2; then

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
            if currentProtocolHas 23 && [[ "${currentHost}" == "null" ]]; then
                currentHost=$(grep 'server_name' <${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf | awk '{print $2}')
                currentHost=${currentHost//;/}
            fi
            if [[ -z "${currentHost}" || "${currentHost}" == "null" ]]; then
                if [[ -n "${AUTO_ENTRY_HOST:-}" ]]; then
                    currentHost=${AUTO_ENTRY_HOST}
                elif [[ -n "${domain:-}" ]]; then
                    currentHost=${domain}
                else
                    currentHost=$(getPublicIP)
                fi
            fi
            currentUUID=$(jq -r .inbounds[0].users[0].uuid ${configPath}${frontingType}.json)
            currentClients=$(jq -r .inbounds[0].users ${configPath}${frontingType}.json)
        else
            currentUUID=$(jq -r .inbounds[0].users[0].uuid ${configPath}${frontingTypeReality}.json)
            currentClients=$(jq -r .inbounds[0].users ${configPath}${frontingTypeReality}.json)
        fi
    fi

    [[ "${currentUUID}" != "null" ]] || currentUUID=

    # 读取path
    if [[ -n "${configPath}" && -n "${frontingType}" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            local fallback
            fallback=$(jq -r -c '.inbounds[0].settings.fallbacks[]?|select(.path)' ${configPath}${frontingType}.json | head -1)

            local path
            path=$(echo "${fallback}" | jq -r .path | awk -F "[/]" '{print $2}')

            if [[ $(echo "${fallback}" | jq -r .dest) == 31297 ]]; then
                currentPath=$(echo "${path}" | awk -F "[w][s]" '{print $1}')
            elif [[ $(echo "${fallback}" | jq -r .dest) == 31299 ]]; then
                currentPath=$(echo "${path}" | awk -F "[v][w][s]" '{print $1}')
            elif [[ $(echo "${fallback}" | jq -r .dest) == 31306 ]]; then
                currentPath=${path}
            fi

            # 尝试读取alpn h2 Path
            if [[ -z "${currentPath}" ]]; then
                dest=$(jq -r -c '.inbounds[0].settings.fallbacks[]?|select(.alpn)|.dest' ${configPath}${frontingType}.json | head -1)
                if [[ "${dest}" == "31302" || "${dest}" == "31304" ]]; then
                    # checkBTPanel
                    # check1Panel
                    if [[ -f "${nginxConfigPath}alone.conf" ]]; then
                        if grep -q "trojangrpc {" <${nginxConfigPath}alone.conf; then
                            currentPath=$(grep "trojangrpc {" <${nginxConfigPath}alone.conf | awk -F "[/]" '{print $2}' | awk -F "[t][r][o][j][a][n]" '{print $1}')
                        elif grep -q "grpc {" <${nginxConfigPath}alone.conf; then
                            currentPath=$(grep "grpc {" <${nginxConfigPath}alone.conf | head -1 | awk -F "[/]" '{print $2}' | awk -F "[g][r][p][c]" '{print $1}')
                        fi
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
    if [[ -n "${currentClients}" ]]; then
        jq -e 'type == "array"' <<<"${currentClients}" >/dev/null 2>&1 || return 1
    fi
}


# 状态展示
protocolCapabilityStatusLabel() {
    local protocolId=$1
    local name lifecycle nginxMode risk
    name=$(protocolCapabilityMeta "${protocolId}" name 2>/dev/null) || return 1
    lifecycle=$(protocolCapabilityMeta "${protocolId}" lifecycle 2>/dev/null) || return 1
    nginxMode=$(protocolCapabilityMeta "${protocolId}" nginx_mode 2>/dev/null) || return 1
    risk=$(protocolCapabilityMeta "${protocolId}" risk_note 2>/dev/null || true)
    printf '%s [%s, nginx:%s]' "${name}" "${lifecycle}" "${nginxMode}"
    [[ -n "${risk}" ]] && printf ' 风险:%s' "${risk}"
}

showInstallStatus() {
    if [[ -n "${coreInstallType}" ]]; then
        local protocolId statusLabel
        if [[ "${coreInstallType}" == 1 ]]; then
            if xrayRunning; then
                echoContent yellow "\n核心: Xray-core[运行中]"
            else
                echoContent yellow "\n核心: Xray-core[未运行]"
            fi

        elif [[ "${coreInstallType}" == 2 ]]; then
            if singBoxRunning; then
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
        while IFS='|' read -r protocolId _; do
            currentProtocolHas "${protocolId}" || continue
            statusLabel=$(protocolCapabilityStatusLabel "${protocolId}" 2>/dev/null || true)
            [[ -n "${statusLabel}" ]] || continue
            echoContent yellow "${statusLabel} \c"
        done < <(protocolCapabilityRegistry | awk -F'|' '$3 == "node" { print }')
        if [[ -n ${currentInstallProtocolType} ]]; then
            echo
        fi
    fi
}
