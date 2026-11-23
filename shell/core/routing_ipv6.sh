#!/usr/bin/env bash

# IPv6 分流

ipv6Routing() {

    if [[ -z "${configPath}" ]]; then

        coreNotInstalledErrorCard

        return 1

    fi



    local successMessage=
    local ipv6Status=
    local domainList=

    progressCard "1" "IPv6 分流"

    while true; do
        echoContent title "\n┌─ IPv6 分流 ────────────────────────────────────────"

    menuItem 1 "查看分流规则"

    menuItem 2 "添加域名" "让指定域名使用 IPv6 直连"

    menuDangerItem 3 "切换全局出站" "清除其他出站规则，改用 IPv6 直连"

    menuDangerItem 4 "移除 IPv6 分流" "移除域名分流及 IPv6 出站配置"

    menuReturnItem 0 "返回分流工具"

    menuClose

    ipv6Status=
    menuReadChoice ipv6_menu "请选择:" ipv6Status interactive || return 0

    if [[ "${ipv6Status}" == "1" ]]; then

        showIPv6Routing

        return 0

    elif [[ "${ipv6Status}" == "2" ]]; then

        if ! hasIPv6Connectivity; then
            errorCard "未检测到可用的 IPv6 连接"
            return 1
        fi

        echoContent title "\n┌─ 添加 IPv6 分流规则 ───────────────────────────────"

        menuLine "多个域名或规则用英文逗号分隔，规则格式见 README"

        menuClose



        autoRead routing_domain_rules "请输入域名规则：" domainList || return 0

        if [[ -z "${domainList}" ]]; then
            coreDomainRequiredErrorCard
            return 1
        fi

        routingConfigApplyTransaction "添加 IPv6 分流失败" false false addIPv6RoutingConfig "${domainList}" || return 1
        successMessage="已添加 IPv6 分流规则"



    elif [[ "${ipv6Status}" == "3" ]]; then



        warnCard \
            "将清除现有分流并改用 IPv6 全局出站" \
            "使用 Xray 时也会移除现有的 BT 阻断和访问控制规则"

        autoConfirm ipv6_global_confirm "确认设置 IPv6 全局出站？" n IPv6OutStatus



        if [[ "${IPv6OutStatus}" == "y" ]]; then
            if ! hasIPv6Connectivity; then
                errorCard "未检测到可用的 IPv6 连接"
                return 1
            fi
            routingConfigApplyTransaction "设置 IPv6 全局出站失败" false false setIPv6GlobalRoutingConfig || return 1
            successMessage="已切换到 IPv6 全局出站"

        else



            coreCancelledStatusCard "未设置 IPv6 全局出站"

            return 0

        fi



    elif [[ "${ipv6Status}" == "4" ]]; then
        routingConfigApplyTransaction "移除 IPv6 分流失败" false false removeIPv6RoutingConfig || return 1
        successMessage="已移除 IPv6 分流"

    elif [[ "${ipv6Status}" == "0" ]]; then

        return 0

    else
        coreSelectionErrorCard "选择错误"

    fi
    if [[ -n "${successMessage}" ]]; then
        successCard "${successMessage}"
        return $?
    fi
    done
}

addIPv6RoutingConfig() {
    local domainList=$1
    if [[ "${coreInstallType}" == "1" ]]; then
        addXrayOutbound IPv6_out || return 1
        addXrayRouting IPv6_out outboundTag "${domainList}" || return 1
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        addSingBoxOutbound 01_direct_outbound || return 1
        addSingBoxOutbound IPv6_out || return 1
        addSingBoxOutbound IPv4_out || return 1
        addSingBoxRouteRule "IPv6_out" "${domainList}" "IPv6_route" || return 1
    fi
}

setIPv6GlobalRoutingConfig() {
    if [[ "${coreInstallType}" == "1" ]]; then
        local xrayRoutingFile
        addXrayOutbound IPv6_out || return 1
        xrayRoutingFile=$(padmManagedFilePath "${configPath:-/etc/padm/xray/conf/}" "09_routing.json") || return 1
        removeManagedFileIfPresent "${xrayRoutingFile}" || return 1
        removeXrayOutbound IPv4_out || return 1
        removeXrayOutbound z_direct_outbound || return 1
        removeXrayOutbound blackhole_out || return 1
        removeXrayOutbound wireguard_out_IPv4 || return 1
        removeXrayOutbound wireguard_out_IPv6 || return 1
        removeXrayOutbound socks5_outbound || return 1
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        removeSingBoxConfig IPv4_out || return 1
        removeSingBoxConfig wireguard_endpoints_IPv4_route || return 1
        removeSingBoxConfig wireguard_endpoints_IPv6_route || return 1
        removeSingBoxConfig wireguard_endpoints_IPv4 || return 1
        removeSingBoxConfig wireguard_endpoints_IPv6 || return 1
        removeSingBoxConfig socks5_02_inbound_route || return 1
        removeSingBoxConfig IPv6_route || return 1
        removeSingBoxConfig 01_direct_outbound || return 1
        addSingBoxOutbound IPv6_out || return 1
    fi
}

removeIPv6RoutingConfig() {
    if [[ "${coreInstallType}" == "1" ]]; then
        unInstallRouting IPv6_out outboundTag || return 1
        removeXrayOutbound IPv6_out || return 1
        addXrayOutbound "z_direct_outbound" || return 1
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        removeSingBoxConfig IPv6_out || return 1
        removeSingBoxConfig "IPv6_route" || return 1
        addSingBoxOutbound "01_direct_outbound" || return 1
    fi
}



# IPv6 分流规则展示

showIPv6Routing() {

    if [[ "${coreInstallType}" == "1" ]]; then

        if [[ -f "${configPath}09_routing.json" ]]; then

            echoContent yellow "Xray-core："

            jq '.routing.rules[] | select(.outboundTag == "IPv6_out") | .domain' ${configPath}09_routing.json

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

            jq '.route.rules[] | select(.outbound == "IPv6_out")' "${singBoxConfigPath}IPv6_route.json"

        elif [[ ! -f "${singBoxConfigPath}IPv6_route.json" && -f "${singBoxConfigPath}IPv6_out.json" ]]; then

            echoContent yellow "sing-box"

            successCard "已设置IPv6全局分流"

        else

            statusCard "IPv6 分流" "未安装 IPv6 分流"

        fi

    fi

}
