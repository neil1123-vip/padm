#!/usr/bin/env bash

vlessEncryptionConfigFile() {
    local xhttpConfig
    xhttpConfig="${PADM_VLESS_XHTTP_CONFIG_FILE:-${PADM_XRAY_CONF_DIR:-/etc/padm/xray/conf}/12_VLESS_XHTTP_inbounds.json}"
    if [[ -f "${xhttpConfig}" ]]; then
        echo "${xhttpConfig}"
    else
        echo "${PADM_VLESS_REALITY_CONFIG_FILE:-${PADM_XRAY_CONF_DIR:-/etc/padm/xray/conf}/07_VLESS_vision_reality_inbounds.json}"
    fi
}

validateVlessEncryptionConfig() {
    local xrayBinary
    local xrayConfigDir
    xrayBinary=$(manageXrayBinaryPath)
    xrayConfigDir=$(manageXrayConfigDir)
    "${xrayBinary}" -test -confdir "${xrayConfigDir}" >"$(padmTmpFilePath padm-xray-test.log)" 2>&1
}

manageXrayBinaryPath() {
    if declare -F coreXrayBinaryPath >/dev/null 2>&1; then
        coreXrayBinaryPath
        return
    fi
    printf '%s\n' "${PADM_XRAY_BINARY:-/etc/padm/xray/xray}"
}

manageXrayConfigDir() {
    if declare -F coreXrayConfigDir >/dev/null 2>&1; then
        coreXrayConfigDir
        return
    fi
    if [[ -n "${PADM_XRAY_CONF_DIR:-}" ]]; then
        printf '%s\n' "${PADM_XRAY_CONF_DIR%/}"
        return
    fi
    printf '%s\n' "${PADM_XRAY_DIR:-/etc/padm/xray}/conf"
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
    stateFile="${PADM_VLESS_ENCRYPTION_STATE_FILE:-/etc/padm/xray/vless_encryption.json}"
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

refreshProtocolSubscriptions() {
    local label=$1 publicSuccess=$2 localSuccess=$3
    readNginxSubscribe
    if [[ -n "${subscribePort}" || -f "${nginxConfigPath}subscribe.conf" ]]; then
        if ! refreshPublishedSubscriptions >/dev/null; then
            errorCard "刷新 ${label} 公网订阅失败"
            return 1
        fi
        successCard "${publicSuccess}"
    else
        refreshLocalSubscriptions "${label}" "${localSuccess}"
    fi
}

refreshVlessEncryptionSubscriptions() {
    refreshProtocolSubscriptions "VLESS Encryption" "已刷新公网订阅；default/Mihomo 已写入 encryption，sing-box 因上游不支持仍省略" "已刷新本地订阅；default/Mihomo 已写入 encryption，sing-box 因上游不支持仍省略"
}

restoreLocalSubscribeOutputs() {
    local localBase=$1
    local backupDir=$2
    local reason=$3
    local restoreMessage
    local previousSubscribeSalt=
    local restoreAll=${5:-false}
    local restoredMessage="已恢复旧本地订阅"
    local failedLabel="旧本地订阅"
    local restoreStatus=0

    if [[ $# -ge 4 ]]; then
        previousSubscribeSalt=$4
    fi

    if [[ "${restoreAll}" == "true" ]]; then
        restoredMessage="已恢复旧订阅输出"
        failedLabel="旧订阅输出"
        subscriptionSyncRestoreSubscribeOutputBackups "${backupDir}" || restoreStatus=1
    else
        subscriptionSyncRestoreBackupPath "${localBase}" "${backupDir}" local || restoreStatus=1
    fi
    if [[ "${restoreStatus}" -ne 0 ]]; then
        padmForgetCleanupPath "${backupDir}"
        subscriptionSyncSetSingleRestoreResultMessage restoreMessage "${reason}" false "" "${failedLabel}" "备份目录：${backupDir}" || true
        errorCard "${restoreMessage}"
        return 1
    fi
    padmRemoveCleanupPath "${backupDir}"
    if [[ $# -ge 4 ]]; then
        subscribeSalt=${previousSubscribeSalt}
    fi
    subscriptionSyncSetSingleRestoreResultMessage restoreMessage "${reason}" true "${restoredMessage}" "${failedLabel}" "备份目录：${backupDir}"
    errorCard "${restoreMessage}"
    return 1
}

refreshLocalSubscriptions() {
    local featureName=$1
    local successMessage=$2
    local localBase backupDir

    localBase=$(subscribeLocalBaseDir)
    padmCreateTmpRootPath backupDir padm-refresh-local-subscriptions.XXXXXX -d || {
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
    local restoreMessage
    local restoreFailed=false
    if ! restoreManagedFileFromBackup "${backupFile}" "${configFile}" 644; then
        coreSetDualRestoreResultMessage restoreMessage \
            "${reason}" \
            false \
            "VLESS Encryption 配置" \
            " ${configFile} 和 ${backupFile}" \
            true \
            "VLESS Encryption 状态" \
            " ${stateFile} 和 ${stateBackupFile}" || true
        errorCard "${restoreMessage}"
        return 1
    fi
    removeManagedFilesIfPresentIgnoreFailure "${backupFile}"
    if [[ "${hadStateBackup}" == "true" ]]; then
        if ! restoreManagedFileFromBackup "${stateBackupFile}" "${stateFile}" 600; then
            restoreFailed=true
        else
            removeManagedFilesIfPresentIgnoreFailure "${stateBackupFile}"
        fi
    elif [[ "${stateMode}" == "remove" ]]; then
        if ! removeManagedFileIfPresent "${stateFile}"; then
            restoreFailed=true
        fi
    fi
    if [[ "${restoreFailed}" == "true" ]]; then
        coreSetDualRestoreResultMessage restoreMessage \
            "${reason}" \
            true \
            "VLESS Encryption 配置" \
            " ${configFile} 和 ${backupFile}" \
            false \
            "VLESS Encryption 状态" \
            " ${stateFile} 和 ${stateBackupFile}" || true
        errorCard "${restoreMessage}"
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
    local configTmpFile
    local stateStageFile
    local encryption
    local decryption
    local hadStateBackup=false
    configFile=$(vlessEncryptionConfigFile)
    stateFile="${PADM_VLESS_ENCRYPTION_STATE_FILE:-/etc/padm/xray/vless_encryption.json}"
    xrayBinary="${PADM_XRAY_BINARY:-/etc/padm/xray/xray}"
    configFile=$(padmRequireSafeAbsolutePath "${configFile}") || { errorCard "VLESS Encryption 配置路径异常"; return 1; }
    stateFile=$(padmRequireSafeAbsolutePath "${stateFile}") || { errorCard "VLESS Encryption 状态路径异常"; return 1; }

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
    if ! backupManagedFileToPath "${configFile}" "${backupFile}" 644; then
        local manualCheckMessage
        coreSetManualCheckMessage manualCheckMessage "创建 VLESS Encryption 配置备份失败" " ${configFile}"
        errorCard "${manualCheckMessage}"
        return 1
    fi
    if [[ -f "${stateFile}" ]]; then
        if ! backupManagedFileToPath "${stateFile}" "${stateBackupFile}" 600; then
            removeManagedFilesIfPresentIgnoreFailure "${backupFile}"
            local manualCheckMessage
            coreSetManualCheckMessage manualCheckMessage "创建 VLESS Encryption 状态备份失败" " ${stateFile}"
            errorCard "${manualCheckMessage}"
            return 1
        fi
        hadStateBackup=true
    else
        if ! removeManagedFileIfPresent "${stateBackupFile}"; then
            removeManagedFilesIfPresentIgnoreFailure "${backupFile}"
            local manualCheckMessage
            coreSetManualCheckMessage manualCheckMessage "清理 VLESS Encryption 旧状态备份失败" " ${stateBackupFile}"
            errorCard "${manualCheckMessage}"
            return 1
        fi
    fi
    padmCreateTempFileForTarget configTmpFile "${configFile}" vlessenc || {
        if [[ "${hadStateBackup}" == "true" ]]; then
            removeManagedFilesIfPresentIgnoreFailure "${backupFile}" "${stateBackupFile}"
        else
            removeManagedFilesIfPresentIgnoreFailure "${backupFile}"
        fi
        return 1
    }

    if [[ "${mode}" == "enable" ]]; then
        xrayVersion=$("${xrayBinary}" --version | awk 'NR==1 {print $2}')
        if ! xrayVersionAtLeast "${xrayVersion}" "25.9.5"; then
            errorCard "当前 Xray-core ${xrayVersion} 不支持 vlessenc，请先升级到 v25.9.5 或更高版本"
            padmRemoveCleanupPath "${configTmpFile}"
            removeManagedFilesIfPresentIgnoreFailure "${backupFile}" "${stateBackupFile}"
            return 1
        fi
        padmCreateTmpRootPath vlessEncOut padm-vlessenc.out.XXXXXX || {
            padmRemoveCleanupPath "${configTmpFile}"
            removeManagedFilesIfPresentIgnoreFailure "${backupFile}" "${stateBackupFile}"
            return 1
        }
        padmCreateTmpRootPath vlessEncErr padm-vlessenc.err.XXXXXX || {
            padmRemoveCleanupPath "${vlessEncOut}"
            padmRemoveCleanupPath "${configTmpFile}"
            removeManagedFilesIfPresentIgnoreFailure "${backupFile}" "${stateBackupFile}"
            return 1
        }
        if ! "${xrayBinary}" vlessenc >"${vlessEncOut}" 2>"${vlessEncErr}"; then
            errorCard "xray vlessenc 执行失败，请先确认当前 Xray-core 支持该命令"
            padmRemoveCleanupPath "${vlessEncOut}"
            padmRemoveCleanupPath "${vlessEncErr}"
            padmRemoveCleanupPath "${configTmpFile}"
            removeManagedFilesIfPresentIgnoreFailure "${backupFile}" "${stateBackupFile}"
            return 1
        fi
        vlessEncOutput=$(cat "${vlessEncOut}")
        encryption=$(printf '%s\n' "${vlessEncOutput}" | extractVlessEncField encryption)
        decryption=$(printf '%s\n' "${vlessEncOutput}" | extractVlessEncField decryption)
        padmRemoveCleanupPath "${vlessEncOut}"
        padmRemoveCleanupPath "${vlessEncErr}"
        if [[ -z "${encryption}" || -z "${decryption}" ]]; then
            errorCard "无法解析 xray vlessenc 输出，已取消启用"
            padmRemoveCleanupPath "${configTmpFile}"
            removeManagedFilesIfPresentIgnoreFailure "${backupFile}" "${stateBackupFile}"
            return 1
        fi
        if ! jq --arg decryption "${decryption}" '
            if has("inbounds") and (.inbounds | length) > 1 then
                del(.inbounds[1].settings.fallbacks) | .inbounds[1].settings.decryption = $decryption
            elif .inbounds[0].streamSettings.network == "xhttp" then
                del(.inbounds[0].settings.fallbacks) | .inbounds[0].settings.decryption = $decryption | .inbounds[0].settings.clients |= map(del(.flow))
            else
                del(.inbounds[0].settings.fallbacks) | .inbounds[0].settings.decryption = $decryption | .inbounds[0].settings.clients |= map(.flow = "xtls-rprx-vision")
            end
        ' "${configFile}" >"${configTmpFile}"; then
            errorCard "写入 Xray 配置失败，已取消启用"
            restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" keep "写入 Xray 配置失败" || return 1
            padmRemoveCleanupPath "${configTmpFile}"
            return 1
        fi
        if ! padmCreateTempFileForTarget stateStageFile "${stateFile}" vlessenc-state; then
            errorCard "创建 VLESS Encryption 状态目录失败，已取消启用"
            padmRemoveCleanupPath "${configTmpFile}"
            restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" keep "创建 VLESS Encryption 状态目录失败" || return 1
            return 1
        fi
        if ! jq -n --arg encryption "${encryption}" --arg decryption "${decryption}" '{enabled:true,encryption:$encryption,decryption:$decryption}' >"${stateStageFile}"; then
            errorCard "写入 VLESS Encryption 状态失败，已取消启用"
            padmRemoveCleanupPath "${configTmpFile}"
            padmRemoveCleanupPath "${stateStageFile}"
            restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" keep "写入 VLESS Encryption 状态失败" || return 1
            return 1
        fi
    else
        if ! jq '
            if has("inbounds") and (.inbounds | length) > 1 then
                .inbounds[1].settings.decryption = "none" | del(.inbounds[1].settings.fallbacks)
            elif .inbounds[0].streamSettings.network == "xhttp" then
                .inbounds[0].settings.decryption = "none" | del(.inbounds[0].settings.fallbacks) | .inbounds[0].settings.clients |= map(del(.flow))
            else
                .inbounds[0].settings.decryption = "none" | del(.inbounds[0].settings.fallbacks)
            end
        ' "${configFile}" >"${configTmpFile}"; then
            errorCard "写入 Xray 配置失败，已取消关闭"
            padmRemoveCleanupPath "${configTmpFile}"
            restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" keep "写入 Xray 配置失败" || return 1
            return 1
        fi
    fi

    if ! commitGeneratedJsonFile "${configTmpFile}" "${configFile}"; then
        local commitFailureMessage
        coreSetPairedFileManualCheckMessage commitFailureMessage "提交 VLESS Encryption 配置失败" "${configFile}" "${backupFile}"
        errorCard "${commitFailureMessage}"
        [[ -n "${stateStageFile:-}" ]] && padmRemoveCleanupPath "${stateStageFile}"
        return 1
    fi
    if [[ "${mode}" == "enable" ]]; then
        if ! commitGeneratedJsonFile "${stateStageFile}" "${stateFile}" 600; then
            if ! restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" remove "提交 VLESS Encryption 状态失败"; then
                padmRemoveCleanupPath "${stateStageFile}"
                return 1
            fi
            padmRemoveCleanupPath "${stateStageFile}"
            local restoreMessage
            coreSetSingleRestoreResultMessage restoreMessage "提交 VLESS Encryption 状态失败" true "已恢复旧配置" "旧配置" "${stateBackupFile}"
            errorCard "${restoreMessage}"
            return 1
        fi
        chmod 600 "${stateFile}" 2>/dev/null || true
    else
        if ! removeManagedFileIfPresent "${stateFile}"; then
            if ! restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" keep "删除 VLESS Encryption 状态失败"; then
                return 1
            fi
            local restoreMessage
            coreSetSingleRestoreResultMessage restoreMessage "删除 VLESS Encryption 状态失败" true "已恢复旧配置" "旧配置" "${stateBackupFile}"
            errorCard "${restoreMessage}"
            return 1
        fi
    fi

    if ! validateVlessEncryptionConfig; then
        if ! restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" remove "$(xrayConfigValidationFailureTitle)"; then
            return 1
        fi
        echoContent title "\n┌─ $(xrayConfigValidationFailureTitle) ─────────────────────────────────"
        menuLine "已回滚本次 VLESS Encryption 修改"
        menuLine "排查日志：$(padmTmpFilePath padm-xray-test.log)"
        menuClose
        return 1
    fi
    if ! reloadCore; then
        if ! restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" remove "核心重载失败"; then
            return 1
        fi
        local rollbackMessage
        coreSetRollbackResultMessage rollbackMessage "核心重载失败" "已回滚 VLESS Encryption 修改" reloadCore "恢复旧配置后核心重载仍失败，请检查核心服务日志"
        errorCard "${rollbackMessage}"
        return 1
    fi
    if ! refreshVlessEncryptionSubscriptions; then
        if ! restoreVlessEncryptionBackup "${backupFile}" "${configFile}" "${stateBackupFile}" "${stateFile}" "${hadStateBackup}" remove "刷新 VLESS Encryption 订阅失败"; then
            return 1
        fi
        local refreshRollbackMessage
        coreSetRollbackResultMessage refreshRollbackMessage "刷新 VLESS Encryption 订阅失败" "已恢复旧配置" reloadCore "恢复旧配置后核心重载失败，请检查核心服务日志"
        removeManagedFilesIfPresentIgnoreFailure "${backupFile}" "${stateBackupFile}"
        errorCard "${refreshRollbackMessage}"
        return 1
    fi
    removeManagedFilesIfPresentIgnoreFailure "${backupFile}" "${stateBackupFile}"
    return 0
}

manageVlessEncryptionExperiment() {
    readInstallType
    readInstallProtocolType
    echoContent title "\n┌─ VLESS Encryption 实验功能 ─────────────────────────"
    menuLine "最佳性能组合：Reality Vision 使用 VLESS Encryption + XTLS Vision"
    menuLine "CDN 场景：Reality XHTTP 使用 VLESS Encryption + XTLS Vision + XHTTP XMUX"
    menuLine "启用后可能只有部分客户端可用；需 Mihomo v1.19.13+，sing-box 暂不支持"
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
            "启用后 default VLESS 链接和 Mihomo 订阅会携带 encryption 参数" \
            "需 Mihomo v1.19.13+；sing-box 订阅因上游不支持仍省略"
        autoConfirm vless_encryption_confirm "确认承担兼容性风险并启用 VLESS Encryption？" n confirmVlessEncryption
        if [[ "${confirmVlessEncryption}" == "y" ]]; then
            setVlessRealityEncryption enable && successCard "VLESS Encryption 实验开关已启用"
        else
            coreCancelledStatusCard "操作未执行"
        fi
        ;;
    2)
        setVlessRealityEncryption disable && successCard "VLESS Encryption 实验开关已关闭"
        ;;
    3)
        return 0
        ;;
    *)
        coreSelectionRetryAction manageVlessEncryptionExperiment
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
            coreSelectionRetryAction checkBTPanel
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
            coreSelectionRetryAction check1Panel
        fi
    fi
}



cleanCoreInstallDirectory() {
    local targetDir=$1
    local description=$2
    if ! padmIsSafeAbsolutePath "${targetDir}"; then
        errorCard "${description}路径异常，已取消清理"
        return 1
    fi
    cleanDirectoryContent "${targetDir}" || { errorCard "${description}文件清理失败"; return 1; }
}

singBoxProtocolUninstallRollback() {
    local backupDir=$1
    local serviceWasRunning=$2
    local serviceWasEnabled=$3
    local restoreRegistration=$4
    local reason=$5
    local rollbackFailed=false

    checkLogBackupRestore "${backupDir}" || rollbackFailed=true
    if [[ "${restoreRegistration}" == "true" ]]; then
        if [[ "${release:-}" == "alpine" ]]; then
            if [[ "${serviceWasEnabled}" == "true" ]] && ! rc-update add sing-box default >/dev/null 2>&1; then
                rollbackFailed=true
            fi
        else
            if ! systemctl daemon-reload >/dev/null 2>&1; then
                rollbackFailed=true
            fi
            if [[ "${serviceWasEnabled}" == "true" ]] && ! systemctl enable sing-box.service >/dev/null 2>&1; then
                rollbackFailed=true
            fi
        fi
    fi
    readInstallType || rollbackFailed=true
    if [[ "${serviceWasRunning}" == "true" ]] && ! runCoreServiceActionAllowFailure handleSingBox start; then
        rollbackFailed=true
    fi
    if [[ "${rollbackFailed}" == "true" ]]; then
        padmForgetCleanupPath "${backupDir}"
        errorCard "${reason}，且回滚失败，请检查备份目录: ${backupDir}"
    else
        padmRemoveCleanupPath "${backupDir}"
        errorCard "${reason}，已恢复旧配置和服务状态"
    fi
    return 1
}

singBoxRemoveServiceRegistration() {
    local serviceFile
    if [[ "${release:-}" == "alpine" ]]; then
        serviceFile=${PADM_SINGBOX_OPENRC_SERVICE_FILE:-/etc/init.d/sing-box}
        if coreStartupServiceEnabled sing-box && ! rc-update del sing-box default >/dev/null 2>&1; then
            return 1
        fi
        removeManagedFileIfPresent "${serviceFile}" || return 1
    else
        serviceFile=${PADM_SINGBOX_SYSTEMD_SERVICE_FILE:-/etc/systemd/system/sing-box.service}
        if coreStartupServiceEnabled sing-box && ! systemctl disable sing-box.service >/dev/null 2>&1; then
            return 1
        fi
        removeManagedFileIfPresent "${serviceFile}" || return 1
        systemctl daemon-reload >/dev/null 2>&1 || return 1
    fi
}

# 卸载 sing-box
unInstallSingBox() {
    local type=${1:-}
    local protocolFile protocolPort mergedFile serviceFile uninstallBackupDir
    local serviceWasRunning=false
    local serviceWasEnabled=false
    local portHoppingStart= portHoppingEnd=
    local firewallStatus=0
    local validationLog

    if [[ -z "${singBoxConfigPath}" ]]; then
        if ! runCoreServiceActionAllowFailure handleSingBox stop; then
            errorCard "sing-box 服务停止失败，已取消卸载"
            return 1
        fi
        singBoxRemoveServiceRegistration || {
            errorCard "sing-box 开机自启清理失败，已取消卸载"
            return 1
        }
        cleanCoreInstallDirectory /etc/padm/sing-box "sing-box" || return 1
        successCard "sing-box 卸载完成"
        return 0
    fi

    if ! padmIsSafeAbsolutePath "${singBoxConfigPath%/}"; then
        errorCard "sing-box 配置路径异常，已取消卸载"
        return 1
    fi
    case "${type}" in
    tuic) protocolFile=09_tuic_inbounds.json ;;
    hysteria2) protocolFile=06_hysteria2_inbounds.json ;;
    *) errorCard "sing-box 协议类型异常，已取消卸载"; return 1 ;;
    esac
    protocolFile=$(padmManagedFilePath "${singBoxConfigPath}" "${protocolFile}") || return 1
    [[ -f "${protocolFile}" ]] || { errorCard "未找到 sing-box ${type} 配置，已取消卸载"; return 1; }
    protocolPort=$(jq -er '.inbounds[0].listen_port | select(type == "number" and . >= 1 and . <= 65535 and floor == .)' "${protocolFile}") || {
        errorCard "sing-box ${type} 端口读取失败，已取消卸载"
        return 1
    }
    validPortNumber "${protocolPort}" || { errorCard "sing-box ${type} 端口异常，已取消卸载"; return 1; }
    mergedFile=$(padmManagedFilePath "${singBoxConfigPath}" config.json) || return 1
    if [[ "${release:-}" == "alpine" ]]; then
        serviceFile=${PADM_SINGBOX_OPENRC_SERVICE_FILE:-/etc/init.d/sing-box}
    else
        serviceFile=${PADM_SINGBOX_SYSTEMD_SERVICE_FILE:-/etc/systemd/system/sing-box.service}
    fi
    if singBoxRunning; then
        serviceWasRunning=true
    fi
    if coreStartupServiceEnabled sing-box; then
        serviceWasEnabled=true
    fi
    if declare -F readPortHopping >/dev/null 2>&1; then
        readPortHopping "${type}" "${protocolPort}" >/dev/null 2>&1 || true
        if [[ "${type}" == "hysteria2" ]]; then
            portHoppingStart=${hysteria2PortHoppingStart:-}
            portHoppingEnd=${hysteria2PortHoppingEnd:-}
        else
            portHoppingStart=${tuicPortHoppingStart:-}
            portHoppingEnd=${tuicPortHoppingEnd:-}
        fi
    fi
    checkLogBackupCreate uninstallBackupDir "${protocolFile}" "${mergedFile}" "${serviceFile}" || {
        errorCard "sing-box 卸载备份失败，已取消卸载"
        return 1
    }
    if [[ "${serviceWasRunning}" == "true" ]] && ! runCoreServiceActionAllowFailure handleSingBox stop; then
        padmRemoveCleanupPath "${uninstallBackupDir}"
        errorCard "sing-box 服务停止失败，已取消卸载"
        return 1
    fi
    if ! removeManagedFileIfPresent "${protocolFile}"; then
        singBoxProtocolUninstallRollback "${uninstallBackupDir}" "${serviceWasRunning}" "${serviceWasEnabled}" false "sing-box ${type} 配置删除失败"
        return 1
    fi
    if ! removeManagedFileIfPresent "${mergedFile}"; then
        singBoxProtocolUninstallRollback "${uninstallBackupDir}" "${serviceWasRunning}" "${serviceWasEnabled}" false "sing-box 主配置删除失败"
        return 1
    fi

    readInstallType || {
        singBoxProtocolUninstallRollback "${uninstallBackupDir}" "${serviceWasRunning}" "${serviceWasEnabled}" false "sing-box 配置状态刷新失败"
        return 1
    }
    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ -x "${PADM_SINGBOX_BINARY:-/etc/padm/sing-box/sing-box}" ]]; then
            validationLog=$(padmTmpFilePath padm-sing-box-uninstall.log)
            if ! singBoxMergeConfigForValidation "${PADM_SINGBOX_BINARY:-/etc/padm/sing-box/sing-box}" "${validationLog}" check; then
                singBoxProtocolUninstallRollback "${uninstallBackupDir}" "${serviceWasRunning}" "${serviceWasEnabled}" false "sing-box 配置校验失败"
                return 1
            fi
        fi
        if [[ "${serviceWasRunning}" == "true" ]] && ! runCoreServiceActionAllowFailure handleSingBox start; then
            singBoxProtocolUninstallRollback "${uninstallBackupDir}" true "${serviceWasEnabled}" false "sing-box 服务重启失败"
            return 1
        fi
        statusCard "保留配置" "检测到有其他配置，保留 sing-box 核心"
    else
        if ! singBoxRemoveServiceRegistration; then
            singBoxProtocolUninstallRollback "${uninstallBackupDir}" "${serviceWasRunning}" "${serviceWasEnabled}" true "sing-box 开机自启清理失败"
            return 1
        fi
        if ! cleanCoreInstallDirectory /etc/padm/sing-box "sing-box"; then
            padmForgetCleanupPath "${uninstallBackupDir}"
            errorCard "sing-box 核心清理失败，请检查备份目录: ${uninstallBackupDir}"
            return 1
        fi
    fi
    padmRemoveCleanupPath "${uninstallBackupDir}"

    if [[ -n "${portHoppingStart}" && -n "${portHoppingEnd}" ]]; then
        deletePortHoppingRules "${type}" "${portHoppingStart}" "${portHoppingEnd}" "${protocolPort}" || firewallStatus=1
    fi
    denyPort "${protocolPort}" || firewallStatus=1
    denyPort "${protocolPort}" udp || firewallStatus=1
    if [[ "${firewallStatus}" != "0" ]]; then
        errorCard "sing-box ${type} 已卸载，但防火墙规则回收失败，请检查防火墙状态"
        return 1
    fi
    successCard "删除sing-box ${type}配置成功"
}


# 清理核心安装残留
cleanUp() {
    if [[ "$1" == "xrayDel" ]]; then
        runCoreServiceActionAllowFailure handleXray stop || { errorCard "Xray 服务停止失败，已取消清理旧核心"; return 1; }
        cleanCoreInstallDirectory "$(coreXrayInstallDir)" "Xray" || return 1
    elif [[ "$1" == "singBoxDel" ]]; then
        runCoreServiceActionAllowFailure handleSingBox stop || { errorCard "sing-box 服务停止失败，已取消清理旧核心"; return 1; }
        removeManagedFileIfPresent "$(singBoxMergedConfigFile)" || { errorCard "sing-box 主配置清理失败"; return 1; }
        cleanDirectoryContent "$(singBoxConfigShardDir)" || { errorCard "sing-box 分片配置清理失败"; return 1; }
    fi
}

# 传统 TLS fallback 维护
manageTraditionalTlsFallback() {
    if [[ "${coreInstallType}" == "2" ]]; then
        errorCard "此功能仅支持 Xray-core 内核"
        exit 0
    fi

    progressCard "$1" "传统 TLS fallback 维护"

    if ! currentProtocolHas 27 || [[ -z "${coreInstallType}" ]]; then
        errorCard "请先安装 Xray-core 的 27.VLESS TCP TLS Vision"
        exit 0
    fi

    echoContent title "\n┌─ 传统 TLS fallback 维护 ───────────────────────────"
    menuLine "仅用于传统 TLS fallback / WS / gRPC / Trojan 兼容维护"
    menuLine "Reality Vision / Reality XHTTP 不依赖此处 ALPN 或静态站点"
    menuRecommendedItem 1 "重建 fallback 配置" "alone.conf 缺失或不完整时重建 Nginx 承接层"
    menuItem 2 "更换静态站点" "更换本机 Nginx fallback 页面"
    menuItem 3 "302 重定向管理" "添加或移除 fallback 根路由重定向"
    menuItem 4 "ALPN 诊断" "检查 h2 fallback、ALPN 与 Nginx 承接层是否匹配"
    menuRecommendedItem 5 "修复为推荐 ALPN" "存在 h2 fallback 时设置 h2,http/1.1"
    menuItem 6 "手动设置 ALPN" "兼容排障时手动调整 ALPN 顺序"
    menuReturnItem 7 "返回站点与证书" "回到上级菜单"
    menuClose
    autoRead traditional_tls_menu "请选择:" selectTraditionalTlsMenu

    case "${selectTraditionalTlsMenu}" in
    1)
        ensureTraditionalTlsFallbackNginxConfig
        ;;
    2)
        manageTraditionalTlsStaticSite
        ;;
    3)
        manageTraditionalTlsRedirect
        ;;
    4)
        diagnoseTraditionalTlsAlpn
        ;;
    5)
        repairTraditionalTlsAlpn
        ;;
    6)
        setTraditionalTlsAlpnManual
        ;;
    7)
        siteCertificateMenu
        ;;
    *)
        coreSelectionRetryAction manageTraditionalTlsFallback "$@"
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
    padmTmpFilePath padm-alpn-xray-test.log
}

restoreTraditionalTlsAlpnBackup() {
    local backupFile=$1
    local configFile=$2
    local reason=$3
    local restoreMessage
    if restoreManagedFileFromBackup "${backupFile}" "${configFile}" 644; then
        removeManagedFilesIfPresentIgnoreFailure "${backupFile}"
        return 0
    fi
    coreSetSingleRestoreResultMessage restoreMessage "${reason}" false "已恢复旧配置" "旧配置" " ${configFile} 和 ${backupFile}" || true
    errorCard "${restoreMessage}"
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
        coreSelectionRetryAction manageTraditionalTlsStaticSite
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
        if ! ensureTraditionalTlsFallbackNginxConfig; then
            return 1
        fi
        backupNginxConfig backup || return 1
        autoRead redirect_domain "请输入要重定向的域名,例如 https://www.baidu.com:" redirectDomain
        if ! removeNginx302 || ! addNginx302 "${redirectDomain}"; then
            backupNginxConfig restoreBackup
            return 1
        fi
        serviceQueueRefresh nginx
        if ! serviceQueueApply; then
            backupNginxConfig restoreBackup || return 1
            serviceQueueRefresh nginx
            serviceQueueApply || return 1
            return 1
        fi
        if [[ -z $(pgrep -f "nginx") ]]; then
            backupNginxConfig restoreBackup
            serviceQueueRefresh nginx
            serviceQueueApply || return 1
            return 1
        fi
        if ! checkNginx302; then
            return 1
        fi
        exit 0
    elif [[ "${redirectStatus}" == "2" ]]; then
        if ! ensureTraditionalTlsFallbackNginxConfig; then
            return 1
        fi
        backupNginxConfig backup || return 1
        removeNginx302 || return 1
        serviceQueueRefresh nginx
        if ! serviceQueueApply; then
            backupNginxConfig restoreBackup || return 1
            serviceQueueRefresh nginx
            serviceQueueApply || return 1
            return 1
        fi
        successCard "移除302重定向成功"
        exit 0
    elif [[ "${redirectStatus}" == "3" ]]; then
        manageTraditionalTlsFallback
    else
        coreSelectionRetryAction manageTraditionalTlsRedirect
    fi
}

diagnoseTraditionalTlsAlpn() {
    local configFile currentAlpn hasH2Fallback nginxH2Status nginxFallbackStatus
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
    if [[ -f "${nginxConfigPath}alone.conf" ]]; then
        nginxFallbackStatus="已检测到"
    else
        nginxFallbackStatus="缺失"
    fi

    echoContent title "\n┌─ 传统 TLS ALPN 诊断 ───────────────────────────────"
    menuLine "配置文件：${configFile}"
    menuLine "当前 ALPN：${currentAlpn:-未设置}"
    menuLine "h2 fallback：${hasH2Fallback}"
    menuLine "Nginx fallback：${nginxFallbackStatus}"
    menuLine "Nginx h2 fallback：${nginxH2Status}"
    if [[ "${nginxFallbackStatus}" == "缺失" ]]; then
        menuLine "建议：先执行“重建 fallback 配置”恢复 alone.conf"
    elif [[ "${hasH2Fallback}" == "是" && "${currentAlpn}" != "h2,http/1.1" ]]; then
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
    configFile=$(padmRequireSafeAbsolutePath "${configFile}") || { errorCard "传统 TLS fallback 配置路径异常"; return 1; }
    backupFile="${configFile}.alpn.bak"
    if [[ ! -f "${configFile}" ]]; then
        errorCard "未检测到传统 TLS fallback 入站配置"
        return 1
    fi
    backupManagedFileToPath "${configFile}" "${backupFile}" 644 || return 1
    padmCreateTempFileForTarget tmpFile "${configFile}" alpn || {
        removeManagedFilesIfPresentIgnoreFailure "${backupFile}"
        return 1
    }
    if ! jq --argjson alpn "${alpnJson}" '.inbounds[0].streamSettings.tlsSettings.alpn = $alpn' "${configFile}" >"${tmpFile}"; then
        padmRemoveCleanupPath "${tmpFile}"
        removeManagedFilesIfPresentIgnoreFailure "${backupFile}"
        errorCard "写入 ALPN 配置失败"
        return 1
    fi
    if ! commitGeneratedJsonFile "${tmpFile}" "${configFile}"; then
        padmRemoveCleanupPath "${tmpFile}"
        removeManagedFilesIfPresentIgnoreFailure "${backupFile}"
        errorCard "写入 ALPN 配置失败"
        return 1
    fi
    local xrayBinary
    local xrayConfigDir
    xrayBinary=$(manageXrayBinaryPath)
    xrayConfigDir=$(manageXrayConfigDir)
    if [[ -x "${xrayBinary}" ]] && ! "${xrayBinary}" -test -confdir "${xrayConfigDir}" >"$(traditionalTlsAlpnTestLog)" 2>&1; then
        if ! restoreTraditionalTlsAlpnBackup "${backupFile}" "${configFile}" "$(xrayConfigValidationFailureTitle)"; then
            return 1
        fi
        echoContent title "\n┌─ $(xrayConfigValidationFailureTitle) ─────────────────────────────────"
        menuLine "已回滚本次 ALPN 修改"
        menuLine "排查日志：$(traditionalTlsAlpnTestLog)"
        menuClose
        return 1
    fi
    if ! reloadCore; then
        if ! restoreTraditionalTlsAlpnBackup "${backupFile}" "${configFile}" "核心重载失败"; then
            return 1
        fi
        local rollbackMessage
        coreSetRollbackResultMessage rollbackMessage "核心重载失败" "已回滚 ALPN 修改" reloadCore "恢复旧配置后核心重载仍失败，请检查核心服务日志"
        errorCard "${rollbackMessage}"
        return 1
    fi
    removeManagedFilesIfPresentIgnoreFailure "${backupFile}"
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
        coreSelectionRetryAction setTraditionalTlsAlpnManual
        ;;
    esac
}



# 入口端口管理
corePortIsValid() {
    local port=$1
    validPortNumber "${port}"
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

corePortSafeConfigDir() {
    [[ -n "${configPath:-}" ]] || return 1
    padmIsSafeAbsolutePath "${configPath%/}" || return 1
    printf '%s\n' "${configPath%/}/"
}

corePortManagedFilesByPattern() {
    local pattern=$1
    local configDir
    configDir=$(corePortSafeConfigDir) || return 1
    [[ -d "${configDir}" ]] || return 0
    find "${configDir}" -maxdepth 1 -type f -name "${pattern}" -print | LC_ALL=C sort
}

corePortManagedFilePath() {
    local fileName=$1
    local configDir
    configDir=$(corePortSafeConfigDir) || return 1
    padmManagedFilePath "${configDir}" "${fileName}"
}

corePortListExtra() {
    local file base port defaultMark count=0
    while IFS= read -r file; do
        base=${file##*/}
        [[ "${base}" == *hysteria* ]] && continue
        if [[ "${base}" =~ ^02_dokodemodoor_inbounds_([0-9]+)(_default)?\.json$ ]]; then
            port=${BASH_REMATCH[1]}
            defaultMark=
            [[ -n "${BASH_REMATCH[2]}" ]] && defaultMark=" 默认"
            count=$((count + 1))
            printf '%s:%s%s\n' "${count}" "${port}" "${defaultMark}"
        fi
    done < <(corePortManagedFilesByPattern '02_dokodemodoor_inbounds_*.json')
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
    while IFS= read -r file; do
        printf '%s\n' "${file}"
        return 0
    done < <(corePortManagedFilesByPattern '02_dokodemodoor_inbounds_*_default.json')
    return 1
}

corePortRemove() {
    local port=$1
    local status=0
    local targetFile
    targetFile=$(corePortManagedFilePath "02_dokodemodoor_inbounds_${port}.json") || return 1
    removeManagedFileIfPresent "${targetFile}" || status=1
    targetFile=$(corePortManagedFilePath "02_dokodemodoor_inbounds_${port}_default.json") || return 1
    removeManagedFileIfPresent "${targetFile}" || status=1
    targetFile=$(corePortManagedFilePath "02_dokodemodoor_inbounds_hysteria_${port}.json") || return 1
    removeManagedFileIfPresent "${targetFile}" || status=1
    return "${status}"
}

corePortBackupFiles() {
    local backupDir=$1
    local file base
    corePortSafeConfigDir >/dev/null || return 1
    padmEnsureSafeDirectory "${backupDir}" || return 1
    while IFS= read -r file; do
        base=${file##*/}
        backupManagedFileToPath "${file}" "${backupDir}/${base}" 644 || return 1
    done < <(corePortManagedFilesByPattern '02_dokodemodoor_inbounds_*.json')
}

corePortRollbackFiles() {
    local backupDir=$1
    local configDir
    local file status=0
    configDir=$(corePortSafeConfigDir) || return 1
    [[ -d "${backupDir}" ]] || return 1
    while IFS= read -r file; do
        removeManagedFileIfPresent "${file}" || status=1
    done < <(corePortManagedFilesByPattern '02_dokodemodoor_inbounds_*.json')
    for file in "${backupDir}"/*.json; do
        local targetFile
        [[ -f "${file}" ]] || continue
        targetFile=$(padmManagedFilePath "${configDir}" "${file##*/}") || return 1
        restoreManagedFileFromBackup "${file}" "${targetFile}" 644 || status=1
    done
    return "${status}"
}

corePortReportBackupFailure() {
    local backupDir=$1
    padmRemoveCleanupPath "${backupDir}"
    errorCard "入口端口配置备份失败"
}

corePortReportRollbackFailure() {
    local backupDir=$1
    local rollbackMessage
    padmForgetCleanupPath "${backupDir}"
    coreSetRollbackFailureMessage rollbackMessage "入口端口配置回滚失败" "${backupDir}" ""
    errorCard "${rollbackMessage}"
}

corePortValidateFiles() {
    local file
    while IFS= read -r file; do
        jq empty "${file}" >/dev/null || return 1
    done < <(corePortManagedFilesByPattern '02_dokodemodoor_inbounds_*.json')
}

corePortWriteAddFiles() {
    local ports=$1
    local defaultPort=$2
    local settingsPort=$3
    local configDir
    local port fileName hysteriaFileName defaultFile
    configDir=$(corePortSafeConfigDir) || return 1
    if [[ -n "${defaultPort}" ]]; then
        defaultFile=$(corePortDefaultFile || true)
        [[ -z "${defaultFile}" ]] || removeManagedFileIfPresent "${defaultFile}" || return 1
    fi
    while read -r port; do
        corePortRemove "${port}" || return 1
        if [[ -n "${defaultPort}" && "${port}" == "${defaultPort}" ]]; then
            fileName="${configDir}02_dokodemodoor_inbounds_${port}_default.json"
        else
            fileName="${configDir}02_dokodemodoor_inbounds_${port}.json"
        fi
        if [[ -n ${hysteriaPort:-} ]]; then
            hysteriaFileName="${configDir}02_dokodemodoor_inbounds_hysteria_${port}.json"
            writeCoreDokodemoInbound "${hysteriaFileName}" "${port}" "${hysteriaPort}" udp "dokodemo-door-newPort-hysteria-${port}" || return 1
        fi
        writeCoreDokodemoInbound "${fileName}" "${port}" "${settingsPort}" tcp "dokodemo-door-newPort-${port}" || return 1
    done <<<"${ports}"
}

corePortApplyFileTransaction() {
    local action=$1
    local backupDir
    padmCreateTmpRootPath backupDir padm-core-port.XXXXXX -d || return 1
    if ! corePortBackupFiles "${backupDir}"; then
        corePortReportBackupFailure "${backupDir}"
        return 1
    fi
    shift
    if ! "${action}" "$@" || ! corePortValidateFiles; then
        if corePortRollbackFiles "${backupDir}"; then
            padmRemoveCleanupPath "${backupDir}"
        else
            corePortReportRollbackFailure "${backupDir}"
        fi
        return 1
    fi
    padmRemoveCleanupPath "${backupDir}"
}

corePortApplyReloadTransaction() {
    local action=$1
    local backupDir
    local restoreMessage
    padmCreateTmpRootPath backupDir padm-core-port.XXXXXX -d || return 1
    if ! corePortBackupFiles "${backupDir}"; then
        corePortReportBackupFailure "${backupDir}"
        return 1
    fi
    shift
    if ! "${action}" "$@" || ! corePortValidateFiles; then
        if corePortRollbackFiles "${backupDir}"; then
            padmRemoveCleanupPath "${backupDir}"
        else
            corePortReportRollbackFailure "${backupDir}"
        fi
        return 1
    fi
    if reloadCore; then
        padmRemoveCleanupPath "${backupDir}"
        return 0
    fi

    if ! corePortRollbackFiles "${backupDir}"; then
        padmForgetCleanupPath "${backupDir}"
        coreSetSingleRestoreResultMessage restoreMessage "入口端口核心重载失败" false "已恢复旧配置" "旧配置" "备份目录: ${backupDir}" || true
        errorCard "${restoreMessage}"
        return 1
    fi
    local rollbackMessage
    coreSetRollbackResultMessage rollbackMessage "入口端口核心重载失败" "已恢复旧配置" reloadCore "恢复后核心重载仍失败，请检查核心服务日志"
    errorCard "${rollbackMessage}"
    padmRemoveCleanupPath "${backupDir}"
    return 1
}

writeCoreDokodemoInbound() {
    local fileName=$1
    local port=$2
    local targetPort=$3
    local network=$4
    local tag=$5
    local tmpFile
    fileName=$(padmRequireSafeAbsolutePath "${fileName}") || return 1
    padmCreateTempFileForTarget tmpFile "${fileName}" dokodemo || return 1
    if ! cat >"${tmpFile}" <<EOF
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
    then
        padmRemoveCleanupPath "${tmpFile}"
        return 1
    fi
    commitGeneratedJsonFile "${tmpFile}" "${fileName}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

corePortRollbackFirewallRules() {
    local rule
    local status=0
    for rule in "$@"; do
        denyPort "${rule%%|*}" "${rule##*|}" || status=1
    done
    [[ "${status}" == "0" ]] || errorCard "入口端口防火墙规则回滚失败，请检查防火墙状态"
    return "${status}"
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
            local -a openedFirewallRules=()
            parsedPorts=$(corePortParseList "${newPort}") || {
                errorCard "端口格式错误"
                return 1
            }
            if [[ -n "${customPort}" ]]; then
                settingsPort=${customPort}
            fi
            while read -r port; do
                if ! allowPort "${port}"; then
                    corePortRollbackFirewallRules "${openedFirewallRules[@]}" || true
                    return 1
                fi
                [[ "${PADM_LAST_ALLOW_PORT_ADDED:-false}" == "true" ]] && openedFirewallRules+=("${port}|tcp")
                if ! allowPort "${port}" "udp"; then
                    corePortRollbackFirewallRules "${openedFirewallRules[@]}" || true
                    return 1
                fi
                [[ "${PADM_LAST_ALLOW_PORT_ADDED:-false}" == "true" ]] && openedFirewallRules+=("${port}|udp")
            done <<<"${parsedPorts}"
            if ! corePortApplyReloadTransaction corePortWriteAddFiles "${parsedPorts}" "${defaultPort}" "${settingsPort}"; then
                corePortRollbackFirewallRules "${openedFirewallRules[@]}" || true
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
            local firewallStatus=0
            denyPort "${port}" || firewallStatus=1
            denyPort "${port}" udp || firewallStatus=1
            if [[ "${firewallStatus}" != "0" ]]; then
                errorCard "入口端口配置已删除，但防火墙规则回收失败，请检查防火墙状态"
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

    if ! padmIsSafeAbsolutePath "${targetPath}"; then
        errorCard "${description}路径异常，已终止: ${targetPath}"
        return 1
    fi

    if [[ ! -e "${targetPath}" && ! -L "${targetPath}" ]]; then
        return 0
    fi

    for attempt in 1 2 3; do
        if removeManagedPathIfPresent "${targetPath}"; then
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
    local wireGuardDir
    local wireGuardConfigFile
    local wireGuardStateFile
    local wireGuardPrivateKeyFile
    local wireGuardPublicKeyFile
    local controlServiceFile
    wireGuardDir=$(subscriptionWireGuardSafeDir) || return 1
    wireGuardConfigFile=$(subscriptionWireGuardConfigFile) || return 1
    wireGuardStateFile=$(subscriptionWireGuardStateFile) || return 1
    wireGuardPrivateKeyFile=$(subscriptionWireGuardPrivateKeyFile) || return 1
    wireGuardPublicKeyFile=$(subscriptionWireGuardPublicKeyFile) || return 1
    controlServiceFile=$(subscriptionControlServiceFile) || return 1

    if [[ -e "${wireGuardConfigFile}" || -L "${wireGuardConfigFile}" ||
        -e "${wireGuardStateFile}" || -L "${wireGuardStateFile}" ||
        -e "${wireGuardPrivateKeyFile}" || -L "${wireGuardPrivateKeyFile}" ||
        -e "${wireGuardPublicKeyFile}" || -L "${wireGuardPublicKeyFile}" ]]; then
        if ! stopSubscriptionWireGuardControlService; then
            errorCard "WireGuard 控制面停止失败，已取消删除控制面文件"
            return 1
        fi
    fi
    if command -v systemctl >/dev/null 2>&1; then
        if [[ -e "${controlServiceFile}" || -L "${controlServiceFile}" ]] ||
            systemctl is-active --quiet padm-subscription-control.service ||
            systemctl is-enabled --quiet padm-subscription-control.service; then
            if ! systemctl disable --now padm-subscription-control.service >/dev/null 2>&1; then
                errorCard "订阅控制服务停止失败，已取消删除控制面文件"
                return 1
            fi
        fi
    fi
    removeInstallPath "${wireGuardConfigFile}" "WireGuard控制面配置" || return 1
    removeInstallPath "${wireGuardStateFile}" "WireGuard控制面状态" || return 1
    removeInstallPath "${wireGuardPrivateKeyFile}" "WireGuard控制面私钥" || return 1
    removeInstallPath "${wireGuardPublicKeyFile}" "WireGuard控制面公钥" || return 1
    removeInstallPath "${controlServiceFile}" "订阅控制面systemd服务" || return 1
    if [[ -d "${wireGuardDir}" && ! -L "${wireGuardDir}" ]] &&
        [[ -z "$(find "${wireGuardDir}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        rmdir -- "${wireGuardDir}" >/dev/null 2>&1 || return 1
    fi
}

cleanupFail2banManagedFilesOnUninstall() {
    local failed=false
    removeInstallPath "$(fail2banManagedJailFile)" "Fail2ban jail 配置" || failed=true
    removeInstallPath "$(fail2banManagedFilterFile)" "Fail2ban filter 配置" || failed=true
    removeInstallPath "$(fail2banManagedNginxScanFilterFile)" "Fail2ban Nginx 扫描 filter 配置" || failed=true
    removeInstallPath "$(fail2banPadmControlLogFile)" "Fail2ban 控制面日志" || failed=true
    if declare -F fail2banReloadServiceIfRunning >/dev/null 2>&1; then
        fail2banReloadServiceIfRunning || failed=true
    fi
    [[ "${failed}" != "true" ]]
}

uninstallShouldStopNginx() {
    if [[ -n "${currentInstallProtocolType:-}" ]] && ! protocolSelectionSkipsNginx "${currentInstallProtocolType}"; then
        return 0
    fi
    [[ -f "${nginxConfigPath:-/etc/nginx/conf.d/}subscribe.conf" ]] && return 0
    [[ -f "${nginxConfigPath:-/etc/nginx/conf.d/}padm-control-wg.conf" ]] && return 0
    [[ -d "${nginxStaticPath:-}" && -f "${nginxStaticPath}/check" ]] && return 0
    return 1
}

uninstallStoppedServicesVerified() {
    local failed=false
    local shouldStopNginx=$1
    local shouldStopXray=$2
    local shouldStopSingBox=$3
    if [[ "${shouldStopNginx}" == "true" ]] && nginxRunning; then
        failed=true
        errorCard "Nginx停止后仍在运行，已取消后续删除"
    fi
    if [[ "${shouldStopXray}" == "true" ]] && xrayRunning; then
        failed=true
        errorCard "Xray停止后仍在运行，已取消后续删除"
    fi
    if [[ "${shouldStopSingBox}" == "true" ]] && singBoxRunning; then
        failed=true
        errorCard "sing-box停止后仍在运行，已取消后续删除"
    fi
    [[ "${failed}" != "true" ]]
}

uninstallReloadSystemdUnits() {
    if padmCommandExists systemctl; then
        systemctl daemon-reload
    fi
}

cleanupPadmCronJobsOnUninstall() {
    local currentCrontab cleanedCrontab
    command -v crontab >/dev/null 2>&1 || return 0
    currentCrontab=$(readUserCrontabContent) || return 1
    cleanedCrontab=$(sed \
        -e '\|/etc/padm/install.sh RenewTLS|d' \
        -e '\|/etc/padm/install.sh UpdateGeo|d' \
        -e '\|/etc/padm/install.sh SyncSubscriptionGroups|d' \
        <<<"${currentCrontab}") || return 1
    [[ "${cleanedCrontab}" == "${currentCrontab}" ]] && return 0
    installUserCrontabContent "${cleanedCrontab}"
}

cleanupPadmManagedRootOnUninstall() {
    local installRoot="${PADM_INSTALL_DIR:-/etc/padm}"
    local resolvedRoot
    local failed=false
    local target
    local childPath
    local -a managedPaths=(
        "${installRoot%/}/xray"
        "${installRoot%/}/sing-box"
        "${installRoot%/}/hysteria"
        "${installRoot%/}/tls"
        "${installRoot%/}/subscribe"
        "${installRoot%/}/subscribe_local"
        "${installRoot%/}/subscribe_remote"
        "${installRoot%/}/subscribe_groups"
        "${installRoot%/}/warp"
        "${installRoot%/}/wireguard"
        "${installRoot%/}/shell"
        "${installRoot%/}/documents"
        "${installRoot%/}/assets"
        "${installRoot%/}/install.sh"
        "${installRoot%/}/README.md"
        "${installRoot%/}/install.sh.bak"
        "${installRoot%/}/.padm-ref"
        "${installRoot%/}/.padm-module-manifest"
        "${installRoot%/}/.padm-entry-ref"
        "${installRoot%/}/cdn"
        "${installRoot%/}/reality_entry_host"
        "${installRoot%/}/reality_target_blocked.tsv"
        "${installRoot%/}/reality_targets_results.tsv"
        "${installRoot%/}/reality_stream_split.json"
        "${installRoot%/}/vless_encryption.json"
        "${installRoot%/}/alone_backup.conf"
        "${installRoot%/}/padm-bbr.state"
        "${installRoot%/}/firewall.state"
        "${installRoot%/}/install.log"
        "${installRoot%/}/install.log.dpkg-recover"
        "${installRoot%/}/nginx_error.log"
        "${installRoot%/}/crontab_tls.log"
        "${installRoot%/}/crontab_subscription_groups.log"
    )

    if ! padmIsSafeAbsolutePath "${installRoot%/}"; then
        errorCard "PADM配置目录路径异常，已终止: ${installRoot}"
        return 1
    fi

    for target in "${managedPaths[@]}"; do
        removeInstallPath "${target}" "PADM配置目录受管项" || failed=true
    done

    if [[ -d "${installRoot}" && ! -L "${installRoot}" ]]; then
        resolvedRoot=$(cd -- "${installRoot}" && pwd -P) || {
            errorCard "PADM配置目录解析失败: ${installRoot}"
            return 1
        }
        while IFS= read -r childPath; do
            [[ -n "${childPath}" ]] || continue
            removeManagedPathWithinRootIfPresent "${resolvedRoot}" "${childPath}" || failed=true
        done < <(find "${resolvedRoot}" -mindepth 1 -maxdepth 1 \( -name 'tmp.geo.*' -o -name 'tmp.xray.*' -o -name 'tmp.sing-box.*' \) -print)
        if [[ -z "$(find "${resolvedRoot}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
            rmdir "${resolvedRoot}" >/dev/null 2>&1 || {
                errorCard "PADM配置目录删除失败: ${installRoot}"
                failed=true
            }
        fi
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
    local nginxWasRunning=false
    local uninstallStatus=0
    nginxRunning && nginxWasRunning=true
    unInstallApply "$@" || uninstallStatus=$?
    if [[ "${nginxWasRunning}" == "true" ]] && ! nginxRunning; then
        local restoreErrorLog
        restoreErrorLog=$(padmTmpFilePath padm-nginx-uninstall-restore.log)
        if ! PADM_NGINX_ERROR_LOG="${restoreErrorLog}" runCoreServiceActionAllowFailure handleNginx start restore; then
            rm -f -- "${restoreErrorLog}" >/dev/null 2>&1 || true
            errorCard "卸载后 Nginx 原运行状态恢复失败，请手动检查 Nginx 服务"
            return 1
        fi
        rm -f -- "${restoreErrorLog}" >/dev/null 2>&1 || true
    fi
    return "${uninstallStatus}"
}

unInstallApply() {
    # checkBTPanel
    statusCard "卸载提示" "脚本不会删除 acme 相关配置" "如需删除请手动执行：rm -rf ${HOME:-/root}/.acme.sh"
    local uninstallFailed=false
    local serviceStopFailed=false
    local shouldStopNginx=false
    local shouldStopXray=false
    local shouldStopSingBox=false
    if uninstallShouldStopNginx; then
        shouldStopNginx=true
    fi
    if [[ "${shouldStopNginx}" == "true" ]] && ! runCoreServiceActionAllowFailure handleNginx stop; then
        serviceStopFailed=true
    fi
    if [[ "${shouldStopNginx}" == "true" && -z $(pgrep -f "nginx") ]]; then
        successCard "停止Nginx成功"
    fi
    if [[ "${release}" == "alpine" ]]; then
        if [[ "${coreInstallType}" == "1" || -e /etc/init.d/xray || -L /etc/init.d/xray ]]; then
            shouldStopXray=true
            if ! runCoreServiceActionAllowFailure handleXray stop; then
                serviceStopFailed=true
            fi
        fi
        if [[ "${coreInstallType}" == "2" || -n "${singBoxConfigPath}" || -e /etc/init.d/sing-box || -L /etc/init.d/sing-box ]]; then
            shouldStopSingBox=true
            if ! runCoreServiceActionAllowFailure handleSingBox stop; then
                serviceStopFailed=true
            fi
        fi
        uninstallStoppedServicesVerified "${shouldStopNginx}" "${shouldStopXray}" "${shouldStopSingBox}" || serviceStopFailed=true
        if [[ "${serviceStopFailed}" == "true" ]]; then
            errorCard "卸载未完全完成，请根据上方失败项手动处理；服务停止失败，已取消后续删除"
            return 1
        fi
        if [[ "${coreInstallType}" == "1" || -e /etc/init.d/xray || -L /etc/init.d/xray ]]; then
            if ! rc-update del xray default; then
                uninstallFailed=true
                errorCard "Xray开机自启删除失败"
            fi
            removeInstallPath /etc/init.d/xray "Xray OpenRC服务" || uninstallFailed=true
            successCard "删除Xray开机自启完成"
        fi
        if [[ "${coreInstallType}" == "2" || -n "${singBoxConfigPath}" || -e /etc/init.d/sing-box || -L /etc/init.d/sing-box ]]; then
            if ! rc-update del sing-box default; then
                uninstallFailed=true
                errorCard "sing-box开机自启删除失败"
            fi
            removeInstallPath /etc/init.d/sing-box "sing-box OpenRC服务" || uninstallFailed=true
            successCard "删除sing-box开机自启完成"
        fi
    else
        if ! uninstallReloadSystemdUnits; then
            serviceStopFailed=true
            errorCard "systemd 配置重载失败，已取消后续删除"
        fi
        if [[ "${coreInstallType}" == "1" || -e /etc/systemd/system/xray.service || -L /etc/systemd/system/xray.service ]]; then
            shouldStopXray=true
            if ! runCoreServiceActionAllowFailure handleXray stop; then
                serviceStopFailed=true
            fi
        fi
        if [[ "${coreInstallType}" == "2" || -n "${singBoxConfigPath}" || -e /etc/systemd/system/sing-box.service || -L /etc/systemd/system/sing-box.service ]]; then
            shouldStopSingBox=true
            if ! runCoreServiceActionAllowFailure handleSingBox stop; then
                serviceStopFailed=true
            fi
        fi
        uninstallStoppedServicesVerified "${shouldStopNginx}" "${shouldStopXray}" "${shouldStopSingBox}" || serviceStopFailed=true
        if [[ "${serviceStopFailed}" == "true" ]]; then
            errorCard "卸载未完全完成，请根据上方失败项手动处理；服务停止失败，已取消后续删除"
            return 1
        fi
        if [[ "${coreInstallType}" == "1" || -e /etc/systemd/system/xray.service || -L /etc/systemd/system/xray.service ]]; then
            if ! systemctl disable xray.service >/dev/null 2>&1; then
                errorCard "Xray systemd 开机自启删除失败"
                return 1
            elif ! removeInstallPath /etc/systemd/system/xray.service "Xray systemd服务"; then
                return 1
            else
                successCard "删除Xray开机自启完成"
            fi
        fi
        if [[ "${coreInstallType}" == "2" || -n "${singBoxConfigPath}" || -e /etc/systemd/system/sing-box.service || -L /etc/systemd/system/sing-box.service ]]; then
            if ! systemctl disable sing-box.service >/dev/null 2>&1; then
                errorCard "sing-box systemd 开机自启删除失败"
                return 1
            elif ! removeInstallPath /etc/systemd/system/sing-box.service "sing-box systemd服务"; then
                return 1
            else
                successCard "删除sing-box开机自启完成"
            fi
        fi
    fi

    if ! cleanupPadmCronJobsOnUninstall; then
        errorCard "PADM 定时任务清理失败，已取消后续删除"
        return 1
    fi
    if ! cleanupPadmFirewallRules; then
        errorCard "PADM 防火墙规则清理失败，已取消后续删除"
        return 1
    fi
    if ! cleanupSubscriptionWireGuardControlOnUninstall; then
        errorCard "WireGuard 控制面清理失败，已取消后续删除"
        return 1
    fi
    cleanupFail2banManagedFilesOnUninstall || uninstallFailed=true

    if ! removePadmNginxConfigFragments; then
        uninstallFailed=true
    fi
    cleanupPadmManagedRootOnUninstall || uninstallFailed=true

    if ! unInstallSubscribe; then
        uninstallFailed=true
    fi

    if [[ -d "${nginxStaticPath}" && -f "${nginxStaticPath}/check" ]]; then
        removeInstallPath "${nginxStaticPath}" "伪装网站" || uninstallFailed=true
        successCard "删除伪装网站完成"
    fi

    removeInstallPath /usr/bin/padm "PADM快捷方式" || uninstallFailed=true
    removeInstallPath /usr/sbin/padm "PADM快捷方式" || uninstallFailed=true
    if [[ "${release}" != "alpine" ]] && ! uninstallReloadSystemdUnits; then
        errorCard "systemd 配置重载失败，卸载未完全完成"
        uninstallFailed=true
    fi
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
    local targetFile targetParent stagedPath

    targetFile=$(padmResolveManagedAbsolutePath "$(cdnAddressFile)") || return 1
    targetParent=$(dirname -- "${targetFile}")
    padmEnsureSafeDirectory "${targetParent}" || return 1
    padmCreateTempFileForTarget stagedPath "${targetFile}" cdn || return 1
    printf '%s\n' "${address}" >"${stagedPath}" || { padmRemoveCleanupPath "${stagedPath}"; return 1; }
    commitGeneratedFile "${stagedPath}" "${targetFile}" 644 || { padmRemoveCleanupPath "${stagedPath}"; return 1; }
}

cdnClearAddress() {
    local targetFile targetParent stagedPath

    targetFile=$(padmResolveManagedAbsolutePath "$(cdnAddressFile)") || return 1
    targetParent=$(dirname -- "${targetFile}")
    padmEnsureSafeDirectory "${targetParent}" || return 1
    padmCreateTempFileForTarget stagedPath "${targetFile}" cdn || return 1
    : >"${stagedPath}" || { padmRemoveCleanupPath "${stagedPath}"; return 1; }
    commitGeneratedFile "${stagedPath}" "${targetFile}" 644 || { padmRemoveCleanupPath "${stagedPath}"; return 1; }
}

cdnRestoreAddressValue() {
    local previousAddress=$1
    if [[ -n "${previousAddress}" ]]; then
        cdnWriteAddress "${previousAddress}"
    else
        cdnClearAddress
    fi
}

cdnRefreshSubscriptionsOrRollback() {
    local previousAddress=$1
    if subscribe false false; then
        return 0
    fi
    cdnRestoreAddressValue "${previousAddress}" || {
        errorCard "订阅刷新失败，且 CDN 入口地址恢复失败，请手动检查 $(cdnAddressFile)"
        return 1
    }
    errorCard "订阅刷新失败，已恢复旧 CDN 入口地址"
    return 1
}

showCDNUsageNotes() {
    echoContent title "\n┌─ CDN 使用说明 ─────────────────────────────────────"
    menuLine "1. 新建 XHTTP 场景优先使用协议 2：$(xrayProtocolName 2)"
    menuLine "2. 这里设置的是客户端订阅里的入口地址，可填 CDN CNAME、优选 IP 或自有域名"
    menuLine "3. Reality SNI/target 不会随入口地址改变；它仍由 Reality 目标站管理维护"
    menuLine "4. Cloudflare WebSocket 可用；gRPC/H2/H3 依赖面板开关、客户端与线路支持"
    menuLine "5. 传统 WS/gRPC/HTTPUpgrade 仅用于旧客户端兼容，新建节点优先迁移到 XHTTP"
    menuClose
}

setCDNEntryAddress() {
    local currentAddress input previousAddress
    currentAddress=$(cdnCurrentAddress)
    previousAddress=
    if [[ -f "$(cdnAddressFile)" ]]; then
        previousAddress=$(head -1 "$(cdnAddressFile)")
    fi
    echoContent title "\n┌─ 设置 CDN 入口地址 ─────────────────────────────────"
    menuLine "当前入口地址：${currentAddress}"
    menuLine "可输入多个地址，用英文逗号分隔；订阅会为每个地址生成一条节点"
    menuLine "示例：cdn.example.com,203.0.113.10"
    menuClose
    autoRead custom_cdn_domain "请输入 CDN 入口 IP 或域名[回车取消]:" input
    if [[ -z "${input}" ]]; then
        coreCancelledStatusCard "未修改 CDN 入口地址"
        return 0
    fi
    if ! cdnWriteAddress "${input}"; then
        errorCard "CDN 入口地址写入失败，未刷新订阅"
        return 1
    fi
    statusCard "CDN 入口" "已更新为 ${input}"
    cdnRefreshSubscriptionsOrRollback "${previousAddress}"
}

clearCDNEntryAddress() {
    local previousAddress=
    if [[ -f "$(cdnAddressFile)" ]]; then
        previousAddress=$(head -1 "$(cdnAddressFile)")
    fi
    if ! cdnClearAddress; then
        errorCard "CDN 入口地址清空失败，未刷新订阅"
        return 1
    fi
    statusCard "CDN 入口" "已清空，订阅将使用安装入口地址"
    cdnRefreshSubscriptionsOrRollback "${previousAddress}"
}

manageCDN() {
    local selectCDNType=
    progressCard "$1" "CDN 入口管理" "1"
    while true; do
        readInstallType
        readInstallProtocolType

        echoContent title "\n┌─ CDN 入口管理 ─────────────────────────────────────"
        menuLine "这里只覆盖订阅里的客户端连接地址，不修改 Reality target/SNI 或 XHTTP 参数"
        menuLine "多个 CDN CNAME、优选 IP 或入口域名可用英文逗号分隔，订阅会生成多条节点"
        menuLine "当前入口地址：$(cdnCurrentAddress)"
        if currentProtocolHas 2; then
            menuLine "当前已安装 Reality XHTTP，可直接调整入口地址"
        elif currentProtocolHasAny 21 23 24 25; then
            menuLine "当前是传统 TLS/CDN 协议，仅建议用于旧客户端兼容"
        else
            menuLine "未检测到 XHTTP 能力；新建 XHTTP 节点建议安装协议 2：$(xrayProtocolName 2)"
        fi
        menuItem 1 "设置入口地址" "写入 CDN CNAME、优选 IP 或自有域名"
        menuItem 2 "清空入口地址" "恢复订阅使用安装入口地址"
        menuItem 3 "CDN / H3 使用说明" "查看协议选择和排障提示"
        menuReturnItem 4 "返回协议与入口" "回到上级菜单"
        menuClose
        selectCDNType=
        autoRead cdn_menu "请选择:" selectCDNType || return 0

        case "${selectCDNType}" in
        1)
            if currentProtocolHas 2 || currentProtocolHasAny 21 23 24 25; then
                setCDNEntryAddress || true
            else
                statusCard "不可用" "请先安装 Reality XHTTP 或传统 TLS/CDN 协议"
            fi
            ;;
        2)
            clearCDNEntryAddress || true
            ;;
        3)
            showCDNUsageNotes
            ;;
        4)
            return 0
            ;;
        *)
            coreSelectionErrorCard "选择错误"
            ;;
        esac
    done
}

# Clash Meta 配置文件
clashMetaConfig() {
    local url=$1
    local id=$2
    # Public profiles must use the per-account identifier, never the shared salt.
    local subscribeSalt=${id}
    local targetPath=${3:-$(subscribePublicBaseDir)/clashMetaProfiles/${id}}
    [[ "${PADM_FAKE_CLASH_META_CONFIG_MODE:-success}" == "success" ]] || return 1
    cat <<EOF >"${targetPath}"
log-level: debug
mode: rule
ipv6: true
mixed-port: 7890
allow-lan: false
bind-address: "127.0.0.1"
lan-allowed-ips:
  - 0.0.0.0/0
  - ::/0
find-process-mode: strict
external-controller: 127.0.0.1:9090

geox-url:
  geoip: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"
  geosite: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
  mmdb: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb"
geo-auto-update: true
geo-update-interval: 24

external-controller-cors:
  allow-origins: []
  allow-private-network: false

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
  listen: 127.0.0.1:1053
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
    local targetParent
    targetPath=$(padmResolveManagedAbsolutePath "${targetPath}") || return 1
    targetParent=$(dirname -- "${targetPath}")
    padmEnsureSafeDirectory "${targetParent}" || return 1
    if [[ -f "${stagedPath}" ]]; then
        commitSubscribePublicFile "${stagedPath}" "${targetPath}" || return 1
    else
        removeManagedFileIfPresent "${targetPath}" || return 1
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
    local stagedPath

    subscribeSaltFile=$(padmResolveManagedAbsolutePath "${subscribeSaltFile}") || return 1
    padmCreateTempFileForTarget stagedPath "${subscribeSaltFile}" subscribe || return 1
    printf '%s\n' "${salt}" >"${stagedPath}" || { padmRemoveCleanupPath "${stagedPath}"; return 1; }
    commitGeneratedFile "${stagedPath}" "${subscribeSaltFile}" 600 || { padmRemoveCleanupPath "${stagedPath}"; return 1; }
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
        subscribeSalt=$(initRandomSalt) || return 1
    else
        autoRead subscribe_salt "请输入salt值, [回车]使用随机:" subscribeSalt
    fi

    if [[ -z "${subscribeSalt}" ]]; then
        subscribeSalt=$(initRandomSalt) || return 1
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
    local remoteSnapshots=${6:-}
    local subscribePortLocal="${subscribePort:-}"
    local email emailMd5 currentDomain account
    local publishAccounts=
    local existingMd5s='[]'
    local remoteScopeEnabled=false

    subscriptionRemoteScopeEnabled && remoteScopeEnabled=true

    SUBSCRIPTION_PUBLISH_ACCOUNTS=
    SUBSCRIPTION_PUBLISH_ACCOUNTS_HAS_REMOTE=
    if [[ -n "${publishAccountsOverride}" ]]; then
        publishAccounts=${publishAccountsOverride}
        SUBSCRIPTION_PUBLISH_ACCOUNTS_HAS_REMOTE=1
        if [[ "${remoteScopeEnabled}" == "true" ]]; then
            while IFS= read -r account; do
                [[ -n "${account}" ]] || continue
                if subscriptionPublishHasRemoteSources "${account}" 2>/dev/null; then
                    SUBSCRIPTION_PUBLISH_ACCOUNTS_HAS_REMOTE=0
                    break
                fi
            done <<<"${publishAccounts}"
        fi
    else
        if ! subscriptionPublishAccounts "${localBase}" >/dev/null 2>&1; then
            return 1
        fi
        publishAccounts=${SUBSCRIPTION_PUBLISH_ACCOUNTS:-}
    fi
    if [[ "${SUBSCRIPTION_PUBLISH_ACCOUNTS_HAS_REMOTE}" == "0" ]]; then
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

        if ! renderSubscribeUserOutputs "${email}" "${emailMd5}" "${currentDomain}" "${updateOtherSubscribeStatus:-}" "${showStatus}" "${remoteSnapshots}"; then
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
    local enabledUsers
    local localAccounts=
    local stagedAccounts=
    local publishAccounts=
    local account=
    local defaultFile
    local allowsMain
    local hasRemote
    local mainPublishSourceAvailable=false
    local remoteScopeEnabled=false

    SUBSCRIPTION_PUBLISH_ACCOUNTS_HAS_REMOTE=1
    subscriptionRemoteScopeEnabled && remoteScopeEnabled=true
    localBase=${localBase:-$(subscribeLocalBaseDir)}
    if [[ -d "${localBase}/default" ]]; then
        while IFS= read -r defaultFile; do
            [[ -n "${defaultFile}" ]] || continue
            localAccounts+="${defaultFile##*/}"$'\n'
        done < <(find "${localBase}/default" -mindepth 1 -maxdepth 1 -type f | sort)
    fi
    if subscriptionActiveGroupRead -e 'any(.sources[]?; .id == "main" and ((.enabled // true) == true))' >/dev/null 2>&1; then
        mainPublishSourceAvailable=true
    fi
    enabledUsers=$(subscriptionActiveEnabledUsersJson) || return 1
    while IFS=$'\t' read -r account allowsMain hasRemote; do
        [[ -n "${account}" ]] || continue
        if [[ "${allowsMain}" == "true" && "${mainPublishSourceAvailable}" == "true" ]]; then
            stagedAccounts+="${account}"$'\n'
            continue
        fi
        if [[ "${remoteScopeEnabled}" == "true" && "${hasRemote}" == "true" ]]; then
            SUBSCRIPTION_PUBLISH_ACCOUNTS_HAS_REMOTE=0
            stagedAccounts+="${account}"$'\n'
        fi
    done < <(subscriptionActiveGroupRead -r --argjson enabledUsers "${enabledUsers}" '
      . as $group |
      $enabledUsers[]?
      | [
          (.account // ""),
          ((.allows_main // false) | tostring),
          ((.has_remote // false) | tostring)
        ]
      | @tsv')
    publishAccounts=$(printf '%s\n%s' "${localAccounts}" "${stagedAccounts}" | awk 'length($0) > 0 && !seen[$0]++' | sed '/^$/d')
    if [[ "${remoteScopeEnabled}" == "true" && "${SUBSCRIPTION_PUBLISH_ACCOUNTS_HAS_REMOTE}" != "0" ]]; then
        while IFS= read -r account; do
            [[ -n "${account}" ]] || continue
            if subscriptionPublishHasRemoteSources "${account}"; then
                SUBSCRIPTION_PUBLISH_ACCOUNTS_HAS_REMOTE=0
                break
            fi
        done <<<"${publishAccounts}"
    fi
    SUBSCRIPTION_PUBLISH_ACCOUNTS=${publishAccounts}
    [[ -n "${publishAccounts}" ]] && printf '%s\n' "${publishAccounts}"
}

cleanupStaleSubscribeOutputs() {
    local localBase=$1
    local existingMd5s=$2
    local publicBase
    local defaultFile
    local staleMd5
    local currentMd5s='[]'
    local -a staleTargets

    publicBase=$(subscribePublicBaseDir)
    [[ -d "${publicBase}/default" ]] || return 0
    while IFS= read -r defaultFile; do
        [[ -n "${defaultFile}" ]] || continue
        currentMd5s=$(jq --arg md5 "${defaultFile##*/}" '. + [$md5]' <<<"${currentMd5s}") || return 1
    done < <(find "${publicBase}/default" -mindepth 1 -maxdepth 1 -type f | sort)

    while IFS= read -r staleMd5; do
        [[ -n "${staleMd5}" ]] || continue
        staleTargets=(
            "${publicBase}/default/${staleMd5}"
            "${publicBase}/clashMeta/${staleMd5}"
            "${publicBase}/clashMetaProfiles/${staleMd5}"
            "${publicBase}/sing-box/${staleMd5}"
            "${publicBase}/sing-box_profiles/${staleMd5}"
        )
        removeManagedFilesIfPresent "${staleTargets[@]}" || return 1
    done < <(jq -r --argjson existing "${existingMd5s}" --argjson current "${currentMd5s}" '$current - $existing | .[]' <<<"null")
}

renderSubscribeUserOutputs() {
    local email=$1
    local emailMd5=$2
    local currentDomain=$3
    local updateRemoteStatus=$4
    local showStatus=$5
    local remoteSnapshots=${6:-}
    local localBase publicBase stageDir defaultPath clashPath clashProfilePath singBoxProfilePath singBoxPath clashProxyUrl localSingBoxTemplate base64Result singBoxTmpPath clashSourcePath clashContentPath
    local localDefaultAvailable=false
    local remoteStageStatus=0
    local previousBase

    SUBSCRIBE_USER_OUTPUT_ERROR=
    localBase=$(subscribeLocalBaseDir)
    publicBase=$(subscribePublicBaseDir)
    padmCreateTmpRootPath stageDir padm-subscribe-user.XXXXXX -d || return 1
    mkdir -p "${stageDir}/default" "${stageDir}/clashMeta" "${stageDir}/clashMetaProfiles" "${stageDir}/sing-box" "${stageDir}/sing-box_profiles" || {
        padmRemoveCleanupPath "${stageDir}"
        return 1
    }

    defaultPath="${stageDir}/default/${emailMd5}"
    clashPath="${stageDir}/clashMeta/${emailMd5}"
    clashProfilePath="${stageDir}/clashMetaProfiles/${emailMd5}"
    singBoxProfilePath="${stageDir}/sing-box_profiles/${emailMd5}"
    singBoxPath="${stageDir}/sing-box/${emailMd5}"

    if [[ -f "${localBase}/default/${email}" ]]; then
        localDefaultAvailable=true
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
    if [[ -f "${localBase}/clashMeta/${email}" ]]; then
        cp "${localBase}/clashMeta/${email}" "${clashPath}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }
    fi
    if [[ -f "${localBase}/sing-box/${email}" ]]; then
        cp "${localBase}/sing-box/${email}" "${singBoxProfilePath}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }
    fi
    if [[ "${updateRemoteStatus}" == "y" ]] && subscriptionRemoteScopeEnabled; then
        remoteStageStatus=0
        PADM_SUBSCRIBE_DIR="${stageDir}" stageRemoteSubscribe "${emailMd5}" "${email}" "${remoteSnapshots}" || remoteStageStatus=$?
        if [[ "${remoteStageStatus}" -ne 0 && "${remoteStageStatus}" -ne 2 ]]; then
            padmRemoveCleanupPath "${stageDir}"
            return 1
        fi
        if [[ "${remoteStageStatus}" -eq 2 && "${localDefaultAvailable}" != "true" ]]; then
            previousBase=${PADM_SUBSCRIBE_PREVIOUS_DIR:-}
            if [[ -z "${previousBase}" ]] || ! previousBase=$(padmResolveManagedAbsolutePath "${previousBase}") ||
                [[ ! -s "${previousBase}/default/${emailMd5}" ]]; then
                padmRemoveCleanupPath "${stageDir}"
                return 1
            fi
            if ! cp "${previousBase}/default/${emailMd5}" "${defaultPath}" ||
                ! { if [[ -f "${previousBase}/clashMeta/${emailMd5}" ]]; then cp "${previousBase}/clashMeta/${emailMd5}" "${clashPath}"; else rm -f "${clashPath}"; fi; } ||
                ! { if [[ -f "${previousBase}/clashMetaProfiles/${emailMd5}" ]]; then cp "${previousBase}/clashMetaProfiles/${emailMd5}" "${clashProfilePath}"; else rm -f "${clashProfilePath}"; fi; } ||
                ! { if [[ -f "${previousBase}/sing-box_profiles/${emailMd5}" ]]; then cp "${previousBase}/sing-box_profiles/${emailMd5}" "${singBoxProfilePath}"; else rm -f "${singBoxProfilePath}"; fi; } ||
                ! { if [[ -f "${previousBase}/sing-box/${emailMd5}" ]]; then cp "${previousBase}/sing-box/${emailMd5}" "${singBoxPath}"; else rm -f "${singBoxPath}"; fi; }; then
                padmRemoveCleanupPath "${stageDir}"
                return 1
            fi
            commitSubscribeUserOutputFile "${defaultPath}" "${publicBase}/default/${emailMd5}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }
            commitSubscribeUserOutputFile "${clashPath}" "${publicBase}/clashMeta/${emailMd5}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }
            commitSubscribeUserOutputFile "${clashProfilePath}" "${publicBase}/clashMetaProfiles/${emailMd5}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }
            commitSubscribeUserOutputFile "${singBoxProfilePath}" "${publicBase}/sing-box_profiles/${emailMd5}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }
            commitSubscribeUserOutputFile "${singBoxPath}" "${publicBase}/sing-box/${emailMd5}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }
            [[ -n "${showStatus}" ]] || statusCard "订阅输出" "${email} 没有可用来源，已保留上一版输出"
            padmRemoveCleanupPath "${stageDir}"
            return 0
        fi
        if [[ -f "${localBase}/sing-box/${email}" ]]; then
            cp "${localBase}/sing-box/${email}" "${singBoxProfilePath}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }
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
    printf '%s\n' "${base64Result}" >"${defaultPath}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }

    clashSourcePath="${clashPath}"
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

    if [[ -f "${singBoxProfilePath}" ]]; then
        [[ -z "${showStatus}" ]] && statusCard "sing-box 通用配置" "正在生成 sing-box 通用配置文件"
        localSingBoxTemplate="${SCRIPT_DIR:-/etc/padm}/documents/sing-box.json"
        if [[ ! -f "${localSingBoxTemplate}" ]]; then
            padmRemoveCleanupPath "${stageDir}"
            return 1
        fi
        cp "${localSingBoxTemplate}" "${singBoxPath}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }
        padmCreateTempFileForTarget singBoxTmpPath "${singBoxPath}" singbox || { padmRemoveCleanupPath "${stageDir}"; return 1; }
        if ! jq --slurpfile localOutbounds "${singBoxProfilePath}" '
          ($localOutbounds[0] | map(.tag)) as $tags |
          .outbounds |= (map(if has("outbounds") then .outbounds += $tags else . end) + $localOutbounds[0])
        ' "${singBoxPath}" >"${singBoxTmpPath}"; then
            padmRemoveCleanupPath "${singBoxTmpPath}"
            padmRemoveCleanupPath "${stageDir}"
            return 1
        fi
        commitGeneratedJsonFile "${singBoxTmpPath}" "${singBoxPath}" || { padmRemoveCleanupPath "${singBoxTmpPath}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    fi

    commitSubscribeUserOutputFile "${defaultPath}" "${publicBase}/default/${emailMd5}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }
    commitSubscribeUserOutputFile "${clashPath}" "${publicBase}/clashMeta/${emailMd5}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }
    commitSubscribeUserOutputFile "${clashProfilePath}" "${publicBase}/clashMetaProfiles/${emailMd5}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }
    commitSubscribeUserOutputFile "${singBoxProfilePath}" "${publicBase}/sing-box_profiles/${emailMd5}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }
    commitSubscribeUserOutputFile "${singBoxPath}" "${publicBase}/sing-box/${emailMd5}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }

    padmRemoveCleanupPath "${stageDir}"
    return 0
}

# 生成并发布订阅输出
generateSubscribeOutputsUnlocked() {
    if ! readNginxSubscribe; then
        errorCard "订阅生成失败：订阅服务配置读取失败"
        return 1
    fi
    local renewSalt=$1
    local showStatus=$2
    local publishAccountsOverride=${3:-}
    local skipCleanup=${4:-}
    local remoteSnapshots=${5:-}
    if [[ "${coreInstallType}" == "1" || "${coreInstallType}" == "2" ]]; then

        echoContent title "\n┌─ 订阅生成说明 ─────────────────────────────────────"
        menuLine "查看订阅会重新生成本地账号的订阅"
        menuLine "需要手动输入 md5 加密 salt 值；不了解时直接回车随机即可"
        menuLine "不影响已添加的远程订阅内容"
        menuClose

        local localBase publicBase subscribeSaltFile backupDir previousSubscribeSalt publishStage
        localBase=$(subscribeLocalBaseDir)
        publicBase=$(padmResolveManagedAbsolutePath "$(subscribePublicBaseDir)") || return 1
        subscribeSaltFile="${localBase}/subscribeSalt"
        previousSubscribeSalt=$(readSubscribeSalt "${subscribeSaltFile}")
        if ! subscriptionSyncCreateSubscribeOutputBackups backupDir; then
            errorCard "订阅生成失败：备份旧订阅输出失败"
            return 1
        fi
        if ! padmCreateTmpRootPath publishStage padm-subscribe-publish.XXXXXX -d; then
            padmRemoveCleanupPath "${backupDir}"
            errorCard "订阅生成失败：创建发布暂存目录失败"
            return 1
        fi
        if ! mkdir -p \
            "${publishStage}/default" \
            "${publishStage}/clashMeta" \
            "${publishStage}/clashMetaProfiles" \
            "${publishStage}/sing-box" \
            "${publishStage}/sing-box_profiles"; then
            padmRemoveCleanupPath "${publishStage}"
            restoreLocalSubscribeOutputs "${localBase}" "${backupDir}" "订阅生成失败：准备发布暂存目录失败" "${previousSubscribeSalt}" true
            return 1
        fi
        if [[ "${skipCleanup}" == "true" && -d "${publicBase}" ]] && ! cp -a "${publicBase}/." "${publishStage}/"; then
            padmRemoveCleanupPath "${publishStage}"
            restoreLocalSubscribeOutputs "${localBase}" "${backupDir}" "订阅生成失败：准备发布暂存目录失败" "${previousSubscribeSalt}" true
            return 1
        fi
        if ! resolveSubscribeSalt "${subscribeSaltFile}" "${renewSalt}"; then
            padmRemoveCleanupPath "${publishStage}"
            restoreLocalSubscribeOutputs "${localBase}" "${backupDir}" "订阅 Salt 初始化失败" "${previousSubscribeSalt}" true
            return 1
        fi
        statusCard "订阅 Salt" "${subscribeSalt}"
        if ! cleanDirectoryContent "${localBase}/default" ||
            ! cleanDirectoryContent "${localBase}/clashMeta" ||
            ! cleanDirectoryContent "${localBase}/sing-box"; then
            padmRemoveCleanupPath "${publishStage}"
            restoreLocalSubscribeOutputs "${localBase}" "${backupDir}" "订阅生成失败：清理本地订阅目录失败" "${previousSubscribeSalt}" true
            return 1
        fi
        if ! showAccounts >/dev/null; then
            padmRemoveCleanupPath "${publishStage}"
            restoreLocalSubscribeOutputs "${localBase}" "${backupDir}" "订阅生成失败：重建本地订阅失败" "${previousSubscribeSalt}" true
            return 1
        fi
        if ! PADM_SUBSCRIBE_DIR="${publishStage}" PADM_SUBSCRIBE_PREVIOUS_DIR="${publicBase}" \
            renderAllSubscribeUserOutputs "${localBase}" "${renewSalt}" "${showStatus}" "${publishAccountsOverride}" "${skipCleanup}" "${remoteSnapshots}"; then
            padmRemoveCleanupPath "${publishStage}"
            restoreLocalSubscribeOutputs "${localBase}" "${backupDir}" "订阅生成失败：生成订阅输出失败" "${previousSubscribeSalt}" true
            return 1
        fi
        if ! chmod 755 \
            "${publishStage}" \
            "${publishStage}/default" \
            "${publishStage}/clashMeta" \
            "${publishStage}/clashMetaProfiles" \
            "${publishStage}/sing-box" \
            "${publishStage}/sing-box_profiles" ||
            ! syncInstallDirectoryTree "${publishStage}" "${publicBase}"; then
            padmRemoveCleanupPath "${publishStage}"
            restoreLocalSubscribeOutputs "${localBase}" "${backupDir}" "订阅生成失败：发布订阅输出失败" "${previousSubscribeSalt}" true
            return 1
        fi
        padmRemoveCleanupPath "${publishStage}"
        padmRemoveCleanupPath "${backupDir}"
    else
        errorCard "未安装传统 TLS fallback 静态站点，无法使用订阅服务"
        return 1
    fi
}

subscribeUnlocked() {
    readInstallProtocolType
    installSubscribe || return 1
    generateSubscribeOutputsUnlocked "$@"
}

subscribe() {
    subscriptionGroupsWithLock subscribeUnlocked "$@"
}

refreshPublishedSubscriptions() {
    local remoteSnapshots=${1:-}
    readInstallProtocolType
    if [[ ( -z "${remoteSnapshots}" || "${remoteSnapshots}" == "null" ) &&
        "${SUBSCRIPTION_GROUPS_LOCK_HELD:-}" != "1" ]] &&
        subscriptionRemoteScopeEnabled &&
        subscriptionHasEnabledRemoteSources; then
        runSubscriptionGroupSync
        return $?
    fi
    subscriptionGroupsWithLock generateSubscribeOutputsUnlocked false false "" "" "${remoteSnapshots}"
}


showSubscriptionUrlCard() {
    local title=$1
    local email=$2
    local url=$3
    echoContent title "\n┌─ ${title} ─────────────────────────────────────────"
    [[ -n "${email}" ]] && menuLine "账号：${email}"
    menuLine "订阅地址：${url}"
    menuClose
    if [[ "${release}" != "alpine" ]] && command -v qrencode >/dev/null 2>&1; then
        echo "${url}" | qrencode -s 10 -m 1 -t UTF8
    fi
}


# 随机订阅 salt
initRandomSalt() {
    local salt=
    if command -v openssl >/dev/null 2>&1; then
        salt=$(openssl rand -hex 16 2>/dev/null || true)
        if [[ "${salt}" =~ ^[0-9a-f]{32}$ ]]; then
            printf '%s\n' "${salt}"
            return 0
        fi
    fi
    if [[ -r /dev/urandom ]] && command -v od >/dev/null 2>&1; then
        salt=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' || true)
        if [[ "${salt}" =~ ^[0-9a-f]{32}$ ]]; then
            printf '%s\n' "${salt}"
            return 0
        fi
    fi
    return 1
}

manageRealityTarget() {
    local currentTarget selectTargetMenu targetInput sniInput selectedHost selectedSni targetAsnSummary networkMatchSummary
    while true; do
    readInstallProtocolType
    readConfigHostPathUUID || return 1
    readCustomPort
    readSingBoxConfig
    if [[ -n "${realityTargetHost:-}" ]]; then
        currentTarget=$(formatRealityTarget "${realityTargetHost}" "${realityTargetPort:-443}")
        targetAsnSummary=$(realityTargetCachedAsnSummary "${currentTarget}")
        networkMatchSummary=$(realityTargetCachedNetworkSummary "${currentTarget}")
    else
        currentTarget="未读取到"
        targetAsnSummary="未读取到目标站"
        networkMatchSummary="未读取到目标站"
    fi

    echoContent title "\n┌─ REALITY 目标站管理 ───────────────────────────────"
    menuLine "当前目标：${currentTarget}"
    menuLine "当前 SNI：${realitySNI:-未知}"
    menuLine "目标 ASN（缓存）：${targetAsnSummary}"
    menuLine "网络关系（缓存）：${networkMatchSummary}"
    menuItem 1 "检测当前目标" "复测 TLS/PQC、ASN 与网络关系，并查看证书链"
    menuItem 2 "刷新目标库" "复测目标库中的目标并更新质量结果"
    menuItem 3 "扫描指定网段" "运行 RealiTLScanner，发现目标并加入目标库"
    menuItem 4 "同 ASN 抽样扫描" "从本机 ASN 公告前缀随机抽样，发现目标并加入目标库"
    menuItem 5 "查看/切换 A 级目标" "分页查看目标库中的 A 级目标并切换"
    menuItem 6 "手动设置目标站" "输入 host[:port] 和可选 SNI"
    menuItem 7 "查看目标站黑名单" "显示不会参与目标库刷新或扫描导入的目标"
    menuItem 8 "查看 PQC/ML-DSA-65 状态" "显示 ML-DSA-65 验证值与目标站评分"
    menuItem 9 "复测全部候选" "复测全部内置/托管候选并更新目标库，耗时较长"
    menuReturnItem 10 "返回" "回到 REALITY 管理"
    menuClose
    autoRead reality_target_manage_menu "请选择：" selectTargetMenu
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
        autoRead reality_target "请输入 REALITY 伪装目标 host[:port]：" targetInput
        [[ -n "${targetInput}" ]] || return 1
        autoRead reality_server_name "请输入 SNI[回车默认等于目标 host]：" sniInput
        changeInstalledRealityTarget "${targetInput}" "${sniInput}"
        ;;
    7)
        showRealityTargetBlockedCandidates
        ;;
    8)
        showRealityTargetPqcStatus
        ;;
    9)
        scanLocalAsnRealityTargets all || true
        ;;
    10)
        return 0
        ;;
    *)
        coreSelectionErrorCard "选择错误"
        ;;
    esac
    done
}

# reality管理
regenerateRealityProfile() {
    if [[ "${coreInstallType}" == "1" ]]; then
        selectCustomInstallType=",1,"
        initXrayConfig custom 1 true || return 1
    elif [[ "${coreInstallType}" == "2" ]]; then
        if currentProtocolHas 1; then
            selectCustomInstallType=",1,"
        fi
        if currentProtocolHas 26; then
            selectCustomInstallType="${selectCustomInstallType},26,"
        fi
        initSingBoxConfig custom 1 true || return 1
    fi

    reloadCore || return 1
    subscribe false || return 1
}

manageReality() {
    while true; do
    readInstallProtocolType
    readConfigHostPathUUID || return 1
    readCustomPort
    readSingBoxConfig

    if ! currentProtocolHasAny 1 2 26 || [[ -z "${coreInstallType}" ]]; then
        errorCard "请先安装 Reality 协议。新人路径：主菜单 -> 安装与重装 -> 无域名 Reality，或 安装与重装 -> 自定义安装 中选择 Reality 编号"
        exit 0
    fi

    echoContent title "\n┌─ REALITY 管理 ─────────────────────────────────────"
    menuItem 1 "重新生成 Reality 参数" "更新 key、shortId 等 Reality 参数"
    menuItem 2 "目标站管理" "查看、检测或切换 Reality 伪装目标"
    menuItem 3 "配置 443 共存分流" "同机真实网站与 Reality 共用公网 443"
    menuItem 4 "查看当前分流状态" "检查 state、Nginx stream 与后端监听"
    menuItem 5 "关闭 443 共存分流" "恢复 Reality 原入口端口并清理分流配置"
    menuReturnItem 6 "返回协议与入口" "回到上级菜单"
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
    6)
        protocolEntryMenu
        return 0
        ;;
    *)
        coreSelectionErrorCard "选择错误"
        ;;
    esac
    done
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
    refreshProtocolSubscriptions XHTTP "已刷新公网订阅" "已刷新本地订阅"
}

configTransactionCommit() {
    local configFile=$1
    local stagedFile=$2
    local backupFile=$3
    local validateFn=$4
    local failureTitle=$5
    local rollbackMessage=$6
    local successMessage=$7
    local refreshFn=$8
    local reloadFn=${9:-reloadCore}

    configFile=$(padmRequireSafeAbsolutePath "${configFile}") || return 1
    backupManagedFileToPath "${configFile}" "${backupFile}" 644 || return 1
    if ! commitGeneratedJsonFile "${stagedFile}" "${configFile}"; then
        removeManagedFilesIfPresentIgnoreFailure "${backupFile}"
        padmRemoveCleanupPath "${stagedFile}"
        return 1
    fi
    if ! "${validateFn}"; then
        if restoreManagedFileFromBackup "${backupFile}" "${configFile}" 644; then
            removeManagedFilesIfPresentIgnoreFailure "${backupFile}"
            padmRemoveCleanupPath "${stagedFile}"
            "${validateFn}" >/dev/null 2>&1 || true
            echoContent title "\n┌─ ${failureTitle} ────────────────────────────────"
            menuLine "${rollbackMessage}"
            menuClose
        else
            padmRemoveCleanupPath "${stagedFile}"
            echoContent title "\n┌─ ${failureTitle} ────────────────────────────────"
            local validateFailureMessage
            coreSetPairedFileManualCheckMessage validateFailureMessage "配置校验失败，且回滚配置失败" "${configFile}" "${backupFile}"
            menuLine "${validateFailureMessage}"
            menuClose
        fi
        return 1
    fi
    if ! "${reloadFn}"; then
        if restoreManagedFileFromBackup "${backupFile}" "${configFile}" 644; then
            removeManagedFilesIfPresentIgnoreFailure "${backupFile}"
            padmRemoveCleanupPath "${stagedFile}"
            echoContent title "\n┌─ 核心重载失败 ────────────────────────────────"
            local rollbackMessage
            coreSetRollbackResultMessage rollbackMessage "核心重载失败" "已回滚本次修改" "${reloadFn}" "恢复旧配置后重载仍失败，请检查核心服务日志"
            menuLine "${rollbackMessage#核心重载失败，}"
            menuClose
        else
            padmRemoveCleanupPath "${stagedFile}"
            echoContent title "\n┌─ 核心重载失败 ────────────────────────────────"
            local reloadFailureMessage
            coreSetPairedFileManualCheckMessage reloadFailureMessage "核心重载失败，且回滚配置失败" "${configFile}" "${backupFile}"
            menuLine "${reloadFailureMessage}"
            menuClose
        fi
        return 1
    fi
    removeManagedFilesIfPresentIgnoreFailure "${backupFile}"
    if ! "${refreshFn}"; then
        echoContent title "\n┌─ 订阅刷新失败 ────────────────────────────────"
        menuLine "核心配置已更新，但订阅刷新失败，请手动刷新订阅"
        menuClose
        return 1
    fi
    successCard "${successMessage}"
}

validateXHTTPConfigUpdate() {
    local xrayBinary
    local xrayConfigDir
    xrayBinary=$(manageXrayBinaryPath)
    xrayConfigDir=$(manageXrayConfigDir)
    [[ -x "${xrayBinary}" ]] || return 0
    "${xrayBinary}" -test -confdir "${xrayConfigDir}" >"$(xhttpConfigTestLog)" 2>&1
}

xhttpConfigTestLog() {
    padmTmpFilePath padm-xhttp-test.log
}

commitXHTTPConfigUpdate() {
    local stagedFile=$1
    local successMessage=$2
    local configFile backupFile
    configFile=$(manageXHTTPConfigFile)
    configFile=$(padmResolveManagedAbsolutePath "${configFile}") || { padmRemoveCleanupPath "${stagedFile}"; return 1; }
    if [[ "${coreInstallType}" != "1" || ! -f "${configFile}" ]]; then
        errorCard "未检测到 Xray Reality XHTTP 配置，请先安装 2.VLESS Reality XHTTP"
        padmRemoveCleanupPath "${stagedFile}"
        return 1
    fi
    backupFile="${configFile}.xhttp.bak"
    configTransactionCommit "${configFile}" "${stagedFile}" "${backupFile}" validateXHTTPConfigUpdate "XHTTP 配置校验失败" "已回滚本次 XHTTP 修改；排查日志：$(xhttpConfigTestLog)" "${successMessage}" refreshXHTTPSubscriptions
}

applyManagedJsonConfigUpdate() {
    local configFile=$1 stageTag=$2 errorMessage=$3 commitFn=$4 jqFilter=$5 successMessage=$6
    local stagedFile
    padmCreateTempFileForTarget stagedFile "${configFile}" "${stageTag}" || { errorCard "${errorMessage}"; return 1; }
    if ! jq "${jqFilter}" "${configFile}" >"${stagedFile}"; then
        errorCard "${errorMessage}"
        padmRemoveCleanupPath "${stagedFile}"
        return 1
    fi
    "${commitFn}" "${stagedFile}" "${successMessage}"
}

applyXHTTPConfigUpdate() {
    local configFile
    configFile=$(manageXHTTPConfigFile) || return 1
    applyManagedJsonConfigUpdate "${configFile}" xhttp "写入 XHTTP 配置失败，已取消" commitXHTTPConfigUpdate "$@"
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
    if [[ "${input}" =~ ^[0-9]{1,10}$ ]]; then
        from=${input}
        to=${input}
    elif [[ "${input}" =~ ^([0-9]{1,10})-([0-9]{1,10})$ ]]; then
        from=${BASH_REMATCH[1]}
        to=${BASH_REMATCH[2]}
    else
        errorCard "范围格式错误，应为数字或 from-to"
        return 1
    fi
    if ((10#${to} < 10#${from})); then
        errorCard "范围不合法"
        return 1
    fi
    printf '%s %s' "${from}" "${to}"
}

setXHTTPCustomXmux() {
    local concurrency requestTimes reusableSecs concurrencyFrom concurrencyTo requestFrom requestTo reusableFrom reusableTo configFile stagedFile
    concurrency=$(readXHTTPRange "请输入 maxConcurrency 范围" 16 32) || return 1
    requestTimes=$(readXHTTPRange "请输入 hMaxRequestTimes 范围" 600 900) || return 1
    reusableSecs=$(readXHTTPRange "请输入 hMaxReusableSecs 范围" 1800 3000) || return 1
    read -r concurrencyFrom concurrencyTo <<<"${concurrency}"
    read -r requestFrom requestTo <<<"${requestTimes}"
    read -r reusableFrom reusableTo <<<"${reusableSecs}"
    if ((10#${concurrencyFrom} < 1)); then
        errorCard "maxConcurrency 必须大于 0"
        return 1
    fi
    if ((10#${requestTo} > 1000)); then
        echoContent title "\n┌─ XHTTP XMUX 提醒 ──────────────────────────────────"
        menuLine "hMaxRequestTimes 超过 1000 可能触发部分 Nginx/CDN 限制"
        menuClose
    fi
    if ((10#${reusableTo} > 3600)); then
        echoContent title "\n┌─ XHTTP XMUX 提醒 ──────────────────────────────────"
        menuLine "hMaxReusableSecs 超过 3600 可能触发部分中间盒旧连接清理"
        menuClose
    fi
    configFile=$(manageXHTTPConfigFile)
    padmCreateTempFileForTarget stagedFile "${configFile}" xhttp || { errorCard "写入 XHTTP XMUX 失败"; return 1; }
    if ! jq --arg concurrency "${concurrencyFrom}-${concurrencyTo}" --arg requestTimes "${requestFrom}-${requestTo}" --arg reusableSecs "${reusableFrom}-${reusableTo}" '.inbounds[0].streamSettings.xhttpSettings.xmux = {"maxConcurrency":$concurrency,"hMaxRequestTimes":$requestTimes,"hMaxReusableSecs":$reusableSecs}' "${configFile}" >"${stagedFile}"; then
        errorCard "写入 XHTTP XMUX 失败"
        padmRemoveCleanupPath "${stagedFile}"
        return 1
    fi
    commitXHTTPConfigUpdate "${stagedFile}" "XHTTP XMUX 自定义范围已应用"
}

setXHTTPPathHost() {
    local configFile currentPath currentHost newPath newHost stagedFile
    configFile=$(manageXHTTPConfigFile)
    currentPath=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.path // ""' "${configFile}" 2>/dev/null)
    currentHost=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.host // ""' "${configFile}" 2>/dev/null)
    autoRead xhttp_path "请输入 XHTTP path，[回车保持 ${currentPath}]:" newPath
    newPath=${newPath:-${currentPath}}
    if ! padmIsSafeRoutePath "${newPath}"; then
        errorCard "path 不合法"
        return 1
    fi
    autoRead xhttp_host "请输入 XHTTP host，[回车保持 ${currentHost}]:" newHost
    newHost=${newHost:-${currentHost}}
    if ! padmIsValidHostName "${newHost}"; then
        errorCard "host 不合法"
        return 1
    fi
    echoContent title "\n┌─ XHTTP path/host 提醒 ─────────────────────────────"
    menuLine "通常建议 host 与 Reality SNI 保持一致"
    menuLine "仅 CDN 域前置或特殊反代场景才需要改"
    menuClose
    padmCreateTempFileForTarget stagedFile "${configFile}" xhttp || { errorCard "写入 XHTTP path/host 失败"; return 1; }
    if ! jq --arg path "${newPath}" --arg host "${newHost}" '.inbounds[0].streamSettings.xhttpSettings.path = $path | .inbounds[0].streamSettings.xhttpSettings.host = $host' "${configFile}" >"${stagedFile}"; then
        errorCard "写入 XHTTP path/host 失败"
        padmRemoveCleanupPath "${stagedFile}"
        return 1
    fi
    commitXHTTPConfigUpdate "${stagedFile}" "XHTTP path/host 已更新"
}

setXHTTPAdvancedParams() {
    local configFile padding maxPost minInterval maxBuffered streamSecs noGrpc noSse pf pt sf st stagedFile
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
    padmCreateTempFileForTarget stagedFile "${configFile}" xhttp || { errorCard "写入 XHTTP 高级参数失败"; return 1; }
    if ! jq --arg padding "${pf}-${pt}" --argjson maxPost "${maxPost}" --argjson minInterval "${minInterval}" --argjson maxBuffered "${maxBuffered}" --arg streamSecs "${sf}-${st}" --argjson noGrpc "$([[ "${noGrpc}" == "y" ]] && echo true || echo false)" --argjson noSse "$([[ "${noSse}" == "y" ]] && echo true || echo false)" '.inbounds[0].streamSettings.xhttpSettings.xPaddingBytes = $padding | .inbounds[0].streamSettings.xhttpSettings.scMaxEachPostBytes = $maxPost | .inbounds[0].streamSettings.xhttpSettings.scMinPostsIntervalMs = $minInterval | .inbounds[0].streamSettings.xhttpSettings.scMaxBufferedPosts = $maxBuffered | .inbounds[0].streamSettings.xhttpSettings.scStreamUpServerSecs = $streamSecs | .inbounds[0].streamSettings.xhttpSettings.noGRPCHeader = $noGrpc | .inbounds[0].streamSettings.xhttpSettings.noSSEHeader = $noSse' "${configFile}" >"${stagedFile}"; then
        errorCard "写入 XHTTP 高级参数失败"
        padmRemoveCleanupPath "${stagedFile}"
        return 1
    fi
    commitXHTTPConfigUpdate "${stagedFile}" "XHTTP 高级参数已更新"
}

setXHTTPDownloadSettings() {
    local configFile address port security serverName host path alpn mode publicKey shortId stagedFile
    configFile=$(manageXHTTPConfigFile)
    echoContent title "\n┌─ XHTTP 上下行分离风险 ─────────────────────────────"
    menuLine "上下行分离属于高级功能"
    menuLine "下行配置完全独立，填错会导致连接失败"
    menuClose
    autoRead xhttp_download_address "请输入下行入口 address/IP/域名:" address
    padmIsValidConnectAddress "${address}" || { errorCard "address 不合法"; return 1; }
    autoRead xhttp_download_port "请输入下行入口端口[回车默认 443]:" port
    port=${port:-443}
    validPortNumber "${port}" || { errorCard "端口不合法"; return 1; }
    autoRead xhttp_download_security "请输入下行 security[tls/reality，回车默认 tls]:" security
    security=${security:-tls}
    [[ "${security}" == "tls" || "${security}" == "reality" ]] || { errorCard "security 仅支持 tls 或 reality"; return 1; }
    autoRead xhttp_download_server_name "请输入下行 serverName/SNI[回车默认当前 Reality SNI]:" serverName
    serverName=${serverName:-$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // ""' "${configFile}" 2>/dev/null)}
    autoRead xhttp_download_host "请输入下行 XHTTP host[回车默认 ${serverName}]:" host
    host=${host:-${serverName}}
    autoRead xhttp_download_path "请输入下行 XHTTP path[回车默认沿用当前 path]:" path
    path=${path:-$(jq -r '.inbounds[0].streamSettings.xhttpSettings.path // ""' "${configFile}" 2>/dev/null)}
    padmIsValidHostName "${serverName}" || { errorCard "serverName 不合法"; return 1; }
    padmIsValidHostName "${host}" || { errorCard "host 不合法"; return 1; }
    padmIsSafeRoutePath "${path}" || { errorCard "path 不合法"; return 1; }
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
    padmCreateTempFileForTarget stagedFile "${configFile}" xhttp || { errorCard "写入 XHTTP 上下行分离配置失败"; return 1; }
    if ! jq --arg address "${address}" --argjson port "${port}" --arg security "${security}" --arg serverName "${serverName}" --arg host "${host}" --arg path "${path}" --arg alpn "${alpn}" --arg mode "${mode}" --arg publicKey "${publicKey}" --arg shortId "${shortId}" '.inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings = {"address":$address,"port":$port,"network":"xhttp","security":$security,"xhttpSettings":{"host":$host,"path":$path,"mode":$mode}} | if $security == "reality" then .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.realitySettings = {"serverName":$serverName,"fingerprint":"chrome","show":false,"publicKey":$publicKey,"shortId":$shortId,"spiderX":"/"} else .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.tlsSettings = {"serverName":$serverName,"alpn":[$alpn],"fingerprint":"chrome"} end' "${configFile}" >"${stagedFile}"; then
        errorCard "写入 XHTTP 上下行分离配置失败"
        padmRemoveCleanupPath "${stagedFile}"
        return 1
    fi
    commitXHTTPConfigUpdate "${stagedFile}" "XHTTP 上下行分离配置已启用"
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
    *) coreSelectionRetryAction manageXHTTPPresets ;;
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
    *) coreSelectionRetryAction manageXHTTPMode ;;
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
    *) coreSelectionRetryAction manageXHTTPXmux ;;
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
        coreSelectionRetryAction manageXHTTPNormal
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
        coreSelectionRetryAction manageXHTTPAdvanced
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
        coreSelectionRetryAction manageXHTTPExperiment
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
    if [[ "${coreInstallType}" != "1" ]] || ! currentProtocolHas 2; then
        errorCard "请先安装 Xray 的 2.VLESS Reality XHTTP"
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
        coreSelectionRetryAction manageXHTTP
        ;;
    esac
}


# hysteria管理
manageHysteria() {
    local hysteria2Status installHysteria2Status
    while true; do
        hysteria2Status=
        echoContent title "\n┌─ Hysteria2 管理 ───────────────────────────────────"
        menuLine "依赖 sing-box 内核；适合 UDP、移动网络场景"
        if [[ -n "${singBoxConfigPath}" ]] && [[ -f "/etc/padm/sing-box/conf/config/06_hysteria2_inbounds.json" ]]; then
            menuItem 1 "重新安装" "重建 Hysteria2 入站配置"
            menuItem 2 "卸载" "移除 Hysteria2 入站配置"
            menuItem 3 "端口跳跃管理" "配置 UDP 端口跳跃转发"
            menuReturnItem 4 "返回协议与入口" "回到上级菜单"
            hysteria2Status=true
        else
            menuItem 1 "安装" "新增 Hysteria2 入站配置"
            menuReturnItem 2 "返回协议与入口" "回到上级菜单"
        fi

        menuClose
        installHysteria2Status=
        autoRead hysteria_menu "请选择:" installHysteria2Status || return 0
        if [[ "${installHysteria2Status}" == "1" ]]; then
            singBoxHysteria2Install || true
        elif [[ "${installHysteria2Status}" == "2" && "${hysteria2Status}" == "true" ]]; then
            unInstallSingBox hysteria2 || true
        elif [[ "${installHysteria2Status}" == "3" && "${hysteria2Status}" == "true" ]]; then
            portHoppingMenu hysteria2 || true
        elif [[ ( "${installHysteria2Status}" == "4" && "${hysteria2Status}" == "true" ) || ( "${installHysteria2Status}" == "2" && "${hysteria2Status}" != "true" ) ]]; then
            return 0
        else
            coreSelectionErrorCard "选择错误"
        fi
    done
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
    refreshProtocolSubscriptions Tuic "已刷新公网订阅" "已刷新本地订阅"
}

validateTuicConfigUpdate() {
    [[ -x /etc/padm/sing-box/sing-box ]] || return 0
    singBoxMergeConfigForValidation /etc/padm/sing-box/sing-box "$(tuicConfigTestLog)"
}

tuicConfigTestLog() {
    padmTmpFilePath padm-tuic-test.log
}

commitTuicConfigUpdate() {
    local stagedFile=$1
    local successMessage=$2
    local configFile backupFile
    configFile=$(tuicConfigFile)
    configFile=$(padmResolveManagedAbsolutePath "${configFile}") || { padmRemoveCleanupPath "${stagedFile}"; return 1; }
    if [[ ! -f "${configFile}" ]]; then
        errorCard "未检测到 Tuic 配置，请先安装 Tuic"
        padmRemoveCleanupPath "${stagedFile}"
        return 1
    fi
    backupFile="${configFile}.tuic.bak"
    configTransactionCommit "${configFile}" "${stagedFile}" "${backupFile}" validateTuicConfigUpdate "Tuic 配置校验失败" "已回滚本次 Tuic 修改；排查日志：$(tuicConfigTestLog)" "${successMessage}" refreshTuicSubscriptions
}

applyTuicConfigUpdate() {
    local configFile
    configFile=$(tuicConfigFile) || return 1
    applyManagedJsonConfigUpdate "${configFile}" tuic "写入 Tuic 配置失败，已取消" commitTuicConfigUpdate "$@"
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
    local authTimeout heartbeat configFile stagedFile
    authTimeout=$(readTuicDuration "请输入认证超时时间 auth_timeout" "3s") || return 1
    heartbeat=$(readTuicDuration "请输入心跳间隔 heartbeat" "10s") || return 1
    configFile=$(tuicConfigFile)
    padmCreateTempFileForTarget stagedFile "${configFile}" tuic || { errorCard "写入 Tuic 连接参数失败"; return 1; }
    if ! jq --arg authTimeout "${authTimeout}" --arg heartbeat "${heartbeat}" '.inbounds[0].auth_timeout = $authTimeout | .inbounds[0].heartbeat = $heartbeat' "${configFile}" >"${stagedFile}"; then
        errorCard "写入 Tuic 连接参数失败"
        padmRemoveCleanupPath "${stagedFile}"
        return 1
    fi
    commitTuicConfigUpdate "${stagedFile}" "Tuic 连接参数已更新"
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
    local selectTuicCongestion=
    while true; do
        echoContent title "\n┌─ Tuic 拥塞控制 ────────────────────────────────────"
        menuLine "sing-box 默认 cubic；bbr 可在高带宽或长距离链路手动尝试"
        menuRecommendedItem 1 "cubic" "默认推荐"
        menuItem 2 "bbr" "高带宽/长距离链路可试"
        menuItem 3 "new_reno" "兼容保守"
        menuReturnItem 4 "返回" "回到 Tuic 管理"
        menuClose
        selectTuicCongestion=
        autoRead tuic_congestion_menu "请选择:" selectTuicCongestion || return 0
        case "${selectTuicCongestion}" in
        1) setTuicCongestionControl cubic || true ;;
        2) setTuicCongestionControl bbr || true ;;
        3) setTuicCongestionControl new_reno || true ;;
        4) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

manageTuicAdvanced() {
    local selectTuicAdvanced=
    while true; do
        echoContent title "\n┌─ Tuic 高级设置 ────────────────────────────────────"
        menuLine "高级参数直接写入 sing-box Tuic inbound，写入后会 merge 校验并 reload"
        menuItem 1 "连接参数" "设置 auth_timeout 与 heartbeat"
        menuDangerItem 2 "启用 0-RTT" "减少握手但增加重放风险"
        menuRecommendedItem 3 "关闭 0-RTT" "恢复上游推荐的安全默认值"
        menuRecommendedItem 4 "恢复推荐默认值" "cubic、3s、10s、0-RTT 关闭"
        menuReturnItem 5 "返回 Tuic 管理" "回到上级菜单"
        menuClose
        selectTuicAdvanced=
        autoRead tuic_advanced_menu "请选择:" selectTuicAdvanced || return 0
        case "${selectTuicAdvanced}" in
        1) setTuicConnectionParams || true ;;
        2) setTuicZeroRtt true || true ;;
        3) setTuicZeroRtt false || true ;;
        4) setTuicRecommendedDefaults || true ;;
        5) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

manageTuic() {
    local tuicStatus installTuicStatus
    while true; do
        tuicStatus=
        echoContent title "\n┌─ Tuic 管理 ────────────────────────────────────────"
        menuLine "依赖 sing-box 内核；适合 UDP、移动网络或 QUIC/HTTP3 客户端场景"
        menuLine "不作为新人默认推荐"
        if [[ -n "${singBoxConfigPath}" ]] && [[ -f "/etc/padm/sing-box/conf/config/09_tuic_inbounds.json" ]]; then
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
            menuItem 1 "安装" "新增 Tuic 入站配置"
            menuReturnItem 2 "返回协议与入口" "回到上级菜单"
        fi

        menuClose
        installTuicStatus=
        autoRead tuic_menu "请选择:" installTuicStatus || return 0
        if [[ "${installTuicStatus}" == "1" ]]; then
            singBoxTuicInstall || true
        elif [[ "${installTuicStatus}" == "2" && "${tuicStatus}" == "true" ]]; then
            unInstallSingBox tuic || true
        elif [[ "${installTuicStatus}" == "3" && "${tuicStatus}" == "true" ]]; then
            portHoppingMenu tuic || true
        elif [[ "${installTuicStatus}" == "4" && "${tuicStatus}" == "true" ]]; then
            manageTuicCongestionControl || true
        elif [[ "${installTuicStatus}" == "5" && "${tuicStatus}" == "true" ]]; then
            manageTuicAdvanced || true
        elif [[ "${installTuicStatus}" == "6" && "${tuicStatus}" == "true" ]]; then
            setTuicRecommendedDefaults || true
        elif [[ ( "${installTuicStatus}" == "7" && "${tuicStatus}" == "true" ) || ( "${installTuicStatus}" == "2" && "${tuicStatus}" != "true" ) ]]; then
            return 0
        else
            coreSelectionErrorCard "选择错误"
        fi
    done
}
