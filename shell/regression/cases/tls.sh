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

    mkdir -p "${root}/home"
    HOME="${root}/home"
    errorCard() { return 0; }
    autoRead() {
        case "$3" in
        sslEmailStatus) printf -v "$3" 'n' ;;
        cfAPIToken) printf -v "$3" 'token' ;;
        cfZoneID) printf -v "$3" '' ;;
        selectSSLType) printf -v "$3" '3' ;;
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

    dnsTLSDomain=example
    captureFailureReturn "${dnsRcFile}" initDNSAPIConfig cloudflare

    dnsAPIType=cloudflare
    sslType=
    captureFailureReturn "${caRcFile}" switchSSLType

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
        openssl req -new -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
            -subj "/CN=${certDomain}" -addext "subjectAltName=DNS:${certDomain}" \
            -keyout "${certificateRoot}/valid.key" -out "${certificateRoot}/valid.crt" >/dev/null 2>&1
        openssl req -new -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
            -subj "/CN=wrong.example.com" -addext "subjectAltName=DNS:wrong.example.com" \
            -keyout "${certificateRoot}/wrong.key" -out "${certificateRoot}/wrong.crt" >/dev/null 2>&1

        # 自签证书可正常复用；错域名、错私钥和损坏 PEM 均不能冒充安装成功。
        cp "${certificateRoot}/valid.crt" "${PADM_TLS_DIR}/${certDomain}.crt"
        cp "${certificateRoot}/valid.key" "${PADM_TLS_DIR}/${certDomain}.key"
        installTLS 1 >/dev/null 2>&1
        singBoxLocalCertificateAvailable
        cp "${certificateRoot}/wrong.crt" "${PADM_TLS_DIR}/${certDomain}.crt"
        regressionExpectStatus 1 installTLS 1 >/dev/null 2>&1
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
        installAcmeTool() { return 0; }
        nginxRunning() { return 1; }
        xrayRunning() { return 1; }
        singBoxRunning() { return 1; }
        initTLSNginxConfig() { [[ "$2" == prepared.example.com ]] || return 1; domain=$2; }
        installTLS() { return 0; }
        singBoxLocalCertificateAvailable() { [[ "${domain}" == prepared.example.com ]]; }
        installCronTLS() { return 0; }
        restoreServicesAfterTLSRenewal() { return 0; }
        exec {inputFd}< <(printf 'next-parent-action\n')
        singBoxInstallLocalTLSCertificate <&"${inputFd}"
        [[ "${domain}" == prepared.example.com ]]
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
    tlsCertificatePairUsable() { return 0; }
    renewalTLS() { printf 'renew\n' >>"${cleanLog}"; }
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
        printf 'sudo:%s\n' "$*" >>"${cleanLog}"
        printf 'acme-cert\n' >"${PADM_TLS_DIR}/reinstall.example.com.crt"
        printf 'acme-key\n' >"${PADM_TLS_DIR}/reinstall.example.com.key"
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
        [[ "${nextInput}" == next-parent-action && "$(<"${cleanLog}")" == renew ]]
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
        [[ "$(grep -c '^sudo:' "${cleanLog}")" == 1 ]]
    done
    : >"${cleanLog}"
    lastInstallationConfig=true
    reInstallStatus=y
    installTLS 1 </dev/null
    [[ "$(<"${cleanLog}")" == renew ]]

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
