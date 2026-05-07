#!/usr/bin/env bash
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_REF_URL="https://api.github.com/repos/neil1123-vip/padm/commits/main"
REPO_ZIP_URL="https://github.com/neil1123-vip/padm/archive/refs/heads/main.tar.gz"
REPO_ARCHIVE_DIR="padm-main"
SCRIPT_REF_FILE="${SCRIPT_DIR}/.padm-ref"

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
    local tmpDir archiveDir
    tmpDir=$(mktemp -d /tmp/padm.XXXXXX) || exit 1
    archiveDir="${tmpDir}/${REPO_ARCHIVE_DIR}"

    printf '正在下载最新完整安装包\n'
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${REPO_ZIP_URL}" | tar -xz -C "${tmpDir}"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "${REPO_ZIP_URL}" | tar -xz -C "${tmpDir}"
    else
        printf '缺少 curl 或 wget，无法下载完整安装包\n'
        rm -rf "${tmpDir}"
        exit 1
    fi

    if [[ ! -d "${archiveDir}/shell" ]]; then
        printf '完整安装包下载失败，请重新执行安装命令\n'
        rm -rf "${tmpDir}"
        exit 1
    fi

    rm -rf "${SCRIPT_DIR}/shell" "${SCRIPT_DIR}/documents" "${SCRIPT_DIR}/assets"
    cp -R "${archiveDir}/shell" "${SCRIPT_DIR}/"
    [[ -d "${archiveDir}/documents" ]] && cp -R "${archiveDir}/documents" "${SCRIPT_DIR}/"
    [[ -d "${archiveDir}/assets" ]] && cp -R "${archiveDir}/assets" "${SCRIPT_DIR}/"
    [[ -f "${archiveDir}/README.md" ]] && cp "${archiveDir}/README.md" "${SCRIPT_DIR}/README.md"
    [[ -n "${remoteRef}" ]] && printf '%s\n' "${remoteRef}" >"${SCRIPT_REF_FILE}"
    rm -rf "${tmpDir}"
}

ensureScriptModules() {
    local remoteRef localRef
    remoteRef=$(fetchRemoteRef || true)
    [[ -f "${SCRIPT_REF_FILE}" ]] && localRef=$(cat "${SCRIPT_REF_FILE}")

    if [[ ! -f "${SCRIPT_DIR}/shell/core/bootstrap.sh" ]]; then
        refreshScriptModules "${remoteRef}"
    elif [[ -n "${remoteRef}" && "${remoteRef}" != "${localRef}" ]]; then
        refreshScriptModules "${remoteRef}"
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
        printf 'geo更新日期:%s\n' "$(date "+%F %H:%M:%S")" >>/etc/padm/crontab_updateGeoSite.log
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
            successCard "订阅服务安装完成: ${subscribeType} 端口 ${subscribePort}"
        fi
        exit 0
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
