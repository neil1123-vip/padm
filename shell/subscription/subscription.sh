#!/usr/bin/env bash

subscribeLocalBaseDir() {
    printf '%s' "${PADM_SUBSCRIBE_LOCAL_DIR:-/etc/padm/subscribe_local}"
}

subscribePublicBaseDir() {
    printf '%s' "${PADM_SUBSCRIBE_DIR:-/etc/padm/subscribe}"
}

resolveSubscribeNginxAccessLogFile() {
    local subscribeConfig="${nginxConfigPath:-/etc/nginx/conf.d/}subscribe.conf"
    local logPath=

    if [[ -f "${subscribeConfig}" ]]; then
        logPath=$(awk '
            /^[[:space:]]*access_log[[:space:]]+/ {
                if ($2 !~ /^(off|syslog:)/) {
                    gsub(/;$/, "", $2)
                    print $2
                    exit
                }
            }
        ' "${subscribeConfig}" 2>/dev/null || true)
    fi
    if [[ -n "${logPath}" ]]; then
        printf '%s\n' "${logPath}"
        return 0
    fi

    if [[ -d /www/server/panel/vhost/nginx ]]; then
        if [[ -n "${domain:-}" && -e "/www/wwwlogs/${domain}.log" ]]; then
            printf '/www/wwwlogs/%s.log\n' "${domain}"
            return 0
        fi
        if [[ -n "${currentHost:-}" && -e "/www/wwwlogs/${currentHost}.log" ]]; then
            printf '/www/wwwlogs/%s.log\n' "${currentHost}"
            return 0
        fi
        if [[ -e /www/wwwlogs/access.log ]]; then
            printf '/www/wwwlogs/access.log\n'
            return 0
        fi
    fi

    if [[ -d /opt/1panel/apps/openresty/openresty/www/sites ]]; then
        if [[ -n "${domain:-}" && -e "/opt/1panel/apps/openresty/openresty/www/sites/${domain}/log/access.log" ]]; then
            printf '/opt/1panel/apps/openresty/openresty/www/sites/%s/log/access.log\n' "${domain}"
            return 0
        fi
        if [[ -n "${currentHost:-}" && -e "/opt/1panel/apps/openresty/openresty/www/sites/${currentHost}/log/access.log" ]]; then
            printf '/opt/1panel/apps/openresty/openresty/www/sites/%s/log/access.log\n' "${currentHost}"
            return 0
        fi
        if [[ -e /opt/1panel/apps/openresty/openresty/logs/access.log ]]; then
            printf '/opt/1panel/apps/openresty/openresty/logs/access.log\n'
            return 0
        fi
    fi

    printf '/var/log/nginx/access.log\n'
}

subscriptionRemoteSubscribeSourcesForAccount() {
    local email=$1
    local groupId
    local userJson
    local allowedSources
    groupId=$(activeSubscriptionGroupId)
    userJson=$(subscriptionSyncFindUserByAccountName "${email}" "${groupId}" 2>/dev/null) || return 0
    [[ -n "${userJson}" ]] || return 0
    if ! jq -e '.enabled == true' <<<"${userJson}" >/dev/null 2>&1; then
        return 0
    fi
    allowedSources=$(jq -c '.allowed_sources // []' <<<"${userJson}") || return 1
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" --argjson allowed "${allowedSources}" '
      .groups[] | select(.id == $groupId) as $group |
      if ($allowed | length) == 0 then
        empty
      elif ($allowed | index("*")) then
        $group.sources[]? | select(.role != "main" and .enabled == true) | "\(.host):\(.port):\(.id):\(.scheme)"
      else
        $group.sources[]? | select(.role != "main" and .enabled == true and (.id as $sid | $allowed | index($sid))) | "\(.host):\(.port):\(.id):\(.scheme)"
      end'
}

subscriptionPublishHasRemoteSources() {
    local accounts=$1
    local account
    while IFS= read -r account; do
        [[ -n "${account}" ]] || continue
        if [[ -n "$(subscriptionRemoteSubscribeSourcesForAccount "${account}" 2>/dev/null)" ]]; then
            return 0
        fi
    done <<<"${accounts}"
    [[ -n "$(listRemoteSubscribeSources 2>/dev/null)" ]]
}

subscriptionMainPublishSourceAvailable() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateRead -e --arg groupId "${groupId}" '
      .groups[] | select(.id == $groupId) |
      any(.sources[]?; .id == "main" and ((.enabled // true) == true))
    ' >/dev/null 2>&1
}

subscriptionAccountHasPublishSource() {
    local accountName=$1
    local groupId
    local userJson
    groupId=$(activeSubscriptionGroupId)
    userJson=$(subscriptionSyncFindUserByAccountName "${accountName}" "${groupId}" 2>/dev/null) || return 1
    [[ -n "${userJson}" ]] || return 1
    jq -e '.enabled == true' <<<"${userJson}" >/dev/null 2>&1 || return 1
    if jq -e '((.allowed_sources // []) | index("*") or index("main"))' <<<"${userJson}" >/dev/null 2>&1; then
        if subscriptionMainPublishSourceAvailable; then
            return 0
        fi
    fi
    [[ -n "$(subscriptionRemoteSubscribeSourcesForAccount "${accountName}" 2>/dev/null)" ]]
}

ensureSubscriptionControlNginxLocation() {
    return 1
}

subscribeNginxConfigWriteError() {
    SUBSCRIBE_NGINX_CONFIG_WRITE_ERROR=$1
    return 1
}

writeSubscribeNginxConfig() {
    local targetPath="${nginxConfigPath}subscribe.conf"
    local tmpPath
    local backupPath=
    local tmpBase="${TMPDIR:-/tmp}"
    local nginxTestLog="${tmpBase%/}/padm-subscribe-nginx-test.log"
    SUBSCRIBE_NGINX_CONFIG_WRITE_ERROR=
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
                commitGeneratedFile "${backupPath}" "${targetPath}" 644 || {
                    padmForgetCleanupPath "${backupPath}"
                    subscribeNginxConfigWriteError "订阅 Nginx 配置校验失败，且旧配置恢复失败，请手动检查 ${targetPath} 和 ${backupPath}"
                    return 1
                }
            else
                rm -f "${targetPath}" || subscribeNginxConfigWriteError "订阅 Nginx 配置校验失败，且新配置清理失败，请手动检查 ${targetPath}" || return 1
            fi
            return 1
        fi
        [[ -n "${backupPath}" ]] && padmRemoveCleanupPath "${backupPath}"
        return 0
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
            errorCard "${SUBSCRIBE_NGINX_CONFIG_WRITE_ERROR:-订阅 Nginx 配置校验失败，已回滚}"
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
    local targetPath
    if ! targetPath=$(nginxConfigFilePath subscribe.conf); then
        padmShowUnsafePathError "卸载订阅 Nginx 配置"
        return 1
    fi
    if [[ ! -e "${targetPath}" && ! -L "${targetPath}" ]]; then
        return 0
    fi
    rm -f -- "${targetPath}" >/dev/null 2>&1
}


fetchRemoteSubscribeContent() {
    local url=$1
    curl -fsSL --connect-timeout 5 --max-time 15 "${url}" 2>/dev/null
}

fetchRemoteControlledSubscribePayload() {
    local source=$1
    local account=$2
    local token
    local url
    local payload
    token=$(subscriptionRemoteControlToken "${source}") || return 1
    [[ -n "${token}" ]] || return 1
    url=$(subscriptionRemoteControlUrl "${source}" subscribe) || return 1
    payload=$(jq -nc --arg account "${account}" '{account:$account}') || return 1
    curl -sS --connect-timeout 5 --max-time 30 \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${token}" \
        -X POST --data "${payload}" "${url}" 2>/dev/null
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
    local source=
    local sourceLines=
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

    sourceLines=$(subscriptionRemoteSubscribeSourcesForAccount "${email}" 2>/dev/null) || sourceLines=
    if [[ -z "${sourceLines}" ]]; then
        sourceLines=$(listRemoteSubscribeSources)
    fi

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
        local controlledResponse=
        local clashFile="${tmpDir}/clash"
        local defaultFile="${tmpDir}/default"
        local singBoxFile="${tmpDir}/sing-box"
        local clashPid defaultPid singBoxPid

        IFS=':' read -r remoteHost remotePort serverAlias subscribeType <<<"${line}"
        remoteUrl="${remoteHost}:${remotePort}"
        source=$(subscriptionGroupsStateRead -c --arg groupId "$(activeSubscriptionGroupId)" --arg id "${serverAlias}" '.groups[] | select(.id == $groupId) | .sources[]? | select(.id == $id)' 2>/dev/null) || source=
        if [[ -n "${source}" ]] && subscriptionRemoteSourceUsesWireGuard "${source}"; then
            controlledResponse=$(fetchRemoteControlledSubscribePayload "${source}" "${email}" 2>/dev/null || true)
            if [[ -n "${controlledResponse}" ]] && jq -e '.ok == true' <<<"${controlledResponse}" >/dev/null 2>&1; then
                jq -r '.clash_meta // ""' <<<"${controlledResponse}" >"${clashFile}"
                jq -r '.default // ""' <<<"${controlledResponse}" >"${defaultFile}"
                jq -c '.sing_box // []' <<<"${controlledResponse}" >"${singBoxFile}"
            else
                : >"${clashFile}"
                : >"${defaultFile}"
                printf '[]\n' >"${singBoxFile}"
            fi
        else
            fetchRemoteSubscribeContent "${subscribeType}://${remoteUrl}/s/clashMeta/${emailMD5}" >"${clashFile}" & clashPid=$!
            fetchRemoteSubscribeContent "${subscribeType}://${remoteUrl}/s/default/${emailMD5}" >"${defaultFile}" & defaultPid=$!
            fetchRemoteSubscribeContent "${subscribeType}://${remoteUrl}/s/sing-box_profiles/${emailMD5}" >"${singBoxFile}" & singBoxPid=$!
            wait "${clashPid}" 2>/dev/null || true
            wait "${defaultPid}" 2>/dev/null || true
            wait "${singBoxPid}" 2>/dev/null || true
        fi

        clashMetaProxies=$(sed '/proxies:/d' "${clashFile}" | sed "s/\"${email}/\"${email}_${serverAlias}/g")
        if [[ -n "${clashMetaProxies}" && "${clashMetaProxies}" != *nginx* ]]; then
            if ! appendUniqueLines "${clashMetaProxies}" "${clashTarget}"; then
                padmRemoveCleanupPath "${tmpDir}"
                padmRemoveCleanupPath "${stageDir}"
                return 1
            fi
            successCard "clashMeta订阅 ${remoteUrl}:${email} 更新成功"
        else
            errorCard "clashMeta订阅 ${remoteUrl}:${email} 拉取失败或不存在"
        fi

        default=$(<"${defaultFile}")
        if [[ -n "${default}" && "${default}" != *nginx* ]]; then
            default=$(echo "${default}" | { base64 -d 2>/dev/null || true; } | sed "s/#${email}/#${email}_${serverAlias}/g")
            if [[ -n "${default}" ]]; then
                if ! appendUniqueLines "${default}" "${defaultTarget}"; then
                    padmRemoveCleanupPath "${tmpDir}"
                    padmRemoveCleanupPath "${stageDir}"
                    return 1
                fi
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
    done <<<"${sourceLines}"

    mkdir -p "${publicBase}/default" "${publicBase}/clashMeta" "${localBase}/sing-box" || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    commitGeneratedFile "${defaultTarget}" "${publicBase}/default/${emailMD5}" 644 || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    commitGeneratedFile "${clashTarget}" "${publicBase}/clashMeta/${emailMD5}" 644 || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    commitGeneratedJsonFile "${singBoxTarget}" "${localBase}/sing-box/${email}" || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    padmRemoveCleanupPath "${tmpDir}"
    padmRemoveCleanupPath "${stageDir}"
}
