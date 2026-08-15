#!/usr/bin/env bash

if ! declare -F padmRealAppendDefaultSubscribeLine >/dev/null 2>&1; then
    eval "$(declare -f appendDefaultSubscribeLine | sed '1s/^appendDefaultSubscribeLine/padmRealAppendDefaultSubscribeLine/')"
    eval "$(declare -f appendClashMetaSubscribeBlock | sed '1s/^appendClashMetaSubscribeBlock/padmRealAppendClashMetaSubscribeBlock/')"
    eval "$(declare -f appendClashMetaSubscribeLines | sed '1s/^appendClashMetaSubscribeLines/padmRealAppendClashMetaSubscribeLines/')"
    eval "$(declare -f appendSingBoxSubscribeLocalConfig | sed '1s/^appendSingBoxSubscribeLocalConfig/padmRealAppendSingBoxSubscribeLocalConfig/')"
fi

restoreLegacyRegressionContext() {
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
}

restoreLegacyRegressionContext
