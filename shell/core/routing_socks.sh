#!/usr/bin/env bash

# Socks5 分流管理
socks5Routing() {
    if [[ -z "${coreInstallType}" ]]; then
        errorCard "未安装任意协议，请先进入主菜单 -> 安装与重装"
        return 1
    fi
    local selectType=
    while true; do
        echoContent title "\n┌─ Socks5 分流 ──────────────────────────────────────"
        menuLine "用于两台机器之间中继出站，不建议把入站暴露给不可信网络"
        menuLine "出站适合本机把部分域名转发到落地机；入站适合落地机只允许指定源 IP 访问"
        menuItem 1 "Socks5 出站" "转发机/代理机配置"
        menuItem 2 "Socks5 入站" "解锁机/落地机配置"
        menuItem 3 "卸载" "移除 Socks5 分流配置"
        menuReturnItem 4 "返回分流工具" "回到上一级分流菜单"
        menuClose
        selectType=
        autoRead socks5_menu "请选择:" selectType || return 0

        case "${selectType}" in
        1) socks5OutboundRoutingMenu || true; continue ;;
        2) socks5InboundRoutingMenu || true; continue ;;
        3) removeSocks5Routing || true; continue ;;
        4) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}
# Socks5 入站菜单
socks5InboundRoutingMenu() {
    local backupDir= selectType=
    local PADM_PORT_ALLOW_TRANSACTION_ACTIVE=false
    local PADM_PORT_ALLOW_TRANSACTION_KEYS=
    while true; do
        readInstallType
        echoContent title "\n┌─ Socks5 入站 ──────────────────────────────────────"
        menuItem 1 "安装 Socks5 入站" "配置解锁机/落地机入站"
        menuItem 2 "查看分流规则" "显示当前入站分流规则"
        menuItem 3 "添加分流规则" "更新入站分流域名"
        menuItem 4 "查看入站配置" "显示端口、用户与密码"
        menuReturnItem 5 "返回 Socks5 分流" "回到上级菜单"
        menuClose
        selectType=
        autoRead socks5_inbound_menu "请选择:" selectType || return 0
        case "${selectType}" in
        1)
            totalProgress=1
            installSingBox 1 || return 1
            singBoxConfigPath="${singBoxConfigPath:-/etc/padm/sing-box/conf/config/}"
            backupDir=
            socks5RoutingBackupCreate backupDir || { errorCard "Socks5 入站配置备份失败"; return 1; }
            PADM_PORT_ALLOW_TRANSACTION_ACTIVE=true
            PADM_PORT_ALLOW_TRANSACTION_KEYS=
            if ! setSocks5Inbound; then
                socks5RoutingRollback "${backupDir}" "Socks5 入站配置失败" false || true
                padmRollbackPortAllowTransaction || errorCard "Socks5 入站配置失败，且新增端口防火墙规则回滚失败"
                return 1
            fi
            if ! setSocks5InboundRouting; then
                socks5RoutingRollback "${backupDir}" "Socks5 入站配置失败" false || true
                padmRollbackPortAllowTransaction || errorCard "Socks5 入站配置失败，且新增端口防火墙规则回滚失败"
                return 1
            fi
            if ! installSingBoxService 1; then
                socks5RoutingRollback "${backupDir}" "sing-box 服务安装失败" false || true
                padmRollbackPortAllowTransaction || errorCard "sing-box 服务安装失败，且 Socks5 入站端口防火墙规则回滚失败"
                return 1
            fi
            if ! reloadCore; then
                socks5RoutingRollback "${backupDir}" "Socks5 入站核心重载失败" true || true
                padmRollbackPortAllowTransaction || errorCard "Socks5 入站核心重载失败，且新增端口防火墙规则回滚失败"
                return 1
            fi
            PADM_PORT_ALLOW_TRANSACTION_ACTIVE=false
            PADM_PORT_ALLOW_TRANSACTION_KEYS=
            padmRemoveCleanupPath "${backupDir}"
            ;;
        2)
            showSingBoxRoutingRules socks5_02_inbound_route
            ;;
        3)
            backupDir=
            socks5RoutingBackupCreate backupDir || { errorCard "Socks5 入站规则备份失败"; return 1; }
            if ! setSocks5InboundRouting addRules; then
                socks5RoutingRollback "${backupDir}" "Socks5 入站规则更新失败" false
                return 1
            fi
            if ! reloadCore; then
                socks5RoutingRollback "${backupDir}" "Socks5 入站核心重载失败" true
                return 1
            fi
            padmRemoveCleanupPath "${backupDir}"
            ;;
        4)
            if [[ -f "${singBoxConfigPath}20_socks5_inbounds.json" ]]; then
                echoContent title "\n┌─ Socks5 入站信息 ──────────────────────────────────"
                menuLine "下列内容需要配置到其他机器的出站，请不要在本机进行代理行为"
                menuLine "端口：$(jq .inbounds[0].listen_port "${singBoxConfigPath}20_socks5_inbounds.json")"
                menuLine "用户名称：$(jq -r .inbounds[0].users[0].username "${singBoxConfigPath}20_socks5_inbounds.json")"
                menuLine "用户密码：$(jq -r .inbounds[0].users[0].password "${singBoxConfigPath}20_socks5_inbounds.json")"
                menuClose
            else
                errorCard "未安装相应功能"
            fi
            ;;
        5) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

# Socks5 出站菜单
socks5OutboundRoutingMenu() {
    local backupDir= selectType=
    while true; do
        echoContent title "\n┌─ Socks5 出站 ──────────────────────────────────────"
        menuItem 1 "安装 Socks5 出站" "配置转发机/代理机出站"
        menuDangerItem 2 "设置 Socks5 全局转发" "删除其他出站并全局走 Socks5"
        menuItem 3 "查看分流规则" "显示当前出站分流规则"
        menuItem 4 "添加分流规则" "更新出站分流域名"
        menuReturnItem 5 "返回 Socks5 分流" "回到上级菜单"
        menuClose
        selectType=
        autoRead socks5_outbound_menu "请选择:" selectType || return 0
        case "${selectType}" in
        1)
            backupDir=
            socks5RoutingBackupCreate backupDir || { errorCard "Socks5 出站配置备份失败"; return 1; }
            if ! setSocks5Outbound || ! setSocks5OutboundRouting; then
                socks5RoutingRollback "${backupDir}" "Socks5 出站配置失败" false
                return 1
            fi
            if ! reloadCore; then
                socks5RoutingRollback "${backupDir}" "Socks5 出站核心重载失败" true
                return 1
            fi
            padmRemoveCleanupPath "${backupDir}"
            ;;
        2)
            backupDir=
            socks5RoutingBackupCreate backupDir || { errorCard "Socks5 全局出站配置备份失败"; return 1; }
            if ! setSocks5Outbound || ! setSocks5OutboundRoutingAll; then
                socks5RoutingRollback "${backupDir}" "Socks5 全局出站配置失败" false
                return 1
            fi
            if ! reloadCore; then
                socks5RoutingRollback "${backupDir}" "Socks5 全局出站核心重载失败" true
                return 1
            fi
            padmRemoveCleanupPath "${backupDir}"
            successCard "Socks5全局出站设置完毕"
            ;;
        3)
            showSingBoxRoutingRules socks5_01_outbound_route
            showXrayRoutingRules socks5_outbound
            ;;
        4)
            backupDir=
            socks5RoutingBackupCreate backupDir || { errorCard "Socks5 出站规则备份失败"; return 1; }
            if ! setSocks5OutboundRouting addRules; then
                socks5RoutingRollback "${backupDir}" "Socks5 出站规则更新失败" false
                return 1
            fi
            if ! reloadCore; then
                socks5RoutingRollback "${backupDir}" "Socks5 出站核心重载失败" true
                return 1
            fi
            padmRemoveCleanupPath "${backupDir}"
            ;;
        5) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

# Socks5 全局分流
setSocks5OutboundRoutingAll() {

    warnCard \
        "会删除所有已经设置的分流规则，包括其他分流（warp、IPv6 等）" \
        "会删除 Socks5 之外的所有出站规则"
    autoConfirm socks5_global_confirm "确认设置 Socks5 全局出站？" n socksOutStatus

    if [[ "${socksOutStatus}" == "y" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            local xrayRoutingFile
            removeXrayOutbound IPv4_out || return 1
            removeXrayOutbound IPv6_out || return 1
            removeXrayOutbound z_direct_outbound || return 1
            removeXrayOutbound blackhole_out || return 1
            removeXrayOutbound wireguard_out_IPv4 || return 1
            removeXrayOutbound wireguard_out_IPv6 || return 1

            xrayRoutingFile=$(padmManagedFilePath "${configPath:-/etc/padm/xray/conf/}" "09_routing.json") || return 1
            removeManagedFileIfPresent "${xrayRoutingFile}" || return 1
        fi
        if [[ -n "${singBoxConfigPath}" ]]; then

            removeSingBoxConfig IPv4_out || return 1
            removeSingBoxConfig IPv6_out || return 1

            removeSingBoxConfig wireguard_endpoints_IPv4_route || return 1
            removeSingBoxConfig wireguard_endpoints_IPv6_route || return 1
            removeSingBoxConfig wireguard_endpoints_IPv4 || return 1
            removeSingBoxConfig wireguard_endpoints_IPv6 || return 1

            removeSingBoxConfig socks5_01_outbound_route || return 1
            removeSingBoxConfig 01_direct_outbound || return 1
        fi
    else
        coreCancelledStatusCard "未设置 Socks5 全局出站"
        return 1
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
            menuLine "$(uiStyle warn "入站配置：")"
            menuLine "$(uiStyle value "$(jq .inbounds[0] "${singBoxConfigPath}20_socks5_inbounds.json")")"
        fi
    fi
}

# Xray-core 分流规则
showXrayRoutingRules() {
    local routingFile="${configPath}09_routing.json"
    local outboundFile="${configPath}socks5_outbound.json"
    if [[ "${coreInstallType}" != "1" || "$1" != "socks5_outbound" || ! -f "${outboundFile}" ]] ||
        ! jq -e --arg tag "$1" '.outbounds[]? | select(.tag == $tag and .protocol == "socks")' "${outboundFile}" >/dev/null 2>&1; then
        return 0
    fi
    if [[ -f "${routingFile}" ]]; then
        jq -e --arg tag "$1" '.routing.rules[]? | select(.outboundTag == $tag)' "${routingFile}" >/dev/null 2>&1 || return 0
        jq --arg tag "$1" '.routing.rules[]? | select(.outboundTag == $tag)' "${routingFile}"
        echoContent yellow "\n已安装 xray-core socks5出站分流"
    else
        echoContent yellow "\n已安装 xray-core socks5全局出站分流"
    fi
    menuLine "$(uiStyle warn "出站分流配置：")"
    menuLine "$(uiStyle value "$(jq .outbounds[0].settings.servers[0] "${outboundFile}")")"
}

stopSocks5SingBox() {
    local previousAllowFailure="${SERVICE_QUEUE_ALLOW_FAILURE:-}"
    SERVICE_QUEUE_ALLOW_FAILURE=true
    handleSingBox stop
    local stopStatus=$?
    SERVICE_QUEUE_ALLOW_FAILURE="${previousAllowFailure}"
    return "${stopStatus}"
}

socks5RoutingBackupCreate() {
    local resultVar=$1
    local createdBackupDir
    local fileName
    local targetPath
    local -a targets=()
    local -a xrayFiles=(
        09_routing.json socks5_outbound.json IPv4_out.json IPv6_out.json
        z_direct_outbound.json blackhole_out.json wireguard_out_IPv4.json wireguard_out_IPv6.json
    )
    local -a singBoxFiles=(
        socks5_outbound.json socks5_01_outbound_route.json 20_socks5_inbounds.json
        socks5_02_inbound_route.json sniff_socks5_inbound.json
        strategy_ipv4_only_socks5_inbound.json strategy_ipv6_only_socks5_inbound.json
        01_direct_outbound.json IPv4_out.json IPv6_out.json dns.json
        wireguard_endpoints_IPv4_route.json wireguard_endpoints_IPv6_route.json
        wireguard_endpoints_IPv4.json wireguard_endpoints_IPv6.json
    )

    if [[ -n "${configPath:-}" ]]; then
        for fileName in "${xrayFiles[@]}"; do
            targetPath=$(padmManagedFilePath "${configPath}" "${fileName}") || return 1
            targets+=("${targetPath}")
        done
    fi
    if [[ -n "${singBoxConfigPath:-}" ]]; then
        for fileName in "${singBoxFiles[@]}"; do
            targetPath=$(padmManagedFilePath "${singBoxConfigPath}" "${fileName}") || return 1
            targets+=("${targetPath}")
        done
    fi
    [[ "${#targets[@]}" -gt 0 ]] || return 1
    checkLogBackupCreate createdBackupDir "${targets[@]}" || return 1
    printf -v "${resultVar}" '%s' "${createdBackupDir}"
}

socks5RoutingRollback() {
    local backupDir=$1
    local reason=$2
    local retryReload=${3:-false}

    if ! checkLogBackupRestore "${backupDir}"; then
        padmForgetCleanupPath "${backupDir}"
        errorCard "${reason}，且旧配置恢复失败" "请手动检查备份目录: ${backupDir}"
        return 1
    fi
    if [[ "${retryReload}" == "true" ]] && ! reloadCore; then
        padmForgetCleanupPath "${backupDir}"
        errorCard "${reason}，旧配置已恢复但核心重载失败" "请手动检查备份目录: ${backupDir}"
        return 1
    fi
    padmRemoveCleanupPath "${backupDir}"
    errorCard "${reason}，已恢复旧配置"
    return 1
}

# 卸载 Socks5 分流
removeSocks5Routing() {
    local backupDir=
    local socks5InboundPort=
    local socks5InboundConfig=
    local unInstallSocks5RoutingStatus=
    while true; do
        backupDir=
        socks5InboundPort=
        socks5InboundConfig=
        echoContent title "\n┌─ 卸载 Socks5 分流 ─────────────────────────────────"
        menuItem 1 "卸载 Socks5 出站" "移除出站转发配置"
        menuItem 2 "卸载 Socks5 入站" "移除入站监听配置"
        menuDangerItem 3 "卸载全部" "同时移除 Socks5 出站和入站配置"
        menuReturnItem 4 "返回 Socks5 分流" "回到上级菜单"
        menuClose
        unInstallSocks5RoutingStatus=
        autoRead socks5_uninstall_menu "请选择:" unInstallSocks5RoutingStatus || return 0
        case "${unInstallSocks5RoutingStatus}" in
        1 | 2 | 3)
            socks5RoutingBackupCreate backupDir || { errorCard "Socks5 卸载配置备份失败"; return 1; }
            ;;
        4)
            return 0
            ;;
        *)
            coreSelectionErrorCard "选择错误"
            continue
            ;;
        esac
        if [[ "${unInstallSocks5RoutingStatus}" == "2" || "${unInstallSocks5RoutingStatus}" == "3" ]] && [[ -n "${singBoxConfigPath}" ]]; then
            socks5InboundConfig=$(padmManagedFilePath "${singBoxConfigPath}" 20_socks5_inbounds.json) || {
                socks5RoutingRollback "${backupDir}" "Socks5 入站端口读取失败" false
                return 1
            }
            if [[ -f "${socks5InboundConfig}" ]]; then
                socks5InboundPort=$(jq -r '.inbounds[0].listen_port // empty' "${socks5InboundConfig}") || {
                    socks5RoutingRollback "${backupDir}" "Socks5 入站端口读取失败" false
                    return 1
                }
                if ! validPortNumber "${socks5InboundPort}"; then
                    socks5RoutingRollback "${backupDir}" "Socks5 入站端口无效" false
                    return 1
                fi
            fi
        fi
        if [[ "${unInstallSocks5RoutingStatus}" == "1" ]]; then
            if [[ "${coreInstallType}" == "1" ]]; then
                unInstallRouting socks5_outbound outboundTag || { socks5RoutingRollback "${backupDir}" "Socks5 出站卸载失败" false; return 1; }
                removeXrayOutbound socks5_outbound || { socks5RoutingRollback "${backupDir}" "Socks5 出站卸载失败" false; return 1; }

                addXrayOutbound z_direct_outbound || { socks5RoutingRollback "${backupDir}" "Socks5 出站卸载失败" false; return 1; }
            fi

            if [[ -n "${singBoxConfigPath}" ]]; then
                removeSingBoxConfig socks5_outbound || { socks5RoutingRollback "${backupDir}" "Socks5 出站卸载失败" false; return 1; }
                removeSingBoxConfig socks5_01_outbound_route || { socks5RoutingRollback "${backupDir}" "Socks5 出站卸载失败" false; return 1; }
                addSingBoxOutbound 01_direct_outbound || { socks5RoutingRollback "${backupDir}" "Socks5 出站卸载失败" false; return 1; }
            fi

        elif [[ "${unInstallSocks5RoutingStatus}" == "2" ]]; then

            if [[ -n "${singBoxConfigPath}" ]]; then
                removeSingBoxConfig 20_socks5_inbounds || { socks5RoutingRollback "${backupDir}" "Socks5 入站卸载失败" false; return 1; }
                removeSingBoxConfig socks5_02_inbound_route || { socks5RoutingRollback "${backupDir}" "Socks5 入站卸载失败" false; return 1; }
                removeSingBoxConfig sniff_socks5_inbound || { socks5RoutingRollback "${backupDir}" "Socks5 入站卸载失败" false; return 1; }
                removeSingBoxConfig "strategy_ipv4_only_socks5_inbound" || { socks5RoutingRollback "${backupDir}" "Socks5 入站卸载失败" false; return 1; }
                removeSingBoxConfig "strategy_ipv6_only_socks5_inbound" || { socks5RoutingRollback "${backupDir}" "Socks5 入站卸载失败" false; return 1; }
            fi

            stopSocks5SingBox || { socks5RoutingRollback "${backupDir}" "Socks5 入站服务停止失败" true; return 1; }
        elif [[ "${unInstallSocks5RoutingStatus}" == "3" ]]; then
            if [[ "${coreInstallType}" == "1" ]]; then
                unInstallRouting socks5_outbound outboundTag || { socks5RoutingRollback "${backupDir}" "Socks5 卸载失败" false; return 1; }
                removeXrayOutbound socks5_outbound || { socks5RoutingRollback "${backupDir}" "Socks5 卸载失败" false; return 1; }
                addXrayOutbound z_direct_outbound || { socks5RoutingRollback "${backupDir}" "Socks5 卸载失败" false; return 1; }
            fi

            if [[ -n "${singBoxConfigPath}" ]]; then
                removeSingBoxConfig socks5_outbound || { socks5RoutingRollback "${backupDir}" "Socks5 卸载失败" false; return 1; }
                removeSingBoxConfig socks5_01_outbound_route || { socks5RoutingRollback "${backupDir}" "Socks5 卸载失败" false; return 1; }
                removeSingBoxConfig 20_socks5_inbounds || { socks5RoutingRollback "${backupDir}" "Socks5 卸载失败" false; return 1; }
                removeSingBoxConfig socks5_02_inbound_route || { socks5RoutingRollback "${backupDir}" "Socks5 卸载失败" false; return 1; }
                removeSingBoxConfig sniff_socks5_inbound || { socks5RoutingRollback "${backupDir}" "Socks5 卸载失败" false; return 1; }
                removeSingBoxConfig "strategy_ipv4_only_socks5_inbound" || { socks5RoutingRollback "${backupDir}" "Socks5 卸载失败" false; return 1; }
                removeSingBoxConfig "strategy_ipv6_only_socks5_inbound" || { socks5RoutingRollback "${backupDir}" "Socks5 卸载失败" false; return 1; }

                addSingBoxOutbound 01_direct_outbound || { socks5RoutingRollback "${backupDir}" "Socks5 卸载失败" false; return 1; }
            fi

            stopSocks5SingBox || { socks5RoutingRollback "${backupDir}" "Socks5 服务停止失败" true; return 1; }
        fi
        if ! reloadCore; then
            socks5RoutingRollback "${backupDir}" "Socks5 卸载核心重载失败" true
            return 1
        fi
        padmRemoveCleanupPath "${backupDir}"
        if [[ -n "${socks5InboundPort}" ]]; then
            local firewallStatus=0
            denyPort "${socks5InboundPort}" || firewallStatus=1
            denyPort "${socks5InboundPort}" udp || firewallStatus=1
            if [[ "${firewallStatus}" != "0" ]]; then
                errorCard "Socks5 入站已卸载，但防火墙规则回收失败，请检查防火墙状态"
                return 1
            fi
        fi
        successCard "卸载完毕"
    done
}
# 写入 Socks5 入站配置
writeSocks5InboundConfig() {
    local targetPath=$1
    local listenPort=$2
    local uuid=$3
    local inboundConfig
    inboundConfig=$(jq -n \
      --argjson listenPort "${listenPort}" \
      --arg uuid "${uuid}" \
      '{inbounds:[{type:"socks", listen:"::", listen_port:$listenPort, tag:"socks5_inbound", users:[{username:$uuid, password:$uuid}]}]}') || return 1
    writeRoutingJsonConfig "${targetPath}" <<<"${inboundConfig}"
}

# Socks5 入站配置
setSocks5Inbound() {

    echoContent title "\n┌─ 配置 Socks5 入站 ─────────────────────────────────"
    menuLine "解锁机、落地机入站配置"
    menuClose
    echoContent title "\n┌─ Socks5 入站端口 ─────────────────────────────────"
    echo
    readSingBoxPortResult result "${singBoxSocks5Port}" || return 1
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
    if [[ -z "${socks5RoutingUUID}" ]]; then
        errorCard "UUID生成失败"
        return 1
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
        return 1
    fi
    local socks5InboundPath="${singBoxConfigPath:-/etc/padm/sing-box/conf/config/}20_socks5_inbounds.json"
    writeSocks5InboundConfig "${socks5InboundPath}" "${result[-1]}" "${socks5RoutingUUID}" || return 1
    setStrategyRouting socks5_inbound "${domainStrategy}" || return 1
}


# Socks5 inbound routing 规则
setSocks5InboundRouting() {

    singBoxConfigPath="${singBoxConfigPath:-/etc/padm/sing-box/conf/config/}"
    local action="${1:-}"

    if [[ "${action}" == "addRules" && ! -f "${singBoxConfigPath}socks5_02_inbound_route.json" && ! -f "${configPath}09_routing.json" ]]; then
        errorCard "请安装入站分流后再添加分流规则"
        errorCard "如已选择允许所有网站，请重新安装分流后设置规则"
        return 1
    fi
    local socks5InboundRoutingIPs=
    if [[ "${action}" == "addRules" ]]; then
        socks5InboundRoutingIPs=$(jq .route.rules[0].source_ip_cidr "${singBoxConfigPath}socks5_02_inbound_route.json") || return 1
    else
        echoContent title "\n┌─ Socks5 入站访问源 ────────────────────────────────"
        menuLine "请输入允许访问的 IP 地址，多个 IP 用英文逗号分隔"
        menuLine "示例：1.1.1.1,2.2.2.2"
        menuClose
        autoRead socks5_inbound_source_ips "IP:" socks5InboundRoutingIPs

        if [[ -z "${socks5InboundRoutingIPs}" ]]; then
            coreIPRequiredErrorCard
            return 1
        fi
        socks5InboundRoutingIPs=$(echo "\"${socks5InboundRoutingIPs}"\" | jq -c '.|split(",")') || return 1
    fi

    echoContent title "\n┌─ Socks5 域名分流 ─────────────────────────────────"
    menuLine "请输入要分流的域名"
    menuLine "支持 Xray-core geosite 匹配，支持 sing-box 1.8+ rule_set 匹配"
    menuLine "非增量添加，会替换原有规则；无法匹配则使用 domain 精确匹配"
    menuClose

    autoRead socks5_inbound_allow_all "是否允许所有网站？请选择[y/n]:" socks5InboundRoutingDomainStatus
    if [[ "${socks5InboundRoutingDomainStatus}" == "y" ]]; then
        addSingBoxRouteRule "01_direct_outbound" "" "socks5_02_inbound_route" || return 1
        updateRoutingJsonConfig "${singBoxConfigPath}socks5_02_inbound_route.json" '.route.rules[0].inbound = ["socks5_inbound"] | .route.rules[0].source_ip_cidr = $sourceIPs' --argjson sourceIPs "${socks5InboundRoutingIPs}" || return 1

        addSingBoxOutbound "01_direct_outbound" || return 1
    else
        echoContent yellow "录入示例:netflix,openai,example.com\n"
        autoRead socks5_inbound_domains "域名:" socks5InboundRoutingDomain
        if [[ -z "${socks5InboundRoutingDomain}" ]]; then
            coreDomainRequiredErrorCard
            return 1
        fi
        addSingBoxRouteRule "01_direct_outbound" "${socks5InboundRoutingDomain}" "socks5_02_inbound_route" || return 1
        updateRoutingJsonConfig "${singBoxConfigPath}socks5_02_inbound_route.json" '.route.rules[0].inbound = ["socks5_inbound"] | .route.rules[0].source_ip_cidr = $sourceIPs' --argjson sourceIPs "${socks5InboundRoutingIPs}" || return 1

        addSingBoxOutbound "01_direct_outbound" || return 1
    fi

}


# Socks5 出站
setSocks5Outbound() {

    echoContent title "\n┌─ 配置 Socks5 出站 ─────────────────────────────────"
    menuLine "转发机、代理机出站配置"
    menuClose
    echo
    autoRead socks5_outbound_ip "请输入落地机IP地址:" socks5RoutingOutboundIP
    if [[ -z "${socks5RoutingOutboundIP}" ]]; then
        coreIPRequiredErrorCard
        return 1
    fi
    echo
    autoRead socks5_outbound_port "请输入落地机端口:" socks5RoutingOutboundPort
    if ! validPortNumber "${socks5RoutingOutboundPort}"; then
        errorCard "端口不合法"
        return 1
    fi
    echo
    autoRead socks5_outbound_username "请输入用户名:" socks5RoutingOutboundUserName
    if [[ -z "${socks5RoutingOutboundUserName}" ]]; then
        errorCard "用户名不可为空"
        return 1
    fi
    echo
    autoRead socks5_outbound_password "请输入用户密码:" socks5RoutingOutboundPassword
    if [[ -z "${socks5RoutingOutboundPassword}" ]]; then
        errorCard "用户密码不可为空"
        return 1
    fi
    echo
    if [[ -n "${singBoxConfigPath}" ]]; then
        local singBoxOutbound
        singBoxOutbound=$(jq -n \
          --arg server "${socks5RoutingOutboundIP}" \
          --argjson serverPort "${socks5RoutingOutboundPort}" \
          --arg username "${socks5RoutingOutboundUserName}" \
          --arg password "${socks5RoutingOutboundPassword}" \
          '{outbounds:[{type:"socks", tag:"socks5_outbound", server:$server, server_port:$serverPort, version:"5", username:$username, password:$password}]}') || return 1
        writeRoutingJsonConfig "${singBoxConfigPath}socks5_outbound.json" <<<"${singBoxOutbound}" || return 1
    fi
    if [[ "${coreInstallType}" == "1" ]]; then
        addXrayOutbound socks5_outbound || return 1
    fi
}

# Socks5 outbound routing 规则
setSocks5OutboundRouting() {
    local action="${1:-}"

    if [[ "${action}" == "addRules" && ! -f "${singBoxConfigPath}socks5_01_outbound_route.json" && ! -f "${configPath}09_routing.json" ]]; then
        errorCard "请安装出站分流后再添加分流规则"
        return 1
    fi

    echoContent title "\n┌─ Socks5 域名分流 ─────────────────────────────────"
    menuLine "请输入要分流的域名"
    menuLine "支持 Xray-core geosite 匹配，支持 sing-box 1.8+ rule_set 匹配"
    menuLine "非增量添加，会替换原有规则；无法匹配则使用 domain 精确匹配"
    menuClose
    echoContent yellow "录入示例:netflix,openai,example.com\n"
    autoRead socks5_outbound_domains "域名:" socks5RoutingOutboundDomain
    if [[ -z "${socks5RoutingOutboundDomain}" ]]; then
        coreDomainRequiredErrorCard
        return 1
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        addSingBoxOutbound "01_direct_outbound" || return 1
        addSingBoxRouteRule "socks5_outbound" "${socks5RoutingOutboundDomain}" "socks5_01_outbound_route" || return 1
    fi

    if [[ "${coreInstallType}" == "1" ]]; then

        unInstallRouting "socks5_outbound" "outboundTag" || return 1
        local domainRules=[]
        local routingRule=
        while read -r line; do
            if echo "${routingRule}" | grep -q "${line}"; then
                coreRuleExistsStatusCard "${line} 已存在，跳过"
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
        updateRoutingJsonConfig "${configPath}09_routing.json" '.routing.rules += [{"type": "field","domain": $domainRules,"outboundTag": "socks5_outbound"}]' --argjson domainRules "${domainRules}" || return 1
    fi
}
