#!/usr/bin/env bash
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ZIP_URL="https://github.com/neil1123-vip/padm/archive/refs/heads/master.tar.gz"

ensureScriptModules() {
    [[ -f "${SCRIPT_DIR}/shell/core/bootstrap.sh" ]] && return

    local tmpDir archiveDir
    tmpDir=$(mktemp -d /tmp/padm.XXXXXX) || exit 1
    archiveDir="${tmpDir}/padm-master"

    echo " ---> 检测到脚本模块缺失，正在下载完整安装包"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${REPO_ZIP_URL}" | tar -xz -C "${tmpDir}"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "${REPO_ZIP_URL}" | tar -xz -C "${tmpDir}"
    else
        echo " ---> 缺少 curl 或 wget，无法下载完整安装包"
        rm -rf "${tmpDir}"
        exit 1
    fi

    if [[ ! -d "${archiveDir}/shell" ]]; then
        echo " ---> 完整安装包下载失败，请重新执行安装命令"
        rm -rf "${tmpDir}"
        exit 1
    fi

    cp -R "${archiveDir}/shell" "${SCRIPT_DIR}/"
    [[ -d "${archiveDir}/documents" ]] && cp -R "${archiveDir}/documents" "${SCRIPT_DIR}/"
    [[ -f "${archiveDir}/README.md" ]] && cp "${archiveDir}/README.md" "${SCRIPT_DIR}/README.md"
    rm -rf "${tmpDir}"
}

loadScriptModules() {
    ensureScriptModules
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/shell/core/bootstrap.sh"
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/shell/subscription/groups.sh"
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/shell/subscription/subscription.sh"
}

initScriptRuntime() {
    parseInstallArgs "$@"
    initVar "$1"
    checkSystem
    checkCPUVendor

    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    readCustomPort
    readSingBoxConfig
}

handleScriptCommand() {
    if [[ "${cronName}" == "RenewTLS" ]]; then
        renewalTLS
        exit 0
    elif [[ "${cronName}" == "UpdateGeo" ]]; then
        updateGeoSite >>/etc/padm/crontab_updateGeoSite.log
        echoContent green " ---> geo更新日期:$(date "+%F %H:%M:%S")" >>/etc/padm/crontab_updateGeoSite.log
        exit 0
    elif [[ "${cronName}" == "SyncSubscriptionGroups" ]]; then
        runSubscriptionGroupSyncCron
        exit 0
    elif [[ "${cronName}" == "SubscriptionControl" ]]; then
        shift
        handleSubscriptionControl "$@"
        exit 0
    elif [[ "${cronName}" == "InstallSubscription" ]]; then
        mkdirTools
        installSubscribe
        readNginxSubscribe
        if [[ -n "${subscribePort}" ]]; then
            echoContent green " ---> 订阅服务安装完成: ${subscribeType} 端口 ${subscribePort}"
        fi
        exit 0
    fi
}
moreProtocolMenu() {
    echoContent skyBlue "\n┌─ 协议管理 ─────────────────────────────────────────"
    menuItem 1 "Hysteria2 管理" "安装、卸载或管理端口跳跃"
    menuItem 2 "REALITY 管理" "重新生成参数、配置 443 共存分流"
    menuItem 3 "Tuic 管理" "安装或卸载 Tuic 协议"
    menuItem 4 "入口端口管理" "为已安装 Xray 追加或移除入口端口"
    menuItem 5 "返回主菜单" "回到 padm 管理面板"
    echoContent skyBlue "└──────────────────────────────────────────────────"
    autoRead protocol_menu "请选择:" selectProtocolMenuType
    case ${selectProtocolMenuType} in
    1)
        manageHysteria
        ;;
    2)
        manageReality 1
        ;;
    3)
        manageTuic
        ;;
    4)
        addCorePort 1
        ;;
    5)
        menu
        ;;
    *)
        echoContent red ' ---> 选择错误，重新选择'
        moreProtocolMenu
        ;;
    esac
}

moreToolsMenu() {
    echoContent skyBlue "\n┌─ 工具箱 ───────────────────────────────────────────"
    menuItem 1 "传统 TLS fallback 静态站点" "更换或维护 Nginx fallback 页面"
    menuItem 2 "证书管理" "续签或管理 TLS 证书"
    menuItem 3 "CDN 节点管理" "CDN 相关节点与配置"
    menuItem 4 "分流工具" "WireGuard、IPv6、Socks5、DNS、SNI 等"
    menuItem 5 "BT 下载管理" "P2P/BT 下载访问控制"
    menuItem 6 "切换 ALPN" "调整 TLS ALPN 行为"
    menuItem 7 "域名黑名单" "维护禁止访问的目标域名"
    menuItem 8 "返回主菜单" "回到 padm 管理面板"
    echoContent skyBlue "└──────────────────────────────────────────────────"
    autoRead tools_menu "请选择:" selectToolsMenuType
    case ${selectToolsMenuType} in
    1)
        updateNginxBlog 1
        ;;
    2)
        renewalTLS 1
        ;;
    3)
        manageCDN 1
        ;;
    4)
        routingToolsMenu 1
        ;;
    5)
        btTools 1
        ;;
    6)
        switchAlpn 1
        ;;
    7)
        blacklist 1
        ;;
    8)
        menu
        ;;
    *)
        echoContent red ' ---> 选择错误，重新选择'
        moreToolsMenu
        ;;
    esac
}

moreSystemMenu() {
    echoContent skyBlue "\n┌─ 版本与系统 ───────────────────────────────────────"
    menuItem 1 "core 管理" "升级、启停、重启核心"
    menuItem 2 "更新脚本" "更新 padm 脚本"
    menuItem 3 "安装 BBR、DD 脚本" "系统网络优化或重装辅助"
    menuItem 4 "返回主菜单" "回到 padm 管理面板"
    echoContent skyBlue "└──────────────────────────────────────────────────"
    autoRead system_menu "请选择:" selectSystemMenuType
    case ${selectSystemMenuType} in
    1)
        coreVersionManageMenu 1
        ;;
    2)
        updatePadm 1
        ;;
    3)
        bbrInstall
        ;;
    4)
        menu
        ;;
    *)
        echoContent red ' ---> 选择错误，重新选择'
        moreSystemMenu
        ;;
    esac
}

advancedDangerMenu() {
    echoContent skyBlue "\n┌─ 高级/危险操作 ────────────────────────────────────"
    menuDangerItem 1 "卸载脚本" "移除脚本和相关配置，执行前请确认备份"
    menuItem 2 "返回主菜单" "回到 padm 管理面板"
    echoContent skyBlue "└──────────────────────────────────────────────────"
    autoRead danger_menu "请选择:" selectDangerMenuType
    case ${selectDangerMenuType} in
    1)
        unInstall 1
        ;;
    2)
        menu
        ;;
    *)
        echoContent red ' ---> 选择错误，重新选择'
        advancedDangerMenu
        ;;
    esac
}

# 安装菜单
installMenu() {
    echoContent skyBlue "\n┌─ 安装管理 ─────────────────────────────────────────"
    if [[ -n "${coreInstallType}" ]]; then
        menuItem 1 "重新安装" "重建核心与协议配置，会覆盖当前安装配置"
    else
        menuItem 1 "完整安装" "传统 TLS 组合，适合旧客户端或已有 TLS 架构"
    fi
    menuItem 2 "自定义安装" "推荐 Xray-core -> 7.Reality Vision；CDN 选 12.XHTTP"
    menuItem 3 "无域名 Reality" "无需自有域名，需理解 entry/target/SNI"
    menuItem 4 "返回主菜单" "回到 padm 管理面板"
    echoContent skyBlue "└──────────────────────────────────────────────────"
    autoRead install_type "请选择:" selectInstallType
    case ${selectInstallType} in
    1 | 2 | 3)
        selectCoreInstall
        ;;
    4)
        menu
        ;;
    *)
        echoContent red ' ---> 选择错误，重新选择'
        installMenu
        ;;
    esac
}

# 主菜单
menu() {
    cd "$HOME" || exit
    echoContent skyBlue "\n┌─ padm 管理面板 ───────────────────────────────────"
    menuLine "Xray-core / sing-box 运维脚本"
    menuLine "版本：$(getScriptVersion)"
    menuLine "能力：节点安装 / 订阅管理 / 协议维护 / 系统工具"
    echoContent skyBlue "├─ 当前状态 ───────────────────────────────────────"
    showInstallStatus
    checkWgetShowProgress
    echoContent skyBlue "├─ 推荐操作 ───────────────────────────────────────"
    menuItem 1 "安装/重装节点" "新手默认自定义安装 Reality Vision；CDN 选 Reality XHTTP"
    menuItem 2 "查看/管理订阅" "查看订阅链接、管理用户订阅、服务器同步和流量"
    echoContent skyBlue "├─ 更多管理 ───────────────────────────────────────"
    menuItem 3 "协议管理" "REALITY、Hysteria2、Tuic、入口端口"
    menuItem 4 "工具箱" "站点、证书、CDN、分流、BT、ALPN、黑名单"
    menuItem 5 "版本与系统" "core 管理、更新脚本、BBR/DD"
    menuDangerItem 6 "高级/危险操作" "卸载等高风险操作"
    menuLine "不确定选哪个？选 1。命令行教程：bash install.sh --help"
    echoContent skyBlue "└──────────────────────────────────────────────────"
    mkdirTools
    aliasInstall
    autoRead main_menu "请选择:" selectMainMenuType
    case ${selectMainMenuType} in
    1)
        installMenu
        ;;
    2)
        manageSubscription 1
        ;;
    3)
        moreProtocolMenu
        ;;
    4)
        moreToolsMenu
        ;;
    5)
        moreSystemMenu
        ;;
    6)
        advancedDangerMenu
        ;;
    *)
        echoContent red ' ---> 选择错误，重新选择'
        menu
        ;;
    esac
}
runMainMenu() {
    checkRoot
    handleScriptCommand "$@"
    menu
}

loadScriptModules
initScriptRuntime "$@"
runMainMenu "$@"
