#!/usr/bin/env bash

resolveScriptPath() {
    local sourcePath=${1:-${BASH_SOURCE[0]}}
    while true; do
        local sourceDir targetPath
        sourceDir=$(cd -- "$(dirname -- "${sourcePath}")" && pwd -P) || return 1
        targetPath=$(readlink "${sourcePath}" 2>/dev/null) || break
        [[ -n "${targetPath}" ]] || break
        if [[ "${targetPath}" != /* ]]; then
            sourcePath="${sourceDir}/${targetPath}"
        else
            sourcePath="${targetPath}"
        fi
    done
    printf '%s\n' "${sourcePath}"
}

SCRIPT_PATH=$(resolveScriptPath "${BASH_SOURCE[0]}") || {
    printf '无法解析安装入口实际路径\n' >&2
    exit 1
}
SCRIPT_DIR=$(cd -- "$(dirname -- "${SCRIPT_PATH}")" && pwd -P)
REPO_REF_URL="https://api.github.com/repos/neil1123-vip/padm/commits/main"
REPO_ZIP_URL="https://github.com/neil1123-vip/padm/archive/refs/heads/main.tar.gz"
REPO_ARCHIVE_DIR="padm-main"
SCRIPT_REF_FILE="${SCRIPT_DIR}/.padm-ref"
SCRIPT_EXPECTED_REF_FILE="${SCRIPT_DIR}/.padm-entry-ref"
SCRIPT_MANIFEST_FILE="${SCRIPT_DIR}/.padm-module-manifest"

scriptTmpPath() {
    local template=$1
    local tmpBase="${TMPDIR:-/tmp}"
    printf '%s\n' "${tmpBase%/}/${template}"
}

scriptIsSafeAbsolutePath() {
    local targetPath=$1
    if [[ -z "${targetPath}" || "${targetPath}" != /* || "${targetPath}" == "/" ||
        "${targetPath}" == "/." || "${targetPath}" == "/.." ||
        "${targetPath}" == */./* || "${targetPath}" == */. ||
        "${targetPath}" == */../* || "${targetPath}" == */.. ]]; then
        return 1
    fi
}

scriptRemovePath() {
    local targetPath=$1
    scriptIsSafeAbsolutePath "${targetPath}" || return 1
    rm -rf -- "${targetPath}"
}

scriptCreateTempPath() {
    local tempPath
    tempPath=$(mktemp "$(scriptTmpPath "$1")") || return 1
    scriptIsSafeAbsolutePath "${tempPath}" || return 1
    printf '%s\n' "${tempPath}"
}

scriptCreateTempDir() {
    local tempPath
    tempPath=$(mktemp -d "$(scriptTmpPath "$1")") || return 1
    scriptIsSafeAbsolutePath "${tempPath}" || return 1
    printf '%s\n' "${tempPath}"
}

scriptArchiveEntryIsSafe() {
    local entryPath=$1
    local normalizedPath segment
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

validateRepoArchive() {
    local archiveFile=$1
    local entryList detailList entry line lineType
    entryList=$(scriptCreateTempPath padm-archive-entries.XXXXXX) || return 1
    detailList=$(scriptCreateTempPath padm-archive-details.XXXXXX) || {
        scriptRemovePath "${entryList}" || true
        return 1
    }
    tar -tzf "${archiveFile}" >"${entryList}" 2>/dev/null || {
        scriptRemovePath "${entryList}" || true
        scriptRemovePath "${detailList}" || true
        return 1
    }
    while IFS= read -r entry; do
        scriptArchiveEntryIsSafe "${entry}" || {
            scriptRemovePath "${entryList}" || true
            scriptRemovePath "${detailList}" || true
            return 1
        }
    done <"${entryList}"
    tar -tvzf "${archiveFile}" >"${detailList}" 2>/dev/null || {
        scriptRemovePath "${entryList}" || true
        scriptRemovePath "${detailList}" || true
        return 1
    }
    while IFS= read -r line; do
        lineType="${line:0:1}"
        case "${lineType}" in
        - | d) ;;
        *)
            scriptRemovePath "${entryList}" || true
            scriptRemovePath "${detailList}" || true
            return 1
            ;;
        esac
    done <"${detailList}"
    scriptRemovePath "${entryList}" || true
    scriptRemovePath "${detailList}" || true
}

removeScriptModuleItems() {
    local scriptDir=$1
    scriptIsSafeAbsolutePath "${scriptDir}" || return 1
    rm -rf -- "${scriptDir}/shell" "${scriptDir}/documents" "${scriptDir}/assets" "${scriptDir}/README.md" "${scriptDir}/.padm-module-manifest"
}

restoreScriptModuleBackup() {
    local backupDir=$1
    local scriptDir=$2
    local restoreStatus=0
    [[ -d "${backupDir}" ]] || return 0
    scriptIsSafeAbsolutePath "${scriptDir}" || return 1
    scriptIsSafeAbsolutePath "${backupDir}" || return 1
    removeScriptModuleItems "${scriptDir}" || return 1
    [[ -e "${backupDir}/shell" ]] && { mv "${backupDir}/shell" "${scriptDir}/shell" || restoreStatus=1; }
    [[ -e "${backupDir}/documents" ]] && { mv "${backupDir}/documents" "${scriptDir}/documents" || restoreStatus=1; }
    [[ -e "${backupDir}/assets" ]] && { mv "${backupDir}/assets" "${scriptDir}/assets" || restoreStatus=1; }
    [[ -e "${backupDir}/README.md" ]] && { mv "${backupDir}/README.md" "${scriptDir}/README.md" || restoreStatus=1; }
    [[ -e "${backupDir}/.padm-module-manifest" ]] && { mv "${backupDir}/.padm-module-manifest" "${scriptDir}/.padm-module-manifest" || restoreStatus=1; }
    return "${restoreStatus}"
}

cleanupScriptModuleRefresh() {
    local backupDir=$1
    local scriptDir=$2
    local tmpDir=$3
    if [[ -d "${backupDir}" ]]; then
        if restoreScriptModuleBackup "${backupDir}" "${scriptDir}"; then
            scriptRemovePath "${backupDir}"
        else
            printf '完整安装包替换中断，旧模块恢复失败，请手动检查备份目录: %s\n' "${backupDir}" >&2
        fi
    fi
    scriptRemovePath "${tmpDir}" || true
}

backupScriptModuleItem() {
    local sourcePath=$1
    local backupPath=$2
    [[ -e "${sourcePath}" ]] || return 0
    if [[ -d "${sourcePath}" ]]; then
        cp -R "${sourcePath}" "${backupPath}"
    else
        cp "${sourcePath}" "${backupPath}"
    fi
}

backupScriptModules() {
    local backupDir=$1
    local scriptDir=$2
    scriptIsSafeAbsolutePath "${scriptDir}" || return 1
    scriptIsSafeAbsolutePath "${backupDir}" || return 1
    backupScriptModuleItem "${scriptDir}/shell" "${backupDir}/shell" || return 1
    backupScriptModuleItem "${scriptDir}/documents" "${backupDir}/documents" || return 1
    backupScriptModuleItem "${scriptDir}/assets" "${backupDir}/assets" || return 1
    backupScriptModuleItem "${scriptDir}/README.md" "${backupDir}/README.md" || return 1
    backupScriptModuleItem "${scriptDir}/.padm-module-manifest" "${backupDir}/.padm-module-manifest" || return 1
}

failScriptModuleRefreshAfterBackup() {
    local backupDir=$1
    local scriptDir=$2
    local tmpDir=$3
    if restoreScriptModuleBackup "${backupDir}" "${scriptDir}"; then
        printf '完整安装包替换失败，已恢复旧模块\n'
        scriptRemovePath "${backupDir}"
    else
        printf '完整安装包替换失败，旧模块恢复失败，请手动检查备份目录: %s\n' "${backupDir}"
    fi
    scriptRemovePath "${tmpDir}" || true
    trap - EXIT INT TERM
    exit 1
}

fetchRemoteRef() {
    local metadata
    if command -v curl >/dev/null 2>&1; then
        metadata=$(curl -fsSL "${REPO_REF_URL}") || return 1
    elif command -v wget >/dev/null 2>&1; then
        metadata=$(wget -qO- "${REPO_REF_URL}") || return 1
    else
        return 1
    fi
    printf '%s\n' "${metadata}" | grep -m 1 '"sha"' | cut -d '"' -f 4
}

downloadRepoArchive() {
    local archiveUrl=$1
    local extractDir=$2
    local archiveFile
    scriptRemovePath "${extractDir}" >/dev/null 2>&1 || return 1
    mkdir -p "${extractDir}" || return 1
    archiveFile=$(scriptCreateTempPath padm-archive.XXXXXX.tar.gz) || return 1
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${archiveUrl}" >"${archiveFile}" || {
            scriptRemovePath "${archiveFile}" || true
            return 1
        }
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "${archiveUrl}" >"${archiveFile}" || {
            scriptRemovePath "${archiveFile}" || true
            return 1
        }
    else
        scriptRemovePath "${archiveFile}" || true
        return 127
    fi
    [[ -s "${archiveFile}" ]] || {
        scriptRemovePath "${archiveFile}" || true
        return 1
    }
    validateRepoArchive "${archiveFile}" || {
        scriptRemovePath "${archiveFile}" || true
        return 2
    }
    tar -xzf "${archiveFile}" -C "${extractDir}" || {
        scriptRemovePath "${archiveFile}" || true
        return 1
    }
    scriptRemovePath "${archiveFile}" || true
}

printRepoArchiveDownloadFailure() {
    local status=$1
    case "${status}" in
    127) printf '缺少 curl 或 wget，无法下载完整安装包\n' ;;
    2) printf '完整安装包结构异常，请重新执行安装命令\n' ;;
    *) printf '完整安装包下载失败，请重新执行安装命令\n' ;;
    esac
}

resolveExtractedArchiveDir() {
    local extractDir=$1
    local archiveDir=$2
    local archiveCandidate

    if [[ -d "${archiveDir}/shell" ]]; then
        printf '%s\n' "${archiveDir}"
        return 0
    fi
    for archiveCandidate in "${extractDir}"/*; do
        if [[ -d "${archiveCandidate}/shell" ]]; then
            printf '%s\n' "${archiveCandidate}"
            return 0
        fi
    done
    return 1
}

refreshScriptModules() {
    local remoteRef=$1
    local tmpDir extractDir archiveDir backupDir copyStatus archiveUrl fallbackRef resolvedRef downloadStatus
    if ! scriptIsSafeAbsolutePath "${SCRIPT_DIR}"; then
        printf '脚本目录异常，已取消完整安装包替换\n'
        exit 1
    fi
    tmpDir=$(scriptCreateTempDir padm.XXXXXX) || exit 1
    extractDir="${tmpDir}/extract"
    backupDir="${SCRIPT_DIR}/.padm-update-backup"
    trap 'scriptRemovePath "${tmpDir}" || true' EXIT INT TERM
    archiveUrl="${REPO_ZIP_URL}"
    if [[ -n "${remoteRef}" ]]; then
        archiveUrl="https://github.com/neil1123-vip/padm/archive/${remoteRef}.tar.gz"
    fi
    archiveDir="${extractDir}/${REPO_ARCHIVE_DIR}"
    resolvedRef="${remoteRef:-}"

    printf '正在下载最新完整安装包\n'
    downloadRepoArchive "${archiveUrl}" "${extractDir}"
    downloadStatus=$?
    if [[ "${downloadStatus}" -ne 0 ]]; then
        if [[ -n "${remoteRef}" ]]; then
            fallbackRef=$(fetchRemoteRef || true)
            printf '指定版本完整安装包不可用，回退到主分支最新完整安装包\n'
            downloadRepoArchive "${REPO_ZIP_URL}" "${extractDir}"
            downloadStatus=$?
            if [[ "${downloadStatus}" -ne 0 ]]; then
                printRepoArchiveDownloadFailure "${downloadStatus}"
                scriptRemovePath "${tmpDir}" || true
                exit 1
            fi
            archiveUrl="${REPO_ZIP_URL}"
            resolvedRef="${fallbackRef:-}"
            archiveDir="${extractDir}/${REPO_ARCHIVE_DIR}"
        else
            printRepoArchiveDownloadFailure "${downloadStatus}"
            scriptRemovePath "${tmpDir}" || true
            exit 1
        fi
    fi

    if ! archiveDir=$(resolveExtractedArchiveDir "${extractDir}" "${archiveDir}"); then
        if [[ -n "${remoteRef}" && "${archiveUrl}" != "${REPO_ZIP_URL}" ]]; then
            fallbackRef=$(fetchRemoteRef || true)
            printf '指定版本完整安装包结构异常，回退到主分支最新完整安装包\n'
            if ! downloadRepoArchive "${REPO_ZIP_URL}" "${extractDir}"; then
                printf '完整安装包下载失败，请重新执行安装命令\n'
                scriptRemovePath "${tmpDir}" || true
                exit 1
            fi
            archiveDir=$(resolveExtractedArchiveDir "${extractDir}" "${extractDir}/${REPO_ARCHIVE_DIR}") || {
                printf '完整安装包下载失败，请重新执行安装命令\n'
                scriptRemovePath "${tmpDir}" || true
                exit 1
            }
            resolvedRef="${fallbackRef:-}"
        else
            printf '完整安装包下载失败，请重新执行安装命令\n'
            scriptRemovePath "${tmpDir}" || true
            exit 1
        fi
    fi

    if [[ ! -d "${archiveDir}/shell" ]]; then
        printf '完整安装包下载失败，请重新执行安装命令\n'
        scriptRemovePath "${tmpDir}" || true
        exit 1
    fi

    if [[ -e "${backupDir}" ]]; then
        printf '存在未处理模块备份目录，请手动检查后重试: %s\n' "${backupDir}"
        scriptRemovePath "${tmpDir}" || true
        trap - EXIT INT TERM
        exit 1
    fi
    mkdir -p "${backupDir}" || { scriptRemovePath "${tmpDir}" || true; trap - EXIT INT TERM; exit 1; }
    if ! backupScriptModules "${backupDir}" "${SCRIPT_DIR}"; then
        printf '旧模块备份失败，已取消完整安装包替换\n'
        scriptRemovePath "${backupDir}" || true
        scriptRemovePath "${tmpDir}" || true
        trap - EXIT INT TERM
        exit 1
    fi
    trap 'cleanupScriptModuleRefresh "${backupDir}" "${SCRIPT_DIR}" "${tmpDir}"' EXIT INT TERM
    removeScriptModuleItems "${SCRIPT_DIR}" || failScriptModuleRefreshAfterBackup "${backupDir}" "${SCRIPT_DIR}" "${tmpDir}"

    cp -R "${archiveDir}/shell" "${SCRIPT_DIR}/"
    copyStatus=$?
    if [[ ${copyStatus} -eq 0 && -d "${archiveDir}/documents" ]]; then
        cp -R "${archiveDir}/documents" "${SCRIPT_DIR}/"
        copyStatus=$?
    fi
    if [[ ${copyStatus} -eq 0 && -d "${archiveDir}/assets" ]]; then
        cp -R "${archiveDir}/assets" "${SCRIPT_DIR}/"
        copyStatus=$?
    fi
    if [[ ${copyStatus} -eq 0 && -f "${archiveDir}/README.md" ]]; then
        cp "${archiveDir}/README.md" "${SCRIPT_DIR}/README.md"
        copyStatus=$?
    fi

    if [[ ${copyStatus} -ne 0 ]]; then
        failScriptModuleRefreshAfterBackup "${backupDir}" "${SCRIPT_DIR}" "${tmpDir}"
    fi

    writeModuleManifest "${SCRIPT_MANIFEST_FILE}" || copyStatus=$?
    if [[ ${copyStatus} -ne 0 ]]; then
        failScriptModuleRefreshAfterBackup "${backupDir}" "${SCRIPT_DIR}" "${tmpDir}"
    fi

    if [[ -n "${resolvedRef}" ]]; then
        printf '%s\n' "${resolvedRef}" >"${SCRIPT_REF_FILE}"
    fi
    scriptRemovePath "${backupDir}" || true
    scriptRemovePath "${tmpDir}" || true
    trap - EXIT INT TERM
}

modulePaths() {
    local bootstrapPath="${SCRIPT_DIR}/shell/core/bootstrap.sh"
    local sourcePath relativePath
    [[ -f "${bootstrapPath}" ]] || return 1
    printf 'install.sh\n'
    printf 'shell/core/bootstrap.sh\n'
    printf 'shell/validate_install.sh\n'
    while IFS= read -r sourcePath; do
        case "${sourcePath}" in
        \$\{CORE_DIR\}/*)
            relativePath="shell/core/${sourcePath#\$\{CORE_DIR\}/}"
            ;;
        \$\{SUB_DIR\}/*)
            relativePath="shell/subscription/${sourcePath#\$\{SUB_DIR\}/}"
            ;;
        *)
            return 1
            ;;
        esac
        printf '%s\n' "${relativePath}"
    done < <(grep '^source ' "${bootstrapPath}" | sed 's/^source "//; s/"$//')
}

scriptModuleFilesPresent() {
    local moduleList requiredPath
    moduleList=$(scriptCreateTempPath padm-modules.XXXXXX) || return 1
    if ! modulePaths >"${moduleList}"; then
        rm -f "${moduleList}"
        return 1
    fi
    while IFS= read -r requiredPath; do
        [[ -f "${SCRIPT_DIR}/${requiredPath}" ]] || { rm -f "${moduleList}"; return 1; }
    done <"${moduleList}"
    rm -f "${moduleList}"
}

scriptModulesReady() {
    local localRef expectedRef
    scriptModuleFilesPresent || return 1
    moduleManifestReady "${SCRIPT_MANIFEST_FILE}" || return 1
    [[ -f "${SCRIPT_EXPECTED_REF_FILE}" ]] || return 0
    [[ -f "${SCRIPT_REF_FILE}" ]] || return 1
    expectedRef=$(cat "${SCRIPT_EXPECTED_REF_FILE}")
    localRef=$(cat "${SCRIPT_REF_FILE}")
    [[ -z "${expectedRef}" || "${expectedRef}" == "${localRef}" ]]
}

moduleManifestReady() {
    local manifestPath=$1
    local line expectedHash relativePath actualHash
    command -v sha256sum >/dev/null 2>&1 || return 0
    [[ -f "${manifestPath}" ]] || return 1
    while IFS='  ' read -r expectedHash relativePath; do
        [[ -n "${expectedHash}" && -n "${relativePath}" ]] || continue
        [[ -f "${SCRIPT_DIR}/${relativePath}" ]] || return 1
        actualHash=$(sha256sum "${SCRIPT_DIR}/${relativePath}" | cut -d ' ' -f 1) || return 1
        [[ "${actualHash}" == "${expectedHash}" ]] || return 1
    done <"${manifestPath}"
}

writeModuleManifest() {
    local manifestPath=$1
    local requiredPath moduleList
    command -v sha256sum >/dev/null 2>&1 || return 0
    moduleList=$(scriptCreateTempPath padm-modules.XXXXXX) || return 1
    if ! modulePaths >"${moduleList}"; then
        rm -f "${moduleList}"
        return 1
    fi
    : >"${manifestPath}" || { rm -f "${moduleList}"; return 1; }
    while IFS= read -r requiredPath; do
        [[ -f "${SCRIPT_DIR}/${requiredPath}" ]] || { rm -f "${moduleList}"; return 1; }
        sha256sum "${SCRIPT_DIR}/${requiredPath}" | awk -v path="${requiredPath}" '{ print $1 "  " path }' >>"${manifestPath}" || { rm -f "${moduleList}"; return 1; }
    done <"${moduleList}"
    rm -f "${moduleList}"
}

ensureScriptModules() {
    local remoteRef= expectedRef=
    if [[ "${PADM_FORCE_SCRIPT_MODULE_REFRESH:-}" == "1" ]]; then
        remoteRef=$(fetchRemoteRef || true)
        refreshScriptModules "${remoteRef}"
        if [[ -s "${SCRIPT_REF_FILE}" ]]; then
            cp "${SCRIPT_REF_FILE}" "${SCRIPT_EXPECTED_REF_FILE}"
        fi
        return 0
    fi
    if scriptModulesReady; then
        return 0
    fi
    if [[ -f "${SCRIPT_EXPECTED_REF_FILE}" ]]; then
        expectedRef=$(cat "${SCRIPT_EXPECTED_REF_FILE}")
    fi
    if [[ "${PADM_SKIP_REMOTE_REF_CHECK:-}" == "1" ]]; then
        if scriptModuleFilesPresent; then
            return 0
        fi
        refreshScriptModules "${expectedRef}"
        return 0
    fi

    remoteRef="${expectedRef}"
    [[ -n "${remoteRef}" ]] || remoteRef=$(fetchRemoteRef || true)
    refreshScriptModules "${remoteRef}"
    if [[ -s "${SCRIPT_REF_FILE}" ]]; then
        cp "${SCRIPT_REF_FILE}" "${SCRIPT_EXPECTED_REF_FILE}"
    fi
}

loadScriptModules() {
    ensureScriptModules
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/shell/core/bootstrap.sh"
}

initScriptRuntime() {
    parseInstallArgs "$@"
    initVar "$1"
    if [[ "${cronName}" == "RefreshScriptModules" ]]; then
        return 0
    fi
    checkSystem
    checkCPUVendor

    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    readCustomPort
    readSingBoxConfig
}

handleScriptCommand() {
    if [[ "${cronName}" == "RefreshScriptModules" ]]; then
        exit 0
    elif [[ "${cronName}" == "RenewTLS" ]]; then
        renewalTLS
        exit 0
    elif [[ "${cronName}" == "UpdateGeo" ]]; then
        updateGeoSite >>/etc/padm/crontab_updateGeoSite.log
        printf 'geo更新日期:%s\n' "$(date "+%F %H:%M:%S")" >>/etc/padm/crontab_updateGeoSite.log
        exit 0
    elif [[ "${cronName}" == "SyncSubscriptionGroups" ]]; then
        runSubscriptionGroupSyncCron skip-subscribe-refresh
        exit $?
    elif [[ "${cronName}" == "SubscriptionControl" ]]; then
        shift
        handleSubscriptionControl "$@"
        exit $?
    elif [[ "${cronName}" == "InstallSubscription" ]]; then
        local installStatus
        if ! mkdirTools; then
            errorCard "初始化安装目录失败"
            exit 1
        fi
        installSubscribe
        installStatus=$?
        if [[ "${installStatus}" -eq 0 ]]; then
            readNginxSubscribe
            if [[ -n "${subscribePort}" ]]; then
                successCard "订阅服务安装完成: ${subscribeType} 端口 ${subscribePort}"
            fi
        fi
        exit "${installStatus}"
    fi
}

runMainMenu() {
    checkRoot
    handleScriptCommand "$@"
    menu
}

loadScriptModules
initScriptRuntime "$@"
runMainMenu "$@"
