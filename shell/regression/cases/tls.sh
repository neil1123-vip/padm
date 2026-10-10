#!/usr/bin/env bash

runTlsFailureReturnRegression() (
    # 这些夹具验证同步和错误传播；真实子进程取消由信号回归覆盖。
    padmRunCancelableCommand() { "$@"; }
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
            [[ "$(<"${accountFile}")" == "${before}" && "${sslEmail}" == previous@example.com ]]
        done
        # 邮箱原地纠错，确认大小写/yes 通用；取消或写入失败不缓存无效邮箱。
        exec {inputFd}< <(printf 'YES\nbad-email\n\nnew@example.com\nnext-parent-action\n')
        customSSLEmail "validate email" <&"${inputFd}"
        grep -Fxq "ACCOUNT_EMAIL='new@example.com'" "${accountFile}"
        read -r -u "${inputFd}" remaining
        [[ "${remaining}" == next-parent-action && "${sslEmail}" == new@example.com ]]
        exec {inputFd}<&-
        before=$(<"${accountFile}")
        regressionExpectStatus 1 customSSLEmail "validate email" < <(printf 'y\nbad-email\n')
        [[ "$(<"${accountFile}")" == "${before}" && "${sslEmail}" == new@example.com ]]
        (
            commitGeneratedFile() { return 1; }
            regressionExpectStatus 1 customSSLEmail "validate email" < <(printf 'y\nanother@example.com\n')
            [[ "$(<"${accountFile}")" == "${before}" && "${sslEmail}" == new@example.com ]]
        )
        (
            local AUTO_INSTALL=true
            autoRead() {
                case "$1" in
                tls_email_retry) printf -v "$3" '%s' y ;;
                *) printf -v "$3" '%s' bad-email ;;
                esac
            }
            regressionExpectStatus 1 customSSLEmail "validate email" </dev/null
            [[ "$(<"${accountFile}")" == "${before}" && "${sslEmail}" == new@example.com ]]
        )
    )

    dnsTLSDomain=example
    (
        local AUTO_INSTALL=true
        captureFailureReturn "${dnsRcFile}" initDNSAPIConfig cloudflare
    )

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
        # 通配符选择原地纠错，不重读凭据；取消仍不提交半份配置。
        unset dnsAPIStatus dnsAPIType cfAPIToken cfZoneID
        exec {inputFd}< <(printf 'y\n\ntoken\n\ny\nn\nnext-action\n')
        switchDNSAPI <&"${inputFd}"
        [[ "${dnsAPIType}" == cloudflare && "${dnsAPIStatus}" == n &&
            "${cfAPIToken}" == token && -z "${cfZoneID}" ]]
        read -r -u "${inputFd}" remaining
        [[ "${remaining}" == next-action ]]
        exec {inputFd}<&-
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
        local lastInstallationConfig= ipType=4 sslIPv6=
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
            [[ "$1" == stop && "${sslType}" == zerossl && "${sslEmail}" == new@example.com ]] || return 1
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
            [[ "$(<"${accountFile}")" == "${before}" ]]
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
        read -r -u "${inputFd}" remaining
        [[ "${remaining}" == next-parent-action ]]
        exec {inputFd}<&-
    )

    domain=missing.example.com
    currentHost=
    installedDNSAPIStatus=
    captureFailureReturn "${installRcFile}" installTLS 1

    local existingTlsRoot="${root}/existing-tls"
    mkdir -p "${existingTlsRoot}"
    export PADM_TLS_DIR="${existingTlsRoot}"
    domain=existing.example.com
    printf 'old-cert\n' >"${existingTlsRoot}/existing.example.com.crt"
    printf 'old-key\n' >"${existingTlsRoot}/existing.example.com.key"
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
        # 同父域源共存时同步当前域名证书；显式签发通配符仍使用本次签发方式。
        local HOME="${root}/source-selection/home" PADM_TLS_DIR="${root}/source-selection/tls"
        local domain=secure.example.com currentHost=stale.example.net sourceDomain= snapshot
        local exactDir="${HOME}/.acme.sh/${domain}_ecc" wildcardDir="${HOME}/.acme.sh/*.example.com_ecc"
        local staleWildcardDir="${HOME}/.acme.sh/*.example.net_ecc"
        mkdir -p "${exactDir}" "${wildcardDir}" "${staleWildcardDir}" "${PADM_TLS_DIR}"
        cp "${secureTlsRoot}/new.crt" "${exactDir}/${domain}.cer"
        cp "${secureTlsRoot}/new.key" "${exactDir}/${domain}.key"
        printf 'invalid-old-cert\n' >"${wildcardDir}/*.example.com.cer"
        printf 'invalid-old-key\n' >"${wildcardDir}/*.example.com.key"
        printf 'stale-wildcard-cert\n' >"${staleWildcardDir}/*.example.net.cer"
        printf 'stale-wildcard-key\n' >"${staleWildcardDir}/*.example.net.key"
        acmeExecutable() { printf '/bin/true\n'; }
        sudo() {
            [[ "$2" == --installcert ]] || return 0
            sourceDomain=$4
            cp "${exactDir}/${domain}.cer" "${PADM_TLS_DIR}/${domain}.crt"
            cp "${exactDir}/${domain}.key" "${PADM_TLS_DIR}/${domain}.key"
        }
        readAcmeTLS
        [[ -z "${installedDNSAPIStatus}" && "${dnsTLSDomain}" == example.com ]]
        installTLSFromAcme >/dev/null 2>&1
        [[ "${sourceDomain}" == "${domain}" ]]
        acmeInstallSSL() { return 0; }
        local ipType=4 dnsAPIType=cloudflare dnsAPIStatus=y
        selectAcmeInstallSSL
        [[ "${installedDNSAPIStatus}" == true ]]
        dnsAPIStatus=n
        selectAcmeInstallSSL
        [[ -z "${installedDNSAPIStatus}" ]]
        # 状态域名回退后重新查源，不得沿用全局旧域名的通配符状态。
        currentHost=missing.example.net domain=missing.example.net
        crontab() { return 1; }
        snapshot=$(tlsCertificateStatusJson)
        jq -e '.domain == "secure.example.com" and .source == "acme-standalone"' <<<"${snapshot}" >/dev/null
        (
            local sslRenewalDays=90
            stat() {
                if [[ "$1" == --format=%z ]]; then
                    date -d '89 days ago' '+%F %T.000000000 %z'
                else
                    command stat "$@"
                fi
            }
            nginxRunning() { return 1; }
            xrayRunning() { return 1; }
            singBoxRunning() { return 1; }
            sourceDomain=
            renewalTLS >/dev/null 2>&1
            [[ "${sourceDomain}" == secure.example.com && -z "${installedDNSAPIStatus}" ]]
        )
        rm -f "${exactDir}/secure.example.com.cer"
        readAcmeTLS secure.example.com
        [[ "${installedDNSAPIStatus}" == true && "${dnsTLSDomain}" == example.com ]]
        : >"${wildcardDir}/*.example.com.cer"
        readAcmeTLS secure.example.com
        [[ -z "${installedDNSAPIStatus}" ]]
    )

    (
        # 同步失败恢复每个文件的原始存在状态，首次安装也不能留下半份证书。
        local domain=partial.example.com state failure attempts
        local crtFile="${PADM_TLS_DIR}/${domain}.crt" keyFile="${PADM_TLS_DIR}/${domain}.key"
        local beforeCrt beforeKey
        sudo() {
            attempts=$((attempts + 1))
            printf 'broken-cert\n' >"${crtFile}"
            [[ "${failure}" != partial ]] || return 1
            cp "${secureTlsRoot}/new.key" "${keyFile}"
            [[ "${failure}" == invalid ]]
        }
        for state in missing cert key empty pair; do
            for failure in partial command invalid; do
                rm -f -- "${crtFile}" "${keyFile}"
                case "${state}" in
                cert | pair) printf 'saved-cert\n' >"${crtFile}" ;;
                empty) : >"${crtFile}" ;;
                esac
                case "${state}" in
                key | pair) printf 'saved-key\n' >"${keyFile}" ;;
                empty) : >"${keyFile}" ;;
                esac
                beforeCrt=missing beforeKey=missing
                [[ ! -f "${crtFile}" ]] || beforeCrt=$(sha256sum "${crtFile}")
                [[ ! -f "${keyFile}" ]] || beforeKey=$(sha256sum "${keyFile}")
                attempts=0
                regressionExpectStatus 1 installTLSFromAcme >/dev/null 2>&1
                [[ "${attempts}" == 2 ]]
                if [[ "${beforeCrt}" == missing ]]; then
                    [[ ! -e "${crtFile}" ]]
                else
                    [[ "$(sha256sum "${crtFile}")" == "${beforeCrt}" ]]
                fi
                if [[ "${beforeKey}" == missing ]]; then
                    [[ ! -e "${keyFile}" ]]
                else
                    [[ "$(sha256sum "${keyFile}")" == "${beforeKey}" &&
                        "$(stat -c %a "${keyFile}")" == 600 ]]
                fi
            done
        done
        (
            # 证书目标损坏也必须恢复可写的私钥，并保留证书备份供手工恢复。
            local TMPDIR="${root}/failed-cert-restore-tmp" savedBackupDir= attempts=0
            local -a PADM_CLEANUP_PATHS=("${PADM_CLEANUP_PATHS[@]}")
            mkdir -p -- "${TMPDIR}"
            printf 'saved-cert\n' >"${crtFile}"
            printf 'saved-key\n' >"${keyFile}"
            sudo() {
                attempts=$((attempts + 1))
                rm -f -- "${crtFile}"
                mkdir -- "${crtFile}"
                printf 'broken-key\n' >"${keyFile}"
                return 1
            }
            regressionExpectStatus 1 installTLSFromAcme >/dev/null 2>&1
            [[ "${attempts}" == 1 && -d "${crtFile}" &&
                "$(<"${keyFile}")" == saved-key && "$(stat -c %a "${keyFile}")" == 600 ]]
            savedBackupDir=$(find "${TMPDIR}" -maxdepth 2 -type f -name "${domain}.crt" -printf '%h\n')
            [[ -n "${savedBackupDir}" && "$(<"${savedBackupDir}/${domain}.crt")" == saved-cert &&
                "$(<"${savedBackupDir}/${domain}.key")" == saved-key ]]
            rmdir -- "${crtFile}"
            padmRemoveCleanupPath "${savedBackupDir}"
        )
    )

    (
        acmeInstallSSL() { return 1; }
        readAcmeTLS() { return 0; }
        captureFailureReturn "${root}/select-acme.rc" selectAcmeInstallSSL
    )

    (
        # 邮箱纠错必须重新签发一次，其他错误和用户取消不能重试或读取半份证书。
        local PADM_TLS_DIR="${root}/issue-retry" tlsDomain=retry.example.com sslType=zerossl
        local ipType=4 dnsAPIType= dnsAPIStatus=n installedDNSAPIStatus=saved
        local issueLog="${root}/issue-retry.calls" issueMode attempts corrections reads
        mkdir -p "${PADM_TLS_DIR}"
        acmeExecutable() { printf '/bin/false\n'; }
        allowPort() { return 0; }
        handleNginx() { return 0; }
        sudo() {
            [[ "$2" == --issue ]] || return 1
            printf 'issue\n' >>"${issueLog}"
            if [[ "${issueMode}" == other ]]; then
                printf 'unrelated issuance error\n'
            elif [[ "${issueMode}" != success || "$(wc -l <"${issueLog}")" == 1 ]]; then
                printf 'Could not validate email address as valid\n'
            else
                return 0
            fi
            return 1
        }
        customSSLEmail() {
            [[ "$1" == "validate email" ]] || return 1
            corrections=$((corrections + 1))
            [[ "${issueMode}" != cancel ]]
        }
        readAcmeTLS() { reads=$((reads + 1)); }
        for issueMode in success repeated cancel other; do
            : >"${issueLog}"
            printf 'Could not validate email address as valid\n' >"$(tlsAcmeLogFile)"
            corrections=0 reads=0 installedDNSAPIStatus=saved
            if [[ "${issueMode}" == success ]]; then
                selectAcmeInstallSSL
                [[ "${reads}" == 1 && -z "${installedDNSAPIStatus}" ]]
            else
                regressionExpectStatus 1 selectAcmeInstallSSL
                [[ "${reads}" == 0 && "${installedDNSAPIStatus}" == saved ]]
            fi
            attempts=$(wc -l <"${issueLog}")
            case "${issueMode}" in
            success | repeated) [[ "${attempts}" == 2 && "${corrections}" == 1 ]] ;;
            cancel) [[ "${attempts}" == 1 && "${corrections}" == 1 ]] ;;
            other) [[ "${attempts}" == 1 && "${corrections}" == 0 ]] ;;
            esac
        done
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
        tlsAcmeSourceCertificateReusable() { return 0; }
        tlsCertificatePairUsable() { return 0; }
        installTLS 1 >/dev/null 2>&1
        [[ "${acmeInstallFromHomeCalled}" == "true" ]]
    )

    (
        # 源证书为空或缺失时重新签发，完整源只同步，不能反复安装半份文件。
        local HOME="${root}/incomplete-source/home" PADM_TLS_DIR="${root}/incomplete-source/tls"
        local domain=incomplete.example.com currentHost=incomplete.example.com tlsDomain=incomplete.example.com
        local sourceDir="${HOME}/.acme.sh/${domain}_ecc" state issues syncs snapshot
        local installedDNSAPIStatus= dnsAPIType= dnsAPIStatus=n sslType=letsencrypt
        unset PADM_REQUIRE_USABLE_TLS_CERTIFICATE
        mkdir -p "${sourceDir}" "${PADM_TLS_DIR}"
        switchSSLType() { return 0; }
        customSSLEmail() { return 0; }
        selectAcmeInstallSSL() { issues=$((issues + 1)); }
        installTLSFromAcme() { syncs=$((syncs + 1)); }
        tlsAcmeSourceCertificateReusable() { [[ "${state}" == complete ]]; }
        tlsCertificatePairUsable() { return 0; }
        crontab() { return 1; }
        sudo() { return 99; }
        for state in complete empty-cert empty-key cert-only key-only; do
            rm -f -- "${PADM_TLS_DIR}/${domain}.crt" "${PADM_TLS_DIR}/${domain}.key"
            rm -f -- "${sourceDir}/${domain}.cer" "${sourceDir}/${domain}.key"
            case "${state}" in
            complete | empty-key | cert-only) printf 'cert\n' >"${sourceDir}/${domain}.cer" ;;
            empty-cert) : >"${sourceDir}/${domain}.cer" ;;
            esac
            case "${state}" in
            complete | empty-cert | key-only) printf 'key\n' >"${sourceDir}/${domain}.key" ;;
            empty-key) : >"${sourceDir}/${domain}.key" ;;
            esac
            issues=0 syncs=0
            installTLS 1 >/dev/null 2>&1
            [[ "${syncs}" == 1 ]]
            if [[ "${state}" == complete ]]; then
                [[ "${issues}" == 0 ]]
            else
                [[ "${issues}" == 1 ]]
            fi
            printf 'local-cert\n' >"${PADM_TLS_DIR}/${domain}.crt"
            printf 'local-key\n' >"${PADM_TLS_DIR}/${domain}.key"
            snapshot=$(tlsCertificateStatusJson)
            if [[ "${state}" == complete ]]; then
                jq -e '.source == "acme-standalone"' <<<"${snapshot}" >/dev/null
            else
                jq -e '.source == "custom"' <<<"${snapshot}" >/dev/null
                regressionExpectStatus 0 renewalTLS >/dev/null 2>&1
            fi
        done
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
            -subj "/CN=${certDomain}" -addext "subjectAltName=DNS:${certDomain},DNS:*.custom.example.com" \
            -keyout "${certificateRoot}/valid.key" -out "${certificateRoot}/valid.crt" >/dev/null 2>&1
        openssl req -new -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
            -subj "/CN=${certDomain}" -addext "subjectAltName=DNS:${certDomain},DNS:*.custom.example.com" \
            -keyout "${certificateRoot}/expiring.key" -out "${certificateRoot}/expiring.crt" >/dev/null 2>&1
        openssl req -new -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
            -subj "/CN=wrong.example.com" -addext "subjectAltName=DNS:wrong.example.com" \
            -keyout "${certificateRoot}/wrong.key" -out "${certificateRoot}/wrong.crt" >/dev/null 2>&1

        (
            # 普通安装和严格修复均只复用有效源；坏源和显式参数回到同一申请流程。
            local PADM_REQUIRE_USABLE_TLS_CERTIFICATE= dnsAPIStatus
            local AUTO_TLS_CA= AUTO_DNS_API= AUTO_DNS_API_TYPE= AUTO_DNS_API_WILDCARD=
            local sourceDir="${HOME}/.acme.sh/${certDomain}_ecc"
            local state certificateMode issues syncs dnsSelections inputFd nextInput
            mkdir -p "${sourceDir}"
            switchDNSAPI() { dnsSelections=$((dnsSelections + 1)); dnsAPIStatus=n; }
            switchSSLType() { [[ "${state}" != cancel ]]; }
            customSSLEmail() { return 0; }
            selectAcmeInstallSSL() {
                issues=$((issues + 1))
                cp "${certificateRoot}/valid.crt" "${sourceDir}/${certDomain}.cer"
                cp "${certificateRoot}/valid.key" "${sourceDir}/${certDomain}.key"
            }
            installTLSFromAcme() {
                syncs=$((syncs + 1))
                [[ "${state}" != sync-fail ]] || return 1
                cp "${sourceDir}/${certDomain}.cer" "${PADM_TLS_DIR}/${certDomain}.crt"
                cp "${sourceDir}/${certDomain}.key" "${PADM_TLS_DIR}/${certDomain}.key"
            }
            for certificateMode in ordinary strict; do
                PADM_REQUIRE_USABLE_TLS_CERTIFICATE=
                [[ "${certificateMode}" != strict ]] || PADM_REQUIRE_USABLE_TLS_CERTIFICATE=true
            for state in valid expiring wrong-domain wrong-key invalid-pem ca dns provider wildcard sync-fail cancel; do
                rm -f "${PADM_TLS_DIR}/${certDomain}.crt" "${PADM_TLS_DIR}/${certDomain}.key"
                cp "${certificateRoot}/valid.crt" "${sourceDir}/${certDomain}.cer"
                cp "${certificateRoot}/valid.key" "${sourceDir}/${certDomain}.key"
                AUTO_TLS_CA= AUTO_DNS_API= AUTO_DNS_API_TYPE= AUTO_DNS_API_WILDCARD=
                issues=0 syncs=0 dnsSelections=0
                unset dnsAPIStatus
                case "${state}" in
                expiring) cp "${certificateRoot}/expiring.crt" "${sourceDir}/${certDomain}.cer" ;;
                wrong-domain) cp "${certificateRoot}/wrong.crt" "${sourceDir}/${certDomain}.cer" ;;
                wrong-key) cp "${certificateRoot}/wrong.key" "${sourceDir}/${certDomain}.key" ;;
                invalid-pem) printf 'invalid-pem\n' >"${sourceDir}/${certDomain}.cer" ;;
                ca) AUTO_TLS_CA=letsencrypt ;;
                dns) AUTO_DNS_API=n ;;
                provider) AUTO_DNS_API_TYPE=cloudflare ;;
                wildcard) AUTO_DNS_API_WILDCARD=n ;;
                cancel) printf 'invalid-pem\n' >"${sourceDir}/${certDomain}.cer" ;;
                esac
                exec {inputFd}< <(printf 'next-parent-action\n')
                if [[ "${state}" == cancel ]]; then
                    regressionExpectStatus 1 installTLS 1 <&"${inputFd}" >/dev/null 2>&1
                    [[ "${issues}" == 0 && "${syncs}" == 0 ]]
                elif [[ "${state}" == sync-fail ]]; then
                    regressionExpectStatus 1 installTLS 1 <&"${inputFd}" >/dev/null 2>&1
                    [[ "${issues}" == 0 && "${syncs}" == 1 ]]
                else
                    installTLS 1 <&"${inputFd}" >/dev/null 2>&1
                    [[ "${syncs}" == 1 ]]
                    if [[ "${state}" == valid ]]; then
                        [[ "${issues}" == 0 ]]
                    else
                        [[ "${issues}" == 1 ]]
                    fi
                    tlsCertificatePairUsable "${PADM_TLS_DIR}" "${certDomain}"
                fi
                read -r -u "${inputFd}" nextInput
                exec {inputFd}<&-
                [[ "${nextInput}" == next-parent-action ]]
                if [[ "${state}" == valid || "${state}" == sync-fail ]]; then
                    [[ "${dnsSelections}" == 0 ]]
                else
                    [[ "${dnsSelections}" == 1 ]]
                fi
            done
            done
            local certDomain=api.custom.example.com domain=api.custom.example.com
            local installedDNSAPIStatus=true dnsTLSDomain=custom.example.com
            sourceDir="${HOME}/.acme.sh/*.custom.example.com_ecc"
            mkdir -p "${sourceDir}"
            cp "${certificateRoot}/valid.crt" "${sourceDir}/*.custom.example.com.cer"
            cp "${certificateRoot}/valid.key" "${sourceDir}/*.custom.example.com.key"
            installTLSFromAcme() {
                syncs=$((syncs + 1))
                cp "${sourceDir}/*.custom.example.com.cer" "${PADM_TLS_DIR}/${certDomain}.crt"
                cp "${sourceDir}/*.custom.example.com.key" "${PADM_TLS_DIR}/${certDomain}.key"
            }
            state=wildcard-source issues=0 syncs=0
            installTLS 1 >/dev/null 2>&1
            [[ "${issues}" == 0 && "${syncs}" == 1 ]]
            tlsCertificatePairUsable "${PADM_TLS_DIR}" "${certDomain}"
            # 坏通配符源重新选择 DNS API，不误入 HTTP-01。
            rm -f "${PADM_TLS_DIR}/${certDomain}.crt" "${PADM_TLS_DIR}/${certDomain}.key"
            printf 'invalid-pem\n' >"${sourceDir}/*.custom.example.com.cer"
            PADM_REQUIRE_USABLE_TLS_CERTIFICATE= issues=0 syncs=0 dnsSelections=0
            unset dnsAPIStatus
            switchDNSAPI() { dnsSelections=$((dnsSelections + 1)); dnsAPIStatus=y; dnsAPIType=cloudflare; }
            selectAcmeInstallSSL() {
                [[ "${dnsAPIStatus}" == y && "${dnsAPIType}" == cloudflare ]]
                issues=$((issues + 1))
                cp "${certificateRoot}/valid.crt" "${sourceDir}/*.custom.example.com.cer"
                cp "${certificateRoot}/valid.key" "${sourceDir}/*.custom.example.com.key"
            }
            installTLS 1 >/dev/null 2>&1
            [[ "${issues}" == 1 && "${syncs}" == 1 && "${dnsSelections}" == 1 ]]
            tlsCertificatePairUsable "${PADM_TLS_DIR}" "${certDomain}"
        )

        (
            # 坏单域名源不能遮蔽有效通配符；好单域名仍优先，显式参数仍重新签发。
            # shellcheck source=/dev/null
            source "${PROJECT_ROOT}/shell/core/state.sh"
            local certDomain=api.custom.example.com domain=api.custom.example.com
            local exactDir="${HOME}/.acme.sh/${certDomain}_ecc"
            local wildcardDir="${HOME}/.acme.sh/*.custom.example.com_ecc"
            local sourceMode certificateMode issues syncs dnsSelections syncDomain selectedDir
            local inputFd nextInput
            local AUTO_TLS_CA= AUTO_DNS_API= AUTO_DNS_API_TYPE= AUTO_DNS_API_WILDCARD=
            mkdir -p "${exactDir}" "${wildcardDir}"
            cp "${certificateRoot}/valid.crt" "${wildcardDir}/*.custom.example.com.cer"
            cp "${certificateRoot}/valid.key" "${wildcardDir}/*.custom.example.com.key"
            acmeExecutable() { printf '/bin/true\n'; }
            switchDNSAPI() { dnsSelections=$((dnsSelections + 1)); dnsAPIStatus=n; }
            switchSSLType() { return 0; }
            customSSLEmail() { return 0; }
            selectAcmeInstallSSL() {
                issues=$((issues + 1))
                installedDNSAPIStatus=
                cp "${certificateRoot}/valid.crt" "${exactDir}/${certDomain}.cer"
                cp "${certificateRoot}/valid.key" "${exactDir}/${certDomain}.key"
            }
            sudo() {
                [[ "$2" == --installcert ]] || return 1
                syncs=$((syncs + 1))
                syncDomain=$4
                selectedDir="${HOME}/.acme.sh/${syncDomain}_ecc"
                cp "${selectedDir}/${syncDomain}.cer" "${PADM_TLS_DIR}/${certDomain}.crt"
                cp "${selectedDir}/${syncDomain}.key" "${PADM_TLS_DIR}/${certDomain}.key"
            }
            crontab() { return 1; }
            for certificateMode in ordinary strict; do
                local PADM_REQUIRE_USABLE_TLS_CERTIFICATE=
                [[ "${certificateMode}" != strict ]] || PADM_REQUIRE_USABLE_TLS_CERTIFICATE=true
                for sourceMode in invalid-pem expiring wrong-domain wrong-key valid ca dns provider wildcard; do
                    rm -f "${PADM_TLS_DIR}/${certDomain}.crt" "${PADM_TLS_DIR}/${certDomain}.key"
                    cp "${certificateRoot}/valid.crt" "${exactDir}/${certDomain}.cer"
                    cp "${certificateRoot}/valid.key" "${exactDir}/${certDomain}.key"
                    AUTO_TLS_CA= AUTO_DNS_API= AUTO_DNS_API_TYPE= AUTO_DNS_API_WILDCARD=
                    issues=0 syncs=0 dnsSelections=0 syncDomain=
                    unset dnsAPIStatus dnsAPIType
                    case "${sourceMode}" in
                    invalid-pem) printf 'invalid-pem\n' >"${exactDir}/${certDomain}.cer" ;;
                    expiring) cp "${certificateRoot}/expiring.crt" "${exactDir}/${certDomain}.cer" ;;
                    wrong-domain) cp "${certificateRoot}/wrong.crt" "${exactDir}/${certDomain}.cer" ;;
                    wrong-key) cp "${certificateRoot}/wrong.key" "${exactDir}/${certDomain}.key" ;;
                    ca) AUTO_TLS_CA=letsencrypt ;;
                    dns) AUTO_DNS_API=n ;;
                    provider) AUTO_DNS_API_TYPE=cloudflare ;;
                    wildcard) AUTO_DNS_API_WILDCARD=n ;;
                    esac
                    installTLS 1 >/dev/null 2>&1
                    [[ "${syncs}" == 1 ]]
                    case "${sourceMode}" in
                    valid)
                        [[ "${issues}" == 0 && "${dnsSelections}" == 0 && "${syncDomain}" == "${certDomain}" ]]
                        ;;
                    ca | dns | provider | wildcard)
                        [[ "${issues}" == 1 && "${dnsSelections}" == 1 && "${syncDomain}" == "${certDomain}" ]]
                        ;;
                    *)
                        [[ "${issues}" == 0 && "${dnsSelections}" == 0 && "${syncDomain}" == '*.custom.example.com' ]]
                        ;;
                    esac
                    tlsCertificatePairUsable "${PADM_TLS_DIR}" "${certDomain}"
                done
            done
            # 明确同步也选择有效通配符源，不重签、不消费父菜单输入。
            menuReadChoice() { printf -v "$3" '%s' y; }
            for certificateMode in ordinary strict; do
                local PADM_REQUIRE_USABLE_TLS_CERTIFICATE= lastInstallationConfig= PADM_CORE_SWITCH_TRANSACTION_ACTIVE=
                [[ "${certificateMode}" != strict ]] || PADM_REQUIRE_USABLE_TLS_CERTIFICATE=true
                cp "${certificateRoot}/valid.crt" "${wildcardDir}/*.custom.example.com.cer"
                cp "${certificateRoot}/valid.key" "${wildcardDir}/*.custom.example.com.key"
                printf 'invalid-pem\n' >"${exactDir}/${certDomain}.cer"
                cp "${certificateRoot}/valid.key" "${exactDir}/${certDomain}.key"
                cp "${certificateRoot}/valid.crt" "${PADM_TLS_DIR}/${certDomain}.crt"
                cp "${certificateRoot}/valid.key" "${PADM_TLS_DIR}/${certDomain}.key"
                AUTO_TLS_CA= AUTO_DNS_API= AUTO_DNS_API_TYPE= AUTO_DNS_API_WILDCARD=
                issues=0 syncs=0 dnsSelections=0 syncDomain=
                exec {inputFd}< <(printf 'next-parent-action\n')
                installTLS 1 <&"${inputFd}" >/dev/null 2>&1
                read -r -u "${inputFd}" nextInput
                exec {inputFd}<&-
                [[ "${nextInput}" == next-parent-action && "${syncs}" == 1 &&
                    "${syncDomain}" == '*.custom.example.com' && "${issues}" == 0 && "${dnsSelections}" == 0 ]]
                tlsCertificatePairUsable "${PADM_TLS_DIR}" "${certDomain}"
            done
            rm -f "${exactDir}/${certDomain}.cer" "${exactDir}/${certDomain}.key"
        )

        (
            # 订阅丢失本机文件时直接同步有效 ACME 源，不询问签发、不检查 DNS/80。
            # shellcheck source=/dev/null
            source "${PROJECT_ROOT}/shell/core/state.sh"
            local sourceDir acmeDomain mode nextInput inputFd
            local callsFile="${certificateRoot}/subscribe-source.calls"
            local AUTO_TLS_CA= AUTO_DNS_API= AUTO_DNS_API_TYPE= AUTO_DNS_API_WILDCARD= AUTO_DOMAIN=
            local AUTO_INSTALL= cronName= syncFails=false
            autoRead() { printf 'prompt\n' >>"${callsFile}"; return 1; }
            switchDNSAPI() { printf 'dns\n' >>"${callsFile}"; return 1; }
            subscriptionInstallTLSHttp01() { printf 'http01\n' >>"${callsFile}"; return 1; }
            installAcmeTool() { printf 'acme\n' >>"${callsFile}"; }
            installCronTLS() { printf 'cron\n' >>"${callsFile}"; }
            installTLSFromAcme() {
                printf 'sync\n' >>"${callsFile}"
                [[ "${syncFails}" != true ]] || return 1
                cp "${sourceDir}/${acmeDomain}.cer" "${PADM_TLS_DIR}/${tlsDomain}.crt"
                cp "${sourceDir}/${acmeDomain}.key" "${PADM_TLS_DIR}/${tlsDomain}.key"
                printf "Le_RealFullChainPath='%s'\nLe_RealKeyPath='%s'\n" \
                    "${PADM_TLS_DIR}/${tlsDomain}.crt" "${PADM_TLS_DIR}/${tlsDomain}.key" >"${sourceDir}/${acmeDomain}.conf"
            }
            for acmeDomain in custom.example.com '*.custom.example.com'; do
                certDomain=custom.example.com
                [[ "${acmeDomain}" != '*.custom.example.com' ]] || certDomain=api.custom.example.com
                sourceDir="${HOME}/.acme.sh/${acmeDomain}_ecc"
                mkdir -p "${sourceDir}"
                cp "${certificateRoot}/valid.crt" "${sourceDir}/${acmeDomain}.cer"
                cp "${certificateRoot}/valid.key" "${sourceDir}/${acmeDomain}.key"
                for mode in interactive automatic cron; do
                    AUTO_INSTALL= cronName=
                    [[ "${mode}" != automatic ]] || AUTO_INSTALL=true
                    [[ "${mode}" != cron ]] || cronName=InstallSubscription
                    rm -f "${PADM_TLS_DIR}/${certDomain}.crt" "${PADM_TLS_DIR}/${certDomain}.key"
                    : >"${callsFile}"
                    exec {inputFd}< <(printf 'next-parent-action\n')
                    prepareSubscribeTLSCertificate "${certDomain}" <&"${inputFd}"
                    read -r -u "${inputFd}" nextInput
                    exec {inputFd}<&-
                    [[ "${nextInput}" == next-parent-action && "$(<"${callsFile}")" == $'acme\nsync\ncron' ]]
                    tlsCertificatePairUsable "${PADM_TLS_DIR}" "${certDomain}"
                    tlsCertificateManagedByAcme "${certDomain}"
                done
            done
            # 订阅自动修复也必须绕过坏单域名源，不要求重新提供签发参数。
            sourceDir="${HOME}/.acme.sh/${acmeDomain}_ecc"
            mkdir -p "${HOME}/.acme.sh/${certDomain}_ecc"
            printf 'invalid-pem\n' >"${HOME}/.acme.sh/${certDomain}_ecc/${certDomain}.cer"
            cp "${certificateRoot}/valid.key" "${HOME}/.acme.sh/${certDomain}_ecc/${certDomain}.key"
            rm -f "${PADM_TLS_DIR}/${certDomain}.crt" "${PADM_TLS_DIR}/${certDomain}.key"
            : >"${callsFile}"
            prepareSubscribeTLSCertificate "${certDomain}"
            [[ "$(<"${callsFile}")" == $'acme\nsync\ncron' ]]
            rm -f "${PADM_TLS_DIR}/${certDomain}.crt" "${PADM_TLS_DIR}/${certDomain}.key"
            syncFails=true
            : >"${callsFile}"
            regressionExpectStatus 1 prepareSubscribeTLSCertificate "${certDomain}"
            [[ "$(<"${callsFile}")" == $'acme\nsync' ]]
            syncFails=false AUTO_TLS_CA=letsencrypt
            : >"${callsFile}"
            regressionExpectStatus 1 prepareSubscribeTLSCertificate "${certDomain}"
            [[ ! -s "${callsFile}" ]]
        )

        # 自签证书可正常复用；错域名、错私钥和损坏 PEM 均不能冒充安装成功。
        rm -f "${HOME}/.acme.sh/${certDomain}_ecc/${certDomain}.cer" "${HOME}/.acme.sh/${certDomain}_ecc/${certDomain}.key"
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

    (
        # 签发成功后的续签任务阶段仍须在取消时恢复 Nginx 原运行态。
        local fixture="${root}/local-certificate-signal" signal wasRunning status
        local HOME="${fixture}/home" PADM_TLS_DIR="${fixture}/tls"
        local domain=signal.example.com currentHost= lastInstallationConfig=
        local AUTO_DOMAIN="${domain}" btDomain= sslType=letsencrypt installedDNSAPIStatus=
        mkdir -p "${HOME}/.acme.sh" "${PADM_TLS_DIR}"
        installAcmeTool() { return 0; }
        nginxRunning() { [[ "$(<"${fixture}/nginx.running")" == true ]]; }
        xrayRunning() { return 1; }
        singBoxRunning() { return 1; }
        handleNginx() {
            printf '%s\n' "$([[ "$1" == start ]] && printf true || printf false)" >"${fixture}/nginx.running"
        }
        readAcmeTLS() { :; }
        tlsCertificatePairExists() { return 1; }
        tlsAcmeSourceCertificateReusable() { return 1; }
        tlsCertificatePairUsable() { return 0; }
        switchDNSAPI() { dnsAPIStatus=n; dnsAPIType=; }
        switchSSLType() { :; }
        customSSLEmail() { :; }
        acmeExecutable() { printf '/bin/true\n'; }
        allowPort() { :; }
        sudo() { "$@"; }
        padmRunPortAllowTransaction() { "$@"; }
        installTLSFromAcme() { :; }
        singBoxLocalCertificateAvailable() { return 0; }
        installCronTLS() {
            [[ "$(<"${fixture}/nginx.running")" == false ]] || return 1
            kill -"${signal}" "${BASHPID}"
            :
        }
        for wasRunning in true false; do
            for signal in INT TERM; do
                printf '%s\n' "${wasRunning}" >"${fixture}/nginx.running"
                status=0
                ( singBoxInstallLocalTLSCertificate ) >/dev/null 2>&1 || status=$?
                [[ "${status}" == "$([[ "${signal}" == TERM ]] && printf 143 || printf 130)" ]] || return 1
                [[ "$(<"${fixture}/nginx.running")" == "${wasRunning}" ]] || return 1
            done
        done
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
    padmRunCancelableCommand() { "$@"; }
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
        printf 'nginx:%s\n' "$1" >>"${serviceLog}"
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
        printf 'xray:%s\n' "$1" >>"${serviceLog}"
        [[ "${mode}" == "xray-stop-fail" && "$1" == "stop" ]] && return 1
        [[ "${mode}" == "xray-start-fail" && "$1" == "start" ]] && return 1
        [[ "$1" == "start" ]] && xrayState=true || xrayState=false
        return 0
    }
    handleSingBox() {
        if [[ "$1" == "stop" && "${singBoxState}" != "true" ]] || [[ "$1" == "start" && "${singBoxState}" == "true" ]]; then
            return 0
        fi
        printf 'sing-box:%s\n' "$1" >>"${serviceLog}"
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

    (
        # 同会话切换 CA 必须重新计算有效期，不能继承上一次的 180 天。
        local sslRenewalDays=90 mode=ca-switch
        prepareRenewalFixture
        stat() {
            if [[ "$1" == --format=%z ]]; then
                date -d '100 days ago' '+%F %T.000000000 %z'
            else
                command stat "$@"
            fi
        }
        printf 'buypass\n' >"$(tlsSslTypeFile)"
        renewalTLS >/dev/null 2>&1
        [[ ! -s "${commandLog}" && "${sslRenewalDays}" == 90 ]]
        printf 'letsencrypt\n' >"$(tlsSslTypeFile)"
        renewalTLS >/dev/null 2>&1
        grep -q '^sudo:.*--cron --home ' "${commandLog}"
        [[ "${sslRenewalDays}" == 90 ]]
    )

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
    grep -qx 'nginx:stop' "${serviceLog}"
    ! grep -q '^sudo:' "${commandLog}"
    ! grep -qx 'xray:stop' "${serviceLog}"

    runRenewalCase xray-stop-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:stop' "${serviceLog}"
    grep -qx 'xray:stop' "${serviceLog}"
    grep -qx 'nginx:start' "${serviceLog}"
    ! grep -q '^sudo:' "${commandLog}"

    runRenewalCase renew-fail
    [[ "${rc}" == "1" ]]
    grep -q '^sudo:.*--cron --home ' "${commandLog}"
    ! grep -q '^sudo:.*--installcert ' "${commandLog}"
    grep -qx 'xray:start' "${serviceLog}"
    grep -qx 'nginx:start' "${serviceLog}"
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    ! grep -qx 'reload' "${serviceLog}"

    runRenewalCase install-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:stop' "${serviceLog}"
    grep -qx 'xray:stop' "${serviceLog}"
    grep -qx 'xray:start' "${serviceLog}"
    grep -qx 'nginx:start' "${serviceLog}"
    ! grep -qx 'reload' "${serviceLog}"
    grep -q '^sudo:.*--cron --home ' "${commandLog}"
    grep -q '^sudo:.*--installcert -d renew.example.com' "${commandLog}"

    runRenewalCase xray-start-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'xray:start' "${serviceLog}"
    grep -qx 'nginx:start' "${serviceLog}"
    ! grep -qx 'reload' "${serviceLog}"
    grep -q '^sudo:.*--installcert -d renew.example.com' "${commandLog}"

    runRenewalCase nginx-start-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'xray:start' "${serviceLog}"
    grep -qx 'nginx:start' "${serviceLog}"
    ! grep -qx 'reload' "${serviceLog}"
    grep -q '^sudo:.*--installcert -d renew.example.com' "${commandLog}"

    runRenewalCase stopped-services
    [[ "${rc}" == "0" ]]
    grep -F -q -- "600 -- ${tlsDir}/renew.example.com.key" "${chmodLog}"
    [[ ! -s "${serviceLog}" ]]
    [[ "${nginxState}" == "false" && "${xrayState}" == "false" && "${singBoxState}" == "false" ]]

    runRenewalCase dual-core-running
    [[ "${rc}" == "0" ]]
    grep -qx 'nginx:stop' "${serviceLog}"
    grep -qx 'xray:stop' "${serviceLog}"
    grep -qx 'sing-box:stop' "${serviceLog}"
    grep -qx 'xray:start' "${serviceLog}"
    grep -qx 'sing-box:start' "${serviceLog}"
    grep -qx 'nginx:start' "${serviceLog}"
    ! grep -qx 'reload' "${serviceLog}"
    [[ "${nginxState}" == "true" && "${xrayState}" == "true" && "${singBoxState}" == "true" ]]

    (
        local phase signal status
        eval "$(declare -f handleNginx | sed '1s/handleNginx/legacySignalHandleNginx/')"
        handleNginx() {
            legacySignalHandleNginx "$@" || return 1
            if [[ "${phase}" == stop && "$1" == stop ]]; then
                kill "-${signal}" "${BASHPID}"
                :
            fi
        }
        cp() {
            command cp "$@" || return 1
            if [[ "${phase}" == backup && "$*" == *"/padm-tls-renew."* ]]; then
                kill "-${signal}" "${BASHPID}"
                :
            fi
        }
        for phase in backup stop; do
            for signal in INT TERM; do
                mode=legacy-signal
                prepareRenewalFixture
                status=0
                ( renewalTLS ) >/dev/null 2>&1 || status=$?
                [[ "${status}" == "$([[ "${signal}" == INT ]] && printf 130 || printf 143)" ]] || return 1
                if [[ "${phase}" == backup ]]; then
                    [[ ! -s "${serviceLog}" ]] || return 1
                else
                    grep -qx 'nginx:stop' "${serviceLog}" &&
                        grep -qx 'nginx:start' "${serviceLog}" || return 1
                    ! grep -qx 'xray:stop' "${serviceLog}" || return 1
                fi
                [[ ! -s "${commandLog}" ]] || return 1
            done
        done
    )

    (
        local legacyDomain=legacy.example.com
        local subscribeTlsDomain=subscribe.example.com
        local usableChecks=0
        local initialNginx initialXray initialSingBox coreStates restartFails=false
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
        reloadCore() {
            printf 'reload\n' >>"${serviceLog}"
            xrayState=true
            singBoxState=true
        }
        runServiceAction() {
            [[ "$2" == restart ]] || return 1
            printf 'restart:%s\n' "$1" >>"${serviceLog}"
            [[ "${restartFails}" != true || "$1" != xray ]] || return 1
            case "$1" in
            xray) handleXray stop && handleXray start ;;
            sing-box) handleSingBox stop && handleSingBox start ;;
            *) return 1 ;;
            esac
        }
        handleNginx() {
            printf 'nginx:%s\n' "$1" >>"${serviceLog}"
            [[ "$1" == start ]] && nginxState=true || nginxState=false
        }
        readNginxSubscribe() {
            subscribeConfigState=valid
            subscribeDomain=${subscribeTlsDomain}
            subscribePort=39778
        }
        probeSubscribeTLS() {
            printf 'probe:%s:%s\n' "$1" "$2" >>"${serviceLog}"
            [[ "${nginxState}" == true ]]
        }

        # DNS 续签无需停服，只更新原来运行的服务；停着的 Nginx 不做 HTTPS 探测。
        for initialNginx in true false; do
            for coreStates in false:false true:false false:true true:true; do
                IFS=: read -r initialXray initialSingBox <<<"${coreStates}"
                nginxState=${initialNginx}
                xrayState=${initialXray}
                singBoxState=${initialSingBox}
                usableChecks=0
                printf 'legacy-old-cert\n' >"${tlsDir}/${legacyDomain}.crt"
                printf 'legacy-old-key\n' >"${tlsDir}/${legacyDomain}.key"
                printf 'subscribe-old-cert\n' >"${tlsDir}/${subscribeTlsDomain}.crt"
                printf 'subscribe-old-key\n' >"${tlsDir}/${subscribeTlsDomain}.key"
                : >"${commandLog}"
                : >"${serviceLog}"
                regressionExpectStatus 0 renewManagedTLSCertificates
                [[ "$(grep -c -- ' --cron ' "${commandLog}")" == "1" ]]
                [[ "$(grep -c -- ' --installcert ' "${commandLog}")" == "2" ]]
                grep -q -- " --installcert -d ${legacyDomain} " "${commandLog}"
                grep -q -- " --installcert -d ${subscribeTlsDomain} " "${commandLog}"
                [[ "$(<"${tlsDir}/${legacyDomain}.crt")" == "legacy-new-cert" ]]
                [[ "$(<"${tlsDir}/${subscribeTlsDomain}.crt")" == "subscribe-new-cert" ]]
                ! grep -qx reload "${serviceLog}"
                [[ "${nginxState}:${xrayState}:${singBoxState}" == "${initialNginx}:${initialXray}:${initialSingBox}" ]]
                if [[ "${initialXray}" == true ]]; then
                    grep -qx restart:xray "${serviceLog}"
                else
                    ! grep -q '^xray:\|^restart:xray$' "${serviceLog}"
                fi
                if [[ "${initialSingBox}" == true ]]; then
                    grep -qx restart:sing-box "${serviceLog}"
                else
                    ! grep -q '^sing-box:\|^restart:sing-box$' "${serviceLog}"
                fi
                if [[ "${initialNginx}" == true ]]; then
                    [[ "$(grep -c '^nginx:stop$' "${serviceLog}")" == "1" ]]
                    [[ "$(grep -c '^nginx:start$' "${serviceLog}")" == "1" ]]
                    grep -qx "probe:${subscribeTlsDomain}:39778" "${serviceLog}"
                else
                    ! grep -Eq '^(nginx:|probe:)' "${serviceLog}"
                fi
                ! grep -q '^nginx:restart$' "${serviceLog}"
            done
        done
        # 核心重启失败必须上报并保留备份，不能继续重启 Nginx 或探测 HTTPS。
        nginxState=true xrayState=true singBoxState=true
        usableChecks=0 restartFails=true
        printf 'legacy-old-cert\n' >"${tlsDir}/${legacyDomain}.crt"
        : >"${serviceLog}"
        : >"${errorLog}"
        regressionExpectStatus 1 renewManagedTLSCertificates
        grep -qx restart:xray "${serviceLog}"
        grep -qx restart:sing-box "${serviceLog}"
        ! grep -Eq '^(nginx:|probe:)' "${serviceLog}"
        grep -q '核心服务重载失败' "${errorLog}"
        grep -q '备份目录:' "${errorLog}"
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
Le_Webroot='no'
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
        grep -qx 'xray:start' "${serviceLog}"
        grep -qx 'nginx:start' "${serviceLog}"
        [[ "${nginxState}" == "true" && "${xrayState}" == "true" && "${singBoxState}" == "false" ]]
        grep -q 'TLS 证书续签后文件校验失败' "${errorLog}"

        sed -i "s|^Le_Webroot=.*$|Le_Webroot='alpn'|" "${homeDir}/.acme.sh/${certDomain}_ecc/${certDomain}.conf"
        usableChecks=0 chmodChecks=0
        : >"${serviceLog}"
        regressionExpectStatus 1 renewManagedTLSCertificates >/dev/null 2>&1
        grep -qx 'nginx:stop' "${serviceLog}"
        grep -qx 'nginx:start' "${serviceLog}"

        # Webroot 续签失败也不能暂停原先运行的服务。
        sed -i "s|^Le_Webroot=.*$|Le_Webroot='/var/www/html'|" "${homeDir}/.acme.sh/${certDomain}_ecc/${certDomain}.conf"
        usableChecks=0 chmodChecks=0
        : >"${serviceLog}"
        : >"${errorLog}"
        regressionExpectStatus 1 renewManagedTLSCertificates >/dev/null 2>&1
        [[ ! -s "${serviceLog}" ]]
        [[ "$(<"${tlsDir}/${certDomain}.crt")" == old-cert && "$(<"${tlsDir}/${certDomain}.key")" == old-key ]]
        [[ "${nginxState}" == true && "${xrayState}" == true && "${singBoxState}" == false ]]
        grep -q 'TLS 证书续签后文件校验失败' "${errorLog}"
    )

    (
        local scopedRoot="${root}/scoped-install"
        local tlsDir="${scopedRoot}/tls" homeDir="${scopedRoot}/home"
        local targetDomain=install.example.com unrelatedDomain=unrelated.example.com
        local acmeDomain sourceDir oldPairHash webroot probeDomain=${unrelatedDomain}
        local exactDir wildcardDir sourceMode
        local nginxHandlerDefinition
        local PADM_REQUIRE_USABLE_TLS_CERTIFICATE= PADM_CORE_SWITCH_TRANSACTION_ACTIVE=
        local lastInstallationConfig=true
        mkdir -p "${scopedRoot}"
        HOME="${homeDir}"
        PADM_TLS_DIR="${tlsDir}"
        command openssl req -new -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 \
            -subj "/CN=install.example.com" -addext "subjectAltName=DNS:install.example.com,DNS:*.example.com,DNS:*.legacy.example.net" \
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
            oldPairHash=$(sha256sum "${tlsDir}/${targetDomain}.crt" "${tlsDir}/${targetDomain}.key")
        }
        sudo() {
            local action= installDomain= crtTarget= keyTarget= acmeHome= force=false ecc=false
            local selectedSourceDir
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
            [[ "${installDomain}" == "${targetDomain}" || "${installDomain}" == "*.${targetDomain#*.}" ]] &&
                [[ "${ecc}" == true ]] || return 1
            selectedSourceDir="${homeDir}/.acme.sh/${installDomain}_ecc"
            case "${action}" in
            installcert)
                [[ "${crtTarget}" == "${tlsDir}/${targetDomain}.crt" &&
                    "${keyTarget}" == "${tlsDir}/${targetDomain}.key" ]] || return 1
                cp "${selectedSourceDir}/${installDomain}.cer" "${crtTarget}" || return 1
                cp "${selectedSourceDir}/${installDomain}.key" "${keyTarget}"
                ;;
            renew)
                [[ "${force}" == true && "${acmeHome}" == "${homeDir}/.acme.sh" ]] || return 1
                [[ "${mode}" != scoped-renew-fail ]] || return 1
                [[ "${mode}" != scoped-renew-short ]] || return 0
                cp "${scopedRoot}/valid.crt" "${selectedSourceDir}/${installDomain}.cer" || return 1
                if [[ "${mode}" == scoped-renew-bad ]]; then
                    printf 'invalid-new-key\n' >"${selectedSourceDir}/${installDomain}.key"
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

        # 坏单域名源回退有效通配符时，仍在原事务中重载运行服务，不请求 CA。
        for sourceMode in invalid-pem expiring; do
            prepareScopedInstallFixture valid dns_cf
            exactDir=${sourceDir}
            acmeDomain='*.example.com'
            sourceDir="${homeDir}/.acme.sh/${acmeDomain}_ecc"
            mkdir -p "${sourceDir}"
            cp "${scopedRoot}/valid.crt" "${sourceDir}/${acmeDomain}.cer"
            cp "${scopedRoot}/valid.key" "${sourceDir}/${acmeDomain}.key"
            if [[ "${sourceMode}" == invalid-pem ]]; then
                printf 'invalid-pem\n' >"${exactDir}/${targetDomain}.cer"
            else
                cp "${scopedRoot}/expiring.crt" "${exactDir}/${targetDomain}.cer"
            fi
            installTLS 1 >/dev/null 2>&1
            [[ "$(grep -c -- ' --installcert ' "${commandLog}")" == 1 ]]
            grep -Fq -- " --installcert -d ${acmeDomain} " "${commandLog}"
            ! grep -q -- ' --renew ' "${commandLog}"
            tlsCertificatePairUsable "${tlsDir}" "${targetDomain}"
            [[ "${nginxState}" == true && "${xrayState}" == true && "${singBoxState}" == false ]]
            grep -qx 'restart:xray' "${serviceLog}"
            assertScopedInstallIsolation
        done
        # 显式参数保留原源选择，不能由坏单域名自动切换到通配符。
        (
            local AUTO_TLS_CA=letsencrypt
            mode=scoped-renew
            prepareScopedInstallFixture expiring dns_cf
            wildcardDir="${homeDir}/.acme.sh/*.example.com_ecc"
            mkdir -p "${wildcardDir}"
            cp "${scopedRoot}/valid.crt" "${wildcardDir}/*.example.com.cer"
            cp "${scopedRoot}/valid.key" "${wildcardDir}/*.example.com.key"
            installTLS 1 >/dev/null 2>&1
            grep -Fq -- " --renew -d ${targetDomain} " "${commandLog}"
            ! grep -Fq -- ' -d *.example.com ' "${commandLog}"
            assertScopedInstallIsolation
        )

        mode=scoped-renew
        prepareScopedInstallFixture expiring no
        installTLS 1 >/dev/null 2>&1
        [[ "$(grep -c -- ' --renew ' "${commandLog}")" == 1 &&
            "$(grep -c -- ' --installcert ' "${commandLog}")" == 2 ]]
        command openssl x509 -in "${tlsDir}/${targetDomain}.crt" -checkend 86400 -noout >/dev/null
        [[ "${nginxState}" == true && "${xrayState}" == true && "${singBoxState}" == false ]]
        grep -qx 'xray:start' "${serviceLog}"
        grep -qx 'nginx-mode:start restore' "${serviceLog}"
        assertScopedInstallIsolation

        for mode in scoped-renew-fail scoped-renew-bad scoped-renew-short; do
            prepareScopedInstallFixture expiring no
            regressionExpectStatus 1 installTLS 1 >/dev/null 2>&1
            [[ "$(sha256sum "${tlsDir}/${targetDomain}.crt" "${tlsDir}/${targetDomain}.key")" == "${oldPairHash}" ]]
            [[ "${nginxState}" == true && "${xrayState}" == true && "${singBoxState}" == false ]]
            grep -qx 'xray:start' "${serviceLog}"
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
    padmRunCancelableCommand() { "$@"; }
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
        acmeInstallTransient=true
        acmeInstallAttempts=0
        renewalTLS() { printf 'renew\n' >>"${cleanLog}"; return 37; }
        : >"${cleanLog}"
        : >"${statusLog}"
        installTLS 1 <<<y
        [[ "${acmeInstallAttempts}" == 2 ]]
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
    sslType="${oldSslType}"
    dnsAPIType="${oldDnsAPIType}"
    dnsAPIStatus="${oldDnsAPIStatus}"
)
