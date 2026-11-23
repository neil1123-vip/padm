#!/usr/bin/env bash

installMenu() {
    while true; do
        echoContent title "\n┌─ 安装与重装 ───────────────────────────────────────"
        if [[ -n "${coreInstallType}" ]]; then
            menuLine "重装会重建核心与协议配置，请先备份"
            menuMutedLine "只需补装 Hysteria2 或 Tuic 时，请到「协议与入口」增量安装"
        fi
        menuRecommendedItem 1 "推荐直连 Reality Vision" "首次安装推荐，使用自有域名直连"
        menuRecommendedItem 2 "推荐 CDN Reality XHTTP" "适合 CDN 或反代，客户端需支持 XHTTP"
        menuItem 3 "无域名 Reality" "使用服务器 IP 或自定义入口"
        menuRecommendedItem 4 "TLS 指纹抗性 NaiveProxy" "需自有域名和可信证书"
        menuItem 5 "自定义安装" "手动选择核心和协议"
        menuItem 6 "传统 TLS 兼容安装" "兼容旧客户端或迁移已有 TLS fallback"
        menuReturnItem 0 "返回主菜单"
        menuClose
        selectInstallType=
        menuReadChoice install_type "请选择:" selectInstallType interactive || return 0
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
        4)
            selectInstallType=2
            selectCoreType=2
            customSingBoxInstall 5
            return $?
            ;;
        3 | 5 | 6)
            case "${selectInstallType}" in
            5) selectInstallType=2 ;;
            6) selectInstallType=1 ;;
            esac
            selectCoreInstall || return $?
            [[ "${selectCoreType:-}" != 0 ]] || continue
            return 0
            ;;
        0) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

protocolEntryMenu() {
    local selectProtocolMenuType=
    while true; do
        echoContent title "\n┌─ 协议与入口 ───────────────────────────────────────"
        menuItem 1 "查看全部协议链接" "查看本机节点链接和二维码"
        menuItem 2 "REALITY 管理" "目标站、密钥和 443 共存分流"
        menuItem 3 "XHTTP 管理" "设置传输、XMUX 和独立下行"
        menuItem 4 "Hysteria2 管理" "安装、卸载和端口跳跃"
        menuItem 5 "Tuic 管理" "安装、卸载和高级参数"
        menuItem 6 "额外入口端口管理" "为 Xray 添加或删除监听端口"
        menuItem 7 "CDN 入口管理" "覆盖订阅中的入口地址"
        menuReturnItem 0 "返回主菜单"
        menuClose
        menuReadChoice protocol_entry_menu "请选择:" selectProtocolMenuType interactive || return 0
        case "${selectProtocolMenuType}" in
        1) showLocalProtocolLinks || true ;;
        2) manageReality 1 || true ;;
        3) manageXHTTP || true ;;
        4) manageHysteria || true ;;
        5) manageTuic || true ;;
        6) addCorePort 1 || true ;;
        7) manageCDN 1 || true ;;
        0) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

siteCertificateMenu() {
    local selectSiteCertificateMenuType=
    while true; do
        echoContent title "\n┌─ 站点与证书 ───────────────────────────────────────"
        menuMutedLine "本机证书供传统 TLS、站点和订阅发布使用"
        menuItem 1 "传统 TLS fallback 维护" "重建站点配置、设置重定向和 ALPN"
        menuItem 2 "本机 TLS 证书管理" "续签或查看 /etc/padm/tls 证书"
        menuItem 3 "本地静态站点" "导入网站或使用内置布局"
        menuReturnItem 0 "返回主菜单"
        menuClose
        selectSiteCertificateMenuType=
        menuReadChoice site_certificate_menu "请选择:" selectSiteCertificateMenuType interactive || return 0
        case "${selectSiteCertificateMenuType}" in
        1) manageTraditionalTlsFallback 1 || true; continue ;;
        2) manageTLSCertificates || true; continue ;;
        3) manageTraditionalTlsStaticSite || true; continue ;;
        0) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

routingAccessMenu() {
    local selectRoutingAccessMenuType=
    while true; do
        echoContent title "\n┌─ 路由与访问控制 ───────────────────────────────────"
        menuMutedLine "阻断规则可能影响系统更新、证书申请和应用连接"
        menuItem 1 "分流工具" "WARP、IPv6、Socks5、DNS/hosts 覆盖"
        menuItem 2 "BT 下载管理" "查看和设置 BT 下载限制"
        menuItem 3 "访问控制" "域名/IP 阻断、直连例外、区域阻断"
        menuReturnItem 0 "返回主菜单"
        menuClose
        selectRoutingAccessMenuType=
        menuReadChoice routing_access_menu "请选择:" selectRoutingAccessMenuType interactive || return 0
        case "${selectRoutingAccessMenuType}" in
        1) routingToolsMenu 1 || true; continue ;;
        2) btTools 1 || true; continue ;;
        3) accessControlMenu 1 || true; continue ;;
        0) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

systemScriptMenu() {
    local selectSystemMenuType=
    while true; do
        echoContent title "\n┌─ 系统与脚本 ───────────────────────────────────────"
        menuItem 1 "更新 padm 脚本"
        menuItem 2 "查看脚本安装状态" "版本、安装来源和文件校验"
        menuItem 3 "Fail2ban 防护" "SSH 和订阅控制接口防护"
        menuItem 4 "网络优化" "查看或启用 BBR + fq"
        menuReturnItem 0 "返回主菜单"
        menuClose
        selectSystemMenuType=
        menuReadChoice system_script_menu "请选择:" selectSystemMenuType interactive || return 0
        case "${selectSystemMenuType}" in
        1) updatePadm 1 || true; continue ;;
        2) showPadmScriptInstallStatus || true; continue ;;
        3) manageFail2ban || true; continue ;;
        4) bbrInstall || true; continue ;;
        0) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

advancedDangerMenu() {
    local selectDangerMenuType=
    while true; do
        echoContent title "\n┌─ 高级与危险操作 ──────────────────────────────────"
        menuDangerItem 1 "卸载脚本" "移除脚本和相关配置，请先备份"
        menuDangerItem 2 "VLESS Encryption 实验" "仅支持 Xray，启用前请核对客户端兼容性"
        menuReturnItem 0 "返回主菜单"
        menuClose
        selectDangerMenuType=
        menuReadChoice danger_menu "请选择:" selectDangerMenuType interactive || return 0
        case "${selectDangerMenuType}" in
        1) unInstall 1; return $? ;;
        2) manageVlessEncryptionExperiment || true; continue ;;
        0) return 0 ;;
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
    local xrayDir xrayBinary reason
    local xrayServiceStatus singBoxServiceStatus nginxServiceStatus
    local xrayVersion="未安装" singBoxVersion="未安装" singBoxApiStatus="无法检查"
    local geoStatus="未安装" geoVersion= geoCron="未设置"
    local xrayConfigStatus="未配置" singBoxConfigStatus="未配置"
    local nginxReasons= nginxReasonText=

    xrayDir=$(coreXrayInstallDir)
    xrayBinary=$(coreXrayBinaryPath)
    if coreExecutableFile "${xrayBinary}"; then
        xrayVersion=$(xrayBinaryVersion "${xrayBinary}")
    fi
    singBoxVersion=$(getSingBoxCurrentVersion)
    case "$(singBoxV2rayApiCapability)" in
    supported) singBoxApiStatus="支持" ;;
    unsupported) singBoxApiStatus="不支持，需升级统计版" ;;
    esac
    xrayConfigInstalled && xrayConfigStatus="已配置"
    singBoxConfigInstalled && singBoxConfigStatus="已配置"
    if [[ -s "${xrayDir}/geosite.dat" && -s "${xrayDir}/geoip.dat" ]]; then
        geoStatus="已安装"
        geoVersion=$(xrayGeoDisplayVersion "${xrayDir}")
    elif coreExecutableFile "${xrayBinary}"; then
        geoStatus="缺失或为空"
    fi
    crontab -l 2>/dev/null | padmMaintenanceCronActive UpdateGeo && geoCron="已设置"
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
    menuLine "sing-box 用户统计能力: $(coreDisplayState "${singBoxApiStatus}")"
    menuLine "sing-box 服务: $(coreDisplayState "${singBoxServiceStatus}")"
    menuLine "sing-box 配置: $(coreDisplayState "${singBoxConfigStatus}")"
    if [[ -n "${nginxReasonText}" ]]; then
        menuLine "Nginx 服务: $(coreDisplayState "${nginxServiceStatus}") / padm 依赖: ${nginxReasonText}"
    elif [[ "${nginxServiceStatus}" != "未安装" ]]; then
        menuLine "Nginx 服务: $(coreDisplayState "${nginxServiceStatus}") / $(coreDisplayState "只读")（非 padm 当前依赖）"
    else
        menuLine "Nginx 服务: $(coreDisplayState "未安装")"
    fi
    menuClose
}

coreLifecycleMenu() {
    local core=$1 title repo menuKey installedFn upgradeFn checkFn auditFn
    local upgradeText
    local selection version versionStatus prerelease
    case "${core}" in
    xray)
        title=Xray-core repo=XTLS/Xray-core menuKey=xray_lifecycle_menu
        installedFn=xrayInstalled upgradeFn=upgradeXrayCore checkFn=showXrayConfigHealthCheck
        auditFn=showXrayCompatibilityAudit
        upgradeText="选择正式版或预发布版，支持升级与回退"
        ;;
    sing-box)
        title=sing-box repo=SagerNet/sing-box menuKey=singbox_lifecycle_menu
        installedFn=singBoxInstalled upgradeFn=upgradeSingBoxCore checkFn=showSingBoxConfigValidation
        auditFn=showSingBoxCompatibilityAudit
        upgradeText="选择正式版或预发布版，缺包时可本机编译"
        ;;
    *) return 1 ;;
    esac
    while true; do
        echoContent title "\n┌─ ${title} 生命周期 ─────────────────────────────────"
        menuItem 1 "升级/切换版本" "${upgradeText}"
        menuItem 2 "检查与诊断" "校验配置，检查升级风险"
        menuReturnItem 0 "返回核心与服务"
        menuClose
        selection=
        menuReadChoice "${menuKey}" "请选择:" selection interactive || return 0
        case "${selection}" in
        1)
            if ! "${installedFn}"; then
                statusCard "${title} 生命周期" "无法检查" "未安装 ${title}；请返回主菜单使用安装与重装"
                continue
            fi
            ;;
        esac
        case "${selection}" in
        1)
            version=
            prerelease=false
            versionStatus=0
            selectCoreVersion "${repo}" "${title}" version prerelease || versionStatus=$?
            if [[ "${versionStatus}" -eq 0 ]]; then
                "${upgradeFn}" "${prerelease}" "${version}" || true
            elif [[ "${versionStatus}" -eq 1 ]]; then
                coreInvalidInputErrorCard
            fi
            ;;
        2)
            "${checkFn}" || true
            "${auditFn}" || true
            ;;
        0) return 0 ;;
        *) coreInvalidInputErrorCard ;;
        esac
    done
}

xrayVersionManageMenu() {
    coreLifecycleMenu xray
}

singBoxVersionManageMenu() {
    coreLifecycleMenu sing-box
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
        menuItem 1 "启动"
        menuItem 2 "停止" "会中断连接"
        menuItem 3 "重启" "会短暂中断连接"
        if [[ "${serviceName}" == "nginx" ]]; then
            if [[ "${serviceStatus}" == "运行中" ]]; then
                menuItem 4 "reload" "校验配置后平滑重载"
            else
                menuItem 4 "reload（不可用）" "Nginx 未运行，无法平滑重载"
            fi
        fi
        menuReturnItem 0 "返回服务运行态"
        menuClose
        selectServiceAction=
        menuReadChoice core_service_control "请选择:" selectServiceAction interactive || return 0
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
                coreInvalidInputErrorCard
            fi
            ;;
        0) return 0 ;;
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
        menuReturnItem 0 "返回核心与服务"
        menuClose
        selectCoreService=
        menuReadChoice core_services_menu "请选择:" selectCoreService interactive || return 0
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
        0) return 0 ;;
        *) coreInvalidInputErrorCard ;;
        esac
    done
}

coreLogsMenu() {
    local logStatus= selectLogs= logFile=
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
        menuReturnItem 0 "返回核心与服务"
        menuClose
        selectLogs=
        menuReadChoice core_logs_menu "请选择:" selectLogs interactive || return 0
        case "${selectLogs}" in
        1) checkLog 1 || true ;;
        2 | 3)
            if [[ "${selectLogs}" == 3 ]]; then
                singBoxLog "${logStatus}" || continue
                [[ "${logStatus}" == false ]] || continue
            fi
            logFile=$(singBoxLogOutputFile) || continue
            padmEnsureSafeDirectory "$(dirname -- "${logFile}")" &&
                touch "${logFile}" >/dev/null 2>&1 &&
                tail -f "${logFile}"
            ;;
        4) checkNginxConfig || true ;;
        0) return 0 ;;
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
        menuReturnItem 0 "返回核心与服务"
        menuClose
        selectGeoAction=
        menuReadChoice xray_geo_menu "请选择:" selectGeoAction interactive || return 0
        case "${selectGeoAction}" in
        1) updateGeoSite || true ;;
        2) showXrayGeoStatus || true ;;
        3) installCronUpdateGeo || true ;;
        0) return 0 ;;
        *) coreInvalidInputErrorCard ;;
        esac
    done
}

coreVersionManageMenu() {
    local selectCore=
    while true; do
        showCoreStatusOverview
        echoContent title "\n┌─ 核心与服务 ───────────────────────────────────────"
        menuItem 1 "Xray-core 生命周期" "版本切换与配置检查"
        menuItem 2 "sing-box 生命周期" "版本切换与配置检查"
        menuItem 3 "服务运行态" "Xray、sing-box 和 padm 依赖的 Nginx"
        menuItem 4 "日志与诊断" "Xray、sing-box 日志和 Nginx 配置检查"
        menuItem 5 "Xray Geo 数据" "更新、查看状态或设置自动更新"
        menuReturnItem 0 "返回主菜单"
        menuClose
        selectCore=
        menuReadChoice core_manage_menu "请选择:" selectCore interactive || return 0
        case "${selectCore}" in
        1) xrayVersionManageMenu ;;
        2) singBoxVersionManageMenu ;;
        3) coreAllServicesMenu ;;
        4) coreLogsMenu ;;
        5) xrayGeoDataMenu ;;
        0) return 0 ;;
        *) coreInvalidInputErrorCard ;;
        esac
    done
}

menu() {
    local installStatus=0
    cd "$HOME" || return 1
    if ! mkdirTools; then
        errorCard "初始化安装目录失败"
        return 1
    fi
    checkWgetShowProgress
    aliasInstall || return 1
    while true; do
        menuSection "\n┌─ padm 管理面板 · $(getScriptVersion)"
        if [[ "${PADM_INSTALL_STATUS_READY:-}" == "1" ]]; then
            showInstallStatus cached
        else
            showInstallStatus
        fi
        menuSection "├─ 功能菜单 ────────────────────────────────────────"
        menuItem 1 "安装与重装" "选择核心和协议"
        menuItem 2 "订阅与用户" "发布与分享订阅、流量限额、多服务器同步"
        menuItem 3 "协议与入口" "节点链接、入站设置和 CDN 入口"
        menuItem 4 "站点与证书" "静态站点、TLS fallback 和证书"
        menuItem 5 "路由与访问控制" "分流、BT 限制和阻断规则"
        menuItem 6 "核心与服务" "版本、服务、日志和 Geo 数据"
        menuItem 7 "系统与脚本" "更新 padm、系统防护和网络优化"
        menuDangerItem 8 "高级与危险操作" "卸载和实验功能"
        menuReturnItem 0 "退出"
        menuClose
        selectMainMenuType=
        menuReadChoice main_menu "请选择编号（回车退出）：" selectMainMenuType interactive || return 0
        PADM_INSTALL_STATUS_READY=0
        case ${selectMainMenuType} in
        1)
            installStatus=0
            installMenu || installStatus=$?
            [[ -n "${AUTO_INSTALL:-}" ]] && return "${installStatus}"
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
        0) return 0 ;;
        *)
            coreInvalidInputErrorCard
            ;;
        esac
        continue
    done
}
