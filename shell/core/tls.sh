#!/usr/bin/env bash

acmeHomeDir() {
    local homeDir="${HOME:-/root}"
    printf '%s\n' "${homeDir%/}/.acme.sh"
}

acmeAccountFile() {
    printf '%s\n' "$(acmeHomeDir)/account.conf"
}

tlsManagedDir() {
    local tlsDir="${PADM_TLS_DIR:-/etc/padm/tls}"
    tlsDir=$(padmResolveManagedAbsolutePath "${tlsDir}") || return 1
    printf '%s\n' "${tlsDir}"
}

tlsSslTypeFile() {
    local tlsDir
    tlsDir=$(tlsManagedDir) || return 1
    printf '%s/ssl_type\n' "${tlsDir}"
}

tlsAcmeLogFile() {
    local tlsDir
    tlsDir=$(tlsManagedDir) || return 1
    printf '%s/acme.log\n' "${tlsDir}"
}

tlsDomainNameIsSafe() {
    padmIsValidHostName "$1"
}

tlsEmailAddressIsSafe() {
    local email=$1
    local localPart domainPart
    [[ -n "${email}" && ${#email} -le 254 && "${email}" == *@* && "${email}" != *@*@* ]] || return 1
    localPart=${email%@*}
    domainPart=${email#*@}
    [[ -n "${localPart}" && ${#localPart} -le 64 && "${localPart}" =~ ^[A-Za-z0-9._%+-]+$ ]] || return 1
    tlsDomainNameIsSafe "${domainPart}"
}

tlsCertificatePairExists() {
    local tlsDir=$1
    local certDomain=$2
    tlsDomainNameIsSafe "${certDomain}" || return 1
    [[ -s "${tlsDir}/${certDomain}.crt" && -s "${tlsDir}/${certDomain}.key" ]]
}

# 自定义 Email
customSSLEmail() {
    local accountFile accountStage retryEmail=false
    accountFile=$(acmeAccountFile)
    if [[ "${1:-}" == *"validate email"* ]]; then
        autoRead tls_email_retry "是否重新输入邮箱地址[y/n]:" sslEmailStatus
        if [[ "${sslEmailStatus}" == "y" ]]; then
            retryEmail=true
        else
            return 1
        fi
    fi

    if [[ -d "$(acmeHomeDir)" && -f "${accountFile}" ]]; then
        if [[ "${retryEmail}" == "true" ]] || { ! grep -q "ACCOUNT_EMAIL" <"${accountFile}" && ! echo "${sslType}" | grep -q "letsencrypt"; }; then
            autoRead tls_account_email "请输入邮箱地址:" sslEmail
            if tlsEmailAddressIsSafe "${sslEmail}"; then
                padmCreateTempFileForTarget accountStage "${accountFile}" account || return 1
                if ! sed '/ACCOUNT_EMAIL/d' "${accountFile}" >"${accountStage}" || ! printf "ACCOUNT_EMAIL='%s'\n" "${sslEmail}" >>"${accountStage}"; then
                    padmRemoveCleanupPath "${accountStage}"
                    return 1
                fi
                commitGeneratedFile "${accountStage}" "${accountFile}" 600 || { padmRemoveCleanupPath "${accountStage}"; return 1; }
                successCard "添加完毕"
            else
                echoContent yellow "请重新输入正确的邮箱格式[例: username@example.com]"
                return 1
            fi
        fi
    fi

}

# DNS API申请证书
switchDNSAPI() {
    autoRead dns_api "是否使用DNS API申请证书[支持NAT]？[y/n]:" dnsAPIStatus
    if [[ "${dnsAPIStatus}" == "y" ]]; then
        echoContent title "\n┌─ DNS API ──────────────────────────────────────────"
        menuRecommendedItem 1 "cloudflare" "默认 DNS API"
        menuItem 2 "aliyun" "阿里云 DNS API"
        menuClose
        autoRead dns_api_type "请选择[回车]使用默认:" selectDNSAPIType
        case ${selectDNSAPIType} in
        2)
            dnsAPIType="aliyun"
            ;;
        *)
            dnsAPIType="cloudflare"
            ;;
        esac
        initDNSAPIConfig "${dnsAPIType}" || return 1
    fi
}

# 初始化 DNS API 配置
initDNSAPIConfig() {
    if [[ "$1" == "cloudflare" ]]; then
        echoContent title "\n┌─ Cloudflare DNS API ──────────────────────────────"
        menuLine "请创建限制到目标 Zone 的 API Token"
        menuLine "权限建议：Zone:DNS:Edit；如需自动识别 Zone，可附加 Zone:Zone:Read"
        menuClose
        autoRead cloudflare_api_token "请输入API Token:" cfAPIToken
        if [[ -z "${cfAPIToken}" ]]; then
            errorCard "输入为空，请重新输入"
            initDNSAPIConfig "$1" || return 1
        else
            autoRead cloudflare_zone_id "请输入Zone ID[可选，回车自动识别]:" cfZoneID
            echo
            if ! echo "${dnsTLSDomain}" | grep -q "\." || [[ -z $(echo "${dnsTLSDomain}" | awk -F "[.]" '{print $1}') ]]; then
                successCard "不支持此域名申请通配符证书，建议使用此格式[xx.xx.xx]"
                return 1
            fi
            autoRead dns_api_wildcard "是否使用*.${dnsTLSDomain}进行API申请通配符证书？[y/n]:" dnsAPIStatus
        fi
    elif [[ "$1" == "aliyun" ]]; then
        autoRead aliyun_api_key "请输入Ali Key:" aliKey
        autoRead aliyun_api_secret "请输入Ali Secret:" aliSecret
        if [[ -z "${aliKey}" || -z "${aliSecret}" ]]; then
            errorCard "输入为空，请重新输入"
            initDNSAPIConfig "$1" || return 1
        else
            echo
            if ! echo "${dnsTLSDomain}" | grep -q "\." || [[ -z $(echo "${dnsTLSDomain}" | awk -F "[.]" '{print $1}') ]]; then
                successCard "不支持此域名申请通配符证书，建议使用此格式[xx.xx.xx]"
                return 1
            fi
            autoRead dns_api_wildcard "是否使用*.${dnsTLSDomain}进行API申请通配符证书？[y/n]:" dnsAPIStatus
        fi
    fi
}

# 选择ssl安装类型
switchSSLType() {
    if [[ -z "${sslType:-}" ]]; then
        local sslTypeFile sslTypeStage
        echoContent title "\n┌─ 证书 CA ──────────────────────────────────────────"
        menuRecommendedItem 1 "letsencrypt" "默认 CA"
        menuItem 2 "zerossl" "ZeroSSL CA"
        menuItem 3 "buypass" "不支持 DNS 申请"
        menuClose
        autoRead tls_ca "请选择[回车]使用默认:" selectSSLType
        case ${selectSSLType} in
        2)
            sslType="zerossl"
            ;;
        3)
            sslType="buypass"
            ;;
        *)
            sslType="letsencrypt"
            ;;
        esac
        if [[ -n "${dnsAPIType:-}" && "${sslType}" == "buypass" ]]; then
            errorCard "buypass不支持API申请证书"
            return 1
        fi
        sslTypeFile=$(tlsSslTypeFile) || return 1
        padmEnsureSafeDirectory "$(dirname -- "${sslTypeFile}")" || return 1
        padmCreateTempFileForTarget sslTypeStage "${sslTypeFile}" ssltype || return 1
        printf '%s\n' "${sslType}" >"${sslTypeStage}" || { padmRemoveCleanupPath "${sslTypeStage}"; return 1; }
        commitGeneratedFile "${sslTypeStage}" "${sslTypeFile}" 644 || { padmRemoveCleanupPath "${sslTypeStage}"; return 1; }
    fi
}


# 选择 acme.sh 证书签发方式
selectAcmeInstallSSL() {
    if [[ "${ipType:-}" == "6" ]]; then
        sslIPv6="--listen-v6"
    fi

    acmeInstallSSL

    readAcmeTLS
}


# 安装 TLS 证书
acmeInstallSSL() {
    local dnsAPIDomain="${tlsDomain}"
    local dnsAPIExtraDomain=
    local acmeLogFile
    acmeLogFile=$(tlsAcmeLogFile) || return 1
    padmEnsureSafeDirectory "$(dirname -- "${acmeLogFile}")" || return 1
    if [[ "${dnsAPIStatus:-}" == "y" ]]; then
        dnsAPIDomain="*.${dnsTLSDomain}"
        dnsAPIExtraDomain="-d ${dnsTLSDomain}"
    fi

    if [[ "${dnsAPIType:-}" == "cloudflare" ]]; then
        successCard "DNS API 生成证书中"
        if [[ -n "${cfZoneID:-}" ]]; then
            CF_Token="${cfAPIToken}" CF_Zone_ID="${cfZoneID}" "$HOME/.acme.sh/acme.sh" --issue -d "${dnsAPIDomain}" ${dnsAPIExtraDomain} --dns dns_cf -k ec-256 --server "${sslType}" ${sslIPv6:-} 2>&1 | tee -a "${acmeLogFile}" >/dev/null
        else
            CF_Token="${cfAPIToken}" "$HOME/.acme.sh/acme.sh" --issue -d "${dnsAPIDomain}" ${dnsAPIExtraDomain} --dns dns_cf -k ec-256 --server "${sslType}" ${sslIPv6:-} 2>&1 | tee -a "${acmeLogFile}" >/dev/null
        fi
    elif [[ "${dnsAPIType:-}" == "aliyun" ]]; then
        successCard "DNS API 生成证书中"
        Ali_Key="${aliKey}" Ali_Secret="${aliSecret}" "$HOME/.acme.sh/acme.sh" --issue -d "${dnsAPIDomain}" ${dnsAPIExtraDomain} --dns dns_ali -k ec-256 --server "${sslType}" ${sslIPv6:-} 2>&1 | tee -a "${acmeLogFile}" >/dev/null
    else
        successCard "生成证书中"
        sudo "$HOME/.acme.sh/acme.sh" --issue -d "${tlsDomain}" --standalone -k ec-256 --server "${sslType}" ${sslIPv6:-} 2>&1 | tee -a "${acmeLogFile}" >/dev/null
    fi
}

installTLSFromAcme() {
    local tlsDomain=${domain}
    local tlsDir
    local crtFile
    local keyFile
    local acmeLogFile
    local backupDir=
    local backupCrt=
    local backupKey=
    local installStatus=0

    tlsDomainNameIsSafe "${tlsDomain}" || { errorCard "TLS 域名不合法"; return 1; }
    tlsDir=$(tlsManagedDir) || return 1
    crtFile="${tlsDir}/${tlsDomain}.crt"
    keyFile="${tlsDir}/${tlsDomain}.key"
    acmeLogFile=$(tlsAcmeLogFile) || return 1

    if [[ -s "${crtFile}" && -s "${keyFile}" ]]; then
        padmCreateTmpRootPath backupDir padm-tls-install.XXXXXX -d || return 1
        backupCrt="${backupDir}/$(basename -- "${crtFile}")"
        backupKey="${backupDir}/$(basename -- "${keyFile}")"
        cp -p "${crtFile}" "${backupCrt}" || { padmRemoveCleanupPath "${backupDir}"; return 1; }
        cp -p "${keyFile}" "${backupKey}" || { padmRemoveCleanupPath "${backupDir}"; return 1; }
    fi

    if [[ "${installedDNSAPIStatus:-}" == "true" ]]; then
        sudo "$HOME/.acme.sh/acme.sh" --installcert -d "*.${dnsTLSDomain}" --fullchainpath "${crtFile}" --keypath "${keyFile}" --ecc >/dev/null || installStatus=$?
    else
        sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${tlsDomain}" --fullchainpath "${crtFile}" --keypath "${keyFile}" --ecc >/dev/null || installStatus=$?
    fi

    if [[ "${installStatus}" -ne 0 || ! -f "${crtFile}" || ! -f "${keyFile}" ]] || [[ -z $(cat "${keyFile}") || -z $(cat "${crtFile}") ]]; then
        tail -n 10 "${acmeLogFile}" 2>/dev/null || true
        if [[ -n "${backupDir}" ]]; then
            if ! restoreManagedFileFromBackup "${backupCrt}" "${crtFile}" 644; then
                padmForgetCleanupPath "${backupDir}"
                errorCard "TLS安装失败，旧证书恢复失败，请手动检查备份目录: ${backupDir}"
                return 1
            fi
            if ! restoreManagedFileFromBackup "${backupKey}" "${keyFile}" 600; then
                padmForgetCleanupPath "${backupDir}"
                errorCard "TLS安装失败，旧私钥恢复失败，请手动检查备份目录: ${backupDir}"
                return 1
            fi
        fi
        if [[ ${installTLSCount:-} == "1" ]]; then
            [[ -n "${backupDir}" ]] && padmRemoveCleanupPath "${backupDir}"
            errorCard "TLS安装失败，请检查acme日志"
            return 1
        fi

        installTLSCount=1
        echo

        if tail -n 10 "${acmeLogFile}" | grep -q "Could not validate email address as valid"; then
            errorCard "邮箱无法通过SSL厂商验证，请重新输入"
            echo
            customSSLEmail "validate email" || {
                [[ -n "${backupDir}" ]] && padmRemoveCleanupPath "${backupDir}"
                return 1
            }
            [[ -n "${backupDir}" ]] && padmRemoveCleanupPath "${backupDir}"
            installTLSFromAcme || return 1
        else
            [[ -n "${backupDir}" ]] && padmRemoveCleanupPath "${backupDir}"
            installTLSFromAcme || return 1
        fi
    fi

    [[ -n "${backupDir}" ]] && padmRemoveCleanupPath "${backupDir}"
    successCard "TLS生成成功"
}

restoreTLSReinstallBackup() {
    local backupDir=$1
    local tlsDir=$2
    local reason=$3

    if cp -a "${backupDir}/." "${tlsDir}/" >/dev/null 2>&1; then
        padmRemoveCleanupPath "${backupDir}"
        return 0
    fi
    padmForgetCleanupPath "${backupDir}"
    errorCard "${reason}，且恢复失败，请手动检查备份目录: ${backupDir}"
    return 1
}

# 安装 TLS 证书
installTLS() {
    progressCard "$1" "申请 TLS 证书"
    readAcmeTLS
    local tlsDomain=${domain}
    local tlsDir
    local crtFile
    local keyFile
    local reinstallBackupDir=
    tlsDomainNameIsSafe "${tlsDomain}" || { errorCard "TLS 域名不合法"; return 1; }
    tlsDir=$(tlsManagedDir) || return 1
    crtFile="${tlsDir}/${tlsDomain}.crt"
    keyFile="${tlsDir}/${tlsDomain}.key"

    if [[ -f "${crtFile}" && -f "${keyFile}" && -n $(cat "${crtFile}") ]] || [[ -d "$HOME/.acme.sh/${tlsDomain}_ecc" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]] || [[ "${installedDNSAPIStatus:-}" == "true" ]]; then
        successCard "检测到证书"
        renewalTLS

        if [[ -z $(find "${tlsDir}/" -name "${tlsDomain}.crt") ]] || [[ -z $(find "${tlsDir}/" -name "${tlsDomain}.key") ]] || [[ -z $(cat "${crtFile}") ]]; then
            installTLSFromAcme || return 1
        else
            if [[ -d "$HOME/.acme.sh/${tlsDomain}_ecc" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]] || [[ "${installedDNSAPIStatus:-}" == "true" ]]; then
                if [[ -z "${lastInstallationConfig}" ]]; then
                    tlsCertificateCard "如未过期或者自定义证书请选择 [n]"
                    autoRead tls_reinstall "是否重新安装？[y/n]:" reInstallStatus
                    if [[ "${reInstallStatus}" == "y" ]]; then
                        padmCreateTmpRootPath reinstallBackupDir padm-tls-reinstall.XXXXXX -d || return 1
                        if ! cp -a "${tlsDir}/." "${reinstallBackupDir}/" >/dev/null 2>&1; then
                            padmRemoveCleanupPath "${reinstallBackupDir}"
                            return 1
                        fi
                        if ! cleanDirectoryContent "${tlsDir}"; then
                            restoreTLSReinstallBackup "${reinstallBackupDir}" "${tlsDir}" "TLS 目录清理失败" || return 1
                            return 1
                        fi
                        if ! installTLSFromAcme; then
                            restoreTLSReinstallBackup "${reinstallBackupDir}" "${tlsDir}" "TLS安装失败" || return 1
                            return 1
                        fi
                        padmRemoveCleanupPath "${reinstallBackupDir}"
                    fi
                fi
            fi
        fi

    elif [[ -d "$HOME/.acme.sh" ]] && [[ ! -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" || ! -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" ]]; then
        switchDNSAPI || return 1
        if [[ -z "${dnsAPIType:-}" ]]; then
            statusCard "TLS 证书申请方式" "不采用 API 申请证书"
            successCard "安装TLS证书，需要依赖80端口"
            allowPort 80 || return 1
        fi

        switchSSLType || return 1
        customSSLEmail || return 1
        selectAcmeInstallSSL

        installTLSFromAcme || return 1
    else
        statusCard "acme.sh" "未安装 acme.sh"
        return 1
    fi
}


# 定时任务更新tls证书
installCronTLS() {
    if [[ -z "${btDomain}" ]]; then
        progressCard "$1" "添加定时维护证书"
        local historyCrontab
        historyCrontab=$(crontab -l 2>/dev/null | sed '/padm/d;/acme.sh/d')
        if ! installUserCrontabContent "${historyCrontab}
30 1 * * * /bin/bash /etc/padm/install.sh RenewTLS >> /etc/padm/crontab_tls.log 2>&1"; then
            errorCard "添加定时维护证书失败，已保留原定时任务"
            exit 1
        fi
        successCard "添加定时维护证书成功"
    fi
}

# 定时任务更新geo文件
installCronUpdateGeo() {
    if [[ "${coreInstallType}" == "1" ]]; then
        if crontab -l | grep -q "UpdateGeo"; then
            errorCard "已添加自动更新定时任务，请不要重复添加"
            exit 0
        fi
        progressCard "1" "添加定时更新 Geo 文件" "1"
        local historyCrontab
        historyCrontab=$(crontab -l 2>/dev/null || true)
        if ! installUserCrontabContent "${historyCrontab}
35 1 * * * /bin/bash /etc/padm/install.sh UpdateGeo >> /etc/padm/crontab_tls.log 2>&1"; then
            errorCard "添加定时更新 Geo 文件失败，已保留原定时任务"
            exit 1
        fi
        successCard "添加定时更新 Geo 文件成功"
    fi
}


# 解析已有 TLS 证书域名
resolveInstalledTLSDomain() {
    local tlsDir
    tlsDir=$(tlsManagedDir) || return 1
    local candidate
    for candidate in "${currentHost:-}" "${tlsDomain:-}" "${domain:-}"; do
        if tlsCertificatePairExists "${tlsDir}" "${candidate}"; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    local certFile keyFile certName
    for certFile in "${tlsDir}"/*.crt; do
        [[ -s "${certFile}" ]] || continue
        certName=$(basename "${certFile}" .crt)
        tlsDomainNameIsSafe "${certName}" || continue
        keyFile="${tlsDir}/${certName}.key"
        [[ -s "${keyFile}" ]] || continue
        printf '%s\n' "${certName}"
        return 0
    done
}

tlsRenewCronState() {
    if crontab -l 2>/dev/null | grep -q "RenewTLS"; then
        printf '已设置'
    else
        printf '未设置'
    fi
}

tlsCertificateStatusJson() {
    readAcmeTLS
    local domain=${currentHost}
    local sslTypeFile
    local tlsDir
    if [[ -z "${domain}" && -n "${tlsDomain}" ]]; then
        domain=${tlsDomain}
    fi
    tlsDir=$(tlsManagedDir) || return 1
    if [[ -n "${domain}" ]] && ! tlsDomainNameIsSafe "${domain}"; then
        domain=
    fi
    if ! tlsCertificatePairExists "${tlsDir}" "${domain}"; then
        domain=$(resolveInstalledTLSDomain)
    fi

    local sslDays=90
    sslTypeFile=$(tlsSslTypeFile) || return 1
    if [[ -f "${sslTypeFile}" ]] && grep -q "buypass" <"${sslTypeFile}"; then
        sslDays=180
    fi

    if tlsCertificatePairExists "${tlsDir}" "${domain}"; then
        if [[ -d "$HOME/.acme.sh/${domain}_ecc" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.key" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.cer" ]] || [[ "${installedDNSAPIStatus:-}" == "true" ]]; then
            local modifyTime currentTime stampDiff days remainingDays sourceType
            if [[ "${installedDNSAPIStatus:-}" == "true" ]]; then
                modifyTime=$(stat --format=%z "$HOME/.acme.sh/*.${dnsTLSDomain}_ecc/*.${dnsTLSDomain}.cer")
                sourceType="acme-dns-api"
            else
                modifyTime=$(stat --format=%z "$HOME/.acme.sh/${domain}_ecc/${domain}.cer")
                sourceType="acme-standalone"
            fi
            modifyTime=$(date +%s -d "${modifyTime}")
            currentTime=$(date +%s)
            ((stampDiff = currentTime - modifyTime))
            ((days = stampDiff / 86400))
            ((remainingDays = sslDays - days))
            jq -n \
                --arg status "installed" \
                --arg source "${sourceType}" \
                --arg domain "${domain}" \
                --arg cron "$(tlsRenewCronState)" \
                --arg issued_at "$(date -d @"${modifyTime}" +"%F %H:%M:%S")" \
                --argjson remaining_days "${remainingDays}" \
                '{status:$status, source:$source, domain:$domain, cron:$cron, issued_at:$issued_at, remaining_days:$remaining_days}'
            return 0
        fi

        jq -n \
            --arg status "installed" \
            --arg source "custom" \
            --arg domain "${domain}" \
            --arg cron "$(tlsRenewCronState)" \
            '{status:$status, source:$source, domain:$domain, cron:$cron}'
        return 0
    fi

    jq -n --arg status "missing" --arg cron "$(tlsRenewCronState)" '{status:$status, cron:$cron}'
}

tlsCertificateStatusCard() {
    statusCard "TLS 证书状态" "$@"
}

tlsCertificateCard() {
    statusCard "TLS 证书" "$@"
}

showTLSCertificateStatus() {
    local statusJson
    statusJson=$(tlsCertificateStatusJson) || {
        errorCard "TLS 证书状态读取失败"
        return 1
    }
    local status source domain cron issuedAt remainingDays
    status=$(jq -r '.status' <<<"${statusJson}")
    source=$(jq -r '.source // "unknown"' <<<"${statusJson}")
    domain=$(jq -r '.domain // "未检测到"' <<<"${statusJson}")
    cron=$(jq -r '.cron // "未设置"' <<<"${statusJson}")
    issuedAt=$(jq -r '.issued_at // ""' <<<"${statusJson}")
    remainingDays=$(jq -r '.remaining_days // ""' <<<"${statusJson}")

    if [[ "${status}" == "missing" ]]; then
        tlsCertificateStatusCard "未检测到本机 TLS 证书" "定时续签：${cron}" "无域名 Reality 不需要这里；域名 Reality 或传统 TLS 请检查证书"
        return 0
    fi
    if [[ "${source}" == "custom" ]]; then
        tlsCertificateStatusCard "域名：${domain}" "来源：自定义证书" "定时续签：${cron}" "说明：自定义证书可读，但不支持 renew 自动续签"
        return 0
    fi
    tlsCertificateStatusCard "域名：${domain}" "来源：${source}" "签发时间：${issuedAt}" "剩余天数：${remainingDays}" "定时续签：${cron}"
}

manageTLSCertificates() {
    while true; do
        echoContent title "\n┌─ 本机 TLS 证书管理 ───────────────────────────────"
        menuLine "这里查看本机 TLS 证书状态，并按需执行续签检查"
        menuItem 1 "查看证书状态" "显示来源、剩余天数和定时续签状态"
        menuItem 2 "立即执行续签检查" "沿用现有 renew 逻辑，按状态决定是否真正续签"
        menuItem 3 "查看续签定时任务" "显示是否已配置 RenewTLS cron"
        menuReturnItem 4 "返回站点与证书" "回到上级菜单"
        menuClose
        autoRead tls_certificate_menu "请选择:" tlsCertificateMenuStatus
        case "${tlsCertificateMenuStatus}" in
        1) showTLSCertificateStatus ;;
        2) renewalTLS 1 ;;
        3) statusCard "TLS 定时续签" "状态：$(tlsRenewCronState)" ;;
        4) return ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}

restoreServicesAfterTLSRenewal() {
    local status=0
    reloadCore || status=1
    runCoreServiceActionAllowFailure handleNginx start || status=1
    return "${status}"
}

failTlsRenewalBeforeInstall() {
    local reason=$1

    errorCard "${reason}，正在尝试恢复服务"
    restoreServicesAfterTLSRenewal || errorCard "${reason}，且服务恢复失败"
    return 1
}

stopServicesForTLSRenewal() {
    if ! runCoreServiceActionAllowFailure handleNginx stop; then
        errorCard "Nginx 服务停止失败，已取消 TLS 续期"
        return 1
    fi

    if [[ "${coreInstallType}" == "1" ]]; then
        if ! runCoreServiceActionAllowFailure handleXray stop; then
            errorCard "Xray 服务停止失败，已取消 TLS 续期"
            runCoreServiceActionAllowFailure handleNginx start >/dev/null 2>&1 || true
            return 1
        fi
    elif [[ "${coreInstallType}" == "2" ]]; then
        if ! runCoreServiceActionAllowFailure handleSingBox stop; then
            errorCard "sing-box 服务停止失败，已取消 TLS 续期"
            runCoreServiceActionAllowFailure handleNginx start >/dev/null 2>&1 || true
            return 1
        fi
    fi
}

# 更新 TLS 证书
renewalTLS() {

    if [[ -n ${1:-} ]]; then
        progressCard "$1" "更新证书" "1"
    fi
    readAcmeTLS
    local domain=${currentHost}
    local sslTypeFile
    local tlsDir
    if [[ -z "${domain}" && -n "${tlsDomain}" ]]; then
        domain=${tlsDomain}
    fi
    tlsDir=$(tlsManagedDir) || return 1
    if [[ -n "${domain}" ]] && ! tlsDomainNameIsSafe "${domain}"; then
        domain=
    fi
    if ! tlsCertificatePairExists "${tlsDir}" "${domain}"; then
        domain=$(resolveInstalledTLSDomain)
    fi

    sslTypeFile=$(tlsSslTypeFile) || return 1
    if [[ -f "${sslTypeFile}" ]]; then
        if [[ -f "${sslTypeFile}" ]] && grep -q "buypass" <"${sslTypeFile}"; then
            sslRenewalDays=180
        fi
    fi
    if [[ -d "$HOME/.acme.sh/${domain}_ecc" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.key" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.cer" ]] || [[ "${installedDNSAPIStatus:-}" == "true" ]]; then
        modifyTime=

        if [[ "${installedDNSAPIStatus:-}" == "true" ]]; then
            modifyTime=$(stat --format=%z "$HOME/.acme.sh/*.${dnsTLSDomain}_ecc/*.${dnsTLSDomain}.cer")
        else
            modifyTime=$(stat --format=%z "$HOME/.acme.sh/${domain}_ecc/${domain}.cer")
        fi

        modifyTime=$(date +%s -d "${modifyTime}")
        currentTime=$(date +%s)
        ((stampDiff = currentTime - modifyTime))
        ((days = stampDiff / 86400))
        ((remainingDays = sslRenewalDays - days))

        tlsStatus=${remainingDays}
        if [[ ${remainingDays} -le 0 ]]; then
            tlsStatus="已过期"
        fi

        tlsCertificateStatusCard \
            "证书检查日期:$(date "+%F %H:%M:%S")" \
            "证书生成日期:$(date -d @"${modifyTime}" +"%F %H:%M:%S")" \
            "证书生成天数:${days}" \
            "证书剩余天数:${tlsStatus}" \
            "证书过期前最后一天自动更新，如更新失败请手动更新"

        if [[ ${remainingDays} -le 1 ]]; then
            local installDomain="${domain}"
            local crtFile="${tlsDir}/${domain}.crt"
            local keyFile="${tlsDir}/${domain}.key"
            tlsCertificateCard "重新生成证书"
            stopServicesForTLSRenewal || return 1

            if [[ "${installedDNSAPIStatus:-}" == "true" ]]; then
                installDomain="*.${dnsTLSDomain}"
            fi
            local backupDir backupCrt backupKey restoreStatus=0
            padmCreateTmpRootPath backupDir padm-tls-renew.XXXXXX -d || {
                failTlsRenewalBeforeInstall "TLS 旧证书备份目录创建失败"
                return 1
            }
            backupCrt="${backupDir}/$(basename -- "${crtFile}")"
            backupKey="${backupDir}/$(basename -- "${keyFile}")"
            cp -p "${crtFile}" "${backupCrt}" || {
                padmRemoveCleanupPath "${backupDir}"
                failTlsRenewalBeforeInstall "TLS 旧证书备份失败"
                return 1
            }
            cp -p "${keyFile}" "${backupKey}" || {
                padmRemoveCleanupPath "${backupDir}"
                failTlsRenewalBeforeInstall "TLS 旧证书备份失败"
                return 1
            }
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${installDomain}" --fullchainpath "${crtFile}" --keypath "${keyFile}" --ecc || {
                local installStatus=$?
                errorCard "TLS 证书安装失败，正在尝试恢复服务"
                restoreManagedFileFromBackup "${backupCrt}" "${crtFile}" 644 || restoreStatus=1
                restoreManagedFileFromBackup "${backupKey}" "${keyFile}" 600 || restoreStatus=1
                if [[ "${restoreStatus}" -eq 0 ]]; then
                    padmRemoveCleanupPath "${backupDir}"
                else
                    padmForgetCleanupPath "${backupDir}"
                    errorCard "TLS 证书恢复失败，请手动检查备份目录: ${backupDir}"
                fi
                restoreServicesAfterTLSRenewal || errorCard "TLS 证书安装失败，且服务恢复失败"
                return "${installStatus}"
            }
            padmRemoveCleanupPath "${backupDir}"
            if ! restoreServicesAfterTLSRenewal; then
                errorCard "TLS 证书已安装，但服务恢复失败"
                return 1
            fi
        else
            successCard "证书有效"
        fi
    elif tlsCertificatePairExists "${tlsDir}" "${domain}"; then
        tlsCertificateCard "检测到使用自定义证书，无法执行 renew 操作"
    else
        errorCard "未安装本机 TLS 证书；无域名 Reality 不需要这里，域名 Reality 或传统 TLS 请检查 acme 与 /etc/padm/tls"
    fi
}
