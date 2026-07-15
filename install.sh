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

scriptDownloadUrlToFileBounded() {
    local url=$1
    local targetFile=$2
    local maxSize=$3
    local maxTime=${4:-30}
    local toolFound=false
    local -a pipelineStatus=()
    [[ -n "${url}" && "${maxSize}" =~ ^[0-9]+$ && "${maxSize}" -gt 0 ]] || return 1
    [[ "${maxTime}" =~ ^[0-9]+$ && "${maxTime}" -gt 0 ]] || return 1

    : >"${targetFile}" || return 1
    if command -v curl >/dev/null 2>&1; then
        toolFound=true
        if curl -fsSL --connect-timeout 10 --max-time "${maxTime}" --max-filesize "${maxSize}" -o "${targetFile}" "${url}" &&
            [[ "$(wc -c <"${targetFile}")" -le "${maxSize}" ]]; then
            return 0
        fi
    fi

    : >"${targetFile}" || return 1
    if command -v wget >/dev/null 2>&1; then
        toolFound=true
        wget -T 30 -t 2 -qO- "${url}" | head -c "$((maxSize + 1))" >"${targetFile}"
        pipelineStatus=("${PIPESTATUS[@]}")
        if [[ "${pipelineStatus[0]:-1}" -eq 0 && "${pipelineStatus[1]:-1}" -eq 0 &&
            "$(wc -c <"${targetFile}")" -le "${maxSize}" ]]; then
            return 0
        fi
    fi
    [[ "${toolFound}" == "true" ]] || return 127
    return 1
}

protectedRegressionWorktreeRoot() {
    local worktreeRoot=${PADM_REGRESSION_WORKTREE_ROOT:-}
    [[ "${PADM_REGRESSION_PROTECT_WORKTREE:-}" == "1" ]] || return 1
    [[ -n "${worktreeRoot}" ]] || return 1
    worktreeRoot=$(cd -- "${worktreeRoot}" 2>/dev/null && pwd -P) || return 1
    printf '%s\n' "${worktreeRoot}"
}

regressionWorktreeRefreshForbidden() {
    local protectedRoot scriptDir
    protectedRoot=$(protectedRegressionWorktreeRoot) || return 1
    scriptDir=$(cd -- "${SCRIPT_DIR}" 2>/dev/null && pwd -P) || return 1
    [[ "${scriptDir}" == "${protectedRoot}" ]] || return 1
    printf '检测到回归工作区，已禁止完整安装包刷新: %s\n' "${scriptDir}" >&2
    return 0
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

scriptArchiveExpandedSizeIsSafe() {
    local archiveFile=$1
    local entryList=$2
    local entryCount expandedBytes

    entryCount=$(wc -l <"${entryList}" | tr -d '[:space:]') || return 1
    [[ "${entryCount}" =~ ^[0-9]+$ ]] && ((entryCount <= 10000)) || return 1
    expandedBytes=$(
        { tar -xOzf "${archiveFile}" 2>/dev/null || true; } |
            head -c 104857601 |
            wc -c |
            tr -d '[:space:]'
    ) || return 1
    [[ "${expandedBytes}" =~ ^[0-9]+$ ]] && ((expandedBytes <= 104857600))
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
    scriptArchiveExpandedSizeIsSafe "${archiveFile}" "${entryList}" || {
        scriptRemovePath "${entryList}" || true
        scriptRemovePath "${detailList}" || true
        return 1
    }
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
    local metadataFile
    local metadata
    metadataFile=$(scriptCreateTempPath padm-ref.XXXXXX) || return 1
    if ! scriptDownloadUrlToFileBounded "${REPO_REF_URL}" "${metadataFile}" 1048576; then
        scriptRemovePath "${metadataFile}" || true
        return 1
    fi
    metadata=$(<"${metadataFile}")
    scriptRemovePath "${metadataFile}" || true
    printf '%s\n' "${metadata}" | grep -m 1 '"sha"' | cut -d '"' -f 4
}

downloadRepoArchive() {
    local archiveUrl=$1
    local extractDir=$2
    local archiveFile
    local downloadStatus=0
    scriptRemovePath "${extractDir}" >/dev/null 2>&1 || return 1
    mkdir -p "${extractDir}" || return 1
    archiveFile=$(scriptCreateTempPath padm-archive.XXXXXX.tar.gz) || return 1
    scriptDownloadUrlToFileBounded "${archiveUrl}" "${archiveFile}" 52428800 120 || downloadStatus=$?
    if [[ "${downloadStatus}" -ne 0 ]]; then
        scriptRemovePath "${archiveFile}" || true
        return "${downloadStatus}"
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
    local tmpDir extractDir archiveDir backupDir copyStatus archiveUrl resolvedRef downloadStatus
    if regressionWorktreeRefreshForbidden; then
        exit 1
    fi
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
        printRepoArchiveDownloadFailure "${downloadStatus}"
        scriptRemovePath "${tmpDir}" || true
        exit 1
    fi

    if ! archiveDir=$(resolveExtractedArchiveDir "${extractDir}" "${archiveDir}"); then
        printf '完整安装包下载失败，请重新执行安装命令\n'
        scriptRemovePath "${tmpDir}" || true
        exit 1
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
    local moduleList requiredPath expectedHash actualHash moduleCount manifestCount
    command -v sha256sum >/dev/null 2>&1 || return 1
    [[ -f "${manifestPath}" ]] || return 1
    moduleList=$(scriptCreateTempPath padm-modules.XXXXXX) || return 1
    if ! modulePaths >"${moduleList}"; then
        rm -f "${moduleList}"
        return 1
    fi
    moduleCount=$(wc -l <"${moduleList}" | tr -d ' ')
    manifestCount=$(awk 'NF == 0 { next } NF != 2 { bad = 1 } { count++ } END { if (bad) exit 1; print count + 0 }' "${manifestPath}") || {
        rm -f "${moduleList}"
        return 1
    }
    [[ "${manifestCount}" == "${moduleCount}" ]] || {
        rm -f "${moduleList}"
        return 1
    }
    while IFS= read -r requiredPath; do
        expectedHash=$(awk -v path="${requiredPath}" '$2 == path { if (seen++) exit 2; print $1 }' "${manifestPath}") || {
            rm -f "${moduleList}"
            return 1
        }
        [[ -n "${expectedHash}" && -f "${SCRIPT_DIR}/${requiredPath}" ]] || {
            rm -f "${moduleList}"
            return 1
        }
        actualHash=$(sha256sum "${SCRIPT_DIR}/${requiredPath}" | cut -d ' ' -f 1) || {
            rm -f "${moduleList}"
            return 1
        }
        [[ "${actualHash}" == "${expectedHash}" ]] || {
            rm -f "${moduleList}"
            return 1
        }
    done <"${moduleList}"
    rm -f "${moduleList}"
}

writeModuleManifest() {
    local manifestPath=$1
    local requiredPath moduleList
    command -v sha256sum >/dev/null 2>&1 || return 1
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
        if regressionWorktreeRefreshForbidden; then
            return 1
        fi
        remoteRef="${PADM_SCRIPT_MODULE_REF:-}"
        [[ -n "${remoteRef}" ]] || remoteRef=$(fetchRemoteRef || true)
        refreshScriptModules "${remoteRef}"
        if [[ -s "${SCRIPT_REF_FILE}" ]]; then
            cp "${SCRIPT_REF_FILE}" "${SCRIPT_EXPECTED_REF_FILE}"
        fi
        return 0
    fi
    if scriptModulesReady; then
        return 0
    fi
    if regressionWorktreeRefreshForbidden; then
        return 1
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

installEarlyCapabilityRegistry() {
    cat <<'EOF'
1|VLESS Reality Vision|node|recommended|xray,sing-box|tcp|reality|none|
2|VLESS Reality XHTTP|node|recommended|xray|xhttp|reality|none|
3|Hysteria2|node|recommended|sing-box|quic|tls|none|
4|AnyTLS|node|recommended|sing-box|tcp|tls|none|
5|NaiveProxy|node|recommended|sing-box|tcp|tls|none|
21|VLESS WS TLS|node|advanced|xray|ws|tls|http_front|WebSocket 属高级方案，新装优先 XHTTP|VLESS Reality XHTTP
22|VMess WS TLS|node|advanced|xray|ws|tls|http_front|VMess 与 WebSocket 均为高级方案|VLESS Reality Vision
23|VMess HTTPUpgrade TLS|node|advanced|xray,sing-box|httpupgrade|tls|http_front|HTTPUpgrade 属高级方案，新装优先 XHTTP|VLESS Reality XHTTP
24|VLESS gRPC TLS|node|advanced|xray|grpc|tls|grpc_front|gRPC 有主动探测与 fallback 限制|VLESS Reality XHTTP
25|Trojan gRPC TLS|node|advanced|xray|grpc|tls|grpc_front|gRPC 有主动探测与 fallback 限制|AnyTLS
26|VLESS Reality gRPC|node|advanced|xray,sing-box|grpc|reality|none|Reality gRPC 是高级方案|VLESS Reality Vision
27|VLESS TCP TLS Vision|node|advanced|xray|tcp|tls|fallback_backend|传统 TLS/fallback 高级路径|VLESS Reality Vision
28|Trojan TCP TLS direct|node|advanced|xray,sing-box|tcp|tls|none|传统 TLS 协议，仅显式选择时使用|AnyTLS
29|Trojan TCP TLS fallback|node|advanced|xray|tcp|tls|fallback_backend|fallback 仅限 TCP+TLS|AnyTLS
30|Shadowsocks|node|advanced|sing-box|tcp|none|none|不作为默认公网节点推荐|VLESS Reality Vision
31|TUIC|node|advanced|sing-box|quic|tls|none|UDP/弱网新装引导使用 Hysteria2|Hysteria2
201|Socks 中继|internal|advanced|xray,sing-box|tcp|none|none|
202|HTTP 中继|internal|advanced|xray,sing-box|tcp|none|none|
203|WireGuard|internal|advanced|xray,sing-box|udp|none|none|
204|TUN|internal|advanced|sing-box|mixed|none|none|
205|Redirect/TProxy|internal|advanced|xray,sing-box|tcp,udp|none|none|
206|DNS/Direct/Block|internal|advanced|xray,sing-box|mixed|none|none|
207|Tunnel/dokodemo-door|internal|advanced|xray|tcp,udp|none|none|
301|Xray Hysteria2 inbound|known|advanced|none|quic|tls|none|
302|Hysteria v1|known|advanced|none|quic|tls|none|
303|ShadowTLS|known|advanced|none|tcp|tls|none|
304|mKCP combinations|known|advanced|none|mkcp|none|none|
305|Cloudflared inbound|known|advanced|none|tcp|tls|none|
306|Selector|known|advanced|none|mixed|none|none|
307|URLTest|known|advanced|none|mixed|none|none|
308|Tor outbound|known|advanced|none|tcp|none|none|
309|SSH outbound|known|advanced|none|tcp|ssh|none|
EOF
}

installPrintEarlyCapabilities() {
    local categoryFilter=${1:-}
    local riskyOnly=${2:-false}
    local id name category lifecycle projectCore transport security nginxMode risk replacement
    while IFS='|' read -r id name category lifecycle projectCore transport security nginxMode risk replacement; do
        [[ -z "${categoryFilter}" || "${category}" == "${categoryFilter}" ]] || continue
        [[ "${riskyOnly}" != "true" || -n "${risk}" ]] || continue
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "${id}" "${name}" "${category}" "${lifecycle}" "${projectCore}" "${transport}" "${security}" "${nginxMode}"
        if [[ -n "${risk}" ]]; then
            printf '\t%s' "${risk}"
            [[ -n "${replacement}" ]] && printf '\t替代：%s' "${replacement}"
        fi
        printf '\n'
    done < <(installEarlyCapabilityRegistry)
}

installHandleEarlyCapabilityListArgs() {
    local arg
    for arg in "$@"; do
        case "${arg}" in
        --list-protocols)
            installPrintEarlyCapabilities node false
            exit 0
            ;;
        --list-capabilities)
            installPrintEarlyCapabilities "" false
            exit 0
            ;;
        --show-risky-protocols)
            installPrintEarlyCapabilities node true
            exit 0
            ;;
        esac
    done
}

initScriptRuntime() {
    parseInstallArgs "$@"
    autoInstallValidateRequiredInputs || exit 1
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
        exit $?
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

installHandleEarlyCapabilityListArgs "$@"
loadScriptModules
initScriptRuntime "$@"
runMainMenu "$@"
exit $?
