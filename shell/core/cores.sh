#!/usr/bin/env bash

# 清理 Xray geo 数据文件
cleanXrayGeoFiles() {
    local targetDir=$1
    rm -f "${targetDir}/geosite.dat" "${targetDir}/geoip.dat" "${targetDir}/geo.version" >/dev/null 2>&1
}

ensureXrayGeoFiles() {
    local targetDir=$1
    local force=${2:-}

    if [[ "${force}" != "force" && -s "${targetDir}/geosite.dat" && -s "${targetDir}/geoip.dat" ]]; then
        return 0
    fi

    local geoVersion
    geoVersion=$(curl -s https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases?per_page=1 | jq -r '.[]|.tag_name')
    checkVersionNotEmpty "${geoVersion}"
    echoContent title "\n┌─ Geo 数据版本 ─────────────────────────────────────"
    menuLine "version:${geoVersion}"
    menuClose
    cleanXrayGeoFiles "${targetDir}"

    if ! downloadGitHubReleaseAsset -P "${targetDir}/" Loyalsoldier/v2ray-rules-dat "${geoVersion}" geosite.dat || ! downloadGitHubReleaseAsset -P "${targetDir}/" Loyalsoldier/v2ray-rules-dat "${geoVersion}" geoip.dat; then
        errorCard "geo文件下载失败"
        return 1
    fi
    printf '%s\n' "${geoVersion}" >"${targetDir}/geo.version"
}

xrayGeoDisplayVersion() {
    local targetDir=${1:-/etc/padm/xray}
    if [[ -s "${targetDir}/geo.version" ]]; then
        printf '版本 %s' "$(tr -d '\r\n' <"${targetDir}/geo.version")"
        return
    fi
    if [[ -s "${targetDir}/geosite.dat" || -s "${targetDir}/geoip.dat" ]]; then
        local newest=0 file mtime
        for file in "${targetDir}/geosite.dat" "${targetDir}/geoip.dat"; do
            [[ -e "${file}" ]] || continue
            mtime=$(stat -c %Y "${file}" 2>/dev/null || stat -f %m "${file}" 2>/dev/null || printf '0')
            [[ ${mtime} =~ ^[0-9]+$ ]] || mtime=0
            ((mtime > newest)) && newest=${mtime}
        done
        if ((newest > 0)); then
            date -d "@${newest}" '+更新时间 %Y-%m-%d' 2>/dev/null || date -r "${newest}" '+更新时间 %Y-%m-%d' 2>/dev/null || printf '版本未知'
            return
        fi
    fi
    printf '版本未知'
}

# 安装 sing-box
installSingBox() {
    readInstallType
    progressCard "$1" "安装 sing-box"

    if [[ ! -f "/etc/padm/sing-box/sing-box" ]]; then

        version=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases?per_page=20" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        checkVersionNotEmpty "${version}"

        successCard "最新版本:${version}"

        if ! downloadGitHubReleaseAsset -P /etc/padm/sing-box/ SagerNet/sing-box "${version}" "sing-box-${version/v/}${singBoxCoreCPUVendor}.tar.gz"; then
            errorCard "sing-box下载失败"
            exit 1
        fi

        if [[ ! -f "/etc/padm/sing-box/sing-box-${version/v/}${singBoxCoreCPUVendor}.tar.gz" ]]; then
            autoRead core_download_retry "核心下载失败，请重新尝试安装，是否重新尝试？[y/n]" downloadStatus
            if [[ "${downloadStatus}" == "y" ]]; then
                installSingBox "$1"
            fi
        else

            if ! tar zxvf "/etc/padm/sing-box/sing-box-${version/v/}${singBoxCoreCPUVendor}.tar.gz" -C "/etc/padm/sing-box/" >/dev/null 2>&1; then
                errorCard "sing-box解压失败"
                exit 1
            fi

            if ! mv "/etc/padm/sing-box/sing-box-${version/v/}${singBoxCoreCPUVendor}/sing-box" /etc/padm/sing-box/sing-box; then
                errorCard "sing-box安装失败"
                exit 1
            fi
            rm -rf /etc/padm/sing-box/sing-box-*
            chmod 655 /etc/padm/sing-box/sing-box
        fi
    else
        successCard "当前版本:v$(/etc/padm/sing-box/sing-box version | grep "sing-box version" | awk '{print $3}')"

        version=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases?per_page=20" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        successCard "最新版本:${version}"

        if [[ -z "${lastInstallationConfig}" ]]; then
            autoRead singbox_reinstall "是否更新、升级？[y/n]:" reInstallSingBoxStatus
            if [[ "${reInstallSingBoxStatus}" == "y" ]]; then
                rm -f /etc/padm/sing-box/sing-box
                installSingBox "$1"
            fi
        fi
    fi

}


# 安装 Xray-core
installXray() {
    readInstallType
    local prereleaseStatus=false
    if [[ "$2" == "true" ]]; then
        prereleaseStatus=true
    fi

    progressCard "$1" "安装 Xray"

    if [[ ! -f "/etc/padm/xray/xray" ]]; then

        version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=100" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        checkVersionNotEmpty "${version}"
        successCard "Xray-core版本:${version}"
        if ! downloadGitHubReleaseAsset -P /etc/padm/xray/ XTLS/Xray-core "${version}" "${xrayCoreCPUVendor}.zip"; then
            errorCard "Xray-core下载失败"
            exit 1
        fi

        if [[ ! -f "/etc/padm/xray/${xrayCoreCPUVendor}.zip" ]]; then
            autoRead core_download_retry "核心下载失败，请重新尝试安装，是否重新尝试？[y/n]" downloadStatus
            if [[ "${downloadStatus}" == "y" ]]; then
                installXray "$1"
            fi
        else
            if ! unzip -o "/etc/padm/xray/${xrayCoreCPUVendor}.zip" -d /etc/padm/xray >/dev/null; then
                errorCard "Xray-core解压失败"
                exit 1
            fi
            rm -rf "/etc/padm/xray/${xrayCoreCPUVendor}.zip"

            if ! ensureXrayGeoFiles /etc/padm/xray force; then
                exit 1
            fi

            chmod 655 /etc/padm/xray/xray
        fi
    else
        if [[ -z "${lastInstallationConfig}" ]]; then
            successCard "Xray-core版本:$(/etc/padm/xray/xray --version | awk '{print $2}' | head -1)"
            if ! ensureXrayGeoFiles /etc/padm/xray; then
                exit 1
            fi
            autoRead xray_reinstall "是否更新、升级？[y/n]:" reInstallXrayStatus
            if [[ "${reInstallXrayStatus}" == "y" ]]; then
                rm -f /etc/padm/xray/xray
                installXray "$1" "$2"
            fi
        fi
    fi
}


# Core lifecycle helpers
coreReleaseTags() {
    local repo=$1
    local prerelease=${2:-false}
    local limit=${3:-20}
    curl -fsSL --connect-timeout 10 --max-time 30 "https://api.github.com/repos/${repo}/releases?per_page=100" | jq -r ".[] | select(.prerelease==${prerelease}) | .tag_name" | head -n "${limit}"
}

coreLatestReleaseTag() {
    local repo=$1
    local prerelease=${2:-false}
    coreReleaseTags "${repo}" "${prerelease}" 1
}

xrayInstalled() {
    [[ -x "$(coreXrayBinaryPath)" ]]
}

singBoxInstalled() {
    [[ -x "$(coreSingBoxBinaryPath)" ]]
}

coreXrayBinaryPath() {
    printf '%s\n' "${PADM_XRAY_BINARY:-/etc/padm/xray/xray}"
}

coreSingBoxBinaryPath() {
    printf '%s\n' "${PADM_SINGBOX_BINARY:-/etc/padm/sing-box/sing-box}"
}

getXrayCurrentVersion() {
    if xrayInstalled; then
        "$(coreXrayBinaryPath)" --version 2>/dev/null | awk 'NR==1 {print "v"$2}'
    else
        echo "未安装"
    fi
}

getSingBoxCurrentVersion() {
    if singBoxInstalled; then
        "$(coreSingBoxBinaryPath)" version 2>/dev/null | awk '/sing-box version/ {print "v"$3; exit}'
    else
        echo "未安装"
    fi
}

coreServiceState() {
    local serviceName=$1
    local runningFn=$2
    if "${runningFn}"; then
        echo "运行中"
    elif [[ -f "/etc/systemd/system/${serviceName}.service" || -f "/etc/init.d/${serviceName}" ]]; then
        echo "已停止"
    else
        echo "未安装服务"
    fi
}

validateXrayConfigWithBinary() {
    local binary=${1:-/etc/padm/xray/xray}
    local logFile=${2:-$(coreXrayConfigTestLog)}
    [[ -x "${binary}" ]] || return 1
    [[ -d /etc/padm/xray/conf ]] || return 1
    "${binary}" -test -confdir /etc/padm/xray/conf >"${logFile}" 2>&1
}

coreTmpFilePath() {
    local fileName=$1
    if declare -F padmTmpFilePath >/dev/null 2>&1; then
        padmTmpFilePath "${fileName}"
    else
        local tmpBase="${TMPDIR:-/tmp}"
        printf '%s\n' "${tmpBase%/}/${fileName}"
    fi
}

coreXrayConfigTestLog() {
    coreTmpFilePath padm-core-xray-test.log
}

coreXrayUpgradeTestLog() {
    coreTmpFilePath padm-core-xray-upgrade-test.log
}

coreSingBoxConfigTestLog() {
    coreTmpFilePath padm-core-sing-box-test.log
}

coreSingBoxUpgradeTestLog() {
    coreTmpFilePath padm-core-sing-box-upgrade-test.log
}

coreAlpineInitTemplate() {
    local serviceName=$1
    coreTmpFilePath "padm-${serviceName}.init.XXXXXX"
}

coreSingBoxServiceTemplate() {
    coreTmpFilePath padm-sing-box.service.XXXXXX
}

coreXrayServiceTemplate() {
    coreTmpFilePath padm-xray.service.XXXXXX
}

singBoxConfigInstalled() {
    [[ -s /etc/padm/sing-box/conf/config.json ]] || compgen -G "/etc/padm/sing-box/conf/config/*.json" >/dev/null
}

validateSingBoxConfigWithBinary() {
    local binary=${1:-/etc/padm/sing-box/sing-box}
    local logFile=${2:-$(coreSingBoxConfigTestLog)}
    [[ -x "${binary}" ]] || return 1
    singBoxConfigInstalled || return 2
    "${binary}" merge config.json -C /etc/padm/sing-box/conf/config/ -D /etc/padm/sing-box/conf/ >"${logFile}" 2>&1 || { appendSingBoxCompatibilityHints "${logFile}"; return 1; }
    "${binary}" check -c /etc/padm/sing-box/conf/config.json >>"${logFile}" 2>&1 || { appendSingBoxCompatibilityHints "${logFile}"; return 1; }
}

appendSingBoxCompatibilityHints() {
    local logFile=$1
    [[ -f "${logFile}" ]] || return 0
    if grep -Eqi 'legacy DNS servers|legacy special outbounds|legacy domain strategy|domain_resolver|default_domain_resolver|wireguard.*outbound|domain_strategy' "${logFile}"; then
        {
            printf '\n[padm 兼容性提示]\n'
            printf -- '- sing-box 1.13+ 已移除 legacy special outbounds；阻断规则应使用 route action: reject，不再使用 type=block 出站。\n'
            printf -- '- sing-box 1.13+ 已移除旧 WireGuard outbound；请迁移到 endpoints[type=wireguard]。\n'
            printf -- '- sing-box 1.14 将移除旧 DNS server 格式与旧 domain_strategy；请使用 typed DNS servers 与 domain_resolver/default_domain_resolver。\n'
        } >>"${logFile}"
    fi
}

coreValidationStateWithPaths() {
    local core=$1
    local binary=$2
    local configDir=$3
    local logFile=$4
    if [[ "${core}" == "xray" ]]; then
        if [[ -x "${binary}" && -d "${configDir}" ]] && "${binary}" -test -confdir "${configDir}" >"${logFile}" 2>&1; then
            echo "通过"
        else
            echo "失败，查看 ${logFile}"
        fi
    elif [[ "${core}" == "sing-box" ]]; then
        coreValidationState sing-box
    fi
}

coreValidationState() {
    local core=$1
    local logFile
    if [[ "${core}" == "xray" ]]; then
        logFile=$(coreXrayConfigTestLog)
        if validateXrayConfigWithBinary /etc/padm/xray/xray "${logFile}"; then
            echo "通过"
        else
            echo "失败，查看 ${logFile}"
        fi
    elif [[ "${core}" == "sing-box" ]]; then
        logFile=$(coreSingBoxConfigTestLog)
        if validateSingBoxConfigWithBinary /etc/padm/sing-box/sing-box "${logFile}"; then
            echo "通过"
        else
            echo "失败，查看 ${logFile}"
        fi
    fi
}

coreDisplayState() {
    case $1 in
    *运行中* | *通过* | *已安装* | *已设置*) uiStyle ok "$1" ;;
    *失败* | *缺失* | *为空*) uiStyle danger "$1" ;;
    *未安装* | *未设置* | *未运行* | *未安装配置*) uiStyle muted "$1" ;;
    *) uiStyle value "$1" ;;
    esac
}

showCoreStatusOverview() {
    local xrayDir=${PADM_XRAY_DIR:-/etc/padm/xray}
    local xrayBinary="${xrayDir}/xray"
    local xrayConfigDir="${xrayDir}/conf"
    local xrayVersion="未安装"
    local singBoxVersion="未安装"
    local geoStatus="未安装"
    local geoVersion=""
    local geoCron="未设置"

    if [[ -x "${xrayBinary}" ]]; then
        xrayVersion=$("${xrayBinary}" --version 2>/dev/null | awk 'NR==1 {print "v"$2}')
    fi
    singBoxVersion=$(getSingBoxCurrentVersion)

    if [[ -s "${xrayDir}/geosite.dat" && -s "${xrayDir}/geoip.dat" ]]; then
        geoStatus="已安装"
        geoVersion=$(xrayGeoDisplayVersion "${xrayDir}")
    elif [[ -x "${xrayBinary}" ]]; then
        geoStatus="缺失或为空"
    fi
    if crontab -l 2>/dev/null | grep -q "UpdateGeo"; then
        geoCron="已设置"
    fi

    echoContent title "\n┌─ 核心状态总览 ─────────────────────────────────────"
    menuLine "Xray-core: $(coreDisplayState "${xrayVersion}")"
    menuLine "Xray 服务: $(coreDisplayState "$(coreServiceState xray xrayRunning)")"
    if [[ -x "${xrayBinary}" ]]; then
        menuLine "Xray 配置: $(coreDisplayState "$(coreValidationStateWithPaths xray "${xrayBinary}" "${xrayConfigDir}" "$(coreXrayConfigTestLog)")")"
        if [[ -n "${geoVersion}" ]]; then
            menuLine "Xray Geo: $(coreDisplayState "${geoStatus}") / $(coreDisplayState "${geoVersion}") / 自动更新 $(coreDisplayState "${geoCron}")"
        else
            menuLine "Xray Geo: $(coreDisplayState "${geoStatus}") / 自动更新 $(coreDisplayState "${geoCron}")"
        fi
    fi
    menuLine "sing-box: $(coreDisplayState "${singBoxVersion}")"
    menuLine "sing-box 服务: $(coreDisplayState "$(coreServiceState sing-box singBoxRunning)")"
    if singBoxConfigInstalled; then
        menuLine "sing-box 配置: $(coreDisplayState "$(coreValidationState sing-box)")"
    elif singBoxInstalled; then
        menuLine "sing-box 配置: $(coreDisplayState "未安装配置")"
    fi
    menuMutedLine "最新版本会在升级或回退时按需获取"
    menuClose
}

runCoreServiceActionAllowFailure() {
    local previousAllowFailure="${SERVICE_QUEUE_ALLOW_FAILURE:-}"
    SERVICE_QUEUE_ALLOW_FAILURE=true
    "$@"
    local rc=$?
    SERVICE_QUEUE_ALLOW_FAILURE="${previousAllowFailure}"
    return "${rc}"
}

restoreCoreBinaryBackup() {
    local backupBinary=$1
    local targetBinary=$2
    [[ -f "${backupBinary}" ]] || return 0
    cp "${backupBinary}" "${targetBinary}" || return 1
    chmod 655 "${targetBinary}" >/dev/null 2>&1 || return 1
}

finalizeFailedCoreBinaryInstall() {
    local coreName=$1
    local backupBinary=$2
    local targetBinary=$3
    local startFunction=$4
    local logFile=$5
    local restoreMessage="无旧二进制需要恢复"

    if [[ -f "${backupBinary}" ]]; then
        if restoreCoreBinaryBackup "${backupBinary}" "${targetBinary}"; then
            restoreMessage="已恢复旧二进制"
            rm -f "${backupBinary}" >/dev/null 2>&1 || true
        else
            restoreMessage="旧二进制恢复失败"
        fi
    fi
    runCoreServiceActionAllowFailure "${startFunction}" start >/dev/null 2>&1 || true
    statusCard "${coreName} 更新失败" "${restoreMessage}" "排查日志: ${logFile}"
    return 1
}

installDownloadedXrayBinary() {
    local version=$1
    local tmpDir oldBinary backupBinary newBinary logFile
    logFile=$(coreXrayUpgradeTestLog)
    padmCreateTempPath tmpDir -d /etc/padm/tmp.xray.XXXXXX || return 1
    if ! downloadGitHubReleaseAsset -P "${tmpDir}/" XTLS/Xray-core "${version}" "${xrayCoreCPUVendor}.zip"; then
        padmRemoveCleanupPath "${tmpDir}"
        return 1
    fi
    if ! unzip -o "${tmpDir}/${xrayCoreCPUVendor}.zip" -d "${tmpDir}" >/dev/null; then
        padmRemoveCleanupPath "${tmpDir}"
        errorCard "Xray-core 解压失败"
        return 1
    fi
    newBinary="${tmpDir}/xray"
    if [[ ! -x "${newBinary}" ]]; then
        padmRemoveCleanupPath "${tmpDir}"
        errorCard "Xray-core 资产中未找到 xray 二进制"
        return 1
    fi
    if [[ -d /etc/padm/xray/conf ]] && ! validateXrayConfigWithBinary "${newBinary}" "${logFile}"; then
        padmRemoveCleanupPath "${tmpDir}"
        statusCard "Xray 配置校验失败" "已取消升级" "排查日志: ${logFile}"
        return 1
    fi

    oldBinary=$(coreXrayBinaryPath)
    backupBinary="${oldBinary}.bak.$(date +%s)"
    if ! mkdir -p "$(dirname "${oldBinary}")"; then
        padmRemoveCleanupPath "${tmpDir}"
        errorCard "Xray-core 安装目录创建失败"
        return 1
    fi
    if [[ -f "${oldBinary}" ]] && ! cp "${oldBinary}" "${backupBinary}"; then
        padmRemoveCleanupPath "${tmpDir}"
        errorCard "Xray-core 旧二进制备份失败"
        return 1
    fi
    if ! runCoreServiceActionAllowFailure handleXray stop; then
        padmRemoveCleanupPath "${tmpDir}"
        [[ -f "${backupBinary}" ]] && rm -f "${backupBinary}" >/dev/null 2>&1 || true
        statusCard "Xray-core 更新失败" "Xray 服务停止失败，已取消替换" "排查日志: ${logFile}"
        return 1
    fi
    if ! cp "${newBinary}" "${oldBinary}" || ! chmod 655 "${oldBinary}"; then
        padmRemoveCleanupPath "${tmpDir}"
        finalizeFailedCoreBinaryInstall "Xray-core" "${backupBinary}" "${oldBinary}" handleXray "${logFile}"
        return 1
    fi
    runCoreServiceActionAllowFailure handleXray start || true
    if xrayInstalled && xrayRunning; then
        successCard "Xray-core更新成功"
        padmRemoveCleanupPath "${tmpDir}"
        [[ -f "${backupBinary}" ]] && rm -f "${backupBinary}"
        return 0
    fi
    padmRemoveCleanupPath "${tmpDir}"
    finalizeFailedCoreBinaryInstall "Xray-core" "${backupBinary}" "${oldBinary}" handleXray "${logFile}"
}

installDownloadedSingBoxBinary() {
    local version=$1
    local tmpDir asset oldBinary backupBinary extractedDir newBinary logFile
    logFile=$(coreSingBoxUpgradeTestLog)
    padmCreateTempPath tmpDir -d /etc/padm/tmp.sing-box.XXXXXX || return 1
    asset="sing-box-${version/v/}${singBoxCoreCPUVendor}.tar.gz"
    if ! downloadGitHubReleaseAsset -P "${tmpDir}/" SagerNet/sing-box "${version}" "${asset}"; then
        padmRemoveCleanupPath "${tmpDir}"
        return 1
    fi
    if ! tar zxf "${tmpDir}/${asset}" -C "${tmpDir}" >/dev/null 2>&1; then
        padmRemoveCleanupPath "${tmpDir}"
        errorCard "sing-box 解压失败"
        return 1
    fi
    extractedDir="${tmpDir}/sing-box-${version/v/}${singBoxCoreCPUVendor}"
    newBinary="${extractedDir}/sing-box"
    if [[ ! -x "${newBinary}" ]]; then
        padmRemoveCleanupPath "${tmpDir}"
        errorCard "sing-box 资产中未找到 sing-box 二进制"
        return 1
    fi
    if [[ -d /etc/padm/sing-box/conf ]] && ! validateSingBoxConfigWithBinary "${newBinary}" "${logFile}"; then
        padmRemoveCleanupPath "${tmpDir}"
        statusCard "sing-box 配置校验失败" "已取消升级" "排查日志: ${logFile}"
        return 1
    fi

    oldBinary=$(coreSingBoxBinaryPath)
    backupBinary="${oldBinary}.bak.$(date +%s)"
    if ! mkdir -p "$(dirname "${oldBinary}")"; then
        padmRemoveCleanupPath "${tmpDir}"
        errorCard "sing-box 安装目录创建失败"
        return 1
    fi
    if [[ -f "${oldBinary}" ]] && ! cp "${oldBinary}" "${backupBinary}"; then
        padmRemoveCleanupPath "${tmpDir}"
        errorCard "sing-box 旧二进制备份失败"
        return 1
    fi
    if ! runCoreServiceActionAllowFailure handleSingBox stop; then
        padmRemoveCleanupPath "${tmpDir}"
        [[ -f "${backupBinary}" ]] && rm -f "${backupBinary}" >/dev/null 2>&1 || true
        statusCard "sing-box 更新失败" "sing-box 服务停止失败，已取消替换" "排查日志: ${logFile}"
        return 1
    fi
    if ! cp "${newBinary}" "${oldBinary}" || ! chmod 655 "${oldBinary}"; then
        padmRemoveCleanupPath "${tmpDir}"
        finalizeFailedCoreBinaryInstall "sing-box" "${backupBinary}" "${oldBinary}" handleSingBox "${logFile}"
        return 1
    fi
    runCoreServiceActionAllowFailure handleSingBox start || true
    if singBoxInstalled && singBoxRunning; then
        successCard "sing-box更新成功"
        padmRemoveCleanupPath "${tmpDir}"
        [[ -f "${backupBinary}" ]] && rm -f "${backupBinary}"
        return 0
    fi
    padmRemoveCleanupPath "${tmpDir}"
    finalizeFailedCoreBinaryInstall "sing-box" "${backupBinary}" "${oldBinary}" handleSingBox "${logFile}"
}

confirmCoreUpgrade() {
    local core=$1
    local version=$2
    local channel=$3
    local confirmVar
    autoRead core_upgrade_confirm "${core} 将切换到 ${channel} ${version}，是否继续？[y/n]:" confirmVar
    [[ "${confirmVar}" == "y" ]]
}

upgradeXrayCore() {
    local prerelease=${1:-false}
    local version=${2:-}
    local channel="稳定版"
    [[ "${prerelease}" == "true" ]] && channel="预览版"
    version=${version:-$(coreLatestReleaseTag XTLS/Xray-core "${prerelease}")}
    checkVersionNotEmpty "${version}"
    confirmCoreUpgrade "Xray-core" "${version}" "${channel}" || { statusCard "已取消" "未更新 Xray-core"; return 0; }
    installDownloadedXrayBinary "${version}"
}

upgradeSingBoxCore() {
    local prerelease=${1:-false}
    local version=${2:-}
    local channel="稳定版"
    [[ "${prerelease}" == "true" ]] && channel="预发布版"
    version=${version:-$(coreLatestReleaseTag SagerNet/sing-box "${prerelease}")}
    checkVersionNotEmpty "${version}"
    confirmCoreUpgrade "sing-box" "${version}" "${channel}" || { statusCard "已取消" "未更新 sing-box"; return 0; }
    installDownloadedSingBoxBinary "${version}"
}

selectRollbackVersion() {
    local repo=$1
    local title=$2
    local selected version
    echoContent title "\n┌─ ${title} 版本回退 ─────────────────────────────────"
    menuLine "只列出最近稳定版本；回退前会使用目标二进制校验当前配置"
    coreReleaseTags "${repo}" false 20 | awk '{print "│ "NR". "$0}'
    menuClose
    autoRead core_rollback_version "请输入要回退的版本序号:" selected
    version=$(coreReleaseTags "${repo}" false 20 | awk -v selected="${selected}" 'NR==selected {print $0}')
    [[ -n "${version}" ]] || return 1
    echo "${version}"
}

xrayVersionManageMenu() {
    echoContent title "\n┌─ Xray-core 生命周期 ────────────────────────────────"
    menuItem 1 "升级稳定版" "下载最新稳定版，校验后替换"
    menuItem 2 "升级预览版" "下载 prerelease，适合验证新能力"
    menuItem 3 "回退稳定版" "选择最近稳定版本回退"
    menuItem 4 "校验配置" "执行 xray -test -confdir"
    menuItem 5 "更新 Geo 数据" "更新 geosite.dat / geoip.dat"
    menuItem 6 "设置 Geo 自动更新" "每天凌晨更新 Xray Geo 数据"
    menuItem 7 "服务控制" "启动、停止、重启 Xray"
    menuItem 8 "日志管理" "查看或调整 Xray 日志"
    menuReturnItem 9 "返回核心与服务" "回到核心生命周期管理"
    menuClose
    autoRead xray_lifecycle_menu "请选择:" selectXrayType
    case "${selectXrayType}" in
    1) upgradeXrayCore false ;;
    2) upgradeXrayCore true ;;
    3)
        version=$(selectRollbackVersion XTLS/Xray-core "Xray-core") || { errorCard "输入有误，请重新输入"; xrayVersionManageMenu; return; }
        upgradeXrayCore false "${version}"
        ;;
    4)
        local logFile
        logFile=$(coreXrayConfigTestLog)
        if validateXrayConfigWithBinary /etc/padm/xray/xray "${logFile}"; then
            statusCard "Xray 配置校验" "通过"
        else
            statusCard "Xray 配置校验" "失败" "排查日志: ${logFile}"
        fi
        ;;
    5) updateGeoSite ;;
    6) installCronUpdateGeo ;;
    7) coreServiceControlMenu xray ;;
    8) checkLog 1 ;;
    9) coreVersionManageMenu ;;
    *) errorCard "输入有误，请重新输入"; xrayVersionManageMenu ;;
    esac
}

updateGeoSite() {
    if ! ensureXrayGeoFiles "/etc/padm/xray" force; then
        exit 1
    fi

    reloadCore
    statusCard "Geo 数据" "更新完毕"
}

updateXray() {
    readInstallType
    local targetVersion=$1
    local targetPrerelease=${prereleaseStatus:-false}
    if xrayInstalled; then
        upgradeXrayCore "${targetPrerelease}" "${targetVersion}"
    else
        installXray 1 "${targetPrerelease}"
    fi
}


# 验证整个服务是否可用
checkGFWStatue() {
    readInstallType
    progressCard "$1" "验证服务启动状态"
    if [[ "${coreInstallType}" == "1" ]] && [[ -n $(pgrep -f "xray/xray") ]]; then
        successCard "服务启动成功"
    elif [[ "${coreInstallType}" == "2" ]] && [[ -n $(pgrep -f "sing-box/sing-box") ]]; then
        successCard "服务启动成功"
    else
        errorCard "服务启动失败，请检查终端是否有日志打印"
        exit 0
    fi
}


# 安装alpine开机启动
installAlpineStartup() {
    local serviceName=$1
    local tmpFile
    padmCreateTempPath tmpFile "$(coreAlpineInitTemplate "${serviceName}")" || return 1

    if [[ "${serviceName}" == "sing-box" ]]; then
        cat <<EOF >"${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
#!/sbin/openrc-run

description="sing-box service"
command="/etc/padm/sing-box/sing-box"
command_args="run -c /etc/padm/sing-box/conf/config.json"
command_background=true
pidfile="/var/run/sing-box.pid"
EOF
    elif [[ "${serviceName}" == "xray" ]]; then
        cat <<EOF >"${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
#!/sbin/openrc-run

description="xray service"
command="/etc/padm/xray/xray"
command_args="run -confdir /etc/padm/xray/conf"
command_background=true
pidfile="/var/run/xray.pid"
EOF
    else
        padmRemoveCleanupPath "${tmpFile}"
        return 1
    fi

    if ! grep -q '^#!/sbin/openrc-run$' "${tmpFile}" || ! grep -q '^command=' "${tmpFile}"; then
        padmRemoveCleanupPath "${tmpFile}"
        return 1
    fi

    commitGeneratedFile "${tmpFile}" "/etc/init.d/${serviceName}" 755
}


# sing-box开机自启
installSingBoxService() {
    progressCard "$1" "配置 sing-box 开机自启"
    execStart='/etc/padm/sing-box/sing-box run -c /etc/padm/sing-box/conf/config.json'

    if [[ -n $(find /bin /usr/bin -name "systemctl") && "${release}" != "alpine" ]]; then
        local serviceFile=/etc/systemd/system/sing-box.service
        local tmpFile
        padmCreateTempPath tmpFile "$(coreSingBoxServiceTemplate)" || exit 1
        cat <<EOF >"${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; exit 1; }
[Unit]
Description=Sing-Box Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
ExecStart=${execStart}
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10
LimitNPROC=infinity
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
        if ! grep -q '^\[Service\]$' "${tmpFile}" || ! grep -q "^ExecStart=${execStart}$" "${tmpFile}"; then
            padmRemoveCleanupPath "${tmpFile}"
            errorCard "sing-box systemd 模板生成失败"
            exit 1
        fi
        if ! commitGeneratedFile "${tmpFile}" "${serviceFile}" 644; then
            padmRemoveCleanupPath "${tmpFile}"
            errorCard "sing-box systemd 模板提交失败"
            exit 1
        fi
        bootStartup "sing-box.service"
    elif [[ "${release}" == "alpine" ]]; then
        if ! installAlpineStartup "sing-box"; then
            errorCard "sing-box OpenRC 模板提交失败"
            exit 1
        fi
        bootStartup "sing-box"
    fi

    successCard "配置sing-box开机启动完毕"
}


# Xray-core 开机自启
installXrayService() {
    progressCard "$1" "配置 Xray 开机自启"
    execStart='/etc/padm/xray/xray run -confdir /etc/padm/xray/conf'
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]]; then
        local serviceFile=/etc/systemd/system/xray.service
        local tmpFile
        padmCreateTempPath tmpFile "$(coreXrayServiceTemplate)" || exit 1
        cat <<EOF >"${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; exit 1; }
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target
[Service]
User=root
ExecStart=${execStart}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=infinity
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
        if ! grep -q '^\[Service\]$' "${tmpFile}" || ! grep -q "^ExecStart=${execStart}$" "${tmpFile}"; then
            padmRemoveCleanupPath "${tmpFile}"
            errorCard "Xray systemd 模板生成失败"
            exit 1
        fi
        if ! commitGeneratedFile "${tmpFile}" "${serviceFile}" 644; then
            padmRemoveCleanupPath "${tmpFile}"
            errorCard "Xray systemd 模板提交失败"
            exit 1
        fi
        bootStartup "xray.service"
        successCard "配置Xray开机自启成功"
    elif [[ "${release}" == "alpine" ]]; then
        if ! installAlpineStartup "xray"; then
            errorCard "Xray OpenRC 模板提交失败"
            exit 1
        fi
        bootStartup "xray"
    fi
}


# 读取 Xray 用户数据并初始化
initXrayClients() {
    local type=",$1,"
    local newUUID=$2
    local newEmail=$3
    if [[ -n "${newUUID}" ]]; then
        local newUser=
        newUser="{\"id\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"email\":\"${newEmail}-VLESS_TCP/TLS_Vision\"}"
        currentClients=$(echo "${currentClients}" | jq -r ". +=[${newUser}]")
    fi
    local users=
    users=[]
    while read -r user; do
        uuid=$(echo "${user}" | jq -r .id//.uuid)
        email=$(echo "${user}" | jq -r .email//.name | awk -F "[-]" '{print $1}')
        currentUser=
        if protocolSelectionIncludes "${type}" 0; then
            currentUser="{\"id\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"email\":\"${email}-VLESS_TCP/TLS_Vision\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # VLESS WS
        if protocolSelectionIncludes "${type}" 1; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-VLESS_WS\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VLESS XHTTP
        if protocolSelectionIncludes "${type}" 12; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-VLESS_Reality_XHTTP\",\"flow\":\"xtls-rprx-vision\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # Trojan gRPC
        if protocolSelectionIncludes "${type}" 2; then
            currentUser="{\"password\":\"${uuid}\",\"email\":\"${email}-Trojan_gRPC\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VMess WS
        if protocolSelectionIncludes "${type}" 3; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-VMess_WS\",\"alterId\": 0}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # Trojan TCP
        if protocolSelectionIncludes "${type}" 4; then
            currentUser="{\"password\":\"${uuid}\",\"email\":\"${email}-trojan_tcp\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # VLESS gRPC
        if protocolSelectionIncludes "${type}" 5; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-vless_grpc\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # Hysteria2
        if protocolSelectionIncludes "${type}" 6; then
            currentUser="{\"password\":\"${uuid}\",\"name\":\"${email}-singbox_hysteria2\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # VLESS Reality Vision
        if protocolSelectionIncludes "${type}" 7; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-vless_reality_vision\",\"flow\":\"xtls-rprx-vision\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # VLESS Reality gRPC
        if protocolSelectionIncludes "${type}" 8; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-vless_reality_grpc\",\"flow\":\"\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # TUIC
        if protocolSelectionIncludes "${type}" 9; then
            currentUser="{\"uuid\":\"${uuid}\",\"password\":\"${uuid}\",\"name\":\"${email}-singbox_tuic\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

    done < <(echo "${currentClients}" | jq -c '.[]')
    echo "${users}"
}

# 读取 sing-box 用户数据并初始化
initSingBoxClients() {
    local type=",$1,"
    local newUUID=$2
    local newName=$3

    if [[ -n "${newUUID}" ]]; then
        local newUser=
        newUser="{\"uuid\":\"${newUUID}\",\"flow\":\"xtls-rprx-vision\",\"name\":\"${newName}-VLESS_TCP/TLS_Vision\"}"
        currentClients=$(echo "${currentClients}" | jq -r ". +=[${newUser}]")
    fi
    local users=
    users=[]
    while read -r user; do
        uuid=$(echo "${user}" | jq -r .uuid//.id//.password)
        name=$(echo "${user}" | jq -r .name//.email//.username | awk -F "[-]" '{print $1}')
        currentUser=
        # VLESS Vision
        if protocolSelectionIncludes "${type}" 0; then
            currentUser="{\"uuid\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"name\":\"${name}-VLESS_TCP/TLS_Vision\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VLESS WS
        if protocolSelectionIncludes "${type}" 1; then
            currentUser="{\"uuid\":\"${uuid}\",\"name\":\"${name}-VLESS_WS\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VMess WS
        if protocolSelectionIncludes "${type}" 3; then
            currentUser="{\"uuid\":\"${uuid}\",\"name\":\"${name}-VMess_WS\",\"alterId\": 0}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # Trojan TCP
        if protocolSelectionIncludes "${type}" 4; then
            currentUser="{\"password\":\"${uuid}\",\"name\":\"${name}-Trojan_TCP\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # VLESS Reality Vision
        if protocolSelectionIncludes "${type}" 7; then
            currentUser="{\"uuid\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"name\":\"${name}-VLESS_Reality_Vision\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VLESS Reality gRPC
        if protocolSelectionIncludes "${type}" 8; then
            currentUser="{\"uuid\":\"${uuid}\",\"name\":\"${name}-VLESS_Reality_gPRC\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # Hysteria2
        if protocolSelectionIncludes "${type}" 6; then
            currentUser="{\"password\":\"${uuid}\",\"name\":\"${name}-singbox_hysteria2\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # TUIC
        if protocolSelectionIncludes "${type}" 9; then
            currentUser="{\"uuid\":\"${uuid}\",\"password\":\"${uuid}\",\"name\":\"${name}-singbox_tuic\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # Naive
        if protocolSelectionIncludes "${type}" 10; then
            currentUser="{\"password\":\"${uuid}\",\"username\":\"${name}-singbox_naive\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VMess HTTPUpgrade
        if protocolSelectionIncludes "${type}" 11; then
            currentUser="{\"uuid\":\"${uuid}\",\"name\":\"${name}-VMess_HTTPUpgrade\",\"alterId\": 0}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # AnyTLS
        if protocolSelectionIncludes "${type}" 13; then
            currentUser="{\"password\":\"${uuid}\",\"name\":\"${name}-anytls\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        if protocolSelectionIncludes "${type}" 20; then
            currentUser="{\"username\":\"${uuid}\",\"password\":\"${uuid}\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

    done < <(echo "${currentClients}" | jq -c '.[]')
    echo "${users}"
}


# 安装 Xray-core
installXrayReality() {
    selectCustomInstallType=",7,"
    readLastInstallationConfig
    unInstallSubscribe
    totalProgress=6
    installTools 1

    handleNginx stop
    if subscriptionWireGuardControlEnabled; then
        refreshSubscriptionWireGuardNginxControl
    fi

    # 安装 Xray
    installXray 2 false
    installXrayService 3
    initXrayConfig custom 4 || return 1
    cleanUp singBoxDel

    serviceQueueRestart xray
    serviceQueueApply || return 1
    # 生成账号
    checkGFWStatue 5
    showAccounts 6
}

# 安装 sing-box Reality
installSingBoxReality() {

    selectCustomInstallType=",7,"
    readLastInstallationConfig
    unInstallSubscribe
    totalProgress=6
    installTools 1

    installSingBox 2
    installSingBoxService 3
    initSingBoxConfig custom 4 || return 1
    cleanUp xrayDel
    serviceQueueRestart sing-box
    serviceQueueApply || return 1
    # 生成账号
    checkGFWStatue 5
    showAccounts 6
}

# Xray-core个性化安装
customXrayInstall() {
    local preselectedProtocols=${1:-}
    local preselectedMode=${2:-}
    realityOnlyWithDomain=
    echoContent title "\n┌─ Xray 个性化安装 ──────────────────────────────────"
    menuLine "可输入单个编号，也可用英文逗号多选，例如 0,1,7"
    menuLine "推荐新人：优先选 7；需要 CDN/反代时选 12；协议说明来自 registry"
    menuLine "传统 TLS/WS/gRPC/HTTPUpgrade 协议仅在明确客户端兼容或迁移需要时选择"
    menuLine "只安装 Reality 时不补传统 TLS 协议；域名 Reality 会额外申请入口域名的本机 TLS 证书"
    protocolRegistryMenu ",0,1,3,4,7,12,"
    menuClose
    if [[ -n "${preselectedProtocols}" ]]; then
        selectCustomInstallType=${preselectedProtocols}
        statusCard "推荐安装" "已选择协议编号: ${selectCustomInstallType}"
    else
        autoRead protocols "请选择[多选]，[例如:0,1,7]:" selectCustomInstallType
    fi
    if echo "${selectCustomInstallType}" | grep -q "，"; then
        errorCard "请使用英文逗号分隔"
        exit 0
    fi
    if [[ "${selectCustomInstallType}" != "12" ]] && ((${#selectCustomInstallType} >= 2)) && ! echo "${selectCustomInstallType}" | grep -q ","; then
        errorCard "多选请使用英文逗号分隔"
        exit 0
    fi
    if protocolSelectionOnlyRealityNoDomain "${selectCustomInstallType}"; then
        if [[ "${selectCustomInstallType}" == "7" ]]; then
            if [[ "${preselectedMode}" == "domain" ]]; then
                realityOnlyWithDomain=true
                statusCard "Reality 安装方式" "已选择域名 Reality：entry 使用自有域名，target/SNI 仍是外部伪装目标"
            else
                echoContent title "\n┌─ Reality 安装方式 ─────────────────────────────────"
                menuItem 1 "无域名 Reality" "客户端入口使用服务器 IP 或 --entry-host，不申请 TLS 证书"
                menuItem 2 "域名 Reality" "客户端入口使用自有域名，同时仍需单独填写 Reality 伪装目标"
                menuLine "入口 entry 是客户端连接地址；target/SNI 是 REALITY 伪装目标，不要混淆"
                menuClose
                autoRead reality_domain "请选择[默认1]:" realityOnlyInstallType
                if [[ "${realityOnlyInstallType}" == "2" ]]; then
                    realityOnlyWithDomain=true
                elif [[ -n "${realityOnlyInstallType}" && "${realityOnlyInstallType}" != "1" ]]; then
                    errorCard "选择错误"
                    customXrayInstall
                    return
                fi
            fi
        fi
        selectCustomInstallType=",${selectCustomInstallType},"
    else
        if ! protocolSelectionHasAny "${selectCustomInstallType}" 0; then
            selectCustomInstallType=",0,${selectCustomInstallType},"
        else
            selectCustomInstallType=",${selectCustomInstallType},"
        fi
    fi
    if [[ "${selectCustomInstallType:0:1}" != "," ]]; then
        selectCustomInstallType=",${selectCustomInstallType},"
    fi
    if [[ "${selectCustomInstallType//,/}" =~ ^[0-9]+$ ]] && protocolSelectionIdsValid "${selectCustomInstallType}" ",0,1,3,4,7,12,"; then
        readLastInstallationConfig
        unInstallSubscribe
        # checkBTPanel
        # check1Panel
        totalProgress=12
        installTools 1
        if [[ -n "${btDomain}" ]]; then
            statusCard "跳过 TLS 证书" "检测到宝塔面板/1Panel"
            handleXray stop
            if [[ "${selectCustomInstallType}" != ",7," || -n "${realityOnlyWithDomain}" ]]; then
                customPortFunction || return 1
            fi
        else
            # 申请tls
            if protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"; then
                if [[ -n "${realityOnlyWithDomain}" ]]; then
                    statusCard "域名 Reality 证书" "将为自有入口域名申请本机 TLS 证书" "该证书用于客户端连接入口和前置 TLS，不是 Reality target/SNI 伪装目标证书"
                fi
                initTLSNginxConfig 2 || return 1
                installTLS 3 || return 1
            else
                statusCard "跳过 TLS 证书" "仅安装无域名 Reality"
            fi
        fi

        if protocolSelectionNeedsPath "${selectCustomInstallType}"; then
            randomPathFunction 4
        fi
        if [[ -n "${btDomain}" ]]; then
            statusCard "跳过伪装网站" "检测到宝塔面板/1Panel"
        else
            nginxBlog 6
        fi
        if protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"; then
            updateRedirectNginxConf
            handleNginx start
        fi

        # 安装 Xray
        installXray 7 false
        installXrayService 8
        initXrayConfig custom 9 || return 1
        cleanUp singBoxDel
        if protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"; then
            installCronTLS 10
        fi

        serviceQueueRestart xray
        serviceQueueApply || return 1
        # 生成账号
        checkGFWStatue 11
        showAccounts 12
    else
        errorCard "输入不合法"
        customXrayInstall
    fi
}


# sing-box 个性化安装
customSingBoxInstall() {
    local preselectedProtocols=${1:-}
    echoContent title "\n┌─ sing-box 个性化安装 ───────────────────────────────"
    menuLine "可输入单个编号，也可用英文逗号多选，例如 0,6,7"
    menuLine "推荐新人：优先选 7；需要 CDN/反代时用 Xray 选择 12；协议说明来自 registry"
    menuLine "传统 TLS 类协议仅在明确需要兼容；Hysteria2/Tuic 用于 UDP/移动网络，Naive 用于 TLS 指纹抗性，AnyTLS 按需选择"
    protocolRegistryMenu ",0,1,3,4,6,7,8,9,10,11,13,"

    menuClose
    if [[ -n "${preselectedProtocols}" ]]; then
        selectCustomInstallType=${preselectedProtocols}
        statusCard "推荐安装" "已选择协议编号: ${selectCustomInstallType}"
    else
        autoRead protocols "请选择[多选]，[例如:0,6,7]:" selectCustomInstallType
    fi
    if echo "${selectCustomInstallType}" | grep -q "，"; then
        errorCard "请使用英文逗号分隔"
        exit 0
    fi
    if [[ "${selectCustomInstallType}" != "10" ]] && [[ "${selectCustomInstallType}" != "11" ]] && [[ "${selectCustomInstallType}" != "13" ]] && ((${#selectCustomInstallType} >= 2)) && ! echo "${selectCustomInstallType}" | grep -q ","; then
        errorCard "多选请使用英文逗号分隔"
        exit 0
    fi
    if [[ "${selectCustomInstallType: -1}" != "," ]]; then
        selectCustomInstallType="${selectCustomInstallType},"
    fi
    if [[ "${selectCustomInstallType:0:1}" != "," ]]; then
        selectCustomInstallType=",${selectCustomInstallType},"
    fi

    if [[ "${selectCustomInstallType//,/}" =~ ^[0-9]+$ ]] && protocolSelectionIdsValid "${selectCustomInstallType}" ",0,1,3,4,6,7,8,9,10,11,13,"; then
        readLastInstallationConfig
        unInstallSubscribe
        totalProgress=9
        installTools 1
        # 申请tls
        if protocolSelectionNeedsTLS "${selectCustomInstallType}"; then
            initTLSNginxConfig 2 || return 1
            installTLS 3 || return 1
            handleNginx stop
        fi

        installSingBox 4
        installSingBoxService 5
        initSingBoxConfig custom 6 || return 1
        cleanUp xrayDel
        installCronTLS 7
        serviceQueueRestart sing-box
        serviceQueueRestart nginx
        serviceQueueApply || return 1
        # 生成账号
        checkGFWStatue 8
        showAccounts 9
    else
        errorCard "输入不合法"
        customSingBoxInstall
    fi
}


# 选择核心安装 sing-box 或 Xray-core
selectCoreInstall() {
    progressCard "1" "选择核心安装"
    echoContent title "\n┌─ 选择核心 ─────────────────────────────────────────"
    menuRecommendedItem 1 "Xray-core" "推荐新人优先选择，Reality Vision 与 Reality XHTTP 场景验证最多"
    menuItem 2 "sing-box" "适合 Hysteria2、Tuic、Naive、AnyTLS 或统一 sing-box 配置"
    menuClose
    autoRead core "请选择:" selectCoreType
    case ${selectCoreType} in
    1)
        if [[ "${selectInstallType}" == "1" ]]; then
            xrayCoreInstall
        elif [[ "${selectInstallType}" == "2" ]]; then
            customXrayInstall
        elif [[ "${selectInstallType}" == "3" ]]; then
            installXrayReality
        fi
        ;;
    2)
        if [[ "${selectInstallType}" == "1" ]]; then
            singBoxInstall
        elif [[ "${selectInstallType}" == "2" ]]; then
            customSingBoxInstall
        elif [[ "${selectInstallType}" == "3" ]]; then
            installSingBoxReality
        fi
        ;;
    *)
        errorCard "选择错误，重新选择"
        selectCoreInstall
        ;;
    esac
}


# Xray-core 个性化安装
xrayCoreInstall() {
    readLastInstallationConfig
    unInstallSubscribe
    # checkBTPanel
    # check1Panel
    selectCustomInstallType=
    totalProgress=12
    installTools 2
    if [[ -n "${btDomain}" ]]; then
        statusCard "跳过 TLS 证书" "检测到宝塔面板/1Panel"
        handleXray stop
        customPortFunction || return 1
    else
        # 申请tls
        initTLSNginxConfig 3 || return 1
        installTLS 4 || return 1
    fi

    randomPathFunction 5

    # 安装 Xray
    installXray 6 false
    installXrayService 7
    initXrayConfig all 8 || return 1
    cleanUp singBoxDel
    installCronTLS 9
    if [[ -n "${btDomain}" ]]; then
        statusCard "跳过伪装网站" "检测到宝塔面板/1Panel"
    else
        nginxBlog 10
    fi
    updateRedirectNginxConf
    handleXray stop
    sleep 2
    handleXray start

    handleNginx start
    # 生成账号
    checkGFWStatue 11
    showAccounts 12
}


# sing-box 全部安装
singBoxInstall() {
    readLastInstallationConfig
    unInstallSubscribe
    # checkBTPanel
    # check1Panel
    selectCustomInstallType=
    totalProgress=8
    installTools 2

    if [[ -n "${btDomain}" ]]; then
        statusCard "跳过 TLS 证书" "检测到宝塔面板/1Panel"
        handleXray stop
        customPortFunction || return 1
    else
        # 申请tls
        initTLSNginxConfig 3 || return 1
        installTLS 4 || return 1
    fi

    handleNginx stop

    installSingBox 5
    installSingBoxService 6
    initSingBoxConfig all 7 || return 1

    cleanUp xrayDel
    installCronTLS 8

    serviceQueueRestart sing-box
    serviceQueueStart nginx
    serviceQueueApply || return 1
    # 生成账号
    showAccounts 9
}


coreServiceControlMenu() {
    local core=$1
    local serviceName=$core
    local title=$core
    if [[ "${core}" == "xray" ]]; then
        title="Xray-core"
    fi
    echoContent title "\n┌─ ${title} 服务控制 ─────────────────────────────────"
    menuItem 1 "启动" "启动 ${serviceName} 服务"
    menuItem 2 "停止" "停止 ${serviceName} 服务"
    menuItem 3 "重启" "重启 ${serviceName} 服务"
    menuReturnItem 4 "返回" "回到核心菜单"
    menuClose
    autoRead core_service_control "请选择:" selectServiceAction
    case "${selectServiceAction}" in
    1) serviceQueueStart "${serviceName}"; serviceQueueApply ;;
    2) serviceQueueStop "${serviceName}"; serviceQueueApply ;;
    3) serviceQueueRestart "${serviceName}"; serviceQueueApply ;;
    4) coreVersionManageMenu ;;
    *) errorCard "输入有误，请重新输入"; coreServiceControlMenu "${core}" ;;
    esac
}

coreConfigMaintenanceMenu() {
    echoContent title "\n┌─ 配置校验与数据维护 ───────────────────────────────"
    menuItem 1 "校验 Xray 配置" "执行 xray -test -confdir"
    menuItem 2 "校验 sing-box 配置" "执行 merge + check"
    menuItem 3 "更新 Xray Geo 数据" "更新 geosite.dat / geoip.dat"
    menuItem 4 "设置 Xray Geo 自动更新" "每天凌晨更新规则数据"
    menuReturnItem 5 "返回核心与服务" "回到核心生命周期管理"
    menuClose
    autoRead core_config_maintenance "请选择:" selectMaintenance
    case "${selectMaintenance}" in
    1)
        local logFile
        logFile=$(coreXrayConfigTestLog)
        if validateXrayConfigWithBinary /etc/padm/xray/xray "${logFile}"; then
            statusCard "Xray 配置校验" "通过"
        else
            statusCard "Xray 配置校验" "失败" "排查日志: ${logFile}"
        fi
        ;;
    2)
        local logFile
        logFile=$(coreSingBoxConfigTestLog)
        if validateSingBoxConfigWithBinary /etc/padm/sing-box/sing-box "${logFile}"; then
            statusCard "sing-box 配置校验" "通过"
        else
            statusCard "sing-box 配置校验" "失败" "排查日志: ${logFile}" "如日志包含 legacy/deprecated/domain_resolver，查看日志底部的 padm 兼容性提示"
        fi
        ;;
    3) updateGeoSite ;;
    4) installCronUpdateGeo ;;
    5) coreVersionManageMenu ;;
    *) errorCard "输入有误，请重新输入"; coreConfigMaintenanceMenu ;;
    esac
}

coreLogsMenu() {
    echoContent title "\n┌─ 核心日志 ─────────────────────────────────────────"
    menuItem 1 "Xray 日志管理" "查看 access/error 或调整日志"
    menuItem 2 "sing-box 实时日志" "tail -f box.log"
    menuReturnItem 3 "返回核心与服务" "回到核心生命周期管理"
    menuClose
    autoRead core_logs_menu "请选择:" selectLogs
    case "${selectLogs}" in
    1) checkLog 1 ;;
    2)
        mkdir -p /etc/padm/sing-box/conf
        touch /etc/padm/sing-box/conf/box.log >/dev/null 2>&1
        tail -f /etc/padm/sing-box/conf/box.log
        ;;
    3) coreVersionManageMenu ;;
    *) errorCard "输入有误，请重新输入"; coreLogsMenu ;;
    esac
}

coreAllServicesMenu() {
    echoContent title "\n┌─ 核心服务控制 ─────────────────────────────────────"
    menuItem 1 "Xray 服务" "启动、停止、重启 Xray"
    menuItem 2 "sing-box 服务" "启动、停止、重启 sing-box"
    menuReturnItem 3 "返回核心与服务" "回到核心生命周期管理"
    menuClose
    autoRead core_services_menu "请选择:" selectCoreService
    case "${selectCoreService}" in
    1) coreServiceControlMenu xray ;;
    2) coreServiceControlMenu sing-box ;;
    3) coreVersionManageMenu ;;
    *) errorCard "输入有误，请重新输入"; coreAllServicesMenu ;;
    esac
}

coreVersionManageMenu() {
    readInstallType
    if ! xrayInstalled && ! singBoxInstalled; then
        errorCard "没有检测到安装目录，请执行脚本安装内容"
        menu
        exit 0
    fi
    showCoreStatusOverview
    echoContent title "\n┌─ 核心与服务 ───────────────────────────────────────"
    menuLine "这里维护 Xray-core / sing-box 二进制、配置校验、服务状态和日志"
    menuLine "协议入口去 协议与入口；脚本更新和 BBR 去 系统与脚本"
    menuItem 1 "Xray-core 生命周期" "升级、回退、校验、服务、日志"
    menuItem 2 "sing-box 生命周期" "升级、回退、校验、服务、日志"
    menuItem 3 "配置校验与数据维护" "校验配置，维护 Xray Geo 数据"
    menuItem 4 "核心服务控制" "统一启动、停止、重启服务"
    menuItem 5 "核心日志" "查看 Xray / sing-box 日志"
    menuReturnItem 6 "返回主菜单" "回到 padm 管理面板"
    menuClose
    autoRead core_manage_menu "请选择:" selectCore
    case "${selectCore}" in
    1) xrayVersionManageMenu ;;
    2) singBoxVersionManageMenu ;;
    3) coreConfigMaintenanceMenu ;;
    4) coreAllServicesMenu ;;
    5) coreLogsMenu ;;
    6) menu ;;
    *) errorCard "输入有误，请重新输入"; coreVersionManageMenu ;;
    esac
}

singBoxVersionManageMenu() {
    echoContent title "\n┌─ sing-box 生命周期 ─────────────────────────────────"
    menuItem 1 "升级稳定版" "下载最新稳定版，校验后替换"
    menuItem 2 "升级预发布版" "下载 prerelease，适合验证新能力"
    menuItem 3 "回退稳定版" "选择最近稳定版本回退"
    menuItem 4 "校验配置" "执行 sing-box merge + check"
    menuItem 5 "服务控制" "启动、停止、重启 sing-box"
    local logStatus=
    if [[ -f /etc/padm/sing-box/conf/config/log.json && "$(jq -r .log.disabled /etc/padm/sing-box/conf/config/log.json)" == "false" ]]; then
        menuItem 6 "关闭 debug 日志" "停止写入 sing-box debug 日志"
        logStatus=true
    else
        menuItem 6 "启用 debug 日志" "开启 sing-box debug 日志"
        logStatus=false
    fi
    menuItem 7 "查看日志" "tail -f 查看 sing-box 日志"
    menuReturnItem 8 "返回核心与服务" "回到核心生命周期管理"
    menuClose
    autoRead singbox_lifecycle_menu "请选择:" selectSingBoxType
    case "${selectSingBoxType}" in
    1) upgradeSingBoxCore false ;;
    2) upgradeSingBoxCore true ;;
    3)
        version=$(selectRollbackVersion SagerNet/sing-box "sing-box") || { errorCard "输入有误，请重新输入"; singBoxVersionManageMenu; return; }
        upgradeSingBoxCore false "${version}"
        ;;
    4)
        local logFile
        logFile=$(coreSingBoxConfigTestLog)
        if validateSingBoxConfigWithBinary /etc/padm/sing-box/sing-box "${logFile}"; then
            statusCard "sing-box 配置校验" "通过"
        else
            statusCard "sing-box 配置校验" "失败" "排查日志: ${logFile}" "如日志包含 legacy/deprecated/domain_resolver，查看日志底部的 padm 兼容性提示"
        fi
        ;;
    5) coreServiceControlMenu sing-box ;;
    6)
        singBoxLog ${logStatus}
        [[ "${logStatus}" == "false" ]] && tail -f /etc/padm/sing-box/conf/box.log
        ;;
    7)
        mkdir -p /etc/padm/sing-box/conf
        touch /etc/padm/sing-box/conf/box.log >/dev/null 2>&1
        tail -f /etc/padm/sing-box/conf/box.log
        ;;
    8) coreVersionManageMenu ;;
    *) errorCard "输入有误，请重新输入"; singBoxVersionManageMenu ;;
    esac
}


# sing-box 日志
singBoxLog() {
    cat <<EOF >/etc/padm/sing-box/conf/config/log.json
{
  "log": {
    "disabled": $1,
    "level": "debug",
    "output": "/etc/padm/sing-box/conf/box.log",
    "timestamp": true
  }
}
EOF

    serviceQueueRestart sing-box
    serviceQueueApply
}
