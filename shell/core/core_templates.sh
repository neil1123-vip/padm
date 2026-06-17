#!/usr/bin/env bash

# core template managed config helpers
xrayTemplateConfigFile() {
    padmManagedFilePath "/etc/padm/xray/conf" "$1"
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

singBoxTemplateConfigFile() {
    padmManagedFilePath "/etc/padm/sing-box/conf/config" "$1"
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

# 初始化 Xray 配置文件
initXrayConfig() {
    set -- "${1:-}" "${2:-}" "${3:-}"
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
            uuid=${customUUID}
        else
            uuid=$(/etc/padm/xray/xray uuid)
        fi

        echoContent yellow "\n请输入自定义用户名[需合法]，[回车]随机用户名"
        autoRead core_init_username "用户名:" customEmail
        if [[ -z ${customEmail} ]]; then
            customEmail="$(defaultRandomUserNameFromUuid "${uuid}")-VLESS_TCP/TLS_Vision"
        fi
    fi

    if [[ -z "${addClientsStatus}" && -z "${uuid}" ]]; then
        addClientsStatus=
        errorCard "uuid读取错误，随机生成"
        uuid=$(/etc/padm/xray/xray uuid)
    fi

    if [[ -n "${uuid}" ]]; then
        currentClients='[{"id":"'${uuid}'","add":"'${add}'","flow":"xtls-rprx-vision","email":"'${customEmail}'"}]'
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

    addXrayOutbound "z_direct_outbound"
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
    if protocolSelectionIncludes "${selectCustomInstallType}" 4 "$1"; then
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
		"clients": $(initXrayClients 4),
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
    if protocolSelectionIncludes "${selectCustomInstallType}" 1 "$1"; then
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
		"clients": $(initXrayClients 1),
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
    if protocolSelectionIncludes "${selectCustomInstallType}" 12 "$1"; then
        initRealityProfile || return 1
        initXrayXHTTPort || return 1
        initRealityKey
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
		"clients": $(initXrayClients 12),
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
    if protocolSelectionIncludes "${selectCustomInstallType}" 3 "$1"; then
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
            "clients": $(initXrayClients 3)
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
    # VLESS Vision
    if protocolSelectionIncludes "${selectCustomInstallType}" 0 "$1"; then

        writeGeneratedJsonFile /etc/padm/xray/conf/02_VLESS_TCP_inbounds.json padm-xray-vless-tcp <<EOF || { errorCard "Xray VLESS TCP 入站模板提交失败"; return 1; }
{
    "inbounds":[
        {
          "port": ${port},
          "protocol": "vless",
          "tag":"VLESSTCP",
          "settings": {
            "clients":$(initXrayClients 0),
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

    # VLESS_TCP/reality
    if protocolSelectionIncludes "${selectCustomInstallType}" 7 "$1"; then
        echoContent title "\n┌─ 配置 VLESS Reality ───────────────────────────────"
        menuLine "生成 Xray Reality Vision 入站配置"
        menuClose

        initRealityProfile || return 1
        initXrayRealityPort || return 1
        initRealityKey
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
        "clients": $(initXrayClients 7),
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
    installSniffing
    if [[ -z "$3" ]]; then
        removeXrayOutbound wireguard_out_IPv4_route
        removeXrayOutbound wireguard_out_IPv6_route
        removeXrayOutbound wireguard_outbound
        removeXrayOutbound IPv4_out
        removeXrayOutbound IPv6_out
        removeXrayOutbound socks5_outbound
        removeXrayOutbound blackhole_out
        removeXrayOutbound wireguard_out_IPv6
        removeXrayOutbound wireguard_out_IPv4
        addXrayOutbound z_direct_outbound
        addXrayOutbound blackhole_out
    fi
}


# 初始化 sing-box 配置文件
stopSingBoxBeforeTemplateWrite() {
    runCoreServiceActionAllowFailure handleSingBox stop || { errorCard "sing-box 服务停止失败，已取消写入配置"; return 1; }
}

initSingBoxConfig() {
    set -- "${1:-}" "${2:-}" "${3:-}"
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
            uuid=${customUUID}
        else
            uuid=$(/etc/padm/sing-box/sing-box generate uuid)
        fi

        echoContent yellow "\n请输入自定义用户名[需合法]，[回车]随机用户名"
        autoRead core_init_username "用户名:" customEmail
        if [[ -z ${customEmail} ]]; then
            customEmail="$(defaultRandomUserNameFromUuid "${uuid}")-VLESS_TCP/TLS_Vision"
        fi
    fi

    if [[ -z "${addClientsStatus}" && -z "${uuid}" ]]; then
        addClientsStatus=
        errorCard "uuid读取错误，随机生成"
        uuid=$(/etc/padm/sing-box/sing-box generate uuid)
    fi

    if [[ -n "${uuid}" ]]; then
        currentClients='[{"uuid":"'${uuid}'","flow":"xtls-rprx-vision","name":"'${customEmail}'"}]'
        echoContent yellow "\n ${customEmail}:${uuid}"
    fi

    # VLESS Vision
    if protocolSelectionIncludes "${selectCustomInstallType}" 0 "$1"; then
        echoContent title "\n┌─ 配置 VLESS Vision ────────────────────────────────"
        menuLine "开始配置 VLESS Vision 协议端口"
        menuClose
        echo
        readSingBoxPortResult result "${singBoxVLESSVisionPort}" || return 1
        statusCard "VLESS Vision端口" "${result[-1]}"

        checkDNSIP "${domain}" || return 1
        removeNginxDefaultConf
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
          "users":$(initSingBoxClients 0),
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

    if protocolSelectionIncludes "${selectCustomInstallType}" 1 "$1"; then
        echoContent title "\n┌─ 配置 VLESS WS ────────────────────────────────────"
        menuLine "开始配置 VLESS WS 协议端口"
        menuClose
        echo
        readSingBoxPortResult result "${singBoxVLESSWSPort}" || return 1
        statusCard "VLESS WS端口" "${result[-1]}"

        checkDNSIP "${domain}" || return 1
        removeNginxDefaultConf
        stopSingBoxBeforeTemplateWrite || return 1
        randomPathFunction
        checkPortOpen "${result[-1]}" "${domain}" || return 1
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/03_VLESS_WS_inbounds.json padm-sing-box-vless-ws <<EOF || { errorCard "sing-box VLESS WS 入站模板提交失败"; return 1; }
{
    "inbounds":[
        {
          "type": "vless",
          "listen":"::",
          "listen_port":${result[-1]},
          "tag":"VLESSWS",
          "users":$(initSingBoxClients 1),
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

    if protocolSelectionIncludes "${selectCustomInstallType}" 3 "$1"; then
        echoContent title "\n┌─ 配置 VMess WS ────────────────────────────────────"
        menuLine "开始配置 VMess WS 协议端口"
        menuClose
        echo
        readSingBoxPortResult result "${singBoxVMessWSPort}" || return 1
        statusCard "VMess ws端口" "${result[-1]}"

        checkDNSIP "${domain}" || return 1
        removeNginxDefaultConf
        stopSingBoxBeforeTemplateWrite || return 1
        randomPathFunction
        checkPortOpen "${result[-1]}" "${domain}" || return 1
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/05_VMess_WS_inbounds.json padm-sing-box-vmess-ws <<EOF || { errorCard "sing-box VMess WS 入站模板提交失败"; return 1; }
{
    "inbounds":[
        {
          "type": "vmess",
          "listen":"::",
          "listen_port":${result[-1]},
          "tag":"VMessWS",
          "users":$(initSingBoxClients 3),
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
    if protocolSelectionIncludes "${selectCustomInstallType}" 7 "$1"; then
        echoContent title "\n┌─ 配置 VLESS Reality Vision ────────────────────────"
        menuLine "开始配置 VLESS Reality Vision 协议端口"
        menuClose
        initRealityProfile || return 1
        initRealityKey
        echo
        readSingBoxPortResult result "${singBoxVLESSRealityVisionPort}" || return 1
        statusCard "VLESS Reality Vision端口" "${result[-1]}"
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/07_VLESS_vision_reality_inbounds.json padm-sing-box-reality <<EOF || { errorCard "sing-box Reality Vision 入站模板提交失败"; return 1; }
{
  "inbounds": [
    {
      "type": "vless",
      "listen":"::",
      "listen_port":${result[-1]},
      "tag": "VLESSReality",
      "users":$(initSingBoxClients 7),
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

    if protocolSelectionIncludes "${selectCustomInstallType}" 8 "$1"; then
        echoContent title "\n┌─ 配置 VLESS Reality gRPC ──────────────────────────"
        menuLine "开始配置 VLESS Reality gRPC 协议端口"
        menuClose
        initRealityProfile || return 1
        initRealityKey
        echo
        readSingBoxPortResult result "${singBoxVLESSRealityGRPCPort}" || return 1
        statusCard "VLESS Reality gPRC端口" "${result[-1]}"
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/08_VLESS_vision_gRPC_inbounds.json padm-sing-box-reality-grpc <<EOF || { errorCard "sing-box Reality gRPC 入站模板提交失败"; return 1; }
{
  "inbounds": [
    {
      "type": "vless",
      "listen":"::",
      "listen_port":${result[-1]},
      "users":$(initSingBoxClients 8),
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

    if protocolSelectionIncludes "${selectCustomInstallType}" 6 "$1"; then
        echoContent title "\n┌─ 配置 Hysteria2 ───────────────────────────────────"
        menuLine "开始配置 Hysteria2 协议端口"
        menuClose
        echo
        readSingBoxPortResult result "${singBoxHysteria2Port}" || return 1
        statusCard "Hysteria2端口" "${result[-1]}"
        initHysteria2Network
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/06_hysteria2_inbounds.json padm-sing-box-hysteria2 <<EOF || { errorCard "sing-box Hysteria2 入站模板提交失败"; return 1; }
{
    "inbounds": [
        {
            "type": "hysteria2",
            "listen": "::",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 6),
            "up_mbps":${hysteria2ClientDownloadSpeed},
            "down_mbps":${hysteria2ClientUploadSpeed},
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
        removeSingBoxTemplateConfigFiles 06_hysteria2_inbounds.json || return 1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 4 "$1"; then
        echoContent title "\n┌─ 配置 Trojan ──────────────────────────────────────"
        menuLine "开始配置 Trojan 协议端口"
        menuClose
        echo
        readSingBoxPortResult result "${singBoxTrojanPort}" || return 1
        statusCard "Trojan端口" "${result[-1]}"
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/04_trojan_TCP_inbounds.json padm-sing-box-trojan <<EOF || { errorCard "sing-box Trojan TCP 入站模板提交失败"; return 1; }
{
    "inbounds": [
        {
            "type": "trojan",
            "listen": "::",
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
        removeSingBoxTemplateConfigFiles 04_trojan_TCP_inbounds.json || return 1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 9 "$1"; then
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
            "users": $(initSingBoxClients 9),
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

    if protocolSelectionIncludes "${selectCustomInstallType}" 10 "$1"; then
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
            "users": $(initSingBoxClients 10),
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
    if protocolSelectionIncludes "${selectCustomInstallType}" 11 "$1"; then
        echoContent title "\n┌─ 配置 VMess HTTPUpgrade ───────────────────────────"
        menuLine "开始配置 VMess HTTPUpgrade 协议端口"
        menuClose
        echo
        readSingBoxPortResult result "${singBoxVMessHTTPUpgradePort}" || return 1
        statusCard "VMess HTTPUpgrade端口" "${result[-1]}"

        checkDNSIP "${domain}" || return 1
        removeNginxDefaultConf || return 1
        stopSingBoxBeforeTemplateWrite || return 1
        randomPathFunction
        local httpUpgradeNginxConf
        if ! httpUpgradeNginxConf=$(nginxConfigFilePath sing_box_VMess_HTTPUpgrade.conf); then
            padmShowUnsafePathError "配置 VMess HTTPUpgrade"
            return 1
        fi
        removeManagedFileIfPresent "${httpUpgradeNginxConf}" || return 1
        checkPortOpen "${result[-1]}" "${domain}" || return 1
        singBoxNginxConfig "$1" "${result[-1]}"
        writeGeneratedJsonFile /etc/padm/sing-box/conf/config/11_VMess_HTTPUpgrade_inbounds.json padm-sing-box-vmess-httpupgrade <<EOF || { errorCard "sing-box VMess HTTPUpgrade 入站模板提交失败"; return 1; }
{
    "inbounds":[
        {
          "type": "vmess",
          "listen":"127.0.0.1",
          "listen_port":31306,
          "tag":"VMessHTTPUpgrade",
          "users":$(initSingBoxClients 11),
          "transport": {
            "type": "httpupgrade",
            "path": "/${currentPath}"
          }
        }
    ]
}
EOF
        bootStartup nginx
        if [[ -n "$3" ]] && ! runCoreServiceActionAllowFailure handleNginx start; then
            errorCard "Nginx 服务启动失败，VMess HTTPUpgrade 配置已写入"
            return 1
        fi
    elif [[ -z "$3" ]]; then
        removeSingBoxTemplateConfigFiles 11_VMess_HTTPUpgrade_inbounds.json || return 1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 13 "$1"; then
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
            "users": $(initSingBoxClients 13),
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
        removeSingBoxConfig wireguard_endpoints_IPv4_route
        removeSingBoxConfig wireguard_endpoints_IPv6_route
        removeSingBoxConfig wireguard_endpoints_IPv4
        removeSingBoxConfig wireguard_endpoints_IPv6

        removeSingBoxConfig IPv4_out
        removeSingBoxConfig IPv6_out
        removeSingBoxConfig IPv6_route
        removeSingBoxConfig block
        removeSingBoxConfig cn_block_outbound
        removeSingBoxConfig cn_block_route
        removeSingBoxConfig 01_direct_outbound
        removeSingBoxConfig socks5_outbound.json
        removeSingBoxConfig block_domain_outbound
        removeSingBoxConfig dns
    fi

    setSniffRouting
}
