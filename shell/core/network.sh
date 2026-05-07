#!/usr/bin/env bash

# 检查防火墙
allowPort() {
    local type=$2
    if [[ -z "${type}" ]]; then
        type=tcp
    fi
    # 如果防火墙启动状态则添加相应的开放端口
    if command -v dpkg >/dev/null 2>&1 && dpkg -l | grep -q "^[[:space:]]*ii[[:space:]]\+ufw"; then
        if ufw status | grep -q "Status: active"; then
            if ! ufw status | grep -q "$1/${type}"; then
                sudo ufw allow "$1/${type}"
                checkUFWAllowPort "$1"
            fi
        fi
    elif systemctl status firewalld 2>/dev/null | grep -q "active (running)"; then
        local updateFirewalldStatus=
        if ! firewall-cmd --list-ports --permanent | grep -qw "$1/${type}"; then
            updateFirewalldStatus=true
            local firewallPort=$1
            if echo "${firewallPort}" | grep -q ":"; then
                firewallPort=$(echo "${firewallPort}" | awk -F ":" '{print $1"-"$2}')
            fi
            firewall-cmd --zone=public --add-port="${firewallPort}/${type}" --permanent
            checkFirewalldAllowPort "${firewallPort}"
        fi

        if echo "${updateFirewalldStatus}" | grep -q "true"; then
            firewall-cmd --reload
        fi
    elif rc-update show 2>/dev/null | grep -q ufw; then
        if ufw status | grep -q "Status: active"; then
            if ! ufw status | grep -q "$1/${type}"; then
                sudo ufw allow "$1/${type}"
                checkUFWAllowPort "$1"
            fi
        fi
    elif dpkg -l | grep -q "^[[:space:]]*ii[[:space:]]\+netfilter-persistent" && systemctl status netfilter-persistent 2>/dev/null | grep -q "active (exited)"; then
        local updateFirewalldStatus=
        if ! iptables -L | grep -q "$1/${type}(neil1123-vip)"; then
            updateFirewalldStatus=true
            iptables -I INPUT -p "${type}" --dport "$1" -m comment --comment "allow $1/${type}(neil1123-vip)" -j ACCEPT
        fi

        if echo "${updateFirewalldStatus}" | grep -q "true"; then
            netfilter-persistent save
        fi
    fi
}

# 获取公网IP
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


# 输出ufw端口开放状态
checkUFWAllowPort() {
    if ufw status | grep -q "$1"; then
        echoContent green " ---> $1端口开放成功"
    else
        echoContent red " ---> $1端口开放失败"
        exit 0
    fi
}


# 输出firewall-cmd端口开放状态
checkFirewalldAllowPort() {
    if firewall-cmd --list-ports --permanent | grep -q "$1"; then
        echoContent green " ---> $1端口开放成功"
    else
        echoContent red " ---> $1端口开放失败"
        exit 0
    fi
}


# 通过dns检查域名的IP
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
            echoContent yellow " ---> 未获取到域名IPv4地址，等待后重试(${dnsRetryCount}/3)"
            sleep 2
        fi
    done
    if echo "${dnsIP}" | grep -q "timed out" || [[ -z "${dnsIP}" ]]; then
        echo
        echoContent red " ---> 无法通过DNS获取域名 IPv4 地址"
        echoContent green " ---> 尝试检查域名 IPv6 地址"
        dnsIP=$(dig @2606:4700:4700::1111 +time=2 aaaa +short "${domain}")
        ipType=6
        if echo "${dnsIP}" | grep -q "network unreachable" || [[ -z "${dnsIP}" ]]; then
            echoContent red " ---> 无法通过DNS获取域名IPv6地址，退出安装"
            exit 0
        fi
    fi
    local publicIP=

    publicIP=$(getPublicIP "${ipType}")
    if [[ "${publicIP}" != "${dnsIP}" ]]; then
        echoContent red " ---> 域名解析IP与当前服务器IP不一致\n"
        echoContent yellow " ---> 请检查域名解析是否生效以及正确"
        echoContent green " ---> 当前VPS IP：${publicIP}"
        echoContent green " ---> DNS解析 IP：${dnsIP}"
        exit 0
    else
        echoContent green " ---> 域名IP校验通过"
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
    allowPort "${port}"

    if [[ -z "${btDomain}" ]]; then

        handleNginx stop
        # 初始化nginx配置
        touch ${nginxConfigPath}checkPortOpen.conf
        local listenIPv6PortConfig=

        if hasIPv6Connectivity; then
            listenIPv6PortConfig="listen [::]:${port};"
        fi
        cat <<EOF >${nginxConfigPath}checkPortOpen.conf
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
        handleNginx start
        if [[ -z $(pgrep -f "nginx") ]]; then
            echoContent red " ---> Nginx未启动，无法检测${port}端口开放状态"
            echoContent yellow " ---> 请检查上方Nginx启动失败日志或执行 nginx -t 查看配置错误"
            rm -f "${nginxConfigPath}checkPortOpen.conf" >/dev/null 2>&1
            exit 0
        fi
        # 检查域名+端口的开放
        checkPortOpenResult=$(curl -s -m 10 "http://${domain}:${port}/checkPort")
        localIP=$(curl -s -m 10 "http://${domain}:${port}/ip")
        rm "${nginxConfigPath}checkPortOpen.conf"
        handleNginx stop
        if [[ "${checkPortOpenResult}" == "fjkvymb6len" ]]; then
            echoContent green " ---> 检测到${port}端口已开放"
        else
            echoContent green " ---> 未检测到${port}端口开放，退出安装"
            if echo "${checkPortOpenResult}" | grep -q "cloudflare"; then
                echoContent yellow " ---> 请关闭云朵后等待三分钟重新尝试"
            else
                if [[ -z "${checkPortOpenResult}" ]]; then
                    echoContent red " ---> 请检查是否有网页防火墙，比如Oracle等云服务商"
                    echoContent red " ---> 检查是否自己安装过nginx并且有配置冲突，可以尝试DD纯净系统后重新尝试"
                else
                    echoContent red " ---> 错误日志：${checkPortOpenResult}，请将此错误日志通过issues提交反馈"
                fi
            fi
            exit 0
        fi
        checkIP "${localIP}"
    fi
}


# 检查ip
checkIP() {
    echoContent skyBlue "\n ---> 检查域名ip中"
    local localIP=$1

    if [[ -z ${localIP} ]] || ! echo "${localIP}" | sed '1{s/[^(]*(//;s/).*//;q}' | grep -q '\.' && ! echo "${localIP}" | sed '1{s/[^(]*(//;s/).*//;q}' | grep -q ':'; then
        echoContent red "\n ---> 未检测到当前域名的ip"
        echoContent skyBlue " ---> 请依次进行下列检查"
        echoContent yellow " --->  1.检查域名是否书写正确"
        echoContent yellow " --->  2.检查域名dns解析是否正确"
        echoContent yellow " --->  3.如解析正确，请等待dns生效，预计三分钟内生效"
        echoContent yellow " --->  4.如报Nginx启动问题，请手动启动nginx查看错误，如自己无法处理请提issues"
        echo
        echoContent skyBlue " ---> 如以上设置都正确，请重新安装纯净系统后再次尝试"

        if [[ -n ${localIP} ]]; then
            echoContent yellow " ---> 检测返回值异常，建议手动卸载nginx后重新执行脚本"
            echoContent red " ---> 异常结果：${localIP}"
        fi
        exit 0
    else
        if echo "${localIP}" | awk -F "[,]" '{print $2}' | grep -q "." || echo "${localIP}" | awk -F "[,]" '{print $2}' | grep -q ":"; then
            echoContent red "\n ---> 检测到多个ip，请确认是否关闭cloudflare的云朵"
            echoContent yellow " ---> 关闭云朵后等待三分钟后重试"
            echoContent yellow " ---> 检测到的ip如下:[${localIP}]"
            exit 0
        fi
        echoContent green " ---> 检查当前域名IP正确"
    fi
}

# 检测端口是否占用
checkPort() {
    if [[ -z "$1" ]] || ! lsof -i "tcp:$1" | grep -q LISTEN; then
        return
    fi

    local port=$1
    local portProcess
    portProcess=$(lsof -nP -i "tcp:${port}" | grep LISTEN)
    echoContent red "\n ---> ${port}端口被占用"
    echoContent yellow "${portProcess}"

    if echo "${portProcess}" | grep -qiE "xray|sing-box|/etc/padm"; then
        echoContent yellow " ---> 检测到占用进程属于本脚本服务，尝试自动停止后继续安装"
        handleXray stop >/dev/null 2>&1
        handleSingBox stop >/dev/null 2>&1
        sleep 1
    elif echo "${portProcess}" | grep -qiE "nginx|openresty"; then
        echoContent yellow " ---> 检测到${port}端口被Nginx/OpenResty占用"
        read -r -p "是否停止该服务并继续安装？[y/n]:" stopPortProcessStatus
        if [[ "${stopPortProcessStatus}" == "y" ]]; then
            handleNginx stop >/dev/null 2>&1
            systemctl stop openresty >/dev/null 2>&1
            systemctl stop nginx >/dev/null 2>&1
            sleep 1
        else
            echoContent red " ---> 已取消安装，请手动处理${port}端口占用后重新执行"
            exit 0
        fi
    else
        read -r -p "是否停止占用${port}端口的进程并继续安装？[y/n]:" stopPortProcessStatus
        if [[ "${stopPortProcessStatus}" == "y" ]]; then
            lsof -ti "tcp:${port}" | xargs -r kill
            sleep 1
        else
            echoContent red " ---> 已取消安装，请手动处理${port}端口占用后重新执行"
            exit 0
        fi
    fi

    if lsof -i "tcp:${port}" | grep -q LISTEN; then
        echoContent red "\n ---> ${port}端口仍被占用，请手动关闭后安装\n"
        lsof -nP -i "tcp:${port}" | grep LISTEN
        exit 0
    fi
}

