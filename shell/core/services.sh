#!/usr/bin/env bash

SERVICE_ACTIONS=
SERVICE_QUEUE_ALLOW_FAILURE=

xrayStartTestLog() {
    padmFallbackTmpFilePath padm-xray-start-test.log
}

waitForServiceState() {
    local checkFunc=$1
    local expectState=$2
    local maxAttempts=${3:-20}
    local sleepSeconds=${4:-0.1}
    local attempt=0

    while (( attempt < maxAttempts )); do
        if [[ "${expectState}" == "running" ]]; then
            if "${checkFunc}"; then
                return 0
            fi
        else
            if ! "${checkFunc}"; then
                return 0
            fi
        fi
        sleep "${sleepSeconds}"
        attempt=$((attempt + 1))
    done
    return 1
}

padmReadProcExe() {
    local path=$1
    readlink -f "${path}" 2>/dev/null || true
}

padmReadProcCmdline() {
    local path=$1
    [[ -r "${path}" ]] || return 0
    tr '\0' ' ' <"${path}" 2>/dev/null || true
}

serviceQueueAdd() {
    local serviceName=$1
    local action=$2
    local entry="${serviceName}:${action}"
    if ! printf '%s\n' "${SERVICE_ACTIONS}" | grep -qx "${entry}"; then
        SERVICE_ACTIONS="${SERVICE_ACTIONS}
${entry}"
    fi
}

serviceQueueStop() {
    serviceQueueAdd "$1" stop
}

serviceQueueStart() {
    serviceQueueAdd "$1" start
}

serviceQueueRestart() {
    serviceQueueAdd "$1" restart
}

serviceQueueApply() {
    local entry serviceName action
    local status=0
    local previousAllowFailure="${SERVICE_QUEUE_ALLOW_FAILURE:-}"
    SERVICE_QUEUE_ALLOW_FAILURE=true
    while read -r entry; do
        [[ -n "${entry}" ]] || continue
        serviceName=${entry%%:*}
        action=${entry#*:}
        case "${serviceName}" in
        nginx)
            if [[ "${action}" == "restart" ]]; then
                handleNginx stop || status=1
                handleNginx start || status=1
            else
                handleNginx "${action}" || status=1
            fi
            ;;
        xray)
            if [[ "${action}" == "restart" ]]; then
                handleXray stop || status=1
                handleXray start || status=1
            elif [[ "${action}" == "start" && xrayRunning ]]; then
                handleXray stop || status=1
                handleXray start || status=1
            else
                handleXray "${action}" || status=1
            fi
            ;;
        sing-box)
            if [[ "${action}" == "restart" ]]; then
                handleSingBox stop || status=1
                handleSingBox start || status=1
            elif [[ "${action}" == "start" && singBoxRunning ]]; then
                handleSingBox stop || status=1
                handleSingBox start || status=1
            else
                handleSingBox "${action}" || status=1
            fi
            ;;
        esac
    done <<<"${SERVICE_ACTIONS}"
    SERVICE_ACTIONS=
    SERVICE_QUEUE_ALLOW_FAILURE="${previousAllowFailure}"
    return "${status}"
}

nginxRunning() {
    local pid
    local exe
    local cmdline
    while IFS= read -r pid; do
        [[ -n "${pid}" ]] || continue
        exe=$(padmReadProcExe "/proc/${pid}/exe")
        cmdline=$(padmReadProcCmdline "/proc/${pid}/cmdline")
        [[ "${exe}" == *"/nginx" || "${cmdline}" == *"nginx: master process"* ]] || continue
        return 0
    done < <(pgrep -x nginx 2>/dev/null)
    return 1
}

nginxServiceInstalled() {
    [[ -e /etc/systemd/system/nginx.service || -e /usr/lib/systemd/system/nginx.service || -e /lib/systemd/system/nginx.service ]]
}

# 操作 Nginx
handleNginx() {
    local nginxErrorLog="${PADM_NGINX_ERROR_LOG:-/etc/padm/nginx_error.log}"

    if ! protocolSelectionSkipsNginx "${selectCustomInstallType}" && ! nginxRunning && [[ "$1" == "start" ]]; then
        if [[ "${release}" == "alpine" ]]; then
            rc-service nginx start 2>"${nginxErrorLog}"
        elif nginxServiceInstalled; then
            systemctl start nginx 2>"${nginxErrorLog}"
        else
            nginx 2>"${nginxErrorLog}"
        fi

        sleep 0.5

        if ! nginxRunning; then
            statusCard "Nginx 启动失败" "请查看下方日志" "如无法处理，请将日志反馈给开发者"
            nginx -t 2>&1 || true
            if grep -q "journalctl -xe" <"${nginxErrorLog}"; then
                updateSELinuxHTTPPortT
            fi
            [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "true" ]] && return 1
            exit 0
        fi
        successCard "Nginx启动成功"
        return 0

    elif nginxRunning && [[ "$1" == "stop" ]]; then

        if [[ "${release}" == "alpine" ]]; then
            rc-service nginx stop
        elif nginxServiceInstalled; then
            systemctl stop nginx
        else
            nginx -s stop >/dev/null 2>&1 || true
        fi
        sleep 0.5

        if [[ -z ${btDomain} ]] && nginxRunning; then
            pgrep -x nginx | xargs -r kill -9
            sleep 0.5
        fi
        if nginxRunning; then
            errorCard "Nginx关闭失败"
            [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "true" ]] && return 1
            exit 0
        fi
        successCard "Nginx关闭成功"
        return 0
    fi
    return 0
}


singBoxRunning() {
    local pid
    local exe
    local cmdline
    local mergedConfig
    local systemdServiceFile
    local openRcServiceFile
    mergedConfig=$(singBoxMergedConfigFile 2>/dev/null || true)
    systemdServiceFile=${PADM_SINGBOX_SYSTEMD_SERVICE_FILE:-/etc/systemd/system/sing-box.service}
    openRcServiceFile=${PADM_SINGBOX_OPENRC_SERVICE_FILE:-/etc/init.d/sing-box}
    while IFS= read -r pid; do
        [[ -n "${pid}" ]] || continue
        exe=$(padmReadProcExe "/proc/${pid}/exe")
        cmdline=$(padmReadProcCmdline "/proc/${pid}/cmdline")
        [[ "${cmdline}" == *"/etc/padm/sing-box/sing-box run -c "* ]] || continue
        if [[ -z "${mergedConfig}" || "${cmdline}" != *" -c ${mergedConfig}"* ]]; then
            continue
        fi
        [[ "${exe}" == "/etc/padm/sing-box/sing-box" || "${exe}" == "/etc/padm/sing-box/sing-box (deleted)" ]] || continue
        if [[ -n "${systemdServiceFile}" && -f "${systemdServiceFile}" ]] || [[ -n "${openRcServiceFile}" && -f "${openRcServiceFile}" ]]; then
            [[ "${cmdline}" == *"/etc/padm/sing-box/sing-box run -c ${mergedConfig}"* ]] || continue
        fi
        return 0
    done < <(pgrep -x sing-box 2>/dev/null)
    return 1
}

handleSingBoxMergeFailure() {
    errorCard "sing-box配置合并失败"
    menuLine "$(uiStyle warn "请手动执行以下命令查看 merge 错误日志：")"
    menuLine "$(uiStyle value "/etc/padm/sing-box/sing-box merge config.json -C /etc/padm/sing-box/conf/config/ -D /etc/padm/sing-box/conf/")"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "true" ]] && return 1
    exit 0
}

# 操作 sing-box
handleSingBox() {
    if [[ -f "${PADM_SINGBOX_SYSTEMD_SERVICE_FILE:-/etc/systemd/system/sing-box.service}" ]]; then
        if ! singBoxRunning && [[ "$1" == "start" ]]; then
            if ! singBoxMergeConfig; then
                handleSingBoxMergeFailure
                return 1
            fi
            systemctl start sing-box.service
        elif singBoxRunning && [[ "$1" == "stop" ]]; then
            systemctl stop sing-box.service
        fi
    elif [[ -f "${PADM_SINGBOX_OPENRC_SERVICE_FILE:-/etc/init.d/sing-box}" ]]; then
        if ! singBoxRunning && [[ "$1" == "start" ]]; then
            if ! singBoxMergeConfig; then
                handleSingBoxMergeFailure
                return 1
            fi
            rc-service sing-box start
        elif singBoxRunning && [[ "$1" == "stop" ]]; then
            rc-service sing-box stop
        fi
    fi
    if [[ "$1" == "start" ]]; then
        if waitForServiceState singBoxRunning running 20 0.1; then
            successCard "sing-box启动成功"
        else
            errorCard "sing-box启动失败"
            menuLine "$(uiStyle warn "请手动执行以下命令查看 merge 错误日志：")"
            menuLine "$(uiStyle value "/etc/padm/sing-box/sing-box merge config.json -C /etc/padm/sing-box/conf/config/ -D /etc/padm/sing-box/conf/")"
            echo
            menuLine "$(uiStyle warn "如 merge 命令没有错误，请手动执行以下命令查看运行日志：")"
            menuLine "$(uiStyle value "/etc/padm/sing-box/sing-box run -c /etc/padm/sing-box/conf/config.json")"
            [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "true" ]] && return 1
            exit 0
        fi
    elif [[ "$1" == "stop" ]]; then
        if waitForServiceState singBoxRunning stopped 20 0.1; then
            successCard "sing-box关闭成功"
        else
            errorCard "sing-box关闭失败"
            menuLine "$(uiStyle warn "请手动执行以下命令清理残留进程：")"
            menuLine "$(uiStyle value "ps -ef|grep -v grep|grep sing-box|awk '{print \$2}'|xargs kill -9")"
            [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "true" ]] && return 1
            exit 0
        fi
    fi
}


xrayRunning() {
    local pid
    local exe
    local cmdline
    while IFS= read -r pid; do
        [[ -n "${pid}" ]] || continue
        exe=$(padmReadProcExe "/proc/${pid}/exe")
        cmdline=$(padmReadProcCmdline "/proc/${pid}/cmdline")
        [[ "${exe}" == "/etc/padm/xray/xray" || "${cmdline}" == *"/etc/padm/xray/xray"* ]] || continue
        [[ "${cmdline}" == *" api statsquery "* ]] && continue
        return 0
    done < <(pgrep -x xray 2>/dev/null)
    return 1
}

# 操作 Xray-core
handleXray() {
    local logFile
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]] && [[ -n $(find /etc/systemd/system/ -name "xray.service") ]]; then
        if ! xrayRunning && [[ "$1" == "start" ]]; then
            logFile=$(xrayStartTestLog)
            if [[ -x /etc/padm/xray/xray && -d /etc/padm/xray/conf ]] && ! /etc/padm/xray/xray -test -confdir /etc/padm/xray/conf >"${logFile}" 2>&1; then
                xrayConfigValidationFailureCard "已取消启动" "排查日志: ${logFile}"
                [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "true" ]] && return 1
                exit 0
            fi
            systemctl start xray.service
        elif xrayRunning && [[ "$1" == "stop" ]]; then
            systemctl stop xray.service
        fi
    elif [[ -f "/etc/init.d/xray" ]]; then
        if ! xrayRunning && [[ "$1" == "start" ]]; then
            logFile=$(xrayStartTestLog)
            if [[ -x /etc/padm/xray/xray && -d /etc/padm/xray/conf ]] && ! /etc/padm/xray/xray -test -confdir /etc/padm/xray/conf >"${logFile}" 2>&1; then
                xrayConfigValidationFailureCard "已取消启动" "排查日志: ${logFile}"
                [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "true" ]] && return 1
                exit 0
            fi
            rc-service xray start
        elif xrayRunning && [[ "$1" == "stop" ]]; then
            rc-service xray stop
        fi
    fi
    if [[ "$1" == "start" ]]; then
        if waitForServiceState xrayRunning running 25 0.1; then
            successCard "Xray启动成功"
        else
            errorCard "Xray启动失败"
            menuLine "$(uiStyle warn "请手动执行以下命令并反馈错误日志：")"
            menuLine "$(uiStyle value "/etc/padm/xray/xray -confdir /etc/padm/xray/conf")"
            [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "true" ]] && return 1
            exit 0
        fi
    elif [[ "$1" == "stop" ]]; then
        if waitForServiceState xrayRunning stopped 20 0.1; then
            successCard "Xray关闭成功"
        else
            errorCard "xray关闭失败"
            menuLine "$(uiStyle warn "请手动执行以下命令清理残留进程：")"
            menuLine "$(uiStyle value "ps -ef|grep -v grep|grep xray|awk '{print \$2}'|xargs kill -9")"
            [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "true" ]] && return 1
            exit 0
        fi
    fi
}


# 重启核心
reloadCore() {
    readInstallType

    if [[ "${coreInstallType}" == "1" ]]; then
        serviceQueueRestart xray
    fi
    if currentProtocolHas 20 || [[ "${coreInstallType}" == "2" || -n "${singBoxConfigPath}" ]]; then
        serviceQueueRestart sing-box
    fi
    serviceQueueApply
}
