#!/usr/bin/env bash

xray_protocol_registry() {
    cat <<'EOF'
0|02_VLESS_TCP_inbounds.json|VLESS TCP TLS Vision|core=xray|family=vless|transport=tcp|security=tls|needs_tls=1|needs_domain=1|needs_certificate=1|needs_nginx=0|needs_reality=0|needs_path=0|needs_udp=0
1|03_VLESS_WS_inbounds.json|VLESS WS TLS|core=xray|family=vless|transport=ws|security=tls|needs_tls=1|needs_domain=1|needs_certificate=1|needs_nginx=1|needs_reality=0|needs_path=1|needs_udp=0
2|04_trojan_GRPc_inbounds.json|Trojan gRPC TLS|core=xray|family=trojan|transport=grpc|security=tls|needs_tls=1|needs_domain=1|needs_certificate=1|needs_nginx=1|needs_reality=0|needs_path=1|needs_udp=0
3|05_VMess_WS_inbounds.json|VMess WS TLS|core=xray|family=vmess|transport=ws|security=tls|needs_tls=1|needs_domain=1|needs_certificate=1|needs_nginx=1|needs_reality=0|needs_path=1|needs_udp=0
4|04_trojan_TCP_inbounds.json|Trojan TCP TLS|core=xray|family=trojan|transport=tcp|security=tls|needs_tls=1|needs_domain=1|needs_certificate=1|needs_nginx=0|needs_reality=0|needs_path=0|needs_udp=0
5|06_VLESS_GRPc_inbounds.json|VLESS gRPC TLS|core=xray|family=vless|transport=grpc|security=tls|needs_tls=1|needs_domain=1|needs_certificate=1|needs_nginx=1|needs_reality=0|needs_path=1|needs_udp=0
6|06_hysteria2_inbounds.json|Hysteria2|core=sing-box|family=hysteria2|transport=quic|security=tls|needs_tls=1|needs_domain=1|needs_certificate=1|needs_nginx=0|needs_reality=0|needs_path=0|needs_udp=1
7|07_VLESS_vision_reality_inbounds.json|VLESS Reality Vision|core=xray|family=vless|transport=tcp|security=reality|needs_tls=0|needs_domain=0|needs_certificate=0|needs_nginx=0|needs_reality=1|needs_reality_keys=1|needs_path=0|needs_udp=0
8|08_VLESS_vision_gRPC_inbounds.json|VLESS Reality gRPC|core=xray|family=vless|transport=grpc|security=reality|needs_tls=0|needs_domain=0|needs_certificate=0|needs_nginx=0|needs_reality=1|needs_reality_keys=1|needs_path=0|needs_udp=0
9|09_tuic_inbounds.json|Tuic|core=sing-box|family=tuic|transport=quic|security=tls|needs_tls=1|needs_domain=1|needs_certificate=1|needs_nginx=0|needs_reality=0|needs_path=0|needs_udp=1
10|10_naive_inbounds.json|Naive|core=sing-box|family=naive|transport=tcp|security=tls|needs_tls=1|needs_domain=1|needs_certificate=1|needs_nginx=0|needs_reality=0|needs_path=0|needs_udp=0
11|11_VMess_HTTPUpgrade_inbounds.json|VMess HTTPUpgrade TLS|core=xray|family=vmess|transport=httpupgrade|security=tls|needs_tls=1|needs_domain=1|needs_certificate=1|needs_nginx=1|needs_reality=0|needs_path=1|needs_udp=0
12|12_VLESS_XHTTP_inbounds.json|VLESS Reality XHTTP|core=xray|family=vless|transport=xhttp|security=reality|needs_tls=0|needs_domain=0|needs_certificate=0|needs_nginx=0|needs_reality=1|needs_reality_keys=1|needs_path=1|needs_udp=0
13|13_anytls_inbounds.json|AnyTLS|core=sing-box|family=anytls|transport=tcp|security=tls|needs_tls=1|needs_domain=1|needs_certificate=1|needs_nginx=0|needs_reality=0|needs_path=0|needs_udp=0
20|20_socks5_inbounds.json|Socks5|core=sing-box|family=socks5|transport=tcp|security=none|needs_tls=0|needs_domain=0|needs_certificate=0|needs_nginx=0|needs_reality=0|needs_path=0|needs_udp=1
EOF
}

protocolMeta() {
    local protocolId=$1
    local key=$2
    local entry caps cap
    entry=$(xray_protocol_registry | awk -F'|' -v id="$protocolId" '$1 == id { print }')
    [[ -n "${entry}" ]] || return 1
    case "${key}" in
    id)
        printf '%s' "$(printf '%s' "${entry}" | awk -F'|' '{print $1}')"
        return 0
        ;;
    file | filename)
        printf '%s' "$(printf '%s' "${entry}" | awk -F'|' '{print $2}')"
        return 0
        ;;
    name)
        printf '%s' "$(printf '%s' "${entry}" | awk -F'|' '{print $3}')"
        return 0
        ;;
    esac
    caps=${entry#*|*|*|}
    IFS='|' read -ra capArray <<<"${caps}"
    for cap in "${capArray[@]}"; do
        if [[ "${cap}" == "${key}="* ]]; then
            printf '%s' "${cap#*=}"
            return 0
        fi
    done
    return 1
}

xrayProtocolCapability() {
    local protocolId=$1
    local key=$2
    [[ "$(protocolMeta "${protocolId}" "${key}" 2>/dev/null)" == "1" ]]
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
    while IFS='|' read -r protocolId _ _ _; do
        if [[ "${selection}" == *",${protocolId},"* ]] && xrayProtocolCapability "${protocolId}" "${key}"; then
            return 0
        fi
    done < <(xray_protocol_registry)
    return 1
}

protocolSelectionOnlyRealityNoDomain() {
    local selection=$1
    local normalized
    normalized=",${selection// /},"
    normalized=${normalized//,,/,}
    [[ "${normalized}" == ",7," || "${normalized}" == ",7,8," || "${normalized}" == ",7,12," || "${normalized}" == ",8," || "${normalized}" == ",12," ]]
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

protocolSelectionHasAll() {
    local selection=$1
    shift
    local normalized protocolId
    normalized=",${selection// /},"
    normalized=${normalized//,,/,}
    for protocolId in "$@"; do
        [[ "${normalized}" == *",${protocolId},"* ]] || return 1
    done
    return 0
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
    protocolSelectionOnlyRealityNoDomain "${selection}" && [[ -z "${realityOnlyWithDomain}" ]]
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
    protocolSelectionNeedsCertificate "${selection}" || [[ -n "${realityOnlyWithDomain:-}" ]]
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
    xray_protocol_registry | awk -F'|' -v id="$protocolId" '$1 == id { print $3 }'
}

xrayProtocolEnabled() {
    local protocolId=$1
    [[ " ${currentInstallProtocolType} " == *",${protocolId},"* ]]
}

xrayProtocolDisplayName() {
    local protocolId=$1
    case "${protocolId}" in
    0) echo "VLESS+TCP/TLS_Vision" ;;
    1) echo "VLESS+WS/TLS" ;;
    2) echo "Trojan+gRPC/TLS" ;;
    3) echo "VMess+WS/TLS" ;;
    4) echo "Trojan+TCP/TLS" ;;
    5) echo "VLESS+gRPC/TLS" ;;
    6) echo "Hysteria2" ;;
    7) echo "VLESS+Reality+Vision" ;;
    8) echo "VLESS+Reality+gRPC" ;;
    9) echo "Tuic" ;;
    10) echo "Naive" ;;
    11) echo "VMess+HTTPUpgrade" ;;
    12) echo "VLESS+Reality+XHTTP" ;;
    13) echo "AnyTLS" ;;
    20) echo "Socks5" ;;
    *) xrayProtocolName "${protocolId}" ;;
    esac
}

xrayEnabledProtocolDisplayList() {
    local protocolId name protocolList=
    while IFS='|' read -r protocolId _ _ _; do
        if xrayProtocolEnabled "${protocolId}"; then
            name=$(xrayProtocolDisplayName "${protocolId}")
            protocolList="${protocolList} ${name}"
        fi
    done < <(xray_protocol_registry)
    echo "${protocolList}"
}

protocolMenuDescription() {
    local protocolId=$1
    local core transport security desc
    core=$(protocolMeta "${protocolId}" core 2>/dev/null)
    transport=$(protocolMeta "${protocolId}" transport 2>/dev/null)
    security=$(protocolMeta "${protocolId}" security 2>/dev/null)
    desc="${core} / ${transport} / ${security}"
    case "${protocolId}" in
    7)
        desc="推荐直连；${desc}"
        ;;
    12)
        desc="推荐 CDN/反代；${desc}"
        ;;
    0)
        desc="传统 TLS 前置/兼容；${desc}"
        ;;
    6 | 9)
        desc="UDP/移动网络按需；${desc}"
        ;;
    10)
        desc="TLS 指纹抗性优先；${desc}"
        ;;
    13)
        desc="sing-box AnyTLS 按需；${desc}"
        ;;
    1 | 2 | 3 | 4 | 5 | 11)
        desc="传统 TLS 兼容；${desc}"
        ;;
    esac
    printf '%s' "${desc}"
}

protocolRegistryMenu() {
    local allowedIds=$1
    local protocolId protocolName protocolDesc
    while IFS='|' read -r protocolId _ protocolName _; do
        if protocolSelectionHasAny "${allowedIds}" "${protocolId}"; then
            protocolDesc=$(protocolMenuDescription "${protocolId}")
            menuItem "${protocolId}" "${protocolName}" "${protocolDesc}"
        fi
    done < <(xray_protocol_registry)
}

protocolSelectionIdsValid() {
    local selection=$1
    local allowedIds=$2
    local protocolId
    selection=",${selection// /},"
    selection=${selection//,,/,}
    while read -r protocolId; do
        [[ -n "${protocolId}" ]] || continue
        protocolSelectionHasAny "${allowedIds}" "${protocolId}" || return 1
    done < <(echo "${selection//,/ }" | tr ' ' '\n')
    return 0
}
