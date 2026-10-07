#!/usr/bin/env bash

SERVICE_ACTIONS=
SERVICE_QUEUE_ALLOW_FAILURE=

xrayStartTestLog() {
    padmTmpFilePath padm-xray-start-test.log
}

coreSystemdStart() {
    local unit=$1
    systemctl start "${unit}" && return 0
    systemctl reset-failed "${unit}" >/dev/null 2>&1 || true
    systemctl start "${unit}"
}

xrayServiceBinaryPath() {
    if declare -F coreXrayBinaryPath >/dev/null 2>&1; then
        coreXrayBinaryPath
        return
    fi
    printf '%s\n' "${PADM_XRAY_BINARY:-/etc/padm/xray/xray}"
}

xrayServiceConfigDir() {
    if declare -F coreXrayConfigDir >/dev/null 2>&1; then
        coreXrayConfigDir
        return
    fi
    if [[ -n "${PADM_XRAY_CONF_DIR:-}" ]]; then
        printf '%s\n' "${PADM_XRAY_CONF_DIR%/}"
        return
    fi
    printf '%s\n' "${PADM_XRAY_DIR:-/etc/padm/xray}/conf"
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
        attempt=$((attempt + 1))
        (( attempt >= maxAttempts )) || sleep "${sleepSeconds}"
    done
    return 1
}

padmReadProcExe() {
    local path=$1
    readlink -f "${path}" 2>/dev/null || true
}

padmReadProcArgs() {
    local -n resultRef=$1
    local path=$2
    resultRef=()
    [[ -r "${path}" ]] || return 1
    mapfile -d '' -t resultRef 2>/dev/null <"${path}"
}

padmCommandExists() {
    command -v "$1" >/dev/null 2>&1
}

serviceQueueAdd() {
    local serviceName=$1
    local action=$2
    local entry="${serviceName}:${action}"
    if [[ $'\n'"${SERVICE_ACTIONS}"$'\n' != *$'\n'"${entry}"$'\n'* ]]; then
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

serviceQueueRefresh() {
    serviceQueueAdd "$1" refresh
}

serviceInstalled() {
    local serviceName=$1
    case "${serviceName}" in
    xray)
        local binary
        binary=$(xrayServiceBinaryPath)
        [[ -f "${binary}" && -x "${binary}" ||
            -f "${PADM_XRAY_SYSTEMD_SERVICE_FILE:-/etc/systemd/system/xray.service}" ||
            -f "${PADM_XRAY_OPENRC_SERVICE_FILE:-/etc/init.d/xray}" ]]
        ;;
    sing-box)
        local binary=${PADM_SINGBOX_BINARY:-/etc/padm/sing-box/sing-box}
        if declare -F coreSingBoxBinaryPath >/dev/null 2>&1; then
            binary=$(coreSingBoxBinaryPath)
        fi
        [[ -f "${binary}" && -x "${binary}" ||
            -f "${PADM_SINGBOX_SYSTEMD_SERVICE_FILE:-/etc/systemd/system/sing-box.service}" ||
            -f "${PADM_SINGBOX_OPENRC_SERVICE_FILE:-/etc/init.d/sing-box}" ]]
        ;;
    nginx)
        nginxServiceInstalled || padmCommandExists nginx
        ;;
    *) return 1 ;;
    esac
}

serviceRunning() {
    case "$1" in
    xray) xrayRunning ;;
    sing-box) singBoxRunning ;;
    nginx) nginxRunning ;;
    *) return 1 ;;
    esac
}

serviceActionSupported() {
    case "$1:$2" in
    xray:start | xray:stop | xray:restart | sing-box:start | sing-box:stop | sing-box:restart | nginx:start | nginx:stop | nginx:restart | nginx:reload | nginx:refresh) return 0 ;;
    *) return 1 ;;
    esac
}

runServiceAction() {
    local serviceName=$1
    local action=$2
    local handler

    if ! serviceActionSupported "${serviceName}" "${action}"; then
        errorCard "不支持的服务动作: ${serviceName}:${action}"
        return 1
    fi
    case "${serviceName}" in
    nginx) handler=handleNginx ;;
    xray) handler=handleXray ;;
    sing-box) handler=handleSingBox ;;
    esac
    case "${action}" in
    start)
        serviceRunning "${serviceName}" && return 0
        "${handler}" start
        ;;
    stop)
        "${handler}" stop
        ;;
    restart)
        # 停服前验证磁盘配置，避免无效配置中断仍可用的服务。
        case "${serviceName}" in
        nginx) checkNginxConfig true ;;
        xray) validateXrayConfigWithBinary "$(xrayServiceBinaryPath)" "$(xrayStartTestLog)" ;;
        sing-box) singBoxMergeConfig check ;;
        esac || {
            errorCard "${serviceName} 配置检查失败，已取消重启"
            return 1
        }
        "${handler}" stop || return 1
        if [[ "${serviceName}" == nginx ]]; then
            "${handler}" start restore
        else
            "${handler}" start
        fi
        ;;
    reload | refresh)
        "${handler}" "${action}"
        ;;
    esac
}

serviceQueueApply() {
    local entry serviceName action
    local status=0
    local SERVICE_QUEUE_ALLOW_FAILURE=true
    while read -r entry; do
        [[ -n "${entry}" ]] || continue
        serviceName=${entry%%:*}
        action=${entry#*:}
        runServiceAction "${serviceName}" "${action}" || status=1
    done <<<"${SERVICE_ACTIONS}"
    SERVICE_ACTIONS=
    return "${status}"
}

nginxRunning() {
    local pid exe option auxiliary OPTIND OPTARG
    local -a procArgs=()
    while IFS= read -r pid; do
        [[ -n "${pid}" ]] || continue
        exe=$(padmReadProcExe "/proc/${pid}/exe")
        padmReadProcArgs procArgs "/proc/${pid}/cmdline" || continue
        [[ "${exe}" == *"/nginx" || "${procArgs[0]:-}" == "nginx: master process"* ]] || continue
        # getopts 保留参数边界，避免把 -c/-g 等参数中的字符当成辅助命令。
        auxiliary=false
        OPTIND=1
        while getopts ':hvVtTqs:p:c:e:g:' option "${procArgs[@]:1}"; do
            case "${option}" in
            h | v | V | t | T | s) auxiliary=true; break ;;
            esac
        done
        [[ "${auxiliary}" == false ]] || continue
        return 0
    done < <(pgrep -x nginx 2>/dev/null)
    return 1
}

nginxServiceInstalled() {
    if [[ "${release:-}" == "alpine" ]]; then
        local openRcServiceFile=${PADM_NGINX_OPENRC_SERVICE_FILE:-/etc/init.d/nginx}
        [[ -e "${openRcServiceFile}" || -L "${openRcServiceFile}" ]]
    else
        [[ -e /etc/systemd/system/nginx.service || -e /usr/lib/systemd/system/nginx.service || -e /lib/systemd/system/nginx.service ]]
    fi
}

nginxRuntimeReasons() {
    local configRoot="${nginxConfigPath:-/etc/nginx/conf.d/}"
    local protocolSelection="${selectCustomInstallType:-${currentInstallProtocolType:-}}"
    local streamConf=

    if [[ "${protocolSelection}" =~ [0-9] ]] &&
        declare -F protocolSelectionSkipsNginx >/dev/null 2>&1 &&
        ! protocolSelectionSkipsNginx "${protocolSelection}"; then
        printf '%s\n' "当前协议入口"
    fi
    if declare -F realityStreamSplitConfFile >/dev/null 2>&1; then
        streamConf=$(realityStreamSplitConfFile)
    fi
    [[ -n "${streamConf}" && -f "${streamConf}" ]] && printf '%s\n' "Reality 443 共存"
    [[ -f "${configRoot%/}/alone.conf" ]] && printf '%s\n' "传统 TLS fallback"
    [[ -f "${configRoot%/}/sing_box_VMess_HTTPUpgrade.conf" ]] && printf '%s\n' "sing-box HTTPUpgrade"
    [[ -f "${configRoot%/}/subscribe.conf" ]] && printf '%s\n' "订阅发布"
    [[ -f "${configRoot%/}/padm-control-wg.conf" ]] && printf '%s\n' "WireGuard 控制面"
    if command -v jq >/dev/null 2>&1; then
        if [[ ! -f "${streamConf}" ]] && declare -F realityStreamSplitEnabled >/dev/null 2>&1 && realityStreamSplitEnabled; then
            printf '%s\n' "Reality 443 共存"
        fi
        if [[ ! -f "${configRoot%/}/padm-control-wg.conf" ]] &&
            declare -F subscriptionWireGuardControlEnabled >/dev/null 2>&1 &&
            subscriptionWireGuardControlEnabled >/dev/null 2>&1; then
            printf '%s\n' "WireGuard 控制面"
        fi
    fi
}

nginxRuntimeRequired() {
    [[ -n "$(nginxRuntimeReasons)" ]]
}

checkNginxConfig() {
    local quiet=${1:-false}
    local nginxErrorLog="${PADM_NGINX_ERROR_LOG:-/etc/padm/nginx_error.log}"

    if ! nginx -t >"${nginxErrorLog}" 2>&1; then
        errorCard "Nginx 配置检查失败"
        menuLine "$(uiStyle value "排查日志: ${nginxErrorLog}")"
        return 1
    fi
    [[ "${quiet}" == "true" ]] || successCard "Nginx 配置检查通过"
}

# 操作 Nginx
handleNginx() {
    local nginxErrorLog="${PADM_NGINX_ERROR_LOG:-/etc/padm/nginx_error.log}"
    local selinuxRetryDone=false

    if [[ "$1" == "reload" || "$1" == "refresh" ]]; then
        checkNginxConfig true || return 1
        if nginxRunning; then
            if ! nginx -s reload >>"${nginxErrorLog}" 2>&1; then
                errorCard "Nginx reload 失败"
                menuLine "$(uiStyle value "排查日志: ${nginxErrorLog}")"
                return 1
            fi
            successCard "Nginx reload 成功"
            return 0
        fi
        if [[ "$1" == "reload" ]]; then
            errorCard "Nginx 未运行，无法 reload"
            return 1
        fi
        nginxRuntimeRequired || return 0
        handleNginx start
        return $?
    fi

    if [[ "$1" == "start" ]] && { [[ "${2:-}" == "restore" ]] || nginxRuntimeRequired; } && ! nginxRunning; then
        while true; do
            if [[ "${release}" == "alpine" ]] && nginxServiceInstalled && padmCommandExists rc-service; then
                rc-service nginx start 2>"${nginxErrorLog}"
            elif [[ "${release}" != "alpine" ]] && nginxServiceInstalled && padmCommandExists systemctl; then
                systemctl start nginx 2>"${nginxErrorLog}"
            else
                nginx 2>"${nginxErrorLog}"
            fi

            sleep 0.5

            if nginxRunning; then
                successCard "Nginx启动成功"
                return 0
            fi
            nginxStartFailureCard "请查看下方日志" "如无法处理，请将日志反馈给开发者"
            nginx -t 2>&1 || true
            if [[ "${selinuxRetryDone}" == "false" ]] && grep -q "journalctl -xe" <"${nginxErrorLog}" && updateSELinuxHTTPPortT; then
                selinuxRetryDone=true
                continue
            fi
            return 1
        done

    elif [[ "$1" == "stop" ]]; then

        if [[ "${release}" == "alpine" ]] && nginxServiceInstalled && padmCommandExists rc-service; then
            rc-service nginx stop
        elif [[ "${release}" != "alpine" ]] && nginxServiceInstalled && padmCommandExists systemctl; then
            systemctl stop nginx
        else
            nginxRunning || return 0
            nginx -s stop >/dev/null 2>&1
        fi || { errorCard "Nginx关闭失败"; return 1; }
        sleep 0.5

        if nginxRunning; then
            errorCard "Nginx关闭失败"
            return 1
        fi
        successCard "Nginx关闭成功"
        return 0
    fi
    [[ "$1" == "start" || "$1" == "stop" ]] && return 0
    return 1
}


singBoxRunning() {
    local pid
    local exe
    local -a procArgs=()
    local mergedConfig
    local systemdServiceFile
    local openRcServiceFile
    local binary
    binary=$(coreSingBoxBinaryPath 2>/dev/null || true)
    [[ -n "${binary}" ]] || return 1
    mergedConfig=$(singBoxMergedConfigFile 2>/dev/null || true)
    systemdServiceFile=${PADM_SINGBOX_SYSTEMD_SERVICE_FILE:-/etc/systemd/system/sing-box.service}
    openRcServiceFile=${PADM_SINGBOX_OPENRC_SERVICE_FILE:-/etc/init.d/sing-box}
    while IFS= read -r pid; do
        [[ -n "${pid}" ]] || continue
        exe=$(padmReadProcExe "/proc/${pid}/exe")
        [[ "${exe}" == "${binary}" || "${exe}" == "${binary} (deleted)" ]] || continue
        padmReadProcArgs procArgs "/proc/${pid}/cmdline" || continue
        [[ -n "${mergedConfig}" && "${procArgs[0]:-}" == "${binary}" && "${procArgs[1]:-}" == run &&
            "${procArgs[2]:-}" == -c && "${procArgs[3]:-}" == "${mergedConfig}" ]] || continue
        return 0
    done < <(pgrep -x sing-box 2>/dev/null)
    if [[ "${release:-}" != "alpine" && -f "${systemdServiceFile}" ]] && padmCommandExists systemctl; then
        systemctl is-active --quiet sing-box.service && return 0
    elif [[ -n "${openRcServiceFile}" && -f "${openRcServiceFile}" ]] && padmCommandExists rc-service; then
        rc-service sing-box status >/dev/null 2>&1 && return 0
    fi
    return 1
}

handleSingBoxMergeFailure() {
    local binary configDir confDir
    binary=$(coreSingBoxBinaryPath)
    configDir=$(singBoxConfigShardDir)
    confDir=$(singBoxConfigConfDir)
    errorCard "sing-box配置合并失败"
    menuLine "$(uiStyle warn "请手动执行以下命令查看 merge 错误日志：")"
    menuLine "$(uiStyle value "${binary} merge config.json -C ${configDir} -D ${confDir}/")"
    return 1
}

# 操作 sing-box
handleSingBox() {
    local serviceManager=
    if [[ "${release:-}" != "alpine" ]] &&
        [[ -f "${PADM_SINGBOX_SYSTEMD_SERVICE_FILE:-/etc/systemd/system/sing-box.service}" ]] &&
        padmCommandExists systemctl; then
        serviceManager=systemd
    elif [[ -f "${PADM_SINGBOX_OPENRC_SERVICE_FILE:-/etc/init.d/sing-box}" ]] &&
        padmCommandExists rc-service; then
        serviceManager=openrc
    fi
    if [[ -n "${serviceManager}" ]]; then
        if ! singBoxRunning && [[ "$1" == "start" ]]; then
            if ! singBoxMergeConfig check; then
                handleSingBoxMergeFailure
                return 1
            fi
            case "${serviceManager}" in
            systemd) coreSystemdStart sing-box.service ;;
            openrc) rc-service sing-box start ;;
            esac
        elif [[ "$1" == "stop" ]]; then
            case "${serviceManager}" in
            systemd) systemctl stop sing-box.service ;;
            openrc) rc-service sing-box stop ;;
            esac || { errorCard "sing-box关闭失败"; return 1; }
        fi
    fi
    if [[ "$1" == "start" ]]; then
        if waitForServiceState singBoxRunning running 20 0.1; then
            successCard "sing-box启动成功"
        else
            errorCard "sing-box启动失败"
            menuLine "$(uiStyle warn "请手动执行以下命令查看 merge 错误日志：")"
            menuLine "$(uiStyle value "$(coreSingBoxBinaryPath) merge config.json -C $(singBoxConfigShardDir) -D $(singBoxConfigConfDir)/")"
            echo
            menuLine "$(uiStyle warn "如 merge 命令没有错误，请手动执行以下命令查看运行日志：")"
            menuLine "$(uiStyle value "$(coreSingBoxBinaryPath) run -c $(singBoxMergedConfigFile)")"
            return 1
        fi
    elif [[ "$1" == "stop" ]]; then
        if waitForServiceState singBoxRunning stopped 20 0.1; then
            successCard "sing-box关闭成功"
        else
            errorCard "sing-box关闭失败"
            menuLine "$(uiStyle warn "请手动执行以下命令清理残留进程：")"
            menuLine "$(uiStyle value "ps -ef|grep -v grep|grep sing-box|awk '{print \$2}'|xargs kill -9")"
            return 1
        fi
    else
        return 1
    fi
    return 0
}


xrayRunning() {
    local pid
    local exe
    local -a procArgs=()
    local index configMatched testMode
    local xrayBinary
    local xrayConfigDir
    local systemdServiceFile=${PADM_XRAY_SYSTEMD_SERVICE_FILE:-/etc/systemd/system/xray.service}
    local openRcServiceFile=${PADM_XRAY_OPENRC_SERVICE_FILE:-/etc/init.d/xray}
    xrayBinary=$(xrayServiceBinaryPath)
    xrayConfigDir=$(xrayServiceConfigDir)
    while IFS= read -r pid; do
        [[ -n "${pid}" ]] || continue
        exe=$(padmReadProcExe "/proc/${pid}/exe")
        [[ "${exe}" == "${xrayBinary}" || "${exe}" == "${xrayBinary} (deleted)" ]] || continue
        padmReadProcArgs procArgs "/proc/${pid}/cmdline" || continue
        configMatched=false
        testMode=false
        for ((index = 1; index < ${#procArgs[@]}; index++)); do
            case "${procArgs[index]}" in
            -confdir) [[ "${procArgs[index + 1]:-}" != "${xrayConfigDir}" ]] || configMatched=true ;;
            -test | -test=*) testMode=true ;;
            esac
        done
        [[ "${configMatched}" == true && "${testMode}" == false ]] || continue
        return 0
    done < <(pgrep -x xray 2>/dev/null)
    if [[ "${release:-}" != "alpine" && -f "${systemdServiceFile}" ]] && padmCommandExists systemctl; then
        systemctl is-active --quiet xray.service && return 0
    elif [[ -n "${openRcServiceFile}" && -f "${openRcServiceFile}" ]] && padmCommandExists rc-service; then
        rc-service xray status >/dev/null 2>&1 && return 0
    fi
    return 1
}

# 操作 Xray-core
handleXray() {
    local logFile serviceManager=
    local xrayBinary
    local xrayConfigDir
    xrayBinary=$(xrayServiceBinaryPath)
    xrayConfigDir=$(xrayServiceConfigDir)
    if [[ "${release:-}" != "alpine" ]] &&
        [[ -f "${PADM_XRAY_SYSTEMD_SERVICE_FILE:-/etc/systemd/system/xray.service}" ]] &&
        padmCommandExists systemctl; then
        serviceManager=systemd
    elif [[ -f "${PADM_XRAY_OPENRC_SERVICE_FILE:-/etc/init.d/xray}" ]] &&
        padmCommandExists rc-service; then
        serviceManager=openrc
    fi
    if [[ -n "${serviceManager}" ]]; then
        if ! xrayRunning && [[ "$1" == "start" ]]; then
            logFile=$(xrayStartTestLog)
            if ! validateXrayConfigWithBinary "${xrayBinary}" "${logFile}"; then
                xrayConfigValidationFailureCard "已取消启动" "排查日志: ${logFile}"
                return 1
            fi
            case "${serviceManager}" in
            systemd) coreSystemdStart xray.service ;;
            openrc) rc-service xray start ;;
            esac
        elif [[ "$1" == "stop" ]]; then
            case "${serviceManager}" in
            systemd) systemctl stop xray.service ;;
            openrc) rc-service xray stop ;;
            esac || { errorCard "Xray关闭失败"; return 1; }
        fi
    fi
    if [[ "$1" == "start" ]]; then
        if waitForServiceState xrayRunning running 25 0.1; then
            successCard "Xray启动成功"
        else
            errorCard "Xray启动失败"
            menuLine "$(uiStyle warn "请手动执行以下命令并反馈错误日志：")"
            menuLine "$(uiStyle value "${xrayBinary} -confdir ${xrayConfigDir}")"
            return 1
        fi
    elif [[ "$1" == "stop" ]]; then
        if waitForServiceState xrayRunning stopped "${PADM_XRAY_STOP_WAIT_ATTEMPTS:-60}" "${PADM_XRAY_STOP_WAIT_INTERVAL:-0.1}"; then
            successCard "Xray关闭成功"
        else
            errorCard "xray关闭失败"
            menuLine "$(uiStyle warn "请手动执行以下命令清理残留进程：")"
            menuLine "$(uiStyle value "ps -ef|grep -v grep|grep xray|awk '{print \$2}'|xargs kill -9")"
            return 1
        fi
    else
        return 1
    fi
    return 0
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
    serviceQueueApply || return 1
    if [[ "${PADM_SKIP_CONTROLLER_REFRESH:-}" != "1" && "${PADM_CONTROL_SERVER:-}" != "1" ]] &&
        declare -F subscriptionNotifyControllerRefresh >/dev/null 2>&1; then
        subscriptionNotifyControllerRefresh || true
    fi
}
