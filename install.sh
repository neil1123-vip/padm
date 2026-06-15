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

scriptCreateTempPath() {
    mktemp "$(scriptTmpPath "$1")"
}

scriptCreateTempDir() {
    mktemp -d "$(scriptTmpPath "$1")"
}

restoreScriptModuleBackup() {
    local backupDir=$1
    local scriptDir=$2
    local restoreStatus=0
    [[ -d "${backupDir}" ]] || return 0
    rm -rf "${scriptDir}/shell" "${scriptDir}/documents" "${scriptDir}/assets" "${scriptDir}/README.md" "${scriptDir}/.padm-module-manifest" || return 1
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
            rm -rf "${backupDir}"
        else
            printf '完整安装包替换中断，旧模块恢复失败，请手动检查备份目录: %s\n' "${backupDir}" >&2
        fi
    fi
    rm -rf "${tmpDir}"
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
        rm -rf "${backupDir}"
    else
        printf '完整安装包替换失败，旧模块恢复失败，请手动检查备份目录: %s\n' "${backupDir}"
    fi
    rm -rf "${tmpDir}"
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

refreshScriptModules() {
    local remoteRef=$1
    local tmpDir archiveDir backupDir copyStatus archiveUrl archiveCandidate
    tmpDir=$(scriptCreateTempDir padm.XXXXXX) || exit 1
    backupDir="${SCRIPT_DIR}/.padm-update-backup"
    trap 'rm -rf "${tmpDir}"' EXIT INT TERM
    archiveUrl="${REPO_ZIP_URL}"
    if [[ -n "${remoteRef}" ]]; then
        archiveUrl="https://github.com/neil1123-vip/padm/archive/${remoteRef}.tar.gz"
    fi
    archiveDir="${tmpDir}/${REPO_ARCHIVE_DIR}"

    printf '正在下载最新完整安装包\n'
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${archiveUrl}" | tar -xz -C "${tmpDir}"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "${archiveUrl}" | tar -xz -C "${tmpDir}"
    else
        printf '缺少 curl 或 wget，无法下载完整安装包\n'
        rm -rf "${tmpDir}"
        exit 1
    fi

    if [[ ! -d "${archiveDir}/shell" ]]; then
        for archiveCandidate in "${tmpDir}"/*; do
            if [[ -d "${archiveCandidate}/shell" ]]; then
                archiveDir="${archiveCandidate}"
                break
            fi
        done
    fi
    if [[ ! -d "${archiveDir}/shell" ]]; then
        printf '完整安装包下载失败，请重新执行安装命令\n'
        rm -rf "${tmpDir}"
        exit 1
    fi

    if [[ -e "${backupDir}" ]]; then
        printf '存在未处理模块备份目录，请手动检查后重试: %s\n' "${backupDir}"
        rm -rf "${tmpDir}"
        trap - EXIT INT TERM
        exit 1
    fi
    mkdir -p "${backupDir}" || { rm -rf "${tmpDir}"; trap - EXIT INT TERM; exit 1; }
    if ! backupScriptModules "${backupDir}" "${SCRIPT_DIR}"; then
        printf '旧模块备份失败，已取消完整安装包替换\n'
        rm -rf "${backupDir}" "${tmpDir}"
        trap - EXIT INT TERM
        exit 1
    fi
    trap 'cleanupScriptModuleRefresh "${backupDir}" "${SCRIPT_DIR}" "${tmpDir}"' EXIT INT TERM
    rm -rf "${SCRIPT_DIR}/shell" "${SCRIPT_DIR}/documents" "${SCRIPT_DIR}/assets" "${SCRIPT_DIR}/README.md" "${SCRIPT_MANIFEST_FILE}" || failScriptModuleRefreshAfterBackup "${backupDir}" "${SCRIPT_DIR}" "${tmpDir}"

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

    [[ -n "${remoteRef}" ]] && printf '%s\n' "${remoteRef}" >"${SCRIPT_REF_FILE}"
    rm -rf "${backupDir}" "${tmpDir}"
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
        [[ -n "${remoteRef}" ]] && printf '%s\n' "${remoteRef}" >"${SCRIPT_EXPECTED_REF_FILE}"
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
    [[ -n "${remoteRef}" ]] && printf '%s\n' "${remoteRef}" >"${SCRIPT_EXPECTED_REF_FILE}"
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
        runSubscriptionGroupSyncCron
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
