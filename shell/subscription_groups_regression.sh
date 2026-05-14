#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

export PADM_SUBSCRIPTION_GROUPS_DIR="${TMP_DIR}/subscribe_groups"
export PADM_SUBSCRIBE_LOCAL_DIR="${TMP_DIR}/subscribe_local"
export PADM_VLESS_ENCRYPTION_STATE_FILE="${TMP_DIR}/vless_encryption.json"
export PADM_REALITY_TARGET_RESULTS_FILE="${TMP_DIR}/reality_targets_results.tsv"
export PADM_REALITY_TARGET_SCAN_FILE="${PADM_REALITY_TARGET_RESULTS_FILE}"
export PADM_REALITY_TARGET_BLOCKED_FILE="${TMP_DIR}/reality_target_blocked.tsv"
export PADM_SUPPRESS_PROGRESS=1

echoContent() {
    if [[ -n "${REGRESSION_ECHO_LOG:-}" ]]; then
        printf '%s\n' "$*" >>"${REGRESSION_ECHO_LOG}"
    fi
    return 0
}

menuLine() {
    return 0
}

menuItem() {
    return 0
}

menuRecommendedItem() {
    return 0
}

menuReturnItem() {
    return 0
}

menuDangerItem() {
    return 0
}

statusCard() {
    printf '%s\n' "$*" >>"${REGRESSION_STATUS_CARD_LOG:-/dev/null}"
}

progressCard() {
    return 0
}

successCard() {
    return 0
}

errorCard() {
    printf '%s\n' "$*" >>"${REGRESSION_ERROR_CARD_LOG:-/dev/null}"
}

menuClose() {
    return 0
}

# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/platform.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/protocols.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/runtime.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/reality_targets.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/protocol_runtime.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/singbox.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/routing.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/cores.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/nginx.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/network.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/entry_helpers.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/users.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/groups.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/subscription.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/control.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/wireguard_control.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/adapters.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/manage.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/state.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/tls.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/menu.sh"

reloadCore() {
    return 0
}

handleNginx() {
    return 0
}

readNginxSubscribe() {
    subscribePort=${subscribePort:-39778}
}

serviceQueueRestart() {
    return 0
}

serviceQueueApply() {
    return 0
}

cleanDirectoryContent() {
    return 0
}

subscribe() {
    return 0
}

regressionNowMs() {
    date +%s%3N 2>/dev/null || printf '%s000\n' "$(date +%s)"
}

runRegressionStep() {
    local name=$1
    shift
    local startMs endMs elapsedMs rc
    local thresholdMs=${PADM_REGRESSION_SLOW_THRESHOLD_MS:-5000}
    startMs=$(regressionNowMs)
    if [[ "${PADM_REGRESSION_VERBOSE:-}" == "1" ]]; then
        printf 'regression-start:%s\n' "${name}"
    fi
    if "$@"; then
        endMs=$(regressionNowMs)
        elapsedMs=$((endMs - startMs))
        if [[ "${PADM_REGRESSION_VERBOSE:-}" == "1" || "${name}" == total:* || "${elapsedMs}" -ge "${thresholdMs}" ]]; then
            printf 'regression-ok:%s:%sms\n' "${name}" "${elapsedMs}"
        fi
        return 0
    else
        rc=$?
        endMs=$(regressionNowMs)
        elapsedMs=$((endMs - startMs))
        printf 'regression-fail:%s:%sms:rc=%s\n' "${name}" "${elapsedMs}" "${rc}" >&2
        return "${rc}"
    fi
}

REALITY_TLS_PING_ARGS_FILE="${TMP_DIR}/tls_ping_args.txt"
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
    addSingBoxIPRouteRule "block_ip_outbound" "1.1.1.0/24,cn" "block_ip_route"
    jq -e '
      (.route.rules[0].ip_cidr | sort) == (["1.1.1.0/24", "geoip:cn"] | sort) and
      .route.rules[0].action == "reject"
    ' "${singBoxConfigPath}block_ip_route.json" >/dev/null
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
    addSingBoxGeoIPRouteRule "block_ip_outbound" "cn" "cn_block_ip_route"
    jq -e '
      .route.rules[0].rule_set == ["geoip_cn_cn_block_ip_route"] and
      .route.rules[0].action == "reject" and
      .route.rule_set[0].format == "binary"
    ' "${singBoxConfigPath}cn_block_ip_route.json" >/dev/null
    addSingBoxOutbound "01_direct_outbound"
    jq -e '.outbounds[0].tag == "01_direct_outbound"' "${singBoxConfigPath}01_direct_outbound.json" >/dev/null
    addSingBoxOutbound "IPv6_out"
    jq -e '.outbounds[0].domain_resolver.server == "dns-local" and .outbounds[0].domain_resolver.strategy == "ipv6_only" and (.outbounds[0].domain_strategy | not)' "${singBoxConfigPath}IPv6_out.json" >/dev/null
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
    setVMessWSTLSPath="/ws"
    setVMessWSTLSAddress="example.com"
    setVMessWSTLSPort=443
    setVMessWSTLSUUID="00000000-0000-0000-0000-000000000000"
    addXrayOutbound "vmess-out"
    jq -e '
      .outbounds[0].protocol == "vmess" and
      .outbounds[0].streamSettings.wsSettings.path == "/ws"
    ' "${configPath}vmess-out.json" >/dev/null
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
    initHysteriaPort() {
        :
    }
    initHysteria2Network() {
        hysteria2ClientDownloadSpeed=120
        hysteria2ClientUploadSpeed=60
    }
    initXrayClients() {
        printf '[{"password":"user-pass","name":"user-singbox_hysteria2"}]\n'
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
    reservedWarpReg='[1,2,3]'
    hysteriaPort=23456
    currentHost=example.com
    initSingBoxHysteria2Config
    jq -e '
      .inbounds[0].listen_port == 23456 and
      .inbounds[0].users[0].password == "user-pass" and
      .inbounds[0].tls.server_name == "example.com"
    ' "${singBoxConfigPath}hysteria2.json" >/dev/null
    originalContent=$(<"${singBoxConfigPath}hysteria2.json")
    hysteriaPort=
    if initSingBoxHysteria2Config 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${singBoxConfigPath}hysteria2.json")" == "${originalContent}" ]]
    [[ ! -e "${singBoxConfigPath}hysteria2.json.tmp" ]]
    unset -f readConfigWarpReg initHysteriaPort initHysteria2Network initXrayClients
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
    addSingBoxDNSConfig "1.1.1.1" "openai,example.com"
    jq -e '
      .dns.rules[0].rule_set == ["geosite_openai_dns"] and
      .dns.rules[0].domain_suffix == ["example.com"] and
      (.dns.rules[0].domain_regex | not) and
      .route.rule_set[0].format == "binary"
    ' "${singBoxConfigPath}dns.json" >/dev/null
    addSingBoxDNSConfig "203.0.113.10" "example.org" "predefined"
    jq -e '
      .dns.rules[0].domain_suffix == ["example.org"] and
      (.dns.rules[0].domain_regex | not) and
      (.dns.servers[] | select(.tag == "hosts") | .predefined["example.org"] == "203.0.113.10")
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
    unInstallSniffing
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

runUserConfigWriteRegression() {
    local targetPath="${TMP_DIR}/user-config.json"
    cat >"${targetPath}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"old"}]}}]}
JSON
    if writeUserConfigJq "${targetPath}" '.inbounds[0].settings.clients = [' 2>/dev/null; then
        return 1
    fi
    jq -e '.inbounds[0].settings.clients[0].email == "old"' "${targetPath}" >/dev/null
    [[ ! -e "${targetPath}.tmp" ]]
    writeUserConfigJq "${targetPath}" '.inbounds[0].settings.clients += [{"email":"new"}]'
    jq -e '.inbounds[0].settings.clients | length == 2 and .[1].email == "new"' "${targetPath}" >/dev/null
}

runRemoveUserRegression() {
    local xrayFile="${configPath}02_VLESS_TCP_inbounds.json"
    local trojanGrpcFile="${configPath}04_trojan_gRPC_inbounds.json"
    local httpUpgradeXrayFile="${configPath}11_VMess_HTTPUpgrade_inbounds.json"
    local httpUpgradeSingBoxFile="${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json"
    local originalContent
    mkdir -p "${configPath}" "${singBoxConfigPath}"
    cat >"${xrayFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"id":"uuid-a","email":"alpha-VLESS_TCP/TLS_Vision"},{"id":"uuid-b","email":"bravo-VLESS_TCP/TLS_Vision"}]}}]}
JSON
    cat >"${trojanGrpcFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"password":"uuid-b","email":"bravo-Trojan_gRPC"},{"password":"uuid-a","email":"alpha-Trojan_gRPC"}]}}]}
JSON
    cat >"${httpUpgradeXrayFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"id":"uuid-a","email":"alpha-VMess_HTTPUpgrade"},{"id":"uuid-b","email":"bravo-VMess_HTTPUpgrade"}]}}]}
JSON
    cat >"${httpUpgradeSingBoxFile}" <<'JSON'
{"inbounds":[{"users":[{"uuid":"uuid-a","name":"alpha-VMess_HTTPUpgrade"},{"uuid":"uuid-b","name":"bravo-VMess_HTTPUpgrade"}]}]}
JSON

    removeUserFromConfigFiles uuid-a alpha
    jq -e '(.inbounds[0].settings.clients | length == 1) and .inbounds[0].settings.clients[0].id == "uuid-b"' "${xrayFile}" >/dev/null
    jq -e '(.inbounds[0].settings.clients | length == 1) and .inbounds[0].settings.clients[0].password == "uuid-b"' "${trojanGrpcFile}" >/dev/null
    jq -e '(.inbounds[0].settings.clients | length == 1) and .inbounds[0].settings.clients[0].id == "uuid-b"' "${httpUpgradeXrayFile}" >/dev/null
    jq -e '(.inbounds[0].users | length == 1) and .inbounds[0].users[0].uuid == "uuid-b"' "${httpUpgradeSingBoxFile}" >/dev/null

    originalContent=$(<"${xrayFile}")
    if writeUserConfigJq "${xrayFile}" '.inbounds[0].settings.clients = [' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${xrayFile}")" == "${originalContent}" ]]
    [[ ! -e "${xrayFile}.tmp" ]]
}

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

runCorePortFileTransactionRegression() {
    mkdir -p "${configPath}"
    writeCoreDokodemoInbound "${configPath}02_dokodemodoor_inbounds_2053.json" 2053 443 tcp dokodemo-door-newPort-2053
    writeCoreDokodemoInbound "${configPath}02_dokodemodoor_inbounds_2083_default.json" 2083 443 tcp dokodemo-door-newPort-2083
    local original2053 original2083
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
    rm -rf "${configPath}"
}

runConfigTransactionRegression() {
    local targetFile="${TMP_DIR}/transaction.json"
    local backupFile="${targetFile}.bak"
    local originalContent updatedContent
    local reloadCountFile="${TMP_DIR}/transaction-reload-count"
    local refreshCountFile="${TMP_DIR}/transaction-refresh-count"
    local validateMode=success
    local oldPath="${PATH}"
    local checkPortNginxDir="${TMP_DIR}/check-port-nginx/"
    local checkPortTarget="${checkPortNginxDir}checkPortOpen.conf"

    transactionReloadMock() {
        printf '1\n' >>"${reloadCountFile}"
    }

    transactionRefreshMock() {
        printf '1\n' >>"${refreshCountFile}"
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

    mkdir -p "${TMP_DIR}/fake-bin" "${checkPortNginxDir}"
    cat >"${TMP_DIR}/fake-bin/nginx" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "-t" ]]
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
    [[ ! -e "${checkPortTarget}.tmp" ]]
    export PADM_FAKE_NGINX_VALIDATE_MODE=success
    writeCheckPortOpenNginxConfig 443 example.com 'listen [::]:443;'
    grep -q 'server_name example.com;' "${checkPortTarget}"
    grep -q 'listen \[::\]:443;' "${checkPortTarget}"
    [[ ! -e "${checkPortTarget}.tmp" ]]
    [[ ! -e "${checkPortTarget}.bak" ]]
    PATH="${oldPath}"
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
        rm -rf "${serviceTmp}"
    )
}

runUninstallNginxCleanupRegression() {
    local primaryDir="${TMP_DIR}/uninstall-nginx-primary/"
    local actualDir="${TMP_DIR}/uninstall-nginx-actual/"
    local oldNginxConfigPath="${nginxConfigPath:-}"
    local oldFallbackDir="${PADM_NGINX_CONF_FALLBACK_DIR:-}"
    local name

    mkdir -p "${primaryDir}" "${actualDir}"
    nginxConfigPath="${primaryDir}"
    PADM_NGINX_CONF_FALLBACK_DIR="${actualDir}"
    for name in alone.conf checkPortOpen.conf sing_box_VMess_HTTPUpgrade.conf subscribe.conf; do
        printf 'padm config\n' >"${primaryDir}${name}"
    done
    for name in sing_box_VMess_HTTPUpgrade.conf subscribe.conf; do
        printf 'padm config\n' >"${actualDir}${name}"
    done

    removePadmNginxConfigFragments
    for name in alone.conf checkPortOpen.conf sing_box_VMess_HTTPUpgrade.conf subscribe.conf; do
        [[ ! -e "${primaryDir}${name}" ]]
    done
    for name in sing_box_VMess_HTTPUpgrade.conf subscribe.conf; do
        [[ ! -e "${actualDir}${name}" ]]
    done
    nginxConfigPath="${oldNginxConfigPath}"
    PADM_NGINX_CONF_FALLBACK_DIR="${oldFallbackDir}"
}

runEntryHelperConfigRegression() {
    local entryConfigPath="${TMP_DIR}/entry-helper-conf/"
    local entryLogBase="${TMP_DIR}/entry-helper-logs/"
    local realityVisionFile="${entryConfigPath}07_VLESS_vision_reality_inbounds.json"
    local realityXhttpFile="${entryConfigPath}12_VLESS_XHTTP_inbounds.json"
    local oldPath="${PATH}"
    local nginxTarget="${TMP_DIR}/entry-helper-nginx/sing_box_VMess_HTTPUpgrade.conf"
    local originalContent
    mkdir -p "${entryConfigPath}" "${entryLogBase}" "${TMP_DIR}/fake-bin" "${TMP_DIR}/entry-helper-nginx"
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
    writeXrayLogConfig "${entryConfigPath}00_log.json" "${entryLogBase}" true
    [[ "$(jq -r '.log.access' "${entryConfigPath}00_log.json")" == "${entryLogBase}access.log" ]]
    [[ "$(jq -r '.log.error' "${entryConfigPath}00_log.json")" == "${entryLogBase}error.log" ]]
    [[ "$(jq -r '.log.loglevel' "${entryConfigPath}00_log.json")" == "debug" ]]
    writeXrayLogConfig "${entryConfigPath}00_log.json" "${entryLogBase}" false
    jq -e '(.log.access | not)' "${entryConfigPath}00_log.json" >/dev/null
    [[ "$(jq -r '.log.error' "${entryConfigPath}00_log.json")" == "${entryLogBase}error.log" ]]
    [[ "$(jq -r '.log.loglevel' "${entryConfigPath}00_log.json")" == "warning" ]]

    nginxConfigPath="${TMP_DIR}/entry-helper-nginx/"
    domain=example.com
    nginxStaticPath="${TMP_DIR}/static"
    currentPath=padm
    selectCustomInstallType=11
    printf 'old config\n' >"${nginxTarget}"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    if singBoxNginxConfig 11 443 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${nginxTarget}")" == "old config" ]]
    [[ ! -e "${nginxTarget}.tmp" ]]
    export PADM_FAKE_NGINX_VALIDATE_MODE=success
    singBoxNginxConfig 11 443
    grep -q 'server_name example.com;' "${nginxTarget}"
    grep -q 'location /padm' "${nginxTarget}"
    [[ ! -e "${nginxTarget}.tmp" ]]
    [[ ! -e "${nginxTarget}.bak" ]]

    cat >"${realityVisionFile}" <<'JSON'
{"inbounds":[{"streamSettings":{"realitySettings":{"show":false}}}]}
JSON
    updateRealityShowConfig "${realityVisionFile}" true
    jq -e '.inbounds[0].streamSettings.realitySettings.show == true' "${realityVisionFile}" >/dev/null
    originalContent=$(<"${realityVisionFile}")
    if updateRoutingJsonConfig "${realityVisionFile}" '.inbounds[0].streamSettings.realitySettings.show = [' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${realityVisionFile}")" == "${originalContent}" ]]
    [[ ! -e "${realityVisionFile}.tmp" ]]

    cat >"${realityXhttpFile}" <<'JSON'
{"inbounds":[{"streamSettings":{"realitySettings":{"show":true}}}]}
JSON
    updateRealityShowConfig "${realityXhttpFile}" false
    jq -e '.inbounds[0].streamSettings.realitySettings.show == false' "${realityXhttpFile}" >/dev/null
    PATH="${oldPath}"
    unset PADM_FAKE_NGINX_VALIDATE_MODE
}

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
    mkdir -p "${TMP_DIR}/fake-bin" "${TMP_DIR}/nginx-subscribe"
    nginxConfigPath="${TMP_DIR}/nginx-subscribe/"
    cat >"${TMP_DIR}/fake-bin/nginx" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "-t" ]]
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
    [[ ! -e "${targetPath}.tmp" ]]
    export PADM_FAKE_NGINX_VALIDATE_MODE=success
    writeSubscribeNginxConfig <<'EOF'
new config
EOF
    [[ "$(<"${targetPath}")" == "new config" ]]
    [[ ! -e "${targetPath}.tmp" ]]
    [[ ! -e "${targetPath}.bak" ]]
    PATH="${oldPath}"
    unset PADM_FAKE_NGINX_VALIDATE_MODE
}

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

    export PADM_FAKE_NGINX_VALIDATE_MODE=success
    updateRedirectNginxConf
    grep -q 'server_name example.com;' "${targetPath}"
    [[ ! -e "${targetPath}.tmp" ]]
    [[ ! -e "${targetPath}.bak" ]]

    printf 'keep\nreturn 302 https://example.org;\nreturn 302 $scheme://example.org$request_uri;\n' >"${targetPath}"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    if removeNginx302 2>/dev/null; then
        return 1
    fi
    grep -q 'return 302 https://example.org;' "${targetPath}"

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

    printf 'server {\n}\n' >"${targetPath}"
    if addNginx302 https://missing-location.example 2>/dev/null; then
        return 1
    fi
    ! grep -q 'missing-location.example' "${targetPath}"

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
    local localDir="${TMP_DIR}/subscribe-user-local"
    local publicDir="${TMP_DIR}/subscribe-user-public"
    local email="atomic-user"
    local emailMd5="atomic-md5"
    export PADM_SUBSCRIBE_LOCAL_DIR="${localDir}"
    export PADM_SUBSCRIBE_DIR="${publicDir}"
    SCRIPT_DIR="${PROJECT_ROOT}"
    subscribeType=https
    subscribeSalt=salt
    mkdir -p "${localDir}/default" "${localDir}/clashMeta" "${localDir}/sing-box" "${publicDir}/default" "${publicDir}/clashMeta" "${publicDir}/clashMetaProfiles" "${publicDir}/sing-box" "${publicDir}/sing-box_profiles"

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

    writeLocalSubscribeOutputs
    renderSubscribeUserOutputs "${email}" "${emailMd5}" "example.com" n true
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
    SCRIPT_DIR="${oldScriptDir}"
}

runRealityStreamDisableRegression() {
    local oldPath="${PATH}"
    local fakeBin="${TMP_DIR}/fake-reality-stream-bin"
    local streamDir="${TMP_DIR}/reality-stream"
    local visionFile="${streamDir}/07_VLESS_vision_reality_inbounds.json"
    local xhttpFile="${streamDir}/12_VLESS_XHTTP_inbounds.json"
    local stateFile="${streamDir}/reality_stream_split.json"
    local streamConf="${streamDir}/padm-reality.conf"
    local nginxMainConf="${streamDir}/nginx.conf"
    local originalVision originalXHTTP originalState originalStreamConf originalNginxConf
    mkdir -p "${fakeBin}" "${streamDir}"
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
    disableRealityStreamSplit
    jq -e '(.inbounds[0].listen | not) and .inbounds[0].port == 443' "${visionFile}" >/dev/null
    jq -e '.inbounds[0].listen == "0.0.0.0" and .inbounds[0].port == 443' "${xhttpFile}" >/dev/null
    [[ ! -e "${stateFile}" ]]
    [[ ! -e "${streamConf}" ]]
    ! grep -q 'padm stream include start' "${nginxMainConf}"

    PATH="${oldPath}"
    unset PADM_REALITY_STREAM_STATE_FILE PADM_REALITY_STREAM_CONF_FILE PADM_REALITY_STREAM_NGINX_CONF PADM_REALITY_STREAM_XRAY_BINARY PADM_REALITY_STREAM_XRAY_CONF_DIR PADM_REALITY_STREAM_VISION_CONFIG_FILE PADM_REALITY_STREAM_XHTTP_CONFIG_FILE PADM_FAKE_REALITY_STREAM_NGINX_VALIDATE_MODE PADM_FAKE_REALITY_STREAM_XRAY_VALIDATE_MODE
}

runRealityStreamEnableRegression() {
    local oldPath="${PATH}"
    local oldAutoInstall="${AUTO_INSTALL:-}"
    local fakeBin="${TMP_DIR}/fake-reality-stream-enable-bin"
    local streamDir="${TMP_DIR}/reality-stream-enable"
    local visionFile="${streamDir}/07_VLESS_vision_reality_inbounds.json"
    local xhttpFile="${streamDir}/12_VLESS_XHTTP_inbounds.json"
    local stateFile="${streamDir}/reality_stream_split.json"
    local streamConf="${streamDir}/padm-reality.conf"
    local nginxMainConf="${streamDir}/nginx.conf"
    local originalVision originalXHTTP originalNginxConf
    mkdir -p "${fakeBin}" "${streamDir}"
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
    chmod +x "${fakeBin}/nginx" "${fakeBin}/fake-xray"
    PATH="${fakeBin}:${PATH}"
    export PADM_REALITY_STREAM_STATE_FILE="${stateFile}"
    export PADM_REALITY_STREAM_CONF_FILE="${streamConf}"
    export PADM_REALITY_STREAM_NGINX_CONF="${nginxMainConf}"
    export PADM_REALITY_STREAM_XRAY_BINARY="${fakeBin}/fake-xray"
    export PADM_REALITY_STREAM_XRAY_CONF_DIR="${streamDir}"
    export PADM_REALITY_STREAM_VISION_CONFIG_FILE="${visionFile}"
    export PADM_REALITY_STREAM_XHTTP_CONFIG_FILE="${xhttpFile}"
    AUTO_INSTALL=true
    coreInstallType=1
    currentInstallProtocolType=",7,12"
    AUTO_REALITY_STREAM_ENABLE=y
    AUTO_REALITY_STREAM_DOMAINS="site.example.com"
    AUTO_REALITY_STREAM_DEFAULT_PROTOCOL=1
    AUTO_REALITY_STREAM_WEBSITE_PORT=8443
    AUTO_REALITY_STREAM_VISION_PORT=2443
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
    configureRealityStreamSplit
    jq -e '.inbounds[0].listen == "127.0.0.1" and .inbounds[0].port == 2443' "${visionFile}" >/dev/null
    jq -e '.enabled == true and .default_protocol == "vision" and .protocols.vision.restore_port == 443 and .protocols.vision.internal_port == 2443' "${stateFile}" >/dev/null
    grep -q 'site.example.com padm_website;' "${streamConf}"
    grep -q 'padm stream include start' "${nginxMainConf}"
    [[ ! -e "${streamConf}.tmp" ]]

    PATH="${oldPath}"
    AUTO_INSTALL="${oldAutoInstall}"
    unset PADM_REALITY_STREAM_STATE_FILE PADM_REALITY_STREAM_CONF_FILE PADM_REALITY_STREAM_NGINX_CONF PADM_REALITY_STREAM_XRAY_BINARY PADM_REALITY_STREAM_XRAY_CONF_DIR PADM_REALITY_STREAM_VISION_CONFIG_FILE PADM_REALITY_STREAM_XHTTP_CONFIG_FILE PADM_FAKE_REALITY_STREAM_NGINX_VALIDATE_MODE PADM_FAKE_REALITY_STREAM_XRAY_VALIDATE_MODE AUTO_REALITY_STREAM_ENABLE AUTO_REALITY_STREAM_DOMAINS AUTO_REALITY_STREAM_DEFAULT_PROTOCOL AUTO_REALITY_STREAM_WEBSITE_PORT AUTO_REALITY_STREAM_VISION_PORT
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

    [[ "$(realityTargetCandidateCount)" == "5" ]]
    [[ "$(realityTargetFilteredCandidateCount recommended)" == "4" ]]
    [[ "$(realityTargetFilteredCandidateCount developer)" == "1" ]]
    [[ "$(realityTargetFilteredCandidateCount asia)" == "1" ]]
    [[ "$(realityTargetFilteredCandidateCount microsoft)" == "1" ]]
    firstRecommendedRealityCandidate=$(realityTargetFilteredCandidateLineByIndex recommended 1)
    [[ "$(realityTargetCandidateField "${firstRecommendedRealityCandidate}" 1)" == "www.ibm.com" ]]
    firstDeveloperRealityCandidate=$(realityTargetFilteredCandidateLineByIndex developer 1)
    [[ "$(realityTargetCandidateField "${firstDeveloperRealityCandidate}" 5)" == "developer" ]]
    targetAsnSummary=$(realityTargetAsnSummary "www.ibm.com")
    [[ "${targetAsnSummary}" == "192.0.2.1 AS64500 ExampleNet" ]]
    currentAsnSummary=$(currentRealityAsnSummary)
    [[ "${currentAsnSummary}" == "203.0.113.10 AS64500 ExampleNet" ]]
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
    local _sampleIp
    AUTO_INSTALL=
    cat >"${asnPrefixFile}" <<'EOF'
192.0.2.0/24
198.51.100.0/25
203.0.113.0/26
10.0.0.0/27
172.16.0.0/28
EOF
    [[ "$(filterRealityAsnPrefixesByMask 28 32 <"${asnPrefixFile}" | wc -l | tr -d ' ')" == "1" ]]
    [[ "$(filterRealityAsnPrefixesByMask 27 32 <"${asnPrefixFile}" | wc -l | tr -d ' ')" == "2" ]]
    [[ "$(filterRealityAsnPrefixesByMask 26 32 <"${asnPrefixFile}" | wc -l | tr -d ' ')" == "3" ]]
    [[ "$(filterRealityAsnPrefixesByMask 25 32 <"${asnPrefixFile}" | wc -l | tr -d ' ')" == "4" ]]
    [[ "$(filterRealityAsnPrefixesByMask 24 32 <"${asnPrefixFile}" | wc -l | tr -d ' ')" == "5" ]]
    [[ "$(realityAsnPrefixAddressCount "172.16.0.0/28")" == "16" ]]
    [[ "$(realityAsnPrefixTotalAddressCount <"${asnPrefixFile}")" == "496" ]]
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
    [[ "$(realityTargetCandidateCount)" -ge 194 ]]
    [[ "$(realityTargetFilteredCandidateCount recommended)" -ge 50 ]]
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
    protocolSelectionNeedsReality 7
    protocolSelectionNeedsCertificate 0
    protocolSelectionNeedsUdp 6
    protocolSelectionTransportHas 7 tcp
    protocolSelectionSecurityHas 7 reality

    parseInstallArgs --install-type custom --core xray --protocols 7 --domain node.example.com --reality-target www.microsoft.com:443 --reality-server-name www.microsoft.com --entry-host node.example.com --reuse-last no
    [[ "${AUTO_REALITY_TARGET}" == "www.microsoft.com:443" ]]
    [[ "${AUTO_REALITY_SERVER_NAME}" == "www.microsoft.com" ]]
    [[ "${AUTO_ENTRY_HOST}" == "node.example.com" ]]
    [[ "$(autoValueForKey reality_target)" == "www.microsoft.com:443" ]]
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
    scoreLine=$(scoreRealityTargetFromTlsPing $'Pinging with SNI\nTLS Post-Quantum key exchange: X25519MLKEM768\nTLS version: TLS 1.3\nCertificate chain total length: 4096')
    [[ "$(printf '%s\n' "${scoreLine}" | awk -F'\t' '{print $1}')" == "A" ]]
    showRealityTargetQuality "www.microsoft.com:443"
    [[ "$(realityTargetResultCount)" -ge "1" ]]
    cachedLine=$(realityTargetCachedLine "www.microsoft.com:443")
    [[ "$(printf '%s\n' "${cachedLine}" | awk -F'\t' '{print $1}')" == "A" ]]
    grep -q "tls ping www.microsoft.com:443" "${REALITY_TLS_PING_ARGS_FILE}"
    scoreLine=$(scoreRealityTargetFromTlsPing $'Pinging with SNI\nTLS Post-Quantum key exchange: X25519MLKEM768\nTLS version: TLS 1.3\nCertificate chain total length: 2048')
    [[ "$(printf '%s\n' "${scoreLine}" | awk -F'\t' '{print $1}')" == "B" ]]
    scoreLine=$(scoreRealityTargetFromTlsPing $'Pinging with SNI\nTLS version: TLS 1.3\nCertificate chain total length: 4096')
    [[ "$(printf '%s\n' "${scoreLine}" | awk -F'\t' '{print $1}')" == "C" ]]
    scoreLine=$(scoreRealityTargetFromTlsPing $'Pinging with SNI\nTLS version: TLS 1.2\nCertificate chain total length: 4096')
    [[ "$(printf '%s\n' "${scoreLine}" | awk -F'\t' '{print $1}')" == "FAIL" ]]
}

runRealityConfigVlessEncryptionRegression() {
    local fakeXrayBinary="${TMP_DIR}/fake-xray-vlessenc"
    local vlessConfigDir="${TMP_DIR}/vlessenc-xray-conf"
    local vlessConfigFile="${vlessConfigDir}/07_VLESS_vision_reality_inbounds.json"
    local vlessStateFile="${TMP_DIR}/vlessenc-state.json"
    local vlessOriginalConfig
    local vlessOriginalState
    local vlessValidateMode=success
    cat >"${fakeXrayBinary}" <<'SH'
#!/usr/bin/env bash
case "$1" in
--version)
    printf 'Xray 25.9.5 test\n'
    ;;
vlessenc)
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

    export PADM_FAKE_XRAY_VALIDATE_MODE="success"
    setVlessRealityEncryption enable
    jq -e '.inbounds[0].settings.decryption == "mlkem768x25519plus.native.0rtt.test" and (.inbounds[0].settings.fallbacks | not) and .inbounds[0].settings.clients[0].flow == "xtls-rprx-vision"' "${vlessConfigFile}" >/dev/null
    jq -e '.enabled == true and .encryption == "mlkem768x25519plus.native.0rtt.test"' "${vlessStateFile}" >/dev/null
    [[ ! -e "${vlessConfigFile}.vlessenc.bak" ]]
    [[ ! -e "${vlessStateFile}.bak" ]]
    setVlessRealityEncryption disable
    jq -e '.inbounds[0].settings.decryption == "none" and (.inbounds[0].settings.fallbacks | not)' "${vlessConfigFile}" >/dev/null
    [[ ! -e "${vlessStateFile}" ]]
    unset PADM_XRAY_BINARY PADM_XRAY_CONF_DIR PADM_VLESS_REALITY_CONFIG_FILE PADM_VLESS_XHTTP_CONFIG_FILE PADM_VLESS_ENCRYPTION_STATE_FILE PADM_FAKE_XRAY_VALIDATE_MODE
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
    scannerImport=$(realityTargetImportScannerCandidates "${TMP_DIR}/realitlscanner.csv")
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
    writeRealityTargetCandidateLine "batch-old.example.com" "batch-old.example.com" "Batch Old" "global" "large_site" "unknown" "9" "yes" "batch candidate" >>"${scannerCandidatesFile}"
    removeRealityTargetsFromUnifiedLibrary "${failedTargetsFile}"
    ! grep -qF $'batch-old.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
    ! grep -qF 'batch-old.example.com|' "${scannerCandidatesFile}"

    rm -f "${PADM_REALITY_TARGET_SCAN_FILE}" "${REALITY_TLS_PING_ARGS_FILE}"
    realityTargetCandidateBlocked "images.apple.com"
    unset AUTO_REALITY_SERVER_NAME
    writeRealityTargetResultLine "local.example.com:443" "sni.local.example.com" "Local Example" "test" "no" "192.0.2.1" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "same ASN test target"
    writeRealityTargetResultLine "remote.example.com:443" "sni.remote.example.com" "Remote Example" "test" "no" "198.51.100.1" "AS64501" "RemoteNet" "different_network" "A" "yes" "8192" "yes" "1234567899" "longer cert but different network"
    [[ "$(realityTargetResultCount)" == "2" ]]
    scanLine=$(realityTargetResultLineByIndex 1)
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
    runRegressionStep reality-config-xhttp-download-settings runXHTTPDownloadSettingsRegression
    runRegressionStep reality-config-refresh-subscription runRealityConfigRefreshSubscriptionRegression
    runRegressionStep reality-config-import-skip runRealityConfigImportSkipRegression
}

runSubscriptionOutputRegression() {
    rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
    export REGRESSION_ECHO_LOG="${SUBSCRIBE_CAPTURE_DIR}/screen.log"
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

    local credential decodedCredential
    credential=$(subscriptionWireGuardCredentialEncode controlled '{"address":"10.77.0.2/24","public_key":"pubkey-abc","control_port":39778,"token":"token-abc"}')
    decodedCredential=$(subscriptionWireGuardCredentialDecode "${credential}")
    jq -e '.kind == "controlled" and .address == "10.77.0.2/24" and .control_port == 39778 and .token == "token-abc"' <<<"${decodedCredential}" >/dev/null
    if subscriptionWireGuardCredentialDecode "remote.example.com:39778:token-abc" >/dev/null 2>&1; then
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

    if normalizeSubscriptionSourceInput 'remote.example.com:443:edge' >/dev/null 2>&1; then
        return 1
    fi
    if normalizeSubscriptionSourceInput '203.0.113.10:39778:vps1' >/dev/null 2>&1; then
        return 1
    fi

    addSubscriptionSourceState remote-edge remote-edge "10.77.0.2" 39778
    setSubscriptionSourceControlToken remote-edge "token-abc"
    jq -e '.groups[0].sources[] | select(.id == "remote-edge" and .scheme == "wireguard" and .transport == "wireguard" and .host == "10.77.0.2" and .port == 39778 and .control_token == "token-abc")' "$(subscriptionGroupsFile)" >/dev/null
    setSubscriptionSourceCredential remote-edge "10.77.0.3" 48779 "token-def"
    jq -e '.groups[0].sources[] | select(.id == "remote-edge" and .scheme == "wireguard" and .transport == "wireguard" and .host == "10.77.0.3" and .port == 48779 and .control_token == "token-def")' "$(subscriptionGroupsFile)" >/dev/null

    setSubscriptionSourceEnabled edge false
    jq -e '.groups[0].sources[] | select(.id == "edge" and .enabled == false)' "$(subscriptionGroupsFile)" >/dev/null
    setSubscriptionSourceEnabled main false
    jq -e '.groups[0].sources[] | select(.id == "main" and .enabled == true)' "$(subscriptionGroupsFile)" >/dev/null
    clearSubscriptionSourceSyncError edge
    jq -e '(.groups[0].sources[] | select(.id == "edge") | has("last_sync_error")) | not' "$(subscriptionGroupsFile)" >/dev/null
    removeSubscriptionSourceState edge
    jq -e '(.groups[0].sources | map(.id) | index("edge") | not) and (.groups[0].traffic.sources | has("edge") | not) and (.groups[0].traffic.user_groups["team-a"].sources | has("edge") | not)' "$(subscriptionGroupsFile)" >/dev/null

    currentHost="self.example.com"
    subscribeDomain="self.example.com"
    subscribePort=39778
    subscriptionGroupsStateWrite '
      .groups[0].sources |= map(if .id == "remote-edge" then .enabled = false else . end) |
      .groups[0].sources += [{"id":"self-ref","name":"SelfRef","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"10.77.0.1","port":39778,"enabled":true,"sync_status":"pending","control_token":"token"}] |
      .groups[0].user_groups = (.groups[0].user_groups | map(if .id == "team-a" then .allowed_sources = ["self-ref"] else . end))
    '
    subscriptionRemoteControlRequest() {
        printf '{"ok":true,"changed":false,"plan":{"create":[],"remove":[]}}\n'
    }
    subscriptionRemoteSyncPlan | jq -e '.[] | select(.source_id == "self-ref" and .status == "self_reference" and .error_detail.type == "self_reference")' >/dev/null
    runSubscriptionRemoteSync | jq -e '.[] | contains("self-ref")' >/dev/null
    subscriptionGroupsStateRead -e '.groups[0].sources[] | select(.id == "self-ref" and .sync_status == "failed" and .last_sync_error.type == "self_reference")' >/dev/null
    local stateSnapshot badBackup legacyBackup
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
}

runRemoteSubscribeFetchRegression() {
    local publicDir="${TMP_DIR}/remote-subscribe-public"
    local localDir="${TMP_DIR}/remote-subscribe-local"
    local email="user@example.com"
    local emailMd5="hash-user"
    local oldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
    local oldPublicDir="${PADM_SUBSCRIBE_DIR:-}"
    export PADM_SUBSCRIBE_LOCAL_DIR="${localDir}"
    export PADM_SUBSCRIBE_DIR="${publicDir}"
    rm -rf "${publicDir}" "${localDir}"
    mkdir -p "${publicDir}/default" "${publicDir}/clashMeta" "${localDir}/sing-box"

    writeRemoteSubscribeOldOutputs() {
        printf 'old-default\n' >"${publicDir}/default/${emailMd5}"
        printf 'old-clash\n' >"${publicDir}/clashMeta/${emailMd5}"
        printf '[{"tag":"old-local"}]\n' >"${localDir}/sing-box/${email}"
    }

    listRemoteSubscribeSources() {
        printf '%s\n' 'remote1.example:443:r1:https' 'remote2.example:443:r2:https'
    }

    fetchRemoteSubscribeContent() {
        local url=$1
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

    writeRemoteSubscribeOldOutputs
    unset PADM_FAKE_REMOTE_SUBSCRIBE_MODE
    updateRemoteSubscribe "${emailMd5}" "${email}"
    grep -qxF -- '- name: "user@example.com_r1"' "${publicDir}/clashMeta/${emailMd5}"
    grep -qxF 'vless://uuid@remote1.example:443#user@example.com_r1' "${publicDir}/default/${emailMd5}"
    jq -e '.[0].tag == "old-local" and .[1].tag == "user@example.com_r1"' "${localDir}/sing-box/${email}" >/dev/null
    [[ ! -e "${publicDir}/default/${emailMd5}.tmp" ]]
    [[ ! -e "${publicDir}/clashMeta/${emailMd5}.tmp" ]]
    [[ ! -e "${localDir}/sing-box/${email}.tmp" ]]

    if [[ -n "${oldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${oldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
    if [[ -n "${oldPublicDir}" ]]; then export PADM_SUBSCRIBE_DIR="${oldPublicDir}"; else unset PADM_SUBSCRIBE_DIR; fi
}

runRemoteControlConcurrencyRegression() {
    mkdir -p "$(dirname "$(subscriptionGroupsFile)")"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"https","host":"main.example","port":443,"enabled":true,"sync_status":"success"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"remote_enabled":true,"quota_auto_apply":false},"traffic":{"user_groups":{},"sources":{},"admin":{"sources":{}}}}]}
JSON
    subscriptionGroupsStateWrite '
      .groups[0].sources += [range(0;12) as $i | {id:("src" + ($i|tostring)), name:("Src" + ($i|tostring)), role:"secondary", scheme:"https", host:("remote" + ($i|tostring) + ".example"), port:443, enabled:true, sync_status:"pending", control_token:("token" + ($i|tostring))}]
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
        [[ "${id}" == "src0" ]] && sleep 0.05
        printf '{"id":"%s","name":"%s","ok":true}\n' "${id}" "${id}"
    }

    subscriptionRemoteControlRequest() {
        local source=$1
        local endpoint=$2
        local sourceId
        sourceId=$(regressionSourceId "${source}")
        [[ "${sourceId}" == "src0" ]] && sleep 0.05
        printf '{"ok":true,"changed":false,"plan":{"create":[],"remove":[]},"source_id":"%s","endpoint":"%s"}\n' "${sourceId}" "${endpoint}"
    }

    subscriptionRemoteSyncPlanForSource() {
        local source=$1
        local sourceId
        sourceId=$(regressionSourceId "${source}")
        [[ "${sourceId}" == "src0" ]] && sleep 0.05
        printf '{"source_id":"%s","status":"success","dry_run":true,"request":{"source_id":"%s"},"response":{"ok":true,"changed":false,"plan":{"create":[],"remove":[]}}}\n' "${sourceId}" "${sourceId}"
    }

    subscriptionRemoteControlHealthAll | jq -e 'length == 12 and .[0].id == "src0" and .[2].id == "src2" and .[10].id == "src10"' >/dev/null
    subscriptionRemoteSyncPlan | jq -e 'length == 12 and .[0].source_id == "src0" and .[2].source_id == "src2" and .[10].source_id == "src10" and all(.[]; .status == "success")' >/dev/null
}

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

runXrayTrafficStatsJqCompatibilityRegression() {
    local fakeBin="${TMP_DIR}/fake-xray-stats-bin"
    local oldXrayStatsBinary="${XRAY_STATS_BINARY:-}"
    mkdir -p "${fakeBin}"
    cat >"${fakeBin}/xray" <<'SH'
#!/usr/bin/env bash
cat <<'JSON'
{"stat":[{"name":"user>>>team-uplink","value":3},{"name":"user>>>team-downlink","value":5},{"name":"user>>>ignored-uplink","value":7}]}
JSON
SH
    chmod +x "${fakeBin}/xray"
    XRAY_STATS_BINARY="${fakeBin}/xray"
    collectXrayTrafficStatsSnapshot '["team"]' | jq -e '. == [{"account":"team","upload":3,"download":5}]' >/dev/null
    XRAY_STATS_BINARY="${oldXrayStatsBinary}"
}

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
    menu() { recordMenuAction menu; }
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
    manageXHTTP() { recordMenuAction manageXHTTP; }
    manageHysteria() { recordMenuAction manageHysteria; }
    manageTuic() { recordMenuAction manageTuic; }
    addCorePort() { recordMenuAction addCorePort; }
    manageCDN() { recordMenuAction manageCDN; }

    installMenu <<<"6"
    assertMenuAction menu
    grep -q "不知道怎么选时，建议直接选 1" <<<"${output}"
    grep -q "entry 是客户端连接地址" <<<"${output}"
    [[ "$(protocolMenuDescription 10)" == "TLS 指纹抗性优先；sing-box / tcp / tls" ]]
    [[ "$(protocolMenuDescription 13)" == "sing-box AnyTLS 按需；sing-box / tcp / tls" ]]
    coreInstallType="${oldCoreInstallType}"
}

runMenuSmokeRegression() {
    local actions=
    local oldConfigPath="${configPath:-}"
    local oldCoreInstallType="${coreInstallType:-}"
    local oldRealityPageSize="${REALITY_TARGET_PAGE_SIZE:-}"
    local wgChoice
    local wgAction
    local wgActions=(
        "1:initSubscriptionWireGuardMain"
        "2:initSubscriptionWireGuardControlled"
        "3:showSubscriptionWireGuardMainCredential"
        "4:importSubscriptionWireGuardMainCredential"
        "5:showSubscriptionWireGuardControlledCredential"
        "6:showSubscriptionWireGuardPeers"
        "7:testSubscriptionWireGuardControl"
        "8:restartSubscriptionWireGuardControl"
        "9:disableSubscriptionWireGuardControl"
    )
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
    menuLine() { output+="$*"$'\n'; }
    menuMutedLine() { output+="$*"$'\n'; }
    menuClose() { return 0; }
    menuRecommendedItem() { return 0; }
    menuReturnItem() { return 0; }
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
    showSubscriptionSources() { recordMenuAction showSubscriptionSources; }
    showSubscriptionWireGuardMainCredential() { recordMenuAction showSubscriptionWireGuardMainCredential; }
    showSubscriptionWireGuardControlledCredential() { recordMenuAction showSubscriptionWireGuardControlledCredential; }
    importSubscriptionWireGuardMainCredential() { recordMenuAction importSubscriptionWireGuardMainCredential; }
    initSubscriptionWireGuardMain() { recordMenuAction initSubscriptionWireGuardMain; }
    initSubscriptionWireGuardControlled() { recordMenuAction initSubscriptionWireGuardControlled; }
    showSubscriptionWireGuardPeers() { recordMenuAction showSubscriptionWireGuardPeers; }
    testSubscriptionWireGuardControl() { recordMenuAction testSubscriptionWireGuardControl; }
    restartSubscriptionWireGuardControl() { recordMenuAction restartSubscriptionWireGuardControl; }
    disableSubscriptionWireGuardControl() { recordMenuAction disableSubscriptionWireGuardControl; }
    showSubscriptionWireGuardStatus() { recordMenuAction showSubscriptionWireGuardStatus; }
    showAccounts() { recordMenuAction showAccounts; }
    showUserSubscriptions() { recordMenuAction showUserSubscriptions; }
    createAndSyncUserSubscriptionWizard() { recordMenuAction createAndSyncUserSubscriptionWizard; }
    manageUserSubscriptionItem() { recordMenuAction manageUserSubscriptionItem; }
    installSubscribe() { recordMenuAction installSubscribe; }
    manageSubscriptionSyncSettings() { recordMenuAction manageSubscriptionSyncSettings; }
    manageSubscriptionStateBackups() { recordMenuAction manageSubscriptionStateBackups; }
    runSubscriptionGroupSync() { recordMenuAction "runSubscriptionGroupSync:$*"; }
    subscriptionSyncPlan() { recordMenuAction subscriptionSyncPlan; printf '[]\n'; }
    subscriptionRemoteSyncPlan() { recordMenuAction subscriptionRemoteSyncPlan; printf '[]\n'; }
    subscriptionQuotaDryRunPlan() { recordMenuAction subscriptionQuotaDryRunPlan; printf '[]\n'; }
    executeSubscriptionQuotaPlanMenu() { recordMenuAction executeSubscriptionQuotaPlanMenu; }
    setSubscriptionSourceControlTokenMenu() { recordMenuAction setSubscriptionSourceControlTokenMenu; }
    showAdminSubscriptionTraffic() { recordMenuAction showAdminSubscriptionTraffic; }
    collectSubscriptionTraffic() { recordMenuAction collectSubscriptionTraffic; return 0; }
    refreshSubscriptionGroupSyncCron() { recordMenuAction refreshSubscriptionGroupSyncCron; }
    xrayInstalled() { return 0; }
    singBoxInstalled() { return 0; }
    getXrayCurrentVersion() { printf 'v1.0.0\n'; }
    getSingBoxCurrentVersion() { printf 'v1.0.0\n'; }
    xrayRunning() { return 0; }
    singBoxRunning() { return 1; }
    validateXrayConfigWithBinary() { return 0; }
    singBoxConfigInstalled() { return 1; }
    crontab() { return 1; }
    coreReleaseTags() { recordMenuAction "unexpected-network-version-fetch"; return 1; }
    subscriptionGroupsStateRead() {
        if [[ "$1" == "-r" ]]; then
            recordMenuAction "subscriptionGroupsStateRead:$*"
        fi
        jq -n '{groups:[{id:"default", sources:[], user_groups:[], traffic:{global:{upload:0,download:0}, admin:{upload:0,download:0}, user_groups:{}, sources:{}}}], upload:0, download:0}'
    }
    local geoOverviewDir="${TMP_DIR}/menu-smoke-xray-geo"
    mkdir -p "${geoOverviewDir}/conf"
    printf '#!/usr/bin/env bash\ncase "$1" in --version) printf "Xray 1.0.0 test\\n" ;; -test) exit 0 ;; *) exit 1 ;; esac\n' >"${geoOverviewDir}/xray"
    chmod +x "${geoOverviewDir}/xray"
    printf 'geoip' >"${geoOverviewDir}/geoip.dat"
    printf 'geosite' >"${geoOverviewDir}/geosite.dat"
    printf 'v20260513' >"${geoOverviewDir}/geo.version"
    local output=
    PADM_XRAY_DIR="${geoOverviewDir}" showCoreStatusOverview
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
    protocolEntryMenu <<<"1
2
7
r"
    assertMenuAction 'statusCard:已取消'

    configPath="${TMP_DIR}/menu-smoke-xray/"
    coreInstallType=1
    ensureSubscriptionGroupsState
    resetMenuActions
    manageSubscription <<<"7"
    assertMenuAction menu
    resetMenuActions
    manageSubscription <<<"1
5
7"
    assertMenuAction menu
    resetMenuActions
    manageSubscription <<<"2
5
7"
    assertMenuAction menu
    resetMenuActions
    manageSubscription <<<"3
6
7"
    assertMenuAction menu
    resetMenuActions
    manageSubscription <<<"4
9
7"
    assertMenuAction menu
    resetMenuActions
    manageSubscription <<<"5
8
7"
    assertMenuAction menu
    resetMenuActions
    manageSubscription <<<"6
6
7"
    assertMenuAction menu
    resetMenuActions
    manageSubscriptionService <<<"1
4
7"
    assertMenuAction installSubscribe
    assertMenuAction menu
    resetMenuActions
    manageSubscriptionService <<<"2
4
7"
    assertMenuAction subscribe
    assertMenuAction menu
    resetMenuActions
    manageSubscriptionService <<<"3
4
7"
    assertMenuAction showSubscriptionServiceStatus
    assertMenuAction menu
    resetMenuActions
    manageMySubscription <<<"1
5
7"
    assertMenuAction subscribe
    assertMenuAction menu
    resetMenuActions
    manageMySubscription <<<"2
5
7"
    assertMenuAction subscribe
    assertMenuAction menu
    resetMenuActions
    manageMySubscription <<<"3
5
7"
    assertMenuAction showSubscriptionSources
    assertMenuAction menu
    resetMenuActions
    manageMySubscription <<<"4
5
7"
    assertMenuAction showAdminSubscriptionTraffic
    assertMenuAction menu
    resetMenuActions
    manageSharedSubscriptions <<<"2
6
7"
    assertMenuAction showUserSubscriptions
    assertMenuAction menu
    resetMenuActions
    manageSharedSubscriptions <<<"1
team-a
Team A
*
0
n
y
6
7"
    assertMenuAction 'runSubscriptionGroupSync:skip-subscribe-refresh'
    assertMenuAction subscribe
    assertMenuAction menu
    subscriptionGroupsStateRead -e '.groups[] | select(.id == "default") | .sync.enabled == false' >/dev/null
    resetMenuActions
    rm -rf "${PADM_SUBSCRIPTION_GROUPS_DIR}"
    ensureSubscriptionGroupsState
    manageSharedSubscriptions <<<"1
team-b
Team B
main
0

y
6
7"
    assertMenuAction refreshSubscriptionGroupSyncCron
    assertMenuAction 'runSubscriptionGroupSync:skip-subscribe-refresh'
    assertMenuAction subscribe
    subscriptionGroupsStateRead -e '.groups[] | select(.id == "default") | .sync.enabled == true' >/dev/null
    resetMenuActions
    manageSharedSubscriptions <<<"4
6
7"
    assertMenuAction runSubscriptionGroupSync
    assertMenuAction menu
    resetMenuActions
    manageSharedSubscriptions <<<"5
6
7"
    assertMenuAction subscriptionSyncPlan
    assertMenuAction menu
    resetMenuActions
    manageMultiServerSubscriptions <<<"1
3
10
7"
    assertMenuAction showSubscriptionWireGuardMainCredential
    assertMenuAction menu
    for wgAction in "${wgActions[@]}"; do
        wgChoice=${wgAction%%:*}
        resetMenuActions
        manageSubscriptionWireGuardControlMenu <<<"${wgChoice}
10"
        assertMenuAction "${wgAction#*:}"
    done
    resetMenuActions
    manageMultiServerSubscriptions <<<"4
10
7"
    assertMenuAction setSubscriptionSourceControlTokenMenu
    assertMenuAction menu
    resetMenuActions
    manageMultiServerSubscriptions <<<"6
10
7"
    assertMenuAction showSubscriptionSourceControlUrls
    assertMenuAction menu
    resetMenuActions
    manageMultiServerSubscriptions <<<"7
10
7"
    assertMenuAction showSubscriptionSourceSyncResults
    assertMenuAction menu
    resetMenuActions
    manageTrafficAndQuota <<<"1
8
7"
    assertMenuAction collectSubscriptionTraffic
    assertMenuAction menu
    resetMenuActions
    manageTrafficAndQuota <<<"6
8
7"
    assertMenuAction subscriptionQuotaDryRunPlan
    assertMenuAction menu
    resetMenuActions
    manageTrafficAndQuota <<<"7
8
7"
    assertMenuAction executeSubscriptionQuotaPlanMenu
    assertMenuAction menu
    resetMenuActions
    manageSubscriptionAutomation <<<"1
6
7"
    assertMenuAction manageSubscriptionSyncSettings
    assertMenuAction menu
    resetMenuActions
    manageSubscriptionAutomation <<<"2
6
7"
    assertMenuAction runSubscriptionGroupSync
    assertMenuAction menu
    resetMenuActions
    manageSubscriptionAutomation <<<"5
6
7"
    assertMenuAction manageSubscriptionStateBackups
    assertMenuAction menu
    resetMenuActions
    manageAdminSubscription <<<"5
7"
    assertMenuAction menu
    resetMenuActions
    manageUserSubscription <<<"6
7"
    assertMenuAction menu
    resetMenuActions
    manageSubscriptionServers <<<"9
7"
    assertMenuAction menu
    resetMenuActions
    manageSubscriptionTraffic <<<"8
7"
    assertMenuAction menu
    resetMenuActions
    manageSubscriptionSettings <<<"6
7"
    assertMenuAction menu
    resetMenuActions
    coreVersionManageMenu <<<"6"
    assertMenuAction menu
    if assertMenuAction unexpected-network-version-fetch; then
        printf 'menu-smoke failed: core menu fetched release versions while rendering overview\n' >&2
        return 1
    fi

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
    packageManager=apt
    release=debian
    initVar
    checkSystem
    [[ "${installType}" == *"--no-install-recommends"* ]]
    packageManager=apt
    release=debian
    selectCustomInstallType=",1,"
    rhelLike=false
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
    [[ "${capturedPackages}" == *"dnsutils"* ]]
    [[ "${capturedPackages}" == *"iptables"* ]]
    [[ "${capturedPackages}" == *"inetutils-ping"* ]]
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

regressionEnsureScriptModules() {
    local remoteRef localRef
    if [[ "${PADM_SKIP_REMOTE_REF_CHECK:-}" == "1" ]]; then
        if [[ ! -f "${SCRIPT_DIR}/shell/core/bootstrap.sh" ]]; then
            refreshScriptModules ""
        fi
        return 0
    fi
    remoteRef=$(fetchRemoteRef || true)
    [[ -f "${SCRIPT_REF_FILE}" ]] && localRef=$(<"${SCRIPT_REF_FILE}")

    if [[ ! -f "${SCRIPT_DIR}/shell/core/bootstrap.sh" ]]; then
        refreshScriptModules "${remoteRef}"
    elif [[ -n "${remoteRef}" && "${remoteRef}" != "${localRef}" ]]; then
        refreshScriptModules "${remoteRef}"
    fi
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
    local savedRepoRefUrl="${REPO_REF_URL:-}"
    local savedRepoZipUrl="${REPO_ZIP_URL:-}"
    local savedRepoArchiveDir="${REPO_ARCHIVE_DIR:-}"
    local savedPadmSkipRemoteRefCheck="${PADM_SKIP_REMOTE_REF_CHECK:-}"

    SCRIPT_DIR="${fixtureDir}"
    SCRIPT_REF_FILE="${fixtureDir}/.padm-ref"
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
    [[ "$(<"${marker}")" == "new-ref" ]]

    SCRIPT_DIR="${savedScriptDir}"
    SCRIPT_REF_FILE="${savedScriptRefFile}"
    REPO_REF_URL="${savedRepoRefUrl}"
    REPO_ZIP_URL="${savedRepoZipUrl}"
    REPO_ARCHIVE_DIR="${savedRepoArchiveDir}"
    if [[ -n "${savedPadmSkipRemoteRefCheck}" ]]; then
        PADM_SKIP_REMOTE_REF_CHECK="${savedPadmSkipRemoteRefCheck}"
    else
        unset PADM_SKIP_REMOTE_REF_CHECK
    fi
}

runRegressionPlatform() {
    runRegressionStep install-entry-refresh runInstallEnsureModulesRegression
    runRegressionStep xray-stats-jq runXrayTrafficStatsJqCompatibilityRegression
    runRegressionStep dpkg-installed-pattern runDpkgInstalledPatternRegression
    runRegressionStep dpkg-query-installed-pattern runDpkgQueryInstalledPatternRegression
    runRegressionStep rhel-like-detection runRhelLikeDetectionRegression
    runRegressionStep fedora-detection runFedoraDetectionRegression
}

runRegressionPlatformIo() {
    runRegressionStep install-tools-certificate-dependency runInstallToolsCertificateDependencyRegression
    runRegressionStep base-package-batch runBasePackageBatchRegression
    runRegressionStep package-command-stdin runPackageCommandStdinRegression
    runRegressionStep reality-scanner-binary runRealityScannerBinaryRegression
}

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

runRegressionTls() {
    runRegressionStep tls-renew-existing-certificate runTlsRenewalExistingCertificateRegression
}

runRegressionFast() {
    runRegressionStep platform runRegressionPlatform
    runRegressionStep nginx-blog-auto-install runNginxBlogAutoInstallRegression
    runRegressionStep ui-smoke-light runMenuSmokeLightRegression
}

runRegressionFastReality() {
    runRegressionFast
    runRegressionStep reality-candidates-fast runRealityCandidateFastRegression
}

runRegressionUi() {
    runRegressionStep ui-smoke runMenuSmokeRegression
}

runRegressionMenuSmoke() {
    runMenuSmokeLightRegression
}

runRegressionRouting() {
    runRegressionStep routing-core runRoutingRegression
    runRegressionStep routing-port-panel runPortAndPanelHelperRegression
}

runRegressionSubscriptionOutput() {
    runRegressionStep subscription-output runSubscriptionOutputRegression
}

runRegressionSubscriptionState() {
    runRegressionStep subscription-state runSubscriptionGroupStateRegression
}

runRegressionSubscriptionRemoteFetch() {
    runRegressionStep subscription-remote-fetch runRemoteSubscribeFetchRegression
}

runRegressionSubscriptionWriteTransaction() {
    runRegressionStep sing-box-subscribe-write runSingBoxSubscribeWriteRegression
    runRegressionStep subscribe-server-name runSubscribeServerNameRegression
    runRegressionStep subscribe-nginx-config-write runSubscribeNginxConfigWriteRegression
    runRegressionStep subscribe-user-output-transaction runSubscribeUserOutputTransactionRegression
}

runRegressionSubscription() {
    runRegressionSubscriptionOutput
    runRegressionSubscriptionState
    runRegressionSubscriptionRemoteFetch
    runRegressionSubscriptionWriteTransaction
}

runRegressionRealityCandidates() {
    runRegressionStep reality-candidates-fast runRealityCandidateFastRegression
    runRegressionStep reality-asn-scan-plan runRealityAsnScanPlanRegression
    runRegressionStep reality-candidates-full runRealityCandidateFullRegression
}

runRegressionRealityStream() {
    runRegressionStep reality-stream-enable runRealityStreamEnableRegression
    runRegressionStep reality-stream-disable runRealityStreamDisableRegression
}

runRegressionRuntime() {
    runRegressionStep runtime-core runRuntimeAndRealityRegression
    runRegressionStep reality-config runRealityConfigRegression
}

runRegressionTransactionCore() {
    runRegressionStep config-transaction runConfigTransactionRegression
    runRegressionStep core-port-file-transaction runCorePortFileTransactionRegression
    runRegressionStep user-config-write runUserConfigWriteRegression
    runRegressionStep remove-user runRemoveUserRegression
}

runRegressionTransactionSubscription() {
    runRegressionStep subscribe-server-name runSubscribeServerNameRegression
    runRegressionStep subscribe-nginx-config-write runSubscribeNginxConfigWriteRegression
    runRegressionStep subscribe-user-output-transaction runSubscribeUserOutputTransactionRegression
    runRegressionStep remote-subscribe-fetch runRemoteSubscribeFetchRegression
}

runRegressionTransactionSystem() {
    runRegressionStep nginx-service-failure runNginxServiceFailureRegression
    runRegressionStep uninstall-nginx-cleanup runUninstallNginxCleanupRegression
    runRegressionStep alone-nginx-config-transaction runAloneNginxConfigTransactionRegression
}

runRegressionTransaction() {
    runRegressionTransactionCore
    runRegressionTransactionSubscription
    runRegressionTransactionSystem
}

runRegressionRemoteControl() {
    runRegressionStep remote-control-concurrency runRemoteControlConcurrencyRegression
}

runRegressionAll() {
    runRegressionRouting
    runRegressionSubscription
    runRegressionRuntime
    runRegressionTransaction
    runRegressionRemoteControl
    runRegressionUi
}

regressionName=${1:-fast}
case "${regressionName}" in
fast)
    regressionRunner=runRegressionFast
    ;;
fast-reality)
    regressionRunner=runRegressionFastReality
    ;;
platform)
    regressionRunner=runRegressionPlatform
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
routing)
    regressionRunner=runRegressionRouting
    ;;
subscription)
    regressionRunner=runRegressionSubscription
    ;;
subscription-output)
    regressionRunner=runRegressionSubscriptionOutput
    ;;
subscription-state)
    regressionRunner=runRegressionSubscriptionState
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
remote-control)
    regressionRunner=runRegressionRemoteControl
    ;;
all|full|ci)
    regressionRunner=runRegressionAll
    ;;
*)
    printf 'usage: %s [fast|fast-reality|platform|platform-io|tls|ui|menu-smoke|routing|subscription|subscription-output|subscription-state|subscription-remote-fetch|subscription-write-transaction|runtime|runtime-core|reality-candidates|reality-candidates-fast|reality-candidates-full|reality-config|reality-stream|transaction|transaction-core|transaction-subscription|transaction-system|remote-control|all|full|ci]\n' "$0" >&2
    exit 2
    ;;
esac

runRegressionStep "total:${regressionName}" "${regressionRunner}"
echo "subscription-groups-regression-ok:${regressionName}"
