#!/usr/bin/env bash

warpConfigSafeDir() {
    local warpDir
    warpDir="${PADM_WARP_DIR:-/etc/padm/warp}"
    padmRequireSafeAbsolutePath "${warpDir%/}"
}

warpRegConfigLooksValid() {
    local targetPath=$1
    [[ -s "${targetPath}" ]] || return 1
    grep -qE '^[[:space:]]*private_key[[:space:]]*:' "${targetPath}" &&
        grep -qE '^[[:space:]]*public_key[[:space:]]*:' "${targetPath}" &&
        grep -qE '^[[:space:]]*reserved[[:space:]]*:' "${targetPath}" &&
        grep -qE '^[[:space:]]*v6[[:space:]]*:' "${targetPath}"
}

# 读取第三方 WARP 配置
readConfigWarpReg() {
    local configFile warpBinary tmpFile
    local warpDir
    warpDir=$(warpConfigSafeDir) || return 1
    configFile="${warpDir}/config"
    warpBinary="${warpDir}/warp-reg"

    if ! warpRegConfigLooksValid "${configFile}"; then
        mkdir -p "${warpDir}" || return 1
        installWarpReg || return 1
        padmCreateTempPath tmpFile "${warpDir}/.config.XXXXXX" || return 1
        if ! "${warpBinary}" >"${tmpFile}" 2>&1; then
            rm -f "${tmpFile}" "${configFile}" >/dev/null 2>&1 || true
            return 1
        fi
        if ! warpRegConfigLooksValid "${tmpFile}"; then
            rm -f "${tmpFile}" "${configFile}" >/dev/null 2>&1 || true
            return 1
        fi
        mv "${tmpFile}" "${configFile}" || {
            rm -f "${tmpFile}" >/dev/null 2>&1 || true
            return 1
        }
    fi

    secretKeyWarpReg=$(grep <"${configFile}" private_key | awk '{print $2}')

    addressWarpReg=$(grep <"${configFile}" v6 | awk '{print $2}')

    publicKeyWarpReg=$(grep <"${configFile}" public_key | awk '{print $2}')

    reservedWarpReg=$(grep <"${configFile}" reserved | awk -F "[:]" '{print $2}')

}
# 安装 warp-reg 工具
installWarpReg() {
    local warpDir warpBinary
    warpDir=$(warpConfigSafeDir) || return 1
    warpBinary="${warpDir}/warp-reg"
    if [[ ! -f "${warpBinary}" || ! -s "${warpBinary}" || ! -x "${warpBinary}" ]]; then
        echo
        echoContent title "\n┌─ warp-reg 第三方工具 ──────────────────────────────"
        menuLine "依赖第三方程序，请熟知其中风险"
        menuLine "项目地址：https://github.com/badafans/warp-reg"
        menuClose

        autoRead warp_reg_install "warp-reg未安装，是否安装？[y/n]:" installWarpRegStatus

        if [[ "${installWarpRegStatus}" == "y" ]]; then

            mkdir -p "${warpDir}" || return 1
            if ! downloadGitHubReleaseAsset -P "${warpDir}/" badafans/warp-reg v1.0 "${warpRegCoreCPUVendor}"; then
                errorCard "warp-reg下载失败"
                return 1
            fi
            if [[ ! -s "${warpDir}/${warpRegCoreCPUVendor}" ]]; then
                errorCard "warp-reg文件异常"
                return 1
            fi
            mv "${warpDir}/${warpRegCoreCPUVendor}" "${warpBinary}" || {
                errorCard "warp-reg文件安装失败"
                return 1
            }
            chmod 755 "${warpBinary}" || {
                errorCard "warp-reg权限设置失败"
                return 1
            }

        else
            coreCancelledStatusCard "放弃安装"
            return 1
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

        addXrayOutbound "wireguard_out_${type}" || return 1
        if [[ -n "${domainList}" ]]; then
            addXrayRouting "wireguard_out_${type}" "${tag}" "${domainList}" || return 1
        fi
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then

        if [[ -n "${domainList}" ]]; then
            addSingBoxOutbound "01_direct_outbound" || return 1
            addSingBoxRouteRule "wireguard_endpoints_${type}" "${domainList}" "wireguard_endpoints_${type}_route" || return 1
        fi

        addSingBoxWireGuardEndpoints "${type}" || return 1
    fi
}

# 卸载 WireGuard
unInstallWireGuard() {
    local warpDir
    local warpConfig
    warpDir=$(warpConfigSafeDir) || return 1
    warpConfig="${warpDir}/config"
    if [[ -n "${configPath:-}" ]] &&
        { [[ -f "${configPath}wireguard_out_IPv4.json" ]] || [[ -f "${configPath}wireguard_out_IPv6.json" ]]; }; then
        return 0
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ -f "${singBoxConfigPath}wireguard_endpoints_IPv4.json" || -f "${singBoxConfigPath}wireguard_endpoints_IPv6.json" ]]; then
            return 0
        fi
        local wireguardOutboundFile
        wireguardOutboundFile=$(padmManagedFilePath "${singBoxConfigPath}" "wireguard_outbound.json") || return 1
        removeManagedFileIfPresent "${wireguardOutboundFile}" || return 1
    fi
    rm -f -- "${warpConfig}" >/dev/null 2>&1 || return 1
}
# 移除 WARP 分流规则
removeWireGuardRoute() {
    local type=$1
    if [[ "${coreInstallType}" == "1" ]]; then

        unInstallRouting wireguard_out_"${type}" outboundTag || return 1

        removeXrayOutbound "wireguard_out_${type}" || return 1
        if [[ ! -f "${configPath}IPv4_out.json" ]]; then
            addXrayOutbound IPv4_out || return 1
        fi
    fi

    if [[ -n "${singBoxConfigPath}" ]]; then
        removeSingBoxRouteRule "wireguard_endpoints_${type}" || return 1
    fi

}
# WARP 第三方分流管理
warpRoutingAddress() {
    case "$1" in
    IPv4) printf '%s\n' "172.16.0.2/32" ;;
    IPv6)
        [[ -n "${addressWarpReg:-}" ]] || return 1
        printf '%s/128\n' "${addressWarpReg}"
        ;;
    *) return 1 ;;
    esac
}

setWireGuardGlobalRoutingConfig() {
    local type=$1
    if [[ "${coreInstallType}" == "1" ]]; then
        local xrayRoutingFile
        addXrayOutbound "wireguard_out_${type}" || return 1
        xrayRoutingFile=$(padmManagedFilePath "${configPath:-/etc/padm/xray/conf/}" "09_routing.json") || return 1
        removeManagedFileIfPresent "${xrayRoutingFile}" || return 1
        if [[ "${type}" == "IPv4" ]]; then
            removeXrayOutbound "wireguard_out_IPv6" || return 1
        else
            removeXrayOutbound "wireguard_out_IPv4" || return 1
        fi
        removeXrayOutbound IPv4_out || return 1
        removeXrayOutbound IPv6_out || return 1
        removeXrayOutbound z_direct_outbound || return 1
        removeXrayOutbound blackhole_out || return 1
        removeXrayOutbound socks5_outbound || return 1
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        removeSingBoxConfig IPv4_out || return 1
        removeSingBoxConfig IPv6_out || return 1
        removeSingBoxConfig 01_direct_outbound || return 1
        removeSingBoxConfig wireguard_endpoints_IPv4_route || return 1
        removeSingBoxConfig wireguard_endpoints_IPv6_route || return 1
        removeSingBoxConfig IPv6_route || return 1
        removeSingBoxConfig socks5_02_inbound_route || return 1
        addWireGuardRoute "${type}" outboundTag "" || return 1
        if [[ "${type}" == "IPv4" ]]; then
            removeSingBoxConfig wireguard_endpoints_IPv6 || return 1
        else
            removeSingBoxConfig wireguard_endpoints_IPv4 || return 1
        fi
    fi
}

removeWireGuardRoutingConfig() {
    local type=$1
    removeWireGuardRoute "${type}" || return 1
    if [[ -n "${singBoxConfigPath}" ]]; then
        removeSingBoxConfig "wireguard_endpoints_${type}" || return 1
        addSingBoxOutbound "01_direct_outbound" || return 1
    fi
    unInstallWireGuard "${type}" || return 1
}

warpRoutingReg() {
    local type=$2
    local title="WARP 分流 ${type}"
    local address= successMessage=
    [[ "${type}" == "IPv4" || "${type}" == "IPv6" ]] || {
        errorCard "IP获取失败，退出安装"
        return 1
    }
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

    if [[ "${warpStatus}" == "1" ]]; then
        showWireGuardDomain "${type}"
        exit 0
    elif [[ "${warpStatus}" == "2" ]]; then
        echoContent title "\n┌─ WARP 分流规则说明 ────────────────────────────────"
        menuLine "支持 sing-box、Xray-core"
        menuLine "请按 README 中的分流说明配置域名或规则"
        menuClose
        autoRead routing_domain_rules "请按照上面示例录入域名:" domainList
        if [[ -z "${domainList}" ]]; then
            coreDomainRequiredErrorCard
            return 1
        fi
        installWarpReg || return 1
        readConfigWarpReg || return 1
        address=$(warpRoutingAddress "${type}") || return 1
        routingConfigApplyTransaction "添加 WARP ${type} 分流失败" false true addWireGuardRoute "${type}" outboundTag "${domainList}" || return 1
        successMessage="添加完毕"
    elif [[ "${warpStatus}" == "3" ]]; then
        warnCard \
            "会删除所有设置的分流规则" \
            "会删除除 WARP[第三方] 之外的所有出站规则"
        autoConfirm warp_global_confirm "确认设置 WARP 全局出站？" n warpOutStatus
        if [[ "${warpOutStatus}" == "y" ]]; then
            installWarpReg || return 1
            readConfigWarpReg || return 1
            address=$(warpRoutingAddress "${type}") || return 1
            routingConfigApplyTransaction "设置 WARP ${type} 全局出站失败" false true setWireGuardGlobalRoutingConfig "${type}" || return 1
            successMessage="WARP全局出站设置完毕"
        else
            coreCancelledStatusCard "未设置 WARP 全局出站"
            return 0
        fi
    elif [[ "${warpStatus}" == "4" ]]; then
        routingConfigApplyTransaction "卸载 WARP ${type} 分流失败" false true removeWireGuardRoutingConfig "${type}" || return 1
        successMessage="卸载WARP ${type}分流完毕"
    elif [[ "${warpStatus}" == "5" ]]; then
        return 0
    else
        coreSelectionErrorCard "选择错误"
        return 1
    fi
    [[ -n "${successMessage}" ]] && successCard "${successMessage}"
}


warpRoutingMenu() {
    local warpRoutingType=
    while true; do
        echoContent title "\n┌─ WARP 出站 ────────────────────────────────────────"
        menuLine "通过 Cloudflare WARP WireGuard 出站，常用于 IPv4/IPv6 出口切换"
        menuLine "依赖第三方 warp-reg 获取账号参数；Cloudflare 服务状态或策略变化会影响可用性"
        menuItem 1 "WARP IPv4" "使用 IPv4 WARP 地址作为出站"
        menuItem 2 "WARP IPv6" "使用 IPv6 WARP 地址作为出站"
        menuReturnItem 3 "返回分流工具" "回到上一级分流菜单"
        menuClose
        warpRoutingType=
        autoRead warp_routing_type_menu "请选择:" warpRoutingType || return 0

        case "${warpRoutingType}" in
        1) warpRoutingReg 1 IPv4 || true; continue ;;
        2) warpRoutingReg 1 IPv6 || true; continue ;;
        3) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}
