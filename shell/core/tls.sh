#!/usr/bin/env bash

acmeAccountFile() {
    printf '%s\n' "$(acmeHomeDir)/account.conf"
}

acmeInstallTargetIsSafe() {
    local acmeDir homeDir expectedOwner path owner mode
    acmeDir=$(acmeSafeHomeDir) || return 1
    homeDir=$(dirname -- "${acmeDir}")
    expectedOwner=$(id -u) || return 1
    [[ -d "${homeDir}" ]] || return 1
    for path in "${homeDir}" "${acmeDir}" "${acmeDir}/dnsapi"; do
        [[ ! -L "${path}" && ( ! -e "${path}" || -d "${path}" ) ]] || return 1
    done
    for path in "${acmeDir}/acme.sh" "${acmeDir}/account.conf" \
        "${acmeDir}/dnsapi/dns_cf.sh" "${acmeDir}/dnsapi/dns_ali.sh"; do
        [[ ! -L "${path}" && ( ! -e "${path}" || -f "${path}" ) ]] || return 1
    done
    for path in "${homeDir}" "${acmeDir}" "${acmeDir}/dnsapi" \
        "${acmeDir}/acme.sh" "${acmeDir}/account.conf" \
        "${acmeDir}/dnsapi/dns_cf.sh" "${acmeDir}/dnsapi/dns_ali.sh"; do
        [[ -e "${path}" ]] || continue
        owner=$(stat --format=%u -- "${path}") || return 1
        mode=$(stat --format=%a -- "${path}") || return 1
        [[ "${owner}" == "${expectedOwner}" && "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
        (( (8#${mode} & 8#22) == 0 )) || return 1
    done
}

acmeExecutable() {
    local acmeDir executable
    acmeInstallTargetIsSafe || return 1
    acmeDir=$(acmeSafeHomeDir) || return 1
    executable="${acmeDir}/acme.sh"
    [[ -s "${executable}" && -x "${executable}" ]] || return 1
    printf '%s\n' "${executable}"
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

tlsCertificatePairUsable() {
    local tlsDir=$1
    local certDomain=$2
    tlsCertificateFilesUsable "${tlsDir}/${certDomain}.crt" "${tlsDir}/${certDomain}.key" "${certDomain}"
}

tlsCertificateDateEpoch() {
    local value=$1 epoch
    [[ -n "${value}" ]] || return 1
    epoch=$(LC_ALL=C date -d "${value}" +%s 2>/dev/null) &&
        [[ "${epoch}" =~ ^-?[0-9]+$ ]] && {
            printf '%s\n' "${epoch}"
            return 0
        }
    [[ "${value}" == *" GMT" ]] || return 1
    value=${value% GMT}
    epoch=$(LC_ALL=C date -u -D '%b %e %H:%M:%S %Y' -d "${value}" +%s 2>/dev/null) || return 1
    [[ "${epoch}" =~ ^-?[0-9]+$ ]] || return 1
    printf '%s\n' "${epoch}"
}

tlsCertificateFilesUsable() {
    local certFile=$1 keyFile=$2 certDomain=$3
    local certDigest keyDigest startDate startTime currentTime
    tlsDomainNameIsSafe "${certDomain}" || return 1
    [[ -s "${certFile}" && -s "${keyFile}" ]] || return 1
    command -v openssl >/dev/null 2>&1 || return 1
    openssl x509 -in "${certFile}" -noout >/dev/null 2>&1 &&
        openssl x509 -in "${certFile}" -checkend 0 -noout >/dev/null 2>&1 &&
        openssl x509 -in "${certFile}" -checkhost "${certDomain}" -noout >/dev/null 2>&1 &&
        openssl pkey -in "${keyFile}" -check -noout >/dev/null 2>&1 || return 1
    startDate=$(openssl x509 -in "${certFile}" -startdate -noout 2>/dev/null) || return 1
    [[ "${startDate}" == notBefore=* ]] || return 1
    startTime=$(tlsCertificateDateEpoch "${startDate#notBefore=}") &&
        currentTime=$(date +%s) &&
        [[ "${startTime}" =~ ^-?[0-9]+$ && "${currentTime}" =~ ^[0-9]+$ ]] &&
        (( startTime <= currentTime )) || return 1
    certDigest=$(openssl x509 -in "${certFile}" -pubkey -noout 2>/dev/null |
        openssl pkey -pubin -outform DER 2>/dev/null |
        openssl dgst -sha256 2>/dev/null) || return 1
    keyDigest=$(openssl pkey -in "${keyFile}" -pubout -outform DER 2>/dev/null |
        openssl dgst -sha256 2>/dev/null) || return 1
    [[ -n "${certDigest}" && "${certDigest}" == "${keyDigest}" ]]
}

# 源证书可直接同步时不重走签发；显式签发参数仍按用户选择处理。
tlsAcmeSourceCertificateReusable() {
    local certDomain=$1 acmeDomain sourceDir
    [[ -z "${AUTO_TLS_CA:-}${AUTO_DNS_API:-}${AUTO_DNS_API_TYPE:-}${AUTO_DNS_API_WILDCARD:-}" ]] || return 1
    # 单域名源失效时再查通配符，并把同一源交给后续同步。
    for acmeDomain in "${certDomain}" "*.${certDomain#*.}"; do
        sourceDir="$(acmeHomeDir)/${acmeDomain}_ecc"
        if tlsCertificateFilesUsable "${sourceDir}/${acmeDomain}.cer" "${sourceDir}/${acmeDomain}.key" "${certDomain}" &&
            openssl x509 -in "${sourceDir}/${acmeDomain}.cer" -checkend 86400 -noout >/dev/null 2>&1; then
            installedDNSAPIStatus=
            dnsTLSDomain=${certDomain#*.}
            [[ "${acmeDomain}" == "${certDomain}" ]] || installedDNSAPIStatus=true
            return 0
        fi
    done
    return 1
}

tlsAcmeConfigValue() {
    local configFile=$1
    local key=$2
    awk -v key="${key}" '
      index($0, key "=") == 1 {
        value = substr($0, length(key) + 2)
        if ((substr(value, 1, 1) == "\047" && substr(value, length(value), 1) == "\047") ||
            (substr(value, 1, 1) == "\"" && substr(value, length(value), 1) == "\"")) {
          value = substr(value, 2, length(value) - 2)
        }
        print value
        exit
      }
    ' "${configFile}"
}

tlsAcmeManagedCertificateRecords() {
    local acmeDir tlsDir configFile certFile keyFile certDomain configFiles
    local -A seen=()
    acmeDir=$(acmeSafeHomeDir) || return 1
    tlsDir=$(tlsManagedDir) || return 1
    [[ -d "${acmeDir}" ]] || return 0
    configFiles=$(find "${acmeDir}" -mindepth 2 -maxdepth 2 -type f -name '*.conf' -print) || return 1
    configFiles=$(LC_ALL=C sort <<<"${configFiles}") || return 1
    while IFS= read -r configFile; do
        [[ -n "${configFile}" ]] || continue
        certFile=$(tlsAcmeConfigValue "${configFile}" Le_RealFullChainPath) || return 1
        keyFile=$(tlsAcmeConfigValue "${configFile}" Le_RealKeyPath) || return 1
        [[ "${certFile}" == "${tlsDir}/"*.crt ]] || continue
        certDomain=$(basename -- "${certFile}" .crt)
        tlsDomainNameIsSafe "${certDomain}" || continue
        [[ "${keyFile}" == "${tlsDir}/${certDomain}.key" ]] || continue
        [[ -z "${seen[${certDomain}]+x}" ]] || continue
        seen["${certDomain}"]=1
        printf '%s\t%s\t%s\t%s\n' "${certDomain}" "${configFile}" "${certFile}" "${keyFile}"
    done <<<"${configFiles}"
}

tlsCertificateManagedByAcme() {
    local certDomain=$1
    local domain _ records
    records=$(tlsAcmeManagedCertificateRecords) || return 2
    while IFS=$'\t' read -r domain _; do
        [[ "${domain}" == "${certDomain}" ]] && return 0
    done <<<"${records}"
    return 1
}

# 自定义 Email
customSSLEmail() {
    local accountFile accountStage retryEmail=false sslEmailStatus nextSSLEmail
    accountFile=$(acmeAccountFile)
    if [[ "${1:-}" == *"validate email"* ]]; then
        autoRead tls_email_retry "是否重新输入邮箱地址[y/n]:" sslEmailStatus || return 1
        if [[ "$(normalizeYesNo "${sslEmailStatus}")" == "y" ]]; then
            retryEmail=true
        else
            return 1
        fi
    fi

    if [[ -d "$(acmeHomeDir)" && -f "${accountFile}" ]]; then
        if [[ "${retryEmail}" == "true" ]] || { ! grep -q "ACCOUNT_EMAIL" <"${accountFile}" && ! echo "${sslType}" | grep -q "letsencrypt"; }; then
            while true; do
                autoRead tls_account_email "请输入邮箱地址:" nextSSLEmail || return 1
                tlsEmailAddressIsSafe "${nextSSLEmail}" && break
                echoContent yellow "请重新输入正确的邮箱格式[例: username@example.com]"
                [[ -z "${AUTO_INSTALL:-}" ]] || return 1
            done
            padmCreateTempFileForTarget accountStage "${accountFile}" account || return 1
            if ! sed '/ACCOUNT_EMAIL/d' "${accountFile}" >"${accountStage}" || ! printf "ACCOUNT_EMAIL='%s'\n" "${nextSSLEmail}" >>"${accountStage}"; then
                padmRemoveCleanupPath "${accountStage}"
                return 1
            fi
            commitGeneratedFile "${accountStage}" "${accountFile}" 600 || { padmRemoveCleanupPath "${accountStage}"; return 1; }
            sslEmail=${nextSSLEmail}
            successCard "添加完毕"
        fi
    fi

}

# DNS API申请证书
switchDNSAPI() {
    local nextDNSAPIStatus selectDNSAPIType nextDNSAPIType
    autoRead dns_api "是否使用DNS API申请证书[支持NAT]？[y/n]:" nextDNSAPIStatus || return 1
    nextDNSAPIStatus=$(normalizeYesNo "${nextDNSAPIStatus}")
    if [[ "${nextDNSAPIStatus}" == "y" ]]; then
        echoContent title "\n┌─ DNS API ──────────────────────────────────────────"
        menuRecommendedItem 1 "cloudflare" "默认 DNS API"
        menuItem 2 "aliyun" "阿里云 DNS API"
        menuClose
        autoRead dns_api_type "请选择[回车]使用默认:" selectDNSAPIType || return 1
        case ${selectDNSAPIType} in
        2)
            nextDNSAPIType="aliyun"
            ;;
        *)
            nextDNSAPIType="cloudflare"
            ;;
        esac
        initDNSAPIConfig "${nextDNSAPIType}" || return 1
        dnsAPIType=${nextDNSAPIType}
    else
        dnsAPIStatus=${nextDNSAPIStatus}
        dnsAPIType=
    fi
}

# 初始化 DNS API 配置
initDNSAPIConfig() {
    local apiToken apiZone apiKey apiSecret wildcardStatus
    if [[ "$1" == "cloudflare" ]]; then
        echoContent title "\n┌─ Cloudflare DNS API ──────────────────────────────"
        menuLine "请创建限制到目标 Zone 的 API Token"
        menuLine "权限建议：Zone:DNS:Edit；如需自动识别 Zone，可附加 Zone:Zone:Read"
        menuClose
        while :; do
            autoRead cloudflare_api_token "请输入API Token:" apiToken || return 1
            [[ -n "${apiToken}" ]] && break
            errorCard "输入为空，请重新输入"
            [[ -z "${AUTO_INSTALL:-}" ]] || return 1
        done
        autoRead cloudflare_zone_id "请输入Zone ID[可选，回车自动识别]:" apiZone || return 1
    elif [[ "$1" == "aliyun" ]]; then
        while :; do
            autoRead aliyun_api_key "请输入Ali Key:" apiKey || return 1
            [[ -n "${apiKey}" ]] && break
            errorCard "输入为空，请重新输入"
            [[ -z "${AUTO_INSTALL:-}" ]] || return 1
        done
        while :; do
            autoRead aliyun_api_secret "请输入Ali Secret:" apiSecret || return 1
            [[ -n "${apiSecret}" ]] && break
            errorCard "输入为空，请重新输入"
            [[ -z "${AUTO_INSTALL:-}" ]] || return 1
        done
    else
        return 1
    fi
    echo
    while true; do
        autoRead dns_api_wildcard "是否使用*.${dnsTLSDomain}进行API申请通配符证书？[y/n]:" wildcardStatus || return 1
        wildcardStatus=$(normalizeYesNo "${wildcardStatus}")
        [[ "${wildcardStatus}" != y || ( "${dnsTLSDomain}" == *.* && -n "${dnsTLSDomain%%.*}" ) ]] && break
        errorCard "当前域名不支持此通配符，请选择 n 申请单域名证书"
        [[ -z "${AUTO_INSTALL:-}" ]] || return 1
    done
    if [[ "$1" == "cloudflare" ]]; then
        cfAPIToken=${apiToken}
        cfZoneID=${apiZone}
    else
        aliKey=${apiKey}
        aliSecret=${apiSecret}
    fi
    dnsAPIStatus=${wildcardStatus}
}

# 选择ssl安装类型
switchSSLType() {
    local nextSSLType="${sslType:-}" selectSSLType sslTypeFile sslTypeStage
    if [[ -n "${AUTO_INSTALL:-}" ]]; then
        case "${AUTO_TLS_CA:-}" in
        "" | letsencrypt | 1 | zerossl | ZeroSSL | 2 | buypass | Buypass | 3) ;;
        *) errorCard "证书 CA 参数不合法" "${AUTO_TLS_CA}"; return 1 ;;
        esac
    fi
    if [[ -z "${nextSSLType}" ||
        -n "${AUTO_TLS_CA:-}" ||
        ( -n "${dnsAPIType:-}" && "${nextSSLType}" == "buypass" ) ]]; then
        echoContent title "\n┌─ 证书 CA ──────────────────────────────────────────"
        menuRecommendedItem 1 "letsencrypt" "默认 CA"
        menuItem 2 "zerossl" "ZeroSSL CA"
        menuItem 3 "buypass" "不支持 DNS 申请"
        menuClose
        while true; do
            autoRead tls_ca "请选择[回车]使用默认:" selectSSLType || return 1
            case ${selectSSLType} in
            "" | 1) nextSSLType="letsencrypt" ;;
            2) nextSSLType="zerossl" ;;
            3) nextSSLType="buypass" ;;
            *)
                errorCard "请选择 1、2 或 3"
                [[ -z "${AUTO_INSTALL:-}" ]] || return 1
                continue
                ;;
            esac
            if [[ -n "${dnsAPIType:-}" && "${nextSSLType}" == "buypass" ]]; then
                errorCard "buypass不支持API申请证书"
                [[ -z "${AUTO_INSTALL:-}" ]] || return 1
                continue
            fi
            break
        done
    fi
    if [[ "${nextSSLType}" != "${sslType:-}" ]]; then
        sslTypeFile=$(tlsSslTypeFile) || return 1
        padmEnsureSafeDirectory "$(dirname -- "${sslTypeFile}")" || return 1
        padmCreateTempFileForTarget sslTypeStage "${sslTypeFile}" ssltype || return 1
        printf '%s\n' "${nextSSLType}" >"${sslTypeStage}" || { padmRemoveCleanupPath "${sslTypeStage}"; return 1; }
        commitGeneratedFile "${sslTypeStage}" "${sslTypeFile}" 644 || { padmRemoveCleanupPath "${sslTypeStage}"; return 1; }
        sslType=${nextSSLType}
    fi
}


# 选择 acme.sh 证书签发方式
selectAcmeInstallSSL() {
    local acmeLogFile acmeLogLines=0
    if [[ "${ipType:-}" == "6" ]]; then
        sslIPv6="--listen-v6"
    fi

    acmeLogFile=$(tlsAcmeLogFile) || return 1
    if [[ -f "${acmeLogFile}" ]]; then
        acmeLogLines=$(wc -l <"${acmeLogFile}") || return 1
    fi
    if ! acmeInstallSSL; then
        # 仅处理本次签发的邮箱错误，纠正后重新签发一次。
        tail -n "+$((acmeLogLines + 1))" "${acmeLogFile}" 2>/dev/null |
            grep -F "Could not validate email address as valid" >/dev/null || return 1
        errorCard "邮箱无法通过SSL厂商验证，请重新输入"
        customSSLEmail "validate email" || return 1
        acmeInstallSSL || return 1
    fi
    readAcmeTLS || return 1
    installedDNSAPIStatus=
    if [[ -n "${dnsAPIType:-}" && "${dnsAPIStatus:-}" == y ]]; then
        installedDNSAPIStatus=true
    fi
}


# 安装 TLS 证书
acmeInstallSSL() {
    padmRunPortAllowTransaction acmeInstallSSLApply
}

runAcmeIssueLogged() {
    local acmeLogFile=$1
    shift
    local -a acmeStatuses=()
    if "$@" 2>&1 | tee -a "${acmeLogFile}" >/dev/null; then
        acmeStatuses=("${PIPESTATUS[@]}")
    else
        acmeStatuses=("${PIPESTATUS[@]}")
    fi
    [[ "${acmeStatuses[1]:-1}" == 0 ]] || return "${acmeStatuses[1]:-1}"
    return "${acmeStatuses[0]:-1}"
}

acmeInstallSSLApply() {
    local dnsAPIDomain="${tlsDomain}"
    local dnsAPIExtraDomain=
    local acmeBin
    local acmeLogFile
    acmeBin=$(acmeExecutable) || { errorCard "acme.sh 路径、所有者或权限异常"; return 1; }
    acmeLogFile=$(tlsAcmeLogFile) || return 1
    padmEnsureSafeDirectory "$(dirname -- "${acmeLogFile}")" || return 1
    if [[ "${dnsAPIStatus:-}" == "y" ]]; then
        dnsAPIDomain="*.${dnsTLSDomain}"
        dnsAPIExtraDomain="-d ${dnsTLSDomain}"
    fi

    if [[ "${dnsAPIType:-}" == "cloudflare" ]]; then
        successCard "DNS API 生成证书中"
        if [[ -n "${cfZoneID:-}" ]]; then
            CF_Token="${cfAPIToken}" CF_Zone_ID="${cfZoneID}" padmRunCancelableCommand runAcmeIssueLogged "${acmeLogFile}" "${acmeBin}" --issue -d "${dnsAPIDomain}" ${dnsAPIExtraDomain} --dns dns_cf -k ec-256 --server "${sslType}" ${sslIPv6:-}
        else
            CF_Token="${cfAPIToken}" padmRunCancelableCommand runAcmeIssueLogged "${acmeLogFile}" "${acmeBin}" --issue -d "${dnsAPIDomain}" ${dnsAPIExtraDomain} --dns dns_cf -k ec-256 --server "${sslType}" ${sslIPv6:-}
        fi
    elif [[ "${dnsAPIType:-}" == "aliyun" ]]; then
        successCard "DNS API 生成证书中"
        Ali_Key="${aliKey}" Ali_Secret="${aliSecret}" padmRunCancelableCommand runAcmeIssueLogged "${acmeLogFile}" "${acmeBin}" --issue -d "${dnsAPIDomain}" ${dnsAPIExtraDomain} --dns dns_ali -k ec-256 --server "${sslType}" ${sslIPv6:-}
    else
        allowPort 80 || return 1
        local PADM_TLS_ISSUE_NGINX_WAS_RUNNING=false
        nginxRunning && PADM_TLS_ISSUE_NGINX_WAS_RUNNING=true
        local PADM_EXIT_ROLLBACK_OWNER=${PADM_EXIT_ROLLBACK_OWNER:-}
        local -a PADM_EXIT_ROLLBACKS=("${PADM_EXIT_ROLLBACKS[@]}")
        padmRegisterExitRollback restoreTLSIssueServiceOnExit
        if ! runCoreServiceActionAllowFailure handleNginx stop; then
            padmRunRollback restoreTLSIssueServiceOnExit
            errorCard "Nginx 服务停止失败，已取消 TLS 签发"
            return 1
        fi
        successCard "生成证书中"
        local issueStatus=0
        padmRunCancelableCommand runAcmeIssueLogged "${acmeLogFile}" sudo "${acmeBin}" --issue -d "${tlsDomain}" --standalone -k ec-256 --server "${sslType}" ${sslIPv6:-} || issueStatus=$?
        [[ "${issueStatus}" == 0 ]] || padmRunRollback restoreTLSIssueServiceOnExit
        return "${issueStatus}"
    fi
}

restoreTLSIssueServiceOnExit() {
    checkPortOpenRestoreCoreServiceState "${PADM_TLS_ISSUE_NGINX_WAS_RUNNING}" nginxRunning handleNginx restore ||
        errorCard "TLS 签发中断，Nginx 服务恢复失败"
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
    local installStatus attempt restoreStatus
    local acmeBin acmeDomain

    tlsDomainNameIsSafe "${tlsDomain}" || { errorCard "TLS 域名不合法"; return 1; }
    tlsDir=$(tlsManagedDir) || return 1
    crtFile="${tlsDir}/${tlsDomain}.crt"
    keyFile="${tlsDir}/${tlsDomain}.key"
    acmeLogFile=$(tlsAcmeLogFile) || return 1
    acmeBin=$(acmeExecutable) || { errorCard "acme.sh 路径、所有者或权限异常"; return 1; }

    if [[ -f "${keyFile}" ]] && ! chmod 600 -- "${keyFile}"; then
        errorCard "TLS 私钥权限收紧失败"
        return 1
    fi

    padmCreateTmpRootPath backupDir padm-tls-install.XXXXXX -d || return 1
    backupCrt="${backupDir}/$(basename -- "${crtFile}")"
    backupKey="${backupDir}/$(basename -- "${keyFile}")"
    if [[ -f "${crtFile}" ]] && ! cp -p "${crtFile}" "${backupCrt}"; then
        padmRemoveCleanupPath "${backupDir}"
        return 1
    fi
    if [[ -f "${keyFile}" ]] && ! cp -p "${keyFile}" "${backupKey}"; then
        padmRemoveCleanupPath "${backupDir}"
        return 1
    fi

    local -A PADM_TLS_SYNC_ROLLBACK=(
        [active]=true [backupDir]="${backupDir}" [backupCrt]="${backupCrt}" [backupKey]="${backupKey}"
        [crtFile]="${crtFile}" [keyFile]="${keyFile}"
    )
    local PADM_EXIT_ROLLBACK_OWNER=${PADM_EXIT_ROLLBACK_OWNER:-}
    local -a PADM_EXIT_ROLLBACKS=("${PADM_EXIT_ROLLBACKS[@]}")
    padmRegisterExitRollback rollbackTLSCertificateSyncOnExit
    acmeDomain=${tlsDomain}
    [[ "${installedDNSAPIStatus:-}" != "true" ]] || acmeDomain="*.${dnsTLSDomain}"
    for attempt in 1 2; do
        installStatus=0
        padmRunCancelableCommand sudo "${acmeBin}" --installcert -d "${acmeDomain}" --fullchainpath "${crtFile}" --keypath "${keyFile}" --ecc >/dev/null || installStatus=$?
        if [[ "${installStatus}" == 0 ]] && tlsCertificatePairExists "${tlsDir}" "${tlsDomain}" &&
            chmod 600 -- "${keyFile}" && tlsCertificatePairUsable "${tlsDir}" "${tlsDomain}"; then
            PADM_TLS_SYNC_ROLLBACK[active]=false
            padmRemoveCleanupPath "${backupDir}"
            successCard "TLS生成成功"
            return 0
        fi
        tail -n 10 "${acmeLogFile}" 2>/dev/null || true
        restoreStatus=0
        restoreCoreOptionalFileBackup "${backupCrt}" "${crtFile}" 644 || restoreStatus=1
        restoreCoreOptionalFileBackup "${backupKey}" "${keyFile}" 600 || restoreStatus=1
        if [[ "${restoreStatus}" != 0 ]]; then
            padmForgetCleanupPath "${backupDir}"
            errorCard "TLS安装失败，证书或私钥恢复失败，请手动检查备份目录: ${backupDir}"
            return 1
        fi
        [[ "${attempt}" != 2 ]] || break
    done
    PADM_TLS_SYNC_ROLLBACK[active]=false
    padmRemoveCleanupPath "${backupDir}"
    errorCard "TLS安装失败，请检查acme日志"
    return 1
}

rollbackTLSCertificateSyncOnExit() {
    [[ "${PADM_TLS_SYNC_ROLLBACK[active]:-false}" == true ]] || return 0
    PADM_TLS_SYNC_ROLLBACK[active]=false
    local padmTlsRestoreStatus=0
    restoreCoreOptionalFileBackup "${PADM_TLS_SYNC_ROLLBACK[backupCrt]}" "${PADM_TLS_SYNC_ROLLBACK[crtFile]}" 644 || padmTlsRestoreStatus=1
    restoreCoreOptionalFileBackup "${PADM_TLS_SYNC_ROLLBACK[backupKey]}" "${PADM_TLS_SYNC_ROLLBACK[keyFile]}" 600 || padmTlsRestoreStatus=1
    if [[ "${padmTlsRestoreStatus}" == 0 ]]; then
        padmRemoveCleanupPath "${PADM_TLS_SYNC_ROLLBACK[backupDir]}"
    else
        padmForgetCleanupPath "${PADM_TLS_SYNC_ROLLBACK[backupDir]}"
        errorCard "TLS 同步中断，证书恢复失败，请检查备份目录: ${PADM_TLS_SYNC_ROLLBACK[backupDir]}"
    fi
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
    readAcmeTLS || return 1
    local tlsDomain=${domain}
    local tlsDir
    local reInstallStatus=n
    tlsDomainNameIsSafe "${tlsDomain}" || { errorCard "TLS 域名不合法"; return 1; }
    tlsDir=$(tlsManagedDir) || return 1
    local PADM_TLS_ISSUE_NGINX_WAS_RUNNING=false
    nginxRunning && PADM_TLS_ISSUE_NGINX_WAS_RUNNING=true
    local PADM_EXIT_ROLLBACK_OWNER=${PADM_EXIT_ROLLBACK_OWNER:-}
    local -a PADM_EXIT_ROLLBACKS=("${PADM_EXIT_ROLLBACKS[@]}")
    # 签发成功到证书同步结束之间，也必须保留原服务的取消恢复状态。
    padmRegisterExitRollback restoreTLSIssueServiceOnExit

    if { [[ "${PADM_REQUIRE_USABLE_TLS_CERTIFICATE:-}" == "true" ]] && tlsCertificatePairUsable "${tlsDir}" "${tlsDomain}"; } ||
        { [[ "${PADM_REQUIRE_USABLE_TLS_CERTIFICATE:-}" != "true" ]] && tlsCertificatePairExists "${tlsDir}" "${tlsDomain}"; }; then
        successCard "检测到证书"
        if [[ "${PADM_CORE_SWITCH_TRANSACTION_ACTIVE:-}" != true && -z "${lastInstallationConfig:-}" ]] &&
            { [[ -s "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.key" &&
                -s "$HOME/.acme.sh/${tlsDomain}_ecc/${tlsDomain}.cer" ]] || [[ "${installedDNSAPIStatus:-}" == "true" ]]; }; then
            tlsCertificateCard "回车保留现有证书；重新安装仅同步当前域名证书"
            menuReadChoice tls_reinstall "是否重新安装当前域名证书？[y/N]:" reInstallStatus true || return 1
        fi
        if [[ "$(normalizeYesNo "${reInstallStatus}")" == "y" ]]; then
            # 显式同步优先选择仍可用的 ACME 源；不可复用时保留原同步与失败行为。
            tlsAcmeSourceCertificateReusable "${tlsDomain}" || true
            installTLSFromAcme || return 1
        elif ! tlsCertificatePairUsable "${tlsDir}" "${tlsDomain}" ||
            ! openssl x509 -in "${tlsDir}/${tlsDomain}.crt" -checkend 86400 -noout >/dev/null 2>&1; then
            renewalTLS "" "${tlsDomain}" || return 1
        fi

    elif tlsAcmeSourceCertificateReusable "${tlsDomain}"; then
        successCard "检测到证书"
        installTLSFromAcme || return 1
    elif [[ -d "$HOME/.acme.sh" ]]; then
        [[ -n "${dnsAPIStatus+x}" ]] || switchDNSAPI || return 1
        if [[ -z "${dnsAPIType:-}" ]]; then
            statusCard "TLS 证书申请方式" "不采用 API 申请证书"
            successCard "安装TLS证书，需要依赖80端口"
        fi

        switchSSLType || return 1
        customSSLEmail || return 1
        selectAcmeInstallSSL || return 1

        installTLSFromAcme || return 1
    else
        statusCard "acme.sh" "未安装 acme.sh"
        return 1
    fi
    if [[ -f "${tlsDir}/${tlsDomain}.key" ]] &&
        ! chmod 600 -- "${tlsDir}/${tlsDomain}.key"; then
        errorCard "TLS 私钥权限收紧失败"
        return 1
    fi
    if ! tlsCertificatePairUsable "${tlsDir}" "${tlsDomain}"; then
        errorCard "本机 TLS 证书不可用" "请检查证书有效期、域名及私钥是否匹配: ${tlsDir}/${tlsDomain}"
        return 1
    fi
}


# 定时任务更新tls证书
installCronTLS() {
    if [[ -z "${btDomain}" ]]; then
        progressCard "$1" "添加定时维护证书"
        local historyCrontab
        historyCrontab=$(readUserCrontabContent) || {
            errorCard "读取现有定时任务失败，已取消添加证书维护任务"
            return 1
        }
        if awk '
          $1 !~ /^#/ {
            command = ($1 ~ /^@/) ? 2 : 6
            if ($command == "/bin/bash" || $command == "bash") command++
            if ($command == "/etc/padm/install.sh" && $(command + 1) == "RenewTLS") {
              count++
              nextArg = $(command + 2)
              if (($1 !~ /^@/ || $1 ~ /^@(annually|yearly|monthly|weekly|daily|midnight|hourly)$/) &&
                  (nextArg == "" || nextArg ~ /^(>|2>|#)/)) valid++
            }
          }
          END { exit !(count == 1 && valid == 1) }
        ' <<<"${historyCrontab}"; then
            statusCard "TLS 自动续签" "已设置" "保留现有定时任务"
            return 0
        fi
        historyCrontab=$(awk '
          $1 !~ /^#/ {
            command = ($1 ~ /^@/) ? 2 : 6
            if ($command == "/bin/bash" || $command == "bash") command++
            if ($command == "/etc/padm/install.sh" && $(command + 1) == "RenewTLS") next
          }
          { print }
        ' <<<"${historyCrontab}") || {
            errorCard "整理现有定时任务失败，已取消添加证书维护任务"
            return 1
        }
        if ! installUserCrontabContent "${historyCrontab}
30 1 * * * /bin/bash /etc/padm/install.sh RenewTLS >> /etc/padm/crontab_tls.log 2>&1"; then
            errorCard "添加定时维护证书失败，已保留原定时任务"
            return 1
        fi
        successCard "添加定时维护证书成功"
    fi
}

padmMaintenanceCronActive() {
    awk -v action="$1" '
      $1 !~ /^#/ {
        command = ($1 ~ /^@/) ? 2 : 6
        if ($command == "/bin/bash" || $command == "bash") command++
        nextArg = $(command + 2)
        if ($command == "/etc/padm/install.sh" && $(command + 1) == action &&
            ($1 !~ /^@/ || $1 ~ /^@(annually|yearly|monthly|weekly|daily|midnight|hourly)$/) &&
            (nextArg == "" || nextArg ~ /^(>|2>|#)/)) found = 1
      }
      END { exit !found }
    '
}

# 定时任务更新 Geo 文件
installCronUpdateGeo() {
    if [[ "${coreInstallType}" == "1" ]]; then
        local historyCrontab
        historyCrontab=$(readUserCrontabContent) || {
            errorCard "读取现有定时任务失败，已取消添加 Geo 更新任务"
            return 1
        }
        if padmMaintenanceCronActive UpdateGeo <<<"${historyCrontab}"; then
            statusCard "Geo 自动更新" "已设置" "保留现有定时任务"
            return 0
        fi
        progressCard "1" "添加定时更新 Geo 文件" "1"
        if ! installUserCrontabContent "${historyCrontab}
35 1 * * * /bin/bash /etc/padm/install.sh UpdateGeo >> /etc/padm/crontab_tls.log 2>&1"; then
            errorCard "添加定时更新 Geo 文件失败，已保留原定时任务"
            return 1
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
    if crontab -l 2>/dev/null | padmMaintenanceCronActive RenewTLS; then
        printf '已设置'
    else
        printf '未设置'
    fi
}

tlsCertificateStatusJson() {
    local domain=${currentHost:-${tlsDomain:-}}
    local tlsDir
    local acmeDir
    tlsDir=$(tlsManagedDir) || return 1
    acmeDir=$(acmeSafeHomeDir 2>/dev/null || true)
    if [[ -n "${domain}" ]] && ! tlsDomainNameIsSafe "${domain}"; then
        domain=
    fi
    if ! tlsCertificatePairExists "${tlsDir}" "${domain}"; then
        domain=$(resolveInstalledTLSDomain)
    fi
    readAcmeTLS "${domain}" || return 1

    if tlsCertificatePairExists "${tlsDir}" "${domain}"; then
        if [[ -n "${acmeDir}" ]] && { [[ -s "${acmeDir}/${domain}_ecc/${domain}.key" &&
            -s "${acmeDir}/${domain}_ecc/${domain}.cer" ]] || [[ "${installedDNSAPIStatus:-}" == "true" ]]; }; then
            local startDate endDate modifyTime endTime currentTime remainingDays sourceType
            if [[ "${installedDNSAPIStatus:-}" == "true" ]]; then
                sourceType="acme-dns-api"
            else
                sourceType="acme-standalone"
            fi
            startDate=$(openssl x509 -in "${tlsDir}/${domain}.crt" -startdate -noout 2>/dev/null) &&
                endDate=$(openssl x509 -in "${tlsDir}/${domain}.crt" -enddate -noout 2>/dev/null) &&
                [[ "${startDate}" == notBefore=* && "${endDate}" == notAfter=* ]] || return 1
            modifyTime=$(tlsCertificateDateEpoch "${startDate#notBefore=}") &&
                endTime=$(tlsCertificateDateEpoch "${endDate#notAfter=}") &&
                currentTime=$(date +%s) || return 1
            remainingDays=$(( (endTime - currentTime) / 86400 ))
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
        tlsCertificateStatusCard "未检测到本机 TLS 证书" "定时续签：${cron}" "Reality 不使用本机证书；传统 TLS、站点或订阅需要时请检查证书"
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
        tlsCertificateMenuStatus=
        menuReadChoice tls_certificate_menu "请选择:" tlsCertificateMenuStatus || return 0
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
    local nginxWasRunning=$1
    local xrayWasRunning=$2
    local singBoxWasRunning=$3
    local status=0

    checkPortOpenRestoreCoreServiceState "${xrayWasRunning}" xrayRunning handleXray || status=1
    checkPortOpenRestoreCoreServiceState "${singBoxWasRunning}" singBoxRunning handleSingBox || status=1
    checkPortOpenRestoreCoreServiceState "${nginxWasRunning}" nginxRunning handleNginx restore || status=1
    return "${status}"
}

stopServicesForTLSRenewal() {
    local nginxWasRunning=$1
    local xrayWasRunning=$2
    local singBoxWasRunning=$3

    if [[ "${nginxWasRunning}" == "true" ]] && ! runCoreServiceActionAllowFailure handleNginx stop; then
        errorCard "Nginx 服务停止失败，已取消 TLS 续期"
        restoreServicesAfterTLSRenewal "$@" || errorCard "TLS 续期取消后服务恢复失败"
        return 1
    fi

    if [[ "${xrayWasRunning}" == "true" ]] && ! runCoreServiceActionAllowFailure handleXray stop; then
        errorCard "Xray 服务停止失败，已取消 TLS 续期"
        restoreServicesAfterTLSRenewal "$@" || errorCard "TLS 续期取消后服务恢复失败"
        return 1
    fi
    if [[ "${singBoxWasRunning}" == "true" ]] && ! runCoreServiceActionAllowFailure handleSingBox stop; then
        errorCard "sing-box 服务停止失败，已取消 TLS 续期"
        restoreServicesAfterTLSRenewal "$@" || errorCard "TLS 续期取消后服务恢复失败"
        return 1
    fi
}

renewManagedTLSCertificates() {
    local records requestedDomain="${1:-}"
    local acmeDir acmeBin tlsDir backupDir
    local domain configFile certFile keyFile acmeDomain webroot
    local nginxWasRunning=false xrayWasRunning=false singBoxWasRunning=false
    local servicesStopped=false changed=false needsServiceStop=false
    local beforeHash afterHash reloadStatus=0
    local -a dueDomains=()
    local -A dueConfigs=()
    local -A beforeHashes=()
    local -a renewArgs=()

    [[ -z "${requestedDomain}" ]] || tlsDomainNameIsSafe "${requestedDomain}" || return 1
    records=$(tlsAcmeManagedCertificateRecords) || return 1
    if [[ -n "${requestedDomain}" ]]; then
        records=$(awk -F '\t' -v domain="${requestedDomain}" '$1 == domain' <<<"${records}")
    else
        [[ -n "${records}" ]] || return 2
    fi
    acmeDir=$(acmeSafeHomeDir) || { errorCard "acme.sh HOME 路径异常"; return 1; }
    acmeBin=$(acmeExecutable) || { errorCard "acme.sh 路径、所有者或权限异常"; return 1; }
    tlsDir=$(tlsManagedDir) || return 1
    if [[ -n "${requestedDomain}" && -z "${records}" ]]; then
        acmeDomain=${requestedDomain}
        [[ "${installedDNSAPIStatus:-}" != true ]] || acmeDomain="*.${dnsTLSDomain}"
        configFile="${acmeDir}/${acmeDomain}_ecc/${acmeDomain}.conf"
        [[ -f "${configFile}" ]] || {
            errorCard "当前域名没有可用的 acme.sh 续签配置" "自定义证书需自行更新：${requestedDomain}"
            return 1
        }
        printf -v records '%s\t%s\t%s\t%s' "${requestedDomain}" "${configFile}" \
            "${tlsDir}/${requestedDomain}.crt" "${tlsDir}/${requestedDomain}.key"
    fi

    while IFS=$'\t' read -r domain configFile certFile keyFile; do
        [[ -n "${domain}" && -s "${certFile}" && -s "${keyFile}" ]] || {
            errorCard "acme.sh 证书安装目标不完整：${domain:-unknown}"
            return 1
        }
        chmod 600 -- "${keyFile}" || { errorCard "TLS 私钥权限收紧失败"; return 1; }
        beforeHash=$(sha256sum "${certFile}" "${keyFile}" 2>/dev/null) || return 1
        beforeHashes["${domain}"]=${beforeHash}
        if ! tlsCertificatePairUsable "${tlsDir}" "${domain}" ||
            ! openssl x509 -in "${certFile}" -checkend 86400 -noout >/dev/null 2>&1; then
            dueDomains+=("${domain}")
            dueConfigs["${domain}"]=${configFile}
            webroot=$(tlsAcmeConfigValue "${configFile}" Le_Webroot) || return 1
            [[ "${webroot}" != "no" && "${webroot}" != "alpn" ]] || needsServiceStop=true
        fi
    done <<<"${records}"

    if [[ ${#dueDomains[@]} -eq 0 ]]; then
        successCard "所有 acme.sh 管理证书均有效"
        return 0
    fi
    padmCreateTmpRootPath backupDir padm-tls-renew-all.XXXXXX -d || return 1
    if [[ -n "${requestedDomain}" ]]; then
        cp -p -- "${tlsDir}/${requestedDomain}.crt" "${tlsDir}/${requestedDomain}.key" "${backupDir}/" ||
            { padmRemoveCleanupPath "${backupDir}"; return 1; }
        configFile=${dueConfigs[${requestedDomain}]}
        acmeDomain=$(tlsAcmeConfigValue "${configFile}" Le_Domain) || acmeDomain=
        [[ -n "${acmeDomain}" ]] || acmeDomain=${requestedDomain}
        # 原事务内选择有效源，保留同步后的服务重载与备份合同。
        if tlsAcmeSourceCertificateReusable "${requestedDomain}"; then
            acmeDomain=${requestedDomain}
            [[ "${installedDNSAPIStatus:-}" != true ]] || acmeDomain="*.${dnsTLSDomain}"
        fi
        renewArgs=(--renew -d "${acmeDomain}" --ecc --force --home "${acmeDir}")
    else
        cp -a "${tlsDir}/." "${backupDir}/" || { padmRemoveCleanupPath "${backupDir}"; return 1; }
        renewArgs=(--cron --home "${acmeDir}")
    fi
    nginxRunning && nginxWasRunning=true
    xrayRunning && xrayWasRunning=true
    singBoxRunning && singBoxWasRunning=true
    local -A PADM_TLS_RENEW_ROLLBACK=(
        [active]=true [backupDir]="${backupDir}" [tlsDir]="${tlsDir}"
        [nginxWasRunning]="${nginxWasRunning}" [xrayWasRunning]="${xrayWasRunning}" [singBoxWasRunning]="${singBoxWasRunning}"
    )
    local PADM_EXIT_ROLLBACK_OWNER=${PADM_EXIT_ROLLBACK_OWNER:-}
    local -a PADM_EXIT_ROLLBACKS=("${PADM_EXIT_ROLLBACKS[@]}")
    padmRegisterExitRollback rollbackTLSRenewalOnExit
    # 安装先同步当前域名的已有证书，足够有效时不重复请求 CA。
    if [[ -n "${requestedDomain}" ]] &&
        padmRunCancelableCommand sudo "${acmeBin}" --installcert -d "${acmeDomain}" --fullchainpath "${tlsDir}/${requestedDomain}.crt" \
            --keypath "${tlsDir}/${requestedDomain}.key" --ecc &&
        tlsCertificatePairUsable "${tlsDir}" "${requestedDomain}" &&
        openssl x509 -in "${tlsDir}/${requestedDomain}.crt" -checkend 86400 -noout >/dev/null 2>&1; then
        renewArgs=()
        dueDomains=()
    fi
    if [[ "${needsServiceStop}" == "true" && ${#renewArgs[@]} -gt 0 ]]; then
        stopServicesForTLSRenewal "${nginxWasRunning}" "${xrayWasRunning}" "${singBoxWasRunning}" || {
            if [[ -n "${requestedDomain}" ]]; then
                restoreTLSReinstallBackup "${backupDir}" "${tlsDir}" "TLS 续签取消" || true
                restoreServicesAfterTLSRenewal "${nginxWasRunning}" "${xrayWasRunning}" "${singBoxWasRunning}" ||
                    errorCard "TLS 续签取消后服务恢复失败"
            else
                padmRemoveCleanupPath "${backupDir}"
            fi
            return 1
        }
        servicesStopped=true
    fi
    if [[ ${#renewArgs[@]} -gt 0 ]] && ! padmRunCancelableCommand sudo "${acmeBin}" "${renewArgs[@]}"; then
        restoreTLSReinstallBackup "${backupDir}" "${tlsDir}" "TLS 证书续签失败" || true
        [[ "${servicesStopped}" != "true" ]] || restoreServicesAfterTLSRenewal "${nginxWasRunning}" "${xrayWasRunning}" "${singBoxWasRunning}" || true
        return 1
    fi
    for domain in "${dueDomains[@]}"; do
        configFile=${dueConfigs[${domain}]}
        acmeDomain=$(tlsAcmeConfigValue "${configFile}" Le_Domain) || acmeDomain=
        [[ -n "${acmeDomain}" ]] || acmeDomain=${domain}
        if ! padmRunCancelableCommand sudo "${acmeBin}" --installcert -d "${acmeDomain}" \
            --fullchainpath "${tlsDir}/${domain}.crt" --keypath "${tlsDir}/${domain}.key" --ecc; then
            restoreTLSReinstallBackup "${backupDir}" "${tlsDir}" "TLS 证书安装失败" || true
            [[ "${servicesStopped}" != "true" ]] || restoreServicesAfterTLSRenewal "${nginxWasRunning}" "${xrayWasRunning}" "${singBoxWasRunning}" || true
            return 1
        fi
    done
    while IFS=$'\t' read -r domain configFile certFile keyFile; do
        if ! tlsCertificatePairUsable "${tlsDir}" "${domain}" ||
            { [[ -n "${requestedDomain}" ]] &&
                ! openssl x509 -in "${certFile}" -checkend 86400 -noout >/dev/null 2>&1; }; then
            restoreTLSReinstallBackup "${backupDir}" "${tlsDir}" "TLS 证书续签后校验失败" || true
            [[ "${servicesStopped}" != "true" ]] || restoreServicesAfterTLSRenewal "${nginxWasRunning}" "${xrayWasRunning}" "${singBoxWasRunning}" || true
            return 1
        fi
        if ! chmod 600 -- "${keyFile}" ||
            ! afterHash=$(sha256sum "${certFile}" "${keyFile}" 2>/dev/null); then
            if restoreTLSReinstallBackup "${backupDir}" "${tlsDir}" "TLS 证书续签后文件校验失败"; then
                errorCard "TLS 证书续签后文件校验失败，已恢复旧证书"
            fi
            if [[ "${servicesStopped}" == "true" ]] &&
                ! restoreServicesAfterTLSRenewal "${nginxWasRunning}" "${xrayWasRunning}" "${singBoxWasRunning}"; then
                errorCard "TLS 证书续签后文件校验失败，且服务恢复失败"
            fi
            return 1
        fi
        [[ "${afterHash}" == "${beforeHashes[${domain}]}" ]] || changed=true
    done <<<"${records}"

    if [[ "${servicesStopped}" == "true" ]]; then
        restoreServicesAfterTLSRenewal "${nginxWasRunning}" "${xrayWasRunning}" "${singBoxWasRunning}" || {
            padmForgetCleanupPath "${backupDir}"
            errorCard "TLS 证书已更新，但服务恢复失败" "备份目录: ${backupDir}"
            return 1
        }
    elif [[ "${changed}" == "true" ]]; then
        [[ "${xrayWasRunning}" != true ]] ||
            runCoreServiceActionAllowFailure runServiceAction xray restart || reloadStatus=1
        [[ "${singBoxWasRunning}" != true ]] ||
            runCoreServiceActionAllowFailure runServiceAction sing-box restart || reloadStatus=1
        [[ "${reloadStatus}" == 0 ]] || {
            padmForgetCleanupPath "${backupDir}"
            errorCard "TLS 证书已更新，但核心服务重载失败" "备份目录: ${backupDir}"
            return 1
        }
        if [[ "${nginxWasRunning}" == "true" ]]; then
            if ! runCoreServiceActionAllowFailure handleNginx stop ||
                ! runCoreServiceActionAllowFailure handleNginx start restore; then
                padmForgetCleanupPath "${backupDir}"
                errorCard "TLS 证书已更新，但 Nginx 重载失败" "备份目录: ${backupDir}"
                return 1
            fi
        fi
    fi
    if [[ "${changed}" == "true" && "${nginxWasRunning}" == true ]] &&
        declare -F readNginxSubscribe >/dev/null 2>&1 && declare -F probeSubscribeTLS >/dev/null 2>&1; then
        subscribePort=
        subscribeDomain=
        subscribeConfigState=
        if readNginxSubscribe && [[ "${subscribeConfigState:-}" == "valid" ]] &&
            [[ -z "${requestedDomain}" || "${subscribeDomain}" == "${requestedDomain}" ]] &&
            ! probeSubscribeTLS "${subscribeDomain}" "${subscribePort}"; then
            padmForgetCleanupPath "${backupDir}"
            errorCard "证书已更新，但订阅 HTTPS 本机 SNI/TLS 探测失败" "备份目录: ${backupDir}"
            return 1
        fi
    fi
    PADM_TLS_RENEW_ROLLBACK[active]=false
    padmRemoveCleanupPath "${backupDir}"
    successCard "acme.sh 管理证书续签检查完成"
}

rollbackTLSRenewalOnExit() {
    [[ "${PADM_TLS_RENEW_ROLLBACK[active]:-false}" == true ]] || return 0
    PADM_TLS_RENEW_ROLLBACK[active]=false
    restoreTLSReinstallBackup "${PADM_TLS_RENEW_ROLLBACK[backupDir]}" "${PADM_TLS_RENEW_ROLLBACK[tlsDir]}" "TLS 续签中断" || true
    restoreServicesAfterTLSRenewal "${PADM_TLS_RENEW_ROLLBACK[nginxWasRunning]}" \
        "${PADM_TLS_RENEW_ROLLBACK[xrayWasRunning]}" "${PADM_TLS_RENEW_ROLLBACK[singBoxWasRunning]}" ||
        errorCard "TLS 续签中断，旧服务恢复失败"
}

# 更新 TLS 证书
renewalTLS() {

    if [[ -n ${1:-} ]]; then
        progressCard "$1" "更新证书" "1"
    fi
    if [[ -n "${2:-}" ]]; then
        renewManagedTLSCertificates "$2"
        return $?
    fi
    local managedRenewStatus=0
    renewManagedTLSCertificates || managedRenewStatus=$?
    if [[ "${managedRenewStatus}" == "0" ]]; then
        return 0
    elif [[ "${managedRenewStatus}" != "2" ]]; then
        return "${managedRenewStatus}"
    fi
    local domain=${currentHost:-${tlsDomain:-}}
    local sslTypeFile
    local tlsDir
    local acmeDir
    local acmeBin
    local renewStatus
    local renewalDays=90
    tlsDir=$(tlsManagedDir) || return 1
    acmeDir=$(acmeSafeHomeDir 2>/dev/null || true)
    if [[ -n "${domain}" ]] && ! tlsDomainNameIsSafe "${domain}"; then
        domain=
    fi
    if ! tlsCertificatePairExists "${tlsDir}" "${domain}"; then
        domain=$(resolveInstalledTLSDomain)
    fi
    readAcmeTLS "${domain}" || return 1

    sslTypeFile=$(tlsSslTypeFile) || return 1
    if [[ -f "${sslTypeFile}" ]] && grep -q "buypass" <"${sslTypeFile}"; then
        renewalDays=180
    fi
    if [[ "${installedDNSAPIStatus:-}" == "true" && -z "${acmeDir}" ]]; then
        errorCard "acme.sh HOME 路径异常"
        return 1
    fi
    if [[ -n "${acmeDir}" ]] && { [[ -s "${acmeDir}/${domain}_ecc/${domain}.key" &&
        -s "${acmeDir}/${domain}_ecc/${domain}.cer" ]] || [[ "${installedDNSAPIStatus:-}" == "true" ]]; }; then
        acmeBin=$(acmeExecutable) || { errorCard "acme.sh 路径、所有者或权限异常"; return 1; }
        chmod 600 -- "${tlsDir}/${domain}.key" || { errorCard "TLS 私钥权限收紧失败"; return 1; }
        modifyTime=

        if [[ "${installedDNSAPIStatus:-}" == "true" ]]; then
            modifyTime=$(stat --format=%z "${acmeDir}/*.${dnsTLSDomain}_ecc/*.${dnsTLSDomain}.cer")
        else
            modifyTime=$(stat --format=%z "${acmeDir}/${domain}_ecc/${domain}.cer")
        fi

        modifyTime=$(date +%s -d "${modifyTime}")
        currentTime=$(date +%s)
        ((stampDiff = currentTime - modifyTime))
        ((days = stampDiff / 86400))
        ((remainingDays = renewalDays - days))

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
            local nginxWasRunning=false
            local xrayWasRunning=false
            local singBoxWasRunning=false
            tlsCertificateCard "重新生成证书"
            nginxRunning && nginxWasRunning=true
            xrayRunning && xrayWasRunning=true
            singBoxRunning && singBoxWasRunning=true
            if [[ "${installedDNSAPIStatus:-}" == "true" ]]; then
                installDomain="*.${dnsTLSDomain}"
            fi
            local backupDir backupCrt backupKey restoreStatus=0
            padmCreateTmpRootPath backupDir padm-tls-renew.XXXXXX -d || {
                errorCard "TLS 旧证书备份目录创建失败，已取消 TLS 续期"
                return 1
            }
            backupCrt="${backupDir}/$(basename -- "${crtFile}")"
            backupKey="${backupDir}/$(basename -- "${keyFile}")"
            cp -p "${crtFile}" "${backupCrt}" || {
                padmRemoveCleanupPath "${backupDir}"
                errorCard "TLS 旧证书备份失败，已取消 TLS 续期"
                return 1
            }
            cp -p "${keyFile}" "${backupKey}" || {
                padmRemoveCleanupPath "${backupDir}"
                errorCard "TLS 旧证书备份失败，已取消 TLS 续期"
                return 1
            }
            local -A PADM_TLS_RENEW_ROLLBACK=(
                [active]=true [backupDir]="${backupDir}" [tlsDir]="${tlsDir}"
                [nginxWasRunning]="${nginxWasRunning}" [xrayWasRunning]="${xrayWasRunning}" [singBoxWasRunning]="${singBoxWasRunning}"
            )
            local PADM_EXIT_ROLLBACK_OWNER=${PADM_EXIT_ROLLBACK_OWNER:-}
            local -a PADM_EXIT_ROLLBACKS=("${PADM_EXIT_ROLLBACKS[@]}")
            padmRegisterExitRollback rollbackTLSRenewalOnExit
            stopServicesForTLSRenewal "${nginxWasRunning}" "${xrayWasRunning}" "${singBoxWasRunning}" || {
                padmRunRollback rollbackTLSRenewalOnExit || true
                return 1
            }
            if padmRunCancelableCommand sudo "${acmeBin}" --cron --home "${acmeDir}"; then
                :
            else
                renewStatus=$?
                errorCard "TLS 证书续签失败，正在恢复旧证书和服务"
                restoreManagedFileFromBackup "${backupCrt}" "${crtFile}" 644 || restoreStatus=1
                restoreManagedFileFromBackup "${backupKey}" "${keyFile}" 600 || restoreStatus=1
                if [[ "${restoreStatus}" -eq 0 ]]; then
                    padmRemoveCleanupPath "${backupDir}"
                else
                    padmForgetCleanupPath "${backupDir}"
                    errorCard "TLS 证书恢复失败，请手动检查备份目录: ${backupDir}"
                fi
                restoreServicesAfterTLSRenewal "${nginxWasRunning}" "${xrayWasRunning}" "${singBoxWasRunning}" || errorCard "TLS 证书续签失败，且服务恢复失败"
                return "${renewStatus}"
            fi
            local installStatus=0
            padmRunCancelableCommand sudo "${acmeBin}" --installcert -d "${installDomain}" --fullchainpath "${crtFile}" --keypath "${keyFile}" --ecc || installStatus=$?
            if [[ "${installStatus}" -eq 0 ]]; then
                chmod 600 -- "${keyFile}" || installStatus=$?
            fi
            if [[ "${installStatus}" -eq 0 ]] && ! tlsCertificatePairUsable "${tlsDir}" "${domain}"; then
                installStatus=1
            fi
            if [[ "${installStatus}" -ne 0 ]]; then
                errorCard "TLS 证书安装失败，正在尝试恢复服务"
                restoreManagedFileFromBackup "${backupCrt}" "${crtFile}" 644 || restoreStatus=1
                restoreManagedFileFromBackup "${backupKey}" "${keyFile}" 600 || restoreStatus=1
                if [[ "${restoreStatus}" -eq 0 ]]; then
                    padmRemoveCleanupPath "${backupDir}"
                else
                    padmForgetCleanupPath "${backupDir}"
                    errorCard "TLS 证书恢复失败，请手动检查备份目录: ${backupDir}"
                fi
                restoreServicesAfterTLSRenewal "${nginxWasRunning}" "${xrayWasRunning}" "${singBoxWasRunning}" || errorCard "TLS 证书安装失败，且服务恢复失败"
                return "${installStatus}"
            fi
            if ! restoreServicesAfterTLSRenewal "${nginxWasRunning}" "${xrayWasRunning}" "${singBoxWasRunning}"; then
                padmForgetCleanupPath "${backupDir}"
                errorCard "TLS 证书已安装，但服务恢复失败"
                return 1
            fi
            PADM_TLS_RENEW_ROLLBACK[active]=false
            padmRemoveCleanupPath "${backupDir}"
        else
            successCard "证书有效"
        fi
    elif tlsCertificatePairExists "${tlsDir}" "${domain}"; then
        tlsCertificateCard "检测到使用自定义证书，无法执行 renew 操作"
    else
        errorCard "未安装本机 TLS 证书；Reality 不使用本机证书，传统 TLS、站点或订阅请检查 acme 与 /etc/padm/tls"
        return 1
    fi
}
