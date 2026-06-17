#!/usr/bin/env bash

fail2banManagedJailFile() {
    echo "${PADM_FAIL2BAN_JAIL_FILE:-/etc/fail2ban/jail.d/padm.local}"
}

fail2banManagedFilterFile() {
    echo "${PADM_FAIL2BAN_FILTER_FILE:-/etc/fail2ban/filter.d/padm-control.conf}"
}

fail2banManagedNginxScanFilterFile() {
    echo "${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE:-/etc/fail2ban/filter.d/padm-nginx-scan-basic.conf}"
}

fail2banPadmControlLogFile() {
    echo "${PADM_FAIL2BAN_CONTROL_LOG_FILE:-/var/log/nginx/padm-control-access.log}"
}

fail2banNginxAccessLogFile() {
    local override=${PADM_FAIL2BAN_NGINX_ACCESS_LOG_FILE:-}
    if [[ -n "${override}" ]]; then
        printf '%s\n' "${override}"
        return 0
    fi
    if declare -F resolveSubscribeNginxAccessLogFile >/dev/null 2>&1; then
        resolveSubscribeNginxAccessLogFile
        return $?
    fi
    fail2banGuessNginxAccessLogFile
}

fail2banValidateLog() {
    if declare -F padmTmpFilePath >/dev/null 2>&1; then
        padmTmpFilePath padm-fail2ban-validate.log
    else
        local tmpBase="${TMPDIR:-/tmp}"
        printf '%s\n' "${tmpBase%/}/padm-fail2ban-validate.log"
    fi
}

fail2banReloadServiceIfRunning() {
    if ! fail2banServiceActive; then
        return 0
    fi
    if command -v systemctl >/dev/null 2>&1 && fail2banSystemdServiceInstalled; then
        systemctl restart fail2ban.service >/dev/null 2>&1
        return $?
    fi
    if command -v rc-service >/dev/null 2>&1 && fail2banOpenRcServiceInstalled; then
        rc-service fail2ban restart >/dev/null 2>&1
        return $?
    fi
    return 0
}

fail2banInstalled() {
    command -v fail2ban-client >/dev/null 2>&1
}

fail2banSystemdServiceInstalled() {
    [[ -e /etc/systemd/system/fail2ban.service || -e /usr/lib/systemd/system/fail2ban.service || -e /lib/systemd/system/fail2ban.service ]]
}

fail2banOpenRcServiceInstalled() {
    [[ -x /etc/init.d/fail2ban ]]
}

fail2banServiceActive() {
    if command -v systemctl >/dev/null 2>&1 && fail2banSystemdServiceInstalled; then
        systemctl is-active --quiet fail2ban.service
        return $?
    fi
    if command -v rc-service >/dev/null 2>&1 && fail2banOpenRcServiceInstalled; then
        rc-service fail2ban status >/dev/null 2>&1
        return $?
    fi
    fail2banInstalled && fail2ban-client ping >/dev/null 2>&1
}

fail2banServiceEnabled() {
    if command -v systemctl >/dev/null 2>&1 && fail2banSystemdServiceInstalled; then
        systemctl is-enabled --quiet fail2ban.service
        return $?
    fi
    if command -v rc-update >/dev/null 2>&1 && fail2banOpenRcServiceInstalled; then
        rc-update show default 2>/dev/null | awk '{print $1}' | grep -qx 'fail2ban'
        return $?
    fi
    return 1
}

fail2banRole() {
    local role=
    if declare -F subscriptionWireGuardRole >/dev/null 2>&1; then
        role=$(subscriptionWireGuardRole 2>/dev/null || true)
    fi
    case "${role}" in
    main | controlled) printf '%s\n' "${role}" ;;
    *) printf 'uninitialized\n' ;;
    esac
}

fail2banRoleText() {
    case "$(fail2banRole)" in
    main) printf '主控' ;;
    controlled) printf '被控' ;;
    *) printf '未初始化' ;;
    esac
}

fail2banControlSurfaceEnabled() {
    if declare -F subscriptionWireGuardControlEnabled >/dev/null 2>&1 && subscriptionWireGuardControlEnabled 2>/dev/null; then
        return 0
    fi
    if declare -F subscriptionWireGuardNginxConfigFile >/dev/null 2>&1; then
        [[ -f "$(subscriptionWireGuardNginxConfigFile)" ]]
        return $?
    fi
    return 1
}

fail2banControlSurfaceText() {
    if fail2banControlSurfaceEnabled; then
        printf '已检测到 /s/control/'
    else
        printf '未检测到 /s/control/'
    fi
}

fail2banRecommendedProfileName() {
    if fail2banControlSurfaceEnabled; then
        printf 'sshd+control\n'
    else
        printf 'sshd\n'
    fi
}

fail2banProfileLabel() {
    case "$1" in
    sshd) printf '仅 SSH 防护' ;;
    sshd+control) printf 'SSH + 控制面防护' ;;
    disabled) printf '未启用' ;;
    custom) printf '自定义/异常状态' ;;
    *) printf '%s' "$1" ;;
    esac
}

fail2banPadmControlPort() {
    local port=
    if declare -F subscriptionWireGuardReadState >/dev/null 2>&1; then
        port=$(subscriptionWireGuardReadState | jq -r '.control_port // empty' 2>/dev/null || true)
    fi
    if [[ -z "${port}" || "${port}" == "null" ]]; then
        if declare -F subscriptionWireGuardDefaultControlPort >/dev/null 2>&1; then
            port=$(subscriptionWireGuardDefaultControlPort)
        else
            port=39778
        fi
    fi
    printf '%s\n' "${port}"
}

fail2banGuessNginxAccessLogFile() {
    local candidate
    for candidate in \
        /var/log/nginx/access.log \
        /www/wwwlogs/access.log \
        /www/wwwlogs/*.log \
        /opt/1panel/apps/openresty/openresty/logs/access.log \
        /var/log/openresty/access.log; do
        if [[ "${candidate}" == *'*'* ]]; then
            for candidate in ${candidate}; do
                [[ -e "${candidate}" ]] || continue
                printf '%s\n' "${candidate}"
                return 0
            done
        elif [[ -e "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    printf '/var/log/nginx/access.log\n'
}

fail2banManagedJailHasSection() {
    local jailName=$1
    local jailFile
    jailFile=$(fail2banManagedJailFile)
    [[ -f "${jailFile}" ]] || return 1
    grep -Eq "^\\[${jailName//./\\.}\\]$" "${jailFile}"
}

fail2banCurrentJailEnabled() {
    local jailName=$1
    local jailFile
    jailFile=$(fail2banManagedJailFile)
    [[ -f "${jailFile}" ]] || return 1
    awk -v target="${jailName}" '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        /^\[/ {
            section=$0
            gsub(/^\[/, "", section)
            gsub(/\]$/, "", section)
            next
        }
        /^[[:space:]]*enabled[[:space:]]*=/ {
            split($0, parts, "=")
            value=tolower(trim(parts[2]))
            if (section == target && value == "true") {
                found=1
            }
        }
        END { exit found ? 0 : 1 }
    ' "${jailFile}"
}

fail2banCurrentEnabledJailsCsv() {
    local jailFile
    jailFile=$(fail2banManagedJailFile)
    [[ -f "${jailFile}" ]] || return 0
    awk '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        /^\[/ {
            section=$0
            gsub(/^\[/, "", section)
            gsub(/\]$/, "", section)
            next
        }
        /^[[:space:]]*enabled[[:space:]]*=/ {
            split($0, parts, "=")
            value=tolower(trim(parts[2]))
            if (section != "" && value == "true") {
                enabled[section]=1
            }
        }
        END {
            sep=""
            if (enabled["sshd"]) {
                printf "%ssshd", sep
                sep=","
            }
            if (enabled["padm-control"]) {
                printf "%spadm-control", sep
                sep=","
            }
            if (enabled["nginx-scan-basic"]) {
                printf "%snginx-scan-basic", sep
            }
        }
    ' "${jailFile}"
}

fail2banCurrentProfileName() {
    local sshdEnabled=false
    local controlEnabled=false
    if fail2banCurrentJailEnabled sshd; then
        sshdEnabled=true
    fi
    if fail2banCurrentJailEnabled padm-control; then
        controlEnabled=true
    fi
    case "${sshdEnabled}:${controlEnabled}" in
    false:false)
        printf 'disabled\n'
        ;;
    true:false)
        printf 'sshd\n'
        ;;
    true:true)
        printf 'sshd+control\n'
        ;;
    *)
        printf 'custom\n'
        ;;
    esac
}

fail2banCurrentProfileLabel() {
    fail2banProfileLabel "$(fail2banCurrentProfileName)"
}

fail2banCurrentNginxScanEnabled() {
    fail2banManagedJailHasSection nginx-scan-basic || return 1
    fail2banCurrentJailEnabled nginx-scan-basic
}

fail2banNginxScanStatusText() {
    if fail2banCurrentNginxScanEnabled; then
        printf '已启用'
    else
        printf '默认关闭'
    fi
}

fail2banServiceStateText() {
    if fail2banServiceActive; then
        printf '运行中'
    elif fail2banInstalled; then
        printf '已安装，未运行'
    else
        printf '未安装'
    fi
}

fail2banEnsurePadmControlLogPath() {
    local logFile logDir
    logFile=$(fail2banPadmControlLogFile)
    logDir=$(dirname -- "${logFile}")
    mkdir -p "${logDir}" || return 1
    touch "${logFile}" || return 1
    chmod 644 "${logFile}" 2>/dev/null || true
}

fail2banEnsureNginxAccessLogPath() {
    local logFile logDir
    logFile=$(fail2banNginxAccessLogFile)
    logDir=$(dirname -- "${logFile}")
    mkdir -p "${logDir}" || return 1
    touch "${logFile}" || return 1
    chmod 644 "${logFile}" 2>/dev/null || true
}

fail2banWriteManagedFilter() {
    local filterFile tmpFile
    filterFile=$(fail2banManagedFilterFile)
    padmCreateTempFileForTarget tmpFile "${filterFile}" fail2ban || return 1
    cat >"${tmpFile}" <<'EOF' || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
[Definition]
failregex = ^<HOST> - .* "(GET|POST|HEAD) /s/control/[^ ]* HTTP/[^"]*" 401
ignoreregex =
EOF
    commitGeneratedFile "${tmpFile}" "${filterFile}" 644 || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

fail2banWriteNginxScanFilter() {
    local filterFile tmpFile
    filterFile=$(fail2banManagedNginxScanFilterFile)
    padmCreateTempFileForTarget tmpFile "${filterFile}" fail2ban || return 1
    cat >"${tmpFile}" <<'EOF' || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
[Definition]
failregex = ^<HOST> - .* "(GET|POST|HEAD) /(\.env(?:\.[^ ?"]*)?|\.git(?:/[^"]*|[^"]*)?|wp-login\.php(?:[? ][^"]*)?|wp-admin(?:/[^"]*|[^"]*)?|phpmyadmin(?:/[^"]*|[^"]*)?|cgi-bin(?:/[^"]*|[^"]*)?|manager/html(?:[? ][^"]*)?|actuator(?:/[^"]*|[^"]*)?|boaform(?:/[^"]*|[^"]*)?) HTTP/[^"]*" (40[34]|444)\b
ignoreregex =
EOF
    commitGeneratedFile "${tmpFile}" "${filterFile}" 644 || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

fail2banWriteManagedJail() {
    local profile=$1
    local nginxScanEnabled=${2:-}
    local jailFile tmpFile controlLog controlPort nginxAccessLog
    local sshdEnabled=false
    local controlEnabled=false

    if [[ -z "${nginxScanEnabled}" ]]; then
        if fail2banCurrentNginxScanEnabled; then
            nginxScanEnabled=true
        else
            nginxScanEnabled=false
        fi
    fi
    case "${nginxScanEnabled}" in
    true | false) ;;
    *)
        return 1
        ;;
    esac
    case "${profile}" in
    sshd)
        sshdEnabled=true
        ;;
    sshd+control)
        sshdEnabled=true
        controlEnabled=true
        ;;
    disabled)
        ;;
    *)
        return 1
        ;;
    esac

    jailFile=$(fail2banManagedJailFile)
    controlLog=$(fail2banPadmControlLogFile)
    controlPort=$(fail2banPadmControlPort)
    nginxAccessLog=$(fail2banNginxAccessLogFile)
    padmCreateTempFileForTarget tmpFile "${jailFile}" fail2ban || return 1
    cat >"${tmpFile}" <<EOF || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
# Managed by padm. Edit via 系统与脚本 -> Fail2ban 防护.
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 6

[sshd]
enabled = ${sshdEnabled}
backend = auto
port = ssh

[padm-control]
enabled = ${controlEnabled}
backend = auto
filter = padm-control
port = ${controlPort}
logpath = ${controlLog}
maxretry = 6
findtime = 10m
bantime = 1h

[nginx-scan-basic]
enabled = ${nginxScanEnabled}
backend = auto
filter = padm-nginx-scan-basic
logpath = ${nginxAccessLog}
maxretry = 6
findtime = 10m
bantime = 1h
EOF
    commitGeneratedFile "${tmpFile}" "${jailFile}" 644 || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

fail2banValidateManagedConfig() {
    local validateLog
    fail2banInstalled || return 0
    validateLog=$(fail2banValidateLog)
    fail2ban-client -t >"${validateLog}" 2>&1
}

fail2banRemoveManagedFiles() {
    local status=0
    removeManagedFilesIfPresent \
        "$(fail2banManagedJailFile)" \
        "$(fail2banManagedFilterFile)" \
        "$(fail2banManagedNginxScanFilterFile)" \
        "$(fail2banPadmControlLogFile)" || status=1
    return "${status}"
}

fail2banInstallPackageIfNeeded() {
    fail2banInstalled && return 0
    installOptionalPackageTracked "fail2ban" fail2ban || return 1
    fail2banInstalled
}

fail2banStartOrReloadService() {
    if command -v systemctl >/dev/null 2>&1 && fail2banSystemdServiceInstalled; then
        if fail2banServiceActive; then
            systemctl restart fail2ban.service >/dev/null 2>&1
        else
            systemctl enable --now fail2ban.service >/dev/null 2>&1
        fi
        return $?
    fi
    if command -v rc-service >/dev/null 2>&1 && fail2banOpenRcServiceInstalled; then
        if command -v rc-update >/dev/null 2>&1; then
            rc-update add fail2ban default >/dev/null 2>&1 || true
        fi
        if fail2banServiceActive; then
            rc-service fail2ban restart >/dev/null 2>&1
        else
            rc-service fail2ban start >/dev/null 2>&1
        fi
        return $?
    fi
    return 1
}

fail2banRestoreManagedFiles() {
    local backupDir=$1
    local serviceWasActive=${2:-false}
    local serviceWasEnabled=${3:-false}
    local rollbackFailed=false

    checkLogBackupRestore "${backupDir}" || rollbackFailed=true
    if command -v systemctl >/dev/null 2>&1 && fail2banSystemdServiceInstalled; then
        if [[ "${serviceWasActive}" == "true" ]]; then
            systemctl restart fail2ban.service >/dev/null 2>&1 || rollbackFailed=true
        elif fail2banServiceActive; then
            systemctl stop fail2ban.service >/dev/null 2>&1 || rollbackFailed=true
        fi
        if [[ "${serviceWasEnabled}" == "true" ]]; then
            systemctl enable fail2ban.service >/dev/null 2>&1 || rollbackFailed=true
        else
            systemctl disable fail2ban.service >/dev/null 2>&1 || true
        fi
    elif command -v rc-service >/dev/null 2>&1 && fail2banOpenRcServiceInstalled; then
        if [[ "${serviceWasActive}" == "true" ]]; then
            rc-service fail2ban restart >/dev/null 2>&1 || rollbackFailed=true
        elif fail2banServiceActive; then
            rc-service fail2ban stop >/dev/null 2>&1 || rollbackFailed=true
        fi
        if command -v rc-update >/dev/null 2>&1; then
            if [[ "${serviceWasEnabled}" == "true" ]]; then
                rc-update add fail2ban default >/dev/null 2>&1 || rollbackFailed=true
            else
                rc-update del fail2ban default >/dev/null 2>&1 || true
            fi
        fi
    fi
    [[ "${rollbackFailed}" != "true" ]]
}

fail2banEnsurePadmControlNginxLogging() {
    if ! fail2banControlSurfaceEnabled; then
        return 0
    fi
    fail2banEnsurePadmControlLogPath || return 1
    if declare -F refreshSubscriptionWireGuardNginxControl >/dev/null 2>&1; then
        refreshSubscriptionWireGuardNginxControl || return 1
        if declare -F serviceQueueApply >/dev/null 2>&1; then
            serviceQueueApply || return 1
        fi
    fi
}

fail2banApplyProfile() {
    local profile=$1
    local nginxScanEnabled=${2:-}
    local backupDir=
    local serviceWasActive=false
    local serviceWasEnabled=false
    local validateLog

    case "${profile}" in
    sshd | sshd+control | disabled) ;;
    *)
        errorCard "Fail2ban 防护配置无效"
        return 1
        ;;
    esac
    if [[ -z "${nginxScanEnabled}" ]]; then
        if fail2banCurrentNginxScanEnabled; then
            nginxScanEnabled=true
        else
            nginxScanEnabled=false
        fi
    fi
    case "${nginxScanEnabled}" in
    true | false) ;;
    *)
        errorCard "Fail2ban 站点扫描扩展开关无效"
        return 1
        ;;
    esac

    if fail2banServiceActive; then
        serviceWasActive=true
    fi
    if fail2banServiceEnabled; then
        serviceWasEnabled=true
    fi

    if [[ "${profile}" == "disabled" ]]; then
        local disabledBackupDir=
        if ! checkLogBackupCreate disabledBackupDir "$(fail2banManagedJailFile)" "$(fail2banManagedFilterFile)" "$(fail2banManagedNginxScanFilterFile)"; then
            errorCard "Fail2ban 防护停用前备份失败"
            return 1
        fi
        if ! fail2banRemoveManagedFiles; then
            if fail2banRestoreManagedFiles "${disabledBackupDir}" "${serviceWasActive}" "${serviceWasEnabled}"; then
                padmRemoveCleanupPath "${disabledBackupDir}"
                errorCard "Fail2ban 防护停用失败，已恢复旧配置"
            else
                padmForgetCleanupPath "${disabledBackupDir}"
                errorCard "Fail2ban 防护停用失败，且旧配置恢复失败"
            fi
            return 1
        fi
        if ! fail2banReloadServiceIfRunning; then
            if fail2banRestoreManagedFiles "${disabledBackupDir}" "${serviceWasActive}" "${serviceWasEnabled}"; then
                padmRemoveCleanupPath "${disabledBackupDir}"
                errorCard "Fail2ban 防护停用后服务重载失败，已恢复旧配置"
            else
                padmForgetCleanupPath "${disabledBackupDir}"
                errorCard "Fail2ban 防护停用后服务重载失败，且旧配置恢复失败"
            fi
            return 1
        fi
        padmRemoveCleanupPath "${disabledBackupDir}"
        successCard "Fail2ban 防护已停用" "padm 管理的 jail 已移除"
        return 0
    fi

    if ! fail2banInstallPackageIfNeeded; then
        errorCard "Fail2ban 安装失败"
        return 1
    fi

    if [[ "${profile}" == "sshd+control" ]]; then
        if ! fail2banControlSurfaceEnabled; then
            errorCard "当前未检测到可保护的 /s/control/ 控制面" "请先完成主控/被控控制面初始化，或改用 只启用 SSH 防护"
            return 1
        fi
        if ! fail2banEnsurePadmControlNginxLogging; then
            errorCard "控制面日志接入失败" "未能为 /s/control/ 配置专用 Nginx 访问日志"
            return 1
        fi
    fi
    if [[ "${nginxScanEnabled}" == "true" ]]; then
        if ! fail2banEnsureNginxAccessLogPath; then
            errorCard "站点扫描扩展日志接入失败" "未能准备 Nginx 访问日志：$(fail2banNginxAccessLogFile)"
            return 1
        fi
    fi

    checkLogBackupCreate backupDir "$(fail2banManagedJailFile)" "$(fail2banManagedFilterFile)" "$(fail2banManagedNginxScanFilterFile)" || {
        errorCard "Fail2ban 配置备份失败"
        return 1
    }

    fail2banWriteManagedFilter || {
        if fail2banRestoreManagedFiles "${backupDir}" "${serviceWasActive}" "${serviceWasEnabled}"; then
            padmRemoveCleanupPath "${backupDir}"
        else
            padmForgetCleanupPath "${backupDir}"
        fi
        errorCard "Fail2ban 过滤器写入失败"
        return 1
    }
    fail2banWriteNginxScanFilter || {
        if fail2banRestoreManagedFiles "${backupDir}" "${serviceWasActive}" "${serviceWasEnabled}"; then
            padmRemoveCleanupPath "${backupDir}"
        else
            padmForgetCleanupPath "${backupDir}"
        fi
        errorCard "Fail2ban 站点扫描过滤器写入失败"
        return 1
    }
    fail2banWriteManagedJail "${profile}" "${nginxScanEnabled}" || {
        if fail2banRestoreManagedFiles "${backupDir}" "${serviceWasActive}" "${serviceWasEnabled}"; then
            padmRemoveCleanupPath "${backupDir}"
        else
            padmForgetCleanupPath "${backupDir}"
        fi
        errorCard "Fail2ban jail 写入失败"
        return 1
    }
    if ! fail2banValidateManagedConfig; then
        validateLog=$(fail2banValidateLog)
        if fail2banRestoreManagedFiles "${backupDir}" "${serviceWasActive}" "${serviceWasEnabled}"; then
            padmRemoveCleanupPath "${backupDir}"
            errorCard "Fail2ban 配置校验失败，已恢复旧配置" "校验日志：${validateLog}"
        else
            padmForgetCleanupPath "${backupDir}"
            errorCard "Fail2ban 配置校验失败，且旧配置恢复失败" "校验日志：${validateLog}"
        fi
        return 1
    fi
    if ! fail2banStartOrReloadService; then
        if fail2banRestoreManagedFiles "${backupDir}" "${serviceWasActive}" "${serviceWasEnabled}"; then
            padmRemoveCleanupPath "${backupDir}"
            errorCard "Fail2ban 服务应用失败，已恢复旧配置"
        else
            padmForgetCleanupPath "${backupDir}"
            errorCard "Fail2ban 服务应用失败，且旧配置恢复失败"
        fi
        return 1
    fi
    padmRemoveCleanupPath "${backupDir}"
    successCard "Fail2ban 防护已更新" "当前策略：$(fail2banProfileLabel "${profile}")；站点扫描扩展：$(fail2banNginxScanStatusText)"
}

fail2banApplyNginxScanExtension() {
    local action=$1
    local currentProfile
    local targetProfile
    local profileBefore
    local scanWasEnabled=false
    case "${action}" in
    enable | disable) ;;
    *)
        errorCard "Fail2ban 站点扫描扩展操作无效"
        return 1
        ;;
    esac

    profileBefore=$(fail2banCurrentProfileName)
    if fail2banCurrentNginxScanEnabled; then
        scanWasEnabled=true
    fi
    currentProfile="${profileBefore}"
    case "${currentProfile}" in
    sshd | sshd+control)
        targetProfile="${currentProfile}"
        ;;
    disabled)
        if [[ "${action}" == "disable" ]]; then
            if ! fail2banManagedJailHasSection nginx-scan-basic && ! ${scanWasEnabled}; then
                successCard "站点扫描扩展已关闭" "当前未接入站点扫描扩展"
                return 0
            fi
            targetProfile=$(fail2banRecommendedProfileName)
        else
            targetProfile=$(fail2banRecommendedProfileName)
        fi
        ;;
    *)
        errorCard "当前 Fail2ban 基线策略异常" "请先重新应用 padm 管理的防护策略，再调整站点扫描扩展"
        return 1
        ;;
    esac

    if [[ "${action}" == "enable" ]]; then
        fail2banApplyProfile "${targetProfile}" true
    else
        fail2banApplyProfile "${targetProfile}" false
    fi
}

showFail2banStatusSummary() {
    statusCard "Fail2ban 防护状态" \
        "服务器角色：$(fail2banRoleText)" \
        "控制面：$(fail2banControlSurfaceText)" \
        "推荐策略：$(fail2banProfileLabel "$(fail2banRecommendedProfileName)")" \
        "当前策略：$(fail2banCurrentProfileLabel)" \
        "站点扫描扩展：$(fail2banNginxScanStatusText)" \
        "服务状态：$(fail2banServiceStateText)"
}

showFail2banRuntimeStatus() {
    local enabledCsv jail
    showFail2banStatusSummary
    if ! fail2banInstalled; then
        menuLine "当前未安装 fail2ban；启用推荐防护时会自动安装。"
        return 0
    fi
    enabledCsv=$(fail2banCurrentEnabledJailsCsv)
    if [[ -z "${enabledCsv}" ]]; then
        menuLine "当前没有启用 padm 管理的 jail。"
    else
        menuLine "当前启用 jail：${enabledCsv}"
    fi
    if fail2banControlSurfaceEnabled; then
        menuLine "控制面日志：$(fail2banPadmControlLogFile)"
    fi
    if fail2banCurrentNginxScanEnabled; then
        menuLine "站点扫描日志：$(fail2banNginxAccessLogFile)"
    else
        menuLine "站点扫描扩展默认关闭；仅在站点探测较多时建议开启。"
    fi
    if fail2banServiceActive && command -v fail2ban-client >/dev/null 2>&1; then
        menuLine "fail2ban-client status："
        while IFS= read -r jail; do
            [[ -n "${jail}" ]] || continue
            menuLine "${jail}"
        done < <(fail2ban-client status 2>/dev/null)
    fi
}

showFail2banBans() {
    local jailName
    if ! fail2banInstalled; then
        errorCard "当前未安装 fail2ban"
        return 1
    fi
    if ! fail2banServiceActive; then
        errorCard "fail2ban 当前未运行"
        return 1
    fi
    menuLine "全局状态："
    while IFS= read -r jailName; do
        [[ -n "${jailName}" ]] || continue
        menuLine "${jailName}"
    done < <(fail2ban-client status 2>/dev/null)
    for jailName in sshd padm-control nginx-scan-basic; do
        if grep -Eq "(^|,)${jailName}(,|$)" <<<"$(fail2banCurrentEnabledJailsCsv)"; then
            menuLine ""
            menuLine "Jail ${jailName}："
            while IFS= read -r jailName; do
                [[ -n "${jailName}" ]] || continue
                menuLine "${jailName}"
            done < <(fail2ban-client status "${jailName}" 2>/dev/null)
        fi
    done
}

manageFail2ban() {
    echoContent title "\n┌─ Fail2ban 防护 ────────────────────────────────────"
    menuLine "这里只管理 padm 当前用到的 SSH、/s/control/ 与站点扫描扩展防护，不扩展成通用安全平台。"
    menuLine "推荐策略会按本机角色和控制面启用状态自动判断。站点扫描扩展默认关闭，只在站点探测较多时建议开启。"
    menuLine "当前角色：$(uiStyle value "$(fail2banRoleText)")；控制面：$(uiStyle value "$(fail2banControlSurfaceText)")；当前策略：$(uiStyle value "$(fail2banCurrentProfileLabel)")；站点扫描扩展：$(uiStyle value "$(fail2banNginxScanStatusText)")"
    menuItem 1 "查看当前防护状态" "查看角色、推荐策略、当前 jail 和服务状态"
    menuItem 2 "启用推荐防护" "自动选择 仅 SSH 或 SSH + 控制面 防护"
    menuItem 3 "只启用 SSH 防护" "适合未启用主控/被控控制面，或先做最小接入"
    menuItem 4 "启用 SSH + 控制面防护" "同时保护 SSH 和 WireGuard 内网 /s/control/ 端点"
    menuItem 5 "启用站点扫描扩展防护" "默认关闭；仅在公开站点遭遇明显探测时再开启"
    menuItem 6 "关闭站点扫描扩展防护" "恢复为纯基线防护，不影响 SSH / 控制面基线策略"
    menuItem 7 "查看当前封禁" "查看 fail2ban 当前 jail 与被封禁 IP"
    menuDangerItem 8 "停用 padm 管理的防护" "保留 fail2ban 软件包，只关闭 padm 管理的 jail"
    menuReturnItem 9 "返回系统与脚本" "回到上级菜单"
    menuClose
    autoRead fail2ban_menu "请选择:" selectFail2banMenuType
    case "${selectFail2banMenuType}" in
    1)
        showFail2banRuntimeStatus
        ;;
    2)
        fail2banApplyProfile "$(fail2banRecommendedProfileName)"
        ;;
    3)
        fail2banApplyProfile sshd
        ;;
    4)
        fail2banApplyProfile sshd+control
        ;;
    5)
        fail2banApplyNginxScanExtension enable
        ;;
    6)
        fail2banApplyNginxScanExtension disable
        ;;
    7)
        showFail2banBans
        ;;
    8)
        fail2banApplyProfile disabled
        ;;
    9)
        systemScriptMenu
        ;;
    *)
        errorCard "选择错误，重新选择"
        manageFail2ban
        ;;
    esac
}
