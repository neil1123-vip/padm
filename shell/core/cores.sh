#!/usr/bin/env bash

# 清理 Xray geo 数据文件
removeXrayGeoManagedFiles() {
    local targetDir=$1
    local geoipFile
    local geositeFile
    local geoVersionFile

    geoipFile=$(padmManagedFilePath "${targetDir}" "geoip.dat") || return 1
    geositeFile=$(padmManagedFilePath "${targetDir}" "geosite.dat") || return 1
    geoVersionFile=$(padmManagedFilePath "${targetDir}" "geo.version") || return 1
    removeManagedFilesIfPresent "${geositeFile}" "${geoipFile}" "${geoVersionFile}"
}

cleanSingBoxDownloadArtifacts() {
    local installDir=$1
    local version=$2
    local assetPath="${installDir%/}/sing-box-${version/v/}${singBoxCoreCPUVendor}.tar.gz"
    local extractedDir="${installDir%/}/sing-box-${version/v/}${singBoxCoreCPUVendor}"

    padmIsSafeAbsolutePath "${assetPath}" || return 1
    padmIsSafeAbsolutePath "${extractedDir}" || return 1
    removeManagedFileIfPresent "${assetPath}" || return 1
    padmRemoveCleanupPath "${extractedDir}"
    [[ ! -e "${extractedDir}" ]]
}

coreArchiveEntryIsSafe() {
    local entryPath=$1
    local normalizedPath segment
    local -a pathSegments
    [[ -n "${entryPath}" ]] || return 1
    normalizedPath="${entryPath}"
    while [[ "${normalizedPath}" == ./* ]]; do
        normalizedPath="${normalizedPath#./}"
    done
    normalizedPath="${normalizedPath%/}"
    [[ -n "${normalizedPath}" && "${normalizedPath}" != /* ]] || return 1
    IFS='/' read -r -a pathSegments <<<"${normalizedPath}"
    for segment in "${pathSegments[@]}"; do
        [[ -n "${segment}" && "${segment}" != "." && "${segment}" != ".." ]] || return 1
    done
}

coreArchiveExpandedSizeIsSafe() {
    local archiveType=$1
    local archiveFile=$2
    local entryList=$3
    local entryCount expandedBytes

    entryCount=$(wc -l <"${entryList}" | tr -d '[:space:]') || return 1
    [[ "${entryCount}" =~ ^[0-9]+$ ]] && ((entryCount <= 4096)) || return 1
    case "${archiveType}" in
    zip) expandedBytes=$({ unzip -p "${archiveFile}" 2>/dev/null || true; } | head -c 268435457 | wc -c | tr -d '[:space:]') ;;
    tar) expandedBytes=$({ tar -xOzf "${archiveFile}" 2>/dev/null || true; } | head -c 268435457 | wc -c | tr -d '[:space:]') ;;
    *) return 1 ;;
    esac
    [[ "${expandedBytes}" =~ ^[0-9]+$ ]] && ((expandedBytes <= 268435456))
}

validateCoreZipArchive() {
    local archiveFile=$1
    local entryList detailList entry entryCount detailCount
    padmCreateTempPath entryList "$(coreTmpFilePath padm-core-zip-entries.XXXXXX)" || return 1
    padmCreateTempPath detailList "$(coreTmpFilePath padm-core-zip-details.XXXXXX)" || { padmRemoveCleanupPath "${entryList}"; return 1; }
    if ! unzip -Z1 "${archiveFile}" >"${entryList}" 2>/dev/null; then
        padmRemoveCleanupPath "${entryList}"
        padmRemoveCleanupPath "${detailList}"
        return 1
    fi
    while IFS= read -r entry; do
        coreArchiveEntryIsSafe "${entry}" || { padmRemoveCleanupPath "${entryList}"; padmRemoveCleanupPath "${detailList}"; return 1; }
    done <"${entryList}"
    if ! unzip -Z -l "${archiveFile}" >"${detailList}" 2>/dev/null; then
        padmRemoveCleanupPath "${entryList}"
        padmRemoveCleanupPath "${detailList}"
        return 1
    fi
    entryCount=$(wc -l <"${entryList}" | tr -d '[:space:]') || { padmRemoveCleanupPath "${entryList}"; padmRemoveCleanupPath "${detailList}"; return 1; }
    detailCount=$(awk '$1 ~ /^[-d][rwxStTs-]{9}$/ { count++ } END { print count + 0 }' "${detailList}") || { padmRemoveCleanupPath "${entryList}"; padmRemoveCleanupPath "${detailList}"; return 1; }
    [[ "${detailCount}" == "${entryCount}" ]] || { padmRemoveCleanupPath "${entryList}"; padmRemoveCleanupPath "${detailList}"; return 1; }
    if ! coreArchiveExpandedSizeIsSafe zip "${archiveFile}" "${entryList}"; then
        padmRemoveCleanupPath "${entryList}"
        padmRemoveCleanupPath "${detailList}"
        return 1
    fi
    padmRemoveCleanupPath "${entryList}"
    padmRemoveCleanupPath "${detailList}"
}

validateCoreTarArchive() {
    local archiveFile=$1
    local entryList detailList entry line lineType
    padmCreateTempPath entryList "$(coreTmpFilePath padm-core-tar-entries.XXXXXX)" || return 1
    padmCreateTempPath detailList "$(coreTmpFilePath padm-core-tar-details.XXXXXX)" || { padmRemoveCleanupPath "${entryList}"; return 1; }
    if ! tar -tzf "${archiveFile}" >"${entryList}" 2>/dev/null; then
        padmRemoveCleanupPath "${entryList}"
        padmRemoveCleanupPath "${detailList}"
        return 1
    fi
    while IFS= read -r entry; do
        coreArchiveEntryIsSafe "${entry}" || { padmRemoveCleanupPath "${entryList}"; padmRemoveCleanupPath "${detailList}"; return 1; }
    done <"${entryList}"
    if ! tar -tvzf "${archiveFile}" >"${detailList}" 2>/dev/null; then
        padmRemoveCleanupPath "${entryList}"
        padmRemoveCleanupPath "${detailList}"
        return 1
    fi
    while IFS= read -r line; do
        lineType="${line:0:1}"
        case "${lineType}" in
        - | d) ;;
        *) padmRemoveCleanupPath "${entryList}"; padmRemoveCleanupPath "${detailList}"; return 1 ;;
        esac
    done <"${detailList}"
    coreArchiveExpandedSizeIsSafe tar "${archiveFile}" "${entryList}" || { padmRemoveCleanupPath "${entryList}"; padmRemoveCleanupPath "${detailList}"; return 1; }
    padmRemoveCleanupPath "${entryList}"
    padmRemoveCleanupPath "${detailList}"
}

coreExtractedFileIsRegular() {
    [[ -f "$1" && ! -L "$1" ]]
}

downloadXrayReleaseBinaryToTempDir() {
    local version=$1
    local tmpDir=$2
    local binary="${tmpDir}/xray"

    if ! downloadGitHubReleaseAsset -P "${tmpDir}/" XTLS/Xray-core "${version}" "${xrayCoreCPUVendor}.zip"; then
        return 1
    fi
    if ! validateCoreZipArchive "${tmpDir}/${xrayCoreCPUVendor}.zip"; then
        return 2
    fi
    if ! unzip -o "${tmpDir}/${xrayCoreCPUVendor}.zip" -d "${tmpDir}" >/dev/null 2>&1; then
        return 2
    fi
    coreExtractedFileIsRegular "${binary}" && [[ -x "${binary}" ]] || return 3
}

downloadSingBoxReleaseBinaryToTempDir() {
    local version=$1
    local tmpDir=$2
    local asset="sing-box-${version/v/}${singBoxCoreCPUVendor}.tar.gz"
    local extractedDir="${tmpDir}/sing-box-${version/v/}${singBoxCoreCPUVendor}"
    local binary="${extractedDir}/sing-box"

    if ! downloadGitHubReleaseAsset -P "${tmpDir}/" SagerNet/sing-box "${version}" "${asset}"; then
        return 1
    fi
    if ! validateCoreTarArchive "${tmpDir}/${asset}"; then
        return 2
    fi
    if ! tar zxf "${tmpDir}/${asset}" -C "${tmpDir}" >/dev/null 2>&1; then
        return 2
    fi
    coreExtractedFileIsRegular "${extractedDir}/libcronet.so" || return 3
    coreExtractedFileIsRegular "${binary}" && [[ -x "${binary}" ]] || return 4
}

downloadXrayGeoFilesToStage() {
    local stageDir=$1
    local geoVersion=$2

    mkdir -p "${stageDir}" || return 1
    if ! downloadGitHubReleaseAsset -P "${stageDir}/" Loyalsoldier/v2ray-rules-dat "${geoVersion}" geosite.dat; then
        return 1
    fi
    if ! downloadGitHubReleaseAsset -P "${stageDir}/" Loyalsoldier/v2ray-rules-dat "${geoVersion}" geoip.dat; then
        return 1
    fi
    [[ -s "${stageDir}/geosite.dat" && -s "${stageDir}/geoip.dat" ]]
}

backupXrayGeoFileIfPresent() {
    local targetFile=$1
    local backupFile=$2
    [[ -e "${targetFile}" || -L "${targetFile}" ]] || return 0
    cp -p "${targetFile}" "${backupFile}"
}

restoreXrayGeoCommitBackup() {
    local backupDir=$1
    local geositeTarget=$2
    local geoipTarget=$3
    local versionTarget=$4
    local status=0

    restoreCoreOptionalFileBackup "${backupDir}/geosite.dat" "${geositeTarget}" 644 || status=1
    restoreCoreOptionalFileBackup "${backupDir}/geoip.dat" "${geoipTarget}" 644 || status=1
    restoreCoreOptionalFileBackup "${backupDir}/geo.version" "${versionTarget}" 644 || status=1
    return "${status}"
}

commitXrayGeoFilesFromStage() {
    local stageDir=$1
    local targetDir=$2
    local geoVersion=$3
    local backupDir=
    local geositeStage
    local geoipStage
    local versionStage
    local geositeTarget
    local geoipTarget
    local versionTarget

    geositeTarget=$(padmManagedFilePath "${targetDir}" "geosite.dat") || return 1
    geoipTarget=$(padmManagedFilePath "${targetDir}" "geoip.dat") || return 1
    versionTarget=$(padmManagedFilePath "${targetDir}" "geo.version") || return 1

    padmCreateTempFileForTarget geositeStage "${geositeTarget}" geo || return 1
    if ! cp -p "${stageDir}/geosite.dat" "${geositeStage}"; then
        padmRemoveCleanupPath "${geositeStage}"
        return 1
    fi
    padmCreateTempFileForTarget geoipStage "${geoipTarget}" geo || { padmRemoveCleanupPath "${geositeStage}"; return 1; }
    if ! cp -p "${stageDir}/geoip.dat" "${geoipStage}"; then
        padmRemoveCleanupPath "${geositeStage}"
        padmRemoveCleanupPath "${geoipStage}"
        return 1
    fi
    padmCreateTempFileForTarget versionStage "${versionTarget}" geo || {
        padmRemoveCleanupPath "${geositeStage}"
        padmRemoveCleanupPath "${geoipStage}"
        return 1
    }
    if ! printf '%s\n' "${geoVersion}" >"${versionStage}"; then
        padmRemoveCleanupPath "${geositeStage}"
        padmRemoveCleanupPath "${geoipStage}"
        padmRemoveCleanupPath "${versionStage}"
        return 1
    fi
    padmCreateTempPath backupDir -d "$(padmFallbackTmpFilePath padm-xray-geo-backup.XXXXXX)" || {
        padmRemoveCleanupPath "${geositeStage}"
        padmRemoveCleanupPath "${geoipStage}"
        padmRemoveCleanupPath "${versionStage}"
        return 1
    }
    if ! backupXrayGeoFileIfPresent "${geositeTarget}" "${backupDir}/geosite.dat" ||
        ! backupXrayGeoFileIfPresent "${geoipTarget}" "${backupDir}/geoip.dat" ||
        ! backupXrayGeoFileIfPresent "${versionTarget}" "${backupDir}/geo.version"; then
        padmRemoveCleanupPath "${backupDir}"
        padmRemoveCleanupPath "${geositeStage}"
        padmRemoveCleanupPath "${geoipStage}"
        padmRemoveCleanupPath "${versionStage}"
        return 1
    fi
    commitGeneratedFile "${geositeStage}" "${geositeTarget}" 644 || {
        if restoreXrayGeoCommitBackup "${backupDir}" "${geositeTarget}" "${geoipTarget}" "${versionTarget}" >/dev/null 2>&1; then
            padmRemoveCleanupPath "${backupDir}"
        else
            printf 'Xray Geo 文件恢复失败，请手动检查备份目录: %s\n' "${backupDir}" >&2
            padmForgetCleanupPath "${backupDir}"
        fi
        padmRemoveCleanupPath "${geositeStage}"
        padmRemoveCleanupPath "${geoipStage}"
        padmRemoveCleanupPath "${versionStage}"
        return 1
    }
    commitGeneratedFile "${geoipStage}" "${geoipTarget}" 644 || {
        if restoreXrayGeoCommitBackup "${backupDir}" "${geositeTarget}" "${geoipTarget}" "${versionTarget}" >/dev/null 2>&1; then
            padmRemoveCleanupPath "${backupDir}"
        else
            printf 'Xray Geo 文件恢复失败，请手动检查备份目录: %s\n' "${backupDir}" >&2
            padmForgetCleanupPath "${backupDir}"
        fi
        padmRemoveCleanupPath "${geoipStage}"
        padmRemoveCleanupPath "${versionStage}"
        return 1
    }
    commitGeneratedFile "${versionStage}" "${versionTarget}" 644 || {
        if restoreXrayGeoCommitBackup "${backupDir}" "${geositeTarget}" "${geoipTarget}" "${versionTarget}" >/dev/null 2>&1; then
            padmRemoveCleanupPath "${backupDir}"
        else
            printf 'Xray Geo 文件恢复失败，请手动检查备份目录: %s\n' "${backupDir}" >&2
            padmForgetCleanupPath "${backupDir}"
        fi
        padmRemoveCleanupPath "${versionStage}"
        return 1
    }
    padmRemoveCleanupPath "${backupDir}"
}

ensureXrayGeoFiles() {
    local targetDir=$1
    local force=${2:-}

    if [[ "${force}" != "force" && -s "${targetDir}/geosite.dat" && -s "${targetDir}/geoip.dat" ]]; then
        return 0
    fi

    local geoVersion
    geoVersion=$(fetchUrlToStdout "https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases?per_page=1" 3 | jq -r '.[]|.tag_name')
    checkVersionNotEmpty "${geoVersion}"
    echoContent title "\n┌─ Geo 数据版本 ─────────────────────────────────────"
    menuLine "version:${geoVersion}"
    menuClose
    local stageDir
    padmCreateTempPath stageDir -d /etc/padm/tmp.geo.XXXXXX || return 1
    if ! downloadXrayGeoFilesToStage "${stageDir}" "${geoVersion}"; then
        padmRemoveCleanupPath "${stageDir}"
        errorCard "geo文件下载失败"
        return 1
    fi
    if ! commitXrayGeoFilesFromStage "${stageDir}" "${targetDir}" "${geoVersion}"; then
        padmRemoveCleanupPath "${stageDir}"
        errorCard "geo文件写入失败"
        return 1
    fi
    padmRemoveCleanupPath "${stageDir}"
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

showXrayGeoStatus() {
    local targetDir="${1:-/etc/padm/xray}"
    local geoipStatus="缺失"
    local geositeStatus="缺失"
    local cronStatus="未设置"
    [[ -s "${targetDir}/geoip.dat" ]] && geoipStatus="已安装"
    [[ -s "${targetDir}/geosite.dat" ]] && geositeStatus="已安装"
    if crontab -l 2>/dev/null | grep -q "UpdateGeo"; then
        cronStatus="已设置"
    fi
    statusCard "Xray Geo 状态" "geoip.dat：${geoipStatus}" "geosite.dat：${geositeStatus}" "版本：$(xrayGeoDisplayVersion "${targetDir}")" "自动更新：${cronStatus}"
}

# 安装 sing-box
installSingBoxApply() {
    local version
    local prereleaseStatus=${prereleaseStatus:-false}
    local tmpDir=
    local extractedDir=
    local targetBinary=
    local targetCronet=
    local cronetBackup=
    readInstallType
    progressCard "$1" "安装 sing-box"

    if ! singBoxInstalled; then

        version=$(coreLatestReleaseTag SagerNet/sing-box "${prereleaseStatus}")
        checkVersionNotEmpty "${version}"

        successCard "最新版本:${version}"

        padmCreateTempPath tmpDir -d /etc/padm/tmp.sing-box.install.XXXXXX || exit 1
        downloadSingBoxReleaseBinaryToTempDir "${version}" "${tmpDir}"
        local rc=$?
        if [[ "${rc}" -ne 0 ]]; then
            padmRemoveCleanupPath "${tmpDir}"
            case "${rc}" in
            2) errorCard "sing-box解压失败" ;;
            3) errorCard "sing-box安装包缺少libcronet.so" ;;
            4) errorCard "sing-box安装失败" ;;
            *) errorCard "sing-box下载失败" ;;
            esac
            exit 1
        fi

        extractedDir="${tmpDir}/sing-box-${version/v/}${singBoxCoreCPUVendor}"
        targetBinary=$(coreSingBoxBinaryPath)
        targetCronet=$(coreSingBoxCronetPath)
        validateCoreInstallTargetPath "${targetBinary}" "sing-box" || { padmRemoveCleanupPath "${tmpDir}"; exit 1; }
        validateCoreInstallTargetPath "${targetCronet}" "sing-box cronet依赖" || { padmRemoveCleanupPath "${tmpDir}"; exit 1; }
        if [[ -f "${targetCronet}" ]]; then
            cronetBackup="${tmpDir}/libcronet.so.bak"
            cp "${targetCronet}" "${cronetBackup}" || {
                padmRemoveCleanupPath "${tmpDir}"
                errorCard "sing-box cronet依赖备份失败"
                exit 1
            }
        fi
        if ! commitStagedCoreInstallFile "${extractedDir}/libcronet.so" "${targetCronet}" 644; then
            padmRemoveCleanupPath "${tmpDir}"
            errorCard "sing-box cronet依赖安装失败"
            exit 1
        fi
        if ! commitStagedCoreInstallFile "${extractedDir}/sing-box" "${targetBinary}" 655; then
            if ! restoreCoreOptionalFileBackup "${cronetBackup}" "${targetCronet}" 644; then
                padmForgetCleanupPath "${tmpDir}"
                errorCard "sing-box安装失败，cronet依赖回滚失败，请手动检查临时备份: ${tmpDir}"
                exit 1
            fi
            padmRemoveCleanupPath "${tmpDir}"
            errorCard "sing-box安装失败"
            exit 1
        fi
        [[ -n "${cronetBackup}" && -e "${cronetBackup}" ]] && removeManagedFilesIfPresentIgnoreFailure "${cronetBackup}"
        padmRemoveCleanupPath "${tmpDir}"
    else
        successCard "当前版本:$(getSingBoxCurrentVersion)"

        version=$(coreLatestReleaseTag SagerNet/sing-box "${prereleaseStatus}") || exit 1
        checkVersionNotEmpty "${version}"
        successCard "最新版本:${version}"

        if [[ -z "${lastInstallationConfig:-}" ]]; then
            autoRead singbox_reinstall "是否更新、升级？[y/n]:" reInstallSingBoxStatus
            if [[ "${reInstallSingBoxStatus}" == "y" ]]; then
                installDownloadedSingBoxBinary "${version}" || exit 1
            fi
        fi
    fi

}

installSingBox() (
    installSingBoxApply "$@"
)


# 安装 Xray-core
installXrayApply() {
    readInstallType
    local version
    local prereleaseStatus=false
    local tmpDir=
    local targetDir=
    local targetBinary=
    if [[ "${2:-}" == "true" ]]; then
        prereleaseStatus=true
    fi

    progressCard "$1" "安装 Xray"

    if ! xrayInstalled; then

        version=$(coreLatestReleaseTag XTLS/Xray-core "${prereleaseStatus}")
        checkVersionNotEmpty "${version}"
        successCard "Xray-core版本:${version}"
        padmCreateTempPath tmpDir -d /etc/padm/tmp.xray.install.XXXXXX || exit 1
        downloadXrayReleaseBinaryToTempDir "${version}" "${tmpDir}"
        local rc=$?
        if [[ "${rc}" -ne 0 ]]; then
            padmRemoveCleanupPath "${tmpDir}"
            case "${rc}" in
            2) errorCard "Xray-core解压失败" ;;
            3) errorCard "Xray-core安装失败" ;;
            *) errorCard "Xray-core下载失败" ;;
            esac
            exit 1
        fi

        targetDir=$(coreXrayInstallDir)
        targetBinary=$(coreXrayBinaryPath)
        validateCoreInstallTargetPath "${targetBinary}" "Xray-core" || { padmRemoveCleanupPath "${tmpDir}"; exit 1; }
        if ! commitStagedCoreInstallFile "${tmpDir}/xray" "${targetBinary}" 655; then
            padmRemoveCleanupPath "${tmpDir}"
            errorCard "Xray-core安装失败"
            exit 1
        fi
        if ! ensureXrayGeoFiles "${targetDir}" force; then
            removeManagedFilesIfPresentIgnoreFailure "${targetBinary}"
            removeXrayGeoManagedFiles "${targetDir}"
            padmRemoveCleanupPath "${tmpDir}"
            exit 1
        fi
        padmRemoveCleanupPath "${tmpDir}"
    else
        if [[ -z "${lastInstallationConfig:-}" ]]; then
            successCard "Xray-core版本:$(coreXrayCurrentVersion)"
            if ! ensureXrayGeoFiles "$(coreXrayInstallDir)"; then
                exit 1
            fi
            autoRead xray_reinstall "是否更新、升级？[y/n]:" reInstallXrayStatus
            if [[ "${reInstallXrayStatus}" == "y" ]]; then
                version=$(coreLatestReleaseTag XTLS/Xray-core "${prereleaseStatus}")
                checkVersionNotEmpty "${version}"
                installDownloadedXrayBinary "${version}" || exit 1
            fi
        fi
    fi
}

installXray() (
    installXrayApply "$@"
)


# Core lifecycle helpers
coreReleaseTags() {
    local repo=$1
    local prerelease=${2:-false}
    local limit=${3:-20}
    local metadata
    [[ "${repo}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
    [[ "${prerelease}" == "true" || "${prerelease}" == "false" ]] || return 1
    [[ "${limit}" =~ ^[0-9]+$ && "${limit}" -gt 0 && "${limit}" -le 100 ]] || return 1
    metadata=$(fetchUrlToStdout "https://api.github.com/repos/${repo}/releases?per_page=100" 3) || return 1
    jq -er --argjson prerelease "${prerelease}" --argjson limit "${limit}" '
      [.[] | select(.prerelease == $prerelease) | .tag_name | select(type == "string" and length > 0)][: $limit][]
    ' <<<"${metadata}"
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

coreXrayConfigDir() {
    if [[ -n "${PADM_XRAY_CONF_DIR:-}" ]]; then
        printf '%s\n' "${PADM_XRAY_CONF_DIR%/}"
        return
    fi
    printf '%s\n' "${PADM_XRAY_DIR:-/etc/padm/xray}/conf"
}

coreSingBoxBinaryPath() {
    printf '%s\n' "${PADM_SINGBOX_BINARY:-/etc/padm/sing-box/sing-box}"
}

coreXrayInstallDir() {
    dirname -- "$(coreXrayBinaryPath)"
}

coreSingBoxInstallDir() {
    dirname -- "$(coreSingBoxBinaryPath)"
}

coreSingBoxCronetPath() {
    printf '%s/libcronet.so\n' "$(coreSingBoxInstallDir)"
}

validateCoreInstallTargetPath() {
    local targetFile=$1
    local description=$2
    local targetDir
    targetDir=$(dirname -- "${targetFile}")
    if ! padmIsSafeAbsolutePath "${targetFile}" || ! padmIsSafeAbsolutePath "${targetDir}"; then
        errorCard "${description}安装路径异常"
        return 1
    fi
    if [[ -e "${targetDir}" && ! -d "${targetDir}" ]]; then
        local manualCheckMessage
        coreSetManualCheckMessage manualCheckMessage "${description}安装目录异常" " ${targetDir}"
        errorCard "${manualCheckMessage}"
        return 1
    fi
    if ! padmCommitTargetIsFileLike "${targetFile}"; then
        local manualCheckMessage
        coreSetManualCheckMessage manualCheckMessage "${description}安装目标异常" " ${targetFile}"
        errorCard "${manualCheckMessage}"
        return 1
    fi
}

commitStagedCoreInstallFile() {
    local stagedFile=$1
    local targetFile=$2
    local mode=$3
    local tmpFile

    padmIsSafeAbsolutePath "${targetFile}" || return 1
    padmCreateTempFileForTarget tmpFile "${targetFile}" install || return 1
    cp "${stagedFile}" "${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    commitGeneratedFile "${tmpFile}" "${targetFile}" "${mode}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

xrayConfigInstalled() {
    local configDir file
    configDir=$(coreXrayConfigDir)
    [[ -d "${configDir}" ]] || return 1
    for file in "${configDir}"/*.json; do
        [[ -f "${file}" ]] && return 0
    done
    return 1
}

coreXrayCurrentVersion() {
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
    local logFile=${2:-$(coreTmpFilePath padm-core-xray-test.log)}
    local configDir
    configDir=$(coreXrayConfigDir)
    [[ -x "${binary}" ]] || return 1
    [[ -d "${configDir}" ]] || return 1
    "${binary}" -test -confdir "${configDir}" >"${logFile}" 2>&1
}

validateXrayConfigStrictWithBinary() {
    local binary=${1:-/etc/padm/xray/xray}
    local logFile=${2:-$(coreTmpFilePath padm-core-xray-strict-test.log)}
    local configDir
    configDir=$(coreXrayConfigDir)
    [[ -x "${binary}" ]] || return 1
    [[ -d "${configDir}" ]] || return 1
    XRAY_JSON_STRICT=true "${binary}" -test -confdir "${configDir}" >"${logFile}" 2>&1
}

coreTmpFilePath() {
    local fileName=$1
    padmFallbackTmpFilePath "${fileName}"
}

singBoxConfigInstalled() {
    local mergedFile shardDir
    mergedFile=$(singBoxMergedConfigFile)
    shardDir=$(singBoxConfigShardDir)
    [[ -s "${mergedFile}" ]] || compgen -G "${shardDir}*.json" >/dev/null
}

validateSingBoxConfigWithBinary() {
    local binary=${1:-/etc/padm/sing-box/sing-box}
    local logFile=${2:-$(coreTmpFilePath padm-core-sing-box-test.log)}
    [[ -x "${binary}" ]] || return 1
    singBoxConfigInstalled || return 2
    singBoxMergeConfigForValidation "${binary}" "${logFile}" check || { appendSingBoxCompatibilityHints "${logFile}"; return 1; }
}

singBoxCompatibilityAuditCard() {
    statusCard "sing-box 兼容体检" "$@"
}

singBoxPrereleaseCompatibilityCard() {
    statusCard "sing-box 预发布兼容检查" "$@"
}

xrayCompatibilityAuditCard() {
    statusCard "Xray 兼容体检" "$@"
}

xrayStrictValidationCard() {
    statusCard "Xray 严格模式校验" "$@"
}

xrayPrereleaseCompatibilityCard() {
    statusCard "Xray 预发布兼容检查" "$@"
}

xrayConfigValidationCard() {
    statusCard "Xray 配置校验" "$@"
}

singBoxConfigValidationCard() {
    statusCard "sing-box 配置校验" "$@"
}

skipTlsCertificateStatusCard() {
    statusCard "跳过 TLS 证书" "$@"
}

singBoxCompatibilityAuditLog() {
    coreTmpFilePath padm-sing-box-compat-audit.log
}

singBoxCompatibilityAuditStatusFile() {
    coreTmpFilePath padm-sing-box-compat-audit.status
}

singBoxCompatibilityAuditWarnFile() {
    coreTmpFilePath padm-sing-box-compat-audit.warn
}

singBoxCompatibilityAuditReset() {
    : >"${1}"
}

singBoxCompatibilityAuditStatusAdd() {
    local file=$1
    local level=$2
    local message=$3
    printf '%s:%s\n' "${level}" "${message}" >>"${file}"
}

singBoxCompatibilityAuditWarn() {
    local warnFile=$1
    local logFile=$2
    local message=$3
    printf '%s\n' "${message}" >>"${warnFile}"
    printf '[WARN] %s\n' "${message}" >>"${logFile}"
}

singBoxCompatibilityAuditFail() {
    local statusFile=$1
    local logFile=$2
    local message=$3
    singBoxCompatibilityAuditStatusAdd "${statusFile}" fail "${message}"
    printf '[FAIL] %s\n' "${message}" >>"${logFile}"
}

singBoxCompatibilityAuditPass() {
    local statusFile=$1
    local logFile=$2
    local message=$3
    singBoxCompatibilityAuditStatusAdd "${statusFile}" pass "${message}"
    printf '[PASS] %s\n' "${message}" >>"${logFile}"
}

singBoxCompatibilityAuditScanJsonFile() {
    local file=$1
    local statusFile=$2
    local logFile=$3

    if ! jq empty "${file}" >/dev/null 2>&1; then
        singBoxCompatibilityAuditFail "${statusFile}" "${logFile}" "JSON 无法解析：${file}"
        return 0
    fi

    if jq -e '.outbounds[]? | select(.type? == "wireguard")' "${file}" >/dev/null 2>&1; then
        singBoxCompatibilityAuditFail "${statusFile}" "${logFile}" "检测到旧 WireGuard outbound，请改用 endpoints[type=wireguard]：${file}"
    fi
    if jq -e '.outbounds[]? | select(.type? == "block" or .type? == "dns")' "${file}" >/dev/null 2>&1; then
        singBoxCompatibilityAuditFail "${statusFile}" "${logFile}" "检测到 legacy special outbound，请改用 route action：${file}"
    fi
    if jq -e '.. | objects | select(has("domain_strategy"))' "${file}" >/dev/null 2>&1; then
        singBoxCompatibilityAuditFail "${statusFile}" "${logFile}" "检测到旧 domain_strategy，请迁移到 domain_resolver/default_domain_resolver：${file}"
    fi
    if jq -e '.. | objects | select(.dns? and ((.dns.rules? // []) | type == "array")) | .dns.rules[]? | select(has("outbound"))' "${file}" >/dev/null 2>&1; then
        singBoxCompatibilityAuditFail "${statusFile}" "${logFile}" "检测到旧 DNS rule outbound，请迁移到 domain_resolver 或 route resolve：${file}"
    fi
    if jq -e '
        .. | objects | select(.dns? and ((.dns.servers? // []) | type == "array")) | .dns.servers[]? |
        select(type == "string" or (type == "object" and (has("address") or has("detour") or has("strategy")) and (has("type") | not)))
    ' "${file}" >/dev/null 2>&1; then
        singBoxCompatibilityAuditFail "${statusFile}" "${logFile}" "检测到旧 DNS server 格式，请迁移到 typed DNS servers：${file}"
    fi
    if jq -e '
        .. | objects | select(.dns? and ((.dns.rules? // []) | type == "array")) |
        .dns.rules[]? |
        select(
            ((has("ip_version") or has("query_type")) and (has("rule_set_ip_cidr_accept_empty") or has("ip_is_private"))) or
            ((has("ip_version") or has("query_type")) and ((.rule_set // []) | tostring | test("query_type")))
        )
    ' "${file}" >/dev/null 2>&1; then
        singBoxCompatibilityAuditFail "${statusFile}" "${logFile}" "检测到 1.14 不兼容的 DNS 规则混搭，请检查 ip_version/query_type 与 legacy address filter：${file}"
    fi
}

collectSingBoxCompatibilityFindings() {
    local statusFile=$1
    local logFile=$2
    local warnFile=$3
    local file foundJson=false mergedFile shardDir

    singBoxCompatibilityAuditReset "${statusFile}"
    singBoxCompatibilityAuditReset "${warnFile}"
    : >"${logFile}"
    printf 'sing-box 兼容体检\n' >>"${logFile}"

    if ! singBoxInstalled; then
        singBoxCompatibilityAuditWarn "${warnFile}" "${logFile}" "未检测到 sing-box 二进制，跳过兼容体检"
        return 0
    fi
    if ! singBoxConfigInstalled; then
        singBoxCompatibilityAuditWarn "${warnFile}" "${logFile}" "未检测到 sing-box 配置，跳过兼容体检"
        return 0
    fi

    mergedFile=$(singBoxMergedConfigFile)
    shardDir=$(singBoxConfigShardDir)
    while IFS= read -r file; do
        [[ -f "${file}" ]] || continue
        foundJson=true
        singBoxCompatibilityAuditScanJsonFile "${file}" "${statusFile}" "${logFile}"
    done < <(
        [[ -f "${mergedFile}" ]] && printf '%s\n' "${mergedFile}"
        for file in "${shardDir}"*.json; do
            [[ -f "${file}" ]] || continue
            printf '%s\n' "${file}"
        done
    )

    if [[ "${foundJson}" != "true" ]]; then
        singBoxCompatibilityAuditWarn "${warnFile}" "${logFile}" "未找到 sing-box JSON 配置文件"
        return 0
    fi

    if [[ ! -s "${statusFile}" ]]; then
        singBoxCompatibilityAuditPass "${statusFile}" "${logFile}" "未检测到 1.13/1.14 已知兼容风险"
    fi
}

singBoxCompatibilityAuditHasFailures() {
    local statusFile=$1
    grep -q '^fail:' "${statusFile}" 2>/dev/null
}

summarizeSingBoxCompatibilityAudit() {
    local statusFile=$1
    local warnFile=$2
    local failCount=0 passCount=0 warnCount=0

    [[ -f "${statusFile}" ]] && failCount=$(grep -c '^fail:' "${statusFile}" 2>/dev/null || printf '0')
    [[ -f "${statusFile}" ]] && passCount=$(grep -c '^pass:' "${statusFile}" 2>/dev/null || printf '0')
    [[ -f "${warnFile}" ]] && warnCount=$(grep -c '.' "${warnFile}" 2>/dev/null || printf '0')
    printf 'FAIL=%s WARN=%s PASS=%s' "${failCount}" "${warnCount}" "${passCount}"
}

singBoxCompatibilityAuditOverviewSummary() {
    local statusFile warnFile logFile
    statusFile=$(singBoxCompatibilityAuditStatusFile)
    warnFile=$(singBoxCompatibilityAuditWarnFile)
    logFile=$(singBoxCompatibilityAuditLog)
    collectSingBoxCompatibilityFindings "${statusFile}" "${logFile}" "${warnFile}"
    summarizeSingBoxCompatibilityAudit "${statusFile}" "${warnFile}"
}

showSingBoxCompatibilityAudit() {
    local logFile=${1:-$(singBoxCompatibilityAuditLog)}
    local statusFile=${2:-$(singBoxCompatibilityAuditStatusFile)}
    local warnFile=${3:-$(singBoxCompatibilityAuditWarnFile)}

    collectSingBoxCompatibilityFindings "${statusFile}" "${logFile}" "${warnFile}"
    if singBoxCompatibilityAuditHasFailures "${statusFile}"; then
        singBoxCompatibilityAuditCard "发现潜在升级风险" "排查日志: ${logFile}" "重点检查 legacy DNS / WireGuard / special outbounds / domain_strategy"
    elif [[ -s "${warnFile}" ]]; then
        singBoxCompatibilityAuditCard "未发现明确风险" "提示: $(head -n 1 "${warnFile}")" "完整日志: ${logFile}"
    else
        singBoxCompatibilityAuditCard "通过" "未发现 1.13/1.14 已知兼容风险"
    fi
}

downloadSingBoxReleaseBinaryToTemp() {
    local version=$1
    local outVar=$2
    local tmpDirVar=${3:-}
    local tmpDir extractedDir binary

    padmCreateTempPath tmpDir -d "$(coreTmpFilePath padm-sing-box-compat-download.XXXXXX)" || return 1
    downloadSingBoxReleaseBinaryToTempDir "${version}" "${tmpDir}"
    local rc=$?
    if [[ "${rc}" -ne 0 ]]; then
        padmRemoveCleanupPath "${tmpDir}"
        case "${rc}" in
        2) errorCard "sing-box 预发布包解压失败" ;;
        3|4) errorCard "sing-box 预发布包中未找到二进制" ;;
        esac
        return 1
    fi
    extractedDir="${tmpDir}/sing-box-${version/v/}${singBoxCoreCPUVendor}"
    binary="${extractedDir}/sing-box"
    printf -v "${outVar}" '%s' "${binary}"
    if [[ -n "${tmpDirVar}" ]]; then
        printf -v "${tmpDirVar}" '%s' "${tmpDir}"
    fi
}

checkSingBoxPrereleaseCompatibility() {
    local version=${1:-}
    local logFile=${2:-$(coreTmpFilePath padm-core-sing-box-prerelease-audit.log)}
    local downloadedBinary=
    local downloadTmpDir=
    local resolvedVersion=

    resolvedVersion=${version:-$(coreLatestReleaseTag SagerNet/sing-box true)}
    checkVersionNotEmpty "${resolvedVersion}"
    if ! singBoxInstalled; then
        singBoxPrereleaseCompatibilityCard "跳过" "未检测到 sing-box 二进制"
        return 0
    fi
    if ! singBoxConfigInstalled; then
        singBoxPrereleaseCompatibilityCard "跳过" "未检测到 sing-box 配置"
        return 0
    fi
    if ! downloadSingBoxReleaseBinaryToTemp "${resolvedVersion}" downloadedBinary downloadTmpDir; then
        singBoxPrereleaseCompatibilityCard "失败" "预发布二进制下载失败"
        return 1
    fi
    if validateSingBoxConfigWithBinary "${downloadedBinary}" "${logFile}"; then
        singBoxPrereleaseCompatibilityCard "通过" "目标版本: ${resolvedVersion}" "仅执行 dry-run，未替换本机二进制"
        [[ -n "${downloadTmpDir}" ]] && padmRemoveCleanupPath "${downloadTmpDir}"
        return 0
    fi
    singBoxPrereleaseCompatibilityCard "失败" "目标版本: ${resolvedVersion}" "排查日志: ${logFile}" "仅执行 dry-run，未替换本机二进制"
    [[ -n "${downloadTmpDir}" ]] && padmRemoveCleanupPath "${downloadTmpDir}"
    return 1
}

appendXrayCompatibilityHints() {
    local logFile=$1
    [[ -f "${logFile}" ]] || return 0
    if grep -Eqi 'echForceQuery|trustedXForwardedFor|settings\.clients|settings\.accounts|legacy reverse|unknown field.*users|unknown field.*clients|unknown field.*accounts|reverse' "${logFile}"; then
        {
            printf '\n[padm 兼容性提示]\n'
            printf -- '- Xray 26.5.9+ 预发布已开始把 inbounds 的 clients/accounts 收敛到 users，请优先关注旧 settings.clients/settings.accounts。\n'
            printf -- '- XHTTP / WS / HTTPUpgrade 如前置 CDN 或反代，建议显式复核 sockopt.trustedXForwardedFor。\n'
            printf -- '- ECH 相关旧字段 echForceQuery 已移除；legacy reverse 也已不再建议继续使用。\n'
        } >>"${logFile}"
    fi
}

xrayCompatibilityAuditLog() {
    coreTmpFilePath padm-xray-compat-audit.log
}

xrayCompatibilityAuditStatusFile() {
    coreTmpFilePath padm-xray-compat-audit.status
}

xrayCompatibilityAuditWarnFile() {
    coreTmpFilePath padm-xray-compat-audit.warn
}

xrayCompatibilityAuditReset() {
    : >"${1}"
}

xrayCompatibilityAuditStatusAdd() {
    local file=$1
    local level=$2
    local message=$3
    printf '%s:%s\n' "${level}" "${message}" >>"${file}"
}

xrayCompatibilityAuditWarn() {
    local warnFile=$1
    local logFile=$2
    local message=$3
    printf '%s\n' "${message}" >>"${warnFile}"
    printf '[WARN] %s\n' "${message}" >>"${logFile}"
}

xrayCompatibilityAuditFail() {
    local statusFile=$1
    local logFile=$2
    local message=$3
    xrayCompatibilityAuditStatusAdd "${statusFile}" fail "${message}"
    printf '[FAIL] %s\n' "${message}" >>"${logFile}"
}

xrayCompatibilityAuditPass() {
    local statusFile=$1
    local logFile=$2
    local message=$3
    xrayCompatibilityAuditStatusAdd "${statusFile}" pass "${message}"
    printf '[PASS] %s\n' "${message}" >>"${logFile}"
}

xrayCompatibilityAuditScanJsonFile() {
    local file=$1
    local statusFile=$2
    local logFile=$3
    local warnFile=$4

    if ! jq empty "${file}" >/dev/null 2>&1; then
        xrayCompatibilityAuditFail "${statusFile}" "${logFile}" "JSON 无法解析：${file}"
        return 0
    fi

    if jq -e '
        .. | objects |
        select(has("settings") and (.settings | type == "object") and (.settings | has("clients") or has("accounts")))
    ' "${file}" >/dev/null 2>&1; then
        xrayCompatibilityAuditFail "${statusFile}" "${logFile}" "检测到旧 users schema（settings.clients/accounts），升级预发布前请专项复核：${file}"
    fi
    if jq -e '.. | objects | select(has("echForceQuery"))' "${file}" >/dev/null 2>&1; then
        xrayCompatibilityAuditFail "${statusFile}" "${logFile}" "检测到已移除的 echForceQuery：${file}"
    fi
    if jq -e 'type == "object" and has("reverse")' "${file}" >/dev/null 2>&1; then
        xrayCompatibilityAuditFail "${statusFile}" "${logFile}" "检测到 legacy reverse 配置，请在升级前确认迁移方案：${file}"
    fi
    if jq -e '
        .inbounds[]? |
        select(
            (.streamSettings.network? == "ws") or
            (.streamSettings.network? == "httpupgrade") or
            (.streamSettings.network? == "xhttp") or
            (.streamSettings.wsSettings? != null) or
            (.streamSettings.httpupgradeSettings? != null) or
            (.streamSettings.xhttpSettings? != null)
        ) |
        select((((.streamSettings.sockopt.trustedXForwardedFor? // .sockopt.trustedXForwardedFor?) // "") | tostring | length) == 0)
    ' "${file}" >/dev/null 2>&1; then
        xrayCompatibilityAuditWarn "${warnFile}" "${logFile}" "检测到 XHTTP/WS/HTTPUpgrade 入站未设置 trustedXForwardedFor；如前置 CDN/反代请专项复核：${file}"
    fi
    if jq -e '.inbounds[]? | select(.protocol? == "tunnel")' "${file}" >/dev/null 2>&1; then
        xrayCompatibilityAuditWarn "${warnFile}" "${logFile}" "检测到 tunnel inbound；Xray 26.5.9+ 已调整相关字段，请复核 network/address/port 新 schema：${file}"
    fi
    if jq -e '.outbounds[]? | select(.protocol? == "dns")' "${file}" >/dev/null 2>&1; then
        xrayCompatibilityAuditWarn "${warnFile}" "${logFile}" "检测到 DNS outbound；Xray 26.5.9+ 已调整相关字段，请复核 network/address/port 新 schema：${file}"
    fi
}

collectXrayCompatibilityFindings() {
    local statusFile=$1
    local logFile=$2
    local warnFile=$3
    local file foundJson=false configDir

    xrayCompatibilityAuditReset "${statusFile}"
    xrayCompatibilityAuditReset "${warnFile}"
    : >"${logFile}"
    printf 'Xray 兼容体检\n' >>"${logFile}"

    if ! xrayInstalled; then
        xrayCompatibilityAuditWarn "${warnFile}" "${logFile}" "未检测到 Xray 二进制，跳过兼容体检"
        return 0
    fi
    if ! xrayConfigInstalled; then
        xrayCompatibilityAuditWarn "${warnFile}" "${logFile}" "未检测到 Xray 配置，跳过兼容体检"
        return 0
    fi

    configDir=$(coreXrayConfigDir)
    while IFS= read -r file; do
        [[ -f "${file}" ]] || continue
        foundJson=true
        xrayCompatibilityAuditScanJsonFile "${file}" "${statusFile}" "${logFile}" "${warnFile}"
    done < <(find "${configDir}" -maxdepth 1 -type f -name '*.json' | sort)

    if [[ "${foundJson}" != "true" ]]; then
        xrayCompatibilityAuditWarn "${warnFile}" "${logFile}" "未找到 Xray JSON 配置文件"
        return 0
    fi

    if [[ ! -s "${statusFile}" ]] && [[ ! -s "${warnFile}" ]]; then
        xrayCompatibilityAuditPass "${statusFile}" "${logFile}" "未检测到当前预发布已知兼容风险"
    fi
}

xrayCompatibilityAuditHasFailures() {
    local statusFile=$1
    grep -q '^fail:' "${statusFile}" 2>/dev/null
}

summarizeXrayCompatibilityAudit() {
    local statusFile=$1
    local warnFile=$2
    local failCount=0 passCount=0 warnCount=0

    [[ -f "${statusFile}" ]] && failCount=$(grep -c '^fail:' "${statusFile}" 2>/dev/null || printf '0')
    [[ -f "${statusFile}" ]] && passCount=$(grep -c '^pass:' "${statusFile}" 2>/dev/null || printf '0')
    [[ -f "${warnFile}" ]] && warnCount=$(grep -c '.' "${warnFile}" 2>/dev/null || printf '0')
    printf 'FAIL=%s WARN=%s PASS=%s' "${failCount}" "${warnCount}" "${passCount}"
}

xrayCompatibilityAuditOverviewSummary() {
    local statusFile warnFile logFile
    statusFile=$(xrayCompatibilityAuditStatusFile)
    warnFile=$(xrayCompatibilityAuditWarnFile)
    logFile=$(xrayCompatibilityAuditLog)
    collectXrayCompatibilityFindings "${statusFile}" "${logFile}" "${warnFile}"
    summarizeXrayCompatibilityAudit "${statusFile}" "${warnFile}"
}

showXrayCompatibilityAudit() {
    local logFile=${1:-$(xrayCompatibilityAuditLog)}
    local statusFile=${2:-$(xrayCompatibilityAuditStatusFile)}
    local warnFile=${3:-$(xrayCompatibilityAuditWarnFile)}

    collectXrayCompatibilityFindings "${statusFile}" "${logFile}" "${warnFile}"
    if xrayCompatibilityAuditHasFailures "${statusFile}"; then
        xrayCompatibilityAuditCard "发现潜在升级风险" "排查日志: ${logFile}" "重点检查 users schema / echForceQuery / legacy reverse"
    elif [[ -s "${warnFile}" ]]; then
        xrayCompatibilityAuditCard "发现需关注项" "提示: $(head -n 1 "${warnFile}")" "完整日志: ${logFile}"
    else
        xrayCompatibilityAuditCard "通过" "未检测到当前预发布已知兼容风险"
    fi
}

downloadXrayReleaseBinaryToTemp() {
    local version=$1
    local outVar=$2
    local tmpDirVar=${3:-}
    local tmpDir binary

    padmCreateTempPath tmpDir -d "$(coreTmpFilePath padm-xray-compat-download.XXXXXX)" || return 1
    downloadXrayReleaseBinaryToTempDir "${version}" "${tmpDir}"
    local rc=$?
    if [[ "${rc}" -ne 0 ]]; then
        padmRemoveCleanupPath "${tmpDir}"
        case "${rc}" in
        2) errorCard "Xray 预发布包解压失败" ;;
        3) errorCard "Xray 预发布包中未找到二进制" ;;
        esac
        return 1
    fi
    binary="${tmpDir}/xray"
    printf -v "${outVar}" '%s' "${binary}"
    if [[ -n "${tmpDirVar}" ]]; then
        printf -v "${tmpDirVar}" '%s' "${tmpDir}"
    fi
}

showXrayStrictValidation() {
    local logFile=${1:-$(coreTmpFilePath padm-core-xray-strict-test.log)}

    if ! xrayInstalled; then
        xrayStrictValidationCard "跳过" "未检测到 Xray 二进制"
        return 0
    fi
    if ! xrayConfigInstalled; then
        xrayStrictValidationCard "跳过" "未检测到 Xray 配置"
        return 0
    fi
    if validateXrayConfigStrictWithBinary "$(coreXrayBinaryPath)" "${logFile}"; then
        xrayStrictValidationCard "通过"
        return 0
    fi
    appendXrayCompatibilityHints "${logFile}"
    xrayStrictValidationCard "失败" "排查日志: ${logFile}"
    return 1
}

checkXrayPrereleaseCompatibility() {
    local version=${1:-}
    local logFile=${2:-$(coreTmpFilePath padm-core-xray-prerelease-audit.log)}
    local downloadedBinary=
    local downloadTmpDir=
    local resolvedVersion=
    local validateLog strictLog

    resolvedVersion=${version:-$(coreLatestReleaseTag XTLS/Xray-core true)}
    checkVersionNotEmpty "${resolvedVersion}"
    if ! xrayInstalled; then
        xrayPrereleaseCompatibilityCard "跳过" "未检测到 Xray 二进制"
        return 0
    fi
    if ! xrayConfigInstalled; then
        xrayPrereleaseCompatibilityCard "跳过" "未检测到 Xray 配置"
        return 0
    fi
    if ! downloadXrayReleaseBinaryToTemp "${resolvedVersion}" downloadedBinary downloadTmpDir; then
        xrayPrereleaseCompatibilityCard "失败" "预发布二进制下载失败"
        return 1
    fi

    validateLog="${logFile}.validate"
    strictLog="${logFile}.strict"
    if ! validateXrayConfigWithBinary "${downloadedBinary}" "${validateLog}"; then
        cat "${validateLog}" >"${logFile}"
        appendXrayCompatibilityHints "${logFile}"
        xrayPrereleaseCompatibilityCard "失败" "目标版本: ${resolvedVersion}" "普通校验失败，排查日志: ${logFile}" "仅执行 dry-run，未替换本机二进制"
        [[ -n "${downloadTmpDir}" ]] && padmRemoveCleanupPath "${downloadTmpDir}"
        return 1
    fi
    if ! validateXrayConfigStrictWithBinary "${downloadedBinary}" "${strictLog}"; then
        {
            printf '[普通模式校验]\n'
            cat "${validateLog}"
            printf '\n[严格模式校验]\n'
            cat "${strictLog}"
        } >"${logFile}"
        appendXrayCompatibilityHints "${logFile}"
        xrayPrereleaseCompatibilityCard "失败" "目标版本: ${resolvedVersion}" "严格模式校验失败，排查日志: ${logFile}" "仅执行 dry-run，未替换本机二进制"
        [[ -n "${downloadTmpDir}" ]] && padmRemoveCleanupPath "${downloadTmpDir}"
        return 1
    fi
    {
        printf '[普通模式校验]\n'
        cat "${validateLog}"
        printf '\n[严格模式校验]\n'
        cat "${strictLog}"
    } >"${logFile}"
    xrayPrereleaseCompatibilityCard "通过" "目标版本: ${resolvedVersion}" "已通过普通校验和严格模式校验" "仅执行 dry-run，未替换本机二进制"
    [[ -n "${downloadTmpDir}" ]] && padmRemoveCleanupPath "${downloadTmpDir}"
    return 0
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
        logFile=$(coreTmpFilePath padm-core-xray-test.log)
        if validateXrayConfigWithBinary "$(coreXrayBinaryPath)" "${logFile}"; then
            echo "通过"
        else
            echo "失败，查看 ${logFile}"
        fi
    elif [[ "${core}" == "sing-box" ]]; then
        logFile=$(coreTmpFilePath padm-core-sing-box-test.log)
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
    local xrayConfigDir
    local xrayDir
    local xrayBinary
    local xrayVersion="未安装"
    local singBoxVersion="未安装"
    local geoStatus="未安装"
    local geoVersion=""
    local geoCron="未设置"

    xrayConfigDir=$(coreXrayConfigDir)
    xrayDir=$(dirname "${xrayConfigDir}")
    xrayBinary=$(coreXrayBinaryPath)

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
        menuLine "Xray 配置: $(coreDisplayState "$(coreValidationStateWithPaths xray "${xrayBinary}" "${xrayConfigDir}" "$(coreTmpFilePath padm-core-xray-test.log)")")"
        if xrayConfigInstalled; then
            menuLine "Xray 兼容: $(coreDisplayState "$(xrayCompatibilityAuditOverviewSummary)")"
        fi
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
        menuLine "sing-box 兼容: $(coreDisplayState "$(singBoxCompatibilityAuditOverviewSummary)")"
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

coreInstallServiceAction() {
    local failureMessage=$1
    shift
    if ! runCoreServiceActionAllowFailure "$@"; then
        errorCard "${failureMessage}"
        return 1
    fi
}

restoreCoreBinaryBackup() {
    local backupBinary=$1
    local targetBinary=$2
    [[ -f "${backupBinary}" ]] || return 0
    restoreManagedFileFromBackup "${backupBinary}" "${targetBinary}" 655
}

finalizeFailedCoreBinaryInstall() {
    local coreName=$1
    local backupBinary=$2
    local targetBinary=$3
    local startFunction=$4
    local logFile=$5
    local startRestoredService=${6:-true}
    local restoreMessage="无旧二进制需要恢复"
    local serviceRestoreMessage="未尝试恢复服务"
    local restoredBinary=false

    if [[ -f "${backupBinary}" ]]; then
        if restoreCoreBinaryBackup "${backupBinary}" "${targetBinary}"; then
            restoreMessage="已恢复旧二进制"
            restoredBinary=true
            removeManagedFilesIfPresentIgnoreFailure "${backupBinary}"
        else
            restoreMessage="旧二进制恢复失败"
        fi
    fi
    if [[ "${restoredBinary}" == "true" && "${startRestoredService}" == "true" ]]; then
        if runCoreServiceActionAllowFailure "${startFunction}" start >/dev/null 2>&1; then
            serviceRestoreMessage="旧服务已尝试恢复启动"
        else
            coreSetManualCheckMessage serviceRestoreMessage "旧服务恢复启动失败" "服务状态"
        fi
    elif [[ "${restoredBinary}" == "true" ]]; then
        serviceRestoreMessage="旧服务未启动，等待依赖恢复"
    elif [[ -f "${backupBinary}" ]]; then
        serviceRestoreMessage="旧二进制未恢复，已跳过服务启动"
    fi
    statusCard "${coreName} 更新失败" "${restoreMessage}" "${serviceRestoreMessage}" "排查日志: ${logFile}"
    return 1
}

restoreCoreOptionalFileBackup() {
    local backupFile=$1
    local targetFile=$2
    local mode=${3:-644}
    if [[ ! -e "${backupFile}" ]]; then
        padmCommitTargetIsFileLike "${targetFile}" || return 1
        removeManagedFileIfPresent "${targetFile}" || return 1
        return 0
    fi
    restoreManagedFileFromBackup "${backupFile}" "${targetFile}" "${mode}"
}

finalizeFailedSingBoxBinaryInstall() {
    local backupBinary=$1
    local targetBinary=$2
    local cronetBackup=$3
    local cronetPath=$4
    local logFile=$5
    local restoreStatus=0
    local cronetRestored=true

    if ! restoreCoreOptionalFileBackup "${cronetBackup}" "${cronetPath}" 644; then
        cronetRestored=false
    fi
    finalizeFailedCoreBinaryInstall "sing-box" "${backupBinary}" "${targetBinary}" handleSingBox "${logFile}" "${cronetRestored}" || restoreStatus=$?
    if [[ "${cronetRestored}" != "true" ]]; then
        local manualCheckMessage
        coreSetManualCheckMessage manualCheckMessage "libcronet.so 恢复失败" " ${cronetPath}"
        statusCard "sing-box 更新失败" "${manualCheckMessage}" "排查日志: ${logFile}"
        return 1
    fi
    [[ -e "${cronetBackup}" ]] && removeManagedFilesIfPresentIgnoreFailure "${cronetBackup}"
    return "${restoreStatus}"
}

installDownloadedXrayBinary() {
    local version=$1
    local tmpDir oldBinary backupBinary newBinary logFile
    local rc
    logFile=$(coreTmpFilePath padm-core-xray-upgrade-test.log)
    padmCreateTempPath tmpDir -d /etc/padm/tmp.xray.XXXXXX || return 1
    downloadXrayReleaseBinaryToTempDir "${version}" "${tmpDir}"
    rc=$?
    if [[ "${rc}" -ne 0 ]]; then
        padmRemoveCleanupPath "${tmpDir}"
        case "${rc}" in
        2) errorCard "Xray-core 解压失败" ;;
        3) errorCard "Xray-core 资产中未找到 xray 二进制" ;;
        esac
        return 1
    fi
    newBinary="${tmpDir}/xray"
    if xrayConfigInstalled && ! validateXrayConfigWithBinary "${newBinary}" "${logFile}"; then
        padmRemoveCleanupPath "${tmpDir}"
        xrayConfigValidationFailureCard "已取消升级" "排查日志: ${logFile}"
        return 1
    fi

    oldBinary=$(coreXrayBinaryPath)
    validateCoreInstallTargetPath "${oldBinary}" "Xray-core" || { padmRemoveCleanupPath "${tmpDir}"; return 1; }
    backupBinary="${oldBinary}.bak.$(date +%s)"
    if ! padmEnsureSafeDirectory "$(dirname "${oldBinary}")"; then
        padmRemoveCleanupPath "${tmpDir}"
        errorCard "Xray-core 安装目录创建失败"
        return 1
    fi
    if [[ -f "${oldBinary}" ]] && ! backupManagedFileToPath "${oldBinary}" "${backupBinary}" 655; then
        padmRemoveCleanupPath "${tmpDir}"
        errorCard "Xray-core 旧二进制备份失败"
        return 1
    fi
    if ! runCoreServiceActionAllowFailure handleXray stop; then
        padmRemoveCleanupPath "${tmpDir}"
        [[ -f "${backupBinary}" ]] && removeManagedFilesIfPresentIgnoreFailure "${backupBinary}"
        statusCard "Xray-core 更新失败" "Xray 服务停止失败，已取消替换" "排查日志: ${logFile}"
        return 1
    fi
    if ! commitStagedCoreInstallFile "${newBinary}" "${oldBinary}" 655; then
        padmRemoveCleanupPath "${tmpDir}"
        finalizeFailedCoreBinaryInstall "Xray-core" "${backupBinary}" "${oldBinary}" handleXray "${logFile}"
        return 1
    fi
    runCoreServiceActionAllowFailure handleXray start || true
    if xrayInstalled && xrayRunning; then
        successCard "Xray-core更新成功"
        padmRemoveCleanupPath "${tmpDir}"
        [[ -f "${backupBinary}" ]] && removeManagedFilesIfPresentIgnoreFailure "${backupBinary}"
        return 0
    fi
    padmRemoveCleanupPath "${tmpDir}"
    finalizeFailedCoreBinaryInstall "Xray-core" "${backupBinary}" "${oldBinary}" handleXray "${logFile}"
}

installDownloadedSingBoxBinary() {
    local version=$1
    local tmpDir oldBinary backupBinary extractedDir newBinary logFile cronetPath cronetBackup
    local rc
    logFile=$(coreTmpFilePath padm-core-sing-box-upgrade-test.log)
    padmCreateTempPath tmpDir -d /etc/padm/tmp.sing-box.XXXXXX || return 1
    downloadSingBoxReleaseBinaryToTempDir "${version}" "${tmpDir}"
    rc=$?
    if [[ "${rc}" -ne 0 ]]; then
        padmRemoveCleanupPath "${tmpDir}"
        case "${rc}" in
        2) errorCard "sing-box 解压失败" ;;
        3) errorCard "sing-box 资产中缺少 libcronet.so" ;;
        4) errorCard "sing-box 资产中未找到 sing-box 二进制" ;;
        esac
        return 1
    fi
    extractedDir="${tmpDir}/sing-box-${version/v/}${singBoxCoreCPUVendor}"
    newBinary="${extractedDir}/sing-box"
    if singBoxConfigInstalled && ! validateSingBoxConfigWithBinary "${newBinary}" "${logFile}"; then
        padmRemoveCleanupPath "${tmpDir}"
        statusCard "sing-box 配置校验失败" "已取消升级" "排查日志: ${logFile}"
        return 1
    fi

    oldBinary=$(coreSingBoxBinaryPath)
    validateCoreInstallTargetPath "${oldBinary}" "sing-box" || { padmRemoveCleanupPath "${tmpDir}"; return 1; }
    backupBinary="${oldBinary}.bak.$(date +%s)"
    cronetPath=$(coreSingBoxCronetPath)
    validateCoreInstallTargetPath "${cronetPath}" "sing-box cronet依赖" || { padmRemoveCleanupPath "${tmpDir}"; return 1; }
    cronetBackup="${cronetPath}.bak.$(date +%s)"
    if ! padmEnsureSafeDirectory "$(dirname "${oldBinary}")"; then
        padmRemoveCleanupPath "${tmpDir}"
        errorCard "sing-box 安装目录创建失败"
        return 1
    fi
    if [[ -f "${oldBinary}" ]] && ! backupManagedFileToPath "${oldBinary}" "${backupBinary}" 655; then
        padmRemoveCleanupPath "${tmpDir}"
        errorCard "sing-box 旧二进制备份失败"
        return 1
    fi
    if [[ -f "${cronetPath}" ]] && ! backupManagedFileToPath "${cronetPath}" "${cronetBackup}" 644; then
        padmRemoveCleanupPath "${tmpDir}"
        [[ -f "${backupBinary}" ]] && removeManagedFilesIfPresentIgnoreFailure "${backupBinary}"
        errorCard "sing-box 旧 cronet 依赖备份失败"
        return 1
    fi
    if ! runCoreServiceActionAllowFailure handleSingBox stop; then
        padmRemoveCleanupPath "${tmpDir}"
        [[ -f "${backupBinary}" ]] && removeManagedFilesIfPresentIgnoreFailure "${backupBinary}"
        [[ -f "${cronetBackup}" ]] && removeManagedFilesIfPresentIgnoreFailure "${cronetBackup}"
        statusCard "sing-box 更新失败" "sing-box 服务停止失败，已取消替换" "排查日志: ${logFile}"
        return 1
    fi
    if ! commitStagedCoreInstallFile "${newBinary}" "${oldBinary}" 655; then
        padmRemoveCleanupPath "${tmpDir}"
        finalizeFailedSingBoxBinaryInstall "${backupBinary}" "${oldBinary}" "${cronetBackup}" "${cronetPath}" "${logFile}"
        return 1
    fi
    if ! commitStagedCoreInstallFile "${extractedDir}/libcronet.so" "${cronetPath}" 644; then
        padmRemoveCleanupPath "${tmpDir}"
        finalizeFailedSingBoxBinaryInstall "${backupBinary}" "${oldBinary}" "${cronetBackup}" "${cronetPath}" "${logFile}"
        return 1
    fi
    runCoreServiceActionAllowFailure handleSingBox start || true
    if singBoxInstalled && singBoxRunning; then
        successCard "sing-box更新成功"
        padmRemoveCleanupPath "${tmpDir}"
        [[ -f "${backupBinary}" ]] && removeManagedFilesIfPresentIgnoreFailure "${backupBinary}"
        [[ -f "${cronetBackup}" ]] && removeManagedFilesIfPresentIgnoreFailure "${cronetBackup}"
        return 0
    fi
    padmRemoveCleanupPath "${tmpDir}"
    finalizeFailedSingBoxBinaryInstall "${backupBinary}" "${oldBinary}" "${cronetBackup}" "${cronetPath}" "${logFile}"
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
    [[ "${prerelease}" == "true" ]] && channel="预发布版"
    version=${version:-$(coreLatestReleaseTag XTLS/Xray-core "${prerelease}")}
    checkVersionNotEmpty "${version}"
    if [[ "${prerelease}" == "true" ]]; then
        if ! checkXrayPrereleaseCompatibility "${version}" "$(coreTmpFilePath padm-core-xray-prerelease-audit.log)"; then
            return 1
        fi
    fi
    confirmCoreUpgrade "Xray-core" "${version}" "${channel}" || { coreCancelledStatusCard "未更新 Xray-core"; return 0; }
    installDownloadedXrayBinary "${version}"
}

upgradeSingBoxCore() {
    local prerelease=${1:-false}
    local version=${2:-}
    local channel="稳定版"
    [[ "${prerelease}" == "true" ]] && channel="预发布版"
    version=${version:-$(coreLatestReleaseTag SagerNet/sing-box "${prerelease}")}
    checkVersionNotEmpty "${version}"
    if [[ "${prerelease}" == "true" ]]; then
        if ! checkSingBoxPrereleaseCompatibility "${version}" "$(coreTmpFilePath padm-core-sing-box-prerelease-audit.log)"; then
            return 1
        fi
    fi
    confirmCoreUpgrade "sing-box" "${version}" "${channel}" || { coreCancelledStatusCard "未更新 sing-box"; return 0; }
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
    menuItem 2 "检查预发布兼容性" "只校验最新 prerelease，不替换本机二进制"
    menuItem 3 "升级预发布版" "下载 prerelease，适合验证新能力"
    menuItem 4 "回退稳定版" "选择最近稳定版本回退"
    menuItem 5 "校验配置" "执行 xray -test -confdir"
    menuItem 6 "严格模式校验" "执行 XRAY_JSON_STRICT=true xray -test"
    menuItem 7 "兼容体检" "扫描 users schema / ECH / legacy reverse 风险"
    menuItem 8 "更新 Geo 数据" "更新 geosite.dat / geoip.dat"
    menuItem 9 "查看 Geo 状态" "查看文件、版本和自动更新状态"
    menuItem 10 "设置 Geo 自动更新" "每天凌晨更新 Xray Geo 数据"
    menuItem 11 "服务控制" "启动、停止、重启 Xray"
    menuItem 12 "日志管理" "查看或调整 Xray 日志"
    menuReturnItem 13 "返回核心与服务" "回到核心生命周期管理"
    menuClose
    autoRead xray_lifecycle_menu "请选择:" selectXrayType
    case "${selectXrayType}" in
    1) upgradeXrayCore false ;;
    2) checkXrayPrereleaseCompatibility ;;
    3) upgradeXrayCore true ;;
    4)
        version=$(selectRollbackVersion XTLS/Xray-core "Xray-core") || { coreInvalidInputRetryMenu xrayVersionManageMenu; return; }
        upgradeXrayCore false "${version}"
        ;;
    5)
        local logFile
        logFile=$(coreTmpFilePath padm-core-xray-test.log)
        if validateXrayConfigWithBinary "$(coreXrayBinaryPath)" "${logFile}"; then
            xrayConfigValidationCard "通过"
        else
            xrayConfigValidationCard "失败" "排查日志: ${logFile}"
        fi
        ;;
    6) showXrayStrictValidation ;;
    7) showXrayCompatibilityAudit ;;
    8) updateGeoSite ;;
    9) showXrayGeoStatus ;;
    10) installCronUpdateGeo ;;
    11) coreServiceControlMenu xray ;;
    12) checkLog 1 ;;
    13) coreVersionManageMenu ;;
    *) coreInvalidInputRetryMenu xrayVersionManageMenu ;;
    esac
}

updateGeoSite() {
    local targetDir="/etc/padm/xray"
    local oldVersion newVersion
    oldVersion=$(xrayGeoDisplayVersion "${targetDir}")
    if ! ensureXrayGeoFiles "${targetDir}" force; then
        return 1
    fi

    newVersion=$(xrayGeoDisplayVersion "${targetDir}")
    if [[ "${oldVersion}" != "${newVersion}" ]]; then
        if ! reloadCore; then
            statusCard "Geo 数据" "Geo 数据已更新，但核心重载失败，请检查核心服务日志"
            return 1
        fi
    fi
    statusCard "Geo 数据" "更新完毕" "当前版本：${newVersion}"
}

# 验证整个服务是否可用
checkGFWStatue() {
    local serviceCheckAttempts=${PADM_CHECK_GFW_SERVICE_ATTEMPTS:-30}
    local serviceCheckInterval=${PADM_CHECK_GFW_SERVICE_INTERVAL:-0.2}
    readInstallType
    progressCard "$1" "验证服务启动状态"
    if [[ "${coreInstallType}" == "1" ]] && waitForServiceState xrayRunning running "${serviceCheckAttempts}" "${serviceCheckInterval}"; then
        successCard "服务启动成功"
    elif [[ "${coreInstallType}" == "2" ]] && waitForServiceState singBoxRunning running "${serviceCheckAttempts}" "${serviceCheckInterval}"; then
        successCard "服务启动成功"
    else
        errorCard "服务启动失败，请检查终端是否有日志打印"
        return 1
    fi
}


# 安装alpine开机启动
installAlpineStartup() {
    local serviceName=$1
    local tmpFile
    padmCreateTempPath tmpFile "$(coreTmpFilePath "padm-${serviceName}.init.XXXXXX")" || return 1

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

    local serviceFile="/etc/init.d/${serviceName}"
    if [[ "${serviceName}" == "sing-box" ]]; then
        serviceFile=${PADM_SINGBOX_OPENRC_SERVICE_FILE:-${serviceFile}}
    elif [[ "${serviceName}" == "xray" ]]; then
        serviceFile=${PADM_XRAY_OPENRC_SERVICE_FILE:-${serviceFile}}
    fi
    commitGeneratedFile "${tmpFile}" "${serviceFile}" 755
}

coreStartupServiceEnabled() {
    local serviceName=$1
    if [[ "${release}" == "alpine" ]]; then
        command -v rc-update >/dev/null 2>&1 || return 1
        rc-update show default 2>/dev/null | awk '{print $1}' | grep -qx "${serviceName}"
    else
        command -v systemctl >/dev/null 2>&1 || return 1
        systemctl is-enabled --quiet "${serviceName}.service" >/dev/null 2>&1
    fi
}

restoreCoreStartupServiceInstall() {
    local backupDir=$1
    local serviceName=$2
    local serviceWasEnabled=$3
    local rollbackFailed=false

    checkLogBackupRestore "${backupDir}" || rollbackFailed=true
    if [[ "${release}" == "alpine" ]]; then
        if command -v rc-update >/dev/null 2>&1; then
            if [[ "${serviceWasEnabled}" == "true" ]]; then
                rc-update add "${serviceName}" default >/dev/null 2>&1 || rollbackFailed=true
            elif coreStartupServiceEnabled "${serviceName}"; then
                rc-update del "${serviceName}" default >/dev/null 2>&1 || rollbackFailed=true
            fi
        elif [[ "${serviceWasEnabled}" == "true" ]]; then
            rollbackFailed=true
        fi
    else
        systemctl daemon-reload >/dev/null 2>&1 || rollbackFailed=true
        if [[ "${serviceWasEnabled}" == "true" ]]; then
            systemctl enable "${serviceName}.service" >/dev/null 2>&1 || rollbackFailed=true
        elif systemctl is-enabled --quiet "${serviceName}.service" >/dev/null 2>&1; then
            systemctl disable "${serviceName}.service" >/dev/null 2>&1 || rollbackFailed=true
        fi
    fi
    if [[ "${rollbackFailed}" == "true" ]]; then
        padmForgetCleanupPath "${backupDir}"
        return 1
    fi
    padmRemoveCleanupPath "${backupDir}"
}

failCoreStartupServiceInstall() {
    local backupDir=$1
    local serviceName=$2
    local serviceWasEnabled=$3
    local reason=$4
    if restoreCoreStartupServiceInstall "${backupDir}" "${serviceName}" "${serviceWasEnabled}"; then
        errorCard "${reason}，已恢复安装前服务状态"
    else
        errorCard "${reason}，且安装前服务状态恢复失败" "请手动检查备份目录: ${backupDir}"
    fi
    return 1
}


# sing-box开机自启
installSingBoxService() {
    progressCard "$1" "配置 sing-box 开机自启"
    local execStart='/etc/padm/sing-box/sing-box run -c /etc/padm/sing-box/conf/config.json'
    local serviceFile=
    local serviceBackupDir=
    local serviceWasEnabled=false

    if [[ -n $(find /bin /usr/bin -name "systemctl") && "${release}" != "alpine" ]]; then
        serviceFile=${PADM_SINGBOX_SYSTEMD_SERVICE_FILE:-/etc/systemd/system/sing-box.service}
        local tmpFile
        padmCreateTempPath tmpFile "$(coreTmpFilePath padm-sing-box.service.XXXXXX)" || return 1
        cat <<EOF >"${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
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
ExecReload=/bin/kill -HUP \$MAINPID
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
            return 1
        fi
        coreStartupServiceEnabled sing-box && serviceWasEnabled=true
        checkLogBackupCreate serviceBackupDir "${serviceFile}" || { padmRemoveCleanupPath "${tmpFile}"; errorCard "sing-box systemd 模板备份失败"; return 1; }
        if ! commitGeneratedFile "${tmpFile}" "${serviceFile}" 644; then
            padmRemoveCleanupPath "${tmpFile}"
            failCoreStartupServiceInstall "${serviceBackupDir}" sing-box "${serviceWasEnabled}" "sing-box systemd 模板提交失败"
            return 1
        fi
        if ! bootStartup "sing-box.service"; then
            failCoreStartupServiceInstall "${serviceBackupDir}" sing-box "${serviceWasEnabled}" "sing-box 开机自启配置失败"
            return 1
        fi
        padmRemoveCleanupPath "${serviceBackupDir}"
    elif [[ "${release}" == "alpine" ]]; then
        serviceFile=${PADM_SINGBOX_OPENRC_SERVICE_FILE:-/etc/init.d/sing-box}
        coreStartupServiceEnabled sing-box && serviceWasEnabled=true
        checkLogBackupCreate serviceBackupDir "${serviceFile}" || { errorCard "sing-box OpenRC 模板备份失败"; return 1; }
        if ! installAlpineStartup "sing-box"; then
            failCoreStartupServiceInstall "${serviceBackupDir}" sing-box "${serviceWasEnabled}" "sing-box OpenRC 模板提交失败"
            return 1
        fi
        if ! bootStartup "sing-box"; then
            failCoreStartupServiceInstall "${serviceBackupDir}" sing-box "${serviceWasEnabled}" "sing-box 开机自启配置失败"
            return 1
        fi
        padmRemoveCleanupPath "${serviceBackupDir}"
    fi

    successCard "配置sing-box开机启动完毕"
}


# Xray-core 开机自启
installXrayService() {
    progressCard "$1" "配置 Xray 开机自启"
    local execStart='/etc/padm/xray/xray run -confdir /etc/padm/xray/conf'
    local serviceFile=
    local serviceBackupDir=
    local serviceWasEnabled=false
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]]; then
        serviceFile=${PADM_XRAY_SYSTEMD_SERVICE_FILE:-/etc/systemd/system/xray.service}
        local tmpFile
        padmCreateTempPath tmpFile "$(coreTmpFilePath padm-xray.service.XXXXXX)" || return 1
        cat <<EOF >"${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
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
            return 1
        fi
        coreStartupServiceEnabled xray && serviceWasEnabled=true
        checkLogBackupCreate serviceBackupDir "${serviceFile}" || { padmRemoveCleanupPath "${tmpFile}"; errorCard "Xray systemd 模板备份失败"; return 1; }
        if ! commitGeneratedFile "${tmpFile}" "${serviceFile}" 644; then
            padmRemoveCleanupPath "${tmpFile}"
            failCoreStartupServiceInstall "${serviceBackupDir}" xray "${serviceWasEnabled}" "Xray systemd 模板提交失败"
            return 1
        fi
        if ! bootStartup "xray.service"; then
            failCoreStartupServiceInstall "${serviceBackupDir}" xray "${serviceWasEnabled}" "Xray 开机自启配置失败"
            return 1
        fi
        padmRemoveCleanupPath "${serviceBackupDir}"
        successCard "配置Xray开机自启成功"
    elif [[ "${release}" == "alpine" ]]; then
        serviceFile=${PADM_XRAY_OPENRC_SERVICE_FILE:-/etc/init.d/xray}
        coreStartupServiceEnabled xray && serviceWasEnabled=true
        checkLogBackupCreate serviceBackupDir "${serviceFile}" || { errorCard "Xray OpenRC 模板备份失败"; return 1; }
        if ! installAlpineStartup "xray"; then
            failCoreStartupServiceInstall "${serviceBackupDir}" xray "${serviceWasEnabled}" "Xray OpenRC 模板提交失败"
            return 1
        fi
        if ! bootStartup "xray"; then
            failCoreStartupServiceInstall "${serviceBackupDir}" xray "${serviceWasEnabled}" "Xray 开机自启配置失败"
            return 1
        fi
        padmRemoveCleanupPath "${serviceBackupDir}"
    fi
}


# 读取 Xray 用户数据并初始化
stripClientNameSuffix() {
    local label=$1
    local suffix
    for suffix in \
        '-VLESS_TCP/TLS_Vision' \
        '-VLESS_WS' \
        '-VLESS_Reality_XHTTP' \
        '-Trojan_gRPC' \
        '-VMess_WS' \
        '-trojan_tcp' \
        '-Trojan_TCP' \
        '-vless_grpc' \
        '-singbox_hysteria2' \
        '-vless_reality_vision' \
        '-vless_reality_grpc' \
        '-VLESS_Reality_Vision' \
        '-VLESS_Reality_gPRC' \
        '-singbox_tuic' \
        '-singbox_naive' \
        '-VMess_HTTPUpgrade' \
        '-Trojan_TCP_direct' \
        '-shadowsocks' \
        '-anytls'; do
        if [[ "${label}" == *"${suffix}" ]]; then
            printf '%s' "${label%"${suffix}"}"
            return 0
        fi
    done
    printf '%s' "${label}"
}

appendJsonObject() {
    local json=$1
    local objectFilter=$2
    shift 2
    jq -c "$@" ". + [${objectFilter}]" <<<"${json}"
}

writeUserConfigJq() {
    local targetPath=$1
    local jqFilter=$2
    local tmpPath

    shift 2
    targetPath=$(padmRequireSafeAbsolutePath "${targetPath}") || return 1
    padmCreateTempFileForTarget tmpPath "${targetPath}" user || return 1
    if ! jq "$@" "${jqFilter}" "${targetPath}" >"${tmpPath}"; then
        padmRemoveCleanupPath "${tmpPath}"
        return 1
    fi
    commitGeneratedJsonFile "${tmpPath}" "${targetPath}" || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
}

removeUserFromConfigFile() {
    local targetPath=$1
    local userPath=$2
    local targetId=$3
    local targetAccount=$4
    local jqFilter

    [[ -f "${targetPath}" ]] || return 0
    jqFilter='
      def padm_user_account:
        (.email // .name // .username // "")
        | sub("-(VLESS_TCP/TLS_Vision|VLESS_WS|VLESS_Reality_XHTTP|Trojan_gRPC|VMess_WS|trojan_tcp|Trojan_TCP|Trojan_TCP_direct|vless_grpc|singbox_hysteria2|vless_reality_vision|vless_reality_grpc|VLESS_Reality_Vision|VLESS_Reality_gPRC|singbox_tuic|singbox_naive|VMess_HTTPUpgrade|shadowsocks|anytls)$"; "");
      '"${userPath}"' = (('"${userPath}"' // []) | map(select(
        (($targetId == "") or ((.id // .uuid // .password // "") != $targetId)) and
        (($targetAccount == "") or (padm_user_account != $targetAccount))
      )))'
    writeUserConfigJq "${targetPath}" "${jqFilter}" --arg targetId "${targetId}" --arg targetAccount "${targetAccount}"
}

removeUserFromConfigFiles() {
    local targetId=$1
    local targetAccount=$2
    local status=0

    removeUserFromConfigFile "${configPath}02_VLESS_TCP_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
    removeUserFromConfigFile "${configPath}03_VLESS_WS_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
    removeUserFromConfigFile "${configPath}04_trojan_gRPC_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
    removeUserFromConfigFile "${configPath}04_trojan_GRPc_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
    removeUserFromConfigFile "${configPath}05_VMess_WS_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
    removeUserFromConfigFile "${configPath}06_VLESS_GRPc_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
    removeUserFromConfigFile "${configPath}06_VLESS_gRPC_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
    removeUserFromConfigFile "${configPath}04_trojan_TCP_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
    removeUserFromConfigFile "${configPath}07_VLESS_vision_reality_inbounds.json" ".inbounds[1].settings.clients" "${targetId}" "${targetAccount}" || status=1
    removeUserFromConfigFile "${configPath}08_VLESS_vision_gRPC_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
    removeUserFromConfigFile "${configPath}11_VMess_HTTPUpgrade_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
    removeUserFromConfigFile "${configPath}12_VLESS_XHTTP_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
    removeUserFromConfigFile "${configPath}28_trojan_TCP_direct_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1

    if [[ -n "${singBoxConfigPath:-}" ]]; then
        removeUserFromConfigFile "${singBoxConfigPath}02_VLESS_TCP_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${singBoxConfigPath}03_VLESS_WS_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${singBoxConfigPath}05_VMess_WS_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${singBoxConfigPath}06_hysteria2_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${singBoxConfigPath}07_VLESS_vision_reality_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${singBoxConfigPath}09_tuic_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${singBoxConfigPath}10_naive_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${singBoxConfigPath}13_anytls_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${singBoxConfigPath}28_trojan_TCP_direct_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${singBoxConfigPath}30_shadowsocks_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
    fi
    return "${status}"
}

shadowsocks2022KeyFromSeed() {
    local seed=$1
    local hex escaped

    hex=$(printf '%s' "${seed}" | sha256sum | awk '{print substr($1, 1, 32)}') || return 1
    escaped=$(printf '%s' "${hex}" | sed 's/../\\x&/g') || return 1
    printf '%b' "${escaped}" | base64 | tr -d '\n'
}

initXrayClients() {
    local type=",$1,"
    local newUUID=${2:-}
    local newEmail=${3:-}
    local clientRows user uuid email
    jq -e 'type == "array"' <<<"${currentClients}" >/dev/null 2>&1 || return 1
    if [[ -n "${newUUID}" ]]; then
        currentClients=$(appendJsonObject "${currentClients}" '{id:$uuid,flow:"xtls-rprx-vision",email:$email}' --arg uuid "${newUUID}" --arg email "${newEmail}-VLESS_TCP/TLS_Vision") || return 1
    fi
    local users=
    users=[]
    clientRows=$(jq -c '.[]' <<<"${currentClients}") || return 1
    while IFS= read -r user; do
        [[ -n "${user}" ]] || continue
        uuid=$(jq -r '.id // .uuid // empty' <<<"${user}") || return 1
        email=$(jq -r '.email // .name // .username // empty' <<<"${user}") || return 1
        [[ -n "${uuid}" && -n "${email}" ]] || return 1
        email=$(stripClientNameSuffix "${email}") || return 1
        if protocolSelectionIncludes "${type}" 27; then
            users=$(appendJsonObject "${users}" '{id:$uuid,flow:"xtls-rprx-vision",email:$email}' --arg uuid "${uuid}" --arg email "${email}-VLESS_TCP/TLS_Vision") || return 1
        fi

        # VLESS WS
        if protocolSelectionIncludes "${type}" 21; then
            users=$(appendJsonObject "${users}" '{id:$uuid,email:$email}' --arg uuid "${uuid}" --arg email "${email}-VLESS_WS") || return 1
        fi
        # VLESS XHTTP
        if protocolSelectionIncludes "${type}" 2; then
            users=$(appendJsonObject "${users}" '{id:$uuid,email:$email}' --arg uuid "${uuid}" --arg email "${email}-VLESS_Reality_XHTTP") || return 1
        fi
        # Trojan gRPC
        if protocolSelectionIncludes "${type}" 25; then
            users=$(appendJsonObject "${users}" '{password:$password,email:$email}' --arg password "${uuid}" --arg email "${email}-Trojan_gRPC") || return 1
        fi
        # VMess WS
        if protocolSelectionIncludes "${type}" 22; then
            users=$(appendJsonObject "${users}" '{id:$uuid,email:$email,alterId:0}' --arg uuid "${uuid}" --arg email "${email}-VMess_WS") || return 1
        fi
        # VMess HTTPUpgrade
        if protocolSelectionIncludes "${type}" 23; then
            users=$(appendJsonObject "${users}" '{id:$uuid,email:$email,alterId:0}' --arg uuid "${uuid}" --arg email "${email}-VMess_HTTPUpgrade") || return 1
        fi

        # Trojan TCP
        if protocolSelectionIncludes "${type}" 28; then
            users=$(appendJsonObject "${users}" '{password:$password,email:$email}' --arg password "${uuid}" --arg email "${email}-Trojan_TCP_direct") || return 1
        fi

        if protocolSelectionIncludes "${type}" 29; then
            users=$(appendJsonObject "${users}" '{password:$password,email:$email}' --arg password "${uuid}" --arg email "${email}-trojan_tcp") || return 1
        fi

        # VLESS gRPC
        if protocolSelectionIncludes "${type}" 24; then
            users=$(appendJsonObject "${users}" '{id:$uuid,email:$email}' --arg uuid "${uuid}" --arg email "${email}-vless_grpc") || return 1
        fi

        # VLESS Reality Vision
        if protocolSelectionIncludes "${type}" 1; then
            users=$(appendJsonObject "${users}" '{id:$uuid,email:$email,flow:"xtls-rprx-vision"}' --arg uuid "${uuid}" --arg email "${email}-vless_reality_vision") || return 1
        fi

        # VLESS Reality gRPC
        if protocolSelectionIncludes "${type}" 26; then
            users=$(appendJsonObject "${users}" '{id:$uuid,email:$email}' --arg uuid "${uuid}" --arg email "${email}-vless_reality_grpc") || return 1
        fi
    done <<<"${clientRows}"
    printf '%s\n' "${users}"
}

# 读取 sing-box 用户数据并初始化
initSingBoxClients() {
    local type=",$1,"
    local newUUID=${2:-}
    local newName=${3:-}
    local clientRows user uuid name

    jq -e 'type == "array"' <<<"${currentClients}" >/dev/null 2>&1 || return 1
    if [[ -n "${newUUID}" ]]; then
        currentClients=$(appendJsonObject "${currentClients}" '{uuid:$uuid,flow:"xtls-rprx-vision",name:$name}' --arg uuid "${newUUID}" --arg name "${newName}-VLESS_TCP/TLS_Vision") || return 1
    fi
    local users=
    users=[]
    clientRows=$(jq -c '.[]' <<<"${currentClients}") || return 1
    while IFS= read -r user; do
        [[ -n "${user}" ]] || continue
        uuid=$(jq -r '.uuid // .id // .password // empty' <<<"${user}") || return 1
        name=$(jq -r '.name // .email // .username // empty' <<<"${user}") || return 1
        [[ -n "${uuid}" && -n "${name}" ]] || return 1
        name=$(stripClientNameSuffix "${name}") || return 1
        # VLESS Vision
        if protocolSelectionIncludes "${type}" 27; then
            users=$(appendJsonObject "${users}" '{uuid:$uuid,flow:"xtls-rprx-vision",name:$name}' --arg uuid "${uuid}" --arg name "${name}-VLESS_TCP/TLS_Vision") || return 1
        fi
        # VLESS WS
        if protocolSelectionIncludes "${type}" 21; then
            users=$(appendJsonObject "${users}" '{uuid:$uuid,name:$name}' --arg uuid "${uuid}" --arg name "${name}-VLESS_WS") || return 1
        fi
        # VMess WS
        if protocolSelectionIncludes "${type}" 22; then
            users=$(appendJsonObject "${users}" '{uuid:$uuid,name:$name,alterId:0}' --arg uuid "${uuid}" --arg name "${name}-VMess_WS") || return 1
        fi

        # Trojan TCP
        if protocolSelectionIncludes "${type}" 28; then
            users=$(appendJsonObject "${users}" '{password:$password,name:$name}' --arg password "${uuid}" --arg name "${name}-Trojan_TCP") || return 1
        fi

        # Shadowsocks
        if protocolSelectionIncludes "${type}" 30; then
            local ssPassword
            ssPassword=$(shadowsocks2022KeyFromSeed "user:${uuid}") || return 1
            users=$(appendJsonObject "${users}" '{password:$password,name:$name}' --arg password "${ssPassword}" --arg name "${name}-shadowsocks") || return 1
        fi

        # VLESS Reality Vision
        if protocolSelectionIncludes "${type}" 1; then
            users=$(appendJsonObject "${users}" '{uuid:$uuid,flow:"xtls-rprx-vision",name:$name}' --arg uuid "${uuid}" --arg name "${name}-VLESS_Reality_Vision") || return 1
        fi
        # VLESS Reality gRPC
        if protocolSelectionIncludes "${type}" 26; then
            users=$(appendJsonObject "${users}" '{uuid:$uuid,name:$name}' --arg uuid "${uuid}" --arg name "${name}-VLESS_Reality_gPRC") || return 1
        fi

        # Hysteria2
        if protocolSelectionIncludes "${type}" 3; then
            users=$(appendJsonObject "${users}" '{password:$password,name:$name}' --arg password "${uuid}" --arg name "${name}-singbox_hysteria2") || return 1
        fi

        # TUIC
        if protocolSelectionIncludes "${type}" 31; then
            users=$(appendJsonObject "${users}" '{uuid:$uuid,password:$password,name:$name}' --arg uuid "${uuid}" --arg password "${uuid}" --arg name "${name}-singbox_tuic") || return 1
        fi

        # Naive
        if protocolSelectionIncludes "${type}" 5; then
            users=$(appendJsonObject "${users}" '{password:$password,username:$username}' --arg password "${uuid}" --arg username "${name}-singbox_naive") || return 1
        fi
        # VMess HTTPUpgrade
        if protocolSelectionIncludes "${type}" 23; then
            users=$(appendJsonObject "${users}" '{uuid:$uuid,name:$name,alterId:0}' --arg uuid "${uuid}" --arg name "${name}-VMess_HTTPUpgrade") || return 1
        fi
        # AnyTLS
        if protocolSelectionIncludes "${type}" 4; then
            users=$(appendJsonObject "${users}" '{password:$password,name:$name}' --arg password "${uuid}" --arg name "${name}-anytls") || return 1
        fi

        if protocolSelectionIncludes "${type}" 201; then
            users=$(appendJsonObject "${users}" '{username:$username,password:$password}' --arg username "${uuid}" --arg password "${uuid}") || return 1
        fi

    done <<<"${clientRows}"
    printf '%s\n' "${users}"
}


# 安装 Xray-core
installXrayRealityApply() {
    local nginxWasRunning=false
    local previousServiceActions="${SERVICE_ACTIONS:-}"
    local installFailure=
    local restoreFailed=false
    selectCustomInstallType=",1,"
    readLastInstallationConfig || return 1
    totalProgress=6
    installTools 1

    nginxRunning && nginxWasRunning=true
    coreInstallServiceAction "Nginx 服务停止失败，已取消 Xray Reality 安装" handleNginx stop || return 1
    if subscriptionWireGuardControlEnabled; then
        if ! refreshSubscriptionWireGuardNginxControl; then
            installFailure="WireGuard Nginx 控制面刷新失败"
        fi
    fi

    if [[ -z "${installFailure}" ]] && ! (installXray 2 false); then
        installFailure="Xray 安装失败"
    fi
    if [[ -z "${installFailure}" ]] && ! initXrayConfig custom 3; then
        installFailure="Xray Reality 配置初始化失败"
    fi
    if [[ -z "${installFailure}" ]] && ! cleanUp singBoxDel; then
        installFailure="旧 sing-box 配置清理失败"
    fi
    if [[ -z "${installFailure}" ]] && ! installXrayService 4; then
        installFailure="Xray 服务安装失败"
    fi
    if [[ -z "${installFailure}" ]]; then
        serviceQueueRestart xray
        serviceQueueApply || installFailure="Xray Reality 服务应用失败"
    fi
    if [[ -n "${installFailure}" ]]; then
        SERVICE_ACTIONS="${previousServiceActions}"
        if [[ "${nginxWasRunning}" == "true" ]]; then
            nginxRunning || runCoreServiceActionAllowFailure handleNginx start || restoreFailed=true
        elif nginxRunning; then
            runCoreServiceActionAllowFailure handleNginx stop || restoreFailed=true
        fi
        if [[ "${restoreFailed}" == "true" ]]; then
            errorCard "${installFailure}，且 Nginx 运行状态恢复失败"
        else
            errorCard "${installFailure}，已恢复原 Nginx 运行状态"
        fi
        return 1
    fi
    # 生成账号
    checkGFWStatue 5 || return 1
    showAccounts 6
}

installXrayReality() {
    padmRunPortAllowTransaction installXrayRealityApply "$@"
}

# 安装 sing-box Reality
installSingBoxRealityApply() {

    selectCustomInstallType=",1,"
    readLastInstallationConfig || return 1
    totalProgress=6
    installTools 1

    installSingBox 2 || return 1
    initSingBoxConfig custom 3 || return 1
    cleanUp xrayDel || return 1
    installSingBoxService 4 || return 1
    serviceQueueRestart sing-box
    serviceQueueApply || return 1
    # 生成账号
    checkGFWStatue 5 || return 1
    showAccounts 6
}

installSingBoxReality() {
    padmRunPortAllowTransaction installSingBoxRealityApply "$@"
}

# Xray-core个性化安装
customXrayInstallApply() {
    local preselectedProtocols=${1:-}
    local preselectedMode=${2:-}
    local allowedIds
    allowedIds=$(protocolSelectionCurrentIdsForCore xray)
    realityOnlyWithDomain=
    echoContent title "\n┌─ Xray 个性化安装 ──────────────────────────────────"
    menuLine "可输入单个编号，也可用英文逗号多选，例如 1,2,21"
    menuLine "推荐新人：优先选 1；需要 XHTTP 时选 2；协议说明来自能力库"
    menuLine "WS/gRPC/HTTPUpgrade/传统 TLS 协议仅在明确客户端兼容或迁移需要时选择"
    menuLine "只安装 Reality 时不补传统 TLS 协议；域名 Reality 会额外申请入口域名的本机 TLS 证书"
    menuLine "推荐能力"
    protocolRegistryMenuByLifecycle "${allowedIds}" recommended
    menuLine "高级能力"
    protocolRegistryMenuByLifecycle "${allowedIds}" advanced
    menuClose
    if [[ -n "${preselectedProtocols}" ]]; then
        selectCustomInstallType=${preselectedProtocols}
        statusCard "推荐安装" "已选择协议编号: ${selectCustomInstallType}"
    else
        autoRead protocols "请选择[多选]，[例如:1,2,21]:" selectCustomInstallType
    fi
    if echo "${selectCustomInstallType}" | grep -q "，"; then
        errorCard "请使用英文逗号分隔"
        exit 0
    fi

    if protocolSelectionOnlyRealityNoDomain "${selectCustomInstallType}"; then
        if [[ "${selectCustomInstallType}" == "1" ]]; then
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
                    coreSelectionErrorCard "选择错误"
                    customXrayInstall
                    return
                fi
            fi
        fi
        selectCustomInstallType=",${selectCustomInstallType},"
    else
        selectCustomInstallType=",${selectCustomInstallType},"
    fi
    if [[ "${selectCustomInstallType:0:1}" != "," ]]; then
        selectCustomInstallType=",${selectCustomInstallType},"
    fi
    if [[ "${selectCustomInstallType//,/}" =~ ^[0-9]+$ ]] && protocolSelectionIdsValid "${selectCustomInstallType}" "${allowedIds}"; then
        protocolSelectionShowRiskNotes "${selectCustomInstallType}"
        readLastInstallationConfig || return 1
        # checkBTPanel
        # check1Panel
        totalProgress=12
        installTools 1
        if [[ -n "${btDomain}" ]]; then
            skipTlsCertificateStatusCard "检测到宝塔面板/1Panel"
            coreInstallServiceAction "Xray 服务停止失败，已取消端口配置" handleXray stop || return 1
            if [[ "${selectCustomInstallType}" != ",1," || -n "${realityOnlyWithDomain}" ]]; then
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
                skipTlsCertificateStatusCard "仅安装无域名 Reality"
                cleanAgentNginxConf || { errorCard "Nginx 配置清理失败，已取消 Xray 安装"; return 1; }
            fi
        fi

        if protocolSelectionNeedsPath "${selectCustomInstallType}"; then
            randomPathFunction 4 || return 1
        fi
        if [[ -n "${btDomain}" ]]; then
            statusCard "跳过伪装网站" "检测到宝塔面板/1Panel"
        else
            nginxBlog 6 || return 1
        fi
        if protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"; then
            updateRedirectNginxConf || return 1
            coreInstallServiceAction "Nginx 服务启动失败，已取消 Xray 安装" handleNginx start || return 1
        fi

        # 安装 Xray
        installXray 7 false || return 1
        initXrayConfig custom 8 || return 1
        cleanUp singBoxDel || return 1
        installXrayService 9 || return 1
        if protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"; then
            installCronTLS 10 || return 1
        fi

        serviceQueueRestart xray
        serviceQueueApply || return 1
        # 生成账号
        checkGFWStatue 11 || return 1
        showAccounts 12
    else
        local unsupportedReason=
        unsupportedReason=$(protocolCoreUnsupportedReason xray "${selectCustomInstallType}" 2>/dev/null || true)
        if [[ -n "${unsupportedReason}" ]]; then
            errorCard "${unsupportedReason}"
        else
            errorCard "输入不合法"
        fi
        if [[ -n "${preselectedProtocols}" || "${AUTO_INSTALL:-}" == "true" ]]; then
            return 1
        fi
        customXrayInstall
    fi
}

customXrayInstall() {
    padmRunPortAllowTransaction customXrayInstallApply "$@"
}


# sing-box 个性化安装
customSingBoxInstallApply() {
    local preselectedProtocols=${1:-}
    local allowedIds
    allowedIds=$(protocolSelectionCurrentIdsForCore sing-box)
    echoContent title "\n┌─ sing-box 个性化安装 ───────────────────────────────"
    menuLine "可输入单个编号，也可用英文逗号多选，例如 1,3,4"
    menuLine "推荐新人：优先选 1 或 3；XHTTP 为 Xray-only；协议说明来自能力库"
    menuLine "传统 TLS 类协议仅在明确需要兼容；Hysteria2/Tuic 用于 UDP/移动网络，Naive 用于 TLS 指纹抗性，AnyTLS 按需选择"
    menuLine "推荐能力"
    protocolRegistryMenuByLifecycle "${allowedIds}" recommended
    menuLine "高级能力"
    protocolRegistryMenuByLifecycle "${allowedIds}" advanced

    menuClose
    if [[ -n "${preselectedProtocols}" ]]; then
        selectCustomInstallType=${preselectedProtocols}
        statusCard "推荐安装" "已选择协议编号: ${selectCustomInstallType}"
    else
        autoRead protocols "请选择[多选]，[例如:1,3,4]:" selectCustomInstallType
    fi
    if echo "${selectCustomInstallType}" | grep -q "，"; then
        errorCard "请使用英文逗号分隔"
        exit 0
    fi

    if [[ "${selectCustomInstallType: -1}" != "," ]]; then
        selectCustomInstallType="${selectCustomInstallType},"
    fi
    if [[ "${selectCustomInstallType:0:1}" != "," ]]; then
        selectCustomInstallType=",${selectCustomInstallType},"
    fi

    if [[ "${selectCustomInstallType//,/}" =~ ^[0-9]+$ ]] && protocolSelectionIdsValid "${selectCustomInstallType}" "${allowedIds}"; then
        protocolSelectionShowRiskNotes "${selectCustomInstallType}"
        readLastInstallationConfig || return 1
        totalProgress=9
        installTools 1
        # 申请tls
        if protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"; then
            initTLSNginxConfig 2 || return 1
            installTLS 3 || return 1
            coreInstallServiceAction "Nginx 服务停止失败，已取消 sing-box 安装" handleNginx stop || return 1
        fi

        installSingBox 4 || return 1
        initSingBoxConfig custom 5 || return 1
        cleanUp xrayDel || return 1
        installSingBoxService 6 || return 1
        installCronTLS 7 || return 1
        serviceQueueRestart sing-box
        serviceQueueRestart nginx
        serviceQueueApply || return 1
        # 生成账号
        checkGFWStatue 8 || return 1
        showAccounts 9
    else
        local unsupportedReason=
        unsupportedReason=$(protocolCoreUnsupportedReason sing-box "${selectCustomInstallType}" 2>/dev/null || true)
        if [[ -n "${unsupportedReason}" ]]; then
            errorCard "${unsupportedReason}"
        else
            errorCard "输入不合法"
        fi
        if [[ -n "${preselectedProtocols}" || "${AUTO_INSTALL:-}" == "true" ]]; then
            return 1
        fi
        customSingBoxInstall
    fi
}

customSingBoxInstall() {
    padmRunPortAllowTransaction customSingBoxInstallApply "$@"
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
            customXrayInstall || return $?
        elif [[ "${selectInstallType}" == "3" ]]; then
            installXrayReality
        fi
        ;;
    2)
        if [[ "${selectInstallType}" == "1" ]]; then
            singBoxInstall
        elif [[ "${selectInstallType}" == "2" ]]; then
            customSingBoxInstall || return $?
        elif [[ "${selectInstallType}" == "3" ]]; then
            installSingBoxReality
        fi
        ;;
    *)
        coreSelectionRetryAction selectCoreInstall
        ;;
    esac
}


# Xray-core 个性化安装
xrayCoreInstallApply() {
    readLastInstallationConfig || return 1
    # checkBTPanel
    # check1Panel
    selectCustomInstallType=
    totalProgress=12
    installTools 2
    if [[ -n "${btDomain}" ]]; then
        skipTlsCertificateStatusCard "检测到宝塔面板/1Panel"
        coreInstallServiceAction "Xray 服务停止失败，已取消端口配置" handleXray stop || return 1
        customPortFunction || return 1
    else
        # 申请tls
        initTLSNginxConfig 3 || return 1
        installTLS 4 || return 1
    fi

    randomPathFunction 5 || return 1

    # 安装 Xray
    installXray 6 false || return 1
    initXrayConfig all 7 || return 1
    cleanUp singBoxDel || return 1
    installXrayService 8 || return 1
    installCronTLS 9 || return 1
    if [[ -n "${btDomain}" ]]; then
        statusCard "跳过伪装网站" "检测到宝塔面板/1Panel"
    else
        nginxBlog 10 || return 1
    fi
    updateRedirectNginxConf || return 1
    coreInstallServiceAction "Xray 服务停止失败，已取消安装收尾" handleXray stop || return 1
    sleep 2
    coreInstallServiceAction "Xray 服务启动失败，已取消安装收尾" handleXray start || return 1

    coreInstallServiceAction "Nginx 服务启动失败，已取消安装收尾" handleNginx start || return 1
    # 生成账号
    checkGFWStatue 11 || return 1
    showAccounts 12
}

xrayCoreInstall() {
    padmRunPortAllowTransaction xrayCoreInstallApply "$@"
}


# sing-box 全部安装
singBoxInstallApply() {
    readLastInstallationConfig || return 1
    # checkBTPanel
    # check1Panel
    selectCustomInstallType=
    totalProgress=8
    installTools 2

    if [[ -n "${btDomain}" ]]; then
        skipTlsCertificateStatusCard "检测到宝塔面板/1Panel"
        coreInstallServiceAction "Xray 服务停止失败，已取消端口配置" handleXray stop || return 1
        customPortFunction || return 1
    else
        # 申请tls
        initTLSNginxConfig 3 || return 1
        installTLS 4 || return 1
    fi

    coreInstallServiceAction "Nginx 服务停止失败，已取消 sing-box 安装" handleNginx stop || return 1

    installSingBox 5 || return 1
    initSingBoxConfig all 6 || return 1
    cleanUp xrayDel || return 1
    installSingBoxService 7 || return 1
    installCronTLS 8 || return 1

    serviceQueueRestart sing-box
    serviceQueueStart nginx
    serviceQueueApply || return 1
    # 生成账号
    showAccounts 9
}

singBoxInstall() {
    padmRunPortAllowTransaction singBoxInstallApply "$@"
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
    1) coreServiceControlAction "${serviceName}" start ;;
    2) coreServiceControlAction "${serviceName}" stop ;;
    3) coreServiceControlAction "${serviceName}" restart ;;
    4) coreVersionManageMenu ;;
    *) coreInvalidInputRetryMenu coreServiceControlMenu "${core}" ;;
    esac
}

coreServiceControlAction() {
    local serviceName=$1
    local action=$2
    local actionName=$action
    case "${action}" in
    start)
        actionName="启动"
        serviceQueueStart "${serviceName}"
        ;;
    stop)
        actionName="停止"
        serviceQueueStop "${serviceName}"
        ;;
    restart)
        actionName="重启"
        serviceQueueRestart "${serviceName}"
        ;;
    *)
        errorCard "服务操作不支持: ${action}"
        return 1
        ;;
    esac
    if ! serviceQueueApply; then
        errorCard "${serviceName} 服务${actionName}失败"
        return 1
    fi
}

coreConfigMaintenanceMenu() {
    echoContent title "\n┌─ 配置校验与数据维护 ───────────────────────────────"
    menuItem 1 "校验 Xray 配置" "执行 xray -test -confdir"
    menuItem 2 "严格模式校验 Xray" "执行 XRAY_JSON_STRICT=true xray -test"
    menuItem 3 "Xray 兼容体检" "扫描 users schema / ECH / legacy reverse 风险"
    menuItem 4 "检查 Xray 预发布兼容性" "只校验最新 prerelease，不替换本机二进制"
    menuItem 5 "校验 sing-box 配置" "执行 merge + check"
    menuItem 6 "sing-box 兼容体检" "扫描 1.13/1.14 迁移风险并输出提示"
    menuItem 7 "检查 sing-box 预发布兼容性" "只校验最新 prerelease，不替换本机二进制"
    menuItem 8 "更新 Xray Geo 数据" "更新 geosite.dat / geoip.dat"
    menuItem 9 "查看 Xray Geo 状态" "查看文件、版本和自动更新状态"
    menuItem 10 "设置 Xray Geo 自动更新" "每天凌晨更新规则数据"
    menuReturnItem 11 "返回核心与服务" "回到核心生命周期管理"
    menuClose
    autoRead core_config_maintenance "请选择:" selectMaintenance
    case "${selectMaintenance}" in
    1)
        local logFile
        logFile=$(coreTmpFilePath padm-core-xray-test.log)
        if validateXrayConfigWithBinary "$(coreXrayBinaryPath)" "${logFile}"; then
            xrayConfigValidationCard "通过"
        else
            xrayConfigValidationCard "失败" "排查日志: ${logFile}"
        fi
        ;;
    2) showXrayStrictValidation ;;
    3) showXrayCompatibilityAudit ;;
    4) checkXrayPrereleaseCompatibility ;;
    5)
        local logFile
        logFile=$(coreTmpFilePath padm-core-sing-box-test.log)
        if validateSingBoxConfigWithBinary /etc/padm/sing-box/sing-box "${logFile}"; then
            singBoxConfigValidationCard "通过"
        else
            singBoxConfigValidationCard "失败" "排查日志: ${logFile}" "如日志包含 legacy/deprecated/domain_resolver，查看日志底部的 padm 兼容性提示"
        fi
        ;;
    6) showSingBoxCompatibilityAudit ;;
    7) checkSingBoxPrereleaseCompatibility ;;
    8) updateGeoSite ;;
    9) showXrayGeoStatus ;;
    10) installCronUpdateGeo ;;
    11) coreVersionManageMenu ;;
    *) coreInvalidInputRetryMenu coreConfigMaintenanceMenu ;;
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
    *) coreInvalidInputRetryMenu coreLogsMenu ;;
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
    *) coreInvalidInputRetryMenu coreAllServicesMenu ;;
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
    *) coreInvalidInputRetryMenu coreVersionManageMenu ;;
    esac
}

singBoxVersionManageMenu() {
    echoContent title "\n┌─ sing-box 生命周期 ─────────────────────────────────"
    menuItem 1 "升级稳定版" "下载最新稳定版，校验后替换"
    menuItem 2 "检查预发布兼容性" "只校验最新 prerelease，不替换本机二进制"
    menuItem 3 "升级预发布版" "下载 prerelease，适合验证新能力"
    menuItem 4 "回退稳定版" "选择最近稳定版本回退"
    menuItem 5 "校验配置" "执行 sing-box merge + check"
    menuItem 6 "兼容体检" "扫描 1.13/1.14 已知迁移风险"
    local logStatus=
    if [[ -f "$(singBoxLogConfigFile)" && "$(jq -r .log.disabled "$(singBoxLogConfigFile)")" == "false" ]]; then
        menuItem 7 "关闭 debug 日志" "停止写入 sing-box debug 日志"
        logStatus=true
    else
        menuItem 7 "启用 debug 日志" "开启 sing-box debug 日志"
        logStatus=false
    fi
    menuItem 8 "查看日志" "tail -f 查看 sing-box 日志"
    menuReturnItem 9 "返回核心与服务" "回到核心生命周期管理"
    menuClose
    autoRead singbox_lifecycle_menu "请选择:" selectSingBoxType
    case "${selectSingBoxType}" in
    1) upgradeSingBoxCore false ;;
    2) checkSingBoxPrereleaseCompatibility ;;
    3) upgradeSingBoxCore true ;;
    4)
        version=$(selectRollbackVersion SagerNet/sing-box "sing-box") || { coreInvalidInputRetryMenu singBoxVersionManageMenu; return; }
        upgradeSingBoxCore false "${version}"
        ;;
    5)
        local logFile
        logFile=$(coreTmpFilePath padm-core-sing-box-test.log)
        if validateSingBoxConfigWithBinary /etc/padm/sing-box/sing-box "${logFile}"; then
            singBoxConfigValidationCard "通过"
        else
            singBoxConfigValidationCard "失败" "排查日志: ${logFile}" "如日志包含 legacy/deprecated/domain_resolver，查看日志底部的 padm 兼容性提示"
        fi
        ;;
    6) showSingBoxCompatibilityAudit ;;
    7)
        singBoxLog ${logStatus}
        [[ "${logStatus}" == "false" ]] && tail -f /etc/padm/sing-box/conf/box.log
        ;;
    8)
        mkdir -p /etc/padm/sing-box/conf
        touch /etc/padm/sing-box/conf/box.log >/dev/null 2>&1
        tail -f /etc/padm/sing-box/conf/box.log
        ;;
    9) coreVersionManageMenu ;;
    *) coreInvalidInputRetryMenu singBoxVersionManageMenu ;;
    esac
}


singBoxLogConfigFile() {
    printf '%s\n' "${PADM_SINGBOX_LOG_CONFIG_FILE:-/etc/padm/sing-box/conf/config/log.json}"
}

# sing-box 日志
singBoxLog() {
    local targetPath
    local tmpPath backupPath hadBackup=false
    local restoreMessage rollbackMessage
    targetPath=$(singBoxLogConfigFile)
    targetPath=$(padmResolveManagedAbsolutePath "${targetPath}") || { errorCard "sing-box 日志配置路径异常"; return 1; }
    padmEnsureSafeDirectory "$(dirname "${targetPath}")" || { errorCard "sing-box 日志目录创建失败"; return 1; }
    padmCreateTempFileForTarget tmpPath "${targetPath}" log || return 1
    if [[ -f "${targetPath}" ]]; then
        backupPath="${targetPath}.bak.$(date +%s)"
        backupManagedFileToPath "${targetPath}" "${backupPath}" 644 || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
        hadBackup=true
    fi
    cat <<EOF >"${tmpPath}"
{
  "log": {
    "disabled": $1,
    "level": "debug",
    "output": "/etc/padm/sing-box/conf/box.log",
    "timestamp": true
  }
}
EOF
    if ! commitGeneratedJsonFile "${tmpPath}" "${targetPath}"; then
        if [[ -n "${backupPath}" ]]; then
            removeManagedFilesIfPresentIgnoreFailure "${backupPath}"
        fi
        padmRemoveCleanupPath "${tmpPath}"
        errorCard "sing-box 日志配置写入失败"
        return 1
    fi

    serviceQueueRestart sing-box
    if serviceQueueApply; then
        if [[ -n "${backupPath}" ]]; then
            removeManagedFilesIfPresentIgnoreFailure "${backupPath}"
        fi
        return 0
    fi
    if [[ "${hadBackup}" == "true" ]]; then
        if ! restoreManagedFileFromBackup "${backupPath}" "${targetPath}" 644; then
            coreSetSingleRestoreResultMessage restoreMessage "sing-box 日志配置重载失败" false "已恢复旧配置" "旧配置" " ${targetPath}，备份文件：${backupPath}" || true
            errorCard "${restoreMessage}"
            backupPath=
            return 1
        fi
        removeManagedFilesIfPresentIgnoreFailure "${backupPath}"
        backupPath=
    else
        if ! removeManagedPathIfPresent "${targetPath}"; then
            coreSetNewConfigCleanupFailureMessage restoreMessage "sing-box 日志配置重载失败" "${targetPath}"
            errorCard "${restoreMessage}"
            return 1
        fi
    fi
    if [[ -n "${backupPath}" ]]; then
        removeManagedFilesIfPresentIgnoreFailure "${backupPath}"
    fi
    coreSetRollbackResultMessage rollbackMessage "sing-box 日志配置重载失败" "已回滚日志配置"
    errorCard "${rollbackMessage}"
    return 1
}
