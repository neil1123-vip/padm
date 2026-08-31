#!/usr/bin/env bash

runRealityProfileFailureRegression() (
    local root="${TMP_DIR}/reality-profile-failure"
    local xrayRoot="${root}/xray/"
    local singBoxRoot="${root}/sing-box/"
    local entryHostFile="${root}/reality_entry_host"
    local errorLog="${root}/error.log"
    local allowCalls=0
    local keyCalls=0
    local portReads=0
    local dnsCalls=0

    mkdir -p "${xrayRoot}" "${singBoxRoot}"
    configPath="${xrayRoot}"
    singBoxConfigPath="${singBoxRoot}"
    currentUUID=existing-user
    currentClients='[]'
    domain=
    currentHost=
    lastInstallationConfig=true
    AUTO_ENTRY_HOST=node.example.com
    AUTO_REALITY_TARGET=www.microsoft.com:443
    PADM_REALITY_ENTRY_HOST_FILE="${entryHostFile}"
    : >"${errorLog}"
    realityPort=10888
    xHTTPort=10889
    singBoxVLESSRealityVisionPort=10890
    xrayVLESSRealityPort=
    xrayVLESSRealityXHTTPort=
    realityTargetHost=
    realityTargetPort=
    realityEntryHost=

    initXrayClients() { printf '[]\n'; }
    initSingBoxClients() { printf '[]\n'; }
    addXrayOutbound() { return 0; }
    installSniffing() { return 0; }
    initRealityKey() {
        keyCalls=$((keyCalls + 1))
        realityPrivateKey=private
        realityPublicKey=public
    }
    initRealityMldsa65() { return 0; }
    checkDNSIP() {
        dnsCalls=$((dnsCalls + 1))
        return 0
    }
    getPublicIP() { printf '2001:db8::10\n'; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    allowPort() {
        allowCalls=$((allowCalls + 1))
        return 0
    }
    readSingBoxPortResult() {
        local -n resultRef=$1
        portReads=$((portReads + 1))
        resultRef=(10890)
        return 0
    }
    writeGeneratedJsonFile() {
        local targetFile=$1
        local outputFile
        shift 2
        case "${targetFile}" in
        /etc/padm/xray/conf/*)
            outputFile="${xrayRoot}${targetFile#/etc/padm/xray/conf/}"
            ;;
        /etc/padm/sing-box/conf/config/*)
            outputFile="${singBoxRoot}${targetFile#/etc/padm/sing-box/conf/config/}"
            ;;
        *)
            outputFile="${targetFile}"
            ;;
        esac
        mkdir -p "$(dirname "${outputFile}")"
        cat >"${outputFile}"
    }

    AUTO_INSTALL=
    AUTO_REALITY_DOMAIN=
    AUTO_DOMAIN=domain.example.com
    domain=legacy.example.com
    currentHost=current.example.com
    printf 'stored.example.com\n' >"${entryHostFile}"
    realityEntryHost=
    collectEntryProfile
    [[ "${realityEntryHost}" == "node.example.com" ]]

    AUTO_ENTRY_HOST=
    AUTO_DOMAIN=2001:db8::10
    realityEntryHost=
    collectEntryProfile
    [[ "${realityEntryHost}" == "2001:db8::10" ]]

    AUTO_DOMAIN=
    domain=2001:db8::20
    realityEntryHost=
    collectEntryProfile
    [[ "${realityEntryHost}" == "2001:db8::20" ]]

    domain=
    realityEntryHost=
    collectEntryProfile
    [[ "${realityEntryHost}" == "stored.example.com" ]]

    rm -f "${entryHostFile}"
    realityEntryHost=
    collectEntryProfile
    [[ "${realityEntryHost}" == "current.example.com" ]]

    currentHost=
    realityEntryHost=
    collectEntryProfile
    [[ "${realityEntryHost}" == "2001:db8::10" ]]

    AUTO_INSTALL=true
    AUTO_REALITY_DOMAIN=yes
    realityEntryHost=
    if collectEntryProfile 2>/dev/null; then
        return 1
    fi
    grep -q '缺少入口域名' "${errorLog}"

    AUTO_INSTALL=
    autoRead() {
        [[ "$1" == "entry_host" ]] || return 1
        printf -v "$3" 'strict.example.com'
    }
    realityEntryHost=
    collectEntryProfile
    [[ "${realityEntryHost}" == "strict.example.com" ]]
    [[ "${dnsCalls}" == "0" ]]
    initRealityProfile
    [[ "${dnsCalls}" == "1" ]]

    configureRealityDomainMode ",1," domain
    [[ "${realityOnlyWithDomain}" == "true" ]]
    if configureRealityDomainMode ",2," domain 2>/dev/null; then return 1; fi
    if configureRealityDomainMode ",26," domain 2>/dev/null; then return 1; fi
    if configureRealityDomainMode ",1,2," domain 2>/dev/null; then return 1; fi

    local sideEffectLog="${root}/strict-side-effects.log"
    : >"${sideEffectLog}"
    readLastInstallationConfig() { printf 'read-last\n' >>"${sideEffectLog}"; return 0; }
    installTools() { printf 'install-tools\n' >>"${sideEffectLog}"; return 0; }
    AUTO_INSTALL=true
    AUTO_ENTRY_HOST=
    AUTO_DOMAIN=
    domain=
    currentHost=
    rm -f "${entryHostFile}"
    if customXrayInstallApply 2 domain >/dev/null 2>&1; then return 1; fi
    if customXrayInstallApply 26 domain >/dev/null 2>&1; then return 1; fi
    if customXrayInstallApply 1,2 domain >/dev/null 2>&1; then return 1; fi
    if customSingBoxInstallApply 26 domain >/dev/null 2>&1; then return 1; fi
    if customXrayInstallApply 1 domain >/dev/null 2>&1; then return 1; fi
    if customSingBoxInstallApply 1 domain >/dev/null 2>&1; then return 1; fi
    [[ ! -s "${sideEffectLog}" ]]

    AUTO_INSTALL=
    AUTO_REALITY_DOMAIN=
    realityOnlyWithDomain=
    AUTO_ENTRY_HOST=node.example.com
    AUTO_REALITY_TARGET=www.microsoft.com:443
    realityEntryHost=
    realityTargetHost=
    realityTargetPort=
    realitySNI=
    initRealityProfile
    [[ ! -e "${entryHostFile}" ]]
    persistRealityEntryProfile
    [[ "$(<"${entryHostFile}")" == "node.example.com" ]]
    rm -f "${entryHostFile}"
    AUTO_ENTRY_HOST='bad entry host'
    realityEntryHost=
    if initRealityProfile 2>/dev/null; then
        return 1
    fi
    [[ ! -e "${entryHostFile}" ]]

    AUTO_ENTRY_HOST=node.example.com
    AUTO_REALITY_TARGET=bad.example.com:70000
    realityTargetHost=
    realityTargetPort=
    realitySNI=
    realityEntryHost=

    selectCustomInstallType=",1,"
    if initXrayConfig custom 1 true 2>/dev/null; then
        return 1
    fi
    [[ "${allowCalls}" == "0" ]]
    [[ "${keyCalls}" == "0" ]]
    [[ ! -e "${entryHostFile}" ]]
    [[ ! -e "${xrayRoot}07_VLESS_vision_reality_inbounds.json" ]]

    selectCustomInstallType=",2,"
    if initXrayConfig custom 1 true 2>/dev/null; then
        return 1
    fi
    [[ "${allowCalls}" == "0" ]]
    [[ "${keyCalls}" == "0" ]]
    [[ ! -e "${entryHostFile}" ]]
    [[ ! -e "${xrayRoot}12_VLESS_XHTTP_inbounds.json" ]]

    selectCustomInstallType=",1,"
    if initSingBoxConfig custom 1 true 2>/dev/null; then
        return 1
    fi
    [[ "${allowCalls}" == "0" ]]
    [[ "${keyCalls}" == "0" ]]
    [[ "${portReads}" == "0" ]]
    [[ ! -e "${entryHostFile}" ]]
    [[ ! -e "${singBoxRoot}07_VLESS_vision_reality_inbounds.json" ]]
)

runRealityCandidateFastRegression() {
    local fixtureFile="${TMP_DIR}/reality-candidates-fast.txt"
    local cacheFile="${TMP_DIR}/reality-target-cache-fast.tsv"
    local oldCandidatesFile="${PADM_REALITY_TARGET_CANDIDATES_FILE:-}"
    local oldResultsFile="${PADM_REALITY_TARGET_RESULTS_FILE:-}"
    local oldRealityPageSize="${REALITY_TARGET_PAGE_SIZE:-}"
    local oldAutoInstall="${AUTO_INSTALL:-}"
    local ipv6OpenSslArgsFile="${TMP_DIR}/reality-ipv6-openssl-args.txt"
    local firstRecommendedRealityCandidate firstDeveloperRealityCandidate microsoftCandidate cachedLine resolvedAddresses

    cat >"${fixtureFile}" <<'EOF'
www.ibm.com|www.ibm.com|IBM|global|large_site|unknown|1|yes|fixture default
www.microsoft.com|www.microsoft.com|Microsoft|global|large_site|unknown|2|yes|fixture microsoft
www.reuters.com|www.reuters.com|Reuters|global|media|unknown|3|yes|fixture media
nodejs.org|nodejs.org|Node.js|global|developer|unknown|4|yes|fixture developer
www.asus.com|www.asus.com|ASUS|asia|large_site|unknown|5|no|fixture asia manual
www.cloudflare.com|www.cloudflare.com|Cloudflare|global|cdn|yes|6|no|fixture blocked
www.apple.com|www.apple.com|Apple|global|large_site|unknown|7|no|fixture blocked
EOF
    export PADM_REALITY_TARGET_CANDIDATES_FILE="${fixtureFile}"
    REALITY_TARGET_PAGE_SIZE=2
    AUTO_INSTALL=

    [[ "$(realityTargetCandidateCount)" == "5" ]]
    [[ "$(realityTargetFilteredCandidateCount recommended)" == "4" ]]
    [[ "$(realityTargetFilteredCandidateCount developer)" == "1" ]]
    [[ "$(realityTargetFilteredCandidateCount asia)" == "1" ]]
    [[ "$(realityTargetFilteredCandidateCount microsoft)" == "1" ]]
    firstRecommendedRealityCandidate=$(realityTargetFilteredCandidateLineByIndex recommended 1)
    [[ "$(realityTargetCandidateField "${firstRecommendedRealityCandidate}" 1)" == "www.ibm.com" ]]
    firstDeveloperRealityCandidate=$(realityTargetFilteredCandidateLineByIndex developer 1)
    [[ "$(realityTargetCandidateField "${firstDeveloperRealityCandidate}" 5)" == "developer" ]]
    export PADM_REALITY_TARGET_RESULTS_FILE="${cacheFile}"
    formatRealityTargetResultLine "www.ibm.com:443" "www.ibm.com" "IBM" "large_site" "no" "192.0.2.44" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "cached" >"${cacheFile}"
    [[ "$(realityTargetCachedAsnSummary "www.ibm.com:443")" == "192.0.2.44 AS64500 ExampleNet" ]]
    [[ "$(realityTargetCachedNetworkSummary "www.ibm.com:443")" == "同 ASN" ]]
    [[ "$(realityTargetCachedAsnSummary "missing.example.com:443")" == "暂无缓存" ]]
    writeRealityTargetCacheLine "www.ibm.com:443" "B" "yes" "2048" "yes" "1234567891" "updated"
    cachedLine=$(realityTargetResultLine "www.ibm.com:443" 2>/dev/null || true)
    [[ -z "${cachedLine}" ]]
    [[ "$(realityTargetResultCount)" == "0" ]]
    formatRealityTargetResultLine "legacy.example.com:443" "legacy.example.com" "Legacy" "test" "yes" "192.0.2.45" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567892" "legacy risk" >"${cacheFile}"
    [[ "$(realityTargetResultCount)" == "0" ]]
    ! realityTargetResultLine "legacy.example.com:443"
    openssl() {
        printf '%s\n' "$*" >"${ipv6OpenSslArgsFile}"
        printf 'Protocol version: TLSv1.3\n'
    }
    timeout() {
        shift 3
        "$@"
    }
    probeRealityTargetTls "" "2001:db8::1" "ipv6.example.com" 443 >/dev/null
    grep -qF -- '-connect [2001:db8::1]:443' "${ipv6OpenSslArgsFile}"
    unset -f openssl timeout
    dig() {
        local type=A status=NOERROR address=192.0.2.60
        if [[ " $* " == *' AAAA '* ]]; then
            type=AAAA
            status=${PADM_FAKE_AAAA_DNS_STATUS:-NOERROR}
            address=2001:db8::60
        fi
        printf ';; ->>HEADER<<- opcode: QUERY, status: %s, id: 1\n' "${status}"
        [[ "${status}" == "NOERROR" ]] && printf 'fixture.example.com. 60 IN %s %s\n' "${type}" "${address}"
    }
    PADM_FAKE_AAAA_DNS_STATUS=SERVFAIL
    ! padmRealResolveRealityTargetAddresses fixture.example.com
    PADM_FAKE_AAAA_DNS_STATUS=NOERROR
    resolvedAddresses=$(padmRealResolveRealityTargetAddresses fixture.example.com)
    grep -qxF '192.0.2.60' <<<"${resolvedAddresses}"
    grep -qxF '2001:db8::60' <<<"${resolvedAddresses}"
    unset PADM_FAKE_AAAA_DNS_STATUS
    unset -f dig
    ! realityTargetCandidates | grep -q '^www.cloudflare.com|'
    ! realityTargetCandidates | grep -q '^www.apple.com|'

    selectRealityTargetCandidateInteractive recommended <<<"n
3
"
    [[ "${realityTargetHost}" == "www.reuters.com" ]]
    microsoftCandidate=$(realityTargetFilteredCandidateLineByIndex microsoft 1)
    [[ "$(realityTargetCandidateField "${microsoftCandidate}" 1)" == "www.microsoft.com" ]]
    selectRealityTargetCandidateInteractive recommended <<<"m
manual.example.com:8443
"
    [[ "${realityTargetHost}" == "manual.example.com" ]]
    [[ "${realityTargetPort}" == "8443" ]]
    if selectRealityTargetCandidateInteractive recommended <<<"r
"; then
        return 1
    fi

    if [[ -n "${oldCandidatesFile}" ]]; then
        export PADM_REALITY_TARGET_CANDIDATES_FILE="${oldCandidatesFile}"
    else
        unset PADM_REALITY_TARGET_CANDIDATES_FILE
    fi
    if [[ -n "${oldAutoInstall}" ]]; then
        AUTO_INSTALL="${oldAutoInstall}"
    else
        unset AUTO_INSTALL
    fi
    if [[ -n "${oldResultsFile}" ]]; then
        export PADM_REALITY_TARGET_RESULTS_FILE="${oldResultsFile}"
    else
        unset PADM_REALITY_TARGET_RESULTS_FILE
    fi
    if [[ -n "${oldRealityPageSize}" ]]; then
        REALITY_TARGET_PAGE_SIZE="${oldRealityPageSize}"
    else
        unset REALITY_TARGET_PAGE_SIZE
    fi
}

runRealityAsnScanPlanRegression() {
    local asnPrefixFile="${TMP_DIR}/asn-prefixes.txt"
    local sampleFile="${TMP_DIR}/asn-sample-ips.txt"
    local oldAutoInstall="${AUTO_INSTALL:-}"
    local sampleCount=0
    local _sampleIp prefixFirst prefixLast prefixUsable
    AUTO_INSTALL=
    cat >"${asnPrefixFile}" <<'EOF'
192.0.2.0/24
198.51.100.0/25
203.0.113.0/26
10.0.0.0/27
172.16.0.0/28
EOF
    IFS=$'\t' read -r prefixFirst prefixLast prefixUsable <<<"$(realityAsnPrefixUsableRange "172.16.0.0/28")"
    [[ "$(realityIntToIpv4 "${prefixFirst}")" == "172.16.0.1" ]]
    [[ "$(realityIntToIpv4 "${prefixLast}")" == "172.16.0.14" ]]
    [[ "${prefixUsable}" == "14" ]]
    [[ "$(realityAsnPrefixTotalUsableAddressCount <"${asnPrefixFile}")" == "486" ]]
    generateRealityAsnSampleIps "${asnPrefixFile}" 12 "${sampleFile}"
    while IFS= read -r _sampleIp; do
        sampleCount=$((sampleCount + 1))
    done <"${sampleFile}"
    [[ "${sampleCount}" == "12" ]]
    awk '!seen[$0]++ {next} {exit 1}' "${sampleFile}"
    selectRealityAsnScanPlan AS64500 "${asnPrefixFile}" <<<"5
12
y
"
    [[ -f "${selectedRealityScannerPrefixFile}" ]]
    [[ "${selectedRealityAsnSampleSize}" == "12" ]]
    [[ "${selectedRealityAsnPrefixTotal}" == "5" ]]
    [[ "${selectedRealityAsnAddressTotal}" == "12" ]]
    [[ "${selectedRealityScannerRange}" == "本次抽样 12 IP（ASN 总可用 486）" ]]
    sampleCount=0
    while IFS= read -r _sampleIp; do
        sampleCount=$((sampleCount + 1))
    done <"${selectedRealityScannerPrefixFile}"
    [[ "${sampleCount}" == "12" ]]
    rm -f "${selectedRealityScannerPrefixFile}"
    selectRealityAsnScanPlan AS64500 "${asnPrefixFile}" <<<"6
y
"
    [[ "${selectedRealityAsnFullScan}" == "true" ]]
    [[ "${selectedRealityAsnSampleSize}" == "486" ]]
    [[ "${selectedRealityScannerRange}" == "全量公告前缀 5 prefixes" ]]
    rm -f "${selectedRealityScannerPrefixFile}"
    if [[ -n "${oldAutoInstall}" ]]; then
        AUTO_INSTALL="${oldAutoInstall}"
    else
        unset AUTO_INSTALL
    fi
}

runRealityCandidateFullRegression() {
    local firstRecommendedRealityCandidate firstDeveloperRealityCandidate firstRealityCandidate secondRealityCandidate blockedCloudflareRealityCandidate
    [[ "$(realityTargetCandidateCount)" -ge 194 ]]
    [[ "$(realityTargetFilteredCandidateCount recommended)" -ge 40 ]]
    [[ "$(realityTargetFilteredCandidateCount developer)" -ge 10 ]]
    [[ "$(realityTargetFilteredCandidateCount asia)" -ge 2 ]]
    [[ "$(realityTargetFilteredCandidateCount microsoft)" -ge 1 ]]
    firstRecommendedRealityCandidate=$(realityTargetFilteredCandidateLineByIndex recommended 1)
    [[ "$(realityTargetCandidateField "${firstRecommendedRealityCandidate}" 1)" == "www.ibm.com" ]]
    firstDeveloperRealityCandidate=$(realityTargetFilteredCandidateLineByIndex developer 1)
    [[ "$(realityTargetCandidateField "${firstDeveloperRealityCandidate}" 5)" == "developer" ]]
    firstRealityCandidate=$(realityTargetCandidateLineByIndex 1)
    [[ "$(realityTargetCandidateField "${firstRealityCandidate}" 1)" == "www.ibm.com" ]]
    secondRealityCandidate=$(realityTargetCandidateLineByIndex 2)
    [[ "$(realityTargetCandidateField "${secondRealityCandidate}" 1)" == "www.microsoft.com" ]]
    blockedCloudflareRealityCandidate=$(realityTargetBlockedCandidates | grep '^www.cloudflare.com|')
    [[ -n "${blockedCloudflareRealityCandidate}" ]]
    realityTargetBlockedCandidates >/dev/null
    ! realityTargetCandidates | grep -q '^www.cloudflare.com|'
    ! realityTargetCandidates | grep -q '^www.apple.com|'
}

runRealityBlockedCandidateTransactionRegression() (
    local rootRel="${TMP_DIR}/reality-blocked-write-transaction"
    local root blockedFile
    local oldBlockedFile="${PADM_REALITY_TARGET_BLOCKED_FILE:-}"
    local rc

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    blockedFile="${root}/reality_target_blocked.tsv"
    printf 'old.example.com|手动加入|legacy|old note\n' >"${blockedFile}"
    export PADM_REALITY_TARGET_BLOCKED_FILE="${blockedFile}"

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${blockedFile}" ]]; then
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    regressionExpectStatus 1 addRealityTargetBlockedCandidate "new.example.com:443" "manual" >/dev/null 2>&1
    [[ "$(<"${blockedFile}")" == "old.example.com|手动加入|legacy|old note" ]]
    ! compgen -G "${root}/.reality_target_blocked.tsv.reality.*" >/dev/null

    commitGeneratedFile() {
        originalCommitGeneratedFile "$@"
    }
    addRealityTargetBlockedCandidate "new.example.com:443" "manual" >/dev/null
    grep -q '^new.example.com|手动加入|manual|' "${blockedFile}"
    addRealityTargetBlockedCandidate "new.example.com:443" "manual" >/dev/null
    [[ "$(grep -c '^new.example.com|' "${blockedFile}")" == "1" ]]
    ! compgen -G "${root}/.reality_target_blocked.tsv.reality.*" >/dev/null

    if [[ -n "${oldBlockedFile}" ]]; then
        export PADM_REALITY_TARGET_BLOCKED_FILE="${oldBlockedFile}"
    else
        unset PADM_REALITY_TARGET_BLOCKED_FILE
    fi
)

runRealityConfigVlessEncryptionRegression() (
    local fakeXrayBinary="${TMP_DIR}/fake-xray-vlessenc"
    local vlessConfigDir="${TMP_DIR}/vlessenc-xray-conf"
    local vlessConfigFile="${vlessConfigDir}/07_VLESS_vision_reality_inbounds.json"
    local xhttpConfigFile="${vlessConfigDir}/12_VLESS_XHTTP_inbounds.json"
    local vlessStateFile="${TMP_DIR}/vlessenc-state.json"
    local oldTmpDir="${TMPDIR:-}"
    local vlessTmpRoot="${TMP_DIR}/vlessenc-tmp"
    local vlessTmpMarker="${TMP_DIR}/vlessenc-tmp-files.txt"
    local vlessOriginalConfig
    local vlessOriginalState
    local vlessEnabledConfig
    local vlessEnabledState
    local xhttpOriginalConfig
    local vlessValidateMode=success
    refreshPublishedSubscriptions() { return 0; }
    mkdir -p "${vlessTmpRoot}"
    : >"${vlessTmpMarker}"
    TMPDIR="${vlessTmpRoot}"
    cat >"${fakeXrayBinary}" <<'SH'
#!/usr/bin/env bash
case "$1" in
--version)
    printf 'Xray 25.9.5 test\n'
    ;;
vlessenc)
    find "${TMPDIR:-/tmp}" -maxdepth 1 -type f \( -name 'padm-vlessenc.out.*' -o -name 'padm-vlessenc.err.*' \) -print >>"${PADM_FAKE_VLESSENC_TMP_MARKER}" 2>/dev/null || true
    printf '{"encryption":"mlkem768x25519plus.native.0rtt.test","decryption":"mlkem768x25519plus.native.0rtt.test"}\n'
    ;;
-test)
    [[ "${PADM_FAKE_XRAY_VALIDATE_MODE:-success}" == "success" ]]
    ;;
*)
    exit 1
    ;;
esac
SH
    chmod +x "${fakeXrayBinary}"
    mkdir -p "${vlessConfigDir}"
    cat >"${vlessConfigFile}" <<'JSON'
{"inbounds":[{"settings":{"decryption":"none","fallbacks":[{"dest":80}],"clients":[{"id":"uuid"}]}}]}
JSON
    printf '{"enabled":false,"encryption":"old","decryption":"old"}\n' >"${vlessStateFile}"
    vlessOriginalConfig=$(<"${vlessConfigFile}")
    vlessOriginalState=$(<"${vlessStateFile}")
    subscribePort=39778
    nginxConfigPath="${TMP_DIR}/nginx/"
    mkdir -p "${nginxConfigPath}"
    export PADM_XRAY_BINARY="${fakeXrayBinary}"
    export PADM_XRAY_CONF_DIR="${vlessConfigDir}"
    export PADM_VLESS_REALITY_CONFIG_FILE="${vlessConfigFile}"
    export PADM_VLESS_XHTTP_CONFIG_FILE="${TMP_DIR}/missing-xhttp.json"
    export PADM_VLESS_ENCRYPTION_STATE_FILE="${vlessStateFile}"
    export PADM_FAKE_VLESSENC_TMP_MARKER="${vlessTmpMarker}"
    export PADM_FAKE_XRAY_VALIDATE_MODE="fail"
    coreInstallType=1
    if setVlessRealityEncryption enable; then
        return 1
    fi
    [[ "$(<"${vlessConfigFile}")" == "${vlessOriginalConfig}" ]]
    [[ "$(<"${vlessStateFile}")" == "${vlessOriginalState}" ]]
    [[ ! -e "${vlessConfigFile}.tmp" ]]
    [[ ! -e "${vlessConfigFile}.vlessenc.bak" ]]
    [[ ! -e "${vlessStateFile}.tmp" ]]
    grep -q "${vlessTmpRoot}/padm-vlessenc.out" "${vlessTmpMarker}"
    grep -q "${vlessTmpRoot}/padm-vlessenc.err" "${vlessTmpMarker}"
    [[ -f "${vlessTmpRoot}/padm-xray-test.log" ]]
    if regressionFindHasMatches "${vlessTmpRoot}" -mindepth 1 -maxdepth 1 \( -name 'padm-vlessenc.out.*' -o -name 'padm-vlessenc.err.*' \); then
        return 1
    fi

    (
        local helperLog="${TMP_DIR}/vlessenc-config-backup-helper.log"
        : >"${helperLog}"
        backupManagedFileToPath() {
            if [[ "$1" == "${vlessConfigFile}" ]]; then
                return 1
            fi
            command cp -p "$1" "$2"
        }
        coreSetManualCheckMessage() {
            printf "manual-check:%s|%s\n" "$2" "$3" >>"${helperLog}"
            printf -v "$1" "%s，请手动检查%s" "$2" "$3"
        }
        if setVlessRealityEncryption enable >/dev/null 2>&1; then
            return 1
        fi
        [[ "$(<"${vlessConfigFile}")" == "${vlessOriginalConfig}" ]]
        [[ "$(<"${vlessStateFile}")" == "${vlessOriginalState}" ]]
        grep -q "manual-check:创建 VLESS Encryption 配置备份失败| ${vlessConfigFile}" "${helperLog}"
    ) || return 1

    export PADM_FAKE_XRAY_VALIDATE_MODE="success"
    setVlessRealityEncryption enable
    jq -e '.inbounds[0].settings.decryption == "mlkem768x25519plus.native.0rtt.test" and (.inbounds[0].settings.fallbacks | not) and .inbounds[0].settings.clients[0].flow == "xtls-rprx-vision"' "${vlessConfigFile}" >/dev/null
    jq -e '.enabled == true and .encryption == "mlkem768x25519plus.native.0rtt.test"' "${vlessStateFile}" >/dev/null
    [[ ! -e "${vlessConfigFile}.vlessenc.bak" ]]
    [[ ! -e "${vlessStateFile}.bak" ]]
    vlessEnabledConfig=$(<"${vlessConfigFile}")
    vlessEnabledState=$(<"${vlessStateFile}")
    (
        rm() {
            local arg
            for arg in "$@"; do
                [[ "${arg}" == "${vlessStateFile}" ]] && return 1
            done
            command rm "$@"
        }
        set +e
        setVlessRealityEncryption disable >/dev/null 2>&1
        local disableStatus=$?
        set -e
        [[ "${disableStatus}" == "1" ]]
        [[ "$(<"${vlessConfigFile}")" == "${vlessEnabledConfig}" ]]
        [[ "$(<"${vlessStateFile}")" == "${vlessEnabledState}" ]]
        [[ ! -e "${vlessConfigFile}.vlessenc.bak" ]]
        [[ ! -e "${vlessStateFile}.bak" ]]
    ) || return 1
    setVlessRealityEncryption disable
    jq -e '.inbounds[0].settings.decryption == "none" and (.inbounds[0].settings.fallbacks | not)' "${vlessConfigFile}" >/dev/null
    [[ ! -e "${vlessStateFile}" ]]
    if regressionFindHasMatches "${vlessTmpRoot}" -mindepth 1 -maxdepth 1 \( -name 'padm-vlessenc.out.*' -o -name 'padm-vlessenc.err.*' \); then
        return 1
    fi

    cat >"${xhttpConfigFile}" <<'JSON'
{"inbounds":[{"settings":{"decryption":"none","fallbacks":[{"dest":80}],"clients":[{"id":"uuid","flow":"xtls-rprx-vision"}]},"streamSettings":{"network":"xhttp"}}]}
JSON
    xhttpOriginalConfig=$(<"${xhttpConfigFile}")
    export PADM_VLESS_XHTTP_CONFIG_FILE="${xhttpConfigFile}"
    export PADM_FAKE_XRAY_VALIDATE_MODE="success"
    setVlessRealityEncryption enable
    jq -e '.inbounds[0].settings.decryption == "mlkem768x25519plus.native.0rtt.test" and (.inbounds[0].settings.fallbacks | not) and (.inbounds[0].settings.clients[0].flow | not)' "${xhttpConfigFile}" >/dev/null
    jq -e '.enabled == true and .encryption == "mlkem768x25519plus.native.0rtt.test"' "${vlessStateFile}" >/dev/null
    [[ ! -e "${xhttpConfigFile}.vlessenc.bak" ]]
    setVlessRealityEncryption disable
    jq -e '.inbounds[0].settings.decryption == "none" and (.inbounds[0].settings.fallbacks | not) and (.inbounds[0].settings.clients[0].flow | not)' "${xhttpConfigFile}" >/dev/null
    [[ ! -e "${vlessStateFile}" ]]
    printf '%s\n' "${xhttpOriginalConfig}" >"${xhttpConfigFile}"

    PADM_VLESS_ENCRYPTION_STATE_FILE="relative-vless-state.json"
    if setVlessRealityEncryption enable >/dev/null 2>&1; then
        return 1
    fi
    [[ ! -e "${vlessConfigFile}.vlessenc.bak" ]]
    [[ ! -e "${vlessConfigFile}.tmp" ]]
    [[ ! -e "${vlessTmpRoot}/relative-vless-state.json" ]]
    unset PADM_XRAY_BINARY PADM_XRAY_CONF_DIR PADM_VLESS_REALITY_CONFIG_FILE PADM_VLESS_XHTTP_CONFIG_FILE PADM_VLESS_ENCRYPTION_STATE_FILE PADM_FAKE_XRAY_VALIDATE_MODE PADM_FAKE_VLESSENC_TMP_MARKER
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runRealityConfigScannerRegression() {
    local scannerCandidatesFile="${TMP_DIR}/reality-config-scanner-candidates.txt"
    local oldCandidatesFile="${PADM_REALITY_TARGET_CANDIDATES_FILE:-}"
    local scannerLine refreshScannerLine sameAsnLine batchLinesFile failedTargetsFile emptyLinesFile scannerSummary sameAsnSummary seenDomainsFile
    local asnLookupFile="${TMP_DIR}/reality-scanner-asn-lookups.log"
    local concurrencyDir="${TMP_DIR}/reality-scanner-concurrency"
    local refreshConcurrencyDir="${TMP_DIR}/reality-refresh-concurrency"
    local refreshTimeoutLog="${TMP_DIR}/reality-refresh-timeout.log"
    local maxConcurrency refreshMaxConcurrency
    local scannerImported scannerSkipped scannerA scannerB scannerC scannerFail
    cat >"${scannerCandidatesFile}" <<'EOF'
fail-auto.example.com|fail-auto.example.com|Fail Auto|global|large_site|unknown|1|yes|fixture failing candidate
www.ibm.com|www.ibm.com|IBM|global|large_site|unknown|2|yes|fixture fallback candidate
EOF
    export PADM_REALITY_TARGET_CANDIDATES_FILE="${scannerCandidatesFile}"

    rm -f "${PADM_REALITY_TARGET_SCAN_FILE}" "${REALITY_TLS_PING_ARGS_FILE}" "${asnLookupFile}" "${refreshTimeoutLog}"
    mkdir -p "${refreshConcurrencyDir}"
    export REALITY_ASN_LOOKUP_ARGS_FILE="${asnLookupFile}"
    export PADM_REALITY_SECONDARY_JOBS=4
    validateRealityTargetSelection manual "manual-b.example.com:443" "manual-b.example.com"
    ! validateRealityTargetSelection auto "manual-b.example.com:443" "manual-b.example.com"
    validateRealityTargetSelection manual "manual-c.example.com:443" "manual-c.example.com"
    ! validateRealityTargetSelection auto "manual-c.example.com:443" "manual-c.example.com"
    ! validateRealityTargetSelection manual "fail.example.com:443" "fail.example.com"
    ! validateRealityTargetSelection manual "relay-asn.example.com:443" "relay-asn.example.com"
    ! validateRealityTargetSelection manual "relay-sni.example.com:443" "relay-sni.example.com"
    ! validateRealityTargetSelection manual "unknown-risk.example.com:443" "unknown-risk.example.com"
    ! validateRealityTargetSelection manual "multi-risk.example.com:443" "multi-risk.example.com"
    rm -f "${REALITY_TLS_PING_ARGS_FILE}" "${asnLookupFile}" "${refreshTimeoutLog}"
    export PADM_FAKE_XRAY_CONCURRENCY_DIR="${refreshConcurrencyDir}"
    timeout() {
        [[ "$1" == "-k" && "$2" == "2" && "$3" == "15" ]] || return 2
        printf '%s %s %s\n' "$1" "$2" "$3" >>"${refreshTimeoutLog}"
        shift 3
        "$@"
    }
    scanLocalAsnRealityTargets
    [[ "$(wc -l <"${REALITY_TLS_PING_ARGS_FILE}" | tr -d ' ')" == "3" ]]
    [[ "$(wc -l <"${asnLookupFile}" | tr -d ' ')" == "2" ]]
    [[ "$(grep -cFx -- '-k 2 15' "${refreshTimeoutLog}")" == "3" ]]
    ! grep -qF $'fail-auto.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
    grep -qF $'www.ibm.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
    refreshMaxConcurrency=$(sort -nr "${refreshConcurrencyDir}/observed" | head -n 1)
    [[ "${refreshMaxConcurrency}" -ge 2 && "${refreshMaxConcurrency}" -le 4 ]]
    writeRealityTargetResultLine "refresh-scanner.example.com:8443" "sni.refresh-scanner.example.com" "Refresh Scanner" "scanner" "no" "198.51.100.20" "AS64501" "RemoteNet" "different_network" "A" "yes" "4096" "yes" "1234567890" "RealiTLScanner: Fixture CA; old result"
    writeRealityTargetResultLine "refresh-network-fail.example.com:443" "refresh-network-fail.example.com" "Refresh Network Fail" "test" "no" "198.51.100.21" "AS64501" "RemoteNet" "different_network" "A" "yes" "4096" "yes" "1234567890" "stale A fixture"
    resolveRealityTargetAddresses() {
        [[ "$1" == "refresh-network-fail.example.com" ]] && return 1
        printf '192.0.2.1\n'
    }
    rm -f "${REALITY_TLS_PING_ARGS_FILE}" "${asnLookupFile}" "${refreshTimeoutLog}"
    scanLocalAsnRealityTargets
    [[ "$(wc -l <"${REALITY_TLS_PING_ARGS_FILE}" | tr -d ' ')" == "4" ]]
    grep -qxF "tls ping -ip 192.0.2.1 www.ibm.com:443" "${REALITY_TLS_PING_ARGS_FILE}"
    grep -qxF "tls ping -ip 192.0.2.1 sni.refresh-scanner.example.com:8443" "${REALITY_TLS_PING_ARGS_FILE}"
    ! grep -qF "fail-auto.example.com" "${REALITY_TLS_PING_ARGS_FILE}"
    [[ "$(wc -l <"${asnLookupFile}" | tr -d ' ')" == "2" ]]
    [[ "$(grep -cFx -- '-k 2 15' "${refreshTimeoutLog}")" == "4" ]]
    ! grep -qF $'refresh-network-fail.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
    refreshScannerLine=$(grep -F $'refresh-scanner.example.com:8443\tsni.refresh-scanner.example.com\tRefresh Scanner\tscanner\tno\t' "${PADM_REALITY_TARGET_SCAN_FILE}")
    [[ "$(realityTargetResultField "${refreshScannerLine}" 9)" == "same_asn" ]]
    [[ "$(realityTargetResultField "${refreshScannerLine}" 15)" == "RealiTLScanner: Fixture CA; TLS 1.3 + X25519MLKEM768 可用，证书链长度满足 Xray 要求" ]]
    resolveRealityTargetAddresses() { printf '192.0.2.1\n'; }
    unset -f timeout
    unset REALITY_ASN_LOOKUP_ARGS_FILE PADM_FAKE_XRAY_CONCURRENCY_DIR PADM_REALITY_SECONDARY_JOBS

    cat >"${TMP_DIR}/realitlscanner.csv" <<'CSV'
IP,ORIGIN,TLS,ALPN,CURVE,CERT_LENGTH,CERT_SIGNATURE,CERT_PUBLICKEY,CERT_DOMAIN,CERT_ISSUER,GEO_CODE
192.0.2.10,192.0.2.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,www.cloudflare.com,"Google Trust Services",N/A
198.51.100.11,198.51.100.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,scanner.example.com,"Let's Encrypt, Inc.",N/A
198.51.100.12,198.51.100.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,scanner.example.com,"Duplicate",N/A
198.51.100.13,198.51.100.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,scanner-two.example.com,"Let's Encrypt",N/A
198.51.100.14,198.51.100.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,scanner-three.example.com,"Let's Encrypt",N/A
198.51.100.15,198.51.100.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,scanner-four.example.com,"Let's Encrypt",N/A
198.51.100.16,198.51.100.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,scanner-five.example.com,"Let's Encrypt",N/A
198.51.100.17,198.51.100.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,fail.example.com,"Let's Encrypt",N/A
192.0.2.12,192.0.2.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,images.apple.com,"Apple Inc.",N/A
192.0.2.13,192.0.2.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,Common Name,"Test",N/A
192.0.2.14,192.0.2.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,CloudFlare Origin Certificate,"CloudFlare, Inc.",N/A
192.0.2.15,192.0.2.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,localhost,"Test",N/A
192.0.2.16,192.0.2.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,invalid.invalid,"Invalid",N/A
192.0.2.17,192.0.2.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,192.0.2.17,"Self",N/A
CSV
    printf 'IP,ORIGIN,TLS\n192.0.2.1,192.0.2.0/24,TLS 1.3\n' >"${TMP_DIR}/realitlscanner-invalid.csv"
    ! normalizeRealityScannerCsv "${TMP_DIR}/realitlscanner-invalid.csv" >/dev/null
    rm -f "${REALITY_TLS_PING_ARGS_FILE}" "${asnLookupFile}"
    mkdir -p "${concurrencyDir}"
    export REALITY_ASN_LOOKUP_ARGS_FILE="${asnLookupFile}"
    export PADM_FAKE_XRAY_CONCURRENCY_DIR="${concurrencyDir}"
    export PADM_REALITY_SECONDARY_JOBS=4
    importRealityScannerResults "${TMP_DIR}/realitlscanner.csv" "AS64500" "ExampleNet" scannerSummary
    IFS=$'\t' read -r scannerImported scannerSkipped scannerA scannerB scannerC scannerFail <<<"${scannerSummary}"
    [[ "${scannerImported}" == "5" ]]
    [[ "${scannerSkipped}" == "9" ]]
    [[ "${scannerA}" == "5" ]]
    [[ "${scannerB}" == "0" ]]
    [[ "${scannerC}" == "0" ]]
    [[ "${scannerFail}" == "1" ]]
    [[ "$(wc -l <"${REALITY_TLS_PING_ARGS_FILE}" | tr -d ' ')" == "11" ]]
    [[ "$(grep -c 'scanner.example.com:443' "${REALITY_TLS_PING_ARGS_FILE}")" == "1" ]]
    [[ "$(wc -l <"${asnLookupFile}" | tr -d ' ')" == "5" ]]
    ! grep -qx '198.51.100.17' "${asnLookupFile}"
    maxConcurrency=$(sort -nr "${concurrencyDir}/observed" | head -n 1)
    [[ "${maxConcurrency}" -ge 2 && "${maxConcurrency}" -le 4 ]]
    scannerLine=$(grep -F $'scanner.example.com:443\tscanner.example.com\tscanner.example.com\tscanner' "${PADM_REALITY_TARGET_SCAN_FILE}")
    [[ "$(realityTargetResultField "${scannerLine}" 7)" == "AS64501" ]]
    [[ "$(realityTargetResultField "${scannerLine}" 8)" == "RemoteNet" ]]
    [[ "$(realityTargetResultField "${scannerLine}" 9)" == "different_network" ]]
    [[ "$(realityTargetResultField "${scannerLine}" 15)" == *"RealiTLScanner: Let's Encrypt, Inc.;"* ]]
    grep -qF $'scanner-five.example.com:443\tscanner-five.example.com' "${PADM_REALITY_TARGET_SCAN_FILE}"

    unset PADM_FAKE_XRAY_CONCURRENCY_DIR
    seenDomainsFile="${TMP_DIR}/reality-scanner-seen-domains.txt"
    : >"${seenDomainsFile}"
    cat >"${TMP_DIR}/realitlscanner-same-asn-1.csv" <<'CSV'
IP,ORIGIN,CERT_DOMAIN,CERT_ISSUER,GEO_CODE
192.0.2.30,192.0.2.0/24,sameasn.example.com,"Let's Encrypt",N/A
CSV
    cat >"${TMP_DIR}/realitlscanner-same-asn-2.csv" <<'CSV'
IP,ORIGIN,CERT_DOMAIN,CERT_ISSUER,GEO_CODE
192.0.2.31,192.0.2.0/24,sameasn.example.com,"Let's Encrypt",N/A
CSV
    rm -f "${asnLookupFile}"
    importRealityScannerResults "${TMP_DIR}/realitlscanner-same-asn-1.csv" "AS64500" "ExampleNet" sameAsnSummary same_asn "${seenDomainsFile}"
    IFS=$'\t' read -r scannerImported scannerSkipped scannerA scannerB scannerC scannerFail <<<"${sameAsnSummary}"
    [[ "${scannerImported}" == "1" && "${scannerSkipped}" == "0" ]]
    importRealityScannerResults "${TMP_DIR}/realitlscanner-same-asn-2.csv" "AS64500" "ExampleNet" sameAsnSummary same_asn "${seenDomainsFile}"
    IFS=$'\t' read -r scannerImported scannerSkipped scannerA scannerB scannerC scannerFail <<<"${sameAsnSummary}"
    [[ "${scannerImported}" == "0" && "${scannerSkipped}" == "1" ]]
    [[ ! -s "${asnLookupFile}" ]]
    [[ "$(grep -c 'sameasn.example.com:443' "${REALITY_TLS_PING_ARGS_FILE}")" == "1" ]]
    sameAsnLine=$(grep -F $'sameasn.example.com:443\tsameasn.example.com' "${PADM_REALITY_TARGET_SCAN_FILE}")
    [[ "$(realityTargetResultField "${sameAsnLine}" 7)" == "AS64500" ]]
    [[ "$(realityTargetResultField "${sameAsnLine}" 9)" == "same_asn" ]]
    unset REALITY_ASN_LOOKUP_ARGS_FILE PADM_REALITY_SECONDARY_JOBS
    batchLinesFile="${TMP_DIR}/reality-batch-lines.tsv"
    failedTargetsFile="${TMP_DIR}/reality-failed-targets.txt"
    emptyLinesFile="${TMP_DIR}/reality-empty-lines.tsv"
    writeRealityTargetResultLine "batch-old.example.com:443" "old.example.com" "Old Batch" "test" "unknown" "192.0.2.20" "AS64500" "ExampleNet" "same_asn" "B" "yes" "4096" "yes" "1234567800" "old batch line"
    writeRealityTargetResultLine "single-drop.example.com:443" "single-drop.example.com" "Single Drop" "test" "no" "192.0.2.23" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567800" "old A line"
    writeRealityTargetResultLine "single-drop.example.com:443" "single-drop.example.com" "Single Drop" "test" "unknown" "192.0.2.23" "AS64500" "ExampleNet" "same_asn" "C" "no" "4096" "yes" "1234567801" "new C line"
    ! grep -qF $'single-drop.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
    writeRealityTargetResultLine "batch-drop.example.com:443" "batch-drop.example.com" "Batch Drop" "test" "no" "192.0.2.24" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567800" "old A batch line"
    {
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "batch-old.example.com:443" "new.example.com" "New Batch" "test" "no" "192.0.2.21" "AS64500" "ExampleNet" "same_asn" "A" "yes" "8192" "yes" "1234567899" "new batch line"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "batch-new.example.com:443" "batch-new.example.com" "Batch New" "test" "unknown" "192.0.2.22" "AS64500" "ExampleNet" "same_asn" "B" "yes" "4096" "yes" "1234567898" "second batch line"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "batch-drop.example.com:443" "batch-drop.example.com" "Batch Drop" "test" "unknown" "192.0.2.24" "AS64500" "ExampleNet" "same_asn" "C" "no" "4096" "yes" "1234567899" "new C batch line"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "batch-c.example.com:443" "batch-c.example.com" "Batch C" "test" "unknown" "192.0.2.25" "AS64500" "ExampleNet" "same_asn" "C" "no" "4096" "yes" "1234567899" "new C line"
    } >"${batchLinesFile}"
    writeRealityTargetResultLines "${batchLinesFile}"
    batchLine=$(grep -F $'batch-old.example.com:443\tnew.example.com' "${PADM_REALITY_TARGET_SCAN_FILE}")
    [[ "$(realityTargetResultField "${batchLine}" 10)" == "A" ]]
    ! grep -qF $'batch-new.example.com:443\tbatch-new.example.com' "${PADM_REALITY_TARGET_SCAN_FILE}"
    ! grep -qF $'batch-drop.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
    ! grep -qF $'batch-c.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
    awk -F'\t' '$10 != "A" {exit 1}' "${PADM_REALITY_TARGET_SCAN_FILE}"
    formatRealityTargetResultLine "legacy-b.example.com:443" "legacy-b.example.com" "Legacy B" "test" "unknown" "198.51.100.30" "AS64501" "RemoteNet" "different_network" "B" "yes" "4096" "yes" "1234567899" "legacy B" >>"${PADM_REALITY_TARGET_SCAN_FILE}"
    : >"${emptyLinesFile}"
    writeRealityTargetResultLines "${emptyLinesFile}"
    ! grep -qF $'legacy-b.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
    printf '%s\n' "batch-old.example.com:443" >"${failedTargetsFile}"
    printf '%s\n' "batch-old.example.com|batch-old.example.com|Batch Old|global|large_site|unknown|9|yes|batch candidate" >>"${scannerCandidatesFile}"
    removeRealityTargetsFromUnifiedLibrary "${failedTargetsFile}"
    ! grep -qF $'batch-old.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
    ! grep -qF 'batch-old.example.com|' "${scannerCandidatesFile}"

    rm -f "${PADM_REALITY_TARGET_SCAN_FILE}" "${REALITY_TLS_PING_ARGS_FILE}"
    realityTargetCandidateBlocked "images.apple.com"
    unset AUTO_REALITY_SERVER_NAME
    writeRealityTargetResultLine "local.example.com:443" "sni.local.example.com" "Local Example" "test" "no" "192.0.2.1" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "same ASN test target"
    writeRealityTargetResultLine "remote.example.com:443" "sni.remote.example.com" "Remote Example" "test" "no" "198.51.100.1" "AS64501" "RemoteNet" "different_network" "A" "yes" "8192" "yes" "1234567899" "longer cert but different network"
    writeRealityTargetResultLine "hidden-c.example.com:443" "hidden-c.example.com" "Hidden C" "test" "no" "198.51.100.2" "AS64501" "RemoteNet" "different_network" "C" "no" "4096" "yes" "1234567899" "must not persist"
    [[ "$(realityTargetResultCount)" == "2" ]]
    [[ "$(realityTargetFilterTitle all)" == "全部 A 级" ]]
    ! realityTargetScanResultFilterMatches "C" "same_asn" "all" "test"
    if ! selectRealityTargetFromScanResults <<<"1"; then
        return 1
    fi
    [[ "${realityTargetHost}" == "local.example.com" ]]
    [[ "${realitySNI}" == "sni.local.example.com" ]]
    scanLine=$(grep -F $'local.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}")
    [[ "$(realityTargetResultField "${scanLine}" 1)" == "local.example.com:443" ]]
    selectDefaultRealityTarget
    [[ "${realityTargetHost}" == "local.example.com" ]]
    [[ "${realityTargetPort}" == "443" ]]
    [[ "${realitySNI}" == "sni.local.example.com" ]]
    rm -f "${PADM_REALITY_TARGET_SCAN_FILE}" "${REALITY_TLS_PING_ARGS_FILE}"
    unset AUTO_REALITY_SERVER_NAME
    PADM_FAKE_XRAY_ONLY_IBM=true selectDefaultRealityTarget
    [[ "${realityTargetHost}" == "www.ibm.com" ]]
    [[ "${realityTargetPort}" == "443" ]]
    [[ "${realitySNI}" == "www.ibm.com" ]]
    grep -q "tls ping -ip 192.0.2.1 www.ibm.com:443" "${REALITY_TLS_PING_ARGS_FILE}"
    if [[ -n "${oldCandidatesFile}" ]]; then
        export PADM_REALITY_TARGET_CANDIDATES_FILE="${oldCandidatesFile}"
    else
        unset PADM_REALITY_TARGET_CANDIDATES_FILE
    fi
    unset PADM_FAKE_XRAY_ONLY_IBM
}

runRealityUnifiedLibraryRollbackRegression() (
    local rootRel="${TMP_DIR}/reality-unified-library-rollback"
    local root resultsFile candidatesFile targetsFile
    local oldResultsFile="${PADM_REALITY_TARGET_RESULTS_FILE:-}"
    local oldScanFile="${PADM_REALITY_TARGET_SCAN_FILE:-}"
    local oldCandidatesFile="${PADM_REALITY_TARGET_CANDIDATES_FILE:-}"
    local rc

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    resultsFile="${root}/reality_targets_results.tsv"
    candidatesFile="${root}/reality_candidates.tsv"
    targetsFile="${root}/remove-targets.txt"
    export PADM_REALITY_TARGET_RESULTS_FILE="${resultsFile}"
    export PADM_REALITY_TARGET_SCAN_FILE="${resultsFile}"
    export PADM_REALITY_TARGET_CANDIDATES_FILE="${candidatesFile}"

    {
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "remove.example.com:443" "remove.example.com" "Remove Example" "scanner" "unknown" "192.0.2.10" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "remove line"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "keep.example.com:443" "keep.example.com" "Keep Example" "scanner" "unknown" "192.0.2.11" "AS64500" "ExampleNet" "same_asn" "B" "yes" "4096" "yes" "1234567891" "keep line"
    } >"${resultsFile}"
    {
        printf '%s\n' 'remove.example.com|remove.example.com|Remove Example|global|scanner|unknown|9|yes|remove candidate'
        printf '%s\n' 'keep.example.com|keep.example.com|Keep Example|global|scanner|unknown|10|yes|keep candidate'
    } >"${candidatesFile}"
    printf '%s\n' 'remove.example.com:443' >"${targetsFile}"

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${candidatesFile}" ]]; then
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    regressionExpectStatus 1 removeRealityTargetsFromUnifiedLibrary "${targetsFile}" >/dev/null 2>&1
    grep -qF $'remove.example.com:443\t' "${resultsFile}"
    grep -qF $'keep.example.com:443\t' "${resultsFile}"
    grep -q '^remove.example.com|' "${candidatesFile}"
    grep -q '^keep.example.com|' "${candidatesFile}"
    ! compgen -G "${root}/.reality_targets_results.tsv.reality.*" >/dev/null
    ! compgen -G "${root}/.reality_candidates.tsv.reality.*" >/dev/null
    if regressionFindHasMatches "${root}" -maxdepth 1 -type d -name 'padm-check-log-backup.*'; then
        return 1
    fi

    commitGeneratedFile() {
        originalCommitGeneratedFile "$@"
    }
    removeRealityTargetsFromUnifiedLibrary "${targetsFile}"
    ! grep -qF $'remove.example.com:443\t' "${resultsFile}"
    ! grep -qF $'keep.example.com:443\t' "${resultsFile}"
    ! grep -q '^remove.example.com|' "${candidatesFile}"
    grep -q '^keep.example.com|' "${candidatesFile}"
    ! compgen -G "${root}/.reality_targets_results.tsv.reality.*" >/dev/null
    ! compgen -G "${root}/.reality_candidates.tsv.reality.*" >/dev/null
    if regressionFindHasMatches "${root}" -maxdepth 1 -type d -name 'padm-check-log-backup.*'; then
        return 1
    fi

    if [[ -n "${oldResultsFile}" ]]; then
        export PADM_REALITY_TARGET_RESULTS_FILE="${oldResultsFile}"
    else
        unset PADM_REALITY_TARGET_RESULTS_FILE
    fi
    if [[ -n "${oldScanFile}" ]]; then
        export PADM_REALITY_TARGET_SCAN_FILE="${oldScanFile}"
    else
        unset PADM_REALITY_TARGET_SCAN_FILE
    fi
    if [[ -n "${oldCandidatesFile}" ]]; then
        export PADM_REALITY_TARGET_CANDIDATES_FILE="${oldCandidatesFile}"
    else
        unset PADM_REALITY_TARGET_CANDIDATES_FILE
    fi
)

runRealityConfigApplyRegression() {
    local realityPatchDir="${TMP_DIR}/reality-target-patch"
    local realityPatchXrayVision="${realityPatchDir}/xray/07_VLESS_vision_reality_inbounds.json"
    local realityPatchXrayXhttp="${realityPatchDir}/xray/12_VLESS_XHTTP_inbounds.json"
    local realityPatchSingBoxVision="${realityPatchDir}/sing-box/07_VLESS_vision_reality_inbounds.json"
    local realityPatchSingBoxGrpc="${realityPatchDir}/sing-box/08_VLESS_vision_gRPC_inbounds.json"
    local realityPatchOriginal
    mkdir -p "${realityPatchDir}/xray" "${realityPatchDir}/sing-box"
    cat >"${realityPatchXrayVision}" <<'JSON'
{"inbounds":[{}, {"streamSettings":{"realitySettings":{"target":"old.example.com:443","serverNames":["old.example.com"]}}}]}
JSON
    cat >"${realityPatchXrayXhttp}" <<'JSON'
{"inbounds":[{"streamSettings":{"realitySettings":{"target":"old.example.com:443","serverNames":["old.example.com"]},"xhttpSettings":{"host":"old.example.com"}}}]}
JSON
    cat >"${realityPatchSingBoxVision}" <<'JSON'
{"inbounds":[{"tls":{"server_name":"old.example.com","reality":{"handshake":{"server":"old.example.com","server_port":443}}}}]}
JSON
    cat >"${realityPatchSingBoxGrpc}" <<'JSON'
{"inbounds":[{"tls":{"server_name":"old.example.com","reality":{"handshake":{"server":"old.example.com","server_port":443}}}}]}
JSON
    export PADM_REALITY_XRAY_VISION_CONFIG_FILE="${realityPatchXrayVision}"
    export PADM_REALITY_XRAY_XHTTP_CONFIG_FILE="${realityPatchXrayXhttp}"
    export PADM_REALITY_SINGBOX_VISION_CONFIG_FILE="${realityPatchSingBoxVision}"
    export PADM_REALITY_SINGBOX_GRPC_CONFIG_FILE="${realityPatchSingBoxGrpc}"
    applyRealityTargetToInstalledConfigs "new.example.com:8443" "sni.example.com"
    jq -e '.inbounds[1].streamSettings.realitySettings.target == "new.example.com:8443" and .inbounds[1].streamSettings.realitySettings.serverNames == ["sni.example.com"]' "${realityPatchXrayVision}" >/dev/null
    jq -e '.inbounds[0].streamSettings.realitySettings.target == "new.example.com:8443" and .inbounds[0].streamSettings.xhttpSettings.host == "sni.example.com"' "${realityPatchXrayXhttp}" >/dev/null
    jq -e '.inbounds[0].tls.server_name == "sni.example.com" and .inbounds[0].tls.reality.handshake.server == "new.example.com" and .inbounds[0].tls.reality.handshake.server_port == 8443' "${realityPatchSingBoxVision}" >/dev/null
    jq -e '.inbounds[0].tls.server_name == "sni.example.com" and .inbounds[0].tls.reality.handshake.server == "new.example.com" and .inbounds[0].tls.reality.handshake.server_port == 8443' "${realityPatchSingBoxGrpc}" >/dev/null
    realityPatchOriginal=$(<"${realityPatchSingBoxVision}")
    if applyRealityTargetToInstalledConfigs "new.example.com:not-a-port" "sni.example.com" 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${realityPatchSingBoxVision}")" == "${realityPatchOriginal}" ]]
    [[ ! -e "${realityPatchXrayVision}.tmp" ]]
    [[ ! -e "${realityPatchXrayXhttp}.tmp" ]]
    [[ ! -e "${realityPatchSingBoxVision}.tmp" ]]
    [[ ! -e "${realityPatchSingBoxGrpc}.tmp" ]]
    unset PADM_REALITY_XRAY_VISION_CONFIG_FILE PADM_REALITY_XRAY_XHTTP_CONFIG_FILE PADM_REALITY_SINGBOX_VISION_CONFIG_FILE PADM_REALITY_SINGBOX_GRPC_CONFIG_FILE
}

runRealityConfigChangeReloadFailureRegression() (
    local root="${TMP_DIR}/reality-config-change-reload-failure"
    local xrayVision="${root}/xray-vision.json"
    local xrayXhttp="${root}/xray-xhttp.json"
    local singBoxVision="${root}/singbox-vision.json"
    local singBoxGrpc="${root}/singbox-grpc.json"
    local statusLog="${root}/status.log"
    local refreshLog="${root}/refresh.log"
    local applyLog
    local reloadCalls=0 preservedBackupDir

    mkdir -p "${root}" "${root}/tmp"
    TMPDIR="${root}/tmp"
    cat >"${singBoxVision}" <<'JSON'
{"inbounds":[{"tls":{"server_name":"old-sni.example.com","reality":{"handshake":{"server":"old.example.com","server_port":443}}}}]}
JSON
    cat >"${singBoxGrpc}" <<'JSON'
{"inbounds":[{"tls":{"server_name":"old-sni.example.com","reality":{"handshake":{"server":"old.example.com","server_port":443}}}}]}
JSON
    PADM_REALITY_XRAY_VISION_CONFIG_FILE="${xrayVision}"
    PADM_REALITY_XRAY_XHTTP_CONFIG_FILE="${xrayXhttp}"
    PADM_REALITY_SINGBOX_VISION_CONFIG_FILE="${singBoxVision}"
    PADM_REALITY_SINGBOX_GRPC_CONFIG_FILE="${singBoxGrpc}"
    applyLog=$(realityTargetTmpPath padm-reality-target-apply.log)

    resetRealityConfigChangeFixture() {
        local xhttpContent=$1
        : >"${statusLog}"
        : >"${refreshLog}"
        reloadCalls=0
        realityTargetHost=old.example.com
        realityTargetPort=443
        realitySNI=old-sni.example.com
        xrayVLESSRealitySNI=old-sni.example.com
        xrayVLESSRealityXHTTPSNI=old-sni.example.com
        singBoxVLESSRealityVisionSNI=old-sni.example.com
        singBoxVLESSRealityGRPCSNI=old-sni.example.com
        printf '%s\n' '{"inbounds":[{}, {"streamSettings":{"realitySettings":{"target":"old.example.com:443","serverNames":["old-sni.example.com"]}}}]}' >"${xrayVision}"
        printf '%s\n' "${xhttpContent}" >"${xrayXhttp}"
    }

    reloadCore() {
        reloadCalls=$((reloadCalls + 1))
        [[ "${reloadCalls}" == "1" ]] && return 1
        return 0
    }
    refreshSubscriptionsAfterRealityTargetChange() {
        printf 'refresh\n' >>"${refreshLog}"
        return 0
    }
    realityTargetStatusBlock() {
        printf '%s\n' "$*" >>"${statusLog}"
    }

    resetRealityConfigChangeFixture '{"inbounds":[{"streamSettings":{"realitySettings":{"target":"old.example.com:443","serverNames":["old-sni.example.com"]},"xhttpSettings":{"host":"old-sni.example.com"}}}]}'
    regressionExpectStatus 1 changeInstalledRealityTarget "new.example.com:8443" "new-sni.example.com"
    [[ "${reloadCalls}" == "2" ]]
    [[ "$(jq -r '.inbounds[1].streamSettings.realitySettings.target' "${xrayVision}")" == "old.example.com:443" ]]
    [[ "$(jq -r '.inbounds[0].streamSettings.realitySettings.target' "${xrayXhttp}")" == "old.example.com:443" ]]
    [[ "$(jq -r '.inbounds[0].tls.reality.handshake.server' "${singBoxVision}")" == "old.example.com" ]]
    [[ "$(jq -r '.inbounds[0].tls.server_name' "${singBoxGrpc}")" == "old-sni.example.com" ]]
    [[ "${realityTargetHost}" == "old.example.com" ]]
    [[ "${realityTargetPort}" == "443" ]]
    [[ "${realitySNI}" == "old-sni.example.com" ]]
    [[ "${xrayVLESSRealitySNI}" == "old-sni.example.com" ]]
    [[ "${xrayVLESSRealityXHTTPSNI}" == "old-sni.example.com" ]]
    [[ "${singBoxVLESSRealityVisionSNI}" == "old-sni.example.com" ]]
    [[ "${singBoxVLESSRealityGRPCSNI}" == "old-sni.example.com" ]]
    [[ ! -s "${refreshLog}" ]]
    grep -q '核心重载失败，已回滚配置' "${statusLog}"

    resetRealityConfigChangeFixture '{bad-json'
    regressionExpectStatus 1 changeInstalledRealityTarget "new.example.com:8443" "new-sni.example.com"
    [[ "${reloadCalls}" == "0" ]]
    [[ "$(jq -r '.inbounds[1].streamSettings.realitySettings.target' "${xrayVision}")" == "old.example.com:443" ]]
    [[ "${realityTargetHost}" == "old.example.com" ]]
    [[ "${realityTargetPort}" == "443" ]]
    [[ ! -s "${refreshLog}" ]]
    grep -q '配置应用失败，已回滚' "${statusLog}"
    grep -q "失败文件: ${xrayXhttp}" "${statusLog}"
    grep -q "排查日志: ${applyLog}" "${statusLog}"
    grep -q 'Invalid numeric literal' "${applyLog}"

    resetRealityConfigChangeFixture '{bad-json'
    cp() {
        if [[ "$1" == "-p" && "$2" == */xray/07_VLESS_vision_reality_inbounds.json && "$3" == "${root}/.xray-vision.json.restore."* ]]; then
            return 1
        fi
        command cp "$@"
    }
    regressionExpectStatus 1 changeInstalledRealityTarget "new.example.com:8443" "new-sni.example.com"
    unset -f cp
    [[ "${reloadCalls}" == "0" ]]
    [[ "$(jq -r '.inbounds[1].streamSettings.realitySettings.target' "${xrayVision}")" == "new.example.com:8443" ]]
    [[ "${realityTargetHost}" == "old.example.com" ]]
    [[ "${realityTargetPort}" == "443" ]]
    [[ ! -s "${refreshLog}" ]]
    grep -q '配置应用失败，且回滚配置失败' "${statusLog}"
    grep -q "失败文件: ${xrayXhttp}" "${statusLog}"
    grep -q "排查日志: ${applyLog}" "${statusLog}"
    preservedBackupDir=$(sed -n 's/.*备份目录: \([^ ]*\).*/\1/p' "${statusLog}" | tail -n 1)
    [[ -n "${preservedBackupDir}" && -d "${preservedBackupDir}" ]]
    [[ -f "${preservedBackupDir}/xray/07_VLESS_vision_reality_inbounds.json" ]]

    resetRealityConfigChangeFixture '{"inbounds":[{"streamSettings":{"realitySettings":{"target":"old.example.com:443","serverNames":["old-sni.example.com"]},"xhttpSettings":{"host":"old-sni.example.com"}}}]}'
    cp() {
        if [[ "$1" == "-p" && "$2" == */xray/07_VLESS_vision_reality_inbounds.json && "$3" == "${root}/.xray-vision.json.restore."* ]]; then
            return 1
        fi
        command cp "$@"
    }
    regressionExpectStatus 1 changeInstalledRealityTarget "new.example.com:8443" "new-sni.example.com"
    unset -f cp
    [[ "${reloadCalls}" == "1" ]]
    [[ "$(jq -r '.inbounds[1].streamSettings.realitySettings.target' "${xrayVision}")" == "new.example.com:8443" ]]
    [[ "${realityTargetHost}" == "new.example.com" ]]
    [[ "${realityTargetPort}" == "8443" ]]
    [[ ! -s "${refreshLog}" ]]
    grep -q '核心重载失败，且回滚配置失败' "${statusLog}"
    ! grep -q '核心重载失败，已回滚配置' "${statusLog}"
)

runRealityConfigChangeSubscriptionRefreshFailureRegression() (
    local root="${TMP_DIR}/reality-config-change-subscription-refresh-failure"
    local xrayVision="${root}/xray-vision.json"
    local statusLog="${root}/status.log"
    local rc reloadCalls=0 refreshCalls=0

    mkdir -p "${root}"
    cat >"${xrayVision}" <<'JSON'
{"inbounds":[{}, {"streamSettings":{"realitySettings":{"target":"old.example.com:443","serverNames":["old-sni.example.com"]}}}]}
JSON
    realityTargetHost=old.example.com
    realityTargetPort=443
    realitySNI=old-sni.example.com
    xrayVLESSRealitySNI=old-sni.example.com
    xrayVLESSRealityXHTTPSNI=old-sni.example.com
    singBoxVLESSRealityVisionSNI=old-sni.example.com
    singBoxVLESSRealityGRPCSNI=old-sni.example.com
    PADM_REALITY_XRAY_VISION_CONFIG_FILE="${xrayVision}"
    PADM_REALITY_XRAY_XHTTP_CONFIG_FILE="${root}/missing-xhttp.json"
    PADM_REALITY_SINGBOX_VISION_CONFIG_FILE="${root}/missing-singbox-vision.json"
    PADM_REALITY_SINGBOX_GRPC_CONFIG_FILE="${root}/missing-singbox-grpc.json"
    : >"${statusLog}"

    reloadCore() {
        reloadCalls=$((reloadCalls + 1))
        return 0
    }
    refreshSubscriptionsAfterRealityTargetChange() {
        refreshCalls=$((refreshCalls + 1))
        return 1
    }
    realityTargetStatusBlock() {
        printf '%s\n' "$*" >>"${statusLog}"
    }

    regressionExpectStatus 1 changeInstalledRealityTarget "new.example.com:8443" "new-sni.example.com"
    [[ "${reloadCalls}" == "1" ]]
    [[ "${refreshCalls}" == "1" ]]
    [[ "$(jq -r '.inbounds[1].streamSettings.realitySettings.target' "${xrayVision}")" == "new.example.com:8443" ]]
    [[ "$(jq -r '.inbounds[1].streamSettings.realitySettings.serverNames[0]' "${xrayVision}")" == "new-sni.example.com" ]]
    [[ "${realityTargetHost}" == "new.example.com" ]]
    [[ "${realityTargetPort}" == "8443" ]]
    [[ "${realitySNI}" == "new-sni.example.com" ]]
    grep -q '订阅刷新失败' "${statusLog}"
    ! grep -q '^green REALITY 目标站 已更新为' "${statusLog}"
)

runXHTTPDownloadSettingsRegression() (
    local xhttpConfigFile="${TMP_DIR}/xhttp-download-settings.json"
    local oldConfigFile="${PADM_XHTTP_CONFIG_FILE:-}"
    local oldCoreInstallType="${coreInstallType:-}"
    local oldAutoInstall="${AUTO_INSTALL:-}"
    local oldAutoInstallType="${AUTO_INSTALL_TYPE:-}"
    refreshXHTTPSubscriptions() { return 0; }
    AUTO_INSTALL=
    AUTO_INSTALL_TYPE=
    cat >"${xhttpConfigFile}" <<'JSON'
{"inbounds":[{"streamSettings":{"realitySettings":{"serverNames":["reality.example.com"],"publicKey":"pubkey-down","shortIds":["","sid-down"]},"xhttpSettings":{"path":"/xhttp","host":"reality.example.com"}}}]}
JSON
    PADM_XHTTP_CONFIG_FILE="${xhttpConfigFile}"
    coreInstallType=1
    setXHTTPDownloadSettings <<<"down.example.com
443
reality
reality-down.example.com
front-down.example.com
/down
h3
packet-up
"
    jq -e '.inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.security == "reality" and (.inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.tlsSettings | not) and .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.realitySettings.serverName == "reality-down.example.com" and .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.realitySettings.publicKey == "pubkey-down" and .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.realitySettings.shortId == "sid-down" and .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.realitySettings.fingerprint == "chrome" and .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.xhttpSettings.host == "front-down.example.com" and .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.xhttpSettings.path == "/down" and .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.xhttpSettings.mode == "packet-up"' "${xhttpConfigFile}" >/dev/null
    setXHTTPDownloadSettings <<<"tls-down.example.com
8443
tls
tls-down.example.com
front-tls.example.com
/tls-down
h2
auto
"
    jq -e '.inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.security == "tls" and (.inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.realitySettings | not) and .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.tlsSettings.serverName == "tls-down.example.com" and .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.tlsSettings.alpn == ["h2"]' "${xhttpConfigFile}" >/dev/null
    setXHTTPDownloadSettings <<<"2001:db8::1
443
tls
tls-down.example.com
front-tls.example.com
/ipv6-down
h3
auto
"
    jq -e '.inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.address == "2001:db8::1" and .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.xhttpSettings.path == "/ipv6-down"' "${xhttpConfigFile}" >/dev/null
    if [[ -n "${oldConfigFile}" ]]; then
        PADM_XHTTP_CONFIG_FILE="${oldConfigFile}"
    else
        unset PADM_XHTTP_CONFIG_FILE
    fi
    coreInstallType="${oldCoreInstallType}"
    if [[ -n "${oldAutoInstall}" ]]; then
        AUTO_INSTALL="${oldAutoInstall}"
    else
        unset AUTO_INSTALL
    fi
    if [[ -n "${oldAutoInstallType}" ]]; then
        AUTO_INSTALL_TYPE="${oldAutoInstallType}"
    else
        unset AUTO_INSTALL_TYPE
    fi
)

runRealityConfigRefreshSubscriptionRegression() {
    local oldNginxConfigPath="${nginxConfigPath:-}"
    local oldSubscribePort="${subscribePort:-}"
    local refreshCalls=0 subscribeCalls=0
    local refreshDir="${TMP_DIR}/reality-refresh-subscribe/"
    mkdir -p "${refreshDir}"
    nginxConfigPath="${refreshDir}"
    subscribePort=
    refreshPublishedSubscriptions() { refreshCalls=$((refreshCalls + 1)); }
    subscribe() { subscribeCalls=$((subscribeCalls + 1)); return 1; }
    readNginxSubscribe() { :; }

    refreshSubscriptionsAfterRealityTargetChange >/dev/null
    [[ "${refreshCalls}" == "0" && "${subscribeCalls}" == "0" ]]

    : >"${nginxConfigPath}subscribe.conf"
    refreshSubscriptionsAfterRealityTargetChange >/dev/null
    [[ "${refreshCalls}" == "1" && "${subscribeCalls}" == "0" ]]

    rm -f "${nginxConfigPath}subscribe.conf"
    readNginxSubscribe() { subscribePort=39778; }
    refreshSubscriptionsAfterRealityTargetChange >/dev/null
    [[ "${refreshCalls}" == "2" && "${subscribeCalls}" == "0" ]]

    nginxConfigPath="${oldNginxConfigPath}"
    subscribePort="${oldSubscribePort}"
}

runRealityConfigImportSkipRegression() {
    cat >"${TMP_DIR}/realitlscanner-fail.csv" <<'CSV'
IP,ORIGIN,CERT_DOMAIN,CERT_ISSUER,GEO_CODE
192.0.2.14,192.0.2.0/24,fail.example.com,"Let's Encrypt",N/A
CSV
    cp "${TMP_DIR}/realitlscanner-fail.csv" "${TMP_DIR}/realitlscanner-fail-1.csv"
    cp "${TMP_DIR}/realitlscanner-fail.csv" "${TMP_DIR}/realitlscanner-fail-2.csv"
    writeRealityTargetResultLine "fail.example.com:443" "fail.example.com" "Fail Example" "scanner" "no" "192.0.2.14" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "stale target"
    rm -f "${REALITY_TLS_PING_ARGS_FILE}"
    importRealityScannerResults "${TMP_DIR}/realitlscanner-fail-1.csv" || true
    grep -qxF "tls ping -ip 192.0.2.14 fail.example.com:443" "${REALITY_TLS_PING_ARGS_FILE}"
    ! grep -qF $'fail.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
    firstFailCount=$(wc -l <"${REALITY_TLS_PING_ARGS_FILE}" | tr -d ' ')
    importRealityScannerResults "${TMP_DIR}/realitlscanner-fail-2.csv" || true
    secondFailCount=$(wc -l <"${REALITY_TLS_PING_ARGS_FILE}" | tr -d ' ')
    [[ "${firstFailCount}" == "1" ]]
    [[ "${secondFailCount}" == "2" ]]
}

runRealityConfigRegression() {
    runRegressionStep reality-config-vless-encryption runRealityConfigVlessEncryptionRegression
    runRegressionStep reality-config-scanner runRealityConfigScannerRegression
    runRegressionStep reality-config-blocked-transaction runRealityBlockedCandidateTransactionRegression
    runRegressionStep reality-config-unified-library-rollback runRealityUnifiedLibraryRollbackRegression
    runRegressionStep reality-config-apply runRealityConfigApplyRegression
    runRegressionStep reality-config-change-reload-failure runRealityConfigChangeReloadFailureRegression
    runRegressionStep reality-config-change-subscription-refresh-failure runRealityConfigChangeSubscriptionRefreshFailureRegression
    runRegressionStep reality-config-xhttp-download-settings runXHTTPDownloadSettingsRegression
    runRegressionStep reality-config-refresh-subscription runRealityConfigRefreshSubscriptionRegression
    runRegressionStep reality-config-import-skip runRealityConfigImportSkipRegression
}
