#!/usr/bin/env bash

# 自定义 Email
customSSLEmail() {
    if echo "${1:-}" | grep -q "validate email"; then
        autoRead tls_email_retry "是否重新输入邮箱地址[y/n]:" sslEmailStatus
        if [[ "${sslEmailStatus}" == "y" ]]; then
            sed '/ACCOUNT_EMAIL/d' /root/.acme.sh/account.conf >/root/.acme.sh/account.conf_tmp && mv /root/.acme.sh/account.conf_tmp /root/.acme.sh/account.conf || return 1
        else
            return 1
        fi
    fi

    if [[ -d "/root/.acme.sh" && -f "/root/.acme.sh/account.conf" ]]; then
        if ! grep -q "ACCOUNT_EMAIL" <"/root/.acme.sh/account.conf" && ! echo "${sslType}" | grep -q "letsencrypt"; then
            autoRead tls_account_email "请输入邮箱地址:" sslEmail
            if echo "${sslEmail}" | grep -q "@"; then
                echo "ACCOUNT_EMAIL='${sslEmail}'" >>/root/.acme.sh/account.conf || return 1
                successCard "添加完毕"
            else
                echoContent yellow "请重新输入正确的邮箱格式[例: username@example.com]"
                customSSLEmail || return 1
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
        1)
            dnsAPIType="cloudflare"
            ;;
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
        echoContent title "\n┌─ 证书 CA ──────────────────────────────────────────"
        menuRecommendedItem 1 "letsencrypt" "默认 CA"
        menuItem 2 "zerossl" "ZeroSSL CA"
        menuItem 3 "buypass" "不支持 DNS 申请"
        menuClose
        autoRead tls_ca "请选择[回车]使用默认:" selectSSLType
        case ${selectSSLType} in
        1)
            sslType="letsencrypt"
            ;;
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
        echo "${sslType}" >/etc/padm/tls/ssl_type || return 1
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
    if [[ "${dnsAPIStatus:-}" == "y" ]]; then
        dnsAPIDomain="*.${dnsTLSDomain}"
    fi

    if [[ "${dnsAPIType:-}" == "cloudflare" ]]; then
        successCard "DNS API 生成证书中"
        if [[ -n "${cfZoneID:-}" ]]; then
            CF_Token="${cfAPIToken}" CF_Zone_ID="${cfZoneID}" "$HOME/.acme.sh/acme.sh" --issue -d "${dnsAPIDomain}" -d "${dnsTLSDomain}" --dns dns_cf -k ec-256 --server "${sslType}" ${sslIPv6:-} 2>&1 | tee -a /etc/padm/tls/acme.log >/dev/null
        else
            CF_Token="${cfAPIToken}" "$HOME/.acme.sh/acme.sh" --issue -d "${dnsAPIDomain}" -d "${dnsTLSDomain}" --dns dns_cf -k ec-256 --server "${sslType}" ${sslIPv6:-} 2>&1 | tee -a /etc/padm/tls/acme.log >/dev/null
        fi
    elif [[ "${dnsAPIType:-}" == "aliyun" ]]; then
        successCard "DNS API 生成证书中"
        Ali_Key="${aliKey}" Ali_Secret="${aliSecret}" "$HOME/.acme.sh/acme.sh" --issue -d "${dnsAPIDomain}" -d "${dnsTLSDomain}" --dns dns_ali -k ec-256 --server "${sslType}" ${sslIPv6:-} 2>&1 | tee -a /etc/padm/tls/acme.log >/dev/null
    else
        successCard "生成证书中"
        sudo "$HOME/.acme.sh/acme.sh" --issue -d "${tlsDomain}" --standalone -k ec-256 --server "${sslType}" ${sslIPv6:-} 2>&1 | tee -a /etc/padm/tls/acme.log >/dev/null
    fi
}

# 安装 TLS 证书
installTLS() {
    progressCard "$1" "申请 TLS 证书"
    readAcmeTLS
    local tlsDomain=${domain}

    if [[ -f "/etc/padm/tls/${tlsDomain}.crt" && -f "/etc/padm/tls/${tlsDomain}.key" && -n $(cat "/etc/padm/tls/${tlsDomain}.crt") ]] || [[ -d "$HOME/.acme.sh/${tlsDomain}_ecc" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]] || [[ "${installedDNSAPIStatus:-}" == "true" ]]; then
        successCard "检测到证书"
        renewalTLS

        if [[ -z $(find /etc/padm/tls/ -name "${tlsDomain}.crt") ]] || [[ -z $(find /etc/padm/tls/ -name "${tlsDomain}.key") ]] || [[ -z $(cat "/etc/padm/tls/${tlsDomain}.crt") ]]; then
            if [[ "${installedDNSAPIStatus:-}" == "true" ]]; then
                sudo "$HOME/.acme.sh/acme.sh" --installcert -d "*.${dnsTLSDomain}" --fullchainpath "/etc/padm/tls/${tlsDomain}.crt" --keypath "/etc/padm/tls/${tlsDomain}.key" --ecc >/dev/null || return 1
            else
                sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${tlsDomain}" --fullchainpath "/etc/padm/tls/${tlsDomain}.crt" --keypath "/etc/padm/tls/${tlsDomain}.key" --ecc >/dev/null || return 1
            fi

        else
            if [[ -d "$HOME/.acme.sh/${tlsDomain}_ecc" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]] || [[ "${installedDNSAPIStatus:-}" == "true" ]]; then
                if [[ -z "${lastInstallationConfig}" ]]; then
                    statusCard "TLS 证书" "如未过期或者自定义证书请选择 [n]"
                    autoRead tls_reinstall "是否重新安装？[y/n]:" reInstallStatus
                    if [[ "${reInstallStatus}" == "y" ]]; then
                        cleanDirectoryContent /etc/padm/tls
                        installTLS "$1" || return 1
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

        if [[ "${installedDNSAPIStatus:-}" == "true" ]]; then
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "*.${dnsTLSDomain}" --fullchainpath "/etc/padm/tls/${tlsDomain}.crt" --keypath "/etc/padm/tls/${tlsDomain}.key" --ecc >/dev/null || true
        else
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${tlsDomain}" --fullchainpath "/etc/padm/tls/${tlsDomain}.crt" --keypath "/etc/padm/tls/${tlsDomain}.key" --ecc >/dev/null || true
        fi

        if [[ ! -f "/etc/padm/tls/${tlsDomain}.crt" || ! -f "/etc/padm/tls/${tlsDomain}.key" ]] || [[ -z $(cat "/etc/padm/tls/${tlsDomain}.key") || -z $(cat "/etc/padm/tls/${tlsDomain}.crt") ]]; then
            tail -n 10 /etc/padm/tls/acme.log 2>/dev/null || true
            if [[ ${installTLSCount:-} == "1" ]]; then
                errorCard "TLS安装失败，请检查acme日志"
                return 1
            fi

            installTLSCount=1
            echo

            if tail -n 10 /etc/padm/tls/acme.log | grep -q "Could not validate email address as valid"; then
                errorCard "邮箱无法通过SSL厂商验证，请重新输入"
                echo
                customSSLEmail "validate email" || return 1
                installTLS "$1" || return 1
            else
                installTLS "$1" || return 1
            fi
        fi

        successCard "TLS生成成功"
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
    local tlsDir="${PADM_TLS_DIR:-/etc/padm/tls}"
    local candidate
    for candidate in "${currentHost:-}" "${tlsDomain:-}" "${domain:-}"; do
        if [[ -n "${candidate}" && -s "${tlsDir}/${candidate}.crt" && -s "${tlsDir}/${candidate}.key" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    local certFile keyFile certName
    for certFile in "${tlsDir}"/*.crt; do
        [[ -s "${certFile}" ]] || continue
        certName=$(basename "${certFile}" .crt)
        keyFile="${tlsDir}/${certName}.key"
        [[ -s "${keyFile}" ]] || continue
        printf '%s\n' "${certName}"
        return 0
    done
}

restoreServicesAfterTLSRenewal() {
    local status=0
    reloadCore || status=1
    runCoreServiceActionAllowFailure handleNginx start || status=1
    return "${status}"
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
    if [[ -z "${domain}" && -n "${tlsDomain}" ]]; then
        domain=${tlsDomain}
    fi
    local tlsDir="${PADM_TLS_DIR:-/etc/padm/tls}"
    if [[ -z "${domain}" || ! -s "${tlsDir}/${domain}.crt" || ! -s "${tlsDir}/${domain}.key" ]]; then
        domain=$(resolveInstalledTLSDomain)
    fi

    if [[ -f "/etc/padm/tls/ssl_type" ]]; then
        if grep -q "buypass" <"/etc/padm/tls/ssl_type"; then
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

        statusCard "TLS 证书状态" \
            "证书检查日期:$(date "+%F %H:%M:%S")" \
            "证书生成日期:$(date -d @"${modifyTime}" +"%F %H:%M:%S")" \
            "证书生成天数:${days}" \
            "证书剩余天数:${tlsStatus}" \
            "证书过期前最后一天自动更新，如更新失败请手动更新"

        if [[ ${remainingDays} -le 1 ]]; then
            local installDomain="${domain}"
            statusCard "TLS 证书" "重新生成证书"
            stopServicesForTLSRenewal || return 1

            if [[ "${installedDNSAPIStatus:-}" == "true" ]]; then
                installDomain="*.${dnsTLSDomain}"
            fi
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${installDomain}" --fullchainpath /etc/padm/tls/"${domain}.crt" --keypath /etc/padm/tls/"${domain}.key" --ecc || {
                local installStatus=$?
                errorCard "TLS 证书安装失败，正在尝试恢复服务"
                restoreServicesAfterTLSRenewal || errorCard "TLS 证书安装失败，且服务恢复失败"
                return "${installStatus}"
            }
            if ! restoreServicesAfterTLSRenewal; then
                errorCard "TLS 证书已安装，但服务恢复失败"
                return 1
            fi
        else
            successCard "证书有效"
        fi
    elif [[ -n "${domain}" && -s "${tlsDir}/${domain}.crt" && -s "${tlsDir}/${domain}.key" ]]; then
        statusCard "TLS 证书" "检测到使用自定义证书，无法执行 renew 操作"
    else
        errorCard "未安装本机 TLS 证书；无域名 Reality 不需要这里，域名 Reality 或传统 TLS 请检查 acme 与 /etc/padm/tls"
    fi
}
