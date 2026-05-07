#!/usr/bin/env bash

# 检查ipv6、ipv4
checkIPv6() {
    if ! hasIPv6Connectivity; then
        echoContent red " ---> 不支持ipv6"
        exit 0
    fi
}

# ipv6 分流
ipv6Routing() {
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装，请使用脚本安装"
        menu
        exit 0
    fi

    checkIPv6
    echoContent skyBlue "\n功能 1/${totalProgress} : IPv6分流"
    echoContent red "\n=============================================================="
    echoContent yellow "1.查看已分流域名"
    echoContent yellow "2.添加域名"
    echoContent yellow "3.设置IPv6全局"
    echoContent yellow "4.卸载IPv6分流"
    echoContent red "=============================================================="
    read -r -p "请选择:" ipv6Status
    if [[ "${ipv6Status}" == "1" ]]; then
        showIPv6Routing
        exit 0
    elif [[ "${ipv6Status}" == "2" ]]; then
        echoContent red "=============================================================="
        echoContent yellow "# 注意事项\n"
        echoContent yellow "# 注意事项"
        echoContent yellow "# 请按 README 中的分流说明配置域名或规则 \n"

        read -r -p "请按照上面示例录入域名:" domainList
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

        echoContent green " ---> 添加完毕"

    elif [[ "${ipv6Status}" == "3" ]]; then

        echoContent red "=============================================================="
        echoContent yellow "# 注意事项\n"
        echoContent yellow "1.会删除所有设置的分流规则"
        echoContent yellow "2.会删除IPv6之外的所有出站规则\n"
        read -r -p "是否确认设置？[y/n]:" IPv6OutStatus

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

            echoContent green " ---> IPv6全局出站设置完毕"
        else

            echoContent green " ---> 放弃设置"
            exit 0
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

        echoContent green " ---> IPv6分流卸载成功"
    else
        echoContent red " ---> 选择错误"
        exit 0
    fi

    reloadCore
}

# ipv6分流规则展示
showIPv6Routing() {
    if [[ "${coreInstallType}" == "1" ]]; then
        if [[ -f "${configPath}09_routing.json" ]]; then
            echoContent yellow "Xray-core："
            jq -r -c '.routing.rules[]|select (.outboundTag=="IPv6_out")|.domain' ${configPath}09_routing.json | jq -r
        elif [[ ! -f "${configPath}09_routing.json" && -f "${configPath}IPv6_out.json" ]]; then
            echoContent yellow "Xray-core"
            echoContent green " ---> 已设置IPv6全局分流"
        else
            echoContent yellow " ---> 未安装IPv6分流"
        fi

    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}IPv6_route.json" ]]; then
            echoContent yellow "sing-box"
            jq -r -c '.route.rules[]|select (.outbound=="IPv6_out")' "${singBoxConfigPath}IPv6_route.json" | jq -r
        elif [[ ! -f "${singBoxConfigPath}IPv6_route.json" && -f "${singBoxConfigPath}IPv6_out.json" ]]; then
            echoContent yellow "sing-box"
            echoContent green " ---> 已设置IPv6全局分流"
        else
            echoContent yellow " ---> 未安装IPv6分流"
        fi
    fi
}
# bt下载管理
btTools() {
    if [[ "${coreInstallType}" == "2" ]]; then
        echoContent red "\n ---> 此功能仅支持Xray-core内核，请等待后续更新"
        exit 0
    fi
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装，请使用脚本安装"
        menu
        exit 0
    fi

    echoContent skyBlue "\n┌─ BT 下载管理 ──────────────────────────────────────"

    if [[ -f ${configPath}09_routing.json ]] && grep -q bittorrent <${configPath}09_routing.json; then
        menuLine "当前状态：已禁止下载 BT"
    else
        menuLine "当前状态：允许下载 BT"
    fi

    menuItem 1 "禁止下载 BT" "添加 bittorrent 黑洞路由"
    menuItem 2 "允许下载 BT" "移除 bittorrent 黑洞路由"
    menuClose
    read -r -p "请选择:" btStatus
    if [[ "${btStatus}" == "1" ]]; then

        if [[ -f "${configPath}09_routing.json" ]]; then

            unInstallRouting blackhole_out outboundTag bittorrent

            routing=$(jq -r '.routing.rules += [{"type":"field","outboundTag":"blackhole_out","protocol":["bittorrent"]}]' ${configPath}09_routing.json)

            echo "${routing}" | jq . >${configPath}09_routing.json

        else
            cat <<EOF >${configPath}09_routing.json
{
    "routing":{
        "domainStrategy": "IPOnDemand",
        "rules": [
          {
            "type": "field",
            "outboundTag": "blackhole_out",
            "protocol": [ "bittorrent" ]
          }
        ]
  }
}
EOF
        fi

        installSniffing
        removeXrayOutbound blackhole_out
        addXrayOutbound blackhole_out

        echoContent green " ---> 禁止BT下载"

    elif [[ "${btStatus}" == "2" ]]; then

        unInstallSniffing

        unInstallRouting blackhole_out outboundTag bittorrent

        echoContent green " ---> 允许BT下载"
    else
        echoContent red " ---> 选择错误"
        exit 0
    fi

    reloadCore
}

# 域名黑名单
blacklist() {
    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装，请使用脚本安装"
        menu
        exit 0
    fi

    echoContent skyBlue "\n┌─ 域名黑名单 ───────────────────────────────────────"
    menuItem 1 "查看已屏蔽域名" "列出当前黑洞路由域名"
    menuItem 2 "添加域名" "添加 geosite 或自定义域名"
    menuItem 3 "屏蔽大陆域名 + IP" "添加大陆域名和 IP 黑洞规则"
    menuItem 4 "卸载黑/白名单" "移除相关路由规则"
    menuItem 5 "添加 IP" "添加自定义 IP 黑洞规则"
    menuItem 6 "添加域名白名单" "为指定域名添加直连例外"
    menuClose

    read -r -p "请选择:" blacklistStatus
    if [[ "${blacklistStatus}" == "1" ]]; then
        jq -r -c '.routing.rules[]|select (.outboundTag=="blackhole_out")|.domain' ${configPath}09_routing.json | jq -r
        exit 0
    elif [[ "${blacklistStatus}" == "2" ]]; then
        echoContent red "=============================================================="
        echoContent yellow "# 注意事项\n"
        echoContent yellow "1.规则支持预定义域名列表[https://github.com/v2fly/domain-list-community]"
        echoContent yellow "2.规则支持自定义域名"
        echoContent yellow "3.录入示例:speedtest,facebook,cn,example.com"
        echoContent yellow "4.如果域名在预定义域名列表中存在则使用 geosite:xx，如果不存在则默认使用输入的域名"
        echoContent yellow "5.添加规则为增量配置，不会删除之前设置的内容\n"
        read -r -p "请按照上面示例录入域名:" domainList
        if [[ "${coreInstallType}" == "1" ]]; then
            addXrayRouting blackhole_out outboundTag "${domainList}"
            addXrayOutbound blackhole_out
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            addSingBoxRouteRule "block_domain_outbound" "${domainList}" "block_domain_route"
            addSingBoxOutbound "block_domain_outbound"
            addSingBoxOutbound "01_direct_outbound"
        fi
        echoContent green " ---> 添加完毕"

    elif [[ "${blacklistStatus}" == "3" ]]; then
        local allowDomainList="dl.google.com,apple.com,bing.com,microsoft.com,gstatic,xn--ngstr-lra8j.com,googleapis.com,googleapis.cn"

        if [[ "${coreInstallType}" == "1" ]]; then
            unInstallRouting blackhole_out outboundTag
            unInstallRouting blackhole_ip_out outboundTag

            addXrayRouting blackhole_out outboundTag "cn"
            addXrayIPRouting blackhole_ip_out outboundTag "cn"
            addXrayRouting allow_domain_direct_outbound outboundTag "${allowDomainList}" "top"

            addXrayOutbound blackhole_out
            addXrayOutbound blackhole_ip_out
            addXrayOutbound allow_domain_direct_outbound
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then

            addSingBoxRouteRule "cn_block_outbound" "cn" "cn_block_route"
            addSingBoxGeoIPRouteRule "block_ip_outbound" "cn" "cn_block_ip_route"
            addSingBoxRouteRule "01_direct_outbound" "${allowDomainList}" "00_allow_domain_route"

            addSingBoxOutbound "cn_block_outbound"
            addSingBoxOutbound "block_ip_outbound"
            addSingBoxOutbound "01_direct_outbound"
        fi

        echoContent green " ---> 屏蔽大陆域名+IP完毕"

    elif [[ "${blacklistStatus}" == "4" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            unInstallRouting blackhole_out outboundTag
            unInstallRouting blackhole_ip_out outboundTag
            unInstallRouting allow_domain_direct_outbound outboundTag

            removeXrayOutbound blackhole_ip_out
            removeXrayOutbound allow_domain_direct_outbound
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            removeSingBoxConfig "cn_block_route"
            removeSingBoxConfig "cn_block_outbound"
            removeSingBoxConfig "cn_block_ip_route"
            removeSingBoxConfig "block_ip_route"
            removeSingBoxConfig "block_ip_outbound"

            removeSingBoxConfig "cn_01_google_play_route"
            removeSingBoxConfig "00_allow_domain_route"

            removeSingBoxConfig "block_domain_route"
            removeSingBoxConfig "block_domain_outbound"
        fi
        echoContent green " ---> 域名黑名单/白名单删除完毕"
    elif [[ "${blacklistStatus}" == "5" ]]; then
        echoContent red "=============================================================="
        echoContent yellow "录入示例:1.1.1.1,8.8.8.8,1.1.1.0/24,2400:3200::/32\n"
        read -r -p "请按照上面示例录入IP:" ipList
        if [[ -z "${ipList}" ]]; then
            echoContent red " ---> IP不可为空"
            exit 0
        fi

        if [[ "${coreInstallType}" == "1" ]]; then
            addXrayIPRouting blackhole_ip_out outboundTag "${ipList}"
            addXrayOutbound blackhole_ip_out
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            addSingBoxIPRouteRule "block_ip_outbound" "${ipList}" "block_ip_route"
            addSingBoxOutbound "block_ip_outbound"
        fi
        echoContent green " ---> 添加IP完毕"
    elif [[ "${blacklistStatus}" == "6" ]]; then
        echoContent red "=============================================================="
        echoContent yellow "录入示例:speedtest,openai,google.com\n"
        read -r -p "请按照上面示例录入域名:" allowDomainList
        if [[ -z "${allowDomainList}" ]]; then
            echoContent red " ---> 域名不可为空"
            exit 0
        fi

        if [[ "${coreInstallType}" == "1" ]]; then
            addXrayRouting allow_domain_direct_outbound outboundTag "${allowDomainList}" "top"
            addXrayOutbound allow_domain_direct_outbound
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            addSingBoxRouteRule "01_direct_outbound" "${allowDomainList}" "00_allow_domain_route"
            addSingBoxOutbound "01_direct_outbound"
        fi
        echoContent green " ---> 添加域名白名单完毕"
    else
        echoContent red " ---> 选择错误"
        exit 0
    fi
    reloadCore
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

# 转义grep/regex匹配字符
escapeDLCRegexPattern() {
    # shellcheck disable=SC2016
    # shellcheck disable=SC2001
    echo "$1" | sed -e 's/[.[\*^$()+?{|]/\\&/g'
}

# 根据规则行号向上回溯对应name
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

# 获取规则匹配结果，优先geosite，失败回退domain
getDLCMatchedRuleValue() {
    local inputRule=$1
    local corePath=$2
    local normalizedInput=
    normalizedInput=$(echo "${inputRule}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if isDomainFormat "${normalizedInput}"; then
        local escapedDomain=
        escapedDomain=$(escapeDLCRegexPattern "${normalizedInput}")
        echo "regexp:.*${escapedDomain}.*"
        return
    fi

    local matchedRuleName=
    matchedRuleName=$(getDLCGeositeName "${normalizedInput}" "${corePath}")
    if [[ -n "${matchedRuleName}" ]]; then
        echo "geosite:${matchedRuleName}"
    else
        echo "domain:${normalizedInput}"
    fi
}

# 添加routing配置
addXrayRouting() {

    local tag=$1    # warp-socks
    local type=$2   # outboundTag/inboundTag
    local domain=$3 # 域名
    local rulePosition=$4

    if [[ -z "${tag}" || -z "${type}" || -z "${domain}" ]]; then
        echoContent red " ---> 参数错误"
        exit 0
    fi

    local routingRule=
    if [[ ! -f "${configPath}09_routing.json" ]]; then
        cat <<EOF >${configPath}09_routing.json
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

    while read -r line; do
        if echo "${routingRule}" | grep -q "${line}"; then
            echoContent yellow " ---> ${line}已存在，跳过"
        else
            local matchedRuleValue
            matchedRuleValue=$(getDLCMatchedRuleValue "${line}" "/etc/padm/xray")
            routingRule=$(echo "${routingRule}" | jq -r --arg rule "${matchedRuleValue}" '.domain += [$rule]')
        fi
    done < <(echo "${domain}" | tr ',' '\n')

    unInstallRouting "${tag}" "${type}"
    if ! grep -q "gstatic.com" ${configPath}09_routing.json && [[ "${tag}" == "blackhole_out" ]]; then
        local routing=
        routing=$(jq -r ".routing.rules += [{\"type\": \"field\",\"domain\": [\"domain:gstatic.com\"],\"outboundTag\": \"allow_domain_direct_outbound\"}]" ${configPath}09_routing.json)
        echo "${routing}" | jq . >${configPath}09_routing.json
        addXrayOutbound allow_domain_direct_outbound
    fi

    if [[ "${rulePosition}" == "top" ]]; then
        routing=$(jq -r ".routing.rules = [${routingRule}] + .routing.rules" ${configPath}09_routing.json)
    else
        routing=$(jq -r ".routing.rules += [${routingRule}]" ${configPath}09_routing.json)
    fi
    echo "${routing}" | jq . >${configPath}09_routing.json
}

# 添加 Xray IP 屏蔽路由规则
# 支持 geoip:cn 与自定义 IPv4/IPv6/CIDR
addXrayIPRouting() {

    local tag=$1
    local type=$2
    local ipList=$3

    if [[ -z "${tag}" || -z "${type}" || -z "${ipList}" ]]; then
        echoContent red " ---> 参数错误"
        exit 0
    fi

    if [[ ! -f "${configPath}09_routing.json" ]]; then
        cat <<EOF >${configPath}09_routing.json
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
            echoContent yellow " ---> ${ipRuleValue}已存在，跳过"
        else
            routingRule=$(echo "${routingRule}" | jq -r '.ip += ["'"${ipRuleValue}"'"]')
        fi
    done < <(echo "${ipList}" | tr ',' '\n')

    unInstallRouting "${tag}" "${type}"
    local routing=
    routing=$(jq -r ".routing.rules += [${routingRule}]" ${configPath}09_routing.json)
    echo "${routing}" | jq . >${configPath}09_routing.json
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
    ipCIDR=$(echo "${ipList}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | sort -n | uniq | jq -R . | jq -s .)

    cat <<EOF >"${singBoxConfigPath}${routingName}.json"
{
  "route": {
    "rules": [
      {
        "ip_cidr": ${ipCIDR},
        "outbound": "${outboundTag}"
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

    cat <<EOF >"${singBoxConfigPath}${routingName}.json"
{
  "route": {
    "rules": [
      {
        "rule_set": [
          "geoip_${geoipCode}_${routingName}"
        ],
        "outbound": "${outboundTag}"
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
# 根据tag卸载Routing
unInstallRouting() {
    local tag=$1
    local type=$2
    local protocol=$3

    if [[ -f "${configPath}09_routing.json" ]]; then
        local routing=
        if [[ -n "${protocol}" ]]; then
            routing=$(jq -r "del(.routing.rules[] | select(.${type} == \"${tag}\" and (.protocol | index(\"${protocol}\"))))" ${configPath}09_routing.json)
            echo "${routing}" | jq . >${configPath}09_routing.json
        else
            routing=$(jq -r "del(.routing.rules[] | select(.${type} == \"${tag}\" and (.protocol == null )))" ${configPath}09_routing.json)
            echo "${routing}" | jq . >${configPath}09_routing.json
        fi
    fi
}

# 卸载嗅探
unInstallSniffing() {

    find ${configPath} -name "*inbounds.json*" | awk -F "[c][o][n][f][/]" '{print $2}' | while read -r inbound; do
        if grep -q "destOverride" <"${configPath}${inbound}"; then
            sniffing=$(jq -r 'del(.inbounds[0].sniffing)' "${configPath}${inbound}")
            echo "${sniffing}" | jq . >"${configPath}${inbound}"
        fi
    done

}

# 安装嗅探
installSniffing() {
    readInstallType
    if [[ "${coreInstallType}" == "1" ]]; then
        if [[ -f "${configPath}02_VLESS_TCP_inbounds.json" ]]; then
            if ! grep -q "destOverride" <"${configPath}02_VLESS_TCP_inbounds.json"; then
                sniffing=$(jq -r '.inbounds[0].sniffing = {"enabled":true,"destOverride":["http","tls","quic"]}' "${configPath}02_VLESS_TCP_inbounds.json")
                echo "${sniffing}" | jq . >"${configPath}02_VLESS_TCP_inbounds.json"
            fi
        fi
    fi
}

# 读取第三方warp配置
readConfigWarpReg() {
    if [[ ! -f "/etc/padm/warp/config" ]]; then
        /etc/padm/warp/warp-reg >/etc/padm/warp/config
    fi

    secretKeyWarpReg=$(grep <"/etc/padm/warp/config" private_key | awk '{print $2}')

    addressWarpReg=$(grep <"/etc/padm/warp/config" v6 | awk '{print $2}')

    publicKeyWarpReg=$(grep <"/etc/padm/warp/config" public_key | awk '{print $2}')

    reservedWarpReg=$(grep <"/etc/padm/warp/config" reserved | awk -F "[:]" '{print $2}')

}
# 安装warp-reg工具
installWarpReg() {
    if [[ ! -f "/etc/padm/warp/warp-reg" ]]; then
        echo
        echoContent yellow "# 注意事项"
        echoContent yellow "# 依赖第三方程序，请熟知其中风险"
        echoContent yellow "# 项目地址：https://github.com/badafans/warp-reg \n"

        read -r -p "warp-reg未安装，是否安装 ？[y/n]:" installWarpRegStatus

        if [[ "${installWarpRegStatus}" == "y" ]]; then

            if ! downloadGitHubReleaseAsset -P /etc/padm/warp/ badafans/warp-reg v1.0 "${warpRegCoreCPUVendor}"; then
                echoContent red " ---> warp-reg下载失败"
                exit 1
            fi
            if [[ ! -s "/etc/padm/warp/${warpRegCoreCPUVendor}" ]]; then
                echoContent red " ---> warp-reg文件异常"
                exit 1
            fi
            mv "/etc/padm/warp/${warpRegCoreCPUVendor}" /etc/padm/warp/warp-reg
            chmod 655 /etc/padm/warp/warp-reg

        else
            echoContent yellow " ---> 放弃安装"
            exit 0
        fi
    fi
}

# 展示warp分流域名
showWireGuardDomain() {
    local type=$1
    # xray
    if [[ "${coreInstallType}" == "1" ]]; then
        if [[ -f "${configPath}09_routing.json" ]]; then
            echoContent yellow "Xray-core"
            jq -r -c '.routing.rules[]|select (.outboundTag=="wireguard_out_'"${type}"'")|.domain' ${configPath}09_routing.json | jq -r
        elif [[ ! -f "${configPath}09_routing.json" && -f "${configPath}wireguard_out_${type}.json" ]]; then
            echoContent yellow "Xray-core"
            echoContent green " ---> 已设置warp ${type}全局分流"
        else
            echoContent yellow " ---> 未安装warp ${type}分流"
        fi
    fi

    # sing-box
    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}wireguard_endpoints_${type}_route.json" ]]; then
            echoContent yellow "sing-box"
            jq -r -c '.route.rules[]' "${singBoxConfigPath}wireguard_endpoints_${type}_route.json" | jq -r
        elif [[ ! -f "${singBoxConfigPath}wireguard_endpoints_${type}_route.json" && -f "${singBoxConfigPath}wireguard_endpoints_${type}.json" ]]; then
            echoContent yellow "sing-box"
            echoContent green " ---> 已设置warp ${type}全局分流"
        else
            echoContent yellow " ---> 未安装warp ${type}分流"
        fi
    fi

}

# 添加WireGuard分流
addWireGuardRoute() {
    local type=$1
    local tag=$2
    local domainList=$3
    # xray
    if [[ "${coreInstallType}" == "1" ]]; then

        addXrayRouting "wireguard_out_${type}" "${tag}" "${domainList}"
        addXrayOutbound "wireguard_out_${type}"
    fi
    # sing-box
    if [[ -n "${singBoxConfigPath}" ]]; then

        # rule
        addSingBoxRouteRule "wireguard_endpoints_${type}" "${domainList}" "wireguard_endpoints_${type}_route"
        # addSingBoxOutbound "wireguard_out_${type}" "wireguard_out"
        if [[ -n "${domainList}" ]]; then
            addSingBoxOutbound "01_direct_outbound"
        fi

        # outbound
        addSingBoxWireGuardEndpoints "${type}"
    fi
}

# 卸载wireGuard
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
# 移除WireGuard分流
removeWireGuardRoute() {
    local type=$1
    if [[ "${coreInstallType}" == "1" ]]; then

        unInstallRouting wireguard_out_"${type}" outboundTag

        removeXrayOutbound "wireguard_out_${type}"
        if [[ ! -f "${configPath}IPv4_out.json" ]]; then
            addXrayOutbound IPv4_out
        fi
    fi

    # sing-box
    if [[ -n "${singBoxConfigPath}" ]]; then
        removeSingBoxRouteRule "wireguard_endpoints_${type}"
    fi

    unInstallWireGuard "${type}"
}
# warp分流-第三方IPv4
warpRoutingReg() {
    local type=$2
    echoContent skyBlue "\n进度  $1/${totalProgress} : WARP分流[第三方]"
    echoContent red "=============================================================="

    echoContent yellow "1.查看已分流域名"
    echoContent yellow "2.添加域名"
    echoContent yellow "3.设置WARP全局"
    echoContent yellow "4.卸载WARP分流"
    echoContent red "=============================================================="
    read -r -p "请选择:" warpStatus
    installWarpReg
    readConfigWarpReg
    local address=
    if [[ ${type} == "IPv4" ]]; then
        address="172.16.0.2/32"
    elif [[ ${type} == "IPv6" ]]; then
        address="${addressWarpReg}/128"
    else
        echoContent red " ---> IP获取失败，退出安装"
    fi

    if [[ "${warpStatus}" == "1" ]]; then
        showWireGuardDomain "${type}"
        exit 0
    elif [[ "${warpStatus}" == "2" ]]; then
        echoContent yellow "# 注意事项"
        echoContent yellow "# 支持sing-box、Xray-core"
        echoContent yellow "# 请按 README 中的分流说明配置域名或规则 \n"

        read -r -p "请按照上面示例录入域名:" domainList
        addWireGuardRoute "${type}" outboundTag "${domainList}"
        echoContent green " ---> 添加完毕"

    elif [[ "${warpStatus}" == "3" ]]; then

        echoContent red "=============================================================="
        echoContent yellow "# 注意事项\n"
        echoContent yellow "1.会删除所有设置的分流规则"
        echoContent yellow "2.会删除除WARP[第三方]之外的所有出站规则\n"
        read -r -p "是否确认设置？[y/n]:" warpOutStatus

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

                # outbound
                # addSingBoxOutbound "wireguard_out_${type}" "wireguard_out"

            fi

            echoContent green " ---> WARP全局出站设置完毕"
        else
            echoContent green " ---> 放弃设置"
            exit 0
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

        echoContent green " ---> 卸载WARP ${type}分流完毕"
    else

        echoContent red " ---> 选择错误"
        exit 0
    fi
    reloadCore
}

# 分流工具
routingToolsMenu() {
    echoContent skyBlue "\n┌─ 分流工具 ─────────────────────────────────────────"
    menuLine "用于服务端流量分流，可用于解锁 ChatGPT、流媒体等内容"
    menuItem 1 "WARP 分流 IPv4" "通过第三方 WARP IPv4 出站"
    menuItem 2 "WARP 分流 IPv6" "通过第三方 WARP IPv6 出站"
    menuItem 3 "IPv6 分流" "配置 IPv6 出站分流"
    menuItem 4 "Socks5 分流" "替换任意门分流，接入外部 Socks5"
    menuItem 5 "DNS 分流" "按 DNS 规则分流"
    menuItem 7 "SNI 反向代理分流" "按 SNI 转发到后端服务"
    menuClose

    read -r -p "请选择:" selectType

    case ${selectType} in
    1)
        warpRoutingReg 1 IPv4
        ;;
    2)
        warpRoutingReg 1 IPv6
        ;;
    3)
        ipv6Routing 1
        ;;
    4)
        socks5Routing
        ;;
    5)
        dnsRouting 1
        ;;
        #    6)
        #        if [[ -n "${singBoxConfigPath}" ]]; then
        #            echoContent red "\n ---> 此功能不支持Hysteria2、Tuic"
        #        fi
        #        vmessWSRouting 1
        #        ;;
    7)
        if [[ -n "${singBoxConfigPath}" ]]; then
            echoContent red "\n ---> 此功能不支持Hysteria2、Tuic"
        fi
        sniRouting 1
        ;;
    esac

}

# VMess+WS+TLS 分流
vmessWSRouting() {
    echoContent skyBlue "\n功能 1/${totalProgress} : VMess+WS+TLS 分流"
    echoContent red "\n=============================================================="
    echoContent yellow "# 注意事项"
    echoContent yellow "# 请按 README 中的分流说明配置域名或规则 \n"

    echoContent yellow "1.添加出站"
    echoContent yellow "2.卸载"
    read -r -p "请选择:" selectType

    case ${selectType} in
    1)
        setVMessWSRoutingOutbounds
        ;;
    2)
        removeVMessWSRouting
        ;;
    esac
}
# Socks5分流
socks5Routing() {
    if [[ -z "${coreInstallType}" ]]; then
        echoContent red " ---> 未安装任意协议，请使用 1.安装管理 进行安装后使用"
        exit 0
    fi
    echoContent skyBlue "\n┌─ Socks5 分流 ──────────────────────────────────────"
    menuLine "流量明文访问，仅限正常网络环境下设备间流量转发"
    menuLine "请按 README 中的分流说明配置域名或规则"
    menuItem 1 "Socks5 出站" "转发机/代理机配置"
    menuItem 2 "Socks5 入站" "解锁机/落地机配置"
    menuItem 3 "卸载" "移除 Socks5 分流配置"
    menuClose
    read -r -p "请选择:" selectType

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
    esac
}
# Socks5入站菜单
socks5InboundRoutingMenu() {
    readInstallType
    echoContent skyBlue "\n功能 1/1 : Socks5入站"
    echoContent red "\n=============================================================="

    echoContent yellow "1.安装Socks5入站"
    echoContent yellow "2.查看分流规则"
    echoContent yellow "3.添加分流规则"
    echoContent yellow "4.查看入站配置"
    read -r -p "请选择:" selectType
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
            echoContent yellow "\n ---> 下列内容需要配置到其他机器的出站，请不要进行代理行为\n"
            echoContent green " 端口：$(jq .inbounds[0].listen_port ${singBoxConfigPath}20_socks5_inbounds.json)"
            echoContent green " 用户名称：$(jq -r .inbounds[0].users[0].username ${singBoxConfigPath}20_socks5_inbounds.json)"
            echoContent green " 用户密码：$(jq -r .inbounds[0].users[0].password ${singBoxConfigPath}20_socks5_inbounds.json)"
        else
            echoContent red " ---> 未安装相应功能"
            socks5InboundRoutingMenu
        fi
        ;;
    esac

}

# Socks5出站菜单
socks5OutboundRoutingMenu() {
    echoContent skyBlue "\n功能 1/1 : Socks5出站"
    echoContent red "\n=============================================================="

    echoContent yellow "1.安装Socks5出站"
    echoContent yellow "2.设置Socks5全局转发"
    echoContent yellow "3.查看分流规则"
    echoContent yellow "4.添加分流规则"
    read -r -p "请选择:" selectType
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
    esac

}

# socks5全局
setSocks5OutboundRoutingAll() {

    echoContent red "=============================================================="
    echoContent yellow "# 注意事项\n"
    echoContent yellow "1.会删除所有已经设置的分流规则，包括其他分流（warp、IPv6等）"
    echoContent yellow "2.会删除Socks5之外的所有出站规则\n"
    read -r -p "是否确认设置？[y/n]:" socksOutStatus

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

        echoContent green " ---> Socks5全局出站设置完毕"
    fi
}
# socks5 分流规则
showSingBoxRoutingRules() {
    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}$1.json" ]]; then
            jq .route.rules "${singBoxConfigPath}$1.json"
        elif [[ "$1" == "socks5_01_outbound_route" && -f "${singBoxConfigPath}socks5_outbound.json" ]]; then
            echoContent yellow "已安装 sing-box socks5全局出站分流"
            echoContent yellow "\n出站分流配置："
            echoContent skyBlue "$(jq .outbounds[0] ${singBoxConfigPath}socks5_outbound.json)"
        elif [[ "$1" == "socks5_02_inbound_route" && -f "${singBoxConfigPath}20_socks5_inbounds.json" ]]; then
            echoContent yellow "已安装 sing-box socks5全局入站分流"
            echoContent yellow "\n出站分流配置："
            echoContent skyBlue "$(jq .outbounds[0] ${singBoxConfigPath}socks5_outbound.json)"
        fi
    fi
}

# xray内核分流规则
showXrayRoutingRules() {
    if [[ "${coreInstallType}" == "1" ]]; then
        if [[ -f "${configPath}09_routing.json" ]]; then
            jq ".routing.rules[]|select(.outboundTag==\"$1\")" "${configPath}09_routing.json"

            echoContent yellow "\n已安装 xray-core socks5全局出站分流"
            echoContent yellow "\n出站分流配置："
            echoContent skyBlue "$(jq .outbounds[0].settings.servers[0] ${configPath}socks5_outbound.json)"

        elif [[ "$1" == "socks5_outbound" && -f "${configPath}socks5_outbound.json" ]]; then
            echoContent yellow "\n已安装 xray-core socks5全局出站分流"
            echoContent yellow "\n出站分流配置："
            echoContent skyBlue "$(jq .outbounds[0].settings.servers[0] ${configPath}socks5_outbound.json)"
        fi
    fi
}

# 卸载Socks5分流
removeSocks5Routing() {
    echoContent skyBlue "\n功能 1/1 : 卸载Socks5分流"
    echoContent red "\n=============================================================="

    echoContent yellow "1.卸载Socks5出站"
    echoContent yellow "2.卸载Socks5入站"
    echoContent yellow "3.卸载全部"
    read -r -p "请选择:" unInstallSocks5RoutingStatus
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
    else
        echoContent red " ---> 选择错误"
        exit 0
    fi
    echoContent green " ---> 卸载完毕"
    reloadCore
}
# Socks5入站
setSocks5Inbound() {

    echoContent yellow "\n==================== 配置 Socks5 入站(解锁机、落地机) =====================\n"
    echoContent skyBlue "\n开始配置Socks5协议入站端口"
    echo
    mapfile -t result < <(initSingBoxPort "${singBoxSocks5Port}")
    echoContent green "\n ---> 入站Socks5端口：${result[-1]}"
    echoContent green "\n ---> 此端口需要配置到其他机器出站，请不要进行代理行为"

    echoContent yellow "\n请输入自定义UUID[需合法]，[回车]随机UUID"
    read -r -p 'UUID:' socks5RoutingUUID
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

    echoContent yellow "\n请选择分流域名DNS解析类型"
    echoContent yellow "# 注意事项：需要保证vps支持相应的DNS解析"
    echoContent yellow "1.IPv4[回车默认]"
    echoContent yellow "2.IPv6"

    read -r -p 'IP类型:' socks5InboundDomainStrategyStatus
    local domainStrategy=
    if [[ -z "${socks5InboundDomainStrategyStatus}" || "${socks5InboundDomainStrategyStatus}" == "1" ]]; then
        domainStrategy="ipv4_only"
    elif [[ "${socks5InboundDomainStrategyStatus}" == "2" ]]; then
        domainStrategy="ipv6_only"
    else
        echoContent red " ---> 选择类型错误"
        exit 0
    fi
    cat <<EOF >/etc/padm/sing-box/conf/config/20_socks5_inbounds.json
{
    "inbounds":[
        {
          "type": "socks",
          "listen":"::",
          "listen_port":${result[-1]},
          "tag":"socks5_inbound",
          "users":[
            {
                  "username": "${socks5RoutingUUID}",
                  "password": "${socks5RoutingUUID}"
            }
          ]
        }
    ]
}
EOF
    setStrategyRouting socks5_inbound "${domainStrategy}"
}

# 初始化sing-box rule配置
initSingBoxRules() {
    local domainRules=[]
    local ruleSet=[]
    while read -r line; do
        local normalizedLine=
        normalizedLine=$(echo "${line}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if isDomainFormat "${normalizedLine}"; then
            local escapedDomain=
            escapedDomain=${normalizedLine//./\\.}
            domainRules=$(echo "${domainRules}" | jq -r --arg reg ".*${escapedDomain}.*" '. += [$reg]')
        else
            local matchedRuleName
            matchedRuleName=$(getDLCGeositeName "${normalizedLine}" "/etc/padm/sing-box")

            if [[ -n "${matchedRuleName}" ]]; then
                ruleSet=$(echo "${ruleSet}" | jq -r ". += [{\"tag\":\"${matchedRuleName}_$2\",\"type\":\"remote\",\"format\":\"binary\",\"url\":\"https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-${matchedRuleName}.srs\",\"download_detour\":\"01_direct_outbound\"}]")
            else
                domainRules=$(echo "${domainRules}" | jq -r --arg reg "^([a-zA-Z0-9_-]+\\.)*${normalizedLine//./\\.}" '. += [$reg]')
            fi
        fi
    done < <(echo "$1" | tr ',' '\n' | grep -v '^$' | sort -n | uniq | paste -sd ',' | tr ',' '\n')
    echo "{ \"domainRules\":${domainRules},\"ruleSet\":${ruleSet}}"
}

# socks5 inbound routing规则
setSocks5InboundRouting() {

    singBoxConfigPath=/etc/padm/sing-box/conf/config/

    if [[ "$1" == "addRules" && ! -f "${singBoxConfigPath}socks5_02_inbound_route.json" && ! -f "${configPath}09_routing.json" ]]; then
        echoContent red " ---> 请安装入站分流后再添加分流规则"
        echoContent red " ---> 如已选择允许所有网站，请重新安装分流后设置规则"
        exit 0
    fi
    local socks5InboundRoutingIPs=
    if [[ "$1" == "addRules" ]]; then
        socks5InboundRoutingIPs=$(jq .route.rules[0].source_ip_cidr "${singBoxConfigPath}socks5_02_inbound_route.json")
    else
        echoContent red "=============================================================="
        echoContent skyBlue "请输入允许访问的IP地址，多个IP英文逗号隔开。例如:1.1.1.1,2.2.2.2\n"
        read -r -p "IP:" socks5InboundRoutingIPs

        if [[ -z "${socks5InboundRoutingIPs}" ]]; then
            echoContent red " ---> IP不可为空"
            exit 0
        fi
        socks5InboundRoutingIPs=$(echo "\"${socks5InboundRoutingIPs}"\" | jq -c '.|split(",")')
    fi

    echoContent red "=============================================================="
    echoContent skyBlue "请输入要分流的域名\n"
    echoContent yellow "支持Xray-core geosite匹配，支持sing-box1.8+ rule_set匹配\n"
    echoContent yellow "非增量添加，会替换原有规则\n"
    echoContent yellow "当输入的规则匹配到geosite或者rule_set后会使用相应的规则\n"
    echoContent yellow "如无法匹配则，则使用domain精确匹配\n"

    read -r -p "是否允许所有网站？请选择[y/n]:" socks5InboundRoutingDomainStatus
    if [[ "${socks5InboundRoutingDomainStatus}" == "y" ]]; then
        addSingBoxRouteRule "01_direct_outbound" "" "socks5_02_inbound_route"
        local route=
        route=$(jq ".route.rules[0].inbound = [\"socks5_inbound\"]" "${singBoxConfigPath}socks5_02_inbound_route.json")
        route=$(echo "${route}" | jq ".route.rules[0].source_ip_cidr=${socks5InboundRoutingIPs}")
        echo "${route}" | jq . >"${singBoxConfigPath}socks5_02_inbound_route.json"

        addSingBoxOutbound block
        addSingBoxOutbound "01_direct_outbound"
    else
        echoContent yellow "录入示例:netflix,openai,example.com\n"
        read -r -p "域名:" socks5InboundRoutingDomain
        if [[ -z "${socks5InboundRoutingDomain}" ]]; then
            echoContent red " ---> 域名不可为空"
            exit 0
        fi
        addSingBoxRouteRule "01_direct_outbound" "${socks5InboundRoutingDomain}" "socks5_02_inbound_route"
        local route=
        route=$(jq ".route.rules[0].inbound = [\"socks5_inbound\"]" "${singBoxConfigPath}socks5_02_inbound_route.json")
        route=$(echo "${route}" | jq ".route.rules[0].source_ip_cidr=${socks5InboundRoutingIPs}")
        echo "${route}" | jq . >"${singBoxConfigPath}socks5_02_inbound_route.json"

        addSingBoxOutbound block
        addSingBoxOutbound "01_direct_outbound"
    fi

}

# 设置sniff routing规则
setSniffRouting() {
    cat <<EOF >"/etc/padm/sing-box/conf/config/sniff.json"
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

# 设置sniff routing规则
setStrategyRouting() {
    local tag=$1
    local strategy=$2
    cat <<EOF >"/etc/padm/sing-box/conf/config/strategy_${strategy}_${tag}.json"
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
# socks5 出站
setSocks5Outbound() {

    echoContent yellow "\n==================== 配置 Socks5 出站（转发机、代理机） =====================\n"
    echo
    read -r -p "请输入落地机IP地址:" socks5RoutingOutboundIP
    if [[ -z "${socks5RoutingOutboundIP}" ]]; then
        echoContent red " ---> IP不可为空"
        exit 0
    fi
    echo
    read -r -p "请输入落地机端口:" socks5RoutingOutboundPort
    if [[ -z "${socks5RoutingOutboundPort}" ]]; then
        echoContent red " ---> 端口不可为空"
        exit 0
    fi
    echo
    read -r -p "请输入用户名:" socks5RoutingOutboundUserName
    if [[ -z "${socks5RoutingOutboundUserName}" ]]; then
        echoContent red " ---> 用户名不可为空"
        exit 0
    fi
    echo
    read -r -p "请输入用户密码:" socks5RoutingOutboundPassword
    if [[ -z "${socks5RoutingOutboundPassword}" ]]; then
        echoContent red " ---> 用户密码不可为空"
        exit 0
    fi
    echo
    if [[ -n "${singBoxConfigPath}" ]]; then
        cat <<EOF >"${singBoxConfigPath}socks5_outbound.json"
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

# socks5 outbound routing规则
setSocks5OutboundRouting() {

    if [[ "$1" == "addRules" && ! -f "${singBoxConfigPath}socks5_01_outbound_route.json" && ! -f "${configPath}09_routing.json" ]]; then
        echoContent red " ---> 请安装出站分流后再添加分流规则"
        exit 0
    fi

    echoContent red "=============================================================="
    echoContent skyBlue "请输入要分流的域名\n"
    echoContent yellow "支持Xray-core geosite匹配，支持sing-box1.8+ rule_set匹配\n"
    echoContent yellow "非增量添加，会替换原有规则\n"
    echoContent yellow "当输入的规则匹配到geosite或者rule_set后会使用相应的规则\n"
    echoContent yellow "如无法匹配则，则使用domain精确匹配\n"
    echoContent yellow "录入示例:netflix,openai,example.com\n"
    read -r -p "域名:" socks5RoutingOutboundDomain
    if [[ -z "${socks5RoutingOutboundDomain}" ]]; then
        echoContent red " ---> IP不可为空"
        exit 0
    fi
    addSingBoxRouteRule "socks5_outbound" "${socks5RoutingOutboundDomain}" "socks5_01_outbound_route"
    addSingBoxOutbound "01_direct_outbound"

    if [[ "${coreInstallType}" == "1" ]]; then

        unInstallRouting "socks5_outbound" "outboundTag"
        local domainRules=[]
        while read -r line; do
            if echo "${routingRule}" | grep -q "${line}"; then
                echoContent yellow " ---> ${line}已存在，跳过"
            else
                local matchedRuleValue
                matchedRuleValue=$(getDLCMatchedRuleValue "${line}" "/etc/padm/xray")
                domainRules=$(echo "${domainRules}" | jq -r --arg rule "${matchedRuleValue}" '. += [$rule]')
            fi
        done < <(echo "${socks5RoutingOutboundDomain}" | tr ',' '\n')
        if [[ ! -f "${configPath}09_routing.json" ]]; then
            cat <<EOF >${configPath}09_routing.json
{
    "routing":{
        "rules": []
  }
}
EOF
        fi
        routing=$(jq -r ".routing.rules += [{\"type\": \"field\",\"domain\": ${domainRules},\"outboundTag\": \"socks5_outbound\"}]" ${configPath}09_routing.json)
        echo "${routing}" | jq . >${configPath}09_routing.json
    fi
}

# 设置VMess+WS+TLS【仅出站】
setVMessWSRoutingOutbounds() {
    read -r -p "请输入VMess+WS+TLS的地址:" setVMessWSTLSAddress
    echoContent red "=============================================================="
    echoContent yellow "录入示例:netflix,openai\n"
    read -r -p "请按照上面示例录入域名:" domainList

    if [[ -z ${domainList} ]]; then
        echoContent red " ---> 域名不可为空"
        setVMessWSRoutingOutbounds
    fi

    if [[ -n "${setVMessWSTLSAddress}" ]]; then
        removeXrayOutbound VMess-out

        echo
        read -r -p "请输入VMess+WS+TLS的端口:" setVMessWSTLSPort
        echo
        if [[ -z "${setVMessWSTLSPort}" ]]; then
            echoContent red " ---> 端口不可为空"
        fi

        read -r -p "请输入VMess+WS+TLS的UUID:" setVMessWSTLSUUID
        echo
        if [[ -z "${setVMessWSTLSUUID}" ]]; then
            echoContent red " ---> UUID不可为空"
        fi

        read -r -p "请输入VMess+WS+TLS的Path路径:" setVMessWSTLSPath
        echo
        if [[ -z "${setVMessWSTLSPath}" ]]; then
            echoContent red " ---> 路径不可为空"
        elif ! echo "${setVMessWSTLSPath}" | grep -q "/"; then
            setVMessWSTLSPath="/${setVMessWSTLSPath}"
        fi
        addXrayOutbound "VMess-out"
        addXrayRouting VMess-out outboundTag "${domainList}"
        reloadCore
        echoContent green " ---> 添加分流成功"
        exit 0
    fi
    echoContent red " ---> 地址不可为空"
    setVMessWSRoutingOutbounds
}

# 移除VMess+WS+TLS分流
removeVMessWSRouting() {

    removeXrayOutbound VMess-out
    unInstallRouting VMess-out outboundTag

    reloadCore
    echoContent green " ---> 卸载成功"
}

# dns分流
dnsRouting() {

    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装，请使用脚本安装"
        menu
        exit 0
    fi
    echoContent skyBlue "\n功能 1/${totalProgress} : DNS分流"
    echoContent red "\n=============================================================="
    echoContent yellow "# 注意事项"
    echoContent yellow "# 请按 README 中的分流说明配置域名或规则 \n"

    echoContent yellow "1.添加"
    echoContent yellow "2.卸载"
    read -r -p "请选择:" selectType

    case ${selectType} in
    1)
        setUnlockDNS
        ;;
    2)
        removeUnlockDNS
        ;;
    esac
}

# SNI反向代理分流
sniRouting() {

    if [[ -z "${configPath}" ]]; then
        echoContent red " ---> 未安装，请使用脚本安装"
        menu
        exit 0
    fi
    echoContent skyBlue "\n功能 1/${totalProgress} : SNI反向代理分流"
    echoContent red "\n=============================================================="
    echoContent yellow "# 注意事项"
    echoContent yellow "# 请按 README 中的分流说明配置域名或规则 \n"
    echoContent yellow "# sing-box不支持规则集，仅支持指定域名。\n"

    echoContent yellow "1.添加"
    echoContent yellow "2.卸载"
    read -r -p "请选择:" selectType

    case ${selectType} in
    1)
        setUnlockSNI
        ;;
    2)
        removeUnlockSNI
        ;;
    esac
}
# 设置SNI分流
setUnlockSNI() {
    read -r -p "请输入分流的SNI IP:" setSNIP
    if [[ -n ${setSNIP} ]]; then
        echoContent red "=============================================================="

        if [[ "${coreInstallType}" == 1 ]]; then
            echoContent yellow "录入示例:netflix,disney,hulu"
            read -r -p "请按照上面示例录入域名:" xrayDomainList
            local hosts={}
            while read -r domain; do
                local matchedRuleValue
                matchedRuleValue=$(getDLCMatchedRuleValue "${domain}" "/etc/padm/xray")
                hosts=$(echo "${hosts}" | jq -r --arg key "${matchedRuleValue}" --arg value "${setSNIP}" '. + {($key):$value}')
            done < <(echo "${xrayDomainList}" | tr ',' '\n')
            cat <<EOF >${configPath}11_dns.json
{
    "dns": {
        "hosts":${hosts},
        "servers": [
            "8.8.8.8",
            "1.1.1.1"
        ]
    }
}
EOF
        fi
        if [[ -n "${singBoxConfigPath}" ]]; then
            echoContent yellow "录入示例:www.netflix.com,www.google.com"
            read -r -p "请按照上面示例录入域名:" singboxDomainList
            addSingBoxDNSConfig "${setSNIP}" "${singboxDomainList}" "predefined"
        fi
        echoContent yellow " ---> SNI反向代理分流成功"
        reloadCore
    else
        echoContent red " ---> SNI IP不可为空"
    fi
    exit 0
}

# 添加xray dns 配置
addXrayDNSConfig() {
    local ip=$1
    local domainList=$2
    local domains=[]
    while read -r line; do
        local matchedRuleValue
        matchedRuleValue=$(getDLCMatchedRuleValue "${line}" "/etc/padm/xray")
        domains=$(echo "${domains}" | jq -r --arg rule "${matchedRuleValue}" '. += [$rule]')
    done < <(echo "${domainList}" | tr ',' '\n')

    if [[ "${coreInstallType}" == "1" ]]; then

        cat <<EOF >${configPath}11_dns.json
{
    "dns": {
        "servers": [
            {
                "address": "${ip}",
                "port": 53,
                "domains": ${domains}
            },
        "localhost"
        ]
    }
}
EOF
    fi
}

# 添加sing-box dns配置
addSingBoxDNSConfig() {
    local ip=$1
    local domainList=$2
    local actionType=$3

    local rules=
    rules=$(initSingBoxRules "${domainList}" "dns")
    # domain精确匹配规则
    local domainRules=
    domainRules=$(echo "${rules}" | jq .domainRules)

    # ruleSet规则集
    local ruleSet=
    ruleSet=$(echo "${rules}" | jq .ruleSet)

    # ruleSet规则tag
    local ruleSetTag=[]
    if [[ "$(echo "${ruleSet}" | jq '.|length')" != "0" ]]; then
        ruleSetTag=$(echo "${ruleSet}" | jq '.|map(.tag)')
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ "${actionType}" == "predefined" ]]; then
            local predefined={}
            while read -r line; do
                predefined=$(echo "${predefined}" | jq ".\"${line}\"=\"${ip}\"")
            done < <(echo "${domainList}" | tr ',' '\n' | grep -v '^$' | sort -n | uniq | paste -sd ',' | tr ',' '\n')

            cat <<EOF >"${singBoxConfigPath}dns.json"
{
  "dns": {
    "servers": [
        {
            "tag": "local",
            "type": "local"
        },
        {
            "tag": "hosts",
            "type": "hosts",
            "predefined": ${predefined}
        }
    ],
    "rules": [
        {
            "domain_regex":${domainRules},
            "server":"hosts"
        }
    ]
  }
}
EOF
        else
            cat <<EOF >"${singBoxConfigPath}dns.json"
{
  "dns": {
    "servers": [
      {
        "tag": "local",
        "type": "local"
      },
      {
        "tag": "dnsRouting",
        "type": "udp",
        "server": "${ip}"
      }
    ],
    "rules": [
      {
        "rule_set": ${ruleSetTag},
        "domain_regex": ${domainRules},
        "server":"dnsRouting"
      }
    ]
  },
  "route":{
    "rule_set":${ruleSet}
  }
}
EOF
        fi
    fi
}
# 设置dns
setUnlockDNS() {
    read -r -p "请输入分流的DNS:" setDNS
    if [[ -n ${setDNS} ]]; then
        echoContent red "=============================================================="
        echoContent yellow "录入示例:netflix,disney,hulu"
        read -r -p "请按照上面示例录入域名:" domainList

        if [[ "${coreInstallType}" == "1" ]]; then
            addXrayDNSConfig "${setDNS}" "${domainList}"
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            addSingBoxOutbound 01_direct_outbound
            addSingBoxDNSConfig "${setDNS}" "${domainList}"
        fi

        reloadCore

        echoContent yellow "\n ---> 如还无法观看可以尝试以下两种方案"
        echoContent yellow " 1.重启vps"
        echoContent yellow " 2.卸载dns解锁后，修改本地的[/etc/resolv.conf]DNS设置并重启vps\n"
    else
        echoContent red " ---> dns不可为空"
    fi
    exit 0
}

# 移除 DNS分流
removeUnlockDNS() {
    if [[ "${coreInstallType}" == "1" && -f "${configPath}11_dns.json" ]]; then
        cat <<EOF >${configPath}11_dns.json
{
	"dns": {
		"servers": [
			"localhost"
		]
	}
}
EOF
    fi

    if [[ "${coreInstallType}" == "2" && -f "${singBoxConfigPath}dns.json" ]]; then
        cat <<EOF >${singBoxConfigPath}dns.json
{
    "dns": {
        "servers":[
            {
                "type":"local"
            }
        ]
    }
}
EOF
    fi

    reloadCore

    echoContent green " ---> 卸载成功"

    exit 0
}

# 移除SNI分流
removeUnlockSNI() {
    if [[ "${coreInstallType}" == 1 ]]; then
        cat <<EOF >${configPath}11_dns.json
{
    "dns": {
        "servers": [
            "localhost"
        ]
    }
}
EOF
    fi

    if [[ "${coreInstallType}" == "2" && -f "${singBoxConfigPath}dns.json" ]]; then
        cat <<EOF >${singBoxConfigPath}dns.json
{
    "dns": {
        "servers":[
            {
                "type":"local"
            }
        ]
    }
}
EOF
    fi

    reloadCore
    echoContent green " ---> 卸载成功"

    exit 0
}
