#!/usr/bin/env bash

refreshAptAfterRepoChange() {
    if [[ "${release}" != "ubuntu" && "${release}" != "debian" ]]; then
        return
    fi
    waitAptProcess
    runWithTimeout 300 "${upgrade} >/dev/null 2>&1"
}

# 安装工具包
installTools() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 安装工具"
    # 修复apt系统个别dpkg中断状态
    if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
        runWithTimeout 120 "dpkg --configure -a"
    fi

    waitAptProcess

    echoContent green " ---> 检查、安装更新【新机器会很慢，如长时间无反应，请手动停止后重新执行】"

    if [[ "${release}" != "centos" ]]; then
        runWithTimeout 600 "${upgrade} >/etc/padm/install.log 2>&1"
    fi

    if grep <"/etc/padm/install.log" -q "changed"; then
        runWithTimeout 300 "${updateReleaseInfoChange} >/dev/null 2>&1"
    fi

    if [[ "${release}" == "centos" ]]; then
        rm -rf /var/run/yum.pid
        runWithTimeout 300 "${installType} epel-release >/dev/null 2>&1"
    fi

    if ! sudo --version >/dev/null 2>&1; then
        echoContent green " ---> 安装sudo"
        runWithTimeout 300 "${installType} sudo >/dev/null 2>&1"
    fi

    if ! wget --help >/dev/null 2>&1; then
        echoContent green " ---> 安装wget"
        runWithTimeout 300 "${installType} wget >/dev/null 2>&1"
    fi

    if ! curl --help >/dev/null 2>&1; then
        echoContent green " ---> 安装curl"
        runWithTimeout 300 "${installType} curl >/dev/null 2>&1"
    fi

    if ! unzip >/dev/null 2>&1; then
        echoContent green " ---> 安装unzip"
        runWithTimeout 300 "${installType} unzip >/dev/null 2>&1"
    fi

    if ! socat -h >/dev/null 2>&1; then
        echoContent green " ---> 安装socat"
        runWithTimeout 300 "${installType} socat >/dev/null 2>&1"
    fi

    if ! tar --help >/dev/null 2>&1; then
        echoContent green " ---> 安装tar"
        runWithTimeout 300 "${installType} tar >/dev/null 2>&1"
    fi

    if ! crontab -l >/dev/null 2>&1; then
        echoContent green " ---> 安装crontabs"
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            runWithTimeout 300 "${installType} cron >/dev/null 2>&1"
        else
            runWithTimeout 300 "${installType} crontabs >/dev/null 2>&1"
        fi
    fi
    if ! jq --help >/dev/null 2>&1; then
        echoContent green " ---> 安装jq"
        runWithTimeout 300 "${installType} jq >/dev/null 2>&1"
    fi

    if ! command -v ld >/dev/null 2>&1; then
        echoContent green " ---> 安装binutils"
        runWithTimeout 300 "${installType} binutils >/dev/null 2>&1"
    fi

    if ! openssl help >/dev/null 2>&1; then
        echoContent green " ---> 安装openssl"
        runWithTimeout 300 "${installType} openssl >/dev/null 2>&1"
    fi

    if ! ping6 --help >/dev/null 2>&1; then
        echoContent green " ---> 安装ping6"
        runWithTimeout 300 "${installType} inetutils-ping >/dev/null 2>&1"
    fi

    if ! qrencode --help >/dev/null 2>&1; then
        echoContent green " ---> 安装qrencode"
        runWithTimeout 300 "${installType} qrencode >/dev/null 2>&1"
    fi

    if ! command -v lsb_release >/dev/null 2>&1; then
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            runWithTimeout 300 "${installType} lsb-release >/dev/null 2>&1"
        elif [[ "${release}" == "centos" ]]; then
            runWithTimeout 300 "${installType} redhat-lsb-core >/dev/null 2>&1"
        else
            runWithTimeout 300 "${installType} lsb-release >/dev/null 2>&1"
        fi
    fi

    if ! lsof -h >/dev/null 2>&1; then
        echoContent green " ---> 安装lsof"
        runWithTimeout 300 "${installType} lsof >/dev/null 2>&1"
    fi

    if ! dig -h >/dev/null 2>&1; then
        echoContent green " ---> 安装dig"
        if [[ "${packageManager}" == "apt" ]]; then
            runWithTimeout 300 "${installType} dnsutils >/dev/null 2>&1"
        elif [[ "${packageManager}" == "yum" ]]; then
            runWithTimeout 300 "${installType} bind-utils >/dev/null 2>&1"
        elif [[ "${packageManager}" == "apk" ]]; then
            runWithTimeout 300 "${installType} bind-tools >/dev/null 2>&1"
        fi
    fi

    # 检测nginx版本，并提供是否卸载的选项
    if protocolSelectionSkipsNginx "${selectCustomInstallType}"; then
        echoContent green " ---> 检测到无需依赖Nginx的服务，跳过安装"
    else
        if ! nginx >/dev/null 2>&1; then
            echoContent green " ---> 安装nginx"
            installNginxTools
        else
            nginxVersion=$(nginx -v 2>&1)
            nginxVersion=$(echo "${nginxVersion}" | awk -F "[n][g][i][n][x][/]" '{print $2}' | awk -F "[.]" '{print $2}')
            if [[ ${nginxVersion} -lt 14 ]]; then
                read -r -p "读取到当前的Nginx版本不支持gRPC，会导致安装失败，是否卸载Nginx后重新安装 ？[y/n]:" unInstallNginxStatus
                if [[ "${unInstallNginxStatus}" == "y" ]]; then
                    ${removeType} nginx >/dev/null 2>&1
                    echoContent yellow " ---> nginx卸载完成"
                    echoContent green " ---> 安装nginx"
                    installNginxTools >/dev/null 2>&1
                else
                    exit 0
                fi
            fi
        fi
    fi

    if [[ "${selectCustomInstallType}" == "7" ]]; then
        echoContent green " ---> 检测到无需依赖证书的服务，跳过安装"
    else
        if [[ ! -d "$HOME/.acme.sh" ]] || [[ -d "$HOME/.acme.sh" && -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
            echoContent green " ---> 安装acme.sh"
            local acmeInstallScript="/tmp/padm-tls/acme.sh"
            if ! curl -fsSL -o "${acmeInstallScript}" https://get.acme.sh; then
                echoContent red "  acme安装脚本下载失败--->"
                exit 1
            fi
            runWithTimeout 600 "sh \"${acmeInstallScript}\" >/etc/padm/tls/acme.log 2>&1"

            if [[ ! -d "$HOME/.acme.sh" ]] || [[ -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
                echoContent red "  acme安装失败--->"
                tail -n 100 /etc/padm/tls/acme.log
                echoContent yellow "错误排查:"
                echoContent red "  1.获取Github文件失败，请等待Github恢复后尝试，恢复进度可查看 [https://www.githubstatus.com/]"
                echoContent red "  2.acme.sh脚本出现bug，可查看[https://github.com/acmesh-official/acme.sh] issues"
                echoContent red "  3.如纯IPv6机器，请设置NAT64,可执行下方命令，如果添加下方命令还是不可用，请尝试更换其他NAT64"
                echoContent skyBlue "  sed -i \"1i\\\nameserver 2a00:1098:2b::1\\\nnameserver 2a00:1098:2c::1\\\nnameserver 2a01:4f8:c2c:123f::1\\\nnameserver 2a01:4f9:c010:3f02::1\" /etc/resolv.conf"
                exit 0
            fi
        fi
    fi

}

# 开机启动
bootStartup() {
    local serviceName=$1
    if [[ "${release}" == "alpine" ]]; then
        rc-update add "${serviceName}" default
    else
        systemctl daemon-reload
        systemctl enable "${serviceName}"
    fi
}

# 安装Nginx
installNginxTools() {

    if [[ "${release}" == "debian" ]]; then
        runWithTimeout 300 "${installType} gnupg2 ca-certificates lsb-release >/dev/null 2>&1"
        local nginxRepoCodename
        nginxRepoCodename=$(lsb_release -cs)
        if curl -fsSL "https://nginx.org/packages/mainline/debian/dists/${nginxRepoCodename}/Release" >/dev/null 2>&1; then
            curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
            echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/mainline/debian ${nginxRepoCodename} nginx" | sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
            echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx >/dev/null 2>&1
            refreshAptAfterRepoChange
        fi

    elif [[ "${release}" == "ubuntu" ]]; then
        runWithTimeout 300 "${installType} gnupg2 ca-certificates lsb-release >/dev/null 2>&1"
        local nginxRepoCodename
        nginxRepoCodename=$(lsb_release -cs)
        if curl -fsSL "https://nginx.org/packages/mainline/ubuntu/dists/${nginxRepoCodename}/Release" >/dev/null 2>&1; then
            curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
            echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/mainline/ubuntu ${nginxRepoCodename} nginx" | sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
            echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx >/dev/null 2>&1
            refreshAptAfterRepoChange
        fi

    elif [[ "${release}" == "centos" ]]; then
        runWithTimeout 300 "${installType} yum-utils >/dev/null 2>&1"
        cat <<EOF >/etc/yum.repos.d/nginx.repo
[nginx-stable]
name=nginx stable repo
baseurl=https://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=https://nginx.org/packages/mainline/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=0
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF
        sudo yum-config-manager --enable nginx-mainline >/dev/null 2>&1
    elif [[ "${release}" == "alpine" ]]; then
        rm "${nginxConfigPath}default.conf"
    fi
    runWithTimeout 300 "${installType} nginx >/dev/null 2>&1"
    bootStartup nginx
}


# 安装warp
installWarp() {
    if [[ "${cpuVendor}" == "arm" ]]; then
        echoContent red " ---> 官方WARP客户端不支持ARM架构"
        exit 0
    fi

    runWithTimeout 300 "${installType} gnupg2 >/dev/null 2>&1"
    if [[ "${release}" == "debian" ]]; then
        local warpRepoCodename
        warpRepoCodename=$(lsb_release -cs)
        if curl -fsSL "https://pkg.cloudflareclient.com/dists/${warpRepoCodename}/Release" >/dev/null 2>&1; then
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg >/dev/null
            echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${warpRepoCodename} main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list >/dev/null 2>&1
            refreshAptAfterRepoChange
        else
            echoContent red " ---> 当前Debian版本暂不支持官方WARP客户端"
            exit 0
        fi

    elif [[ "${release}" == "ubuntu" ]]; then
        local warpRepoCodename="focal"
        if curl -fsSL "https://pkg.cloudflareclient.com/dists/${warpRepoCodename}/Release" >/dev/null 2>&1; then
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg >/dev/null
            echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${warpRepoCodename} main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list >/dev/null 2>&1
            refreshAptAfterRepoChange
        else
            echoContent red " ---> 当前Ubuntu版本暂不支持官方WARP客户端"
            exit 0
        fi

    elif [[ "${release}" == "centos" ]]; then
        runWithTimeout 300 "${installType} yum-utils >/dev/null 2>&1"
        sudo rpm -ivh "https://pkg.cloudflareclient.com/cloudflare-release-el${centosVersion}.rpm" >/dev/null 2>&1
    fi

    echoContent green " ---> 安装WARP"
    runWithTimeout 300 "${installType} cloudflare-warp >/dev/null 2>&1"
    if [[ -z $(which warp-cli) ]]; then
        echoContent red " ---> 安装WARP失败"
        exit 0
    fi
    systemctl enable warp-svc
    warp-cli --accept-tos register
    warp-cli --accept-tos set-mode proxy
    warp-cli --accept-tos set-proxy-port 31303
    warp-cli --accept-tos connect
    warp-cli --accept-tos enable-always-on

    local warpStatus=
    warpStatus=$(curl -s --socks5 127.0.0.1:31303 https://www.cloudflare.com/cdn-cgi/trace | grep "warp" | cut -d "=" -f 2)

    if [[ "${warpStatus}" == "on" ]]; then
        echoContent green " ---> WARP启动成功"
    fi
}


