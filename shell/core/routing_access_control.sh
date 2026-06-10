#!/usr/bin/env bash

# 访问控制
blacklist() {
    accessControlMenu "$@"
}

accessControlMenu() {
    if [[ -z "${configPath}" ]]; then
        errorCard "未安装，请使用脚本安装"
        menu
        exit 0
    fi

    echoContent title "\n┌─ 访问控制 ─────────────────────────────────────────"
    menuLine "管理域名/IP 阻断、直连例外和区域阻断规则"
    menuLine "这是服务端出站与访问限制，不会修改客户端订阅入口"
    menuLine "Xray 使用 routing + blackhole/direct；sing-box 使用 rule_set/domain_suffix/ip_cidr"
    menuItem 1 "查看当前访问控制" "显示 Xray / sing-box 当前阻断与例外"
    menuItem 2 "添加域名阻断" "添加 geosite 或自定义域名阻断"
    menuItem 3 "添加 IP/CIDR 阻断" "添加自定义 IP、CIDR 或 geoip 规则"
    menuItem 4 "添加直连例外" "添加优先直连域名规则"
    menuDangerItem 5 "区域阻断策略" "屏蔽 geosite:cn / geoip:cn 等高风险策略"
    menuItem 6 "移除访问控制" "按类型移除阻断或例外规则"
    menuReturnItem 7 "返回路由与访问控制" "回到上级菜单"
    menuClose

    autoRead access_control_menu "请选择:" accessControlStatus
    case "${accessControlStatus}" in
    1)
        showAccessControlStatus
        ;;
    2)
        addBlockedDomains
        ;;
    3)
        addBlockedIPs
        ;;
    4)
        addDirectAllowDomains
        ;;
    5)
        manageRegionalBlockPolicy
        ;;
    6)
        removeAccessControlMenu
        ;;
    7)
        routingAccessMenu
        ;;
    *)
        errorCard "选择错误，请重新选择"
        accessControlMenu
        return
        ;;
    esac
}

showAccessControlStatus() {
    echoContent title "\n┌─ 当前访问控制 ─────────────────────────────────────"
    if [[ "${coreInstallType}" == "1" && -f "${configPath}09_routing.json" ]]; then
        menuLine "Xray 域名阻断："
        jq -r '.routing.rules[]? | select(.outboundTag=="blackhole_out" and (.domain != null)) | .domain[]?' "${configPath}09_routing.json" | sed 's/^/  /' || true
        menuLine "Xray IP/CIDR 阻断："
        jq -r '.routing.rules[]? | select(.outboundTag=="blackhole_ip_out" and (.ip != null)) | .ip[]?' "${configPath}09_routing.json" | sed 's/^/  /' || true
        menuLine "Xray 直连例外："
        jq -r '.routing.rules[]? | select(.outboundTag=="allow_domain_direct_outbound" and (.domain != null)) | .domain[]?' "${configPath}09_routing.json" | sed 's/^/  /' || true
    else
        menuLine "Xray：未检测到访问控制路由"
    fi

    if [[ -n "${singBoxConfigPath}" ]]; then
        menuLine "sing-box 域名阻断："
        showSingBoxAccessRuleFile "block_domain_route"
        showSingBoxAccessRuleFile "cn_block_route"
        menuLine "sing-box IP/CIDR 阻断："
        showSingBoxAccessRuleFile "block_ip_route"
        showSingBoxAccessRuleFile "cn_block_ip_route"
        menuLine "sing-box 直连例外："
        showSingBoxAccessRuleFile "00_allow_domain_route"
    else
        menuLine "sing-box：未检测到配置"
    fi
    menuClose
}

showSingBoxAccessRuleFile() {
    local name=$1
    local file="${singBoxConfigPath}${name}.json"
    [[ -f "${file}" ]] || return 0
    menuLine "  ${name}:"
    jq -r '
        .route.rules[]? as $rule |
        ($rule.rule_set[]? // empty),
        ($rule.domain[]? // empty),
        ($rule.domain_suffix[]? // empty),
        ($rule.ip_cidr[]? // empty)
    ' "${file}" | sed 's/^/    /' || true
    jq -r '.route.rule_set[]?.url? // empty' "${file}" | sed 's/^/    /' || true
}

addBlockedDomains() {
    local domainList
    echoContent title "\n┌─ 添加域名阻断 ─────────────────────────────────────"
    menuLine "示例：openai,geosite:category-ads-all,domain:example.com,full:api.example.com,keyword:tracker"
    menuLine "具体域名会按 domain/domain_suffix 匹配，不再生成宽泛 regexp"
    menuLine "添加规则为增量配置，不会删除之前设置的内容"
    menuClose
    autoRead access_block_domains "请录入要阻断的域名或规则:" domainList
    if [[ -z "${domainList}" ]]; then
        errorCard "域名不可为空"
        accessControlMenu
        return
    fi

    accessControlBackupCreate
    if [[ "${coreInstallType}" == "1" ]]; then
        addXrayRouting blackhole_out outboundTag "${domainList}"
        addXrayOutbound blackhole_out
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        addSingBoxRouteRule "block_domain_outbound" "${domainList}" "block_domain_route"
        addSingBoxOutbound "01_direct_outbound"
    fi
    applyAccessControlConfigChange || return 1
    successCard "域名阻断规则已添加"
}

addBlockedIPs() {
    local ipList normalizedIPs
    echoContent title "\n┌─ 添加 IP/CIDR 阻断 ────────────────────────────────"
    menuLine "录入示例：1.1.1.1,8.8.8.8,1.1.1.0/24,2400:3200::/32,cn"
    menuClose
    autoRead access_block_ips "请录入 IP/CIDR:" ipList
    normalizedIPs=$(validateAccessIPList "${ipList}") || { errorCard "IP/CIDR 格式错误"; accessControlMenu; return; }
    if [[ -z "${normalizedIPs}" ]]; then
        errorCard "IP/CIDR 不可为空"
        accessControlMenu
        return
    fi

    accessControlBackupCreate
    if [[ "${coreInstallType}" == "1" ]]; then
        addXrayIPRouting blackhole_ip_out outboundTag "${normalizedIPs}"
        addXrayOutbound blackhole_ip_out
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        addSingBoxIPRouteRule "block_ip_outbound" "${normalizedIPs}" "block_ip_route"
    fi
    applyAccessControlConfigChange || return 1
    successCard "IP/CIDR 阻断规则已添加"
}

addDirectAllowDomains() {
    local allowDomainList
    echoContent title "\n┌─ 添加直连例外 ─────────────────────────────────────"
    menuLine "直连例外会优先于阻断规则，适合系统更新、证书签发或必要服务"
    menuLine "录入示例：dl.google.com,apple.com,domain:example.com,full:api.example.com"
    menuClose
    autoRead access_allow_domains "请录入直连例外域名:" allowDomainList
    if [[ -z "${allowDomainList}" ]]; then
        errorCard "域名不可为空"
        accessControlMenu
        return
    fi

    accessControlBackupCreate
    if [[ "${coreInstallType}" == "1" ]]; then
        addXrayRouting allow_domain_direct_outbound outboundTag "${allowDomainList}" "top"
        addXrayOutbound allow_domain_direct_outbound
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        addSingBoxRouteRule "01_direct_outbound" "${allowDomainList}" "00_allow_domain_route"
        addSingBoxOutbound "01_direct_outbound"
    fi
    applyAccessControlConfigChange || return 1
    successCard "直连例外已添加"
}

manageRegionalBlockPolicy() {
    local policyStatus allowDomainList extraAllowDomainList
    allowDomainList="dl.google.com,apple.com,bing.com,microsoft.com,gstatic,xn--ngstr-lra8j.com,googleapis.com,googleapis.cn"
    echoContent title "\n┌─ 区域阻断策略 ─────────────────────────────────────"
    menuLine "危险操作：可能影响系统更新、证书签发、应用连接和客户端服务"
    menuLine "默认直连例外：${allowDomainList}"
    menuDangerItem 1 "屏蔽 geosite:cn + geoip:cn" "同时阻断大陆域名和大陆 IP"
    menuDangerItem 2 "仅屏蔽 geosite:cn" "只按域名规则阻断"
    menuDangerItem 3 "仅屏蔽 geoip:cn" "只按 IP 规则阻断"
    menuReturnItem 4 "返回" "回到访问控制"
    menuClose
    autoRead access_region_policy "请选择:" policyStatus
    [[ "${policyStatus}" == "4" ]] && { accessControlMenu; return; }
    if [[ ! "${policyStatus}" =~ ^[1-3]$ ]]; then
        errorCard "选择错误，请重新选择"
        manageRegionalBlockPolicy
        return
    fi
    autoRead access_region_extra_allow "追加直连例外域名[可留空，多个用英文逗号]:" extraAllowDomainList
    if [[ -n "${extraAllowDomainList}" ]]; then
        allowDomainList="${allowDomainList},${extraAllowDomainList}"
    fi

    accessControlBackupCreate
    if [[ "${coreInstallType}" == "1" ]]; then
        [[ "${policyStatus}" == "1" || "${policyStatus}" == "2" ]] && { addXrayRouting blackhole_out outboundTag "cn"; addXrayOutbound blackhole_out; }
        [[ "${policyStatus}" == "1" || "${policyStatus}" == "3" ]] && { addXrayIPRouting blackhole_ip_out outboundTag "cn"; addXrayOutbound blackhole_ip_out; }
        addXrayRouting allow_domain_direct_outbound outboundTag "${allowDomainList}" "top"
        addXrayOutbound allow_domain_direct_outbound
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        [[ "${policyStatus}" == "1" || "${policyStatus}" == "2" ]] && { addSingBoxRouteRule "cn_block_outbound" "cn" "cn_block_route"; }
        [[ "${policyStatus}" == "1" || "${policyStatus}" == "3" ]] && { addSingBoxGeoIPRouteRule "block_ip_outbound" "cn" "cn_block_ip_route"; }
        addSingBoxRouteRule "01_direct_outbound" "${allowDomainList}" "00_allow_domain_route"
        addSingBoxOutbound "01_direct_outbound"
    fi
    applyAccessControlConfigChange || return 1
    successCard "区域阻断策略已应用"
}

removeAccessControlMenu() {
    echoContent title "\n┌─ 移除访问控制 ─────────────────────────────────────"
    menuItem 1 "只移除域名阻断" "保留 IP 阻断和直连例外"
    menuItem 2 "只移除 IP/CIDR 阻断" "保留域名阻断和直连例外"
    menuItem 3 "只移除直连例外" "保留阻断规则"
    menuItem 4 "只移除区域阻断" "移除 cn 域名/IP 区域策略"
    menuDangerItem 5 "移除全部访问控制" "移除域名/IP 阻断、区域阻断和直连例外"
    menuReturnItem 6 "返回" "回到访问控制"
    menuClose
    autoRead access_remove_menu "请选择:" removeStatus
    accessControlBackupCreate
    case "${removeStatus}" in
    1) removeAccessControlByKind domain ;;
    2) removeAccessControlByKind ip ;;
    3) removeAccessControlByKind allow ;;
    4) removeAccessControlByKind region ;;
    5) removeAccessControlByKind all ;;
    6) accessControlMenu; return ;;
    *) errorCard "选择错误，请重新选择"; removeAccessControlMenu; return ;;
    esac
    applyAccessControlConfigChange || return 1
    successCard "访问控制规则已移除"
}

removeAccessControlByKind() {
    local kind=$1
    if [[ "${coreInstallType}" == "1" ]]; then
        case "${kind}" in
        domain)
            unInstallRouting blackhole_out outboundTag
            removeXrayOutbound blackhole_out
            ;;
        ip)
            unInstallRouting blackhole_ip_out outboundTag
            removeXrayOutbound blackhole_ip_out
            ;;
        allow)
            unInstallRouting allow_domain_direct_outbound outboundTag
            removeXrayOutbound allow_domain_direct_outbound
            ;;
        region)
            removeXrayRegionalRules
            ;;
        all)
            unInstallRouting blackhole_out outboundTag
            unInstallRouting blackhole_ip_out outboundTag
            unInstallRouting allow_domain_direct_outbound outboundTag
            removeXrayOutbound blackhole_out
            removeXrayOutbound blackhole_ip_out
            removeXrayOutbound allow_domain_direct_outbound
            ;;
        esac
    fi

    if [[ -n "${singBoxConfigPath}" ]]; then
        case "${kind}" in
        domain)
            removeSingBoxConfig "block_domain_route"
            removeSingBoxConfig "block_domain_outbound"
            ;;
        ip)
            removeSingBoxConfig "block_ip_route"
            removeSingBoxConfig "block_ip_outbound"
            ;;
        allow)
            removeSingBoxConfig "00_allow_domain_route"
            ;;
        region)
            removeSingBoxConfig "cn_block_route"
            removeSingBoxConfig "cn_block_outbound"
            removeSingBoxConfig "cn_block_ip_route"
            ;;
        all)
            removeSingBoxConfig "block_domain_route"
            removeSingBoxConfig "block_domain_outbound"
            removeSingBoxConfig "block_ip_route"
            removeSingBoxConfig "block_ip_outbound"
            removeSingBoxConfig "cn_block_route"
            removeSingBoxConfig "cn_block_outbound"
            removeSingBoxConfig "cn_block_ip_route"
            removeSingBoxConfig "00_allow_domain_route"
            ;;
        esac
    fi
}

removeXrayRegionalRules() {
    if [[ -f "${configPath}09_routing.json" ]]; then
        updateRoutingJsonConfig "${configPath}09_routing.json" '
            del(.routing.rules[] | select((.outboundTag == "blackhole_out") and ((.domain // []) | index("geosite:cn")))) |
            del(.routing.rules[] | select((.outboundTag == "blackhole_ip_out") and ((.ip // []) | index("geoip:cn"))))
        '
    fi
}

validateAccessIPList() {
    local input=$1
    local item output= seen=,
    while read -r item; do
        item=$(echo "${item}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "${item}" ]] && continue
        if [[ "${item}" != "cn" && ! "${item}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$ && ! "${item}" =~ ^[0-9a-f:]+(/[0-9]{1,3})?$ ]]; then
            return 1
        fi
        if [[ "${seen}" != *",${item},"* ]]; then
            seen="${seen}${item},"
            output="${output}${output:+,}${item}"
        fi
    done < <(echo "${input}" | tr ',' '\n')
    echo "${output}"
}

accessControlBackupDir() {
    echo "${PADM_ACCESS_CONTROL_BACKUP_DIR:-/tmp/padm-access-control-backup}"
}

accessControlBackupCreate() {
    local backupDir
    backupDir=$(accessControlBackupDir)
    rm -rf "${backupDir}" >/dev/null 2>&1
    mkdir -p "${backupDir}/xray" "${backupDir}/sing-box" >/dev/null 2>&1 || return 1
    if [[ -n "${configPath}" ]]; then
        for file in 09_routing.json blackhole_out.json blackhole_ip_out.json allow_domain_direct_outbound.json; do
            if [[ -f "${configPath}${file}" ]]; then
                cp "${configPath}${file}" "${backupDir}/xray/${file}" || return 1
            fi
        done
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        for file in block_domain_route.json block_domain_outbound.json block_ip_route.json block_ip_outbound.json cn_block_route.json cn_block_outbound.json cn_block_ip_route.json 00_allow_domain_route.json 01_direct_outbound.json; do
            if [[ -f "${singBoxConfigPath}${file}" ]]; then
                cp "${singBoxConfigPath}${file}" "${backupDir}/sing-box/${file}" || return 1
            fi
        done
    fi
    return 0
}

accessControlBackupRestore() {
    local backupDir
    backupDir=$(accessControlBackupDir)
    if [[ -n "${configPath}" ]]; then
        for file in 09_routing.json blackhole_out.json blackhole_ip_out.json allow_domain_direct_outbound.json; do
            rm -f "${configPath}${file}" >/dev/null 2>&1
            [[ -f "${backupDir}/xray/${file}" ]] && cp "${backupDir}/xray/${file}" "${configPath}${file}"
        done
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        for file in block_domain_route.json block_domain_outbound.json block_ip_route.json block_ip_outbound.json cn_block_route.json cn_block_outbound.json cn_block_ip_route.json 00_allow_domain_route.json 01_direct_outbound.json; do
            rm -f "${singBoxConfigPath}${file}" >/dev/null 2>&1
            [[ -f "${backupDir}/sing-box/${file}" ]] && cp "${backupDir}/sing-box/${file}" "${singBoxConfigPath}${file}"
        done
    fi
}

validateAccessControlConfig() {
    if [[ "${coreInstallType}" == "1" && -x /etc/padm/xray/xray ]]; then
        if ! /etc/padm/xray/xray -test -confdir /etc/padm/xray/conf >/tmp/padm-access-xray-test.log 2>&1; then
            accessControlBackupRestore
            echoContent title "\n┌─ Xray 配置校验失败 ─────────────────────────────────"
            menuLine "访问控制配置未通过校验，已回滚本次修改"
            menuLine "排查日志：/tmp/padm-access-xray-test.log"
            menuClose
            return 1
        fi
    fi
    if [[ -n "${singBoxConfigPath}" && -x /etc/padm/sing-box/sing-box ]]; then
        if ! /etc/padm/sing-box/sing-box merge config.json -C /etc/padm/sing-box/conf/config/ -D /etc/padm/sing-box/conf/ >/tmp/padm-access-sing-box-test.log 2>&1; then
            accessControlBackupRestore
            echoContent title "\n┌─ sing-box 配置校验失败 ─────────────────────────────"
            menuLine "访问控制配置未通过校验，已回滚本次修改"
            menuLine "排查日志：/tmp/padm-access-sing-box-test.log"
            menuClose
            return 1
        fi
    fi
    rm -rf "$(accessControlBackupDir)" >/dev/null 2>&1
}

applyAccessControlConfigChange() {
    validateAccessControlConfig || return 1
    reloadCore || return 1
}
