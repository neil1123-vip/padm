#!/usr/bin/env bash

checkCentosSELinux() {
    if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" == "Enforcing" ]; then
        echoContent yellow "# 注意事项"
        echoContent yellow "检测到SELinux已开启，请手动关闭后重新执行脚本"
        exit 0
    fi
}

checkSystem() {
    if [[ -n $(find /etc -name "redhat-release") ]] || grep </proc/version -q -i "centos"; then
        mkdir -p /etc/yum.repos.d

        if [[ -f "/etc/centos-release" ]]; then
            centosVersion=$(rpm -q centos-release | awk -F "[-]" '{print $3}' | awk -F "[.]" '{print $1}')

            if [[ -z "${centosVersion}" ]] && grep </etc/centos-release -q -i "release 8"; then
                centosVersion=8
            fi
        fi

        release="centos"
        packageManager="yum"
        installType='yum -y install'
        removeType='yum -y remove'
        upgrade="yum -y update"
        checkCentosSELinux
    elif { [[ -f "/etc/issue" ]] && grep -qi "debian" /etc/issue; } || { [[ -f "/proc/version" ]] && grep -qi "debian" /proc/version; } || { [[ -f "/etc/os-release" ]] && grep -qi "ID=debian" /etc/os-release; }; then
        release="debian"
        packageManager="apt"
        installType='DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install'
        upgrade="DEBIAN_FRONTEND=noninteractive apt-get update"
        updateReleaseInfoChange='DEBIAN_FRONTEND=noninteractive apt-get --allow-releaseinfo-change update'
        removeType='DEBIAN_FRONTEND=noninteractive apt-get -y autoremove'
    elif { [[ -f "/etc/issue" ]] && grep -qi "ubuntu" /etc/issue; } || { [[ -f "/proc/version" ]] && grep -qi "ubuntu" /proc/version; }; then
        release="ubuntu"
        packageManager="apt"
        installType='DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install'
        upgrade="DEBIAN_FRONTEND=noninteractive apt-get update"
        updateReleaseInfoChange='DEBIAN_FRONTEND=noninteractive apt-get --allow-releaseinfo-change update'
        removeType='DEBIAN_FRONTEND=noninteractive apt-get -y autoremove'
        if grep </etc/issue -q -i "16."; then
            release=
        fi
    elif { [[ -f "/etc/issue" ]] && grep -qi "alpine" /etc/issue; } || { [[ -f "/proc/version" ]] && grep -qi "alpine" /proc/version; }; then
        release="alpine"
        packageManager="apk"
        installType='apk add'
        upgrade="apk update"
        removeType='apk del'
        nginxConfigPath=/etc/nginx/http.d/
    fi

    if [[ -z ${release} ]]; then
        echoContent red "\n本脚本不支持此系统，请将下方日志反馈给开发者\n"
        echoContent yellow "$(cat /etc/issue)"
        echoContent yellow "$(cat /proc/version)"
        exit 0
    fi
}

checkCPUVendor() {
    if [[ -n $(which uname) ]]; then
        if [[ "$(uname)" == "Linux" ]]; then
            case "$(uname -m)" in
            'amd64' | 'x86_64')
                xrayCoreCPUVendor="Xray-linux-64"
                warpRegCoreCPUVendor="main-linux-amd64"
                singBoxCoreCPUVendor="-linux-amd64"
                ;;
            'armv8' | 'aarch64')
                cpuVendor="arm"
                xrayCoreCPUVendor="Xray-linux-arm64-v8a"
                warpRegCoreCPUVendor="main-linux-arm64"
                singBoxCoreCPUVendor="-linux-arm64"
                ;;
            *)
                echo "  不支持此CPU架构--->"
                exit 1
                ;;
            esac
        fi
    else
        echoContent red "  无法识别此CPU架构，默认amd64、x86_64--->"
        xrayCoreCPUVendor="Xray-linux-64"
    fi
}

initVar() {
    packageManager=
    installType='yum -y install'
    removeType='yum -y remove'
    upgrade="yum -y update"
    echoType='echo -e'
    xrayCoreCPUVendor=""
    warpRegCoreCPUVendor=""
    cpuVendor=""
    domain=
    totalProgress=1
    coreInstallType=
    ctlPath=
    currentInstallProtocolType=
    currentAlpn=
    frontingType=
    selectCustomInstallType=
    configPath=
    realityStatus=
    singBoxConfigPath=
    singBoxVLESSVisionPort=
    singBoxVLESSRealityVisionPort=
    singBoxVLESSRealityGRPCPort=
    singBoxHysteria2Port=
    singBoxTrojanPort=
    singBoxTuicPort=
    singBoxNaivePort=
    singBoxVMessWSPort=
    singBoxVLESSWSPort=
    singBoxVMessHTTPUpgradePort=
    subscribePort=
    subscribeType=
    singBoxVLESSRealityGRPCSNI=
    singBoxVLESSRealityVisionSNI=
    singBoxVLESSRealityPublicKey=
    xrayVLESSRealitySNI=
    xrayVLESSRealityPort=
    xrayVLESSRealityXHTTPSNI=
    xrayVLESSRealityXHTTPort=
    portHoppingStart=
    portHoppingEnd=
    portHopping=
    hysteria2PortHoppingStart=
    hysteria2PortHoppingEnd=
    hysteria2PortHopping=
    tuicAlgorithm=
    tuicPort=
    currentPath=
    currentHost=
    selectCoreType=
    centosVersion=
    currentUUID=
    currentClients=
    localIP=
    cronName=$1
    installTLSCount=
    btDomain=
    nginxConfigPath=/etc/nginx/conf.d/
    nginxStaticPath=/usr/share/nginx/html/
    prereleaseStatus=false
    sslType=
    cfAPIToken=
    sslEmail=
    sslRenewalDays=90
    dnsTLSDomain=
    ipType=
    customPort=
    hysteriaPort=
    hysteria2ClientDownloadSpeed=
    hysteria2ClientUploadSpeed=
    realityPrivateKey=
    realitySNI=
    realityTargetHost=
    realityTargetPort=
    realityEntryHost=
    tlsEnabled=
    tlsCertDomain=
    tlsSNI=
    tlsCertFile=
    tlsKeyFile=
    realityDestDomain=
    wgetShowProgressStatus=
    reservedWarpReg=
    publicKeyWarpReg=
    addressWarpReg=
    secretKeyWarpReg=
    lastInstallationConfig=
    realityOnlyWithDomain=
}
