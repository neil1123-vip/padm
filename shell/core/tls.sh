#!/usr/bin/env bash

# 自定义email
customSSLEmail() {
    if echo "$1" | grep -q "validate email"; then
        read -r -p "是否重新输入邮箱地址[y/n]:" sslEmailStatus
        if [[ "${sslEmailStatus}" == "y" ]]; then
            sed '/ACCOUNT_EMAIL/d' /root/.acme.sh/account.conf >/root/.acme.sh/account.conf_tmp && mv /root/.acme.sh/account.conf_tmp /root/.acme.sh/account.conf
        else
            exit 0
        fi
    fi

    if [[ -d "/root/.acme.sh" && -f "/root/.acme.sh/account.conf" ]]; then
        if ! grep -q "ACCOUNT_EMAIL" <"/root/.acme.sh/account.conf" && ! echo "${sslType}" | grep -q "letsencrypt"; then
            read -r -p "请输入邮箱地址:" sslEmail
            if echo "${sslEmail}" | grep -q "@"; then
                echo "ACCOUNT_EMAIL='${sslEmail}'" >>/root/.acme.sh/account.conf
                echoContent green " ---> 添加完毕"
            else
                echoContent yellow "请重新输入正确的邮箱格式[例: username@example.com]"
                customSSLEmail
            fi
        fi
    fi

}

# DNS API申请证书
switchDNSAPI() {
    autoRead dns_api "是否使用DNS API申请证书[支持NAT]？[y/n]:" dnsAPIStatus
    if [[ "${dnsAPIStatus}" == "y" ]]; then
        echoContent red "\n=============================================================="
        echoContent yellow "1.cloudflare[默认]"
        echoContent yellow "2.aliyun"
        echoContent red "=============================================================="
        read -r -p "请选择[回车]使用默认:" selectDNSAPIType
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
        initDNSAPIConfig "${dnsAPIType}"
    fi
}

# 初始化dns配置
initDNSAPIConfig() {
    if [[ "$1" == "cloudflare" ]]; then
        echoContent yellow "\n 请在 Cloudflare 控制台创建具备 DNS 编辑权限的 API Token\n"
        read -r -p "请输入API Token:" cfAPIToken
        if [[ -z "${cfAPIToken}" ]]; then
            echoContent red " ---> 输入为空，请重新输入"
            initDNSAPIConfig "$1"
        else
            echo
            if ! echo "${dnsTLSDomain}" | grep -q "\." || [[ -z $(echo "${dnsTLSDomain}" | awk -F "[.]" '{print $1}') ]]; then
                echoContent green " ---> 不支持此域名申请通配符证书，建议使用此格式[xx.xx.xx]"
                exit 0
            fi
            read -r -p "是否使用*.${dnsTLSDomain}进行API申请通配符证书？[y/n]:" dnsAPIStatus
        fi
    elif [[ "$1" == "aliyun" ]]; then
        read -r -p "请输入Ali Key:" aliKey
        read -r -p "请输入Ali Secret:" aliSecret
        if [[ -z "${aliKey}" || -z "${aliSecret}" ]]; then
            echoContent red " ---> 输入为空，请重新输入"
            initDNSAPIConfig "$1"
        else
            echo
            if ! echo "${dnsTLSDomain}" | grep -q "\." || [[ -z $(echo "${dnsTLSDomain}" | awk -F "[.]" '{print $1}') ]]; then
                echoContent green " ---> 不支持此域名申请通配符证书，建议使用此格式[xx.xx.xx]"
                exit 0
            fi
            read -r -p "是否使用*.${dnsTLSDomain}进行API申请通配符证书？[y/n]:" dnsAPIStatus
        fi
    fi
}

# 选择ssl安装类型
switchSSLType() {
    if [[ -z "${sslType}" ]]; then
        echoContent red "\n=============================================================="
        echoContent yellow "1.letsencrypt[默认]"
        echoContent yellow "2.zerossl"
        echoContent yellow "3.buypass[不支持DNS申请]"
        echoContent red "=============================================================="
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
        if [[ -n "${dnsAPIType}" && "${sslType}" == "buypass" ]]; then
            echoContent red " ---> buypass不支持API申请证书"
            exit 0
        fi
        echo "${sslType}" >/etc/padm/tls/ssl_type
    fi
}


# 选择acme安装证书方式
selectAcmeInstallSSL() {
    #    local sslIPv6=
    #    local currentIPType=
    if [[ "${ipType}" == "6" ]]; then
        sslIPv6="--listen-v6"
    fi
    #    currentIPType=$(curl -s "-${ipType}" http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2)

    #    if [[ -z "${currentIPType}" ]]; then
    #                currentIPType=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2)
    #        if [[ -n "${currentIPType}" ]]; then
    #            sslIPv6="--listen-v6"
    #        fi
    #    fi

    acmeInstallSSL

    readAcmeTLS
}


# 安装SSL证书
acmeInstallSSL() {
    local dnsAPIDomain="${tlsDomain}"
    if [[ "${dnsAPIStatus}" == "y" ]]; then
        dnsAPIDomain="*.${dnsTLSDomain}"
    fi

    if [[ "${dnsAPIType}" == "cloudflare" ]]; then
        echoContent green " ---> DNS API 生成证书中"
        sudo CF_Token="${cfAPIToken}" "$HOME/.acme.sh/acme.sh" --issue -d "${dnsAPIDomain}" -d "${dnsTLSDomain}" --dns dns_cf -k ec-256 --server "${sslType}" ${sslIPv6} 2>&1 | tee -a /etc/padm/tls/acme.log >/dev/null
    elif [[ "${dnsAPIType}" == "aliyun" ]]; then
        echoContent green " --->  DNS API 生成证书中"
        sudo Ali_Key="${aliKey}" Ali_Secret="${aliSecret}" "$HOME/.acme.sh/acme.sh" --issue -d "${dnsAPIDomain}" -d "${dnsTLSDomain}" --dns dns_ali -k ec-256 --server "${sslType}" ${sslIPv6} 2>&1 | tee -a /etc/padm/tls/acme.log >/dev/null
    else
        echoContent green " ---> 生成证书中"
        sudo "$HOME/.acme.sh/acme.sh" --issue -d "${tlsDomain}" --standalone -k ec-256 --server "${sslType}" ${sslIPv6} 2>&1 | tee -a /etc/padm/tls/acme.log >/dev/null
    fi
}

# 安装TLS
installTLS() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 申请TLS证书\n"
    readAcmeTLS
    local tlsDomain=${domain}

    # 安装tls
    if [[ -f "/etc/padm/tls/${tlsDomain}.crt" && -f "/etc/padm/tls/${tlsDomain}.key" && -n $(cat "/etc/padm/tls/${tlsDomain}.crt") ]] || [[ -d "$HOME/.acme.sh/${tlsDomain}_ecc" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]] || [[ "${installedDNSAPIStatus}" == "true" ]]; then
        echoContent green " ---> 检测到证书"
        renewalTLS

        if [[ -z $(find /etc/padm/tls/ -name "${tlsDomain}.crt") ]] || [[ -z $(find /etc/padm/tls/ -name "${tlsDomain}.key") ]] || [[ -z $(cat "/etc/padm/tls/${tlsDomain}.crt") ]]; then
            if [[ "${installedDNSAPIStatus}" == "true" ]]; then
                sudo "$HOME/.acme.sh/acme.sh" --installcert -d "*.${dnsTLSDomain}" --fullchainpath "/etc/padm/tls/${tlsDomain}.crt" --keypath "/etc/padm/tls/${tlsDomain}.key" --ecc >/dev/null
            else
                sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${tlsDomain}" --fullchainpath "/etc/padm/tls/${tlsDomain}.crt" --keypath "/etc/padm/tls/${tlsDomain}.key" --ecc >/dev/null
            fi

        else
            if [[ -d "$HOME/.acme.sh/${tlsDomain}_ecc" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" && -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]] || [[ "${installedDNSAPIStatus}" == "true" ]]; then
                if [[ -z "${lastInstallationConfig}" ]]; then
                    echoContent yellow " ---> 如未过期或者自定义证书请选择[n]\n"
                    read -r -p "是否重新安装？[y/n]:" reInstallStatus
                    if [[ "${reInstallStatus}" == "y" ]]; then
                        cleanDirectoryContent /etc/padm/tls
                        installTLS "$1"
                    fi
                fi
            fi
        fi

    elif [[ -d "$HOME/.acme.sh" ]] && [[ ! -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" || ! -f "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" ]]; then
        switchDNSAPI
        if [[ -z "${dnsAPIType}" ]]; then
            echoContent yellow "\n ---> 不采用API申请证书"
            echoContent green " ---> 安装TLS证书，需要依赖80端口"
            allowPort 80
        fi

        switchSSLType
        customSSLEmail
        selectAcmeInstallSSL

        if [[ "${installedDNSAPIStatus}" == "true" ]]; then
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "*.${dnsTLSDomain}" --fullchainpath "/etc/padm/tls/${tlsDomain}.crt" --keypath "/etc/padm/tls/${tlsDomain}.key" --ecc >/dev/null
        else
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${tlsDomain}" --fullchainpath "/etc/padm/tls/${tlsDomain}.crt" --keypath "/etc/padm/tls/${tlsDomain}.key" --ecc >/dev/null
        fi

        if [[ ! -f "/etc/padm/tls/${tlsDomain}.crt" || ! -f "/etc/padm/tls/${tlsDomain}.key" ]] || [[ -z $(cat "/etc/padm/tls/${tlsDomain}.key") || -z $(cat "/etc/padm/tls/${tlsDomain}.crt") ]]; then
            tail -n 10 /etc/padm/tls/acme.log
            if [[ ${installTLSCount} == "1" ]]; then
                echoContent red " ---> TLS安装失败，请检查acme日志"
                exit 0
            fi

            installTLSCount=1
            echo

            if tail -n 10 /etc/padm/tls/acme.log | grep -q "Could not validate email address as valid"; then
                echoContent red " ---> 邮箱无法通过SSL厂商验证，请重新输入"
                echo
                customSSLEmail "validate email"
                installTLS "$1"
            else
                installTLS "$1"
            fi
        fi

        echoContent green " ---> TLS生成成功"
    else
        echoContent yellow " ---> 未安装acme.sh"
        exit 0
    fi
}


# 定时任务更新tls证书
installCronTLS() {
    if [[ -z "${btDomain}" ]]; then
        echoContent skyBlue "\n进度 $1/${totalProgress} : 添加定时维护证书"
        crontab -l >/etc/padm/backup_crontab.cron
        local historyCrontab
        historyCrontab=$(sed '/padm/d;/acme.sh/d' /etc/padm/backup_crontab.cron)
        echo "${historyCrontab}" >/etc/padm/backup_crontab.cron
        echo "30 1 * * * /bin/bash /etc/padm/install.sh RenewTLS >> /etc/padm/crontab_tls.log 2>&1" >>/etc/padm/backup_crontab.cron
        crontab /etc/padm/backup_crontab.cron
        echoContent green "\n ---> 添加定时维护证书成功"
    fi
}

# 定时任务更新geo文件
installCronUpdateGeo() {
    if [[ "${coreInstallType}" == "1" ]]; then
        if crontab -l | grep -q "UpdateGeo"; then
            echoContent red "\n ---> 已添加自动更新定时任务，请不要重复添加"
            exit 0
        fi
        echoContent skyBlue "\n进度 1/1 : 添加定时更新geo文件"
        crontab -l >/etc/padm/backup_crontab.cron
        echo "35 1 * * * /bin/bash /etc/padm/install.sh UpdateGeo >> /etc/padm/crontab_tls.log 2>&1" >>/etc/padm/backup_crontab.cron
        crontab /etc/padm/backup_crontab.cron
        echoContent green "\n ---> 添加定时更新geo文件成功"
    fi
}


# 更新证书
renewalTLS() {

    if [[ -n $1 ]]; then
        echoContent skyBlue "\n进度  $1/1 : 更新证书"
    fi
    readAcmeTLS
    local domain=${currentHost}
    if [[ -z "${currentHost}" && -n "${tlsDomain}" ]]; then
        domain=${tlsDomain}
    fi

    if [[ -f "/etc/padm/tls/ssl_type" ]]; then
        if grep -q "buypass" <"/etc/padm/tls/ssl_type"; then
            sslRenewalDays=180
        fi
    fi
    if [[ -d "$HOME/.acme.sh/${domain}_ecc" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.key" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.cer" ]] || [[ "${installedDNSAPIStatus}" == "true" ]]; then
        modifyTime=

        if [[ "${installedDNSAPIStatus}" == "true" ]]; then
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

        echoContent skyBlue " ---> 证书检查日期:$(date "+%F %H:%M:%S")"
        echoContent skyBlue " ---> 证书生成日期:$(date -d @"${modifyTime}" +"%F %H:%M:%S")"
        echoContent skyBlue " ---> 证书生成天数:${days}"
        echoContent skyBlue " ---> 证书剩余天数:"${tlsStatus}
        echoContent skyBlue " ---> 证书过期前最后一天自动更新，如更新失败请手动更新"

        if [[ ${remainingDays} -le 1 ]]; then
            echoContent yellow " ---> 重新生成证书"
            handleNginx stop

            if [[ "${coreInstallType}" == "1" ]]; then
                handleXray stop
            elif [[ "${coreInstallType}" == "2" ]]; then
                handleSingBox stop
            fi

            sudo "$HOME/.acme.sh/acme.sh" --cron --home "$HOME/.acme.sh"
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${domain}" --fullchainpath /etc/padm/tls/"${domain}.crt" --keypath /etc/padm/tls/"${domain}.key" --ecc
            reloadCore
            handleNginx start
        else
            echoContent green " ---> 证书有效"
        fi
    elif [[ -f "/etc/padm/tls/${tlsDomain}.crt" && -f "/etc/padm/tls/${tlsDomain}.key" && -n $(cat "/etc/padm/tls/${tlsDomain}.crt") ]]; then
        echoContent yellow " ---> 检测到使用自定义证书，无法执行renew操作。"
    else
        echoContent red " ---> 未安装"
    fi
}

