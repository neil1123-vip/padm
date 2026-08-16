#!/usr/bin/env bash

PADM_CLEANUP_PATHS=()
PADM_CLEANUP_TRAP_INSTALLED=

padmResolveCleanupPath() {
    local path=$1
    local parent base
    [[ -n "${path}" ]] || return 1
    if [[ "${path}" != /* ]]; then
        parent=$(dirname -- "${path}")
        base=$(basename -- "${path}")
        parent=$(cd -- "${parent}" 2>/dev/null && pwd -P) || return 1
        printf '%s\n' "${parent}/${base}"
        return 0
    fi
    printf '%s\n' "${path}"
}

padmResolveManagedAbsolutePath() {
    local path=$1
    [[ -n "${path}" ]] || return 1
    while [[ "${path}" == ./* ]]; do
        path="${path#./}"
    done
    if [[ "${path}" != /* ]]; then
        if [[ "${path}" == "." || "${path}" == ".." ||
            "${path}" == */./* || "${path}" == */. ||
            "${path}" == */../* || "${path}" == */.. ]]; then
            return 1
        fi
        path="$(pwd -P)/${path}"
    fi
    padmIsSafeAbsolutePath "${path}" || return 1
    printf '%s\n' "${path}"
}

padmRequireSafeAbsolutePath() {
    local path=$1
    [[ -n "${path}" ]] || return 1
    padmIsSafeAbsolutePath "${path}" || return 1
    printf '%s\n' "${path}"
}

coreSafeConfigDir() { local path=${1%/}; padmRequireSafeAbsolutePath "${path}" >/dev/null || return 1; printf '%s/\n' "${path}"; }

padmManagedFilePath() {
    local dirPath=$1
    local fileName=$2

    [[ -n "${fileName}" && "${fileName}" != "." && "${fileName}" != ".." && "${fileName}" != */* ]] || return 1
    dirPath=$(padmRequireSafeAbsolutePath "${dirPath%/}") || return 1
    printf '%s\n' "${dirPath}/${fileName}"
}

padmManagedPathWithinRoot() {
    local rootPath=$1
    local relativePath=$2

    [[ -n "${relativePath}" && "${relativePath}" != /* &&
        "${relativePath}" != "." && "${relativePath}" != ".." &&
        "${relativePath}" != */./* && "${relativePath}" != */. &&
        "${relativePath}" != */../* && "${relativePath}" != */.. ]] || return 1
    rootPath=$(padmRequireSafeAbsolutePath "${rootPath%/}") || return 1
    printf '%s\n' "${rootPath}/${relativePath}"
}

padmIsValidHostName() {
    local host=$1
    local label octet
    [[ -n "${host}" && ${#host} -le 253 ]] || return 1
    [[ "${host}" != *[[:space:]]* && "${host}" != *[\"\'\\/:\;\,\{\}\[\]\(\)]* ]] || return 1
    if [[ "${host}" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
        local IFS=.
        read -r -a octets <<<"${host}"
        for octet in "${octets[@]}"; do
            [[ "${octet}" =~ ^[0-9]+$ ]] && ((10#${octet} <= 255)) || return 1
        done
        return 0
    fi
    [[ "${host}" != .* && "${host}" != *. && "${host}" != *..* ]] || return 1
    local IFS=.
    read -r -a labels <<<"${host}"
    for label in "${labels[@]}"; do
        [[ ${#label} -ge 1 && ${#label} -le 63 ]] || return 1
        [[ "${label}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    done
}

padmIsValidIPv6Address() {
    local address=$1
    local part
    local -a parts
    [[ -n "${address}" && ${#address} -le 45 ]] || return 1
    [[ "${address}" == *:*:* && "${address}" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
    [[ "${address}" != *:::* && "${address}" != *::*::* ]] || return 1
    [[ "${address}" == ::* || "${address}" != :* ]] || return 1
    [[ "${address}" == *:: || "${address}" != *: ]] || return 1

    local IFS=:
    read -r -a parts <<<"${address}"
    if [[ "${address}" != *::* ]]; then
        ((${#parts[@]} == 8)) || return 1
    else
        ((${#parts[@]} <= 8)) || return 1
    fi
    for part in "${parts[@]}"; do
        [[ -z "${part}" || "${part}" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
    done
}

padmIsValidConnectAddress() {
    padmIsValidHostName "$1" || padmIsValidIPv6Address "$1"
}

padmIsSafeRoutePath() {
    local path=$1
    [[ "${path}" =~ ^/[A-Za-z0-9._~/-]+$ ]] || return 1
    [[ "${path}" != *'//'*
        && "${path}" != *'/../'*
        && "${path}" != '/../'*
        && "${path}" != *'/..'
        && "${path}" != *'/%'* ]]
}

padmIsSafeRoutePathSegment() {
    local segment=$1
    [[ -n "${segment}" && ${#segment} -le 64 && "${segment}" =~ ^[A-Za-z0-9._~-]+$ ]]
}

padmInstallCleanupTrap() {
    if [[ -n "${PADM_CLEANUP_TRAP_INSTALLED}" ]]; then
        return 0
    fi
    PADM_CLEANUP_TRAP_INSTALLED=1
    trap 'padmCleanupTempPaths' EXIT
    trap 'padmCleanupTempPaths INT' INT
    trap 'padmCleanupTempPaths TERM' TERM
}

padmRegisterCleanupPath() {
    local path=$1
    local resolvedPath=
    [[ -n "${path}" ]] || return 0
    resolvedPath=$(padmResolveCleanupPath "${path}" 2>/dev/null || true)
    PADM_CLEANUP_PATHS+=("${resolvedPath:-${path}}")
}

padmUnregisterCleanupPath() {
    local path=$1
    local kept=()
    local item
    for item in "${PADM_CLEANUP_PATHS[@]}"; do
        [[ "${item}" == "${path}" ]] || kept+=("${item}")
    done
    PADM_CLEANUP_PATHS=("${kept[@]}")
}

padmCreateTempPath() {
    local resultVar=$1
    shift
    local path
    path=$(mktemp "$@") || return 1
    padmInstallCleanupTrap
    padmRegisterCleanupPath "${path}"
    printf -v "${resultVar}" '%s' "${path}"
}

padmCreateTmpRootPath() {
    local resultVar=$1
    local template=$2
    shift 2
    padmCreateTempPath "${resultVar}" "$@" "$(padmTmpFilePath "${template}")"
}

padmCreateTempFileForTarget() {
    local resultVar=$1
    local targetFile=$2
    local label=${3:-tmp}
    local targetDir targetName
    targetFile=$(padmResolveManagedAbsolutePath "${targetFile}") || return 1
    targetDir=$(dirname -- "${targetFile}")
    targetName=$(basename -- "${targetFile}")
    padmEnsureSafeDirectory "${targetDir}" || return 1
    padmCreateTempPath "${resultVar}" "${targetDir}/.${targetName}.${label}.XXXXXX"
}

padmTmpFilePath() {
    local fileName=$1
    local tmpBase="${TMPDIR:-/tmp}"
    printf '%s\n' "${tmpBase%/}/${fileName}"
}

padmForgetCleanupPath() {
    local path=$1
    local resolvedPath=
    resolvedPath=$(padmResolveCleanupPath "${path}" 2>/dev/null || true)
    padmUnregisterCleanupPath "${resolvedPath:-${path}}"
}

padmRemoveCleanupPath() {
    local path=$1
    local resolvedPath=
    resolvedPath=$(padmResolveCleanupPath "${path}" 2>/dev/null || true)
    if rm -rf -- "${resolvedPath:-${path}}" >/dev/null 2>&1; then
        padmUnregisterCleanupPath "${resolvedPath:-${path}}"
    fi
}

padmCommitTargetIsFileLike() {
    local targetFile=$1
    targetFile=$(padmResolveManagedAbsolutePath "${targetFile}") || return 1
    [[ ! -d "${targetFile}" ]] || return 1
    [[ ! -e "${targetFile}" || -f "${targetFile}" || -L "${targetFile}" ]]
}

removeManagedFileIfPresent() {
    local targetFile=$1

    targetFile=$(padmRequireSafeAbsolutePath "${targetFile}") || return 1
    [[ ! -e "${targetFile}" || -f "${targetFile}" || -L "${targetFile}" ]] || return 1
    rm -f -- "${targetFile}" >/dev/null 2>&1 || return 1
}

removeManagedFilesIfPresent() {
    local targetFile
    local resolvedTarget
    local -a resolvedTargets=()

    for targetFile in "$@"; do
        resolvedTarget=$(padmRequireSafeAbsolutePath "${targetFile}") || return 1
        [[ ! -e "${resolvedTarget}" || -f "${resolvedTarget}" || -L "${resolvedTarget}" ]] || return 1
        resolvedTargets+=("${resolvedTarget}")
    done
    for resolvedTarget in "${resolvedTargets[@]}"; do
        rm -f -- "${resolvedTarget}" >/dev/null 2>&1 || return 1
    done
}

removeManagedFilesIfPresentIgnoreFailure() {
    local targetFile

    for targetFile in "$@"; do
        removeManagedFileIfPresent "${targetFile}" >/dev/null 2>&1 || true
    done
}

removeManagedPathIfPresentIgnoreFailure() {
    local targetPath

    for targetPath in "$@"; do
        removeManagedPathIfPresent "${targetPath}" >/dev/null 2>&1 || true
    done
}

removeManagedPathIfPresent() {
    local targetPath=$1

    targetPath=$(padmResolveManagedAbsolutePath "${targetPath}") || return 1
    if [[ ! -e "${targetPath}" && ! -L "${targetPath}" ]]; then
        return 0
    fi
    if [[ -d "${targetPath}" && ! -L "${targetPath}" ]]; then
        padmRemoveCleanupPath "${targetPath}"
        [[ ! -e "${targetPath}" && ! -L "${targetPath}" ]]
        return $?
    fi
    removeManagedFileIfPresent "${targetPath}"
}

padmResolvePathWithinRoot() {
    local rootPath=$1
    local targetPath=$2
    local parentPath targetName resolvedTarget

    rootPath=$(padmResolveManagedAbsolutePath "${rootPath}") || return 1
    [[ -n "${targetPath}" && "${targetPath}" == /* ]] || return 1
    parentPath=$(dirname -- "${targetPath}")
    targetName=$(basename -- "${targetPath}")
    parentPath=$(cd -- "${parentPath}" 2>/dev/null && pwd -P) || return 1
    resolvedTarget="${parentPath}/${targetName}"
    case "${resolvedTarget}" in
    "${rootPath}"/*) printf '%s\n' "${resolvedTarget}" ;;
    *) return 1 ;;
    esac
}

removeManagedPathWithinRootIfPresent() {
    local rootPath=$1
    local targetPath=$2

    targetPath=$(padmResolvePathWithinRoot "${rootPath}" "${targetPath}") || return 1
    if [[ ! -e "${targetPath}" && ! -L "${targetPath}" ]]; then
        return 0
    fi
    if [[ -d "${targetPath}" && ! -L "${targetPath}" ]]; then
        padmRemoveCleanupPath "${targetPath}"
    else
        rm -f -- "${targetPath}" >/dev/null 2>&1 || return 1
        padmUnregisterCleanupPath "${targetPath}"
    fi
    [[ ! -e "${targetPath}" && ! -L "${targetPath}" ]]
}

commitGeneratedFile() {
    local tmpFile=$1
    local targetFile=$2
    local mode=${3:-}

    targetFile=$(padmResolveManagedAbsolutePath "${targetFile}") || return 1

    if [[ -n "${mode}" ]]; then
        chmod "${mode}" "${tmpFile}" || return 1
    fi
    padmCommitTargetIsFileLike "${targetFile}" || return 1
    mv -f -- "${tmpFile}" "${targetFile}" && padmForgetCleanupPath "${tmpFile}"
}

commitGeneratedJsonFile() {
    local tmpFile=$1
    local targetFile=$2
    local mode=${3:-644}

    jq empty "${tmpFile}" >/dev/null 2>&1 && commitGeneratedFile "${tmpFile}" "${targetFile}" "${mode}"
}

coreSetRollbackResultMessage() {
    local outputVar=$1
    local reason=$2
    local restoredMessage=$3
    local retryFn=${4:-}
    local retryFailureMessage=${5:-}
    local result

    if [[ -n "${retryFn}" ]]; then
        shift 5
        if "${retryFn}" "$@"; then
            result="${reason}，${restoredMessage}"
        else
            result="${reason}，${restoredMessage}；${retryFailureMessage}"
        fi
    else
        result="${reason}，${restoredMessage}"
    fi

    printf -v "${outputVar}" '%s' "${result}"
}

coreSetSingleRestoreResultMessage() {
    local outputVar=$1
    local reason=$2
    local restored=$3
    local restoredMessage=$4
    local failedLabel=$5
    local failedLocation=$6
    local result=

    if [[ "${restored}" == "true" ]]; then
        result="${reason}，${restoredMessage}"
        printf -v "${outputVar}" '%s' "${result}"
        return 0
    fi

    coreSetRestoreFailureDetail result "${failedLabel}" "${failedLocation}"
    result="${reason}，且${result}"
    printf -v "${outputVar}" '%s' "${result}"
    return 1
}

coreSetRestoreFailureDetail() {
    local outputVar=$1
    local failedLabel=$2
    local failedLocation=$3
    coreSetManualCheckMessage "${outputVar}" "${failedLabel}恢复失败" "${failedLocation}"
}

coreSetManualCheckMessage() {
    local outputVar=$1
    local reason=$2
    local checkTarget=$3
    local formatted="${reason}，请手动检查${checkTarget}"

    printf -v "${outputVar}" '%s' "${formatted}"
}

coreSelectionErrorCard() {
    local message=${1:-选择错误，请重新选择}
    errorCard "${message}"
}

coreSelectionRetryAction() {
    local actionHandler=$1
    shift
    coreSelectionErrorCard
    "${actionHandler}" "$@"
}

coreInvalidInputErrorCard() {
    errorCard "输入有误，请重新输入"
}

coreCancelledStatusCard() {
    statusCard "已取消" "$@"
}

coreRuleExistsStatusCard() {
    statusCard "规则已存在" "$@"
}

coreNotInstalledErrorCard() {
    errorCard "未安装，请使用脚本安装"
}

coreDomainRequiredErrorCard() {
    errorCard "域名不可为空"
}

coreIPRequiredErrorCard() {
    errorCard "IP不可为空"
}

corePortInputErrorCard() {
    errorCard "端口输入错误"
}

aloneNginxConfigRecoveredErrorCard() {
    errorCard "Nginx 配置检测失败，已恢复旧 alone.conf"
}

nginxStartFailureCard() {
    statusCard "Nginx 启动失败" "$@"
}

xrayConfigValidationFailureTitle() {
    printf '%s\n' "Xray 配置校验失败"
}

xrayConfigValidationFailureCard() {
    statusCard "$(xrayConfigValidationFailureTitle)" "$@"
}

coreSetDualRestoreResultMessage() {
    local outputVar=$1
    local reason=$2
    local firstRestored=$3
    local firstLabel=$4
    local firstLocation=$5
    local secondRestored=$6
    local secondLabel=$7
    local secondLocation=$8
    local result=

    if [[ "${firstRestored}" != "true" ]]; then
        coreSetRestoreFailureDetail result "${firstLabel}" "${firstLocation}"
        result="${reason}，且${result}"
        printf -v "${outputVar}" '%s' "${result}"
        return 1
    fi
    if [[ "${secondRestored}" != "true" ]]; then
        coreSetRestoreFailureDetail result "${secondLabel}" "${secondLocation}"
        result="${reason}，且${result}"
        printf -v "${outputVar}" '%s' "${result}"
        return 1
    fi

    printf -v "${outputVar}" '%s' ''
    return 0
}

coreSetPairedFileManualCheckMessage() {
    local outputVar=$1
    local reason=$2
    local targetPath=$3
    local backupPath=$4
    coreSetManualCheckMessage "${outputVar}" "${reason}" " ${targetPath} 和 ${backupPath}"
}

coreSetPairedFileRestoreFailureMessage() {
    local outputVar=$1
    local reason=$2
    local failedLabel=$3
    local targetPath=$4
    local backupPath=$5
    coreSetPairedFileManualCheckMessage "${outputVar}" "${reason}，${failedLabel}恢复失败" "${targetPath}" "${backupPath}"
}

coreSetRollbackFailureMessage() {
    local outputVar=$1
    local reason=$2
    local backupDir=$3
    local separator=${4-，且}
    local result=

    if [[ -n "${separator}" ]]; then
        coreSetManualCheckMessage result "${reason}${separator}回滚失败" "备份目录: ${backupDir}"
    else
        coreSetManualCheckMessage result "${reason}" "备份目录: ${backupDir}"
    fi

    printf -v "${outputVar}" '%s' "${result}"
}

coreSetNewConfigCleanupFailureMessage() {
    local outputVar=$1
    local reason=$2
    local targetPath=$3
    coreSetManualCheckMessage "${outputVar}" "${reason}，且新配置清理失败" " ${targetPath}"
}

restoreManagedFileFromBackup() {
    local backupFile=$1
    local targetFile=$2
    local mode=${3:-644}
    local restoreStage

    [[ -f "${backupFile}" ]] || return 1
    padmCreateTempFileForTarget restoreStage "${targetFile}" restore || return 1
    if ! cp -p "${backupFile}" "${restoreStage}"; then
        padmRemoveCleanupPath "${restoreStage}"
        return 1
    fi
    commitGeneratedFile "${restoreStage}" "${targetFile}" "${mode}" || { padmRemoveCleanupPath "${restoreStage}"; return 1; }
}

backupManagedFileToPath() {
    local sourceFile=$1
    local backupFile=$2
    local mode=${3:-644}
    local backupStage

    sourceFile=$(padmRequireSafeAbsolutePath "${sourceFile}") || return 1
    [[ -f "${sourceFile}" ]] || return 1
    padmCreateTempFileForTarget backupStage "${backupFile}" backup || return 1
    if ! cp -p "${sourceFile}" "${backupStage}"; then
        padmRemoveCleanupPath "${backupStage}"
        return 1
    fi
    commitGeneratedFile "${backupStage}" "${backupFile}" "${mode}" || { padmRemoveCleanupPath "${backupStage}"; return 1; }
}

padmWriteManagedFileBackupManifest() {
    local backupDir=$1
    shift
    local manifest
    local backupPath
    local targetPath

    [[ $(($# % 2)) -eq 0 ]] || return 1
    backupDir=$(padmRequireSafeAbsolutePath "${backupDir}") || return 1
    padmEnsureSafeDirectory "${backupDir}" || return 1
    manifest="${backupDir}/manifest"
    : >"${manifest}" || return 1
    while [[ $# -gt 0 ]]; do
        backupPath=$(padmManagedPathWithinRoot "${backupDir}" "$1") || return 1
        targetPath=$(padmRequireSafeAbsolutePath "$2") || return 1
        shift 2
        [[ ! -e "${targetPath}" || -f "${targetPath}" || -L "${targetPath}" ]] || return 1
        if [[ -f "${targetPath}" ]]; then
            padmEnsureSafeDirectory "$(dirname -- "${backupPath}")" || return 1
            backupManagedFileToPath "${targetPath}" "${backupPath}" 644 || return 1
            printf '%s\t%s\tfile\n' "${backupPath}" "${targetPath}" >>"${manifest}" || return 1
        else
            printf -- '-\t%s\tmissing\n' "${targetPath}" >>"${manifest}" || return 1
        fi
    done
}

padmRestoreManagedFileBackupManifest() {
    local backupDir=$1
    local validateTargetFn=${2:-}
    local manifest
    local backupPath
    local targetPath
    local state
    local status=0

    backupDir=$(padmRequireSafeAbsolutePath "${backupDir}") || return 1
    manifest="${backupDir}/manifest"
    [[ -f "${manifest}" ]] || return 1
    while IFS=$'\t' read -r backupPath targetPath state; do
        if [[ -z "${state}" && "${targetPath}" == "missing" && -n "${backupPath}" ]]; then
            targetPath="${backupPath}"
            state=missing
            backupPath=
        fi
        [[ -n "${targetPath}" ]] || continue
        targetPath=$(padmRequireSafeAbsolutePath "${targetPath}") || return 1
        if [[ -n "${validateTargetFn}" ]]; then
            declare -F "${validateTargetFn}" >/dev/null 2>&1 || return 1
            "${validateTargetFn}" "${targetPath}" || return 1
        fi
        case "${state}" in
        file)
            backupPath=$(padmRequireSafeAbsolutePath "${backupPath}") || return 1
            backupPath=$(padmResolvePathWithinRoot "${backupDir}" "${backupPath}") || return 1
            restoreManagedFileFromBackup "${backupPath}" "${targetPath}" 644 || status=1
            ;;
        missing)
            removeManagedFileIfPresent "${targetPath}" || status=1
            ;;
        *)
            status=1
            ;;
        esac
    done <"${manifest}"
    return "${status}"
}

writeGeneratedJsonFile() {
    local targetFile=$1
    local tmpPrefix=$2
    local tmpFile

    padmEnsureSafeDirectory "$(dirname -- "${targetFile}")" || return 1
    padmCreateTempPath tmpFile "$(padmTmpFilePath "${tmpPrefix}.XXXXXX")" || return 1
    cat >"${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    commitGeneratedJsonFile "${tmpFile}" "${targetFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

padmCleanupTempPaths() {
    local status=$?
    local signal=${1:-}
    local index
    trap - EXIT INT TERM
    for ((index=${#PADM_CLEANUP_PATHS[@]} - 1; index >= 0; index--)); do
        [[ -n "${PADM_CLEANUP_PATHS[index]}" ]] || continue
        rm -rf -- "${PADM_CLEANUP_PATHS[index]}" >/dev/null 2>&1 || true
    done
    if [[ -n "${signal}" ]]; then
        case "${signal}" in
        INT) exit 130 ;;
        TERM) exit 143 ;;
        esac
    fi
    exit "${status}"
}

readUserCrontabContent() {
    local errorFile
    local currentCrontab
    local status

    padmCreateTempPath errorFile "$(padmTmpFilePath "padm-crontab-read.XXXXXX")" || return 1
    if currentCrontab=$(LC_ALL=C crontab -l 2>"${errorFile}"); then
        :
    else
        status=$?
        if grep -qiE "^no crontab for |^no crontab$|^crontab: can't open '[^']+': No such file or directory$" "${errorFile}"; then
            currentCrontab=
        else
            cat "${errorFile}" >&2
            padmRemoveCleanupPath "${errorFile}"
            return "${status}"
        fi
    fi
    padmRemoveCleanupPath "${errorFile}"
    printf '%s\n' "${currentCrontab}"
}

installUserCrontabContent() {
    local tmpFile

    padmCreateTempPath tmpFile "$(padmTmpFilePath "padm-crontab.XXXXXX")" || return 1
    printf '%s\n' "$1" | sed '/^$/d' >"${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    crontab "${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    padmRemoveCleanupPath "${tmpFile}"
}

parseInstallArgs() {
    local value
    local valueVar

    AUTO_INSTALL=
    AUTO_INSTALL_TYPE=
    AUTO_CORE=
    AUTO_PROTOCOLS=
    AUTO_DOMAIN=
    AUTO_PORT=
    AUTO_TLS_CA=
    AUTO_DNS_API=
    AUTO_DNS_API_TYPE=
    AUTO_DNS_API_WILDCARD=
    AUTO_CLOUDFLARE_API_TOKEN=${PADM_CLOUDFLARE_API_TOKEN:-${CLOUDFLARE_API_TOKEN:-${CF_Token:-}}}
    AUTO_CLOUDFLARE_ZONE_ID=${PADM_CLOUDFLARE_ZONE_ID:-${CF_Zone_ID:-}}
    AUTO_ALIYUN_API_KEY=
    AUTO_ALIYUN_API_SECRET=
    AUTO_REUSE_LAST=
    AUTO_CLEAN_ACME=
    AUTO_REALITY_DOMAIN=
    AUTO_REALITY_TARGET=
    AUTO_REALITY_SERVER_NAME=
    AUTO_ENTRY_HOST=
    AUTO_SUBSCRIBE_PORT=
    AUTO_INSTALL_NGINX=
    AUTO_UUID=
    AUTO_USER=

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --install-type)
            valueVar=AUTO_INSTALL_TYPE
            ;;
        --core)
            valueVar=AUTO_CORE
            ;;
        --protocols)
            valueVar=AUTO_PROTOCOLS
            ;;
        --list-protocols)
            protocolListProtocols
            exit 0
            ;;
        --list-capabilities)
            protocolListCapabilities
            exit 0
            ;;
        --show-risky-protocols)
            protocolShowRiskyProtocols
            exit 0
            ;;
        --domain)
            valueVar=AUTO_DOMAIN
            ;;
        --port)
            valueVar=AUTO_PORT
            ;;
        --tls-ca)
            valueVar=AUTO_TLS_CA
            ;;
        --dns-api)
            valueVar=AUTO_DNS_API
            ;;
        --dns-api-type)
            valueVar=AUTO_DNS_API_TYPE
            ;;
        --dns-api-wildcard)
            valueVar=AUTO_DNS_API_WILDCARD
            ;;
        --cloudflare-api-token)
            valueVar=AUTO_CLOUDFLARE_API_TOKEN
            ;;
        --cloudflare-zone-id)
            valueVar=AUTO_CLOUDFLARE_ZONE_ID
            ;;
        --aliyun-api-key)
            valueVar=AUTO_ALIYUN_API_KEY
            ;;
        --aliyun-api-secret)
            valueVar=AUTO_ALIYUN_API_SECRET
            ;;
        --reuse-last)
            valueVar=AUTO_REUSE_LAST
            ;;
        --clean-acme)
            valueVar=AUTO_CLEAN_ACME
            ;;
        --reality-domain)
            valueVar=AUTO_REALITY_DOMAIN
            ;;
        --reality-target)
            valueVar=AUTO_REALITY_TARGET
            ;;
        --reality-server-name)
            valueVar=AUTO_REALITY_SERVER_NAME
            ;;
        --entry-host)
            valueVar=AUTO_ENTRY_HOST
            ;;
        --subscribe-port)
            valueVar=AUTO_SUBSCRIBE_PORT
            ;;
        --install-nginx)
            valueVar=AUTO_INSTALL_NGINX
            ;;
        --uuid)
            valueVar=AUTO_UUID
            ;;
        --user)
            valueVar=AUTO_USER
            ;;
        --help)
            showInstallArgsHelp
            exit 0
            ;;
        *)
            shift
            continue
            ;;
        esac

        AUTO_INSTALL=true
        if [[ $# -ge 2 && "${2}" != --* ]]; then
            value=$2
            shift 2
        else
            value=
            shift
        fi
        printf -v "${valueVar}" '%s' "${value}"
        valueVar=
    done
}

validUuidValue() {
    [[ "${1:-}" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}

validAccountNameValue() {
    local value=${1:-}
    [[ -n "${value}" && "${value}" != "." && "${value}" != ".." && "${value}" =~ ^[A-Za-z0-9._~@+=:-]+$ ]]
}

validManualAccountNameValue() {
    validAccountNameValue "${1:-}" && [[ "$1" != sub_* ]]
}

autoInstallValidateRequiredInputs() {
    [[ "${AUTO_INSTALL:-}" == "true" ]] || return 0

    if [[ -n "${AUTO_UUID:-}" ]] && ! validUuidValue "${AUTO_UUID}"; then
        errorCard "--uuid 格式不合法"
        return 1
    fi

    if [[ -n "${AUTO_USER:-}" ]] && ! validManualAccountNameValue "${AUTO_USER}"; then
        if [[ "${AUTO_USER}" == sub_* ]]; then
            errorCard "--user 不能使用 sub_ 开头，该前缀由订阅同步保留"
        else
            errorCard "--user 格式不合法，仅支持英文、数字及 . _ ~ @ + = : -"
        fi
        return 1
    fi

    if [[ "$(normalizeYesNo "${AUTO_REALITY_DOMAIN:-}")" == "y" ]]; then
        local strictSelection=${AUTO_PROTOCOLS:-}
        case "${AUTO_INSTALL_TYPE:-}" in
        reality | reality-only | no-domain-reality | 3)
            [[ -n "${strictSelection}" ]] || strictSelection=1
            ;;
        esac
        if ! protocolSelectionSupportsStrictRealityDomain "${strictSelection}"; then
            errorCard "--reality-domain yes 仅支持单选 Reality Vision 协议 1"
            return 1
        fi
    fi

    [[ -n "${AUTO_PROTOCOLS:-}" ]] || return 0

    if protocolSelectionNeedsLocalCertificate "${AUTO_PROTOCOLS}" && [[ -z "${AUTO_DOMAIN:-}" ]]; then
        coreDomainRequiredErrorCard
        return 1
    fi
}

showInstallArgsHelp() {
    cat <<EOF
┌─ padm 非交互安装参数 ──────────────────────────────
│ 用法: bash install.sh [RenewTLS|UpdateGeo|SyncSubscriptionGroups|SubscriptionControl|InstallSubscription] [options]
├─ 新人三步走
│ 1. 推荐直连: bash install.sh --install-type custom --core xray --protocols 1 --entry-host node.example.com --reality-target www.ibm.com:443
│ 2. 推荐 XHTTP: bash install.sh --install-type custom --core xray --protocols 2 --entry-host cdn.example.com --reality-target www.ibm.com:443
│ 3. 安装后: 运行 padm -> 订阅与用户；可选本机单独使用、主控或被控
├─ 交互菜单路径
│ 安装与重装: 含新手选择指引，推荐直连/CDN/无域名 Reality、NaiveProxy、自定义安装、传统 TLS 兼容安装
│ 订阅与用户: 未启用拓扑时可直接管理本机，也可初始化主控或被控
│ 协议与入口: REALITY、XHTTP、Hysteria2、Tuic、入口端口和 CDN 入口
│ 站点与证书: 传统 TLS fallback 站点、302、ALPN 和证书
│ 路由与访问控制: 分流、BT、域名/IP 阻断、直连例外和区域阻断
│ 核心与服务: Xray/sing-box 版本管理、配置校验、服务控制和日志
│ 系统与脚本: 更新 padm、网络优化和宿主机辅助项
├─ 正式子命令
│ bash install.sh InstallSubscription --domain subscribe.example.com --subscribe-port 39778 --install-nginx yes
│ 独立确保订阅 TLS 证书与 HTTPS 发布；缺证书时可复用 --tls-ca / --dns-api 参数签发
├─ 关键概念
│ TLS 域名/端口: 普通 TLS 协议入口；当前不作为新人首选，传统 TLS 类协议存在更高识别风险
│ Reality entry: 客户端实际连接地址，通常是自有域名、CDN 入口或服务器 IP
│ Reality target: REALITY 伪装目标站，建议使用真实大型 HTTPS 站点，端口默认 443
│ Reality SNI: REALITY 握手 SNI，默认等于 target host
│ Reality 不申请本机 TLS 证书，也不因安装操作 Nginx；严格域名仅支持单选 Vision 1
├─ 常用示例
│ bash install.sh --install-type custom --core xray --protocols 1 --entry-host node.example.com --reality-target www.ibm.com:443 --reality-server-name www.ibm.com
│ bash install.sh --install-type custom --core xray --protocols 2 --entry-host cdn.example.com --reality-target www.ibm.com:443 --reality-server-name www.ibm.com
│ bash install.sh --install-type reality --core xray --reality-target www.ibm.com:443 --reuse-last no
├─ 参数
│ --install-type <install|custom|reality>  安装类型；无自动参数时进入交互菜单；有其它自动参数时默认 custom
│ --core <xray|sing-box|1|2>              安装核心
│ --protocols <ids>                       当前公开公网节点能力编号，例如 1,2,3；旧 0..13/20 已废弃
│ --list-protocols                        列出可安装公网节点能力
│ --list-capabilities                     列出公网节点、内部能力和上游已知能力
│ --show-risky-protocols                  列出带风险提示的高级公网节点能力
│ --domain <domain>                       TLS 域名；InstallSubscription 中专指订阅 HTTPS 域名
│ --port <port>                           TLS 入口端口；单选 Reality 为客户端连接端口，默认 443
│ --tls-ca <letsencrypt|zerossl|buypass>  证书 CA，默认 letsencrypt
│ --dns-api <yes|no|y|n>                  是否使用 DNS API 申请证书
│ --dns-api-type <cloudflare|aliyun|1|2>   DNS API 服务商，默认 cloudflare
│ --dns-api-wildcard <yes|no|y|n>          DNS API 是否申请 *.根域名 通配符证书
│ --cloudflare-api-token <token>           Cloudflare API Token，也可用 PADM_CLOUDFLARE_API_TOKEN
│ --cloudflare-zone-id <zone_id>           可选，也可用 PADM_CLOUDFLARE_ZONE_ID
│ --aliyun-api-key <key>                   阿里云 DNS AccessKey ID，也可用 PADM_ALIYUN_API_KEY
│ --aliyun-api-secret <secret>             阿里云 DNS AccessKey Secret，也可用 PADM_ALIYUN_API_SECRET
│ --reuse-last <yes|no|y|n>               是否复用上次安装配置
│ --clean-acme <yes|no|y|n>               清空上次配置时是否清理 acme
│ --reality-domain <yes|no|y|n>           严格域名模式，仅支持单选 Reality Vision 1
│ --reality-target <host[:port]>          REALITY 伪装目标站，默认推荐 www.ibm.com:443
│ --reality-server-name <sni>             REALITY SNI，默认等于 target host
│ --entry-host <host>                     Reality entry；优先于 --domain、历史 entry、currentHost 和公网 IP
│ --subscribe-port <port>                 订阅服务端口
│ --install-nginx <yes|no|y|n>            订阅需要 nginx 时是否自动安装
│ --uuid <uuid>                           初始用户 UUID，默认随机生成
│ --user <name>                           初始用户名，默认随机生成
└──────────────────────────────────────────────────
EOF
}

normalizeYesNo() {
    case "$1" in
    y | Y | yes | YES | Yes | true | TRUE | True | 1)
        printf 'y'
        ;;
    n | N | no | NO | No | false | FALSE | False | 0)
        printf 'n'
        ;;
    *)
        printf 'n'
        ;;
    esac
}

autoConfirm() {
    local key=$1
    local prompt=$2
    local defaultValue=${3:-n}
    local resultVar=$4
    local input=
    local suffix='[y/N]：'

    [[ "$(normalizeYesNo "${defaultValue}")" == "y" ]] && suffix='[Y/n]：'
    autoRead "${key}" "${prompt}${suffix}" input
    if [[ -z "${input}" ]]; then
        input=${defaultValue}
    fi
    printf -v "${resultVar}" '%s' "$(normalizeYesNo "${input}")"
}

autoValueForKey() {
    case "$1" in
    main_menu)
        printf '1'
        ;;
    install_type)
        case "${AUTO_INSTALL_TYPE}" in
        custom | any | 任意组合 | 2 | install | full | traditional | 1)
            printf '5'
            ;;
        reality | reality-only | no-domain-reality | 3)
            printf '3'
            ;;
        *)
            printf '4'
            ;;
        esac
        ;;
    core)
        case "${AUTO_CORE}" in
        sing-box | singbox | 2)
            printf '2'
            ;;
        *)
            printf '1'
            ;;
        esac
        ;;
    protocols)
        printf '%s' "${AUTO_PROTOCOLS}"
        ;;
    core_init_uuid)
        if [[ -z "${AUTO_UUID:-}" ]]; then
            AUTO_UUID=$(generateRandomUuidValue) || return 1
        fi
        printf '%s' "${AUTO_UUID}"
        ;;
    core_init_username)
        if [[ -z "${AUTO_USER:-}" ]]; then
            [[ -n "${AUTO_UUID:-}" ]] || AUTO_UUID=$(generateRandomUuidValue) || return 1
            AUTO_USER=$(defaultRandomUserNameFromUuid "${AUTO_UUID}") || return 1
        fi
        printf '%s' "${AUTO_USER}"
        ;;
    domain)
        printf '%s' "${AUTO_DOMAIN}"
        ;;
    port | singbox_custom_port | reality_port | xhttp_port)
        printf '%s' "${AUTO_PORT}"
        ;;
    tls_ca)
        case "${AUTO_TLS_CA}" in
        zerossl | ZeroSSL | 2)
            printf '2'
            ;;
        buypass | Buypass | 3)
            printf '3'
            ;;
        *)
            printf '1'
            ;;
        esac
        ;;
    dns_api)
        normalizeYesNo "${AUTO_DNS_API}"
        ;;
    dns_api_type)
        case "${AUTO_DNS_API_TYPE}" in
        aliyun | Aliyun | alibaba | 2)
            printf '2'
            ;;
        *)
            printf '1'
            ;;
        esac
        ;;
    dns_api_wildcard)
        normalizeYesNo "${AUTO_DNS_API_WILDCARD}"
        ;;
    singbox_reinstall | xray_reinstall)
        printf 'y'
        ;;
    core_download_retry)
        printf 'y'
        ;;
    nginx_grpc_reinstall)
        printf 'y'
        ;;
    cloudflare_api_token)
        printf '%s' "${AUTO_CLOUDFLARE_API_TOKEN:-${PADM_CLOUDFLARE_API_TOKEN:-}}"
        ;;
    cloudflare_zone_id)
        printf '%s' "${AUTO_CLOUDFLARE_ZONE_ID:-${PADM_CLOUDFLARE_ZONE_ID:-}}"
        ;;
    aliyun_api_key)
        printf '%s' "${AUTO_ALIYUN_API_KEY:-${PADM_ALIYUN_API_KEY:-}}"
        ;;
    aliyun_api_secret)
        printf '%s' "${AUTO_ALIYUN_API_SECRET:-${PADM_ALIYUN_API_SECRET:-}}"
        ;;
    reuse_last)
        normalizeYesNo "${AUTO_REUSE_LAST}"
        ;;
    clean_acme)
        normalizeYesNo "${AUTO_CLEAN_ACME}"
        ;;
    reality_domain)
        if [[ "$(normalizeYesNo "${AUTO_REALITY_DOMAIN}")" == "y" ]]; then
            printf '2'
        else
            printf '1'
        fi
        ;;
    reality_target)
        printf '%s' "${AUTO_REALITY_TARGET}"
        ;;
    reality_server_name)
        printf '%s' "${AUTO_REALITY_SERVER_NAME}"
        ;;
    entry_host)
        printf '%s' "${AUTO_ENTRY_HOST}"
        ;;
    subscribe_port)
        printf '%s' "${AUTO_SUBSCRIBE_PORT}"
        ;;
    reality_stream_enable)
        normalizeYesNo "${AUTO_REALITY_STREAM_ENABLE}"
        ;;
    reality_stream_domains)
        printf '%s' "${AUTO_REALITY_STREAM_DOMAINS}"
        ;;
    reality_stream_default_protocol)
        printf '%s' "${AUTO_REALITY_STREAM_DEFAULT_PROTOCOL}"
        ;;
    reality_stream_website_port)
        printf '%s' "${AUTO_REALITY_STREAM_WEBSITE_PORT}"
        ;;
    reality_stream_vision_port)
        printf '%s' "${AUTO_REALITY_STREAM_VISION_PORT}"
        ;;
    reality_stream_xhttp_port)
        printf '%s' "${AUTO_REALITY_STREAM_XHTTP_PORT}"
        ;;
    install_nginx)
        normalizeYesNo "${AUTO_INSTALL_NGINX}"
        ;;
    esac
}

generateRandomUuidValue() {
    local uuid=
    local hex=
    local variant
    if command -v uuidgen >/dev/null 2>&1; then
        uuid=$(uuidgen 2>/dev/null || true)
    fi
    if ! validUuidValue "${uuid}" && [[ -r /dev/urandom ]] && command -v od >/dev/null 2>&1; then
        hex=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n') || hex=
        if [[ "${hex}" =~ ^[0-9A-Fa-f]{32}$ ]]; then
            variant=$(((16#${hex:16:1} & 3) | 8))
            printf -v uuid '%s-%s-4%s-%x%s-%s' "${hex:0:8}" "${hex:8:4}" "${hex:13:3}" "${variant}" "${hex:17:3}" "${hex:20:12}"
        fi
    fi
    if ! validUuidValue "${uuid}" && [[ -r /proc/sys/kernel/random/uuid ]]; then
        uuid=$(</proc/sys/kernel/random/uuid)
    fi
    uuid=${uuid,,}
    validUuidValue "${uuid}" || return 1
    printf '%s\n' "${uuid}"
}

defaultRandomUserNameFromUuid() {
    local uuid=${1:-}
    local prefix
    if [[ -z "${uuid}" ]]; then
        uuid=$(generateRandomUuidValue) || return 1
    fi
    prefix=${uuid%%-*}
    prefix=${prefix,,}
    printf 'padm-%s\n' "${prefix}"
}

autoReadAllowsEmptyValue() {
    case "$1" in
    port | singbox_custom_port | reality_port | xhttp_port | hysteria_port | tuic_port | reality_target | reality_server_name | entry_host | subscribe_port | cloudflare_zone_id | reality_stream_website_port | reality_stream_vision_port | reality_stream_xhttp_port | hysteria_download_speed | hysteria_upload_speed)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}

autoInstallSummaryValue() {
    case "$1" in
    cloudflare_api_token | cloudflare_zone_id | aliyun_api_key | aliyun_api_secret)
        if [[ -n "$2" ]]; then
            printf '********'
        else
            printf '未设置'
        fi
        ;;
    *)
        printf '%s' "${2:-未设置}"
        ;;
    esac
}

showAutoInstallSummary() {
    [[ -n "${AUTO_INSTALL}" ]] || return 0
    [[ -z "${AUTO_INSTALL_SUMMARY_SHOWN:-}" ]] || return 0
    AUTO_INSTALL_SUMMARY_SHOWN=true

    statusCard "自动安装摘要" \
        "安装类型：$(autoInstallSummaryValue install_type "${AUTO_INSTALL_TYPE:-custom}")" \
        "核心：$(autoInstallSummaryValue core "${AUTO_CORE:-xray}")" \
        "协议：$(autoInstallSummaryValue protocols "${AUTO_PROTOCOLS:-默认推荐}")" \
        "UUID：$(autoInstallSummaryValue uuid "${AUTO_UUID:-随机生成}")" \
        "用户名：$(autoInstallSummaryValue user "${AUTO_USER:-随机生成}")" \
        "TLS 域名：$(autoInstallSummaryValue domain "${AUTO_DOMAIN:-未设置}")" \
        "入口地址：$(autoInstallSummaryValue entry_host "${AUTO_ENTRY_HOST:-自动推导}")" \
        "REALITY target：$(autoInstallSummaryValue reality_target "${AUTO_REALITY_TARGET:-默认推荐}")" \
        "订阅端口：$(autoInstallSummaryValue subscribe_port "${AUTO_SUBSCRIBE_PORT:-按安装流程选择}")"
}

formatReadPrompt() {
    case "$1" in
    "请选择:")
        printf '请选择编号：'
        ;;
    "请输入:")
        printf '请输入：'
        ;;
    *)
        printf '%s' "$1"
        ;;
    esac
}

autoRead() {
    local key=$1
    local prompt=$2
    local resultVar=$3
    local autoValue=

    prompt=$(formatReadPrompt "${prompt}")

    if [[ -n "${AUTO_INSTALL:-}" && ( "${key}" != "install_type" || -n "${AUTO_INSTALL_TYPE:-}" ) ]]; then
        autoValue=$(autoValueForKey "${key}") || return 1
        if [[ -n "${autoValue}" ]]; then
            showAutoInstallSummary
            printf -v "${resultVar}" '%s' "${autoValue}"
            return
        elif autoReadAllowsEmptyValue "${key}"; then
            printf -v "${resultVar}" '%s' ""
            return
        else
            printf -v "${resultVar}" '%s' ""
            return
        fi
    fi

    read -r -p "${prompt}" "${resultVar}"
}

argumentHasValue() {
    [[ $# -ge 2 && -n "${2}" && "${2}" != -* ]]
}

downloadFileOptionHasValue() {
    [[ $# -ge 3 && -n "${2}" && "${2}" != -* ]]
}

downloadUrlToFileBounded() {
    local url=$1
    local targetFile=$2
    local maxSize=$3
    local maxTime=${4:-30}
    local -a pipelineStatus=()
    [[ -n "${url}" && "${maxSize}" =~ ^[0-9]+$ && "${maxSize}" -gt 0 ]] || return 1
    [[ "${maxTime}" =~ ^[0-9]+$ && "${maxTime}" -gt 0 ]] || return 1

    : >"${targetFile}" || return 1
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL --connect-timeout 10 --max-time "${maxTime}" --max-filesize "${maxSize}" --retry 1 --retry-delay 1 -o "${targetFile}" "${url}" &&
            [[ "$(wc -c <"${targetFile}")" -le "${maxSize}" ]]; then
            return 0
        fi
    fi

    : >"${targetFile}" || return 1
    if command -v wget >/dev/null 2>&1; then
        wget -T 30 -t 2 -qO- "${url}" | head -c "$((maxSize + 1))" >"${targetFile}"
        pipelineStatus=("${PIPESTATUS[@]}")
        if [[ "${pipelineStatus[0]:-1}" -eq 0 && "${pipelineStatus[1]:-1}" -eq 0 &&
            "$(wc -c <"${targetFile}")" -le "${maxSize}" ]]; then
            return 0
        fi
    fi
    return 1
}

downloadFile() {
    local outputDir=
    local outputFile=
    local url=
    local outputParent=
    local outputName=
    local tmpFile=

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -P)
            if downloadFileOptionHasValue "$@"; then
                outputDir=$2
                shift 2
            else
                shift
            fi
            ;;
        -O)
            if downloadFileOptionHasValue "$@"; then
                outputFile=$2
                shift 2
            else
                shift
            fi
            ;;
        *)
            url=$1
            shift
            ;;
        esac
    done

    [[ -n "${url}" ]] || return 1
    if [[ -n "${outputDir}" ]]; then
        outputName=$(basename -- "${url%%[?#]*}")
        [[ -n "${outputName}" && "${outputName}" != "." && "${outputName}" != ".." ]] || return 1
        outputFile="${outputDir%/}/${outputName}"
    elif [[ -z "${outputFile}" ]]; then
        outputFile=$(basename -- "${url%%[?#]*}")
        [[ -n "${outputFile}" && "${outputFile}" != "." && "${outputFile}" != ".." ]] || return 1
    fi

    outputParent=$(dirname -- "${outputFile}")
    outputName=$(basename -- "${outputFile}")
    padmCreateTempPath tmpFile "${outputParent}/.${outputName}.download.XXXXXX" || return 1
    if ! downloadUrlToFileBounded "${url}" "${tmpFile}" 52428800 120 || [[ ! -s "${tmpFile}" ]]; then
        padmRemoveCleanupPath "${tmpFile}"
        return 1
    fi
    if ! mv -f -- "${tmpFile}" "${outputFile}"; then
        padmRemoveCleanupPath "${tmpFile}"
        return 1
    fi
    padmForgetCleanupPath "${tmpFile}"
}

fetchUrlToStdout() {
    local url=$1
    local maxAttempts=${2:-3}
    local attempt=1
    local tmpFile

    padmCreateTmpRootPath tmpFile padm-fetch-url.XXXXXX || return 1

    while [[ ${attempt} -le ${maxAttempts} ]]; do
        if downloadUrlToFileBounded "${url}" "${tmpFile}" 5242880; then
            cat "${tmpFile}"
            padmRemoveCleanupPath "${tmpFile}"
            return 0
        fi
        if [[ ${attempt} -lt ${maxAttempts} ]]; then
            sleep 1
        fi
        attempt=$((attempt + 1))
    done
    padmRemoveCleanupPath "${tmpFile}"
    return 1
}

resolveGitHubCommitRef() {
    local repo=$1
    local ref=$2
    local metadata
    local commitRef

    [[ "${repo}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
    [[ "${ref}" =~ ^[A-Za-z0-9._/-]+$ && "${ref}" != */../* && "${ref}" != ../* && "${ref}" != */.. ]] || return 1
    metadata=$(fetchUrlToStdout "https://api.github.com/repos/${repo}/commits/${ref}" 3) || return 1
    commitRef=$(awk -F'"' '/^[[:space:]]*"sha":[[:space:]]*"/ { print $4; exit }' <<<"${metadata}") || return 1
    [[ "${commitRef}" =~ ^[0-9a-f]{40}$ ]] || return 1
    printf '%s\n' "${commitRef}"
}

validateGitHubReleaseTag() {
    [[ "$1" =~ ^[A-Za-z0-9._+-]{1,128}$ ]]
}

githubReleaseAssetPinnedDigest() {
    case "$1:$2:$3" in
    badafans/warp-reg:v1.0:main-linux-amd64)
        printf '%s\n' 'sha256:95e97d92bda8f343e0ba0b7a7402c5947fb4204fdb0d368fd53dbddb664de895'
        ;;
    badafans/warp-reg:v1.0:main-linux-arm64)
        printf '%s\n' 'sha256:eb7a29853466f805755caddcebeedfbfb36cccd73a4eb950a1eb82915fa17f9b'
        ;;
    *) return 1 ;;
    esac
}

downloadGitHubReleaseAsset() {
    local outputDir=
    local repo=
    local version=
    local assetName=
    local metadata=
    local downloadUrl=
    local digest=
    local outputPath=
    local expectedSha256=
    local actualSha256=
    local expectedSize=
    local actualSize=
    local releaseMetadataUrl=

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -P)
            if argumentHasValue "$@"; then
                outputDir=$2
                shift 2
            else
                shift
            fi
            ;;
        *)
            if [[ -z "${repo}" ]]; then
                repo=$1
            elif [[ -z "${version}" ]]; then
                version=$1
            else
                assetName=$1
            fi
            shift
            ;;
        esac
    done

    if [[ -z "${outputDir}" || -z "${repo}" || -z "${version}" || -z "${assetName}" ||
        ! "${repo}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
        echoContent title "\n┌─ GitHub Release 下载 ──────────────────────────────"
        menuLine "下载参数不完整"
        menuClose
        return 1
    fi
    if ! validateGitHubReleaseTag "${version}"; then
        echoContent title "\n┌─ GitHub Release 下载 ──────────────────────────────"
        menuLine "Release 版本格式异常: ${version}"
        menuClose
        return 1
    fi
    if [[ "${assetName}" == *"/"* || "${assetName}" == *".."* ]]; then
        echoContent title "\n┌─ GitHub Release 下载 ──────────────────────────────"
        menuLine "Release 资产名称异常: ${assetName}"
        menuClose
        return 1
    fi

    mkdir -p "${outputDir}"
    if [[ "${version}" == "latest" ]]; then
        releaseMetadataUrl="https://api.github.com/repos/${repo}/releases/latest"
    else
        releaseMetadataUrl="https://api.github.com/repos/${repo}/releases/tags/${version}"
    fi
    local releaseMetadata
    releaseMetadata=$(fetchUrlToStdout "${releaseMetadataUrl}" 3) || releaseMetadata=
    if [[ -n "${releaseMetadata}" ]]; then
        metadata=$(jq -ce --arg name "${assetName}" 'first(.assets[]? | select(.name == $name) | {url:.browser_download_url, digest:(.digest // ""), size:(.size // 0)})' <<<"${releaseMetadata}" 2>/dev/null) || metadata=
    fi
    if [[ -n "${metadata}" ]]; then
        downloadUrl=$(jq -r '.url // empty' <<<"${metadata}" 2>/dev/null)
        digest=$(jq -r '.digest // empty' <<<"${metadata}" 2>/dev/null)
        expectedSize=$(jq -r '.size // 0' <<<"${metadata}" 2>/dev/null)
    fi
    if [[ -z "${metadata}" ]]; then
        echoContent title "\n┌─ GitHub Release 下载 ──────────────────────────────"
        menuLine "Release 元数据不可用或未找到资产，已取消下载: ${assetName}"
        menuClose
        return 1
    fi
    if [[ -z "${downloadUrl}" ]]; then
        echoContent title "\n┌─ GitHub Release 下载 ──────────────────────────────"
        menuLine "Release 资产 URL 缺失，已取消下载: ${assetName}"
        menuClose
        return 1
    fi
    if [[ "${downloadUrl}" != "https://github.com/${repo}/releases/download/"*"/${assetName}" ||
        ! "${expectedSize}" =~ ^[0-9]+$ || "${expectedSize}" -le 0 || "${expectedSize}" -gt 52428800 ]]; then
        echoContent title "\n┌─ GitHub Release 下载 ─────────────────────────────"
        menuLine "Release 资产 URL 或大小异常，已取消下载: ${assetName}"
        menuClose
        return 1
    fi
    if [[ "${digest}" != sha256:* ]]; then
        digest=$(githubReleaseAssetPinnedDigest "${repo}" "${version}" "${assetName}" 2>/dev/null || true)
    fi
    if [[ "${digest}" != sha256:* ]]; then
        echoContent title "\n┌─ GitHub Release 校验 ──────────────────────────────"
        menuLine "GitHub 未提供 sha256 digest，已取消下载: ${assetName}"
        menuClose
        return 1
    fi
    outputPath="${outputDir%/}/${assetName}"
    if ! downloadFile -P "${outputDir}" "${downloadUrl}"; then
        return 1
    fi
    if [[ -f "${outputPath}" ]]; then
        actualSize=$(wc -c <"${outputPath}")
    else
        actualSize=0
    fi
    if [[ ! -f "${outputPath}" || "${actualSize}" -ne "${expectedSize}" ]]; then
        echoContent title "\n┌─ GitHub Release 下载 ──────────────────────────────"
        menuLine "下载文件大小与 Release 元数据不一致，已取消下载: ${assetName}"
        menuClose
        rm -f -- "${outputPath}"
        return 1
    fi
    if ! command -v sha256sum >/dev/null 2>&1; then
        echoContent title "\n┌─ GitHub Release 校验 ──────────────────────────────"
        menuLine "缺少 sha256sum，无法校验下载文件"
        menuClose
        rm -f -- "${outputPath}"
        return 1
    fi
    expectedSha256=${digest#sha256:}
    actualSha256=$(sha256sum "${outputPath}" | awk '{print $1}')
    if [[ "${actualSha256}" != "${expectedSha256}" ]]; then
        echoContent title "\n┌─ GitHub Release 校验 ──────────────────────────────"
        menuLine "下载文件 sha256 校验失败: ${assetName}"
        menuClose
        rm -f "${outputPath}"
        return 1
    fi
    echoContent title "\n┌─ GitHub Release 校验 ──────────────────────────────"
    menuLine "sha256 校验通过: ${assetName}"
    menuClose
}

# 初始化安装目录
mkdirTools() {
    local dir status=0
    local privateDirs=(
        /etc/padm/subscribe_local
        /etc/padm/subscribe_local/default
        /etc/padm/subscribe_local/clashMeta
        /etc/padm/subscribe_local/sing-box
        /etc/padm/xray/conf
        /etc/padm/sing-box/conf
    )
    local dirs=(
        /etc/padm/tls
        /etc/padm/subscribe_local/default
        /etc/padm/subscribe_local/clashMeta
        /etc/padm/subscribe_remote/default
        /etc/padm/subscribe_remote/clashMeta
        /etc/padm/subscribe/default
        /etc/padm/subscribe/clashMetaProfiles
        /etc/padm/subscribe/clashMeta
        /etc/padm/subscribe/sing-box
        /etc/padm/subscribe/sing-box_profiles
        /etc/padm/subscribe_local/sing-box
        /etc/padm/xray/conf
        /etc/padm/xray/reality_scan
        /etc/padm/xray/tmp
        /etc/systemd/system/
        "$(padmTmpFilePath padm-tls)"
        /etc/padm/warp
        /etc/padm/sing-box/conf/config
        /usr/share/nginx/html/
    )
    for dir in "${dirs[@]}"; do
        mkdir -p "${dir}" || status=1
    done
    if [[ "${status}" -eq 0 ]]; then
        chmod 700 "${privateDirs[@]}" || status=1
    fi
    return "${status}"
}

# 检查 root 权限
checkRoot() {
    if [ "$(id -u)" -ne 0 ]; then
        echoContent red "\n请使用 Root 用户执行脚本"
        exit 1
    fi
    local configDir
    for configDir in /etc/padm/xray/conf /etc/padm/sing-box/conf; do
        [[ ! -e "${configDir}" ]] || chmod 700 "${configDir}" || {
            errorCard "核心配置目录权限收紧失败" "${configDir}"
            exit 1
        }
    done
}

# 安全执行命令并限制超时
runWithTimeout() {
    local timeoutSeconds=$1
    shift
    local commandString="$*"
    local maxAttempts=1
    local attempt=1
    local status=0

    if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]] && [[ "${commandString}" =~ (apt-get|dpkg) ]]; then
        maxAttempts=3
    fi

    while [[ ${attempt} -le ${maxAttempts} ]]; do
        if [[ ${maxAttempts} -gt 1 ]]; then
            waitAptProcess
        fi

        if command -v timeout >/dev/null 2>&1; then
            timeout "${timeoutSeconds}s" bash -lc "${commandString}"
            status=$?
        else
            bash -lc "${commandString}"
            status=$?
        fi

        if [[ ${status} -eq 0 ]]; then
            return 0
        fi

        if [[ ${attempt} -lt ${maxAttempts} ]]; then
            echoContent title "\n┌─ 软件包命令重试 ───────────────────────────────────"
            menuLine "软件包命令执行失败，等待后重试 (${attempt}/${maxAttempts})"
            menuClose
            sleep 5
        fi
        attempt=$((attempt + 1))
    done

    return ${status}
}

# 等待 apt/dpkg 进程结束
waitAptProcess() {
    if [[ "${release}" != "ubuntu" && "${release}" != "debian" ]]; then
        return
    fi

    local waitCount=0
    local lockFiles=(/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock)
    while true; do
        local lockPids=
        lockPids=$(lsof -t "${lockFiles[@]}" 2>/dev/null | sort -u | tr '\n' ' ')
        if [[ -z "${lockPids// }" ]]; then
            return
        fi

        if [[ ${waitCount} -ge 36 ]]; then
            echoContent title "\n┌─ apt/dpkg 锁占用 ─────────────────────────────────"
            menuLine "检测到 apt/dpkg 锁仍在占用，请等待系统软件包任务结束后重新执行脚本"
            menuLine "占用锁的进程: ${lockPids}"
            menuClose
            exit 1
        fi

        if [[ ${waitCount} == 0 ]]; then
            echoContent title "\n┌─ apt/dpkg 锁等待 ─────────────────────────────────"
            menuLine "检测到 apt/dpkg 锁正在占用，等待其结束"
            menuClose
        fi

        sleep 5
        waitCount=$((waitCount + 1))
    done
}

padmIsSafeAbsolutePath() {
    local targetPath=$1
    if [[ -z "${targetPath}" || "${targetPath}" != /* || "${targetPath}" == "/" ||
        "${targetPath}" == "/." || "${targetPath}" == "/.." ||
        "${targetPath}" == */./* || "${targetPath}" == */. ||
        "${targetPath}" == */../* || "${targetPath}" == */.. ]]; then
        return 1
    fi
}

padmShowUnsafePathError() {
    local title=$1
    echoContent title "\n┌─ ${title} ─────────────────────────────────────────"
    menuLine "目标路径异常，已终止"
    menuClose
}

padmEnsureSafeDirectory() {
    local targetPath=$1
    local parentPath targetName
    targetPath=$(padmResolveManagedAbsolutePath "${targetPath}") || return 1
    if [[ -e "${targetPath}" ]]; then
        [[ -d "${targetPath}" ]] || return 1
        return 0
    fi
    parentPath=$(dirname -- "${targetPath}")
    targetName=$(basename -- "${targetPath}")
    if [[ ! -d "${parentPath}" && "${parentPath}" != "/" ]]; then
        padmEnsureSafeDirectory "${parentPath}" || return 1
    fi
    (cd -- "${parentPath}" && mkdir -p -- "${targetName}") >/dev/null 2>&1 || return 1
}

# 安全清理目录内容
cleanDirectoryContent() {
    local targetPath=$1
    local resolvedPath
    local childPath
    if ! padmIsSafeAbsolutePath "${targetPath}"; then
        padmShowUnsafePathError "清理目录"
        return 1
    fi
    if [[ -e "${targetPath}" ]]; then
        [[ -d "${targetPath}" ]] || return 1
    else
        mkdir -p "${targetPath}" || return 1
    fi
    resolvedPath=$(cd -- "${targetPath}" && pwd -P) || return 1
    if [[ -z "${resolvedPath}" || "${resolvedPath}" == "/" ]]; then
        padmShowUnsafePathError "清理目录"
        return 1
    fi
    while IFS= read -r childPath; do
        [[ -n "${childPath}" ]] || continue
        removeManagedPathWithinRootIfPresent "${resolvedPath}" "${childPath}" || return 1
    done < <(find "${resolvedPath}" -mindepth 1 -maxdepth 1 -print)
}


# 检查版本号
checkVersionNotEmpty() {
    if [[ -z "$1" || "$1" == "null" ]]; then
        echoContent title "\n┌─ 版本获取 ─────────────────────────────────────────"
        menuLine "获取版本失败，请稍后重试"
        menuClose
        exit 1
    fi
}


# 初始化随机字符串
initRandomPath() {
    local chars="abcdefghijklmnopqrtuxyz"
    local initCustomPath=
    for i in {1..4}; do
        echo "${i}" >/dev/null
        initCustomPath+="${chars:RANDOM%${#chars}:1}"
    done
    customPath=${initCustomPath}
}


# 生成随机数
randomNum() {
    if [[ "${release}" == "alpine" ]]; then
        local ranNum=
        ranNum="$(shuf -i "$1"-"$2" -n 1)"
        echo "${ranNum}"
    else
        echo $((RANDOM % ($2 - $1 + 1) + $1))
    fi
}
