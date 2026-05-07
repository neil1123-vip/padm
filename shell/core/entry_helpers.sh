#!/usr/bin/env bash

# 初始化Nginx申请证书配置
initTLSNginxConfig() {
    handleNginx stop
    echoContent skyBlue "\n进度  $1/${totalProgress} : 初始化Nginx证书验证配置"
    if [[ -n "${currentHost}" && -z "${lastInstallationConfig}" ]]; then
        echo
        autoRead reuse_last "读取到上次安装记录，域名为 [${currentHost}]，是否使用？[y/n]:" historyDomainStatus
        if [[ "${historyDomainStatus}" == "y" ]]; then
            domain=${currentHost}
            echoContent yellow "\n ---> 域名: ${domain}"
        else
            echo
            echoContent yellow "请输入要配置的域名 例: www.example.com --->"
            autoRead domain "域名:" domain
        fi
    elif [[ -n "${currentHost}" && -n "${lastInstallationConfig}" ]]; then
        domain=${currentHost}
    else
        echo
        echoContent yellow "请输入要配置的域名 例: www.example.com --->"
        autoRead domain "域名:" domain
    fi

    if [[ -z ${domain} ]]; then
        echoContent red "  域名不可为空--->"
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

# singbox Nginx config
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
        cat <<EOF >>${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf
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
            autoRead reuse_last "读取到上次安装时的TLS类型协议入口端口 [${currentPort}]，用于VLESS+TCP/TLS Vision、VLESS+WS/TLS、VMess+WS/TLS、Trojan+TCP/TLS、Trojan+gRPC/TLS、VLESS+gRPC/TLS，是否使用？[y/n]:" historyCustomPortStatus
            if [[ "${historyCustomPortStatus}" == "y" ]]; then
                port=${currentPort}
                echoContent yellow "\n ---> TLS类型协议入口端口: ${port}"
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
            echoContent yellow "请输入TLS类型协议入口端口[默认: 443]，用于VLESS+TCP/TLS Vision、VLESS+WS/TLS、VMess+WS/TLS、Trojan+TCP/TLS、Trojan+gRPC/TLS、VLESS+gRPC/TLS，[回车使用默认]"
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
                echoContent yellow "\n ---> TLS类型协议入口端口: ${port}"
                if [[ -z "${btDomain}" ]]; then
                    checkDNSIP "${domain}"
                    removeNginxDefaultConf
                    checkPortOpen "${port}" "${domain}"
                fi
            else
                echoContent red " ---> 端口输入错误"
                exit 0
            fi
        else
            echoContent red " ---> 端口不可为空"
            exit 0
        fi
    fi
}

# 自定义/随机路径
randomPathFunction() {
    if [[ -n $1 ]]; then
        echoContent skyBlue "\n进度  $1/${totalProgress} : 配置协议路径"
    else
        echoContent skyBlue "配置协议路径"
    fi

    if [[ -n "${currentPath}" ]]; then
        customPath=${currentPath}
        echoContent green " ---> 已复用上次安装的path路径"
    else
        initRandomPath
        currentPath=${customPath}
        echoContent green " ---> 已自动生成随机path路径"
    fi

    echoContent yellow "\n path:${currentPath}"
    echoContent skyBlue "\n----------------------------"
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
        downloadFile -P "${nginxStaticPath}" "https://raw.githubusercontent.com/neil1123-vip/padm/master/assets/static-sites/templates/html${templateIndex}.zip"
    fi
    if [[ ! -f "${targetZip}" ]]; then
        echoContent red " ---> 静态站点模板下载失败"
        exit 1
    fi
    if ! unzip -o "${targetZip}" -d "${nginxStaticPath}" >/dev/null; then
        echoContent red " ---> 静态站点模板解压失败"
        exit 1
    fi
    rm -f "${nginxStaticPath}html${templateIndex}.zip"*
    renderNginxStaticTemplate
}

# Nginx传统 TLS fallback 静态站点
nginxBlog() {
    if [[ -n "$1" ]]; then
        echoContent skyBlue "\n进度 $1/${totalProgress} : 添加传统 TLS fallback 静态站点"
    else
        echoContent yellow "\n开始添加传统 TLS fallback 静态站点"
    fi

    if [[ -d "${nginxStaticPath}" && -f "${nginxStaticPath}/check" ]]; then
        echo
        if [[ -z "${lastInstallationConfig}" ]]; then
            read -r -p "检测到已安装传统 TLS fallback 静态站点，是否需要重新安装[y/n]:" nginxBlogInstallStatus
        else
            nginxBlogInstallStatus="n"
        fi

        if [[ "${nginxBlogInstallStatus}" == "y" ]]; then
            randomNum=$(randomNum 1 20)
            installNginxStaticTemplate "${randomNum}"
            echoContent green " ---> 添加传统 TLS fallback 静态站点成功"
        fi
    else
        randomNum=$(randomNum 1 20)
        installNginxStaticTemplate "${randomNum}"
        echoContent green " ---> 添加传统 TLS fallback 静态站点成功"
    fi

}

# 修改http_port_t端口
updateSELinuxHTTPPortT() {

    $(find /usr/bin /usr/sbin | grep -w journalctl) -xe >/etc/padm/nginx_error.log 2>&1

    if find /usr/bin /usr/sbin | grep -q -w semanage && find /usr/bin /usr/sbin | grep -q -w getenforce && grep -E "31300|31302" </etc/padm/nginx_error.log | grep -q "Permission denied"; then
        echoContent red " ---> 检查SELinux端口是否开放"
        if ! $(find /usr/bin /usr/sbin | grep -w semanage) port -l | grep http_port | grep -q 31300; then
            $(find /usr/bin /usr/sbin | grep -w semanage) port -a -t http_port_t -p tcp 31300
            echoContent green " ---> http_port_t 31300 端口开放成功"
        fi

        if ! $(find /usr/bin /usr/sbin | grep -w semanage) port -l | grep http_port | grep -q 31302; then
            $(find /usr/bin /usr/sbin | grep -w semanage) port -a -t http_port_t -p tcp 31302
            echoContent green " ---> http_port_t 31302 端口开放成功"
        fi
        handleNginx start

    else
        exit 0
    fi
}

# 检查wget showProgress
checkWgetShowProgress() {
    if [[ "${release}" != "alpine" ]]; then
        if find /usr/bin /usr/sbin | grep -q "/wget" && wget --help | grep -q show-progress; then
            wgetShowProgressStatus="--show-progress"
        fi
    fi
}
# 添加302配置
addNginx302() {

    local count=1
    grep -n "location / {" <"${nginxConfigPath}alone.conf" | while read -r line; do
        if [[ -n "${line}" ]]; then
            local insertIndex=
            insertIndex="$(echo "${line}" | awk -F "[:]" '{print $1}')"
            insertIndex=$((insertIndex + count))
            sed "${insertIndex}i return 302 '$1';" ${nginxConfigPath}alone.conf >${nginxConfigPath}tmpfile && mv ${nginxConfigPath}tmpfile ${nginxConfigPath}alone.conf
            count=$((count + 1))
        else
            echoContent red " ---> 302添加失败"
            backupNginxConfig restoreBackup
        fi

    done
}

# 更新脚本
updatePadm() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 更新管理脚本"
    rm -rf /etc/padm/install.sh
    if [[ "${release}" == "alpine" ]]; then
        wget -c -q -P /etc/padm/ -N "https://raw.githubusercontent.com/neil1123-vip/padm/master/install.sh"
    else
        downloadFile -P /etc/padm/ "https://raw.githubusercontent.com/neil1123-vip/padm/master/install.sh"
    fi

    sudo chmod 700 /etc/padm/install.sh

    echoContent green "\n ---> 更新完毕"
    echoContent yellow " ---> 请手动执行[padm]打开脚本"
    echoContent green " ---> 当前版本：$(getScriptVersion)\n"
    echoContent yellow "如更新不成功，请手动执行下面命令\n"
    echoContent skyBlue "wget -P /root -N https://raw.githubusercontent.com/neil1123-vip/padm/master/install.sh && chmod 700 /root/install.sh && /root/install.sh"
    echo
    exit 0
}

# 防火墙
handleFirewall() {
    if systemctl status ufw 2>/dev/null | grep -q "active (exited)" && [[ "$1" == "stop" ]]; then
        systemctl stop ufw >/dev/null 2>&1
        systemctl disable ufw >/dev/null 2>&1
        echoContent green " ---> ufw关闭成功"

    fi

    if systemctl status firewalld 2>/dev/null | grep -q "active (running)" && [[ "$1" == "stop" ]]; then
        systemctl stop firewalld >/dev/null 2>&1
        systemctl disable firewalld >/dev/null 2>&1
        echoContent green " ---> firewalld关闭成功"
    fi
}

# 安装BBR
bbrInstall() {
    echoContent skyBlue "\n┌─ BBR / DD 脚本 ────────────────────────────────────"
    menuLine "使用 ylx2016/Linux-NetSpeed 成熟脚本，请先确认风险"
    menuItem 1 "安装脚本" "推荐原版 BBR + FQ"
    menuItem 2 "返回主菜单" "回到 padm 管理面板"
    menuClose
    read -r -p "请选择:" installBBRStatus
    if [[ "${installBBRStatus}" == "1" ]]; then
        wget -O tcpx.sh "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh" && chmod +x tcpx.sh && ./tcpx.sh
    else
        menu
    fi
}

# 查看、检查日志
checkLog() {
    if [[ "${coreInstallType}" == "2" ]]; then
        echoContent red "\n ---> 此功能仅支持Xray-core内核"
        exit 0
    fi
    if [[ -z "${configPath}" && -z "${realityStatus}" ]]; then
        echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
        exit 0
    fi
    local realityLogShow=
    local logStatus=false
    if grep -q "access" ${configPath}00_log.json; then
        logStatus=true
    fi

    echoContent skyBlue "\n┌─ 日志管理 ─────────────────────────────────────────"
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

    read -r -p "请选择:" selectAccessLogType
    local configPathLog=${configPath//conf\//}

    case ${selectAccessLogType} in
    1)
        if [[ "${logStatus}" == "false" ]]; then
            realityLogShow=true
            cat <<EOF >${configPath}00_log.json
{
  "log": {
    "access":"${configPathLog}access.log",
    "error": "${configPathLog}error.log",
    "loglevel": "debug"
  }
}
EOF
        elif [[ "${logStatus}" == "true" ]]; then
            realityLogShow=false
            cat <<EOF >${configPath}00_log.json
{
  "log": {
    "error": "${configPathLog}error.log",
    "loglevel": "warning"
  }
}
EOF
        fi

        if [[ ${realityStatus} == "7" ]]; then
            local vlessVisionRealityInbounds
            vlessVisionRealityInbounds=$(jq -r ".inbounds[0].streamSettings.realitySettings.show=${realityLogShow}" ${configPath}07_VLESS_vision_reality_inbounds.json)
            echo "${vlessVisionRealityInbounds}" | jq . >${configPath}07_VLESS_vision_reality_inbounds.json
        fi
        if [[ ${realityStatus} == "12" ]]; then
            local vlessVisionRealityXHTTPInbounds
            vlessVisionRealityXHTTPInbounds=$(jq -r ".inbounds[0].streamSettings.realitySettings.show=${realityLogShow}" ${configPath}12_VLESS_XHTTP_inbounds.json)
            echo "${vlessVisionRealityXHTTPInbounds}" | jq . >${configPath}12_VLESS_XHTTP_inbounds.json
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
