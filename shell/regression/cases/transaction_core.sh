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

runCoreRollbackResultMessageRegression() (
    local message=
    local detailMessage=
    local retryLog="${TMP_DIR}/core-rollback-result.log"

    coreSetRollbackResultMessage message \
        "核心重载失败" \
        "已回滚本次修改"
    [[ "${message}" == "核心重载失败，已回滚本次修改" ]]

    : >"${retryLog}"
    coreRollbackRetrySuccess() {
        printf '%s\n' "$*" >>"${retryLog}"
        return 0
    }
    coreSetRollbackResultMessage message \
        "核心重载失败" \
        "已回滚本次修改" \
        coreRollbackRetrySuccess \
        "恢复旧配置后重载仍失败，请检查核心服务日志" \
        dns
    [[ "${message}" == "核心重载失败，已回滚本次修改" ]]
    grep -q '^dns$' "${retryLog}"

    : >"${retryLog}"
    coreRollbackRetryFail() {
        printf '%s\n' "$*" >>"${retryLog}"
        return 1
    }
    coreSetRollbackResultMessage message \
        "核心重载失败" \
        "已回滚本次修改" \
        coreRollbackRetryFail \
        "恢复旧配置后重载仍失败，请检查核心服务日志" \
        dns
    [[ "${message}" == "核心重载失败，已回滚本次修改；恢复旧配置后重载仍失败，请检查核心服务日志" ]]
    grep -q '^dns$' "${retryLog}"

    coreSetRollbackResultMessage message \
        "刷新 VLESS Encryption 订阅失败" \
        "已恢复旧配置"
    [[ "${message}" == "刷新 VLESS Encryption 订阅失败，已恢复旧配置" ]]

    : >"${retryLog}"
    coreSetRollbackResultMessage message \
        "核心重载失败" \
        "已回滚日志配置修改" \
        coreRollbackRetryFail \
        "恢复旧配置后核心重载仍失败，请检查核心服务日志" \
        log
    [[ "${message}" == "核心重载失败，已回滚日志配置修改；恢复旧配置后核心重载仍失败，请检查核心服务日志" ]]
    grep -q '^log$' "${retryLog}"

    : >"${retryLog}"
    coreSetRollbackResultMessage message \
        "核心重载失败" \
        "已回滚配置" \
        coreRollbackRetrySuccess \
        "恢复旧配置后重载仍失败，请检查核心服务日志" \
        reality
    [[ "${message}" == "核心重载失败，已回滚配置" ]]
    grep -q '^reality$' "${retryLog}"

    set +e
    coreSetSingleRestoreResultMessage message \
        "Fail2ban 服务应用失败" \
        true \
        "已恢复旧配置" \
        "旧配置" \
        "/tmp/fail2ban-backup"
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
    [[ "${message}" == "Fail2ban 服务应用失败，已恢复旧配置" ]]

    set +e
    coreSetSingleRestoreResultMessage message \
        "Fail2ban 服务应用失败" \
        false \
        "已恢复旧配置" \
        "旧配置" \
        "/tmp/fail2ban-backup"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "Fail2ban 服务应用失败，且旧配置恢复失败，请手动检查/tmp/fail2ban-backup" ]]

    coreSetRestoreFailureDetail detailMessage "旧配置" "/tmp/fail2ban-backup"
    [[ "${detailMessage}" == "旧配置恢复失败，请手动检查/tmp/fail2ban-backup" ]]

    set +e
    coreSetSingleRestoreResultMessage message \
        "提交 VLESS Encryption 状态失败" \
        true \
        "已恢复旧配置" \
        "旧配置" \
        "/tmp/vless-state-backup"
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
    [[ "${message}" == "提交 VLESS Encryption 状态失败，已恢复旧配置" ]]

    set +e
    coreSetSingleRestoreResultMessage message \
        "写入日志配置失败" \
        false \
        "已恢复旧配置" \
        "旧配置" \
        "备份目录: /tmp/check-log-backup"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "写入日志配置失败，且旧配置恢复失败，请手动检查备份目录: /tmp/check-log-backup" ]]

    set +e
    coreSetSingleRestoreResultMessage message \
        "Xray 配置校验失败" \
        false \
        "已恢复旧配置" \
        "旧配置" \
        " /tmp/xray-fallback.json 和 /tmp/xray-fallback.json.alpn.bak"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "Xray 配置校验失败，且旧配置恢复失败，请手动检查 /tmp/xray-fallback.json 和 /tmp/xray-fallback.json.alpn.bak" ]]

    set +e
    coreSetSingleRestoreResultMessage message \
        "sing-box 日志配置重载失败" \
        false \
        "已恢复旧配置" \
        "旧配置" \
        " /tmp/log.json，备份文件：/tmp/log.json.bak"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "sing-box 日志配置重载失败，且旧配置恢复失败，请手动检查 /tmp/log.json，备份文件：/tmp/log.json.bak" ]]

    coreSetRollbackResultMessage message \
        "sing-box 日志配置重载失败" \
        "已回滚日志配置"
    [[ "${message}" == "sing-box 日志配置重载失败，已回滚日志配置" ]]

    coreSetRollbackResultMessage message \
        "写入日志配置失败" \
        "已回滚本次日志修改"
    [[ "${message}" == "写入日志配置失败，已回滚本次日志修改" ]]

    coreSetRollbackFailureMessage message \
        "核心重载失败" \
        "/tmp/core-backup"
    [[ "${message}" == "核心重载失败，且回滚失败，请手动检查备份目录: /tmp/core-backup" ]]

    coreSetRollbackFailureMessage message \
        "入口端口配置回滚失败" \
        "/tmp/core-port-backup" \
        ""
    [[ "${message}" == "入口端口配置回滚失败，请手动检查备份目录: /tmp/core-port-backup" ]]

    coreSetNewConfigCleanupFailureMessage message \
        "sing-box 日志配置重载失败" \
        "/tmp/log.json"
    [[ "${message}" == "sing-box 日志配置重载失败，且新配置清理失败，请手动检查 /tmp/log.json" ]]

    set +e
    coreSetDualRestoreResultMessage message \
        "写入 Xray 配置失败" \
        false \
        "VLESS Encryption 配置" \
        " /tmp/config.json 和 /tmp/config.json.bak" \
        true \
        "VLESS Encryption 状态" \
        " /tmp/state.json 和 /tmp/state.json.bak"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "写入 Xray 配置失败，且VLESS Encryption 配置恢复失败，请手动检查 /tmp/config.json 和 /tmp/config.json.bak" ]]

    coreSetRestoreFailureDetail detailMessage "VLESS Encryption 配置" " /tmp/config.json 和 /tmp/config.json.bak"
    [[ "${detailMessage}" == "VLESS Encryption 配置恢复失败，请手动检查 /tmp/config.json 和 /tmp/config.json.bak" ]]

    coreSetManualCheckMessage detailMessage "VLESS Encryption 配置恢复失败" " /tmp/config.json 和 /tmp/config.json.bak"
    [[ "${detailMessage}" == "VLESS Encryption 配置恢复失败，请手动检查 /tmp/config.json 和 /tmp/config.json.bak" ]]

    set +e
    coreSetDualRestoreResultMessage message \
        "删除 VLESS Encryption 状态失败" \
        true \
        "VLESS Encryption 配置" \
        " /tmp/config.json 和 /tmp/config.json.bak" \
        false \
        "VLESS Encryption 状态" \
        " /tmp/state.json 和 /tmp/state.json.bak"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "删除 VLESS Encryption 状态失败，且VLESS Encryption 状态恢复失败，请手动检查 /tmp/state.json 和 /tmp/state.json.bak" ]]

    coreSetPairedFileRestoreFailureMessage message \
        "新版入口执行失败" \
        "旧入口" \
        "/tmp/install.sh" \
        "/tmp/install.sh.bak"
    [[ "${message}" == "新版入口执行失败，旧入口恢复失败，请手动检查 /tmp/install.sh 和 /tmp/install.sh.bak" ]]

    coreSetPairedFileManualCheckMessage message \
        "核心重载失败，且回滚配置失败" \
        "/tmp/config.json" \
        "/tmp/config.json.bak"
    [[ "${message}" == "核心重载失败，且回滚配置失败，请手动检查 /tmp/config.json 和 /tmp/config.json.bak" ]]

    coreSetManualCheckMessage detailMessage "核心重载失败，且回滚配置失败" " /tmp/config.json 和 /tmp/config.json.bak"
    [[ "${detailMessage}" == "核心重载失败，且回滚配置失败，请手动检查 /tmp/config.json 和 /tmp/config.json.bak" ]]

    coreSetManualCheckMessage detailMessage "Nginx 配置目标异常" " /tmp/alone.conf"
    [[ "${detailMessage}" == "Nginx 配置目标异常，请手动检查 /tmp/alone.conf" ]]

    coreSetManualCheckMessage detailMessage "端口检测 Nginx 配置备份清理失败" " /tmp/check-port-open.conf.bak"
    [[ "${detailMessage}" == "端口检测 Nginx 配置备份清理失败，请手动检查 /tmp/check-port-open.conf.bak" ]]

    subscriptionSyncSetManualCheckMessage detailMessage "订阅配置恢复失败" " /tmp/subscribe.json"
    [[ "${detailMessage}" == "订阅配置恢复失败，请手动检查 /tmp/subscribe.json" ]]
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
        local rollbackMessage
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
        coreSetRollbackResultMessage rollbackMessage "入口端口核心重载失败" "已恢复旧配置" reloadCore "恢复后核心重载仍失败，请检查核心服务日志"
        errorCard "${rollbackMessage}"
        padmRemoveCleanupPath "${backupDir}"
        return 1
    }
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

        set +e
        originalAddCorePort >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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
        set +e
        originalAddCorePort >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -qx 'deny:2555:tcp' "${firewallLog}"
        grep -qx 'deny:2555:udp' "${firewallLog}"
    )

    rm -rf "${configPath}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runCorePortRejectsUnsafeConfigDirRegression() (
    local rootRel="${TMP_DIR}/core-port-unsafe-config"
    local root rmLog cpLog
    local rc

    mkdir -p "${rootRel}/relative-config" "${rootRel}/backup-restore"
    root=$(cd -- "${rootRel}" && pwd -P) || return 1
    rmLog="${root}/rm.log"
    cpLog="${root}/cp.log"
    : >"${rmLog}"
    : >"${cpLog}"
    printf '{"inbounds":[{"port":2053,"settings":{"port":443}}]}\n' >"${root}/relative-config/02_dokodemodoor_inbounds_2053_default.json"
    printf '{"inbounds":[{"port":2443,"settings":{"port":443}}]}\n' >"${root}/backup-restore/02_dokodemodoor_inbounds_2443_default.json"

    cd "${root}"
    configPath="relative-config/"
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }
    cp() {
        printf 'cp:%s\n' "$*" >>"${cpLog}"
        command cp "$@"
    }

    set +e
    writeCoreDokodemoInbound "${configPath}02_dokodemodoor_inbounds_2053.json" 2053 443 tcp dokodemo-door-unsafe >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -e "${root}/relative-config/02_dokodemodoor_inbounds_2053.json" ]]

    set +e
    corePortRemove 2053 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -f "${root}/relative-config/02_dokodemodoor_inbounds_2053_default.json" ]]

    set +e
    corePortBackupFiles "${root}/backup-out" >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -e "${root}/backup-out" ]]

    set +e
    corePortRollbackFiles "${root}/backup-restore" >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -f "${root}/relative-config/02_dokodemodoor_inbounds_2053_default.json" ]]
    [[ ! -e "${root}/relative-config/02_dokodemodoor_inbounds_2443_default.json" ]]
    [[ ! -s "${rmLog}" ]]
    [[ ! -s "${cpLog}" ]]
)

runXrayRealityPortFailureRegression() (
    local xrayRoot="${TMP_DIR}/xray-reality-port-failure"
    local oldConfigPath="${configPath:-}"
    local oldSelectCustomInstallType="${selectCustomInstallType:-}"
    local oldCurrentUUID="${currentUUID:-}"
    local oldCurrentClients="${currentClients:-}"
    local oldRealityPort="${realityPort:-}"
    local oldXHTTPort="${xHTTPort:-}"
    local oldXrayRealityPort="${xrayVLESSRealityPort:-}"
    local oldXrayXHTTPort="${xrayVLESSRealityXHTTPort:-}"
    local oldLastInstallationConfig="${lastInstallationConfig:-}"
    local allowCalls=0
    local checkCalls=0
    local streamEnabled=false
    local rejectPort=
    local beforeAllow beforeCheck singBoxPort singBoxPromptPort=
    local serviceLog="${xrayRoot}/service.log"
    local errorLog="${xrayRoot}/error.log"
    local allowMarker="${xrayRoot}/allow.log"
    local configRc

    configPath="${xrayRoot}/"
    mkdir -p "${configPath}"
    currentUUID=existing-user
    xrayVLESSRealityPort=
    xrayVLESSRealityXHTTPort=
    lastInstallationConfig=true
    realityPort=70000
    xHTTPort=
    initXrayClients() { printf '[]\n'; }
    addXrayOutbound() { return 0; }
    installSniffing() { return 0; }
    writeGeneratedJsonFile() {
        local targetFile=$1
        local outputFile
        shift 2
        if [[ "${targetFile}" == /etc/padm/xray/conf/* ]]; then
            outputFile="${configPath}${targetFile#/etc/padm/xray/conf/}"
        else
            outputFile="${targetFile}"
        fi
        mkdir -p "$(dirname "${outputFile}")"
        cat >"${outputFile}"
    }
    initRealityProfile() { return 0; }
    initRealityKey() {
        realityPrivateKey=private
        realityPublicKey=public
    }
    initRealityMldsa65() {
        realityMldsa65Seed=seed
        realityMldsa65Verify=verify
    }
    allowPort() {
        allowCalls=$((allowCalls + 1))
        printf 'allow:%s\n' "$*" >>"${allowMarker}"
        return 0
    }
    allowPortTcpAndUdp() {
        allowCalls=$((allowCalls + 1))
        printf 'allow-both:%s\n' "$*" >>"${allowMarker}"
        return 0
    }
    checkPort() {
        checkCalls=$((checkCalls + 1))
        [[ -z "${rejectPort}" || "$1" != "${rejectPort}" ]]
    }
    realityStreamSplitEnabled() { [[ "${streamEnabled}" == "true" ]]; }
    realityStreamInternalPortForProtocol() {
        case "$1" in
        vision) printf '2443\n' ;;
        xhttp) printf '2444\n' ;;
        esac
    }
    realityStreamPublicPortForProtocol() { printf '443\n'; }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        return 0
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        return 0
    }
    errorCard() {
        printf '%s\n' "$*" >>"${errorLog}"
    }

    ! validPortNumber 999999999999999999999
    corePortIsValid 08
    ! corePortIsValid 999999999999999999999
    subscriptionGroupSyncIntervalValid 08
    ! subscriptionGroupSyncIntervalValid 999999999999999999999
    validateRealityTarget example.com 08
    ! validateRealityTarget example.com 999999999999999999999

    if initXrayRealityPort 2>/dev/null; then
        return 1
    fi
    [[ "${allowCalls}" == "0" ]]

    xHTTPort=bad-port
    if initXrayXHTTPort 2>/dev/null; then
        return 1
    fi
    [[ "${allowCalls}" == "0" ]]

    selectCustomInstallType=",1,"
    : >"${serviceLog}"
    : >"${errorLog}"
    rm -f "${allowMarker}"
    realityPort=
    xHTTPort=
    xrayVLESSRealityPort=1443
    lastInstallationConfig=true
    AUTO_PORT=2443
    autoRead() {
        case "$1" in
        reality_port_subport) printf -v "$3" '15555' ;;
        xhttp_port_subport) printf -v "$3" '15556' ;;
        reality_subport) printf -v "$3" '%s' "${singBoxPromptPort}" ;;
        *) printf -v "$3" '' ;;
        esac
    }
    initXrayRealityPort
    [[ "${realityPort}" == "2443" ]]

    AUTO_PORT=
    realityPort=
    initXrayRealityPort
    [[ "${realityPort}" == "1443" ]]

    lastInstallationConfig=
    AUTO_INSTALL=true
    realityPort=
    initXrayRealityPort
    [[ "${realityPort}" == "1443" ]]

    singBoxPort=$(initSingBoxPort 1443 true tcp reality_subport 1 vision)
    [[ "${singBoxPort}" == "1443" ]]
    AUTO_INSTALL=
    lastInstallationConfig=true

    xrayVLESSRealityPort=
    realityPort=
    initXrayRealityPort
    [[ "${realityPort}" == "443" ]]

    selectCustomInstallType=",1,2,"
    lastInstallationConfig=
    AUTO_INSTALL=true
    AUTO_PORT=7443
    xrayVLESSRealityPort=1443
    realityPort=
    initXrayRealityPort
    [[ "${realityPort}" == "15555" ]]
    AUTO_INSTALL=
    lastInstallationConfig=true

    selectCustomInstallType=",1,"
    AUTO_PORT=16666
    realityPort=
    rejectPort=16666
    beforeAllow=${allowCalls}
    if initXrayRealityPort 2>/dev/null; then
        return 1
    fi
    [[ "${allowCalls}" == "${beforeAllow}" ]]
    [[ ! -s "${serviceLog}" ]]

    rejectPort=
    streamEnabled=true
    AUTO_PORT=
    realityPort=
    initXrayRealityPort
    [[ "${realityPort}" == "2443" ]]

    AUTO_PORT=443
    realityPort=
    initXrayRealityPort
    [[ "${realityPort}" == "2443" ]]

    AUTO_PORT=8443
    realityPort=
    beforeAllow=${allowCalls}
    beforeCheck=${checkCalls}
    if initXrayRealityPort 2>/dev/null; then
        return 1
    fi
    [[ "${allowCalls}" == "${beforeAllow}" ]]
    [[ "${checkCalls}" == "${beforeCheck}" ]]
    [[ ! -s "${serviceLog}" ]]

    selectCustomInstallType=",2,"
    AUTO_PORT=443
    xHTTPort=
    initXrayXHTTPort
    [[ "${xHTTPort}" == "2444" ]]

    streamEnabled=false
    selectCustomInstallType=",1,"
    lastInstallationConfig=true
    AUTO_PORT=3443
    singBoxPort=$(initSingBoxPort 1443 true tcp reality_subport 1 vision)
    [[ "${singBoxPort}" == "3443" ]]

    AUTO_PORT=
    singBoxPort=$(initSingBoxPort 1443 true tcp reality_subport 1 vision)
    [[ "${singBoxPort}" == "1443" ]]

    singBoxPort=$(initSingBoxPort '' true tcp reality_subport 1 vision)
    [[ "${singBoxPort}" == "443" ]]

    selectCustomInstallType=",1,26,"
    lastInstallationConfig=
    AUTO_INSTALL=true
    AUTO_PORT=7443
    singBoxPromptPort=15557
    singBoxPort=$(initSingBoxPort 1443 true tcp reality_subport 1 vision)
    [[ "${singBoxPort}" == "15557" ]]
    AUTO_INSTALL=
    lastInstallationConfig=true

    streamEnabled=true
    selectCustomInstallType=",1,"
    AUTO_PORT=443
    singBoxPort=$(initSingBoxPort '' true tcp reality_subport 1 vision)
    [[ "${singBoxPort}" == "2443" ]]

    AUTO_PORT=8443
    beforeAllow=${allowCalls}
    beforeCheck=${checkCalls}
    if singBoxPort=$(initSingBoxPort '' true tcp reality_subport 1 vision 2>/dev/null); then
        return 1
    fi
    [[ "${allowCalls}" == "${beforeAllow}" ]]
    [[ "${checkCalls}" == "${beforeCheck}" ]]
    [[ ! -s "${serviceLog}" ]]

    streamEnabled=false
    AUTO_PORT=
    selectCustomInstallType=",1,"
    xrayVLESSRealityPort=
    xrayVLESSRealityXHTTPort=
    xHTTPort=
    realityPort=70000
    rm -f "${allowMarker}"
    set +e
    (
        set +e
        initXrayConfig custom 1 true >/dev/null 2>&1
    )
    configRc=$?
    set -e
    [[ "${configRc}" == "1" ]]
    [[ ! -e "${allowMarker}" ]]
    [[ ! -e "${configPath}07_VLESS_vision_reality_inbounds.json" ]]

    selectCustomInstallType=",2,"
    realityPort=10888
    xHTTPort=bad-port
    rm -f "${allowMarker}"
    set +e
    (
        set +e
        initXrayConfig custom 1 true >/dev/null 2>&1
    )
    configRc=$?
    set -e
    [[ "${configRc}" == "1" ]]
    [[ ! -e "${allowMarker}" ]]
    [[ ! -e "${configPath}12_VLESS_XHTTP_inbounds.json" ]]

    configPath="${oldConfigPath}"
    selectCustomInstallType="${oldSelectCustomInstallType}"
    currentUUID="${oldCurrentUUID}"
    currentClients="${oldCurrentClients}"
    realityPort="${oldRealityPort}"
    xHTTPort="${oldXHTTPort}"
    xrayVLESSRealityPort="${oldXrayRealityPort}"
    xrayVLESSRealityXHTTPort="${oldXrayXHTTPort}"
    lastInstallationConfig="${oldLastInstallationConfig}"
)

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
    set +e
    initXrayConfig custom 1 true 2>/dev/null
    xrayRc=$?
    set -e
    [[ "${xrayRc}" != "0" ]]
    [[ "$(<"${xrayRoot}/00_log.json")" == 'old-xray-log' ]]
    [[ ! -e "${xrayRoot}/12_policy.json" ]]
    [[ ! -e "${xrayRoot}/11_dns.json" ]]

    mode=xray-outbound
    set +e
    initXrayConfig custom 1 true 2>/dev/null
    xrayRc=$?
    set -e
    [[ "${xrayRc}" != "0" ]]
    [[ ! -e "${xrayRoot}/09_routing.json" ]]

    mode=stop-fail
    selectCustomInstallType=",27,"
    writeCalls=0
    : >"${serviceLog}"
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    rm -f "${firewallState}"
    : >"${firewallLog}"
    set +e
    initSingBoxConfig custom 1 true 2>/dev/null
    stopRc=$?
    set -e
    [[ "${stopRc}" != "0" ]]
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
    set +e
    initSingBoxConfig custom 1 true 2>/dev/null
    singBoxRc=$?
    set -e
    [[ "${singBoxRc}" != "0" ]]
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
    set +e
    initSingBoxConfig custom 1 true 2>/dev/null
    stopRc=$?
    set -e
    [[ "${stopRc}" != "0" ]]
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
    set +e
    installSingBoxReality >/dev/null 2>&1
    stopRc=$?
    set -e
    [[ "${stopRc}" == "1" ]]
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
    set +e
    installSingBoxReality >/dev/null 2>&1
    stopRc=$?
    set -e
    [[ "${stopRc}" == "1" ]]
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
    set +e
    initXrayConfigApply custom 1 true 2>/dev/null
    xrayRc=$?
    set -e
    [[ "${xrayRc}" != "0" ]]
    [[ "${writeCalls}" == "0" ]]

    selectCustomInstallType=",27,"
    set +e
    initSingBoxConfigApply custom 1 true 2>/dev/null
    singBoxRc=$?
    set -e
    [[ "${singBoxRc}" != "0" ]]
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
    set +e
    initXrayConfig custom 1 true 2>/dev/null
    xrayRc=$?
    set -e
    [[ "${xrayRc}" != "0" ]]

    installSniffing() { return 1; }
    selectCustomInstallType=",999,"
    set +e
    initXrayConfig custom 1 true 2>/dev/null
    xrayRc=$?
    set -e
    [[ "${xrayRc}" != "0" ]]

    installSniffing() { return 0; }
    removeSingBoxConfig() { return 1; }
    setSniffRouting() { return 0; }
    mode=cleanup-fail
    selectCustomInstallType=",999,"
    set +e
    padmRunPortAllowTransaction initSingBoxConfigApply custom 1 2>/dev/null
    singBoxRc=$?
    set -e
    [[ "${singBoxRc}" != "0" ]]
)

runCoreTemplateManagedConfigRemovalRegression() (
    local cleanupLog="${TMP_DIR}/core-template-managed-remove.log"

    : >"${cleanupLog}"
    rm() {
        printf 'rm:%s\n' "$*" >>"${cleanupLog}"
        return 0
    }

    removeXrayTemplateConfigFiles 03_VLESS_WS_inbounds.json 07_VLESS_vision_reality_inbounds.json
    grep -qx 'rm:-f -- /etc/padm/xray/conf/03_VLESS_WS_inbounds.json' "${cleanupLog}"
    grep -qx 'rm:-f -- /etc/padm/xray/conf/07_VLESS_vision_reality_inbounds.json' "${cleanupLog}"

    : >"${cleanupLog}"
    removeSingBoxTemplateConfigFiles 11_VMess_HTTPUpgrade_inbounds.json 13_anytls_inbounds.json
    grep -qx 'rm:-f -- /etc/padm/sing-box/conf/config/11_VMess_HTTPUpgrade_inbounds.json' "${cleanupLog}"
    grep -qx 'rm:-f -- /etc/padm/sing-box/conf/config/13_anytls_inbounds.json' "${cleanupLog}"

    : >"${cleanupLog}"
    if removeXrayTemplateConfigFiles ../unsafe.json >/dev/null 2>&1; then
        return 1
    fi
    [[ ! -s "${cleanupLog}" ]]
)

runCoreBinaryInstallCopyFailureRegression() (
    local root="${TMP_DIR}/core-binary-copy-failure"
    local xrayBinary="${root}/xray/xray"
    local singBoxBinary="${root}/sing-box/sing-box"
    local singBoxCronet="${root}/sing-box/libcronet.so"
    local statusLog="${root}/status.log"
    local successLog="${root}/success.log"
    local serviceLog="${root}/service.log"
    local copyFailureLog="${root}/copy-failure.log"
    local xrayRc singBoxRc
    local restoreCopyShouldFail= xrayStartShouldFail= singBoxStartShouldFail=

    mkdir -p "$(dirname "${xrayBinary}")" "$(dirname "${singBoxBinary}")" "${root}/tmp"
    printf 'old-xray\n' >"${xrayBinary}"
    printf 'old-sing-box\n' >"${singBoxBinary}"
    printf 'old-cronet\n' >"${singBoxCronet}"
    chmod 755 "${xrayBinary}" "${singBoxBinary}"

    PADM_XRAY_BINARY="${xrayBinary}"
    PADM_SINGBOX_BINARY="${singBoxBinary}"
    xrayCoreCPUVendor=linux-64
    singBoxCoreCPUVendor=-linux-amd64
    REGRESSION_STATUS_CARD_LOG="${statusLog}"
    REGRESSION_SUCCESS_CARD_LOG="${successLog}"
    : >"${statusLog}"
    : >"${successLog}"
    : >"${serviceLog}"
    : >"${copyFailureLog}"

    padmIsSafeAbsolutePath() { return 0; }
    padmCreateTempPath() {
        local resultVar=$1
        local path
        shift
        if [[ "${1:-}" == "-d" ]]; then
            path=$(mktemp -d "${root}/tmp/core.XXXXXX") || return 1
        else
            path=$(mktemp "${root}/tmp/core.XXXXXX") || return 1
        fi
        printf -v "${resultVar}" '%s' "${path}"
    }
    padmRemoveCleanupPath() {
        rm -rf "$1"
    }
    padmForgetCleanupPath() { return 0; }
    downloadGitHubReleaseAsset() {
        local outputDir= assetName=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -P)
                outputDir=$2
                shift 2
                ;;
            *)
                assetName=$1
                shift
                ;;
            esac
        done
        mkdir -p "${outputDir}"
        : >"${outputDir}/${assetName}"
    }
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
        return 0
    }
    cp() {
        local args=("$@")
        local sourcePath="${args[$((${#args[@]} - 2))]}"
        local targetPath="${args[$((${#args[@]} - 1))]}"
        if [[ "${restoreCopyShouldFail}" == "true" && "${sourcePath}" == "${xrayBinary}.bak.restore-fail" &&
            "${targetPath}" == "${root}"/tmp/core.* ]]; then
            printf 'restore-xray\n' >>"${copyFailureLog}"
            return 1
        fi
        if [[ "${targetPath}" == "${root}"/tmp/core.* && "${sourcePath}" == "${root}"/tmp/core.*/xray ]]; then
            printf 'xray\n' >>"${copyFailureLog}"
            return 1
        fi
        if [[ "${targetPath}" == "${root}"/tmp/core.* &&
            "${sourcePath}" == "${root}"/tmp/core.*/sing-box-1.2.3-linux-amd64/libcronet.so ]]; then
            printf 'sing-box\n' >>"${copyFailureLog}"
            return 1
        fi
        command cp "$@"
    }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "$1" == "start" && "${xrayStartShouldFail}" == "true" ]] && return 1
        return 0
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "$1" == "start" && "${singBoxStartShouldFail}" == "true" ]] && return 1
        return 0
    }
    xrayRunning() { return 1; }
    singBoxRunning() { return 1; }
    validateXrayConfigWithBinary() { return 0; }
    validateSingBoxConfigWithBinary() { return 0; }

    SERVICE_QUEUE_ALLOW_FAILURE=
    set +e
    installDownloadedXrayBinary v1.2.3 >/dev/null 2>&1
    xrayRc=$?
    installDownloadedSingBoxBinary v1.2.3 >/dev/null 2>&1
    singBoxRc=$?
    set -e

    [[ "${xrayRc}" == "1" ]]
    [[ "${singBoxRc}" == "1" ]]
    [[ "$(<"${xrayBinary}")" == "old-xray" ]]
    [[ "$(<"${singBoxBinary}")" == "old-sing-box" ]]
    grep -qx 'xray' "${copyFailureLog}"
    grep -qx 'sing-box' "${copyFailureLog}"
    grep -q 'Xray-core 更新失败' "${statusLog}"
    grep -q 'sing-box 更新失败' "${statusLog}"
    grep -q '旧服务已尝试恢复启动' "${statusLog}"
    ! grep -q 'Xray-core更新成功' "${successLog}"
    ! grep -q 'sing-box更新成功' "${successLog}"
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    grep -qx 'sing-box:start:true' "${serviceLog}"
    [[ -z "${SERVICE_QUEUE_ALLOW_FAILURE}" ]]

    : >"${statusLog}"
    : >"${serviceLog}"
    printf 'new-xray\n' >"${xrayBinary}"
    printf 'old-xray\n' >"${xrayBinary}.bak.service-fail"
    xrayStartShouldFail=true
    coreSetManualCheckMessage() {
        printf "manual-check:%s|%s\n" "$2" "$3" >>"${serviceLog}"
        printf -v "$1" "%s，请手动检查%s" "$2" "$3"
    }
    set +e
    finalizeFailedCoreBinaryInstall "Xray-core" "${xrayBinary}.bak.service-fail" "${xrayBinary}" handleXray "/tmp/xray.log" >/dev/null 2>&1
    xrayRc=$?
    set -e
    xrayStartShouldFail=
    [[ "${xrayRc}" == "1" ]]
    [[ "$(<"${xrayBinary}")" == "old-xray" ]]
    [[ ! -e "${xrayBinary}.bak.service-fail" ]]
    grep -q '旧服务恢复启动失败，请手动检查服务状态' "${statusLog}"
    grep -q 'manual-check:旧服务恢复启动失败|服务状态' "${serviceLog}"
    grep -qx 'xray:start:true' "${serviceLog}"

    : >"${statusLog}"
    : >"${serviceLog}"
    printf 'new-xray\n' >"${xrayBinary}"
    printf 'old-xray\n' >"${xrayBinary}.bak.restore-fail"
    restoreCopyShouldFail=true
    set +e
    finalizeFailedCoreBinaryInstall "Xray-core" "${xrayBinary}.bak.restore-fail" "${xrayBinary}" handleXray "/tmp/xray.log" >/dev/null 2>&1
    xrayRc=$?
    set -e
    restoreCopyShouldFail=
    [[ "${xrayRc}" == "1" ]]
    [[ "$(<"${xrayBinary}")" == "new-xray" ]]
    [[ -e "${xrayBinary}.bak.restore-fail" ]]
    grep -q '旧二进制恢复失败' "${statusLog}"
    grep -q '旧二进制未恢复，已跳过服务启动' "${statusLog}"
    ! grep -q 'xray:start:true' "${serviceLog}"
)

runSingBoxCronetRollbackRegression() (
    local root="${TMP_DIR}/sing-box-cronet-rollback"
    local singBoxBinary="${root}/sing-box/sing-box"
    local singBoxCronet="${root}/sing-box/libcronet.so"
    local statusLog="${root}/status.log"
    local successLog="${root}/success.log"
    local serviceLog="${root}/service.log"
    local copyFailureLog="${root}/copy-failure.log"
    local singBoxRc
    local singBoxStartShouldFail=

    mkdir -p "$(dirname "${singBoxBinary}")" "${root}/tmp"
    printf 'old-sing-box\n' >"${singBoxBinary}"
    printf 'old-cronet\n' >"${singBoxCronet}"
    chmod 755 "${singBoxBinary}"

    PADM_SINGBOX_BINARY="${singBoxBinary}"
    singBoxCoreCPUVendor=-linux-amd64
    REGRESSION_STATUS_CARD_LOG="${statusLog}"
    REGRESSION_SUCCESS_CARD_LOG="${successLog}"
    : >"${statusLog}"
    : >"${successLog}"
    : >"${serviceLog}"
    : >"${copyFailureLog}"

    padmIsSafeAbsolutePath() { return 0; }
    padmCreateTempPath() {
        local resultVar=$1
        local path
        shift
        if [[ "${1:-}" == "-d" ]]; then
            path=$(mktemp -d "${root}/tmp/core.XXXXXX") || return 1
        else
            path=$(mktemp "${root}/tmp/core.XXXXXX") || return 1
        fi
        printf -v "${resultVar}" '%s' "${path}"
    }
    padmRemoveCleanupPath() { rm -rf "$1"; }
    padmForgetCleanupPath() { return 0; }
    downloadGitHubReleaseAsset() {
        local outputDir= assetName=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -P)
                outputDir=$2
                shift 2
                ;;
            *)
                assetName=$1
                shift
                ;;
            esac
        done
        mkdir -p "${outputDir}"
        : >"${outputDir}/${assetName}"
    }
    tar() {
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
        return 0
    }
    cp() {
        local args=("$@")
        local sourcePath="${args[$((${#args[@]} - 2))]}"
        local targetPath="${args[$((${#args[@]} - 1))]}"
        if [[ "${targetPath}" == "${root}"/tmp/core.* &&
            "${sourcePath}" == "${root}"/tmp/core.*/sing-box-1.2.3-linux-amd64/libcronet.so ]]; then
            printf 'cronet-copy-fail\n' >>"${copyFailureLog}"
            return 1
        fi
        command cp "$@"
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "$1" == "start" ]] && printf 'cronet-at-start:%s\n' "$(<"${singBoxCronet}")" >>"${serviceLog}"
        [[ "$1" == "start" && "${singBoxStartShouldFail}" == "true" ]] && return 1
        return 0
    }
    singBoxRunning() { return 1; }
    validateSingBoxConfigWithBinary() { return 0; }

    SERVICE_QUEUE_ALLOW_FAILURE=
    set +e
    installDownloadedSingBoxBinary v1.2.3 >/dev/null 2>&1
    singBoxRc=$?
    set -e

    [[ "${singBoxRc}" == "1" ]]
    [[ "$(<"${singBoxBinary}")" == "old-sing-box" ]]
    [[ "$(<"${singBoxCronet}")" == "old-cronet" ]]
    grep -qx 'cronet-copy-fail' "${copyFailureLog}"
    grep -q 'sing-box 更新失败' "${statusLog}"
    grep -q '旧服务已尝试恢复启动' "${statusLog}"
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    grep -qx 'sing-box:start:true' "${serviceLog}"
    grep -qx 'cronet-at-start:old-cronet' "${serviceLog}"
    [[ -z "${SERVICE_QUEUE_ALLOW_FAILURE}" ]]

    : >"${statusLog}"
    : >"${serviceLog}"
    printf 'new-sing-box\n' >"${singBoxBinary}"
    printf 'old-sing-box\n' >"${singBoxBinary}.bak.service-fail"
    printf 'new-cronet\n' >"${singBoxCronet}"
    printf 'old-cronet\n' >"${singBoxCronet}.bak.service-fail"
    singBoxStartShouldFail=true
    set +e
    finalizeFailedSingBoxBinaryInstall "${singBoxBinary}.bak.service-fail" "${singBoxBinary}" "${singBoxCronet}.bak.service-fail" "${singBoxCronet}" "/tmp/sing-box.log" >/dev/null 2>&1
    singBoxRc=$?
    set -e
    singBoxStartShouldFail=
    [[ "${singBoxRc}" == "1" ]]
    [[ "$(<"${singBoxBinary}")" == "old-sing-box" ]]
    [[ "$(<"${singBoxCronet}")" == "old-cronet" ]]
    [[ ! -e "${singBoxBinary}.bak.service-fail" ]]
    [[ ! -e "${singBoxCronet}.bak.service-fail" ]]
    grep -q '旧服务恢复启动失败，请手动检查服务状态' "${statusLog}"
    grep -qx 'sing-box:start:true' "${serviceLog}"
)

runFinalizeSingBoxBinaryInstallRollbackRegression() (
    local root="${TMP_DIR}/finalize-sing-box-rollback"
    local singBoxBinary="${root}/sing-box/sing-box"
    local singBoxCronet="${root}/sing-box/libcronet.so"
    local statusLog="${root}/status.log"
    local serviceLog="${root}/service.log"
    local singBoxRc
    local singBoxStartShouldFail=

    mkdir -p "$(dirname "${singBoxBinary}")"
    : >"${statusLog}"
    : >"${serviceLog}"
    printf 'new-sing-box\n' >"${singBoxBinary}"
    printf 'old-sing-box\n' >"${singBoxBinary}.bak"
    printf 'new-cronet\n' >"${singBoxCronet}"
    printf 'old-cronet\n' >"${singBoxCronet}.bak"
    chmod 755 "${singBoxBinary}" "${singBoxBinary}.bak"

    REGRESSION_STATUS_CARD_LOG="${statusLog}"
    padmIsSafeAbsolutePath() { return 0; }
    coreSetManualCheckMessage() {
        printf "manual-check:%s|%s\n" "$2" "$3" >>"${serviceLog}"
        printf -v "$1" "%s，请手动检查%s" "$2" "$3"
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "$1" == "start" ]] && printf 'cronet-at-start:%s\n' "$(<"${singBoxCronet}")" >>"${serviceLog}"
        [[ "$1" == "start" && "${singBoxStartShouldFail}" == "true" ]] && return 1
        return 0
    }

    singBoxStartShouldFail=true
    set +e
    finalizeFailedSingBoxBinaryInstall "${singBoxBinary}.bak" "${singBoxBinary}" "${singBoxCronet}.bak" "${singBoxCronet}" "/tmp/sing-box.log" >/dev/null 2>&1
    singBoxRc=$?
    set -e
    singBoxStartShouldFail=

    [[ "${singBoxRc}" == "1" ]]
    [[ "$(<"${singBoxBinary}")" == "old-sing-box" ]]
    [[ "$(<"${singBoxCronet}")" == "old-cronet" ]]
    [[ ! -e "${singBoxBinary}.bak" ]]
    [[ ! -e "${singBoxCronet}.bak" ]]
    grep -q '旧服务恢复启动失败，请手动检查服务状态' "${statusLog}"
    grep -q 'manual-check:旧服务恢复启动失败|服务状态' "${serviceLog}"
    grep -qx 'sing-box:start:true' "${serviceLog}"
    grep -qx 'cronet-at-start:old-cronet' "${serviceLog}"

    : >"${statusLog}"
    : >"${serviceLog}"
    rm -f "${singBoxCronet}.bak"
    rm -f "${singBoxCronet}"
    mkdir -p "${singBoxCronet}"
    set +e
    finalizeFailedSingBoxBinaryInstall "${singBoxBinary}.bak" "${singBoxBinary}" "${singBoxCronet}.bak" "${singBoxCronet}" "/tmp/sing-box.log" >/dev/null 2>&1
    singBoxRc=$?
    set -e

    [[ "${singBoxRc}" == "1" ]]
    [[ -d "${singBoxCronet}" ]]
    grep -q "manual-check:libcronet.so 恢复失败| ${singBoxCronet}" "${serviceLog}"
    grep -q "libcronet.so 恢复失败，请手动检查 ${singBoxCronet}" "${statusLog}"
    ! grep -qx 'sing-box:start:true' "${serviceLog}"
)

runCoreUpgradeRejectsDirectoryTargetRegression() (
    local root="${TMP_DIR}/core-upgrade-directory-target"
    local xrayBinary="${root}/xray/xray"
    local singBoxBinary="${root}/sing-box/sing-box"
    local errorLog="${root}/error.log"
    local serviceLog="${root}/service.log"
    local xrayRc singBoxRc

    mkdir -p "${xrayBinary}" "${singBoxBinary}" "${root}/tmp"

    PADM_XRAY_BINARY="${xrayBinary}"
    PADM_SINGBOX_BINARY="${singBoxBinary}"
    xrayCoreCPUVendor=linux-64
    singBoxCoreCPUVendor=-linux-amd64

    : >"${errorLog}"
    : >"${serviceLog}"

    padmIsSafeAbsolutePath() { return 0; }
    padmCreateTempPath() {
        local resultVar=$1
        local path
        shift
        if [[ "${1:-}" == "-d" ]]; then
            path=$(mktemp -d "${root}/tmp/core.XXXXXX") || return 1
        else
            path=$(mktemp "${root}/tmp/core.XXXXXX") || return 1
        fi
        printf -v "${resultVar}" '%s' "${path}"
    }
    padmRemoveCleanupPath() { rm -rf "$1"; }
    padmForgetCleanupPath() { return 0; }
    downloadGitHubReleaseAsset() {
        local outputDir= assetName=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -P)
                outputDir=$2
                shift 2
                ;;
            *)
                assetName=$1
                shift
                ;;
            esac
        done
        mkdir -p "${outputDir}"
        : >"${outputDir}/${assetName}"
    }
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
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        return 0
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        return 0
    }
    xrayRunning() { return 1; }
    singBoxRunning() { return 1; }
    validateXrayConfigWithBinary() { return 0; }
    validateSingBoxConfigWithBinary() { return 0; }
    coreSetManualCheckMessage() {
        printf "manual-check:%s|%s\n" "$2" "$3" >>"${serviceLog}"
        printf -v "$1" "%s，请手动检查%s" "$2" "$3"
    }

    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    set +e
    installDownloadedXrayBinary v1.2.3 >/dev/null 2>&1
    xrayRc=$?
    set -e

    set +e
    installDownloadedSingBoxBinary v1.2.3 >/dev/null 2>&1
    singBoxRc=$?
    set -e

    [[ "${xrayRc}" == "1" ]]
    [[ "${singBoxRc}" == "1" ]]
    [[ -d "${xrayBinary}" ]]
    [[ -d "${singBoxBinary}" ]]
    [[ ! -e "${xrayBinary}/xray" ]]
    [[ ! -e "${singBoxBinary}/sing-box" ]]
    [[ ! -e "${singBoxBinary}/libcronet.so" ]]
    grep -q "manual-check:Xray-core安装目标异常| ${xrayBinary}" "${serviceLog}"
    grep -q "manual-check:sing-box安装目标异常| ${singBoxBinary}" "${serviceLog}"
    grep -q "Xray-core安装目标异常，请手动检查 ${xrayBinary}" "${errorLog}"
    grep -q "sing-box安装目标异常，请手动检查 ${singBoxBinary}" "${errorLog}"
    ! grep -q '^xray:' "${serviceLog}"
    ! grep -q '^sing-box:' "${serviceLog}"
)

runLegacyCoreUpgradeKeepsExistingBinaryRegression() (
    local root="${TMP_DIR}/legacy-core-upgrade-keeps-existing"
    local xrayBinary="${root}/xray/xray"
    local singBoxBinary="${root}/sing-box/sing-box"
    local callLog="${root}/calls.log"
    local queryLog="${root}/queries.log"
    local rmLog="${root}/rm.log"
    local rc

    mkdir -p "$(dirname "${xrayBinary}")" "$(dirname "${singBoxBinary}")"
    cat >"${xrayBinary}" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat >"${singBoxBinary}" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod 755 "${xrayBinary}" "${singBoxBinary}"

    PADM_XRAY_BINARY="${xrayBinary}"
    PADM_SINGBOX_BINARY="${singBoxBinary}"
    : >"${callLog}"
    : >"${queryLog}"
    : >"${rmLog}"
    lastInstallationConfig=

    readInstallType() { return 0; }
    errorCard() { return 0; }
    getSingBoxCurrentVersion() { printf 'vold-sing-box\n'; }
    coreLatestReleaseTag() { printf 'v1.2.3\n'; }
    autoRead() { printf -v "$3" 'y'; }
    ensureXrayGeoFiles() {
        printf 'geo:%s\n' "$*" >>"${callLog}"
        return 0
    }
    installDownloadedXrayBinary() {
        printf 'upgrade-xray:%s\n' "$1" >>"${callLog}"
        return 0
    }
    installDownloadedSingBoxBinary() {
        printf 'upgrade-sing-box:%s\n' "$1" >>"${callLog}"
        return 0
    }
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    installXray 1 false >/dev/null 2>&1
    installSingBox 1 >/dev/null 2>&1

    [[ -x "${xrayBinary}" ]]
    [[ -x "${singBoxBinary}" ]]
    grep -qx "geo:$(dirname "${xrayBinary}")" "${callLog}"
    grep -qx 'upgrade-xray:v1.2.3' "${callLog}"
    grep -qx 'upgrade-sing-box:v1.2.3' "${callLog}"
    ! grep -q -- "${xrayBinary}" "${rmLog}"
    ! grep -q -- "${singBoxBinary}" "${rmLog}"

    lastInstallationConfig=true
    coreLatestReleaseTag() { printf 'query\n' >>"${queryLog}"; return 1; }
    autoRead() { printf 'prompt\n' >>"${queryLog}"; return 1; }
    set +e
    installSingBox 1 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
    [[ ! -s "${queryLog}" ]]

    lastInstallationConfig=
    autoRead() { printf 'prompt\n' >>"${queryLog}"; printf -v "$3" 'n'; }
    : >"${queryLog}"
    installSingBox 1 >/dev/null 2>&1
    [[ "$(<"${queryLog}")" == "prompt" ]]
)

runSingBoxDownloadArtifactsCleanupRegression() (
    local root="${TMP_DIR}/sing-box-artifacts-cleanup"
    local installDir="${root}/install"
    local rmLog="${root}/rm.log"
    local rc

    mkdir -p "${installDir}/sing-box-1.2.3-linux-amd64" "${installDir}/sing-box-keep"
    printf 'archive\n' >"${installDir}/sing-box-1.2.3-linux-amd64.tar.gz"
    printf 'current\n' >"${installDir}/sing-box"
    printf 'keep\n' >"${installDir}/sing-box-keep/sentinel"
    : >"${rmLog}"

    singBoxCoreCPUVendor=-linux-amd64
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    cleanSingBoxDownloadArtifacts "${installDir}" v1.2.3
    [[ ! -e "${installDir}/sing-box-1.2.3-linux-amd64.tar.gz" ]]
    [[ ! -e "${installDir}/sing-box-1.2.3-linux-amd64" ]]
    [[ -f "${installDir}/sing-box" ]]
    [[ -f "${installDir}/sing-box-keep/sentinel" ]]
    grep -qxF "rm:-f -- ${installDir}/sing-box-1.2.3-linux-amd64.tar.gz" "${rmLog}"
    grep -qxF "rm:-rf -- ${installDir}/sing-box-1.2.3-linux-amd64" "${rmLog}"
    ! grep -qF 'sing-box-keep' "${rmLog}"

    set +e
    cleanSingBoxDownloadArtifacts relative-install v1.2.3 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
)

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

runCoreReleaseArchiveRejectsUnsafePathRegression() { runCoreReleaseArchiveRejectsRegression unsafe-path; }

runCoreReleaseArchiveRejectsSymlinkPayloadRegression() { runCoreReleaseArchiveRejectsRegression symlink-payload; }

runCoreFirstInstallLeavesNoLiveArtifactsOnFailureRegression() (
    local rootRel="${TMP_DIR}/core-first-install-failure"
    local root
    local xrayDir
    local singBoxDir
    local errorLog
    local rmLog
    local callLog
    local xrayRc singBoxRc

    mkdir -p "${rootRel}/tmp" "${rootRel}/sing-box"
    root=$(cd -- "${rootRel}" && pwd -P)
    xrayDir="${root}/xray"
    singBoxDir="${root}/sing-box"
    errorLog="${root}/error.log"
    rmLog="${root}/rm.log"
    callLog="${root}/call.log"
    : >"${errorLog}"
    : >"${rmLog}"
    : >"${callLog}"

    PADM_XRAY_BINARY="${xrayDir}/xray"
    PADM_SINGBOX_BINARY="${singBoxDir}/sing-box"
    xrayCoreCPUVendor=linux-64
    singBoxCoreCPUVendor=-linux-amd64
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    TMPDIR="${root}/tmp"

    readInstallType() { return 0; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    coreLatestReleaseTag() { printf 'v1.2.3\n'; }
    checkVersionNotEmpty() { [[ -n "$1" ]]; }
    ensureXrayGeoFiles() { printf 'geo:%s\n' "$*" >>"${callLog}"; return 0; }
    padmCreateTempPath() {
        local resultVar=$1
        local path
        shift
        printf 'mktemp:%s\n' "$*" >>"${callLog}"
        if [[ "${1:-}" == "-d" ]]; then
            path=$(mktemp -d "${TMPDIR}/core.XXXXXX") || return 1
        else
            path=$(mktemp "${TMPDIR}/core.XXXXXX") || return 1
        fi
        printf -v "${resultVar}" '%s' "${path}"
    }
    padmRemoveCleanupPath() {
        printf 'rm:%s\n' "$1" >>"${rmLog}"
        rm -rf "$1"
    }
    downloadGitHubReleaseAsset() {
        local outputDir= assetName=
        printf 'download:%s\n' "$*" >>"${callLog}"
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -P)
                outputDir=$2
                shift 2
                ;;
            *)
                assetName=$1
                shift
                ;;
            esac
        done
        mkdir -p "${outputDir}"
        : >"${outputDir}/${assetName}"
    }
    unzip() { printf 'unzip:%s\n' "$*" >>"${callLog}"; return 1; }
    tar() { printf 'tar:%s\n' "$*" >>"${callLog}"; return 1; }

    set +e
    installXray 1 false >/dev/null 2>&1
    xrayRc=$?
    installSingBox 1 >/dev/null 2>&1
    singBoxRc=$?
    set -e

    [[ "${xrayRc}" == "1" ]]
    [[ "${singBoxRc}" == "1" ]]
    [[ ! -e "${xrayDir}/xray" ]]
    [[ ! -e "${singBoxDir}/sing-box" ]]
    [[ ! -e "${singBoxDir}/libcronet.so" ]]
    grep -q 'Xray-core解压失败' "${errorLog}"
    grep -q 'sing-box解压失败' "${errorLog}"
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

runNetworkCheckReturnFailureRegression() (
    local root="${TMP_DIR}/network-check-return"
    local dnsRcFile="${root}/dns.rc"
    local ipRcFile="${root}/ip.rc"
    local portRcFile="${root}/port.rc"
    local templateRcFile="${root}/template.rc"
    local writeProbe="${root}/template.write"
    local serviceLog="${root}/port-services.log"
    local cleanLog="${root}/port-clean.log"
    local writeLog="${root}/port-write.log"
    local listenerKillLog="${root}/listener-kill.log"
    local publicIpCurlLog="${root}/public-ip-curl.log"
    local firewallLog="${root}/firewall.log"
    local mode=
    local dnsShellRc ipShellRc portShellRc templateShellRc

    mkdir -p "${root}/nginx"
    PADM_FIREWALL_STATE_FILE="${root}/firewall.state"
    eval "$(declare -f cleanAgentNginxConf | sed '1s/^cleanAgentNginxConf/originalCleanAgentNginxConf/')"

    if allowPort 0 || allowPort 65536 || allowPort 2000:1000 || allowPort 443 sctp; then
        return 1
    fi

    local ufwTcpAdded=false
    local ufwUdpAdded=false
    local ufwActive=true
    local ufwUdpAllowShouldFail=false
    : >"${firewallLog}"
    dpkg() {
        [[ "$1" == "-l" ]] || return 1
        printf 'ii  ufw  0  all  firewall\n'
    }
    ufw() {
        case "$1" in
        status)
            if [[ "${ufwActive}" == "true" ]]; then
                printf 'Status: active\n1443/tcp ALLOW Anywhere\n'
                [[ "${ufwTcpAdded}" == "true" ]] && printf '443/tcp ALLOW Anywhere\n'
                [[ "${ufwUdpAdded}" == "true" ]] && printf '443/udp ALLOW Anywhere\n'
            else
                printf 'Status: inactive\n'
            fi
            return 0
            ;;
        show)
            [[ "$2" == "added" ]] || return 1
            printf 'Added user rules:\n'
            [[ "${ufwTcpAdded}" == "true" ]] && printf 'ufw allow 443/tcp\n'
            [[ "${ufwUdpAdded}" == "true" ]] && printf 'ufw allow 443/udp\n'
            return 0
            ;;
        allow)
            printf 'ufw:allow:%s\n' "$2" >>"${firewallLog}"
            [[ "$2" != "443/udp" || "${ufwUdpAllowShouldFail}" != "true" ]] || return 1
            [[ "$2" == "443/tcp" ]] && ufwTcpAdded=true
            [[ "$2" == "443/udp" ]] && ufwUdpAdded=true
            return 0
            ;;
        delete)
            printf 'ufw:delete:%s\n' "$3" >>"${firewallLog}"
            [[ "$3" == "443/tcp" ]] && ufwTcpAdded=false
            [[ "$3" == "443/udp" ]] && ufwUdpAdded=false
            return 0
            ;;
        *) return 1 ;;
        esac
    }
    sudo() { "$@"; }
    allowPort 443
    allowPort 443 udp
    grep -qx 'ufw:allow:443/tcp' "${firewallLog}"
    grep -qx 'ufw:allow:443/udp' "${firewallLog}"
    : >"${firewallLog}"
    allowPort 443
    allowPort 443 udp
    [[ ! -s "${firewallLog}" ]]
    grep -qx 'port:ufw:tcp:443' "${PADM_FIREWALL_STATE_FILE}"
    grep -qx 'port:ufw:udp:443' "${PADM_FIREWALL_STATE_FILE}"
    lsof() {
        if [[ "$*" == "-nP -iTCP:443 -sTCP:LISTEN" && "${tcpListenerPresent:-false}" == "true" ]]; then
            printf 'nginx 123 root 6u IPv4 TCP *:443 (LISTEN)\n'
            return 0
        fi
        if [[ "$*" == "-nP -iUDP:443" && "${udpListenerPresent:-false}" == "true" ]]; then
            printf 'wireguard 123 root 6u IPv4 UDP *:443\n'
            return 0
        fi
        return 1
    }
    local tcpListenerPresent=true
    local udpListenerPresent=true
    denyPort 443
    denyPort 443 udp
    ! grep -qx 'ufw:delete:443/tcp' "${firewallLog}"
    ! grep -qx 'ufw:delete:443/udp' "${firewallLog}" || return 1
    grep -qx 'port:ufw:tcp:443' "${PADM_FIREWALL_STATE_FILE}"
    grep -qx 'port:ufw:udp:443' "${PADM_FIREWALL_STATE_FILE}" || return 1
    tcpListenerPresent=false
    udpListenerPresent=false
    denyPort 443
    denyPort 443 udp
    grep -qx 'ufw:delete:443/tcp' "${firewallLog}"
    [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]

    (
        local concurrentState="${root}/concurrent-firewall.state"
        local firstPid secondPid firstRc secondRc
        PADM_FIREWALL_STATE_FILE="${concurrentState}"
        PADM_FIREWALL_STATE_LOCK_TIMEOUT=5
        rm -f "${concurrentState}" "${concurrentState}.lock"
        commitGeneratedFile() {
            local tmpFile=$1
            local targetFile=$2
            local mode=${3:-}
            [[ -z "${mode}" ]] || chmod "${mode}" "${tmpFile}"
            sleep 0.1
            mv -f -- "${tmpFile}" "${targetFile}" || return 1
            padmForgetCleanupPath "${tmpFile}"
        }
        padmFirewallStateAdd 'port:ufw:tcp:30001' &
        firstPid=$!
        padmFirewallStateAdd 'port:ufw:tcp:30002' &
        secondPid=$!
        set +e
        wait "${firstPid}"
        firstRc=$?
        wait "${secondPid}"
        secondRc=$?
        set -e
        [[ "${firstRc}" == "0" ]]
        [[ "${secondRc}" == "0" ]]
        grep -qx 'port:ufw:tcp:30001' "${concurrentState}"
        grep -qx 'port:ufw:tcp:30002' "${concurrentState}"
    )

    padmFirewallStateAdd 'port:ufw:tcp:443'
    : >"${firewallLog}"
    failAfterPortAllow() {
        allowPort 443
        return 1
    }
    if padmRunPortAllowTransaction failAfterPortAllow; then
        return 1
    fi
    grep -qx 'ufw:allow:443/tcp' "${firewallLog}"
    grep -qx 'ufw:delete:443/tcp' "${firewallLog}"
    [[ "${ufwTcpAdded}" == "false" ]]
    [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]

    : >"${firewallLog}"
    allowPort 1443
    denyPort 1443
    [[ ! -s "${firewallLog}" ]]
    allowPort 443
    allowPort 443 udp
    ufwActive=false
    : >"${firewallLog}"
    cleanupPadmFirewallRules
    grep -qx 'ufw:delete:443/tcp' "${firewallLog}"
    grep -qx 'ufw:delete:443/udp' "${firewallLog}"
    [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]
    ufwActive=true
    ufwUdpAllowShouldFail=true
    : >"${firewallLog}"
    if allowPortTcpAndUdp 443; then
        return 1
    fi
    ufwUdpAllowShouldFail=false
    grep -qx 'ufw:delete:443/tcp' "${firewallLog}"
    [[ "${ufwTcpAdded}" == "false" ]]
    [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]

    ufwActive=false
    local fallbackFirewalldAdded=false
    systemctl() { [[ "$*" == "is-active --quiet firewalld" ]]; }
    firewall-cmd() {
        case "$*" in
        *--list-ports*) [[ "${fallbackFirewalldAdded}" == "true" ]] && printf '2443/tcp\n' ;;
        *--add-port=2443/tcp*) fallbackFirewalldAdded=true ;;
        *--remove-port=2443/tcp*) fallbackFirewalldAdded=false ;;
        *--reload*) return 0 ;;
        *) return 1 ;;
        esac
    }
    allowPort 2443
    [[ "${fallbackFirewalldAdded}" == "true" ]]
    grep -qx 'port:firewalld:tcp:2443' "${PADM_FIREWALL_STATE_FILE}"
    denyPort 2443
    [[ "${fallbackFirewalldAdded}" == "false" ]]
    unset -f systemctl firewall-cmd
    unset -f dpkg ufw sudo

    local firewalldPermanentTcpAdded=false
    local firewalldRuntimeTcpAdded=false
    local firewalldReloadShouldFail=false
    : >"${firewallLog}"
    dpkg() { return 1; }
    systemctl() {
        if [[ "$*" == "status firewalld" || "$*" == "is-active --quiet firewalld" ]]; then
            printf 'Active: active (running)\n'
            return 0
        fi
        return 1
    }
    firewall-cmd() {
        if [[ "$*" != "--reload" && " $* " != *" --zone=public "* ]]; then
            return 1
        fi
        case "$*" in
        *--list-ports*)
            printf '443/udp'
            [[ "${firewalldPermanentTcpAdded}" == "true" ]] && printf ' 443/tcp'
            printf '\n'
            ;;
        *--add-port=*)
            for arg in "$@"; do
                case "${arg}" in
                --add-port=*)
                    printf 'firewalld:add:%s\n' "${arg}" >>"${firewallLog}"
                    ;;
                esac
            done
                firewalldPermanentTcpAdded=true
            ;;
        *--remove-port=*)
            for arg in "$@"; do
                case "${arg}" in
                --remove-port=*)
                    printf 'firewalld:remove:%s\n' "${arg}" >>"${firewallLog}"
                    ;;
                esac
            done
                firewalldPermanentTcpAdded=false
            ;;
        *--reload*)
            [[ "${firewalldReloadShouldFail}" != "true" ]] || return 1
            firewalldRuntimeTcpAdded=${firewalldPermanentTcpAdded}
            ;;
        *) return 1 ;;
        esac
    }
    allowPort 443
    grep -qx 'firewalld:add:--add-port=443/tcp' "${firewallLog}"
    grep -qx 'port:firewalld:tcp:443' "${PADM_FIREWALL_STATE_FILE}"
    [[ "${firewalldRuntimeTcpAdded}" == "true" ]]
    firewalldReloadShouldFail=true
    if denyPort 443; then
        return 1
    fi
    [[ "${firewalldPermanentTcpAdded}" == "false" ]]
    [[ "${firewalldRuntimeTcpAdded}" == "true" ]]
    grep -qx 'port:firewalld:tcp:443' "${PADM_FIREWALL_STATE_FILE}"
    firewalldReloadShouldFail=false
    denyPort 443
    grep -qx 'firewalld:remove:--remove-port=443/tcp' "${firewallLog}"
    [[ "${firewalldRuntimeTcpAdded}" == "false" ]]
    [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]
    unset -f dpkg systemctl firewall-cmd

    : >"${firewallLog}"
    local iptablesTcpAdded=false
    local iptablesTcpPersisted=false
    local iptablesSaveShouldFail=false
    dpkg() { return 1; }
    systemctl() {
        [[ "$*" == "is-active --quiet netfilter-persistent" ]]
    }
    rc-update() { return 1; }
    dpkg-query() { printf 'ii\n'; }
    iptables() {
        if [[ "$1" == "-L" ]]; then
            printf 'ACCEPT tcp -- anywhere anywhere /* allow 1443/tcp(neil1123-vip) */\n'
            [[ "${iptablesTcpAdded}" == "true" ]] && printf 'ACCEPT tcp -- anywhere anywhere /* allow 443/tcp(neil1123-vip) */\n'
            return 0
        elif [[ "$1" == "-I" ]]; then
            printf 'iptables:add:%s\n' "$*" >>"${firewallLog}"
            iptablesTcpAdded=true
        elif [[ "$1" == "-D" ]]; then
            printf 'iptables:delete:%s\n' "$*" >>"${firewallLog}"
            iptablesTcpAdded=false
        fi
    }
    netfilter-persistent() {
        [[ "$1" == "save" ]] || return 1
        [[ "${iptablesSaveShouldFail}" != "true" ]] || return 1
        iptablesTcpPersisted=${iptablesTcpAdded}
    }
    allowPort 443
    grep -q '^iptables:add:-I INPUT -p tcp --dport 443 ' "${firewallLog}"
    grep -qx 'port:iptables:tcp:443' "${PADM_FIREWALL_STATE_FILE}"
    [[ "${iptablesTcpPersisted}" == "true" ]]
    iptablesSaveShouldFail=true
    if denyPort 443; then
        return 1
    fi
    [[ "${iptablesTcpAdded}" == "false" ]]
    [[ "${iptablesTcpPersisted}" == "true" ]]
    grep -qx 'port:iptables:tcp:443' "${PADM_FIREWALL_STATE_FILE}"
    iptablesSaveShouldFail=false
    denyPort 443
    grep -q '^iptables:delete:-D INPUT -p tcp --dport 443 ' "${firewallLog}"
    [[ "${iptablesTcpPersisted}" == "false" ]]
    [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]
    unset -f dpkg systemctl rc-update dpkg-query iptables netfilter-persistent

    errorCard() { return 0; }
    sleep() { return 0; }
    dig() { return 1; }
    curl() {
        printf '%s\n' "$*" >>"${publicIpCurlLog}"
        case "$*" in
        *" -4 "*) printf 'ip=203.0.113.10\n' ;;
        *" -6 "*) printf 'ip=2001:db8::10\n' ;;
        *) return 1 ;;
        esac
    }
    [[ "$(getPublicIP 4)" == "203.0.113.10" ]]
    [[ "$(getPublicIP 6)" == "2001:db8::10" ]]
    hasIPv6Connectivity
    grep -q -- 'https://www.cloudflare.com/cdn-cgi/trace' "${publicIpCurlLog}"
    grep -q -- '--connect-timeout 5' "${publicIpCurlLog}"
    grep -q -- '--max-time 10' "${publicIpCurlLog}"
    curl() { printf 'ip=not-an-ip\n'; }
    [[ -z "$(getPublicIP 4)" ]]
    unset -f curl
    (
        local publicIpErrorLog="${root}/public-ip-error.log"
        : >"${publicIpErrorLog}"
        errorCard() { printf '%s\n' "$*" >>"${publicIpErrorLog}"; }
        dig() { printf '203.0.113.10\n'; }
        getPublicIP() { return 0; }
        if checkDNSIP entry.example.com >/dev/null; then
            return 1
        fi
        grep -q '无法获取当前 VPS 公网 IPv4 地址' "${publicIpErrorLog}"
        grep -q 'curl 已安装' "${publicIpErrorLog}"
    )
    getPublicIP() { printf '203.0.113.10\n'; }

    (
        command() {
            if [[ "$1" == "-v" && "$2" == "dig" ]]; then
                return 1
            fi
            builtin command "$@"
        }
        dig() { : >"${root}/unexpected-dig-call"; return 127; }
        getent() {
            [[ "$1" == "ahostsv4" && "$2" == "entry.example.com" ]] || return 1
            printf '203.0.113.10 STREAM entry.example.com\n'
        }
        checkDNSIP entry.example.com >/dev/null
    )
    [[ ! -e "${root}/unexpected-dig-call" ]]

    set +e
    (
        set +e
        checkDNSIP bad.example.com >/dev/null 2>&1
        printf '%s\n' "$?" >"${dnsRcFile}"
    )
    dnsShellRc=$?
    (
        set +e
        checkIP "" >/dev/null 2>&1
        printf '%s\n' "$?" >"${ipRcFile}"
    )
    ipShellRc=$?
    set -e
    [[ "${dnsShellRc}" == "0" ]]
    [[ "${ipShellRc}" == "0" ]]
    [[ "$(<"${dnsRcFile}")" == "1" ]]
    [[ "$(<"${ipRcFile}")" == "1" ]]

    btDomain=
    nginxConfigPath="${root}/nginx/"
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "sing-box-stop-fail" ]] && return 1
        return 0
    }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "xray-stop-fail" ]] && return 1
        return 0
    }
    cleanAgentNginxConf() {
        printf 'clean:%s\n' "${mode}" >>"${cleanLog}"
        [[ "${mode}" != "clean-fail" ]]
    }
    allowPort() { return 0; }
    handleNginx() {
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "nginx-stop-fail" && "$1" == "stop" ]] && return 1
        [[ "${mode}" == "nginx-start-fail" && "$1" == "start" ]] && return 1
        return 0
    }
    hasIPv6Connectivity() { return 1; }
    writeCheckPortOpenNginxConfig() {
        printf 'write:%s\n' "${mode}" >>"${writeLog}"
        [[ "${mode}" != "write-fail" ]]
    }

    mode=clean-fail
    : >"${serviceLog}"
    : >"${cleanLog}"
    : >"${writeLog}"
    set +e
    (
        set +e
        checkPortOpen 443 example.com >/dev/null 2>&1
        printf '%s\n' "$?" >"${portRcFile}"
    )
    portShellRc=$?
    set -e
    [[ "${portShellRc}" == "0" ]]
    [[ "$(<"${portRcFile}")" == "1" ]]
    grep -qx 'clean:clean-fail' "${cleanLog}"
    [[ ! -s "${writeLog}" ]]

    mode=write-fail
    : >"${serviceLog}"
    : >"${cleanLog}"
    : >"${writeLog}"
    set +e
    (
        set +e
        checkPortOpen 443 example.com >/dev/null 2>&1
        printf '%s\n' "$?" >"${portRcFile}"
    )
    portShellRc=$?
    set -e
    [[ "${portShellRc}" == "0" ]]
    [[ "$(<"${portRcFile}")" == "1" ]]
    grep -qx 'write:write-fail' "${writeLog}"

    runPortServiceFailureCase() {
        local failureMode=$1
        local rc
        mode="${failureMode}"
        : >"${serviceLog}"
        : >"${cleanLog}"
        : >"${writeLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        set +e
        checkPortOpen 443 example.com >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    }

    runPortServiceFailureCase sing-box-stop-fail
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    ! grep -q '^xray:' "${serviceLog}"
    [[ ! -s "${writeLog}" ]]

    runPortServiceFailureCase xray-stop-fail
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    grep -qx 'xray:stop:true' "${serviceLog}"
    ! grep -q '^nginx:' "${serviceLog}"
    [[ ! -s "${writeLog}" ]]

    runPortServiceFailureCase nginx-stop-fail
    grep -qx 'nginx:stop:true' "${serviceLog}"
    [[ ! -s "${writeLog}" ]]

    runPortServiceFailureCase nginx-start-fail
    grep -qx 'nginx:start:true' "${serviceLog}"
    grep -qx 'write:nginx-start-fail' "${writeLog}"

    allowPort() {
        printf 'allow:%s\n' "$*" >>"${serviceLog}"
        return 1
    }
    mode=
    : >"${serviceLog}"
    : >"${cleanLog}"
    : >"${writeLog}"
    set +e
    (
        set +e
        checkPortOpen 443 example.com >/dev/null 2>&1
        printf '%s\n' "$?" >"${portRcFile}"
    )
    portShellRc=$?
    set -e
    [[ "${portShellRc}" == "0" ]]
    [[ "$(<"${portRcFile}")" == "1" ]]
    grep -qx 'allow:443' "${serviceLog}"
    ! grep -q '^sing-box:' "${serviceLog}"
    ! grep -q '^xray:' "${serviceLog}"
    ! grep -q '^nginx:' "${serviceLog}"
    [[ ! -s "${cleanLog}" ]]
    [[ ! -s "${writeLog}" ]]

    portProcessKind=padm
    lsof() {
        if [[ -s "${listenerKillLog}" && "$*" != "-t -a -i tcp:8443 -sTCP:LISTEN" ]]; then
            return 1
        fi
        case "$*" in
        "-i tcp:8443"|"-nP -i tcp:8443")
            case "${portProcessKind}" in
            padm) printf 'xray 123 root 3u IPv4 TCP *:8443 (LISTEN)\n' ;;
            nginx) printf 'nginx 123 root 3u IPv4 TCP *:8443 (LISTEN)\n' ;;
            openresty) printf 'openresty 123 root 3u IPv4 TCP *:8443 (LISTEN)\n' ;;
            mixed) printf 'nginx 123 root /etc/padm/site TCP *:8443 (LISTEN)\n' ;;
            other)
                printf 'listener 123 root 3u IPv4 TCP *:8443 (LISTEN)\n'
                printf 'client 456 root 4u IPv4 TCP 10.0.0.2:50000->198.51.100.10:8443 (ESTABLISHED)\n'
                ;;
            none) return 1 ;;
            esac
            ;;
        "-t -a -i tcp:8443 -sTCP:LISTEN")
            printf '123\n'
            ;;
        *)
            return 1
            ;;
        esac
    }
    autoRead() {
        printf -v "$3" 'y'
    }
    systemctl() {
        printf 'systemctl:%s\n' "$*" >>"${serviceLog}"
        return 0
    }
    runCheckPortStopFailureCase() {
        local failureMode=$1
        local processKind=$2
        local rc
        mode="${failureMode}"
        portProcessKind="${processKind}"
        : >"${serviceLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        set +e
        checkPort 8443 >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    }

    runCheckPortStopFailureCase xray-stop-fail padm
    grep -qx 'xray:stop:true' "${serviceLog}"
    ! grep -q '^sing-box:' "${serviceLog}"

    runCheckPortStopFailureCase sing-box-stop-fail padm
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'sing-box:stop:true' "${serviceLog}"

    for portProcessKind in nginx openresty mixed; do
        runCheckPortStopFailureCase nginx-stop-fail "${portProcessKind}"
        [[ ! -s "${serviceLog}" ]]
    done

    xargs() {
        [[ "$1" == "-r" && "$2" == "kill" ]] || return 1
        cat >"${listenerKillLog}"
    }
    portProcessKind=other
    : >"${listenerKillLog}"
    checkPort 8443 >/dev/null 2>&1
    grep -qx '123' "${listenerKillLog}"
    ! grep -q '456' "${listenerKillLog}"
    unset -f xargs

    local singBoxState=true
    local xrayState=true
    local nginxState=true
    local realityConf="${root}/reality-stream.conf"
    local realityState="${root}/reality-stream.state"
    local nginxMainConf="${root}/nginx.conf"
    export PADM_REALITY_STREAM_CONF_FILE="${realityConf}"
    export PADM_REALITY_STREAM_STATE_FILE="${realityState}"
    export PADM_REALITY_STREAM_NGINX_CONF="${nginxMainConf}"
    printf 'old-alone\n' >"${root}/nginx/alone.conf"
    printf 'old-stream\n' >"${realityConf}"
    printf 'old-state\n' >"${realityState}"
    cat >"${nginxMainConf}" <<EOF
events {}
# padm stream include start
include ${root}/stream.d/*.conf;
# padm stream include end
http {}
EOF
    local originalNginxMainConf
    originalNginxMainConf=$(<"${nginxMainConf}")
    allowPort() { return 0; }
    singBoxRunning() { [[ "${singBoxState}" == "true" ]]; }
    xrayRunning() { [[ "${xrayState}" == "true" ]]; }
    nginxRunning() { [[ "${nginxState}" == "true" ]]; }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "$1" == "stop" ]] && singBoxState=false
        [[ "$1" == "start" ]] && singBoxState=true
        return 0
    }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "$1" == "stop" ]] && xrayState=false
        [[ "$1" == "start" ]] && xrayState=true
        return 0
    }
    handleNginx() {
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ -n "${2:-}" ]] && printf 'nginx-mode:%s\n' "$*" >>"${serviceLog}"
        [[ "$1" == "stop" ]] && nginxState=false
        [[ "$1" == "start" ]] && nginxState=true
        return 0
    }
    cleanAgentNginxConf() {
        printf 'clean:%s\n' "${mode}" >>"${cleanLog}"
        originalCleanAgentNginxConf
    }

    mode=write-fail
    : >"${serviceLog}"
    set +e
    checkPortOpen 443 example.com >/dev/null 2>&1
    local restoreRc=$?
    set -e
    [[ "${restoreRc}" == "1" ]]
    [[ "$(<"${root}/nginx/alone.conf")" == "old-alone" ]]
    [[ "$(<"${realityConf}")" == "old-stream" ]]
    [[ "$(<"${realityState}")" == "old-state" ]]
    [[ "$(<"${nginxMainConf}")" == "${originalNginxMainConf}" ]]
    [[ "${singBoxState}" == "true" && "${xrayState}" == "true" && "${nginxState}" == "true" ]]
    grep -qx 'sing-box:start:true' "${serviceLog}"
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1

    mode=success
    singBoxState=true
    xrayState=true
    nginxState=true
    pgrep() { [[ "$*" == "-f nginx" ]] && printf '123\n'; }
    curl() {
        [[ "${!#}" == */checkPort ]] && printf 'fjkvymb6len' || printf '203.0.113.10'
    }
    checkIP() { return 0; }
    checkPortOpen 443 example.com >/dev/null 2>&1
    [[ ! -e "${root}/nginx/alone.conf" ]]
    [[ ! -e "${realityConf}" && ! -e "${realityState}" ]]
    ! grep -q 'padm stream include start' "${nginxMainConf}"
    [[ "${singBoxState}" == "false" && "${xrayState}" == "false" && "${nginxState}" == "true" ]] || return 1
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    if regressionFindHasMatches "${TMP_DIR}" -mindepth 1 -maxdepth 1 -name 'padm-check-port-open.*'; then
        return 1
    fi

    currentUUID=existing-user
    currentClients='[]'
    domain=tls.example.com
    currentHost=tls.example.com
    lastInstallationConfig=true
    selectCustomInstallType=",27,"
    singBoxVLESSVisionPort=10890

    initSingBoxClients() { printf '[]\n'; }
    readSingBoxPortResult() {
        local -n resultRef=$1
        resultRef=(10890)
        return 0
    }
    checkDNSIP() { return 1; }
    removeNginxDefaultConf() { return 0; }
    checkPortOpen() { return 0; }
    writeGeneratedJsonFile() {
        printf 'called\n' >"${writeProbe}"
        cat >/dev/null
    }
    setSniffRouting() { return 0; }

    set +e
    (
        set +e
        initSingBoxConfig custom 1 true >/dev/null 2>&1
        printf '%s\n' "$?" >"${templateRcFile}"
    )
    templateShellRc=$?
    set -e
    [[ "${templateShellRc}" == "0" ]]
    [[ "$(<"${templateRcFile}")" == "1" ]]
    [[ ! -e "${writeProbe}" ]]
)

runServiceQueueApplyPropagationRegression() (
    local root="${TMP_DIR}/service-queue-propagation"
    local rcFile="${root}/install.rc"
    local reachedFile="${root}/show-accounts"
    local serviceCallsFile="${root}/service-calls"
    local shellRc

    mkdir -p "${root}"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/core/services.sh"
    TMPDIR="${root}/tmp"
    mkdir -p "${TMPDIR}"
    [[ "$(xrayStartTestLog)" == "${TMPDIR}/padm-xray-start-test.log" ]]
    handleNginx() {
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceCallsFile}"
        return 1
    }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceCallsFile}"
        return 1
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceCallsFile}"
        return 1
    }
    errorCard() { :; }
    serviceRunning() { return 0; }
    SERVICE_ACTIONS=
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    serviceQueueStop nginx
    serviceQueueStop xray
    serviceQueueStop xray
    serviceQueueStop sing-box
    set +e
    serviceQueueApply >/dev/null 2>&1
    local queueRc=$?
    set -e
    [[ "${queueRc}" == "1" ]]
    grep -qx 'nginx:stop:true' "${serviceCallsFile}"
    grep -qx 'xray:stop:true' "${serviceCallsFile}"
    [[ "$(grep -c '^xray:stop:true$' "${serviceCallsFile}")" == "1" ]]
    grep -qx 'sing-box:stop:true' "${serviceCallsFile}"
    [[ -z "${SERVICE_ACTIONS}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    : >"${serviceCallsFile}"
    serviceQueueStart xray
    serviceQueueApply >/dev/null 2>&1
    [[ ! -s "${serviceCallsFile}" ]]
    serviceRunning() { return 1; }
    serviceQueueStop xray
    serviceQueueApply >/dev/null 2>&1
    [[ ! -s "${serviceCallsFile}" ]]

    serviceRunning() { return 0; }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceCallsFile}"
        [[ "$1" == "stop" ]] && return 1
        return 0
    }
    SERVICE_ACTIONS=
    serviceQueueRestart xray
    set +e
    serviceQueueApply >/dev/null 2>&1
    local restartRc=$?
    set -e
    [[ "${restartRc}" == "1" ]]
    grep -qx 'xray:stop:true' "${serviceCallsFile}"
    grep -qx 'xray:start:true' "${serviceCallsFile}"

    : >"${serviceCallsFile}"
    serviceRunning() { return 0; }
    serviceQueueAdd unknown start
    serviceQueueStop xray
    set +e
    serviceQueueApply >/dev/null 2>&1
    local unknownRc=$?
    set -e
    [[ "${unknownRc}" == "1" ]]
    grep -qx 'xray:stop:true' "${serviceCallsFile}"
    [[ -z "${SERVICE_ACTIONS}" ]]
    set +e
    runServiceAction nginx invalid >/dev/null 2>&1
    [[ "$?" == "1" ]]
    set -e

    readLastInstallationConfig() { return 0; }
    unInstallSubscribe() { return 0; }
    installTools() { return 0; }
    handleNginx() { return 0; }
    subscriptionWireGuardControlEnabled() { return 1; }
    refreshSubscriptionWireGuardNginxControl() { return 0; }
    installXray() { return 0; }
    installXrayService() { return 0; }
    initXrayConfig() { return 0; }
    cleanUp() { return 0; }
    serviceQueueRestart() { return 0; }
    serviceQueueApply() { return 1; }
    checkGFWStatue() {
        printf 'reached\n' >"${reachedFile}"
        return 0
    }
    showAccounts() {
        printf 'reached\n' >"${reachedFile}"
        return 0
    }

    set +e
    (
        set +e
        installXrayReality >/dev/null 2>&1
        printf '%s\n' "$?" >"${rcFile}"
    )
    shellRc=$?
    set -e
    [[ "${shellRc}" == "0" ]]
    [[ "$(<"${rcFile}")" == "1" ]]
    [[ ! -e "${reachedFile}" ]]
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
    set +e
    installXrayReality >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
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
    set +e
    customSingBoxInstall 26 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
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
    set +e
    customXrayInstall 21 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'path:4' "${callLog}"
    ! grep -q '^nginxBlog:' "${callLog}"
    ! grep -q '^installXray:' "${callLog}"

    resetInstallServiceFixture blog-fail
    set +e
    customXrayInstall 21 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'nginxBlog:6' "${callLog}"
    ! grep -q '^installXray:' "${callLog}"

    resetInstallServiceFixture cron-fail
    set +e
    customXrayInstall 21 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'cron:10' "${callLog}"
    ! grep -q '^queueApply$' "${callLog}"
    [[ ! -e "${reachedFile}" ]]

    resetInstallServiceFixture wg-refresh-fail
    set +e
    installXrayReality >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
    ! grep -q '^nginx:' "${serviceLog}"
    ! grep -q '^wg-refresh$' "${callLog}"
    grep -q '^installXray:' "${callLog}"
    [[ "${nginxRuntimeState}" == "true" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture xray-config-fail
    SERVICE_ACTIONS="existing:start"
    set +e
    installXrayReality >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
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
        set +e
        installXrayReality >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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
    set +e
    installXrayReality >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    ! grep -q '^nginx:' "${serviceLog}"
    [[ "${nginxRuntimeState}" == "true" ]] || return 1

    resetInstallServiceFixture nginx-start-fail
    set +e
    customXrayInstall 21 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:start:true' "${serviceLog}"
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    [[ "${nginxRuntimeState}" == "true" ]] || return 1
    ! grep -q '^installXray:' "${callLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture xray-service-fail
    btDomain=panel.example.com
    set +e
    customXrayInstall 21 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'customPort' "${callLog}"
    grep -qx 'ufw:2443:tcp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    resetInstallServiceFixture redirect-fail
    set +e
    customXrayInstall 21 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'redirect' "${callLog}"
    ! grep -q '^nginx:start:' "${serviceLog}"
    ! grep -q '^installXray:' "${callLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture no-local-cert
    set +e
    customXrayInstall 2 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
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
    set +e
    xrayCoreInstall >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}" || return 1
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    [[ "${nginxRuntimeState}" == "true" ]] || return 1
    grep -q '^installXray:' "${callLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture redirect-fail
    set +e
    xrayCoreInstall >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'redirect' "${callLog}"
    ! grep -q '^xray:stop:' "${serviceLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture nginx-stop-fail
    set +e
    singBoxInstall >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:stop:true' "${serviceLog}"
    ! grep -q '^installSingBox:' "${callLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture blog-fail
    set +e
    xrayCoreInstall >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'nginxBlog:10' "${callLog}"
    ! grep -q '^redirect$' "${callLog}"

    resetInstallServiceFixture cron-fail
    set +e
    singBoxInstall >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'cron:8' "${callLog}"
    grep -qx 'nginx:stop:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}" || return 1
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    [[ "${nginxRuntimeState}" == "true" ]] || return 1
    ! grep -q '^queueApply$' "${callLog}"
)

runSingBoxMergeStartFailureRegression() (
    local root="${TMP_DIR}/sing-box-merge-start-failure"
    local serviceFile="${root}/sing-box.service"
    local mergeMarker="${root}/merge"
    local systemctlMarker="${root}/systemctl"
    local queueRc

    mkdir -p "${root}"
    touch "${serviceFile}"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/core/services.sh"

    PADM_SINGBOX_SYSTEMD_SERVICE_FILE="${serviceFile}"
    SERVICE_ACTIONS=
    SERVICE_QUEUE_ALLOW_FAILURE=
    singBoxRunning() { return 1; }
    singBoxMergeConfig() {
        printf 'merge\n' >"${mergeMarker}"
        return 1
    }
    systemctl() {
        printf '%s\n' "$*" >"${systemctlMarker}"
        return 0
    }
    uiStyle() { shift; printf '%s\n' "$*"; }

    serviceQueueStart sing-box
    set +e
    serviceQueueApply >/dev/null 2>&1
    queueRc=$?
    set -e

    [[ "${queueRc}" == "1" ]]
    [[ -e "${mergeMarker}" ]]
    [[ ! -e "${systemctlMarker}" ]]
    [[ -z "${SERVICE_ACTIONS}" ]]
    [[ -z "${SERVICE_QUEUE_ALLOW_FAILURE}" ]]
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
    set +e
    singBoxMergeConfig >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${outputFile}")" == '{"old":true}' ]]
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null

    export PADM_FAKE_SINGBOX_MERGE_MODE=empty
    set +e
    singBoxMergeConfig >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
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
    set +e
    singBoxMergeConfigForValidation "${binary}" "${logFile}" check >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
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

runSingBoxUninstallRejectsUnsafeConfigPathRegression() (
    local root="${TMP_DIR}/sing-box-uninstall-unsafe-config"
    local configDir="${root}/unsafe-config/"
    local errorLog="${root}/error.log"
    local rmLog="${root}/rm.log"
    local rc

    mkdir -p "${root}/unsafe-config"
    printf '{}\n' >"${configDir}config.json"
    printf 'keep\n' >"${root}/unsafe-config/sentinel"
    : >"${errorLog}"
    : >"${rmLog}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"

    singBoxConfigPath="relative-config/"
    readInstallType() { return 0; }
    handleSingBox() { return 0; }
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    set +e
    unInstallSingBox >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -f "${root}/unsafe-config/sentinel" ]]
    [[ ! -s "${rmLog}" ]]
    grep -q '路径异常' "${errorLog}"
)

runSingBoxManagedCleanupRegression() (
    local root="${TMP_DIR}/sing-box-managed-cleanup"
    local serviceLog="${root}/service.log"
    local registrationLog="${root}/registration.log"
    local rmLog="${root}/rm.log"
    local cleanupLog="${root}/cleanup.log"

    mkdir -p "${root}"
    : >"${serviceLog}"
    : >"${registrationLog}"
    : >"${rmLog}"
    : >"${cleanupLog}"

    readInstallType() { return 0; }
    cleanCoreInstallDirectory() {
        printf 'clean-core:%s:%s\n' "$1" "$2" >>"${cleanupLog}"
        return 0
    }
    handleSingBox() {
        printf 'handle:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        return 0
    }
    coreStartupServiceEnabled() { return 0; }
    systemctl() {
        printf '%s\n' "$*" >>"${registrationLog}"
        return 0
    }
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        return 0
    }

    release=debian
    singBoxConfigPath=
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    unInstallSingBox >/dev/null 2>&1
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    grep -qx 'handle:stop:true' "${serviceLog}"
    grep -qx 'disable sing-box.service' "${registrationLog}"
    grep -qx 'daemon-reload' "${registrationLog}"
    grep -qx 'rm:-f -- /etc/systemd/system/sing-box.service' "${rmLog}"
    grep -qx 'clean-core:/etc/padm/sing-box:sing-box' "${cleanupLog}"

    : >"${serviceLog}"
    : >"${rmLog}"
    : >"${cleanupLog}"
    cleanDirectoryContent() {
        printf 'clean-dir:%s\n' "$1" >>"${cleanupLog}"
        return 0
    }

    SERVICE_QUEUE_ALLOW_FAILURE=previous
    cleanUp singBoxDel >/dev/null 2>&1
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    grep -qx 'handle:stop:true' "${serviceLog}"
    grep -qx 'rm:-f -- /etc/padm/sing-box/conf/config.json' "${rmLog}"
    grep -qx 'clean-dir:/etc/padm/sing-box/conf/config/' "${cleanupLog}"
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
        set +e
        singBoxHysteria2Install >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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

    set +e
    singBoxTuicInstall >/dev/null 2>&1
    tuicRc=$?
    set -e
    [[ "${tuicRc}" == "1" ]]
    grep -qx 'transaction:sing-box' "${callLog}"
    grep -qx 'config:custom 2 true' "${callLog}"
    grep -qx 'restart:sing-box' "${callLog}"
    grep -qx 'apply' "${callLog}"
    ! grep -qx 'reload' "${callLog}"
    ! grep -qx 'restart:xray' "${callLog}"
    [[ ! -e "${reachedFile}" ]]

    : >"${callLog}"
    rm -f "${reachedFile}"
    set +e
    singBoxHysteria2Install >/dev/null 2>&1
    hysteriaRc=$?
    set -e
    [[ "${hysteriaRc}" == "1" ]]
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
        set +e
        coreInstallConfigTransaction sing-box failingInstall >/dev/null 2>&1
        transactionRc=$?
        set -e
        [[ "${transactionRc}" == "7" ]]
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
    set +e
    updateGeoSite >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'geo:/etc/padm/xray force' "${callLog}"
    ! grep -q '^reload$' "${callLog}"

    mode=reload-fail
    : >"${callLog}"
    printf 'old-version\n' >"${geoVersionFile}"
    set +e
    updateGeoSite >/dev/null 2>&1
    rc=$?
    set -e

    [[ "${rc}" == "1" ]]
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

runXrayGeoCommitRollbackRegression() (
    local root="${TMP_DIR}/xray-geo-commit-rollback"
    local stageDir="${root}/stage"
    local targetDir="${root}/target"
    local rc
    local preservedBackupDir=

    mkdir -p "${stageDir}" "${targetDir}"
    printf 'old-geosite\n' >"${targetDir}/geosite.dat"
    printf 'old-geoip\n' >"${targetDir}/geoip.dat"
    printf 'old-version\n' >"${targetDir}/geo.version"
    printf 'new-geosite\n' >"${stageDir}/geosite.dat"
    printf 'new-geoip\n' >"${stageDir}/geoip.dat"

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        local targetFile=$2
        [[ "${targetFile}" == "${targetDir}/geoip.dat" ]] && return 1
        originalCommitGeneratedFile "$@"
    }
    padmForgetCleanupPath() {
        [[ "$1" == *padm-xray-geo-backup.* ]] && preservedBackupDir=$1
    }

    set +e
    commitXrayGeoFilesFromStage "${stageDir}" "${targetDir}" v-new
    rc=$?
    set -e

    [[ "${rc}" == "1" ]]
    [[ "$(<"${targetDir}/geosite.dat")" == "old-geosite" ]]
    [[ "$(<"${targetDir}/geoip.dat")" == "old-geoip" ]]
    [[ "$(<"${targetDir}/geo.version")" == "old-version" ]]
    [[ -n "${preservedBackupDir}" && -d "${preservedBackupDir}" ]]
    rm -rf -- "${preservedBackupDir}"
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
    set +e
    cleanUp xrayDel >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
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

    set +e
    installSingBoxReality >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
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

        set +e
        coreSwitchConfigTransaction sing-box failingSwitch >/dev/null 2>&1
        switchRc=$?
        set -e
        [[ "${switchRc}" == "7" ]]
        [[ "$(<"${oldCoreDir}/state")" == "old-core" ]]
        [[ "$(<"${switchLog}")" == $'config-restore\nxray:start:restored' ]]
    )
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
    set +e
    applyTraditionalTlsAlpn '["h2","http/1.1"]' >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
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
        set +e
        applyTraditionalTlsAlpn '["h2","http/1.1"]' >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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
    set +e
    setVlessRealityEncryption enable >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
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
        set +e
        setVlessRealityEncryption enable >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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
        set +e
        setVlessRealityEncryption enable >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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
        set +e
        setVlessRealityEncryption enable >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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
    set +e
    setVlessRealityEncryption enable >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
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
    set +e
    refreshVlessEncryptionSubscriptions >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]

    subscribePort=
    readNginxSubscribe() {
        subscribePort=
        nginxConfigPath="${root}/nginx/"
    }
    showAccounts() { return 1; }
    set +e
    refreshVlessEncryptionSubscriptions >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]

    initXrayConfig() { return 0; }
    reloadCore() { return 1; }
    subscribe() {
        printf 'subscribe\n' >"${subscribeMarker}"
        return 0
    }
    rm -f "${subscribeMarker}"
    set +e
    regenerateRealityProfile >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -e "${subscribeMarker}" ]]

    reloadCore() { return 0; }
    subscribe() {
        printf 'subscribe\n' >"${subscribeMarker}"
        return 1
    }
    rm -f "${subscribeMarker}"
    set +e
    regenerateRealityProfile >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
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
        set +e
        refreshVlessEncryptionSubscriptions >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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
        set +e
        checkLog >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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
        set +e
        checkLog >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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
        set +e
        initTLSNginxConfig 1 >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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
        set +e
        customPortFunction >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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
        set +e
        customPortFunction >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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
        set +e
        customPortFunction >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ ! -e "${checkPortMarker}" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    )

    PATH="${oldPath}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    eval "${protocolSelectionIncludesDef}"
    unset PADM_FAKE_NGINX_VALIDATE_MODE
}

runCheckPortOpenNginxRejectsDirectoryTargetRegression() {
    (
        set -euo pipefail
        local rootRel="${TMP_DIR}/check-port-nginx-directory-target"
        local root
        local oldPath="${PATH}"
        local targetPath
        mkdir -p "${TMP_DIR}/fake-bin" "${rootRel}/nginx/checkPortOpen.conf"
        root=$(cd -- "${rootRel}" && pwd -P)
        targetPath="${root}/nginx/checkPortOpen.conf"
        nginxConfigPath="${root}/nginx/"
        cat >"${TMP_DIR}/fake-bin/nginx" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "-t" ]]
exit 0
SH
        chmod +x "${TMP_DIR}/fake-bin/nginx"
        PATH="${TMP_DIR}/fake-bin:${PATH}"
        CHECK_PORT_OPEN_NGINX_CONFIG_ERROR=

        if writeCheckPortOpenNginxConfig 443 example.com '' >/dev/null 2>&1; then
            return 1
        fi
        [[ -d "${targetPath}" ]]
        [[ ! -e "${targetPath}/checkPortOpen.conf.tmp" ]]
        [[ "${CHECK_PORT_OPEN_NGINX_CONFIG_ERROR}" == "端口检测 Nginx 配置目标异常，请手动检查 ${targetPath}" ]]

        PATH="${oldPath}"
    )
}

runAloneNginxRejectsDirectoryTargetRegression() {
    (
        set -euo pipefail
        local rootRel="${TMP_DIR}/nginx-alone-directory-target"
        local root
        local oldPath="${PATH}"
        local targetPath errorLog
        mkdir -p "${TMP_DIR}/fake-bin" "${rootRel}/nginx/alone.conf" "${TMP_DIR}/static"
        root=$(cd -- "${rootRel}" && pwd -P)
        targetPath="${root}/nginx/alone.conf"
        errorLog="${root}/error.log"
        nginxConfigPath="${root}/nginx/"
        cat >"${TMP_DIR}/fake-bin/nginx" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-v" ]]; then
    printf 'nginx version: nginx/1.24.0\n' >&2
    exit 0
fi
[[ "$1" == "-t" ]]
exit 0
SH
        chmod +x "${TMP_DIR}/fake-bin/nginx"
        PATH="${TMP_DIR}/fake-bin:${PATH}"
        domain=example.com
        port=443
        currentPath=padm
        nginxStaticPath="${TMP_DIR}/static"
        selectCustomInstallType=9
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }

        if updateRedirectNginxConf >/dev/null 2>&1; then
            return 1
        fi
        [[ -d "${targetPath}" ]]
        [[ ! -e "${targetPath}/alone.conf.tmp" ]]
        grep -qx "Nginx 配置目标异常，请手动检查 ${targetPath}" "${errorLog}"

        PATH="${oldPath}"
    )
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

    set +e
    initRealityKey >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
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
    set +e
    initRealityKey >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${keyFile}")" == "publicKey:public-generated" ]]

    cat >"${singBoxBinary}" <<'EOF'
#!/usr/bin/env bash
printf 'PrivateKey private-only\n'
EOF
    chmod +x "${singBoxBinary}"
    realityPrivateKey=
    realityPublicKey=
    set +e
    initRealityKey >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
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
