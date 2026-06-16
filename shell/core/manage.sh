#!/usr/bin/env bash

vlessEncryptionStateFile() {
    echo "${PADM_VLESS_ENCRYPTION_STATE_FILE:-/etc/padm/xray/vless_encryption.json}"
}

vlessEncryptionXrayBinary() {
    echo "${PADM_XRAY_BINARY:-/etc/padm/xray/xray}"
}

vlessEncryptionXrayConfDir() {
    echo "${PADM_XRAY_CONF_DIR:-/etc/padm/xray/conf}"
}

vlessEncryptionVisionConfigFile() {
    echo "${PADM_VLESS_REALITY_CONFIG_FILE:-$(vlessEncryptionXrayConfDir)/07_VLESS_vision_reality_inbounds.json}"
}

vlessEncryptionXHTTPConfigFile() {
    echo "${PADM_VLESS_XHTTP_CONFIG_FILE:-$(vlessEncryptionXrayConfDir)/12_VLESS_XHTTP_inbounds.json}"
}

vlessEncryptionConfigFile() {
    local xhttpConfig
    xhttpConfig=$(vlessEncryptionXHTTPConfigFile)
    if [[ -f "${xhttpConfig}" ]]; then
        echo "${xhttpConfig}"
    else
        vlessEncryptionVisionConfigFile
    fi
}

validateVlessEncryptionConfig() {
    local xrayBinary
    xrayBinary=$(vlessEncryptionXrayBinary)
    "${xrayBinary}" -test -confdir "$(vlessEncryptionXrayConfDir)" >"$(vlessEncryptionXrayTestLog)" 2>&1
}

vlessEncryptionXrayTestLog() {
    local tmpBase="${TMPDIR:-/tmp}"
    printf '%s\n' "${tmpBase%/}/padm-xray-test.log"
}

xrayVersionAtLeast() {
    local current=$1
    local required=$2
    current=${current#v}
    required=${required#v}
    [[ "$(printf '%s\n%s\n' "${required}" "${current}" | sort -V | head -n 1)" == "${required}" ]]
}

extractVlessEncField() {
    local field=$1
    sed -n 's/.*"'"${field}"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}

vlessEncryptionStateSummary() {
    local stateFile
    local xrayVersion="未安装"
    local encryptionPrefix="none"
    stateFile=$(vlessEncryptionStateFile)
    if [[ -x /etc/padm/xray/xray ]]; then
        xrayVersion=$(/etc/padm/xray/xray --version | awk 'NR==1 {print $2}')
    fi
    if [[ -f "${stateFile}" ]]; then
        encryptionPrefix=$(jq -r '.encryption // "none" | split(".")[:3] | join(".")' "${stateFile}" 2>/dev/null)
        [[ -z "${encryptionPrefix}" || "${encryptionPrefix}" == "null" ]] && encryptionPrefix=none
        menuLine "当前状态：已启用；Xray=${xrayVersion}；encryption=${encryptionPrefix}..."
    else
        menuLine "当前状态：未启用；Xray=${xrayVersion}；encryption=none"
    fi
}

refreshVlessEncryptionSubscriptions() {
    readNginxSubscribe
    if [[ -n "${subscribePort}" || -f "${nginxConfigPath}subscribe.conf" ]]; then
        if ! subscribe renew >/dev/null; then
            errorCard "刷新 VLESS Encryption 公网订阅失败"
            return 1
        fi
        successCard "已刷新 default 公网订阅；Clash/Mihomo/sing-box 订阅未写入实验 encryption 字段"
    else
        refreshLocalSubscriptions "VLESS Encryption" "已刷新本地 default 订阅；Clash/Mihomo/sing-box 订阅未写入实验 encryption 字段" || return 1
    fi
}

restoreLocalSubscribeOutputs() {
    local localBase=$1
    local backupDir=$2
    local reason=$3
    local previousSubscribeSalt=

    if [[ $# -ge 4 ]]; then
        previousSubscribeSalt=$4
    fi

    if ! subscriptionSyncRestoreBackupPath "${localBase}" "${backupDir}" local; then
        padmForgetCleanupPath "${backupDir}"
        errorCard "${reason}，且旧本地订阅恢复失败，请手动检查备份目录：${backupDir}"
        return 1
    fi
    padmRemoveCleanupPath "${backupDir}"
    if [[ $# -ge 4 ]]; then
        subscribeSalt=${previousSubscribeSalt}
    fi
    errorCard "${reason}，已恢复旧本地订阅"
    return 1
}

refreshLocalSubscriptions() {
    local featureName=$1
    local successMessage=$2
    local localBase backupDir
    local tmpBase="${TMPDIR:-/tmp}"

    localBase=$(subscribeLocalBaseDir)
    padmCreateTempPath backupDir -d "${tmpBase%/}/padm-refresh-local-subscriptions.XXXXXX" || {
        errorCard "刷新 ${featureName} 本地订阅失败：创建备份目录失败"
        return 1
    }
    if ! subscriptionSyncBackupPath "${localBase}" "${backupDir}" local; then
        padmRemoveCleanupPath "${backupDir}"
        errorCard "刷新 ${featureName} 本地订阅失败：备份旧本地订阅失败"
        return 1
    fi

    if ! cleanDirectoryContent "${localBase}/default" ||
        ! cleanDirectoryContent "${localBase}/clashMeta" ||
        ! cleanDirectoryContent "${localBase}/sing-box"; then
        restoreLocalSubscribeOutputs "${localBase}" "${backupDir}" "刷新 ${featureName} 本地订阅失败：清理本地订阅目录失败"
        return 1
    fi
    if ! showAccounts >/dev/null; then
        restoreLocalSubscribeOutputs "${localBase}" "${backupDir}" "刷新 ${featureName} 本地订阅失败：重建本地订阅失败"
        return 1
    fi
    padmRemoveCleanupPath "${backupDir}"
    successCard "${successMessage}"
}

restoreVlessEncryptionBackup() {
    local backupFile=$1
    local configFile=$2
    local stateBackupFile=$3
    local stateFile=$4
    local hadStateBackup=$5
    local stateMode=$6
    local reason=$7
    local restoreFailed=false
    if ! mv "${backupFile}" "${configFile}"; then
        errorCard "${reason}，且 VLESS Encryption 配置恢复失败，请手动检查 ${configFile} 和 ${backupFile}"
        return 1
    fi
    if [[ "${hadStateBackup}" == "true" ]]; then
        if ! mv "${stateBackupFile}" "${stateFile}"; then
            restoreFailed=true
        fi
    elif [[ "${stateMode}" == "remove" ]]; then
        if ! rm -f "${stateFile}" >/dev/null 2>&1; then
            restoreFailed=true
        fi
    fi
    if [[ "${restoreFailed}" == "true" ]]; then
        errorCard "${reason}，且 VLESS Encryption 状态恢复失败，请手动检查 ${stateFile} 和 ${stateBackupFile}"
        return 1
    fi
}

setVlessRealityEncryption() {
    local mode=$1
    local configFile
    local stateFile
    local backupFile
    local stateBackupFile
    local stateTmpFile
    local xrayBinary
    local xrayVersion
    local vlessEncOutput
    local vlessEncOut
    local vlessEncErr
    local tmpBase
    local encryption
    local decryption
    local hadStateBackup=false
    configFile=$(vlessEncryptionConfigFile)
    stateFile=$(vlessEncryptionStateFile)
    xrayBinary=$(vlessEncryptionXrayBinary)

    if [[ "${coreInstallType}" != "1" ]]; then
        errorCard "此实验功能仅支持 Xray-core"
        return 1
    fi
    if [[ ! -x "${xrayBinary}" || ! -f "${configFile}" ]]; then
        errorCard "未检测到 Xray Reality Vision 或 Reality XHTTP 配置，请先安装 Xray Reality Vision；CDN 场景优先安装 Reality XHTTP"
        return 1
    fi

    backupFile="${configFile}.vlessenc.bak"
    stateBackupFile="${stateFile}.bak"
    stateTmpFile="${stateFile}.tmp"
    if ! cp "${configFile}" "${backupFile}"; then
        errorCard "创建 VLESS Encryption 配置备份失败，请手动检查 ${configFile}"
        return 1
    fi
    if [[ -f "${stateFile}" ]]; then
        if ! cp "${stateFile}" "${stateBackupFile}"; then
            rm -f "${backupFile}"
            errorCard "创建 VLESS Encryption 状态备份失败，请手动检查 ${stateFile}"
            return 1
        fi
        hadStateBackup=true
    else
        if ! rm -f "${stateBackupFile}" >/dev/null 2>&1; then
            rm -f "${backupFile}"
            errorCard "清理 VLESS Encryption 旧状态备份失败，请手动检查 ${stateBackupFile}"
            return 1
        fi
    fi

    if [[ "${mode}" == "enable" ]]; then
        xrayVersion=$("${xrayBinary}" --version | awk 'NR==1 {print $2}')
        if ! xrayVersionAtLeast "${xrayVersion}" "25.9.5"; then
            errorCard "当前 Xray-core ${xrayVersion} 不支持 vlessenc，请先升级到 v25.9.5 或更高版本"
            rm -f "${backupFile}" "${stateBackupFile}"
            return 1
        fi
        tmpBase="${TMPDIR:-/tmp}"
        padmCreateTempPath vlessEncOut "${tmpBase%/}/padm-vlessenc.out.XXXXXX" || {
            rm -f "${backupFile}" "${stateBackupFile}"
            return 1
        }
        padmCreateTempPath vlessEncErr "${tmpBase%/}/padm-vlessenc.err.XXXXXX" || {
            padmRemoveCleanupPath "${vlessEncOut}"
            rm -f "${backupFile}" "${stateBackupFile}"
            return 1
        }
        if ! "${xrayBinary}" vlessenc >"${vlessEncOut}" 2>"${vlessEncErr}"; then
            errorCard "xray vlessenc 执行失败，请先确认当前 Xray-core 支持该命令"
            padmRemoveCleanupPath "${vlessEncOut}"
            padmRemoveCleanupPath "${vlessEncErr}"
            rm -f "${backupFile}" "${stateBackupFile}"
            return 1
        fi
        vlessEncOutput=$(cat "${vlessEncOut}")
        encryption=$(printf '%s\n' "${vlessEncOutput}" | extractVlessEncField encryption)
        decryption=$(printf '%s\n' "${vlessEncOutput}" | extractVlessEncField decryption)
        padmRemoveCleanupPath "${vlessEncOut}"
        padmRemoveCleanupPath "${vlessEncErr}"
        if [[ -z "${encryption}" || -z "${decryption}" ]]; then
            errorCard "无法解析 xray vlessenc 输出，已取消启用"
            rm -f "${backupFile}" "${stateBackupFile}"
            return 1
        fi
        if ! jq --arg decryption "${decryption}" '
            if has("inbounds") and (.inbounds | length) > 1 then
                del(.inbounds[1].settings.fallbacks) | .inbounds[1].settings.decryption = $decryption
            else
                del(.inbounds[0].settings.fallbacks) | .inbounds[0].settings.decryption = $decryption | .inbounds[0].settings.clients |= map(.flow = "xtls-rprx-vision")
            end
        ' "${configFile}" >"${configFile}.tmp"; then
            errorCard "写入 Xray 配置失败，已取消启用"
            restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" keep "写入 Xray 配置失败" || return 1
            rm -f "${configFile}.tmp" "${stateBackupFile}"
            return 1
        fi
        if ! mkdir -p "$(dirname "${stateFile}")"; then
            errorCard "创建 VLESS Encryption 状态目录失败，已取消启用"
            rm -f "${configFile}.tmp" "${stateTmpFile}"
            restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" keep "创建 VLESS Encryption 状态目录失败" || return 1
            return 1
        fi
        if ! jq -n --arg encryption "${encryption}" --arg decryption "${decryption}" '{enabled:true,encryption:$encryption,decryption:$decryption}' >"${stateTmpFile}"; then
            errorCard "写入 VLESS Encryption 状态失败，已取消启用"
            rm -f "${configFile}.tmp" "${stateTmpFile}"
            restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" keep "写入 VLESS Encryption 状态失败" || return 1
            return 1
        fi
    else
        if ! jq '
            if has("inbounds") and (.inbounds | length) > 1 then
                .inbounds[1].settings.decryption = "none" | del(.inbounds[1].settings.fallbacks)
            else
                .inbounds[0].settings.decryption = "none" | del(.inbounds[0].settings.fallbacks)
            end
        ' "${configFile}" >"${configFile}.tmp"; then
            errorCard "写入 Xray 配置失败，已取消关闭"
            rm -f "${configFile}.tmp"
            restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" keep "写入 Xray 配置失败" || return 1
            return 1
        fi
    fi

    if ! mv "${configFile}.tmp" "${configFile}"; then
        errorCard "提交 VLESS Encryption 配置失败，请手动检查 ${configFile}、${configFile}.tmp 和 ${backupFile}"
        rm -f "${stateTmpFile}"
        return 1
    fi
    if [[ "${mode}" == "enable" ]]; then
        if ! mv "${stateTmpFile}" "${stateFile}"; then
            if ! restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" remove "提交 VLESS Encryption 状态失败"; then
                rm -f "${stateTmpFile}"
                return 1
            fi
            rm -f "${stateTmpFile}"
            errorCard "提交 VLESS Encryption 状态失败，已恢复旧配置"
            return 1
        fi
        chmod 600 "${stateFile}" 2>/dev/null || true
    else
        if ! rm -f "${stateFile}" >/dev/null 2>&1; then
            if ! restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" keep "删除 VLESS Encryption 状态失败"; then
                return 1
            fi
            errorCard "删除 VLESS Encryption 状态失败，已恢复旧配置"
            return 1
        fi
    fi

    if ! validateVlessEncryptionConfig; then
        if ! restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" remove "Xray 配置校验失败"; then
            rm -f "${stateTmpFile}"
            return 1
        fi
        rm -f "${stateTmpFile}"
        echoContent title "\n┌─ Xray 配置校验失败 ─────────────────────────────────"
        menuLine "已回滚本次 VLESS Encryption 修改"
        menuLine "排查日志：$(vlessEncryptionXrayTestLog)"
        menuClose
        return 1
    fi
    if ! reloadCore; then
        if ! restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" remove "核心重载失败"; then
            rm -f "${stateTmpFile}"
            return 1
        fi
        rm -f "${stateTmpFile}"
        if reloadCore; then
            errorCard "核心重载失败，已回滚 VLESS Encryption 修改"
        else
            errorCard "核心重载失败，已回滚 VLESS Encryption 修改；恢复旧配置后核心重载仍失败，请检查核心服务日志"
        fi
        return 1
    fi
    if ! refreshVlessEncryptionSubscriptions; then
        if ! restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" remove "刷新 VLESS Encryption 订阅失败"; then
            rm -f "${stateTmpFile}"
            return 1
        fi
        if ! reloadCore; then
            rm -f "${stateTmpFile}"
            errorCard "刷新 VLESS Encryption 订阅失败，已恢复旧配置；恢复旧配置后核心重载失败，请检查核心服务日志"
            return 1
        fi
        rm -f "${backupFile}" "${stateBackupFile}" "${stateTmpFile}"
        errorCard "刷新 VLESS Encryption 订阅失败，已恢复旧配置"
        return 1
    fi
    rm -f "${backupFile}" "${stateBackupFile}" "${stateTmpFile}"
    return 0
}

manageVlessEncryptionExperiment() {
    readInstallType
    readInstallProtocolType
    echoContent title "\n┌─ VLESS Encryption 实验功能 ─────────────────────────"
    menuLine "最佳性能组合：Reality Vision 使用 VLESS Encryption + XTLS Vision"
    menuLine "CDN 场景：Reality XHTTP 使用 VLESS Encryption + XTLS Vision + XHTTP XMUX"
    menuLine "启用后可能只有部分客户端可用；Clash/Mihomo/sing-box 订阅不保证兼容"
    menuLine "默认推荐仍是 Reality Vision，不建议新手启用"
    vlessEncryptionStateSummary
    menuDangerItem 1 "启用实验开关" "优先应用到 Reality XHTTP，否则应用到 Reality Vision"
    menuItem 2 "关闭实验开关" "恢复 decryption=none 并删除实验订阅参数"
    menuReturnItem 3 "返回主菜单" "回到 padm 管理面板"
    echoContent title "└──────────────────────────────────────────────────"
    autoRead vless_encryption_menu "请选择:" selectVlessEncryptionMenu
    case ${selectVlessEncryptionMenu} in
    1)
        warnCard \
            "这是实验功能，可能只有部分客户端可用" \
            "启用后 default VLESS 链接会携带新的 encryption 参数" \
            "Clash/Mihomo/sing-box 订阅不保证兼容"
        autoConfirm vless_encryption_confirm "确认承担兼容性风险并启用 VLESS Encryption？" n confirmVlessEncryption
        if [[ "${confirmVlessEncryption}" == "y" ]]; then
            setVlessRealityEncryption enable && successCard "VLESS Encryption 实验开关已启用"
        else
            statusCard "已取消" "操作未执行"
        fi
        ;;
    2)
        setVlessRealityEncryption disable && successCard "VLESS Encryption 实验开关已关闭"
        ;;
    3)
        menu
        ;;
    *)
        errorCard "选择错误，重新选择"
        manageVlessEncryptionExperiment
        ;;
    esac
}

panelCertDomainList() {
    local certGlob=$1
    local domainDepth=$2
    local certFile=
    local domain=
    local count=0

    for certFile in ${certGlob}; do
        [[ -f "${certFile}" ]] || continue
        if [[ "${domainDepth}" == "2" ]]; then
            domain=$(basename "$(dirname "$(dirname "${certFile}")")")
        else
            domain=$(basename "$(dirname "${certFile}")")
        fi
        count=$((count + 1))
        printf '%s:%s\n' "${count}" "${domain}"
    done
}

selectPanelCertDomain() {
    local title=$1
    local certGlob=$2
    local domainDepth=$3
    local certList=
    local selectBTDomain=

    certList=$(panelCertDomainList "${certGlob}" "${domainDepth}")
    [[ -n "${certList}" ]] || return 1
    if [[ -z "${currentHost}" ]]; then
        echoContent title "\n读取${title}配置\n"
        echo "${certList}"
        autoRead bt_domain_select "请输入编号选择:" selectBTDomain
    else
        selectBTDomain=$(awk -F ':' -v host="${currentHost}" '$2 == host {print $1; exit}' <<<"${certList}")
    fi

    btDomain=$(awk -F ':' -v selected="${selectBTDomain}" '$1 == selected {print $2; exit}' <<<"${certList}")
    [[ -n "${btDomain}" ]]
}

# 检查是否安装宝塔
checkBTPanel() {
    if [[ -n $(pgrep -f "BT-Panel") ]]; then
        if [[ -d '/www/server/panel/vhost/cert/' ]] && selectPanelCertDomain "宝塔" '/www/server/panel/vhost/cert/*/fullchain.pem' 1; then
            domain=${btDomain}
            if [[ ! -f "/etc/padm/tls/${btDomain}.crt" && ! -f "/etc/padm/tls/${btDomain}.key" ]]; then
                ln -s "/www/server/panel/vhost/cert/${btDomain}/fullchain.pem" "/etc/padm/tls/${btDomain}.crt"
                ln -s "/www/server/panel/vhost/cert/${btDomain}/privkey.pem" "/etc/padm/tls/${btDomain}.key"
            fi

            nginxStaticPath="/www/wwwroot/${btDomain}/html/"
            mkdir -p "/www/wwwroot/${btDomain}/html/"
            if [[ -f "/www/wwwroot/${btDomain}/.user.ini" ]]; then
                chattr -i "/www/wwwroot/${btDomain}/.user.ini"
            fi
            nginxConfigPath="/www/server/panel/vhost/nginx/"
        elif [[ -d '/www/server/panel/vhost/cert/' ]]; then
            errorCard "选择错误，请重新选择"
            checkBTPanel
        fi
    fi
}

check1Panel() {
    if [[ -n $(pgrep -f "1panel") ]]; then
        if [[ -d '/opt/1panel/apps/openresty/openresty/www/sites/' ]] && selectPanelCertDomain "1Panel" '/opt/1panel/apps/openresty/openresty/www/sites/*/ssl/fullchain.pem' 2; then
            domain=${btDomain}
            if [[ ! -f "/etc/padm/tls/${btDomain}.crt" && ! -f "/etc/padm/tls/${btDomain}.key" ]]; then
                ln -s "/opt/1panel/apps/openresty/openresty/www/sites/${btDomain}/ssl/fullchain.pem" "/etc/padm/tls/${btDomain}.crt"
                ln -s "/opt/1panel/apps/openresty/openresty/www/sites/${btDomain}/ssl/privkey.pem" "/etc/padm/tls/${btDomain}.key"
            fi

            nginxStaticPath="/opt/1panel/apps/openresty/openresty/www/sites/${btDomain}/index/"
        elif [[ -d '/opt/1panel/apps/openresty/openresty/www/sites/' ]]; then
            errorCard "选择错误，请重新选择"
            check1Panel
        fi
    fi
}



# 卸载 sing-box
unInstallSingBox() {
    local type=${1:-}
    if [[ -n "${singBoxConfigPath}" ]]; then
        if grep -q 'tuic' </etc/padm/sing-box/conf/config.json && [[ "${type}" == "tuic" ]]; then
            rm "${singBoxConfigPath}09_tuic_inbounds.json"
            successCard "删除sing-box tuic配置成功"
        fi

        if grep -q 'hysteria2' </etc/padm/sing-box/conf/config.json && [[ "${type}" == "hysteria2" ]]; then
            rm "${singBoxConfigPath}06_hysteria2_inbounds.json"
            successCard "删除sing-box hysteria2配置成功"
        fi
        rm "${singBoxConfigPath}config.json"
    fi

    readInstallType

    if [[ -n "${singBoxConfigPath}" ]]; then
        statusCard "保留配置" "检测到有其他配置，保留 sing-box 核心"
        serviceQueueRestart sing-box
        serviceQueueApply || { errorCard "sing-box 服务重启失败"; return 1; }
    else
        if ! runCoreServiceActionAllowFailure handleSingBox stop; then
            errorCard "sing-box 服务停止失败，已取消卸载"
            return 1
        fi
        rm -f /etc/systemd/system/sing-box.service || { errorCard "sing-box systemd 服务文件删除失败"; return 1; }
        rm -rf /etc/padm/sing-box/* || { errorCard "sing-box 文件清理失败"; return 1; }
        successCard "sing-box 卸载完成"
    fi
}


# 清理核心安装残留
cleanUp() {
    if [[ "$1" == "xrayDel" ]]; then
        runCoreServiceActionAllowFailure handleXray stop || { errorCard "Xray 服务停止失败，已取消清理旧核心"; return 1; }
        rm -rf /etc/padm/xray/* || { errorCard "Xray 文件清理失败"; return 1; }
    elif [[ "$1" == "singBoxDel" ]]; then
        runCoreServiceActionAllowFailure handleSingBox stop || { errorCard "sing-box 服务停止失败，已取消清理旧核心"; return 1; }
        rm -rf /etc/padm/sing-box/conf/config.json >/dev/null 2>&1 || { errorCard "sing-box 主配置清理失败"; return 1; }
        cleanDirectoryContent /etc/padm/sing-box/conf/config || { errorCard "sing-box 分片配置清理失败"; return 1; }
    fi
}

# 传统 TLS fallback 维护
manageTraditionalTlsFallback() {
    if [[ "${coreInstallType}" == "2" ]]; then
        errorCard "此功能仅支持 Xray-core 内核"
        exit 0
    fi

    progressCard "$1" "传统 TLS fallback 维护"

    if ! currentProtocolHas 0 || [[ -z "${coreInstallType}" ]]; then
        errorCard "请先安装 Xray-core 的 VLESS TCP TLS Vision"
        exit 0
    fi

    echoContent title "\n┌─ 传统 TLS fallback 维护 ───────────────────────────"
    menuLine "仅用于传统 TLS fallback / WS / gRPC / Trojan 兼容维护"
    menuLine "Reality Vision / Reality XHTTP 不依赖此处 ALPN 或静态站点"
    menuItem 1 "更换静态站点" "更换本机 Nginx fallback 页面"
    menuItem 2 "302 重定向管理" "添加或移除 fallback 根路由重定向"
    menuItem 3 "ALPN 诊断" "检查 h2 fallback 与 TLS ALPN 是否匹配"
    menuRecommendedItem 4 "修复为推荐 ALPN" "存在 h2 fallback 时设置 h2,http/1.1"
    menuItem 5 "手动设置 ALPN" "兼容排障时手动调整 ALPN 顺序"
    menuReturnItem 6 "返回站点与证书" "回到上级菜单"
    menuClose
    autoRead traditional_tls_menu "请选择:" selectTraditionalTlsMenu

    case "${selectTraditionalTlsMenu}" in
    1)
        manageTraditionalTlsStaticSite
        ;;
    2)
        manageTraditionalTlsRedirect
        ;;
    3)
        diagnoseTraditionalTlsAlpn
        ;;
    4)
        repairTraditionalTlsAlpn
        ;;
    5)
        setTraditionalTlsAlpnManual
        ;;
    6)
        siteCertificateMenu
        ;;
    *)
        errorCard "选择错误，请重新选择"
        manageTraditionalTlsFallback "$@"
        ;;
    esac
}

traditionalTlsFallbackConfigFile() {
    echo "${configPath:-/etc/padm/xray/conf/}02_VLESS_TCP_inbounds.json"
}

traditionalTlsHasH2Fallback() {
    local configFile
    configFile=$(traditionalTlsFallbackConfigFile)
    [[ -f "${configFile}" ]] && jq -e '.inbounds[0].settings.fallbacks[]? | select(.alpn == "h2")' "${configFile}" >/dev/null 2>&1
}

traditionalTlsAlpnTestLog() {
    local tmpBase="${TMPDIR:-/tmp}"
    printf '%s\n' "${tmpBase%/}/padm-alpn-xray-test.log"
}

restoreTraditionalTlsAlpnBackup() {
    local backupFile=$1
    local configFile=$2
    local reason=$3
    if mv "${backupFile}" "${configFile}"; then
        return 0
    fi
    errorCard "${reason}，且旧配置恢复失败，请手动检查 ${configFile} 和 ${backupFile}"
    return 1
}

traditionalTlsCurrentAlpn() {
    local configFile
    configFile=$(traditionalTlsFallbackConfigFile)
    if [[ -f "${configFile}" ]]; then
        jq -r '.inbounds[0].streamSettings.tlsSettings.alpn // [] | join(",")' "${configFile}"
    fi
}

manageTraditionalTlsStaticSite() {
    echoContent title "\n┌─ 传统 TLS fallback 静态站点 ───────────────────────"
    menuLine "未命中代理协议时展示本机静态页面"
    menuLine "如需自定义，请手动复制模板文件到 ${nginxStaticPath}"
    menuItem 1 "现代引导页" "站点模板 1"
    menuItem 2 "游戏工作室" "站点模板 2"
    menuItem 3 "个人笔记" "站点模板 3"
    menuItem 4 "商务服务" "站点模板 4"
    menuItem 5 "媒体工具" "站点模板 5"
    menuItem 6 "互动节奏页" "站点模板 6"
    menuItem 7 "制造企业" "站点模板 7"
    menuItem 8 "作品集展示" "站点模板 8"
    menuItem 9 "本地404页面" "站点模板 9"
    menuItem 10 "服务状态页" "站点模板 10"
    menuItem 11 "文档索引" "站点模板 11"
    menuItem 12 "产品简介" "站点模板 12"
    menuItem 13 "研究实验室" "站点模板 13"
    menuItem 14 "社区主页" "站点模板 14"
    menuItem 15 "旅行札记" "站点模板 15"
    menuItem 16 "食谱收藏" "站点模板 16"
    menuItem 17 "图片日志" "站点模板 17"
    menuItem 18 "学习中心" "站点模板 18"
    menuItem 19 "活动页面" "站点模板 19"
    menuItem 20 "团队介绍" "站点模板 20"
    menuReturnItem 21 "返回" "回到传统 TLS fallback 维护"
    menuClose
    autoRead nginx_blog_menu "请选择:" selectInstallNginxBlogType

    if [[ "${selectInstallNginxBlogType}" =~ ^([1-9]|1[0-9]|20)$ ]]; then
        installNginxStaticTemplate "${selectInstallNginxBlogType}"
        successCard "更换传统 TLS fallback 静态站点成功"
    elif [[ "${selectInstallNginxBlogType}" == "21" ]]; then
        manageTraditionalTlsFallback
    else
        errorCard "选择错误，请重新选择"
        manageTraditionalTlsStaticSite
    fi
}

manageTraditionalTlsRedirect() {
    echoContent title "\n┌─ 302 重定向管理 ───────────────────────────────────"
    menuLine "重定向优先级更高；配置后根路由静态站点将不起作用"
    menuLine "如想恢复静态站点展示，需要先删除 302 重定向配置"
    menuItem 1 "添加" "写入 302 重定向目标"
    menuItem 2 "删除" "移除当前 302 重定向"
    menuReturnItem 3 "返回" "回到传统 TLS fallback 维护"
    menuClose
    autoRead nginx_redirect_menu "请选择:" redirectStatus

    if [[ "${redirectStatus}" == "1" ]]; then
        backupNginxConfig backup
        autoRead redirect_domain "请输入要重定向的域名,例如 https://www.baidu.com:" redirectDomain
        if ! removeNginx302 || ! addNginx302 "${redirectDomain}"; then
            backupNginxConfig restoreBackup
            return 1
        fi
        serviceQueueRestart nginx
        if ! serviceQueueApply; then
            backupNginxConfig restoreBackup
            return 1
        fi
        if [[ -z $(pgrep -f "nginx") ]]; then
            backupNginxConfig restoreBackup
            serviceQueueStart nginx
            serviceQueueApply || return 1
            return 1
        fi
        if ! checkNginx302; then
            return 1
        fi
        exit 0
    elif [[ "${redirectStatus}" == "2" ]]; then
        removeNginx302
        successCard "移除302重定向成功"
        exit 0
    elif [[ "${redirectStatus}" == "3" ]]; then
        manageTraditionalTlsFallback
    else
        errorCard "选择错误，请重新选择"
        manageTraditionalTlsRedirect
    fi
}

diagnoseTraditionalTlsAlpn() {
    local configFile currentAlpn hasH2Fallback nginxH2Status
    configFile=$(traditionalTlsFallbackConfigFile)
    if [[ ! -f "${configFile}" ]]; then
        statusCard "ALPN 诊断" "未检测到传统 TLS fallback 入站配置"
        return 0
    fi

    currentAlpn=$(traditionalTlsCurrentAlpn)
    if traditionalTlsHasH2Fallback; then
        hasH2Fallback="是"
    else
        hasH2Fallback="否"
    fi
    if [[ -f "${nginxConfigPath}alone.conf" ]] && grep -q "127.0.0.1:31302" "${nginxConfigPath}alone.conf"; then
        nginxH2Status="存在"
    else
        nginxH2Status="未检测到"
    fi

    echoContent title "\n┌─ 传统 TLS ALPN 诊断 ───────────────────────────────"
    menuLine "配置文件：${configFile}"
    menuLine "当前 ALPN：${currentAlpn:-未设置}"
    menuLine "h2 fallback：${hasH2Fallback}"
    menuLine "Nginx h2 fallback：${nginxH2Status}"
    if [[ "${hasH2Fallback}" == "是" && "${currentAlpn}" != "h2,http/1.1" ]]; then
        menuLine "建议：修复为 h2,http/1.1"
    elif [[ "${hasH2Fallback}" == "是" ]]; then
        menuLine "结论：当前 ALPN 已符合 h2 fallback 推荐顺序"
    else
        menuLine "结论：未发现 h2 fallback，不需要调整 ALPN 顺序"
    fi
    menuClose
}

applyTraditionalTlsAlpn() {
    local alpnJson=$1
    local configFile backupFile tmpFile
    configFile=$(traditionalTlsFallbackConfigFile)
    backupFile="${configFile}.alpn.bak"
    if [[ ! -f "${configFile}" ]]; then
        errorCard "未检测到传统 TLS fallback 入站配置"
        return 1
    fi
    cp "${configFile}" "${backupFile}"
    padmCreateTempFileForTarget tmpFile "${configFile}" alpn || { rm -f "${backupFile}"; return 1; }
    if ! jq --argjson alpn "${alpnJson}" '.inbounds[0].streamSettings.tlsSettings.alpn = $alpn' "${configFile}" >"${tmpFile}"; then
        padmRemoveCleanupPath "${tmpFile}"
        rm -f "${backupFile}"
        errorCard "写入 ALPN 配置失败"
        return 1
    fi
    if ! commitGeneratedJsonFile "${tmpFile}" "${configFile}"; then
        padmRemoveCleanupPath "${tmpFile}"
        rm -f "${backupFile}"
        errorCard "写入 ALPN 配置失败"
        return 1
    fi
    if [[ -x /etc/padm/xray/xray ]] && ! /etc/padm/xray/xray -test -confdir /etc/padm/xray/conf >"$(traditionalTlsAlpnTestLog)" 2>&1; then
        if ! restoreTraditionalTlsAlpnBackup "${backupFile}" "${configFile}" "Xray 配置校验失败"; then
            return 1
        fi
        echoContent title "\n┌─ Xray 配置校验失败 ─────────────────────────────────"
        menuLine "已回滚本次 ALPN 修改"
        menuLine "排查日志：$(traditionalTlsAlpnTestLog)"
        menuClose
        return 1
    fi
    if ! reloadCore; then
        if ! restoreTraditionalTlsAlpnBackup "${backupFile}" "${configFile}" "核心重载失败"; then
            return 1
        fi
        if reloadCore; then
            errorCard "核心重载失败，已回滚 ALPN 修改"
        else
            errorCard "核心重载失败，已回滚 ALPN 修改；恢复旧配置后核心重载仍失败，请检查核心服务日志"
        fi
        return 1
    fi
    rm -f "${backupFile}"
    successCard "ALPN 配置已更新"
}

repairTraditionalTlsAlpn() {
    if traditionalTlsHasH2Fallback; then
        applyTraditionalTlsAlpn '["h2","http/1.1"]'
    else
        statusCard "ALPN 修复" "未发现 h2 fallback，不需要自动调整"
    fi
}

setTraditionalTlsAlpnManual() {
    echoContent title "\n┌─ 手动设置 ALPN ────────────────────────────────────"
    menuLine "仅用于传统 TLS fallback 兼容排障"
    menuRecommendedItem 1 "h2,http/1.1" "推荐用于存在 h2 fallback/gRPC 的场景"
    menuItem 2 "http/1.1,h2" "旧客户端兼容排障"
    menuItem 3 "http/1.1" "仅 HTTP/1.1"
    menuReturnItem 4 "返回" "回到传统 TLS fallback 维护"
    menuClose
    autoRead traditional_tls_alpn_manual "请选择:" selectAlpnManual
    case "${selectAlpnManual}" in
    1)
        applyTraditionalTlsAlpn '["h2","http/1.1"]'
        ;;
    2)
        applyTraditionalTlsAlpn '["http/1.1","h2"]'
        ;;
    3)
        applyTraditionalTlsAlpn '["http/1.1"]'
        ;;
    4)
        manageTraditionalTlsFallback
        ;;
    *)
        errorCard "选择错误，请重新选择"
        setTraditionalTlsAlpnManual
        ;;
    esac
}



# 入口端口管理
corePortIsValid() {
    local port=$1
    [[ "${port}" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535))
}

corePortParseList() {
    local input=$1
    local item
    local seen=,
    printf '%s\n' "${input}" | tr ',' '\n' | while read -r item; do
        item=${item//[[:space:]]/}
        [[ -z "${item}" ]] && continue
        if ! corePortIsValid "${item}"; then
            return 1
        fi
        if [[ "${seen}" != *",${item},"* ]]; then
            seen="${seen}${item},"
            printf '%s\n' "${item}"
        fi
    done
}

corePortListExtra() {
    local file base port defaultMark count=0
    for file in "${configPath}"02_dokodemodoor_inbounds_*.json; do
        [[ -f "${file}" ]] || continue
        base=${file##*/}
        [[ "${base}" == *hysteria* ]] && continue
        if [[ "${base}" =~ ^02_dokodemodoor_inbounds_([0-9]+)(_default)?\.json$ ]]; then
            port=${BASH_REMATCH[1]}
            defaultMark=
            [[ -n "${BASH_REMATCH[2]}" ]] && defaultMark=" 默认"
            count=$((count + 1))
            printf '%s:%s%s\n' "${count}" "${port}" "${defaultMark}"
        fi
    done
}

corePortResolveByIndex() {
    local index=$1
    corePortListExtra | while IFS=: read -r currentIndex value; do
        if [[ "${currentIndex}" == "${index}" ]]; then
            printf '%s\n' "${value%% *}"
            return 0
        fi
    done
}

corePortDefaultFile() {
    local file
    for file in "${configPath}"02_dokodemodoor_inbounds_*_default.json; do
        [[ -f "${file}" ]] && printf '%s\n' "${file}" && return 0
    done
    return 1
}

corePortRemove() {
    local port=$1
    local status=0
    rm -f "${configPath}02_dokodemodoor_inbounds_${port}.json" || status=1
    rm -f "${configPath}02_dokodemodoor_inbounds_${port}_default.json" || status=1
    rm -f "${configPath}02_dokodemodoor_inbounds_hysteria_${port}.json" || status=1
    return "${status}"
}

corePortBackupFiles() {
    local backupDir=$1
    local file base
    mkdir -p "${backupDir}" || return 1
    for file in "${configPath}"02_dokodemodoor_inbounds_*.json; do
        [[ -f "${file}" ]] || continue
        base=${file##*/}
        cp "${file}" "${backupDir}/${base}" || return 1
    done
}

corePortRollbackFiles() {
    local backupDir=$1
    local file status=0
    [[ -d "${backupDir}" ]] || return 1
    rm -f "${configPath}"02_dokodemodoor_inbounds_*.json || status=1
    for file in "${backupDir}"/*.json; do
        [[ -f "${file}" ]] || continue
        cp "${file}" "${configPath}${file##*/}" || status=1
    done
    return "${status}"
}

corePortValidateFiles() {
    local file
    for file in "${configPath}"02_dokodemodoor_inbounds_*.json; do
        [[ -f "${file}" ]] || continue
        jq empty "${file}" >/dev/null || return 1
    done
}

corePortWriteAddFiles() {
    local ports=$1
    local defaultPort=$2
    local settingsPort=$3
    local port fileName hysteriaFileName defaultFile
    if [[ -n "${defaultPort}" ]]; then
        defaultFile=$(corePortDefaultFile || true)
        [[ -z "${defaultFile}" ]] || rm -f "${defaultFile}" || return 1
    fi
    while read -r port; do
        corePortRemove "${port}" || return 1
        if [[ -n "${defaultPort}" && "${port}" == "${defaultPort}" ]]; then
            fileName="${configPath}02_dokodemodoor_inbounds_${port}_default.json"
        else
            fileName="${configPath}02_dokodemodoor_inbounds_${port}.json"
        fi
        if [[ -n ${hysteriaPort:-} ]]; then
            hysteriaFileName="${configPath}02_dokodemodoor_inbounds_hysteria_${port}.json"
            writeCoreDokodemoInbound "${hysteriaFileName}" "${port}" "${hysteriaPort}" udp "dokodemo-door-newPort-hysteria-${port}" || return 1
        fi
        writeCoreDokodemoInbound "${fileName}" "${port}" "${settingsPort}" tcp "dokodemo-door-newPort-${port}" || return 1
    done <<<"${ports}"
}

corePortApplyFileTransaction() {
    local action=$1
    local backupDir
    local tmpBase="${TMPDIR:-/tmp}"
    padmCreateTempPath backupDir -d "${tmpBase%/}/padm-core-port.XXXXXX" || return 1
    if ! corePortBackupFiles "${backupDir}"; then
        padmRemoveCleanupPath "${backupDir}"
        errorCard "入口端口配置备份失败"
        return 1
    fi
    shift
    if ! "${action}" "$@" || ! corePortValidateFiles; then
        if corePortRollbackFiles "${backupDir}"; then
            padmRemoveCleanupPath "${backupDir}"
        else
            padmForgetCleanupPath "${backupDir}"
            errorCard "入口端口配置回滚失败，请手动检查备份目录: ${backupDir}"
        fi
        return 1
    fi
    padmRemoveCleanupPath "${backupDir}"
}

corePortApplyReloadTransaction() {
    local action=$1
    local backupDir
    local tmpBase="${TMPDIR:-/tmp}"
    padmCreateTempPath backupDir -d "${tmpBase%/}/padm-core-port.XXXXXX" || return 1
    if ! corePortBackupFiles "${backupDir}"; then
        padmRemoveCleanupPath "${backupDir}"
        errorCard "入口端口配置备份失败"
        return 1
    fi
    shift
    if ! "${action}" "$@" || ! corePortValidateFiles; then
        if corePortRollbackFiles "${backupDir}"; then
            padmRemoveCleanupPath "${backupDir}"
        else
            padmForgetCleanupPath "${backupDir}"
            errorCard "入口端口配置回滚失败，请手动检查备份目录: ${backupDir}"
        fi
        return 1
    fi
    if reloadCore; then
        padmRemoveCleanupPath "${backupDir}"
        return 0
    fi

    if ! corePortRollbackFiles "${backupDir}"; then
        padmForgetCleanupPath "${backupDir}"
        errorCard "入口端口核心重载失败，且旧配置恢复失败，请手动检查备份目录: ${backupDir}"
        return 1
    fi
    reloadCore || errorCard "入口端口核心重载失败，已恢复旧配置；恢复后核心重载仍失败，请检查核心服务日志"
    padmRemoveCleanupPath "${backupDir}"
    return 1
}

writeCoreDokodemoInbound() {
    local fileName=$1
    local port=$2
    local targetPort=$3
    local network=$4
    local tag=$5
    mkdir -p "$(dirname "${fileName}")" || return 1
    cat <<EOF >"${fileName}" || return 1
{
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${port},
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1",
        "port": ${targetPort},
        "network": "${network}",
        "followRedirect": false
      },
      "tag": "${tag}"
    }
  ]
}
EOF
}

addCorePort() {

    if [[ "${coreInstallType}" == "2" ]]; then
        errorCard "此功能仅支持Xray-core内核"
        exit 0
    fi

    echoContent title "\n┌─ 入口端口管理 ─────────────────────────────────────"
    menuLine "支持批量添加；不影响默认端口使用"
    menuLine "查看账号时只展示默认端口账号；端口列表用英文逗号分隔"
    menuLine "如已安装 Hysteria2，会同时安装 Hysteria2 新端口"
    menuLine "示例：2053,2083,2087"
    menuItem 1 "查看已添加端口" "列出当前额外端口"
    menuItem 2 "添加端口" "批量添加新入口端口"
    menuItem 3 "删除端口" "移除已添加端口"
    menuClose
    autoRead core_port_menu "请选择:" selectNewPortType
    if [[ "${selectNewPortType}" == "1" ]]; then
        corePortListExtra
        exit 0
    elif [[ "${selectNewPortType}" == "2" ]]; then
        autoRead extra_core_ports "请输入端口号:" newPort
        autoRead extra_core_default_port "请输入默认的端口号，同时会更改订阅端口以及节点端口，[回车]默认443:" defaultPort

        if [[ -n "${newPort}" ]]; then
            local parsedPorts=
            local settingsPort=443
            parsedPorts=$(corePortParseList "${newPort}") || {
                errorCard "端口格式错误"
                return 1
            }
            if [[ -n "${customPort}" ]]; then
                settingsPort=${customPort}
            fi
            while read -r port; do
                allowPort "${port}" || return 1
                allowPort "${port}" "udp" || return 1
            done <<<"${parsedPorts}"
            if ! corePortApplyReloadTransaction corePortWriteAddFiles "${parsedPorts}" "${defaultPort}" "${settingsPort}"; then
                errorCard "入口端口配置写入或重载失败，已尝试恢复旧配置；如上方提示回滚失败，请检查备份目录"
                return 1
            fi

            successCard "添加完毕"
            addCorePort
        fi
    elif [[ "${selectNewPortType}" == "3" ]]; then
        corePortListExtra
        autoRead extra_core_delete_port "请输入要删除的端口编号:" portIndex
        local port
        port=$(corePortResolveByIndex "${portIndex}")
        if [[ -n "${port}" ]]; then
            if ! corePortApplyReloadTransaction corePortRemove "${port}"; then
                errorCard "入口端口删除或重载失败，已尝试恢复旧配置；如上方提示回滚失败，请检查备份目录"
                return 1
            fi

            addCorePort
        else
            statusCard "输入错误" "编号输入错误，请重新选择"
            addCorePort
        fi
    fi
}


# 卸载脚本
removeInstallPath() {
    local targetPath=$1
    local description=$2
    local attempt

    if [[ ! -e "${targetPath}" && ! -L "${targetPath}" ]]; then
        return 0
    fi

    for attempt in 1 2 3; do
        if rm -rf "${targetPath}"; then
            if [[ ! -e "${targetPath}" && ! -L "${targetPath}" ]]; then
                return 0
            fi
        fi
        sleep 0.2
    done

    errorCard "${description}删除失败: ${targetPath}"
    return 1
}

removePadmNginxConfigFragments() {
    local failed=false
    local dir name candidate
    local -a dirs=()
    local -a names=(alone.conf checkPortOpen.conf sing_box_VMess_HTTPUpgrade.conf subscribe.conf padm-control-wg.conf)

    [[ -n "${nginxConfigPath:-}" ]] && dirs+=("${nginxConfigPath}")
    dirs+=("${PADM_NGINX_CONF_FALLBACK_DIR:-/etc/nginx/conf.d/}")

    for dir in "${dirs[@]}"; do
        for name in "${names[@]}"; do
            candidate="${dir%/}/${name}"
            removeInstallPath "${candidate}" "Nginx PADM配置" || failed=true
        done
    done

    [[ "${failed}" != "true" ]]
}

cleanupSubscriptionWireGuardControlOnUninstall() {
    stopSubscriptionWireGuardControlService
    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now padm-subscription-control.service >/dev/null 2>&1 || true
    fi
    removeInstallPath "$(subscriptionWireGuardConfigFile)" "WireGuard控制面配置" || return 1
    removeInstallPath "$(subscriptionControlServiceFile)" "订阅控制面systemd服务" || return 1
}

cleanupFail2banManagedFilesOnUninstall() {
    local failed=false
    removeInstallPath "$(fail2banManagedJailFile)" "Fail2ban jail 配置" || failed=true
    removeInstallPath "$(fail2banManagedFilterFile)" "Fail2ban filter 配置" || failed=true
    removeInstallPath "$(fail2banPadmControlLogFile)" "Fail2ban 控制面日志" || failed=true
    if declare -F fail2banReloadServiceIfRunning >/dev/null 2>&1; then
        fail2banReloadServiceIfRunning || failed=true
    fi
    [[ "${failed}" != "true" ]]
}

unInstall() {
    autoRead uninstall_confirm "是否确认卸载安装内容？[y/n]:" unInstallStatus
    if [[ "${unInstallStatus}" != "y" ]]; then
        successCard "放弃卸载"
        menu
        exit 0
    fi
    # checkBTPanel
    statusCard "卸载提示" "脚本不会删除 acme 相关配置" "如需删除请手动执行：rm -rf /root/.acme.sh"
    local uninstallFailed=false
    if ! runCoreServiceActionAllowFailure handleNginx stop; then
        uninstallFailed=true
    fi
    if [[ -z $(pgrep -f "nginx") ]]; then
        successCard "停止Nginx成功"
    fi
    if [[ "${release}" == "alpine" ]]; then
        if [[ "${coreInstallType}" == "1" || -e /etc/init.d/xray || -L /etc/init.d/xray ]]; then
            if ! runCoreServiceActionAllowFailure handleXray stop; then
                uninstallFailed=true
            fi
            if ! rc-update del xray default; then
                uninstallFailed=true
                errorCard "Xray开机自启删除失败"
            fi
            removeInstallPath /etc/init.d/xray "Xray OpenRC服务" || uninstallFailed=true
            successCard "删除Xray开机自启完成"
        fi
        if [[ "${coreInstallType}" == "2" || -n "${singBoxConfigPath}" || -e /etc/init.d/sing-box || -L /etc/init.d/sing-box ]]; then
            if ! runCoreServiceActionAllowFailure handleSingBox stop; then
                uninstallFailed=true
            fi
            if ! rc-update del sing-box default; then
                uninstallFailed=true
                errorCard "sing-box开机自启删除失败"
            fi
            removeInstallPath /etc/init.d/sing-box "sing-box OpenRC服务" || uninstallFailed=true
            successCard "删除sing-box开机自启完成"
        fi
    else
        if [[ "${coreInstallType}" == "1" || -e /etc/systemd/system/xray.service || -L /etc/systemd/system/xray.service ]]; then
            if ! runCoreServiceActionAllowFailure handleXray stop; then
                uninstallFailed=true
            fi
            removeInstallPath /etc/systemd/system/xray.service "Xray systemd服务" || uninstallFailed=true
            successCard "删除Xray开机自启完成"
        fi
        if [[ "${coreInstallType}" == "2" || -n "${singBoxConfigPath}" || -e /etc/systemd/system/sing-box.service || -L /etc/systemd/system/sing-box.service ]]; then
            if ! runCoreServiceActionAllowFailure handleSingBox stop; then
                uninstallFailed=true
            fi
            removeInstallPath /etc/systemd/system/sing-box.service "sing-box systemd服务" || uninstallFailed=true
            successCard "删除sing-box开机自启完成"
        fi
    fi

    cleanupSubscriptionWireGuardControlOnUninstall || uninstallFailed=true
    cleanupFail2banManagedFilesOnUninstall || uninstallFailed=true

    if ! removePadmNginxConfigFragments; then
        uninstallFailed=true
    fi
    removeInstallPath /etc/padm "PADM配置目录" || uninstallFailed=true

    if ! unInstallSubscribe; then
        uninstallFailed=true
    fi

    if [[ -d "${nginxStaticPath}" && -f "${nginxStaticPath}/check" ]]; then
        removeInstallPath "${nginxStaticPath}" "伪装网站" || uninstallFailed=true
        successCard "删除伪装网站完成"
    fi

    removeInstallPath /usr/bin/padm "PADM快捷方式" || uninstallFailed=true
    removeInstallPath /usr/sbin/padm "PADM快捷方式" || uninstallFailed=true
    if [[ "${uninstallFailed}" == "true" ]]; then
        errorCard "卸载未完全完成，请根据上方失败项手动处理"
        return 1
    fi
    successCard "卸载快捷方式完成"
    successCard "卸载管理脚本完成"
}


# CDN 入口管理
cdnAddressFile() {
    printf '%s' "/etc/padm/cdn"
}

cdnCurrentAddress() {
    readInstallType
    if [[ -f "$(cdnAddressFile)" ]] && [[ -n "$(head -1 "$(cdnAddressFile)")" ]]; then
        head -1 "$(cdnAddressFile)"
    elif [[ -n "${currentHost:-}" ]]; then
        printf '%s\n' "${currentHost}"
    elif [[ -n "${realityEntryHost:-}" ]]; then
        printf '%s\n' "${realityEntryHost}"
    else
        printf '未设置\n'
    fi
}

cdnWriteAddress() {
    local address=$1
    mkdir -p /etc/padm
    printf '%s\n' "${address}" >"$(cdnAddressFile)"
}

cdnClearAddress() {
    mkdir -p /etc/padm
    : >"$(cdnAddressFile)"
}

showCDNUsageNotes() {
    echoContent title "\n┌─ CDN 使用说明 ─────────────────────────────────────"
    menuLine "1. 新建 CDN 场景优先使用协议 12：$(xrayProtocolName 12)"
    menuLine "2. 这里设置的是客户端订阅里的入口地址，可填 CDN CNAME、优选 IP 或自有域名"
    menuLine "3. Reality SNI/target 不会随入口地址改变；它仍由 Reality 目标站管理维护"
    menuLine "4. Cloudflare WebSocket 可用；gRPC/H2/H3 依赖面板开关、客户端与线路支持"
    menuLine "5. 传统 WS/gRPC/HTTPUpgrade 仅用于旧客户端兼容，新建节点优先迁移到 XHTTP"
    menuClose
}

setCDNEntryAddress() {
    local currentAddress input
    currentAddress=$(cdnCurrentAddress)
    echoContent title "\n┌─ 设置 CDN 入口地址 ─────────────────────────────────"
    menuLine "当前入口地址：${currentAddress}"
    menuLine "可输入多个地址，用英文逗号分隔；订阅会为每个地址生成一条节点"
    menuLine "示例：cdn.example.com,203.0.113.10"
    menuClose
    autoRead custom_cdn_domain "请输入 CDN 入口 IP 或域名[回车取消]:" input
    if [[ -z "${input}" ]]; then
        statusCard "已取消" "未修改 CDN 入口地址"
        return 0
    fi
    cdnWriteAddress "${input}"
    statusCard "CDN 入口" "已更新为 ${input}"
    subscribe false false
}

manageCDN() {
    progressCard "$1" "CDN 入口管理" "1"
    readInstallType
    readInstallProtocolType

    echoContent title "\n┌─ CDN 入口管理 ─────────────────────────────────────"
    menuLine "这里只覆盖订阅里的客户端连接地址，不修改 Reality target/SNI 或 XHTTP 参数"
    menuLine "多个 CDN CNAME、优选 IP 或入口域名可用英文逗号分隔，订阅会生成多条节点"
    menuLine "当前入口地址：$(cdnCurrentAddress)"
    if currentProtocolHas 12; then
        menuLine "当前已安装 Reality XHTTP，可直接调整入口地址"
    elif currentProtocolHasAny 1 2 3 5 11; then
        menuLine "当前是传统 TLS/CDN 协议，仅建议用于旧客户端兼容"
    else
        menuLine "未检测到 CDN 友好协议；新建 CDN 节点建议安装协议 12：$(xrayProtocolName 12)"
    fi
    menuItem 1 "设置入口地址" "写入 CDN CNAME、优选 IP 或自有域名"
    menuItem 2 "清空入口地址" "恢复订阅使用安装入口地址"
    menuItem 3 "CDN / H3 使用说明" "查看协议选择和排障提示"
    menuReturnItem 4 "返回协议与入口" "回到上级菜单"
    menuClose
    autoRead cdn_menu "请选择:" selectCDNType

    case ${selectCDNType} in
    1)
        if currentProtocolHas 12 || currentProtocolHasAny 1 2 3 5 11; then
            setCDNEntryAddress
        else
            statusCard "不可用" "请先安装 Reality XHTTP 或传统 TLS/CDN 协议"
        fi
        ;;
    2)
        cdnClearAddress
        statusCard "CDN 入口" "已清空，订阅将使用安装入口地址"
        subscribe false false
        ;;
    3)
        showCDNUsageNotes
        ;;
    4)
        protocolEntryMenu
        ;;
    *)
        errorCard "选择错误"
        manageCDN 1
        ;;
    esac
}

# Clash Meta 配置文件
clashMetaConfig() {
    local url=$1
    local id=$2
    local targetPath=${3:-$(subscribePublicBaseDir)/clashMetaProfiles/${id}}
    [[ "${PADM_FAKE_CLASH_META_CONFIG_MODE:-success}" == "success" ]] || return 1
    cat <<EOF >"${targetPath}"
log-level: debug
mode: rule
ipv6: true
mixed-port: 7890
allow-lan: true
bind-address: "*"
lan-allowed-ips:
  - 0.0.0.0/0
  - ::/0
find-process-mode: strict
external-controller: 0.0.0.0:9090

geox-url:
  geoip: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"
  geosite: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
  mmdb: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb"
geo-auto-update: true
geo-update-interval: 24

external-controller-cors:
  allow-private-network: true

global-client-fingerprint: chrome

profile:
  store-selected: true
  store-fake-ip: true

sniffer:
  enable: true
  override-destination: false
  sniff:
    QUIC:
      ports: [ 443 ]
    TLS:
      ports: [ 443 ]
    HTTP:
      ports: [80]


dns:
  enable: true
  prefer-h3: false
  listen: 0.0.0.0:1053
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - '*.lan'
    - '*.local'
    - 'dns.google'
    - "localhost.ptlogin2.qq.com"
  use-hosts: true
  nameserver:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
    - 1.1.1.1
    - 8.8.8.8
  proxy-server-nameserver:
    - https://223.5.5.5/dns-query
    - https://1.12.12.12/dns-query
  nameserver-policy:
    "geosite:cn,private":
      - https://doh.pub/dns-query
      - https://dns.alidns.com/dns-query

proxy-providers:
  ${subscribeSalt}_provider:
    type: http
    path: ./${subscribeSalt}_provider.yaml
    url: ${url}
    interval: 3600
    proxy: DIRECT
    health-check:
      enable: true
      url: https://cp.cloudflare.com/generate_204
      interval: 300

proxy-groups:
  - name: 手动切换
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies: null
  - name: 自动选择
    type: url-test
    url: http://www.gstatic.com/generate_204
    interval: 36000
    tolerance: 50
    use:
      - ${subscribeSalt}_provider
    proxies: null

  - name: 全球代理
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择

  - name: 流媒体
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
      - DIRECT
  - name: DNS_Proxy
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 自动选择
      - 手动切换
      - DIRECT

  - name: Telegram
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
  - name: Google
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
      - DIRECT
  - name: YouTube
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
  - name: Netflix
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 流媒体
      - 手动切换
      - 自动选择
  - name: Spotify
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 流媒体
      - 手动切换
      - 自动选择
      - DIRECT
  - name: HBO
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 流媒体
      - 手动切换
      - 自动选择
  - name: Bing
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择


  - name: OpenAI
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择

  - name: ClaudeAI
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择

  - name: Disney
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 流媒体
      - 手动切换
      - 自动选择
  - name: GitHub
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
      - DIRECT

  - name: 国内媒体
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - DIRECT
  - name: 本地直连
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - DIRECT
      - 自动选择
  - name: 漏网之鱼
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - DIRECT
      - 手动切换
      - 自动选择
rule-providers:
  lan:
    type: http
    behavior: classical
    interval: 86400
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Lan/Lan.yaml
    path: ./Rules/lan.yaml
  reject:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt
    path: ./ruleset/reject.yaml
    interval: 86400
  proxy:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/proxy.txt
    path: ./ruleset/proxy.yaml
    interval: 86400
  direct:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt
    path: ./ruleset/direct.yaml
    interval: 86400
  private:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/private.txt
    path: ./ruleset/private.yaml
    interval: 86400
  gfw:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/gfw.txt
    path: ./ruleset/gfw.yaml
    interval: 86400
  greatfire:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/greatfire.txt
    path: ./ruleset/greatfire.yaml
    interval: 86400
  tld-not-cn:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/tld-not-cn.txt
    path: ./ruleset/tld-not-cn.yaml
    interval: 86400
  telegramcidr:
    type: http
    behavior: ipcidr
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/telegramcidr.txt
    path: ./ruleset/telegramcidr.yaml
    interval: 86400
  applications:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/applications.txt
    path: ./ruleset/applications.yaml
    interval: 86400
  Disney:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Disney/Disney.yaml
    path: ./ruleset/disney.yaml
    interval: 86400
  Netflix:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Netflix/Netflix.yaml
    path: ./ruleset/netflix.yaml
    interval: 86400
  YouTube:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/YouTube/YouTube.yaml
    path: ./ruleset/youtube.yaml
    interval: 86400
  HBO:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/HBO/HBO.yaml
    path: ./ruleset/hbo.yaml
    interval: 86400
  OpenAI:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/OpenAI/OpenAI.yaml
    path: ./ruleset/openai.yaml
    interval: 86400
  ClaudeAI:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Claude/Claude.yaml
    path: ./ruleset/claudeai.yaml
    interval: 86400
  Bing:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Bing/Bing.yaml
    path: ./ruleset/bing.yaml
    interval: 86400
  Google:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Google/Google.yaml
    path: ./ruleset/google.yaml
    interval: 86400
  GitHub:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/GitHub/GitHub.yaml
    path: ./ruleset/github.yaml
    interval: 86400
  Spotify:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Spotify/Spotify.yaml
    path: ./ruleset/spotify.yaml
    interval: 86400
  ChinaMaxDomain:
    type: http
    behavior: domain
    interval: 86400
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/ChinaMax/ChinaMax_Domain.yaml
    path: ./Rules/ChinaMaxDomain.yaml
  ChinaMaxIPNoIPv6:
    type: http
    behavior: ipcidr
    interval: 86400
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/ChinaMax/ChinaMax_IP_No_IPv6.yaml
    path: ./Rules/ChinaMaxIPNoIPv6.yaml
rules:
  - RULE-SET,YouTube,YouTube,no-resolve
  - RULE-SET,Google,Google,no-resolve
  - RULE-SET,GitHub,GitHub
  - RULE-SET,telegramcidr,Telegram,no-resolve
  - RULE-SET,Spotify,Spotify,no-resolve
  - RULE-SET,Netflix,Netflix
  - RULE-SET,HBO,HBO
  - RULE-SET,Bing,Bing
  - RULE-SET,OpenAI,OpenAI
  - RULE-SET,ClaudeAI,ClaudeAI
  - RULE-SET,Disney,Disney
  - RULE-SET,proxy,全球代理
  - RULE-SET,gfw,全球代理
  - RULE-SET,applications,本地直连
  - RULE-SET,ChinaMaxDomain,本地直连
  - RULE-SET,ChinaMaxIPNoIPv6,本地直连,no-resolve
  - RULE-SET,lan,本地直连,no-resolve
  - GEOIP,CN,本地直连
  - MATCH,漏网之鱼
EOF

}

commitSubscribeUserOutputFile() {
    local stagedPath=$1
    local targetPath=$2
    mkdir -p "$(dirname "${targetPath}")" || return 1
    if [[ -f "${stagedPath}" ]]; then
        mv "${stagedPath}" "${targetPath}" || return 1
    else
        rm -f "${targetPath}" || return 1
    fi
}

readSubscribeSalt() {
    local subscribeSaltFile=$1

    if [[ -f "${subscribeSaltFile}" ]]; then
        head -n 1 "${subscribeSaltFile}"
    fi
}

writeSubscribeSalt() {
    local subscribeSaltFile=$1
    local salt=$2

    mkdir -p "$(dirname "${subscribeSaltFile}")" || return 1
    printf '%s\n' "${salt}" >"${subscribeSaltFile}"
}

resolveSubscribeSalt() {
    local subscribeSaltFile=$1
    local renewSalt=$2
    local existingSalt

    existingSalt=$(readSubscribeSalt "${subscribeSaltFile}")
    if [[ -n "${existingSalt}" ]]; then
        if [[ -z "${renewSalt}" ]]; then
            autoRead subscribe_history_salt "读取到上次安装设置的Salt [${existingSalt}]，是否使用？[y/n]:" historySaltStatus
            if [[ "${historySaltStatus}" == "y" ]]; then
                subscribeSalt=${existingSalt}
            else
                autoRead subscribe_salt "请输入salt值, [回车]使用随机:" subscribeSalt
            fi
        else
            subscribeSalt=${existingSalt}
        fi
    elif [[ -n "${renewSalt}" || -n "${AUTO_INSTALL:-}" ]]; then
        subscribeSalt=$(initRandomSalt)
    else
        autoRead subscribe_salt "请输入salt值, [回车]使用随机:" subscribeSalt
    fi

    if [[ -z "${subscribeSalt}" ]]; then
        subscribeSalt=$(initRandomSalt)
    fi
    writeSubscribeSalt "${subscribeSaltFile}" "${subscribeSalt}"
}

resolveSubscribePublicDomain() {
    local domain="${subscribeDomain:-${currentHost:-}}"
    printf '%s' "${domain}"
}

renderAllSubscribeUserOutputs() {
    local localBase=$1
    local renewSalt=$2
    local showStatus=$3
    local publishAccountsOverride=${4:-}
    local skipCleanup=${5:-}
    local subscribePortLocal="${subscribePort}"
    local email emailMd5 currentDomain defaultFile
    local publishAccounts=
    local existingMd5s='[]'

    publishAccounts=${publishAccountsOverride:-$(subscriptionPublishAccounts "${localBase}" 2>/dev/null)} || return 1
    if subscriptionPublishHasRemoteSources "${publishAccounts}"; then
        if [[ -z "${renewSalt}" ]]; then
            autoRead subscribe_update_remote "读取到其他订阅，是否更新？[y/n]" updateOtherSubscribeStatus
        else
            updateOtherSubscribeStatus=y
        fi
    fi
    if [[ -z "${publishAccounts}" ]]; then
        if [[ "${skipCleanup}" != "true" ]]; then
            cleanupStaleSubscribeOutputs "${localBase}" "${existingMd5s}" || return 1
        fi
        return 0
    fi

    while IFS= read -r email; do
        [[ -n "${email}" ]] || continue
        emailMd5=$(printf '%s\n' "${email}${subscribeSalt}" | md5sum | awk '{print $1}')
        existingMd5s=$(jq --arg md5 "${emailMd5}" '. + [$md5]' <<<"${existingMd5s}") || return 1
        echoContent title "\n┌─ 订阅输出 ─────────────────────────────────────────"
        currentDomain=$(resolveSubscribePublicDomain)
        if [[ -z "${currentDomain}" ]]; then
            errorCard "订阅地址生成失败" "未读取到订阅服务域名，请进入 我的订阅 检查 HTTPS 发布入口配置"
            return 1
        fi

        if [[ -n "${currentDefaultPort}" && "${currentDefaultPort}" != "443" && -z "${subscribePortLocal}" ]]; then
            currentDomain="${currentDomain}:${currentDefaultPort}"
        fi
        if [[ -n "${subscribePortLocal}" ]]; then
            currentDomain="${currentDomain}:${subscribePort}"
        fi

        if ! renderSubscribeUserOutputs "${email}" "${emailMd5}" "${currentDomain}" "${updateOtherSubscribeStatus:-}" "${showStatus}"; then
            errorCard "${SUBSCRIBE_USER_OUTPUT_ERROR:-订阅生成失败，已保留旧订阅输出}"
            return 1
        fi

        if [[ -z "${showStatus}" ]]; then
            showSubscriptionUrlCard "默认订阅" "${email}" "${subscribeType}://${currentDomain}/s/default/${emailMd5}"
        fi
        if [[ -f "${localBase}/clashMeta/${email}" && -z "${showStatus}" ]]; then
            showSubscriptionUrlCard "Clash Meta 订阅" "${email}" "${subscribeType}://${currentDomain}/s/clashMetaProfiles/${emailMd5}"
        fi
        if [[ -f "${localBase}/sing-box/${email}" && -z "${showStatus}" ]]; then
            showSubscriptionUrlCard "sing-box 订阅" "${email}" "${subscribeType}://${currentDomain}/s/sing-box/${emailMd5}"
        fi
        if [[ -z "${showStatus}" ]]; then
            menuClose
        else
            successCard "email:${email}，订阅已更新，请使用客户端重新拉取"
        fi
    done <<<"${publishAccounts}"

    if [[ "${skipCleanup}" != "true" ]]; then
        cleanupStaleSubscribeOutputs "${localBase}" "${existingMd5s}" || return 1
    fi
}

subscriptionPublishAccounts() {
    local localBase=$1
    local localAccounts=
    local stagedAccounts=
    local publishAccounts=
    local account=

    localBase=${localBase:-$(subscribeLocalBaseDir)}
    if [[ -d "${localBase}/default" ]]; then
        while IFS= read -r defaultFile; do
            [[ -n "${defaultFile}" ]] || continue
            localAccounts+="${defaultFile##*/}"$'\n'
        done < <(find "${localBase}/default" -mindepth 1 -maxdepth 1 -type f | sort)
    fi
    while IFS= read -r account; do
        [[ -n "${account}" ]] || continue
        if subscriptionAccountHasPublishSource "${account}"; then
            stagedAccounts+="${account}"$'\n'
        fi
    done < <(listUserSubscriptions | awk -F ':' '$3 == "true" {print "sub_" $1}' | tr '-' '_')
    publishAccounts=$(printf '%s\n%s' "${localAccounts}" "${stagedAccounts}" | awk 'length($0) > 0 && !seen[$0]++')
    printf '%s\n' "${publishAccounts}" | sed '/^$/d'
}

cleanupStaleSubscribeOutputs() {
    local localBase=$1
    local existingMd5s=$2
    local publicBase
    local defaultFile
    local staleMd5
    local currentMd5s='[]'

    publicBase=$(subscribePublicBaseDir)
    [[ -d "${publicBase}/default" ]] || return 0
    while IFS= read -r defaultFile; do
        [[ -n "${defaultFile}" ]] || continue
        currentMd5s=$(jq --arg md5 "${defaultFile##*/}" '. + [$md5]' <<<"${currentMd5s}") || return 1
    done < <(find "${publicBase}/default" -mindepth 1 -maxdepth 1 -type f | sort)

    while IFS= read -r staleMd5; do
        [[ -n "${staleMd5}" ]] || continue
        rm -f \
            "${publicBase}/default/${staleMd5}" \
            "${publicBase}/clashMeta/${staleMd5}" \
            "${publicBase}/clashMetaProfiles/${staleMd5}" \
            "${publicBase}/sing-box/${staleMd5}" \
            "${publicBase}/sing-box_profiles/${staleMd5}" || return 1
    done < <(jq -r --argjson existing "${existingMd5s}" --argjson current "${currentMd5s}" '$current - $existing | .[]' <<<"null")
}

renderSubscribeUserOutputs() {
    local email=$1
    local emailMd5=$2
    local currentDomain=$3
    local updateRemoteStatus=$4
    local showStatus=$5
    local localBase publicBase stageDir defaultPath clashPath clashProfilePath singBoxProfilePath singBoxPath clashProxyUrl localSingBoxTemplate base64Result singBoxTmpPath subscribeBackupDir clashSourcePath clashContentPath
    local commitFailed=false
    local tmpBase="${TMPDIR:-/tmp}"

    SUBSCRIBE_USER_OUTPUT_ERROR=
    localBase=$(subscribeLocalBaseDir)
    publicBase=$(subscribePublicBaseDir)
    padmCreateTempPath stageDir -d "${tmpBase%/}/padm-subscribe-user.XXXXXX" || return 1
    mkdir -p "${stageDir}/default" "${stageDir}/clashMeta" "${stageDir}/clashMetaProfiles" "${stageDir}/sing-box" "${stageDir}/sing-box_profiles"

    defaultPath="${stageDir}/default/${emailMd5}"
    clashPath="${stageDir}/clashMeta/${emailMd5}"
    clashProfilePath="${stageDir}/clashMetaProfiles/${emailMd5}"
    singBoxProfilePath="${stageDir}/sing-box_profiles/${emailMd5}"
    singBoxPath="${stageDir}/sing-box/${emailMd5}"

    if [[ -f "${localBase}/default/${email}" ]]; then
        if ! cp "${localBase}/default/${email}" "${defaultPath}"; then
            padmRemoveCleanupPath "${stageDir}"
            return 1
        fi
    elif [[ "${updateRemoteStatus}" == "y" ]]; then
        : >"${defaultPath}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }
    else
        padmRemoveCleanupPath "${stageDir}"
        return 1
    fi
    if [[ "${updateRemoteStatus}" == "y" ]]; then
        if ! PADM_SUBSCRIBE_DIR="${stageDir}" updateRemoteSubscribe "${emailMd5}" "${email}"; then
            padmRemoveCleanupPath "${stageDir}"
            return 1
        fi
    fi
    if [[ ! -s "${defaultPath}" ]]; then
        padmRemoveCleanupPath "${stageDir}"
        return 1
    fi
    if ! base64Result=$(base64 -w 0 "${defaultPath}"); then
        padmRemoveCleanupPath "${stageDir}"
        return 1
    fi
    printf '%s\n' "${base64Result}" >"${defaultPath}"

    clashSourcePath="${localBase}/clashMeta/${email}"
    if [[ ! -f "${clashSourcePath}" && -s "${clashPath}" ]]; then
        clashSourcePath="${clashPath}"
    fi
    if [[ -f "${clashSourcePath}" ]]; then
        clashContentPath="${clashSourcePath}"
        if [[ "${clashSourcePath}" == "${clashPath}" ]]; then
            padmCreateTempFileForTarget clashContentPath "${clashPath}" clash || { padmRemoveCleanupPath "${stageDir}"; return 1; }
            cp "${clashPath}" "${clashContentPath}" || { padmRemoveCleanupPath "${clashContentPath}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
        fi
        {
            printf 'proxies:\n'
            cat "${clashContentPath}"
        } >"${clashPath}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }
        [[ "${clashContentPath}" != "${clashSourcePath}" ]] && padmRemoveCleanupPath "${clashContentPath}"
        clashProxyUrl="${subscribeType}://${currentDomain}/s/clashMeta/${emailMd5}"
        if ! clashMetaConfig "${clashProxyUrl}" "${emailMd5}" "${clashProfilePath}"; then
            padmRemoveCleanupPath "${stageDir}"
            return 1
        fi
    fi

    if [[ -f "${localBase}/sing-box/${email}" ]]; then
        if ! cp "${localBase}/sing-box/${email}" "${singBoxProfilePath}"; then
            padmRemoveCleanupPath "${stageDir}"
            return 1
        fi
        [[ -z "${showStatus}" ]] && statusCard "sing-box 通用配置" "正在下载 sing-box 通用配置文件"
        localSingBoxTemplate="${SCRIPT_DIR:-/etc/padm}/documents/sing-box.json"
        if [[ -f "${localSingBoxTemplate}" ]]; then
            cp "${localSingBoxTemplate}" "${singBoxPath}"
        else
            downloadFile -O "${singBoxPath}" "https://raw.githubusercontent.com/neil1123-vip/padm/main/documents/sing-box.json"
        fi
        padmCreateTempFileForTarget singBoxTmpPath "${singBoxPath}" singbox || { padmRemoveCleanupPath "${stageDir}"; return 1; }
        if ! jq --slurpfile localOutbounds "${localBase}/sing-box/${email}" '
          ($localOutbounds[0] | map(.tag)) as $tags |
          .outbounds |= (map(if has("outbounds") then .outbounds += $tags else . end) + $localOutbounds[0])
        ' "${singBoxPath}" >"${singBoxTmpPath}"; then
            padmRemoveCleanupPath "${singBoxTmpPath}"
            padmRemoveCleanupPath "${stageDir}"
            return 1
        fi
        commitGeneratedJsonFile "${singBoxTmpPath}" "${singBoxPath}" || { padmRemoveCleanupPath "${singBoxTmpPath}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    fi

    checkLogBackupCreate subscribeBackupDir \
        "${publicBase}/default/${emailMd5}" \
        "${publicBase}/clashMeta/${emailMd5}" \
        "${publicBase}/clashMetaProfiles/${emailMd5}" \
        "${publicBase}/sing-box_profiles/${emailMd5}" \
        "${publicBase}/sing-box/${emailMd5}" || {
        padmRemoveCleanupPath "${stageDir}"
        SUBSCRIBE_USER_OUTPUT_ERROR="订阅输出备份失败，已取消发布"
        return 1
    }

    commitSubscribeUserOutputFile "${defaultPath}" "${publicBase}/default/${emailMd5}" || commitFailed=true
    commitSubscribeUserOutputFile "${clashPath}" "${publicBase}/clashMeta/${emailMd5}" || commitFailed=true
    commitSubscribeUserOutputFile "${clashProfilePath}" "${publicBase}/clashMetaProfiles/${emailMd5}" || commitFailed=true
    commitSubscribeUserOutputFile "${singBoxProfilePath}" "${publicBase}/sing-box_profiles/${emailMd5}" || commitFailed=true
    commitSubscribeUserOutputFile "${singBoxPath}" "${publicBase}/sing-box/${emailMd5}" || commitFailed=true

    if [[ "${commitFailed}" == "true" ]]; then
        if ! checkLogBackupRestore "${subscribeBackupDir}"; then
            padmForgetCleanupPath "${subscribeBackupDir}"
            padmRemoveCleanupPath "${stageDir}"
            SUBSCRIBE_USER_OUTPUT_ERROR="订阅生成失败，且旧订阅输出恢复失败，请手动检查备份目录: ${subscribeBackupDir}"
            return 1
        fi
        padmRemoveCleanupPath "${subscribeBackupDir}"
        padmRemoveCleanupPath "${stageDir}"
        SUBSCRIBE_USER_OUTPUT_ERROR="订阅生成失败，已恢复旧订阅输出"
        return 1
    fi

    padmRemoveCleanupPath "${subscribeBackupDir}"
    padmRemoveCleanupPath "${stageDir}"
    return 0
}

# 订阅
subscribe() {
    readInstallProtocolType
    if ! installSubscribe; then
        return 1
    fi

    readNginxSubscribe
    local renewSalt=$1
    local showStatus=$2
    local publishAccountsOverride=${3:-}
    local skipCleanup=${4:-}
    if [[ "${coreInstallType}" == "1" || "${coreInstallType}" == "2" ]]; then

        echoContent title "\n┌─ 订阅生成说明 ─────────────────────────────────────"
        menuLine "查看订阅会重新生成本地账号的订阅"
        menuLine "需要手动输入 md5 加密 salt 值；不了解时直接回车随机即可"
        menuLine "不影响已添加的远程订阅内容"
        menuClose

        local localBase subscribeSaltFile backupDir previousSubscribeSalt
        local tmpBase="${TMPDIR:-/tmp}"
        localBase=$(subscribeLocalBaseDir)
        subscribeSaltFile="${localBase}/subscribeSalt"
        previousSubscribeSalt=$(readSubscribeSalt "${subscribeSaltFile}")
        padmCreateTempPath backupDir -d "${tmpBase%/}/padm-subscribe-local-backup.XXXXXX" || {
            errorCard "订阅生成失败：创建本地订阅备份目录失败"
            return 1
        }
        if ! subscriptionSyncBackupPath "${localBase}" "${backupDir}" local; then
            padmRemoveCleanupPath "${backupDir}"
            errorCard "订阅生成失败：备份旧本地订阅失败"
            return 1
        fi
        if ! resolveSubscribeSalt "${subscribeSaltFile}" "${renewSalt}"; then
            restoreLocalSubscribeOutputs "${localBase}" "${backupDir}" "订阅 Salt 初始化失败" "${previousSubscribeSalt}"
            return 1
        fi
        statusCard "订阅 Salt" "${subscribeSalt}"
        if ! cleanDirectoryContent "${localBase}/default" ||
            ! cleanDirectoryContent "${localBase}/clashMeta" ||
            ! cleanDirectoryContent "${localBase}/sing-box"; then
            restoreLocalSubscribeOutputs "${localBase}" "${backupDir}" "订阅生成失败：清理本地订阅目录失败" "${previousSubscribeSalt}"
            return 1
        fi
        if ! showAccounts >/dev/null; then
            restoreLocalSubscribeOutputs "${localBase}" "${backupDir}" "订阅生成失败：重建本地订阅失败" "${previousSubscribeSalt}"
            return 1
        fi
        if ! renderAllSubscribeUserOutputs "${localBase}" "${renewSalt}" "${showStatus}" "${publishAccountsOverride}" "${skipCleanup}"; then
            restoreLocalSubscribeOutputs "${localBase}" "${backupDir}" "订阅生成失败：生成订阅输出失败" "${previousSubscribeSalt}"
            return 1
        fi
        padmRemoveCleanupPath "${backupDir}"
    else
        errorCard "未安装传统 TLS fallback 静态站点，无法使用订阅服务"
        return 1
    fi
}


showSubscriptionUrlCard() {
    local title=$1
    local email=$2
    local url=$3
    echoContent title "\n┌─ ${title} ─────────────────────────────────────────"
    [[ -n "${email}" ]] && menuLine "账号：${email}"
    menuLine "订阅地址：${url}"
    menuLine "在线二维码：https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=${url}"
    menuClose
    if [[ "${release}" != "alpine" ]] && command -v qrencode >/dev/null 2>&1; then
        echo "${url}" | qrencode -s 10 -m 1 -t UTF8
    fi
}


# 随机订阅 salt
initRandomSalt() {
    local chars="abcdefghijklmnopqrtuxyz"
    local initCustomPath=
    for i in {1..10}; do
        echo "${i}" >/dev/null
        initCustomPath+="${chars:RANDOM%${#chars}:1}"
    done
    echo "${initCustomPath}"
}

switchAlpn() {
    manageTraditionalTlsFallback "$@"
}


manageRealityTarget() {
    local currentTarget selectTargetMenu targetInput sniInput selectedHost selectedSni targetAsnSummary currentAsnSummary
    while true; do
    readInstallProtocolType
    readConfigHostPathUUID
    readCustomPort
    readSingBoxConfig
    if [[ -n "${realityTargetHost:-}" ]]; then
        currentTarget=$(formatRealityTarget "${realityTargetHost}" "${realityTargetPort:-443}")
        targetAsnSummary=$(realityTargetAsnSummary "${realityTargetHost}" || true)
    else
        currentTarget="未读取到"
        targetAsnSummary="未读取到目标站"
    fi
    currentAsnSummary=$(currentRealityAsnSummary || true)

    echoContent title "\n┌─ REALITY 目标站管理 ───────────────────────────────"
    menuLine "当前目标: ${currentTarget}"
    menuLine "当前 SNI: ${realitySNI:-未知}"
    menuLine "目标 ASN: ${targetAsnSummary}"
    menuLine "本机 ASN: ${currentAsnSummary}"
    menuItem 1 "实时查看目标质量" "重新检测评分、TLS/PQC，并展示证书链与链路分析"
    menuItem 2 "刷新目标库质量" "复测统一目标库，按 TLS/PQC 与 ASN 关系写入结果"
    menuItem 3 "扫描本机附近网段" "运行 RealiTLScanner，发现目标并导入统一目标库"
    menuItem 4 "随机抽样同 ASN" "拉取本机 ASN 公告前缀，发现目标并导入统一目标库"
    menuItem 5 "查看/切换检测结果" "分页查看统一结果；A/B 级可直接选择切换"
    menuItem 6 "手动设置目标站" "输入 host[:port] 和可选 SNI"
    menuItem 7 "查看目标站黑名单" "显示 CDN/Apple 等不会参与扫描的目标"
    menuItem 8 "查看 PQC/ML-DSA-65 状态" "展示当前 pqv 与目标站评分"
    menuReturnItem 9 "返回" "回到 REALITY 管理"
    menuClose
    autoRead reality_target_manage_menu "请选择:" selectTargetMenu
    case "${selectTargetMenu}" in
    1)
        if [[ "${currentTarget}" != "未读取到" ]]; then
            showRealityTargetCachedQuality "${currentTarget}" || true
        fi
        ;;
    2)
        scanLocalAsnRealityTargets || true
        ;;
    3)
        runRealityScannerAdvanced || true
        ;;
    4)
        runRealityScannerSameAsnPrefixes || true
        ;;
    5)
        if selectRealityTargetFromScanResults; then
            autoConfirm reality_target_confirm "确认切换到 ${realityTargetHost}:${realityTargetPort}，SNI=${realitySNI}？" n sniInput
            if [[ "${sniInput}" == "y" ]]; then
                changeInstalledRealityTarget "${realityTargetHost}:${realityTargetPort}" "${realitySNI}"
            fi
        fi
        ;;
    6)
        autoRead reality_target "请输入REALITY伪装目标 host[:port]:" targetInput
        [[ -n "${targetInput}" ]] || return 1
        autoRead reality_server_name "请输入SNI[回车默认等于目标 host]:" sniInput
        changeInstalledRealityTarget "${targetInput}" "${sniInput}"
        ;;
    7)
        showRealityTargetBlockedCandidates
        ;;
    8)
        showRealityTargetPqcStatus
        ;;
    9)
        return 0
        ;;
    *)
        errorCard "选择错误"
        ;;
    esac
    done
}

# reality管理
regenerateRealityProfile() {
    if [[ "${coreInstallType}" == "1" ]]; then
        selectCustomInstallType=",7,"
        initXrayConfig custom 1 true || return 1
    elif [[ "${coreInstallType}" == "2" ]]; then
        if currentProtocolHas 7; then
            selectCustomInstallType=",7,"
        fi
        if currentProtocolHas 8; then
            selectCustomInstallType="${selectCustomInstallType},8,"
        fi
        initSingBoxConfig custom 1 true || return 1
    fi

    reloadCore || return 1
    subscribe false || return 1
}

manageReality() {
    readInstallProtocolType
    readConfigHostPathUUID
    readCustomPort
    readSingBoxConfig

    if ! currentProtocolHasAny 7 8 12 || [[ -z "${coreInstallType}" ]]; then
        errorCard "请先安装 Reality 协议。新人路径：主菜单 -> 安装与重装 -> 无域名 Reality，或 安装与重装 -> 自定义安装 中选择 Reality 编号"
        exit 0
    fi

    echoContent title "\n┌─ REALITY 管理 ─────────────────────────────────────"
    menuItem 1 "重新生成 Reality 参数" "更新 key、shortId 等 Reality 参数"
    menuItem 2 "目标站管理" "查看、检测或切换 Reality 伪装目标"
    menuItem 3 "配置 443 共存分流" "同机真实网站与 Reality 共用公网 443"
    menuItem 4 "查看当前分流状态" "检查 state、Nginx stream 与后端监听"
    menuItem 5 "关闭 443 共存分流" "恢复 Reality 原入口端口并清理分流配置"
    menuLine "Reality 不需要本机伪装站点；443 共存分流仅用于同机真实网站"
    menuLine "分流时只填写真实网站域名，其他 SNI 默认转给 Reality"
    menuClose
    autoRead reality_manage_menu "请选择:" selectRealityManageType

    case "${selectRealityManageType}" in
    1)
        regenerateRealityProfile
        ;;
    2)
        manageRealityTarget
        ;;
    3)
        configureRealityStreamSplit
        ;;
    4)
        showRealityStreamSplitStatus
        ;;
    5)
        disableRealityStreamSplit
        ;;
    *)
        errorCard "选择错误"
        ;;
    esac
}


manageXHTTPConfigFile() {
    echo "${PADM_XHTTP_CONFIG_FILE:-/etc/padm/xray/conf/12_VLESS_XHTTP_inbounds.json}"
}

xhttpRangeValue() {
    local jqPath=$1
    local configFile
    configFile=$(manageXHTTPConfigFile)
    jq -r "${jqPath} // 0 | if type == \"object\" then ((.from | tostring) + \"-\" + (.to | tostring)) else tostring end" "${configFile}" 2>/dev/null
}

xhttpSettingsSummary() {
    local configFile
    configFile=$(manageXHTTPConfigFile)
    if [[ ! -f "${configFile}" ]]; then
        menuLine "当前状态：未检测到 VLESS Reality XHTTP 配置"
        return 0
    fi
    local mode maxConcurrency hMaxRequestTimes hMaxReusableSecs host path port sni xPaddingBytes noGRPCHeader noSSEHeader downloadAddress
    mode=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.mode // "auto"' "${configFile}" 2>/dev/null)
    host=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.host // ""' "${configFile}" 2>/dev/null)
    path=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.path // ""' "${configFile}" 2>/dev/null)
    port=$(jq -r '.inbounds[0].port // ""' "${configFile}" 2>/dev/null)
    sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // ""' "${configFile}" 2>/dev/null)
    maxConcurrency=$(xhttpRangeValue '.inbounds[0].streamSettings.xhttpSettings.xmux.maxConcurrency')
    hMaxRequestTimes=$(xhttpRangeValue '.inbounds[0].streamSettings.xhttpSettings.xmux.hMaxRequestTimes')
    hMaxReusableSecs=$(xhttpRangeValue '.inbounds[0].streamSettings.xhttpSettings.xmux.hMaxReusableSecs')
    xPaddingBytes=$(xhttpRangeValue '.inbounds[0].streamSettings.xhttpSettings.xPaddingBytes')
    noGRPCHeader=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.noGRPCHeader // false' "${configFile}" 2>/dev/null)
    noSSEHeader=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.noSSEHeader // false' "${configFile}" 2>/dev/null)
    downloadAddress=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.address // empty' "${configFile}" 2>/dev/null)
    menuLine "当前配置：端口=${port}；mode=${mode}；Reality SNI=${sni}"
    menuLine "XHTTP：host=${host}；path=${path}"
    menuLine "XMUX：maxConcurrency=${maxConcurrency}；hMaxRequestTimes=${hMaxRequestTimes}；hMaxReusableSecs=${hMaxReusableSecs}"
    menuLine "高级：xPaddingBytes=${xPaddingBytes}；noGRPCHeader=${noGRPCHeader}；noSSEHeader=${noSSEHeader}"
    if [[ -n "${downloadAddress}" ]]; then
        menuLine "上下行分离：已配置下行 address=${downloadAddress}"
    else
        menuLine "上下行分离：未启用"
    fi
}

refreshXHTTPSubscriptions() {
    readNginxSubscribe
    if [[ -n "${subscribePort}" || -f "${nginxConfigPath}subscribe.conf" ]]; then
        if ! subscribe renew >/dev/null; then
            errorCard "刷新 XHTTP 公网订阅失败"
            return 1
        fi
        successCard "已刷新公网订阅"
    else
        refreshLocalSubscriptions "XHTTP" "已刷新本地订阅" || return 1
    fi
}

configTransactionCommit() {
    local configFile=$1
    local backupFile=$2
    local validateFn=$3
    local failureTitle=$4
    local rollbackMessage=$5
    local successMessage=$6
    local refreshFn=$7
    local reloadFn=${8:-reloadCore}

    cp "${configFile}" "${backupFile}" || return 1
    mv "${configFile}.tmp" "${configFile}" || { rm -f "${backupFile}" "${configFile}.tmp"; return 1; }
    if ! "${validateFn}"; then
        if mv "${backupFile}" "${configFile}"; then
            rm -f "${backupFile}" "${configFile}.tmp"
            "${validateFn}" >/dev/null 2>&1 || true
            echoContent title "\n┌─ ${failureTitle} ────────────────────────────────"
            menuLine "${rollbackMessage}"
            menuClose
        else
            rm -f "${configFile}.tmp"
            echoContent title "\n┌─ ${failureTitle} ────────────────────────────────"
            menuLine "配置校验失败，且回滚配置失败，请手动检查 ${configFile} 和 ${backupFile}"
            menuClose
        fi
        return 1
    fi
    if ! "${reloadFn}"; then
        if mv "${backupFile}" "${configFile}"; then
            rm -f "${configFile}.tmp"
            echoContent title "\n┌─ 核心重载失败 ────────────────────────────────"
            if "${reloadFn}" >/dev/null 2>&1; then
                menuLine "已回滚本次修改"
            else
                menuLine "已回滚本次修改；恢复旧配置后重载仍失败，请检查核心服务日志"
            fi
            menuClose
        else
            echoContent title "\n┌─ 核心重载失败 ────────────────────────────────"
            menuLine "核心重载失败，且回滚配置失败，请手动检查 ${configFile} 和 ${backupFile}"
            menuClose
        fi
        return 1
    fi
    rm -f "${backupFile}"
    if ! "${refreshFn}"; then
        echoContent title "\n┌─ 订阅刷新失败 ────────────────────────────────"
        menuLine "核心配置已更新，但订阅刷新失败，请手动刷新订阅"
        menuClose
        return 1
    fi
    successCard "${successMessage}"
}

validateXHTTPConfigUpdate() {
    [[ -x /etc/padm/xray/xray ]] || return 0
    /etc/padm/xray/xray -test -confdir /etc/padm/xray/conf >"$(xhttpConfigTestLog)" 2>&1
}

xhttpConfigTestLog() {
    local tmpBase="${TMPDIR:-/tmp}"
    printf '%s\n' "${tmpBase%/}/padm-xhttp-test.log"
}

commitXHTTPConfigUpdate() {
    local successMessage=$1
    local configFile backupFile
    configFile=$(manageXHTTPConfigFile)
    if [[ "${coreInstallType}" != "1" || ! -f "${configFile}" ]]; then
        errorCard "未检测到 Xray Reality XHTTP 配置，请先安装 12.VLESS Reality XHTTP"
        rm -f "${configFile}.tmp"
        return 1
    fi
    backupFile="${configFile}.xhttp.bak"
    configTransactionCommit "${configFile}" "${backupFile}" validateXHTTPConfigUpdate "XHTTP 配置校验失败" "已回滚本次 XHTTP 修改；排查日志：$(xhttpConfigTestLog)" "${successMessage}" refreshXHTTPSubscriptions
}

applyXHTTPConfigUpdate() {
    local jqFilter=$1
    local successMessage=$2
    local configFile
    configFile=$(manageXHTTPConfigFile)
    if ! jq "${jqFilter}" "${configFile}" >"${configFile}.tmp"; then
        errorCard "写入 XHTTP 配置失败，已取消"
        rm -f "${configFile}.tmp"
        return 1
    fi
    commitXHTTPConfigUpdate "${successMessage}"
}

setXHTTPMode() {
    local mode=$1
    applyXHTTPConfigUpdate ".inbounds[0].streamSettings.xhttpSettings.mode = \"${mode}\"" "XHTTP mode 已切换为 ${mode}"
}

setXHTTPPreset() {
    local preset=$1
    case "${preset}" in
    daily)
        applyXHTTPConfigUpdate '.inbounds[0].streamSettings.xhttpSettings.mode = "auto" | .inbounds[0].streamSettings.xhttpSettings.xmux = {"maxConcurrency":"16-32","hMaxRequestTimes":"600-900","hMaxReusableSecs":"1800-3000"}' "已应用 XHTTP 日常/CDN 推荐预设"
        ;;
    compatible)
        applyXHTTPConfigUpdate '.inbounds[0].streamSettings.xhttpSettings.mode = "packet-up" | .inbounds[0].streamSettings.xhttpSettings.xmux = {"maxConcurrency":"16-32","hMaxRequestTimes":"600-900","hMaxReusableSecs":"1800-3000"}' "已应用 XHTTP 兼容优先预设"
        ;;
    stream)
        applyXHTTPConfigUpdate '.inbounds[0].streamSettings.xhttpSettings.mode = "stream-up" | .inbounds[0].streamSettings.xhttpSettings.xmux = {"maxConcurrency":"16-32","hMaxRequestTimes":"600-900","hMaxReusableSecs":"1800-3000"}' "已应用 XHTTP stream-up 性能预设"
        ;;
    single)
        applyXHTTPConfigUpdate '.inbounds[0].streamSettings.xhttpSettings.mode = "auto" | .inbounds[0].streamSettings.xhttpSettings.xmux = {"maxConcurrency":1,"hMaxRequestTimes":"600-900","hMaxReusableSecs":"1800-3000"}' "已应用 XHTTP 测速/单并发预设"
        ;;
    esac
}

setXHTTPRecommendedDefaults() {
    applyXHTTPConfigUpdate '.inbounds[0].streamSettings.xhttpSettings.mode = "auto" | .inbounds[0].streamSettings.xhttpSettings.xmux = {"maxConcurrency":"16-32","hMaxRequestTimes":"600-900","hMaxReusableSecs":"1800-3000"} | .inbounds[0].streamSettings.xhttpSettings.xPaddingBytes = "100-1000" | .inbounds[0].streamSettings.xhttpSettings.noGRPCHeader = false | .inbounds[0].streamSettings.xhttpSettings.noSSEHeader = false | .inbounds[0].streamSettings.xhttpSettings.scMaxEachPostBytes = 1000000 | .inbounds[0].streamSettings.xhttpSettings.scMinPostsIntervalMs = 30 | .inbounds[0].streamSettings.xhttpSettings.scMaxBufferedPosts = 30 | .inbounds[0].streamSettings.xhttpSettings.scStreamUpServerSecs = "20-80"' "XHTTP 已恢复推荐默认值"
}

readXHTTPRange() {
    local prompt=$1
    local defaultFrom=$2
    local defaultTo=$3
    local input from to
    autoRead xhttp_range "${prompt}[回车默认 ${defaultFrom}-${defaultTo}]:" input
    input=${input:-${defaultFrom}-${defaultTo}}
    if [[ "${input}" =~ ^[0-9]+$ ]]; then
        from=${input}
        to=${input}
    elif [[ "${input}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        from=${BASH_REMATCH[1]}
        to=${BASH_REMATCH[2]}
    else
        errorCard "范围格式错误，应为数字或 from-to"
        return 1
    fi
    if ((from < 0 || to < from)); then
        errorCard "范围不合法"
        return 1
    fi
    printf '%s %s' "${from}" "${to}"
}

setXHTTPCustomXmux() {
    local concurrency requestTimes reusableSecs concurrencyFrom concurrencyTo requestFrom requestTo reusableFrom reusableTo configFile
    concurrency=$(readXHTTPRange "请输入 maxConcurrency 范围" 16 32) || return 1
    requestTimes=$(readXHTTPRange "请输入 hMaxRequestTimes 范围" 600 900) || return 1
    reusableSecs=$(readXHTTPRange "请输入 hMaxReusableSecs 范围" 1800 3000) || return 1
    read -r concurrencyFrom concurrencyTo <<<"${concurrency}"
    read -r requestFrom requestTo <<<"${requestTimes}"
    read -r reusableFrom reusableTo <<<"${reusableSecs}"
    if ((concurrencyFrom < 1)); then
        errorCard "maxConcurrency 必须大于 0"
        return 1
    fi
    if ((requestTo > 1000)); then
        echoContent title "\n┌─ XHTTP XMUX 提醒 ──────────────────────────────────"
        menuLine "hMaxRequestTimes 超过 1000 可能触发部分 Nginx/CDN 限制"
        menuClose
    fi
    if ((reusableTo > 3600)); then
        echoContent title "\n┌─ XHTTP XMUX 提醒 ──────────────────────────────────"
        menuLine "hMaxReusableSecs 超过 3600 可能触发部分中间盒旧连接清理"
        menuClose
    fi
    configFile=$(manageXHTTPConfigFile)
    if ! jq --arg concurrency "${concurrencyFrom}-${concurrencyTo}" --arg requestTimes "${requestFrom}-${requestTo}" --arg reusableSecs "${reusableFrom}-${reusableTo}" '.inbounds[0].streamSettings.xhttpSettings.xmux = {"maxConcurrency":$concurrency,"hMaxRequestTimes":$requestTimes,"hMaxReusableSecs":$reusableSecs}' "${configFile}" >"${configFile}.tmp"; then
        errorCard "写入 XHTTP XMUX 失败"
        return 1
    fi
    commitXHTTPConfigUpdate "XHTTP XMUX 自定义范围已应用"
}

setXHTTPPathHost() {
    local configFile currentPath currentHost newPath newHost
    configFile=$(manageXHTTPConfigFile)
    currentPath=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.path // ""' "${configFile}" 2>/dev/null)
    currentHost=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.host // ""' "${configFile}" 2>/dev/null)
    autoRead xhttp_path "请输入 XHTTP path，[回车保持 ${currentPath}]:" newPath
    newPath=${newPath:-${currentPath}}
    if [[ ! "${newPath}" =~ ^/[^[:space:]]*$ ]]; then
        errorCard "path 必须以 / 开头且不能包含空格"
        return 1
    fi
    autoRead xhttp_host "请输入 XHTTP host，[回车保持 ${currentHost}]:" newHost
    newHost=${newHost:-${currentHost}}
    if [[ -z "${newHost}" || "${newHost}" =~ [[:space:]/] ]]; then
        errorCard "host 不能为空，且不能包含空格或 /"
        return 1
    fi
    echoContent title "\n┌─ XHTTP path/host 提醒 ─────────────────────────────"
    menuLine "通常建议 host 与 Reality SNI 保持一致"
    menuLine "仅 CDN 域前置或特殊反代场景才需要改"
    menuClose
    if ! jq --arg path "${newPath}" --arg host "${newHost}" '.inbounds[0].streamSettings.xhttpSettings.path = $path | .inbounds[0].streamSettings.xhttpSettings.host = $host' "${configFile}" >"${configFile}.tmp"; then
        errorCard "写入 XHTTP path/host 失败"
        return 1
    fi
    commitXHTTPConfigUpdate "XHTTP path/host 已更新"
}

setXHTTPAdvancedParams() {
    local configFile padding maxPost minInterval maxBuffered streamSecs noGrpc noSse pf pt sf st
    configFile=$(manageXHTTPConfigFile)
    padding=$(readXHTTPRange "请输入 xPaddingBytes 范围" 100 1000) || return 1
    read -r pf pt <<<"${padding}"
    autoRead xhttp_max_post_bytes "请输入 packet-up 单个 POST 最大字节数[回车默认 1000000]:" maxPost
    maxPost=${maxPost:-1000000}
    autoRead xhttp_min_posts_interval "请输入 packet-up 客户端 POST 最小间隔毫秒[回车默认 30]:" minInterval
    minInterval=${minInterval:-30}
    autoRead xhttp_max_buffered_posts "请输入 packet-up 服务端最多缓存 POST 数[回车默认 30]:" maxBuffered
    maxBuffered=${maxBuffered:-30}
    streamSecs=$(readXHTTPRange "请输入 stream-up 服务端保活秒数范围" 20 80) || return 1
    read -r sf st <<<"${streamSecs}"
    autoRead xhttp_disable_grpc_header "是否关闭 gRPC header 伪装？[y/n，默认 n]:" noGrpc
    autoRead xhttp_disable_sse_header "是否关闭 SSE response header？[y/n，默认 n]:" noSse
    [[ "${maxPost}" =~ ^[0-9]+$ && "${minInterval}" =~ ^[0-9]+$ && "${maxBuffered}" =~ ^[0-9]+$ ]] || {
        errorCard "数值参数必须是非负整数"
        return 1
    }
    if ! jq --arg padding "${pf}-${pt}" --argjson maxPost "${maxPost}" --argjson minInterval "${minInterval}" --argjson maxBuffered "${maxBuffered}" --arg streamSecs "${sf}-${st}" --argjson noGrpc "$([[ "${noGrpc}" == "y" ]] && echo true || echo false)" --argjson noSse "$([[ "${noSse}" == "y" ]] && echo true || echo false)" '.inbounds[0].streamSettings.xhttpSettings.xPaddingBytes = $padding | .inbounds[0].streamSettings.xhttpSettings.scMaxEachPostBytes = $maxPost | .inbounds[0].streamSettings.xhttpSettings.scMinPostsIntervalMs = $minInterval | .inbounds[0].streamSettings.xhttpSettings.scMaxBufferedPosts = $maxBuffered | .inbounds[0].streamSettings.xhttpSettings.scStreamUpServerSecs = $streamSecs | .inbounds[0].streamSettings.xhttpSettings.noGRPCHeader = $noGrpc | .inbounds[0].streamSettings.xhttpSettings.noSSEHeader = $noSse' "${configFile}" >"${configFile}.tmp"; then
        errorCard "写入 XHTTP 高级参数失败"
        return 1
    fi
    commitXHTTPConfigUpdate "XHTTP 高级参数已更新"
}

setXHTTPDownloadSettings() {
    local configFile address port security serverName host path alpn mode publicKey shortId
    configFile=$(manageXHTTPConfigFile)
    echoContent title "\n┌─ XHTTP 上下行分离风险 ─────────────────────────────"
    menuLine "上下行分离属于高级功能"
    menuLine "下行配置完全独立，填错会导致连接失败"
    menuClose
    autoRead xhttp_download_address "请输入下行入口 address/IP/域名:" address
    [[ -n "${address}" && ! "${address}" =~ [[:space:]/] ]] || { errorCard "address 不合法"; return 1; }
    autoRead xhttp_download_port "请输入下行入口端口[回车默认 443]:" port
    port=${port:-443}
    [[ "${port}" =~ ^[0-9]+$ && "${port}" -ge 1 && "${port}" -le 65535 ]] || { errorCard "端口不合法"; return 1; }
    autoRead xhttp_download_security "请输入下行 security[tls/reality，回车默认 tls]:" security
    security=${security:-tls}
    [[ "${security}" == "tls" || "${security}" == "reality" ]] || { errorCard "security 仅支持 tls 或 reality"; return 1; }
    autoRead xhttp_download_server_name "请输入下行 serverName/SNI[回车默认当前 Reality SNI]:" serverName
    serverName=${serverName:-$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // ""' "${configFile}" 2>/dev/null)}
    autoRead xhttp_download_host "请输入下行 XHTTP host[回车默认 ${serverName}]:" host
    host=${host:-${serverName}}
    autoRead xhttp_download_path "请输入下行 XHTTP path[回车默认沿用当前 path]:" path
    path=${path:-$(jq -r '.inbounds[0].streamSettings.xhttpSettings.path // ""' "${configFile}" 2>/dev/null)}
    autoRead xhttp_download_alpn "请输入下行 ALPN[h2/h3，回车默认 h3]:" alpn
    alpn=${alpn:-h3}
    [[ "${alpn}" == "h2" || "${alpn}" == "h3" ]] || { errorCard "ALPN 仅支持 h2 或 h3"; return 1; }
    autoRead xhttp_download_mode "请输入下行 mode[auto/stream-one/packet-up/stream-up，回车默认 auto]:" mode
    mode=${mode:-auto}
    [[ "${mode}" == "auto" || "${mode}" == "stream-one" || "${mode}" == "packet-up" || "${mode}" == "stream-up" ]] || { errorCard "mode 不合法"; return 1; }
    publicKey=$(jq -r '.inbounds[0].streamSettings.realitySettings.publicKey // ""' "${configFile}" 2>/dev/null)
    shortId=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[1] // .inbounds[0].streamSettings.realitySettings.shortIds[0] // ""' "${configFile}" 2>/dev/null)
    if [[ "${security}" == "reality" && -z "${publicKey}" ]]; then
        errorCard "下行 Reality 需要 publicKey；当前配置未找到，请先确认 Reality 密钥"
        return 1
    fi
    if ! jq --arg address "${address}" --argjson port "${port}" --arg security "${security}" --arg serverName "${serverName}" --arg host "${host}" --arg path "${path}" --arg alpn "${alpn}" --arg mode "${mode}" --arg publicKey "${publicKey}" --arg shortId "${shortId}" '.inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings = {"address":$address,"port":$port,"network":"xhttp","security":$security,"xhttpSettings":{"host":$host,"path":$path,"mode":$mode}} | if $security == "reality" then .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.realitySettings = {"serverName":$serverName,"fingerprint":"chrome","show":false,"publicKey":$publicKey,"shortId":$shortId,"spiderX":"/"} else .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.tlsSettings = {"serverName":$serverName,"alpn":[$alpn],"fingerprint":"chrome"} end' "${configFile}" >"${configFile}.tmp"; then
        errorCard "写入 XHTTP 上下行分离配置失败"
        return 1
    fi
    commitXHTTPConfigUpdate "XHTTP 上下行分离配置已启用"
}

disableXHTTPDownloadSettings() {
    applyXHTTPConfigUpdate 'del(.inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings) | if .inbounds[0].streamSettings.xhttpSettings.extra == {} then del(.inbounds[0].streamSettings.xhttpSettings.extra) else . end' "XHTTP 上下行分离配置已关闭"
}

manageXHTTPPresets() {
    echoContent title "\n┌─ XHTTP 场景预设 ───────────────────────────────────"
    menuRecommendedItem 1 "日常/CDN 推荐" "auto + XMUX 16-32"
    menuItem 2 "兼容优先" "packet-up，适合未知 CDN/反代"
    menuItem 3 "性能优先" "stream-up，适合 H2/gRPC 兼容链路"
    menuItem 4 "测速/单并发" "auto + maxConcurrency=1"
    menuReturnItem 5 "返回" "回到 XHTTP 管理"
    menuClose
    autoRead xhttp_preset_menu "请选择:" selectXHTTPPreset
    case "${selectXHTTPPreset}" in
    1) setXHTTPPreset daily ;;
    2) setXHTTPPreset compatible ;;
    3) setXHTTPPreset stream ;;
    4) setXHTTPPreset single ;;
    5) manageXHTTP ;;
    *) errorCard "选择错误，请重新选择"; manageXHTTPPresets ;;
    esac
}

manageXHTTPMode() {
    echoContent title "\n┌─ XHTTP mode 设置 ──────────────────────────────────"
    menuRecommendedItem 1 "auto" "推荐默认，由 Xray 自动选择"
    menuItem 2 "packet-up" "兼容性最强"
    menuItem 3 "stream-up" "流式上行，效率更高"
    menuReturnItem 4 "返回" "回到 XHTTP 管理"
    menuClose
    autoRead xhttp_mode_menu "请选择:" selectXHTTPMode
    case "${selectXHTTPMode}" in
    1) setXHTTPMode auto ;;
    2) setXHTTPMode packet-up ;;
    3) setXHTTPMode stream-up ;;
    4) manageXHTTP ;;
    *) errorCard "选择错误，请重新选择"; manageXHTTPMode ;;
    esac
}

manageXHTTPXmux() {
    echoContent title "\n┌─ XHTTP XMUX 设置 ──────────────────────────────────"
    menuItem 1 "日常随机复用" "maxConcurrency 16-32"
    menuItem 2 "单并发" "maxConcurrency 1，测速/排障"
    menuItem 3 "自定义范围" "自定义 maxConcurrency/request/time"
    menuReturnItem 4 "返回" "回到 XHTTP 管理"
    menuClose
    autoRead xhttp_xmux_menu "请选择:" selectXHTTPXmux
    case "${selectXHTTPXmux}" in
    1) setXHTTPPreset daily ;;
    2) setXHTTPPreset single ;;
    3) setXHTTPCustomXmux ;;
    4) manageXHTTP ;;
    *) errorCard "选择错误，请重新选择"; manageXHTTPXmux ;;
    esac
}

manageXHTTPNormal() {
    echoContent title "\n┌─ XHTTP 普通设置 ───────────────────────────────────"
    menuLine "普通设置面向日常/CDN 使用，优先选择场景预设"
    menuItem 1 "查看当前配置" "显示 mode、path、host、XMUX 与高级状态"
    menuItem 2 "场景预设" "日常、兼容、性能、测速"
    menuItem 3 "mode 设置" "auto / packet-up / stream-up"
    menuItem 4 "CDN / H3 使用说明" "查看 Cloudflare、H3 和兼容性提示"
    menuReturnItem 5 "返回 XHTTP 管理" "回到上级菜单"
    menuClose
    autoRead xhttp_normal_menu "请选择:" selectXHTTPNormal
    case "${selectXHTTPNormal}" in
    1)
        xhttpSettingsSummary
        ;;
    2)
        manageXHTTPPresets
        ;;
    3)
        manageXHTTPMode
        ;;
    4)
        showXHTTPUsageNotes
        ;;
    5)
        manageXHTTP
        ;;
    *)
        errorCard "选择错误，请重新选择"
        manageXHTTPNormal
        ;;
    esac
}

manageXHTTPAdvanced() {
    echoContent title "\n┌─ XHTTP 高级设置 ───────────────────────────────────"
    menuLine "高级设置会改变复用、path/host 或 packet/stream 细节"
    menuItem 1 "XMUX 设置" "日常、单并发或自定义范围"
    menuItem 2 "path / host 设置" "CDN 域前置或特殊反代场景"
    menuItem 3 "header / packet / stream 参数" "xPadding、sc*、gRPC/SSE header"
    menuRecommendedItem 4 "恢复推荐默认值" "恢复 mode、XMUX 与高级推荐值"
    menuReturnItem 5 "返回 XHTTP 管理" "回到上级菜单"
    menuClose
    autoRead xhttp_advanced_menu "请选择:" selectXHTTPAdvanced
    case "${selectXHTTPAdvanced}" in
    1)
        manageXHTTPXmux
        ;;
    2)
        setXHTTPPathHost
        ;;
    3)
        setXHTTPAdvancedParams
        ;;
    4)
        setXHTTPRecommendedDefaults
        ;;
    5)
        manageXHTTP
        ;;
    *)
        errorCard "选择错误，请重新选择"
        manageXHTTPAdvanced
        ;;
    esac
}

manageXHTTPExperiment() {
    echoContent title "\n┌─ XHTTP 实验功能 ───────────────────────────────────"
    menuLine "实验功能依赖客户端、CDN 和反代行为；填错会导致连接失败"
    menuDangerItem 1 "启用上下行分离" "配置独立下行 downloadSettings"
    menuItem 2 "关闭上下行分离" "删除 downloadSettings"
    menuReturnItem 3 "返回 XHTTP 管理" "回到上级菜单"
    menuClose
    autoRead xhttp_experiment_menu "请选择:" selectXHTTPExperiment
    case "${selectXHTTPExperiment}" in
    1)
        setXHTTPDownloadSettings
        ;;
    2)
        disableXHTTPDownloadSettings
        ;;
    3)
        manageXHTTP
        ;;
    *)
        errorCard "选择错误，请重新选择"
        manageXHTTPExperiment
        ;;
    esac
}

showXHTTPUsageNotes() {
    echoContent title "\n┌─ XHTTP 使用说明 ───────────────────────────────────"
    menuLine "1. 默认日常推荐：mode=auto，XMUX maxConcurrency=16-32"
    menuLine "2. 未知 CDN/反代不通时，优先尝试 packet-up"
    menuLine "3. Cloudflare 走 stream-up/H2 时，需确认 CF 面板开启 gRPC"
    menuLine "4. H3/QUIC 需要客户端、CDN 与 UDP 路径同时支持；订阅默认仍偏 H2 兼容"
    menuLine "5. 上下行分离适合上行/下行走不同入口或线路，属于高级功能"
    menuClose
}

manageXHTTP() {
    readInstallType
    readInstallProtocolType
    if [[ "${coreInstallType}" != "1" ]] || ! currentProtocolHas 12; then
        errorCard "请先安装 Xray 的 12.VLESS Reality XHTTP"
        return 1
    fi

    echoContent title "\n┌─ XHTTP 管理 ───────────────────────────────────────"
    menuLine "这里只调整 XHTTP 协议参数；CDN 连接地址在 协议与入口 -> CDN 入口管理"
    menuLine "普通设置优先；高级和实验功能适合明确知道客户端与线路能力时使用"
    xhttpSettingsSummary
    menuItem 1 "普通设置" "状态、场景预设、mode 与使用说明"
    menuItem 2 "高级设置" "XMUX、path/host、header/packet/stream 参数"
    menuDangerItem 3 "实验功能" "上下行分离等高风险能力"
    menuRecommendedItem 4 "恢复推荐默认值" "恢复 mode、XMUX 与高级推荐值"
    menuReturnItem 5 "返回协议与入口" "回到上级菜单"
    menuClose
    autoRead xhttp_manage_menu "请选择:" selectXHTTPManageType

    case "${selectXHTTPManageType}" in
    1)
        manageXHTTPNormal
        ;;
    2)
        manageXHTTPAdvanced
        ;;
    3)
        manageXHTTPExperiment
        ;;
    4)
        setXHTTPRecommendedDefaults
        ;;
    5)
        protocolEntryMenu
        ;;
    *)
        errorCard "选择错误，请重新选择"
        manageXHTTP
        ;;
    esac
}


# hysteria管理
manageHysteria() {
    echoContent title "\n┌─ Hysteria2 管理 ───────────────────────────────────"
    local hysteria2Status=
    if [[ -n "${singBoxConfigPath}" ]] && [[ -f "/etc/padm/sing-box/conf/config/06_hysteria2_inbounds.json" ]]; then
        menuLine "依赖 sing-box 内核；适合 UDP、移动网络场景"
        menuItem 1 "重新安装" "重建 Hysteria2 入站配置"
        menuItem 2 "卸载" "移除 Hysteria2 入站配置"
        menuItem 3 "端口跳跃管理" "配置 UDP 端口跳跃转发"
        menuReturnItem 4 "返回协议与入口" "回到上级菜单"
        hysteria2Status=true
    else
        menuLine "依赖 sing-box 内核；适合 UDP、移动网络场景"
        menuItem 1 "安装" "新增 Hysteria2 入站配置"
        menuReturnItem 2 "返回协议与入口" "回到上级菜单"
    fi

    menuClose
    autoRead hysteria_menu "请选择:" installHysteria2Status
    if [[ "${installHysteria2Status}" == "1" ]]; then
        singBoxHysteria2Install
    elif [[ "${installHysteria2Status}" == "2" && "${hysteria2Status}" == "true" ]]; then
        unInstallSingBox hysteria2
    elif [[ "${installHysteria2Status}" == "3" && "${hysteria2Status}" == "true" ]]; then
        portHoppingMenu hysteria2
    elif [[ ( "${installHysteria2Status}" == "4" && "${hysteria2Status}" == "true" ) || ( "${installHysteria2Status}" == "2" && "${hysteria2Status}" != "true" ) ]]; then
        protocolEntryMenu
    else
        errorCard "选择错误，请重新选择"
        manageHysteria
    fi
}


# TUIC 管理
tuicConfigFile() {
    echo "/etc/padm/sing-box/conf/config/09_tuic_inbounds.json"
}

tuicSettingsSummary() {
    local configFile algorithm authTimeout heartbeat zeroRtt port userCount
    configFile=$(tuicConfigFile)
    if [[ ! -f "${configFile}" ]]; then
        menuLine "当前状态：未检测到 Tuic 配置"
        return 0
    fi
    port=$(jq -r '.inbounds[0].listen_port // ""' "${configFile}" 2>/dev/null)
    algorithm=$(jq -r '.inbounds[0].congestion_control // "cubic"' "${configFile}" 2>/dev/null)
    authTimeout=$(jq -r '.inbounds[0].auth_timeout // "3s"' "${configFile}" 2>/dev/null)
    heartbeat=$(jq -r '.inbounds[0].heartbeat // "10s"' "${configFile}" 2>/dev/null)
    zeroRtt=$(jq -r '.inbounds[0].zero_rtt_handshake // false' "${configFile}" 2>/dev/null)
    userCount=$(jq -r '.inbounds[0].users | length' "${configFile}" 2>/dev/null)
    menuLine "监听端口：${port}"
    menuLine "拥塞控制：${algorithm}"
    menuLine "连接参数：auth_timeout=${authTimeout}；heartbeat=${heartbeat}"
    menuLine "0-RTT：${zeroRtt}（默认关闭，开启会增加重放风险）"
    menuLine "用户数量：${userCount}"
}

refreshTuicSubscriptions() {
    readNginxSubscribe
    if [[ -n "${subscribePort}" || -f "${nginxConfigPath}subscribe.conf" ]]; then
        if ! subscribe renew >/dev/null; then
            errorCard "刷新 Tuic 公网订阅失败"
            return 1
        fi
        successCard "已刷新公网订阅"
    else
        refreshLocalSubscriptions "Tuic" "已刷新本地订阅" || return 1
    fi
}

validateTuicConfigUpdate() {
    [[ -x /etc/padm/sing-box/sing-box ]] || return 0
    singBoxMergeConfigForValidation /etc/padm/sing-box/sing-box "$(tuicConfigTestLog)"
}

tuicConfigTestLog() {
    local tmpBase="${TMPDIR:-/tmp}"
    printf '%s\n' "${tmpBase%/}/padm-tuic-test.log"
}

commitTuicConfigUpdate() {
    local successMessage=$1
    local configFile backupFile
    configFile=$(tuicConfigFile)
    if [[ ! -f "${configFile}" ]]; then
        errorCard "未检测到 Tuic 配置，请先安装 Tuic"
        rm -f "${configFile}.tmp"
        return 1
    fi
    backupFile="${configFile}.tuic.bak"
    configTransactionCommit "${configFile}" "${backupFile}" validateTuicConfigUpdate "Tuic 配置校验失败" "已回滚本次 Tuic 修改；排查日志：$(tuicConfigTestLog)" "${successMessage}" refreshTuicSubscriptions
}

applyTuicConfigUpdate() {
    local jqFilter=$1
    local successMessage=$2
    local configFile
    configFile=$(tuicConfigFile)
    if ! jq "${jqFilter}" "${configFile}" >"${configFile}.tmp"; then
        errorCard "写入 Tuic 配置失败，已取消"
        rm -f "${configFile}.tmp"
        return 1
    fi
    commitTuicConfigUpdate "${successMessage}"
}

setTuicCongestionControl() {
    local algorithm=$1
    applyTuicConfigUpdate ".inbounds[0].congestion_control = \"${algorithm}\"" "Tuic 拥塞控制已切换为 ${algorithm}"
}

readTuicDuration() {
    local prompt=$1
    local defaultValue=$2
    local input
    autoRead tuic_duration "${prompt}[回车默认 ${defaultValue}]：" input
    input=${input:-${defaultValue}}
    if [[ ! "${input}" =~ ^[0-9]+(ms|s|m|h)$ ]]; then
        errorCard "时间格式错误，应为 300ms、3s、10s、1m 这类格式"
        return 1
    fi
    printf '%s' "${input}"
}

setTuicConnectionParams() {
    local authTimeout heartbeat configFile
    authTimeout=$(readTuicDuration "请输入认证超时时间 auth_timeout" "3s") || return 1
    heartbeat=$(readTuicDuration "请输入心跳间隔 heartbeat" "10s") || return 1
    configFile=$(tuicConfigFile)
    if ! jq --arg authTimeout "${authTimeout}" --arg heartbeat "${heartbeat}" '.inbounds[0].auth_timeout = $authTimeout | .inbounds[0].heartbeat = $heartbeat' "${configFile}" >"${configFile}.tmp"; then
        errorCard "写入 Tuic 连接参数失败"
        rm -f "${configFile}.tmp"
        return 1
    fi
    commitTuicConfigUpdate "Tuic 连接参数已更新"
}

setTuicZeroRtt() {
    local enabled=$1
    if [[ "${enabled}" == "true" ]]; then
        warnCard \
            "0-RTT 可以减少握手往返，但上游文档明确提示存在重放攻击风险" \
            "除非你清楚客户端兼容性和风险边界，否则建议保持关闭"
        autoConfirm tuic_zero_rtt_confirm "确认启用 Tuic 0-RTT？" n confirmZeroRtt
        [[ "${confirmZeroRtt}" == "y" ]] || return 0
    fi
    applyTuicConfigUpdate ".inbounds[0].zero_rtt_handshake = ${enabled}" "Tuic 0-RTT 已设置为 ${enabled}"
}

setTuicRecommendedDefaults() {
    applyTuicConfigUpdate '.inbounds[0].congestion_control = "cubic" | .inbounds[0].auth_timeout = "3s" | .inbounds[0].heartbeat = "10s" | .inbounds[0].zero_rtt_handshake = false' "Tuic 已恢复 sing-box 推荐默认值"
}

manageTuicCongestionControl() {
    echoContent title "\n┌─ Tuic 拥塞控制 ────────────────────────────────────"
    menuLine "sing-box 默认 cubic；bbr 可在高带宽或长距离链路手动尝试"
    menuRecommendedItem 1 "cubic" "默认推荐"
    menuItem 2 "bbr" "高带宽/长距离链路可试"
    menuItem 3 "new_reno" "兼容保守"
    menuReturnItem 4 "返回" "回到 Tuic 管理"
    menuClose
    autoRead tuic_congestion_menu "请选择:" selectTuicCongestion
    case "${selectTuicCongestion}" in
    1) setTuicCongestionControl cubic ;;
    2) setTuicCongestionControl bbr ;;
    3) setTuicCongestionControl new_reno ;;
    4) manageTuic ;;
    *) errorCard "选择错误，请重新选择"; manageTuicCongestionControl ;;
    esac
}

manageTuicAdvanced() {
    echoContent title "\n┌─ Tuic 高级设置 ────────────────────────────────────"
    menuLine "高级参数直接写入 sing-box Tuic inbound，写入后会 merge 校验并 reload"
    menuItem 1 "连接参数" "设置 auth_timeout 与 heartbeat"
    menuDangerItem 2 "启用 0-RTT" "减少握手但增加重放风险"
    menuRecommendedItem 3 "关闭 0-RTT" "恢复上游推荐的安全默认值"
    menuRecommendedItem 4 "恢复推荐默认值" "cubic、3s、10s、0-RTT 关闭"
    menuReturnItem 5 "返回 Tuic 管理" "回到上级菜单"
    menuClose
    autoRead tuic_advanced_menu "请选择:" selectTuicAdvanced
    case "${selectTuicAdvanced}" in
    1) setTuicConnectionParams ;;
    2) setTuicZeroRtt true ;;
    3) setTuicZeroRtt false ;;
    4) setTuicRecommendedDefaults ;;
    5) manageTuic ;;
    *) errorCard "选择错误，请重新选择"; manageTuicAdvanced ;;
    esac
}

manageTuic() {
    echoContent title "\n┌─ Tuic 管理 ────────────────────────────────────────"
    local tuicStatus=
    if [[ -n "${singBoxConfigPath}" ]] && [[ -f "/etc/padm/sing-box/conf/config/09_tuic_inbounds.json" ]]; then
        menuLine "依赖 sing-box 内核；适合 UDP、移动网络或 QUIC/HTTP3 客户端场景"
        menuLine "不作为新人默认推荐"
        tuicSettingsSummary
        menuItem 1 "重新安装" "重建 Tuic 入站配置"
        menuItem 2 "卸载" "移除 Tuic 入站配置"
        menuItem 3 "端口跳跃管理" "配置 UDP 端口跳跃转发"
        menuItem 4 "拥塞控制" "cubic / bbr / new_reno"
        menuItem 5 "高级设置" "auth_timeout、heartbeat、0-RTT"
        menuRecommendedItem 6 "恢复推荐默认值" "cubic、3s、10s、0-RTT 关闭"
        menuReturnItem 7 "返回协议与入口" "回到上级菜单"
        tuicStatus=true
    else
        menuLine "依赖 sing-box 内核；适合 UDP、移动网络或 QUIC/HTTP3 客户端场景"
        menuLine "不作为新人默认推荐"
        menuItem 1 "安装" "新增 Tuic 入站配置"
        menuReturnItem 2 "返回协议与入口" "回到上级菜单"
    fi

    menuClose
    autoRead tuic_menu "请选择:" installTuicStatus
    if [[ "${installTuicStatus}" == "1" ]]; then
        singBoxTuicInstall
    elif [[ "${installTuicStatus}" == "2" && "${tuicStatus}" == "true" ]]; then
        unInstallSingBox tuic
    elif [[ "${installTuicStatus}" == "3" && "${tuicStatus}" == "true" ]]; then
        portHoppingMenu tuic
    elif [[ "${installTuicStatus}" == "4" && "${tuicStatus}" == "true" ]]; then
        manageTuicCongestionControl
    elif [[ "${installTuicStatus}" == "5" && "${tuicStatus}" == "true" ]]; then
        manageTuicAdvanced
    elif [[ "${installTuicStatus}" == "6" && "${tuicStatus}" == "true" ]]; then
        setTuicRecommendedDefaults
    elif [[ ( "${installTuicStatus}" == "7" && "${tuicStatus}" == "true" ) || ( "${installTuicStatus}" == "2" && "${tuicStatus}" != "true" ) ]]; then
        protocolEntryMenu
    else
        errorCard "选择错误，请重新选择"
        manageTuic
    fi
}

# 操作 Hysteria
handleHysteria() {
    # shellcheck disable=SC2010
    if find /bin /usr/bin | grep -q systemctl && ls /etc/systemd/system/ | grep -q hysteria.service; then
        if [[ -z $(pgrep -f "hysteria/hysteria") ]] && [[ "$1" == "start" ]]; then
            systemctl start hysteria.service
        elif [[ -n $(pgrep -f "hysteria/hysteria") ]] && [[ "$1" == "stop" ]]; then
            systemctl stop hysteria.service
        fi
    fi
    sleep 0.8

    if [[ "$1" == "start" ]]; then
        if [[ -n $(pgrep -f "hysteria/hysteria") ]]; then
            successCard "Hysteria启动成功"
        else
            errorCard "Hysteria启动失败"
            menuLine "$(uiStyle warn "请手动执行以下命令查看错误日志：")"
            menuLine "$(uiStyle value "/etc/padm/hysteria/hysteria --log-level debug -c /etc/padm/hysteria/conf/config.json server")"
            exit 0
        fi
    elif [[ "$1" == "stop" ]]; then
        if [[ -z $(pgrep -f "hysteria/hysteria") ]]; then
            successCard "Hysteria关闭成功"
        else
            errorCard "Hysteria关闭失败"
            menuLine "$(uiStyle warn "请手动执行以下命令清理残留进程：")"
            menuLine "$(uiStyle value "ps -ef|grep -v grep|grep hysteria|awk '{print \$2}'|xargs kill -9")"
            exit 0
        fi
    fi
}
