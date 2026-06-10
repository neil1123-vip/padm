#!/usr/bin/env bash

subscribeLocalBaseDir() {
    printf '%s' "${PADM_SUBSCRIBE_LOCAL_DIR:-/etc/padm/subscribe_local}"
}

subscribePublicBaseDir() {
    printf '%s' "${PADM_SUBSCRIBE_DIR:-/etc/padm/subscribe}"
}

ensureSubscriptionControlNginxLocation() {
    return 1
}


writeSubscribeNginxConfig() {
    local targetPath="${nginxConfigPath}subscribe.conf"
    local tmpPath
    local backupPath=
    local tmpBase="${TMPDIR:-/tmp}"
    local nginxTestLog="${tmpBase%/}/padm-subscribe-nginx-test.log"
    padmCreateTempFileForTarget tmpPath "${targetPath}" subscribe || return 1
    if ! cat >"${tmpPath}"; then
        padmRemoveCleanupPath "${tmpPath}"
        return 1
    fi
    if command -v nginx >/dev/null 2>&1; then
        if [[ -f "${targetPath}" ]]; then
            padmCreateTempFileForTarget backupPath "${targetPath}" backup || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
            cp "${targetPath}" "${backupPath}" || { padmRemoveCleanupPath "${tmpPath}"; padmRemoveCleanupPath "${backupPath}"; return 1; }
        fi
        if ! commitGeneratedFile "${tmpPath}" "${targetPath}" 644; then
            padmRemoveCleanupPath "${tmpPath}"
            [[ -n "${backupPath}" ]] && padmRemoveCleanupPath "${backupPath}"
            return 1
        fi
        if ! nginx -t >"${nginxTestLog}" 2>&1; then
            if [[ -n "${backupPath}" && -f "${backupPath}" ]]; then
                commitGeneratedFile "${backupPath}" "${targetPath}" 644 || return 1
            else
                rm -f "${targetPath}" || return 1
            fi
            return 1
        fi
        [[ -n "${backupPath}" ]] && padmRemoveCleanupPath "${backupPath}"
    else
        commitGeneratedFile "${tmpPath}" "${targetPath}" 644 || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
    fi
}

availableSubscribeCertificateDomain() {
    local certDir="${PADM_TLS_DIR:-/etc/padm/tls}"
    local certFile domainName
    for certFile in "${certDir}"/*.crt; do
        [[ -s "${certFile}" ]] || continue
        domainName=$(basename "${certFile}" .crt)
        [[ -s "${certDir}/${domainName}.key" ]] || continue
        printf '%s\n' "${domainName}"
        return 0
    done
    return 1
}

resolveSubscribeServerName() {
    if [[ -n "${currentHost:-}" ]]; then
        printf '%s\n' "${currentHost}"
        return 0
    fi
    if [[ -n "${domain:-}" ]]; then
        printf '%s\n' "${domain}"
        return 0
    fi
    availableSubscribeCertificateDomain
}

runSubscribeNginxAction() {
    local action=$1
    local previousAllowFailure="${SERVICE_QUEUE_ALLOW_FAILURE:-}"
    SERVICE_QUEUE_ALLOW_FAILURE=true
    handleNginx "${action}"
    local rc=$?
    SERVICE_QUEUE_ALLOW_FAILURE="${previousAllowFailure}"
    return "${rc}"
}

# 安装订阅服务
installSubscribe() {
    readNginxSubscribe
    local nginxSubscribeListen=
    local nginxSubscribeSSL=
    local serverName=
    local SSLType=
    local listenIPv6=
    local subscribeServerName=
    if [[ -n "${AUTO_SUBSCRIBE_PORT:-}" && "${subscribePort}" != "${AUTO_SUBSCRIBE_PORT}" ]]; then
        subscribePort=
    fi
    if [[ -z "${subscribePort}" ]]; then

        nginxVersion=$(nginx -v 2>&1)

        if echo "${nginxVersion}" | grep -q "not found" || [[ -z "${nginxVersion}" ]]; then
            menuLine "$(uiStyle warn "未检测到 nginx，无法使用订阅服务")"
            autoConfirm install_nginx "未检测到 nginx，是否安装？" n installNginxStatus
            if [[ "${installNginxStatus}" == "y" ]]; then
                installNginxTools
            else
                errorCard "放弃安装nginx\n"
                exit 0
            fi
        fi
        echoContent title "开始配置订阅，请输入订阅的端口"

        readSingBoxPortResult result "${AUTO_SUBSCRIBE_PORT:-${subscribePort}}" false || return 1
        PADM_NGINX_BLOG_REINSTALL_PROMPT=false nginxBlog
        echo
        subscribeServerName=$(resolveSubscribeServerName || true)
        if [[ -z "${subscribeServerName}" ]]; then
            errorCard "订阅服务需要 HTTPS 域名" "未发现可用于订阅服务的 TLS 域名或证书" "请先在 站点与证书 中配置域名证书，或安装时提供 --domain"
            return 1
        fi

        SSLType="ssl"
        serverName="server_name ${subscribeServerName};"
        nginxSubscribeSSL="ssl_certificate ${PADM_TLS_DIR:-/etc/padm/tls}/${subscribeServerName}.crt;ssl_certificate_key ${PADM_TLS_DIR:-/etc/padm/tls}/${subscribeServerName}.key;"
        if hasIPv6Connectivity; then
            listenIPv6="listen [::]:${result[-1]} ${SSLType};"
        fi
        if echo "${nginxVersion}" | grep -q "1.25" && [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $3}') -gt 0 ]] || [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $2}') -gt 25 ]]; then
            nginxSubscribeListen="listen ${result[-1]} ${SSLType} so_keepalive=on;http2 on;${listenIPv6}"
        else
            nginxSubscribeListen="listen ${result[-1]} ${SSLType} so_keepalive=on;${listenIPv6}"
        fi

        if ! writeSubscribeNginxConfig <<EOF
server {
    ${nginxSubscribeListen}
    ${serverName}
    ${nginxSubscribeSSL}
    ssl_protocols              TLSv1.2 TLSv1.3;
    ssl_ciphers                TLS13_AES_128_GCM_SHA256:TLS13_AES_256_GCM_SHA384:TLS13_CHACHA20_POLY1305_SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers  on;

    resolver                   1.1.1.1 valid=60s;
    resolver_timeout           2s;
    client_max_body_size 100m;
    root ${nginxStaticPath};
    location ~ ^/s/(clashMeta|default|clashMetaProfiles|sing-box|sing-box_profiles)/(.*) {
        default_type 'text/plain; charset=utf-8';
        alias /etc/padm/subscribe/\$1/\$2;
    }
    location / {
    }
}
EOF
        then
            errorCard "订阅 Nginx 配置校验失败，已回滚"
            return 1
        fi
        if ! installSubscriptionControlService; then
            errorCard "订阅控制服务安装失败"
            return 1
        fi
        bootStartup nginx
        if ! runSubscribeNginxAction stop || ! runSubscribeNginxAction start; then
            errorCard "订阅 Nginx 服务重载失败"
            return 1
        fi
    fi
    if [[ -z $(pgrep -f "nginx") ]]; then
        if ! runSubscribeNginxAction start; then
            errorCard "订阅 Nginx 服务启动失败"
            return 1
        fi
    fi
}

# 卸载订阅服务
unInstallSubscribe() {
    if [[ ! -e "${nginxConfigPath}subscribe.conf" && ! -L "${nginxConfigPath}subscribe.conf" ]]; then
        return 0
    fi
    rm -rf "${nginxConfigPath}subscribe.conf" >/dev/null 2>&1
}


fetchRemoteSubscribeContent() {
    local url=$1
    curl -fsSL --connect-timeout 5 --max-time 15 "${url}" 2>/dev/null
}

appendUniqueLines() {
    local content=$1
    local targetPath=$2
    local tmpPath

    padmCreateTempFileForTarget tmpPath "${targetPath}" unique || return 1
    {
        [[ -f "${targetPath}" ]] && cat "${targetPath}"
        printf '%s\n' "${content}"
    } | LC_ALL=C awk 'length($0) > 0 && !seen[$0]++' >"${tmpPath}" || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
    commitGeneratedFile "${tmpPath}" "${targetPath}" 644 || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
}

mergeSingBoxSubscribeOutbounds() {
    local targetPath=$1
    local remoteContent=$2
    local tmpPath
    local remoteTmpPath

    padmCreateTempFileForTarget tmpPath "${targetPath}" subscribe || return 1
    padmCreateTempFileForTarget remoteTmpPath "${targetPath}" remote || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
    echo "${remoteContent}" >"${remoteTmpPath}" || {
        padmRemoveCleanupPath "${remoteTmpPath}"
        padmRemoveCleanupPath "${tmpPath}"
        return 1
    }
    if ! jq -s '
      .[0] as $local |
      .[1] as $remote |
      ($local | map(.tag // empty) | reduce .[] as $tag ({}; .[$tag] = true)) as $seenTags |
      $local + ($remote | map(select((.tag // "") as $tag | ($tag | length) == 0 or ($seenTags[$tag] | not))))
    ' "${targetPath}" "${remoteTmpPath}" >"${tmpPath}"; then
        padmRemoveCleanupPath "${remoteTmpPath}"
        padmRemoveCleanupPath "${tmpPath}"
        return 1
    fi
    commitGeneratedJsonFile "${tmpPath}" "${targetPath}" || { padmRemoveCleanupPath "${remoteTmpPath}"; padmRemoveCleanupPath "${tmpPath}"; return 1; }
    padmRemoveCleanupPath "${remoteTmpPath}"
}

# 更新远程订阅源
updateRemoteSubscribe() {
    local emailMD5=$1
    local email=$2
    local line=
    local tmpDir stageDir publicBase localBase defaultTarget clashTarget singBoxTarget
    local tmpBase="${TMPDIR:-/tmp}"

    padmCreateTempPath tmpDir -d "${tmpBase%/}/padm-remote-subscribe-fetch.XXXXXX" || return 1
    padmCreateTempPath stageDir -d "${tmpBase%/}/padm-remote-subscribe-stage.XXXXXX" || { padmRemoveCleanupPath "${tmpDir}"; return 1; }
    publicBase=$(subscribePublicBaseDir)
    localBase=$(subscribeLocalBaseDir)
    mkdir -p "${stageDir}/default" "${stageDir}/clashMeta" "${stageDir}/sing-box"
    defaultTarget="${stageDir}/default/${emailMD5}"
    clashTarget="${stageDir}/clashMeta/${emailMD5}"
    singBoxTarget="${stageDir}/sing-box/${email}"
    [[ -f "${publicBase}/default/${emailMD5}" ]] && cp "${publicBase}/default/${emailMD5}" "${defaultTarget}" || : >"${defaultTarget}"
    [[ -f "${publicBase}/clashMeta/${emailMD5}" ]] && cp "${publicBase}/clashMeta/${emailMD5}" "${clashTarget}" || : >"${clashTarget}"
    [[ -f "${localBase}/sing-box/${email}" ]] && cp "${localBase}/sing-box/${email}" "${singBoxTarget}" || printf '[]\n' >"${singBoxTarget}"

    while IFS= read -r line; do
        if [[ -z "${line}" ]]; then
            continue
        fi
        local subscribeType=
        local serverAlias=
        local remoteUrl=
        local clashMetaProxies=
        local default=
        local singBoxSubscribe=
        local clashFile="${tmpDir}/clash"
        local defaultFile="${tmpDir}/default"
        local singBoxFile="${tmpDir}/sing-box"
        local clashPid defaultPid singBoxPid

        IFS=':' read -r remoteHost remotePort serverAlias subscribeType <<<"${line}"
        remoteUrl="${remoteHost}:${remotePort}"

        fetchRemoteSubscribeContent "${subscribeType}://${remoteUrl}/s/clashMeta/${emailMD5}" >"${clashFile}" & clashPid=$!
        fetchRemoteSubscribeContent "${subscribeType}://${remoteUrl}/s/default/${emailMD5}" >"${defaultFile}" & defaultPid=$!
        fetchRemoteSubscribeContent "${subscribeType}://${remoteUrl}/s/sing-box_profiles/${emailMD5}" >"${singBoxFile}" & singBoxPid=$!
        wait "${clashPid}" 2>/dev/null || true
        wait "${defaultPid}" 2>/dev/null || true
        wait "${singBoxPid}" 2>/dev/null || true

        clashMetaProxies=$(sed '/proxies:/d' "${clashFile}" | sed "s/\"${email}/\"${email}_${serverAlias}/g")
        if [[ -n "${clashMetaProxies}" && "${clashMetaProxies}" != *nginx* ]]; then
            appendUniqueLines "${clashMetaProxies}" "${clashTarget}"
            successCard "clashMeta订阅 ${remoteUrl}:${email} 更新成功"
        else
            errorCard "clashMeta订阅 ${remoteUrl}:${email} 拉取失败或不存在"
        fi

        default=$(<"${defaultFile}")
        if [[ -n "${default}" && "${default}" != *nginx* ]]; then
            default=$(echo "${default}" | { base64 -d 2>/dev/null || true; } | sed "s/#${email}/#${email}_${serverAlias}/g")
            if [[ -n "${default}" ]]; then
                appendUniqueLines "${default}" "${defaultTarget}"
                successCard "通用订阅 ${remoteUrl}:${email} 更新成功"
            else
                errorCard "通用订阅 ${remoteUrl}:${email} 解码失败"
            fi
        else
            errorCard "通用订阅 ${remoteUrl}:${email} 拉取失败或不存在"
        fi

        singBoxSubscribe=$(<"${singBoxFile}")
        if [[ -n "${singBoxSubscribe}" && "${singBoxSubscribe}" != *nginx* ]] && echo "${singBoxSubscribe}" | jq empty >/dev/null 2>&1; then
            if ! singBoxSubscribe=$(jq --arg email "${email}" --arg alias "${serverAlias}" 'map(if ((.tag // "") | startswith($email)) then .tag = ($email + "_" + $alias + (.tag[($email | length):])) else . end)' <<<"${singBoxSubscribe}"); then
                padmRemoveCleanupPath "${tmpDir}"
                padmRemoveCleanupPath "${stageDir}"
                return 1
            fi
            if ! mergeSingBoxSubscribeOutbounds "${singBoxTarget}" "${singBoxSubscribe}"; then
                padmRemoveCleanupPath "${tmpDir}"
                padmRemoveCleanupPath "${stageDir}"
                return 1
            fi
            successCard "sing-box订阅 ${remoteUrl}:${email} 更新成功"
        else
            errorCard "sing-box订阅 ${remoteUrl}:${email} 拉取失败或不存在"
        fi
        rm -f "${clashFile}" "${defaultFile}" "${singBoxFile}"
    done < <(listRemoteSubscribeSources)

    mkdir -p "${publicBase}/default" "${publicBase}/clashMeta" "${localBase}/sing-box" || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    commitGeneratedFile "${defaultTarget}" "${publicBase}/default/${emailMD5}" 644 || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    commitGeneratedFile "${clashTarget}" "${publicBase}/clashMeta/${emailMD5}" 644 || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    commitGeneratedJsonFile "${singBoxTarget}" "${localBase}/sing-box/${email}" || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    padmRemoveCleanupPath "${tmpDir}"
    padmRemoveCleanupPath "${stageDir}"
}
