#!/usr/bin/env bash

installMenu() {
    echoContent title "\n┌─ 安装与重装 ───────────────────────────────────────"
    if [[ -n "${coreInstallType}" ]]; then
        menuLine "检测到已有安装；以下入口会重建核心与协议配置，请先确认已备份"
    else
        menuLine "首次安装或不知道怎么选时，建议直接选 1；安装后去 订阅与用户 查看链接"
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
    autoRead install_type "请选择:" selectInstallType
    case ${selectInstallType} in
    1)
        selectInstallType=2
        selectCoreType=1
        customXrayInstall 1 domain
        ;;
    2)
        selectInstallType=2
        selectCoreType=1
        customXrayInstall 2
        ;;
    3)
        selectInstallType=3
        selectCoreInstall
        ;;
    4)
        selectInstallType=2
        selectCoreType=2
        customSingBoxInstall 5
        ;;
    5)
        selectInstallType=2
        selectCoreInstall
        ;;
    6)
        selectInstallType=1
        selectCoreInstall
        ;;
    7)
        menu
        ;;
    *)
        coreSelectionRetryAction installMenu
        ;;
    esac
}

protocolEntryMenu() {
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
    autoRead protocol_entry_menu "请选择:" selectProtocolMenuType
    case ${selectProtocolMenuType} in
    1)
        manageReality 1
        ;;
    2)
        manageXHTTP
        ;;
    3)
        manageHysteria
        ;;
    4)
        manageTuic
        ;;
    5)
        addCorePort 1
        ;;
    6)
        manageCDN 1
        ;;
    7)
        menu
        ;;
    *)
        coreSelectionRetryAction protocolEntryMenu
        ;;
    esac
}

siteCertificateMenu() {
    echoContent title "\n┌─ 站点与证书 ───────────────────────────────────────"
    menuLine "这里只维护传统 TLS fallback 站点、302、ALPN 和本机 TLS 证书"
    menuLine "Reality 不使用本机 TLS 证书；这里的证书只服务传统 TLS、站点或订阅"
    menuLine "Reality target/SNI 伪装目标仍由 Reality 目标站管理，二者不要混淆"
    menuItem 1 "传统 TLS fallback 维护" "静态站点、302 重定向、ALPN 诊断/修复"
    menuItem 2 "本机 TLS 证书管理" "续签或查看 /etc/padm/tls 证书"
    menuReturnItem 3 "返回主菜单" "回到 padm 管理面板"
    menuClose
    autoRead site_certificate_menu "请选择:" selectSiteCertificateMenuType
    case ${selectSiteCertificateMenuType} in
    1)
        manageTraditionalTlsFallback 1
        ;;
    2)
        manageTLSCertificates
        ;;
    3)
        menu
        ;;
    *)
        coreSelectionRetryAction siteCertificateMenu
        ;;
    esac
}

routingAccessMenu() {
    echoContent title "\n┌─ 路由与访问控制 ───────────────────────────────────"
    menuLine "这里管理服务端出站、分流、BT 阻断和访问限制，不是客户端配置教程"
    menuLine "阻断/区域策略可能影响系统更新、证书申请和应用连接，执行前先看说明"
    menuItem 1 "分流工具" "WARP、IPv6、Socks5、DNS/hosts 覆盖"
    menuItem 2 "BT 下载管理" "P2P/BT 下载访问控制"
    menuItem 3 "访问控制" "域名/IP 阻断、直连例外、区域阻断"
    menuReturnItem 4 "返回主菜单" "回到 padm 管理面板"
    menuClose
    autoRead routing_access_menu "请选择:" selectRoutingAccessMenuType
    case ${selectRoutingAccessMenuType} in
    1)
        routingToolsMenu 1
        ;;
    2)
        btTools 1
        ;;
    3)
        accessControlMenu 1
        ;;
    4)
        menu
        ;;
    *)
        coreSelectionRetryAction routingAccessMenu
        ;;
    esac
}

systemScriptMenu() {
    echoContent title "\n┌─ 系统与脚本 ───────────────────────────────────────"
    menuLine "这里维护 padm 脚本自身和宿主机网络辅助项"
    menuLine "核心版本、服务、日志和配置校验请去 核心与服务"
    menuItem 1 "更新 padm 脚本" "更新脚本文件"
    menuItem 2 "查看脚本安装状态" "显示入口校验、版本、ref 和 manifest"
    menuItem 3 "Fail2ban 防护" "SSH 和 /s/control/ 的最小防护入口"
    menuItem 4 "网络优化" "查看或启用官方 BBR + fq"
    menuReturnItem 5 "返回主菜单" "回到 padm 管理面板"
    menuClose
    autoRead system_script_menu "请选择:" selectSystemMenuType
    case ${selectSystemMenuType} in
    1)
        updatePadm 1
        ;;
    2)
        showPadmScriptInstallStatus
        ;;
    3)
        manageFail2ban
        ;;
    4)
        bbrInstall
        ;;
    5)
        menu
        ;;
    *)
        coreSelectionRetryAction systemScriptMenu
        ;;
    esac
}

advancedDangerMenu() {
    echoContent title "\n┌─ 高级/危险操作 ────────────────────────────────────"
    menuLine "这里只放不可逆、实验性或容易影响现有连接的操作"
    menuDangerItem 1 "卸载脚本" "移除脚本和相关配置，执行前请确认备份"
    menuDangerItem 2 "VLESS Encryption 实验" "Xray-only，高级兼容性实验开关"
    menuReturnItem 3 "返回主菜单" "回到 padm 管理面板"
    menuClose
    autoRead danger_menu "请选择:" selectDangerMenuType
    case ${selectDangerMenuType} in
    1)
        unInstall 1
        ;;
    2)
        manageVlessEncryptionExperiment
        ;;
    3)
        menu
        ;;
    *)
        coreSelectionRetryAction advancedDangerMenu
        ;;
    esac
}

menu() {
    cd "$HOME" || exit
    echoContent title "\n┌─ padm 管理面板 ───────────────────────────────────"
    menuLine "Xray-core / sing-box 节点安装与运维脚本"
    menuLine "版本：$(getScriptVersion)"
    menuLine "原则：安装、订阅、入口、站点、路由、核心、系统各归一处"
    menuSection "├─ 当前状态 ───────────────────────────────────────"
    showInstallStatus
    checkWgetShowProgress
    menuSection "├─ 任务入口 ───────────────────────────────────────"
    menuItem 1 "安装与重装" "含新手选择指引；推荐直连/CDN/无域名 Reality、NaiveProxy、自定义和传统 TLS"
    menuItem 2 "订阅与用户" "快速开始、我的订阅、分享订阅、用量限额、同步备份、多服务器和诊断"
    menuItem 3 "协议与入口" "REALITY、XHTTP、Hysteria2、Tuic、入口端口和 CDN 入口"
    menuItem 4 "站点与证书" "传统 TLS fallback 站点、302、ALPN 和 TLS 证书"
    menuItem 5 "路由与访问控制" "分流、BT、域名/IP 阻断、直连例外和区域阻断"
    menuItem 6 "核心与服务" "Xray/sing-box 版本管理、配置校验、服务控制和日志"
    menuItem 7 "系统与脚本" "更新 padm、网络优化和宿主机辅助项"
    menuDangerItem 8 "高级/危险操作" "卸载和实验性高风险开关"
    menuLine "新人建议：1 安装与重装里先看怎么选；安装后 2 查看订阅"
    menuClose
    if ! mkdirTools; then
        errorCard "初始化安装目录失败"
        return 1
    fi
    aliasInstall
    autoRead main_menu "请选择:" selectMainMenuType
    case ${selectMainMenuType} in
    1)
        installMenu || return $?
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
        ;;
    7)
        systemScriptMenu
        ;;
    8)
        advancedDangerMenu
        ;;
    *)
        coreSelectionRetryAction menu
        ;;
    esac
}
