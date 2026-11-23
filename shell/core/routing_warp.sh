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
        menuLine "WARP 账号注册需要运行第三方工具 warp-reg"
        menuLine "项目地址：https://github.com/badafans/warp-reg"
        menuClose

        autoRead warp_reg_install "需要安装 warp-reg，是否继续？[y/n]：" installWarpRegStatus || return 1

        if [[ "${installWarpRegStatus}" == "y" ]]; then

            mkdir -p "${warpDir}" || return 1
            if ! downloadGitHubReleaseAsset -P "${warpDir}/" badafans/warp-reg v1.0 "${warpRegCoreCPUVendor}"; then
                errorCard "warp-reg 下载失败"
                return 1
            fi
            if [[ ! -s "${warpDir}/${warpRegCoreCPUVendor}" ]]; then
                errorCard "warp-reg 文件无效"
                return 1
            fi
            mv "${warpDir}/${warpRegCoreCPUVendor}" "${warpBinary}" || {
                errorCard "warp-reg 安装失败"
                return 1
            }
            chmod 755 "${warpBinary}" || {
                errorCard "warp-reg 权限设置失败"
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
            jq '.routing.rules[] | select(.outboundTag == "wireguard_out_'"${type}"'") | .domain' ${configPath}09_routing.json
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
            jq '.route.rules[]' "${singBoxConfigPath}wireguard_endpoints_${type}_route.json"
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
    local title="WARP ${type} 分流"
    local address= successMessage= domainList=
    [[ "${type}" == "IPv4" || "${type}" == "IPv6" ]] || {
        errorCard "无法确定 WARP 出站的 IP 类型"
        return 1
    }
    progressCard "$1" "${title}"
    echoContent title "\n┌─ ${title} ────────────────────────────────────────"
    menuItem 1 "查看分流规则"
    menuItem 2 "添加域名" "让指定域名使用 WARP ${type} 出站"
    menuDangerItem 3 "切换全局出站" "清除其他出站规则，改用 WARP ${type} 转发"
    menuDangerItem 4 "移除 WARP 分流" "停用 WARP ${type} 出站"
    menuReturnItem 0 "返回 WARP 出站"
    menuClose
    local warpStatus
    while true; do
        menuReadChoice warp_ipv4_menu "请选择:" warpStatus interactive || return 0
        case "${warpStatus}" in
        0) return 0 ;;
        [1-4]) break ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done

    if [[ "${warpStatus}" == "1" ]]; then
        showWireGuardDomain "${type}"
        return 0
    elif [[ "${warpStatus}" == "2" ]]; then
        echoContent title "\n┌─ 添加 WARP 分流规则 ────────────────────────────────"
        menuLine "多个域名或规则用英文逗号分隔，规则格式见 README"
        menuClose
        autoRead routing_domain_rules "请输入域名规则：" domainList || return 0
        if [[ -z "${domainList}" ]]; then
            coreDomainRequiredErrorCard
            return 1
        fi
        installWarpReg || return 1
        readConfigWarpReg || return 1
        address=$(warpRoutingAddress "${type}") || return 1
        routingConfigApplyTransaction "添加 WARP ${type} 分流失败" false true addWireGuardRoute "${type}" outboundTag "${domainList}" || return 1
        successMessage="已添加 WARP ${type} 分流规则"
    elif [[ "${warpStatus}" == "3" ]]; then
        warnCard \
            "将清除现有分流并改用 WARP ${type} 全局出站" \
            "使用 Xray 时也会移除现有的 BT 阻断和访问控制规则"
        autoConfirm warp_global_confirm "确认设置 WARP 全局出站？" n warpOutStatus
        if [[ "${warpOutStatus}" == "y" ]]; then
            installWarpReg || return 1
            readConfigWarpReg || return 1
            address=$(warpRoutingAddress "${type}") || return 1
            routingConfigApplyTransaction "设置 WARP ${type} 全局出站失败" false true setWireGuardGlobalRoutingConfig "${type}" || return 1
            successMessage="已切换到 WARP ${type} 全局出站"
        else
            coreCancelledStatusCard "未设置 WARP 全局出站"
            return 0
        fi
    elif [[ "${warpStatus}" == "4" ]]; then
        routingConfigApplyTransaction "移除 WARP ${type} 分流失败" false true removeWireGuardRoutingConfig "${type}" || return 1
        successMessage="已移除 WARP ${type} 分流"
    fi
    [[ -n "${successMessage}" ]] && successCard "${successMessage}"
}


warpRoutingMenu() {
    local warpRoutingType=
    while true; do
        echoContent title "\n┌─ WARP 出站 ────────────────────────────────────────"
        menuLine "使用第三方 warp-reg 注册账号，可用性取决于 Cloudflare 服务"
        menuItem 1 "WARP IPv4" "通过 WARP 的 IPv4 地址出站"
        menuItem 2 "WARP IPv6" "通过 WARP 的 IPv6 地址出站"
        menuReturnItem 0 "返回分流工具"
        menuClose
        warpRoutingType=
        menuReadChoice warp_routing_type_menu "请选择:" warpRoutingType interactive || return 0

        case "${warpRoutingType}" in
        1) warpRoutingReg 1 IPv4 || true; continue ;;
        2) warpRoutingReg 1 IPv6 || true; continue ;;
        0) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}
