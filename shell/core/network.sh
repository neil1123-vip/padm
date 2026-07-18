#!/usr/bin/env bash

ufwRulePresent() {
    local rule="$1/${2:-tcp}"
    ufw status | awk -v rule="${rule}" '$1 == rule { found = 1 } END { exit !found }'
}

ufwActive() {
    LC_ALL=C ufw status 2>/dev/null | grep -q '^Status: active'
}

ufwConfiguredRulePresent() {
    local rule="$1/${2:-tcp}"
    ufw show added | awk -v rule="${rule}" '$1 == "ufw" && $2 == "allow" && $3 == rule { found = 1 } END { exit !found }'
}

firewalldRulePresent() {
    local rule="$1/${2:-tcp}"
    firewall-cmd --zone=public --permanent --list-ports | tr ' ' '\n' | grep -Fxq "${rule}"
}

padmFirewallStateFile() {
    local installRoot=${PADM_INSTALL_DIR:-/etc/padm}
    padmRequireSafeAbsolutePath "${PADM_FIREWALL_STATE_FILE:-${installRoot%/}/firewall.state}"
}

padmFirewallStateHas() {
    local key=$1
    local stateFile
    stateFile=$(padmFirewallStateFile) || return 1
    [[ -f "${stateFile}" ]] && grep -Fxq -- "${key}" "${stateFile}"
}

padmFirewallStateAdd() {
    local key=$1
    local stateFile tmpFile
    stateFile=$(padmFirewallStateFile) || return 1
    padmFirewallStateHas "${key}" && return 0
    padmCreateTempFileForTarget tmpFile "${stateFile}" firewall || return 1
    if [[ -f "${stateFile}" ]]; then
        cat "${stateFile}" >"${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    fi
    printf '%s\n' "${key}" >>"${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    commitGeneratedFile "${tmpFile}" "${stateFile}" 600 || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

padmFirewallStateRemove() {
    local key=$1
    local stateFile tmpFile
    stateFile=$(padmFirewallStateFile) || return 1
    [[ -f "${stateFile}" ]] || return 0
    padmCreateTempFileForTarget tmpFile "${stateFile}" firewall || return 1
    awk -v key="${key}" '$0 != key' "${stateFile}" >"${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    if [[ -s "${tmpFile}" ]]; then
        commitGeneratedFile "${tmpFile}" "${stateFile}" 600 || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    else
        padmRemoveCleanupPath "${tmpFile}"
        removeManagedFileIfPresent "${stateFile}"
    fi
}

removeFirewallPortRule() {
    local backend=$1
    local requestedPort=$2
    local type=$3
    local firewallPort=${requestedPort}
    if [[ "${requestedPort}" == *:* ]]; then
        firewallPort="${requestedPort/:/-}"
    fi
    case "${backend}" in
    ufw)
        command -v ufw >/dev/null 2>&1 || return 1
        ufw show added >/dev/null 2>&1 || return 1
        if ufwConfiguredRulePresent "${requestedPort}" "${type}"; then
            sudo ufw delete allow "${requestedPort}/${type}" || return 1
        fi
        ;;
    firewalld)
        command -v firewall-cmd >/dev/null 2>&1 || return 1
        firewall-cmd --zone=public --permanent --list-ports >/dev/null 2>&1 || return 1
        if firewalldRulePresent "${firewallPort}" "${type}"; then
            firewall-cmd --zone=public --permanent --remove-port="${firewallPort}/${type}" || return 1
        fi
        firewall-cmd --reload || return 1
        ;;
    iptables)
        command -v iptables >/dev/null 2>&1 || return 1
        iptables -L >/dev/null 2>&1 || return 1
        if iptables -L | grep -Fq "allow ${requestedPort}/${type}(neil1123-vip)"; then
            iptables -D INPUT -p "${type}" --dport "${requestedPort}" -m comment --comment "allow ${requestedPort}/${type}(neil1123-vip)" -j ACCEPT || return 1
        fi
        netfilter-persistent save || return 1
        ;;
    *) return 1 ;;
    esac
}

denyPort() {
    local requestedPort=$1
    local type=${2:-tcp}
    local backend key
    local status=0
    [[ "${type}" == "tcp" || "${type}" == "udp" ]] || return 1
    if [[ "${requestedPort}" == *:* ]]; then
        local portStart=${requestedPort%%:*}
        local portEnd=${requestedPort#*:}
        validPortNumber "${portStart}" && validPortNumber "${portEnd}" && ((10#${portStart} <= 10#${portEnd})) || return 1
    else
        validPortNumber "${requestedPort}" || return 1
    fi
    for backend in ufw firewalld iptables; do
        key="port:${backend}:${type}:${requestedPort}"
        if padmFirewallStateHas "${key}"; then
            if removeFirewallPortRule "${backend}" "${requestedPort}" "${type}"; then
                padmFirewallStateRemove "${key}" || status=1
            else
                status=1
            fi
        fi
    done
    return "${status}"
}

padmFirewalldForwardStateKey() {
    printf 'forward:firewalld:udp:%s:%s:%s' "$1" "$2" "$3"
}

padmFirewalldForwardStateKeyForTarget() {
    local targetPort=$1
    local stateFile
    validPortNumber "${targetPort}" || return 1
    stateFile=$(padmFirewallStateFile) || return 1
    [[ -f "${stateFile}" ]] || return 1
    awk -F: -v targetPort="${targetPort}" '
        NF == 6 && $1 == "forward" && $2 == "firewalld" && $3 == "udp" && $6 == targetPort {
            print
            found = 1
            exit
        }
        END { exit !found }
    ' "${stateFile}"
}

padmIptablesForwardStateKey() {
    printf 'forward:iptables:%s:%s:%s:%s' "$1" "$2" "$3" "$4"
}

padmIptablesForwardStateKeyForTarget() {
    local type=$1
    local targetPort=$2
    local stateFile
    [[ "${type}" == "hysteria2" || "${type}" == "tuic" ]] || return 1
    validPortNumber "${targetPort}" || return 1
    stateFile=$(padmFirewallStateFile) || return 1
    [[ -f "${stateFile}" ]] || return 1
    awk -F: -v type="${type}" -v targetPort="${targetPort}" '
        NF == 6 && $1 == "forward" && $2 == "iptables" && $3 == type && $6 == targetPort {
            print
            found = 1
            exit
        }
        END { exit !found }
    ' "${stateFile}"
}

removeFirewalldForwardPortRange() {
    local start=$1
    local end=$2
    local targetPort=$3
    local permanentRules
    local port rule listedRule
    local -a listedRules=()
    local -A existingRules=()
    local status=0
    validPortNumber "${start}" && validPortNumber "${end}" && validPortNumber "${targetPort}" && ((10#${start} <= 10#${end})) || return 1
    command -v firewall-cmd >/dev/null 2>&1 || return 1
    permanentRules=$(firewall-cmd --zone=public --permanent --list-forward-ports) || return 1
    read -r -a listedRules <<<"${permanentRules//$'\n'/ }"
    for listedRule in "${listedRules[@]}"; do
        existingRules["${listedRule}"]=1
    done
    for ((port = 10#${start}; port <= 10#${end}; port++)); do
        rule="port=${port}:proto=udp:toport=${targetPort}"
        if [[ -n "${existingRules[${rule}]:-}" ]]; then
            firewall-cmd --zone=public --permanent --remove-forward-port="${rule}" || status=1
        fi
    done
    firewall-cmd --reload || status=1
    return "${status}"
}

removeFirewalldMasqueradeRule() {
    local queryStatus
    command -v firewall-cmd >/dev/null 2>&1 || return 1
    if firewall-cmd --zone=public --permanent --query-masquerade >/dev/null 2>&1; then
        firewall-cmd --zone=public --permanent --remove-masquerade || return 1
    else
        queryStatus=$?
        [[ "${queryStatus}" == "1" ]] || return 1
    fi
    firewall-cmd --reload
}

removeIptablesPortHoppingRules() {
    local type=$1
    local marker="neil1123-vip_${type}_portHopping"
    local line savedRules
    local status=0
    local -a ruleLines=()
    [[ "${type}" == "hysteria2" || "${type}" == "tuic" ]] || return 1
    command -v iptables >/dev/null 2>&1 && command -v iptables-save >/dev/null 2>&1 || return 1
    iptables -t nat -L PREROUTING --line-numbers >/dev/null 2>&1 || return 1
    mapfile -t ruleLines < <(iptables -t nat -L PREROUTING --line-numbers | awk -v marker="${marker}" '$0 ~ marker { print $1 }' | sort -rn)
    for line in "${ruleLines[@]}"; do
        [[ -n "${line}" ]] || continue
        iptables -t nat -D PREROUTING "${line}" || status=1
    done
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1 || status=1
    fi
    if ! savedRules=$(iptables-save); then
        status=1
    elif grep -Fq "${marker}" <<<"${savedRules}"; then
        status=1
    fi
    return "${status}"
}

cleanupPadmFirewallRules() {
    local stateFile key rest type requestedPort
    local kind backend ruleType start end targetPort extra
    local hopType savedRules
    local remainingForwardPorts=
    local status=0
    local -a keys=()
    stateFile=$(padmFirewallStateFile) || return 1
    if command -v iptables-save >/dev/null 2>&1; then
        if ! savedRules=$(iptables-save); then
            status=1
        else
            for hopType in hysteria2 tuic; do
                if grep -Fq "neil1123-vip_${hopType}_portHopping" <<<"${savedRules}"; then
                    removeIptablesPortHoppingRules "${hopType}" || status=1
                fi
            done
        fi
    fi
    [[ -f "${stateFile}" ]] || return "${status}"
    mapfile -t keys <"${stateFile}" || return 1
    for key in "${keys[@]}"; do
        if [[ "${key}" == port:* ]]; then
            rest=${key#port:}
            rest=${rest#*:}
            type=${rest%%:*}
            requestedPort=${rest#*:}
            denyPort "${requestedPort}" "${type}" || status=1
        elif [[ "${key}" == forward:* ]]; then
            IFS=: read -r kind backend ruleType start end targetPort extra <<<"${key}"
            case "${backend}" in
            firewalld)
                if [[ "${kind}" != "forward" || "${ruleType}" != "udp" || -n "${extra}" ]]; then
                    status=1
                elif removeFirewalldForwardPortRange "${start}" "${end}" "${targetPort}"; then
                    padmFirewallStateRemove "${key}" || status=1
                else
                    status=1
                fi
                ;;
            iptables)
                if [[ "${kind}" != "forward" || ( "${ruleType}" != "hysteria2" && "${ruleType}" != "tuic" ) || -n "${extra}" ]]; then
                    status=1
                elif removeIptablesPortHoppingRules "${ruleType}"; then
                    padmFirewallStateRemove "${key}" || status=1
                else
                    status=1
                fi
                ;;
            *) status=1 ;;
            esac
        fi
    done
    if [[ "${status}" == "0" ]] && padmFirewallStateHas masquerade:firewalld; then
        if ! remainingForwardPorts=$(firewall-cmd --zone=public --permanent --list-forward-ports); then
            status=1
        elif [[ -z "${remainingForwardPorts//[[:space:]]/}" ]]; then
            removeFirewalldMasqueradeRule || status=1
        fi
        [[ "${status}" != "0" ]] || padmFirewallStateRemove masquerade:firewalld || status=1
    fi
    [[ "${status}" != "0" || ! -f "${stateFile}" ]] || status=1
    return "${status}"
}

# 开放防火墙端口
allowPort() {
    local requestedPort=$1
    local type=${2:-tcp}
    local firewallPort=${requestedPort}
    local portStart portEnd
    local backend=
    local added=false
    PADM_LAST_ALLOW_PORT_ADDED=false
    [[ "${type}" == "tcp" || "${type}" == "udp" ]] || return 1
    if [[ "${requestedPort}" == *:* ]]; then
        portStart=${requestedPort%%:*}
        portEnd=${requestedPort#*:}
        validPortNumber "${portStart}" && validPortNumber "${portEnd}" && ((10#${portStart} <= 10#${portEnd})) || return 1
        firewallPort="${portStart}-${portEnd}"
    else
        validPortNumber "${requestedPort}" || return 1
    fi
    # 如果防火墙启动状态则添加相应的开放端口
    if command -v dpkg >/dev/null 2>&1 && dpkg -l | grep -Eq "^[[:space:]]*ii[[:space:]]+ufw[[:space:]]" && ufwActive; then
        if ! ufwRulePresent "${requestedPort}" "${type}"; then
            if ! sudo ufw allow "${requestedPort}/${type}" || ! checkUFWAllowPort "${requestedPort}" "${type}"; then
                sudo ufw delete allow "${requestedPort}/${type}" >/dev/null 2>&1 || true
                errorCard "${requestedPort}端口开放失败，已尝试回滚本次 ufw 规则"
                return 1
            fi
            backend=ufw
            added=true
        fi
    elif systemctl is-active --quiet firewalld 2>/dev/null; then
        if ! firewalldRulePresent "${firewallPort}" "${type}"; then
            if ! firewall-cmd --zone=public --permanent --add-port="${firewallPort}/${type}" || ! firewall-cmd --reload || ! checkFirewalldAllowPort "${firewallPort}" "${type}"; then
                firewall-cmd --zone=public --permanent --remove-port="${firewallPort}/${type}" >/dev/null 2>&1 || true
                firewall-cmd --reload >/dev/null 2>&1 || true
                errorCard "${requestedPort}端口开放失败，已尝试回滚本次 firewalld 规则"
                return 1
            fi
            backend=firewalld
            added=true
        fi
    elif rc-update show 2>/dev/null | grep -q ufw && ufwActive; then
        if ! ufwRulePresent "${requestedPort}" "${type}"; then
            if ! sudo ufw allow "${requestedPort}/${type}" || ! checkUFWAllowPort "${requestedPort}" "${type}"; then
                sudo ufw delete allow "${requestedPort}/${type}" >/dev/null 2>&1 || true
                errorCard "${requestedPort}端口开放失败，已尝试回滚本次 ufw 规则"
                return 1
            fi
            backend=ufw
            added=true
        fi
    elif dpkg-query -W -f='${db:Status-Abbrev}' netfilter-persistent 2>/dev/null | grep -q '^ii' && systemctl is-active --quiet netfilter-persistent; then
        if ! iptables -L | grep -Fq "allow ${requestedPort}/${type}(neil1123-vip)"; then
            if ! iptables -I INPUT -p "${type}" --dport "${requestedPort}" -m comment --comment "allow ${requestedPort}/${type}(neil1123-vip)" -j ACCEPT || ! netfilter-persistent save; then
                iptables -D INPUT -p "${type}" --dport "${requestedPort}" -m comment --comment "allow ${requestedPort}/${type}(neil1123-vip)" -j ACCEPT >/dev/null 2>&1 || true
                netfilter-persistent save >/dev/null 2>&1 || true
                errorCard "${requestedPort}端口开放失败，已尝试回滚本次 iptables 规则"
                return 1
            fi
            backend=iptables
            added=true
        fi
    fi
    if [[ "${added}" == "true" ]]; then
        if ! padmFirewallStateAdd "port:${backend}:${type}:${requestedPort}"; then
            removeFirewallPortRule "${backend}" "${requestedPort}" "${type}" >/dev/null 2>&1 || true
            errorCard "${requestedPort}端口状态记录失败，已尝试回滚本次防火墙规则"
            return 1
        fi
        PADM_LAST_ALLOW_PORT_ADDED=true
    fi
}

allowPortTcpAndUdp() {
    local requestedPort=$1
    local tcpAdded=false
    allowPort "${requestedPort}" || return 1
    [[ "${PADM_LAST_ALLOW_PORT_ADDED:-false}" == "true" ]] && tcpAdded=true
    allowPort "${requestedPort}" udp && return 0
    if [[ "${tcpAdded}" == "true" ]] && ! denyPort "${requestedPort}"; then
        errorCard "${requestedPort}端口 TCP 防火墙规则回滚失败，请检查防火墙状态"
    fi
    return 1
}

validPortNumber() {
    local port=$1
    [[ "${port}" =~ ^[0-9]{1,5}$ ]] && ((10#${port} >= 1 && 10#${port} <= 65535))
}

# 获取公网 IP
fetchPublicIP() {
    local type=$1
    local currentIP
    [[ "${type}" == "4" || "${type}" == "6" ]] || return 1
    currentIP=$(curl -fsS --connect-timeout 5 --max-time 10 "-${type}" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null |
        awk -F= '$1 == "ip" {print $2; exit}') || return 1
    if [[ "${type}" == "4" ]]; then
        [[ "${currentIP}" =~ ^[0-9]+(\.[0-9]+){3}$ ]] && padmIsValidHostName "${currentIP}" || return 1
    else
        padmIsValidIPv6Address "${currentIP}" || return 1
    fi
    printf '%s\n' "${currentIP}"
}

hasIPv6Connectivity() {
    fetchPublicIP 6 >/dev/null 2>&1
}

getPublicIP() {
    local type=${1:-4}
    if [[ -n "${currentHost:-}" && -z "${1:-}" ]] && [[ "${singBoxVLESSRealityVisionSNI:-}" == "${currentHost}" || "${singBoxVLESSRealityGRPCSNI:-}" == "${currentHost}" || "${xrayVLESSRealitySNI:-}" == "${currentHost}" ]]; then
        echo "${currentHost}"
    else
        local currentIP=
        currentIP=$(fetchPublicIP "${type}" 2>/dev/null || true)
        if [[ -z "${currentIP}" && -z "${1:-}" ]]; then
            currentIP=$(fetchPublicIP 6 2>/dev/null || true)
        fi
        echo "${currentIP}"
    fi

}


# 输出 ufw 端口开放状态
checkUFWAllowPort() {
    if ufwRulePresent "$1" "${2:-tcp}"; then
        successCard "$1端口开放成功"
    else
        errorCard "$1端口开放失败"
        return 1
    fi
}


# 输出 firewalld 端口开放状态
checkFirewalldAllowPort() {
    if firewalldRulePresent "$1" "${2:-tcp}"; then
        successCard "$1端口开放成功"
    else
        errorCard "$1端口开放失败"
        return 1
    fi
}


# 通过 DNS 检查域名 IP
checkDNSIP() {
    local domain=$1
    local dnsIP=
    ipType=4
    local dnsRetryCount=0
    while [[ ${dnsRetryCount} -lt 3 && -z "${dnsIP}" ]]; do
        dnsIP=$(dig @1.1.1.1 +time=2 +short "${domain}" | grep -E "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$")
        if [[ -z "${dnsIP}" ]]; then
            dnsIP=$(dig @8.8.8.8 +time=2 +short "${domain}" | grep -E "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$")
        fi
        dnsRetryCount=$((dnsRetryCount + 1))
        if [[ -z "${dnsIP}" && ${dnsRetryCount} -lt 3 ]]; then
            statusCard "DNS 重试" "未获取到域名 IPv4 地址，等待后重试(${dnsRetryCount}/3)"
            sleep 2
        fi
    done
    if [[ "${dnsIP}" == *"timed out"* || -z "${dnsIP}" ]]; then
        echo
        statusCard "DNS 解析回退" "无法通过 DNS 获取域名 IPv4 地址" "尝试检查域名 IPv6 地址"
        dnsIP=$(dig @2606:4700:4700::1111 +time=2 aaaa +short "${domain}")
        ipType=6
        if [[ "${dnsIP}" == *"network unreachable"* || -z "${dnsIP}" ]]; then
            errorCard "无法通过DNS获取域名IPv6地址，退出安装"
            return 1
        fi
    fi
    local publicIP=

    publicIP=$(getPublicIP "${ipType}")
    if [[ "${publicIP}" != "${dnsIP}" ]]; then
        statusCard "域名 IP 不一致" "当前 VPS IP：${publicIP}" "DNS 解析 IP：${dnsIP}" "请检查域名解析是否生效且正确"
        return 1
    else
        successCard "域名IP校验通过"
    fi
    return 0
}

writeCheckPortOpenNginxConfig() {
    local port=$1
    local domain=$2
    local listenIPv6PortConfig=$3
    local targetPath
    local restoreMessage
    if ! targetPath=$(nginxConfigFilePath checkPortOpen.conf); then
        CHECK_PORT_OPEN_NGINX_CONFIG_ERROR="端口检测 Nginx 配置路径异常"
        return 1
    fi
    local tmpPath
    local backupPath="${targetPath}.bak"
    local targetDir
    local nginxTestLog
    nginxTestLog="$(padmFallbackTmpFilePath padm-check-port-open-nginx-test.log)"
    CHECK_PORT_OPEN_NGINX_CONFIG_ERROR=
    if ! validPortNumber "${port}" || ! padmIsValidHostName "${domain}"; then
        CHECK_PORT_OPEN_NGINX_CONFIG_ERROR="端口检测 Nginx 监听端口或域名不合法"
        return 1
    fi
    if ! padmCommitTargetIsFileLike "${targetPath}"; then
        coreSetManualCheckMessage CHECK_PORT_OPEN_NGINX_CONFIG_ERROR "端口检测 Nginx 配置目标异常" " ${targetPath}"
        return 1
    fi
    targetDir=$(dirname -- "${targetPath}")
    padmEnsureSafeDirectory "${targetDir}" || { CHECK_PORT_OPEN_NGINX_CONFIG_ERROR="端口检测 Nginx 配置目录创建失败"; return 1; }
    padmCreateTempFileForTarget tmpPath "${targetPath}" nginx || { CHECK_PORT_OPEN_NGINX_CONFIG_ERROR="端口检测 Nginx 配置临时文件写入失败"; return 1; }
    cat >"${tmpPath}" <<EOF || { padmRemoveCleanupPath "${tmpPath}"; CHECK_PORT_OPEN_NGINX_CONFIG_ERROR="端口检测 Nginx 配置临时文件写入失败"; return 1; }
server {
    listen ${port};
    ${listenIPv6PortConfig}
    server_name ${domain};
    location /checkPort {
        return 200 'fjkvymb6len';
    }
    location /ip {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header REMOTE-HOST \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        default_type text/plain;
        return 200 \$proxy_add_x_forwarded_for;
    }
}
EOF
    if command -v nginx >/dev/null 2>&1; then
        if [[ -f "${targetPath}" ]] && ! backupManagedFileToPath "${targetPath}" "${backupPath}" 644; then
            padmRemoveCleanupPath "${tmpPath}"
            CHECK_PORT_OPEN_NGINX_CONFIG_ERROR="端口检测 Nginx 旧配置备份失败"
            return 1
        fi
        if ! commitGeneratedFile "${tmpPath}" "${targetPath}" 644; then
            padmRemoveCleanupPath "${tmpPath}"
            removeManagedFilesIfPresentIgnoreFailure "${backupPath}"
            CHECK_PORT_OPEN_NGINX_CONFIG_ERROR="端口检测 Nginx 配置提交失败"
            return 1
        fi
        if ! nginx -t >"${nginxTestLog}" 2>&1; then
            if [[ -f "${backupPath}" ]]; then
                if ! restoreManagedFileFromBackup "${backupPath}" "${targetPath}" 644; then
                    coreSetSingleRestoreResultMessage restoreMessage "端口检测 Nginx 配置校验失败" false "已恢复旧配置" "旧配置" " ${targetPath} 和 ${backupPath}" || true
                    CHECK_PORT_OPEN_NGINX_CONFIG_ERROR="${restoreMessage}"
                    return 1
                fi
            else
                if ! removeManagedFileIfPresent "${targetPath}"; then
                    coreSetNewConfigCleanupFailureMessage restoreMessage "端口检测 Nginx 配置校验失败" "${targetPath}"
                    CHECK_PORT_OPEN_NGINX_CONFIG_ERROR="${restoreMessage}"
                    return 1
                fi
            fi
            CHECK_PORT_OPEN_NGINX_CONFIG_ERROR="端口检测 Nginx 配置校验失败"
            return 1
        fi
        if [[ -f "${backupPath}" ]] && ! removeManagedFileIfPresent "${backupPath}"; then
            coreSetManualCheckMessage CHECK_PORT_OPEN_NGINX_CONFIG_ERROR "端口检测 Nginx 配置备份清理失败" " ${backupPath}"
            return 1
        fi
    else
        if ! commitGeneratedFile "${tmpPath}" "${targetPath}" 644; then
            padmRemoveCleanupPath "${tmpPath}"
            CHECK_PORT_OPEN_NGINX_CONFIG_ERROR="端口检测 Nginx 配置提交失败"
            return 1
        fi
    fi
}

removeCheckPortOpenNginxConfig() {
    local targetPath
    targetPath=$(nginxConfigFilePath checkPortOpen.conf) || return 1
    rm -f -- "${targetPath}" >/dev/null 2>&1
}

checkPortOpenBackupCreate() {
    local resultVar=$1
    local backupRoot targetPath nginxMainConf file
    local -a backupArgs=()

    padmCreateTmpRootPath backupRoot padm-check-port-open.XXXXXX -d || return 1
    for file in alone.conf sing_box_VMess_HTTPUpgrade.conf subscribe.conf checkPortOpen.conf; do
        targetPath=$(nginxConfigFilePath "${file}") || { padmRemoveCleanupPath "${backupRoot}"; return 1; }
        backupArgs+=("nginx/${file}" "${targetPath}")
    done
    backupArgs+=(
        "stream/padm-reality.conf" "$(realityStreamSplitConfFile)"
        "stream/reality-state.json" "$(realityStreamSplitStateFile)"
    )
    nginxMainConf=$(realityStreamSplitNginxConf)
    if [[ -n "${nginxMainConf}" ]]; then
        backupArgs+=("nginx/nginx.conf" "${nginxMainConf}")
    fi
    if ! padmWriteManagedFileBackupManifest "${backupRoot}" "${backupArgs[@]}"; then
        padmRemoveCleanupPath "${backupRoot}"
        return 1
    fi
    printf -v "${resultVar}" '%s' "${backupRoot}"
}

checkPortOpenRestoreCoreServiceState() {
    local wasRunning=$1
    local runningFn=$2
    local actionFn=$3
    if [[ "${wasRunning}" == "true" ]]; then
        "${runningFn}" || runCoreServiceActionAllowFailure "${actionFn}" start
    elif "${runningFn}"; then
        runCoreServiceActionAllowFailure "${actionFn}" stop
    fi
}

checkPortOpenAbort() {
    local backupDir=$1
    local singBoxWasRunning=$2
    local xrayWasRunning=$3
    local nginxWasRunning=$4
    local nginxConfigChanged=$5
    local reason=$6
    local status=0

    padmRestoreManagedFileBackupManifest "${backupDir}" || status=1
    checkPortOpenRestoreCoreServiceState "${singBoxWasRunning}" singBoxRunning handleSingBox || status=1
    checkPortOpenRestoreCoreServiceState "${xrayWasRunning}" xrayRunning handleXray || status=1
    if [[ "${nginxConfigChanged}" == "true" ]]; then
        if nginxRunning; then
            runCoreServiceActionAllowFailure handleNginx stop || status=1
        fi
        if [[ "${nginxWasRunning}" == "true" ]] && ! nginxRunning; then
            runCoreServiceActionAllowFailure handleNginx start || status=1
        fi
    else
        checkPortOpenRestoreCoreServiceState "${nginxWasRunning}" nginxRunning handleNginx || status=1
    fi
    if [[ "${status}" -eq 0 ]]; then
        padmRemoveCleanupPath "${backupDir}"
        errorCard "${reason}，已恢复原配置和服务状态"
    else
        padmForgetCleanupPath "${backupDir}"
        errorCard "${reason}，恢复失败，请手动检查备份目录: ${backupDir}"
    fi
    return 1
}

# 检查端口实际开放状态
checkPortOpen() {
    local port=$1
    local domain=$2
    local checkPortOpenResult=
    local localIP=
    local backupDir=
    local singBoxWasRunning=false
    local xrayWasRunning=false
    local nginxWasRunning=false
    local nginxConfigChanged=false

    allowPort "${port}" || return 1
    checkPortOpenBackupCreate backupDir || { errorCard "端口检测配置备份失败"; return 1; }
    singBoxRunning && singBoxWasRunning=true
    xrayRunning && xrayWasRunning=true
    nginxRunning && nginxWasRunning=true
    if ! runCoreServiceActionAllowFailure handleSingBox stop >/dev/null 2>&1; then
        checkPortOpenAbort "${backupDir}" "${singBoxWasRunning}" "${xrayWasRunning}" "${nginxWasRunning}" "${nginxConfigChanged}" "sing-box 服务停止失败，无法检测端口开放状态"
        return 1
    fi
    if ! runCoreServiceActionAllowFailure handleXray stop >/dev/null 2>&1; then
        checkPortOpenAbort "${backupDir}" "${singBoxWasRunning}" "${xrayWasRunning}" "${nginxWasRunning}" "${nginxConfigChanged}" "Xray 服务停止失败，无法检测端口开放状态"
        return 1
    fi
    nginxConfigChanged=true
    if ! cleanAgentNginxConf; then
        checkPortOpenAbort "${backupDir}" "${singBoxWasRunning}" "${xrayWasRunning}" "${nginxWasRunning}" "${nginxConfigChanged}" "Nginx 配置清理失败，无法检测端口开放状态"
        return 1
    fi

    if [[ -z "${btDomain}" ]]; then

        if ! runCoreServiceActionAllowFailure handleNginx stop; then
            checkPortOpenAbort "${backupDir}" "${singBoxWasRunning}" "${xrayWasRunning}" "${nginxWasRunning}" "${nginxConfigChanged}" "Nginx 停止失败，无法检测 ${port} 端口开放状态"
            return 1
        fi
        # 初始化 Nginx 端口检测配置
        local listenIPv6PortConfig=

        if hasIPv6Connectivity; then
            listenIPv6PortConfig="listen [::]:${port};"
        fi
        if ! writeCheckPortOpenNginxConfig "${port}" "${domain}" "${listenIPv6PortConfig}"; then
            statusCard "Nginx 配置校验失败" "无法检测 ${port} 端口开放状态" "${CHECK_PORT_OPEN_NGINX_CONFIG_ERROR:-请检查上方 Nginx 配置错误}" "也可以执行 nginx -t 查看配置错误"
            checkPortOpenAbort "${backupDir}" "${singBoxWasRunning}" "${xrayWasRunning}" "${nginxWasRunning}" "${nginxConfigChanged}" "端口检测 Nginx 配置写入失败"
            return 1
        fi
        if ! runCoreServiceActionAllowFailure handleNginx start; then
            nginxStartFailureCard "无法检测 ${port} 端口开放状态" "请检查上方 Nginx 启动失败日志" "也可以执行 nginx -t 查看配置错误"
            removeCheckPortOpenNginxConfig || true
            checkPortOpenAbort "${backupDir}" "${singBoxWasRunning}" "${xrayWasRunning}" "${nginxWasRunning}" "${nginxConfigChanged}" "端口检测 Nginx 启动失败"
            return 1
        fi
        if [[ -z $(pgrep -f "nginx") ]]; then
            nginxStartFailureCard "无法检测 ${port} 端口开放状态" "请检查上方 Nginx 启动失败日志" "也可以执行 nginx -t 查看配置错误"
            removeCheckPortOpenNginxConfig || true
            checkPortOpenAbort "${backupDir}" "${singBoxWasRunning}" "${xrayWasRunning}" "${nginxWasRunning}" "${nginxConfigChanged}" "端口检测未发现 Nginx 进程"
            return 1
        fi
        # 检查域名和端口开放状态
        checkPortOpenResult=$(curl -s -m 10 "http://${domain}:${port}/checkPort")
        localIP=$(curl -s -m 10 "http://${domain}:${port}/ip")
        removeCheckPortOpenNginxConfig || {
            checkPortOpenAbort "${backupDir}" "${singBoxWasRunning}" "${xrayWasRunning}" "${nginxWasRunning}" "${nginxConfigChanged}" "端口检测 Nginx 配置删除失败"
            return 1
        }
        if ! runCoreServiceActionAllowFailure handleNginx stop; then
            checkPortOpenAbort "${backupDir}" "${singBoxWasRunning}" "${xrayWasRunning}" "${nginxWasRunning}" "${nginxConfigChanged}" "Nginx 服务停止失败，端口检测配置已删除"
            return 1
        fi
        if [[ "${checkPortOpenResult}" == "fjkvymb6len" ]]; then
            successCard "检测到${port}端口已开放"
        else
            successCard "未检测到${port}端口开放，退出安装"
            if [[ "${checkPortOpenResult}" == *cloudflare* ]]; then
                statusCard "端口开放检测失败" "检测到 Cloudflare 响应" "请关闭云朵后等待三分钟重新尝试"
            else
                if [[ -z "${checkPortOpenResult}" ]]; then
                    statusCard "端口开放检测失败" "请检查是否有网页防火墙，例如 Oracle 等云服务商" "请检查是否安装过 Nginx 并存在配置冲突" "仍无法处理时，可以尝试 DD 纯净系统后重新执行"
                else
                    statusCard "端口开放检测失败" "错误日志：${checkPortOpenResult}" "请将此错误日志通过 issues 提交反馈"
                fi
            fi
            checkPortOpenAbort "${backupDir}" "${singBoxWasRunning}" "${xrayWasRunning}" "${nginxWasRunning}" "${nginxConfigChanged}" "未检测到 ${port} 端口开放"
            return 1
        fi
        if ! checkIP "${localIP}"; then
            checkPortOpenAbort "${backupDir}" "${singBoxWasRunning}" "${xrayWasRunning}" "${nginxWasRunning}" "${nginxConfigChanged}" "端口回源 IP 检查失败"
            return 1
        fi
    fi
    padmRemoveCleanupPath "${backupDir}"
    return 0
}


# 检查 IP 回源结果
checkIP() {
    statusCard "域名 IP 检查" "检查域名 IP 中"
    local localIP=$1
    local normalizedIP
    local extraIP
    normalizedIP=$(echo "${localIP}" | sed '1{s/[^(]*(//;s/).*//;q}')
    extraIP=$(echo "${localIP}" | awk -F "[,]" '{print $2}')

    if [[ -z ${localIP} ]] || ! grep -q '\.' <<<"${normalizedIP}" && ! grep -q ':' <<<"${normalizedIP}"; then
        errorCard "未检测到当前域名的ip"
        echoContent title "\n┌─ 域名解析排障 ─────────────────────────────────────"
        menuLine "请依次进行下列检查"
        menuLine "检查域名是否书写正确"
        menuLine "检查域名 DNS 解析是否正确"
        menuLine "如解析正确，请等待 DNS 生效，预计三分钟内生效"
        menuLine "如报 Nginx 启动问题，请手动启动 nginx 查看错误；仍无法处理请提交 issue"
        menuClose

        statusCard "后续建议" "如以上设置都正确，请重新安装纯净系统后再次尝试"

        if [[ -n ${localIP} ]]; then
            statusCard "检测返回值异常" "异常结果：${localIP}" "建议手动卸载 Nginx 后重新执行脚本"
        fi
        return 1
    else
        if [[ "${extraIP}" == *.* || "${extraIP}" == *:* ]]; then
            statusCard "检测到多个 IP" "请确认是否关闭 Cloudflare 云朵" "关闭云朵后等待三分钟再重试" "检测到的 IP：${localIP}"
            return 1
        fi
        successCard "检查当前域名IP正确"
    fi
    return 0
}

# 检测端口是否占用
checkPort() {
    if [[ -z "$1" ]] || ! lsof -i "tcp:$1" | grep -q LISTEN; then
        return
    fi

    local port=$1
    local portProcess
    portProcess=$(lsof -nP -i "tcp:${port}" | grep LISTEN)
    errorCard "${port}端口被占用"
    echoContent yellow "${portProcess}"

    if echo "${portProcess}" | grep -qiE "xray|sing-box|/etc/padm"; then
        statusCard "端口占用" "检测到占用进程属于本脚本服务" "尝试自动停止后继续安装"
        if ! runCoreServiceActionAllowFailure handleXray stop >/dev/null 2>&1; then
            errorCard "Xray 服务停止失败，请手动处理${port}端口占用后重新执行"
            return 1
        fi
        if ! runCoreServiceActionAllowFailure handleSingBox stop >/dev/null 2>&1; then
            errorCard "sing-box 服务停止失败，请手动处理${port}端口占用后重新执行"
            return 1
        fi
        sleep 1
    elif echo "${portProcess}" | grep -qiE "nginx|openresty"; then
        statusCard "端口占用" "检测到 ${port} 端口被 Nginx/OpenResty 占用"
        autoRead stop_port_service_confirm "是否停止该服务并继续安装？[y/n]:" stopPortProcessStatus
        if [[ "${stopPortProcessStatus}" == "y" ]]; then
            if ! runCoreServiceActionAllowFailure handleNginx stop >/dev/null 2>&1; then
                errorCard "Nginx 服务停止失败，请手动处理${port}端口占用后重新执行"
                return 1
            fi
            systemctl stop openresty >/dev/null 2>&1
            systemctl stop nginx >/dev/null 2>&1
            sleep 1
        else
            errorCard "已取消安装，请手动处理${port}端口占用后重新执行"
            return 1
        fi
    else
        autoRead stop_port_process_confirm "是否停止占用${port}端口的进程并继续安装？[y/n]:" stopPortProcessStatus
        if [[ "${stopPortProcessStatus}" == "y" ]]; then
            lsof -ti "tcp:${port}" | xargs -r kill
            sleep 1
        else
            errorCard "已取消安装，请手动处理${port}端口占用后重新执行"
            return 1
        fi
    fi

    if lsof -i "tcp:${port}" | grep -q LISTEN; then
        errorCard "${port}端口仍被占用，请手动关闭后安装\n"
        lsof -nP -i "tcp:${port}" | grep LISTEN
        return 1
    fi
}
