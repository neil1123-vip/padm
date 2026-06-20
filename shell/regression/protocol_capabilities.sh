#!/usr/bin/env bash
set -euo pipefail

REGRESSION_ENTRY_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_ENTRY_DIR}/regression/bootstrap.sh"

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
    if ! jq -e '.[0].name == "main-shadowsocks" and .[0].password == "11111111-1111-4111-8111-111111111111"' >/dev/null <<<"${ssUsers}"; then
        printf 'assert-fail:sing-box Shadowsocks users should use name/password\n' >&2
        return 1
    fi
}

runHysteria2CapabilityRegression() {
    local coreTemplate="${PROJECT_ROOT}/shell/core/core_templates.sh"
    local oldSingBoxConfigPath="${singBoxConfigPath:-}"
    local configDir="${TMP_DIR}/hysteria2-conf/"
    local oldUpload="${hysteria2ClientUploadSpeed:-}"
    local oldDownload="${hysteria2ClientDownloadSpeed:-}"

    if ! grep -Fq '"up_mbps":${hysteria2ClientUploadSpeed}' "${coreTemplate}"; then
        printf 'assert-fail:hysteria2 template up_mbps should use upload speed\n' >&2
        return 1
    fi
    if ! grep -Fq '"down_mbps":${hysteria2ClientDownloadSpeed}' "${coreTemplate}"; then
        printf 'assert-fail:hysteria2 template down_mbps should use download speed\n' >&2
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
    assertEquals 75 "${hysteria2ClientUploadSpeed}" "hysteria2-read-upload"
    assertEquals 150 "${hysteria2ClientDownloadSpeed}" "hysteria2-read-download"

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
    if hysteria2SingBoxFieldSupported bbr_profile v1.13.13; then
        printf 'assert-fail:hysteria2 bbr_profile should require sing-box 1.14\n' >&2
        return 1
    fi

    singBoxConfigPath="${oldSingBoxConfigPath}"
    hysteria2ClientUploadSpeed="${oldUpload}"
    hysteria2ClientDownloadSpeed="${oldDownload}"
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
    assertEquals showTuicAccounts "$(subscriptionAccountDisplayFunction 31)" "account-display-fn:31"

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
}

runRegressionStep protocol-capability-registry runProtocolCapabilityRegistryRegression
runRegressionStep protocol-capability-menu-core runProtocolCapabilityMenuAndCoreRegression
runRegressionStep protocol-capability-nginx-topology runProtocolCapabilityNginxTopologyRegression
runRegressionStep protocol-capability-templates runProtocolCapabilityTemplateRegression
runRegressionStep hysteria2-capability runHysteria2CapabilityRegression
runRegressionStep subscription-capability-dispatch runSubscriptionCapabilityDispatchRegression
echo "protocol-capabilities-regression-ok"
