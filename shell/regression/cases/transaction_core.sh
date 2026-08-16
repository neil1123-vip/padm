#!/usr/bin/env bash

if ! declare -F regressionProtocolSelectionIncludesCompat >/dev/null 2>&1; then
    regressionProtocolSelectionIncludesCompat() {
        local selection=$1
        local protocolId=$2
        local mode=${3:-}

        [[ "${mode}" == "all" ]] && return 0
        if [[ "${protocolId}" == "11" ]] && [[ ",${selection}," == *",23,"* ]]; then
            return 0
        fi
        protocolSelectionHasAny "${selection}" "${protocolId}"
    }
fi

runCoreReleaseArchiveRejectsRegression() (
    local mode=$1
    local root="${TMP_DIR}/core-release-archive-${mode}"
    local tmpDir="${root}/tmp"
    local xrayRc singBoxRc
    local xrayListing singBoxListing singBoxLongListing singBoxExtract

    rm -rf "${root}"
    mkdir -p "${tmpDir}"
    xrayCoreCPUVendor=Xray-linux-64
    singBoxCoreCPUVendor=-linux-amd64
    if [[ "${mode}" == "symlink-payload" ]]; then
        xrayListing=xray
        singBoxListing=$'sing-box-1.2.3-linux-amd64/\nsing-box-1.2.3-linux-amd64/sing-box\nsing-box-1.2.3-linux-amd64/libcronet.so'
        singBoxLongListing=$'drwxr-xr-x root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/\n-rwxr-xr-x root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/sing-box\nlrwxrwxrwx root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/libcronet.so -> /tmp/libcronet.so'
        singBoxExtract=$'sing-box\ncronet'
    else
        xrayListing=../xray
        singBoxListing=../sing-box
        singBoxLongListing='-rw-r--r-- root/root 0 2026-01-01 00:00 ../sing-box'
        singBoxExtract=sing-box
    fi
    downloadGitHubReleaseAsset() {
        local outputDir= assetName=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -P) outputDir=$2; shift 2 ;;
            *) assetName=$1; shift ;;
            esac
        done
        mkdir -p "${outputDir}"
        : >"${outputDir}/${assetName}"
    }
    unzip() {
        if [[ "${1:-}" == "-Z1" ]]; then
            printf '%s\n' "${xrayListing}"
            return 0
        fi
        if [[ "${mode}" == "symlink-payload" && "${1:-}" == "-Z" && "${2:-}" == "-l" ]]; then
            printf '%s\n' 'lrwxrwxrwx  3.0 unx 0 b- 0% 2026-01-01 00:00 xray'
            return 0
        fi
        if [[ "${1:-}" == "-p" ]]; then
            printf 'xray\n'
            return 0
        fi
        local dest=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -d) dest=$2; shift 2 ;;
            *) shift ;;
            esac
        done
        if [[ "${mode}" == "symlink-payload" ]]; then
            mkdir -p "${dest}/xray"
        else
            printf '#!/usr/bin/env bash\nexit 0\n' >"${dest}/xray"
            chmod 755 "${dest}/xray"
        fi
    }
    tar() {
        case "$1" in
        -tzf) printf '%s\n' "${singBoxListing}"; return 0 ;;
        -tvzf) printf '%s\n' "${singBoxLongListing}"; return 0 ;;
        -xOzf) printf '%s\n' "${singBoxExtract}"; return 0 ;;
        esac
        local dest=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -C) dest=$2; shift 2 ;;
            *) shift ;;
            esac
        done
        mkdir -p "${dest}/sing-box-1.2.3-linux-amd64"
        printf '#!/usr/bin/env bash\nexit 0\n' >"${dest}/sing-box-1.2.3-linux-amd64/sing-box"
        printf 'cronet\n' >"${dest}/sing-box-1.2.3-linux-amd64/libcronet.so"
        chmod 755 "${dest}/sing-box-1.2.3-linux-amd64/sing-box"
    }

    set +e
    downloadXrayReleaseBinaryToTempDir v1.2.3 "${tmpDir}/xray"
    xrayRc=$?
    downloadSingBoxReleaseBinaryToTempDir v1.2.3 "${tmpDir}/sing"
    singBoxRc=$?
    set -e

    [[ "${xrayRc}" -ne 0 ]]
    [[ "${singBoxRc}" -ne 0 ]]
)

runCoreFirstInstallCommitFailureRollbackRegression() (
    local rootRel="${TMP_DIR}/core-first-install-commit-failure"
    local root
    local xrayDir
    local singBoxDir
    local errorLog
    local copyLog
    local rmLog
    local xrayRc singBoxRc

    mkdir -p "${rootRel}/tmp" "${rootRel}/sing-box"
    root=$(cd -- "${rootRel}" && pwd -P)
    xrayDir="${root}/xray"
    singBoxDir="${root}/sing-box"
    printf 'old-cronet\n' >"${singBoxDir}/libcronet.so"
    errorLog="${root}/error.log"
    copyLog="${root}/copy.log"
    rmLog="${root}/rm.log"
    : >"${errorLog}"
    : >"${copyLog}"
    : >"${rmLog}"

    PADM_XRAY_BINARY="${xrayDir}/xray"
    PADM_SINGBOX_BINARY="${singBoxDir}/sing-box"
    xrayCoreCPUVendor=linux-64
    singBoxCoreCPUVendor=-linux-amd64
    TMPDIR="${root}/tmp"

    readInstallType() { return 0; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    coreLatestReleaseTag() { printf 'v1.2.3\n'; }
    checkVersionNotEmpty() { [[ -n "$1" ]]; }
    padmCreateTempPath() {
        local resultVar=$1
        local path
        shift
        if [[ "${1:-}" == "-d" ]]; then
            path=$(mktemp -d "${TMPDIR}/core.XXXXXX") || return 1
        else
            path=$(mktemp "${TMPDIR}/core.XXXXXX") || return 1
        fi
        printf -v "${resultVar}" '%s' "${path}"
    }
    padmCreateTempFileForTarget() {
        local resultVar=$1
        local targetFile=$2
        local targetDir targetName
        targetDir=$(dirname -- "${targetFile}")
        targetName=$(basename -- "${targetFile}")
        mkdir -p "${targetDir}" || return 1
        path=$(cd -- "${targetDir}" && mktemp ".${targetName}.install.XXXXXX") || return 1
        printf -v "${resultVar}" '%s' "${targetDir}/${path}"
    }
    padmRemoveCleanupPath() { rm -rf "$1"; }
    padmForgetCleanupPath() { return 0; }
    removeManagedFileIfPresent() {
        printf 'rm:%s\n' "$1" >>"${rmLog}"
        command rm -f -- "$1"
    }
    commitGeneratedFile() {
        local tmpFile=$1
        local targetFile=$2
        local mode=$3
        [[ -n "${mode}" ]] && chmod "${mode}" "${tmpFile}" || return 1
        if [[ "${targetFile}" == "${PADM_SINGBOX_BINARY}" ]]; then
            return 1
        fi
        mv "${tmpFile}" "${targetFile}"
    }
    xrayInstalled() { return 1; }
    singBoxInstalled() { return 1; }
    ensureXrayGeoFiles() { return 1; }
    downloadXrayReleaseBinaryToTempDir() {
        local version=$1
        local tmpDir=$2
        (
            cd -- "${tmpDir}" || return 1
            printf '#!/usr/bin/env bash\nexit 0\n' >xray || return 1
            chmod 755 xray || return 1
        ) || return 1
        return 0
    }
    downloadSingBoxReleaseBinaryToTempDir() {
        local version=$1
        local tmpDir=$2
        local extractedDir="sing-box-${version/v/}${singBoxCoreCPUVendor}"
        (
            cd -- "${tmpDir}" || return 1
            mkdir -p "${extractedDir}" || return 1
            printf '#!/usr/bin/env bash\nexit 0\n' >"${extractedDir}/sing-box" || return 1
            printf 'cronet\n' >"${extractedDir}/libcronet.so" || return 1
            chmod 755 "${extractedDir}/sing-box" || return 1
        ) || return 1
        return 0
    }
    cp() {
        local sourcePath=$1
        local targetPath=$2
        printf '%s -> %s\n' "${sourcePath}" "${targetPath}" >>"${copyLog}"
        command cp "$@"
    }

    set +e
    ( installXray 1 false >/dev/null 2>&1 )
    xrayRc=$?
    ( installSingBox 1 >/dev/null 2>&1 )
    singBoxRc=$?
    set -e

    [[ "${xrayRc}" == "1" ]]
    [[ "${singBoxRc}" == "1" ]]
    [[ ! -e "${xrayDir}/xray" ]]
    [[ ! -e "${singBoxDir}/sing-box" ]]
    [[ -e "${singBoxDir}/libcronet.so" ]] || return 1
    [[ "$(<"${singBoxDir}/libcronet.so")" == 'old-cronet' ]] || return 1
    grep -qxF "rm:${xrayDir}/xray" "${rmLog}"
    grep -q 'sing-box安装失败' "${errorLog}"
    ! grep -q 'cronet依赖回滚失败' "${errorLog}"

    rm -f "${singBoxDir}/libcronet.so"
    set +e
    ( installSingBox 1 >/dev/null 2>&1 )
    singBoxRc=$?
    set -e
    [[ "${singBoxRc}" == "1" ]]
    [[ ! -e "${singBoxDir}/sing-box" ]]
    [[ ! -e "${singBoxDir}/libcronet.so" ]] || return 1
)

runCoreInstallRejectsUnsafeBinaryPathRegression() (
    local root="${TMP_DIR}/core-install-unsafe-binary"
    local errorLog="${root}/error.log"
    local xrayRc singBoxRc

    mkdir -p "${root}"
    : >"${errorLog}"

    PADM_XRAY_BINARY="relative/xray"
    PADM_SINGBOX_BINARY="relative/sing-box"
    xrayCoreCPUVendor=linux-64
    singBoxCoreCPUVendor=-linux-amd64

    readInstallType() { return 0; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    coreLatestReleaseTag() { printf 'v1.2.3\n'; }
    checkVersionNotEmpty() { [[ -n "$1" ]]; }
    ensureXrayGeoFiles() { return 0; }
    padmCreateTempPath() {
        local resultVar=$1
        local path
        shift
        if [[ "${1:-}" == "-d" ]]; then
            path=$(mktemp -d "${root}/tmp.XXXXXX") || return 1
        else
            path=$(mktemp "${root}/tmp.XXXXXX") || return 1
        fi
        printf -v "${resultVar}" '%s' "${path}"
    }
    padmRemoveCleanupPath() { rm -rf "$1"; }
    downloadGitHubReleaseAsset() { return 0; }
    unzip() {
        if [[ "${1:-}" == "-Z1" ]]; then
            printf 'xray\n'
            return 0
        fi
        if [[ "${1:-}" == "-Z" && "${2:-}" == "-l" ]]; then
            printf '%s\n' '-rwxr-xr-x  3.0 unx 0 b- 0% 2026-01-01 00:00 xray'
            return 0
        fi
        if [[ "${1:-}" == "-p" ]]; then
            printf 'xray\n'
            return 0
        fi
        local dest=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -d)
                dest=$2
                shift 2
                ;;
            *)
                shift
                ;;
            esac
        done
        printf '#!/usr/bin/env bash\nexit 0\n' >"${dest}/xray"
        chmod 755 "${dest}/xray"
    }
    tar() {
        case "${1:-}" in
        -tzf)
            printf 'sing-box-1.2.3-linux-amd64/\nsing-box-1.2.3-linux-amd64/sing-box\nsing-box-1.2.3-linux-amd64/libcronet.so\n'
            return 0
            ;;
        -tvzf)
            printf '%s\n' 'drwxr-xr-x root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/'
            printf '%s\n' '-rwxr-xr-x root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/sing-box'
            printf '%s\n' '-rw-r--r-- root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/libcronet.so'
            return 0
            ;;
        -xOzf)
            printf 'sing-box\ncronet\n'
            return 0
            ;;
        esac
        local dest=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -C)
                dest=$2
                shift 2
                ;;
            *)
                shift
                ;;
            esac
        done
        mkdir -p "${dest}/sing-box-1.2.3-linux-amd64"
        printf '#!/usr/bin/env bash\nexit 0\n' >"${dest}/sing-box-1.2.3-linux-amd64/sing-box"
        printf 'cronet\n' >"${dest}/sing-box-1.2.3-linux-amd64/libcronet.so"
        chmod 755 "${dest}/sing-box-1.2.3-linux-amd64/sing-box"
    }

    set +e
    ( installXray 1 false >/dev/null 2>&1 )
    xrayRc=$?
    ( installSingBox 1 >/dev/null 2>&1 )
    singBoxRc=$?
    set -e

    [[ "${xrayRc}" == "1" ]]
    [[ "${singBoxRc}" == "1" ]]
    grep -q 'Xray-core安装路径异常' "${errorLog}"
    grep -q 'sing-box安装路径异常' "${errorLog}"
)

runCoreCleanupFailurePropagationRegression() (
    local root="${TMP_DIR}/core-cleanup-failure"
    local serviceLog="${root}/service.log"
    local rmLog="${root}/rm.log"
    local errorLog="${root}/error.log"
    local reachedFile="${root}/reached"
    local queueLog="${root}/queue.log"
    local rc

    mkdir -p "${root}/xray" "${root}/sing-box" "${root}/nginx"
    configPath="${root}/xray/"
    singBoxConfigPath="${root}/sing-box/"
    nginxConfigPath="${root}/nginx/"
    PADM_REALITY_ENTRY_HOST_FILE="${root}/reality_entry_host"
    : >"${serviceLog}"
    : >"${rmLog}"
    : >"${errorLog}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"

    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        return 0
    }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        printf 'cleanup\n' >>"${queueLog}"
        return 1
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        return 0
    }

    SERVICE_QUEUE_ALLOW_FAILURE=previous
    regressionExpectStatus 1 cleanUp xrayDel >/dev/null 2>&1
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -q 'Xray 服务停止失败，已取消清理旧核心' "${errorLog}"
    [[ ! -s "${rmLog}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    : >"${serviceLog}"
    : >"${rmLog}"
    : >"${errorLog}"
    : >"${queueLog}"
    command rm -f "${reachedFile}"
    readLastInstallationConfig() { return 0; }
    collectEntryProfile() { realityEntryHost=cleanup.example.com; return 0; }
    persistRealityEntryProfile() { printf 'persist\n' >>"${queueLog}"; return 0; }
    unInstallSubscribe() { return 0; }
    installTools() { return 0; }
    installSingBox() { return 0; }
    installSingBoxService() { return 0; }
    initSingBoxConfig() { return 0; }
    serviceQueueRestart() {
        printf 'restart:%s\n' "$1" >>"${queueLog}"
        return 0
    }
    serviceQueueApply() {
        printf 'apply\n' >>"${queueLog}"
        return 0
    }
    checkGFWStatue() {
        printf 'check\n' >>"${queueLog}"
        printf 'reached\n' >"${reachedFile}"
        return 0
    }
    showAccounts() {
        printf 'reached\n' >"${reachedFile}"
        return 0
    }

    regressionExpectStatus 1 installSingBoxReality >/dev/null 2>&1
    grep -qx 'xray:stop:true' "${serviceLog}"
    ! grep -q '/etc/padm/xray' "${rmLog}"
    [[ "$(<"${queueLog}")" == $'restart:sing-box\napply\npersist\ncheck\ncleanup' ]]
    [[ -e "${reachedFile}" ]]

    (
        local switchRoot="${root}/switch-rollback"
        local oldCoreDir="${switchRoot}/xray"
        local switchLog="${switchRoot}/switch.log"
        local xrayServiceRunning=true
        local switchRc

        mkdir -p "${oldCoreDir}"
        printf 'old-core\n' >"${oldCoreDir}/state"
        : >"${switchLog}"
        PADM_XRAY_BINARY="${oldCoreDir}/xray"
        rm() { command rm "$@"; }
        coreTemplateConfigBackupCreate() {
            printf -v "$1" '%s' "${switchRoot}/config-backup"
        }
        checkLogBackupRestore() {
            printf 'config-restore\n' >>"${switchLog}"
        }
        xrayRunning() { [[ "${xrayServiceRunning}" == "true" ]]; }
        singBoxRunning() { return 1; }
        handleXray() {
            if [[ "$1" == "start" && -f "${oldCoreDir}/state" ]]; then
                printf 'xray:start:restored\n' >>"${switchLog}"
                xrayServiceRunning=true
                return 0
            fi
            printf 'xray:%s:missing\n' "$1" >>"${switchLog}"
            return 1
        }
        failingSwitch() {
            xrayServiceRunning=false
            mv "${oldCoreDir}" "${oldCoreDir}.removed"
            return 7
        }

        regressionExpectStatus 7 coreSwitchConfigTransaction sing-box failingSwitch >/dev/null 2>&1
        [[ "$(<"${oldCoreDir}/state")" == "old-core" ]]
        [[ "$(<"${switchLog}")" == $'config-restore\nxray:start:restored' ]]
    )
)

runCorePortFileTransactionRegression() {
    local oldTmpDir="${TMPDIR:-}"
    local configRoot
    local portTmpRoot="${TMP_DIR}/core-port-tmp"
    mkdir -p "${portTmpRoot}"
    portTmpRoot=$(cd -- "${portTmpRoot}" && pwd -P) || return 1
    TMPDIR="${portTmpRoot}"
    mkdir -p "${configPath}"
    configRoot=$(cd -- "${configPath}" && pwd -P) || return 1
    configPath="${configRoot%/}/"
    writeCoreDokodemoInbound "${configPath}02_dokodemodoor_inbounds_2053.json" 2053 443 tcp dokodemo-door-newPort-2053
    writeCoreDokodemoInbound "${configPath}02_dokodemodoor_inbounds_2083_default.json" 2083 443 tcp dokodemo-door-newPort-2083
    local original2053 original2083 keptBackup
    original2053=$(<"${configPath}02_dokodemodoor_inbounds_2053.json")
    original2083=$(<"${configPath}02_dokodemodoor_inbounds_2083_default.json")
    if corePortApplyFileTransaction corePortWriteAddFiles $'2053\n2083' 2053 'bad-port' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${configPath}02_dokodemodoor_inbounds_2053.json")" == "${original2053}" ]]
    [[ "$(<"${configPath}02_dokodemodoor_inbounds_2083_default.json")" == "${original2083}" ]]
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2053_default.json" ]]
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2083.json" ]]

    corePortApplyFileTransaction corePortWriteAddFiles $'2053\n2083' 2053 443
    [[ -e "${configPath}02_dokodemodoor_inbounds_2053_default.json" ]]
    [[ -e "${configPath}02_dokodemodoor_inbounds_2083.json" ]]
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2083_default.json" ]]
    jq -e '.inbounds[0].port == 2053 and .inbounds[0].settings.port == 443' "${configPath}02_dokodemodoor_inbounds_2053_default.json" >/dev/null

    if corePortApplyFileTransaction corePortWriteAddFiles 2443 2443 'bad-port' 2>/dev/null; then
        return 1
    fi
    [[ -e "${configPath}02_dokodemodoor_inbounds_2053_default.json" ]]
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2443_default.json" ]]

    corePortApplyFileTransaction corePortRemove 2083
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2083.json" ]]
    [[ -e "${configPath}02_dokodemodoor_inbounds_2053_default.json" ]]

    local reloadCalls=0 errorLog="${TMP_DIR}/core-port-reload-error.log"
    local reloadLog="${TMP_DIR}/core-port-reload-calls.log"
    local helperLog="${TMP_DIR}/core-port-helper.log"
    : >"${errorLog}"
    : >"${helperLog}"
    errorCard() {
        printf '%s\n' "$*" >>"${errorLog}"
    }
    eval "$(declare -f corePortReportBackupFailure | sed '1s/^corePortReportBackupFailure/originalCorePortReportBackupFailure/')"
    corePortReportBackupFailure() {
        printf 'backup\n' >>"${helperLog}"
        originalCorePortReportBackupFailure "$@"
    }
    eval "$(declare -f corePortReportRollbackFailure | sed '1s/^corePortReportRollbackFailure/originalCorePortReportRollbackFailure/')"
    corePortReportRollbackFailure() {
        printf 'rollback\n' >>"${helperLog}"
        originalCorePortReportRollbackFailure "$@"
    }

    : >"${errorLog}"
    (
        cp() {
            local args=("$@")
            local targetPath="${args[$((${#args[@]} - 1))]}"
            if [[ "${targetPath}" == "${portTmpRoot}"/padm-core-port.*/.* ]]; then
                return 1
            fi
            command cp "$@"
        }
        if corePortApplyFileTransaction corePortWriteAddFiles 2443 2443 443 2>/dev/null; then
            return 1
        fi
        [[ "$(<"${configPath}02_dokodemodoor_inbounds_2053_default.json")" == "${original2053}" ]]
        [[ ! -e "${configPath}02_dokodemodoor_inbounds_2443_default.json" ]]
        if regressionFindHasMatches "${portTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-core-port.*'; then
            return 1
        fi
    ) || return 1
    grep -q "入口端口配置备份失败" "${errorLog}"
    [[ "$(grep -c '^backup$' "${helperLog}")" == "1" ]]

    : >"${errorLog}"
    : >"${helperLog}"
    (
        corePortBackupFiles() {
            return 1
        }
        if corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 443 2>/dev/null; then
            return 1
        fi
    ) || return 1
    grep -q "入口端口配置备份失败" "${errorLog}"
    [[ "$(grep -c '^backup$' "${helperLog}")" == "1" ]]

    : >"${errorLog}"
    : >"${helperLog}"
    (
        cp() {
            local args=("$@")
            local targetPath="${args[$((${#args[@]} - 1))]}"
            if [[ "${targetPath}" == "${configPath}".02_dokodemodoor_inbounds_2053_default.json.restore.* ]]; then
                return 1
            fi
            command cp "$@"
        }
        if corePortApplyFileTransaction corePortWriteAddFiles 2443 2443 'bad-port' 2>/dev/null; then
            return 1
        fi
    ) || return 1
    grep -q "入口端口配置回滚失败" "${errorLog}"
    [[ "$(grep -c '^rollback$' "${helperLog}")" == "1" ]]
    keptBackup=$(find "${portTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-core-port.*' -print -quit)
    [[ -n "${keptBackup}" && -d "${keptBackup}" ]]
    [[ -f "${keptBackup}/02_dokodemodoor_inbounds_2053_default.json" ]]
    rm -rf "${keptBackup}"
    printf '%s\n' "${original2053}" >"${configPath}02_dokodemodoor_inbounds_2053_default.json"
    rm -f "${configPath}02_dokodemodoor_inbounds_2443_default.json"

    reloadCore() {
        reloadCalls=$((reloadCalls + 1))
        [[ "${reloadCalls}" != "1" ]]
    }

    original2053=$(<"${configPath}02_dokodemodoor_inbounds_2053_default.json")
    if corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 443 2>/dev/null; then
        return 1
    fi
    [[ "${reloadCalls}" == "2" ]]
    [[ "$(<"${configPath}02_dokodemodoor_inbounds_2053_default.json")" == "${original2053}" ]]
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2443_default.json" ]]

    reloadCalls=0
    reloadCore() {
        reloadCalls=$((reloadCalls + 1))
        [[ "${reloadCalls}" != "1" ]]
    }
    if corePortApplyReloadTransaction corePortRemove 2053 2>/dev/null; then
        return 1
    fi
    [[ "${reloadCalls}" == "2" ]]
    [[ "$(<"${configPath}02_dokodemodoor_inbounds_2053_default.json")" == "${original2053}" ]]
    grep -q "入口端口核心重载失败，已恢复旧配置" "${errorLog}"
    grep -q "恢复后核心重载仍失败" "${errorLog}" && return 1

    reloadCalls=0
    : >"${reloadLog}"
    : >"${errorLog}"
    reloadCore() {
        printf 'reload\n' >>"${reloadLog}"
        reloadCalls=$((reloadCalls + 1))
        [[ "${reloadCalls}" != "1" ]]
    }
    (
        cp() {
            local args=("$@")
            local sourcePath="${args[$((${#args[@]} - 2))]}"
            if [[ "${sourcePath}" == */padm-core-port.*/02_dokodemodoor_inbounds_2053_default.json ]]; then
                return 1
            fi
            command cp "$@"
        }
        if corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 443 2>/dev/null; then
            return 1
        fi
    ) || return 1
    [[ "$(grep -c '^reload$' "${reloadLog}")" == "1" ]]
    grep -q "入口端口核心重载失败，且旧配置恢复失败" "${errorLog}"
    keptBackup=$(find "${portTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-core-port.*' -print -quit)
    [[ -n "${keptBackup}" && -d "${keptBackup}" ]]
    rm -rf "${keptBackup}"
    printf '%s\n' "${original2053}" >"${configPath}02_dokodemodoor_inbounds_2053_default.json"
    rm -f "${configPath}02_dokodemodoor_inbounds_2443_default.json"

    reloadCalls=0
    reloadCore() {
        reloadCalls=$((reloadCalls + 1))
        return 0
    }
    corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 443
    [[ "${reloadCalls}" == "1" ]]
    [[ -e "${configPath}02_dokodemodoor_inbounds_2443_default.json" ]]
    if regressionFindHasMatches "${portTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-core-port.*'; then
        return 1
    fi

    (
        local firewallLog="${TMP_DIR}/core-port-firewall-lifecycle.log"
        local firewallErrorLog="${TMP_DIR}/core-port-firewall-errors.log"
        local denyShouldFail=false
        local denyTcpShouldFail=false
        local mode=add-fail
        local rc
        : >"${firewallLog}"
        : >"${firewallErrorLog}"
        eval "$(declare -f addCorePort | sed '1s/^addCorePort/originalAddCorePort/')"
        addCorePort() { return 0; }
        autoRead() {
            case "$1" in
            core_port_menu) [[ "${mode}" == "delete" ]] && printf -v "$3" 3 || printf -v "$3" 2 ;;
            extra_core_ports) printf -v "$3" '2555,2666' ;;
            extra_core_default_port) printf -v "$3" 443 ;;
            extra_core_delete_port) printf -v "$3" 1 ;;
            esac
        }
        allowPort() {
            PADM_LAST_ALLOW_PORT_ADDED=true
            printf 'allow:%s:%s\n' "$1" "${2:-tcp}" >>"${firewallLog}"
        }
        denyPort() {
            printf 'deny:%s:%s\n' "$1" "${2:-tcp}" >>"${firewallLog}"
            [[ "${denyShouldFail}" != "true" && ( "${denyTcpShouldFail}" != "true" || "${2:-tcp}" != "tcp" ) ]]
        }
        errorCard() { printf '%s\n' "$1" >>"${firewallErrorLog}"; }
        corePortListExtra() { return 0; }
        corePortResolveByIndex() { printf '2555\n'; }
        corePortApplyReloadTransaction() { [[ "${mode}" == "delete" ]]; }
        coreInstallType=1
        customPort=

        regressionExpectStatus 1 originalAddCorePort >/dev/null 2>&1
        grep -qx 'deny:2555:tcp' "${firewallLog}"
        grep -qx 'deny:2555:udp' "${firewallLog}"
        grep -qx 'deny:2666:tcp' "${firewallLog}"
        grep -qx 'deny:2666:udp' "${firewallLog}"

        denyShouldFail=true
        : >"${firewallErrorLog}"
        set +e
        originalAddCorePort >/dev/null 2>&1
        rc=$?
        set -e
        denyShouldFail=false
        [[ "${rc}" == "1" ]]
        grep -qx '入口端口防火墙规则回滚失败，请检查防火墙状态' "${firewallErrorLog}"

        mode=delete
        : >"${firewallLog}"
        originalAddCorePort >/dev/null 2>&1
        grep -qx 'deny:2555:tcp' "${firewallLog}"
        grep -qx 'deny:2555:udp' "${firewallLog}"

        denyTcpShouldFail=true
        : >"${firewallLog}"
        regressionExpectStatus 1 originalAddCorePort >/dev/null 2>&1
        grep -qx 'deny:2555:tcp' "${firewallLog}"
        grep -qx 'deny:2555:udp' "${firewallLog}"
    )

    rm -rf "${configPath}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runCoreTemplateReturnFailureRegression() (
    local root="${TMP_DIR}/core-template-return"
    local xrayRoot="${root}/xray"
    local singBoxRoot="${root}/sing-box"
    local nginxRoot="${root}/nginx"
    local firewallState="${root}/firewall.state"
    local firewallLog="${root}/firewall.log"
    local entryHostFile="${root}/reality_entry_host"
    local mode=xray
    local xrayRc singBoxRc
    local stopRc writeCalls=0 serviceLog="${TMP_DIR}/core-template-service.log"
    local singBoxServiceRunning=true
    local xrayServiceRunning=true

    mkdir -p "${xrayRoot}" "${singBoxRoot}" "${nginxRoot}"
    PADM_XRAY_BINARY="${root}/xray-install/xray"
    configPath="${xrayRoot}/"
    singBoxConfigPath="${singBoxRoot}/"
    nginxConfigPath="${nginxRoot}/"
    PADM_FIREWALL_STATE_FILE="${firewallState}"
    PADM_REALITY_ENTRY_HOST_FILE="${entryHostFile}"
    : >"${firewallLog}"
    currentUUID=existing-user
    currentClients='[]'
    domain=tls.example.com
    currentHost=tls.example.com
    lastInstallationConfig=true
    selectCustomInstallType=",1,"
    singBoxVLESSVisionPort=10890
    singBoxVLESSWSPort=10891

    xrayTemplateConfigDir() { printf '%s\n' "${xrayRoot}"; }
    singBoxTemplateConfigDir() { printf '%s\n' "${singBoxRoot}"; }
    initXrayClients() { printf '[]\n'; }
    initSingBoxClients() { printf '[]\n'; }
    addXrayOutbound() { [[ "${mode}" != "xray-outbound" ]]; }
    checkDNSIP() { return 0; }
    removeNginxDefaultConf() { return 0; }
    randomPathFunction() { currentPath=template-path; }
    xrayRunning() { [[ "${xrayServiceRunning}" == "true" ]]; }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        if [[ "$1" == "stop" ]]; then
            xrayServiceRunning=false
        elif [[ "$1" == "start" ]]; then
            xrayServiceRunning=true
        fi
    }
    singBoxRunning() { [[ "${singBoxServiceRunning}" == "true" ]]; }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        if [[ "$1" == "stop" ]]; then
            [[ "${mode}" != "stop-fail" ]] || return 1
            singBoxServiceRunning=false
        elif [[ "$1" == "start" ]]; then
            singBoxServiceRunning=true
        fi
    }
    checkPortOpen() { return 0; }
    initSingBoxPort() {
        if [[ "${mode}" == "state-drift" ]]; then
            padmTrackPortAllowTransactionKey "port:ufw:tcp:10890"
        else
            padmFirewallStateAdd "port:ufw:tcp:10890"
            padmFirewallStateAdd "port:ufw:udp:10890"
        fi
        printf '10890\n'
    }
    removeFirewallPortRule() {
        printf '%s:%s:%s\n' "$1" "$2" "$3" >>"${firewallLog}"
        return 0
    }
    writeGeneratedJsonFile() {
        local targetFile=$1
        local mappedTarget=${targetFile}
        shift 2
        writeCalls=$((writeCalls + 1))
        if [[ "${mode}" == "xray" && "${targetFile}" == "/etc/padm/xray/conf/09_routing.json" ]]; then
            return 1
        fi
        if [[ "${mode}" == "sing-box" && "${targetFile}" == "/etc/padm/sing-box/conf/config/03_VLESS_WS_inbounds.json" ]]; then
            return 1
        fi
        case "${targetFile}" in
        /etc/padm/xray/conf/*) mappedTarget="${xrayRoot}/${targetFile##*/}" ;;
        /etc/padm/sing-box/conf/config/*) mappedTarget="${singBoxRoot}/${targetFile##*/}" ;;
        esac
        cat >"${mappedTarget}"
    }

    printf '%s\n' 'old-xray-log' >"${xrayRoot}/00_log.json"
    regressionExpectFailure initXrayConfig custom 1 true 2>/dev/null
    [[ "$(<"${xrayRoot}/00_log.json")" == 'old-xray-log' ]]
    [[ ! -e "${xrayRoot}/12_policy.json" ]]
    [[ ! -e "${xrayRoot}/11_dns.json" ]]

    mode=xray-outbound
    regressionExpectFailure initXrayConfig custom 1 true 2>/dev/null
    [[ ! -e "${xrayRoot}/09_routing.json" ]]

    mode=stop-fail
    selectCustomInstallType=",27,"
    writeCalls=0
    : >"${serviceLog}"
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    rm -f "${firewallState}"
    : >"${firewallLog}"
    regressionExpectFailure initSingBoxConfig custom 1 true 2>/dev/null
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    [[ "${writeCalls}" == "0" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    grep -qx 'ufw:10890:tcp' "${firewallLog}"
    grep -qx 'ufw:10890:udp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    mode=sing-box
    selectCustomInstallType=",27,21,"
    writeCalls=0
    printf '%s\n' 'old-sing-box-inbound' >"${singBoxRoot}/02_VLESS_TCP_inbounds.json"
    : >"${serviceLog}"
    rm -f "${firewallState}"
    : >"${firewallLog}"
    regressionExpectFailure initSingBoxConfig custom 1 true 2>/dev/null
    [[ "${writeCalls}" != "0" ]]
    [[ "$(<"${singBoxRoot}/02_VLESS_TCP_inbounds.json")" == 'old-sing-box-inbound' ]]
    [[ ! -e "${singBoxRoot}/03_VLESS_WS_inbounds.json" ]]
    [[ "${singBoxServiceRunning}" == "true" ]]
    grep -qx 'sing-box:start:true' "${serviceLog}"
    grep -qx 'ufw:10890:tcp' "${firewallLog}"
    grep -qx 'ufw:10890:udp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    mode=stop-fail
    writeCalls=0
    padmFirewallStateAdd "port:ufw:tcp:10890"
    : >"${firewallLog}"
    regressionExpectFailure initSingBoxConfig custom 1 true 2>/dev/null
    ! grep -q ':tcp$' "${firewallLog}"
    grep -qx 'ufw:10890:udp' "${firewallLog}"
    padmFirewallStateHas "port:ufw:tcp:10890"
    ! padmFirewallStateHas "port:ufw:udp:10890"
    rm -f "${firewallState}"

    readLastInstallationConfig() { return 0; }
    installTools() { return 0; }
    installSingBox() { return 0; }
    installSingBoxService() { return 0; }
    serviceQueueRestart() { return 0; }
    serviceQueueApply() { return 0; }
    checkGFWStatue() { return 0; }
    showAccounts() { return 0; }
    collectEntryProfile() {
        realityEntryHost=new-entry.example.com
        return 0
    }
    initSingBoxConfig() {
        local result=()
        readSingBoxPortResult result 10890 false
    }
    cleanUp() {
        xrayServiceRunning=false
        return 1
    }
    mode=install-failure
    printf 'old-entry.example.com\n' >"${entryHostFile}"
    rm -f "${firewallState}"
    : >"${firewallLog}"
    : >"${serviceLog}"
    regressionExpectStatus 1 installSingBoxReality >/dev/null 2>&1
    grep -qx 'ufw:10890:tcp' "${firewallLog}"
    grep -qx 'ufw:10890:udp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]
    [[ "$(<"${entryHostFile}")" == "old-entry.example.com" ]]
    [[ "${xrayServiceRunning}" == "true" ]]
    [[ "${singBoxServiceRunning}" == "true" ]]
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    grep -qx 'sing-box:start:true' "${serviceLog}"

    mode=state-drift
    padmFirewallStateAdd "port:ufw:tcp:10890"
    : >"${firewallLog}"
    : >"${serviceLog}"
    regressionExpectStatus 1 installSingBoxReality >/dev/null 2>&1
    grep -qx 'ufw:10890:tcp' "${firewallLog}"
    ! grep -q ':udp$' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]
    [[ "$(<"${entryHostFile}")" == "old-entry.example.com" ]]
    [[ "${xrayServiceRunning}" == "true" ]]
    [[ "${singBoxServiceRunning}" == "true" ]]

    local manualUuid=11111111-1111-1111-1111-111111111111
    local manualUser=sub_manual
    local uuidGenerationLog="${root}/uuid-generation.log"
    autoRead() {
        case "$1" in
        core_init_uuid) printf -v "$3" '%s' "${manualUuid}" ;;
        core_init_username) printf -v "$3" '%s' "${manualUser}" ;;
        *) return 1 ;;
        esac
    }
    collectTLSProfile() { tlsCertDomain=tls.example.com; }
    currentUUID=
    lastInstallationConfig=
    writeCalls=0
    regressionExpectFailure initXrayConfigApply custom 1 true 2>/dev/null
    [[ "${writeCalls}" == "0" ]]

    selectCustomInstallType=",27,"
    regressionExpectFailure initSingBoxConfigApply custom 1 true 2>/dev/null
    [[ "${writeCalls}" == "0" ]]

    manualUuid=not-a-uuid
    set +e
    initXrayConfigApply custom 1 true 2>/dev/null
    xrayRc=$?
    initSingBoxConfigApply custom 1 true 2>/dev/null
    singBoxRc=$?
    set -e
    [[ "${xrayRc}" != "0" && "${singBoxRc}" != "0" ]]
    [[ "${writeCalls}" == "0" ]]

    manualUuid=
    manualUser=manual
    : >"${uuidGenerationLog}"
    generateRandomUuidValue() {
        printf 'call\n' >>"${uuidGenerationLog}"
        return 1
    }
    set +e
    initXrayConfigApply custom 1 true 2>/dev/null
    xrayRc=$?
    initSingBoxConfigApply custom 1 true 2>/dev/null
    singBoxRc=$?
    set -e
    [[ "${xrayRc}" != "0" && "${singBoxRc}" != "0" ]]
    [[ "$(grep -c '^call$' "${uuidGenerationLog}")" == "2" ]]
    [[ "${writeCalls}" == "0" ]]
    currentUUID=existing-user
    lastInstallationConfig=true

    mode=template
    initRealityProfile() { return 0; }
    initXrayRealityPort() { return 0; }
    initRealityKey() { return 1; }
    initRealityMldsa65() { return 0; }
    selectCustomInstallType=",1,"
    regressionExpectFailure initXrayConfig custom 1 true 2>/dev/null

    installSniffing() { return 1; }
    selectCustomInstallType=",999,"
    regressionExpectFailure initXrayConfig custom 1 true 2>/dev/null

    installSniffing() { return 0; }
    removeSingBoxConfig() { return 1; }
    setSniffRouting() { return 0; }
    mode=cleanup-fail
    selectCustomInstallType=",999,"
    regressionExpectFailure padmRunPortAllowTransaction initSingBoxConfigApply custom 1 2>/dev/null
)

runCoreInstallServiceActionFailureRegression() (
    local root="${TMP_DIR}/core-install-service-action"
    local serviceLog="${root}/service.log"
    local callLog="${root}/calls.log"
    local errorLog="${root}/errors.log"
    local reachedFile="${root}/reached"
    local firewallState="${root}/firewall.state"
    local firewallLog="${root}/firewall.log"
    local entryHostFile="${root}/reality_entry_host"
    local xrayRoot="${root}/xray"
    local singBoxRoot="${root}/sing-box"
    local nginxRoot="${root}/nginx"
    local mode rc nginxRuntimeState
    local xrayRuntimeState=false singBoxRuntimeState=false

    mkdir -p "${xrayRoot}" "${singBoxRoot}" "${nginxRoot}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    PADM_FIREWALL_STATE_FILE="${firewallState}"
    PADM_REALITY_ENTRY_HOST_FILE="${entryHostFile}"
    configPath="${xrayRoot}/"
    singBoxConfigPath="${singBoxRoot}/"
    nginxConfigPath="${nginxRoot}/"
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    protocolRegistryMenu() { return 0; }
    readLastInstallationConfig() { return 0; }
    unInstallSubscribe() { return 0; }
    installTools() { printf 'installTools:%s\n' "$*" >>"${callLog}"; return 0; }
    initTLSNginxConfig() { printf 'initTLS:%s\n' "$*" >>"${callLog}"; return 0; }
    installTLS() { printf 'installTLS:%s\n' "$*" >>"${callLog}"; return 0; }
    randomPathFunction() {
        printf 'path:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" != "path-fail" ]]
    }
    nginxBlog() {
        printf 'nginxBlog:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" != "blog-fail" ]]
    }
    updateRedirectNginxConf() {
        printf 'redirect\n' >>"${callLog}"
        [[ "${mode}" == "redirect-fail" ]] && return 1
        nginxRuntimeState=false
        return 0
    }
    installXray() {
        printf 'installXray:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" == "xray-install-exit" ]] && exit 1
        return 0
    }
    installXrayService() {
        printf 'installXrayService:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" == "xray-service-fail" ]] && return 1
        return 0
    }
    initXrayConfig() {
        printf 'initXrayConfig:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" != "xray-config-fail" ]]
    }
    installSingBox() { printf 'installSingBox:%s\n' "$*" >>"${callLog}"; return 0; }
    installSingBoxService() { printf 'installSingBoxService:%s\n' "$*" >>"${callLog}"; return 0; }
    initSingBoxConfig() { printf 'initSingBoxConfig:%s\n' "$*" >>"${callLog}"; return 0; }
    cleanUp() { printf 'cleanup:%s\n' "$*" >>"${callLog}"; return 0; }
    cleanAgentNginxConf() { printf 'clean-nginx\n' >>"${callLog}"; return 0; }
    installCronTLS() {
        printf 'cron:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" != "cron-fail" ]]
    }
    customPortFunction() {
        padmFirewallStateAdd 'port:ufw:tcp:2443' || return 1
        padmTrackPortAllowTransactionKey 'port:ufw:tcp:2443'
        printf 'customPort\n' >>"${callLog}"
    }
    removeFirewallPortRule() {
        printf '%s:%s:%s\n' "$1" "$2" "$3" >>"${firewallLog}"
    }
    subscriptionWireGuardControlEnabled() { return 0; }
    refreshSubscriptionWireGuardNginxControl() {
        printf 'wg-refresh\n' >>"${callLog}"
        [[ "${mode}" != "wg-refresh-fail" ]] || return 1
        serviceQueueRefresh nginx
    }
    serviceQueueRefresh() {
        printf 'queueRefresh:%s\n' "$*" >>"${callLog}"
        SERVICE_ACTIONS="${SERVICE_ACTIONS}
$1:refresh"
    }
    serviceQueueStart() { printf 'queueStart:%s\n' "$*" >>"${callLog}"; return 0; }
    serviceQueueApply() {
        printf 'queueApply\n' >>"${callLog}"
        SERVICE_ACTIONS=
        return 0
    }
    checkGFWStatue() {
        printf 'reached\n' >"${reachedFile}"
        [[ "${mode}" != "check-gfw-fail" ]]
    }
    showAccounts() { printf 'reached\n' >"${reachedFile}"; return 0; }
    handleNginx() {
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ -n "${2:-}" ]] && printf 'nginx-mode:%s\n' "$*" >>"${serviceLog}"
        [[ "${mode}" == "nginx-stop-fail" && "$1" == "stop" ]] && return 1
        [[ "${mode}" == "nginx-start-fail" && "$1" == "start" && "${2:-}" != "restore" ]] && return 1
        [[ "$1" == "stop" ]] && nginxRuntimeState=false
        [[ "$1" == "start" ]] && nginxRuntimeState=true
        return 0
    }
    nginxRunning() { [[ "${nginxRuntimeState}" == "true" ]]; }
    xrayRunning() { [[ "${xrayRuntimeState}" == "true" ]]; }
    singBoxRunning() { [[ "${singBoxRuntimeState}" == "true" ]]; }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "xray-stop-fail" && "$1" == "stop" ]] && return 1
        [[ "${mode}" == "xray-start-fail" && "$1" == "start" ]] && return 1
        [[ "$1" == "stop" ]] && xrayRuntimeState=false
        [[ "$1" == "start" ]] && xrayRuntimeState=true
        return 0
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "$1" == "stop" ]] && singBoxRuntimeState=false
        [[ "$1" == "start" ]] && singBoxRuntimeState=true
        return 0
    }

    resetInstallServiceFixture() {
        mode=$1
        : >"${serviceLog}"
        : >"${callLog}"
        : >"${errorLog}"
        : >"${firewallLog}"
        rm -f "${reachedFile}"
        rm -f "${firewallState}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        btDomain=
        realityOnlyWithDomain=
        currentHost=install.example.com
        domain=install.example.com
        AUTO_ENTRY_HOST=
        AUTO_DOMAIN=
        AUTO_REALITY_DOMAIN=
        realityEntryHost=
        nginxRuntimeState=true
        xrayRuntimeState=false
        singBoxRuntimeState=false
        SERVICE_ACTIONS=
        rm -f "${entryHostFile}"
    }

    resetInstallServiceFixture nginx-stop-fail
    regressionExpectStatus 0 installXrayReality >/dev/null 2>&1
    ! grep -q '^nginx:' "${serviceLog}"
    grep -q '^installXray:' "${callLog}"
    ! grep -q '^wg-refresh$' "${callLog}"
    ! grep -q '^initTLS:' "${callLog}"
    ! grep -q '^installTLS:' "${callLog}"
    ! grep -q '^nginxBlog:' "${callLog}"
    ! grep -q '^cron:' "${callLog}"
    ! grep -q '^clean-nginx$' "${callLog}"
    [[ -e "${reachedFile}" ]]
    [[ "$(<"${entryHostFile}")" == "install.example.com" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture singbox-reality-grpc
    regressionExpectStatus 0 customSingBoxInstall 26 >/dev/null 2>&1
    ! grep -q '^nginx:' "${serviceLog}"
    ! grep -q '^initTLS:' "${callLog}"
    ! grep -q '^installTLS:' "${callLog}"
    ! grep -q '^nginxBlog:' "${callLog}"
    ! grep -q '^cron:' "${callLog}"
    grep -q '^installSingBox:' "${callLog}"
    grep -qx 'cleanup:xrayDel' "${callLog}"
    [[ -e "${reachedFile}" ]]
    [[ "$(<"${entryHostFile}")" == "install.example.com" ]]

    resetInstallServiceFixture path-fail
    regressionExpectStatus 1 customXrayInstall 21 >/dev/null 2>&1
    grep -qx 'path:4' "${callLog}"
    ! grep -q '^nginxBlog:' "${callLog}"
    ! grep -q '^installXray:' "${callLog}"

    resetInstallServiceFixture blog-fail
    regressionExpectStatus 1 customXrayInstall 21 >/dev/null 2>&1
    grep -qx 'nginxBlog:6' "${callLog}"
    ! grep -q '^installXray:' "${callLog}"

    resetInstallServiceFixture cron-fail
    regressionExpectStatus 1 customXrayInstall 21 >/dev/null 2>&1
    grep -qx 'cron:10' "${callLog}"
    ! grep -q '^queueApply$' "${callLog}"
    [[ ! -e "${reachedFile}" ]]

    resetInstallServiceFixture wg-refresh-fail
    regressionExpectStatus 0 installXrayReality >/dev/null 2>&1
    ! grep -q '^nginx:' "${serviceLog}"
    ! grep -q '^wg-refresh$' "${callLog}"
    grep -q '^installXray:' "${callLog}"
    [[ "${nginxRuntimeState}" == "true" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture xray-config-fail
    SERVICE_ACTIONS="existing:start"
    regressionExpectStatus 1 installXrayReality >/dev/null 2>&1
    ! grep -q '^nginx:' "${serviceLog}"
    ! grep -q '^wg-refresh$' "${callLog}"
    ! grep -q '^queueRefresh:nginx$' "${callLog}"
    grep -qx 'initXrayConfig:custom 3' "${callLog}"
    ! grep -q '^cleanup:' "${callLog}"
    [[ "${nginxRuntimeState}" == "true" ]]
    [[ "${SERVICE_ACTIONS}" == "existing:start" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    for mode in xray-install-exit xray-service-fail; do
        resetInstallServiceFixture "${mode}"
        regressionExpectStatus 1 installXrayReality >/dev/null 2>&1
        ! grep -q '^nginx:' "${serviceLog}"
        ! grep -q '^wg-refresh$' "${callLog}"
        ! grep -q '^queueRefresh:nginx$' "${callLog}"
        grep -q '^installXray:' "${callLog}"
        if [[ "${mode}" == "xray-service-fail" ]]; then
            grep -q '^installXrayService:' "${callLog}"
        else
            ! grep -q '^installXrayService:' "${callLog}"
        fi
        [[ "${nginxRuntimeState}" == "true" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    done

    resetInstallServiceFixture check-gfw-fail
    regressionExpectStatus 1 installXrayReality >/dev/null 2>&1
    ! grep -q '^nginx:' "${serviceLog}"
    [[ "${nginxRuntimeState}" == "true" ]] || return 1

    resetInstallServiceFixture nginx-start-fail
    regressionExpectStatus 1 customXrayInstall 21 >/dev/null 2>&1
    grep -qx 'nginx:start:true' "${serviceLog}"
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    [[ "${nginxRuntimeState}" == "true" ]] || return 1
    ! grep -q '^installXray:' "${callLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture xray-service-fail
    btDomain=panel.example.com
    regressionExpectStatus 1 customXrayInstall 21 >/dev/null 2>&1
    grep -qx 'customPort' "${callLog}"
    grep -qx 'ufw:2443:tcp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    resetInstallServiceFixture redirect-fail
    regressionExpectStatus 1 customXrayInstall 21 >/dev/null 2>&1
    grep -qx 'redirect' "${callLog}"
    ! grep -q '^nginx:start:' "${serviceLog}"
    ! grep -q '^installXray:' "${callLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture no-local-cert
    regressionExpectStatus 0 customXrayInstall 2 >/dev/null 2>&1
    ! grep -q '^clean-nginx$' "${callLog}"
    ! grep -q '^initTLS:' "${callLog}"
    ! grep -q '^installTLS:' "${callLog}"
    ! grep -q '^nginxBlog:' "${callLog}"
    ! grep -q '^cron:' "${callLog}"
    ! grep -q '^nginx:' "${serviceLog}"
    grep -q '^installXray:' "${callLog}"
    [[ -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture xray-start-fail
    regressionExpectStatus 1 xrayCoreInstall >/dev/null 2>&1
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}" || return 1
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    [[ "${nginxRuntimeState}" == "true" ]] || return 1
    grep -q '^installXray:' "${callLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture redirect-fail
    regressionExpectStatus 1 xrayCoreInstall >/dev/null 2>&1
    grep -qx 'redirect' "${callLog}"
    ! grep -q '^xray:stop:' "${serviceLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture nginx-stop-fail
    regressionExpectStatus 1 singBoxInstall >/dev/null 2>&1
    grep -qx 'nginx:stop:true' "${serviceLog}"
    ! grep -q '^installSingBox:' "${callLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture blog-fail
    regressionExpectStatus 1 xrayCoreInstall >/dev/null 2>&1
    grep -qx 'nginxBlog:10' "${callLog}"
    ! grep -q '^redirect$' "${callLog}"

    resetInstallServiceFixture cron-fail
    regressionExpectStatus 1 singBoxInstall >/dev/null 2>&1
    grep -qx 'cron:8' "${callLog}"
    grep -qx 'nginx:stop:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}" || return 1
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    [[ "${nginxRuntimeState}" == "true" ]] || return 1
    ! grep -q '^queueApply$' "${callLog}"
)

runSingBoxMergeConfigTransactionRegression() (
    local root="${TMP_DIR}/sing-box-merge-config-transaction"
    local confDir="${root}/conf"
    local shardDir="${confDir}/config"
    local binary="${root}/fake-sing-box"
    local outputFile="${confDir}/config.json"
    local checkLog="${root}/check.log"
    local commitMarker="${root}/commit.log"
    local logFile="${root}/merge.log"
    local rc

    mkdir -p "${shardDir}"
    cat >"${binary}" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "check" ]]; then
    shift
    config=
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        -c)
            config=$2
            shift 2
            ;;
        *)
            shift
            ;;
        esac
    done
    printf 'check:%s\n' "${config}" >>"${PADM_FAKE_SINGBOX_CHECK_LOG}"
    [[ "${PADM_FAKE_SINGBOX_CHECK_MODE:-success}" == "success" ]]
    exit
fi
[[ "$1" == "merge" ]] || exit 2
output=$2
shift 2
dest=
while [[ "$#" -gt 0 ]]; do
    case "$1" in
    -D)
        dest=$2
        shift 2
        ;;
    -C)
        shift 2
        ;;
    *)
        shift
        ;;
    esac
done
[[ -n "${dest}" ]] || exit 2
case "${PADM_FAKE_SINGBOX_MERGE_MODE:-success}" in
fail)
    exit 1
    ;;
empty)
    : >"${dest%/}/${output}"
    exit 0
    ;;
*)
    printf '{"merged":true}\n' >"${dest%/}/${output}"
    exit 0
    ;;
esac
SH
    chmod +x "${binary}"
    PADM_SINGBOX_BINARY="${binary}"
    singBoxConfigPath="${shardDir}/"
    export PADM_FAKE_SINGBOX_CHECK_LOG="${checkLog}"

    printf '{"old":true}\n' >"${outputFile}"
    export PADM_FAKE_SINGBOX_MERGE_MODE=fail
    regressionExpectStatus 1 singBoxMergeConfig >/dev/null 2>&1
    [[ "$(<"${outputFile}")" == '{"old":true}' ]]
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null

    export PADM_FAKE_SINGBOX_MERGE_MODE=empty
    regressionExpectStatus 1 singBoxMergeConfig >/dev/null 2>&1
    [[ "$(<"${outputFile}")" == '{"old":true}' ]]
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null

    export PADM_FAKE_SINGBOX_MERGE_MODE=success
    mv() {
        local args=("$@")
        if [[ "${args[$((${#args[@]} - 1))]}" == "${outputFile}" ]]; then
            printf 'commit\n' >"${commitMarker}"
            return 1
        fi
        command mv "$@"
    }
    set +e
    (
        singBoxMergeConfig >/dev/null 2>&1
    )
    rc=$?
    set -e
    unset -f mv
    [[ "${rc}" == "1" ]]
    [[ -e "${commitMarker}" ]]
    [[ "$(<"${outputFile}")" == '{"old":true}' ]]
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null

    singBoxMergeConfig
    [[ "$(<"${outputFile}")" == '{"merged":true}' ]]
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null

    printf '{"runtime":true}\n' >"${outputFile}"
    : >"${checkLog}"
    : >"${logFile}"
    export PADM_FAKE_SINGBOX_MERGE_MODE=success
    export PADM_FAKE_SINGBOX_CHECK_MODE=success
    singBoxMergeConfigForValidation "${binary}" "${logFile}" check
    [[ "$(<"${outputFile}")" == '{"runtime":true}' ]]
    grep -q '^check:' "${checkLog}"
    ! grep -qx "check:${outputFile}" "${checkLog}"
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null

    : >"${checkLog}"
    export PADM_FAKE_SINGBOX_CHECK_MODE=fail
    regressionExpectStatus 1 singBoxMergeConfigForValidation "${binary}" "${logFile}" check >/dev/null 2>&1
    [[ "$(<"${outputFile}")" == '{"runtime":true}' ]]
    grep -q '^check:' "${checkLog}"
    ! grep -qx "check:${outputFile}" "${checkLog}"
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null
)

runSingBoxUninstallFailurePropagationRegression() (
    local root="${TMP_DIR}/sing-box-uninstall-failure"
    local configDir="${root}/conf/config/"
    local serviceLog="${root}/service.log"
    local firewallLog="${root}/firewall.log"
    local errorLog="${root}/error.log"
    local startCalls=0
    local rc oldConfig

    mkdir -p "${configDir}"
    printf '{"inbounds":[{"type":"tuic","listen_port":26451}]}\n' >"${configDir}09_tuic_inbounds.json"
    printf '{"inbounds":[{"type":"vless","listen_port":2443}]}\n' >"${configDir}02_other_inbounds.json"
    printf '{"inbounds":[{"type":"tuic","listen_port":26451}]}\n' >"${configDir}config.json"
    oldConfig=$(<"${configDir}09_tuic_inbounds.json")
    : >"${serviceLog}"
    : >"${firewallLog}"
    : >"${errorLog}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    PADM_SINGBOX_BINARY="${root}/missing-sing-box"
    PADM_SINGBOX_SYSTEMD_SERVICE_FILE="${root}/sing-box.service"

    singBoxConfigPath="${configDir}"
    readInstallType() { singBoxConfigPath="${configDir}"; }
    readPortHopping() {
        tuicPortHoppingStart=
        tuicPortHoppingEnd=
    }
    singBoxRunning() { return 0; }
    coreStartupServiceEnabled() { return 1; }
    runCoreServiceActionAllowFailure() {
        printf '%s:%s\n' "$1" "$2" >>"${serviceLog}"
        if [[ "$2" == "start" ]]; then
            startCalls=$((startCalls + 1))
            [[ "${startCalls}" != "1" ]]
        fi
    }
    denyPort() {
        printf 'deny:%s:%s\n' "$1" "${2:-tcp}" >>"${firewallLog}"
    }

    if unInstallSingBox tuic; then
        rc=0
    else
        rc=$?
    fi
    [[ "${rc}" == "1" ]]
    [[ "$(<"${configDir}09_tuic_inbounds.json")" == "${oldConfig}" ]]
    [[ -f "${configDir}config.json" ]]
    [[ "${startCalls}" == "2" ]]
    [[ ! -s "${firewallLog}" ]]
    grep -q 'sing-box 服务重启失败，已恢复旧配置和服务状态' "${errorLog}"

    printf '{"inbounds":[{"type":"tuic","listen_port":26451}]}\n' >"${configDir}09_tuic_inbounds.json"
    rm -f "${configDir}config.json"
    : >"${serviceLog}"
    : >"${firewallLog}"
    : >"${errorLog}"
    singBoxRunning() { return 1; }
    runCoreServiceActionAllowFailure() { return 0; }
    readPortHopping() {
        tuicPortHoppingStart=33000
        tuicPortHoppingEnd=33005
    }
    deletePortHoppingRules() {
        printf 'hopping:%s:%s:%s:%s\n' "$1" "$2" "$3" "$4" >>"${firewallLog}"
    }
    unInstallSingBox tuic
    [[ ! -e "${configDir}09_tuic_inbounds.json" ]]
    [[ ! -e "${configDir}config.json" ]]
    grep -qx 'hopping:tuic:33000:33005:26451' "${firewallLog}"
    grep -qx 'deny:26451:tcp' "${firewallLog}"
    grep -qx 'deny:26451:udp' "${firewallLog}"

    local alpineConfigDir="${root}/alpine/conf/config/"
    local openRcService="${root}/alpine/sing-box"
    local rcUpdateLog="${root}/alpine/rc-update.log"
    mkdir -p "${alpineConfigDir}"
    printf '{"inbounds":[{"type":"hysteria2","listen_port":16295}]}\n' >"${alpineConfigDir}06_hysteria2_inbounds.json"
    printf '{"inbounds":[{"type":"hysteria2","listen_port":16295}]}\n' >"${alpineConfigDir}config.json"
    printf '#!/sbin/openrc-run\n' >"${openRcService}"
    : >"${rcUpdateLog}"
    : >"${firewallLog}"
    singBoxConfigPath="${alpineConfigDir}"
    PADM_SINGBOX_OPENRC_SERVICE_FILE="${openRcService}"
    release=alpine
    readInstallType() { singBoxConfigPath=; }
    readPortHopping() {
        hysteria2PortHoppingStart=
        hysteria2PortHoppingEnd=
    }
    coreStartupServiceEnabled() { return 0; }
    rc-update() {
        printf '%s\n' "$*" >>"${rcUpdateLog}"
    }
    cleanCoreInstallDirectory() { return 0; }
    unInstallSingBox hysteria2
    grep -qx 'del sing-box default' "${rcUpdateLog}"
    [[ ! -e "${openRcService}" ]]
    grep -qx 'deny:16295:tcp' "${firewallLog}"
    grep -qx 'deny:16295:udp' "${firewallLog}"

    singBoxConfigPath=
    release=debian
    : >"${serviceLog}"
    : >"${errorLog}"
    handleSingBox() {
        printf 'handle:%s\n' "$1" >>"${serviceLog}"
        return 1
    }
    runCoreServiceActionAllowFailure() { "$@"; }

    if unInstallSingBox >/dev/null 2>&1; then
        rc=0
    else
        rc=$?
    fi
    [[ "${rc}" == "1" ]]
    grep -qx 'handle:stop' "${serviceLog}"
    grep -q 'sing-box 服务停止失败，已取消卸载' "${errorLog}"
)

runSingBoxLogTransactionRegression() (
    local root="${TMP_DIR}/sing-box-log-transaction"
    local targetPath="${root}/conf/config/log.json"
    local serviceLog="${root}/service.log"
    local errorLog="${root}/error.log"
    local applyMode rc keptBackup

    set +e
    mkdir -p "$(dirname "${targetPath}")" || return 1
    export PADM_SINGBOX_LOG_CONFIG_FILE="${targetPath}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    serviceQueueRestart() {
        printf 'restart:%s\n' "$1" >>"${serviceLog}"
        return 0
    }
    serviceQueueApply() {
        printf 'apply:%s\n' "${applyMode}" >>"${serviceLog}"
        [[ "${applyMode}" == "fail" ]] && return 1
        return 0
    }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    runSingBoxLogCase() {
        local disabled=$1
        local expectedRc=$2
        local rcFile="${root}/sing-box-log.rc"
        PADM_REGRESSION_APPLY_MODE="${applyMode}" \
            PADM_SINGBOX_LOG_CONFIG_FILE="${targetPath}" \
            bash -c '
                set +e
                source "$1/shell/core/runtime.sh"
                source "$1/shell/core/services.sh"
                source "$1/shell/core/cores.sh"
                serviceLog=$2
                errorLog=$3
                disabled=$4
                rcFile=$5
                serviceQueueRestart() {
                    printf "restart:%s\n" "$1" >>"${serviceLog}"
                    return 0
                }
                serviceQueueApply() {
                    printf "apply:%s\n" "${PADM_REGRESSION_APPLY_MODE}" >>"${serviceLog}"
                    [[ "${PADM_REGRESSION_APPLY_MODE}" == "fail" ]] && return 1
                    return 0
                }
                errorCard() { printf "%s\n" "$*" >>"${errorLog}"; }
                singBoxLog "${disabled}" >/dev/null 2>&1
                printf "%s\n" "$?" >"${rcFile}"
            ' _ "${PROJECT_ROOT}" "${serviceLog}" "${errorLog}" "${disabled}" "${rcFile}" || return 1
        rc=$(<"${rcFile}") || return 1
        if [[ "${rc}" != "${expectedRc}" ]]; then
            printf 'singBoxLog rc mismatch: expected=%s actual=%s\n' "${expectedRc}" "${rc}" >&2
            return 1
        fi
        return 0
    }

    printf '{"log":{"disabled":true,"level":"warning"}}\n' >"${targetPath}" || return 1
    : >"${serviceLog}" || return 1
    : >"${errorLog}" || return 1
    applyMode=fail
    runSingBoxLogCase false 1 || return 1
    jq -e '.log.disabled == true and .log.level == "warning"' "${targetPath}" >/dev/null || return 1
    grep -qx 'restart:sing-box' "${serviceLog}" || return 1
    grep -qx 'apply:fail' "${serviceLog}" || return 1
    grep -q 'sing-box 日志配置重载失败' "${errorLog}" || return 1
    ! compgen -G "$(dirname "${targetPath}")/.log.json.*" >/dev/null || return 1
    ! compgen -G "${targetPath}.bak.*" >/dev/null || return 1

    rm -f "${targetPath}" || return 1
    : >"${serviceLog}" || return 1
    : >"${errorLog}" || return 1
    applyMode=fail
    runSingBoxLogCase false 1 || return 1
    [[ ! -e "${targetPath}" ]] || return 1
    grep -qx 'restart:sing-box' "${serviceLog}" || return 1
    grep -qx 'apply:fail' "${serviceLog}" || return 1
    grep -q 'sing-box 日志配置重载失败' "${errorLog}" || return 1
    ! compgen -G "$(dirname "${targetPath}")/.log.json.*" >/dev/null || return 1
    ! compgen -G "${targetPath}.bak.*" >/dev/null || return 1

    printf '{"log":{"disabled":true,"level":"warning"}}\n' >"${targetPath}" || return 1
    : >"${serviceLog}" || return 1
    : >"${errorLog}" || return 1
    applyMode=fail
    PADM_REGRESSION_APPLY_MODE="${applyMode}" \
        PADM_SINGBOX_LOG_CONFIG_FILE="${targetPath}" \
        bash -c '
            set +e
            source "$1/shell/core/runtime.sh"
            source "$1/shell/core/services.sh"
            source "$1/shell/core/cores.sh"
            serviceLog=$2
            errorLog=$3
            rcFile=$4
            serviceQueueRestart() {
                printf "restart:%s\n" "$1" >>"${serviceLog}"
                return 0
            }
            serviceQueueApply() {
                printf "apply:%s\n" "${PADM_REGRESSION_APPLY_MODE}" >>"${serviceLog}"
                return 1
            }
            errorCard() { printf "%s\n" "$*" >>"${errorLog}"; }
            restoreManagedFileFromBackup() { return 1; }
            singBoxLog false >/dev/null 2>&1
            printf "%s\n" "$?" >"${rcFile}"
        ' _ "${PROJECT_ROOT}" "${serviceLog}" "${errorLog}" "${root}/sing-box-log-restore-fail.rc" || return 1
    rc=$(<"${root}/sing-box-log-restore-fail.rc") || return 1
    [[ "${rc}" == "1" ]] || return 1
    jq -e '.log.disabled == false and .log.level == "debug" and .log.output == "/etc/padm/sing-box/conf/box.log"' "${targetPath}" >/dev/null || return 1
    grep -qx 'restart:sing-box' "${serviceLog}" || return 1
    grep -qx 'apply:fail' "${serviceLog}" || return 1
    grep -q '旧配置恢复失败' "${errorLog}" || return 1
    keptBackup=$(compgen -G "${targetPath}.bak.*" | head -n 1) || true
    [[ -n "${keptBackup}" && -f "${keptBackup}" ]] || return 1
    jq -e '.log.disabled == true and .log.level == "warning"' "${keptBackup}" >/dev/null || return 1
    rm -f "${keptBackup}" || return 1
    ! compgen -G "$(dirname "${targetPath}")/.log.json.*" >/dev/null || return 1

    : >"${serviceLog}" || return 1
    : >"${errorLog}" || return 1
    applyMode=success
    runSingBoxLogCase false 0 || return 1
    jq -e '.log.disabled == false and .log.level == "debug" and .log.output == "/etc/padm/sing-box/conf/box.log"' "${targetPath}" >/dev/null || return 1
    grep -qx 'restart:sing-box' "${serviceLog}" || return 1
    grep -qx 'apply:success' "${serviceLog}" || return 1
    [[ ! -s "${errorLog}" ]] || return 1
    ! compgen -G "$(dirname "${targetPath}")/.log.json.*" >/dev/null || return 1
    ! compgen -G "${targetPath}.bak.*" >/dev/null || return 1
    return 0
)

runSingBoxProtocolReloadFailureRegression() (
    local root="${TMP_DIR}/sing-box-protocol-reload-failure"
    local reachedFile="${root}/accounts"
    local callLog="${root}/calls.log"
    local anyTlsLog="${root}/anytls.log"
    local tuicRc hysteriaRc

    mkdir -p "${root}"
    : >"${callLog}"
    : >"${anyTlsLog}"

    (
        local dependencyRoot="${root}/reality-tls"
        local certificateLog="${dependencyRoot}/certificate.log"
        local transactionLog="${dependencyRoot}/transaction.log"
        local xrayLog="${dependencyRoot}/xray.log"
        local certificateAvailable=false confirmValue=y rc

        mkdir -p "${dependencyRoot}"
        : >"${certificateLog}"
        : >"${transactionLog}"
        : >"${xrayLog}"
        coreInstallType=1
        selectCoreType=1
        currentInstallProtocolType=',1,'
        protocolSelectionNeedsCertificate() { return 1; }
        singBoxLocalCertificateAvailable() { [[ "${certificateAvailable}" == "true" ]]; }
        autoConfirm() { printf -v "$4" '%s' "${confirmValue}"; }
        installAcmeTool() { printf 'acme\n' >>"${certificateLog}"; }
        nginxRunning() { return 0; }
        xrayRunning() { return 0; }
        singBoxRunning() { return 1; }
        initTLSNginxConfig() {
            [[ -z "${selectCoreType}" ]] || return 1
            printf 'init\n' >>"${certificateLog}"
        }
        installTLS() {
            printf 'tls\n' >>"${certificateLog}"
            certificateAvailable=true
        }
        installCronTLS() { printf 'cron\n' >>"${certificateLog}"; }
        restoreServicesAfterTLSRenewal() { printf 'restore:%s\n' "$*" >>"${certificateLog}"; }
        customXrayInstall() { printf '%s\n' "$*" >>"${xrayLog}"; return 1; }
        coreInstallConfigTransaction() { printf 'transaction:%s\n' "$1" >>"${transactionLog}"; }

        certificateAvailable=true
        singBoxHysteria2Install >/dev/null 2>&1
        grep -qx 'transaction:sing-box' "${transactionLog}"
        [[ ! -s "${certificateLog}" && ! -s "${xrayLog}" ]]
        [[ "${currentInstallProtocolType}" == ',1,' ]]

        : >"${certificateLog}"
        : >"${transactionLog}"
        certificateAvailable=false
        confirmValue=y
        singBoxHysteria2Install >/dev/null 2>&1
        grep -qx 'transaction:sing-box' "${transactionLog}"
        [[ "$(tr '\n' ',' <"${certificateLog}")" == 'acme,init,tls,cron,restore:true true false,' ]]
        [[ ! -s "${xrayLog}" ]]
        [[ "${selectCoreType}" == "1" && "${currentInstallProtocolType}" == ',1,' ]]

        : >"${certificateLog}"
        : >"${transactionLog}"
        certificateAvailable=false
        confirmValue=n
        regressionExpectStatus 1 singBoxHysteria2Install >/dev/null 2>&1
        [[ ! -s "${certificateLog}" && ! -s "${transactionLog}" && ! -s "${xrayLog}" ]]
        [[ "${currentInstallProtocolType}" == ',1,' ]]
    )

    currentInstallProtocolType=',4,'
    installSingBox() {
        printf 'install:%s\n' "$*" >>"${anyTlsLog}"
        return 1
    }
    set +e
    (singBoxTuicInstallApply >/dev/null 2>&1)
    tuicRc=$?
    (singBoxHysteria2InstallApply >/dev/null 2>&1)
    hysteriaRc=$?
    set -e
    [[ "${tuicRc}" == "1" ]]
    [[ "${hysteriaRc}" == "1" ]]
    [[ "$(wc -l <"${anyTlsLog}" | tr -d ' ')" == "2" ]]

    currentInstallProtocolType=
    protocolSelectionNeedsCertificate() { return 1; }
    set +e
    (singBoxTuicInstall >/dev/null 2>&1)
    tuicRc=$?
    (singBoxHysteria2Install >/dev/null 2>&1)
    hysteriaRc=$?
    set -e
    [[ "${tuicRc}" == "1" ]]
    [[ "${hysteriaRc}" == "1" ]]

    protocolSelectionNeedsCertificate() { return 0; }
    coreInstallConfigTransaction() {
        local core=$1
        local operation=$2
        shift 2
        printf 'transaction:%s\n' "${core}" >>"${callLog}"
        "${operation}" "$@"
    }
    installSingBox() {
        printf 'install:%s\n' "$*" >>"${callLog}"
        return 0
    }
    initSingBoxConfig() {
        printf 'config:%s\n' "$*" >>"${callLog}"
        return 0
    }
    installSingBoxService() {
        printf 'service:%s\n' "$*" >>"${callLog}"
        return 0
    }
    reloadCore() {
        printf 'reload\n' >>"${callLog}"
        return 99
    }
    serviceQueueRestart() {
        printf 'restart:%s\n' "$1" >>"${callLog}"
        return 0
    }
    serviceQueueApply() {
        printf 'apply\n' >>"${callLog}"
        return 1
    }
    showAccounts() {
        printf 'accounts\n' >"${reachedFile}"
        return 0
    }

    regressionExpectStatus 1 singBoxTuicInstall >/dev/null 2>&1
    grep -qx 'transaction:sing-box' "${callLog}"
    grep -qx 'config:custom 2 true' "${callLog}"
    grep -qx 'restart:sing-box' "${callLog}"
    grep -qx 'apply' "${callLog}"
    ! grep -qx 'reload' "${callLog}"
    ! grep -qx 'restart:xray' "${callLog}"
    [[ ! -e "${reachedFile}" ]]

    : >"${callLog}"
    rm -f "${reachedFile}"
    regressionExpectStatus 1 singBoxHysteria2Install >/dev/null 2>&1
    grep -qx 'transaction:sing-box' "${callLog}"
    grep -qx 'config:custom 2 true' "${callLog}"
    grep -qx 'restart:sing-box' "${callLog}"
    grep -qx 'apply' "${callLog}"
    ! grep -qx 'reload' "${callLog}"
    ! grep -qx 'restart:xray' "${callLog}"
    [[ ! -e "${reachedFile}" ]]

    (
        local transactionRoot="${root}/transaction"
        local configBackup="${transactionRoot}/config-backup"
        local serviceBackup="${transactionRoot}/service-backup"
        local transactionLog="${transactionRoot}/transaction.log"
        local transactionRc
        mkdir -p "${transactionRoot}"
        # Reload the original transaction after the caller-order mock above.
        source "${PROJECT_ROOT}/shell/core/core_templates.sh"
        coreTemplateConfigBackupCreate() {
            printf -v "$1" '%s' "${configBackup}"
            return 0
        }
        checkLogBackupRestore() {
            printf 'config-restore\n' >>"${transactionLog}"
            return 0
        }
        padmRemoveCleanupPath() {
            printf 'cleanup:%s\n' "$1" >>"${transactionLog}"
            return 0
        }
        padmForgetCleanupPath() {
            printf 'forget:%s\n' "$1" >>"${transactionLog}"
            return 0
        }
        xrayRunning() { return 1; }
        singBoxRunning() { return 1; }
        restoreCoreStartupServiceInstall() {
            printf 'service-restore:%s:%s\n' "$2" "$3" >>"${transactionLog}"
            return 0
        }
        failingInstall() {
            coreInstallServiceBackupFinalize "${serviceBackup}" sing-box false
            return 7
        }
        regressionExpectStatus 7 coreInstallConfigTransaction sing-box failingInstall >/dev/null 2>&1
        grep -qx 'config-restore' "${transactionLog}"
        grep -qx 'service-restore:sing-box:false' "${transactionLog}"
    )
)

runGeoUpdateReloadFailureRegression() (
    local root="${TMP_DIR}/geo-update-reload-failure"
    local callLog="${root}/calls.log"
    local statusLog="${root}/status.log"
    local geoVersionFile="${root}/geo-version.txt"
    local geoCronLog="${root}/geo-cron.log"
    local handlerSource
    local mode=reload-fail
    local rc

    mkdir -p "${root}"
    : >"${callLog}"
    : >"${statusLog}"
    printf 'old-version\n' >"${geoVersionFile}"
    ensureXrayGeoFiles() {
        printf 'geo:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" == "ensure-fail" ]] && return 1
        printf 'new-version\n' >"${geoVersionFile}"
        return 0
    }
    xrayGeoDisplayVersion() {
        cat "${geoVersionFile}"
    }
    reloadCore() {
        printf 'reload\n' >>"${callLog}"
        return 1
    }
    statusCard() {
        printf '%s\n' "$*" >>"${statusLog}"
    }

    mode=ensure-fail
    regressionExpectStatus 1 updateGeoSite >/dev/null 2>&1
    grep -qx 'geo:/etc/padm/xray force' "${callLog}"
    ! grep -q '^reload$' "${callLog}"

    mode=reload-fail
    : >"${callLog}"
    printf 'old-version\n' >"${geoVersionFile}"
    regressionExpectStatus 1 updateGeoSite >/dev/null 2>&1
    grep -qx 'geo:/etc/padm/xray force' "${callLog}"
    grep -qx 'reload' "${callLog}"
    grep -q '核心重载失败' "${statusLog}"
    ! grep -q '更新完毕' "${statusLog}"

    handlerSource=$(awk '/^handleScriptCommand\(\)/,/^}/ { print }' "${PROJECT_ROOT}/install.sh")
    handlerSource=${handlerSource//\/etc\/padm\/crontab_updateGeoSite.log/${geoCronLog}}
    eval "${handlerSource}"
    updateGeoSite() {
        printf 'geo-failed\n'
        return 23
    }
    cronName=UpdateGeo
    : >"${geoCronLog}"
    set +e
    (handleScriptCommand)
    rc=$?
    set -e
    [[ "${rc}" == "23" ]]
    ! grep -q 'geo更新日期:' "${geoCronLog}"

    updateGeoSite() {
        printf 'geo-updated\n'
        return 0
    }
    : >"${geoCronLog}"
    set +e
    (handleScriptCommand)
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
    grep -q '^geo-updated$' "${geoCronLog}"
    grep -q '^geo更新日期:' "${geoCronLog}"
)

runReloadCorePropagationRegression() (
    local root="${TMP_DIR}/reload-core-propagation"
    local alpnConfig="${root}/alpn.json"
    local vlessConfig="${root}/vless.json"
    local vlessState="${root}/vless-state.json"
    local fakeXray="${root}/xray"
    local refreshMarker="${root}/refresh"
    local subscribeMarker="${root}/subscribe"
    local reloadLog="${root}/reloads"
    local originalContent rc

    mkdir -p "${root}/nginx"
    errorCard() { return 0; }
    echoContent() { return 0; }
    menuLine() { return 0; }
    menuClose() { return 0; }
    cleanDirectoryContent() { return 0; }

    cat >"${alpnConfig}" <<'JSON'
{"inbounds":[{"streamSettings":{"tlsSettings":{"alpn":["http/1.1"]}}}]}
JSON
    traditionalTlsFallbackConfigFile() { printf '%s\n' "${alpnConfig}"; }
    padmCreateTempFileForTarget() {
        local -n targetRef=$1
        local targetFile=$2
        targetRef="${targetFile}.tmp"
        return 0
    }
    padmRemoveCleanupPath() { rm -f "$1"; }
    commitGeneratedJsonFile() {
        local tmpFile=$1
        local targetFile=$2
        mv "${tmpFile}" "${targetFile}"
    }
    reloadCore() {
        printf 'reload\n' >>"${reloadLog}"
        return 1
    }

    originalContent=$(<"${alpnConfig}")
    regressionExpectStatus 1 applyTraditionalTlsAlpn '["h2","http/1.1"]' >/dev/null 2>&1
    [[ "$(<"${alpnConfig}")" == "${originalContent}" ]]
    [[ "$(wc -l <"${reloadLog}" | tr -d ' ')" == "2" ]]

    printf '%s\n' "${originalContent}" >"${alpnConfig}"
    rm -f "${alpnConfig}.alpn.bak"
    (
        cp() {
            if [[ "$1" == "-p" && "$2" == "${alpnConfig}.alpn.bak" && "$3" == "${alpnConfig}.tmp" ]]; then
                return 1
            fi
            command cp "$@"
        }
        regressionExpectStatus 1 applyTraditionalTlsAlpn '["h2","http/1.1"]' >/dev/null 2>&1
        jq -e '.inbounds[0].streamSettings.tlsSettings.alpn == ["h2","http/1.1"]' "${alpnConfig}" >/dev/null
        [[ "$(<"${alpnConfig}.alpn.bak")" == "${originalContent}" ]]
    ) || return 1
    printf '%s\n' "${originalContent}" >"${alpnConfig}"
    rm -f "${alpnConfig}.alpn.bak"

    cat >"${fakeXray}" <<'SH'
#!/usr/bin/env bash
case "$1" in
--version)
    printf 'Xray 25.9.5\n'
    ;;
vlessenc)
    printf '{"encryption":"mlkem768x25519plus.native.enc","decryption":"mlkem768x25519plus.native.dec"}\n'
    ;;
-test)
    exit 0
    ;;
esac
SH
    chmod +x "${fakeXray}"
    cat >"${vlessConfig}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"id":"u","flow":"xtls-rprx-vision"}],"decryption":"none","fallbacks":[]}}]}
JSON
    originalContent=$(<"${vlessConfig}")
    coreInstallType=1
    PADM_XRAY_BINARY="${fakeXray}"
    PADM_XRAY_CONF_DIR="${root}"
    PADM_VLESS_REALITY_CONFIG_FILE="${vlessConfig}"
    PADM_VLESS_XHTTP_CONFIG_FILE="${root}/missing-xhttp.json"
    PADM_VLESS_ENCRYPTION_STATE_FILE="${vlessState}"
    readNginxSubscribe() {
        printf 'refresh\n' >"${refreshMarker}"
        subscribePort=443
        nginxConfigPath="${root}/nginx/"
    }
    subscribe() { return 0; }

    rm -f "${refreshMarker}" "${vlessState}" "${reloadLog}"
    regressionExpectStatus 1 setVlessRealityEncryption enable >/dev/null 2>&1
    [[ "$(<"${vlessConfig}")" == "${originalContent}" ]]
    [[ ! -e "${vlessState}" ]]
    [[ ! -e "${refreshMarker}" ]]
    [[ "$(wc -l <"${reloadLog}" | tr -d ' ')" == "2" ]]

    printf '%s\n' "${originalContent}" >"${vlessConfig}"
    rm -f "${refreshMarker}" "${vlessState}" "${vlessConfig}.vlessenc.bak" "${vlessState}.bak" "${vlessState}.tmp"
    (
        cp() {
            if [[ "$1" == "-p" && "$2" == "${vlessConfig}" && "$3" == "${vlessConfig}.vlessenc.bak.tmp" ]]; then
                return 1
            fi
            command cp "$@"
        }
        reloadCore() { return 0; }
        regressionExpectStatus 1 setVlessRealityEncryption enable >/dev/null 2>&1
        [[ "$(<"${vlessConfig}")" == "${originalContent}" ]]
        [[ ! -e "${vlessConfig}.vlessenc.bak" ]]
        [[ ! -e "${vlessState}" ]]
        [[ ! -e "${refreshMarker}" ]]
    ) || return 1

    printf '%s\n' "${originalContent}" >"${vlessConfig}"
    rm -f "${refreshMarker}" "${vlessState}" "${vlessConfig}.vlessenc.bak" "${vlessState}.bak" "${vlessState}.tmp"
    (
        mv() {
            if [[ "$1" == "${vlessState}.tmp" && "$2" == "${vlessState}" ]] ||
                [[ "$1" == "-f" && "$2" == "--" && "$3" == "${vlessState}.tmp" && "$4" == "${vlessState}" ]]; then
                return 1
            fi
            command mv "$@"
        }
        reloadCore() { return 0; }
        regressionExpectStatus 1 setVlessRealityEncryption enable >/dev/null 2>&1
        [[ "$(<"${vlessConfig}")" == "${originalContent}" ]]
        [[ ! -e "${vlessConfig}.vlessenc.bak" ]]
        [[ ! -e "${vlessState}" ]]
        [[ ! -e "${vlessState}.tmp" ]]
        [[ ! -e "${refreshMarker}" ]]
    ) || return 1

    printf '%s\n' "${originalContent}" >"${vlessConfig}"
    rm -f "${refreshMarker}" "${vlessState}" "${vlessConfig}.vlessenc.bak" "${vlessState}.bak" "${vlessState}.tmp"
    (
        mv() {
            if [[ "$1" == "${vlessConfig}.tmp" && "$2" == "${vlessConfig}" ]] ||
                [[ "$1" == "-f" && "$2" == "--" && "$3" == "${vlessConfig}.vlessenc" && "$4" == "${vlessConfig}" ]]; then
                return 1
            fi
            command mv "$@"
        }
        regressionExpectStatus 1 setVlessRealityEncryption enable >/dev/null 2>&1
        jq -e '.inbounds[0].settings.decryption == "mlkem768x25519plus.native.dec"' "${vlessConfig}" >/dev/null
        [[ "$(<"${vlessConfig}.vlessenc.bak")" == "${originalContent}" ]]
        [[ -e "${vlessState}" ]]
        [[ ! -e "${refreshMarker}" ]]
    ) || return 1
    printf '%s\n' "${originalContent}" >"${vlessConfig}"
    rm -f "${vlessState}" "${vlessConfig}.vlessenc.bak" "${vlessState}.bak" "${vlessState}.tmp"

    reloadCore() { printf 'reload\n' >>"${reloadLog}"; return 0; }
    subscribe() {
        printf 'subscribe-unexpected\n' >"${subscribeMarker}"
        return 1
    }
    refreshPublishedSubscriptions() {
        printf 'refresh-published\n' >"${subscribeMarker}"
        return 1
    }
    readNginxSubscribe() {
        subscribePort=443
        nginxConfigPath="${root}/nginx/"
    }
    rm -f "${refreshMarker}" "${subscribeMarker}" "${reloadLog}" "${vlessState}" "${vlessConfig}.vlessenc.bak" "${vlessState}.bak" "${vlessState}.tmp"
    regressionExpectStatus 1 setVlessRealityEncryption enable >/dev/null 2>&1
    [[ "$(<"${vlessConfig}")" == "${originalContent}" ]]
    [[ ! -e "${vlessState}" ]]
    [[ ! -e "${vlessConfig}.vlessenc.bak" ]]
    [[ ! -e "${vlessState}.bak" ]]
    grep -qx 'refresh-published' "${subscribeMarker}"
    [[ "$(wc -l <"${reloadLog}" | tr -d ' ')" == "2" ]]

    reloadCore() { return 0; }
    refreshPublishedSubscriptions() { return 1; }
    readNginxSubscribe() {
        subscribePort=443
        nginxConfigPath="${root}/nginx/"
    }
    regressionExpectStatus 1 refreshVlessEncryptionSubscriptions >/dev/null 2>&1

    subscribePort=
    readNginxSubscribe() {
        subscribePort=
        nginxConfigPath="${root}/nginx/"
    }
    showAccounts() { return 1; }
    regressionExpectStatus 1 refreshVlessEncryptionSubscriptions >/dev/null 2>&1

    initXrayConfig() { return 0; }
    reloadCore() { return 1; }
    subscribe() {
        printf 'subscribe\n' >"${subscribeMarker}"
        return 0
    }
    rm -f "${subscribeMarker}"
    regressionExpectStatus 1 regenerateRealityProfile >/dev/null 2>&1
    [[ ! -e "${subscribeMarker}" ]]

    reloadCore() { return 0; }
    subscribe() {
        printf 'subscribe\n' >"${subscribeMarker}"
        return 1
    }
    rm -f "${subscribeMarker}"
    regressionExpectStatus 1 regenerateRealityProfile >/dev/null 2>&1
    [[ -e "${subscribeMarker}" ]]
)

runConfigTransactionRegression() (
    local tmpRoot
    tmpRoot=$(cd -- "${TMP_DIR}" && pwd -P) || return 1
    local targetFile="${tmpRoot}/transaction.json"
    local backupFile="${targetFile}.bak"
    local stagedFile
    local originalContent updatedContent
    local reloadCountFile="${tmpRoot}/transaction-reload-count"
    local refreshCountFile="${tmpRoot}/transaction-refresh-count"
    local validateMode=success
    local reloadMode=success
    local refreshMode=success
    local oldPath="${PATH}"
    local oldTmpDir="${TMPDIR:-}"
    local checkPortTmpRootRel="${TMP_DIR}/check-port-tmp"
    local checkPortTmpRoot
    local checkPortNginxDirRel="${TMP_DIR}/check-port-nginx"
    local checkPortNginxDir checkPortTarget
    local fakeBinDirRel="${TMP_DIR}/fake-bin"
    local fakeBinDir="${tmpRoot}/fake-bin"
    mkdir -p "${checkPortTmpRootRel}" "${checkPortNginxDirRel}" "${fakeBinDirRel}"
    checkPortTmpRoot="$(cd -- "${checkPortTmpRootRel}" && pwd -P)"
    checkPortNginxDir="$(cd -- "${checkPortNginxDirRel}" && pwd -P)/"
    checkPortTarget="${checkPortNginxDir}checkPortOpen.conf"
    TMPDIR="${checkPortTmpRoot}"

    transactionReloadMock() {
        printf '1\n' >>"${reloadCountFile}"
        [[ "${reloadMode}" == "success" ]]
    }

    transactionRefreshMock() {
        printf '1\n' >>"${refreshCountFile}"
        [[ "${refreshMode}" == "success" ]]
    }

    transactionValidateMock() {
        [[ "${validateMode}" == "success" ]]
    }

    cat >"${targetFile}" <<'JSON'
{"mode":"old","port":443}
JSON
    originalContent=$(<"${targetFile}")
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new"' "${targetFile}" >"${stagedFile}"
    validateMode=fail
    if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock; then
        return 1
    fi
    [[ "$(<"${targetFile}")" == "${originalContent}" ]]
    [[ ! -e "${stagedFile}" ]]
    [[ ! -e "${backupFile}" ]]
    [[ ! -e "${reloadCountFile}" ]]
    [[ ! -e "${refreshCountFile}" ]]

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    originalContent=$(<"${targetFile}")
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    validateMode=fail
    (
        cp() {
            local args=("$@")
            local targetPath="${args[$((${#args[@]} - 1))]}"
            if [[ "${targetPath}" == "${tmpRoot}"/.transaction.json.restore.* ]]; then
                return 1
            fi
            command cp "$@"
        }
        if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
            return 1
        fi
        [[ "$(<"${targetFile}")" != "${originalContent}" ]]
        jq -e '.mode == "new" and .port == 8443' "${targetFile}" >/dev/null
        [[ "$(<"${backupFile}")" == "${originalContent}" ]]
        [[ ! -e "${stagedFile}" ]]
        [[ ! -e "${reloadCountFile}" ]]
        [[ ! -e "${refreshCountFile}" ]]
    ) || return 1

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    local validateFailureLog="${tmpRoot}/transaction-validate-failure.log"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    validateMode=fail
    (
        menuLine() { printf '%s\n' "$*" >>"${validateFailureLog}"; }
        echoContent() { :; }
        menuClose() { :; }
        cp() {
            local args=("$@")
            local targetPath="${args[$((${#args[@]} - 1))]}"
            if [[ "${targetPath}" == "${tmpRoot}"/.transaction.json.restore.* ]]; then
                return 1
            fi
            command cp "$@"
        }
        if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
            return 1
        fi
        grep -qx "配置校验失败，且回滚配置失败，请手动检查 ${targetFile} 和 ${backupFile}" "${validateFailureLog}"
    ) || return 1

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    rm -f "${backupFile}"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    validateMode=success
    configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock
    updatedContent=$(<"${targetFile}")
    [[ "${updatedContent}" != "${originalContent}" ]]
    jq -e '.mode == "new" and .port == 8443' "${targetFile}" >/dev/null
    [[ ! -e "${stagedFile}" ]]
    [[ ! -e "${backupFile}" ]]
    [[ "$(wc -l <"${reloadCountFile}" | tr -d ' ')" == "1" ]]
    [[ "$(wc -l <"${refreshCountFile}" | tr -d ' ')" == "1" ]]

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    originalContent=$(<"${targetFile}")
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    reloadMode=fail
    refreshMode=success
    if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(<"${targetFile}")" == "${originalContent}" ]]
    [[ ! -e "${stagedFile}" ]]
    [[ ! -e "${backupFile}" ]]
    [[ "$(wc -l <"${reloadCountFile}" | tr -d ' ')" == "2" ]]
    [[ ! -e "${refreshCountFile}" ]]

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    local reloadFailureLog="${tmpRoot}/transaction-reload-failure.log"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    reloadMode=fail
    refreshMode=success
    (
        menuLine() { printf '%s\n' "$*" >>"${reloadFailureLog}"; }
        echoContent() { :; }
        menuClose() { :; }
        cp() {
            local args=("$@")
            local targetPath="${args[$((${#args[@]} - 1))]}"
            if [[ "${targetPath}" == "${tmpRoot}"/.transaction.json.restore.* ]]; then
                return 1
            fi
            command cp "$@"
        }
        if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
            return 1
        fi
        grep -qx "核心重载失败，且回滚配置失败，请手动检查 ${targetFile} 和 ${backupFile}" "${reloadFailureLog}"
    ) || return 1

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    reloadMode=success
    refreshMode=fail
    if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
        return 1
    fi
    jq -e '.mode == "new" and .port == 8443' "${targetFile}" >/dev/null
    [[ ! -e "${stagedFile}" ]]
    [[ ! -e "${backupFile}" ]]
    [[ "$(wc -l <"${reloadCountFile}" | tr -d ' ')" == "1" ]]
    [[ "$(wc -l <"${refreshCountFile}" | tr -d ' ')" == "1" ]]
    refreshMode=success

    local refreshFailureLog="${tmpRoot}/transaction-refresh-failure.log"
    local localSubscribeBase
    mkdir -p "${TMP_DIR}/subscribe_local/default" "${TMP_DIR}/subscribe_local/clashMeta" "${TMP_DIR}/subscribe_local/sing-box"
    PADM_SUBSCRIBE_LOCAL_DIR="${tmpRoot}/subscribe_local"
    localSubscribeBase=$(subscribeLocalBaseDir)
    readNginxSubscribe() {
        subscribePort=443
        nginxConfigPath="${TMP_DIR}/nginx-refresh/"
    }
    subscribe() {
        printf 'subscribe-unexpected:%s\n' "$*" >>"${refreshFailureLog}"
        return 1
    }
    refreshPublishedSubscriptions() {
        printf 'refresh-published\n' >>"${refreshFailureLog}"
        return 1
    }
    showAccounts() {
        printf 'showAccounts\n' >>"${refreshFailureLog}"
        return 1
    }
    errorCard() { return 0; }
    : >"${refreshFailureLog}"
    if refreshXHTTPSubscriptions >/dev/null 2>&1; then
        return 1
    fi
    grep -qx 'refresh-published' "${refreshFailureLog}"
    ! grep -q '^subscribe-unexpected:' "${refreshFailureLog}"

    : >"${refreshFailureLog}"
    if refreshTuicSubscriptions >/dev/null 2>&1; then
        return 1
    fi
    grep -qx 'refresh-published' "${refreshFailureLog}"

    readNginxSubscribe() {
        subscribePort=
        nginxConfigPath="${TMP_DIR}/nginx-refresh/"
    }
    : >"${refreshFailureLog}"
    if refreshTuicSubscriptions >/dev/null 2>&1; then
        return 1
    fi
    grep -qx 'showAccounts' "${refreshFailureLog}"

    (
        cleanDirectoryContent() {
            printf 'cleanDirectoryContent\n' >>"${refreshFailureLog}"
            return 1
        }
        showAccounts() {
            printf 'showAccounts\n' >>"${refreshFailureLog}"
            return 0
        }
        readNginxSubscribe() {
            subscribePort=
            nginxConfigPath="${TMP_DIR}/nginx-refresh/"
        }
        : >"${refreshFailureLog}"
        regressionExpectStatus 1 refreshVlessEncryptionSubscriptions >/dev/null 2>&1
        grep -qx 'cleanDirectoryContent' "${refreshFailureLog}"
        ! grep -q '^showAccounts$' "${refreshFailureLog}"
    ) || return 1

    cat >"${fakeBinDir}/nginx" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "-t" ]]
printf 'check-port validate %s\n' "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}"
[[ "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}" == "success" ]]
SH
    chmod +x "${fakeBinDir}/nginx"
    PATH="${fakeBinDir}:${PATH}"
    nginxConfigPath="${checkPortNginxDir}"
    printf 'old config\n' >"${checkPortTarget}"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    if writeCheckPortOpenNginxConfig 443 example.com '' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${checkPortTarget}")" == "old config" ]]
    grep -qxF 'check-port validate fail' "${checkPortTmpRoot}/padm-check-port-open-nginx-test.log"
    [[ ! -e "${checkPortTarget}.tmp" ]]

    printf 'old config\n' >"${checkPortTarget}"
    rm -f "${checkPortTarget}.bak"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    (
        restoreManagedFileFromBackup() { return 1; }
        if writeCheckPortOpenNginxConfig 443 example.com '' 2>/dev/null; then
            return 1
        fi
        [[ "${CHECK_PORT_OPEN_NGINX_CONFIG_ERROR}" == *"旧配置恢复失败"* ]]
        [[ "$(<"${checkPortTarget}")" != "old config" ]]
        [[ "$(<"${checkPortTarget}.bak")" == "old config" ]]
        [[ ! -e "${checkPortTarget}.tmp" ]]
    ) || return 1
    printf 'old config\n' >"${checkPortTarget}"
    rm -f "${checkPortTarget}.bak"

    export PADM_FAKE_NGINX_VALIDATE_MODE=success
    writeCheckPortOpenNginxConfig 443 example.com 'listen [::]:443;'
    grep -qxF 'check-port validate success' "${checkPortTmpRoot}/padm-check-port-open-nginx-test.log"
    grep -q 'server_name example.com;' "${checkPortTarget}"
    grep -q 'listen \[::\]:443;' "${checkPortTarget}"
    [[ ! -e "${checkPortTarget}.tmp" ]]
    [[ ! -e "${checkPortTarget}.bak" ]]
    PATH="${oldPath}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    unset PADM_FAKE_NGINX_VALIDATE_MODE
)

runEntryHelperConfigRegression() {
    local entryConfigPath="${TMP_DIR}/entry-helper-conf/"
    local entryFakeBin="${TMP_DIR}/entry-helper-fake-bin"
    local entryLogBase="${TMP_DIR}/entry-helper-logs/"
    local entryTmpRoot="${TMP_DIR}/entry-helper-tmp"
    local oldTmpDir="${TMPDIR:-}"
    local realityVisionFile="${entryConfigPath}07_VLESS_vision_reality_inbounds.json"
    local realityXhttpFile="${entryConfigPath}12_VLESS_XHTTP_inbounds.json"
    local oldPath="${PATH}"
    local protocolSelectionIncludesDef=
    local nginxTarget="${TMP_DIR}/entry-helper-nginx/sing_box_VMess_HTTPUpgrade.conf"
    local originalContent
    mkdir -p "${entryConfigPath}" "${entryLogBase}" "${entryFakeBin}" "${TMP_DIR}/entry-helper-nginx" "${entryTmpRoot}"
    cat >"${entryFakeBin}/nginx" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-v" ]]; then
    printf 'nginx version: nginx/1.24.0\n' >&2
    exit 0
fi
[[ "$1" == "-t" ]]
printf 'entry-helper validate %s\n' "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}"
[[ "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}" == "success" ]]
SH
    chmod +x "${entryFakeBin}/nginx"
    PATH="${entryFakeBin}:${PATH}"
    TMPDIR="${entryTmpRoot}"
    protocolSelectionIncludesDef=$(declare -f protocolSelectionIncludes)
    protocolSelectionIncludesDef="${protocolSelectionIncludesDef/protocolSelectionIncludes/regressionOriginalProtocolSelectionIncludes}"
    eval "${protocolSelectionIncludesDef}"
    protocolSelectionIncludes() {
        regressionProtocolSelectionIncludesCompat "$@"
    }
    writeXrayLogConfig "${entryConfigPath}00_log.json" "${entryLogBase}" true
    [[ "$(jq -r '.log.access' "${entryConfigPath}00_log.json")" == "${entryLogBase}access.log" ]]
    [[ "$(jq -r '.log.error' "${entryConfigPath}00_log.json")" == "${entryLogBase}error.log" ]]
    [[ "$(jq -r '.log.loglevel' "${entryConfigPath}00_log.json")" == "debug" ]]
    writeXrayLogConfig "${entryConfigPath}00_log.json" "${entryLogBase}" false
    jq -e '(.log.access | not)' "${entryConfigPath}00_log.json" >/dev/null
    [[ "$(jq -r '.log.error' "${entryConfigPath}00_log.json")" == "${entryLogBase}error.log" ]]
    [[ "$(jq -r '.log.loglevel' "${entryConfigPath}00_log.json")" == "warning" ]]

    nginxConfigPath="${TMP_DIR}/entry-helper-nginx/"
    domain=example.com
    nginxStaticPath="${TMP_DIR}/static"
    currentPath=padm
    selectCustomInstallType=23
    printf 'old config\n' >"${nginxTarget}"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    if singBoxNginxConfig 23 443 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${nginxTarget}")" == "old config" ]]
    [[ ! -e "${nginxTarget}.tmp" ]]
    [[ -s "${entryTmpRoot}/padm-sing-box-vmess-httpupgrade-nginx-test.log" ]]
    export PADM_FAKE_NGINX_VALIDATE_MODE=success
    singBoxNginxConfig 23 443
    grep -q 'server_name example.com;' "${nginxTarget}"
    grep -q 'location /padm' "${nginxTarget}"
    ! grep -qx 'old config' "${nginxTarget}"
    [[ ! -e "${nginxTarget}.tmp" ]]
    [[ ! -e "${nginxTarget}.bak" ]]
    ! compgen -G "${TMP_DIR}/entry-helper-nginx/.sing_box_VMess_HTTPUpgrade.conf.*" >/dev/null

    (
        local unsafeRoot="${TMP_DIR}/entry-helper-nginx-unsafe"
        local rc
        mkdir -p "${unsafeRoot}/relative-nginx"
        printf 'stale\n' >"${unsafeRoot}/relative-nginx/sing_box_VMess_HTTPUpgrade.conf"
        cd "${unsafeRoot}"
        nginxConfigPath="relative-nginx/"
        set +e
        writeSingBoxVMessHTTPUpgradeNginxConfig <<'EOF' >/dev/null 2>&1
server {}
EOF
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ "$(<"${unsafeRoot}/relative-nginx/sing_box_VMess_HTTPUpgrade.conf")" == "stale" ]]
        ! compgen -G "${unsafeRoot}/relative-nginx/.sing_box_VMess_HTTPUpgrade.conf.*" >/dev/null
    )

    cat >"${realityVisionFile}" <<'JSON'
{"inbounds":[{"streamSettings":{"realitySettings":{"show":false}}}]}
JSON
    updateRealityShowConfig "${realityVisionFile}" true
    jq -e '.inbounds[0].streamSettings.realitySettings.show == true' "${realityVisionFile}" >/dev/null
    originalContent=$(<"${realityVisionFile}")
    if updateRoutingJsonConfig "${realityVisionFile}" '.inbounds[0].streamSettings.realitySettings.show = [' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${realityVisionFile}")" == "${originalContent}" ]]
    [[ ! -e "${realityVisionFile}.tmp" ]]

    cat >"${realityXhttpFile}" <<'JSON'
{"inbounds":[{"streamSettings":{"realitySettings":{"show":true}}}]}
JSON
    updateRealityShowConfig "${realityXhttpFile}" false
    jq -e '.inbounds[0].streamSettings.realitySettings.show == false' "${realityXhttpFile}" >/dev/null

    (
        local errorLog="${TMP_DIR}/entry-helper-check-log-write-error.log"
        local readCalls=0 rc
        : >"${errorLog}"
        coreInstallType=1
        configPath="${entryConfigPath}"
        realityStatus=7
        writeXrayLogConfig "${entryConfigPath}00_log.json" "${entryLogBase}" false
        cat >"${realityVisionFile}" <<'JSON'
{"inbounds":[{"streamSettings":{"realitySettings":{"show":false}}}]}
JSON
        autoRead() {
            readCalls=$((readCalls + 1))
            printf -v "$3" '1'
        }
        updateRealityShowConfig() {
            return 1
        }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        regressionExpectStatus 1 checkLog >/dev/null 2>&1
        [[ "${readCalls}" == "1" ]]
        grep -q 'Reality 日志联动配置写入失败' "${errorLog}"
        jq -e '(.log.access | not) and .log.error == "'"${entryLogBase}"'error.log" and .log.loglevel == "warning"' "${entryConfigPath}00_log.json" >/dev/null
        jq -e '.inbounds[0].streamSettings.realitySettings.show == false' "${realityVisionFile}" >/dev/null
        if regressionFindHasMatches "${entryTmpRoot}" -maxdepth 1 -type d -name 'padm-check-log-backup.*'; then
            return 1
        fi
    )

    (
        local errorLog="${TMP_DIR}/entry-helper-check-log-error.log"
        local reloadCalls=0 readCalls=0 rc
        : >"${errorLog}"
        coreInstallType=1
        configPath="${entryConfigPath}"
        realityStatus=7
        writeXrayLogConfig "${entryConfigPath}00_log.json" "${entryLogBase}" false
        cat >"${realityVisionFile}" <<'JSON'
{"inbounds":[{"streamSettings":{"realitySettings":{"show":false}}}]}
JSON
        autoRead() {
            readCalls=$((readCalls + 1))
            printf -v "$3" '1'
        }
        reloadCore() {
            reloadCalls=$((reloadCalls + 1))
            return 1
        }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        regressionExpectStatus 1 checkLog >/dev/null 2>&1
        [[ "${readCalls}" == "1" ]]
        [[ "${reloadCalls}" == "2" ]]
        grep -q '已回滚日志配置修改' "${errorLog}"
        grep -q '恢复旧配置后核心重载仍失败' "${errorLog}"
        jq -e '(.log.access | not) and .log.error == "'"${entryLogBase}"'error.log" and .log.loglevel == "warning"' "${entryConfigPath}00_log.json" >/dev/null
        jq -e '.inbounds[0].streamSettings.realitySettings.show == false' "${realityVisionFile}" >/dev/null
        if regressionFindHasMatches "${entryTmpRoot}" -maxdepth 1 -type d -name 'padm-check-log-backup.*'; then
            return 1
        fi
    )

    (
        local serviceLog="${TMP_DIR}/entry-helper-tls-init-service.log"
        local errorLog="${TMP_DIR}/entry-helper-tls-init-error.log"
        local rc
        : >"${serviceLog}"
        : >"${errorLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        currentHost=tls-init.example.com
        lastInstallationConfig=true
        selectCoreType=2
        domain=
        handleNginx() {
            printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
            return 1
        }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        regressionExpectStatus 1 initTLSNginxConfig 1 >/dev/null 2>&1
        grep -qx 'nginx:stop:true' "${serviceLog}"
        grep -q 'TLS 初始化' "${errorLog}"
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    )

    (
        local serviceLog="${TMP_DIR}/entry-helper-port-service.log"
        local errorLog="${TMP_DIR}/entry-helper-port-error.log"
        local allowMarker="${TMP_DIR}/entry-helper-port-allow"
        local rc
        : >"${serviceLog}"
        : >"${errorLog}"
        rm -f "${allowMarker}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        btDomain=
        currentPort=
        customPort=
        xrayVLESSRealityPort=443
        domain=port.example.com
        handleXray() {
            printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
            return 1
        }
        autoRead() {
            printf -v "$3" '443'
        }
        allowPort() {
            printf 'allow\n' >"${allowMarker}"
        }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        regressionExpectStatus 1 customPortFunction >/dev/null 2>&1
        grep -qx 'xray:stop:true' "${serviceLog}"
        grep -q '无法复用当前 Reality 端口' "${errorLog}"
        [[ ! -e "${allowMarker}" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    )

    (
        local errorLog="${TMP_DIR}/entry-helper-port-expression-error.log"
        local allowLog="${TMP_DIR}/entry-helper-port-expression-allow.log"
        local rc
        : >"${errorLog}"
        : >"${allowLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        btDomain=
        currentPort=
        customPort=
        xrayVLESSRealityPort=
        domain=port.example.com
        autoRead() {
            printf -v "$3" '1+2'
        }
        allowPort() {
            printf '%s\n' "$1" >>"${allowLog}"
        }
        checkDNSIP() { return 0; }
        removeNginxDefaultConf() { return 0; }
        checkPortOpen() { return 0; }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        regressionExpectStatus 1 customPortFunction >/dev/null 2>&1
        grep -q '端口输入错误' "${errorLog}"
        [[ ! -s "${allowLog}" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    )

    (
        local checkPortMarker="${TMP_DIR}/entry-helper-port-nginx-cleanup-check"
        local errorLog="${TMP_DIR}/entry-helper-port-nginx-cleanup-error.log"
        local rc
        : >"${errorLog}"
        rm -f "${checkPortMarker}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        btDomain=
        currentPort=
        customPort=
        xrayVLESSRealityPort=
        domain=port.example.com
        autoRead() {
            printf -v "$3" '443'
        }
        allowPort() { return 0; }
        checkDNSIP() { return 0; }
        removeNginxDefaultConf() { return 1; }
        checkPortOpen() {
            : >"${checkPortMarker}"
            return 0
        }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        regressionExpectStatus 1 customPortFunction >/dev/null 2>&1
        [[ ! -e "${checkPortMarker}" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    )

    PATH="${oldPath}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    eval "${protocolSelectionIncludesDef}"
    unset PADM_FAKE_NGINX_VALIDATE_MODE
}

runSingBoxRealityKeyTransactionRegression() (
    local rootRel="${TMP_DIR}/singbox-reality-key-transaction"
    local root singBoxBinary keyFile
    local oldSingBoxBinary="${PADM_SINGBOX_BINARY:-}"
    local oldRealityKeyFile="${PADM_SINGBOX_REALITY_KEY_FILE:-}"
    local oldSelectCoreType="${selectCoreType:-}"
    local oldCoreInstallType="${coreInstallType:-}"
    local oldLastInstallationConfig="${lastInstallationConfig:-}"
    local oldCurrentRealityPublicKey="${currentRealityPublicKey:-}"
    local oldCurrentRealityPrivateKey="${currentRealityPrivateKey:-}"
    local oldRealityPrivateKey="${realityPrivateKey:-}"
    local oldRealityPublicKey="${realityPublicKey:-}"
    local rc

    mkdir -p "${rootRel}/sing-box" "${rootRel}/config"
    root=$(cd -- "${rootRel}" && pwd -P) || return 1
    singBoxBinary="${root}/sing-box/sing-box"
    keyFile="${root}/config/reality_key"
    cat >"${singBoxBinary}" <<'EOF'
#!/usr/bin/env bash
printf 'PrivateKey private-generated\n'
printf 'PublicKey public-generated\n'
EOF
    chmod +x "${singBoxBinary}"
    printf 'publicKey:old-public\n' >"${keyFile}"

    PADM_SINGBOX_BINARY="${singBoxBinary}"
    PADM_SINGBOX_REALITY_KEY_FILE="${keyFile}"
    selectCoreType=2
    coreInstallType=2
    lastInstallationConfig=
    currentRealityPublicKey=
    currentRealityPrivateKey=
    realityPrivateKey=
    realityPublicKey=

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${keyFile}" ]]; then
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    regressionExpectStatus 1 initRealityKey >/dev/null 2>&1
    [[ "$(<"${keyFile}")" == "publicKey:old-public" ]]
    [[ "${realityPrivateKey}" == "private-generated" ]]
    [[ "${realityPublicKey}" == "public-generated" ]]
    ! compgen -G "${root}/config/.reality_key.reality.*" >/dev/null

    commitGeneratedFile() {
        originalCommitGeneratedFile "$@"
    }
    realityPrivateKey=
    realityPublicKey=
    initRealityKey >/dev/null
    [[ "${realityPrivateKey}" == "private-generated" ]]
    [[ "${realityPublicKey}" == "public-generated" ]]
    [[ "$(<"${keyFile}")" == "publicKey:public-generated" ]]
    ! compgen -G "${root}/config/.reality_key.reality.*" >/dev/null
    ! grep -qF 'statusCard "Reality Key" "privateKey:${realityPrivateKey}"' "${PROJECT_ROOT}/shell/core/protocol_runtime.sh"

    lastInstallationConfig=true
    currentRealityPrivateKey=private-reused
    currentRealityPublicKey=public-reused
    realityPrivateKey=
    realityPublicKey=
    initRealityKey >/dev/null
    [[ "${realityPrivateKey}" == "private-reused" ]]
    [[ "${realityPublicKey}" == "public-reused" ]]
    [[ "$(<"${keyFile}")" == "publicKey:public-reused" ]]

    lastInstallationConfig=
    currentRealityPrivateKey=
    currentRealityPublicKey=
    printf 'publicKey:public-generated\n' >"${keyFile}"

    cat >"${singBoxBinary}" <<'EOF'
#!/usr/bin/env bash
exit 23
EOF
    chmod +x "${singBoxBinary}"
    realityPrivateKey=
    realityPublicKey=
    regressionExpectStatus 1 initRealityKey >/dev/null 2>&1
    [[ "$(<"${keyFile}")" == "publicKey:public-generated" ]]

    cat >"${singBoxBinary}" <<'EOF'
#!/usr/bin/env bash
printf 'PrivateKey private-only\n'
EOF
    chmod +x "${singBoxBinary}"
    realityPrivateKey=
    realityPublicKey=
    regressionExpectStatus 1 initRealityKey >/dev/null 2>&1
    [[ "$(<"${keyFile}")" == "publicKey:public-generated" ]]

    if [[ -n "${oldSingBoxBinary}" ]]; then
        PADM_SINGBOX_BINARY="${oldSingBoxBinary}"
    else
        unset PADM_SINGBOX_BINARY
    fi
    if [[ -n "${oldRealityKeyFile}" ]]; then
        PADM_SINGBOX_REALITY_KEY_FILE="${oldRealityKeyFile}"
    else
        unset PADM_SINGBOX_REALITY_KEY_FILE
    fi
    selectCoreType="${oldSelectCoreType}"
    coreInstallType="${oldCoreInstallType}"
    lastInstallationConfig="${oldLastInstallationConfig}"
    currentRealityPublicKey="${oldCurrentRealityPublicKey}"
    currentRealityPrivateKey="${oldCurrentRealityPrivateKey}"
    realityPrivateKey="${oldRealityPrivateKey}"
    realityPublicKey="${oldRealityPublicKey}"
)
