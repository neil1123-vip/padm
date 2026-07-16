#!/usr/bin/env bash

# IPv6 分流

ipv6Routing() {

    if [[ -z "${configPath}" ]]; then

        coreNotInstalledErrorCard

        menu

        exit 0

    fi



    if ! hasIPv6Connectivity; then
        errorCard "不支持ipv6"
        return 1
    fi

    local successMessage=

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

        if [[ -z "${domainList}" ]]; then
            coreDomainRequiredErrorCard
            return 1
        fi

        routingConfigApplyTransaction "添加 IPv6 分流失败" false false addIPv6RoutingConfig "${domainList}" || return 1
        successMessage="添加完毕"



    elif [[ "${ipv6Status}" == "3" ]]; then



        warnCard \

            "会删除所有设置的分流规则" \

            "会删除 IPv6 之外的所有出站规则"

        autoConfirm ipv6_global_confirm "确认设置 IPv6 全局出站？" n IPv6OutStatus



        if [[ "${IPv6OutStatus}" == "y" ]]; then
            routingConfigApplyTransaction "设置 IPv6 全局出站失败" false false setIPv6GlobalRoutingConfig || return 1
            successMessage="IPv6全局出站设置完毕"

        else



            coreCancelledStatusCard "未设置 IPv6 全局出站"

            ipv6Routing

            return

        fi



    elif [[ "${ipv6Status}" == "4" ]]; then
        routingConfigApplyTransaction "卸载 IPv6 分流失败" false false removeIPv6RoutingConfig || return 1
        successMessage="IPv6分流卸载成功"

    elif [[ "${ipv6Status}" == "5" ]]; then

        routingAccessMenu

        return

    else
        coreSelectionRetryAction ipv6Routing

        return

    fi
    [[ -n "${successMessage}" ]] && successCard "${successMessage}"

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
