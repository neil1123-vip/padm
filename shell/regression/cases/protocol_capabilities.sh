#!/usr/bin/env bash

assertEquals() {
    local expected=$1
    local actual=$2
    local message=$3
    if [[ "${actual}" != "${expected}" ]]; then
        printf 'assert-fail:%s expected=%s actual=%s\n' "${message}" "${expected}" "${actual}" >&2
        return 1
    fi
}

assertPublicNode() {
    local id=$1
    protocolCapabilityIsPublicNode "${id}" || {
        printf 'assert-fail:capability %s should be public node\n' "${id}" >&2
        return 1
    }
    assertEquals node "$(protocolCapabilityMeta "${id}" category)" "category:${id}"
}

assertNotPublicNode() {
    local id=$1
    if protocolCapabilityIsPublicNode "${id}"; then
        printf 'assert-fail:capability %s should not be public node\n' "${id}" >&2
        return 1
    fi
}

runProtocolCapabilityRegistryRegression() {
    local id publicNodeIds internalIds

    publicNodeIds="1 2 3 4 5 21 22 23 24 25 26 27 28 29 30 31"
    for id in ${publicNodeIds}; do
        assertPublicNode "${id}"
    done

    internalIds="201 202 203 204 205 206 207"
    for id in ${internalIds}; do
        assertNotPublicNode "${id}"
        assertEquals internal "$(protocolCapabilityMeta "${id}" category)" "internal-category:${id}"
    done

    assertEquals xray "$(protocolCapabilityMeta 2 core_support)" "xhttp-core-support"
    assertEquals xray "$(protocolCapabilityMeta 2 project_core)" "xhttp-project-core"
    assertEquals uri,clash-meta,sing-box "$(protocolCapabilityMeta 4 subscription_emitters)" "anytls-subscription-emitters"
    assertEquals uri "$(protocolCapabilityMeta 5 subscription_emitters)" "naive-subscription-emitters"
    assertEquals 1 "$(protocolCapabilityIdByConfigFile 07_VLESS_vision_reality_inbounds.json)" "reality-config-file-id"
    assertEquals 2 "$(protocolCapabilityIdByConfigFile 12_VLESS_XHTTP_inbounds.json)" "xhttp-config-file-id"
    assertEquals 29 "$(protocolCapabilityIdByConfigFile 04_trojan_TCP_inbounds.json)" "trojan-fallback-config-file-id"
    if [[ ",$(protocolCapabilityIdsByCategory node)," == *",201,"* ]]; then
        printf 'assert-fail:internal capability leaked into public node ids\n' >&2
        return 1
    fi
    if protocolSelectionIdsValid "0" "$(protocolCapabilityIdsByCategory node)"; then
        printf 'assert-fail:legacy public id 0 should not be accepted\n' >&2
        return 1
    fi
    if protocolSelectionIdsValid "7" "$(protocolCapabilityIdsByCategory node)"; then
        printf 'assert-fail:legacy public id 7 should not be accepted\n' >&2
        return 1
    fi
    if protocolSelectionIdsValid "20" "$(protocolCapabilityIdsByCategory node)"; then
        printf 'assert-fail:legacy public id 20 should not be accepted\n' >&2
        return 1
    fi
    if ! protocolSelectionIdsValid "1,2,3,4,5" "$(protocolCapabilityIdsByCategory node)"; then
        printf 'assert-fail:recommended public ids should be accepted\n' >&2
        return 1
    fi
    if protocolCapabilityRegistry | awk -F'|' '$3 == "node" { if ($19 in seen) exit 1; seen[$19] = 1 }'; then
        :
    else
        printf 'assert-fail:node config_file values must be unique\n' >&2
        return 1
    fi
    if protocolCapabilityMeta 2 legacy_id >/dev/null 2>&1; then
        printf 'assert-fail:capability registry must not expose legacy_id\n' >&2
        return 1
    fi
    if declare -F protocolLegacyId >/dev/null || declare -F protocolCapabilityLegacyId >/dev/null || declare -F xrayProtocolIdByFilename >/dev/null; then
        printf 'assert-fail:legacy protocol id mapping function still exists\n' >&2
        return 1
    fi
}

runProtocolCapabilityMenuAndCoreRegression() {
    local recommendedIds advancedIds xrayIds singBoxIds

    recommendedIds=$(protocolCapabilityIdsByLifecycle recommended)
    assertEquals "1,2,3,4,5" "${recommendedIds}" "recommended-menu-ids"

    advancedIds=$(protocolCapabilityIdsByLifecycle advanced)
    for id in 21 22 23 24 25 26 27 28 29 30 31; do
        if [[ ",${advancedIds}," != *",${id},"* ]]; then
            printf 'assert-fail:advanced menu should include %s\n' "${id}" >&2
            return 1
        fi
    done
    for id in 201 202 203 204 205 206 207; do
        if [[ ",${recommendedIds},${advancedIds}," == *",${id},"* ]]; then
            printf 'assert-fail:internal capability %s should not be in node menus\n' "${id}" >&2
            return 1
        fi
    done

    xrayIds=$(protocolCapabilityIdsByProjectCore xray)
    singBoxIds=$(protocolCapabilityIdsByProjectCore sing-box)
    for id in 1 2 21 22 23 24 25 26 27 28 29; do
        if [[ ",${xrayIds}," != *",${id},"* ]]; then
            printf 'assert-fail:xray core ids should include %s\n' "${id}" >&2
            return 1
        fi
    done
    for id in 1 3 4 5 23 26 28 30 31; do
        if [[ ",${singBoxIds}," != *",${id},"* ]]; then
            printf 'assert-fail:sing-box core ids should include %s\n' "${id}" >&2
            return 1
        fi
    done
    if [[ ",${singBoxIds}," == *",2,"* ]]; then
        printf 'assert-fail:sing-box core ids must not include XHTTP id 2\n' >&2
        return 1
    fi
}

runProtocolCapabilityNginxTopologyRegression() {
    local id
    for id in 1 2 3 4 5 26 28 30 31; do
        assertEquals none "$(protocolCapabilityMeta "${id}" nginx_mode)" "nginx-none:${id}"
        if ! protocolSelectionSkipsNginx "${id}"; then
            printf 'assert-fail:capability %s should skip node nginx\n' "${id}" >&2
            return 1
        fi
    done
    for id in 1 2 26; do
        if protocolSelectionNeedsLocalCertificate "${id}"; then
            printf 'assert-fail:reality capability %s should not require local certificate\n' "${id}" >&2
            return 1
        fi
    done
    for id in 3 4 5 31; do
        if ! protocolSelectionNeedsLocalCertificate "${id}"; then
            printf 'assert-fail:TLS direct capability %s should require local certificate\n' "${id}" >&2
            return 1
        fi
    done
    for id in 21 22 23; do
        assertEquals http_front "$(protocolCapabilityMeta "${id}" nginx_mode)" "nginx-http-front:${id}"
        if protocolSelectionSkipsNginx "${id}"; then
            printf 'assert-fail:capability %s should require HTTP front nginx\n' "${id}" >&2
            return 1
        fi
    done
    for id in 24 25; do
        assertEquals grpc_front "$(protocolCapabilityMeta "${id}" nginx_mode)" "nginx-grpc-front:${id}"
        if protocolSelectionSkipsNginx "${id}"; then
            printf 'assert-fail:capability %s should require gRPC front nginx\n' "${id}" >&2
            return 1
        fi
    done
    for id in 27 29; do
        assertEquals fallback_backend "$(protocolCapabilityMeta "${id}" nginx_mode)" "nginx-fallback:${id}"
        if protocolSelectionSkipsNginx "${id}"; then
            printf 'assert-fail:capability %s should require fallback nginx\n' "${id}" >&2
            return 1
        fi
    done
    for id in 1 2 3 4 5 21 22 23 24 25 26 28 30 31; do
        if [[ "$(protocolCapabilityMeta "${id}" nginx_mode)" == "fallback_backend" ]]; then
            printf 'assert-fail:capability %s should not be fallback_backend\n' "${id}" >&2
            return 1
        fi
    done
}

runProtocolCapabilityTemplateRegression() {
    local coreTemplate="${PROJECT_ROOT}/shell/core/core_templates.sh"
    local stateFile="${PROJECT_ROOT}/shell/core/state.sh"
    local xrayIds singBoxIds reason ssUsers id configFile

    assertEquals "1,2,21,22,23,24,25,26,27,28,29" "$(protocolCapabilityIdsByProjectCore xray)" "xray-template-core-ids"
    assertEquals "1,3,4,5,23,26,28,30,31" "$(protocolCapabilityIdsByProjectCore sing-box)" "sing-box-template-core-ids"
    assertEquals 28 "$(protocolCapabilityIdByConfigFile 28_trojan_TCP_direct_inbounds.json)" "trojan-direct-config-file-id"
    assertEquals 30 "$(protocolCapabilityIdByConfigFile 30_shadowsocks_inbounds.json)" "shadowsocks-config-file-id"

    xrayIds=$(protocolCapabilityIdsByProjectCore xray)
    for id in 1 2 21 22 23 24 25 26 27 28 29; do
        if [[ ",${xrayIds}," != *",${id},"* ]]; then
            printf 'assert-fail:xray template chain should include %s\n' "${id}" >&2
            return 1
        fi
    done

    singBoxIds=$(protocolCapabilityIdsByProjectCore sing-box)
    for id in 1 3 4 5 23 26 28 30 31; do
        if [[ ",${singBoxIds}," != *",${id},"* ]]; then
            printf 'assert-fail:sing-box template chain should include %s\n' "${id}" >&2
            return 1
        fi
    done
    if [[ ",${singBoxIds}," == *",2,"* ]]; then
        printf 'assert-fail:sing-box template chain must reject XHTTP id 2\n' >&2
        return 1
    fi

    for id in 1 2 21 22 23 24 25 26 27 28 29; do
        configFile=$(protocolCapabilityMeta "${id}" config_file)
        if ! grep -Fq "writeGeneratedJsonFile /etc/padm/xray/conf/${configFile}" "${coreTemplate}"; then
            printf 'assert-fail:xray template missing config path for %s:%s\n' "${id}" "${configFile}" >&2
            return 1
        fi
    done
    if ! grep -Fq 'if [[ "$1" != "all" ]] && protocolSelectionIncludes "${selectCustomInstallType}" 28 "$1"; then' "${coreTemplate}"; then
        printf 'assert-fail:xray all mode must exclude direct Trojan sharing the fallback port\n' >&2
        return 1
    fi
    if ! grep -Fq 'protocolCapabilityIdsByProjectCore xray' "${stateFile}" ||
        ! grep -Fq 'protocolCapabilityMeta "${configFile}" config_file' "${stateFile}"; then
        printf 'assert-fail:readInstallType should recognize xray configs through capability metadata\n' >&2
        return 1
    fi
    for id in 1 3 4 5 23 26 28 30 31; do
        configFile=$(protocolCapabilityMeta "${id}" config_file)
        if ! grep -Fq "writeGeneratedJsonFile /etc/padm/sing-box/conf/config/${configFile}" "${coreTemplate}"; then
            printf 'assert-fail:sing-box template missing config path for %s:%s\n' "${id}" "${configFile}" >&2
            return 1
        fi
    done

    if ! declare -F protocolCoreUnsupportedReason >/dev/null; then
        printf 'assert-fail:missing protocolCoreUnsupportedReason\n' >&2
        return 1
    fi
    reason=$(protocolCoreUnsupportedReason sing-box "2")
    assertEquals "sing-box currently has no XHTTP transport support" "${reason}" "sing-box-xhttp-rejection"

    currentClients='[{"uuid":"11111111-1111-4111-8111-111111111111","name":"main-VLESS_Reality_Vision"}]'
    ssUsers=$(initSingBoxClients 30)
    if ! jq -e '.[0].name == "main-shadowsocks" and .[0].password != "11111111-1111-4111-8111-111111111111"' <<<"${ssUsers}" >/dev/null; then
        printf 'assert-fail:sing-box Shadowsocks 2022 users should not use UUID as raw key\n' >&2
        return 1
    fi
    ssPassword=$(jq -r '.[0].password' <<<"${ssUsers}")
    if [[ "$(printf '%s' "${ssPassword}" | base64 -d 2>/dev/null | wc -c | tr -d ' ')" != "16" ]]; then
        printf 'assert-fail:sing-box Shadowsocks 2022 user key should decode to 16 bytes\n' >&2
        return 1
    fi
    (
        # 从磁盘连续重装，保留独立密钥和全部用户，而非再次派生。
        local PADM_SINGBOX_CONFIG_DIR="${TMP_DIR}/shadowsocks-reinstall" coreInstallType=2
        local configPath="${PADM_SINGBOX_CONFIG_DIR}/"
        local singBoxConfigPath="${configPath}"
        local frontingType=30_shadowsocks_inbounds currentInstallProtocolType=,30, selectCustomInstallType=,30,
        local AUTO_INSTALL=true AUTO_UUID= AUTO_USER= AUTO_REUSE_LAST= lastInstallationConfig=true
        local PADM_INSTALL_CLIENTS_PREPARED= currentUUID= tlsCertDomain= singBoxShadowsocksPort=23433 singBoxTrojanPort=23434
        local target="${configPath}30_shadowsocks_inbounds.json" expected password users round invalid before writes=0
        local result=()
        mkdir -p "${PADM_SINGBOX_CONFIG_DIR}"
        collectTLSProfile() { tlsCertDomain=; }
        readSingBoxProtocolPort() { local -n ports=$1; ports=("${singBoxShadowsocksPort}"); }
        progressCard() { :; }
        echoContent() { :; }
        menuLine() { :; }
        menuClose() { :; }
        statusCard() { :; }
        successCard() { :; }
        errorCard() { :; }
        setSniffRouting() { :; }
        cdnStoredAddress() { :; }
        showLastInstallationConfig() { :; }
        writeGeneratedJsonFile() {
            jq . >"${PADM_SINGBOX_CONFIG_DIR}/${1##*/}" || return 1
            writes=$((writes + 1))
        }
        currentClients='[{"uuid":"11111111-1111-4111-8111-111111111111","name":"alice"},{"uuid":"22222222-2222-4222-8222-222222222222","name":"bob"}]'
        password=$(shadowsocks2022KeyFromSeed "server:${currentClients}")
        users=$(initSingBoxClients 30)
        expected=$(jq -nc --arg password "${password}" --argjson users "${users}" '{password:$password,users:$users}')
        jq -n --argjson credentials "${expected}" '{inbounds:[($credentials + {type:"shadowsocks",method:"2022-blake3-aes-128-gcm",listen_port:23432,tag:"old-tag"})]}' >"${target}"
        AUTO_ENTRY_HOST=45.221.113.40
        for round in 1 2; do
            readConfigHostPathUUID
            initSingBoxConfigApply custom 1 true >/dev/null
            assertEquals "${expected}" "$(jq -c '.inbounds[0] | {password,users}' "${target}")" "shadowsocks-reuse:${round}"
            jq -e '.inbounds[0] | .listen_port == 23433 and .tag == "singbox-shadowsocks-in"' "${target}" >/dev/null
        done
        # 模板持有其它协议的主用户时，仍须保留 Shadowsocks 的独立凭据。
        selectCustomInstallType=,28,30,
        currentClients='[{"uuid":"33333333-3333-4333-8333-333333333333","name":"primary"}]'
        initSingBoxConfigApply custom 1 true >/dev/null
        assertEquals "${expected}" "$(jq -c '.inbounds[0] | {password,users}' "${target}")" shadowsocks-independent-credentials
        AUTO_REUSE_LAST=no AUTO_UUID=44444444-4444-4444-8444-444444444444 AUTO_USER=new-user
        readLastInstallationConfig
        selectCustomInstallType=,30, singBoxShadowsocksPort=23433
        initSingBoxConfigApply custom 1 true >/dev/null
        jq -e --arg password "${password}" --argjson users "${users}" '.inbounds[0] | .password != $password and .users != $users and .users[0].name == "new-user-shadowsocks"' "${target}" >/dev/null
        rm -- "${target}"
        lastInstallationConfig=true AUTO_UUID= AUTO_USER=
        initSingBoxConfigApply custom 1 true >/dev/null
        jq -e '.inbounds[0] | (.password | type == "string" and length > 0) and (.users | length == 1)' "${target}" >/dev/null
        for invalid in '{"password":"","users":[]}' '{"password":"server-key","users":[{"name":"alice","password":false}]}'; do
            jq -n --argjson invalid "${invalid}" '{inbounds:[($invalid + {type:"shadowsocks",method:"2022-blake3-aes-128-gcm"})]}' >"${target}"
            before=$(cat "${target}")
            writes=0
            regressionExpectStatus 1 initSingBoxConfigApply custom 1 true >/dev/null
            [[ "${writes}" == 0 ]]
            assertEquals "${before}" "$(cat "${target}")" shadowsocks-invalid-credentials-preserved
        done
    )
}

runHysteria2CapabilityRegression() {
    local coreTemplate="${PROJECT_ROOT}/shell/core/core_templates.sh"
    local oldSingBoxConfigPath="${singBoxConfigPath:-}"
    local configDir="${TMP_DIR}/hysteria2-conf/"
    local oldUpload="${hysteria2ClientUploadSpeed:-}"
    local oldDownload="${hysteria2ClientDownloadSpeed:-}"
    local oldBandwidthMode="${hysteria2BandwidthMode:-}"
    local oldObfsType="${hysteria2ObfsType:-}"
    local oldObfsPassword="${hysteria2ObfsPassword:-}"
    local oldDomain="${domain:-}"
    local oldCurrentHost="${currentHost:-}"
    local oldPadmTlsDir="${PADM_TLS_DIR:-}"
    local tlsFallbackDir="${TMP_DIR}/hysteria2-tls-fallback/"

    if ! grep -Fq '"up_mbps": %s,\n            "down_mbps": %s,' "${coreTemplate}" ||
        ! grep -Fq '"${hysteria2ClientDownloadSpeed}" "${hysteria2ClientUploadSpeed}"' "${coreTemplate}"; then
        printf 'assert-fail:hysteria2 template should map client download/upload to server up/down\n' >&2
        return 1
    fi
    if ! grep -Fq '"masquerade":' "${coreTemplate}"; then
        printf 'assert-fail:hysteria2 template should emit masquerade config\n' >&2
        return 1
    fi

    mkdir -p "${configDir}"
    cat >"${configDir}06_hysteria2_inbounds.json" <<'EOF'
{"inbounds":[{"type":"hysteria2","listen_port":2443,"up_mbps":75,"down_mbps":150,"users":[],"tls":{"enabled":true}}]}
EOF
    singBoxConfigPath="${configDir}"
    readSingBoxConfig
    assertEquals 150 "${hysteria2ClientUploadSpeed}" "hysteria2-read-upload"
    assertEquals 75 "${hysteria2ClientDownloadSpeed}" "hysteria2-read-download"

    cat >"${configDir}06_hysteria2_inbounds.json" <<'EOF'
{"inbounds":[{"type":"hysteria2","listen_port":2443,"ignore_client_bandwidth":true,"obfs":{"type":"salamander","password":"obfs-password"},"users":[],"tls":{"enabled":true}}]}
EOF
    readSingBoxConfig
    assertEquals bbr "${hysteria2BandwidthMode}" "hysteria2-read-bbr"
    assertEquals salamander "${hysteria2ObfsType}" "hysteria2-read-obfs-type"
    assertEquals obfs-password "${hysteria2ObfsPassword}" "hysteria2-read-obfs-password"

    mkdir -p "${tlsFallbackDir}"
    printf 'cert\n' >"${tlsFallbackDir}/fallback.example.com.crt"
    printf 'key\n' >"${tlsFallbackDir}/fallback.example.com.key"
    domain=
    currentHost=
    export PADM_TLS_DIR="${tlsFallbackDir}"
    collectTLSProfile
    assertEquals fallback.example.com "${tlsCertDomain}" "hysteria2-tls-profile-installed-domain"
    assertEquals fallback.example.com "${tlsSNI}" "hysteria2-tls-profile-installed-sni"
    assertEquals /etc/padm/tls/fallback.example.com.crt "${tlsCertFile}" "hysteria2-tls-profile-installed-cert-path"
    assertEquals /etc/padm/tls/fallback.example.com.key "${tlsKeyFile}" "hysteria2-tls-profile-installed-key-path"

    if ! declare -F singBoxVersionAtLeast >/dev/null; then
        printf 'assert-fail:missing singBoxVersionAtLeast\n' >&2
        return 1
    fi
    singBoxVersionAtLeast v1.11.0 1.11.0 || { printf 'assert-fail:sing-box 1.11 should satisfy 1.11 gate\n' >&2; return 1; }
    singBoxVersionAtLeast v1.14.0-alpha.32 1.14.0 || { printf 'assert-fail:sing-box 1.14 prerelease should satisfy 1.14 gate\n' >&2; return 1; }
    if singBoxVersionAtLeast v1.10.7 1.11.0; then
        printf 'assert-fail:sing-box 1.10 should not satisfy 1.11 gate\n' >&2
        return 1
    fi
    if ! declare -F hysteria2SingBoxFieldSupported >/dev/null; then
        printf 'assert-fail:missing hysteria2SingBoxFieldSupported\n' >&2
        return 1
    fi
    hysteria2SingBoxFieldSupported masquerade v1.11.0 || { printf 'assert-fail:hysteria2 masquerade should be available on sing-box 1.11\n' >&2; return 1; }
    hysteria2SingBoxFieldSupported obfs_gecko v1.14.0-alpha.32 || { printf 'assert-fail:hysteria2 gecko obfs should be available on sing-box 1.14 prerelease\n' >&2; return 1; }
    assertEquals '{"type":"salamander","password":"secret"}' "$(hysteria2ObfsConfigJson salamander secret | jq -c .)" "hysteria2-obfs-json"
    if hysteria2ObfsConfigJson gecko "" >/dev/null 2>&1; then
        printf 'assert-fail:hysteria2 obfs password must not be empty\n' >&2
        return 1
    fi
    if hysteria2SingBoxFieldSupported bbr_profile v1.13.13; then
        printf 'assert-fail:hysteria2 bbr_profile should require sing-box 1.14\n' >&2
        return 1
    fi

    singBoxConfigPath="${oldSingBoxConfigPath}"
    hysteria2ClientUploadSpeed="${oldUpload}"
    hysteria2ClientDownloadSpeed="${oldDownload}"
    hysteria2BandwidthMode="${oldBandwidthMode}"
    hysteria2ObfsType="${oldObfsType}"
    hysteria2ObfsPassword="${oldObfsPassword}"
    domain="${oldDomain}"
    currentHost="${oldCurrentHost}"
    if [[ -n "${oldPadmTlsDir}" ]]; then
        export PADM_TLS_DIR="${oldPadmTlsDir}"
    else
        unset PADM_TLS_DIR
    fi
}

runSubscriptionCapabilityDispatchRegression() {
    local accountsFile="${PROJECT_ROOT}/shell/subscription/accounts.sh"
    local stateFile="${PROJECT_ROOT}/shell/core/state.sh"

    if ! declare -F subscriptionAccountDisplayFunction >/dev/null; then
        printf 'assert-fail:missing subscriptionAccountDisplayFunction\n' >&2
        return 1
    fi
    assertEquals showVlessRealityAccounts "$(subscriptionAccountDisplayFunction 1)" "account-display-fn:1"
    assertEquals showHysteriaAccounts "$(subscriptionAccountDisplayFunction 3)" "account-display-fn:3"
    assertEquals showVmessHTTPUpgradeAccounts "$(subscriptionAccountDisplayFunction 23)" "account-display-fn:23"
    assertEquals showShadowsocksAccounts "$(subscriptionAccountDisplayFunction 30)" "account-display-fn:30"
    assertEquals showTuicAccounts "$(subscriptionAccountDisplayFunction 31)" "account-display-fn:31"
    assertEquals 25 "$(protocolCapabilityFieldIndex account_display)" "account-display-field-index"
    if protocolCapabilityRegistry | awk -F'|' '$3 == "node" && $25 == "" { exit 1 }'; then
        :
    else
        printf 'assert-fail:public node capabilities must define account display functions\n' >&2
        return 1
    fi
    if grep -Eq '^[[:space:]]*case "\$1"' "${accountsFile}"; then
        printf 'assert-fail:account display mapping must live in capability registry\n' >&2
        return 1
    fi

    if grep -Eq '^[[:space:]]*show(Vless|Trojan|Vmess|Hysteria|Tuic|Naive|AnyTls)' "${accountsFile}"; then
        printf 'assert-fail:showAccounts should dispatch account display functions through capability ids\n' >&2
        return 1
    fi
    if ! grep -Fq 'protocolCapabilityRegistry' "${accountsFile}"; then
        printf 'assert-fail:showAccounts should iterate protocolCapabilityRegistry\n' >&2
        return 1
    fi

    if ! declare -F protocolCapabilityStatusLabel >/dev/null; then
        printf 'assert-fail:missing protocolCapabilityStatusLabel\n' >&2
        return 1
    fi
    assertEquals 'VLESS Reality Vision [recommended, nginx:none]' "$(protocolCapabilityStatusLabel 1)" "status-label:1"
    assertEquals 'VMess HTTPUpgrade TLS [advanced, nginx:http_front] 风险:HTTPUpgrade 属高级方案，新装优先 XHTTP' "$(protocolCapabilityStatusLabel 23)" "status-label:23"
    if grep -Fq 'VLESS+Reality+Vision' "${stateFile}" || grep -Fq 'VMess+TLS+HTTPUpgrade' "${stateFile}"; then
        printf 'assert-fail:showInstallStatus should use capability status labels instead of hard-coded names\n' >&2
        return 1
    fi
    if grep -Fq 'pgrep -f "xray/xray"' "${stateFile}" || grep -Fq 'pgrep -f "sing-box/sing-box"' "${stateFile}"; then
        printf 'assert-fail:showInstallStatus should use service helpers instead of process substring checks\n' >&2
        return 1
    fi
}

runInstallStatusVlessEncryptionRegression() (
    local outputFile="${TMP_DIR}/install-status-vless-encryption.log"

    coreInstallType=1
    readInstallProtocolType() { currentInstallProtocolType=",1,"; }
    xrayRunning() { return 0; }
    echoContent() { printf '%s\n' "$*" >>"${outputFile}"; }

    printf '%s\n' '{"enabled":true,"encryption":"active-encryption","decryption":"active-decryption"}' >"${PADM_VLESS_ENCRYPTION_STATE_FILE}"
    showInstallStatus
    grep -Fq 'VLESS Encryption [experimental]' "${outputFile}"

    : >"${outputFile}"
    printf '%s\n' '{"enabled":false}' >"${PADM_VLESS_ENCRYPTION_STATE_FILE}"
    showInstallStatus
    ! grep -Fq 'VLESS Encryption [experimental]' "${outputFile}"
)

runSingBoxPlainInboundHostFallbackRegression() {
    local oldCoreInstallType="${coreInstallType:-}"
    local oldConfigPath="${configPath:-}"
    local oldSingBoxConfigPath="${singBoxConfigPath:-}"
    local oldFrontingType="${frontingType:-}"
    local oldCurrentInstallProtocolType="${currentInstallProtocolType:-}"
    local oldAutoEntryHost="${AUTO_ENTRY_HOST:-}"
    local configDir="${TMP_DIR}/singbox-plain-host/"

    mkdir -p "${configDir}"
    cat >"${configDir}30_shadowsocks_inbounds.json" <<'JSON'
{"inbounds":[{"type":"shadowsocks","listen_port":23432,"method":"2022-blake3-aes-128-gcm","password":"server-key","users":[{"name":"main-shadowsocks","password":"user-key"}]}]}
JSON

    coreInstallType=2
    configPath="${configDir}"
    singBoxConfigPath="${configDir}"
    frontingType=30_shadowsocks_inbounds
    currentInstallProtocolType=",30,"
    AUTO_ENTRY_HOST=45.221.113.40
    readConfigHostPathUUID
    assertEquals 45.221.113.40 "${currentHost}" "singbox-plain-current-host"
    assertEquals '' "${currentUUID}" "singbox-plain-current-uuid"

    coreInstallType="${oldCoreInstallType}"
    configPath="${oldConfigPath}"
    singBoxConfigPath="${oldSingBoxConfigPath}"
    frontingType="${oldFrontingType}"
    currentInstallProtocolType="${oldCurrentInstallProtocolType}"
    AUTO_ENTRY_HOST="${oldAutoEntryHost}"
}

runXrayDirectTlsInboundWithoutFallbackRegression() {
    local oldCoreInstallType="${coreInstallType:-}"
    local oldConfigPath="${configPath:-}"
    local oldSingBoxConfigPath="${singBoxConfigPath:-}"
    local oldNginxConfigPath="${nginxConfigPath:-}"
    local oldFrontingType="${frontingType:-}"
    local oldCurrentInstallProtocolType="${currentInstallProtocolType:-}"
    local configDir="${TMP_DIR}/xray-direct-tls/"
    local errorFile="${TMP_DIR}/xray-direct-tls.err"

    mkdir -p "${configDir}"
    cat >"${configDir}28_trojan_TCP_direct_inbounds.json" <<'JSON'
{"inbounds":[{"port":443,"settings":{"clients":[{"password":"secret","email":"main-Trojan_TCP_direct"}]},"streamSettings":{"tlsSettings":{"certificates":[{"certificateFile":"/etc/padm/tls/example.com.crt"}]}}}]}
JSON
    printf '{}\n' >"${configDir}02_dokodemodoor_inbounds_443_default.json"

    coreInstallType=1
    configPath="${configDir}"
    singBoxConfigPath=
    nginxConfigPath="${configDir}"
    frontingType=28_trojan_TCP_direct_inbounds
    currentInstallProtocolType=",28,"
    local readStatus
    regressionExpectStatus 0 readConfigHostPathUUID 2>"${errorFile}"
    if [[ -s "${errorFile}" ]]; then
        cat "${errorFile}" >&2
        return 1
    fi
    assertEquals secret "${currentUUID}" "xray-direct-tls-current-uuid"

    coreInstallType="${oldCoreInstallType}"
    configPath="${oldConfigPath}"
    singBoxConfigPath="${oldSingBoxConfigPath}"
    nginxConfigPath="${oldNginxConfigPath}"
    frontingType="${oldFrontingType}"
    currentInstallProtocolType="${oldCurrentInstallProtocolType}"
}

runProtocolConfigOwnershipRegression() (
    set -euo pipefail
    source "${PROJECT_ROOT}/shell/core/state.sh"
    local root="${TMP_DIR}/protocol-config-ownership"
    local configPath="${root}/xray" singBoxConfigPath="${root}/sing-box" coreInstallType=1
    local id file expected
    mkdir -p "${configPath}" "${singBoxConfigPath}"
    for id in 1 2 3 4 5 23 26 28 29 30 31; do
        file=$(protocolCapabilityMeta "${id}" config_file)
        printf '{"inbounds":[]}\n' >"${configPath}/${file}"
        printf '{"inbounds":[]}\n' >"${singBoxConfigPath}/${file}"
        expected=${configPath}
        [[ "$(protocolCapabilityMeta "${id}" project_core)" != "sing-box" ]] || expected=${singBoxConfigPath}
        assertEquals "${expected}/${file}" "$(protocolConfigFile "${id}")" "config-owner:${id}"
        rm "${expected}/${file}"
        if [[ "$(protocolCapabilityMeta "${id}" project_core)" != "xray,sing-box" ]]; then
            regressionExpectStatus 1 protocolConfigFile "${id}"
        else
            assertEquals "${singBoxConfigPath}/${file}" "$(protocolConfigFile "${id}")" "config-aux-only:${id}"
        fi
    done
    coreInstallType=2
    configPath=${singBoxConfigPath}
    singBoxConfigPath=
    assertEquals "${configPath}/07_VLESS_vision_reality_inbounds.json" "$(protocolConfigFile 1)" single-singbox-config
    regressionExpectStatus 1 protocolConfigFile 2
    regressionExpectStatus 1 protocolConfigFile 999

    coreInstallType=1
    configPath="${root}/primary/"
    singBoxConfigPath="${root}/auxiliary/"
    mkdir -p "${configPath}" "${singBoxConfigPath}"
    printf '{"inbounds":[{"listen_port":14443,"tls":{"server_name":"aux.example"}}]}\n' >"${singBoxConfigPath}07_VLESS_vision_reality_inbounds.json"
    printf '{"inbounds":[{"listen_port":24443}]}\n' >"${singBoxConfigPath}28_trojan_TCP_direct_inbounds.json"
    printf '{"inbounds":[{"listen_port":34443}]}\n' >"${singBoxConfigPath}30_shadowsocks_inbounds.json"
    printf 'publicKey:aux-key\n' >"${singBoxConfigPath}reality_key"
    readInstallProtocolType
    for id in 1 28 30; do currentProtocolHas "${id}"; done
    assertEquals 14443 "${singBoxVLESSRealityVisionPort}" auxiliary-vision-port
    assertEquals aux.example "${singBoxVLESSRealityVisionSNI}" auxiliary-vision-sni
    assertEquals aux-key "${singBoxVLESSRealityPublicKey}" auxiliary-vision-key
    assertEquals 24443 "${singBoxTrojanPort}" auxiliary-trojan-port
    assertEquals 34443 "${singBoxShadowsocksPort}" auxiliary-shadowsocks-port
    readConfigHostPathUUID 2>"${root}/host-errors"
    [[ ! -s "${root}/host-errors" ]]
)

runProtocolEntryConfigUpdateRegression() (
    local root="${TMP_DIR}/protocol-entry-config" fixtureConfig before commits=0 field command value statusLog
    mkdir -p "${root}"
    root=$(cd -- "${root}" && pwd -P) || return 1
    fixtureConfig="${root}/config.json"
    statusLog="${root}/status.log"
    AUTO_INSTALL=
    (
        local PADM_XHTTP_CONFIG_FILE= PADM_XRAY_CONF_DIR="${root}/separate/conf/" PADM_XRAY_DIR="${root}/custom"
        assertEquals "${root}/separate/conf/12_VLESS_XHTTP_inbounds.json" "$(manageXHTTPConfigFile)" xhttp-custom-conf-dir
        PADM_XRAY_CONF_DIR=
        assertEquals "${root}/custom/conf/12_VLESS_XHTTP_inbounds.json" "$(manageXHTTPConfigFile)" xhttp-custom-root
        PADM_XHTTP_CONFIG_FILE="${fixtureConfig}"
        assertEquals "${fixtureConfig}" "$(manageXHTTPConfigFile)" xhttp-explicit-config
        PADM_XHTTP_CONFIG_FILE=relative/xhttp.json
        assertEquals relative/xhttp.json "$(manageXHTTPConfigFile)" xhttp-relative-config
        PADM_XHTTP_CONFIG_FILE=
        manageXrayConfigDir() { return 1; }
        regressionExpectStatus 1 manageXHTTPConfigFile
    )
    manageXHTTPConfigFile() { printf '%s\n' "${fixtureConfig}"; }
    tuicConfigFile() { printf '%s\n' "${fixtureConfig}"; }
    hysteria2ConfigFile() { printf '%s\n' "${fixtureConfig}"; }
    (
        # Hysteria2/Tuic 参数修改必须执行 sing-box check，不能只 merge。
        local validationArgs= fixtureBinary="${root}/sing-box"
        coreSingBoxBinaryPath() { printf '%s\n' "${fixtureBinary}"; }
        coreExecutableFile() { return 0; }
        singBoxMergeConfigForValidation() { validationArgs="$*"; }
        validateHysteria2ConfigUpdate
        [[ "${validationArgs}" == "${fixtureBinary} "*' check' ]]
        validationArgs=
        validateTuicConfigUpdate
        [[ "${validationArgs}" == "${fixtureBinary} "*' check' ]]
    )
    commitXHTTPConfigUpdate() {
        commits=$((commits + 1))
        commitGeneratedJsonFile "$1" "${fixtureConfig}"
    }
    commitTuicConfigUpdate() { commitXHTTPConfigUpdate "$@"; }
    echoContent() { :; }
    menuLine() { :; }
    menuClose() { :; }
    errorCard() { :; }
    statusCard() { printf '%s\n' "$*" >>"${statusLog}"; }
    warnCard() { :; }
    printf '%s\n' '{"inbounds":[{"up_mbps":100,"down_mbps":50,"streamSettings":{"realitySettings":{"serverNames":["reality.example.com"],"publicKey":"fixture-key","shortIds":["","fixture-id"]},"xhttpSettings":{"path":"/old","host":"old.example.com"}}}]}' >"${fixtureConfig}"

    # 同一入口接受无参数、字符串和带类型参数，保持原有提交路径。
    setXHTTPMode packet-up
    setXHTTPCustomXmux <<< $'\n\n\n'
    setXHTTPPathHost <<< $'/new/path\nfront.example.com'
    setXHTTPAdvancedParams <<< $'100-200\n2000000\n40\n50\n10-90\ny\nn'
    setTuicConnectionParams <<< $'300ms\n15s'
    jq -e '.inbounds[0] | .auth_timeout == "300ms" and .heartbeat == "15s" and
        (.streamSettings.xhttpSettings | .mode == "packet-up" and .path == "/new/path" and
        .host == "front.example.com" and .xmux.maxConcurrency == "16-32" and
        .xPaddingBytes == "100-200" and .scMaxEachPostBytes == 2000000 and
        .scMinPostsIntervalMs == 40 and .scMaxBufferedPosts == 50 and
        .scStreamUpServerSecs == "10-90" and .noGRPCHeader == true and .noSSEHeader == false)' \
        "${fixtureConfig}" >/dev/null
    value=$'quote " slash \\ line\nbreak'
    applyXHTTPConfigUpdate '.payload = $text | .port = $port | .enabled = $enabled' fixture \
        --arg text "${value}" --argjson port 8443 --argjson enabled true
    jq -e --arg text "${value}" '.payload == $text and .port == 8443 and .enabled == true' \
        "${fixtureConfig}" >/dev/null
    [[ "${commits}" == 6 ]]
    before=$(<"${fixtureConfig}")
    (
        # 只修改一个连接参数时，另一个回车沿用现有值；恢复默认值由独立入口负责。
        setTuicConnectionParams <<< $'500ms\n'
        jq -e '.inbounds[0] | .auth_timeout == "500ms" and .heartbeat == "15s"' "${fixtureConfig}" >/dev/null
        printf '%s\n' "${before}" >"${fixtureConfig}"
    )
    (
        # 开关复用统一确认规则，大小写和完整 yes 都不能被静默当成关闭。
        setXHTTPAdvancedParams <<< $'\n\n\n\n\nY\nyes'
        jq -e '.inbounds[0].streamSettings.xhttpSettings | .noGRPCHeader and .noSSEHeader' "${fixtureConfig}" >/dev/null
        setXHTTPAdvancedParams <<< $'\n\n\n\n\n\nn'
        jq -e '.inbounds[0].streamSettings.xhttpSettings | .noGRPCHeader == false and .noSSEHeader == false' "${fixtureConfig}" >/dev/null
        printf '%s\n' "${before}" >"${fixtureConfig}"
    )
    (
        # 数据用输出变量返回，非法时间的错误提示不能被命令替换吞掉。
        local errorLog="${root}/tuic-input-error.log"
        errorCard() { printf '%s\n' "$*"; }
        regressionExpectStatus 1 setTuicConnectionParams <<<bad >"${errorLog}"
        grep -q '时间格式错误' "${errorLog}"
        [[ "${commits}" == 6 && "$(<"${fixtureConfig}")" == "${before}" ]]
    )
    (
        # 范围读取不捕获错误卡；格式和顺序失败都保留配置与输出变量。
        local errorLog="${root}/xhttp-input-error.log" fromValue=unchanged toValue=unchanged
        errorCard() { printf '%s\n' "$*"; }
        for value in bad 9-2; do
            regressionExpectStatus 1 setXHTTPCustomXmux <<<"${value}" >"${errorLog}"
            grep -q '范围' "${errorLog}"
            [[ "${commits}" == 6 && "$(<"${fixtureConfig}")" == "${before}" ]]
            regressionExpectStatus 1 readXHTTPRange fixture 16 32 fromValue toValue <<<"${value}" >"${errorLog}"
            [[ "${fromValue}" == unchanged && "${toValue}" == unchanged ]]
        done
        readXHTTPRange fixture 16 32 fromValue toValue <<<7
        [[ "${fromValue}:${toValue}" == 7:7 ]]
    )
    (
        # 无效字段尽早返回，后续输入、配置和提交计数均保持。
        local inputFd unread earlyInput
        for value in xmux maxPost minInterval maxBuffered serverName host; do
            case "${value}" in
            xmux) command=setXHTTPCustomXmux; earlyInput=0 ;;
            maxPost) command=setXHTTPAdvancedParams; earlyInput=$'\nbad' ;;
            minInterval) command=setXHTTPAdvancedParams; earlyInput=$'\n\nbad' ;;
            maxBuffered) command=setXHTTPAdvancedParams; earlyInput=$'\n\n\nbad' ;;
            serverName) command=setXHTTPDownloadSettings; earlyInput=$'down.example.com\n\ntls\nbad:host' ;;
            host) command=setXHTTPDownloadSettings; earlyInput=$'down.example.com\n\ntls\n\nbad:host' ;;
            esac
            exec {inputFd}<<<"${earlyInput}"$'\nsentinel'
            regressionExpectStatus 1 "${command}" <&"${inputFd}"
            read -r unread <&"${inputFd}"
            exec {inputFd}<&-
            [[ "${unread}" == sentinel && "${commits}" == 6 && "$(<"${fixtureConfig}")" == "${before}" ]]
        done
    )
    (
        # 状态读取失败不使用残留协议，也不消费下级菜单输入。
        local step inputFd unread coreInstallType=1 currentInstallProtocolType=,2, summaryCalls=0
        xhttpSettingsSummary() { summaryCalls=$((summaryCalls + 1)); }
        for step in install protocols; do
            readInstallType() { [[ "${step}" != install ]]; }
            readInstallProtocolType() { [[ "${step}" != protocols ]]; }
            exec {inputFd}<<<sentinel
            regressionExpectStatus 1 manageXHTTP <&"${inputFd}"
            read -r unread <&"${inputFd}"
            exec {inputFd}<&-
            [[ "${unread}" == sentinel && "${summaryCalls}" == 0 ]]
        done
    )
    regressionExpectStatus 1 applyXHTTPConfigUpdate '.enabled = $enabled' fixture --argjson enabled invalid 2>/dev/null
    [[ "${commits}" == 6 && "$(<"${fixtureConfig}")" == "${before}" ]]
    [[ -z "$(find "${root}" -name '.config.json.xhttp.*' -print -quit)" ]]
    (
        # 无 JSON 输出不能进入协议提交，也不能留下空暂存文件。
        commitHysteria2ConfigUpdate() { commitXHTTPConfigUpdate "$@"; }
        for value in '' '   ' '{'; do
            printf '%s' "${value}" >"${fixtureConfig}"
            for command in applyXHTTPConfigUpdate applyHysteria2ConfigUpdate applyTuicConfigUpdate; do
                regressionExpectStatus 1 "${command}" '.enabled = false' fixture 2>/dev/null
                [[ "${commits}" == 6 && "$(<"${fixtureConfig}")" == "${value}" ]]
                [[ -z "$(find "${root}" -name '.config.json.*' -print -quit)" ]]
            done
        done
        printf '%s\n' "${before}" >"${fixtureConfig}"
        regressionExpectStatus 1 applyXHTTPConfigUpdate empty fixture
        [[ "${commits}" == 6 && "$(<"${fixtureConfig}")" == "${before}" ]]
        [[ -z "$(find "${root}" -name '.config.json.*' -print -quit)" ]]
    )
    printf '%s\n' "${before}" >"${fixtureConfig}"

    (
        # 默认字段只读一次并保留空值；坏配置或缺文件不能消费下一条菜单输入。
        local reads="${root}/xhttp-reads.log" inputFd unread missingKeyConfig
        jq() { printf '%s\n' "$*" >>"${reads}"; command jq "$@"; }
        setXHTTPPathHost <<< $'\n\n'
        [[ "$(grep -c '^-er ' "${reads}")" == 1 ]]
        jq -e '.inbounds[0].streamSettings.xhttpSettings | .path == "/new/path" and .host == "front.example.com"' "${fixtureConfig}" >/dev/null
        : >"${reads}"
        # Reality 不读取无效的 ALPN，mode 之后的菜单输入必须保留。
        exec {inputFd}<<< $'down.example.com\n\nreality\n\n\n\npacket-up\nsentinel'
        setXHTTPDownloadSettings <&"${inputFd}"
        read -r unread <&"${inputFd}"
        exec {inputFd}<&-
        [[ "${unread}" == sentinel ]]
        [[ "$(grep -c '^-er ' "${reads}")" == 1 ]]
        jq -e '.inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings |
            .port == 443 and .realitySettings.serverName == "reality.example.com" and
            .realitySettings.publicKey == "fixture-key" and .realitySettings.shortId == "fixture-id" and
            .xhttpSettings.host == "reality.example.com" and .xhttpSettings.path == "/new/path" and
            .xhttpSettings.mode == "packet-up" and (has("tlsSettings") | not)' "${fixtureConfig}" >/dev/null
        command jq '.inbounds[0].streamSettings.realitySettings.shortIds = ["fallback-id"] |
            .inbounds[0].streamSettings.xhttpSettings.path = ""' "${fixtureConfig}" >"${root}/empty-path.json"
        mv "${root}/empty-path.json" "${fixtureConfig}"
        setXHTTPDownloadSettings <<< $'down.example.com\n\nreality\n\n\n/explicit\n'
        jq -e '.inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings |
            .realitySettings.publicKey == "fixture-key" and .realitySettings.shortId == "fallback-id" and
            .xhttpSettings.path == "/explicit" and .xhttpSettings.mode == "auto"' "${fixtureConfig}" >/dev/null
        # 缺少公钥时在选择 Reality 后退出，不继续提问或提交。
        command jq 'del(.inbounds[0].streamSettings.realitySettings.publicKey)' "${fixtureConfig}" >"${root}/missing-key.json"
        mv "${root}/missing-key.json" "${fixtureConfig}"
        missingKeyConfig=$(<"${fixtureConfig}")
        exec {inputFd}<<< $'down.example.com\n\nreality\nsentinel'
        regressionExpectStatus 1 setXHTTPDownloadSettings <&"${inputFd}"
        read -r unread <&"${inputFd}"
        exec {inputFd}<&-
        [[ "${unread}" == sentinel && "${commits}" == 9 && "$(<"${fixtureConfig}")" == "${missingKeyConfig}" ]]
        for value in malformed empty whitespace missing; do
            printf '{' >"${fixtureConfig}"
            [[ "${value}" != empty ]] || : >"${fixtureConfig}"
            [[ "${value}" != whitespace ]] || printf '   \n' >"${fixtureConfig}"
            [[ "${value}" != missing ]] || rm "${fixtureConfig}"
            for command in setXHTTPPathHost setXHTTPDownloadSettings setHysteria2BandwidthMode setTuicConnectionParams; do
                exec {inputFd}<<<sentinel
                if [[ "${command}" == setHysteria2BandwidthMode ]]; then
                    regressionExpectStatus 1 "${command}" brutal <&"${inputFd}"
                else
                    regressionExpectStatus 1 "${command}" <&"${inputFd}"
                fi
                read -r unread <&"${inputFd}"
                exec {inputFd}<&-
                [[ "${unread}" == sentinel && "${commits}" == 9 ]]
                [[ -z "$(find "${root}" -name '.config.json.xhttp.*' -print -quit)" ]]
            done
        done
    )
    printf '%s\n' "${before}" >"${fixtureConfig}"

    (
        # 模式按落盘结果展示；配置不可读时不能消费后续菜单输入。
        local modeLog="${root}/hysteria-mode.log" inputFd unread
        commitHysteria2ConfigUpdate() { commitXHTTPConfigUpdate "$@"; }
        menuLine() { printf '%s\n' "$*" >>"${modeLog}"; }
        manageHysteria2Bandwidth <<< $'2\n3'
        grep -qx '当前模式：brutal' "${modeLog}"
        grep -qx '当前模式：bbr' "${modeLog}"
        [[ "${commits}" == 7 ]]
        for value in malformed empty missing; do
            printf '{' >"${fixtureConfig}"
            [[ "${value}" != empty ]] || : >"${fixtureConfig}"
            [[ "${value}" != missing ]] || rm "${fixtureConfig}"
            : >"${modeLog}"
            exec {inputFd}<<<sentinel
            regressionExpectStatus 1 manageHysteria2Bandwidth <&"${inputFd}"
            read -r unread <&"${inputFd}"
            exec {inputFd}<&-
            [[ "${unread}" == sentinel && ! -s "${modeLog}" && "${commits}" == 7 ]]
        done
    )
    printf '%s\n' "${before}" >"${fixtureConfig}"

    # 未换行输入与 EOF 均不能被当成回车默认值，也不能创建暂存文件或提交。
    for command in setXHTTPCustomXmux setXHTTPPathHost setXHTTPAdvancedParams setXHTTPDownloadSettings setTuicConnectionParams; do
        regressionExpectStatus 1 "${command}" </dev/null
    done
    regressionExpectStatus 1 setTuicZeroRtt true < <(printf y)
    value=unchanged
    regressionExpectStatus 1 readHysteria2Bandwidth fixture bad value </dev/null
    [[ "${value}" == unchanged ]]
    (
        local failedKey
        autoRead() {
            case "$1" in
            xhttp_path) printf -v "$3" '%s' /new ;;
            xhttp_host|xhttp_download_address) printf -v "$3" '%s' front.example.com ;;
            *) printf -v "$3" '%s' '' ;;
            esac
            [[ "$1" != "${failedKey}" ]]
        }
        for field in xhttp_path xhttp_host; do
            failedKey=${field}
            regressionExpectStatus 1 setXHTTPPathHost
        done
        for field in xhttp_range xhttp_max_post_bytes xhttp_min_posts_interval xhttp_max_buffered_posts xhttp_disable_grpc_header xhttp_disable_sse_header; do
            failedKey=${field}
            regressionExpectStatus 1 setXHTTPAdvancedParams
        done
        for field in xhttp_download_address xhttp_download_port xhttp_download_security xhttp_download_server_name xhttp_download_host xhttp_download_path xhttp_download_alpn xhttp_download_mode; do
            failedKey=${field}
            regressionExpectStatus 1 setXHTTPDownloadSettings
        done
        [[ "${commits}" == 6 && "$(<"${fixtureConfig}")" == "${before}" ]]
    )
    [[ "${commits}" == 6 && "$(<"${fixtureConfig}")" == "${before}" ]]
    [[ -z "$(find "${root}" -name '.config.json.*' -print -quit)" ]]
    (
        local currentHost=installed.example.com realityEntryHost=reality.example.com
        readInstallType() { :; }
        cdnAddressFile() { printf '%s/cdn\n' "${root}"; }
        [[ -z "$(cdnStoredAddress)" && "$(cdnCurrentAddress)" == installed.example.com ]]
        regressionExpectStatus 1 setCDNEntryAddress < <(printf partial.example.com)
        [[ ! -e "${root}/cdn" && ! -e "${statusLog}" ]]
        for value in ,cdn.example.com cdn.example.com, cdn.example.com,,203.0.113.10 \
            'cdn.example.com, 203.0.113.10' https://cdn.example.com cdn.example.com:443 \
            999.0.0.1 2001:::1; do
            regressionExpectStatus 1 setCDNEntryAddress <<<"${value}"
            [[ ! -e "${root}/cdn" && ! -e "${statusLog}" ]]
        done
        (
            autoRead() { printf -v "$3" '%s' $'cdn.example.com\n203.0.113.10'; }
            regressionExpectStatus 1 setCDNEntryAddress
            [[ ! -e "${root}/cdn" && ! -e "${statusLog}" ]]
        )
        # 缺失或空文件必须按原始空值回滚，不能写回展示用的安装入口。
        subscribe() { return 1; }
        regressionExpectStatus 1 setCDNEntryAddress <<<new.example.com
        [[ ! -s "${root}/cdn" && -z "$(cdnStoredAddress)" && ! -e "${statusLog}" ]]
        currentHost=
        [[ "$(cdnCurrentAddress)" == reality.example.com ]]
        realityEntryHost=
        [[ "$(cdnCurrentAddress)" == 未设置 ]]
        currentHost=installed.example.com
        printf 'old.example.com\n' >"${root}/cdn"
        [[ "$(cdnStoredAddress)" == old.example.com && "$(cdnCurrentAddress)" == old.example.com ]]
        regressionExpectStatus 1 setCDNEntryAddress <<<new.example.com
        [[ "$(<"${root}/cdn")" == old.example.com && ! -e "${statusLog}" ]]
        regressionExpectStatus 1 clearCDNEntryAddress
        [[ "$(<"${root}/cdn")" == old.example.com && ! -e "${statusLog}" ]]
        (
            local coreInstallType= configPath= singBoxConfigPath= frontingType= currentInstallProtocolType=
            readConfigHostPathUUID
            [[ "${currentCDNAddress}" == old.example.com ]]
            head() { return 1; }
            regressionExpectStatus 1 cdnStoredAddress
            regressionExpectStatus 1 setCDNEntryAddress <<<new.example.com
            regressionExpectStatus 1 clearCDNEntryAddress
            regressionExpectStatus 1 readConfigHostPathUUID
            local inputFd unread errorLog="${root}/cdn-read-error.log"
            readInstallProtocolType() { :; }
            errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
            exec {inputFd}<<<sentinel
            regressionExpectStatus 1 manageCDN 1 <&"${inputFd}"
            read -r unread <&"${inputFd}"
            exec {inputFd}<&-
            [[ "${unread}" == sentinel ]]
            grep -qx '读取 CDN 入口地址失败' "${errorLog}"
            [[ "$(<"${root}/cdn")" == old.example.com && ! -e "${statusLog}" ]]
        )
        subscribe() { return 0; }
        value=cdn.example.com,203.0.113.10,2001:db8::1
        setCDNEntryAddress <<<"${value}"
        [[ "$(<"${root}/cdn")" == "${value}" ]]
        clearCDNEntryAddress
        [[ ! -s "${root}/cdn" && "$(wc -l <"${statusLog}")" == 2 ]]
        (
            local currentInstallProtocolType=,22, menuLog="${root}/cdn-menu.log"
            readInstallProtocolType() { :; }
            menuLine() { printf '%s\n' "$*" >>"${menuLog}"; }
            manageCDN 1 <<< $'1\ncdn.example.com\n4'
            [[ "$(<"${root}/cdn")" == cdn.example.com ]]
            grep -q '当前是传统 TLS/CDN 协议' "${menuLog}"
            currentInstallProtocolType=,2,
            manageCDN 1 <<< $'1\nxhttp.example.com\n4'
            [[ "$(<"${root}/cdn")" == xhttp.example.com ]]
            grep -q '当前已安装 Reality XHTTP' "${menuLog}"
            currentInstallProtocolType=,1,
            manageCDN 1 <<< $'1\n4'
            [[ "$(<"${root}/cdn")" == xhttp.example.com ]]
        )
    )
    (
        # 场景预设仍一次更新 mode 与 XMUX；XMUX 子菜单不能顺带重置 mode。
        for value in daily compatible stream single; do
            setXHTTPPreset "${value}"
            command jq -e --arg preset "${value}" '
                .inbounds[0].streamSettings.xhttpSettings |
                .mode == (if $preset == "compatible" then "packet-up" elif $preset == "stream" then "stream-up" else "auto" end) and
                .xmux.maxConcurrency == (if $preset == "single" then 1 else "16-32" end) and
                .xmux.hMaxRequestTimes == "600-900" and .xmux.hMaxReusableSecs == "1800-3000"
            ' "${fixtureConfig}" >/dev/null
        done
        before=$(<"${fixtureConfig}")
        regressionExpectStatus 1 setXHTTPPreset invalid
        [[ "$(<"${fixtureConfig}")" == "${before}" ]]
        setXHTTPMode packet-up
        applyXHTTPConfigUpdate '.inbounds[0].streamSettings.xhttpSettings.xmux |=
            (.hMaxRequestTimes = "42-84" | .hMaxReusableSecs = "90-120" | .cMaxReuseTimes = 7)' fixture
        manageXHTTPXmux <<< $'1\n4'
        command jq -e '.inbounds[0].streamSettings.xhttpSettings | .mode == "packet-up" and
            .xmux == {"maxConcurrency":"16-32","hMaxRequestTimes":"42-84","hMaxReusableSecs":"90-120","cMaxReuseTimes":7}' "${fixtureConfig}" >/dev/null
        manageXHTTPXmux <<< $'2\n4'
        command jq -e '.inbounds[0].streamSettings.xhttpSettings | .mode == "packet-up" and
            .xmux == {"maxConcurrency":1,"hMaxRequestTimes":"42-84","hMaxReusableSecs":"90-120","cMaxReuseTimes":7}' "${fixtureConfig}" >/dev/null
        setXHTTPCustomXmux <<< $'8-16\n50-100\n120-180'
        command jq -e '.inbounds[0].streamSettings.xhttpSettings | .mode == "packet-up" and
            .xmux == {"maxConcurrency":"8-16","hMaxRequestTimes":"50-100","hMaxReusableSecs":"120-180","cMaxReuseTimes":7}' "${fixtureConfig}" >/dev/null
        applyXHTTPConfigUpdate 'del(.inbounds[0].streamSettings.xhttpSettings.xmux)' fixture
        setXHTTPXmux 1
        command jq -e '.inbounds[0].streamSettings.xhttpSettings.xmux ==
            {"maxConcurrency":1,"hMaxRequestTimes":"600-900","hMaxReusableSecs":"1800-3000"}' "${fixtureConfig}" >/dev/null

        # 空可选字段、对象/数字/字符串范围与布尔值仍正确展示，每个摘要只解析一次。
        printf '%s\n' '{"inbounds":[{"port":8443,"listen_port":9443,"ignore_client_bandwidth":true,"users":[{},{}],"congestion_control":"bbr","auth_timeout":"300ms","heartbeat":"15s","zero_rtt_handshake":true,"streamSettings":{"realitySettings":{"serverNames":["sni.example.com"]},"xhttpSettings":{"mode":"packet-up","host":"","path":"","xmux":{"maxConcurrency":{"from":16,"to":32},"hMaxRequestTimes":800,"hMaxReusableSecs":"1800-3000"},"noGRPCHeader":true,"noSSEHeader":false}}}]}' >"${fixtureConfig}"
        local summaryLog="${root}/summary.log" jqCalls="${root}/summary-jq.log"
        jq() { printf 'jq\n' >>"${jqCalls}"; command jq "$@"; }
        menuLine() { printf '%s\n' "$*" >>"${summaryLog}"; }
        xhttpSettingsSummary
        hysteria2SettingsSummary "${fixtureConfig}"
        tuicSettingsSummary
        [[ "$(wc -l <"${jqCalls}")" == 3 ]]
        grep -qx '当前配置：端口=8443；mode=packet-up；Reality SNI=sni.example.com' "${summaryLog}"
        grep -qx 'XHTTP：host=；path=' "${summaryLog}"
        grep -qx 'XMUX：maxConcurrency=16-32；hMaxRequestTimes=800；hMaxReusableSecs=1800-3000' "${summaryLog}"
        grep -qx '高级：xPaddingBytes=0；noGRPCHeader=true；noSSEHeader=false' "${summaryLog}"
        grep -qx '上下行分离：未启用' "${summaryLog}"
        grep -qx '拥塞控制：BBR（自适应）' "${summaryLog}"
        grep -qx '连接参数：auth_timeout=300ms；heartbeat=15s' "${summaryLog}"
        grep -qx '0-RTT：true（默认关闭，开启会增加重放风险）' "${summaryLog}"
        [[ "$(grep -cx '用户数量：2' "${summaryLog}")" == 2 ]]
        : >"${summaryLog}"
        printf '%s\n' '{"inbounds":[{}]}' >"${fixtureConfig}"
        xhttpSettingsSummary
        hysteria2SettingsSummary "${fixtureConfig}"
        tuicSettingsSummary
        grep -qx '当前配置：端口=；mode=auto；Reality SNI=' "${summaryLog}"
        grep -qx '拥塞控制：Brutal（下行  Mbps，上行  Mbps）' "${summaryLog}"
        grep -qx '连接参数：auth_timeout=3s；heartbeat=10s' "${summaryLog}"
        before=$(<"${summaryLog}")
        for value in '' '   ' '{'; do
            printf '%s' "${value}" >"${fixtureConfig}"
            regressionExpectStatus 1 xhttpSettingsSummary
            regressionExpectStatus 1 hysteria2SettingsSummary "${fixtureConfig}"
            regressionExpectStatus 1 tuicSettingsSummary
            [[ "$(<"${summaryLog}")" == "${before}" ]]
        done
        (
            # 摘要失败必须在菜单读取前返回，不消费上级菜单后续输入。
            local inputFd unread coreInstallType=1 currentInstallProtocolType=,2, singBoxConfigPath="${root}/"
            readInstallType() { :; }
            readInstallProtocolType() { :; }
            for value in '' '   ' '{'; do
                printf '%s' "${value}" >"${fixtureConfig}"
                for command in manageXHTTP manageHysteria manageTuic; do
                    exec {inputFd}<<<sentinel
                    regressionExpectStatus 1 "${command}" <&"${inputFd}"
                    read -r unread <&"${inputFd}"
                    exec {inputFd}<&-
                    [[ "${unread}" == sentinel ]]
                done
            done
        )
    )
    (
        # 首次增量安装的局部路径返回后，每轮按落盘状态刷新安装/卸载菜单。
        local coreInstallType=1 singBoxConfigPath= detections=0 summaries=0 installs=0 removals=0
        local menuLog="${root}/protocol-install-menu.log" inputFd unread
        readInstallType() {
            detections=$((detections + 1))
            singBoxConfigPath=
            [[ ! -f "${fixtureConfig}" ]] || singBoxConfigPath="${root}/"
            return 0
        }
        singBoxHysteria2Install() {
            local singBoxConfigPath="${root}/"
            installs=$((installs + 1))
            printf '{"inbounds":[{}]}\n' >"${fixtureConfig}"
        }
        singBoxTuicInstall() { singBoxHysteria2Install; }
        unInstallSingBox() { removals=$((removals + 1)); rm "${fixtureConfig}"; }
        hysteria2SettingsSummary() { summaries=$((summaries + 1)); }
        tuicSettingsSummary() { summaries=$((summaries + 1)); }
        menuItem() { printf '%s\n' "$2" >>"${menuLog}"; }
        errorCard() { return 1; }
        for command in manageHysteria manageTuic; do
            rm -f "${fixtureConfig}"
            : >"${menuLog}"
            detections=0 summaries=0 installs=0 removals=0
            "${command}" <<< $'1\n2\n2'
            [[ "${detections}:${summaries}:${installs}:${removals}" == 3:1:1:1 ]]
            [[ "${coreInstallType}" == 1 && -z "${singBoxConfigPath}" && ! -e "${fixtureConfig}" ]]
            grep -qx 重新安装 "${menuLog}"
            grep -qx 卸载 "${menuLog}"
        done
        readInstallType() { return 1; }
        for command in manageHysteria manageTuic; do
            exec {inputFd}<<<sentinel
            regressionExpectStatus 1 "${command}" <&"${inputFd}"
            read -r unread <&"${inputFd}"
            exec {inputFd}<&-
            [[ "${unread}" == sentinel ]]
        done
    )
)

runProtocolEntryPortRegression() (
    local root="${TMP_DIR}/protocol-entry-port" configPath coreInstallType=1 singBoxConfigPath= hysteriaPort=
    local listenerFile defaultFile before installedIds=,1,
    reloadCore() { return 99; }
    runServiceAction() { [[ "$*" == "xray restart" ]]; }
    mkdir -p "${root}"
    root=$(cd -- "${root}" && pwd -P) || return 1
    configPath="${root}/"
    (
        # 文件名匹配已排除 UDP 转发和其它分片，列表编号只计算 TCP 入口。
        local configPath="${root}/listing/"
        mkdir -p "${configPath}"
        for value in 2053 2083_default hysteria_2083 legacy; do
            printf '{}\n' >"${configPath}02_dokodemodoor_inbounds_${value}.json"
        done
        [[ "$(corePortListExtra)" == $'1:2053\n2:2083 默认' ]]
        [[ "$(corePortResolveByIndex 2)" == 2083 ]]
    )
    listenerFile="${configPath}07_VLESS_vision_reality_inbounds.json"
    defaultFile="${configPath}02_dokodemodoor_inbounds_2053_default.json"
    [[ "$(corePortParseList '02053,2053, 2083,,')" == $'2053\n2083' ]]
    regressionExpectStatus 1 corePortParseList ', ,'
    regressionExpectStatus 1 corePortParseList '2053,bad'
    printf '%s\n' '{"inbounds":[{"port":8443},{"settings":{"clients":[{"id":"test-id","email":"main-Reality"}]}}]}' >"${listenerFile}"
    [[ "$(corePortForwardTarget)" == 8443 ]]
    corePortApplyReloadTransaction corePortWriteAddFiles 2053 02053 "$(corePortForwardTarget)"
    jq -e '.inbounds[0].port == 2053 and .inbounds[0].settings.port == 8443' "${defaultFile}" >/dev/null
    before=$(<"${defaultFile}")
    (
        # 多个默认入口不能按排序猜选，也不能产生订阅端口或覆盖配置。
        local duplicateFile="${configPath}02_dokodemodoor_inbounds_2083_default.json"
        local duplicateContent='{"inbounds":[{"port":2083,"settings":{"port":9443}}]}'
        local command output="${root}/ambiguous-default-result"
        local -a args
        printf '%s\n' "${duplicateContent}" >"${duplicateFile}"
        for command in corePortDefaultFile corePortForwardTarget corePortSubscriptionPort corePortWriteAddFiles; do
            args=()
            case "${command}" in
            corePortSubscriptionPort) args=(8443) ;;
            corePortWriteAddFiles) args=(2443 2443 8443) ;;
            esac
            regressionExpectStatus 1 "${command}" "${args[@]}" >"${output}"
            [[ ! -s "${output}" && "$(<"${defaultFile}")" == "${before}" &&
                "$(<"${duplicateFile}")" == "${duplicateContent}" &&
                ! -e "${configPath}02_dokodemodoor_inbounds_2443_default.json" &&
                ! -e "${configPath}02_dokodemodoor_inbounds_2053.json" ]]
        done
        rm "${duplicateFile}"
    )
    (
        # 默认入口不存在是空结果；枚举失败不能输出部分列表、回退端口或修改配置。
        local partial command output="${root}/lookup-result" status=1 fixtureDefault=${defaultFile}
        local -a args
        corePortManagedFilesByPattern() {
            [[ -z "${partial}" ]] || printf '%s\n' "${fixtureDefault}"
            return "${status}"
        }
        for partial in '' true; do
            for command in corePortListExtra corePortResolveByIndex corePortDefaultFile corePortForwardTarget corePortSubscriptionPort corePortWriteAddFiles; do
                args=()
                case "${command}" in
                corePortResolveByIndex) args=(1) ;;
                corePortSubscriptionPort) args=(8443) ;;
                corePortWriteAddFiles) args=(2443 2443 8443) ;;
                esac
                regressionExpectStatus 1 "${command}" "${args[@]}" >"${output}"
                [[ ! -s "${output}" && "$(<"${defaultFile}")" == "${before}" && ! -e "${configPath}02_dokodemodoor_inbounds_2443_default.json" ]]
            done
        done
        partial=
        status=0
        corePortDefaultFile >"${output}"
        [[ ! -s "${output}" && "$(corePortForwardTarget)" == 8443 && "$(corePortSubscriptionPort 8443)" == 8443 ]]
    )
    (
        # 枚举失败不能先处理部分输出，也不能在无备份时删除入口或重载核心。
        local partial= calls="${root}/enumeration-actions.log" backupDir="${root}/enumeration-backup"
        mkdir -p "${backupDir}"
        backupManagedFileToPath() { printf 'backup\n' >>"${calls}"; }
        restoreManagedFileFromBackup() { printf 'restore\n' >>"${calls}"; }
        removeManagedFileIfPresent() { printf 'remove\n' >>"${calls}"; }
        runServiceAction() { printf 'reload\n' >>"${calls}"; }
        jq() { printf 'validate\n' >>"${calls}"; }
        corePortManagedFilesByPattern() {
            [[ -z "${partial}" ]] || printf '%s\n' "${defaultFile}"
            return 1
        }
        for partial in '' true; do
            regressionExpectStatus 1 corePortApplyReloadTransaction corePortRemove 2053
            regressionExpectStatus 1 corePortRollbackFiles "${backupDir}"
            regressionExpectStatus 1 corePortValidateFiles
            [[ "$(<"${defaultFile}")" == "${before}" && ! -e "${calls}" ]]
        done
    )
    (
        # find 的失败必须穿过排序管道，不依赖调用方是否开启 pipefail。
        set +o pipefail
        find() { printf '%s\n' "${defaultFile}"; return 1; }
        regressionExpectStatus 1 corePortManagedFilesByPattern '02_dokodemodoor_inbounds_*.json' >/dev/null
    )
    regressionExpectStatus 1 corePortApplyReloadTransaction corePortWriteAddFiles 2443 9999 8443
    regressionExpectStatus 1 corePortApplyReloadTransaction corePortWriteAddFiles 8443 8443 8443
    [[ "$(<"${defaultFile}")" == "${before}" && ! -e "${configPath}02_dokodemodoor_inbounds_2443.json" ]]
    printf '%s\n' '{"inbounds":[{"port":2053,"settings":{"port":9443}}]}' >"${configPath}02_dokodemodoor_inbounds_2053.json"
    regressionExpectStatus 1 corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 8443
    [[ "$(<"${defaultFile}")" == "${before}" ]]
    jq -e '.inbounds[0].settings.port == 9443' "${configPath}02_dokodemodoor_inbounds_2053.json" >/dev/null
    rm "${configPath}02_dokodemodoor_inbounds_2053.json"
    corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 8443
    [[ -f "${configPath}02_dokodemodoor_inbounds_2053.json" && ! -e "${defaultFile}" ]]
    [[ "$(corePortSubscriptionPort 8443)" == 2443 && "$(corePortSubscriptionPort 443)" == 443 ]]
    (
        # 订阅端口一次读取；空值、非法字段和解析失败仍不替换回退端口。
        local defaultFile content reads="${root}/subscription-port-reads.log" value
        defaultFile=$(corePortDefaultFile)
        content=$(<"${defaultFile}")
        jq() { printf 'jq\n' >>"${reads}"; command jq "$@"; }
        [[ "$(corePortSubscriptionPort 8443)" == 2443 && "$(wc -l <"${reads}")" == 1 ]]
        printf '%s\n' '{"inbounds":[{"port":"2443","settings":{"port":"8443"}}]}' >"${defaultFile}"
        [[ "$(corePortSubscriptionPort 8443)" == 2443 ]]
        for value in '{"inbounds":[{"port":2443}]}' \
            '{"inbounds":[{"settings":{"port":8443}}]}' \
            '{"inbounds":[{"port":2443,"settings":{"port":{}}}]}' \
            '{"inbounds":[{"port":2443,"settings":{"port":"8443\t2053\n"}}]}'; do
            printf '%s\n' "${value}" >"${defaultFile}"
            [[ "$(corePortSubscriptionPort 8443 443)" == 443 ]]
        done
        printf '%s\n%s\n' \
            '{"inbounds":[{"port":2443,"settings":{"port":8443}}]}' \
            '{"inbounds":[{"port":2999,"settings":{"port":8443}}]}' >"${defaultFile}"
        [[ "$(corePortSubscriptionPort 8443 443)" == 443 ]]
        printf '{' >"${defaultFile}"
        regressionExpectStatus 1 corePortSubscriptionPort 8443 443
        printf '%s\n' "${content}" >"${defaultFile}"
    )
    corePortApplyReloadTransaction corePortWriteAddFiles 2666 '' 8443
    [[ "$(corePortSubscriptionPort 8443)" == 2443 ]]
    corePortApplyReloadTransaction corePortWriteAddFiles 2443 '' 8443
    [[ "$(corePortSubscriptionPort 8443)" == 2443 ]]
    corePortApplyReloadTransaction corePortWriteAddFiles 2777 8443 8443
    defaultFile=$(corePortDefaultFile)
    [[ -z "${defaultFile}" && -f "${configPath}02_dokodemodoor_inbounds_2443.json" ]]
    [[ "$(corePortSubscriptionPort 8443)" == 8443 ]]
    printf '%s\n' '{"inbounds":[{"port":9443,"settings":{"clients":[{"id":"test-id","email":"main-XHTTP"}]}}]}' >"${configPath}12_VLESS_XHTTP_inbounds.json"
    regressionExpectStatus 1 corePortForwardTarget
    corePortApplyReloadTransaction corePortWriteAddFiles 2053 2053 8443
    [[ "$(corePortForwardTarget)" == 8443 ]]

    # 默认别名只覆盖它转发的协议，不能误改其它协议或 443 共存的回落。
    currentProtocolHas() { [[ "${installedIds}" == *",$1,"* ]]; }
    subscribeSectionTitle() { :; }
    subscribeAccountTitle() { :; }
    realityStreamPublicPortForProtocol() { printf '443\n'; }
    realityEntryHost() { printf 'entry.example.com\n'; }
    xrayRealityXHTTPSetting() { printf '/xhttp\n'; }
    defaultBase64Code() { printf '%s:%s\n' "$1" "$2" >>"${root}/nodes"; }
    showVlessRealityAccountsFromConfig 1 "${listenerFile}" 8443
    grep -qx 'vlessReality:2053' "${root}/nodes"
    installedIds=,2,
    local xrayVLESSRealityXHTTPort=9443 currentCDNAddress= currentPath=xhttp
    corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 9443
    showVlessRealityXHTTPAccounts
    grep -qx 'vlessXHTTP:2443' "${root}/nodes"
    printf '%s\n' '{"inbounds":[{"port":10443,"settings":{"clients":[{"id":"test-id","email":"main-gRPC"}]}}]}' >"${configPath}08_VLESS_vision_gRPC_inbounds.json"
    corePortApplyReloadTransaction corePortWriteAddFiles 2666 2666 10443
    showVlessRealityGrpcAccountsFromConfig "${configPath}08_VLESS_vision_gRPC_inbounds.json" 10443 sni.example.com key ''
    grep -qx 'vlessRealityGRPC:2666' "${root}/nodes"
    [[ "$(corePortSubscriptionPort 8443 443)" == 443 ]]
    : >"${root}/nodes"
    corePortApplyReloadTransaction corePortWriteAddFiles 2777 10443 10443
    showVlessRealityGrpcAccountsFromConfig "${configPath}08_VLESS_vision_gRPC_inbounds.json" 10443 sni.example.com key ''
    grep -qx 'vlessRealityGRPC:10443' "${root}/nodes"
)

runProtocolEntryMenuSyncRegression() (
    local log="${TMP_DIR}/protocol-entry-sync.log" input expected choice inputFd unread refreshStatus=0 transactionStatus=0
    local hysteriaPort= failNetwork= existingNetwork=
    local PADM_SKIP_CONTROLLER_REFRESH= PADM_CONTROL_SERVER=
    coreInstallType=1
    AUTO_INSTALL=
    echoContent() { :; }
    menuLine() { :; }
    menuClose() { :; }
    statusCard() { :; }
    readInstallType() { :; }
    readSingBoxConfig() { :; }
    errorCard() { printf 'error:%s\n' "$1" >>"${log}"; }
    corePortListExtra() { :; }
    corePortForwardTarget() { printf '443\n'; }
    corePortResolveByIndex() { printf '2053\n'; }
    allowPort() {
        PADM_LAST_ALLOW_PORT_ADDED=true
        [[ "${existingNetwork}" != "${2:-tcp}" ]] || PADM_LAST_ALLOW_PORT_ADDED=false
        printf 'allow:%s:%s\n' "$1" "${2:-tcp}" >>"${log}"
        [[ "${failNetwork}" != "${2:-tcp}" ]]
    }
    denyPort() { printf 'deny:%s:%s\n' "$1" "${2:-tcp}" >>"${log}"; return "${denyStatus:-0}"; }
    corePortApplyReloadTransaction() { printf 'apply:%s\n' "$1" >>"${log}"; return "${transactionStatus}"; }
    refreshProtocolSubscriptions() { printf 'refresh\n' >>"${log}"; return "${refreshStatus}"; }
    subscriptionNotifyControllerRefresh() { printf 'notify\n' >>"${log}"; return 1; }
    (
        # 读取失败不能消费菜单输入，更不能开放端口。
        local step reader
        for step in readInstallType readSingBoxConfig; do
            for reader in readInstallType readSingBoxConfig; do
                eval "${reader}() { [[ '${reader}' != '${step}' ]]; }"
            done
            exec {inputFd}<<< sentinel
            regressionExpectStatus 1 addCorePort <&"${inputFd}" || return 1
            read -r unread <&"${inputFd}"
            exec {inputFd}<&-
            [[ "${unread}" == sentinel && ! -e "${log}" ]] || return 1
        done
    ) || return 1
    (
        # 安装 wrapper 的局部变量返回后失效，新增入口必须采用实际磁盘状态。
        source "${PROJECT_ROOT}/shell/core/state.sh"
        local root="${TMP_DIR}/entry-live-state" configPath singBoxConfigPath hysteriaPort= invalidFile
        export PADM_XRAY_BINARY=/bin/true PADM_XRAY_CONF_DIR="${root}/xray" \
            PADM_SINGBOX_BINARY=/bin/true PADM_SINGBOX_CONFIG_DIR="${root}/sing-box"
        mkdir -p "${PADM_XRAY_CONF_DIR}" "${PADM_SINGBOX_CONFIG_DIR}"
        printf '%s\n' '{"inbounds":[{"port":443,"settings":{"clients":[{"id":"test"}]},"streamSettings":{"network":"xhttp","xhttpSettings":{"path":"/xhttp"}}}]}' \
            >"${PADM_XRAY_CONF_DIR}/12_VLESS_XHTTP_inbounds.json"
        printf '%s\n' '{"inbounds":[{"listen_port":16295}]}' >"${PADM_SINGBOX_CONFIG_DIR}/06_hysteria2_inbounds.json"
        corePortApplyReloadTransaction() { "$@"; }
        addCorePort <<< $'2\n2053\n2053\n4' || return 1
        grep -qx 'allow:2053:udp' "${log}" || return 1
        jq -e '.inbounds[0].settings.port == 16295' "${configPath}02_dokodemodoor_inbounds_hysteria_2053.json" >/dev/null || return 1
        rm "${PADM_SINGBOX_CONFIG_DIR}/06_hysteria2_inbounds.json"
        hysteriaPort=16295
        : >"${log}"
        addCorePort <<< $'2\n2061\n\n4' || return 1
        ! grep -q ':udp$' "${log}" || return 1
        [[ -z "${hysteriaPort}" && ! -e "${configPath}02_dokodemodoor_inbounds_hysteria_2061.json" ]] || return 1
        for invalidFile in 06_hysteria2_inbounds.json 09_tuic_inbounds.json; do
            printf '{' >"${PADM_SINGBOX_CONFIG_DIR}/${invalidFile}"
            : >"${log}"
            exec {inputFd}<<< sentinel
            regressionExpectStatus 1 addCorePort <&"${inputFd}" || return 1
            read -r unread <&"${inputFd}"
            exec {inputFd}<&-
            [[ "${unread}" == sentinel && ! -s "${log}" ]] || return 1
            rm "${PADM_SINGBOX_CONFIG_DIR}/${invalidFile}"
        done
    ) || return 1
    rm -f "${log}"
    # 无效新增列表不能继续读取默认端口或修改防火墙、配置和订阅。
    exec {inputFd}<<< $'2\ninvalid\nsentinel'
    regressionExpectStatus 1 addCorePort <&"${inputFd}"
    read -r unread <&"${inputFd}"
    exec {inputFd}<&-
    [[ "${unread}" == sentinel && "$(<"${log}")" == 'error:端口格式错误' ]]
    for hysteriaPort in '' 16295; do
        for choice in 2 3; do
            if [[ "${choice}" == 2 ]]; then
                input=$'2\n2053\n2053\n4'
                expected='allow:2053:tcp'
                [[ -z "${hysteriaPort}" ]] || expected+=$'\nallow:2053:udp'
                expected+=$'\napply:corePortWriteAddFiles\nrefresh\nnotify'
            else
                input=$'3\n1\n4'
                expected=$'apply:corePortRemove\ndeny:2053:tcp\ndeny:2053:udp\nrefresh\nnotify'
            fi
            : >"${log}"
            refreshStatus=0
            addCorePort <<<"${input}"
            [[ "$(<"${log}")" == "${expected}" ]]
            : >"${log}"
            refreshStatus=1
            regressionExpectStatus 1 addCorePort <<<"${input}"
            [[ "$(<"${log}")" == "${expected%$'\nnotify'}"$'\nerror:入口端口已生效，但订阅刷新失败，请手动刷新订阅' ]]
        done
        transactionStatus=1
        for existingNetwork in '' tcp; do
            : >"${log}"
            regressionExpectStatus 1 addCorePort <<< $'2\n2053\n2053'
            expected='allow:2053:tcp'
            [[ -z "${hysteriaPort}" ]] || expected+=$'\nallow:2053:udp'
            [[ -n "${existingNetwork}" ]] || expected+=$'\ndeny:2053:tcp'
            [[ -z "${hysteriaPort}" ]] || expected+=$'\ndeny:2053:udp'
            [[ "$(grep -E '^(allow|deny):' "${log}")" == "${expected}" ]]
            ! grep -qx refresh "${log}"
            ! grep -qx notify "${log}"
        done
        existingNetwork=
        transactionStatus=0
    done
    failNetwork=udp
    for existingNetwork in '' tcp; do
        : >"${log}"
        regressionExpectStatus 1 addCorePort <<< $'2\n2061\n2061'
        expected=$'allow:2061:tcp\nallow:2061:udp'
        [[ -n "${existingNetwork}" ]] || expected+=$'\ndeny:2061:tcp'
        [[ "$(<"${log}")" == "${expected}" ]]
    done
    hysteriaPort=
    existingNetwork=
    failNetwork=tcp
    : >"${log}"
    regressionExpectStatus 1 addCorePort <<< $'2\n2061\n2061'
    [[ "$(<"${log}")" == 'allow:2061:tcp' ]]
    failNetwork=
    : >"${log}"
    transactionStatus=0
    refreshStatus=0
    local denyStatus=1
    regressionExpectStatus 1 addCorePort <<< $'3\n1\n4'
    [[ "$(<"${log}")" == $'apply:corePortRemove\ndeny:2053:tcp\ndeny:2053:udp\nerror:入口端口配置已删除，但防火墙规则回收失败，请检查防火墙状态\nrefresh\nnotify' ]]
    denyStatus=0
    : >"${log}"
    PADM_SKIP_CONTROLLER_REFRESH=1 addCorePort <<< $'3\n1\n4'
    [[ "$(<"${log}")" == $'apply:corePortRemove\ndeny:2053:tcp\ndeny:2053:udp\nrefresh' ]]
    : >"${log}"
    PADM_CONTROL_SERVER=1 addCorePort <<< $'3\n1\n4'
    [[ "$(<"${log}")" == $'apply:corePortRemove\ndeny:2053:tcp\ndeny:2053:udp\nrefresh' ]]
    : >"${log}"
    corePortResolveByIndex() { :; }
    addCorePort <<< $'3\nbad\n4'
    [[ ! -s "${log}" ]]
    corePortResolveByIndex() { return 1; }
    regressionExpectStatus 1 addCorePort <<< $'3\n1'
    [[ "$(<"${log}")" == 'error:入口端口列表读取失败' ]]
    corePortListExtra() { return 1; }
    for choice in 1 3; do
        : >"${log}"
        regressionExpectStatus 1 addCorePort <<<"${choice}"
        [[ "$(<"${log}")" == 'error:入口端口列表读取失败' ]]
    done
)

runProtocolCapabilitiesRegression() {
    runRegressionStep protocol-entry-config-update runProtocolEntryConfigUpdateRegression
    runRegressionStep protocol-entry-port runProtocolEntryPortRegression
    runRegressionStep protocol-entry-menu-sync runProtocolEntryMenuSyncRegression
    runRegressionStep protocol-config-ownership runProtocolConfigOwnershipRegression
    runRegressionStep protocol-capability-registry runProtocolCapabilityRegistryRegression
    runRegressionStep protocol-capability-menu-core runProtocolCapabilityMenuAndCoreRegression
    runRegressionStep protocol-capability-nginx-topology runProtocolCapabilityNginxTopologyRegression
    runRegressionStep protocol-capability-templates runProtocolCapabilityTemplateRegression
    runRegressionStep hysteria2-capability runHysteria2CapabilityRegression
    runRegressionStep subscription-capability-dispatch runSubscriptionCapabilityDispatchRegression
    runRegressionStep install-status-vless-encryption runInstallStatusVlessEncryptionRegression
    runRegressionStep singbox-plain-inbound-host-fallback runSingBoxPlainInboundHostFallbackRegression
    runRegressionStep xray-direct-tls-inbound-without-fallback runXrayDirectTlsInboundWithoutFallbackRegression
}
