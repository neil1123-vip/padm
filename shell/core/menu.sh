#!/usr/bin/env bash

installMenu() {
    while true; do
        echoContent title "\n┌─ 安装与重装 ───────────────────────────────────────"
        if [[ -n "${coreInstallType}" ]]; then
            menuLine "检测到已有安装；以下入口会重建核心与协议配置，请先确认已备份"
        else
            menuLine "首次安装或不知道怎么选时，建议直接选 1；安装后去 订阅与用户 -> 发布与链接 -> 刷新并查看订阅链接"
        fi
        menuLine "怎么选：直连/有域名选 1；需要 CDN/反代选 2；没有域名选 3；需要 TLS 指纹抗性可选 4"
        menuLine "高级：想手选核心和协议选 5；旧客户端、迁移或已有 TLS/fallback 架构选 6"
        menuLine "概念：entry 是客户端连接地址；target/SNI 是 Reality 伪装目标，不是同一个概念"
        menuRecommendedItem 1 "推荐直连 Reality Vision" "新手首选；稳定、配置少，有域名或直连入口都适合"
        menuRecommendedItem 2 "推荐 CDN Reality XHTTP" "需要 CDN/反代时选择；客户端兼容要求更高"
        menuItem 3 "无域名 Reality" "没有域名时选择；用服务器 IP 或自定义 entry-host"
        menuRecommendedItem 4 "TLS 指纹抗性 NaiveProxy" "需要真实域名和证书；不是无域名 Reality 替代"
        menuItem 5 "自定义安装" "手动选择核心和协议组合，适合熟悉参数的人"
        menuItem 6 "传统 TLS 兼容安装" "仅用于旧客户端、迁移或已有 TLS/fallback 架构"
        menuReturnItem 7 "返回主菜单" "回到 padm 管理面板"
        menuClose
        selectInstallType=
        autoRead install_type "请选择:" selectInstallType || return 0
        case "${selectInstallType}" in
        1)
            selectInstallType=2
            selectCoreType=1
            customXrayInstall 1 domain
            return $?
            ;;
        2)
            selectInstallType=2
            selectCoreType=1
            customXrayInstall 2
            return $?
            ;;
        3)
            selectInstallType=3
            selectCoreInstall
            return $?
            ;;
        4)
            selectInstallType=2
            selectCoreType=2
            customSingBoxInstall 5
            return $?
            ;;
        5)
            selectInstallType=2
            selectCoreInstall
            return $?
            ;;
        6)
            selectInstallType=1
            selectCoreInstall
            return $?
            ;;
        7) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

protocolEntryMenu() {
    local selectProtocolMenuType=
    while true; do
        echoContent title "\n┌─ 协议与入口 ───────────────────────────────────────"
        menuLine "这里集中管理客户端入口、入站协议和订阅中的连接地址"
        menuLine "证书/静态站点去 站点与证书；分流/阻断去 路由与访问控制"
        menuItem 1 "REALITY 管理" "目标站、密钥、443 共存分流和 Reality 参数"
        menuItem 2 "XHTTP 管理" "普通/高级/实验分层调整 Reality XHTTP"
        menuItem 3 "Hysteria2 管理" "安装、卸载或管理 UDP 端口跳跃"
        menuItem 4 "Tuic 管理" "安装、卸载和高级参数"
        menuItem 5 "入口端口管理" "为已安装 Xray 追加或移除入口端口"
        menuItem 6 "CDN 入口管理" "订阅入口地址覆盖、CDN/H3 使用说明"
        menuReturnItem 7 "返回主菜单" "回到 padm 管理面板"
        menuClose
        selectProtocolMenuType=
        autoRead protocol_entry_menu "请选择:" selectProtocolMenuType || return 0
        case "${selectProtocolMenuType}" in
        1) manageReality 1 || true; continue ;;
        2) manageXHTTP || true; continue ;;
        3) manageHysteria || true; continue ;;
        4) manageTuic || true; continue ;;
        5) addCorePort 1 || true; continue ;;
        6) manageCDN 1 || true; continue ;;
        7) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

siteCertificateMenu() {
    local selectSiteCertificateMenuType=
    while true; do
        echoContent title "\n┌─ 站点与证书 ───────────────────────────────────────"
        menuLine "这里只维护传统 TLS fallback 站点、302、ALPN 和本机 TLS 证书"
        menuLine "Reality 不使用本机 TLS 证书；这里的证书只服务传统 TLS、站点或订阅"
        menuLine "Reality target/SNI 伪装目标仍由 Reality 目标站管理，二者不要混淆"
        menuItem 1 "传统 TLS fallback 维护" "静态站点、302 重定向、ALPN 诊断/修复"
        menuItem 2 "本机 TLS 证书管理" "续签或查看 /etc/padm/tls 证书"
        menuReturnItem 3 "返回主菜单" "回到 padm 管理面板"
        menuClose
        selectSiteCertificateMenuType=
        autoRead site_certificate_menu "请选择:" selectSiteCertificateMenuType || return 0
        case "${selectSiteCertificateMenuType}" in
        1) manageTraditionalTlsFallback 1 || true; continue ;;
        2) manageTLSCertificates || true; continue ;;
        3) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

routingAccessMenu() {
    local selectRoutingAccessMenuType=
    while true; do
        echoContent title "\n┌─ 路由与访问控制 ───────────────────────────────────"
        menuLine "这里管理服务端出站、分流、BT 阻断和访问限制，不是客户端配置教程"
        menuLine "阻断/区域策略可能影响系统更新、证书申请和应用连接，执行前先看说明"
        menuItem 1 "分流工具" "WARP、IPv6、Socks5、DNS/hosts 覆盖"
        menuItem 2 "BT 下载管理" "P2P/BT 下载访问控制"
        menuItem 3 "访问控制" "域名/IP 阻断、直连例外、区域阻断"
        menuReturnItem 4 "返回主菜单" "回到 padm 管理面板"
        menuClose
        selectRoutingAccessMenuType=
        autoRead routing_access_menu "请选择:" selectRoutingAccessMenuType || return 0
        case "${selectRoutingAccessMenuType}" in
        1) routingToolsMenu 1 || true; continue ;;
        2) btTools 1 || true; continue ;;
        3) accessControlMenu 1 || true; continue ;;
        4) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

systemScriptMenu() {
    local selectSystemMenuType=
    while true; do
        echoContent title "\n┌─ 系统与脚本 ───────────────────────────────────────"
        menuLine "这里维护 padm 脚本自身和宿主机网络辅助项"
        menuLine "核心版本、服务、日志和配置校验请去 核心与服务"
        menuItem 1 "更新 padm 脚本" "更新脚本文件"
        menuItem 2 "查看脚本安装状态" "显示入口校验、版本、ref 和 manifest"
        menuItem 3 "Fail2ban 防护" "SSH 和 /s/control/ 的最小防护入口"
        menuItem 4 "网络优化" "查看或启用官方 BBR + fq"
        menuReturnItem 5 "返回主菜单" "回到 padm 管理面板"
        menuClose
        selectSystemMenuType=
        autoRead system_script_menu "请选择:" selectSystemMenuType || return 0
        case "${selectSystemMenuType}" in
        1) updatePadm 1 || true; continue ;;
        2) showPadmScriptInstallStatus || true; continue ;;
        3) manageFail2ban || true; continue ;;
        4) bbrInstall || true; continue ;;
        5) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

advancedDangerMenu() {
    local selectDangerMenuType=
    while true; do
        echoContent title "\n┌─ 高级/危险操作 ────────────────────────────────────"
        menuLine "这里只放不可逆、实验性或容易影响现有连接的操作"
        menuDangerItem 1 "卸载脚本" "移除脚本和相关配置，执行前请确认备份"
        menuDangerItem 2 "VLESS Encryption 实验" "Xray-only，高级兼容性实验开关"
        menuReturnItem 3 "返回主菜单" "回到 padm 管理面板"
        menuClose
        selectDangerMenuType=
        autoRead danger_menu "请选择:" selectDangerMenuType || return 0
        case "${selectDangerMenuType}" in
        1) unInstall 1; return $? ;;
        2) manageVlessEncryptionExperiment || true; continue ;;
        3) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

coreDisplayState() {
    case $1 in
    *运行中* | *通过* | *已安装* | *已配置* | *已设置*) uiStyle ok "$1" ;;
    *失败* | *缺失* | *为空*) uiStyle danger "$1" ;;
    *未安装* | *未配置* | *未设置* | *已停止* | *只读*) uiStyle muted "$1" ;;
    *) uiStyle value "$1" ;;
    esac
}

coreMenuServiceState() {
    if ! serviceInstalled "$1"; then
        printf '%s\n' "未安装"
    elif serviceRunning "$1"; then
        printf '%s\n' "运行中"
    else
        printf '%s\n' "已停止"
    fi
}

showCoreStatusOverview() {
    local xrayConfigDir xrayDir xrayBinary reason
    local xrayServiceStatus singBoxServiceStatus nginxServiceStatus
    local xrayVersion="未安装" singBoxVersion="未安装"
    local geoStatus="未安装" geoVersion= geoCron="未设置"
    local xrayConfigStatus="未配置" singBoxConfigStatus="未配置"
    local nginxReasons= nginxReasonText=

    xrayConfigDir=$(coreXrayConfigDir)
    xrayDir=$(dirname "${xrayConfigDir}")
    xrayBinary=$(coreXrayBinaryPath)
    if [[ -x "${xrayBinary}" ]]; then
        xrayVersion=$(xrayBinaryVersion "${xrayBinary}")
    fi
    singBoxVersion=$(getSingBoxCurrentVersion)
    xrayConfigInstalled && xrayConfigStatus="已配置"
    singBoxConfigInstalled && singBoxConfigStatus="已配置"
    if [[ -s "${xrayDir}/geosite.dat" && -s "${xrayDir}/geoip.dat" ]]; then
        geoStatus="已安装"
        geoVersion=$(xrayGeoDisplayVersion "${xrayDir}")
    elif [[ -x "${xrayBinary}" ]]; then
        geoStatus="缺失或为空"
    fi
    crontab -l 2>/dev/null | grep -q "UpdateGeo" && geoCron="已设置"
    nginxReasons=$(nginxRuntimeReasons)
    while IFS= read -r reason; do
        [[ -n "${reason}" ]] || continue
        nginxReasonText+="${nginxReasonText:+、}${reason}"
    done <<<"${nginxReasons}"
    xrayServiceStatus=$(coreMenuServiceState xray)
    singBoxServiceStatus=$(coreMenuServiceState sing-box)
    nginxServiceStatus=$(coreMenuServiceState nginx)

    echoContent title "\n┌─ 核心状态总览 ─────────────────────────────────────"
    menuLine "Xray-core: $(coreDisplayState "${xrayVersion}")"
    menuLine "Xray 服务: $(coreDisplayState "${xrayServiceStatus}")"
    menuLine "Xray 配置: $(coreDisplayState "${xrayConfigStatus}")"
    if [[ -n "${geoVersion}" ]]; then
        menuLine "Xray Geo: $(coreDisplayState "${geoStatus}") / $(coreDisplayState "${geoVersion}") / 自动更新 $(coreDisplayState "${geoCron}")"
    else
        menuLine "Xray Geo: $(coreDisplayState "${geoStatus}") / 自动更新 $(coreDisplayState "${geoCron}")"
    fi
    menuLine "sing-box: $(coreDisplayState "${singBoxVersion}")"
    menuLine "sing-box 服务: $(coreDisplayState "${singBoxServiceStatus}")"
    menuLine "sing-box 配置: $(coreDisplayState "${singBoxConfigStatus}")"
    if [[ -n "${nginxReasonText}" ]]; then
        menuLine "Nginx 服务: $(coreDisplayState "${nginxServiceStatus}") / padm 依赖: ${nginxReasonText}"
    elif [[ "${nginxServiceStatus}" != "未安装" ]]; then
        menuLine "Nginx 服务: $(coreDisplayState "${nginxServiceStatus}") / $(coreDisplayState "只读")（非 padm 当前依赖）"
    else
        menuLine "Nginx 服务: $(coreDisplayState "未安装")"
    fi
    menuMutedLine "首页只读取本地状态；版本和预发布信息仅在明确动作时获取"
    menuClose
}

xrayVersionManageMenu() {
    local selectXrayType version rollbackStatus
    while true; do
        echoContent title "\n┌─ Xray-core 生命周期 ────────────────────────────────"
        menuItem 1 "升级稳定版" "下载并校验最新稳定版后替换"
        menuItem 2 "升级预发布版" "下载、试跑并确认后替换"
        menuItem 3 "回退稳定版" "选择最近的稳定版本回退"
        menuItem 4 "检查当前配置" "执行运行检查和内部严格检查"
        menuItem 5 "扫描升级风险" "只读扫描已知不兼容配置"
        menuItem 6 "试跑预发布版" "不替换二进制，不操作服务"
        menuReturnItem 7 "返回核心与服务" "回到核心与服务"
        menuClose
        selectXrayType=
        autoRead xray_lifecycle_menu "请选择:" selectXrayType || return 0
        case "${selectXrayType}" in
        1 | 2 | 3 | 4)
            if ! xrayInstalled; then
                statusCard "Xray-core 生命周期" "无法检查" "未安装 Xray-core；请返回主菜单使用安装与重装"
                continue
            fi
            ;;
        esac
        case "${selectXrayType}" in
        1) upgradeXrayCore false || true ;;
        2) upgradeXrayCore true || true ;;
        3)
            version=
            rollbackStatus=0
            selectRollbackVersion XTLS/Xray-core "Xray-core" version || rollbackStatus=$?
            if [[ "${rollbackStatus}" -eq 0 ]]; then
                upgradeXrayCore false "${version}" || true
            elif [[ "${rollbackStatus}" -eq 1 ]]; then
                coreInvalidInputErrorCard
            fi
            ;;
        4) showXrayConfigHealthCheck || true ;;
        5) showXrayCompatibilityAudit || true ;;
        6) checkXrayPrereleaseCompatibility || true ;;
        7) return 0 ;;
        *) coreInvalidInputErrorCard ;;
        esac
    done
}

singBoxVersionManageMenu() {
    local selectSingBoxType version rollbackStatus
    while true; do
        echoContent title "\n┌─ sing-box 生命周期 ─────────────────────────────────"
        menuItem 1 "升级稳定版" "下载并校验最新稳定版后替换"
        menuItem 2 "升级预发布版" "下载、试跑并确认后替换"
        menuItem 3 "回退稳定版" "选择最近的稳定版本回退"
        menuItem 4 "检查当前配置" "执行 merge + check"
        menuItem 5 "扫描升级风险" "只读扫描 1.13/1.14 迁移风险"
        menuItem 6 "试跑预发布版" "不替换二进制，不操作服务"
        menuReturnItem 7 "返回核心与服务" "回到核心与服务"
        menuClose
        selectSingBoxType=
        autoRead singbox_lifecycle_menu "请选择:" selectSingBoxType || return 0
        case "${selectSingBoxType}" in
        1 | 2 | 3 | 4)
            if ! singBoxInstalled; then
                statusCard "sing-box 生命周期" "无法检查" "未安装 sing-box；请返回主菜单使用安装与重装"
                continue
            fi
            ;;
        esac
        case "${selectSingBoxType}" in
        1) upgradeSingBoxCore false || true ;;
        2) upgradeSingBoxCore true || true ;;
        3)
            version=
            rollbackStatus=0
            selectRollbackVersion SagerNet/sing-box "sing-box" version || rollbackStatus=$?
            if [[ "${rollbackStatus}" -eq 0 ]]; then
                upgradeSingBoxCore false "${version}" || true
            elif [[ "${rollbackStatus}" -eq 1 ]]; then
                coreInvalidInputErrorCard
            fi
            ;;
        4) showSingBoxConfigValidation || true ;;
        5) showSingBoxCompatibilityAudit || true ;;
        6) checkSingBoxPrereleaseCompatibility || true ;;
        7) return 0 ;;
        *) coreInvalidInputErrorCard ;;
        esac
    done
}

coreServiceControlAction() {
    local serviceName=$1 action=$2 actionName=$2
    if ! serviceInstalled "${serviceName}"; then
        statusCard "${serviceName} 服务" "无法检查" "服务未安装"
        return 2
    fi
    case "${action}" in
    start) actionName="启动" ;;
    stop) actionName="停止" ;;
    restart) actionName="重启" ;;
    reload) actionName="reload" ;;
    *) errorCard "服务操作不支持: ${action}"; return 1 ;;
    esac
    if ! runServiceAction "${serviceName}" "${action}"; then
        errorCard "${serviceName} 服务${actionName}失败"
        return 1
    fi
    statusCard "${serviceName} 服务" "${actionName}完成"
}

coreServiceControlMenu() {
    local serviceName=$1 title=$1 selectServiceAction= confirm= serviceStatus=
    [[ "${serviceName}" == "xray" ]] && title="Xray-core"
    [[ "${serviceName}" == "nginx" ]] && title="Nginx"
    if [[ "${serviceName}" == "nginx" ]] && ! nginxRuntimeRequired; then
        statusCard "Nginx 服务" "只读" "未检测到 padm 当前依赖，未执行服务动作"
        return 0
    fi
    while true; do
        serviceStatus=$(coreMenuServiceState "${serviceName}")
        echoContent title "\n┌─ ${title} 服务控制 ─────────────────────────────────"
        menuLine "当前状态: $(coreDisplayState "${serviceStatus}")"
        menuItem 1 "启动" "服务已运行时不重复启动"
        menuItem 2 "停止" "会中断当前连接，执行前再次确认"
        menuItem 3 "重启" "完整停止后重新启动"
        if [[ "${serviceName}" == "nginx" ]]; then
            if [[ "${serviceStatus}" == "运行中" ]]; then
                menuItem 4 "reload" "先执行 nginx -t，再平滑重载"
            else
                menuItem 4 "reload（不可用）" "Nginx 未运行，无法平滑重载"
            fi
            menuReturnItem 5 "返回服务运行态" "回到服务列表"
        else
            menuReturnItem 4 "返回服务运行态" "回到服务列表"
        fi
        menuClose
        selectServiceAction=
        autoRead core_service_control "请选择:" selectServiceAction || return 0
        case "${selectServiceAction}" in
        1) coreServiceControlAction "${serviceName}" start || true ;;
        2)
            confirm=
            autoConfirm core_service_stop "停止 ${title} 会中断连接，确认继续？" n confirm || return 0
            if [[ "${confirm}" == "y" ]]; then
                coreServiceControlAction "${serviceName}" stop || true
            else
                coreCancelledStatusCard "未停止 ${title}"
            fi
            ;;
        3) coreServiceControlAction "${serviceName}" restart || true ;;
        4)
            if [[ "${serviceName}" == "nginx" ]]; then
                if [[ "${serviceStatus}" == "运行中" ]]; then
                    coreServiceControlAction nginx reload || true
                else
                    statusCard "Nginx reload" "不可用" "Nginx 未运行，未执行服务动作"
                fi
            else
                return 0
            fi
            ;;
        5) [[ "${serviceName}" == "nginx" ]] && return 0 || coreInvalidInputErrorCard ;;
        *) coreInvalidInputErrorCard ;;
        esac
    done
}

coreAllServicesMenu() {
    local selectCoreService= nginxReasons=
    while true; do
        nginxReasons=$(nginxRuntimeReasons)
        echoContent title "\n┌─ 服务运行态 ───────────────────────────────────────"
        menuLine "Xray: $(coreDisplayState "$(coreMenuServiceState xray)") / sing-box: $(coreDisplayState "$(coreMenuServiceState sing-box)") / Nginx: $(coreDisplayState "$(coreMenuServiceState nginx)")"
        menuItem 1 "Xray 服务" "启动、停止或重启 Xray"
        menuItem 2 "sing-box 服务" "启动、停止或重启 sing-box"
        if [[ -n "${nginxReasons}" ]]; then
            menuItem 3 "Nginx 服务" "padm 当前依赖；运行时可 reload"
        else
            menuItem 3 "Nginx 服务（只读）" "非 padm 当前依赖，不提供服务动作"
        fi
        menuReturnItem 4 "返回核心与服务" "回到核心与服务"
        menuClose
        selectCoreService=
        autoRead core_services_menu "请选择:" selectCoreService || return 0
        case "${selectCoreService}" in
        1) coreServiceControlMenu xray ;;
        2) coreServiceControlMenu sing-box ;;
        3)
            if [[ -n "${nginxReasons}" ]]; then
                coreServiceControlMenu nginx
            else
                statusCard "Nginx 服务" "只读" "未检测到 padm 当前依赖，未执行服务动作"
            fi
            ;;
        4) return 0 ;;
        *) coreInvalidInputErrorCard ;;
        esac
    done
}

coreLogsMenu() {
    local logStatus= selectLogs=
    while true; do
        logStatus=false
        if [[ -f "$(singBoxLogConfigFile)" ]] && [[ "$(jq -r .log.disabled "$(singBoxLogConfigFile)" 2>/dev/null)" == "false" ]]; then
            logStatus=true
        fi
        echoContent title "\n┌─ 日志与诊断 ───────────────────────────────────────"
        menuItem 1 "Xray 日志管理" "查看 access/error 或调整日志"
        menuItem 2 "sing-box 实时日志" "实时查看 box.log"
        if [[ "${logStatus}" == "true" ]]; then
            menuItem 3 "关闭 sing-box 调试日志" "停止记录调试日志"
        else
            menuItem 3 "开启 sing-box 调试日志" "记录调试日志并实时查看"
        fi
        menuItem 4 "Nginx 配置检查" "执行 nginx -t，不重载服务"
        menuReturnItem 5 "返回核心与服务" "回到核心与服务"
        menuClose
        selectLogs=
        autoRead core_logs_menu "请选择:" selectLogs || return 0
        case "${selectLogs}" in
        1) checkLog 1 || true ;;
        2)
            mkdir -p /etc/padm/sing-box/conf
            touch /etc/padm/sing-box/conf/box.log >/dev/null 2>&1
            tail -f /etc/padm/sing-box/conf/box.log
            ;;
        3)
            if singBoxLog "${logStatus}" && [[ "${logStatus}" == "false" ]]; then
                mkdir -p /etc/padm/sing-box/conf
                touch /etc/padm/sing-box/conf/box.log >/dev/null 2>&1
                tail -f /etc/padm/sing-box/conf/box.log
            fi
            ;;
        4) checkNginxConfig || true ;;
        5) return 0 ;;
        *) coreInvalidInputErrorCard ;;
        esac
    done
}

xrayGeoDataMenu() {
    local selectGeoAction=
    while true; do
        echoContent title "\n┌─ Xray Geo 数据 ────────────────────────────────────"
        menuItem 1 "更新 Xray Geo 数据" "更新 geosite.dat / geoip.dat"
        menuItem 2 "查看 Xray Geo 状态" "查看文件、版本和自动更新状态"
        menuItem 3 "设置 Xray Geo 自动更新" "每天凌晨更新规则数据"
        menuReturnItem 4 "返回核心与服务" "回到核心与服务"
        menuClose
        selectGeoAction=
        autoRead xray_geo_menu "请选择:" selectGeoAction || return 0
        case "${selectGeoAction}" in
        1) updateGeoSite || true ;;
        2) showXrayGeoStatus || true ;;
        3) installCronUpdateGeo || true ;;
        4) return 0 ;;
        *) coreInvalidInputErrorCard ;;
        esac
    done
}

coreVersionManageMenu() {
    local selectCore=
    while true; do
        showCoreStatusOverview
        echoContent title "\n┌─ 核心与服务 ───────────────────────────────────────"
        menuLine "安装与重装只在主菜单；未安装时仍可查看状态和只读扫描"
        menuItem 1 "Xray-core 生命周期" "升级、回退和三项配置检查"
        menuItem 2 "sing-box 生命周期" "升级、回退和三项配置检查"
        menuItem 3 "服务运行态" "Xray、sing-box 和 padm 依赖的 Nginx"
        menuItem 4 "日志与诊断" "Xray、sing-box 日志和 Nginx 配置检查"
        menuItem 5 "Xray Geo 数据" "更新、查看状态或设置自动更新"
        menuReturnItem 6 "返回主菜单" "回到 padm 管理面板"
        menuClose
        selectCore=
        autoRead core_manage_menu "请选择:" selectCore || return 0
        case "${selectCore}" in
        1) xrayVersionManageMenu ;;
        2) singBoxVersionManageMenu ;;
        3) coreAllServicesMenu ;;
        4) coreLogsMenu ;;
        5) xrayGeoDataMenu ;;
        6) return 0 ;;
        *) coreInvalidInputErrorCard ;;
        esac
    done
}

menu() {
    cd "$HOME" || return 1
    if ! mkdirTools; then
        errorCard "初始化安装目录失败"
        return 1
    fi
    checkWgetShowProgress
    aliasInstall || return 1
    while true; do
        echoContent title "\n┌─ padm 管理面板 ───────────────────────────────────"
        menuLine "Xray-core / sing-box 节点安装与运维脚本"
        menuLine "版本：$(getScriptVersion)"
        menuLine "原则：安装、订阅、入口、站点、路由、核心、系统各归一处"
        menuSection "├─ 当前状态 ───────────────────────────────────────"
        if [[ "${PADM_INSTALL_STATUS_READY:-}" == "1" ]]; then
            showInstallStatus cached
        else
            showInstallStatus
        fi
        menuSection "├─ 任务入口 ───────────────────────────────────────"
        menuItem 1 "安装与重装" "含新手选择指引；推荐直连/CDN/无域名 Reality、NaiveProxy、自定义和传统 TLS"
        menuItem 2 "订阅与用户" "发布链接、创建和维护分享订阅、流量限额与多服务器同步"
        menuItem 3 "协议与入口" "REALITY、XHTTP、Hysteria2、Tuic、入口端口和 CDN 入口"
        menuItem 4 "站点与证书" "传统 TLS fallback 站点、302、ALPN 和 TLS 证书"
        menuItem 5 "路由与访问控制" "分流、BT、域名/IP 阻断、直连例外和区域阻断"
        menuItem 6 "核心与服务" "核心生命周期、服务运行态、日志诊断和 Xray Geo 数据"
        menuItem 7 "系统与脚本" "更新 padm、网络优化和宿主机辅助项"
        menuDangerItem 8 "高级/危险操作" "卸载和实验性高风险开关"
        menuLine "新人建议：1 安装与重装里先看怎么选；安装后 2 查看订阅"
        menuClose
        autoRead main_menu "请选择:" selectMainMenuType || return 0
        PADM_INSTALL_STATUS_READY=0
        case ${selectMainMenuType} in
        1)
            installMenu || return $?
            [[ "${AUTO_INSTALL:-}" == "true" ]] && return 0
            ;;
        2)
            manageSubscription 1
            ;;
        3)
            protocolEntryMenu
            ;;
        4)
            siteCertificateMenu
            ;;
        5)
            routingAccessMenu
            ;;
        6)
            coreVersionManageMenu 1
            continue
            ;;
        7)
            systemScriptMenu
            ;;
        8)
            advancedDangerMenu
            ;;
        *)
            coreInvalidInputErrorCard
            ;;
        esac
        continue
    done
}
