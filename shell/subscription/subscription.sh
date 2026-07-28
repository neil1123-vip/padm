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
    local outputVar=${2:-}
    local user
    local allowedSources
    local resolvedSources
    if ! subscriptionRemoteScopeEnabled; then
        [[ -n "${outputVar}" ]] && printf -v "${outputVar}" ''
        return 0
    fi
    user=$(subscriptionSyncFindUserByAccountName "${accountName}" 2>/dev/null) || return 2
    [[ -n "${user}" ]] || return 2
    allowedSources=$(jq -c '.allowed_sources // []' <<<"${user}") || return 1
    [[ -n "${allowedSources}" ]] || return 1
    resolvedSources=$(subscriptionActiveGroupRead -r --argjson allowed "${allowedSources}" '
      . as $group |
      if ($allowed | length) == 0 then
        empty
      elif ($allowed | index("*")) then
        $group.sources[]? | select(.role != "main" and .enabled == true) | "\(.host):\(.port):\(.id):\(.scheme)"
      else
        $group.sources[]? | select(.role != "main" and .enabled == true and (.id as $sid | $allowed | index($sid))) | "\(.host):\(.port):\(.id):\(.scheme)"
      end') || return 1
    if [[ -n "${outputVar}" ]]; then
        printf -v "${outputVar}" '%s' "${resolvedSources}"
    else
        printf '%s\n' "${resolvedSources}"
    fi
}

subscriptionPublishHasRemoteSources() {
    local accountName=$1
    local user
    subscriptionRemoteScopeEnabled || return 1
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
    local outputVar=${1:-}
    local certDir certFile domainName selectedDomain=
    local suggestions=
    local -a certificateDomains=()
    certDir=$(tlsManagedDir) || return 1
    if [[ -n "${AUTO_DOMAIN:-}" ]]; then
        tlsDomainNameIsSafe "${AUTO_DOMAIN}" || {
            errorCard "订阅 TLS 域名无效" "--domain 必须是合法主机名"
            return 1
        }
        selectedDomain=${AUTO_DOMAIN}
    elif [[ "${subscribeConfigState:-}" == "valid" && -n "${subscribeDomain:-}" ]]; then
        selectedDomain=${subscribeDomain}
    fi
    if [[ -z "${selectedDomain}" ]]; then
        for certFile in "${certDir}"/*.crt; do
            [[ -s "${certFile}" ]] || continue
            domainName=$(basename "${certFile}" .crt)
            tlsCertificatePairUsable "${certDir}" "${domainName}" || continue
            certificateDomains+=("${domainName}")
        done
        if [[ ${#certificateDomains[@]} -eq 1 ]]; then
            selectedDomain=${certificateDomains[0]}
        elif [[ ${#certificateDomains[@]} -gt 1 && ( "${cronName:-}" == "InstallSubscription" || "${AUTO_INSTALL:-}" == "true" ) ]]; then
            errorCard "检测到多张可用 TLS 证书" "自动安装必须显式提供 --domain"
            return 1
        fi
    fi
    if [[ -z "${selectedDomain}" && "${cronName:-}" != "InstallSubscription" && "${AUTO_INSTALL:-}" != "true" ]]; then
        [[ ${#certificateDomains[@]} -gt 0 ]] && suggestions="可用证书：${certificateDomains[*]}"
        [[ -n "${currentHost:-}" ]] && suggestions="${suggestions:+${suggestions}；}现有 TLS 域名：${currentHost}"
        [[ -n "${realityEntryHost:-}" ]] && suggestions="${suggestions:+${suggestions}；}Reality entry：${realityEntryHost}"
        [[ -n "${suggestions}" ]] && statusCard "订阅 TLS 域名候选" "${suggestions}" "请确认订阅服务自己的公网域名"
        autoRead subscription_tls_domain "请输入订阅 HTTPS 域名:" selectedDomain
        tlsDomainNameIsSafe "${selectedDomain}" || {
            errorCard "订阅 TLS 域名无效"
            return 1
        }
    fi
    if [[ -z "${selectedDomain}" ]]; then
        errorCard "无法确定订阅 TLS 域名" "请显式提供 --domain；不会自动使用 currentHost 或 Reality entry"
        return 1
    fi
    if [[ -n "${outputVar}" ]]; then
        printf -v "${outputVar}" '%s' "${selectedDomain}"
    else
        printf '%s\n' "${selectedDomain}"
    fi
}

subscriptionTcpPortHasListener() {
    local port=$1
    validPortNumber "${port}" || return 2
    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 { found = 1 } END { exit !found }'
        return $?
    fi
    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | awk -v port=":${port}" '$4 ~ port "$" { found = 1 } END { exit !found }'
        return $?
    fi
    return 2
}

subscriptionTcpPortListenersAreNginx() {
    local port=$1
    local pid commandName lines
    if command -v lsof >/dev/null 2>&1; then
        lines=$(lsof -t -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | LC_ALL=C sort -u) || true
        [[ -n "${lines}" ]] || return 1
        while IFS= read -r pid; do
            commandName=$(ps -p "${pid}" -o comm= 2>/dev/null | awk '{print $1}')
            [[ "${commandName}" == "nginx" || "${commandName}" == "openresty" ]] || return 1
        done <<<"${lines}"
        return 0
    fi
    command -v ss >/dev/null 2>&1 || return 1
    lines=$(ss -ltnp 2>/dev/null | awk -v port=":${port}" '$4 ~ port "$" { print }')
    [[ -n "${lines}" ]] && ! grep -vEq 'users:\(\("(nginx|openresty)"' <<<"${lines}"
}

subscriptionInstallTLSHttp01() {
    local certDomain=$1
    local nginxWasRunning=false
    local firewallAdded=false
    local status=0
    local listenerStatus=0

    checkDNSIP "${certDomain}" || {
        errorCard "订阅域名未解析到本机" "HTTP-01 未停止服务、开放 80 端口或调用 CA"
        return 1
    }
    subscriptionTcpPortHasListener 80 || listenerStatus=$?
    if [[ "${listenerStatus}" == "0" ]]; then
        if ! subscriptionTcpPortListenersAreNginx; then
            errorCard "80 端口被非 Nginx 进程占用" "不会停止或杀死占用进程"
            return 1
        fi
        nginxRunning || {
            errorCard "80 端口监听状态无法归属到受管 Nginx"
            return 1
        }
        nginxWasRunning=true
        runSubscribeNginxAction stop || return 1
        if subscriptionTcpPortHasListener 80; then
            runSubscribeNginxAction start restore || true
            errorCard "停止 Nginx 后 80 端口仍被占用"
            return 1
        fi
    elif [[ "${listenerStatus}" == "2" ]]; then
        errorCard "无法检查 80 端口监听状态"
        return 1
    fi
    allowPort 80 || status=$?
    [[ "${PADM_LAST_ALLOW_PORT_ADDED:-false}" == "true" ]] && firewallAdded=true
    if [[ "${status}" == "0" ]]; then
        installTLS 1 || status=$?
    fi
    if [[ "${firewallAdded}" == "true" ]] && ! denyPort 80; then
        errorCard "HTTP-01 临时 80 端口防火墙规则恢复失败"
        status=1
    fi
    if [[ "${nginxWasRunning}" == "true" ]] && ! runSubscribeNginxAction start restore; then
        errorCard "HTTP-01 完成后 Nginx 原运行状态恢复失败"
        status=1
    fi
    return "${status}"
}

prepareSubscribeTLSCertificate() {
    local certDomain=$1
    local tlsDir confirm=
    tlsDir=$(tlsManagedDir) || return 1
    if tlsCertificatePairUsable "${tlsDir}" "${certDomain}"; then
        if tlsCertificateManagedByAcme "${certDomain}"; then
            crontab -l 2>/dev/null | grep -q '/etc/padm/install.sh RenewTLS' || installCronTLS 1 || return 1
            statusCard "订阅 TLS 证书" "已复用 acme.sh 管理的可用证书：${certDomain}"
        else
            statusCard "订阅 TLS 证书" "已复用自定义证书：${certDomain}" "自定义证书需自行续期"
        fi
        return 0
    fi
    if [[ "${cronName:-}" == "InstallSubscription" || "${AUTO_INSTALL:-}" == "true" ]]; then
        if [[ -z "${AUTO_DOMAIN:-}" ]]; then
            errorCard "订阅证书缺失或不可用" "自动修复必须显式提供 --domain"
            return 1
        fi
    else
        statusCard "公网订阅只提供 HTTPS" "需要为 ${certDomain} 申请或修复证书"
        autoRead subscription_tls_issue_confirm "现在申请证书？[y/n]:" confirm
        if [[ "${confirm}" != "y" && "${confirm}" != "yes" ]]; then
            statusCard "已取消订阅服务安装" "Nginx 配置未修改"
            return 1
        fi
    fi
    if [[ ( "${cronName:-}" == "InstallSubscription" || "${AUTO_INSTALL:-}" == "true" ) &&
        "$(normalizeYesNo "${AUTO_DNS_API:-}")" == "y" ]]; then
        case "${AUTO_DNS_API_TYPE:-}" in
        aliyun | Aliyun | alibaba | 2)
            if [[ -z "${AUTO_ALIYUN_API_KEY:-${PADM_ALIYUN_API_KEY:-}}" ||
                -z "${AUTO_ALIYUN_API_SECRET:-${PADM_ALIYUN_API_SECRET:-}}" ]]; then
                errorCard "阿里云 DNS API 凭据不完整" "请提供 --aliyun-api-key 和 --aliyun-api-secret"
                return 1
            fi
            ;;
        *)
            if [[ -z "${AUTO_CLOUDFLARE_API_TOKEN:-${PADM_CLOUDFLARE_API_TOKEN:-${CLOUDFLARE_API_TOKEN:-${CF_Token:-}}}}" ]]; then
                errorCard "Cloudflare DNS API Token 为空" "请提供 --cloudflare-api-token 或 PADM_CLOUDFLARE_API_TOKEN"
                return 1
            fi
            ;;
        esac
    fi
    (
        domain=${certDomain}
        currentHost=
        tlsDomain=${certDomain}
        PADM_REQUIRE_USABLE_TLS_CERTIFICATE=true
        unset dnsAPIStatus dnsAPIType installedDNSAPIStatus sslType selectSSLType
        readAcmeTLS || exit 1
        switchDNSAPI || exit 1
        installAcmeTool || exit 1
        if [[ -n "${dnsAPIType:-}" ]]; then
            installTLS 1 || exit 1
        else
            subscriptionInstallTLSHttp01 "${certDomain}" || exit 1
        fi
    ) || return 1
    tlsCertificatePairUsable "${tlsDir}" "${certDomain}" || {
        errorCard "订阅 TLS 证书生成后仍不可用" "未修改 Nginx 配置"
        return 1
    }
    tlsCertificateManagedByAcme "${certDomain}" || {
        errorCard "订阅证书缺少 acme.sh 安装目标" "无法保证自动续期更新受管 .crt/.key"
        return 1
    }
    crontab -l 2>/dev/null | grep -q '/etc/padm/install.sh RenewTLS' || installCronTLS 1 || return 1
}

runSubscribeNginxAction() {
    local action=$1
    shift
    local previousAllowFailure="${SERVICE_QUEUE_ALLOW_FAILURE:-}"
    SERVICE_QUEUE_ALLOW_FAILURE=true
    handleNginx "${action}" "$@"
    local rc=$?
    SERVICE_QUEUE_ALLOW_FAILURE="${previousAllowFailure}"
    return "${rc}"
}

rollbackSubscribeNginxInstall() {
    local backupDir=$1
    local nginxWasRunning=$2
    local nginxWasEnabled=$3
    local reason=$4
    local configWasApplied=${5:-true}
    local installStateRestored=true
    local serviceRestored=true

    restoreCoreStartupServiceInstall "${backupDir}" nginx "${nginxWasEnabled}" || installStateRestored=false

    if [[ "${nginxWasRunning}" == "true" ]]; then
        if [[ "${installStateRestored}" == "true" && "${configWasApplied}" == "true" ]] &&
            nginxRunning && ! runSubscribeNginxAction stop; then
            serviceRestored=false
        fi
        if ! nginxRunning && ! runSubscribeNginxAction start restore; then
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

resolveSubscribePort() {
    local outputVar=$1
    local currentPort=${2:-}
    local selectedPort=${AUTO_SUBSCRIBE_PORT:-${currentPort}}
    if [[ -z "${selectedPort}" ]]; then
        autoRead subscription_port "请输入订阅 HTTPS 端口[回车随机]:" selectedPort
        [[ -n "${selectedPort}" ]] || selectedPort=$((RANDOM % 50001 + 10000))
    fi
    validPortNumber "${selectedPort}" || {
        errorCard "订阅端口无效"
        return 1
    }
    printf -v "${outputVar}" '%s' "${selectedPort}"
}

subscriptionNginxConfigListensOnPort() {
    local configFile=$1
    local port=$2
    awk -v expected="${port}" '
      /^[[:space:]]*#/ { next }
      {
        for (i = 1; i < NF; i++) {
          token = $i
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", token)
          if (token != "listen") continue
          value = $(i + 1)
          gsub(/;/, "", value)
          sub(/^.*:/, "", value)
          if (value == expected) found = 1
        }
      }
      END { exit !found }
    ' "${configFile}"
}

subscriptionNginxPortConfiguredElsewhere() {
    local port=$1
    local targetPath=$2
    local configFile
    local configDir
    configDir=$(dirname -- "${targetPath}")
    [[ -d "${configDir}" ]] || return 1
    for configFile in "${configDir}"/*.conf; do
        [[ -f "${configFile}" && "${configFile}" != "${targetPath}" ]] || continue
        subscriptionNginxConfigListensOnPort "${configFile}" "${port}" && return 0
    done
    return 1
}

validateSubscribeTargetPort() {
    local port=$1
    local oldPort=$2
    local targetPath=$3
    local listenerStatus=0
    if subscriptionNginxPortConfiguredElsewhere "${port}" "${targetPath}"; then
        errorCard "订阅端口 ${port} 已被其他 Nginx 配置使用" "不会共享监听或停止其他服务"
        return 1
    fi
    subscriptionTcpPortHasListener "${port}" || listenerStatus=$?
    if [[ "${listenerStatus}" == "1" ]]; then
        return 0
    fi
    if [[ "${listenerStatus}" == "2" ]]; then
        errorCard "无法检查订阅端口 ${port} 的监听状态"
        return 1
    fi
    if [[ "${subscribeConfigState:-}" == "valid" && "${port}" == "${oldPort}" ]] &&
        subscriptionTcpPortListenersAreNginx "${port}"; then
        return 0
    fi
    errorCard "订阅端口 ${port} 已被占用" "不会停止或杀死占用进程"
    return 1
}

probeSubscribeTLS() {
    local certDomain=$1
    local port=$2
    local tlsDir peerCertificate expectedFingerprint actualFingerprint
    tlsDir=$(tlsManagedDir) || return 1
    padmCreateTmpRootPath peerCertificate padm-subscribe-peer.XXXXXX || return 1
    if ! timeout 15 openssl s_client -connect "127.0.0.1:${port}" -servername "${certDomain}" -showcerts </dev/null 2>/dev/null |
        openssl x509 -outform PEM >"${peerCertificate}" 2>/dev/null; then
        padmRemoveCleanupPath "${peerCertificate}"
        return 1
    fi
    openssl x509 -in "${peerCertificate}" -checkhost "${certDomain}" -noout >/dev/null 2>&1 || {
        padmRemoveCleanupPath "${peerCertificate}"
        return 1
    }
    expectedFingerprint=$(openssl x509 -in "${tlsDir}/${certDomain}.crt" -noout -fingerprint -sha256 2>/dev/null) || {
        padmRemoveCleanupPath "${peerCertificate}"
        return 1
    }
    actualFingerprint=$(openssl x509 -in "${peerCertificate}" -noout -fingerprint -sha256 2>/dev/null) || {
        padmRemoveCleanupPath "${peerCertificate}"
        return 1
    }
    padmRemoveCleanupPath "${peerCertificate}"
    [[ -n "${expectedFingerprint}" && "${expectedFingerprint}" == "${actualFingerprint}" ]]
}

subscriptionFirewallPortKeys() {
    local port=$1
    local stateFile
    stateFile=$(padmFirewallStateFile) || return 1
    [[ -f "${stateFile}" ]] || return 0
    awk -F: -v port="${port}" '$1 == "port" && $3 == "tcp" && $4 == port { print }' "${stateFile}"
}

# 安装订阅服务
installSubscribeApply() {
    local oldSubscribePort= oldSubscribeDomain= oldSubscribeConfigState=
    local desiredPort= subscribeServerName=
    local listenIPv6=
    local subscribePublicBase=
    local tlsDir=
    local targetPath=
    local installBackupDir=
    local nginxWasRunning=false
    local nginxWasEnabled=false
    local oldFirewallKeys= key
    local oldFirewallRestoreFailed=false

    if ! readNginxSubscribe; then
        errorCard "订阅 Nginx 配置损坏" "不会按未安装状态覆盖 subscribe.conf"
        return 1
    fi
    oldSubscribePort=${subscribePort:-}
    oldSubscribeDomain=${subscribeDomain:-}
    oldSubscribeConfigState=${subscribeConfigState:-missing}
    targetPath=$(nginxConfigFilePath subscribe.conf) || {
        errorCard "订阅 Nginx 配置路径异常"
        return 1
    }
    resolveSubscribeServerName subscribeServerName || return 1
    resolveSubscribePort desiredPort "${oldSubscribePort}" || return 1
    validateSubscribeTargetPort "${desiredPort}" "${oldSubscribePort}" "${targetPath}" || return 1
    prepareSubscribeTLSCertificate "${subscribeServerName}" || return 1
    tlsDir=$(tlsManagedDir) || return 1
    tlsCertificatePairUsable "${tlsDir}" "${subscribeServerName}" || return 1

    if ! command -v nginx >/dev/null 2>&1; then
        menuLine "$(uiStyle warn "未检测到 nginx，无法使用订阅服务")"
        autoConfirm install_nginx "未检测到 nginx，是否安装？" n installNginxStatus
        if [[ "${installNginxStatus}" != "y" ]] || ! (installNginxTools); then
            errorCard "Nginx 不可用，已取消订阅配置"
            return 1
        fi
    fi
    nginx -v >/dev/null 2>&1 || return 1
    subscribePublicBase=$(padmResolveManagedAbsolutePath "$(subscribePublicBaseDir)") || return 1
    subscribePublicBase="${subscribePublicBase%/}"
    padmEnsureSafeDirectory "${subscribePublicBase}" || return 1
    padmEnsureSafeDirectory "${nginxStaticPath}" || return 1

    if [[ "${oldSubscribeConfigState}" == "valid" &&
        "${oldSubscribePort}" == "${desiredPort}" &&
        "${oldSubscribeDomain}" == "${subscribeServerName}" ]]; then
        nginx -t || {
            errorCard "订阅 Nginx 配置校验失败"
            return 1
        }
        nginxRunning || runSubscribeNginxAction start || return 1
        probeSubscribeTLS "${subscribeServerName}" "${desiredPort}" || {
            errorCard "订阅 HTTPS 本机 SNI/TLS 探测失败"
            return 1
        }
        return 0
    fi

    allowPort "${desiredPort}" || return 1
    checkLogBackupCreate installBackupDir "${targetPath}" || {
        errorCard "订阅 Nginx 配置备份失败"
        return 1
    }
    nginxRunning && nginxWasRunning=true
    coreStartupServiceEnabled nginx && nginxWasEnabled=true
    hasIPv6Connectivity && listenIPv6="    listen [::]:${desiredPort} ssl;"

    if ! writeSubscribeNginxConfig <<EOF
server {
    listen ${desiredPort} ssl so_keepalive=on;
${listenIPv6}
    server_name ${subscribeServerName};
    ssl_certificate ${tlsDir}/${subscribeServerName}.crt;
    ssl_certificate_key ${tlsDir}/${subscribeServerName}.key;
    ssl_protocols              TLSv1.2 TLSv1.3;
    ssl_ciphers                TLS13_AES_128_GCM_SHA256:TLS13_AES_256_GCM_SHA384:TLS13_CHACHA20_POLY1305_SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers  on;

    resolver                   1.1.1.1 valid=60s;
    resolver_timeout           2s;
    client_max_body_size 100m;
    root ${nginxStaticPath};
    location ~ "^/s/(clashMeta|default|clashMetaProfiles|sing-box|sing-box_profiles)/([A-Fa-f0-9]{32})$" {
        access_log off;
        default_type 'text/plain; charset=utf-8';
        alias ${subscribePublicBase}/\$1/\$2;
    }
    location / {
    }
}
EOF
    then
        rollbackSubscribeNginxInstall "${installBackupDir}" "${nginxWasRunning}" "${nginxWasEnabled}" "${SUBSCRIBE_NGINX_CONFIG_WRITE_ERROR:-订阅 Nginx 配置校验失败}" false || true
        return 1
    fi
    if ! bootStartup nginx || ! runSubscribeNginxAction stop || ! runSubscribeNginxAction start; then
        rollbackSubscribeNginxInstall "${installBackupDir}" "${nginxWasRunning}" "${nginxWasEnabled}" "订阅 Nginx 服务应用失败" || true
        return 1
    fi
    if ! probeSubscribeTLS "${subscribeServerName}" "${desiredPort}"; then
        rollbackSubscribeNginxInstall "${installBackupDir}" "${nginxWasRunning}" "${nginxWasEnabled}" "订阅 HTTPS 本机 SNI/TLS 探测失败" || true
        return 1
    fi
    if [[ -n "${oldSubscribePort}" && "${oldSubscribePort}" != "${desiredPort}" ]]; then
        oldFirewallKeys=$(subscriptionFirewallPortKeys "${oldSubscribePort}") || oldFirewallKeys=
        if [[ -n "${oldFirewallKeys}" ]] && ! denyPort "${oldSubscribePort}"; then
            allowPort "${oldSubscribePort}" || oldFirewallRestoreFailed=true
            while IFS= read -r key; do
                [[ -n "${key}" ]] && padmUntrackPortAllowTransactionKey "${key}"
            done <<<"${oldFirewallKeys}"
            if [[ "${oldFirewallRestoreFailed}" == "true" ]]; then
                rollbackSubscribeNginxInstall "${installBackupDir}" "${nginxWasRunning}" "${nginxWasEnabled}" "旧订阅端口防火墙规则回收失败，且旧规则恢复失败" || true
            else
                rollbackSubscribeNginxInstall "${installBackupDir}" "${nginxWasRunning}" "${nginxWasEnabled}" "旧订阅端口防火墙规则回收失败" || true
            fi
            return 1
        fi
    fi
    padmRemoveCleanupPath "${installBackupDir}"
}

installSubscribe() {
    subscriptionRequireLocalPublisherRole || return 1
    padmRunPortAllowTransaction installSubscribeApply "$@"
}

# 卸载订阅服务
unInstallSubscribe() {
    local targetPath
    local subscribePort
    local firewallStatus=0
    if ! targetPath=$(nginxConfigFilePath subscribe.conf); then
        padmShowUnsafePathError "卸载订阅 Nginx 配置"
        return 1
    fi
    if [[ ! -e "${targetPath}" && ! -L "${targetPath}" ]]; then
        return 0
    fi
    subscribePort=$(awk '
        /^[[:space:]]*listen[[:space:]]/ {
            for (i = 2; i <= NF; i++) {
                value = $i
                gsub(/[;].*/, "", value)
                if (value ~ /^[0-9]+$/) {
                    print value
                    exit
                }
                if (value ~ /:[0-9]+$/) {
                    sub(/^.*:/, "", value)
                    print value
                    exit
                }
            }
        }
    ' "${targetPath}" 2>/dev/null || true)
    removeManagedFileIfPresent "${targetPath}" || return 1
    if [[ -n "${subscribePort}" ]] && validPortNumber "${subscribePort}"; then
        denyPort "${subscribePort}" || firewallStatus=1
        denyPort "${subscribePort}" udp || firewallStatus=1
    fi
    if [[ "${firewallStatus}" != "0" ]]; then
        errorCard "订阅 Nginx 配置已删除，但防火墙端口回收失败，请检查防火墙状态"
        return 1
    fi
    return 0
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
    local sourceStatus=0
    local escapedEmail=
    local tmpDir stageDir publicBase localBase defaultTarget clashTarget singBoxTarget remoteBackupDir=
    local commitFailed=false

    subscriptionRemoteScopeEnabled || return 0

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

    subscriptionRemoteSubscribeSourcesForAccount "${email}" sourceLines || sourceStatus=$?
    if [[ "${sourceStatus}" == "2" ]]; then
        sourceLines=$(subscriptionActiveGroupRead -r '
          .sources[]?
          | select(.role != "main" and .enabled == true and .transport != "wireguard")
          | "\(.host):\(.port):\(.id):\(.scheme)"')
    elif [[ "${sourceStatus}" != "0" ]]; then
        return 1
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
                padmRemoveCleanupPath "${tmpDir}"
                padmRemoveCleanupPath "${stageDir}"
                return 1
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
