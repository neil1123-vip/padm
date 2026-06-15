#!/usr/bin/env bash


# 添加 sing-box 路由规则
addSingBoxRouteRule() {
    local outboundTag=$1
    # 域名列表
    local domainList=$2
    # 路由文件名称
    local routingName=$3
    # 读取上次安装内容
    if [[ -f "${singBoxConfigPath}${routingName}.json" ]]; then
        autoRead singbox_route_history "读取到上次的配置，是否保留？[y/n]:" historyRouteStatus
        if [[ "${historyRouteStatus}" == "y" ]]; then
            local historyRuleSetLines historyRuleSets historyDomainLines historyDomains
            historyRuleSetLines=$(jq -rc '.route.rules[0].rule_set[]?' "${singBoxConfigPath}${routingName}.json") || return 1
            historyRuleSets=$(printf '%s\n' "${historyRuleSetLines}" | awk -F "[_]" '{print $2}' | paste -sd ',')
            historyDomainLines=$(jq -rc '.route.rules[0].domain[]?,.route.rules[0].domain_suffix[]?' "${singBoxConfigPath}${routingName}.json") || return 1
            historyDomains=$(printf '%s\n' "${historyDomainLines}" | paste -sd ',')
            domainList="${domainList},${historyRuleSets}"
            domainList="${domainList},${historyDomains}"
        fi

    fi
    local rules=
    rules=$(initSingBoxRules "${domainList}" "${routingName}") || return 1
    local domainRules suffixRules ruleSet ruleSetTag
    splitSingBoxRules "${rules}" domainRules suffixRules ruleSet ruleSetTag || return 1
    if [[ -n "${singBoxConfigPath}" ]]; then
        local routeAction='"outbound": "'"${outboundTag}"'"'
        if [[ "${outboundTag}" == *block* ]]; then
            routeAction='"action": "reject"'
        fi
        writeRoutingJsonConfig "${singBoxConfigPath}${routingName}.json" <<EOF || return 1
{
  "route": {
    "rules": [
      {
        "rule_set":${ruleSetTag},
        "domain":${domainRules},
        "domain_suffix":${suffixRules},
        ${routeAction}
      }
    ],
    "rule_set":${ruleSet}
  }
}
EOF
        updateRoutingJsonConfig "${singBoxConfigPath}${routingName}.json" 'if .route.rule_set == [] then del(.route.rule_set) else . end | (.route.rules[] |= with_entries(select((.value | if type == "array" then length > 0 else true end))))' || return 1
    fi

}


# 移除 sing-box 路由规则
removeSingBoxRouteRule() {
    local outboundTag=$1
    if [[ -f "${singBoxConfigPath}${outboundTag}_route.json" ]]; then
        updateRoutingJsonConfig "${singBoxConfigPath}${outboundTag}_route.json" 'del(.route.rules[] | select(.outbound == $outboundTag or .action == "reject"))' --arg outboundTag "${outboundTag}" || return 1
    fi
}


# 添加 sing-box 出站
addSingBoxOutbound() {
    local tag=$1
    local type="ipv4"
    local detour=${2:-}
    local resolverTag="padm-local"
    if [[ "${tag}" == *IPv6* ]]; then
        type=ipv6
    fi
    if [[ -n "${detour}" ]]; then
        writeRoutingJsonConfig "${singBoxConfigPath}${tag}.json" <<EOF || return 1
{
     "outbounds": [
        {
             "type": "direct",
             "tag": "${tag}",
             "detour": "${detour}",
             "domain_resolver": {
                 "server": "${resolverTag}",
                 "strategy": "${type}_only"
             }
        }
    ]
}
EOF
    elif [[ "${tag}" == *direct* ]]; then

        writeRoutingJsonConfig "${singBoxConfigPath}${tag}.json" <<EOF || return 1
{
     "outbounds": [
        {
             "type": "direct",
             "tag": "${tag}"
        }
    ]
}
EOF
    elif [[ "${tag}" == *block* ]]; then
        return 0
    else
        writeRoutingJsonConfig "${singBoxConfigPath}${tag}.json" <<EOF || return 1
{
     "outbounds": [
        {
             "type": "direct",
             "tag": "${tag}",
             "domain_resolver": {
                 "server": "${resolverTag}",
                 "strategy": "${type}_only"
             }
        }
    ]
}
EOF
    fi
}


# 添加 Xray-core 出站
addXrayOutbound() {
    local tag=$1
    local domainStrategy=
    local xrayConfigPath="${configPath:-/etc/padm/xray/conf/}"

    mkdir -p "${xrayConfigPath}" >/dev/null 2>&1

    if [[ "${tag}" == *IPv4* ]]; then
        domainStrategy="ForceIPv4"
    elif [[ "${tag}" == *IPv6* ]]; then
        domainStrategy="ForceIPv6"
    fi

    if [[ -n "${domainStrategy}" ]]; then
        writeRoutingJsonConfig "${xrayConfigPath}${tag}.json" <<EOF || return 1
{
    "outbounds":[
        {
            "protocol":"freedom",
            "settings":{
                "domainStrategy":"${domainStrategy}"
            },
            "tag":"${tag}"
        }
    ]
}
EOF
    fi
    # direct
    if [[ "${tag}" == *direct* ]]; then
        writeRoutingJsonConfig "${xrayConfigPath}${tag}.json" <<EOF || return 1
{
    "outbounds":[
        {
            "protocol":"freedom",
            "settings": {
                "domainStrategy":"UseIP"
            },
            "tag":"${tag}"
        }
    ]
}
EOF
    fi
    # blackhole
    if [[ "${tag}" == *blackhole* ]]; then
        writeRoutingJsonConfig "${xrayConfigPath}${tag}.json" <<EOF || return 1
{
    "outbounds":[
        {
            "protocol":"blackhole",
            "tag":"${tag}"
        }
    ]
}
EOF
    fi
    # socks5 outbound
    if [[ "${tag}" == *socks5* ]]; then
        writeRoutingJsonConfig "${xrayConfigPath}${tag}.json" <<EOF || return 1
{
  "outbounds": [
    {
      "protocol": "socks",
      "tag": "${tag}",
      "settings": {
        "servers": [
          {
            "address": "${socks5RoutingOutboundIP}",
            "port": ${socks5RoutingOutboundPort},
            "users": [
              {
                "user": "${socks5RoutingOutboundUserName}",
                "pass": "${socks5RoutingOutboundPassword}"
              }
            ]
          }
        ]
      }
    }
  ]
}
EOF
    fi
    if [[ "${tag}" == *wireguard_out_IPv4* ]]; then
        writeRoutingJsonConfig "${xrayConfigPath}${tag}.json" <<EOF || return 1
{
  "outbounds": [
    {
      "protocol": "wireguard",
      "settings": {
        "secretKey": "${secretKeyWarpReg}",
        "address": [
          "${address}"
        ],
        "peers": [
          {
            "publicKey": "${publicKeyWarpReg}",
            "allowedIPs": [
              "0.0.0.0/0",
              "::/0"
            ],
            "endpoint": "162.159.192.1:2408"
          }
        ],
        "reserved": ${reservedWarpReg},
        "mtu": 1280
      },
      "tag": "${tag}"
    }
  ]
}
EOF
    fi
    if [[ "${tag}" == *wireguard_out_IPv6* ]]; then
        writeRoutingJsonConfig "${xrayConfigPath}${tag}.json" <<EOF || return 1
{
  "outbounds": [
    {
      "protocol": "wireguard",
      "settings": {
        "secretKey": "${secretKeyWarpReg}",
        "address": [
          "${address}"
        ],
        "peers": [
          {
            "publicKey": "${publicKeyWarpReg}",
            "allowedIPs": [
              "0.0.0.0/0",
              "::/0"
            ],
            "endpoint": "162.159.192.1:2408"
          }
        ],
        "reserved": ${reservedWarpReg},
        "mtu": 1280
      },
      "tag": "${tag}"
    }
  ]
}
EOF
    fi
    if [[ "${tag}" == *vmess-out* ]]; then
        writeRoutingJsonConfig "${xrayConfigPath}${tag}.json" <<EOF || return 1
{
  "outbounds": [
    {
      "tag": "${tag}",
      "protocol": "vmess",
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {},
        "wsSettings": {
          "path": "${setVMessWSTLSPath}"
        }
      },
      "mux": {
        "enabled": true,
        "concurrency": 8
      },
      "settings": {
        "vnext": [
          {
            "address": "${setVMessWSTLSAddress}",
            "port": "${setVMessWSTLSPort}",
            "users": [
              {
                "id": "${setVMessWSTLSUUID}",
                "security": "auto",
                "alterId": 0
              }
            ]
          }
        ]
      }
    }
  ]
}
EOF
    fi
}


# 删除 Xray-core 出站
removeXrayOutbound() {
    local tag=$1
    local xrayConfigPath="${configPath:-/etc/padm/xray/conf/}"
    if [[ -f "${xrayConfigPath}${tag}.json" ]]; then
        rm "${xrayConfigPath}${tag}.json" >/dev/null 2>&1
    fi
}

# 移除 sing-box 配置
removeSingBoxConfig() {

    local tag=$1
    if [[ -f "${singBoxConfigPath}${tag}.json" ]]; then
        rm "${singBoxConfigPath}${tag}.json"
    fi
}


# 初始化 WARP 出站信息
addSingBoxWireGuardEndpoints() {
    local type=$1

    readConfigWarpReg

    writeRoutingJsonConfig "${singBoxConfigPath}wireguard_endpoints_${type}.json" <<EOF || return 1
{
     "endpoints": [
        {
            "type": "wireguard",
            "tag": "wireguard_endpoints_${type}",
            "address": [
                "${address}"
            ],
            "private_key": "${secretKeyWarpReg}",
            "peers": [
                {
                  "address": "162.159.192.1",
                  "port": 2408,
                  "public_key": "${publicKeyWarpReg}",
                  "reserved":${reservedWarpReg},
                  "allowed_ips": ["0.0.0.0/0","::/0"]
                }
            ]
        }
    ]
}
EOF
}


# 初始化 sing-box Hysteria2 配置
initSingBoxHysteria2Config() {
    progressCard "${1:-}" "初始化 Hysteria2 配置"

    initHysteriaPort
    initHysteria2Network

    local targetPath="${singBoxConfigPath:-/etc/padm/sing-box/conf/config/}hysteria2.json"
    writeRoutingJsonConfig "${targetPath}" <<EOF || return 1
{
    "inbounds": [
        {
            "type": "hysteria2",
            "listen": "::",
            "listen_port": ${hysteriaPort},
            "users": $(initXrayClients 6),
            "up_mbps":${hysteria2ClientDownloadSpeed},
            "down_mbps":${hysteria2ClientUploadSpeed},
            "tls": {
                "enabled": true,
                "server_name":"${currentHost}",
                "alpn": [
                    "h3"
                ],
                "certificate_path": "/etc/padm/tls/${currentHost}.crt",
                "key_path": "/etc/padm/tls/${currentHost}.key"
            }
        }
    ]
}
EOF
}


# sing-box TUIC 安装
singBoxTuicInstall() {
    if ! currentProtocolHasAny 0 1 2 3 4 5 6 9 10; then
        errorCard "由于需要依赖证书，如安装 Tuic，请先安装带有 TLS 标识协议"
        exit 0
    fi

    totalProgress=5
    installSingBox 1
    selectCustomInstallType=",9,"
    initSingBoxConfig custom 2 true || return 1
    installSingBoxService 3
    reloadCore || return 1
    showAccounts 4
}


# sing-box Hysteria2 安装
singBoxHysteria2Install() {
    if ! currentProtocolHasAny 0 1 2 3 4 5 6 9 10; then
        errorCard "由于需要依赖证书，如安装 Hysteria2，请先安装带有 TLS 标识协议"
        exit 0
    fi

    totalProgress=5
    installSingBox 1
    selectCustomInstallType=",6,"
    initSingBoxConfig custom 2 true || return 1
    installSingBoxService 3
    reloadCore || return 1
    showAccounts 4
}


singBoxConfigShardDir() {
    local configDir="${singBoxConfigPath:-/etc/padm/sing-box/conf/config/}"

    configDir="${configDir%/}/"
    printf '%s\n' "${configDir}"
}

singBoxConfigConfDir() {
    local configDir confDir
    configDir=$(singBoxConfigShardDir)
    confDir="$(dirname -- "${configDir%/}")"
    printf '%s\n' "${confDir}"
}

singBoxMergedConfigFile() {
    printf '%s/config.json\n' "$(singBoxConfigConfDir)"
}

singBoxMergeConfigToTemp() {
    local resultVar=$1
    local binary="${2:-${PADM_SINGBOX_BINARY:-/etc/padm/sing-box/sing-box}}"
    local logFile="${3:-/dev/null}"
    local configDir confDir outputFile mergedTmpFile tmpName

    configDir=$(singBoxConfigShardDir)
    confDir=$(singBoxConfigConfDir)
    outputFile=$(singBoxMergedConfigFile)

    padmCreateTempFileForTarget mergedTmpFile "${outputFile}" merge || return 1
    tmpName=$(basename -- "${mergedTmpFile}")
    rm -f "${mergedTmpFile}" >/dev/null 2>&1 || { padmRemoveCleanupPath "${mergedTmpFile}"; return 1; }

    if ! "${binary}" merge "${tmpName}" -C "${configDir}" -D "${confDir}/" >"${logFile}" 2>&1 || [[ ! -s "${mergedTmpFile}" ]]; then
        padmRemoveCleanupPath "${mergedTmpFile}"
        return 1
    fi
    printf -v "${resultVar}" '%s' "${mergedTmpFile}"
}

singBoxMergeConfigForValidation() {
    local binary="${1:-${PADM_SINGBOX_BINARY:-/etc/padm/sing-box/sing-box}}"
    local logFile="${2:-/dev/null}"
    local checkMode="${3:-}"
    local tmpFile

    singBoxMergeConfigToTemp tmpFile "${binary}" "${logFile}" || return 1
    if [[ "${checkMode}" == "check" ]]; then
        if ! "${binary}" check -c "${tmpFile}" >>"${logFile}" 2>&1; then
            padmRemoveCleanupPath "${tmpFile}"
            return 1
        fi
    fi
    padmRemoveCleanupPath "${tmpFile}"
}

# 合并 sing-box 配置
singBoxMergeConfig() {
    local binary="${PADM_SINGBOX_BINARY:-/etc/padm/sing-box/sing-box}"
    local outputFile tmpFile

    outputFile=$(singBoxMergedConfigFile)
    singBoxMergeConfigToTemp tmpFile "${binary}" /dev/null || return 1
    commitGeneratedFile "${tmpFile}" "${outputFile}" 644 || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}


# 初始化 sing-box 端口
initSingBoxPort() {
    local port=$1
    local promptHistory=${2:-true}
    if [[ -n "${port}" && "${promptHistory}" != "true" ]]; then
        if ((port >= 1 && port <= 65535)); then
            allowPort "${port}" || return 1
            allowPort "${port}" "udp" || return 1
            echo "${port}"
            return
        else
            errorCard "端口输入错误"
            return 1
        fi
    fi
    if [[ -n "${port}" && -z "${lastInstallationConfig}" ]]; then
        autoRead singbox_history_port "读取到上次使用的端口 [${port}]，是否使用？[y/n]:" historyPort
        if [[ "${historyPort}" != "y" ]]; then
            port=
        else
            echo "${port}"
        fi
    elif [[ -n "${port}" && -n "${lastInstallationConfig}" ]]; then
        echo "${port}"
    fi
    if [[ -z "${port}" ]]; then
        autoRead singbox_custom_port "请输入自定义端口[需合法]，端口不可重复，[回车]随机端口:" port
        if [[ -z "${port}" ]]; then
            port=$((RANDOM % 50001 + 10000))
        fi
        if ((port >= 1 && port <= 65535)); then
            allowPort "${port}" || return 1
            allowPort "${port}" "udp" || return 1
            echo "${port}"
        else
            errorCard "端口输入错误"
            return 1
        fi
    fi
}

readSingBoxPortResult() {
    local -n resultRef=$1
    local port=${2:-}
    local promptHistory=${3:-true}
    local output

    resultRef=()
    output=$(initSingBoxPort "${port}" "${promptHistory}") || return 1
    mapfile -t resultRef <<<"${output}"
    [[ -n "${resultRef[-1]:-}" ]] || return 1
}
