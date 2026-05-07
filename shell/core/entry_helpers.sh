#!/usr/bin/env bash

# 初始化 Nginx 证书验证配置
initTLSNginxConfig() {
    handleNginx stop
    progressCard "$1" "初始化 Nginx 证书验证配置"
    if [[ -n "${currentHost}" && -z "${lastInstallationConfig}" ]]; then
        echo
        autoRead reuse_last "读取到上次安装记录，域名为 [${currentHost}]，是否使用？[y/n]:" historyDomainStatus
        if [[ "${historyDomainStatus}" == "y" ]]; then
            domain=${currentHost}
            statusCard "域名" "${domain}"
        else
            echo
            statusCard "域名输入" "请输入要配置的域名，例：www.example.com"
            autoRead domain "域名:" domain
        fi
    elif [[ -n "${currentHost}" && -n "${lastInstallationConfig}" ]]; then
        domain=${currentHost}
    else
        echo
        statusCard "域名输入" "请输入要配置的域名，例：www.example.com"
        autoRead domain "域名:" domain
    fi

    if [[ -z ${domain} ]]; then
        errorCard "域名不可为空"
        initTLSNginxConfig 3
    else
        dnsTLSDomain=$(echo "${domain}" | awk -F "." '{$1="";print $0}' | sed 's/^[[:space:]]*//' | sed 's/ /./g')
        if [[ "${selectCoreType}" == "1" ]]; then
            customPortFunction
        fi
        # 修改配置
        handleNginx stop
    fi
}

# sing-box Nginx 配置
writeSingBoxVMessHTTPUpgradeNginxConfig() {
    local targetPath="${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf"
    local tmpPath="${targetPath}.tmp"
    mkdir -p "$(dirname "${targetPath}")"
    cat >"${tmpPath}"
    if command -v nginx >/dev/null 2>&1; then
        local backupPath="${targetPath}.bak"
        [[ -f "${targetPath}" ]] && cp "${targetPath}" "${backupPath}"
        cat "${tmpPath}" >>"${targetPath}"
        rm -f "${tmpPath}"
        if ! nginx -t >/tmp/padm-sing-box-vmess-httpupgrade-nginx-test.log 2>&1; then
            if [[ -f "${backupPath}" ]]; then
                mv "${backupPath}" "${targetPath}"
            else
                rm -f "${targetPath}"
            fi
            return 1
        fi
        rm -f "${backupPath}"
    else
        cat "${tmpPath}" >>"${targetPath}"
        rm -f "${tmpPath}"
    fi
}

singBoxNginxConfig() {
    local type=$1
    local port=$2

    local nginxH2Conf=
    nginxH2Conf="listen ${port} http2 so_keepalive=on ssl;"
    nginxVersion=$(nginx -v 2>&1)

    local singBoxNginxSSL=
    singBoxNginxSSL="ssl_certificate /etc/padm/tls/${domain}.crt;ssl_certificate_key /etc/padm/tls/${domain}.key;"

    if echo "${nginxVersion}" | grep -q "1.25" && [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $3}') -gt 0 ]] || [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $2}') -gt 25 ]]; then
        nginxH2Conf="listen ${port} so_keepalive=on ssl;http2 on;"
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 11 "$1"; then
        writeSingBoxVMessHTTPUpgradeNginxConfig <<EOF || return 1
server {
	${nginxH2Conf}

	server_name ${domain};
	root ${nginxStaticPath};
    ${singBoxNginxSSL}

    ssl_protocols              TLSv1.2 TLSv1.3;
    ssl_ciphers                TLS13_AES_128_GCM_SHA256:TLS13_AES_256_GCM_SHA384:TLS13_CHACHA20_POLY1305_SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers  on;

    resolver                   1.1.1.1 valid=60s;
    resolver_timeout           2s;
    client_max_body_size 100m;

    location /${currentPath} {
        if (\$http_upgrade != "websocket") {
            return 444;
        }

        proxy_pass                          http://127.0.0.1:31306;
        proxy_http_version                  1.1;
        proxy_set_header Upgrade            \$http_upgrade;
        proxy_set_header Connection         "upgrade";
        proxy_set_header X-Real-IP          \$remote_addr;
        proxy_set_header X-Forwarded-For    \$proxy_add_x_forwarded_for;
        proxy_set_header Host               \$host;
        proxy_redirect                      off;
	}
}
EOF
    fi
}

# 自定义端口
customPortFunction() {
    local historyCustomPortStatus=
    if [[ -n "${customPort}" || -n "${currentPort}" ]]; then
        echo
        if [[ -z "${lastInstallationConfig}" ]]; then
            autoRead reuse_last "读取到上次安装时的本机 TLS 入口端口 [${currentPort}]，用于传统 TLS 协议或域名 Reality 入口，是否使用？[y/n]:" historyCustomPortStatus
            if [[ "${historyCustomPortStatus}" == "y" ]]; then
                port=${currentPort}
                statusCard "TLS 入口端口" "${port}"
            fi
        elif [[ -n "${lastInstallationConfig}" ]]; then
            port=${currentPort}
        fi
    fi
    if [[ -z "${currentPort}" ]] || [[ "${historyCustomPortStatus}" == "n" ]]; then
        echo

        if [[ -n "${btDomain}" ]]; then
            echoContent yellow "请输入端口[不可与BT Panel/1Panel端口相同，回车随机]"
            autoRead port "端口:" port
            if [[ -z "${port}" ]]; then
                port=$((RANDOM % 20001 + 10000))
            fi
        else
            echo
            echoContent yellow "请输入本机 TLS 入口端口[默认: 443]，用于传统 TLS 协议或域名 Reality 入口，[回车使用默认]"
            autoRead port "端口:" port
            if [[ -z "${port}" ]]; then
                port=443
            fi
            if [[ "${port}" == "${xrayVLESSRealityPort}" ]]; then
                handleXray stop
            fi
        fi

        if [[ -n "${port}" ]]; then
            if ((port >= 1 && port <= 65535)); then
                allowPort "${port}"
                statusCard "TLS 入口端口" "${port}"
                if [[ -z "${btDomain}" ]]; then
                    checkDNSIP "${domain}"
                    removeNginxDefaultConf
                    checkPortOpen "${port}" "${domain}"
                fi
            else
                errorCard "端口输入错误"
                exit 0
            fi
        else
            errorCard "端口不可为空"
            exit 0
        fi
    fi
}

# 自定义/随机路径
randomPathFunction() {
    if [[ -n $1 ]]; then
        progressCard "$1" "配置协议路径"
    else
        echoContent title "配置协议路径"
    fi

    if [[ -n "${currentPath}" ]]; then
        customPath=${currentPath}
        successCard "已复用上次安装的path路径"
    else
        initRandomPath
        currentPath=${customPath}
        successCard "已自动生成随机path路径"
    fi

    echoContent yellow "\n path:${currentPath}"
    menuClose
}
# 随机渲染传统 TLS fallback 静态站点变量
renderNginxStaticTemplate() {
    local titleOptions=("Northstar Studio" "Blue Harbor" "Evergreen Notes" "Stonebridge Labs" "Silverline Works" "Morning Grid" "Quiet Pixel" "Clearpath Systems" "Open Field" "Urban Archive")
    local eyebrowOptions=("Welcome" "Studio" "Notes" "Services" "Updates" "Portfolio" "Workspace" "Journal" "Overview" "Status")
    local headlineOptions=(
        "A lightweight page for everyday visitors"
        "Simple updates from a small digital workspace"
        "Clean static content with a modern responsive layout"
        "Practical notes, services, and project highlights"
        "A quiet homepage for useful information"
        "Focused work, clear pages, and fast loading"
        "Local-first content for a straightforward website"
        "A small public page with no external dependencies"
        "Useful links, brief notes, and current updates"
        "A calm landing page for regular web traffic"
    )
    local bodyOptions=(
        "This page is intentionally simple, fast, and fully static. It is suitable for traditional TLS fallback scenarios where a normal website response is expected."
        "The site uses local HTML and CSS only, with a responsive layout that works across common browsers and devices."
        "A small static page keeps the fallback predictable while avoiding third-party scripts, trackers, and remote assets."
        "Visitors can load this page quickly, read a few neutral sections, and continue browsing without special client requirements."
        "This template provides generic public content for a traditional TLS fallback endpoint."
    )
    local ctaOptions=("Learn more" "View updates" "Open homepage" "Browse notes" "See details" "Continue")
    local footerOptions=(
        "Static fallback page"
        "Local HTML and CSS only"
        "No external assets loaded"
        "Responsive static website"
        "Traditional TLS fallback content"
    )
    local accentOptions=("#2563eb" "#0f766e" "#7c3aed" "#dc2626" "#ea580c" "#4f46e5" "#0891b2" "#16a34a" "#9333ea" "#475569")
    local cardOneOptions=("Overview" "Updates" "Services" "Projects" "Notes" "Resources")
    local cardTwoOptions=("Responsive" "Reliable" "Lightweight" "Local" "Accessible" "Portable")
    local cardThreeOptions=("Contact" "Archive" "Status" "Links" "About" "Support")
    local cardTextOptions=(
        "Short neutral copy keeps the page natural without needing any remote dependency."
        "The layout is responsive and remains readable on phones, tablets, and desktops."
        "The files are bundled locally so the page can load without external networks."
        "Simple sections make the page look complete while staying easy to maintain."
        "The template is generated with small variations during installation."
    )

    local title=${titleOptions[$(($(randomNum 1 ${#titleOptions[@]}) - 1))]}
    local eyebrow=${eyebrowOptions[$(($(randomNum 1 ${#eyebrowOptions[@]}) - 1))]}
    local headline=${headlineOptions[$(($(randomNum 1 ${#headlineOptions[@]}) - 1))]}
    local body=${bodyOptions[$(($(randomNum 1 ${#bodyOptions[@]}) - 1))]}
    local cta=${ctaOptions[$(($(randomNum 1 ${#ctaOptions[@]}) - 1))]}
    local footer=${footerOptions[$(($(randomNum 1 ${#footerOptions[@]}) - 1))]}
    local accent=${accentOptions[$(($(randomNum 1 ${#accentOptions[@]}) - 1))]}
    local cardOne=${cardOneOptions[$(($(randomNum 1 ${#cardOneOptions[@]}) - 1))]}
    local cardTwo=${cardTwoOptions[$(($(randomNum 1 ${#cardTwoOptions[@]}) - 1))]}
    local cardThree=${cardThreeOptions[$(($(randomNum 1 ${#cardThreeOptions[@]}) - 1))]}
    local cardTextOne=${cardTextOptions[$(($(randomNum 1 ${#cardTextOptions[@]}) - 1))]}
    local cardTextTwo=${cardTextOptions[$(($(randomNum 1 ${#cardTextOptions[@]}) - 1))]}
    local cardTextThree=${cardTextOptions[$(($(randomNum 1 ${#cardTextOptions[@]}) - 1))]}

    local targetFile
    while IFS= read -r targetFile; do
        [[ -f "${targetFile}" ]] || continue
        sed -i \
            -e "s|__SITE_TITLE__|${title}|g" \
            -e "s|__SITE_EYEBROW__|${eyebrow}|g" \
            -e "s|__SITE_HEADLINE__|${headline}|g" \
            -e "s|__SITE_BODY__|${body}|g" \
            -e "s|__SITE_CTA__|${cta}|g" \
            -e "s|__SITE_FOOTER__|${footer}|g" \
            -e "s|__SITE_ACCENT__|${accent}|g" \
            -e "s|__CARD_ONE__|${cardOne}|g" \
            -e "s|__CARD_TWO__|${cardTwo}|g" \
            -e "s|__CARD_THREE__|${cardThree}|g" \
            -e "s|__CARD_TEXT_ONE__|${cardTextOne}|g" \
            -e "s|__CARD_TEXT_TWO__|${cardTextTwo}|g" \
            -e "s|__CARD_TEXT_THREE__|${cardTextThree}|g" \
            "${targetFile}"
    done < <(find "${nginxStaticPath}" -type f \( -name "*.html" -o -name "*.css" -o -name "*.js" \))
}

installNginxStaticTemplate() {
    local templateIndex=$1
    local localTemplate="${SCRIPT_DIR:-/etc/padm}/assets/static-sites/templates/html${templateIndex}.zip"
    local targetZip="${nginxStaticPath}html${templateIndex}.zip"
    cleanDirectoryContent "${nginxStaticPath}"
    if [[ -f "${localTemplate}" ]]; then
        cp "${localTemplate}" "${targetZip}"
    else
        downloadFile -P "${nginxStaticPath}" "https://raw.githubusercontent.com/neil1123-vip/padm/main/assets/static-sites/templates/html${templateIndex}.zip"
    fi
    if [[ ! -f "${targetZip}" ]]; then
        errorCard "静态站点模板下载失败"
        exit 1
    fi
    if ! unzip -o "${targetZip}" -d "${nginxStaticPath}" >/dev/null; then
        errorCard "静态站点模板解压失败"
        exit 1
    fi
    rm -f "${nginxStaticPath}html${templateIndex}.zip"*
    renderNginxStaticTemplate
}

# Nginx 传统 TLS fallback 静态站点
nginxBlog() {
    local progressIndex=${1:-}
    if [[ -d "${nginxStaticPath}" && -f "${nginxStaticPath}/check" && "${PADM_NGINX_BLOG_REINSTALL_PROMPT:-true}" != "true" ]]; then
        return 0
    fi

    if [[ -n "${progressIndex}" ]]; then
        progressCard "${progressIndex}" "添加传统 TLS fallback 静态站点"
    else
        echoContent yellow "\n开始添加传统 TLS fallback 静态站点"
    fi

    if [[ -d "${nginxStaticPath}" && -f "${nginxStaticPath}/check" ]]; then
        if [[ "${PADM_NGINX_BLOG_REINSTALL_PROMPT:-true}" == "true" && -z "${lastInstallationConfig}" && "${AUTO_INSTALL:-}" != "true" ]]; then
            echo
            autoRead nginx_blog_reinstall "检测到已安装传统 TLS fallback 静态站点，是否需要重新安装[y/n]:" nginxBlogInstallStatus
        else
            nginxBlogInstallStatus="n"
        fi

        if [[ "${nginxBlogInstallStatus}" == "y" ]]; then
            randomNum=$(randomNum 1 20)
            installNginxStaticTemplate "${randomNum}"
            successCard "添加传统 TLS fallback 静态站点成功"
        fi
    else
        randomNum=$(randomNum 1 20)
        installNginxStaticTemplate "${randomNum}"
        successCard "添加传统 TLS fallback 静态站点成功"
    fi

}

# 更新 SELinux http_port_t 端口
updateSELinuxHTTPPortT() {

    $(find /usr/bin /usr/sbin | grep -w journalctl) -xe >/etc/padm/nginx_error.log 2>&1

    if find /usr/bin /usr/sbin | grep -q -w semanage && find /usr/bin /usr/sbin | grep -q -w getenforce && grep -E "31300|31302" </etc/padm/nginx_error.log | grep -q "Permission denied"; then
        errorCard "检查SELinux端口是否开放"
        if ! $(find /usr/bin /usr/sbin | grep -w semanage) port -l | grep http_port | grep -q 31300; then
            $(find /usr/bin /usr/sbin | grep -w semanage) port -a -t http_port_t -p tcp 31300
            successCard "http_port_t 31300 端口开放成功"
        fi

        if ! $(find /usr/bin /usr/sbin | grep -w semanage) port -l | grep http_port | grep -q 31302; then
            $(find /usr/bin /usr/sbin | grep -w semanage) port -a -t http_port_t -p tcp 31302
            successCard "http_port_t 31302 端口开放成功"
        fi
        handleNginx start

    else
        exit 0
    fi
}

# 检查 wget 进度显示支持
checkWgetShowProgress() {
    if [[ "${release}" != "alpine" ]]; then
        if find /usr/bin /usr/sbin | grep -q "/wget" && wget --help | grep -q show-progress; then
            wgetShowProgressStatus="--show-progress"
        fi
    fi
}
addNginx302ToFile() {
    local redirectTarget=$1
    local targetPath=$2
    local tmpPath="${targetPath}.rewrite"
    awk -v redirectTarget="${redirectTarget}" '
        { print }
        /location \/ \{/ {
            print "return 302 '\''" redirectTarget "'\'';"
            inserted = 1
        }
        END { if (!inserted) exit 1 }
    ' "${targetPath}" >"${tmpPath}" && mv "${tmpPath}" "${targetPath}"
}

# 添加 302 重定向配置
addNginx302() {
    local redirectTarget=$1
    if ! updateAloneNginxConfig addNginx302ToFile "${redirectTarget}"; then
        errorCard "Nginx 配置检测失败，已恢复旧 alone.conf"
        return 1
    fi
}

# 更新脚本
updatePadm() {
    progressCard "$1" "更新管理脚本"
    rm -rf /etc/padm/install.sh
    if [[ "${release}" == "alpine" ]]; then
        wget -c -q -P /etc/padm/ -N "https://raw.githubusercontent.com/neil1123-vip/padm/main/install.sh"
    else
        downloadFile -P /etc/padm/ "https://raw.githubusercontent.com/neil1123-vip/padm/main/install.sh"
    fi

    sudo chmod 700 /etc/padm/install.sh

    successCard "更新完毕"
    statusCard "下一步" "请手动执行 [padm] 打开脚本"
    successCard "当前版本：$(getScriptVersion)\n"
    menuLine "$(uiStyle warn "如更新不成功，请手动执行下面命令")"
    menuLine "$(uiStyle value "wget -P /root -N https://raw.githubusercontent.com/neil1123-vip/padm/main/install.sh && chmod 700 /root/install.sh && /root/install.sh")"
    echo
    exit 0
}

disableRunningService() {
    local serviceName=$1
    local displayName=$2
    local wasActive=false

    systemctl is-active --quiet "${serviceName}" || return 0
    wasActive=true
    if ! systemctl stop "${serviceName}" >/dev/null 2>&1; then
        errorCard "${displayName}关闭失败"
        return 1
    fi
    if ! systemctl disable "${serviceName}" >/dev/null 2>&1; then
        if [[ "${wasActive}" == "true" ]]; then
            systemctl start "${serviceName}" >/dev/null 2>&1 || true
        fi
        errorCard "${displayName}禁用失败，已尝试恢复原运行状态"
        return 1
    fi
    successCard "${displayName}关闭成功"
}

# 防火墙
handleFirewall() {
    if [[ "$1" == "stop" ]]; then
        disableRunningService ufw ufw
        disableRunningService firewalld firewalld
    fi
}

# 网络优化
readonly PADM_BBR_SYSCTL_CONF="/etc/sysctl.d/99-padm-bbr.conf"
readonly PADM_BBR_STATE_FILE="/etc/padm/padm-bbr.state"

readSysctlValue() {
    local key=$1
    sysctl -n "${key}" 2>/dev/null || true
}

padmBbrAvailable() {
    local available
    available="$(readSysctlValue net.ipv4.tcp_available_congestion_control)"
    [[ " ${available} " == *" bbr "* ]]
}

printNetworkOptimizationStatus() {
    local kernel currentCongestion availableCongestion currentQdisc bbrStatus padmStatus
    kernel="$(uname -r 2>/dev/null || echo unknown)"
    currentCongestion="$(readSysctlValue net.ipv4.tcp_congestion_control)"
    availableCongestion="$(readSysctlValue net.ipv4.tcp_available_congestion_control)"
    currentQdisc="$(readSysctlValue net.core.default_qdisc)"
    currentCongestion=${currentCongestion:-unknown}
    availableCongestion=${availableCongestion:-unknown}
    currentQdisc=${currentQdisc:-unknown}

    if padmBbrAvailable; then
        bbrStatus="可用"
    else
        bbrStatus="不可用"
    fi

    if [[ -f "${PADM_BBR_SYSCTL_CONF}" ]]; then
        padmStatus="已写入 ${PADM_BBR_SYSCTL_CONF}"
    else
        padmStatus="未写入"
    fi

    echoContent title "\n┌─ 网络优化状态 ────────────────────────────────────"
    menuLine "当前内核：${kernel}"
    menuLine "当前拥塞控制：${currentCongestion}"
    menuLine "可用拥塞控制：${availableCongestion}"
    menuLine "当前默认 qdisc：${currentQdisc}"
    menuLine "BBR 是否可用：${bbrStatus}"
    menuLine "padm BBR 配置：${padmStatus}"
    menuClose
}

showNetworkOptimizationStatus() {
    printNetworkOptimizationStatus
    bbrInstall
}

commitPadmBbrFile() {
    local tmpFile=$1
    local targetFile=$2

    chmod 644 "${tmpFile}" || return 1
    mv "${tmpFile}" "${targetFile}"
}

restorePadmBbrRuntime() {
    local congestion=$1
    local qdisc=$2

    sysctl -w "net.ipv4.tcp_congestion_control=${congestion}" >>/tmp/padm-bbr-sysctl.log 2>&1 || true
    sysctl -w "net.core.default_qdisc=${qdisc}" >>/tmp/padm-bbr-sysctl.log 2>&1 || true
}

enableOfficialBbrFq() {
    if ! padmBbrAvailable; then
        modprobe tcp_bbr >/dev/null 2>&1 || true
    fi

    if ! padmBbrAvailable; then
        statusCard "BBR 不可用" "当前内核不支持 BBR" "padm 不会自动安装或切换内核" "如需第三方内核，请使用高级脚本并自行确认风险"
        bbrInstall
        return
    fi

    local previousCongestion previousQdisc stateTmp sysctlTmp
    previousCongestion="$(readSysctlValue net.ipv4.tcp_congestion_control)"
    previousQdisc="$(readSysctlValue net.core.default_qdisc)"
    previousCongestion=${previousCongestion:-cubic}
    previousQdisc=${previousQdisc:-fq_codel}

    mkdir -p "$(dirname "${PADM_BBR_STATE_FILE}")"
    stateTmp=$(mktemp /tmp/padm-bbr-state.XXXXXX) || { statusCard "BBR 启用失败" "无法创建状态临时文件"; bbrInstall; return; }
    cat >"${stateTmp}" <<EOF
previous_congestion=${previousCongestion}
previous_qdisc=${previousQdisc}
EOF
    if ! commitPadmBbrFile "${stateTmp}" "${PADM_BBR_STATE_FILE}"; then
        rm -f "${stateTmp}"
        statusCard "BBR 启用失败" "状态文件提交失败，未改动 sysctl 配置"
        bbrInstall
        return
    fi

    sysctlTmp=$(mktemp /tmp/padm-bbr-sysctl.XXXXXX) || { rm -f "${PADM_BBR_STATE_FILE}"; statusCard "BBR 启用失败" "无法创建 sysctl 临时文件"; bbrInstall; return; }
    cat >"${sysctlTmp}" <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    if ! commitPadmBbrFile "${sysctlTmp}" "${PADM_BBR_SYSCTL_CONF}"; then
        rm -f "${sysctlTmp}" "${PADM_BBR_STATE_FILE}"
        statusCard "BBR 启用失败" "sysctl 配置提交失败，已删除本次状态记录"
        bbrInstall
        return
    fi

    if ! sysctl -p "${PADM_BBR_SYSCTL_CONF}" >/tmp/padm-bbr-sysctl.log 2>&1; then
        rm -f "${PADM_BBR_SYSCTL_CONF}" "${PADM_BBR_STATE_FILE}"
        restorePadmBbrRuntime "${previousCongestion}" "${previousQdisc}"
        statusCard "BBR 启用失败" "sysctl 应用失败，已删除本次写入并尝试恢复原运行值" "日志：/tmp/padm-bbr-sysctl.log"
        bbrInstall
        return
    fi

    if [[ "$(readSysctlValue net.ipv4.tcp_congestion_control)" == "bbr" && "$(readSysctlValue net.core.default_qdisc)" == "fq" ]]; then
        statusCard "BBR 已启用" "当前拥塞控制：bbr" "当前默认 qdisc：fq"
    else
        rm -f "${PADM_BBR_SYSCTL_CONF}" "${PADM_BBR_STATE_FILE}"
        restorePadmBbrRuntime "${previousCongestion}" "${previousQdisc}"
        statusCard "BBR 启用失败" "配置已应用但当前状态未完全匹配，已删除本次写入并尝试恢复原运行值" "请查看下方状态和 /tmp/padm-bbr-sysctl.log"
    fi
    printNetworkOptimizationStatus
    bbrInstall
}

disablePadmBbr() {
    if [[ ! -f "${PADM_BBR_SYSCTL_CONF}" ]]; then
        statusCard "无需关闭" "padm 未写入 BBR 配置" "不会改动其它 sysctl 文件"
        printNetworkOptimizationStatus
        bbrInstall
        return
    fi

    local previousCongestion="cubic"
    local previousQdisc="fq_codel"
    if [[ -f "${PADM_BBR_STATE_FILE}" ]]; then
        . "${PADM_BBR_STATE_FILE}"
    fi

    rm -f "${PADM_BBR_SYSCTL_CONF}" "${PADM_BBR_STATE_FILE}"
    sysctl --system >/tmp/padm-bbr-sysctl.log 2>&1 || true
    sysctl -w "net.ipv4.tcp_congestion_control=${previous_congestion:-${previousCongestion}}" >>/tmp/padm-bbr-sysctl.log 2>&1 || true
    sysctl -w "net.core.default_qdisc=${previous_qdisc:-${previousQdisc}}" >>/tmp/padm-bbr-sysctl.log 2>&1 || true
    statusCard "padm BBR 已关闭" "已删除 ${PADM_BBR_SYSCTL_CONF}" "已尝试恢复启用前的拥塞控制和 qdisc" "未改动用户其它 sysctl 配置"
    printNetworkOptimizationStatus
    bbrInstall
}

runThirdPartyTcpAccelerationScript() {
    warnCard \
        "来源：ylx2016/Linux-NetSpeed" \
        "可能安装第三方或旧内核、修改 grub 引导，并要求重启" \
        "生产节点慎用；padm 不校验该脚本内部行为" \
        "默认推荐仍是官方内核自带 BBR + fq"
    autoConfirm third_party_tcp_confirm "确认下载并运行第三方 TCP 加速脚本？" n confirmThirdPartyTcp
    if [[ "${confirmThirdPartyTcp}" != "y" ]]; then
        statusCard "已取消" "未运行第三方 TCP 加速脚本"
        bbrInstall
        return
    fi

    local scriptPath="/tmp/padm-tcpx.sh"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcpx.sh" -o "${scriptPath}"
    else
        wget -O "${scriptPath}" "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcpx.sh"
    fi

    if [[ ! -s "${scriptPath}" ]] || ! grep -q "^#!" "${scriptPath}"; then
        rm -f "${scriptPath}"
        statusCard "下载失败" "第三方脚本为空或格式异常" "未执行任何第三方脚本"
        bbrInstall
        return
    fi

    chmod +x "${scriptPath}"
    "${scriptPath}"
}

bbrInstall() {
    echoContent title "\n┌─ 网络优化 ─────────────────────────────────────────"
    menuLine "默认推荐官方内核自带 BBR + fq；不自动换内核"
    menuItem 1 "查看网络优化状态" "内核、拥塞控制、qdisc、BBR 可用性"
    menuItem 2 "启用官方 BBR + fq" "写入 ${PADM_BBR_SYSCTL_CONF}"
    menuItem 3 "关闭 padm BBR 设置" "只删除 padm 写入的 sysctl 配置"
    menuDangerItem 4 "高级：第三方 TCP 加速脚本" "可能换内核、改引导、需要重启"
    menuReturnItem 5 "返回主菜单" "回到 padm 管理面板"
    menuClose
    autoRead bbr_menu "请选择:" installBBRStatus
    case "${installBBRStatus}" in
    1)
        showNetworkOptimizationStatus
        ;;
    2)
        enableOfficialBbrFq
        ;;
    3)
        disablePadmBbr
        ;;
    4)
        runThirdPartyTcpAccelerationScript
        ;;
    5)
        menu
        ;;
    *)
        errorCard "选择错误，重新选择"
        bbrInstall
        ;;
    esac
}

writeXrayLogConfig() {
    local targetPath=$1
    local logBasePath=$2
    local accessEnabled=$3
    if [[ "${accessEnabled}" == "true" ]]; then
        writeRoutingJsonConfig "${targetPath}" <<EOF || return 1
{
  "log": {
    "access":"${logBasePath}access.log",
    "error": "${logBasePath}error.log",
    "loglevel": "debug"
  }
}
EOF
    else
        writeRoutingJsonConfig "${targetPath}" <<EOF || return 1
{
  "log": {
    "error": "${logBasePath}error.log",
    "loglevel": "warning"
  }
}
EOF
    fi
}

updateRealityShowConfig() {
    local targetPath=$1
    local showStatus=$2
    updateRoutingJsonConfig "${targetPath}" '.inbounds[0].streamSettings.realitySettings.show = $showStatus' --argjson showStatus "${showStatus}"
}

# 日志管理
checkLog() {
    if [[ "${coreInstallType}" == "2" ]]; then
        errorCard "此功能仅支持 Xray-core 内核"
        exit 0
    fi
    if [[ -z "${configPath}" && -z "${realityStatus}" ]]; then
        errorCard "没有检测到安装目录，请执行脚本安装内容"
        exit 0
    fi
    local realityLogShow=
    local logStatus=false
    if grep -q "access" ${configPath}00_log.json; then
        logStatus=true
    fi

    echoContent title "\n┌─ 日志管理 ─────────────────────────────────────────"
    menuLine "建议仅调试时打开 access 日志"

    if [[ "${logStatus}" == "false" ]]; then
        menuItem 1 "打开 access 日志" "写入 access/error 调试日志配置"
    else
        menuItem 1 "关闭 access 日志" "停止写入 access 调试日志"
    fi

    menuItem 2 "监听 access 日志" "tail -f access.log"
    menuItem 3 "监听 error 日志" "tail -f error.log"
    menuItem 4 "查看证书定时任务日志" "查看 TLS cron 日志"
    menuItem 5 "查看证书安装日志" "查看证书申请/安装日志"
    menuItem 6 "清空日志" "清理当前日志文件"
    menuClose

    autoRead log_menu "请选择:" selectAccessLogType
    local configPathLog=${configPath//conf\//}

    case ${selectAccessLogType} in
    1)
        if [[ "${logStatus}" == "false" ]]; then
            realityLogShow=true
            writeXrayLogConfig "${configPath}00_log.json" "${configPathLog}" true || return 1
        elif [[ "${logStatus}" == "true" ]]; then
            realityLogShow=false
            writeXrayLogConfig "${configPath}00_log.json" "${configPathLog}" false || return 1
        fi

        if [[ ${realityStatus} == "7" ]]; then
            updateRealityShowConfig "${configPath}07_VLESS_vision_reality_inbounds.json" "${realityLogShow}" || return 1
        fi
        if [[ ${realityStatus} == "12" ]]; then
            updateRealityShowConfig "${configPath}12_VLESS_XHTTP_inbounds.json" "${realityLogShow}" || return 1
        fi
        reloadCore
        checkLog 1
        ;;
    2)
        tail -f "${configPathLog}access.log"
        ;;
    3)
        tail -f "${configPathLog}error.log"
        ;;
    4)
        if [[ ! -f "/etc/padm/crontab_tls.log" ]]; then
            touch /etc/padm/crontab_tls.log
        fi
        tail -n 100 /etc/padm/crontab_tls.log
        ;;
    5)
        tail -n 100 /etc/padm/tls/acme.log
        ;;
    6)
        echo >"${configPathLog}access.log"
        echo >"${configPathLog}error.log"
        ;;
    esac
}

# 脚本快捷方式
aliasInstall() {
    local sourceInstall="${SCRIPT_DIR}/install.sh"
    if [[ ! -f "${sourceInstall}" && -f "$HOME/install.sh" ]]; then
        sourceInstall="$HOME/install.sh"
    fi

    if [[ -f "${sourceInstall}" && -d "/etc/padm" ]] && grep <"${sourceInstall}" -q "ensureScriptModules"; then
        cp "${sourceInstall}" /etc/padm/install.sh
        chmod 700 /etc/padm/install.sh
        if [[ -d "${SCRIPT_DIR}/shell" ]]; then
            rm -rf /etc/padm/shell
            cp -R "${SCRIPT_DIR}/shell" /etc/padm/
        fi
        if [[ -d "${SCRIPT_DIR}/documents" ]]; then
            rm -rf /etc/padm/documents
            cp -R "${SCRIPT_DIR}/documents" /etc/padm/
        fi
        if [[ -d "${SCRIPT_DIR}/assets" ]]; then
            rm -rf /etc/padm/assets
            cp -R "${SCRIPT_DIR}/assets" /etc/padm/
        fi
        rm -f /etc/padm/xray/README.md
        local shortcutCreated=
        if [[ -d "/usr/bin/" ]]; then
            if [[ ! -f "/usr/bin/padm" ]]; then
                ln -s /etc/padm/install.sh /usr/bin/padm
                chmod 700 /usr/bin/padm
                shortcutCreated=true
            fi
        elif [[ -d "/usr/sbin" ]]; then
            if [[ ! -f "/usr/sbin/padm" ]]; then
                ln -s /etc/padm/install.sh /usr/sbin/padm
                chmod 700 /usr/sbin/padm
                shortcutCreated=true
            fi
        fi
        if [[ "${sourceInstall}" == "$HOME/install.sh" ]]; then
            rm -rf "$HOME/install.sh"
        fi
        if [[ "${shortcutCreated}" == "true" ]]; then
            echoContent green "快捷方式创建成功，可执行[padm]重新打开脚本"
        fi
    fi
}
