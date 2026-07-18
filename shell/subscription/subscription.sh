#!/usr/bin/env bash

subscribeLocalBaseDir() {
    printf '%s' "${PADM_SUBSCRIBE_LOCAL_DIR:-/etc/padm/subscribe_local}"
}

subscribePublicBaseDir() {
    printf '%s' "${PADM_SUBSCRIBE_DIR:-/etc/padm/subscribe}"
}

subscriptionNginxWorkerGroup() {
    local workerUser=${PADM_NGINX_USER:-}
    local candidate
    if [[ "$(id -u)" -ne 0 && -z "${workerUser}" ]]; then
        id -gn
        return 0
    fi
    if [[ -z "${workerUser}" ]] && command -v nginx >/dev/null 2>&1; then
        workerUser=$(nginx -T 2>/dev/null | awk '$1 == "user" { gsub(/;$/, "", $2); print $2; exit }' || true)
    fi
    if [[ -z "${workerUser}" ]] && command -v ps >/dev/null 2>&1; then
        workerUser=$(ps -eo user=,comm= 2>/dev/null | awk '$2 ~ /^nginx/ && $1 != "root" { print $1; exit }' || true)
    fi
    for candidate in "${workerUser}" www-data nginx http nobody; do
        [[ -n "${candidate}" ]] || continue
        if id -g "${candidate}" >/dev/null 2>&1; then
            id -gn "${candidate}"
            return 0
        fi
    done
    id -gn
}

commitSubscribePublicFile() {
    local stagedPath=$1
    local targetPath=$2
    local targetParent
    local nginxGroup
    targetPath=$(padmResolveManagedAbsolutePath "${targetPath}") || return 1
    targetParent=$(dirname -- "${targetPath}")
    padmEnsureSafeDirectory "${targetParent}" || return 1
    nginxGroup=$(subscriptionNginxWorkerGroup) || return 1
    chgrp -- "${nginxGroup}" "${stagedPath}" || return 1
    commitGeneratedFile "${stagedPath}" "${targetPath}" 640
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
    local accountName=$1
    local user
    local allowedSources
    user=$(subscriptionSyncFindUserByAccountName "${accountName}" 2>/dev/null) || return 0
    [[ -n "${user}" ]] || return 0
    allowedSources=$(jq -c '.allowed_sources // []' <<<"${user}") || return 0
    [[ -n "${allowedSources}" ]] || return 0
    subscriptionActiveGroupRead -r --argjson allowed "${allowedSources}" '
      . as $group |
      if ($allowed | length) == 0 then
        empty
      elif ($allowed | index("*")) then
        $group.sources[]? | select(.role != "main" and .enabled == true) | "\(.host):\(.port):\(.id):\(.scheme)"
      else
        $group.sources[]? | select(.role != "main" and .enabled == true and (.id as $sid | $allowed | index($sid))) | "\(.host):\(.port):\(.id):\(.scheme)"
      end'
}

subscriptionPublishHasRemoteSources() {
    local accountName=$1
    local user
    user=$(subscriptionSyncFindUserByAccountName "${accountName}" 2>/dev/null) || return 1
    [[ -n "${user}" ]] || return 1
    jq -e '(.has_remote // false) == true' <<<"${user}" >/dev/null 2>&1
}

ensureSubscriptionControlNginxLocation() {
    return 1
}

subscribeNginxConfigWriteError() {
    SUBSCRIBE_NGINX_CONFIG_WRITE_ERROR=$1
    return 1
}

writeSubscribeNginxConfig() {
    local targetPath
    local restoreMessage
    if ! targetPath=$(nginxConfigFilePath subscribe.conf); then
        subscribeNginxConfigWriteError "订阅 Nginx 配置路径异常"
        return 1
    fi
    if ! padmCommitTargetIsFileLike "${targetPath}"; then
        subscribeNginxConfigWriteError "订阅 Nginx 配置目标异常"
        return 1
    fi
    local tmpPath
    local backupPath=
    local nginxTestLog
    nginxTestLog="$(padmFallbackTmpFilePath padm-subscribe-nginx-test.log)"
    SUBSCRIBE_NGINX_CONFIG_WRITE_ERROR=
    padmCreateTempFileForTarget tmpPath "${targetPath}" subscribe || return 1
    if ! cat >"${tmpPath}"; then
        padmRemoveCleanupPath "${tmpPath}"
        return 1
    fi
    if command -v nginx >/dev/null 2>&1; then
        if [[ -f "${targetPath}" ]]; then
            padmCreateTempFileForTarget backupPath "${targetPath}" backup || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
            backupManagedFileToPath "${targetPath}" "${backupPath}" 644 || {
                padmRemoveCleanupPath "${tmpPath}"
                padmRemoveCleanupPath "${backupPath}"
                return 1
            }
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
                    subscriptionSyncSetSingleRestoreResultMessage restoreMessage "订阅 Nginx 配置校验失败" false "已恢复旧配置" "旧配置" " ${targetPath} 和 ${backupPath}" || true
                    subscribeNginxConfigWriteError "${restoreMessage}"
                    return 1
                }
            else
                subscriptionSyncSetManualCheckMessage restoreMessage "订阅 Nginx 配置校验失败，且新配置清理失败" " ${targetPath}"
                removeManagedFileIfPresent "${targetPath}" || subscribeNginxConfigWriteError "${restoreMessage}" || return 1
            fi
            return 1
        fi
        [[ -n "${backupPath}" ]] && padmRemoveCleanupPath "${backupPath}"
        return 0
    else
        commitGeneratedFile "${tmpPath}" "${targetPath}" 644 || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
    fi
}

resolveSubscribeServerName() {
    local certDir
    local certFile domainName
    certDir=$(tlsManagedDir) || return 1
    if [[ -n "${currentHost:-}" ]]; then
        padmIsValidHostName "${currentHost}" || return 1
        printf '%s\n' "${currentHost}"
        return 0
    fi
    if [[ -n "${domain:-}" ]]; then
        padmIsValidHostName "${domain}" || return 1
        printf '%s\n' "${domain}"
        return 0
    fi
    for certFile in "${certDir}"/*.crt; do
        [[ -s "${certFile}" ]] || continue
        domainName=$(basename "${certFile}" .crt)
        padmIsValidHostName "${domainName}" || continue
        [[ -s "${certDir}/${domainName}.key" ]] || continue
        printf '%s\n' "${domainName}"
        return 0
    done
    return 1
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

rollbackSubscribeNginxInstall() {
    local backupDir=$1
    local nginxWasRunning=$2
    local nginxWasEnabled=$3
    local reason=$4
    local installStateRestored=true
    local serviceRestored=true

    restoreCoreStartupServiceInstall "${backupDir}" nginx "${nginxWasEnabled}" || installStateRestored=false

    if [[ "${nginxWasRunning}" == "true" ]]; then
        if ! nginxRunning && ! runSubscribeNginxAction start; then
            serviceRestored=false
        fi
    elif nginxRunning && ! runSubscribeNginxAction stop; then
        serviceRestored=false
    fi

    if [[ "${installStateRestored}" == "true" && "${serviceRestored}" == "true" ]]; then
        errorCard "${reason}，已恢复旧 Nginx 配置、开机自启和运行状态"
        return 0
    fi
    if [[ "${installStateRestored}" != "true" ]]; then
        errorCard "${reason}，且回滚未完全成功" "请手动检查 Nginx 配置和服务状态；备份目录: ${backupDir}"
    else
        errorCard "${reason}，旧 Nginx 配置已恢复但运行状态恢复失败" "请手动检查 Nginx 服务状态"
    fi
    return 1
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
    local subscribePublicBase=
    local tlsDir=
    local targetPath=
    local installBackupDir=
    local nginxWasRunning=false
    local nginxWasEnabled=false
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
        PADM_NGINX_BLOG_REINSTALL_PROMPT=false nginxBlog || return 1
        echo
        subscribeServerName=$(resolveSubscribeServerName || true)
        if [[ -z "${subscribeServerName}" ]]; then
            errorCard "订阅服务需要 HTTPS 域名" "未发现可用于订阅服务的 TLS 域名或证书" "请先在 站点与证书 中配置域名证书，或安装时提供 --domain"
            return 1
        fi

        SSLType="ssl"
        serverName="server_name ${subscribeServerName};"
        tlsDir=$(tlsManagedDir) || return 1
        subscribePublicBase=$(padmResolveManagedAbsolutePath "$(subscribePublicBaseDir)") || return 1
        subscribePublicBase="${subscribePublicBase%/}"
        nginxSubscribeSSL="ssl_certificate ${tlsDir}/${subscribeServerName}.crt;ssl_certificate_key ${tlsDir}/${subscribeServerName}.key;"
        if hasIPv6Connectivity; then
            listenIPv6="listen [::]:${result[-1]} ${SSLType};"
        fi
        if echo "${nginxVersion}" | grep -q "1.25" && [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $3}') -gt 0 ]] || [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $2}') -gt 25 ]]; then
            nginxSubscribeListen="listen ${result[-1]} ${SSLType} so_keepalive=on;http2 on;${listenIPv6}"
        else
            nginxSubscribeListen="listen ${result[-1]} ${SSLType} so_keepalive=on;${listenIPv6}"
        fi

        targetPath=$(nginxConfigFilePath subscribe.conf) || {
            errorCard "订阅 Nginx 配置路径异常"
            return 1
        }
        checkLogBackupCreate installBackupDir "${targetPath}" || {
            errorCard "订阅 Nginx 配置备份失败"
            return 1
        }
        if nginxRunning; then
            nginxWasRunning=true
        fi
        coreStartupServiceEnabled nginx && nginxWasEnabled=true

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
    location ~ ^/s/(clashMeta|default|clashMetaProfiles|sing-box|sing-box_profiles)/([A-Fa-f0-9]{32})$ {
        access_log off;
        default_type 'text/plain; charset=utf-8';
        alias ${subscribePublicBase}/\$1/\$2;
    }
    location / {
    }
}
EOF
        then
            rollbackSubscribeNginxInstall \
                "${installBackupDir}" \
                "${nginxWasRunning}" \
                "${nginxWasEnabled}" \
                "${SUBSCRIBE_NGINX_CONFIG_WRITE_ERROR:-订阅 Nginx 配置校验失败}" || true
            return 1
        fi
        if ! bootStartup nginx; then
            rollbackSubscribeNginxInstall "${installBackupDir}" "${nginxWasRunning}" "${nginxWasEnabled}" "Nginx 开机自启配置失败" || true
            return 1
        fi
        if ! runSubscribeNginxAction stop || ! runSubscribeNginxAction start; then
            rollbackSubscribeNginxInstall "${installBackupDir}" "${nginxWasRunning}" "${nginxWasEnabled}" "订阅 Nginx 服务重载失败" || true
            return 1
        fi
        if ! installSubscriptionControlService; then
            rollbackSubscribeNginxInstall "${installBackupDir}" "${nginxWasRunning}" "${nginxWasEnabled}" "订阅控制服务安装失败" || true
            return 1
        fi
        padmRemoveCleanupPath "${installBackupDir}"
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
    curl -fsSL --connect-timeout 5 --max-time 15 --max-filesize 1048576 "${url}" 2>/dev/null
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
    local escapedEmail=
    local tmpDir stageDir publicBase localBase defaultTarget clashTarget singBoxTarget remoteBackupDir=
    local commitFailed=false

    padmCreateTmpRootPath tmpDir padm-remote-subscribe-fetch.XXXXXX -d || return 1
    padmCreateTmpRootPath stageDir padm-remote-subscribe-stage.XXXXXX -d || { padmRemoveCleanupPath "${tmpDir}"; return 1; }
    publicBase=$(subscribePublicBaseDir)
    localBase=$(subscribeLocalBaseDir)
    publicBase=$(padmResolveManagedAbsolutePath "${publicBase}") || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    localBase=$(padmResolveManagedAbsolutePath "${localBase}") || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    mkdir -p "${stageDir}/default" "${stageDir}/clashMeta" "${stageDir}/sing-box" || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    defaultTarget="${stageDir}/default/${emailMD5}"
    clashTarget="${stageDir}/clashMeta/${emailMD5}"
    singBoxTarget="${stageDir}/sing-box/${email}"
    if [[ -f "${publicBase}/default/${emailMD5}" ]]; then
        cp "${publicBase}/default/${emailMD5}" "${defaultTarget}" || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    else
        : >"${defaultTarget}" || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    fi
    if [[ -f "${publicBase}/clashMeta/${emailMD5}" ]]; then
        cp "${publicBase}/clashMeta/${emailMD5}" "${clashTarget}" || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    else
        : >"${clashTarget}" || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    fi
    if [[ -f "${localBase}/sing-box/${email}" ]]; then
        cp "${localBase}/sing-box/${email}" "${singBoxTarget}" || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    else
        printf '[]\n' >"${singBoxTarget}" || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    fi

    sourceLines=$(subscriptionRemoteSubscribeSourcesForAccount "${email}" 2>/dev/null) || sourceLines=
    if [[ -z "${sourceLines}" ]]; then
        sourceLines=$(subscriptionActiveGroupRead -r '
          .sources[]?
          | select(.role != "main" and .enabled == true and .transport != "wireguard")
          | "\(.host):\(.port):\(.id):\(.scheme)"')
    fi
    escapedEmail=$(printf '%s\n' "${email}" | sed 's/[][\/.^$*+?(){}|]/\\&/g')

    while IFS= read -r line; do
        if [[ -z "${line}" ]]; then
            continue
        fi
        local subscribeType=
        local serverAlias=
        local remoteUrl=
        local clashMetaProxies=
        local default=
        local decodedDefault=
        local singBoxSubscribe=
        local controlledResponse=
        local controlledPayload=
        local clashFile="${tmpDir}/clash"
        local defaultFile="${tmpDir}/default"
        local singBoxFile="${tmpDir}/sing-box"
        local clashPid defaultPid singBoxPid
        local fetchFailed=false

        IFS=':' read -r remoteHost remotePort serverAlias subscribeType <<<"${line}"
        remoteUrl="${remoteHost}:${remotePort}"
        source=$(subscriptionActiveGroupRead -c --arg id "${serverAlias}" '.sources[]? | select(.id == $id)' 2>/dev/null) || source=
        if [[ -n "${source}" ]] && subscriptionRemoteSourceUsesWireGuard "${source}"; then
            controlledResponse=
            if controlledPayload=$(jq -nc --arg account "${email}" '{account:$account}') &&
                controlledResponse=$(subscriptionRemoteControlRequest "${source}" subscribe "${controlledPayload}" 2>/dev/null); then
                :
            fi
            if [[ -n "${controlledResponse}" ]] && jq -e '.ok == true' <<<"${controlledResponse}" >/dev/null 2>&1; then
                jq -r '.clash_meta // ""' <<<"${controlledResponse}" >"${clashFile}" || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
                jq -r '.default // ""' <<<"${controlledResponse}" >"${defaultFile}" || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
                jq -c '.sing_box // []' <<<"${controlledResponse}" >"${singBoxFile}" || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
            else
                : >"${clashFile}" || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
                : >"${defaultFile}" || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
                printf '[]\n' >"${singBoxFile}" || { padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
            fi
        else
            fetchRemoteSubscribeContent "${subscribeType}://${remoteUrl}/s/clashMeta/${emailMD5}" >"${clashFile}" & clashPid=$!
            fetchRemoteSubscribeContent "${subscribeType}://${remoteUrl}/s/default/${emailMD5}" >"${defaultFile}" & defaultPid=$!
            fetchRemoteSubscribeContent "${subscribeType}://${remoteUrl}/s/sing-box_profiles/${emailMD5}" >"${singBoxFile}" & singBoxPid=$!
            wait "${clashPid}" 2>/dev/null || fetchFailed=true
            wait "${defaultPid}" 2>/dev/null || fetchFailed=true
            wait "${singBoxPid}" 2>/dev/null || fetchFailed=true
            if [[ "${fetchFailed}" == "true" ]]; then
                padmRemoveCleanupPath "${tmpDir}"
                padmRemoveCleanupPath "${stageDir}"
                return 1
            fi
        fi

        clashMetaProxies=$(sed '/proxies:/d' "${clashFile}" | sed -E \
            -e "s/^([[:space:]-]*name:[[:space:]]*\")${escapedEmail}([^\"]*)(\".*)$/\1${email}_${serverAlias}\2\3/" \
            -e "s/^([[:space:]-]*name:[[:space:]]*)${escapedEmail}([^[:space:]]*)([[:space:]]*)$/\1${email}_${serverAlias}\2\3/")
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
            if decodedDefault=$(printf '%s' "${default}" | base64 -d 2>/dev/null); then
                default=$(printf '%s' "${decodedDefault}" | sed "s/#${email}/#${email}_${serverAlias}/g")
            else
                default=
            fi
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

    checkLogBackupCreate remoteBackupDir \
        "${publicBase}/default/${emailMD5}" \
        "${publicBase}/clashMeta/${emailMD5}" \
        "${localBase}/sing-box/${email}" || {
        padmRemoveCleanupPath "${tmpDir}"
        padmRemoveCleanupPath "${stageDir}"
        return 1
    }
    padmEnsureSafeDirectory "${publicBase}/default" || { padmRemoveCleanupPath "${remoteBackupDir}"; padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    padmEnsureSafeDirectory "${publicBase}/clashMeta" || { padmRemoveCleanupPath "${remoteBackupDir}"; padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    padmEnsureSafeDirectory "${localBase}/sing-box" || { padmRemoveCleanupPath "${remoteBackupDir}"; padmRemoveCleanupPath "${tmpDir}"; padmRemoveCleanupPath "${stageDir}"; return 1; }
    commitSubscribePublicFile "${defaultTarget}" "${publicBase}/default/${emailMD5}" || commitFailed=true
    commitSubscribePublicFile "${clashTarget}" "${publicBase}/clashMeta/${emailMD5}" || commitFailed=true
    commitGeneratedJsonFile "${singBoxTarget}" "${localBase}/sing-box/${email}" || commitFailed=true
    if [[ "${commitFailed}" == "true" ]]; then
        if ! checkLogBackupRestore "${remoteBackupDir}"; then
            padmForgetCleanupPath "${remoteBackupDir}"
            padmRemoveCleanupPath "${tmpDir}"
            padmRemoveCleanupPath "${stageDir}"
            return 1
        fi
        padmRemoveCleanupPath "${remoteBackupDir}"
        padmRemoveCleanupPath "${tmpDir}"
        padmRemoveCleanupPath "${stageDir}"
        return 1
    fi
    padmRemoveCleanupPath "${remoteBackupDir}"
    padmRemoveCleanupPath "${tmpDir}"
    padmRemoveCleanupPath "${stageDir}"
}
