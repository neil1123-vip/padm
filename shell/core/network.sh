#!/usr/bin/env bash

# 开放防火墙端口
allowPort() {
    local type=$2
    local firewallPort=$1
    if [[ -z "${type}" ]]; then
        type=tcp
    fi
    if [[ "${firewallPort}" == *:* ]]; then
        firewallPort=${firewallPort/:/-}
    fi
    # 如果防火墙启动状态则添加相应的开放端口
    if command -v dpkg >/dev/null 2>&1 && dpkg -l | grep -Eq "^[[:space:]]*ii[[:space:]]+ufw[[:space:]]"; then
        if ufw status | grep -q "Status: active"; then
            if ! ufw status | grep -q "$1/${type}"; then
                if ! sudo ufw allow "$1/${type}" || ! checkUFWAllowPort "$1"; then
                    sudo ufw delete allow "$1/${type}" >/dev/null 2>&1 || true
                    errorCard "$1端口开放失败，已尝试回滚本次 ufw 规则"
                    exit 1
                fi
            fi
        fi
    elif systemctl status firewalld 2>/dev/null | grep -q "active (running)"; then
        if ! firewall-cmd --list-ports --permanent | grep -qw "${firewallPort}/${type}"; then
            if ! firewall-cmd --zone=public --add-port="${firewallPort}/${type}" --permanent || ! firewall-cmd --reload || ! checkFirewalldAllowPort "${firewallPort}"; then
                firewall-cmd --zone=public --remove-port="${firewallPort}/${type}" --permanent >/dev/null 2>&1 || true
                firewall-cmd --reload >/dev/null 2>&1 || true
                errorCard "$1端口开放失败，已尝试回滚本次 firewalld 规则"
                exit 1
            fi
        fi
    elif rc-update show 2>/dev/null | grep -q ufw; then
        if ufw status | grep -q "Status: active"; then
            if ! ufw status | grep -q "$1/${type}"; then
                if ! sudo ufw allow "$1/${type}" || ! checkUFWAllowPort "$1"; then
                    sudo ufw delete allow "$1/${type}" >/dev/null 2>&1 || true
                    errorCard "$1端口开放失败，已尝试回滚本次 ufw 规则"
                    exit 1
                fi
            fi
        fi
    elif dpkg-query -W -f='${db:Status-Abbrev}' netfilter-persistent 2>/dev/null | grep -q '^ii' && systemctl is-active --quiet netfilter-persistent; then
        if ! iptables -L | grep -q "$1/${type}(neil1123-vip)"; then
            if ! iptables -I INPUT -p "${type}" --dport "$1" -m comment --comment "allow $1/${type}(neil1123-vip)" -j ACCEPT || ! netfilter-persistent save; then
                iptables -D INPUT -p "${type}" --dport "$1" -m comment --comment "allow $1/${type}(neil1123-vip)" -j ACCEPT >/dev/null 2>&1 || true
                netfilter-persistent save >/dev/null 2>&1 || true
                errorCard "$1端口开放失败，已尝试回滚本次 iptables 规则"
                exit 1
            fi
        fi
    fi
}

validPortNumber() {
    local port=$1
    [[ "${port}" =~ ^[0-9]{1,5}$ ]] && ((10#${port} >= 1 && 10#${port} <= 65535))
}

# 获取公网 IP
hasIPv6Connectivity() {
    [[ -n "$(curl --connect-timeout 2 -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2)" ]]
}

getPublicIP() {
    local type=4
    if [[ -n "$1" ]]; then
        type=$1
    fi
    if [[ -n "${currentHost}" && -z "$1" ]] && [[ "${singBoxVLESSRealityVisionSNI}" == "${currentHost}" || "${singBoxVLESSRealityGRPCSNI}" == "${currentHost}" || "${xrayVLESSRealitySNI}" == "${currentHost}" ]]; then
        echo "${currentHost}"
    else
        local currentIP=
        currentIP=$(curl -s "-${type}" http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
        if [[ -z "${currentIP}" && -z "$1" ]]; then
            currentIP=$(curl -s "-6" http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
        fi
        echo "${currentIP}"
    fi

}


# 输出 ufw 端口开放状态
checkUFWAllowPort() {
    if ufw status | grep -q "$1"; then
        successCard "$1端口开放成功"
    else
        errorCard "$1端口开放失败"
        return 1
    fi
}


# 输出 firewalld 端口开放状态
checkFirewalldAllowPort() {
    if firewall-cmd --list-ports --permanent | grep -q "$1"; then
        successCard "$1端口开放成功"
    else
        errorCard "$1端口开放失败"
        return 1
    fi
}


# 通过 DNS 检查域名 IP
checkDNSIP() {
    local domain=$1
    local dnsIP=
    ipType=4
    local dnsRetryCount=0
    while [[ ${dnsRetryCount} -lt 3 && -z "${dnsIP}" ]]; do
        dnsIP=$(dig @1.1.1.1 +time=2 +short "${domain}" | grep -E "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$")
        if [[ -z "${dnsIP}" ]]; then
            dnsIP=$(dig @8.8.8.8 +time=2 +short "${domain}" | grep -E "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$")
        fi
        dnsRetryCount=$((dnsRetryCount + 1))
        if [[ -z "${dnsIP}" && ${dnsRetryCount} -lt 3 ]]; then
            statusCard "DNS 重试" "未获取到域名 IPv4 地址，等待后重试(${dnsRetryCount}/3)"
            sleep 2
        fi
    done
    if [[ "${dnsIP}" == *"timed out"* || -z "${dnsIP}" ]]; then
        echo
        statusCard "DNS 解析回退" "无法通过 DNS 获取域名 IPv4 地址" "尝试检查域名 IPv6 地址"
        dnsIP=$(dig @2606:4700:4700::1111 +time=2 aaaa +short "${domain}")
        ipType=6
        if [[ "${dnsIP}" == *"network unreachable"* || -z "${dnsIP}" ]]; then
            errorCard "无法通过DNS获取域名IPv6地址，退出安装"
            return 1
        fi
    fi
    local publicIP=

    publicIP=$(getPublicIP "${ipType}")
    if [[ "${publicIP}" != "${dnsIP}" ]]; then
        statusCard "域名 IP 不一致" "当前 VPS IP：${publicIP}" "DNS 解析 IP：${dnsIP}" "请检查域名解析是否生效且正确"
        return 1
    else
        successCard "域名IP校验通过"
    fi
    return 0
}

writeCheckPortOpenNginxConfig() {
    local port=$1
    local domain=$2
    local listenIPv6PortConfig=$3
    local targetPath="${nginxConfigPath}checkPortOpen.conf"
    local tmpPath="${targetPath}.tmp"
    local backupPath="${targetPath}.bak"
    local tmpBase="${TMPDIR:-/tmp}"
    local nginxTestLog="${tmpBase%/}/padm-check-port-open-nginx-test.log"
    mkdir -p "$(dirname "${targetPath}")"
    cat >"${tmpPath}" <<EOF
server {
    listen ${port};
    ${listenIPv6PortConfig}
    server_name ${domain};
    location /checkPort {
        return 200 'fjkvymb6len';
    }
    location /ip {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header REMOTE-HOST \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        default_type text/plain;
        return 200 \$proxy_add_x_forwarded_for;
    }
}
EOF
    if command -v nginx >/dev/null 2>&1; then
        [[ -f "${targetPath}" ]] && cp "${targetPath}" "${backupPath}"
        mv "${tmpPath}" "${targetPath}"
        if ! nginx -t >"${nginxTestLog}" 2>&1; then
            if [[ -f "${backupPath}" ]]; then
                mv "${backupPath}" "${targetPath}"
            else
                rm -f "${targetPath}"
            fi
            return 1
        fi
        rm -f "${backupPath}"
    else
        mv "${tmpPath}" "${targetPath}"
    fi
}

# 检查端口实际开放状态
checkPortOpen() {
    handleSingBox stop >/dev/null 2>&1
    handleXray stop >/dev/null 2>&1
    cleanAgentNginxConf

    local port=$1
    local domain=$2
    local checkPortOpenResult=
    local localIP=
    allowPort "${port}"

    if [[ -z "${btDomain}" ]]; then

        handleNginx stop
        # 初始化 Nginx 端口检测配置
        local listenIPv6PortConfig=

        if hasIPv6Connectivity; then
            listenIPv6PortConfig="listen [::]:${port};"
        fi
        if ! writeCheckPortOpenNginxConfig "${port}" "${domain}" "${listenIPv6PortConfig}"; then
            statusCard "Nginx 配置校验失败" "无法检测 ${port} 端口开放状态" "请检查上方 Nginx 配置错误" "也可以执行 nginx -t 查看配置错误"
            rm -f "${nginxConfigPath}checkPortOpen.conf" >/dev/null 2>&1
            return 1
        fi
        handleNginx start
        if [[ -z $(pgrep -f "nginx") ]]; then
            statusCard "Nginx 启动失败" "无法检测 ${port} 端口开放状态" "请检查上方 Nginx 启动失败日志" "也可以执行 nginx -t 查看配置错误"
            rm -f "${nginxConfigPath}checkPortOpen.conf" >/dev/null 2>&1
            return 1
        fi
        # 检查域名和端口开放状态
        checkPortOpenResult=$(curl -s -m 10 "http://${domain}:${port}/checkPort")
        localIP=$(curl -s -m 10 "http://${domain}:${port}/ip")
        rm "${nginxConfigPath}checkPortOpen.conf"
        handleNginx stop
        if [[ "${checkPortOpenResult}" == "fjkvymb6len" ]]; then
            successCard "检测到${port}端口已开放"
        else
            successCard "未检测到${port}端口开放，退出安装"
            if [[ "${checkPortOpenResult}" == *cloudflare* ]]; then
                statusCard "端口开放检测失败" "检测到 Cloudflare 响应" "请关闭云朵后等待三分钟重新尝试"
            else
                if [[ -z "${checkPortOpenResult}" ]]; then
                    statusCard "端口开放检测失败" "请检查是否有网页防火墙，例如 Oracle 等云服务商" "请检查是否安装过 Nginx 并存在配置冲突" "仍无法处理时，可以尝试 DD 纯净系统后重新执行"
                else
                    statusCard "端口开放检测失败" "错误日志：${checkPortOpenResult}" "请将此错误日志通过 issues 提交反馈"
                fi
            fi
            return 1
        fi
        checkIP "${localIP}" || return 1
    fi
    return 0
}


# 检查 IP 回源结果
checkIP() {
    statusCard "域名 IP 检查" "检查域名 IP 中"
    local localIP=$1
    local normalizedIP
    local extraIP
    normalizedIP=$(echo "${localIP}" | sed '1{s/[^(]*(//;s/).*//;q}')
    extraIP=$(echo "${localIP}" | awk -F "[,]" '{print $2}')

    if [[ -z ${localIP} ]] || ! grep -q '\.' <<<"${normalizedIP}" && ! grep -q ':' <<<"${normalizedIP}"; then
        errorCard "未检测到当前域名的ip"
        echoContent title "\n┌─ 域名解析排障 ─────────────────────────────────────"
        menuLine "请依次进行下列检查"
        menuLine "检查域名是否书写正确"
        menuLine "检查域名 DNS 解析是否正确"
        menuLine "如解析正确，请等待 DNS 生效，预计三分钟内生效"
        menuLine "如报 Nginx 启动问题，请手动启动 nginx 查看错误；仍无法处理请提交 issue"
        menuClose

        statusCard "后续建议" "如以上设置都正确，请重新安装纯净系统后再次尝试"

        if [[ -n ${localIP} ]]; then
            statusCard "检测返回值异常" "异常结果：${localIP}" "建议手动卸载 Nginx 后重新执行脚本"
        fi
        return 1
    else
        if [[ "${extraIP}" == *.* || "${extraIP}" == *:* ]]; then
            statusCard "检测到多个 IP" "请确认是否关闭 Cloudflare 云朵" "关闭云朵后等待三分钟再重试" "检测到的 IP：${localIP}"
            return 1
        fi
        successCard "检查当前域名IP正确"
    fi
    return 0
}

# 检测端口是否占用
checkPort() {
    if [[ -z "$1" ]] || ! lsof -i "tcp:$1" | grep -q LISTEN; then
        return
    fi

    local port=$1
    local portProcess
    portProcess=$(lsof -nP -i "tcp:${port}" | grep LISTEN)
    errorCard "${port}端口被占用"
    echoContent yellow "${portProcess}"

    if echo "${portProcess}" | grep -qiE "xray|sing-box|/etc/padm"; then
        statusCard "端口占用" "检测到占用进程属于本脚本服务" "尝试自动停止后继续安装"
        handleXray stop >/dev/null 2>&1
        handleSingBox stop >/dev/null 2>&1
        sleep 1
    elif echo "${portProcess}" | grep -qiE "nginx|openresty"; then
        statusCard "端口占用" "检测到 ${port} 端口被 Nginx/OpenResty 占用"
        autoRead stop_port_service_confirm "是否停止该服务并继续安装？[y/n]:" stopPortProcessStatus
        if [[ "${stopPortProcessStatus}" == "y" ]]; then
            handleNginx stop >/dev/null 2>&1
            systemctl stop openresty >/dev/null 2>&1
            systemctl stop nginx >/dev/null 2>&1
            sleep 1
        else
            errorCard "已取消安装，请手动处理${port}端口占用后重新执行"
            return 1
        fi
    else
        autoRead stop_port_process_confirm "是否停止占用${port}端口的进程并继续安装？[y/n]:" stopPortProcessStatus
        if [[ "${stopPortProcessStatus}" == "y" ]]; then
            lsof -ti "tcp:${port}" | xargs -r kill
            sleep 1
        else
            errorCard "已取消安装，请手动处理${port}端口占用后重新执行"
            return 1
        fi
    fi

    if lsof -i "tcp:${port}" | grep -q LISTEN; then
        errorCard "${port}端口仍被占用，请手动关闭后安装\n"
        lsof -nP -i "tcp:${port}" | grep LISTEN
        return 1
    fi
}
