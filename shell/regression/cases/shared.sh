#!/usr/bin/env bash

if ! declare -F padmRealAppendDefaultSubscribeLine >/dev/null 2>&1; then
    eval "$(declare -f appendDefaultSubscribeLine | sed '1s/^appendDefaultSubscribeLine/padmRealAppendDefaultSubscribeLine/')"
    eval "$(declare -f appendClashMetaSubscribeBlock | sed '1s/^appendClashMetaSubscribeBlock/padmRealAppendClashMetaSubscribeBlock/')"
    eval "$(declare -f appendClashMetaSubscribeLines | sed '1s/^appendClashMetaSubscribeLines/padmRealAppendClashMetaSubscribeLines/')"
    eval "$(declare -f appendSingBoxSubscribeLocalConfig | sed '1s/^appendSingBoxSubscribeLocalConfig/padmRealAppendSingBoxSubscribeLocalConfig/')"
fi

REALITY_TLS_PING_ARGS_FILE="${TMP_DIR}/tls_ping_args.txt"
SUBSCRIBE_CAPTURE_DIR="${TMP_DIR}/subscribe_local"
configPath="${TMP_DIR}/xray-conf/"
singBoxConfigPath="${TMP_DIR}/sing-box-conf/"

regressionFindHasMatches() {
    local firstMatch
    firstMatch=$(find "$@" -print -quit 2>/dev/null) || return 1
    [[ -n "${firstMatch}" ]]
}

readInstallType() {
    coreInstallType=${coreInstallType:-1}
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
    if [[ -n "${REALITY_ASN_LOOKUP_ARGS_FILE:-}" ]]; then
        printf '%s\n' "$1" >>"${REALITY_ASN_LOOKUP_ARGS_FILE}"
    fi
    case "$1" in
    198.51.100.*) printf 'AS64501\tRemoteNet\n' ;;
    *) printf 'AS64500\tExampleNet\n' ;;
    esac
}

appendDefaultSubscribeLine() {
    local user=$1 line=$2
    mkdir -p "${SUBSCRIBE_CAPTURE_DIR}/default"
    printf '%s\n' "${line}" >>"${SUBSCRIBE_CAPTURE_DIR}/default/${user}"
}

appendClashMetaSubscribeBlock() {
    local user=$1 block=$2
    mkdir -p "${SUBSCRIBE_CAPTURE_DIR}/clashMeta"
    printf '%s\n' "${block}" >>"${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"
}

appendSingBoxSubscribeLocalConfig() {
    local user=$1 jqFilter=$2
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

fake-xray() {
    local concurrencyMarker= active=0 attempt=0
    [[ "$1" == "tls" && "$2" == "ping" ]]
    printf '%s\n' "$*" >>"${REALITY_TLS_PING_ARGS_FILE}"
    if [[ -n "${PADM_FAKE_XRAY_CONCURRENCY_DIR:-}" ]]; then
        command mkdir -p "${PADM_FAKE_XRAY_CONCURRENCY_DIR}/active"
        concurrencyMarker="${PADM_FAKE_XRAY_CONCURRENCY_DIR}/active/${BASHPID:-$$}"
        : >"${concurrencyMarker}"
        for ((attempt = 0; attempt < 200; attempt++)); do
            active=$(find "${PADM_FAKE_XRAY_CONCURRENCY_DIR}/active" -type f | wc -l | tr -d ' ')
            (( active >= 2 )) && break
            command sleep 0.01
        done
        printf '%s\n' "${active}" >>"${PADM_FAKE_XRAY_CONCURRENCY_DIR}/observed"
        command sleep 0.05
        command rm -f "${concurrencyMarker}"
    fi
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
