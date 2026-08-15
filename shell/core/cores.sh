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
    padmCreateTempPath backupDir -d "$(padmTmpFilePath padm-xray-geo-backup.XXXXXX)" || {
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

        if [[ -z "${lastInstallationConfig:-}" ]]; then
            autoRead singbox_reinstall "是否更新、升级？[y/n]:" reInstallSingBoxStatus
            if [[ "${reInstallSingBoxStatus}" == "y" ]]; then
                version=$(coreLatestReleaseTag SagerNet/sing-box "${prereleaseStatus}") || exit 1
                checkVersionNotEmpty "${version}"
                successCard "最新版本:${version}"
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
    local metadata page=1 pageSize=5 pageCount tagCount=0 tag
    [[ "${repo}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
    [[ "${prerelease}" == "true" || "${prerelease}" == "false" ]] || return 1
    [[ "${limit}" =~ ^[0-9]+$ && "${limit}" -gt 0 && "${limit}" -le 100 ]] || return 1
    while ((tagCount < limit && page <= 20)); do
        metadata=$(fetchUrlToStdout "https://api.github.com/repos/${repo}/releases?per_page=${pageSize}&page=${page}" 3) || return 1
        pageCount=$(jq -er 'if type == "array" then length else error("release metadata is not an array") end' <<<"${metadata}") || return 1
        tag=$(jq -r --argjson prerelease "${prerelease}" '
          .[] | select(.prerelease == $prerelease) | .tag_name | select(type == "string" and length > 0)
        ' <<<"${metadata}") || return 1
        while IFS= read -r tag; do
            [[ -n "${tag}" ]] || continue
            printf '%s\n' "${tag}"
            tagCount=$((tagCount + 1))
            ((tagCount >= limit)) && break
        done <<<"${tag}"
        ((pageCount < pageSize)) && break
        page=$((page + 1))
    done
    ((tagCount > 0))
}

coreLatestReleaseTag() {
    local repo=$1
    local prerelease=${2:-false}
    local metadata
    if [[ "${prerelease}" == "false" ]]; then
        metadata=$(fetchUrlToStdout "https://api.github.com/repos/${repo}/releases/latest" 3) || metadata=
        if [[ -n "${metadata}" ]]; then
            jq -er '.tag_name | select(type == "string" and length > 0)' <<<"${metadata}" && return 0
        fi
    fi
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
        xrayBinaryVersion "$(coreXrayBinaryPath)"
    else
        echo "未安装"
    fi
}

xrayBinaryVersion() {
    "${1}" --version 2>/dev/null | awk 'NR == 1 && $1 == "Xray" { print "v"$2; exit }'
}

getSingBoxCurrentVersion() {
    if singBoxInstalled; then
        singBoxBinaryVersion "$(coreSingBoxBinaryPath)"
    else
        echo "未安装"
    fi
}

singBoxBinaryVersion() {
    "${1}" version 2>/dev/null | awk 'NR == 1 && $1 == "sing-box" && $2 == "version" { print "v"$3; exit }'
}

runXrayConfigValidation() {
    local binary=$1
    local mode=$2
    local logFile=$3
    local configDir
    configDir=$(coreXrayConfigDir)

    : >"${logFile}" || return 1
    printf '核心: Xray\n二进制: %s\n配置目录: %s\n阶段: %s\n' "${binary}" "${configDir}" "${mode}" >>"${logFile}" || return 1
    case "${mode}" in
    normal | strict) ;;
    *)
        printf '失败: 未知校验模式\n' >>"${logFile}"
        return 1
        ;;
    esac
    if [[ ! -x "${binary}" ]]; then
        printf '无法检查: 二进制不存在或不可执行\n' >>"${logFile}"
        return 2
    fi
    if [[ ! -d "${configDir}" ]]; then
        printf '无法检查: 配置目录不存在\n' >>"${logFile}"
        return 2
    fi
    if [[ "${mode}" == "strict" ]]; then
        XRAY_JSON_STRICT=true "${binary}" -test -confdir "${configDir}" >>"${logFile}" 2>&1
    else
        "${binary}" -test -confdir "${configDir}" >>"${logFile}" 2>&1
    fi
}

validateXrayConfigWithBinary() {
    runXrayConfigValidation "${1:-/etc/padm/xray/xray}" normal "${2:-$(coreTmpFilePath padm-core-xray-test.log)}"
}

validateXrayConfigStrictWithBinary() {
    runXrayConfigValidation "${1:-/etc/padm/xray/xray}" strict "${2:-$(coreTmpFilePath padm-core-xray-strict-test.log)}"
}

coreTmpFilePath() {
    local fileName=$1
    padmTmpFilePath "${fileName}"
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

    : >"${logFile}" || return 1
    printf '核心: sing-box\n二进制: %s\n配置目录: %s\n阶段: 当前配置检查\n' "${binary}" "$(singBoxConfigShardDir)" >>"${logFile}" || return 1
    if [[ ! -x "${binary}" ]]; then
        printf '无法检查: 二进制不存在或不可执行\n' >>"${logFile}"
        return 2
    fi
    if ! singBoxConfigInstalled; then
        printf '无法检查: 配置不存在\n' >>"${logFile}"
        return 2
    fi
    singBoxMergeConfigForValidation "${binary}" "${logFile}" check || { appendSingBoxCompatibilityHints "${logFile}"; return 1; }
}

singBoxCompatibilityAuditCard() {
    statusCard "sing-box 升级风险扫描" "$@"
}

singBoxPrereleaseCompatibilityCard() {
    statusCard "sing-box 预发布版试跑" "$@"
}

xrayCompatibilityAuditCard() {
    statusCard "Xray 升级风险扫描" "$@"
}

xrayStrictValidationCard() {
    statusCard "Xray 严格模式校验" "$@"
}

xrayPrereleaseCompatibilityCard() {
    statusCard "Xray 预发布版试跑" "$@"
}

xrayConfigValidationCard() {
    statusCard "Xray 当前配置检查" "$@"
}

singBoxConfigValidationCard() {
    statusCard "sing-box 当前配置检查" "$@"
}

skipTlsCertificateStatusCard() {
    statusCard "跳过 TLS 证书" "$@"
}

coreCompatibilityAuditReset() {
    : >"${1}"
}

coreCompatibilityAuditStatusAdd() {
    local file=$1
    local level=$2
    local message=$3
    printf '%s:%s\n' "${level}" "${message}" >>"${file}"
}

coreCompatibilityAuditWarn() {
    local warnFile=$1
    local logFile=$2
    local message=$3
    printf '%s\n' "${message}" >>"${warnFile}" &&
        printf '[WARN] %s\n' "${message}" >>"${logFile}"
}

coreCompatibilityAuditFail() {
    local statusFile=$1
    local logFile=$2
    local message=$3
    coreCompatibilityAuditStatusAdd "${statusFile}" fail "${message}" &&
        printf '[FAIL] %s\n' "${message}" >>"${logFile}"
}

coreCompatibilityAuditPass() {
    local statusFile=$1
    local logFile=$2
    local message=$3
    coreCompatibilityAuditStatusAdd "${statusFile}" pass "${message}" &&
        printf '[PASS] %s\n' "${message}" >>"${logFile}"
}

singBoxCompatibilityAuditScanJsonFile() {
    local file=$1
    local statusFile=$2
    local logFile=$3
    local finding findings=

    if ! findings=$(jq -r '
        [
            if any(.outbounds[]?; .type? == "wireguard") then "wireguard-outbound" else empty end,
            if any(.outbounds[]?; .type? == "block" or .type? == "dns") then "special-outbound" else empty end,
            if any(.. | objects; has("domain_strategy")) then "domain-strategy" else empty end,
            if any(.. | objects | select(.dns? and ((.dns.rules? // []) | type == "array")) | .dns.rules[]?; has("outbound")) then "dns-rule-outbound" else empty end,
            if any(
                .. | objects | select(.dns? and ((.dns.servers? // []) | type == "array")) | .dns.servers[]?;
                type == "string" or (type == "object" and (has("address") or has("detour") or has("strategy")) and (has("type") | not))
            ) then "dns-server-format" else empty end,
            if any(
                .. | objects | select(.dns? and ((.dns.rules? // []) | type == "array")) | .dns.rules[]?;
                ((has("ip_version") or has("query_type")) and (has("rule_set_ip_cidr_accept_empty") or has("ip_is_private"))) or
                ((has("ip_version") or has("query_type")) and ((.rule_set // []) | tostring | test("query_type")))
            ) then "dns-rule-mix" else empty end
        ] | unique[]
    ' "${file}" 2>>"${logFile}"); then
        coreCompatibilityAuditFail "${statusFile}" "${logFile}" "JSON 无法解析：${file}" || return 1
        return 0
    fi

    while IFS= read -r finding; do
        case "${finding}" in
        wireguard-outbound) coreCompatibilityAuditFail "${statusFile}" "${logFile}" "检测到旧 WireGuard outbound，请改用 endpoints[type=wireguard]：${file}" || return 1 ;;
        special-outbound) coreCompatibilityAuditFail "${statusFile}" "${logFile}" "检测到 legacy special outbound，请改用 route action：${file}" || return 1 ;;
        domain-strategy) coreCompatibilityAuditFail "${statusFile}" "${logFile}" "检测到旧 domain_strategy，请迁移到 domain_resolver/default_domain_resolver：${file}" || return 1 ;;
        dns-rule-outbound) coreCompatibilityAuditFail "${statusFile}" "${logFile}" "检测到旧 DNS rule outbound，请迁移到 domain_resolver 或 route resolve：${file}" || return 1 ;;
        dns-server-format) coreCompatibilityAuditFail "${statusFile}" "${logFile}" "检测到旧 DNS server 格式，请迁移到 typed DNS servers：${file}" || return 1 ;;
        dns-rule-mix) coreCompatibilityAuditFail "${statusFile}" "${logFile}" "检测到 1.14 不兼容的 DNS 规则混搭，请检查 ip_version/query_type 与 legacy address filter：${file}" || return 1 ;;
        esac
    done <<<"${findings}"
}

collectSingBoxCompatibilityFindings() {
    local statusFile=$1
    local logFile=$2
    local warnFile=$3
    local file foundJson=false mergedFile shardDir

    coreCompatibilityAuditReset "${statusFile}" || return 1
    coreCompatibilityAuditReset "${warnFile}" || return 1
    : >"${logFile}" || return 1
    printf '核心: sing-box\n配置目录: %s\n阶段: 升级风险扫描\n' "$(singBoxConfigShardDir)" >>"${logFile}" || return 1

    if ! singBoxConfigInstalled; then
        coreCompatibilityAuditWarn "${warnFile}" "${logFile}" "未检测到 sing-box 配置" || return 1
        return 2
    fi
    if ! command -v jq >/dev/null 2>&1; then
        coreCompatibilityAuditFail "${statusFile}" "${logFile}" "缺少 jq，无法扫描 sing-box 配置" || return 1
        return 1
    fi

    mergedFile=$(singBoxMergedConfigFile)
    shardDir=$(singBoxConfigShardDir)
    if [[ -f "${mergedFile}" ]]; then
        foundJson=true
        singBoxCompatibilityAuditScanJsonFile "${mergedFile}" "${statusFile}" "${logFile}" || return 1
    fi
    for file in "${shardDir}"*.json; do
        [[ -f "${file}" ]] || continue
        foundJson=true
        singBoxCompatibilityAuditScanJsonFile "${file}" "${statusFile}" "${logFile}" || return 1
    done

    if [[ "${foundJson}" != "true" ]]; then
        coreCompatibilityAuditWarn "${warnFile}" "${logFile}" "未找到 sing-box JSON 配置文件" || return 1
        return 2
    fi

    if [[ ! -s "${statusFile}" ]]; then
        coreCompatibilityAuditPass "${statusFile}" "${logFile}" "未检测到 1.13/1.14 已知兼容风险" || return 1
    fi
    coreCompatibilityAuditHasFailures "${statusFile}" && return 1
    return 0
}

coreCompatibilityAuditHasFailures() {
    local statusFile=$1
    grep -q '^fail:' "${statusFile}" 2>/dev/null
}

summarizeCoreCompatibilityAudit() {
    local statusFile=$1
    local warnFile=$2
    local failCount=0 passCount=0 warnCount=0

    [[ -f "${statusFile}" ]] && failCount=$(grep -c '^fail:' "${statusFile}" 2>/dev/null || true)
    [[ -f "${statusFile}" ]] && passCount=$(grep -c '^pass:' "${statusFile}" 2>/dev/null || true)
    [[ -f "${warnFile}" ]] && warnCount=$(grep -c '.' "${warnFile}" 2>/dev/null || true)
    printf 'FAIL=%s WARN=%s PASS=%s' "${failCount}" "${warnCount}" "${passCount}"
}

showCoreCompatibilityAudit() {
    local collectFn=$1 cardFn=$2 missingMessage=$3 failureHint=$4 successMessage=$5
    local logFile=$6 statusFile=$7 warnFile=$8 rc=0

    "${collectFn}" "${statusFile}" "${logFile}" "${warnFile}" || rc=$?
    if [[ "${rc}" -eq 2 ]]; then
        "${cardFn}" "无法检查" "${missingMessage}" "排查日志: ${logFile}"
    elif [[ "${rc}" -ne 0 ]]; then
        "${cardFn}" "失败" "排查日志: ${logFile}" "${failureHint}"
    elif [[ -s "${warnFile}" ]]; then
        "${cardFn}" "需关注" "提示: $(head -n 1 "${warnFile}")" "完整日志: ${logFile}"
    else
        "${cardFn}" "通过" "${successMessage}"
    fi
    return "${rc}"
}

showSingBoxCompatibilityAudit() {
    showCoreCompatibilityAudit collectSingBoxCompatibilityFindings singBoxCompatibilityAuditCard \
        "未检测到 sing-box 配置" "重点检查 JSON / legacy DNS / WireGuard / special outbounds / domain_strategy" "未发现 1.13/1.14 已知兼容风险" \
        "${1:-$(coreTmpFilePath padm-sing-box-compat-audit.log)}" "${2:-$(coreTmpFilePath padm-sing-box-compat-audit.status)}" "${3:-$(coreTmpFilePath padm-sing-box-compat-audit.warn)}"
}

showSingBoxConfigValidation() {
    local logFile=${1:-$(coreTmpFilePath padm-core-sing-box-test.log)}
    local rc=0

    validateSingBoxConfigWithBinary "$(coreSingBoxBinaryPath)" "${logFile}" || rc=$?
    case "${rc}" in
    0) singBoxConfigValidationCard "通过" ;;
    2) singBoxConfigValidationCard "无法检查" "缺少 sing-box 二进制或配置" "排查日志: ${logFile}" ;;
    *) singBoxConfigValidationCard "失败" "排查日志: ${logFile}" ;;
    esac
    return "${rc}"
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
    local retainedTmpDirVar=${3:-}
    local downloadedBinary= downloadTmpDir= resolvedVersion= actualVersion=
    local riskStatus="${logFile}.risk.status"
    local riskLog="${logFile}.risk.log"
    local riskWarn="${logFile}.risk.warn"
    local validateLog="${logFile}.validate"
    local scanRc=0 validateRc=0

    : >"${logFile}" || return 1
    collectSingBoxCompatibilityFindings "${riskStatus}" "${riskLog}" "${riskWarn}" || scanRc=$?
    {
        printf '核心: sing-box\n配置目录: %s\n阶段: 预发布版试跑\n' "$(singBoxConfigShardDir)"
        printf '\n[本地升级风险扫描]\n'
        cat "${riskLog}" 2>/dev/null || true
    } >"${logFile}" || { removeManagedFilesIfPresentIgnoreFailure "${riskStatus}" "${riskLog}" "${riskWarn}"; return 1; }
    removeManagedFilesIfPresentIgnoreFailure "${riskStatus}" "${riskLog}" "${riskWarn}"
    if [[ "${scanRc}" -eq 2 ]]; then
        singBoxPrereleaseCompatibilityCard "无法检查" "未检测到 sing-box 配置" "排查日志: ${logFile}"
        return 2
    fi
    if [[ "${scanRc}" -ne 0 ]]; then
        singBoxPrereleaseCompatibilityCard "失败" "本地升级风险扫描未通过" "排查日志: ${logFile}"
        return 1
    fi

    if [[ -n "${version}" ]]; then
        resolvedVersion=${version}
    else
        resolvedVersion=$(coreLatestReleaseTag SagerNet/sing-box true 2>/dev/null || true)
    fi
    if [[ -z "${resolvedVersion}" || "${resolvedVersion}" == "null" ]]; then
        printf '\n失败: 无法获取目标版本\n' >>"${logFile}"
        singBoxPrereleaseCompatibilityCard "失败" "无法获取预发布版本" "排查日志: ${logFile}"
        return 1
    fi
    printf '\n目标版本: %s\n' "${resolvedVersion}" >>"${logFile}" || return 1
    if ! downloadSingBoxReleaseBinaryToTemp "${resolvedVersion}" downloadedBinary downloadTmpDir; then
        printf '失败: 预发布二进制下载失败\n' >>"${logFile}"
        singBoxPrereleaseCompatibilityCard "失败" "预发布二进制下载失败" "排查日志: ${logFile}"
        return 1
    fi
    actualVersion=$(singBoxBinaryVersion "${downloadedBinary}" || true)
    printf '目标二进制: %s\n实际版本: %s\n' "${downloadedBinary}" "${actualVersion:-无法解析}" >>"${logFile}" || true
    if [[ -z "${actualVersion}" || "${actualVersion#v}" != "${resolvedVersion#v}" ]]; then
        [[ -n "${downloadTmpDir}" ]] && padmRemoveCleanupPath "${downloadTmpDir}"
        singBoxPrereleaseCompatibilityCard "失败" "下载二进制版本不匹配" "目标版本: ${resolvedVersion}" "实际版本: ${actualVersion:-无法解析}" "排查日志: ${logFile}"
        return 1
    fi
    validateSingBoxConfigWithBinary "${downloadedBinary}" "${validateLog}" || validateRc=$?
    {
        printf '\n[目标二进制配置校验]\n'
        cat "${validateLog}" 2>/dev/null || true
    } >>"${logFile}"
    removeManagedFilesIfPresentIgnoreFailure "${validateLog}"
    if [[ "${validateRc}" -ne 0 ]]; then
        [[ -n "${downloadTmpDir}" ]] && padmRemoveCleanupPath "${downloadTmpDir}"
        if [[ "${validateRc}" -eq 2 ]]; then
            singBoxPrereleaseCompatibilityCard "无法检查" "配置在试跑期间不可用" "排查日志: ${logFile}"
            return 2
        fi
        singBoxPrereleaseCompatibilityCard "失败" "目标二进制无法加载当前配置" "排查日志: ${logFile}"
        return 1
    fi
    if [[ -n "${retainedTmpDirVar}" ]]; then
        printf -v "${retainedTmpDirVar}" '%s' "${downloadTmpDir}"
        singBoxPrereleaseCompatibilityCard "通过" "目标版本: ${resolvedVersion}" "预检通过，确认后安装本次已校验文件"
    else
        [[ -n "${downloadTmpDir}" ]] && padmRemoveCleanupPath "${downloadTmpDir}"
        singBoxPrereleaseCompatibilityCard "通过" "目标版本: ${resolvedVersion}" "仅执行 dry-run，未替换本机二进制"
    fi
    return 0
}

appendXrayCompatibilityHints() {
    local logFile=$1
    [[ -f "${logFile}" ]] || return 0
    if grep -Eqi 'echForceQuery|trustedXForwardedFor|settings\.clients|settings\.accounts|legacy reverse|unknown field.*users|unknown field.*clients|unknown field.*accounts|reverse' "${logFile}"; then
        {
            printf '\n[padm 兼容性提示]\n'
            printf -- '- 当前预发布仍兼容 settings.clients/settings.accounts，users 是建议迁移方向。\n'
            printf -- '- XHTTP / WS / HTTPUpgrade 如前置 CDN 或反代，建议显式复核 sockopt.trustedXForwardedFor。\n'
            printf -- '- Xray 26.5.9 起 echForceQuery 不再控制 ECH 行为；legacy reverse 会被拒绝，请迁移到 VLESS Reverse Proxy。\n'
        } >>"${logFile}"
    fi
}

xrayCompatibilityAuditScanJsonFile() {
    local file=$1
    local statusFile=$2
    local logFile=$3
    local warnFile=$4
    local finding findings=

    if ! findings=$(jq -r '
        [
            if any(.. | objects; has("settings") and (.settings | type == "object") and ((.settings | has("clients")) or (.settings | has("accounts")))) then "settings-alias" else empty end,
            if any(.. | objects; has("echForceQuery")) then "ech-force-query" else empty end,
            if (type == "object" and has("reverse")) then "legacy-reverse" else empty end,
            if any(
                .inbounds[]?;
                ((.streamSettings.network? == "ws") or
                 (.streamSettings.network? == "httpupgrade") or
                 (.streamSettings.network? == "xhttp") or
                 (.streamSettings.wsSettings? != null) or
                 (.streamSettings.httpupgradeSettings? != null) or
                 (.streamSettings.xhttpSettings? != null)) and
                ((((.streamSettings.sockopt.trustedXForwardedFor? // .sockopt.trustedXForwardedFor?) // "") | tostring | length) == 0)
            ) then "trusted-xff" else empty end,
            if any(.inbounds[]?; .protocol? == "tunnel") then "tunnel-inbound" else empty end,
            if any(.outbounds[]?; .protocol? == "dns") then "dns-outbound" else empty end
        ] | unique[]
    ' "${file}" 2>>"${logFile}"); then
        coreCompatibilityAuditFail "${statusFile}" "${logFile}" "JSON 无法解析：${file}" || return 1
        return 0
    fi

    while IFS= read -r finding; do
        case "${finding}" in
        settings-alias) coreCompatibilityAuditWarn "${warnFile}" "${logFile}" "检测到兼容别名 settings.clients/accounts；当前预发布仍兼容，建议后续迁移到 users：${file}" || return 1 ;;
        ech-force-query) coreCompatibilityAuditWarn "${warnFile}" "${logFile}" "检测到 echForceQuery；Xray 26.5.9 起该字段不再控制 ECH，配置 ECH 时将强制查询：${file}" || return 1 ;;
        legacy-reverse) coreCompatibilityAuditFail "${statusFile}" "${logFile}" "检测到 legacy reverse；Xray 26.5.9 起会拒绝该配置，请迁移到 VLESS Reverse Proxy：${file}" || return 1 ;;
        trusted-xff) coreCompatibilityAuditWarn "${warnFile}" "${logFile}" "检测到 XHTTP/WS/HTTPUpgrade 入站未设置 trustedXForwardedFor；如前置 CDN/反代请专项复核：${file}" || return 1 ;;
        tunnel-inbound) coreCompatibilityAuditWarn "${warnFile}" "${logFile}" "检测到 tunnel inbound；Xray 26.5.9+ 已调整相关字段，请复核 network/address/port 新 schema：${file}" || return 1 ;;
        dns-outbound) coreCompatibilityAuditWarn "${warnFile}" "${logFile}" "检测到 DNS outbound；Xray 26.5.9+ 已调整相关字段，请复核 network/address/port 新 schema：${file}" || return 1 ;;
        esac
    done <<<"${findings}"
}

collectXrayCompatibilityFindings() {
    local statusFile=$1
    local logFile=$2
    local warnFile=$3
    local file foundJson=false configDir

    coreCompatibilityAuditReset "${statusFile}" || return 1
    coreCompatibilityAuditReset "${warnFile}" || return 1
    : >"${logFile}" || return 1
    printf '核心: Xray\n配置目录: %s\n阶段: 升级风险扫描\n' "$(coreXrayConfigDir)" >>"${logFile}" || return 1

    if ! xrayConfigInstalled; then
        coreCompatibilityAuditWarn "${warnFile}" "${logFile}" "未检测到 Xray 配置" || return 1
        return 2
    fi
    if ! command -v jq >/dev/null 2>&1; then
        coreCompatibilityAuditFail "${statusFile}" "${logFile}" "缺少 jq，无法扫描 Xray 配置" || return 1
        return 1
    fi

    configDir=$(coreXrayConfigDir)
    for file in "${configDir}"/*.json; do
        [[ -f "${file}" ]] || continue
        foundJson=true
        xrayCompatibilityAuditScanJsonFile "${file}" "${statusFile}" "${logFile}" "${warnFile}" || return 1
    done

    if [[ "${foundJson}" != "true" ]]; then
        coreCompatibilityAuditWarn "${warnFile}" "${logFile}" "未找到 Xray JSON 配置文件" || return 1
        return 2
    fi

    if [[ ! -s "${statusFile}" ]] && [[ ! -s "${warnFile}" ]]; then
        coreCompatibilityAuditPass "${statusFile}" "${logFile}" "未检测到当前预发布已知兼容风险" || return 1
    fi
    coreCompatibilityAuditHasFailures "${statusFile}" && return 1
    return 0
}

showXrayCompatibilityAudit() {
    showCoreCompatibilityAudit collectXrayCompatibilityFindings xrayCompatibilityAuditCard \
        "未检测到 Xray 配置" "重点检查 JSON 解析 / legacy reverse" "未检测到当前预发布已知兼容风险" \
        "${1:-$(coreTmpFilePath padm-xray-compat-audit.log)}" "${2:-$(coreTmpFilePath padm-xray-compat-audit.status)}" "${3:-$(coreTmpFilePath padm-xray-compat-audit.warn)}"
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
        : >"${logFile}"
        printf '无法检查: 未检测到 Xray 二进制\n' >>"${logFile}"
        xrayStrictValidationCard "无法检查" "未检测到 Xray 二进制"
        return 2
    fi
    if ! xrayConfigInstalled; then
        : >"${logFile}"
        printf '无法检查: 未检测到 Xray 配置\n' >>"${logFile}"
        xrayStrictValidationCard "无法检查" "未检测到 Xray 配置"
        return 2
    fi
    if validateXrayConfigStrictWithBinary "$(coreXrayBinaryPath)" "${logFile}"; then
        xrayStrictValidationCard "通过"
        return 0
    fi
    appendXrayCompatibilityHints "${logFile}"
    xrayStrictValidationCard "失败" "排查日志: ${logFile}"
    return 1
}

showXrayConfigHealthCheck() {
    local binary validateLog strictLog
    local validateRc=0 strictRc=0

    if ! xrayInstalled; then
        xrayConfigValidationCard "无法检查" "未检测到 Xray 二进制"
        return 2
    fi
    if ! xrayConfigInstalled; then
        xrayConfigValidationCard "无法检查" "未检测到 Xray 配置"
        return 2
    fi

    binary=$(coreXrayBinaryPath)
    validateLog=$(coreTmpFilePath padm-core-xray-test.log)
    strictLog=$(coreTmpFilePath padm-core-xray-strict-test.log)

    validateXrayConfigWithBinary "${binary}" "${validateLog}" || validateRc=$?
    if [[ "${validateRc}" -ne 0 ]]; then
        if [[ "${validateRc}" -eq 2 ]]; then
            xrayConfigValidationCard "无法检查" "运行检查缺少前提" "排查日志: ${validateLog}"
        else
            xrayConfigValidationCard "失败" "运行检查未通过" "排查日志: ${validateLog}"
        fi
        return "${validateRc}"
    fi

    validateXrayConfigStrictWithBinary "${binary}" "${strictLog}" || strictRc=$?
    if [[ "${strictRc}" -eq 1 ]]; then
        appendXrayCompatibilityHints "${strictLog}"
        xrayConfigValidationCard "需关注" "运行检查: 通过" "严格检查未通过，日志: ${strictLog}"
        return 0
    fi
    if [[ "${strictRc}" -eq 2 ]]; then
        xrayConfigValidationCard "无法检查" "严格检查缺少前提" "排查日志: ${strictLog}"
        return 2
    fi
    xrayConfigValidationCard "通过" "运行检查: 通过" "严格检查: 通过"
}

checkXrayPrereleaseCompatibility() {
    local version=${1:-}
    local logFile=${2:-$(coreTmpFilePath padm-core-xray-prerelease-audit.log)}
    local retainedTmpDirVar=${3:-}
    local downloadedBinary= downloadTmpDir= resolvedVersion= actualVersion=
    local riskStatus="${logFile}.risk.status"
    local riskLog="${logFile}.risk.log"
    local riskWarn="${logFile}.risk.warn"
    local validateLog="${logFile}.validate"
    local strictLog="${logFile}.strict"
    local scanRc=0 validateRc=0 strictRc=0
    local completionMessage="仅执行 dry-run，未替换本机二进制"

    : >"${logFile}" || return 1
    collectXrayCompatibilityFindings "${riskStatus}" "${riskLog}" "${riskWarn}" || scanRc=$?
    {
        printf '核心: Xray\n配置目录: %s\n阶段: 预发布版试跑\n' "$(coreXrayConfigDir)"
        printf '\n[本地升级风险扫描]\n'
        cat "${riskLog}" 2>/dev/null || true
    } >"${logFile}" || { removeManagedFilesIfPresentIgnoreFailure "${riskStatus}" "${riskLog}" "${riskWarn}"; return 1; }
    removeManagedFilesIfPresentIgnoreFailure "${riskStatus}" "${riskLog}" "${riskWarn}"
    if [[ "${scanRc}" -eq 2 ]]; then
        xrayPrereleaseCompatibilityCard "无法检查" "未检测到 Xray 配置" "排查日志: ${logFile}"
        return 2
    fi
    if [[ "${scanRc}" -ne 0 ]]; then
        xrayPrereleaseCompatibilityCard "失败" "本地升级风险扫描未通过" "排查日志: ${logFile}"
        return 1
    fi

    if [[ -n "${version}" ]]; then
        resolvedVersion=${version}
    else
        resolvedVersion=$(coreLatestReleaseTag XTLS/Xray-core true 2>/dev/null || true)
    fi
    if [[ -z "${resolvedVersion}" || "${resolvedVersion}" == "null" ]]; then
        printf '\n失败: 无法获取目标版本\n' >>"${logFile}"
        xrayPrereleaseCompatibilityCard "失败" "无法获取预发布版本" "排查日志: ${logFile}"
        return 1
    fi
    printf '\n目标版本: %s\n' "${resolvedVersion}" >>"${logFile}" || return 1
    if ! downloadXrayReleaseBinaryToTemp "${resolvedVersion}" downloadedBinary downloadTmpDir; then
        printf '失败: 预发布二进制下载失败\n' >>"${logFile}"
        xrayPrereleaseCompatibilityCard "失败" "预发布二进制下载失败" "排查日志: ${logFile}"
        return 1
    fi
    actualVersion=$(xrayBinaryVersion "${downloadedBinary}" || true)
    printf '目标二进制: %s\n实际版本: %s\n' "${downloadedBinary}" "${actualVersion:-无法解析}" >>"${logFile}" || true
    if [[ -z "${actualVersion}" || "${actualVersion#v}" != "${resolvedVersion#v}" ]]; then
        [[ -n "${downloadTmpDir}" ]] && padmRemoveCleanupPath "${downloadTmpDir}"
        xrayPrereleaseCompatibilityCard "失败" "下载二进制版本不匹配" "目标版本: ${resolvedVersion}" "实际版本: ${actualVersion:-无法解析}" "排查日志: ${logFile}"
        return 1
    fi

    validateXrayConfigWithBinary "${downloadedBinary}" "${validateLog}" || validateRc=$?
    {
        printf '\n[运行校验]\n'
        cat "${validateLog}" 2>/dev/null || true
    } >>"${logFile}"
    if [[ "${validateRc}" -ne 0 ]]; then
        removeManagedFilesIfPresentIgnoreFailure "${validateLog}" "${strictLog}"
        appendXrayCompatibilityHints "${logFile}"
        [[ -n "${downloadTmpDir}" ]] && padmRemoveCleanupPath "${downloadTmpDir}"
        if [[ "${validateRc}" -eq 2 ]]; then
            xrayPrereleaseCompatibilityCard "无法检查" "配置在试跑期间不可用" "排查日志: ${logFile}"
            return 2
        fi
        xrayPrereleaseCompatibilityCard "失败" "运行校验失败" "目标版本: ${resolvedVersion}" "排查日志: ${logFile}"
        return 1
    fi
    validateXrayConfigStrictWithBinary "${downloadedBinary}" "${strictLog}" || strictRc=$?
    {
        printf '\n[严格校验]\n'
        cat "${strictLog}" 2>/dev/null || true
    } >>"${logFile}"
    removeManagedFilesIfPresentIgnoreFailure "${validateLog}" "${strictLog}"
    if [[ "${strictRc}" -ne 0 ]]; then
        appendXrayCompatibilityHints "${logFile}"
        [[ -n "${downloadTmpDir}" ]] && padmRemoveCleanupPath "${downloadTmpDir}"
        if [[ "${strictRc}" -eq 2 ]]; then
            xrayPrereleaseCompatibilityCard "无法检查" "配置在试跑期间不可用" "排查日志: ${logFile}"
            return 2
        fi
        xrayPrereleaseCompatibilityCard "失败" "严格校验失败" "目标版本: ${resolvedVersion}" "排查日志: ${logFile}"
        return 1
    fi
    if [[ -n "${retainedTmpDirVar}" ]]; then
        printf -v "${retainedTmpDirVar}" '%s' "${downloadTmpDir}"
        completionMessage="预检通过，确认后安装本次已校验文件"
    else
        [[ -n "${downloadTmpDir}" ]] && padmRemoveCleanupPath "${downloadTmpDir}"
    fi
    xrayPrereleaseCompatibilityCard "通过" "目标版本: ${resolvedVersion}" "已通过运行校验和严格校验" "${completionMessage}"
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

runCoreServiceActionAllowFailure() {
    local previousAllowFailure="${SERVICE_QUEUE_ALLOW_FAILURE:-}"
    SERVICE_QUEUE_ALLOW_FAILURE=true
    "$@"
    local rc=$?
    SERVICE_QUEUE_ALLOW_FAILURE="${previousAllowFailure}"
    return "${rc}"
}

runCoreInstallRestoringNginxOnFailure() {
    local operation=$1
    shift
    local nginxWasRunning=false
    local installStatus=0
    nginxRunning && nginxWasRunning=true
    "${operation}" "$@" || installStatus=$?
    if [[ "${installStatus}" != "0" && "${nginxWasRunning}" == "true" ]] && ! nginxRunning; then
        if ! runCoreServiceActionAllowFailure handleNginx start restore; then
            errorCard "核心安装失败，且 Nginx 原运行状态恢复失败，请手动检查 Nginx 服务"
            return 1
        fi
    fi
    return "${installStatus}"
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
    local tmpDir=${2:-}
    local oldBinary backupBinary newBinary logFile installedVersion actualVersion
    local newServiceRunning=false
    local reusedPreparedDir=false
    local rc
    logFile=$(coreTmpFilePath padm-core-xray-upgrade-test.log)
    [[ -n "${tmpDir}" ]] && reusedPreparedDir=true
    if [[ -z "${tmpDir}" ]]; then
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
    fi
    newBinary="${tmpDir}/xray"
    if ! coreExtractedFileIsRegular "${newBinary}" || [[ ! -x "${newBinary}" ]]; then
        padmRemoveCleanupPath "${tmpDir}"
        errorCard "Xray-core 已校验临时文件不可用"
        return 1
    fi
    if [[ "${reusedPreparedDir}" == "true" ]]; then
        actualVersion=$(xrayBinaryVersion "${newBinary}" || true)
        if [[ -z "${actualVersion}" || "${actualVersion#v}" != "${version#v}" ]]; then
            padmRemoveCleanupPath "${tmpDir}"
            statusCard "Xray-core 更新失败" "已校验二进制版本发生变化" "目标版本: ${version}" "实际版本: ${actualVersion:-无法解析}"
            return 1
        fi
    fi
    if xrayConfigInstalled && ! validateXrayConfigWithBinary "${newBinary}" "${logFile}"; then
        padmRemoveCleanupPath "${tmpDir}"
        xrayConfigValidationFailureCard "已取消升级" "排查日志: ${logFile}"
        return 1
    fi
    if [[ "${reusedPreparedDir}" == "true" ]] && xrayConfigInstalled && ! validateXrayConfigStrictWithBinary "${newBinary}" "${logFile}"; then
        padmRemoveCleanupPath "${tmpDir}"
        appendXrayCompatibilityHints "${logFile}"
        xrayConfigValidationFailureCard "已取消升级" "严格校验失败，排查日志: ${logFile}"
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
    installedVersion=$(coreXrayCurrentVersion)
    if xrayRunning; then
        newServiceRunning=true
    fi
    if xrayInstalled && [[ "${newServiceRunning}" == "true" && "${installedVersion}" == "${version}" ]]; then
        successCard "Xray-core更新成功" "当前版本: ${installedVersion}"
        padmRemoveCleanupPath "${tmpDir}"
        [[ -f "${backupBinary}" ]] && removeManagedFilesIfPresentIgnoreFailure "${backupBinary}"
        return 0
    fi
    if [[ "${installedVersion}" != "${version}" ]]; then
        printf '目标版本: %s\n实际版本: %s\n' "${version}" "${installedVersion}" >>"${logFile}"
        if [[ "${newServiceRunning}" == "true" ]] && ! runCoreServiceActionAllowFailure handleXray stop; then
            padmRemoveCleanupPath "${tmpDir}"
            statusCard "Xray-core 更新失败" "版本核验失败，且 Xray 服务停止失败" "目标版本: ${version}" "实际版本: ${installedVersion}" "请手动检查服务与备份: ${backupBinary}"
            return 1
        fi
    fi
    padmRemoveCleanupPath "${tmpDir}"
    finalizeFailedCoreBinaryInstall "Xray-core" "${backupBinary}" "${oldBinary}" handleXray "${logFile}"
}

installDownloadedSingBoxBinary() {
    local version=$1
    local tmpDir=${2:-}
    local oldBinary backupBinary extractedDir newBinary logFile cronetPath cronetBackup actualVersion
    local reusedPreparedDir=false
    local rc
    logFile=$(coreTmpFilePath padm-core-sing-box-upgrade-test.log)
    if [[ -n "${tmpDir}" ]]; then
        reusedPreparedDir=true
    else
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
    fi
    extractedDir="${tmpDir}/sing-box-${version/v/}${singBoxCoreCPUVendor}"
    newBinary="${extractedDir}/sing-box"
    if ! coreExtractedFileIsRegular "${newBinary}" || [[ ! -x "${newBinary}" ]] || ! coreExtractedFileIsRegular "${extractedDir}/libcronet.so"; then
        padmRemoveCleanupPath "${tmpDir}"
        errorCard "sing-box 已校验临时文件不可用"
        return 1
    fi
    if [[ "${reusedPreparedDir}" == "true" ]]; then
        actualVersion=$(singBoxBinaryVersion "${newBinary}" || true)
        if [[ -z "${actualVersion}" || "${actualVersion#v}" != "${version#v}" ]]; then
            padmRemoveCleanupPath "${tmpDir}"
            statusCard "sing-box 更新失败" "已校验二进制版本发生变化" "目标版本: ${version}" "实际版本: ${actualVersion:-无法解析}"
            return 1
        fi
    fi
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

upgradeCore() {
    local core=$1
    local repo=$2
    local auditName=$3
    local compatibilityFn=$4
    local installFn=$5
    shift 5
    local prerelease=${1:-false}
    local version=${2:-}
    local channel="稳定版"
    local preparedDir=
    [[ "${prerelease}" == "true" ]] && channel="预发布版"
    [[ -n "${version}" ]] || version=$(coreLatestReleaseTag "${repo}" "${prerelease}" || true)
    if [[ -z "${version}" || "${version}" == "null" ]]; then
        errorCard "无法获取 ${core} 目标版本"
        return 1
    fi
    if [[ "${prerelease}" == "true" ]]; then
        if ! "${compatibilityFn}" "${version}" "$(coreTmpFilePath "padm-core-${auditName}-prerelease-audit.log")" preparedDir; then
            return 1
        fi
    fi
    if ! confirmCoreUpgrade "${core}" "${version}" "${channel}"; then
        [[ -n "${preparedDir}" ]] && padmRemoveCleanupPath "${preparedDir}"
        coreCancelledStatusCard "未更新 ${core}"
        return 0
    fi
    "${installFn}" "${version}" "${preparedDir}"
}

upgradeXrayCore() {
    upgradeCore "Xray-core" XTLS/Xray-core xray checkXrayPrereleaseCompatibility installDownloadedXrayBinary "$@"
}

upgradeSingBoxCore() {
    upgradeCore "sing-box" SagerNet/sing-box sing-box checkSingBoxPrereleaseCompatibility installDownloadedSingBoxBinary "$@"
}

selectRollbackVersion() {
    local repo=$1
    local title=$2
    local resultVar=${3:-}
    local selection version versions
    versions=$(coreReleaseTags "${repo}" false 20) || {
        errorCard "获取稳定版本列表失败，请稍后重试"
        return 2
    }
    echoContent title "\n┌─ ${title} 版本回退 ─────────────────────────────────"
    menuLine "只列出最近稳定版本；回退前会使用目标二进制校验当前配置"
    awk '{print "│ "NR". "$0}' <<<"${versions}"
    menuClose
    autoRead core_rollback_version "请输入要回退的版本序号:" selection
    version=$(awk -v selected="${selection}" 'NR==selected {print $0}' <<<"${versions}")
    [[ -n "${version}" ]] || return 1
    if [[ -n "${resultVar}" ]]; then
        printf -v "${resultVar}" '%s' "${version}"
    else
        printf '%s\n' "${version}"
    fi
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

coreInstallServiceBackupFinalize() {
    local backupDir=$1
    local serviceName=$2
    local serviceWasEnabled=$3
    [[ -n "${backupDir}" ]] || return 0
    if [[ "${PADM_CORE_INSTALL_TRANSACTION_ACTIVE:-}" == "true" ]]; then
        PADM_CORE_INSTALL_SERVICE_BACKUP_DIR=${backupDir}
        PADM_CORE_INSTALL_SERVICE_NAME=${serviceName}
        PADM_CORE_INSTALL_SERVICE_WAS_ENABLED=${serviceWasEnabled}
    else
        padmRemoveCleanupPath "${backupDir}"
    fi
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
        coreInstallServiceBackupFinalize "${serviceBackupDir}" sing-box "${serviceWasEnabled}"
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
        coreInstallServiceBackupFinalize "${serviceBackupDir}" sing-box "${serviceWasEnabled}"
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

appendSelectedCoreClient() {
    local -n usersRef=$1
    local selection=$2 protocol=$3 objectFilter=$4
    shift 4
    protocolSelectionIncludes "${selection}" "${protocol}" || return 0
    usersRef=$(appendJsonObject "${usersRef}" "${objectFilter}" "$@")
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
        uuid=$(jq -r '.id // .uuid // .password // empty' <<<"${user}") || return 1
        email=$(jq -r '.email // .name // .username // empty' <<<"${user}") || return 1
        [[ -n "${uuid}" && -n "${email}" ]] || return 1
        email=$(stripClientNameSuffix "${email}") || return 1
        appendSelectedCoreClient users "${type}" 27 '{id:$uuid,flow:"xtls-rprx-vision",email:$email}' --arg uuid "${uuid}" --arg email "${email}-VLESS_TCP/TLS_Vision" || return 1

        # VLESS WS
        appendSelectedCoreClient users "${type}" 21 '{id:$uuid,email:$email}' --arg uuid "${uuid}" --arg email "${email}-VLESS_WS" || return 1
        # VLESS XHTTP
        appendSelectedCoreClient users "${type}" 2 '{id:$uuid,email:$email}' --arg uuid "${uuid}" --arg email "${email}-VLESS_Reality_XHTTP" || return 1
        # Trojan gRPC
        appendSelectedCoreClient users "${type}" 25 '{password:$password,email:$email}' --arg password "${uuid}" --arg email "${email}-Trojan_gRPC" || return 1
        # VMess WS
        appendSelectedCoreClient users "${type}" 22 '{id:$uuid,email:$email,alterId:0}' --arg uuid "${uuid}" --arg email "${email}-VMess_WS" || return 1
        # VMess HTTPUpgrade
        appendSelectedCoreClient users "${type}" 23 '{id:$uuid,email:$email,alterId:0}' --arg uuid "${uuid}" --arg email "${email}-VMess_HTTPUpgrade" || return 1

        # Trojan TCP
        appendSelectedCoreClient users "${type}" 28 '{password:$password,email:$email}' --arg password "${uuid}" --arg email "${email}-Trojan_TCP_direct" || return 1

        appendSelectedCoreClient users "${type}" 29 '{password:$password,email:$email}' --arg password "${uuid}" --arg email "${email}-trojan_tcp" || return 1

        # VLESS gRPC
        appendSelectedCoreClient users "${type}" 24 '{id:$uuid,email:$email}' --arg uuid "${uuid}" --arg email "${email}-vless_grpc" || return 1

        # VLESS Reality Vision
        appendSelectedCoreClient users "${type}" 1 '{id:$uuid,email:$email,flow:"xtls-rprx-vision"}' --arg uuid "${uuid}" --arg email "${email}-vless_reality_vision" || return 1

        # VLESS Reality gRPC
        appendSelectedCoreClient users "${type}" 26 '{id:$uuid,email:$email}' --arg uuid "${uuid}" --arg email "${email}-vless_reality_grpc" || return 1
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
        appendSelectedCoreClient users "${type}" 27 '{uuid:$uuid,flow:"xtls-rprx-vision",name:$name}' --arg uuid "${uuid}" --arg name "${name}-VLESS_TCP/TLS_Vision" || return 1
        # VLESS WS
        appendSelectedCoreClient users "${type}" 21 '{uuid:$uuid,name:$name}' --arg uuid "${uuid}" --arg name "${name}-VLESS_WS" || return 1
        # VMess WS
        appendSelectedCoreClient users "${type}" 22 '{uuid:$uuid,name:$name,alterId:0}' --arg uuid "${uuid}" --arg name "${name}-VMess_WS" || return 1

        # Trojan TCP
        appendSelectedCoreClient users "${type}" 28 '{password:$password,name:$name}' --arg password "${uuid}" --arg name "${name}-Trojan_TCP" || return 1

        # Shadowsocks
        if protocolSelectionIncludes "${type}" 30; then
            local ssPassword
            ssPassword=$(shadowsocks2022KeyFromSeed "user:${uuid}") || return 1
            users=$(appendJsonObject "${users}" '{password:$password,name:$name}' --arg password "${ssPassword}" --arg name "${name}-shadowsocks") || return 1
        fi

        # VLESS Reality Vision
        appendSelectedCoreClient users "${type}" 1 '{uuid:$uuid,flow:"xtls-rprx-vision",name:$name}' --arg uuid "${uuid}" --arg name "${name}-VLESS_Reality_Vision" || return 1
        # VLESS Reality gRPC
        appendSelectedCoreClient users "${type}" 26 '{uuid:$uuid,name:$name}' --arg uuid "${uuid}" --arg name "${name}-VLESS_Reality_gPRC" || return 1

        # Hysteria2
        appendSelectedCoreClient users "${type}" 3 '{password:$password,name:$name}' --arg password "${uuid}" --arg name "${name}-singbox_hysteria2" || return 1

        # TUIC
        appendSelectedCoreClient users "${type}" 31 '{uuid:$uuid,password:$password,name:$name}' --arg uuid "${uuid}" --arg password "${uuid}" --arg name "${name}-singbox_tuic" || return 1

        # Naive
        appendSelectedCoreClient users "${type}" 5 '{password:$password,username:$username}' --arg password "${uuid}" --arg username "${name}-singbox_naive" || return 1
        # VMess HTTPUpgrade
        appendSelectedCoreClient users "${type}" 23 '{uuid:$uuid,name:$name,alterId:0}' --arg uuid "${uuid}" --arg name "${name}-VMess_HTTPUpgrade" || return 1
        # AnyTLS
        appendSelectedCoreClient users "${type}" 4 '{password:$password,name:$name}' --arg password "${uuid}" --arg name "${name}-anytls" || return 1

        appendSelectedCoreClient users "${type}" 201 '{username:$username,password:$password}' --arg username "${uuid}" --arg password "${uuid}" || return 1

    done <<<"${clientRows}"
    printf '%s\n' "${users}"
}


# Reality 严格域名模式仅支持单选 Vision。
configureRealityDomainMode() {
    local selection=$1
    local preselectedMode=${2:-}
    local strictRequested=false
    local realityOnlyInstallType=
    realityOnlyWithDomain=

    if [[ "${preselectedMode}" == "domain" || "$(normalizeYesNo "${AUTO_REALITY_DOMAIN:-}")" == "y" ]]; then
        strictRequested=true
    fi
    if [[ "${strictRequested}" == "true" ]] && ! protocolSelectionSupportsStrictRealityDomain "${selection}"; then
        errorCard "严格域名 Reality 仅支持单选 Reality Vision 协议 1"
        return 1
    fi
    protocolSelectionSupportsStrictRealityDomain "${selection}" || return 0

    if [[ "${strictRequested}" != "true" ]]; then
        echoContent title "\n┌─ Reality 安装方式 ─────────────────────────────────"
        menuItem 1 "普通 Reality" "客户端入口使用服务器 IP、历史入口或 --entry-host"
        menuItem 2 "严格域名 Reality" "客户端入口必须是解析到本机的自有域名"
        menuLine "entry 是客户端连接地址；target/SNI 是 REALITY 伪装目标"
        menuClose
        autoRead reality_domain "请选择[默认1]:" realityOnlyInstallType
        if [[ "${realityOnlyInstallType:-1}" == "2" ]]; then
            strictRequested=true
        elif [[ -n "${realityOnlyInstallType:-}" && "${realityOnlyInstallType}" != "1" ]]; then
            coreSelectionErrorCard "选择错误"
            return 1
        fi
    fi
    if [[ "${strictRequested}" == "true" ]]; then
        realityOnlyWithDomain=true
        statusCard "Reality 安装方式" "严格域名模式：entry 使用自有域名，target/SNI 仍是外部伪装目标"
    fi
}

# 安装 Xray-core
installXrayRealityApply() {
    selectCustomInstallType=",1,"
    realityOnlyWithDomain=
    [[ "$(normalizeYesNo "${AUTO_REALITY_DOMAIN:-}")" == "y" ]] && realityOnlyWithDomain=true
    collectEntryProfile || return 1
    readLastInstallationConfig || return 1
    totalProgress=6
    installTools 1

    (installXray 2 false) || return 1
    initXrayConfig custom 3 || return 1
    installXrayService 4 || return 1
    serviceQueueRestart xray
    serviceQueueApply || return 1
    persistRealityEntryProfile || return 1
    checkGFWStatue 5 || return 1
    cleanUp singBoxDel || return 1
    showAccounts 6
}

installXrayReality() {
    runCoreInstallRestoringNginxOnFailure coreSwitchConfigTransaction xray padmRunPortAllowTransaction installXrayRealityApply "$@"
}

# 安装 sing-box Reality
installSingBoxRealityApply() {

    selectCustomInstallType=",1,"
    realityOnlyWithDomain=
    [[ "$(normalizeYesNo "${AUTO_REALITY_DOMAIN:-}")" == "y" ]] && realityOnlyWithDomain=true
    collectEntryProfile || return 1
    readLastInstallationConfig || return 1
    totalProgress=6
    installTools 1

    installSingBox 2 || return 1
    initSingBoxConfig custom 3 || return 1
    installSingBoxService 4 || return 1
    serviceQueueRestart sing-box
    serviceQueueApply || return 1
    persistRealityEntryProfile || return 1
    checkGFWStatue 5 || return 1
    cleanUp xrayDel || return 1
    showAccounts 6
}

installSingBoxReality() {
    runCoreInstallRestoringNginxOnFailure coreSwitchConfigTransaction sing-box padmRunPortAllowTransaction installSingBoxRealityApply "$@"
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
    menuLine "Reality 不申请本机证书；严格域名模式仅支持单选 Reality Vision"
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

    selectCustomInstallType=$(protocolSelectionNormalizeCsv "${selectCustomInstallType}")
    if [[ "${selectCustomInstallType//,/}" =~ ^[0-9]+$ ]] && protocolSelectionIdsValid "${selectCustomInstallType}" "${allowedIds}"; then
        configureRealityDomainMode "${selectCustomInstallType}" "${preselectedMode}" || return 1
        if protocolSelectionHasAny "${selectCustomInstallType}" 1 2 26; then
            collectEntryProfile || return 1
        fi
        protocolSelectionShowRiskNotes "${selectCustomInstallType}"
        readLastInstallationConfig || return 1
        # checkBTPanel
        # check1Panel
        totalProgress=12
        installTools 1
        if [[ -n "${btDomain}" ]]; then
            if protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"; then
                skipTlsCertificateStatusCard "检测到宝塔面板/1Panel"
                coreInstallServiceAction "Xray 服务停止失败，已取消端口配置" handleXray stop || return 1
                customPortFunction || return 1
            else
                skipTlsCertificateStatusCard "Reality 不需要本机 TLS 证书"
            fi
        else
            # 申请tls
            if protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"; then
                initTLSNginxConfig 2 || return 1
                installTLS 3 || return 1
            else
                skipTlsCertificateStatusCard "Reality 不需要本机 TLS 证书"
            fi
        fi

        if protocolSelectionNeedsPath "${selectCustomInstallType}"; then
            randomPathFunction 4 || return 1
        fi
        if [[ -n "${btDomain}" ]] && protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"; then
            statusCard "跳过伪装网站" "检测到宝塔面板/1Panel"
        elif protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"; then
            nginxBlog 6 || return 1
        fi
        if protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"; then
            updateRedirectNginxConf || return 1
            coreInstallServiceAction "Nginx 服务启动失败，已取消 Xray 安装" handleNginx start || return 1
        fi

        # 安装 Xray
        installXray 7 false || return 1
        initXrayConfig custom 8 || return 1
        installXrayService 9 || return 1
        if protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"; then
            installCronTLS 10 || return 1
        fi

        serviceQueueRestart xray
        serviceQueueApply || return 1
        if protocolSelectionHasAny "${selectCustomInstallType}" 1 2 26; then
            persistRealityEntryProfile || return 1
        fi
        checkGFWStatue 11 || return 1
        cleanUp singBoxDel || return 1
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
    runCoreInstallRestoringNginxOnFailure coreSwitchConfigTransaction xray padmRunPortAllowTransaction customXrayInstallApply "$@"
}


# sing-box 个性化安装
customSingBoxInstallApply() {
    local preselectedProtocols=${1:-}
    local preselectedMode=${2:-}
    local allowedIds
    allowedIds=$(protocolSelectionCurrentIdsForCore sing-box)
    realityOnlyWithDomain=
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

    selectCustomInstallType=$(protocolSelectionNormalizeCsv "${selectCustomInstallType}")

    if [[ "${selectCustomInstallType//,/}" =~ ^[0-9]+$ ]] && protocolSelectionIdsValid "${selectCustomInstallType}" "${allowedIds}"; then
        configureRealityDomainMode "${selectCustomInstallType}" "${preselectedMode}" || return 1
        if protocolSelectionHasAny "${selectCustomInstallType}" 1 26; then
            collectEntryProfile || return 1
        fi
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
        installSingBoxService 6 || return 1
        if protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"; then
            installCronTLS 7 || return 1
        fi
        serviceQueueRestart sing-box
        if protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"; then
            serviceQueueRestart nginx
        fi
        serviceQueueApply || return 1
        if protocolSelectionHasAny "${selectCustomInstallType}" 1 26; then
            persistRealityEntryProfile || return 1
        fi
        checkGFWStatue 8 || return 1
        cleanUp xrayDel || return 1
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
    runCoreInstallRestoringNginxOnFailure coreSwitchConfigTransaction sing-box padmRunPortAllowTransaction customSingBoxInstallApply "$@"
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
    runCoreInstallRestoringNginxOnFailure coreSwitchConfigTransaction xray padmRunPortAllowTransaction xrayCoreInstallApply "$@"
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
    runCoreInstallRestoringNginxOnFailure coreSwitchConfigTransaction sing-box padmRunPortAllowTransaction singBoxInstallApply "$@"
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
