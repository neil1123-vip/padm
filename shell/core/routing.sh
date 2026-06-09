#!/usr/bin/env bash

# 检查 IPv6、IPv4
checkIPv6() {
    if ! hasIPv6Connectivity; then
        errorCard "不支持ipv6"
        exit 0
    fi
}

# IPv6 分流
ipv6Routing() {
    if [[ -z "${configPath}" ]]; then
        errorCard "未安装，请使用脚本安装"
        menu
        exit 0
    fi

    checkIPv6
    progressCard "1" "IPv6 分流"
    echoContent title "\n┌─ IPv6 分流 ────────────────────────────────────────"
    menuItem 1 "查看已分流域名" "显示当前 IPv6 分流规则"
    menuItem 2 "添加域名" "添加 IPv6 出站分流规则"
    menuDangerItem 3 "设置 IPv6 全局" "删除其他出站并全局走 IPv6"
    menuDangerItem 4 "卸载 IPv6 分流" "移除 IPv6 分流配置"
    menuReturnItem 5 "返回路由与访问控制" "回到上级菜单"
    menuClose
    autoRead ipv6_menu "请选择:" ipv6Status
    if [[ "${ipv6Status}" == "1" ]]; then
        showIPv6Routing
        exit 0
    elif [[ "${ipv6Status}" == "2" ]]; then
        echoContent title "\n┌─ IPv6 分流规则说明 ────────────────────────────────"
        menuLine "请按 README 中的分流说明配置域名或规则"
        menuClose

        autoRead routing_domain_rules "请按照上面示例录入域名:" domainList
        if [[ "${coreInstallType}" == "1" ]]; then
            addXrayRouting IPv6_out outboundTag "${domainList}"
            addXrayOutbound IPv6_out
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            addSingBoxRouteRule "IPv6_out" "${domainList}" "IPv6_route"
            addSingBoxOutbound 01_direct_outbound
            addSingBoxOutbound IPv6_out
            addSingBoxOutbound IPv4_out
        fi

        successCard "添加完毕"

    elif [[ "${ipv6Status}" == "3" ]]; then

        warnCard \
            "会删除所有设置的分流规则" \
            "会删除 IPv6 之外的所有出站规则"
        autoConfirm ipv6_global_confirm "确认设置 IPv6 全局出站？" n IPv6OutStatus

        if [[ "${IPv6OutStatus}" == "y" ]]; then
            if [[ "${coreInstallType}" == "1" ]]; then
                addXrayOutbound IPv6_out
                removeXrayOutbound IPv4_out
                removeXrayOutbound z_direct_outbound
                removeXrayOutbound blackhole_out
                removeXrayOutbound wireguard_out_IPv4
                removeXrayOutbound wireguard_out_IPv6
                removeXrayOutbound socks5_outbound

                rm ${configPath}09_routing.json >/dev/null 2>&1
            fi
            if [[ -n "${singBoxConfigPath}" ]]; then

                removeSingBoxConfig IPv4_out

                removeSingBoxConfig wireguard_endpoints_IPv4_route
                removeSingBoxConfig wireguard_endpoints_IPv6_route
                removeSingBoxConfig wireguard_endpoints_IPv4
                removeSingBoxConfig wireguard_endpoints_IPv6

                removeSingBoxConfig socks5_02_inbound_route

                removeSingBoxConfig IPv6_route

                removeSingBoxConfig 01_direct_outbound

                addSingBoxOutbound IPv6_out

            fi

            successCard "IPv6全局出站设置完毕"
        else

            statusCard "已取消" "未设置 IPv6 全局出站"
            ipv6Routing
            return
        fi

    elif [[ "${ipv6Status}" == "4" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            unInstallRouting IPv6_out outboundTag

            removeXrayOutbound IPv6_out
            addXrayOutbound "z_direct_outbound"
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            removeSingBoxConfig IPv6_out
            removeSingBoxConfig "IPv6_route"
            addSingBoxOutbound "01_direct_outbound"
        fi

        successCard "IPv6分流卸载成功"
    elif [[ "${ipv6Status}" == "5" ]]; then
        routingAccessMenu
        return
    else
        errorCard "选择错误，请重新选择"
        ipv6Routing
        return
    fi

    reloadCore
}

# IPv6 分流规则展示
showIPv6Routing() {
    if [[ "${coreInstallType}" == "1" ]]; then
        if [[ -f "${configPath}09_routing.json" ]]; then
            echoContent yellow "Xray-core："
            jq -r -c '.routing.rules[]|select (.outboundTag=="IPv6_out")|.domain' ${configPath}09_routing.json | jq -r
        elif [[ ! -f "${configPath}09_routing.json" && -f "${configPath}IPv6_out.json" ]]; then
            echoContent yellow "Xray-core"
            successCard "已设置IPv6全局分流"
        else
            statusCard "IPv6 分流" "未安装 IPv6 分流"
        fi

    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}IPv6_route.json" ]]; then
            echoContent yellow "sing-box"
            jq -r -c '.route.rules[]|select (.outbound=="IPv6_out")' "${singBoxConfigPath}IPv6_route.json" | jq -r
        elif [[ ! -f "${singBoxConfigPath}IPv6_route.json" && -f "${singBoxConfigPath}IPv6_out.json" ]]; then
            echoContent yellow "sing-box"
            successCard "已设置IPv6全局分流"
        else
            statusCard "IPv6 分流" "未安装 IPv6 分流"
        fi
    fi
}
# BT 下载管理
btTools() {
    readInstallType
    if [[ -z "${configPath}" ]]; then
        errorCard "未安装，请使用脚本安装"
        menu
        exit 0
    fi

    echoContent title "\n┌─ BT 下载管理 ──────────────────────────────────────"
    menuLine "通过核心协议嗅探识别 bittorrent 后阻断"
    menuLine "只能覆盖可识别流量；加密、混淆或部分 uTP 场景可能绕过"
    menuLine "Xray：协议规则 + 入站 sniffing；sing-box：sniff action + protocol 规则"
    echo
    showBTBlockStatus
    menuItem 1 "启用 BT 阻断" "阻断已识别的 bittorrent 流量"
    menuItem 2 "关闭 BT 阻断" "移除 BT 协议阻断规则"
    menuItem 3 "查看当前状态" "显示 Xray / sing-box 规则状态"
    menuReturnItem 4 "返回路由与访问控制" "回到上级菜单"
    menuClose
    autoRead bt_menu "请选择:" btStatus
    if [[ "${btStatus}" == "1" ]]; then
        installBTBlock
        successCard "已启用 BT 阻断"
    elif [[ "${btStatus}" == "2" ]]; then
        uninstallBTBlock
        successCard "已关闭 BT 阻断"
    elif [[ "${btStatus}" == "3" ]]; then
        showBTBlockStatus
        return
    elif [[ "${btStatus}" == "4" ]]; then
        routingAccessMenu
        return
    else
        errorCard "选择错误，请重新选择"
        btTools
        return
    fi

    reloadCore
}

showBTBlockStatus() {
    local hasStatus=false

    if [[ "${coreInstallType}" == "1" ]]; then
        hasStatus=true
        if hasXrayBTBlockRule; then
            menuLine "Xray-core：已启用 BT 阻断"
        else
            menuLine "Xray-core：未启用 BT 阻断"
        fi
    fi

    if [[ -n "${singBoxConfigPath}" ]]; then
        hasStatus=true
        if hasSingBoxBTBlockRule; then
            menuLine "sing-box：已启用 BT 阻断"
        else
            menuLine "sing-box：未启用 BT 阻断"
        fi
    fi

    if [[ "${hasStatus}" == "false" ]]; then
        menuLine "当前未检测到可管理的 Xray 或 sing-box 配置"
    fi
}

hasXrayBTBlockRule() {
    [[ -f "${configPath}09_routing.json" ]] && jq -e '.routing.rules[]? | select(.outboundTag == "blackhole_out" and (.protocol // [] | index("bittorrent")))' "${configPath}09_routing.json" >/dev/null 2>&1
}

hasSingBoxBTBlockRule() {
    [[ -f "${singBoxConfigPath}bt_block_route.json" ]] && jq -e '.route.rules[]? | select((.action == "reject" or .outbound == "block") and (.protocol // [] | index("bittorrent")))' "${singBoxConfigPath}bt_block_route.json" >/dev/null 2>&1
}

installBTBlock() {
    if [[ "${coreInstallType}" == "1" ]]; then
        addXrayBTBlockRule
        installSniffing
        removeXrayOutbound blackhole_out
        addXrayOutbound blackhole_out
    fi

    if [[ -n "${singBoxConfigPath}" ]]; then
        addSingBoxBTBlockRule
    fi
}

uninstallBTBlock() {
    if [[ "${coreInstallType}" == "1" ]]; then
        unInstallRouting blackhole_out outboundTag bittorrent
    fi

    if [[ -n "${singBoxConfigPath}" ]]; then
        removeSingBoxConfig bt_block_route
    fi
}

addXrayBTBlockRule() {
    if [[ ! -f "${configPath}09_routing.json" ]]; then
        writeRoutingJsonConfig "${configPath}09_routing.json" <<EOF || return 1
{
  "routing": {
    "domainStrategy": "IPOnDemand",
    "rules": []
  }
}
EOF
    fi

    unInstallRouting blackhole_out outboundTag bittorrent || return 1
    updateRoutingJsonConfig "${configPath}09_routing.json" '.routing.rules += [{"type":"field","outboundTag":"blackhole_out","protocol":["bittorrent"]}]'
}

addSingBoxBTBlockRule() {
    writeRoutingJsonConfig "${singBoxConfigPath}bt_block_route.json" <<EOF || return 1
{
  "route": {
    "rules": [
      {
        "action": "sniff",
        "timeout": "1s"
      },
      {
        "protocol": [
          "bittorrent"
        ],
        "action": "reject"
      }
    ]
  }
}
EOF
}

# 下载 dlc.dat_plain.yml 到核心目录
downloadDLCPlainYAML() {
    local corePath=$1
    local dlcFilePath="${corePath}/dlc.dat_plain.yml"
    local tmpFilePath="${dlcFilePath}.tmp"

    if [[ -z "${corePath}" ]]; then
        return 1
    fi

    mkdir -p "${corePath}" >/dev/null 2>&1
    if [[ -s "${dlcFilePath}" ]]; then
        return 0
    fi
    local dlcDownloadURL="https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat_plain.yml"
    downloadFile -O "${tmpFilePath}" "${dlcDownloadURL}" >/dev/null 2>&1

    # shellcheck disable=SC2181
    if [[ "$?" -ne 0 || ! -s "${tmpFilePath}" ]]; then
        rm -f "${tmpFilePath}" >/dev/null 2>&1
        return 1
    fi

    mv "${tmpFilePath}" "${dlcFilePath}" >/dev/null 2>&1
}

# 转义 grep/regex 匹配字符
escapeDLCRegexPattern() {
    # shellcheck disable=SC2016
    # shellcheck disable=SC2001
    echo "$1" | sed -e 's/[.[\*^$()+?{|]/\\&/g'
}

# 根据规则行号向上回溯对应 name
getDLCNameByRuleLine() {
    local ruleLine=$1
    local dlcFilePath=$2
    awk -v targetLine="${ruleLine}" '
    /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
        line = $0
        sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", line)
        currentName = line
    }
    NR == targetLine {
        print currentName
        exit
    }' "${dlcFilePath}"
}

isDomainFormat() {
    local target=$1
    [[ "${target}" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z0-9-]{2,63}$ ]]
}

# 根据输入域名匹配 dlc.dat_plain.yml 对应 geosite name
getDLCGeositeName() {
    local inputRule=$1
    local corePath=$2
    local dlcFilePath="${corePath}/dlc.dat_plain.yml"

    if [[ -z "${inputRule}" || -z "${corePath}" ]]; then
        echo ""
        return
    fi

    local normalizedInput
    normalizedInput=$(echo "${inputRule}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    normalizedInput=${normalizedInput#domain:}
    normalizedInput=${normalizedInput#full:}
    normalizedInput=${normalizedInput#keyword:}

    if [[ -z "${normalizedInput}" ]]; then
        echo ""
        return
    fi

    if isDomainFormat "${normalizedInput}"; then
        return
    fi

    if ! downloadDLCPlainYAML "${corePath}"; then
        echo ""
        return
    fi

    local escapedInput=
    escapedInput=$(escapeDLCRegexPattern "${normalizedInput}")

    local matchedLine=
    matchedLine=$(grep -n -m1 -E "^[[:space:]]*-[[:space:]]*name:[[:space:]]*${escapedInput}[[:space:]]*$" "${dlcFilePath}")
    if [[ -n "${matchedLine}" ]]; then
        echo "${normalizedInput}"
    fi
}

# 获取规则匹配结果，优先 geosite，失败按显式前缀或 domain 匹配
getDLCMatchedRuleValue() {
    local inputRule=$1
    local corePath=$2
    local normalizedInput=
    normalizedInput=$(echo "${inputRule}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [[ -z "${normalizedInput}" ]]; then
        echo ""
        return
    fi

    if [[ "${normalizedInput}" == geosite:* ]]; then
        echo "geosite:${normalizedInput#geosite:}"
        return
    fi
    if [[ "${normalizedInput}" == domain:* ]]; then
        echo "domain:${normalizedInput#domain:}"
        return
    fi
    if [[ "${normalizedInput}" == full:* ]]; then
        echo "full:${normalizedInput#full:}"
        return
    fi
    if [[ "${normalizedInput}" == keyword:* ]]; then
        echo "keyword:${normalizedInput#keyword:}"
        return
    fi
    if isDomainFormat "${normalizedInput}"; then
        echo "domain:${normalizedInput}"
        return
    fi

    local matchedRuleName=
    matchedRuleName=$(getDLCGeositeName "${normalizedInput}" "${corePath}")
    if [[ -n "${matchedRuleName}" ]]; then
        echo "geosite:${matchedRuleName}"
    else
        echo "keyword:${normalizedInput}"
    fi
}

# 添加 routing 配置
addXrayRouting() {

    local tag=$1    # warp-socks
    local type=$2   # outboundTag/inboundTag
    local domain=$3 # 域名
    local rulePosition=${4:-}

    if [[ -z "${tag}" || -z "${type}" || -z "${domain}" ]]; then
        errorCard "参数错误"
        exit 0
    fi

    local routingRule=
    if [[ ! -f "${configPath}09_routing.json" ]]; then
        writeRoutingJsonConfig "${configPath}09_routing.json" <<EOF || return 1
{
    "routing":{
        "type": "field",
        "rules": [
            {
                "type": "field",
                "domain": [
                ],
            "outboundTag": "${tag}"
          }
        ]
  }
}
EOF
    fi
    local routingRule=
    routingRule=$(jq -r ".routing.rules[]|select(.outboundTag==\"${tag}\" and (.protocol == null))" ${configPath}09_routing.json)

    if [[ -z "${routingRule}" ]]; then
        routingRule="{\"type\": \"field\",\"domain\": [],\"outboundTag\": \"${tag}\"}"
    fi

    local newRules=()
    while read -r line; do
        if echo "${routingRule}" | grep -q "${line}"; then
            statusCard "规则已存在" "${line} 已存在，跳过"
        else
            local matchedRuleValue
            matchedRuleValue=$(getDLCMatchedRuleValue "${line}" "/etc/padm/xray")
            newRules+=("${matchedRuleValue}")
        fi
    done < <(echo "${domain}" | tr ',' '\n')
    if [[ ${#newRules[@]} -gt 0 ]]; then
        local rulesJson
        rulesJson=$(printf '%s\n' "${newRules[@]}" | jq -R -s 'split("\n") | map(select(length > 0))')
        routingRule=$(jq -r --argjson rules "${rulesJson}" '.domain += $rules' <<<"${routingRule}")
    fi

    unInstallRouting "${tag}" "${type}" || return 1
    if ! grep -q "gstatic.com" ${configPath}09_routing.json && [[ "${tag}" == "blackhole_out" ]]; then
        updateRoutingJsonConfig "${configPath}09_routing.json" '.routing.rules += [{"type": "field","domain": ["domain:gstatic.com"],"outboundTag": "allow_domain_direct_outbound"}]' || return 1
        addXrayOutbound allow_domain_direct_outbound
    fi

    if [[ "${rulePosition}" == "top" ]]; then
        updateRoutingJsonConfig "${configPath}09_routing.json" '.routing.rules = [$routingRule] + .routing.rules' --argjson routingRule "${routingRule}"
    else
        updateRoutingJsonConfig "${configPath}09_routing.json" '.routing.rules += [$routingRule]' --argjson routingRule "${routingRule}"
    fi
}

# 添加 Xray IP 屏蔽路由规则
# 支持 geoip:cn 与自定义 IPv4/IPv6/CIDR
addXrayIPRouting() {

    local tag=$1
    local type=$2
    local ipList=$3

    if [[ -z "${tag}" || -z "${type}" || -z "${ipList}" ]]; then
        errorCard "参数错误"
        exit 0
    fi

    if [[ ! -f "${configPath}09_routing.json" ]]; then
        writeRoutingJsonConfig "${configPath}09_routing.json" <<EOF || return 1
{
    "routing":{
        "type": "field",
        "rules": []
    }
}
EOF
    fi

    local routingRule=
    routingRule=$(jq -r ".routing.rules[]|select(.outboundTag==\"${tag}\" and (.protocol == null) and (.ip != null))" ${configPath}09_routing.json)
    if [[ -z "${routingRule}" ]]; then
        routingRule="{\"type\": \"field\",\"ip\": [],\"outboundTag\": \"${tag}\"}"
    fi

    local newRules=()
    while read -r line; do
        line=$(echo "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -z "${line}" ]]; then
            continue
        fi

        local ipRuleValue=${line}
        if [[ "${line}" == "cn" ]]; then
            ipRuleValue="geoip:cn"
        fi

        if echo "${routingRule}" | grep -q "${ipRuleValue}"; then
            statusCard "规则已存在" "${ipRuleValue} 已存在，跳过"
        else
            newRules+=("${ipRuleValue}")
        fi
    done < <(echo "${ipList}" | tr ',' '\n')
    if [[ ${#newRules[@]} -gt 0 ]]; then
        local rulesJson
        rulesJson=$(printf '%s\n' "${newRules[@]}" | jq -R -s 'split("\n") | map(select(length > 0))')
        routingRule=$(jq -r --argjson rules "${rulesJson}" '.ip += $rules' <<<"${routingRule}")
    fi

    unInstallRouting "${tag}" "${type}" || return 1
    updateRoutingJsonConfig "${configPath}09_routing.json" '.routing.rules += [$routingRule]' --argjson routingRule "${routingRule}"
}

# 添加 sing-box IP 屏蔽路由规则
# 支持增量合并历史 ip_cidr
addSingBoxIPRouteRule() {
    local outboundTag=$1
    local ipList=$2
    local routingName=$3

    local historyIPs=
    if [[ -f "${singBoxConfigPath}${routingName}.json" ]]; then
        historyIPs=$(jq -r '.route.rules[0].ip_cidr[]?' "${singBoxConfigPath}${routingName}.json" | paste -sd ',')
    fi

    if [[ -n "${historyIPs}" ]]; then
        ipList="${ipList},${historyIPs}"
    fi

    local ipCIDR=[]
    ipCIDR=$(echo "${ipList}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^cn$/geoip:cn/' | grep -v '^$' | sort -n | uniq | jq -R . | jq -s .)

    local routeAction='"outbound": "'"${outboundTag}"'"'
    if [[ "${outboundTag}" == *block* ]]; then
        routeAction='"action": "reject"'
    fi
    writeRoutingJsonConfig "${singBoxConfigPath}${routingName}.json" <<EOF || return 1
{
  "route": {
    "rules": [
      {
        "ip_cidr": ${ipCIDR},
        ${routeAction}
      }
    ]
  }
}
EOF
}

# 添加 sing-box GeoIP 远程规则
# 用于大陆 IP 自动屏蔽场景
addSingBoxGeoIPRouteRule() {
    local outboundTag=$1
    local geoipCode=$2
    local routingName=$3

    local routeAction='"outbound": "'"${outboundTag}"'"'
    if [[ "${outboundTag}" == *block* ]]; then
        routeAction='"action": "reject"'
    fi
    writeRoutingJsonConfig "${singBoxConfigPath}${routingName}.json" <<EOF || return 1
{
  "route": {
    "rules": [
      {
        "rule_set": [
          "geoip_${geoipCode}_${routingName}"
        ],
        ${routeAction}
      }
    ],
    "rule_set": [
      {
        "tag": "geoip_${geoipCode}_${routingName}",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-${geoipCode}.srs",
        "download_detour": "01_direct_outbound"
      }
    ]
  }
}
EOF
}
# 根据 tag 卸载 Routing
unInstallRouting() {
    local tag=$1
    local type=$2
    local protocol=${3:-}

    if [[ -f "${configPath}09_routing.json" ]]; then
        if [[ -n "${protocol}" ]]; then
            updateRoutingJsonConfig "${configPath}09_routing.json" 'del(.routing.rules[] | select(.[$type] == $tag and ((.protocol // []) | index($protocol))))' --arg type "${type}" --arg tag "${tag}" --arg protocol "${protocol}"
        else
            updateRoutingJsonConfig "${configPath}09_routing.json" 'del(.routing.rules[] | select(.[$type] == $tag and (.protocol == null)))' --arg type "${type}" --arg tag "${tag}"
        fi
    fi
}

# 卸载嗅探配置
unInstallSniffing() {
    local inbound
    while IFS= read -r inbound; do
        if grep -q "destOverride" <"${inbound}"; then
            updateRoutingJsonConfig "${inbound}" 'del(.inbounds[0].sniffing)' || return 1
        fi
    done < <(find "${configPath}" -name "*inbounds.json")

}

# 安装嗅探配置
installSniffing() {
    local inbound
    readInstallType
    if [[ "${coreInstallType}" == "1" ]]; then
        while IFS= read -r inbound; do
            updateRoutingJsonConfig "${inbound}" '
                .inbounds[0].sniffing.enabled = true |
                .inbounds[0].sniffing.destOverride = ((.inbounds[0].sniffing.destOverride // []) + ["http", "tls", "quic"] | unique)
            ' || return 1
        done < <(find "${configPath}" -name "*inbounds.json")
    fi
}

# 读取第三方 WARP 配置
readConfigWarpReg() {
    if [[ ! -f "/etc/padm/warp/config" ]]; then
        /etc/padm/warp/warp-reg >/etc/padm/warp/config
    fi

    secretKeyWarpReg=$(grep <"/etc/padm/warp/config" private_key | awk '{print $2}')

    addressWarpReg=$(grep <"/etc/padm/warp/config" v6 | awk '{print $2}')

    publicKeyWarpReg=$(grep <"/etc/padm/warp/config" public_key | awk '{print $2}')

    reservedWarpReg=$(grep <"/etc/padm/warp/config" reserved | awk -F "[:]" '{print $2}')

}
# 安装 warp-reg 工具
installWarpReg() {
    if [[ ! -f "/etc/padm/warp/warp-reg" ]]; then
        echo
        echoContent title "\n┌─ warp-reg 第三方工具 ──────────────────────────────"
        menuLine "依赖第三方程序，请熟知其中风险"
        menuLine "项目地址：https://github.com/badafans/warp-reg"
        menuClose

        autoRead warp_reg_install "warp-reg未安装，是否安装？[y/n]:" installWarpRegStatus

        if [[ "${installWarpRegStatus}" == "y" ]]; then

            if ! downloadGitHubReleaseAsset -P /etc/padm/warp/ badafans/warp-reg v1.0 "${warpRegCoreCPUVendor}"; then
                errorCard "warp-reg下载失败"
                exit 1
            fi
            if [[ ! -s "/etc/padm/warp/${warpRegCoreCPUVendor}" ]]; then
                errorCard "warp-reg文件异常"
                exit 1
            fi
            mv "/etc/padm/warp/${warpRegCoreCPUVendor}" /etc/padm/warp/warp-reg
            chmod 655 /etc/padm/warp/warp-reg

        else
            statusCard "已取消" "放弃安装"
            exit 0
        fi
    fi
}

# 展示 WARP 分流域名
showWireGuardDomain() {
    local type=$1
    if [[ "${coreInstallType}" == "1" ]]; then
        if [[ -f "${configPath}09_routing.json" ]]; then
            echoContent yellow "Xray-core"
            jq -r -c '.routing.rules[]|select (.outboundTag=="wireguard_out_'"${type}"'")|.domain' ${configPath}09_routing.json | jq -r
        elif [[ ! -f "${configPath}09_routing.json" && -f "${configPath}wireguard_out_${type}.json" ]]; then
            echoContent yellow "Xray-core"
            successCard "已设置warp ${type}全局分流"
        else
            statusCard "WARP 分流" "未安装 WARP ${type} 分流"
        fi
    fi

    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}wireguard_endpoints_${type}_route.json" ]]; then
            echoContent yellow "sing-box"
            jq -r -c '.route.rules[]' "${singBoxConfigPath}wireguard_endpoints_${type}_route.json" | jq -r
        elif [[ ! -f "${singBoxConfigPath}wireguard_endpoints_${type}_route.json" && -f "${singBoxConfigPath}wireguard_endpoints_${type}.json" ]]; then
            echoContent yellow "sing-box"
            successCard "已设置warp ${type}全局分流"
        else
            statusCard "WARP 分流" "未安装 WARP ${type} 分流"
        fi
    fi

}

# 添加 WARP 分流规则
addWireGuardRoute() {
    local type=$1
    local tag=$2
    local domainList=$3
    if [[ "${coreInstallType}" == "1" ]]; then

        addXrayRouting "wireguard_out_${type}" "${tag}" "${domainList}"
        addXrayOutbound "wireguard_out_${type}"
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then

        addSingBoxRouteRule "wireguard_endpoints_${type}" "${domainList}" "wireguard_endpoints_${type}_route"
        if [[ -n "${domainList}" ]]; then
            addSingBoxOutbound "01_direct_outbound"
        fi

        addSingBoxWireGuardEndpoints "${type}"
    fi
}

# 卸载 WireGuard
unInstallWireGuard() {
    local type=$1
    if [[ "${coreInstallType}" == "1" ]]; then

        if [[ "${type}" == "IPv4" ]]; then
            if [[ ! -f "${configPath}wireguard_out_IPv6.json" ]]; then
                rm -rf /etc/padm/warp/config >/dev/null 2>&1
            fi
        elif [[ "${type}" == "IPv6" ]]; then
            if [[ ! -f "${configPath}wireguard_out_IPv4.json" ]]; then
                rm -rf /etc/padm/warp/config >/dev/null 2>&1
            fi
        fi
    fi

    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ ! -f "${singBoxConfigPath}wireguard_endpoints_IPv6_route.json" && ! -f "${singBoxConfigPath}wireguard_endpoints_IPv4_route.json" ]]; then
            rm "${singBoxConfigPath}wireguard_outbound.json" >/dev/null 2>&1
            rm -rf /etc/padm/warp/config >/dev/null 2>&1
        fi
    fi
}
# 移除 WARP 分流规则
removeWireGuardRoute() {
    local type=$1
    if [[ "${coreInstallType}" == "1" ]]; then

        unInstallRouting wireguard_out_"${type}" outboundTag

        removeXrayOutbound "wireguard_out_${type}"
        if [[ ! -f "${configPath}IPv4_out.json" ]]; then
            addXrayOutbound IPv4_out
        fi
    fi

    if [[ -n "${singBoxConfigPath}" ]]; then
        removeSingBoxRouteRule "wireguard_endpoints_${type}"
    fi

    unInstallWireGuard "${type}"
}
# WARP 第三方分流管理
warpRoutingReg() {
    local type=$2
    local title="WARP 分流 ${type}"
    progressCard "$1" "${title}"
    echoContent title "\n┌─ ${title} ────────────────────────────────────────"
    menuLine "依赖 Cloudflare WARP WireGuard 出站与第三方 warp-reg 账号注册工具"
    menuLine "适合少量域名或明确场景分流；全局模式会移除其他出站规则"
    menuItem 1 "查看已分流域名" "显示当前 WARP ${type} 分流规则"
    menuItem 2 "添加域名" "添加 WARP ${type} 出站分流规则"
    menuDangerItem 3 "设置 WARP 全局" "删除其他出站并全局走 WARP ${type}"
    menuDangerItem 4 "卸载 WARP 分流" "移除 WARP ${type} 分流配置"
    menuReturnItem 5 "返回 WARP 出站" "回到 WARP 出站菜单"
    menuClose
    autoRead warp_ipv4_menu "请选择:" warpStatus
    installWarpReg
    readConfigWarpReg
    local address=
    if [[ ${type} == "IPv4" ]]; then
        address="172.16.0.2/32"
    elif [[ ${type} == "IPv6" ]]; then
        address="${addressWarpReg}/128"
    else
        errorCard "IP获取失败，退出安装"
    fi

    if [[ "${warpStatus}" == "1" ]]; then
        showWireGuardDomain "${type}"
        exit 0
    elif [[ "${warpStatus}" == "2" ]]; then
        echoContent title "\n┌─ WARP 分流规则说明 ────────────────────────────────"
        menuLine "支持 sing-box、Xray-core"
        menuLine "请按 README 中的分流说明配置域名或规则"
        menuClose

        autoRead routing_domain_rules "请按照上面示例录入域名:" domainList
        addWireGuardRoute "${type}" outboundTag "${domainList}"
        successCard "添加完毕"

    elif [[ "${warpStatus}" == "3" ]]; then

        warnCard \
            "会删除所有设置的分流规则" \
            "会删除除 WARP[第三方] 之外的所有出站规则"
        autoConfirm warp_global_confirm "确认设置 WARP 全局出站？" n warpOutStatus

        if [[ "${warpOutStatus}" == "y" ]]; then
            readConfigWarpReg
            if [[ "${coreInstallType}" == "1" ]]; then
                addXrayOutbound "wireguard_out_${type}"
                if [[ "${type}" == "IPv4" ]]; then
                    removeXrayOutbound "wireguard_out_IPv6"
                elif [[ "${type}" == "IPv6" ]]; then
                    removeXrayOutbound "wireguard_out_IPv4"
                fi

                removeXrayOutbound IPv4_out
                removeXrayOutbound IPv6_out
                removeXrayOutbound z_direct_outbound
                removeXrayOutbound blackhole_out
                removeXrayOutbound socks5_outbound

                rm ${configPath}09_routing.json >/dev/null 2>&1
            fi

            if [[ -n "${singBoxConfigPath}" ]]; then

                removeSingBoxConfig IPv4_out
                removeSingBoxConfig IPv6_out
                removeSingBoxConfig 01_direct_outbound

                # 删除所有分流规则
                removeSingBoxConfig wireguard_endpoints_IPv4_route
                removeSingBoxConfig wireguard_endpoints_IPv6_route

                removeSingBoxConfig IPv6_route
                removeSingBoxConfig socks5_02_inbound_route

                addSingBoxWireGuardEndpoints "${type}"
                addWireGuardRoute "${type}" outboundTag ""
                if [[ "${type}" == "IPv4" ]]; then
                    removeSingBoxConfig wireguard_endpoints_IPv6
                else
                    removeSingBoxConfig wireguard_endpoints_IPv4
                fi

            fi

            successCard "WARP全局出站设置完毕"
        else
            statusCard "已取消" "未设置 WARP 全局出站"
            warpRoutingReg "$1" "${type}"
            return 0
        fi

    elif [[ "${warpStatus}" == "4" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            unInstallRouting "wireguard_out_${type}" outboundTag

            removeXrayOutbound "wireguard_out_${type}"
            addXrayOutbound "z_direct_outbound"
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            removeSingBoxConfig "wireguard_endpoints_${type}_route"

            removeSingBoxConfig "wireguard_endpoints_${type}"
            addSingBoxOutbound "01_direct_outbound"
        fi

        successCard "卸载WARP ${type}分流完毕"
    elif [[ "${warpStatus}" == "5" ]]; then
        warpRoutingMenu
        return 0
    else

        errorCard "选择错误"
        warpRoutingReg "$1" "${type}"
        return 0
    fi
    reloadCore
}

# 分流工具
routingToolsMenu() {
    echoContent title "\n┌─ 分流工具 ─────────────────────────────────────────"
    menuLine "按域名或规则把服务端出站流量改走指定出口"
    menuLine "WARP、Socks5 全局模式会删除其他出站规则，启用前请确认用途"
    menuItem 1 "WARP 出站" "Cloudflare WARP WireGuard 出站，依赖第三方注册工具"
    menuItem 2 "IPv6 出站" "按域名或全局走 IPv6 direct 出站"
    menuItem 3 "Socks5 中继" "接入外部 Socks5 或给其他机器提供 Socks5 入站"
    menuItem 4 "DNS 覆盖" "为指定域名改用指定 DNS 解析"
    menuItem 5 "DNS/hosts 覆盖" "把指定域名解析到指定后端 IP"
    menuReturnItem 6 "返回路由与访问控制" "回到上级菜单"
    menuClose

    autoRead routing_tools_menu "请选择:" selectType

    case ${selectType} in
    1)
        warpRoutingMenu
        ;;
    2)
        ipv6Routing 1
        ;;
    3)
        socks5Routing
        ;;
    4)
        dnsRouting 1
        ;;
    5)
        if [[ -n "${singBoxConfigPath}" ]]; then
            errorCard "此功能不支持Hysteria2、Tuic"
        fi
        sniRouting 1
        ;;
    6)
        routingAccessMenu
        ;;
    *)
        errorCard "选择错误"
        routingToolsMenu
        ;;
    esac
}

warpRoutingMenu() {
    echoContent title "\n┌─ WARP 出站 ────────────────────────────────────────"
    menuLine "通过 Cloudflare WARP WireGuard 出站，常用于 IPv4/IPv6 出口切换"
    menuLine "依赖第三方 warp-reg 获取账号参数；Cloudflare 服务状态或策略变化会影响可用性"
    menuItem 1 "WARP IPv4" "使用 IPv4 WARP 地址作为出站"
    menuItem 2 "WARP IPv6" "使用 IPv6 WARP 地址作为出站"
    menuReturnItem 3 "返回分流工具" "回到上一级分流菜单"
    menuClose
    autoRead warp_routing_type_menu "请选择:" warpRoutingType

    case ${warpRoutingType} in
    1)
        warpRoutingReg 1 IPv4
        ;;
    2)
        warpRoutingReg 1 IPv6
        ;;
    3)
        routingToolsMenu
        ;;
    *)
        errorCard "选择错误"
        warpRoutingMenu
        ;;
    esac
}

# VMess+WS+TLS 分流
vmessWSRouting() {
    echoContent title "\n┌─ VMess WS TLS 分流 ────────────────────────────────"
    menuLine "请按 README 中的分流说明配置域名或规则"
    menuItem 1 "添加出站" "添加 VMess WS TLS 出站分流"
    menuDangerItem 2 "卸载" "移除 VMess WS TLS 分流"
    menuReturnItem 3 "返回分流工具" "回到上一级分流菜单"
    menuClose
    autoRead vmess_ws_routing_menu "请选择:" selectType

    case ${selectType} in
    1)
        setVMessWSRoutingOutbounds
        ;;
    2)
        removeVMessWSRouting
        ;;
    3)
        routingToolsMenu
        ;;
    *)
        errorCard "选择错误，请重新选择"
        vmessWSRouting
        ;;
    esac
}

# Socks5 分流管理
socks5Routing() {
    if [[ -z "${coreInstallType}" ]]; then
        errorCard "未安装任意协议，请先进入主菜单 -> 安装与重装"
        exit 0
    fi
    echoContent title "\n┌─ Socks5 分流 ──────────────────────────────────────"
    menuLine "用于两台机器之间中继出站，不建议把入站暴露给不可信网络"
    menuLine "出站适合本机把部分域名转发到落地机；入站适合落地机只允许指定源 IP 访问"
    menuItem 1 "Socks5 出站" "转发机/代理机配置"
    menuItem 2 "Socks5 入站" "解锁机/落地机配置"
    menuItem 3 "卸载" "移除 Socks5 分流配置"
    menuReturnItem 4 "返回分流工具" "回到上一级分流菜单"
    menuClose
    autoRead socks5_menu "请选择:" selectType

    case ${selectType} in
    1)
        socks5OutboundRoutingMenu
        ;;
    2)
        socks5InboundRoutingMenu
        ;;
    3)
        removeSocks5Routing
        ;;
    4)
        routingToolsMenu
        ;;
    *)
        errorCard "选择错误，请重新选择"
        socks5Routing
        ;;
    esac
}
# Socks5 入站菜单
socks5InboundRoutingMenu() {
    readInstallType
    echoContent title "\n┌─ Socks5 入站 ──────────────────────────────────────"
    menuItem 1 "安装 Socks5 入站" "配置解锁机/落地机入站"
    menuItem 2 "查看分流规则" "显示当前入站分流规则"
    menuItem 3 "添加分流规则" "更新入站分流域名"
    menuItem 4 "查看入站配置" "显示端口、用户与密码"
    menuReturnItem 5 "返回 Socks5 分流" "回到上级菜单"
    menuClose
    autoRead socks5_inbound_menu "请选择:" selectType
    case ${selectType} in
    1)
        totalProgress=1
        installSingBox 1
        installSingBoxService 1
        setSocks5Inbound
        setSocks5InboundRouting
        reloadCore
        socks5InboundRoutingMenu
        ;;
    2)
        showSingBoxRoutingRules socks5_02_inbound_route
        socks5InboundRoutingMenu
        ;;
    3)
        setSocks5InboundRouting addRules
        reloadCore
        socks5InboundRoutingMenu
        ;;
    4)
        if [[ -f "${singBoxConfigPath}20_socks5_inbounds.json" ]]; then
            echoContent title "\n┌─ Socks5 出站信息 ──────────────────────────────────"
            menuLine "下列内容需要配置到其他机器的出站，请不要在本机进行代理行为"
            menuLine "端口：$(jq .inbounds[0].listen_port ${singBoxConfigPath}20_socks5_inbounds.json)"
            menuLine "用户名称：$(jq -r .inbounds[0].users[0].username ${singBoxConfigPath}20_socks5_inbounds.json)"
            menuLine "用户密码：$(jq -r .inbounds[0].users[0].password ${singBoxConfigPath}20_socks5_inbounds.json)"
            menuClose
        else
            errorCard "未安装相应功能"
            socks5InboundRoutingMenu
        fi
        ;;
    5)
        socks5Routing
        ;;
    *)
        errorCard "选择错误，请重新选择"
        socks5InboundRoutingMenu
        ;;
    esac

}

# Socks5 出站菜单
socks5OutboundRoutingMenu() {
    echoContent title "\n┌─ Socks5 出站 ──────────────────────────────────────"
    menuItem 1 "安装 Socks5 出站" "配置转发机/代理机出站"
    menuDangerItem 2 "设置 Socks5 全局转发" "删除其他出站并全局走 Socks5"
    menuItem 3 "查看分流规则" "显示当前出站分流规则"
    menuItem 4 "添加分流规则" "更新出站分流域名"
    menuReturnItem 5 "返回 Socks5 分流" "回到上级菜单"
    menuClose
    autoRead socks5_outbound_menu "请选择:" selectType
    case ${selectType} in
    1)
        setSocks5Outbound
        setSocks5OutboundRouting
        reloadCore
        socks5OutboundRoutingMenu
        ;;
    2)
        setSocks5Outbound
        setSocks5OutboundRoutingAll
        reloadCore
        socks5OutboundRoutingMenu
        ;;
    3)
        showSingBoxRoutingRules socks5_01_outbound_route
        showXrayRoutingRules socks5_outbound
        socks5OutboundRoutingMenu
        ;;
    4)
        setSocks5OutboundRouting addRules
        reloadCore
        socks5OutboundRoutingMenu
        ;;
    5)
        socks5Routing
        ;;
    *)
        errorCard "选择错误，请重新选择"
        socks5OutboundRoutingMenu
        ;;
    esac

}

# Socks5 全局分流
setSocks5OutboundRoutingAll() {

    warnCard \
        "会删除所有已经设置的分流规则，包括其他分流（warp、IPv6 等）" \
        "会删除 Socks5 之外的所有出站规则"
    autoConfirm socks5_global_confirm "确认设置 Socks5 全局出站？" n socksOutStatus

    if [[ "${socksOutStatus}" == "y" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            removeXrayOutbound IPv4_out
            removeXrayOutbound IPv6_out
            removeXrayOutbound z_direct_outbound
            removeXrayOutbound blackhole_out
            removeXrayOutbound wireguard_out_IPv4
            removeXrayOutbound wireguard_out_IPv6

            rm ${configPath}09_routing.json >/dev/null 2>&1
        fi
        if [[ -n "${singBoxConfigPath}" ]]; then

            removeSingBoxConfig IPv4_out
            removeSingBoxConfig IPv6_out

            removeSingBoxConfig wireguard_endpoints_IPv4_route
            removeSingBoxConfig wireguard_endpoints_IPv6_route
            removeSingBoxConfig wireguard_endpoints_IPv4
            removeSingBoxConfig wireguard_endpoints_IPv6

            removeSingBoxConfig socks5_01_outbound_route
            removeSingBoxConfig 01_direct_outbound
        fi

        successCard "Socks5全局出站设置完毕"
    fi
}
# Socks5 分流规则
showSingBoxRoutingRules() {
    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}$1.json" ]]; then
            jq .route.rules "${singBoxConfigPath}$1.json"
        elif [[ "$1" == "socks5_01_outbound_route" && -f "${singBoxConfigPath}socks5_outbound.json" ]]; then
            echoContent yellow "已安装 sing-box socks5全局出站分流"
            menuLine "$(uiStyle warn "出站分流配置：")"
            menuLine "$(uiStyle value "$(jq .outbounds[0] ${singBoxConfigPath}socks5_outbound.json)")"
        elif [[ "$1" == "socks5_02_inbound_route" && -f "${singBoxConfigPath}20_socks5_inbounds.json" ]]; then
            echoContent yellow "已安装 sing-box socks5全局入站分流"
            menuLine "$(uiStyle warn "出站分流配置：")"
            menuLine "$(uiStyle value "$(jq .outbounds[0] ${singBoxConfigPath}socks5_outbound.json)")"
        fi
    fi
}

# Xray-core 分流规则
showXrayRoutingRules() {
    if [[ "${coreInstallType}" == "1" ]]; then
        if [[ -f "${configPath}09_routing.json" ]]; then
            jq ".routing.rules[]|select(.outboundTag==\"$1\")" "${configPath}09_routing.json"

            echoContent yellow "\n已安装 xray-core socks5全局出站分流"
            menuLine "$(uiStyle warn "出站分流配置：")"
            menuLine "$(uiStyle value "$(jq .outbounds[0].settings.servers[0] ${configPath}socks5_outbound.json)")"

        elif [[ "$1" == "socks5_outbound" && -f "${configPath}socks5_outbound.json" ]]; then
            echoContent yellow "\n已安装 xray-core socks5全局出站分流"
            menuLine "$(uiStyle warn "出站分流配置：")"
            menuLine "$(uiStyle value "$(jq .outbounds[0].settings.servers[0] ${configPath}socks5_outbound.json)")"
        fi
    fi
}

# 卸载 Socks5 分流
removeSocks5Routing() {
    echoContent title "\n┌─ 卸载 Socks5 分流 ─────────────────────────────────"
    menuItem 1 "卸载 Socks5 出站" "移除出站转发配置"
    menuItem 2 "卸载 Socks5 入站" "移除入站监听配置"
    menuDangerItem 3 "卸载全部" "同时移除 Socks5 出站和入站配置"
    menuReturnItem 4 "返回 Socks5 分流" "回到上级菜单"
    menuClose
    autoRead socks5_uninstall_menu "请选择:" unInstallSocks5RoutingStatus
    if [[ "${unInstallSocks5RoutingStatus}" == "1" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            removeXrayOutbound socks5_outbound
            unInstallRouting socks5_outbound outboundTag

            addXrayOutbound z_direct_outbound
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            removeSingBoxConfig socks5_outbound
            removeSingBoxConfig socks5_01_outbound_route
            addSingBoxOutbound 01_direct_outbound
        fi

    elif [[ "${unInstallSocks5RoutingStatus}" == "2" ]]; then

        removeSingBoxConfig 20_socks5_inbounds
        removeSingBoxConfig socks5_02_inbound_route
        removeSingBoxConfig sniff_socks5_inbound
        removeSingBoxConfig "strategy_ipv4_only_socks5_inbound"
        removeSingBoxConfig "strategy_ipv6_only_socks5_inbound"

        handleSingBox stop
    elif [[ "${unInstallSocks5RoutingStatus}" == "3" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            removeXrayOutbound socks5_outbound
            unInstallRouting socks5_outbound outboundTag
            addXrayOutbound z_direct_outbound
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            removeSingBoxConfig socks5_outbound
            removeSingBoxConfig socks5_01_outbound_route
            removeSingBoxConfig 20_socks5_inbounds
            removeSingBoxConfig socks5_02_inbound_route
            removeSingBoxConfig sniff_socks5_inbound
            removeSingBoxConfig "strategy_ipv4_only_socks5_inbound"
            removeSingBoxConfig "strategy_ipv6_only_socks5_inbound"

            addSingBoxOutbound 01_direct_outbound
        fi

        handleSingBox stop
    elif [[ "${unInstallSocks5RoutingStatus}" == "4" ]]; then
        socks5Routing
        return
    else
        errorCard "选择错误，请重新选择"
        removeSocks5Routing
        return
    fi
    successCard "卸载完毕"
    reloadCore
}
# 写入 Socks5 入站配置
writeSocks5InboundConfig() {
    local targetPath=$1
    local listenPort=$2
    local uuid=$3
    writeRoutingJsonConfig "${targetPath}" <<EOF || return 1
{
    "inbounds":[
        {
          "type": "socks",
          "listen":"::",
          "listen_port":${listenPort},
          "tag":"socks5_inbound",
          "users":[
            {
                  "username": "${uuid}",
                  "password": "${uuid}"
            }
          ]
        }
    ]
}
EOF
}

# Socks5 入站配置
setSocks5Inbound() {

    echoContent title "\n┌─ 配置 Socks5 入站 ─────────────────────────────────"
    menuLine "解锁机、落地机入站配置"
    menuClose
    echoContent title "\n┌─ Socks5 入站端口 ─────────────────────────────────"
    echo
    mapfile -t result < <(initSingBoxPort "${singBoxSocks5Port}")
    statusCard "入站 Socks5" "端口：${result[-1]}" "此端口需要配置到其他机器出站，请不要进行代理行为"

    echoContent yellow "\n请输入自定义UUID[需合法]，[回车]随机UUID"
    autoRead socks5_inbound_uuid "UUID:" socks5RoutingUUID
    if [[ -z "${socks5RoutingUUID}" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            socks5RoutingUUID=$(/etc/padm/xray/xray uuid)
        elif [[ -n "${singBoxConfigPath}" ]]; then
            socks5RoutingUUID=$(/etc/padm/sing-box/sing-box generate uuid)
        fi
    fi
    echo
    echoContent green "用户名称：${socks5RoutingUUID}"
    echoContent green "用户密码：${socks5RoutingUUID}"

    echoContent title "\n┌─ Socks5 DNS 解析类型 ──────────────────────────────"
    menuLine "需要保证 VPS 支持相应的 DNS 解析"
    menuRecommendedItem 1 "IPv4" "默认解析策略"
    menuItem 2 "IPv6" "IPv6 解析策略"
    menuClose

    autoRead socks5_inbound_ip_type "IP类型:" socks5InboundDomainStrategyStatus
    local domainStrategy=
    if [[ -z "${socks5InboundDomainStrategyStatus}" || "${socks5InboundDomainStrategyStatus}" == "1" ]]; then
        domainStrategy="ipv4_only"
    elif [[ "${socks5InboundDomainStrategyStatus}" == "2" ]]; then
        domainStrategy="ipv6_only"
    else
        errorCard "选择类型错误"
        exit 0
    fi
    local socks5InboundPath="${singBoxConfigPath:-/etc/padm/sing-box/conf/config/}20_socks5_inbounds.json"
    writeSocks5InboundConfig "${socks5InboundPath}" "${result[-1]}" "${socks5RoutingUUID}" || return 1
    setStrategyRouting socks5_inbound "${domainStrategy}"
}

# 初始化 sing-box rule_set 路由规则
initSingBoxRules() {
    local domainRuleLines=
    local ruleSetLines=
    local suffixRuleLines=
    local singBoxRulePath="${singBoxConfigPath:-/etc/padm/sing-box/conf/config/}"
    local line normalizedLine matchedRuleName tag url
    while read -r line; do
        normalizedLine=$(echo "${line}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [[ -z "${normalizedLine}" ]]; then
            continue
        fi

        if [[ "${normalizedLine}" == geosite:* ]]; then
            normalizedLine=${normalizedLine#geosite:}
            tag="geosite_${normalizedLine}_$2"
            url="https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-${normalizedLine}.srs"
            ruleSetLines+="${tag}"$'\t'"${url}"$'\n'
            continue
        fi
        if [[ "${normalizedLine}" == domain:* ]]; then
            suffixRuleLines+="${normalizedLine#domain:}"$'\n'
            continue
        fi
        if [[ "${normalizedLine}" == full:* ]]; then
            domainRuleLines+="${normalizedLine#full:}"$'\n'
            continue
        fi
        if [[ "${normalizedLine}" == keyword:* ]]; then
            suffixRuleLines+="${normalizedLine#keyword:}"$'\n'
            continue
        fi

        if isDomainFormat "${normalizedLine}"; then
            suffixRuleLines+="${normalizedLine}"$'\n'
        else
            matchedRuleName=$(getDLCGeositeName "${normalizedLine}" "${singBoxRulePath}")

            if [[ -n "${matchedRuleName}" ]]; then
                tag="geosite_${matchedRuleName}_$2"
                url="https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-${matchedRuleName}.srs"
                ruleSetLines+="${tag}"$'\t'"${url}"$'\n'
            else
                suffixRuleLines+="${normalizedLine}"$'\n'
            fi
        fi
    done < <(echo "$1" | tr ',' '\n' | grep -v '^$' | sort -u)

    jq -n \
        --arg domainRules "${domainRuleLines}" \
        --arg suffixRules "${suffixRuleLines}" \
        --arg ruleSet "${ruleSetLines}" '
        def lines($value): $value | split("\n") | map(select(length > 0));
        {
          domainRules: lines($domainRules),
          suffixRules: lines($suffixRules),
          ruleSet: ($ruleSet | split("\n") | map(select(length > 0) | split("\t") | {
            tag: .[0],
            type: "remote",
            format: "binary",
            url: .[1],
            download_detour: "01_direct_outbound"
          }))
        }'
}

splitSingBoxRules() {
    local rules=$1
    local -n domainRulesRef=$2
    local -n suffixRulesRef=$3
    local -n ruleSetRef=$4
    local -n ruleSetTagRef=$5
    local parsedRules
    mapfile -t parsedRules < <(jq -c '.domainRules, .suffixRules, .ruleSet, (.ruleSet | map(.tag))' <<<"${rules}")
    domainRulesRef=${parsedRules[0]:-[]}
    suffixRulesRef=${parsedRules[1]:-[]}
    ruleSetRef=${parsedRules[2]:-[]}
    ruleSetTagRef=${parsedRules[3]:-[]}
}

# Socks5 inbound routing 规则
setSocks5InboundRouting() {

    singBoxConfigPath=/etc/padm/sing-box/conf/config/

    if [[ "$1" == "addRules" && ! -f "${singBoxConfigPath}socks5_02_inbound_route.json" && ! -f "${configPath}09_routing.json" ]]; then
        errorCard "请安装入站分流后再添加分流规则"
        errorCard "如已选择允许所有网站，请重新安装分流后设置规则"
        exit 0
    fi
    local socks5InboundRoutingIPs=
    if [[ "$1" == "addRules" ]]; then
        socks5InboundRoutingIPs=$(jq .route.rules[0].source_ip_cidr "${singBoxConfigPath}socks5_02_inbound_route.json")
    else
        echoContent title "\n┌─ Socks5 入站访问源 ────────────────────────────────"
        menuLine "请输入允许访问的 IP 地址，多个 IP 用英文逗号分隔"
        menuLine "示例：1.1.1.1,2.2.2.2"
        menuClose
        autoRead socks5_inbound_source_ips "IP:" socks5InboundRoutingIPs

        if [[ -z "${socks5InboundRoutingIPs}" ]]; then
            errorCard "IP不可为空"
            exit 0
        fi
        socks5InboundRoutingIPs=$(echo "\"${socks5InboundRoutingIPs}"\" | jq -c '.|split(",")')
    fi

    echoContent title "\n┌─ Socks5 域名分流 ─────────────────────────────────"
    menuLine "请输入要分流的域名"
    menuLine "支持 Xray-core geosite 匹配，支持 sing-box 1.8+ rule_set 匹配"
    menuLine "非增量添加，会替换原有规则；无法匹配则使用 domain 精确匹配"
    menuClose

    autoRead socks5_inbound_allow_all "是否允许所有网站？请选择[y/n]:" socks5InboundRoutingDomainStatus
    if [[ "${socks5InboundRoutingDomainStatus}" == "y" ]]; then
        addSingBoxRouteRule "01_direct_outbound" "" "socks5_02_inbound_route"
        updateRoutingJsonConfig "${singBoxConfigPath}socks5_02_inbound_route.json" '.route.rules[0].inbound = ["socks5_inbound"] | .route.rules[0].source_ip_cidr = $sourceIPs' --argjson sourceIPs "${socks5InboundRoutingIPs}" || return 1

        addSingBoxOutbound "01_direct_outbound"
    else
        echoContent yellow "录入示例:netflix,openai,example.com\n"
        autoRead socks5_inbound_domains "域名:" socks5InboundRoutingDomain
        if [[ -z "${socks5InboundRoutingDomain}" ]]; then
            errorCard "域名不可为空"
            exit 0
        fi
        addSingBoxRouteRule "01_direct_outbound" "${socks5InboundRoutingDomain}" "socks5_02_inbound_route"
        updateRoutingJsonConfig "${singBoxConfigPath}socks5_02_inbound_route.json" '.route.rules[0].inbound = ["socks5_inbound"] | .route.rules[0].source_ip_cidr = $sourceIPs' --argjson sourceIPs "${socks5InboundRoutingIPs}" || return 1

        addSingBoxOutbound "01_direct_outbound"
    fi

}

# 设置 sniff routing 规则
setSniffRouting() {
    local targetPath="${singBoxConfigPath:-/etc/padm/sing-box/conf/config/}sniff.json"
    writeRoutingJsonConfig "${targetPath}" <<EOF || return 1
{
    "route":{
        "rules":[
          {
            "action": "sniff",
            "timeout": "1s"
          }
        ]
    }
}
EOF
}

# 设置 sniff routing 规则
setStrategyRouting() {
    local tag=$1
    local strategy=$2
    local targetPath="${singBoxConfigPath:-/etc/padm/sing-box/conf/config/}strategy_${strategy}_${tag}.json"
    writeRoutingJsonConfig "${targetPath}" <<EOF || return 1
{
    "route":{
        "rules":[
          {
            "inbound": "${tag}",
            "action": "resolve",
            "strategy": "${strategy}"
          }
        ]
    }
}
EOF
}
# Socks5 出站
setSocks5Outbound() {

    echoContent title "\n┌─ 配置 Socks5 出站 ─────────────────────────────────"
    menuLine "转发机、代理机出站配置"
    menuClose
    echo
    autoRead socks5_outbound_ip "请输入落地机IP地址:" socks5RoutingOutboundIP
    if [[ -z "${socks5RoutingOutboundIP}" ]]; then
        errorCard "IP不可为空"
        exit 0
    fi
    echo
    autoRead socks5_outbound_port "请输入落地机端口:" socks5RoutingOutboundPort
    if [[ -z "${socks5RoutingOutboundPort}" ]]; then
        errorCard "端口不可为空"
        exit 0
    fi
    echo
    autoRead socks5_outbound_username "请输入用户名:" socks5RoutingOutboundUserName
    if [[ -z "${socks5RoutingOutboundUserName}" ]]; then
        errorCard "用户名不可为空"
        exit 0
    fi
    echo
    autoRead socks5_outbound_password "请输入用户密码:" socks5RoutingOutboundPassword
    if [[ -z "${socks5RoutingOutboundPassword}" ]]; then
        errorCard "用户密码不可为空"
        exit 0
    fi
    echo
    if [[ -n "${singBoxConfigPath}" ]]; then
        writeRoutingJsonConfig "${singBoxConfigPath}socks5_outbound.json" <<EOF || return 1
{
    "outbounds":[
        {
          "type": "socks",
          "tag":"socks5_outbound",
          "server": "${socks5RoutingOutboundIP}",
          "server_port": ${socks5RoutingOutboundPort},
          "version": "5",
          "username":"${socks5RoutingOutboundUserName}",
          "password":"${socks5RoutingOutboundPassword}"
        }
    ]
}
EOF
    fi
    if [[ "${coreInstallType}" == "1" ]]; then
        addXrayOutbound socks5_outbound
    fi
}

# Socks5 outbound routing 规则
setSocks5OutboundRouting() {

    if [[ "$1" == "addRules" && ! -f "${singBoxConfigPath}socks5_01_outbound_route.json" && ! -f "${configPath}09_routing.json" ]]; then
        errorCard "请安装出站分流后再添加分流规则"
        exit 0
    fi

    echoContent title "\n┌─ Socks5 域名分流 ─────────────────────────────────"
    menuLine "请输入要分流的域名"
    menuLine "支持 Xray-core geosite 匹配，支持 sing-box 1.8+ rule_set 匹配"
    menuLine "非增量添加，会替换原有规则；无法匹配则使用 domain 精确匹配"
    menuClose
    echoContent yellow "录入示例:netflix,openai,example.com\n"
    autoRead socks5_outbound_domains "域名:" socks5RoutingOutboundDomain
    if [[ -z "${socks5RoutingOutboundDomain}" ]]; then
        errorCard "IP不可为空"
        exit 0
    fi
    addSingBoxRouteRule "socks5_outbound" "${socks5RoutingOutboundDomain}" "socks5_01_outbound_route"
    addSingBoxOutbound "01_direct_outbound"

    if [[ "${coreInstallType}" == "1" ]]; then

        unInstallRouting "socks5_outbound" "outboundTag"
        local domainRules=[]
        while read -r line; do
            if echo "${routingRule}" | grep -q "${line}"; then
                statusCard "规则已存在" "${line} 已存在，跳过"
            else
                local matchedRuleValue
                matchedRuleValue=$(getDLCMatchedRuleValue "${line}" "/etc/padm/xray")
                domainRules=$(echo "${domainRules}" | jq -r --arg rule "${matchedRuleValue}" '. += [$rule]')
            fi
        done < <(echo "${socks5RoutingOutboundDomain}" | tr ',' '\n')
        if [[ ! -f "${configPath}09_routing.json" ]]; then
            writeRoutingJsonConfig "${configPath}09_routing.json" <<EOF || return 1
{
    "routing":{
        "rules": []
  }
}
EOF
        fi
        updateRoutingJsonConfig "${configPath}09_routing.json" '.routing.rules += [{"type": "field","domain": $domainRules,"outboundTag": "socks5_outbound"}]' --argjson domainRules "${domainRules}"
    fi
}

# 设置 VMess WS TLS 出站
setVMessWSRoutingOutbounds() {
    autoRead vmess_ws_address "请输入VMess+WS+TLS的地址:" setVMessWSTLSAddress
    echoContent title "\n┌─ VMess WS TLS 分流规则 ────────────────────────────"
    menuLine "录入示例：netflix,openai"
    menuClose
    autoRead vmess_ws_domains "请按照上面示例录入域名:" domainList

    if [[ -z ${domainList} ]]; then
        errorCard "域名不可为空"
        setVMessWSRoutingOutbounds
    fi

    if [[ -n "${setVMessWSTLSAddress}" ]]; then
        removeXrayOutbound VMess-out

        echo
        autoRead vmess_ws_port "请输入VMess+WS+TLS的端口:" setVMessWSTLSPort
        echo
        if [[ -z "${setVMessWSTLSPort}" ]]; then
            errorCard "端口不可为空"
        fi

        autoRead vmess_ws_uuid "请输入VMess+WS+TLS的UUID:" setVMessWSTLSUUID
        echo
        if [[ -z "${setVMessWSTLSUUID}" ]]; then
            errorCard "UUID不可为空"
        fi

        autoRead vmess_ws_path "请输入VMess+WS+TLS的Path路径:" setVMessWSTLSPath
        echo
        if [[ -z "${setVMessWSTLSPath}" ]]; then
            errorCard "路径不可为空"
        elif [[ "${setVMessWSTLSPath}" != */* ]]; then
            setVMessWSTLSPath="/${setVMessWSTLSPath}"
        fi
        addXrayOutbound "VMess-out"
        addXrayRouting VMess-out outboundTag "${domainList}"
        reloadCore
        successCard "添加分流成功"
        exit 0
    fi
    errorCard "地址不可为空"
    setVMessWSRoutingOutbounds
}

# 移除 VMess WS TLS 分流
removeVMessWSRouting() {

    removeXrayOutbound VMess-out
    unInstallRouting VMess-out outboundTag

    reloadCore
    successCard "卸载成功"
}

# DNS 分流管理
# 设置 DNS/hosts 覆盖
writeRoutingJsonConfig() {
    local targetPath=$1
    local targetDir targetName tmpPath
    targetDir=$(dirname -- "${targetPath}")
    targetName=$(basename -- "${targetPath}")
    mkdir -p "${targetDir}" || return 1
    padmCreateTempPath tmpPath "${targetDir}/.${targetName}.XXXXXX" || return 1
    if ! cat >"${tmpPath}"; then
        padmRemoveCleanupPath "${tmpPath}"
        return 1
    fi
    commitGeneratedJsonFile "${tmpPath}" "${targetPath}" || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
}

updateRoutingJsonConfig() {
    local targetPath=$1
    local filter=$2
    local targetDir targetName tmpPath
    shift 2
    targetDir=$(dirname -- "${targetPath}")
    targetName=$(basename -- "${targetPath}")
    mkdir -p "${targetDir}" || return 1
    padmCreateTempPath tmpPath "${targetDir}/.${targetName}.XXXXXX" || return 1
    if ! jq "$@" "${filter}" "${targetPath}" >"${tmpPath}"; then
        padmRemoveCleanupPath "${tmpPath}"
        return 1
    fi
    commitGeneratedJsonFile "${tmpPath}" "${targetPath}" || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
}
