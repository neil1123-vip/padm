#!/usr/bin/env bash

SERVICE_ACTIONS=

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
    while read -r entry; do
        [[ -n "${entry}" ]] || continue
        serviceName=${entry%%:*}
        action=${entry#*:}
        case "${serviceName}" in
        nginx)
            if [[ "${action}" == "restart" ]]; then
                handleNginx stop
                handleNginx start
            else
                handleNginx "${action}"
            fi
            ;;
        xray)
            if [[ "${action}" == "restart" ]]; then
                handleXray stop
                handleXray start
            else
                handleXray "${action}"
            fi
            ;;
        sing-box)
            if [[ "${action}" == "restart" ]]; then
                handleSingBox stop
                handleSingBox start
            else
                handleSingBox "${action}"
            fi
            ;;
        esac
    done <<<"${SERVICE_ACTIONS}"
    SERVICE_ACTIONS=
}

nginxRunning() {
    pgrep -x nginx >/dev/null 2>&1
}

# 操作Nginx
handleNginx() {

    if ! protocolSelectionSkipsNginx "${selectCustomInstallType}" && ! nginxRunning && [[ "$1" == "start" ]]; then
        if [[ "${release}" == "alpine" ]]; then
            rc-service nginx start 2>/etc/padm/nginx_error.log
        else
            systemctl start nginx 2>/etc/padm/nginx_error.log
        fi

        sleep 0.5

        if ! nginxRunning; then
            echoContent red " ---> Nginx启动失败"
            echoContent red " ---> 请将下方日志反馈给开发者"
            nginx
            if grep -q "journalctl -xe" </etc/padm/nginx_error.log; then
                updateSELinuxHTTPPortT
            fi
        else
            echoContent green " ---> Nginx启动成功"
        fi

    elif nginxRunning && [[ "$1" == "stop" ]]; then

        if [[ "${release}" == "alpine" ]]; then
            rc-service nginx stop
        else
            systemctl stop nginx
        fi
        sleep 0.5

        if [[ -z ${btDomain} ]] && nginxRunning; then
            pgrep -x nginx | xargs -r kill -9
        fi
        echoContent green " ---> Nginx关闭成功"
    fi
}


singBoxRunning() {
    pgrep -f '/etc/padm/sing-box/sing-box' >/dev/null 2>&1
}

# 操作sing-box
handleSingBox() {
    if [[ -f "/etc/systemd/system/sing-box.service" ]]; then
        if ! singBoxRunning && [[ "$1" == "start" ]]; then
            singBoxMergeConfig
            systemctl start sing-box.service
        elif singBoxRunning && [[ "$1" == "stop" ]]; then
            systemctl stop sing-box.service
        fi
    elif [[ -f "/etc/init.d/sing-box" ]]; then
        if ! singBoxRunning && [[ "$1" == "start" ]]; then
            singBoxMergeConfig
            rc-service sing-box start
        elif singBoxRunning && [[ "$1" == "stop" ]]; then
            rc-service sing-box stop
        fi
    fi
    sleep 1

    if [[ "$1" == "start" ]]; then
        if singBoxRunning; then
            echoContent green " ---> sing-box启动成功"
        else
            echoContent red "sing-box启动失败"
            echoContent yellow "请手动执行【 /etc/padm/sing-box/sing-box merge config.json -C /etc/padm/sing-box/conf/config/ -D /etc/padm/sing-box/conf/ 】，查看错误日志"
            echo
            echoContent yellow "如上面命令没有错误，请手动执行【 /etc/padm/sing-box/sing-box run -c /etc/padm/sing-box/conf/config.json 】，查看错误日志"
            exit 0
        fi
    elif [[ "$1" == "stop" ]]; then
        if ! singBoxRunning; then
            echoContent green " ---> sing-box关闭成功"
        else
            echoContent red " ---> sing-box关闭失败"
            echoContent red "请手动执行【ps -ef|grep -v grep|grep sing-box|awk '{print \$2}'|xargs kill -9】"
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
        exe=$(readlink -f "/proc/${pid}/exe" 2>/dev/null)
        cmdline=$(tr '\0' ' ' <"/proc/${pid}/cmdline" 2>/dev/null)
        [[ "${exe}" == "/etc/padm/xray/xray" || "${cmdline}" == *"/etc/padm/xray/xray"* ]] || continue
        [[ "${cmdline}" == *" api statsquery "* ]] && continue
        return 0
    done < <(pgrep -x xray 2>/dev/null)
    return 1
}

# 操作xray
handleXray() {
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]] && [[ -n $(find /etc/systemd/system/ -name "xray.service") ]]; then
        if ! xrayRunning && [[ "$1" == "start" ]]; then
            systemctl start xray.service
        elif xrayRunning && [[ "$1" == "stop" ]]; then
            systemctl stop xray.service
        fi
    elif [[ -f "/etc/init.d/xray" ]]; then
        if ! xrayRunning && [[ "$1" == "start" ]]; then
            rc-service xray start
        elif xrayRunning && [[ "$1" == "stop" ]]; then
            rc-service xray stop
        fi
    fi

    sleep 0.8

    if [[ "$1" == "start" ]]; then
        if xrayRunning; then
            echoContent green " ---> Xray启动成功"
        else
            echoContent red "Xray启动失败"
            echoContent red "请手动执行以下的命令后【/etc/padm/xray/xray -confdir /etc/padm/xray/conf】将错误日志进行反馈"
            exit 0
        fi
    elif [[ "$1" == "stop" ]]; then
        if ! xrayRunning; then
            echoContent green " ---> Xray关闭成功"
        else
            echoContent red "xray关闭失败"
            echoContent red "请手动执行【ps -ef|grep -v grep|grep xray|awk '{print \$2}'|xargs kill -9】"
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

