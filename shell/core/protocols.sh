#!/usr/bin/env bash

protocolCapabilityRegistry() {
    cat <<'EOF'
1|VLESS Reality Vision|node|recommended|both|xray,sing-box|vless|tcp|reality|none|yes|core|no|no|no|conditional|||07_VLESS_vision_reality_inbounds.json|uri,clash-meta,sing-box|wide|||默认直连推荐
2|VLESS Reality XHTTP|node|recommended|xray|xray|vless|xhttp|reality|none|yes|core|no|no|no|conditional|||12_VLESS_XHTTP_inbounds.json|uri,clash-meta|modern|||Xray-only；sing-box 不生成
3|Hysteria2|node|recommended|both|sing-box|hysteria2|quic|tls|none|yes|core|yes|yes|yes|no||1.11.0|06_hysteria2_inbounds.json|uri,clash-meta,sing-box|modern|||UDP/移动/弱网默认推荐
4|AnyTLS|node|recommended|sing-box|sing-box|anytls|tcp|tls|none|yes|core|yes|yes|no|no||1.12.0|13_anytls_inbounds.json|uri,sing-box|modern|||sing-box AnyTLS
5|NaiveProxy|node|recommended|sing-box|sing-box|naive|tcp|tls|none|yes|core|yes|yes|no|no|||10_naive_inbounds.json|uri,sing-box|modern|||HTTPS/Cronet 指纹场景
21|VLESS WS TLS|node|advanced|xray|xray|vless|ws|tls|http_front|yes|nginx|yes|yes|no|yes|||03_VLESS_WS_inbounds.json|uri,clash-meta,sing-box|wide|WebSocket 属高级方案，新装优先 XHTTP|VLESS Reality XHTTP|高级兼容协议
22|VMess WS TLS|node|advanced|xray|xray|vmess|ws|tls|http_front|yes|nginx|yes|yes|no|yes|||05_VMess_WS_inbounds.json|uri,clash-meta,sing-box|wide|VMess 与 WebSocket 均为高级方案|VLESS Reality Vision|高级兼容协议
23|VMess HTTPUpgrade TLS|node|advanced|both|xray,sing-box|vmess|httpupgrade|tls|http_front|yes|nginx|yes|yes|no|yes|||11_VMess_HTTPUpgrade_inbounds.json|uri,clash-meta,sing-box|modern|HTTPUpgrade 属高级方案，新装优先 XHTTP|VLESS Reality XHTTP|高级兼容协议
24|VLESS gRPC TLS|node|advanced|xray|xray|vless|grpc|tls|grpc_front|yes|nginx|yes|yes|no|yes|||06_VLESS_GRPc_inbounds.json|uri,clash-meta,sing-box|wide|gRPC 有主动探测与 fallback 限制|VLESS Reality XHTTP|高级兼容协议
25|Trojan gRPC TLS|node|advanced|xray|xray|trojan|grpc|tls|grpc_front|yes|nginx|yes|yes|no|yes|||04_trojan_GRPc_inbounds.json|uri,clash-meta,sing-box|wide|gRPC 有主动探测与 fallback 限制|AnyTLS|高级兼容协议
26|VLESS Reality gRPC|node|advanced|both|xray,sing-box|vless|grpc|reality|none|yes|core|no|no|no|conditional|||08_VLESS_vision_gRPC_inbounds.json|uri,clash-meta,sing-box|modern|Reality gRPC 是高级方案|VLESS Reality Vision|高级 Reality 组合
27|VLESS TCP TLS Vision|node|advanced|xray|xray|vless|tcp|tls|fallback_backend|yes|xray|yes|yes|no|no|||02_VLESS_TCP_inbounds.json|uri,clash-meta,sing-box|wide|传统 TLS/fallback 高级路径|VLESS Reality Vision|fallback 入口
28|Trojan TCP TLS direct|node|advanced|both|xray,sing-box|trojan|tcp|tls|none|yes|core|yes|yes|no|no|||28_trojan_TCP_direct_inbounds.json|uri,clash-meta,sing-box|wide|传统 TLS 协议，仅显式选择时使用|AnyTLS|直连 TLS
29|Trojan TCP TLS fallback|node|advanced|xray|xray|trojan|tcp|tls|fallback_backend|yes|xray|yes|yes|no|no|||04_trojan_TCP_inbounds.json|uri,clash-meta,sing-box|wide|fallback 仅限 TCP+TLS|AnyTLS|fallback 入口
30|Shadowsocks|node|advanced|sing-box|sing-box|shadowsocks|tcp|none|none|yes|core|no|no|yes|no|||30_shadowsocks_inbounds.json|uri,clash-meta,sing-box|wide|不作为默认公网节点推荐|VLESS Reality Vision|高级兼容协议
31|TUIC|node|advanced|sing-box|sing-box|tuic|quic|tls|none|yes|core|yes|yes|yes|no|||09_tuic_inbounds.json|uri,clash-meta,sing-box|modern|UDP/弱网新装引导使用 Hysteria2|Hysteria2|高级 UDP 协议
201|Socks 中继|internal|advanced|both|xray,sing-box|socks|tcp|none|none|no|core|no|no|yes|no|||20_socks5_inbounds.json||wide|||中继与路由菜单能力
202|HTTP 中继|internal|advanced|both|xray,sing-box|http|tcp|none|none|no|core|no|no|no|no|||||wide|||中继菜单能力
203|WireGuard|internal|advanced|both|xray,sing-box|wireguard|udp|none|none|no|core|no|no|yes|no|||||wide|||路由能力
204|TUN|internal|advanced|sing-box|sing-box|tun|mixed|none|none|no|core|no|no|yes|no|||||wide|||透明代理能力
205|Redirect/TProxy|internal|advanced|both|xray,sing-box|redirect|tcp,udp|none|none|no|core|no|no|yes|no|||||wide|||透明代理能力
206|DNS/Direct/Block|internal|advanced|both|xray,sing-box|routing|mixed|none|none|no|core|no|no|no|no|||||wide|||路由规则能力
207|Tunnel/dokodemo-door|internal|advanced|xray|xray|dokodemo-door|tcp,udp|none|none|no|core|no|no|yes|no|||||wide|||访问控制能力
301|Xray Hysteria2 inbound|known|advanced|xray|none|hysteria2|quic|tls|none|no|core|yes|yes|yes|no|||||modern|||上游已知，本项目暂不生成
302|Hysteria v1|known|advanced|sing-box|none|hysteria|quic|tls|none|no|core|yes|yes|yes|no|||||legacy|||上游已知，本项目暂不生成
303|ShadowTLS|known|advanced|sing-box|none|shadowtls|tcp|tls|none|no|core|yes|yes|no|no|||||modern|||上游已知，本项目暂不生成
304|mKCP combinations|known|advanced|xray|none|vless|mkcp|none|none|no|core|no|no|yes|no|||||legacy|||上游已知，本项目暂不生成
305|Cloudflared inbound|known|advanced|sing-box|none|cloudflared|tcp|tls|none|no|core|yes|yes|no|conditional|||||modern|||偏客户端或出站能力
306|Selector|known|advanced|sing-box|none|selector|mixed|none|none|no|core|no|no|no|no|||||modern|||偏客户端或出站能力
307|URLTest|known|advanced|sing-box|none|urltest|mixed|none|none|no|core|no|no|no|no|||||modern|||偏客户端或出站能力
308|Tor outbound|known|advanced|sing-box|none|tor|tcp|none|none|no|core|no|no|no|no|||||modern|||偏客户端或出站能力
309|SSH outbound|known|advanced|sing-box|none|ssh|tcp|ssh|none|no|core|no|no|no|no|||||modern|||偏客户端或出站能力
EOF
}

protocolCapabilityFieldIndex() {
    case "$1" in
    id) printf '1' ;;
    name) printf '2' ;;
    category) printf '3' ;;
    lifecycle) printf '4' ;;
    core_support) printf '5' ;;
    project_core) printf '6' ;;
    protocol) printf '7' ;;
    transport) printf '8' ;;
    security) printf '9' ;;
    nginx_mode) printf '10' ;;
    public_listener) printf '11' ;;
    tls_terminator) printf '12' ;;
    requires_domain) printf '13' ;;
    requires_cert) printf '14' ;;
    udp_support) printf '15' ;;
    cdn_support) printf '16' ;;
    min_xray) printf '17' ;;
    min_singbox) printf '18' ;;
    config_file | file | filename) printf '19' ;;
    subscription_emitters) printf '20' ;;
    client_support) printf '21' ;;
    risk_note) printf '22' ;;
    replacement) printf '23' ;;
    notes) printf '24' ;;
    *) return 1 ;;
    esac
}

protocolCapabilityMeta() {
    local protocolId=$1
    local key=$2
    local fieldIndex
    fieldIndex=$(protocolCapabilityFieldIndex "${key}") || return 1
    protocolCapabilityRegistry | awk -F'|' -v id="${protocolId}" -v idx="${fieldIndex}" '$1 == id { print $idx; found = 1; exit } END { exit found ? 0 : 1 }'
}

protocolCapabilityIdsByCategory() {
    local category=$1
    protocolCapabilityRegistry | awk -F'|' -v category="${category}" '$3 == category { print $1 }' | paste -sd ','
}

protocolCapabilityIdsByLifecycle() {
    local lifecycle=$1
    protocolCapabilityRegistry | awk -F'|' -v lifecycle="${lifecycle}" '$3 == "node" && $4 == lifecycle { print $1 }' | paste -sd ','
}

protocolCapabilityIdsByProjectCore() {
    local core=$1
    protocolCapabilityRegistry | awk -F'|' -v core="${core}" '$3 == "node" && ("," $6 ",") ~ ("," core ",") { print $1 }' | paste -sd ','
}

protocolCapabilityIdByConfigFile() {
    local configFile=$1
    protocolCapabilityRegistry | awk -F'|' -v file="${configFile}" '$19 == file { print $1; found = 1; exit } END { exit found ? 0 : 1 }'
}

protocolCapabilityIsPublicNode() {
    [[ "$(protocolCapabilityMeta "$1" category 2>/dev/null)" == "node" ]]
}

protocolCapabilityPrintRows() {
    local categoryFilter=${1:-}
    local riskyOnly=${2:-false}
    local id name category lifecycle projectCore transport security nginxMode risk replacement
    while IFS='|' read -r id name category lifecycle _ projectCore _ transport security nginxMode _ _ _ _ _ _ _ _ _ _ _ risk replacement _; do
        [[ -z "${categoryFilter}" || "${category}" == "${categoryFilter}" ]] || continue
        [[ "${riskyOnly}" != "true" || -n "${risk}" ]] || continue
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "${id}" "${name}" "${category}" "${lifecycle}" "${projectCore}" "${transport}" "${security}" "${nginxMode}"
        if [[ -n "${risk}" ]]; then
            printf '\t%s' "${risk}"
            [[ -n "${replacement}" ]] && printf '\t替代：%s' "${replacement}"
        fi
        printf '\n'
    done < <(protocolCapabilityRegistry)
}

protocolListProtocols() {
    protocolCapabilityPrintRows node false
}

protocolListCapabilities() {
    protocolCapabilityPrintRows "" false
}

protocolShowRiskyProtocols() {
    protocolCapabilityPrintRows node true
}

protocolMetaBool() {
    case "$1" in
    yes | true | 1) printf '1' ;;
    *) printf '0' ;;
    esac
}

protocolMeta() {
    local protocolId=$1
    local key=$2
    local value

    case "${key}" in
    core)
        protocolCapabilityMeta "${protocolId}" project_core
        return
        ;;
    family)
        protocolCapabilityMeta "${protocolId}" protocol
        return
        ;;
    needs_tls)
        [[ "$(protocolCapabilityMeta "${protocolId}" security 2>/dev/null)" == "tls" ]] && printf '1' || printf '0'
        return
        ;;
    needs_domain)
        value=$(protocolCapabilityMeta "${protocolId}" requires_domain 2>/dev/null) || return 1
        protocolMetaBool "${value}"
        return
        ;;
    needs_certificate)
        value=$(protocolCapabilityMeta "${protocolId}" requires_cert 2>/dev/null) || return 1
        protocolMetaBool "${value}"
        return
        ;;
    needs_nginx)
        value=$(protocolCapabilityMeta "${protocolId}" nginx_mode 2>/dev/null) || return 1
        [[ "${value}" != "none" && "${value}" != "acme_only" ]] && printf '1' || printf '0'
        return
        ;;
    needs_reality | needs_reality_keys)
        [[ "$(protocolCapabilityMeta "${protocolId}" security 2>/dev/null)" == "reality" ]] && printf '1' || printf '0'
        return
        ;;
    needs_path)
        value=$(protocolCapabilityMeta "${protocolId}" transport 2>/dev/null) || return 1
        [[ ",ws,grpc,httpupgrade,xhttp," == *",${value},"* ]] && printf '1' || printf '0'
        return
        ;;
    needs_udp)
        value=$(protocolCapabilityMeta "${protocolId}" udp_support 2>/dev/null) || return 1
        protocolMetaBool "${value}"
        return
        ;;
    *)
        protocolCapabilityMeta "${protocolId}" "${key}"
        ;;
    esac
}

protocolSelectionIncludes() {
    local selection=$1
    local protocolId=$2
    [[ "${3:-}" == "all" ]] && return 0
    protocolSelectionHasAny "${selection}" "${protocolId}"
}

protocolSelectionHasCapability() {
    local selection=$1
    local key=$2
    local protocolId
    selection=",${selection// /},"
    selection=${selection//,,/,}
    while IFS='|' read -r protocolId _; do
        if [[ "${selection}" == *",${protocolId},"* ]] && [[ "$(protocolMeta "${protocolId}" "${key}" 2>/dev/null)" == "1" ]]; then
            return 0
        fi
    done < <(protocolCapabilityRegistry)
    return 1
}

protocolSelectionOnlyRealityNoDomain() {
    local selection=$1
    local normalized protocolId sawProtocol=false
    normalized=",${selection// /},"
    normalized=${normalized//,,/,}
    normalized=${normalized#,}
    normalized=${normalized%,}
    [[ -n "${normalized}" ]] || return 1
    IFS=',' read -ra protocolIds <<<"${normalized}"
    for protocolId in "${protocolIds[@]}"; do
        [[ -n "${protocolId}" ]] || continue
        sawProtocol=true
        [[ "$(protocolCapabilityMeta "${protocolId}" security 2>/dev/null)" == "reality" ]] || return 1
        [[ "$(protocolCapabilityMeta "${protocolId}" requires_domain 2>/dev/null)" == "no" ]] || return 1
    done
    [[ "${sawProtocol}" == "true" ]]
}

protocolSelectionHasAny() {
    local selection=$1
    shift
    local normalized protocolId
    normalized=",${selection// /},"
    normalized=${normalized//,,/,}
    for protocolId in "$@"; do
        [[ "${normalized}" == *",${protocolId},"* ]] && return 0
    done
    return 1
}

protocolSelectionIsExactly() {
    [[ "$(protocolSelectionNormalizeCsv "$1")" == ",$2," ]]
}

protocolSelectionSupportsStrictRealityDomain() {
    protocolSelectionIsExactly "$1" 1
}

realityStrictDomainModeEnabled() {
    [[ -n "${realityOnlyWithDomain:-}" ]] || [[ "$(normalizeYesNo "${AUTO_REALITY_DOMAIN:-}")" == "y" ]]
}

currentProtocolHas() {
    local protocolId=$1
    protocolSelectionHasAny "${currentInstallProtocolType}" "${protocolId}"
}

currentProtocolHasAny() {
    protocolSelectionHasAny "${currentInstallProtocolType}" "$@"
}

protocolSelectionSkipsNginx() {
    local selection=$1
    local normalized protocolId mode sawProtocol=false
    normalized=$(protocolSelectionNormalizeCsv "${selection}")
    normalized=${normalized#,}
    normalized=${normalized%,}
    [[ -n "${normalized}" ]] || return 1
    IFS=',' read -ra protocolIds <<<"${normalized}"
    for protocolId in "${protocolIds[@]}"; do
        [[ -n "${protocolId}" ]] || continue
        sawProtocol=true
        mode=$(protocolCapabilityMeta "${protocolId}" nginx_mode 2>/dev/null) || return 1
        [[ "${mode}" == "none" || "${mode}" == "acme_only" ]] || return 1
    done
    [[ "${sawProtocol}" == "true" ]]
}

protocolSelectionNeedsPath() {
    local selection=$1
    protocolSelectionHasCapability "${selection}" "needs_path"
}

protocolSelectionNeedsCertificate() {
    local selection=$1
    protocolSelectionHasCapability "${selection}" "needs_certificate"
}


protocolSelectionNeedsLocalCertificate() {
    local selection=$1
    protocolSelectionNeedsCertificate "${selection}"
}

protocolStateAdd() {
    local protocolId=$1
    [[ -n "${protocolId}" ]] || return
    if [[ ",${currentInstallProtocolType}" != *",${protocolId},"* ]]; then
        currentInstallProtocolType="${currentInstallProtocolType}${protocolId},"
    fi
}

xrayProtocolName() {
    local protocolId=$1
    protocolCapabilityMeta "${protocolId}" name 2>/dev/null
}

protocolMenuDescription() {
    local protocolId=$1
    local core transport security lifecycle risk replacement desc
    core=$(protocolMeta "${protocolId}" core 2>/dev/null)
    transport=$(protocolMeta "${protocolId}" transport 2>/dev/null)
    security=$(protocolMeta "${protocolId}" security 2>/dev/null)
    lifecycle=$(protocolMeta "${protocolId}" lifecycle 2>/dev/null)
    risk=$(protocolMeta "${protocolId}" risk_note 2>/dev/null)
    replacement=$(protocolMeta "${protocolId}" replacement 2>/dev/null)
    desc="${core} / ${transport} / ${security}"
    [[ "${lifecycle}" == "recommended" ]] && desc="推荐；${desc}"
    if [[ -n "${risk}" ]]; then
        desc="${risk}；替代：${replacement:-按场景选择推荐协议}；${desc}"
    fi
    printf '%s' "${desc}"
}

protocolRegistryMenu() {
    local allowedIds=$1
    local protocolId protocolName protocolDesc
    while IFS='|' read -r protocolId protocolName _; do
        if protocolSelectionHasAny "${allowedIds}" "${protocolId}"; then
            protocolDesc=$(protocolMenuDescription "${protocolId}")
            menuItem "${protocolId}" "${protocolName}" "${protocolDesc}"
        fi
    done < <(protocolCapabilityRegistry)
}

protocolSelectionIdsValid() {
    local selection=$1
    local allowedIds=${2:-}
    local protocolId
    selection=",${selection// /},"
    selection=${selection//,,/,}
    while read -r protocolId; do
        [[ -n "${protocolId}" ]] || continue
        protocolCapabilityIsPublicNode "${protocolId}" || return 1
        if [[ -n "${allowedIds}" ]]; then
            protocolSelectionHasAny "${allowedIds}" "${protocolId}" || return 1
        fi
    done < <(echo "${selection//,/ }" | tr ' ' '\n')
    return 0
}

protocolCoreUnsupportedReason() {
    local core=$1
    local selection=$2
    local protocolId transport

    selection=$(protocolSelectionNormalizeCsv "${selection}")
    selection=${selection#,}
    selection=${selection%,}
    [[ -n "${selection}" ]] || return 1
    IFS=',' read -ra protocolIds <<<"${selection}"
    for protocolId in "${protocolIds[@]}"; do
        [[ -n "${protocolId}" ]] || continue
        if ! protocolCapabilityIsPublicNode "${protocolId}"; then
            printf 'protocol %s is not a public node capability' "${protocolId}"
            return 0
        fi
        if ! protocolSelectionHasAny "$(protocolSelectionCurrentIdsForCore "${core}")" "${protocolId}"; then
            transport=$(protocolCapabilityMeta "${protocolId}" transport 2>/dev/null || true)
            if [[ "${core}" == "sing-box" && "${transport}" == "xhttp" ]]; then
                printf 'sing-box currently has no XHTTP transport support'
                return 0
            fi
            printf '%s does not support protocol %s (%s)' "${core}" "${protocolId}" "$(protocolCapabilityMeta "${protocolId}" name 2>/dev/null || printf 'unknown')"
            return 0
        fi
    done
    return 1
}

protocolSelectionNormalizeCsv() {
    local selection=$1
    selection="${selection// /}"
    selection="${selection//，/,}"
    selection=",${selection},"
    while [[ "${selection}" == *",,"* ]]; do
        selection=${selection//,,/,}
    done
    printf '%s' "${selection}"
}

protocolSelectionCurrentIdsForCore() {
    local core=$1
    local ids
    ids=$(protocolCapabilityIdsByProjectCore "${core}")
    printf ',%s,' "${ids}"
}

protocolRegistryMenuByLifecycle() {
    local allowedIds=$1
    local lifecycle=$2
    local ids id
    ids=$(protocolCapabilityIdsByLifecycle "${lifecycle}")
    IFS=',' read -ra idArray <<<"${ids}"
    for id in "${idArray[@]}"; do
        [[ -n "${id}" ]] || continue
        protocolSelectionHasAny "${allowedIds}" "${id}" || continue
        menuItem "${id}" "$(protocolCapabilityMeta "${id}" name)" "$(protocolMenuDescription "${id}")"
    done
}

protocolSelectionShowRiskNotes() {
    local selection=$1
    local id risk replacement
    selection=$(protocolSelectionNormalizeCsv "${selection}")
    while read -r id; do
        [[ -n "${id}" ]] || continue
        protocolSelectionHasAny "${selection}" "${id}" || continue
        risk=$(protocolCapabilityMeta "${id}" risk_note 2>/dev/null || true)
        [[ -n "${risk}" ]] || continue
        replacement=$(protocolCapabilityMeta "${id}" replacement 2>/dev/null || true)
        statusCard "高级协议风险：$(protocolCapabilityMeta "${id}" name)" "${risk}" "替代方案：${replacement:-按场景选择推荐协议}"
    done < <(protocolCapabilityRegistry | awk -F'|' '$3 == "node" { print $1 }')
}
