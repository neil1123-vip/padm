#!/usr/bin/env bash

PADM_THIRD_PARTY_TCP_SCRIPT_URL="https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcpx.sh"

# 初始化 Nginx 证书验证配置
entryHelperTmpPath() {
    local template=$1
    padmFallbackTmpFilePath "${template}"
}

singBoxVMessHTTPUpgradeNginxTestLog() {
    entryHelperTmpPath padm-sing-box-vmess-httpupgrade-nginx-test.log
}

thirdPartyTcpScriptPath() {
    entryHelperTmpPath padm-tcpx.sh
}

entryHelperNginxConfigFile() {
    local fileName=$1
    if declare -F nginxConfigFilePath >/dev/null 2>&1; then
        nginxConfigFilePath "${fileName}"
        return $?
    fi
    [[ -n "${nginxConfigPath:-}" ]] || return 1
    padmManagedFilePath "${nginxConfigPath}" "${fileName}"
}

initTLSNginxConfig() {
    if ! runCoreServiceActionAllowFailure handleNginx stop; then
        errorCard "Nginx 服务停止失败，已取消 TLS 初始化"
        return 1
    fi
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
        coreDomainRequiredErrorCard
        [[ "${AUTO_INSTALL:-}" == "true" ]] && return 1
        initTLSNginxConfig 3
    else
        if ! padmIsValidHostName "${domain}"; then
            errorCard "域名不合法" "${domain}"
            return 1
        fi
        dnsTLSDomain=$(echo "${domain}" | awk -F "." '{$1="";print $0}' | sed 's/^[[:space:]]*//' | sed 's/ /./g')
        if [[ "${selectCoreType}" == "1" ]]; then
            customPortFunction || return 1
        fi
        # 修改配置
        if ! runCoreServiceActionAllowFailure handleNginx stop; then
            errorCard "Nginx 服务停止失败，已取消 TLS 初始化"
            return 1
        fi
    fi
}

# sing-box Nginx 配置
writeSingBoxVMessHTTPUpgradeNginxConfig() {
    local targetPath
    local tmpPath
    local backupPath
    local logFile
    if ! targetPath=$(entryHelperNginxConfigFile "sing_box_VMess_HTTPUpgrade.conf"); then
        errorCard "sing-box HTTPUpgrade Nginx 配置路径异常"
        return 1
    fi
    padmCommitTargetIsFileLike "${targetPath}" || {
        errorCard "sing-box HTTPUpgrade Nginx 配置目标异常"
        return 1
    }
    padmCreateTempFileForTarget tmpPath "${targetPath}" nginx || return 1
    if ! cat >"${tmpPath}"; then
        padmRemoveCleanupPath "${tmpPath}"
        return 1
    fi
    backupPath="${targetPath}.bak"
    if command -v nginx >/dev/null 2>&1; then
        if [[ -f "${targetPath}" ]] && ! backupManagedFileToPath "${targetPath}" "${backupPath}" 644; then
            padmRemoveCleanupPath "${tmpPath}"
            return 1
        fi
        if ! commitGeneratedFile "${tmpPath}" "${targetPath}" 644; then
            padmRemoveCleanupPath "${tmpPath}"
            removeManagedFilesIfPresentIgnoreFailure "${backupPath}"
            return 1
        fi
        logFile=$(singBoxVMessHTTPUpgradeNginxTestLog)
        if ! nginx -t >"${logFile}" 2>&1; then
            if [[ -f "${backupPath}" ]]; then
                restoreManagedFileFromBackup "${backupPath}" "${targetPath}" 644 || return 1
            else
                removeManagedFileIfPresent "${targetPath}" || return 1
            fi
            return 1
        fi
        removeManagedFilesIfPresentIgnoreFailure "${backupPath}"
    else
        commitGeneratedFile "${tmpPath}" "${targetPath}" 644 || {
            padmRemoveCleanupPath "${tmpPath}"
            return 1
        }
    fi
}

singBoxNginxConfig() {
    local type=$1
    local port=$2

    if ! padmIsValidHostName "${domain}"; then
        errorCard "域名不合法" "${domain}"
        return 1
    fi
    if protocolSelectionIncludes "${selectCustomInstallType}" 23 "$1" && ! padmIsSafeRoutePathSegment "${currentPath}"; then
        errorCard "path 不合法" "${currentPath}"
        return 1
    fi

    local nginxH2Conf=
    nginxH2Conf="listen ${port} http2 so_keepalive=on ssl;"
    nginxVersion=$(nginx -v 2>&1)

    local singBoxNginxSSL=
    singBoxNginxSSL="ssl_certificate /etc/padm/tls/${domain}.crt;ssl_certificate_key /etc/padm/tls/${domain}.key;"

    if echo "${nginxVersion}" | grep -q "1.25" && [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $3}') -gt 0 ]] || [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $2}') -gt 25 ]]; then
        nginxH2Conf="listen ${port} so_keepalive=on ssl;http2 on;"
    fi

    if protocolSelectionIncludes "${selectCustomInstallType}" 23 "$1"; then
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
                if ! runCoreServiceActionAllowFailure handleXray stop; then
                    errorCard "Xray 服务停止失败，无法复用当前 Reality 端口"
                    return 1
                fi
            fi
        fi

        if [[ -n "${port}" ]]; then
            if validPortNumber "${port}"; then
                allowPort "${port}" || return 1
                statusCard "TLS 入口端口" "${port}"
                if [[ -z "${btDomain}" ]]; then
                    checkDNSIP "${domain}" || return 1
                    removeNginxDefaultConf
                    checkPortOpen "${port}" "${domain}" || return 1
                fi
            else
                corePortInputErrorCard
                return 1
            fi
        else
            errorCard "端口不可为空"
            return 1
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
        if ! padmIsSafeRoutePathSegment "${currentPath}"; then
            errorCard "path 不合法" "${currentPath}"
            return 1
        fi
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

nginxStaticSafePath() {
    local staticPath="${nginxStaticPath:-}"
    [[ -n "${staticPath}" ]] || return 1
    staticPath="${staticPath%/}"
    padmIsSafeAbsolutePath "${staticPath}" || return 1
    printf '%s\n' "${staticPath}/"
}

installNginxStaticTemplate() {
    local templateIndex=$1
    local localTemplate="${SCRIPT_DIR:-/etc/padm}/assets/static-sites/templates/html${templateIndex}.zip"
    local staticPath resolvedStaticPath staticParent staticName
    local stageRoot stageStaticPath targetZip
    local oldStaticPath renderStatus=0
    if ! staticPath=$(nginxStaticSafePath); then
        errorCard "静态站点目录异常"
        return 1
    fi
    resolvedStaticPath="${staticPath%/}"
    staticParent=$(dirname -- "${resolvedStaticPath}")
    staticName=$(basename -- "${resolvedStaticPath}")
    padmEnsureSafeDirectory "${staticParent}" || { errorCard "静态站点目录异常"; return 1; }
    padmCreateTempPathCompat stageRoot -d "${staticParent}/.${staticName}.padm-template.XXXXXX" || {
        errorCard "静态站点模板暂存目录创建失败"
        return 1
    }
    stageStaticPath="${stageRoot}/${staticName}"
    mkdir -p "${stageStaticPath}" || {
        cleanupInstallSyncPath "${stageRoot}"
        errorCard "静态站点模板暂存目录创建失败"
        return 1
    }
    targetZip="${stageStaticPath}/html${templateIndex}.zip"
    if [[ -f "${localTemplate}" ]]; then
        cp "${localTemplate}" "${targetZip}" || {
            cleanupInstallSyncPath "${stageRoot}"
            errorCard "静态站点模板准备失败"
            return 1
        }
    else
        cleanupInstallSyncPath "${stageRoot}"
        errorCard "静态站点模板缺失"
        return 1
    fi
    if [[ ! -f "${targetZip}" ]]; then
        cleanupInstallSyncPath "${stageRoot}"
        errorCard "静态站点模板准备失败"
        return 1
    fi
    if ! unzip -o "${targetZip}" -d "${stageStaticPath}" >/dev/null; then
        cleanupInstallSyncPath "${stageRoot}"
        errorCard "静态站点模板解压失败"
        return 1
    fi
    removeManagedFileIfPresent "${targetZip}" || {
        cleanupInstallSyncPath "${stageRoot}"
        errorCard "静态站点模板清理失败"
        return 1
    }

    oldStaticPath="${nginxStaticPath:-}"
    nginxStaticPath="${stageStaticPath}"
    renderNginxStaticTemplate || renderStatus=$?
    nginxStaticPath="${oldStaticPath}"
    if [[ "${renderStatus}" -ne 0 ]]; then
        cleanupInstallSyncPath "${stageRoot}"
        return "${renderStatus}"
    fi

    if ! syncInstallDirectoryTree "${stageStaticPath}" "${resolvedStaticPath}"; then
        cleanupInstallSyncPath "${stageRoot}"
        errorCard "静态站点模板安装失败，已保留旧站点"
        return 1
    fi
    cleanupInstallSyncPath "${stageRoot}"
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
            installNginxStaticTemplate "${randomNum}" || return 1
            successCard "添加传统 TLS fallback 静态站点成功"
        fi
    else
        randomNum=$(randomNum 1 20)
        installNginxStaticTemplate "${randomNum}" || return 1
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
    ' "${targetPath}" >"${tmpPath}" || {
        rm -f "${tmpPath}" >/dev/null 2>&1
        coreSetManualCheckMessage ALONE_NGINX_CONFIG_ERROR "Nginx 302 配置编辑失败" " ${targetPath}"
        errorCard "${ALONE_NGINX_CONFIG_ERROR}"
        return 1
    }
    mv "${tmpPath}" "${targetPath}" || {
        rm -f "${tmpPath}" >/dev/null 2>&1
        coreSetManualCheckMessage ALONE_NGINX_CONFIG_ERROR "Nginx 302 配置提交失败" " ${targetPath}"
        errorCard "${ALONE_NGINX_CONFIG_ERROR}"
        return 1
    }
}

# 添加 302 重定向配置
addNginx302() {
    local redirectTarget=$1
    if ! updateAloneNginxConfig addNginx302ToFile "${redirectTarget}"; then
        [[ -n "${ALONE_NGINX_CONFIG_ERROR:-}" ]] || aloneNginxConfigRecoveredErrorCard
        return 1
    fi
}

padmEntryScriptReady() {
    local entryPath=$1
    [[ -s "${entryPath}" ]] && bash -n "${entryPath}" && grep -q "ensureScriptModules" "${entryPath}"
}

showPadmScriptInstallStatus() {
    local installDir="${PADM_INSTALL_DIR:-/etc/padm}"
    local installPath="${installDir}/install.sh"
    local refFile="${installDir}/.padm-ref"
    local manifestFile="${installDir}/.padm-module-manifest"
    local entryStatus="未就绪"
    local refStatus="缺失"
    local manifestStatus="缺失"

    if padmEntryScriptReady "${installPath}"; then
        entryStatus="已就绪"
    fi
    [[ -s "${refFile}" ]] && refStatus="$(tr -d '\r\n' <"${refFile}")"
    [[ -s "${manifestFile}" ]] && manifestStatus="存在"

    statusCard "padm 脚本安装状态" \
        "入口：${installPath}" \
        "入口校验：${entryStatus}" \
        "版本：$(getScriptVersion)" \
        ".padm-ref：${refStatus}" \
        ".padm-module-manifest：${manifestStatus}"
}

restorePadmEntryBackup() {
    local backupPath=$1
    local installPath=$2
    backupPath=$(padmResolveManagedAbsolutePath "${backupPath}") || return 1
    installPath=$(padmResolveManagedAbsolutePath "${installPath}") || return 1
    [[ -f "${backupPath}" ]] || return 2
    [[ ! -d "${installPath}" ]] || return 1
    commitGeneratedFile "${backupPath}" "${installPath}" 700
}

# 更新脚本
updatePadm() {
    local installDir="${PADM_INSTALL_DIR:-/etc/padm}"
    local installPath backupPath
    local tmpDir newInstall installStage
    local remoteRef= installUrl
    if ! padmIsSafeAbsolutePath "${installDir}"; then
        errorCard "更新入口目录异常"
        return 1
    fi
    installPath=$(padmManagedFilePath "${installDir}" "install.sh") || { errorCard "更新入口路径异常"; return 1; }
    backupPath=$(padmManagedFilePath "${installDir}" "install.sh.bak") || { errorCard "更新入口备份路径异常"; return 1; }
    if ! padmEnsureSafeDirectory "${installDir}"; then
        errorCard "更新入口目录创建失败"
        return 1
    fi
    if [[ -d "${installPath}" ]]; then
        local manualCheckMessage
        coreSetManualCheckMessage manualCheckMessage "更新入口目标异常" " ${installPath}"
        errorCard "${manualCheckMessage}"
        return 1
    fi
    progressCard "$1" "更新管理脚本"

    padmCreateTmpRootPath tmpDir padm-update.XXXXXX -d || { errorCard "更新入口临时目录创建失败"; return 1; }
    newInstall="${tmpDir}/install.sh"
    if declare -F fetchRemoteRef >/dev/null 2>&1; then
        remoteRef=$(fetchRemoteRef || true)
    fi
    installUrl="https://raw.githubusercontent.com/neil1123-vip/padm/main/install.sh"
    [[ -n "${remoteRef}" ]] && installUrl="https://raw.githubusercontent.com/neil1123-vip/padm/${remoteRef}/install.sh"

    if [[ "${release}" == "alpine" ]]; then
        if ! wget -c -q -P "${tmpDir}/" -N "${installUrl}"; then
            padmRemoveCleanupPath "${tmpDir}" 2>/dev/null || rm -rf "${tmpDir}"
            errorCard "更新入口下载失败"
            return 1
        fi
    elif ! downloadFile -P "${tmpDir}/" "${installUrl}"; then
        padmRemoveCleanupPath "${tmpDir}" 2>/dev/null || rm -rf "${tmpDir}"
        errorCard "更新入口下载失败"
        return 1
    fi

    if ! padmEntryScriptReady "${newInstall}"; then
        padmRemoveCleanupPath "${tmpDir}" 2>/dev/null || rm -rf "${tmpDir}"
        errorCard "新版入口校验失败，已保留旧入口"
        return 1
    fi

    if ! padmCreateTempFileForTarget installStage "${installPath}" install; then
        padmRemoveCleanupPath "${tmpDir}" 2>/dev/null || rm -rf "${tmpDir}"
        errorCard "更新入口暂存失败，已取消更新"
        return 1
    fi
    if ! cp -p "${newInstall}" "${installStage}"; then
        padmRemoveCleanupPath "${installStage}" 2>/dev/null || true
        padmRemoveCleanupPath "${tmpDir}" 2>/dev/null || rm -rf "${tmpDir}"
        errorCard "更新入口暂存失败，已取消更新"
        return 1
    fi

    if ! removeManagedFileIfPresent "${backupPath}"; then
        padmRemoveCleanupPath "${installStage}" 2>/dev/null || true
        padmRemoveCleanupPath "${tmpDir}" 2>/dev/null || rm -rf "${tmpDir}"
        errorCard "旧入口备份清理失败，已取消更新"
        return 1
    fi
    if [[ -f "${installPath}" ]] && ! backupManagedFileToPath "${installPath}" "${backupPath}" 700; then
        padmRemoveCleanupPath "${installStage}" 2>/dev/null || true
        padmRemoveCleanupPath "${tmpDir}" 2>/dev/null || rm -rf "${tmpDir}"
        errorCard "旧入口备份失败，已取消更新"
        return 1
    fi
    if ! commitGeneratedFile "${installStage}" "${installPath}" 700; then
        removeManagedFilesIfPresentIgnoreFailure "${backupPath}"
        padmRemoveCleanupPath "${installStage}" 2>/dev/null || true
        padmRemoveCleanupPath "${tmpDir}" 2>/dev/null || rm -rf "${tmpDir}"
        errorCard "更新入口提交失败，已取消更新"
        return 1
    fi
    padmRemoveCleanupPath "${tmpDir}" 2>/dev/null || rm -rf "${tmpDir}"

    successCard "更新入口已下载，正在重新打开新版脚本"
    if PADM_FORCE_SCRIPT_MODULE_REFRESH=1 PADM_SCRIPT_MODULE_REF="${remoteRef}" "${installPath}" RefreshScriptModules; then
        removeManagedFilesIfPresentIgnoreFailure "${backupPath}"
        exit 0
    fi

    if [[ -f "${backupPath}" ]]; then
        if restorePadmEntryBackup "${backupPath}" "${installPath}" >/dev/null 2>&1; then
            errorCard "新版入口执行失败，已恢复旧入口"
        else
            local restoreMessage
            coreSetPairedFileRestoreFailureMessage restoreMessage "新版入口执行失败" "旧入口" "${installPath}" "${backupPath}"
            errorCard "${restoreMessage}"
        fi
    else
        errorCard "新版入口执行失败，旧入口备份不存在"
    fi
    menuLine "$(uiStyle warn "请手动执行下面命令重新更新")"
    menuLine "$(uiStyle value "wget -O /root/install.sh https://raw.githubusercontent.com/neil1123-vip/padm/main/install.sh && chmod 700 /root/install.sh && /root/install.sh")"
    echo
    return 1
}

# 网络优化
if ! declare -p PADM_BBR_SYSCTL_CONF >/dev/null 2>&1; then
    readonly PADM_BBR_SYSCTL_CONF="/etc/sysctl.d/99-padm-bbr.conf"
fi
if ! declare -p PADM_BBR_STATE_FILE >/dev/null 2>&1; then
    readonly PADM_BBR_STATE_FILE="/etc/padm/padm-bbr.state"
fi

bbrTmpPath() {
    local template=$1
    padmFallbackTmpFilePath "${template}"
}

bbrSysctlLog() {
    bbrTmpPath padm-bbr-sysctl.log
}

bbrStateTempTemplate() {
    bbrTmpPath 'padm-bbr-state.XXXXXX'
}

bbrSysctlTempTemplate() {
    bbrTmpPath 'padm-bbr-sysctl.XXXXXX'
}

readSysctlValue() {
    local key=$1
    sysctl -n "${key}" 2>/dev/null || true
}

padmBbrAvailable() {
    local available
    available="$(readSysctlValue net.ipv4.tcp_available_congestion_control)"
    [[ " ${available} " == *" bbr "* ]]
}

bbrEnableFailureCard() {
    statusCard "BBR 启用失败" "$@"
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

    commitGeneratedFile "${tmpFile}" "${targetFile}" 644
}

restorePadmBbrRuntime() {
    local congestion=$1
    local qdisc=$2
    local logFile
    logFile=$(bbrSysctlLog)

    sysctl -w "net.ipv4.tcp_congestion_control=${congestion}" >>"${logFile}" 2>&1 || true
    sysctl -w "net.core.default_qdisc=${qdisc}" >>"${logFile}" 2>&1 || true
}

readPadmBbrStateValue() {
    local key=$1
    local stateFile=${2:-${PADM_BBR_STATE_FILE}}
    local value
    [[ -f "${stateFile}" ]] || return 1
    value=$(awk -F= -v key="${key}" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "${stateFile}") || return 1
    [[ "${value}" =~ ^[A-Za-z0-9_.+-]+$ ]] || return 1
    printf '%s\n' "${value}"
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

    local previousCongestion previousQdisc stateTmp sysctlTmp logFile
    logFile=$(bbrSysctlLog)
    previousCongestion="$(readSysctlValue net.ipv4.tcp_congestion_control)"
    previousQdisc="$(readSysctlValue net.core.default_qdisc)"
    previousCongestion=${previousCongestion:-cubic}
    previousQdisc=${previousQdisc:-fq_codel}

    padmEnsureSafeDirectory "$(dirname "${PADM_BBR_STATE_FILE}")" || { bbrEnableFailureCard "状态目录创建失败"; bbrInstall; return; }
    padmCreateTempPath stateTmp "$(bbrStateTempTemplate)" || { bbrEnableFailureCard "无法创建状态临时文件"; bbrInstall; return; }
    cat >"${stateTmp}" <<EOF
previous_congestion=${previousCongestion}
previous_qdisc=${previousQdisc}
EOF
    if ! commitPadmBbrFile "${stateTmp}" "${PADM_BBR_STATE_FILE}"; then
        padmRemoveCleanupPath "${stateTmp}"
        bbrEnableFailureCard "状态文件提交失败，未改动 sysctl 配置"
        bbrInstall
        return
    fi

    if ! padmCreateTempPath sysctlTmp "$(bbrSysctlTempTemplate)"; then
        if ! removeManagedFileIfPresent "${PADM_BBR_STATE_FILE}"; then
            local cleanupFailureMessage
            coreSetManualCheckMessage cleanupFailureMessage "无法创建 sysctl 临时文件，且状态文件清理失败" " ${PADM_BBR_STATE_FILE}"
            bbrEnableFailureCard "${cleanupFailureMessage}"
        else
            bbrEnableFailureCard "无法创建 sysctl 临时文件，已删除本次状态记录"
        fi
        bbrInstall
        return
    fi
    cat >"${sysctlTmp}" <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    if ! commitPadmBbrFile "${sysctlTmp}" "${PADM_BBR_SYSCTL_CONF}"; then
        padmRemoveCleanupPath "${sysctlTmp}"
        if ! removeManagedFileIfPresent "${PADM_BBR_STATE_FILE}"; then
            local cleanupFailureMessage
            coreSetManualCheckMessage cleanupFailureMessage "sysctl 配置提交失败，且状态文件清理失败" " ${PADM_BBR_STATE_FILE}"
            bbrEnableFailureCard "${cleanupFailureMessage}"
        else
            bbrEnableFailureCard "sysctl 配置提交失败，已删除本次状态记录"
        fi
        bbrInstall
        return
    fi

    if ! sysctl -p "${PADM_BBR_SYSCTL_CONF}" >"${logFile}" 2>&1; then
        if ! removeManagedFilesIfPresent "${PADM_BBR_SYSCTL_CONF}" "${PADM_BBR_STATE_FILE}"; then
            restorePadmBbrRuntime "${previousCongestion}" "${previousQdisc}"
            local applyCleanupFailureMessage
            coreSetPairedFileManualCheckMessage applyCleanupFailureMessage "sysctl 应用失败，且本次写入清理失败" "${PADM_BBR_SYSCTL_CONF}" "${PADM_BBR_STATE_FILE}"
            bbrEnableFailureCard "${applyCleanupFailureMessage}" "日志：${logFile}"
            bbrInstall
            return
        fi
        restorePadmBbrRuntime "${previousCongestion}" "${previousQdisc}"
        bbrEnableFailureCard "sysctl 应用失败，已删除本次写入并尝试恢复原运行值" "日志：${logFile}"
        bbrInstall
        return
    fi

    if [[ "$(readSysctlValue net.ipv4.tcp_congestion_control)" == "bbr" && "$(readSysctlValue net.core.default_qdisc)" == "fq" ]]; then
        statusCard "BBR 已启用" "当前拥塞控制：bbr" "当前默认 qdisc：fq"
    else
        if ! removeManagedFilesIfPresent "${PADM_BBR_SYSCTL_CONF}" "${PADM_BBR_STATE_FILE}"; then
            restorePadmBbrRuntime "${previousCongestion}" "${previousQdisc}"
            local stateMismatchCleanupFailureMessage
            coreSetPairedFileManualCheckMessage stateMismatchCleanupFailureMessage "配置已应用但当前状态未完全匹配，且本次写入清理失败" "${PADM_BBR_SYSCTL_CONF}" "${PADM_BBR_STATE_FILE}"
            bbrEnableFailureCard "${stateMismatchCleanupFailureMessage}" "请查看下方状态和 ${logFile}"
            printNetworkOptimizationStatus
            bbrInstall
            return
        fi
        restorePadmBbrRuntime "${previousCongestion}" "${previousQdisc}"
        bbrEnableFailureCard "配置已应用但当前状态未完全匹配，已删除本次写入并尝试恢复原运行值" "请查看下方状态和 ${logFile}"
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
        previousCongestion=$(readPadmBbrStateValue previous_congestion "${PADM_BBR_STATE_FILE}" || printf '%s' "${previousCongestion}")
        previousQdisc=$(readPadmBbrStateValue previous_qdisc "${PADM_BBR_STATE_FILE}" || printf '%s' "${previousQdisc}")
    fi

    if ! removeManagedFilesIfPresent "${PADM_BBR_SYSCTL_CONF}" "${PADM_BBR_STATE_FILE}"; then
        local disableCleanupFailureMessage
        coreSetPairedFileManualCheckMessage disableCleanupFailureMessage "配置文件清理失败" "${PADM_BBR_SYSCTL_CONF}" "${PADM_BBR_STATE_FILE}"
        statusCard "padm BBR 关闭失败" "${disableCleanupFailureMessage}"
        printNetworkOptimizationStatus
        bbrInstall
        return
    fi
    local logFile
    logFile=$(bbrSysctlLog)
    sysctl --system >"${logFile}" 2>&1 || true
    sysctl -w "net.ipv4.tcp_congestion_control=${previousCongestion}" >>"${logFile}" 2>&1 || true
    sysctl -w "net.core.default_qdisc=${previousQdisc}" >>"${logFile}" 2>&1 || true
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
        coreCancelledStatusCard "未运行第三方 TCP 加速脚本"
        bbrInstall
        return
    fi

    local tmpDir
    local scriptPath
    if ! padmCreateTmpRootPath tmpDir padm-tcpx.XXXXXX -d; then
        statusCard "下载失败" "第三方脚本临时目录创建失败" "未执行任何第三方脚本"
        bbrInstall
        return
    fi
    scriptPath="${tmpDir}/tcpx.sh"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${PADM_THIRD_PARTY_TCP_SCRIPT_URL}" -o "${scriptPath}"
    else
        wget -O "${scriptPath}" "${PADM_THIRD_PARTY_TCP_SCRIPT_URL}"
    fi

    if [[ ! -s "${scriptPath}" ]] || ! grep -q "^#!" "${scriptPath}"; then
        padmRemoveCleanupPath "${tmpDir}"
        statusCard "下载失败" "第三方脚本为空或格式异常" "未执行任何第三方脚本"
        bbrInstall
        return
    fi

    if ! chmod +x "${scriptPath}"; then
        padmRemoveCleanupPath "${tmpDir}"
        statusCard "下载失败" "第三方脚本权限设置失败" "未执行任何第三方脚本"
        bbrInstall
        return
    fi
    local scriptStatus=0
    "${scriptPath}" || scriptStatus=$?
    padmRemoveCleanupPath "${tmpDir}"
    return "${scriptStatus}"
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
        coreSelectionRetryAction bbrInstall
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

checkLogBackupCreate() {
    local resultVar=$1
    shift
    local backupDir
    local targetPath
    local backupIndex=0
    local -a backupArgs=()

    padmCreateTmpRootPath backupDir padm-check-log-backup.XXXXXX -d || return 1
    for targetPath in "$@"; do
        [[ -n "${targetPath}" ]] || continue
        targetPath=$(padmRequireSafeAbsolutePath "${targetPath}") || {
            padmRemoveCleanupPath "${backupDir}"
            return 1
        }
        backupArgs+=("$(printf '%06d.json' "${backupIndex}")" "${targetPath}")
        backupIndex=$((backupIndex + 1))
    done
    if ! padmWriteManagedFileBackupManifest "${backupDir}" "${backupArgs[@]}"; then
        padmRemoveCleanupPath "${backupDir}"
        return 1
    fi
    printf -v "${resultVar}" '%s' "${backupDir}"
}

checkLogBackupRestore() {
    local backupDir=$1
    padmRestoreManagedFileBackupManifest "${backupDir}"
}

checkLogRollbackOrReport() {
    local backupDir=$1
    local restoreReason=$2
    local rollbackReason=$3
    local restoreMessage
    local rollbackMessage

    if ! checkLogBackupRestore "${backupDir}"; then
        padmForgetCleanupPath "${backupDir}"
        coreSetSingleRestoreResultMessage restoreMessage "${restoreReason}" false "已恢复旧配置" "旧配置" "备份目录: ${backupDir}" || true
        errorCard "${restoreMessage}"
        return 1
    fi

    padmRemoveCleanupPath "${backupDir}"
    if [[ -n "${rollbackReason}" ]]; then
        coreSetRollbackResultMessage rollbackMessage "${restoreReason}" "${rollbackReason}"
        errorCard "${rollbackMessage}"
    fi
    return 1
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
        local logBackupDir
        local -a backupTargets=("${configPath}00_log.json")
        [[ ${realityStatus} == "7" ]] && backupTargets+=("${configPath}07_VLESS_vision_reality_inbounds.json")
        [[ ${realityStatus} == "12" ]] && backupTargets+=("${configPath}12_VLESS_XHTTP_inbounds.json")
        checkLogBackupCreate logBackupDir "${backupTargets[@]}" || {
            errorCard "日志配置备份失败，已取消修改"
            return 1
        }
        if [[ "${logStatus}" == "false" ]]; then
            realityLogShow=true
            if ! writeXrayLogConfig "${configPath}00_log.json" "${configPathLog}" true; then
                checkLogRollbackOrReport "${logBackupDir}" "写入日志配置失败" "已回滚本次日志修改"
                return 1
            fi
        elif [[ "${logStatus}" == "true" ]]; then
            realityLogShow=false
            if ! writeXrayLogConfig "${configPath}00_log.json" "${configPathLog}" false; then
                checkLogRollbackOrReport "${logBackupDir}" "写入日志配置失败" "已回滚本次日志修改"
                return 1
            fi
        fi

        if [[ ${realityStatus} == "7" ]]; then
            if ! updateRealityShowConfig "${configPath}07_VLESS_vision_reality_inbounds.json" "${realityLogShow}"; then
                checkLogRollbackOrReport "${logBackupDir}" "Reality 日志联动配置写入失败" "已回滚本次日志修改"
                return 1
            fi
        fi
        if [[ ${realityStatus} == "12" ]]; then
            if ! updateRealityShowConfig "${configPath}12_VLESS_XHTTP_inbounds.json" "${realityLogShow}"; then
                checkLogRollbackOrReport "${logBackupDir}" "Reality 日志联动配置写入失败" "已回滚本次日志修改"
                return 1
            fi
        fi
        if ! reloadCore; then
            if ! checkLogBackupRestore "${logBackupDir}"; then
                padmForgetCleanupPath "${logBackupDir}"
                local restoreMessage
                coreSetSingleRestoreResultMessage restoreMessage "日志配置更新后核心重载失败" false "已恢复旧配置" "旧配置" "备份目录: ${logBackupDir}"
                errorCard "${restoreMessage}"
                return 1
            fi
            padmRemoveCleanupPath "${logBackupDir}"
            local rollbackMessage
            coreSetRollbackResultMessage rollbackMessage "核心重载失败" "已回滚日志配置修改" reloadCore "恢复旧配置后核心重载仍失败，请检查核心服务日志"
            errorCard "${rollbackMessage}"
            return 1
        fi
        padmRemoveCleanupPath "${logBackupDir}"
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

sameInstallPath() {
    local left=$1
    local right=$2
    local leftDir rightDir leftBase rightBase
    leftDir=$(cd -- "$(dirname -- "${left}")" 2>/dev/null && pwd -P) || return 1
    rightDir=$(cd -- "$(dirname -- "${right}")" 2>/dev/null && pwd -P) || return 1
    leftBase=$(basename -- "${left}")
    rightBase=$(basename -- "${right}")
    [[ "${leftDir}/${leftBase}" == "${rightDir}/${rightBase}" ]]
}

syncInstallManagedFile() {
    local sourcePath=$1
    local targetPath=$2
    local mode=${3:-644}
    local targetParent stagedFile

    [[ -f "${sourcePath}" ]] || return 0
    if sameInstallPath "${sourcePath}" "${targetPath}"; then
        return 0
    fi
    targetPath=$(padmResolveManagedAbsolutePath "${targetPath}") || return 1
    targetParent=$(dirname -- "${targetPath}")
    padmEnsureSafeDirectory "${targetParent}" || return 1
    padmCreateTempFileForTarget stagedFile "${targetPath}" install || return 1
    if ! cp -p "${sourcePath}" "${stagedFile}"; then
        padmRemoveCleanupPath "${stagedFile}"
        return 1
    fi
    commitGeneratedFile "${stagedFile}" "${targetPath}" "${mode}" || {
        padmRemoveCleanupPath "${stagedFile}"
        return 1
    }
}

syncInstallMetadataFile() {
    local sourcePath=$1
    local targetPath=$2
    syncInstallManagedFile "${sourcePath}" "${targetPath}" 644
}

cleanupInstallSyncPath() {
    local targetPath=$1
    [[ -n "${targetPath}" ]] || return 0
    if declare -F removeManagedPathIfPresent >/dev/null 2>&1; then
        removeManagedPathIfPresentIgnoreFailure "${targetPath}"
        return 0
    fi
    padmRemoveCleanupPath "${targetPath}" 2>/dev/null || rm -rf -- "${targetPath}"
}

preserveInstallSyncPath() {
    local targetPath=$1
    [[ -n "${targetPath}" ]] || return 0
    if declare -F padmForgetCleanupPath >/dev/null 2>&1; then
        padmForgetCleanupPath "${targetPath}" >/dev/null 2>&1 || true
    fi
}

syncInstallDirectoryTree() {
    local sourceDir=$1
    local targetDir=$2
    local targetParent targetName stageRoot stageDir backupRoot= backupPath=
    local restoreStatus=0

    sourceDir=$(padmResolveManagedAbsolutePath "${sourceDir}") || return 1
    targetDir=$(padmResolveManagedAbsolutePath "${targetDir}") || return 1
    [[ -d "${sourceDir}" ]] || return 0
    if sameInstallPath "${sourceDir}" "${targetDir}"; then
        return 0
    fi

    targetParent=$(dirname -- "${targetDir}")
    targetName=$(basename -- "${targetDir}")
    padmEnsureSafeDirectory "${targetParent}" || return 1

    padmCreateTempPathCompat stageRoot -d "${targetParent}/.${targetName}.padm-stage.XXXXXX" || return 1
    stageDir="${stageRoot}/${targetName}"
    if ! cp -R "${sourceDir}" "${stageDir}"; then
        cleanupInstallSyncPath "${stageRoot}"
        return 1
    fi

    if [[ -e "${targetDir}" || -L "${targetDir}" ]]; then
        padmCreateTempPathCompat backupRoot -d "${targetParent}/.${targetName}.padm-backup.XXXXXX" || {
            cleanupInstallSyncPath "${stageRoot}"
            return 1
        }
        backupPath="${backupRoot}/${targetName}"
        if ! mv "${targetDir}" "${backupPath}"; then
            cleanupInstallSyncPath "${stageRoot}"
            cleanupInstallSyncPath "${backupRoot}"
            return 1
        fi
    fi

    if ! mv "${stageDir}" "${targetDir}"; then
        if [[ -n "${backupPath}" ]] && ! mv "${backupPath}" "${targetDir}" >/dev/null 2>&1; then
            restoreStatus=1
            preserveInstallSyncPath "${backupRoot}"
        fi
        cleanupInstallSyncPath "${stageRoot}"
        [[ "${restoreStatus}" -eq 0 ]] && cleanupInstallSyncPath "${backupRoot}"
        return 1
    fi

    cleanupInstallSyncPath "${stageRoot}"
    cleanupInstallSyncPath "${backupRoot}"
}

# 脚本快捷方式
aliasInstall() {
    local sourceInstall="${SCRIPT_DIR}/install.sh"
    local targetDir="${PADM_INSTALL_DIR:-/etc/padm}"
    local homeInstall=
    if ! padmIsSafeAbsolutePath "${targetDir}"; then
        errorCard "脚本安装目录异常"
        return 1
    fi
    if [[ ! -f "${sourceInstall}" && -n "${HOME:-}" ]]; then
        homeInstall="${HOME%/}/install.sh"
        if padmIsSafeAbsolutePath "${homeInstall}" && [[ -f "${homeInstall}" ]]; then
            sourceInstall="${homeInstall}"
        fi
    fi

    if [[ -f "${sourceInstall}" && -d "${targetDir}" ]] && padmEntryScriptReady "${sourceInstall}"; then
        syncInstallDirectoryTree "${SCRIPT_DIR}/shell" "${targetDir}/shell" || return 1
        syncInstallDirectoryTree "${SCRIPT_DIR}/documents" "${targetDir}/documents" || return 1
        syncInstallDirectoryTree "${SCRIPT_DIR}/assets" "${targetDir}/assets" || return 1
        syncInstallMetadataFile "${SCRIPT_DIR}/.padm-module-manifest" "${targetDir}/.padm-module-manifest" || return 1
        syncInstallMetadataFile "${SCRIPT_DIR}/.padm-ref" "${targetDir}/.padm-ref" || return 1
        syncInstallMetadataFile "${SCRIPT_DIR}/.padm-entry-ref" "${targetDir}/.padm-entry-ref" || return 1
        rm -f "${targetDir}/xray/README.md"
        syncInstallManagedFile "${sourceInstall}" "${targetDir}/install.sh" 700 || return 1
        local shortcutCreated=
        if [[ -d "/usr/bin/" ]]; then
            if [[ ! -f "/usr/bin/padm" ]]; then
                ln -s "${targetDir}/install.sh" /usr/bin/padm
                chmod 700 /usr/bin/padm
                shortcutCreated=true
            fi
        elif [[ -d "/usr/sbin" ]]; then
            if [[ ! -f "/usr/sbin/padm" ]]; then
                ln -s "${targetDir}/install.sh" /usr/sbin/padm
                chmod 700 /usr/sbin/padm
                shortcutCreated=true
            fi
        fi
        if [[ -n "${homeInstall}" && "${sourceInstall}" == "${homeInstall}" ]]; then
            rm -f -- "${sourceInstall}"
        fi
        if [[ "${shortcutCreated}" == "true" ]]; then
            echoContent green "快捷方式创建成功，可执行[padm]重新打开脚本"
        fi
    fi
}
