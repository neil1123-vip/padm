#!/usr/bin/env bash

runRoutingRegression() {
    local routingRootRel="${TMP_DIR}/routing-core"
    local routingRoot
    mkdir -p "${routingRootRel}/xray-conf" "${routingRootRel}/sing-box-conf" "${routingRootRel}/tmp"
    routingRoot=$(cd -- "${routingRootRel}" && pwd -P)
    local configPath="${routingRoot}/xray-conf/"
    local singBoxConfigPath="${routingRoot}/sing-box-conf/"
    local TMPDIR="${routingRoot}/tmp"
    local PADM_ACCESS_CONTROL_BACKUP_DIR="${routingRoot}/access_control_backup"
    export TMPDIR
    cat >"${singBoxConfigPath}dlc.dat_plain.yml" <<'YAML'
- name: "openai"
YAML
    rulesJson=$(initSingBoxRules "openai,example.com,full:api.example.com" "regression")
    jq -e '
      .ruleSet[0].tag == "geosite_openai_regression" and
      .ruleSet[0].http_client.detour == "01_direct_outbound" and
      (.ruleSet[0] | has("download_detour") | not) and
      .suffixRules == ["example.com"] and
      .domainRules == ["api.example.com"]
    ' <<<"${rulesJson}" >/dev/null
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
      .route.rule_set[0].url == "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-openai.srs" and
      .route.rule_set[0].http_client.detour == "01_direct_outbound" and
      (.route.rule_set[0] | has("download_detour") | not)
    ' "${singBoxConfigPath}test_route.json" >/dev/null
    [[ "$(getDLCMatchedRuleValue example.com "${singBoxConfigPath}")" == "domain:example.com" ]]
    [[ "$(getDLCMatchedRuleValue full:api.example.com "${singBoxConfigPath}")" == "full:api.example.com" ]]
    [[ "$(getDLCMatchedRuleValue openai "${singBoxConfigPath}")" == "geosite:openai" ]]
    ! grep -q 'regexp:' < <(getDLCMatchedRuleValue example.com "${singBoxConfigPath}")
    (
        local dlcRoot="${routingRoot}/dlc-release"
        local dlcCorePath="${dlcRoot}/core"
        local dlcTarget="${dlcCorePath}/dlc.dat_plain.yml"
        local seenOutputDir= seenRepo= seenVersion= seenAsset=
        mkdir -p "${dlcCorePath}"
        downloadFile() {
            return 1
        }
        downloadGitHubReleaseAsset() {
            [[ "${1:-}" == "-P" ]] || return 1
            seenOutputDir=$2
            seenRepo=$3
            seenVersion=$4
            seenAsset=$5
            [[ "${seenVersion}" == "latest" ]] || return 1
            mkdir -p "${seenOutputDir}"
            printf -- '- name: openai\n' >"${seenOutputDir}/${seenAsset}"
        }
        downloadDLCPlainYAML "${dlcCorePath}" || return 1
        [[ "${seenRepo}" == "v2fly/domain-list-community" ]]
        [[ "${seenAsset}" == "dlc.dat_plain.yml" ]]
        [[ -s "${dlcTarget}" ]]
    )
    (
        local dlcRoot="${routingRoot}/dlc-commit"
        local dlcCorePath="${dlcRoot}/core"
        local dlcTarget="${dlcCorePath}/dlc.dat_plain.yml"
        mkdir -p "${dlcCorePath}"
        downloadGitHubReleaseAsset() {
            [[ "${1:-}" == "-P" ]] || return 1
            mkdir -p "$2"
            printf -- '- name: openai\n' >"$2/$5"
        }
        commitGeneratedFile() {
            return 1
        }
        if downloadDLCPlainYAML "${dlcCorePath}" 2>/dev/null; then
            return 1
        fi
        [[ ! -e "${dlcTarget}" ]]
        [[ ! -e "${dlcTarget}.tmp" ]]
    )
    (
        local unsafeRoot="${routingRoot}/dlc-unsafe"
        local downloadCalled=
        mkdir -p "${unsafeRoot}/child"
        cd "${unsafeRoot}/child"
        downloadFile() {
            downloadCalled=1
            return 1
        }
        if downloadDLCPlainYAML "../outside-core" 2>/dev/null; then
            return 1
        fi
        [[ -z "${downloadCalled}" ]]
        [[ ! -e "${unsafeRoot}/outside-core" ]]
    )
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
      .route.rule_set[0].format == "binary" and
      .route.rule_set[0].http_client.detour == "01_direct_outbound" and
      (.route.rule_set[0] | has("download_detour") | not)
    ' "${singBoxConfigPath}cn_block_ip_route.json" >/dev/null
    addSingBoxOutbound "01_direct_outbound"
    jq -e '.outbounds[0].tag == "01_direct_outbound"' "${singBoxConfigPath}01_direct_outbound.json" >/dev/null
    addSingBoxOutbound "IPv6_out"
    jq -e '.outbounds[0].domain_resolver.server == "padm-local" and .outbounds[0].domain_resolver.strategy == "ipv6_only" and (.outbounds[0].domain_strategy | not)' "${singBoxConfigPath}IPv6_out.json" >/dev/null
    jq -e '[.dns.servers[] | select(.tag == "padm-local" and .type == "local")] | length == 1' "${singBoxConfigPath}dns.json" >/dev/null
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
    unset -f readConfigWarpReg initHysteriaPort initHysteria2Network initXrayClients
    hysteriaPort=23456
    rm -f "${singBoxConfigPath}dns.json"
    setSniffRouting
    jq -e '.route.rules[0].action == "sniff"' "${singBoxConfigPath}sniff.json" >/dev/null
    jq -e '
      [.dns.servers[] | select(.tag == "padm-local" and .type == "local")] | length == 1
    ' "${singBoxConfigPath}dns.json" >/dev/null
    initSingBoxLocalDNSConfig
    jq -e '
      [.dns.servers[] | select(.tag == "padm-local" and .type == "local")] | length == 1
    ' "${singBoxConfigPath}dns.json" >/dev/null
    printf '%s\n' '{"dns":{"servers":[{"tag":"custom","type":"udp","server":"1.1.1.1"}]},"route":{"final":"direct"}}' >"${singBoxConfigPath}dns.json"
    initSingBoxLocalDNSConfig
    jq -e '
      any(.dns.servers[]; .tag == "custom") and
      any(.dns.servers[]; .tag == "padm-local" and .type == "local") and
      .route.final == "direct"
    ' "${singBoxConfigPath}dns.json" >/dev/null
    rm -f "${singBoxConfigPath}dns.json"
    printf '%s\n' '{"dns":{"servers":[{"tag":"padm-local","type":"udp","server":"1.1.1.1"}]}}' >"${singBoxConfigPath}resolver.json"
    originalContent=$(<"${singBoxConfigPath}resolver.json")
    if initSingBoxLocalDNSConfig 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${singBoxConfigPath}resolver.json")" == "${originalContent}" ]]
    [[ ! -e "${singBoxConfigPath}dns.json" ]]
    printf '%s\n' '{"dns":{"servers":[{"tag":"padm-local","type":"local"}]}}' >"${singBoxConfigPath}resolver.json"
    initSingBoxLocalDNSConfig
    [[ ! -e "${singBoxConfigPath}dns.json" ]]
    addSingBoxDNSConfig "1.1.1.1" "cross-shard.example.com"
    jq -e '
      ([.dns.servers[]? | select(.tag == "padm-local")] | length) == 0 and
      .route.default_domain_resolver == "padm-local"
    ' "${singBoxConfigPath}dns.json" >/dev/null
    jq -s -e '
      [.[].dns.servers[]? | select(.tag == "padm-local" and .type == "local")] | length == 1
    ' "${singBoxConfigPath}"*.json >/dev/null
    printf '%s\n' '{"dns":{"servers":[{"tag":"padm-local","type":"local"}]}}' >"${singBoxConfigPath}resolver-duplicate.json"
    if initSingBoxLocalDNSConfig 2>/dev/null; then
        return 1
    fi
    rm -f "${singBoxConfigPath}resolver-duplicate.json"
    rm -f "${singBoxConfigPath}resolver.json"
    initSingBoxLocalDNSConfig
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
      .route.rule_set[0].format == "binary" and
      .route.rule_set[0].http_client.detour == "01_direct_outbound" and
      (.route.rule_set[0] | has("download_detour") | not)
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
    addSingBoxDNSConfig "203.0.113.11" 'domain:bad"key.example' "predefined"
    jq -e '
      (.dns.servers[] | select(.tag == "padm-hosts") | .predefined["bad\"key.example"] == "203.0.113.11")
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
{"routing":{"rules":[{"outboundTag":"blackhole_out","domain":["geosite:cn","domain:custom.example"]},{"outboundTag":"blackhole_out","domain":["geosite:cn"]},{"outboundTag":"blackhole_ip_out","ip":["geoip:cn","203.0.113.0/24"]},{"outboundTag":"blackhole_ip_out","ip":["geoip:cn"]},{"outboundTag":"keep_out","domain":["domain:keep.example"]}]}}
JSON
    removeXrayRegionalRules
    jq -e '
      (.routing.rules | length) == 3 and
      ([.routing.rules[] | select(.outboundTag == "blackhole_out") | .domain[]] | . == ["domain:custom.example"]) and
      ([.routing.rules[] | select(.outboundTag == "blackhole_ip_out") | .ip[]] | . == ["203.0.113.0/24"]) and
      .routing.rules[2].outboundTag == "keep_out"
    ' "${configPath}09_routing.json" >/dev/null
    addXrayBTBlockRule
    jq -e '.routing.rules[] | select(.outboundTag == "blackhole_out" and (.protocol | index("bittorrent")))' "${configPath}09_routing.json" >/dev/null
    coreInstallType=2
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

runRoutingCoreRejectsUnsafeConfigDirRegression() (
    local root="${TMP_DIR}/routing-core-unsafe-config"
    local rmLog="${root}/rm.log"
    local rc

    mkdir -p "${root}/relative-config" "${root}/relative-sing-box"
    : >"${rmLog}"
    printf '{"routing":{"rules":[]}}\n' >"${root}/relative-config/09_routing.json"
    printf '{"outbounds":[]}\n' >"${root}/relative-sing-box/socks5_outbound.json"

    cd "${root}"
    configPath="relative-config/"
    singBoxConfigPath="relative-sing-box/"
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    set +e
    writeRoutingJsonConfig "${configPath}11_dns.json" <<'JSON' >/dev/null 2>&1
{"dns":{"servers":["localhost"]}}
JSON
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -e "${root}/relative-config/11_dns.json" ]]
    ! compgen -G "${root}/relative-config/.11_dns.json.routing.*" >/dev/null

    regressionExpectStatus 1 updateRoutingJsonConfig "${configPath}09_routing.json" '.routing.rules += [{"type":"field"}]' >/dev/null 2>&1
    jq -e '.routing.rules == []' "${root}/relative-config/09_routing.json" >/dev/null
    ! compgen -G "${root}/relative-config/.09_routing.json.routing.*" >/dev/null

    regressionExpectStatus 1 removeXrayOutbound "09_routing" >/dev/null 2>&1
    [[ -f "${root}/relative-config/09_routing.json" ]]

    regressionExpectStatus 1 removeSingBoxConfig "socks5_outbound" >/dev/null 2>&1
    [[ -f "${root}/relative-sing-box/socks5_outbound.json" ]]
    [[ ! -s "${rmLog}" ]]
)

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
    local removeChoice=1
    local rc

    configPath="${root}/xray/"
    singBoxConfigPath=
    coreInstallType=1
    mkdir -p "${configPath}"

    errorCard() { return 0; }
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

    rm -f "${backupMarker}" "${addMarker}" "${outboundMarker}" "${uninstallMarker}" "${removeMarker}" "${restoreMarker}" "${cleanupMarker}" "${reloadMarker}"
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
    local rootRel="${TMP_DIR}/access-control-config-transaction"
    local root
    local backupDir
    local statusLog
    local rc reloadCalls=0

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    statusLog="${root}/status.log"
    configPath="${root}/xray/"
    singBoxConfigPath="${root}/sing-box/"
    unset PADM_ACCESS_CONTROL_BACKUP_DIR
    ACCESS_CONTROL_ACTIVE_BACKUP_DIR=
    coreInstallType=1
    mkdir -p "${rootRel}/xray" "${rootRel}/sing-box"
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
    backupDir=$(accessControlBackupDir)
    [[ -d "${backupDir}" ]]
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

    regressionExpectStatus 1 applyAccessControlConfigChange >/dev/null 2>&1
    [[ "${reloadCalls}" == "2" ]]
    jq -e '.routing.rules[0].outboundTag == "old"' "${configPath}09_routing.json" >/dev/null
    [[ ! -e "${configPath}blackhole_out.json" ]]
    jq -e '.route.rules[0].domain_suffix == ["old.example"]' "${singBoxConfigPath}block_domain_route.json" >/dev/null
    [[ ! -e "${singBoxConfigPath}cn_block_route.json" ]]
    [[ ! -e "${backupDir}" ]]
    [[ -z "${ACCESS_CONTROL_ACTIVE_BACKUP_DIR:-}" ]]
    grep -q '核心重载失败，已回滚本次修改' "${statusLog}"

    rm -rf "${rootRel}"
    mkdir -p "${rootRel}/xray" "${rootRel}/sing-box"
    root=$(cd -- "${rootRel}" && pwd -P)
    statusLog="${root}/status.log"
    configPath="${root}/xray/"
    singBoxConfigPath="${root}/sing-box/"
    PADM_ACCESS_CONTROL_BACKUP_DIR="${root}/backup"
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
        if [[ "$1" == "-p" && "$2" == "${PADM_ACCESS_CONTROL_BACKUP_DIR}/xray/09_routing.json" && "$3" == "${root}/xray/.09_routing.json.restore."* ]]; then
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

runRoutingRejectsUnsafeDirRegression() (
    local routing=$1
    local dirType=$2
    local backupDirVar backupCreateFn backupCleanupFn backupRestoreFn configFile
    local root="${TMP_DIR}/${routing}-unsafe-${dirType}"
    local rmLog="${root}/rm.log"
    local backupDir="${root}/backup"
    local rc

    case "${routing}" in
    access-control)
        backupDirVar=PADM_ACCESS_CONTROL_BACKUP_DIR
        backupCreateFn=accessControlBackupCreate
        backupCleanupFn=accessControlBackupCleanup
        backupRestoreFn=accessControlBackupRestore
        configFile=09_routing.json
        ;;
    dns-routing)
        backupDirVar=PADM_DNS_ROUTING_BACKUP_DIR
        backupCreateFn=dnsRoutingBackupCreate
        backupCleanupFn=dnsRoutingBackupCleanup
        backupRestoreFn=dnsRoutingBackupRestore
        configFile=11_dns.json
        ;;
    *) return 1 ;;
    esac

    mkdir -p "${root}"
    : >"${rmLog}"
    singBoxConfigPath=
    if [[ "${dirType}" == "backup" ]]; then
        printf -v "${backupDirVar}" '%s' relative-backup
        configPath="${root}/xray/"
        mkdir -p "${configPath}"
    elif [[ "${dirType}" == "config" ]]; then
        configPath=relative-config/
        printf -v "${backupDirVar}" '%s' "${backupDir}"
    else
        return 1
    fi

    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    regressionExpectStatus 1 "${backupCreateFn}" >/dev/null 2>&1
    [[ ! -s "${rmLog}" ]]

    if [[ "${dirType}" == "backup" ]]; then
        regressionExpectStatus 1 "${backupCleanupFn}" >/dev/null 2>&1
        [[ ! -s "${rmLog}" ]]

        mkdir -p "${root}/relative-backup/xray"
        printf 'old\n' >"${root}/relative-backup/xray/${configFile}"
        (
            cd "${root}"
            regressionExpectStatus 1 "${backupRestoreFn}" >/dev/null 2>&1
        )
    else
        [[ ! -s "${rmLog}" ]]
        [[ ! -e "${backupDir}" ]]

        mkdir -p "${backupDir}/xray"
        printf 'old\n' >"${backupDir}/xray/${configFile}"
        regressionExpectStatus 1 "${backupRestoreFn}" >/dev/null 2>&1
    fi
    [[ ! -s "${rmLog}" ]]
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
    local rootRel="${TMP_DIR}/dns-routing-failure"
    local root
    local reloadMarker
    local errorLog
    local rc

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    reloadMarker="${root}/reload"
    errorLog="${root}/error.log"
    PADM_DNS_ROUTING_BACKUP_DIR="${root}/backup"
    errorCard() {
        printf '%s\n' "$*" >>"${errorLog}"
        return 0
    }
    getDLCMatchedRuleValue() { printf 'domain:%s\n' "$1"; }
    reloadCore() {
        printf 'reload\n' >>"${reloadMarker}"
        return 1
    }

    (
        mkdir -p "${rootRel}/dns-empty-rules"
        configPath="${root}/dns-empty-rules/"
        singBoxConfigPath="${root}/dns-empty-rules/"
        coreInstallType=1
        printf '{"dns":{"servers":["old"]}}\n' >"${configPath}11_dns.json"
        printf '{"dns":{"servers":["old"]}}\n' >"${singBoxConfigPath}dns.json"
        getDLCMatchedRuleValue() { return 99; }
        if addXrayDNSConfig "1.1.1.1" ' ,  ' >/dev/null 2>&1; then
            return 1
        fi
        if addSingBoxDNSConfig "1.1.1.1" ',,' >/dev/null 2>&1; then
            return 1
        fi
        jq -e '.dns.servers == ["old"]' "${configPath}11_dns.json" >/dev/null
        jq -e '.dns.servers == ["old"]' "${singBoxConfigPath}dns.json" >/dev/null
    )

    (
        mkdir -p "${rootRel}/dns-sing-box-helper"
        configPath=
        singBoxConfigPath="${root}/dns-sing-box-helper/"
        printf '{"dns":{"servers":["old"]}}\n' >"${singBoxConfigPath}dns.json"
        splitSingBoxRules() { return 1; }
        regressionExpectStatus 1 addSingBoxDNSConfig "1.1.1.1" "example.com" >/dev/null 2>&1
        jq -e '.dns.servers == ["old"]' "${singBoxConfigPath}dns.json" >/dev/null
    )

    (
        mkdir -p "${rootRel}/dns-xray"
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
        unset PADM_DNS_ROUTING_BACKUP_DIR
        DNS_ROUTING_ACTIVE_BACKUP_DIR=
        rm -f "${reloadMarker}" "${errorLog}"
        regressionExpectStatus 1 setUnlockDNS >/dev/null 2>&1
        [[ -e "${reloadMarker}" ]]
        [[ "$(wc -l <"${reloadMarker}")" == "2" ]]
        jq -e '.dns.servers == ["old-xray"]' "${configPath}11_dns.json" >/dev/null
        [[ -z "${DNS_ROUTING_ACTIVE_BACKUP_DIR:-}" ]]
        grep -q 'DNS 分流核心重载失败，已回滚本次修改' "${errorLog}"
    )

    (
        mkdir -p "${rootRel}/dns-sing-box-outbound"
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
        rm -f "${reloadMarker}" "${errorLog}"
        regressionExpectStatus 1 setUnlockDNS >/dev/null 2>&1
        [[ ! -e "${reloadMarker}" ]]
        [[ ! -e "${singBoxConfigPath}dns.json" ]]
        [[ ! -e "${singBoxConfigPath}01_direct_outbound.json" ]]
        [[ ! -e "${PADM_DNS_ROUTING_BACKUP_DIR}" ]]
    )

    (
        mkdir -p "${rootRel}/sni-xray"
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
        rm -f "${reloadMarker}" "${errorLog}"
        regressionExpectStatus 1 setUnlockSNI >/dev/null 2>&1
        [[ -e "${reloadMarker}" ]]
        [[ "$(wc -l <"${reloadMarker}")" == "2" ]]
        jq -e '.dns.servers == ["old-sni"]' "${configPath}11_dns.json" >/dev/null
        [[ ! -e "${PADM_DNS_ROUTING_BACKUP_DIR}" ]]
    )

    (
        mkdir -p "${rootRel}/sni-sing-box"
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
        rm -f "${reloadMarker}" "${errorLog}"
        regressionExpectStatus 1 setUnlockSNI >/dev/null 2>&1
        [[ ! -e "${reloadMarker}" ]]
        jq -e '.dns.servers == ["old-sing-sni"]' "${singBoxConfigPath}dns.json" >/dev/null
        [[ ! -e "${PADM_DNS_ROUTING_BACKUP_DIR}" ]]
    )

    (
        mkdir -p "${rootRel}/remove-dns"
        configPath="${root}/remove-dns/"
        singBoxConfigPath=
        coreInstallType=1
        cat >"${configPath}11_dns.json" <<'JSON'
{"dns":{"servers":["8.8.8.8"]}}
JSON
        rm -rf "${PADM_DNS_ROUTING_BACKUP_DIR}"
        rm -f "${reloadMarker}" "${errorLog}"
        regressionExpectStatus 1 removeUnlockDNS >/dev/null 2>&1
        [[ -e "${reloadMarker}" ]]
        [[ "$(wc -l <"${reloadMarker}")" == "2" ]]
        jq -e '.dns.servers == ["8.8.8.8"]' "${configPath}11_dns.json" >/dev/null
        [[ ! -e "${PADM_DNS_ROUTING_BACKUP_DIR}" ]]
        [[ ! -e "${root}/remove-dns/dns.json" ]]
    )

    (
        mkdir -p "${rootRel}/remove-dns-xray-sing-box-assist/xray" "${rootRel}/remove-dns-xray-sing-box-assist/sing-box"
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
        rm -f "${reloadMarker}" "${errorLog}"
        regressionExpectStatus 1 removeUnlockDNS >/dev/null 2>&1
        [[ -e "${reloadMarker}" ]]
        [[ "$(wc -l <"${reloadMarker}")" == "2" ]]
        jq -e '.dns.servers == ["8.8.8.8"]' "${configPath}11_dns.json" >/dev/null
        jq -e '.dns.servers[0].tag == "hosts"' "${singBoxConfigPath}dns.json" >/dev/null
        [[ ! -e "${PADM_DNS_ROUTING_BACKUP_DIR}" ]]
    )

    (
        mkdir -p "${rootRel}/remove-sni-xray-sing-box-assist/xray" "${rootRel}/remove-sni-xray-sing-box-assist/sing-box"
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
        rm -f "${reloadMarker}" "${errorLog}"
        regressionExpectStatus 1 removeUnlockSNI >/dev/null 2>&1
        [[ -e "${reloadMarker}" ]]
        [[ "$(wc -l <"${reloadMarker}")" == "2" ]]
        jq -e '.dns.hosts["domain:example.com"] == "203.0.113.10"' "${configPath}11_dns.json" >/dev/null
        jq -e '.dns.servers[0].tag == "hosts"' "${singBoxConfigPath}dns.json" >/dev/null
        [[ ! -e "${PADM_DNS_ROUTING_BACKUP_DIR}" ]]
    )

    (
        mkdir -p "${rootRel}/dns-xray-restore-fail"
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
            if [[ "$1" == "-p" && "$2" == "${PADM_DNS_ROUTING_BACKUP_DIR}/xray/11_dns.json" && "$3" == "${configPath}.11_dns.json.restore."* ]]; then
                return 1
            fi
            command cp "$@"
        }
        rm -rf "${PADM_DNS_ROUTING_BACKUP_DIR}"
        rm -f "${reloadMarker}" "${errorLog}"
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
