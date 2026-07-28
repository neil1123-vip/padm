#!/usr/bin/env bash

# core template managed config helpers
xrayTemplateConfigDir() {
    printf '%s\n' "/etc/padm/xray/conf"
}

xrayTemplateConfigFile() {
    padmManagedFilePath "$(xrayTemplateConfigDir)" "$1"
}

removeXrayTemplateConfigFiles() {
    local fileName
    local targetFile
    local status=0

    for fileName in "$@"; do
        targetFile=$(xrayTemplateConfigFile "${fileName}") || return 1
        removeManagedFileIfPresent "${targetFile}" || status=1
    done
    return "${status}"
}

singBoxTemplateConfigDir() {
    printf '%s\n' "/etc/padm/sing-box/conf/config"
}

singBoxTemplateConfigFile() {
    padmManagedFilePath "$(singBoxTemplateConfigDir)" "$1"
}

removeSingBoxTemplateConfigFiles() {
    local fileName
    local targetFile
    local status=0

    for fileName in "$@"; do
        targetFile=$(singBoxTemplateConfigFile "${fileName}") || return 1
        removeManagedFileIfPresent "${targetFile}" || status=1
    done
    return "${status}"
}

coreTemplateValidateManualAccountName() {
    local accountName=$1
    local baseName
    baseName=$(stripClientNameSuffix "${accountName}") || return 1
    if [[ "${baseName}" == sub_* ]]; then
        errorCard "用户名不能使用 sub_ 开头，该前缀由订阅同步保留"
        return 1
    fi
    if ! validAccountNameValue "${baseName}"; then
        errorCard "用户名格式不合法，仅支持英文、数字及 . _ ~ @ + = : -"
        return 1
    fi
}

coreTemplateConfigBackupCreate() {
    local resultVar=$1
    local core=$2
    local configDir fileName targetPath
    local -a fileNames=()
    local -a existingTargets=()
    local -a targets=()
    local -A seenTargets=()

    case "${core}" in
    xray)
        configDir=$(xrayTemplateConfigDir)
        fileNames=(
            00_log.json 02_VLESS_TCP_inbounds.json 03_VLESS_WS_inbounds.json
            04_trojan_GRPc_inbounds.json 04_trojan_TCP_inbounds.json 05_VMess_WS_inbounds.json
            06_VLESS_GRPc_inbounds.json 07_VLESS_vision_reality_inbounds.json
            08_VLESS_vision_gRPC_inbounds.json 09_routing.json 11_dns.json
            11_VMess_HTTPUpgrade_inbounds.json 12_policy.json 12_VLESS_XHTTP_inbounds.json
            28_trojan_TCP_direct_inbounds.json z_direct_outbound.json blackhole_out.json
            wireguard_out_IPv4_route.json wireguard_out_IPv6_route.json wireguard_outbound.json
            IPv4_out.json IPv6_out.json socks5_outbound.json wireguard_out_IPv6.json
            wireguard_out_IPv4.json
        )
        ;;
    sing-box)
        configDir=$(singBoxTemplateConfigDir)
        fileNames=(
            02_VLESS_TCP_inbounds.json 03_VLESS_WS_inbounds.json 05_VMess_WS_inbounds.json
            06_hysteria2_inbounds.json 07_VLESS_vision_reality_inbounds.json
            08_VLESS_vision_gRPC_inbounds.json 09_tuic_inbounds.json 10_naive_inbounds.json
            11_VMess_HTTPUpgrade_inbounds.json 13_anytls_inbounds.json
            28_trojan_TCP_direct_inbounds.json 30_shadowsocks_inbounds.json sniff.json
            wireguard_endpoints_IPv4_route.json wireguard_endpoints_IPv6_route.json
            wireguard_endpoints_IPv4.json wireguard_endpoints_IPv6.json IPv4_out.json
            IPv6_out.json IPv6_route.json block.json cn_block_outbound.json cn_block_route.json
            01_direct_outbound.json socks5_outbound.json block_domain_outbound.json dns.json
        )
        ;;
    *) return 1 ;;
    esac

    configDir=$(padmRequireSafeAbsolutePath "${configDir%/}") || return 1
    if [[ -d "${configDir}" ]]; then
        existingTargets=("${configDir}"/*.json)
        for targetPath in "${existingTargets[@]}"; do
            [[ -f "${targetPath}" || -L "${targetPath}" ]] || continue
            if [[ -z "${seenTargets[${targetPath}]+x}" ]]; then
                targets+=("${targetPath}")
                seenTargets["${targetPath}"]=1
            fi
        done
    fi
    for fileName in "${fileNames[@]}"; do
        targetPath=$(padmManagedFilePath "${configDir}" "${fileName}") || return 1
        if [[ -z "${seenTargets[${targetPath}]+x}" ]]; then
            targets+=("${targetPath}")
            seenTargets["${targetPath}"]=1
        fi
    done

    if [[ "${core}" == "sing-box" && -n "${nginxConfigPath:-}" ]]; then
        for fileName in default.conf sing_box_VMess_HTTPUpgrade.conf; do
            targetPath=$(nginxConfigFilePath "${fileName}") || return 1
            if [[ -z "${seenTargets[${targetPath}]+x}" ]]; then
                targets+=("${targetPath}")
                seenTargets["${targetPath}"]=1
            fi
        done
    fi

    if declare -F realityEntryHostFile >/dev/null 2>&1; then
        targetPath=$(realityEntryHostFile) || return 1
    else
        targetPath=${PADM_REALITY_ENTRY_HOST_FILE:-/etc/padm/reality_entry_host}
    fi
    if [[ -z "${seenTargets[${targetPath}]+x}" ]]; then
        targets+=("${targetPath}")
    fi

    checkLogBackupCreate "${resultVar}" "${targets[@]}"
}

coreTemplateRestoreServiceState() {
    local service=$1
    local wasRunning=$2
    local restartRunning=${3:-false}
    local runningFunction handleFunction
    case "${service}" in
    xray)
        runningFunction=xrayRunning
        handleFunction=handleXray
        ;;
    sing-box)
        runningFunction=singBoxRunning
        handleFunction=handleSingBox
        ;;
    *) return 1 ;;
    esac

    if [[ "${wasRunning}" == "true" ]]; then
        if "${runningFunction}"; then
            [[ "${restartRunning}" == "true" ]] || return 0
            runCoreServiceActionAllowFailure "${handleFunction}" stop || return 1
        fi
        runCoreServiceActionAllowFailure "${handleFunction}" start
    elif "${runningFunction}"; then
        runCoreServiceActionAllowFailure "${handleFunction}" stop
    fi
}

coreInstallConfigTransaction() {
    local PADM_CORE_INSTALL_TRANSACTION_ACTIVE=true
    coreTemplateConfigTransaction "$@"
}

coreTemplateConfigTransaction() {
    local core=$1
    local operation=$2
    shift 2
    if [[ "${PADM_CORE_TEMPLATE_TRANSACTION_ACTIVE:-}" == "true" ]]; then
        "${operation}" "$@"
        return $?
    fi

    local backupDir=
    local rc=0
    local xrayWasRunning=false
    local singBoxWasRunning=false
    local xrayRestartRunning=false
    local singBoxRestartRunning=false
    local configRestored=true
    local serviceRestored=true
    local title="Xray 配置初始化"
    [[ "${core}" == "sing-box" ]] && title="sing-box 配置初始化"
    [[ "${core}" == "xray" ]] && xrayRestartRunning=true
    [[ "${core}" == "sing-box" ]] && singBoxRestartRunning=true

    coreTemplateConfigBackupCreate backupDir "${core}" || {
        errorCard "${title}备份失败，已取消修改"
        return 1
    }
    if [[ "${core}" == "xray" || "${PADM_CORE_INSTALL_TRANSACTION_ACTIVE:-}" == "true" ]] && xrayRunning; then
        xrayWasRunning=true
    fi
    if [[ "${core}" == "sing-box" || "${PADM_CORE_INSTALL_TRANSACTION_ACTIVE:-}" == "true" ]] && singBoxRunning; then
        singBoxWasRunning=true
    fi

    local PADM_CORE_TEMPLATE_TRANSACTION_ACTIVE=true
    "${operation}" "$@" || rc=$?
    if [[ "${rc}" == "0" ]]; then
        padmRemoveCleanupPath "${backupDir}"
        return 0
    fi

    if checkLogBackupRestore "${backupDir}"; then
        padmRemoveCleanupPath "${backupDir}"
    else
        configRestored=false
        padmForgetCleanupPath "${backupDir}"
    fi
    if [[ "${configRestored}" == "true" ]]; then
        if [[ "${core}" == "xray" || "${PADM_CORE_INSTALL_TRANSACTION_ACTIVE:-}" == "true" ]] &&
            ! coreTemplateRestoreServiceState xray "${xrayWasRunning}" "${xrayRestartRunning}"; then
            serviceRestored=false
        fi
        if [[ "${core}" == "sing-box" || "${PADM_CORE_INSTALL_TRANSACTION_ACTIVE:-}" == "true" ]] &&
            ! coreTemplateRestoreServiceState sing-box "${singBoxWasRunning}" "${singBoxRestartRunning}"; then
            serviceRestored=false
        fi
    fi

    if [[ "${configRestored}" != "true" ]]; then
        errorCard "${title}失败，且旧配置恢复失败，请手动检查备份目录: ${backupDir}"
    elif [[ "${serviceRestored}" != "true" ]]; then
        errorCard "${title}失败，旧配置已恢复，但核心服务运行状态恢复失败"
    else
        errorCard "${title}失败，已恢复旧配置"
    fi
    return "${rc}"
}

# 初始化 Xray 配置文件
initXrayConfigApply() {
    set -- "${1:-}" "${2:-}" "${3:-}"
    local configPath
    configPath="$(xrayTemplateConfigDir)/" || return 1
    progressCard "$2" "初始化 Xray 配置"
    echo
    local uuid=
    local addClientsStatus=
    if [[ -n "${currentUUID}" && -z "${lastInstallationConfig}" ]]; then
        autoRead core_history_user "读取到上次用户配置，UUID为 [${currentUUID}]，是否复用上次安装的用户配置？[y/n]:" historyUUIDStatus
        if [[ "${historyUUIDStatus}" == "y" ]]; then
            addClientsStatus=true
            successCard "使用成功"
        fi
    elif [[ -n "${currentUUID}" && -n "${lastInstallationConfig}" ]]; then
        addClientsStatus=true
    fi

    if [[ -z "${addClientsStatus}" ]]; then
        echoContent yellow "请输入自定义UUID[需合法]，[回车]随机UUID"
        autoRead core_init_uuid "UUID:" customUUID

        if [[ -n ${customUUID} ]]; then
            validUuidValue "${customUUID}" || { errorCard "UUID 格式不合法"; return 1; }
            uuid=${customUUID}
        else
            uuid=$(/etc/padm/xray/xray uuid)
        fi

        echoContent yellow "\n请输入自定义用户名[需合法]，[回车]随机用户名"
        autoRead core_init_username "用户名:" customEmail
        if [[ -z ${customEmail} ]]; then
            customEmail="$(defaultRandomUserNameFromUuid "${uuid}")-VLESS_TCP/TLS_Vision"
        fi
        coreTemplateValidateManualAccountName "${customEmail}" || return 1
    fi

    if [[ -z "${addClientsStatus}" && -z "${uuid}" ]]; then
        addClientsStatus=
        errorCard "uuid读取错误，随机生成"
        uuid=$(/etc/padm/xray/xray uuid)
    fi

    if [[ -n "${uuid}" ]]; then
        currentClients=$(jq -nc --arg uuid "${uuid}" --arg add "${add}" --arg email "${customEmail}" '[{id:$uuid,add:$add,flow:"xtls-rprx-vision",email:$email}]') || return 1
        echoContent green "\n ${customEmail}:${uuid}"
        echo
    fi

    # log
    if [[ ! -f "/etc/padm/xray/conf/00_log.json" ]]; then
        writeGeneratedJsonFile /etc/padm/xray/conf/00_log.json padm-xray-log <<EOF || { errorCard "Xray 日志配置模板提交失败"; return 1; }
{
  "log": {
    "error": "/etc/padm/xray/error.log",
    "loglevel": "warning",
    "dnsLog": false
  }
}
EOF
    fi

    if [[ ! -f "/etc/padm/xray/conf/12_policy.json" ]]; then
        writeGeneratedJsonFile /etc/padm/xray/conf/12_policy.json padm-xray-policy <<EOF || { errorCard "Xray policy 配置模板提交失败"; return 1; }
{
  "policy": {
      "levels": {
          "0": {
              "handshake": $((1 + RANDOM % 4)),
              "connIdle": $((250 + RANDOM % 51))
          }
      }
  }
}
EOF
    fi

    addXrayOutbound "z_direct_outbound" || return 1
    # dns
    if [[ ! -f "/etc/padm/xray/conf/11_dns.json" ]]; then
        writeGeneratedJsonFile /etc/padm/xray/conf/11_dns.json padm-xray-dns <<EOF || { errorCard "Xray DNS 配置模板提交失败"; return 1; }
{
    "dns": {
        "servers": [
          "localhost"
        ]
  }
}
EOF
    fi
    # routing
    writeGeneratedJsonFile /etc/padm/xray/conf/09_routing.json padm-xray-routing <<EOF || { errorCard "Xray routing 配置模板提交失败"; return 1; }
{
  "routing": {
    "rules": [
      {
        "type": "field",
        "domain": [
          "domain:gstatic.com",
          "domain:googleapis.com",
          "domain:googleapis.cn"
        ],
        "outboundTag": "z_direct_outbound"
      }
    ]
  }
}
EOF
    # VLESS_TCP_TLS_Vision
    # 回落nginx
    local fallbacksList='{"dest":31300,"xver":1},{"alpn":"h2","dest":31302,"xver":1}'

    # Trojan TCP
    if protocolSelectionIncludes "${selectCustomInstallType}" 29 "$1"; then
        fallbacksList='{"dest":31296,"xver":1},{"alpn":"h2","dest":31302,"xver":1}'
        writeGeneratedJsonFile /etc/padm/xray/conf/04_trojan_TCP_inbounds.json padm-xray-trojan <<EOF || { errorCard "Xray Trojan TCP 入站模板提交失败"; return 1; }
{
"inbounds":[
	{
	  "port": 31296,
	  "listen": "127.0.0.1",
	  "protocol": "trojan",
	  "tag":"trojanTCP",
	  "settings": {
		"clients": $(initXrayClients 29),
		"fallbacks":[
			{
			    "dest":"31300",
			    "xver":1
			}
		]
	  },
	  "streamSettings": {
		"network": "tcp",
		"security": "none",
		"tcpSettings": {
			"acceptProxyProtocol": true
		}
	  }
	}
	]
}
EOF
    elif [[ -z "$3" ]]; then
        removeXrayTemplateConfigFiles 04_trojan_TCP_inbounds.json || return 1
    fi

    # VLESS_WS_TLS
    if protocolSelectionIncludes "${selectCustomInstallType}" 21 "$1"; then
        fallbacksList=${fallbacksList}',{"path":"/'${customPath}'ws","dest":31297,"xver":1}'
        writeGeneratedJsonFile /etc/padm/xray/conf/03_VLESS_WS_inbounds.json padm-xray-vless-ws <<EOF || { errorCard "Xray VLESS WS 入站模板提交失败"; return 1; }
{
"inbounds":[
    {
	  "port": 31297,
	  "listen": "127.0.0.1",
	  "protocol": "vless",
	  "tag":"VLESSWS",
	  "settings": {
		"clients": $(initXrayClients 21),
		"decryption": "none"
	  },
	  "streamSettings": {
		"network": "ws",
		"security": "none",
		"wsSettings": {
		  "acceptProxyProtocol": true,
		  "path": "/${customPath}ws"
		}
	  }
	}
]
}
EOF
    elif [[ -z "$3" ]]; then
        removeXrayTemplateConfigFiles 03_VLESS_WS_inbounds.json || return 1
    fi
    # VLESS_Reality_XHTTP_TLS
    if protocolSelectionIncludes "${selectCustomInstallType}" 2 "$1"; then
        initRealityProfile || return 1
        initXrayXHTTPort || return 1
        initRealityKey || return 1
        initRealityMldsa65
        writeGeneratedJsonFile /etc/padm/xray/conf/12_VLESS_XHTTP_inbounds.json padm-xray-xhttp <<EOF || { errorCard "Xray XHTTP 入站模板提交失败"; return 1; }
{
"inbounds":[
    {
	  "port": ${xHTTPort},
	  "listen": "0.0.0.0",
	  "protocol": "vless",
	  "tag":"VLESSRealityXHTTP",
	  "settings": {
		"clients": $(initXrayClients 2),
		"decryption": "none"
	  },
	  "streamSettings": {
		"network": "xhttp",
		"security": "reality",
		"realitySettings": {
            "show": false,
            "target": "${realityTargetHost}:${realityTargetPort}",
            "xver": 0,
            "serverNames": [
                "${realitySNI}"
            ],
            "privateKey": "${realityPrivateKey}",
            "publicKey": "${realityPublicKey}",
            "maxTimeDiff": 70000,
            "shortIds": [
                "",
                "6ba85179e30d4fc2"
            ]
        },
        "xhttpSettings": {
            "host": "${realitySNI}",
            "path": "/${customPath}xHTTP",
            "mode": "auto",
            "xmux": {
                "maxConcurrency": "16-32",
                "hMaxRequestTimes": "600-900",
                "hMaxReusableSecs": "1800-3000"
            }
        }
	  }
	}
]
}
EOF
    elif [[ -z "$3" ]]; then
        removeXrayTemplateConfigFiles 12_VLESS_XHTTP_inbounds.json || return 1
    fi
    if protocolSelectionIncludes "${selectCustomInstallType}" 23 "$1"; then
        fallbacksList=${fallbacksList}',{"path":"/'${customPath}'","dest":31306,"xver":1}'
        writeGeneratedJsonFile /etc/padm/xray/conf/11_VMess_HTTPUpgrade_inbounds.json padm-xray-vmess-httpupgrade <<EOF || { errorCard "Xray VMess HTTPUpgrade 入站模板提交失败"; return 1; }
{
    "inbounds":[
        {
          "listen": "127.0.0.1",
          "port": 31306,
          "protocol": "vmess",
          "tag":"VMessHTTPUpgrade",
          "settings": {
            "clients": $(initXrayClients 23)
          },
          "streamSettings": {
            "network": "httpupgrade",
            "security": "none",
            "httpupgradeSettings": {
              "acceptProxyProtocol": true,
              "path": "/${customPath}"
            }
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeXrayTemplateConfigFiles 11_VMess_HTTPUpgrade_inbounds.json || return 1
    fi
    if protocolSelectionIncludes "${selectCustomInstallType}" 22 "$1"; then
        fallbacksList=${fallbacksList}',{"path":"/'${customPath}'vws","dest":31299,"xver":1}'
        writeGeneratedJsonFile /etc/padm/xray/conf/05_VMess_WS_inbounds.json padm-xray-vmess-ws <<EOF || { errorCard "Xray VMess WS 入站模板提交失败"; return 1; }
{
    "inbounds":[
        {
          "listen": "127.0.0.1",
          "port": 31299,
          "protocol": "vmess",
          "tag":"VMessWS",
          "settings": {
            "clients": $(initXrayClients 22)
          },
          "streamSettings": {
            "network": "ws",
            "security": "none",
            "wsSettings": {
              "acceptProxyProtocol": true,
              "path": "/${customPath}vws"
            }
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeXrayTemplateConfigFiles 05_VMess_WS_inbounds.json || return 1
    fi
    if protocolSelectionIncludes "${selectCustomInstallType}" 24 "$1"; then
        fallbacksList=${fallbacksList}',{"path":"/'${customPath}'grpc","dest":31301,"xver":1}'
        writeGeneratedJsonFile /etc/padm/xray/conf/06_VLESS_GRPc_inbounds.json padm-xray-vless-grpc <<EOF || { errorCard "Xray VLESS gRPC 入站模板提交失败"; return 1; }
{
    "inbounds":[
        {
          "listen": "127.0.0.1",
          "port": 31301,
          "protocol": "vless",
          "tag":"VLESSGRPC",
          "settings": {
            "clients": $(initXrayClients 24),
            "decryption": "none"
          },
          "streamSettings": {
            "network": "grpc",
            "security": "none",
            "grpcSettings": {
              "serviceName": "${customPath}grpc"
            }
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeXrayTemplateConfigFiles 06_VLESS_GRPc_inbounds.json || return 1
    fi
    if protocolSelectionIncludes "${selectCustomInstallType}" 25 "$1"; then
        fallbacksList=${fallbacksList}',{"path":"/'${customPath}'trojangrpc","dest":31304,"xver":1}'
        writeGeneratedJsonFile /etc/padm/xray/conf/04_trojan_GRPc_inbounds.json padm-xray-trojan-grpc <<EOF || { errorCard "Xray Trojan gRPC 入站模板提交失败"; return 1; }
{
    "inbounds":[
        {
          "listen": "127.0.0.1",
          "port": 31304,
          "protocol": "trojan",
          "tag":"trojanGRPC",
          "settings": {
            "clients": $(initXrayClients 25)
          },
          "streamSettings": {
            "network": "grpc",
            "security": "none",
            "grpcSettings": {
              "serviceName": "${customPath}trojangrpc"
            }
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeXrayTemplateConfigFiles 04_trojan_GRPc_inbounds.json || return 1
    fi
    # VLESS Vision / traditional TLS fallback frontend
    if [[ "$1" == "all" ]] || protocolSelectionHasAny "${selectCustomInstallType}" 21 22 23 24 25 27 29; then

        writeGeneratedJsonFile /etc/padm/xray/conf/02_VLESS_TCP_inbounds.json padm-xray-vless-tcp <<EOF || { errorCard "Xray VLESS TCP 入站模板提交失败"; return 1; }
{
    "inbounds":[
        {
          "port": ${port},
          "protocol": "vless",
          "tag":"VLESSTCP",
          "settings": {
            "clients":$(initXrayClients 27),
            "decryption": "none",
            "fallbacks": [
                ${fallbacksList}
            ]
          },
          "add": "${add}",
          "streamSettings": {
            "network": "tcp",
            "security": "tls",
            "tlsSettings": {
              "rejectUnknownSni": true,
              "minVersion": "1.2",
              "certificates": [
                {
                  "certificateFile": "/etc/padm/tls/${domain}.crt",
                  "keyFile": "/etc/padm/tls/${domain}.key",
                  "ocspStapling": 3600
                }
              ]
            }
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeXrayTemplateConfigFiles 02_VLESS_TCP_inbounds.json || return 1
    fi

    # Trojan TCP direct
    if [[ "$1" != "all" ]] && protocolSelectionIncludes "${selectCustomInstallType}" 28 "$1"; then
        writeGeneratedJsonFile /etc/padm/xray/conf/28_trojan_TCP_direct_inbounds.json padm-xray-trojan-direct <<EOF || { errorCard "Xray Trojan TCP direct 入站模板提交失败"; return 1; }
{
    "inbounds":[
        {
          "port": ${port},
          "protocol": "trojan",
          "tag":"trojanTCPDirect",
          "settings": {
            "clients": $(initXrayClients 28)
          },
          "streamSettings": {
            "network": "tcp",
            "security": "tls",
            "tlsSettings": {
              "rejectUnknownSni": true,
              "minVersion": "1.2",
              "certificates": [
                {
                  "certificateFile": "/etc/padm/tls/${domain}.crt",
                  "keyFile": "/etc/padm/tls/${domain}.key",
                  "ocspStapling": 3600
                }
              ]
            }
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeXrayTemplateConfigFiles 28_trojan_TCP_direct_inbounds.json || return 1
    fi

    # VLESS_TCP/reality
    if protocolSelectionIncludes "${selectCustomInstallType}" 1 "$1"; then
        echoContent title "\n┌─ 配置 VLESS Reality ───────────────────────────────"
        menuLine "生成 Xray Reality Vision 入站配置"
        menuClose

        initRealityProfile || return 1
        initXrayRealityPort || return 1
        initRealityKey || return 1
        initRealityMldsa65
        writeGeneratedJsonFile /etc/padm/xray/conf/07_VLESS_vision_reality_inbounds.json padm-xray-reality <<EOF || { errorCard "Xray Reality 入站模板提交失败"; return 1; }
{
  "inbounds": [
    {
      "tag": "dokodemo-in-VLESSReality",
      "port": ${realityPort},
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1",
        "port": 45987,
        "network": "tcp"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "tls"
        ],
        "routeOnly": true
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 45987,
      "protocol": "vless",
      "settings": {
        "clients": $(initXrayClients 1),
        "decryption": "none",
        "fallbacks":[
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "${realityTargetHost}:${realityTargetPort}",
          "xver": 0,
          "serverNames": [
            "${realitySNI}"
          ],
          "privateKey": "${realityPrivateKey}",
          "publicKey": "${realityPublicKey}",
          "mldsa65Seed": "${realityMldsa65Seed}",
          "mldsa65Verify": "${realityMldsa65Verify}",
          "maxTimeDiff": 70000,
          "shortIds": [
            "",
            "6ba85179e30d4fc2"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    }
  ],
  "routing": {
    "rules": [
      {
        "inboundTag": [
          "dokodemo-in"
        ],
        "domain": [
          "${realitySNI}"
        ],
        "outboundTag": "z_direct_outbound"
      },
      {
        "inboundTag": [
          "dokodemo-in"
        ],
        "outboundTag": "blackhole_out"
      }
    ]
  }
}
EOF
    elif [[ -z "$3" ]]; then
        removeXrayTemplateConfigFiles \
            07_VLESS_vision_reality_inbounds.json \
            08_VLESS_vision_gRPC_inbounds.json || return 1
    fi
    if protocolSelectionIncludes "${selectCustomInstallType}" 26 "$1"; then
        echoContent title "\n┌─ 配置 VLESS Reality gRPC ──────────────────────────"
        menuLine "生成 Xray Reality gRPC 入站配置"
        menuClose

        initRealityProfile || return 1
        initXrayRealityGrpcPort || return 1
        initRealityKey || return 1
        initRealityMldsa65
        writeGeneratedJsonFile /etc/padm/xray/conf/08_VLESS_vision_gRPC_inbounds.json padm-xray-reality-grpc <<EOF || { errorCard "Xray Reality gRPC 入站模板提交失败"; return 1; }
{
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${realityGrpcPort},
      "protocol": "vless",
      "settings": {
        "clients": $(initXrayClients 26),
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "${realityTargetHost}:${realityTargetPort}",
          "xver": 0,
          "serverNames": [
            "${realitySNI}"
          ],
          "privateKey": "${realityPrivateKey}",
          "publicKey": "${realityPublicKey}",
          "mldsa65Seed": "${realityMldsa65Seed}",
          "mldsa65Verify": "${realityMldsa65Verify}",
          "maxTimeDiff": 70000,
          "shortIds": [
            "",
            "6ba85179e30d4fc2"
          ]
        },
        "grpcSettings": {
          "serviceName": "grpc"
        }
      }
    }
  ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeXrayTemplateConfigFiles 08_VLESS_vision_gRPC_inbounds.json || return 1
    fi
    installSniffing || return 1
    if [[ -z "$3" ]]; then
        removeXrayOutbound wireguard_out_IPv4_route || return 1
        removeXrayOutbound wireguard_out_IPv6_route || return 1
        removeXrayOutbound wireguard_outbound || return 1
        removeXrayOutbound IPv4_out || return 1
        removeXrayOutbound IPv6_out || return 1
        removeXrayOutbound socks5_outbound || return 1
        removeXrayOutbound blackhole_out || return 1
        removeXrayOutbound wireguard_out_IPv6 || return 1
        removeXrayOutbound wireguard_out_IPv4 || return 1
        addXrayOutbound z_direct_outbound || return 1
        addXrayOutbound blackhole_out || return 1
    fi
}

initXrayConfig() {
    coreTemplateConfigTransaction xray initXrayConfigApply "$@"
}


# 初始化 sing-box 配置文件
stopSingBoxBeforeTemplateWrite() {
    runCoreServiceActionAllowFailure handleSingBox stop || { errorCard "sing-box 服务停止失败，已取消写入配置"; return 1; }
}

initSingBoxConfigApply() {
    set -- "${1:-}" "${2:-}" "${3:-}"
    local singBoxConfigPath
    singBoxConfigPath="$(singBoxTemplateConfigDir)/" || return 1
    progressCard "$2" "初始化 sing-box 配置"

    echo
    local uuid=
    local addClientsStatus=
    local sslDomain=
    collectTLSProfile
    sslDomain=${tlsCertDomain}
    if [[ -n "${currentUUID}" && -z "${lastInstallationConfig}" ]]; then
        autoRead core_history_user "读取到上次用户配置，UUID为 [${currentUUID}]，是否复用上次安装的用户配置？[y/n]:" historyUUIDStatus
        if [[ "${historyUUIDStatus}" == "y" ]]; then
            addClientsStatus=true
            successCard "使用成功"
        fi
    elif [[ -n "${currentUUID}" && -n "${lastInstallationConfig}" ]]; then
        addClientsStatus=true
    fi

    if [[ -z "${addClientsStatus}" ]]; then
        echoContent yellow "请输入自定义UUID[需合法]，[回车]随机UUID"
        autoRead core_init_uuid "UUID:" customUUID

        if [[ -n ${customUUID} ]]; then
            validUuidValue "${customUUID}" || { errorCard "UUID 格式不合法"; return 1; }
            uuid=${customUUID}
        else
            uuid=$(/etc/padm/sing-box/sing-box generate uuid)
        fi

        echoContent yellow "\n请输入自定义用户名[需合法]，[回车]随机用户名"
        autoRead core_init_username "用户名:" customEmail
        if [[ -z ${customEmail} ]]; then
            customEmail="$(defaultRandomUserNameFromUuid "${uuid}")-VLESS_TCP/TLS_Vision"
        fi
        coreTemplateValidateManualAccountName "${customEmail}" || return 1
    fi

    if [[ -z "${addClientsStatus}" && -z "${uuid}" ]]; then
        addClientsStatus=
        errorCard "uuid读取错误，随机生成"
        uuid=$(/etc/padm/sing-box/sing-box generate uuid)
    fi

    if [[ -n "${uuid}" ]]; then
        currentClients=$(jq -nc --arg uuid "${uuid}" --arg name "${customEmail}" '[{uuid:$uuid,flow:"xtls-rprx-vision",name:$name}]') || return 1
        echoContent yellow "\n ${customEmail}:${uuid}"
    fi

    # VLESS Vision
    if protocolSelectionIncludes "${selectCustomInstallType}" 27 "$1"; then
        echoContent title "\n┌─ 配置 VLESS Vision ────────────────────────────────"
        menuLine "开始配置 VLESS Vision 协议端口"
        menuClose
        echo
        readSingBoxPortResult result "${singBoxVLESSVisionPort}" || return 1
        statusCard "VLESS Vision端口" "${result[-1]}"

        checkDNSIP "${domain}" || return 1
        removeNginxDefaultConf || return 1
        stopSingBoxBeforeTemplateWrite || return 1

        checkPortOpen "${result[-1]}" "${domain}" || return 1
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/02_VLESS_TCP_inbounds.json padm-sing-box-vless-tcp <<EOF || { errorCard "sing-box VLESS Vision 入站模板提交失败"; return 1; }
{
    "inbounds":[
        {
          "type": "vless",
          "listen":"::",
          "listen_port":${result[-1]},
          "tag":"VLESSTCP",
          "users":$(initSingBoxClients 27),
          "tls":{
            "server_name": "${sslDomain}",
            "enabled": true,
            "certificate_path": "/etc/padm/tls/${sslDomain}.crt",
            "key_path": "/etc/padm/tls/${sslDomain}.key"
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeSingBoxTemplateConfigFiles 02_VLESS_TCP_inbounds.json || return 1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 21 "$1"; then
        echoContent title "\n┌─ 配置 VLESS WS ────────────────────────────────────"
        menuLine "开始配置 VLESS WS 协议端口"
        menuClose
        echo
        readSingBoxPortResult result "${singBoxVLESSWSPort}" || return 1
        statusCard "VLESS WS端口" "${result[-1]}"

        checkDNSIP "${domain}" || return 1
        removeNginxDefaultConf || return 1
        stopSingBoxBeforeTemplateWrite || return 1
        randomPathFunction || return 1
        checkPortOpen "${result[-1]}" "${domain}" || return 1
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/03_VLESS_WS_inbounds.json padm-sing-box-vless-ws <<EOF || { errorCard "sing-box VLESS WS 入站模板提交失败"; return 1; }
{
    "inbounds":[
        {
          "type": "vless",
          "listen":"::",
          "listen_port":${result[-1]},
          "tag":"VLESSWS",
          "users":$(initSingBoxClients 21),
          "tls":{
            "server_name": "${sslDomain}",
            "enabled": true,
            "certificate_path": "/etc/padm/tls/${sslDomain}.crt",
            "key_path": "/etc/padm/tls/${sslDomain}.key"
          },
          "transport": {
            "type": "ws",
            "path": "/${currentPath}ws",
            "max_early_data": 2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeSingBoxTemplateConfigFiles 03_VLESS_WS_inbounds.json || return 1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 22 "$1"; then
        echoContent title "\n┌─ 配置 VMess WS ────────────────────────────────────"
        menuLine "开始配置 VMess WS 协议端口"
        menuClose
        echo
        readSingBoxPortResult result "${singBoxVMessWSPort}" || return 1
        statusCard "VMess ws端口" "${result[-1]}"

        checkDNSIP "${domain}" || return 1
        removeNginxDefaultConf || return 1
        stopSingBoxBeforeTemplateWrite || return 1
        randomPathFunction || return 1
        checkPortOpen "${result[-1]}" "${domain}" || return 1
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/05_VMess_WS_inbounds.json padm-sing-box-vmess-ws <<EOF || { errorCard "sing-box VMess WS 入站模板提交失败"; return 1; }
{
    "inbounds":[
        {
          "type": "vmess",
          "listen":"::",
          "listen_port":${result[-1]},
          "tag":"VMessWS",
          "users":$(initSingBoxClients 22),
          "tls":{
            "server_name": "${sslDomain}",
            "enabled": true,
            "certificate_path": "/etc/padm/tls/${sslDomain}.crt",
            "key_path": "/etc/padm/tls/${sslDomain}.key"
          },
          "transport": {
            "type": "ws",
            "path": "/${currentPath}",
            "max_early_data": 2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeSingBoxTemplateConfigFiles 05_VMess_WS_inbounds.json || return 1
    fi

    # VLESS_Reality_Vision
    if protocolSelectionIncludes "${selectCustomInstallType}" 1 "$1"; then
        echoContent title "\n┌─ 配置 VLESS Reality Vision ────────────────────────"
        menuLine "开始配置 VLESS Reality Vision 协议端口"
        menuClose
        initRealityProfile || return 1
        initRealityKey || return 1
        echo
        readSingBoxPortResult result "${singBoxVLESSRealityVisionPort}" true tcp reality_subport 1 vision || return 1
        if declare -F realityStreamSplitEnabled >/dev/null 2>&1 && realityStreamSplitEnabled &&
            [[ "${result[-1]}" == "$(realityStreamInternalPortForProtocol vision)" ]]; then
            statusCard "VLESS Reality Vision 共存内部端口" "${result[-1]}"
        else
            statusCard "VLESS Reality Vision 客户端连接端口" "${result[-1]}"
        fi
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/07_VLESS_vision_reality_inbounds.json padm-sing-box-reality <<EOF || { errorCard "sing-box Reality Vision 入站模板提交失败"; return 1; }
{
  "inbounds": [
    {
      "type": "vless",
      "listen":"::",
      "listen_port":${result[-1]},
      "tag": "VLESSReality",
      "users":$(initSingBoxClients 1),
      "tls": {
        "enabled": true,
        "server_name": "${realitySNI}",
        "reality": {
            "enabled": true,
            "handshake":{
                "server": "${realityTargetHost}",
                "server_port":${realityTargetPort}
            },
            "private_key": "${realityPrivateKey}",
            "short_id": [
                "",
                "6ba85179e30d4fc2"
            ]
        }
      }
    }
  ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeSingBoxTemplateConfigFiles 07_VLESS_vision_reality_inbounds.json || return 1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 26 "$1"; then
        echoContent title "\n┌─ 配置 VLESS Reality gRPC ──────────────────────────"
        menuLine "开始配置 VLESS Reality gRPC 协议端口"
        menuClose
        initRealityProfile || return 1
        initRealityKey || return 1
        echo
        readSingBoxPortResult result "${singBoxVLESSRealityGRPCPort}" true tcp reality_grpc_subport 26 || return 1
        statusCard "VLESS Reality gRPC 客户端连接端口" "${result[-1]}"
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/08_VLESS_vision_gRPC_inbounds.json padm-sing-box-reality-grpc <<EOF || { errorCard "sing-box Reality gRPC 入站模板提交失败"; return 1; }
{
  "inbounds": [
    {
      "type": "vless",
      "listen":"::",
      "listen_port":${result[-1]},
      "users":$(initSingBoxClients 26),
      "tag": "VLESSRealityGRPC",
      "tls": {
        "enabled": true,
        "server_name": "${realitySNI}",
        "reality": {
            "enabled": true,
            "handshake":{
                "server":"${realityTargetHost}",
                "server_port":${realityTargetPort}
            },
            "private_key": "${realityPrivateKey}",
            "short_id": [
                "",
                "6ba85179e30d4fc2"
            ]
        }
      },
      "transport": {
          "type": "grpc",
          "service_name": "grpc"
      }
    }
  ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeSingBoxTemplateConfigFiles 08_VLESS_vision_gRPC_inbounds.json || return 1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 3 "$1"; then
        echoContent title "\n┌─ 配置 Hysteria2 ───────────────────────────────────"
        menuLine "开始配置 Hysteria2 协议端口"
        menuClose
        echo
        readSingBoxPortResult result "${singBoxHysteria2Port}" || return 1
        statusCard "Hysteria2端口" "${result[-1]}"
        initHysteria2Network || return 1
        local hysteria2MasqueradeConfig
        hysteria2MasqueradeConfig=$(hysteria2MasqueradeJson "${hysteria2Masquerade:-}") || return 1
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/06_hysteria2_inbounds.json padm-sing-box-hysteria2 <<EOF || { errorCard "sing-box Hysteria2 入站模板提交失败"; return 1; }
{
    "inbounds": [
        {
            "type": "hysteria2",
            "listen": "::",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 3),
            "up_mbps":${hysteria2ClientUploadSpeed},
            "down_mbps":${hysteria2ClientDownloadSpeed},
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "alpn": [
                    "h3"
                ],
                "certificate_path": "/etc/padm/tls/${sslDomain}.crt",
                "key_path": "/etc/padm/tls/${sslDomain}.key"
            },
            "masquerade": ${hysteria2MasqueradeConfig}
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeSingBoxTemplateConfigFiles 06_hysteria2_inbounds.json || return 1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 28 "$1"; then
        echoContent title "\n┌─ 配置 Trojan ──────────────────────────────────────"
        menuLine "开始配置 Trojan 协议端口"
        menuClose
        echo
        readSingBoxPortResult result "${singBoxTrojanPort}" || return 1
        statusCard "Trojan端口" "${result[-1]}"
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/28_trojan_TCP_direct_inbounds.json padm-sing-box-trojan <<EOF || { errorCard "sing-box Trojan TCP 入站模板提交失败"; return 1; }
{
    "inbounds": [
        {
            "type": "trojan",
            "listen": "::",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 28),
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "certificate_path": "/etc/padm/tls/${sslDomain}.crt",
                "key_path": "/etc/padm/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeSingBoxTemplateConfigFiles 28_trojan_TCP_direct_inbounds.json || return 1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 30 "$1"; then
        echoContent title "\n┌─ 配置 Shadowsocks ─────────────────────────────────"
        menuLine "开始配置 Shadowsocks 协议端口"
        menuClose
        echo
        readSingBoxPortResult result "${singBoxShadowsocksPort}" || return 1
        statusCard "Shadowsocks端口" "${result[-1]}"
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/30_shadowsocks_inbounds.json padm-sing-box-shadowsocks <<EOF || { errorCard "sing-box Shadowsocks 入站模板提交失败"; return 1; }
{
    "inbounds": [
        {
            "type": "shadowsocks",
            "listen": "::",
            "tag": "singbox-shadowsocks-in",
            "listen_port": ${result[-1]},
            "method": "2022-blake3-aes-128-gcm",
            "password": "$(shadowsocks2022KeyFromSeed "server:${currentClients}")",
            "users": $(initSingBoxClients 30)
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeSingBoxTemplateConfigFiles 30_shadowsocks_inbounds.json || return 1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 31 "$1"; then
        echoContent title "\n┌─ 配置 Tuic ────────────────────────────────────────"
        menuLine "开始配置 Tuic 协议端口"
        menuClose
        echo
        readSingBoxPortResult result "${singBoxTuicPort}" || return 1
        statusCard "Tuic端口" "${result[-1]}"
        initTuicProtocol
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/09_tuic_inbounds.json padm-sing-box-tuic <<EOF || { errorCard "sing-box TUIC 入站模板提交失败"; return 1; }
{
     "inbounds": [
        {
            "type": "tuic",
            "listen": "::",
            "tag": "singbox-tuic-in",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 31),
            "congestion_control": "${tuicAlgorithm}",
            "auth_timeout": "3s",
            "zero_rtt_handshake": false,
            "heartbeat": "10s",
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "alpn": [
                    "h3"
                ],
                "certificate_path": "/etc/padm/tls/${sslDomain}.crt",
                "key_path": "/etc/padm/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeSingBoxTemplateConfigFiles 09_tuic_inbounds.json || return 1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 5 "$1"; then
        echoContent title "\n┌─ 配置 Naive ───────────────────────────────────────"
        menuLine "开始配置 Naive 协议端口"
        menuClose
        echo
        readSingBoxPortResult result "${singBoxNaivePort}" || return 1
        statusCard "Naive端口" "${result[-1]}"
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/10_naive_inbounds.json padm-sing-box-naive <<EOF || { errorCard "sing-box Naive 入站模板提交失败"; return 1; }
{
     "inbounds": [
        {
            "type": "naive",
            "listen": "::",
            "tag": "singbox-naive-in",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 5),
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "certificate_path": "/etc/padm/tls/${sslDomain}.crt",
                "key_path": "/etc/padm/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeSingBoxTemplateConfigFiles 10_naive_inbounds.json || return 1
    fi
    if protocolSelectionIncludes "${selectCustomInstallType}" 23 "$1"; then
        echoContent title "\n┌─ 配置 VMess HTTPUpgrade ───────────────────────────"
        menuLine "开始配置 VMess HTTPUpgrade 协议端口"
        menuClose
        echo
        readSingBoxPortResult result "${singBoxVMessHTTPUpgradePort}" || return 1
        statusCard "VMess HTTPUpgrade端口" "${result[-1]}"

        checkDNSIP "${domain}" || return 1
        removeNginxDefaultConf || return 1
        stopSingBoxBeforeTemplateWrite || return 1
        randomPathFunction || return 1
        local httpUpgradeNginxConf
        if ! httpUpgradeNginxConf=$(nginxConfigFilePath sing_box_VMess_HTTPUpgrade.conf); then
            padmShowUnsafePathError "配置 VMess HTTPUpgrade"
            return 1
        fi
        removeManagedFileIfPresent "${httpUpgradeNginxConf}" || return 1
        checkPortOpen "${result[-1]}" "${domain}" || return 1
        singBoxNginxConfig "$1" "${result[-1]}" || return 1
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/11_VMess_HTTPUpgrade_inbounds.json padm-sing-box-vmess-httpupgrade <<EOF || { errorCard "sing-box VMess HTTPUpgrade 入站模板提交失败"; return 1; }
{
    "inbounds":[
        {
          "type": "vmess",
          "listen":"127.0.0.1",
          "listen_port":31306,
          "tag":"VMessHTTPUpgrade",
          "users":$(initSingBoxClients 23),
          "transport": {
            "type": "httpupgrade",
            "path": "/${currentPath}"
          }
        }
    ]
}
EOF
        if ! bootStartup nginx; then
            errorCard "Nginx 开机自启配置失败"
            return 1
        fi
        if [[ -n "$3" ]] && ! runCoreServiceActionAllowFailure handleNginx start; then
            errorCard "Nginx 服务启动失败，VMess HTTPUpgrade 配置已写入"
            return 1
        fi
    elif [[ -z "$3" ]]; then
        removeSingBoxTemplateConfigFiles 11_VMess_HTTPUpgrade_inbounds.json || return 1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 4 "$1"; then
        echoContent title "\n┌─ 配置 AnyTLS ──────────────────────────────────────"
        menuLine "开始配置 AnyTLS 协议端口"
        menuClose
        echo
        readSingBoxPortResult result "${singBoxAnyTLSPort}" || return 1
        statusCard "AnyTLS端口" "${result[-1]}"
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/13_anytls_inbounds.json padm-sing-box-anytls <<EOF || { errorCard "sing-box AnyTLS 入站模板提交失败"; return 1; }
{
    "inbounds": [
        {
            "type": "anytls",
            "listen": "::",
            "tag":"anytls",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 4),
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "certificate_path": "/etc/padm/tls/${sslDomain}.crt",
                "key_path": "/etc/padm/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        removeSingBoxTemplateConfigFiles 13_anytls_inbounds.json || return 1
    fi

    if [[ -z "$3" ]]; then
        removeSingBoxConfig wireguard_endpoints_IPv4_route || return 1
        removeSingBoxConfig wireguard_endpoints_IPv6_route || return 1
        removeSingBoxConfig wireguard_endpoints_IPv4 || return 1
        removeSingBoxConfig wireguard_endpoints_IPv6 || return 1

        removeSingBoxConfig IPv4_out || return 1
        removeSingBoxConfig IPv6_out || return 1
        removeSingBoxConfig IPv6_route || return 1
        removeSingBoxConfig block || return 1
        removeSingBoxConfig cn_block_outbound || return 1
        removeSingBoxConfig cn_block_route || return 1
        removeSingBoxConfig 01_direct_outbound || return 1
        removeSingBoxConfig socks5_outbound.json || return 1
        removeSingBoxConfig block_domain_outbound || return 1
        removeSingBoxConfig dns || return 1
    fi

    setSniffRouting || return 1
}

initSingBoxConfigTransaction() {
    coreTemplateConfigTransaction sing-box initSingBoxConfigApply "$@"
}

initSingBoxConfig() {
    padmRunPortAllowTransaction initSingBoxConfigTransaction "$@"
}
