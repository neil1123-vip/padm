#!/usr/bin/env bash

runTlsFailureReturnRegression() (
    local root="${TMP_DIR}/tls-failure-return"
    local oldHome="${HOME}"
    local emailRcFile="${root}/email.rc"
    local dnsRcFile="${root}/dns-api.rc"
    local caRcFile="${root}/ca.rc"
    local installRcFile="${root}/install.rc"
    local xrayRcFile="${root}/xray.rc"
    local chmodLog="${root}/chmod.log"
    local reachedFile="${root}/reached"
    local shellRc
    local autoReadDefinition
    autoReadDefinition=$(declare -f autoRead)

    mkdir -p "${root}/home"
    HOME="${root}/home"
    errorCard() { return 0; }
    autoRead() {
        case "$1" in
        tls_email_retry) printf -v "$3" 'n' ;;
        cloudflare_api_token) printf -v "$3" 'token' ;;
        cloudflare_zone_id) printf -v "$3" '' ;;
        dns_api_wildcard) printf -v "$3" 'y' ;;
        tls_ca) printf -v "$3" '3' ;;
        *) printf -v "$3" '' ;;
        esac
    }

    captureFailureReturn() {
        local rcFile=$1
        shift
        rm -f "${rcFile}"
        set +e
        (
            set +e
            "$@" >/dev/null 2>&1
            printf '%s\n' "$?" >"${rcFile}"
        )
        shellRc=$?
        set -e
        [[ "${shellRc}" == "0" ]]
        [[ "$(<"${rcFile}")" == "1" ]]
    }

    captureFailureReturn "${emailRcFile}" customSSLEmail "validate email"

    (
        # 邮箱确认或邮箱字段的 EOF、截断不能提交账号配置。
        eval "${autoReadDefinition}"
        local HOME="${root}/email-home" AUTO_INSTALL= sslType=zerossl
        local sslEmail=previous@example.com sslEmailStatus=y input accountFile before inputFd remaining
        mkdir -p "${HOME}/.acme.sh"
        accountFile=$(acmeAccountFile)
        printf "SAVED=unchanged\nACCOUNT_EMAIL='old@example.com'\n" >"${accountFile}"
        before=$(<"${accountFile}")
        for input in '' y $'y\n' $'y\nnew@example.com'; do
            sslEmail=previous@example.com
            sslEmailStatus=y
            regressionExpectStatus 1 customSSLEmail "validate email" < <(printf '%s' "${input}")
            [[ "$(<"${accountFile}")" == "${before}" ]]
        done
        printf 'SAVED=unchanged\n' >"${accountFile}"
        before=$(<"${accountFile}")
        for input in '' new@example.com; do
            sslEmail=previous@example.com
            regressionExpectStatus 1 customSSLEmail < <(printf '%s' "${input}")
            [[ "$(<"${accountFile}")" == "${before}" ]]
        done
        exec {inputFd}< <(printf 'y\nnew@example.com\nnext-parent-action\n')
        customSSLEmail "validate email" <&"${inputFd}"
        grep -Fxq "ACCOUNT_EMAIL='new@example.com'" "${accountFile}"
        read -r -u "${inputFd}" remaining
        [[ "${remaining}" == next-parent-action ]]
        exec {inputFd}<&-
    )

    dnsTLSDomain=example
    captureFailureReturn "${dnsRcFile}" initDNSAPIConfig cloudflare

    dnsAPIType=cloudflare
    sslType=
    (
        local AUTO_INSTALL=true AUTO_TLS_CA=buypass
        captureFailureReturn "${caRcFile}" switchSSLType
    )

    (
        eval "${autoReadDefinition}"
        local dnsTLSDomain=example.com input inputFd remaining affirmative
        local AUTO_INSTALL= AUTO_DNS_API AUTO_DNS_API_TYPE AUTO_DNS_API_WILDCARD=n
        local AUTO_CLOUDFLARE_API_TOKEN= PADM_CLOUDFLARE_API_TOKEN=
        local AUTO_ALIYUN_API_KEY= PADM_ALIYUN_API_KEY=
        local AUTO_ALIYUN_API_SECRET= PADM_ALIYUN_API_SECRET=
        local AUTO_TLS_CA
        export PADM_TLS_DIR="${root}/input-tls"

        # 每个读取点的 EOF 都必须失败，不能缓存半份配置或跳过下轮采集。
        for input in '' $'y\n' $'y\n\n' $'y\n\ntoken\n' $'y\n\ntoken\nzone\n'; do
            unset dnsAPIStatus dnsAPIType cfAPIToken cfZoneID
            regressionExpectStatus 1 switchDNSAPI < <(printf '%s' "${input}")
            [[ -z "${dnsAPIStatus+x}" && -z "${dnsAPIType+x}" &&
                -z "${cfAPIToken+x}" && -z "${cfZoneID+x}" ]]
        done

        # 空输入原地重填一次，不重复读取 Zone 或吞掉下一层菜单输入。
        exec {inputFd}< <(printf 'y\n\n\ntoken\n\nn\nnext-action\n')
        switchDNSAPI <&"${inputFd}"
        [[ "${dnsAPIType}" == cloudflare && "${dnsAPIStatus}" == n &&
            "${cfAPIToken}" == token && -z "${cfZoneID}" ]]
        read -r -u "${inputFd}" remaining
        [[ "${remaining}" == next-action ]]
        exec {inputFd}<&-
        for affirmative in Y yes; do
            unset dnsAPIStatus dnsAPIType cfAPIToken cfZoneID
            exec {inputFd}< <(printf '%s\n1\ntoken\n\nyes\nnext-action\n' "${affirmative}")
            switchDNSAPI <&"${inputFd}"
            [[ "${dnsAPIType}" == cloudflare && "${dnsAPIStatus}" == y && "${cfAPIToken}" == token ]]
            read -r -u "${inputFd}" remaining
            [[ "${remaining}" == next-action ]]
            exec {inputFd}<&-
        done

        # 单域名 DNS 申请不受通配符父域限制；选择通配符才校验父域。
        dnsTLSDomain=com
        unset dnsAPIStatus dnsAPIType cfAPIToken cfZoneID
        switchDNSAPI < <(printf 'y\n\ntoken\n\nn\n')
        [[ "${dnsAPIType}" == cloudflare && "${dnsAPIStatus}" == n && "${cfAPIToken}" == token ]]
        unset dnsAPIStatus dnsAPIType cfAPIToken cfZoneID
        regressionExpectStatus 1 switchDNSAPI < <(printf 'y\n\ntoken\n\ny\n')
        [[ -z "${dnsAPIStatus+x}" && -z "${dnsAPIType+x}" &&
            -z "${cfAPIToken+x}" && -z "${cfZoneID+x}" ]]
        dnsTLSDomain=example.com

        (
            local keyReads=0
            autoRead() {
                [[ "$1" != aliyun_api_key ]] || keyReads=$((keyReads + 1))
                read -r "$3"
            }
            exec {inputFd}< <(printf 'y\n2\nkey\n\nsecret\nn\nnext-parent-action\n')
            switchDNSAPI <&"${inputFd}"
            [[ "${keyReads}" == 1 && "${aliKey}" == key && "${aliSecret}" == secret ]]
            read -r -u "${inputFd}" remaining
            [[ "${remaining}" == next-parent-action ]]
            exec {inputFd}<&-
        )

        for AUTO_DNS_API_TYPE in cloudflare aliyun; do
            unset dnsAPIStatus dnsAPIType cfAPIToken cfZoneID aliKey aliSecret
            AUTO_INSTALL=true
            AUTO_DNS_API=y
            regressionExpectStatus 1 switchDNSAPI </dev/null
            [[ -z "${dnsAPIStatus+x}" && -z "${dnsAPIType+x}" &&
                -z "${cfAPIToken+x}" && -z "${cfZoneID+x}" &&
                -z "${aliKey+x}" && -z "${aliSecret+x}" ]]
        done
        AUTO_ALIYUN_API_KEY=key
        regressionExpectStatus 1 switchDNSAPI </dev/null
        AUTO_ALIYUN_API_SECRET=secret
        switchDNSAPI </dev/null
        [[ "${dnsAPIType}" == aliyun && "${dnsAPIStatus}" == n &&
            "${aliKey}" == key && "${aliSecret}" == secret ]]

        # 冲突、EOF、落盘失败均不能缓存 CA；下一次有效选择正常生效。
        unset sslType
        AUTO_TLS_CA=buypass
        regressionExpectStatus 1 switchSSLType </dev/null
        regressionExpectStatus 1 switchSSLType </dev/null
        [[ -z "${sslType+x}" && ! -e "${PADM_TLS_DIR}/ssl_type" ]]
        sslType=buypass
        regressionExpectStatus 1 switchSSLType </dev/null
        [[ "${sslType}" == buypass && ! -e "${PADM_TLS_DIR}/ssl_type" ]]
        unset sslType
        AUTO_INSTALL=
        regressionExpectStatus 1 switchSSLType </dev/null
        [[ -z "${sslType+x}" && ! -e "${PADM_TLS_DIR}/ssl_type" ]]
        (
            AUTO_INSTALL=true
            AUTO_TLS_CA=letsencrypt
            commitGeneratedFile() { return 1; }
            regressionExpectStatus 1 switchSSLType </dev/null
            [[ -z "${sslType+x}" && ! -e "${PADM_TLS_DIR}/ssl_type" ]]
        )
        switchSSLType <<<"1"
        [[ "${sslType}" == letsencrypt && "$(<"${PADM_TLS_DIR}/ssl_type")" == letsencrypt ]]

        # 缓存 CA 与 DNS 冲突时允许重新选择；自动参数可以替换已有合法 CA。
        sslType=buypass
        AUTO_TLS_CA=
        regressionExpectStatus 1 switchSSLType </dev/null
        [[ "${sslType}" == buypass && "$(<"${PADM_TLS_DIR}/ssl_type")" == letsencrypt ]]
        switchSSLType <<<"1"
        [[ "${sslType}" == letsencrypt && "$(<"${PADM_TLS_DIR}/ssl_type")" == letsencrypt ]]
        AUTO_INSTALL=true
        AUTO_TLS_CA=zerossl
        switchSSLType </dev/null
        [[ "${sslType}" == zerossl && "$(<"${PADM_TLS_DIR}/ssl_type")" == zerossl ]]
        (
            AUTO_TLS_CA=letsencrypt
            commitGeneratedFile() { return 1; }
            regressionExpectStatus 1 switchSSLType </dev/null
            [[ "${sslType}" == zerossl && "$(<"${PADM_TLS_DIR}/ssl_type")" == zerossl ]]
        )
        AUTO_TLS_CA=buypass
        regressionExpectStatus 1 switchSSLType </dev/null
        [[ "${sslType}" == zerossl && "$(<"${PADM_TLS_DIR}/ssl_type")" == zerossl ]]
        sslType=buypass
        AUTO_TLS_CA=letsencrypt
        switchSSLType </dev/null
        [[ "${sslType}" == letsencrypt && "$(<"${PADM_TLS_DIR}/ssl_type")" == letsencrypt ]]

        (
            # CA 非法选择和 DNS 冲突原地纠错；取消及自动坏参数不能替换旧 CA。
            local AUTO_INSTALL= AUTO_TLS_CA= sslType= invalid inputFd remaining
            for invalid in 9 abc; do
                sslType=
                exec {inputFd}< <(printf '%s\n2\nnext-parent-action\n' "${invalid}")
                switchSSLType <&"${inputFd}"
                read -r -u "${inputFd}" remaining
                [[ "${sslType}" == zerossl && "$(<"${PADM_TLS_DIR}/ssl_type")" == zerossl &&
                    "${remaining}" == next-parent-action ]]
                exec {inputFd}<&-
            done
            sslType=
            exec {inputFd}< <(printf '3\n\nnext-parent-action\n')
            switchSSLType <&"${inputFd}"
            read -r -u "${inputFd}" remaining
            [[ "${sslType}" == letsencrypt && "$(<"${PADM_TLS_DIR}/ssl_type")" == letsencrypt &&
                "${remaining}" == next-parent-action ]]
            exec {inputFd}<&-
            sslType=
            regressionExpectStatus 1 switchSSLType < <(printf '9\n')
            [[ -z "${sslType}" && "$(<"${PADM_TLS_DIR}/ssl_type")" == letsencrypt ]]
            AUTO_INSTALL=true
            AUTO_TLS_CA=unknown
            regressionExpectStatus 1 switchSSLType </dev/null
            [[ -z "${sslType}" && "$(<"${PADM_TLS_DIR}/ssl_type")" == letsencrypt ]]
        )
    )

    (
        # 签发参数读完才释放 HTTP 端口；DNS API 不需要停止 Nginx。
        eval "${autoReadDefinition}"
        local HOME="${root}/decision-home" AUTO_INSTALL= currentHost= domain=decision.example.com
        local lastInstallationConfig= ipType=4 sslIPv6= SERVICE_QUEUE_ALLOW_FAILURE=previous
        local PADM_REQUIRE_USABLE_TLS_CERTIFICATE= PADM_CORE_SWITCH_TRANSACTION_ACTIVE=
        local dnsAPIStatus dnsAPIType cfAPIToken cfZoneID aliKey aliSecret sslType sslEmail
        local input inputFd remaining provider accountFile before decisionLog="${root}/decision.log"
        export PADM_TLS_DIR="${root}/decision-tls"
        mkdir -p "${HOME}/.acme.sh"
        accountFile=$(acmeAccountFile)
        acmeExecutable() { printf tlsIssueTool; }
        tlsAcmeLogFile() { printf '%s\n' "${root}/decision-acme.log"; }
        tlsIssueTool() { printf 'issue:%s:%s\n' "${CF_Token:-${Ali_Key:-}}" "$*" >>"${decisionLog}"; }
        sudo() { "$@"; }
        handleNginx() {
            [[ "$1" == stop && "${sslType}" == zerossl && "${sslEmail}" == new@example.com &&
                "${SERVICE_QUEUE_ALLOW_FAILURE}" == true ]] || return 1
            printf 'stop\n' >>"${decisionLog}"
        }
        allowPort() { printf 'allow:%s\n' "$1" >>"${decisionLog}"; }
        installTLSFromAcme() { printf 'sync\n' >>"${decisionLog}"; }
        tlsCertificatePairUsable() { return 0; }

        for input in '' $'n\n' $'y\n\n' $'y\n\ntoken\n\nn\n' $'n\n2\n' $'n\n2\nnew@example.com'; do
            unset dnsAPIStatus dnsAPIType cfAPIToken cfZoneID aliKey aliSecret sslType sslEmail
            printf 'SAVED=unchanged\n' >"${accountFile}"
            before=$(<"${accountFile}")
            : >"${decisionLog}"
            regressionExpectStatus 1 installTLS 1 < <(printf '%s' "${input}")
            ! grep -Eq '^(allow|stop|issue|sync)' "${decisionLog}"
            [[ "$(<"${accountFile}")" == "${before}" && "${SERVICE_QUEUE_ALLOW_FAILURE}" == previous ]]
        done
        for provider in cloudflare aliyun; do
            unset dnsAPIStatus dnsAPIType cfAPIToken cfZoneID aliKey aliSecret sslType sslEmail
            : >"${decisionLog}"
            input=$'y\n1\ntoken\nzone\nn\n1\n'
            [[ "${provider}" != aliyun ]] || input=$'y\n2\nkey\nsecret\nn\n1\n'
            exec {inputFd}< <(printf '%snext-parent-action\n' "${input}")
            installTLS 1 <&"${inputFd}"
            ! grep -Eq '^(stop|allow)' "${decisionLog}"
            grep -q "^issue:.*--dns dns_" "${decisionLog}"
            [[ "$(<"${decisionLog}")" == issue:*$'\n'sync ]]
            read -r -u "${inputFd}" remaining
            [[ "${remaining}" == next-parent-action ]]
            exec {inputFd}<&-
        done
        unset dnsAPIStatus dnsAPIType cfAPIToken cfZoneID aliKey aliSecret sslType sslEmail
        : >"${decisionLog}"
        exec {inputFd}< <(printf 'n\n2\nnew@example.com\nnext-parent-action\n')
        installTLS 1 <&"${inputFd}"
        [[ "$(<"${decisionLog}")" == $'allow:80\nstop\n'issue:*--standalone*$'\n'sync ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == previous ]]
        read -r -u "${inputFd}" remaining
        [[ "${remaining}" == next-parent-action ]]
        exec {inputFd}<&-
    )

    domain=missing.example.com
    currentHost=
    installedDNSAPIStatus=
    installTLSCount=
    captureFailureReturn "${installRcFile}" installTLS 1

    local existingTlsRoot="${root}/existing-tls"
    mkdir -p "${existingTlsRoot}"
    export PADM_TLS_DIR="${existingTlsRoot}"
    domain=existing.example.com
    printf 'old-cert\n' >"${existingTlsRoot}/existing.example.com.crt"
    printf 'old-key\n' >"${existingTlsRoot}/existing.example.com.key"
    installTLSCount=
    sudo() { return 1; }
    regressionExpectStatus 1 installTLSFromAcme >/dev/null 2>&1
    unset -f sudo

    local secureTlsRoot="${root}/secure-install"
    mkdir -p "${secureTlsRoot}/home/.acme.sh" "${secureTlsRoot}/tls"
    HOME="${secureTlsRoot}/home"
    export PADM_TLS_DIR="${secureTlsRoot}/tls"
    domain=secure.example.com
    installedDNSAPIStatus=
    printf '#!/usr/bin/env sh\n' >"${HOME}/.acme.sh/acme.sh"
    command chmod 755 "${HOME}/.acme.sh/acme.sh"
    printf 'old-cert\n' >"${PADM_TLS_DIR}/secure.example.com.crt"
    printf 'old-key\n' >"${PADM_TLS_DIR}/secure.example.com.key"
    openssl req -new -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
        -subj '/CN=secure.example.com' -addext 'subjectAltName=DNS:secure.example.com' \
        -keyout "${secureTlsRoot}/new.key" -out "${secureTlsRoot}/new.crt" >/dev/null 2>&1
    command chmod 644 "${PADM_TLS_DIR}/secure.example.com.key"
    : >"${chmodLog}"
    chmod() {
        printf '%s\n' "$*" >>"${chmodLog}"
        command chmod "$@"
    }
    sudo() {
        cp "${secureTlsRoot}/new.crt" "${PADM_TLS_DIR}/secure.example.com.crt"
        cp "${secureTlsRoot}/new.key" "${PADM_TLS_DIR}/secure.example.com.key"
        return 0
    }
    installTLSFromAcme >/dev/null 2>&1
    grep -F -q -- "600 -- ${PADM_TLS_DIR}/secure.example.com.key" "${chmodLog}"
    cmp "${secureTlsRoot}/new.key" "${PADM_TLS_DIR}/secure.example.com.key"
    unset -f chmod
    unset -f sudo

    (
        acmeInstallSSL() { return 1; }
        readAcmeTLS() { return 0; }
        captureFailureReturn "${root}/select-acme.rc" selectAcmeInstallSSL
    )

    (
        readAcmeTLS() { return 1; }
        captureFailureReturn "${root}/install-read-acme.rc" installTLS 1
        captureFailureReturn "${root}/status-read-acme.rc" tlsCertificateStatusJson
        captureFailureReturn "${root}/renew-read-acme.rc" renewalTLS
    )

    (
        btDomain=
        readUserCrontabContent() { return 1; }
        captureFailureReturn "${root}/install-cron.rc" installCronTLS 1
    )

    (
        local renewalRoot="${root}/renewal-install"
        mkdir -p "${renewalRoot}/home"
        export PADM_TLS_DIR="${renewalRoot}/tls"
        HOME="${renewalRoot}/home"
        mkdir -p "${PADM_TLS_DIR}"
        domain=renew.example.com
        currentHost=renew.example.com
        tlsDomain=renew.example.com
        lastInstallationConfig=true
        installedDNSAPIStatus=
        printf 'cert\n' >"${PADM_TLS_DIR}/renew.example.com.crt"
        printf 'key\n' >"${PADM_TLS_DIR}/renew.example.com.key"
        readAcmeTLS() { return 0; }
        renewalTLS() { return 37; }
        ! installTLS 1 >/dev/null 2>&1
    )

    (
        local emptyKeyRoot="${root}/empty-key"
        mkdir -p "${emptyKeyRoot}/home" "${emptyKeyRoot}/tls"
        export PADM_TLS_DIR="${emptyKeyRoot}/tls"
        HOME="${emptyKeyRoot}/home"
        domain=empty-key.example.com
        currentHost=empty-key.example.com
        tlsDomain=empty-key.example.com
        lastInstallationConfig=true
        installedDNSAPIStatus=
        printf 'cert\n' >"${PADM_TLS_DIR}/empty-key.example.com.crt"
        : >"${PADM_TLS_DIR}/empty-key.example.com.key"
        readAcmeTLS() { return 0; }
        ! installTLS 1 >/dev/null 2>&1
    )

    (
        local acmeOnlyRoot="${root}/acme-only"
        mkdir -p "${acmeOnlyRoot}/home/.acme.sh/acme-only.example.com_ecc"
        export PADM_TLS_DIR="${acmeOnlyRoot}/tls"
        HOME="${acmeOnlyRoot}/home"
        domain=acme-only.example.com
        currentHost=acme-only.example.com
        tlsDomain=acme-only.example.com
        installedDNSAPIStatus=
        printf 'cert\n' >"${HOME}/.acme.sh/acme-only.example.com_ecc/acme-only.example.com.cer"
        printf 'key\n' >"${HOME}/.acme.sh/acme-only.example.com_ecc/acme-only.example.com.key"
        local acmeInstallFromHomeCalled=false
        readAcmeTLS() { return 0; }
        installTLSFromAcme() { acmeInstallFromHomeCalled=true; return 0; }
        tlsCertificatePairUsable() { return 0; }
        installTLS 1 >/dev/null 2>&1
        [[ "${acmeInstallFromHomeCalled}" == "true" ]]
    )

    (
        local certificateRoot="${root}/usable-certificate"
        local certDomain=custom.example.com
        mkdir -p "${certificateRoot}/home" "${certificateRoot}/tls"
        export PADM_TLS_DIR="${certificateRoot}/tls"
        HOME="${certificateRoot}/home"
        domain=${certDomain}
        currentHost=${certDomain}
        tlsDomain=${certDomain}
        lastInstallationConfig=true
        installedDNSAPIStatus=
        unset PADM_REQUIRE_USABLE_TLS_CERTIFICATE
        readAcmeTLS() { return 0; }
        collectTLSProfile() { tlsCertDomain=${certDomain}; }
        openssl req -new -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 \
            -subj "/CN=${certDomain}" -addext "subjectAltName=DNS:${certDomain}" \
            -keyout "${certificateRoot}/valid.key" -out "${certificateRoot}/valid.crt" >/dev/null 2>&1
        openssl req -new -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
            -subj "/CN=${certDomain}" -addext "subjectAltName=DNS:${certDomain}" \
            -keyout "${certificateRoot}/expiring.key" -out "${certificateRoot}/expiring.crt" >/dev/null 2>&1
        openssl req -new -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
            -subj "/CN=wrong.example.com" -addext "subjectAltName=DNS:wrong.example.com" \
            -keyout "${certificateRoot}/wrong.key" -out "${certificateRoot}/wrong.crt" >/dev/null 2>&1

        # 自签证书可正常复用；错域名、错私钥和损坏 PEM 均不能冒充安装成功。
        cp "${certificateRoot}/valid.crt" "${PADM_TLS_DIR}/${certDomain}.crt"
        cp "${certificateRoot}/valid.key" "${PADM_TLS_DIR}/${certDomain}.key"
        chmod 644 "${PADM_TLS_DIR}/${certDomain}.key"
        local renewalCalls=0
        renewalTLS() { renewalCalls=$((renewalCalls + 1)); return 37; }
        installTLS 1 >/dev/null 2>&1
        [[ "${renewalCalls}" == 0 && "$(stat -c %a "${PADM_TLS_DIR}/${certDomain}.key")" == 600 ]]
        singBoxLocalCertificateAvailable
        cp "${certificateRoot}/expiring.crt" "${PADM_TLS_DIR}/${certDomain}.crt"
        cp "${certificateRoot}/expiring.key" "${PADM_TLS_DIR}/${certDomain}.key"
        regressionExpectStatus 1 installTLS 1 >/dev/null 2>&1
        [[ "${renewalCalls}" == 1 ]]
        cp "${certificateRoot}/wrong.crt" "${PADM_TLS_DIR}/${certDomain}.crt"
        regressionExpectStatus 1 installTLS 1 >/dev/null 2>&1
        [[ "${renewalCalls}" == 2 ]]
        ! singBoxLocalCertificateAvailable
        cp "${certificateRoot}/valid.crt" "${PADM_TLS_DIR}/${certDomain}.crt"
        cp "${certificateRoot}/wrong.key" "${PADM_TLS_DIR}/${certDomain}.key"
        regressionExpectStatus 1 installTLS 1 >/dev/null 2>&1
        ! singBoxLocalCertificateAvailable
        printf 'invalid-pem\n' >"${PADM_TLS_DIR}/${certDomain}.crt"
        regressionExpectStatus 1 installTLS 1 >/dev/null 2>&1
        ! singBoxLocalCertificateAvailable

        # ACME 退出成功但写入错误证书时，在删除备份前恢复合法旧证书和私钥。
        local badPair oldPairHash
        acmeExecutable() { printf '/bin/true\n'; }
        sudo() {
            cp "${certificateRoot}/valid.key" "${PADM_TLS_DIR}/${certDomain}.key"
            case "${badPair}" in
            domain) cp "${certificateRoot}/wrong.crt" "${PADM_TLS_DIR}/${certDomain}.crt" ;;
            key)
                cp "${certificateRoot}/valid.crt" "${PADM_TLS_DIR}/${certDomain}.crt"
                cp "${certificateRoot}/wrong.key" "${PADM_TLS_DIR}/${certDomain}.key"
                ;;
            pem) printf 'invalid-pem\n' >"${PADM_TLS_DIR}/${certDomain}.crt" ;;
            esac
        }
        for badPair in domain key pem; do
            cp "${certificateRoot}/valid.crt" "${PADM_TLS_DIR}/${certDomain}.crt"
            cp "${certificateRoot}/valid.key" "${PADM_TLS_DIR}/${certDomain}.key"
            oldPairHash=$(sha256sum "${PADM_TLS_DIR}/${certDomain}.crt" "${PADM_TLS_DIR}/${certDomain}.key")
            installTLSCount=1
            regressionExpectStatus 1 installTLSFromAcme >/dev/null 2>&1
            [[ "$(sha256sum "${PADM_TLS_DIR}/${certDomain}.crt" "${PADM_TLS_DIR}/${certDomain}.key")" == "${oldPairHash}" ]]
            tlsCertificatePairUsable "${PADM_TLS_DIR}" "${certDomain}"
        done
        unset -f sudo

        # ACME 同步返回成功也必须验证实际落盘文件，不能只相信命令状态。
        mkdir -p "${HOME}/.acme.sh/${certDomain}_ecc"
        cp "${certificateRoot}/valid.crt" "${HOME}/.acme.sh/${certDomain}_ecc/${certDomain}.cer"
        cp "${certificateRoot}/valid.key" "${HOME}/.acme.sh/${certDomain}_ecc/${certDomain}.key"
        rm -f "${PADM_TLS_DIR}/${certDomain}.crt" "${PADM_TLS_DIR}/${certDomain}.key"
        installTLSFromAcme() {
            printf 'invalid-pem\n' >"${PADM_TLS_DIR}/${certDomain}.crt"
            cp "${certificateRoot}/valid.key" "${PADM_TLS_DIR}/${certDomain}.key"
        }
        regressionExpectStatus 1 installTLS 1 >/dev/null 2>&1
    )

    (
        local missingRenewRoot="${root}/renewal-missing"
        mkdir -p "${missingRenewRoot}/home" "${missingRenewRoot}/tls"
        export PADM_TLS_DIR="${missingRenewRoot}/tls"
        HOME="${missingRenewRoot}/home"
        currentHost=
        domain=
        tlsDomain=
        installedDNSAPIStatus=
        readAcmeTLS() { return 0; }
        errorCard() { return 0; }
        ! renewalTLS >/dev/null 2>&1
    )

    (
        # 增量申请在域名取消时不能安装 ACME 或操作服务。
        local events= currentHost= lastInstallationConfig= domain=stale.example.com
        unset AUTO_DOMAIN AUTO_INSTALL
        installAcmeTool() { events+=$'acme\n'; return 0; }
        nginxRunning() { events+=$'nginx\n'; return 1; }
        regressionExpectStatus 1 singBoxInstallLocalTLSCertificate <<<""
        [[ -z "${events}" ]]
    )

    (
        # 域名只读一次，并保留给证书就绪后的协议模板使用。
        local domain= currentHost=old-entry.example.com lastInstallationConfig=
        local AUTO_DOMAIN=prepared.example.com inputFd nextInput
        local dnsAPIStatus=y dnsAPIType=cloudflare cfAPIToken=parent-token cfZoneID=parent-zone
        local aliKey=parent-key aliSecret=parent-secret sslIPv6=--listen-v6
        installAcmeTool() { return 0; }
        nginxRunning() { return 1; }
        xrayRunning() { return 1; }
        singBoxRunning() { return 1; }
        initTLSNginxConfig() { [[ "$2" == prepared.example.com ]] || return 1; domain=$2; }
        installTLS() {
            [[ -z "${dnsAPIStatus+x}${dnsAPIType+x}${cfAPIToken+x}${cfZoneID+x}${aliKey+x}${aliSecret+x}${sslIPv6+x}" ]]
        }
        singBoxLocalCertificateAvailable() { [[ "${domain}" == prepared.example.com ]]; }
        installCronTLS() { return 0; }
        restoreServicesAfterTLSRenewal() { return 0; }
        exec {inputFd}< <(printf 'next-parent-action\n')
        singBoxInstallLocalTLSCertificate <&"${inputFd}"
        [[ "${domain}" == prepared.example.com ]]
        [[ "${dnsAPIStatus}" == y && "${dnsAPIType}" == cloudflare &&
            "${cfAPIToken}" == parent-token && "${cfZoneID}" == parent-zone &&
            "${aliKey}" == parent-key && "${aliSecret}" == parent-secret && "${sslIPv6}" == --listen-v6 ]]
        read -r -u "${inputFd}" nextInput
        [[ "${nextInput}" == next-parent-action ]]
        exec {inputFd}<&-
    )

    btDomain=
    readLastInstallationConfig() { return 0; }
    unInstallSubscribe() { return 0; }
    installTools() { return 0; }
    initTLSNginxConfig() { return 0; }
    installTLS() { return 1; }
    randomPathFunction() {
        printf 'reached\n' >"${reachedFile}"
        return 0
    }

    captureFailureReturn "${xrayRcFile}" xrayCoreInstall
    [[ ! -e "${reachedFile}" ]]

    HOME="${oldHome}"
)

runTlsRenewalFailurePropagationRegression() (
    local root="${TMP_DIR}/tls-renew-failure-propagation"
    local tlsDir="${root}/certs"
    local homeDir="${root}/home"
    local serviceLog="${root}/services.log"
    local commandLog="${root}/commands.log"
    local statusLog="${root}/status.log"
    local errorLog="${root}/error.log"
    local statusJson
    local mode rc tlsRegressionStatMode=
    local chmodLog="${TMP_DIR}/tls-renew-chmod.log"
    local nginxState xrayState singBoxState

    mkdir -p "${tlsDir}" "${homeDir}"
    HOME="${homeDir}"
    PADM_TLS_DIR="${tlsDir}"
    currentHost=renew.example.com
    domain=
    tlsDomain=
    dnsTLSDomain=
    installedDNSAPIStatus=
    coreInstallType=1
    sslRenewalDays=90
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    export REGRESSION_STATUS_CARD_LOG="${statusLog}"
    export REGRESSION_ERROR_CARD_LOG="${errorLog}"

    statusCard() { printf '%s\n' "$*" >>"${statusLog}"; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    nginxRunning() { [[ "${nginxState}" == "true" ]]; }
    xrayRunning() { [[ "${xrayState}" == "true" ]]; }
    singBoxRunning() { [[ "${singBoxState}" == "true" ]]; }
    handleNginx() {
        if [[ "$1" == "stop" && "${nginxState}" != "true" ]] || [[ "$1" == "start" && "${nginxState}" == "true" ]]; then
            return 0
        fi
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ -n "${2:-}" ]] && printf 'nginx-mode:%s\n' "$*" >>"${serviceLog}"
        [[ "${mode}" == "nginx-stop-fail" && "$1" == "stop" ]] && return 1
        [[ "${mode}" == "nginx-start-fail" && "$1" == "start" ]] && return 1
        [[ "$1" == "start" ]] && nginxState=true || nginxState=false
        return 0
    }
    handleXray() {
        if [[ "$1" == "stop" && "${xrayState}" != "true" ]] || [[ "$1" == "start" && "${xrayState}" == "true" ]]; then
            return 0
        fi
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "xray-stop-fail" && "$1" == "stop" ]] && return 1
        [[ "${mode}" == "xray-start-fail" && "$1" == "start" ]] && return 1
        [[ "$1" == "start" ]] && xrayState=true || xrayState=false
        return 0
    }
    handleSingBox() {
        if [[ "$1" == "stop" && "${singBoxState}" != "true" ]] || [[ "$1" == "start" && "${singBoxState}" == "true" ]]; then
            return 0
        fi
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "$1" == "start" ]] && singBoxState=true || singBoxState=false
        return 0
    }
    reloadCore() {
        printf 'reload\n' >>"${serviceLog}"
        [[ "${mode}" == "reload-fail" ]] && return 1
        xrayState=true
        singBoxState=true
        return 0
    }
    stat() {
        if [[ "${tlsRegressionStatMode:-}" == "unsafe-acme" && "$1" == "--format=%a" ]]; then
            printf '777\n'
            return 0
        fi
        if [[ "$1" == "--format=%z" && "${2:-}" == *"/renew.example.com_ecc/renew.example.com.cer" ]]; then
            date -d '89 days ago' '+%F %T.000000000 %z'
            return 0
        fi
        command stat "$@"
    }
    sudo() {
        printf 'sudo:%s\n' "$*" >>"${commandLog}"
        [[ "${mode}" == "renew-fail" && "$*" == *" --cron "* ]] && return 1
        [[ "${mode}" == "install-fail" && "$*" == *" --installcert "* ]] && return 1
        return 0
    }
    chmod() {
        printf '%s\n' "$*" >>"${chmodLog}"
        command chmod "$@"
    }
    prepareRenewalFixture() {
        rm -rf "${tlsDir}" "${homeDir}/.acme.sh"
        mkdir -p "${tlsDir}" "${homeDir}/.acme.sh/renew.example.com_ecc"
        printf 'cert\n' >"${tlsDir}/renew.example.com.crt"
        printf 'key\n' >"${tlsDir}/renew.example.com.key"
        printf 'cert\n' >"${homeDir}/.acme.sh/renew.example.com_ecc/renew.example.com.cer"
        printf 'key\n' >"${homeDir}/.acme.sh/renew.example.com_ecc/renew.example.com.key"
        printf '#!/usr/bin/env sh\n' >"${homeDir}/.acme.sh/acme.sh"
        chmod 755 "${homeDir}/.acme.sh/acme.sh"
        : >"${serviceLog}"
        : >"${commandLog}"
        : >"${chmodLog}"
        : >"${statusLog}"
        : >"${errorLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        nginxState=true
        xrayState=true
        singBoxState=false
        if [[ "${mode}" == "stopped-services" ]]; then
            nginxState=false
            xrayState=false
        elif [[ "${mode}" == "dual-core-running" ]]; then
            singBoxState=true
        fi
    }
    runRenewalCase() {
        mode=$1
        prepareRenewalFixture
        set +e
        renewalTLS >/dev/null 2>&1
        rc=$?
        set -e
    }

    rm -rf "${tlsDir}" "${homeDir}/.acme.sh"
    mkdir -p "${tlsDir}" "${homeDir}"
    currentHost=../escape
    domain=
    tlsDomain=
    installedDNSAPIStatus=
    dnsTLSDomain=
    printf 'cert\n' >"${root}/escape.crt"
    printf 'key\n' >"${root}/escape.key"
    : >"${statusLog}"
    : >"${errorLog}"
    statusJson=$(tlsCertificateStatusJson)
    jq -e '.status == "missing"' <<<"${statusJson}" >/dev/null
    ! renewalTLS >/dev/null 2>&1
    grep -q "未安装本机 TLS 证书" "${errorLog}"
    ! grep -q "检测到使用自定义证书" "${statusLog}"
    rm -f "${root}/escape.crt" "${root}/escape.key"

    currentHost=
    printf 'cert\n' >"${tlsDir}/bad;name.crt"
    printf 'key\n' >"${tlsDir}/bad;name.key"
    : >"${statusLog}"
    : >"${errorLog}"
    statusJson=$(tlsCertificateStatusJson)
    jq -e '.status == "missing"' <<<"${statusJson}" >/dev/null
    ! renewalTLS >/dev/null 2>&1
    grep -q "未安装本机 TLS 证书" "${errorLog}"
    ! grep -q "检测到使用自定义证书" "${statusLog}"
    rm -f "${tlsDir}/bad;name.crt" "${tlsDir}/bad;name.key"
    currentHost=renew.example.com

    mode=unsafe-acme
    prepareRenewalFixture
    tlsRegressionStatMode=unsafe-acme
    chmod 777 "${homeDir}/.acme.sh"
    regressionExpectStatus 1 renewalTLS >/dev/null 2>&1
    [[ ! -s "${commandLog}" ]]
    [[ ! -s "${serviceLog}" ]]
    grep -q 'acme.sh 路径、所有者或权限异常' "${errorLog}"
    tlsRegressionStatMode=

    runRenewalCase nginx-stop-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:stop:true' "${serviceLog}"
    ! grep -q '^sudo:' "${commandLog}"
    ! grep -q '^xray:stop:' "${serviceLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    runRenewalCase xray-stop-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:stop:true' "${serviceLog}"
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    ! grep -q '^sudo:' "${commandLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    runRenewalCase renew-fail
    [[ "${rc}" == "1" ]]
    grep -q '^sudo:.*--cron --home ' "${commandLog}"
    ! grep -q '^sudo:.*--installcert ' "${commandLog}"
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    ! grep -qx 'reload' "${serviceLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    runRenewalCase install-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:stop:true' "${serviceLog}"
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    ! grep -qx 'reload' "${serviceLog}"
    grep -q '^sudo:.*--cron --home ' "${commandLog}"
    grep -q '^sudo:.*--installcert -d renew.example.com' "${commandLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    runRenewalCase xray-start-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    ! grep -qx 'reload' "${serviceLog}"
    grep -q '^sudo:.*--installcert -d renew.example.com' "${commandLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    runRenewalCase nginx-start-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    ! grep -qx 'reload' "${serviceLog}"
    grep -q '^sudo:.*--installcert -d renew.example.com' "${commandLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    runRenewalCase stopped-services
    [[ "${rc}" == "0" ]]
    grep -F -q -- "600 -- ${tlsDir}/renew.example.com.key" "${chmodLog}"
    [[ ! -s "${serviceLog}" ]]
    [[ "${nginxState}" == "false" && "${xrayState}" == "false" && "${singBoxState}" == "false" ]]

    runRenewalCase dual-core-running
    [[ "${rc}" == "0" ]]
    grep -qx 'nginx:stop:true' "${serviceLog}"
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'sing-box:start:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    ! grep -qx 'reload' "${serviceLog}"
    [[ "${nginxState}" == "true" && "${xrayState}" == "true" && "${singBoxState}" == "true" ]]

    (
        local legacyDomain=legacy.example.com
        local subscribeTlsDomain=subscribe.example.com
        local usableChecks=0
        mode=multi-cert
        rm -rf "${tlsDir}" "${homeDir}/.acme.sh"
        mkdir -p "${tlsDir}" \
            "${homeDir}/.acme.sh/${legacyDomain}_ecc" \
            "${homeDir}/.acme.sh/${subscribeTlsDomain}_ecc"
        chmod 700 "${homeDir}/.acme.sh"
        printf '#!/usr/bin/env sh\n' >"${homeDir}/.acme.sh/acme.sh"
        chmod 755 "${homeDir}/.acme.sh/acme.sh"
        printf 'legacy-old-cert\n' >"${tlsDir}/${legacyDomain}.crt"
        printf 'legacy-old-key\n' >"${tlsDir}/${legacyDomain}.key"
        printf 'subscribe-old-cert\n' >"${tlsDir}/${subscribeTlsDomain}.crt"
        printf 'subscribe-old-key\n' >"${tlsDir}/${subscribeTlsDomain}.key"
        cat >"${homeDir}/.acme.sh/${legacyDomain}_ecc/${legacyDomain}.conf" <<EOF
Le_Domain='${legacyDomain}'
Le_Webroot='dns_cf'
Le_RealFullChainPath='${tlsDir}/${legacyDomain}.crt'
Le_RealKeyPath='${tlsDir}/${legacyDomain}.key'
EOF
        cat >"${homeDir}/.acme.sh/${subscribeTlsDomain}_ecc/${subscribeTlsDomain}.conf" <<EOF
Le_Domain='${subscribeTlsDomain}'
Le_Webroot='dns_cf'
Le_RealFullChainPath='${tlsDir}/${subscribeTlsDomain}.crt'
Le_RealKeyPath='${tlsDir}/${subscribeTlsDomain}.key'
EOF
        : >"${commandLog}"
        : >"${serviceLog}"
        nginxState=true
        xrayState=false
        singBoxState=false
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        tlsCertificatePairUsable() {
            usableChecks=$((usableChecks + 1))
            ((usableChecks > 2))
        }
        sudo() {
            printf 'sudo:%s\n' "$*" >>"${commandLog}"
            case " $* " in
            *" --installcert -d ${legacyDomain} "*)
                printf 'legacy-new-cert\n' >"${tlsDir}/${legacyDomain}.crt"
                printf 'legacy-new-key\n' >"${tlsDir}/${legacyDomain}.key"
                ;;
            *" --installcert -d ${subscribeTlsDomain} "*)
                printf 'subscribe-new-cert\n' >"${tlsDir}/${subscribeTlsDomain}.crt"
                printf 'subscribe-new-key\n' >"${tlsDir}/${subscribeTlsDomain}.key"
                ;;
            esac
        }
        reloadCore() { printf 'reload\n' >>"${serviceLog}"; }
        handleNginx() { printf 'nginx:%s\n' "$1" >>"${serviceLog}"; }
        readNginxSubscribe() {
            subscribeConfigState=valid
            subscribeDomain=${subscribeTlsDomain}
            subscribePort=39778
        }
        probeSubscribeTLS() { printf 'probe:%s:%s\n' "$1" "$2" >>"${serviceLog}"; }

        renewManagedTLSCertificates
        [[ "$(grep -c -- ' --cron ' "${commandLog}")" == "1" ]]
        [[ "$(grep -c -- ' --installcert ' "${commandLog}")" == "2" ]]
        grep -q -- " --installcert -d ${legacyDomain} " "${commandLog}"
        grep -q -- " --installcert -d ${subscribeTlsDomain} " "${commandLog}"
        [[ "$(<"${tlsDir}/${legacyDomain}.crt")" == "legacy-new-cert" ]]
        [[ "$(<"${tlsDir}/${subscribeTlsDomain}.crt")" == "subscribe-new-cert" ]]
        [[ "$(grep -c '^reload$' "${serviceLog}")" == "1" ]]
        [[ "$(grep -c '^nginx:stop$' "${serviceLog}")" == "1" ]]
        [[ "$(grep -c '^nginx:start$' "${serviceLog}")" == "1" ]]
        ! grep -q '^nginx:restart$' "${serviceLog}"
        grep -qx "probe:${subscribeTlsDomain}:39778" "${serviceLog}"
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    )

    (
        local certDomain=managed-http.example.com
        local usableChecks=0 chmodChecks=0 managedRc
        mode=managed-post-renew-chmod-fail
        rm -rf "${tlsDir}" "${homeDir}/.acme.sh"
        mkdir -p "${tlsDir}" "${homeDir}/.acme.sh/${certDomain}_ecc"
        chmod 700 "${homeDir}/.acme.sh"
        printf '#!/usr/bin/env sh\n' >"${homeDir}/.acme.sh/acme.sh"
        chmod 755 "${homeDir}/.acme.sh/acme.sh"
        printf 'old-cert\n' >"${tlsDir}/${certDomain}.crt"
        printf 'old-key\n' >"${tlsDir}/${certDomain}.key"
        cat >"${homeDir}/.acme.sh/${certDomain}_ecc/${certDomain}.conf" <<EOF
Le_Domain='${certDomain}'
Le_Webroot='/var/www/html'
Le_RealFullChainPath='${tlsDir}/${certDomain}.crt'
Le_RealKeyPath='${tlsDir}/${certDomain}.key'
EOF
        : >"${commandLog}"
        : >"${serviceLog}"
        : >"${errorLog}"
        nginxState=true
        xrayState=true
        singBoxState=false
        tlsCertificatePairUsable() {
            usableChecks=$((usableChecks + 1))
            ((usableChecks > 1))
        }
        sudo() {
            printf 'sudo:%s\n' "$*" >>"${commandLog}"
            if [[ " $* " == *" --installcert -d ${certDomain} "* ]]; then
                printf 'new-cert\n' >"${tlsDir}/${certDomain}.crt"
                printf 'new-key\n' >"${tlsDir}/${certDomain}.key"
            fi
        }
        chmod() {
            if [[ "${1:-}" == "600" && "${3:-}" == "${tlsDir}/${certDomain}.key" ]]; then
                chmodChecks=$((chmodChecks + 1))
                ((chmodChecks == 2)) && return 1
            fi
            command chmod "$@"
        }

        regressionExpectStatus 1 renewManagedTLSCertificates >/dev/null 2>&1
        [[ "$(<"${tlsDir}/${certDomain}.crt")" == "old-cert" ]]
        [[ "$(<"${tlsDir}/${certDomain}.key")" == "old-key" ]]
        grep -qx 'xray:start:true' "${serviceLog}"
        grep -qx 'nginx:start:true' "${serviceLog}"
        [[ "${nginxState}" == "true" && "${xrayState}" == "true" && "${singBoxState}" == "false" ]]
        grep -q 'TLS 证书续签后文件校验失败' "${errorLog}"
    )

    (
        local scopedRoot="${root}/scoped-install"
        local tlsDir="${scopedRoot}/tls" homeDir="${scopedRoot}/home"
        local targetDomain=install.example.com unrelatedDomain=unrelated.example.com
        local acmeDomain sourceDir oldPairHash webroot probeDomain=${unrelatedDomain}
        local nginxHandlerDefinition
        local PADM_REQUIRE_USABLE_TLS_CERTIFICATE= PADM_CORE_SWITCH_TRANSACTION_ACTIVE=
        local lastInstallationConfig=true
        mkdir -p "${scopedRoot}"
        HOME="${homeDir}"
        PADM_TLS_DIR="${tlsDir}"
        command openssl req -new -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 \
            -subj "/CN=install.example.com" -addext "subjectAltName=DNS:install.example.com,DNS:*.legacy.example.net" \
            -keyout "${scopedRoot}/valid.key" -out "${scopedRoot}/valid.crt" >/dev/null 2>&1
        command openssl req -new -x509 -key "${scopedRoot}/valid.key" -days 1 \
            -subj "/CN=install.example.com" -addext "subjectAltName=DNS:install.example.com,DNS:*.legacy.example.net" \
            -out "${scopedRoot}/expiring.crt" >/dev/null 2>&1

        prepareScopedInstallFixture() {
            local sourceAge=$1 webroot=$2 legacy=${3:-false}
            targetDomain=install.example.com
            acmeDomain=${targetDomain}
            if [[ "${legacy}" == true ]]; then
                targetDomain=api.legacy.example.net
                acmeDomain='*.legacy.example.net'
            fi
            domain=${targetDomain}
            currentHost=${targetDomain}
            rm -rf "${tlsDir}" "${homeDir}/.acme.sh"
            sourceDir="${homeDir}/.acme.sh/${acmeDomain}_ecc"
            mkdir -p "${tlsDir}" "${sourceDir}" "${homeDir}/.acme.sh/${unrelatedDomain}_ecc"
            command chmod 700 "${homeDir}" "${homeDir}/.acme.sh"
            printf '#!/usr/bin/env sh\n' >"${homeDir}/.acme.sh/acme.sh"
            command chmod 755 "${homeDir}/.acme.sh/acme.sh"
            cp "${scopedRoot}/${sourceAge}.crt" "${sourceDir}/${acmeDomain}.cer"
            cp "${scopedRoot}/valid.key" "${sourceDir}/${acmeDomain}.key"
            cp "${scopedRoot}/expiring.crt" "${tlsDir}/${targetDomain}.crt"
            printf 'old-invalid-key\n' >"${tlsDir}/${targetDomain}.key"
            printf "Le_Domain='%s'\nLe_Webroot='%s'\n" "${acmeDomain}" "${webroot}" >"${sourceDir}/${acmeDomain}.conf"
            if [[ "${legacy}" != true ]]; then
                printf "Le_RealFullChainPath='%s/%s.crt'\nLe_RealKeyPath='%s/%s.key'\n" \
                    "${tlsDir}" "${targetDomain}" "${tlsDir}" "${targetDomain}" >>"${sourceDir}/${acmeDomain}.conf"
            fi
            # 无关域名的受管记录故意缺证书，安装不能检查、续签或修复它。
            printf 'unrelated-key\n' >"${tlsDir}/${unrelatedDomain}.key"
            printf "Le_Domain='%s'\nLe_Webroot='dns_cf'\nLe_RealFullChainPath='%s/%s.crt'\nLe_RealKeyPath='%s/%s.key'\n" \
                "${unrelatedDomain}" "${tlsDir}" "${unrelatedDomain}" "${tlsDir}" "${unrelatedDomain}" \
                >"${homeDir}/.acme.sh/${unrelatedDomain}_ecc/${unrelatedDomain}.conf"
            : >"${commandLog}"
            : >"${serviceLog}"
            : >"${errorLog}"
            nginxState=true
            xrayState=true
            singBoxState=false
            SERVICE_QUEUE_ALLOW_FAILURE=previous
            oldPairHash=$(sha256sum "${tlsDir}/${targetDomain}.crt" "${tlsDir}/${targetDomain}.key")
        }
        sudo() {
            local action= installDomain= crtTarget= keyTarget= acmeHome= force=false ecc=false
            printf 'sudo:%s\n' "$*" >>"${commandLog}"
            shift
            while [[ $# -gt 0 ]]; do
                case "$1" in
                --installcert|--renew) action=${1#--}; shift ;;
                -d) installDomain=$2; shift 2 ;;
                --fullchainpath) crtTarget=$2; shift 2 ;;
                --keypath) keyTarget=$2; shift 2 ;;
                --home) acmeHome=$2; shift 2 ;;
                --force) force=true; shift ;;
                --ecc) ecc=true; shift ;;
                *) return 1 ;;
                esac
            done
            [[ "${installDomain}" == "${acmeDomain}" && "${ecc}" == true ]] || return 1
            case "${action}" in
            installcert)
                [[ "${crtTarget}" == "${tlsDir}/${targetDomain}.crt" &&
                    "${keyTarget}" == "${tlsDir}/${targetDomain}.key" ]] || return 1
                cp "${sourceDir}/${acmeDomain}.cer" "${crtTarget}" || return 1
                cp "${sourceDir}/${acmeDomain}.key" "${keyTarget}"
                ;;
            renew)
                [[ "${force}" == true && "${acmeHome}" == "${homeDir}/.acme.sh" ]] || return 1
                [[ "${mode}" != scoped-renew-fail ]] || return 1
                [[ "${mode}" != scoped-renew-short ]] || return 0
                cp "${scopedRoot}/valid.crt" "${sourceDir}/${acmeDomain}.cer" || return 1
                if [[ "${mode}" == scoped-renew-bad ]]; then
                    printf 'invalid-new-key\n' >"${sourceDir}/${acmeDomain}.key"
                fi
                ;;
            *) return 1 ;;
            esac
        }
        nginxHandlerDefinition=$(declare -f handleNginx)
        eval "${nginxHandlerDefinition/handleNginx/scopedOriginalHandleNginx}"
        handleNginx() {
            if [[ "${mode}" == xray-stop-fail && "$1" == start ]] &&
                ! tlsCertificatePairUsable "${tlsDir}" "${targetDomain}"; then
                printf 'nginx:start-invalid-pair\n' >>"${serviceLog}"
                return 1
            fi
            scopedOriginalHandleNginx "$@"
        }
        runServiceAction() {
            [[ "$2" == restart ]] || return 1
            printf 'restart:%s\n' "$1" >>"${serviceLog}"
            case "$1" in
            xray) handleXray stop && handleXray start ;;
            sing-box) handleSingBox stop && handleSingBox start ;;
            *) return 1 ;;
            esac
        }
        reloadCore() { printf 'reload\n' >>"${serviceLog}"; }
        readNginxSubscribe() {
            subscribeConfigState=valid
            subscribeDomain=${probeDomain}
            subscribePort=39778
        }
        probeSubscribeTLS() { printf 'probe:%s\n' "$1" >>"${serviceLog}"; return 1; }
        assertScopedInstallIsolation() {
            ! grep -q -- ' --cron ' "${commandLog}"
            ! grep -Fq -- " -d ${unrelatedDomain} " "${commandLog}"
            [[ ! -e "${tlsDir}/${unrelatedDomain}.crt" &&
                "$(<"${tlsDir}/${unrelatedDomain}.key")" == unrelated-key ]]
            ! grep -q '^probe:' "${serviceLog}"
            [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == previous ]]
        }

        # 本域 ACME 源证书仍有效时只同步；临近过期才定向强制续签。
        mode=scoped-sync
        for webroot in dns_cf no; do
            prepareScopedInstallFixture valid "${webroot}"
            installTLS 1 >/dev/null 2>&1
            [[ "$(grep -c -- ' --installcert ' "${commandLog}")" == 1 ]]
            ! grep -q -- ' --renew ' "${commandLog}"
            tlsCertificatePairUsable "${tlsDir}" "${targetDomain}"
            [[ "${xrayState}" == true && "${singBoxState}" == false ]]
            grep -qx 'restart:xray' "${serviceLog}"
            ! grep -Eq '^(restart:sing-box|sing-box:|reload$)' "${serviceLog}"
            assertScopedInstallIsolation
        done

        mode=scoped-renew
        prepareScopedInstallFixture expiring no
        installTLS 1 >/dev/null 2>&1
        [[ "$(grep -c -- ' --renew ' "${commandLog}")" == 1 &&
            "$(grep -c -- ' --installcert ' "${commandLog}")" == 2 ]]
        command openssl x509 -in "${tlsDir}/${targetDomain}.crt" -checkend 86400 -noout >/dev/null
        [[ "${nginxState}" == true && "${xrayState}" == true && "${singBoxState}" == false ]]
        grep -qx 'xray:start:true' "${serviceLog}"
        grep -qx 'nginx-mode:start restore' "${serviceLog}"
        assertScopedInstallIsolation

        for mode in scoped-renew-fail scoped-renew-bad scoped-renew-short; do
            prepareScopedInstallFixture expiring no
            regressionExpectStatus 1 installTLS 1 >/dev/null 2>&1
            [[ "$(sha256sum "${tlsDir}/${targetDomain}.crt" "${tlsDir}/${targetDomain}.key")" == "${oldPairHash}" ]]
            [[ "${nginxState}" == true && "${xrayState}" == true && "${singBoxState}" == false ]]
            grep -qx 'xray:start:true' "${serviceLog}"
            grep -qx 'nginx-mode:start restore' "${serviceLog}"
            assertScopedInstallIsolation
        done

        # 部分停止失败时，先恢复旧证书再重试恢复先前运行的 Nginx。
        mode=xray-stop-fail
        prepareScopedInstallFixture expiring no
        cp "${scopedRoot}/valid.key" "${tlsDir}/${targetDomain}.key"
        printf 'invalid-source-key\n' >"${sourceDir}/${acmeDomain}.key"
        oldPairHash=$(sha256sum "${tlsDir}/${targetDomain}.crt" "${tlsDir}/${targetDomain}.key")
        regressionExpectStatus 1 installTLS 1 >/dev/null 2>&1
        [[ "$(sha256sum "${tlsDir}/${targetDomain}.crt" "${tlsDir}/${targetDomain}.key")" == "${oldPairHash}" ]]
        [[ "${nginxState}" == true && "${xrayState}" == true && "${singBoxState}" == false ]]
        grep -qx 'nginx:start-invalid-pair' "${serviceLog}"
        grep -qx 'nginx-mode:start restore' "${serviceLog}"
        ! grep -q -- ' --renew ' "${commandLog}"
        assertScopedInstallIsolation

        # 旧通配符记录没有安装路径，也只更新当前主机名的证书文件。
        mode=scoped-renew
        prepareScopedInstallFixture expiring dns_cf true
        installTLS 1 >/dev/null 2>&1
        grep -Fq -- " --renew -d ${acmeDomain} " "${commandLog}"
        tlsCertificatePairUsable "${tlsDir}" "${targetDomain}"
        assertScopedInstallIsolation

        prepareScopedInstallFixture valid dns_cf
        nginxState=false
        xrayState=false
        probeDomain=${targetDomain}
        installTLS 1 >/dev/null 2>&1
        [[ "${nginxState}" == false && "${xrayState}" == false && "${singBoxState}" == false ]]
        [[ ! -s "${serviceLog}" ]]
        assertScopedInstallIsolation

        prepareScopedInstallFixture valid dns_cf
        rm -f "${sourceDir}/${acmeDomain}.conf"
        regressionExpectStatus 1 installTLS 1 >/dev/null 2>&1
        [[ ! -s "${commandLog}" && ! -s "${serviceLog}" ]]
        [[ "$(sha256sum "${tlsDir}/${targetDomain}.crt" "${tlsDir}/${targetDomain}.key")" == "${oldPairHash}" ]]
    )

    eval "$(awk '/^handleScriptCommand\(\)/,/^}/ { print }' "${PROJECT_ROOT}/install.sh")"
    renewalTLS() { return 37; }
    cronName=RenewTLS
    set +e
    (handleScriptCommand)
    rc=$?
    set -e
    [[ "${rc}" == "37" ]]
)

runTlsReinstallRollbackRegression() (
    local root="${TMP_DIR}/tls-reinstall-rollback"
    local tlsDir="${root}/tls"
    local homeDir="${root}/home"
    local statusLog="${root}/status.log"
    local errorLog="${root}/error.log"
    local cleanLog="${root}/clean.log"
    local oldHome="${HOME}"
    local oldTlsDir="${PADM_TLS_DIR:-}"
    local oldCurrentHost="${currentHost:-}"
    local oldDomain="${domain:-}"
    local oldTlsDomain="${tlsDomain:-}"
    local oldInstalledDNSAPIStatus="${installedDNSAPIStatus:-}"
    local oldLastInstallationConfig="${lastInstallationConfig:-}"
    local oldInstallTLSCount="${installTLSCount:-}"
    local oldSslType="${sslType:-}"
    local oldDnsAPIType="${dnsAPIType:-}"
    local oldDnsAPIStatus="${dnsAPIStatus:-}"
    local shellRc answer inputFd nextInput
    local acmeInstallFailure=true
    local acmeInstallTransient=false acmeInstallAttempts=0

    mkdir -p "${tlsDir}" "${homeDir}/.acme.sh/reinstall.example.com_ecc"
    printf 'old-cert\n' >"${tlsDir}/reinstall.example.com.crt"
    printf 'old-key\n' >"${tlsDir}/reinstall.example.com.key"
    printf 'other-cert\n' >"${tlsDir}/other.example.com.crt"
    printf 'other-key\n' >"${tlsDir}/other.example.com.key"
    printf 'letsencrypt\n' >"${tlsDir}/ssl_type"
    printf 'acme-cert\n' >"${homeDir}/.acme.sh/reinstall.example.com_ecc/reinstall.example.com.cer"
    printf 'acme-key\n' >"${homeDir}/.acme.sh/reinstall.example.com_ecc/reinstall.example.com.key"
    printf '#!/usr/bin/env sh\n' >"${homeDir}/.acme.sh/acme.sh"
    chmod 755 "${homeDir}/.acme.sh/acme.sh"
    : >"${statusLog}"
    : >"${errorLog}"
    : >"${cleanLog}"

    HOME="${homeDir}"
    PADM_TLS_DIR="${tlsDir}"
    currentHost=
    domain=reinstall.example.com
    tlsDomain=
    installedDNSAPIStatus=
    lastInstallationConfig=
    installTLSCount=
    sslType=letsencrypt
    dnsAPIType=
    dnsAPIStatus=
    unset AUTO_INSTALL
    export REGRESSION_STATUS_CARD_LOG="${statusLog}"
    export REGRESSION_ERROR_CARD_LOG="${errorLog}"

    statusCard() { printf '%s\n' "$*" >>"${statusLog}"; }
    successCard() { printf '%s\n' "$*" >>"${statusLog}"; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    # 文本证书夹具仅验证回滚；有效期检查由真实 OpenSSL 证书场景覆盖。
    tlsCertificatePairUsable() { return 0; }
    openssl() { return 0; }
    renewalTLS() {
        printf 'renew\n' >>"${cleanLog}"
        return 37
    }
    allowPort() { return 0; }
    switchDNSAPI() { return 0; }
    switchSSLType() { return 0; }
    customSSLEmail() { return 0; }
    cleanDirectoryContent() {
        printf 'clean:%s\n' "$1" >>"${cleanLog}"
        return 1
    }
    selectAcmeInstallSSL() { return 0; }
    sudo() {
        acmeInstallAttempts=$((acmeInstallAttempts + 1))
        printf 'sudo:%s\n' "$*" >>"${cleanLog}"
        printf 'acme-cert\n' >"${PADM_TLS_DIR}/reinstall.example.com.crt"
        printf 'acme-key\n' >"${PADM_TLS_DIR}/reinstall.example.com.key"
        [[ "${acmeInstallTransient}" != true || "${acmeInstallAttempts}" != 1 ]] || return 1
        [[ "${acmeInstallFailure}" != "true" ]]
    }

    set +e
    (
        set +e
        installTLS 1 <<<y >/dev/null 2>&1
        printf '%s\n' "$?" >"${root}/install.rc"
    )
    shellRc=$?
    set -e
    [[ "${shellRc}" == "0" ]]
    [[ "$(<"${root}/install.rc")" == "1" ]]
    ! grep -q '^clean:' "${cleanLog}"
    grep -q '^sudo:.*--installcert -d reinstall.example.com' "${cleanLog}"
    [[ "$(<"${tlsDir}/reinstall.example.com.crt")" == "old-cert" ]]
    [[ "$(<"${tlsDir}/reinstall.example.com.key")" == "old-key" ]]
    [[ "$(<"${tlsDir}/other.example.com.crt")" == "other-cert" ]]
    [[ "$(<"${tlsDir}/other.example.com.key")" == "other-key" ]]
    [[ "$(<"${tlsDir}/ssl_type")" == "letsencrypt" ]]
    grep -q 'TLS安装失败' "${errorLog}"
    ! grep -q 'TLS生成成功' "${statusLog}"

    # 未完成输入不能先续签；回车或 n 保留证书，不消费上级菜单输入。
    for answer in "" y yes; do
        : >"${cleanLog}"
        regressionExpectStatus 1 installTLS 1 < <(printf '%s' "${answer}")
        [[ ! -s "${cleanLog}" ]]
    done
    for answer in "" n; do
        : >"${cleanLog}"
        exec {inputFd}< <(printf '%s\nnext-parent-action\n' "${answer}")
        installTLS 1 <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ "${nextInput}" == next-parent-action && ! -s "${cleanLog}" ]]
        exec {inputFd}<&-
        [[ "$(<"${tlsDir}/reinstall.example.com.crt")" == "old-cert" ]]
    done

    acmeInstallFailure=false
    for answer in y Y yes YES true 1; do
        : >"${cleanLog}"
        installTLS 1 <<<"${answer}"
        [[ "$(<"${tlsDir}/reinstall.example.com.crt")" == "acme-cert" ]]
        [[ "$(<"${tlsDir}/reinstall.example.com.key")" == "acme-key" ]]
        [[ "$(<"${tlsDir}/other.example.com.crt")" == "other-cert" ]]
        [[ "$(<"${tlsDir}/other.example.com.key")" == "other-key" ]]
        [[ "$(<"${tlsDir}/ssl_type")" == "letsencrypt" ]]
        ! grep -q '^clean:' "${cleanLog}"
        ! grep -q '^renew$' "${cleanLog}"
        [[ "$(grep -c '^sudo:' "${cleanLog}")" == 1 ]]
    done
    (
        # 明确重装不先续签；单次重试状态不受历史失败影响，也不能重复报告成功。
        installTLSCount=1
        acmeInstallTransient=true
        acmeInstallAttempts=0
        renewalTLS() { printf 'renew\n' >>"${cleanLog}"; return 37; }
        : >"${cleanLog}"
        : >"${statusLog}"
        installTLS 1 <<<y
        [[ "${acmeInstallAttempts}" == 2 && "${installTLSCount}" == 1 ]]
        ! grep -q '^renew$' "${cleanLog}"
        [[ "$(grep -c '^TLS生成成功$' "${statusLog}")" == 1 ]]
    )
    (
        # 完整重装保留证书，不再重问；独立安装仍沿用上面的确认合同。
        local PADM_CORE_SWITCH_TRANSACTION_ACTIVE=true lastInstallationConfig=
        : >"${cleanLog}"
        exec {inputFd}< <(printf 'next-parent-action\n')
        installTLS 1 <&"${inputFd}"
        [[ ! -s "${cleanLog}" ]]
        read -r -u "${inputFd}" nextInput
        [[ "${nextInput}" == next-parent-action ]]
        exec {inputFd}<&-
    )
    : >"${cleanLog}"
    lastInstallationConfig=true
    reInstallStatus=y
    installTLS 1 </dev/null
    [[ ! -s "${cleanLog}" ]]

    if [[ -n "${oldTlsDir}" ]]; then
        PADM_TLS_DIR="${oldTlsDir}"
    else
        unset PADM_TLS_DIR
    fi
    HOME="${oldHome}"
    currentHost="${oldCurrentHost}"
    domain="${oldDomain}"
    tlsDomain="${oldTlsDomain}"
    installedDNSAPIStatus="${oldInstalledDNSAPIStatus}"
    lastInstallationConfig="${oldLastInstallationConfig}"
    installTLSCount="${oldInstallTLSCount}"
    sslType="${oldSslType}"
    dnsAPIType="${oldDnsAPIType}"
    dnsAPIStatus="${oldDnsAPIStatus}"
)
