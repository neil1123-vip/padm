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
initSingBoxLocalDNSConfig() {
    local mode=${1:-ensure}
    local configDir targetPath file resolverState
    local -a configFiles=()

    case "${mode}" in
    ensure|check) ;;
    *) return 2 ;;
    esac
    configDir=$(coreSafeConfigDir "${singBoxConfigPath:-/etc/padm/sing-box/conf/config/}") || return 1
    targetPath="${configDir}dns.json"
    for file in "${configDir}"*.json; do
        [[ -f "${file}" ]] && configFiles+=("${file}")
    done
    if [[ "${#configFiles[@]}" -gt 0 ]]; then
        if ! resolverState=$(jq -sr '
            def padm_resolvers:
                .[] | .. | objects | .dns? | select(type == "object") |
                .servers? | select(type == "array") | .[]? |
                select(type == "object" and .tag? == "padm-local");
            [padm_resolvers] as $resolvers |
            if any($resolvers[]; .type? != "local") then "conflict"
            elif ($resolvers | length) > 1 then "duplicate"
            elif ($resolvers | length) == 1 then "present"
            else "missing"
            end
        ' "${configFiles[@]}"); then
            errorCard "sing-box DNS 配置解析失败，已保留旧配置"
            return 1
        fi
        case "${resolverState}" in
        present) return 0 ;;
        conflict)
            errorCard "padm-local DNS resolver 已存在但不是 local 类型"
            return 1
            ;;
        duplicate)
            errorCard "检测到重复的 padm-local DNS resolver"
            return 1
            ;;
        missing)
            if [[ "${mode}" == "check" ]]; then
                if jq -s -e '
                    any(.[] | .. | objects;
                        ((.domain_resolver? | type) == "object" and .domain_resolver.server? == "padm-local") or
                        ((.route? | type) == "object" and
                            (.route.default_domain_resolver? == "padm-local" or
                             any(.route.rules[]? | recurse(.rules[]?); .server? == "padm-local"))) or
                        ((.dns? | type) == "object" and
                            (.dns.final? == "padm-local" or
                             any(.dns.rules[]? | recurse(.rules[]?); .server? == "padm-local")))
                    )
                ' "${configFiles[@]}" >/dev/null; then
                    errorCard "配置引用了不存在的 padm-local DNS resolver"
                    return 1
                fi
                return 0
            fi
            ;;
        esac
    elif [[ "${mode}" == "check" ]]; then
        return 0
    fi

    if [[ ! -f "${targetPath}" ]]; then
        writeRoutingJsonConfig "${targetPath}" <<'EOF' || return 1
{
    "dns": {
        "servers": [
            {
                "tag": "padm-local",
                "type": "local"
            }
        ]
    }
}
EOF
        return 0
    fi

    updateRoutingJsonConfig "${targetPath}" '
        if type != "object" then
            error("sing-box DNS 配置不是对象")
        elif (.dns? | type) == "null" then
            .dns = {servers: [{tag: "padm-local", type: "local"}]}
        elif (.dns | type) != "object" then
            error("sing-box DNS 配置不是对象")
        elif (.dns.servers? | type) == "null" then
            .dns.servers = [{tag: "padm-local", type: "local"}]
        elif (.dns.servers | type) != "array" then
            error("sing-box DNS servers 不是数组")
        else
            .dns.servers += [{tag: "padm-local", type: "local"}]
        end
    '
}

addSingBoxOutbound() {
    local tag=$1
    local type="ipv4"
    local detour=${2:-}
    local resolverTag="padm-local"
    if [[ -n "${detour}" || ( "${tag}" != *direct* && "${tag}" != *block* ) ]]; then
        initSingBoxLocalDNSConfig || return 1
    fi
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
    local xrayConfigDir="${xrayConfigPath%/}"

    if ! padmIsSafeAbsolutePath "${xrayConfigDir}"; then
        padmShowUnsafePathError "配置 Xray 出站"
        return 1
    fi
    if [[ -e "${xrayConfigDir}" ]]; then
        [[ -d "${xrayConfigDir}" ]] || {
            errorCard "Xray 出站配置目录异常"
            return 1
        }
    elif ! padmEnsureSafeDirectory "${xrayConfigDir}"; then
        errorCard "Xray 出站配置目录创建失败"
        return 1
    fi

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
        local socks5Outbound
        socks5Outbound=$(jq -n \
          --arg tag "${tag}" \
          --arg address "${socks5RoutingOutboundIP}" \
          --argjson port "${socks5RoutingOutboundPort}" \
          --arg user "${socks5RoutingOutboundUserName}" \
          --arg pass "${socks5RoutingOutboundPassword}" \
          '{outbounds:[{protocol:"socks", tag:$tag, settings:{servers:[{address:$address, port:$port, users:[{user:$user, pass:$pass}]}]}}]}') || return 1
        writeRoutingJsonConfig "${xrayConfigPath}${tag}.json" <<<"${socks5Outbound}" || return 1
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
}


# 删除 Xray-core 出站
removeXrayOutbound() {
    local tag=$1
    local fileName="${tag}"
    local targetPath
    local xrayConfigPath="${configPath:-/etc/padm/xray/conf/}"

    [[ -n "${fileName}" ]] || return 1
    [[ "${fileName}" == *.json ]] || fileName="${fileName}.json"
    targetPath=$(padmManagedFilePath "${xrayConfigPath}" "${fileName}") || return 1
    removeManagedFileIfPresent "${targetPath}"
}

# 移除 sing-box 配置
removeSingBoxConfig() {

    local tag=$1
    local fileName="${tag}"
    local targetPath

    [[ -n "${fileName}" ]] || return 1
    [[ "${fileName}" == *.json ]] || fileName="${fileName}.json"
    targetPath=$(padmManagedFilePath "${singBoxConfigPath}" "${fileName}") || return 1
    removeManagedFileIfPresent "${targetPath}"
}


# 初始化 WARP 出站信息
addSingBoxWireGuardEndpoints() {
    local type=$1
    local addressValue="${address:-}"

    readConfigWarpReg || return 1
    if [[ -z "${addressValue}" ]]; then
        if [[ "${type}" == "IPv6" && -n "${addressWarpReg:-}" ]]; then
            addressValue="${addressWarpReg}"
        else
            addressValue="172.16.0.2/32"
        fi
    fi

    writeRoutingJsonConfig "${singBoxConfigPath}wireguard_endpoints_${type}.json" <<EOF || return 1
{
     "endpoints": [
        {
            "type": "wireguard",
            "tag": "wireguard_endpoints_${type}",
            "address": [
                "${addressValue}"
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


# 检查 sing-box TLS 入站是否已有可复用的本机证书。
singBoxLocalCertificateAvailable() {
    local tlsDir

    collectTLSProfile || return 1
    [[ -n "${tlsCertDomain:-}" ]] || return 1
    tlsDir=$(tlsManagedDir) || return 1
    tlsCertificatePairUsable "${tlsDir}" "${tlsCertDomain}"
}

singBoxInstallLocalTLSCertificate() {
    local nginxWasRunning=false xrayWasRunning=false singBoxWasRunning=false
    local selectCoreType=
    local dnsAPIStatus dnsAPIType cfAPIToken cfZoneID aliKey aliSecret sslIPv6

    readInstallTLSDomain domain || return 1
    installAcmeTool || return 1
    nginxRunning && nginxWasRunning=true
    xrayRunning && xrayWasRunning=true
    singBoxRunning && singBoxWasRunning=true
    statusCard "本机 TLS 证书" \
        "Reality 不使用本机证书，现有核心配置保持不变" \
        "先申请或复用证书，成功后再继续安装"

    # 只借用域名和 ACME 流程，避免 initTLSNginxConfig 触发 Xray 端口改动。
    if ! initTLSNginxConfig 1 "${domain}"; then
        restoreServicesAfterTLSRenewal "${nginxWasRunning}" "${xrayWasRunning}" "${singBoxWasRunning}" ||
            errorCard "TLS 初始化失败，且服务恢复失败"
        return 1
    fi

    if ! installTLS 2; then
        restoreServicesAfterTLSRenewal "${nginxWasRunning}" "${xrayWasRunning}" "${singBoxWasRunning}" ||
            errorCard "TLS 证书申请失败，且服务恢复失败"
        return 1
    fi
    if ! singBoxLocalCertificateAvailable; then
        errorCard "TLS 证书申请完成但文件校验失败" "请检查 /etc/padm/tls/"
        restoreServicesAfterTLSRenewal "${nginxWasRunning}" "${xrayWasRunning}" "${singBoxWasRunning}" ||
            errorCard "TLS 证书文件校验失败，且服务恢复失败"
        return 1
    fi
    if ! installCronTLS 3; then
        restoreServicesAfterTLSRenewal "${nginxWasRunning}" "${xrayWasRunning}" "${singBoxWasRunning}" ||
            errorCard "TLS 续签任务配置失败，且服务恢复失败"
        return 1
    fi
    restoreServicesAfterTLSRenewal "${nginxWasRunning}" "${xrayWasRunning}" "${singBoxWasRunning}" || {
        errorCard "TLS 证书已准备，但服务恢复失败"
        return 1
    }
    return 0
}

singBoxEnsureTLSDependency() {
    local protocolName=$1
    local allowCertificateInstall=${2:-false}
    local confirm

    if protocolSelectionNeedsCertificate "${currentInstallProtocolType:-}" ||
        singBoxLocalCertificateAvailable; then
        return 0
    fi

    if [[ "${allowCertificateInstall}" == "true" ]] &&
        protocolSelectionOnlyRealityNoDomain "${currentInstallProtocolType:-}"; then
        statusCard "${protocolName} 证书依赖" \
            "当前仅有 Reality；将直接申请本机 TLS 证书，现有 Reality 配置保持不变"
        autoConfirm singbox_tls_certificate "是否直接申请本机 TLS 证书？" y confirm
        if [[ "${confirm}" != "y" ]]; then
            coreCancelledStatusCard "${protocolName} 安装未开始" "Reality 配置和证书均未修改"
            return 1
        fi
        singBoxInstallLocalTLSCertificate || return 1
        return 0
    fi

    errorCard "${protocolName} 需要本机 TLS 证书" \
        "当前配置没有可复用的证书；请先安装带有 TLS 标识的协议或准备证书后再试" \
        "Reality target/SNI 是外部伪装目标，不是本机证书"
    return 1
}

# 辅助协议只增量写入 sing-box，不切换或清理主核心。
singBoxProtocolInstallApply() {
    singBoxEnsureTLSDependency "$1" || return 1

    totalProgress=5
    installSingBox 1 || return 1
    initSingBoxConfig custom 2 true || return 1
    installSingBoxService 3 || return 1
    serviceQueueRestart sing-box
    serviceQueueApply || return 1
    showAccounts 4 || return 1
    if declare -F subscriptionNotifyControllerRefresh >/dev/null 2>&1; then
        subscriptionNotifyControllerRefresh || true
    fi
    return 0
}

singBoxProtocolInstall() {
    local protocolId=$1 protocolName configFile reuseParameters=
    shift
    local selectCustomInstallType=",${protocolId},"
    local singBoxHysteria2CredentialMode=false PADM_INSTALL_CLIENTS_PREPARED=true
    local AUTO_UUID="${AUTO_UUID:-}" AUTO_USER="${AUTO_USER:-}" AUTO_PORT="${AUTO_PORT:-}"
    local currentClients="${currentClients:-}" currentUUID="${currentUUID:-}" lastInstallationConfig=
    local singBoxConfigPath hysteriaPort tuicPort tuicAlgorithm tuicAuthTimeout tuicHeartbeat tuicZeroRttHandshake
    local hysteria2BandwidthMode hysteria2ClientDownloadSpeed hysteria2ClientUploadSpeed
    local hysteria2ObfsType hysteria2ObfsPassword hysteria2Masquerade
    local -a protocolPort=()
    case "${protocolId}" in
    3) singBoxHysteria2CredentialMode=true ;;
    31) ;;
    *) return 1 ;;
    esac
    protocolName=$(protocolCapabilityMeta "${protocolId}" name) || return 1
    configFile=$(protocolCapabilityMeta "${protocolId}" config_file) || return 1
    configFile=$(singBoxTemplateConfigFile "${configFile}") || return 1

    # 重装优先保留本协议用户，避免主核心用户覆盖独立密码或独立账号。
    if [[ -f "${configFile}" ]]; then
        currentClients=$(jq -ce --arg id "${protocolId}" '
            .inbounds[0].users | select(type == "array" and length > 0 and all(.[];
                type == "object" and (.name | type == "string" and length > 0) and
                (.password | type == "string" and length > 0) and
                ($id != "31" or (.uuid | type == "string" and length > 0))
            ))
        ' "${configFile}") || {
            errorCard "${protocolName} 现有用户配置读取失败，已取消重装"
            return 1
        }
        currentUUID=
    fi
    # 每次重读磁盘，采集仅保存在本次作用域，取消或失败不污染后续重装。
    singBoxConfigPath="$(singBoxTemplateConfigDir)/" || return 1
    readSingBoxConfig || return 1
    if [[ -f "${configFile}" ]]; then
        while true; do
            if [[ -n "${AUTO_INSTALL:-}" ]]; then
                reuseParameters=${AUTO_REUSE_LAST:-yes}
            else
                menuReadChoice reuse_last "是否直接复用 ${protocolName} 的全部用户、端口和网络参数？[Y/n，回车保留；n 逐项调整]:" reuseParameters true || return 1
            fi
            case "${reuseParameters}" in
            "" | y | Y | yes | YES | Yes | true | TRUE | True | 1)
                lastInstallationConfig=true
                break
                ;;
            n | N | no | NO | No | false | FALSE | False | 0)
                if [[ -n "${AUTO_INSTALL:-}" ]]; then
                    currentClients=
                    currentUUID=
                    case "${protocolId}" in
                    3)
                        hysteriaPort= hysteria2BandwidthMode= hysteria2ClientDownloadSpeed= hysteria2ClientUploadSpeed=
                        hysteria2ObfsType= hysteria2ObfsPassword= hysteria2Masquerade=
                        ;;
                    31)
                        tuicPort= tuicAlgorithm= tuicAuthTimeout= tuicHeartbeat= tuicZeroRttHandshake=
                        ;;
                    esac
                fi
                break
                ;;
            *)
                errorCard "请输入 y 复用全部参数，或 n 逐项调整"
                [[ -z "${AUTO_INSTALL:-}" ]] || return 1
                ;;
            esac
        done
    fi
    coreTemplateCollectInitialClients sing-box "${singBoxHysteria2CredentialMode}" true || return 1
    case "${protocolId}" in
    3)
        readSingBoxProtocolPort protocolPort 3 "${hysteriaPort}" true || return 1
        initHysteria2Network true || return 1
        ;;
    31)
        readSingBoxProtocolPort protocolPort 31 "${tuicPort}" true || return 1
        initTuicProtocol || return 1
        ;;
    esac
    # 本协议参数复用不替代独立的证书、域名确认。
    lastInstallationConfig=
    singBoxEnsureTLSDependency "${protocolName}" true || return 1
    AUTO_PORT=${protocolPort[-1]}
    lastInstallationConfig=true
    coreInstallConfigTransaction sing-box padmRunPortAllowTransaction singBoxProtocolInstallApply "${protocolName}" "$@"
}

singBoxTuicInstall() {
    singBoxProtocolInstall 31 "$@"
}

singBoxHysteria2Install() {
    singBoxProtocolInstall 3 "$@"
}

singBoxConfigShardDir() {
    local configDir="${singBoxConfigPath:-${PADM_SINGBOX_CONFIG_DIR:-/etc/padm/sing-box/conf/config/}}"

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

    initSingBoxLocalDNSConfig check || return 1
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
    local outputFile tmpFile statsConfig

    outputFile=$(singBoxMergedConfigFile)
    if declare -F singBoxV2rayApiSupported >/dev/null 2>&1 &&
        ! singBoxV2rayApiSupported "${binary}"; then
        statsConfig="$(singBoxConfigShardDir)14_stats_api.json"
        if [[ -e "${statsConfig}" ]]; then
            removeManagedFileIfPresent "${statsConfig}" || return 1
        fi
    fi
    singBoxMergeConfigToTemp tmpFile "${binary}" /dev/null || return 1
    if [[ "${1:-}" == check ]] && ! "${binary}" check -c "${tmpFile}" >"$(padmTmpFilePath padm-sing-box-start-test.log)" 2>&1; then
        padmRemoveCleanupPath "${tmpFile}"
        return 1
    fi
    commitGeneratedFile "${tmpFile}" "${outputFile}" 644 || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}


# 只登记本次模板实际监听的传输，允许 TCP 与 UDP 使用相同端口。
singBoxInstallPortAvailable() {
    local port=$((10#$1)) transport=$2 type
    declare -p singBoxInstallListeners >/dev/null 2>&1 || return 0
    for type in tcp udp; do
        [[ "${transport}" == "${type}" || "${transport}" == tcp+udp ]] || continue
        if [[ -n "${singBoxInstallListeners[${type}:${port}]:-}" ]]; then
            errorCard "${port}/${type} 已用于本次安装的其他监听，请选择不同端口"
            return 1
        fi
    done
}

readSingBoxProtocolPort() {
    local -n protocolPortsRef=$1
    local protocolId=$2 historyPort=${3:-} inputsOnly=${4:-false}
    local transport=tcp promptHistory=true promptKey=singbox_custom_port realityId= stream= type
    case "${protocolId}" in
    1) realityId=1; stream=vision; promptKey=reality_subport ;;
    26) realityId=26; promptKey=reality_grpc_subport ;;
    3 | 31) transport=udp ;;
    5 | 30) transport=tcp+udp ;;
    esac
    if [[ "${inputsOnly}" != true && -n "${PADM_INSTALL_SINGBOX_PORTS[${protocolId}]:-}" ]]; then
        historyPort=${PADM_INSTALL_SINGBOX_PORTS[${protocolId}]}
        promptHistory=false
    fi
    readSingBoxPortResult "$1" "${historyPort}" "${promptHistory}" "${transport}" "${promptKey}" "${realityId}" "${stream}" "${inputsOnly}" || return 1
    if declare -p singBoxInstallListeners >/dev/null 2>&1; then
        for type in tcp udp; do
            [[ "${transport}" == "${type}" || "${transport}" == tcp+udp ]] || continue
            singBoxInstallListeners["${type}:${protocolPortsRef[-1]}"]=${protocolId}
        done
    fi
}

# 完整安装先采集参数，模板阶段只消费本次结果并校验实际核心版本。
prepareSingBoxInstallInputs() {
    local mode=custom entry protocolId portVar
    local -a ports=()
    local -A singBoxInstallListeners=()
    [[ -n "${selectCustomInstallType:-}" ]] || mode=all
    if protocolSelectionIncludes "${selectCustomInstallType:-}" 23 "${mode}"; then
        singBoxInstallListeners[tcp:31306]=httpupgrade
    fi
    for entry in \
        27:singBoxVLESSVisionPort 21:singBoxVLESSWSPort 22:singBoxVMessWSPort \
        1:singBoxVLESSRealityVisionPort 26:singBoxVLESSRealityGRPCPort 3:singBoxHysteria2Port \
        28:singBoxTrojanPort 30:singBoxShadowsocksPort 31:singBoxTuicPort \
        5:singBoxNaivePort 23:singBoxVMessHTTPUpgradePort 4:singBoxAnyTLSPort; do
        protocolId=${entry%%:*}
        portVar=${entry#*:}
        protocolSelectionIncludes "${selectCustomInstallType:-}" "${protocolId}" "${mode}" || continue
        statusCard "安装参数" "$(protocolCapabilityMeta "${protocolId}" name)"
        readSingBoxProtocolPort ports "${protocolId}" "${!portVar:-}" true || return 1
        PADM_INSTALL_SINGBOX_PORTS[${protocolId}]=${ports[-1]}
        case "${protocolId}" in
        3)
            initHysteria2Network true || return 1
            PADM_INSTALL_HY2_INPUTS_PREPARED=true
            ;;
        31)
            initTuicProtocol || return 1
            PADM_INSTALL_TUIC_INPUTS_PREPARED=true
            ;;
        esac
    done
}

# 初始化 sing-box 端口
initSingBoxPort() {
    local port=$1
    local promptHistory=${2:-true}
    local transport=${3:-tcp+udp}
    local promptKey=${4:-singbox_custom_port}
    local realityProtocolId=${5:-}
    local streamProtocol=${6:-}
    local inputsOnly=${7:-false}
    local selection=${selectCustomInstallType:-}
    local historyPort=${port} portInput=
    local openPort=false
    local AUTO_PORT=${AUTO_PORT:-}
    local coexistStatus=1 singleReality=false realityLabel=Reality
    case "${transport}" in
    tcp | udp | tcp+udp) ;;
    *) return 1 ;;
    esac
    if [[ -n "${realityProtocolId}" ]]; then
        [[ "${realityProtocolId}" == "26" ]] && realityLabel="Reality gRPC"
        protocolSelectionIsExactly "${selection}" "${realityProtocolId}" && singleReality=true
    fi
    # 公共端口仅用于单选入口，不能覆盖共存内部端口或重复套用到多协议。
    if ! protocolSelectionIsExactly "${selection}" "${selection//,/}" ||
        [[ -n "${realityProtocolId}" && "${singleReality}" != "true" ]]; then
        AUTO_PORT=
    fi
    if [[ -n "${realityProtocolId}" && -n "${streamProtocol}" ]]; then
        if resolveRealityInstallCoexistPort port "${streamProtocol}" "${realityLabel}"; then
            coexistStatus=0
            promptHistory=false
        else
            coexistStatus=$?
            [[ "${coexistStatus}" == "2" ]] && return 1
        fi
    fi
    if [[ "${promptHistory}" == true && -n "${port}" && -z "${AUTO_PORT}${AUTO_INSTALL:-}" ]] &&
        ! validPortNumber "${port}"; then
        corePortInputErrorCard
        port=
    fi
    if [[ "${promptHistory}" == "true" && -n "${AUTO_PORT}" ]]; then
        port=${AUTO_PORT}
        promptHistory=false
    fi
    if validPortNumber "${port}" && ! singBoxInstallPortAvailable "${port}" "${transport}"; then
        [[ -z "${AUTO_INSTALL:-}${AUTO_PORT}" && "${coexistStatus}" != 0 ]] || return 1
        port=
        promptHistory=true
    fi

    if [[ -n "${port}" && ( "${promptHistory}" != "true" || ( "${singleReality}" == "true" && -n "${AUTO_INSTALL:-}" ) ) ]]; then
        openPort=true
    elif [[ -z "${port}" || -z "${lastInstallationConfig:-}" ]]; then
        local defaultPort=${port} prompt
        if [[ -n "${port}" ]]; then
            prompt="连接端口[回车保留 ${port}]:"
        elif [[ "${singleReality}" == "true" ]]; then
            prompt="Reality 连接端口[回车默认 443]:"
        else
            prompt="自定义端口[端口不可重复，回车随机]:"
        fi
        while true; do
            menuReadChoice "${promptKey}" "${prompt}" portInput true || return 1
            port=${portInput:-${defaultPort}}
            if [[ -z "${port}" ]]; then
                if [[ "${singleReality}" == "true" ]]; then
                    port=443
                else
                    port=$((RANDOM % 50001 + 10000))
                fi
            fi
            if validPortNumber "${port}"; then
                singBoxInstallPortAvailable "${port}" "${transport}" && break
            else
                corePortInputErrorCard
            fi
            [[ -z "${AUTO_INSTALL:-}" ]] || return 1
        done
        [[ "${port}" == "${historyPort}" ]] || openPort=true
    fi

    validPortNumber "${port}" || { corePortInputErrorCard; return 1; }
    singBoxInstallPortAvailable "${port}" "${transport}" || return 1
    port=$((10#${port}))
    if [[ "${inputsOnly}" != true ]]; then
        [[ -z "${realityProtocolId}" ]] || checkPort "${port}" || return 1
        if [[ "${openPort}" == "true" ]]; then
            case "${transport}" in
            tcp+udp) allowPortTcpAndUdp "${port}" || return 1 ;;
            tcp) allowPort "${port}" || return 1 ;;
            udp) allowPort "${port}" udp || return 1 ;;
            esac
        fi
    fi
    printf '%s\n' "${port}"
}

readSingBoxPortResult() {
    local -n resultRef=$1
    local port=${2:-}
    local promptHistory=${3:-true}
    local transport=${4:-tcp+udp}
    local promptKey=${5:-singbox_custom_port}
    local realityProtocolId=${6:-}
    local streamProtocol=${7:-}
    local inputsOnly=${8:-false}
    local outputFile stateFile beforeState key backend type

    resultRef=()
    if [[ "${inputsOnly}" != true ]]; then
        stateFile=$(padmFirewallStateFile 2>/dev/null || true)
        if [[ -n "${stateFile}" && -f "${stateFile}" ]]; then
            beforeState=$(<"${stateFile}")
        fi
    fi
    padmCreateTmpRootPath outputFile padm-sing-box-port.XXXXXX || return 1
    if ! initSingBoxPort "${port}" "${promptHistory}" "${transport}" "${promptKey}" "${realityProtocolId}" "${streamProtocol}" "${inputsOnly}" >"${outputFile}"; then
        padmRemoveCleanupPath "${outputFile}"
        return 1
    fi
    mapfile -t resultRef <"${outputFile}"
    padmRemoveCleanupPath "${outputFile}" || return 1
    [[ -n "${resultRef[-1]:-}" ]] || return 1
    [[ "${inputsOnly}" != true ]] || return 0
    for backend in ufw firewalld iptables; do
        for type in tcp udp; do
            key="port:${backend}:${type}:${resultRef[-1]}"
            if padmFirewallStateHas "${key}" && ! grep -Fxq -- "${key}" <<<"${beforeState:-}"; then
                padmTrackPortAllowTransactionKey "${key}"
            fi
        done
    done
}
