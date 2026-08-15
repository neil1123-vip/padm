#!/usr/bin/env bash

runSubscribeSaltWriteTransactionRegression() (
    local rootRel="${TMP_DIR}/subscribe-salt-write-transaction"
    local root saltFile
    local rc

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    saltFile="${root}/subscribeSalt"
    printf 'old-salt\n' >"${saltFile}"

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${saltFile}" ]]; then
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    set +e
    writeSubscribeSalt "${saltFile}" "new-salt"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${saltFile}")" == "old-salt" ]]
    ! compgen -G "${root}/.subscribeSalt.subscribe.*" >/dev/null

    commitGeneratedFile() {
        printf '%s|%s\n' "$2" "${3:-}" >"${root}/commit-mode.log"
        originalCommitGeneratedFile "$@"
    }
    writeSubscribeSalt "${saltFile}" "new-salt"
    [[ "$(<"${saltFile}")" == "new-salt" ]]
    grep -Fxq "${saltFile}|600" "${root}/commit-mode.log"
    ! compgen -G "${root}/.subscribeSalt.subscribe.*" >/dev/null
)

runCdnAddressTransactionRegression() (
    local rootRel="${TMP_DIR}/cdn-address-write-transaction"
    local root cdnFile
    local rc

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    cdnFile="${root}/cdn"
    printf 'old-cdn.example.com\n' >"${cdnFile}"

    cdnAddressFile() {
        printf '%s' "${cdnFile}"
    }

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${cdnFile}" ]]; then
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    set +e
    cdnWriteAddress "new-cdn.example.com"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${cdnFile}")" == "old-cdn.example.com" ]]
    ! compgen -G "${root}/.cdn.cdn.*" >/dev/null

    set +e
    cdnClearAddress
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${cdnFile}")" == "old-cdn.example.com" ]]
    ! compgen -G "${root}/.cdn.cdn.*" >/dev/null

    commitGeneratedFile() {
        originalCommitGeneratedFile "$@"
    }
    cdnWriteAddress "new-cdn.example.com"
    [[ "$(<"${cdnFile}")" == "new-cdn.example.com" ]]
    ! compgen -G "${root}/.cdn.cdn.*" >/dev/null

    cdnClearAddress
    [[ ! -s "${cdnFile}" ]]
    ! compgen -G "${root}/.cdn.cdn.*" >/dev/null

    subscribe() {
        return 1
    }
    AUTO_INSTALL=
    cdnWriteAddress "old-cdn.example.com"
    set +e
    setCDNEntryAddress <<<"new-cdn.example.com"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${cdnFile}")" == "old-cdn.example.com" ]]

    set +e
    clearCDNEntryAddress
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${cdnFile}")" == "old-cdn.example.com" ]]

    local refreshCalls=0
    subscribe() {
        refreshCalls=$((refreshCalls + 1))
        return 0
    }
    cdnWriteAddress() { return 1; }
    set +e
    setCDNEntryAddress <<<"new-cdn.example.com"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${refreshCalls}" == "0" ]]
    [[ "$(<"${cdnFile}")" == "old-cdn.example.com" ]]

    cdnClearAddress() { return 1; }
    set +e
    clearCDNEntryAddress
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${refreshCalls}" == "0" ]]
    [[ "$(<"${cdnFile}")" == "old-cdn.example.com" ]]
)

runSubscribeServerNameRegression() {
    local oldCurrentHost="${currentHost:-}"
    local oldTlsDir="${PADM_TLS_DIR:-}"
    local oldAutoDomain="${AUTO_DOMAIN:-}"
    local oldCronName="${cronName:-}"
    local oldConfigState="${subscribeConfigState:-}"
    local oldSubscribeDomain="${subscribeDomain:-}"
    local originalPairUsable
    local tlsDir="${TMP_DIR}/subscribe-tls"
    mkdir -p "${tlsDir}"
    originalPairUsable=$(declare -f tlsCertificatePairUsable)

    cronName=InstallSubscription
    currentHost=host.example.com
    AUTO_DOMAIN=
    subscribeConfigState=missing
    subscribeDomain=
    ! resolveSubscribeServerName >/dev/null

    AUTO_DOMAIN=domain.example.com
    [[ "$(resolveSubscribeServerName)" == "domain.example.com" ]]
    AUTO_DOMAIN='bad domain.example.com'
    ! resolveSubscribeServerName >/dev/null

    AUTO_DOMAIN=
    subscribeConfigState=valid
    subscribeDomain=subscribe.example.com
    [[ "$(resolveSubscribeServerName)" == "subscribe.example.com" ]]

    subscribeConfigState=missing
    subscribeDomain=
    export PADM_TLS_DIR="${tlsDir}"
    printf 'cert\n' >"${tlsDir}/cert.example.com.crt"
    printf 'key\n' >"${tlsDir}/cert.example.com.key"
    printf 'cert\n' >"${tlsDir}/bad;name.crt"
    printf 'key\n' >"${tlsDir}/bad;name.key"
    tlsCertificatePairUsable() { [[ "$2" == "cert.example.com" ]]; }
    [[ "$(resolveSubscribeServerName)" == "cert.example.com" ]]

    eval "${originalPairUsable}"

    (
        set -e
        local certRoot="${TMP_DIR}/subscribe-real-certificates"
        local caDir="${certRoot}/ca"
        local subjectPrefix=/
        [[ -z "${MSYSTEM:-}" ]] || subjectPrefix=//
        mkdir -p "${certRoot}" "${caDir}/newcerts"
        openssl req -x509 -newkey rsa:2048 -nodes \
            -keyout "${certRoot}/valid.example.com.key" \
            -out "${certRoot}/valid.example.com.crt" \
            -days 1 -subj "${subjectPrefix}CN=valid.example.com" \
            -addext 'subjectAltName=DNS:valid.example.com' >/dev/null 2>&1
        openssl req -x509 -newkey rsa:2048 -nodes \
            -keyout "${certRoot}/other.example.com.key" \
            -out "${certRoot}/other.example.com.crt" \
            -days 1 -subj "${subjectPrefix}CN=other.example.com" \
            -addext 'subjectAltName=DNS:other.example.com' >/dev/null 2>&1
        tlsCertificatePairUsable "${certRoot}" valid.example.com
        cp "${certRoot}/valid.example.com.crt" "${certRoot}/wrong.example.com.crt"
        cp "${certRoot}/valid.example.com.key" "${certRoot}/wrong.example.com.key"
        ! tlsCertificatePairUsable "${certRoot}" wrong.example.com
        cp "${certRoot}/other.example.com.key" "${certRoot}/valid.example.com.key"
        ! tlsCertificatePairUsable "${certRoot}" valid.example.com
        printf 'not-a-certificate\n' >"${certRoot}/broken.example.com.crt"
        printf 'not-a-key\n' >"${certRoot}/broken.example.com.key"
        ! tlsCertificatePairUsable "${certRoot}" broken.example.com

        export PADM_TEST_CA_DIR="${caDir}"
        : >"${caDir}/index.txt"
        printf '1000\n' >"${caDir}/serial"
        openssl req -x509 -newkey rsa:2048 -nodes \
            -keyout "${caDir}/ca.key" -out "${caDir}/ca.crt" \
            -days 1 -subj "${subjectPrefix}CN=padm-regression-ca" >/dev/null 2>&1
        openssl req -new -newkey rsa:2048 -nodes \
            -keyout "${certRoot}/expired.example.com.key" \
            -out "${caDir}/expired.csr" -subj "${subjectPrefix}CN=expired.example.com" \
            -addext 'subjectAltName=DNS:expired.example.com' >/dev/null 2>&1
        cat >"${caDir}/ca.cnf" <<'EOF'
[ ca ]
default_ca = CA_default
[ CA_default ]
dir = $ENV::PADM_TEST_CA_DIR
database = $dir/index.txt
new_certs_dir = $dir/newcerts
certificate = $dir/ca.crt
private_key = $dir/ca.key
serial = $dir/serial
default_md = sha256
default_days = 1
policy = policy_any
copy_extensions = copy
unique_subject = no
[ policy_any ]
commonName = optional
EOF
        openssl ca -batch -notext -config "${caDir}/ca.cnf" \
            -startdate 20200101000000Z -enddate 20200102000000Z \
            -in "${caDir}/expired.csr" \
            -out "${certRoot}/expired.example.com.crt" >/dev/null 2>&1
        ! tlsCertificatePairUsable "${certRoot}" expired.example.com
        unset PADM_TEST_CA_DIR
    )

    (
        local callLog="${TMP_DIR}/subscribe-auto-dns-preflight.log"
        local errorLog="${TMP_DIR}/subscribe-auto-dns-preflight-error.log"
        local testTlsDir="${tlsDir}"
        : >"${callLog}"
        : >"${errorLog}"
        tlsManagedDir() { printf '%s\n' "${testTlsDir}"; }
        tlsCertificatePairUsable() { return 1; }
        readAcmeTLS() { printf 'read-acme\n' >>"${callLog}"; }
        switchDNSAPI() { printf 'switch-dns\n' >>"${callLog}"; }
        installAcmeTool() { printf 'install-acme\n' >>"${callLog}"; }
        installTLS() { printf 'install-tls\n' >>"${callLog}"; }
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        cronName=InstallSubscription
        AUTO_INSTALL=true
        AUTO_DOMAIN=cert.example.com
        AUTO_DNS_API=yes
        AUTO_DNS_API_TYPE=cloudflare
        AUTO_CLOUDFLARE_API_TOKEN=
        PADM_CLOUDFLARE_API_TOKEN=
        CLOUDFLARE_API_TOKEN=
        CF_Token=
        ! prepareSubscribeTLSCertificate cert.example.com
        [[ ! -s "${callLog}" ]]
        grep -q 'Cloudflare DNS API Token 为空' "${errorLog}"

        : >"${errorLog}"
        AUTO_DNS_API_TYPE=aliyun
        AUTO_ALIYUN_API_KEY=only-key
        AUTO_ALIYUN_API_SECRET=
        PADM_ALIYUN_API_KEY=
        PADM_ALIYUN_API_SECRET=
        ! prepareSubscribeTLSCertificate cert.example.com
        [[ ! -s "${callLog}" ]]
        grep -q '阿里云 DNS API 凭据不完整' "${errorLog}"
    )

    (
        local callLog="${TMP_DIR}/subscribe-http01-restore.log"
        local dnsReady=true
        local issueStatus=0
        local nginxStopped=false
        checkDNSIP() { [[ "${dnsReady}" == "true" ]]; }
        subscriptionTcpPortHasListener() { [[ "${nginxStopped}" != "true" ]]; }
        subscriptionTcpPortListenersAreNginx() { return 0; }
        nginxRunning() { return 0; }
        runSubscribeNginxAction() {
            printf 'nginx:%s\n' "$1" >>"${callLog}"
            [[ "$1" == "stop" ]] && nginxStopped=true || nginxStopped=false
        }
        allowPort() { PADM_LAST_ALLOW_PORT_ADDED=true; printf 'allow:80\n' >>"${callLog}"; }
        denyPort() { printf 'deny:80\n' >>"${callLog}"; }
        installTLS() { printf 'issue\n' >>"${callLog}"; return "${issueStatus}"; }
        : >"${callLog}"
        subscriptionInstallTLSHttp01 cert.example.com
        [[ "$(<"${callLog}")" == $'nginx:stop\nallow:80\nissue\ndeny:80\nnginx:start' ]]

        : >"${callLog}"
        issueStatus=1
        nginxStopped=false
        ! subscriptionInstallTLSHttp01 cert.example.com
        [[ "$(<"${callLog}")" == $'nginx:stop\nallow:80\nissue\ndeny:80\nnginx:start' ]]

        : >"${callLog}"
        dnsReady=false
        nginxStopped=false
        ! subscriptionInstallTLSHttp01 cert.example.com
        [[ ! -s "${callLog}" ]]
    )

    (
        local commandLog="${TMP_DIR}/install-subscription-command.log"
        local commandStatus
        eval "$(awk '/^handleScriptCommand\(\)/,/^}/ { print }' "${PROJECT_ROOT}/install.sh")"
        mkdirTools() { return 0; }
        installSubscribe() { return 0; }
        errorCard() { printf 'error:%s\n' "$*" >>"${commandLog}"; }
        successCard() { printf 'success:%s\n' "$*" >>"${commandLog}"; }
        cronName=InstallSubscription
        readNginxSubscribe() { subscribeConfigState=invalid; return 1; }
        : >"${commandLog}"
        set +e
        (handleScriptCommand)
        commandStatus=$?
        set -e
        [[ "${commandStatus}" == "1" ]]
        grep -q '安装后配置读取失败' "${commandLog}"

        readNginxSubscribe() {
            subscribeConfigState=valid
            subscribeType=https
            subscribePort=39778
        }
        : >"${commandLog}"
        set +e
        (handleScriptCommand)
        commandStatus=$?
        set -e
        [[ "${commandStatus}" == "0" ]]
        grep -q 'success:订阅服务安装完成: https 端口 39778' "${commandLog}"
    )

    currentHost="${oldCurrentHost}"
    AUTO_DOMAIN="${oldAutoDomain}"
    cronName="${oldCronName}"
    subscribeConfigState="${oldConfigState}"
    subscribeDomain="${oldSubscribeDomain}"
    if [[ -n "${oldTlsDir}" ]]; then
        PADM_TLS_DIR="${oldTlsDir}"
    else
        unset PADM_TLS_DIR
    fi
}

runSubscribeNginxConfigWriteRegression() {
    local nginxRootRel="${TMP_DIR}/nginx-subscribe"
    local nginxRoot targetPath
    local oldPath="${PATH}"
    local oldTmpDir="${TMPDIR:-}"
    local nginxTmpRoot="${TMP_DIR}/nginx-subscribe-tmp"
    local helperLog="${TMP_DIR}/nginx-subscribe-helper.log"
    mkdir -p "${TMP_DIR}/fake-bin" "${nginxRootRel}" "${nginxTmpRoot}"
    nginxRoot=$(cd -- "${nginxRootRel}" && pwd -P)
    targetPath="${nginxRoot}/subscribe.conf"
    TMPDIR="${nginxTmpRoot}"
    nginxConfigPath="${nginxRoot}/"
    : >"${helperLog}"
    cat >"${TMP_DIR}/fake-bin/nginx" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "-t" ]]
printf 'nginx validate %s\n' "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}"
[[ "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}" == "success" ]]
SH
    chmod +x "${TMP_DIR}/fake-bin/nginx"
    PATH="${TMP_DIR}/fake-bin:${PATH}"
    printf 'old config\n' >"${targetPath}"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    if writeSubscribeNginxConfig <<'EOF' 2>/dev/null
new config
EOF
    then
        return 1
    fi
    [[ "$(<"${targetPath}")" == "old config" ]]
    grep -qxF 'nginx validate fail' "${nginxTmpRoot}/padm-subscribe-nginx-test.log"
    [[ ! -e "${targetPath}.tmp" ]]
    ! compgen -G "${TMP_DIR}/nginx-subscribe/.subscribe.conf.*" >/dev/null
    printf 'old config\n' >"${targetPath}"
    (
        commitGeneratedFile() { return 1; }
        if writeSubscribeNginxConfig <<'EOF' 2>/dev/null
commit fail config
EOF
        then
            exit 1
        fi
    )
    [[ "$(<"${targetPath}")" == "old config" ]]
    ! compgen -G "${TMP_DIR}/nginx-subscribe/.subscribe.conf.*" >/dev/null
    printf 'old config\n' >"${targetPath}"
    (
        local backupGlob="${nginxRoot}/.subscribe.conf.backup.*"
        local backups=()
        eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
        commitGeneratedFile() {
            if [[ "$2" == "${targetPath}" && "$1" == "${nginxRoot}/.subscribe.conf.backup."* ]]; then
                return 1
            fi
            originalCommitGeneratedFile "$@"
        }
        if writeSubscribeNginxConfig <<'EOF' 2>/dev/null
rollback fail config
EOF
        then
            return 1
        fi
        [[ "$(<"${targetPath}")" == "rollback fail config" ]]
        mapfile -t backups < <(compgen -G "${backupGlob}" || true)
        [[ "${#backups[@]}" == "1" ]]
        [[ "$(<"${backups[0]}")" == "old config" ]]
        [[ "${SUBSCRIBE_NGINX_CONFIG_WRITE_ERROR}" == *"旧配置恢复失败"* ]]
        rm -f "${backups[0]}"
    ) || return 1
    rm -f "${targetPath}"
    (
        subscriptionSyncSetManualCheckMessage() {
            printf "manual-check:%s|%s\n" "$2" "$3" >>"${helperLog}"
            printf -v "$1" "%s，请手动检查%s" "$2" "$3"
        }
        rm() {
            if [[ "$1" == "-f" && ( "$2" == "${targetPath}" || ( "$2" == "--" && "$3" == "${targetPath}" ) ) ]]; then
                return 1
            fi
            command rm "$@"
        }
        if writeSubscribeNginxConfig <<'EOF' 2>/dev/null
cleanup fail config
EOF
        then
            return 1
        fi
        [[ "$(<"${targetPath}")" == "cleanup fail config" ]]
        [[ "${SUBSCRIBE_NGINX_CONFIG_WRITE_ERROR}" == *"新配置清理失败"* ]]
        grep -q "manual-check:订阅 Nginx 配置校验失败，且新配置清理失败| ${targetPath}" "${helperLog}"
    ) || return 1
    rm -f "${targetPath}"
    export PADM_FAKE_NGINX_VALIDATE_MODE=success
    writeSubscribeNginxConfig <<'EOF'
new config
EOF
    [[ "$(<"${targetPath}")" == "new config" ]]
    grep -qxF 'nginx validate success' "${nginxTmpRoot}/padm-subscribe-nginx-test.log"
    [[ ! -e "${targetPath}.tmp" ]]
    [[ ! -e "${targetPath}.bak" ]]
    ! compgen -G "${TMP_DIR}/nginx-subscribe/.subscribe.conf.*" >/dev/null
    PATH="${oldPath}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    unset PADM_FAKE_NGINX_VALIDATE_MODE

    (
        local root="${TMP_DIR}/subscribe-nginx-custom-alias"
        local nginxRoot="${root}/nginx"
        local tlsRoot="${root}/tls"
        local subscribeRoot="${root}/public-subscribe"
        local staticRoot="${root}/static"
        local oldSubscribeDir="${PADM_SUBSCRIBE_DIR:-}"
        local oldTlsDir="${PADM_TLS_DIR:-}"
        local oldCurrentHost="${currentHost:-}"
        local configPath

        mkdir -p "${root}/fake-bin" "${nginxRoot}" "${tlsRoot}" "${subscribeRoot}" "${staticRoot}"
        cat >"${root}/fake-bin/nginx" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-v" ]]; then
    printf 'nginx version: nginx/1.26.0\n' >&2
    exit 0
fi
[[ "$1" == "-t" ]]
SH
        chmod +x "${root}/fake-bin/nginx"
        PATH="${root}/fake-bin:${oldPath}"
        nginxConfigPath="${nginxRoot}/"
        nginxStaticPath="${staticRoot}"
        export PADM_TLS_DIR="${tlsRoot}"
        export PADM_SUBSCRIBE_DIR="${subscribeRoot}"
        currentHost=reality.example.com
        AUTO_DOMAIN=subscribe.example.com
        AUTO_SUBSCRIBE_PORT=39778
        printf 'cert\n' >"${tlsRoot}/subscribe.example.com.crt"
        printf 'key\n' >"${tlsRoot}/subscribe.example.com.key"

        readNginxSubscribe() {
            subscribePort=
            subscribeDomain=
            subscribeType=
            subscribeConfigState=missing
        }
        prepareSubscribeTLSCertificate() { return 0; }
        tlsCertificatePairUsable() { return 0; }
        subscriptionTcpPortHasListener() { return 1; }
        allowPort() { return 0; }
        probeSubscribeTLS() { return 0; }
        hasIPv6Connectivity() { return 1; }
        installSubscriptionControlService() { return 1; }
        coreStartupServiceEnabled() { return 1; }
        bootStartup() { return 0; }
        handleNginx() { return 0; }
        nginxRunning() { return 0; }

        installSubscribe >/dev/null 2>&1
        configPath="${nginxRoot}/subscribe.conf"
        grep -q "alias ${subscribeRoot}/\\\$1/\\\$2;" "${configPath}"
        grep -q "ssl_certificate ${tlsRoot}/subscribe.example.com.crt;" "${configPath}"
        grep -q "ssl_certificate_key ${tlsRoot}/subscribe.example.com.key;" "${configPath}"

        if [[ -n "${oldSubscribeDir}" ]]; then export PADM_SUBSCRIBE_DIR="${oldSubscribeDir}"; else unset PADM_SUBSCRIBE_DIR; fi
        if [[ -n "${oldTlsDir}" ]]; then export PADM_TLS_DIR="${oldTlsDir}"; else unset PADM_TLS_DIR; fi
        currentHost="${oldCurrentHost}"
    )
}

runSubscribeNginxServiceFailureRegression() (
    local root="${TMP_DIR}/subscribe-nginx-service-failure"
    local oldPath="${PATH}"
    local serviceLog="${root}/service.log"
    local firewallState="${root}/firewall.state"
    local firewallLog="${root}/firewall.log"
    local errorLog="${root}/error.log"
    local mode=reload
    local rc writeCalls controlCalls bootCalls
    local runtimeRunning=true
    local runtimeEnabled=false
    local startFailures=0
    local startCalls=0

    mkdir -p "${root}/fake-bin" "${root}/nginx" "${root}/static" "${root}/tls"
    cat >"${root}/fake-bin/nginx" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-v" ]]; then
    printf 'nginx version: nginx/1.26.0\n' >&2
    exit 0
fi
exit 0
SH
    chmod +x "${root}/fake-bin/nginx"
    PATH="${root}/fake-bin:${PATH}"
    nginxConfigPath="${root}/nginx/"
    nginxStaticPath="${root}/static"
    export PADM_TLS_DIR="${root}/tls"
    export PADM_SUBSCRIBE_DIR="${root}/public"
    currentHost=reality.example.com
    AUTO_DOMAIN=subscribe.example.com
    AUTO_SUBSCRIBE_PORT=39778
    printf 'cert\n' >"${PADM_TLS_DIR}/subscribe.example.com.crt"
    printf 'key\n' >"${PADM_TLS_DIR}/subscribe.example.com.key"
    printf 'old-subscribe-config\n' >"${nginxConfigPath}subscribe.conf"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    PADM_FIREWALL_STATE_FILE="${firewallState}"
    : >"${serviceLog}"
    : >"${firewallLog}"
    : >"${errorLog}"

    readNginxSubscribe() {
        subscribePort=
        subscribeDomain=
        subscribeType=
        subscribeConfigState=missing
        if [[ "${mode}" == "existing-port" ]]; then
            subscribePort=39778
            subscribeDomain=subscribe.example.com
            subscribeType=https
            subscribeConfigState=valid
        elif [[ "${mode}" == "port-change" || "${mode}" == "old-port-deny-fail" ]]; then
            subscribePort=3443
            subscribeDomain=subscribe.example.com
            subscribeType=https
            subscribeConfigState=valid
        fi
    }
    prepareSubscribeTLSCertificate() { return 0; }
    tlsCertificatePairUsable() { return 0; }
    subscriptionTcpPortHasListener() {
        [[ "${mode}" == "existing-port" ]]
    }
    subscriptionTcpPortListenersAreNginx() { return 0; }
    allowPort() {
        local key="port:ufw:tcp:$1"
        PADM_LAST_ALLOW_PORT_ADDED=true
        padmFirewallStateAdd "${key}" || return 1
        padmTrackPortAllowTransactionKey "${key}"
    }
    removeFirewallPortRule() {
        printf '%s:%s:%s\n' "$1" "$2" "$3" >>"${firewallLog}"
        [[ "${mode}" == "old-port-deny-fail" && "$2" == "3443" ]] && return 1
        return 0
    }
    hasIPv6Connectivity() { return 1; }
    writeSubscribeNginxConfig() {
        writeCalls=$((writeCalls + 1))
        local generatedConfig
        generatedConfig=$(cat)
        if [[ "${mode}" == "config-fail" ]]; then
            SUBSCRIBE_NGINX_CONFIG_WRITE_ERROR="订阅 Nginx 配置校验失败，且旧配置恢复失败"
            return 1
        fi
        printf '%s\n' "${generatedConfig}" >"${nginxConfigPath}subscribe.conf"
    }
    installSubscriptionControlService() {
        controlCalls=$((controlCalls + 1))
        return 1
    }
    bootStartup() {
        bootCalls=$((bootCalls + 1))
        printf '%s:boot\n' "${mode}" >>"${serviceLog}"
        runtimeEnabled=true
        return 0
    }
    coreStartupServiceEnabled() { [[ "${runtimeEnabled}" == "true" ]]; }
    restoreCoreStartupServiceInstall() {
        checkLogBackupRestore "$1" || return 1
        runtimeEnabled=$3
        padmRemoveCleanupPath "$1"
    }
    nginxRunning() { [[ "${runtimeRunning}" == "true" ]]; }
    handleNginx() {
        printf '%s:%s:%s\n' "${mode}" "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ -n "${2:-}" ]] && printf '%s:nginx-mode:%s\n' "${mode}" "$*" >>"${serviceLog}"
        if [[ "$1" == "stop" ]]; then
            runtimeRunning=false
            return 0
        fi
        startCalls=$((startCalls + 1))
        if ((startFailures > 0)); then
            startFailures=$((startFailures - 1))
            return 1
        fi
        runtimeRunning=true
        return 0
    }
    probeSubscribeTLS() { [[ "${mode}" != "probe-fail" ]]; }

    mode=reload
    : >"${serviceLog}"
    : >"${errorLog}"
    rm -f "${firewallState}"
    : >"${firewallLog}"
    writeCalls=0
    controlCalls=0
    bootCalls=0
    startCalls=0
    runtimeRunning=true
    runtimeEnabled=false
    startFailures=1
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    set +e
    installSubscribe >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${writeCalls}" == "1" ]]
    [[ "${controlCalls}" == "0" ]]
    [[ "${bootCalls}" == "1" ]]
    grep -qx 'reload:stop:true' "${serviceLog}"
    grep -qx 'reload:start:true' "${serviceLog}"
    grep -qx 'reload:nginx-mode:start restore' "${serviceLog}" || return 1
    grep -q '订阅 Nginx 服务应用失败' "${errorLog}"
    grep -qxF 'old-subscribe-config' "${nginxConfigPath}subscribe.conf"
    [[ "${runtimeRunning}" == "true" ]]
    [[ "${runtimeEnabled}" == "false" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    grep -qx 'ufw:39778:tcp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    mode=existing-port
    : >"${serviceLog}"
    : >"${firewallLog}"
    rm -f "${firewallState}"
    : >"${errorLog}"
    writeCalls=0
    controlCalls=0
    bootCalls=0
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    runtimeRunning=true
    runtimeEnabled=false
    startFailures=0
    set +e
    installSubscribe >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
    [[ "${writeCalls}" == "0" ]]
    [[ "${controlCalls}" == "0" ]]
    [[ "${bootCalls}" == "0" ]]
    [[ ! -s "${serviceLog}" ]]
    [[ ! -s "${errorLog}" ]]
    [[ "${runtimeEnabled}" == "false" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    [[ ! -s "${firewallLog}" ]]

    mode=port-change
    : >"${serviceLog}"
    : >"${firewallLog}"
    : >"${errorLog}"
    printf 'old-subscribe-config\n' >"${nginxConfigPath}subscribe.conf"
    printf 'port:ufw:tcp:3443\n' >"${firewallState}"
    writeCalls=0
    controlCalls=0
    bootCalls=0
    startCalls=0
    runtimeRunning=true
    runtimeEnabled=false
    startFailures=0
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    set +e
    installSubscribe >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
    [[ "${writeCalls}" == "1" && "${controlCalls}" == "0" && "${bootCalls}" == "1" ]]
    grep -q 'listen 39778 ssl' "${nginxConfigPath}subscribe.conf"
    grep -qx 'port:ufw:tcp:39778' "${firewallState}"
    ! grep -q 'port:ufw:tcp:3443' "${firewallState}"
    grep -qx 'ufw:3443:tcp' "${firewallLog}"
    [[ "${runtimeRunning}" == "true" && "${runtimeEnabled}" == "true" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    mode=old-port-deny-fail
    : >"${serviceLog}"
    : >"${firewallLog}"
    : >"${errorLog}"
    printf 'old-subscribe-config\n' >"${nginxConfigPath}subscribe.conf"
    printf 'port:ufw:tcp:3443\n' >"${firewallState}"
    writeCalls=0
    controlCalls=0
    bootCalls=0
    startCalls=0
    runtimeRunning=true
    runtimeEnabled=false
    startFailures=0
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    set +e
    installSubscribe >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${writeCalls}" == "1" && "${controlCalls}" == "0" && "${bootCalls}" == "1" ]]
    grep -qxF 'old-subscribe-config' "${nginxConfigPath}subscribe.conf"
    grep -qx 'port:ufw:tcp:3443' "${firewallState}"
    ! grep -q 'port:ufw:tcp:39778' "${firewallState}"
    grep -qx 'ufw:3443:tcp' "${firewallLog}"
    grep -qx 'ufw:39778:tcp' "${firewallLog}"
    [[ "$(grep -c '^old-port-deny-fail:stop:true$' "${serviceLog}")" == "2" ]]
    [[ "$(grep -c '^old-port-deny-fail:start:true$' "${serviceLog}")" == "2" ]]
    grep -q '旧订阅端口防火墙规则回收失败，已恢复旧 Nginx 配置' "${errorLog}"
    [[ "${runtimeRunning}" == "true" && "${runtimeEnabled}" == "false" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    mode=config-fail
    : >"${serviceLog}"
    : >"${errorLog}"
    writeCalls=0
    controlCalls=0
    bootCalls=0
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    runtimeRunning=true
    runtimeEnabled=false
    startFailures=0
    rm -f "${firewallState}"
    : >"${firewallLog}"
    set +e
    installSubscribe >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${writeCalls}" == "1" ]]
    [[ "${controlCalls}" == "0" ]]
    [[ "${bootCalls}" == "0" ]]
    grep -q '订阅 Nginx 配置校验失败，且旧配置恢复失败' "${errorLog}"
    grep -qxF 'old-subscribe-config' "${nginxConfigPath}subscribe.conf"
    [[ "${runtimeEnabled}" == "false" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    grep -qx 'ufw:39778:tcp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    mode=probe-fail
    : >"${serviceLog}"
    : >"${errorLog}"
    : >"${firewallLog}"
    rm -f "${firewallState}"
    writeCalls=0
    controlCalls=0
    bootCalls=0
    startCalls=0
    runtimeRunning=true
    runtimeEnabled=false
    startFailures=0
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    set +e
    installSubscribe >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${writeCalls}" == "1" ]]
    [[ "${controlCalls}" == "0" ]]
    [[ "${bootCalls}" == "1" ]]
    grep -qx 'probe-fail:stop:true' "${serviceLog}"
    grep -qx 'probe-fail:start:true' "${serviceLog}"
    [[ "$(grep -c '^probe-fail:stop:true$' "${serviceLog}")" == "2" ]]
    [[ "$(grep -c '^probe-fail:start:true$' "${serviceLog}")" == "2" ]]
    grep -q '订阅 HTTPS 本机 SNI/TLS 探测失败' "${errorLog}"
    grep -qxF 'old-subscribe-config' "${nginxConfigPath}subscribe.conf"
    [[ "${runtimeRunning}" == "true" ]]
    [[ "${runtimeEnabled}" == "false" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    grep -qx 'ufw:39778:tcp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    PATH="${oldPath}"
)

runSubscribeUserOutputTransactionRegression() {
    local oldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
    local oldPublicDir="${PADM_SUBSCRIBE_DIR:-}"
    local oldScriptDir="${SCRIPT_DIR}"
    local oldTmpDir="${TMPDIR:-}"
    local rootRel="${TMP_DIR}/subscribe-user-transaction"
    local root localDir publicDir userTmpRoot stageMarker clashProfilePath
    local email="atomic-user"
    local emailMd5="atomic-md5"
    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    localDir="${root}/local"
    publicDir="${root}/public"
    userTmpRoot="${root}/tmp"
    stageMarker="${root}/stage-dirs.txt"
    export PADM_SUBSCRIBE_LOCAL_DIR="${localDir}"
    export PADM_SUBSCRIBE_DIR="${publicDir}"
    TMPDIR="${userTmpRoot}"
    SCRIPT_DIR="${PROJECT_ROOT}"
    subscribeType=https
    subscribeSalt=salt
    mkdir -p "${localDir}/default" "${localDir}/clashMeta" "${localDir}/sing-box" "${publicDir}/default" "${publicDir}/clashMeta" "${publicDir}/clashMetaProfiles" "${publicDir}/sing-box" "${publicDir}/sing-box_profiles" "${userTmpRoot}"
    : >"${stageMarker}"
    clashProfilePath="${root}/clash-meta-profile.yaml"
    clashMetaConfig "https://example.com/proxies" "${emailMd5}" "${clashProfilePath}"
    grep -qx 'allow-lan: false' "${clashProfilePath}"
    grep -qx 'bind-address: "127.0.0.1"' "${clashProfilePath}"
    grep -qx 'external-controller: 127.0.0.1:9090' "${clashProfilePath}"
    grep -qx '  allow-origins: \[\]' "${clashProfilePath}"
    grep -qx '  allow-private-network: false' "${clashProfilePath}"
    grep -qx '  listen: 127.0.0.1:1053' "${clashProfilePath}"
    ! grep -qE '^(bind-address: "\*"|external-controller: 0\.0\.0\.0:|  listen: 0\.0\.0\.0:)' "${clashProfilePath}"
    grep -q '^  atomic-md5_provider:' "${clashProfilePath}"
    grep -q '^    path: ./atomic-md5_provider.yaml$' "${clashProfilePath}"
    ! grep -q 'salt_provider' "${clashProfilePath}"
    eval "$(declare -f clashMetaConfig | sed '1s/^clashMetaConfig/originalClashMetaConfig/')"
    eval "$(declare -f commitSubscribeUserOutputFile | sed '1s/^commitSubscribeUserOutputFile/originalCommitSubscribeUserOutputFile/')"

    (
        local stagedPath="${root}/public-mode.stage"
        local targetPath="${root}/public-mode.target"
        eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
        commitGeneratedFile() {
            [[ "${3:-}" == "640" ]] || return 1
            originalCommitGeneratedFile "$@"
        }
        printf 'secret\n' >"${stagedPath}"
        commitSubscribePublicFile "${stagedPath}" "${targetPath}"
        [[ "$(<"${targetPath}")" == "secret" ]]
    )

    writeOldSubscribeOutputs() {
        printf 'old-default\n' >"${publicDir}/default/${emailMd5}"
        printf 'old-clash\n' >"${publicDir}/clashMeta/${emailMd5}"
        printf 'old-profile\n' >"${publicDir}/clashMetaProfiles/${emailMd5}"
        printf 'old-sing-profile\n' >"${publicDir}/sing-box_profiles/${emailMd5}"
        printf 'old-sing\n' >"${publicDir}/sing-box/${emailMd5}"
    }

    writeLocalSubscribeOutputs() {
        printf 'vless://new-node#atomic-user\n' >"${localDir}/default/${email}"
        printf '  - name: atomic-user\n    type: vless\n' >"${localDir}/clashMeta/${email}"
        printf '[{"tag":"atomic-user","type":"direct"}]\n' >"${localDir}/sing-box/${email}"
    }

    (
        currentHost=example.com
        rm -rf "${localDir}/default" "${localDir}/clashMeta" "${localDir}/sing-box"
        mkdir -p "${localDir}/default" "${localDir}/clashMeta" "${localDir}/sing-box"
        if defaultBase64Code vmessws 443 'bad"name' '11111111-1111-1111-1111-111111111111' example.com /ws >/dev/null 2>&1; then
            return 1
        fi
        if defaultBase64Code vlessws 443 safe-user '11111111-1111-1111-1111-111111111111' example.com $'/ws\nproxy-groups:' >/dev/null 2>&1; then
            return 1
        fi
        if defaultBase64Code vlessws 443 safe-user '11111111-1111-1111-1111-111111111111' example.com ../ws >/dev/null 2>&1; then
            return 1
        fi
        if regressionFindHasMatches "${localDir}" -mindepth 2 -type f; then
            return 1
        fi
    )

    clashMetaConfig() {
        find "${userTmpRoot}" -maxdepth 1 -type d -name 'padm-subscribe-user.*' -print >>"${stageMarker}" 2>/dev/null || true
        originalClashMetaConfig "$@"
    }

    writeOldSubscribeOutputs
    writeLocalSubscribeOutputs
    rm -f "${localDir}/default/${email}"
    if renderSubscribeUserOutputs "${email}" "${emailMd5}" "example.com" n true 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
    [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
    [[ "$(<"${publicDir}/sing-box/${emailMd5}")" == "old-sing" ]]

    writeLocalSubscribeOutputs
    export PADM_FAKE_CLASH_META_CONFIG_MODE=fail
    if renderSubscribeUserOutputs "${email}" "${emailMd5}" "example.com" n true 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
    [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
    [[ "$(<"${publicDir}/clashMetaProfiles/${emailMd5}")" == "old-profile" ]]
    [[ "$(<"${publicDir}/sing-box/${emailMd5}")" == "old-sing" ]]
    unset PADM_FAKE_CLASH_META_CONFIG_MODE

    printf '{bad json\n' >"${localDir}/sing-box/${email}"
    if renderSubscribeUserOutputs "${email}" "${emailMd5}" "example.com" n true 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
    [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
    [[ "$(<"${publicDir}/sing-box/${emailMd5}")" == "old-sing" ]]

    writeOldSubscribeOutputs
    writeLocalSubscribeOutputs
    (
        local downloadMarker="${root}/sing-box-template-download.log"
        SCRIPT_DIR="${root}/missing-sing-box-template"
        downloadFile() {
            printf 'download\n' >"${downloadMarker}"
            [[ "$1" == "-O" ]] || return 1
            cp "${PROJECT_ROOT}/documents/sing-box.json" "$2"
        }
        if renderSubscribeUserOutputs "${email}" "${emailMd5}" "example.com" n true 2>/dev/null; then
            return 1
        fi
        [[ ! -e "${downloadMarker}" ]]
    )
    [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
    [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
    [[ "$(<"${publicDir}/clashMetaProfiles/${emailMd5}")" == "old-profile" ]]
    [[ "$(<"${publicDir}/sing-box_profiles/${emailMd5}")" == "old-sing-profile" ]]
    [[ "$(<"${publicDir}/sing-box/${emailMd5}")" == "old-sing" ]]
    if regressionFindHasMatches "${userTmpRoot}" -mindepth 1 -maxdepth 1 -type d; then
        return 1
    fi

    writeOldSubscribeOutputs
    writeLocalSubscribeOutputs
    (
        currentHost=example.com
        subscribePort=
        currentDefaultPort=443
        renderSubscribeUserOutputs() {
            return 1
        }
        if renderAllSubscribeUserOutputs "${localDir}" renew true 2>/dev/null; then
            return 1
        fi
    )

    writeOldSubscribeOutputs
    writeLocalSubscribeOutputs
    (
        subscriptionRemoteScopeEnabled() { return 0; }
        stageRemoteSubscribe() {
            return 1
        }
        if renderSubscribeUserOutputs "${email}" "${emailMd5}" "example.com" y true 2>/dev/null; then
            return 1
        fi
    )
    [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
    [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
    [[ "$(<"${publicDir}/sing-box/${emailMd5}")" == "old-sing" ]]

    writeOldSubscribeOutputs
    rm -f "${localDir}/default/${email}" "${localDir}/clashMeta/${email}" "${localDir}/sing-box/${email}"
    (
        subscriptionRemoteScopeEnabled() { return 0; }
        stageRemoteSubscribe() {
            mkdir -p "${PADM_SUBSCRIBE_DIR}/default" "${PADM_SUBSCRIBE_DIR}/clashMeta" "${localDir}/sing-box"
            printf 'vless://remote-node#atomic-user_remote\n' >"${PADM_SUBSCRIBE_DIR}/default/${emailMd5}"
            printf '  - name: atomic-user_remote\n    type: vless\n' >"${PADM_SUBSCRIBE_DIR}/clashMeta/${emailMd5}"
            printf '[{"tag":"atomic-user_remote","type":"direct"}]\n' >"${localDir}/sing-box/${email}"
            return 0
        }
        renderSubscribeUserOutputs "${email}" "${emailMd5}" "example.com" y true
    )
    [[ "$(base64 -d <"${publicDir}/default/${emailMd5}")" == "vless://remote-node#atomic-user_remote" ]]
    grep -q 'atomic-user_remote' "${publicDir}/clashMeta/${emailMd5}"
    jq -e '.outbounds[] | select(.tag == "atomic-user_remote")' "${publicDir}/sing-box/${emailMd5}" >/dev/null
    jq -e '.[0].tag == "atomic-user_remote"' "${publicDir}/sing-box_profiles/${emailMd5}" >/dev/null

    writeOldSubscribeOutputs
    writeLocalSubscribeOutputs
    (
        commitSubscribeUserOutputFile() {
            return 1
        }
        if renderSubscribeUserOutputs "${email}" "${emailMd5}" "example.com" n true 2>/dev/null; then
            return 1
        fi
    )
    [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
    [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
    [[ "$(<"${publicDir}/sing-box/${emailMd5}")" == "old-sing" ]]

    writeOldSubscribeOutputs
    writeLocalSubscribeOutputs
    (
        local publishStage="${root}/publish-stage"
        local commitCalls=0
        mkdir -p "${publishStage}"
        cp -a "${publicDir}/." "${publishStage}/"
        checkLogBackupCreate() {
            return 97
        }
        commitSubscribeUserOutputFile() {
            commitCalls=$((commitCalls + 1))
            if [[ "${commitCalls}" == "2" ]]; then
                return 1
            fi
            originalCommitSubscribeUserOutputFile "$@"
        }
        if PADM_SUBSCRIBE_DIR="${publishStage}" renderSubscribeUserOutputs "${email}" "${emailMd5}" "example.com" n true 2>/dev/null; then
            return 1
        fi
        [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
        [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
        [[ "$(<"${publicDir}/clashMetaProfiles/${emailMd5}")" == "old-profile" ]]
        [[ "$(<"${publicDir}/sing-box_profiles/${emailMd5}")" == "old-sing-profile" ]]
        [[ "$(<"${publicDir}/sing-box/${emailMd5}")" == "old-sing" ]]
        rm -rf "${publishStage}"
    )

    writeLocalSubscribeOutputs
    renderSubscribeUserOutputs "${email}" "${emailMd5}" "example.com" n true
    grep -q . "${stageMarker}"
    while IFS= read -r path; do
        [[ -z "${path}" || "${path}" == "${userTmpRoot}"/padm-subscribe-user.* ]] || return 1
    done <"${stageMarker}"
    if regressionFindHasMatches "${userTmpRoot}" -mindepth 1 -maxdepth 1 -type d; then
        return 1
    fi
    [[ "$(base64 -d <"${publicDir}/default/${emailMd5}")" == "vless://new-node#atomic-user" ]]
    grep -q '^proxies:$' "${publicDir}/clashMeta/${emailMd5}"
    grep -q 'atomic-user' "${publicDir}/clashMeta/${emailMd5}"
    jq -e '.outbounds[] | select(.tag == "atomic-user")' "${publicDir}/sing-box/${emailMd5}" >/dev/null
    jq -e '.outbounds[] | select(has("outbounds")) | .outbounds | index("atomic-user")' "${publicDir}/sing-box/${emailMd5}" >/dev/null
    jq -e '.[0].tag == "atomic-user"' "${publicDir}/sing-box_profiles/${emailMd5}" >/dev/null
    [[ ! -e "${publicDir}/sing-box/${emailMd5}_tmp" ]]

    rm -f "${localDir}/subscribeSalt"
    subscribeSalt=
    resolveSubscribeSalt "${localDir}/subscribeSalt" renew
    [[ -s "${localDir}/subscribeSalt" ]]
    [[ "${subscribeSalt}" =~ ^[0-9a-f]{32}$ ]]
    [[ "$(<"${localDir}/subscribeSalt")" == "${subscribeSalt}" ]]

    subscribeDomain=subscribe.example.com
    currentHost=
    subscribePort=38813
    subscribeType=https
    [[ "$(resolveSubscribePublicDomain)" == "subscribe.example.com" ]]

    subscribeDomain=
    currentHost=
    if [[ -n "$(resolveSubscribePublicDomain)" ]]; then
        return 1
    fi

    currentHost=current.example.com
    [[ "$(resolveSubscribePublicDomain)" == "current.example.com" ]]

    if [[ -n "${oldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${oldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
    if [[ -n "${oldPublicDir}" ]]; then export PADM_SUBSCRIBE_DIR="${oldPublicDir}"; else unset PADM_SUBSCRIBE_DIR; fi
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    SCRIPT_DIR="${oldScriptDir}"
}

runRemoveUserSubscriptionMenuFailureRegression() (
    local root="${TMP_DIR}/remove-user-subscription-menu-failure"
    local callLog="${root}/calls.log"
    local successLog="${root}/success.log"
    local statusLog="${root}/status.log"
    local errorLog="${root}/error.log"
    local helperLog="${root}/helper.log"
    local backupDir="${root}/backup"
    local mode rc

    mkdir -p "${root}"
    : >"${callLog}"
    : >"${successLog}"
    : >"${statusLog}"
    : >"${errorLog}"
    : >"${helperLog}"

    autoRead() {
        printf -v "$3" 'yes'
    }
    subscriptionGroupsFile() {
        printf '%s\n' "${root}/groups.json"
    }
    subscriptionGroupsStateRead() {
        [[ "${mode}" != "groups-read-fail" ]] || return 1
        printf '{"version":2,"active_group":"default","groups":[{"id":"default","user_groups":[{"id":"team-a","enabled":true}]}]}\n'
    }
    subscriptionSyncCreateConfigBackups() {
        local resultVar=$1
        printf 'backup-create\n' >>"${callLog}"
        [[ "${mode}" != "backup-fail" ]] || return 1
        mkdir -p "${backupDir}"
        printf -v "${resultVar}" '%s' "${backupDir}"
    }
    subscriptionSyncAccountName() {
        printf 'sub_%s\n' "$1"
    }
    removeUserSubscriptionState() {
        printf 'state:%s\n' "$1" >>"${callLog}"
        [[ "${mode}" != "state-fail" ]]
    }
    subscriptionSyncRemoveAccount() {
        printf 'account:%s\n' "$1" >>"${callLog}"
        [[ "${mode}" != "account-fail" && "${mode}" != "state-restore-fail" && "${mode}" != "account-restore-fail" && "${mode}" != "both-restore-fail" ]]
    }
    subscriptionGroupsStateWrite() {
        printf 'state-restore\n' >>"${callLog}"
        [[ "${mode}" != "state-restore-fail" && "${mode}" != "both-restore-fail" ]]
    }
    subscriptionSyncRestoreConfigBackups() {
        printf 'account-restore:%s\n' "$1" >>"${callLog}"
        [[ "${mode}" != "account-restore-fail" && "${mode}" != "both-restore-fail" ]]
    }
    padmRemoveCleanupPath() {
        printf 'cleanup:%s\n' "$1" >>"${callLog}"
    }
    padmForgetCleanupPath() {
        printf 'keep-backup:%s\n' "$1" >>"${callLog}"
    }
    reloadCore() {
        printf 'reload\n' >>"${callLog}"
        [[ "${mode}" != "reload-fail" ]]
    }
    subscriptionGroupSyncEnabled() {
        return 0
    }
    runSubscriptionGroupSync() {
        printf 'sync:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" != "sync-fail" ]]
    }
    successCard() {
        printf '%s\n' "$*" >>"${successLog}"
    }
    statusCard() {
        printf '%s\n' "$*" >>"${statusLog}"
    }
    warnCard() {
        printf '%s\n' "$*" >>"${statusLog}"
    }
    errorCard() {
        printf '%s\n' "$*" >>"${errorLog}"
    }
    subscriptionSyncSetManualCheckMessage() {
        printf "manual-check:%s|%s\n" "$2" "$3" >>"${helperLog}"
        printf -v "$1" "%s，请手动检查%s" "$2" "$3"
    }
    runRemoveCase() {
        mode=$1
        : >"${callLog}"
        : >"${successLog}"
        : >"${statusLog}"
        : >"${errorLog}"
        : >"${helperLog}"
        set +e
        removeUserSubscriptionMenu team-a >/dev/null 2>&1
        rc=$?
        set -e
    }

    runRemoveCase groups-read-fail
    [[ "${rc}" == "1" ]]
    ! grep -q '^backup-create$' "${callLog}"
    ! grep -q '^sync:' "${callLog}"
    grep -q "manual-check:读取当前订阅状态失败| ${root}/groups.json" "${helperLog}"
    grep -q "读取当前订阅状态失败，请手动检查 ${root}/groups.json" "${errorLog}"
    [[ ! -s "${successLog}" ]]

    runRemoveCase backup-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'backup-create' "${callLog}"
    ! grep -q '^state:' "${callLog}"
    ! grep -q '^sync:' "${callLog}"
    grep -q "manual-check:删除订阅前托管账号配置备份失败|本机配置" "${helperLog}"
    grep -q "删除订阅前托管账号配置备份失败，请手动检查本机配置" "${errorLog}"
    [[ ! -s "${successLog}" ]]

    runRemoveCase state-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'backup-create' "${callLog}"
    grep -qx 'state:team-a' "${callLog}"
    ! grep -q '^account:' "${callLog}"
    ! grep -qx 'reload' "${callLog}"
    ! grep -q '^sync:' "${callLog}"
    grep -qx "cleanup:${backupDir}" "${callLog}"
    [[ ! -s "${successLog}" ]]

    runRemoveCase account-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'backup-create' "${callLog}"
    grep -qx 'state:team-a' "${callLog}"
    grep -qx 'account:sub_team-a' "${callLog}"
    ! grep -qx 'reload' "${callLog}"
    ! grep -q '^sync:' "${callLog}"
    grep -qx 'state-restore' "${callLog}"
    grep -qx "account-restore:${backupDir}" "${callLog}"
    grep -qx "cleanup:${backupDir}" "${callLog}"
    grep -q '托管账号配置移除失败，已恢复旧配置' "${errorLog}"
    [[ ! -s "${successLog}" ]]

    runRemoveCase reload-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'backup-create' "${callLog}"
    grep -qx 'state:team-a' "${callLog}"
    grep -qx 'account:sub_team-a' "${callLog}"
    [[ "$(grep -c '^reload$' "${callLog}")" == "2" ]]
    ! grep -q '^sync:' "${callLog}"
    grep -qx 'state-restore' "${callLog}"
    grep -qx "account-restore:${backupDir}" "${callLog}"
    grep -qx "cleanup:${backupDir}" "${callLog}"
    ! grep -q '^sync:' "${callLog}"
    grep -q '恢复旧配置后核心重载仍失败' "${errorLog}"
    [[ ! -s "${successLog}" ]]

    runRemoveCase state-restore-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'state:team-a' "${callLog}"
    grep -qx 'account:sub_team-a' "${callLog}"
    grep -qx 'state-restore' "${callLog}"
    grep -qx "account-restore:${backupDir}" "${callLog}"
    grep -qx "cleanup:${backupDir}" "${callLog}"
    grep -q '订阅状态恢复失败' "${errorLog}"
    [[ ! -s "${successLog}" ]]

    runRemoveCase account-restore-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'state:team-a' "${callLog}"
    grep -qx 'account:sub_team-a' "${callLog}"
    grep -qx 'state-restore' "${callLog}"
    grep -qx "account-restore:${backupDir}" "${callLog}"
    grep -qx "keep-backup:${backupDir}" "${callLog}"
    ! grep -q '^sync:' "${callLog}"
    grep -q '托管账号配置恢复失败' "${errorLog}"
    [[ ! -s "${successLog}" ]]

    runRemoveCase both-restore-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'state:team-a' "${callLog}"
    grep -qx 'account:sub_team-a' "${callLog}"
    grep -qx 'state-restore' "${callLog}"
    grep -qx "account-restore:${backupDir}" "${callLog}"
    grep -qx "keep-backup:${backupDir}" "${callLog}"
    ! grep -q '^sync:' "${callLog}"
    grep -q '订阅状态与托管账号配置恢复失败' "${errorLog}"
    [[ ! -s "${successLog}" ]]

    runRemoveCase success
    [[ "${rc}" == "0" ]]
    grep -qx "cleanup:${backupDir}" "${callLog}"
    grep -qx 'reload' "${callLog}"
    grep -qx 'sync:' "${callLog}"
    grep -q '用户订阅已删除' "${successLog}"

    runRemoveCase sync-fail
    [[ "${rc}" == "0" ]]
    grep -qx "cleanup:${backupDir}" "${callLog}"
    grep -qx 'reload' "${callLog}"
    grep -qx 'sync:' "${callLog}"
    grep -q '用户订阅已删除' "${successLog}"
    grep -q '变更已保存，但后置完整同步失败' "${statusLog}"
)

runUserSubscriptionMenuMutationFailureRegression() (
    local root="${TMP_DIR}/user-subscription-menu-mutation-failure"
    local callLog="${root}/calls.log"
    local successLog="${root}/success.log"
    local statusLog="${root}/status.log"
    local errorLog="${root}/error.log"
    local mode rc menuStep=0

    mkdir -p "${root}"
    : >"${callLog}"
    : >"${successLog}"
    : >"${statusLog}"
    : >"${errorLog}"

    resetLogs() {
        : >"${callLog}"
        : >"${successLog}"
        : >"${statusLog}"
        : >"${errorLog}"
        menuStep=0
    }
    autoRead() {
        local key=$1
        local targetVar=$3
        case "${key}" in
        user_subscription_id) printf -v "${targetVar}" 'team-new' ;;
        user_subscription_sources)
            if [[ "${mode}" == "empty-sources" ]]; then
                printf -v "${targetVar}" ', ,'
            elif [[ "${mode}" == "invalid-source" ]]; then
                printf -v "${targetVar}" 'main,missing-source'
            else
                printf -v "${targetVar}" 'main,remote-a'
            fi
            ;;
        user_subscription_traffic_limit) printf -v "${targetVar}" '100' ;;
        user_subscription_item_menu)
            menuStep=$((menuStep + 1))
            if [[ "${menuStep}" == "1" ]]; then
                printf -v "${targetVar}" '6'
            else
                printf -v "${targetVar}" '9'
            fi
            ;;
        *) printf -v "${targetVar}" '' ;;
        esac
    }
    subscriptionSyncAccountName() {
        printf 'sub_%s\n' "$1"
    }
    subscribe() {
        printf 'subscribe:%s|%s|%s|%s\n' "${1:-}" "${2:-}" "${3:-}" "${4:-}" >>"${callLog}"
        [[ "${mode}" != "subscribe-fail" ]]
    }
    ensureSubscriptionServiceForSharedLinks() {
        [[ "${mode}" != "service-install-fail" ]] || return 2
    }
    addUserSubscriptionState() {
        printf 'create:%s:%s:%s:%s\n' "$1" "$2" "$3" "$4" >>"${callLog}"
        [[ "${mode}" != "create-state-fail" ]]
    }
    setUserSubscriptionSources() {
        printf 'sources:%s:%s\n' "$1" "$2" >>"${callLog}"
        [[ "${mode}" != "sources-fail" ]]
    }
    setUserSubscriptionTrafficLimit() {
        printf 'limit:%s:%s\n' "$1" "$2" >>"${callLog}"
        [[ "${mode}" != "limit-fail" ]]
    }
    runSubscriptionGroupSync() {
        printf 'sync:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" != "sync-fail" ]]
    }
    subscriptionGroupSyncEnabled() { [[ "${mode}" != "auto-disabled" ]]; }
    selectUserSubscriptionId() {
        selectedUserSubscriptionId=team-a
    }
    showUserSubscriptions() { return 0; }
    showUserSubscriptionTraffic() { return 0; }
    showSubscriptionLocalSyncPlan() { return 0; }
    subscriptionCurrentRoleNormalized() { printf 'main\n'; }
    subscriptionRequireMainRole() { return 0; }
    subscriptionActiveGroupRead() {
        if [[ "$*" == *'.sync'* ]]; then
            printf '{}\n'
        elif [[ "$*" == *'.sources[]?.id'* ]]; then
            printf '%s\n' main remote-a
        else
            printf '%s\n' \
                'main:Main:main:local:127.0.0.1:0:true:local' \
                'remote-a:Remote A:secondary:wireguard:10.77.0.2:39778:true:success'
        fi
    }
    removeUserSubscriptionMenu() { return 0; }
    toggleUserSubscriptionState() {
        printf 'toggle:%s\n' "$1" >>"${callLog}"
        [[ "${mode}" != "toggle-fail" ]]
    }
    userResultCard() { return 0; }
    successCard() {
        printf '%s\n' "$*" >>"${successLog}"
    }
    statusCard() {
        printf '%s\n' "$*" >>"${statusLog}"
    }
    warnCard() {
        printf '%s\n' "$*" >>"${statusLog}"
    }
    errorCard() {
        printf '%s\n' "$*" >>"${errorLog}"
    }

    mode=auto-disabled
    resetLogs
    runSubscriptionSyncAfterMutation "test-disabled" >/dev/null 2>&1
    ! grep -q '^sync:' "${callLog}"
    grep -q '自动同步已关闭，等待手动完整同步' "${statusLog}"

    mode=service-install-fail
    resetLogs
    set +e
    createAndSyncUserSubscriptionWizard >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    ! grep -q '^create:' "${callLog}"

    mode=create-state-fail
    resetLogs
    set +e
    createAndSyncUserSubscriptionWizard >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qxF 'create:team-new:team-new:["main","remote-a"]:100' "${callLog}"
    grep -q '分享订阅创建失败' "${errorLog}"
    ! grep -q '分享订阅已创建' "${statusLog}"
    ! grep -q '^sync:' "${callLog}"

    mode=success
    resetLogs
    runSubscriptionSyncAfterMutation "test-enabled" >/dev/null 2>&1
    grep -qx 'sync:' "${callLog}"

    mode=subscribe-fail
    resetLogs
    set +e
    showUserSubscriptionLinks team-a >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'subscribe:false||sub_team-a|true' "${callLog}"
    grep -q '订阅输出刷新失败' "${errorLog}"
    [[ ! -s "${statusLog}" ]]

    mode=empty-sources
    resetLogs
    set +e
    setUserSubscriptionSourcesMenu team-a >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    ! grep -q '^sources:team-a:' "${callLog}"
    grep -q '服务器范围不能为空' "${errorLog}"
    [[ ! -s "${successLog}" ]]

    mode=invalid-source
    resetLogs
    set +e
    setUserSubscriptionSourcesMenu team-a >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    ! grep -q '^sources:team-a:' "${callLog}"
    grep -q '服务器范围包含不存在的服务器源' "${errorLog}"
    [[ ! -s "${successLog}" ]]

    mode=sources-fail
    resetLogs
    set +e
    setUserSubscriptionSourcesMenu team-a >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -q '^sources:team-a:' "${callLog}"
    grep -q '节点范围更新失败' "${errorLog}"
    [[ ! -s "${successLog}" ]]

    mode=limit-fail
    resetLogs
    set +e
    setUserSubscriptionTrafficLimitMenu team-a >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'limit:team-a:100' "${callLog}"
    grep -q '订阅额度更新失败' "${errorLog}"
    [[ ! -s "${successLog}" ]]

    mode=toggle-fail
    resetLogs
    manageUserSubscriptionItem >/dev/null 2>&1
    grep -qx 'toggle:team-a' "${callLog}"
    grep -q '用户订阅状态切换失败' "${errorLog}"
    ! grep -q '用户订阅状态已切换' "${successLog}"

    mode=sync-fail
    resetLogs
    set +e
    runSubscriptionSyncAfterMutation "test-failure" >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'sync:' "${callLog}"
    grep -q '变更已保存，但后置完整同步失败' "${statusLog}"

    mode=success
    resetLogs
    showUserSubscriptionLinks team-a >/dev/null 2>&1
    grep -q '用户订阅链接' "${statusLog}"
    resetLogs
    setUserSubscriptionSourcesMenu team-a >/dev/null 2>&1
    grep -q '节点范围已更新' "${successLog}"
    grep -qx 'sync:' "${callLog}"
    resetLogs
    setUserSubscriptionTrafficLimitMenu team-a >/dev/null 2>&1
    grep -q '订阅额度已更新' "${successLog}"
    grep -qx 'sync:' "${callLog}"
    resetLogs
    manageUserSubscriptionItem >/dev/null 2>&1
    grep -q '用户订阅状态已切换' "${successLog}"
    grep -qx 'sync:' "${callLog}"
)

runRemoteSubscribeSnapshotRegression() {
    local publicDir="${TMP_DIR}/remote-subscribe-public"
    local localDir="${TMP_DIR}/remote-subscribe-local"
    local email="sub_team"
    local emailMd5="hash-team"
    local oldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
    local oldPublicDir="${PADM_SUBSCRIBE_DIR:-}"
    local oldTmpDir="${TMPDIR:-}"
    local remoteTmpRoot="${TMP_DIR}/remote-subscribe-tmp"
    local syncSnapshots
    subscriptionRemoteScopeEnabled() { return 0; }
    export PADM_SUBSCRIBE_LOCAL_DIR="${localDir}"
    export PADM_SUBSCRIBE_DIR="${publicDir}"
    TMPDIR="${remoteTmpRoot}"
    rm -rf "${publicDir}" "${localDir}" "${remoteTmpRoot}"
    mkdir -p "${publicDir}/default" "${publicDir}/clashMeta" "${localDir}/sing-box" "${remoteTmpRoot}"
    mkdir -p "$(dirname "$(subscriptionGroupsFile)")"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"r1","name":"Remote 1","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"10.77.0.2","port":39778,"enabled":true,"sync_status":"success","control_token":"token-r1"},{"id":"r2","name":"Remote 2","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"10.77.0.3","port":39778,"enabled":true,"sync_status":"success","control_token":"token-r2"},{"id":"r3","name":"Remote 3","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"10.77.0.4","port":39778,"enabled":true,"sync_status":"success","control_token":"token-r3"}],"user_groups":[{"id":"team","name":"Team","enabled":true,"allowed_sources":["r1","r2","r3"],"traffic_limit_gb":0,"token":"","uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    syncSnapshots=$(jq -cn --arg account "${email}" \
        --arg r1 'vless://uuid@remote1.example:443#sub_team' \
        --arg r2 'vless://uuid@remote2.example:443#sub_team' \
        --arg r3 'trojan://pass@remote3.example:443#sub_team-extra' '
      {
        r1:{($account):{default:($r1 | @base64),clash_meta:"proxies:\n- name: \"sub_team\"\n",sing_box:[{tag:"sub_team"}]}},
        r2:{($account):{default:($r2 | @base64),clash_meta:"proxies:\n- name: \"sub_team\"\n",sing_box:[{tag:"sub_team"}]}},
        r3:{($account):{default:($r3 | @base64),clash_meta:"proxies:\n- name: \"sub_team-extra\"\n",sing_box:[{tag:"sub_team-extra"}]}}
      }
    ') || return 1

    writeRemoteSubscribeOldOutputs() {
        printf 'old-default\n' >"${publicDir}/default/${emailMd5}"
        printf 'old-clash\n' >"${publicDir}/clashMeta/${emailMd5}"
        printf '[{"tag":"old-local"}]\n' >"${localDir}/sing-box/${email}"
    }

    eval "$(declare -f appendUniqueLines | sed '1s/^appendUniqueLines/originalAppendUniqueLines/')"
    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"

    writeRemoteSubscribeOldOutputs
    if stageRemoteSubscribe "${emailMd5}" "${email}" '{}' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
    [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
    jq -e '.[0].tag == "old-local"' "${localDir}/sing-box/${email}" >/dev/null

    writeRemoteSubscribeOldOutputs
    local invalidSnapshots
    invalidSnapshots=$(jq -c '.r2.sub_team.sing_box = []' <<<"${syncSnapshots}") || return 1
    if stageRemoteSubscribe "${emailMd5}" "${email}" "${invalidSnapshots}" 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
    [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
    jq -e 'length == 1 and .[0].tag == "old-local"' "${localDir}/sing-box/${email}" >/dev/null

    writeRemoteSubscribeOldOutputs
    printf '{bad local json\n' >"${localDir}/sing-box/${email}"
    if stageRemoteSubscribe "${emailMd5}" "${email}" "${syncSnapshots}" 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
    [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
    [[ "$(<"${localDir}/sing-box/${email}")" == "{bad local json" ]]
    if regressionFindHasMatches "${remoteTmpRoot}" -mindepth 1 -maxdepth 1 -type d; then
        return 1
    fi

    printf 'vless://new-local@new-target.example:443?security=reality#sub_team\n' >"${publicDir}/default/${emailMd5}"
    printf '  - name: "sub_team"\n    type: vless\n' >"${publicDir}/clashMeta/${emailMd5}"
    printf '[{"tag":"sub_team","type":"vless"}]\n' >"${localDir}/sing-box/${email}"
    stageRemoteSubscribe "${emailMd5}" "${email}" "${syncSnapshots}"
    grep -qxF 'vless://new-local@new-target.example:443?security=reality#sub_team' "${publicDir}/default/${emailMd5}"
    grep -qxF -- '- name: "sub_team_r1"' "${publicDir}/clashMeta/${emailMd5}"
    grep -qxF 'vless://uuid@remote1.example:443#sub_team_r1' "${publicDir}/default/${emailMd5}"
    grep -qxF 'vless://uuid@remote2.example:443#sub_team_r2' "${publicDir}/default/${emailMd5}"
    grep -qxF 'trojan://pass@remote3.example:443#sub_team_r3-extra' "${publicDir}/default/${emailMd5}"
    jq -e '.[0].tag == "sub_team" and .[1].tag == "sub_team_r1" and .[2].tag == "sub_team_r2" and .[3].tag == "sub_team_r3-extra"' "${localDir}/sing-box/${email}" >/dev/null
    [[ ! -e "${publicDir}/default/${emailMd5}.tmp" ]]
    [[ ! -e "${publicDir}/clashMeta/${emailMd5}.tmp" ]]
    [[ ! -e "${localDir}/sing-box/${email}.tmp" ]]

    local disabledStateBackup="${TMP_DIR}/remote-subscribe-disabled-state.backup.json"
    writeRemoteSubscribeOldOutputs
    cp "$(subscriptionGroupsFile)" "${disabledStateBackup}"
    jq '
      .groups[0].sources |= map(if .id == "r2" or .id == "r3" then .enabled = false else . end)
    ' "$(subscriptionGroupsFile)" >"${TMP_DIR}/remote-subscribe-disabled-state.json"
    mv "${TMP_DIR}/remote-subscribe-disabled-state.json" "$(subscriptionGroupsFile)"
    stageRemoteSubscribe "${emailMd5}" "${email}" "${syncSnapshots}"
    grep -qxF 'vless://uuid@remote1.example:443#sub_team_r1' "${publicDir}/default/${emailMd5}"
    if grep -q 'remote3.example' "${publicDir}/default/${emailMd5}"; then
        return 1
    fi
    jq -e 'length == 2 and .[0].tag == "old-local" and .[1].tag == "sub_team_r1"' "${localDir}/sing-box/${email}" >/dev/null
    cp "${disabledStateBackup}" "$(subscriptionGroupsFile)"

    writeRemoteSubscribeOldOutputs
    (
        local appendCalls=0
        appendUniqueLines() {
            appendCalls=$((appendCalls + 1))
            if [[ "${appendCalls}" == "2" ]]; then
                return 1
            fi
            originalAppendUniqueLines "$@"
        }
        if stageRemoteSubscribe "${emailMd5}" "${email}" "${syncSnapshots}" 2>/dev/null; then
            return 1
        fi
        [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
        [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
        jq -e '.[0].tag == "old-local"' "${localDir}/sing-box/${email}" >/dev/null
        [[ ! -e "${publicDir}/default/${emailMd5}.tmp" ]]
        [[ ! -e "${publicDir}/clashMeta/${emailMd5}.tmp" ]]
        [[ ! -e "${localDir}/sing-box/${email}.tmp" ]]
    )

    writeRemoteSubscribeOldOutputs
    (
        local commitCalls=0
        commitGeneratedFile() {
            commitCalls=$((commitCalls + 1))
            if [[ "${commitCalls}" == "2" ]]; then
                return 1
            fi
            originalCommitGeneratedFile "$@"
        }
        if stageRemoteSubscribe "${emailMd5}" "${email}" "${syncSnapshots}" 2>/dev/null; then
            return 1
        fi
        [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
        [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
        jq -e '.[0].tag == "old-local"' "${localDir}/sing-box/${email}" >/dev/null
        [[ ! -e "${publicDir}/default/${emailMd5}.tmp" ]]
        [[ ! -e "${publicDir}/clashMeta/${emailMd5}.tmp" ]]
        [[ ! -e "${localDir}/sing-box/${email}.tmp" ]]
        if regressionFindHasMatches "${remoteTmpRoot}" -mindepth 1 -maxdepth 1 -type d; then
            return 1
        fi
    )

    writeRemoteSubscribeOldOutputs
    stageRemoteSubscribe "${emailMd5}" "${email}" "${syncSnapshots}"
    stageRemoteSubscribe "${emailMd5}" "${email}" "${syncSnapshots}"
    [[ "$(grep -cFx -- '- name: "sub_team_r1"' "${publicDir}/clashMeta/${emailMd5}")" == "1" ]]
    [[ "$(grep -cFx 'vless://uuid@remote1.example:443#sub_team_r1' "${publicDir}/default/${emailMd5}")" == "1" ]]
    [[ "$(grep -cFx 'vless://uuid@remote2.example:443#sub_team_r2' "${publicDir}/default/${emailMd5}")" == "1" ]]
    [[ "$(grep -cFx 'trojan://pass@remote3.example:443#sub_team_r3-extra' "${publicDir}/default/${emailMd5}")" == "1" ]]
    jq -e 'length == 4 and .[0].tag == "old-local" and .[1].tag == "sub_team_r1" and .[2].tag == "sub_team_r2" and .[3].tag == "sub_team_r3-extra"' "${localDir}/sing-box/${email}" >/dev/null

    if [[ -n "${oldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${oldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
    if [[ -n "${oldPublicDir}" ]]; then export PADM_SUBSCRIBE_DIR="${oldPublicDir}"; else unset PADM_SUBSCRIBE_DIR; fi
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}
