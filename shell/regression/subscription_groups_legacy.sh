#!/usr/bin/env bash
set -euo pipefail

REGRESSION_ENTRY_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_ENTRY_DIR}/regression/bootstrap.sh"

runCleanupTrapRegression() {
    local tmpDir exitProbe intProbe intOutput termProbe termOutput

    tmpDir=$(mktemp -d)
    exitProbe="${tmpDir}/exit.XXXXXX"
    intProbe="${tmpDir}/int.XXXXXX"
    termProbe="${tmpDir}/term.XXXXXX"
    intOutput="${tmpDir}/int.out"
    termOutput="${tmpDir}/term.out"
    bash -c 'source "$1"; padmCreateTempPath p "$2"; exit 0' _ "${PROJECT_ROOT}/shell/core/runtime.sh" "${exitProbe}"
    [[ ! -e "${exitProbe}" ]]
    set +e
    bash -c 'source "$1"; padmCreateTempPath p "$2"; kill -INT $$; exit 99' _ "${PROJECT_ROOT}/shell/core/runtime.sh" "${intProbe}" >"${intOutput}" 2>&1
    local intStatus=$?
    bash -c 'source "$1"; padmCreateTempPath p "$2"; kill -TERM $$; exit 99' _ "${PROJECT_ROOT}/shell/core/runtime.sh" "${termProbe}" >"${termOutput}" 2>&1
    local termStatus=$?
    set -e
    [[ ${intStatus} -eq 130 ]]
    [[ ${termStatus} -eq 143 ]]
    [[ ! -e "${intProbe}" ]]
    [[ ! -e "${termProbe}" ]]
    rm -rf "${tmpDir}"
}

realityTargetDetector() {
    printf '%s\n' fake-xray
}

currentRealityNetworkProfile() {
    printf '203.0.113.10\tAS64500\tExampleNet\n'
}

resolveRealityTargetIPv4() {
    printf '192.0.2.1\n'
}

lookupRealityTargetAsn() {
    case "$1" in
    198.51.100.*)
        printf 'AS64501\tRemoteNet\n'
        ;;
    *)
        printf 'AS64500\tExampleNet\n'
        ;;
    esac
}

REALITY_TLS_PING_ARGS_FILE="${TMP_DIR}/tls_ping_args.txt"
fake-xray() {
    [[ "$1" == "tls" && "$2" == "ping" ]]
    printf '%s\n' "$*" >>"${REALITY_TLS_PING_ARGS_FILE}"
    if [[ "$*" == *"fail.example.com"* || "$*" == *"fail-auto.example.com"* ]]; then
        return 1
    fi
    if [[ "${PADM_FAKE_XRAY_ONLY_IBM:-}" == "true" && "$*" != *"www.ibm.com"* ]]; then
        return 1
    fi
    if [[ "$*" == *"www.microsoft.com"* ]]; then
        printf 'Pinging with SNI\nTLS Post-Quantum key exchange: X25519MLKEM768\nTLS version: TLS 1.3\nCertificate chain total length: 8192\n'
        return 0
    fi
    printf 'Pinging with SNI\nTLS Post-Quantum key exchange: X25519MLKEM768\nTLS version: TLS 1.3\nCertificate chain total length: 4096\n'
}

jq() {
    if [[ "$#" -eq 0 ]]; then
        command jq . >/dev/null
    else
        command jq "$@"
    fi
}

readInstallType() {
    coreInstallType=${coreInstallType:-1}
}

SUBSCRIBE_CAPTURE_DIR="${TMP_DIR}/subscribe_local"
configPath="${TMP_DIR}/xray-conf/"
singBoxConfigPath="${TMP_DIR}/sing-box-conf/"
runRoutingRegression() {
    mkdir -p "${configPath}" "${singBoxConfigPath}"
    cat >"${singBoxConfigPath}dlc.dat_plain.yml" <<'YAML'
- name: openai
YAML
    rulesJson=$(initSingBoxRules "openai,example.com,full:api.example.com" "regression")
    jq -e '.ruleSet[0].tag == "geosite_openai_regression" and .suffixRules == ["example.com"] and .domainRules == ["api.example.com"]' <<<"${rulesJson}" >/dev/null
    local splitDomainRules splitSuffixRules splitRuleSet splitRuleSetTag
    if splitSingBoxRules '{bad-json' splitDomainRules splitSuffixRules splitRuleSet splitRuleSetTag 2>/dev/null; then
        return 1
    fi
    addSingBoxRouteRule "test_outbound" "openai,example.com,full:api.example.com" "test_route"
    jq -e '
      .route.rules[0].rule_set == ["geosite_openai_test_route"] and
      .route.rules[0].domain_suffix == ["example.com"] and
      .route.rules[0].domain == ["api.example.com"] and
      (.route.rules[0].domain_regex | not) and
      .route.rule_set[0].url == "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-openai.srs"
    ' "${singBoxConfigPath}test_route.json" >/dev/null
    [[ "$(getDLCMatchedRuleValue example.com "${singBoxConfigPath}")" == "domain:example.com" ]]
    [[ "$(getDLCMatchedRuleValue full:api.example.com "${singBoxConfigPath}")" == "full:api.example.com" ]]
    [[ "$(getDLCMatchedRuleValue openai "${singBoxConfigPath}")" == "geosite:openai" ]]
    ! grep -q 'regexp:' < <(getDLCMatchedRuleValue example.com "${singBoxConfigPath}")
    originalContent=$(<"${singBoxConfigPath}test_route.json")
    if updateRoutingJsonConfig "${singBoxConfigPath}test_route.json" '.route.rules = [' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${singBoxConfigPath}test_route.json")" == "${originalContent}" ]]
    [[ ! -e "${singBoxConfigPath}test_route.json.tmp" ]]
    ! compgen -G "${singBoxConfigPath}.test_route.json.*" >/dev/null
    (
        autoRead() { printf -v "$3" 'y'; }
        printf '{bad-json\n' >"${singBoxConfigPath}bad_history_route.json"
        if addSingBoxRouteRule "test_outbound" "example.net" "bad_history_route" 2>/dev/null; then
            exit 1
        fi
    )
    rm -f "${singBoxConfigPath}bad_history_route.json"
    addSingBoxIPRouteRule "block_ip_outbound" "1.1.1.0/24,cn" "block_ip_route"
    jq -e '
      (.route.rules[0].ip_cidr | sort) == (["1.1.1.0/24", "geoip:cn"] | sort) and
      .route.rules[0].action == "reject"
    ' "${singBoxConfigPath}block_ip_route.json" >/dev/null
    printf '{bad-json\n' >"${singBoxConfigPath}bad_ip_route.json"
    if addSingBoxIPRouteRule "block_ip_outbound" "2.2.2.2" "bad_ip_route" 2>/dev/null; then
        return 1
    fi
    rm -f "${singBoxConfigPath}bad_ip_route.json"
    cat >"${singBoxConfigPath}block_ip_outbound_route.json" <<'JSON'
{"route":{"rules":[{"action":"reject","domain":["example.com"]},{"outbound":"keep_outbound","domain":["keep.example.com"]}]}}
JSON
    removeSingBoxRouteRule "block_ip_outbound"
    jq -e '
      (.route.rules | length) == 1 and
      .route.rules[0].outbound == "keep_outbound"
    ' "${singBoxConfigPath}block_ip_outbound_route.json" >/dev/null
    originalContent=$(<"${singBoxConfigPath}block_ip_outbound_route.json")
    if updateRoutingJsonConfig "${singBoxConfigPath}block_ip_outbound_route.json" '.route.rules = [' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${singBoxConfigPath}block_ip_outbound_route.json")" == "${originalContent}" ]]
    [[ ! -e "${singBoxConfigPath}block_ip_outbound_route.json.tmp" ]]
    printf '{bad-json\n' >"${singBoxConfigPath}block_ip_outbound_route.json"
    if removeSingBoxRouteRule "block_ip_outbound" 2>/dev/null; then
        return 1
    fi
    rm -f "${singBoxConfigPath}block_ip_outbound_route.json"
    addSingBoxGeoIPRouteRule "block_ip_outbound" "cn" "cn_block_ip_route"
    jq -e '
      .route.rules[0].rule_set == ["geoip_cn_cn_block_ip_route"] and
      .route.rules[0].action == "reject" and
      .route.rule_set[0].format == "binary"
    ' "${singBoxConfigPath}cn_block_ip_route.json" >/dev/null
    addSingBoxOutbound "01_direct_outbound"
    jq -e '.outbounds[0].tag == "01_direct_outbound"' "${singBoxConfigPath}01_direct_outbound.json" >/dev/null
    addSingBoxOutbound "IPv6_out"
    jq -e '.outbounds[0].domain_resolver.server == "padm-local" and .outbounds[0].domain_resolver.strategy == "ipv6_only" and (.outbounds[0].domain_strategy | not)' "${singBoxConfigPath}IPv6_out.json" >/dev/null
    addSingBoxOutbound "block_domain_outbound"
    [[ ! -e "${singBoxConfigPath}block_domain_outbound.json" ]]
    addXrayOutbound "IPv4_outbound"
    jq -e '
      .outbounds[0].protocol == "freedom" and
      .outbounds[0].settings.domainStrategy == "ForceIPv4" and
      .outbounds[0].tag == "IPv4_outbound"
    ' "${configPath}IPv4_outbound.json" >/dev/null
    addXrayOutbound "direct_outbound"
    jq -e '
      .outbounds[0].protocol == "freedom" and
      .outbounds[0].settings.domainStrategy == "UseIP"
    ' "${configPath}direct_outbound.json" >/dev/null
    addXrayOutbound "blackhole_outbound"
    jq -e '.outbounds[0].protocol == "blackhole"' "${configPath}blackhole_outbound.json" >/dev/null
    socks5RoutingOutboundIP="127.0.0.1"
    socks5RoutingOutboundPort=1080
    socks5RoutingOutboundUserName="user"
    socks5RoutingOutboundPassword="pass"
    addXrayOutbound "socks5_outbound"
    jq -e '
      .outbounds[0].protocol == "socks" and
      .outbounds[0].settings.servers[0].address == "127.0.0.1" and
      .outbounds[0].settings.servers[0].port == 1080
    ' "${configPath}socks5_outbound.json" >/dev/null
    writeRoutingJsonConfig "${configPath}socks5_outbound.json" <<'JSON'
{"outbounds":[{"protocol":"socks","tag":"old"}]}
JSON
    socks5RoutingOutboundPort=
    if addXrayOutbound "socks5_outbound" 2>/dev/null; then
        return 1
    fi
    jq -e '.outbounds[0].tag == "old"' "${configPath}socks5_outbound.json" >/dev/null
    [[ ! -e "${configPath}socks5_outbound.json.tmp" ]]
    writeSocks5InboundConfig "${singBoxConfigPath}20_socks5_inbounds.json" 1081 "socks-user"
    jq -e '
      .inbounds[0].listen_port == 1081 and
      .inbounds[0].users[0].username == "socks-user" and
      .inbounds[0].users[0].password == "socks-user"
    ' "${singBoxConfigPath}20_socks5_inbounds.json" >/dev/null
    originalContent=$(<"${singBoxConfigPath}20_socks5_inbounds.json")
    if writeSocks5InboundConfig "${singBoxConfigPath}20_socks5_inbounds.json" '' "broken" 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${singBoxConfigPath}20_socks5_inbounds.json")" == "${originalContent}" ]]
    [[ ! -e "${singBoxConfigPath}20_socks5_inbounds.json.tmp" ]]
    readConfigWarpReg() {
        address="172.16.0.2/32"
        secretKeyWarpReg="warp-secret"
        publicKeyWarpReg="warp-public"
        if [[ -z ${reservedWarpReg+x} ]]; then
            reservedWarpReg='[1,2,3]'
        fi
    }
    addSingBoxWireGuardEndpoints IPv4
    jq -e '
      .endpoints[0].tag == "wireguard_endpoints_IPv4" and
      .endpoints[0].private_key == "warp-secret" and
      .endpoints[0].peers[0].reserved == [1,2,3]
    ' "${singBoxConfigPath}wireguard_endpoints_IPv4.json" >/dev/null
    originalContent=$(<"${singBoxConfigPath}wireguard_endpoints_IPv4.json")
    reservedWarpReg=
    if addSingBoxWireGuardEndpoints IPv4 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${singBoxConfigPath}wireguard_endpoints_IPv4.json")" == "${originalContent}" ]]
    [[ ! -e "${singBoxConfigPath}wireguard_endpoints_IPv4.json.tmp" ]]
    unset -f readConfigWarpReg
    hysteriaPort=23456
    setSniffRouting
    jq -e '.route.rules[0].action == "sniff"' "${singBoxConfigPath}sniff.json" >/dev/null
    setStrategyRouting socks5_inbound ipv6_only
    jq -e '
      .route.rules[0].inbound == "socks5_inbound" and
      .route.rules[0].strategy == "ipv6_only"
    ' "${singBoxConfigPath}strategy_ipv6_only_socks5_inbound.json" >/dev/null
    writeRoutingJsonConfig "${singBoxConfigPath}socks5_outbound.json" <<'JSON'
{"outbounds":[{"type":"socks","tag":"old"}]}
JSON
    if writeRoutingJsonConfig "${singBoxConfigPath}socks5_outbound.json" <<'JSON' 2>/dev/null
{"outbounds":[{"type":"socks","tag":"broken","server_port":}]}
JSON
    then
        return 1
    fi
    jq -e '.outbounds[0].tag == "old"' "${singBoxConfigPath}socks5_outbound.json" >/dev/null
    [[ ! -e "${singBoxConfigPath}socks5_outbound.json.tmp" ]]
    ! compgen -G "${singBoxConfigPath}.socks5_outbound.json.*" >/dev/null
    cat >"${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json" <<'JSON'
{"inbounds":[{"tls":{"reality":{"handshake":{"server":"nodejs.org"}}}}]}
JSON
    cat >"${singBoxConfigPath}socks5_outbound.json" <<'JSON'
{"outbounds":[{"type":"socks","tag":"socks5_outbound","server":"example.net","server_port":1080}]}
JSON
    addSingBoxDNSConfig "1.1.1.1" "openai,example.com"
    jq -e '
      .dns.rules[0].rule_set == ["geosite_openai_dns"] and
      .dns.rules[0].domain_suffix == ["example.com"] and
      (.dns.servers[] | select(.tag == "padm-local" and .type == "local")) and
      (.dns.servers[] | select(.tag == "padm-dnsRouting" and .type == "udp" and .server == "1.1.1.1")) and
      .route.default_domain_resolver == "padm-local" and
      (.route.rules[]? | select(.action == "resolve" and .server == "padm-dnsRouting")) and
      (.dns.rules[0].domain_regex | not) and
      .route.rule_set[0].format == "binary"
    ' "${singBoxConfigPath}dns.json" >/dev/null
    jq -e '.inbounds[0].tls.reality.handshake.domain_resolver? | not' "${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json" >/dev/null
    jq -e '.outbounds[0].domain_resolver? | not' "${singBoxConfigPath}socks5_outbound.json" >/dev/null
    addSingBoxDNSConfig "203.0.113.10" "example.org" "predefined"
    jq -e '
      .dns.rules[0].domain_suffix == ["example.org"] and
      .route.default_domain_resolver == "padm-local" and
      (.route.rules[]? | select(.action == "resolve" and .server == "padm-hosts")) and
      (.dns.rules[0].domain_regex | not) and
      (.dns.servers[] | select(.tag == "padm-hosts") | .predefined["example.org"] == "203.0.113.10")
    ' "${singBoxConfigPath}dns.json" >/dev/null
    printf '{"dns":{"servers":["old-xray"]}}\n' >"${configPath}11_dns.json"
    if writeRoutingJsonConfig "${configPath}11_dns.json" <<'JSON' 2>/dev/null
{"dns":{"servers":[}
JSON
    then
        return 1
    fi
    jq -e '.dns.servers == ["old-xray"]' "${configPath}11_dns.json" >/dev/null
    [[ ! -e "${configPath}11_dns.json.tmp" ]]
    ! compgen -G "${configPath}.11_dns.json.*" >/dev/null
    printf '{"dns":{"servers":["old-sing"]}}\n' >"${singBoxConfigPath}dns.json"
    if writeRoutingJsonConfig "${singBoxConfigPath}dns.json" <<'JSON' 2>/dev/null
{"dns":{"servers":[}
JSON
    then
        return 1
    fi
    jq -e '.dns.servers == ["old-sing"]' "${singBoxConfigPath}dns.json" >/dev/null
    [[ ! -e "${singBoxConfigPath}dns.json.tmp" ]]
    coreInstallType=1
    printf '{"dns":{"servers":["custom"]}}\n' >"${configPath}11_dns.json"
    ( removeUnlockDNS ) || return 1
    jq -e '.dns.servers == ["localhost"]' "${configPath}11_dns.json" >/dev/null
    coreInstallType=2
    printf '{"dns":{"servers":["custom"]}}\n' >"${singBoxConfigPath}dns.json"
    ( removeUnlockSNI ) || return 1
    jq -e '.dns.servers[0].type == "local"' "${singBoxConfigPath}dns.json" >/dev/null
    coreInstallType=1
    printf '{"inbounds":[{"sniffing":{"destOverride":["http"]},"settings":{}}]}
' >"${configPath}02_sniffing_inbounds.json"
    printf '{"inbounds":[{"settings":{}}]}
' >"${configPath}03_sniffing_inbounds.json"
    originalContent=$(<"${configPath}02_sniffing_inbounds.json")
    if updateRoutingJsonConfig "${configPath}02_sniffing_inbounds.json" '.inbounds[0].sniffing = [' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${configPath}02_sniffing_inbounds.json")" == "${originalContent}" ]]
    [[ ! -e "${configPath}02_sniffing_inbounds.json.tmp" ]]
    installSniffing
    jq -e '
      .inbounds[0].sniffing.enabled == true and
      (.inbounds[0].sniffing.destOverride | sort) == ["http", "quic", "tls"]
    ' "${configPath}02_sniffing_inbounds.json" >/dev/null
    jq -e '
      .inbounds[0].sniffing.enabled == true and
      (.inbounds[0].sniffing.destOverride | sort) == ["http", "quic", "tls"]
    ' "${configPath}03_sniffing_inbounds.json" >/dev/null
    updateRoutingJsonConfig "${configPath}02_sniffing_inbounds.json" 'del(.inbounds[0].sniffing)'
    updateRoutingJsonConfig "${configPath}03_sniffing_inbounds.json" 'del(.inbounds[0].sniffing)'
    jq -e '.inbounds[0].sniffing | not' "${configPath}02_sniffing_inbounds.json" >/dev/null
    jq -e '.inbounds[0].sniffing | not' "${configPath}03_sniffing_inbounds.json" >/dev/null
    coreInstallType=
    cat >"${configPath}09_routing.json" <<'JSON'
{"routing":{"rules":[{"outboundTag":"old","domain":["domain:old.example"]}]}}
JSON
    originalContent=$(<"${configPath}09_routing.json")
    if updateRoutingJsonConfig "${configPath}09_routing.json" '.routing.rules = [' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${configPath}09_routing.json")" == "${originalContent}" ]]
    [[ ! -e "${configPath}09_routing.json.tmp" ]]
    printf '{bad-json\n' >"${configPath}09_routing.json"
    if unInstallRouting blackhole_out outboundTag 2>/dev/null; then
        return 1
    fi
    cat >"${configPath}09_routing.json" <<'JSON'
{"routing":{"rules":[{"outboundTag":"blackhole_out","domain":["geosite:cn"]},{"outboundTag":"blackhole_ip_out","ip":["geoip:cn"]},{"outboundTag":"keep_out","domain":["domain:keep.example"]}]}}
JSON
    removeXrayRegionalRules
    jq -e '
      (.routing.rules | length) == 1 and
      .routing.rules[0].outboundTag == "keep_out"
    ' "${configPath}09_routing.json" >/dev/null
    addXrayBTBlockRule
    jq -e '.routing.rules[] | select(.outboundTag == "blackhole_out" and (.protocol | index("bittorrent")))' "${configPath}09_routing.json" >/dev/null
    coreInstallType=2
    mkdir -p "${singBoxConfigPath}"
    addSingBoxBTBlockRule
    hasSingBoxBTBlockRule
    accessControlBackupCreate
    [[ -d "$(accessControlBackupDir)/xray" ]]
    [[ -d "$(accessControlBackupDir)/sing-box" ]]
    coreInstallType=1
    cat >"${configPath}09_routing.json" <<'JSON'
{"routing":{"rules":[]}}
JSON
    addXrayRouting blackhole_out outboundTag "example.com"
    jq -e '.routing.rules[] | select(.outboundTag == "blackhole_out") | .domain == ["domain:example.com"]' "${configPath}09_routing.json" >/dev/null
    addXrayRouting allow_domain_direct_outbound outboundTag "full:api.example.com" top
    jq -e '.routing.rules[0].outboundTag == "allow_domain_direct_outbound" and (.routing.rules[0].domain | index("full:api.example.com"))' "${configPath}09_routing.json" >/dev/null
    addXrayIPRouting blackhole_ip_out outboundTag "cn,1.1.1.0/24"
    jq -e '.routing.rules[] | select(.outboundTag == "blackhole_ip_out") | .ip == ["geoip:cn", "1.1.1.0/24"]' "${configPath}09_routing.json" >/dev/null
    [[ "$(validateAccessIPList '1.1.1.1, 1.1.1.1,2001:db8::/32,cn')" == "1.1.1.1,2001:db8::/32,cn" ]]
    ! validateAccessIPList 'bad-ip' >/dev/null
}

runAccessControlFailureReturnCase() {
    (
    local mode=$1
    local action=$2
    local root="${TMP_DIR}/access-control-return-${mode}"
    local backupMarker="${root}/backup"
    local addMarker="${root}/add"
    local outboundMarker="${root}/outbound"
    local uninstallMarker="${root}/uninstall"
    local removeMarker="${root}/remove"
    local restoreMarker="${root}/restore"
    local cleanupMarker="${root}/cleanup"
    local reloadMarker="${root}/reload"
    local successMarker="${root}/success"
    local removeChoice=1
    local rc

    configPath="${root}/xray/"
    singBoxConfigPath=
    coreInstallType=1
    mkdir -p "${configPath}"

    errorCard() { return 0; }
    echoContent() { return 0; }
    menuLine() { return 0; }
    menuItem() { return 0; }
    menuDangerItem() { return 0; }
    menuReturnItem() { return 0; }
    menuClose() { return 0; }
    successCard() {
        printf 'success\n' >"${successMarker}"
        return 0
    }
    autoRead() {
        case "$1" in
        access_block_domains) printf -v "$3" 'example.com' ;;
        access_remove_menu) printf -v "$3" "${removeChoice}" ;;
        *) printf -v "$3" '' ;;
        esac
    }
    accessControlBackupCreate() {
        printf 'backup\n' >"${backupMarker}"
        [[ "${mode}" != "backup-fail" ]]
    }
    accessControlBackupRestore() {
        printf 'restore\n' >"${restoreMarker}"
        [[ "${mode}" != *"restore-fail" ]]
    }
    accessControlBackupCleanup() {
        printf 'cleanup\n' >"${cleanupMarker}"
        [[ "${mode}" != "cleanup-fail" ]]
    }
    addXrayRouting() {
        printf 'add\n' >"${addMarker}"
        [[ "${mode}" != "add-fail" ]]
    }
    addXrayOutbound() {
        printf 'outbound\n' >"${outboundMarker}"
        [[ "${mode}" != "outbound-fail" ]]
    }
    unInstallRouting() {
        printf 'uninstall\n' >"${uninstallMarker}"
        [[ "${mode}" != "uninstall-fail" ]]
    }
    removeXrayOutbound() {
        printf 'remove\n' >"${removeMarker}"
        [[ "${mode}" != "remove-fail" ]]
    }
    validateAccessControlConfig() {
        [[ "${mode}" != "validate-fail" && "${mode}" != "validate-restore-fail" ]]
    }
    reloadCore() {
        printf 'reload\n' >>"${reloadMarker}"
        [[ "${mode}" != "reload-fail" && "${mode}" != "reload-restore-fail" ]]
    }

    rm -f "${backupMarker}" "${addMarker}" "${outboundMarker}" "${uninstallMarker}" "${removeMarker}" "${restoreMarker}" "${cleanupMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    if [[ "${action}" == "remove" ]]; then
        removeAccessControlMenu >/dev/null 2>&1
    else
        addBlockedDomains >/dev/null 2>&1
    fi
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]

    case "${mode}" in
    backup-fail)
        [[ -e "${backupMarker}" ]]
        [[ ! -e "${addMarker}" ]]
        [[ ! -e "${reloadMarker}" ]]
        ;;
    add-fail)
        [[ -e "${backupMarker}" ]]
        [[ -e "${addMarker}" ]]
        [[ -e "${restoreMarker}" ]]
        [[ ! -e "${outboundMarker}" ]]
        [[ ! -e "${reloadMarker}" ]]
        ;;
    validate-fail)
        [[ -e "${backupMarker}" ]]
        [[ -e "${addMarker}" ]]
        [[ -e "${outboundMarker}" ]]
        [[ -e "${restoreMarker}" ]]
        [[ -e "${cleanupMarker}" ]]
        [[ ! -e "${reloadMarker}" ]]
        ;;
    validate-restore-fail)
        [[ -e "${backupMarker}" ]]
        [[ -e "${addMarker}" ]]
        [[ -e "${outboundMarker}" ]]
        [[ -e "${restoreMarker}" ]]
        [[ ! -e "${cleanupMarker}" ]]
        [[ ! -e "${reloadMarker}" ]]
        ;;
    reload-fail)
        [[ -e "${backupMarker}" ]]
        [[ -e "${addMarker}" ]]
        [[ -e "${outboundMarker}" ]]
        [[ -e "${restoreMarker}" ]]
        [[ -e "${cleanupMarker}" ]]
        [[ -e "${reloadMarker}" ]]
        [[ "$(wc -l <"${reloadMarker}")" == "2" ]]
        ;;
    reload-restore-fail)
        [[ -e "${backupMarker}" ]]
        [[ -e "${addMarker}" ]]
        [[ -e "${outboundMarker}" ]]
        [[ -e "${restoreMarker}" ]]
        [[ ! -e "${cleanupMarker}" ]]
        [[ -e "${reloadMarker}" ]]
        [[ "$(wc -l <"${reloadMarker}")" == "1" ]]
        ;;
    cleanup-fail)
        [[ -e "${backupMarker}" ]]
        [[ -e "${addMarker}" ]]
        [[ -e "${outboundMarker}" ]]
        [[ ! -e "${restoreMarker}" ]]
        [[ -e "${cleanupMarker}" ]]
        [[ -e "${reloadMarker}" ]]
        [[ "$(wc -l <"${reloadMarker}")" == "1" ]]
        ;;
    remove-fail)
        [[ -e "${backupMarker}" ]]
        [[ -e "${uninstallMarker}" ]]
        [[ -e "${removeMarker}" ]]
        [[ -e "${restoreMarker}" ]]
        [[ -e "${cleanupMarker}" ]]
        [[ ! -e "${reloadMarker}" ]]
        ;;
    esac
    [[ ! -e "${successMarker}" ]]
    )
}

runAccessControlFailureReturnRegression() {
    runAccessControlFailureReturnCase backup-fail add &&
        runAccessControlFailureReturnCase add-fail add &&
        runAccessControlFailureReturnCase validate-fail add &&
        runAccessControlFailureReturnCase validate-restore-fail add &&
        runAccessControlFailureReturnCase reload-fail add &&
        runAccessControlFailureReturnCase reload-restore-fail add &&
        runAccessControlFailureReturnCase cleanup-fail add &&
        runAccessControlFailureReturnCase remove-fail remove
}

runAccessControlConfigTransactionRegression() (
    local root="${TMP_DIR}/access-control-config-transaction"
    local statusLog="${root}/status.log"
    local rc reloadCalls=0

    configPath="${root}/xray/"
    singBoxConfigPath="${root}/sing-box/"
    PADM_ACCESS_CONTROL_BACKUP_DIR="${root}/backup"
    coreInstallType=1
    mkdir -p "${configPath}" "${singBoxConfigPath}"
    : >"${statusLog}"

    echoContent() { printf 'title:%s\n' "$*" >>"${statusLog}"; }
    menuLine() { printf 'menu:%s\n' "$*" >>"${statusLog}"; }
    menuClose() { printf 'close\n' >>"${statusLog}"; }
    errorCard() { printf 'error:%s\n' "$*" >>"${statusLog}"; }
    reloadCore() {
        reloadCalls=$((reloadCalls + 1))
        [[ "${reloadCalls}" -gt 1 ]]
    }

    cat >"${configPath}09_routing.json" <<'JSON'
{"routing":{"rules":[{"outboundTag":"old","domain":["domain:old.example"]}]}}
JSON
    cat >"${singBoxConfigPath}block_domain_route.json" <<'JSON'
{"route":{"rules":[{"domain_suffix":["old.example"],"action":"reject"}]}}
JSON
    accessControlBackupCreate
    cat >"${configPath}09_routing.json" <<'JSON'
{"routing":{"rules":[{"outboundTag":"new","domain":["domain:new.example"]}]}}
JSON
    cat >"${configPath}blackhole_out.json" <<'JSON'
{"outbounds":[{"tag":"blackhole_out"}]}
JSON
    cat >"${singBoxConfigPath}block_domain_route.json" <<'JSON'
{"route":{"rules":[{"domain_suffix":["new.example"],"action":"reject"}]}}
JSON
    cat >"${singBoxConfigPath}cn_block_route.json" <<'JSON'
{"route":{"rules":[{"rule_set":["geosite-cn"],"action":"reject"}]}}
JSON

    set +e
    applyAccessControlConfigChange >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${reloadCalls}" == "2" ]]
    jq -e '.routing.rules[0].outboundTag == "old"' "${configPath}09_routing.json" >/dev/null
    [[ ! -e "${configPath}blackhole_out.json" ]]
    jq -e '.route.rules[0].domain_suffix == ["old.example"]' "${singBoxConfigPath}block_domain_route.json" >/dev/null
    [[ ! -e "${singBoxConfigPath}cn_block_route.json" ]]
    [[ ! -e "${PADM_ACCESS_CONTROL_BACKUP_DIR}" ]]
    grep -q '核心重载失败，已回滚本次修改' "${statusLog}"

    rm -rf "${root}"
    mkdir -p "${configPath}" "${singBoxConfigPath}"
    : >"${statusLog}"
    reloadCalls=0
    cat >"${configPath}09_routing.json" <<'JSON'
{"routing":{"rules":[{"outboundTag":"old","domain":["domain:old.example"]}]}}
JSON
    accessControlBackupCreate
    cat >"${configPath}09_routing.json" <<'JSON'
{"routing":{"rules":[{"outboundTag":"new","domain":["domain:new.example"]}]}}
JSON
    cp() {
        if [[ "$1" == "${PADM_ACCESS_CONTROL_BACKUP_DIR}/xray/09_routing.json" && "$2" == "${configPath}09_routing.json" ]]; then
            return 1
        fi
        command cp "$@"
    }
    set +e
    applyAccessControlConfigChange >/dev/null 2>&1
    rc=$?
    set -e
    unset -f cp
    [[ "${rc}" == "1" ]]
    [[ "${reloadCalls}" == "1" ]]
    [[ -d "${PADM_ACCESS_CONTROL_BACKUP_DIR}" ]]
    [[ -f "${PADM_ACCESS_CONTROL_BACKUP_DIR}/xray/09_routing.json" ]]
    grep -q '核心重载失败，且回滚失败' "${statusLog}"
)

runBTRoutingFailureReturnRegression() (
    local root="${TMP_DIR}/bt-routing-failure"
    local installMarker="${root}/install"
    local sniffMarker="${root}/sniff"
    local uninstallMarker="${root}/uninstall"
    local reloadMarker="${root}/reload"
    local successMarker="${root}/success"
    local rc

    mkdir -p "${root}/xray" "${root}/sing-box"
    configPath="${root}/xray/"
    singBoxConfigPath=
    coreInstallType=1
    statusCard() { return 0; }
    errorCard() { return 0; }
    echoContent() { return 0; }
    menuLine() { return 0; }
    menuItem() { return 0; }
    menuReturnItem() { return 0; }
    menuClose() { return 0; }
    showBTBlockStatus() { return 0; }
    readInstallType() { coreInstallType=1; }
    successCard() {
        printf 'success\n' >"${successMarker}"
        return 0
    }

    (
        configPath="${root}/xray/"
        cat >"${configPath}09_routing.json" <<'JSON'
{"routing":{"rules":[]}}
JSON
        unInstallRouting() { return 0; }
        updateRoutingJsonConfig() { return 1; }
        set +e
        addXrayBTBlockRule >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
    )

    addXrayBTBlockRule() { return 1; }
    installSniffing() {
        printf 'sniff\n' >"${sniffMarker}"
        return 0
    }
    set +e
    installBTBlock >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -e "${sniffMarker}" ]]

    unInstallRouting() { return 1; }
    set +e
    uninstallBTBlock >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]

    autoRead() { printf -v "$3" '1'; }
    installBTBlock() {
        printf 'install\n' >"${installMarker}"
        return 0
    }
    reloadCore() {
        printf 'reload\n' >"${reloadMarker}"
        return 1
    }
    rm -f "${installMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    btTools >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${installMarker}" ]]
    [[ -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]

    autoRead() { printf -v "$3" '2'; }
    uninstallBTBlock() {
        printf 'uninstall\n' >"${uninstallMarker}"
        return 0
    }
    rm -f "${uninstallMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    btTools >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${uninstallMarker}" ]]
    [[ -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]
)

runIPv6RoutingFailureReturnRegression() (
    local root="${TMP_DIR}/ipv6-routing-failure"
    local outboundMarker="${root}/outbound"
    local routingMarker="${root}/routing"
    local removeMarker="${root}/remove"
    local uninstallMarker="${root}/uninstall"
    local reloadMarker="${root}/reload"
    local successMarker="${root}/success"
    local mode=success
    local menuChoice=2
    local rc

    mkdir -p "${root}/xray"
    configPath="${root}/xray/"
    singBoxConfigPath=
    coreInstallType=1

    errorCard() { return 0; }
    statusCard() { return 0; }
    warnCard() { return 0; }
    echoContent() { return 0; }
    progressCard() { return 0; }
    menuLine() { return 0; }
    menuItem() { return 0; }
    menuDangerItem() { return 0; }
    menuReturnItem() { return 0; }
    menuClose() { return 0; }
    successCard() {
        printf 'success\n' >"${successMarker}"
        return 0
    }
    hasIPv6Connectivity() { return 0; }
    autoConfirm() {
        printf -v "$4" 'y'
        return 0
    }
    autoRead() {
        case "$3" in
        ipv6Status) printf -v "$3" "${menuChoice}" ;;
        domainList)
            if [[ "${mode}" == "empty-domain" ]]; then
                printf -v "$3" ''
            else
                printf -v "$3" 'example.com'
            fi
            ;;
        *) printf -v "$3" '' ;;
        esac
    }
    addXrayOutbound() {
        printf 'outbound:%s\n' "$1" >>"${outboundMarker}"
        [[ "${mode}" != "outbound-fail" ]]
    }
    addXrayRouting() {
        printf 'routing\n' >"${routingMarker}"
        [[ "${mode}" != "routing-fail" ]]
    }
    removeXrayOutbound() {
        printf 'remove:%s\n' "$1" >>"${removeMarker}"
        return 0
    }
    unInstallRouting() {
        printf 'uninstall\n' >"${uninstallMarker}"
        [[ "${mode}" != "uninstall-fail" ]]
    }
    reloadCore() {
        printf 'reload\n' >"${reloadMarker}"
        [[ "${mode}" != "reload-fail" ]]
    }

    hasIPv6Connectivity() { return 1; }
    rm -f "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    ipv6Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]

    hasIPv6Connectivity() { return 0; }
    mode=empty-domain
    menuChoice=2
    rm -f "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    ipv6Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -e "${outboundMarker}" ]]
    [[ ! -e "${routingMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]

    mode=routing-fail
    rm -f "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    ipv6Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${outboundMarker}" ]]
    [[ -e "${routingMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]

    mode=reload-fail
    rm -f "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    ipv6Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]

    mode=outbound-fail
    menuChoice=3
    rm -f "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    ipv6Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${outboundMarker}" ]]
    [[ ! -e "${removeMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]

    mode=uninstall-fail
    menuChoice=4
    rm -f "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    ipv6Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${uninstallMarker}" ]]
    [[ ! -e "${removeMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]

    mode=reload-fail
    rm -f "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    ipv6Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${uninstallMarker}" ]]
    [[ -e "${removeMarker}" ]]
    [[ -e "${outboundMarker}" ]]
    [[ -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]
)

runWARPRoutingFailureReturnRegression() (
    local root="${TMP_DIR}/warp-routing-failure"
    local installMarker="${root}/install"
    local readMarker="${root}/read"
    local outboundMarker="${root}/outbound"
    local routingMarker="${root}/routing"
    local removeMarker="${root}/remove"
    local uninstallMarker="${root}/uninstall"
    local reloadMarker="${root}/reload"
    local successMarker="${root}/success"
    local mode=success
    local menuChoice=2
    local rc

    mkdir -p "${root}/xray"
    configPath="${root}/xray/"
    singBoxConfigPath=
    coreInstallType=1

    errorCard() { return 0; }
    statusCard() { return 0; }
    warnCard() { return 0; }
    echoContent() { return 0; }
    progressCard() { return 0; }
    menuLine() { return 0; }
    menuItem() { return 0; }
    menuDangerItem() { return 0; }
    menuReturnItem() { return 0; }
    menuClose() { return 0; }
    successCard() {
        printf 'success\n' >"${successMarker}"
        return 0
    }
    installWarpReg() {
        printf 'install\n' >"${installMarker}"
        [[ "${mode}" != "install-fail" ]]
    }
    readConfigWarpReg() {
        printf 'read\n' >>"${readMarker}"
        addressWarpReg="2001:db8::2"
        secretKeyWarpReg="warp-secret"
        publicKeyWarpReg="warp-public"
        reservedWarpReg='[1,2,3]'
        [[ "${mode}" != "read-fail" ]]
    }
    autoConfirm() {
        printf -v "$4" 'y'
        return 0
    }
    autoRead() {
        case "$3" in
        warpStatus) printf -v "$3" "${menuChoice}" ;;
        domainList)
            if [[ "${mode}" == "empty-domain" ]]; then
                printf -v "$3" ''
            else
                printf -v "$3" 'example.com'
            fi
            ;;
        *) printf -v "$3" '' ;;
        esac
    }
    addXrayOutbound() {
        printf 'outbound:%s\n' "$1" >>"${outboundMarker}"
        [[ "${mode}" != "outbound-fail" ]]
    }
    addXrayRouting() {
        printf 'routing\n' >"${routingMarker}"
        [[ "${mode}" != "routing-fail" ]]
    }
    removeXrayOutbound() {
        printf 'remove:%s\n' "$1" >>"${removeMarker}"
        return 0
    }
    unInstallRouting() {
        printf 'uninstall\n' >"${uninstallMarker}"
        [[ "${mode}" != "uninstall-fail" ]]
    }
    unInstallWireGuard() { return 0; }
    reloadCore() {
        printf 'reload\n' >"${reloadMarker}"
        [[ "${mode}" != "reload-fail" ]]
    }

    mode=install-fail
    rm -f "${installMarker}" "${readMarker}" "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    warpRoutingReg 1 IPv4 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${installMarker}" ]]
    [[ ! -e "${readMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]

    mode=empty-domain
    menuChoice=2
    rm -f "${installMarker}" "${readMarker}" "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    warpRoutingReg 1 IPv4 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${installMarker}" ]]
    [[ -e "${readMarker}" ]]
    [[ ! -e "${outboundMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]

    mode=routing-fail
    rm -f "${installMarker}" "${readMarker}" "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    warpRoutingReg 1 IPv4 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${outboundMarker}" ]]
    [[ -e "${routingMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]

    mode=reload-fail
    rm -f "${installMarker}" "${readMarker}" "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    warpRoutingReg 1 IPv4 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]

    mode=outbound-fail
    menuChoice=3
    rm -f "${installMarker}" "${readMarker}" "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    warpRoutingReg 1 IPv4 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${outboundMarker}" ]]
    [[ ! -e "${removeMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]

    mode=uninstall-fail
    menuChoice=4
    rm -f "${installMarker}" "${readMarker}" "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    warpRoutingReg 1 IPv4 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${uninstallMarker}" ]]
    [[ ! -e "${removeMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]

    mode=reload-fail
    rm -f "${installMarker}" "${readMarker}" "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    warpRoutingReg 1 IPv4 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${uninstallMarker}" ]]
    [[ -e "${removeMarker}" ]]
    [[ -e "${outboundMarker}" ]]
    [[ -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]
)

runSocks5RoutingFailureReturnRegression() (
    local root="${TMP_DIR}/socks5-routing-failure"
    local outboundMarker="${root}/outbound"
    local routingMarker="${root}/routing"
    local uninstallMarker="${root}/uninstall"
    local removeMarker="${root}/remove"
    local reloadMarker="${root}/reload"
    local stopMarker="${root}/stop"
    local successMarker="${root}/success"
    local menuChoice=1
    local uninstallChoice=1
    local mode=invalid-port
    local rc

    mkdir -p "${root}/xray" "${root}/sing-box"
    configPath="${root}/xray/"
    singBoxConfigPath=
    coreInstallType=1

    errorCard() { return 0; }
    statusCard() { return 0; }
    warnCard() { return 0; }
    echoContent() { return 0; }
    menuLine() { return 0; }
    menuItem() { return 0; }
    menuDangerItem() { return 0; }
    menuReturnItem() { return 0; }
    menuClose() { return 0; }
    successCard() {
        printf 'success\n' >"${successMarker}"
        return 0
    }
    autoConfirm() {
        printf -v "$4" 'y'
        return 0
    }
    autoRead() {
        case "$1" in
        socks5_outbound_menu) printf -v "$3" "${menuChoice}" ;;
        socks5_uninstall_menu) printf -v "$3" "${uninstallChoice}" ;;
        socks5_outbound_ip) printf -v "$3" '127.0.0.1' ;;
        socks5_outbound_port)
            if [[ "${mode}" == "invalid-port" ]]; then
                printf -v "$3" 'bad-port'
            else
                printf -v "$3" '1080'
            fi
            ;;
        socks5_outbound_username) printf -v "$3" 'user' ;;
        socks5_outbound_password) printf -v "$3" 'pass' ;;
        socks5_outbound_domains) printf -v "$3" 'example.com' ;;
        *) printf -v "$3" '' ;;
        esac
    }
    addXrayOutbound() {
        printf 'outbound:%s\n' "$1" >>"${outboundMarker}"
        [[ "${mode}" != "outbound-fail" ]]
    }
    unInstallRouting() {
        printf 'uninstall\n' >"${uninstallMarker}"
        [[ "${mode}" != "uninstall-fail" ]]
    }
    removeXrayOutbound() {
        printf 'remove:%s\n' "$1" >>"${removeMarker}"
        return 0
    }
    reloadCore() {
        printf 'reload\n' >"${reloadMarker}"
        [[ "${mode}" != "reload-fail" ]]
    }
    handleSingBox() {
        printf 'stop\n' >"${stopMarker}"
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE:-}" == "true" ]] && [[ "${mode}" != "stop-fail" ]]
    }

    mode=invalid-port
    rm -f "${outboundMarker}" "${routingMarker}" "${uninstallMarker}" "${removeMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    setSocks5Outbound >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -e "${outboundMarker}" ]]

    mode=outbound-fail
    rm -f "${outboundMarker}" "${routingMarker}" "${uninstallMarker}" "${removeMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    setSocks5Outbound >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${outboundMarker}" ]]

    mode=uninstall-fail
    rm -f "${outboundMarker}" "${routingMarker}" "${uninstallMarker}" "${removeMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    setSocks5OutboundRouting >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${uninstallMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]

    setSocks5Outbound() {
        printf 'outbound-config\n' >"${outboundMarker}"
        return 0
    }
    setSocks5OutboundRouting() {
        printf 'routing\n' >"${routingMarker}"
        return 0
    }

    mode=reload-fail
    menuChoice=1
    rm -f "${outboundMarker}" "${routingMarker}" "${uninstallMarker}" "${removeMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    socks5OutboundRoutingMenu >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${outboundMarker}" ]]
    [[ -e "${routingMarker}" ]]
    [[ -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]

    mode=stop-fail
    uninstallChoice=2
    rm -f "${outboundMarker}" "${routingMarker}" "${uninstallMarker}" "${removeMarker}" "${reloadMarker}" "${stopMarker}" "${successMarker}"
    set +e
    removeSocks5Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${stopMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]

    mode=uninstall-fail
    uninstallChoice=1
    rm -f "${outboundMarker}" "${routingMarker}" "${uninstallMarker}" "${removeMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    removeSocks5Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${uninstallMarker}" ]]
    [[ ! -e "${removeMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]

    mode=reload-fail
    rm -f "${outboundMarker}" "${routingMarker}" "${uninstallMarker}" "${removeMarker}" "${reloadMarker}" "${successMarker}"
    set +e
    removeSocks5Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${uninstallMarker}" ]]
    [[ -e "${removeMarker}" ]]
    [[ -e "${outboundMarker}" ]]
    [[ -e "${reloadMarker}" ]]
    [[ ! -e "${successMarker}" ]]
)

runSocks5UdpAssociateRegression() (
    local root="${TMP_DIR}/socks5-udp-associate"
    local allowAllMode=true

    mkdir -p "${root}/xray" "${root}/sing-box"
    configPath="${root}/xray/"
    singBoxConfigPath="${root}/sing-box/"
    coreInstallType=2
    singBoxSocks5Port=

    cat >"${singBoxConfigPath}dlc.dat_plain.yml" <<'YAML'
- name: openai
YAML

    readSingBoxPortResult() {
        local -n resultRef=$1
        resultRef=(10891)
        return 0
    }
    autoRead() {
        case "$1" in
        socks5_inbound_uuid) printf -v "$3" 'udp-associate-user' ;;
        socks5_inbound_ip_type) printf -v "$3" '1' ;;
        socks5_inbound_source_ips) printf -v "$3" '10.0.0.1,10.0.0.2' ;;
        socks5_inbound_allow_all)
            if [[ "${allowAllMode}" == "true" ]]; then
                printf -v "$3" 'y'
            else
                printf -v "$3" 'n'
            fi
            ;;
        socks5_inbound_domains) printf -v "$3" 'openai,example.com' ;;
        singbox_route_history) printf -v "$3" 'n' ;;
        *) printf -v "$3" '' ;;
        esac
    }

    setSocks5Inbound
    jq -e '
      .inbounds[0].type == "socks" and
      .inbounds[0].listen == "::" and
      .inbounds[0].listen_port == 10891 and
      .inbounds[0].tag == "socks5_inbound" and
      .inbounds[0].users[0].username == "udp-associate-user" and
      .inbounds[0].users[0].password == "udp-associate-user" and
      (.inbounds[0].network? | not) and
      (.inbounds[0].udp? | not)
    ' "${singBoxConfigPath}20_socks5_inbounds.json" >/dev/null
    jq -e '
      .route.rules[0].inbound == "socks5_inbound" and
      .route.rules[0].action == "resolve" and
      .route.rules[0].strategy == "ipv4_only" and
      (.route.rules[0].network? | not) and
      (.route.rules[0].protocol? | not)
    ' "${singBoxConfigPath}strategy_ipv4_only_socks5_inbound.json" >/dev/null

    setSocks5InboundRouting
    jq -e '
      .route.rules[0].inbound == ["socks5_inbound"] and
      (.route.rules[0].source_ip_cidr | sort) == (["10.0.0.1", "10.0.0.2"] | sort) and
      .route.rules[0].outbound == "01_direct_outbound" and
      (.route.rules[0].action? | not) and
      (.route.rules[0].protocol? | not) and
      (.route.rules[0].network? | not) and
      (.route.rules[0].domain? | not) and
      (.route.rules[0].domain_suffix? | not) and
      (.route.rules[0].rule_set? | not)
    ' "${singBoxConfigPath}socks5_02_inbound_route.json" >/dev/null
    jq -e '
      .outbounds[0].type == "direct" and
      .outbounds[0].tag == "01_direct_outbound" and
      (.outbounds[0].network? | not)
    ' "${singBoxConfigPath}01_direct_outbound.json" >/dev/null

    allowAllMode=false
    setSocks5InboundRouting addRules
    jq -e '
      .route.rules[0].inbound == ["socks5_inbound"] and
      (.route.rules[0].source_ip_cidr | sort) == (["10.0.0.1", "10.0.0.2"] | sort) and
      .route.rules[0].outbound == "01_direct_outbound" and
      .route.rules[0].domain_suffix == ["example.com"] and
      .route.rules[0].rule_set == ["geosite_openai_socks5_02_inbound_route"] and
      (.route.rules[0].action? | not) and
      (.route.rules[0].protocol? | not) and
      (.route.rules[0].network? | not) and
      (.route.rules[0].domain? | not)
    ' "${singBoxConfigPath}socks5_02_inbound_route.json" >/dev/null
)

runDNSRoutingFailureReturnRegression() (
    local root="${TMP_DIR}/dns-routing-failure"
    local reloadMarker="${root}/reload"
    local statusMarker="${root}/status"
    local successMarker="${root}/success"
    local errorLog="${root}/error.log"
    local rc

    mkdir -p "${root}"
    PADM_DNS_ROUTING_BACKUP_DIR="${root}/backup"
    errorCard() {
        printf '%s\n' "$*" >>"${errorLog}"
        return 0
    }
    echoContent() { return 0; }
    menuLine() { return 0; }
    menuClose() { return 0; }
    getDLCMatchedRuleValue() { printf 'domain:%s\n' "$1"; }
    statusCard() {
        printf 'status\n' >"${statusMarker}"
        return 0
    }
    successCard() {
        printf 'success\n' >"${successMarker}"
        return 0
    }
    reloadCore() {
        printf 'reload\n' >>"${reloadMarker}"
        return 1
    }

    (
        mkdir -p "${root}/dns-sing-box-helper"
        configPath=
        singBoxConfigPath="${root}/dns-sing-box-helper/"
        printf '{"dns":{"servers":["old"]}}\n' >"${singBoxConfigPath}dns.json"
        splitSingBoxRules() { return 1; }
        set +e
        addSingBoxDNSConfig "1.1.1.1" "example.com" >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        jq -e '.dns.servers == ["old"]' "${singBoxConfigPath}dns.json" >/dev/null
    )

    (
        mkdir -p "${root}/dns-xray"
        configPath="${root}/dns-xray/"
        singBoxConfigPath=
        coreInstallType=1
        printf '{"dns":{"servers":["old-xray"]}}\n' >"${configPath}11_dns.json"
        autoRead() {
            case "$3" in
            setDNS) printf -v "$3" '8.8.8.8' ;;
            domainList) printf -v "$3" 'example.com' ;;
            *) printf -v "$3" '' ;;
            esac
        }
        rm -rf "${PADM_DNS_ROUTING_BACKUP_DIR}"
        rm -f "${reloadMarker}" "${statusMarker}" "${successMarker}" "${errorLog}"
        set +e
        setUnlockDNS >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ -e "${reloadMarker}" ]]
        [[ "$(wc -l <"${reloadMarker}")" == "2" ]]
        jq -e '.dns.servers == ["old-xray"]' "${configPath}11_dns.json" >/dev/null
        [[ ! -e "${PADM_DNS_ROUTING_BACKUP_DIR}" ]]
        grep -q 'DNS 分流核心重载失败，已回滚本次修改' "${errorLog}"
    )

    (
        mkdir -p "${root}/dns-sing-box-outbound"
        configPath=
        singBoxConfigPath="${root}/dns-sing-box-outbound/"
        coreInstallType=2
        autoRead() {
            case "$3" in
            setDNS) printf -v "$3" '8.8.8.8' ;;
            domainList) printf -v "$3" 'example.com' ;;
            *) printf -v "$3" '' ;;
            esac
        }
        addSingBoxOutbound() { return 1; }
        rm -rf "${PADM_DNS_ROUTING_BACKUP_DIR}"
        rm -f "${reloadMarker}" "${statusMarker}" "${successMarker}" "${errorLog}"
        set +e
        setUnlockDNS >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ ! -e "${reloadMarker}" ]]
        [[ ! -e "${singBoxConfigPath}dns.json" ]]
        [[ ! -e "${singBoxConfigPath}01_direct_outbound.json" ]]
        [[ ! -e "${PADM_DNS_ROUTING_BACKUP_DIR}" ]]
    )

    (
        mkdir -p "${root}/sni-xray"
        configPath="${root}/sni-xray/"
        singBoxConfigPath=
        coreInstallType=1
        printf '{"dns":{"servers":["old-sni"]}}\n' >"${configPath}11_dns.json"
        autoRead() {
            case "$3" in
            setSNIP) printf -v "$3" '203.0.113.10' ;;
            xrayDomainList) printf -v "$3" 'example.com' ;;
            *) printf -v "$3" '' ;;
            esac
        }
        rm -rf "${PADM_DNS_ROUTING_BACKUP_DIR}"
        rm -f "${reloadMarker}" "${statusMarker}" "${successMarker}" "${errorLog}"
        set +e
        setUnlockSNI >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ -e "${reloadMarker}" ]]
        [[ "$(wc -l <"${reloadMarker}")" == "2" ]]
        jq -e '.dns.servers == ["old-sni"]' "${configPath}11_dns.json" >/dev/null
        [[ ! -e "${PADM_DNS_ROUTING_BACKUP_DIR}" ]]
        [[ ! -e "${statusMarker}" ]]
    )

    (
        mkdir -p "${root}/sni-sing-box"
        configPath=
        singBoxConfigPath="${root}/sni-sing-box/"
        coreInstallType=2
        printf '{"dns":{"servers":["old-sing-sni"]}}\n' >"${singBoxConfigPath}dns.json"
        autoRead() {
            case "$3" in
            setSNIP) printf -v "$3" '203.0.113.10' ;;
            singboxDomainList) printf -v "$3" 'example.com' ;;
            *) printf -v "$3" '' ;;
            esac
        }
        addSingBoxDNSConfig() { return 1; }
        rm -rf "${PADM_DNS_ROUTING_BACKUP_DIR}"
        rm -f "${reloadMarker}" "${statusMarker}" "${successMarker}" "${errorLog}"
        set +e
        setUnlockSNI >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ ! -e "${reloadMarker}" ]]
        [[ ! -e "${statusMarker}" ]]
        jq -e '.dns.servers == ["old-sing-sni"]' "${singBoxConfigPath}dns.json" >/dev/null
        [[ ! -e "${PADM_DNS_ROUTING_BACKUP_DIR}" ]]
    )

    (
        mkdir -p "${root}/remove-dns"
        configPath="${root}/remove-dns/"
        singBoxConfigPath=
        coreInstallType=1
        cat >"${configPath}11_dns.json" <<'JSON'
{"dns":{"servers":["8.8.8.8"]}}
JSON
        rm -rf "${PADM_DNS_ROUTING_BACKUP_DIR}"
        rm -f "${reloadMarker}" "${successMarker}" "${errorLog}"
        set +e
        removeUnlockDNS >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ -e "${reloadMarker}" ]]
        [[ "$(wc -l <"${reloadMarker}")" == "2" ]]
        jq -e '.dns.servers == ["8.8.8.8"]' "${configPath}11_dns.json" >/dev/null
        [[ ! -e "${PADM_DNS_ROUTING_BACKUP_DIR}" ]]
        [[ ! -e "${successMarker}" ]]
        [[ ! -e "${root}/remove-dns/dns.json" ]]
    )

    (
        mkdir -p "${root}/remove-dns-xray-sing-box-assist/xray" "${root}/remove-dns-xray-sing-box-assist/sing-box"
        configPath="${root}/remove-dns-xray-sing-box-assist/xray/"
        singBoxConfigPath="${root}/remove-dns-xray-sing-box-assist/sing-box/"
        coreInstallType=1
        cat >"${configPath}11_dns.json" <<'JSON'
{"dns":{"servers":["8.8.8.8"]}}
JSON
        cat >"${singBoxConfigPath}dns.json" <<'JSON'
{"dns":{"servers":[{"tag":"hosts","type":"hosts","predefined":{"example.com":"203.0.113.10"}}]}}
JSON
        rm -rf "${PADM_DNS_ROUTING_BACKUP_DIR}"
        rm -f "${reloadMarker}" "${successMarker}" "${errorLog}"
        set +e
        removeUnlockDNS >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ -e "${reloadMarker}" ]]
        [[ "$(wc -l <"${reloadMarker}")" == "2" ]]
        jq -e '.dns.servers == ["8.8.8.8"]' "${configPath}11_dns.json" >/dev/null
        jq -e '.dns.servers[0].tag == "hosts"' "${singBoxConfigPath}dns.json" >/dev/null
        [[ ! -e "${PADM_DNS_ROUTING_BACKUP_DIR}" ]]
        [[ ! -e "${successMarker}" ]]
    )

    (
        mkdir -p "${root}/remove-sni-xray-sing-box-assist/xray" "${root}/remove-sni-xray-sing-box-assist/sing-box"
        configPath="${root}/remove-sni-xray-sing-box-assist/xray/"
        singBoxConfigPath="${root}/remove-sni-xray-sing-box-assist/sing-box/"
        coreInstallType=1
        cat >"${configPath}11_dns.json" <<'JSON'
{"dns":{"hosts":{"domain:example.com":"203.0.113.10"},"servers":["8.8.8.8"]}}
JSON
        cat >"${singBoxConfigPath}dns.json" <<'JSON'
{"dns":{"servers":[{"tag":"hosts","type":"hosts","predefined":{"example.com":"203.0.113.10"}}],"rules":[{"domain_suffix":["example.com"],"server":"hosts"}]}}
JSON
        rm -rf "${PADM_DNS_ROUTING_BACKUP_DIR}"
        rm -f "${reloadMarker}" "${successMarker}" "${errorLog}"
        set +e
        removeUnlockSNI >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ -e "${reloadMarker}" ]]
        [[ "$(wc -l <"${reloadMarker}")" == "2" ]]
        jq -e '.dns.hosts["domain:example.com"] == "203.0.113.10"' "${configPath}11_dns.json" >/dev/null
        jq -e '.dns.servers[0].tag == "hosts"' "${singBoxConfigPath}dns.json" >/dev/null
        [[ ! -e "${PADM_DNS_ROUTING_BACKUP_DIR}" ]]
        [[ ! -e "${successMarker}" ]]
    )

    (
        mkdir -p "${root}/dns-xray-restore-fail"
        configPath="${root}/dns-xray-restore-fail/"
        singBoxConfigPath=
        coreInstallType=1
        printf '{"dns":{"servers":["old-restore"]}}\n' >"${configPath}11_dns.json"
        autoRead() {
            case "$3" in
            setDNS) printf -v "$3" '8.8.8.8' ;;
            domainList) printf -v "$3" 'example.com' ;;
            *) printf -v "$3" '' ;;
            esac
        }
        cp() {
            if [[ "$1" == "${PADM_DNS_ROUTING_BACKUP_DIR}/xray/11_dns.json" && "$2" == "${configPath}11_dns.json" ]]; then
                return 1
            fi
            command cp "$@"
        }
        rm -rf "${PADM_DNS_ROUTING_BACKUP_DIR}"
        rm -f "${reloadMarker}" "${statusMarker}" "${successMarker}" "${errorLog}"
        set +e
        setUnlockDNS >/dev/null 2>&1
        rc=$?
        set -e
        unset -f cp
        [[ "${rc}" == "1" ]]
        [[ -e "${reloadMarker}" ]]
        [[ "$(wc -l <"${reloadMarker}")" == "1" ]]
        [[ -d "${PADM_DNS_ROUTING_BACKUP_DIR}" ]]
        [[ -f "${PADM_DNS_ROUTING_BACKUP_DIR}/xray/11_dns.json" ]]
        grep -q 'DNS 分流核心重载失败，且旧配置恢复失败' "${errorLog}"
    )
)

runPortAndPanelHelperRegression() {
    parsedCorePorts=$(corePortParseList '2053, 2083,2053')
    [[ "${parsedCorePorts}" == $'2053\n2083' ]]
    ! corePortParseList '0,70000,abc' >/dev/null
    writeCoreDokodemoInbound "${configPath}02_dokodemodoor_inbounds_2053.json" 2053 443 tcp dokodemo-door-newPort-2053
    writeCoreDokodemoInbound "${configPath}02_dokodemodoor_inbounds_hysteria_2053.json" 2053 9443 udp dokodemo-door-newPort-hysteria-2053
    writeCoreDokodemoInbound "${configPath}02_dokodemodoor_inbounds_2083_default.json" 2083 443 tcp dokodemo-door-newPort-2083
    corePortListExtra | grep -qx '1:2053'
    corePortListExtra | grep -qx '2:2083 默认'
    [[ "$(corePortResolveByIndex 2)" == "2083" ]]
    [[ "$(basename "$(corePortDefaultFile)")" == "02_dokodemodoor_inbounds_2083_default.json" ]]
    corePortRemove 2053
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2053.json" ]]
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_hysteria_2053.json" ]]
    [[ -e "${configPath}02_dokodemodoor_inbounds_2083_default.json" ]]
    jq -e '.inbounds[0].settings.network == "tcp" and .inbounds[0].settings.port == 443' "${configPath}02_dokodemodoor_inbounds_2083_default.json" >/dev/null
    mkdir -p "${TMP_DIR}/bt-panel/example.com" "${TMP_DIR}/one-panel/example.org/ssl"
    printf 'cert' >"${TMP_DIR}/bt-panel/example.com/fullchain.pem"
    printf 'cert' >"${TMP_DIR}/one-panel/example.org/ssl/fullchain.pem"
    panelCertDomainList "${TMP_DIR}/bt-panel/*/fullchain.pem" 1 | grep -qx '1:example.com'
    panelCertDomainList "${TMP_DIR}/one-panel/*/ssl/fullchain.pem" 2 | grep -qx '1:example.org'
    rm -rf "${configPath}"
}

runRuntimeTempDirRegression() (
    local oldTmpDir="${TMPDIR:-}"
    local tmpRoot="${TMP_DIR}/runtime-tmp"
    local targetRoot="${TMP_DIR}/runtime-tempdir-target"
    local crontabPathMarker="${TMP_DIR}/runtime-crontab-path.txt"
    local jsonFile="${targetRoot}/state.json"
    local mkdirToolsLog="${TMP_DIR}/runtime-mkdir-tools.log"
    local mkdirStatus

    mkdir -p "${tmpRoot}" "${targetRoot}"
    TMPDIR="${tmpRoot}"

    : >"${mkdirToolsLog}"
    set +e
    (
        mkdir() {
            printf '%s\n' "$*" >>"${mkdirToolsLog}"
            [[ "$*" == "-p /etc/padm/xray/conf" ]] && return 1
            return 0
        }
        mkdirTools
    )
    mkdirStatus=$?
    set -e
    [[ "${mkdirStatus}" == "1" ]]
    grep -qx -- '-p /etc/padm/xray/conf' "${mkdirToolsLog}"
    grep -qx -- "-p ${tmpRoot}/padm-tls" "${mkdirToolsLog}"
    grep -qx -- '-p /usr/share/nginx/html/' "${mkdirToolsLog}"

    [[ "$(padmTmpFilePath padm-runtime-direct.log)" == "${tmpRoot}/padm-runtime-direct.log" ]]
    [[ "$(traditionalTlsAlpnTestLog)" == "${tmpRoot}/padm-alpn-xray-test.log" ]]
    [[ "$(xhttpConfigTestLog)" == "${tmpRoot}/padm-xhttp-test.log" ]]
    [[ "$(tuicConfigTestLog)" == "${tmpRoot}/padm-tuic-test.log" ]]
    [[ "$(coreTmpFilePath padm-core-xray-test.log)" == "${tmpRoot}/padm-core-xray-test.log" ]]
    [[ "$(coreTmpFilePath padm-core-xray-upgrade-test.log)" == "${tmpRoot}/padm-core-xray-upgrade-test.log" ]]
    [[ "$(coreTmpFilePath padm-core-sing-box-test.log)" == "${tmpRoot}/padm-core-sing-box-test.log" ]]
    [[ "$(coreTmpFilePath padm-core-sing-box-upgrade-test.log)" == "${tmpRoot}/padm-core-sing-box-upgrade-test.log" ]]
    [[ "$(coreTmpFilePath padm-xray.init.XXXXXX)" == "${tmpRoot}/padm-xray.init.XXXXXX" ]]
    [[ "$(coreTmpFilePath padm-sing-box.service.XXXXXX)" == "${tmpRoot}/padm-sing-box.service.XXXXXX" ]]
    [[ "$(coreTmpFilePath padm-xray.service.XXXXXX)" == "${tmpRoot}/padm-xray.service.XXXXXX" ]]
    [[ "$(adapterTmpPath padm-packages.XXXXXX)" == "${tmpRoot}/padm-packages.XXXXXX" ]]
    [[ "$(adapterTmpPath padm-tls)" == "${tmpRoot}/padm-tls" ]]
    [[ "$(adapterTmpPath padm-tls)/acme.sh" == "${tmpRoot}/padm-tls/acme.sh" ]]
    [[ "$(adapterTmpPath padm-tls/acme.sh.download.XXXXXX)" == "${tmpRoot}/padm-tls/acme.sh.download.XXXXXX" ]]
    [[ "$(adapterNginxRepoTemplate)" == "${tmpRoot}/padm-nginx-repo.XXXXXX" ]]
    [[ "$(adapterNginxPinTemplate)" == "${tmpRoot}/padm-nginx-pin.XXXXXX" ]]
    [[ "$(adapterNginxYumRepoTemplate)" == "${tmpRoot}/padm-nginx-yum-repo.XXXXXX" ]]
    [[ "$(adapterTmpPath padm-warp-repo.XXXXXX)" == "${tmpRoot}/padm-warp-repo.XXXXXX" ]]
    [[ "$(adapterTmpPath padm-warp-yum-repo.XXXXXX)" == "${tmpRoot}/padm-warp-yum-repo.XXXXXX" ]]
    [[ "$(accessControlXrayTestLog)" == "${tmpRoot}/padm-access-xray-test.log" ]]
    [[ "$(accessControlSingBoxTestLog)" == "${tmpRoot}/padm-access-sing-box-test.log" ]]
    [[ "$(aloneNginxTestLog)" == "${tmpRoot}/padm-alone-nginx-test.log" ]]
    [[ "$(realityStreamEnableBackupTemplate)" == "${tmpRoot}/padm-reality-stream.XXXXXX" ]]
    [[ "$(realityStreamDisableBackupTemplate)" == "${tmpRoot}/padm-reality-stream-disable.XXXXXX" ]]
    [[ "$(bbrSysctlLog)" == "${tmpRoot}/padm-bbr-sysctl.log" ]]
    [[ "$(bbrStateTempTemplate)" == "${tmpRoot}/padm-bbr-state.XXXXXX" ]]
    [[ "$(bbrSysctlTempTemplate)" == "${tmpRoot}/padm-bbr-sysctl.XXXXXX" ]]
    [[ "$(singBoxVMessHTTPUpgradeNginxTestLog)" == "${tmpRoot}/padm-sing-box-vmess-httpupgrade-nginx-test.log" ]]
    [[ "$(thirdPartyTcpScriptPath)" == "${tmpRoot}/padm-tcpx.sh" ]]
    [[ "$(realityTargetTmpPath RealiTLScanner)" == "${tmpRoot}/RealiTLScanner" ]]
    [[ "$(realityTargetTmpPath padm-realitlscanner-123.csv)" == "${tmpRoot}/padm-realitlscanner-123.csv" ]]
    [[ "$(realityTargetTmpPath padm-realitlscanner-123-sample-2.csv)" == "${tmpRoot}/padm-realitlscanner-123-sample-2.csv" ]]
    [[ "$(realityTargetTmpPath padm-reality-target-xray-test.log)" == "${tmpRoot}/padm-reality-target-xray-test.log" ]]
    [[ "$(realityTargetTmpPath padm-reality-target-sing-box-test.log)" == "${tmpRoot}/padm-reality-target-sing-box-test.log" ]]
    [[ "$(realityTargetTmpPath 'padm-reality-target.XXXXXX')" == "${tmpRoot}/padm-reality-target.XXXXXX" ]]

    printf '{"ok":true}\n' | writeGeneratedJsonFile "${jsonFile}" padm-runtime-json
    jq -e '.ok == true' "${jsonFile}" >/dev/null
    if find "${tmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-runtime-json.*' | grep -q .; then
        return 1
    fi

    crontab() {
        printf '%s\n' "$1" >"${crontabPathMarker}"
        grep -qxF '15 1 * * * echo ok' "$1"
    }
    installUserCrontabContent $'\n15 1 * * * echo ok\n'
    [[ "$(<"${crontabPathMarker}")" == "${tmpRoot}"/padm-crontab.* ]]
    if find "${tmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-crontab.*' | grep -q .; then
        return 1
    fi

    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runCorePortFileTransactionRegression() {
    local oldTmpDir="${TMPDIR:-}"
    local portTmpRoot="${TMP_DIR}/core-port-tmp"
    mkdir -p "${portTmpRoot}"
    TMPDIR="${portTmpRoot}"
    mkdir -p "${configPath}"
    writeCoreDokodemoInbound "${configPath}02_dokodemodoor_inbounds_2053.json" 2053 443 tcp dokodemo-door-newPort-2053
    writeCoreDokodemoInbound "${configPath}02_dokodemodoor_inbounds_2083_default.json" 2083 443 tcp dokodemo-door-newPort-2083
    local original2053 original2083 keptBackup
    original2053=$(<"${configPath}02_dokodemodoor_inbounds_2053.json")
    original2083=$(<"${configPath}02_dokodemodoor_inbounds_2083_default.json")
    if corePortApplyFileTransaction corePortWriteAddFiles $'2053\n2083' 2053 'bad-port' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${configPath}02_dokodemodoor_inbounds_2053.json")" == "${original2053}" ]]
    [[ "$(<"${configPath}02_dokodemodoor_inbounds_2083_default.json")" == "${original2083}" ]]
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2053_default.json" ]]
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2083.json" ]]

    corePortApplyFileTransaction corePortWriteAddFiles $'2053\n2083' 2053 443
    [[ -e "${configPath}02_dokodemodoor_inbounds_2053_default.json" ]]
    [[ -e "${configPath}02_dokodemodoor_inbounds_2083.json" ]]
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2083_default.json" ]]
    jq -e '.inbounds[0].port == 2053 and .inbounds[0].settings.port == 443' "${configPath}02_dokodemodoor_inbounds_2053_default.json" >/dev/null

    if corePortApplyFileTransaction corePortWriteAddFiles 2443 2443 'bad-port' 2>/dev/null; then
        return 1
    fi
    [[ -e "${configPath}02_dokodemodoor_inbounds_2053_default.json" ]]
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2443_default.json" ]]

    corePortApplyFileTransaction corePortRemove 2083
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2083.json" ]]
    [[ -e "${configPath}02_dokodemodoor_inbounds_2053_default.json" ]]

    local reloadCalls=0 errorLog="${TMP_DIR}/core-port-reload-error.log"
    : >"${errorLog}"
    errorCard() {
        printf '%s\n' "$*" >>"${errorLog}"
    }

    : >"${errorLog}"
    (
        cp() {
            if [[ "${2:-}" == "${portTmpRoot}"/padm-core-port.*/* ]]; then
                return 1
            fi
            command cp "$@"
        }
        if corePortApplyFileTransaction corePortWriteAddFiles 2443 2443 443 2>/dev/null; then
            return 1
        fi
        [[ "$(<"${configPath}02_dokodemodoor_inbounds_2053_default.json")" == "${original2053}" ]]
        [[ ! -e "${configPath}02_dokodemodoor_inbounds_2443_default.json" ]]
        if find "${portTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-core-port.*' | grep -q .; then
            return 1
        fi
    ) || return 1
    grep -q "入口端口配置备份失败" "${errorLog}"

    : >"${errorLog}"
    (
        cp() {
            if [[ "${2:-}" == "${configPath}"02_dokodemodoor_inbounds_2053_default.json ]]; then
                return 1
            fi
            command cp "$@"
        }
        if corePortApplyFileTransaction corePortWriteAddFiles 2443 2443 'bad-port' 2>/dev/null; then
            return 1
        fi
    ) || return 1
    grep -q "入口端口配置回滚失败" "${errorLog}"
    keptBackup=$(find "${portTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-core-port.*' -print -quit)
    [[ -n "${keptBackup}" && -d "${keptBackup}" ]]
    [[ -f "${keptBackup}/02_dokodemodoor_inbounds_2053_default.json" ]]
    rm -rf "${keptBackup}"
    printf '%s\n' "${original2053}" >"${configPath}02_dokodemodoor_inbounds_2053_default.json"
    rm -f "${configPath}02_dokodemodoor_inbounds_2443_default.json"

    reloadCore() {
        reloadCalls=$((reloadCalls + 1))
        [[ "${reloadCalls}" != "1" ]]
    }

    original2053=$(<"${configPath}02_dokodemodoor_inbounds_2053_default.json")
    if corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 443 2>/dev/null; then
        return 1
    fi
    [[ "${reloadCalls}" == "2" ]]
    [[ "$(<"${configPath}02_dokodemodoor_inbounds_2053_default.json")" == "${original2053}" ]]
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2443_default.json" ]]

    reloadCalls=0
    reloadCore() {
        reloadCalls=$((reloadCalls + 1))
        [[ "${reloadCalls}" != "1" ]]
    }
    if corePortApplyReloadTransaction corePortRemove 2053 2>/dev/null; then
        return 1
    fi
    [[ "${reloadCalls}" == "2" ]]
    [[ "$(<"${configPath}02_dokodemodoor_inbounds_2053_default.json")" == "${original2053}" ]]
    grep -q "恢复后核心重载仍失败" "${errorLog}" && return 1

    reloadCalls=0
    : >"${errorLog}"
    reloadCore() {
        reloadCalls=$((reloadCalls + 1))
        [[ "${reloadCalls}" != "1" ]]
    }
    (
        cp() {
            if [[ "${2:-}" == "${configPath}"02_dokodemodoor_inbounds_2053_default.json ]]; then
                return 1
            fi
            command cp "$@"
        }
        if corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 443 2>/dev/null; then
            return 1
        fi
    ) || return 1
    [[ "${reloadCalls}" == "1" ]]
    grep -q "入口端口核心重载失败，且旧配置恢复失败" "${errorLog}"
    keptBackup=$(find "${portTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-core-port.*' -print -quit)
    [[ -n "${keptBackup}" && -d "${keptBackup}" ]]
    rm -rf "${keptBackup}"
    printf '%s\n' "${original2053}" >"${configPath}02_dokodemodoor_inbounds_2053_default.json"
    rm -f "${configPath}02_dokodemodoor_inbounds_2443_default.json"

    reloadCalls=0
    reloadCore() {
        reloadCalls=$((reloadCalls + 1))
        return 0
    }
    corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 443
    [[ "${reloadCalls}" == "1" ]]
    [[ -e "${configPath}02_dokodemodoor_inbounds_2443_default.json" ]]
    if find "${portTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-core-port.*' | grep -q .; then
        return 1
    fi
    rm -rf "${configPath}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runXrayRealityPortFailureRegression() (
    local xrayRoot="${TMP_DIR}/xray-reality-port-failure"
    local oldConfigPath="${configPath:-}"
    local oldSelectCustomInstallType="${selectCustomInstallType:-}"
    local oldCurrentUUID="${currentUUID:-}"
    local oldCurrentClients="${currentClients:-}"
    local oldRealityPort="${realityPort:-}"
    local oldXHTTPort="${xHTTPort:-}"
    local oldXrayRealityPort="${xrayVLESSRealityPort:-}"
    local oldXrayXHTTPort="${xrayVLESSRealityXHTTPort:-}"
    local oldLastInstallationConfig="${lastInstallationConfig:-}"
    local allowCalls=0
    local serviceLog="${xrayRoot}/service.log"
    local errorLog="${xrayRoot}/error.log"
    local allowMarker="${xrayRoot}/allow.log"
    local configRc

    configPath="${xrayRoot}/"
    mkdir -p "${configPath}"
    currentUUID=existing-user
    xrayVLESSRealityPort=
    xrayVLESSRealityXHTTPort=
    lastInstallationConfig=true
    realityPort=70000
    xHTTPort=
    initXrayClients() { printf '[]\n'; }
    addXrayOutbound() { return 0; }
    installSniffing() { return 0; }
    writeGeneratedJsonFile() {
        local targetFile=$1
        local outputFile
        shift 2
        if [[ "${targetFile}" == /etc/padm/xray/conf/* ]]; then
            outputFile="${configPath}${targetFile#/etc/padm/xray/conf/}"
        else
            outputFile="${targetFile}"
        fi
        mkdir -p "$(dirname "${outputFile}")"
        cat >"${outputFile}"
    }
    initRealityProfile() { return 0; }
    initRealityKey() {
        realityPrivateKey=private
        realityPublicKey=public
    }
    initRealityMldsa65() {
        realityMldsa65Seed=seed
        realityMldsa65Verify=verify
    }
    allowPort() {
        allowCalls=$((allowCalls + 1))
        printf 'allow:%s\n' "$*" >>"${allowMarker}"
        return 0
    }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        return 1
    }
    errorCard() {
        printf '%s\n' "$*" >>"${errorLog}"
    }

    ! validPortNumber 999999999999999999999

    if initXrayRealityPort 2>/dev/null; then
        return 1
    fi
    [[ "${allowCalls}" == "0" ]]

    xHTTPort=bad-port
    if initXrayXHTTPort 2>/dev/null; then
        return 1
    fi
    [[ "${allowCalls}" == "0" ]]

    : >"${serviceLog}"
    : >"${errorLog}"
    realityPort=
    xHTTPort=
    xrayVLESSRealityPort=1443
    lastInstallationConfig=
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    autoRead() {
        printf -v "$3" '1443'
    }
    if initXrayRealityPort 2>/dev/null; then
        return 1
    fi
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -q '无法复用当前 Reality 端口' "${errorLog}"
    [[ "${allowCalls}" == "0" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    : >"${serviceLog}"
    : >"${errorLog}"
    realityPort=
    xHTTPort=
    xrayVLESSRealityPort=
    xrayVLESSRealityXHTTPort=2443
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    autoRead() {
        printf -v "$3" '2443'
    }
    if initXrayXHTTPort 2>/dev/null; then
        return 1
    fi
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -q '无法复用当前 Reality XHTTP 端口' "${errorLog}"
    [[ "${allowCalls}" == "0" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    selectCustomInstallType=",7,"
    xrayVLESSRealityPort=
    xrayVLESSRealityXHTTPort=
    xHTTPort=
    realityPort=70000
    rm -f "${allowMarker}"
    set +e
    (
        set +e
        initXrayConfig custom 1 true >/dev/null 2>&1
    )
    configRc=$?
    set -e
    [[ "${configRc}" == "1" ]]
    [[ ! -e "${allowMarker}" ]]
    [[ ! -e "${configPath}07_VLESS_vision_reality_inbounds.json" ]]

    selectCustomInstallType=",12,"
    realityPort=10888
    xHTTPort=bad-port
    rm -f "${allowMarker}"
    set +e
    (
        set +e
        initXrayConfig custom 1 true >/dev/null 2>&1
    )
    configRc=$?
    set -e
    [[ "${configRc}" == "1" ]]
    [[ ! -e "${allowMarker}" ]]
    [[ ! -e "${configPath}12_VLESS_XHTTP_inbounds.json" ]]

    configPath="${oldConfigPath}"
    selectCustomInstallType="${oldSelectCustomInstallType}"
    currentUUID="${oldCurrentUUID}"
    currentClients="${oldCurrentClients}"
    realityPort="${oldRealityPort}"
    xHTTPort="${oldXHTTPort}"
    xrayVLESSRealityPort="${oldXrayRealityPort}"
    xrayVLESSRealityXHTTPort="${oldXrayXHTTPort}"
    lastInstallationConfig="${oldLastInstallationConfig}"
)

runRealityProfileFailureRegression() (
    local root="${TMP_DIR}/reality-profile-failure"
    local xrayRoot="${root}/xray/"
    local singBoxRoot="${root}/sing-box/"
    local entryHostFile="${root}/reality_entry_host"
    local allowCalls=0
    local keyCalls=0
    local portReads=0

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

    initRealityProfile
    [[ "$(<"${entryHostFile}")" == "node.example.com" ]]
    rm -f "${entryHostFile}"
    AUTO_REALITY_TARGET=bad.example.com:70000
    realityTargetHost=
    realityTargetPort=
    realitySNI=
    realityEntryHost=

    selectCustomInstallType=",7,"
    if initXrayConfig custom 1 true 2>/dev/null; then
        return 1
    fi
    [[ "${allowCalls}" == "0" ]]
    [[ "${keyCalls}" == "0" ]]
    [[ ! -e "${entryHostFile}" ]]
    [[ ! -e "${xrayRoot}07_VLESS_vision_reality_inbounds.json" ]]

    selectCustomInstallType=",12,"
    if initXrayConfig custom 1 true 2>/dev/null; then
        return 1
    fi
    [[ "${allowCalls}" == "0" ]]
    [[ "${keyCalls}" == "0" ]]
    [[ ! -e "${entryHostFile}" ]]
    [[ ! -e "${xrayRoot}12_VLESS_XHTTP_inbounds.json" ]]

    selectCustomInstallType=",7,"
    if initSingBoxConfig custom 1 true 2>/dev/null; then
        return 1
    fi
    [[ "${allowCalls}" == "0" ]]
    [[ "${keyCalls}" == "0" ]]
    [[ "${portReads}" == "0" ]]
    [[ ! -e "${entryHostFile}" ]]
    [[ ! -e "${singBoxRoot}07_VLESS_vision_reality_inbounds.json" ]]
)

runCoreTemplateReturnFailureRegression() (
    local mode=xray
    local xrayRc singBoxRc
    local stopRc writeCalls=0 serviceLog="${TMP_DIR}/core-template-service.log"

    currentUUID=existing-user
    currentClients='[]'
    domain=tls.example.com
    currentHost=tls.example.com
    lastInstallationConfig=true
    selectCustomInstallType=",7,"
    singBoxVLESSVisionPort=10890

    initXrayClients() { printf '[]\n'; }
    initSingBoxClients() { printf '[]\n'; }
    addXrayOutbound() { return 0; }
    checkDNSIP() { return 0; }
    removeNginxDefaultConf() { return 0; }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" != "stop-fail" ]]
    }
    checkPortOpen() { return 0; }
    readSingBoxPortResult() {
        local -n resultRef=$1
        resultRef=(10890)
        return 0
    }
    writeGeneratedJsonFile() {
        local targetFile=$1
        shift 2
        writeCalls=$((writeCalls + 1))
        if [[ "${mode}" == "xray" && "${targetFile}" == "/etc/padm/xray/conf/09_routing.json" ]]; then
            return 1
        fi
        if [[ "${mode}" == "sing-box" && "${targetFile}" == "/etc/padm/sing-box/conf/config/02_VLESS_TCP_inbounds.json" ]]; then
            return 1
        fi
        cat >/dev/null
    }

    set +e
    initXrayConfig custom 1 true 2>/dev/null
    xrayRc=$?
    set -e
    [[ "${xrayRc}" != "0" ]]

    mode=stop-fail
    selectCustomInstallType=",0,"
    writeCalls=0
    : >"${serviceLog}"
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    set +e
    initSingBoxConfig custom 1 true 2>/dev/null
    stopRc=$?
    set -e
    [[ "${stopRc}" != "0" ]]
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    [[ "${writeCalls}" == "0" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    mode=sing-box
    selectCustomInstallType=",0,"
    writeCalls=0
    set +e
    initSingBoxConfig custom 1 true 2>/dev/null
    singBoxRc=$?
    set -e
    [[ "${singBoxRc}" != "0" ]]
    [[ "${writeCalls}" != "0" ]]
)

runCoreBinaryInstallCopyFailureRegression() (
    local root="${TMP_DIR}/core-binary-copy-failure"
    local xrayBinary="${root}/xray/xray"
    local singBoxBinary="${root}/sing-box/sing-box"
    local statusLog="${root}/status.log"
    local successLog="${root}/success.log"
    local serviceLog="${root}/service.log"
    local copyFailureLog="${root}/copy-failure.log"
    local xrayRc singBoxRc
    local restoreCopyShouldFail= xrayStartShouldFail= singBoxStartShouldFail=

    mkdir -p "$(dirname "${xrayBinary}")" "$(dirname "${singBoxBinary}")" "${root}/tmp"
    printf 'old-xray\n' >"${xrayBinary}"
    printf 'old-sing-box\n' >"${singBoxBinary}"
    chmod 755 "${xrayBinary}" "${singBoxBinary}"

    PADM_XRAY_BINARY="${xrayBinary}"
    PADM_SINGBOX_BINARY="${singBoxBinary}"
    xrayCoreCPUVendor=linux-64
    singBoxCoreCPUVendor=-linux-amd64
    REGRESSION_STATUS_CARD_LOG="${statusLog}"
    REGRESSION_SUCCESS_CARD_LOG="${successLog}"
    : >"${statusLog}"
    : >"${successLog}"
    : >"${serviceLog}"
    : >"${copyFailureLog}"

    padmCreateTempPath() {
        local resultVar=$1
        local path
        shift
        if [[ "${1:-}" == "-d" ]]; then
            path=$(mktemp -d "${root}/tmp/core.XXXXXX") || return 1
        else
            path=$(mktemp "${root}/tmp/core.XXXXXX") || return 1
        fi
        printf -v "${resultVar}" '%s' "${path}"
    }
    padmRemoveCleanupPath() {
        rm -rf "$1"
    }
    padmForgetCleanupPath() { return 0; }
    downloadGitHubReleaseAsset() {
        local outputDir= assetName=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -P)
                outputDir=$2
                shift 2
                ;;
            *)
                assetName=$1
                shift
                ;;
            esac
        done
        mkdir -p "${outputDir}"
        : >"${outputDir}/${assetName}"
    }
    unzip() {
        local dest=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -d)
                dest=$2
                shift 2
                ;;
            *)
                shift
                ;;
            esac
        done
        printf '#!/usr/bin/env bash\nexit 0\n' >"${dest}/xray"
        chmod 755 "${dest}/xray"
    }
    tar() {
        local dest=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -C)
                dest=$2
                shift 2
                ;;
            *)
                shift
                ;;
            esac
        done
        mkdir -p "${dest}/sing-box-1.2.3-linux-amd64"
        printf '#!/usr/bin/env bash\nexit 0\n' >"${dest}/sing-box-1.2.3-linux-amd64/sing-box"
        chmod 755 "${dest}/sing-box-1.2.3-linux-amd64/sing-box"
    }
    cp() {
        local sourcePath=$1
        local targetPath=$2
        if [[ "${restoreCopyShouldFail}" == "true" && "${sourcePath}" == "${xrayBinary}.bak.restore-fail" && "${targetPath}" == "${xrayBinary}" ]]; then
            printf 'restore-xray\n' >>"${copyFailureLog}"
            return 1
        fi
        if [[ "${targetPath}" == "${xrayBinary}" && "${sourcePath}" != ${xrayBinary}.bak.* ]]; then
            printf 'xray\n' >>"${copyFailureLog}"
            return 1
        fi
        if [[ "${targetPath}" == "${singBoxBinary}" && "${sourcePath}" != ${singBoxBinary}.bak.* ]]; then
            printf 'sing-box\n' >>"${copyFailureLog}"
            return 1
        fi
        command cp "$@"
    }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "$1" == "start" && "${xrayStartShouldFail}" == "true" ]] && return 1
        return 0
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "$1" == "start" && "${singBoxStartShouldFail}" == "true" ]] && return 1
        return 0
    }
    xrayRunning() { return 1; }
    singBoxRunning() { return 1; }
    validateXrayConfigWithBinary() { return 0; }
    validateSingBoxConfigWithBinary() { return 0; }

    SERVICE_QUEUE_ALLOW_FAILURE=
    set +e
    installDownloadedXrayBinary v1.2.3 >/dev/null 2>&1
    xrayRc=$?
    installDownloadedSingBoxBinary v1.2.3 >/dev/null 2>&1
    singBoxRc=$?
    set -e

    [[ "${xrayRc}" == "1" ]]
    [[ "${singBoxRc}" == "1" ]]
    [[ "$(<"${xrayBinary}")" == "old-xray" ]]
    [[ "$(<"${singBoxBinary}")" == "old-sing-box" ]]
    grep -qx 'xray' "${copyFailureLog}"
    grep -qx 'sing-box' "${copyFailureLog}"
    grep -q 'Xray-core 更新失败' "${statusLog}"
    grep -q 'sing-box 更新失败' "${statusLog}"
    grep -q '旧服务已尝试恢复启动' "${statusLog}"
    ! grep -q 'Xray-core更新成功' "${successLog}"
    ! grep -q 'sing-box更新成功' "${successLog}"
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    grep -qx 'sing-box:start:true' "${serviceLog}"
    [[ -z "${SERVICE_QUEUE_ALLOW_FAILURE}" ]]

    : >"${statusLog}"
    : >"${serviceLog}"
    printf 'new-xray\n' >"${xrayBinary}"
    printf 'old-xray\n' >"${xrayBinary}.bak.service-fail"
    xrayStartShouldFail=true
    set +e
    finalizeFailedCoreBinaryInstall "Xray-core" "${xrayBinary}.bak.service-fail" "${xrayBinary}" handleXray "/tmp/xray.log" >/dev/null 2>&1
    xrayRc=$?
    set -e
    xrayStartShouldFail=
    [[ "${xrayRc}" == "1" ]]
    [[ "$(<"${xrayBinary}")" == "old-xray" ]]
    [[ ! -e "${xrayBinary}.bak.service-fail" ]]
    grep -q '旧服务恢复启动失败，请手动检查服务状态' "${statusLog}"
    grep -qx 'xray:start:true' "${serviceLog}"

    : >"${statusLog}"
    : >"${serviceLog}"
    printf 'new-xray\n' >"${xrayBinary}"
    printf 'old-xray\n' >"${xrayBinary}.bak.restore-fail"
    restoreCopyShouldFail=true
    set +e
    finalizeFailedCoreBinaryInstall "Xray-core" "${xrayBinary}.bak.restore-fail" "${xrayBinary}" handleXray "/tmp/xray.log" >/dev/null 2>&1
    xrayRc=$?
    set -e
    restoreCopyShouldFail=
    [[ "${xrayRc}" == "1" ]]
    [[ "$(<"${xrayBinary}")" == "new-xray" ]]
    [[ -e "${xrayBinary}.bak.restore-fail" ]]
    grep -q '旧二进制恢复失败' "${statusLog}"
    grep -q '旧二进制未恢复，已跳过服务启动' "${statusLog}"
    ! grep -q 'xray:start:true' "${serviceLog}"
)

runNetworkCheckReturnFailureRegression() (
    local root="${TMP_DIR}/network-check-return"
    local dnsRcFile="${root}/dns.rc"
    local ipRcFile="${root}/ip.rc"
    local portRcFile="${root}/port.rc"
    local templateRcFile="${root}/template.rc"
    local writeProbe="${root}/template.write"
    local serviceLog="${root}/port-services.log"
    local cleanLog="${root}/port-clean.log"
    local writeLog="${root}/port-write.log"
    local mode=
    local dnsShellRc ipShellRc portShellRc templateShellRc

    mkdir -p "${root}/nginx"
    statusCard() { return 0; }
    successCard() { return 0; }
    errorCard() { return 0; }
    echoContent() { return 0; }
    menuLine() { return 0; }
    menuClose() { return 0; }
    progressCard() { return 0; }
    sleep() { return 0; }
    dig() { return 1; }
    getPublicIP() { printf '203.0.113.10\n'; }

    set +e
    (
        set +e
        checkDNSIP bad.example.com >/dev/null 2>&1
        printf '%s\n' "$?" >"${dnsRcFile}"
    )
    dnsShellRc=$?
    (
        set +e
        checkIP "" >/dev/null 2>&1
        printf '%s\n' "$?" >"${ipRcFile}"
    )
    ipShellRc=$?
    set -e
    [[ "${dnsShellRc}" == "0" ]]
    [[ "${ipShellRc}" == "0" ]]
    [[ "$(<"${dnsRcFile}")" == "1" ]]
    [[ "$(<"${ipRcFile}")" == "1" ]]

    btDomain=
    nginxConfigPath="${root}/nginx/"
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "sing-box-stop-fail" ]] && return 1
        return 0
    }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "xray-stop-fail" ]] && return 1
        return 0
    }
    cleanAgentNginxConf() {
        printf 'clean:%s\n' "${mode}" >>"${cleanLog}"
        [[ "${mode}" != "clean-fail" ]]
    }
    allowPort() { return 0; }
    handleNginx() {
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "nginx-stop-fail" && "$1" == "stop" ]] && return 1
        [[ "${mode}" == "nginx-start-fail" && "$1" == "start" ]] && return 1
        return 0
    }
    hasIPv6Connectivity() { return 1; }
    writeCheckPortOpenNginxConfig() {
        printf 'write:%s\n' "${mode}" >>"${writeLog}"
        [[ "${mode}" != "write-fail" ]]
    }

    mode=clean-fail
    : >"${serviceLog}"
    : >"${cleanLog}"
    : >"${writeLog}"
    set +e
    (
        set +e
        checkPortOpen 443 example.com >/dev/null 2>&1
        printf '%s\n' "$?" >"${portRcFile}"
    )
    portShellRc=$?
    set -e
    [[ "${portShellRc}" == "0" ]]
    [[ "$(<"${portRcFile}")" == "1" ]]
    grep -qx 'clean:clean-fail' "${cleanLog}"
    [[ ! -s "${writeLog}" ]]

    mode=write-fail
    : >"${serviceLog}"
    : >"${cleanLog}"
    : >"${writeLog}"
    set +e
    (
        set +e
        checkPortOpen 443 example.com >/dev/null 2>&1
        printf '%s\n' "$?" >"${portRcFile}"
    )
    portShellRc=$?
    set -e
    [[ "${portShellRc}" == "0" ]]
    [[ "$(<"${portRcFile}")" == "1" ]]
    grep -qx 'write:write-fail' "${writeLog}"

    runPortServiceFailureCase() {
        local failureMode=$1
        local rc
        mode="${failureMode}"
        : >"${serviceLog}"
        : >"${cleanLog}"
        : >"${writeLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        set +e
        checkPortOpen 443 example.com >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    }

    runPortServiceFailureCase sing-box-stop-fail
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    ! grep -q '^xray:' "${serviceLog}"
    [[ ! -s "${writeLog}" ]]

    runPortServiceFailureCase xray-stop-fail
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    grep -qx 'xray:stop:true' "${serviceLog}"
    ! grep -q '^nginx:' "${serviceLog}"
    [[ ! -s "${writeLog}" ]]

    runPortServiceFailureCase nginx-stop-fail
    grep -qx 'nginx:stop:true' "${serviceLog}"
    [[ ! -s "${writeLog}" ]]

    runPortServiceFailureCase nginx-start-fail
    grep -qx 'nginx:start:true' "${serviceLog}"
    grep -qx 'write:nginx-start-fail' "${writeLog}"

    allowPort() {
        printf 'allow:%s\n' "$*" >>"${serviceLog}"
        return 1
    }
    mode=
    : >"${serviceLog}"
    : >"${cleanLog}"
    : >"${writeLog}"
    set +e
    (
        set +e
        checkPortOpen 443 example.com >/dev/null 2>&1
        printf '%s\n' "$?" >"${portRcFile}"
    )
    portShellRc=$?
    set -e
    [[ "${portShellRc}" == "0" ]]
    [[ "$(<"${portRcFile}")" == "1" ]]
    grep -qx 'allow:443' "${serviceLog}"
    ! grep -q '^sing-box:' "${serviceLog}"
    ! grep -q '^xray:' "${serviceLog}"
    ! grep -q '^nginx:' "${serviceLog}"
    [[ ! -s "${cleanLog}" ]]
    [[ ! -s "${writeLog}" ]]

    portProcessKind=padm
    lsof() {
        case "$*" in
        "-i tcp:8443"|"-nP -i tcp:8443")
            case "${portProcessKind}" in
            padm) printf 'xray 123 root 3u IPv4 TCP *:8443 (LISTEN)\n' ;;
            nginx) printf 'nginx 123 root 3u IPv4 TCP *:8443 (LISTEN)\n' ;;
            none) return 1 ;;
            esac
            ;;
        "-ti tcp:8443")
            printf '123\n'
            ;;
        *)
            return 1
            ;;
        esac
    }
    autoRead() {
        printf -v "$3" 'y'
    }
    systemctl() {
        printf 'systemctl:%s\n' "$*" >>"${serviceLog}"
        return 0
    }
    runCheckPortStopFailureCase() {
        local failureMode=$1
        local processKind=$2
        local rc
        mode="${failureMode}"
        portProcessKind="${processKind}"
        : >"${serviceLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        set +e
        checkPort 8443 >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    }

    runCheckPortStopFailureCase xray-stop-fail padm
    grep -qx 'xray:stop:true' "${serviceLog}"
    ! grep -q '^sing-box:' "${serviceLog}"

    runCheckPortStopFailureCase sing-box-stop-fail padm
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'sing-box:stop:true' "${serviceLog}"

    runCheckPortStopFailureCase nginx-stop-fail nginx
    grep -qx 'nginx:stop:true' "${serviceLog}"
    ! grep -q '^systemctl:' "${serviceLog}"

    currentUUID=existing-user
    currentClients='[]'
    domain=tls.example.com
    currentHost=tls.example.com
    lastInstallationConfig=true
    selectCustomInstallType=",0,"
    singBoxVLESSVisionPort=10890

    initSingBoxClients() { printf '[]\n'; }
    readSingBoxPortResult() {
        local -n resultRef=$1
        resultRef=(10890)
        return 0
    }
    checkDNSIP() { return 1; }
    removeNginxDefaultConf() { return 0; }
    checkPortOpen() { return 0; }
    writeGeneratedJsonFile() {
        printf 'called\n' >"${writeProbe}"
        cat >/dev/null
    }
    setSniffRouting() { return 0; }

    set +e
    (
        set +e
        initSingBoxConfig custom 1 true >/dev/null 2>&1
        printf '%s\n' "$?" >"${templateRcFile}"
    )
    templateShellRc=$?
    set -e
    [[ "${templateShellRc}" == "0" ]]
    [[ "$(<"${templateRcFile}")" == "1" ]]
    [[ ! -e "${writeProbe}" ]]
)

runTlsFailureReturnRegression() (
    local root="${TMP_DIR}/tls-failure-return"
    local oldHome="${HOME}"
    local emailRcFile="${root}/email.rc"
    local dnsRcFile="${root}/dns-api.rc"
    local caRcFile="${root}/ca.rc"
    local installRcFile="${root}/install.rc"
    local xrayRcFile="${root}/xray.rc"
    local shellRc

    mkdir -p "${root}/home"
    HOME="${root}/home"
    statusCard() { return 0; }
    successCard() { return 0; }
    errorCard() { return 0; }
    echoContent() { return 0; }
    menuLine() { return 0; }
    menuClose() { return 0; }
    menuItem() { return 0; }
    menuRecommendedItem() { return 0; }
    progressCard() { return 0; }
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

    btDomain=
    readLastInstallationConfig() { return 0; }
    unInstallSubscribe() { return 0; }
    installTools() { return 0; }
    initTLSNginxConfig() { return 0; }
    installTLS() { return 1; }

    captureFailureReturn "${xrayRcFile}" xrayCoreInstall
    HOME="${oldHome}"
)

runServiceQueueApplyPropagationRegression() (
    local root="${TMP_DIR}/service-queue-propagation"
    local rcFile="${root}/install.rc"
    local serviceCallsFile="${root}/service-calls"
    local shellRc

    mkdir -p "${root}"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/core/services.sh"
    TMPDIR="${root}/tmp"
    mkdir -p "${TMPDIR}"
    [[ "$(xrayStartTestLog)" == "${TMPDIR}/padm-xray-start-test.log" ]]
    handleNginx() {
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceCallsFile}"
        return 1
    }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceCallsFile}"
        return 1
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceCallsFile}"
        return 1
    }
    SERVICE_ACTIONS=
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    serviceQueueStart nginx
    serviceQueueStop xray
    serviceQueueStop sing-box
    set +e
    serviceQueueApply >/dev/null 2>&1
    local queueRc=$?
    set -e
    [[ "${queueRc}" == "1" ]]
    grep -qx 'nginx:start:true' "${serviceCallsFile}"
    grep -qx 'xray:stop:true' "${serviceCallsFile}"
    grep -qx 'sing-box:stop:true' "${serviceCallsFile}"
    [[ -z "${SERVICE_ACTIONS}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    readLastInstallationConfig() { return 0; }
    unInstallSubscribe() { return 0; }
    installTools() { return 0; }
    handleNginx() { return 0; }
    subscriptionWireGuardControlEnabled() { return 1; }
    refreshSubscriptionWireGuardNginxControl() { return 0; }
    installXray() { return 0; }
    installXrayService() { return 0; }
    initXrayConfig() { return 0; }
    cleanUp() { return 0; }
    serviceQueueRestart() { return 0; }
    serviceQueueApply() { return 1; }

    set +e
    (
        set +e
        installXrayReality >/dev/null 2>&1
        printf '%s\n' "$?" >"${rcFile}"
    )
    shellRc=$?
    set -e
    [[ "${shellRc}" == "0" ]]
    [[ "$(<"${rcFile}")" == "1" ]]
)

runCoreInstallServiceActionFailureRegression() (
    local root="${TMP_DIR}/core-install-service-action"
    local serviceLog="${root}/service.log"
    local callLog="${root}/calls.log"
    local errorLog="${root}/errors.log"
    local mode rc

    mkdir -p "${root}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    statusCard() { return 0; }
    successCard() { return 0; }
    progressCard() { return 0; }
    echoContent() { return 0; }
    menuLine() { return 0; }
    menuClose() { return 0; }
    protocolRegistryMenu() { return 0; }
    readLastInstallationConfig() { return 0; }
    unInstallSubscribe() { return 0; }
    installTools() { printf 'installTools:%s\n' "$*" >>"${callLog}"; return 0; }
    initTLSNginxConfig() { printf 'initTLS:%s\n' "$*" >>"${callLog}"; return 0; }
    installTLS() { printf 'installTLS:%s\n' "$*" >>"${callLog}"; return 0; }
    randomPathFunction() { printf 'path:%s\n' "$*" >>"${callLog}"; return 0; }
    nginxBlog() { printf 'nginxBlog:%s\n' "$*" >>"${callLog}"; return 0; }
    updateRedirectNginxConf() {
        printf 'redirect\n' >>"${callLog}"
        [[ "${mode}" == "redirect-fail" ]] && return 1
        return 0
    }
    installXray() { printf 'installXray:%s\n' "$*" >>"${callLog}"; return 0; }
    installXrayService() { printf 'installXrayService:%s\n' "$*" >>"${callLog}"; return 0; }
    initXrayConfig() { printf 'initXrayConfig:%s\n' "$*" >>"${callLog}"; return 0; }
    installSingBox() { printf 'installSingBox:%s\n' "$*" >>"${callLog}"; return 0; }
    installSingBoxService() { printf 'installSingBoxService:%s\n' "$*" >>"${callLog}"; return 0; }
    initSingBoxConfig() { printf 'initSingBoxConfig:%s\n' "$*" >>"${callLog}"; return 0; }
    cleanUp() { printf 'cleanup:%s\n' "$*" >>"${callLog}"; return 0; }
    installCronTLS() { printf 'cron:%s\n' "$*" >>"${callLog}"; return 0; }
    customPortFunction() { printf 'customPort\n' >>"${callLog}"; return 0; }
    subscriptionWireGuardControlEnabled() { return 0; }
    refreshSubscriptionWireGuardNginxControl() { printf 'wg-refresh\n' >>"${callLog}"; return 0; }
    serviceQueueRestart() { printf 'queueRestart:%s\n' "$*" >>"${callLog}"; return 0; }
    serviceQueueStart() { printf 'queueStart:%s\n' "$*" >>"${callLog}"; return 0; }
    serviceQueueApply() { printf 'queueApply\n' >>"${callLog}"; return 0; }
    handleNginx() {
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "nginx-stop-fail" && "$1" == "stop" ]] && return 1
        [[ "${mode}" == "nginx-start-fail" && "$1" == "start" ]] && return 1
        return 0
    }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "xray-stop-fail" && "$1" == "stop" ]] && return 1
        [[ "${mode}" == "xray-start-fail" && "$1" == "start" ]] && return 1
        return 0
    }

    resetInstallServiceFixture() {
        mode=$1
        : >"${serviceLog}"
        : >"${callLog}"
        : >"${errorLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        btDomain=
        realityOnlyWithDomain=
        currentHost=install.example.com
        domain=install.example.com
    }

    resetInstallServiceFixture nginx-stop-fail
    set +e
    installXrayReality >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:stop:true' "${serviceLog}"
    ! grep -q '^installXray:' "${callLog}"
    ! grep -q '^wg-refresh$' "${callLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture nginx-start-fail
    set +e
    customXrayInstall 0 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:start:true' "${serviceLog}"
    ! grep -q '^installXray:' "${callLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture redirect-fail
    set +e
    customXrayInstall 0 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'redirect' "${callLog}"
    ! grep -q '^nginx:start:' "${serviceLog}"
    ! grep -q '^installXray:' "${callLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture xray-start-fail
    set +e
    xrayCoreInstall >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -q '^installXray:' "${callLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture redirect-fail
    set +e
    xrayCoreInstall >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'redirect' "${callLog}"
    ! grep -q '^xray:stop:' "${serviceLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture nginx-stop-fail
    set +e
    singBoxInstall >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:stop:true' "${serviceLog}"
    ! grep -q '^installSingBox:' "${callLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
)

runSingBoxMergeStartFailureRegression() (
    local root="${TMP_DIR}/sing-box-merge-start-failure"
    local serviceFile="${root}/sing-box.service"
    local mergeMarker="${root}/merge"
    local systemctlMarker="${root}/systemctl"
    local queueRc

    mkdir -p "${root}"
    touch "${serviceFile}"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/core/services.sh"

    PADM_SINGBOX_SYSTEMD_SERVICE_FILE="${serviceFile}"
    SERVICE_ACTIONS=
    SERVICE_QUEUE_ALLOW_FAILURE=
    singBoxRunning() { return 1; }
    singBoxMergeConfig() {
        printf 'merge\n' >"${mergeMarker}"
        return 1
    }
    systemctl() {
        printf '%s\n' "$*" >"${systemctlMarker}"
        return 0
    }
    errorCard() { return 0; }
    menuLine() { return 0; }
    uiStyle() { shift; printf '%s\n' "$*"; }

    serviceQueueStart sing-box
    set +e
    serviceQueueApply >/dev/null 2>&1
    queueRc=$?
    set -e

    [[ "${queueRc}" == "1" ]]
    [[ -e "${mergeMarker}" ]]
    [[ ! -e "${systemctlMarker}" ]]
    [[ -z "${SERVICE_ACTIONS}" ]]
    [[ -z "${SERVICE_QUEUE_ALLOW_FAILURE}" ]]
)

runSingBoxMergeConfigTransactionRegression() (
    local root="${TMP_DIR}/sing-box-merge-config-transaction"
    local confDir="${root}/conf"
    local shardDir="${confDir}/config"
    local binary="${root}/fake-sing-box"
    local outputFile="${confDir}/config.json"
    local checkLog="${root}/check.log"
    local commitMarker="${root}/commit.log"
    local logFile="${root}/merge.log"
    local rc

    mkdir -p "${shardDir}"
    cat >"${binary}" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "check" ]]; then
    shift
    config=
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        -c)
            config=$2
            shift 2
            ;;
        *)
            shift
            ;;
        esac
    done
    printf 'check:%s\n' "${config}" >>"${PADM_FAKE_SINGBOX_CHECK_LOG}"
    [[ "${PADM_FAKE_SINGBOX_CHECK_MODE:-success}" == "success" ]]
    exit
fi
[[ "$1" == "merge" ]] || exit 2
output=$2
shift 2
dest=
while [[ "$#" -gt 0 ]]; do
    case "$1" in
    -D)
        dest=$2
        shift 2
        ;;
    -C)
        shift 2
        ;;
    *)
        shift
        ;;
    esac
done
[[ -n "${dest}" ]] || exit 2
case "${PADM_FAKE_SINGBOX_MERGE_MODE:-success}" in
fail)
    exit 1
    ;;
empty)
    : >"${dest%/}/${output}"
    exit 0
    ;;
*)
    printf '{"merged":true}\n' >"${dest%/}/${output}"
    exit 0
    ;;
esac
SH
    chmod +x "${binary}"
    PADM_SINGBOX_BINARY="${binary}"
    singBoxConfigPath="${shardDir}/"
    export PADM_FAKE_SINGBOX_CHECK_LOG="${checkLog}"

    printf '{"old":true}\n' >"${outputFile}"
    export PADM_FAKE_SINGBOX_MERGE_MODE=fail
    set +e
    singBoxMergeConfig >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${outputFile}")" == '{"old":true}' ]]
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null

    export PADM_FAKE_SINGBOX_MERGE_MODE=empty
    set +e
    singBoxMergeConfig >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${outputFile}")" == '{"old":true}' ]]
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null

    export PADM_FAKE_SINGBOX_MERGE_MODE=success
    mv() {
        if [[ "$#" -eq 2 && "$2" == "${outputFile}" ]]; then
            printf 'commit\n' >"${commitMarker}"
            return 1
        fi
        command mv "$@"
    }
    set +e
    (
        singBoxMergeConfig >/dev/null 2>&1
    )
    rc=$?
    set -e
    unset -f mv
    [[ "${rc}" == "1" ]]
    [[ -e "${commitMarker}" ]]
    [[ "$(<"${outputFile}")" == '{"old":true}' ]]
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null

    singBoxMergeConfig
    [[ "$(<"${outputFile}")" == '{"merged":true}' ]]
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null

    printf '{"runtime":true}\n' >"${outputFile}"
    : >"${checkLog}"
    : >"${logFile}"
    export PADM_FAKE_SINGBOX_MERGE_MODE=success
    export PADM_FAKE_SINGBOX_CHECK_MODE=success
    singBoxMergeConfigForValidation "${binary}" "${logFile}" check
    [[ "$(<"${outputFile}")" == '{"runtime":true}' ]]
    grep -q '^check:' "${checkLog}"
    ! grep -qx "check:${outputFile}" "${checkLog}"
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null

    : >"${checkLog}"
    export PADM_FAKE_SINGBOX_CHECK_MODE=fail
    set +e
    singBoxMergeConfigForValidation "${binary}" "${logFile}" check >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${outputFile}")" == '{"runtime":true}' ]]
    grep -q '^check:' "${checkLog}"
    ! grep -qx "check:${outputFile}" "${checkLog}"
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null
)

runSingBoxUninstallFailurePropagationRegression() (
    local root="${TMP_DIR}/sing-box-uninstall-failure"
    local configDir="${root}/conf/config/"
    local serviceLog="${root}/service.log"
    local rmLog="${root}/rm.log"
    local errorLog="${root}/error.log"
    local rc

    mkdir -p "${configDir}"
    printf '{}\n' >"${configDir}config.json"
    : >"${serviceLog}"
    : >"${rmLog}"
    : >"${errorLog}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"

    singBoxConfigPath="${configDir}"
    readInstallType() { return 0; }
    serviceQueueRestart() {
        printf 'restart:%s\n' "$1" >>"${serviceLog}"
        return 0
    }
    serviceQueueApply() {
        printf 'apply\n' >>"${serviceLog}"
        return 1
    }

    set +e
    unInstallSingBox other >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'restart:sing-box' "${serviceLog}"
    grep -qx 'apply' "${serviceLog}"
    grep -q 'sing-box 服务重启失败' "${errorLog}"

    singBoxConfigPath=
    : >"${serviceLog}"
    : >"${rmLog}"
    : >"${errorLog}"
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    handleSingBox() {
        printf 'handle:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        return 1
    }
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    set +e
    unInstallSingBox >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'handle:stop:true' "${serviceLog}"
    grep -q 'sing-box 服务停止失败，已取消卸载' "${errorLog}"
    [[ ! -s "${rmLog}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
)

runSingBoxLogTransactionRegression() (
    local root="${TMP_DIR}/sing-box-log-transaction"
    local targetPath="${root}/conf/config/log.json"
    local serviceLog="${root}/service.log"
    local errorLog="${root}/error.log"
    local applyMode rc

    set +e
    mkdir -p "$(dirname "${targetPath}")" || return 1
    export PADM_SINGBOX_LOG_CONFIG_FILE="${targetPath}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    serviceQueueRestart() {
        printf 'restart:%s\n' "$1" >>"${serviceLog}"
        return 0
    }
    serviceQueueApply() {
        printf 'apply:%s\n' "${applyMode}" >>"${serviceLog}"
        [[ "${applyMode}" == "fail" ]] && return 1
        return 0
    }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    runSingBoxLogCase() {
        local disabled=$1
        local expectedRc=$2
        local rcFile="${root}/sing-box-log.rc"
        PADM_REGRESSION_APPLY_MODE="${applyMode}" \
            PADM_SINGBOX_LOG_CONFIG_FILE="${targetPath}" \
            bash -c '
                set +e
                source "$1/shell/core/runtime.sh"
                source "$1/shell/core/services.sh"
                source "$1/shell/core/cores.sh"
                serviceLog=$2
                errorLog=$3
                disabled=$4
                rcFile=$5
                serviceQueueRestart() {
                    printf "restart:%s\n" "$1" >>"${serviceLog}"
                    return 0
                }
                serviceQueueApply() {
                    printf "apply:%s\n" "${PADM_REGRESSION_APPLY_MODE}" >>"${serviceLog}"
                    [[ "${PADM_REGRESSION_APPLY_MODE}" == "fail" ]] && return 1
                    return 0
                }
                errorCard() { printf "%s\n" "$*" >>"${errorLog}"; }
                singBoxLog "${disabled}" >/dev/null 2>&1
                printf "%s\n" "$?" >"${rcFile}"
            ' _ "${PROJECT_ROOT}" "${serviceLog}" "${errorLog}" "${disabled}" "${rcFile}" || return 1
        rc=$(<"${rcFile}") || return 1
        if [[ "${rc}" != "${expectedRc}" ]]; then
            printf 'singBoxLog rc mismatch: expected=%s actual=%s\n' "${expectedRc}" "${rc}" >&2
            return 1
        fi
        return 0
    }

    printf '{"log":{"disabled":true,"level":"warning"}}\n' >"${targetPath}" || return 1
    : >"${serviceLog}" || return 1
    : >"${errorLog}" || return 1
    applyMode=fail
    runSingBoxLogCase false 1 || return 1
    jq -e '.log.disabled == true and .log.level == "warning"' "${targetPath}" >/dev/null || return 1
    grep -qx 'restart:sing-box' "${serviceLog}" || return 1
    grep -qx 'apply:fail' "${serviceLog}" || return 1
    grep -q 'sing-box 日志配置重载失败' "${errorLog}" || return 1
    ! compgen -G "$(dirname "${targetPath}")/.log.json.*" >/dev/null || return 1

    rm -f "${targetPath}" || return 1
    : >"${serviceLog}" || return 1
    : >"${errorLog}" || return 1
    applyMode=fail
    runSingBoxLogCase false 1 || return 1
    [[ ! -e "${targetPath}" ]] || return 1
    grep -qx 'restart:sing-box' "${serviceLog}" || return 1
    grep -qx 'apply:fail' "${serviceLog}" || return 1
    grep -q 'sing-box 日志配置重载失败' "${errorLog}" || return 1
    ! compgen -G "$(dirname "${targetPath}")/.log.json.*" >/dev/null || return 1

    : >"${serviceLog}" || return 1
    : >"${errorLog}" || return 1
    applyMode=success
    runSingBoxLogCase false 0 || return 1
    jq -e '.log.disabled == false and .log.level == "debug" and .log.output == "/etc/padm/sing-box/conf/box.log"' "${targetPath}" >/dev/null || return 1
    grep -qx 'restart:sing-box' "${serviceLog}" || return 1
    grep -qx 'apply:success' "${serviceLog}" || return 1
    [[ ! -s "${errorLog}" ]] || return 1
    ! compgen -G "$(dirname "${targetPath}")/.log.json.*" >/dev/null || return 1
    return 0
)

runSingBoxProtocolReloadFailureRegression() (
    local root="${TMP_DIR}/sing-box-protocol-reload-failure"
    local callLog="${root}/calls.log"
    local tuicRc hysteriaRc

    mkdir -p "${root}"
    : >"${callLog}"
    currentProtocolHasAny() { return 0; }
    installSingBox() {
        printf 'install:%s\n' "$*" >>"${callLog}"
        return 0
    }
    initSingBoxConfig() {
        printf 'config:%s\n' "$*" >>"${callLog}"
        return 0
    }
    installSingBoxService() {
        printf 'service:%s\n' "$*" >>"${callLog}"
        return 0
    }
    reloadCore() {
        printf 'reload\n' >>"${callLog}"
        return 1
    }
    set +e
    singBoxTuicInstall >/dev/null 2>&1
    tuicRc=$?
    set -e
    [[ "${tuicRc}" == "1" ]]
    grep -qx 'config:custom 2 true' "${callLog}"
    grep -qx 'reload' "${callLog}"

    : >"${callLog}"
    set +e
    singBoxHysteria2Install >/dev/null 2>&1
    hysteriaRc=$?
    set -e
    [[ "${hysteriaRc}" == "1" ]]
    grep -qx 'config:custom 2 true' "${callLog}"
    grep -qx 'reload' "${callLog}"
)

runGeoUpdateReloadFailureRegression() (
    local root="${TMP_DIR}/geo-update-reload-failure"
    local callLog="${root}/calls.log"
    local statusLog="${root}/status.log"
    local rc

    mkdir -p "${root}"
    : >"${callLog}"
    : >"${statusLog}"
    ensureXrayGeoFiles() {
        printf 'geo:%s\n' "$*" >>"${callLog}"
        return 0
    }
    reloadCore() {
        printf 'reload\n' >>"${callLog}"
        return 1
    }
    statusCard() {
        printf '%s\n' "$*" >>"${statusLog}"
    }

    set +e
    updateGeoSite >/dev/null 2>&1
    rc=$?
    set -e

    [[ "${rc}" == "1" ]]
    grep -qx 'geo:/etc/padm/xray force' "${callLog}"
    grep -qx 'reload' "${callLog}"
    grep -q '核心重载失败' "${statusLog}"
    ! grep -q '更新完毕' "${statusLog}"
)

runCoreCleanupFailurePropagationRegression() (
    local root="${TMP_DIR}/core-cleanup-failure"
    local serviceLog="${root}/service.log"
    local rmLog="${root}/rm.log"
    local errorLog="${root}/error.log"
    local rc

    mkdir -p "${root}"
    : >"${serviceLog}"
    : >"${rmLog}"
    : >"${errorLog}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"

    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        return 0
    }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        return 1
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        return 0
    }

    SERVICE_QUEUE_ALLOW_FAILURE=previous
    set +e
    cleanUp xrayDel >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -q 'Xray 服务停止失败，已取消清理旧核心' "${errorLog}"
    [[ ! -s "${rmLog}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    : >"${serviceLog}"
    : >"${rmLog}"
    : >"${errorLog}"
    readLastInstallationConfig() { return 0; }
    unInstallSubscribe() { return 0; }
    installTools() { return 0; }
    installSingBox() { return 0; }
    installSingBoxService() { return 0; }
    initSingBoxConfig() { return 0; }
    set +e
    installSingBoxReality >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'xray:stop:true' "${serviceLog}"
    [[ ! -s "${rmLog}" ]]
)

runReloadCorePropagationRegression() (
    local root="${TMP_DIR}/reload-core-propagation"
    local alpnConfig="${root}/alpn.json"
    local vlessConfig="${root}/vless.json"
    local vlessState="${root}/vless-state.json"
    local fakeXray="${root}/xray"
    local successMarker="${root}/success"
    local refreshMarker="${root}/refresh"
    local subscribeMarker="${root}/subscribe"
    local reloadLog="${root}/reloads"
    local originalContent rc

    mkdir -p "${root}/nginx"
    statusCard() { return 0; }
    successCard() {
        printf 'success\n' >>"${successMarker}"
        return 0
    }
    errorCard() { return 0; }
    echoContent() { return 0; }
    menuLine() { return 0; }
    menuClose() { return 0; }
    cleanDirectoryContent() { return 0; }

    cat >"${alpnConfig}" <<'JSON'
{"inbounds":[{"streamSettings":{"tlsSettings":{"alpn":["http/1.1"]}}}]}
JSON
    traditionalTlsFallbackConfigFile() { printf '%s\n' "${alpnConfig}"; }
    padmCreateTempFileForTarget() {
        local -n targetRef=$1
        local targetFile=$2
        targetRef="${targetFile}.tmp"
        return 0
    }
    padmRemoveCleanupPath() { rm -f "$1"; }
    commitGeneratedJsonFile() {
        local tmpFile=$1
        local targetFile=$2
        mv "${tmpFile}" "${targetFile}"
    }
    reloadCore() {
        printf 'reload\n' >>"${reloadLog}"
        return 1
    }

    originalContent=$(<"${alpnConfig}")
    rm -f "${successMarker}"
    set +e
    applyTraditionalTlsAlpn '["h2","http/1.1"]' >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${alpnConfig}")" == "${originalContent}" ]]
    [[ ! -e "${successMarker}" ]]
    [[ "$(wc -l <"${reloadLog}" | tr -d ' ')" == "2" ]]

    printf '%s\n' "${originalContent}" >"${alpnConfig}"
    rm -f "${successMarker}" "${alpnConfig}.alpn.bak"
    (
        mv() {
            if [[ "$1" == "${alpnConfig}.alpn.bak" && "$2" == "${alpnConfig}" ]]; then
                return 1
            fi
            command mv "$@"
        }
        set +e
        applyTraditionalTlsAlpn '["h2","http/1.1"]' >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        jq -e '.inbounds[0].streamSettings.tlsSettings.alpn == ["h2","http/1.1"]' "${alpnConfig}" >/dev/null
        [[ "$(<"${alpnConfig}.alpn.bak")" == "${originalContent}" ]]
        [[ ! -e "${successMarker}" ]]
    ) || return 1
    printf '%s\n' "${originalContent}" >"${alpnConfig}"
    rm -f "${alpnConfig}.alpn.bak"

    cat >"${fakeXray}" <<'SH'
#!/usr/bin/env bash
case "$1" in
--version)
    printf 'Xray 25.9.5\n'
    ;;
vlessenc)
    printf '{"encryption":"mlkem768x25519plus.native.enc","decryption":"mlkem768x25519plus.native.dec"}\n'
    ;;
-test)
    exit 0
    ;;
esac
SH
    chmod +x "${fakeXray}"
    cat >"${vlessConfig}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"id":"u","flow":"xtls-rprx-vision"}],"decryption":"none","fallbacks":[]}}]}
JSON
    originalContent=$(<"${vlessConfig}")
    coreInstallType=1
    PADM_XRAY_BINARY="${fakeXray}"
    PADM_XRAY_CONF_DIR="${root}"
    PADM_VLESS_REALITY_CONFIG_FILE="${vlessConfig}"
    PADM_VLESS_XHTTP_CONFIG_FILE="${root}/missing-xhttp.json"
    PADM_VLESS_ENCRYPTION_STATE_FILE="${vlessState}"
    readNginxSubscribe() {
        printf 'refresh\n' >"${refreshMarker}"
        subscribePort=443
        nginxConfigPath="${root}/nginx/"
    }
    subscribe() { return 0; }

    rm -f "${refreshMarker}" "${vlessState}" "${reloadLog}"
    set +e
    setVlessRealityEncryption enable >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${vlessConfig}")" == "${originalContent}" ]]
    [[ ! -e "${vlessState}" ]]
    [[ ! -e "${refreshMarker}" ]]
    [[ "$(wc -l <"${reloadLog}" | tr -d ' ')" == "2" ]]

    printf '%s\n' "${originalContent}" >"${vlessConfig}"
    rm -f "${refreshMarker}" "${vlessState}" "${vlessConfig}.vlessenc.bak" "${vlessState}.bak" "${vlessState}.tmp"
    (
        cp() {
            if [[ "$1" == "${vlessConfig}" && "$2" == "${vlessConfig}.vlessenc.bak" ]]; then
                return 1
            fi
            command cp "$@"
        }
        reloadCore() { return 0; }
        set +e
        setVlessRealityEncryption enable >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ "$(<"${vlessConfig}")" == "${originalContent}" ]]
        [[ ! -e "${vlessConfig}.vlessenc.bak" ]]
        [[ ! -e "${vlessState}" ]]
        [[ ! -e "${refreshMarker}" ]]
    ) || return 1

    printf '%s\n' "${originalContent}" >"${vlessConfig}"
    rm -f "${refreshMarker}" "${vlessState}" "${vlessConfig}.vlessenc.bak" "${vlessState}.bak" "${vlessState}.tmp"
    (
        mv() {
            if [[ "$1" == "${vlessState}.tmp" && "$2" == "${vlessState}" ]]; then
                return 1
            fi
            command mv "$@"
        }
        reloadCore() { return 0; }
        set +e
        setVlessRealityEncryption enable >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ "$(<"${vlessConfig}")" == "${originalContent}" ]]
        [[ ! -e "${vlessConfig}.vlessenc.bak" ]]
        [[ ! -e "${vlessState}" ]]
        [[ ! -e "${vlessState}.tmp" ]]
        [[ ! -e "${refreshMarker}" ]]
    ) || return 1

    printf '%s\n' "${originalContent}" >"${vlessConfig}"
    rm -f "${refreshMarker}" "${vlessState}" "${vlessConfig}.vlessenc.bak" "${vlessState}.bak" "${vlessState}.tmp"
    (
        mv() {
            if [[ "$1" == "${vlessConfig}.vlessenc.bak" && "$2" == "${vlessConfig}" ]]; then
                return 1
            fi
            command mv "$@"
        }
        set +e
        setVlessRealityEncryption enable >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        jq -e '.inbounds[0].settings.decryption == "mlkem768x25519plus.native.dec"' "${vlessConfig}" >/dev/null
        [[ "$(<"${vlessConfig}.vlessenc.bak")" == "${originalContent}" ]]
        [[ -e "${vlessState}" ]]
        [[ ! -e "${refreshMarker}" ]]
    ) || return 1
    printf '%s\n' "${originalContent}" >"${vlessConfig}"
    rm -f "${vlessState}" "${vlessConfig}.vlessenc.bak" "${vlessState}.bak" "${vlessState}.tmp"

    reloadCore() { printf 'reload\n' >>"${reloadLog}"; return 0; }
    subscribe() {
        printf 'subscribe\n' >"${subscribeMarker}"
        return 1
    }
    readNginxSubscribe() {
        subscribePort=443
        nginxConfigPath="${root}/nginx/"
    }
    rm -f "${refreshMarker}" "${subscribeMarker}" "${reloadLog}" "${vlessState}" "${vlessConfig}.vlessenc.bak" "${vlessState}.bak" "${vlessState}.tmp"
    set +e
    setVlessRealityEncryption enable >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${vlessConfig}")" == "${originalContent}" ]]
    [[ ! -e "${vlessState}" ]]
    [[ ! -e "${vlessConfig}.vlessenc.bak" ]]
    [[ ! -e "${vlessState}.bak" ]]
    [[ -e "${subscribeMarker}" ]]
    [[ "$(wc -l <"${reloadLog}" | tr -d ' ')" == "2" ]]

    reloadCore() { return 0; }
    subscribe() { return 1; }
    readNginxSubscribe() {
        subscribePort=443
        nginxConfigPath="${root}/nginx/"
    }
    set +e
    refreshVlessEncryptionSubscriptions >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]

    subscribePort=
    readNginxSubscribe() {
        subscribePort=
        nginxConfigPath="${root}/nginx/"
    }
    showAccounts() { return 1; }
    set +e
    refreshVlessEncryptionSubscriptions >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]

    initXrayConfig() { return 0; }
    reloadCore() { return 1; }
    subscribe() {
        printf 'subscribe\n' >"${subscribeMarker}"
        return 0
    }
    rm -f "${subscribeMarker}"
    set +e
    regenerateRealityProfile >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -e "${subscribeMarker}" ]]

    reloadCore() { return 0; }
    subscribe() {
        printf 'subscribe\n' >"${subscribeMarker}"
        return 1
    }
    rm -f "${subscribeMarker}"
    set +e
    regenerateRealityProfile >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${subscribeMarker}" ]]
)

runConfigTransactionRegression() {
    local targetFile="${TMP_DIR}/transaction.json"
    local backupFile="${targetFile}.bak"
    local originalContent updatedContent
    local reloadCountFile="${TMP_DIR}/transaction-reload-count"
    local refreshCountFile="${TMP_DIR}/transaction-refresh-count"
    local validateMode=success
    local reloadMode=success
    local refreshMode=success
    local oldPath="${PATH}"
    local oldTmpDir="${TMPDIR:-}"
    local checkPortTmpRoot="${TMP_DIR}/check-port-tmp"
    local checkPortNginxDir="${TMP_DIR}/check-port-nginx/"
    local checkPortTarget="${checkPortNginxDir}checkPortOpen.conf"
    mkdir -p "${checkPortTmpRoot}"
    TMPDIR="${checkPortTmpRoot}"

    transactionReloadMock() {
        printf '1\n' >>"${reloadCountFile}"
        [[ "${reloadMode}" == "success" ]]
    }

    transactionRefreshMock() {
        printf '1\n' >>"${refreshCountFile}"
        [[ "${refreshMode}" == "success" ]]
    }

    transactionValidateMock() {
        [[ "${validateMode}" == "success" ]]
    }

    cat >"${targetFile}" <<'JSON'
{"mode":"old","port":443}
JSON
    originalContent=$(<"${targetFile}")
    jq '.mode = "new"' "${targetFile}" >"${targetFile}.tmp"
    validateMode=fail
    if configTransactionCommit "${targetFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock; then
        return 1
    fi
    [[ "$(<"${targetFile}")" == "${originalContent}" ]]
    [[ ! -e "${targetFile}.tmp" ]]
    [[ ! -e "${backupFile}" ]]
    [[ ! -e "${reloadCountFile}" ]]
    [[ ! -e "${refreshCountFile}" ]]

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    originalContent=$(<"${targetFile}")
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${targetFile}.tmp"
    validateMode=fail
    (
        mv() {
            if [[ "$1" == "${backupFile}" && "$2" == "${targetFile}" ]]; then
                return 1
            fi
            command mv "$@"
        }
        if configTransactionCommit "${targetFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
            return 1
        fi
        [[ "$(<"${targetFile}")" != "${originalContent}" ]]
        jq -e '.mode == "new" and .port == 8443' "${targetFile}" >/dev/null
        [[ "$(<"${backupFile}")" == "${originalContent}" ]]
        [[ ! -e "${targetFile}.tmp" ]]
        [[ ! -e "${reloadCountFile}" ]]
        [[ ! -e "${refreshCountFile}" ]]
    ) || return 1

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    rm -f "${backupFile}"
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${targetFile}.tmp"
    validateMode=success
    configTransactionCommit "${targetFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock
    updatedContent=$(<"${targetFile}")
    [[ "${updatedContent}" != "${originalContent}" ]]
    jq -e '.mode == "new" and .port == 8443' "${targetFile}" >/dev/null
    [[ ! -e "${targetFile}.tmp" ]]
    [[ ! -e "${backupFile}" ]]
    [[ "$(wc -l <"${reloadCountFile}" | tr -d ' ')" == "1" ]]
    [[ "$(wc -l <"${refreshCountFile}" | tr -d ' ')" == "1" ]]

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    originalContent=$(<"${targetFile}")
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${targetFile}.tmp"
    reloadMode=fail
    refreshMode=success
    if configTransactionCommit "${targetFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(<"${targetFile}")" == "${originalContent}" ]]
    [[ ! -e "${targetFile}.tmp" ]]
    [[ ! -e "${backupFile}" ]]
    [[ "$(wc -l <"${reloadCountFile}" | tr -d ' ')" == "2" ]]
    [[ ! -e "${refreshCountFile}" ]]

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${targetFile}.tmp"
    reloadMode=success
    refreshMode=fail
    if configTransactionCommit "${targetFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
        return 1
    fi
    jq -e '.mode == "new" and .port == 8443' "${targetFile}" >/dev/null
    [[ ! -e "${targetFile}.tmp" ]]
    [[ ! -e "${backupFile}" ]]
    [[ "$(wc -l <"${reloadCountFile}" | tr -d ' ')" == "1" ]]
    [[ "$(wc -l <"${refreshCountFile}" | tr -d ' ')" == "1" ]]
    refreshMode=success

    local refreshFailureLog="${TMP_DIR}/transaction-refresh-failure.log"
    readNginxSubscribe() {
        subscribePort=443
        nginxConfigPath="${TMP_DIR}/nginx-refresh/"
    }
    subscribe() {
        printf 'subscribe:%s\n' "$*" >>"${refreshFailureLog}"
        return 1
    }
    showAccounts() {
        printf 'showAccounts\n' >>"${refreshFailureLog}"
        return 1
    }
    errorCard() { return 0; }
    rm -f "${refreshFailureLog}"
    if refreshXHTTPSubscriptions >/dev/null 2>&1; then
        return 1
    fi
    grep -qx 'subscribe:renew' "${refreshFailureLog}"

    readNginxSubscribe() {
        subscribePort=
        nginxConfigPath="${TMP_DIR}/nginx-refresh/"
    }
    rm -f "${refreshFailureLog}"
    if refreshTuicSubscriptions >/dev/null 2>&1; then
        return 1
    fi
    grep -qx 'showAccounts' "${refreshFailureLog}"

    (
        cleanDirectoryContent() {
            printf 'cleanDirectoryContent\n' >>"${refreshFailureLog}"
            return 1
        }
        readNginxSubscribe() {
            subscribePort=
            nginxConfigPath="${TMP_DIR}/nginx-refresh/"
        }
        rm -f "${refreshFailureLog}"
        set +e
        refreshVlessEncryptionSubscriptions >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -qx 'cleanDirectoryContent' "${refreshFailureLog}"
    ) || return 1

    mkdir -p "${TMP_DIR}/fake-bin" "${checkPortNginxDir}"
    cat >"${TMP_DIR}/fake-bin/nginx" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "-t" ]]
printf 'check-port validate %s\n' "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}"
[[ "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}" == "success" ]]
SH
    chmod +x "${TMP_DIR}/fake-bin/nginx"
    PATH="${TMP_DIR}/fake-bin:${PATH}"
    nginxConfigPath="${checkPortNginxDir}"
    printf 'old config\n' >"${checkPortTarget}"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    if writeCheckPortOpenNginxConfig 443 example.com '' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${checkPortTarget}")" == "old config" ]]
    grep -qxF 'check-port validate fail' "${checkPortTmpRoot}/padm-check-port-open-nginx-test.log"
    [[ ! -e "${checkPortTarget}.tmp" ]]

    printf 'old config\n' >"${checkPortTarget}"
    rm -f "${checkPortTarget}.bak"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    (
        mv() {
            if [[ "$1" == "${checkPortTarget}.bak" && "$2" == "${checkPortTarget}" ]]; then
                return 1
            fi
            command mv "$@"
        }
        if writeCheckPortOpenNginxConfig 443 example.com '' 2>/dev/null; then
            return 1
        fi
        [[ "${CHECK_PORT_OPEN_NGINX_CONFIG_ERROR}" == *"旧配置恢复失败"* ]]
        [[ "$(<"${checkPortTarget}")" != "old config" ]]
        [[ "$(<"${checkPortTarget}.bak")" == "old config" ]]
        [[ ! -e "${checkPortTarget}.tmp" ]]
    ) || return 1
    printf 'old config\n' >"${checkPortTarget}"
    rm -f "${checkPortTarget}.bak"

    export PADM_FAKE_NGINX_VALIDATE_MODE=success
    writeCheckPortOpenNginxConfig 443 example.com 'listen [::]:443;'
    grep -qxF 'check-port validate success' "${checkPortTmpRoot}/padm-check-port-open-nginx-test.log"
    grep -q 'server_name example.com;' "${checkPortTarget}"
    grep -q 'listen \[::\]:443;' "${checkPortTarget}"
    [[ ! -e "${checkPortTarget}.tmp" ]]
    [[ ! -e "${checkPortTarget}.bak" ]]
    PATH="${oldPath}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    unset PADM_FAKE_NGINX_VALIDATE_MODE
}

runNginxServiceFailureRegression() {
    (
        set -euo pipefail
        local serviceTmp
        local fakeBin
        serviceTmp=$(mktemp -d)
        fakeBin="${serviceTmp}/bin"
        mkdir -p "${fakeBin}" "${serviceTmp}/etc-padm"

        cat >"${fakeBin}/systemctl" <<'SH'
#!/usr/bin/env bash
case "$1" in
start)
    [[ "${PADM_FAKE_SYSTEMCTL_START_RC:-0}" == "0" ]] || exit "${PADM_FAKE_SYSTEMCTL_START_RC}"
    printf '%s\n' "${PADM_FAKE_SYSTEMCTL_START_STATE:-true}" >"${PADM_FAKE_NGINX_STATE_FILE}"
    ;;
stop)
    [[ "${PADM_FAKE_SYSTEMCTL_STOP_RC:-0}" == "0" ]] || exit "${PADM_FAKE_SYSTEMCTL_STOP_RC}"
    printf '%s\n' "${PADM_FAKE_SYSTEMCTL_STOP_STATE:-false}" >"${PADM_FAKE_NGINX_STATE_FILE}"
    ;;
*)
    exit 0
    ;;
esac
SH
        cat >"${fakeBin}/pgrep" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-x" && "$2" == "nginx" && "$(cat "${PADM_FAKE_NGINX_STATE_FILE}" 2>/dev/null)" == "true" ]]; then
    printf '12345\n'
    exit 0
fi
exit 1
SH
        cat >"${fakeBin}/kill" <<'SH'
#!/usr/bin/env bash
printf 'false\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
SH
        cat >"${fakeBin}/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
        cat >"${fakeBin}/nginx" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-s" && "$2" == "stop" ]]; then
    printf 'false\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
fi
exit 0
SH
        chmod +x "${fakeBin}/systemctl" "${fakeBin}/pgrep" "${fakeBin}/kill" "${fakeBin}/sleep" "${fakeBin}/nginx"

        PATH="${fakeBin}:${PATH}"
        source "${PROJECT_ROOT}/shell/core/protocols.sh"
        source "${PROJECT_ROOT}/shell/core/services.sh"
        echoContent() { return 0; }
        successCard() { return 0; }
        statusCard() { return 0; }
        errorCard() { return 0; }
        updateSELinuxHTTPPortT() { return 0; }
        protocolSelectionSkipsNginx() { return 1; }
        nginxServiceInstalled() { return 0; }
        release=centos
        selectCustomInstallType=
        btDomain=panel.example.com
        SERVICE_QUEUE_ALLOW_FAILURE=true
        export PADM_FAKE_NGINX_STATE_FILE="${serviceTmp}/nginx-running"
        export PADM_NGINX_ERROR_LOG="${serviceTmp}/nginx-error.log"

        printf 'false\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
        PADM_FAKE_SYSTEMCTL_START_RC=0 PADM_FAKE_SYSTEMCTL_START_STATE=false handleNginx start >/dev/null 2>&1 && return 1
        printf 'true\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
        PADM_FAKE_SYSTEMCTL_STOP_RC=0 PADM_FAKE_SYSTEMCTL_STOP_STATE=true handleNginx stop >/dev/null 2>&1
        [[ "$(cat "${PADM_FAKE_NGINX_STATE_FILE}")" == "false" ]]
        printf 'false\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
        PADM_FAKE_SYSTEMCTL_START_RC=0 PADM_FAKE_SYSTEMCTL_START_STATE=true handleNginx start >/dev/null 2>&1
        printf 'true\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
        PADM_FAKE_SYSTEMCTL_STOP_RC=0 PADM_FAKE_SYSTEMCTL_STOP_STATE=false handleNginx stop >/dev/null 2>&1
        printf 'false\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
        SERVICE_ACTIONS=
        serviceQueueStart nginx
        serviceQueueStop nginx
        if PADM_FAKE_SYSTEMCTL_START_RC=0 PADM_FAKE_SYSTEMCTL_START_STATE=false serviceQueueApply >/dev/null 2>&1; then
            return 1
        fi
        [[ -z "${SERVICE_ACTIONS}" ]]
        rm -rf "${serviceTmp}"
    )
}


runUninstallWireGuardCleanupRegression() (
    local actions=
    local targetDir="${TMP_DIR}/uninstall-wireguard"
    local oldWireGuardDir="${PADM_WIREGUARD_CONTROL_DIR:-}"
    PADM_WIREGUARD_CONTROL_DIR="${targetDir}/state"
    mkdir -p "${PADM_WIREGUARD_CONTROL_DIR}" "${targetDir}/etc-wireguard" "${targetDir}/systemd"
    subscriptionWireGuardWriteState '.enabled = true'
    removeInstallPath() { actions+="remove:$1:$2"$'\n'; rm -rf "$1"; }
    systemctl() { actions+="systemctl:$*"$'\n'; return 0; }
    command() {
        if [[ "$1" == "-v" && "$2" == "systemctl" ]]; then
            return 0
        fi
        builtin command "$@"
    }
    subscriptionWireGuardConfigFile() { printf '%s\n' "${targetDir}/etc-wireguard/wg-padm.conf"; }
    subscriptionControlServiceFile() { printf '%s\n' "${targetDir}/systemd/padm-subscription-control.service"; }
    printf 'wg\n' >"$(subscriptionWireGuardConfigFile)"
    printf 'svc\n' >"$(subscriptionControlServiceFile)"
    cleanupSubscriptionWireGuardControlOnUninstall
    grep -qxF 'systemctl:disable --now wg-quick@wg-padm' <<<"${actions}"
    grep -qxF 'systemctl:disable --now padm-subscription-control.service' <<<"${actions}"
    [[ ! -e "$(subscriptionWireGuardConfigFile)" ]]
    [[ ! -e "$(subscriptionControlServiceFile)" ]]
    if [[ -n "${oldWireGuardDir}" ]]; then PADM_WIREGUARD_CONTROL_DIR="${oldWireGuardDir}"; else unset PADM_WIREGUARD_CONTROL_DIR; fi
)
runUninstallNginxCleanupRegression() {
    local primaryDir="${TMP_DIR}/uninstall-nginx-primary/"
    local actualDir="${TMP_DIR}/uninstall-nginx-actual/"
    local oldNginxConfigPath="${nginxConfigPath:-}"
    local oldFallbackDir="${PADM_NGINX_CONF_FALLBACK_DIR:-}"
    local name

    mkdir -p "${primaryDir}" "${actualDir}"
    nginxConfigPath="${primaryDir}"
    PADM_NGINX_CONF_FALLBACK_DIR="${actualDir}"
    for name in alone.conf checkPortOpen.conf sing_box_VMess_HTTPUpgrade.conf subscribe.conf padm-control-wg.conf; do
        printf 'padm config\n' >"${primaryDir}${name}"
    done
    for name in sing_box_VMess_HTTPUpgrade.conf subscribe.conf padm-control-wg.conf; do
        printf 'padm config\n' >"${actualDir}${name}"
    done

    removePadmNginxConfigFragments
    for name in alone.conf checkPortOpen.conf sing_box_VMess_HTTPUpgrade.conf subscribe.conf padm-control-wg.conf; do
        [[ ! -e "${primaryDir}${name}" ]]
    done
    for name in sing_box_VMess_HTTPUpgrade.conf subscribe.conf padm-control-wg.conf; do
        [[ ! -e "${actualDir}${name}" ]]
    done
    nginxConfigPath="${oldNginxConfigPath}"
    PADM_NGINX_CONF_FALLBACK_DIR="${oldFallbackDir}"
}

runUninstallServiceStopFailureRegression() (
    local root="${TMP_DIR}/uninstall-service-stop"
    local serviceLog="${root}/service.log"
    local actionLog="${root}/actions.log"
    local errorLog="${root}/errors.log"
    local rcFile="${root}/uninstall.rc"
    local mode shellRc

    mkdir -p "${root}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    autoRead() { printf -v "$3" 'y'; }
    statusCard() { return 0; }
    successCard() { return 0; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    menu() { return 0; }
    pgrep() { return 1; }
    removeInstallPath() {
        printf 'remove:%s:%s\n' "$1" "$2" >>"${actionLog}"
        return 0
    }
    cleanupSubscriptionWireGuardControlOnUninstall() {
        printf 'wireguard-cleanup\n' >>"${actionLog}"
        return 0
    }
    removePadmNginxConfigFragments() {
        printf 'nginx-fragments\n' >>"${actionLog}"
        return 0
    }
    unInstallSubscribe() {
        printf 'unsubscribe-cleanup\n' >>"${actionLog}"
        return 0
    }
    handleNginx() {
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        if [[ "${mode}" == "nginx-stop-fail" && "$1" == "stop" ]]; then
            [[ "${SERVICE_QUEUE_ALLOW_FAILURE:-}" == "true" ]] && return 1
            exit 0
        fi
        return 0
    }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        if [[ "${mode}" == "xray-stop-fail" && "$1" == "stop" ]]; then
            [[ "${SERVICE_QUEUE_ALLOW_FAILURE:-}" == "true" ]] && return 1
            exit 0
        fi
        return 0
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        if [[ "${mode}" == "sing-box-stop-fail" && "$1" == "stop" ]]; then
            [[ "${SERVICE_QUEUE_ALLOW_FAILURE:-}" == "true" ]] && return 1
            exit 0
        fi
        return 0
    }

    runUninstallStopFailureCase() {
        mode=$1
        : >"${serviceLog}"
        : >"${actionLog}"
        : >"${errorLog}"
        rm -f "${rcFile}"
        release=centos
        coreInstallType=1
        singBoxConfigPath="${root}/sing-box-conf/"
        nginxStaticPath="${root}/static"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        set +e
        (
            set +e
            unInstall >/dev/null 2>&1
            printf '%s\n' "$?" >"${rcFile}"
        )
        shellRc=$?
        set -e
        [[ "${shellRc}" == "0" ]]
        [[ "$(<"${rcFile}")" == "1" ]]
        grep -qx 'nginx:stop:true' "${serviceLog}"
        grep -qx 'xray:stop:true' "${serviceLog}"
        grep -qx 'sing-box:stop:true' "${serviceLog}"
        grep -qxF 'remove:/etc/padm:PADM配置目录' "${actionLog}"
        grep -qxF 'unsubscribe-cleanup' "${actionLog}"
        grep -q '卸载未完全完成' "${errorLog}"
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    }

    runUninstallStopFailureCase nginx-stop-fail
    runUninstallStopFailureCase xray-stop-fail
    runUninstallStopFailureCase sing-box-stop-fail
)

runCleanLastInstallationConfigFailureRegression() (
    local root="${TMP_DIR}/clean-last-installation"
    local serviceLog="${root}/service.log"
    local cleanupLog="${root}/cleanup.log"
    local errorLog="${root}/error.log"
    local installLog="${root}/install.log"
    local mode rc

    mkdir -p "${root}/nginx" "${root}/static"
    : >"${serviceLog}"
    : >"${cleanupLog}"
    : >"${errorLog}"
    : >"${installLog}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"

    currentDefaultPort=443
    currentPort=
    customPort=
    xrayVLESSRealityPort=
    xrayVLESSRealityXHTTPort=
    singBoxVLESSVisionPort=
    singBoxVLESSRealityVisionPort=
    singBoxVLESSRealityGRPCPort=
    singBoxHysteria2Port=
    singBoxTuicPort=
    singBoxSocks5Port=
    hysteriaPort=
    tuicPort=
    nginxConfigPath="${root}/nginx/"
    nginxStaticPath="${root}/static"
    configPath="${root}/xray-conf/"

    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "xray-stop-fail" ]] && return 1
        return 0
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "sing-box-stop-fail" ]] && return 1
        return 0
    }
    handleNginx() {
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "nginx-stop-fail" ]] && return 1
        return 0
    }
    cleanAgentNginxConf() {
        printf 'clean-agent\n' >>"${cleanupLog}"
        [[ "${mode}" != "clean-fail" ]]
    }
    cleanDirectoryContent() {
        printf 'clean-dir:%s\n' "$1" >>"${cleanupLog}"
        [[ "${mode}" == "clean-dir-tls-fail" && "$1" == "/etc/padm/tls" ]] && return 1
        return 0
    }
    readInstallType() { printf 'read-install-type\n' >>"${cleanupLog}"; }
    mkdirTools() { printf 'mkdir-tools\n' >>"${cleanupLog}"; }
    statusCard() { return 0; }
    successCard() { return 0; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    showLastInstallationConfig() { return 0; }
    autoRead() { printf -v "$3" 'n'; }
    lsof() { return 1; }
    systemctl() {
        printf 'systemctl:%s\n' "$*" >>"${cleanupLog}"
        [[ "${mode}" == "daemon-reload-fail" && "$*" == "daemon-reload" ]] && return 1
        return 0
    }
    rm() {
        printf 'rm:%s\n' "$*" >>"${cleanupLog}"
        [[ "${mode}" == "rm-warp-fail" && "$*" == "-rf /etc/padm/warp/config" ]] && return 1
        return 0
    }

    runCleanFailureCase() {
        local failureMode=$1
        mode="${failureMode}"
        : >"${serviceLog}"
        : >"${cleanupLog}"
        : >"${errorLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        set +e
        cleanLastInstallationConfig >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
        [[ ! -s "${cleanupLog}" ]]
        grep -q '已取消清空上次安装配置' "${errorLog}"
    }

    runCleanFailureCase xray-stop-fail
    grep -qx 'xray:stop:true' "${serviceLog}"
    ! grep -q '^sing-box:' "${serviceLog}"

    runCleanFailureCase sing-box-stop-fail
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    ! grep -q '^nginx:' "${serviceLog}"

    runCleanFailureCase nginx-stop-fail
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    grep -qx 'nginx:stop:true' "${serviceLog}"

    mode=clean-fail
    : >"${serviceLog}"
    : >"${cleanupLog}"
    : >"${errorLog}"
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    set +e
    cleanLastInstallationConfig >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    grep -qx 'nginx:stop:true' "${serviceLog}"
    grep -qx 'clean-agent' "${cleanupLog}"
    ! grep -q '^clean-dir:' "${cleanupLog}"
    ! grep -q '^read-install-type$' "${cleanupLog}"
    grep -q 'Nginx 配置清理失败，已取消清空上次安装配置' "${errorLog}"

    runCleanupStepFailureCase() {
        local failureMode=$1
        local expectedError=$2
        local expectedLastStep=$3
        local forbiddenNextStep=$4
        mode="${failureMode}"
        : >"${serviceLog}"
        : >"${cleanupLog}"
        : >"${errorLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        set +e
        cleanLastInstallationConfig >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
        grep -qx 'xray:stop:true' "${serviceLog}"
        grep -qx 'sing-box:stop:true' "${serviceLog}"
        grep -qx 'nginx:stop:true' "${serviceLog}"
        grep -qxF "${expectedLastStep}" "${cleanupLog}"
        ! grep -qxF "${forbiddenNextStep}" "${cleanupLog}"
        ! grep -q '^read-install-type$' "${cleanupLog}"
        ! grep -q '^mkdir-tools$' "${cleanupLog}"
        grep -q "${expectedError}" "${errorLog}"
    }

    runCleanupStepFailureCase clean-dir-tls-fail \
        'TLS 目录清理失败，已取消清空上次安装配置' \
        'clean-dir:/etc/padm/tls' \
        'clean-dir:/etc/padm/subscribe'

    runCleanupStepFailureCase rm-warp-fail \
        'WARP 配置清理失败，已取消清空上次安装配置' \
        'rm:-rf /etc/padm/warp/config' \
        'rm:-f /etc/padm/cdn'

    runCleanupStepFailureCase daemon-reload-fail \
        'systemd 配置重载失败，已取消清空上次安装配置' \
        'systemctl:daemon-reload' \
        'read-install-type'

    mode=xray-stop-fail
    : >"${serviceLog}"
    : >"${cleanupLog}"
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    set +e
    readLastInstallationConfig >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'xray:stop:true' "${serviceLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    mode=xray-stop-fail
    : >"${serviceLog}"
    : >"${cleanupLog}"
    : >"${installLog}"
    btDomain=
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    set +e
    xrayCoreInstall >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'xray:stop:true' "${serviceLog}"
    [[ ! -s "${installLog}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
)

appendDefaultSubscribeLine() {
    local user=$1
    local line=$2
    mkdir -p "${SUBSCRIBE_CAPTURE_DIR}/default"
    printf '%s\n' "${line}" >>"${SUBSCRIBE_CAPTURE_DIR}/default/${user}"
}

appendClashMetaSubscribeBlock() {
    local user=$1
    local block=$2
    mkdir -p "${SUBSCRIBE_CAPTURE_DIR}/clashMeta"
    printf '%s\n' "${block}" >>"${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"
}

appendSingBoxSubscribeLocalConfig() {
    local user=$1
    local jqFilter=$2
    local targetPath="${SUBSCRIBE_CAPTURE_DIR}/sing-box/${user}"
    local tmpPath="${targetPath}.tmp"
    mkdir -p "${SUBSCRIBE_CAPTURE_DIR}/sing-box"
    [[ -f "${targetPath}" ]] || printf '[]\n' >"${targetPath}"
    if ! jq -r "${jqFilter}" "${targetPath}" | jq . >"${tmpPath}"; then
        rm -f "${tmpPath}"
        return 1
    fi
    mv "${tmpPath}" "${targetPath}"
}

runSingBoxSubscribeWriteRegression() {
    local targetPath="${SUBSCRIBE_CAPTURE_DIR}/sing-box/atomic-user"
    mkdir -p "${SUBSCRIBE_CAPTURE_DIR}/sing-box"
    printf '[{"tag":"old"}]\n' >"${targetPath}"
    if appendSingBoxSubscribeLocalConfig atomic-user '. += [' 2>/dev/null; then
        return 1
    fi
    jq -e '.[0].tag == "old"' "${targetPath}" >/dev/null
    [[ ! -e "${targetPath}.tmp" ]]
    appendSingBoxSubscribeLocalConfig atomic-user '. += [{"tag":"new"}]'
    jq -e 'length == 2 and .[1].tag == "new"' "${targetPath}" >/dev/null
}

runSubscribeServerNameRegression() {
    local oldCurrentHost="${currentHost:-}"
    local oldDomain="${domain:-}"
    local oldTlsDir="${PADM_TLS_DIR:-}"
    local tlsDir="${TMP_DIR}/subscribe-tls"
    mkdir -p "${tlsDir}"

    currentHost=host.example.com
    domain=
    [[ "$(resolveSubscribeServerName)" == "host.example.com" ]]

    currentHost=
    domain=domain.example.com
    [[ "$(resolveSubscribeServerName)" == "domain.example.com" ]]

    currentHost=
    domain=
    export PADM_TLS_DIR="${tlsDir}"
    printf 'cert\n' >"${tlsDir}/cert.example.com.crt"
    printf 'key\n' >"${tlsDir}/cert.example.com.key"
    [[ "$(resolveSubscribeServerName)" == "cert.example.com" ]]

    currentHost="${oldCurrentHost}"
    domain="${oldDomain}"
    if [[ -n "${oldTlsDir}" ]]; then
        PADM_TLS_DIR="${oldTlsDir}"
    else
        unset PADM_TLS_DIR
    fi
}

runSubscribeNginxConfigWriteRegression() {
    local targetPath="${TMP_DIR}/nginx-subscribe/subscribe.conf"
    local oldPath="${PATH}"
    local oldTmpDir="${TMPDIR:-}"
    local nginxTmpRoot="${TMP_DIR}/nginx-subscribe-tmp"
    mkdir -p "${TMP_DIR}/fake-bin" "${TMP_DIR}/nginx-subscribe" "${nginxTmpRoot}"
    TMPDIR="${nginxTmpRoot}"
    nginxConfigPath="${TMP_DIR}/nginx-subscribe/"
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
        local backupGlob="${TMP_DIR}/nginx-subscribe/.subscribe.conf.backup.*"
        local backups=()
        mv() {
            if [[ "$1" == "${TMP_DIR}/nginx-subscribe/.subscribe.conf.backup."* && "$2" == "${targetPath}" ]]; then
                return 1
            fi
            command mv "$@"
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
        rm() {
            if [[ "$1" == "-f" && "$2" == "${targetPath}" ]]; then
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
}

runSubscribeNginxServiceFailureRegression() (
    local root="${TMP_DIR}/subscribe-nginx-service-failure"
    local oldPath="${PATH}"
    local serviceLog="${root}/service.log"
    local errorLog="${root}/error.log"
    local mode=reload
    local rc writeCalls controlCalls bootCalls

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
    currentHost=subscribe.example.com
    printf 'cert\n' >"${PADM_TLS_DIR}/subscribe.example.com.crt"
    printf 'key\n' >"${PADM_TLS_DIR}/subscribe.example.com.key"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    : >"${serviceLog}"
    : >"${errorLog}"

    readNginxSubscribe() {
        if [[ "${mode}" == "reload" || "${mode}" == "config-fail" ]]; then
            subscribePort=
        else
            subscribePort=39778
        fi
    }
    readSingBoxPortResult() {
        local -n resultRef=$1
        resultRef=(39778)
        return 0
    }
    nginxBlog() { return 0; }
    hasIPv6Connectivity() { return 1; }
    writeSubscribeNginxConfig() {
        writeCalls=$((writeCalls + 1))
        cat >/dev/null
        if [[ "${mode}" == "config-fail" ]]; then
            SUBSCRIBE_NGINX_CONFIG_WRITE_ERROR="订阅 Nginx 配置校验失败，且旧配置恢复失败"
            return 1
        fi
        return 0
    }
    installSubscriptionControlService() {
        controlCalls=$((controlCalls + 1))
        return 0
    }
    bootStartup() {
        bootCalls=$((bootCalls + 1))
        return 0
    }
    handleNginx() {
        printf '%s:%s:%s\n' "${mode}" "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "$1" != "start" ]]
    }
    pgrep() {
        [[ "${mode}" == "existing-port" ]] && return 1
        return 0
    }

    writeCalls=0
    controlCalls=0
    bootCalls=0
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    set +e
    installSubscribe >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${writeCalls}" == "1" ]]
    [[ "${controlCalls}" == "1" ]]
    [[ "${bootCalls}" == "1" ]]
    grep -qx 'reload:stop:true' "${serviceLog}"
    grep -qx 'reload:start:true' "${serviceLog}"
    grep -q '订阅 Nginx 服务重载失败' "${errorLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    mode=existing-port
    : >"${serviceLog}"
    : >"${errorLog}"
    writeCalls=0
    controlCalls=0
    bootCalls=0
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    set +e
    installSubscribe >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${writeCalls}" == "0" ]]
    [[ "${controlCalls}" == "0" ]]
    [[ "${bootCalls}" == "0" ]]
    grep -qx 'existing-port:start:true' "${serviceLog}"
    grep -q '订阅 Nginx 服务启动失败' "${errorLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    mode=config-fail
    : >"${serviceLog}"
    : >"${errorLog}"
    writeCalls=0
    controlCalls=0
    bootCalls=0
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    set +e
    installSubscribe >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${writeCalls}" == "1" ]]
    [[ "${controlCalls}" == "0" ]]
    [[ "${bootCalls}" == "0" ]]
    grep -q '订阅 Nginx 配置校验失败，且旧配置恢复失败' "${errorLog}"
    ! grep -q '订阅 Nginx 配置校验失败，已回滚' "${errorLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    PATH="${oldPath}"
)

runSingBoxPortFailureRegression() (
    local result=()
    local subscribeRoot="${TMP_DIR}/subscribe-port-failure"
    local oldPath="${PATH}"
    local oldNginxConfigPath="${nginxConfigPath:-}"
    local oldStaticPath="${nginxStaticPath:-}"
    local oldSubscribePort="${subscribePort:-}"
    local oldAutoSubscribePort="${AUTO_SUBSCRIBE_PORT:-}"
    local oldCurrentHost="${currentHost:-}"
    local oldTlsDir="${PADM_TLS_DIR:-}"
    local writeCalls=0

    allowPort() { return 0; }

    if readSingBoxPortResult result 70000 false 2>/dev/null; then
        return 1
    fi
    [[ "${#result[@]}" == "0" ]]

    mkdir -p "${subscribeRoot}/fake-bin" "${subscribeRoot}/nginx" "${subscribeRoot}/tls" "${subscribeRoot}/static"
    cat >"${subscribeRoot}/fake-bin/nginx" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-v" ]]; then
    printf 'nginx version: nginx/1.26.0\n' >&2
    exit 0
fi
exit 0
SH
    chmod +x "${subscribeRoot}/fake-bin/nginx"
    PATH="${subscribeRoot}/fake-bin:${PATH}"
    nginxConfigPath="${subscribeRoot}/nginx/"
    nginxStaticPath="${subscribeRoot}/static"
    export PADM_TLS_DIR="${subscribeRoot}/tls"
    currentHost=port.example.com
    printf 'cert\n' >"${PADM_TLS_DIR}/port.example.com.crt"
    printf 'key\n' >"${PADM_TLS_DIR}/port.example.com.key"
    subscribePort=
    AUTO_SUBSCRIBE_PORT=70000
    writeSubscribeNginxConfig() {
        writeCalls=$((writeCalls + 1))
        return 0
    }
    nginxBlog() { return 0; }
    hasIPv6Connectivity() { return 1; }
    installSubscriptionControlService() { return 0; }
    bootStartup() { return 0; }
    handleNginx() { return 0; }
    pgrep() { return 0; }

    if installSubscribe 2>/dev/null; then
        return 1
    fi
    [[ "${writeCalls}" == "0" ]]
    [[ ! -e "${nginxConfigPath}subscribe.conf" ]]

    PATH="${oldPath}"
    nginxConfigPath="${oldNginxConfigPath}"
    nginxStaticPath="${oldStaticPath}"
    subscribePort="${oldSubscribePort}"
    AUTO_SUBSCRIBE_PORT="${oldAutoSubscribePort}"
    currentHost="${oldCurrentHost}"
    if [[ -n "${oldTlsDir}" ]]; then export PADM_TLS_DIR="${oldTlsDir}"; else unset PADM_TLS_DIR; fi
)

runAloneNginxConfigTransactionRegression() {
    local targetPath="${TMP_DIR}/nginx-alone/alone.conf"
    local oldPath="${PATH}"
    mkdir -p "${TMP_DIR}/fake-bin" "${TMP_DIR}/nginx-alone"
    nginxConfigPath="${TMP_DIR}/nginx-alone/"
    cat >"${TMP_DIR}/fake-bin/nginx" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-v" ]]; then
    printf 'nginx version: nginx/1.24.0\n' >&2
    exit 0
fi
[[ "$1" == "-t" ]]
[[ "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}" == "success" ]]
SH
    chmod +x "${TMP_DIR}/fake-bin/nginx"
    PATH="${TMP_DIR}/fake-bin:${PATH}"
    domain=example.com
    port=443
    currentPath=padm
    nginxStaticPath="${TMP_DIR}/static"
    selectCustomInstallType=9
    printf 'old config\n' >"${targetPath}"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    if updateRedirectNginxConf 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${targetPath}")" == "old config" ]]
    [[ ! -e "${targetPath}.tmp" ]]

    printf 'old config\n' >"${targetPath}"
    (
        local errorLog="${TMP_DIR}/nginx-alone-write-backup-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        cp() {
            if [[ "$1" == "${targetPath}" && "$2" == "${targetPath}.bak" ]]; then
                return 1
            fi
            command cp "$@"
        }
        export PADM_FAKE_NGINX_VALIDATE_MODE=success
        if updateRedirectNginxConf >/dev/null 2>&1; then
            return 1
        fi
        [[ "$(<"${targetPath}")" == "old config" ]]
        [[ ! -e "${targetPath}.tmp" ]]
        [[ ! -e "${targetPath}.bak" ]]
        grep -q 'Nginx 配置备份失败' "${errorLog}"
        ! grep -q '已恢复旧 alone.conf' "${errorLog}"
    ) || return 1

    printf 'old config\n' >"${targetPath}"
    (
        local errorLog="${TMP_DIR}/nginx-alone-write-commit-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        mv() {
            if [[ "$1" == "${targetPath}.tmp" && "$2" == "${targetPath}" ]]; then
                return 1
            fi
            command mv "$@"
        }
        export PADM_FAKE_NGINX_VALIDATE_MODE=success
        if updateRedirectNginxConf >/dev/null 2>&1; then
            return 1
        fi
        [[ "$(<"${targetPath}")" == "old config" ]]
        [[ ! -e "${targetPath}.tmp" ]]
        [[ ! -e "${targetPath}.bak" ]]
        grep -q 'Nginx 配置提交失败' "${errorLog}"
        ! grep -q '已恢复旧 alone.conf' "${errorLog}"
    ) || return 1

    printf 'old config\n' >"${targetPath}"
    (
        local errorLog="${TMP_DIR}/nginx-alone-write-restore-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        mv() {
            if [[ "$1" == "${targetPath}.bak" && "$2" == "${targetPath}" ]]; then
                return 1
            fi
            command mv "$@"
        }
        if updateRedirectNginxConf 2>/dev/null; then
            return 1
        fi
        grep -q 'server_name example.com;' "${targetPath}"
        [[ "$(<"${targetPath}.bak")" == "old config" ]]
        grep -q '旧 alone.conf 恢复失败' "${errorLog}"
    ) || return 1
    printf 'old config\n' >"${targetPath}"
    rm -f "${targetPath}.bak"

    (
        local errorLog="${TMP_DIR}/nginx-alone-write-backup-cleanup-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        rm() {
            if [[ "$1" == "-f" && "$2" == "${targetPath}.bak" ]]; then
                return 1
            fi
            command rm "$@"
        }
        export PADM_FAKE_NGINX_VALIDATE_MODE=success
        if updateRedirectNginxConf >/dev/null 2>&1; then
            return 1
        fi
        grep -q 'server_name example.com;' "${targetPath}"
        [[ "$(<"${targetPath}.bak")" == "old config" ]]
        grep -q 'Nginx 配置备份清理失败' "${errorLog}"
        ! grep -q '已恢复旧 alone.conf' "${errorLog}"
    ) || return 1
    printf 'old config\n' >"${targetPath}"
    rm -f "${targetPath}.bak"

    export PADM_FAKE_NGINX_VALIDATE_MODE=success
    updateRedirectNginxConf
    grep -q 'server_name example.com;' "${targetPath}"
    [[ ! -e "${targetPath}.tmp" ]]
    [[ ! -e "${targetPath}.bak" ]]

    rm -f "${targetPath}"
    (
        local errorLog="${TMP_DIR}/nginx-alone-missing-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        if addNginx302 https://missing-alone.example >/dev/null 2>&1; then
            return 1
        fi
        [[ ! -e "${targetPath}" ]]
        grep -q '请先重建 alone.conf' "${errorLog}"
    ) || return 1

    currentInstallProtocolType=",0,5,"
    currentHost=example.com
    currentPort=443
    currentPath=padm
    rm -f "${targetPath}"
    ensureTraditionalTlsFallbackNginxConfig >/dev/null 2>&1
    grep -q 'server_name example.com;' "${targetPath}"
    grep -q 'location /padmgrpc {' "${targetPath}"
    grep -q 'listen 127.0.0.1:31300 proxy_protocol;' "${targetPath}"

    (
        local serviceLog="${TMP_DIR}/nginx-alone-service.log"
        local errorLog="${TMP_DIR}/nginx-alone-error.log"
        local rcFile="${TMP_DIR}/nginx-alone-redirect.rc"
        local shellRc
        : >"${serviceLog}"
        : >"${errorLog}"
        rm -f "${rcFile}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        handleNginx() {
            printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
            [[ "${SERVICE_QUEUE_ALLOW_FAILURE:-}" == "true" ]] && return 1
            exit 0
        }
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        set +e
        (
            set +e
            updateRedirectNginxConf >/dev/null 2>&1
            printf '%s\n' "$?" >"${rcFile}"
        )
        shellRc=$?
        set -e
        [[ "${shellRc}" == "0" ]]
        [[ -s "${rcFile}" ]]
        [[ "$(<"${rcFile}")" == "1" ]]
        grep -qx 'nginx:stop:true' "${serviceLog}"
        grep -q 'Nginx 服务停止失败' "${errorLog}"
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    )

    printf 'keep\nreturn 302 https://example.org;\nreturn 302 $scheme://example.org$request_uri;\n' >"${targetPath}"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    if removeNginx302 2>/dev/null; then
        return 1
    fi
    grep -q 'return 302 https://example.org;' "${targetPath}"

    (
        local errorLog="${TMP_DIR}/nginx-alone-update-restore-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        mv() {
            if [[ "$1" == "${targetPath}.bak" && "$2" == "${targetPath}" ]]; then
                return 1
            fi
            command mv "$@"
        }
        if removeNginx302 2>/dev/null; then
            return 1
        fi
        ! grep -q 'return 302 https://example.org;' "${targetPath}"
        grep -q 'return 302 https://example.org;' "${targetPath}.bak"
        grep -q '旧 alone.conf 恢复失败' "${errorLog}"
    ) || return 1
    printf 'keep\nreturn 302 https://example.org;\nreturn 302 $scheme://example.org$request_uri;\n' >"${targetPath}"
    rm -f "${targetPath}.bak"

    export PADM_FAKE_NGINX_VALIDATE_MODE=success
    removeNginx302
    ! grep -q 'return 302 https://example.org;' "${targetPath}"
    grep -q 'request_uri' "${targetPath}"

    printf 'server {\nlocation / {\n}\n}\n' >"${targetPath}"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    if addNginx302 https://redirect.example 2>/dev/null; then
        return 1
    fi
    ! grep -q 'redirect.example' "${targetPath}"

    export PADM_FAKE_NGINX_VALIDATE_MODE=success
    addNginx302 https://redirect.example
    grep -q "return 302 'https://redirect.example';" "${targetPath}"

    printf 'server {\nlocation / {\n}\n}\n' >"${targetPath}"
    (
        local errorLog="${TMP_DIR}/nginx-alone-update-commit-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        mv() {
            if [[ "$1" == "${targetPath}.tmp" && "$2" == "${targetPath}" ]]; then
                return 1
            fi
            command mv "$@"
        }
        if addNginx302 https://commit-fail.example >/dev/null 2>&1; then
            return 1
        fi
        ! grep -q 'commit-fail.example' "${targetPath}"
        [[ ! -e "${targetPath}.tmp" ]]
        [[ ! -e "${targetPath}.bak" ]]
        grep -q 'Nginx 配置提交失败' "${errorLog}"
        ! grep -q '已恢复旧 alone.conf' "${errorLog}"
    ) || return 1

    printf 'server {\n}\n' >"${targetPath}"
    (
        local errorLog="${TMP_DIR}/nginx-alone-add-editor-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        if addNginx302 https://missing-location.example >/dev/null 2>&1; then
            return 1
        fi
        ! grep -q 'missing-location.example' "${targetPath}"
        [[ ! -e "${targetPath}.tmp" ]]
        [[ ! -e "${targetPath}.tmp.rewrite" ]]
        grep -q 'Nginx 302 配置编辑失败' "${errorLog}"
        ! grep -q '已恢复旧 alone.conf' "${errorLog}"
    ) || return 1

    PADM_ALONE_NGINX_BACKUP_FILE="${TMP_DIR}/alone_backup.conf"
    printf 'backup config\n' >"${PADM_ALONE_NGINX_BACKUP_FILE}"
    printf 'changed config\n' >"${targetPath}"
    currentHost=example.com
    currentPort=443
    curl() { printf '200 OK\n'; }
    if checkNginx302 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${targetPath}")" == "backup config" ]]
    [[ ! -e "${PADM_ALONE_NGINX_BACKUP_FILE}" ]]
    printf 'backup config\n' >"${PADM_ALONE_NGINX_BACKUP_FILE}"
    printf 'changed config\n' >"${targetPath}"
    (
        local errorLog="${TMP_DIR}/nginx-302-restore-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        cp() {
            if [[ "$1" == "${PADM_ALONE_NGINX_BACKUP_FILE}" && "$2" == "${targetPath}" ]]; then
                return 1
            fi
            command cp "$@"
        }
        if checkNginx302 >/dev/null 2>&1; then
            return 1
        fi
        [[ "$(<"${targetPath}")" == "changed config" ]]
        [[ -e "${PADM_ALONE_NGINX_BACKUP_FILE}" ]]
        grep -q '恢复备份失败' "${errorLog}"
    )
    rm -f "${PADM_ALONE_NGINX_BACKUP_FILE}"
    curl() { printf '302 Found\n'; }
    checkNginx302
    unset -f curl
    PATH="${oldPath}"
    unset PADM_FAKE_NGINX_VALIDATE_MODE
}

runSubscribeUserOutputTransactionRegression() {
    local oldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
    local oldPublicDir="${PADM_SUBSCRIBE_DIR:-}"
    local oldScriptDir="${SCRIPT_DIR}"
    local oldTmpDir="${TMPDIR:-}"
    local localDir="${TMP_DIR}/subscribe-user-local"
    local publicDir="${TMP_DIR}/subscribe-user-public"
    local userTmpRoot="${TMP_DIR}/subscribe-user-tmp"
    local stageMarker="${TMP_DIR}/subscribe-user-stage-dirs.txt"
    local email="atomic-user"
    local emailMd5="atomic-md5"
    export PADM_SUBSCRIBE_LOCAL_DIR="${localDir}"
    export PADM_SUBSCRIBE_DIR="${publicDir}"
    TMPDIR="${userTmpRoot}"
    SCRIPT_DIR="${PROJECT_ROOT}"
    subscribeType=https
    subscribeSalt=salt
    mkdir -p "${localDir}/default" "${localDir}/clashMeta" "${localDir}/sing-box" "${publicDir}/default" "${publicDir}/clashMeta" "${publicDir}/clashMetaProfiles" "${publicDir}/sing-box" "${publicDir}/sing-box_profiles" "${userTmpRoot}"
    : >"${stageMarker}"
    eval "$(declare -f clashMetaConfig | sed '1s/^clashMetaConfig/originalClashMetaConfig/')"
    eval "$(declare -f commitSubscribeUserOutputFile | sed '1s/^commitSubscribeUserOutputFile/originalCommitSubscribeUserOutputFile/')"

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
        currentHost=example.com
        subscribePort=
        currentDefaultPort=443
        listRemoteSubscribeSources() {
            return 0
        }
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
        updateRemoteSubscribe() {
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
        updateRemoteSubscribe() {
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
        local commitCalls=0
        commitSubscribeUserOutputFile() {
            commitCalls=$((commitCalls + 1))
            if [[ "${commitCalls}" == "2" ]]; then
                return 1
            fi
            originalCommitSubscribeUserOutputFile "$@"
        }
        if renderSubscribeUserOutputs "${email}" "${emailMd5}" "example.com" n true 2>/dev/null; then
            return 1
        fi
        [[ "${SUBSCRIBE_USER_OUTPUT_ERROR}" == "订阅生成失败，已恢复旧订阅输出" ]]
        [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
        [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
        [[ "$(<"${publicDir}/clashMetaProfiles/${emailMd5}")" == "old-profile" ]]
        [[ "$(<"${publicDir}/sing-box_profiles/${emailMd5}")" == "old-sing-profile" ]]
        [[ "$(<"${publicDir}/sing-box/${emailMd5}")" == "old-sing" ]]
        if find "${userTmpRoot}" -maxdepth 1 -type d -name 'padm-check-log-backup.*' | grep -q .; then
            return 1
        fi
    )

    writeLocalSubscribeOutputs
    renderSubscribeUserOutputs "${email}" "${emailMd5}" "example.com" n true
    grep -q . "${stageMarker}"
    while IFS= read -r path; do
        [[ -z "${path}" || "${path}" == "${userTmpRoot}"/padm-subscribe-user.* ]] || return 1
    done <"${stageMarker}"
    if find "${userTmpRoot}" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
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
    [[ -n "${subscribeSalt}" ]]

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

runSubscribeReturnFailureRegression() (
    local localDir="${TMP_DIR}/subscribe-return-local"
    local oldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
    local installCalls=0
    local renderCalls=0
    local showAccountsCalls=0

    # Re-source manage.sh because the regression bootstrap replaces subscribe with a menu-safe no-op.
    source "${PROJECT_ROOT}/shell/core/manage.sh"
    export PADM_SUBSCRIBE_LOCAL_DIR="${localDir}"
    mkdir -p "${localDir}/default" "${localDir}/clashMeta" "${localDir}/sing-box"
    printf 'existing-salt\n' >"${localDir}/subscribeSalt"

    readInstallProtocolType() { return 0; }
    readNginxSubscribe() { return 0; }
    installSubscribe() {
        installCalls=$((installCalls + 1))
        return 1
    }
    showAccounts() {
        showAccountsCalls=$((showAccountsCalls + 1))
        return 0
    }
    renderAllSubscribeUserOutputs() {
        renderCalls=$((renderCalls + 1))
        return 0
    }

    coreInstallType=1
    if subscribe false true 2>/dev/null; then
        return 1
    fi
    [[ "${installCalls}" == "1" ]]
    [[ "${showAccountsCalls}" == "0" ]]
    [[ "${renderCalls}" == "0" ]]

    installSubscribe() {
        installCalls=$((installCalls + 1))
        return 0
    }
    renderAllSubscribeUserOutputs() {
        renderCalls=$((renderCalls + 1))
        return 1
    }
    if subscribe false true 2>/dev/null; then
        return 1
    fi
    [[ "${renderCalls}" == "1" ]]

    coreInstallType=
    renderAllSubscribeUserOutputs() {
        renderCalls=$((renderCalls + 1))
        return 0
    }
    if subscribe false true 2>/dev/null; then
        return 1
    fi
    [[ "${renderCalls}" == "1" ]]

    if [[ -n "${oldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${oldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
)

runSubscribeLocalRollbackRegression() (
    local root="${TMP_DIR}/subscribe-local-rollback"
    local localDir="${root}/subscribe_local"
    local errorLog="${root}/error.log"
    local callLog="${root}/calls.log"
    local beforeSnapshot="${root}/before.txt"
    local oldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
    local oldTmpDir="${TMPDIR:-}"
    local oldSubscribeSalt="${subscribeSalt:-}"
    local renderCalls=0
    local showAccountsCalls=0
    local rc

    captureSubscribeLocalSnapshot() {
        find "${localDir}" -type f -printf '%P\t' -exec cat {} \; | sort
    }

    source "${PROJECT_ROOT}/shell/core/manage.sh"
    export PADM_SUBSCRIBE_LOCAL_DIR="${localDir}"
    TMPDIR="${root}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    mkdir -p "${localDir}/default" "${localDir}/clashMeta" "${localDir}/sing-box"
    printf 'existing-salt\n' >"${localDir}/subscribeSalt"
    printf 'old default\n' >"${localDir}/default/existing"
    printf 'old clash\n' >"${localDir}/clashMeta/existing"
    printf '[{"tag":"old-local"}]\n' >"${localDir}/sing-box/existing"
    subscribeSalt=existing-salt
    captureSubscribeLocalSnapshot >"${beforeSnapshot}"

    readInstallProtocolType() { return 0; }
    readNginxSubscribe() { return 0; }
    installSubscribe() { return 0; }
    renderAllSubscribeUserOutputs() {
        renderCalls=$((renderCalls + 1))
        printf 'render\n' >>"${callLog}"
        return 0
    }

    : >"${errorLog}"
    : >"${callLog}"
    resolveSubscribeSalt() {
        writeSubscribeSalt "$1" "new-salt"
        subscribeSalt="new-salt"
        return 1
    }
    coreInstallType=1
    set +e
    subscribe false true >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${renderCalls}" == "0" ]]
    [[ "${subscribeSalt}" == "existing-salt" ]]
    [[ "$(<"${localDir}/subscribeSalt")" == "existing-salt" ]]
    diff -u "${beforeSnapshot}" <(captureSubscribeLocalSnapshot)
    grep -q '订阅 Salt 初始化失败，已恢复旧本地订阅' "${errorLog}"
    ! find "${root}" -maxdepth 1 -type d -name 'padm-subscribe-local-backup.*' | grep -q .

    : >"${errorLog}"
    : >"${callLog}"
    renderCalls=0
    showAccountsCalls=0
    resolveSubscribeSalt() {
        writeSubscribeSalt "$1" "new-salt"
        subscribeSalt="new-salt"
        return 0
    }
    showAccounts() {
        showAccountsCalls=$((showAccountsCalls + 1))
        printf 'showAccounts\n' >>"${callLog}"
        printf 'new default\n' >"${localDir}/default/existing"
        printf 'new clash\n' >"${localDir}/clashMeta/existing"
        printf '[{"tag":"new-local"}]\n' >"${localDir}/sing-box/existing"
        return 1
    }
    set +e
    subscribe false true >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${showAccountsCalls}" == "1" ]]
    [[ "${renderCalls}" == "0" ]]
    [[ "${subscribeSalt}" == "existing-salt" ]]
    [[ "$(<"${localDir}/subscribeSalt")" == "existing-salt" ]]
    diff -u "${beforeSnapshot}" <(captureSubscribeLocalSnapshot)
    grep -q '订阅生成失败：重建本地订阅失败，已恢复旧本地订阅' "${errorLog}"
    grep -qx 'showAccounts' "${callLog}"
    ! find "${root}" -maxdepth 1 -type d -name 'padm-subscribe-local-backup.*' | grep -q .

    : >"${errorLog}"
    : >"${callLog}"
    renderCalls=0
    showAccountsCalls=0
    resolveSubscribeSalt() {
        writeSubscribeSalt "$1" "new-salt"
        subscribeSalt="new-salt"
        return 0
    }
    showAccounts() {
        showAccountsCalls=$((showAccountsCalls + 1))
        printf 'showAccounts\n' >>"${callLog}"
        printf 'new default\n' >"${localDir}/default/existing"
        printf 'new clash\n' >"${localDir}/clashMeta/existing"
        printf '[{"tag":"new-local"}]\n' >"${localDir}/sing-box/existing"
        return 0
    }
    renderAllSubscribeUserOutputs() {
        renderCalls=$((renderCalls + 1))
        printf 'render\n' >>"${callLog}"
        return 1
    }
    set +e
    subscribe false true >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${showAccountsCalls}" == "1" ]]
    [[ "${renderCalls}" == "1" ]]
    [[ "${subscribeSalt}" == "existing-salt" ]]
    [[ "$(<"${localDir}/subscribeSalt")" == "existing-salt" ]]
    diff -u "${beforeSnapshot}" <(captureSubscribeLocalSnapshot)
    grep -q '订阅生成失败：生成订阅输出失败，已恢复旧本地订阅' "${errorLog}"
    grep -qx 'showAccounts' "${callLog}"
    grep -qx 'render' "${callLog}"
    ! find "${root}" -maxdepth 1 -type d -name 'padm-subscribe-local-backup.*' | grep -q .

    if [[ -n "${oldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${oldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
    if [[ -n "${oldTmpDir}" ]]; then TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    if [[ -n "${oldSubscribeSalt}" ]]; then subscribeSalt="${oldSubscribeSalt}"; else unset subscribeSalt; fi
)

runSubscriptionGroupsMigrationBackupRegression() (
    local root="${TMP_DIR}/subscription-groups-migration-backup"
    local groupsDir="${root}/subscribe_groups"
    local backupsDir="${groupsDir}/backups"
    local stateFile="${groupsDir}/groups.json"
    local errorLog="${root}/error.log"
    local oldGroupsDir="${PADM_SUBSCRIPTION_GROUPS_DIR:-}"
    local oldTmpDir="${TMPDIR:-}"
    local rc

    source "${PROJECT_ROOT}/shell/subscription/groups.sh"
    export PADM_SUBSCRIPTION_GROUPS_DIR="${groupsDir}"
    TMPDIR="${root}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    mkdir -p "${groupsDir}"
    cat >"${stateFile}" <<'JSON'
{"version":1,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"本机","role":"main","scheme":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON

    cp() {
        return 1
    }

    set +e
    migrateSubscriptionGroupsState >/dev/null 2>&1
    rc=$?
    set -e
    unset -f cp
    [[ "${rc}" == "1" ]]
    [[ -f "${stateFile}" ]]
    [[ "$(jq -r '.version' "${stateFile}")" == "1" ]]
    if find "${backupsDir}" -maxdepth 1 -type f -name 'groups-pre-migrate-*.json' | grep -q .; then
        return 1
    fi

    if [[ -n "${oldGroupsDir}" ]]; then export PADM_SUBSCRIPTION_GROUPS_DIR="${oldGroupsDir}"; else unset PADM_SUBSCRIPTION_GROUPS_DIR; fi
    if [[ -n "${oldTmpDir}" ]]; then TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runSubscriptionGroupsRestoreFailureRegression() (
    local root="${TMP_DIR}/subscription-groups-restore-failure"
    local groupsDir="${root}/groups"
    local currentBackup="${root}/current-backup.json"
    local targetBackup="${root}/target-backup.json"
    local stateFile="${groupsDir}/groups.json"
    local oldGroupsDir="${PADM_SUBSCRIPTION_GROUPS_DIR:-}"
    local oldTmpDir="${TMPDIR:-}"
    local beforeSnapshot
    local rc

    source "${PROJECT_ROOT}/shell/subscription/groups.sh"
    export PADM_SUBSCRIPTION_GROUPS_DIR="${groupsDir}"
    TMPDIR="${root}"
    mkdir -p "${groupsDir}"
    cat >"${stateFile}" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"默认订阅组","admin":{"id":"admin","name":"我的订阅","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"本机","role":"main","transport":"local","scheme":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    beforeSnapshot=$(<"${stateFile}")
    cp "${stateFile}" "${currentBackup}"
    cat >"${targetBackup}" <<'JSON'
{"version":1,"active_group":"legacy","groups":[{"id":"legacy","name":"Legacy","sources":[],"user_groups":[],"sync":{"enabled":true},"traffic":{}}]}
JSON

    createSubscriptionGroupsBackup() {
        printf '%s\n' "${currentBackup}"
    }
    migrateSubscriptionGroupsState() {
        return 1
    }

    set +e
    restoreSubscriptionGroupsBackup "${targetBackup}" >/dev/null 2>&1
    rc=$?
    set -e
    unset -f createSubscriptionGroupsBackup
    unset -f migrateSubscriptionGroupsState
    [[ "${rc}" == "1" ]]
    [[ "$(<"${stateFile}")" == "${beforeSnapshot}" ]]
    [[ ! -e "${currentBackup}" ]]

    if [[ -n "${oldGroupsDir}" ]]; then export PADM_SUBSCRIPTION_GROUPS_DIR="${oldGroupsDir}"; else unset PADM_SUBSCRIPTION_GROUPS_DIR; fi
    if [[ -n "${oldTmpDir}" ]]; then TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runSubscriptionGroupsBackupFailureRegression() (
    local root="${TMP_DIR}/subscription-groups-backup-failure"
    local groupsDir="${root}/subscribe_groups"
    local backupsDir="${groupsDir}/backups"
    local stateFile="${groupsDir}/groups.json"
    local oldGroupsDir="${PADM_SUBSCRIPTION_GROUPS_DIR:-}"
    local oldTmpDir="${TMPDIR:-}"
    local beforeSnapshot
    local backupFile
    local rc

    source "${PROJECT_ROOT}/shell/subscription/groups.sh"
    export PADM_SUBSCRIPTION_GROUPS_DIR="${groupsDir}"
    TMPDIR="${root}"
    mkdir -p "${groupsDir}"
    cat >"${stateFile}" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"默认订阅组","admin":{"id":"admin","name":"我的订阅","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"本机","role":"main","transport":"local","scheme":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    beforeSnapshot=$(<"${stateFile}")

    cp() {
        return 1
    }

    set +e
    backupFile=$(createSubscriptionGroupsBackup)
    rc=$?
    set -e
    unset -f cp
    [[ "${rc}" == "1" ]]
    [[ -z "${backupFile}" ]]
    [[ "$(<"${stateFile}")" == "${beforeSnapshot}" ]]
    if find "${backupsDir}" -maxdepth 1 -type f -name 'groups-*.json' | grep -q .; then
        return 1
    fi

    if [[ -n "${oldGroupsDir}" ]]; then export PADM_SUBSCRIPTION_GROUPS_DIR="${oldGroupsDir}"; else unset PADM_SUBSCRIPTION_GROUPS_DIR; fi
    if [[ -n "${oldTmpDir}" ]]; then TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runRefreshLocalSubscriptionsRollbackRegression() (
    local root="${TMP_DIR}/refresh-local-subscriptions-rollback"
    local localDir="${root}/subscribe_local"
    local errorLog="${root}/error.log"
    local callLog="${root}/calls.log"
    local beforeSnapshot="${root}/before.txt"
    local oldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
    local oldTmpDir="${TMPDIR:-}"
    local cleanCalls=0
    local rc

    captureRefreshLocalSnapshot() {
        find "${localDir}" -type f -printf '%P\t' -exec cat {} \; | sort
    }

    mkdir -p "${localDir}/default" "${localDir}/clashMeta" "${localDir}/sing-box"
    export PADM_SUBSCRIBE_LOCAL_DIR="${localDir}"
    TMPDIR="${root}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    printf 'old salt\n' >"${localDir}/subscribeSalt"
    printf 'old default\n' >"${localDir}/default/existing"
    printf 'old clash\n' >"${localDir}/clashMeta/existing"
    printf '["old"]\n' >"${localDir}/sing-box/existing"
    captureRefreshLocalSnapshot >"${beforeSnapshot}"

    : >"${errorLog}"
    : >"${callLog}"
    showAccounts() {
        printf 'showAccounts\n' >>"${callLog}"
        printf 'new default\n' >"${localDir}/default/existing"
        printf 'new clash\n' >"${localDir}/clashMeta/existing"
        printf '["new"]\n' >"${localDir}/sing-box/existing"
        printf 'new default user\n' >"${localDir}/default/new-user"
        return 1
    }
    set +e
    refreshLocalSubscriptions "Tuic" "已刷新本地订阅" >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    diff -u "${beforeSnapshot}" <(captureRefreshLocalSnapshot)
    grep -q '重建本地订阅失败，已恢复旧本地订阅' "${errorLog}"
    grep -qx 'showAccounts' "${callLog}"
    ! find "${root}" -maxdepth 1 -type d -name 'padm-refresh-local-subscriptions.*' | grep -q .

    : >"${errorLog}"
    : >"${callLog}"
    cleanCalls=0
    cleanDirectoryContent() {
        cleanCalls=$((cleanCalls + 1))
        printf 'clean:%s\n' "$1" >>"${callLog}"
        mkdir -p "$1" || return 1
        find "$1" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || return 1
        [[ "${cleanCalls}" -lt 2 ]]
    }
    set +e
    refreshLocalSubscriptions "XHTTP" "已刷新本地订阅" >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${cleanCalls}" == "2" ]]
    diff -u "${beforeSnapshot}" <(captureRefreshLocalSnapshot)
    grep -q '清理本地订阅目录失败，已恢复旧本地订阅' "${errorLog}"
    ! find "${root}" -maxdepth 1 -type d -name 'padm-refresh-local-subscriptions.*' | grep -q .

    if [[ -n "${oldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${oldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
    if [[ -n "${oldTmpDir}" ]]; then TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runRemoveUserSubscriptionMenuFailureRegression() (
    local root="${TMP_DIR}/remove-user-subscription-menu-failure"
    local callLog="${root}/calls.log"
    local successLog="${root}/success.log"
    local errorLog="${root}/error.log"
    local backupDir="${root}/backup"
    local mode rc

    mkdir -p "${root}"
    : >"${callLog}"
    : >"${successLog}"
    : >"${errorLog}"

    autoRead() {
        printf -v "$3" 'yes'
    }
    subscriptionGroupsFile() {
        printf '%s\n' "${root}/groups.json"
    }
    subscriptionGroupsStateRead() {
        printf '{"version":2,"active_group":"default","groups":[{"id":"default","user_groups":[{"id":"team-a","enabled":true}]}]}\n'
    }
    subscriptionSyncCreateConfigBackups() {
        printf 'backup-create\n' >>"${callLog}"
        mkdir -p "${backupDir}"
        printf '%s\n' "${backupDir}"
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
        [[ "${mode}" != "account-fail" && "${mode}" != "state-restore-fail" && "${mode}" != "account-restore-fail" ]]
    }
    subscriptionGroupsStateWrite() {
        printf 'state-restore\n' >>"${callLog}"
        [[ "${mode}" != "state-restore-fail" ]]
    }
    subscriptionSyncRestoreConfigBackups() {
        printf 'account-restore:%s\n' "$1" >>"${callLog}"
        [[ "${mode}" != "account-restore-fail" ]]
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
    successCard() {
        printf '%s\n' "$*" >>"${successLog}"
    }
    errorCard() {
        printf '%s\n' "$*" >>"${errorLog}"
    }
    statusCard() { return 0; }

    runRemoveCase() {
        mode=$1
        : >"${callLog}"
        : >"${successLog}"
        : >"${errorLog}"
        set +e
        removeUserSubscriptionMenu team-a >/dev/null 2>&1
        rc=$?
        set -e
    }

    runRemoveCase state-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'backup-create' "${callLog}"
    grep -qx 'state:team-a' "${callLog}"
    ! grep -q '^account:' "${callLog}"
    ! grep -qx 'reload' "${callLog}"
    grep -qx "cleanup:${backupDir}" "${callLog}"
    [[ ! -s "${successLog}" ]]

    runRemoveCase account-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'backup-create' "${callLog}"
    grep -qx 'state:team-a' "${callLog}"
    grep -qx 'account:sub_team-a' "${callLog}"
    ! grep -qx 'reload' "${callLog}"
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
    grep -qx 'state-restore' "${callLog}"
    grep -qx "account-restore:${backupDir}" "${callLog}"
    grep -qx "cleanup:${backupDir}" "${callLog}"
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
    grep -q '托管账号配置恢复失败' "${errorLog}"
    [[ ! -s "${successLog}" ]]

    runRemoveCase success
    [[ "${rc}" == "0" ]]
    grep -qx "cleanup:${backupDir}" "${callLog}"
    grep -qx 'reload' "${callLog}"
    grep -q '用户订阅已删除' "${successLog}"
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
        user_subscription_sources) printf -v "${targetVar}" 'main,remote-a' ;;
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
        printf 'subscribe:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" != "subscribe-fail" ]]
    }
    listSubscriptionSources() {
        printf 'main:本机:main:https:127.0.0.1:443:true:ok\n'
        printf 'remote-a:远端:remote:https:10.0.0.2:39778:true:ok\n'
    }
    setUserSubscriptionSources() {
        printf 'sources:%s:%s\n' "$1" "$2" >>"${callLog}"
        [[ "${mode}" != "sources-fail" ]]
    }
    setUserSubscriptionTrafficLimit() {
        printf 'limit:%s:%s\n' "$1" "$2" >>"${callLog}"
        [[ "${mode}" != "limit-fail" ]]
    }
    selectUserSubscriptionId() {
        printf 'team-a\n'
    }
    showUserSubscriptions() { return 0; }
    showUserSubscriptionTraffic() { return 0; }
    showSubscriptionLocalSyncPlan() { return 0; }
    removeUserSubscriptionMenu() { return 0; }
    toggleUserSubscriptionState() {
        printf 'toggle:%s\n' "$1" >>"${callLog}"
        [[ "${mode}" != "toggle-fail" ]]
    }
    echoContent() { return 0; }
    menuLine() { return 0; }
    menuItem() { return 0; }
    menuDangerItem() { return 0; }
    menuReturnItem() { return 0; }
    menuClose() { return 0; }
    userResultCard() { return 0; }
    successCard() {
        printf '%s\n' "$*" >>"${successLog}"
    }
    statusCard() {
        printf '%s\n' "$*" >>"${statusLog}"
    }
    errorCard() {
        printf '%s\n' "$*" >>"${errorLog}"
    }

    mode=subscribe-fail
    resetLogs
    set +e
    showUserSubscriptionLinks team-a >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'subscribe:false' "${callLog}"
    grep -q '订阅输出刷新失败' "${errorLog}"
    [[ ! -s "${statusLog}" ]]

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

    mode=success
    resetLogs
    showUserSubscriptionLinks team-a >/dev/null 2>&1
    grep -q '用户订阅链接' "${statusLog}"
    resetLogs
    setUserSubscriptionSourcesMenu team-a >/dev/null 2>&1
    grep -q '节点范围已更新' "${successLog}"
    resetLogs
    setUserSubscriptionTrafficLimitMenu team-a >/dev/null 2>&1
    grep -q '订阅额度已更新' "${successLog}"
    resetLogs
    manageUserSubscriptionItem >/dev/null 2>&1
    grep -q '用户订阅状态已切换' "${successLog}"
)

runRealityStreamDisableRegression() {
    local oldPath="${PATH}"
    local oldTmpDir="${TMPDIR:-}"
    local fakeBin="${TMP_DIR}/fake-reality-stream-bin"
    local streamDir="${TMP_DIR}/reality-stream"
    local streamTmpRoot="${TMP_DIR}/reality-stream-disable-tmp"
    local visionFile="${streamDir}/07_VLESS_vision_reality_inbounds.json"
    local xhttpFile="${streamDir}/12_VLESS_XHTTP_inbounds.json"
    local stateFile="${streamDir}/reality_stream_split.json"
    local streamConf="${streamDir}/padm-reality.conf"
    local nginxMainConf="${streamDir}/nginx.conf"
    local serviceMode=success
    local serviceLog="${TMP_DIR}/reality-stream-disable-services.log"
    local originalVision originalXHTTP originalState originalStreamConf originalNginxConf
    mkdir -p "${fakeBin}" "${streamDir}" "${streamTmpRoot}"
    TMPDIR="${streamTmpRoot}"
    cat >"${fakeBin}/nginx" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "-t" ]]
[[ "${PADM_FAKE_REALITY_STREAM_NGINX_VALIDATE_MODE:-success}" == "success" ]]
SH
    cat >"${fakeBin}/fake-xray" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "-test" ]]
[[ "${PADM_FAKE_REALITY_STREAM_XRAY_VALIDATE_MODE:-success}" == "success" ]]
SH
    chmod +x "${fakeBin}/nginx" "${fakeBin}/fake-xray"
    PATH="${fakeBin}:${PATH}"
    export PADM_REALITY_STREAM_STATE_FILE="${stateFile}"
    export PADM_REALITY_STREAM_CONF_FILE="${streamConf}"
    export PADM_REALITY_STREAM_NGINX_CONF="${nginxMainConf}"
    export PADM_REALITY_STREAM_XRAY_BINARY="${fakeBin}/fake-xray"
    export PADM_REALITY_STREAM_XRAY_CONF_DIR="${streamDir}"
    export PADM_REALITY_STREAM_VISION_CONFIG_FILE="${visionFile}"
    export PADM_REALITY_STREAM_XHTTP_CONFIG_FILE="${xhttpFile}"
    : >"${serviceLog}"

    reloadCore() {
        printf 'reload:%s\n' "${serviceMode}" >>"${serviceLog}"
        [[ "${serviceMode}" == "reload-fail" ]] && return 1
        return 0
    }

    serviceQueueRestart() {
        printf 'restart:%s:%s\n' "$*" "${serviceMode}" >>"${serviceLog}"
        return 0
    }

    serviceQueueApply() {
        printf 'apply:%s\n' "${serviceMode}" >>"${serviceLog}"
        [[ "${serviceMode}" == "service-fail" ]] && return 1
        return 0
    }

    realityStreamRefreshSubscribeIfInstalled() {
        printf 'refresh\n' >>"${serviceLog}"
        return 0
    }

    writeRealityStreamFixture() {
        cat >"${visionFile}" <<'JSON'
{"inbounds":[{"listen":"127.0.0.1","port":2443,"settings":{"clients":[]}}]}
JSON
        cat >"${xhttpFile}" <<'JSON'
{"inbounds":[{"listen":"127.0.0.1","port":2444,"settings":{"clients":[]}}]}
JSON
        cat >"${stateFile}" <<'JSON'
{"enabled":true,"protocols":{"vision":{"restore_port":443,"internal_port":2443},"xhttp":{"restore_port":443,"internal_port":2444}}}
JSON
        printf 'stream conf\n' >"${streamConf}"
        cat >"${nginxMainConf}" <<'EOF'
events {}
# padm stream include start
include /etc/nginx/stream.d/*.conf;
# padm stream include end
http {}
EOF
        originalVision=$(<"${visionFile}")
        originalXHTTP=$(<"${xhttpFile}")
        originalState=$(<"${stateFile}")
        originalStreamConf=$(<"${streamConf}")
        originalNginxConf=$(<"${nginxMainConf}")
    }

    writeRealityStreamFixture
    export PADM_FAKE_REALITY_STREAM_NGINX_VALIDATE_MODE=fail
    if disableRealityStreamSplit 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${visionFile}")" == "${originalVision}" ]]
    [[ "$(<"${xhttpFile}")" == "${originalXHTTP}" ]]
    [[ "$(<"${stateFile}")" == "${originalState}" ]]
    [[ "$(<"${streamConf}")" == "${originalStreamConf}" ]]
    [[ "$(<"${nginxMainConf}")" == "${originalNginxConf}" ]]

    writeRealityStreamFixture
    export PADM_FAKE_REALITY_STREAM_NGINX_VALIDATE_MODE=success
    export PADM_FAKE_REALITY_STREAM_XRAY_VALIDATE_MODE=fail
    if disableRealityStreamSplit 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${visionFile}")" == "${originalVision}" ]]
    [[ "$(<"${xhttpFile}")" == "${originalXHTTP}" ]]
    [[ -f "${stateFile}" && -f "${streamConf}" ]]

    writeRealityStreamFixture
    export PADM_FAKE_REALITY_STREAM_XRAY_VALIDATE_MODE=success
    serviceMode=reload-fail
    : >"${serviceLog}"
    set +e
    disableRealityStreamSplit >/dev/null 2>&1
    local disableStatus=$?
    set -e
    if [[ "${disableStatus}" -eq 0 ]]; then
        return 1
    fi
    [[ "$(<"${visionFile}")" == "${originalVision}" ]]
    [[ "$(<"${xhttpFile}")" == "${originalXHTTP}" ]]
    [[ "$(<"${stateFile}")" == "${originalState}" ]]
    [[ "$(<"${streamConf}")" == "${originalStreamConf}" ]]
    [[ "$(<"${nginxMainConf}")" == "${originalNginxConf}" ]]
    ! grep -q '^refresh$' "${serviceLog}"
    if find "${streamTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-reality-stream-disable.*' | grep -q .; then
        return 1
    fi

    writeRealityStreamFixture
    serviceMode=service-fail
    : >"${serviceLog}"
    set +e
    disableRealityStreamSplit >/dev/null 2>&1
    disableStatus=$?
    set -e
    if [[ "${disableStatus}" -eq 0 ]]; then
        return 1
    fi
    [[ "$(<"${visionFile}")" == "${originalVision}" ]]
    [[ "$(<"${xhttpFile}")" == "${originalXHTTP}" ]]
    [[ "$(<"${stateFile}")" == "${originalState}" ]]
    [[ "$(<"${streamConf}")" == "${originalStreamConf}" ]]
    [[ "$(<"${nginxMainConf}")" == "${originalNginxConf}" ]]
    grep -q '^restart:nginx:service-fail$' "${serviceLog}"
    ! grep -q '^refresh$' "${serviceLog}"
    if find "${streamTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-reality-stream-disable.*' | grep -q .; then
        return 1
    fi

    writeRealityStreamFixture
    serviceMode=success
    : >"${serviceLog}"
    export PADM_FAKE_REALITY_STREAM_XRAY_VALIDATE_MODE=success
    disableRealityStreamSplit
    jq -e '(.inbounds[0].listen | not) and .inbounds[0].port == 443' "${visionFile}" >/dev/null
    jq -e '.inbounds[0].listen == "0.0.0.0" and .inbounds[0].port == 443' "${xhttpFile}" >/dev/null
    [[ ! -e "${stateFile}" ]]
    [[ ! -e "${streamConf}" ]]
    ! grep -q 'padm stream include start' "${nginxMainConf}"
    if find "${streamTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-reality-stream-disable.*' | grep -q .; then
        return 1
    fi

    PATH="${oldPath}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    unset PADM_REALITY_STREAM_STATE_FILE PADM_REALITY_STREAM_CONF_FILE PADM_REALITY_STREAM_NGINX_CONF PADM_REALITY_STREAM_XRAY_BINARY PADM_REALITY_STREAM_XRAY_CONF_DIR PADM_REALITY_STREAM_VISION_CONFIG_FILE PADM_REALITY_STREAM_XHTTP_CONFIG_FILE PADM_FAKE_REALITY_STREAM_NGINX_VALIDATE_MODE PADM_FAKE_REALITY_STREAM_XRAY_VALIDATE_MODE
}

runRealityStreamEnableRegression() {
    local oldPath="${PATH}"
    local oldAutoInstall="${AUTO_INSTALL:-}"
    local oldTmpDir="${TMPDIR:-}"
    local fakeBin="${TMP_DIR}/fake-reality-stream-enable-bin"
    local streamDir="${TMP_DIR}/reality-stream-enable"
    local streamTmpRoot="${TMP_DIR}/reality-stream-enable-tmp"
    local visionFile="${streamDir}/07_VLESS_vision_reality_inbounds.json"
    local xhttpFile="${streamDir}/12_VLESS_XHTTP_inbounds.json"
    local stateFile="${streamDir}/reality_stream_split.json"
    local streamConf="${streamDir}/padm-reality.conf"
    local nginxMainConf="${streamDir}/nginx.conf"
    local serviceMode=success
    local serviceLog="${TMP_DIR}/reality-stream-enable-services.log"
    local errorLog="${TMP_DIR}/reality-stream-enable-errors.log"
    local keptBackup
    local originalVision originalXHTTP originalNginxConf
    mkdir -p "${fakeBin}" "${streamDir}" "${streamTmpRoot}"
    TMPDIR="${streamTmpRoot}"
    cat >"${fakeBin}/nginx" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-V" ]]; then
    printf 'nginx version: fake --with-stream\n'
    exit 0
fi
[[ "$1" == "-t" ]]
[[ "${PADM_FAKE_REALITY_STREAM_NGINX_VALIDATE_MODE:-success}" == "success" ]]
SH
    cat >"${fakeBin}/fake-xray" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "-test" ]]
[[ "${PADM_FAKE_REALITY_STREAM_XRAY_VALIDATE_MODE:-success}" == "success" ]]
SH
    cat >"${fakeBin}/cp" <<'SH'
#!/usr/bin/env bash
target="${@: -1}"
if [[ "${PADM_FAKE_REALITY_STREAM_CP_MODE:-success}" == "restore-vision-fail" && "${target}" == "${PADM_FAKE_REALITY_STREAM_VISION_FILE:-}" ]]; then
    exit 1
fi
PATH="${PADM_FAKE_REALITY_STREAM_OLD_PATH:-/usr/bin:/bin}" exec cp "$@"
SH
    chmod +x "${fakeBin}/nginx" "${fakeBin}/fake-xray" "${fakeBin}/cp"
    PATH="${fakeBin}:${PATH}"
    export PADM_REALITY_STREAM_STATE_FILE="${stateFile}"
    export PADM_REALITY_STREAM_CONF_FILE="${streamConf}"
    export PADM_REALITY_STREAM_NGINX_CONF="${nginxMainConf}"
    export PADM_REALITY_STREAM_XRAY_BINARY="${fakeBin}/fake-xray"
    export PADM_REALITY_STREAM_XRAY_CONF_DIR="${streamDir}"
    export PADM_REALITY_STREAM_VISION_CONFIG_FILE="${visionFile}"
    export PADM_REALITY_STREAM_XHTTP_CONFIG_FILE="${xhttpFile}"
    export PADM_FAKE_REALITY_STREAM_OLD_PATH="${oldPath}"
    export PADM_FAKE_REALITY_STREAM_VISION_FILE="${visionFile}"
    export PADM_FAKE_REALITY_STREAM_CP_MODE=success
    AUTO_INSTALL=true
    coreInstallType=1
    currentInstallProtocolType=",7,12"
    AUTO_REALITY_STREAM_ENABLE=y
    AUTO_REALITY_STREAM_DOMAINS="site.example.com"
    AUTO_REALITY_STREAM_DEFAULT_PROTOCOL=1
    AUTO_REALITY_STREAM_WEBSITE_PORT=8443
    AUTO_REALITY_STREAM_VISION_PORT=2443
    : >"${serviceLog}"
    : >"${errorLog}"

    reloadCore() {
        printf 'reload:%s\n' "${serviceMode}" >>"${serviceLog}"
        [[ "${serviceMode}" == "reload-fail" ]] && return 1
        return 0
    }

    serviceQueueRestart() {
        printf 'restart:%s:%s\n' "$*" "${serviceMode}" >>"${serviceLog}"
        return 0
    }

    serviceQueueApply() {
        printf 'apply:%s\n' "${serviceMode}" >>"${serviceLog}"
        [[ "${serviceMode}" == "service-fail" ]] && return 1
        return 0
    }

    realityStreamRefreshSubscribeIfInstalled() {
        printf 'refresh\n' >>"${serviceLog}"
        return 0
    }

    errorCard() {
        printf '%s\n' "$*" >>"${errorLog}"
    }

    realityStreamWarnPublic443Status() {
        return 0
    }

    realityStreamWarnWebsiteDomainResolve() {
        return 0
    }

    realityStreamWarnWebsiteBackend() {
        return 0
    }

    writeRealityStreamEnableFixture() {
        cat >"${visionFile}" <<'JSON'
{"inbounds":[{"port":443,"settings":{"clients":[]}}]}
JSON
        cat >"${xhttpFile}" <<'JSON'
{"inbounds":[{"listen":"0.0.0.0","port":8443,"settings":{"clients":[]}}]}
JSON
        cat >"${nginxMainConf}" <<'EOF'
events {}
http {}
EOF
        rm -f "${stateFile}" "${streamConf}"
        originalVision=$(<"${visionFile}")
        originalXHTTP=$(<"${xhttpFile}")
        originalNginxConf=$(<"${nginxMainConf}")
    }

    writeRealityStreamEnableFixture
    export PADM_FAKE_REALITY_STREAM_NGINX_VALIDATE_MODE=fail
    set +e
    configureRealityStreamSplit
    local enableStatus=$?
    set -e
    if [[ "${enableStatus}" -eq 0 ]]; then
        return 1
    fi
    [[ "$(<"${visionFile}")" == "${originalVision}" ]]
    [[ "$(<"${xhttpFile}")" == "${originalXHTTP}" ]]
    [[ "$(<"${nginxMainConf}")" == "${originalNginxConf}" ]]
    [[ ! -e "${stateFile}" ]]
    [[ ! -e "${streamConf}" ]]
    [[ ! -e "${streamConf}.tmp" ]]

    writeRealityStreamEnableFixture
    export PADM_FAKE_REALITY_STREAM_NGINX_VALIDATE_MODE=success
    export PADM_FAKE_REALITY_STREAM_XRAY_VALIDATE_MODE=fail
    set +e
    configureRealityStreamSplit
    local enableStatus=$?
    set -e
    if [[ "${enableStatus}" -eq 0 ]]; then
        return 1
    fi
    [[ "$(<"${visionFile}")" == "${originalVision}" ]]
    [[ "$(<"${xhttpFile}")" == "${originalXHTTP}" ]]
    [[ ! -e "${stateFile}" ]]
    [[ ! -e "${streamConf}" ]]

    writeRealityStreamEnableFixture
    export PADM_FAKE_REALITY_STREAM_XRAY_VALIDATE_MODE=success
    serviceMode=reload-fail
    export PADM_FAKE_REALITY_STREAM_CP_MODE=success
    : >"${serviceLog}"
    : >"${errorLog}"
    set +e
    configureRealityStreamSplit >/dev/null 2>&1
    enableStatus=$?
    set -e
    if [[ "${enableStatus}" -eq 0 ]]; then
        return 1
    fi
    [[ "$(<"${visionFile}")" == "${originalVision}" ]]
    [[ "$(<"${xhttpFile}")" == "${originalXHTTP}" ]]
    [[ "$(<"${nginxMainConf}")" == "${originalNginxConf}" ]]
    [[ ! -e "${stateFile}" ]]
    [[ ! -e "${streamConf}" ]]
    ! grep -q '^refresh$' "${serviceLog}"
    grep -q 'Reality 443 共存分流服务应用失败' "${errorLog}"
    if find "${streamTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-reality-stream.*' | grep -q .; then
        return 1
    fi

    writeRealityStreamEnableFixture
    serviceMode=service-fail
    export PADM_FAKE_REALITY_STREAM_CP_MODE=success
    : >"${serviceLog}"
    : >"${errorLog}"
    set +e
    configureRealityStreamSplit >/dev/null 2>&1
    enableStatus=$?
    set -e
    if [[ "${enableStatus}" -eq 0 ]]; then
        return 1
    fi
    [[ "$(<"${visionFile}")" == "${originalVision}" ]]
    [[ "$(<"${xhttpFile}")" == "${originalXHTTP}" ]]
    [[ "$(<"${nginxMainConf}")" == "${originalNginxConf}" ]]
    [[ ! -e "${stateFile}" ]]
    [[ ! -e "${streamConf}" ]]
    grep -q '^restart:nginx:service-fail$' "${serviceLog}"
    ! grep -q '^refresh$' "${serviceLog}"
    if find "${streamTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-reality-stream.*' | grep -q .; then
        return 1
    fi

    writeRealityStreamEnableFixture
    serviceMode=reload-fail
    export PADM_FAKE_REALITY_STREAM_CP_MODE=restore-vision-fail
    : >"${serviceLog}"
    : >"${errorLog}"
    set +e
    configureRealityStreamSplit >/dev/null 2>&1
    enableStatus=$?
    set -e
    if [[ "${enableStatus}" -eq 0 ]]; then
        return 1
    fi
    jq -e '.inbounds[0].listen == "127.0.0.1" and .inbounds[0].port == 2443' "${visionFile}" >/dev/null
    grep -q '回滚失败' "${errorLog}"
    keptBackup=$(find "${streamTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-reality-stream.*' -print -quit)
    [[ -n "${keptBackup}" && -d "${keptBackup}" ]]
    rm -rf "${keptBackup}"
    export PADM_FAKE_REALITY_STREAM_CP_MODE=success

    writeRealityStreamEnableFixture
    serviceMode=success
    : >"${serviceLog}"
    : >"${errorLog}"
    export PADM_FAKE_REALITY_STREAM_XRAY_VALIDATE_MODE=success
    configureRealityStreamSplit
    jq -e '.inbounds[0].listen == "127.0.0.1" and .inbounds[0].port == 2443' "${visionFile}" >/dev/null
    jq -e '.enabled == true and .default_protocol == "vision" and .protocols.vision.restore_port == 443 and .protocols.vision.internal_port == 2443' "${stateFile}" >/dev/null
    grep -q 'site.example.com padm_website;' "${streamConf}"
    grep -q 'padm stream include start' "${nginxMainConf}"
    grep -Fq "include ${streamDir}/*.conf;" "${nginxMainConf}"
    [[ ! -e "${streamConf}.tmp" ]]
    if find "${streamTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-reality-stream.*' | grep -q .; then
        return 1
    fi

    PATH="${oldPath}"
    AUTO_INSTALL="${oldAutoInstall}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    unset PADM_REALITY_STREAM_STATE_FILE PADM_REALITY_STREAM_CONF_FILE PADM_REALITY_STREAM_NGINX_CONF PADM_REALITY_STREAM_XRAY_BINARY PADM_REALITY_STREAM_XRAY_CONF_DIR PADM_REALITY_STREAM_VISION_CONFIG_FILE PADM_REALITY_STREAM_XHTTP_CONFIG_FILE PADM_FAKE_REALITY_STREAM_NGINX_VALIDATE_MODE PADM_FAKE_REALITY_STREAM_XRAY_VALIDATE_MODE PADM_FAKE_REALITY_STREAM_OLD_PATH PADM_FAKE_REALITY_STREAM_VISION_FILE PADM_FAKE_REALITY_STREAM_CP_MODE AUTO_REALITY_STREAM_ENABLE AUTO_REALITY_STREAM_DOMAINS AUTO_REALITY_STREAM_DEFAULT_PROTOCOL AUTO_REALITY_STREAM_WEBSITE_PORT AUTO_REALITY_STREAM_VISION_PORT
}

assertCapturedSubscribeOutputs() {
    local user=$1
    local expectedDefault=$2
    local expectedServer=$3
    local expectedSNI=$4
    local expectedNetwork=$5
    local expectedType=$6

    grep -qxF "${expectedDefault}" "${SUBSCRIBE_CAPTURE_DIR}/default/${user}"
    grep -qx "    server: ${expectedServer}" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"
    if grep -q "^    servername:" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"; then
        grep -qx "    servername: ${expectedSNI}" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"
    elif grep -q "^    sni:" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"; then
        grep -qx "    sni: ${expectedSNI}" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"
    fi
    jq -e --arg server "${expectedServer}" --arg sni "${expectedSNI}" --arg network "${expectedNetwork}" --arg type "${expectedType}" '
      .[0].type == $type and
      .[0].server == $server and
      .[0].tls.server_name == $sni and
      (if $network == "tcp" then (.[0].transport | not) else .[0].transport.type == $network end)
    ' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/${user}" >/dev/null
}

runRealityCandidateFastRegression() {
    local fixtureFile="${TMP_DIR}/reality-candidates-fast.txt"
    local oldCandidatesFile="${PADM_REALITY_TARGET_CANDIDATES_FILE:-}"
    local oldRealityPageSize="${REALITY_TARGET_PAGE_SIZE:-}"
    local oldAutoInstall="${AUTO_INSTALL:-}"
    local firstRecommendedRealityCandidate firstDeveloperRealityCandidate microsoftCandidate targetAsnSummary currentAsnSummary

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

    [[ "$(realityTargetCandidates | awk 'END { print NR + 0 }')" == "5" ]]
    [[ "$(realityTargetFilteredCandidates recommended | awk 'END { print NR + 0 }')" == "4" ]]
    [[ "$(realityTargetFilteredCandidates developer | awk 'END { print NR + 0 }')" == "1" ]]
    [[ "$(realityTargetFilteredCandidates asia | awk 'END { print NR + 0 }')" == "1" ]]
    [[ "$(realityTargetFilteredCandidates microsoft | awk 'END { print NR + 0 }')" == "1" ]]
    firstRecommendedRealityCandidate=$(realityTargetFilteredCandidates recommended | awk 'NR == 1 { print; exit }')
    [[ "$(realityTargetCandidateField "${firstRecommendedRealityCandidate}" 1)" == "www.ibm.com" ]]
    firstDeveloperRealityCandidate=$(realityTargetFilteredCandidates developer | awk 'NR == 1 { print; exit }')
    [[ "$(realityTargetCandidateField "${firstDeveloperRealityCandidate}" 5)" == "developer" ]]
    targetIp=$(resolveRealityTargetIPv4 "www.ibm.com")
    targetProfile=$(lookupRealityTargetAsn "${targetIp}")
    targetAsn=${targetProfile%%$'\t'*}
    targetOrg=${targetProfile#*$'\t'}
    targetAsnSummary="${targetIp} ${targetAsn} ${targetOrg}"
    [[ "${targetAsnSummary}" == "192.0.2.1 AS64500 ExampleNet" ]]
    currentProfile=$(currentRealityNetworkProfile)
    currentIp=${currentProfile%%$'\t'*}
    currentProfileRest=${currentProfile#*$'\t'}
    currentAsn=${currentProfileRest%%$'\t'*}
    currentOrg=${currentProfileRest#*$'\t'}
    currentAsnSummary="${currentIp} ${currentAsn} ${currentOrg}"
    [[ "${currentAsnSummary}" == "203.0.113.10 AS64500 ExampleNet" ]]
    ! realityTargetCandidates | grep -q '^www.cloudflare.com|'
    ! realityTargetCandidates | grep -q '^www.apple.com|'

    selectRealityTargetCandidateInteractive recommended <<<"n
3
"
    [[ "${realityTargetHost}" == "www.reuters.com" ]]
    microsoftCandidate=$(realityTargetFilteredCandidates microsoft | awk 'NR == 1 { print; exit }')
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
    local _sampleIp _prefix prefixMask prefixAddressCount totalAddressCount=0
    local mask28Count=0 mask27Count=0 mask26Count=0 mask25Count=0 mask24Count=0
    AUTO_INSTALL=
    cat >"${asnPrefixFile}" <<'EOF'
192.0.2.0/24
198.51.100.0/25
203.0.113.0/26
10.0.0.0/27
172.16.0.0/28
EOF
    while IFS= read -r _prefix; do
        [[ "${_prefix}" =~ /([0-9]+)$ ]]
        prefixMask=${BASH_REMATCH[1]}
        [[ "${prefixMask}" -ge 28 && "${prefixMask}" -le 32 ]] && mask28Count=$((mask28Count + 1))
        [[ "${prefixMask}" -ge 27 && "${prefixMask}" -le 32 ]] && mask27Count=$((mask27Count + 1))
        [[ "${prefixMask}" -ge 26 && "${prefixMask}" -le 32 ]] && mask26Count=$((mask26Count + 1))
        [[ "${prefixMask}" -ge 25 && "${prefixMask}" -le 32 ]] && mask25Count=$((mask25Count + 1))
        [[ "${prefixMask}" -ge 24 && "${prefixMask}" -le 32 ]] && mask24Count=$((mask24Count + 1))
        prefixAddressCount=$((1 << (32 - prefixMask)))
        totalAddressCount=$((totalAddressCount + prefixAddressCount))
    done <"${asnPrefixFile}"
    [[ "${mask28Count}" == "1" ]]
    [[ "${mask27Count}" == "2" ]]
    [[ "${mask26Count}" == "3" ]]
    [[ "${mask25Count}" == "4" ]]
    [[ "${mask24Count}" == "5" ]]
    [[ "$((1 << (32 - 28)))" == "16" ]]
    [[ "${totalAddressCount}" == "496" ]]
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
    [[ "${selectedRealityAsnAddressTotal}" == "486" ]]
    [[ "${selectedRealityScannerRange}" == "随机抽样 12/486 IP" ]]
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
    [[ "$(realityTargetCandidates | awk 'END { print NR + 0 }')" -ge 194 ]]
    [[ "$(realityTargetFilteredCandidates recommended | awk 'END { print NR + 0 }')" -ge 50 ]]
    [[ "$(realityTargetFilteredCandidates developer | awk 'END { print NR + 0 }')" -ge 10 ]]
    [[ "$(realityTargetFilteredCandidates asia | awk 'END { print NR + 0 }')" -ge 2 ]]
    [[ "$(realityTargetFilteredCandidates microsoft | awk 'END { print NR + 0 }')" -ge 1 ]]
    firstRecommendedRealityCandidate=$(realityTargetFilteredCandidates recommended | awk 'NR == 1 { print; exit }')
    [[ "$(realityTargetCandidateField "${firstRecommendedRealityCandidate}" 1)" == "www.ibm.com" ]]
    firstDeveloperRealityCandidate=$(realityTargetFilteredCandidates developer | awk 'NR == 1 { print; exit }')
    [[ "$(realityTargetCandidateField "${firstDeveloperRealityCandidate}" 5)" == "developer" ]]
    firstRealityCandidate=$(realityTargetCandidates | awk 'NR == 1 { print; exit }')
    [[ "$(realityTargetCandidateField "${firstRealityCandidate}" 1)" == "www.ibm.com" ]]
    secondRealityCandidate=$(realityTargetCandidates | awk 'NR == 2 { print; exit }')
    [[ "$(realityTargetCandidateField "${secondRealityCandidate}" 1)" == "www.microsoft.com" ]]
    blockedCloudflareRealityCandidate=$(realityTargetBlockedCandidates | grep '^www.cloudflare.com|')
    [[ -n "${blockedCloudflareRealityCandidate}" ]]
    ! realityTargetCandidates | grep -q '^www.cloudflare.com|'
    ! realityTargetCandidates | grep -q '^www.apple.com|'
}

runRuntimeAndRealityRegression() {
    visionLink=$(serializeVlessRealityVisionLink "uuid-a" "node.example.com" "443" "www.microsoft.com" "pubkey" "pqv" "user-a")
    [[ "${visionLink}" == "vless://uuid-a@node.example.com:443?encryption=none&security=reality&pqv=pqv&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=pubkey&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#user-a" ]]
    visionEncLink=$(serializeVlessRealityVisionLink "uuid-a" "node.example.com" "443" "www.microsoft.com" "pubkey" "pqv" "user-a" "mlkem768x25519plus.native.0rtt.test")
    [[ "${visionEncLink}" == "vless://uuid-a@node.example.com:443?encryption=mlkem768x25519plus.native.0rtt.test&security=reality&pqv=pqv&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=pubkey&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#user-a" ]]
    grpcLink=$(serializeVlessRealityGrpcLink "uuid-a" "node.example.com" "8443" "www.microsoft.com" "pubkey" "pqv" "user-a")
    [[ "${grpcLink}" == "vless://uuid-a@node.example.com:8443?encryption=none&security=reality&pqv=pqv&type=grpc&sni=www.microsoft.com&fp=chrome&pbk=pubkey&sid=6ba85179e30d4fc2&path=grpc&serviceName=grpc#user-a" ]]
    xhttpLink=$(serializeVlessRealityXHTTPLink "uuid-a" "cdn.example.com" "443" "www.microsoft.com" "/xHTTP" "pubkey" "user-a")
    [[ "${xhttpLink}" == "vless://uuid-a@cdn.example.com:443?encryption=none&security=reality&type=xhttp&sni=www.microsoft.com&host=www.microsoft.com&fp=chrome&path=/xHTTP&pbk=pubkey&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#user-a" ]]
    xhttpLink=$(serializeVlessRealityXHTTPLink "uuid-a" "cdn.example.com" "443" "www.microsoft.com" "/custom" "pubkey" "user-a" none "front.example.com" "stream-one")
    [[ "${xhttpLink}" == "vless://uuid-a@cdn.example.com:443?encryption=none&security=reality&type=xhttp&sni=www.microsoft.com&host=front.example.com&fp=chrome&path=/custom&mode=stream-one&pbk=pubkey&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#user-a" ]]
    domain=tls.example.com
    currentHost=
    collectTLSProfile
    [[ "${tlsCertDomain}" == "tls.example.com" ]]
    [[ "${tlsSNI}" == "tls.example.com" ]]
    protocolMeta 7 security | grep -qx reality
    protocolMeta 7 transport | grep -qx tcp
    protocolSelectionHasCapability 7 needs_reality
    protocolSelectionNeedsCertificate 0
    protocolSelectionHasCapability 6 needs_udp
    [[ "$(protocolMeta 7 transport)" == "tcp" ]]
    [[ "$(protocolMeta 7 security)" == "reality" ]]

    parseInstallArgs --install-type custom --core xray --protocols 7 --domain node.example.com --reality-target www.microsoft.com:443 --reality-server-name www.microsoft.com --entry-host node.example.com --reuse-last no
    [[ "${AUTO_REALITY_TARGET}" == "www.microsoft.com:443" ]]
    [[ "${AUTO_REALITY_SERVER_NAME}" == "www.microsoft.com" ]]
    [[ "${AUTO_ENTRY_HOST}" == "node.example.com" ]]
    [[ "$(autoValueForKey reality_target)" == "www.microsoft.com:443" ]]
    [[ "$(autoValueForKey install_type)" == "5" ]]
    validateGitHubReleaseTag "v26.3.27"
    validateGitHubReleaseTag "202605082251"
    validateGitHubReleaseTag "release-2026.05.08"
    ! validateGitHubReleaseTag "../bad"
    ! validateGitHubReleaseTag "bad/tag"
    geoTmpDir="${TMP_DIR}/geo"
    mkdir -p "${geoTmpDir}"
    printf 'geoip' >"${geoTmpDir}/geoip.dat"
    printf 'geosite' >"${geoTmpDir}/geosite.dat"
    ensureXrayGeoFiles "${geoTmpDir}"
    [[ "$(<"${geoTmpDir}/geoip.dat")" == "geoip" ]]
    [[ "$(<"${geoTmpDir}/geosite.dat")" == "geosite" ]]
    printf 'v20260513' >"${geoTmpDir}/geo.version"
    [[ "$(xrayGeoDisplayVersion "${geoTmpDir}")" == "版本 v20260513" ]]
    rm -f "${geoTmpDir}/geo.version"
    [[ "$(xrayGeoDisplayVersion "${geoTmpDir}")" == 更新时间* || "$(xrayGeoDisplayVersion "${geoTmpDir}")" == "版本未知" ]]

    parseRealityTargetInput "example.com"
    [[ "${realityTargetHost}" == "example.com" ]]
    [[ "${realityTargetPort}" == "443" ]]
    parseRealityTargetInput "example.org:8443"
    [[ "${realityTargetHost}" == "example.org" ]]
    [[ "${realityTargetPort}" == "8443" ]]
    ! parseRealityTargetInput "bad.example.org:70000"
    [[ "${realityTargetHost}" == "example.org" ]]
    [[ "${realityTargetPort}" == "8443" ]]
    [[ "${realitySNI}" == "example.org" ]]
    scoreLine=$(scoreRealityTargetFromTlsPing $'Pinging with SNI\nTLS Post-Quantum key exchange: X25519MLKEM768\nTLS version: TLS 1.3\nCertificate chain total length: 4096')
    [[ "$(printf '%s\n' "${scoreLine}" | awk -F'\t' '{print $1}')" == "A" ]]
    showRealityTargetQuality "www.microsoft.com:443"
    [[ "$(awk -F'\t' '$10 == "A" || $10 == "B" {count++} END{print count + 0}' "${PADM_REALITY_TARGET_SCAN_FILE}")" -ge "1" ]]
    cachedLine=$(awk -F'\t' '$1 == "www.microsoft.com:443" {printf "%s\t%s\t%s\t%s\t%s\t%s\n", $10, $11, $12, $13, $14, $15; exit}' "${PADM_REALITY_TARGET_SCAN_FILE}")
    [[ "$(printf '%s\n' "${cachedLine}" | awk -F'\t' '{print $1}')" == "A" ]]
    grep -q "tls ping www.microsoft.com:443" "${REALITY_TLS_PING_ARGS_FILE}"
    scoreLine=$(scoreRealityTargetFromTlsPing $'Pinging with SNI\nTLS Post-Quantum key exchange: X25519MLKEM768\nTLS version: TLS 1.3\nCertificate chain total length: 2048')
    [[ "$(printf '%s\n' "${scoreLine}" | awk -F'\t' '{print $1}')" == "B" ]]
    scoreLine=$(scoreRealityTargetFromTlsPing $'Pinging with SNI\nTLS version: TLS 1.3\nCertificate chain total length: 4096')
    [[ "$(printf '%s\n' "${scoreLine}" | awk -F'\t' '{print $1}')" == "C" ]]
    scoreLine=$(scoreRealityTargetFromTlsPing $'Pinging with SNI\nTLS version: TLS 1.2\nCertificate chain total length: 4096')
    [[ "$(printf '%s\n' "${scoreLine}" | awk -F'\t' '{print $1}')" == "FAIL" ]]
}

runAutoInstallRealityRouteRegression() (
    local actions=
    local output=
    local oldCoreInstallType="${coreInstallType:-}"

    recordMenuAction() {
        actions+="$1"$'\n'
    }
    assertMenuAction() {
        grep -qxF "$1" <<<"${actions}"
    }

    parseInstallArgs --install-type reality --core xray --reality-target www.microsoft.com:443 --reality-server-name www.microsoft.com --reuse-last no
    AUTO_INSTALL_SUMMARY_SHOWN=
    selectInstallType=
    coreInstallType=

    echoContent() { :; }
    uiStyle() { printf '%s' "$2"; }
    menuLine() { output+="$*"$'\n'; }
    menuMutedLine() { output+="$*"$'\n'; }
    menuSection() { :; }
    menuItem() { output+="$2 $3"$'\n'; }
    menuRecommendedItem() { output+="$2 $3"$'\n'; }
    menuDangerItem() { output+="$2 $3"$'\n'; }
    menuReturnItem() { output+="$2 $3"$'\n'; }
    menuClose() { return 0; }
    progressCard() { return 0; }
    statusCard() { recordMenuAction "statusCard:$1"; }
    successCard() { recordMenuAction "successCard:$1"; }
    errorCard() { recordMenuAction "errorCard:$1"; }
    showInstallStatus() { recordMenuAction showInstallStatus; }
    checkWgetShowProgress() { return 0; }
    mkdirTools() { recordMenuAction mkdirTools; return 0; }
    aliasInstall() { recordMenuAction aliasInstall; return 0; }
    getScriptVersion() { printf 'test\n'; }
    installXrayReality() { recordMenuAction installXrayReality; }
    installSingBoxReality() { recordMenuAction installSingBoxReality; }
    xrayCoreInstall() { recordMenuAction xrayCoreInstall; }
    singBoxInstall() { recordMenuAction singBoxInstall; }
    customXrayInstall() { recordMenuAction "customXrayInstall:$*"; }
    customSingBoxInstall() { recordMenuAction "customSingBoxInstall:$*"; }
    manageSubscription() { recordMenuAction manageSubscription; }
    protocolEntryMenu() { recordMenuAction protocolEntryMenu; }
    siteCertificateMenu() { recordMenuAction siteCertificateMenu; }
    routingAccessMenu() { recordMenuAction routingAccessMenu; }
    coreVersionManageMenu() { recordMenuAction coreVersionManageMenu; }
    systemScriptMenu() { recordMenuAction systemScriptMenu; }
    advancedDangerMenu() { recordMenuAction advancedDangerMenu; }

    menu

    assertMenuAction showInstallStatus
    assertMenuAction mkdirTools
    assertMenuAction aliasInstall
    assertMenuAction installXrayReality
    [[ "$(autoValueForKey main_menu)" == "1" ]]
    [[ "$(autoValueForKey install_type)" == "3" ]]
    [[ "$(autoValueForKey core)" == "1" ]]
    [[ "${selectInstallType}" == "3" ]]
    ! grep -qxF 'installSingBoxReality' <<<"${actions}"
    ! grep -qxF 'xrayCoreInstall' <<<"${actions}"
    ! grep -qxF 'singBoxInstall' <<<"${actions}"
    ! grep -q '^errorCard:' <<<"${actions}"
    coreInstallType="${oldCoreInstallType}"
)

resolveReleaseWorkflowVersionForRegression() {
    local isReleaseCommit=$1
    local currentVersion=$2
    local latestTag=$3
    local commits=$4
    local releaseVersion needsBump
    local baseVersion major minor patch bump commitMessage

    releaseWorkflowCommitRequiresMajorBump() {
        local commitMessage=$1
        echo "${commitMessage}" | grep -qE '^[a-zA-Z]+(\([^)]*\))?!:|BREAKING CHANGE:'
    }

    releaseWorkflowCommitRequiresMinorBump() {
        local commitMessage=$1
        echo "${commitMessage}" | grep -qE '^feat(\([^)]*\))?:'
    }

    releaseWorkflowCommitRequiresPatchBump() {
        local commitMessage=$1
        echo "${commitMessage}" | grep -qE '^(fix|perf|refactor|docs|test|build|ci|chore)(\([^)]*\))?:'
    }

    if [[ "${isReleaseCommit}" == "true" ]]; then
        releaseVersion="${currentVersion}"
        needsBump=false
    else
        baseVersion=${latestTag#v}
        major=${baseVersion%%.*}
        minor=${baseVersion#*.}
        minor=${minor%%.*}
        patch=${baseVersion##*.}
        bump=none

        while IFS= read -r commitMessage; do
            if releaseWorkflowCommitRequiresMajorBump "${commitMessage}"; then
                bump=major
                break
            elif [[ "${bump}" != "minor" ]] && releaseWorkflowCommitRequiresMinorBump "${commitMessage}"; then
                bump=minor
            elif [[ "${bump}" == "none" ]] && releaseWorkflowCommitRequiresPatchBump "${commitMessage}"; then
                bump=patch
            fi
        done <<<"${commits}"

        case "${bump}" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        esac

        releaseVersion="v${major}.${minor}.${patch}"
        if [[ "${releaseVersion}" != "${currentVersion}" ]]; then
            needsBump=true
        else
            needsBump=false
        fi
    fi
    printf '%s %s\n' "${releaseVersion}" "${needsBump}"
}

runReleaseWorkflowVersionRegression() {
    local result
    result=$(resolveReleaseWorkflowVersionForRegression false v1.2.0 v1.2.0 $'fix(update): harden script refresh rollback')
    [[ "${result}" == "v1.2.1 true" ]]
    result=$(resolveReleaseWorkflowVersionForRegression false v1.2.0 v1.2.0 $'feat(subscription): add new flow')
    [[ "${result}" == "v1.3.0 true" ]]
    result=$(resolveReleaseWorkflowVersionForRegression false v1.2.0 v1.2.0 $'style: whitespace only')
    [[ "${result}" == "v1.2.0 false" ]]
    result=$(resolveReleaseWorkflowVersionForRegression false v0.0.0 v0.0.0 $'feat(core): initial release')
    [[ "${result}" == "v0.1.0 true" ]]
    result=$(resolveReleaseWorkflowVersionForRegression true v1.3.0 v1.2.0 $'chore(release): v1.3.0')
    [[ "${result}" == "v1.3.0 false" ]]
}

runRealityConfigVlessEncryptionRegression() {
    local fakeXrayBinary="${TMP_DIR}/fake-xray-vlessenc"
    local vlessConfigDir="${TMP_DIR}/vlessenc-xray-conf"
    local vlessConfigFile="${vlessConfigDir}/07_VLESS_vision_reality_inbounds.json"
    local vlessStateFile="${TMP_DIR}/vlessenc-state.json"
    local oldTmpDir="${TMPDIR:-}"
    local vlessTmpRoot="${TMP_DIR}/vlessenc-tmp"
    local vlessTmpMarker="${TMP_DIR}/vlessenc-tmp-files.txt"
    local vlessOriginalConfig
    local vlessOriginalState
    local vlessEnabledConfig
    local vlessEnabledState
    local vlessValidateMode=success
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
    if find "${vlessTmpRoot}" -mindepth 1 -maxdepth 1 \( -name 'padm-vlessenc.out.*' -o -name 'padm-vlessenc.err.*' \) | grep -q .; then
        return 1
    fi

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
    if find "${vlessTmpRoot}" -mindepth 1 -maxdepth 1 \( -name 'padm-vlessenc.out.*' -o -name 'padm-vlessenc.err.*' \) | grep -q .; then
        return 1
    fi
    unset PADM_XRAY_BINARY PADM_XRAY_CONF_DIR PADM_VLESS_REALITY_CONFIG_FILE PADM_VLESS_XHTTP_CONFIG_FILE PADM_VLESS_ENCRYPTION_STATE_FILE PADM_FAKE_XRAY_VALIDATE_MODE PADM_FAKE_VLESSENC_TMP_MARKER
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runRealityConfigScannerRegression() {
    local scannerCandidatesFile="${TMP_DIR}/reality-config-scanner-candidates.txt"
    local oldCandidatesFile="${PADM_REALITY_TARGET_CANDIDATES_FILE:-}"
    local scannerLine batchLinesFile failedTargetsFile
    cat >"${scannerCandidatesFile}" <<'EOF'
fail-auto.example.com|fail-auto.example.com|Fail Auto|global|large_site|unknown|1|yes|fixture failing candidate
www.ibm.com|www.ibm.com|IBM|global|large_site|unknown|2|yes|fixture fallback candidate
EOF
    export PADM_REALITY_TARGET_CANDIDATES_FILE="${scannerCandidatesFile}"

    cat >"${TMP_DIR}/realitlscanner.csv" <<'CSV'
IP,ORIGIN,CERT_DOMAIN,CERT_ISSUER,GEO_CODE
192.0.2.10,192.0.2.0/24,www.cloudflare.com,"Google Trust Services",N/A
198.51.100.11,198.51.100.0/24,scanner.example.com,"Let's Encrypt",N/A
192.0.2.12,192.0.2.0/24,images.apple.com,"Apple Inc.",N/A
192.0.2.13,192.0.2.0/24,Common Name,"Test",N/A
192.0.2.14,192.0.2.0/24,CloudFlare Origin Certificate,"CloudFlare, Inc.",N/A
192.0.2.15,192.0.2.0/24,localhost,"Test",N/A
192.0.2.16,192.0.2.0/24,invalid.invalid,"Invalid",N/A
192.0.2.17,192.0.2.0/24,192.0.2.17,"Self",N/A
CSV
    scannerImport=0
    while IFS=, read -r ip origin domain issuer geo; do
        [[ "${ip}" == "IP" ]] && continue
        domain=${domain#\"}
        domain=${domain%\"}
        if ! realityTargetScannerRecordAllowed "${domain}" || realityTargetCandidatePool | awk -F'|' -v host="${domain}" '$1 == host {found=1} END{exit !found}'; then
            continue
        fi
        scannerImport=$((scannerImport + 1))
    done < "${TMP_DIR}/realitlscanner.csv"
    [[ "${scannerImport}" == "1" ]]
    importRealityScannerResults "${TMP_DIR}/realitlscanner.csv" "AS64500" "ExampleNet"
    scannerLine=$(grep -F $'scanner.example.com:443\tscanner.example.com\tscanner.example.com\tscanner' "${PADM_REALITY_TARGET_SCAN_FILE}")
    [[ "$(realityTargetResultField "${scannerLine}" 7)" == "AS64501" ]]
    [[ "$(realityTargetResultField "${scannerLine}" 8)" == "RemoteNet" ]]
    [[ "$(realityTargetResultField "${scannerLine}" 9)" == "different_network" ]]
    batchLinesFile="${TMP_DIR}/reality-batch-lines.tsv"
    failedTargetsFile="${TMP_DIR}/reality-failed-targets.txt"
    writeRealityTargetResultLine "batch-old.example.com:443" "old.example.com" "Old Batch" "test" "unknown" "192.0.2.20" "AS64500" "ExampleNet" "same_asn" "B" "yes" "4096" "yes" "1234567800" "old batch line"
    {
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "batch-old.example.com:443" "new.example.com" "New Batch" "test" "unknown" "192.0.2.21" "AS64500" "ExampleNet" "same_asn" "A" "yes" "8192" "yes" "1234567899" "new batch line"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "batch-new.example.com:443" "batch-new.example.com" "Batch New" "test" "unknown" "192.0.2.22" "AS64500" "ExampleNet" "same_asn" "B" "yes" "4096" "yes" "1234567898" "second batch line"
    } >"${batchLinesFile}"
    writeRealityTargetResultLines "${batchLinesFile}"
    batchLine=$(grep -F $'batch-old.example.com:443\tnew.example.com' "${PADM_REALITY_TARGET_SCAN_FILE}")
    [[ "$(realityTargetResultField "${batchLine}" 10)" == "A" ]]
    grep -qF $'batch-new.example.com:443\tbatch-new.example.com' "${PADM_REALITY_TARGET_SCAN_FILE}"
    printf '%s\n' "batch-old.example.com:443" >"${failedTargetsFile}"
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "batch-old.example.com" "batch-old.example.com" "Batch Old" "global" "large_site" "unknown" "9" "yes" "batch candidate" >>"${scannerCandidatesFile}"
    removeRealityTargetsFromUnifiedLibrary "${failedTargetsFile}"
    ! grep -qF $'batch-old.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
    ! grep -qF 'batch-old.example.com|' "${scannerCandidatesFile}"

    rm -f "${PADM_REALITY_TARGET_SCAN_FILE}" "${REALITY_TLS_PING_ARGS_FILE}"
    realityTargetCandidateBlocked "images.apple.com"
    unset AUTO_REALITY_SERVER_NAME
    writeRealityTargetResultLine "local.example.com:443" "sni.local.example.com" "Local Example" "test" "no" "192.0.2.1" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "same ASN test target"
    writeRealityTargetResultLine "remote.example.com:443" "sni.remote.example.com" "Remote Example" "test" "no" "198.51.100.1" "AS64501" "RemoteNet" "different_network" "A" "yes" "8192" "yes" "1234567899" "longer cert but different network"
    [[ "$(awk -F'\t' '$10 == "A" || $10 == "B" {count++} END{print count + 0}' "${PADM_REALITY_TARGET_SCAN_FILE}")" == "2" ]]
    scanLine=$(sortedRealityTargetResults | awk -F'\t' '$10 == "A" || $10 == "B" {print; exit}')
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
    grep -q "tls ping www.ibm.com:443" "${REALITY_TLS_PING_ARGS_FILE}"
    if [[ -n "${oldCandidatesFile}" ]]; then
        export PADM_REALITY_TARGET_CANDIDATES_FILE="${oldCandidatesFile}"
    else
        unset PADM_REALITY_TARGET_CANDIDATES_FILE
    fi
    unset PADM_FAKE_XRAY_ONLY_IBM
}

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
    local rc reloadCalls=0 preservedBackupDir

    mkdir -p "${root}" "${root}/tmp"
    TMPDIR="${root}/tmp"
    cat >"${xrayVision}" <<'JSON'
{"inbounds":[{}, {"streamSettings":{"realitySettings":{"target":"old.example.com:443","serverNames":["old-sni.example.com"]}}}]}
JSON
    cat >"${xrayXhttp}" <<'JSON'
{"inbounds":[{"streamSettings":{"realitySettings":{"target":"old.example.com:443","serverNames":["old-sni.example.com"]},"xhttpSettings":{"host":"old-sni.example.com"}}}]}
JSON
    cat >"${singBoxVision}" <<'JSON'
{"inbounds":[{"tls":{"server_name":"old-sni.example.com","reality":{"handshake":{"server":"old.example.com","server_port":443}}}}]}
JSON
    cat >"${singBoxGrpc}" <<'JSON'
{"inbounds":[{"tls":{"server_name":"old-sni.example.com","reality":{"handshake":{"server":"old.example.com","server_port":443}}}}]}
JSON
    realityTargetHost=old.example.com
    realityTargetPort=443
    realitySNI=old-sni.example.com
    xrayVLESSRealitySNI=old-sni.example.com
    xrayVLESSRealityXHTTPSNI=old-sni.example.com
    singBoxVLESSRealityVisionSNI=old-sni.example.com
    singBoxVLESSRealityGRPCSNI=old-sni.example.com
    PADM_REALITY_XRAY_VISION_CONFIG_FILE="${xrayVision}"
    PADM_REALITY_XRAY_XHTTP_CONFIG_FILE="${xrayXhttp}"
    PADM_REALITY_SINGBOX_VISION_CONFIG_FILE="${singBoxVision}"
    PADM_REALITY_SINGBOX_GRPC_CONFIG_FILE="${singBoxGrpc}"
    applyLog=$(realityTargetApplyLog)
    : >"${statusLog}"
    : >"${refreshLog}"

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

    set +e
    changeInstalledRealityTarget "new.example.com:8443" "new-sni.example.com"
    rc=$?
    set -e

    [[ "${rc}" == "1" ]]
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
    cat >"${xrayVision}" <<'JSON'
{"inbounds":[{}, {"streamSettings":{"realitySettings":{"target":"old.example.com:443","serverNames":["old-sni.example.com"]}}}]}
JSON
    cat >"${xrayXhttp}" <<'JSON'
{bad-json
JSON
    set +e
    changeInstalledRealityTarget "new.example.com:8443" "new-sni.example.com"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${reloadCalls}" == "0" ]]
    [[ "$(jq -r '.inbounds[1].streamSettings.realitySettings.target' "${xrayVision}")" == "old.example.com:443" ]]
    [[ "${realityTargetHost}" == "old.example.com" ]]
    [[ "${realityTargetPort}" == "443" ]]
    [[ ! -s "${refreshLog}" ]]
    grep -q '配置应用失败，已回滚' "${statusLog}"
    grep -q "失败文件: ${xrayXhttp}" "${statusLog}"
    grep -q "排查日志: ${applyLog}" "${statusLog}"
    grep -q 'Invalid numeric literal' "${applyLog}"

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
    cat >"${xrayVision}" <<'JSON'
{"inbounds":[{}, {"streamSettings":{"realitySettings":{"target":"old.example.com:443","serverNames":["old-sni.example.com"]}}}]}
JSON
    cat >"${xrayXhttp}" <<'JSON'
{bad-json
JSON
    cp() {
        if [[ "$1" == */xray/07_VLESS_vision_reality_inbounds.json && "$2" == "${xrayVision}" ]]; then
            return 1
        fi
        command cp "$@"
    }
    set +e
    changeInstalledRealityTarget "new.example.com:8443" "new-sni.example.com"
    rc=$?
    set -e
    unset -f cp
    [[ "${rc}" == "1" ]]
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
    cat >"${xrayVision}" <<'JSON'
{"inbounds":[{}, {"streamSettings":{"realitySettings":{"target":"old.example.com:443","serverNames":["old-sni.example.com"]}}}]}
JSON
    cat >"${xrayXhttp}" <<'JSON'
{"inbounds":[{"streamSettings":{"realitySettings":{"target":"old.example.com:443","serverNames":["old-sni.example.com"]},"xhttpSettings":{"host":"old-sni.example.com"}}}]}
JSON
    cp() {
        if [[ "$1" == */xray/07_VLESS_vision_reality_inbounds.json && "$2" == "${xrayVision}" ]]; then
            return 1
        fi
        command cp "$@"
    }
    set +e
    changeInstalledRealityTarget "new.example.com:8443" "new-sni.example.com"
    rc=$?
    set -e
    unset -f cp
    [[ "${rc}" == "1" ]]
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

    set +e
    changeInstalledRealityTarget "new.example.com:8443" "new-sni.example.com"
    rc=$?
    set -e

    [[ "${rc}" == "1" ]]
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

runXHTTPDownloadSettingsRegression() {
    local xhttpConfigFile="${TMP_DIR}/xhttp-download-settings.json"
    local oldConfigFile="${PADM_XHTTP_CONFIG_FILE:-}"
    local oldCoreInstallType="${coreInstallType:-}"
    local oldAutoInstall="${AUTO_INSTALL:-}"
    local oldAutoInstallType="${AUTO_INSTALL_TYPE:-}"
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
}

runRealityConfigRefreshSubscriptionRegression() {
    local oldNginxConfigPath="${nginxConfigPath:-}"
    local oldSubscribePort="${subscribePort:-}"
    local subscribeCalls=0
    local refreshDir="${TMP_DIR}/reality-refresh-subscribe/"
    mkdir -p "${refreshDir}"
    nginxConfigPath="${refreshDir}"
    subscribePort=
    subscribe() { subscribeCalls=$((subscribeCalls + 1)); }
    readNginxSubscribe() { :; }

    refreshSubscriptionsAfterRealityTargetChange >/dev/null
    [[ "${subscribeCalls}" == "0" ]]

    : >"${nginxConfigPath}subscribe.conf"
    refreshSubscriptionsAfterRealityTargetChange >/dev/null
    [[ "${subscribeCalls}" == "1" ]]

    rm -f "${nginxConfigPath}subscribe.conf"
    readNginxSubscribe() { subscribePort=39778; }
    refreshSubscriptionsAfterRealityTargetChange >/dev/null
    [[ "${subscribeCalls}" == "2" ]]

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
    writeRealityTargetResultLine "fail.example.com:443" "fail.example.com" "Fail Example" "scanner" "unknown" "192.0.2.14" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "stale target"
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
    runRegressionStep reality-config-apply runRealityConfigApplyRegression
    runRegressionStep reality-config-change-reload-failure runRealityConfigChangeReloadFailureRegression
    runRegressionStep reality-config-change-subscription-refresh-failure runRealityConfigChangeSubscriptionRefreshFailureRegression
    runRegressionStep reality-config-xhttp-download-settings runXHTTPDownloadSettingsRegression
    runRegressionStep reality-config-refresh-subscription runRealityConfigRefreshSubscriptionRegression
    runRegressionStep reality-config-import-skip runRealityConfigImportSkipRegression
}

runSubscriptionOutputRegression() {
    rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
    export REGRESSION_ECHO_LOG="${SUBSCRIBE_CAPTURE_DIR}/screen.log"
local profileEmail profileId profilePassword profileName profileUuid
IFS=$'\037' read -r profileEmail profileId profilePassword _ profileName profileUuid <<<"$(subscriptionAccountProfile '{"email":"user-main","id":"uuid-main","password":"pass-main"}')"
[[ "${profileEmail}" == "user-main" && "${profileId}" == "uuid-main" && "${profilePassword}" == "pass-main" && "${profileName}" == "user-main" && "${profileUuid}" == "uuid-main" ]]
IFS=$'\037' read -r _ _ profilePassword _ profileName profileUuid <<<"$(subscriptionAccountProfile '{"name":"udp-user","password":"udp-pass"}')"
[[ "${profilePassword}" == "udp-pass" && "${profileName}" == "udp-user" && -z "${profileUuid}" ]]
coreInstallType=1
currentHost="tls.example.com"
realityEntryHost="node.example.com"
xrayVLESSRealitySNI="www.microsoft.com"
currentRealityPublicKey="pubkey"
currentRealityMldsa65Verify="pqv"
defaultBase64Code vlessReality 443 user-a-main uuid-a "" ""
expectedVisionLink=$(serializeVlessRealityVisionLink "uuid-a" "node.example.com" "443" "www.microsoft.com" "pubkey" "pqv" "user-a-main")
assertCapturedSubscribeOutputs "user" "${expectedVisionLink}" "node.example.com" "www.microsoft.com" "tcp" "vless"
jq -e '.[0].flow == "xtls-rprx-vision" and .[0].tls.reality.public_key == "pubkey"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
defaultBase64Code vlessRealityGRPC 8443 user-a-grpc uuid-a "" ""
expectedGrpcLink=$(serializeVlessRealityGrpcLink "uuid-a" "node.example.com" "8443" "www.microsoft.com" "pubkey" "pqv" "user-a-grpc")
assertCapturedSubscribeOutputs "user" "${expectedGrpcLink}" "node.example.com" "www.microsoft.com" "grpc" "vless"
jq -e '.[0].transport.service_name == "grpc" and .[0].tls.reality.short_id == "6ba85179e30d4fc2"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/user" >/dev/null
grep -q 'pqv%3Dpqv' "${SUBSCRIBE_CAPTURE_DIR}/screen.log"

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
local oldConfigPath="${configPath:-}"
configPath="${TMP_DIR}/xhttp-subscription-conf/"
mkdir -p "${configPath}"
cat >"${configPath}12_VLESS_XHTTP_inbounds.json" <<'EOF'
{"inbounds":[{"streamSettings":{"xhttpSettings":{"host":"front.example.com","path":"/custom-xhttp","mode":"packet-up"}}}]}
EOF
xrayVLESSRealityXHTTPSNI="www.microsoft.com"
currentRealityXHTTPPublicKey="pubkey"
defaultBase64Code vlessXHTTP 443 user-a-xhttp uuid-a "cdn.example.com" "/ignored"
expectedXHTTPLink=$(serializeVlessRealityXHTTPLink "uuid-a" "cdn.example.com" "443" "www.microsoft.com" "/custom-xhttp" "pubkey" "user-a-xhttp" none "front.example.com" "packet-up")
grep -qxF "${expectedXHTTPLink}" "${SUBSCRIBE_CAPTURE_DIR}/default/user"
grep -qx "    server: cdn.example.com" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user"
grep -qx "    servername: www.microsoft.com" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user"
grep -qx "      path: /custom-xhttp" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user"
grep -qx "      host: front.example.com" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user"
grep -qx "      mode: packet-up" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user"
configPath="${oldConfigPath}"

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code vlesstcp 443 tls-user uuid-tls "" ""
assertCapturedSubscribeOutputs "tls" "vless://uuid-tls@tls.example.com:443?encryption=none&security=tls&type=tcp&host=tls.example.com&fp=chrome&headerType=none&sni=tls.example.com&flow=xtls-rprx-vision#tls-user" "tls.example.com" "tls.example.com" "tcp" "vless"
jq -e '.[0].flow == "xtls-rprx-vision" and (.[0].tls.reality | not)' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code vlessws 443 tls-ws-user uuid-ws "edge.example.com" "/ws-path"
assertCapturedSubscribeOutputs "tls" "vless://uuid-ws@edge.example.com:443?encryption=none&security=tls&type=ws&host=tls.example.com&sni=tls.example.com&fp=chrome&path=/ws-path#tls-ws-user" "edge.example.com" "tls.example.com" "ws" "vless"
jq -e '.[0].transport.path == "/ws-path" and .[0].transport.headers.Host == "tls.example.com" and .[0].multiplex.enabled == false' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
currentPath="svc-"
defaultBase64Code vlessgrpc 443 tls-grpc-user uuid-grpc "edge.example.com" ""
assertCapturedSubscribeOutputs "tls" "vless://uuid-grpc@edge.example.com:443?encryption=none&security=tls&type=grpc&host=tls.example.com&path=svc-grpc&serviceName=svc-grpc&fp=chrome&alpn=h2&sni=tls.example.com#tls-grpc-user" "edge.example.com" "tls.example.com" "grpc" "vless"
jq -e '.[0].transport.service_name == "svc-grpc" and .[0].packet_encoding == "xudp"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code vmessws 443 tls-vmess-user uuid-vmess "edge.example.com" "/vmess-ws"
vmessWsLink=$(sed -n '1p' "${SUBSCRIBE_CAPTURE_DIR}/default/tls")
[[ "${vmessWsLink}" == vmess://* ]]
assertCapturedSubscribeOutputs "tls" "${vmessWsLink}" "edge.example.com" "tls.example.com" "ws" "vmess"
jq -e '.[0].alter_id == 0 and .[0].transport.max_early_data == 2048 and .[0].packet_encoding == "packetaddr"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code trojan 443 tls-trojan-user pass-trojan "" ""
assertCapturedSubscribeOutputs "tls" "trojan://pass-trojan@tls.example.com:443?peer=tls.example.com&fp=chrome&sni=tls.example.com&alpn=http/1.1#tls-trojan-user_Trojan" "tls.example.com" "tls.example.com" "tcp" "trojan"
jq -e '.[0].password == "pass-trojan" and .[0].tls.alpn[0] == "http/1.1"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
currentPath="svc-"
defaultBase64Code trojangrpc 443 tls-trojan-grpc-user pass-trojan-grpc "edge.example.com" ""
assertCapturedSubscribeOutputs "tls" "trojan://pass-trojan-grpc@edge.example.com:443?encryption=none&peer=tls.example.com&security=tls&type=grpc&fp=chrome&sni=tls.example.com&alpn=h2&path=svc-trojangrpc&serviceName=svc-trojangrpc#tls-trojan-grpc-user" "edge.example.com" "tls.example.com" "grpc" "trojan"
jq -e '.[0].transport.service_name == "svc-trojangrpc" and (.[0].tls | has("insecure") | not) and .[0].multiplex.enabled == false' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code vmessHTTPUpgrade 443 tls-httpupgrade-user uuid-http "edge.example.com" "/upgrade"
httpUpgradeLink=$(sed -n '1p' "${SUBSCRIBE_CAPTURE_DIR}/default/tls")
[[ "${httpUpgradeLink}" == vmess://* ]]
[[ "${httpUpgradeLink}" != " "* ]]
assertCapturedSubscribeOutputs "tls" "${httpUpgradeLink}" "edge.example.com" "tls.example.com" "httpupgrade" "vmess"
jq -e '.[0].security == "auto" and .[0].transport.path == "/upgrade" and .[0].packet_encoding == "packetaddr"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
singBoxAnyTLSPort=8443
defaultBase64Code anytls 443 tls-any-user pass-any "" ""
assertCapturedSubscribeOutputs "tls" "anytls://pass-any@tls.example.com:8443?peer=tls.example.com&insecure=0&sni=tls.example.com#tls-any-user" "tls.example.com" "tls.example.com" "tcp" "anytls"
jq -e '.[0].password == "pass-any" and .[0].server_port == 8443' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
singBoxHysteria2Port=9443
hysteria2ClientUploadSpeed=100
hysteria2ClientDownloadSpeed=200
defaultBase64Code hysteria 8443 tls-hysteria-user pass-hysteria "" ""
assertCapturedSubscribeOutputs "tls" "hysteria2://pass-hysteria@tls.example.com:9443?peer=tls.example.com&insecure=0&sni=tls.example.com&alpn=h3#tls-hysteria-user" "tls.example.com" "tls.example.com" "tcp" "hysteria2"
jq -e '.[0].password == "pass-hysteria" and .[0].up_mbps == 100 and .[0].down_mbps == 200 and .[0].tls.alpn[0] == "h3"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
singBoxHysteria2Port=9443
hysteria2ClientUploadSpeed=100
hysteria2ClientDownloadSpeed=200
defaultBase64Code hysteria "20000-20002" tls-hysteria-hop-user pass-hysteria-hop "" ""
grep -qxF "hysteria2://pass-hysteria-hop@tls.example.com:20000-20002?peer=tls.example.com&insecure=0&sni=tls.example.com&alpn=h3#tls-hysteria-hop-user" "${SUBSCRIBE_CAPTURE_DIR}/default/tls"
grep -qx "    ports: 20000-20002" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls"
if grep -q 'mport' "${SUBSCRIBE_CAPTURE_DIR}/default/tls" "${SUBSCRIBE_CAPTURE_DIR}/screen.log"; then
    return 1
fi

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
tuicAlgorithm="bbr"
defaultBase64Code tuic 9443 tls-tuic-user uuid-tuic_pass-tuic "" ""
grep -qxF "tuic://uuid-tuic:pass-tuic@tls.example.com:9443?congestion_control=bbr&alpn=h3&sni=tls.example.com&udp_relay_mode=native&allow_insecure=0#tls-tuic-user" "${SUBSCRIBE_CAPTURE_DIR}/default/tls"
grep -qx "    server: tls.example.com" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls"
grep -qx "    udp-relay-mode: native" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls"
grep -qx "    disable-sni: false" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls"
grep -qx "    reduce-rtt: false" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls"
grep -qx "    sni: tls.example.com" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls"
jq -e '.[0].type == "tuic" and .[0].server == "tls.example.com" and .[0].tls.server_name == "tls.example.com"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null
jq -e '.[0].uuid == "uuid-tuic" and .[0].password == "pass-tuic" and .[0].congestion_control == "bbr" and .[0].udp_relay_mode == "native" and .[0].zero_rtt_handshake == false and .[0].tls.alpn[0] == "h3"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code naive 443 tls-naive-user pass-naive "" ""
grep -qxF "naive+https://tls-naive-user:pass-naive@tls.example.com:443?padding=true#tls-naive-user" "${SUBSCRIBE_CAPTURE_DIR}/default/tls"
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls" ]]
jq -e '. == []' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null
unset REGRESSION_ECHO_LOG
}

runSubscriptionGroupStateRegression() {
    ensureSubscriptionGroupsState
    jq -e '.version == 2 and .active_group == "default" and (.groups | length == 1)' "$(subscriptionGroupsFile)" >/dev/null

    addSubscriptionSourceState ip-edge "IP Edge" 203.0.113.10 39778
    jq -e '.groups[0].sources[] | select(.id == "ip-edge" and .scheme == "wireguard" and .transport == "wireguard" and .host == "203.0.113.10" and .port == 39778)' "$(subscriptionGroupsFile)" >/dev/null
    removeSubscriptionSourceState ip-edge

    local credential decodedCredential invalidCredential oldWireGuardDir selfRefHost
    credential=$(subscriptionWireGuardCredentialEncode controlled '{"address":"10.77.0.2/24","public_key":"pubkey-abc","control_port":39778,"token":"token-abc"}')
    decodedCredential=$(subscriptionWireGuardCredentialDecode "${credential}")
    jq -e '.kind == "controlled" and .address == "10.77.0.2/24" and .control_port == 39778 and .token == "token-abc"' <<<"${decodedCredential}" >/dev/null
    if subscriptionWireGuardCredentialDecode "remote.example.com:39778:token-abc" >/dev/null 2>&1; then
        return 1
    fi
    invalidCredential=$(subscriptionWireGuardCredentialEncode controlled '{"address":"10.77.0.2/24","public_key":"pubkey-abc","control_port":39778}')
    if subscriptionWireGuardCredentialDecode "${invalidCredential}" >/dev/null 2>&1; then
        return 1
    fi
    invalidCredential=$(subscriptionWireGuardCredentialEncode controlled '{"address":"10.77.999.2/24","public_key":"pubkey-abc","control_port":39778,"token":"token-abc"}')
    if subscriptionWireGuardCredentialDecode "${invalidCredential}" >/dev/null 2>&1; then
        return 1
    fi
    invalidCredential=$(subscriptionWireGuardCredentialEncode controlled '{"address":"10.77.0.2/24","public_key":"pubkey-abc","control_port":70000,"token":"token-abc"}')
    if subscriptionWireGuardCredentialDecode "${invalidCredential}" >/dev/null 2>&1; then
        return 1
    fi

    cat >"$(subscriptionGroupsFile)" <<'JSON'
{
  "version": 1,
  "active_group": "edge-group",
  "groups": [
    {
      "id": "edge-group",
      "name": "Edge Group",
      "sources": [
        {"id": "edge", "name": "Edge", "scheme": "https", "host": "example.com", "port": "443", "enabled": true, "sync_status": "failed", "last_sync_error": {"type": "unreachable", "message": "old"}}
      ],
      "user_groups": [
        {"id": "team-a", "name": "Team A", "enabled": true, "allowed_sources": ["edge"], "traffic_limit_gb": "1", "uuid": "11111111-1111-1111-1111-111111111111"}
      ],
      "sync": {"enabled": true},
      "traffic": {"user_groups": {"team-a": {"upload": 1, "download": 2, "sources": {"edge": {"upload": 1, "download": 2}}}}, "sources": {"edge": {"upload": 1, "download": 2}}, "admin": {"sources": {"edge": {"upload": 0, "download": 0}}}}
    }
  ]
}
JSON

    ensureSubscriptionGroupsState
    jq -e '
      .version == 2 and
      .active_group == "edge-group" and
      (.groups[0].sync.remote_enabled == true) and
      (.groups[0].sync.quota_auto_apply == false) and
      any(.groups[0].sources[]; .id == "main" and .role == "main") and
      any(.groups[0].sources[]; .id == "edge" and .port == 443) and
      (.groups[0].user_groups[0].traffic_limit_gb == 1)
    ' "$(subscriptionGroupsFile)" >/dev/null

    (
        local summaryOutput
        menuLine() { printf 'menu:%s\n' "$*"; }
        menuClose() { return 0; }
        summaryOutput=$(showSubscriptionGroupsStateSummary)
        [[ "${summaryOutput}" == *"当前组：Edge Group(edge-group)"* ]]
        [[ "${summaryOutput}" == *"分享订阅：1 个，启用 1 个"* ]]
        [[ "${summaryOutput}" == *"服务器源：2 个，启用远端 1 个"* ]]
    )

    (
        local resetRoot="${TMP_DIR}/subscription-groups-reset-failure"
        local resetGroupsDir="${resetRoot}/groups"
        local resetStateFile="${resetGroupsDir}/groups.json"
        local resetErrorLog="${resetRoot}/error.log"
        local resetCurrentBackup
        local resetBeforeSnapshot
        local resetStatus
        local oldGroupsDir="${PADM_SUBSCRIPTION_GROUPS_DIR:-}"
        local oldTmpDir="${TMPDIR:-}"

        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/subscription/state_maintenance.sh"
        export PADM_SUBSCRIPTION_GROUPS_DIR="${resetGroupsDir}"
        TMPDIR="${resetRoot}"
        REGRESSION_ERROR_CARD_LOG="${resetErrorLog}"
        mkdir -p "${resetGroupsDir}"
        cat >"${resetStateFile}" <<'JSON'
{"version":2,"active_group":"legacy","groups":[{"id":"legacy","name":"Legacy","admin":{"id":"admin","name":"我的订阅","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"本机","role":"main","transport":"local","scheme":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["main"],"traffic_limit_gb":0,"token":"","uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
        resetBeforeSnapshot=$(<"${resetStateFile}")
        resetCurrentBackup="${resetGroupsDir}/backups/groups-current.json"

        showSubscriptionGroupsStateSummary() { return 0; }
        statusCard() { return 0; }
        successCard() { return 0; }
        autoRead() {
            local targetVar=$3
            printf -v "${targetVar}" '%s' "yes"
        }
        createSubscriptionGroupsBackup() {
            mkdir -p "${resetGroupsDir}/backups" || return 1
            cp "${resetStateFile}" "${resetCurrentBackup}" || return 1
            printf '%s\n' "${resetCurrentBackup}"
        }
        migrateSubscriptionGroupsState() {
            return 1
        }

        : >"${resetErrorLog}"
        set +e
        resetSubscriptionGroupsStateMenu >/dev/null 2>&1
        resetStatus=$?
        set -e
        unset -f showSubscriptionGroupsStateSummary
        unset -f statusCard
        unset -f successCard
        unset -f autoRead
        unset -f createSubscriptionGroupsBackup
        unset -f migrateSubscriptionGroupsState
        [[ "${resetStatus}" == "1" ]]
        [[ "$(<"${resetStateFile}")" == "${resetBeforeSnapshot}" ]]
        grep -q '订阅状态重建失败，已恢复旧状态' "${resetErrorLog}"
        [[ -f "${resetCurrentBackup}" ]]
        if find "${resetGroupsDir}" -maxdepth 1 -type f -name '.groups.json.reset.*' | grep -q .; then
            return 1
        fi

        if [[ -n "${oldGroupsDir}" ]]; then export PADM_SUBSCRIPTION_GROUPS_DIR="${oldGroupsDir}"; else unset PADM_SUBSCRIPTION_GROUPS_DIR; fi
        if [[ -n "${oldTmpDir}" ]]; then TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    )

    if ! true >/dev/null 2>&1; then
        return 1
    fi
    if ! true >/dev/null 2>&1; then
        return 1
    fi

    addSubscriptionSourceState remote-edge remote-edge "10.77.0.2" 39778
    setSubscriptionSourceCredential remote-edge "10.77.0.2" 39778 "token-abc"
    jq -e '.groups[0].sources[] | select(.id == "remote-edge" and .scheme == "wireguard" and .transport == "wireguard" and .host == "10.77.0.2" and .port == 39778 and .control_token == "token-abc")' "$(subscriptionGroupsFile)" >/dev/null
    setSubscriptionSourceCredential remote-edge "10.77.0.3" 48779 "token-def"
    jq -e '.groups[0].sources[] | select(.id == "remote-edge" and .scheme == "wireguard" and .transport == "wireguard" and .host == "10.77.0.3" and .port == 48779 and .control_token == "token-def")' "$(subscriptionGroupsFile)" >/dev/null

    subscriptionGroupsStateWrite --arg groupId "$(activeSubscriptionGroupId)" --arg id edge --argjson enabled false '
      .groups |= map(if .id == $groupId then
        .sources |= map(if .id == $id and .role != "main" then .enabled = $enabled else . end)
      else . end)'
    jq -e '.groups[0].sources[] | select(.id == "edge" and .enabled == false)' "$(subscriptionGroupsFile)" >/dev/null
    subscriptionGroupsStateWrite --arg groupId "$(activeSubscriptionGroupId)" --arg id main --argjson enabled false '
      .groups |= map(if .id == $groupId then
        .sources |= map(if .id == $id and .role != "main" then .enabled = $enabled else . end)
      else . end)'
    jq -e '.groups[0].sources[] | select(.id == "main" and .enabled == true)' "$(subscriptionGroupsFile)" >/dev/null
    clearSubscriptionSourceSyncError edge
    jq -e '(.groups[0].sources[] | select(.id == "edge") | has("last_sync_error")) | not' "$(subscriptionGroupsFile)" >/dev/null
    removeSubscriptionSourceState edge
    jq -e '(.groups[0].sources | map(.id) | index("edge") | not) and (.groups[0].traffic.sources | has("edge") | not) and (.groups[0].traffic.user_groups["team-a"].sources | has("edge") | not)' "$(subscriptionGroupsFile)" >/dev/null

    subscriptionGroupsStateWrite '
      .groups[0].user_groups[0].enabled = true |
      .groups[0].user_groups[0].traffic_limit_gb = 1 |
      .groups[0].traffic.admin = {upload:2097152, download:1048576, sources:{main:{upload:2097152, download:1048576, updated_at:"2026-06-10 10:00:00"}}} |
      .groups[0].traffic.sources = {main:{upload:2097152, download:1048576, updated_at:"2026-06-10 10:00:00"}, "remote-edge":{upload:1048576, download:0, updated_at:"2026-06-10 10:01:00"}} |
      .groups[0].traffic.user_groups["team-a"] = {upload: 1073741824, download: 1, sources:{main:{upload:1073741824, download:1}}}
    '
    (
        local trafficOutput
        menuLine() { printf 'menu:%s\n' "$*"; }
        menuClose() { return 0; }
        trafficOutput=$(showAdminSubscriptionTraffic)
        [[ "${trafficOutput}" == *"总上传：2 MB"* ]]
        [[ "${trafficOutput}" == *"总下载：1 MB"* ]]
        [[ "${trafficOutput}" == *"来源数：1"* ]]
        trafficOutput=$(showSubscriptionSourcesTraffic)
        [[ "${trafficOutput}" == *"服务器数：2"* ]]
        [[ "${trafficOutput}" == *"总上传：3 MB"* ]]
        [[ "${trafficOutput}" == *"总下载：1 MB"* ]]
        [[ "${trafficOutput}" == *"最近更新：2026-06-10 10:01:00"* ]]
    )
    subscriptionQuotaDryRunPlan | jq -e 'length == 1 and .[0].id == "team-a" and .[0].limit_gb == 1 and .[0].percent >= 100 and .[0].action == "disable-and-remove-local-account"' >/dev/null
    if applySubscriptionQuotaPlan '{bad-json' 2>/dev/null; then
        return 1
    fi
    if applySubscriptionQuotaPlan '[{"id":"","action":"disable-and-remove-local-account"}]' 2>/dev/null; then
        return 1
    fi
    if applySubscriptionQuotaPlan '[{"id":"missing","action":"disable-and-remove-local-account"}]' 2>/dev/null; then
        return 1
    fi
    if subscriptionSyncApplyAccountPlan '{bad-json' 2>/dev/null; then
        return 1
    fi
    if subscriptionSyncApplyAccountPlan '{"create":["sub_team_a"],"remove":[null]}' 2>/dev/null; then
        return 1
    fi
    applySubscriptionQuotaPlan "$(subscriptionQuotaDryRunPlan)"
    jq -e '.groups[0].user_groups[] | select(.id == "team-a" and .enabled == false)' "$(subscriptionGroupsFile)" >/dev/null
    subscriptionGroupsStateWrite '.groups[0].user_groups[0].enabled = true'
    (
        local quotaMenuOutput
        local quotaMenuStatus
        menuLine() { printf 'menu:%s\n' "$*"; }
        menuClose() { return 0; }
        subscriptionSyncApplyAccountPlanTransaction() {
            return 42
        }
        set +e
        quotaMenuOutput=$(executeSubscriptionQuotaPlanMenu <<<"yes" 2>/dev/null)
        quotaMenuStatus=$?
        set -e
        if [[ "${quotaMenuStatus}" -eq 0 ]]; then
            return 1
        fi
        [[ "${quotaMenuOutput}" == *"待处理订阅：1"* ]]
        [[ "${quotaMenuOutput}" == *"动作：停用超额订阅并移除本机托管账号"* ]]
    )
    (
        local quotaTxRoot="${TMP_DIR}/subscription-quota-transaction"
        local quotaTxPlan
        local quotaTxStatus
        mkdir -p "${quotaTxRoot}/groups"
        export PADM_SUBSCRIPTION_GROUPS_DIR="${quotaTxRoot}/groups"
        cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":1,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{"team-a":{"upload":1073741824,"download":1,"sources":{"main":{"upload":1073741824,"download":1}}}},"sources":{"main":{"upload":2097152,"download":1048576,"updated_at":"2026-06-10 10:00:00"}}}}]}
JSON
        quotaTxPlan=$(subscriptionQuotaDryRunPlan)
        subscriptionSyncApplyAccountPlanTransaction() {
            return 1
        }
        set +e
        applySubscriptionQuotaPlanTransaction "${quotaTxPlan}"
        quotaTxStatus=$?
        set -e
        [[ "${quotaTxStatus}" == "1" ]]
        jq -e '.groups[0].user_groups[] | select(.id == "team-a" and .enabled == true)' "$(subscriptionGroupsFile)" >/dev/null
        [[ "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR}" == *"已恢复旧订阅状态"* ]]
        if find "${quotaTxRoot}/groups/backups" -maxdepth 1 -type f -name 'groups-*.json' | grep -q .; then
            return 1
        fi
    )
    (
        local quotaPartialRoot="${TMP_DIR}/subscription-quota-partial-state-failure"
        local quotaPartialPlan='[{"id":"team-a","action":"disable-and-remove-local-account"},{"id":"team-b","action":"disable-and-remove-local-account"}]'
        local quotaPartialStatus
        mkdir -p "${quotaPartialRoot}/groups"
        export PADM_SUBSCRIPTION_GROUPS_DIR="${quotaPartialRoot}/groups"
        cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":1,"uuid":"11111111-1111-1111-1111-111111111111"},{"id":"team-b","name":"Team B","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":1,"uuid":"22222222-2222-2222-2222-222222222222"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
        setUserSubscriptionEnabled() {
            local id=$1
            local enabled=$2
            if [[ "${id}" == "team-b" ]]; then
                return 1
            fi
            subscriptionGroupsStateWrite --arg groupId "default" --arg id "${id}" --argjson enabled "${enabled}" '.groups |= map(if .id == $groupId then .user_groups |= map(if .id == $id then .enabled = $enabled else . end) else . end)'
        }
        set +e
        applySubscriptionQuotaPlanTransaction "${quotaPartialPlan}"
        quotaPartialStatus=$?
        set -e
        [[ "${quotaPartialStatus}" == "1" ]]
        jq -e '.groups[0].user_groups[] | select(.id == "team-a" and .enabled == true)' "$(subscriptionGroupsFile)" >/dev/null
        jq -e '.groups[0].user_groups[] | select(.id == "team-b" and .enabled == true)' "$(subscriptionGroupsFile)" >/dev/null
        [[ "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR}" == *"停用超额分享订阅失败"* ]]
        if find "${quotaPartialRoot}/groups/backups" -maxdepth 1 -type f -name 'groups-*.json' | grep -q .; then
            return 1
        fi
    )
    (
        subscriptionSyncPlanFromAccounts() {
            jq -n '{create:[], remove:["sub_team_a"]}'
        }
        subscriptionSyncPlan | jq -e '.remove | index("sub_team_a")' >/dev/null
    )
    local oldConfigPath="${configPath:-}"
    local oldSingBoxConfigPath="${singBoxConfigPath:-}"
    local syncConfigRoot="${TMP_DIR}/subscription-sync-config"
    configPath="${syncConfigRoot}/xray/"
    singBoxConfigPath="${syncConfigRoot}/sing-box/"
    mkdir -p "${configPath}" "${singBoxConfigPath}"
    cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_team_a-main"},{"email":"sub_team_b-main"}]}}]}
JSON
    cat >"${singBoxConfigPath}06_hysteria2_inbounds.json" <<'JSON'
{"inbounds":[{"users":[{"name":"sub_team_a-main"},{"username":"sub_team_b-main"}]}]}
JSON
    subscriptionSyncConfiguredManagedUsers | jq -R -e -s 'split("\n") | map(select(length > 0)) | sort == ["sub_team_a", "sub_team_b"]' >/dev/null
    subscriptionSyncPlanFromAccounts $'sub_team_a' | jq -e '.create == [] and .remove == ["sub_team_b"]' >/dev/null
    printf '{bad-json' >"${configPath}99_broken_inbounds.json"
    set +e
    subscriptionSyncPlanFromAccounts $'sub_team_a' >/dev/null 2>&1
    local brokenPlanStatus=$?
    set -e
    [[ "${brokenPlanStatus}" -ne 0 ]]
    rm -f "${configPath}99_broken_inbounds.json"
    configPath="${oldConfigPath}"
    singBoxConfigPath="${oldSingBoxConfigPath}"
    (
        runSubscriptionGroupSync() {
            return 23
        }
        set +e
        runSubscriptionGroupSyncCron
        local cronStatus=$?
        set -e
        [[ "${cronStatus}" -eq 23 ]]
    )

    currentHost="self.example.com"
    subscribeDomain="self.example.com"
    subscribePort=39778
    oldWireGuardDir="${PADM_WIREGUARD_CONTROL_DIR:-}"
    PADM_WIREGUARD_CONTROL_DIR="${TMP_DIR}/subscription-state-wireguard"
    mkdir -p "$(subscriptionWireGuardDir)"
    cat >"$(subscriptionWireGuardStateFile)" <<'JSON'
{"enabled":true,"role":"main","address":"10.77.0.1/24","peers":[]}
JSON
    selfRefHost=$(subscriptionWireGuardReadState | jq -r '.address // empty')
    selfRefHost=$(subscriptionWireGuardAddressHost "${selfRefHost}")
    subscriptionGroupsStateWrite --arg selfRefHost "${selfRefHost}" '
      .groups[0].sources |= map(if .id == "remote-edge" then .enabled = false else . end) |
      .groups[0].sources += [{"id":"self-ref","name":"SelfRef","role":"secondary","scheme":"wireguard","transport":"wireguard","host":$selfRefHost,"port":39778,"enabled":true,"sync_status":"pending","control_token":"token"}] |
      .groups[0].user_groups = (.groups[0].user_groups | map(if .id == "team-a" then .allowed_sources = ["self-ref"] else . end))
    '
    subscriptionRemoteControlRequest() {
        return 19
    }
    subscriptionRemoteSyncPlan | jq -e '.[] | select(.source_id == "self-ref" and .status == "self_reference" and .error_detail.type == "self_reference")' >/dev/null
    runSubscriptionRemoteSync | jq -e '.[] | contains("self-ref")' >/dev/null
    subscriptionGroupsStateRead -e '.groups[0].sources[] | select(.id == "self-ref" and .sync_status == "failed" and .last_sync_error.type == "self_reference")' >/dev/null
    if [[ -n "${oldWireGuardDir}" ]]; then PADM_WIREGUARD_CONTROL_DIR="${oldWireGuardDir}"; else unset PADM_WIREGUARD_CONTROL_DIR; fi
    local stateSnapshot badBackup legacyBackup menuBackup
    stateSnapshot=$(<"$(subscriptionGroupsFile)")
    if subscriptionGroupsStateWrite '.groups = "broken" | .dangling = ' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"$(subscriptionGroupsFile)")" == "${stateSnapshot}" ]]
    [[ ! -e "$(subscriptionGroupsFile).tmp" ]]
    [[ ! -e "$(subscriptionGroupsFile).tmp.commit" ]]

    badBackup="${TMP_DIR}/bad-groups-backup.json"
    printf '{bad json\n' >"${badBackup}"
    if restoreSubscriptionGroupsBackup "${badBackup}" 2>/dev/null; then
        return 1
    fi
    [[ "$(<"$(subscriptionGroupsFile)")" == "${stateSnapshot}" ]]
    [[ ! -e "$(subscriptionGroupsFile).restore.tmp" ]]

    legacyBackup="${TMP_DIR}/legacy-groups-backup.json"
    cat >"${legacyBackup}" <<'JSON'
{"version":1,"active_group":"legacy","groups":[{"id":"legacy","name":"Legacy","sources":[],"user_groups":[],"sync":{"enabled":true},"traffic":{}}]}
JSON
    restoreSubscriptionGroupsBackup "${legacyBackup}"
    jq -e '.version == 2 and .active_group == "legacy" and any(.groups[0].sources[]; .role == "main") and (.groups[0].sync.remote_enabled == true)' "$(subscriptionGroupsFile)" >/dev/null

    menuBackup=$(createSubscriptionGroupsBackup)
    subscriptionGroupsStateWrite '.active_group = "changed" | .groups[0].id = "changed" | .groups[0].name = "Changed"'
    (
        local menuOutput
        autoRead() {
            local targetVar=$3
            local input=
            IFS= read -r input || input=
            printf -v "${targetVar}" '%s' "${input}"
        }
        menuLine() { printf 'menu:%s\n' "$*"; }
        menuClose() { printf 'menu:close\n'; }
        menuOutput=$(printf '%s\nyes\n' "${menuBackup}" | restoreSubscriptionGroupsBackupMenu)
        [[ "${menuOutput}" == *"menu:"* ]]
    )
    jq -e '.version == 2 and .active_group == "legacy" and .groups[0].id == "legacy"' "$(subscriptionGroupsFile)" >/dev/null
}

runSubscriptionSyncTempDirRegression() (
    local oldTmpDir="${TMPDIR:-}"
    local oldConfigPath="${configPath:-}"
    local oldSingBoxConfigPath="${singBoxConfigPath:-}"
    local oldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
    local oldPublicDir="${PADM_SUBSCRIBE_DIR:-}"
    local tmpRoot="${TMP_DIR}/subscription-sync-tmp"
    local syncConfigRoot="${TMP_DIR}/subscription-sync-tempdir-config"
    local localDir="${TMP_DIR}/subscription-sync-tempdir-local"
    local publicDir="${TMP_DIR}/subscription-sync-tempdir-public"
    local backupDir
    local outputBackupDir

    mkdir -p "${tmpRoot}" "${syncConfigRoot}/xray" "${syncConfigRoot}/sing-box" "${localDir}/default" "${publicDir}/default"
    TMPDIR="${tmpRoot}"
    configPath="${syncConfigRoot}/xray/"
    singBoxConfigPath="${syncConfigRoot}/sing-box/"
    cat >"${configPath}01_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_team_a-main"}]}}]}
JSON

    backupDir=$(subscriptionSyncCreateConfigBackups)
    [[ "${backupDir}" == "${tmpRoot}"/padm-subscription-sync-backup.* ]]
    [[ -f "${backupDir}/manifest" ]]
    padmRemoveCleanupPath "${backupDir}"

    export PADM_SUBSCRIBE_LOCAL_DIR="${localDir}"
    export PADM_SUBSCRIBE_DIR="${publicDir}"
    printf 'local\n' >"${localDir}/default/user"
    printf 'public\n' >"${publicDir}/default/user"
    outputBackupDir=$(subscriptionSyncCreateSubscribeOutputBackups)
    [[ "${outputBackupDir}" == "${tmpRoot}"/padm-subscription-output-backup.* ]]
    [[ -f "${outputBackupDir}/local.exists" && -f "${outputBackupDir}/public.exists" ]]
    padmRemoveCleanupPath "${outputBackupDir}"

    if find "${tmpRoot}" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
        return 1
    fi
    configPath="${oldConfigPath}"
    singBoxConfigPath="${oldSingBoxConfigPath}"
    if [[ -n "${oldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${oldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
    if [[ -n "${oldPublicDir}" ]]; then export PADM_SUBSCRIBE_DIR="${oldPublicDir}"; else unset PADM_SUBSCRIBE_DIR; fi
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runSubscriptionSyncRollbackFailureRegression() (
    local root="${TMP_DIR}/subscription-sync-rollback-failure"
    local oldConfigPath="${configPath:-}"
    local oldSingBoxConfigPath="${singBoxConfigPath:-}"
    local oldTmpDir="${TMPDIR:-}"
    local targetFile="${root}/xray/02_VLESS_TCP_inbounds.json"
    local rc backupDirs=()

    mkdir -p "${root}/xray" "${root}/tmp"
    configPath="${root}/xray/"
    singBoxConfigPath="${root}/xray/"
    TMPDIR="${root}/tmp"
    coreInstallType=1
    ctlPath=
    cat >"${targetFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_old-main"}]}}]}
JSON
    eval "$(declare -f subscriptionSyncApplyAccountPlan | sed '1s/^subscriptionSyncApplyAccountPlan/originalSubscriptionSyncApplyAccountPlan/')"

    initXrayClients() {
        jq -n --arg email "$3-main" '[{email:$email}]'
    }
    subscriptionSyncGenerateUUID() {
        printf '99999999-9999-9999-9999-999999999999\n'
    }
    subscriptionSyncApplyAccountPlan() {
        originalSubscriptionSyncApplyAccountPlan "$@"
        return 1
    }
    cp() {
        if [[ "$1" == "-p" && "$2" == "${root}/tmp"/padm-subscription-sync-backup.*/*.json && "$3" == "${targetFile}" ]]; then
            return 1
        fi
        command cp "$@"
    }

    set +e
    subscriptionSyncApplyAccountPlanTransaction '{"create":["sub_new"],"remove":[]}'
    rc=$?
    set -e
    unset -f cp subscriptionSyncApplyAccountPlan initXrayClients subscriptionSyncGenerateUUID

    [[ "${rc}" == "1" ]]
    jq -e '.inbounds[0].settings.clients[0].email == "sub_new-main"' "${targetFile}" >/dev/null
    [[ "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR}" == *"配置恢复失败"* ]]
    [[ "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR}" == *"备份目录:"* ]]
    mapfile -t backupDirs < <(find "${root}/tmp" -maxdepth 1 -type d -name 'padm-subscription-sync-backup.*' -print)
    [[ "${#backupDirs[@]}" == "1" ]]
    [[ -f "${backupDirs[0]}/manifest" ]]
    grep -q "${targetFile}" "${backupDirs[0]}/manifest"
    if find "${root}/xray" -name '*.sync.*' | grep -q .; then
        return 1
    fi

    (
        local restoreDirRoot="${TMP_DIR}/subscription-sync-restore-dir-failure"
        local restoreDirTarget="${restoreDirRoot}/subscribe_local"
        local restoreDirBackup="${restoreDirRoot}/backup"
        local restoreStatus
        mkdir -p "${restoreDirTarget}/default" "${restoreDirTarget}/clashMeta" "${restoreDirBackup}/local/default" "${restoreDirBackup}/local/clashMeta"
        printf 'current default\n' >"${restoreDirTarget}/default/existing"
        printf 'current clash\n' >"${restoreDirTarget}/clashMeta/existing"
        printf 'backup default\n' >"${restoreDirBackup}/local/default/existing"
        printf 'backup clash\n' >"${restoreDirBackup}/local/clashMeta/existing"
        printf 'dir\n' >"${restoreDirBackup}/local.exists"
        cp() {
            if [[ "$1" == "-a" && "$2" == "${restoreDirBackup}/local/." && "$3" == "${restoreDirRoot}"/.restore-local.*"/" ]]; then
                return 1
            fi
            command cp "$@"
        }
        set +e
        subscriptionSyncRestoreBackupPath "${restoreDirTarget}" "${restoreDirBackup}" local
        restoreStatus=$?
        set -e
        unset -f cp
        [[ "${restoreStatus}" == "1" ]]
        [[ "$(<"${restoreDirTarget}/default/existing")" == "current default" ]]
        [[ "$(<"${restoreDirTarget}/clashMeta/existing")" == "current clash" ]]
        if find "${restoreDirRoot}" -maxdepth 1 -type d \( -name '.restore-local.*' -o -name '.restore-old-local.*' \) | grep -q .; then
            return 1
        fi
    )

    (
        local reloadRoot="${TMP_DIR}/subscription-sync-reload-rollback"
        local reloadTargetFile="${reloadRoot}/xray/02_VLESS_TCP_inbounds.json"
        local reloadLog="${reloadRoot}/reload.log"
        local reloadOriginalContent
        local reloadStatus

        mkdir -p "${reloadRoot}/xray" "${reloadRoot}/tmp"
        configPath="${reloadRoot}/xray/"
        singBoxConfigPath="${reloadRoot}/xray/"
        TMPDIR="${reloadRoot}/tmp"
        coreInstallType=1
        cat >"${reloadTargetFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_old-main"}]}}]}
JSON
        reloadOriginalContent=$(<"${reloadTargetFile}")

        subscriptionSyncApplyAccountPlan() {
            originalSubscriptionSyncApplyAccountPlan "$@"
        }
        reloadCore() {
            printf 'reload\n' >>"${reloadLog}"
            return 1
        }

        set +e
        applySubscriptionQuotaPlanAccounts '[{"id":"team-a","action":"disable-and-remove-local-account"}]'
        reloadStatus=$?
        set -e
        [[ "${reloadStatus}" == "1" ]]
        [[ "$(<"${reloadTargetFile}")" == "${reloadOriginalContent}" ]]
        [[ "$(wc -l <"${reloadLog}" | tr -d ' ')" == "2" ]]
        [[ "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR}" == *"核心重载失败"* ]]
        [[ "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR}" == *"恢复旧配置后核心重载仍失败"* ]]
        if find "${reloadRoot}/tmp" -maxdepth 1 -type d -name 'padm-subscription-sync-backup.*' | grep -q .; then
            return 1
        fi
    )

    (
        local syncRoot="${TMP_DIR}/subscription-group-sync-apply-failure"
        local syncConfigFile="${syncRoot}/xray/02_VLESS_TCP_inbounds.json"
        local syncLocalFile="${syncRoot}/subscribe_local/default/user"
        local syncPublicFile="${syncRoot}/subscribe/default/user"
        local statusLog="${syncRoot}/status.log"
        local resultStatus="${syncRoot}/mark-status.log"
        local resultFailures="${syncRoot}/mark-failures.log"
        local originalConfig
        local syncStatus

        mkdir -p "${syncRoot}/xray" "${syncRoot}/subscribe_local/default" "${syncRoot}/subscribe/default" "${syncRoot}/groups" "${syncRoot}/tmp"
        configPath="${syncRoot}/xray/"
        singBoxConfigPath="${syncRoot}/xray/"
        export PADM_SUBSCRIPTION_GROUPS_DIR="${syncRoot}/groups"
        export PADM_SUBSCRIBE_LOCAL_DIR="${syncRoot}/subscribe_local"
        export PADM_SUBSCRIBE_DIR="${syncRoot}/subscribe"
        TMPDIR="${syncRoot}/tmp"
        cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge-a","name":"Edge A","role":"secondary","scheme":"https","host":"edge.example.com","port":443,"enabled":true,"sync_status":"pending","control_token":"token-a"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
        cat >"${syncConfigFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_old-main"}]}}]}
JSON
        printf 'old-local\n' >"${syncLocalFile}"
        printf 'old-public\n' >"${syncPublicFile}"
        originalConfig=$(<"${syncConfigFile}")

        subscriptionGroupRemoteSyncEnabled() { return 0; }
        collectSubscriptionTraffic() { return 0; }
        readInstallType() { return 0; }
        readInstallProtocolType() { return 0; }
        readConfigHostPathUUID() { return 0; }
        subscriptionSyncPlan() {
            printf '{"create":["sub_team_a"],"remove":[]}'
        }
        subscriptionSyncApplyAccountPlanTransaction() {
            SUBSCRIPTION_SYNC_TRANSACTION_ERROR="本机同步计划应用失败"
            return 1
        }
        subscriptionSyncMarkResult() {
            printf '%s\n' "$1" >"${resultStatus}"
            printf '%s\n' "$2" >"${resultFailures}"
            return 0
        }
        statusCard() { printf '%s\n' "$*" >"${statusLog}"; }

        set +e
        runSubscriptionGroupSync
        syncStatus=$?
        set -e
        [[ "${syncStatus}" == "1" ]]
        [[ "$(<"${syncConfigFile}")" == "${originalConfig}" ]]
        [[ "$(<"${syncLocalFile}")" == "old-local" ]]
        [[ "$(<"${syncPublicFile}")" == "old-public" ]]
        grep -q '本机同步计划应用失败' "${resultFailures}"
        grep -q '本机同步未完成，已跳过被控服务器同步' "${resultFailures}"
        grep -q '本机同步未完全完成' "${statusLog}"
        grep -qx 'partial' "${resultStatus}"
        if find "${syncRoot}/tmp" -maxdepth 1 -type d \( -name 'padm-subscription-sync-backup.*' -o -name 'padm-subscription-output-backup.*' \) | grep -q .; then
            return 1
        fi
    )

    (
        local syncRoot="${TMP_DIR}/subscription-group-sync-reconcile-rollback"
        local syncConfigFile="${syncRoot}/xray/02_VLESS_TCP_inbounds.json"
        local syncLocalFile="${syncRoot}/subscribe_local/default/user"
        local syncPublicFile="${syncRoot}/subscribe/default/user"
        local reconcileLog="${syncRoot}/reconcile.log"
        local statusLog="${syncRoot}/status.log"
        local resultStatus="${syncRoot}/mark-status.log"
        local resultFailures="${syncRoot}/mark-failures.log"
        local originalConfig
        local syncStatus

        mkdir -p "${syncRoot}/xray" "${syncRoot}/subscribe_local/default" "${syncRoot}/subscribe/default" "${syncRoot}/groups" "${syncRoot}/tmp"
        configPath="${syncRoot}/xray/"
        singBoxConfigPath="${syncRoot}/xray/"
        export PADM_SUBSCRIPTION_GROUPS_DIR="${syncRoot}/groups"
        export PADM_SUBSCRIBE_LOCAL_DIR="${syncRoot}/subscribe_local"
        export PADM_SUBSCRIBE_DIR="${syncRoot}/subscribe"
        TMPDIR="${syncRoot}/tmp"
        cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge-a","name":"Edge A","role":"secondary","scheme":"https","host":"edge.example.com","port":443,"enabled":true,"sync_status":"pending","control_token":"token-a"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
        cat >"${syncConfigFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_old-main"}]}}]}
JSON
        printf 'old-local\n' >"${syncLocalFile}"
        printf 'old-public\n' >"${syncPublicFile}"
        originalConfig=$(<"${syncConfigFile}")

        subscriptionGroupRemoteSyncEnabled() { return 0; }
        collectSubscriptionTraffic() { return 0; }
        readInstallType() { return 0; }
        readInstallProtocolType() { return 0; }
        readConfigHostPathUUID() { return 0; }
        subscriptionSyncPlan() {
            printf '{"create":["sub_team_a"],"remove":[]}'
        }
        subscriptionSyncApplyAccountPlanTransaction() {
            cat >"${syncConfigFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_new-main"}]}}]}
JSON
            return 0
        }
        subscriptionSyncReconcileLocalServices() {
            printf '%s\n' "${1:-<empty>}" >>"${reconcileLog}"
            if [[ -z "${1:-}" ]]; then
                printf 'new-local\n' >"${syncLocalFile}"
                printf 'new-public\n' >"${syncPublicFile}"
                return 1
            fi
            return 0
        }
        subscriptionSyncMarkResult() {
            printf '%s\n' "$1" >"${resultStatus}"
            printf '%s\n' "$2" >"${resultFailures}"
            return 0
        }
        statusCard() { printf '%s\n' "$*" >"${statusLog}"; }

        set +e
        runSubscriptionGroupSync
        syncStatus=$?
        set -e
        [[ "${syncStatus}" == "1" ]]
        [[ "$(<"${syncConfigFile}")" == "${originalConfig}" ]]
        [[ "$(<"${syncLocalFile}")" == "old-local" ]]
        [[ "$(<"${syncPublicFile}")" == "old-public" ]]
        [[ "$(wc -l <"${reconcileLog}" | tr -d ' ')" == "2" ]]
        grep -qx '<empty>' "${reconcileLog}"
        grep -qx 'true' "${reconcileLog}"
        grep -q '本机同步后服务重建失败，已恢复旧配置' "${resultFailures}"
        grep -q '本机同步未完成，已跳过被控服务器同步' "${resultFailures}"
        grep -q '本机同步未完全完成' "${statusLog}"
        grep -qx 'partial' "${resultStatus}"
        if find "${syncRoot}/tmp" -maxdepth 1 -type d \( -name 'padm-subscription-sync-backup.*' -o -name 'padm-subscription-output-backup.*' \) | grep -q .; then
            return 1
        fi
    )

    (
        local syncRoot="${TMP_DIR}/subscription-group-sync-remote-failure"
        local syncConfigFile="${syncRoot}/xray/02_VLESS_TCP_inbounds.json"
        local syncLocalFile="${syncRoot}/subscribe_local/default/user"
        local syncPublicFile="${syncRoot}/subscribe/default/user"
        local remoteLog="${syncRoot}/remote.log"
        local statusLog="${syncRoot}/status.log"
        local resultStatus="${syncRoot}/mark-status.log"
        local resultFailures="${syncRoot}/mark-failures.log"
        local originalConfig
        local syncStatus

        mkdir -p "${syncRoot}/xray" "${syncRoot}/subscribe_local/default" "${syncRoot}/subscribe/default" "${syncRoot}/groups" "${syncRoot}/tmp"
        configPath="${syncRoot}/xray/"
        singBoxConfigPath="${syncRoot}/xray/"
        export PADM_SUBSCRIPTION_GROUPS_DIR="${syncRoot}/groups"
        export PADM_SUBSCRIBE_LOCAL_DIR="${syncRoot}/subscribe_local"
        export PADM_SUBSCRIBE_DIR="${syncRoot}/subscribe"
        TMPDIR="${syncRoot}/tmp"
        cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge-a","name":"Edge A","role":"secondary","scheme":"https","host":"edge.example.com","port":443,"enabled":true,"sync_status":"pending","control_token":"token-a"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
        cat >"${syncConfigFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_old-main"}]}}]}
JSON
        printf 'old-local\n' >"${syncLocalFile}"
        printf 'old-public\n' >"${syncPublicFile}"
        originalConfig=$(<"${syncConfigFile}")

        subscriptionGroupRemoteSyncEnabled() { return 0; }
        collectSubscriptionTraffic() { return 0; }
        readInstallType() { return 0; }
        readInstallProtocolType() { return 0; }
        readConfigHostPathUUID() { return 0; }
        subscriptionSyncPlan() {
            printf '{"create":["sub_team_a"],"remove":[]}'
        }
        subscriptionSyncApplyAccountPlanTransaction() {
            cat >"${syncConfigFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_new-main"}]}}]}
JSON
            return 0
        }
        subscriptionSyncReconcileLocalServices() {
            if [[ -z "${1:-}" ]]; then
                printf 'new-local\n' >"${syncLocalFile}"
                printf 'new-public\n' >"${syncPublicFile}"
            fi
            return 0
        }
        runSubscriptionRemoteSync() {
            printf 'remote\n' >>"${remoteLog}"
            printf '["被控服务器同步失败"]'
        }
        subscriptionSyncMarkResult() {
            printf '%s\n' "$1" >"${resultStatus}"
            printf '%s\n' "$2" >"${resultFailures}"
            return 0
        }
        statusCard() { printf '%s\n' "$*" >"${statusLog}"; }

        set +e
        runSubscriptionGroupSync
        syncStatus=$?
        set -e
        [[ "${syncStatus}" == "1" ]]
        [[ "$(<"${syncConfigFile}")" != "${originalConfig}" ]]
        grep -q 'sub_new-main' "${syncConfigFile}"
        [[ "$(<"${syncLocalFile}")" == "new-local" ]]
        [[ "$(<"${syncPublicFile}")" == "new-public" ]]
        grep -qx 'remote' "${remoteLog}"
        grep -q '被控服务器同步失败' "${resultFailures}"
        grep -q '本机自动同步完成，但被控服务器同步失败，请查看失败列表' "${statusLog}"
        grep -qx 'partial' "${resultStatus}"
        if find "${syncRoot}/tmp" -maxdepth 1 -type d \( -name 'padm-subscription-sync-backup.*' -o -name 'padm-subscription-output-backup.*' \) | grep -q .; then
            return 1
        fi
    )

    configPath="${oldConfigPath}"
    singBoxConfigPath="${oldSingBoxConfigPath}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runSubscriptionSyncReconcileEarlyExitRegression() (
    local root="${TMP_DIR}/subscription-sync-reconcile-early-exit"
    local callLog="${root}/calls.log"
    local rc

    mkdir -p "${root}"

    (
        : >"${callLog}"
        subscribePort=
        reloadCore() {
            printf 'reload\n' >>"${callLog}"
            return 1
        }
        set +e
        subscriptionSyncReconcileLocalServices
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -qx 'reload' "${callLog}"
        [[ "$(wc -l <"${callLog}" | tr -d ' ')" == "1" ]]
    )

    (
        : >"${callLog}"
        subscribePort=
        reloadCore() {
            printf 'reload\n' >>"${callLog}"
            return 0
        }
        readNginxSubscribe() {
            printf 'read\n' >>"${callLog}"
            subscribePort=39778
        }
        installSubscriptionControlService() {
            printf 'install\n' >>"${callLog}"
            return 1
        }
        set +e
        subscriptionSyncReconcileLocalServices
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -qx 'reload' "${callLog}"
        grep -qx 'read' "${callLog}"
        grep -qx 'install' "${callLog}"
        [[ "$(wc -l <"${callLog}" | tr -d ' ')" == "3" ]]
    )

    (
        : >"${callLog}"
        subscribePort=
        reloadCore() {
            printf 'reload\n' >>"${callLog}"
            return 0
        }
        readNginxSubscribe() {
            printf 'read\n' >>"${callLog}"
            subscribePort=39778
        }
        installSubscriptionControlService() {
            printf 'install\n' >>"${callLog}"
            return 0
        }
        ensureSubscriptionControlNginxLocation() {
            printf 'ensure\n' >>"${callLog}"
            return 0
        }
        serviceQueueRestart() {
            printf 'restart:%s\n' "$1" >>"${callLog}"
            return 0
        }
        serviceQueueApply() {
            printf 'apply\n' >>"${callLog}"
            return 1
        }
        set +e
        subscriptionSyncReconcileLocalServices
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -qx 'reload' "${callLog}"
        grep -qx 'read' "${callLog}"
        grep -qx 'install' "${callLog}"
        grep -qx 'ensure' "${callLog}"
        grep -qx 'restart:nginx' "${callLog}"
        grep -qx 'apply' "${callLog}"
        [[ "$(wc -l <"${callLog}" | tr -d ' ')" == "6" ]]
    )
)

runRemoteSubscribeFetchRegression() {
    local publicDir="${TMP_DIR}/remote-subscribe-public"
    local localDir="${TMP_DIR}/remote-subscribe-local"
    local email="user@example.com"
    local emailMd5="hash-user"
    local uniqueFile="${TMP_DIR}/remote-subscribe-unique.txt"
    local oldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
    local oldPublicDir="${PADM_SUBSCRIBE_DIR:-}"
    local oldFakeRemoteSubscribeMode="${PADM_FAKE_REMOTE_SUBSCRIBE_MODE:-}"
    local oldTmpDir="${TMPDIR:-}"
    local remoteTmpRoot="${TMP_DIR}/remote-subscribe-tmp"
    local fetchTmpMarker="${TMP_DIR}/remote-subscribe-fetch-tmpdirs.txt"
    local stageTmpMarker="${TMP_DIR}/remote-subscribe-stage-tmpdirs.txt"
    export PADM_SUBSCRIBE_LOCAL_DIR="${localDir}"
    export PADM_SUBSCRIBE_DIR="${publicDir}"
    TMPDIR="${remoteTmpRoot}"
    rm -rf "${publicDir}" "${localDir}" "${remoteTmpRoot}"
    mkdir -p "${publicDir}/default" "${publicDir}/clashMeta" "${localDir}/sing-box" "${remoteTmpRoot}"
    : >"${fetchTmpMarker}"
    : >"${stageTmpMarker}"

    writeRemoteSubscribeOldOutputs() {
        printf 'old-default\n' >"${publicDir}/default/${emailMd5}"
        printf 'old-clash\n' >"${publicDir}/clashMeta/${emailMd5}"
        printf '[{"tag":"old-local"}]\n' >"${localDir}/sing-box/${email}"
    }

    eval "$(declare -f appendUniqueLines | sed '1s/^appendUniqueLines/originalAppendUniqueLines/')"

    listRemoteSubscribeSources() {
        printf '%s\n' 'remote1.example:443:r1:https' 'remote2.example:443:r2:https' 'remote3.example:443:r3:https'
    }

    printf '%s\n' old same >"${uniqueFile}"
    appendUniqueLines $'same\nnew\nnew' "${uniqueFile}"
    cmp -s "${uniqueFile}" <(printf '%s\n' old same new)

    recordRemoteSubscribeTmpDirs() {
        find "${remoteTmpRoot}" -maxdepth 1 -type d -name 'padm-remote-subscribe-fetch.*' -print >>"${fetchTmpMarker}" 2>/dev/null || true
        find "${remoteTmpRoot}" -maxdepth 1 -type d -name 'padm-remote-subscribe-stage.*' -print >>"${stageTmpMarker}" 2>/dev/null || true
    }

    fetchRemoteSubscribeContent() {
        local url=$1
        recordRemoteSubscribeTmpDirs
        case "${url}" in
        *remote1.example*/s/clashMeta/*)
            printf '%s\n' 'proxies:' '- name: "user@example.com"'
            ;;
        *remote1.example*/s/default/*)
            printf '%s' 'vless://uuid@remote1.example:443#user@example.com' | base64
            ;;
        *remote1.example*/s/sing-box_profiles/*)
            printf '%s\n' '[{"tag":"user@example.com"}]'
            ;;
        *remote2.example*/s/default/*)
            printf '%s\n' 'not-base64'
            ;;
        *remote2.example*/s/sing-box_profiles/*)
            if [[ "${PADM_FAKE_REMOTE_SUBSCRIBE_MODE:-partial}" == "fail-singbox-merge" ]]; then
                printf '%s\n' '[{"tag":"user@example.com_r2"}]'
            else
                printf '%s\n' '{bad json'
            fi
            ;;
        *remote3.example*/s/clashMeta/*)
            printf '%s\n' 'proxies:' '- name: "user@example.com"'
            ;;
        *remote3.example*/s/default/*)
            printf '%s' 'trojan://pass@remote3.example:443#user@example.com-extra' | base64
            ;;
        *remote3.example*/s/sing-box_profiles/*)
            printf '%s\n' '[{"tag":"user@example.com-extra"}]'
            ;;
        *)
            return 1
            ;;
        esac
    }

    writeRemoteSubscribeOldOutputs
    export PADM_FAKE_REMOTE_SUBSCRIBE_MODE=fail-singbox-merge
    printf '{bad local json\n' >"${localDir}/sing-box/${email}"
    if updateRemoteSubscribe "${emailMd5}" "${email}" 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
    [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
    [[ "$(<"${localDir}/sing-box/${email}")" == "{bad local json" ]]
    grep -q . "${fetchTmpMarker}"
    grep -q . "${stageTmpMarker}"
    while IFS= read -r path; do
        [[ -z "${path}" || "${path}" == "${remoteTmpRoot}"/padm-remote-subscribe-fetch.* ]] || return 1
    done <"${fetchTmpMarker}"
    while IFS= read -r path; do
        [[ -z "${path}" || "${path}" == "${remoteTmpRoot}"/padm-remote-subscribe-stage.* ]] || return 1
    done <"${stageTmpMarker}"
    if find "${remoteTmpRoot}" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
        return 1
    fi

    writeRemoteSubscribeOldOutputs
    unset PADM_FAKE_REMOTE_SUBSCRIBE_MODE
    updateRemoteSubscribe "${emailMd5}" "${email}"
    grep -qxF -- '- name: "user@example.com_r1"' "${publicDir}/clashMeta/${emailMd5}"
    grep -qxF 'vless://uuid@remote1.example:443#user@example.com_r1' "${publicDir}/default/${emailMd5}"
    grep -qxF 'trojan://pass@remote3.example:443#user@example.com_r3-extra' "${publicDir}/default/${emailMd5}"
    jq -e '.[0].tag == "old-local" and .[1].tag == "user@example.com_r1" and .[2].tag == "user@example.com_r3-extra"' "${localDir}/sing-box/${email}" >/dev/null
    [[ ! -e "${publicDir}/default/${emailMd5}.tmp" ]]
    [[ ! -e "${publicDir}/clashMeta/${emailMd5}.tmp" ]]
    [[ ! -e "${localDir}/sing-box/${email}.tmp" ]]

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
        if updateRemoteSubscribe "${emailMd5}" "${email}" 2>/dev/null; then
            return 1
        fi
        [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
        [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
        jq -e '.[0].tag == "old-local"' "${localDir}/sing-box/${email}" >/dev/null
        [[ ! -e "${publicDir}/default/${emailMd5}.tmp" ]]
        [[ ! -e "${publicDir}/clashMeta/${emailMd5}.tmp" ]]
        [[ ! -e "${localDir}/sing-box/${email}.tmp" ]]
    )

    updateRemoteSubscribe "${emailMd5}" "${email}"
    [[ "$(grep -cFx -- '- name: "user@example.com_r1"' "${publicDir}/clashMeta/${emailMd5}")" == "1" ]]
    [[ "$(grep -cFx 'vless://uuid@remote1.example:443#user@example.com_r1' "${publicDir}/default/${emailMd5}")" == "1" ]]
    [[ "$(grep -cFx 'trojan://pass@remote3.example:443#user@example.com_r3-extra' "${publicDir}/default/${emailMd5}")" == "1" ]]
    jq -e 'length == 3 and .[0].tag == "old-local" and .[1].tag == "user@example.com_r1" and .[2].tag == "user@example.com_r3-extra"' "${localDir}/sing-box/${email}" >/dev/null

    if [[ -n "${oldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${oldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
    if [[ -n "${oldPublicDir}" ]]; then export PADM_SUBSCRIBE_DIR="${oldPublicDir}"; else unset PADM_SUBSCRIBE_DIR; fi
    if [[ -n "${oldFakeRemoteSubscribeMode}" ]]; then export PADM_FAKE_REMOTE_SUBSCRIBE_MODE="${oldFakeRemoteSubscribeMode}"; else unset PADM_FAKE_REMOTE_SUBSCRIBE_MODE; fi
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runRemoteControlConcurrencyRegression() (
    mkdir -p "$(dirname "$(subscriptionGroupsFile)")"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"https","host":"main.example","port":443,"enabled":true,"sync_status":"success"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"remote_enabled":true,"quota_auto_apply":false},"traffic":{"user_groups":{},"sources":{},"admin":{"sources":{}}}}]}
JSON
    subscriptionGroupsStateWrite '
      .groups[0].sources += [
        {id:"src0", name:"Src0", role:"secondary", scheme:"https", host:"remote0.example", port:443, enabled:true, sync_status:"pending", control_token:"token0"},
        {id:"src2", name:"Src2", role:"secondary", scheme:"https", host:"remote2.example", port:443, enabled:true, sync_status:"pending", control_token:"token2"},
        {id:"src10", name:"Src10", role:"secondary", scheme:"https", host:"remote10.example", port:443, enabled:true, sync_status:"pending", control_token:"token10"}
      ]
    '

    regressionSourceId() {
        local source=$1
        local id=${source#*\"id\":\"}
        printf '%s\n' "${id%%\"*}"
    }

    subscriptionRemoteControlPayload() {
        local source=$1
        local dryRun=$2
        local sourceId
        sourceId=$(regressionSourceId "${source}")
        printf '{"version":1,"group_id":"default","source_id":"%s","dry_run":%s,"desired_users":[]}\n' "${sourceId}" "${dryRun}"
    }

    subscriptionRemoteControlHealth() {
        local source=$1
        local id
        id=$(regressionSourceId "${source}")
        [[ "${id}" == "src0" ]] && sleep 0.01
        printf '{"id":"%s","name":"%s","ok":true}\n' "${id}" "${id}"
    }

    subscriptionRemoteControlRequest() {
        local source=$1
        local endpoint=$2
        local sourceId
        sourceId=$(regressionSourceId "${source}")
        [[ "${sourceId}" == "src0" ]] && sleep 0.01
        printf '{"ok":true,"changed":false,"plan":{"create":[],"remove":[]},"source_id":"%s","endpoint":"%s"}\n' "${sourceId}" "${endpoint}"
    }

    subscriptionRemoteSyncPlanForSource() {
        local source=$1
        local sourceId
        sourceId=$(regressionSourceId "${source}")
        [[ "${sourceId}" == "src0" ]] && sleep 0.01
        printf '{"source_id":"%s","status":"success","dry_run":true,"request":{"source_id":"%s"},"response":{"ok":true,"changed":false,"plan":{"create":[],"remove":[]}}}\n' "${sourceId}" "${sourceId}"
    }

    subscriptionRemoteControlHealthAll | jq -e 'length == 3 and .[0].id == "src0" and .[1].id == "src2" and .[2].id == "src10"' >/dev/null
    subscriptionRemoteSyncPlan | jq -e 'length == 3 and .[0].source_id == "src0" and .[1].source_id == "src2" and .[2].source_id == "src10" and all(.[]; .status == "success")' >/dev/null
)

runRemoteControlAggregationFailureRegression() (
    mkdir -p "$(dirname "$(subscriptionGroupsFile)")"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"https","host":"main.example","port":443,"enabled":true,"sync_status":"success"},{"id":"edge-a","name":"Edge A","role":"secondary","scheme":"https","host":"a.example","port":443,"enabled":true,"sync_status":"pending","control_token":"token-a"},{"id":"edge-b","name":"Edge B","role":"secondary","scheme":"https","host":"b.example","port":443,"enabled":true,"sync_status":"pending","control_token":"token-b"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"remote_enabled":true,"quota_auto_apply":false},"traffic":{"user_groups":{},"sources":{},"admin":{"sources":{}}}}]}
JSON

    subscriptionRemoteControlHealth() {
        local source=$1
        case "$(jq -r '.id' <<<"${source}")" in
        edge-a)
            printf '{"id":"edge-a","name":"Edge A","ok":true}\n'
            ;;
        edge-b)
            printf 'broken-health-json\n'
            ;;
        *)
            printf '{"id":"main","name":"Main","ok":true}\n'
            ;;
        esac
    }
    subscriptionRemoteSyncPlanForSource() {
        local source=$1
        case "$(jq -r '.id' <<<"${source}")" in
        edge-a)
            printf '{"source_id":"edge-a","status":"success","dry_run":true,"request":{"source_id":"edge-a"},"response":{"ok":true,"changed":false,"plan":{"create":[],"remove":[]}}}\n'
            ;;
        edge-b)
            printf 'broken-plan-json\n'
            ;;
        *)
            printf '{"source_id":"main","status":"success","dry_run":true,"request":{"source_id":"main"},"response":{"ok":true,"changed":false,"plan":{"create":[],"remove":[]}}}\n'
            ;;
        esac
    }

    subscriptionRemoteControlHealthAll | jq -e 'length == 2 and .[0].ok == true and .[0].id == "edge-a" and .[1].status == "internal_error" and .[1].error_detail.type == "internal_error"' >/dev/null
    subscriptionRemoteSyncPlan | jq -e 'length == 2 and .[0].status == "success" and .[0].source_id == "edge-a" and .[1].status == "internal_error" and .[1].error_detail.type == "internal_error"' >/dev/null
)

runRemoteControlHealthRegression() (
    local responseFile="${TMP_DIR}/remote-control-health.json"
    local sourceMissing='{"id":"edge-missing","name":"Edge Missing","scheme":"wireguard","transport":"wireguard","host":"remote.example","port":443}'
    local sourceRemote='{"id":"edge-remote","name":"Edge Remote","control_token":"token","scheme":"wireguard","transport":"wireguard","host":"remote.example","port":443}'
    local sourceUnauthorized='{"id":"edge-auth","name":"Edge Auth","control_token":"token","scheme":"wireguard","transport":"wireguard","host":"remote.example","port":443}'

    curl() {
        case "${PADM_FAKE_REMOTE_HEALTH_MODE:-}" in
        unauthorized)
            printf '{"ok":false,"error":"unauthorized"}\n401'
            ;;
        remote_error)
            printf '{"ok":false,"error":"service_unavailable","error_detail":{"type":"service_unavailable","message":"服务暂时不可用"}}\n503'
            ;;
        success)
            printf '{"ok":true,"version":"test","capabilities":["health","sync"]}\n200'
            ;;
        *)
            printf '{"ok":false,"error":"unexpected"}\n500'
            ;;
        esac
    }

    subscriptionRemoteControlHealth "${sourceMissing}" >"${responseFile}"
    jq -e '.status == "missing_token" and .error_detail.type == "missing_token" and .error_detail.message == "未配置控制 token"' "${responseFile}" >/dev/null

    PADM_FAKE_REMOTE_HEALTH_MODE=unauthorized subscriptionRemoteControlHealth "${sourceUnauthorized}" >"${responseFile}"
    jq -e '.status == "unauthorized" and .status_code == "401" and .error_detail.type == "unauthorized" and .error_detail.message == "控制 token 验证失败"' "${responseFile}" >/dev/null

    PADM_FAKE_REMOTE_HEALTH_MODE=remote_error subscriptionRemoteControlHealth "${sourceRemote}" >"${responseFile}"
    jq -e '.status == "remote_error" and .status_code == "503" and .error_detail.type == "remote_error" and (.error | contains("服务暂时不可用"))' "${responseFile}" >/dev/null

    PADM_FAKE_REMOTE_HEALTH_MODE=success subscriptionRemoteControlHealth "${sourceRemote}" >"${responseFile}"
    jq -e '.ok == true and .version == "test" and .capabilities == ["health","sync"] and .id == "edge-remote" and .name == "Edge Remote"' "${responseFile}" >/dev/null
)

runRemoteControlServerRefreshRegression() (
    local subscribeCalls=0
    local subscribeArgs=
    local reconcileCalls=0
    local responseFile="${TMP_DIR}/remote-control-server-refresh.json"
    local oldConfigPath="${configPath:-}"
    local oldSingBoxConfigPath="${singBoxConfigPath:-}"
    local rollbackRoot="${TMP_DIR}/remote-control-rollback"
    local rollbackStateBefore
    local rollbackFirstBefore
    local rollbackSecondBefore
    local oldCoreInstallType="${coreInstallType:-}"
    local setUsersCalls=0
    local rollbackExpectedFile="${TMP_DIR}/remote-control-rollback-expected.json"

    eval "$(declare -f subscriptionControlApplyAccountPlan | sed '1s/^subscriptionControlApplyAccountPlan/originalSubscriptionControlApplyAccountPlan/')"
    eval "$(declare -f subscriptionSyncSetUsersInFile | sed '1s/^subscriptionSyncSetUsersInFile/originalSubscriptionSyncSetUsersInFile/')"
    eval "$(declare -f subscriptionSyncPlanFromAccounts | sed '1s/^subscriptionSyncPlanFromAccounts/originalSubscriptionSyncPlanFromAccounts/')"
    eval "$(declare -f renderSubscribeUserOutputs | sed '1s/^renderSubscribeUserOutputs/originalRenderSubscribeUserOutputs/')"

    subscriptionSyncPlanFromAccounts() {
        printf '{"create":["sub_team_a"],"remove":[]}'
    }
    subscriptionControlApplyAccountPlan() {
        return 0
    }
    subscribe() {
        subscribeCalls=$((subscribeCalls + 1))
        subscribeArgs="$*"
    }
    subscriptionSyncReconcileLocalServices() {
        reconcileCalls=$((reconcileCalls + 1))
    }

    set +e
    subscriptionControlApplySync '{"desired_users":[{"id":"","uuid":""}]}' >"${responseFile}"
    local invalidEmptyIdStatus=$?
    subscriptionControlApplySync '{"desired_users":[{"id":"team-a"},{"id":"team-a"}]}' >"${responseFile}.duplicate"
    local invalidDuplicateStatus=$?
    subscriptionControlApplySync '{"desired_users":[{"id":"team-a","uuid":123}]}' >"${responseFile}.uuid"
    local invalidUuidStatus=$?
    set -e
    [[ "${invalidEmptyIdStatus}" -ne 0 ]]
    [[ "${invalidDuplicateStatus}" -ne 0 ]]
    [[ "${invalidUuidStatus}" -ne 0 ]]
    jq -e '.ok == false and .error == "invalid_payload" and .error_detail.type == "invalid_payload"' "${responseFile}" >/dev/null
    jq -e '.ok == false and .error == "invalid_payload" and .error_detail.type == "invalid_payload"' "${responseFile}.duplicate" >/dev/null
    jq -e '.ok == false and .error == "invalid_payload" and .error_detail.type == "invalid_payload"' "${responseFile}.uuid" >/dev/null

    subscriptionSyncPlanFromAccounts() {
        printf '{"create":["sub_team_a"],"remove":[]}'
    }
    PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}' >"${responseFile}"
    jq -e '.ok == true and .changed == true and .dry_run == false' "${responseFile}" >/dev/null
    [[ "${subscribeCalls}" == "1" ]]
    [[ "${subscribeArgs}" == "false false" ]]
    [[ "${reconcileCalls}" == "0" ]]

    PADM_CONTROL_SERVER= subscriptionControlApplySync '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}' >"${responseFile}"
    jq -e '.ok == true and .changed == true and .dry_run == false' "${responseFile}" >/dev/null
    [[ "${subscribeCalls}" == "1" ]]
    [[ "${reconcileCalls}" == "1" ]]

    (
        local prepareRoot="${TMP_DIR}/remote-control-prepare-config-failure"
        local prepareResponse="${TMP_DIR}/remote-control-prepare-config-failure.json"
        mkdir -p "${prepareRoot}/groups"
        export PADM_SUBSCRIPTION_GROUPS_DIR="${prepareRoot}/groups"
        cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
        subscriptionSyncCreateConfigBackups() {
            return 1
        }
        set +e
        PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}' >"${prepareResponse}"
        local prepareStatus=$?
        set -e
        [[ "${prepareStatus}" -ne 0 ]]
        jq -e '.ok == false and .changed == false and .dry_run == false and .error == "prepare_failed" and .error_detail.type == "prepare_failed" and (.error_detail.message | contains("配置备份失败")) and .plan.create == ["sub_team_a"] and .plan.remove == []' "${prepareResponse}" >/dev/null
    )

    (
        local prepareRoot="${TMP_DIR}/remote-control-prepare-output-failure"
        local prepareResponse="${TMP_DIR}/remote-control-prepare-output-failure.json"
        local expectedBackupDir="${prepareRoot}/created-backup"
        mkdir -p "${prepareRoot}/groups"
        export PADM_SUBSCRIPTION_GROUPS_DIR="${prepareRoot}/groups"
        cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
        subscriptionSyncCreateConfigBackups() {
            local backupPath="${expectedBackupDir}"
            mkdir -p "${backupPath}" || return 1
            printf '%s\n' "${backupPath}"
        }
        subscriptionSyncCreateSubscribeOutputBackups() {
            return 1
        }
        set +e
        PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}' >"${prepareResponse}"
        local prepareStatus=$?
        set -e
        [[ "${prepareStatus}" -ne 0 ]]
        jq -e '.ok == false and .changed == false and .dry_run == false and .error == "prepare_failed" and .error_detail.type == "prepare_failed" and (.error_detail.message | contains("订阅输出备份失败")) and .plan.create == ["sub_team_a"] and .plan.remove == []' "${prepareResponse}" >/dev/null
        [[ ! -e "${expectedBackupDir}" ]]
    )

    subscribe() {
        subscribeCalls=$((subscribeCalls + 1))
        subscribeArgs="$*"
        return 1
    }
    set +e
    PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}' >"${responseFile}"
    local refreshStatus=$?
    set -e
    [[ "${refreshStatus}" -ne 0 ]]
    jq -e '.ok == false and .error == "refresh_failed" and .error_detail.type == "refresh_failed"' "${responseFile}" >/dev/null

    subscriptionControlApplyAccountPlan() {
        return 1
    }
    set +e
    PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"team-b","uuid":"22222222-2222-2222-2222-222222222222"}],"dry_run":false}' >"${responseFile}"
    local applyStatus=$?
    set -e
    [[ "${applyStatus}" -ne 0 ]]
    jq -e '.ok == false and .error == "apply_plan_failed" and .error_detail.type == "apply_plan_failed"' "${responseFile}" >/dev/null

    (
        local restoreFailureStateWriteCalls=0
        local restoreFailureRoot="${TMP_DIR}/remote-control-apply-restore-failure"
        local restoreFailureResponse="${TMP_DIR}/remote-control-apply-restore-failure.json"
        mkdir -p "${restoreFailureRoot}/xray"
        configPath="${restoreFailureRoot}/xray/"
        singBoxConfigPath="${restoreFailureRoot}/xray/"
        cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":false,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"00000000-0000-0000-0000-000000000000"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
        eval "$(declare -f subscriptionGroupsStateWrite | sed '1s/^subscriptionGroupsStateWrite/originalSubscriptionGroupsStateWrite/')"
        subscriptionSyncPlanFromAccounts() {
            printf '{"create":["sub_team_a"],"remove":[]}'
        }
        subscriptionSyncApplyAccountPlanTransaction() {
            return 1
        }
        subscriptionGroupsStateWrite() {
            restoreFailureStateWriteCalls=$((restoreFailureStateWriteCalls + 1))
            if [[ "${restoreFailureStateWriteCalls}" == "2" ]]; then
                return 1
            fi
            originalSubscriptionGroupsStateWrite "$@"
        }
        set +e
        PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}' >"${restoreFailureResponse}"
        local restoreFailureStatus=$?
        set -e
        [[ "${restoreFailureStatus}" -ne 0 ]]
        jq -e '.ok == false and .error == "apply_plan_failed" and .error_detail.type == "apply_plan_failed" and (.error_detail.message | contains("订阅状态恢复失败"))' "${restoreFailureResponse}" >/dev/null
        jq -e '.groups[0].user_groups[0].enabled == true and .groups[0].user_groups[0].uuid == "11111111-1111-1111-1111-111111111111"' "$(subscriptionGroupsFile)" >/dev/null
    )

    (
        local restoreOrderLog="${TMP_DIR}/remote-control-restore-order.log"
        local restoreOrderConfig="${TMP_DIR}/remote-control-restore-config"
        local restoreOrderOutput="${TMP_DIR}/remote-control-restore-output"
        mkdir -p "${restoreOrderConfig}" "${restoreOrderOutput}"
        subscriptionGroupsStateWrite() {
            printf 'state\n' >>"${restoreOrderLog}"
            return 0
        }
        subscriptionSyncRestoreConfigBackups() {
            printf 'config\n' >>"${restoreOrderLog}"
            return 1
        }
        subscriptionSyncRestoreSubscribeOutputBackups() {
            printf 'output\n' >>"${restoreOrderLog}"
            return 0
        }
        SUBSCRIPTION_CONTROL_RESTORE_ERROR=
        rm -f "${restoreOrderLog}"
        set +e
        subscriptionControlRestoreAppliedPlan '{"version":2,"groups":[]}' "${restoreOrderConfig}" "${restoreOrderOutput}"
        local restoreOrderStatus=$?
        set -e
        [[ "${restoreOrderStatus}" -eq 1 ]]
        grep -qx 'state' "${restoreOrderLog}"
        grep -qx 'config' "${restoreOrderLog}"
        grep -qx 'output' "${restoreOrderLog}"
        [[ "${SUBSCRIPTION_CONTROL_RESTORE_ERROR}" == *"配置恢复失败"* ]]
    )

    (
        local restoreOrderLog="${TMP_DIR}/remote-control-restore-order-state.log"
        local restoreOrderConfig="${TMP_DIR}/remote-control-restore-config-state"
        local restoreOrderOutput="${TMP_DIR}/remote-control-restore-output-state"
        mkdir -p "${restoreOrderConfig}" "${restoreOrderOutput}"
        subscriptionGroupsStateWrite() {
            printf 'state\n' >>"${restoreOrderLog}"
            return 1
        }
        subscriptionSyncRestoreConfigBackups() {
            printf 'config\n' >>"${restoreOrderLog}"
            return 0
        }
        subscriptionSyncRestoreSubscribeOutputBackups() {
            printf 'output\n' >>"${restoreOrderLog}"
            return 0
        }
        SUBSCRIPTION_CONTROL_RESTORE_ERROR=
        rm -f "${restoreOrderLog}"
        set +e
        subscriptionControlRestoreAppliedPlan '{"version":2,"groups":[]}' "${restoreOrderConfig}" "${restoreOrderOutput}"
        local restoreOrderStatus=$?
        set -e
        [[ "${restoreOrderStatus}" -eq 1 ]]
        grep -qx 'state' "${restoreOrderLog}"
        grep -qx 'config' "${restoreOrderLog}"
        grep -qx 'output' "${restoreOrderLog}"
        [[ "${SUBSCRIPTION_CONTROL_RESTORE_ERROR}" == *"状态恢复失败"* ]]
    )

    mkdir -p "${rollbackRoot}/xray"
    configPath="${rollbackRoot}/xray/"
    singBoxConfigPath="${rollbackRoot}/xray/"
    cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[]}}]}
JSON
    cat >"${configPath}03_VLESS_WS_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[]}}]}
JSON
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    coreInstallType=1
    subscriptionSyncPlanFromAccounts() {
        printf '{"create":["sub_rollback"],"remove":[]}'
    }
    rollbackStateBefore=$(<"$(subscriptionGroupsFile)")
    rollbackFirstBefore=$(<"${configPath}02_VLESS_TCP_inbounds.json")
    rollbackSecondBefore=$(<"${configPath}03_VLESS_WS_inbounds.json")
    subscriptionControlApplyAccountPlan() {
        originalSubscriptionControlApplyAccountPlan "$@"
    }
    subscriptionSyncSetUsersInFile() {
        setUsersCalls=$((setUsersCalls + 1))
        if [[ "${setUsersCalls}" -eq 2 ]]; then
            return 1
        fi
        originalSubscriptionSyncSetUsersInFile "$@"
    }
    set +e
    PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"rollback","uuid":"66666666-6666-6666-6666-666666666666"}],"dry_run":false}' >"${responseFile}.rollback"
    local rollbackStatus=$?
    set -e
    [[ "${rollbackStatus}" -ne 0 ]]
    jq -e '.ok == false and .error == "apply_plan_failed" and .error_detail.type == "apply_plan_failed"' "${responseFile}.rollback" >/dev/null
    printf '%s\n' "${rollbackStateBefore}" >"${rollbackExpectedFile}"
    jq -e --slurpfile expected "${rollbackExpectedFile}" '. == $expected[0]' "$(subscriptionGroupsFile)" >/dev/null
    [[ "$(<"${configPath}02_VLESS_TCP_inbounds.json")" == "${rollbackFirstBefore}" ]]
    [[ "$(<"${configPath}03_VLESS_WS_inbounds.json")" == "${rollbackSecondBefore}" ]]
    if find "${rollbackRoot}" \( -name '*.sync.*' -o -name '*subscription-sync-backup*' \) | grep -q .; then
        return 1
    fi
    configPath="${oldConfigPath}"
    singBoxConfigPath="${oldSingBoxConfigPath}"
    coreInstallType="${oldCoreInstallType}"
    subscriptionSyncSetUsersInFile() {
        originalSubscriptionSyncSetUsersInFile "$@"
    }

    local refreshRollbackRoot="${TMP_DIR}/remote-control-refresh-rollback"
    local refreshRollbackLocalDir="${refreshRollbackRoot}/subscribe_local"
    local refreshRollbackPublicDir="${refreshRollbackRoot}/subscribe"
    local refreshRollbackStateBefore
    local refreshRollbackFirstBefore
    local refreshRollbackOldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
    local refreshRollbackOldPublicDir="${PADM_SUBSCRIBE_DIR:-}"
    local refreshRollbackOldScriptDir="${SCRIPT_DIR}"
    local refreshRollbackPublicBefore
    local refreshRollbackLocalBefore
    local refreshRollbackExpectedFile="${TMP_DIR}/remote-control-refresh-rollback-expected.json"
    local refreshRollbackPublicExpected="${TMP_DIR}/remote-control-refresh-public-expected.txt"
    local refreshRollbackLocalExpected="${TMP_DIR}/remote-control-refresh-local-expected.txt"
    mkdir -p "${refreshRollbackRoot}/xray"
    configPath="${refreshRollbackRoot}/xray/"
    singBoxConfigPath="${refreshRollbackRoot}/xray/"
    cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[]}}]}
JSON
    mkdir -p "${refreshRollbackLocalDir}/default" "${refreshRollbackLocalDir}/clashMeta" "${refreshRollbackLocalDir}/sing-box" "${refreshRollbackPublicDir}/default" "${refreshRollbackPublicDir}/clashMeta"
    export PADM_SUBSCRIBE_LOCAL_DIR="${refreshRollbackLocalDir}"
    export PADM_SUBSCRIBE_DIR="${refreshRollbackPublicDir}"
    SCRIPT_DIR="${PROJECT_ROOT}"
    subscribeType=https
    subscribePort=39778
    currentHost=refresh.example.com
    printf 'old salt\n' >"${refreshRollbackLocalDir}/subscribeSalt"
    printf 'old local default\n' >"${refreshRollbackLocalDir}/default/existing"
    printf 'old public default\n' >"${refreshRollbackPublicDir}/default/existing-md5"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    coreInstallType=1
    subscriptionSyncPlanFromAccounts() {
        printf '{"create":["sub_publish"],"remove":[]}'
    }
    subscriptionControlApplyAccountPlan() {
        subscriptionGroupsStateWrite '.groups |= map(.user_groups += [{"id":"publish","name":"Publish","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"77777777-7777-7777-7777-777777777777"}])'
        cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_publish-vless","id":"77777777-7777-7777-7777-777777777777"}]}}]}
JSON
    }
    refreshRollbackStateBefore=$(<"$(subscriptionGroupsFile)")
    refreshRollbackFirstBefore=$(<"${configPath}02_VLESS_TCP_inbounds.json")
    refreshRollbackLocalBefore=$(find "${refreshRollbackLocalDir}" -type f -printf '%P\t' -exec cat {} \; | sort)
    refreshRollbackPublicBefore=$(find "${refreshRollbackPublicDir}" -type f -printf '%P\t' -exec cat {} \; | sort)
    printf '%s\n' "${refreshRollbackLocalBefore}" >"${refreshRollbackLocalExpected}"
    printf '%s\n' "${refreshRollbackPublicBefore}" >"${refreshRollbackPublicExpected}"
    subscriptionControlRefreshPublishedSubscriptions() {
        printf 'new salt\n' >"${refreshRollbackLocalDir}/subscribeSalt"
        printf 'new local default\n' >"${refreshRollbackLocalDir}/default/existing"
        printf 'new local created\n' >"${refreshRollbackLocalDir}/default/generated"
        printf 'new public default\n' >"${refreshRollbackPublicDir}/default/existing-md5"
        printf 'new public created\n' >"${refreshRollbackPublicDir}/default/generated-md5"
        return 1
    }
    set +e
    PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"publish","uuid":"77777777-7777-7777-7777-777777777777"}],"dry_run":false}' >"${responseFile}.refresh-rollback"
    local refreshRollbackStatus=$?
    set -e
    [[ "${refreshRollbackStatus}" -ne 0 ]]
    jq -e '.ok == false and .error == "refresh_failed" and .error_detail.type == "refresh_failed"' "${responseFile}.refresh-rollback" >/dev/null
    printf '%s\n' "${refreshRollbackStateBefore}" >"${refreshRollbackExpectedFile}"
    jq -e --slurpfile expected "${refreshRollbackExpectedFile}" '. == $expected[0]' "$(subscriptionGroupsFile)" >/dev/null
    [[ "$(<"${configPath}02_VLESS_TCP_inbounds.json")" == "${refreshRollbackFirstBefore}" ]]
    diff -u "${refreshRollbackLocalExpected}" <(find "${refreshRollbackLocalDir}" -type f -printf '%P\t' -exec cat {} \; | sort)
    diff -u "${refreshRollbackPublicExpected}" <(find "${refreshRollbackPublicDir}" -type f -printf '%P\t' -exec cat {} \; | sort)
    if find "${refreshRollbackRoot}" \( -name '*.sync.*' -o -name '*subscription-sync-backup*' -o -name '*subscription-output-backup*' \) | grep -q .; then
        return 1
    fi
    configPath="${oldConfigPath}"
    singBoxConfigPath="${oldSingBoxConfigPath}"
    coreInstallType="${oldCoreInstallType}"
    SCRIPT_DIR="${refreshRollbackOldScriptDir}"
    if [[ -n "${refreshRollbackOldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${refreshRollbackOldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
    if [[ -n "${refreshRollbackOldPublicDir}" ]]; then export PADM_SUBSCRIBE_DIR="${refreshRollbackOldPublicDir}"; else unset PADM_SUBSCRIBE_DIR; fi
    subscriptionControlRefreshPublishedSubscriptions() {
        subscribe false false >/dev/null 2>&1
    }

    local restoreFailureRoot="${TMP_DIR}/remote-control-restore-failure"
    local restoreFailureLocalDir="${restoreFailureRoot}/subscribe_local"
    local restoreFailurePublicDir="${restoreFailureRoot}/subscribe"
    local restoreFailureOldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
    local restoreFailureOldPublicDir="${PADM_SUBSCRIBE_DIR:-}"
    local restoreFailureOldScriptDir="${SCRIPT_DIR}"
    local restoreFailureOldTmpDir="${TMPDIR:-}"
    local restoreFailureBackupDirs=()
    mkdir -p "${restoreFailureRoot}/xray" "${restoreFailureLocalDir}/default" "${restoreFailurePublicDir}/default"
    configPath="${restoreFailureRoot}/xray/"
    singBoxConfigPath="${restoreFailureRoot}/xray/"
    TMPDIR="${restoreFailureRoot}"
    cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[]}}]}
JSON
    export PADM_SUBSCRIBE_LOCAL_DIR="${restoreFailureLocalDir}"
    export PADM_SUBSCRIBE_DIR="${restoreFailurePublicDir}"
    SCRIPT_DIR="${PROJECT_ROOT}"
    printf 'old local\n' >"${restoreFailureLocalDir}/default/existing"
    printf 'old public\n' >"${restoreFailurePublicDir}/default/existing-md5"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    coreInstallType=1
    subscriptionSyncPlanFromAccounts() {
        printf '{"create":["sub_restore_fail"],"remove":[]}'
    }
    subscriptionControlApplyAccountPlan() {
        subscriptionGroupsStateWrite '.groups |= map(.user_groups += [{"id":"restore-fail","name":"Restore Fail","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"88888888-8888-8888-8888-888888888888"}])'
        cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_restore_fail-vless","id":"88888888-8888-8888-8888-888888888888"}]}}]}
JSON
    }
    subscriptionControlRefreshPublishedSubscriptions() {
        printf 'new local\n' >"${restoreFailureLocalDir}/default/existing"
        printf 'new local created\n' >"${restoreFailureLocalDir}/default/generated"
        printf 'new public\n' >"${restoreFailurePublicDir}/default/existing-md5"
        printf 'new public created\n' >"${restoreFailurePublicDir}/default/generated-md5"
        return 1
    }
    cp() {
        if [[ "$1" == "-a" && "$2" == ${restoreFailureRoot}/padm-subscription-output-backup.*/local/. ]]; then
            return 1
        fi
        command cp "$@"
    }
    set +e
    PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"restore-fail","uuid":"88888888-8888-8888-8888-888888888888"}],"dry_run":false}' >"${responseFile}.restore-failure"
    local restoreFailureStatus=$?
    set -e
    unset -f cp
    [[ "${restoreFailureStatus}" -ne 0 ]]
    jq -e '.ok == false and .error == "refresh_failed" and .error_detail.type == "refresh_failed" and (.error_detail.message | contains("订阅输出恢复失败"))' "${responseFile}.restore-failure" >/dev/null
    mapfile -t restoreFailureBackupDirs < <(find "${restoreFailureRoot}" -maxdepth 1 -type d \( -name 'padm-subscription-output-backup.*' -o -name 'padm-subscription-sync-backup.*' \) -print)
    [[ "${#restoreFailureBackupDirs[@]}" == "2" ]]
    find "${restoreFailureRoot}" -maxdepth 1 -type d -name 'padm-subscription-output-backup.*' | grep -q .
    [[ ! -e "${restoreFailureLocalDir}/default/existing" || "$(<"${restoreFailureLocalDir}/default/existing")" != "old local" ]]
    if find "${restoreFailureRoot}/xray" -name '*.sync.*' | grep -q .; then
        return 1
    fi
    if [[ -n "${restoreFailureOldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${restoreFailureOldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
    if [[ -n "${restoreFailureOldPublicDir}" ]]; then export PADM_SUBSCRIBE_DIR="${restoreFailureOldPublicDir}"; else unset PADM_SUBSCRIBE_DIR; fi
    configPath="${oldConfigPath}"
    singBoxConfigPath="${oldSingBoxConfigPath}"
    coreInstallType="${oldCoreInstallType}"
    SCRIPT_DIR="${restoreFailureOldScriptDir}"
    if [[ -n "${restoreFailureOldTmpDir}" ]]; then export TMPDIR="${restoreFailureOldTmpDir}"; else unset TMPDIR; fi
    subscriptionControlRefreshPublishedSubscriptions() {
        subscribe false false >/dev/null 2>&1
    }
    subscriptionControlApplyAccountPlan() {
        originalSubscriptionControlApplyAccountPlan "$@"
    }
    subscriptionSyncPlanFromAccounts() {
        originalSubscriptionSyncPlanFromAccounts "$@"
    }

    subscriptionControlApplyAccountPlan() {
        return 0
    }
    (
        local reconcileLog="${TMP_DIR}/remote-control-local-reconcile-retry.log"
        reconcileCalls=0
        : >"${reconcileLog}"
        subscriptionSyncReconcileLocalServices() {
            reconcileCalls=$((reconcileCalls + 1))
            printf '%s\n' "${1:-<empty>}" >>"${reconcileLog}"
            [[ -n "${1:-}" ]]
        }
        set +e
        PADM_CONTROL_SERVER= subscriptionControlApplySync '{"desired_users":[{"id":"team-c","uuid":"33333333-3333-3333-3333-333333333333"}],"dry_run":false}' >"${responseFile}"
        local reconcileStatus=$?
        set -e
        [[ "${reconcileStatus}" -ne 0 ]]
        [[ "${reconcileCalls}" == "2" ]]
        grep -qx '<empty>' "${reconcileLog}"
        grep -qx 'true' "${reconcileLog}"
        jq -e '.ok == false and .error == "reconcile_failed" and .error_detail.type == "reconcile_failed" and (.error_detail.message | contains("已恢复旧配置")) and ((.error_detail.message | contains("恢复旧配置后服务重建仍失败")) | not)' "${responseFile}" >/dev/null
    )

    (
        local reconcileLog="${TMP_DIR}/remote-control-local-reconcile-retry-fail.log"
        reconcileCalls=0
        : >"${reconcileLog}"
        subscriptionSyncReconcileLocalServices() {
            reconcileCalls=$((reconcileCalls + 1))
            printf '%s\n' "${1:-<empty>}" >>"${reconcileLog}"
            return 1
        }
        set +e
        PADM_CONTROL_SERVER= subscriptionControlApplySync '{"desired_users":[{"id":"team-c","uuid":"33333333-3333-3333-3333-333333333333"}],"dry_run":false}' >"${responseFile}.reconcile-retry-fail"
        local reconcileStatus=$?
        set -e
        [[ "${reconcileStatus}" -ne 0 ]]
        [[ "${reconcileCalls}" == "2" ]]
        grep -qx '<empty>' "${reconcileLog}"
        grep -qx 'true' "${reconcileLog}"
        jq -e '.ok == false and .error == "reconcile_failed" and .error_detail.type == "reconcile_failed" and (.error_detail.message | contains("恢复旧配置后服务重建仍失败"))' "${responseFile}.reconcile-retry-fail" >/dev/null
    )

    subscriptionSyncPlanFromAccounts() {
        printf '{"create":[null],"remove":[]}'
    }
    set +e
    PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"team-d","uuid":"44444444-4444-4444-4444-444444444444"}],"dry_run":true}' >"${responseFile}"
    local invalidPlanStatus=$?
    set -e
    [[ "${invalidPlanStatus}" -ne 0 ]]
    jq -e '.ok == false and .error == "plan_failed" and .error_detail.type == "plan_failed" and (.plan.create[0] == null)' "${responseFile}" >/dev/null

    subscriptionSyncPlanFromAccounts() {
        printf 'not-json\n'
    }
    set +e
    PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"team-e","uuid":"55555555-5555-5555-5555-555555555555"}],"dry_run":true}' >"${responseFile}"
    local badPlanStatus=$?
    set -e
    [[ "${badPlanStatus}" -ne 0 ]]
    jq -e '.ok == false and .error == "plan_failed" and .error_detail.type == "plan_failed" and has("plan") == false' "${responseFile}" >/dev/null
)

runSubscriptionControlServiceInstallRegression() (
    local fakeBin="${TMP_DIR}/remote-control-service-bin"
    local controlRoot="${TMP_DIR}/remote-control-service-install"
    local actionsFile="${TMP_DIR}/remote-control-systemctl-actions.txt"
    local healthTokensFile="${TMP_DIR}/remote-control-health-tokens.txt"
    local knownToken="known-control-token"
    local installStatus
    local oldPath="${PATH}"
    local oldServerScript
    local oldServiceFile
    local oldHealthCheckDefinition=
    local oldHealthRetries="${PADM_CONTROL_HEALTH_RETRIES:-}"
    local oldHealthRetryDelay="${PADM_CONTROL_HEALTH_RETRY_DELAY:-}"
    local oldHealthTimeout="${PADM_CONTROL_HEALTH_TIMEOUT:-}"

    mkdir -p "${fakeBin}" "${controlRoot}"
    cat >"${fakeBin}/python3" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${PADM_CONTROL_HEALTH_TOKEN:-}" >>"${PADM_FAKE_HEALTH_TOKENS}"
[[ "${PADM_FAKE_HEALTH_FAIL:-}" == "true" ]] && exit 1
exit 0
SH
    cat >"${fakeBin}/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    cat >"${fakeBin}/systemctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${PADM_FAKE_SYSTEMCTL_ACTIONS}"
case "$1" in
daemon-reload)
    [[ "${PADM_FAKE_SYSTEMCTL_FAIL:-}" == "daemon-reload" ]] && exit 1
    exit 0
    ;;
is-active)
    [[ "${PADM_FAKE_SYSTEMCTL_ACTIVE:-}" == "true" ]] && exit 0
    exit 3
    ;;
is-enabled)
    [[ "${PADM_FAKE_SYSTEMCTL_ENABLED:-}" == "true" ]] && exit 0
    exit 1
    ;;
restart)
    [[ "${PADM_FAKE_SYSTEMCTL_FAIL:-}" == "restart" ]] && exit 1
    exit 0
    ;;
enable)
    [[ "${PADM_FAKE_SYSTEMCTL_FAIL:-}" == "enable" ]] && exit 1
    exit 0
    ;;
*)
    exit 0
    ;;
esac
SH
    chmod +x "${fakeBin}/python3" "${fakeBin}/sleep" "${fakeBin}/systemctl"

    oldHealthCheckDefinition=$(declare -f subscriptionControlHealthCheck)
    subscriptionControlHealthCheck() {
        printf '%s\n' "$1" >>"${PADM_FAKE_HEALTH_TOKENS}"
        [[ "${PADM_FAKE_HEALTH_FAIL:-}" != "true" ]]
    }

    subscriptionControlServiceFile() {
        printf '%s\n' "${controlRoot}/systemd/padm-subscription-control.service"
    }
    export PADM_FAKE_SYSTEMCTL_ACTIONS="${actionsFile}"
    export PADM_FAKE_HEALTH_TOKENS="${healthTokensFile}"
    export PADM_CONTROL_HEALTH_RETRIES=1
    export PADM_CONTROL_HEALTH_RETRY_DELAY=0
    export PADM_CONTROL_HEALTH_TIMEOUT=0.05
    PATH="${fakeBin}:${oldPath}"
    sleep() { return 0; }

    PADM_SUBSCRIPTION_GROUPS_DIR="${controlRoot}/success"
    mkdir -p "$(dirname "$(subscriptionControlTokenFile)")"
    printf '%s\n' "${knownToken}" >"$(subscriptionControlTokenFile)"
    : >"${actionsFile}"
    : >"${healthTokensFile}"
    installSubscriptionControlService
    [[ -x "$(subscriptionControlServerScript)" ]]
    grep -q 'ExecStart=/usr/bin/env python3' "$(subscriptionControlServiceFile)"
    grep -qxF 'enable --now padm-subscription-control.service' "${actionsFile}"
    grep -qxF "${knownToken}" "${healthTokensFile}"

    PADM_SUBSCRIPTION_GROUPS_DIR="${controlRoot}/systemctl-fail"
    mkdir -p "$(dirname "$(subscriptionControlTokenFile)")"
    printf '%s\n' "${knownToken}" >"$(subscriptionControlTokenFile)"
    export PADM_FAKE_SYSTEMCTL_FAIL=enable
    set +e
    installSubscriptionControlService
    installStatus=$?
    set -e
    PADM_FAKE_SYSTEMCTL_FAIL=
    [[ "${installStatus}" -ne 0 ]]
    [[ ! -e "$(subscriptionControlServerScript)" ]]
    [[ ! -e "$(subscriptionControlServiceFile)" ]]
    [[ "${SUBSCRIPTION_CONTROL_INSTALL_ERROR}" == *"已恢复安装前状态"* ]]

    PADM_SUBSCRIPTION_GROUPS_DIR="${controlRoot}/health-fail"
    mkdir -p "$(dirname "$(subscriptionControlTokenFile)")"
    printf '%s\n' "${knownToken}" >"$(subscriptionControlTokenFile)"
    : >"${actionsFile}"
    export PADM_FAKE_HEALTH_FAIL=true
    set +e
    installSubscriptionControlService
    installStatus=$?
    set -e
    PADM_FAKE_HEALTH_FAIL=
    [[ "${installStatus}" -ne 0 ]]
    [[ ! -e "$(subscriptionControlServerScript)" ]]
    [[ ! -e "$(subscriptionControlServiceFile)" ]]
    [[ "${SUBSCRIPTION_CONTROL_INSTALL_ERROR}" == *"已恢复安装前状态"* ]]

    PADM_SUBSCRIPTION_GROUPS_DIR="${controlRoot}/health-rollback"
    mkdir -p "$(dirname "$(subscriptionControlTokenFile)")" "$(dirname "$(subscriptionControlServerScript)")" "$(dirname "$(subscriptionControlServiceFile)")"
    printf '%s\n' "${knownToken}" >"$(subscriptionControlTokenFile)"
    printf 'old-server\n' >"$(subscriptionControlServerScript)"
    printf 'old-service\n' >"$(subscriptionControlServiceFile)"
    oldServerScript=$(subscriptionControlServerScript)
    oldServiceFile=$(subscriptionControlServiceFile)
    : >"${actionsFile}"
    export PADM_FAKE_SYSTEMCTL_ACTIVE=true
    export PADM_FAKE_SYSTEMCTL_ENABLED=true
    export PADM_FAKE_HEALTH_FAIL=true
    set +e
    installSubscriptionControlService
    installStatus=$?
    set -e
    PADM_FAKE_SYSTEMCTL_ACTIVE=
    PADM_FAKE_SYSTEMCTL_ENABLED=
    PADM_FAKE_HEALTH_FAIL=
    [[ "${installStatus}" -ne 0 ]]
    [[ "$(<"${oldServerScript}")" == "old-server" ]]
    [[ "$(<"${oldServiceFile}")" == "old-service" ]]
    [[ "$(grep -c '^daemon-reload$' "${actionsFile}")" == "2" ]]
    [[ "$(grep -c '^restart padm-subscription-control.service$' "${actionsFile}")" == "2" ]]

    if [[ -n "${oldHealthRetries}" ]]; then export PADM_CONTROL_HEALTH_RETRIES="${oldHealthRetries}"; else unset PADM_CONTROL_HEALTH_RETRIES; fi
    if [[ -n "${oldHealthRetryDelay}" ]]; then export PADM_CONTROL_HEALTH_RETRY_DELAY="${oldHealthRetryDelay}"; else unset PADM_CONTROL_HEALTH_RETRY_DELAY; fi
    if [[ -n "${oldHealthTimeout}" ]]; then export PADM_CONTROL_HEALTH_TIMEOUT="${oldHealthTimeout}"; else unset PADM_CONTROL_HEALTH_TIMEOUT; fi
    if [[ -n "${oldHealthCheckDefinition}" ]]; then
        eval "${oldHealthCheckDefinition}"
    else
        unset -f subscriptionControlHealthCheck
    fi
)

runSubscriptionControlServerResponseRegression() (
    command -v python3 >/dev/null 2>&1 || return 0

    local controlRoot="${TMP_DIR}/remote-control-server-response"
    local fakeInstall="${controlRoot}/install.sh"
    local modeFile="${controlRoot}/mode"
    local responseFile="${controlRoot}/response.txt"
    local serverLog="${controlRoot}/server.log"
    local serverScript
    local serverPid=
    local testPort
    local serverToken="test-token"
    local status
    local body
    local ready=

    mkdir -p "${controlRoot}"
    testPort=$(python3 <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)
    getScriptVersion() {
        printf 'test\n'
    }
    cat >"${fakeInstall}" <<'SH'
#!/usr/bin/env bash
endpoint=${2:-}
mode=$(cat "${PADM_FAKE_CONTROL_MODE_FILE}" 2>/dev/null || true)
payload=
if [[ "${PADM_CONTROL_TOKEN:-}" != "${PADM_FAKE_SERVER_TOKEN:-}" ]]; then
    printf '{"ok":false,"error":"unauthorized","error_detail":{"type":"unauthorized","message":"控制 token 验证失败"}}\n'
    exit 1
fi
        if [[ "${endpoint}" == "sync" || "${endpoint}" == "subscribe" ]]; then
            payload=$(cat)
            if [[ -z "${payload}" ]]; then
                if [[ "${endpoint}" == "sync" ]]; then
                    printf '{"ok":false,"error":"empty_payload","error_detail":{"type":"empty_payload","message":"同步请求体为空"}}\n'
                else
                    printf '{"ok":false,"error":"empty_payload","error_detail":{"type":"empty_payload","message":"订阅请求体为空"}}\n'
                fi
                exit 1
            fi
            if ! jq -e . >/dev/null 2>&1 <<<"${payload}"; then
                if [[ "${endpoint}" == "sync" ]]; then
                    printf '{"ok":false,"error":"invalid_payload","error_detail":{"type":"invalid_payload","message":"同步请求体格式不正确"}}\n'
                else
                    printf '{"ok":false,"error":"invalid_payload","error_detail":{"type":"invalid_payload","message":"订阅请求体格式不正确"}}\n'
                fi
                exit 1
            fi
        fi
        case "${endpoint}:${mode}" in
        health:*)
    printf '{"ok":false,"error":"health_should_not_execute"}\n'
    exit 9
    ;;
sync:noise)
    printf 'ui noise before sync\n'
    printf '{"ok":false,"error":"first_json"}\n'
    printf 'ui noise between json\n'
    printf '{"ok":true,"changed":true,"plan":{"create":[],"remove":[]}}\n'
    ;;
sync:failed)
    printf 'ui noise before failed sync\n'
    printf '{"ok":true,"changed":true}\n'
    exit 7
    ;;
sync:timeout)
    /bin/sleep 2
    printf '{"ok":true}\n'
    ;;
        sync:invalid)
            printf 'ui noise only\n'
            exit 0
            ;;
        subscribe:noise)
            printf 'ui noise before subscribe\n'
            printf '{"ok":false,"error":"first_json"}\n'
            printf 'ui noise between json\n'
            cat <<'JSON'
{"ok":true,"default":"dmxlc3M6Ly91dWlkQGV4YW1wbGUuY29tOjQ0MyN0ZWFtLWE=","clash_meta":"proxies:\n- name: team-a\n","sing_box":[{"tag":"team-a"}]}
JSON
            ;;
        *)
            printf '{"ok":false,"error":"unexpected"}\n'
            exit 1
            ;;
        esac
SH
    chmod +x "${fakeInstall}"

    subscriptionControlPort() {
        printf '%s\n' "${testPort}"
    }
    subscriptionGroupSyncInstallScript() {
        printf '%s\n' "${fakeInstall}"
    }
    PADM_SUBSCRIPTION_GROUPS_DIR="${controlRoot}/state"
    mkdir -p "$(dirname "$(subscriptionControlTokenFile)")"
    printf '%s\n' "${serverToken}" >"$(subscriptionControlTokenFile)"
    export PADM_FAKE_SERVER_TOKEN="${serverToken}"
    writeSubscriptionControlServer
    serverScript=$(subscriptionControlServerScript)
    printf 'noise\n' >"${modeFile}"
    PADM_CONTROL_SCRIPT_TIMEOUT=1 PADM_FAKE_CONTROL_MODE_FILE="${modeFile}" python3 "${serverScript}" >"${serverLog}" 2>&1 &
    serverPid=$!
    trap '[[ -n "${serverPid}" ]] && kill "${serverPid}" >/dev/null 2>&1 || true; [[ -n "${serverPid}" ]] && wait "${serverPid}" 2>/dev/null || true' EXIT

    controlServerRequest() {
        local method=$1
        local endpoint=$2
        local payload=${3:-}
        local token=${4:-${serverToken}}
        PADM_TEST_CONTROL_METHOD="${method}" \
        PADM_TEST_CONTROL_ENDPOINT="${endpoint}" \
        PADM_TEST_CONTROL_PORT="${testPort}" \
        PADM_TEST_CONTROL_PAYLOAD="${payload}" \
        PADM_TEST_CONTROL_TOKEN="${token}" \
        python3 <<'PY'
import os
import sys
import urllib.error
import urllib.request

method = os.environ["PADM_TEST_CONTROL_METHOD"]
endpoint = os.environ["PADM_TEST_CONTROL_ENDPOINT"]
port = os.environ["PADM_TEST_CONTROL_PORT"]
payload = os.environ.get("PADM_TEST_CONTROL_PAYLOAD", "")
token = os.environ["PADM_TEST_CONTROL_TOKEN"]
data = payload.encode() if method == "POST" else None
request = urllib.request.Request(
    f"http://127.0.0.1:{port}/s/control/{endpoint}",
    data=data,
    method=method,
    headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"},
)
try:
    with urllib.request.urlopen(request, timeout=3) as response:
        print(response.status)
        print(response.read().decode())
except urllib.error.HTTPError as error:
    print(error.code)
    print(error.read().decode())
except Exception:
    sys.exit(1)
PY
    }

    for _ in {1..50}; do
        if controlServerRequest GET health >"${responseFile}" 2>/dev/null; then
            ready=true
            break
        fi
        sleep 0.1
    done
    [[ "${ready}" == "true" ]]
    status=$(sed -n '1p' "${responseFile}")
    body=$(sed '1d' "${responseFile}")
    [[ "${status}" == "200" ]]
    jq -e '.ok == true and .version == "test" and .capabilities == ["health","sync","subscribe"]' <<<"${body}" >/dev/null

    printf 'noise\n' >"${modeFile}"
    controlServerRequest POST sync '{"desired_users":[]}' >"${responseFile}"
    status=$(sed -n '1p' "${responseFile}")
    body=$(sed '1d' "${responseFile}")
    [[ "${status}" == "200" ]]
    jq -e '.ok == true and .changed == true and (.plan.create | length) == 0' <<<"${body}" >/dev/null

    controlServerRequest POST subscribe '{"account":"team_a"}' >"${responseFile}"
    status=$(sed -n '1p' "${responseFile}")
    body=$(sed '1d' "${responseFile}")
    [[ "${status}" == "200" ]]
    jq -e '.ok == true and (.default | @base64d) == "vless://uuid@example.com:443#team-a" and (.clash_meta | contains("team-a")) and .sing_box[0].tag == "team-a"' <<<"${body}" >/dev/null

    controlServerRequest GET health '' wrong-token >"${responseFile}" || true
    status=$(sed -n '1p' "${responseFile}")
    body=$(sed '1d' "${responseFile}")
    [[ "${status}" == "401" ]]
    jq -e '.ok == false and .error == "unauthorized" and .error_detail.type == "unauthorized"' <<<"${body}" >/dev/null

    controlServerRequest POST sync '' >"${responseFile}" || true
    status=$(sed -n '1p' "${responseFile}")
    body=$(sed '1d' "${responseFile}")
    [[ "${status}" == "400" ]]
    jq -e '.ok == false and .error == "empty_payload" and .error_detail.type == "empty_payload"' <<<"${body}" >/dev/null

    controlServerRequest POST sync 'not-json' >"${responseFile}" || true
    status=$(sed -n '1p' "${responseFile}")
    body=$(sed '1d' "${responseFile}")
    [[ "${status}" == "400" ]]
    jq -e '.ok == false and .error == "invalid_payload" and .error_detail.type == "invalid_payload"' <<<"${body}" >/dev/null

    controlServerRequest POST subscribe '' >"${responseFile}" || true
    status=$(sed -n '1p' "${responseFile}")
    body=$(sed '1d' "${responseFile}")
    [[ "${status}" == "400" ]]
    jq -e '.ok == false and .error == "empty_payload" and .error_detail.type == "empty_payload"' <<<"${body}" >/dev/null

    controlServerRequest POST subscribe 'not-json' >"${responseFile}" || true
    status=$(sed -n '1p' "${responseFile}")
    body=$(sed '1d' "${responseFile}")
    [[ "${status}" == "400" ]]
    jq -e '.ok == false and .error == "invalid_payload" and .error_detail.type == "invalid_payload"' <<<"${body}" >/dev/null

    printf 'failed\n' >"${modeFile}"
    controlServerRequest POST sync '{"desired_users":[]}' >"${responseFile}"
    status=$(sed -n '1p' "${responseFile}")
    body=$(sed '1d' "${responseFile}")
    [[ "${status}" == "503" ]]
    jq -e '.ok == false and .error == "script_failed" and .error_detail.type == "script_failed" and .exit_code == 7' <<<"${body}" >/dev/null

    printf 'timeout\n' >"${modeFile}"
    controlServerRequest POST sync '{"desired_users":[]}' >"${responseFile}"
    status=$(sed -n '1p' "${responseFile}")
    body=$(sed '1d' "${responseFile}")
    [[ "${status}" == "503" ]]
    jq -e '.ok == false and .error == "script_timeout" and .error_detail.type == "script_timeout"' <<<"${body}" >/dev/null

    printf 'invalid\n' >"${modeFile}"
    controlServerRequest POST sync '{"desired_users":[]}' >"${responseFile}"
    status=$(sed -n '1p' "${responseFile}")
    body=$(sed '1d' "${responseFile}")
    [[ "${status}" == "503" ]]
    jq -e '.ok == false and .error == "invalid_response" and .error_detail.type == "invalid_response"' <<<"${body}" >/dev/null
)

runNginxBlogAutoInstallRegression() {
    local oldAutoInstall="${AUTO_INSTALL:-}"
    local staticDir="${TMP_DIR}/nginx-blog-auto/"
    mkdir -p "${staticDir}"
    : >"${staticDir}/check"
    printf 'keep\n' >"${staticDir}/index.html"

    nginxStaticPath="${staticDir}"
    lastInstallationConfig=
    AUTO_INSTALL=true
    autoRead() {
        return 1
    }
    nginxBlog
    [[ "$(<"${staticDir}/index.html")" == "keep" ]]
    AUTO_INSTALL="${oldAutoInstall}"
}

runXrayTrafficStatsJqCompatibilityRegression() (
    local fakeBin="${TMP_DIR}/fake-xray-stats-bin"
    mkdir -p "${fakeBin}"
    cat >"${fakeBin}/xray" <<'SH'
#!/usr/bin/env bash
cat <<'JSON'
{"stat":[{"name":"user>>>team-uplink","value":3},{"name":"user>>>team-uplink","value":4},{"name":"user>>>team-downlink","value":5},{"name":"user>>>team-downlink","value":"6"},{"name":"user>>>ignored-uplink","value":7},{"name":"inbound>>>api>>>traffic>>>uplink","value":99}]}
JSON
SH
    chmod +x "${fakeBin}/xray"
    XRAY_STATS_BINARY="${fakeBin}/xray"
    collectXrayTrafficStatsSnapshot '["team","missing"]' | jq -e '. == [{"account":"team","upload":7,"download":11},{"account":"missing","upload":0,"download":0}]' >/dev/null
)

runLocalTrafficAccountsBatchRegression() (
    local xrayConfig="${TMP_DIR}/traffic-xray-conf/"
    local singBoxConfig="${TMP_DIR}/traffic-sing-box-conf/"
    local accounts
    local snapshot
    local reloadMarker="${TMP_DIR}/traffic-reload"
    local originalStats
    local originalPolicy
    mkdir -p "${xrayConfig}" "${singBoxConfig}"
    configPath="${xrayConfig}"
    singBoxConfigPath="${singBoxConfig}"
    coreInstallType=1
    cat >"${xrayConfig}01_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_team_a-vless"},{"email":"admin-root"}]}},{"users":[{"name":"sub_team_b-hysteria2"}]}]}
JSON
    cat >"${singBoxConfig}02_inbounds.json" <<'JSON'
{"inbounds":[{"users":[{"username":"sub_team_a-tuic"},{"username":"ops"}]}]}
JSON
    accounts=$(collectLocalTrafficAccounts)
    jq -R -s 'split("\n") | map(select(length > 0))' <<<"${accounts}" | jq -e '. == ["admin","ops","sub_team_a","sub_team_b"]' >/dev/null

    printf '{bad-json\n' >"${singBoxConfig}03_inbounds.json"
    if collectLocalTrafficAccounts >/dev/null 2>&1; then
        return 1
    fi
    snapshot=$(collectLocalTrafficSnapshot)
    jq -e '.ok == false and (.items | length) == 0' <<<"${snapshot}" >/dev/null

    rm -f "${singBoxConfig}03_inbounds.json" "${reloadMarker}" "${xrayConfig}13_stats_api.json" "${xrayConfig}12_policy.json"
    printf '{bad-json\n' >"${xrayConfig}12_policy.json"
    if ensureXrayTrafficStatsConfig >/dev/null 2>&1; then
        return 1
    fi
    [[ ! -e "${xrayConfig}13_stats_api.json" ]]
    [[ "$(<"${xrayConfig}12_policy.json")" == "{bad-json" ]]

    cat >"${xrayConfig}13_stats_api.json" <<'JSON'
{"stats":{"old":true}}
JSON
    cat >"${xrayConfig}12_policy.json" <<'JSON'
{"policy":{"levels":{"0":{"statsUserUplink":false,"statsUserDownlink":false}},"system":{"statsInboundUplink":false,"statsInboundDownlink":false,"statsOutboundUplink":false,"statsOutboundDownlink":false}}}
JSON
    originalStats=$(<"${xrayConfig}13_stats_api.json")
    originalPolicy=$(<"${xrayConfig}12_policy.json")
    reloadCore() {
        printf 'reload\n' >"${reloadMarker}"
        return 1
    }
    if ensureXrayTrafficStatsConfig >/dev/null 2>&1; then
        return 1
    fi
    [[ -e "${reloadMarker}" ]]
    [[ "$(<"${xrayConfig}13_stats_api.json")" == "${originalStats}" ]]
    [[ "$(<"${xrayConfig}12_policy.json")" == "${originalPolicy}" ]]
)

runCheckLogBackupMissingRestoreRegression() (
    local root="${TMP_DIR}/check-log-backup-restore"
    local restoreBackupDir
    mkdir -p "${root}"
    printf 'old-policy\n' >"${root}/policy.json"

    checkLogBackupCreate restoreBackupDir "${root}/stats.json" "${root}/policy.json"
    printf 'new-stats\n' >"${root}/stats.json"
    printf 'new-policy\n' >"${root}/policy.json"

    checkLogBackupRestore "${restoreBackupDir}"
    [[ ! -e "${root}/stats.json" ]]
    [[ "$(<"${root}/policy.json")" == "old-policy" ]]
)

runDpkgInstalledPatternRegression() {
    printf 'ii  ufw                             0.36.2-6                                all          program for managing a Netfilter firewall\n' | grep -Eq '^[[:space:]]*ii[[:space:]]+ufw[[:space:]]'
    printf 'ii  netfilter-persistent            1.0.20                                   all          boot-time loader for netfilter rules\n' | grep -Eq '^[[:space:]]*ii[[:space:]]+netfilter-persistent[[:space:]]'
}

runDpkgQueryInstalledPatternRegression() {
    printf 'ii ' | grep -q '^ii'
    if printf 'un ' | grep -q '^ii'; then
        return 1
    fi
}

runRhelLikeDetectionRegression() {
    local osRelease="${TMP_DIR}/alma-os-release"
    local oldOsReleaseFile="${PADM_OS_RELEASE_FILE:-}"

    cat >"${osRelease}" <<'EOF'
NAME="AlmaLinux"
VERSION="9.7 (Moss Jungle Cat)"
ID="almalinux"
ID_LIKE="rhel centos fedora"
VERSION_ID="9.7"
EOF
    PADM_OS_RELEASE_FILE="${osRelease}"
    PADM_YUM_REPOS_DIR="${TMP_DIR}/yum.repos.d"
    initVar
    checkSystem
    [[ "${release}" == "centos" ]]
    [[ "${packageManager}" == "yum" ]]
    [[ "${centosVersion}" == "9" ]]
    [[ "${rhelLike}" == "true" ]]
    [[ "${osReleaseId}" == "almalinux" ]]
    [[ "${installType}" == *"--disablerepo=epel"* ]]
    PADM_OS_RELEASE_FILE="${oldOsReleaseFile}"
    PADM_YUM_REPOS_DIR=
}

runFedoraDetectionRegression() {
    local osRelease="${TMP_DIR}/fedora-os-release"
    local oldOsReleaseFile="${PADM_OS_RELEASE_FILE:-}"

    cat >"${osRelease}" <<'EOF'
NAME="Fedora Linux"
VERSION="43 (Cloud Edition)"
ID=fedora
VERSION_ID=43
EOF
    PADM_OS_RELEASE_FILE="${osRelease}"
    PADM_YUM_REPOS_DIR="${TMP_DIR}/fedora-yum.repos.d"
    initVar
    checkSystem
    [[ "${release}" == "fedora" ]]
    [[ "${packageManager}" == "yum" ]]
    [[ "${centosVersion}" == "43" ]]
    [[ "${rhelLike}" == "true" ]]
    [[ "${osReleaseId}" == "fedora" ]]
    [[ "${installType}" == "yum -y install" ]]
    PADM_OS_RELEASE_FILE="${oldOsReleaseFile}"
    PADM_YUM_REPOS_DIR=
}

runSubscriptionWireGuardMenuFlowRegression() (
    local oldWireGuardDir="${PADM_WIREGUARD_CONTROL_DIR:-}"
    local oldCurrentHost="${currentHost:-}"
    local oldNginxConfigPath="${nginxConfigPath:-}"
    local oldPath="${PATH}"
    local controlledCredential updatedCredential failingCredential failingCredentialJson
    local nginxFakeBin nginxTarget
    local mainStateSnapshot
    local wireGuardApplyShouldFail= installControlShouldFail= refreshControlShouldFail= serviceQueueShouldFail=
    local addSourceShouldFail= setCredentialShouldFail= restoreStateWriteShouldFail= restoreGroupsWriteShouldFail=
    local disableStateWriteShouldFail=
    local stopShouldFail=
    local stopAllowMissingBackend=
    local actions=

    # Restore the real subscription functions because earlier UI smoke tests
    # define menu stubs with global Bash function scope.
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/subscription/groups.sh"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/subscription/wireguard_control.sh"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/subscription/menu.sh"

    recordMenuAction() {
        actions+="$1"$'\n'
    }
    assertMenuAction() {
        grep -qxF "$1" <<<"${actions}"
    }
    resetMenuActions() {
        actions=
    }
    autoRead() {
        local targetVar=$3
        local input=
        IFS= read -r input || input=
        printf -v "${targetVar}" '%s' "${input}"
    }
    echoContent() { return 0; }
    menuLine() { return 0; }
    menuItem() { return 0; }
    menuReturnItem() { return 0; }
    menuDangerItem() { return 0; }
    menuClose() { return 0; }
    statusCard() { recordMenuAction "statusCard:$1"; }
    errorCard() { recordMenuAction "errorCard:$1"; }
    successCard() { recordMenuAction "successCard:$1"; }

    PADM_WIREGUARD_CONTROL_DIR="${TMP_DIR}/menu-smoke-wireguard"
    currentHost="main.example.com"
    nginxConfigPath="${TMP_DIR}/menu-smoke-nginx/"
    rm -rf "${PADM_WIREGUARD_CONTROL_DIR}" "${PADM_SUBSCRIPTION_GROUPS_DIR}"
    mkdir -p "${nginxConfigPath}"
    ensureSubscriptionGroupsState

    initSubscriptionWireGuardMain() {
        recordMenuAction initSubscriptionWireGuardMain
        local endpointHost=
        autoRead wg_main_endpoint_host "请输入主控公网地址或域名[用于被控连接 WireGuard]:" endpointHost
        subscriptionWireGuardWriteState --arg endpointHost "${endpointHost}" '.enabled = true | .role = "main" | .address = "10.77.0.1/24" | .endpoint_host = $endpointHost | .public_key = "public-key" | .listen_port = 51820 | .control_port = 39778'
        applySubscriptionWireGuardService
    }
    eval "$(declare -f disableSubscriptionWireGuardControl | sed '1s/^disableSubscriptionWireGuardControl/originalDisableSubscriptionWireGuardControl/')"
    disableSubscriptionWireGuardControl() { recordMenuAction disableSubscriptionWireGuardControl; subscriptionWireGuardWriteState '.enabled = false'; }
    installSubscriptionWireGuardTools() { return 0; }
    subscriptionWireGuardEnsureKeys() {
        mkdir -p "$(subscriptionWireGuardDir)"
        printf 'private-key\n' >"$(subscriptionWireGuardPrivateKeyFile)"
        printf 'public-key\n' >"$(subscriptionWireGuardPublicKeyFile)"
    }
    subscriptionWireGuardPublicKey() { printf 'public-key\n'; }
    applySubscriptionWireGuardService() {
        [[ "${wireGuardApplyShouldFail}" == "true" ]] && return 1
        mkdir -p "$(dirname "$(subscriptionWireGuardConfigFile)")"
        printf 'Address = %s\n' "$(subscriptionWireGuardReadState | jq -r '.address')" >"$(subscriptionWireGuardConfigFile)"
    }
    eval "$(declare -f subscriptionWireGuardWriteState | sed '1s/^subscriptionWireGuardWriteState/originalSubscriptionWireGuardWriteState/')"
    subscriptionWireGuardWriteState() {
        if [[ "${restoreStateWriteShouldFail}" == "true" && "${*: -1}" == '$previousState' ]]; then
            return 1
        fi
        if [[ "${disableStateWriteShouldFail}" == "true" && "${*: -1}" == ".enabled = false" ]]; then
            return 1
        fi
        originalSubscriptionWireGuardWriteState "$@"
    }
    eval "$(declare -f subscriptionGroupsStateWrite | sed '1s/^subscriptionGroupsStateWrite/originalSubscriptionGroupsStateWrite/')"
    subscriptionGroupsStateWrite() {
        if [[ "${restoreGroupsWriteShouldFail}" == "true" && "${*: -1}" == '$previousGroupsState' ]]; then
            return 1
        fi
        originalSubscriptionGroupsStateWrite "$@"
    }
    installSubscriptionControlService() {
        recordMenuAction installSubscriptionControlService
        [[ "${installControlShouldFail}" == "true" ]] && return 1
        return 0
    }
    refreshSubscriptionWireGuardNginxControl() {
        recordMenuAction refreshSubscriptionWireGuardNginxControl
        [[ "${refreshControlShouldFail}" == "true" ]] && return 1
        return 0
    }
    serviceQueueRestart() { recordMenuAction "serviceQueueRestart:$*"; }
    serviceQueueApply() {
        recordMenuAction serviceQueueApply
        [[ "${serviceQueueShouldFail}" == "true" ]] && return 1
        return 0
    }
    stopSubscriptionWireGuardControlService() {
        recordMenuAction "stopSubscriptionWireGuardControlService:${1:-}"
        if [[ "${stopShouldFail}" == "true" ]]; then
            [[ "${1:-}" == "true" && "${stopAllowMissingBackend}" == "true" ]] && return 0
            return 1
        fi
        return 0
    }
    eval "$(declare -f addSubscriptionSourceState | sed '1s/^addSubscriptionSourceState/originalAddSubscriptionSourceState/')"
    eval "$(declare -f setSubscriptionSourceCredential | sed '1s/^setSubscriptionSourceCredential/originalSetSubscriptionSourceCredential/')"
    addSubscriptionSourceState() {
        [[ "${addSourceShouldFail}" == "true" ]] && return 1
        originalAddSubscriptionSourceState "$@"
    }
    setSubscriptionSourceCredential() {
        [[ "${setCredentialShouldFail}" == "true" ]] && return 1
        originalSetSubscriptionSourceCredential "$@"
    }
    subscriptionRemoteControlHealthAll() { printf '[{"id":"edge-a","ok":true}]\n'; }
    subscribe() { recordMenuAction subscribe; }

    resetMenuActions
    manageSubscriptionRoleSelection <<<"1
main.example.com
3"
    assertMenuAction initSubscriptionWireGuardMain
    subscriptionWireGuardReadState | jq -e '.role == "main" and .enabled == true and .endpoint_host == "main.example.com" and .address == "10.77.0.1/24"' >/dev/null
    grep -q 'Address = 10.77.0.1/24' "$(subscriptionWireGuardConfigFile)"

    mainStateSnapshot=$(subscriptionWireGuardReadState)
    subscriptionWireGuardWriteState '.endpoint_host = ""'
    if showSubscriptionWireGuardMainCredential >/dev/null 2>&1; then
        return 1
    fi
    subscriptionWireGuardWriteState --argjson previousState "${mainStateSnapshot}" '$previousState'

    nginxFakeBin="${TMP_DIR}/wg-nginx-fail-bin"
    mkdir -p "${nginxFakeBin}"
    cat >"${nginxFakeBin}/nginx" <<'SH'
#!/usr/bin/env bash
exit 1
SH
    chmod +x "${nginxFakeBin}/nginx"
    nginxStaticPath="${TMP_DIR}/static"
    nginxTarget=$(subscriptionWireGuardNginxConfigFile)
    printf 'old config\n' >"${nginxTarget}"
    PATH="${nginxFakeBin}:${PATH}"
    if ensureSubscriptionWireGuardNginxConfig >/dev/null 2>&1; then
        PATH="${oldPath}"
        return 1
    fi
    PATH="${oldPath}"
    grep -qxF 'old config' "${nginxTarget}"
    ! find "$(dirname "${nginxTarget}")" -maxdepth 1 \( -name '.padm-control-wg.conf.nginx.*' -o -name '.padm-control-wg.conf.backup.*' \) | grep -q .

    controlledCredential=$(subscriptionWireGuardCredentialEncode controlled '{"address":"10.77.0.2/24","public_key":"controlled-pub","control_port":39778,"token":"token-a"}')
    resetMenuActions
    manageSubscriptionMultiServer <<<"2
1
${controlledCredential}
edge-a
3
5"
    subscriptionWireGuardReadState | jq -e '.peers[] | select(.id == "edge-a" and .address == "10.77.0.2/24" and .public_key == "controlled-pub")' >/dev/null
    subscriptionGroupsStateRead -e '.groups[0].sources[] | select(.id == "edge-a" and .scheme == "wireguard" and .transport == "wireguard" and .host == "10.77.0.2" and .port == 39778 and .control_token == "token-a")' >/dev/null

    failingCredential=$(subscriptionWireGuardCredentialEncode controlled '{"address":"10.77.0.4/24","public_key":"controlled-pub-fail","control_port":39778,"token":"token-fail"}')
    failingCredentialJson=$(subscriptionWireGuardCredentialDecode "${failingCredential}")
    if subscriptionWireGuardAddPeerFromCredential "bad alias" "${failingCredentialJson}" >/dev/null 2>&1; then
        return 1
    fi
    wireGuardApplyShouldFail=true
    if subscriptionWireGuardAddPeerFromCredential "edge-fail" "${failingCredentialJson}" >/dev/null 2>&1; then
        wireGuardApplyShouldFail=
        return 1
    fi
    wireGuardApplyShouldFail=
    if subscriptionGroupsStateRead -e 'any(.groups[0].sources[]?; .id == "edge-fail")' >/dev/null 2>&1; then
        return 1
    fi
    if subscriptionWireGuardReadState | jq -e 'any(.peers[]?; .id == "edge-fail")' >/dev/null 2>&1; then
        return 1
    fi

    wireGuardApplyShouldFail=true
    restoreStateWriteShouldFail=true
    resetMenuActions
    if subscriptionWireGuardAddPeerFromCredential "edge-restore-fail" "${failingCredentialJson}" >/dev/null 2>&1; then
        wireGuardApplyShouldFail=
        restoreStateWriteShouldFail=
        return 1
    fi
    wireGuardApplyShouldFail=
    restoreStateWriteShouldFail=
    assertMenuAction 'errorCard:WireGuard 被控服务器服务应用失败，且旧状态恢复失败'
    subscriptionWireGuardReadState | jq -e 'any(.peers[]?; .id == "edge-restore-fail")' >/dev/null

    addSourceShouldFail=true
    if subscriptionWireGuardAddPeerFromCredential "edge-addfail" "${failingCredentialJson}" >/dev/null 2>&1; then
        addSourceShouldFail=
        return 1
    fi
    addSourceShouldFail=
    if subscriptionGroupsStateRead -e 'any(.groups[0].sources[]?; .id == "edge-addfail")' >/dev/null 2>&1; then
        return 1
    fi

    setCredentialShouldFail=true
    if subscriptionWireGuardAddPeerFromCredential "edge-setfail" "${failingCredentialJson}" >/dev/null 2>&1; then
        setCredentialShouldFail=
        return 1
    fi
    setCredentialShouldFail=
    if subscriptionGroupsStateRead -e 'any(.groups[0].sources[]?; .id == "edge-setfail")' >/dev/null 2>&1; then
        return 1
    fi
    if subscriptionWireGuardReadState | jq -e 'any(.peers[]?; .id == "edge-setfail")' >/dev/null 2>&1; then
        return 1
    fi

    setCredentialShouldFail=true
    restoreGroupsWriteShouldFail=true
    resetMenuActions
    if subscriptionWireGuardAddPeerFromCredential "edge-groups-restore-fail" "${failingCredentialJson}" >/dev/null 2>&1; then
        setCredentialShouldFail=
        restoreGroupsWriteShouldFail=
        return 1
    fi
    setCredentialShouldFail=
    restoreGroupsWriteShouldFail=
    assertMenuAction 'errorCard:订阅来源凭据写入失败，且旧状态恢复失败'
    subscriptionGroupsStateRead -e 'any(.groups[0].sources[]?; .id == "edge-groups-restore-fail")' >/dev/null
    if subscriptionWireGuardReadState | jq -e 'any(.peers[]?; .id == "edge-groups-restore-fail")' >/dev/null 2>&1; then
        return 1
    fi

    updatedCredential=$(subscriptionWireGuardCredentialEncode controlled '{"address":"10.77.0.3/24","public_key":"controlled-pub-2","control_port":48779,"token":"token-b"}')
    resetMenuActions
    manageSubscriptionMultiServer <<<"3
${updatedCredential}
edge-a
5"
    subscriptionGroupsStateRead -e '.groups[0].sources[] | select(.id == "edge-a" and .host == "10.77.0.3" and .port == 48779 and .control_token == "token-b")' >/dev/null

    resetMenuActions
    applySubscriptionSourceToggleFixture() {
        subscriptionRequireMainRole || return 1
        local sourceId=
        local sourceAction=
        autoRead subscription_source_toggle_id "请输入被控服务器源ID:" sourceId
        autoRead subscription_source_action "请输入操作[enable/disable]:" sourceAction
        if [[ "${sourceAction}" == "enable" ]]; then
            setSubscriptionSourceEnabled "${sourceId}" true
        elif [[ "${sourceAction}" == "disable" ]]; then
            setSubscriptionSourceEnabled "${sourceId}" false
        else
            return 1
        fi
    }
    resetMenuActions
    applySubscriptionSourceToggleFixture <<<"edge-a
disable"
    subscriptionGroupsStateRead -e '.groups[0].sources[] | select(.id == "edge-a" and .enabled == false)' >/dev/null
    resetMenuActions
    applySubscriptionSourceToggleFixture <<<"edge-a
enable"
    subscriptionGroupsStateRead -e '.groups[0].sources[] | select(.id == "edge-a" and .enabled == true)' >/dev/null
    setSubscriptionSourceSyncFailure edge-a remote_error old-error
    resetMenuActions
    clearSubscriptionSourceSyncErrorMenu() {
        subscriptionRequireMainRole || return 1
        recordMenuAction clearSubscriptionSourceSyncErrorMenu
        local sourceId=
        autoRead subscription_clear_error_source "请输入要清除错误的被控服务器源ID:" sourceId
        clearSubscriptionSourceSyncError "${sourceId}"
    }
    clearSubscriptionSourceSyncErrorMenu <<<"edge-a"
    subscriptionGroupsStateRead -e '(.groups[0].sources[] | select(.id == "edge-a") | has("last_sync_error")) | not' >/dev/null
    resetMenuActions
    local multiServerStatusOutput
    multiServerStatusOutput=
    manageSubscriptionMultiServer <<<"4
5"
    assertMenuAction 'statusCard:本机主控接入凭据'

    installControlShouldFail=true
    if restartSubscriptionWireGuardControl >/dev/null 2>&1; then
        installControlShouldFail=
        return 1
    fi
    installControlShouldFail=
    wireGuardApplyShouldFail=true
    if restartSubscriptionWireGuardControl >/dev/null 2>&1; then
        wireGuardApplyShouldFail=
        return 1
    fi
    wireGuardApplyShouldFail=
    refreshControlShouldFail=true
    if restartSubscriptionWireGuardControl >/dev/null 2>&1; then
        refreshControlShouldFail=
        return 1
    fi
    refreshControlShouldFail=
    serviceQueueShouldFail=true
    if restartSubscriptionWireGuardControl >/dev/null 2>&1; then
        serviceQueueShouldFail=
        return 1
    fi
    serviceQueueShouldFail=

    resetMenuActions
    manageSubscriptionMainControlDetails <<<"5
6
7"
    assertMenuAction installSubscriptionControlService
    assertMenuAction refreshSubscriptionWireGuardNginxControl
    subscriptionWireGuardReadState | jq -e '.enabled == false' >/dev/null

    subscriptionWireGuardWriteState --argjson previousState "${mainStateSnapshot}" '$previousState'
    printf 'keep-config\n' >"$(subscriptionWireGuardConfigFile)"
    stopShouldFail=true
    resetMenuActions
    if originalDisableSubscriptionWireGuardControl >/dev/null 2>&1; then
        stopShouldFail=
        return 1
    fi
    stopShouldFail=
    assertMenuAction 'errorCard:WireGuard 控制面停用失败'
    subscriptionWireGuardReadState | jq -e '.enabled == true' >/dev/null
    grep -qxF 'keep-config' "$(subscriptionWireGuardConfigFile)"

    subscriptionWireGuardWriteState --argjson previousState "${mainStateSnapshot}" '$previousState'
    disableStateWriteShouldFail=true
    resetMenuActions
    if originalDisableSubscriptionWireGuardControl >/dev/null 2>&1; then
        disableStateWriteShouldFail=
        return 1
    fi
    disableStateWriteShouldFail=
    assertMenuAction 'errorCard:WireGuard 控制面状态写入失败'
    subscriptionWireGuardReadState | jq -e '.enabled == true' >/dev/null
    grep -q 'Address = 10.77.0.1/24' "$(subscriptionWireGuardConfigFile)"

    local restoreStopState='{"enabled":false,"role":"uninitialized","interface":"wg-padm","network":"10.77.0.0/24","listen_port":51820,"control_port":39778,"address":"","endpoint_host":"","public_key":"","peers":[]}'
    printf 'keep-config\n' >"$(subscriptionWireGuardConfigFile)"
    stopShouldFail=true
    if subscriptionWireGuardRestoreStateAndConfig "${restoreStopState}" >/dev/null 2>&1; then
        stopShouldFail=
        return 1
    fi
    stopShouldFail=
    grep -qxF 'keep-config' "$(subscriptionWireGuardConfigFile)"

    printf 'keep-config\n' >"$(subscriptionWireGuardConfigFile)"
    stopShouldFail=true
    stopAllowMissingBackend=true
    resetMenuActions
    subscriptionWireGuardRestoreStateAndConfig "${restoreStopState}" >/dev/null 2>&1 || {
        stopShouldFail=
        stopAllowMissingBackend=
        return 1
    }
    stopShouldFail=
    stopAllowMissingBackend=
    assertMenuAction 'stopSubscriptionWireGuardControlService:true'
    [[ ! -e "$(subscriptionWireGuardConfigFile)" ]]

    if [[ -n "${oldWireGuardDir}" ]]; then PADM_WIREGUARD_CONTROL_DIR="${oldWireGuardDir}"; else unset PADM_WIREGUARD_CONTROL_DIR; fi
    currentHost="${oldCurrentHost}"
    nginxConfigPath="${oldNginxConfigPath}"
)

runMenuSmokeLightRegression() {
    local actions=
    local output=
    local oldCoreInstallType="${coreInstallType:-}"
    coreInstallType=
    recordMenuAction() {
        actions+="$1"$'\n'
    }
    assertMenuAction() {
        grep -qxF "$1" <<<"${actions}"
    }
    resetMenuActions() {
        actions=
    }
    menuLine() { output+="$*"$'\n'; }
    menuItem() { output+="$2 $3"$'\n'; }
    menuRecommendedItem() { output+="$2 $3"$'\n'; }
    menuReturnItem() { output+="$2 $3"$'\n'; }
    menuClose() { return 0; }
    statusCard() { recordMenuAction "statusCard:$1"; }
    errorCard() { recordMenuAction "errorCard:$1"; }
    successCard() { recordMenuAction "successCard:$1"; }
    autoRead() {
        local targetVar=$3
        local input=
        IFS= read -r input || input=
        printf -v "${targetVar}" '%s' "${input}"
    }
    selectCoreInstall() { recordMenuAction selectCoreInstall; }
    manageFail2ban() { recordMenuAction manageFail2ban; }
    updatePadm() { recordMenuAction "updatePadm:$*"; }
    showPadmScriptInstallStatus() { recordMenuAction showPadmScriptInstallStatus; }
    bbrInstall() { recordMenuAction bbrInstall; }

    installMenu <<<"6"
    assertMenuAction selectCoreInstall
    grep -q "不知道怎么选时，建议直接选 1" <<<"${output}"
    grep -q "entry 是客户端连接地址" <<<"${output}"

    resetMenuActions
    installXray() { recordMenuAction installXray; }
    installXrayService() { recordMenuAction installXrayService; }
    initXrayConfig() { recordMenuAction initXrayConfig; }
    cleanUp() { recordMenuAction cleanUp; }
    checkGFWStatue() { recordMenuAction checkGFWStatue; }
    showAccounts() { recordMenuAction showAccounts; }
    installTools() { recordMenuAction installTools; }
    readLastInstallationConfig() { recordMenuAction readLastInstallationConfig; }
    unInstallSubscribe() { recordMenuAction unInstallSubscribe; }
    handleNginx() { recordMenuAction "handleNginx:$*"; }
    serviceQueueRestart() { recordMenuAction "serviceQueueRestart:$*"; }
    serviceQueueApply() { recordMenuAction serviceQueueApply; }
    subscriptionWireGuardControlEnabled() { return 0; }
    refreshSubscriptionWireGuardNginxControl() { recordMenuAction refreshSubscriptionWireGuardNginxControl; }
    installXrayReality
    assertMenuAction 'handleNginx:stop'
    assertMenuAction refreshSubscriptionWireGuardNginxControl
    assertMenuAction serviceQueueApply
    resetMenuActions
    output=
    systemScriptMenu <<<"3"
    assertMenuAction manageFail2ban
    grep -q "Fail2ban 防护" <<<"${output}"
    resetMenuActions
    systemScriptMenu <<<"1"
    assertMenuAction 'updatePadm:1'
    resetMenuActions
    systemScriptMenu <<<"2"
    assertMenuAction showPadmScriptInstallStatus
    resetMenuActions
    systemScriptMenu <<<"4"
    assertMenuAction bbrInstall
    [[ "$(protocolMenuDescription 10)" == "TLS 指纹抗性优先；sing-box / tcp / tls" ]]
    [[ "$(protocolMenuDescription 13)" == "sing-box AnyTLS 按需；sing-box / tcp / tls" ]]
    coreInstallType="${oldCoreInstallType}"
}

runMenuSmokeRegression() {
    local actions=
    local oldConfigPath="${configPath:-}"
    local oldCoreInstallType="${coreInstallType:-}"
    local oldRealityPageSize="${REALITY_TARGET_PAGE_SIZE:-}"
    local serviceQueueShouldFail=
    local wgChoice
    local wgAction
    coreInstallType=${coreInstallType:-}

    recordMenuAction() {
        actions+="$1"$'\n'
    }
    assertMenuAction() {
        grep -qxF "$1" <<<"${actions}"
    }
    resetMenuActions() {
        actions=
    }
    menu() { recordMenuAction menu; }
    uiStyle() { printf '%s' "$2"; }
    menuLine() { output+="$*"$'\n'; }
    menuMutedLine() { output+="$*"$'\n'; }
    menuItem() { output+="$2 $3"$'\n'; }
    menuDangerItem() { output+="$2 $3"$'\n'; }
    menuClose() { return 0; }
    menuRecommendedItem() { output+="$2 $3"$'\n'; }
    menuReturnItem() { output+="$2 $3"$'\n'; }
    statusCard() { recordMenuAction "statusCard:$1"; }
    errorCard() { recordMenuAction "errorCard:$1"; }
    successCard() { recordMenuAction "successCard:$1"; }
    progressCard() { return 0; }
    showInstallStatus() { return 0; }
    checkWgetShowProgress() { return 0; }
    mkdirTools() { return 0; }
    aliasInstall() { return 0; }
    getScriptVersion() { printf 'test\n'; }
    autoRead() {
        local targetVar=$3
        local input=
        IFS= read -r input || input=
        printf -v "${targetVar}" '%s' "${input}"
    }
    autoConfirm() {
        local targetVar=$4
        local input=
        IFS= read -r input || input=$3
        [[ -z "${input}" ]] && input=$3
        printf -v "${targetVar}" '%s' "${input}"
    }
    selectCoreInstall() { recordMenuAction selectCoreInstall; }
    manageXHTTP() { recordMenuAction manageXHTTP; }
    manageHysteria() { recordMenuAction manageHysteria; }
    manageTuic() { recordMenuAction manageTuic; }
    addCorePort() { recordMenuAction addCorePort; }
    manageCDN() { recordMenuAction manageCDN; }
    readInstallProtocolType() { coreInstallType=1; }
    readConfigHostPathUUID() {
        realityTargetHost=www.ibm.com
        realityTargetPort=443
        realitySNI=www.ibm.com
    }
    readCustomPort() { return 0; }
    readSingBoxConfig() { return 0; }
    currentProtocolHasAny() { return 0; }
    regenerateRealityProfile() { recordMenuAction regenerateRealityProfile; }
    configureRealityStreamSplit() { recordMenuAction configureRealityStreamSplit; }
    showRealityStreamSplitStatus() { recordMenuAction showRealityStreamSplitStatus; }
    disableRealityStreamSplit() { recordMenuAction disableRealityStreamSplit; }
    changeInstalledRealityTarget() { recordMenuAction "changeReality:$*"; }
    subscribe() { recordMenuAction subscribe; }
    showSubscriptionServiceStatus() { recordMenuAction showSubscriptionServiceStatus; }
    showSubscriptionSources() { recordMenuAction showSubscriptionSources; }
    showSubscriptionSourceControlUrls() { recordMenuAction showSubscriptionSourceControlUrls; }
    showSubscriptionSourceSyncResults() { recordMenuAction showSubscriptionSourceSyncResults; }
    showSubscriptionWireGuardMainCredential() { recordMenuAction showSubscriptionWireGuardMainCredential; }
    showSubscriptionWireGuardControlledCredential() { recordMenuAction showSubscriptionWireGuardControlledCredential; }
    importSubscriptionWireGuardMainCredential() { recordMenuAction importSubscriptionWireGuardMainCredential; }
    initSubscriptionWireGuardMain() {
        recordMenuAction initSubscriptionWireGuardMain
        subscriptionWireGuardReadState() {
            jq -n '{enabled:true, role:"main", address:"10.77.0.1/24", peers:[{id:"edge-a"}]}'
        }
    }
    initSubscriptionWireGuardControlled() {
        recordMenuAction initSubscriptionWireGuardControlled
        subscriptionWireGuardReadState() {
            jq -n '{enabled:true, role:"controlled", address:"10.77.0.2/24", peers:[{id:"main"}]}'
        }
    }
    showSubscriptionWireGuardPeers() { recordMenuAction showSubscriptionWireGuardPeers; }
    restartSubscriptionWireGuardControl() { recordMenuAction restartSubscriptionWireGuardControl; }
    disableSubscriptionWireGuardControl() { recordMenuAction disableSubscriptionWireGuardControl; }
    showSubscriptionWireGuardStatus() { recordMenuAction showSubscriptionWireGuardStatus; }
    subscriptionWireGuardReadState() {
        jq -n '{enabled:false, role:"uninitialized", address:"", peers:[]}'
    }
    setMenuSmokeRole() {
        local role=$1
        case "${role}" in
        main)
            subscriptionWireGuardReadState() {
                jq -n '{enabled:true, role:"main", address:"10.77.0.1/24", peers:[{id:"edge-a"}]}'
            }
            ;;
        controlled)
            subscriptionWireGuardReadState() {
                jq -n '{enabled:true, role:"controlled", address:"10.77.0.2/24", peers:[{id:"main"}]}'
            }
            ;;
        *)
            subscriptionWireGuardReadState() {
                jq -n '{enabled:false, role:"uninitialized", address:"", peers:[]}'
            }
            ;;
        esac
    }
    eval "$(declare -f subscriptionGroupsStateRead | sed '1s/^subscriptionGroupsStateRead/originalSubscriptionGroupsStateRead/')"
    subscriptionWireGuardConfigFile() { echo "${TMP_DIR}/menu-smoke-wireguard/wg-padm.conf"; }
    readNginxSubscribe() { subscribePort=39778; subscribeDomain=main.example.com; subscribeType=https; }
    showAccounts() { recordMenuAction showAccounts; }
    installSubscribe() { recordMenuAction installSubscribe; }
    runSubscriptionGroupSync() { recordMenuAction "runSubscriptionGroupSync:$*"; }
    subscriptionSyncPlan() { recordMenuAction subscriptionSyncPlan; jq -n '{create:[], remove:[]}'; }
    subscriptionRemoteControlHealthAll() { recordMenuAction subscriptionRemoteControlHealthAll; jq -n '[{id:"edge-a", ok:true}]'; }
    subscriptionRemoteSyncPlan() { recordMenuAction subscriptionRemoteSyncPlan; jq -n '[{source_id:"edge-a", status:"success", response:{plan:{create:[], remove:[]}}}]'; }
    subscriptionQuotaDryRunPlan() { recordMenuAction subscriptionQuotaDryRunPlan; printf '[]\n'; }
    showSubscriptionLocalSyncPlan() { recordMenuAction showSubscriptionLocalSyncPlan; subscriptionSyncPlan >/dev/null; }
    showSubscriptionRemoteHealthPlan() { recordMenuAction showSubscriptionRemoteHealthPlan; subscriptionRemoteControlHealthAll >/dev/null; }
    showSubscriptionRemoteSyncPlan() { recordMenuAction showSubscriptionRemoteSyncPlan; subscriptionRemoteSyncPlan >/dev/null; }
    showSubscriptionQuotaPlan() { recordMenuAction showSubscriptionQuotaPlan; subscriptionQuotaDryRunPlan >/dev/null; }
    executeSubscriptionQuotaPlanMenu() { recordMenuAction executeSubscriptionQuotaPlanMenu; }
    setSubscriptionSourceControlTokenMenu() {
        subscriptionRequireMainRole || return 1
        recordMenuAction setSubscriptionSourceControlTokenMenu
    }
    assertToggleSubscriptionSourceMenuRequiresMainRole() {
        subscriptionRequireMainRole || return 1
    }
    clearSubscriptionSourceSyncErrorMenu() {
        subscriptionRequireMainRole || return 1
        recordMenuAction clearSubscriptionSourceSyncErrorMenu
    }
    showAdminSubscriptionTraffic() { recordMenuAction showAdminSubscriptionTraffic; }
    collectSubscriptionTraffic() { recordMenuAction collectSubscriptionTraffic; return 0; }
    showSubscriptionTrafficOverview() { recordMenuAction showSubscriptionTrafficOverview; }
    showSubscriptionGroupsStateSummary() { recordMenuAction showSubscriptionGroupsStateSummary; }
    createSubscriptionGroupsBackupMenu() { recordMenuAction createSubscriptionGroupsBackupMenu; }
    showSubscriptionGroupsBackups() { recordMenuAction showSubscriptionGroupsBackups; }
    restoreSubscriptionGroupsBackupMenu() { recordMenuAction restoreSubscriptionGroupsBackupMenu; }
    resetSubscriptionGroupsStateMenu() { recordMenuAction resetSubscriptionGroupsStateMenu; }
    refreshSubscriptionGroupSyncCron() { recordMenuAction refreshSubscriptionGroupSyncCron; }
    installUserCrontabContent() { return 0; }
    xrayInstalled() { return 0; }
    singBoxInstalled() { return 0; }
    xrayRunning() { return 0; }
    singBoxRunning() { return 1; }
    validateXrayConfigWithBinary() { return 0; }
    singBoxConfigInstalled() { return 1; }
    crontab() {
        recordMenuAction "crontab:$*"
        if [[ "${1:-}" == "-l" ]]; then
            printf '0 * * * * SyncSubscriptionGroups\n'
            return 0
        fi
        return 1
    }
    coreReleaseTags() { recordMenuAction "unexpected-network-version-fetch"; return 1; }
    serviceQueueStart() { recordMenuAction "serviceQueueStart:$*"; }
    serviceQueueStop() { recordMenuAction "serviceQueueStop:$*"; }
    serviceQueueRestart() { recordMenuAction "serviceQueueRestart:$*"; }
    serviceQueueApply() {
        recordMenuAction serviceQueueApply
        [[ "${serviceQueueShouldFail}" == "true" ]] && return 1
        return 0
    }
    subscriptionGroupsStateRead() {
        if [[ "$1" == "-r" ]]; then
            recordMenuAction "subscriptionGroupsStateRead:$*"
        fi
        originalSubscriptionGroupsStateRead "$@"
    }
    local geoOverviewDir="${TMP_DIR}/menu-smoke-xray-geo"
    mkdir -p "${geoOverviewDir}/conf"
    printf '#!/usr/bin/env bash\ncase "$1" in --version) printf "Xray 1.0.0 test\\n" ;; -test) exit 0 ;; *) exit 1 ;; esac\n' >"${geoOverviewDir}/xray"
    chmod +x "${geoOverviewDir}/xray"
    local singBoxOverviewDir="${TMP_DIR}/menu-smoke-singbox-overview"
    mkdir -p "${singBoxOverviewDir}"
    printf '#!/usr/bin/env bash\ncase "$1" in version) printf "sing-box version 1.0.0\\n" ;; *) exit 1 ;; esac\n' >"${singBoxOverviewDir}/sing-box"
    chmod +x "${singBoxOverviewDir}/sing-box"
    printf 'geoip' >"${geoOverviewDir}/geoip.dat"
    printf 'geosite' >"${geoOverviewDir}/geosite.dat"
    printf 'v20260513' >"${geoOverviewDir}/geo.version"
    local output=
    PADM_XRAY_DIR="${geoOverviewDir}" PADM_SINGBOX_BINARY="${singBoxOverviewDir}/sing-box" showCoreStatusOverview
    [[ "${output}" == *"Xray Geo:"*"版本 v20260513"* ]]
    customSingBoxInstall() { recordMenuAction "customSingBoxInstall:$*"; }
    installMenu <<<"7"
    assertMenuAction menu
    resetMenuActions
    installMenu <<<"4"
    assertMenuAction "customSingBoxInstall:10"
    resetMenuActions
    installMenu <<<"5"
    assertMenuAction selectCoreInstall
    resetMenuActions
    protocolEntryMenu <<<"7"
    assertMenuAction menu
    resetMenuActions
    output=
    protocolEntryMenu <<<"1
2
9"
    grep -q "实时查看目标质量" <<<"${output}"
    if assertMenuAction 'errorCard:选择错误'; then
        printf 'menu-smoke failed: protocol entry reality target flow returned unexpected selection error\n' >&2
        return 1
    fi

    configPath="${TMP_DIR}/menu-smoke-xray/"
    coreInstallType=1
    ensureSubscriptionGroupsState
    setMenuSmokeRole uninitialized
    resetMenuActions
    output=
    manageSubscription <<<"3" || true
    assertMenuAction menu
    grep -q "当前服务器角色：.*未配置主控/被控" <<<"${output}"
    grep -q "这台作为主控" <<<"${output}"
    grep -q "这台作为被控" <<<"${output}"
    if grep -q "快速开始" <<<"${output}" || grep -q "发布订阅" <<<"${output}" || grep -q "多服务器协同" <<<"${output}" || grep -q "高级诊断" <<<"${output}"; then
        printf 'menu-smoke failed: uninitialized top-level still shows post-init entries\n' >&2
        return 1
    fi
    resetMenuActions
    output=
    manageSubscriptionRoleSelection <<<"1
3"
    assertMenuAction initSubscriptionWireGuardMain
    assertMenuAction showSubscriptionWireGuardMainCredential
    assertMenuAction showSubscriptionRemoteHealthPlan
    assertMenuAction showSubscriptionRemoteSyncPlan
    resetMenuActions
    output=
    manageSubscriptionRoleSelection <<<"2"
    assertMenuAction initSubscriptionWireGuardControlled
    assertMenuAction importSubscriptionWireGuardMainCredential
    assertMenuAction showSubscriptionWireGuardControlledCredential
    assertMenuAction showSubscriptionWireGuardStatus
    setMenuSmokeRole main
    resetMenuActions
    output=
    manageSubscription <<<"4"
    grep -q "发布订阅" <<<"${output}"
    grep -q "多服务器协同" <<<"${output}"
    grep -q "主控维护与排障" <<<"${output}"
    if grep -q "我自己用" <<<"${output}" || grep -q "给别人用" <<<"${output}" || grep -q "运行与维护" <<<"${output}" || grep -q "高级诊断" <<<"${output}" || grep -q "被控维护与排障" <<<"${output}"; then
        printf 'menu-smoke failed: main top-level still shows removed or controlled entries\n' >&2
        return 1
    fi
    assertMenuAction menu
    resetMenuActions
    output=
    manageSubscriptionPublishSubscriptions <<<"7"
    grep -q "安装/更新订阅服务" <<<"${output}"
    grep -q "刷新并查看我的订阅链接" <<<"${output}"
    grep -q "新建并发布订阅" <<<"${output}"
    grep -q "查看并处理已有订阅" <<<"${output}"
    grep -q "查看我的可用服务器" <<<"${output}"
    grep -q "查看我的流量" <<<"${output}"
    if grep -q "同步订阅变更" <<<"${output}" || grep -q "预览同步变更" <<<"${output}"; then
        printf 'menu-smoke failed: publish menu still shows batch sync entries\n' >&2
        return 1
    fi
    resetMenuActions
    manageSubscriptionPublishSubscriptions <<<"1
7"
    assertMenuAction installSubscribe
    assertMenuAction showSubscriptionServiceStatus
    resetMenuActions
    manageSubscriptionPublishSubscriptions <<<"2
7"
    assertMenuAction subscribe
    resetMenuActions
    manageSubscriptionPublishSubscriptions <<<"4
7" || true
    subscriptionGroupsStateRead -e '.groups[] | select(.id == "default") | ((.user_groups // []) | length) == 0' >/dev/null
    resetMenuActions
    manageSubscriptionPublishSubscriptions <<<"3
demo-user
Demo User
main
0
n
7"
    subscriptionGroupsStateRead -e '.groups[] | select(.id == "default") | any(.user_groups[]?; .id == "demo-user" and .name == "Demo User")' >/dev/null
    resetMenuActions
    output=
    manageSubscriptionPublishSubscriptions <<<"4
demo-user
3
9
7"
    grep -q "查看并处理已有订阅" <<<"${output}"
    grep -q "查看当前用量" <<<"${output}"
    resetMenuActions
    subscriptionGroupsStateWrite --arg groupId "default" '.groups |= map(if .id == $groupId then .sync.enabled = false else . end)'
    manageSubscriptionPublishSubscriptions <<<"3
team-a
Team A
*
0
n
n
7"
    assertMenuAction 'statusCard:稍后同步'
    subscriptionGroupsStateRead -e '.groups[] | select(.id == "default") | any(.user_groups[]?; .id == "team-a" and .name == "Team A")' >/dev/null
    subscriptionGroupsStateRead -e '.groups[] | select(.id == "default") | .sync.enabled == false' >/dev/null
    if assertMenuAction 'runSubscriptionGroupSync:skip-subscribe-refresh'; then
        printf 'menu-smoke failed: team-a should stay deferred when sync-now is disabled\n' >&2
        return 1
    fi
    resetMenuActions
    rm -rf "${PADM_SUBSCRIPTION_GROUPS_DIR}"
    ensureSubscriptionGroupsState
    subscriptionGroupsStateWrite --arg groupId "default" '.groups |= map(if .id == $groupId then .sync.enabled = false else . end)'
    manageSubscriptionPublishSubscriptions <<<"3
team-b
Team B
main
0


7"
    assertMenuAction refreshSubscriptionGroupSyncCron
    assertMenuAction 'runSubscriptionGroupSync:skip-subscribe-refresh'
    subscriptionGroupsStateRead -e '.groups[] | select(.id == "default") | .sync.enabled == true' >/dev/null
    resetMenuActions
    output=
    manageSubscriptionMultiServer <<<"5"
    grep -q "主控建链向导" <<<"${output}"
    grep -q "添加/移除被控服务器" <<<"${output}"
    grep -q "更新被控服务器凭据" <<<"${output}"
    grep -q "查看协同状态" <<<"${output}"
    if grep -q "多服务器细项" <<<"${output}"; then
        printf 'menu-smoke failed: main multi-server still shows advanced submenu\n' >&2
        return 1
    fi
    resetMenuActions
    manageSubscriptionMultiServer <<<"1
3
5"
    assertMenuAction initSubscriptionWireGuardMain
    resetMenuActions
    manageSubscriptionMultiServer <<<"3
5"
    assertMenuAction setSubscriptionSourceControlTokenMenu
    resetMenuActions
    manageSubscriptionMultiServer <<<"4
5"
    assertMenuAction showSubscriptionWireGuardMainCredential
    assertMenuAction showSubscriptionSources
    assertMenuAction showSubscriptionRemoteHealthPlan
    assertMenuAction subscriptionRemoteControlHealthAll
    assertMenuAction showSubscriptionSourceSyncResults
    resetMenuActions
    output=
    manageSubscriptionMainMaintenance <<<"9"
    grep -q "刷新并查看运行总览" <<<"${output}"
    grep -q "立即执行同步" <<<"${output}"
    grep -q "查看运行状态" <<<"${output}"
    grep -q "用量与限额" <<<"${output}"
    grep -q "自动同步设置" <<<"${output}"
    grep -q "状态备份与恢复" <<<"${output}"
    grep -q "控制面与连接细节" <<<"${output}"
    grep -q "清除同步错误" <<<"${output}"
    if grep -q "兼容 WireGuard 控制面" <<<"${output}"; then
        printf 'menu-smoke failed: main maintenance still shows compatibility entry\n' >&2
        return 1
    fi
    resetMenuActions
    manageSubscriptionMainMaintenance <<<"1
9"
    assertMenuAction collectSubscriptionTraffic
    assertMenuAction showSubscriptionTrafficOverview
    resetMenuActions
    manageSubscriptionMainMaintenance <<<"2
9"
    assertMenuAction 'runSubscriptionGroupSync:skip-subscribe-refresh'
    if assertMenuAction 'runSubscriptionGroupSync:'; then
        printf 'menu-smoke failed: main maintenance sync still triggers publish refresh path\n' >&2
        return 1
    fi
    resetMenuActions
    manageSubscriptionMainMaintenance <<<"3
9"
    assertMenuAction showSubscriptionGroupsStateSummary
    assertMenuAction showSubscriptionLocalSyncPlan
    assertMenuAction subscriptionSyncPlan
    assertMenuAction showSubscriptionRemoteSyncPlan
    assertMenuAction subscriptionRemoteSyncPlan
    assertMenuAction showSubscriptionSourceSyncResults
    resetMenuActions
    manageTrafficAndQuota <<<"1
8"
    assertMenuAction collectSubscriptionTraffic
    assertMenuAction showSubscriptionTrafficOverview
    resetMenuActions
    manageTrafficAndQuota <<<"6
8"
    assertMenuAction showSubscriptionQuotaPlan
    assertMenuAction subscriptionQuotaDryRunPlan
    resetMenuActions
    manageTrafficAndQuota <<<"7
8"
    assertMenuAction executeSubscriptionQuotaPlanMenu
    resetMenuActions
    output=
    manageSubscriptionMainMaintenance <<<"5
11
9"
    grep -q "开启/关闭自动同步" <<<"${output}"
    grep -q "查看定时任务" <<<"${output}"
    resetMenuActions
    manageSubscriptionSyncSettings <<<"5
11"
    assertMenuAction 'runSubscriptionGroupSync:skip-subscribe-refresh'
    if assertMenuAction 'runSubscriptionGroupSync:'; then
        printf 'menu-smoke failed: sync settings immediate sync still triggers publish refresh path\n' >&2
        return 1
    fi
    resetMenuActions
    output=
    manageSubscriptionSyncSettings <<<"10
11"
    assertMenuAction 'crontab:-l'
    grep -q 'SyncSubscriptionGroups' <<<"${output}"
    resetMenuActions
    output=
    manageSubscriptionMainMaintenance <<<"6
6
9"
    grep -q "查看当前状态摘要" <<<"${output}"
    grep -q "重建订阅状态" <<<"${output}"
    resetMenuActions
    manageSubscriptionMainControlDetails <<<"1
7"
    assertMenuAction showSubscriptionWireGuardMainCredential
    for wgAction in "2:showSubscriptionWireGuardPeers" "4:showSubscriptionSourceControlUrls" "5:restartSubscriptionWireGuardControl" "6:disableSubscriptionWireGuardControl"; do
        wgChoice=${wgAction%%:*}
        resetMenuActions
        manageSubscriptionMainControlDetails <<<"${wgChoice}
7"
        assertMenuAction "${wgAction#*:}"
    done
    resetMenuActions
    manageSubscriptionMainControlDetails <<<"3
7"
    assertMenuAction showSubscriptionRemoteHealthPlan
    assertMenuAction subscriptionRemoteControlHealthAll
    resetMenuActions
    manageSubscriptionStateBackups <<<"1
6"
    assertMenuAction showSubscriptionGroupsStateSummary
    resetMenuActions
    manageSubscriptionStateBackups <<<"2
6"
    assertMenuAction createSubscriptionGroupsBackupMenu
    resetMenuActions
    manageSubscriptionStateBackups <<<"3
6"
    assertMenuAction showSubscriptionGroupsBackups
    resetMenuActions
    manageSubscriptionStateBackups <<<"4
6"
    assertMenuAction restoreSubscriptionGroupsBackupMenu
    resetMenuActions
    manageSubscriptionStateBackups <<<"5
6"
    assertMenuAction resetSubscriptionGroupsStateMenu
    setMenuSmokeRole controlled
    resetMenuActions
    output=
    manageSubscription <<<"4"
    grep -q "接入主控" <<<"${output}"
    grep -q "查看本机状态" <<<"${output}"
    grep -q "被控维护与排障" <<<"${output}"
    if grep -q "发布订阅" <<<"${output}" || grep -q "多服务器协同" <<<"${output}" || grep -q "主控维护与排障" <<<"${output}"; then
        printf 'menu-smoke failed: controlled top-level still shows main entries\n' >&2
        return 1
    fi
    assertMenuAction menu
    resetMenuActions
    manageSubscriptionControlledHome <<<"1
main-credential
4"
    assertMenuAction initSubscriptionWireGuardControlled
    assertMenuAction importSubscriptionWireGuardMainCredential
    assertMenuAction showSubscriptionWireGuardControlledCredential
    assertMenuAction showSubscriptionWireGuardStatus
    resetMenuActions
    output=
    manageSubscriptionControlledHome <<<"2
4"
    grep -q "当前服务器角色：" <<<"${output}"
    assertMenuAction showSubscriptionWireGuardControlledCredential
    assertMenuAction showSubscriptionWireGuardStatus
    assertMenuAction showSubscriptionSourceSyncResults
    resetMenuActions
    output=
    manageSubscriptionControlledMaintenance <<<"5"
    grep -q "导入/更新主控接入凭据" <<<"${output}"
    grep -q "查看控制面与 Peer 细节" <<<"${output}"
    grep -q "重写配置并重启被控控制面" <<<"${output}"
    grep -q "关闭被控控制面" <<<"${output}"
    if grep -q "查看本机主控接入凭据" <<<"${output}" || grep -q "初始化本机为主控" <<<"${output}"; then
        printf 'menu-smoke failed: controlled maintenance still shows main-only actions\n' >&2
        return 1
    fi
    resetMenuActions
    manageSubscriptionControlledMaintenance <<<"1
5"
    assertMenuAction importSubscriptionWireGuardMainCredential
    resetMenuActions
    manageSubscriptionControlledMaintenance <<<"2
5"
    assertMenuAction showSubscriptionWireGuardStatus
    assertMenuAction showSubscriptionWireGuardPeers
    resetMenuActions
    manageSubscriptionControlledMaintenance <<<"3
5"
    assertMenuAction restartSubscriptionWireGuardControl
    resetMenuActions
    manageSubscriptionControlledMaintenance <<<"4
5"
    assertMenuAction disableSubscriptionWireGuardControl
    resetMenuActions
    addSubscribeMenu <<<"3" || true
    assertMenuAction 'errorCard:当前机器已初始化为被控'
    resetMenuActions
    setSubscriptionSourceControlTokenMenu <<<"" || true
    assertMenuAction 'errorCard:当前机器已初始化为被控'
    resetMenuActions
    assertToggleSubscriptionSourceMenuRequiresMainRole <<<"" || true
    assertMenuAction 'errorCard:当前机器已初始化为被控'
    resetMenuActions
    clearSubscriptionSourceSyncErrorMenu <<<"" || true
    assertMenuAction 'errorCard:当前机器已初始化为被控'
    resetMenuActions
    manageSubscriptionMainHome <<<"4" || true
    assertMenuAction 'errorCard:当前机器已初始化为被控'
    resetMenuActions
    setMenuSmokeRole main
    manageSubscriptionControlledHome <<<"4" || true
    assertMenuAction 'errorCard:当前机器已初始化为主控'
    resetMenuActions
    output=
    manageSubscriptionPublishSubscriptions <<<"7"
    grep -q "安装/更新订阅服务" <<<"${output}"
    resetMenuActions
    output=
    manageSubscriptionPublishSubscriptions <<<"7"
    grep -q "查看并处理已有订阅" <<<"${output}"
    resetMenuActions
    output=
    manageTrafficAndQuota <<<"8"
    grep -q "查看用量总览" <<<"${output}"
    resetMenuActions
    setMenuSmokeRole controlled
    manageTrafficAndQuota <<<"8" || true
    assertMenuAction 'errorCard:当前机器已初始化为被控'
    resetMenuActions
    manageSubscriptionStateBackups <<<"6" || true
    assertMenuAction 'errorCard:当前机器已初始化为被控'
    resetMenuActions
    manageSubscriptionSyncSettings <<<"11" || true
    assertMenuAction 'errorCard:当前机器已初始化为被控'
    resetMenuActions
    setMenuSmokeRole uninitialized
    manageTrafficAndQuota <<<"8" || true
    assertMenuAction 'errorCard:当前机器还没完成角色初始化'
    resetMenuActions
    manageSubscriptionStateBackups <<<"6" || true
    assertMenuAction 'errorCard:当前机器还没完成角色初始化'
    resetMenuActions
    manageSubscriptionSyncSettings <<<"11" || true
    assertMenuAction 'errorCard:当前机器还没完成角色初始化'
    resetMenuActions
    coreVersionManageMenu <<<"6"
    assertMenuAction menu
    if assertMenuAction unexpected-network-version-fetch; then
        printf 'menu-smoke failed: core menu fetched release versions while rendering overview\n' >&2
        return 1
    fi
    resetMenuActions
    coreConfigMaintenanceMenu <<<"3"
    assertMenuAction 'statusCard:Xray 兼容体检'
    resetMenuActions
    coreConfigMaintenanceMenu <<<"4"
    assertMenuAction 'statusCard:Xray 预发布兼容检查'
    resetMenuActions
    coreConfigMaintenanceMenu <<<"6"
    assertMenuAction 'statusCard:sing-box 兼容体检'
    if assertMenuAction unexpected-network-version-fetch; then
        printf 'menu-smoke failed: core maintenance fetched release versions while rendering compatibility entries\n' >&2
        return 1
    fi
    resetMenuActions
    coreServiceControlMenu xray <<<"3"
    assertMenuAction 'serviceQueueRestart:xray'
    assertMenuAction serviceQueueApply
    serviceQueueShouldFail=true
    resetMenuActions
    if coreServiceControlMenu sing-box <<<"3" >/dev/null 2>&1; then
        serviceQueueShouldFail=
        return 1
    fi
    serviceQueueShouldFail=
    assertMenuAction 'serviceQueueRestart:sing-box'
    assertMenuAction serviceQueueApply
    assertMenuAction 'errorCard:sing-box 服务重启失败'

    configPath="${oldConfigPath}"
    coreInstallType="${oldCoreInstallType}"
    if [[ -n "${oldRealityPageSize}" ]]; then
        REALITY_TARGET_PAGE_SIZE="${oldRealityPageSize}"
    else
        unset REALITY_TARGET_PAGE_SIZE
    fi
}

runInstallToolsCertificateDependencyRegression() {
    local oldHome="${HOME}"
    local oldSelect="${selectCustomInstallType:-}"
    local oldRealityDomain="${realityOnlyWithDomain:-}"
    local statusLog="${TMP_DIR}/install-tools-cert-status.log"
    local fakeHome="${TMP_DIR}/install-tools-cert-home"
    local oldStatusLog="${REGRESSION_STATUS_CARD_LOG:-}"
    local oldInstallLog="${PADM_INSTALL_LOG:-}"
    mkdir -p "${fakeHome}/.acme.sh"
    printf '#!/usr/bin/env sh\n' >"${fakeHome}/.acme.sh/acme.sh"
    HOME="${fakeHome}"
    export REGRESSION_STATUS_CARD_LOG="${statusLog}"
    PADM_INSTALL_LOG="${TMP_DIR}/install-tools-install.log"
    : >"${statusLog}"
    release=debian
    rhelLike=false
    upgrade=true
    updateReleaseInfoChange=true
    packageManager=apt
    selectCustomInstallType=",7,"
    realityOnlyWithDomain=
    command() {
        if [[ "$1" == "-v" && "$2" == "qrencode" ]]; then
            return 0
        fi
        builtin command "$@"
    }
    runWithTimeout() { return 0; }
    runPackageCommandWithProgress() { return 0; }
    waitAptProcess() { return 0; }
    installBasePackages() { return 0; }
    installNginxTools() { printf 'unexpected-nginx\n' >>"${statusLog}"; return 1; }
    nginx() { return 0; }
    protocolSelectionSkipsNginx() { return 0; }
    beginPackageInstallTransaction() { PADM_PACKAGE_TRANSACTION_STARTED=; }
    completePackageInstallTransaction() { return 0; }

    installTools 1
    grep -q "跳过安装 acme.sh" "${statusLog}"

    : >"${statusLog}"
    realityOnlyWithDomain=true
    installTools 1
    ! grep -q "跳过安装 acme.sh" "${statusLog}"

    if [[ -n "${oldStatusLog}" ]]; then
        REGRESSION_STATUS_CARD_LOG="${oldStatusLog}"
    else
        unset REGRESSION_STATUS_CARD_LOG
    fi
    if [[ -n "${oldInstallLog}" ]]; then
        PADM_INSTALL_LOG="${oldInstallLog}"
    else
        unset PADM_INSTALL_LOG
    fi
    HOME="${oldHome}"
    selectCustomInstallType="${oldSelect}"
    realityOnlyWithDomain="${oldRealityDomain}"
}

runInstallToolsAcmeResultFailureRegression() {
    (
        local oldHome="${HOME}"
        local oldSelect="${selectCustomInstallType:-}"
        local oldErrorLog="${REGRESSION_ERROR_CARD_LOG:-}"
        local oldStatusLog="${REGRESSION_STATUS_CARD_LOG:-}"
        local oldTmpDir="${TMPDIR:-}"
        local fakeHome="${TMP_DIR}/install-tools-acme-result-home"
        local tmpRoot="${TMP_DIR}/install-tools-acme-result-tmp"
        local errorLog="${TMP_DIR}/install-tools-acme-result-error.log"
        local statusLog="${TMP_DIR}/install-tools-acme-result-status.log"
        local installStatus

        rm -rf "${fakeHome}" "${tmpRoot}"
        mkdir -p "${fakeHome}" "${tmpRoot}"
        HOME="${fakeHome}"
        TMPDIR="${tmpRoot}"
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        export REGRESSION_STATUS_CARD_LOG="${statusLog}"
        : >"${errorLog}"
        : >"${statusLog}"
        release=debian
        rhelLike=false
        upgrade=true
        updateReleaseInfoChange=true
        packageManager=apt
        installType=true
        removeType=true
        selectCustomInstallType=",7,"
        command() {
            if [[ "$1" == "-v" && "$2" == "qrencode" ]]; then
                return 0
            fi
            builtin command "$@"
        }
        runWithTimeout() { return 0; }
        runPackageCommandWithProgress() { return 0; }
        waitAptProcess() { return 0; }
        installBasePackages() { return 0; }
        installNginxTools() { return 0; }
        nginx() { return 0; }
        protocolSelectionSkipsNginx() { return 0; }
        protocolSelectionNeedsLocalCertificate() { return 0; }
        curl() {
            local outputFile=
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -o)
                    outputFile=$2
                    shift 2
                    ;;
                *)
                    shift
                    ;;
                esac
            done
            [[ -n "${outputFile}" ]] || return 1
            printf '#!/usr/bin/env sh\nexit 0\n' >"${outputFile}"
        }
        tail() { return 0; }

        set +e
        (
            installTools 1
        ) >/dev/null 2>&1
        installStatus=$?
        set -e
        [[ "${installStatus}" -ne 0 ]]
        grep -q "acme.sh安装结果校验失败" "${errorLog}"
        [[ ! -e "${fakeHome}/.acme.sh/acme.sh" ]]

        if [[ -n "${oldErrorLog}" ]]; then
            REGRESSION_ERROR_CARD_LOG="${oldErrorLog}"
        else
            unset REGRESSION_ERROR_CARD_LOG
        fi
        if [[ -n "${oldStatusLog}" ]]; then
            REGRESSION_STATUS_CARD_LOG="${oldStatusLog}"
        else
            unset REGRESSION_STATUS_CARD_LOG
        fi
        if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
        HOME="${oldHome}"
        selectCustomInstallType="${oldSelect}"
        unset -f command runWithTimeout runPackageCommandWithProgress waitAptProcess installBasePackages installNginxTools nginx protocolSelectionSkipsNginx protocolSelectionNeedsLocalCertificate curl tail
    )
}

runInstallToolsAcmeCommitFailureRegression() {
    (
        local oldHome="${HOME}"
        local oldSelect="${selectCustomInstallType:-}"
        local oldErrorLog="${REGRESSION_ERROR_CARD_LOG:-}"
        local oldStatusLog="${REGRESSION_STATUS_CARD_LOG:-}"
        local oldTmpDir="${TMPDIR:-}"
        local fakeHome="${TMP_DIR}/install-tools-acme-commit-home"
        local tmpRoot="${TMP_DIR}/install-tools-acme-commit-tmp"
        local errorLog="${TMP_DIR}/install-tools-acme-commit-error.log"
        local statusLog="${TMP_DIR}/install-tools-acme-commit-status.log"
        local runMarker="${TMP_DIR}/install-tools-acme-commit-run"
        local installStatus

        rm -rf "${fakeHome}" "${tmpRoot}"
        rm -f "${runMarker}"
        mkdir -p "${fakeHome}" "${tmpRoot}"
        HOME="${fakeHome}"
        TMPDIR="${tmpRoot}"
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        export REGRESSION_STATUS_CARD_LOG="${statusLog}"
        : >"${errorLog}"
        : >"${statusLog}"
        release=debian
        rhelLike=false
        upgrade=true
        updateReleaseInfoChange=true
        packageManager=apt
        installType=true
        removeType=true
        selectCustomInstallType=",7,"
        command() {
            if [[ "$1" == "-v" && "$2" == "qrencode" ]]; then
                return 0
            fi
            builtin command "$@"
        }
        runWithTimeout() { : >"${runMarker}"; return 0; }
        runPackageCommandWithProgress() { return 0; }
        waitAptProcess() { return 0; }
        installBasePackages() { return 0; }
        installNginxTools() { return 0; }
        nginx() { return 0; }
        protocolSelectionSkipsNginx() { return 0; }
        protocolSelectionNeedsLocalCertificate() { return 0; }
        curl() {
            local outputFile=
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -o)
                    outputFile=$2
                    shift 2
                    ;;
                *)
                    shift
                    ;;
                esac
            done
            [[ -n "${outputFile}" ]] || return 1
            printf '#!/usr/bin/env sh\nexit 0\n' >"${outputFile}"
        }
        mv() { return 1; }

        set +e
        (
            installTools 1
        ) >/dev/null 2>&1
        installStatus=$?
        set -e
        [[ "${installStatus}" -ne 0 ]]
        grep -q "acme安装脚本提交失败" "${errorLog}"
        [[ ! -e "${runMarker}" ]]
        if find "${tmpRoot}" -type f -name 'acme.sh.download.*' | grep -q .; then
            return 1
        fi

        if [[ -n "${oldErrorLog}" ]]; then
            REGRESSION_ERROR_CARD_LOG="${oldErrorLog}"
        else
            unset REGRESSION_ERROR_CARD_LOG
        fi
        if [[ -n "${oldStatusLog}" ]]; then
            REGRESSION_STATUS_CARD_LOG="${oldStatusLog}"
        else
            unset REGRESSION_STATUS_CARD_LOG
        fi
        if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
        HOME="${oldHome}"
        selectCustomInstallType="${oldSelect}"
        unset -f command runWithTimeout runPackageCommandWithProgress waitAptProcess installBasePackages installNginxTools nginx protocolSelectionSkipsNginx protocolSelectionNeedsLocalCertificate curl mv
    )
}

runInstallToolsUpdateFailureRegression() {
    (
        local oldHome="${HOME}"
        local oldSelect="${selectCustomInstallType:-}"
        local oldStatusLog="${REGRESSION_STATUS_CARD_LOG:-}"
        local oldErrorLog="${REGRESSION_ERROR_CARD_LOG:-}"
        local oldInstallLog="${PADM_INSTALL_LOG:-}"
        local oldBasePackageCalledFile="${PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE:-}"
        local statusLog="${TMP_DIR}/install-tools-update-status.log"
        local errorLog="${TMP_DIR}/install-tools-update-error.log"
        local fakeHome="${TMP_DIR}/install-tools-update-home"
        PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE="${TMP_DIR}/install-tools-update-base-called"

        mkdir -p "${fakeHome}/.acme.sh"
        printf '#!/usr/bin/env sh\n' >"${fakeHome}/.acme.sh/acme.sh"
        HOME="${fakeHome}"
        export REGRESSION_STATUS_CARD_LOG="${statusLog}"
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        PADM_INSTALL_LOG="${TMP_DIR}/install-tools-update-install.log"
        : >"${statusLog}"
        : >"${errorLog}"
        release=debian
        rhelLike=false
        upgrade=false
        updateReleaseInfoChange=true
        packageManager=apt
        installType=true
        removeType=true
        selectCustomInstallType=",7,"
        protocolSelectionSkipsNginx() { return 0; }
        protocolSelectionNeedsLocalCertificate() { return 0; }
        runWithTimeout() { return 0; }
        waitAptProcess() { return 0; }
        installBasePackages() { : >"${PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE}"; }
        runPackageCommandWithProgress() {
            [[ "$1" == "检查、安装更新" ]] && return 1
            return 0
        }

        set +e
        (
            installTools 1
        ) >/dev/null 2>&1
        local installStatus=$?
        set -e
        [[ "${installStatus}" -ne 0 ]]
        [[ ! -e "${PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE}" ]]
        grep -q "系统软件源刷新失败" "${errorLog}"

        if [[ -n "${oldStatusLog}" ]]; then
            REGRESSION_STATUS_CARD_LOG="${oldStatusLog}"
        else
            unset REGRESSION_STATUS_CARD_LOG
        fi
        if [[ -n "${oldErrorLog}" ]]; then
            REGRESSION_ERROR_CARD_LOG="${oldErrorLog}"
        else
            unset REGRESSION_ERROR_CARD_LOG
        fi
        if [[ -n "${oldInstallLog}" ]]; then
            PADM_INSTALL_LOG="${oldInstallLog}"
        else
            unset PADM_INSTALL_LOG
        fi
        HOME="${oldHome}"
        selectCustomInstallType="${oldSelect}"
        if [[ -n "${oldBasePackageCalledFile}" ]]; then
            PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE="${oldBasePackageCalledFile}"
        else
            unset PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE
        fi
    )
}

runInstallToolsReleaseInfoFailureRegression() {
    (
        local oldHome="${HOME}"
        local oldSelect="${selectCustomInstallType:-}"
        local oldErrorLog="${REGRESSION_ERROR_CARD_LOG:-}"
        local oldInstallLog="${PADM_INSTALL_LOG:-}"
        local oldBasePackageCalledFile="${PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE:-}"
        local errorLog="${TMP_DIR}/install-tools-release-info-error.log"
        local fakeHome="${TMP_DIR}/install-tools-release-info-home"
        PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE="${TMP_DIR}/install-tools-release-info-base-called"

        mkdir -p "${fakeHome}/.acme.sh"
        printf '#!/usr/bin/env sh\n' >"${fakeHome}/.acme.sh/acme.sh"
        HOME="${fakeHome}"
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        PADM_INSTALL_LOG="${TMP_DIR}/install-tools-release-info-install.log"
        : >"${errorLog}"
        printf 'Repository changed its value\n' >"${PADM_INSTALL_LOG}"
        release=debian
        rhelLike=false
        upgrade=true
        updateReleaseInfoChange=false
        packageManager=apt
        installType=true
        removeType=true
        selectCustomInstallType=",7,"
        protocolSelectionSkipsNginx() { return 0; }
        protocolSelectionNeedsLocalCertificate() { return 0; }
        waitAptProcess() { return 0; }
        installBasePackages() { : >"${PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE}"; }
        runPackageCommandWithProgress() {
            printf 'changed\n' >"$4"
            return 0
        }
        runWithTimeout() {
            [[ "$1" == "300" ]] && return 1
            return 0
        }

        set +e
        (
            installTools 1
        ) >/dev/null 2>&1
        local installStatus=$?
        set -e
        [[ "${installStatus}" -ne 0 ]]
        [[ ! -e "${PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE}" ]]
        grep -q "系统软件源 release 信息刷新失败" "${errorLog}"

        if [[ -n "${oldErrorLog}" ]]; then
            REGRESSION_ERROR_CARD_LOG="${oldErrorLog}"
        else
            unset REGRESSION_ERROR_CARD_LOG
        fi
        if [[ -n "${oldInstallLog}" ]]; then
            PADM_INSTALL_LOG="${oldInstallLog}"
        else
            unset PADM_INSTALL_LOG
        fi
        HOME="${oldHome}"
        selectCustomInstallType="${oldSelect}"
        if [[ -n "${oldBasePackageCalledFile}" ]]; then
            PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE="${oldBasePackageCalledFile}"
        else
            unset PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE
        fi
    )
}

runInstallToolsNginxReinstallFailureRegression() {
    (
        local oldHome="${HOME}"
        local oldSelect="${selectCustomInstallType:-}"
        local oldErrorLog="${REGRESSION_ERROR_CARD_LOG:-}"
        local oldInstallLog="${PADM_INSTALL_LOG:-}"
        local errorLog="${TMP_DIR}/install-tools-nginx-reinstall-error.log"
        local fakeHome="${TMP_DIR}/install-tools-nginx-reinstall-home"

        mkdir -p "${fakeHome}/.acme.sh"
        printf '#!/usr/bin/env sh\n' >"${fakeHome}/.acme.sh/acme.sh"
        HOME="${fakeHome}"
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        PADM_INSTALL_LOG="${TMP_DIR}/install-tools-nginx-reinstall-install.log"
        : >"${errorLog}"
        release=debian
        rhelLike=false
        upgrade=true
        updateReleaseInfoChange=true
        packageManager=apt
        installType=true
        removeType=true
        selectCustomInstallType=",1,"
        unInstallNginxStatus=y
        protocolSelectionSkipsNginx() { return 1; }
        protocolSelectionNeedsLocalCertificate() { return 0; }
        runWithTimeout() { return 0; }
        runPackageCommandWithProgress() { return 0; }
        waitAptProcess() { return 0; }
        installBasePackages() { return 0; }
        command() {
            if [[ "$1" == "-v" && "$2" == "qrencode" ]]; then
                return 0
            fi
            builtin command "$@"
        }
        nginx() {
            [[ "${1:-}" == "-v" ]] && { printf 'nginx version: nginx/1.12.0\n' >&2; return 0; }
            return 0
        }
        autoRead() {
            printf -v "$3" 'y'
        }
        installNginxTools() {
            return 42
        }

        set +e
        (
            installTools 1
        ) >/dev/null 2>&1
        local installStatus=$?
        set -e
        [[ "${installStatus}" -ne 0 ]]
        grep -q "Nginx重装失败" "${errorLog}"

        if [[ -n "${oldErrorLog}" ]]; then
            REGRESSION_ERROR_CARD_LOG="${oldErrorLog}"
        else
            unset REGRESSION_ERROR_CARD_LOG
        fi
        if [[ -n "${oldInstallLog}" ]]; then
            PADM_INSTALL_LOG="${oldInstallLog}"
        else
            unset PADM_INSTALL_LOG
        fi
        HOME="${oldHome}"
        selectCustomInstallType="${oldSelect}"
    )
}

runAptKeyInstallFailureRegression() {
    (
        local oldErrorLog="${REGRESSION_ERROR_CARD_LOG:-}"
        local errorLog="${TMP_DIR}/apt-key-error.log"
        local curlCalls="${TMP_DIR}/apt-key-curl-calls.log"
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        : >"${errorLog}"
        : >"${curlCalls}"
        removeType=true
        PADM_INSTALLED_PACKAGES="new-dependency"
        curl() {
            printf '%s\n' "$*" >>"${curlCalls}"
            return 22
        }
        gpg() {
            cat >/dev/null
        }
        sudo() {
            "$@"
        }

        set +e
        (
            installAptKeyringFromUrl https://example.invalid/key.gpg "${TMP_DIR}/missing-keyring.gpg" "测试源"
        ) >/dev/null 2>&1
        local keyStatus=$?
        set -e
        [[ "${keyStatus}" -ne 0 ]]
        grep -q "测试源 apt key 安装失败" "${errorLog}"
        grep -q "https://example.invalid/key.gpg" "${curlCalls}"

        if [[ -n "${oldErrorLog}" ]]; then
            REGRESSION_ERROR_CARD_LOG="${oldErrorLog}"
        else
            unset REGRESSION_ERROR_CARD_LOG
        fi
        unset -f curl gpg sudo
    )
}

runNginxYumMainlineEnableFailureRegression() {
    (
        local oldErrorLog="${REGRESSION_ERROR_CARD_LOG:-}"
        local errorLog="${TMP_DIR}/nginx-yum-mainline-error.log"
        local repoDir="${TMP_DIR}/nginx-yum-repos"
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        : >"${errorLog}"
        mkdir -p "${repoDir}"
        release=centos
        packageManager=yum
        removeType=true
        PADM_YUM_REPOS_DIR="${repoDir}"
        installPackageTracked() { return 0; }
        packageInstalled() { return 0; }
        nginxServiceInstalled() { return 0; }
        bootStartup() { return 0; }
        sudo() {
            [[ "$1" == "yum-config-manager" && "$2" == "--enable" && "$3" == "nginx-mainline" ]] && return 1
            "$@"
        }

        set +e
        (
            installNginxTools
        ) >/dev/null 2>&1
        local nginxStatus=$?
        set -e
        [[ "${nginxStatus}" -ne 0 ]]
        grep -q "Nginx yum mainline 源启用失败" "${errorLog}"

        if [[ -n "${oldErrorLog}" ]]; then
            REGRESSION_ERROR_CARD_LOG="${oldErrorLog}"
        else
            unset REGRESSION_ERROR_CARD_LOG
        fi
        unset -f installPackageTracked packageInstalled nginxServiceInstalled bootStartup sudo
        unset PADM_YUM_REPOS_DIR
    )
}

runBasePackageBatchRegression() {
    local commands=(sudo wget curl unzip socat tar crontab jq ld openssl ping6 ping lsb_release lsof dig iptables-save nginx)
    local cmd
    local oldTotal="${PADM_INSTALL_STEP_TOTAL:-}"
    local oldIndex="${PADM_INSTALL_STEP_INDEX:-}"
    local oldTitle="${PADM_INSTALL_PROGRESS_TITLE:-}"

    command() {
        if [[ "$1" == "-v" ]]; then
            for cmd in "${commands[@]}"; do
                [[ "$2" == "${cmd}" ]] && return 1
            done
        fi
        builtin command "$@"
    }
    release=debian
    initVar
    checkSystem
    [[ "${installType}" == *"--no-install-recommends"* ]]
    packageManager=yum
    release=centos
    centosVersion=10
    selectCustomInstallType=",1,"
    rhelLike=true
    protocolSelectionSkipsNginx() { return 1; }
    local capturedDisplay=
    local capturedPackages=
    local capturedTimeout=
    runPackageCommandWithProgress() {
        capturedTimeout=$2
        return 0
    }
    installPackageTracked() {
        capturedDisplay=$1
        shift
        capturedPackages="$*"
    }

    initInstallProgress
    [[ "${PADM_INSTALL_STEP_TOTAL}" == "3" ]]
    installBasePackages
    [[ "${capturedDisplay}" == "基础工具" ]]
    [[ "${capturedPackages}" == *"sudo"* ]]
    [[ "${capturedPackages}" == *"bind-utils"* ]]
    [[ "${capturedPackages}" == *"iptables"* ]]
    [[ "${capturedPackages}" != *"iptables-legacy"* ]]
    [[ "${capturedPackages}" == *"iputils"* ]]
    installPackageTracked "测试" padm-missing-package
    [[ "${capturedTimeout}" == "900" ]]
    PADM_INSTALL_STEP_TOTAL=1
    PADM_INSTALL_STEP_INDEX=2
    nextInstallProgressTitle "安装nginx"
    [[ "${PADM_INSTALL_PROGRESS_TITLE}" == "工具依赖 3/3：安装nginx" ]]
    PADM_INSTALL_STEP_TOTAL="${oldTotal}"
    PADM_INSTALL_STEP_INDEX="${oldIndex}"
    PADM_INSTALL_PROGRESS_TITLE="${oldTitle}"
}

runPackageRollbackFailureRegression() {
    (
        local removedFile="${TMP_DIR}/package-rollback-removed.log"
        local oldInstalled="${PADM_INSTALLED_PACKAGES:-}"
        local oldFailures="${PADM_PACKAGE_ROLLBACK_FAILURES:-}"
        local oldRemoveType="${removeType:-}"

        removePackageForRegression() {
            printf '%s\n' "$1" >>"${removedFile}"
            [[ "$1" != "bad-package" ]]
        }

        removeType=removePackageForRegression
        PADM_INSTALLED_PACKAGES="ok-package bad-package"
        if rollbackPackageInstallTransaction; then
            return 1
        fi
        grep -qxF "ok-package" "${removedFile}"
        grep -qxF "bad-package" "${removedFile}"
        [[ "${PADM_INSTALLED_PACKAGES}" == "" ]]
        [[ "${PADM_PACKAGE_ROLLBACK_FAILURES}" == "bad-package" ]]

        if [[ -n "${oldInstalled}" ]]; then
            PADM_INSTALLED_PACKAGES="${oldInstalled}"
        else
            unset PADM_INSTALLED_PACKAGES
        fi
        if [[ -n "${oldFailures}" ]]; then
            PADM_PACKAGE_ROLLBACK_FAILURES="${oldFailures}"
        else
            unset PADM_PACKAGE_ROLLBACK_FAILURES
        fi
        removeType="${oldRemoveType}"
        unset -f removePackageForRegression
    )
}

runPackageCommandStdinRegression() {
    local oldPath="${PATH}"
    local fakeBin="${TMP_DIR}/stdin-fake-bin"
    local fdTargetFile="${TMP_DIR}/stdin-fd-target"
    local sessionFile="${TMP_DIR}/stdin-session"
    local parentSession

    parentSession=$(cut -d ' ' -f 6 "/proc/$$/stat")
    mkdir -p "${fakeBin}"
    cat >"${fakeBin}/timeout" <<'SH'
#!/usr/bin/env bash
shift
exec "$@"
SH
    chmod +x "${fakeBin}/timeout"
    PATH="${fakeBin}:${PATH}"
    source "${PROJECT_ROOT}/shell/core/adapters.sh"
    PADM_INSTALL_STEP_INDEX=0
    PADM_INSTALL_STEP_TOTAL=1
    runPackageCommandWithProgress "stdin-check" 10 "readlink /proc/\$\$/fd/0 >\"${fdTargetFile}\"; cut -d ' ' -f 6 /proc/\$\$/stat >\"${sessionFile}\"" "${TMP_DIR}/stdin-install.log"
    [[ "$(<"${fdTargetFile}")" == "/dev/null" ]]
    [[ "$(tr -d ' ' <"${sessionFile}")" =~ ^[0-9]+$ ]]
    [[ "$(tr -d ' ' <"${sessionFile}")" != "${parentSession}" ]]
    PATH="${oldPath}"
}

runRealityScannerBinaryRegression() {
    local scannerDir="${TMP_DIR}/scanner-bin"
    local scannerBin="${scannerDir}/RealiTLScanner"
    local capturedRepo= capturedVersion= capturedAsset= capturedDir=

    downloadGitHubReleaseAsset() {
        capturedDir=$2
        capturedRepo=$3
        capturedVersion=$4
        capturedAsset=$5
        mkdir -p "${capturedDir}"
        printf '#!/usr/bin/env bash\n' >"${capturedDir}/${capturedAsset}"
        return 0
    }
    curl() { printf 'v0.2.0\n'; }
    jq() { printf 'v0.2.0\n'; }

    ensureRealityScannerBinary "${scannerDir}" "${scannerBin}"
    [[ -x "${scannerBin}" ]]
    [[ "${capturedRepo}" == "XTLS/RealiTLScanner" ]]
    [[ "${capturedVersion}" == "v0.2.0" ]]
    [[ "${capturedAsset}" == "RealiTLScanner-linux-64" ]]
}

regressionModuleManifestReady() {
    [[ "${PADM_FAKE_MODULE_MANIFEST_READY:-1}" == "1" ]]
}

regressionScriptModulesReady() {
    [[ -f "${SCRIPT_DIR}/shell/core/bootstrap.sh" ]] || return 1
    regressionModuleManifestReady || return 1
    [[ -f "${SCRIPT_EXPECTED_REF_FILE}" ]] || return 0
    [[ -f "${SCRIPT_REF_FILE}" ]] || return 1
    [[ "$(<"${SCRIPT_EXPECTED_REF_FILE}")" == "$(<"${SCRIPT_REF_FILE}")" ]]
}

regressionScriptModuleFilesPresent() {
    [[ -f "${SCRIPT_DIR}/shell/core/bootstrap.sh" ]]
}

regressionEnsureScriptModules() {
    local remoteRef= expectedRef=
    if [[ "${PADM_FORCE_SCRIPT_MODULE_REFRESH:-}" == "1" ]]; then
        remoteRef=$(fetchRemoteRef || true)
        refreshScriptModules "${remoteRef}"
        [[ -n "${remoteRef}" ]] && printf '%s\n' "${remoteRef}" >"${SCRIPT_EXPECTED_REF_FILE}"
        return 0
    fi
    if regressionScriptModulesReady; then
        return 0
    fi
    if [[ -f "${SCRIPT_EXPECTED_REF_FILE}" ]]; then
        expectedRef=$(<"${SCRIPT_EXPECTED_REF_FILE}")
    fi
    if [[ "${PADM_SKIP_REMOTE_REF_CHECK:-}" == "1" ]]; then
        if regressionScriptModuleFilesPresent; then
            return 0
        fi
        refreshScriptModules "${expectedRef}"
        return 0
    fi

    remoteRef="${expectedRef}"
    [[ -n "${remoteRef}" ]] || remoteRef=$(fetchRemoteRef || true)
    refreshScriptModules "${remoteRef}"
    [[ -n "${remoteRef}" ]] && printf '%s\n' "${remoteRef}" >"${SCRIPT_EXPECTED_REF_FILE}"
}

runUpdatePadmVersionPromptRegression() {
    local successLog errorLog installDir updateTmpRoot downloadDirLog oldTmpDir
    local replaceFailureDir replaceFailureErrorLog replaceFailureDownloadLog
    local chmodFailureDir chmodFailureErrorLog chmodFailureDownloadLog
    successLog="${TMP_DIR}/update-padm-success.log"
    errorLog="${TMP_DIR}/update-padm-error.log"
    installDir="${TMP_DIR}/update-padm-install"
    updateTmpRoot="${TMP_DIR}/update-padm-tmp"
    downloadDirLog="${TMP_DIR}/update-padm-download-dirs.log"
    replaceFailureDir="${TMP_DIR}/update-padm-replace-restore-failure"
    replaceFailureErrorLog="${TMP_DIR}/update-padm-replace-restore-failure-error.log"
    replaceFailureDownloadLog="${TMP_DIR}/update-padm-replace-restore-failure-download.log"
    chmodFailureDir="${TMP_DIR}/update-padm-chmod-restore-failure"
    chmodFailureErrorLog="${TMP_DIR}/update-padm-chmod-restore-failure-error.log"
    chmodFailureDownloadLog="${TMP_DIR}/update-padm-chmod-restore-failure-download.log"
    oldTmpDir="${TMPDIR:-}"
    mkdir -p "${installDir}" "${updateTmpRoot}" "${replaceFailureDir}" "${chmodFailureDir}"
    : >"${downloadDirLog}"
    : >"${successLog}"
    : >"${errorLog}"
    : >"${replaceFailureErrorLog}"
    : >"${replaceFailureDownloadLog}"
    : >"${chmodFailureErrorLog}"
    : >"${chmodFailureDownloadLog}"
    TMPDIR="${updateTmpRoot}"
    printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${installDir}/install.sh"
    chmod 700 "${installDir}/install.sh"

    (
        REGRESSION_SUCCESS_CARD_LOG="${successLog}"
        REGRESSION_ERROR_CARD_LOG="${errorLog}"
        release=debian
        PADM_INSTALL_DIR="${installDir}"

        downloadFile() {
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -P)
                    mkdir -p "$2"
                    printf '%s\n' "$2" >>"${downloadDirLog}"
                    cat >"$2/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
printf 'new-entry-ok\n'
exit 0
EOF
                    return 0
                    ;;
                esac
                shift
            done
            return 1
        }
        sudo() { "$@"; }

        updatePadm 1
    ) >"${TMP_DIR}/update-padm-run-ok.log" 2>&1
    grep -q '更新入口已下载，正在重新打开新版脚本' "${successLog}"
    grep -q 'new-entry-ok' "${successLog}" && return 1
    grep -qx "${updateTmpRoot}/padm-update\\.[A-Za-z0-9][A-Za-z0-9]*" "${downloadDirLog}"
    if find "${updateTmpRoot}" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
        return 1
    fi
    [[ ! -e "${installDir}/install.sh.bak" ]]
    "${installDir}/install.sh" | grep -q 'new-entry-ok'

    printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${installDir}/install.sh"
    chmod 700 "${installDir}/install.sh"
    : >"${successLog}"
    : >"${errorLog}"
    (
        REGRESSION_ERROR_CARD_LOG="${errorLog}"
        release=debian
        PADM_INSTALL_DIR="${installDir}"

        downloadFile() {
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -P)
                    mkdir -p "$2"
                    printf '%s\n' "$2" >>"${downloadDirLog}"
                    cat >"$2/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
exit 23
EOF
                    return 0
                    ;;
                esac
                shift
            done
            return 1
        }
        sudo() { "$@"; }

        updatePadm 1
    ) >"${TMP_DIR}/update-padm-run-fail.log" 2>&1 && return 1
    grep -q '新版入口执行失败，已恢复旧入口' "${errorLog}"
    grep -qx "${updateTmpRoot}/padm-update\\.[A-Za-z0-9][A-Za-z0-9]*" "${downloadDirLog}"
    if find "${updateTmpRoot}" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
        return 1
    fi
    "${installDir}/install.sh" | grep -q 'old-entry'

    printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${replaceFailureDir}/install.sh"
    chmod 700 "${replaceFailureDir}/install.sh"
    (
        REGRESSION_ERROR_CARD_LOG="${replaceFailureErrorLog}"
        release=debian
        PADM_INSTALL_DIR="${replaceFailureDir}"

        downloadFile() {
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -P)
                    mkdir -p "$2"
                    printf '%s\n' "$2" >>"${replaceFailureDownloadLog}"
                    cat >"$2/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
printf 'new-entry\n'
exit 0
EOF
                    return 0
                    ;;
                esac
                shift
            done
            return 1
        }
        sudo() {
            if [[ "$1" == "chmod" && "$2" == "700" && "$3" == "${replaceFailureDir}/install.sh" ]]; then
                return 1
            fi
            "$@"
        }
        mv() {
            if [[ "$1" == "${replaceFailureDir}/install.sh.bak" && "$2" == "${replaceFailureDir}/install.sh" ]]; then
                return 1
            fi
            command mv "$@"
        }

        updatePadm 1
    ) >"${TMP_DIR}/update-padm-replace-restore-failure-run.log" 2>&1 && return 1
    grep -q '更新入口替换失败，旧入口恢复失败' "${replaceFailureErrorLog}"
    grep -q "${replaceFailureDir}/install.sh.bak" "${replaceFailureErrorLog}"
    [[ -f "${replaceFailureDir}/install.sh.bak" ]]
    "${replaceFailureDir}/install.sh" | grep -q 'new-entry'

    printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${chmodFailureDir}/install.sh"
    chmod 700 "${chmodFailureDir}/install.sh"
    (
        REGRESSION_ERROR_CARD_LOG="${chmodFailureErrorLog}"
        release=debian
        PADM_INSTALL_DIR="${chmodFailureDir}"

        downloadFile() {
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -P)
                    mkdir -p "$2"
                    printf '%s\n' "$2" >>"${chmodFailureDownloadLog}"
                    cat >"$2/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
exit 23
EOF
                    return 0
                    ;;
                esac
                shift
            done
            return 1
        }
        sudo() {
            if [[ "$1" == "chmod" && "$2" == "700" && "$3" == "${chmodFailureDir}/install.sh" && -f "${chmodFailureDir}/install.sh.bak" ]]; then
                return 1
            fi
            "$@"
        }

        updatePadm 1
    ) >"${TMP_DIR}/update-padm-chmod-restore-failure-run.log" 2>&1 && return 1
    grep -q '新版入口执行失败，旧入口恢复失败' "${chmodFailureErrorLog}"
    grep -q "${chmodFailureDir}/install.sh.bak" "${chmodFailureErrorLog}"
    [[ ! -e "${chmodFailureDir}/install.sh.bak" ]]
    "${chmodFailureDir}/install.sh" | grep -q 'old-entry'
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runInstallRefreshRestoresBackupRegression() {
    local fixtureDir archiveRoot outputLog archiveDirName refreshTmpRoot oldTmpDir restoreFailureDir restoreFailureArchiveRoot restoreFailureOutputLog restoreFailureTmpRoot
    fixtureDir="${TMP_DIR}/install-refresh-restore"
    archiveDirName="padm-main"
    archiveRoot="${fixtureDir}/archive/${archiveDirName}"
    outputLog="${fixtureDir}/refresh.log"
    refreshTmpRoot="${fixtureDir}/tmp"
    restoreFailureDir="${TMP_DIR}/install-refresh-restore-failure"
    restoreFailureArchiveRoot="${restoreFailureDir}/archive/${archiveDirName}"
    restoreFailureOutputLog="${restoreFailureDir}/refresh.log"
    restoreFailureTmpRoot="${restoreFailureDir}/tmp"
    oldTmpDir="${TMPDIR:-}"
    mkdir -p "${fixtureDir}/shell" "${fixtureDir}/documents" "${archiveRoot}/shell" "${archiveRoot}/documents" "${refreshTmpRoot}"
    printf 'old-shell\n' >"${fixtureDir}/shell/marker"
    printf 'old-doc\n' >"${fixtureDir}/documents/marker"
    printf 'old-readme\n' >"${fixtureDir}/README.md"
    printf 'new-shell\n' >"${archiveRoot}/shell/marker"
    printf 'new-doc\n' >"${archiveRoot}/documents/marker"
    printf 'new-readme\n' >"${archiveRoot}/README.md"

    (
        set +e
        TMPDIR="${refreshTmpRoot}"
        eval "$(awk '
            /^scriptTmpPath\(\)/ { capture = 1 }
            /^ensureScriptModules\(\)/ { capture = 0 }
            capture { print }
        ' "${PROJECT_ROOT}/install.sh")"
        SCRIPT_DIR="${fixtureDir}"
        REPO_ARCHIVE_DIR="${archiveDirName}"
        SCRIPT_REF_FILE="${fixtureDir}/.padm-ref"
        SCRIPT_MANIFEST_FILE="${fixtureDir}/.padm-module-manifest"
        REPO_ZIP_URL="fixture.tar.gz"
        command() {
            if [[ "$1" == "-v" && "$2" == "curl" ]]; then
                return 0
            fi
            builtin command "$@"
        }
        curl() { tar -cz -C "${fixtureDir}/archive" "${REPO_ARCHIVE_DIR}"; }
        cp() {
            if [[ "$1" == "-R" && "$2" == "${archiveRoot}/documents" ]]; then
                return 1
            fi
            command cp "$@"
        }
        refreshScriptModules new-ref
    ) >"${outputLog}" 2>&1
    grep -q '完整安装包替换失败，已恢复旧模块' "${outputLog}"
    [[ "$(<"${fixtureDir}/shell/marker")" == "old-shell" ]]
    [[ "$(<"${fixtureDir}/documents/marker")" == "old-doc" ]]
    [[ "$(<"${fixtureDir}/README.md")" == "old-readme" ]]
    [[ ! -e "${fixtureDir}/.padm-ref" ]]
    [[ ! -e "${fixtureDir}/.padm-update-backup" ]]
    if find "${refreshTmpRoot}" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
        return 1
    fi

    mkdir -p "${restoreFailureDir}/shell" "${restoreFailureDir}/documents" "${restoreFailureArchiveRoot}/shell" "${restoreFailureArchiveRoot}/documents" "${restoreFailureTmpRoot}"
    printf 'old-shell\n' >"${restoreFailureDir}/shell/marker"
    printf 'old-doc\n' >"${restoreFailureDir}/documents/marker"
    printf 'old-readme\n' >"${restoreFailureDir}/README.md"
    printf 'new-shell\n' >"${restoreFailureArchiveRoot}/shell/marker"
    printf 'new-doc\n' >"${restoreFailureArchiveRoot}/documents/marker"
    printf 'new-readme\n' >"${restoreFailureArchiveRoot}/README.md"

    (
        set +e
        TMPDIR="${restoreFailureTmpRoot}"
        eval "$(awk '
            /^scriptTmpPath\(\)/ { capture = 1 }
            /^ensureScriptModules\(\)/ { capture = 0 }
            capture { print }
        ' "${PROJECT_ROOT}/install.sh")"
        SCRIPT_DIR="${restoreFailureDir}"
        REPO_ARCHIVE_DIR="${archiveDirName}"
        SCRIPT_REF_FILE="${restoreFailureDir}/.padm-ref"
        SCRIPT_MANIFEST_FILE="${restoreFailureDir}/.padm-module-manifest"
        REPO_ZIP_URL="fixture.tar.gz"
        command() {
            if [[ "$1" == "-v" && "$2" == "curl" ]]; then
                return 0
            fi
            builtin command "$@"
        }
        curl() { tar -cz -C "${restoreFailureDir}/archive" "${REPO_ARCHIVE_DIR}"; }
        cp() {
            if [[ "$1" == "-R" && "$2" == "${restoreFailureArchiveRoot}/documents" ]]; then
                return 1
            fi
            command cp "$@"
        }
        mv() {
            if [[ "$1" == "${restoreFailureDir}/.padm-update-backup/documents" && "$2" == "${restoreFailureDir}/documents" ]]; then
                return 1
            fi
            command mv "$@"
        }
        refreshScriptModules new-ref
    ) >"${restoreFailureOutputLog}" 2>&1
    grep -q '完整安装包替换失败，旧模块恢复失败，请手动检查备份目录' "${restoreFailureOutputLog}"
    grep -q "${restoreFailureDir}/.padm-update-backup" "${restoreFailureOutputLog}"
    [[ -d "${restoreFailureDir}/.padm-update-backup" ]]
    [[ "$(<"${restoreFailureDir}/shell/marker")" == "old-shell" ]]
    [[ -d "${restoreFailureDir}/.padm-update-backup/documents" ]]
    [[ "$(<"${restoreFailureDir}/.padm-update-backup/documents/marker")" == "old-doc" ]]
    [[ ! -e "${restoreFailureDir}/.padm-ref" ]]
    if find "${restoreFailureTmpRoot}" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
        return 1
    fi
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runInstallEnsureModulesRegression() {
    local fixtureDir marker
    fixtureDir="${TMP_DIR}/install-entry"
    marker="${fixtureDir}/refresh-called"
    mkdir -p "${fixtureDir}/shell/core"
    touch "${fixtureDir}/shell/core/bootstrap.sh"
    printf 'old-ref\n' >"${fixtureDir}/.padm-ref"

    local savedScriptDir="${SCRIPT_DIR:-}"
    local savedScriptRefFile="${SCRIPT_REF_FILE:-}"
    local savedScriptExpectedRefFile="${SCRIPT_EXPECTED_REF_FILE:-}"
    local savedRepoRefUrl="${REPO_REF_URL:-}"
    local savedRepoZipUrl="${REPO_ZIP_URL:-}"
    local savedRepoArchiveDir="${REPO_ARCHIVE_DIR:-}"
    local savedPadmSkipRemoteRefCheck="${PADM_SKIP_REMOTE_REF_CHECK:-}"

    SCRIPT_DIR="${fixtureDir}"
    SCRIPT_REF_FILE="${fixtureDir}/.padm-ref"
    SCRIPT_EXPECTED_REF_FILE="${fixtureDir}/.padm-entry-ref"
    refreshScriptModules() { printf '%s\n' "$1" >"${marker}"; }
    fetchRemoteRef() { return 1; }
    regressionEnsureScriptModules
    [[ ! -e "${marker}" ]]

    rm -f "${fixtureDir}/shell/core/bootstrap.sh"
    regressionEnsureScriptModules
    [[ -f "${marker}" ]]

    rm -f "${marker}"
    mkdir -p "${fixtureDir}/shell/core"
    touch "${fixtureDir}/shell/core/bootstrap.sh"
    fetchRemoteRef() { printf 'new-ref\n'; }
    regressionEnsureScriptModules
    [[ ! -e "${marker}" ]]

    printf 'expected-ref\n' >"${fixtureDir}/.padm-entry-ref"
    printf 'old-ref\n' >"${fixtureDir}/.padm-ref"
    rm -f "${marker}"
    regressionEnsureScriptModules
    [[ "$(<"${marker}")" == "expected-ref" ]]

    printf 'expected-ref\n' >"${fixtureDir}/.padm-entry-ref"
    printf 'expected-ref\n' >"${fixtureDir}/.padm-ref"
    rm -f "${marker}"
    PADM_FAKE_MODULE_MANIFEST_READY=0 regressionEnsureScriptModules
    [[ ! -e "${marker}" ]]

    unset PADM_FAKE_MODULE_MANIFEST_READY

    rm -f "${marker}" "${fixtureDir}/.padm-entry-ref"
    rm -f "${fixtureDir}/shell/core/bootstrap.sh"
    regressionEnsureScriptModules
    [[ "$(<"${marker}")" == "new-ref" ]]

    SCRIPT_DIR="${savedScriptDir}"
    SCRIPT_REF_FILE="${savedScriptRefFile}"
    SCRIPT_EXPECTED_REF_FILE="${savedScriptExpectedRefFile}"
    REPO_REF_URL="${savedRepoRefUrl}"
    REPO_ZIP_URL="${savedRepoZipUrl}"
    REPO_ARCHIVE_DIR="${savedRepoArchiveDir}"
    if [[ -n "${savedPadmSkipRemoteRefCheck}" ]]; then
        PADM_SKIP_REMOTE_REF_CHECK="${savedPadmSkipRemoteRefCheck}"
    else
        unset PADM_SKIP_REMOTE_REF_CHECK
    fi
}

runAliasInstallSameTargetRegression() {
    local fixtureDir outputLog cpLog oldScriptDir oldPadmInstallDir oldHome
    fixtureDir="${TMP_DIR}/alias-install-same-target"
    outputLog="${fixtureDir}/output.log"
    cpLog="${fixtureDir}/cp.log"
    mkdir -p "${fixtureDir}"
    cat >"${fixtureDir}/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
EOF

    oldScriptDir="${SCRIPT_DIR:-}"
    oldPadmInstallDir="${PADM_INSTALL_DIR:-}"
    oldHome="${HOME}"
    SCRIPT_DIR="${fixtureDir}"
    PADM_INSTALL_DIR="${fixtureDir}"
    HOME="${fixtureDir}/home"
    mkdir -p "${HOME}"

    (
        cp() { printf 'cp %s\n' "$*" >>"${cpLog}"; command cp "$@"; }
        chmod() { :; }
        ln() { :; }
        aliasInstall
    ) >"${outputLog}" 2>&1

    [[ ! -s "${outputLog}" ]]
    [[ ! -e "${cpLog}" ]]

    SCRIPT_DIR="${oldScriptDir}"
    HOME="${oldHome}"
    if [[ -n "${oldPadmInstallDir}" ]]; then
        PADM_INSTALL_DIR="${oldPadmInstallDir}"
    else
        unset PADM_INSTALL_DIR
    fi
}

runInstallModulePathsRegression() {
    local outputList moduleTmpRoot oldTmpDir moduleListBefore moduleListAfter
    outputList="${TMP_DIR}/install-module-paths.txt"
    moduleTmpRoot="${TMP_DIR}/install-module-paths-tmp"
    oldTmpDir="${TMPDIR:-}"
    mkdir -p "${moduleTmpRoot}"
    (
        TMPDIR="${moduleTmpRoot}"
        eval "$(awk '
            /^scriptTmpPath\(\)/ { capture = 1 }
            /^ensureScriptModules\(\)/ { capture = 0 }
            capture { print }
        ' "${PROJECT_ROOT}/install.sh")"
        SCRIPT_DIR="${PROJECT_ROOT}"
        SCRIPT_MANIFEST_FILE="${TMP_DIR}/install-module-paths-manifest"
        SCRIPT_EXPECTED_REF_FILE="${TMP_DIR}/install-module-paths-entry-ref"
        SCRIPT_REF_FILE="${TMP_DIR}/install-module-paths-ref"
        moduleListBefore=$(find "${moduleTmpRoot}" -maxdepth 1 -type f -name 'padm-modules.*' | wc -l | tr -d ' ')
        modulePaths
        scriptModulesReady >/dev/null
        moduleListAfter=$(find "${moduleTmpRoot}" -maxdepth 1 -type f -name 'padm-modules.*' | wc -l | tr -d ' ')
        [[ "${moduleListBefore}" == "0" && "${moduleListAfter}" == "0" ]]
    ) | sort >"${outputList}"
    grep -q '^shell/core/bootstrap\.sh$' "${outputList}"
    grep -q '^shell/core/fail2ban\.sh$' "${outputList}"
    grep -q '^shell/validate_install\.sh$' "${outputList}"
    grep -q '^shell/core/menu\.sh$' "${outputList}"
    grep -q '^shell/subscription/wireguard_control\.sh$' "${outputList}"
    ! grep -q '^REQUIRED_MODULE_PATHS' "${PROJECT_ROOT}/install.sh"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runRegressionPlatform() {
    runRegressionStep release-workflow-version runReleaseWorkflowVersionRegression &&
        runRegressionStep cleanup-trap runCleanupTrapRegression &&
        runRegressionStep check-log-backup-restore runCheckLogBackupMissingRestoreRegression &&
        runRegressionStep update-padm-version-prompt runUpdatePadmVersionPromptRegression &&
        runRegressionStep install-refresh-restore runInstallRefreshRestoresBackupRegression &&
        runRegressionStep install-entry-refresh runInstallEnsureModulesRegression &&
        runRegressionStep install-module-paths runInstallModulePathsRegression &&
        runRegressionStep alias-install-same-target runAliasInstallSameTargetRegression &&
        runRegressionStep xray-stats-jq runXrayTrafficStatsJqCompatibilityRegression &&
        runRegressionStep local-traffic-accounts runLocalTrafficAccountsBatchRegression &&
        runRegressionStep dpkg-installed-pattern runDpkgInstalledPatternRegression &&
        runRegressionStep dpkg-query-installed-pattern runDpkgQueryInstalledPatternRegression &&
        runRegressionStep rhel-like-detection runRhelLikeDetectionRegression &&
        runRegressionStep fedora-detection runFedoraDetectionRegression
}

runRegressionPlatformIo() {
    runRegressionStep install-tools-certificate-dependency runInstallToolsCertificateDependencyRegression &&
        runRegressionStep install-tools-acme-result-failure runInstallToolsAcmeResultFailureRegression &&
        runRegressionStep install-tools-acme-commit-failure runInstallToolsAcmeCommitFailureRegression &&
        runRegressionStep install-tools-update-failure runInstallToolsUpdateFailureRegression &&
        runRegressionStep install-tools-release-info-failure runInstallToolsReleaseInfoFailureRegression &&
        runRegressionStep install-tools-nginx-reinstall-failure runInstallToolsNginxReinstallFailureRegression &&
        runRegressionStep apt-key-install-failure runAptKeyInstallFailureRegression &&
        runRegressionStep nginx-yum-mainline-enable-failure runNginxYumMainlineEnableFailureRegression &&
        runRegressionStep base-package-batch runBasePackageBatchRegression &&
        runRegressionStep package-rollback-failure runPackageRollbackFailureRegression &&
        runRegressionStep package-command-stdin runPackageCommandStdinRegression &&
        runRegressionStep reality-scanner-binary runRealityScannerBinaryRegression
}

runTlsDnsApiDomainSelectionRegression() (
    local root="${TMP_DIR}/tls-dns-api-domain-selection"
    local homeDir="${root}/home"
    local commandLog="${root}/commands.log"

    mkdir -p "${homeDir}/.acme.sh"
    HOME="${homeDir}"
    export PADM_TEST_ACME_LOG="${commandLog}"
    cat <<'EOF' >"${homeDir}/.acme.sh/acme.sh"
#!/usr/bin/env sh
printf '%s\n' "$*" >>"${PADM_TEST_ACME_LOG}"
EOF
    chmod +x "${homeDir}/.acme.sh/acme.sh"

    tee() {
        cat >/dev/null
    }

    tlsDomain=sub.example.com
    dnsTLSDomain=example.com
    sslType=letsencrypt
    sslIPv6=

    : >"${commandLog}"
    dnsAPIType=cloudflare
    dnsAPIStatus=n
    cfAPIToken=token
    cfZoneID=
    acmeInstallSSL
    grep -F -q -- '--issue -d sub.example.com --dns dns_cf' "${commandLog}"
    ! grep -F -q -- '-d example.com' "${commandLog}"

    : >"${commandLog}"
    dnsAPIStatus=y
    acmeInstallSSL
    grep -F -q -- '--issue -d *.example.com -d example.com --dns dns_cf' "${commandLog}"

    : >"${commandLog}"
    dnsAPIType=aliyun
    dnsAPIStatus=n
    aliKey=key
    aliSecret=secret
    acmeInstallSSL
    grep -F -q -- '--issue -d sub.example.com --dns dns_ali' "${commandLog}"
    ! grep -F -q -- '-d example.com' "${commandLog}"
)

runTlsRenewalExistingCertificateRegression() {
    local oldHome="${HOME}"
    local oldTlsDir="${PADM_TLS_DIR:-}"
    local oldCurrentHost="${currentHost:-}"
    local oldDomain="${domain:-}"
    local oldTlsDomain="${tlsDomain:-}"
    local oldStatusLog="${REGRESSION_STATUS_CARD_LOG:-}"
    local oldErrorLog="${REGRESSION_ERROR_CARD_LOG:-}"
    local oldInstalledDNSAPIStatus="${installedDNSAPIStatus:-}"
    local oldSslRenewalDays="${sslRenewalDays:-}"
    local oldCoreInstallType="${coreInstallType:-}"
    local oldDnsTLSDomain="${dnsTLSDomain:-}"
    local statusLog="${TMP_DIR}/tls-renew-status.log"
    local errorLog="${TMP_DIR}/tls-renew-error.log"
    local tlsDir="${TMP_DIR}/tls-renew-certs"
    mkdir -p "${tlsDir}"
    HOME="${TMP_DIR}/tls-renew-home"
    PADM_TLS_DIR="${tlsDir}"
    currentHost=
    domain=
    tlsDomain=
    installedDNSAPIStatus=
    dnsTLSDomain=
    coreInstallType=
    sslRenewalDays=90
    export REGRESSION_STATUS_CARD_LOG="${statusLog}"
    export REGRESSION_ERROR_CARD_LOG="${errorLog}"
    : >"${statusLog}"
    : >"${errorLog}"
    mkdir -p "${HOME}"
    printf 'cert\n' >"${tlsDir}/existing.example.com.crt"
    printf 'key\n' >"${tlsDir}/existing.example.com.key"

    renewalTLS

    grep -q "检测到使用自定义证书，无法执行 renew 操作" "${statusLog}"
    ! grep -q "未安装" "${errorLog}"
    rm -f "${tlsDir}/existing.example.com.crt" "${tlsDir}/existing.example.com.key"
    : >"${statusLog}"
    : >"${errorLog}"

    renewalTLS
    grep -q "未安装本机 TLS 证书" "${errorLog}"

    : >"${statusLog}"
    : >"${errorLog}"
    currentHost=wild.example.com
    dnsTLSDomain=example.com
    installedDNSAPIStatus=true
    mkdir -p "${HOME}/.acme.sh/*.example.com_ecc"
    printf 'cert\n' >"${tlsDir}/wild.example.com.crt"
    printf 'key\n' >"${tlsDir}/wild.example.com.key"
    printf 'cert\n' >"${HOME}/.acme.sh/*.example.com_ecc/*.example.com.cer"
    printf 'key\n' >"${HOME}/.acme.sh/*.example.com_ecc/*.example.com.key"
    touch -d '89 days ago' "${HOME}/.acme.sh/*.example.com_ecc/*.example.com.cer"
    handleNginx() { return 0; }
    handleXray() { return 0; }
    handleSingBox() { return 0; }
    reloadCore() { return 0; }
    sudo() {
        printf '%s\n' "$*" >>"${statusLog}"
        return 0
    }

    renewalTLS
    grep -q -- "--installcert -d \*.example.com" "${statusLog}"
    ! grep -q -- "--installcert -d wild.example.com" "${statusLog}"
    ! grep -q "检测到使用自定义证书" "${statusLog}"

    if [[ -n "${oldStatusLog}" ]]; then
        REGRESSION_STATUS_CARD_LOG="${oldStatusLog}"
    else
        unset REGRESSION_STATUS_CARD_LOG
    fi
    if [[ -n "${oldErrorLog}" ]]; then
        REGRESSION_ERROR_CARD_LOG="${oldErrorLog}"
    else
        unset REGRESSION_ERROR_CARD_LOG
    fi
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
    sslRenewalDays="${oldSslRenewalDays}"
    coreInstallType="${oldCoreInstallType}"
    dnsTLSDomain="${oldDnsTLSDomain}"
}

runTlsRenewalFailurePropagationRegression() (
    local root="${TMP_DIR}/tls-renew-failure-propagation"
    local tlsDir="${root}/certs"
    local homeDir="${root}/home"
    local serviceLog="${root}/services.log"
    local commandLog="${root}/commands.log"
    local statusLog="${root}/status.log"
    local errorLog="${root}/error.log"
    local mode rc

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
    progressCard() { return 0; }
    handleNginx() {
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "nginx-stop-fail" && "$1" == "stop" ]] && return 1
        [[ "${mode}" == "nginx-start-fail" && "$1" == "start" ]] && return 1
        return 0
    }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "xray-stop-fail" && "$1" == "stop" ]] && return 1
        return 0
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        return 0
    }
    reloadCore() {
        printf 'reload\n' >>"${serviceLog}"
        [[ "${mode}" == "reload-fail" ]] && return 1
        return 0
    }
    stat() {
        if [[ "$1" == "--format=%z" && "${2:-}" == *"/renew.example.com_ecc/renew.example.com.cer" ]]; then
            date -d '89 days ago' '+%F %T.000000000 %z'
            return 0
        fi
        command stat "$@"
    }
    sudo() {
        printf 'sudo:%s\n' "$*" >>"${commandLog}"
        [[ "${mode}" == "install-fail" ]] && return 1
        return 0
    }
    prepareRenewalFixture() {
        rm -rf "${tlsDir}" "${homeDir}/.acme.sh"
        mkdir -p "${tlsDir}" "${homeDir}/.acme.sh/renew.example.com_ecc"
        printf 'cert\n' >"${tlsDir}/renew.example.com.crt"
        printf 'key\n' >"${tlsDir}/renew.example.com.key"
        printf 'cert\n' >"${homeDir}/.acme.sh/renew.example.com_ecc/renew.example.com.cer"
        printf 'key\n' >"${homeDir}/.acme.sh/renew.example.com_ecc/renew.example.com.key"
        : >"${serviceLog}"
        : >"${commandLog}"
        : >"${statusLog}"
        : >"${errorLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
    }
    runRenewalCase() {
        mode=$1
        prepareRenewalFixture
        set +e
        renewalTLS >/dev/null 2>&1
        rc=$?
        set -e
    }

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

    runRenewalCase install-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:stop:true' "${serviceLog}"
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'reload' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    grep -q '^sudo:.*--installcert -d renew.example.com' "${commandLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    runRenewalCase reload-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'reload' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    grep -q '^sudo:.*--installcert -d renew.example.com' "${commandLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    runRenewalCase nginx-start-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'reload' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    grep -q '^sudo:.*--installcert -d renew.example.com' "${commandLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
)

runRegressionTls() {
    runRegressionStep tls-dns-api-domain-selection runTlsDnsApiDomainSelectionRegression &&
        runRegressionStep tls-renew-existing-certificate runTlsRenewalExistingCertificateRegression &&
        runRegressionStep tls-renew-failure-propagation runTlsRenewalFailurePropagationRegression
}

runRegressionFast() {
    runRegressionStep platform runRegressionPlatform &&
        runRegressionStep nginx-blog-auto-install runNginxBlogAutoInstallRegression &&
        runRegressionStep ui-smoke-light runMenuSmokeLightRegression
}

runRegressionFastReality() {
    runRegressionFast &&
        runRegressionStep reality-candidates-fast runRealityCandidateFastRegression
}

runRegressionUi() {
    runRegressionStep ui-smoke-light runMenuSmokeLightRegression
    runRegressionStep ui-smoke runMenuSmokeRegression
    runRegressionStep wireguard-menu-flow runSubscriptionWireGuardMenuFlowRegression
}

runRegressionMenuSmoke() {
    runRegressionStep ui-smoke-light runMenuSmokeLightRegression
}

runRegressionMenuSmokeFull() {
    runRegressionStep ui-smoke runMenuSmokeRegression
}

runRegressionRouting() {
    runRegressionStep routing-core runRoutingRegression
    runRegressionStep routing-socks5-udp-associate runSocks5UdpAssociateRegression
    runRegressionStep routing-access-control-failure-return runAccessControlFailureReturnRegression
    runRegressionStep routing-access-control-config-transaction runAccessControlConfigTransactionRegression
    runRegressionStep routing-bt-failure-return runBTRoutingFailureReturnRegression
    runRegressionStep routing-ipv6-failure-return runIPv6RoutingFailureReturnRegression
    runRegressionStep routing-warp-failure-return runWARPRoutingFailureReturnRegression
    runRegressionStep routing-socks5-failure-return runSocks5RoutingFailureReturnRegression
    runRegressionStep routing-dns-failure-return runDNSRoutingFailureReturnRegression
    runRegressionStep routing-port-panel runPortAndPanelHelperRegression
}

runRegressionSubscriptionOutput() {
    runRegressionStep subscription-output runSubscriptionOutputRegression
}

runRegressionSubscriptionState() {
    runRegressionStep subscription-state runSubscriptionGroupStateRegression
    runRegressionStep subscription-sync-tempdir runSubscriptionSyncTempDirRegression
    runRegressionStep subscription-sync-rollback-failure runSubscriptionSyncRollbackFailureRegression
    runRegressionStep subscription-sync-reconcile-early-exit runSubscriptionSyncReconcileEarlyExitRegression
    runRegressionStep subscription-groups-restore-failure runSubscriptionGroupsRestoreFailureRegression
}

runRegressionSubscriptionRemoteFetch() {
    runRegressionStep subscription-remote-fetch runRemoteSubscribeFetchRegression
}

runRegressionSubscriptionWriteTransaction() {
    runRegressionStep sing-box-subscribe-write runSingBoxSubscribeWriteRegression
    runRegressionStep subscribe-server-name runSubscribeServerNameRegression
    runRegressionStep subscribe-nginx-config-write runSubscribeNginxConfigWriteRegression
    runRegressionStep subscribe-nginx-service-failure runSubscribeNginxServiceFailureRegression
    runRegressionStep sing-box-port-failure runSingBoxPortFailureRegression
    runRegressionStep subscribe-user-output-transaction runSubscribeUserOutputTransactionRegression
    runRegressionStep subscribe-local-rollback runSubscribeLocalRollbackRegression
    runRegressionStep subscription-groups-migration-backup runSubscriptionGroupsMigrationBackupRegression
    runRegressionStep subscription-groups-backup-failure runSubscriptionGroupsBackupFailureRegression
    runRegressionStep refresh-local-subscriptions-rollback runRefreshLocalSubscriptionsRollbackRegression
    runRegressionStep subscribe-return-failure runSubscribeReturnFailureRegression
    runRegressionStep remove-user-subscription-menu-failure runRemoveUserSubscriptionMenuFailureRegression
    runRegressionStep user-subscription-menu-mutation-failure runUserSubscriptionMenuMutationFailureRegression
}

runRegressionSubscription() {
    runRegressionSubscriptionOutput
    runRegressionSubscriptionState
    runRegressionSubscriptionRemoteFetch
    runRegressionSubscriptionWriteTransaction
}

runRegressionRealityCandidates() {
    runRegressionStep reality-candidates-fast runRealityCandidateFastRegression &&
        runRegressionStep reality-asn-scan-plan runRealityAsnScanPlanRegression &&
        runRegressionStep reality-candidates-full runRealityCandidateFullRegression
}

runRegressionRealityStream() {
    runRegressionStep reality-stream-enable runRealityStreamEnableRegression &&
        runRegressionStep reality-stream-disable runRealityStreamDisableRegression
}

runRegressionRuntime() {
    runRegressionStep runtime-core runRuntimeAndRealityRegression &&
        runRegressionStep runtime-auto-install-reality-route runAutoInstallRealityRouteRegression &&
        runRegressionStep runtime-tempdir runRuntimeTempDirRegression &&
        runRegressionStep reality-config runRealityConfigRegression
}

runRegressionTransactionCore() {
    runRegressionStep config-transaction runConfigTransactionRegression &&
        runRegressionStep core-port-file-transaction runCorePortFileTransactionRegression &&
        runRegressionStep xray-reality-port-failure runXrayRealityPortFailureRegression &&
        runRegressionStep reality-profile-failure runRealityProfileFailureRegression &&
        runRegressionStep core-template-return-failure runCoreTemplateReturnFailureRegression &&
        runRegressionStep core-binary-install-copy-failure runCoreBinaryInstallCopyFailureRegression &&
        runRegressionStep network-check-return-failure runNetworkCheckReturnFailureRegression &&
        runRegressionStep tls-failure-return runTlsFailureReturnRegression &&
        runRegressionStep tls-renew-failure-propagation runTlsRenewalFailurePropagationRegression &&
        runRegressionStep service-queue-apply-propagation runServiceQueueApplyPropagationRegression &&
        runRegressionStep core-install-service-action-failure runCoreInstallServiceActionFailureRegression &&
        runRegressionStep sing-box-merge-start-failure runSingBoxMergeStartFailureRegression &&
        runRegressionStep sing-box-merge-config-transaction runSingBoxMergeConfigTransactionRegression &&
        runRegressionStep sing-box-uninstall-failure-propagation runSingBoxUninstallFailurePropagationRegression &&
        runRegressionStep sing-box-protocol-reload-failure runSingBoxProtocolReloadFailureRegression &&
        runRegressionStep geo-update-reload-failure runGeoUpdateReloadFailureRegression &&
        runRegressionStep core-cleanup-failure-propagation runCoreCleanupFailurePropagationRegression &&
        runRegressionStep reload-core-propagation runReloadCorePropagationRegression &&
        runRegressionStep sing-box-log-transaction runSingBoxLogTransactionRegression
}

runRegressionTransactionSubscription() {
    runRegressionStep subscribe-server-name runSubscribeServerNameRegression &&
        runRegressionStep subscribe-nginx-config-write runSubscribeNginxConfigWriteRegression &&
        runRegressionStep subscribe-nginx-service-failure runSubscribeNginxServiceFailureRegression &&
        runRegressionStep subscribe-user-output-transaction runSubscribeUserOutputTransactionRegression &&
        runRegressionStep remove-user-subscription-menu-failure runRemoveUserSubscriptionMenuFailureRegression &&
        runRegressionStep user-subscription-menu-mutation-failure runUserSubscriptionMenuMutationFailureRegression &&
        runRegressionStep remote-subscribe-fetch runRemoteSubscribeFetchRegression
}

runRegressionTransactionSystem() {
    runRegressionStep nginx-service-failure runNginxServiceFailureRegression &&
        runRegressionStep uninstall-nginx-cleanup runUninstallNginxCleanupRegression &&
        runRegressionStep uninstall-wireguard-cleanup runUninstallWireGuardCleanupRegression &&
        runRegressionStep uninstall-service-stop-failure runUninstallServiceStopFailureRegression &&
        runRegressionStep clean-last-installation-failure runCleanLastInstallationConfigFailureRegression &&
        runRegressionStep alone-nginx-config-transaction runAloneNginxConfigTransactionRegression
}

runRegressionTransaction() {
    runRegressionTransactionCore &&
        runRegressionTransactionSubscription &&
        runRegressionTransactionSystem
}

runRegressionRemoteControl() {
    runRegressionStep remote-control-concurrency runRemoteControlConcurrencyRegression &&
        runRegressionStep remote-control-aggregation-failure runRemoteControlAggregationFailureRegression &&
        runRegressionStep remote-control-health runRemoteControlHealthRegression &&
        runRegressionStep remote-control-server-refresh runRemoteControlServerRefreshRegression &&
        runRegressionStep remote-control-service-install runSubscriptionControlServiceInstallRegression &&
        runRegressionStep remote-control-server-response runSubscriptionControlServerResponseRegression
}

runRegressionAll() {
    runRegressionRouting &&
        runRegressionSubscription &&
        runRegressionRuntime &&
        runRegressionTransaction &&
        runRegressionRemoteControl &&
        runRegressionUi
}

regressionName=${1:-fast}
case "${regressionName}" in
fast-reality)
    regressionRunner=runRegressionFastReality
    ;;
platform-io)
    regressionRunner=runRegressionPlatformIo
    ;;
tls)
    regressionRunner=runRegressionTls
    ;;
ui)
    regressionRunner=runRegressionUi
    ;;
menu-smoke)
    regressionRunner=runRegressionMenuSmoke
    ;;
menu-smoke-full)
    regressionRunner=runRegressionMenuSmokeFull
    ;;
routing)
    regressionRunner=runRegressionRouting
    ;;
routing-socks5-udp-associate)
    regressionRunner=runSocks5UdpAssociateRegression
    ;;
subscription)
    regressionRunner=runRegressionSubscription
    ;;
subscription-output)
    regressionRunner=runRegressionSubscriptionOutput
    ;;
subscription-remote-fetch)
    regressionRunner=runRegressionSubscriptionRemoteFetch
    ;;
subscription-write-transaction)
    regressionRunner=runRegressionSubscriptionWriteTransaction
    ;;
runtime)
    regressionRunner=runRegressionRuntime
    ;;
runtime-core)
    regressionRunner=runRuntimeAndRealityRegression
    ;;
runtime-auto-install-reality-route)
    regressionRunner=runAutoInstallRealityRouteRegression
    ;;
reality-candidates)
    regressionRunner=runRegressionRealityCandidates
    ;;
reality-candidates-fast)
    regressionRunner=runRealityCandidateFastRegression
    ;;
reality-candidates-full)
    regressionRunner=runRealityCandidateFullRegression
    ;;
reality-config)
    regressionRunner=runRealityConfigRegression
    ;;
reality-stream)
    regressionRunner=runRegressionRealityStream
    ;;
transaction)
    regressionRunner=runRegressionTransaction
    ;;
transaction-core)
    regressionRunner=runRegressionTransactionCore
    ;;
transaction-subscription)
    regressionRunner=runRegressionTransactionSubscription
    ;;
transaction-system)
    regressionRunner=runRegressionTransactionSystem
    ;;
all|full|ci)
    regressionRunner=runRegressionAll
    ;;
*)
    printf 'usage: %s [fast-reality|platform-io|tls|ui|menu-smoke|menu-smoke-full|routing|routing-socks5-udp-associate|subscription|subscription-output|subscription-remote-fetch|subscription-write-transaction|runtime|runtime-core|reality-candidates|reality-candidates-fast|reality-candidates-full|reality-config|reality-stream|transaction|transaction-core|transaction-subscription|transaction-system|all|full|ci]\n' "$0" >&2
    exit 2
    ;;
esac

runRegressionStep "total:${regressionName}" "${regressionRunner}"
echo "subscription-groups-regression-ok:${regressionName}"
