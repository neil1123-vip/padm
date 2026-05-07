#!/usr/bin/env bash

# 清理 Xray geo 数据文件
cleanXrayGeoFiles() {
    local targetDir=$1
    rm -f "${targetDir}/geosite.dat" "${targetDir}/geoip.dat" >/dev/null 2>&1
}

# 安装 sing-box
installSingBox() {
    readInstallType
    echoContent skyBlue "\n进度  $1/${totalProgress} : 安装sing-box"

    if [[ ! -f "/etc/padm/sing-box/sing-box" ]]; then

        version=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases?per_page=20" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        checkVersionNotEmpty "${version}"

        echoContent green " ---> 最新版本:${version}"

        if ! downloadFile -P /etc/padm/sing-box/ "https://github.com/SagerNet/sing-box/releases/download/${version}/sing-box-${version/v/}${singBoxCoreCPUVendor}.tar.gz"; then
            echoContent red " ---> sing-box下载失败"
            exit 1
        fi

        if [[ ! -f "/etc/padm/sing-box/sing-box-${version/v/}${singBoxCoreCPUVendor}.tar.gz" ]]; then
            read -r -p "核心下载失败，请重新尝试安装，是否重新尝试？[y/n]" downloadStatus
            if [[ "${downloadStatus}" == "y" ]]; then
                installSingBox "$1"
            fi
        else

            if ! tar zxvf "/etc/padm/sing-box/sing-box-${version/v/}${singBoxCoreCPUVendor}.tar.gz" -C "/etc/padm/sing-box/" >/dev/null 2>&1; then
                echoContent red " ---> sing-box解压失败"
                exit 1
            fi

            if ! mv "/etc/padm/sing-box/sing-box-${version/v/}${singBoxCoreCPUVendor}/sing-box" /etc/padm/sing-box/sing-box; then
                echoContent red " ---> sing-box安装失败"
                exit 1
            fi
            rm -rf /etc/padm/sing-box/sing-box-*
            chmod 655 /etc/padm/sing-box/sing-box
        fi
    else
        echoContent green " ---> 当前版本:v$(/etc/padm/sing-box/sing-box version | grep "sing-box version" | awk '{print $3}')"

        version=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases?per_page=20" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        echoContent green " ---> 最新版本:${version}"

        if [[ -z "${lastInstallationConfig}" ]]; then
            read -r -p "是否更新、升级？[y/n]:" reInstallSingBoxStatus
            if [[ "${reInstallSingBoxStatus}" == "y" ]]; then
                rm -f /etc/padm/sing-box/sing-box
                installSingBox "$1"
            fi
        fi
    fi

}


# 安装xray
installXray() {
    readInstallType
    local prereleaseStatus=false
    if [[ "$2" == "true" ]]; then
        prereleaseStatus=true
    fi

    echoContent skyBlue "\n进度  $1/${totalProgress} : 安装Xray"

    if [[ ! -f "/etc/padm/xray/xray" ]]; then

        version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=100" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        checkVersionNotEmpty "${version}"
        echoContent green " ---> Xray-core版本:${version}"
        if ! downloadFile -P /etc/padm/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"; then
            echoContent red " ---> Xray-core下载失败"
            exit 1
        fi

        if [[ ! -f "/etc/padm/xray/${xrayCoreCPUVendor}.zip" ]]; then
            read -r -p "核心下载失败，请重新尝试安装，是否重新尝试？[y/n]" downloadStatus
            if [[ "${downloadStatus}" == "y" ]]; then
                installXray "$1"
            fi
        else
            if ! unzip -o "/etc/padm/xray/${xrayCoreCPUVendor}.zip" -d /etc/padm/xray >/dev/null; then
                echoContent red " ---> Xray-core解压失败"
                exit 1
            fi
            rm -rf "/etc/padm/xray/${xrayCoreCPUVendor}.zip"

            version=$(curl -s https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases?per_page=1 | jq -r '.[]|.tag_name')
            checkVersionNotEmpty "${version}"
            echoContent skyBlue "------------------------Version-------------------------------"
            echo "version:${version}"
            cleanXrayGeoFiles /etc/padm/xray

            if ! downloadFile -P /etc/padm/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geosite.dat" || ! downloadFile -P /etc/padm/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geoip.dat"; then
                echoContent red " ---> geo文件下载失败"
                exit 1
            fi

            chmod 655 /etc/padm/xray/xray
        fi
    else
        if [[ -z "${lastInstallationConfig}" ]]; then
            echoContent green " ---> Xray-core版本:$(/etc/padm/xray/xray --version | awk '{print $2}' | head -1)"
            read -r -p "是否更新、升级？[y/n]:" reInstallXrayStatus
            if [[ "${reInstallXrayStatus}" == "y" ]]; then
                rm -f /etc/padm/xray/xray
                installXray "$1" "$2"
            fi
        fi
    fi
}


# xray版本管理
xrayVersionManageMenu() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : Xray版本管理"
    if [[ "${coreInstallType}" != "1" ]]; then
        echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
        exit 0
    fi
    echoContent red "\n=============================================================="
    echoContent yellow "1.升级Xray-core"
    echoContent yellow "2.升级Xray-core 预览版"
    echoContent yellow "3.回退Xray-core"
    echoContent yellow "4.关闭Xray-core"
    echoContent yellow "5.打开Xray-core"
    echoContent yellow "6.重启Xray-core"
    echoContent yellow "7.更新geosite、geoip"
    echoContent yellow "8.设置自动更新geo文件[每天凌晨更新]"
    echoContent yellow "9.查看日志"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectXrayType
    if [[ "${selectXrayType}" == "1" ]]; then
        prereleaseStatus=false
        updateXray
    elif [[ "${selectXrayType}" == "2" ]]; then
        prereleaseStatus=true
        updateXray
    elif [[ "${selectXrayType}" == "3" ]]; then
        echoContent yellow "\n1.只可以回退最近的稳定版本"
        echoContent yellow "2.不保证回退后一定可以正常使用"
        echoContent yellow "3.如果回退的版本不支持当前的config，则会无法连接，谨慎操作"
        echoContent skyBlue "------------------------Version-------------------------------"
        curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=100" | jq -r ".[]|select (.prerelease==false)|.tag_name" | awk '{print ""NR""":"$0}'
        echoContent skyBlue "--------------------------------------------------------------"
        read -r -p "请输入要回退的版本:" selectXrayVersionType
        version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=100" | jq -r ".[]|select (.prerelease==false)|.tag_name" | awk '{print ""NR""":"$0}' | grep "${selectXrayVersionType}:" | awk -F "[:]" '{print $2}')
        if [[ -n "${version}" ]]; then
            updateXray "${version}"
        else
            echoContent red "\n ---> 输入有误，请重新输入"
            xrayVersionManageMenu 1
        fi
    elif [[ "${selectXrayType}" == "4" ]]; then
        serviceQueueStop xray
        serviceQueueApply
    elif [[ "${selectXrayType}" == "5" ]]; then
        serviceQueueStart xray
        serviceQueueApply
    elif [[ "${selectXrayType}" == "6" ]]; then
        reloadCore
    elif [[ "${selectXrayType}" == "7" ]]; then
        updateGeoSite
    elif [[ "${selectXrayType}" == "8" ]]; then
        installCronUpdateGeo
    elif [[ "${selectXrayType}" == "9" ]]; then
        checkLog 1
    fi
}


# 更新 geosite
updateGeoSite() {
    echoContent yellow "\n来源 https://github.com/Loyalsoldier/v2ray-rules-dat"

    version=$(curl -s https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases?per_page=1 | jq -r '.[]|.tag_name')
    echoContent skyBlue "------------------------Version-------------------------------"
    echo "version:${version}"
    cleanXrayGeoFiles "${configPath}.."

    downloadFile -P ${configPath}../ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geosite.dat"
    downloadFile -P ${configPath}../ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geoip.dat"

    reloadCore
    echoContent green " ---> 更新完毕"

}


# 更新Xray
updateXray() {
    readInstallType

    if [[ -z "${coreInstallType}" || "${coreInstallType}" != "1" ]]; then
        if [[ -n "$1" ]]; then
            version=$1
        else
            version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=100" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        fi

        echoContent green " ---> Xray-core版本:${version}"

        if ! downloadFile -P /etc/padm/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"; then
            echoContent red " ---> Xray-core下载失败"
            exit 1
        fi

        unzip -o "/etc/padm/xray/${xrayCoreCPUVendor}.zip" -d /etc/padm/xray >/dev/null
        rm -rf "/etc/padm/xray/${xrayCoreCPUVendor}.zip"
        chmod 655 /etc/padm/xray/xray
        serviceQueueRestart xray
        serviceQueueApply
    else
        echoContent green " ---> 当前版本:v$(/etc/padm/xray/xray --version | awk '{print $2}' | head -1)"
        remoteVersion=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=100" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)

        echoContent green " ---> 最新版本:${remoteVersion}"

        if [[ -n "$1" ]]; then
            version=$1
        else
            version=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases?per_page=100" | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
        fi

        if [[ -n "$1" ]]; then
            read -r -p "回退版本为${version}，是否继续？[y/n]:" rollbackXrayStatus
            if [[ "${rollbackXrayStatus}" == "y" ]]; then
                echoContent green " ---> 当前Xray-core版本:$(/etc/padm/xray/xray --version | awk '{print $2}' | head -1)"

                handleXray stop
                rm -f /etc/padm/xray/xray
                updateXray "${version}"
            else
                echoContent green " ---> 放弃回退版本"
            fi
        elif [[ "${version}" == "v$(/etc/padm/xray/xray --version | awk '{print $2}' | head -1)" ]]; then
            read -r -p "当前版本与最新版相同，是否重新安装？[y/n]:" reInstallXrayStatus
            if [[ "${reInstallXrayStatus}" == "y" ]]; then
                handleXray stop
                rm -f /etc/padm/xray/xray
                updateXray
            else
                echoContent green " ---> 放弃重新安装"
            fi
        else
            read -r -p "最新版本为:${version}，是否更新？[y/n]:" installXrayStatus
            if [[ "${installXrayStatus}" == "y" ]]; then
                rm /etc/padm/xray/xray
                updateXray
            else
                echoContent green " ---> 放弃更新"
            fi

        fi
    fi
}


# 验证整个服务是否可用
checkGFWStatue() {
    readInstallType
    echoContent skyBlue "\n进度 $1/${totalProgress} : 验证服务启动状态"
    if [[ "${coreInstallType}" == "1" ]] && [[ -n $(pgrep -f "xray/xray") ]]; then
        echoContent green " ---> 服务启动成功"
    elif [[ "${coreInstallType}" == "2" ]] && [[ -n $(pgrep -f "sing-box/sing-box") ]]; then
        echoContent green " ---> 服务启动成功"
    else
        echoContent red " ---> 服务启动失败，请检查终端是否有日志打印"
        exit 0
    fi
}


# 安装alpine开机启动
installAlpineStartup() {
    local serviceName=$1
    if [[ "${serviceName}" == "sing-box" ]]; then
        cat <<EOF >"/etc/init.d/${serviceName}"
#!/sbin/openrc-run

description="sing-box service"
command="/etc/padm/sing-box/sing-box"
command_args="run -c /etc/padm/sing-box/conf/config.json"
command_background=true
pidfile="/var/run/sing-box.pid"
EOF
    elif [[ "${serviceName}" == "xray" ]]; then
        cat <<EOF >"/etc/init.d/${serviceName}"
#!/sbin/openrc-run

description="xray service"
command="/etc/padm/xray/xray"
command_args="run -confdir /etc/padm/xray/conf"
command_background=true
pidfile="/var/run/xray.pid"
EOF
    fi

    chmod +x "/etc/init.d/${serviceName}"
}


# sing-box开机自启
installSingBoxService() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 配置sing-box开机自启"
    execStart='/etc/padm/sing-box/sing-box run -c /etc/padm/sing-box/conf/config.json'

    if [[ -n $(find /bin /usr/bin -name "systemctl") && "${release}" != "alpine" ]]; then
        rm -rf /etc/systemd/system/sing-box.service
        touch /etc/systemd/system/sing-box.service
        cat <<EOF >/etc/systemd/system/sing-box.service
[Unit]
Description=Sing-Box Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
ExecStart=${execStart}
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10
LimitNPROC=infinity
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
        bootStartup "sing-box.service"
    elif [[ "${release}" == "alpine" ]]; then
        installAlpineStartup "sing-box"
        bootStartup "sing-box"
    fi

    echoContent green " ---> 配置sing-box开机启动完毕"
}


# Xray开机自启
installXrayService() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 配置Xray开机自启"
    execStart='/etc/padm/xray/xray run -confdir /etc/padm/xray/conf'
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]]; then
        rm -rf /etc/systemd/system/xray.service
        touch /etc/systemd/system/xray.service
        cat <<EOF >/etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target
[Service]
User=root
ExecStart=${execStart}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=infinity
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
        bootStartup "xray.service"
        echoContent green " ---> 配置Xray开机自启成功"
    elif [[ "${release}" == "alpine" ]]; then
        installAlpineStartup "xray"
        bootStartup "xray"
    fi
}


# 读取Xray用户数据并初始化
initXrayClients() {
    local type=",$1,"
    local newUUID=$2
    local newEmail=$3
    if [[ -n "${newUUID}" ]]; then
        local newUser=
        newUser="{\"id\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"email\":\"${newEmail}-VLESS_TCP/TLS_Vision\"}"
        currentClients=$(echo "${currentClients}" | jq -r ". +=[${newUser}]")
    fi
    local users=
    users=[]
    while read -r user; do
        uuid=$(echo "${user}" | jq -r .id//.uuid)
        email=$(echo "${user}" | jq -r .email//.name | awk -F "[-]" '{print $1}')
        currentUser=
        if protocolSelectionIncludes "${type}" 0; then
            currentUser="{\"id\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"email\":\"${email}-VLESS_TCP/TLS_Vision\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # VLESS WS
        if protocolSelectionIncludes "${type}" 1; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-VLESS_WS\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VLESS XHTTP
        if protocolSelectionIncludes "${type}" 12; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-VLESS_Reality_XHTTP\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # trojan grpc
        if protocolSelectionIncludes "${type}" 2; then
            currentUser="{\"password\":\"${uuid}\",\"email\":\"${email}-Trojan_gRPC\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VMess WS
        if protocolSelectionIncludes "${type}" 3; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-VMess_WS\",\"alterId\": 0}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # trojan tcp
        if protocolSelectionIncludes "${type}" 4; then
            currentUser="{\"password\":\"${uuid}\",\"email\":\"${email}-trojan_tcp\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # vless grpc
        if protocolSelectionIncludes "${type}" 5; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-vless_grpc\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # hysteria
        if protocolSelectionIncludes "${type}" 6; then
            currentUser="{\"password\":\"${uuid}\",\"name\":\"${email}-singbox_hysteria2\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # vless reality vision
        if protocolSelectionIncludes "${type}" 7; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-vless_reality_vision\",\"flow\":\"xtls-rprx-vision\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # vless reality grpc
        if protocolSelectionIncludes "${type}" 8; then
            currentUser="{\"id\":\"${uuid}\",\"email\":\"${email}-vless_reality_grpc\",\"flow\":\"\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # tuic
        if protocolSelectionIncludes "${type}" 9; then
            currentUser="{\"uuid\":\"${uuid}\",\"password\":\"${uuid}\",\"name\":\"${email}-singbox_tuic\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

    done < <(echo "${currentClients}" | jq -c '.[]')
    echo "${users}"
}

# 读取singbox用户数据并初始化
initSingBoxClients() {
    local type=",$1,"
    local newUUID=$2
    local newName=$3

    if [[ -n "${newUUID}" ]]; then
        local newUser=
        newUser="{\"uuid\":\"${newUUID}\",\"flow\":\"xtls-rprx-vision\",\"name\":\"${newName}-VLESS_TCP/TLS_Vision\"}"
        currentClients=$(echo "${currentClients}" | jq -r ". +=[${newUser}]")
    fi
    local users=
    users=[]
    while read -r user; do
        uuid=$(echo "${user}" | jq -r .uuid//.id//.password)
        name=$(echo "${user}" | jq -r .name//.email//.username | awk -F "[-]" '{print $1}')
        currentUser=
        # VLESS Vision
        if protocolSelectionIncludes "${type}" 0; then
            currentUser="{\"uuid\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"name\":\"${name}-VLESS_TCP/TLS_Vision\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VLESS WS
        if protocolSelectionIncludes "${type}" 1; then
            currentUser="{\"uuid\":\"${uuid}\",\"name\":\"${name}-VLESS_WS\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VMess ws
        if protocolSelectionIncludes "${type}" 3; then
            currentUser="{\"uuid\":\"${uuid}\",\"name\":\"${name}-VMess_WS\",\"alterId\": 0}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # trojan
        if protocolSelectionIncludes "${type}" 4; then
            currentUser="{\"password\":\"${uuid}\",\"name\":\"${name}-Trojan_TCP\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # VLESS Reality Vision
        if protocolSelectionIncludes "${type}" 7; then
            currentUser="{\"uuid\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"name\":\"${name}-VLESS_Reality_Vision\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VLESS Reality gRPC
        if protocolSelectionIncludes "${type}" 8; then
            currentUser="{\"uuid\":\"${uuid}\",\"name\":\"${name}-VLESS_Reality_gPRC\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # hysteria2
        if protocolSelectionIncludes "${type}" 6; then
            currentUser="{\"password\":\"${uuid}\",\"name\":\"${name}-singbox_hysteria2\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # tuic
        if protocolSelectionIncludes "${type}" 9; then
            currentUser="{\"uuid\":\"${uuid}\",\"password\":\"${uuid}\",\"name\":\"${name}-singbox_tuic\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        # naive
        if protocolSelectionIncludes "${type}" 10; then
            currentUser="{\"password\":\"${uuid}\",\"username\":\"${name}-singbox_naive\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # VMess HTTPUpgrade
        if protocolSelectionIncludes "${type}" 11; then
            currentUser="{\"uuid\":\"${uuid}\",\"name\":\"${name}-VMess_HTTPUpgrade\",\"alterId\": 0}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi
        # anytls
        if protocolSelectionIncludes "${type}" 13; then
            currentUser="{\"password\":\"${uuid}\",\"name\":\"${name}-anytls\"}"
            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

        if protocolSelectionIncludes "${type}" 20; then
            currentUser="{\"username\":\"${uuid}\",\"password\":\"${uuid}\"}"

            users=$(echo "${users}" | jq -r ". +=[${currentUser}]")
        fi

    done < <(echo "${currentClients}" | jq -c '.[]')
    echo "${users}"
}


# 初始化Xray 配置文件
initXrayConfig() {
    echoContent skyBlue "\n进度 $2/${totalProgress} : 初始化Xray配置"
    echo
    local uuid=
    local addClientsStatus=
    if [[ -n "${currentUUID}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "读取到上次用户配置，UUID为 [${currentUUID}]，是否复用上次安装的用户配置？[y/n]:" historyUUIDStatus
        if [[ "${historyUUIDStatus}" == "y" ]]; then
            addClientsStatus=true
            echoContent green "\n ---> 使用成功"
        fi
    elif [[ -n "${currentUUID}" && -n "${lastInstallationConfig}" ]]; then
        addClientsStatus=true
    fi

    if [[ -z "${addClientsStatus}" ]]; then
        echoContent yellow "请输入自定义UUID[需合法]，[回车]随机UUID"
        read -r -p 'UUID:' customUUID

        if [[ -n ${customUUID} ]]; then
            uuid=${customUUID}
        else
            uuid=$(/etc/padm/xray/xray uuid)
        fi

        echoContent yellow "\n请输入自定义用户名[需合法]，[回车]随机用户名"
        read -r -p '用户名:' customEmail
        if [[ -z ${customEmail} ]]; then
            customEmail="$(echo "${uuid}" | cut -d "-" -f 1)-VLESS_TCP/TLS_Vision"
        fi
    fi

    if [[ -z "${addClientsStatus}" && -z "${uuid}" ]]; then
        addClientsStatus=
        echoContent red "\n ---> uuid读取错误，随机生成"
        uuid=$(/etc/padm/xray/xray uuid)
    fi

    if [[ -n "${uuid}" ]]; then
        currentClients='[{"id":"'${uuid}'","add":"'${add}'","flow":"xtls-rprx-vision","email":"'${customEmail}'"}]'
        echoContent green "\n ${customEmail}:${uuid}"
        echo
    fi

    # log
    if [[ ! -f "/etc/padm/xray/conf/00_log.json" ]]; then

        cat <<EOF >/etc/padm/xray/conf/00_log.json
{
  "log": {
    "error": "/etc/padm/xray/error.log",
    "loglevel": "warning",
    "dnsLog": false
  }
}
EOF
    fi

    if [[ ! -f "/etc/padm/xray/conf/12_policy.json" ]]; then

        cat <<EOF >/etc/padm/xray/conf/12_policy.json
{
  "policy": {
      "levels": {
          "0": {
              "handshake": $((1 + RANDOM % 4)),
              "connIdle": $((250 + RANDOM % 51))
          }
      }
  }
}
EOF
    fi

    addXrayOutbound "z_direct_outbound"
    # dns
    if [[ ! -f "/etc/padm/xray/conf/11_dns.json" ]]; then
        cat <<EOF >/etc/padm/xray/conf/11_dns.json
{
    "dns": {
        "servers": [
          "localhost"
        ]
  }
}
EOF
    fi
    # routing
    cat <<EOF >/etc/padm/xray/conf/09_routing.json
{
  "routing": {
    "rules": [
      {
        "type": "field",
        "domain": [
          "domain:gstatic.com",
          "domain:googleapis.com",
	  "domain:googleapis.cn"
        ],
        "outboundTag": "z_direct_outbound"
      }
    ]
  }
}
EOF
    # VLESS_TCP_TLS_Vision
    # 回落nginx
    local fallbacksList='{"dest":31300,"xver":1},{"alpn":"h2","dest":31302,"xver":1}'

    # trojan
    if protocolSelectionIncludes "${selectCustomInstallType}" 4 "$1"; then
        fallbacksList='{"dest":31296,"xver":1},{"alpn":"h2","dest":31302,"xver":1}'
        cat <<EOF >/etc/padm/xray/conf/04_trojan_TCP_inbounds.json
{
"inbounds":[
	{
	  "port": 31296,
	  "listen": "127.0.0.1",
	  "protocol": "trojan",
	  "tag":"trojanTCP",
	  "settings": {
		"clients": $(initXrayClients 4),
		"fallbacks":[
			{
			    "dest":"31300",
			    "xver":1
			}
		]
	  },
	  "streamSettings": {
		"network": "tcp",
		"security": "none",
		"tcpSettings": {
			"acceptProxyProtocol": true
		}
	  }
	}
	]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/padm/xray/conf/04_trojan_TCP_inbounds.json >/dev/null 2>&1
    fi

    # VLESS_WS_TLS
    if protocolSelectionIncludes "${selectCustomInstallType}" 1 "$1"; then
        fallbacksList=${fallbacksList}',{"path":"/'${customPath}'ws","dest":31297,"xver":1}'
        cat <<EOF >/etc/padm/xray/conf/03_VLESS_WS_inbounds.json
{
"inbounds":[
    {
	  "port": 31297,
	  "listen": "127.0.0.1",
	  "protocol": "vless",
	  "tag":"VLESSWS",
	  "settings": {
		"clients": $(initXrayClients 1),
		"decryption": "none"
	  },
	  "streamSettings": {
		"network": "ws",
		"security": "none",
		"wsSettings": {
		  "acceptProxyProtocol": true,
		  "path": "/${customPath}ws"
		}
	  }
	}
]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/padm/xray/conf/03_VLESS_WS_inbounds.json >/dev/null 2>&1
    fi
    # VLESS_Reality_XHTTP_TLS
    if protocolSelectionIncludes "${selectCustomInstallType}" 12 "$1"; then
        initXrayXHTTPort
        initRealityProfile
        initRealityKey
        initRealityMldsa65
        cat <<EOF >/etc/padm/xray/conf/12_VLESS_XHTTP_inbounds.json
{
"inbounds":[
    {
	  "port": ${xHTTPort},
	  "listen": "0.0.0.0",
	  "protocol": "vless",
	  "tag":"VLESSRealityXHTTP",
	  "settings": {
		"clients": $(initXrayClients 12),
		"decryption": "none"
	  },
	  "streamSettings": {
		"network": "xhttp",
		"security": "reality",
		"realitySettings": {
            "show": false,
            "target": "${realityTargetHost}:${realityTargetPort}",
            "xver": 0,
            "serverNames": [
                "${realitySNI}"
            ],
            "privateKey": "${realityPrivateKey}",
            "publicKey": "${realityPublicKey}",
            "maxTimeDiff": 70000,
            "shortIds": [
                "",
                "6ba85179e30d4fc2"
            ]
        },
        "xhttpSettings": {
            "host": "${realitySNI}",
            "path": "/${customPath}xHTTP",
            "mode": "auto"
        }
	  }
	}
]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/padm/xray/conf/12_VLESS_XHTTP_inbounds.json >/dev/null 2>&1
    fi
    if protocolSelectionIncludes "${selectCustomInstallType}" 3 "$1"; then
        fallbacksList=${fallbacksList}',{"path":"/'${customPath}'vws","dest":31299,"xver":1}'
        cat <<EOF >/etc/padm/xray/conf/05_VMess_WS_inbounds.json
{
    "inbounds":[
        {
          "listen": "127.0.0.1",
          "port": 31299,
          "protocol": "vmess",
          "tag":"VMessWS",
          "settings": {
            "clients": $(initXrayClients 3)
          },
          "streamSettings": {
            "network": "ws",
            "security": "none",
            "wsSettings": {
              "acceptProxyProtocol": true,
              "path": "/${customPath}vws"
            }
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/padm/xray/conf/05_VMess_WS_inbounds.json >/dev/null 2>&1
    fi
    # VLESS_gRPC
    #    if echo "${selectCustomInstallType}" | grep -q ",5," || [[ "$1" == "all" ]]; then
    #        cat <<EOF >/etc/padm/xray/conf/06_VLESS_gRPC_inbounds.json
    #{
    #    "inbounds":[
    #        {
    #            "port": 31301,
    #            "listen": "127.0.0.1",
    #            "protocol": "vless",
    #            "tag":"VLESSGRPC",
    #            "settings": {
    #                "clients": $(initXrayClients 5),
    #                "decryption": "none"
    #            },
    #            "streamSettings": {
    #                "network": "grpc",
    #                "grpcSettings": {
    #                    "serviceName": "${customPath}grpc"
    #                }
    #            }
    #        }
    #    ]
    #}
    #EOF
    #    elif [[ -z "$3" ]]; then
    #        rm /etc/padm/xray/conf/06_VLESS_gRPC_inbounds.json >/dev/null 2>&1
    #    fi

    # VLESS Vision
    if protocolSelectionIncludes "${selectCustomInstallType}" 0 "$1"; then

        cat <<EOF >/etc/padm/xray/conf/02_VLESS_TCP_inbounds.json
{
    "inbounds":[
        {
          "port": ${port},
          "protocol": "vless",
          "tag":"VLESSTCP",
          "settings": {
            "clients":$(initXrayClients 0),
            "decryption": "none",
            "fallbacks": [
                ${fallbacksList}
            ]
          },
          "add": "${add}",
          "streamSettings": {
            "network": "tcp",
            "security": "tls",
            "tlsSettings": {
              "rejectUnknownSni": true,
              "minVersion": "1.2",
              "certificates": [
                {
                  "certificateFile": "/etc/padm/tls/${domain}.crt",
                  "keyFile": "/etc/padm/tls/${domain}.key",
                  "ocspStapling": 3600
                }
              ]
            }
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/padm/xray/conf/02_VLESS_TCP_inbounds.json >/dev/null 2>&1
    fi

    # VLESS_TCP/reality
    if protocolSelectionIncludes "${selectCustomInstallType}" 7 "$1"; then
        echoContent skyBlue "\n===================== 配置VLESS+Reality =====================\n"

        initXrayRealityPort
        initRealityProfile
        initRealityKey
        initRealityMldsa65
        cat <<EOF >/etc/padm/xray/conf/07_VLESS_vision_reality_inbounds.json
{
  "inbounds": [
    {
      "tag": "dokodemo-in-VLESSReality",
      "port": ${realityPort},
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1",
        "port": 45987,
        "network": "tcp"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "tls"
        ],
        "routeOnly": true
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 45987,
      "protocol": "vless",
      "settings": {
        "clients": $(initXrayClients 7),
        "decryption": "none",
        "fallbacks":[
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "${realityTargetHost}:${realityTargetPort}",
          "xver": 0,
          "serverNames": [
            "${realitySNI}"
          ],
          "privateKey": "${realityPrivateKey}",
          "publicKey": "${realityPublicKey}",
          "mldsa65Seed": "${realityMldsa65Seed}",
          "mldsa65Verify": "${realityMldsa65Verify}",
          "maxTimeDiff": 70000,
          "shortIds": [
            "",
            "6ba85179e30d4fc2"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    }
  ],
  "routing": {
    "rules": [
      {
        "inboundTag": [
          "dokodemo-in"
        ],
        "domain": [
          "${realitySNI}"
        ],
        "outboundTag": "z_direct_outbound"
      },
      {
        "inboundTag": [
          "dokodemo-in"
        ],
        "outboundTag": "blackhole_out"
      }
    ]
  }
}
EOF
        #        cat <<EOF >/etc/padm/xray/conf/08_VLESS_vision_gRPC_inbounds.json
        #{
        #  "inbounds": [
        #    {
        #      "port": 31305,
        #      "listen": "127.0.0.1",
        #      "protocol": "vless",
        #      "tag": "VLESSRealityGRPC",
        #      "settings": {
        #        "clients": $(initXrayClients 8),
        #        "decryption": "none"
        #      },
        #      "streamSettings": {
        #            "network": "grpc",
        #            "grpcSettings": {
        #                "serviceName": "grpc",
        #                "multiMode": true
        #            },
        #            "sockopt": {
        #                "acceptProxyProtocol": true
        #            }
        #      }
        #    }
        #  ]
        #}
        #EOF

    elif [[ -z "$3" ]]; then
        rm /etc/padm/xray/conf/07_VLESS_vision_reality_inbounds.json >/dev/null 2>&1
        rm /etc/padm/xray/conf/08_VLESS_vision_gRPC_inbounds.json >/dev/null 2>&1
    fi
    installSniffing
    if [[ -z "$3" ]]; then
        removeXrayOutbound wireguard_out_IPv4_route
        removeXrayOutbound wireguard_out_IPv6_route
        removeXrayOutbound wireguard_outbound
        removeXrayOutbound IPv4_out
        removeXrayOutbound IPv6_out
        removeXrayOutbound socks5_outbound
        removeXrayOutbound blackhole_out
        removeXrayOutbound wireguard_out_IPv6
        removeXrayOutbound wireguard_out_IPv4
        addXrayOutbound z_direct_outbound
        addXrayOutbound blackhole_out
    fi
}


# 初始化sing-box配置文件
initSingBoxConfig() {
    echoContent skyBlue "\n进度 $2/${totalProgress} : 初始化sing-box配置"

    echo
    local uuid=
    local addClientsStatus=
    local sslDomain=
    collectTLSProfile
    sslDomain=${tlsCertDomain}
    if [[ -n "${currentUUID}" && -z "${lastInstallationConfig}" ]]; then
        read -r -p "读取到上次用户配置，UUID为 [${currentUUID}]，是否复用上次安装的用户配置？[y/n]:" historyUUIDStatus
        if [[ "${historyUUIDStatus}" == "y" ]]; then
            addClientsStatus=true
            echoContent green "\n ---> 使用成功"
        fi
    elif [[ -n "${currentUUID}" && -n "${lastInstallationConfig}" ]]; then
        addClientsStatus=true
    fi

    if [[ -z "${addClientsStatus}" ]]; then
        echoContent yellow "请输入自定义UUID[需合法]，[回车]随机UUID"
        read -r -p 'UUID:' customUUID

        if [[ -n ${customUUID} ]]; then
            uuid=${customUUID}
        else
            uuid=$(/etc/padm/sing-box/sing-box generate uuid)
        fi

        echoContent yellow "\n请输入自定义用户名[需合法]，[回车]随机用户名"
        read -r -p '用户名:' customEmail
        if [[ -z ${customEmail} ]]; then
            customEmail="$(echo "${uuid}" | cut -d "-" -f 1)-VLESS_TCP/TLS_Vision"
        fi
    fi

    if [[ -z "${addClientsStatus}" && -z "${uuid}" ]]; then
        addClientsStatus=
        echoContent red "\n ---> uuid读取错误，随机生成"
        uuid=$(/etc/padm/sing-box/sing-box generate uuid)
    fi

    if [[ -n "${uuid}" ]]; then
        currentClients='[{"uuid":"'${uuid}'","flow":"xtls-rprx-vision","name":"'${customEmail}'"}]'
        echoContent yellow "\n ${customEmail}:${uuid}"
    fi

    # VLESS Vision
    if protocolSelectionIncludes "${selectCustomInstallType}" 0 "$1"; then
        echoContent yellow "\n===================== 配置VLESS+Vision =====================\n"
        echoContent skyBlue "\n开始配置VLESS+Vision协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVLESSVisionPort}")
        echoContent green "\n ---> VLESS_Vision端口：${result[-1]}"

        checkDNSIP "${domain}"
        removeNginxDefaultConf
        handleSingBox stop

        checkPortOpen "${result[-1]}" "${domain}"
        cat <<EOF >/etc/padm/sing-box/conf/config/02_VLESS_TCP_inbounds.json
{
    "inbounds":[
        {
          "type": "vless",
          "listen":"::",
          "listen_port":${result[-1]},
          "tag":"VLESSTCP",
          "users":$(initSingBoxClients 0),
          "tls":{
            "server_name": "${sslDomain}",
            "enabled": true,
            "certificate_path": "/etc/padm/tls/${sslDomain}.crt",
            "key_path": "/etc/padm/tls/${sslDomain}.key"
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/padm/sing-box/conf/config/02_VLESS_TCP_inbounds.json >/dev/null 2>&1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 1 "$1"; then
        echoContent yellow "\n===================== 配置VLESS+WS =====================\n"
        echoContent skyBlue "\n开始配置VLESS+WS协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVLESSWSPort}")
        echoContent green "\n ---> VLESS_WS端口：${result[-1]}"

        checkDNSIP "${domain}"
        removeNginxDefaultConf
        handleSingBox stop
        randomPathFunction
        checkPortOpen "${result[-1]}" "${domain}"
        cat <<EOF >/etc/padm/sing-box/conf/config/03_VLESS_WS_inbounds.json
{
    "inbounds":[
        {
          "type": "vless",
          "listen":"::",
          "listen_port":${result[-1]},
          "tag":"VLESSWS",
          "users":$(initSingBoxClients 1),
          "tls":{
            "server_name": "${sslDomain}",
            "enabled": true,
            "certificate_path": "/etc/padm/tls/${sslDomain}.crt",
            "key_path": "/etc/padm/tls/${sslDomain}.key"
          },
          "transport": {
            "type": "ws",
            "path": "/${currentPath}ws",
            "max_early_data": 2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/padm/sing-box/conf/config/03_VLESS_WS_inbounds.json >/dev/null 2>&1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 3 "$1"; then
        echoContent yellow "\n===================== 配置VMess+ws =====================\n"
        echoContent skyBlue "\n开始配置VMess+ws协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVMessWSPort}")
        echoContent green "\n ---> VMess_ws端口：${result[-1]}"

        checkDNSIP "${domain}"
        removeNginxDefaultConf
        handleSingBox stop
        randomPathFunction
        checkPortOpen "${result[-1]}" "${domain}"
        cat <<EOF >/etc/padm/sing-box/conf/config/05_VMess_WS_inbounds.json
{
    "inbounds":[
        {
          "type": "vmess",
          "listen":"::",
          "listen_port":${result[-1]},
          "tag":"VMessWS",
          "users":$(initSingBoxClients 3),
          "tls":{
            "server_name": "${sslDomain}",
            "enabled": true,
            "certificate_path": "/etc/padm/tls/${sslDomain}.crt",
            "key_path": "/etc/padm/tls/${sslDomain}.key"
          },
          "transport": {
            "type": "ws",
            "path": "/${currentPath}",
            "max_early_data": 2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/padm/sing-box/conf/config/05_VMess_WS_inbounds.json >/dev/null 2>&1
    fi

    # VLESS_Reality_Vision
    if protocolSelectionIncludes "${selectCustomInstallType}" 7 "$1"; then
        echoContent yellow "\n================= 配置VLESS+Reality+Vision =================\n"
        initRealityProfile
        initRealityKey
        echoContent skyBlue "\n开始配置VLESS+Reality+Vision协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVLESSRealityVisionPort}")
        echoContent green "\n ---> VLESS_Reality_Vision端口：${result[-1]}"
        cat <<EOF >/etc/padm/sing-box/conf/config/07_VLESS_vision_reality_inbounds.json
{
  "inbounds": [
    {
      "type": "vless",
      "listen":"::",
      "listen_port":${result[-1]},
      "tag": "VLESSReality",
      "users":$(initSingBoxClients 7),
      "tls": {
        "enabled": true,
        "server_name": "${realitySNI}",
        "reality": {
            "enabled": true,
            "handshake":{
                "server": "${realityTargetHost}",
                "server_port":${realityTargetPort}
            },
            "private_key": "${realityPrivateKey}",
            "short_id": [
                "",
                "6ba85179e30d4fc2"
            ]
        }
      }
    }
  ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/padm/sing-box/conf/config/07_VLESS_vision_reality_inbounds.json >/dev/null 2>&1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 8 "$1"; then
        echoContent yellow "\n================== 配置VLESS+Reality+gRPC ==================\n"
        initRealityProfile
        initRealityKey
        echoContent skyBlue "\n开始配置VLESS+Reality+gRPC协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVLESSRealityGRPCPort}")
        echoContent green "\n ---> VLESS_Reality_gPRC端口：${result[-1]}"
        cat <<EOF >/etc/padm/sing-box/conf/config/08_VLESS_vision_gRPC_inbounds.json
{
  "inbounds": [
    {
      "type": "vless",
      "listen":"::",
      "listen_port":${result[-1]},
      "users":$(initSingBoxClients 8),
      "tag": "VLESSRealityGRPC",
      "tls": {
        "enabled": true,
        "server_name": "${realitySNI}",
        "reality": {
            "enabled": true,
            "handshake":{
                "server":"${realityTargetHost}",
                "server_port":${realityTargetPort}
            },
            "private_key": "${realityPrivateKey}",
            "short_id": [
                "",
                "6ba85179e30d4fc2"
            ]
        }
      },
      "transport": {
          "type": "grpc",
          "service_name": "grpc"
      }
    }
  ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/padm/sing-box/conf/config/08_VLESS_vision_gRPC_inbounds.json >/dev/null 2>&1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 6 "$1"; then
        echoContent yellow "\n================== 配置 Hysteria2 ==================\n"
        echoContent skyBlue "\n开始配置Hysteria2协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxHysteria2Port}")
        echoContent green "\n ---> Hysteria2端口：${result[-1]}"
        initHysteria2Network
        cat <<EOF >/etc/padm/sing-box/conf/config/06_hysteria2_inbounds.json
{
    "inbounds": [
        {
            "type": "hysteria2",
            "listen": "::",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 6),
            "up_mbps":${hysteria2ClientDownloadSpeed},
            "down_mbps":${hysteria2ClientUploadSpeed},
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "alpn": [
                    "h3"
                ],
                "certificate_path": "/etc/padm/tls/${sslDomain}.crt",
                "key_path": "/etc/padm/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/padm/sing-box/conf/config/06_hysteria2_inbounds.json >/dev/null 2>&1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 4 "$1"; then
        echoContent yellow "\n================== 配置 Trojan ==================\n"
        echoContent skyBlue "\n开始配置Trojan协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxTrojanPort}")
        echoContent green "\n ---> Trojan端口：${result[-1]}"
        cat <<EOF >/etc/padm/sing-box/conf/config/04_trojan_TCP_inbounds.json
{
    "inbounds": [
        {
            "type": "trojan",
            "listen": "::",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 4),
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "certificate_path": "/etc/padm/tls/${sslDomain}.crt",
                "key_path": "/etc/padm/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/padm/sing-box/conf/config/04_trojan_TCP_inbounds.json >/dev/null 2>&1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 9 "$1"; then
        echoContent yellow "\n==================== 配置 Tuic =====================\n"
        echoContent skyBlue "\n开始配置Tuic协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxTuicPort}")
        echoContent green "\n ---> Tuic端口：${result[-1]}"
        initTuicProtocol
        cat <<EOF >/etc/padm/sing-box/conf/config/09_tuic_inbounds.json
{
     "inbounds": [
        {
            "type": "tuic",
            "listen": "::",
            "tag": "singbox-tuic-in",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 9),
            "congestion_control": "${tuicAlgorithm}",
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "alpn": [
                    "h3"
                ],
                "certificate_path": "/etc/padm/tls/${sslDomain}.crt",
                "key_path": "/etc/padm/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/padm/sing-box/conf/config/09_tuic_inbounds.json >/dev/null 2>&1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 10 "$1"; then
        echoContent yellow "\n==================== 配置 Naive =====================\n"
        echoContent skyBlue "\n开始配置Naive协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxNaivePort}")
        echoContent green "\n ---> Naive端口：${result[-1]}"
        cat <<EOF >/etc/padm/sing-box/conf/config/10_naive_inbounds.json
{
     "inbounds": [
        {
            "type": "naive",
            "listen": "::",
            "tag": "singbox-naive-in",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 10),
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "certificate_path": "/etc/padm/tls/${sslDomain}.crt",
                "key_path": "/etc/padm/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/padm/sing-box/conf/config/10_naive_inbounds.json >/dev/null 2>&1
    fi
    if protocolSelectionIncludes "${selectCustomInstallType}" 11 "$1"; then
        echoContent yellow "\n===================== 配置VMess+HTTPUpgrade =====================\n"
        echoContent skyBlue "\n开始配置VMess+HTTPUpgrade协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxVMessHTTPUpgradePort}")
        echoContent green "\n ---> VMess_HTTPUpgrade端口：${result[-1]}"

        checkDNSIP "${domain}"
        removeNginxDefaultConf
        handleSingBox stop
        randomPathFunction
        rm -rf "${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf" >/dev/null 2>&1
        checkPortOpen "${result[-1]}" "${domain}"
        singBoxNginxConfig "$1" "${result[-1]}"
        bootStartup nginx
        cat <<EOF >/etc/padm/sing-box/conf/config/11_VMess_HTTPUpgrade_inbounds.json
{
    "inbounds":[
        {
          "type": "vmess",
          "listen":"127.0.0.1",
          "listen_port":31306,
          "tag":"VMessHTTPUpgrade",
          "users":$(initSingBoxClients 11),
          "transport": {
            "type": "httpupgrade",
            "path": "/${currentPath}"
          }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/padm/sing-box/conf/config/11_VMess_HTTPUpgrade_inbounds.json >/dev/null 2>&1
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 13 "$1"; then
        echoContent yellow "\n================== 配置 AnyTLS ==================\n"
        echoContent skyBlue "\n开始配置AnyTLS协议端口"
        echo
        mapfile -t result < <(initSingBoxPort "${singBoxAnyTLSPort}")
        echoContent green "\n ---> AnyTLS端口：${result[-1]}"
        cat <<EOF >/etc/padm/sing-box/conf/config/13_anytls_inbounds.json
{
    "inbounds": [
        {
            "type": "anytls",
            "listen": "::",
            "tag":"anytls",
            "listen_port": ${result[-1]},
            "users": $(initSingBoxClients 13),
            "tls": {
                "enabled": true,
                "server_name":"${sslDomain}",
                "certificate_path": "/etc/padm/tls/${sslDomain}.crt",
                "key_path": "/etc/padm/tls/${sslDomain}.key"
            }
        }
    ]
}
EOF
    elif [[ -z "$3" ]]; then
        rm /etc/padm/sing-box/conf/config/13_anytls_inbounds.json >/dev/null 2>&1
    fi

    if [[ -z "$3" ]]; then
        removeSingBoxConfig wireguard_endpoints_IPv4_route
        removeSingBoxConfig wireguard_endpoints_IPv6_route
        removeSingBoxConfig wireguard_endpoints_IPv4
        removeSingBoxConfig wireguard_endpoints_IPv6

        removeSingBoxConfig IPv4_out
        removeSingBoxConfig IPv6_out
        removeSingBoxConfig IPv6_route
        removeSingBoxConfig block
        removeSingBoxConfig cn_block_outbound
        removeSingBoxConfig cn_block_route
        removeSingBoxConfig 01_direct_outbound
        removeSingBoxConfig socks5_outbound.json
        removeSingBoxConfig block_domain_outbound
        removeSingBoxConfig dns
    fi

    setSniffRouting
}

# 一键无域名Xray-core Reality
installXrayReality() {
    selectCustomInstallType=",7,"
    readLastInstallationConfig
    unInstallSubscribe
    totalProgress=6
    installTools 1

    handleNginx stop

    # 安装Xray
    installXray 2 false
    installXrayService 3
    initXrayConfig custom 4
    cleanUp singBoxDel

    serviceQueueRestart xray
    serviceQueueApply
    # 生成账号
    checkGFWStatue 5
    showAccounts 6
}

# 一键无域名sing-box Reality
installSingBoxReality() {

    selectCustomInstallType=",7,"
    readLastInstallationConfig
    unInstallSubscribe
    totalProgress=6
    installTools 1

    installSingBox 2
    installSingBoxService 3
    initSingBoxConfig custom 4
    cleanUp xrayDel
    serviceQueueRestart sing-box
    serviceQueueApply
    # 生成账号
    checkGFWStatue 5
    showAccounts 6
}

# Xray-core个性化安装
customXrayInstall() {
    echoContent skyBlue "\n========================个性化安装============================"
    echoContent yellow "选择说明：可输入单个编号，也可用英文逗号多选，例如 0,1,7"
    echoContent yellow "推荐新人：7 = VLESS Reality Vision，有域名也优先选择；12 = VLESS Reality XHTTP，推荐 CDN 场景使用"
    echoContent yellow "传统 TLS/WS/gRPC/HTTPUpgrade 协议存在更高识别风险，仅在明确客户端兼容或迁移需要时选择"
    echoContent yellow "Xray 会自动补齐 0 作为前置 TLS 协议，除非只安装无域名 Reality"
    protocolRegistryMenu ",0,1,3,4,7,12,"
    autoRead protocols "请选择[多选]，[例如:0,1,7]:" selectCustomInstallType
    echoContent skyBlue "--------------------------------------------------------------"
    if echo "${selectCustomInstallType}" | grep -q "，"; then
        echoContent red " ---> 请使用英文逗号分隔"
        exit 0
    fi
    if [[ "${selectCustomInstallType}" != "12" ]] && ((${#selectCustomInstallType} >= 2)) && ! echo "${selectCustomInstallType}" | grep -q ","; then
        echoContent red " ---> 多选请使用英文逗号分隔"
        exit 0
    fi
    if protocolSelectionOnlyRealityNoDomain "${selectCustomInstallType}"; then
        if [[ "${selectCustomInstallType}" == "7" ]]; then
            echoContent yellow "请选择Reality安装方式"
            echoContent yellow "1.无域名Reality - 客户端入口使用服务器 IP 或 --entry-host，不申请 TLS 证书"
            echoContent yellow "2.域名Reality - 客户端入口使用自有域名，同时仍需单独填写 Reality 伪装目标"
            echoContent yellow "说明：入口 entry 是客户端连接地址；target/SNI 是 REALITY 伪装目标，不要把两者混淆"
            autoRead reality_domain "请选择[默认1]:" realityOnlyInstallType
            if [[ "${realityOnlyInstallType}" == "2" ]]; then
                realityOnlyWithDomain=true
            elif [[ -n "${realityOnlyInstallType}" && "${realityOnlyInstallType}" != "1" ]]; then
                echoContent red " ---> 选择错误"
                customXrayInstall
                return
            fi
        fi
        selectCustomInstallType=",${selectCustomInstallType},"
    else
        if ! protocolSelectionHasAny "${selectCustomInstallType}" 0; then
            selectCustomInstallType=",0,${selectCustomInstallType},"
        else
            selectCustomInstallType=",${selectCustomInstallType},"
        fi
    fi
    if [[ "${selectCustomInstallType:0:1}" != "," ]]; then
        selectCustomInstallType=",${selectCustomInstallType},"
    fi
    if [[ "${selectCustomInstallType//,/}" =~ ^[0-9]+$ ]] && protocolSelectionIdsValid "${selectCustomInstallType}" ",0,1,3,4,7,12,"; then
        readLastInstallationConfig
        unInstallSubscribe
        # checkBTPanel
        # check1Panel
        totalProgress=12
        installTools 1
        if [[ -n "${btDomain}" ]]; then
            echoContent skyBlue "\n ---> 检测到宝塔面板/1Panel，跳过申请TLS步骤"
            handleXray stop
            if [[ "${selectCustomInstallType}" != ",7," || -n "${realityOnlyWithDomain}" ]]; then
                customPortFunction
            fi
        else
            # 申请tls
            if ! protocolSelectionOnlyRealityNoDomain "${selectCustomInstallType}" || [[ -n "${realityOnlyWithDomain}" ]]; then
                initTLSNginxConfig 2
                installTLS 3
            else
                echoContent skyBlue "\n ---> 检测到仅安装无域名Reality，跳过TLS证书步骤"
            fi
        fi

        if protocolSelectionNeedsPath "${selectCustomInstallType}"; then
            randomPathFunction 4
        fi
        if [[ -n "${btDomain}" ]]; then
            echoContent skyBlue "\n ---> 检测到宝塔面板/1Panel，跳过伪装网站"
        else
            nginxBlog 6
        fi
        if ! protocolSelectionOnlyRealityNoDomain "${selectCustomInstallType}" || [[ -n "${realityOnlyWithDomain}" ]]; then
            updateRedirectNginxConf
            handleNginx start
        fi

        # 安装Xray
        installXray 7 false
        installXrayService 8
        initXrayConfig custom 9
        cleanUp singBoxDel
        if ! protocolSelectionOnlyRealityNoDomain "${selectCustomInstallType}" || [[ -n "${realityOnlyWithDomain}" ]]; then
            installCronTLS 10
        fi

        serviceQueueRestart xray
        serviceQueueApply
        # 生成账号
        checkGFWStatue 11
        showAccounts 12
    else
        echoContent red " ---> 输入不合法"
        customXrayInstall
    fi
}


# sing-box 个性化安装
customSingBoxInstall() {
    echoContent skyBlue "\n========================个性化安装============================"
    echoContent yellow "选择说明：可输入单个编号，也可用英文逗号多选，例如 0,6,7"
    echoContent yellow "推荐新人：7 = VLESS Reality Vision；需要 CDN 时优先使用 Xray 的 12.VLESS Reality XHTTP"
    echoContent yellow "8 = VLESS Reality gRPC，适合需要 gRPC/HTTP2 多路复用但不走 CDN 的场景"
    echoContent yellow "传统 TLS 类协议存在更高识别风险；sing-box 下只有明确需要 Hysteria2、Tuic、Naive 或 AnyTLS 时再选对应协议"
    protocolRegistryMenu ",0,1,3,4,6,7,8,9,10,11,13,"

    autoRead protocols "请选择[多选]，[例如:0,6,7]:" selectCustomInstallType
    echoContent skyBlue "--------------------------------------------------------------"
    if echo "${selectCustomInstallType}" | grep -q "，"; then
        echoContent red " ---> 请使用英文逗号分隔"
        exit 0
    fi
    if [[ "${selectCustomInstallType}" != "10" ]] && [[ "${selectCustomInstallType}" != "11" ]] && [[ "${selectCustomInstallType}" != "13" ]] && ((${#selectCustomInstallType} >= 2)) && ! echo "${selectCustomInstallType}" | grep -q ","; then
        echoContent red " ---> 多选请使用英文逗号分隔"
        exit 0
    fi
    if [[ "${selectCustomInstallType: -1}" != "," ]]; then
        selectCustomInstallType="${selectCustomInstallType},"
    fi
    if [[ "${selectCustomInstallType:0:1}" != "," ]]; then
        selectCustomInstallType=",${selectCustomInstallType},"
    fi

    if [[ "${selectCustomInstallType//,/}" =~ ^[0-9]+$ ]] && protocolSelectionIdsValid "${selectCustomInstallType}" ",0,1,3,4,6,7,8,9,10,11,13,"; then
        readLastInstallationConfig
        unInstallSubscribe
        totalProgress=9
        installTools 1
        # 申请tls
        if protocolSelectionNeedsTLS "${selectCustomInstallType}"; then
            initTLSNginxConfig 2
            installTLS 3
            handleNginx stop
        fi

        installSingBox 4
        installSingBoxService 5
        initSingBoxConfig custom 6
        cleanUp xrayDel
        installCronTLS 7
        serviceQueueRestart sing-box
        serviceQueueRestart nginx
        serviceQueueApply
        # 生成账号
        checkGFWStatue 8
        showAccounts 9
    else
        echoContent red " ---> 输入不合法"
        customSingBoxInstall
    fi
}


# 选择核心安装sing-box、xray-core
selectCoreInstall() {
    echoContent skyBlue "\n功能 1/${totalProgress} : 选择核心安装"
    echoContent red "\n=============================================================="
    echoContent yellow "1.Xray-core - 推荐新人优先选择，Reality Vision 与 Reality XHTTP 场景验证最多"
    echoContent yellow "2.sing-box - 适合需要 Hysteria2、Tuic、Naive、AnyTLS 或统一 sing-box 配置的场景"
    echoContent red "=============================================================="
    autoRead core "请选择:" selectCoreType
    case ${selectCoreType} in
    1)
        if [[ "${selectInstallType}" == "1" ]]; then
            xrayCoreInstall
        elif [[ "${selectInstallType}" == "2" ]]; then
            customXrayInstall
        elif [[ "${selectInstallType}" == "3" ]]; then
            installXrayReality
        fi
        ;;
    2)
        if [[ "${selectInstallType}" == "1" ]]; then
            singBoxInstall
        elif [[ "${selectInstallType}" == "2" ]]; then
            customSingBoxInstall
        elif [[ "${selectInstallType}" == "3" ]]; then
            installSingBoxReality
        fi
        ;;
    *)
        echoContent red ' ---> 选择错误，重新选择'
        selectCoreInstall
        ;;
    esac
}


# xray-core 安装
xrayCoreInstall() {
    readLastInstallationConfig
    unInstallSubscribe
    # checkBTPanel
    # check1Panel
    selectCustomInstallType=
    totalProgress=12
    installTools 2
    if [[ -n "${btDomain}" ]]; then
        echoContent skyBlue "\n ---> 检测到宝塔面板/1Panel，跳过申请TLS步骤"
        handleXray stop
        customPortFunction
    else
        # 申请tls
        initTLSNginxConfig 3
        installTLS 4
    fi

    randomPathFunction 5

    # 安装Xray
    installXray 6 false
    installXrayService 7
    initXrayConfig all 8
    cleanUp singBoxDel
    installCronTLS 9
    if [[ -n "${btDomain}" ]]; then
        echoContent skyBlue "\n ---> 检测到宝塔面板/1Panel，跳过伪装网站"
    else
        nginxBlog 10
    fi
    updateRedirectNginxConf
    handleXray stop
    sleep 2
    handleXray start

    handleNginx start
    # 生成账号
    checkGFWStatue 11
    showAccounts 12
}


# sing-box 全部安装
singBoxInstall() {
    readLastInstallationConfig
    unInstallSubscribe
    # checkBTPanel
    # check1Panel
    selectCustomInstallType=
    totalProgress=8
    installTools 2

    if [[ -n "${btDomain}" ]]; then
        echoContent skyBlue "\n ---> 检测到宝塔面板/1Panel，跳过申请TLS步骤"
        handleXray stop
        customPortFunction
    else
        # 申请tls
        initTLSNginxConfig 3
        installTLS 4
    fi

    handleNginx stop

    installSingBox 5
    installSingBoxService 6
    initSingBoxConfig all 7

    cleanUp xrayDel
    installCronTLS 8

    serviceQueueRestart sing-box
    serviceQueueStart nginx
    serviceQueueApply
    # 生成账号
    showAccounts 9
}


# 核心管理
coreVersionManageMenu() {

    if [[ -z "${coreInstallType}" ]]; then
        echoContent red "\n ---> 没有检测到安装目录，请执行脚本安装内容"
        menu
        exit 0
    fi
    echoContent skyBlue "\n┌─ core 管理 ────────────────────────────────────────"
    menuItem 1 "Xray-core" "管理 Xray-core 版本"
    menuItem 2 "sing-box" "管理 sing-box 版本与服务"
    menuClose
    read -r -p "请输入:" selectCore

    if [[ "${selectCore}" == "1" ]]; then
        xrayVersionManageMenu 1
    elif [[ "${selectCore}" == "2" ]]; then
        singBoxVersionManageMenu 1
    fi
}

# sing-box 版本管理
singBoxVersionManageMenu() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : sing-box 版本管理"
    if [[ -z "${singBoxConfigPath}" ]]; then
        echoContent red " ---> 没有检测到安装程序，请执行脚本安装内容"
        menu
        exit 0
    fi
    echoContent skyBlue "\n┌─ sing-box 版本管理 ────────────────────────────────"
    menuItem 1 "升级 sing-box" "下载并安装最新版本"
    menuItem 2 "关闭 sing-box" "停止 sing-box 服务"
    menuItem 3 "打开 sing-box" "启动 sing-box 服务"
    menuItem 4 "重启 sing-box" "重启 sing-box 服务"
    local logStatus=
    if [[ -n "${singBoxConfigPath}" && -f "${singBoxConfigPath}log.json" && "$(jq -r .log.disabled "${singBoxConfigPath}log.json")" == "false" ]]; then
        menuItem 5 "关闭日志" "停止写入 sing-box debug 日志"
        logStatus=true
    else
        menuItem 5 "启用日志" "开启 sing-box debug 日志"
        logStatus=false
    fi

    menuItem 6 "查看日志" "tail -f 查看 sing-box 日志"
    menuClose

    read -r -p "请选择:" selectSingBoxType
    if [[ ! -f "${singBoxConfigPath}../box.log" ]]; then
        touch "${singBoxConfigPath}../box.log" >/dev/null 2>&1
    fi
    if [[ "${selectSingBoxType}" == "1" ]]; then
        installSingBox 1
        serviceQueueRestart sing-box
        serviceQueueApply
    elif [[ "${selectSingBoxType}" == "2" ]]; then
        serviceQueueStop sing-box
        serviceQueueApply
    elif [[ "${selectSingBoxType}" == "3" ]]; then
        serviceQueueStart sing-box
        serviceQueueApply
    elif [[ "${selectSingBoxType}" == "4" ]]; then
        serviceQueueRestart sing-box
        serviceQueueApply
    elif [[ "${selectSingBoxType}" == "5" ]]; then
        singBoxLog ${logStatus}
        if [[ "${logStatus}" == "false" ]]; then
            tail -f "${singBoxConfigPath}../box.log"
        fi
    elif [[ "${selectSingBoxType}" == "6" ]]; then
        tail -f "${singBoxConfigPath}../box.log"
    fi
}


# sing-box log日志
singBoxLog() {
    cat <<EOF >/etc/padm/sing-box/conf/config/log.json
{
  "log": {
    "disabled": $1,
    "level": "debug",
    "output": "/etc/padm/sing-box/conf/box.log",
    "timestamp": true
  }
}
EOF

    serviceQueueRestart sing-box
    serviceQueueApply
}

