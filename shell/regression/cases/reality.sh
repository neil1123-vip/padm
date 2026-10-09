#!/usr/bin/env bash

runRealityMldsa65FailureRegression() (
    local root="${TMP_DIR}/reality-mldsa65-failure" mode writes=0 reloads=0
    local coreInstallType=1 currentInstallProtocolType=",2," lastInstallationConfig=
    local realityTargetHost=target.example.com realityTargetPort=443 realitySNI=sni.example.com
    local currentRealityMldsa65Seed=old-seed currentRealityMldsa65Verify=old-verify
    local realityMldsa65Seed= realityMldsa65Verify=
    local profileFile="${root}/12_VLESS_XHTTP_inbounds.json"
    mkdir -p "${root}"
    printf '%s\n' '{"inbounds":[{"streamSettings":{"realitySettings":{"mldsa65Seed":"old-seed","mldsa65Verify":"old-verify"}}}]}' >"${profileFile}"
    coreXrayBinaryPath() { printf '%s\n' regressionMldsa65Xray; }
    regressionMldsa65Xray() {
        if [[ "$1" == tls ]]; then
            [[ "${mode}" != ping-failure ]] || return 1
            [[ "${mode}" != disabled ]] || { printf 'Pinging with SNI\nTLS version: TLS 1.3\n'; return 0; }
            printf 'Pinging with SNI\nTLS Post-Quantum key exchange: X25519MLKEM768\nCertificate chain total length: 4096\n'
        else
            case "${mode}" in
            generate-failure) return 1 ;;
            seed-only) printf 'Seed: new-seed\n' ;;
            verify-only) printf 'Verify: new-verify\n' ;;
            *) printf 'Seed: new-seed\nVerify: new-verify\n' ;;
            esac
        fi
    }
    autoRead() {
        [[ "${mode}" != read-failure ]] || return 1
        printf -v "$3" '%s' n
    }
    errorCard() { :; }
    initRealityProfile() { :; }
    initRealityKey() { :; }
    xrayTemplateConfigDir() { printf '%s\n' "${root}"; }
    updateRoutingJsonConfig() { writes=$((writes + 1)); }
    validateRealityTargetConfigAfterChange() { :; }
    reloadCore() { reloads=$((reloads + 1)); }
    currentProtocolHas() { [[ "$1" == 2 ]]; }
    for mode in ping-failure read-failure generate-failure seed-only verify-only; do
        realityMldsa65Seed= realityMldsa65Verify=
        regressionExpectStatus 1 initRealityMldsa65 || return 1
        [[ -z "${realityMldsa65Seed}${realityMldsa65Verify}" ]] || return 1
        regressionExpectStatus 1 regenerateRealityProfileApply || return 1
        [[ "${writes}${reloads}" == 00 &&
            "${currentRealityMldsa65Seed}:${currentRealityMldsa65Verify}" == old-seed:old-verify ]] || return 1
        jq -e '.inbounds[0].streamSettings.realitySettings |
            .mldsa65Seed == "old-seed" and .mldsa65Verify == "old-verify"' "${profileFile}" >/dev/null || return 1
    done
    mode=complete realityMldsa65Seed= realityMldsa65Verify=
    initRealityMldsa65 || return 1
    [[ "${realityMldsa65Seed}:${realityMldsa65Verify}" == new-seed:new-verify ]] || return 1
    mode=disabled realityMldsa65Seed= realityMldsa65Verify=
    initRealityMldsa65 || return 1
    [[ -z "${realityMldsa65Seed}${realityMldsa65Verify}" ]]
)

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

    runRealityMldsa65FailureRegression || return 1
    mkdir -p "${xrayRoot}" "${singBoxRoot}"
    configPath="${xrayRoot}"
    singBoxConfigPath="${singBoxRoot}"
    currentUUID=existing-user
    currentClients='[]'
    domain=
    currentHost=
    lastInstallationConfig=true
    AUTO_ENTRY_HOST=node.example.com
    AUTO_REALITY_TARGET=www.gnu.org:443
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

    (
        local input inputFd nextInput legacySource explicitSource
        unset AUTO_INSTALL AUTO_ENTRY_HOST AUTO_DOMAIN
        AUTO_REALITY_DOMAIN=yes
        domain=
        currentHost=
        # EOF、截断和回车取消不能保留输入，也不能消费上级菜单动作。
        for input in "" strict.example.com; do
            realityEntryHost=previous.example.com
            regressionExpectStatus 1 collectEntryProfile < <(printf '%s' "${input}")
            [[ -z "${realityEntryHost}" ]]
        done
        exec {inputFd}< <(printf '\nnext-parent-action\n')
        regressionExpectStatus 1 collectEntryProfile <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ -z "${realityEntryHost}" && "${nextInput}" == next-parent-action ]]
        exec {inputFd}<&-
        exec {inputFd}< <(printf 'strict.example.com\nnext-parent-action\n')
        collectEntryProfile <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ "${realityEntryHost}" == strict.example.com && "${nextInput}" == next-parent-action ]]
        exec {inputFd}<&-

        # 普通模式的历史 IP 切换为严格域名时，只补填入口；错误输入在当前字段重试。
        for legacySource in current stored; do
            currentHost=192.0.2.10
            if [[ "${legacySource}" == stored ]]; then
                printf '192.0.2.20\n' >"${entryHostFile}"
            fi
            exec {inputFd}< <(printf 'bad entry\nstrict.example.com\nnext-parent-action\n')
            collectEntryProfile <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            [[ "${realityEntryHost}" == strict.example.com && "${nextInput}" == next-parent-action ]]
            exec {inputFd}<&-
        done
        rm -f "${entryHostFile}"
        exec {inputFd}< <(printf '\nnext-parent-action\n')
        regressionExpectStatus 1 collectEntryProfile <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ -z "${realityEntryHost}" && "${nextInput}" == next-parent-action ]]
        exec {inputFd}<&-

        # 显式入口错误和自动安装仍快速失败，不能读取后续交互输入。
        for explicitSource in AUTO_ENTRY_HOST AUTO_DOMAIN domain; do
            AUTO_ENTRY_HOST=
            AUTO_DOMAIN=
            domain=
            printf -v "${explicitSource}" '%s' 192.0.2.30
            exec {inputFd}< <(printf 'next-parent-action\n')
            regressionExpectStatus 1 collectEntryProfile <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            [[ "${nextInput}" == next-parent-action ]]
            exec {inputFd}<&-
        done
        domain=
        AUTO_INSTALL=true
        exec {inputFd}< <(printf 'next-parent-action\n')
        regressionExpectStatus 1 collectEntryProfile <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ "${nextInput}" == next-parent-action ]]
        exec {inputFd}<&-
        unset AUTO_INSTALL
        currentHost=stored-valid.example.com
        exec {inputFd}< <(printf 'next-parent-action\n')
        collectEntryProfile <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ "${realityEntryHost}" == stored-valid.example.com && "${nextInput}" == next-parent-action ]]
        exec {inputFd}<&-
    )

    (
        local inputFd nextInput autoReads=0
        unset AUTO_INSTALL AUTO_REALITY_DOMAIN
        exec {inputFd}< <(printf '9\n2\nnext-parent-action\n')
        configureRealityDomainMode ",1," <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ "${realityOnlyWithDomain}" == true && "${nextInput}" == next-parent-action ]]
        exec {inputFd}<&-
        regressionExpectStatus 1 configureRealityDomainMode ",1," < <(printf '9\n')
        [[ -z "${realityOnlyWithDomain}" ]]
        AUTO_INSTALL=true
        autoRead() { autoReads=$((autoReads + 1)); printf -v "$3" '%s' 9; }
        regressionExpectStatus 1 configureRealityDomainMode ",1," </dev/null
        [[ "${autoReads}" == 1 && -z "${realityOnlyWithDomain}" ]]
    )

    (
        local input inputFd nextInput targetValidations=0 defaultTargetCalls=0 candidateCalls=0 autoReads=0
        local autoTargetCalls=0 autoTargetStatus=0 validationPolicy= validationStatus=0
        local menuLog="${root}/target-menu.log"
        unset AUTO_INSTALL AUTO_REALITY_TARGET AUTO_REALITY_SERVER_NAME
        realityEntryHost=node.example.com
        validateRealityTargetSelection() {
            targetValidations=$((targetValidations + 1))
            validationPolicy=$1
            return "${validationStatus}"
        }
        printRealityTargetProfile() { :; }
        menuItem() { printf '%s %s\n' "$1" "$2"; }
        menuRecommendedItem() { menuItem "$@"; }
        selectDefaultRealityTarget() { defaultTargetCalls=$((defaultTargetCalls + 1)); return 1; }
        selectAutoRecommendedRealityTarget() {
            autoTargetCalls=$((autoTargetCalls + 1))
            (( autoTargetStatus == 0 )) || return "${autoTargetStatus}"
            parseRealityTargetInput random-a.example.com:443
        }
        selectRealityTargetCandidateInteractive() {
            [[ "$1" == detect-first ]] || return 1
            candidateCalls=$((candidateCalls + 1))
            parseRealityTargetInput candidate.example.com:443
        }
        # 复用目标保留自定义 SNI；显式 SNI 优先，新目标默认使用新域名。
        realityTargetHost=old.example.com
        realityTargetPort=8443
        realitySNI=old-sni.example.com
        collectRealityProfile </dev/null
        [[ "${realityTargetHost}" == old.example.com && "${realityTargetPort}" == 8443 && "${realitySNI}" == old-sni.example.com ]]
        AUTO_REALITY_SERVER_NAME=explicit.example.com
        collectRealityProfile </dev/null
        [[ "${realitySNI}" == explicit.example.com ]]
        unset AUTO_REALITY_SERVER_NAME
        AUTO_REALITY_TARGET=new.example.com:9443
        collectRealityProfile </dev/null
        [[ "${realityTargetHost}" == new.example.com && "${realityTargetPort}" == 9443 && "${realitySNI}" == new.example.com ]]
        unset AUTO_REALITY_TARGET
        # 默认和选项 1 都进入检测后选择，不调用自动推荐，也不消费上级菜单输入。
        for input in "" 1; do
            realityTargetHost=
            realityTargetPort=
            realitySNI=
            exec {inputFd}< <(printf '%s\nnext-parent-action\n' "${input}")
            collectRealityProfile <&"${inputFd}" >"${menuLog}"
            read -r -u "${inputFd}" nextInput
            [[ "${realityTargetHost}" == candidate.example.com && "${nextInput}" == next-parent-action ]]
            [[ "${defaultTargetCalls}" == 0 ]]
            [[ "$(<"${menuLog}")" == $'1 检测候选后选择\n2 手动输入' ]]
            exec {inputFd}<&-
        done
        [[ "${candidateCalls}" == 2 ]]
        targetValidations=0
        for input in "" manual.example.com:9443; do
            realityTargetHost=
            realityTargetPort=
            realitySNI=
            regressionExpectStatus 1 collectRealityProfile < <(printf '2\n%s' "${input}")
            [[ -z "${realityTargetHost}${realityTargetPort}${realitySNI}" && "${targetValidations}" == 0 && "${defaultTargetCalls}" == 0 ]]
        done
        realityTargetHost=
        realityTargetPort=
        realitySNI=
        exec {inputFd}< <(printf '2\n\nnext-parent-action\n')
        regressionExpectStatus 1 collectRealityProfile <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ -z "${realityTargetHost}${realityTargetPort}${realitySNI}" && "${nextInput}" == next-parent-action && "${defaultTargetCalls}" == 0 ]]
        exec {inputFd}<&-
        exec {inputFd}< <(printf '2\nmanual.example.com:9443\nnext-parent-action\n')
        collectRealityProfile <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ "${realityTargetHost}" == manual.example.com && "${realityTargetPort}" == 9443 && "${realitySNI}" == manual.example.com ]]
        [[ "${nextInput}" == next-parent-action && "${targetValidations}" == 1 && "${defaultTargetCalls}" == 0 ]]
        exec {inputFd}<&-
        realityTargetHost=
        realityTargetPort=
        realitySNI=
        exec {inputFd}< <(printf '3\n2\ncorrected.example.com\nnext-parent-action\n')
        collectRealityProfile <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ "${realityTargetHost}" == corrected.example.com && "${nextInput}" == next-parent-action && "${defaultTargetCalls}" == 0 ]]
        exec {inputFd}<&-
        realityTargetHost=
        realityTargetPort=
        realitySNI=
        regressionExpectStatus 1 collectRealityProfile < <(printf '9\n')
        [[ "${defaultTargetCalls}" == 0 ]]
        AUTO_INSTALL=true
        autoRead() { autoReads=$((autoReads + 1)); printf -v "$3" '%s' 9; }
        exec {inputFd}< <(printf 'next-parent-action\n')
        collectRealityProfile <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ "${realityTargetHost}" == random-a.example.com && "${validationPolicy}" == auto && "${autoTargetCalls}" == 1 ]]
        [[ "${nextInput}" == next-parent-action && "${autoReads}" == 0 && "${defaultTargetCalls}" == 0 && "${candidateCalls}" == 2 ]]
        exec {inputFd}<&-
        realityTargetHost=
        autoTargetStatus=1
        regressionExpectStatus 1 collectRealityProfile </dev/null
        [[ -z "${realityTargetHost}" && "${autoTargetCalls}" == 2 && "${autoReads}" == 0 ]]
        autoTargetStatus=0
        validationStatus=1
        regressionExpectStatus 1 collectRealityProfile </dev/null
        [[ "${validationPolicy}" == auto && "${autoTargetCalls}" == 3 && "${autoReads}" == 0 ]]
        validationStatus=0
        AUTO_REALITY_TARGET=explicit.example.com:9443
        collectRealityProfile </dev/null
        [[ "${realityTargetHost}" == explicit.example.com && "${realityTargetPort}" == 9443 && "${autoReads}" == 0 && "${validationPolicy}" == manual && "${autoTargetCalls}" == 3 ]]
        unset AUTO_REALITY_TARGET
        realitySNI=reused-sni.example.com
        collectRealityProfile </dev/null
        [[ "${realitySNI}" == reused-sni.example.com && "${autoReads}" == 0 && "${autoTargetCalls}" == 3 ]]
    )

    (
        local scanCalls=0 scanStatus=0 detectorStatus=0 goodCount=1 i testIndex scanRecords selectedHost
        export PADM_REALITY_TARGET_CANDIDATES_FILE="${root}/random-candidates.tsv"
        export PADM_REALITY_TARGET_RESULTS_FILE="${root}/random-results.tsv"
        export PADM_REALITY_TARGET_SCAN_FILE="${PADM_REALITY_TARGET_RESULTS_FILE}"
        local recordsFile="${root}/random-scan-records.tsv"
        local PADM_REALITY_AUTO_PROBE_LIMIT=1 PADM_REALITY_TARGET_SELECTION_REQUIRE_SCAN=1
        unset AUTO_REALITY_SERVER_NAME
        : >"${PADM_REALITY_TARGET_CANDIDATES_FILE}"
        for ((i = 1; i <= 13; i++)); do
            printf 'random-%s.example.com|sni-%s.example.com|Random %s|global|test|unknown|%s|yes|fixture\n' "${i}" "${i}" "${i}" "${i}" >>"${PADM_REALITY_TARGET_CANDIDATES_FILE}"
        done
        printf 'manual-only.example.com|manual-only.example.com|Manual|global|test|unknown|14|no|fixture\n' >>"${PADM_REALITY_TARGET_CANDIDATES_FILE}"
        realityTargetDetector() { (( detectorStatus == 0 )) || return 1; printf 'fake-xray\n'; }
        scanLocalAsnRealityTargets() {
            [[ "$1" == recommended_only && "${PADM_REALITY_TARGET_SELECTION_REQUIRE_SCAN}" == 0 ]] || return 1
            scanCalls=$((scanCalls + 1))
            (( scanStatus == 0 )) || return "${scanStatus}"
            realityTargetRefreshRecords "$1" >"${recordsFile}"
            [[ "$(wc -l <"${recordsFile}")" == 13 ]] || return 1
            # 旧库和非推荐项保持 A，但不能进入本次随机候选。
            formatRealityTargetResultLine old-library.example.com:443 old-library.example.com Old test no 192.0.2.1 AS64500 ExampleNet same_asn A yes 4096 yes 1 fixture >"${PADM_REALITY_TARGET_RESULTS_FILE}"
            formatRealityTargetResultLine manual-only.example.com:443 manual-only.example.com Manual test no 192.0.2.1 AS64500 ExampleNet same_asn A yes 4096 yes 1 fixture >>"${PADM_REALITY_TARGET_RESULTS_FILE}"
            for ((i = 1; i <= 13; i++)); do
                local score=B
                if (( goodCount > 0 && i == 13 || goodCount > 1 && i == 1 )); then score=A; fi
                formatRealityTargetResultLine "random-${i}.example.com:443" "sni-${i}.example.com" Random test no 192.0.2.1 AS64500 ExampleNet same_asn "${score}" yes 4096 yes 2 fixture >>"${PADM_REALITY_TARGET_RESULTS_FILE}"
            done
        }
        selectAutoRecommendedRealityTarget </dev/null
        [[ "${realityTargetHost}" == random-13.example.com && "${realityTargetPort}" == 443 && "${realitySNI}" == sni-13.example.com && "${scanCalls}" == 1 ]]
        AUTO_REALITY_SERVER_NAME=override.example.com
        selectAutoRecommendedRealityTarget </dev/null
        [[ "${realitySNI}" == override.example.com ]]
        unset AUTO_REALITY_SERVER_NAME
        goodCount=2
        for ((testIndex = 0; testIndex < 4; testIndex++)); do
            selectAutoRecommendedRealityTarget </dev/null
            selectedHost=${realityTargetHost}
            [[ "${selectedHost}" == random-1.example.com || "${selectedHost}" == random-13.example.com ]]
            [[ "${realitySNI}" == "sni-${selectedHost#random-}" ]]
        done
        realityTargetHost=unchanged.example.com
        goodCount=0
        regressionExpectStatus 1 selectAutoRecommendedRealityTarget </dev/null
        [[ "${realityTargetHost}" == unchanged.example.com ]]
        scanStatus=1
        regressionExpectStatus 1 selectAutoRecommendedRealityTarget </dev/null
        [[ "${realityTargetHost}" == unchanged.example.com ]]
        scanRecords=${scanCalls}
        detectorStatus=1
        regressionExpectStatus 1 selectAutoRecommendedRealityTarget </dev/null
        [[ "${scanCalls}" == "${scanRecords}" && "${realityTargetHost}" == unchanged.example.com ]]
    )

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
    if customXrayInstall 2 domain >/dev/null 2>&1; then return 1; fi
    if customXrayInstall 26 domain >/dev/null 2>&1; then return 1; fi
    if customXrayInstall 1,2 domain >/dev/null 2>&1; then return 1; fi
    if customSingBoxInstall 26 domain >/dev/null 2>&1; then return 1; fi
    if customXrayInstall 1 domain >/dev/null 2>&1; then return 1; fi
    if customSingBoxInstall 1 domain >/dev/null 2>&1; then return 1; fi
    # 合法协议先读取历史入口，但入口校验失败时仍不得下载或变更服务。
    [[ "$(grep -c '^read-last$' "${sideEffectLog}")" == "2" ]]
    ! grep -q '^install-tools$' "${sideEffectLog}"

    AUTO_INSTALL=
    AUTO_REALITY_DOMAIN=
    realityOnlyWithDomain=
    AUTO_ENTRY_HOST=node.example.com
    AUTO_REALITY_TARGET=www.gnu.org:443
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

    (
        local PADM_INSTALL_CLIENTS_PREPARED=true
        local selectCustomInstallType=",1," currentClients='[]'
        local realityMldsa65Seed= realityMldsa65Verify=
        xrayTemplateConfigDir() { printf '%s\n' "${xrayRoot}"; }
        initRealityProfile() {
            realityTargetHost=target.example.com
            realityTargetPort=443
            realitySNI=sni.example.com
        }
        initXrayRealityPort() { realityPort=10888; }
        initXrayXHTTPort() { xHTTPort=10889; }
        initXrayRealityGrpcPort() { realityGrpcPort=10891; }
        initRealityMldsa65() { return 1; }
        local protocolId
        for protocolId in 1 2 26; do
            selectCustomInstallType=",${protocolId},"
            regressionExpectStatus 1 initXrayConfigApply custom 1 true || return 1
            [[ ! -e "${xrayRoot}$(protocolCapabilityMeta "${protocolId}" config_file)" ]] || return 1
        done
        selectCustomInstallType=",1,"
        initRealityMldsa65() { return 0; }
        initXrayConfigApply custom 1 true
        # 嗅探前端的 SNI 放行与兜底阻断规则必须匹配真实入站 tag。
        jq -e --arg sni "${realitySNI}" '
            .inbounds[0].tag as $tag |
            $tag == "dokodemo-in" and
            .inbounds[0].protocol == "dokodemo-door" and
            .inbounds[0].sniffing.routeOnly == true and
            (.routing.rules | length) == 2 and
            all(.routing.rules[]; .inboundTag == [$tag]) and
            .routing.rules[0].domain == [$sni] and
            .routing.rules[0].outboundTag == "z_direct_outbound" and
            .routing.rules[1].outboundTag == "blackhole_out"
        ' "${xrayRoot}07_VLESS_vision_reality_inbounds.json" >/dev/null
    )
)

runPublicIPIPv4FallbackRegression() (
    set -euo pipefail
    unset currentHost singBoxVLESSRealityVisionSNI singBoxVLESSRealityGRPCSNI xrayVLESSRealitySNI

    local address
    for address in 0.0.0.0 192.0.2.10 255.255.255.255; do
        padmIsValidHostName "${address}"
    done
    for address in 256.1.2.3 18446744073709551617.2.3.4; do
        regressionExpectStatus 1 padmIsValidHostName "${address}"
    done
    for address in :: ::1 ::1:2:3:4:5:6:7 1:2:3:4:5:6:7:: 2001:db8::10 1:2:3:4:5:6:7:8; do
        padmIsValidIPv6Address "${address}"
    done
    for address in 1:2:3:4:5:6:7 1::2::3 :::1 ::1:2:3:4:5:6:7:8 1:2:3:4:5:6:7:8::; do
        regressionExpectStatus 1 padmIsValidIPv6Address "${address}"
    done
    [[ "$(padmNormalizeIPv6Address ::)" == 0000:0000:0000:0000:0000:0000:0000:0000 ]]
    [[ "$(padmNormalizeIPv6Address 1:2:3:4:5:6:7::)" == 0001:0002:0003:0004:0005:0006:0007:0000 ]]

    fetchPublicIP() {
        case "$1" in
        4) return 1 ;;
        6) printf '2001:db8::10\n' ;;
        *) return 1 ;;
        esac
    }
    fetchUrlToStdout() {
        [[ "$1" == 'https://api.ipify.org' ]] || return 1
        printf '203.0.113.10\n'
    }

    [[ "$(getPublicIP)" == '203.0.113.10' ]]
    [[ -z "$(getPublicIP 4)" ]]
    [[ "$(getPublicIP 6)" == '2001:db8::10' ]]
    (
        # AAAA 别名行不参与地址比较；没有真实地址时仍拒绝安装。
        source "${PROJECT_ROOT}/shell/core/network.sh"
        local mode ipType= calls= dnsErrors=
        command() {
            [[ "$1" != -v || "$2" != dig ]] || return 0
            builtin command "$@"
        }
        sleep() { :; }
        statusCard() { :; }
        successCard() { :; }
        errorCard() { dnsErrors+="$*"$'\n'; }
        getPublicIP() { printf '%s\n' 2001:db8::10; }
        dig() {
            if [[ " $* " != *" aaaa "* ]]; then
                [[ "${mode}" != multi-v4 ]] || printf '203.0.113.20\n203.0.113.10\n'
                return 0
            fi
            printf 'canonical.example.com.\n'
            case "${mode}" in
            alias-only) ;;
            expanded) printf '2001:0DB8:0000:0000:0000:0000:0000:0010\n' ;;
            multi-v6) printf '2001:db8::20\n2001:0DB8:0:0:0:0:0:10\n' ;;
            *) printf '2001:db8::10\n' ;;
            esac
        }
        mode=alias
        checkDNSIP alias.example.com || return 1
        [[ "${ipType}" == 6 && -z "${dnsErrors}" ]] || return 1
        mode=alias-only
        regressionExpectStatus 1 checkDNSIP alias.example.com || return 1
        [[ "${dnsErrors}" == *无法通过DNS获取域名IPv6地址* ]] || return 1
        mode=alias
        getPublicIP() { printf '%s\n' 2001:db8::20; }
        regressionExpectStatus 1 checkDNSIP alias.example.com || return 1
        getPublicIP() { printf '%s\n' 2001:db8::10; }
        mode=expanded
        checkDNSIP alias.example.com || return 1
        mode=multi-v6
        checkDNSIP alias.example.com || return 1
        mode=multi-v4
        getPublicIP() { printf '%s\n' 203.0.113.10; }
        checkDNSIP alias.example.com || return 1
        [[ "${ipType}" == 4 ]] || return 1
        getPublicIP() { printf '%s\n' 203.0.113.30; }
        regressionExpectStatus 1 checkDNSIP alias.example.com || return 1
        (
            command() {
                [[ "$1" != -v || "$2" != dig ]] || return 1
                builtin command "$@"
            }
            getent() { printf '203.0.113.20 STREAM\n203.0.113.10 STREAM\n'; }
            getPublicIP() { printf '%s\n' 203.0.113.10; }
            checkDNSIP alias.example.com || return 1
        ) || return 1
    ) || return 1
)

runRealityTargetLocationRegression() (
    local resultsFile="${TMP_DIR}/reality-location-results.tsv"
    local linesFile="${TMP_DIR}/reality-location-lines.tsv"
    local lookupLog="${TMP_DIR}/reality-location-lookups.log"
    local line location
    local note="TLS 1.3 + X25519MLKEM768 可用"

    formatRealityTargetResultLine "legacy-location.example.com:443" "legacy-location.example.com" "Legacy" "test" "no" "192.0.2.201" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "${note}" >"${resultsFile}"
    line=$(<"${resultsFile}")
    [[ "$(awk -F'\t' '{print NF}' <<<"${line}")" == "16" ]]
    [[ "$(realityTargetResultField "${line}" 15)" == "${note}" ]]
    [[ "$(realityTargetResultField "${line}" 16)" == "Unknown" ]]
    formatRealityTargetResultLine "untouched-location.example.com:443" "untouched-location.example.com" "Untouched" "test" "no" "192.0.2.203" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "${note}" >>"${resultsFile}"
    : >"${linesFile}"
    {
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "legacy-location.example.com:443" "legacy-location.example.com" "Legacy" "test" "no" "192.0.2.201" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567891" "${note}"
        formatRealityTargetResultLine "same-ip-location.example.com:443" "same-ip-location.example.com" "Same IP" "test" "no" "192.0.2.201" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567892" "${note}"
        formatRealityTargetResultLine "same-asn-location.example.com:443" "same-asn-location.example.com" "Same ASN" "test" "no" "192.0.2.202" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567893" "${note}"
        formatRealityTargetResultLine "known-location.example.com:443" "known-location.example.com" "Known" "test" "no" "198.51.100.210" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567894" "${note}" "Known, United Kingdom"
        formatRealityTargetResultLine "non-a-location.example.com:443" "non-a-location.example.com" "Non-A" "test" "no" "198.51.100.211" "AS64500" "ExampleNet" "same_asn" "B" "yes" "4096" "yes" "1234567895" "${note}"
    } >"${linesFile}"
    export PADM_REALITY_TARGET_RESULTS_FILE="${resultsFile}"
    export PADM_REALITY_TARGET_SCAN_FILE="${resultsFile}"
    export REALITY_LOCATION_LOOKUP_ARGS_FILE="${lookupLog}"
    : >"${lookupLog}"
    writeRealityTargetResultLines "${linesFile}"
    line=$(realityTargetResultLine "legacy-location.example.com:443")
    [[ "$(realityTargetResultField "${line}" 15)" == "${note}" ]]
    [[ "$(realityTargetResultField "${line}" 16)" == "Los Angeles, United States" ]]
    line=$(realityTargetResultLine "same-ip-location.example.com:443")
    [[ "$(realityTargetResultField "${line}" 16)" == "Los Angeles, United States" ]]
    line=$(realityTargetResultLine "same-asn-location.example.com:443")
    [[ "$(realityTargetResultField "${line}" 16)" == "New York, United States" ]]
    [[ "$(wc -l <"${lookupLog}" | tr -d ' ')" == "2" ]]
    grep -qxF '192.0.2.201' "${lookupLog}"
    grep -qxF '192.0.2.202' "${lookupLog}"
    ! grep -qF '192.0.2.203' "${lookupLog}"
    ! grep -qF '198.51.100.211' "${lookupLog}"
    [[ "$(realityTargetResultCount)" == "5" ]]
    line=$(realityTargetResultLine "untouched-location.example.com:443")
    [[ "$(realityTargetResultField "${line}" 16)" == "Unknown" ]]
    [[ "$(awk -F'\t' '{print NF}' <<<"${line}")" == "16" ]]

    # 既存位置只对同一个 IP 有效，目标 IP 改变后重新查询。
    : >"${lookupLog}"
    formatRealityTargetResultLine "changed-ip-location.example.com:443" "changed-ip-location.example.com" "Changed" "test" "no" "192.0.2.201" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567896" "${note}" >"${linesFile}"
    writeRealityTargetResultLines "${linesFile}"
    [[ ! -s "${lookupLog}" ]]
    : >"${linesFile}"
    formatRealityTargetResultLine "changed-ip-location.example.com:443" "changed-ip-location.example.com" "Changed" "test" "no" "198.51.100.212" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567897" "${note}" >"${linesFile}"
    writeRealityTargetResultLines "${linesFile}"
    line=$(realityTargetResultLine "changed-ip-location.example.com:443")
    [[ "$(realityTargetResultField "${line}" 16)" == "London, United Kingdom" ]]
    grep -qxF '198.51.100.212' "${lookupLog}"
    [[ "$(wc -l <"${lookupLog}" | tr -d ' ')" == "1" ]]
    writeRealityTargetResultLine "changed-ip-location.example.com:443" "changed-ip-location.example.com" "Changed" "test" "no" "192.0.2.202" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567898" "${note}"
    line=$(realityTargetResultLine "changed-ip-location.example.com:443")
    [[ "$(realityTargetResultField "${line}" 16)" == "New York, United States" ]]
    [[ "$(wc -l <"${lookupLog}" | tr -d ' ')" == "1" ]]

    # 同批失败 IP 只查询一次，显式 Unknown 不在写入时重试。
    : >"${lookupLog}"
    {
        formatRealityTargetResultLine "changed-ip-location.example.com:443" "changed-ip-location.example.com" "Changed" "test" "no" "203.0.113.250" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567898" "${note}"
        formatRealityTargetResultLine "failed-location.example.com:443" "failed-location.example.com" "Failed" "test" "no" "203.0.113.250" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567898" "${note}"
    } >"${linesFile}"
    writeRealityTargetResultLines "${linesFile}"
    [[ "$(wc -l <"${lookupLog}" | tr -d ' ')" == "1" ]]
    line=$(realityTargetResultLine "failed-location.example.com:443")
    [[ "$(realityTargetResultField "${line}" 16)" == "Unknown" ]]
    : >"${lookupLog}"
    formatRealityTargetResultLine "failed-location.example.com:443" "failed-location.example.com" "Failed" "test" "no" "203.0.113.250" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567898" "${note}" "Unknown" >"${linesFile}"
    writeRealityTargetResultLines "${linesFile}"
    [[ ! -s "${lookupLog}" ]]

    (
        local fetchLog="${TMP_DIR}/reality-location-fetch.log"
        local longCity longLocation
        fetchUrlToStdout() {
            printf '%s\n' "$1" >>"${fetchLog}"
            case "$1" in
            *192.0.2.221?*) printf '%s\n' '{"success":true,"city":"Los Angeles","region":"California","country":"United States"}' ;;
            *198.51.100.221?*) printf '%s\n' '{"success":true,"city":"London","region":"England","country":"United Kingdom"}' ;;
            *2001:db8::221?*) printf '%s\n' '{"success":true,"city":null,"region":"Tokyo","country":"Japan"}' ;;
            *192.0.2.222?*) printf '%s\n' '{"success":true,"city":null,"region":null,"country":"United States"}' ;;
            *192.0.2.223?*) printf '%s\n' '{"success":' ;;
            *192.0.2.224?*) printf '%s\n' '{"success":false,"message":"Reserved range"}' ;;
            *192.0.2.225?*) printf '%s\n' '{"success":true,"city":"Bad\tCity","region":"Bad\rRegion","country":"United\nStates"}' ;;
            *192.0.2.226?*)
                printf -v longCity '%150s' ''
                printf '{"success":true,"city":"%s","country":"United States"}\n' "${longCity// /x}"
                ;;
            *192.0.2.227?*) return 1 ;;
            *192.0.2.228?*) printf '%s\n' '{"success":true}' ;;
            *) return 1 ;;
            esac
        }
        : >"${fetchLog}"
        [[ "$(padmRealLookupRealityTargetLocation "192.0.2.221")" == "Los Angeles, United States" ]]
        [[ "$(padmRealLookupRealityTargetLocation "198.51.100.221")" == "London, United Kingdom" ]]
        [[ "$(padmRealLookupRealityTargetLocation "2001:db8::221")" == "Tokyo, Japan" ]]
        [[ "$(padmRealLookupRealityTargetLocation "192.0.2.222")" == "United States" ]]
        ! padmRealLookupRealityTargetLocation "192.0.2.223" >/dev/null
        ! padmRealLookupRealityTargetLocation "192.0.2.224" >/dev/null
        location=$(padmRealLookupRealityTargetLocation "192.0.2.225")
        [[ "${location}" != *$'\t'* && "${location}" != *$'\n'* && "${location}" != *$'\r'* ]]
        [[ "${location}" == "Bad City, United States" ]]
        longLocation=$(padmRealLookupRealityTargetLocation "192.0.2.226")
        [[ "${#longLocation}" -le 115 ]]
        ! padmRealLookupRealityTargetLocation "192.0.2.227" >/dev/null
        ! padmRealLookupRealityTargetLocation "192.0.2.228" >/dev/null
        ! padmRealLookupRealityTargetLocation "not-an-ip" >/dev/null
        ! padmRealLookupRealityTargetLocation "999.2.3.4" >/dev/null
        ! padmRealLookupRealityTargetLocation ":::" >/dev/null
        grep -qxF 'https://ipwho.is/2001:db8::221?lang=en&fields=success,city,region,country' "${fetchLog}"
        [[ "$(wc -l <"${fetchLog}" | tr -d ' ')" == "10" ]]
    )

    (
        local detailLog="${TMP_DIR}/reality-location-detail.log"
        local statusLog="${TMP_DIR}/reality-location-status.log"
        local unknownLog="${TMP_DIR}/reality-location-unknown.log"
        : >"${detailLog}"
        : >"${statusLog}"
        REALITY_LOCATION_LOOKUP_ARGS_FILE="${detailLog}"
        realityTargetDetector() { printf 'fake-xray\n'; }
        currentRealityNetworkProfile() { printf '203.0.113.10\tAS64500\tExampleNet\n'; }
        probeRealityTargetEndpoint() {
            printf 'no\t198.51.100.221\tAS64501\tRemoteNet\tA\tyes\t4096\tyes\tprimary probe fixture\n'
        }
        realityTargetStatusBlock() { printf '%s\n' "$*" >>"${statusLog}"; }
        showRealityTargetQuality "location-detail.example.com:443" >/dev/null
        grep -qxF '198.51.100.221' "${detailLog}"
        [[ "$(wc -l <"${detailLog}" | tr -d ' ')" == "1" ]]
        grep -qF '地理位置: London, United Kingdom' "${statusLog}"
        line=$(realityTargetResultLine "location-detail.example.com:443")
        [[ "$(realityTargetResultField "${line}" 6)" == "198.51.100.221" ]]
        [[ "$(realityTargetResultField "${line}" 16)" == "London, United Kingdom" ]]
        : >"${detailLog}"
        realityTargetHost=location-detail.example.com
        realityTargetPort=443
        realitySNI=installed-detail.example.com
        probeRealityTargetEndpoint() {
            [[ "$3" == installed-detail.example.com ]] || return 1
            printf 'no\t198.51.100.221\tAS64501\tRemoteNet\tA\tyes\t4096\tyes\tprimary probe fixture\n'
        }
        showRealityTargetQuality "location-detail.example.com:443" >/dev/null
        [[ ! -s "${detailLog}" ]]
        line=$(realityTargetResultLine "location-detail.example.com:443")
        [[ "$(realityTargetResultField "${line}" 2)" == installed-detail.example.com ]]
        realityTargetHost=
        probeRealityTargetEndpoint() {
            printf 'no\t198.51.100.221\tAS64501\tRemoteNet\tA\tyes\t4096\tyes\tprimary probe fixture\n'
        }
        showRealityTargetQuality "same-ip-detail.example.com:443" >/dev/null
        [[ ! -s "${detailLog}" ]]
        line=$(realityTargetResultLine "same-ip-detail.example.com:443")
        [[ "$(realityTargetResultField "${line}" 16)" == "London, United Kingdom" ]]

        REALITY_LOCATION_LOOKUP_ARGS_FILE="${unknownLog}"
        : >"${unknownLog}"
        lookupRealityTargetLocation() { printf '%s\n' "$1" >>"${unknownLog}"; return 1; }
        probeRealityTargetEndpoint() {
            printf 'no\t198.51.100.222\tAS64501\tRemoteNet\tA\tyes\t4096\tyes\tvalidation fixture\n'
        }
        validateRealityTargetSelection manual "location-unknown.example.com:443" "location-unknown.example.com"
        line=$(realityTargetResultLine "location-unknown.example.com:443")
        [[ "$(realityTargetResultField "${line}" 16)" == "Unknown" ]]
        grep -qxF '198.51.100.222' "${unknownLog}"
        [[ "$(wc -l <"${unknownLog}" | tr -d ' ')" == "1" ]]
        : >"${unknownLog}"
        showRealityTargetQuality "location-detail-unknown.example.com:443" >/dev/null
        [[ "$(wc -l <"${unknownLog}" | tr -d ' ')" == "1" ]]
        grep -qF '地理位置: Unknown' "${statusLog}"
    )

    (
        local pageLog="${TMP_DIR}/reality-location-page.log"
        local pageOutput
        menuLine() { printf '%s\n' "$*"; }
        : >"${pageLog}"
        formatRealityTargetResultLine "location-page.example.com:443" "location-page.example.com" "Page" "test" "no" "198.51.100.230" "AS64501" "RemoteNet" "different_network" "A" "yes" "4096" "yes" "1234567898" "${note}" "London, United Kingdom" >"${resultsFile}"
        REALITY_LOCATION_LOOKUP_ARGS_FILE="${pageLog}"
        pageOutput=$(showRealityTargetScanResults all once)
        [[ "${pageOutput}" == *"location=London, United Kingdom"* ]]
        [[ ! -s "${pageLog}" ]]
        [[ "$(realityTargetResultField "$(<"${resultsFile}")" 16)" == "London, United Kingdom" ]]
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "legacy-page.example.com:443" "legacy-page.example.com" "Legacy" "test" "no" "192.0.2.231" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567898" "${note}" >"${resultsFile}"
        pageOutput=$(showRealityTargetScanResults all once)
        [[ "${pageOutput}" == *"location=Unknown"* ]]
        [[ ! -s "${pageLog}" ]]
        [[ "$(awk -F'\t' '{print NF}' "${resultsFile}")" == "15" ]]
        formatRealityTargetResultLine "empty-note.example.com:443" "empty-note.example.com" "" "test" "no" "192.0.2.201" "AS64500" "" "same_asn" "A" "yes" "4096" "yes" "1234567898" "" >"${linesFile}"
        writeRealityTargetResultLines "${linesFile}"
        line=$(realityTargetResultLine "empty-note.example.com:443")
        [[ "$(realityTargetResultField "${line}" 3)" == "" ]]
        [[ "$(realityTargetResultField "${line}" 8)" == "" ]]
        [[ "$(realityTargetResultField "${line}" 15)" == "" ]]
        [[ "$(realityTargetResultField "${line}" 16)" == "Los Angeles, United States" ]]
        pageOutput=$(showRealityTargetScanResults all once)
        [[ "${pageOutput}" == *"location=Los Angeles, United States"* ]]
        [[ "$(realityTargetResultField "${line}" 0)" == "" ]]
        [[ "$(realityTargetResultField "${line}" 17)" == "" ]]
    )
    (
        local parallelResultsFile="${TMP_DIR}/reality-location-parallel-results.tsv"
        local parallelLinesFile="${TMP_DIR}/reality-location-parallel-lines.tsv"
        local parallelLog="${TMP_DIR}/reality-location-parallel.log"
        PADM_REALITY_TARGET_RESULTS_FILE="${parallelResultsFile}"
        PADM_REALITY_SECONDARY_JOBS=2
        lookupRealityTargetLocation() {
            local retries=0
            printf 'start\t%s\n' "$1" >>"${parallelLog}"
            if [[ "$1" == "192.0.2.241" ]]; then
                # 首个请求必须等第三个完成，整批等待会在这里超时。
                while ! grep -qxF $'end\t192.0.2.243' "${parallelLog}" && (( retries < 200 )); do
                    sleep 0.01
                    retries=$((retries + 1))
                done
                (( retries < 200 )) || return 1
            elif [[ "$1" != "192.0.2.243" ]]; then
                while [[ "$(grep -c '^start' "${parallelLog}")" -lt 2 && "${retries}" -lt 200 ]]; do
                    sleep 0.01
                    retries=$((retries + 1))
                done
                (( retries < 200 )) || return 1
            fi
            sleep 0.05
            printf 'end\t%s\n' "$1" >>"${parallelLog}"
            printf 'Los Angeles, United States\n'
        }
        {
            formatRealityTargetResultLine "parallel-one.example.com:443" "parallel-one.example.com" "One" "test" "no" "192.0.2.241" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567898" "${note}"
            formatRealityTargetResultLine "parallel-two.example.com:443" "parallel-two.example.com" "Two" "test" "no" "192.0.2.242" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567898" "${note}"
            formatRealityTargetResultLine "parallel-three.example.com:443" "parallel-three.example.com" "Three" "test" "no" "192.0.2.243" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567898" "${note}"
            formatRealityTargetResultLine "parallel-duplicate.example.com:443" "parallel-duplicate.example.com" "Duplicate" "test" "no" "192.0.2.241" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567898" "${note}"
        } >"${parallelLinesFile}"
        : >"${parallelLog}"
        writeRealityTargetResultLines "${parallelLinesFile}"
        awk -F'\t' '$1 == "start" {running++; started++; if (running > peak) peak = running} $1 == "end" {running--} END {exit !(peak == 2 && started == 3 && running == 0)}' "${parallelLog}"
        [[ "$(awk -F'\t' '$16 == "Los Angeles, United States" {count++} END {print count + 0}' "${parallelResultsFile}")" == "4" ]]
        local cancelRoot="${TMP_DIR}/reality-location-cancel" writerPid workerPid oldResults retries=0 rc=0
        mkdir -p "${cancelRoot}/tmp"
        oldResults=$(<"${parallelResultsFile}")
        (
            PADM_CLEANUP_PATHS=()
            PADM_CLEANUP_TRAP_INSTALLED=
            TMPDIR="${cancelRoot}/tmp"
            PADM_REALITY_TARGET_RESULTS_FILE="${cancelRoot}/results.tsv"
            lookupRealityTargetLocation() {
                printf '%s\n' "${BASHPID}" >>"${cancelRoot}/workers"
                mktemp "${TMPDIR}/padm-fetch-url.XXXXXX" >/dev/null
                sleep 30
                printf 'Unknown\n'
            }
            writeRealityTargetResultLines "${parallelLinesFile}"
        ) >"${cancelRoot}/output" 2>&1 &
        writerPid=$!
        while [[ ! -s "${cancelRoot}/workers" && "${retries}" -lt 200 ]]; do
            sleep 0.01
            retries=$((retries + 1))
        done
        [[ -s "${cancelRoot}/workers" ]]
        kill -TERM "${writerPid}"
        wait "${writerPid}" || rc=$?
        [[ "${rc}" == "143" ]]
        while IFS= read -r workerPid; do
            ! kill -0 "${workerPid}" 2>/dev/null
        done <"${cancelRoot}/workers"
        [[ ! -e "${cancelRoot}/results.tsv" ]]
        [[ -z "$(find "${cancelRoot}/tmp" -mindepth 1 -print -quit)" ]]
        [[ "$(<"${parallelResultsFile}")" == "${oldResults}" ]]
        rc=0
        (
            PADM_CLEANUP_PATHS=()
            PADM_CLEANUP_TRAP_INSTALLED=
            TMPDIR="${cancelRoot}/tmp"
            PADM_REALITY_TARGET_RESULTS_FILE="${cancelRoot}/exit-results.tsv"
            realityTargetProgressLine() { exit 7; }
            writeRealityTargetResultLines "${parallelLinesFile}"
        ) || rc=$?
        [[ "${rc}" == "7" && ! -e "${cancelRoot}/exit-results.tsv" ]]
        [[ -z "$(find "${cancelRoot}/tmp" -mindepth 1 -print -quit)" ]]
        rc=0
        (
            PADM_CLEANUP_PATHS=()
            PADM_CLEANUP_TRAP_INSTALLED=
            TMPDIR="${cancelRoot}/tmp"
            PADM_REALITY_TARGET_RESULTS_FILE="${cancelRoot}/early-cancel-results.tsv"
            set -T
            trap 'if [[ "${BASH_COMMAND}" == '\''jobPids[jobIndex]=$!'\'' ]]; then trap - DEBUG; kill -TERM "${BASHPID}"; fi' DEBUG
            writeRealityTargetResultLines "${parallelLinesFile}"
        ) >"${cancelRoot}/early-output" 2>&1 || rc=$?
        [[ "${rc}" == "143" && ! -e "${cancelRoot}/early-cancel-results.tsv" ]]
        [[ -z "$(find "${cancelRoot}/tmp" -mindepth 1 -print -quit)" ]]
        local monitorMode monitorTraps
        lookupRealityTargetLocation() { return 1; }
        for monitorMode in off on; do
            PADM_REALITY_TARGET_RESULTS_FILE="${cancelRoot}/failed-${monitorMode}.tsv"
            [[ "${monitorMode}" != on ]] || set -m
            monitorTraps=$(trap -p EXIT INT TERM)
            writeRealityTargetResultLines "${parallelLinesFile}" >"${cancelRoot}/failed-${monitorMode}.output" 2>&1
            [[ "$(trap -p EXIT INT TERM)" == "${monitorTraps}" ]]
            if [[ "${monitorMode}" == on ]]; then
                [[ $- == *m* ]]
                set +m
            else
                [[ $- != *m* ]]
            fi
            ! grep -Eq '^\[[0-9]+\].*(Done|Terminated)' "${cancelRoot}/failed-${monitorMode}.output"
            [[ "$(awk -F'\t' '$16 == "Unknown" {count++} END {print count + 0}' "${PADM_REALITY_TARGET_RESULTS_FILE}")" == 4 ]]
        done
    )
)

runRealityCandidateFastRegression() {
    runRealityTargetLocationRegression
    local fixtureFile="${TMP_DIR}/reality-candidates-fast.txt"
    local cacheFile="${TMP_DIR}/reality-target-cache-fast.tsv"
    local emptyResultsFile="${TMP_DIR}/reality-target-empty-fast.tsv"
    local oldCandidatesFile="${PADM_REALITY_TARGET_CANDIDATES_FILE:-}"
    local oldResultsFile="${PADM_REALITY_TARGET_RESULTS_FILE:-}"
    local oldRealityPageSize="${REALITY_TARGET_PAGE_SIZE:-}"
    local oldAutoInstall="${AUTO_INSTALL:-}"
    local ipv6OpenSslArgsFile="${TMP_DIR}/reality-ipv6-openssl-args.txt"
    local staleResultsFile="${TMP_DIR}/reality-target-stale.tsv"
    local firstRecommendedRealityCandidate secondaryCandidate resolvedAddresses refreshRecordsWithNewCandidate

    (
        local observedNetworkMatch record recordOutput
        ! realityTargetProviderMatches Unknown unknown
        [[ "$(realityTargetNetworkMatch AS64500 ExampleNet AS64500 RemoteNet)" == same_asn ]]
        [[ "$(realityTargetNetworkMatch AS64500 EXAMPLENET AS64501 'ExampleNet Hosting')" == same_provider ]]
        [[ "$(realityTargetNetworkMatch AS64500 unknown AS64501 unknown)" == different_network ]]
        [[ "$(realityTargetNetworkMatch unknown unknown unknown unknown)" == unknown ]]
        [[ "$(realityTargetNetworkMatch "" "" AS64501 RemoteNet)" == unknown ]]
        [[ "$(realityTargetNetworkMatch AS64500 ExampleNet unknown unknown scanner_local)" == scanner_local ]]
        realityTargetDetector() { printf 'fake-xray\n'; }
        currentRealityNetworkProfile() { printf '203.0.113.10\tunknown\tunknown\n'; }
        lookupRealityTargetAsnCached() { printf 'unknown\tunknown\n'; }
        lookupRealityTargetLocation() { printf 'Unknown\n'; }
        realityTargetResultLine() { return 1; }
        realityTargetStatusBlock() { :; }
        probeRealityTargetEndpoint() { printf 'no\t192.0.2.1\tunknown\tunknown\tA\tyes\t4096\tyes\tfixture\n'; }
        writeRealityTargetResultLine() { observedNetworkMatch=$9; }
        showRealityTargetQuality "network-fixture.example.com:443"
        [[ "${observedNetworkMatch}" == unknown ]]
        validateRealityTargetSelection manual "network-fixture.example.com:443" "network-fixture.example.com"
        [[ "${observedNetworkMatch}" == unknown ]]
        record=$(formatRealityTargetResultLine "network-fixture.example.com:443" "network-fixture.example.com" Fixture test no unknown unknown unknown unknown unknown unknown unknown unknown 0 fixture)
        recordOutput=$(probeRealityTargetRecord "" "${record}" unknown unknown)
        [[ "$(realityTargetResultField "${recordOutput#*$'\t'}" 9)" == unknown ]]
        [[ "$(scannerRealityNetworkProfile 192.0.2.1 unknown unknown)" == $'unknown\tunknown\tscanner_local' ]]
    )

    cat >"${fixtureFile}" <<'EOF'
fixture-primary.example.com|fixture-primary.example.com|Fixture Primary|global|large_site|unknown|1|yes|fixture default
fixture-secondary.example.com|fixture-secondary.example.com|Fixture Secondary|global|large_site|unknown|2|yes|fixture secondary
fixture-media.example.com|fixture-media.example.com|Fixture Media|global|media|unknown|3|yes|fixture media
fixture-developer.example.com|fixture-developer.example.com|Fixture Developer|global|developer|unknown|4|yes|fixture developer
fixture-asia.example.com|fixture-asia.example.com|Fixture Asia|asia|large_site|unknown|5|no|fixture asia manual
www.cloudflare.com|www.cloudflare.com|Cloudflare|global|cdn|yes|6|no|fixture blocked
cdn-risk.example.com|cdn-risk.example.com|CDN Risk|global|large_site|yes|6|no|fixture CDN risk
www.apple.com|www.apple.com|Apple|global|large_site|unknown|7|no|fixture blocked
www.java.com|www.java.com|Java|global|large_site|unknown|8|no|fixture blocked relay
lol.secure.dyn.riotcdn.net|lol.secure.dyn.riotcdn.net|Riot CDN|global|cdn|unknown|9|no|fixture blocked relay
WWW.JAVA.COM|WWW.JAVA.COM|Java Upper|global|large_site|unknown|10|no|fixture blocked relay uppercase
LOL.SECURE.DYN.RIOTCDN.NET|LOL.SECURE.DYN.RIOTCDN.NET|Riot CDN Upper|global|cdn|unknown|11|no|fixture blocked relay uppercase
EOF
    export PADM_REALITY_TARGET_CANDIDATES_FILE="${fixtureFile}"
    REALITY_TARGET_PAGE_SIZE=2
    AUTO_INSTALL=

    (
        local output
        realityTargetBlockedCandidates() {
            printf '%s\n' 'blocked.example.com|Blocked Site|manual|Note \ path|ignored' \
                'empty.example.com|||'
        }
        echoContent() { :; }
        menuItem() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }
        menuLine() { printf '%s\n' "$1"; }
        menuClose() { :; }
        awk() { return 99; }
        output=$(showRealityTargetBlockedCandidates)
        [[ "${output}" == $'1\tblocked.example.com\tBlocked Site reason=manual\n    Note \\ path\n2\tempty.example.com\t reason=\n    ' ]]
    )

    (
        local selectedTarget selectedSni switched=0 confirmation=n menuSequence="2 1 2 2 5 8" scope=
        realityTargetHost=installed.example.com
        realityTargetPort=443
        realitySNI=installed-sni.example.com
        showRealityTargetScanResults() {
            realityTargetHost=chosen.example.com
            realityTargetPort=8443
            realitySNI=chosen-sni.example.com
            return 2
        }
        autoConfirm() { printf -v "$4" '%s' "${confirmation}"; }
        changeInstalledRealityTarget() {
            [[ "${realityTargetHost}" == "installed.example.com" && "${realitySNI}" == "installed-sni.example.com" ]]
            [[ "$1" == "chosen.example.com:8443" && "$2" == "chosen-sni.example.com" ]]
            switched=$((switched + 1))
            return 1
        }
        selectRealityTargetFromScanResults selectedTarget selectedSni
        [[ "${selectedTarget}" == "chosen.example.com:8443" && "${selectedSni}" == "chosen-sni.example.com" ]]
        [[ "${realityTargetHost}" == "installed.example.com" && "${realitySNI}" == "installed-sni.example.com" ]]
        changeRealityTargetFromScanResults
        [[ "${switched}" == 0 ]]
        confirmation=y
        regressionExpectStatus 1 changeRealityTargetFromScanResults
        [[ "${switched}" == 1 && "${realityTargetHost}" == "installed.example.com" ]]
        readInstallProtocolType() { :; }
        readConfigHostPathUUID() { :; }
        readCustomPort() { :; }
        readSingBoxConfig() { :; }
        showRealityTargetPqcSummary() { :; }
        menuReadChoice() {
            printf -v "$3" '%s' "${menuSequence%% *}"
            menuSequence=${menuSequence#* }
        }
        scanLocalAsnRealityTargets() { scope+="${1:-recommended} "; }
        changeRealityTargetFromScanResults() { switched=$((switched + 1)); }
        manageRealityTarget
        [[ "${scope}" == "recommended recommended_only " && "${switched}" == 2 ]]
        local failedRead
        autoRead() {
            printf -v "$3" '%s' 'partial.example.com:8443'
            [[ "$1" != "${failedRead}" ]]
        }
        changeInstalledRealityTarget() { switched=$((switched + 1)); }
        parseRealityTargetInput() { switched=$((switched + 1)); }
        for failedRead in reality_target reality_server_name; do
            menuSequence='6'
            switched=0
            regressionExpectStatus 1 manageRealityTarget
            [[ "${switched}" == 0 && "${realityTargetHost}" == installed.example.com && "${realitySNI}" == installed-sni.example.com ]]
        done
        for failedRead in reality_target reality_target_filter; do
            if [[ "${failedRead}" == reality_target ]]; then menuSequence=m; else menuSequence=f; fi
            switched=0
            regressionExpectStatus 1 selectRealityTargetCandidateInteractive
            [[ "${switched}" == 0 && "${realityTargetHost}" == installed.example.com && "${realitySNI}" == installed-sni.example.com ]]
        done
        autoRead() { printf -v "$3" '%s' ''; }
        menuSequence='6 8'
        manageRealityTarget
        [[ "${menuSequence}" == 8 && "${switched}" == 0 ]]
        for REALITY_TARGET_PAGE_SIZE in 0 invalid; do
            menuSequence=r
            regressionExpectStatus 1 selectRealityTargetCandidateInteractive
        done
    )

    (
        local changed=0 blocked=0 confirm=y
        # 读取失败即使留下 y，也不能复用旧确认或执行后续变更。
        autoRead() { printf -v "$3" '%s' y; return 7; }
        regressionExpectStatus 7 autoConfirm reality_target_confirm "确认切换？" y confirm
        [[ "${confirm}" == n ]]
        selectRealityTargetFromScanResults() {
            printf -v "$1" '%s' chosen.example.com:443
            printf -v "$2" '%s' chosen.example.com
        }
        changeInstalledRealityTarget() { changed=$((changed + 1)); }
        regressionExpectStatus 1 changeRealityTargetFromScanResults
        menuReadChoice() { printf -v "$3" '%s' 2; }
        addRealityTargetBlockedCandidate() { blocked=$((blocked + 1)); }
        regressionExpectStatus 1 showRealityTargetQualityActions chosen.example.com:443
        [[ "${changed}" == 0 && "${blocked}" == 0 ]]
    )

    [[ "$(realityTargetCandidateCount)" == "5" ]]
    [[ "$(realityTargetFilteredCandidateCount recommended)" == "4" ]]
    [[ "$(realityTargetFilteredCandidateCount asia)" == "1" ]]
    [[ "$(realityTargetFilteredCandidateCount secondary)" == "1" ]]
    firstRecommendedRealityCandidate=$(realityTargetFilteredCandidateLineByIndex recommended 1)
    [[ "$(realityTargetCandidateField "${firstRecommendedRealityCandidate}" 1)" == "fixture-primary.example.com" ]]
    export PADM_REALITY_TARGET_RESULTS_FILE="${cacheFile}"
    formatRealityTargetResultLine "fixture-primary.example.com:443" "fixture-primary.example.com" "Fixture Primary" "large_site" "no" "192.0.2.44" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "cached" "Los Angeles, United States" >"${cacheFile}"
    formatRealityTargetResultLine "fixture-secondary.example.com:8443" "fixture-secondary.example.com" "Fixture Secondary Alternate Port" "large_site" "unknown" "192.0.2.45" "AS64500" "ExampleNet" "same_asn" "B" "yes" "2048" "yes" "1234567890" "alternate port cache" >>"${cacheFile}"
    [[ "$(realityTargetCachedAsnSummary "fixture-primary.example.com:443")" == "192.0.2.44 AS64500 ExampleNet" ]]
    [[ "$(realityTargetCachedNetworkSummary "fixture-primary.example.com:443")" == "同 ASN" ]]
    [[ "$(realityTargetCachedAsnSummary "missing.example.com:443")" == "暂无缓存" ]]
    (
        local candidatePageOutput
        menuLine() { printf '%s\n' "$*"; }
        candidatePageOutput=$(showRealityTargetCandidatePage all 1 2)
        [[ "${candidatePageOutput}" == *"location=Los Angeles, United States"* ]]
    )
    formatRealityTargetResultLine "stale.example.com:443" "stale.example.com" "Stale" "test" "no" "192.0.2.40" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "old A" >"${staleResultsFile}"
    formatRealityTargetResultLine "stale.example.com:443" "stale.example.com" "Stale" "test" "no" "192.0.2.40" "AS64500" "ExampleNet" "same_asn" "B" "yes" "4096" "yes" "1234567891" "latest B" >>"${staleResultsFile}"
    (
        export PADM_REALITY_TARGET_RESULTS_FILE="${staleResultsFile}"
        ! realityTargetResultLine "stale.example.com:443" >/dev/null
        ! grep -qF $'stale.example.com:443\t' <<<"$(sortedRealityTargetResults)"
        [[ "$(realityTargetResultCount)" == "0" ]]
        ! bestScannedRealityTargetLine A >/dev/null
        ! grep -qF $'stale.example.com:443\t' <<<"$(realityTargetRefreshRecords)"
    )
    refreshRecordsWithNewCandidate=$(realityTargetRefreshRecords)
    [[ "$(printf '%s\n' "${refreshRecordsWithNewCandidate}" | wc -l | tr -d ' ')" == "4" ]]
    grep -qF $'fixture-primary.example.com:443\t' <<<"${refreshRecordsWithNewCandidate}"
    grep -qF $'fixture-secondary.example.com:443\t' <<<"${refreshRecordsWithNewCandidate}"
    ! grep -qF $'fixture-secondary.example.com:8443\t' <<<"${refreshRecordsWithNewCandidate}"
    (
        local scopeResultsFile="${TMP_DIR}/reality-refresh-scope.tsv" records
        export PADM_REALITY_TARGET_RESULTS_FILE="${scopeResultsFile}"
        formatRealityTargetResultLine "library-only.example.com:443" "library-only.example.com" \
            "Library Only" "test" "no" "192.0.2.99" "AS64500" "ExampleNet" \
            "same_asn" "A" "yes" "4096" "yes" "1234567890" "library fixture" >"${scopeResultsFile}"
        grep -qF $'library-only.example.com:443\t' <<<"$(realityTargetRefreshRecords recommended)"
        records=$(realityTargetRefreshRecords recommended_only)
        [[ "$(printf '%s\n' "${records}" | wc -l | tr -d ' ')" == "4" ]]
        grep -qF $'fixture-primary.example.com:443\t' <<<"${records}"
        ! grep -qF $'library-only.example.com:443\t' <<<"${records}"
        ! grep -qF $'fixture-asia.example.com:443\t' <<<"${records}"
    )
    writeRealityTargetResultLine "fixture-primary.example.com:443" "fixture-primary.example.com" "Fixture Primary" "large_site" "no" "192.0.2.44" "AS64500" "ExampleNet" "same_asn" "B" "yes" "2048" "yes" "1234567891" "updated" "Los Angeles, United States"
    ! realityTargetResultLine "fixture-primary.example.com:443" >/dev/null
    [[ "$(realityTargetResultCount)" == "0" ]]
    formatRealityTargetResultLine "legacy.example.com:443" "legacy.example.com" "Legacy" "test" "yes" "192.0.2.45" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567892" "legacy risk" >"${cacheFile}"
    formatRealityTargetResultLine "www.java.com:443" "www.java.com" "Java" "test" "no" "192.0.2.46" "AS64500" "ExampleNet" "same_asn" "A" "yes" "8192" "yes" "1234567893" "legacy blocked target" >>"${cacheFile}"
    formatRealityTargetResultLine "nodejs.org:443" "nodejs.org" "Node.js" "test" "no" "192.0.2.47" "AS64500" "ExampleNet" "same_asn" "A" "yes" "8192" "yes" "1234567894" "legacy blocked target" >>"${cacheFile}"
    : >"${emptyResultsFile}"
    writeRealityTargetResultLines "${emptyResultsFile}"
    [[ ! -s "${cacheFile}" ]]
    [[ "$(realityTargetResultCount)" == "0" ]]
    ! grep -qF $'www.java.com:443\t' <<<"$(sortedRealityTargetResults)"
    ! grep -qF $'nodejs.org:443\t' <<<"$(sortedRealityTargetResults)"
    [[ "$(realityTargetRefreshRecords | wc -l | tr -d ' ')" == "4" ]]
    grep -qF $'fixture-primary.example.com:443\t' <<<"$(realityTargetRefreshRecords)"
    ! grep -qF $'fixture-asia.example.com:443\t' <<<"$(realityTargetRefreshRecords)"
    [[ "$(realityTargetRefreshRecords all | wc -l | tr -d ' ')" == "5" ]]
    grep -qF $'fixture-asia.example.com:443\t' <<<"$(realityTargetRefreshRecords all)"
    (
        local pageResultsFile="${TMP_DIR}/reality-page-selection-results.tsv"
        local pageChoiceSequence pageIndex REALITY_TARGET_RESULT_PAGE_SIZE=10
        export PADM_REALITY_TARGET_RESULTS_FILE="${pageResultsFile}"
        : >"${pageResultsFile}"
        for ((pageIndex = 1; pageIndex <= 11; pageIndex++)); do
            formatRealityTargetResultLine "page-${pageIndex}.example.com:443" "page-${pageIndex}.example.com" \
                "Page ${pageIndex}" "test" "no" "192.0.2.${pageIndex}" "AS64500" "ExampleNet" \
                "same_asn" "A" "yes" "$((5000 - pageIndex))" "yes" "1234567890" "page fixture" >>"${pageResultsFile}"
        done
        echoContent() { :; }
        menuClose() { :; }
        menuItem() { :; }
        menuLine() { :; }
        errorCard() { printf '%s\n' "$*" >>"${pageResultsFile}.errors"; }
        realityTargetStatusBlock() { :; }
        menuReadChoice() {
            printf -v "$3" '%s' "${pageChoiceSequence%% *}"
            pageChoiceSequence=${pageChoiceSequence#* }
        }
        pageChoiceSequence="11 01"
        regressionExpectStatus 2 showRealityTargetScanResults all interactive 1
        [[ "${realityTargetHost}" == "page-1.example.com" ]]
        [[ "$(wc -l <"${pageResultsFile}.errors" | tr -d ' ')" == "1" ]]
        pageChoiceSequence="0 1"
        regressionExpectStatus 2 showRealityTargetScanResults all interactive 2
        [[ "${realityTargetHost}" == "page-11.example.com" ]]
        [[ "$(wc -l <"${pageResultsFile}.errors" | tr -d ' ')" == "2" ]]
        selectRealityTargetScanResultFilter() { printf 'scanner\n'; }
        formatRealityTargetResultLine "page-scanner.example.com:443" "scanner-sni.example.com" \
            "Scanner" "scanner" "no" "192.0.2.12" "AS64500" "ExampleNet" \
            "same_asn" "A" "yes" "4000" "yes" "1234567890" "scanner fixture" >>"${pageResultsFile}"
        pageChoiceSequence="f 2 999999999999999999999 01"
        regressionExpectStatus 2 showRealityTargetScanResults all interactive 2
        [[ "${realityTargetHost}" == "page-scanner.example.com" && "${realitySNI}" == "scanner-sni.example.com" ]]
        [[ "$(wc -l <"${pageResultsFile}.errors" | tr -d ' ')" == "4" ]]
        REALITY_TARGET_RESULT_PAGE_SIZE=0
        showRealityTargetScanResults all once
    )
    (
        local persistenceRoot="${TMP_DIR}/reality-persistence-failure"
        local persistenceStatusLog="${persistenceRoot}/status.log"
        local failureStage removed summary fullScan
        mkdir -p "${persistenceRoot}/tmp"
        TMPDIR="${persistenceRoot}/tmp"
        export PADM_REALITY_TARGET_RESULTS_FILE="${persistenceRoot}/results.tsv"
        realityTargetDetector() { printf 'fake-xray\n'; }
        currentRealityNetworkProfile() { printf '203.0.113.10\tAS64500\tExampleNet\n'; }
        realityTargetRefreshRecords() {
            formatRealityTargetResultLine "persist-failure.example.com:443" "persist-failure.example.com" \
                "Persist Failure" "test" "no" "unknown" "unknown" "unknown" "unknown" \
                "unknown" "unknown" "unknown" "unknown" "0" "fixture"
        }
        probeRealityTargetRecord() { printf 'OK\t%s\n' "$2"; }
        realityTargetProgressLine() { :; }
        realityTargetStatusBlock() { printf '%s\n' "$*" >>"${persistenceStatusLog}"; }
        writeRealityTargetResultLines() { [[ "${failureStage}" != write ]]; }
        updateRealityTargetLibrary() {
            writeRealityTargetResultLines "$1" || return 1
            removed=1
            return 1
        }
        printf 'IP,ORIGIN,CERT_DOMAIN,CERT_ISSUER,GEO_CODE\n' >"${persistenceRoot}/empty.csv"
        for failureStage in write remove; do
            removed=0
            : >"${persistenceStatusLog}"
            regressionExpectStatus 1 scanLocalAsnRealityTargets
            grep -qF "保存目标库失败" "${persistenceStatusLog}"
            ! grep -q '^green' "${persistenceStatusLog}"
            [[ "${failureStage}" != write || "${removed}" == 0 ]]
            [[ -z "$(find "${TMPDIR}" -mindepth 1 -print -quit)" ]]
            summary=unchanged
            : >"${persistenceStatusLog}"
            regressionExpectStatus 1 importRealityScannerResults "${persistenceRoot}/empty.csv" AS64500 ExampleNet summary
            [[ "${summary}" == unchanged ]]
            grep -qF "保存目标库失败" "${persistenceStatusLog}"
            ! grep -q '^green' "${persistenceStatusLog}"
            [[ -z "$(find "${TMPDIR}" -mindepth 1 -print -quit)" ]]
        done
        (
            local probeCase collectionRecord updateCalls=0
            local collectionTarget=persist-failure.example.com:443
            collectionRecord=$(formatRealityTargetResultLine "${collectionTarget}" persist-failure.example.com \
                "Collection Failure" scanner no 192.0.2.1 AS64500 ExampleNet same_asn A yes 4096 yes 1 fixture)
            builtin printf 'unchanged\n' >"${PADM_REALITY_TARGET_RESULTS_FILE}"
            normalizeRealityScannerCsv() {
                builtin printf '192.0.2.1\tAS64500\tpersist-failure.example.com\tExample CA\tUS\n'
            }
            runRealityTargetProbeJobs() {
                case "${probeCase}" in
                result) builtin printf 'OK\t%s\n' "${collectionRecord}" >"$3/0.result" ;;
                empty) builtin printf 'OK\t\n' >"$3/0.result" ;;
                fail) builtin printf 'FAIL\t%s\n' "${collectionTarget}" >"$3/0.result" ;;
                missing) : ;;
                esac
            }
            # 模拟结果或失败目标追加失败，不影响探测输出及菜单提示。
            printf() {
                if [[ "$1" == '%s\n' && ( "${2:-}" == "${collectionRecord}" || "${2:-}" == "${collectionTarget}" ) ]]; then
                    return 1
                fi
                builtin printf "$@"
            }
            updateRealityTargetLibrary() { updateCalls=$((updateCalls + 1)); }
            for probeCase in result empty fail missing; do
                : >"${persistenceStatusLog}"
                regressionExpectStatus 1 scanLocalAsnRealityTargets
                summary=unchanged
                regressionExpectStatus 1 importRealityScannerResults "${persistenceRoot}/empty.csv" AS64500 ExampleNet summary
                [[ "${updateCalls}" == 0 && "${summary}" == unchanged ]]
                [[ "$(<"${PADM_REALITY_TARGET_RESULTS_FILE}")" == unchanged ]]
                [[ -z "$(find "${TMPDIR}" -mindepth 1 -print -quit)" ]]
                ! grep -q '^green' "${persistenceStatusLog}"
            done
        )
        ensureRealityScannerBinary() { :; }
        realityScannerOutputPath() { printf '%s\n' "${persistenceRoot}/scan.csv"; }
        runRealityScannerQuietly() { printf 'IP,ORIGIN,CERT_DOMAIN,CERT_ISSUER,GEO_CODE\n' >"$1"; }
        importRealityScannerResults() { return 1; }
        sleep() { :; }
        printf '192.0.2.1\n' >"${persistenceRoot}/targets"
        printf '192.0.2.0/24\n' >"${persistenceRoot}/prefixes"
        : >"${persistenceStatusLog}"
        regressionExpectStatus 1 runRealityScannerTargetFile "${persistenceRoot}/targets" AS64500 ExampleNet
        ! grep -qF '抽样扫描汇总' "${persistenceStatusLog}"
        regressionExpectStatus 1 runRealityScannerPrefixFile "${persistenceRoot}/prefixes" AS64500 ExampleNet
        [[ -z "$(find "${TMPDIR}" -mindepth 1 -print -quit)" ]]
        fetchRealityAsnPrefixes() { printf '192.0.2.0/24\n'; }
        autoRead() { printf -v "$3" '%s' y; }
        selectRealityAsnScanPlan() {
            padmCreateTempPath selectedRealityScannerPrefixFile
            printf '192.0.2.0/24\n' >"${selectedRealityScannerPrefixFile}"
            selectedRealityAsnFullScan=${fullScan}
            selectedRealityScannerRange=fixture
            selectedRealityAsnPrefixTotal=1
            selectedRealityAsnAddressTotal=1
        }
        for fullScan in true false; do
            regressionExpectStatus 1 runRealityScannerSameAsnPrefixes
            [[ -z "$(find "${TMPDIR}" -mindepth 1 -print -quit)" ]]
        done
        autoRead() { printf -v "$3" '%s' y; return 1; }
        local scanCalls=0
        runRealityScannerRange() { scanCalls=$((scanCalls + 1)); return 99; }
        runRealityScannerTargetFile() { scanCalls=$((scanCalls + 1)); return 99; }
        runRealityScannerPrefixFile() { scanCalls=$((scanCalls + 1)); return 99; }
        regressionExpectStatus 1 runRealityScannerAdvanced
        [[ -z "$(find "${TMPDIR}" -mindepth 1 -print -quit)" ]]
        for fullScan in true false; do
            regressionExpectStatus 1 runRealityScannerSameAsnPrefixes
            [[ -z "$(find "${TMPDIR}" -mindepth 1 -print -quit)" ]]
        done
        [[ "${scanCalls}" == 0 ]]
    )
    (
        local pqcRoot="${TMP_DIR}/reality-pqc-summary"
        local configPath="${pqcRoot}/" output
        mkdir -p "${configPath}"
        menuLine() { printf '%s\n' "$*"; }
        showRealityTargetCachedQuality() { printf 'unexpected probe\n'; return 1; }
        jq -n '{inbounds: [{streamSettings: {network: "grpc", realitySettings: {mldsa65Verify: "grpc-pqv"}}}]}' >"${configPath}/grpc.json"
        output=$(showRealityTargetPqcSummary)
        [[ "${output}" == "ML-DSA-65 (grpc): grpc-pqv" ]]
        jq -n '{inbounds: [{streamSettings: {network: "tcp", realitySettings: {}}},
            {streamSettings: {network: "xhttp", realitySettings: {mldsa65Verify: "xhttp-pqv"}}}]}' >"${configPath}/mixed.json"
        output=$(showRealityTargetPqcSummary)
        [[ "${output}" == *"ML-DSA-65 (grpc): grpc-pqv"* && "${output}" == *"ML-DSA-65 (tcp): 未启用"* && "${output}" == *"ML-DSA-65 (xhttp): xhttp-pqv"* ]]
        [[ "${output}" != *"unexpected probe"* ]]
        printf '{bad json\n' >"${configPath}/invalid.json"
        regressionExpectStatus 1 showRealityTargetPqcSummary
        configPath=
        [[ "$(showRealityTargetPqcSummary)" == "ML-DSA-65: 未配置" ]]
    )
    (
        local certArgs="${TMP_DIR}/reality-certificate-args.log"
        local certStatus="${TMP_DIR}/reality-certificate-status.log"
        local cachedLine matches=true
        realityTargetHost=2001:db8::1
        realityTargetPort=443
        realitySNI=installed-cert.example.com
        cachedLine=$(formatRealityTargetResultLine "2001:db8::1:443" "cached-cert.example.com" "Cert" "test" "no" "2001:db8::1" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "fixture")
        realityTargetResultLine() { printf '%s\n' "${cachedLine}"; }
        realityTargetStatusBlock() { printf '%s\n' "$*" >>"${certStatus}"; }
        timeout() { shift; "$@"; }
        openssl() {
            printf '%s\n' "$*" >>"${certArgs}"
            if [[ "$1" == s_client ]]; then
                printf '%s\n' '-----BEGIN CERTIFICATE-----' fixture '-----END CERTIFICATE-----'
            elif [[ " $* " == *" -checkhost "* ]]; then
                [[ "${matches}" == true ]]
            fi
        }
        showRealityTargetCertificateChain "2001:db8::1:443"
        grep -qF -- '-connect [2001:db8::1]:443 -servername installed-cert.example.com' "${certArgs}"
        grep -qF -- '-checkhost installed-cert.example.com' "${certArgs}"
        grep -qF 'SAN/Subject 匹配 installed-cert.example.com' "${certStatus}"
        : >"${certStatus}"
        realityTargetHost=
        matches=false
        showRealityTargetCertificateChain "2001:db8::1:443"
        grep -qF -- '-servername cached-cert.example.com' "${certArgs}"
        grep -qF 'SAN/Subject 未确认匹配 cached-cert.example.com' "${certStatus}"
    )
    (
        local qualityActions=0 qualityCertificates=0
        showRealityTargetQuality() { return 1; }
        showRealityTargetCertificateChain() { qualityCertificates=$((qualityCertificates + 1)); return 1; }
        showRealityTargetQualityActions() { qualityActions=$((qualityActions + 1)); return 1; }
        regressionExpectStatus 1 showRealityTargetCachedQuality "failed-detail.example.com:443"
        [[ "${qualityActions}" == 1 && "${qualityCertificates}" == 1 ]]
    )
    (
        local option5ResultsFile="${TMP_DIR}/reality-option5-results.tsv"
        local option5SortCallsFile="${TMP_DIR}/reality-option5-sort-calls.log"
        local option5BlockedCallsFile="${TMP_DIR}/reality-option5-blocked-calls.log"
        export PADM_REALITY_TARGET_RESULTS_FILE="${option5ResultsFile}"
        export PADM_REALITY_TARGET_SCAN_FILE="${option5ResultsFile}"
        : >"${option5SortCallsFile}"
        : >"${option5BlockedCallsFile}"
        formatRealityTargetResultLine "option5-a.example.com:443" "option5-a.example.com" "Option 5 A" "test" "no" "192.0.2.44" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "cached" >"${option5ResultsFile}"
        formatRealityTargetResultLine "option5-b.example.com:443" "option5-b.example.com" "Option 5 B" "test" "no" "192.0.2.45" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "cached" >>"${option5ResultsFile}"
        eval "$(declare -f sortedRealityTargetResults | sed "1s/^sortedRealityTargetResults/originalSortedRealityTargetResults/")"
        eval "$(declare -f realityTargetBlockedCandidates | sed "1s/^realityTargetBlockedCandidates/originalRealityTargetBlockedCandidates/")"
        sortedRealityTargetResults() {
            printf 'sorted\n' >>"${option5SortCallsFile}"
            originalSortedRealityTargetResults
        }
        realityTargetBlockedCandidates() {
            printf 'blocked\n' >>"${option5BlockedCallsFile}"
            originalRealityTargetBlockedCandidates
        }
        showRealityTargetScanResults all interactive <<<"r" >/dev/null
        [[ "$(wc -l <"${option5SortCallsFile}" | tr -d ' ')" == "1" ]]
        [[ "$(wc -l <"${option5BlockedCallsFile}" | tr -d ' ')" == "1" ]]
    )
    (
        local relativeResultsRoot="${TMP_DIR}/reality-relative-results"
        mkdir -p "${relativeResultsRoot}/child"
        formatRealityTargetResultLine "safe.example.com:443" "safe.example.com" "Safe" "test" "no" "192.0.2.47" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567894" "managed path fixture" >"${relativeResultsRoot}/results.tsv"
        cd "${relativeResultsRoot}/child"
        export PADM_REALITY_TARGET_RESULTS_FILE=../results.tsv
        ! sortedRealityTargetResults
    )
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
    ! realityTargetCandidates | grep -q '^cdn-risk.example.com|'
    ! realityTargetCandidates | grep -q '^www.apple.com|'
    ! realityTargetCandidates | grep -qi '^www.java.com|'
    ! realityTargetCandidates | grep -qi '^nodejs.org|'
    ! realityTargetCandidates | grep -qi 'riotcdn.net|'
    realityTargetCandidateBlocked "www.java.com"
    realityTargetCandidateBlocked "nodejs.org" cloudflare_relay
    realityTargetCandidateBlocked "www.nodejs.org" cloudflare_relay
    realityTargetCandidateBlocked "lol.secure.dyn.riotcdn.net"
    realityTargetCandidateBlocked "WWW.JAVA.COM"
    realityTargetCandidateBlocked "LOL.SECURE.DYN.RIOTCDN.NET"

    selectRealityTargetCandidateInteractive <<<"n
3
"
    [[ "${realityTargetHost}" == "fixture-media.example.com" ]]
    (
        local snapshotCalls="${TMP_DIR}/reality-candidate-snapshot-calls.log"
        local snapshotItems="${TMP_DIR}/reality-candidate-snapshot-items.log"
        local poolChanged=false
        eval "$(declare -f realityTargetCandidatePool | sed '1s/^realityTargetCandidatePool/snapshotOriginalCandidatePool/')"
        realityTargetCandidatePool() {
            printf 'pool\n' >>"${snapshotCalls}"
            if [[ "${poolChanged}" == false ]]; then
                snapshotOriginalCandidatePool
            else
                printf '%s\n' 'snapshot-secondary.example.com|snapshot-sni.example.com|Snapshot Secondary|asia|developer|unknown|1|no|changed fixture'
            fi
        }
        menuItem() { printf '%s\t%s\n' "$1" "$2" >>"${snapshotItems}"; }
        menuReadChoice() {
            read -r "$3" || return 1
            poolChanged=true
        }
        autoRead() { read -r "$3"; }
        : >"${snapshotCalls}"
        : >"${snapshotItems}"
        selectRealityTargetCandidateInteractive < <(printf 'n\n0\n01\n999999999999999999999999999999\n3\n') >/dev/null
        [[ "${realityTargetHost}" == fixture-media.example.com ]]
        [[ "$(wc -l <"${snapshotCalls}")" == 1 ]]
        grep -qxF $'3\tfixture-media.example.com:443' "${snapshotItems}"
        ! grep -qF snapshot-secondary "${snapshotItems}"
        local snapshotFilter
        for snapshotFilter in all secondary; do
            poolChanged=false
            : >"${snapshotCalls}"
            selectRealityTargetCandidateInteractive < <(printf 'f\n%s\n1\n' "${snapshotFilter}") >/dev/null
            [[ "$(wc -l <"${snapshotCalls}")" == 2 ]]
            [[ "${realityTargetHost}" == snapshot-secondary.example.com && "${realitySNI}" == snapshot-sni.example.com ]]
        done
    )
    secondaryCandidate=$(realityTargetFilteredCandidateLineByIndex secondary 1)
    [[ "$(realityTargetCandidateField "${secondaryCandidate}" 1)" == "fixture-secondary.example.com" ]]
    selectRealityTargetCandidateInteractive <<<"m
manual.example.com:8443
"
    [[ "${realityTargetHost}" == "manual.example.com" ]]
    [[ "${realityTargetPort}" == "8443" ]]
    (
        local selectionResultsFile="${TMP_DIR}/reality-candidate-selection-results.tsv"
        local selectionOrderFile="${TMP_DIR}/reality-candidate-selection-order.log"
        export PADM_REALITY_TARGET_RESULTS_FILE="${selectionResultsFile}"
        : >"${selectionOrderFile}"
        scanLocalAsnRealityTargets() {
            printf 'scan\n' >>"${selectionOrderFile}"
            formatRealityTargetResultLine "fixture-primary.example.com:443" "fixture-primary.example.com" "Fixture Primary" "large_site" "no" "192.0.2.44" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "检测通过" >"${selectionResultsFile}"
            formatRealityTargetResultLine "fixture-secondary.example.com:443" "fixture-secondary.example.com" "Fixture Secondary" "large_site" "no" "192.0.2.45" "AS64500" "ExampleNet" "same_asn" "B" "yes" "2048" "yes" "1234567890" "B 级排除" >>"${selectionResultsFile}"
            formatRealityTargetResultLine "fixture-media.example.com:443" "fixture-media.example.com" "Fixture Media" "media" "no" "192.0.2.46" "AS64500" "ExampleNet" "same_asn" "C" "yes" "1024" "yes" "1234567890" "C 级排除" >>"${selectionResultsFile}"
        }
        selectRealityTargetCandidateInteractive detect-first <<<"1" >/dev/null
        printf 'select\n' >>"${selectionOrderFile}"
        [[ "${realityTargetHost}" == "fixture-primary.example.com" ]]
        [[ "$(<"${selectionOrderFile}")" == $'scan\nselect' ]]
        PADM_REALITY_TARGET_SELECTION_REQUIRE_SCAN=1
        [[ "$(realityTargetCandidateCount)" == "1" ]]
        [[ "$(realityTargetCandidateField "$(realityTargetCandidateLineByIndex 1)" 1)" == "fixture-primary.example.com" ]]
        unset PADM_REALITY_TARGET_SELECTION_REQUIRE_SCAN
    )
    if selectRealityTargetCandidateInteractive <<<"r
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
    local largePrefixFile="${TMP_DIR}/asn-large-prefix.txt"
    local largeSampleFile="${TMP_DIR}/asn-large-sample-ips.txt"
    AUTO_INSTALL=
    (
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/reality_targets.sh"
        fetchPublicIP() { printf '999.0.0.1\n'; }
        fetchUrlToStdout() {
            case "$1" in
            https://api.ipify.org) printf '999.0.0.2\n' ;;
            https://ipinfo.io/ip) printf '203.0.113.10\n' ;;
            https://api.bgpview.io/ip/203.0.113.10 | https://ipinfo.io/203.0.113.10/org) return 1 ;;
            'https://stat.ripe.net/data/prefix-overview/data.json?resource=203.0.113.10')
                printf '%s\n' '{"data":{"asns":[{"asn":64500,"holder":"ExampleNet"}]}}'
                ;;
            *) return 1 ;;
            esac
        }
        [[ "$(currentRealityNetworkProfile)" == $'203.0.113.10\tAS64500\tExampleNet' ]]
    )
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
    printf '10.0.0.0/8\n' >"${largePrefixFile}"
    generateRealityAsnSampleIps "${largePrefixFile}" 10000 "${largeSampleFile}"
    [[ "$(wc -l <"${largeSampleFile}" | tr -d ' ')" == "10000" ]]
    awk '!seen[$0]++ {next} {exit 1}' "${largeSampleFile}"
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
    (
        local fullScan planCalls=0 failedSampleFile="${TMP_DIR}/asn-confirm-failed-sample.txt"
        autoRead() { printf -v "$3" '%s' y; return 1; }
        selectRealityAsnSampleSize() {
            planCalls=$((planCalls + 1))
            selectedRealityAsnFullScan=${fullScan}
            selectedRealityAsnSampleSize=1
        }
        showRealityAsnPrefixSetSummary() { :; }
        showRealityAsnSampleSummary() { :; }
        padmCreateTempPath() { printf -v "$1" '%s' "${failedSampleFile}"; : >"${failedSampleFile}"; }
        generateRealityAsnSampleIps() { printf '192.0.2.1\n' >"$3"; }
        for fullScan in true false; do
            planCalls=0
            regressionExpectStatus 1 selectRealityAsnScanPlan AS64500 "${asnPrefixFile}"
            [[ "${planCalls}" == 1 && -z "${selectedRealityScannerPrefixFile}" ]]
            [[ ! -e "${failedSampleFile}" ]]
        done
    )
    if [[ -n "${oldAutoInstall}" ]]; then
        AUTO_INSTALL="${oldAutoInstall}"
    else
        unset AUTO_INSTALL
    fi
}

runRealityCandidateFullRegression() {
    local firstRecommendedRealityCandidate firstRealityCandidate secondRealityCandidate blockedCloudflareRealityCandidate blockedNodejsRealityCandidate candidateHost
    [[ "$(realityTargetCandidateCount)" == "25" ]]
    [[ "$(realityTargetCandidatePool | wc -l | tr -d ' ')" == "25" ]]
    [[ "$(realityTargetFilteredCandidateCount all)" == "$(realityTargetCandidateCount)" ]]
    [[ "$(realityTargetBuiltInCdnBlockedCandidates | sort -u | wc -l | tr -d ' ')" == "154" ]]
    [[ "$(realityTargetFilteredCandidateCount recommended)" == "25" ]]
    [[ "$(realityTargetFilteredCandidateCount manual)" == "0" ]]
    ! realityTargetCandidates | grep -qF 'www.microsoft.com|'
    [[ "$(realityTargetFilteredCandidateCount dev)" == "$(realityTargetFilteredCandidateCount developer)" ]]
    firstRecommendedRealityCandidate=$(realityTargetFilteredCandidateLineByIndex recommended 1)
    [[ "$(realityTargetCandidateField "${firstRecommendedRealityCandidate}" 1)" == "www.libreoffice.org" ]]
    firstRealityCandidate=$(realityTargetCandidateLineByIndex 1)
    [[ "$(realityTargetCandidateField "${firstRealityCandidate}" 1)" == "www.libreoffice.org" ]]
    secondRealityCandidate=$(realityTargetCandidateLineByIndex 2)
    [[ "$(realityTargetCandidateField "${secondRealityCandidate}" 1)" == "www.collaboraoffice.com" ]]
    ! realityTargetFilteredCandidates recommended | grep -Eq '^(www.gnu.org|www.debian.org|www.ubuntu.com|mariadb.org)[|]'
    blockedCloudflareRealityCandidate=$(realityTargetBlockedCandidates | grep '^www.cloudflare.com|')
    [[ -n "${blockedCloudflareRealityCandidate}" ]]
    blockedNodejsRealityCandidate=$(realityTargetBlockedCandidates | grep '^nodejs.org|')
    [[ -n "${blockedNodejsRealityCandidate}" ]]
    realityTargetBlockedCandidates >/dev/null
    ! realityTargetCandidatePool | grep -q '^nodejs.org|'
    [[ "$(realityTargetCandidatePool | awk -F'|' 'tolower($6) == "yes" {count++} END {print count + 0}')" == "0" ]]
    while IFS='|' read -r candidateHost _; do
        if realityTargetCandidateBlocked "${candidateHost}"; then
            return 1
        fi
    done < <(realityTargetCandidatePool)
    realityTargetCandidateBlocked "www.ibm.com" cdn_edge
    ! realityTargetCandidateBlocked "www.gnu.org"
    [[ "$(realityTargetCdnProviderFromCname d123.cloudfront.net.)" == "cloudfront" ]]
    [[ "$(realityTargetCdnProviderFromCname edge.fastly.net.)" == "fastly" ]]
    [[ "$(realityTargetCdnProviderFromCname a123.edgekey.net.)" == "akamai" ]]
    [[ "$(realityTargetCdnProviderFromAsn AS20940 "Akamai International")" == "akamai" ]]
    [[ "$(realityTargetCdnProviderFromAsn AS54113 "Fastly")" == "fastly" ]]
    ! realityTargetCdnProviderFromAsn AS16509 "Amazon.com"
    (
        dig() {
            [[ " $* " == *" CNAME "* ]] && printf 'd123.cloudfront.net.\n'
        }
        [[ "$(realityTargetDnsCdnProvider fresh.example.com)" == "cloudfront" ]]
    )
    ! realityTargetCandidates | grep -q '^www.cloudflare.com|'
    ! realityTargetCandidates | grep -q '^www.apple.com|'
    ! realityTargetCandidates | grep -q '^nodejs.org|'
    realityTargetCandidateBlocked "nodejs.org" cloudflare_relay
    realityTargetCandidateBlocked "www.nodejs.org" cloudflare_relay
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

runRealityProbeQueueRegression() (
    local queueRoot="${TMP_DIR}/reality-probe-queue" consumer cancelMode monitorMode writerPid workerPid retries rc oldResults monitorTraps
    mkdir -p "${queueRoot}/tmp"
    export TMPDIR="${queueRoot}/tmp"
    export PADM_REALITY_TARGET_RESULTS_FILE="${queueRoot}/results.tsv"
    export PADM_REALITY_TARGET_SCAN_FILE="${PADM_REALITY_TARGET_RESULTS_FILE}"
    export PADM_REALITY_SECONDARY_JOBS=2
    printf 'IP,ORIGIN,CERT_DOMAIN,CERT_ISSUER,GEO_CODE\n192.0.2.1,192.0.2.0/24,queue.example.com,Test CA,N/A\n' >"${queueRoot}/scanner.csv"
    oldResults=$(formatRealityTargetResultLine "queue.example.com:443" "queue.example.com" "Queue" "test" "no" \
        "192.0.2.1" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "original" "London, United Kingdom")
    realityTargetDetector() { printf 'fake-xray\n'; }
    currentRealityNetworkProfile() { printf '192.0.2.10\tunknown\tunknown\n'; }
    realityTargetRefreshRecords() { printf '%s\n' "${oldResults}"; }
    realityTargetProgressLine() { return 0; }
    realityTargetStatusBlock() { printf '%s\n' "$@" >>"${queueRoot}/status.log"; }
    cancelProbe() {
        printf '%s\n' "${BASHPID}" >>"${queueRoot}/workers"
        mktemp "${TMPDIR}/probe-download.XXXXXX" >/dev/null
        command sleep 30 &
        printf '%s\n' "$!" >>"${queueRoot}/workers"
        wait "$!"
    }
    probeRealityTargetRecord() {
        if [[ "${cancelMode}" != normal ]]; then cancelProbe; return; fi
        printf 'OK\t'
        formatRealityTargetResultLine "queue.example.com:443" "queue.example.com" "Queue" "test" "no" \
            "192.0.2.1" "AS64500" "ExampleNet" "$(realityTargetNetworkMatch "$3" "$4" AS64500 ExampleNet)" \
            "A" "yes" "4096" "yes" "1234567891" "updated"
    }
    probeRealityScannerCandidate() {
        if [[ "${cancelMode}" != normal ]]; then cancelProbe; return; fi
        [[ "$8" == 192.0.2.0/24 && -f "$9" ]]
        printf 'OK\t'
        formatRealityTargetResultLine "${3}:443" "$3" "$3" "scanner" "no" "$2" \
            "AS64500" "ExampleNet" "unknown" "A" "yes" "4096" "yes" "1234567891" "updated"
    }
    runProbeConsumer() {
        if [[ "${consumer}" == refresh ]]; then
            scanLocalAsnRealityTargets
        else
            importRealityScannerResults "${queueRoot}/scanner.csv" "unknown" "unknown"
        fi
    }
    for consumer in refresh scanner; do
        for cancelMode in term early; do
            printf '%s\n' "${oldResults}" >"${PADM_REALITY_TARGET_RESULTS_FILE}"
            : >"${queueRoot}/workers"
            rc=0
            (
                PADM_CLEANUP_PATHS=()
                PADM_CLEANUP_TRAP_INSTALLED=
                if [[ "${cancelMode}" == early ]]; then
                    set -T
                    trap 'if [[ "${BASH_COMMAND}" == '\''jobPids[jobIndex]=$!'\'' ]]; then trap - DEBUG; kill -TERM "${BASHPID}"; fi' DEBUG
                fi
                runProbeConsumer
            ) >"${queueRoot}/${consumer}-${cancelMode}.output" 2>&1 &
            writerPid=$!
            if [[ "${cancelMode}" == term ]]; then
                retries=0
                while [[ "$(wc -l <"${queueRoot}/workers")" -lt 2 && "${retries}" -lt 200 ]]; do
                    command sleep 0.01
                    retries=$((retries + 1))
                done
                [[ "$(wc -l <"${queueRoot}/workers")" -eq 2 ]]
                kill -TERM "${writerPid}"
            fi
            wait "${writerPid}" || rc=$?
            [[ "${rc}" == 143 ]]
            while IFS= read -r workerPid; do
                ! kill -0 "${workerPid}" 2>/dev/null
            done <"${queueRoot}/workers"
            [[ "$(<"${PADM_REALITY_TARGET_RESULTS_FILE}")" == "${oldResults}" ]]
            [[ -z "$(find "${queueRoot}/tmp" -mindepth 1 -print -quit)" ]]
        done
        cancelMode=normal
        padmInstallCleanupTrap
        for monitorMode in off on; do
            [[ "${monitorMode}" != on ]] || set -m
            monitorTraps=$(trap -p EXIT INT TERM)
            : >"${queueRoot}/status.log"
            runProbeConsumer >"${queueRoot}/${consumer}-${monitorMode}.output" 2>&1
            [[ "$(trap -p EXIT INT TERM)" == "${monitorTraps}" ]]
            if [[ "${monitorMode}" == on ]]; then
                [[ $- == *m* ]]
                set +m
            else
                [[ $- != *m* ]]
            fi
            ! grep -Eq '^\[[0-9]+\].*(Done|Terminated)' "${queueRoot}/${consumer}-${monitorMode}.output"
            [[ "$(realityTargetResultField "$(realityTargetResultLine queue.example.com:443)" 9)" == unknown ]]
            if [[ "${consumer}" == refresh ]]; then
                grep -qxF 'different_network: 0' "${queueRoot}/status.log"
                grep -qxF 'unknown: 1' "${queueRoot}/status.log"
            fi
            [[ -z "$(find "${queueRoot}/tmp" -mindepth 1 -print -quit)" ]]
        done
    done
)

runRealityConfigScannerRegression() {
    local scannerCandidatesFile="${TMP_DIR}/reality-config-scanner-candidates.txt"
    local oldCandidatesFile="${PADM_REALITY_TARGET_CANDIDATES_FILE:-}"
    local scannerLine refreshScannerLine sameAsnLine batchLinesFile failedTargetsFile emptyLinesFile scannerSummary sameAsnSummary seenDomainsFile endpointResult asnCacheFile asnCacheProfile asnLookupCount
    local asnLookupFile="${TMP_DIR}/reality-scanner-asn-lookups.log"
    local locationLookupFile="${TMP_DIR}/reality-scanner-location-lookups.log"
    local concurrencyDir="${TMP_DIR}/reality-scanner-concurrency"
    local refreshConcurrencyDir="${TMP_DIR}/reality-refresh-concurrency"
    local refreshTimeoutLog="${TMP_DIR}/reality-refresh-timeout.log"
    local maxConcurrency refreshMaxConcurrency
    local scannerImported scannerSkipped scannerA scannerB scannerC scannerFail
    runRegressionStep reality-config-probe-queue runRealityProbeQueueRegression
    cat >"${scannerCandidatesFile}" <<'EOF'
fail-auto.example.com|fail-auto.example.com|Fail Auto|global|large_site|unknown|1|yes|fixture failing candidate
fixture-fallback.example.com|fixture-fallback.example.com|Fixture Fallback|global|large_site|unknown|2|yes|fixture fallback candidate
EOF
    export PADM_REALITY_TARGET_CANDIDATES_FILE="${scannerCandidatesFile}"

    rm -f "${PADM_REALITY_TARGET_SCAN_FILE}" "${REALITY_TLS_PING_ARGS_FILE}" "${asnLookupFile}" "${refreshTimeoutLog}"
    mkdir -p "${refreshConcurrencyDir}"
    export REALITY_ASN_LOOKUP_ARGS_FILE="${asnLookupFile}"
    export PADM_REALITY_SECONDARY_JOBS=4
    (
        export PADM_REALITY_TARGET_RESULTS_FILE="${TMP_DIR}/reality-static-block-results.tsv"
        realityTargetDetector() { printf 'fake-xray\n'; }
        probeRealityTargetEndpoint() {
            printf 'no\t192.0.2.80\tAS64500\tExampleNet\tA\tyes\t4096\tyes\tstatic block fixture\n'
        }
        validateRealityTargetSelection manual "WWW.APPLE.COM:443" "WWW.APPLE.COM"
        ! validateRealityTargetSelection manual "WWW.IBM.COM:443" "WWW.IBM.COM"
        ! validateRealityTargetSelection manual "WWW.JAVA.COM:443" "WWW.JAVA.COM"
        ! validateRealityTargetSelection manual "WWW.NODEJS.ORG:443" "WWW.NODEJS.ORG"
        ! validateRealityTargetSelection manual "LOL.SECURE.DYN.RIOTCDN.NET:443" "LOL.SECURE.DYN.RIOTCDN.NET"
        probeRealityTargetEndpoint() {
            printf 'no\t192.0.2.81\tAS64500\tExampleNet\tINVALID\tno\tunknown\tyes\tinvalid score fixture\n'
        }
        ! validateRealityTargetSelection manual "invalid-score.example.com:443" "invalid-score.example.com"
    )
    validateRealityTargetSelection manual "manual-b.example.com:443" "manual-b.example.com"
    ! validateRealityTargetSelection auto "manual-b.example.com:443" "manual-b.example.com"
    validateRealityTargetSelection manual "manual-c.example.com:443" "manual-c.example.com"
    ! validateRealityTargetSelection auto "manual-c.example.com:443" "manual-c.example.com"
    ! validateRealityTargetSelection manual "fail.example.com:443" "fail.example.com"
    ! validateRealityTargetSelection manual "relay-asn.example.com:443" "relay-asn.example.com"
    ! validateRealityTargetSelection manual "relay-sni.example.com:443" "relay-sni.example.com"
    ! validateRealityTargetSelection manual "unknown-risk.example.com:443" "unknown-risk.example.com"
    ! validateRealityTargetSelection manual "multi-risk.example.com:443" "multi-risk.example.com"
    endpointResult=$(probeRealityTargetEndpoint fake-xray "multi-score.example.com:443" "multi-score.example.com")
    [[ "$(printf '%s\n' "${endpointResult}" | awk -F'\t' '{print $1 "\t" $2 "\t" $5 "\t" $7}')" == $'no\t198.51.100.53\tC\t2048' ]]
    [[ "$(printf '%s\n' "${endpointResult}" | awk -F'\t' '{print $9}')" == *"全部 3 个地址按最差评分聚合"* ]]
    endpointResult=$(probeRealityTargetEndpoint fake-xray "multi-risk.example.com:443" "multi-risk.example.com")
    [[ "$(printf '%s\n' "${endpointResult}" | awk -F'\t' '{print $1 "\t" $5}')" == $'cloudflare_relay\tC' ]]
    [[ "$(printf '%s\n' "${endpointResult}" | awk -F'\t' '{print $9}')" == *"全部 3 个地址按最差评分聚合"* ]]
    ! realityTargetResultLine "manual-b.example.com:443" >/dev/null
    ! realityTargetResultLine "manual-c.example.com:443" >/dev/null
    ! realityTargetResultLine "relay-asn.example.com:443" >/dev/null
    ! realityTargetResultLine "unknown-risk.example.com:443" >/dev/null
    (
        realityTargetDnsCdnProvider() { printf 'cloudfront\n'; }
        resolveRealityTargetAddresses() { printf '192.0.2.88\n'; }
        lookupRealityTargetAsnCached() { printf 'AS16509\tAmazon.com\n'; }
        endpointResult=$(probeRealityTargetEndpoint fake-xray "fresh-edge.example.com:443" "fresh-edge.example.com")
        [[ "$(printf '%s\n' "${endpointResult}" | awk -F'\t' '{print $1 "\t" $5}')" == $'cdn_edge\tA' ]]
        realityTargetDnsCdnProvider() { printf 'fastly\n'; }
        scannerRecord=$(probeRealityScannerCandidate fake-xray 192.0.2.89 fresh-fastly.example.com Fastly AS64500 ExampleNet)
        [[ "$(printf '%s\n' "${scannerRecord}" | awk -F'\t' '{print $1 "\t" $6}')" == $'OK\tcdn_edge' ]]
    )
    rm -f "${REALITY_TLS_PING_ARGS_FILE}" "${asnLookupFile}" "${refreshTimeoutLog}"
    export PADM_FAKE_XRAY_CONCURRENCY_DIR="${refreshConcurrencyDir}"
    timeout() {
        [[ "$1" == "-k" && "$2" == "2" && "$3" == "15" ]] || return 2
        printf '%s %s %s\n' "$1" "$2" "$3" >>"${refreshTimeoutLog}"
        shift 3
        "$@"
    }
    export REALITY_LOCATION_LOOKUP_ARGS_FILE="${locationLookupFile}"
    : >"${locationLookupFile}"
    scanLocalAsnRealityTargets
    [[ "$(wc -l <"${REALITY_TLS_PING_ARGS_FILE}" | tr -d ' ')" == "3" ]]
    asnLookupCount=$(wc -l <"${asnLookupFile}" | tr -d ' ')
    [[ "${asnLookupCount}" == "1" ]]
    [[ "$(wc -l <"${locationLookupFile}" | tr -d ' ')" == "1" ]]
    grep -qxF '192.0.2.1' "${locationLookupFile}"
    [[ "$(grep -cFx -- '-k 2 15' "${refreshTimeoutLog}")" == "3" ]]
    ! grep -qF $'fail-auto.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
    grep -qF $'fixture-fallback.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
    refreshMaxConcurrency=$(sort -nr "${refreshConcurrencyDir}/observed" | head -n 1)
    [[ "${refreshMaxConcurrency}" -ge 2 && "${refreshMaxConcurrency}" -le 4 ]]
    writeRealityTargetResultLine "refresh-scanner.example.com:8443" "sni.refresh-scanner.example.com" "Refresh Scanner" "scanner" "no" "198.51.100.20" "AS64501" "RemoteNet" "different_network" "A" "yes" "4096" "yes" "1234567890" "RealiTLScanner: Fixture CA; old result"
    writeRealityTargetResultLine "refresh-network-fail.example.com:443" "refresh-network-fail.example.com" "Refresh Network Fail" "test" "no" "198.51.100.21" "AS64501" "RemoteNet" "different_network" "A" "yes" "4096" "yes" "1234567890" "stale A fixture"
    resolveRealityTargetAddresses() {
        [[ "$1" == "refresh-network-fail.example.com" ]] && return 1
        printf '192.0.2.1\n'
    }
    rm -f "${REALITY_TLS_PING_ARGS_FILE}" "${asnLookupFile}" "${refreshTimeoutLog}"
    : >"${locationLookupFile}"
    scanLocalAsnRealityTargets
    [[ "$(wc -l <"${REALITY_TLS_PING_ARGS_FILE}" | tr -d ' ')" == "5" ]]
    grep -qxF "tls ping -ip 192.0.2.1 fixture-fallback.example.com:443" "${REALITY_TLS_PING_ARGS_FILE}"
    grep -qxF "tls ping -ip 192.0.2.1 sni.refresh-scanner.example.com:8443" "${REALITY_TLS_PING_ARGS_FILE}"
    grep -qxF "tls ping -ip 192.0.2.1 fail-auto.example.com:443" "${REALITY_TLS_PING_ARGS_FILE}"
    asnLookupCount=$(wc -l <"${asnLookupFile}" | tr -d ' ')
    [[ "${asnLookupCount}" == "1" ]]
    [[ "$(grep -cFx -- '-k 2 15' "${refreshTimeoutLog}")" == "5" ]]
    ! grep -qF $'refresh-network-fail.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
    refreshScannerLine=$(grep -F $'refresh-scanner.example.com:8443\tsni.refresh-scanner.example.com\tRefresh Scanner\tscanner\tno\t' "${PADM_REALITY_TARGET_SCAN_FILE}")
    [[ "$(realityTargetResultField "${refreshScannerLine}" 9)" == "same_asn" ]]
    [[ "$(realityTargetResultField "${refreshScannerLine}" 15)" == "RealiTLScanner: Fixture CA; TLS 1.3 + X25519MLKEM768 可用，证书链长度满足 Xray 要求" ]]
    [[ "$(realityTargetResultField "${refreshScannerLine}" 16)" == "Los Angeles, United States" ]]
    [[ ! -s "${locationLookupFile}" ]]
    resolveRealityTargetAddresses() { printf '192.0.2.1\n'; }
    unset -f timeout
    unset REALITY_ASN_LOOKUP_ARGS_FILE REALITY_LOCATION_LOOKUP_ARGS_FILE PADM_FAKE_XRAY_CONCURRENCY_DIR PADM_REALITY_SECONDARY_JOBS

    (
        local rollingDir="${TMP_DIR}/reality-refresh-rolling"
        local rollingProgressLog="${rollingDir}/progress.log"
        mkdir -p "${rollingDir}"
        rm -f "${rollingDir}/slow-active" "${rollingDir}/ninth-started" "${rollingDir}/rolling-observed" \
            "${rollingProgressLog}" "${rollingDir}/results.tsv"
        export PADM_REALITY_TARGET_RESULTS_FILE="${rollingDir}/results.tsv"
        export PADM_REALITY_TARGET_SCAN_FILE="${PADM_REALITY_TARGET_RESULTS_FILE}"
        unset PADM_REALITY_SECONDARY_JOBS
        realityTargetRefreshRecords() {
            local fixtureIndex
            for ((fixtureIndex = 0; fixtureIndex < 9; fixtureIndex++)); do
                formatRealityTargetResultLine "rolling-${fixtureIndex}.example.com:443" "rolling-${fixtureIndex}.example.com" \
                    "Rolling ${fixtureIndex}" "test" "no" "192.0.2.${fixtureIndex}" "AS64500" "ExampleNet" \
                    "same_asn" "A" "yes" "4096" "yes" "1234567890" "rolling fixture"
            done
        }
        realityTargetProgressLine() { printf '%s\n' "$*" >>"${rollingProgressLog}"; }
        probeRealityTargetRecord() {
            local record=$2 target sni name category _rest attempt
            IFS=$'\t' read -r target sni name category _rest <<<"${record}"
            case "${target}" in
            rolling-0.example.com:443)
                : >"${rollingDir}/slow-active"
                for ((attempt = 0; attempt < 10; attempt++)); do
                    if [[ -f "${rollingDir}/ninth-started" ]]; then
                        : >"${rollingDir}/rolling-observed"
                        break
                    fi
                    command sleep 0.01
                done
                command rm -f "${rollingDir}/slow-active"
                ;;
            rolling-8.example.com:443)
                : >"${rollingDir}/ninth-started"
                [[ -f "${rollingDir}/slow-active" ]] && : >"${rollingDir}/rolling-observed"
                ;;
            *)
                for ((attempt = 0; attempt < 10; attempt++)); do
                    [[ -f "${rollingDir}/slow-active" ]] && break
                    command sleep 0.01
                done
                ;;
            esac
            printf 'OK\t'
            formatRealityTargetResultLine "${target}" "${sni}" "${name}" "${category}" "no" "192.0.2.1" \
                "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "rolling fixture"
        }
        scanLocalAsnRealityTargets >/dev/null
        grep -qF '并发：8' "${rollingProgressLog}"
        [[ -f "${rollingDir}/rolling-observed" ]]
        [[ "$(wc -l <"${PADM_REALITY_TARGET_RESULTS_FILE}" | tr -d ' ')" == "9" ]]
    )

    (
        local rollingDir="${TMP_DIR}/reality-scanner-rolling"
        local rollingCsv="${rollingDir}/scanner.csv"
        local rollingProgressLog="${rollingDir}/progress.log"
        local fixtureIndex
        mkdir -p "${rollingDir}"
        rm -f "${rollingDir}/slow-active" "${rollingDir}/ninth-started" "${rollingDir}/rolling-observed" \
            "${rollingProgressLog}" "${rollingDir}/results.tsv" "${rollingCsv}"
        export PADM_REALITY_TARGET_RESULTS_FILE="${rollingDir}/results.tsv"
        export PADM_REALITY_TARGET_SCAN_FILE="${PADM_REALITY_TARGET_RESULTS_FILE}"
        unset PADM_REALITY_SECONDARY_JOBS
        printf 'IP,ORIGIN,CERT_DOMAIN,CERT_ISSUER,GEO_CODE\n' >"${rollingCsv}"
        for ((fixtureIndex = 0; fixtureIndex < 9; fixtureIndex++)); do
            printf '192.0.2.%s,192.0.2.0/24,rolling-scanner-%s.example.com,Test CA,N/A\n' \
                "$((fixtureIndex + 1))" "${fixtureIndex}" >>"${rollingCsv}"
        done
        realityTargetProgressLine() { printf '%s\n' "$*" >>"${rollingProgressLog}"; }
        probeRealityScannerCandidate() {
            local ip=$2 domain=$3 attempt
            case "${domain}" in
            rolling-scanner-0.example.com)
                : >"${rollingDir}/slow-active"
                for ((attempt = 0; attempt < 10; attempt++)); do
                    if [[ -f "${rollingDir}/ninth-started" ]]; then
                        : >"${rollingDir}/rolling-observed"
                        break
                    fi
                    command sleep 0.01
                done
                command rm -f "${rollingDir}/slow-active"
                ;;
            rolling-scanner-8.example.com)
                : >"${rollingDir}/ninth-started"
                [[ -f "${rollingDir}/slow-active" ]] && : >"${rollingDir}/rolling-observed"
                ;;
            *)
                for ((attempt = 0; attempt < 10; attempt++)); do
                    [[ -f "${rollingDir}/slow-active" ]] && break
                    command sleep 0.01
                done
                ;;
            esac
            printf 'OK\t'
            formatRealityTargetResultLine "${domain}:443" "${domain}" "${domain}" "scanner" "no" "${ip}" \
                "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "rolling scanner fixture"
        }
        importRealityScannerResults "${rollingCsv}" "AS64500" "ExampleNet" >/dev/null
        grep -qF 'TLS/CDN 二次检测 0/9 并发：8' "${rollingProgressLog}"
        [[ -f "${rollingDir}/rolling-observed" ]]
        [[ "$(wc -l <"${PADM_REALITY_TARGET_RESULTS_FILE}" | tr -d ' ')" == "9" ]]
    )

    cat >"${TMP_DIR}/realitlscanner.csv" <<'CSV'
IP,ORIGIN,TLS,ALPN,CURVE,CERT_LENGTH,CERT_SIGNATURE,CERT_PUBLICKEY,CERT_DOMAIN,CERT_ISSUER,GEO_CODE
192.0.2.10,192.0.2.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,www.cloudflare.com,"Google Trust Services",N/A
198.51.100.11,198.51.100.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,scanner.example.com,"Let's Encrypt, Inc.",N/A
198.51.100.12,198.51.100.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,scanner.example.com,"Duplicate",N/A
198.51.100.13,198.51.100.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,scanner-two.example.com,"Let's Encrypt",N/A
198.51.100.14,198.51.100.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,scanner-three.example.com,"Let's Encrypt",N/A
198.51.100.15,198.51.100.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,scanner-four.example.com,"Let's Encrypt",N/A
198.51.100.16,198.51.100.0/24,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,scanner-five.example.com,"Let's Encrypt",N/A
198.51.100.254,198.51.100.128/25,TLS 1.3,h2,X25519,4096,ECDSA,ECDSA,scanner-unknown-asn.example.com,"Let's Encrypt",N/A
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
    asnCacheFile="${TMP_DIR}/reality-scanner-asn-cache.tsv"
    : >"${asnCacheFile}"
    asnCacheProfile=$(scannerRealityNetworkProfile "198.51.100.11" "AS64500" "ExampleNet" "198.51.100.0/24" "${asnCacheFile}")
    [[ "${asnCacheProfile}" == $'AS64501\tRemoteNet\tdifferent_network' ]]
    asnCacheProfile=$(scannerRealityNetworkProfile "198.51.100.12" "AS64500" "ExampleNet" "198.51.100.0/24" "${asnCacheFile}")
    [[ "${asnCacheProfile}" == $'AS64501\tRemoteNet\tdifferent_network' ]]
    asnCacheProfile=$(lookupRealityTargetAsnCached "198.51.100.11" "${asnCacheFile}")
    [[ "${asnCacheProfile}" == $'AS64501\tRemoteNet' ]]
    [[ "$(wc -l <"${asnLookupFile}" | tr -d ' ')" == "1" ]]
    grep -qxF '198.51.100.11' "${asnLookupFile}"
    (
        local singleflightDir="${TMP_DIR}/reality-asn-singleflight"
        local singleflightCache="${singleflightDir}/cache.tsv"
        local singleflightLookups="${singleflightDir}/lookups.log"
        local index pid
        local -a pids=()
        mkdir -p "${singleflightDir}"
        : >"${singleflightCache}"
        : >"${singleflightLookups}"
        lookupRealityTargetAsn() {
            printf '%s\n' "$1" >>"${singleflightLookups}"
            command sleep 0.1
            printf 'AS64501\tRemoteNet\n'
        }
        for ((index = 1; index <= 8; index++)); do
            lookupRealityTargetAsnCached "198.51.100.${index}" "${singleflightCache}" "198.51.100.0/24" >"${singleflightDir}/${index}.out" &
            pids+=("$!")
        done
        for pid in "${pids[@]}"; do
            wait "${pid}"
        done
        [[ "$(wc -l <"${singleflightLookups}" | tr -d ' ')" == "1" ]]
        for ((index = 1; index <= 8; index++)); do
            grep -qxF $'AS64501\tRemoteNet' "${singleflightDir}/${index}.out"
        done
    )
    rm -f "${asnLookupFile}"
    export PADM_FAKE_XRAY_CONCURRENCY_DIR="${concurrencyDir}"
    export PADM_REALITY_SECONDARY_JOBS=4
    export REALITY_LOCATION_LOOKUP_ARGS_FILE="${locationLookupFile}"
    : >"${locationLookupFile}"
    importRealityScannerResults "${TMP_DIR}/realitlscanner.csv" "AS64500" "ExampleNet" scannerSummary
    IFS=$'\t' read -r scannerImported scannerSkipped scannerA scannerB scannerC scannerFail <<<"${scannerSummary}"
    [[ "${scannerImported}" == "5" ]]
    [[ "${scannerSkipped}" == "10" ]]
    [[ "${scannerA}" == "5" ]]
    [[ "${scannerB}" == "0" ]]
    [[ "${scannerC}" == "0" ]]
    [[ "${scannerFail}" == "2" ]]
    [[ "$(wc -l <"${REALITY_TLS_PING_ARGS_FILE}" | tr -d ' ')" == "13" ]]
    [[ "$(grep -c 'scanner.example.com:443' "${REALITY_TLS_PING_ARGS_FILE}")" == "1" ]]
    [[ "$(grep -c 'cloudflare.com:443' "${REALITY_TLS_PING_ARGS_FILE}")" == "6" ]]
    grep -qxF 'tls ping -ip 198.51.100.254 cloudflare.com:443' "${REALITY_TLS_PING_ARGS_FILE}"
    asnLookupCount=$(wc -l <"${asnLookupFile}" | tr -d ' ')
    [[ "${asnLookupCount}" == "2" ]]
    ! grep -qxF '198.51.100.16' "${asnLookupFile}"
    ! grep -qx '198.51.100.17' "${asnLookupFile}"
    maxConcurrency=$(sort -nr "${concurrencyDir}/observed" | head -n 1)
    [[ "${maxConcurrency}" -ge 2 && "${maxConcurrency}" -le 4 ]]
    scannerLine=$(grep -F $'scanner.example.com:443\tscanner.example.com\tscanner.example.com\tscanner' "${PADM_REALITY_TARGET_SCAN_FILE}")
    [[ "$(realityTargetResultField "${scannerLine}" 7)" == "AS64501" ]]
    [[ "$(realityTargetResultField "${scannerLine}" 8)" == "RemoteNet" ]]
    [[ "$(realityTargetResultField "${scannerLine}" 9)" == "different_network" ]]
    [[ "$(realityTargetResultField "${scannerLine}" 15)" == *"RealiTLScanner: Let's Encrypt, Inc.;"* ]]
    [[ "$(realityTargetResultField "${scannerLine}" 16)" == "London, United Kingdom" ]]
    [[ "$(wc -l <"${locationLookupFile}" | tr -d ' ')" == "5" ]]
    grep -qxF '198.51.100.11' "${locationLookupFile}"
    ! grep -qxF '198.51.100.12' "${locationLookupFile}"
    ! grep -qxF '198.51.100.17' "${locationLookupFile}"
    ! grep -qF $'scanner-unknown-asn.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
    grep -qF $'scanner-five.example.com:443\tscanner-five.example.com' "${PADM_REALITY_TARGET_SCAN_FILE}"

    unset PADM_FAKE_XRAY_CONCURRENCY_DIR REALITY_LOCATION_LOOKUP_ARGS_FILE
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
    [[ "$(realityTargetResultField "${sameAsnLine}" 16)" == "Los Angeles, United States" ]]
    unset REALITY_ASN_LOOKUP_ARGS_FILE PADM_REALITY_SECONDARY_JOBS
    batchLinesFile="${TMP_DIR}/reality-batch-lines.tsv"
    failedTargetsFile="${TMP_DIR}/reality-failed-targets.txt"
    emptyLinesFile="${TMP_DIR}/reality-empty-lines.tsv"
    writeRealityTargetResultLine "batch-old.example.com:443" "old.example.com" "Old Batch" "test" "unknown" "192.0.2.20" "AS64500" "ExampleNet" "same_asn" "B" "yes" "4096" "yes" "1234567800" "old batch line"
    writeRealityTargetResultLine "single-drop.example.com:443" "single-drop.example.com" "Single Drop" "test" "no" "192.0.2.23" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567800" "old A line"
    writeRealityTargetResultLine "single-drop.example.com:443" "single-drop.example.com" "Single Drop" "test" "unknown" "192.0.2.23" "AS64500" "ExampleNet" "same_asn" "C" "no" "4096" "yes" "1234567801" "new C line"
    ! realityTargetResultLine "single-drop.example.com:443" >/dev/null
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
    ! realityTargetResultLine "batch-drop.example.com:443" >/dev/null
    ! grep -qF $'batch-c.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
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
    ! grep -qF $'hidden-c.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
    [[ "$(realityTargetFilterTitle all)" == "全部" ]]
    [[ "$(selectRealityTargetScanResultFilter <<<"2" 2>/dev/null)" == "same_asn" ]]
    ! realityTargetScanResultFilterMatches "C" "same_asn" "all" "test"
    local selectedScanTarget selectedScanSni
    if ! selectRealityTargetFromScanResults selectedScanTarget selectedScanSni <<<"1"; then
        return 1
    fi
    [[ "${selectedScanTarget}" == "local.example.com:443" ]]
    [[ "${selectedScanSni}" == "sni.local.example.com" ]]
    scanLine=$(grep -F $'local.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}")
    [[ "$(realityTargetResultField "${scanLine}" 1)" == "local.example.com:443" ]]
    selectDefaultRealityTarget
    [[ "${realityTargetHost}" == "local.example.com" ]]
    [[ "${realityTargetPort}" == "443" ]]
    [[ "${realitySNI}" == "sni.local.example.com" ]]
    rm -f "${PADM_REALITY_TARGET_SCAN_FILE}" "${REALITY_TLS_PING_ARGS_FILE}"
    unset AUTO_REALITY_SERVER_NAME
    unset PADM_REALITY_TARGET_CANDIDATES_FILE
    PADM_FAKE_XRAY_ONLY_HOST=www.libreoffice.org selectDefaultRealityTarget
    [[ "${realityTargetHost}" == "www.libreoffice.org" ]]
    [[ "${realityTargetPort}" == "443" ]]
    [[ "${realitySNI}" == "www.libreoffice.org" ]]
    grep -q "tls ping -ip 192.0.2.1 www.libreoffice.org:443" "${REALITY_TLS_PING_ARGS_FILE}"
    (
        export PADM_REALITY_TARGET_RESULTS_FILE="${TMP_DIR}/reality-singbox-openssl-results.tsv"
        export PADM_REALITY_TARGET_SCAN_FILE="${PADM_REALITY_TARGET_RESULTS_FILE}"
        export PADM_REALITY_TARGET_CANDIDATES_FILE="${TMP_DIR}/reality-singbox-openssl-candidates.tsv"
        printf '%s\n' 'openssl-c.example.com|openssl-c.example.com|OpenSSL C|global|large_site|unknown|1|yes|strict A fixture' >"${PADM_REALITY_TARGET_CANDIDATES_FILE}"
        rm -f "${PADM_REALITY_TARGET_RESULTS_FILE}"
        coreInstallType=2
        selectCoreType=
        PADM_REALITY_AUTO_PROBE_LIMIT=1
        realityTargetDetector() { return 1; }
        openssl() { return 0; }
        probeRealityTargetEndpoint() {
            printf 'no\t192.0.2.70\tAS64500\tExampleNet\tC\tno\tunknown\tyes\tOpenSSL TLS 1.3 fixture\n'
        }
        realityTargetHost=unchanged.example.com
        ! selectAutoRecommendedRealityTarget
        [[ "${realityTargetHost}" == "unchanged.example.com" ]]
        ! validateRealityTargetSelection auto "openssl-c.example.com:443" "openssl-c.example.com"
        realityTargetDetector() { printf 'fake-xray\n'; }
        ! selectAutoRecommendedRealityTarget
        [[ "${realityTargetHost}" == "unchanged.example.com" ]]
        ! validateRealityTargetSelection auto "openssl-c.example.com:443" "openssl-c.example.com"
        ! realityTargetResultLine "openssl-c.example.com:443" >/dev/null
    )
    if [[ -n "${oldCandidatesFile}" ]]; then
        export PADM_REALITY_TARGET_CANDIDATES_FILE="${oldCandidatesFile}"
    else
        unset PADM_REALITY_TARGET_CANDIDATES_FILE
    fi
    unset PADM_FAKE_XRAY_ONLY_HOST
}

runRealityLibraryUpdateRollbackRegression() (
    local root="${TMP_DIR}/reality-library-update-rollback" oldResults oldCandidates consumer mergeCalls=0 failCandidateWrite
    mkdir -p "${root}/tmp"
    export TMPDIR="${root}/tmp"
    export PADM_REALITY_TARGET_RESULTS_FILE="${root}/results.tsv"
    export PADM_REALITY_TARGET_SCAN_FILE="${PADM_REALITY_TARGET_RESULTS_FILE}"
    export PADM_REALITY_TARGET_CANDIDATES_FILE="${root}/candidates.tsv"
    oldResults=$(
        formatRealityTargetResultLine "remove.example.com:443" "remove.example.com" "Remove" "test" "no" \
            "192.0.2.1" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "old remove" "London, United Kingdom"
        formatRealityTargetResultLine "keep.example.com:443" "keep.example.com" "Keep" "test" "no" \
            "192.0.2.2" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "old keep" "London, United Kingdom"
    )
    oldCandidates=$'remove.example.com|remove.example.com|Remove|global|test|unknown|1|yes|fixture\nkeep.example.com|keep.example.com|Keep|global|test|unknown|2|yes|fixture'
    printf 'IP,ORIGIN,CERT_DOMAIN,CERT_ISSUER,GEO_CODE\n192.0.2.1,192.0.2.0/24,remove.example.com,Test CA,N/A\n192.0.2.2,192.0.2.0/24,keep.example.com,Test CA,N/A\n' >"${root}/scanner.csv"
    realityTargetDetector() { printf 'fake-xray\n'; }
    currentRealityNetworkProfile() { printf '192.0.2.10\tAS64500\tExampleNet\n'; }
    realityTargetRefreshRecords() { printf '%s\n' "${oldResults}"; }
    realityTargetProgressLine() { :; }
    realityTargetStatusBlock() { :; }
    libraryFixtureProbe() {
        if [[ "$1" == remove.example.com:443 ]]; then
            printf 'FAIL\t%s\n' "$1"
            return 0
        fi
        printf 'OK\t'
        formatRealityTargetResultLine "keep.example.com:443" "keep.example.com" "Keep" "test" "no" \
            "192.0.2.2" "AS64500" "ExampleNet" "same_asn" "A" "yes" "8192" "yes" "1234567891" "new keep" "London, United Kingdom"
    }
    probeRealityTargetRecord() { libraryFixtureProbe "${2%%$'\t'*}"; }
    probeRealityScannerCandidate() { libraryFixtureProbe "${3}:443"; }
    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/libraryOriginalCommitGeneratedFile/')"
    eval "$(declare -f writeRealityTargetResultLines | sed '1s/^writeRealityTargetResultLines/libraryOriginalWriteRealityTargetResultLines/')"
    commitGeneratedFile() {
        if [[ "$2" == "${PADM_REALITY_TARGET_CANDIDATES_FILE}" && "${failCandidateWrite}" == true ]]; then
            failCandidateWrite=false
            return 1
        fi
        libraryOriginalCommitGeneratedFile "$@"
    }
    writeRealityTargetResultLines() {
        mergeCalls=$((mergeCalls + 1))
        libraryOriginalWriteRealityTargetResultLines "$@"
    }
    for consumer in refresh scanner; do
        printf '%s\n' "${oldResults}" >"${PADM_REALITY_TARGET_RESULTS_FILE}"
        printf '%s\n' "${oldCandidates}" >"${PADM_REALITY_TARGET_CANDIDATES_FILE}"
        mergeCalls=0
        failCandidateWrite=true
        if [[ "${consumer}" == refresh ]]; then
            regressionExpectStatus 1 scanLocalAsnRealityTargets
        else
            regressionExpectStatus 1 importRealityScannerResults "${root}/scanner.csv" AS64500 ExampleNet
        fi
        [[ "${mergeCalls}" == 1 && "${failCandidateWrite}" == false ]]
        [[ "$(<"${PADM_REALITY_TARGET_RESULTS_FILE}")" == "${oldResults}" ]]
        [[ "$(<"${PADM_REALITY_TARGET_CANDIDATES_FILE}")" == "${oldCandidates}" ]]
        [[ -z "$(find "${root}/tmp" -mindepth 1 -print -quit)" ]]
    done
)

runRealityUnifiedLibraryRollbackRegression() (
    runRegressionStep reality-library-update-rollback runRealityLibraryUpdateRollbackRegression
    local rootRel="${TMP_DIR}/reality-unified-library-rollback"
    local root resultsFile candidatesFile targetsFile
    local oldResultsFile="${PADM_REALITY_TARGET_RESULTS_FILE:-}"
    local oldScanFile="${PADM_REALITY_TARGET_SCAN_FILE:-}"
    local oldCandidatesFile="${PADM_REALITY_TARGET_CANDIDATES_FILE:-}"
    local oldResults oldCandidates failCandidateWrite=true

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    resultsFile="${root}/reality_targets_results.tsv"
    candidatesFile="${root}/reality_candidates.tsv"
    targetsFile="${root}/remove-targets.txt"
    export PADM_REALITY_TARGET_RESULTS_FILE="${resultsFile}"
    export PADM_REALITY_TARGET_SCAN_FILE="${resultsFile}"
    export PADM_REALITY_TARGET_CANDIDATES_FILE="${candidatesFile}"

    {
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "remove.example.com:443" "remove.example.com" "Remove Example" "scanner" "unknown" "192.0.2.10" "AS64500" "ExampleNet" "same_asn" "unknown" "yes" "4096" "yes" "1234567890" "remove line"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "keep.example.com:443" "keep.example.com" "Keep Example" "scanner" "no" "192.0.2.11" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567891" "keep line"
    } >"${resultsFile}"
    {
        printf '%s\n' 'remove.example.com|remove.example.com|Remove Example|global|scanner|unknown|9|yes|remove candidate'
        printf '%s\n' 'keep.example.com|keep.example.com|Keep Example|global|scanner|unknown|10|yes|keep candidate'
    } >"${candidatesFile}"
    printf '%s\n' 'remove.example.com:443' >"${targetsFile}"
    oldResults=$(<"${resultsFile}")
    oldCandidates=$(<"${candidatesFile}")

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${candidatesFile}" && "${failCandidateWrite}" == true ]]; then
            failCandidateWrite=false
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    regressionExpectStatus 1 removeRealityTargetsFromUnifiedLibrary "${targetsFile}" >/dev/null 2>&1
    [[ "$(<"${resultsFile}")" == "${oldResults}" ]]
    [[ "$(<"${candidatesFile}")" == "${oldCandidates}" ]]
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
    grep -qF $'keep.example.com:443\t' "${resultsFile}"
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
    local realityPatchXrayGrpc="${realityPatchDir}/xray/08_VLESS_vision_gRPC_inbounds.json"
    local realityPatchXrayXhttp="${realityPatchDir}/xray/12_VLESS_XHTTP_inbounds.json"
    local realityPatchSingBoxVision="${realityPatchDir}/sing-box/07_VLESS_vision_reality_inbounds.json"
    local realityPatchSingBoxGrpc="${realityPatchDir}/sing-box/08_VLESS_vision_gRPC_inbounds.json"
    local realityPatchOriginal realityPatchXhttpHost realityPatchVisionUnchanged
    mkdir -p "${realityPatchDir}/xray" "${realityPatchDir}/sing-box"
    cat >"${realityPatchXrayVision}" <<'JSON'
{
  "inbounds": [
    {"tag":"dokodemo-in","protocol":"dokodemo-door","port":2443,
     "settings":{"address":"127.0.0.1","port":45987,"network":"tcp"}},
    {"listen":"127.0.0.1","port":45987,"settings":{"clients":[{"id":"keep-id"}]},
     "streamSettings":{"realitySettings":{"target":"old.example.com:443","serverNames":["old.example.com"],"shortIds":["keep-short-id"]}}}
  ],
  "routing": {"marker":"keep","rules":[
    {"inboundTag":["dokodemo-in"],"domain":["old.example.com","other.example.com"],"outboundTag":"z_direct_outbound","network":"tcp"},
    {"inboundTag":["dokodemo-in"],"outboundTag":"blackhole_out"},
    {"inboundTag":["other-in"],"domain":["old.example.com"],"outboundTag":"z_direct_outbound"},
    {"inboundTag":["dokodemo-in"],"domain":["old.example.com"],"outboundTag":"custom-out"},
    {"inboundTag":["dokodemo-in"],"domain":["full:old.example.com"],"outboundTag":"z_direct_outbound"}
  ]}
}
JSON
    realityPatchVisionUnchanged=$(jq -c 'del(.inbounds[1].streamSettings.realitySettings.target,
        .inbounds[1].streamSettings.realitySettings.serverNames, .routing.rules[0].domain[0])' "${realityPatchXrayVision}") || return 1
    jq -n '{inbounds: [{streamSettings: {realitySettings: {target: "old.example.com:443", serverNames: ["old.example.com"]}}}]}' >"${realityPatchXrayGrpc}"
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
    export PADM_REALITY_XRAY_GRPC_CONFIG_FILE="${realityPatchXrayGrpc}"
    export PADM_REALITY_XRAY_XHTTP_CONFIG_FILE="${realityPatchXrayXhttp}"
    export PADM_REALITY_SINGBOX_VISION_CONFIG_FILE="${realityPatchSingBoxVision}"
    export PADM_REALITY_SINGBOX_GRPC_CONFIG_FILE="${realityPatchSingBoxGrpc}"
    applyRealityTargetToInstalledConfigs "new.example.com:8443" "sni.example.com"
    jq -e '.inbounds[1].streamSettings.realitySettings.target == "new.example.com:8443" and .inbounds[1].streamSettings.realitySettings.serverNames == ["sni.example.com"]' "${realityPatchXrayVision}" >/dev/null
    # 前端只替换旧 SNI 精确元素，保留其它域名、无关规则、兜底和用户监听。
    jq -e '.routing.rules[0].domain == ["sni.example.com","other.example.com"]' "${realityPatchXrayVision}" >/dev/null || return 1
    [[ "$(jq -c 'del(.inbounds[1].streamSettings.realitySettings.target,
        .inbounds[1].streamSettings.realitySettings.serverNames, .routing.rules[0].domain[0])' "${realityPatchXrayVision}")" == "${realityPatchVisionUnchanged}" ]] || return 1
    jq -e '.inbounds[0].streamSettings.realitySettings.target == "new.example.com:8443" and .inbounds[0].streamSettings.realitySettings.serverNames == ["sni.example.com"]' "${realityPatchXrayGrpc}" >/dev/null
    [[ "${xrayVLESSRealityGRPCSNI}" == sni.example.com ]]
    jq -e '.inbounds[0].streamSettings.realitySettings.target == "new.example.com:8443" and .inbounds[0].streamSettings.xhttpSettings.host == "sni.example.com"' "${realityPatchXrayXhttp}" >/dev/null
    jq -e '.inbounds[0].tls.server_name == "sni.example.com" and .inbounds[0].tls.reality.handshake.server == "new.example.com" and .inbounds[0].tls.reality.handshake.server_port == 8443' "${realityPatchSingBoxVision}" >/dev/null
    jq -e '.inbounds[0].tls.server_name == "sni.example.com" and .inbounds[0].tls.reality.handshake.server == "new.example.com" and .inbounds[0].tls.reality.handshake.server_port == 8443' "${realityPatchSingBoxGrpc}" >/dev/null
    for realityPatchXhttpHost in custom.example.com ''; do
        updateRoutingJsonConfig "${realityPatchXrayXhttp}" \
            '.inbounds[0].streamSettings.xhttpSettings.host = $host' --arg host "${realityPatchXhttpHost}" || return 1
        applyRealityTargetToInstalledConfigs "host.example.com:9443" "host-sni.example.com" || return 1
        jq -e --arg host "${realityPatchXhttpHost}" \
            '.inbounds[0].streamSettings.realitySettings.target == "host.example.com:9443" and
                .inbounds[0].streamSettings.realitySettings.serverNames == ["host-sni.example.com"] and
                .inbounds[0].streamSettings.xhttpSettings.host == $host' "${realityPatchXrayXhttp}" >/dev/null || return 1
    done
    (
        # 同身份下行跟随 SNI；仅跟随主 SNI 的 host 同步，独立身份保持原值。
        local identity downloadKey downloadSNI downloadHost expectedSNI expectedHost absentHost
        for identity in shared independent-key independent-sni independent-host absent-host; do
            downloadKey=shared-public downloadSNI=old.example.com downloadHost=old.example.com
            expectedSNI=download-sni.example.com expectedHost=${downloadHost} absentHost=false
            case "${identity}" in
            shared) expectedHost=download-sni.example.com ;;
            independent-key) downloadKey=independent-public; expectedSNI=${downloadSNI} ;;
            independent-sni) downloadSNI=independent.example.com; expectedSNI=${downloadSNI} ;;
            independent-host) downloadHost=independent-host.example.com; expectedHost=${downloadHost} ;;
            absent-host) absentHost=true ;;
            esac
            updateRoutingJsonConfig "${realityPatchXrayXhttp}" '
                .inbounds[0].streamSettings.realitySettings.publicKey = "shared-public" |
                .inbounds[0].streamSettings.realitySettings.serverNames = ["old.example.com"] |
                .inbounds[0].streamSettings.xhttpSettings.host = "old.example.com" |
                .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings =
                    {address:"download.example.com",realitySettings:{publicKey:$key,serverName:$sni},
                     xhttpSettings:(if $absentHost then {} else {host:$host} end)}' \
                --arg key "${downloadKey}" --arg sni "${downloadSNI}" --arg host "${downloadHost}" \
                --argjson absentHost "${absentHost}" || return 1
            applyRealityTargetToInstalledConfigs "download-target.example.com:443" "download-sni.example.com" || return 1
            jq -e --arg key "${downloadKey}" --arg sni "${expectedSNI}" --arg host "${expectedHost}" \
                --argjson absentHost "${absentHost}" '
                .inbounds[0].streamSettings.realitySettings.serverNames == ["download-sni.example.com"] and
                .inbounds[0].streamSettings.xhttpSettings.host == "download-sni.example.com" and
                .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.address == "download.example.com" and
                .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.realitySettings.publicKey == $key and
                .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.realitySettings.serverName == $sni and
                (if $absentHost
                 then (.inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.xhttpSettings | has("host") | not)
                 else .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.xhttpSettings.host == $host end)' \
                "${realityPatchXrayXhttp}" >/dev/null || return 1
        done
    ) || return 1
    realityPatchOriginal=$(<"${realityPatchSingBoxVision}")
    if applyRealityTargetToInstalledConfigs "new.example.com:not-a-port" "sni.example.com" 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${realityPatchSingBoxVision}")" == "${realityPatchOriginal}" ]]
    [[ ! -e "${realityPatchXrayVision}.tmp" ]]
    [[ ! -e "${realityPatchXrayGrpc}.tmp" ]]
    [[ ! -e "${realityPatchXrayXhttp}.tmp" ]]
    [[ ! -e "${realityPatchSingBoxVision}.tmp" ]]
    [[ ! -e "${realityPatchSingBoxGrpc}.tmp" ]]
    (
        # 自定义目录无尾斜杠时仍定位真实分片；显式文件覆盖优先级不变。
        local singBoxConfigPath= PADM_SINGBOX_CONFIG_DIR="${realityPatchDir}/sing-box" suffix
        unset PADM_REALITY_SINGBOX_VISION_CONFIG_FILE PADM_REALITY_SINGBOX_GRPC_CONFIG_FILE
        for suffix in '' /; do
            PADM_SINGBOX_CONFIG_DIR="${realityPatchDir}/sing-box${suffix}"
            [[ "$(realitySingBoxVisionConfigPath)" == "${realityPatchSingBoxVision}" ]] || return 1
            [[ "$(realitySingBoxGrpcConfigPath)" == "${realityPatchSingBoxGrpc}" ]] || return 1
            applyRealityTargetToInstalledConfigs "directory.example.com:9443" "directory-sni.example.com" || return 1
            jq -e '.inbounds[0].tls.server_name == "directory-sni.example.com" and
                .inbounds[0].tls.reality.handshake.server == "directory.example.com"' \
                "${realityPatchSingBoxVision}" "${realityPatchSingBoxGrpc}" >/dev/null || return 1
        done
        singBoxConfigPath="${realityPatchDir}/sing-box"
        PADM_SINGBOX_CONFIG_DIR="${realityPatchDir}/ignored"
        [[ "$(realitySingBoxVisionConfigPath)" == "${realityPatchSingBoxVision}" ]] || return 1
        PADM_REALITY_SINGBOX_VISION_CONFIG_FILE="${realityPatchDir}/explicit.json"
        [[ "$(realitySingBoxVisionConfigPath)" == "${PADM_REALITY_SINGBOX_VISION_CONFIG_FILE}" ]] || return 1
    ) || return 1
    (
        local grpcRoot="${realityPatchDir}/grpc-only"
        local reloadCalls=0 refreshCalls=0
        mkdir -p "${grpcRoot}"
        PADM_REALITY_XRAY_VISION_CONFIG_FILE="${grpcRoot}/missing-vision.json"
        PADM_REALITY_XRAY_XHTTP_CONFIG_FILE="${grpcRoot}/missing-xhttp.json"
        PADM_REALITY_SINGBOX_VISION_CONFIG_FILE="${grpcRoot}/missing-singbox-vision.json"
        PADM_REALITY_SINGBOX_GRPC_CONFIG_FILE="${grpcRoot}/missing-singbox-grpc.json"
        PADM_REALITY_XRAY_GRPC_CONFIG_FILE="${grpcRoot}/08_VLESS_vision_gRPC_inbounds.json"
        jq -n '{inbounds: [{streamSettings: {realitySettings: {target: "old.example.com:443", serverNames: ["old-grpc.example.com"]}}}]}' >"${PADM_REALITY_XRAY_GRPC_CONFIG_FILE}"
        export REALITY_GRPC_VALIDATION_ARGS_FILE="${grpcRoot}/validate.args"
        export REALITY_GRPC_VALIDATION_STATUS=1
        cat >"${grpcRoot}/xray-test" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${REALITY_GRPC_VALIDATION_ARGS_FILE}"
exit "${REALITY_GRPC_VALIDATION_STATUS}"
EOF
        chmod +x "${grpcRoot}/xray-test"
        coreXrayBinaryPath() { printf '%s\n' "${grpcRoot}/xray-test"; }
        coreXrayConfigDir() { printf '%s\n' "${grpcRoot}"; }
        validateRealityTargetSelection() { :; }
        realityTargetStatusBlock() { :; }
        refreshSubscriptionsAfterRealityTargetChange() { refreshCalls=$((refreshCalls + 1)); }
        reloadCore() { reloadCalls=$((reloadCalls + 1)); [[ "${reloadCalls}" -gt 1 ]]; }
        realityTargetHost=old.example.com
        realityTargetPort=443
        realitySNI=old-grpc.example.com
        xrayVLESSRealityGRPCSNI=old-grpc.example.com
        regressionExpectStatus 1 changeInstalledRealityTarget "new.example.com:8443" "new-grpc.example.com"
        grep -qxF -- "-test -confdir ${grpcRoot}" "${REALITY_GRPC_VALIDATION_ARGS_FILE}"
        [[ "${reloadCalls}" == 0 && "${refreshCalls}" == 0 ]]
        [[ "${realitySNI}" == old-grpc.example.com && "${xrayVLESSRealityGRPCSNI}" == old-grpc.example.com ]]
        jq -e '.inbounds[0].streamSettings.realitySettings.target == "old.example.com:443" and .inbounds[0].streamSettings.realitySettings.serverNames == ["old-grpc.example.com"]' "${PADM_REALITY_XRAY_GRPC_CONFIG_FILE}" >/dev/null
        REALITY_GRPC_VALIDATION_STATUS=0
        regressionExpectStatus 1 changeInstalledRealityTarget "new.example.com:8443" "new-grpc.example.com"
        [[ "${reloadCalls}" == 2 && "${refreshCalls}" == 0 ]]
        [[ "${realitySNI}" == old-grpc.example.com && "${xrayVLESSRealityGRPCSNI}" == old-grpc.example.com ]]
        jq -e '.inbounds[0].streamSettings.realitySettings.target == "old.example.com:443" and .inbounds[0].streamSettings.realitySettings.serverNames == ["old-grpc.example.com"]' "${PADM_REALITY_XRAY_GRPC_CONFIG_FILE}" >/dev/null
        reloadCore() { return 0; }
        changeInstalledRealityTarget "new.example.com:8443" "new-grpc.example.com"
        [[ "${refreshCalls}" == 1 && "${xrayVLESSRealityGRPCSNI}" == new-grpc.example.com ]]
        jq -e '.inbounds[0].streamSettings.realitySettings.target == "new.example.com:8443" and .inbounds[0].streamSettings.realitySettings.serverNames == ["new-grpc.example.com"]' "${PADM_REALITY_XRAY_GRPC_CONFIG_FILE}" >/dev/null
    )
    unset PADM_REALITY_XRAY_VISION_CONFIG_FILE PADM_REALITY_XRAY_GRPC_CONFIG_FILE PADM_REALITY_XRAY_XHTTP_CONFIG_FILE PADM_REALITY_SINGBOX_VISION_CONFIG_FILE PADM_REALITY_SINGBOX_GRPC_CONFIG_FILE
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
        [[ "${PADM_SKIP_CONTROLLER_REFRESH:-}" != "1" ]] || return 98
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

    regressionExpectStatus 1 changeInstalledRealityTarget "new.example.com:8443" ""
    [[ "${reloadCalls}" == "1" ]]
    [[ "${refreshCalls}" == "1" ]]
    [[ "$(jq -r '.inbounds[1].streamSettings.realitySettings.target' "${xrayVision}")" == "new.example.com:8443" ]]
    [[ "$(jq -r '.inbounds[1].streamSettings.realitySettings.serverNames[0]' "${xrayVision}")" == "new.example.com" ]]
    [[ "${realityTargetHost}" == "new.example.com" ]]
    [[ "${realityTargetPort}" == "8443" ]]
    [[ "${realitySNI}" == "new.example.com" ]]
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
    reloadXrayProtocolCore() { return 0; }
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

runRealityStreamSplitRegression() (
    local mode=${1:-all} root="${TMP_DIR}/reality-stream-split" failKey= defaultChoice=1
    # 隔离容器自带的 /usr/sbin/nginx，安装状态只由下方函数模拟。
    local PATH=/usr/local/bin:/usr/bin:/bin
    local configPath="${root}/ports/" aliasFile aliasXHTTPFile ignoredFile ignoredContent oldAlias oldXHTTPAlias
    local visionPort=2443 xhttpPort=2444 websitePortInput=8443
    local backupCalls=0 patchCalls=0 allowCalls=0 reloadCalls=0 installCalls=0 subscribeCalls=0
    local reloadShouldFail=false subscribeReadStatus=0 key oldVision oldXHTTP oldNginx oldState oldStream
    export PADM_REALITY_STREAM_STATE_FILE="${root}/state.json" \
        PADM_REALITY_STREAM_CONF_FILE="${root}/stream.d/padm-reality.conf" \
        PADM_REALITY_STREAM_NGINX_CONF="${root}/nginx.conf" \
        PADM_REALITY_STREAM_VISION_CONFIG_FILE="${root}/vision.json" \
        PADM_REALITY_STREAM_XHTTP_CONFIG_FILE="${root}/xhttp.json"
    export TMPDIR="${root}/tmp"
    mkdir -p "${TMPDIR}"
    mkdir -p "${configPath}"
    rm -f "${PADM_REALITY_STREAM_STATE_FILE}" "${PADM_REALITY_STREAM_CONF_FILE}" "${root}/install-called"
    printf '%s\n' '{"inbounds":[{"port":443,"settings":{"marker":"vision"}},{"port":12345}]}' >"${PADM_REALITY_STREAM_VISION_CONFIG_FILE}"
    printf '%s\n' '{"inbounds":[{"listen":"0.0.0.0","port":9443,"settings":{"marker":"xhttp"}}]}' >"${PADM_REALITY_STREAM_XHTTP_CONFIG_FILE}"
    printf 'events {}\nhttp {}\n' >"${PADM_REALITY_STREAM_NGINX_CONF}"
    coreInstallType=1
    currentInstallProtocolType=",1,2,"
    unset AUTO_INSTALL

    eval "$(declare -f backupRealityStreamState | sed '1s/^backupRealityStreamState/streamOriginalBackupRealityStreamState/')"
    eval "$(declare -f realityStreamPatchXrayConfig | sed '1s/^realityStreamPatchXrayConfig/streamOriginalPatchXrayConfig/')"
    backupRealityStreamState() { backupCalls=$((backupCalls + 1)); streamOriginalBackupRealityStreamState "$@"; }
    realityStreamPatchXrayConfig() { patchCalls=$((patchCalls + 1)); streamOriginalPatchXrayConfig "$@"; }
    realityStreamNginxSupportsStream() { return 0; }
    realityStreamWarnPublic443Status() { :; }
    realityStreamWarnWebsiteDomainResolve() { :; }
    realityStreamWarnWebsiteBackend() { :; }
    realityStreamXrayBinary() { printf '/bin/true\n'; }
    realityStreamXrayConfDir() { printf '%s\n' "${root}"; }
    nginx() { return 0; }
    installNginxTools() { installCalls=$((installCalls + 1)); : >"${root}/install-called"; return 0; }
    allowPort() { allowCalls=$((allowCalls + 1)); PADM_LAST_ALLOW_PORT_ADDED=false; }
    reloadCore() { reloadCalls=$((reloadCalls + 1)); [[ "${reloadShouldFail}" != true ]]; }
    nginxRunning() { return 1; }
    menuLine() { printf '%s\n' "$*" >>"${root}/status.log"; }
    serviceQueueRefresh() { :; }
    (
        local snapshot damage
        for damage in missing dir; do
            padmCreateTempPath snapshot -d "$(realityStreamEnableBackupTemplate)" || return 1
            backupRealityStreamState "${snapshot}" || return 1
            printf 'current vision\n' >"${PADM_REALITY_STREAM_VISION_CONFIG_FILE}"
            rm -f -- "${snapshot}/vision.json"
            [[ "${damage}" != dir ]] || mkdir "${snapshot}/vision.json"
            regressionExpectStatus 1 realityStreamRollback "${snapshot}" || return 1
            [[ "$(<"${PADM_REALITY_STREAM_VISION_CONFIG_FILE}")" == 'current vision' ]] || return 1
            removeRealityStreamBackup "${snapshot}" || return 1
            printf '%s\n' '{"inbounds":[{"port":443,"settings":{"marker":"vision"}},{"port":12345}]}' >"${PADM_REALITY_STREAM_VISION_CONFIG_FILE}"
        done
        padmCreateTempPath snapshot -d "$(realityStreamEnableBackupTemplate)" || return 1
        backupRealityStreamState "${snapshot}" || return 1
        mkdir -p "$(dirname -- "${PADM_REALITY_STREAM_CONF_FILE}")"
        printf 'new stream\n' >"${PADM_REALITY_STREAM_CONF_FILE}"
        realityStreamRollback "${snapshot}" || return 1
        [[ ! -e "${PADM_REALITY_STREAM_CONF_FILE}" ]] || return 1
        removeRealityStreamBackup "${snapshot}" || return 1
        regressionExpectStatus 1 realityStreamRollback "${snapshot}" || return 1
    ) || return 1
    serviceQueueApply() { return 0; }
    readNginxSubscribe() { subscribePort=; return "${subscribeReadStatus}"; }
    subscribe() { subscribeCalls=$((subscribeCalls + 1)); }
    autoRead() {
        local value=
        case "$1" in
        reality_stream_enable|reality_stream_install_nginx) value=y ;;
        reality_stream_domains) value=site.example.com ;;
        reality_stream_website_port) value=${websitePortInput} ;;
        reality_stream_vision_port) value=${visionPort} ;;
        reality_stream_xhttp_port) value=${xhttpPort} ;;
        *) return 99 ;;
        esac
        printf -v "$3" '%s' "${value}"
        [[ "$1" != "${failKey}" ]] || return 7
    }
    menuReadChoice() {
        printf -v "$3" '%s' "${defaultChoice}"
        [[ "$1" != "${failKey}" ]] || return 7
    }
    oldVision=$(<"${PADM_REALITY_STREAM_VISION_CONFIG_FILE}")
    oldXHTTP=$(<"${PADM_REALITY_STREAM_XHTTP_CONFIG_FILE}")
    oldNginx=$(<"${PADM_REALITY_STREAM_NGINX_CONF}")

    if [[ "${mode}" != restore ]]; then
        # 损坏状态和孤立 stream 配置不能按未启用处理，更不能继续安装或重载。
        local invalidState operation statusLog="${root}/status.log"
        for invalidState in '' '{' '{}' '{"enabled":"true"}' '{"enabled":true,"default_protocol":"xhttp","protocols":{}}'; do
            printf '%s' "${invalidState}" >"${PADM_REALITY_STREAM_STATE_FILE}"
            for operation in configureRealityStreamSplit disableRealityStreamSplit showRealityStreamSplitStatus; do
                regressionExpectStatus 1 "${operation}" >"${statusLog}"
                ! grep -Eq '当前未启用|当前已启用' "${statusLog}"
                [[ "$(<"${PADM_REALITY_STREAM_STATE_FILE}")" == "${invalidState}" ]]
                [[ "$(<"${PADM_REALITY_STREAM_VISION_CONFIG_FILE}")" == "${oldVision}" &&
                    "$(<"${PADM_REALITY_STREAM_XHTTP_CONFIG_FILE}")" == "${oldXHTTP}" &&
                    "${backupCalls}:${patchCalls}:${allowCalls}:${reloadCalls}:${installCalls}" == 0:0:0:0:0 ]]
            done
        done
        rm "${PADM_REALITY_STREAM_STATE_FILE}"
        mkdir -p "${PADM_REALITY_STREAM_CONF_FILE%/*}"
        printf 'orphan stream\n' >"${PADM_REALITY_STREAM_CONF_FILE}"
        regressionExpectStatus 1 configureRealityStreamSplit
        regressionExpectStatus 1 disableRealityStreamSplit
        regressionExpectStatus 1 showRealityStreamSplitStatus >"${statusLog}"
        ! grep -Eq '当前未启用|当前已启用' "${statusLog}"
        [[ "$(<"${PADM_REALITY_STREAM_CONF_FILE}")" == 'orphan stream' ]]
        rm "${PADM_REALITY_STREAM_CONF_FILE}"
        showRealityStreamSplitStatus >"${statusLog}"
        grep -q '当前未启用' "${statusLog}"
        printf '{"enabled":false}\n' >"${PADM_REALITY_STREAM_STATE_FILE}"
        showRealityStreamSplitStatus >"${statusLog}"
        grep -q '当前未启用' "${statusLog}"
        rm "${PADM_REALITY_STREAM_STATE_FILE}"
        # 每个输入失败都在备份、开放端口和配置写入之前停止。
        for key in enable domains default_protocol website_port vision_port xhttp_port install_nginx; do
            failKey="reality_stream_${key}"
            defaultChoice=1
            nginx() { return 0; }
            [[ "${key}" != xhttp_port ]] || defaultChoice=2
            [[ "${key}" != install_nginx ]] || unset -f nginx
            regressionExpectStatus 1 configureRealityStreamSplit
            [[ "${backupCalls}" == 0 && "${patchCalls}" == 0 && "${allowCalls}" == 0 && "${reloadCalls}" == 0 && "${installCalls}" == 0 ]]
            [[ ! -e "${root}/install-called" ]]
            [[ "$(<"${PADM_REALITY_STREAM_VISION_CONFIG_FILE}")" == "${oldVision}" ]]
            [[ "$(<"${PADM_REALITY_STREAM_XHTTP_CONFIG_FILE}")" == "${oldXHTTP}" ]]
            [[ "$(<"${PADM_REALITY_STREAM_NGINX_CONF}")" == "${oldNginx}" ]]
            [[ ! -e "${PADM_REALITY_STREAM_STATE_FILE}" && ! -e "${PADM_REALITY_STREAM_CONF_FILE}" ]]
            [[ -z "$(find "${TMPDIR}" -mindepth 1 -print -quit)" ]]
        done
        nginx() { return 0; }
        failKey= defaultChoice=9
        regressionExpectStatus 1 configureRealityStreamSplit
        [[ "${backupCalls}" == 0 && "${patchCalls}" == 0 && "${allowCalls}" == 0 ]]
        defaultChoice=1 websitePortInput=invalid
        regressionExpectStatus 1 configureRealityStreamSplit
        [[ "${backupCalls}" == 0 && "${patchCalls}" == 0 && "${allowCalls}" == 0 ]]
        websitePortInput=8443
        # 首次启用也不能把仍使用 443 的非默认协议留在公网监听。
        defaultChoice=2
        unset -f nginx
        regressionExpectStatus 1 configureRealityStreamSplit
        [[ "${backupCalls}" == 0 && "${patchCalls}" == 0 && "${allowCalls}" == 0 && "${reloadCalls}" == 0 ]]
        [[ "${installCalls}" == 0 && ! -e "${root}/install-called" ]]
        [[ ! -e "${PADM_REALITY_STREAM_STATE_FILE}" && ! -e "${PADM_REALITY_STREAM_CONF_FILE}" ]]
        nginx() { return 0; }
        local conflict
        for conflict in website-public vision-public xhttp-public same-backend other-internal other-website; do
            defaultChoice=1 visionPort=2443 xhttpPort=2444 websitePortInput=8443
            case "${conflict}" in
            website-public) websitePortInput=00443 ;;
            vision-public) visionPort=443 ;;
            xhttp-public) defaultChoice=2; xhttpPort=00443 ;;
            same-backend) websitePortInput=02443 ;;
            other-internal) visionPort=09443 ;;
            other-website) websitePortInput=9443 ;;
            esac
            regressionExpectStatus 1 configureRealityStreamSplit
            [[ "${backupCalls}" == 0 && "${patchCalls}" == 0 && "${allowCalls}" == 0 && "${reloadCalls}" == 0 ]]
            [[ "$(<"${PADM_REALITY_STREAM_VISION_CONFIG_FILE}")" == "${oldVision}" ]]
            [[ "$(<"${PADM_REALITY_STREAM_XHTTP_CONFIG_FILE}")" == "${oldXHTTP}" ]]
            [[ "$(<"${PADM_REALITY_STREAM_NGINX_CONF}")" == "${oldNginx}" ]]
            [[ ! -e "${PADM_REALITY_STREAM_STATE_FILE}" && ! -e "${PADM_REALITY_STREAM_CONF_FILE}" ]]
        done
        defaultChoice=1 visionPort=2443 xhttpPort=2444 websitePortInput=8443
    fi
    if [[ "${mode}" == input ]]; then return 0; fi

    aliasFile="${configPath}02_dokodemodoor_inbounds_2053_default.json"
    aliasXHTTPFile="${configPath}02_dokodemodoor_inbounds_2083.json"
    ignoredFile="${configPath}02_dokodemodoor_inbounds_hysteria_2053.json"
    writeCoreDokodemoInbound "${aliasFile}" 2053 443 tcp dokodemo-door-newPort-2053
    writeCoreDokodemoInbound "${aliasXHTTPFile}" 2083 9443 tcp dokodemo-door-newPort-2083
    writeCoreDokodemoInbound "${ignoredFile}" 2053 443 udp dokodemo-door-newPort-hysteria-2053
    ignoredContent=$(<"${ignoredFile}")
    (
        # 迁移首个入口后，另一个入口写入失败必须恢复监听、全部入口和分流状态。
        local secondAlias="${configPath}02_dokodemodoor_inbounds_2096.json"
        local originalAlias=$(<"${aliasFile}") originalSecond
        writeCoreDokodemoInbound "${secondAlias}" 2096 443 tcp dokodemo-door-newPort-2096
        originalSecond=$(<"${secondAlias}")
        eval "$(declare -f commitGeneratedJsonFile | sed '1s/^commitGeneratedJsonFile/streamOriginalCommitJson/')"
        commitGeneratedJsonFile() { [[ "$2" != "${secondAlias}" ]] || return 1; streamOriginalCommitJson "$@"; }
        regressionExpectStatus 1 configureRealityStreamSplit
        [[ "$(<"${aliasFile}")" == "${originalAlias}" && "$(<"${secondAlias}")" == "${originalSecond}" &&
            "$(<"${PADM_REALITY_STREAM_VISION_CONFIG_FILE}")" == "${oldVision}" &&
            "$(<"${PADM_REALITY_STREAM_XHTTP_CONFIG_FILE}")" == "${oldXHTTP}" &&
            "$(<"${PADM_REALITY_STREAM_NGINX_CONF}")" == "${oldNginx}" &&
            ! -e "${PADM_REALITY_STREAM_STATE_FILE}" && ! -e "${PADM_REALITY_STREAM_CONF_FILE}" ]]
    )
    rm "${configPath}02_dokodemodoor_inbounds_2096.json"
    defaultChoice= visionPort= websitePortInput=
    configureRealityStreamSplit
    jq -e '.inbounds[0].listen == "127.0.0.1" and .inbounds[0].port == 2443 and .inbounds[0].settings.marker == "vision"' "${PADM_REALITY_STREAM_VISION_CONFIG_FILE}" >/dev/null
    jq -e '.inbounds[0].port == 2053 and .inbounds[0].settings.port == 2443' "${aliasFile}" >/dev/null
    defaultChoice=1 visionPort=2445 websitePortInput=8443
    configureRealityStreamSplit
    jq -e '.protocols.vision.restore_port == 443 and .protocols.vision.internal_port == 2445' "${PADM_REALITY_STREAM_STATE_FILE}" >/dev/null
    jq -e '.inbounds[0].settings.port == 2445' "${aliasFile}" >/dev/null
    showRealityStreamSplitStatus >"${root}/status.log"
    grep -q '当前已启用' "${root}/status.log"
    grep -qx '默认 Reality 后端监听正常: 127.0.0.1:2445' "${root}/status.log"
    grep -qx '订阅应输出公网端口: 443' "${root}/status.log"
    (
        # 详情渲染失败不能输出部分状态或已启用提示，也不能修改当前配置。
        local domains renderedState stateBefore=$(<"${PADM_REALITY_STREAM_STATE_FILE}")
        local effects="${backupCalls}:${patchCalls}:${allowCalls}:${reloadCalls}"
        local REGRESSION_ERROR_CARD_LOG="${root}/status-error.log"
        for domains in '"broken"' '{}' false; do
            jq --argjson domains "${domains}" '.website_domains = $domains' \
                "${PADM_REALITY_STREAM_STATE_FILE}" >"${root}/status-state.json" || return 1
            mv "${root}/status-state.json" "${PADM_REALITY_STREAM_STATE_FILE}" || return 1
            renderedState=$(<"${PADM_REALITY_STREAM_STATE_FILE}")
            : >"${REGRESSION_ERROR_CARD_LOG}"
            regressionExpectStatus 1 showRealityStreamSplitStatus >"${root}/status.log" || return 1
            grep -q '读取 Reality 443 共存状态失败' "${REGRESSION_ERROR_CARD_LOG}" || return 1
            ! grep -Eq '当前已启用|公网入口端口:|后端监听正常' "${root}/status.log" || return 1
            [[ "${backupCalls}:${patchCalls}:${allowCalls}:${reloadCalls}" == "${effects}" ]] || return 1
            [[ "$(<"${PADM_REALITY_STREAM_STATE_FILE}")" == "${renderedState}" ]] || return 1
        done
        jq '.website_domains = null' "${PADM_REALITY_STREAM_STATE_FILE}" >"${root}/status-state.json" || return 1
        mv "${root}/status-state.json" "${PADM_REALITY_STREAM_STATE_FILE}" || return 1
        showRealityStreamSplitStatus >"${root}/status.log" || return 1
        grep -q '当前已启用' "${root}/status.log" || return 1
        printf '%s\n' "${stateBefore}" >"${PADM_REALITY_STREAM_STATE_FILE}"
    ) || return 1
    (
        # 恢复端口读取失败必须在备份、配置写入和服务应用前退出。
        local failProtocol effects="${backupCalls}:${patchCalls}:${allowCalls}:${reloadCalls}"
        local stateBefore=$(<"${PADM_REALITY_STREAM_STATE_FILE}") aliasBefore=$(<"${aliasFile}")
        eval "$(declare -f realityStreamStoredPublicPortForProtocol | sed '1s/^realityStreamStoredPublicPortForProtocol/streamOriginalStoredPort/')"
        realityStreamStoredPublicPortForProtocol() { [[ "$1" != "${failProtocol}" ]] || return 1; streamOriginalStoredPort "$@"; }
        for failProtocol in vision xhttp; do
            regressionExpectStatus 1 disableRealityStreamSplit
            [[ "${backupCalls}:${patchCalls}:${allowCalls}:${reloadCalls}" == "${effects}" &&
                "$(<"${PADM_REALITY_STREAM_STATE_FILE}")" == "${stateBefore}" &&
                "$(<"${aliasFile}")" == "${aliasBefore}" && -f "${PADM_REALITY_STREAM_CONF_FILE}" ]]
        done
    )
    # 原后端恢复到 443 会与 stream 冲突，切换必须在任何写入前拒绝。
    oldVision=$(<"${PADM_REALITY_STREAM_VISION_CONFIG_FILE}")
    oldXHTTP=$(<"${PADM_REALITY_STREAM_XHTTP_CONFIG_FILE}")
    oldState=$(<"${PADM_REALITY_STREAM_STATE_FILE}")
    oldNginx=$(<"${PADM_REALITY_STREAM_NGINX_CONF}")
    oldStream=$(<"${PADM_REALITY_STREAM_CONF_FILE}")
    local previousEffects="${backupCalls}:${patchCalls}:${allowCalls}:${reloadCalls}"
    defaultChoice=2
    regressionExpectStatus 1 configureRealityStreamSplit
    [[ "${backupCalls}:${patchCalls}:${allowCalls}:${reloadCalls}" == "${previousEffects}" ]]
    [[ "$(<"${PADM_REALITY_STREAM_VISION_CONFIG_FILE}")" == "${oldVision}" ]]
    [[ "$(<"${PADM_REALITY_STREAM_XHTTP_CONFIG_FILE}")" == "${oldXHTTP}" ]]
    [[ "$(<"${PADM_REALITY_STREAM_STATE_FILE}")" == "${oldState}" ]]
    [[ "$(<"${PADM_REALITY_STREAM_NGINX_CONF}")" == "${oldNginx}" ]]
    [[ "$(<"${PADM_REALITY_STREAM_CONF_FILE}")" == "${oldStream}" ]]
    (
        # 模拟旧 Nginx 占住 443，关闭与失败回滚都必须按磁盘目标状态交接。
        local order='' socket443=nginx failCore=false failRestart=false nginxActive=true
        local snapshot
        padmCreateTempPath snapshot -d "$(realityStreamDisableBackupTemplate)" || return 1
        backupRealityStreamState "${snapshot}" || return 1
        nginxRunning() { [[ "${nginxActive}" == true ]]; }
        runServiceAction() {
            [[ "$1:$2" == nginx:restart ]] || return 1
            order+=N
            [[ "${failRestart}" == false ]] || return 1
            socket443=
        }
        reloadCore() {
            order+=C
            if realityStreamSplitEnabled; then
                [[ "${socket443}" != core ]] || socket443=
            else
                [[ "${socket443}" != nginx ]] || return 1
                socket443=core
            fi
            if [[ "${failCore}" == true ]]; then failCore=false; return 1; fi
        }
        serviceQueueApply() {
            order+=A
            if realityStreamSplitEnabled; then
                [[ "${socket443}" != core ]] || return 1
                socket443=nginx
            fi
        }
        (
            disableRealityStreamSplit || return 1
            [[ "${order}" == NCA && "${socket443}" == core ]] || return 1
        ) || return 1
        realityStreamRollback "${snapshot}" || return 1
        (
            nginxActive=false socket443=
            disableRealityStreamSplit || return 1
            [[ "${order}" == CA && "${socket443}" == core ]] || return 1
        ) || return 1
        realityStreamRollback "${snapshot}" || return 1
        (
            failCore=true
            regressionExpectStatus 1 disableRealityStreamSplit || return 1
            [[ "${order}" == NCCA && "${socket443}" == nginx ]] || return 1
            [[ "$(<"${PADM_REALITY_STREAM_STATE_FILE}")" == "${oldState}" ]] || return 1
        ) || return 1
        realityStreamRollback "${snapshot}" || return 1
        (
            failRestart=true
            regressionExpectStatus 1 disableRealityStreamSplit || return 1
            [[ "${order}" == NCA && "${socket443}" == nginx ]] || return 1
        ) || return 1
        realityStreamRollback "${snapshot}" || return 1
        (
            disableRealityStreamSplit || return 1
            order='' failCore=true defaultChoice=1
            regressionExpectStatus 1 configureRealityStreamSplit || return 1
            [[ "${order}" == CNCA && "${socket443}" == core ]] || return 1
            [[ ! -e "${PADM_REALITY_STREAM_STATE_FILE}" ]] || return 1
        ) || return 1
        realityStreamRollback "${snapshot}" || return 1
        (
            disableRealityStreamSplit || return 1
            order='' failCore=true failRestart=true defaultChoice=1
            regressionExpectStatus 1 configureRealityStreamSplit || return 1
            [[ "${order}" == CNA ]] || return 1
        ) || return 1
        realityStreamRollback "${snapshot}" || return 1
        removeRealityStreamBackup "${snapshot}" || return 1
    ) || return 1
    disableRealityStreamSplit
    jq -e '.inbounds[0].port == 443 and (.inbounds[0] | has("listen") | not)' "${PADM_REALITY_STREAM_VISION_CONFIG_FILE}" >/dev/null
    jq -e '.inbounds[0].settings.port == 443' "${aliasFile}" >/dev/null
    [[ ! -e "${PADM_REALITY_STREAM_STATE_FILE}" && ! -e "${PADM_REALITY_STREAM_CONF_FILE}" ]]

    # 两协议切换时旧后端恢复公网监听，新后端关闭后也恢复自己的原端口。
    jq '.inbounds[0].port = 11443' "${PADM_REALITY_STREAM_VISION_CONFIG_FILE}" >"${root}/vision-reset.json"
    mv "${root}/vision-reset.json" "${PADM_REALITY_STREAM_VISION_CONFIG_FILE}"
    writeCoreDokodemoInbound "${aliasFile}" 2053 11443 tcp dokodemo-door-newPort-2053
    defaultChoice=1 visionPort=2443
    configureRealityStreamSplit
    defaultChoice=2
    configureRealityStreamSplit
    jq -e '.inbounds[0].port == 11443 and (.inbounds[0] | has("listen") | not)' "${PADM_REALITY_STREAM_VISION_CONFIG_FILE}" >/dev/null
    jq -e '.inbounds[0].listen == "127.0.0.1" and .inbounds[0].port == 2444' "${PADM_REALITY_STREAM_XHTTP_CONFIG_FILE}" >/dev/null
    jq -e '.default_protocol == "xhttp" and (.protocols | has("vision") | not) and .protocols.xhttp.restore_port == 9443' "${PADM_REALITY_STREAM_STATE_FILE}" >/dev/null
    jq -e '.inbounds[0].settings.port == 11443' "${aliasFile}" >/dev/null
    jq -e '.inbounds[0].settings.port == 2444' "${aliasXHTTPFile}" >/dev/null
    showRealityStreamSplitStatus >"${root}/status.log"
    grep -qx '默认 Reality 后端监听正常: 127.0.0.1:2444' "${root}/status.log"
    grep -qx '订阅应输出公网端口: 443' "${root}/status.log"
    oldAlias=$(<"${aliasFile}") oldXHTTPAlias=$(<"${aliasXHTTPFile}")
    oldVision=$(<"${PADM_REALITY_STREAM_VISION_CONFIG_FILE}")
    oldXHTTP=$(<"${PADM_REALITY_STREAM_XHTTP_CONFIG_FILE}")
    oldState=$(<"${PADM_REALITY_STREAM_STATE_FILE}")
    oldNginx=$(<"${PADM_REALITY_STREAM_NGINX_CONF}")
    oldStream=$(<"${PADM_REALITY_STREAM_CONF_FILE}")
    reloadShouldFail=true defaultChoice=1 visionPort=2446
    regressionExpectStatus 1 configureRealityStreamSplit
    [[ "$(<"${PADM_REALITY_STREAM_VISION_CONFIG_FILE}")" == "${oldVision}" ]]
    [[ "$(<"${PADM_REALITY_STREAM_XHTTP_CONFIG_FILE}")" == "${oldXHTTP}" ]]
    [[ "$(<"${PADM_REALITY_STREAM_STATE_FILE}")" == "${oldState}" ]]
    [[ "$(<"${PADM_REALITY_STREAM_NGINX_CONF}")" == "${oldNginx}" ]]
    [[ "$(<"${PADM_REALITY_STREAM_CONF_FILE}")" == "${oldStream}" ]]
    [[ "$(<"${aliasFile}")" == "${oldAlias}" && "$(<"${aliasXHTTPFile}")" == "${oldXHTTPAlias}" ]]
    reloadShouldFail=false
    disableRealityStreamSplit
    jq -e '.inbounds[0].listen == "0.0.0.0" and .inbounds[0].port == 9443' "${PADM_REALITY_STREAM_XHTTP_CONFIG_FILE}" >/dev/null
    jq -e '.inbounds[0].port == 11443' "${PADM_REALITY_STREAM_VISION_CONFIG_FILE}" >/dev/null
    jq -e '.inbounds[0].settings.port == 9443' "${aliasXHTTPFile}" >/dev/null
    [[ "$(<"${ignoredFile}")" == "${ignoredContent}" ]]
    [[ "$(<"${PADM_REALITY_STREAM_NGINX_CONF}")" == $'events {}\nhttp {}' ]]
    [[ -z "$(find "${TMPDIR}" -mindepth 1 -print -quit)" ]]
    subscribeReadStatus=1
    regressionExpectStatus 1 realityStreamRefreshSubscribeIfInstalled
    [[ "${subscribeCalls}" == 0 ]]
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

    refreshPublishedSubscriptions() { refreshCalls=$((refreshCalls + 1)); return 1; }
    SUBSCRIPTION_SYNC_PUBLISHED=true
    refreshSubscriptionsAfterRealityTargetChange >/dev/null
    [[ "${refreshCalls}" == "3" && "${subscribeCalls}" == "0" ]]

    readNginxSubscribe() { subscribePort=39778; return 1; }
    regressionExpectStatus 1 refreshSubscriptionsAfterRealityTargetChange
    [[ "${refreshCalls}" == "3" && "${subscribeCalls}" == "0" ]]

    nginxConfigPath="${oldNginxConfigPath}"
    subscribePort="${oldSubscribePort}"
}

runRealityConfigControlledRefreshRegression() (
    local refreshSourceFile="${TMP_DIR}/reality-controlled-refresh-source.json"
    local statusLog="${TMP_DIR}/reality-controlled-refresh-status.log"
    : >"${statusLog}"
    subscriptionCurrentRoleNormalized() { printf 'controlled\n'; }
    subscriptionWireGuardReadState() {
        printf '%s\n' '{"peers":[{"id":"main","address":"10.77.0.1/24","enabled":true}]}'
    }
    subscriptionControlToken() { printf 'controlled-token\n'; }
    subscriptionRemoteControlRequest() {
        printf '%s\n' "$1" >"${refreshSourceFile}"
        [[ "$2" == "refresh" && "$3" == "{}" ]] || return 1
        printf '%s\n' '{"ok":true,"refreshed":true}'
    }
    realityTargetStatusBlock() { printf '%s\n' "$*" >>"${statusLog}"; }

    subscriptionNotifyControllerRefresh
    jq -e '.id == "main" and .host == "10.77.0.1" and .port == 39778 and .control_token == "controlled-token"' "${refreshSourceFile}" >/dev/null
    grep -q '已通知主控刷新订阅' "${statusLog}"
)

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
    runRegressionStep reality-config-stream-split runRealityStreamSplitRegression
    runRegressionStep reality-config-refresh-subscription runRealityConfigRefreshSubscriptionRegression
    runRegressionStep reality-config-controlled-refresh runRealityConfigControlledRefreshRegression
    runRegressionStep reality-config-import-skip runRealityConfigImportSkipRegression
}
