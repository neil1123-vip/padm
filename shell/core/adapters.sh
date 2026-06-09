#!/usr/bin/env bash

refreshAptAfterRepoChange() {
    if [[ "${release}" != "ubuntu" && "${release}" != "debian" ]]; then
        return
    fi
    waitAptProcess || return 1
    runWithTimeout 300 "${upgrade} >/dev/null 2>&1"
}

commitRepoFile() {
    local tmpFile=$1
    local targetFile=$2
    local mode=${3:-644}

    if [[ ! -s "${tmpFile}" ]]; then
        padmRemoveCleanupPath "${tmpFile}"
        return 1
    fi

    chmod "${mode}" "${tmpFile}" && mv "${tmpFile}" "${targetFile}" && padmForgetCleanupPath "${tmpFile}"
}

packageInstalled() {
    local packageName=$1

    case "${packageManager}" in
    apt)
        dpkg -s "${packageName}" >/dev/null 2>&1
        ;;
    yum)
        rpm -q "${packageName}" >/dev/null 2>&1
        ;;
    apk)
        apk info -e "${packageName}" >/dev/null 2>&1
        ;;
    *)
        return 1
        ;;
    esac
}

writeMissingPackages() {
    local tmpFile=$1
    local packageName

    shift
    for packageName in "$@"; do
        if ! packageInstalled "${packageName}"; then
            printf '%s\n' "${packageName}" >>"${tmpFile}"
        fi
    done
}

trackInstalledPackagesFromFile() {
    local tmpFile=$1
    local packageName

    [[ -f "${tmpFile}" ]] || return 0
    while IFS= read -r packageName; do
        [[ -n "${packageName}" ]] || continue
        if packageInstalled "${packageName}"; then
            PADM_INSTALLED_PACKAGES="${PADM_INSTALLED_PACKAGES:-} ${packageName}"
        fi
    done <"${tmpFile}"
    padmRemoveCleanupPath "${tmpFile}"
}

beginPackageInstallTransaction() {
    if [[ "${PADM_PACKAGE_TRANSACTION_ACTIVE:-}" == "true" ]]; then
        PADM_PACKAGE_TRANSACTION_STARTED=false
        return 0
    fi

    PADM_PACKAGE_TRANSACTION_ACTIVE=true
    PADM_PACKAGE_TRANSACTION_STARTED=true
    PADM_INSTALLED_PACKAGES=
    PADM_PACKAGE_ROLLBACK_FAILURES=
}

endPackageInstallTransaction() {
    if [[ "$1" == "true" ]]; then
        PADM_INSTALLED_PACKAGES=
        PADM_PACKAGE_ROLLBACK_FAILURES=
        PADM_PACKAGE_TRANSACTION_ACTIVE=
    fi
}

rollbackPackageInstallTransaction() {
    local packageName
    local failedPackages=()
    local rc=0
    PADM_PACKAGE_ROLLBACK_FAILURES=

    if [[ -z "${PADM_INSTALLED_PACKAGES:-}" ]]; then
        return 0
    fi

    for packageName in ${PADM_INSTALLED_PACKAGES}; do
        if ! ${removeType} "${packageName}" >/dev/null 2>&1; then
            failedPackages+=("${packageName}")
            rc=1
        fi
    done
    PADM_INSTALLED_PACKAGES=
    PADM_PACKAGE_ROLLBACK_FAILURES="${failedPackages[*]}"
    return "${rc}"
}

failPackageInstallTransaction() {
    local rollbackStatus=0
    rollbackPackageInstallTransaction || rollbackStatus=$?
    if [[ "${rollbackStatus}" -eq 0 ]]; then
        errorCard "$1，已尝试回滚本次新增软件包"
    else
        errorCard "$1，回滚部分软件包失败" "请手动检查：${PADM_PACKAGE_ROLLBACK_FAILURES}"
    fi
    exit 1
}

nextInstallProgressTitle() {
    local title=$1
    if [[ -n "${PADM_INSTALL_STEP_TOTAL:-}" ]]; then
        PADM_INSTALL_STEP_INDEX=$((PADM_INSTALL_STEP_INDEX + 1))
        if [[ ${PADM_INSTALL_STEP_INDEX} -gt ${PADM_INSTALL_STEP_TOTAL} ]]; then
            PADM_INSTALL_STEP_TOTAL=${PADM_INSTALL_STEP_INDEX}
        fi
        PADM_INSTALL_PROGRESS_TITLE=$(printf '工具依赖 %d/%d：%s' "${PADM_INSTALL_STEP_INDEX}" "${PADM_INSTALL_STEP_TOTAL}" "${title}")
    else
        PADM_INSTALL_PROGRESS_TITLE="${title}"
    fi
}

printInstallProgressLine() {
    printf '\r\033[K%s\n' "$1"
}

countInstallStep() {
    PADM_INSTALL_STEP_TOTAL=$((PADM_INSTALL_STEP_TOTAL + 1))
}

initInstallProgress() {
    PADM_INSTALL_STEP_INDEX=0
    PADM_INSTALL_STEP_TOTAL=0

    local missingBaseTools=false
    [[ "${rhelLike:-}" != "true" ]] && countInstallStep
    ! command -v sudo >/dev/null 2>&1 && missingBaseTools=true
    ! command -v wget >/dev/null 2>&1 && missingBaseTools=true
    ! command -v curl >/dev/null 2>&1 && missingBaseTools=true
    ! command -v unzip >/dev/null 2>&1 && missingBaseTools=true
    ! command -v socat >/dev/null 2>&1 && missingBaseTools=true
    ! command -v tar >/dev/null 2>&1 && missingBaseTools=true
    ! command -v crontab >/dev/null 2>&1 && missingBaseTools=true
    ! command -v jq >/dev/null 2>&1 && missingBaseTools=true
    ! command -v ld >/dev/null 2>&1 && missingBaseTools=true
    ! command -v openssl >/dev/null 2>&1 && missingBaseTools=true
    if ! command -v ping6 >/dev/null 2>&1 && ! command -v ping >/dev/null 2>&1; then
        missingBaseTools=true
    fi
    if ! command -v lsb_release >/dev/null 2>&1 && [[ "${release}" != "centos" ]]; then
        missingBaseTools=true
    fi
    ! command -v lsof >/dev/null 2>&1 && missingBaseTools=true
    ! command -v dig >/dev/null 2>&1 && missingBaseTools=true
    ! command -v iptables-save >/dev/null 2>&1 && missingBaseTools=true
    [[ "${missingBaseTools}" == "true" ]] && countInstallStep
    if ! protocolSelectionSkipsNginx "${selectCustomInstallType}"; then
        if ! nginx >/dev/null 2>&1; then
            if [[ "${packageManager}" == "apt" || "${packageManager}" == "yum" ]]; then
                countInstallStep
            fi
            countInstallStep
        else
            local nginxMinorVersion
            nginxMinorVersion=$(nginx -v 2>&1 | awk -F "[n][g][i][n][x][/]" '{print $2}' | awk -F "[.]" '{print $2}')
            [[ ${nginxMinorVersion:-0} -lt 14 ]] && countInstallStep
        fi
    fi
}

runPackageCommandWithProgress() {
    local title=$1
    local timeoutSeconds=$2
    local commandString=$3
    local logFile=$4
    local progressFile="${logFile}.progress"
    local progressTitle
    local lastLogLine=
    local staleLogCount=0
    local currentLogLine=
    local status=0

    nextInstallProgressTitle "${title}"
    progressTitle=${PADM_INSTALL_PROGRESS_TITLE}
    printInstallProgressLine "${progressTitle} 正在执行；完整日志：${logFile}"
    rm -f "${progressFile}"
    if command -v timeout >/dev/null 2>&1; then
        if command -v setsid >/dev/null 2>&1; then
            timeout "${timeoutSeconds}s" setsid bash -lc "${commandString}" </dev/null >"${progressFile}" 2>&1 &
        else
            timeout "${timeoutSeconds}s" bash -lc "${commandString}" </dev/null >"${progressFile}" 2>&1 &
        fi
    elif command -v setsid >/dev/null 2>&1; then
        setsid bash -lc "${commandString}" </dev/null >"${progressFile}" 2>&1 &
    else
        bash -lc "${commandString}" </dev/null >"${progressFile}" 2>&1 &
    fi
    local commandPid=$!
    local elapsed=0
    while kill -0 "${commandPid}" >/dev/null 2>&1; do
        sleep 1
        elapsed=$((elapsed + 1))
        [[ $((elapsed % 10)) -eq 0 ]] || continue
        if [[ -s "${progressFile}" ]]; then
            currentLogLine=$(tail -n 1 "${progressFile}")
            if [[ "${currentLogLine}" == "${lastLogLine}" ]]; then
                staleLogCount=$((staleLogCount + 1))
            else
                staleLogCount=0
                lastLogLine=${currentLogLine}
            fi
            if [[ ${staleLogCount} -ge 6 ]]; then
                printInstallProgressLine "${progressTitle} 已执行 ${elapsed}s；日志 60s 未变化，可能卡住：${currentLogLine}"
            else
                printInstallProgressLine "${progressTitle} 已执行 ${elapsed}s；最新日志：${currentLogLine}"
            fi
        elif [[ ${elapsed} -ge 120 ]]; then
            printInstallProgressLine "${progressTitle} 已执行 ${elapsed}s；最新日志：暂无输出，请查看 ${logFile} 或检查 apt/yum 锁和软件源网络"
        else
            printInstallProgressLine "${progressTitle} 已执行 ${elapsed}s；最新日志：暂无输出"
        fi
    done

    wait "${commandPid}"
    status=$?
    cat "${progressFile}" >>"${logFile}"
    if [[ ${status} -eq 124 ]]; then
        if [[ -s "${progressFile}" ]]; then
            printInstallProgressLine "${progressTitle} 超时退出；最后日志：$(tail -n 1 "${progressFile}")"
        else
            printInstallProgressLine "${progressTitle} 超时退出；未产生安装日志"
        fi
    fi
    rm -f "${progressFile}"
    return ${status}
}

allPackagesInstalled() {
    local packageName

    for packageName in "$@"; do
        packageInstalled "${packageName}" || return 1
    done
    return 0
}

recoverAptInstallAfterTimeout() {
    local displayName=$1
    shift

    [[ "${packageManager}" == "apt" ]] || return 1
    allPackagesInstalled "$@" || return 1

    statusCard "${displayName}安装收尾" "软件包已安装，apt/dpkg 收尾阶段可能卡住，正在尝试恢复"
    pkill -TERM -x mandb >/dev/null 2>&1 || true
    runWithTimeout 120 "DEBIAN_FRONTEND=noninteractive dpkg --configure -a >/etc/padm/install.log.dpkg-recover 2>&1" || {
        statusCard "${displayName}安装收尾" "dpkg 收尾失败，日志：/etc/padm/install.log.dpkg-recover"
        return 1
    }
    statusCard "${displayName}安装收尾" "dpkg 收尾完成，继续后续流程"
    return 0
}

diagnosePackageInstallFailure() {
    if [[ "${packageManager}" != "apt" ]]; then
        return 0
    fi

    statusCard "软件包安装排障" \
        "可查看日志：/etc/padm/install.log" \
        "可检查锁：lsof /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock" \
        "可检查未完成配置：dpkg --audit" \
        "若卡在 man-db trigger：ps -ef | grep '[m]andb\\|[d]pkg\\|[a]pt'"
}

installPackageTracked() {
    local displayName=$1
    shift
    local packages=("$@")
    local missingPackagesFile

    local packageTimeout=300

    padmCreateTempPath missingPackagesFile /tmp/padm-packages.XXXXXX || failPackageInstallTransaction "${displayName}安装状态记录失败"
    writeMissingPackages "${missingPackagesFile}" "${packages[@]}"
    [[ "${packageManager}" == "apt" && -s "${missingPackagesFile}" ]] && packageTimeout=900

    runPackageCommandWithProgress "安装${displayName}" "${packageTimeout}" "${installType} ${packages[*]}" /etc/padm/install.log || {
        if recoverAptInstallAfterTimeout "${displayName}" "${packages[@]}"; then
            :
        else
            padmRemoveCleanupPath "${missingPackagesFile}"
            diagnosePackageInstallFailure
            failPackageInstallTransaction "${displayName}安装失败"
        fi
    }
    trackInstalledPackagesFromFile "${missingPackagesFile}"
}

installOptionalPackageTracked() {
    local displayName=$1
    shift
    local packages=("$@")
    local missingPackagesFile

    local packageTimeout=300

    padmCreateTempPath missingPackagesFile /tmp/padm-packages.XXXXXX || return 1
    writeMissingPackages "${missingPackagesFile}" "${packages[@]}"
    [[ "${packageManager}" == "apt" && -s "${missingPackagesFile}" ]] && packageTimeout=900

    if ! runPackageCommandWithProgress "安装${displayName}" "${packageTimeout}" "${installType} ${packages[*]}" /etc/padm/install.log; then
        recoverAptInstallAfterTimeout "${displayName}" "${packages[@]}" || {
            padmRemoveCleanupPath "${missingPackagesFile}"
            diagnosePackageInstallFailure
            return 1
        }
    fi
    trackInstalledPackagesFromFile "${missingPackagesFile}"
}

installBasePackages() {
    local packages=()
    local displayName="基础工具"

    ! command -v sudo >/dev/null 2>&1 && packages+=(sudo)
    ! command -v wget >/dev/null 2>&1 && packages+=(wget)
    ! command -v curl >/dev/null 2>&1 && packages+=(curl)
    ! command -v unzip >/dev/null 2>&1 && packages+=(unzip)
    ! command -v socat >/dev/null 2>&1 && packages+=(socat)
    ! command -v tar >/dev/null 2>&1 && packages+=(tar)
    if ! command -v crontab >/dev/null 2>&1; then
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            packages+=(cron)
        else
            packages+=(crontabs)
        fi
    fi
    ! command -v jq >/dev/null 2>&1 && packages+=(jq)
    ! command -v ld >/dev/null 2>&1 && packages+=(binutils)
    ! command -v openssl >/dev/null 2>&1 && packages+=(openssl)
    if ! command -v ping6 >/dev/null 2>&1 && ! command -v ping >/dev/null 2>&1; then
        if [[ "${release}" == "centos" ]]; then
            packages+=(iputils)
        else
            packages+=(inetutils-ping)
        fi
    fi
    if ! command -v lsb_release >/dev/null 2>&1; then
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" || "${release}" != "centos" ]]; then
            packages+=(lsb-release)
        fi
    fi
    ! command -v lsof >/dev/null 2>&1 && packages+=(lsof)
    if ! command -v dig >/dev/null 2>&1; then
        if [[ "${packageManager}" == "apt" ]]; then
            packages+=(dnsutils)
        elif [[ "${packageManager}" == "yum" ]]; then
            packages+=(bind-utils)
        elif [[ "${packageManager}" == "apk" ]]; then
            packages+=(bind-tools)
        fi
    fi
    if ! command -v iptables-save >/dev/null 2>&1; then
        if [[ "${packageManager}" == "apt" ]]; then
            packages+=(iptables)
        elif [[ "${packageManager}" == "yum" ]]; then
            packages+=(iptables)
            [[ "${centosVersion:-}" != "10" ]] && packages+=(iptables-legacy)
        elif [[ "${packageManager}" == "apk" ]]; then
            packages+=(iptables)
        fi
    fi

    [[ ${#packages[@]} -eq 0 ]] && return 0
    installPackageTracked "${displayName}" "${packages[@]}"
}

# 安装工具包
installTools() {
    progressCard "$1" "安装工具"
    beginPackageInstallTransaction
    local packageTransactionOwner=${PADM_PACKAGE_TRANSACTION_STARTED}
    # 修复 apt/dpkg 中断状态
    if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
        runWithTimeout 120 "dpkg --configure -a"
    fi

    waitAptProcess || failPackageInstallTransaction "等待 apt/dpkg 锁释放失败"

    initInstallProgress
    successCard "检查、安装工具依赖【新机器会很慢，请根据工具依赖进度判断是否仍在执行】"

    local installLog=${PADM_INSTALL_LOG:-/etc/padm/install.log}
    mkdir -p "${installLog%/*}"
    : >"${installLog}"
    if [[ "${rhelLike:-}" == "true" ]]; then
        statusCard "系统更新" "RHEL-like/Fedora 基础安装跳过全量系统更新，仅安装所需依赖"
    else
        runPackageCommandWithProgress "检查、安装更新" 600 "${upgrade}" "${installLog}" || {
            diagnosePackageInstallFailure
            failPackageInstallTransaction "系统软件源刷新失败"
        }
    fi

    if grep <"${installLog}" -q "changed"; then
        runWithTimeout 300 "${updateReleaseInfoChange} >/dev/null 2>&1" || {
            diagnosePackageInstallFailure
            failPackageInstallTransaction "系统软件源 release 信息刷新失败"
        }
    fi

    if [[ "${rhelLike:-}" == "true" ]]; then
        statusCard "EPEL 仓库" "基础安装不启用 EPEL，避免第三方仓库元数据超时影响安装"
    fi

    installBasePackages

    if ! command -v qrencode >/dev/null 2>&1; then
        if [[ "${packageManager}" == "yum" ]]; then
            statusCard "安装qrencode" "默认仓库未提供 qrencode，跳过本地二维码输出"
        else
            successCard "安装qrencode"
            if ! installOptionalPackageTracked "qrencode" qrencode; then
                warnCard "qrencode 安装失败，跳过本地二维码输出；不影响节点安装和订阅链接"
            fi
        fi
    fi

    # 检查 Nginx 版本并确认是否重装
    if protocolSelectionSkipsNginx "${selectCustomInstallType}"; then
        successCard "检测到无需依赖Nginx的服务，跳过安装"
    else
        if ! nginx >/dev/null 2>&1; then
            successCard "安装nginx"
            installNginxTools
        else
            nginxVersion=$(nginx -v 2>&1)
            nginxVersion=$(echo "${nginxVersion}" | awk -F "[n][g][i][n][x][/]" '{print $2}' | awk -F "[.]" '{print $2}')
            if [[ ${nginxVersion} -lt 14 ]]; then
                autoRead nginx_grpc_reinstall "读取到当前的Nginx版本不支持gRPC，会导致安装失败，是否卸载Nginx后重新安装？[y/n]:" unInstallNginxStatus
                if [[ "${unInstallNginxStatus}" == "y" ]]; then
                    if ! ${removeType} nginx >/dev/null 2>&1; then
                        failPackageInstallTransaction "旧版Nginx卸载失败"
                    fi
                    statusCard "Nginx 状态" "nginx 卸载完成"
                    successCard "安装nginx"
                    installNginxTools || failPackageInstallTransaction "Nginx重装失败"
                else
                    exit 0
                fi
            fi
        fi
    fi

    if ! protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"; then
        successCard "检测到无需依赖本机 TLS 证书的服务，跳过安装 acme.sh"
    else
        if [[ ! -d "$HOME/.acme.sh" ]] || [[ -d "$HOME/.acme.sh" && -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
            successCard "安装acme.sh"
            local acmeInstallScript="/tmp/padm-tls/acme.sh"
            local acmeDownloadScript
            padmCreateTempPath acmeDownloadScript /tmp/padm-tls/acme.sh.download.XXXXXX || failPackageInstallTransaction "acme安装脚本临时文件创建失败"
            if curl -fsSL -o "${acmeDownloadScript}" https://get.acme.sh && [[ -s "${acmeDownloadScript}" ]]; then
                mv "${acmeDownloadScript}" "${acmeInstallScript}"
                padmForgetCleanupPath "${acmeDownloadScript}"
            else
                padmRemoveCleanupPath "${acmeDownloadScript}"
                failPackageInstallTransaction "acme安装脚本下载失败"
            fi
            runWithTimeout 600 "sh \"${acmeInstallScript}\" >/etc/padm/tls/acme.log 2>&1" || failPackageInstallTransaction "acme.sh安装失败"

            if [[ ! -d "$HOME/.acme.sh" ]] || [[ -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
                echoContent title "\n┌─ acme.sh 安装失败 ─────────────────────────────────"
                menuLine "安装日志：/etc/padm/tls/acme.log"
                menuClose
                tail -n 100 /etc/padm/tls/acme.log
                echoContent title "\n┌─ acme.sh 安装排障 ─────────────────────────────────"
                menuLine "获取 GitHub 文件失败时，请等待 GitHub 恢复后重试：https://www.githubstatus.com/"
                menuLine "acme.sh 脚本异常时，可查看 https://github.com/acmesh-official/acme.sh/issues"
                menuLine "纯 IPv6 机器请设置 NAT64；如仍不可用，请尝试更换其他 NAT64"
                menuLine "可尝试写入 NAT64 DNS："
                menuLine "sed -i \"1i\\nameserver 2a00:1098:2b::1\\nnameserver 2a00:1098:2c::1\\nnameserver 2a01:4f8:c2c:123f::1\\nnameserver 2a01:4f9:c010:3f02::1\" /etc/resolv.conf"
                menuClose
                rollbackPackageInstallTransaction
                exit 0
            fi
        fi
    fi

    endPackageInstallTransaction "${packageTransactionOwner}"
}

# 开机启动
bootStartup() {
    local serviceName=$1
    if [[ "${release}" == "alpine" ]]; then
        rc-update add "${serviceName}" default
    else
        systemctl daemon-reload && systemctl enable "${serviceName}"
    fi
}

# 安装 Nginx
installNginxTools() {
    beginPackageInstallTransaction
    local packageTransactionOwner=${PADM_PACKAGE_TRANSACTION_STARTED}

    if [[ "${release}" == "debian" ]]; then
        installPackageTracked "Nginx依赖" gnupg2 ca-certificates lsb-release
        local nginxRepoCodename
        nginxRepoCodename=$(lsb_release -cs)
        if curl -fsSL "https://nginx.org/packages/mainline/debian/dists/${nginxRepoCodename}/Release" >/dev/null 2>&1; then
            curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
            local repoFile
            padmCreateTempPath repoFile /tmp/padm-nginx-repo.XXXXXX || failPackageInstallTransaction "Nginx apt 源临时文件创建失败"
            printf 'deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/mainline/debian %s nginx\n' "${nginxRepoCodename}" >"${repoFile}"
            commitRepoFile "${repoFile}" /etc/apt/sources.list.d/nginx.list || failPackageInstallTransaction "Nginx apt 源提交失败"
            local pinFile
            padmCreateTempPath pinFile /tmp/padm-nginx-pin.XXXXXX || failPackageInstallTransaction "Nginx apt pin 临时文件创建失败"
            printf 'Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n\n' >"${pinFile}"
            commitRepoFile "${pinFile}" /etc/apt/preferences.d/99nginx || failPackageInstallTransaction "Nginx apt pin 配置提交失败"
            refreshAptAfterRepoChange || failPackageInstallTransaction "Nginx apt 源刷新失败"
        fi

    elif [[ "${release}" == "ubuntu" ]]; then
        installPackageTracked "Nginx依赖" gnupg2 ca-certificates lsb-release
        local nginxRepoCodename
        nginxRepoCodename=$(lsb_release -cs)
        if curl -fsSL "https://nginx.org/packages/mainline/ubuntu/dists/${nginxRepoCodename}/Release" >/dev/null 2>&1; then
            curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
            local repoFile
            padmCreateTempPath repoFile /tmp/padm-nginx-repo.XXXXXX || failPackageInstallTransaction "Nginx apt 源临时文件创建失败"
            printf 'deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/mainline/ubuntu %s nginx\n' "${nginxRepoCodename}" >"${repoFile}"
            commitRepoFile "${repoFile}" /etc/apt/sources.list.d/nginx.list || failPackageInstallTransaction "Nginx apt 源提交失败"
            local pinFile
            padmCreateTempPath pinFile /tmp/padm-nginx-pin.XXXXXX || failPackageInstallTransaction "Nginx apt pin 临时文件创建失败"
            printf 'Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n\n' >"${pinFile}"
            commitRepoFile "${pinFile}" /etc/apt/preferences.d/99nginx || failPackageInstallTransaction "Nginx apt pin 配置提交失败"
            refreshAptAfterRepoChange || failPackageInstallTransaction "Nginx apt 源刷新失败"
        fi

    elif [[ "${release}" == "centos" ]]; then
        installPackageTracked "yum-utils" yum-utils
        local repoFile
        padmCreateTempPath repoFile /tmp/padm-nginx-yum-repo.XXXXXX || failPackageInstallTransaction "Nginx yum 源临时文件创建失败"
        cat <<EOF >"${repoFile}"
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
        commitRepoFile "${repoFile}" /etc/yum.repos.d/nginx.repo || failPackageInstallTransaction "Nginx yum 源提交失败"
        sudo yum-config-manager --enable nginx-mainline >/dev/null 2>&1
    elif [[ "${release}" == "fedora" ]]; then
        statusCard "Nginx 源" "nginx.org 未提供 Fedora ${centosVersion} 仓库，使用系统默认仓库安装 Nginx"
    elif [[ "${release}" == "alpine" ]]; then
        rm "${nginxConfigPath}default.conf"
    fi
    installPackageTracked "nginx" nginx
    if nginxServiceInstalled; then
        bootStartup nginx || failPackageInstallTransaction "Nginx开机自启配置失败"
    else
        statusCard "Nginx 开机自启" "未发现 nginx systemd unit，跳过开机自启配置"
    fi
    endPackageInstallTransaction "${packageTransactionOwner}"
}


warpCliHelpContains() {
    warp-cli --help 2>/dev/null | grep -q -- "$1"
}

warpRegister() {
    if warpCliHelpContains 'registration'; then
        warp-cli --accept-tos registration new
    else
        warp-cli --accept-tos register
    fi
}

warpSetProxyMode() {
    if warp-cli mode --help 2>/dev/null | grep -q 'proxy'; then
        warp-cli --accept-tos mode proxy
    else
        warp-cli --accept-tos set-mode proxy
    fi
}

warpSetProxyPort() {
    if warpCliHelpContains 'proxy'; then
        warp-cli --accept-tos proxy port 31303
    else
        warp-cli --accept-tos set-proxy-port 31303
    fi
}

warpEnableAlwaysOn() {
    if warpCliHelpContains 'enable-always-on'; then
        warp-cli --accept-tos enable-always-on
    fi
}

warpRollbackProxy() {
    if warpCliHelpContains 'disable-always-on'; then
        warp-cli --accept-tos disable-always-on >/dev/null 2>&1 || true
    fi
    warp-cli --accept-tos disconnect >/dev/null 2>&1 || true
    systemctl disable --now warp-svc >/dev/null 2>&1 || true
}

enableWarpProxy() {
    if ! systemctl enable warp-svc || ! systemctl start warp-svc; then
        errorCard "WARP 服务启用失败"
        return 1
    fi
    if ! warpRegister; then
        systemctl disable --now warp-svc >/dev/null 2>&1 || true
        errorCard "WARP 注册失败，已尝试禁用服务"
        return 1
    fi
    if ! warpSetProxyMode || ! warpSetProxyPort || ! warp-cli --accept-tos connect || ! warpEnableAlwaysOn; then
        warpRollbackProxy
        errorCard "WARP 代理启用失败，已尝试断开连接并禁用服务"
        return 1
    fi
}

checkWarpProxyTrace() {
    local attempt
    local warpStatus

    for attempt in 1 2 3 4 5 6; do
        warpStatus=$(curl -s --socks5 127.0.0.1:31303 --connect-timeout 5 --max-time 15 https://www.cloudflare.com/cdn-cgi/trace | grep "warp" | cut -d "=" -f 2)
        if [[ "${warpStatus}" == "on" ]]; then
            return 0
        fi
        sleep 5
    done
    return 1
}

# 安装 WARP
installWarp() {
    if [[ "${cpuVendor}" == "arm" ]]; then
        errorCard "官方WARP客户端不支持ARM架构"
        exit 0
    fi

    beginPackageInstallTransaction
    local packageTransactionOwner=${PADM_PACKAGE_TRANSACTION_STARTED}

    installPackageTracked "gnupg2" gnupg2
    if [[ "${release}" == "debian" ]]; then
        local warpRepoCodename
        warpRepoCodename=$(lsb_release -cs)
        if curl -fsSL "https://pkg.cloudflareclient.com/dists/${warpRepoCodename}/Release" >/dev/null 2>&1; then
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg >/dev/null
            local repoFile
            padmCreateTempPath repoFile /tmp/padm-warp-repo.XXXXXX || failPackageInstallTransaction "WARP apt 源临时文件创建失败"
            printf 'deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ %s main\n' "${warpRepoCodename}" >"${repoFile}"
            commitRepoFile "${repoFile}" /etc/apt/sources.list.d/cloudflare-client.list || failPackageInstallTransaction "WARP apt 源提交失败"
            refreshAptAfterRepoChange || failPackageInstallTransaction "WARP apt 源刷新失败"
        else
            errorCard "当前Debian版本暂不支持官方WARP客户端"
            endPackageInstallTransaction "${packageTransactionOwner}"
            exit 0
        fi

    elif [[ "${release}" == "ubuntu" ]]; then
        local warpRepoCodename="focal"
        if curl -fsSL "https://pkg.cloudflareclient.com/dists/${warpRepoCodename}/Release" >/dev/null 2>&1; then
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg >/dev/null
            local repoFile
            padmCreateTempPath repoFile /tmp/padm-warp-repo.XXXXXX || failPackageInstallTransaction "WARP apt 源临时文件创建失败"
            printf 'deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ %s main\n' "${warpRepoCodename}" >"${repoFile}"
            commitRepoFile "${repoFile}" /etc/apt/sources.list.d/cloudflare-client.list || failPackageInstallTransaction "WARP apt 源提交失败"
            refreshAptAfterRepoChange || failPackageInstallTransaction "WARP apt 源刷新失败"
        else
            errorCard "当前Ubuntu版本暂不支持官方WARP客户端"
            endPackageInstallTransaction "${packageTransactionOwner}"
            exit 0
        fi

    elif [[ "${release}" == "centos" || "${release}" == "fedora" ]]; then
        installPackageTracked "yum-utils" yum-utils
        local repoFile
        padmCreateTempPath repoFile /tmp/padm-warp-yum-repo.XXXXXX || failPackageInstallTransaction "WARP yum 源临时文件创建失败"
        cat <<EOF >"${repoFile}"
[cloudflare-warp]
name=Cloudflare WARP
baseurl=https://pkg.cloudflareclient.com/rpm
enabled=1
gpgcheck=1
gpgkey=https://pkg.cloudflareclient.com/pubkey.gpg
EOF
        commitRepoFile "${repoFile}" /etc/yum.repos.d/cloudflare-client.repo || failPackageInstallTransaction "WARP yum 源提交失败"
    fi

    installPackageTracked "cloudflare-warp" cloudflare-warp
    if [[ -z $(which warp-cli) ]]; then
        failPackageInstallTransaction "安装WARP失败"
    fi
    if ! enableWarpProxy; then
        failPackageInstallTransaction "WARP代理启用失败"
    fi

    if checkWarpProxyTrace; then
        successCard "WARP启动成功"
        endPackageInstallTransaction "${packageTransactionOwner}"
    else
        warpRollbackProxy
        failPackageInstallTransaction "WARP 连通性检测失败"
    fi
}
