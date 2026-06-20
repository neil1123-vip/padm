#!/usr/bin/env bash

checkCentosSELinux() {
    if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" == "Enforcing" ]; then
        echoContent title "\n┌─ SELinux 检测 ─────────────────────────────────────"
        menuLine "检测到 SELinux 已开启，请手动关闭后重新执行脚本"
        menuClose
        exit 0
    fi
}

checkSystem() {
    local osReleaseFile=${PADM_OS_RELEASE_FILE:-/etc/os-release}

    if [[ -f "${osReleaseFile}" ]]; then
        osReleaseId=$(awk -F= '$1 == "ID" {gsub(/"/, "", $2); print $2}' "${osReleaseFile}")
        osReleaseLike=$(awk -F= '$1 == "ID_LIKE" {gsub(/"/, "", $2); print $2}' "${osReleaseFile}")
        osVersionId=$(awk -F= '$1 == "VERSION_ID" {gsub(/"/, "", $2); print $2}' "${osReleaseFile}")
    fi

    if [[ "${osReleaseId}" == "fedora" ]]; then
        mkdir -p "${PADM_YUM_REPOS_DIR:-/etc/yum.repos.d}"
        release="fedora"
        rhelLike=true
        centosVersion=${osVersionId%%.*}
        packageManager="yum"
        installType='yum -y install'
        removeType='yum -y remove'
        upgrade="yum -y update"
        checkCentosSELinux
    elif [[ "${osReleaseId}" == "centos" || "${osReleaseId}" == "rhel" || "${osReleaseId}" == "almalinux" || "${osReleaseId}" == "rocky" || "${osReleaseId}" == "ol" || " ${osReleaseLike} " == *" rhel "* || " ${osReleaseLike} " == *" centos "* ]] || [[ -f /etc/redhat-release ]] || grep </proc/version -q -i "centos"; then
        mkdir -p "${PADM_YUM_REPOS_DIR:-/etc/yum.repos.d}"
        release="centos"
        rhelLike=true
        centosVersion=${osVersionId%%.*}

        if [[ "${osReleaseId}" == "centos" && -f "/etc/centos-release" && -z "${centosVersion}" ]]; then
            centosVersion=$(rpm -q centos-release | awk -F "[-]" '{print $3}' | awk -F "[.]" '{print $1}')

            if [[ -z "${centosVersion}" ]] && grep </etc/centos-release -q -i "release 8"; then
                centosVersion=8
            fi
        fi

        packageManager="yum"
        installType='yum -y --disablerepo=epel install'
        removeType='yum -y remove'
        upgrade="yum -y update"
        checkCentosSELinux
    elif { [[ -f "/etc/issue" ]] && grep -qi "debian" /etc/issue; } || { [[ -f "/proc/version" ]] && grep -qi "debian" /proc/version; } || { [[ -f "/etc/os-release" ]] && grep -qi "ID=debian" /etc/os-release; }; then
        release="debian"
        packageManager="apt"
        installType='DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install'
        upgrade="DEBIAN_FRONTEND=noninteractive apt-get update"
        updateReleaseInfoChange='DEBIAN_FRONTEND=noninteractive apt-get --allow-releaseinfo-change update'
        removeType='DEBIAN_FRONTEND=noninteractive apt-get -y autoremove'
    elif { [[ -f "/etc/issue" ]] && grep -qi "ubuntu" /etc/issue; } || { [[ -f "/proc/version" ]] && grep -qi "ubuntu" /proc/version; }; then
        release="ubuntu"
        packageManager="apt"
        installType='DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install'
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
        errorCard "无法识别此CPU架构，默认amd64、x86_64"
        xrayCoreCPUVendor="Xray-linux-64"
    fi
}

initVar() {
    packageManager=
    installType='yum -y --disablerepo=epel install'
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
    singBoxShadowsocksPort=
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
    tuicPortHoppingStart=
    tuicPortHoppingEnd=
    tuicPortHopping=
    tuicAlgorithm=
    tuicAuthTimeout=
    tuicHeartbeat=
    tuicZeroRttHandshake=
    tuicPort=
    currentPath=
    currentHost=
    osReleaseId=
    osReleaseLike=
    osVersionId=
    rhelLike=
    centosVersion=
    currentUUID=
    currentClients=
    localIP=
    cronName=${1:-}
    installTLSCount=
    btDomain=
    nginxConfigPath=/etc/nginx/conf.d/
    nginxStaticPath=/usr/share/nginx/html/
    prereleaseStatus=false
    sslType=
    cfAPIToken=
    cfZoneID=
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
