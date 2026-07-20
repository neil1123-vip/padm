#!/usr/bin/env bash
set -euo pipefail

REGRESSION_ENTRY_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
REGRESSION_ENTRY_SCRIPT_PATH="${REGRESSION_ENTRY_DIR}/subscription_groups_regression.sh"
REGRESSION_LEGACY_SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")"
# shellcheck source=/dev/null
source "${REGRESSION_ENTRY_DIR}/regression/bootstrap.sh"

regressionFindHasMatches() {
    local firstMatch
    firstMatch=$(find "$@" -print -quit 2>/dev/null) || return 1
    [[ -n "${firstMatch}" ]]
}

if ! declare -F coreSetRollbackResultMessage >/dev/null 2>&1; then
    coreSetRollbackResultMessage() {
        local outputVar=$1
        local reason=$2
        local restoredMessage=$3
        local retryFn=${4:-}
        local retryFailureMessage=${5:-}
        local result

        if [[ -n "${retryFn}" ]]; then
            shift 5
            if "${retryFn}" "$@"; then
                result="${reason}，${restoredMessage}"
            else
                result="${reason}，${restoredMessage}；${retryFailureMessage}"
            fi
        else
            result="${reason}，${restoredMessage}"
        fi

        printf -v "${outputVar}" '%s' "${result}"
    }
fi

if ! declare -F coreSetSingleRestoreResultMessage >/dev/null 2>&1; then
    coreSetSingleRestoreResultMessage() {
        local outputVar=$1
        local reason=$2
        local restored=$3
        local restoredMessage=$4
        local failedLabel=$5
        local failedLocation=$6
        local result=

        if [[ "${restored}" == "true" ]]; then
            result="${reason}，${restoredMessage}"
            printf -v "${outputVar}" '%s' "${result}"
            return 0
        fi

        coreSetRestoreFailureDetail result "${failedLabel}" "${failedLocation}"
        result="${reason}，且${result}"
        printf -v "${outputVar}" '%s' "${result}"
        return 1
    }
fi

if ! declare -F coreSetRestoreFailureDetail >/dev/null 2>&1; then
    coreSetRestoreFailureDetail() {
        local outputVar=$1
        local failedLabel=$2
        local failedLocation=$3
        coreSetManualCheckMessage "${outputVar}" "${failedLabel}恢复失败" "${failedLocation}"
    }
fi

if ! declare -F coreSetManualCheckMessage >/dev/null 2>&1; then
    coreSetManualCheckMessage() {
        local outputVar=$1
        local reason=$2
        local checkTarget=$3
        local formatted="${reason}，请手动检查${checkTarget}"

        printf -v "${outputVar}" '%s' "${formatted}"
    }
fi

if ! declare -F coreSetDualRestoreResultMessage >/dev/null 2>&1; then
    coreSetDualRestoreResultMessage() {
        local outputVar=$1
        local reason=$2
        local firstRestored=$3
        local firstLabel=$4
        local firstLocation=$5
        local secondRestored=$6
        local secondLabel=$7
        local secondLocation=$8
        local result=

        if [[ "${firstRestored}" != "true" ]]; then
            coreSetRestoreFailureDetail result "${firstLabel}" "${firstLocation}"
            result="${reason}，且${result}"
            printf -v "${outputVar}" '%s' "${result}"
            return 1
        fi
        if [[ "${secondRestored}" != "true" ]]; then
            coreSetRestoreFailureDetail result "${secondLabel}" "${secondLocation}"
            result="${reason}，且${result}"
            printf -v "${outputVar}" '%s' "${result}"
            return 1
        fi

        printf -v "${outputVar}" '%s' ''
        return 0
    }
fi

if ! declare -F coreSetPairedFileManualCheckMessage >/dev/null 2>&1; then
    coreSetPairedFileManualCheckMessage() {
        local outputVar=$1
        local reason=$2
        local targetPath=$3
        local backupPath=$4
        coreSetManualCheckMessage "${outputVar}" "${reason}" " ${targetPath} 和 ${backupPath}"
    }
fi

if ! declare -F coreSetPairedFileRestoreFailureMessage >/dev/null 2>&1; then
    coreSetPairedFileRestoreFailureMessage() {
        local outputVar=$1
        local reason=$2
        local failedLabel=$3
        local targetPath=$4
        local backupPath=$5
        coreSetPairedFileManualCheckMessage "${outputVar}" "${reason}，${failedLabel}恢复失败" "${targetPath}" "${backupPath}"
    }
fi

if ! declare -F coreSetRollbackFailureMessage >/dev/null 2>&1; then
    coreSetRollbackFailureMessage() {
        local outputVar=$1
        local reason=$2
        local backupDir=$3
        local separator=${4-，且}
        local result=

        if [[ -n "${separator}" ]]; then
            coreSetManualCheckMessage result "${reason}${separator}回滚失败" "备份目录: ${backupDir}"
        else
            coreSetManualCheckMessage result "${reason}" "备份目录: ${backupDir}"
        fi

        printf -v "${outputVar}" '%s' "${result}"
    }
fi

if ! declare -F coreSetNewConfigCleanupFailureMessage >/dev/null 2>&1; then
    coreSetNewConfigCleanupFailureMessage() {
        local outputVar=$1
        local reason=$2
        local targetPath=$3
        coreSetManualCheckMessage "${outputVar}" "${reason}，且新配置清理失败" " ${targetPath}"
    }
fi

if ! declare -F padmCreateTmpRootPath >/dev/null 2>&1; then
    padmCreateTmpRootPath() {
        local outputVar=$1
        local template=$2
        local tmpBase="${TMPDIR:-/tmp}"

        shift 2
        padmCreateTempPath "${outputVar}" "$@" "${tmpBase%/}/${template}"
    }
fi

if ! declare -F corePortReportBackupFailure >/dev/null 2>&1; then
    corePortReportBackupFailure() {
        local backupDir=$1
        padmRemoveCleanupPath "${backupDir}"
        errorCard "入口端口配置备份失败"
    }
fi

if ! declare -F corePortReportRollbackFailure >/dev/null 2>&1; then
    corePortReportRollbackFailure() {
        local backupDir=$1
        local rollbackMessage
        padmForgetCleanupPath "${backupDir}"
        coreSetRollbackFailureMessage rollbackMessage "入口端口配置回滚失败" "${backupDir}" ""
        errorCard "${rollbackMessage}"
    }
fi

if ! declare -F subscriptionSyncSetManualCheckMessage >/dev/null 2>&1; then
    subscriptionSyncSetManualCheckMessage() {
        coreSetManualCheckMessage "$@"
    }
fi

if ! declare -F writeUserConfigJq >/dev/null 2>&1; then
    writeUserConfigJq() {
        local targetPath=$1
        local jqFilter=$2
        local tmpPath

        shift 2
        targetPath=$(padmRequireSafeAbsolutePath "${targetPath}") || return 1
        padmCreateTempFileForTarget tmpPath "${targetPath}" user || return 1
        if ! jq "$@" "${jqFilter}" "${targetPath}" >"${tmpPath}"; then
            padmRemoveCleanupPath "${tmpPath}"
            return 1
        fi
        commitGeneratedJsonFile "${tmpPath}" "${targetPath}" || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
    }
fi

if ! declare -F removeUserFromConfigFile >/dev/null 2>&1; then
    removeUserFromConfigFile() {
        local targetPath=$1
        local userPath=$2
        local targetId=$3
        local targetAccount=$4
        local jqFilter

        [[ -f "${targetPath}" ]] || return 0
        jqFilter='
          def padm_user_account:
            (.email // .name // .username // "")
            | sub("-(VLESS_TCP/TLS_Vision|VLESS_WS|VLESS_Reality_XHTTP|Trojan_gRPC|VMess_WS|trojan_tcp|Trojan_TCP|Trojan_TCP_direct|vless_grpc|singbox_hysteria2|vless_reality_vision|vless_reality_grpc|VLESS_Reality_Vision|VLESS_Reality_GPRC|VLESS_Reality_gPRC|singbox_tuic|singbox_naive|VMess_HTTPUpgrade|shadowsocks|anytls)$"; "");
          '"${userPath}"' = (('"${userPath}"' // []) | map(select(
            (($targetId == "") or ((.id // .uuid // .password // "") != $targetId)) and
            (($targetAccount == "") or (padm_user_account != $targetAccount))
          )))'
        writeUserConfigJq "${targetPath}" "${jqFilter}" --arg targetId "${targetId}" --arg targetAccount "${targetAccount}"
    }
fi

if ! declare -F removeUserFromConfigFiles >/dev/null 2>&1; then
    removeUserFromConfigFiles() {
        local targetId=$1
        local targetAccount=$2
        local status=0

        removeUserFromConfigFile "${configPath}02_VLESS_TCP_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${configPath}03_VLESS_WS_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${configPath}04_trojan_gRPC_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${configPath}04_trojan_GRPc_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${configPath}05_VMess_WS_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${configPath}06_VLESS_GRPc_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${configPath}06_VLESS_gRPC_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${configPath}04_trojan_TCP_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${configPath}07_VLESS_vision_reality_inbounds.json" ".inbounds[1].settings.clients" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${configPath}08_VLESS_vision_gRPC_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${configPath}11_VMess_HTTPUpgrade_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${configPath}12_VLESS_XHTTP_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1
        removeUserFromConfigFile "${configPath}28_trojan_TCP_direct_inbounds.json" ".inbounds[0].settings.clients" "${targetId}" "${targetAccount}" || status=1

        if [[ -n "${singBoxConfigPath:-}" ]]; then
            removeUserFromConfigFile "${singBoxConfigPath}02_VLESS_TCP_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
            removeUserFromConfigFile "${singBoxConfigPath}03_VLESS_WS_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
            removeUserFromConfigFile "${singBoxConfigPath}05_VMess_WS_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
            removeUserFromConfigFile "${singBoxConfigPath}06_hysteria2_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
            removeUserFromConfigFile "${singBoxConfigPath}07_VLESS_vision_reality_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
            removeUserFromConfigFile "${singBoxConfigPath}08_VLESS_vision_gRPC_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
            removeUserFromConfigFile "${singBoxConfigPath}09_tuic_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
            removeUserFromConfigFile "${singBoxConfigPath}10_naive_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
            removeUserFromConfigFile "${singBoxConfigPath}11_VMess_HTTPUpgrade_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
            removeUserFromConfigFile "${singBoxConfigPath}13_anytls_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
            removeUserFromConfigFile "${singBoxConfigPath}28_trojan_TCP_direct_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
            removeUserFromConfigFile "${singBoxConfigPath}30_shadowsocks_inbounds.json" ".inbounds[0].users" "${targetId}" "${targetAccount}" || status=1
        fi
        return "${status}"
    }
fi

if ! declare -F regressionProtocolSelectionIncludesCompat >/dev/null 2>&1; then
    regressionProtocolSelectionIncludesCompat() {
        local selection=$1
        local protocolId=$2
        local mode=${3:-}

        [[ "${mode}" == "all" ]] && return 0
        if [[ "${protocolId}" == "11" ]] && [[ ",${selection}," == *",23,"* ]]; then
            return 0
        fi
        protocolSelectionHasAny "${selection}" "${protocolId}"
    }
fi

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

    set +e
    updateRoutingJsonConfig "${configPath}09_routing.json" '.routing.rules += [{"type":"field"}]' >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    jq -e '.routing.rules == []' "${root}/relative-config/09_routing.json" >/dev/null
    ! compgen -G "${root}/relative-config/.09_routing.json.routing.*" >/dev/null

    set +e
    removeXrayOutbound "09_routing" >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -f "${root}/relative-config/09_routing.json" ]]

    set +e
    removeSingBoxConfig "socks5_outbound" >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
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

runAccessControlRejectsUnsafeBackupDirRegression() (
    local root="${TMP_DIR}/access-control-unsafe-backup"
    local rmLog="${root}/rm.log"
    local rc

    mkdir -p "${root}"
    : >"${rmLog}"
    PADM_ACCESS_CONTROL_BACKUP_DIR=relative-backup
    configPath="${root}/xray/"
    singBoxConfigPath=
    mkdir -p "${configPath}"

    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    set +e
    accessControlBackupCreate >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -s "${rmLog}" ]]

    set +e
    accessControlBackupCleanup >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -s "${rmLog}" ]]

    mkdir -p "${root}/relative-backup/xray"
    printf 'old\n' >"${root}/relative-backup/xray/09_routing.json"
    (
        cd "${root}"
        set +e
        accessControlBackupRestore >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
    )
    [[ ! -s "${rmLog}" ]]
)

runAccessControlRejectsUnsafeConfigDirRegression() (
    local root="${TMP_DIR}/access-control-unsafe-config"
    local rmLog="${root}/rm.log"
    local rc

    mkdir -p "${root}/unsafe-config"
    : >"${rmLog}"
    configPath="relative-config/"
    singBoxConfigPath=
    PADM_ACCESS_CONTROL_BACKUP_DIR="${root}/backup"

    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    set +e
    accessControlBackupCreate >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -s "${rmLog}" ]]
    [[ ! -e "${PADM_ACCESS_CONTROL_BACKUP_DIR}" ]]

    mkdir -p "${PADM_ACCESS_CONTROL_BACKUP_DIR}/xray"
    printf 'old\n' >"${PADM_ACCESS_CONTROL_BACKUP_DIR}/xray/09_routing.json"
    set +e
    accessControlBackupRestore >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -s "${rmLog}" ]]
)

runBTRoutingFailureReturnRegression() (
    local root="${TMP_DIR}/bt-routing-failure"
    local installMarker="${root}/install"
    local sniffMarker="${root}/sniff"
    local uninstallMarker="${root}/uninstall"
    local reloadMarker="${root}/reload"
    local rc reloadCalls=0

    mkdir -p "${root}/xray" "${root}/sing-box"
    configPath="${root}/xray/"
    singBoxConfigPath=
    coreInstallType=1
    errorCard() { return 0; }
    showBTBlockStatus() { return 0; }
    readInstallType() { coreInstallType=1; }

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
        printf 'new-routing\n' >"${configPath}09_routing.json"
        printf 'new-inbound\n' >"${configPath}02_test_inbounds.json"
        return 0
    }
    reloadCore() {
        reloadCalls=$((reloadCalls + 1))
        printf 'reload\n' >>"${reloadMarker}"
        [[ "${reloadCalls}" -gt 1 ]]
    }
    printf 'old-routing\n' >"${configPath}09_routing.json"
    printf 'old-inbound\n' >"${configPath}02_test_inbounds.json"
    rm -f "${installMarker}" "${reloadMarker}"
    reloadCalls=0
    set +e
    btTools >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${installMarker}" ]]
    [[ -e "${reloadMarker}" ]]
    [[ "$(<"${configPath}09_routing.json")" == "old-routing" ]]
    [[ "$(<"${configPath}02_test_inbounds.json")" == "old-inbound" ]]
    [[ "${reloadCalls}" == "2" ]]

    autoRead() { printf -v "$3" '2'; }
    uninstallBTBlock() {
        printf 'uninstall\n' >"${uninstallMarker}"
        printf 'new-routing\n' >"${configPath}09_routing.json"
        return 0
    }
    printf 'old-routing\n' >"${configPath}09_routing.json"
    rm -f "${uninstallMarker}" "${reloadMarker}"
    reloadCalls=0
    set +e
    btTools >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${uninstallMarker}" ]]
    [[ -e "${reloadMarker}" ]]
    [[ "$(<"${configPath}09_routing.json")" == "old-routing" ]]
    [[ "${reloadCalls}" == "2" ]]
)

runIPv6RoutingFailureReturnRegression() (
    local root="${TMP_DIR}/ipv6-routing-failure"
    local outboundMarker="${root}/outbound"
    local routingMarker="${root}/routing"
    local removeMarker="${root}/remove"
    local uninstallMarker="${root}/uninstall"
    local reloadMarker="${root}/reload"
    local mode=success
    local menuChoice=2
    local rc reloadCalls=0

    mkdir -p "${root}/xray"
    configPath="${root}/xray/"
    singBoxConfigPath=
    coreInstallType=1

    errorCard() { return 0; }
    warnCard() { return 0; }
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
        printf 'new-outbound\n' >"${configPath}$1.json"
        [[ "${mode}" != "outbound-fail" ]]
    }
    addXrayRouting() {
        printf 'routing\n' >"${routingMarker}"
        printf 'new-routing\n' >"${configPath}09_routing.json"
        [[ "${mode}" != "routing-fail" ]]
    }
    removeXrayOutbound() {
        printf 'remove:%s\n' "$1" >>"${removeMarker}"
        return 0
    }
    unInstallRouting() {
        printf 'uninstall\n' >"${uninstallMarker}"
        printf 'new-routing\n' >"${configPath}09_routing.json"
        [[ "${mode}" != "uninstall-fail" ]]
    }
    reloadCore() {
        reloadCalls=$((reloadCalls + 1))
        printf 'reload\n' >>"${reloadMarker}"
        [[ "${mode}" != "reload-fail" || "${reloadCalls}" -gt 1 ]]
    }

    hasIPv6Connectivity() { return 1; }
    rm -f "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}"
    set +e
    ipv6Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -e "${reloadMarker}" ]]

    hasIPv6Connectivity() { return 0; }
    mode=empty-domain
    menuChoice=2
    rm -f "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}"
    set +e
    ipv6Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -e "${outboundMarker}" ]]
    [[ ! -e "${routingMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]

    mode=routing-fail
    rm -f "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}"
    reloadCalls=0
    set +e
    ipv6Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${outboundMarker}" ]]
    [[ -e "${routingMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]
    [[ ! -e "${configPath}IPv6_out.json" ]]
    [[ ! -e "${configPath}09_routing.json" ]]

    mode=reload-fail
    rm -f "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}"
    reloadCalls=0
    set +e
    ipv6Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${reloadMarker}" ]]
    [[ "${reloadCalls}" == "2" ]]
    [[ ! -e "${configPath}IPv6_out.json" ]]
    [[ ! -e "${configPath}09_routing.json" ]]

    mode=outbound-fail
    menuChoice=3
    rm -f "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}"
    reloadCalls=0
    set +e
    ipv6Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${outboundMarker}" ]]
    [[ ! -e "${removeMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]
    [[ ! -e "${configPath}IPv6_out.json" ]]

    mode=uninstall-fail
    menuChoice=4
    rm -f "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}"
    reloadCalls=0
    set +e
    ipv6Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${uninstallMarker}" ]]
    [[ ! -e "${removeMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]
    [[ ! -e "${configPath}09_routing.json" ]]

    mode=reload-fail
    rm -f "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}"
    reloadCalls=0
    set +e
    ipv6Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${uninstallMarker}" ]]
    [[ -e "${removeMarker}" ]]
    [[ -e "${outboundMarker}" ]]
    [[ -e "${reloadMarker}" ]]
    [[ "${reloadCalls}" == "2" ]]
    [[ ! -e "${configPath}09_routing.json" ]]
    [[ ! -e "${configPath}z_direct_outbound.json" ]]
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
    local returnMarker="${root}/return"
    local mode=success
    local menuChoice=2
    local rc reloadCalls=0

    mkdir -p "${root}/xray" "${root}/warp"
    configPath="${root}/xray/"
    singBoxConfigPath=
    PADM_WARP_DIR="${root}/warp"
    coreInstallType=1

    errorCard() { return 0; }
    warnCard() { return 0; }
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
        printf 'new-outbound\n' >"${configPath}$1.json"
        [[ "${mode}" != "outbound-fail" ]]
    }
    addXrayRouting() {
        printf 'routing\n' >"${routingMarker}"
        printf 'new-routing\n' >"${configPath}09_routing.json"
        [[ "${mode}" != "routing-fail" ]]
    }
    removeXrayOutbound() {
        printf 'remove:%s\n' "$1" >>"${removeMarker}"
        return 0
    }
    unInstallRouting() {
        printf 'uninstall\n' >"${uninstallMarker}"
        printf 'new-routing\n' >"${configPath}09_routing.json"
        [[ "${mode}" != "uninstall-fail" ]]
    }
    unInstallWireGuard() {
        rm -f "${PADM_WARP_DIR}/config"
        return 0
    }
    warpRoutingMenu() {
        printf 'return\n' >"${returnMarker}"
    }
    reloadCore() {
        reloadCalls=$((reloadCalls + 1))
        printf 'reload\n' >>"${reloadMarker}"
        [[ "${mode}" != "reload-fail" || "${reloadCalls}" -gt 1 ]]
    }

    mode=install-fail
    rm -f "${installMarker}" "${readMarker}" "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}"
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
    rm -f "${installMarker}" "${readMarker}" "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}"
    set +e
    warpRoutingReg 1 IPv4 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -e "${installMarker}" ]]
    [[ ! -e "${readMarker}" ]]
    [[ ! -e "${outboundMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]

    mode=routing-fail
    rm -f "${installMarker}" "${readMarker}" "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}"
    reloadCalls=0
    set +e
    warpRoutingReg 1 IPv4 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${outboundMarker}" ]]
    [[ -e "${routingMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]
    [[ ! -e "${configPath}wireguard_out_IPv4.json" ]]
    [[ ! -e "${configPath}09_routing.json" ]]

    mode=reload-fail
    printf 'old-warp-config\n' >"${PADM_WARP_DIR}/config"
    rm -f "${installMarker}" "${readMarker}" "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}"
    reloadCalls=0
    set +e
    warpRoutingReg 1 IPv4 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${reloadMarker}" ]]
    [[ "${reloadCalls}" == "2" ]]
    [[ ! -e "${configPath}wireguard_out_IPv4.json" ]]
    [[ ! -e "${configPath}09_routing.json" ]]

    mode=outbound-fail
    menuChoice=3
    rm -f "${installMarker}" "${readMarker}" "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}"
    reloadCalls=0
    set +e
    warpRoutingReg 1 IPv4 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${outboundMarker}" ]]
    [[ ! -e "${removeMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]
    [[ ! -e "${configPath}wireguard_out_IPv4.json" ]]

    mode=uninstall-fail
    menuChoice=4
    rm -f "${installMarker}" "${readMarker}" "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}"
    reloadCalls=0
    set +e
    warpRoutingReg 1 IPv4 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${uninstallMarker}" ]]
    [[ ! -e "${removeMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]
    [[ ! -e "${configPath}09_routing.json" ]]

    mode=reload-fail
    rm -f "${installMarker}" "${readMarker}" "${outboundMarker}" "${routingMarker}" "${removeMarker}" "${uninstallMarker}" "${reloadMarker}"
    reloadCalls=0
    set +e
    warpRoutingReg 1 IPv4 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${uninstallMarker}" ]]
    [[ -e "${removeMarker}" ]]
    [[ -e "${outboundMarker}" ]]
    [[ -e "${reloadMarker}" ]]
    [[ "${reloadCalls}" == "2" ]]
    [[ ! -e "${configPath}09_routing.json" ]]
    [[ ! -e "${configPath}IPv4_out.json" ]]
    [[ "$(<"${PADM_WARP_DIR}/config")" == "old-warp-config" ]]

    mode=success
    menuChoice=5
    rm -f "${installMarker}" "${readMarker}" "${reloadMarker}" "${returnMarker}"
    warpRoutingReg 1 IPv4 >/dev/null 2>&1
    [[ -e "${returnMarker}" ]]
    [[ ! -e "${installMarker}" ]]
    [[ ! -e "${readMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]
)

runSocks5RoutingFailureReturnRegression() (
    local root="${TMP_DIR}/socks5-routing-failure"
    local outboundMarker="${root}/outbound"
    local routingMarker="${root}/routing"
    local uninstallMarker="${root}/uninstall"
    local removeMarker="${root}/remove"
    local reloadMarker="${root}/reload"
    local stopMarker="${root}/stop"
    local singBoxPathMarker="${root}/sing-box-path"
    local statusLog="${root}/status.log"
    local inboundChoice=1
    local menuChoice=1
    local uninstallChoice=1
    local mode=invalid-port
    local rc

    mkdir -p "${root}/xray" "${root}/sing-box"
    configPath="${root}/xray/"
    singBoxConfigPath=
    coreInstallType=1
    eval "$(declare -f addXrayOutbound | sed '1s/^addXrayOutbound/originalAddXrayOutbound/')"

    errorCard() { return 0; }
    warnCard() { return 0; }
    autoConfirm() {
        printf -v "$4" 'y'
        return 0
    }
    autoRead() {
        case "$1" in
        socks5_inbound_menu) printf -v "$3" "${inboundChoice}" ;;
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
        socks5_outbound_username)
            if [[ "${mode}" == "escaped-credentials" ]]; then
                printf -v "$3" '%s' 'us"er\name'
            else
                printf -v "$3" 'user'
            fi
            ;;
        socks5_outbound_password)
            if [[ "${mode}" == "escaped-credentials" ]]; then
                printf -v "$3" '%s' 'pa"ss\word'
            else
                printf -v "$3" 'pass'
            fi
            ;;
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
        printf 'reload\n' >>"${reloadMarker}"
        [[ "${mode}" != "reload-fail" ]]
    }
    handleSingBox() {
        printf 'stop\n' >"${stopMarker}"
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE:-}" == "true" ]] && [[ "${mode}" != "stop-fail" ]]
    }

    mode=invalid-port
    rm -f "${outboundMarker}" "${routingMarker}" "${uninstallMarker}" "${removeMarker}" "${reloadMarker}"
    set +e
    setSocks5Outbound >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -e "${outboundMarker}" ]]

    mode=outbound-fail
    rm -f "${outboundMarker}" "${routingMarker}" "${uninstallMarker}" "${removeMarker}" "${reloadMarker}"
    set +e
    setSocks5Outbound >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${outboundMarker}" ]]

    mode=escaped-credentials
    singBoxConfigPath="${root}/sing-box/"
    addXrayOutbound() { originalAddXrayOutbound "$@"; }
    if ! setSocks5Outbound >"${statusLog}" 2>&1; then
        cat "${statusLog}" >&2
        return 1
    fi
    jq -e --arg username 'us"er\name' --arg password 'pa"ss\word' '
      .outbounds[0].username == $username and .outbounds[0].password == $password
    ' "${singBoxConfigPath}socks5_outbound.json" >/dev/null
    jq -e --arg username 'us"er\name' --arg password 'pa"ss\word' '
      .outbounds[0].settings.servers[0].users[0].user == $username and
      .outbounds[0].settings.servers[0].users[0].pass == $password
    ' "${configPath}socks5_outbound.json" >/dev/null

    echoContent() { printf '%s\n' "$*" >>"${statusLog}"; }
    menuLine() { printf '%s\n' "$*" >>"${statusLog}"; }
    printf '{"routing":{"rules":[{"type":"field","outboundTag":"z_direct_outbound"}]}}\n' >"${configPath}09_routing.json"
    : >"${statusLog}"
    showXrayRoutingRules socks5_outbound
    [[ ! -s "${statusLog}" ]]
    printf '{"routing":{"rules":[{"type":"field","outboundTag":"socks5_outbound"}]}}\n' >"${configPath}09_routing.json"
    showXrayRoutingRules socks5_outbound >/dev/null
    grep -q '已安装 xray-core socks5出站分流' "${statusLog}"

    rm -f "${singBoxConfigPath}socks5_02_inbound_route.json"
    writeSocks5InboundConfig "${singBoxConfigPath}20_socks5_inbounds.json" 1081 'inbound-secret'
    : >"${statusLog}"
    showSingBoxRoutingRules socks5_02_inbound_route
    grep -q 'inbound-secret' "${statusLog}"
    singBoxConfigPath=
    addXrayOutbound() {
        printf 'outbound:%s\n' "$1" >>"${outboundMarker}"
        [[ "${mode}" != "outbound-fail" ]]
    }

    mode=uninstall-fail
    rm -f "${outboundMarker}" "${routingMarker}" "${uninstallMarker}" "${removeMarker}" "${reloadMarker}"
    set +e
    setSocks5OutboundRouting >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${uninstallMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]

    setSocks5Outbound() {
        printf 'outbound-config\n' >"${outboundMarker}"
        printf 'new-outbound\n' >"${configPath}socks5_outbound.json"
        return 0
    }
    setSocks5OutboundRouting() {
        printf 'routing\n' >"${routingMarker}"
        printf 'new-routing\n' >"${configPath}09_routing.json"
        return 0
    }

    mode=reload-fail
    menuChoice=1
    rm -f "${outboundMarker}" "${routingMarker}" "${uninstallMarker}" "${removeMarker}" "${reloadMarker}"
    printf 'old-outbound\n' >"${configPath}socks5_outbound.json"
    printf 'old-routing\n' >"${configPath}09_routing.json"
    set +e
    socks5OutboundRoutingMenu >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${outboundMarker}" ]]
    [[ -e "${routingMarker}" ]]
    [[ -e "${reloadMarker}" ]]
    [[ "$(<"${configPath}socks5_outbound.json")" == "old-outbound" ]]
    [[ "$(<"${configPath}09_routing.json")" == "old-routing" ]]
    [[ "$(wc -l <"${reloadMarker}")" == "2" ]]

    mode=stop-fail
    uninstallChoice=2
    rm -f "${outboundMarker}" "${routingMarker}" "${uninstallMarker}" "${removeMarker}" "${reloadMarker}" "${stopMarker}"
    set +e
    removeSocks5Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${stopMarker}" ]]
    [[ -e "${reloadMarker}" ]]

    mode=uninstall-fail
    uninstallChoice=1
    rm -f "${outboundMarker}" "${routingMarker}" "${uninstallMarker}" "${removeMarker}" "${reloadMarker}"
    set +e
    removeSocks5Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${uninstallMarker}" ]]
    [[ ! -e "${removeMarker}" ]]
    [[ ! -e "${reloadMarker}" ]]

    mode=reload-fail
    rm -f "${outboundMarker}" "${routingMarker}" "${uninstallMarker}" "${removeMarker}" "${reloadMarker}"
    set +e
    removeSocks5Routing >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${uninstallMarker}" ]]
    [[ -e "${removeMarker}" ]]
    [[ -e "${outboundMarker}" ]]
    [[ -e "${reloadMarker}" ]]
    [[ "$(wc -l <"${reloadMarker}")" == "2" ]]

    readInstallType() {
        coreInstallType=1
        configPath="${root}/xray/"
        singBoxConfigPath=
    }
    installSingBox() { return 0; }
    installSingBoxService() { return 0; }
    socks5RoutingBackupCreate() {
        printf '%s\n' "${singBoxConfigPath}" >"${singBoxPathMarker}"
        return 1
    }
    set +e
    socks5InboundRoutingMenu >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${singBoxPathMarker}")" == "/etc/padm/sing-box/conf/config/" ]]

    local inboundRoot="${root}/inbound-firewall"
    local inboundFirewallState="${inboundRoot}/firewall.state"
    local inboundFirewallLog="${inboundRoot}/firewall.log"
    mkdir -p "${inboundRoot}/sing-box"
    : >"${inboundFirewallLog}"
    PADM_FIREWALL_STATE_FILE="${inboundFirewallState}"
    inboundChoice=1
    singBoxSocks5Port=
    readInstallType() {
        coreInstallType=2
        singBoxConfigPath="${inboundRoot}/sing-box/"
    }
    installSingBox() { return 0; }
    socks5RoutingBackupCreate() {
        local resultVar=$1
        local path="${inboundRoot}/backup"
        mkdir -p "${path}"
        printf -v "${resultVar}" '%s' "${path}"
    }
    socks5RoutingRollback() {
        padmRemoveCleanupPath "$1"
        return 1
    }
    initSingBoxPort() {
        padmFirewallStateAdd "port:ufw:tcp:10891"
        padmFirewallStateAdd "port:ufw:udp:10891"
        printf '10891\n'
    }
    removeFirewallPortRule() {
        printf '%s:%s:%s\n' "$1" "$2" "$3" >>"${inboundFirewallLog}"
        return 0
    }
    autoRead() {
        case "$1" in
        socks5_inbound_menu) printf -v "$3" '1' ;;
        socks5_uninstall_menu) printf -v "$3" "${uninstallChoice}" ;;
        socks5_inbound_uuid) printf -v "$3" 'inbound-user' ;;
        socks5_inbound_ip_type) printf -v "$3" 'invalid' ;;
        *) printf -v "$3" '' ;;
        esac
    }
    set +e
    socks5InboundRoutingMenu >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'ufw:10891:tcp' "${inboundFirewallLog}"
    grep -qx 'ufw:10891:udp' "${inboundFirewallLog}"
    [[ ! -e "${inboundFirewallState}" ]]

    mode=success
    uninstallChoice=2
    writeSocks5InboundConfig "${singBoxConfigPath}20_socks5_inbounds.json" 10891 inbound-user
    padmFirewallStateAdd "port:ufw:tcp:10891"
    padmFirewallStateAdd "port:ufw:udp:10891"
    : >"${inboundFirewallLog}"
    removeSocks5Routing >/dev/null 2>&1
    grep -qx 'ufw:10891:tcp' "${inboundFirewallLog}"
    grep -qx 'ufw:10891:udp' "${inboundFirewallLog}"
    [[ ! -e "${inboundFirewallState}" ]]
    [[ ! -e "${singBoxConfigPath}20_socks5_inbounds.json" ]]
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
        set +e
        addSingBoxDNSConfig "1.1.1.1" "example.com" >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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
        set +e
        setUnlockDNS >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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
        set +e
        setUnlockSNI >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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
        set +e
        setUnlockSNI >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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
        set +e
        removeUnlockDNS >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
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

runDNSRoutingRejectsUnsafeBackupDirRegression() (
    local root="${TMP_DIR}/dns-routing-unsafe-backup"
    local rmLog="${root}/rm.log"
    local rc

    mkdir -p "${root}"
    : >"${rmLog}"
    PADM_DNS_ROUTING_BACKUP_DIR=relative-backup
    configPath="${root}/xray/"
    singBoxConfigPath=
    mkdir -p "${configPath}"

    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    set +e
    dnsRoutingBackupCreate >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -s "${rmLog}" ]]

    set +e
    dnsRoutingBackupCleanup >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -s "${rmLog}" ]]

    mkdir -p "${root}/relative-backup/xray"
    printf 'old\n' >"${root}/relative-backup/xray/11_dns.json"
    (
        cd "${root}"
        set +e
        dnsRoutingBackupRestore >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
    )
    [[ ! -s "${rmLog}" ]]
)

runDNSRoutingRejectsUnsafeConfigDirRegression() (
    local root="${TMP_DIR}/dns-routing-unsafe-config"
    local rmLog="${root}/rm.log"
    local rc

    mkdir -p "${root}"
    : >"${rmLog}"
    configPath="relative-config/"
    singBoxConfigPath=
    PADM_DNS_ROUTING_BACKUP_DIR="${root}/backup"

    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    set +e
    dnsRoutingBackupCreate >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -s "${rmLog}" ]]
    [[ ! -e "${PADM_DNS_ROUTING_BACKUP_DIR}" ]]

    mkdir -p "${PADM_DNS_ROUTING_BACKUP_DIR}/xray"
    printf 'old\n' >"${PADM_DNS_ROUTING_BACKUP_DIR}/xray/11_dns.json"
    set +e
    dnsRoutingBackupRestore >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -s "${rmLog}" ]]
)

runDNSRoutingRestoreKeepsUnmanagedSingBoxFilesRegression() (
    local rootRel="${TMP_DIR}/dns-routing-restore-scope"
    local root
    local backupDir
    local customFile

    mkdir -p "${rootRel}/xray" "${rootRel}/sing-box"
    root=$(cd -- "${rootRel}" && pwd -P)
    backupDir="${root}/backup"
    customFile="${root}/sing-box/custom.json"
    configPath="${root}/xray/"
    singBoxConfigPath="${root}/sing-box/"
    PADM_DNS_ROUTING_BACKUP_DIR="${backupDir}"
    dnsRoutingSafeBackupDir() { printf '%s\n' "${root}/backup"; }
    dnsRoutingSafeXrayConfigDir() { printf '%s\n' "${root}/xray/"; }
    dnsRoutingSafeSingBoxConfigDir() { printf '%s\n' "${root}/sing-box/"; }

    printf '{"dns":{"servers":["old"]}}\n' >"${configPath}11_dns.json"
    printf '{"dns":{"servers":["old-sing"]}}\n' >"${singBoxConfigPath}dns.json"
    printf '{"outbounds":[{"tag":"old-direct"}]}\n' >"${singBoxConfigPath}01_direct_outbound.json"
    printf '{"custom":"keep-before"}\n' >"${customFile}"

    dnsRoutingBackupCreate

    printf '{"dns":{"servers":["new"]}}\n' >"${configPath}11_dns.json"
    printf '{"dns":{"servers":["new-sing"]}}\n' >"${singBoxConfigPath}dns.json"
    printf '{"outbounds":[{"tag":"new-direct"}]}\n' >"${singBoxConfigPath}01_direct_outbound.json"
    printf '{"custom":"keep-after"}\n' >"${customFile}"

    dnsRoutingBackupRestore

    jq -e '.dns.servers == ["old"]' "${configPath}11_dns.json" >/dev/null
    jq -e '.dns.servers == ["old-sing"]' "${singBoxConfigPath}dns.json" >/dev/null
    jq -e '.outbounds[0].tag == "old-direct"' "${singBoxConfigPath}01_direct_outbound.json" >/dev/null
    jq -e '.custom == "keep-after"' "${customFile}" >/dev/null
)

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
    local trojanDirectFile="${configPath}28_trojan_TCP_direct_inbounds.json"
    local shadowsocksFile="${singBoxConfigPath}30_shadowsocks_inbounds.json"
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
    cat >"${trojanDirectFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"password":"uuid-a","email":"alpha-Trojan_TCP_direct"},{"password":"uuid-b","email":"bravo-Trojan_TCP_direct"}]}}]}
JSON
    cat >"${shadowsocksFile}" <<'JSON'
{"inbounds":[{"users":[{"password":"ss-a","name":"alpha-shadowsocks"},{"password":"ss-b","name":"bravo-shadowsocks"}]}]}
JSON

    removeUserFromConfigFiles uuid-a alpha
    jq -e '(.inbounds[0].settings.clients | length == 1) and .inbounds[0].settings.clients[0].id == "uuid-b"' "${xrayFile}" >/dev/null
    jq -e '(.inbounds[0].settings.clients | length == 1) and .inbounds[0].settings.clients[0].password == "uuid-b"' "${trojanGrpcFile}" >/dev/null
    jq -e '(.inbounds[0].settings.clients | length == 1) and .inbounds[0].settings.clients[0].id == "uuid-b"' "${httpUpgradeXrayFile}" >/dev/null
    jq -e '(.inbounds[0].users | length == 1) and .inbounds[0].users[0].uuid == "uuid-b"' "${httpUpgradeSingBoxFile}" >/dev/null
    jq -e '(.inbounds[0].settings.clients | length == 1) and .inbounds[0].settings.clients[0].password == "uuid-b"' "${trojanDirectFile}" >/dev/null
    jq -e '(.inbounds[0].users | length == 1) and .inbounds[0].users[0].password == "ss-b"' "${shadowsocksFile}" >/dev/null

    originalContent=$(<"${xrayFile}")
    if writeUserConfigJq "${xrayFile}" '.inbounds[0].settings.clients = [' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${xrayFile}")" == "${originalContent}" ]]
    [[ ! -e "${xrayFile}.tmp" ]]
}

runPortAndPanelHelperRegression() {
    local -a extraPorts btPanelDomains onePanelDomains

    parsedCorePorts=$(corePortParseList '2053, 2083,2053')
    [[ "${parsedCorePorts}" == $'2053\n2083' ]]
    ! corePortParseList '0,70000,abc' >/dev/null
    writeCoreDokodemoInbound "${configPath}02_dokodemodoor_inbounds_2053.json" 2053 443 tcp dokodemo-door-newPort-2053
    writeCoreDokodemoInbound "${configPath}02_dokodemodoor_inbounds_hysteria_2053.json" 2053 9443 udp dokodemo-door-newPort-hysteria-2053
    writeCoreDokodemoInbound "${configPath}02_dokodemodoor_inbounds_2083_default.json" 2083 443 tcp dokodemo-door-newPort-2083
    mapfile -t extraPorts < <(corePortListExtra)
    [[ "${#extraPorts[@]}" == "2" ]]
    [[ "${extraPorts[0]}" == "1:2053" ]]
    [[ "${extraPorts[1]}" == "2:2083 默认" ]]
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
    mapfile -t btPanelDomains < <(panelCertDomainList "${TMP_DIR}/bt-panel/*/fullchain.pem" 1)
    [[ "${#btPanelDomains[@]}" == "1" ]]
    [[ "${btPanelDomains[0]}" == "1:example.com" ]]
    mapfile -t onePanelDomains < <(panelCertDomainList "${TMP_DIR}/one-panel/*/ssl/fullchain.pem" 2)
    [[ "${#onePanelDomains[@]}" == "1" ]]
    [[ "${onePanelDomains[0]}" == "1:example.org" ]]
    rm -rf "${configPath}"
}

runRuntimeTempDirRegression() (
    local oldTmpDir="${TMPDIR:-}"
    local tmpRoot="${TMP_DIR}/runtime-tmp"
    local targetRoot="${TMP_DIR}/runtime-tempdir-target"
    local crontabPathMarker="${TMP_DIR}/runtime-crontab-path.txt"
    local jsonFile="${targetRoot}/state.json"
    local nestedJsonFile="${targetRoot}/missing/parent/state.json"
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

    : >"${mkdirToolsLog}"
    (
        mkdir() {
            printf 'mkdir:%s\n' "$*" >>"${mkdirToolsLog}"
            return 0
        }
        chmod() {
            printf 'chmod:%s\n' "$*" >>"${mkdirToolsLog}"
            return 0
        }
        mkdirTools
    )
    grep -q -- 'chmod:700 .*subscribe_local' "${mkdirToolsLog}"
    grep -q -- 'chmod:700 .* /etc/padm/xray/conf' "${mkdirToolsLog}"
    grep -q -- 'chmod:700 .* /etc/padm/sing-box/conf' "${mkdirToolsLog}"
    grep -q -- 'chmod:700 .*subscribe_local/default' "${mkdirToolsLog}"
    grep -q -- 'chmod:700 .*subscribe_local/clashMeta' "${mkdirToolsLog}"
    grep -q -- 'chmod:700 .*subscribe_local/sing-box' "${mkdirToolsLog}"

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
    [[ "$(realityScannerOutputPath 123)" == "${tmpRoot}/padm-realitlscanner-123.csv" ]]
    [[ "$(realityScannerOutputPath 123 sample-2)" == "${tmpRoot}/padm-realitlscanner-123-sample-2.csv" ]]
    [[ "$(realityTargetTmpPath padm-reality-target-xray-test.log)" == "${tmpRoot}/padm-reality-target-xray-test.log" ]]
    [[ "$(realityTargetTmpPath padm-reality-target-sing-box-test.log)" == "${tmpRoot}/padm-reality-target-sing-box-test.log" ]]
    [[ "$(realityTargetTmpPath padm-reality-target.XXXXXX)" == "${tmpRoot}/padm-reality-target.XXXXXX" ]]

    printf '{"ok":true}\n' | writeGeneratedJsonFile "${jsonFile}" padm-runtime-json
    jq -e '.ok == true' "${jsonFile}" >/dev/null
    if regressionFindHasMatches "${tmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-runtime-json.*'; then
        return 1
    fi
    printf '{"nested":true}\n' | writeGeneratedJsonFile "${nestedJsonFile}" padm-runtime-json
    jq -e '.nested == true' "${nestedJsonFile}" >/dev/null

    crontab() {
        printf '%s\n' "$1" >"${crontabPathMarker}"
        grep -qxF '15 1 * * * echo ok' "$1"
    }
    installUserCrontabContent $'\n15 1 * * * echo ok\n'
    [[ "$(<"${crontabPathMarker}")" == "${tmpRoot}"/padm-crontab.* ]]
    if regressionFindHasMatches "${tmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-crontab.*'; then
        return 1
    fi

    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runCoreRollbackResultMessageRegression() (
    local message=
    local detailMessage=
    local retryLog="${TMP_DIR}/core-rollback-result.log"

    coreSetRollbackResultMessage message \
        "核心重载失败" \
        "已回滚本次修改"
    [[ "${message}" == "核心重载失败，已回滚本次修改" ]]

    : >"${retryLog}"
    coreRollbackRetrySuccess() {
        printf '%s\n' "$*" >>"${retryLog}"
        return 0
    }
    coreSetRollbackResultMessage message \
        "核心重载失败" \
        "已回滚本次修改" \
        coreRollbackRetrySuccess \
        "恢复旧配置后重载仍失败，请检查核心服务日志" \
        dns
    [[ "${message}" == "核心重载失败，已回滚本次修改" ]]
    grep -q '^dns$' "${retryLog}"

    : >"${retryLog}"
    coreRollbackRetryFail() {
        printf '%s\n' "$*" >>"${retryLog}"
        return 1
    }
    coreSetRollbackResultMessage message \
        "核心重载失败" \
        "已回滚本次修改" \
        coreRollbackRetryFail \
        "恢复旧配置后重载仍失败，请检查核心服务日志" \
        dns
    [[ "${message}" == "核心重载失败，已回滚本次修改；恢复旧配置后重载仍失败，请检查核心服务日志" ]]
    grep -q '^dns$' "${retryLog}"

    coreSetRollbackResultMessage message \
        "刷新 VLESS Encryption 订阅失败" \
        "已恢复旧配置"
    [[ "${message}" == "刷新 VLESS Encryption 订阅失败，已恢复旧配置" ]]

    : >"${retryLog}"
    coreSetRollbackResultMessage message \
        "核心重载失败" \
        "已回滚日志配置修改" \
        coreRollbackRetryFail \
        "恢复旧配置后核心重载仍失败，请检查核心服务日志" \
        log
    [[ "${message}" == "核心重载失败，已回滚日志配置修改；恢复旧配置后核心重载仍失败，请检查核心服务日志" ]]
    grep -q '^log$' "${retryLog}"

    : >"${retryLog}"
    coreSetRollbackResultMessage message \
        "核心重载失败" \
        "已回滚配置" \
        coreRollbackRetrySuccess \
        "恢复旧配置后重载仍失败，请检查核心服务日志" \
        reality
    [[ "${message}" == "核心重载失败，已回滚配置" ]]
    grep -q '^reality$' "${retryLog}"

    set +e
    coreSetSingleRestoreResultMessage message \
        "Fail2ban 服务应用失败" \
        true \
        "已恢复旧配置" \
        "旧配置" \
        "/tmp/fail2ban-backup"
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
    [[ "${message}" == "Fail2ban 服务应用失败，已恢复旧配置" ]]

    set +e
    coreSetSingleRestoreResultMessage message \
        "Fail2ban 服务应用失败" \
        false \
        "已恢复旧配置" \
        "旧配置" \
        "/tmp/fail2ban-backup"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "Fail2ban 服务应用失败，且旧配置恢复失败，请手动检查/tmp/fail2ban-backup" ]]

    coreSetRestoreFailureDetail detailMessage "旧配置" "/tmp/fail2ban-backup"
    [[ "${detailMessage}" == "旧配置恢复失败，请手动检查/tmp/fail2ban-backup" ]]

    set +e
    coreSetSingleRestoreResultMessage message \
        "提交 VLESS Encryption 状态失败" \
        true \
        "已恢复旧配置" \
        "旧配置" \
        "/tmp/vless-state-backup"
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
    [[ "${message}" == "提交 VLESS Encryption 状态失败，已恢复旧配置" ]]

    set +e
    coreSetSingleRestoreResultMessage message \
        "写入日志配置失败" \
        false \
        "已恢复旧配置" \
        "旧配置" \
        "备份目录: /tmp/check-log-backup"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "写入日志配置失败，且旧配置恢复失败，请手动检查备份目录: /tmp/check-log-backup" ]]

    set +e
    coreSetSingleRestoreResultMessage message \
        "Xray 配置校验失败" \
        false \
        "已恢复旧配置" \
        "旧配置" \
        " /tmp/xray-fallback.json 和 /tmp/xray-fallback.json.alpn.bak"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "Xray 配置校验失败，且旧配置恢复失败，请手动检查 /tmp/xray-fallback.json 和 /tmp/xray-fallback.json.alpn.bak" ]]

    set +e
    coreSetSingleRestoreResultMessage message \
        "sing-box 日志配置重载失败" \
        false \
        "已恢复旧配置" \
        "旧配置" \
        " /tmp/log.json，备份文件：/tmp/log.json.bak"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "sing-box 日志配置重载失败，且旧配置恢复失败，请手动检查 /tmp/log.json，备份文件：/tmp/log.json.bak" ]]

    coreSetRollbackResultMessage message \
        "sing-box 日志配置重载失败" \
        "已回滚日志配置"
    [[ "${message}" == "sing-box 日志配置重载失败，已回滚日志配置" ]]

    coreSetRollbackResultMessage message \
        "写入日志配置失败" \
        "已回滚本次日志修改"
    [[ "${message}" == "写入日志配置失败，已回滚本次日志修改" ]]

    coreSetRollbackFailureMessage message \
        "核心重载失败" \
        "/tmp/core-backup"
    [[ "${message}" == "核心重载失败，且回滚失败，请手动检查备份目录: /tmp/core-backup" ]]

    coreSetRollbackFailureMessage message \
        "入口端口配置回滚失败" \
        "/tmp/core-port-backup" \
        ""
    [[ "${message}" == "入口端口配置回滚失败，请手动检查备份目录: /tmp/core-port-backup" ]]

    coreSetNewConfigCleanupFailureMessage message \
        "sing-box 日志配置重载失败" \
        "/tmp/log.json"
    [[ "${message}" == "sing-box 日志配置重载失败，且新配置清理失败，请手动检查 /tmp/log.json" ]]

    set +e
    coreSetDualRestoreResultMessage message \
        "写入 Xray 配置失败" \
        false \
        "VLESS Encryption 配置" \
        " /tmp/config.json 和 /tmp/config.json.bak" \
        true \
        "VLESS Encryption 状态" \
        " /tmp/state.json 和 /tmp/state.json.bak"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "写入 Xray 配置失败，且VLESS Encryption 配置恢复失败，请手动检查 /tmp/config.json 和 /tmp/config.json.bak" ]]

    coreSetRestoreFailureDetail detailMessage "VLESS Encryption 配置" " /tmp/config.json 和 /tmp/config.json.bak"
    [[ "${detailMessage}" == "VLESS Encryption 配置恢复失败，请手动检查 /tmp/config.json 和 /tmp/config.json.bak" ]]

    coreSetManualCheckMessage detailMessage "VLESS Encryption 配置恢复失败" " /tmp/config.json 和 /tmp/config.json.bak"
    [[ "${detailMessage}" == "VLESS Encryption 配置恢复失败，请手动检查 /tmp/config.json 和 /tmp/config.json.bak" ]]

    set +e
    coreSetDualRestoreResultMessage message \
        "删除 VLESS Encryption 状态失败" \
        true \
        "VLESS Encryption 配置" \
        " /tmp/config.json 和 /tmp/config.json.bak" \
        false \
        "VLESS Encryption 状态" \
        " /tmp/state.json 和 /tmp/state.json.bak"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "删除 VLESS Encryption 状态失败，且VLESS Encryption 状态恢复失败，请手动检查 /tmp/state.json 和 /tmp/state.json.bak" ]]

    coreSetPairedFileRestoreFailureMessage message \
        "新版入口执行失败" \
        "旧入口" \
        "/tmp/install.sh" \
        "/tmp/install.sh.bak"
    [[ "${message}" == "新版入口执行失败，旧入口恢复失败，请手动检查 /tmp/install.sh 和 /tmp/install.sh.bak" ]]

    coreSetPairedFileManualCheckMessage message \
        "核心重载失败，且回滚配置失败" \
        "/tmp/config.json" \
        "/tmp/config.json.bak"
    [[ "${message}" == "核心重载失败，且回滚配置失败，请手动检查 /tmp/config.json 和 /tmp/config.json.bak" ]]

    coreSetManualCheckMessage detailMessage "核心重载失败，且回滚配置失败" " /tmp/config.json 和 /tmp/config.json.bak"
    [[ "${detailMessage}" == "核心重载失败，且回滚配置失败，请手动检查 /tmp/config.json 和 /tmp/config.json.bak" ]]

    coreSetManualCheckMessage detailMessage "Nginx 配置目标异常" " /tmp/alone.conf"
    [[ "${detailMessage}" == "Nginx 配置目标异常，请手动检查 /tmp/alone.conf" ]]

    coreSetManualCheckMessage detailMessage "端口检测 Nginx 配置备份清理失败" " /tmp/check-port-open.conf.bak"
    [[ "${detailMessage}" == "端口检测 Nginx 配置备份清理失败，请手动检查 /tmp/check-port-open.conf.bak" ]]

    subscriptionSyncSetManualCheckMessage detailMessage "订阅配置恢复失败" " /tmp/subscribe.json"
    [[ "${detailMessage}" == "订阅配置恢复失败，请手动检查 /tmp/subscribe.json" ]]
)

runCorePortFileTransactionRegression() {
    local oldTmpDir="${TMPDIR:-}"
    local configRoot
    local portTmpRoot="${TMP_DIR}/core-port-tmp"
    mkdir -p "${portTmpRoot}"
    portTmpRoot=$(cd -- "${portTmpRoot}" && pwd -P) || return 1
    TMPDIR="${portTmpRoot}"
    mkdir -p "${configPath}"
    configRoot=$(cd -- "${configPath}" && pwd -P) || return 1
    configPath="${configRoot%/}/"
    corePortApplyFileTransaction() {
        local action=$1
        local backupDir
        padmCreateTmpRootPath backupDir padm-core-port.XXXXXX -d || return 1
        if ! corePortBackupFiles "${backupDir}"; then
            corePortReportBackupFailure "${backupDir}"
            return 1
        fi
        shift
        if ! "${action}" "$@" || ! corePortValidateFiles; then
            if corePortRollbackFiles "${backupDir}"; then
                padmRemoveCleanupPath "${backupDir}"
            else
                corePortReportRollbackFailure "${backupDir}"
            fi
            return 1
        fi
        padmRemoveCleanupPath "${backupDir}"
    }
    corePortApplyReloadTransaction() {
        local action=$1
        local backupDir
        local restoreMessage
        local rollbackMessage
        padmCreateTmpRootPath backupDir padm-core-port.XXXXXX -d || return 1
        if ! corePortBackupFiles "${backupDir}"; then
            corePortReportBackupFailure "${backupDir}"
            return 1
        fi
        shift
        if ! "${action}" "$@" || ! corePortValidateFiles; then
            if corePortRollbackFiles "${backupDir}"; then
                padmRemoveCleanupPath "${backupDir}"
            else
                corePortReportRollbackFailure "${backupDir}"
            fi
            return 1
        fi
        if reloadCore; then
            padmRemoveCleanupPath "${backupDir}"
            return 0
        fi

        if ! corePortRollbackFiles "${backupDir}"; then
            padmForgetCleanupPath "${backupDir}"
            coreSetSingleRestoreResultMessage restoreMessage "入口端口核心重载失败" false "已恢复旧配置" "旧配置" "备份目录: ${backupDir}" || true
            errorCard "${restoreMessage}"
            return 1
        fi
        coreSetRollbackResultMessage rollbackMessage "入口端口核心重载失败" "已恢复旧配置" reloadCore "恢复后核心重载仍失败，请检查核心服务日志"
        errorCard "${rollbackMessage}"
        padmRemoveCleanupPath "${backupDir}"
        return 1
    }
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
    local reloadLog="${TMP_DIR}/core-port-reload-calls.log"
    local helperLog="${TMP_DIR}/core-port-helper.log"
    : >"${errorLog}"
    : >"${helperLog}"
    errorCard() {
        printf '%s\n' "$*" >>"${errorLog}"
    }
    eval "$(declare -f corePortReportBackupFailure | sed '1s/^corePortReportBackupFailure/originalCorePortReportBackupFailure/')"
    corePortReportBackupFailure() {
        printf 'backup\n' >>"${helperLog}"
        originalCorePortReportBackupFailure "$@"
    }
    eval "$(declare -f corePortReportRollbackFailure | sed '1s/^corePortReportRollbackFailure/originalCorePortReportRollbackFailure/')"
    corePortReportRollbackFailure() {
        printf 'rollback\n' >>"${helperLog}"
        originalCorePortReportRollbackFailure "$@"
    }

    : >"${errorLog}"
    (
        cp() {
            local args=("$@")
            local targetPath="${args[$((${#args[@]} - 1))]}"
            if [[ "${targetPath}" == "${portTmpRoot}"/padm-core-port.*/.* ]]; then
                return 1
            fi
            command cp "$@"
        }
        if corePortApplyFileTransaction corePortWriteAddFiles 2443 2443 443 2>/dev/null; then
            return 1
        fi
        [[ "$(<"${configPath}02_dokodemodoor_inbounds_2053_default.json")" == "${original2053}" ]]
        [[ ! -e "${configPath}02_dokodemodoor_inbounds_2443_default.json" ]]
        if regressionFindHasMatches "${portTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-core-port.*'; then
            return 1
        fi
    ) || return 1
    grep -q "入口端口配置备份失败" "${errorLog}"
    [[ "$(grep -c '^backup$' "${helperLog}")" == "1" ]]

    : >"${errorLog}"
    : >"${helperLog}"
    (
        corePortBackupFiles() {
            return 1
        }
        if corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 443 2>/dev/null; then
            return 1
        fi
    ) || return 1
    grep -q "入口端口配置备份失败" "${errorLog}"
    [[ "$(grep -c '^backup$' "${helperLog}")" == "1" ]]

    : >"${errorLog}"
    : >"${helperLog}"
    (
        cp() {
            local args=("$@")
            local targetPath="${args[$((${#args[@]} - 1))]}"
            if [[ "${targetPath}" == "${configPath}".02_dokodemodoor_inbounds_2053_default.json.restore.* ]]; then
                return 1
            fi
            command cp "$@"
        }
        if corePortApplyFileTransaction corePortWriteAddFiles 2443 2443 'bad-port' 2>/dev/null; then
            return 1
        fi
    ) || return 1
    grep -q "入口端口配置回滚失败" "${errorLog}"
    [[ "$(grep -c '^rollback$' "${helperLog}")" == "1" ]]
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
    grep -q "入口端口核心重载失败，已恢复旧配置" "${errorLog}"
    grep -q "恢复后核心重载仍失败" "${errorLog}" && return 1

    reloadCalls=0
    : >"${reloadLog}"
    : >"${errorLog}"
    reloadCore() {
        printf 'reload\n' >>"${reloadLog}"
        reloadCalls=$((reloadCalls + 1))
        [[ "${reloadCalls}" != "1" ]]
    }
    (
        cp() {
            local args=("$@")
            local sourcePath="${args[$((${#args[@]} - 2))]}"
            if [[ "${sourcePath}" == */padm-core-port.*/02_dokodemodoor_inbounds_2053_default.json ]]; then
                return 1
            fi
            command cp "$@"
        }
        if corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 443 2>/dev/null; then
            return 1
        fi
    ) || return 1
    [[ "$(grep -c '^reload$' "${reloadLog}")" == "1" ]]
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
    if regressionFindHasMatches "${portTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-core-port.*'; then
        return 1
    fi

    (
        local firewallLog="${TMP_DIR}/core-port-firewall-lifecycle.log"
        local firewallErrorLog="${TMP_DIR}/core-port-firewall-errors.log"
        local denyShouldFail=false
        local denyTcpShouldFail=false
        local mode=add-fail
        local rc
        : >"${firewallLog}"
        : >"${firewallErrorLog}"
        eval "$(declare -f addCorePort | sed '1s/^addCorePort/originalAddCorePort/')"
        addCorePort() { return 0; }
        autoRead() {
            case "$1" in
            core_port_menu) [[ "${mode}" == "delete" ]] && printf -v "$3" 3 || printf -v "$3" 2 ;;
            extra_core_ports) printf -v "$3" '2555,2666' ;;
            extra_core_default_port) printf -v "$3" 443 ;;
            extra_core_delete_port) printf -v "$3" 1 ;;
            esac
        }
        allowPort() {
            PADM_LAST_ALLOW_PORT_ADDED=true
            printf 'allow:%s:%s\n' "$1" "${2:-tcp}" >>"${firewallLog}"
        }
        denyPort() {
            printf 'deny:%s:%s\n' "$1" "${2:-tcp}" >>"${firewallLog}"
            [[ "${denyShouldFail}" != "true" && ( "${denyTcpShouldFail}" != "true" || "${2:-tcp}" != "tcp" ) ]]
        }
        errorCard() { printf '%s\n' "$1" >>"${firewallErrorLog}"; }
        corePortListExtra() { return 0; }
        corePortResolveByIndex() { printf '2555\n'; }
        corePortApplyReloadTransaction() { [[ "${mode}" == "delete" ]]; }
        coreInstallType=1
        customPort=

        set +e
        originalAddCorePort >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -qx 'deny:2555:tcp' "${firewallLog}"
        grep -qx 'deny:2555:udp' "${firewallLog}"
        grep -qx 'deny:2666:tcp' "${firewallLog}"
        grep -qx 'deny:2666:udp' "${firewallLog}"

        denyShouldFail=true
        : >"${firewallErrorLog}"
        set +e
        originalAddCorePort >/dev/null 2>&1
        rc=$?
        set -e
        denyShouldFail=false
        [[ "${rc}" == "1" ]]
        grep -qx '入口端口防火墙规则回滚失败，请检查防火墙状态' "${firewallErrorLog}"

        mode=delete
        : >"${firewallLog}"
        originalAddCorePort >/dev/null 2>&1
        grep -qx 'deny:2555:tcp' "${firewallLog}"
        grep -qx 'deny:2555:udp' "${firewallLog}"

        denyTcpShouldFail=true
        : >"${firewallLog}"
        set +e
        originalAddCorePort >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -qx 'deny:2555:tcp' "${firewallLog}"
        grep -qx 'deny:2555:udp' "${firewallLog}"
    )

    rm -rf "${configPath}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runCorePortRejectsUnsafeConfigDirRegression() (
    local rootRel="${TMP_DIR}/core-port-unsafe-config"
    local root rmLog cpLog
    local rc

    mkdir -p "${rootRel}/relative-config" "${rootRel}/backup-restore"
    root=$(cd -- "${rootRel}" && pwd -P) || return 1
    rmLog="${root}/rm.log"
    cpLog="${root}/cp.log"
    : >"${rmLog}"
    : >"${cpLog}"
    printf '{"inbounds":[{"port":2053,"settings":{"port":443}}]}\n' >"${root}/relative-config/02_dokodemodoor_inbounds_2053_default.json"
    printf '{"inbounds":[{"port":2443,"settings":{"port":443}}]}\n' >"${root}/backup-restore/02_dokodemodoor_inbounds_2443_default.json"

    cd "${root}"
    configPath="relative-config/"
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }
    cp() {
        printf 'cp:%s\n' "$*" >>"${cpLog}"
        command cp "$@"
    }

    set +e
    writeCoreDokodemoInbound "${configPath}02_dokodemodoor_inbounds_2053.json" 2053 443 tcp dokodemo-door-unsafe >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -e "${root}/relative-config/02_dokodemodoor_inbounds_2053.json" ]]

    set +e
    corePortRemove 2053 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -f "${root}/relative-config/02_dokodemodoor_inbounds_2053_default.json" ]]

    set +e
    corePortBackupFiles "${root}/backup-out" >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -e "${root}/backup-out" ]]

    set +e
    corePortRollbackFiles "${root}/backup-restore" >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -f "${root}/relative-config/02_dokodemodoor_inbounds_2053_default.json" ]]
    [[ ! -e "${root}/relative-config/02_dokodemodoor_inbounds_2443_default.json" ]]
    [[ ! -s "${rmLog}" ]]
    [[ ! -s "${cpLog}" ]]
)

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
    corePortIsValid 08
    ! corePortIsValid 999999999999999999999
    subscriptionGroupSyncIntervalValid 08
    ! subscriptionGroupSyncIntervalValid 999999999999999999999
    validateRealityTarget example.com 08
    ! validateRealityTarget example.com 999999999999999999999

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

    selectCustomInstallType=",1,"
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

    selectCustomInstallType=",2,"
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
)

runCoreTemplateReturnFailureRegression() (
    local root="${TMP_DIR}/core-template-return"
    local xrayRoot="${root}/xray"
    local singBoxRoot="${root}/sing-box"
    local nginxRoot="${root}/nginx"
    local firewallState="${root}/firewall.state"
    local firewallLog="${root}/firewall.log"
    local mode=xray
    local xrayRc singBoxRc
    local stopRc writeCalls=0 serviceLog="${TMP_DIR}/core-template-service.log"
    local singBoxServiceRunning=true

    mkdir -p "${xrayRoot}" "${singBoxRoot}" "${nginxRoot}"
    configPath="${xrayRoot}/"
    singBoxConfigPath="${singBoxRoot}/"
    nginxConfigPath="${nginxRoot}/"
    PADM_FIREWALL_STATE_FILE="${firewallState}"
    : >"${firewallLog}"
    currentUUID=existing-user
    currentClients='[]'
    domain=tls.example.com
    currentHost=tls.example.com
    lastInstallationConfig=true
    selectCustomInstallType=",1,"
    singBoxVLESSVisionPort=10890
    singBoxVLESSWSPort=10891

    xrayTemplateConfigDir() { printf '%s\n' "${xrayRoot}"; }
    singBoxTemplateConfigDir() { printf '%s\n' "${singBoxRoot}"; }
    initXrayClients() { printf '[]\n'; }
    initSingBoxClients() { printf '[]\n'; }
    addXrayOutbound() { [[ "${mode}" != "xray-outbound" ]]; }
    checkDNSIP() { return 0; }
    removeNginxDefaultConf() { return 0; }
    randomPathFunction() { currentPath=template-path; }
    singBoxRunning() { [[ "${singBoxServiceRunning}" == "true" ]]; }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        if [[ "$1" == "stop" ]]; then
            [[ "${mode}" != "stop-fail" ]] || return 1
            singBoxServiceRunning=false
        elif [[ "$1" == "start" ]]; then
            singBoxServiceRunning=true
        fi
    }
    checkPortOpen() { return 0; }
    initSingBoxPort() {
        if [[ "${mode}" == "state-drift" ]]; then
            padmTrackPortAllowTransactionKey "port:ufw:tcp:10890"
        else
            padmFirewallStateAdd "port:ufw:tcp:10890"
            padmFirewallStateAdd "port:ufw:udp:10890"
        fi
        printf '10890\n'
    }
    removeFirewallPortRule() {
        printf '%s:%s:%s\n' "$1" "$2" "$3" >>"${firewallLog}"
        return 0
    }
    writeGeneratedJsonFile() {
        local targetFile=$1
        local mappedTarget=${targetFile}
        shift 2
        writeCalls=$((writeCalls + 1))
        if [[ "${mode}" == "xray" && "${targetFile}" == "/etc/padm/xray/conf/09_routing.json" ]]; then
            return 1
        fi
        if [[ "${mode}" == "sing-box" && "${targetFile}" == "/etc/padm/sing-box/conf/config/03_VLESS_WS_inbounds.json" ]]; then
            return 1
        fi
        case "${targetFile}" in
        /etc/padm/xray/conf/*) mappedTarget="${xrayRoot}/${targetFile##*/}" ;;
        /etc/padm/sing-box/conf/config/*) mappedTarget="${singBoxRoot}/${targetFile##*/}" ;;
        esac
        cat >"${mappedTarget}"
    }

    printf '%s\n' 'old-xray-log' >"${xrayRoot}/00_log.json"
    set +e
    initXrayConfig custom 1 true 2>/dev/null
    xrayRc=$?
    set -e
    [[ "${xrayRc}" != "0" ]]
    [[ "$(<"${xrayRoot}/00_log.json")" == 'old-xray-log' ]]
    [[ ! -e "${xrayRoot}/12_policy.json" ]]
    [[ ! -e "${xrayRoot}/11_dns.json" ]]

    mode=xray-outbound
    set +e
    initXrayConfig custom 1 true 2>/dev/null
    xrayRc=$?
    set -e
    [[ "${xrayRc}" != "0" ]]
    [[ ! -e "${xrayRoot}/09_routing.json" ]]

    mode=stop-fail
    selectCustomInstallType=",27,"
    writeCalls=0
    : >"${serviceLog}"
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    rm -f "${firewallState}"
    : >"${firewallLog}"
    set +e
    initSingBoxConfig custom 1 true 2>/dev/null
    stopRc=$?
    set -e
    [[ "${stopRc}" != "0" ]]
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    [[ "${writeCalls}" == "0" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    grep -qx 'ufw:10890:tcp' "${firewallLog}"
    grep -qx 'ufw:10890:udp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    mode=sing-box
    selectCustomInstallType=",27,21,"
    writeCalls=0
    printf '%s\n' 'old-sing-box-inbound' >"${singBoxRoot}/02_VLESS_TCP_inbounds.json"
    : >"${serviceLog}"
    rm -f "${firewallState}"
    : >"${firewallLog}"
    set +e
    initSingBoxConfig custom 1 true 2>/dev/null
    singBoxRc=$?
    set -e
    [[ "${singBoxRc}" != "0" ]]
    [[ "${writeCalls}" != "0" ]]
    [[ "$(<"${singBoxRoot}/02_VLESS_TCP_inbounds.json")" == 'old-sing-box-inbound' ]]
    [[ ! -e "${singBoxRoot}/03_VLESS_WS_inbounds.json" ]]
    [[ "${singBoxServiceRunning}" == "true" ]]
    grep -qx 'sing-box:start:true' "${serviceLog}"
    grep -qx 'ufw:10890:tcp' "${firewallLog}"
    grep -qx 'ufw:10890:udp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    mode=stop-fail
    writeCalls=0
    padmFirewallStateAdd "port:ufw:tcp:10890"
    : >"${firewallLog}"
    set +e
    initSingBoxConfig custom 1 true 2>/dev/null
    stopRc=$?
    set -e
    [[ "${stopRc}" != "0" ]]
    ! grep -q ':tcp$' "${firewallLog}"
    grep -qx 'ufw:10890:udp' "${firewallLog}"
    padmFirewallStateHas "port:ufw:tcp:10890"
    ! padmFirewallStateHas "port:ufw:udp:10890"
    rm -f "${firewallState}"

    readLastInstallationConfig() { return 0; }
    installTools() { return 0; }
    installSingBox() { return 0; }
    initSingBoxConfig() {
        local result=()
        readSingBoxPortResult result 10890 false
    }
    cleanUp() { return 1; }
    rm -f "${firewallState}"
    : >"${firewallLog}"
    set +e
    installSingBoxReality >/dev/null 2>&1
    stopRc=$?
    set -e
    [[ "${stopRc}" == "1" ]]
    grep -qx 'ufw:10890:tcp' "${firewallLog}"
    grep -qx 'ufw:10890:udp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    mode=state-drift
    padmFirewallStateAdd "port:ufw:tcp:10890"
    : >"${firewallLog}"
    set +e
    installSingBoxReality >/dev/null 2>&1
    stopRc=$?
    set -e
    [[ "${stopRc}" == "1" ]]
    grep -qx 'ufw:10890:tcp' "${firewallLog}"
    ! grep -q ':udp$' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    autoRead() {
        case "$1" in
        core_init_uuid) printf -v "$3" '%s' '11111111-1111-1111-1111-111111111111' ;;
        core_init_username) printf -v "$3" '%s' 'sub_manual' ;;
        *) return 1 ;;
        esac
    }
    collectTLSProfile() { tlsCertDomain=tls.example.com; }
    currentUUID=
    lastInstallationConfig=
    writeCalls=0
    set +e
    initXrayConfigApply custom 1 true 2>/dev/null
    xrayRc=$?
    set -e
    [[ "${xrayRc}" != "0" ]]
    [[ "${writeCalls}" == "0" ]]

    selectCustomInstallType=",27,"
    set +e
    initSingBoxConfigApply custom 1 true 2>/dev/null
    singBoxRc=$?
    set -e
    [[ "${singBoxRc}" != "0" ]]
    [[ "${writeCalls}" == "0" ]]
    currentUUID=existing-user
    lastInstallationConfig=true

    mode=template
    initRealityProfile() { return 0; }
    initXrayRealityPort() { return 0; }
    initRealityKey() { return 1; }
    initRealityMldsa65() { return 0; }
    selectCustomInstallType=",1,"
    set +e
    initXrayConfig custom 1 true 2>/dev/null
    xrayRc=$?
    set -e
    [[ "${xrayRc}" != "0" ]]

    installSniffing() { return 1; }
    selectCustomInstallType=",999,"
    set +e
    initXrayConfig custom 1 true 2>/dev/null
    xrayRc=$?
    set -e
    [[ "${xrayRc}" != "0" ]]

    installSniffing() { return 0; }
    removeSingBoxConfig() { return 1; }
    setSniffRouting() { return 0; }
    mode=cleanup-fail
    selectCustomInstallType=",999,"
    set +e
    padmRunPortAllowTransaction initSingBoxConfigApply custom 1 2>/dev/null
    singBoxRc=$?
    set -e
    [[ "${singBoxRc}" != "0" ]]
)

runCoreTemplateManagedConfigRemovalRegression() (
    local cleanupLog="${TMP_DIR}/core-template-managed-remove.log"

    : >"${cleanupLog}"
    rm() {
        printf 'rm:%s\n' "$*" >>"${cleanupLog}"
        return 0
    }

    removeXrayTemplateConfigFiles 03_VLESS_WS_inbounds.json 07_VLESS_vision_reality_inbounds.json
    grep -qx 'rm:-f -- /etc/padm/xray/conf/03_VLESS_WS_inbounds.json' "${cleanupLog}"
    grep -qx 'rm:-f -- /etc/padm/xray/conf/07_VLESS_vision_reality_inbounds.json' "${cleanupLog}"

    : >"${cleanupLog}"
    removeSingBoxTemplateConfigFiles 11_VMess_HTTPUpgrade_inbounds.json 13_anytls_inbounds.json
    grep -qx 'rm:-f -- /etc/padm/sing-box/conf/config/11_VMess_HTTPUpgrade_inbounds.json' "${cleanupLog}"
    grep -qx 'rm:-f -- /etc/padm/sing-box/conf/config/13_anytls_inbounds.json' "${cleanupLog}"

    : >"${cleanupLog}"
    if removeXrayTemplateConfigFiles ../unsafe.json >/dev/null 2>&1; then
        return 1
    fi
    [[ ! -s "${cleanupLog}" ]]
)

runCoreBinaryInstallCopyFailureRegression() (
    local root="${TMP_DIR}/core-binary-copy-failure"
    local xrayBinary="${root}/xray/xray"
    local singBoxBinary="${root}/sing-box/sing-box"
    local singBoxCronet="${root}/sing-box/libcronet.so"
    local statusLog="${root}/status.log"
    local successLog="${root}/success.log"
    local serviceLog="${root}/service.log"
    local copyFailureLog="${root}/copy-failure.log"
    local xrayRc singBoxRc
    local restoreCopyShouldFail= xrayStartShouldFail= singBoxStartShouldFail=

    mkdir -p "$(dirname "${xrayBinary}")" "$(dirname "${singBoxBinary}")" "${root}/tmp"
    printf 'old-xray\n' >"${xrayBinary}"
    printf 'old-sing-box\n' >"${singBoxBinary}"
    printf 'old-cronet\n' >"${singBoxCronet}"
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

    padmIsSafeAbsolutePath() { return 0; }
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
        if [[ "${1:-}" == "-Z1" ]]; then
            printf 'xray\n'
            return 0
        fi
        if [[ "${1:-}" == "-Z" && "${2:-}" == "-l" ]]; then
            printf '%s\n' '-rwxr-xr-x  3.0 unx 0 b- 0% 2026-01-01 00:00 xray'
            return 0
        fi
        if [[ "${1:-}" == "-p" ]]; then
            printf 'xray\n'
            return 0
        fi
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
        case "${1:-}" in
        -tzf)
            printf 'sing-box-1.2.3-linux-amd64/\nsing-box-1.2.3-linux-amd64/sing-box\nsing-box-1.2.3-linux-amd64/libcronet.so\n'
            return 0
            ;;
        -tvzf)
            printf '%s\n' 'drwxr-xr-x root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/'
            printf '%s\n' '-rwxr-xr-x root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/sing-box'
            printf '%s\n' '-rw-r--r-- root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/libcronet.so'
            return 0
            ;;
        -xOzf)
            printf 'sing-box\ncronet\n'
            return 0
            ;;
        esac
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
        printf 'cronet\n' >"${dest}/sing-box-1.2.3-linux-amd64/libcronet.so"
        chmod 755 "${dest}/sing-box-1.2.3-linux-amd64/sing-box"
        return 0
    }
    cp() {
        local args=("$@")
        local sourcePath="${args[$((${#args[@]} - 2))]}"
        local targetPath="${args[$((${#args[@]} - 1))]}"
        if [[ "${restoreCopyShouldFail}" == "true" && "${sourcePath}" == "${xrayBinary}.bak.restore-fail" &&
            "${targetPath}" == "${root}"/tmp/core.* ]]; then
            printf 'restore-xray\n' >>"${copyFailureLog}"
            return 1
        fi
        if [[ "${targetPath}" == "${root}"/tmp/core.* && "${sourcePath}" == "${root}"/tmp/core.*/xray ]]; then
            printf 'xray\n' >>"${copyFailureLog}"
            return 1
        fi
        if [[ "${targetPath}" == "${root}"/tmp/core.* &&
            "${sourcePath}" == "${root}"/tmp/core.*/sing-box-1.2.3-linux-amd64/libcronet.so ]]; then
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
    coreSetManualCheckMessage() {
        printf "manual-check:%s|%s\n" "$2" "$3" >>"${serviceLog}"
        printf -v "$1" "%s，请手动检查%s" "$2" "$3"
    }
    set +e
    finalizeFailedCoreBinaryInstall "Xray-core" "${xrayBinary}.bak.service-fail" "${xrayBinary}" handleXray "/tmp/xray.log" >/dev/null 2>&1
    xrayRc=$?
    set -e
    xrayStartShouldFail=
    [[ "${xrayRc}" == "1" ]]
    [[ "$(<"${xrayBinary}")" == "old-xray" ]]
    [[ ! -e "${xrayBinary}.bak.service-fail" ]]
    grep -q '旧服务恢复启动失败，请手动检查服务状态' "${statusLog}"
    grep -q 'manual-check:旧服务恢复启动失败|服务状态' "${serviceLog}"
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

runSingBoxCronetRollbackRegression() (
    local root="${TMP_DIR}/sing-box-cronet-rollback"
    local singBoxBinary="${root}/sing-box/sing-box"
    local singBoxCronet="${root}/sing-box/libcronet.so"
    local statusLog="${root}/status.log"
    local successLog="${root}/success.log"
    local serviceLog="${root}/service.log"
    local copyFailureLog="${root}/copy-failure.log"
    local singBoxRc
    local singBoxStartShouldFail=

    mkdir -p "$(dirname "${singBoxBinary}")" "${root}/tmp"
    printf 'old-sing-box\n' >"${singBoxBinary}"
    printf 'old-cronet\n' >"${singBoxCronet}"
    chmod 755 "${singBoxBinary}"

    PADM_SINGBOX_BINARY="${singBoxBinary}"
    singBoxCoreCPUVendor=-linux-amd64
    REGRESSION_STATUS_CARD_LOG="${statusLog}"
    REGRESSION_SUCCESS_CARD_LOG="${successLog}"
    : >"${statusLog}"
    : >"${successLog}"
    : >"${serviceLog}"
    : >"${copyFailureLog}"

    padmIsSafeAbsolutePath() { return 0; }
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
    padmRemoveCleanupPath() { rm -rf "$1"; }
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
        printf 'cronet\n' >"${dest}/sing-box-1.2.3-linux-amd64/libcronet.so"
        chmod 755 "${dest}/sing-box-1.2.3-linux-amd64/sing-box"
        return 0
    }
    cp() {
        local args=("$@")
        local sourcePath="${args[$((${#args[@]} - 2))]}"
        local targetPath="${args[$((${#args[@]} - 1))]}"
        if [[ "${targetPath}" == "${root}"/tmp/core.* &&
            "${sourcePath}" == "${root}"/tmp/core.*/sing-box-1.2.3-linux-amd64/libcronet.so ]]; then
            printf 'cronet-copy-fail\n' >>"${copyFailureLog}"
            return 1
        fi
        command cp "$@"
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "$1" == "start" ]] && printf 'cronet-at-start:%s\n' "$(<"${singBoxCronet}")" >>"${serviceLog}"
        [[ "$1" == "start" && "${singBoxStartShouldFail}" == "true" ]] && return 1
        return 0
    }
    singBoxRunning() { return 1; }
    validateSingBoxConfigWithBinary() { return 0; }

    SERVICE_QUEUE_ALLOW_FAILURE=
    set +e
    installDownloadedSingBoxBinary v1.2.3 >/dev/null 2>&1
    singBoxRc=$?
    set -e

    [[ "${singBoxRc}" == "1" ]]
    [[ "$(<"${singBoxBinary}")" == "old-sing-box" ]]
    [[ "$(<"${singBoxCronet}")" == "old-cronet" ]]
    grep -qx 'cronet-copy-fail' "${copyFailureLog}"
    grep -q 'sing-box 更新失败' "${statusLog}"
    grep -q '旧服务已尝试恢复启动' "${statusLog}"
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    grep -qx 'sing-box:start:true' "${serviceLog}"
    grep -qx 'cronet-at-start:old-cronet' "${serviceLog}"
    [[ -z "${SERVICE_QUEUE_ALLOW_FAILURE}" ]]

    : >"${statusLog}"
    : >"${serviceLog}"
    printf 'new-sing-box\n' >"${singBoxBinary}"
    printf 'old-sing-box\n' >"${singBoxBinary}.bak.service-fail"
    printf 'new-cronet\n' >"${singBoxCronet}"
    printf 'old-cronet\n' >"${singBoxCronet}.bak.service-fail"
    singBoxStartShouldFail=true
    set +e
    finalizeFailedSingBoxBinaryInstall "${singBoxBinary}.bak.service-fail" "${singBoxBinary}" "${singBoxCronet}.bak.service-fail" "${singBoxCronet}" "/tmp/sing-box.log" >/dev/null 2>&1
    singBoxRc=$?
    set -e
    singBoxStartShouldFail=
    [[ "${singBoxRc}" == "1" ]]
    [[ "$(<"${singBoxBinary}")" == "old-sing-box" ]]
    [[ "$(<"${singBoxCronet}")" == "old-cronet" ]]
    [[ ! -e "${singBoxBinary}.bak.service-fail" ]]
    [[ ! -e "${singBoxCronet}.bak.service-fail" ]]
    grep -q '旧服务恢复启动失败，请手动检查服务状态' "${statusLog}"
    grep -qx 'sing-box:start:true' "${serviceLog}"
)

runFinalizeSingBoxBinaryInstallRollbackRegression() (
    local root="${TMP_DIR}/finalize-sing-box-rollback"
    local singBoxBinary="${root}/sing-box/sing-box"
    local singBoxCronet="${root}/sing-box/libcronet.so"
    local statusLog="${root}/status.log"
    local serviceLog="${root}/service.log"
    local singBoxRc
    local singBoxStartShouldFail=

    mkdir -p "$(dirname "${singBoxBinary}")"
    : >"${statusLog}"
    : >"${serviceLog}"
    printf 'new-sing-box\n' >"${singBoxBinary}"
    printf 'old-sing-box\n' >"${singBoxBinary}.bak"
    printf 'new-cronet\n' >"${singBoxCronet}"
    printf 'old-cronet\n' >"${singBoxCronet}.bak"
    chmod 755 "${singBoxBinary}" "${singBoxBinary}.bak"

    REGRESSION_STATUS_CARD_LOG="${statusLog}"
    padmIsSafeAbsolutePath() { return 0; }
    coreSetManualCheckMessage() {
        printf "manual-check:%s|%s\n" "$2" "$3" >>"${serviceLog}"
        printf -v "$1" "%s，请手动检查%s" "$2" "$3"
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "$1" == "start" ]] && printf 'cronet-at-start:%s\n' "$(<"${singBoxCronet}")" >>"${serviceLog}"
        [[ "$1" == "start" && "${singBoxStartShouldFail}" == "true" ]] && return 1
        return 0
    }

    singBoxStartShouldFail=true
    set +e
    finalizeFailedSingBoxBinaryInstall "${singBoxBinary}.bak" "${singBoxBinary}" "${singBoxCronet}.bak" "${singBoxCronet}" "/tmp/sing-box.log" >/dev/null 2>&1
    singBoxRc=$?
    set -e
    singBoxStartShouldFail=

    [[ "${singBoxRc}" == "1" ]]
    [[ "$(<"${singBoxBinary}")" == "old-sing-box" ]]
    [[ "$(<"${singBoxCronet}")" == "old-cronet" ]]
    [[ ! -e "${singBoxBinary}.bak" ]]
    [[ ! -e "${singBoxCronet}.bak" ]]
    grep -q '旧服务恢复启动失败，请手动检查服务状态' "${statusLog}"
    grep -q 'manual-check:旧服务恢复启动失败|服务状态' "${serviceLog}"
    grep -qx 'sing-box:start:true' "${serviceLog}"
    grep -qx 'cronet-at-start:old-cronet' "${serviceLog}"

    : >"${statusLog}"
    : >"${serviceLog}"
    rm -f "${singBoxCronet}.bak"
    rm -f "${singBoxCronet}"
    mkdir -p "${singBoxCronet}"
    set +e
    finalizeFailedSingBoxBinaryInstall "${singBoxBinary}.bak" "${singBoxBinary}" "${singBoxCronet}.bak" "${singBoxCronet}" "/tmp/sing-box.log" >/dev/null 2>&1
    singBoxRc=$?
    set -e

    [[ "${singBoxRc}" == "1" ]]
    [[ -d "${singBoxCronet}" ]]
    grep -q "manual-check:libcronet.so 恢复失败| ${singBoxCronet}" "${serviceLog}"
    grep -q "libcronet.so 恢复失败，请手动检查 ${singBoxCronet}" "${statusLog}"
    ! grep -qx 'sing-box:start:true' "${serviceLog}"
)

runCoreUpgradeRejectsDirectoryTargetRegression() (
    local root="${TMP_DIR}/core-upgrade-directory-target"
    local xrayBinary="${root}/xray/xray"
    local singBoxBinary="${root}/sing-box/sing-box"
    local errorLog="${root}/error.log"
    local serviceLog="${root}/service.log"
    local xrayRc singBoxRc

    mkdir -p "${xrayBinary}" "${singBoxBinary}" "${root}/tmp"

    PADM_XRAY_BINARY="${xrayBinary}"
    PADM_SINGBOX_BINARY="${singBoxBinary}"
    xrayCoreCPUVendor=linux-64
    singBoxCoreCPUVendor=-linux-amd64

    : >"${errorLog}"
    : >"${serviceLog}"

    padmIsSafeAbsolutePath() { return 0; }
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
    padmRemoveCleanupPath() { rm -rf "$1"; }
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
        if [[ "${1:-}" == "-Z1" ]]; then
            printf 'xray\n'
            return 0
        fi
        if [[ "${1:-}" == "-Z" && "${2:-}" == "-l" ]]; then
            printf '%s\n' '-rwxr-xr-x  3.0 unx 0 b- 0% 2026-01-01 00:00 xray'
            return 0
        fi
        if [[ "${1:-}" == "-p" ]]; then
            printf 'xray\n'
            return 0
        fi
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
        case "${1:-}" in
        -tzf)
            printf 'sing-box-1.2.3-linux-amd64/\nsing-box-1.2.3-linux-amd64/sing-box\nsing-box-1.2.3-linux-amd64/libcronet.so\n'
            return 0
            ;;
        -tvzf)
            printf '%s\n' 'drwxr-xr-x root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/'
            printf '%s\n' '-rwxr-xr-x root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/sing-box'
            printf '%s\n' '-rw-r--r-- root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/libcronet.so'
            return 0
            ;;
        -xOzf)
            printf 'sing-box\ncronet\n'
            return 0
            ;;
        esac
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
        printf 'cronet\n' >"${dest}/sing-box-1.2.3-linux-amd64/libcronet.so"
        chmod 755 "${dest}/sing-box-1.2.3-linux-amd64/sing-box"
    }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        return 0
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        return 0
    }
    xrayRunning() { return 1; }
    singBoxRunning() { return 1; }
    validateXrayConfigWithBinary() { return 0; }
    validateSingBoxConfigWithBinary() { return 0; }
    coreSetManualCheckMessage() {
        printf "manual-check:%s|%s\n" "$2" "$3" >>"${serviceLog}"
        printf -v "$1" "%s，请手动检查%s" "$2" "$3"
    }

    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    set +e
    installDownloadedXrayBinary v1.2.3 >/dev/null 2>&1
    xrayRc=$?
    set -e

    set +e
    installDownloadedSingBoxBinary v1.2.3 >/dev/null 2>&1
    singBoxRc=$?
    set -e

    [[ "${xrayRc}" == "1" ]]
    [[ "${singBoxRc}" == "1" ]]
    [[ -d "${xrayBinary}" ]]
    [[ -d "${singBoxBinary}" ]]
    [[ ! -e "${xrayBinary}/xray" ]]
    [[ ! -e "${singBoxBinary}/sing-box" ]]
    [[ ! -e "${singBoxBinary}/libcronet.so" ]]
    grep -q "manual-check:Xray-core安装目标异常| ${xrayBinary}" "${serviceLog}"
    grep -q "manual-check:sing-box安装目标异常| ${singBoxBinary}" "${serviceLog}"
    grep -q "Xray-core安装目标异常，请手动检查 ${xrayBinary}" "${errorLog}"
    grep -q "sing-box安装目标异常，请手动检查 ${singBoxBinary}" "${errorLog}"
    ! grep -q '^xray:' "${serviceLog}"
    ! grep -q '^sing-box:' "${serviceLog}"
)

runLegacyCoreUpgradeKeepsExistingBinaryRegression() (
    local root="${TMP_DIR}/legacy-core-upgrade-keeps-existing"
    local xrayBinary="${root}/xray/xray"
    local singBoxBinary="${root}/sing-box/sing-box"
    local callLog="${root}/calls.log"
    local rmLog="${root}/rm.log"

    mkdir -p "$(dirname "${xrayBinary}")" "$(dirname "${singBoxBinary}")"
    cat >"${xrayBinary}" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat >"${singBoxBinary}" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod 755 "${xrayBinary}" "${singBoxBinary}"

    PADM_XRAY_BINARY="${xrayBinary}"
    PADM_SINGBOX_BINARY="${singBoxBinary}"
    : >"${callLog}"
    : >"${rmLog}"

    readInstallType() { return 0; }
    errorCard() { return 0; }
    getSingBoxCurrentVersion() { printf 'vold-sing-box\n'; }
    coreLatestReleaseTag() { printf 'v1.2.3\n'; }
    autoRead() { printf -v "$3" 'y'; }
    ensureXrayGeoFiles() {
        printf 'geo:%s\n' "$*" >>"${callLog}"
        return 0
    }
    installDownloadedXrayBinary() {
        printf 'upgrade-xray:%s\n' "$1" >>"${callLog}"
        return 0
    }
    installDownloadedSingBoxBinary() {
        printf 'upgrade-sing-box:%s\n' "$1" >>"${callLog}"
        return 0
    }
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    installXray 1 false >/dev/null 2>&1
    installSingBox 1 >/dev/null 2>&1

    [[ -x "${xrayBinary}" ]]
    [[ -x "${singBoxBinary}" ]]
    grep -qx "geo:$(dirname "${xrayBinary}")" "${callLog}"
    grep -qx 'upgrade-xray:v1.2.3' "${callLog}"
    grep -qx 'upgrade-sing-box:v1.2.3' "${callLog}"
    ! grep -q -- "${xrayBinary}" "${rmLog}"
    ! grep -q -- "${singBoxBinary}" "${rmLog}"
)

runSingBoxDownloadArtifactsCleanupRegression() (
    local root="${TMP_DIR}/sing-box-artifacts-cleanup"
    local installDir="${root}/install"
    local rmLog="${root}/rm.log"
    local rc

    mkdir -p "${installDir}/sing-box-1.2.3-linux-amd64" "${installDir}/sing-box-keep"
    printf 'archive\n' >"${installDir}/sing-box-1.2.3-linux-amd64.tar.gz"
    printf 'current\n' >"${installDir}/sing-box"
    printf 'keep\n' >"${installDir}/sing-box-keep/sentinel"
    : >"${rmLog}"

    singBoxCoreCPUVendor=-linux-amd64
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    cleanSingBoxDownloadArtifacts "${installDir}" v1.2.3
    [[ ! -e "${installDir}/sing-box-1.2.3-linux-amd64.tar.gz" ]]
    [[ ! -e "${installDir}/sing-box-1.2.3-linux-amd64" ]]
    [[ -f "${installDir}/sing-box" ]]
    [[ -f "${installDir}/sing-box-keep/sentinel" ]]
    grep -qxF "rm:-f -- ${installDir}/sing-box-1.2.3-linux-amd64.tar.gz" "${rmLog}"
    grep -qxF "rm:-rf -- ${installDir}/sing-box-1.2.3-linux-amd64" "${rmLog}"
    ! grep -qF 'sing-box-keep' "${rmLog}"

    set +e
    cleanSingBoxDownloadArtifacts relative-install v1.2.3 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
)

runCoreReleaseArchiveRejectsUnsafePathRegression() (
    local root="${TMP_DIR}/core-release-archive-unsafe-path"
    local tmpDir="${root}/tmp"
    local xrayRc singBoxRc

    rm -rf "${root}"
    mkdir -p "${tmpDir}"
    xrayCoreCPUVendor=Xray-linux-64
    singBoxCoreCPUVendor=-linux-amd64
    downloadGitHubReleaseAsset() {
        local outputDir= assetName=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -P) outputDir=$2; shift 2 ;;
            *) assetName=$1; shift ;;
            esac
        done
        mkdir -p "${outputDir}"
        : >"${outputDir}/${assetName}"
    }
    unzip() {
        if [[ "${1:-}" == "-Z1" ]]; then
            printf '../xray\n'
            return 0
        fi
        if [[ "${1:-}" == "-p" ]]; then
            printf 'xray\n'
            return 0
        fi
        local dest=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -d) dest=$2; shift 2 ;;
            *) shift ;;
            esac
        done
        printf '#!/usr/bin/env bash\nexit 0\n' >"${dest}/xray"
        chmod 755 "${dest}/xray"
    }
    tar() {
        case "$1" in
        -tzf) printf '../sing-box\n'; return 0 ;;
        -tvzf) printf '%s\n' '-rw-r--r-- root/root 0 2026-01-01 00:00 ../sing-box'; return 0 ;;
        -xOzf) printf 'sing-box\n'; return 0 ;;
        esac
        local dest=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -C) dest=$2; shift 2 ;;
            *) shift ;;
            esac
        done
        mkdir -p "${dest}/sing-box-1.2.3-linux-amd64"
        printf '#!/usr/bin/env bash\nexit 0\n' >"${dest}/sing-box-1.2.3-linux-amd64/sing-box"
        printf 'cronet\n' >"${dest}/sing-box-1.2.3-linux-amd64/libcronet.so"
        chmod 755 "${dest}/sing-box-1.2.3-linux-amd64/sing-box"
    }

    set +e
    downloadXrayReleaseBinaryToTempDir v1.2.3 "${tmpDir}/xray"
    xrayRc=$?
    downloadSingBoxReleaseBinaryToTempDir v1.2.3 "${tmpDir}/sing"
    singBoxRc=$?
    set -e

    [[ "${xrayRc}" -ne 0 ]]
    [[ "${singBoxRc}" -ne 0 ]]
)

runCoreReleaseArchiveRejectsSymlinkPayloadRegression() (
    local root="${TMP_DIR}/core-release-archive-symlink-payload"
    local tmpDir="${root}/tmp"
    local xrayRc singBoxRc

    rm -rf "${root}"
    mkdir -p "${tmpDir}"
    xrayCoreCPUVendor=Xray-linux-64
    singBoxCoreCPUVendor=-linux-amd64
    downloadGitHubReleaseAsset() {
        local outputDir= assetName=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -P) outputDir=$2; shift 2 ;;
            *) assetName=$1; shift ;;
            esac
        done
        mkdir -p "${outputDir}"
        : >"${outputDir}/${assetName}"
    }
    unzip() {
        if [[ "${1:-}" == "-Z1" ]]; then
            printf 'xray\n'
            return 0
        fi
        if [[ "${1:-}" == "-Z" && "${2:-}" == "-l" ]]; then
            printf '%s\n' 'lrwxrwxrwx  3.0 unx 0 b- 0% 2026-01-01 00:00 xray'
            return 0
        fi
        if [[ "${1:-}" == "-p" ]]; then
            printf 'xray\n'
            return 0
        fi
        local dest=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -d) dest=$2; shift 2 ;;
            *) shift ;;
            esac
        done
        mkdir -p "${dest}/xray"
    }
    tar() {
        case "$1" in
        -tzf)
            printf 'sing-box-1.2.3-linux-amd64/\nsing-box-1.2.3-linux-amd64/sing-box\nsing-box-1.2.3-linux-amd64/libcronet.so\n'
            return 0
            ;;
        -tvzf)
            printf '%s\n' 'drwxr-xr-x root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/'
            printf '%s\n' '-rwxr-xr-x root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/sing-box'
            printf '%s\n' 'lrwxrwxrwx root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/libcronet.so -> /tmp/libcronet.so'
            return 0
            ;;
        -xOzf)
            printf 'sing-box\ncronet\n'
            return 0
            ;;
        esac
        local dest=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -C) dest=$2; shift 2 ;;
            *) shift ;;
            esac
        done
        mkdir -p "${dest}/sing-box-1.2.3-linux-amd64"
        printf '#!/usr/bin/env bash\nexit 0\n' >"${dest}/sing-box-1.2.3-linux-amd64/sing-box"
        printf 'cronet\n' >"${dest}/sing-box-1.2.3-linux-amd64/libcronet.so"
        chmod 755 "${dest}/sing-box-1.2.3-linux-amd64/sing-box"
    }

    set +e
    downloadXrayReleaseBinaryToTempDir v1.2.3 "${tmpDir}/xray"
    xrayRc=$?
    downloadSingBoxReleaseBinaryToTempDir v1.2.3 "${tmpDir}/sing"
    singBoxRc=$?
    set -e

    [[ "${xrayRc}" -ne 0 ]]
    [[ "${singBoxRc}" -ne 0 ]]
)

runCoreFirstInstallLeavesNoLiveArtifactsOnFailureRegression() (
    local rootRel="${TMP_DIR}/core-first-install-failure"
    local root
    local xrayDir
    local singBoxDir
    local errorLog
    local rmLog
    local callLog
    local xrayRc singBoxRc

    mkdir -p "${rootRel}/tmp" "${rootRel}/sing-box"
    root=$(cd -- "${rootRel}" && pwd -P)
    xrayDir="${root}/xray"
    singBoxDir="${root}/sing-box"
    errorLog="${root}/error.log"
    rmLog="${root}/rm.log"
    callLog="${root}/call.log"
    : >"${errorLog}"
    : >"${rmLog}"
    : >"${callLog}"

    PADM_XRAY_BINARY="${xrayDir}/xray"
    PADM_SINGBOX_BINARY="${singBoxDir}/sing-box"
    xrayCoreCPUVendor=linux-64
    singBoxCoreCPUVendor=-linux-amd64
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    TMPDIR="${root}/tmp"

    readInstallType() { return 0; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    coreLatestReleaseTag() { printf 'v1.2.3\n'; }
    checkVersionNotEmpty() { [[ -n "$1" ]]; }
    ensureXrayGeoFiles() { printf 'geo:%s\n' "$*" >>"${callLog}"; return 0; }
    padmCreateTempPath() {
        local resultVar=$1
        local path
        shift
        printf 'mktemp:%s\n' "$*" >>"${callLog}"
        if [[ "${1:-}" == "-d" ]]; then
            path=$(mktemp -d "${TMPDIR}/core.XXXXXX") || return 1
        else
            path=$(mktemp "${TMPDIR}/core.XXXXXX") || return 1
        fi
        printf -v "${resultVar}" '%s' "${path}"
    }
    padmRemoveCleanupPath() {
        printf 'rm:%s\n' "$1" >>"${rmLog}"
        rm -rf "$1"
    }
    downloadGitHubReleaseAsset() {
        local outputDir= assetName=
        printf 'download:%s\n' "$*" >>"${callLog}"
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
    unzip() { printf 'unzip:%s\n' "$*" >>"${callLog}"; return 1; }
    tar() { printf 'tar:%s\n' "$*" >>"${callLog}"; return 1; }

    set +e
    installXray 1 false >/dev/null 2>&1
    xrayRc=$?
    installSingBox 1 >/dev/null 2>&1
    singBoxRc=$?
    set -e

    [[ "${xrayRc}" == "1" ]]
    [[ "${singBoxRc}" == "1" ]]
    [[ ! -e "${xrayDir}/xray" ]]
    [[ ! -e "${singBoxDir}/sing-box" ]]
    [[ ! -e "${singBoxDir}/libcronet.so" ]]
    grep -q 'Xray-core解压失败' "${errorLog}"
    grep -q 'sing-box解压失败' "${errorLog}"
)

runCoreFirstInstallCommitFailureRollbackRegression() (
    local rootRel="${TMP_DIR}/core-first-install-commit-failure"
    local root
    local xrayDir
    local singBoxDir
    local errorLog
    local copyLog
    local rmLog
    local xrayRc singBoxRc

    mkdir -p "${rootRel}/tmp" "${rootRel}/sing-box"
    root=$(cd -- "${rootRel}" && pwd -P)
    xrayDir="${root}/xray"
    singBoxDir="${root}/sing-box"
    printf 'old-cronet\n' >"${singBoxDir}/libcronet.so"
    errorLog="${root}/error.log"
    copyLog="${root}/copy.log"
    rmLog="${root}/rm.log"
    : >"${errorLog}"
    : >"${copyLog}"
    : >"${rmLog}"

    PADM_XRAY_BINARY="${xrayDir}/xray"
    PADM_SINGBOX_BINARY="${singBoxDir}/sing-box"
    xrayCoreCPUVendor=linux-64
    singBoxCoreCPUVendor=-linux-amd64
    TMPDIR="${root}/tmp"

    readInstallType() { return 0; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    coreLatestReleaseTag() { printf 'v1.2.3\n'; }
    checkVersionNotEmpty() { [[ -n "$1" ]]; }
    padmCreateTempPath() {
        local resultVar=$1
        local path
        shift
        if [[ "${1:-}" == "-d" ]]; then
            path=$(mktemp -d "${TMPDIR}/core.XXXXXX") || return 1
        else
            path=$(mktemp "${TMPDIR}/core.XXXXXX") || return 1
        fi
        printf -v "${resultVar}" '%s' "${path}"
    }
    padmCreateTempFileForTarget() {
        local resultVar=$1
        local targetFile=$2
        local targetDir targetName
        targetDir=$(dirname -- "${targetFile}")
        targetName=$(basename -- "${targetFile}")
        mkdir -p "${targetDir}" || return 1
        path=$(cd -- "${targetDir}" && mktemp ".${targetName}.install.XXXXXX") || return 1
        printf -v "${resultVar}" '%s' "${targetDir}/${path}"
    }
    padmRemoveCleanupPath() { rm -rf "$1"; }
    padmForgetCleanupPath() { return 0; }
    removeManagedFileIfPresent() {
        printf 'rm:%s\n' "$1" >>"${rmLog}"
        command rm -f -- "$1"
    }
    commitGeneratedFile() {
        local tmpFile=$1
        local targetFile=$2
        local mode=$3
        [[ -n "${mode}" ]] && chmod "${mode}" "${tmpFile}" || return 1
        if [[ "${targetFile}" == "${PADM_SINGBOX_BINARY}" ]]; then
            return 1
        fi
        mv "${tmpFile}" "${targetFile}"
    }
    xrayInstalled() { return 1; }
    singBoxInstalled() { return 1; }
    ensureXrayGeoFiles() { return 1; }
    downloadXrayReleaseBinaryToTempDir() {
        local version=$1
        local tmpDir=$2
        (
            cd -- "${tmpDir}" || return 1
            printf '#!/usr/bin/env bash\nexit 0\n' >xray || return 1
            chmod 755 xray || return 1
        ) || return 1
        return 0
    }
    downloadSingBoxReleaseBinaryToTempDir() {
        local version=$1
        local tmpDir=$2
        local extractedDir="sing-box-${version/v/}${singBoxCoreCPUVendor}"
        (
            cd -- "${tmpDir}" || return 1
            mkdir -p "${extractedDir}" || return 1
            printf '#!/usr/bin/env bash\nexit 0\n' >"${extractedDir}/sing-box" || return 1
            printf 'cronet\n' >"${extractedDir}/libcronet.so" || return 1
            chmod 755 "${extractedDir}/sing-box" || return 1
        ) || return 1
        return 0
    }
    cp() {
        local sourcePath=$1
        local targetPath=$2
        printf '%s -> %s\n' "${sourcePath}" "${targetPath}" >>"${copyLog}"
        command cp "$@"
    }

    set +e
    ( installXray 1 false >/dev/null 2>&1 )
    xrayRc=$?
    ( installSingBox 1 >/dev/null 2>&1 )
    singBoxRc=$?
    set -e

    [[ "${xrayRc}" == "1" ]]
    [[ "${singBoxRc}" == "1" ]]
    [[ ! -e "${xrayDir}/xray" ]]
    [[ ! -e "${singBoxDir}/sing-box" ]]
    [[ -e "${singBoxDir}/libcronet.so" ]] || return 1
    [[ "$(<"${singBoxDir}/libcronet.so")" == 'old-cronet' ]] || return 1
    grep -qxF "rm:${xrayDir}/xray" "${rmLog}"
    grep -q 'sing-box安装失败' "${errorLog}"
    ! grep -q 'cronet依赖回滚失败' "${errorLog}"

    rm -f "${singBoxDir}/libcronet.so"
    set +e
    ( installSingBox 1 >/dev/null 2>&1 )
    singBoxRc=$?
    set -e
    [[ "${singBoxRc}" == "1" ]]
    [[ ! -e "${singBoxDir}/sing-box" ]]
    [[ ! -e "${singBoxDir}/libcronet.so" ]] || return 1
)

runCoreInstallRejectsUnsafeBinaryPathRegression() (
    local root="${TMP_DIR}/core-install-unsafe-binary"
    local errorLog="${root}/error.log"
    local xrayRc singBoxRc

    mkdir -p "${root}"
    : >"${errorLog}"

    PADM_XRAY_BINARY="relative/xray"
    PADM_SINGBOX_BINARY="relative/sing-box"
    xrayCoreCPUVendor=linux-64
    singBoxCoreCPUVendor=-linux-amd64

    readInstallType() { return 0; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    coreLatestReleaseTag() { printf 'v1.2.3\n'; }
    checkVersionNotEmpty() { [[ -n "$1" ]]; }
    ensureXrayGeoFiles() { return 0; }
    padmCreateTempPath() {
        local resultVar=$1
        local path
        shift
        if [[ "${1:-}" == "-d" ]]; then
            path=$(mktemp -d "${root}/tmp.XXXXXX") || return 1
        else
            path=$(mktemp "${root}/tmp.XXXXXX") || return 1
        fi
        printf -v "${resultVar}" '%s' "${path}"
    }
    padmRemoveCleanupPath() { rm -rf "$1"; }
    downloadGitHubReleaseAsset() { return 0; }
    unzip() {
        if [[ "${1:-}" == "-Z1" ]]; then
            printf 'xray\n'
            return 0
        fi
        if [[ "${1:-}" == "-Z" && "${2:-}" == "-l" ]]; then
            printf '%s\n' '-rwxr-xr-x  3.0 unx 0 b- 0% 2026-01-01 00:00 xray'
            return 0
        fi
        if [[ "${1:-}" == "-p" ]]; then
            printf 'xray\n'
            return 0
        fi
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
        case "${1:-}" in
        -tzf)
            printf 'sing-box-1.2.3-linux-amd64/\nsing-box-1.2.3-linux-amd64/sing-box\nsing-box-1.2.3-linux-amd64/libcronet.so\n'
            return 0
            ;;
        -tvzf)
            printf '%s\n' 'drwxr-xr-x root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/'
            printf '%s\n' '-rwxr-xr-x root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/sing-box'
            printf '%s\n' '-rw-r--r-- root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/libcronet.so'
            return 0
            ;;
        -xOzf)
            printf 'sing-box\ncronet\n'
            return 0
            ;;
        esac
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
        printf 'cronet\n' >"${dest}/sing-box-1.2.3-linux-amd64/libcronet.so"
        chmod 755 "${dest}/sing-box-1.2.3-linux-amd64/sing-box"
    }

    set +e
    ( installXray 1 false >/dev/null 2>&1 )
    xrayRc=$?
    ( installSingBox 1 >/dev/null 2>&1 )
    singBoxRc=$?
    set -e

    [[ "${xrayRc}" == "1" ]]
    [[ "${singBoxRc}" == "1" ]]
    grep -q 'Xray-core安装路径异常' "${errorLog}"
    grep -q 'sing-box安装路径异常' "${errorLog}"
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
    local listenerKillLog="${root}/listener-kill.log"
    local publicIpCurlLog="${root}/public-ip-curl.log"
    local firewallLog="${root}/firewall.log"
    local mode=
    local dnsShellRc ipShellRc portShellRc templateShellRc

    mkdir -p "${root}/nginx"
    PADM_FIREWALL_STATE_FILE="${root}/firewall.state"
    eval "$(declare -f cleanAgentNginxConf | sed '1s/^cleanAgentNginxConf/originalCleanAgentNginxConf/')"

    if allowPort 0 || allowPort 65536 || allowPort 2000:1000 || allowPort 443 sctp; then
        return 1
    fi

    local ufwTcpAdded=false
    local ufwUdpAdded=false
    local ufwActive=true
    local ufwUdpAllowShouldFail=false
    : >"${firewallLog}"
    dpkg() {
        [[ "$1" == "-l" ]] || return 1
        printf 'ii  ufw  0  all  firewall\n'
    }
    ufw() {
        case "$1" in
        status)
            if [[ "${ufwActive}" == "true" ]]; then
                printf 'Status: active\n1443/tcp ALLOW Anywhere\n'
                [[ "${ufwTcpAdded}" == "true" ]] && printf '443/tcp ALLOW Anywhere\n'
                [[ "${ufwUdpAdded}" == "true" ]] && printf '443/udp ALLOW Anywhere\n'
            else
                printf 'Status: inactive\n'
            fi
            return 0
            ;;
        show)
            [[ "$2" == "added" ]] || return 1
            printf 'Added user rules:\n'
            [[ "${ufwTcpAdded}" == "true" ]] && printf 'ufw allow 443/tcp\n'
            [[ "${ufwUdpAdded}" == "true" ]] && printf 'ufw allow 443/udp\n'
            return 0
            ;;
        allow)
            printf 'ufw:allow:%s\n' "$2" >>"${firewallLog}"
            [[ "$2" != "443/udp" || "${ufwUdpAllowShouldFail}" != "true" ]] || return 1
            [[ "$2" == "443/tcp" ]] && ufwTcpAdded=true
            [[ "$2" == "443/udp" ]] && ufwUdpAdded=true
            return 0
            ;;
        delete)
            printf 'ufw:delete:%s\n' "$3" >>"${firewallLog}"
            [[ "$3" == "443/tcp" ]] && ufwTcpAdded=false
            [[ "$3" == "443/udp" ]] && ufwUdpAdded=false
            return 0
            ;;
        *) return 1 ;;
        esac
    }
    sudo() { "$@"; }
    allowPort 443
    allowPort 443 udp
    grep -qx 'ufw:allow:443/tcp' "${firewallLog}"
    grep -qx 'ufw:allow:443/udp' "${firewallLog}"
    : >"${firewallLog}"
    allowPort 443
    allowPort 443 udp
    [[ ! -s "${firewallLog}" ]]
    grep -qx 'port:ufw:tcp:443' "${PADM_FIREWALL_STATE_FILE}"
    grep -qx 'port:ufw:udp:443' "${PADM_FIREWALL_STATE_FILE}"
    lsof() {
        if [[ "$*" == "-nP -iTCP:443 -sTCP:LISTEN" && "${tcpListenerPresent:-false}" == "true" ]]; then
            printf 'nginx 123 root 6u IPv4 TCP *:443 (LISTEN)\n'
            return 0
        fi
        if [[ "$*" == "-nP -iUDP:443" && "${udpListenerPresent:-false}" == "true" ]]; then
            printf 'wireguard 123 root 6u IPv4 UDP *:443\n'
            return 0
        fi
        return 1
    }
    local tcpListenerPresent=true
    local udpListenerPresent=true
    denyPort 443
    denyPort 443 udp
    ! grep -qx 'ufw:delete:443/tcp' "${firewallLog}"
    ! grep -qx 'ufw:delete:443/udp' "${firewallLog}" || return 1
    grep -qx 'port:ufw:tcp:443' "${PADM_FIREWALL_STATE_FILE}"
    grep -qx 'port:ufw:udp:443' "${PADM_FIREWALL_STATE_FILE}" || return 1
    tcpListenerPresent=false
    udpListenerPresent=false
    denyPort 443
    denyPort 443 udp
    grep -qx 'ufw:delete:443/tcp' "${firewallLog}"
    [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]

    (
        local concurrentState="${root}/concurrent-firewall.state"
        local firstPid secondPid firstRc secondRc
        PADM_FIREWALL_STATE_FILE="${concurrentState}"
        PADM_FIREWALL_STATE_LOCK_TIMEOUT=5
        rm -f "${concurrentState}" "${concurrentState}.lock"
        commitGeneratedFile() {
            local tmpFile=$1
            local targetFile=$2
            local mode=${3:-}
            [[ -z "${mode}" ]] || chmod "${mode}" "${tmpFile}"
            sleep 0.1
            mv -f -- "${tmpFile}" "${targetFile}" || return 1
            padmForgetCleanupPath "${tmpFile}"
        }
        padmFirewallStateAdd 'port:ufw:tcp:30001' &
        firstPid=$!
        padmFirewallStateAdd 'port:ufw:tcp:30002' &
        secondPid=$!
        set +e
        wait "${firstPid}"
        firstRc=$?
        wait "${secondPid}"
        secondRc=$?
        set -e
        [[ "${firstRc}" == "0" ]]
        [[ "${secondRc}" == "0" ]]
        grep -qx 'port:ufw:tcp:30001' "${concurrentState}"
        grep -qx 'port:ufw:tcp:30002' "${concurrentState}"
    )

    padmFirewallStateAdd 'port:ufw:tcp:443'
    : >"${firewallLog}"
    failAfterPortAllow() {
        allowPort 443
        return 1
    }
    if padmRunPortAllowTransaction failAfterPortAllow; then
        return 1
    fi
    grep -qx 'ufw:allow:443/tcp' "${firewallLog}"
    grep -qx 'ufw:delete:443/tcp' "${firewallLog}"
    [[ "${ufwTcpAdded}" == "false" ]]
    [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]

    : >"${firewallLog}"
    allowPort 1443
    denyPort 1443
    [[ ! -s "${firewallLog}" ]]
    allowPort 443
    allowPort 443 udp
    ufwActive=false
    : >"${firewallLog}"
    cleanupPadmFirewallRules
    grep -qx 'ufw:delete:443/tcp' "${firewallLog}"
    grep -qx 'ufw:delete:443/udp' "${firewallLog}"
    [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]
    ufwActive=true
    ufwUdpAllowShouldFail=true
    : >"${firewallLog}"
    if allowPortTcpAndUdp 443; then
        return 1
    fi
    ufwUdpAllowShouldFail=false
    grep -qx 'ufw:delete:443/tcp' "${firewallLog}"
    [[ "${ufwTcpAdded}" == "false" ]]
    [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]

    ufwActive=false
    local fallbackFirewalldAdded=false
    systemctl() { [[ "$*" == "is-active --quiet firewalld" ]]; }
    firewall-cmd() {
        case "$*" in
        *--list-ports*) [[ "${fallbackFirewalldAdded}" == "true" ]] && printf '2443/tcp\n' ;;
        *--add-port=2443/tcp*) fallbackFirewalldAdded=true ;;
        *--remove-port=2443/tcp*) fallbackFirewalldAdded=false ;;
        *--reload*) return 0 ;;
        *) return 1 ;;
        esac
    }
    allowPort 2443
    [[ "${fallbackFirewalldAdded}" == "true" ]]
    grep -qx 'port:firewalld:tcp:2443' "${PADM_FIREWALL_STATE_FILE}"
    denyPort 2443
    [[ "${fallbackFirewalldAdded}" == "false" ]]
    unset -f systemctl firewall-cmd
    unset -f dpkg ufw sudo

    local firewalldPermanentTcpAdded=false
    local firewalldRuntimeTcpAdded=false
    local firewalldReloadShouldFail=false
    : >"${firewallLog}"
    dpkg() { return 1; }
    systemctl() {
        if [[ "$*" == "status firewalld" || "$*" == "is-active --quiet firewalld" ]]; then
            printf 'Active: active (running)\n'
            return 0
        fi
        return 1
    }
    firewall-cmd() {
        if [[ "$*" != "--reload" && " $* " != *" --zone=public "* ]]; then
            return 1
        fi
        case "$*" in
        *--list-ports*)
            printf '443/udp'
            [[ "${firewalldPermanentTcpAdded}" == "true" ]] && printf ' 443/tcp'
            printf '\n'
            ;;
        *--add-port=*)
            for arg in "$@"; do
                case "${arg}" in
                --add-port=*)
                    printf 'firewalld:add:%s\n' "${arg}" >>"${firewallLog}"
                    ;;
                esac
            done
                firewalldPermanentTcpAdded=true
            ;;
        *--remove-port=*)
            for arg in "$@"; do
                case "${arg}" in
                --remove-port=*)
                    printf 'firewalld:remove:%s\n' "${arg}" >>"${firewallLog}"
                    ;;
                esac
            done
                firewalldPermanentTcpAdded=false
            ;;
        *--reload*)
            [[ "${firewalldReloadShouldFail}" != "true" ]] || return 1
            firewalldRuntimeTcpAdded=${firewalldPermanentTcpAdded}
            ;;
        *) return 1 ;;
        esac
    }
    allowPort 443
    grep -qx 'firewalld:add:--add-port=443/tcp' "${firewallLog}"
    grep -qx 'port:firewalld:tcp:443' "${PADM_FIREWALL_STATE_FILE}"
    [[ "${firewalldRuntimeTcpAdded}" == "true" ]]
    firewalldReloadShouldFail=true
    if denyPort 443; then
        return 1
    fi
    [[ "${firewalldPermanentTcpAdded}" == "false" ]]
    [[ "${firewalldRuntimeTcpAdded}" == "true" ]]
    grep -qx 'port:firewalld:tcp:443' "${PADM_FIREWALL_STATE_FILE}"
    firewalldReloadShouldFail=false
    denyPort 443
    grep -qx 'firewalld:remove:--remove-port=443/tcp' "${firewallLog}"
    [[ "${firewalldRuntimeTcpAdded}" == "false" ]]
    [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]
    unset -f dpkg systemctl firewall-cmd

    : >"${firewallLog}"
    local iptablesTcpAdded=false
    local iptablesTcpPersisted=false
    local iptablesSaveShouldFail=false
    dpkg() { return 1; }
    systemctl() {
        [[ "$*" == "is-active --quiet netfilter-persistent" ]]
    }
    rc-update() { return 1; }
    dpkg-query() { printf 'ii\n'; }
    iptables() {
        if [[ "$1" == "-L" ]]; then
            printf 'ACCEPT tcp -- anywhere anywhere /* allow 1443/tcp(neil1123-vip) */\n'
            [[ "${iptablesTcpAdded}" == "true" ]] && printf 'ACCEPT tcp -- anywhere anywhere /* allow 443/tcp(neil1123-vip) */\n'
            return 0
        elif [[ "$1" == "-I" ]]; then
            printf 'iptables:add:%s\n' "$*" >>"${firewallLog}"
            iptablesTcpAdded=true
        elif [[ "$1" == "-D" ]]; then
            printf 'iptables:delete:%s\n' "$*" >>"${firewallLog}"
            iptablesTcpAdded=false
        fi
    }
    netfilter-persistent() {
        [[ "$1" == "save" ]] || return 1
        [[ "${iptablesSaveShouldFail}" != "true" ]] || return 1
        iptablesTcpPersisted=${iptablesTcpAdded}
    }
    allowPort 443
    grep -q '^iptables:add:-I INPUT -p tcp --dport 443 ' "${firewallLog}"
    grep -qx 'port:iptables:tcp:443' "${PADM_FIREWALL_STATE_FILE}"
    [[ "${iptablesTcpPersisted}" == "true" ]]
    iptablesSaveShouldFail=true
    if denyPort 443; then
        return 1
    fi
    [[ "${iptablesTcpAdded}" == "false" ]]
    [[ "${iptablesTcpPersisted}" == "true" ]]
    grep -qx 'port:iptables:tcp:443' "${PADM_FIREWALL_STATE_FILE}"
    iptablesSaveShouldFail=false
    denyPort 443
    grep -q '^iptables:delete:-D INPUT -p tcp --dport 443 ' "${firewallLog}"
    [[ "${iptablesTcpPersisted}" == "false" ]]
    [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]
    unset -f dpkg systemctl rc-update dpkg-query iptables netfilter-persistent

    errorCard() { return 0; }
    sleep() { return 0; }
    dig() { return 1; }
    curl() {
        printf '%s\n' "$*" >>"${publicIpCurlLog}"
        case "$*" in
        *" -4 "*) printf 'ip=203.0.113.10\n' ;;
        *" -6 "*) printf 'ip=2001:db8::10\n' ;;
        *) return 1 ;;
        esac
    }
    [[ "$(getPublicIP 4)" == "203.0.113.10" ]]
    [[ "$(getPublicIP 6)" == "2001:db8::10" ]]
    hasIPv6Connectivity
    grep -q -- 'https://www.cloudflare.com/cdn-cgi/trace' "${publicIpCurlLog}"
    grep -q -- '--connect-timeout 5' "${publicIpCurlLog}"
    grep -q -- '--max-time 10' "${publicIpCurlLog}"
    curl() { printf 'ip=not-an-ip\n'; }
    [[ -z "$(getPublicIP 4)" ]]
    unset -f curl
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
        if [[ -s "${listenerKillLog}" && "$*" != "-t -a -i tcp:8443 -sTCP:LISTEN" ]]; then
            return 1
        fi
        case "$*" in
        "-i tcp:8443"|"-nP -i tcp:8443")
            case "${portProcessKind}" in
            padm) printf 'xray 123 root 3u IPv4 TCP *:8443 (LISTEN)\n' ;;
            nginx) printf 'nginx 123 root 3u IPv4 TCP *:8443 (LISTEN)\n' ;;
            other)
                printf 'listener 123 root 3u IPv4 TCP *:8443 (LISTEN)\n'
                printf 'client 456 root 4u IPv4 TCP 10.0.0.2:50000->198.51.100.10:8443 (ESTABLISHED)\n'
                ;;
            none) return 1 ;;
            esac
            ;;
        "-t -a -i tcp:8443 -sTCP:LISTEN")
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

    xargs() {
        [[ "$1" == "-r" && "$2" == "kill" ]] || return 1
        cat >"${listenerKillLog}"
    }
    portProcessKind=other
    : >"${listenerKillLog}"
    checkPort 8443 >/dev/null 2>&1
    grep -qx '123' "${listenerKillLog}"
    ! grep -q '456' "${listenerKillLog}"
    unset -f xargs

    local singBoxState=true
    local xrayState=true
    local nginxState=true
    local realityConf="${root}/reality-stream.conf"
    local realityState="${root}/reality-stream.state"
    local nginxMainConf="${root}/nginx.conf"
    export PADM_REALITY_STREAM_CONF_FILE="${realityConf}"
    export PADM_REALITY_STREAM_STATE_FILE="${realityState}"
    export PADM_REALITY_STREAM_NGINX_CONF="${nginxMainConf}"
    printf 'old-alone\n' >"${root}/nginx/alone.conf"
    printf 'old-stream\n' >"${realityConf}"
    printf 'old-state\n' >"${realityState}"
    cat >"${nginxMainConf}" <<EOF
events {}
# padm stream include start
include ${root}/stream.d/*.conf;
# padm stream include end
http {}
EOF
    local originalNginxMainConf
    originalNginxMainConf=$(<"${nginxMainConf}")
    allowPort() { return 0; }
    singBoxRunning() { [[ "${singBoxState}" == "true" ]]; }
    xrayRunning() { [[ "${xrayState}" == "true" ]]; }
    nginxRunning() { [[ "${nginxState}" == "true" ]]; }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "$1" == "stop" ]] && singBoxState=false
        [[ "$1" == "start" ]] && singBoxState=true
        return 0
    }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "$1" == "stop" ]] && xrayState=false
        [[ "$1" == "start" ]] && xrayState=true
        return 0
    }
    handleNginx() {
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ -n "${2:-}" ]] && printf 'nginx-mode:%s\n' "$*" >>"${serviceLog}"
        [[ "$1" == "stop" ]] && nginxState=false
        [[ "$1" == "start" ]] && nginxState=true
        return 0
    }
    cleanAgentNginxConf() {
        printf 'clean:%s\n' "${mode}" >>"${cleanLog}"
        originalCleanAgentNginxConf
    }

    mode=write-fail
    : >"${serviceLog}"
    set +e
    checkPortOpen 443 example.com >/dev/null 2>&1
    local restoreRc=$?
    set -e
    [[ "${restoreRc}" == "1" ]]
    [[ "$(<"${root}/nginx/alone.conf")" == "old-alone" ]]
    [[ "$(<"${realityConf}")" == "old-stream" ]]
    [[ "$(<"${realityState}")" == "old-state" ]]
    [[ "$(<"${nginxMainConf}")" == "${originalNginxMainConf}" ]]
    [[ "${singBoxState}" == "true" && "${xrayState}" == "true" && "${nginxState}" == "true" ]]
    grep -qx 'sing-box:start:true' "${serviceLog}"
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1

    mode=success
    singBoxState=true
    xrayState=true
    nginxState=true
    pgrep() { [[ "$*" == "-f nginx" ]] && printf '123\n'; }
    curl() {
        [[ "${!#}" == */checkPort ]] && printf 'fjkvymb6len' || printf '203.0.113.10'
    }
    checkIP() { return 0; }
    checkPortOpen 443 example.com >/dev/null 2>&1
    [[ ! -e "${root}/nginx/alone.conf" ]]
    [[ ! -e "${realityConf}" && ! -e "${realityState}" ]]
    ! grep -q 'padm stream include start' "${nginxMainConf}"
    [[ "${singBoxState}" == "false" && "${xrayState}" == "false" && "${nginxState}" == "true" ]] || return 1
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    if regressionFindHasMatches "${TMP_DIR}" -mindepth 1 -maxdepth 1 -name 'padm-check-port-open.*'; then
        return 1
    fi

    currentUUID=existing-user
    currentClients='[]'
    domain=tls.example.com
    currentHost=tls.example.com
    lastInstallationConfig=true
    selectCustomInstallType=",27,"
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
    local chmodLog="${root}/chmod.log"
    local reachedFile="${root}/reached"
    local shellRc

    mkdir -p "${root}/home"
    HOME="${root}/home"
    errorCard() { return 0; }
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

    local existingTlsRoot="${root}/existing-tls"
    mkdir -p "${existingTlsRoot}"
    export PADM_TLS_DIR="${existingTlsRoot}"
    domain=existing.example.com
    printf 'old-cert\n' >"${existingTlsRoot}/existing.example.com.crt"
    printf 'old-key\n' >"${existingTlsRoot}/existing.example.com.key"
    installTLSCount=
    sudo() { return 1; }
    set +e
    installTLSFromAcme >/dev/null 2>&1
    shellRc=$?
    set -e
    [[ "${shellRc}" == "1" ]]
    unset -f sudo

    local secureTlsRoot="${root}/secure-install"
    mkdir -p "${secureTlsRoot}/home/.acme.sh" "${secureTlsRoot}/tls"
    HOME="${secureTlsRoot}/home"
    export PADM_TLS_DIR="${secureTlsRoot}/tls"
    domain=secure.example.com
    installedDNSAPIStatus=
    printf '#!/usr/bin/env sh\n' >"${HOME}/.acme.sh/acme.sh"
    command chmod 755 "${HOME}/.acme.sh/acme.sh"
    printf 'old-cert\n' >"${PADM_TLS_DIR}/secure.example.com.crt"
    printf 'old-key\n' >"${PADM_TLS_DIR}/secure.example.com.key"
    command chmod 644 "${PADM_TLS_DIR}/secure.example.com.key"
    : >"${chmodLog}"
    chmod() {
        printf '%s\n' "$*" >>"${chmodLog}"
        command chmod "$@"
    }
    sudo() {
        printf 'new-cert\n' >"${PADM_TLS_DIR}/secure.example.com.crt"
        printf 'new-key\n' >"${PADM_TLS_DIR}/secure.example.com.key"
        return 0
    }
    installTLSFromAcme >/dev/null 2>&1
    grep -F -q -- "600 -- ${PADM_TLS_DIR}/secure.example.com.key" "${chmodLog}"
    [[ "$(<"${PADM_TLS_DIR}/secure.example.com.key")" == "new-key" ]]
    unset -f chmod
    unset -f sudo

    (
        acmeInstallSSL() { return 1; }
        readAcmeTLS() { return 0; }
        captureFailureReturn "${root}/select-acme.rc" selectAcmeInstallSSL
    )

    (
        readAcmeTLS() { return 1; }
        captureFailureReturn "${root}/install-read-acme.rc" installTLS 1
        captureFailureReturn "${root}/status-read-acme.rc" tlsCertificateStatusJson
        captureFailureReturn "${root}/renew-read-acme.rc" renewalTLS
    )

    (
        btDomain=
        readUserCrontabContent() { return 1; }
        captureFailureReturn "${root}/install-cron.rc" installCronTLS 1
    )

    (
        local renewalRoot="${root}/renewal-install"
        mkdir -p "${renewalRoot}/home"
        export PADM_TLS_DIR="${renewalRoot}/tls"
        HOME="${renewalRoot}/home"
        mkdir -p "${PADM_TLS_DIR}"
        domain=renew.example.com
        currentHost=renew.example.com
        tlsDomain=renew.example.com
        lastInstallationConfig=true
        installedDNSAPIStatus=
        printf 'cert\n' >"${PADM_TLS_DIR}/renew.example.com.crt"
        printf 'key\n' >"${PADM_TLS_DIR}/renew.example.com.key"
        readAcmeTLS() { return 0; }
        renewalTLS() { return 37; }
        ! installTLS 1 >/dev/null 2>&1
    )

    (
        local emptyKeyRoot="${root}/empty-key"
        mkdir -p "${emptyKeyRoot}/home" "${emptyKeyRoot}/tls"
        export PADM_TLS_DIR="${emptyKeyRoot}/tls"
        HOME="${emptyKeyRoot}/home"
        domain=empty-key.example.com
        currentHost=empty-key.example.com
        tlsDomain=empty-key.example.com
        lastInstallationConfig=true
        installedDNSAPIStatus=
        printf 'cert\n' >"${PADM_TLS_DIR}/empty-key.example.com.crt"
        : >"${PADM_TLS_DIR}/empty-key.example.com.key"
        readAcmeTLS() { return 0; }
        ! installTLS 1 >/dev/null 2>&1
    )

    (
        local acmeOnlyRoot="${root}/acme-only"
        mkdir -p "${acmeOnlyRoot}/home/.acme.sh/acme-only.example.com_ecc"
        export PADM_TLS_DIR="${acmeOnlyRoot}/tls"
        HOME="${acmeOnlyRoot}/home"
        domain=acme-only.example.com
        currentHost=acme-only.example.com
        tlsDomain=acme-only.example.com
        installedDNSAPIStatus=
        printf 'cert\n' >"${HOME}/.acme.sh/acme-only.example.com_ecc/acme-only.example.com.cer"
        printf 'key\n' >"${HOME}/.acme.sh/acme-only.example.com_ecc/acme-only.example.com.key"
        local acmeInstallFromHomeCalled=false
        readAcmeTLS() { return 0; }
        installTLSFromAcme() { acmeInstallFromHomeCalled=true; return 0; }
        installTLS 1 >/dev/null 2>&1
        [[ "${acmeInstallFromHomeCalled}" == "true" ]]
    )

    (
        local missingRenewRoot="${root}/renewal-missing"
        mkdir -p "${missingRenewRoot}/home" "${missingRenewRoot}/tls"
        export PADM_TLS_DIR="${missingRenewRoot}/tls"
        HOME="${missingRenewRoot}/home"
        currentHost=
        domain=
        tlsDomain=
        installedDNSAPIStatus=
        readAcmeTLS() { return 0; }
        errorCard() { return 0; }
        ! renewalTLS >/dev/null 2>&1
    )

    btDomain=
    readLastInstallationConfig() { return 0; }
    unInstallSubscribe() { return 0; }
    installTools() { return 0; }
    initTLSNginxConfig() { return 0; }
    installTLS() { return 1; }
    randomPathFunction() {
        printf 'reached\n' >"${reachedFile}"
        return 0
    }

    captureFailureReturn "${xrayRcFile}" xrayCoreInstall
    [[ ! -e "${reachedFile}" ]]

    HOME="${oldHome}"
)

runAutoReadUnsetAutoInstallRegression() (
    local value=
    unset AUTO_INSTALL AUTO_INSTALL_TYPE
    autoRead regression_unset_auto_install "请输入:" value <<<"manual-value"
    [[ "${value}" == "manual-value" ]]
)

runTlsCustomSSLEmailUsesHomeAccountFileRegression() (
    local root="${TMP_DIR}/tls-custom-email-home"
    local homeDir="${root}/home"
    local accountFile="${homeDir}/.acme.sh/account.conf"
    local oldHome="${HOME}"

    mkdir -p "$(dirname -- "${accountFile}")"
    printf "ACCOUNT_EMAIL='old@example.com'\n" >"${accountFile}"
    HOME="${homeDir}"
    sslType=zerossl
    autoRead() {
        case "$3" in
        sslEmailStatus) printf -v "$3" 'y' ;;
        sslEmail) printf -v "$3" 'new@example.com' ;;
        *) printf -v "$3" '' ;;
        esac
    }

    customSSLEmail "validate email"

    grep -q "ACCOUNT_EMAIL='new@example.com'" "${accountFile}"
    ! grep -q "old@example.com" "${accountFile}"
    HOME="${oldHome}"
)

runTlsCustomSSLEmailTransactionRegression() (
    local root="${TMP_DIR}/tls-custom-email-transaction"
    local homeDir="${root}/home"
    local accountFile="${homeDir}/.acme.sh/account.conf"
    local oldHome="${HOME}"

    mkdir -p "$(dirname -- "${accountFile}")"
    printf "ACCOUNT_EMAIL='old@example.com'\n" >"${accountFile}"
    HOME="${homeDir}"
    sslType=zerossl
    autoRead() {
        case "$3" in
        sslEmailStatus) printf -v "$3" 'y' ;;
        sslEmail) printf -v "$3" 'new@example.com' ;;
        *) printf -v "$3" '' ;;
        esac
    }
    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${accountFile}" ]]; then
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    set +e
    customSSLEmail "validate email"
    local rc=$?
    set -e

    [[ "${rc}" == "1" ]]
    grep -q "ACCOUNT_EMAIL='old@example.com'" "${accountFile}"
    ! grep -q "new@example.com" "${accountFile}"
    ! compgen -G "${homeDir}/.acme.sh/.account.conf.*" >/dev/null
    unset -f commitGeneratedFile originalCommitGeneratedFile
    HOME="${oldHome}"
)

runTlsCustomSSLEmailRejectsUnsafeAddressRegression() (
    local root="${TMP_DIR}/tls-custom-email-unsafe-address"
    local homeDir="${root}/home"
    local accountFile="${homeDir}/.acme.sh/account.conf"
    local oldHome="${HOME}"
    local rc

    mkdir -p "$(dirname -- "${accountFile}")"
    printf "ACCOUNT_EMAIL='old@example.com'\n" >"${accountFile}"
    HOME="${homeDir}"
    sslType=zerossl
    autoRead() {
        case "$3" in
        sslEmailStatus) printf -v "$3" 'y' ;;
        sslEmail) printf -v "$3" "bad'@example.com" ;;
        *) printf -v "$3" '' ;;
        esac
    }

    set +e
    customSSLEmail "validate email"
    rc=$?
    set -e

    [[ "${rc}" == "1" ]]
    grep -qxF "ACCOUNT_EMAIL='old@example.com'" "${accountFile}"
    ! grep -qF "bad'" "${accountFile}"
    [[ ! -e "${accountFile}_tmp" ]]
    ! compgen -G "${homeDir}/.acme.sh/.account.conf.*" >/dev/null
    HOME="${oldHome}"
)

runTlsSslTypeWriteTransactionRegression() (
    local root="${TMP_DIR}/tls-ssl-type-transaction"
    local tlsDir="${root}/tls"
    local sslTypeFile="${tlsDir}/ssl_type"
    local errorLog="${root}/errors.log"
    local oldTlsDir="${PADM_TLS_DIR:-}"

    mkdir -p "${tlsDir}"
    printf 'zerossl\n' >"${sslTypeFile}"
    PADM_TLS_DIR="${tlsDir}"
    sslType=
    dnsAPIType=
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; return 0; }
    autoRead() {
        case "$3" in
        selectSSLType) printf -v "$3" '3' ;;
        *) printf -v "$3" '' ;;
        esac
    }
    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${sslTypeFile}" ]]; then
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    set +e
    switchSSLType
    local rc=$?
    set -e

    [[ "${rc}" == "1" ]]
    [[ "$(<"${sslTypeFile}")" == "zerossl" ]]
    [[ "${sslType}" == "buypass" ]]
    ! compgen -G "${tlsDir}/.ssl_type.*" >/dev/null
    unset -f commitGeneratedFile originalCommitGeneratedFile
    if [[ -n "${oldTlsDir}" ]]; then
        PADM_TLS_DIR="${oldTlsDir}"
    else
        unset PADM_TLS_DIR
    fi
)

runServiceQueueApplyPropagationRegression() (
    local root="${TMP_DIR}/service-queue-propagation"
    local rcFile="${root}/install.rc"
    local reachedFile="${root}/show-accounts"
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
    checkGFWStatue() {
        printf 'reached\n' >"${reachedFile}"
        return 0
    }
    showAccounts() {
        printf 'reached\n' >"${reachedFile}"
        return 0
    }

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
    [[ ! -e "${reachedFile}" ]]
)

runCoreInstallServiceActionFailureRegression() (
    local root="${TMP_DIR}/core-install-service-action"
    local serviceLog="${root}/service.log"
    local callLog="${root}/calls.log"
    local errorLog="${root}/errors.log"
    local reachedFile="${root}/reached"
    local firewallState="${root}/firewall.state"
    local firewallLog="${root}/firewall.log"
    local mode rc nginxRuntimeState

    mkdir -p "${root}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    PADM_FIREWALL_STATE_FILE="${firewallState}"
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    protocolRegistryMenu() { return 0; }
    readLastInstallationConfig() { return 0; }
    unInstallSubscribe() { return 0; }
    installTools() { printf 'installTools:%s\n' "$*" >>"${callLog}"; return 0; }
    initTLSNginxConfig() { printf 'initTLS:%s\n' "$*" >>"${callLog}"; return 0; }
    installTLS() { printf 'installTLS:%s\n' "$*" >>"${callLog}"; return 0; }
    randomPathFunction() {
        printf 'path:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" != "path-fail" ]]
    }
    nginxBlog() {
        printf 'nginxBlog:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" != "blog-fail" ]]
    }
    updateRedirectNginxConf() {
        printf 'redirect\n' >>"${callLog}"
        [[ "${mode}" == "redirect-fail" ]] && return 1
        nginxRuntimeState=false
        return 0
    }
    installXray() {
        printf 'installXray:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" == "xray-install-exit" ]] && exit 1
        return 0
    }
    installXrayService() {
        printf 'installXrayService:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" == "xray-service-fail" ]] && return 1
        return 0
    }
    initXrayConfig() {
        printf 'initXrayConfig:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" != "xray-config-fail" ]]
    }
    installSingBox() { printf 'installSingBox:%s\n' "$*" >>"${callLog}"; return 0; }
    installSingBoxService() { printf 'installSingBoxService:%s\n' "$*" >>"${callLog}"; return 0; }
    initSingBoxConfig() { printf 'initSingBoxConfig:%s\n' "$*" >>"${callLog}"; return 0; }
    cleanUp() { printf 'cleanup:%s\n' "$*" >>"${callLog}"; return 0; }
    cleanAgentNginxConf() { printf 'clean-nginx\n' >>"${callLog}"; return 0; }
    installCronTLS() {
        printf 'cron:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" != "cron-fail" ]]
    }
    customPortFunction() {
        padmFirewallStateAdd 'port:ufw:tcp:2443' || return 1
        padmTrackPortAllowTransactionKey 'port:ufw:tcp:2443'
        printf 'customPort\n' >>"${callLog}"
    }
    removeFirewallPortRule() {
        printf '%s:%s:%s\n' "$1" "$2" "$3" >>"${firewallLog}"
    }
    subscriptionWireGuardControlEnabled() { return 0; }
    refreshSubscriptionWireGuardNginxControl() {
        printf 'wg-refresh\n' >>"${callLog}"
        [[ "${mode}" != "wg-refresh-fail" ]] || return 1
        serviceQueueRestart nginx
    }
    serviceQueueRestart() {
        printf 'queueRestart:%s\n' "$*" >>"${callLog}"
        SERVICE_ACTIONS="${SERVICE_ACTIONS}
$1:restart"
    }
    serviceQueueStart() { printf 'queueStart:%s\n' "$*" >>"${callLog}"; return 0; }
    serviceQueueApply() {
        printf 'queueApply\n' >>"${callLog}"
        SERVICE_ACTIONS=
        return 0
    }
    checkGFWStatue() {
        printf 'reached\n' >"${reachedFile}"
        [[ "${mode}" != "check-gfw-fail" ]]
    }
    showAccounts() { printf 'reached\n' >"${reachedFile}"; return 0; }
    handleNginx() {
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ -n "${2:-}" ]] && printf 'nginx-mode:%s\n' "$*" >>"${serviceLog}"
        [[ "${mode}" == "nginx-stop-fail" && "$1" == "stop" ]] && return 1
        [[ "${mode}" == "nginx-start-fail" && "$1" == "start" && "${2:-}" != "restore" ]] && return 1
        [[ "$1" == "stop" ]] && nginxRuntimeState=false
        [[ "$1" == "start" ]] && nginxRuntimeState=true
        return 0
    }
    nginxRunning() { [[ "${nginxRuntimeState}" == "true" ]]; }
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
        : >"${firewallLog}"
        rm -f "${reachedFile}"
        rm -f "${firewallState}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        btDomain=
        realityOnlyWithDomain=
        currentHost=install.example.com
        domain=install.example.com
        nginxRuntimeState=true
        SERVICE_ACTIONS=
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
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture path-fail
    set +e
    customXrayInstall 21 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'path:4' "${callLog}"
    ! grep -q '^nginxBlog:' "${callLog}"
    ! grep -q '^installXray:' "${callLog}"

    resetInstallServiceFixture blog-fail
    set +e
    customXrayInstall 21 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'nginxBlog:6' "${callLog}"
    ! grep -q '^installXray:' "${callLog}"

    resetInstallServiceFixture cron-fail
    set +e
    customXrayInstall 21 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'cron:10' "${callLog}"
    ! grep -q '^queueApply$' "${callLog}"
    [[ ! -e "${reachedFile}" ]]

    resetInstallServiceFixture wg-refresh-fail
    set +e
    installXrayReality >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:stop:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    grep -qx 'wg-refresh' "${callLog}"
    ! grep -q '^installXray:' "${callLog}"
    [[ "${nginxRuntimeState}" == "true" ]]
    grep -q 'WireGuard Nginx 控制面刷新失败，已恢复原 Nginx 运行状态' "${errorLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture xray-config-fail
    SERVICE_ACTIONS="existing:start"
    set +e
    installXrayReality >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:stop:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    grep -qx 'wg-refresh' "${callLog}"
    grep -qx 'queueRestart:nginx' "${callLog}"
    grep -qx 'initXrayConfig:custom 3' "${callLog}"
    ! grep -q '^cleanup:' "${callLog}"
    [[ "${nginxRuntimeState}" == "true" ]]
    [[ "${SERVICE_ACTIONS}" == "existing:start" ]]
    grep -q 'Xray Reality 配置初始化失败，已恢复原 Nginx 运行状态' "${errorLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    for mode in xray-install-exit xray-service-fail; do
        resetInstallServiceFixture "${mode}"
        set +e
        installXrayReality >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -qx 'nginx:stop:true' "${serviceLog}"
        grep -qx 'nginx:start:true' "${serviceLog}"
        grep -qx 'wg-refresh' "${callLog}"
        grep -qx 'queueRestart:nginx' "${callLog}"
        grep -q '^installXray:' "${callLog}"
        if [[ "${mode}" == "xray-service-fail" ]]; then
            grep -q '^installXrayService:' "${callLog}"
        else
            ! grep -q '^installXrayService:' "${callLog}"
        fi
        [[ "${nginxRuntimeState}" == "true" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    done

    resetInstallServiceFixture check-gfw-fail
    set +e
    installXrayReality >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:stop:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}" || return 1
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    [[ "${nginxRuntimeState}" == "true" ]] || return 1

    resetInstallServiceFixture nginx-start-fail
    set +e
    customXrayInstall 21 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:start:true' "${serviceLog}"
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    [[ "${nginxRuntimeState}" == "true" ]] || return 1
    ! grep -q '^installXray:' "${callLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture xray-service-fail
    btDomain=panel.example.com
    set +e
    customXrayInstall 21 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'customPort' "${callLog}"
    grep -qx 'ufw:2443:tcp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    resetInstallServiceFixture redirect-fail
    set +e
    customXrayInstall 21 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'redirect' "${callLog}"
    ! grep -q '^nginx:start:' "${serviceLog}"
    ! grep -q '^installXray:' "${callLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture no-local-cert
    set +e
    customXrayInstall 2 >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
    grep -qx 'clean-nginx' "${callLog}"
    grep -q '^installXray:' "${callLog}"
    [[ -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture xray-start-fail
    set +e
    xrayCoreInstall >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}" || return 1
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    [[ "${nginxRuntimeState}" == "true" ]] || return 1
    grep -q '^installXray:' "${callLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture redirect-fail
    set +e
    xrayCoreInstall >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'redirect' "${callLog}"
    ! grep -q '^xray:stop:' "${serviceLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture nginx-stop-fail
    set +e
    singBoxInstall >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:stop:true' "${serviceLog}"
    ! grep -q '^installSingBox:' "${callLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture blog-fail
    set +e
    xrayCoreInstall >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'nginxBlog:10' "${callLog}"
    ! grep -q '^redirect$' "${callLog}"

    resetInstallServiceFixture cron-fail
    set +e
    singBoxInstall >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'cron:8' "${callLog}"
    grep -qx 'nginx:stop:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}" || return 1
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    [[ "${nginxRuntimeState}" == "true" ]] || return 1
    ! grep -q '^queueApply$' "${callLog}"
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
        local args=("$@")
        if [[ "${args[$((${#args[@]} - 1))]}" == "${outputFile}" ]]; then
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
    local firewallLog="${root}/firewall.log"
    local errorLog="${root}/error.log"
    local startCalls=0
    local rc oldConfig

    mkdir -p "${configDir}"
    printf '{"inbounds":[{"type":"tuic","listen_port":26451}]}\n' >"${configDir}09_tuic_inbounds.json"
    printf '{"inbounds":[{"type":"vless","listen_port":2443}]}\n' >"${configDir}02_other_inbounds.json"
    printf '{"inbounds":[{"type":"tuic","listen_port":26451}]}\n' >"${configDir}config.json"
    oldConfig=$(<"${configDir}09_tuic_inbounds.json")
    : >"${serviceLog}"
    : >"${firewallLog}"
    : >"${errorLog}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    PADM_SINGBOX_BINARY="${root}/missing-sing-box"
    PADM_SINGBOX_SYSTEMD_SERVICE_FILE="${root}/sing-box.service"

    singBoxConfigPath="${configDir}"
    readInstallType() { singBoxConfigPath="${configDir}"; }
    readPortHopping() {
        tuicPortHoppingStart=
        tuicPortHoppingEnd=
    }
    singBoxRunning() { return 0; }
    coreStartupServiceEnabled() { return 1; }
    runCoreServiceActionAllowFailure() {
        printf '%s:%s\n' "$1" "$2" >>"${serviceLog}"
        if [[ "$2" == "start" ]]; then
            startCalls=$((startCalls + 1))
            [[ "${startCalls}" != "1" ]]
        fi
    }
    denyPort() {
        printf 'deny:%s:%s\n' "$1" "${2:-tcp}" >>"${firewallLog}"
    }

    if unInstallSingBox tuic; then
        rc=0
    else
        rc=$?
    fi
    [[ "${rc}" == "1" ]]
    [[ "$(<"${configDir}09_tuic_inbounds.json")" == "${oldConfig}" ]]
    [[ -f "${configDir}config.json" ]]
    [[ "${startCalls}" == "2" ]]
    [[ ! -s "${firewallLog}" ]]
    grep -q 'sing-box 服务重启失败，已恢复旧配置和服务状态' "${errorLog}"

    printf '{"inbounds":[{"type":"tuic","listen_port":26451}]}\n' >"${configDir}09_tuic_inbounds.json"
    rm -f "${configDir}config.json"
    : >"${serviceLog}"
    : >"${firewallLog}"
    : >"${errorLog}"
    singBoxRunning() { return 1; }
    runCoreServiceActionAllowFailure() { return 0; }
    readPortHopping() {
        tuicPortHoppingStart=33000
        tuicPortHoppingEnd=33005
    }
    deletePortHoppingRules() {
        printf 'hopping:%s:%s:%s:%s\n' "$1" "$2" "$3" "$4" >>"${firewallLog}"
    }
    unInstallSingBox tuic
    [[ ! -e "${configDir}09_tuic_inbounds.json" ]]
    [[ ! -e "${configDir}config.json" ]]
    grep -qx 'hopping:tuic:33000:33005:26451' "${firewallLog}"
    grep -qx 'deny:26451:tcp' "${firewallLog}"
    grep -qx 'deny:26451:udp' "${firewallLog}"

    local alpineConfigDir="${root}/alpine/conf/config/"
    local openRcService="${root}/alpine/sing-box"
    local rcUpdateLog="${root}/alpine/rc-update.log"
    mkdir -p "${alpineConfigDir}"
    printf '{"inbounds":[{"type":"hysteria2","listen_port":16295}]}\n' >"${alpineConfigDir}06_hysteria2_inbounds.json"
    printf '{"inbounds":[{"type":"hysteria2","listen_port":16295}]}\n' >"${alpineConfigDir}config.json"
    printf '#!/sbin/openrc-run\n' >"${openRcService}"
    : >"${rcUpdateLog}"
    : >"${firewallLog}"
    singBoxConfigPath="${alpineConfigDir}"
    PADM_SINGBOX_OPENRC_SERVICE_FILE="${openRcService}"
    release=alpine
    readInstallType() { singBoxConfigPath=; }
    readPortHopping() {
        hysteria2PortHoppingStart=
        hysteria2PortHoppingEnd=
    }
    coreStartupServiceEnabled() { return 0; }
    rc-update() {
        printf '%s\n' "$*" >>"${rcUpdateLog}"
    }
    cleanCoreInstallDirectory() { return 0; }
    unInstallSingBox hysteria2
    grep -qx 'del sing-box default' "${rcUpdateLog}"
    [[ ! -e "${openRcService}" ]]
    grep -qx 'deny:16295:tcp' "${firewallLog}"
    grep -qx 'deny:16295:udp' "${firewallLog}"

    singBoxConfigPath=
    release=debian
    : >"${serviceLog}"
    : >"${errorLog}"
    handleSingBox() {
        printf 'handle:%s\n' "$1" >>"${serviceLog}"
        return 1
    }
    runCoreServiceActionAllowFailure() { "$@"; }

    if unInstallSingBox >/dev/null 2>&1; then
        rc=0
    else
        rc=$?
    fi
    [[ "${rc}" == "1" ]]
    grep -qx 'handle:stop' "${serviceLog}"
    grep -q 'sing-box 服务停止失败，已取消卸载' "${errorLog}"
)

runSingBoxUninstallRejectsUnsafeConfigPathRegression() (
    local root="${TMP_DIR}/sing-box-uninstall-unsafe-config"
    local configDir="${root}/unsafe-config/"
    local errorLog="${root}/error.log"
    local rmLog="${root}/rm.log"
    local rc

    mkdir -p "${root}/unsafe-config"
    printf '{}\n' >"${configDir}config.json"
    printf 'keep\n' >"${root}/unsafe-config/sentinel"
    : >"${errorLog}"
    : >"${rmLog}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"

    singBoxConfigPath="relative-config/"
    readInstallType() { return 0; }
    handleSingBox() { return 0; }
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    set +e
    unInstallSingBox >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -f "${root}/unsafe-config/sentinel" ]]
    [[ ! -s "${rmLog}" ]]
    grep -q '路径异常' "${errorLog}"
)

runSingBoxManagedCleanupRegression() (
    local root="${TMP_DIR}/sing-box-managed-cleanup"
    local serviceLog="${root}/service.log"
    local registrationLog="${root}/registration.log"
    local rmLog="${root}/rm.log"
    local cleanupLog="${root}/cleanup.log"

    mkdir -p "${root}"
    : >"${serviceLog}"
    : >"${registrationLog}"
    : >"${rmLog}"
    : >"${cleanupLog}"

    readInstallType() { return 0; }
    cleanCoreInstallDirectory() {
        printf 'clean-core:%s:%s\n' "$1" "$2" >>"${cleanupLog}"
        return 0
    }
    handleSingBox() {
        printf 'handle:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        return 0
    }
    coreStartupServiceEnabled() { return 0; }
    systemctl() {
        printf '%s\n' "$*" >>"${registrationLog}"
        return 0
    }
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        return 0
    }

    release=debian
    singBoxConfigPath=
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    unInstallSingBox >/dev/null 2>&1
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    grep -qx 'handle:stop:true' "${serviceLog}"
    grep -qx 'disable sing-box.service' "${registrationLog}"
    grep -qx 'daemon-reload' "${registrationLog}"
    grep -qx 'rm:-f -- /etc/systemd/system/sing-box.service' "${rmLog}"
    grep -qx 'clean-core:/etc/padm/sing-box:sing-box' "${cleanupLog}"

    : >"${serviceLog}"
    : >"${rmLog}"
    : >"${cleanupLog}"
    cleanDirectoryContent() {
        printf 'clean-dir:%s\n' "$1" >>"${cleanupLog}"
        return 0
    }

    SERVICE_QUEUE_ALLOW_FAILURE=previous
    cleanUp singBoxDel >/dev/null 2>&1
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    grep -qx 'handle:stop:true' "${serviceLog}"
    grep -qx 'rm:-f -- /etc/padm/sing-box/conf/config.json' "${rmLog}"
    grep -qx 'clean-dir:/etc/padm/sing-box/conf/config' "${cleanupLog}"
)

runSingBoxLogTransactionRegression() (
    local root="${TMP_DIR}/sing-box-log-transaction"
    local targetPath="${root}/conf/config/log.json"
    local serviceLog="${root}/service.log"
    local errorLog="${root}/error.log"
    local applyMode rc keptBackup

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
    ! compgen -G "${targetPath}.bak.*" >/dev/null || return 1

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
    ! compgen -G "${targetPath}.bak.*" >/dev/null || return 1

    printf '{"log":{"disabled":true,"level":"warning"}}\n' >"${targetPath}" || return 1
    : >"${serviceLog}" || return 1
    : >"${errorLog}" || return 1
    applyMode=fail
    PADM_REGRESSION_APPLY_MODE="${applyMode}" \
        PADM_SINGBOX_LOG_CONFIG_FILE="${targetPath}" \
        bash -c '
            set +e
            source "$1/shell/core/runtime.sh"
            source "$1/shell/core/services.sh"
            source "$1/shell/core/cores.sh"
            serviceLog=$2
            errorLog=$3
            rcFile=$4
            serviceQueueRestart() {
                printf "restart:%s\n" "$1" >>"${serviceLog}"
                return 0
            }
            serviceQueueApply() {
                printf "apply:%s\n" "${PADM_REGRESSION_APPLY_MODE}" >>"${serviceLog}"
                return 1
            }
            errorCard() { printf "%s\n" "$*" >>"${errorLog}"; }
            restoreManagedFileFromBackup() { return 1; }
            singBoxLog false >/dev/null 2>&1
            printf "%s\n" "$?" >"${rcFile}"
        ' _ "${PROJECT_ROOT}" "${serviceLog}" "${errorLog}" "${root}/sing-box-log-restore-fail.rc" || return 1
    rc=$(<"${root}/sing-box-log-restore-fail.rc") || return 1
    [[ "${rc}" == "1" ]] || return 1
    jq -e '.log.disabled == false and .log.level == "debug" and .log.output == "/etc/padm/sing-box/conf/box.log"' "${targetPath}" >/dev/null || return 1
    grep -qx 'restart:sing-box' "${serviceLog}" || return 1
    grep -qx 'apply:fail' "${serviceLog}" || return 1
    grep -q '旧配置恢复失败' "${errorLog}" || return 1
    keptBackup=$(compgen -G "${targetPath}.bak.*" | head -n 1) || true
    [[ -n "${keptBackup}" && -f "${keptBackup}" ]] || return 1
    jq -e '.log.disabled == true and .log.level == "warning"' "${keptBackup}" >/dev/null || return 1
    rm -f "${keptBackup}" || return 1
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
    ! compgen -G "${targetPath}.bak.*" >/dev/null || return 1
    return 0
)

runSingBoxProtocolReloadFailureRegression() (
    local root="${TMP_DIR}/sing-box-protocol-reload-failure"
    local reachedFile="${root}/accounts"
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
    showAccounts() {
        printf 'accounts\n' >"${reachedFile}"
        return 0
    }

    set +e
    singBoxTuicInstall >/dev/null 2>&1
    tuicRc=$?
    set -e
    [[ "${tuicRc}" == "1" ]]
    grep -qx 'config:custom 2 true' "${callLog}"
    grep -qx 'reload' "${callLog}"
    [[ ! -e "${reachedFile}" ]]

    : >"${callLog}"
    rm -f "${reachedFile}"
    set +e
    singBoxHysteria2Install >/dev/null 2>&1
    hysteriaRc=$?
    set -e
    [[ "${hysteriaRc}" == "1" ]]
    grep -qx 'config:custom 2 true' "${callLog}"
    grep -qx 'reload' "${callLog}"
    [[ ! -e "${reachedFile}" ]]
)

runGeoUpdateReloadFailureRegression() (
    local root="${TMP_DIR}/geo-update-reload-failure"
    local callLog="${root}/calls.log"
    local statusLog="${root}/status.log"
    local geoVersionFile="${root}/geo-version.txt"
    local geoCronLog="${root}/geo-cron.log"
    local handlerSource
    local mode=reload-fail
    local rc

    mkdir -p "${root}"
    : >"${callLog}"
    : >"${statusLog}"
    printf 'old-version\n' >"${geoVersionFile}"
    ensureXrayGeoFiles() {
        printf 'geo:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" == "ensure-fail" ]] && return 1
        printf 'new-version\n' >"${geoVersionFile}"
        return 0
    }
    xrayGeoDisplayVersion() {
        cat "${geoVersionFile}"
    }
    reloadCore() {
        printf 'reload\n' >>"${callLog}"
        return 1
    }
    statusCard() {
        printf '%s\n' "$*" >>"${statusLog}"
    }

    mode=ensure-fail
    set +e
    updateGeoSite >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'geo:/etc/padm/xray force' "${callLog}"
    ! grep -q '^reload$' "${callLog}"

    mode=reload-fail
    : >"${callLog}"
    printf 'old-version\n' >"${geoVersionFile}"
    set +e
    updateGeoSite >/dev/null 2>&1
    rc=$?
    set -e

    [[ "${rc}" == "1" ]]
    grep -qx 'geo:/etc/padm/xray force' "${callLog}"
    grep -qx 'reload' "${callLog}"
    grep -q '核心重载失败' "${statusLog}"
    ! grep -q '更新完毕' "${statusLog}"

    handlerSource=$(awk '/^handleScriptCommand\(\)/,/^}/ { print }' "${PROJECT_ROOT}/install.sh")
    handlerSource=${handlerSource//\/etc\/padm\/crontab_updateGeoSite.log/${geoCronLog}}
    eval "${handlerSource}"
    updateGeoSite() {
        printf 'geo-failed\n'
        return 23
    }
    cronName=UpdateGeo
    : >"${geoCronLog}"
    set +e
    (handleScriptCommand)
    rc=$?
    set -e
    [[ "${rc}" == "23" ]]
    ! grep -q 'geo更新日期:' "${geoCronLog}"

    updateGeoSite() {
        printf 'geo-updated\n'
        return 0
    }
    : >"${geoCronLog}"
    set +e
    (handleScriptCommand)
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
    grep -q '^geo-updated$' "${geoCronLog}"
    grep -q '^geo更新日期:' "${geoCronLog}"
)

runXrayGeoCommitRollbackRegression() (
    local root="${TMP_DIR}/xray-geo-commit-rollback"
    local stageDir="${root}/stage"
    local targetDir="${root}/target"
    local rc
    local preservedBackupDir=

    mkdir -p "${stageDir}" "${targetDir}"
    printf 'old-geosite\n' >"${targetDir}/geosite.dat"
    printf 'old-geoip\n' >"${targetDir}/geoip.dat"
    printf 'old-version\n' >"${targetDir}/geo.version"
    printf 'new-geosite\n' >"${stageDir}/geosite.dat"
    printf 'new-geoip\n' >"${stageDir}/geoip.dat"

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        local targetFile=$2
        [[ "${targetFile}" == "${targetDir}/geoip.dat" ]] && return 1
        originalCommitGeneratedFile "$@"
    }
    padmForgetCleanupPath() {
        [[ "$1" == *padm-xray-geo-backup.* ]] && preservedBackupDir=$1
    }

    set +e
    commitXrayGeoFilesFromStage "${stageDir}" "${targetDir}" v-new
    rc=$?
    set -e

    [[ "${rc}" == "1" ]]
    [[ "$(<"${targetDir}/geosite.dat")" == "old-geosite" ]]
    [[ "$(<"${targetDir}/geoip.dat")" == "old-geoip" ]]
    [[ "$(<"${targetDir}/geo.version")" == "old-version" ]]
    [[ -n "${preservedBackupDir}" && -d "${preservedBackupDir}" ]]
    rm -rf -- "${preservedBackupDir}"
)

runCoreCleanupFailurePropagationRegression() (
    local root="${TMP_DIR}/core-cleanup-failure"
    local serviceLog="${root}/service.log"
    local rmLog="${root}/rm.log"
    local errorLog="${root}/error.log"
    local reachedFile="${root}/reached"
    local queueLog="${root}/queue.log"
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
    : >"${queueLog}"
    command rm -f "${reachedFile}"
    readLastInstallationConfig() { return 0; }
    unInstallSubscribe() { return 0; }
    installTools() { return 0; }
    installSingBox() { return 0; }
    installSingBoxService() { return 0; }
    initSingBoxConfig() { return 0; }
    serviceQueueRestart() {
        printf 'restart:%s\n' "$1" >>"${queueLog}"
        return 0
    }
    serviceQueueApply() {
        printf 'apply\n' >>"${queueLog}"
        return 0
    }
    checkGFWStatue() {
        printf 'reached\n' >"${reachedFile}"
        return 0
    }
    showAccounts() {
        printf 'reached\n' >"${reachedFile}"
        return 0
    }

    set +e
    installSingBoxReality >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'xray:stop:true' "${serviceLog}"
    [[ ! -s "${rmLog}" ]]
    [[ ! -s "${queueLog}" ]]
    [[ ! -e "${reachedFile}" ]]
)

runReloadCorePropagationRegression() (
    local root="${TMP_DIR}/reload-core-propagation"
    local alpnConfig="${root}/alpn.json"
    local vlessConfig="${root}/vless.json"
    local vlessState="${root}/vless-state.json"
    local fakeXray="${root}/xray"
    local refreshMarker="${root}/refresh"
    local subscribeMarker="${root}/subscribe"
    local reloadLog="${root}/reloads"
    local originalContent rc

    mkdir -p "${root}/nginx"
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
    set +e
    applyTraditionalTlsAlpn '["h2","http/1.1"]' >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${alpnConfig}")" == "${originalContent}" ]]
    [[ "$(wc -l <"${reloadLog}" | tr -d ' ')" == "2" ]]

    printf '%s\n' "${originalContent}" >"${alpnConfig}"
    rm -f "${alpnConfig}.alpn.bak"
    (
        cp() {
            if [[ "$1" == "-p" && "$2" == "${alpnConfig}.alpn.bak" && "$3" == "${alpnConfig}.tmp" ]]; then
                return 1
            fi
            command cp "$@"
        }
        set +e
        applyTraditionalTlsAlpn '["h2","http/1.1"]' >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        jq -e '.inbounds[0].streamSettings.tlsSettings.alpn == ["h2","http/1.1"]' "${alpnConfig}" >/dev/null
        [[ "$(<"${alpnConfig}.alpn.bak")" == "${originalContent}" ]]
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
            if [[ "$1" == "-p" && "$2" == "${vlessConfig}" && "$3" == "${vlessConfig}.vlessenc.bak.tmp" ]]; then
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
            if [[ "$1" == "${vlessState}.tmp" && "$2" == "${vlessState}" ]] ||
                [[ "$1" == "-f" && "$2" == "--" && "$3" == "${vlessState}.tmp" && "$4" == "${vlessState}" ]]; then
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
            if [[ "$1" == "${vlessConfig}.tmp" && "$2" == "${vlessConfig}" ]] ||
                [[ "$1" == "-f" && "$2" == "--" && "$3" == "${vlessConfig}.vlessenc" && "$4" == "${vlessConfig}" ]]; then
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

runConfigTransactionRegression() (
    local tmpRoot
    tmpRoot=$(cd -- "${TMP_DIR}" && pwd -P) || return 1
    local targetFile="${tmpRoot}/transaction.json"
    local backupFile="${targetFile}.bak"
    local stagedFile
    local originalContent updatedContent
    local reloadCountFile="${tmpRoot}/transaction-reload-count"
    local refreshCountFile="${tmpRoot}/transaction-refresh-count"
    local validateMode=success
    local reloadMode=success
    local refreshMode=success
    local oldPath="${PATH}"
    local oldTmpDir="${TMPDIR:-}"
    local checkPortTmpRootRel="${TMP_DIR}/check-port-tmp"
    local checkPortTmpRoot
    local checkPortNginxDirRel="${TMP_DIR}/check-port-nginx"
    local checkPortNginxDir checkPortTarget
    local fakeBinDirRel="${TMP_DIR}/fake-bin"
    local fakeBinDir="${tmpRoot}/fake-bin"
    mkdir -p "${checkPortTmpRootRel}" "${checkPortNginxDirRel}" "${fakeBinDirRel}"
    checkPortTmpRoot="$(cd -- "${checkPortTmpRootRel}" && pwd -P)"
    checkPortNginxDir="$(cd -- "${checkPortNginxDirRel}" && pwd -P)/"
    checkPortTarget="${checkPortNginxDir}checkPortOpen.conf"
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
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new"' "${targetFile}" >"${stagedFile}"
    validateMode=fail
    if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock; then
        return 1
    fi
    [[ "$(<"${targetFile}")" == "${originalContent}" ]]
    [[ ! -e "${stagedFile}" ]]
    [[ ! -e "${backupFile}" ]]
    [[ ! -e "${reloadCountFile}" ]]
    [[ ! -e "${refreshCountFile}" ]]

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    originalContent=$(<"${targetFile}")
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    validateMode=fail
    (
        cp() {
            local args=("$@")
            local targetPath="${args[$((${#args[@]} - 1))]}"
            if [[ "${targetPath}" == "${tmpRoot}"/.transaction.json.restore.* ]]; then
                return 1
            fi
            command cp "$@"
        }
        if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
            return 1
        fi
        [[ "$(<"${targetFile}")" != "${originalContent}" ]]
        jq -e '.mode == "new" and .port == 8443' "${targetFile}" >/dev/null
        [[ "$(<"${backupFile}")" == "${originalContent}" ]]
        [[ ! -e "${stagedFile}" ]]
        [[ ! -e "${reloadCountFile}" ]]
        [[ ! -e "${refreshCountFile}" ]]
    ) || return 1

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    local validateFailureLog="${tmpRoot}/transaction-validate-failure.log"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    validateMode=fail
    (
        menuLine() { printf '%s\n' "$*" >>"${validateFailureLog}"; }
        echoContent() { :; }
        menuClose() { :; }
        cp() {
            local args=("$@")
            local targetPath="${args[$((${#args[@]} - 1))]}"
            if [[ "${targetPath}" == "${tmpRoot}"/.transaction.json.restore.* ]]; then
                return 1
            fi
            command cp "$@"
        }
        if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
            return 1
        fi
        grep -qx "配置校验失败，且回滚配置失败，请手动检查 ${targetFile} 和 ${backupFile}" "${validateFailureLog}"
    ) || return 1

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    rm -f "${backupFile}"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    validateMode=success
    configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock
    updatedContent=$(<"${targetFile}")
    [[ "${updatedContent}" != "${originalContent}" ]]
    jq -e '.mode == "new" and .port == 8443' "${targetFile}" >/dev/null
    [[ ! -e "${stagedFile}" ]]
    [[ ! -e "${backupFile}" ]]
    [[ "$(wc -l <"${reloadCountFile}" | tr -d ' ')" == "1" ]]
    [[ "$(wc -l <"${refreshCountFile}" | tr -d ' ')" == "1" ]]

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    originalContent=$(<"${targetFile}")
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    reloadMode=fail
    refreshMode=success
    if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(<"${targetFile}")" == "${originalContent}" ]]
    [[ ! -e "${stagedFile}" ]]
    [[ ! -e "${backupFile}" ]]
    [[ "$(wc -l <"${reloadCountFile}" | tr -d ' ')" == "2" ]]
    [[ ! -e "${refreshCountFile}" ]]

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    local reloadFailureLog="${tmpRoot}/transaction-reload-failure.log"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    reloadMode=fail
    refreshMode=success
    (
        menuLine() { printf '%s\n' "$*" >>"${reloadFailureLog}"; }
        echoContent() { :; }
        menuClose() { :; }
        cp() {
            local args=("$@")
            local targetPath="${args[$((${#args[@]} - 1))]}"
            if [[ "${targetPath}" == "${tmpRoot}"/.transaction.json.restore.* ]]; then
                return 1
            fi
            command cp "$@"
        }
        if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
            return 1
        fi
        grep -qx "核心重载失败，且回滚配置失败，请手动检查 ${targetFile} 和 ${backupFile}" "${reloadFailureLog}"
    ) || return 1

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    reloadMode=success
    refreshMode=fail
    if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
        return 1
    fi
    jq -e '.mode == "new" and .port == 8443' "${targetFile}" >/dev/null
    [[ ! -e "${stagedFile}" ]]
    [[ ! -e "${backupFile}" ]]
    [[ "$(wc -l <"${reloadCountFile}" | tr -d ' ')" == "1" ]]
    [[ "$(wc -l <"${refreshCountFile}" | tr -d ' ')" == "1" ]]
    refreshMode=success

    local refreshFailureLog="${tmpRoot}/transaction-refresh-failure.log"
    local localSubscribeBase
    mkdir -p "${TMP_DIR}/subscribe_local/default" "${TMP_DIR}/subscribe_local/clashMeta" "${TMP_DIR}/subscribe_local/sing-box"
    PADM_SUBSCRIBE_LOCAL_DIR="${tmpRoot}/subscribe_local"
    localSubscribeBase=$(subscribeLocalBaseDir)
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
    : >"${refreshFailureLog}"
    if refreshXHTTPSubscriptions >/dev/null 2>&1; then
        return 1
    fi
    grep -qx 'subscribe:renew' "${refreshFailureLog}"

    readNginxSubscribe() {
        subscribePort=
        nginxConfigPath="${TMP_DIR}/nginx-refresh/"
    }
    : >"${refreshFailureLog}"
    if refreshTuicSubscriptions >/dev/null 2>&1; then
        return 1
    fi
    grep -qx 'showAccounts' "${refreshFailureLog}"

    (
        cleanDirectoryContent() {
            printf 'cleanDirectoryContent\n' >>"${refreshFailureLog}"
            return 1
        }
        showAccounts() {
            printf 'showAccounts\n' >>"${refreshFailureLog}"
            return 0
        }
        readNginxSubscribe() {
            subscribePort=
            nginxConfigPath="${TMP_DIR}/nginx-refresh/"
        }
        : >"${refreshFailureLog}"
        set +e
        refreshVlessEncryptionSubscriptions >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -qx 'cleanDirectoryContent' "${refreshFailureLog}"
        ! grep -q '^showAccounts$' "${refreshFailureLog}"
    ) || return 1

    cat >"${fakeBinDir}/nginx" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "-t" ]]
printf 'check-port validate %s\n' "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}"
[[ "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}" == "success" ]]
SH
    chmod +x "${fakeBinDir}/nginx"
    PATH="${fakeBinDir}:${PATH}"
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
        restoreManagedFileFromBackup() { return 1; }
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
)

runNginxServiceFailureRegression() (
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
    printf '%s\n' "$*" >>"${PADM_FAKE_SYSTEMCTL_ACTIONS:-/dev/null}"
    if [[ "${PADM_FAKE_SYSTEMCTL_RETRY_ONCE:-false}" == "true" && ! -e "${PADM_FAKE_SYSTEMCTL_RETRY_MARKER}" ]]; then
        : >"${PADM_FAKE_SYSTEMCTL_RETRY_MARKER}"
        printf 'See "journalctl -xe" for details\n' >&2
        exit 1
    fi
    [[ "${PADM_FAKE_SYSTEMCTL_START_RC:-0}" == "0" ]] || exit "${PADM_FAKE_SYSTEMCTL_START_RC}"
    printf '%s\n' "${PADM_FAKE_SYSTEMCTL_START_STATE:-true}" >"${PADM_FAKE_NGINX_STATE_FILE}"
    ;;
stop)
    printf '%s\n' "$*" >>"${PADM_FAKE_SYSTEMCTL_ACTIONS:-/dev/null}"
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
    errorCard() { return 0; }
    export PADM_NGINX_ERROR_LOG="${serviceTmp}/nginx-error.log"
    eval "$(declare -f updateSELinuxHTTPPortT | sed '1s/^updateSELinuxHTTPPortT/originalUpdateSELinuxHTTPPortT/')"
    journalctl() { printf '31300 Permission denied\n'; }
    getenforce() { printf 'Enforcing\n'; }
    semanage() {
        if [[ "$1" == "port" && "$2" == "-l" ]]; then
            printf 'http_port_t tcp 80\n'
            return 0
        fi
        return 1
    }
    if originalUpdateSELinuxHTTPPortT >/dev/null 2>&1; then
        return 1
    fi
    unset -f journalctl getenforce semanage
    updateSELinuxHTTPPortT() {
        printf 'update\n' >>"${serviceTmp}/selinux-update"
        return 0
    }
    protocolSelectionSkipsNginx() { return 1; }
    nginxServiceInstalled() { return 0; }
    padmReadProcExe() {
        [[ "$1" == "/proc/12345/exe" && "$(cat "${PADM_FAKE_NGINX_STATE_FILE}" 2>/dev/null)" == "true" ]] || return 1
        printf '/usr/sbin/nginx\n'
    }
    padmReadProcCmdline() {
        [[ "$1" == "/proc/12345/cmdline" && "$(cat "${PADM_FAKE_NGINX_STATE_FILE}" 2>/dev/null)" == "true" ]] || return 1
        printf 'nginx: master process nginx\n'
    }
    release=centos
    selectCustomInstallType=
    btDomain=
    SERVICE_QUEUE_ALLOW_FAILURE=true
    export PADM_FAKE_NGINX_STATE_FILE="${serviceTmp}/nginx-running"
    export PADM_NGINX_ERROR_LOG="${serviceTmp}/nginx-error.log"
    export PADM_FAKE_SYSTEMCTL_ACTIONS="${serviceTmp}/systemctl-actions"
    export PADM_FAKE_SYSTEMCTL_RETRY_MARKER="${serviceTmp}/selinux-retry"
    export PADM_FAKE_NGINX_FORCE_KILL_LOG="${serviceTmp}/nginx-force-kill"
    xargs() { printf '%s\n' "$*" >>"${PADM_FAKE_NGINX_FORCE_KILL_LOG}"; }

    printf 'false\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
    PADM_FAKE_SYSTEMCTL_START_RC=0 PADM_FAKE_SYSTEMCTL_START_STATE=false handleNginx start >/dev/null 2>&1 && return 1
    printf 'true\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
    if PADM_FAKE_SYSTEMCTL_STOP_RC=0 PADM_FAKE_SYSTEMCTL_STOP_STATE=true handleNginx stop >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(cat "${PADM_FAKE_NGINX_STATE_FILE}")" == "true" ]]
    printf 'false\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
    PADM_FAKE_SYSTEMCTL_START_RC=0 PADM_FAKE_SYSTEMCTL_START_STATE=true handleNginx start >/dev/null 2>&1
    printf 'true\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
    PADM_FAKE_SYSTEMCTL_STOP_RC=0 PADM_FAKE_SYSTEMCTL_STOP_STATE=false handleNginx stop >/dev/null 2>&1

    : >"${PADM_FAKE_NGINX_FORCE_KILL_LOG}"
    printf 'true\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
    if PADM_FAKE_SYSTEMCTL_STOP_RC=1 handleNginx stop >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(<"${PADM_FAKE_NGINX_STATE_FILE}")" == "true" ]]
    [[ ! -s "${PADM_FAKE_NGINX_FORCE_KILL_LOG}" ]]

    mkdir -p "${serviceTmp}/nginx"
    nginxConfigPath="${serviceTmp}/nginx/"
    selectCustomInstallType=",1,"
    protocolSelectionSkipsNginx() { return 0; }
    subscriptionWireGuardControlEnabled() { return 1; }
    printf 'false\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
    handleNginx start >/dev/null 2>&1
    [[ "$(<"${PADM_FAKE_NGINX_STATE_FILE}")" == "false" ]]
    handleNginx start restore >/dev/null 2>&1
    [[ "$(<"${PADM_FAKE_NGINX_STATE_FILE}")" == "true" ]] || return 1
    handleNginx stop >/dev/null 2>&1
    : >"${nginxConfigPath}subscribe.conf"
    handleNginx start >/dev/null 2>&1
    [[ "$(<"${PADM_FAKE_NGINX_STATE_FILE}")" == "true" ]]
    rm -f "${nginxConfigPath}subscribe.conf"
    handleNginx stop >/dev/null 2>&1
    : >"${nginxConfigPath}padm-control-wg.conf"
    handleNginx start >/dev/null 2>&1
    [[ "$(<"${PADM_FAKE_NGINX_STATE_FILE}")" == "true" ]]
    rm -f "${nginxConfigPath}padm-control-wg.conf"
    handleNginx stop >/dev/null 2>&1
    subscriptionWireGuardControlEnabled() { return 0; }
    handleNginx start >/dev/null 2>&1
    [[ "$(<"${PADM_FAKE_NGINX_STATE_FILE}")" == "true" ]]
    subscriptionWireGuardControlEnabled() { return 1; }
    SERVICE_ACTIONS=
    serviceQueueRestart nginx
    serviceQueueApply >/dev/null 2>&1
    [[ "$(<"${PADM_FAKE_NGINX_STATE_FILE}")" == "true" ]] || return 1
    protocolSelectionSkipsNginx() { return 1; }
    subscriptionWireGuardControlEnabled() { return 1; }

    : >"${PADM_FAKE_SYSTEMCTL_ACTIONS}"
    rm -f "${PADM_FAKE_SYSTEMCTL_RETRY_MARKER}"
    export PADM_FAKE_SYSTEMCTL_RETRY_ONCE=true
    printf 'false\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
    if ! handleNginx start >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(<"${PADM_FAKE_NGINX_STATE_FILE}")" == "true" ]]
    [[ "$(grep -c '^start nginx$' "${PADM_FAKE_SYSTEMCTL_ACTIONS}")" == "2" ]]
    [[ "$(grep -c '^update$' "${serviceTmp}/selinux-update")" == "1" ]]
    unset PADM_FAKE_SYSTEMCTL_RETRY_ONCE

    printf 'false\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
    SERVICE_ACTIONS=
    serviceQueueStart nginx
    serviceQueueStop nginx
    if PADM_FAKE_SYSTEMCTL_START_RC=0 PADM_FAKE_SYSTEMCTL_START_STATE=false serviceQueueApply >/dev/null 2>&1; then
        return 1
    fi
    [[ -z "${SERVICE_ACTIONS}" ]]

    local xrayWaitLog="${serviceTmp}/xray-wait.log"
    find() {
        if [[ "$*" == *'systemctl'* ]]; then
            printf '/usr/bin/systemctl\n'
            return 0
        fi
        if [[ "$*" == *'xray.service'* ]]; then
            printf '/etc/systemd/system/xray.service\n'
            return 0
        fi
        command find "$@"
    }
    systemctl() { return 0; }
    xrayRunning() { return 0; }
    waitForServiceState() {
        printf '%s:%s:%s:%s\n' "$1" "$2" "$3" "$4" >>"${xrayWaitLog}"
        return 0
    }
    handleXray stop >/dev/null
    if ! grep -qx 'xrayRunning:stopped:60:0.1' "${xrayWaitLog}"; then
        cat "${xrayWaitLog}" >&2 || true
        return 1
    fi

    local xrayStartLimitLog="${serviceTmp}/xray-start-limit.log"
    local xrayRunningState="${serviceTmp}/xray-running"
    : >"${xrayStartLimitLog}"
    printf 'false\n' >"${xrayRunningState}"
    xrayRunning() {
        [[ "$(<"${xrayRunningState}")" == "true" ]]
    }
    waitForServiceState() {
        printf '%s:%s:%s:%s\n' "$1" "$2" "$3" "$4" >>"${xrayWaitLog}"
        [[ "${2}" == "running" ]] && xrayRunning
    }
    systemctl() {
        printf '%s\n' "$*" >>"${xrayStartLimitLog}"
        case "$1" in
        start)
            if ! grep -qx 'reset-failed xray.service' "${xrayStartLimitLog}"; then
                return 1
            fi
            printf 'true\n' >"${xrayRunningState}"
            return 0
            ;;
        reset-failed)
            return 0
            ;;
        esac
        return 0
    }
    SERVICE_QUEUE_ALLOW_FAILURE=true
    if ! handleXray start >/dev/null 2>&1; then
        cat "${xrayStartLimitLog}" >&2 || true
        cat "${xrayWaitLog}" >&2 || true
        return 1
    fi
    grep -qx 'reset-failed xray.service' "${xrayStartLimitLog}" || return 1
    [[ "$(grep -c '^start xray.service$' "${xrayStartLimitLog}")" == "2" ]] || return 1
    grep -qx 'xrayRunning:running:25:0.1' "${xrayWaitLog}" || return 1
    [[ "$(<"${xrayRunningState}")" == "true" ]] || return 1
    rm -rf "${serviceTmp}"
)


runUninstallWireGuardCleanupRegression() (
    local actions=
    local mode=success
    local rc
    local targetDir="${TMP_DIR}/uninstall-wireguard"
    local oldWireGuardDir="${PADM_WIREGUARD_CONTROL_DIR:-}"
    PADM_WIREGUARD_CONTROL_DIR="${targetDir}/state"
    mkdir -p "${PADM_WIREGUARD_CONTROL_DIR}" "${targetDir}/etc-wireguard" "${targetDir}/systemd"
    subscriptionWireGuardWriteState '.enabled = true'
    printf 'private\n' >"$(subscriptionWireGuardPrivateKeyFile)"
    printf 'public\n' >"$(subscriptionWireGuardPublicKeyFile)"
    printf 'keep\n' >"${PADM_WIREGUARD_CONTROL_DIR}/unmanaged"
    removeInstallPath() { actions+="remove:$1:$2"$'\n'; rm -rf "$1"; }
    systemctl() {
        actions+="systemctl:$*"$'\n'
        if [[ "${mode}" == "wg-stop-fail" && "$*" == "disable --now wg-quick@wg-padm" ]]; then
            return 1
        fi
        if [[ "${mode}" == "control-stop-fail" && "$*" == "disable --now padm-subscription-control.service" ]]; then
            return 1
        fi
        return 0
    }
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

    for mode in wg-stop-fail control-stop-fail; do
        actions=
        set +e
        cleanupSubscriptionWireGuardControlOnUninstall >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ -e "$(subscriptionWireGuardConfigFile)" ]]
        [[ -e "$(subscriptionWireGuardStateFile)" ]]
        [[ -e "$(subscriptionWireGuardPrivateKeyFile)" ]]
        [[ -e "$(subscriptionWireGuardPublicKeyFile)" ]]
        [[ -e "$(subscriptionControlServiceFile)" ]]
    done

    mode=success
    actions=
    cleanupSubscriptionWireGuardControlOnUninstall
    grep -qxF 'systemctl:disable --now wg-quick@wg-padm' <<<"${actions}"
    grep -qxF 'systemctl:disable --now padm-subscription-control.service' <<<"${actions}"
    [[ ! -e "$(subscriptionWireGuardConfigFile)" ]]
    [[ ! -e "$(subscriptionWireGuardStateFile)" ]]
    [[ ! -e "$(subscriptionWireGuardPrivateKeyFile)" ]]
    [[ ! -e "$(subscriptionWireGuardPublicKeyFile)" ]]
    [[ ! -e "$(subscriptionControlServiceFile)" ]]
    [[ -e "${PADM_WIREGUARD_CONTROL_DIR}/unmanaged" ]]

    local nginxTarget="${targetDir}/nginx/padm-control-wg.conf"
    local nginxBackupDir=
    local nginxRuntimeState=true
    mkdir -p "$(dirname "${nginxTarget}")"
    printf 'old-nginx\n' >"${nginxTarget}"
    checkLogBackupCreate nginxBackupDir "${nginxTarget}"
    printf 'new-nginx\n' >"${nginxTarget}"
    actions=
    subscriptionWireGuardWriteState() { actions+="state-restored"$'\n'; return 0; }
    applySubscriptionWireGuardService() { actions+="wireguard-restored"$'\n'; return 0; }
    nginxRunning() { [[ "${nginxRuntimeState}" == "true" ]]; }
    handleNginx() {
        actions+="nginx:$1:${SERVICE_QUEUE_ALLOW_FAILURE:-}"$'\n'
        [[ -n "${2:-}" ]] && actions+="nginx-mode:$*"$'\n'
        [[ "$1" == "start" ]] && nginxRuntimeState=true
        [[ "$1" == "stop" ]] && nginxRuntimeState=false
        return 0
    }
    subscriptionWireGuardRestoreStateAndConfig \
        '{"enabled":true,"address":"10.77.0.2/24"}' \
        "${nginxBackupDir}" \
        true
    grep -qxF 'old-nginx' "${nginxTarget}"
    [[ "${nginxRuntimeState}" == "true" ]]
    grep -qx 'nginx:stop:true' <<<"${actions}"
    grep -qx 'nginx:start:true' <<<"${actions}"
    grep -qx 'nginx-mode:start restore' <<<"${actions}" || return 1
    [[ ! -e "${nginxBackupDir}" ]]

    printf 'old-nginx-after-state-failure\n' >"${nginxTarget}"
    checkLogBackupCreate nginxBackupDir "${nginxTarget}"
    printf 'new-nginx-after-state-failure\n' >"${nginxTarget}"
    actions=
    subscriptionWireGuardWriteState() { actions+="state-restore-failed"$'\n'; return 1; }
    set +e
    subscriptionWireGuardRestoreStateAndConfig \
        '{"enabled":true,"address":"10.77.0.2/24"}' \
        "${nginxBackupDir}" \
        true
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qxF 'old-nginx-after-state-failure' "${nginxTarget}"
    [[ "${nginxRuntimeState}" == "true" ]]
    grep -qx 'state-restore-failed' <<<"${actions}"
    grep -qx 'nginx:stop:true' <<<"${actions}"
    grep -qx 'nginx:start:true' <<<"${actions}"
    [[ -d "${nginxBackupDir}" ]]
    padmRemoveCleanupPath "${nginxBackupDir}"

    if [[ -n "${oldWireGuardDir}" ]]; then PADM_WIREGUARD_CONTROL_DIR="${oldWireGuardDir}"; else unset PADM_WIREGUARD_CONTROL_DIR; fi
)

runWarpConfigSafeDirRegression() (
    local root="${TMP_DIR}/warp-config-safe-dir"
    local rmLog="${root}/rm.log"
    local errorLog="${root}/error.log"
    local rc

    mkdir -p "${root}"
    : >"${rmLog}"
    : >"${errorLog}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"

    PADM_WARP_DIR=relative-warp
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    set +e
    readConfigWarpReg >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -s "${rmLog}" ]]
    [[ ! -s "${errorLog}" ]]

    set +e
    installWarpReg >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -s "${rmLog}" ]]
    [[ ! -s "${errorLog}" ]]

    (
        source "${PROJECT_ROOT}/shell/core/routing_warp.sh"
        PADM_WARP_DIR="${root}/warp-stale"
        warpRegCoreCPUVendor="warp-reg-linux-amd64"
        local downloadMarker="${root}/warp-stale-download"
        mkdir -p "${PADM_WARP_DIR}"
        printf 'stale\n' >"${PADM_WARP_DIR}/warp-reg"
        chmod 644 "${PADM_WARP_DIR}/warp-reg"
        echoContent() { :; }
        menuLine() { :; }
        menuClose() { :; }
        autoRead() { printf -v "$3" y; }
        errorCard() { :; }
        downloadGitHubReleaseAsset() {
            : >"${downloadMarker}"
            printf '#!/usr/bin/env sh\n' >"${2%/}/$5"
        }
        installWarpReg
        [[ -e "${downloadMarker}" ]]
        [[ -x "${PADM_WARP_DIR}/warp-reg" ]]
    )

    (
        source "${PROJECT_ROOT}/shell/core/routing_warp.sh"
        PADM_WARP_DIR="${root}/warp-download-fail"
        warpRegCoreCPUVendor="warp-reg-linux-amd64"
        local callerMarker="${root}/warp-caller-reached"
        mkdir -p "${PADM_WARP_DIR}"
        echoContent() { :; }
        menuLine() { :; }
        menuClose() { :; }
        autoRead() { printf -v "$3" y; }
        errorCard() { :; }
        downloadGitHubReleaseAsset() { return 1; }
        set +e
        installWarpReg >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        : >"${callerMarker}"
        [[ -f "${callerMarker}" ]]
    )

    local cancelMarker="${root}/warp-cancel-caller-reached"
    (
        source "${PROJECT_ROOT}/shell/core/routing_warp.sh"
        PADM_WARP_DIR="${root}/warp-cancel"
        warpRegCoreCPUVendor="warp-reg-linux-amd64"
        mkdir -p "${PADM_WARP_DIR}"
        echoContent() { :; }
        menuLine() { :; }
        menuClose() { :; }
        autoRead() { printf -v "$3" n; }
        coreCancelledStatusCard() { :; }
        set +e
        installWarpReg >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        : >"${cancelMarker}"
    )
    [[ -f "${cancelMarker}" ]]

    (
        source "${PROJECT_ROOT}/shell/core/routing_warp.sh"
        PADM_WARP_DIR="${root}/warp-latest"
        warpRegCoreCPUVendor="warp-reg-linux-amd64"
        local versionLog="${root}/warp-download-version.log"
        mkdir -p "${PADM_WARP_DIR}"
        echoContent() { :; }
        menuLine() { :; }
        menuClose() { :; }
        autoRead() { printf -v "$3" y; }
        errorCard() { return 1; }
        downloadGitHubReleaseAsset() {
            [[ "$1" == "-P" && "$3" == "badafans/warp-reg" && "$4" == "v1.0" && "$5" == "${warpRegCoreCPUVendor}" ]] || return 1
            printf '%s\n' "$4" >"${versionLog}"
            printf '#!/usr/bin/env sh\n' >"${2%/}/$5"
        }
        installWarpReg >/dev/null 2>&1
        [[ "$(<"${versionLog}")" == "v1.0" ]]
        [[ -s "${PADM_WARP_DIR}/warp-reg" ]]
        [[ "$(stat -c '%a' "${PADM_WARP_DIR}/warp-reg")" == "755" ]]
    )

    (
        source "${PROJECT_ROOT}/shell/core/routing_warp.sh"
        coreInstallType=1
        configPath="${root}/xray/"
        singBoxConfigPath=
        mkdir -p "${configPath}"
        set +e
        unInstallWireGuard IPv4 >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
    )
    [[ ! -s "${rmLog}" ]]
)

runWireGuardControlSafeDirRegression() (
    local root="${TMP_DIR}/wireguard-control-safe-dir"
    local rmLog="${root}/rm.log"
    local rc

    mkdir -p "${root}"
    : >"${rmLog}"
    PADM_WIREGUARD_CONTROL_DIR=relative-wireguard

    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    set +e
    subscriptionWireGuardWriteState '.enabled = true' >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -s "${rmLog}" ]]
    [[ ! -e "${root}/relative-wireguard" ]]

    set +e
    subscriptionWireGuardEnsureKeys >/dev/null 2>&1
    rc=$?
    set -e
    unset -f rm
    [[ "${rc}" == "1" ]]
    [[ ! -s "${rmLog}" ]]
    [[ ! -e "${root}/relative-wireguard" ]]
)

runWireGuardKeyTransactionRegression() (
    local rootRel="${TMP_DIR}/wireguard-key-transaction"
    local root wireGuardDir privateKeyFile publicKeyFile
    local rc

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    wireGuardDir="${root}/wireguard"
    privateKeyFile="${wireGuardDir}/private.key"
    publicKeyFile="${wireGuardDir}/public.key"
    PADM_WIREGUARD_CONTROL_DIR="${wireGuardDir}"

    wg() {
        case "${1:-}" in
        genkey)
            printf 'generated-private-key\n'
            ;;
        pubkey)
            cat >/dev/null
            printf 'generated-public-key\n'
            ;;
        *)
            return 1
            ;;
        esac
    }

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${publicKeyFile}" ]]; then
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    set +e
    subscriptionWireGuardEnsureKeys >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -e "${privateKeyFile}" ]]
    [[ ! -e "${publicKeyFile}" ]]
    if regressionFindHasMatches "${wireGuardDir}" -maxdepth 1 -type f -name '.*.wireguard.*'; then
        return 1
    fi

    mkdir -p "${wireGuardDir}"
    printf 'existing-private-key\n' >"${privateKeyFile}"
    printf 'existing-public-key\n' >"${publicKeyFile}"

    set +e
    subscriptionWireGuardEnsureKeys >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${privateKeyFile}")" == "existing-private-key" ]]
    [[ "$(<"${publicKeyFile}")" == "existing-public-key" ]]
    if regressionFindHasMatches "${wireGuardDir}" -maxdepth 1 -type f -name '.*.wireguard.*'; then
        return 1
    fi

    commitGeneratedFile() {
        originalCommitGeneratedFile "$@"
    }
    subscriptionWireGuardEnsureKeys >/dev/null 2>&1
    [[ "$(<"${privateKeyFile}")" == "existing-private-key" ]]
    [[ "$(<"${publicKeyFile}")" == "generated-public-key" ]]

    rm -f "${privateKeyFile}" "${publicKeyFile}"
    subscriptionWireGuardEnsureKeys >/dev/null 2>&1
    [[ "$(<"${privateKeyFile}")" == "generated-private-key" ]]
    [[ "$(<"${publicKeyFile}")" == "generated-public-key" ]]
    if regressionFindHasMatches "${wireGuardDir}" -maxdepth 1 -type f -name '.*.wireguard.*'; then
        return 1
    fi

    command chmod 644 "${privateKeyFile}"
    chmod() {
        if [[ "$1" == "600" && "$2" == "${privateKeyFile}" ]]; then
            return 1
        fi
        command chmod "$@"
    }
    set +e
    subscriptionWireGuardEnsureKeys >/dev/null 2>&1
    rc=$?
    set -e
    unset -f chmod
    [[ "${rc}" == "1" ]]
    [[ "$(stat -c '%a' "${privateKeyFile}")" == "644" ]]
)

runWarpConfigFileCleanupRegression() (
    local rootRel="${TMP_DIR}/warp-config-file-cleanup"
    local root rmLog

    mkdir -p "${rootRel}/warp" "${rootRel}/xray"
    root=$(cd -- "${rootRel}" && pwd -P)
    rmLog="${root}/rm.log"
    : >"${rmLog}"
    printf 'config\n' >"${root}/warp/config"

    (
        source "${PROJECT_ROOT}/shell/core/routing_warp.sh"
        PADM_WARP_DIR="${root}/warp"
        coreInstallType=1
        configPath="${root}/xray/"
        singBoxConfigPath=
        rm() {
            printf 'rm:%s\n' "$*" >>"${rmLog}"
            command rm "$@"
        }
        unInstallWireGuard IPv4
    )

    grep -qxF "rm:-f -- ${root}/warp/config" "${rmLog}"
    ! grep -q "rm:-rf ${root}/warp/config" "${rmLog}"
    [[ ! -e "${root}/warp/config" ]]

    printf 'config\n' >"${root}/warp/config"
    mkdir -p "${root}/sing-box"
    printf '{}\n' >"${root}/sing-box/wireguard_endpoints_IPv4.json"
    printf '{}\n' >"${root}/sing-box/wireguard_endpoints_IPv6.json"
    (
        source "${PROJECT_ROOT}/shell/core/routing_warp.sh"
        PADM_WARP_DIR="${root}/warp"
        coreInstallType=2
        configPath=
        singBoxConfigPath="${root}/sing-box/"
        removeSingBoxRouteRule() { return 0; }
        removeSingBoxConfig() { rm -f -- "${singBoxConfigPath}$1.json"; }
        addSingBoxOutbound() { return 0; }

        removeWireGuardRoutingConfig IPv4
        [[ -f "${PADM_WARP_DIR}/config" ]]
        [[ -f "${singBoxConfigPath}wireguard_endpoints_IPv6.json" ]]
        removeWireGuardRoutingConfig IPv6
        [[ ! -e "${PADM_WARP_DIR}/config" ]]
    )
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

    local installedCrontab=
    readUserCrontabContent() {
        printf '%s\n' \
            '30 1 * * * /bin/bash /etc/padm/install.sh RenewTLS >> /etc/padm/crontab_tls.log 2>&1' \
            '35 1 * * * /bin/bash /etc/padm/install.sh UpdateGeo >> /etc/padm/crontab_tls.log 2>&1' \
            '* * * * * /bin/bash /etc/padm/install.sh SyncSubscriptionGroups' \
            '5 5 * * * /usr/local/bin/keep'
    }
    installUserCrontabContent() { installedCrontab=$1; }
    crontab() { return 0; }
    cleanupPadmCronJobsOnUninstall
    [[ "${installedCrontab}" == '5 5 * * * /usr/local/bin/keep' ]]

    nginxConfigPath="${oldNginxConfigPath}"
    PADM_NGINX_CONF_FALLBACK_DIR="${oldFallbackDir}"
}

runCleanAgentNginxManagedRemovalRegression() (
    local rootRel="${TMP_DIR}/clean-agent-nginx-managed-removal"
    local root
    local rmLog
    local includeLog
    local name

    mkdir -p "${rootRel}/nginx"
    root=$(cd -- "${rootRel}" && pwd -P)
    rmLog="${root}/rm.log"
    includeLog="${root}/include.log"
    : >"${rmLog}"
    : >"${includeLog}"

    nginxConfigPath="${root}/nginx/"
    PADM_REALITY_STREAM_CONF_FILE="${root}/reality-stream.conf"
    PADM_REALITY_STREAM_STATE_FILE="${root}/reality-stream.json"

    for name in alone.conf checkPortOpen.conf sing_box_VMess_HTTPUpgrade.conf subscribe.conf; do
        printf 'managed\n' >"${root}/nginx/${name}"
    done
    printf 'stream\n' >"${root}/reality-stream.conf"
    printf 'state\n' >"${root}/reality-stream.json"

    removeRealityStreamNginxInclude() {
        printf 'remove-include\n' >>"${includeLog}"
        return 0
    }
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    cleanAgentNginxConf
    for name in alone.conf checkPortOpen.conf sing_box_VMess_HTTPUpgrade.conf subscribe.conf; do
        grep -qxF "rm:-f -- ${root}/nginx/${name}" "${rmLog}"
        [[ ! -e "${root}/nginx/${name}" ]]
    done
    grep -qxF "rm:-f -- ${root}/reality-stream.conf" "${rmLog}"
    grep -qxF "rm:-f -- ${root}/reality-stream.json" "${rmLog}"
    [[ ! -e "${root}/reality-stream.conf" ]]
    [[ ! -e "${root}/reality-stream.json" ]]
    grep -qx 'remove-include' "${includeLog}"

    : >"${rmLog}"
    nginxConfigPath="relative-nginx/"
    if cleanAgentNginxConf >/dev/null 2>&1; then
        return 1
    fi
    [[ ! -s "${rmLog}" ]]
)

runFail2banManagedCleanupRegression() (
    local rootRel="${TMP_DIR}/fail2ban-managed-cleanup"
    local root
    local rmLog

    mkdir -p "${rootRel}/jail.d" "${rootRel}/filter.d" "${rootRel}/log"
    root=$(cd -- "${rootRel}" && pwd -P)
    rmLog="${root}/rm.log"
    : >"${rmLog}"

    PADM_FAIL2BAN_JAIL_FILE="${root}/jail.d/padm.local"
    PADM_FAIL2BAN_FILTER_FILE="${root}/filter.d/padm-control.conf"
    PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE="${root}/filter.d/padm-nginx-scan-basic.conf"
    PADM_FAIL2BAN_CONTROL_LOG_FILE="${root}/log/padm-control-access.log"

    printf 'jail\n' >"${PADM_FAIL2BAN_JAIL_FILE}"
    printf 'filter\n' >"${PADM_FAIL2BAN_FILTER_FILE}"
    printf 'scan\n' >"${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}"
    printf 'log\n' >"${PADM_FAIL2BAN_CONTROL_LOG_FILE}"

    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    fail2banRemoveManagedFiles
    grep -qxF "rm:-f -- ${PADM_FAIL2BAN_JAIL_FILE}" "${rmLog}"
    grep -qxF "rm:-f -- ${PADM_FAIL2BAN_FILTER_FILE}" "${rmLog}"
    grep -qxF "rm:-f -- ${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}" "${rmLog}"
    grep -qxF "rm:-f -- ${PADM_FAIL2BAN_CONTROL_LOG_FILE}" "${rmLog}"
    [[ ! -e "${PADM_FAIL2BAN_JAIL_FILE}" ]]
    [[ ! -e "${PADM_FAIL2BAN_FILTER_FILE}" ]]
    [[ ! -e "${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}" ]]
    [[ ! -e "${PADM_FAIL2BAN_CONTROL_LOG_FILE}" ]]

    : >"${rmLog}"
    PADM_FAIL2BAN_FILTER_FILE="${root}/filter.d/padm-control.conf"
    PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE="${root}/filter.d/padm-nginx-scan-basic.conf"
    PADM_FAIL2BAN_CONTROL_LOG_FILE="${root}/log/padm-control-access.log"
    printf 'filter-again\n' >"${PADM_FAIL2BAN_FILTER_FILE}"
    printf 'scan-again\n' >"${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}"
    printf 'log-again\n' >"${PADM_FAIL2BAN_CONTROL_LOG_FILE}"
    PADM_FAIL2BAN_JAIL_FILE="relative/padm.local"
    if fail2banRemoveManagedFiles >/dev/null 2>&1; then
        return 1
    fi
    [[ ! -s "${rmLog}" ]]
    [[ "$(<"${PADM_FAIL2BAN_FILTER_FILE}")" == "filter-again" ]]
    [[ "$(<"${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}")" == "scan-again" ]]
    [[ "$(<"${PADM_FAIL2BAN_CONTROL_LOG_FILE}")" == "log-again" ]]

    PADM_FAIL2BAN_JAIL_FILE="${root}/jail.d/padm.local"
    PADM_FAIL2BAN_FILTER_FILE="${root}/filter.d/padm-control.conf"
    PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE="${root}/filter.d/padm-nginx-scan-basic.conf"
    PADM_FAIL2BAN_CONTROL_LOG_FILE="${root}/log/padm-control-access.log"
    printf 'jail-uninstall\n' >"${PADM_FAIL2BAN_JAIL_FILE}"
    printf 'filter-uninstall\n' >"${PADM_FAIL2BAN_FILTER_FILE}"
    printf 'scan-uninstall\n' >"${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}"
    printf 'log-uninstall\n' >"${PADM_FAIL2BAN_CONTROL_LOG_FILE}"
    fail2banReloadServiceIfRunning() { return 0; }

    cleanupFail2banManagedFilesOnUninstall
    [[ ! -e "${PADM_FAIL2BAN_JAIL_FILE}" ]]
    [[ ! -e "${PADM_FAIL2BAN_FILTER_FILE}" ]]
    [[ ! -e "${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}" ]]
    [[ ! -e "${PADM_FAIL2BAN_CONTROL_LOG_FILE}" ]]
)

runFail2banApplyTransactionRegression() (
    local rootRel="${TMP_DIR}/fail2ban-apply-transaction"
    local root
    local errorLog="${TMP_DIR}/fail2ban-apply-transaction-errors.log"
    local rc
    local jailCommitFailures=0

    eval "$(declare -f fail2banStartOrReloadService | sed '1s/^fail2banStartOrReloadService/originalFail2banStartOrReloadService/')"

    mkdir -p "${rootRel}/fail2ban/jail.d" "${rootRel}/fail2ban/filter.d"
    root=$(cd -- "${rootRel}" && pwd -P)
    export TMPDIR="${root}"
    export PADM_FAIL2BAN_JAIL_FILE="${root}/fail2ban/jail.d/padm.local"
    export PADM_FAIL2BAN_FILTER_FILE="${root}/fail2ban/filter.d/padm-control.conf"
    export PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE="${root}/fail2ban/filter.d/padm-nginx-scan-basic.conf"
    export PADM_FAIL2BAN_CONTROL_LOG_FILE="${root}/fail2ban/log/padm-control-access.log"
    export PADM_FAIL2BAN_VALIDATE_LOG="${root}/fail2ban/validate.log"
    : >"${errorLog}"

    mkdir -p "$(dirname "${PADM_FAIL2BAN_CONTROL_LOG_FILE}")"
    printf 'legacy jail\n' >"${PADM_FAIL2BAN_JAIL_FILE}"
    printf 'legacy filter\n' >"${PADM_FAIL2BAN_FILTER_FILE}"
    printf 'legacy scan\n' >"${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}"
    printf 'legacy control log\n' >"${PADM_FAIL2BAN_CONTROL_LOG_FILE}"

    fail2banServiceActive() { return 1; }
    fail2banServiceEnabled() { return 1; }
    fail2banInstalled() { return 0; }
    fail2banSystemdServiceInstalled() { return 1; }
    fail2banOpenRcServiceInstalled() { return 1; }
    fail2banValidateManagedConfig() { return 0; }
    fail2banStartOrReloadService() { return 0; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${PADM_FAIL2BAN_JAIL_FILE}" && "${jailCommitFailures}" == "0" ]]; then
            jailCommitFailures=1
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    set +e
    fail2banApplyProfile sshd false >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${PADM_FAIL2BAN_JAIL_FILE}")" == "legacy jail" ]]
    [[ "$(<"${PADM_FAIL2BAN_FILTER_FILE}")" == "legacy filter" ]]
    [[ "$(<"${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}")" == "legacy scan" ]]
    ! compgen -G "${root}/fail2ban/jail.d/.padm.local.fail2ban.*" >/dev/null
    ! compgen -G "${root}/fail2ban/filter.d/.padm-control.conf.fail2ban.*" >/dev/null
    ! compgen -G "${root}/fail2ban/filter.d/.padm-nginx-scan-basic.conf.fail2ban.*" >/dev/null
    if regressionFindHasMatches "${root}" -maxdepth 1 -type d -name 'padm-check-log-backup.*'; then
        return 1
    fi

    fail2banReloadServiceIfRunning() { return 1; }
    set +e
    fail2banApplyProfile disabled false >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${PADM_FAIL2BAN_JAIL_FILE}")" == "legacy jail" ]]
    [[ "$(<"${PADM_FAIL2BAN_FILTER_FILE}")" == "legacy filter" ]]
    [[ "$(<"${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}")" == "legacy scan" ]]
    [[ "$(<"${PADM_FAIL2BAN_CONTROL_LOG_FILE}")" == "legacy control log" ]]

    commitGeneratedFile() {
        originalCommitGeneratedFile "$@"
    }
    fail2banApplyProfile sshd false >/dev/null
    grep -q '^\[sshd\]' "${PADM_FAIL2BAN_JAIL_FILE}"
    grep -q '^enabled = true$' "${PADM_FAIL2BAN_JAIL_FILE}"
    grep -q '/s/control/' "${PADM_FAIL2BAN_FILTER_FILE}"
    grep -Eq 'wp-login\.php|\.env|phpmyadmin|actuator' "${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}"
    ! compgen -G "${root}/fail2ban/jail.d/.padm.local.fail2ban.*" >/dev/null
    ! compgen -G "${root}/fail2ban/filter.d/.padm-control.conf.fail2ban.*" >/dev/null
    ! compgen -G "${root}/fail2ban/filter.d/.padm-nginx-scan-basic.conf.fail2ban.*" >/dev/null
    if regressionFindHasMatches "${root}" -maxdepth 1 -type d -name 'padm-check-log-backup.*'; then
        return 1
    fi

    (
        fail2banSystemdServiceInstalled() { return 1; }
        fail2banOpenRcServiceInstalled() { return 0; }
        fail2banServiceActive() { return 1; }
        systemctl() { return 1; }
        rc-update() { return 1; }
        rc-service() { return 0; }
        if originalFail2banStartOrReloadService; then
            return 1
        fi
    )

    (
        checkLogBackupRestore() { return 0; }
        fail2banSystemdServiceInstalled() { return 0; }
        fail2banOpenRcServiceInstalled() { return 1; }
        fail2banServiceActive() { return 1; }
        systemctl() {
            [[ "$1" != "disable" ]]
        }
        if fail2banRestoreManagedFiles "${root}/unused-backup" false false; then
            return 1
        fi
    )
)

runUninstallServiceStopFailureRegression() (
    local root="${TMP_DIR}/uninstall-service-stop"
    local serviceLog="${root}/service.log"
    local actionLog="${root}/actions.log"
    local errorLog="${root}/errors.log"
    local rcFile="${root}/uninstall.rc"
    local mode shellRc rc
    local nginxState=false

    mkdir -p "${root}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    autoRead() { printf -v "$3" 'y'; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    menu() { return 0; }
    pgrep() { return 1; }
    nginxRunning() { [[ "${nginxState}" == "true" ]]; }
    xrayRunning() {
        [[ "${mode:-}" == "xray-still-running" ]]
    }
    singBoxRunning() {
        [[ "${mode:-}" == "sing-box-still-running" ]]
    }
    removeInstallPath() {
        printf 'remove:%s:%s\n' "$1" "$2" >>"${actionLog}"
        return 0
    }
    cleanupSubscriptionWireGuardControlOnUninstall() {
        printf 'wireguard-cleanup\n' >>"${actionLog}"
        [[ "${mode:-}" == "wireguard-cleanup-fail" ]] && return 1
        return 0
    }
    cleanupPadmManagedRootOnUninstall() {
        printf 'padm-root-cleanup\n' >>"${actionLog}"
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
    uninstallReloadSystemdUnits() {
        printf 'daemon-reload\n' >>"${serviceLog}"
        return 0
    }
    systemctl() {
        printf 'systemctl:%s\n' "$*" >>"${serviceLog}"
        return 0
    }
    handleNginx() {
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ -n "${2:-}" ]] && printf 'nginx-mode:%s\n' "$*" >>"${serviceLog}"
        if [[ "${mode}" == "nginx-stop-fail" && "$1" == "stop" ]]; then
            [[ "${SERVICE_QUEUE_ALLOW_FAILURE:-}" == "true" ]] && return 1
            exit 0
        fi
        [[ "$1" == "stop" ]] && nginxState=false
        [[ "$1" == "start" ]] && nginxState=true
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
        currentInstallProtocolType=",27,"
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
        ! grep -qxF 'padm-root-cleanup' "${actionLog}"
        ! grep -qxF 'unsubscribe-cleanup' "${actionLog}"
        ! grep -q '^remove:/etc/systemd/system/xray.service:' "${actionLog}"
        ! grep -q '^remove:/etc/systemd/system/sing-box.service:' "${actionLog}"
        grep -q '卸载未完全完成' "${errorLog}"
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    }

    runUninstallStillRunningCase() {
        mode=$1
        : >"${serviceLog}"
        : >"${actionLog}"
        : >"${errorLog}"
        rm -f "${rcFile}"
        release=centos
        coreInstallType=1
        currentInstallProtocolType=",1,"
        singBoxConfigPath="${root}/sing-box-conf/"
        nginxConfigPath="${root}/nginx/"
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
        grep -qx 'xray:stop:true' "${serviceLog}"
        grep -qx 'sing-box:stop:true' "${serviceLog}"
        ! grep -qxF 'padm-root-cleanup' "${actionLog}"
        ! grep -qxF 'unsubscribe-cleanup' "${actionLog}"
        grep -q '停止后仍在运行' "${errorLog}"
        grep -q '卸载未完全完成' "${errorLog}"
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    }

    runUninstallNoNginxProtocolCase() {
        mode=nginx-stop-fail
        : >"${serviceLog}"
        : >"${actionLog}"
        : >"${errorLog}"
        rm -f "${rcFile}"
        release=centos
        coreInstallType=1
        currentInstallProtocolType=",1,"
        singBoxConfigPath="${root}/sing-box-conf/"
        nginxConfigPath="${root}/nginx/"
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
        [[ "$(<"${rcFile}")" == "0" ]]
        ! grep -qx 'nginx:stop:true' "${serviceLog}"
        grep -qx 'xray:stop:true' "${serviceLog}"
        grep -qx 'sing-box:stop:true' "${serviceLog}"
        grep -qxF 'padm-root-cleanup' "${actionLog}"
        grep -qxF 'unsubscribe-cleanup' "${actionLog}"
        grep -qx 'systemctl:disable xray.service' "${serviceLog}"
        grep -qx 'systemctl:disable sing-box.service' "${serviceLog}"
        [[ "$(grep -c '^daemon-reload$' "${serviceLog}")" == "2" ]]
        [[ ! -s "${errorLog}" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    }

    runUninstallWireGuardCleanupFailureCase() {
        mode=wireguard-cleanup-fail
        : >"${serviceLog}"
        : >"${actionLog}"
        : >"${errorLog}"
        rm -f "${rcFile}"
        release=centos
        coreInstallType=1
        currentInstallProtocolType=",1,"
        singBoxConfigPath=
        nginxConfigPath="${root}/nginx/"
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
        grep -qxF 'wireguard-cleanup' "${actionLog}"
        ! grep -qxF 'nginx-fragments' "${actionLog}"
        ! grep -qxF 'padm-root-cleanup' "${actionLog}"
        ! grep -qxF 'unsubscribe-cleanup' "${actionLog}"
        ! grep -qF 'remove:/usr/bin/padm:' "${actionLog}"
        ! grep -qF 'remove:/usr/sbin/padm:' "${actionLog}"
        grep -q 'WireGuard 控制面清理失败，已取消后续删除' "${errorLog}"
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    }

    runUninstallRestoresNginxCase() {
        mode=success
        nginxState=true
        : >"${serviceLog}"
        : >"${actionLog}"
        : >"${errorLog}"
        release=centos
        coreInstallType=1
        currentInstallProtocolType=",27,"
        singBoxConfigPath="${root}/sing-box-conf/"
        nginxStaticPath="${root}/static"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        set +e
        unInstall >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "0" ]]
        [[ "${nginxState}" == "true" ]] || return 1
        grep -qx 'nginx:stop:true' "${serviceLog}"
        grep -qx 'nginx:start:true' "${serviceLog}" || return 1
        grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    }

    runUninstallStopFailureCase nginx-stop-fail
    runUninstallStopFailureCase xray-stop-fail
    runUninstallStopFailureCase sing-box-stop-fail
    runUninstallStillRunningCase xray-still-running
    runUninstallStillRunningCase sing-box-still-running
    runUninstallNoNginxProtocolCase
    runUninstallWireGuardCleanupFailureCase
    runUninstallRestoresNginxCase
)

runCleanLastInstallationConfigFailureRegression() (
    local root="${TMP_DIR}/clean-last-installation"
    local serviceLog="${root}/service.log"
    local cleanupLog="${root}/cleanup.log"
    local errorLog="${root}/error.log"
    local installLog="${root}/install.log"
    local mode rc
    local nginxState=true

    mkdir -p "${root}/nginx" "${root}/static"
    printf 'managed-static\n' >"${root}/static/check"
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
        [[ -n "${2:-}" ]] && printf 'nginx-mode:%s\n' "$*" >>"${serviceLog}"
        [[ "${mode}" == "nginx-stop-fail" ]] && return 1
        [[ "$1" == "stop" ]] && nginxState=false
        [[ "$1" == "start" ]] && nginxState=true
        return 0
    }
    nginxRunning() { [[ "${nginxState}" == "true" ]]; }
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
        [[ "${mode}" == "rm-warp-fail" && "$*" == "-f -- /etc/padm/warp/config" ]] && return 1
        [[ "${mode}" == "rm-static-fail" && "$1" == "-rf" && "$2" == "--" && "$3" == "${root}/static/" ]] && return 1
        return 0
    }
    unInstallSubscribe() { printf 'uninstall-subscribe\n' >>"${installLog}"; return 0; }
    installTools() { printf 'install-tools:%s\n' "$*" >>"${installLog}"; return 0; }
    initTLSNginxConfig() { printf 'init-tls:%s\n' "$*" >>"${installLog}"; return 0; }
    installTLS() { printf 'install-tls:%s\n' "$*" >>"${installLog}"; return 0; }
    randomPathFunction() { printf 'random-path:%s\n' "$*" >>"${installLog}"; return 0; }
    installXray() { printf 'install-xray:%s\n' "$*" >>"${installLog}"; return 0; }
    installXrayService() { printf 'install-xray-service:%s\n' "$*" >>"${installLog}"; return 0; }
    initXrayConfig() { printf 'init-xray-config:%s\n' "$*" >>"${installLog}"; return 0; }
    cleanUp() { printf 'cleanup-core:%s\n' "$*" >>"${installLog}"; return 0; }
    installCronTLS() { printf 'install-cron:%s\n' "$*" >>"${installLog}"; return 0; }
    nginxBlog() { printf 'nginx-blog:%s\n' "$*" >>"${installLog}"; return 0; }
    updateRedirectNginxConf() { printf 'update-redirect\n' >>"${installLog}"; return 0; }
    checkGFWStatue() { printf 'check-gfw:%s\n' "$*" >>"${installLog}"; return 0; }
    showAccounts() { printf 'show-accounts:%s\n' "$*" >>"${installLog}"; return 0; }

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
    grep -qx 'nginx:start:true' "${serviceLog}" || return 1
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    [[ "${nginxState}" == "true" ]] || return 1
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
        'rm:-f -- /etc/padm/warp/config' \
        'rm:-f -- /etc/padm/cdn'

    runCleanupStepFailureCase daemon-reload-fail \
        'systemd 配置重载失败，已取消清空上次安装配置' \
        'systemctl:daemon-reload' \
        'read-install-type'

    runCleanupStepFailureCase rm-static-fail \
        '静态站点清理失败，已取消清空上次安装配置' \
        "rm:-rf -- ${root}/static/" \
        'read-install-type'

    local xrayOpenRcServiceFile="${root}/init.d/xray"
    local singBoxOpenRcServiceFile="${root}/init.d/sing-box"
    mkdir -p "${root}/init.d"
    printf 'xray-service\n' >"${xrayOpenRcServiceFile}"
    printf 'sing-box-service\n' >"${singBoxOpenRcServiceFile}"
    export PADM_XRAY_OPENRC_SERVICE_FILE="${xrayOpenRcServiceFile}"
    export PADM_SINGBOX_OPENRC_SERVICE_FILE="${singBoxOpenRcServiceFile}"
    release=alpine
    coreInstallType=1
    rc-update() {
        printf 'rc-update:%s\n' "$*" >>"${cleanupLog}"
        return 0
    }
    mode=
    : >"${cleanupLog}"
    cleanLastInstallationConfig >/dev/null 2>&1
    grep -qx 'rc-update:del xray default' "${cleanupLog}"
    grep -qx 'rc-update:del sing-box default' "${cleanupLog}"
    grep -qxF "rm:-f -- ${xrayOpenRcServiceFile}" "${cleanupLog}"
    grep -qxF "rm:-f -- ${singBoxOpenRcServiceFile}" "${cleanupLog}"
    ! grep -q '^systemctl:' "${cleanupLog}"
    release=debian
    coreInstallType=
    unset PADM_XRAY_OPENRC_SERVICE_FILE PADM_SINGBOX_OPENRC_SERVICE_FILE
    unset -f rc-update

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

runCleanLastInstallationConfigAcmeHomeFailureRegression() (
    local root="${TMP_DIR}/clean-last-installation-acme-home"
    local homeDir="${root}/home"
    local acmeDir="${homeDir}/.acme.sh"
    local resolvedAcmeDir
    local cleanupLog="${root}/cleanup.log"
    local errorLog="${root}/error.log"
    local rc

    mkdir -p "${root}/nginx" "${root}/static" "${acmeDir}"
    resolvedAcmeDir=$(cd -- "${homeDir}" && pwd -P)/.acme.sh
    : >"${cleanupLog}"
    : >"${errorLog}"

    HOME="${homeDir}"
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

    handleXray() { return 0; }
    handleSingBox() { return 0; }
    handleNginx() { return 0; }
    cleanAgentNginxConf() { return 0; }
    cleanDirectoryContent() { return 0; }
    readInstallType() { return 0; }
    mkdirTools() { return 0; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    showLastInstallationConfig() { return 0; }
    autoRead() {
        if [[ "$1" == "clean_acme" ]]; then
            printf -v "$3" 'y'
        else
            printf -v "$3" 'n'
        fi
    }
    lsof() { return 1; }
    systemctl() { return 0; }
    rm() {
        printf 'rm:%s\n' "$*" >>"${cleanupLog}"
        if [[ "$*" == "-rf -- ${resolvedAcmeDir}" ]]; then
            return 1
        fi
        return 0
    }

    set +e
    cleanLastInstallationConfig >/dev/null 2>&1
    rc=$?
    set -e

    [[ "${rc}" == "1" ]]
    grep -qxF "rm:-rf -- ${resolvedAcmeDir}" "${cleanupLog}"
    ! grep -q "/root/.acme.sh" "${cleanupLog}"
    grep -q "acme证书和账号配置清理失败" "${errorLog}"
)

runCleanLastInstallationConfigResolvesRelativeAcmeHomeRegression() (
    local rootRel="${TMP_DIR}/clean-last-installation-acme-relative-home"
    local root
    local rootWorkRel
    local cleanupLog
    local errorLog
    local resolvedAcmeDir
    local rc

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    rootWorkRel="${rootRel}/work"
    cleanupLog="${root}/cleanup.log"
    errorLog="${root}/error.log"
    mkdir -p "${rootWorkRel}/nginx" "${rootWorkRel}/static" "${rootWorkRel}/relative-home/.acme.sh"
    resolvedAcmeDir="${root}/work/relative-home/.acme.sh"
    : >"${cleanupLog}"
    : >"${errorLog}"

    HOME="relative-home"
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
    nginxConfigPath="${root}/work/nginx/"
    nginxStaticPath="${root}/work/static"
    configPath="${root}/work/xray-conf/"

    handleXray() { return 0; }
    handleSingBox() { return 0; }
    handleNginx() { return 0; }
    cleanAgentNginxConf() { return 0; }
    cleanDirectoryContent() { return 0; }
    readInstallType() { return 0; }
    mkdirTools() { return 0; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    showLastInstallationConfig() { return 0; }
    autoRead() {
        if [[ "$1" == "clean_acme" ]]; then
            printf -v "$3" 'y'
        else
            printf -v "$3" 'n'
        fi
    }
    lsof() { return 1; }
    systemctl() { return 0; }
    rm() {
        printf 'rm:%s\n' "$*" >>"${cleanupLog}"
        command rm "$@"
    }

    (
        cd "${rootWorkRel}"
        set +e
        cleanLastInstallationConfig >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "0" ]]
        [[ ! -d "${resolvedAcmeDir}" ]]
        grep -qxF "rm:-rf -- ${resolvedAcmeDir}" "${cleanupLog}"
        ! grep -q 'rm:-rf -- relative-home/.acme.sh' "${cleanupLog}"
        [[ ! -s "${errorLog}" ]]
    )
)

runEntryHelperConfigRegression() {
    local entryConfigPath="${TMP_DIR}/entry-helper-conf/"
    local entryFakeBin="${TMP_DIR}/entry-helper-fake-bin"
    local entryLogBase="${TMP_DIR}/entry-helper-logs/"
    local entryTmpRoot="${TMP_DIR}/entry-helper-tmp"
    local oldTmpDir="${TMPDIR:-}"
    local realityVisionFile="${entryConfigPath}07_VLESS_vision_reality_inbounds.json"
    local realityXhttpFile="${entryConfigPath}12_VLESS_XHTTP_inbounds.json"
    local oldPath="${PATH}"
    local protocolSelectionIncludesDef=
    local nginxTarget="${TMP_DIR}/entry-helper-nginx/sing_box_VMess_HTTPUpgrade.conf"
    local originalContent
    mkdir -p "${entryConfigPath}" "${entryLogBase}" "${entryFakeBin}" "${TMP_DIR}/entry-helper-nginx" "${entryTmpRoot}"
    cat >"${entryFakeBin}/nginx" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-v" ]]; then
    printf 'nginx version: nginx/1.24.0\n' >&2
    exit 0
fi
[[ "$1" == "-t" ]]
printf 'entry-helper validate %s\n' "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}"
[[ "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}" == "success" ]]
SH
    chmod +x "${entryFakeBin}/nginx"
    PATH="${entryFakeBin}:${PATH}"
    TMPDIR="${entryTmpRoot}"
    protocolSelectionIncludesDef=$(declare -f protocolSelectionIncludes)
    protocolSelectionIncludesDef="${protocolSelectionIncludesDef/protocolSelectionIncludes/regressionOriginalProtocolSelectionIncludes}"
    eval "${protocolSelectionIncludesDef}"
    protocolSelectionIncludes() {
        regressionProtocolSelectionIncludesCompat "$@"
    }
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
    selectCustomInstallType=23
    printf 'old config\n' >"${nginxTarget}"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    if singBoxNginxConfig 23 443 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${nginxTarget}")" == "old config" ]]
    [[ ! -e "${nginxTarget}.tmp" ]]
    [[ -s "${entryTmpRoot}/padm-sing-box-vmess-httpupgrade-nginx-test.log" ]]
    export PADM_FAKE_NGINX_VALIDATE_MODE=success
    singBoxNginxConfig 23 443
    grep -q 'server_name example.com;' "${nginxTarget}"
    grep -q 'location /padm' "${nginxTarget}"
    ! grep -qx 'old config' "${nginxTarget}"
    [[ ! -e "${nginxTarget}.tmp" ]]
    [[ ! -e "${nginxTarget}.bak" ]]
    ! compgen -G "${TMP_DIR}/entry-helper-nginx/.sing_box_VMess_HTTPUpgrade.conf.*" >/dev/null

    (
        local unsafeRoot="${TMP_DIR}/entry-helper-nginx-unsafe"
        local rc
        mkdir -p "${unsafeRoot}/relative-nginx"
        printf 'stale\n' >"${unsafeRoot}/relative-nginx/sing_box_VMess_HTTPUpgrade.conf"
        cd "${unsafeRoot}"
        nginxConfigPath="relative-nginx/"
        set +e
        writeSingBoxVMessHTTPUpgradeNginxConfig <<'EOF' >/dev/null 2>&1
server {}
EOF
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ "$(<"${unsafeRoot}/relative-nginx/sing_box_VMess_HTTPUpgrade.conf")" == "stale" ]]
        ! compgen -G "${unsafeRoot}/relative-nginx/.sing_box_VMess_HTTPUpgrade.conf.*" >/dev/null
    )

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

    (
        local errorLog="${TMP_DIR}/entry-helper-check-log-write-error.log"
        local readCalls=0 rc
        : >"${errorLog}"
        coreInstallType=1
        configPath="${entryConfigPath}"
        realityStatus=7
        writeXrayLogConfig "${entryConfigPath}00_log.json" "${entryLogBase}" false
        cat >"${realityVisionFile}" <<'JSON'
{"inbounds":[{"streamSettings":{"realitySettings":{"show":false}}}]}
JSON
        autoRead() {
            readCalls=$((readCalls + 1))
            printf -v "$3" '1'
        }
        updateRealityShowConfig() {
            return 1
        }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        set +e
        checkLog >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ "${readCalls}" == "1" ]]
        grep -q 'Reality 日志联动配置写入失败' "${errorLog}"
        jq -e '(.log.access | not) and .log.error == "'"${entryLogBase}"'error.log" and .log.loglevel == "warning"' "${entryConfigPath}00_log.json" >/dev/null
        jq -e '.inbounds[0].streamSettings.realitySettings.show == false' "${realityVisionFile}" >/dev/null
        if regressionFindHasMatches "${entryTmpRoot}" -maxdepth 1 -type d -name 'padm-check-log-backup.*'; then
            return 1
        fi
    )

    (
        local errorLog="${TMP_DIR}/entry-helper-check-log-error.log"
        local reloadCalls=0 readCalls=0 rc
        : >"${errorLog}"
        coreInstallType=1
        configPath="${entryConfigPath}"
        realityStatus=7
        writeXrayLogConfig "${entryConfigPath}00_log.json" "${entryLogBase}" false
        cat >"${realityVisionFile}" <<'JSON'
{"inbounds":[{"streamSettings":{"realitySettings":{"show":false}}}]}
JSON
        autoRead() {
            readCalls=$((readCalls + 1))
            printf -v "$3" '1'
        }
        reloadCore() {
            reloadCalls=$((reloadCalls + 1))
            return 1
        }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        set +e
        checkLog >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ "${readCalls}" == "1" ]]
        [[ "${reloadCalls}" == "2" ]]
        grep -q '已回滚日志配置修改' "${errorLog}"
        grep -q '恢复旧配置后核心重载仍失败' "${errorLog}"
        jq -e '(.log.access | not) and .log.error == "'"${entryLogBase}"'error.log" and .log.loglevel == "warning"' "${entryConfigPath}00_log.json" >/dev/null
        jq -e '.inbounds[0].streamSettings.realitySettings.show == false' "${realityVisionFile}" >/dev/null
        if regressionFindHasMatches "${entryTmpRoot}" -maxdepth 1 -type d -name 'padm-check-log-backup.*'; then
            return 1
        fi
    )

    (
        local serviceLog="${TMP_DIR}/entry-helper-tls-init-service.log"
        local errorLog="${TMP_DIR}/entry-helper-tls-init-error.log"
        local rc
        : >"${serviceLog}"
        : >"${errorLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        currentHost=tls-init.example.com
        lastInstallationConfig=true
        selectCoreType=2
        domain=
        handleNginx() {
            printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
            return 1
        }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        set +e
        initTLSNginxConfig 1 >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -qx 'nginx:stop:true' "${serviceLog}"
        grep -q 'TLS 初始化' "${errorLog}"
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    )

    (
        local serviceLog="${TMP_DIR}/entry-helper-port-service.log"
        local errorLog="${TMP_DIR}/entry-helper-port-error.log"
        local allowMarker="${TMP_DIR}/entry-helper-port-allow"
        local rc
        : >"${serviceLog}"
        : >"${errorLog}"
        rm -f "${allowMarker}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        btDomain=
        currentPort=
        customPort=
        xrayVLESSRealityPort=443
        domain=port.example.com
        handleXray() {
            printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
            return 1
        }
        autoRead() {
            printf -v "$3" '443'
        }
        allowPort() {
            printf 'allow\n' >"${allowMarker}"
        }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        set +e
        customPortFunction >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -qx 'xray:stop:true' "${serviceLog}"
        grep -q '无法复用当前 Reality 端口' "${errorLog}"
        [[ ! -e "${allowMarker}" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    )

    (
        local errorLog="${TMP_DIR}/entry-helper-port-expression-error.log"
        local allowLog="${TMP_DIR}/entry-helper-port-expression-allow.log"
        local rc
        : >"${errorLog}"
        : >"${allowLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        btDomain=
        currentPort=
        customPort=
        xrayVLESSRealityPort=
        domain=port.example.com
        autoRead() {
            printf -v "$3" '1+2'
        }
        allowPort() {
            printf '%s\n' "$1" >>"${allowLog}"
        }
        checkDNSIP() { return 0; }
        removeNginxDefaultConf() { return 0; }
        checkPortOpen() { return 0; }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        set +e
        customPortFunction >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -q '端口输入错误' "${errorLog}"
        [[ ! -s "${allowLog}" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    )

    (
        local checkPortMarker="${TMP_DIR}/entry-helper-port-nginx-cleanup-check"
        local errorLog="${TMP_DIR}/entry-helper-port-nginx-cleanup-error.log"
        local rc
        : >"${errorLog}"
        rm -f "${checkPortMarker}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        btDomain=
        currentPort=
        customPort=
        xrayVLESSRealityPort=
        domain=port.example.com
        autoRead() {
            printf -v "$3" '443'
        }
        allowPort() { return 0; }
        checkDNSIP() { return 0; }
        removeNginxDefaultConf() { return 1; }
        checkPortOpen() {
            : >"${checkPortMarker}"
            return 0
        }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        set +e
        customPortFunction >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ ! -e "${checkPortMarker}" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    )

    PATH="${oldPath}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    eval "${protocolSelectionIncludesDef}"
    unset PADM_FAKE_NGINX_VALIDATE_MODE
}

eval "$(declare -f appendDefaultSubscribeLine | sed '1s/^appendDefaultSubscribeLine/padmRealAppendDefaultSubscribeLine/')"
eval "$(declare -f appendClashMetaSubscribeBlock | sed '1s/^appendClashMetaSubscribeBlock/padmRealAppendClashMetaSubscribeBlock/')"
eval "$(declare -f appendClashMetaSubscribeLines | sed '1s/^appendClashMetaSubscribeLines/padmRealAppendClashMetaSubscribeLines/')"
eval "$(declare -f appendSingBoxSubscribeLocalConfig | sed '1s/^appendSingBoxSubscribeLocalConfig/padmRealAppendSingBoxSubscribeLocalConfig/')"

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

runSubscribeLocalOutputTransactionRegression() (
    local rootRel="${TMP_DIR}/subscribe-local-output-transaction"
    local root localDir defaultFile clashFile clashLinesFile
    local rc

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    localDir="${root}/subscribe_local"
    defaultFile="${localDir}/default/user"
    clashFile="${localDir}/clashMeta/user"
    clashLinesFile="${localDir}/clashMeta/xhttp-user"
    export PADM_SUBSCRIBE_LOCAL_DIR="${localDir}"
    mkdir -p "${localDir}/default" "${localDir}/clashMeta"
    printf 'old-default\n' >"${defaultFile}"
    printf 'old-clash\n' >"${clashFile}"
    printf 'old-lines\n' >"${clashLinesFile}"

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${defaultFile}" || "$2" == "${clashFile}" || "$2" == "${clashLinesFile}" ]]; then
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    set +e
    padmRealAppendDefaultSubscribeLine user 'new-default'
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${defaultFile}")" == "old-default" ]]
    if regressionFindHasMatches "${localDir}/default" -maxdepth 1 -type f -name '.user.subscribe.*'; then
        return 1
    fi

    set +e
    padmRealAppendClashMetaSubscribeBlock user 'new-clash'
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${clashFile}")" == "old-clash" ]]
    if regressionFindHasMatches "${localDir}/clashMeta" -maxdepth 1 -type f -name '.user.subscribe.*'; then
        return 1
    fi

    set +e
    padmRealAppendClashMetaSubscribeLines xhttp-user <<'EOF'
  - name: "xhttp-user"
    type: vless
EOF
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${clashLinesFile}")" == "old-lines" ]]
    if regressionFindHasMatches "${localDir}/clashMeta" -maxdepth 1 -type f -name '.xhttp-user.subscribe.*'; then
        return 1
    fi

    (
        local inlineRootRel="${TMP_DIR}/subscribe-local-output-inline-helpers"
        local inlineRoot inlineLocalDir
        local modeLog

        mkdir -p "${inlineRootRel}"
        inlineRoot=$(cd -- "${inlineRootRel}" && pwd -P)
        inlineLocalDir="${inlineRoot}/subscribe_local"
        modeLog="${inlineRoot}/commit-modes.log"
        export PADM_SUBSCRIBE_LOCAL_DIR="${inlineLocalDir}"
        commitGeneratedFile() {
            printf '%s|%s\n' "$2" "${3:-}" >>"${modeLog}"
            originalCommitGeneratedFile "$@"
        }
        subscribeLocalOutputCategoryDir() {
            return 91
        }
        ensureSubscribeLocalSingBoxConfig() {
            return 92
        }

        padmRealAppendDefaultSubscribeLine user 'new-default-inline'
        padmRealAppendClashMetaSubscribeBlock user 'new-clash-inline'
        padmRealAppendSingBoxSubscribeLocalConfig user '. += [{"tag":"inline-user"}]'
        padmRealAppendClashMetaSubscribeLines xhttp-user <<'EOF'
  - name: "xhttp-user"
    type: vless
EOF

        [[ "$(<"${inlineLocalDir}/default/user")" == "new-default-inline" ]]
        [[ "$(<"${inlineLocalDir}/clashMeta/user")" == "new-clash-inline" ]]
        grep -q 'xhttp-user' "${inlineLocalDir}/clashMeta/xhttp-user"
        grep -Fxq "${inlineLocalDir}/default/user|600" "${modeLog}"
        grep -Fxq "${inlineLocalDir}/clashMeta/user|600" "${modeLog}"
        grep -Fxq "${inlineLocalDir}/clashMeta/xhttp-user|600" "${modeLog}"
        jq -e '.[0].tag == "inline-user"' "${inlineLocalDir}/sing-box/user" >/dev/null
    )
)

runSubscribeSaltWriteTransactionRegression() (
    local rootRel="${TMP_DIR}/subscribe-salt-write-transaction"
    local root saltFile
    local rc

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    saltFile="${root}/subscribeSalt"
    printf 'old-salt\n' >"${saltFile}"

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${saltFile}" ]]; then
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    set +e
    writeSubscribeSalt "${saltFile}" "new-salt"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${saltFile}")" == "old-salt" ]]
    ! compgen -G "${root}/.subscribeSalt.subscribe.*" >/dev/null

    commitGeneratedFile() {
        printf '%s|%s\n' "$2" "${3:-}" >"${root}/commit-mode.log"
        originalCommitGeneratedFile "$@"
    }
    writeSubscribeSalt "${saltFile}" "new-salt"
    [[ "$(<"${saltFile}")" == "new-salt" ]]
    grep -Fxq "${saltFile}|600" "${root}/commit-mode.log"
    ! compgen -G "${root}/.subscribeSalt.subscribe.*" >/dev/null
)

runCdnAddressTransactionRegression() (
    local rootRel="${TMP_DIR}/cdn-address-write-transaction"
    local root cdnFile
    local rc

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    cdnFile="${root}/cdn"
    printf 'old-cdn.example.com\n' >"${cdnFile}"

    cdnAddressFile() {
        printf '%s' "${cdnFile}"
    }

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${cdnFile}" ]]; then
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    set +e
    cdnWriteAddress "new-cdn.example.com"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${cdnFile}")" == "old-cdn.example.com" ]]
    ! compgen -G "${root}/.cdn.cdn.*" >/dev/null

    set +e
    cdnClearAddress
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${cdnFile}")" == "old-cdn.example.com" ]]
    ! compgen -G "${root}/.cdn.cdn.*" >/dev/null

    commitGeneratedFile() {
        originalCommitGeneratedFile "$@"
    }
    cdnWriteAddress "new-cdn.example.com"
    [[ "$(<"${cdnFile}")" == "new-cdn.example.com" ]]
    ! compgen -G "${root}/.cdn.cdn.*" >/dev/null

    cdnClearAddress
    [[ ! -s "${cdnFile}" ]]
    ! compgen -G "${root}/.cdn.cdn.*" >/dev/null

    subscribe() {
        return 1
    }
    AUTO_INSTALL=
    cdnWriteAddress "old-cdn.example.com"
    set +e
    setCDNEntryAddress <<<"new-cdn.example.com"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${cdnFile}")" == "old-cdn.example.com" ]]

    set +e
    clearCDNEntryAddress
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${cdnFile}")" == "old-cdn.example.com" ]]

    local refreshCalls=0
    subscribe() {
        refreshCalls=$((refreshCalls + 1))
        return 0
    }
    cdnWriteAddress() { return 1; }
    set +e
    setCDNEntryAddress <<<"new-cdn.example.com"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${refreshCalls}" == "0" ]]
    [[ "$(<"${cdnFile}")" == "old-cdn.example.com" ]]

    cdnClearAddress() { return 1; }
    set +e
    clearCDNEntryAddress
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${refreshCalls}" == "0" ]]
    [[ "$(<"${cdnFile}")" == "old-cdn.example.com" ]]
)

runSingBoxSubscribeWriteRegression() {
    local targetPath="${SUBSCRIBE_CAPTURE_DIR}/sing-box/atomic-user"
    rm -rf "${SUBSCRIBE_CAPTURE_DIR}/sing-box"
    mkdir -p "$(dirname "${targetPath}")"
    printf '[{"tag":"old"}]\n' >"${targetPath}"
    if padmRealAppendSingBoxSubscribeLocalConfig atomic-user '. += [' 2>/dev/null; then
        return 1
    fi
    jq -e '.[0].tag == "old"' "${targetPath}" >/dev/null
    if regressionFindHasMatches "${SUBSCRIBE_CAPTURE_DIR}/sing-box" -maxdepth 1 -type f -name '.atomic-user.subscribe.*'; then
        return 1
    fi
    padmRealAppendSingBoxSubscribeLocalConfig atomic-user '. += [{"tag":"new"}]'
    jq -e 'length == 2 and .[1].tag == "new"' "${targetPath}" >/dev/null
    if regressionFindHasMatches "${SUBSCRIBE_CAPTURE_DIR}/sing-box" -maxdepth 1 -type f -name '.atomic-user.subscribe.*'; then
        return 1
    fi
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
    currentHost=$'bad.example.com;\nreturn 444'
    ! resolveSubscribeServerName >/dev/null

    currentHost=
    domain=domain.example.com
    [[ "$(resolveSubscribeServerName)" == "domain.example.com" ]]
    domain='bad domain.example.com'
    ! resolveSubscribeServerName >/dev/null

    currentHost=
    domain=
    export PADM_TLS_DIR="${tlsDir}"
    printf 'cert\n' >"${tlsDir}/cert.example.com.crt"
    printf 'key\n' >"${tlsDir}/cert.example.com.key"
    printf 'cert\n' >"${tlsDir}/bad;name.crt"
    printf 'key\n' >"${tlsDir}/bad;name.key"
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
    local nginxRootRel="${TMP_DIR}/nginx-subscribe"
    local nginxRoot targetPath
    local oldPath="${PATH}"
    local oldTmpDir="${TMPDIR:-}"
    local nginxTmpRoot="${TMP_DIR}/nginx-subscribe-tmp"
    local helperLog="${TMP_DIR}/nginx-subscribe-helper.log"
    mkdir -p "${TMP_DIR}/fake-bin" "${nginxRootRel}" "${nginxTmpRoot}"
    nginxRoot=$(cd -- "${nginxRootRel}" && pwd -P)
    targetPath="${nginxRoot}/subscribe.conf"
    TMPDIR="${nginxTmpRoot}"
    nginxConfigPath="${nginxRoot}/"
    : >"${helperLog}"
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
        local backupGlob="${nginxRoot}/.subscribe.conf.backup.*"
        local backups=()
        eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
        commitGeneratedFile() {
            if [[ "$2" == "${targetPath}" && "$1" == "${nginxRoot}/.subscribe.conf.backup."* ]]; then
                return 1
            fi
            originalCommitGeneratedFile "$@"
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
        subscriptionSyncSetManualCheckMessage() {
            printf "manual-check:%s|%s\n" "$2" "$3" >>"${helperLog}"
            printf -v "$1" "%s，请手动检查%s" "$2" "$3"
        }
        rm() {
            if [[ "$1" == "-f" && ( "$2" == "${targetPath}" || ( "$2" == "--" && "$3" == "${targetPath}" ) ) ]]; then
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
        grep -q "manual-check:订阅 Nginx 配置校验失败，且新配置清理失败| ${targetPath}" "${helperLog}"
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

    (
        local root="${TMP_DIR}/subscribe-nginx-custom-alias"
        local nginxRoot="${root}/nginx"
        local tlsRoot="${root}/tls"
        local subscribeRoot="${root}/public-subscribe"
        local staticRoot="${root}/static"
        local oldSubscribeDir="${PADM_SUBSCRIBE_DIR:-}"
        local oldTlsDir="${PADM_TLS_DIR:-}"
        local oldCurrentHost="${currentHost:-}"
        local configPath

        mkdir -p "${root}/fake-bin" "${nginxRoot}" "${tlsRoot}" "${subscribeRoot}" "${staticRoot}"
        cat >"${root}/fake-bin/nginx" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-v" ]]; then
    printf 'nginx version: nginx/1.26.0\n' >&2
    exit 0
fi
[[ "$1" == "-t" ]]
SH
        chmod +x "${root}/fake-bin/nginx"
        PATH="${root}/fake-bin:${oldPath}"
        nginxConfigPath="${nginxRoot}/"
        nginxStaticPath="${staticRoot}"
        export PADM_TLS_DIR="${tlsRoot}"
        export PADM_SUBSCRIBE_DIR="${subscribeRoot}"
        currentHost=subscribe.example.com
        printf 'cert\n' >"${tlsRoot}/subscribe.example.com.crt"
        printf 'key\n' >"${tlsRoot}/subscribe.example.com.key"

        readNginxSubscribe() { subscribePort=; }
        readSingBoxPortResult() {
            local -n resultRef=$1
            resultRef=(39778)
        }
        nginxBlog() { return 0; }
        hasIPv6Connectivity() { return 1; }
        installSubscriptionControlService() { return 0; }
        coreStartupServiceEnabled() { return 1; }
        bootStartup() { return 0; }
        handleNginx() { return 0; }
        pgrep() { return 0; }

        installSubscribe >/dev/null 2>&1
        configPath="${nginxRoot}/subscribe.conf"
        grep -q "alias ${subscribeRoot}/\\\$1/\\\$2;" "${configPath}"
        grep -q "ssl_certificate ${tlsRoot}/subscribe.example.com.crt;ssl_certificate_key ${tlsRoot}/subscribe.example.com.key;" "${configPath}"

        if [[ -n "${oldSubscribeDir}" ]]; then export PADM_SUBSCRIBE_DIR="${oldSubscribeDir}"; else unset PADM_SUBSCRIBE_DIR; fi
        if [[ -n "${oldTlsDir}" ]]; then export PADM_TLS_DIR="${oldTlsDir}"; else unset PADM_TLS_DIR; fi
        currentHost="${oldCurrentHost}"
    )
}

runSubscribeNginxServiceFailureRegression() (
    local root="${TMP_DIR}/subscribe-nginx-service-failure"
    local oldPath="${PATH}"
    local serviceLog="${root}/service.log"
    local firewallState="${root}/firewall.state"
    local firewallLog="${root}/firewall.log"
    local errorLog="${root}/error.log"
    local installMarker="${root}/install.marker"
    local mode=reload
    local rc writeCalls controlCalls bootCalls
    local runtimeRunning=true
    local runtimeEnabled=false
    local startFailures=0
    local startCalls=0

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
    nginx() {
        [[ "${mode}" != "install-fail" ]] || return 127
        command nginx "$@"
    }
    autoConfirm() { printf -v "$4" '%s' y; }
    installNginxTools() {
        : >"${installMarker}"
        exit 17
    }
    nginxConfigPath="${root}/nginx/"
    nginxStaticPath="${root}/static"
    export PADM_TLS_DIR="${root}/tls"
    currentHost=subscribe.example.com
    printf 'cert\n' >"${PADM_TLS_DIR}/subscribe.example.com.crt"
    printf 'key\n' >"${PADM_TLS_DIR}/subscribe.example.com.key"
    printf 'old-subscribe-config\n' >"${nginxConfigPath}subscribe.conf"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    PADM_FIREWALL_STATE_FILE="${firewallState}"
    : >"${serviceLog}"
    : >"${firewallLog}"
    : >"${errorLog}"

    readNginxSubscribe() {
        if [[ "${mode}" == "existing-port" ]]; then
            subscribePort=39778
        else
            subscribePort=
        fi
    }
    initSingBoxPort() {
        padmFirewallStateAdd "port:ufw:tcp:39778"
        padmFirewallStateAdd "port:ufw:udp:39778"
        printf '39778\n'
    }
    removeFirewallPortRule() {
        printf '%s:%s:%s\n' "$1" "$2" "$3" >>"${firewallLog}"
        return 0
    }
    nginxBlog() { [[ "${mode}" != "blog-fail" ]]; }
    hasIPv6Connectivity() { return 1; }
    writeSubscribeNginxConfig() {
        writeCalls=$((writeCalls + 1))
        local generatedConfig
        generatedConfig=$(cat)
        if [[ "${mode}" == "config-fail" ]]; then
            SUBSCRIBE_NGINX_CONFIG_WRITE_ERROR="订阅 Nginx 配置校验失败，且旧配置恢复失败"
            return 1
        fi
        printf '%s\n' "${generatedConfig}" >"${nginxConfigPath}subscribe.conf"
    }
    installSubscriptionControlService() {
        controlCalls=$((controlCalls + 1))
        printf '%s:control\n' "${mode}" >>"${serviceLog}"
        [[ "${mode}" == "control-fail" ]] && return 1
        [[ "${mode}" == "final-start-fail" ]] && runtimeRunning=false
        return 0
    }
    bootStartup() {
        bootCalls=$((bootCalls + 1))
        printf '%s:boot\n' "${mode}" >>"${serviceLog}"
        runtimeEnabled=true
        [[ "${mode}" == "boot-fail" ]] && return 1
        return 0
    }
    coreStartupServiceEnabled() { [[ "${runtimeEnabled}" == "true" ]]; }
    restoreCoreStartupServiceInstall() {
        checkLogBackupRestore "$1" || return 1
        runtimeEnabled=$3
        padmRemoveCleanupPath "$1"
    }
    nginxRunning() { [[ "${runtimeRunning}" == "true" ]]; }
    handleNginx() {
        printf '%s:%s:%s\n' "${mode}" "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ -n "${2:-}" ]] && printf '%s:nginx-mode:%s\n' "${mode}" "$*" >>"${serviceLog}"
        if [[ "$1" == "stop" ]]; then
            runtimeRunning=false
            return 0
        fi
        startCalls=$((startCalls + 1))
        if [[ "${mode}" == "final-start-fail" && "${startCalls}" == "2" ]]; then
            return 1
        fi
        if ((startFailures > 0)); then
            startFailures=$((startFailures - 1))
            return 1
        fi
        runtimeRunning=true
        return 0
    }
    pgrep() {
        [[ "${mode}" == "final-start-fail" ]] && return 1
        return 0
    }

    writeCalls=0
    controlCalls=0
    bootCalls=0
    mode=install-fail
    rm -f "${installMarker}" "${firewallState}"
    : >"${firewallLog}"
    set +e
    installSubscribe >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -e "${installMarker}" ]]
    [[ "${writeCalls}" == "0" ]]
    [[ "${controlCalls}" == "0" ]]
    [[ "${bootCalls}" == "0" ]]
    [[ ! -s "${firewallLog}" ]]
    [[ ! -e "${firewallState}" ]]

    writeCalls=0
    controlCalls=0
    bootCalls=0
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    runtimeRunning=true
    runtimeEnabled=false
    startFailures=1
    mode=blog-fail
    rm -f "${firewallState}"
    : >"${firewallLog}"
    set +e
    installSubscribe >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${writeCalls}" == "0" ]]
    grep -qx 'ufw:39778:tcp' "${firewallLog}"
    grep -qx 'ufw:39778:udp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    mode=reload
    rm -f "${firewallState}"
    : >"${firewallLog}"
    set +e
    installSubscribe >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${writeCalls}" == "1" ]]
    [[ "${controlCalls}" == "0" ]]
    [[ "${bootCalls}" == "1" ]]
    grep -qx 'reload:stop:true' "${serviceLog}"
    grep -qx 'reload:start:true' "${serviceLog}"
    grep -qx 'reload:nginx-mode:start restore' "${serviceLog}" || return 1
    grep -q '订阅 Nginx 服务重载失败' "${errorLog}"
    grep -qxF 'old-subscribe-config' "${nginxConfigPath}subscribe.conf"
    [[ "${runtimeRunning}" == "true" ]]
    [[ "${runtimeEnabled}" == "false" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    grep -qx 'ufw:39778:tcp' "${firewallLog}"
    grep -qx 'ufw:39778:udp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    mode=existing-port
    : >"${serviceLog}"
    : >"${firewallLog}"
    rm -f "${firewallState}"
    : >"${errorLog}"
    writeCalls=0
    controlCalls=0
    bootCalls=0
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    runtimeRunning=false
    runtimeEnabled=false
    startFailures=1
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
    [[ "${runtimeEnabled}" == "false" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    [[ ! -s "${firewallLog}" ]]

    mode=config-fail
    : >"${serviceLog}"
    : >"${errorLog}"
    writeCalls=0
    controlCalls=0
    bootCalls=0
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    runtimeRunning=true
    runtimeEnabled=false
    startFailures=0
    rm -f "${firewallState}"
    : >"${firewallLog}"
    set +e
    installSubscribe >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${writeCalls}" == "1" ]]
    [[ "${controlCalls}" == "0" ]]
    [[ "${bootCalls}" == "0" ]]
    grep -q '订阅 Nginx 配置校验失败，且旧配置恢复失败' "${errorLog}"
    grep -qxF 'old-subscribe-config' "${nginxConfigPath}subscribe.conf"
    [[ "${runtimeEnabled}" == "false" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    grep -qx 'ufw:39778:tcp' "${firewallLog}"
    grep -qx 'ufw:39778:udp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    for mode in control-fail boot-fail; do
        : >"${serviceLog}"
        : >"${errorLog}"
        writeCalls=0
        controlCalls=0
        bootCalls=0
        runtimeRunning=true
        if [[ "${mode}" == "control-fail" ]]; then
            runtimeEnabled=true
        else
            runtimeEnabled=false
        fi
        startFailures=0
        rm -f "${firewallState}"
        : >"${firewallLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        set +e
        installSubscribe >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ "${writeCalls}" == "1" ]]
        if [[ "${mode}" == "control-fail" ]]; then
            [[ "${controlCalls}" == "1" ]]
            [[ "${bootCalls}" == "1" ]]
            awk '
                $0 == "control-fail:start:true" { start = NR }
                $0 == "control-fail:control" { control = NR }
                END { exit !(start && control && start < control) }
            ' "${serviceLog}"
        else
            [[ "${controlCalls}" == "0" ]]
            [[ "${bootCalls}" == "1" ]]
        fi
        grep -qxF 'old-subscribe-config' "${nginxConfigPath}subscribe.conf"
        [[ "${runtimeRunning}" == "true" ]]
        if [[ "${mode}" == "control-fail" ]]; then
            [[ "${runtimeEnabled}" == "true" ]]
        else
            [[ "${runtimeEnabled}" == "false" ]]
        fi
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
        grep -qx 'ufw:39778:tcp' "${firewallLog}"
        grep -qx 'ufw:39778:udp' "${firewallLog}"
        [[ ! -e "${firewallState}" ]]
    done

    mode=final-start-fail
    : >"${serviceLog}"
    : >"${errorLog}"
    : >"${firewallLog}"
    rm -f "${firewallState}"
    writeCalls=0
    controlCalls=0
    bootCalls=0
    startCalls=0
    runtimeRunning=true
    runtimeEnabled=false
    startFailures=0
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    set +e
    installSubscribe >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${writeCalls}" == "1" ]]
    grep -qx 'final-start-fail:start:true' "${serviceLog}"
    grep -q '订阅 Nginx 服务启动失败' "${errorLog}"
    grep -qxF 'old-subscribe-config' "${nginxConfigPath}subscribe.conf"
    [[ "${runtimeRunning}" == "true" ]]
    grep -qx 'ufw:39778:tcp' "${firewallLog}"
    grep -qx 'ufw:39778:udp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    PATH="${oldPath}"
)

runSingBoxPortFailureRegression() (
    local result=()
    local subscribeRoot="${TMP_DIR}/subscribe-port-failure"
    local allowLog="${TMP_DIR}/subscribe-port-allow.log"
    local oldPath="${PATH}"
    local oldNginxConfigPath="${nginxConfigPath:-}"
    local oldStaticPath="${nginxStaticPath:-}"
    local oldSubscribePort="${subscribePort:-}"
    local oldAutoSubscribePort="${AUTO_SUBSCRIBE_PORT:-}"
    local oldCurrentHost="${currentHost:-}"
    local oldTlsDir="${PADM_TLS_DIR:-}"
    local writeCalls=0

    : >"${allowLog}"
    allowPort() {
        printf '%s:%s\n' "$1" "${2:-tcp}" >>"${allowLog}"
        return 0
    }

    if readSingBoxPortResult result '1+2' false 2>/dev/null; then
        return 1
    fi
    [[ "${#result[@]}" == "0" ]]
    [[ ! -s "${allowLog}" ]]

    if readSingBoxPortResult result 70000 false 2>/dev/null; then
        return 1
    fi
    [[ "${#result[@]}" == "0" ]]

    : >"${allowLog}"
    readSingBoxPortResult result 39778 false tcp
    [[ "${result[-1]}" == "39778" ]]
    [[ "$(<"${allowLog}")" == "39778:tcp" ]]

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

runAloneNginxConfigWriteTransactionRegression() {
    local nginxRootRel="${TMP_DIR}/nginx-alone"
    local nginxRoot targetPath
    local oldPath="${PATH}"
    mkdir -p "${TMP_DIR}/fake-bin" "${nginxRootRel}"
    nginxRoot=$(cd -- "${nginxRootRel}" && pwd -P)
    targetPath="${nginxRoot}/alone.conf"
    nginxConfigPath="${nginxRoot}/"
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
            if [[ "$1" == "-p" && "$2" == "${targetPath}" ]]; then
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
    unset -f cp

    printf 'old config\n' >"${targetPath}"
    (
        local errorLog="${TMP_DIR}/nginx-alone-write-commit-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
        commitGeneratedFile() {
            if [[ "$2" == "${targetPath}" ]]; then
                return 1
            fi
            originalCommitGeneratedFile "$@"
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
        restoreAloneNginxConfigBackup() {
            ALONE_NGINX_CONFIG_ERROR="Nginx 配置检测失败，且旧 alone.conf 恢复失败，请手动检查 ${targetPath} 和 ${targetPath}.bak"
            printf '%s\n' "${ALONE_NGINX_CONFIG_ERROR}" >>"${errorLog}"
            return 1
        }
        if updateRedirectNginxConf 2>/dev/null; then
            return 1
        fi
        grep -q 'server_name example.com;' "${targetPath}"
        [[ "${ALONE_NGINX_CONFIG_ERROR}" == *"旧 alone.conf 恢复失败"* ]]
        grep -q '旧 alone.conf 恢复失败' "${errorLog}"
    ) || return 1
    printf 'old config\n' >"${targetPath}"
    rm -f "${targetPath}.bak"

    (
        local errorLog="${TMP_DIR}/nginx-alone-write-backup-cleanup-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        rm() {
            if [[ "$1" == "-f" && "$2" == "--" && "$3" == "${targetPath}.bak" ]]; then
                return 1
            fi
            command rm "$@"
        }
        export PADM_FAKE_NGINX_VALIDATE_MODE=success
        if updateRedirectNginxConf >/dev/null 2>&1; then
            return 1
        fi
        grep -q 'server_name example.com;' "${targetPath}"
        [[ -f "${targetPath}.bak" ]]
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

    currentInstallProtocolType=",0,2,24,27,"
    currentHost=example.com
    currentPort=443
    currentPath=padm
    rm -f "${targetPath}"
    ensureTraditionalTlsFallbackNginxConfig >/dev/null 2>&1
    grep -q 'server_name example.com;' "${targetPath}"
    grep -q 'location /padmgrpc {' "${targetPath}"
    grep -q 'listen 127.0.0.1:31302 http2 so_keepalive=on proxy_protocol;' "${targetPath}"

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

    PATH="${oldPath}"
    unset PADM_FAKE_NGINX_VALIDATE_MODE
}

runAloneNginxUpdateTransactionRegression() {
    local nginxRootRel="${TMP_DIR}/nginx-alone-update"
    local nginxRoot targetPath
    local oldPath="${PATH}"
    mkdir -p "${TMP_DIR}/fake-bin" "${nginxRootRel}"
    nginxRoot=$(cd -- "${nginxRootRel}" && pwd -P)
    targetPath="${nginxRoot}/alone.conf"
    nginxConfigPath="${nginxRoot}/"
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

    printf 'keep\nreturn 302 https://example.org;\nreturn 302 $scheme://example.org$request_uri;\n' >"${targetPath}"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    if removeNginx302 2>/dev/null; then
        return 1
    fi
    grep -q 'return 302 https://example.org;' "${targetPath}"

    (
        local errorLog="${TMP_DIR}/nginx-alone-update-restore-error.log"
        : >"${errorLog}"
        restoreAloneNginxConfigBackup() {
            ALONE_NGINX_CONFIG_ERROR="Nginx 配置检测失败，且旧 alone.conf 恢复失败，请手动检查 ${targetPath} 和 ${targetPath}.bak"
            printf '%s\n' "${ALONE_NGINX_CONFIG_ERROR}" >>"${errorLog}"
            return 1
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
    if addNginx302 "https://malicious.example'; add_header X-Padm injected; #" >/dev/null 2>&1; then
        return 1
    fi
    ! grep -q 'X-Padm' "${targetPath}"

    printf 'server {\nlocation / {\n}\n}\n' >"${targetPath}"
    (
        local errorLog="${TMP_DIR}/nginx-alone-update-commit-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
        commitGeneratedFile() {
            if [[ "$2" == "${targetPath}" ]]; then
                return 1
            fi
            originalCommitGeneratedFile "$@"
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

    (
        local curlLog="${TMP_DIR}/nginx-302-curl.log"
        local serviceLog="${TMP_DIR}/nginx-302-service.log"
        PADM_ALONE_NGINX_BACKUP_FILE="${TMP_DIR}/alone_backup.conf"
        printf 'backup config\n' >"${PADM_ALONE_NGINX_BACKUP_FILE}"
        printf 'changed config\n' >"${targetPath}"
        currentHost=example.com
        currentPort=443
        curl() { printf '%s\n' "$*" >>"${curlLog}"; printf '200'; }
        serviceQueueRestart() { printf 'restart\n' >>"${serviceLog}"; }
        serviceQueueApply() { printf 'apply\n' >>"${serviceLog}"; }
        if checkNginx302 2>/dev/null; then
            return 1
        fi
        [[ "$(<"${targetPath}")" == "backup config" ]]
        [[ ! -e "${PADM_ALONE_NGINX_BACKUP_FILE}" ]]
        grep -qx 'restart' "${serviceLog}"
        grep -qx 'apply' "${serviceLog}"
        grep -q -- '--connect-timeout 5' "${curlLog}"
        grep -q -- '--max-time 15' "${curlLog}"

        printf 'backup config\n' >"${PADM_ALONE_NGINX_BACKUP_FILE}"
        printf 'changed config\n' >"${targetPath}"
        curl() { printf '302'; }
        checkNginx302
        [[ "$(<"${targetPath}")" == "changed config" ]]
    )

    (
        local actionLog="${TMP_DIR}/nginx-302-backup-failure.log"
        autoRead() { printf -v "$3" '1'; }
        ensureTraditionalTlsFallbackNginxConfig() { return 0; }
        backupNginxConfig() { printf 'backup\n' >>"${actionLog}"; return 1; }
        removeNginx302() { printf 'remove\n' >>"${actionLog}"; return 0; }
        set +e
        manageTraditionalTlsRedirect >/dev/null 2>&1
        local rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        ! grep -q '^remove$' "${actionLog}"
    )
    PATH="${oldPath}"
    unset PADM_FAKE_NGINX_VALIDATE_MODE
}

runNginxBackupManualCheckRegression() {
    (
        set -euo pipefail
        local rootRel="${TMP_DIR}/nginx-backup-manual-check"
        local root targetPath backupPath
        local helperLog="${TMP_DIR}/nginx-backup-helper.log"
        local errorLog="${TMP_DIR}/nginx-backup-error.log"

        mkdir -p "${rootRel}"
        root=$(cd -- "${rootRel}" && pwd -P)
        targetPath="${root}/alone.conf"
        backupPath="${root}/alone_backup.conf"
        nginxConfigPath="${root}/"
        PADM_ALONE_NGINX_BACKUP_FILE="${backupPath}"
        : >"${helperLog}"
        : >"${errorLog}"
        printf 'source config\n' >"${targetPath}"

        coreSetManualCheckMessage() {
            printf "manual-check:%s|%s\n" "$2" "$3" >>"${helperLog}"
            printf -v "$1" "%s，请手动检查%s" "$2" "$3"
        }
        coreSetPairedFileManualCheckMessage() {
            coreSetManualCheckMessage "$1" "$2" " ${3} 和 ${4}"
        }
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        successCard() { return 0; }

        backupManagedFileToPath() { return 1; }
        if backupNginxConfig backup >/dev/null 2>&1; then
            return 1
        fi
        grep -q "manual-check:nginx配置文件备份失败| ${targetPath}" "${helperLog}"
        grep -q "nginx配置文件备份失败，请手动检查 ${targetPath}" "${errorLog}"

        : >"${helperLog}"
        : >"${errorLog}"
        printf 'backup config\n' >"${backupPath}"
        restoreManagedFileFromBackup() { return 1; }
        if backupNginxConfig restoreBackup >/dev/null 2>&1; then
            return 1
        fi
        grep -q "manual-check:nginx配置文件恢复备份失败| ${targetPath} 和 ${backupPath}" "${helperLog}"
        grep -q "nginx配置文件恢复备份失败，请手动检查 ${targetPath} 和 ${backupPath}" "${errorLog}"

        : >"${helperLog}"
        : >"${errorLog}"
        printf 'backup config\n' >"${backupPath}"
        restoreManagedFileFromBackup() {
            command cp -p "$1" "$2"
        }
        removeManagedFileIfPresent() {
            if [[ "$1" == "${backupPath}" ]]; then
                return 1
            fi
            command rm -f -- "$1"
        }
        if backupNginxConfig restoreBackup >/dev/null 2>&1; then
            return 1
        fi
        grep -q "manual-check:nginx配置备份文件删除失败| ${backupPath}" "${helperLog}"
        grep -q "nginx配置备份文件删除失败，请手动检查 ${backupPath}" "${errorLog}"
    )
}

runCheckPortOpenNginxRejectsDirectoryTargetRegression() {
    (
        set -euo pipefail
        local rootRel="${TMP_DIR}/check-port-nginx-directory-target"
        local root
        local oldPath="${PATH}"
        local targetPath
        mkdir -p "${TMP_DIR}/fake-bin" "${rootRel}/nginx/checkPortOpen.conf"
        root=$(cd -- "${rootRel}" && pwd -P)
        targetPath="${root}/nginx/checkPortOpen.conf"
        nginxConfigPath="${root}/nginx/"
        cat >"${TMP_DIR}/fake-bin/nginx" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "-t" ]]
exit 0
SH
        chmod +x "${TMP_DIR}/fake-bin/nginx"
        PATH="${TMP_DIR}/fake-bin:${PATH}"
        CHECK_PORT_OPEN_NGINX_CONFIG_ERROR=

        if writeCheckPortOpenNginxConfig 443 example.com '' >/dev/null 2>&1; then
            return 1
        fi
        [[ -d "${targetPath}" ]]
        [[ ! -e "${targetPath}/checkPortOpen.conf.tmp" ]]
        [[ "${CHECK_PORT_OPEN_NGINX_CONFIG_ERROR}" == "端口检测 Nginx 配置目标异常，请手动检查 ${targetPath}" ]]

        PATH="${oldPath}"
    )
}

runAloneNginxRejectsDirectoryTargetRegression() {
    (
        set -euo pipefail
        local rootRel="${TMP_DIR}/nginx-alone-directory-target"
        local root
        local oldPath="${PATH}"
        local targetPath errorLog
        mkdir -p "${TMP_DIR}/fake-bin" "${rootRel}/nginx/alone.conf" "${TMP_DIR}/static"
        root=$(cd -- "${rootRel}" && pwd -P)
        targetPath="${root}/nginx/alone.conf"
        errorLog="${root}/error.log"
        nginxConfigPath="${root}/nginx/"
        cat >"${TMP_DIR}/fake-bin/nginx" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-v" ]]; then
    printf 'nginx version: nginx/1.24.0\n' >&2
    exit 0
fi
[[ "$1" == "-t" ]]
exit 0
SH
        chmod +x "${TMP_DIR}/fake-bin/nginx"
        PATH="${TMP_DIR}/fake-bin:${PATH}"
        domain=example.com
        port=443
        currentPath=padm
        nginxStaticPath="${TMP_DIR}/static"
        selectCustomInstallType=9
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }

        if updateRedirectNginxConf >/dev/null 2>&1; then
            return 1
        fi
        [[ -d "${targetPath}" ]]
        [[ ! -e "${targetPath}/alone.conf.tmp" ]]
        grep -qx "Nginx 配置目标异常，请手动检查 ${targetPath}" "${errorLog}"

        PATH="${oldPath}"
    )
}

runSubscribeUserOutputTransactionRegression() {
    local oldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
    local oldPublicDir="${PADM_SUBSCRIBE_DIR:-}"
    local oldScriptDir="${SCRIPT_DIR}"
    local oldTmpDir="${TMPDIR:-}"
    local rootRel="${TMP_DIR}/subscribe-user-transaction"
    local root localDir publicDir userTmpRoot stageMarker clashProfilePath
    local email="atomic-user"
    local emailMd5="atomic-md5"
    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    localDir="${root}/local"
    publicDir="${root}/public"
    userTmpRoot="${root}/tmp"
    stageMarker="${root}/stage-dirs.txt"
    export PADM_SUBSCRIBE_LOCAL_DIR="${localDir}"
    export PADM_SUBSCRIBE_DIR="${publicDir}"
    TMPDIR="${userTmpRoot}"
    SCRIPT_DIR="${PROJECT_ROOT}"
    subscribeType=https
    subscribeSalt=salt
    mkdir -p "${localDir}/default" "${localDir}/clashMeta" "${localDir}/sing-box" "${publicDir}/default" "${publicDir}/clashMeta" "${publicDir}/clashMetaProfiles" "${publicDir}/sing-box" "${publicDir}/sing-box_profiles" "${userTmpRoot}"
    : >"${stageMarker}"
    clashProfilePath="${root}/clash-meta-profile.yaml"
    clashMetaConfig "https://example.com/proxies" "${emailMd5}" "${clashProfilePath}"
    grep -qx 'allow-lan: false' "${clashProfilePath}"
    grep -qx 'bind-address: "127.0.0.1"' "${clashProfilePath}"
    grep -qx 'external-controller: 127.0.0.1:9090' "${clashProfilePath}"
    grep -qx '  allow-origins: \[\]' "${clashProfilePath}"
    grep -qx '  allow-private-network: false' "${clashProfilePath}"
    grep -qx '  listen: 127.0.0.1:1053' "${clashProfilePath}"
    ! grep -qE '^(bind-address: "\*"|external-controller: 0\.0\.0\.0:|  listen: 0\.0\.0\.0:)' "${clashProfilePath}"
    grep -q '^  atomic-md5_provider:' "${clashProfilePath}"
    grep -q '^    path: ./atomic-md5_provider.yaml$' "${clashProfilePath}"
    ! grep -q 'salt_provider' "${clashProfilePath}"
    eval "$(declare -f clashMetaConfig | sed '1s/^clashMetaConfig/originalClashMetaConfig/')"
    eval "$(declare -f commitSubscribeUserOutputFile | sed '1s/^commitSubscribeUserOutputFile/originalCommitSubscribeUserOutputFile/')"

    (
        local stagedPath="${root}/public-mode.stage"
        local targetPath="${root}/public-mode.target"
        eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
        commitGeneratedFile() {
            [[ "${3:-}" == "640" ]] || return 1
            originalCommitGeneratedFile "$@"
        }
        printf 'secret\n' >"${stagedPath}"
        commitSubscribePublicFile "${stagedPath}" "${targetPath}"
        [[ "$(<"${targetPath}")" == "secret" ]]
    )

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

    (
        currentHost=example.com
        rm -rf "${localDir}/default" "${localDir}/clashMeta" "${localDir}/sing-box"
        mkdir -p "${localDir}/default" "${localDir}/clashMeta" "${localDir}/sing-box"
        if defaultBase64Code vmessws 443 'bad"name' '11111111-1111-1111-1111-111111111111' example.com /ws >/dev/null 2>&1; then
            return 1
        fi
        if defaultBase64Code vlessws 443 safe-user '11111111-1111-1111-1111-111111111111' example.com $'/ws\nproxy-groups:' >/dev/null 2>&1; then
            return 1
        fi
        if defaultBase64Code vlessws 443 safe-user '11111111-1111-1111-1111-111111111111' example.com ../ws >/dev/null 2>&1; then
            return 1
        fi
        if regressionFindHasMatches "${localDir}" -mindepth 2 -type f; then
            return 1
        fi
    )

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
        local downloadMarker="${root}/sing-box-template-download.log"
        SCRIPT_DIR="${root}/missing-sing-box-template"
        downloadFile() {
            printf 'download\n' >"${downloadMarker}"
            [[ "$1" == "-O" ]] || return 1
            cp "${PROJECT_ROOT}/documents/sing-box.json" "$2"
        }
        if renderSubscribeUserOutputs "${email}" "${emailMd5}" "example.com" n true 2>/dev/null; then
            return 1
        fi
        [[ ! -e "${downloadMarker}" ]]
    )
    [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
    [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
    [[ "$(<"${publicDir}/clashMetaProfiles/${emailMd5}")" == "old-profile" ]]
    [[ "$(<"${publicDir}/sing-box_profiles/${emailMd5}")" == "old-sing-profile" ]]
    [[ "$(<"${publicDir}/sing-box/${emailMd5}")" == "old-sing" ]]
    if regressionFindHasMatches "${userTmpRoot}" -mindepth 1 -maxdepth 1 -type d; then
        return 1
    fi

    writeOldSubscribeOutputs
    writeLocalSubscribeOutputs
    (
        currentHost=example.com
        subscribePort=
        currentDefaultPort=443
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
        local helperCalls=0
        local helperMessage=
        subscriptionSyncSetSingleRestoreResultMessage() {
            helperCalls=$((helperCalls + 1))
            command printf -v "$1" '%s' "${2}|${3}|${4}|${5}|${6}|${7:-true}"
            [[ "$2" == "订阅生成失败" ]]
            [[ "$3" == "true" ]]
            [[ "$4" == "已恢复旧订阅输出" ]]
            [[ "$5" == "旧订阅输出" ]]
            [[ "$6" == "备份目录: ${subscribeBackupDir}" ]]
            helperMessage=${!1}
            return 0
        }
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
        [[ "${helperCalls}" == "1" ]]
        [[ "${SUBSCRIBE_USER_OUTPUT_ERROR}" == "${helperMessage}" ]]
        [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
        [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
        [[ "$(<"${publicDir}/clashMetaProfiles/${emailMd5}")" == "old-profile" ]]
        [[ "$(<"${publicDir}/sing-box_profiles/${emailMd5}")" == "old-sing-profile" ]]
        [[ "$(<"${publicDir}/sing-box/${emailMd5}")" == "old-sing" ]]
        if regressionFindHasMatches "${userTmpRoot}" -maxdepth 1 -type d -name 'padm-check-log-backup.*'; then
            return 1
        fi
    )

    writeOldSubscribeOutputs
    writeLocalSubscribeOutputs
    (
        local helperCalls=0
        local helperMessage=
        subscriptionSyncSetSingleRestoreResultMessage() {
            helperCalls=$((helperCalls + 1))
            command printf -v "$1" '%s' "${2}|${3}|${4}|${5}|${6}|${7:-true}"
            [[ "$2" == "订阅生成失败" ]]
            [[ "$3" == "false" ]]
            [[ "$4" == "已恢复旧订阅输出" ]]
            [[ "$5" == "旧订阅输出" ]]
            [[ "$6" == "备份目录: ${subscribeBackupDir}" ]]
            helperMessage=${!1}
            return 1
        }
        commitSubscribeUserOutputFile() {
            return 1
        }
        checkLogBackupRestore() {
            return 1
        }
        if renderSubscribeUserOutputs "${email}" "${emailMd5}" "example.com" n true 2>/dev/null; then
            return 1
        fi
        [[ "${helperCalls}" == "1" ]]
        [[ "${SUBSCRIBE_USER_OUTPUT_ERROR}" == "${helperMessage}" ]]
        regressionFindHasMatches "${userTmpRoot}" -maxdepth 1 -type d -name 'padm-check-log-backup.*'
        find "${userTmpRoot}" -maxdepth 1 -type d -name 'padm-check-log-backup.*' -exec rm -rf {} +
    )

    writeLocalSubscribeOutputs
    renderSubscribeUserOutputs "${email}" "${emailMd5}" "example.com" n true
    grep -q . "${stageMarker}"
    while IFS= read -r path; do
        [[ -z "${path}" || "${path}" == "${userTmpRoot}"/padm-subscribe-user.* ]] || return 1
    done <"${stageMarker}"
    if regressionFindHasMatches "${userTmpRoot}" -mindepth 1 -maxdepth 1 -type d; then
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
    [[ "${subscribeSalt}" =~ ^[0-9a-f]{32}$ ]]
    [[ "$(<"${localDir}/subscribeSalt")" == "${subscribeSalt}" ]]

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
    local publicDir="${TMP_DIR}/subscribe-return-public"
    local oldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
    local oldPublicDir="${PADM_SUBSCRIBE_DIR:-}"
    local installCalls=0
    local renderCalls=0
    local showAccountsCalls=0

    # Re-source manage.sh because the regression bootstrap replaces subscribe with a menu-safe no-op.
    source "${PROJECT_ROOT}/shell/core/manage.sh"
    export PADM_SUBSCRIBE_LOCAL_DIR="${localDir}"
    export PADM_SUBSCRIBE_DIR="${publicDir}"
    mkdir -p "${localDir}/default" "${localDir}/clashMeta" "${localDir}/sing-box"
    mkdir -p "${publicDir}"
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
    if [[ -n "${oldPublicDir}" ]]; then export PADM_SUBSCRIBE_DIR="${oldPublicDir}"; else unset PADM_SUBSCRIBE_DIR; fi
)

runSubscribeLocalRollbackRegression() (
    local rootRel="${TMP_DIR}/subscribe-local-rollback"
    local root localDir publicDir errorLog callLog beforeSnapshot beforePublicSnapshot
    local oldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
    local oldPublicDir="${PADM_SUBSCRIBE_DIR:-}"
    local oldTmpDir="${TMPDIR:-}"
    local oldSubscribeSalt="${subscribeSalt:-}"
    local renderCalls=0
    local showAccountsCalls=0
    local rc

    captureSubscribeLocalSnapshot() {
        find "${localDir}" -type f -printf '%P\t' -exec cat {} \; | sort
    }
    captureSubscribePublicSnapshot() {
        find "${publicDir}" -type f -printf '%P\t' -exec cat {} \; | sort
    }

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    localDir="${root}/subscribe_local"
    publicDir="${root}/subscribe_public"
    errorLog="${root}/error.log"
    callLog="${root}/calls.log"
    beforeSnapshot="${root}/before.txt"
    beforePublicSnapshot="${root}/before-public.txt"
    source "${PROJECT_ROOT}/shell/core/manage.sh"
    export PADM_SUBSCRIBE_LOCAL_DIR="${localDir}"
    export PADM_SUBSCRIBE_DIR="${publicDir}"
    TMPDIR="${root}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    mkdir -p "${localDir}/default" "${localDir}/clashMeta" "${localDir}/sing-box"
    mkdir -p "${publicDir}/default" "${publicDir}/clashMeta" "${publicDir}/clashMetaProfiles" "${publicDir}/sing-box" "${publicDir}/sing-box_profiles"
    printf 'existing-salt\n' >"${localDir}/subscribeSalt"
    printf 'old default\n' >"${localDir}/default/existing"
    printf 'old clash\n' >"${localDir}/clashMeta/existing"
    printf '[{"tag":"old-local"}]\n' >"${localDir}/sing-box/existing"
    printf 'old public\n' >"${publicDir}/default/existing"
    subscribeSalt=existing-salt
    captureSubscribeLocalSnapshot >"${beforeSnapshot}"
    captureSubscribePublicSnapshot >"${beforePublicSnapshot}"

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
    showAccountsCalls=0
    resolveSubscribeSalt() {
        writeSubscribeSalt "$1" "new-salt"
        subscribeSalt="new-salt"
        return 1
    }
    showAccounts() {
        showAccountsCalls=$((showAccountsCalls + 1))
        printf 'showAccounts\n' >>"${callLog}"
        return 0
    }
    coreInstallType=1
    set +e
    subscribe false true >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${showAccountsCalls}" == "0" ]]
    [[ "${renderCalls}" == "0" ]]
    [[ "${subscribeSalt}" == "existing-salt" ]]
    [[ "$(<"${localDir}/subscribeSalt")" == "existing-salt" ]]
    diff -u "${beforeSnapshot}" <(captureSubscribeLocalSnapshot)
    grep -q '订阅 Salt 初始化失败，已恢复旧订阅输出' "${errorLog}"
    ! regressionFindHasMatches "${root}" -maxdepth 1 -type d -name 'padm-subscription-output-backup.*'

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
    grep -q '订阅生成失败：重建本地订阅失败，已恢复旧订阅输出' "${errorLog}"
    grep -qx 'showAccounts' "${callLog}"
    ! regressionFindHasMatches "${root}" -maxdepth 1 -type d -name 'padm-subscription-output-backup.*'

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
        printf 'new public\n' >"${publicDir}/default/existing"
        printf 'first account published\n' >"${publicDir}/default/first-account"
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
    diff -u "${beforePublicSnapshot}" <(captureSubscribePublicSnapshot)
    [[ ! -e "${publicDir}/default/first-account" ]]
    grep -q '订阅生成失败：生成订阅输出失败，已恢复旧订阅输出' "${errorLog}"
    grep -qx 'showAccounts' "${callLog}"
    grep -qx 'render' "${callLog}"
    ! regressionFindHasMatches "${root}" -maxdepth 1 -type d -name 'padm-subscription-output-backup.*'

    if [[ -n "${oldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${oldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
    if [[ -n "${oldPublicDir}" ]]; then export PADM_SUBSCRIBE_DIR="${oldPublicDir}"; else unset PADM_SUBSCRIBE_DIR; fi
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
    if regressionFindHasMatches "${backupsDir}" -maxdepth 1 -type f -name 'groups-pre-migrate-*.json'; then
        return 1
    fi

    jq '.version = 2 | .active_group = "missing" | .groups[0].sync.event_enabled = true' "${stateFile}" >"${stateFile}.tmp"
    mv "${stateFile}.tmp" "${stateFile}"
    migrateSubscriptionGroupsState
    [[ "$(jq -r '.active_group' "${stateFile}")" == "default" ]]
    set +e
    subscriptionGroupRead missing -r '.id' >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" -ne 0 ]]

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
    local backupModeLog="${root}/backup-mode.log"
    local chmodLog="${root}/chmod.log"
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
    : >"${backupModeLog}"
    : >"${chmodLog}"
    eval "$(declare -f backupManagedFileToPath | sed '1s/^backupManagedFileToPath/originalBackupManagedFileToPath/')"
    backupManagedFileToPath() {
        printf '%s|%s|%s\n' "$1" "$2" "${3:-}" >>"${backupModeLog}"
        originalBackupManagedFileToPath "$@"
    }

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
    if regressionFindHasMatches "${backupsDir}" -maxdepth 1 -type f -name 'groups-*.json'; then
        return 1
    fi
    chmod() {
        printf '%s\n' "$*" >>"${chmodLog}"
        command chmod "$@"
    }
    backupFile=$(createSubscriptionGroupsBackup)
    [[ -f "${backupFile}" ]]
    grep -Fxq "${stateFile}|${backupFile}|600" "${backupModeLog}"
    grep -Fxq "700 ${backupsDir}" "${chmodLog}"
    command chmod 755 "${backupsDir}"
    command chmod 644 "${backupFile}"
    : >"${chmodLog}"
    subscriptionGroupsSecureStateFiles
    grep -Fxq "700 ${backupsDir}" "${chmodLog}"
    grep -Fxq "600 ${backupFile}" "${chmodLog}"

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
    ! regressionFindHasMatches "${root}" -maxdepth 1 -type d -name 'padm-refresh-local-subscriptions.*'

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
    showAccounts() {
        printf 'showAccounts\n' >>"${callLog}"
        return 0
    }
    set +e
    refreshLocalSubscriptions "XHTTP" "已刷新本地订阅" >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${cleanCalls}" == "2" ]]
    diff -u "${beforeSnapshot}" <(captureRefreshLocalSnapshot)
    grep -q '清理本地订阅目录失败，已恢复旧本地订阅' "${errorLog}"
    ! grep -q '^showAccounts$' "${callLog}"
    ! regressionFindHasMatches "${root}" -maxdepth 1 -type d -name 'padm-refresh-local-subscriptions.*'

    if [[ -n "${oldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${oldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
    if [[ -n "${oldTmpDir}" ]]; then TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runRemoveUserSubscriptionMenuFailureRegression() (
    local root="${TMP_DIR}/remove-user-subscription-menu-failure"
    local callLog="${root}/calls.log"
    local successLog="${root}/success.log"
    local statusLog="${root}/status.log"
    local errorLog="${root}/error.log"
    local helperLog="${root}/helper.log"
    local backupDir="${root}/backup"
    local mode rc

    mkdir -p "${root}"
    : >"${callLog}"
    : >"${successLog}"
    : >"${statusLog}"
    : >"${errorLog}"
    : >"${helperLog}"

    autoRead() {
        printf -v "$3" 'yes'
    }
    subscriptionGroupsFile() {
        printf '%s\n' "${root}/groups.json"
    }
    subscriptionGroupsStateRead() {
        [[ "${mode}" != "groups-read-fail" ]] || return 1
        printf '{"version":2,"active_group":"default","groups":[{"id":"default","user_groups":[{"id":"team-a","enabled":true}]}]}\n'
    }
    subscriptionSyncCreateConfigBackups() {
        local resultVar=$1
        printf 'backup-create\n' >>"${callLog}"
        [[ "${mode}" != "backup-fail" ]] || return 1
        mkdir -p "${backupDir}"
        printf -v "${resultVar}" '%s' "${backupDir}"
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
        [[ "${mode}" != "account-fail" && "${mode}" != "state-restore-fail" && "${mode}" != "account-restore-fail" && "${mode}" != "both-restore-fail" ]]
    }
    subscriptionGroupsStateWrite() {
        printf 'state-restore\n' >>"${callLog}"
        [[ "${mode}" != "state-restore-fail" && "${mode}" != "both-restore-fail" ]]
    }
    subscriptionSyncRestoreConfigBackups() {
        printf 'account-restore:%s\n' "$1" >>"${callLog}"
        [[ "${mode}" != "account-restore-fail" && "${mode}" != "both-restore-fail" ]]
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
    subscriptionEventSyncEnabled() {
        return 0
    }
    runSubscriptionGroupSync() {
        printf 'sync:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" != "sync-fail" ]]
    }
    successCard() {
        printf '%s\n' "$*" >>"${successLog}"
    }
    statusCard() {
        printf '%s\n' "$*" >>"${statusLog}"
    }
    errorCard() {
        printf '%s\n' "$*" >>"${errorLog}"
    }
    subscriptionSyncSetManualCheckMessage() {
        printf "manual-check:%s|%s\n" "$2" "$3" >>"${helperLog}"
        printf -v "$1" "%s，请手动检查%s" "$2" "$3"
    }
    runRemoveCase() {
        mode=$1
        : >"${callLog}"
        : >"${successLog}"
        : >"${statusLog}"
        : >"${errorLog}"
        : >"${helperLog}"
        set +e
        removeUserSubscriptionMenu team-a >/dev/null 2>&1
        rc=$?
        set -e
    }

    runRemoveCase groups-read-fail
    [[ "${rc}" == "1" ]]
    ! grep -q '^backup-create$' "${callLog}"
    ! grep -q '^sync:' "${callLog}"
    grep -q "manual-check:读取当前订阅状态失败| ${root}/groups.json" "${helperLog}"
    grep -q "读取当前订阅状态失败，请手动检查 ${root}/groups.json" "${errorLog}"
    [[ ! -s "${successLog}" ]]

    runRemoveCase backup-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'backup-create' "${callLog}"
    ! grep -q '^state:' "${callLog}"
    ! grep -q '^sync:' "${callLog}"
    grep -q "manual-check:删除订阅前托管账号配置备份失败|本机配置" "${helperLog}"
    grep -q "删除订阅前托管账号配置备份失败，请手动检查本机配置" "${errorLog}"
    [[ ! -s "${successLog}" ]]

    runRemoveCase state-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'backup-create' "${callLog}"
    grep -qx 'state:team-a' "${callLog}"
    ! grep -q '^account:' "${callLog}"
    ! grep -qx 'reload' "${callLog}"
    ! grep -q '^sync:' "${callLog}"
    grep -qx "cleanup:${backupDir}" "${callLog}"
    [[ ! -s "${successLog}" ]]

    runRemoveCase account-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'backup-create' "${callLog}"
    grep -qx 'state:team-a' "${callLog}"
    grep -qx 'account:sub_team-a' "${callLog}"
    ! grep -qx 'reload' "${callLog}"
    ! grep -q '^sync:' "${callLog}"
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
    ! grep -q '^sync:' "${callLog}"
    grep -qx 'state-restore' "${callLog}"
    grep -qx "account-restore:${backupDir}" "${callLog}"
    grep -qx "cleanup:${backupDir}" "${callLog}"
    ! grep -q '^sync:' "${callLog}"
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
    ! grep -q '^sync:' "${callLog}"
    grep -q '托管账号配置恢复失败' "${errorLog}"
    [[ ! -s "${successLog}" ]]

    runRemoveCase both-restore-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'state:team-a' "${callLog}"
    grep -qx 'account:sub_team-a' "${callLog}"
    grep -qx 'state-restore' "${callLog}"
    grep -qx "account-restore:${backupDir}" "${callLog}"
    grep -qx "keep-backup:${backupDir}" "${callLog}"
    ! grep -q '^sync:' "${callLog}"
    grep -q '订阅状态与托管账号配置恢复失败' "${errorLog}"
    [[ ! -s "${successLog}" ]]

    runRemoveCase success
    [[ "${rc}" == "0" ]]
    grep -qx "cleanup:${backupDir}" "${callLog}"
    grep -qx 'reload' "${callLog}"
    grep -qx 'sync:skip-subscribe-refresh' "${callLog}"
    grep -q '用户订阅已删除' "${successLog}"

    runRemoveCase sync-fail
    [[ "${rc}" == "0" ]]
    grep -qx "cleanup:${backupDir}" "${callLog}"
    grep -qx 'reload' "${callLog}"
    grep -qx 'sync:skip-subscribe-refresh' "${callLog}"
    grep -q '用户订阅已删除' "${successLog}"
    grep -q '订阅已删除，但自动同步失败' "${statusLog}"
)

runUserSubscriptionMenuMutationFailureRegression() (
    local root="${TMP_DIR}/user-subscription-menu-mutation-failure"
    local callLog="${root}/calls.log"
    local successLog="${root}/success.log"
    local statusLog="${root}/status.log"
    local errorLog="${root}/error.log"
    local mode rc menuStep=0 syncMenuChoice=8

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
        user_subscription_id) printf -v "${targetVar}" 'team-new' ;;
        user_subscription_name) printf -v "${targetVar}" 'Team New' ;;
        user_subscription_sources)
            if [[ "${mode}" == "empty-sources" ]]; then
                printf -v "${targetVar}" ', ,'
            elif [[ "${mode}" == "invalid-source" ]]; then
                printf -v "${targetVar}" 'main,missing-source'
            else
                printf -v "${targetVar}" 'main,remote-a'
            fi
            ;;
        user_subscription_traffic_limit) printf -v "${targetVar}" '100' ;;
        user_subscription_item_menu)
            menuStep=$((menuStep + 1))
            if [[ "${menuStep}" == "1" ]]; then
                printf -v "${targetVar}" '6'
            else
                printf -v "${targetVar}" '9'
            fi
            ;;
        sync_settings_menu)
            menuStep=$((menuStep + 1))
            if [[ "${menuStep}" == "1" ]]; then
                printf -v "${targetVar}" "${syncMenuChoice}"
            else
                printf -v "${targetVar}" '12'
            fi
            ;;
        *) printf -v "${targetVar}" '' ;;
        esac
    }
    subscriptionSyncAccountName() {
        printf 'sub_%s\n' "$1"
    }
    subscribe() {
        printf 'subscribe:%s|%s|%s|%s\n' "${1:-}" "${2:-}" "${3:-}" "${4:-}" >>"${callLog}"
        [[ "${mode}" != "subscribe-fail" ]]
    }
    ensureSubscriptionServiceForSharedLinks() {
        [[ "${mode}" != "service-install-fail" ]] || return 2
    }
    addUserSubscriptionState() {
        printf 'create:%s:%s:%s:%s\n' "$1" "$2" "$3" "$4" >>"${callLog}"
        [[ "${mode}" != "create-state-fail" ]]
    }
    setUserSubscriptionSources() {
        printf 'sources:%s:%s\n' "$1" "$2" >>"${callLog}"
        [[ "${mode}" != "sources-fail" ]]
    }
    setUserSubscriptionTrafficLimit() {
        printf 'limit:%s:%s\n' "$1" "$2" >>"${callLog}"
        [[ "${mode}" != "limit-fail" ]]
    }
    runSubscriptionGroupSync() {
        printf 'sync:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" != "sync-fail" ]]
    }
    selectUserSubscriptionId() {
        selectedUserSubscriptionId=team-a
    }
    showUserSubscriptions() { return 0; }
    showUserSubscriptionTraffic() { return 0; }
    showSubscriptionLocalSyncPlan() { return 0; }
    subscriptionRequireMainRole() { return 0; }
    subscriptionActiveGroupRead() {
        if [[ "$*" == *'.sync'* ]]; then
            printf '{}\n'
        elif [[ "$*" == *'.sources[]?.id'* ]]; then
            printf '%s\n' main remote-a
        else
            printf '%s\n' \
                'main:Main:main:local:127.0.0.1:0:true:local' \
                'remote-a:Remote A:secondary:wireguard:10.77.0.2:39778:true:success'
        fi
    }
    removeUserSubscriptionMenu() { return 0; }
    toggleUserSubscriptionState() {
        printf 'toggle:%s\n' "$1" >>"${callLog}"
        [[ "${mode}" != "toggle-fail" ]]
    }
    toggleSubscriptionGroupRemoteSyncEnabled() {
        printf 'sync-toggle:remote\n' >>"${callLog}"
        [[ "${mode}" != "sync-settings-fail" ]]
    }
    toggleSubscriptionGroupQuotaAutoApplyEnabled() {
        printf 'sync-toggle:quota\n' >>"${callLog}"
        [[ "${mode}" != "sync-settings-fail" ]]
    }
    toggleSubscriptionEventSyncEnabled() {
        printf 'sync-toggle:event\n' >>"${callLog}"
        [[ "${mode}" != "sync-settings-fail" ]]
    }
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

    mode=event-disabled
    resetLogs
    subscriptionEventSyncEnabled() { return 1; }
    runSubscriptionEventSyncIfEnabled "test-disabled" >/dev/null 2>&1
    ! grep -q '^sync:' "${callLog}"
    grep -q '等待手动/定时同步' "${statusLog}"
    subscriptionEventSyncEnabled() { [[ "${mode}" != "event-disabled" ]]; }

    mode=service-install-fail
    resetLogs
    set +e
    createAndSyncUserSubscriptionWizard >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    ! grep -q '^create:' "${callLog}"

    mode=create-state-fail
    resetLogs
    set +e
    createAndSyncUserSubscriptionWizard >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qxF 'create:team-new:Team New:["main","remote-a"]:100' "${callLog}"
    grep -q '分享订阅创建失败' "${errorLog}"
    ! grep -q '分享订阅已创建' "${statusLog}"
    ! grep -q '^sync:' "${callLog}"

    mode=success
    resetLogs
    runSubscriptionEventSyncIfEnabled "test-enabled" >/dev/null 2>&1
    grep -qx 'sync:skip-subscribe-refresh' "${callLog}"

    mode=subscribe-fail
    resetLogs
    set +e
    showUserSubscriptionLinks team-a >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'subscribe:false||sub_team-a|true' "${callLog}"
    grep -q '订阅输出刷新失败' "${errorLog}"
    [[ ! -s "${statusLog}" ]]

    mode=empty-sources
    resetLogs
    set +e
    setUserSubscriptionSourcesMenu team-a >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    ! grep -q '^sources:team-a:' "${callLog}"
    grep -q '服务器范围不能为空' "${errorLog}"
    [[ ! -s "${successLog}" ]]

    mode=invalid-source
    resetLogs
    set +e
    setUserSubscriptionSourcesMenu team-a >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    ! grep -q '^sources:team-a:' "${callLog}"
    grep -q '服务器范围包含不存在的服务器源' "${errorLog}"
    [[ ! -s "${successLog}" ]]

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

    mode=sync-settings-fail
    syncMenuChoice=8
    resetLogs
    manageSubscriptionSyncSettings >/dev/null 2>&1
    grep -qx 'sync-toggle:remote' "${callLog}"
    grep -q '远程同步状态切换失败' "${errorLog}"
    ! grep -q '远程同步状态已切换' "${successLog}"

    syncMenuChoice=9
    resetLogs
    manageSubscriptionSyncSettings >/dev/null 2>&1
    grep -qx 'sync-toggle:quota' "${callLog}"
    grep -q '限额自动执行状态切换失败' "${errorLog}"
    ! grep -q '限额自动执行状态已切换' "${successLog}"

    syncMenuChoice=10
    resetLogs
    manageSubscriptionSyncSettings >/dev/null 2>&1
    grep -qx 'sync-toggle:event' "${callLog}"
    grep -q '事件同步状态切换失败' "${errorLog}"
    ! grep -q '事件同步状态已切换' "${successLog}"

    mode=success
    resetLogs
    showUserSubscriptionLinks team-a >/dev/null 2>&1
    grep -q '用户订阅链接' "${statusLog}"
    resetLogs
    setUserSubscriptionSourcesMenu team-a >/dev/null 2>&1
    grep -q '节点范围已更新' "${successLog}"
    grep -qx 'sync:skip-subscribe-refresh' "${callLog}"
    resetLogs
    setUserSubscriptionTrafficLimitMenu team-a >/dev/null 2>&1
    grep -q '订阅额度已更新' "${successLog}"
    grep -qx 'sync:skip-subscribe-refresh' "${callLog}"
    resetLogs
    manageUserSubscriptionItem >/dev/null 2>&1
    grep -q '用户订阅状态已切换' "${successLog}"
    grep -qx 'sync:skip-subscribe-refresh' "${callLog}"
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
    local refreshMode=success
    local serviceLog="${TMP_DIR}/reality-stream-disable-services.log"
    local firewallLog="${TMP_DIR}/reality-stream-disable-firewall.log"
    local errorLog="${TMP_DIR}/reality-stream-disable-errors.log"
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
    : >"${firewallLog}"
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
        [[ "${refreshMode}" == "success" ]]
    }

    denyPort() {
        printf 'deny:%s:%s\n' "$1" "${2:-tcp}" >>"${firewallLog}"
    }

    errorCard() {
        printf '%s\n' "$*" >>"${errorLog}"
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
        : >"${firewallLog}"
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
    if regressionFindHasMatches "${streamTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-reality-stream-disable.*'; then
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
    if regressionFindHasMatches "${streamTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-reality-stream-disable.*'; then
        return 1
    fi

    writeRealityStreamFixture
    serviceMode=success
    refreshMode=fail
    : >"${serviceLog}"
    : >"${errorLog}"
    set +e
    disableRealityStreamSplit >/dev/null 2>&1
    disableStatus=$?
    set -e
    [[ "${disableStatus}" == "1" ]]
    [[ ! -e "${stateFile}" && ! -e "${streamConf}" ]]
    grep -qx 'refresh' "${serviceLog}"
    grep -q 'Reality 443 共存分流已关闭，但订阅刷新失败' "${errorLog}"
    [[ ! -s "${firewallLog}" ]]

    writeRealityStreamFixture
    jq '.firewall_owned = true | .protocols.vision.restore_port = 8443 | .protocols.xhttp.restore_port = 9443' "${stateFile}" >"${stateFile}.tmp"
    mv "${stateFile}.tmp" "${stateFile}"
    serviceMode=success
    refreshMode=success
    : >"${serviceLog}"
    export PADM_FAKE_REALITY_STREAM_XRAY_VALIDATE_MODE=success
    disableRealityStreamSplit
    jq -e '(.inbounds[0].listen | not) and .inbounds[0].port == 8443' "${visionFile}" >/dev/null
    jq -e '.inbounds[0].listen == "0.0.0.0" and .inbounds[0].port == 9443' "${xhttpFile}" >/dev/null
    [[ ! -e "${stateFile}" ]]
    [[ ! -e "${streamConf}" ]]
    grep -qx 'deny:443:tcp' "${firewallLog}"
    ! grep -q 'padm stream include start' "${nginxMainConf}"
    if regressionFindHasMatches "${streamTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-reality-stream-disable.*'; then
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
    local refreshMode=success
    local serviceLog="${TMP_DIR}/reality-stream-enable-services.log"
    local firewallLog="${TMP_DIR}/reality-stream-enable-firewall.log"
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
vision_file="${PADM_FAKE_REALITY_STREAM_VISION_FILE:-}"
if [[ "${PADM_FAKE_REALITY_STREAM_CP_MODE:-success}" == "restore-vision-fail" && -n "${vision_file}" ]]; then
    vision_dir="$(dirname -- "${vision_file}")"
    vision_base="$(basename -- "${vision_file}")"
    case "${target}" in
    "${vision_file}"|${vision_dir}/.${vision_base}.restore.*)
        exit 1
        ;;
    esac
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
    : >"${firewallLog}"
    : >"${errorLog}"

    local nginxInstallMarker="${streamDir}/nginx-install.marker"
    (
        command() {
            if [[ "${1:-}" == "-v" && "${2:-}" == "nginx" ]]; then
                return 1
            fi
            builtin command "$@"
        }
        nginx() { return 127; }
        installNginxTools() {
            : >"${nginxInstallMarker}"
            exit 17
        }
        rm -f "${nginxInstallMarker}"
        set +e
        configureRealityStreamSplit >/dev/null 2>&1
        local installStatus=$?
        set -e
        [[ "${installStatus}" == "1" ]]
        [[ -e "${nginxInstallMarker}" ]]
    )

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

    allowPort() {
        printf 'allow:%s:%s\n' "$1" "${2:-tcp}" >>"${firewallLog}"
        PADM_LAST_ALLOW_PORT_ADDED=true
        padmTrackPortAllowTransactionKey "port:ufw:${2:-tcp}:$1"
    }

    padmRollbackPortAllowTransaction() {
        printf 'rollback\n' >>"${firewallLog}"
        PADM_PORT_ALLOW_TRANSACTION_KEYS=
    }

    realityStreamRefreshSubscribeIfInstalled() {
        printf 'refresh\n' >>"${serviceLog}"
        [[ "${refreshMode}" == "success" ]]
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
        : >"${firewallLog}"
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
    grep -qx 'allow:443:tcp' "${firewallLog}"
    grep -qx 'rollback' "${firewallLog}"

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
    if regressionFindHasMatches "${streamTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-reality-stream.*'; then
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
    grep -qx 'allow:443:tcp' "${firewallLog}"
    grep -qx 'rollback' "${firewallLog}"
    if regressionFindHasMatches "${streamTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-reality-stream.*'; then
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
    [[ "$(<"${visionFile}")" == "${originalVision}" ]]
    [[ "$(<"${xhttpFile}")" == "${originalXHTTP}" ]]
    [[ "$(<"${nginxMainConf}")" == "${originalNginxConf}" ]]
    [[ ! -e "${stateFile}" ]]
    [[ ! -e "${streamConf}" ]]
    grep -q '已回滚本次修改' "${errorLog}"
    grep -q '恢复旧配置后服务应用仍失败' "${errorLog}"
    if regressionFindHasMatches "${streamTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-reality-stream.*'; then
        return 1
    fi
    export PADM_FAKE_REALITY_STREAM_CP_MODE=success

    writeRealityStreamEnableFixture
    serviceMode=success
    refreshMode=fail
    : >"${serviceLog}"
    : >"${errorLog}"
    set +e
    configureRealityStreamSplit >/dev/null 2>&1
    enableStatus=$?
    set -e
    [[ "${enableStatus}" == "1" ]]
    [[ -f "${stateFile}" && -f "${streamConf}" ]]
    grep -qx 'allow:443:tcp' "${firewallLog}"
    ! grep -qx 'rollback' "${firewallLog}"
    grep -q 'Reality 443 共存分流已生效，但订阅刷新失败' "${errorLog}"

    writeRealityStreamEnableFixture
    serviceMode=success
    refreshMode=success
    : >"${serviceLog}"
    : >"${errorLog}"
    export PADM_FAKE_REALITY_STREAM_XRAY_VALIDATE_MODE=success
    configureRealityStreamSplit
    jq -e '.inbounds[0].listen == "127.0.0.1" and .inbounds[0].port == 2443' "${visionFile}" >/dev/null
    jq -e '.enabled == true and .firewall_owned == true and .default_protocol == "vision" and .protocols.vision.restore_port == 443 and .protocols.vision.internal_port == 2443' "${stateFile}" >/dev/null
    grep -qx 'allow:443:tcp' "${firewallLog}"
    ! grep -qx 'rollback' "${firewallLog}"
    selectCustomInstallType=1
    nginxConfigPath="${streamDir}/no-subscription/"
    subscriptionWireGuardControlEnabled() { return 1; }
    nginxRuntimeRequired
    grep -q 'site.example.com padm_website;' "${streamConf}"
    grep -q 'padm stream include start' "${nginxMainConf}"
    grep -Fq "include ${streamDir}/*.conf;" "${nginxMainConf}"
    [[ ! -e "${streamConf}.tmp" ]]
    if regressionFindHasMatches "${streamTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-reality-stream.*'; then
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
    local _sampleIp prefixFirst prefixLast prefixUsable
    AUTO_INSTALL=
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
    if [[ -n "${oldAutoInstall}" ]]; then
        AUTO_INSTALL="${oldAutoInstall}"
    else
        unset AUTO_INSTALL
    fi
}

runRealityCandidateFullRegression() {
    local firstRecommendedRealityCandidate firstDeveloperRealityCandidate firstRealityCandidate secondRealityCandidate blockedCloudflareRealityCandidate
    [[ "$(realityTargetCandidateCount)" -ge 194 ]]
    [[ "$(realityTargetFilteredCandidateCount recommended)" -ge 40 ]]
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
    realityTargetBlockedCandidates >/dev/null
    ! realityTargetCandidates | grep -q '^www.cloudflare.com|'
    ! realityTargetCandidates | grep -q '^www.apple.com|'
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

    set +e
    addRealityTargetBlockedCandidate "new.example.com:443" "manual" >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
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

runSingBoxRealityKeyTransactionRegression() (
    local rootRel="${TMP_DIR}/singbox-reality-key-transaction"
    local root singBoxBinary keyFile
    local oldSingBoxBinary="${PADM_SINGBOX_BINARY:-}"
    local oldRealityKeyFile="${PADM_SINGBOX_REALITY_KEY_FILE:-}"
    local oldSelectCoreType="${selectCoreType:-}"
    local oldCoreInstallType="${coreInstallType:-}"
    local oldLastInstallationConfig="${lastInstallationConfig:-}"
    local oldCurrentRealityPublicKey="${currentRealityPublicKey:-}"
    local oldCurrentRealityPrivateKey="${currentRealityPrivateKey:-}"
    local oldRealityPrivateKey="${realityPrivateKey:-}"
    local oldRealityPublicKey="${realityPublicKey:-}"
    local rc

    mkdir -p "${rootRel}/sing-box" "${rootRel}/config"
    root=$(cd -- "${rootRel}" && pwd -P) || return 1
    singBoxBinary="${root}/sing-box/sing-box"
    keyFile="${root}/config/reality_key"
    cat >"${singBoxBinary}" <<'EOF'
#!/usr/bin/env bash
printf 'PrivateKey private-generated\n'
printf 'PublicKey public-generated\n'
EOF
    chmod +x "${singBoxBinary}"
    printf 'publicKey:old-public\n' >"${keyFile}"

    PADM_SINGBOX_BINARY="${singBoxBinary}"
    PADM_SINGBOX_REALITY_KEY_FILE="${keyFile}"
    selectCoreType=2
    coreInstallType=2
    lastInstallationConfig=
    currentRealityPublicKey=
    currentRealityPrivateKey=
    realityPrivateKey=
    realityPublicKey=

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${keyFile}" ]]; then
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    set +e
    initRealityKey >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${keyFile}")" == "publicKey:old-public" ]]
    [[ "${realityPrivateKey}" == "private-generated" ]]
    [[ "${realityPublicKey}" == "public-generated" ]]
    ! compgen -G "${root}/config/.reality_key.reality.*" >/dev/null

    commitGeneratedFile() {
        originalCommitGeneratedFile "$@"
    }
    realityPrivateKey=
    realityPublicKey=
    initRealityKey >/dev/null
    [[ "${realityPrivateKey}" == "private-generated" ]]
    [[ "${realityPublicKey}" == "public-generated" ]]
    [[ "$(<"${keyFile}")" == "publicKey:public-generated" ]]
    ! compgen -G "${root}/config/.reality_key.reality.*" >/dev/null
    ! grep -qF 'statusCard "Reality Key" "privateKey:${realityPrivateKey}"' "${PROJECT_ROOT}/shell/core/protocol_runtime.sh"

    lastInstallationConfig=true
    currentRealityPrivateKey=private-reused
    currentRealityPublicKey=public-reused
    realityPrivateKey=
    realityPublicKey=
    initRealityKey >/dev/null
    [[ "${realityPrivateKey}" == "private-reused" ]]
    [[ "${realityPublicKey}" == "public-reused" ]]
    [[ "$(<"${keyFile}")" == "publicKey:public-reused" ]]

    lastInstallationConfig=
    currentRealityPrivateKey=
    currentRealityPublicKey=
    printf 'publicKey:public-generated\n' >"${keyFile}"

    cat >"${singBoxBinary}" <<'EOF'
#!/usr/bin/env bash
exit 23
EOF
    chmod +x "${singBoxBinary}"
    realityPrivateKey=
    realityPublicKey=
    set +e
    initRealityKey >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${keyFile}")" == "publicKey:public-generated" ]]

    cat >"${singBoxBinary}" <<'EOF'
#!/usr/bin/env bash
printf 'PrivateKey private-only\n'
EOF
    chmod +x "${singBoxBinary}"
    realityPrivateKey=
    realityPublicKey=
    set +e
    initRealityKey >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${keyFile}")" == "publicKey:public-generated" ]]

    if [[ -n "${oldSingBoxBinary}" ]]; then
        PADM_SINGBOX_BINARY="${oldSingBoxBinary}"
    else
        unset PADM_SINGBOX_BINARY
    fi
    if [[ -n "${oldRealityKeyFile}" ]]; then
        PADM_SINGBOX_REALITY_KEY_FILE="${oldRealityKeyFile}"
    else
        unset PADM_SINGBOX_REALITY_KEY_FILE
    fi
    selectCoreType="${oldSelectCoreType}"
    coreInstallType="${oldCoreInstallType}"
    lastInstallationConfig="${oldLastInstallationConfig}"
    currentRealityPublicKey="${oldCurrentRealityPublicKey}"
    currentRealityPrivateKey="${oldCurrentRealityPrivateKey}"
    realityPrivateKey="${oldRealityPrivateKey}"
    realityPublicKey="${oldRealityPublicKey}"
)

runRuntimeAndRealityRegression() {
    local oldCurrentClients="${currentClients:-}"
    local xhttpClients
    local realityGrpcClients
    local visionClients

    visionLink=$(serializeVlessRealityVisionLink "uuid-a" "node.example.com" "443" "www.microsoft.com" "pubkey" "pqv" "user-a")
    [[ "${visionLink}" == "vless://uuid-a@node.example.com:443?encryption=none&security=reality&pqv=pqv&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=pubkey&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#user-a" ]]
    visionEncLink=$(serializeVlessRealityVisionLink "uuid-a" "node.example.com" "443" "www.microsoft.com" "pubkey" "pqv" "user-a" "mlkem768x25519plus.native.0rtt.test")
    [[ "${visionEncLink}" == "vless://uuid-a@node.example.com:443?encryption=mlkem768x25519plus.native.0rtt.test&security=reality&pqv=pqv&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=pubkey&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#user-a" ]]
    grpcLink=$(serializeVlessRealityGrpcLink "uuid-a" "node.example.com" "8443" "www.microsoft.com" "pubkey" "pqv" "user-a")
    [[ "${grpcLink}" == "vless://uuid-a@node.example.com:8443?encryption=none&security=reality&pqv=pqv&type=grpc&sni=www.microsoft.com&fp=chrome&pbk=pubkey&sid=6ba85179e30d4fc2&path=grpc&serviceName=grpc#user-a" ]]
    xhttpLink=$(serializeVlessRealityXHTTPLink "uuid-a" "cdn.example.com" "443" "www.microsoft.com" "/xHTTP" "pubkey" "user-a")
    [[ "${xhttpLink}" == "vless://uuid-a@cdn.example.com:443?encryption=none&security=reality&type=xhttp&sni=www.microsoft.com&host=www.microsoft.com&fp=chrome&path=/xHTTP&pbk=pubkey&sid=6ba85179e30d4fc2#user-a" ]]
    xhttpLink=$(serializeVlessRealityXHTTPLink "uuid-a" "cdn.example.com" "443" "www.microsoft.com" "/custom" "pubkey" "user-a" none "front.example.com" "stream-one")
    [[ "${xhttpLink}" == "vless://uuid-a@cdn.example.com:443?encryption=none&security=reality&type=xhttp&sni=www.microsoft.com&host=front.example.com&fp=chrome&path=/custom&mode=stream-one&pbk=pubkey&sid=6ba85179e30d4fc2#user-a" ]]
    currentClients='[{"id":"uuid-a","email":"user-a"}]'
    xhttpClients=$(initXrayClients 2)
    jq -e '.[0].email == "user-a-VLESS_Reality_XHTTP" and (.[0].flow | not)' <<<"${xhttpClients}" >/dev/null
    realityGrpcClients=$(initXrayClients 26)
    jq -e '.[0].email == "user-a-vless_reality_grpc" and (.[0].flow | not)' <<<"${realityGrpcClients}" >/dev/null
    visionClients=$(initXrayClients 27)
    jq -e '.[0].email == "user-a-VLESS_TCP/TLS_Vision" and .[0].flow == "xtls-rprx-vision"' <<<"${visionClients}" >/dev/null
    currentClients="${oldCurrentClients}"
    domain=tls.example.com
    currentHost=
    collectTLSProfile
    [[ "${tlsCertDomain}" == "tls.example.com" ]]
    [[ "${tlsSNI}" == "tls.example.com" ]]
    protocolMeta 1 security | grep -qx reality
    protocolMeta 1 transport | grep -qx tcp
    protocolMeta 1 needs_reality | grep -qx 1
    ! protocolSelectionNeedsCertificate 1
    protocolSelectionNeedsCertificate 3
    protocolMeta 3 needs_udp | grep -qx 1
    protocolCapabilityMeta 1 transport | grep -qx tcp
    protocolCapabilityMeta 1 security | grep -qx reality

    parseInstallArgs --install-type custom --core xray --protocols 1 --domain node.example.com --reality-target www.microsoft.com:443 --reality-server-name www.microsoft.com --entry-host node.example.com --reuse-last no
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

    padmIsValidConnectAddress "example.org"
    padmIsValidConnectAddress "203.0.113.10"
    padmIsValidConnectAddress "2001:db8::1"
    ! padmIsValidConnectAddress "bad host"
    ! padmIsValidConnectAddress $'bad\nhost'
    ! padmIsValidConnectAddress "2001:::1"

    AUTO_REALITY_SERVER_NAME=
    parseRealityTargetInput "example.com"
    [[ "${realityTargetHost}" == "example.com" ]]
    [[ "${realityTargetPort}" == "443" ]]
    parseRealityTargetInput "example.org:8443"
    [[ "${realityTargetHost}" == "example.org" ]]
    [[ "${realityTargetPort}" == "8443" ]]
    ! parseRealityTargetInput $'bad","extra":"x:443'
    ! parseRealityTargetInput "bad host:443"
    AUTO_REALITY_SERVER_NAME=$'bad"\nname'
    ! parseRealityTargetInput "example.net:443"
    AUTO_REALITY_SERVER_NAME=www.example.net
    parseRealityTargetInput "example.net:443"
    [[ "${realitySNI}" == "www.example.net" ]]
    AUTO_ENTRY_HOST=$'bad\nentry'
    ! collectEntryProfile
    AUTO_ENTRY_HOST=entry.example.com
    collectEntryProfile
    [[ "${realityEntryHost}" == "entry.example.com" ]]
    AUTO_ENTRY_HOST=
    AUTO_REALITY_SERVER_NAME=
    parseRealityTargetInput "example.org:8443"
    ! parseRealityTargetInput "bad.example.org:70000"
    [[ "${realityTargetHost}" == "example.org" ]]
    [[ "${realityTargetPort}" == "8443" ]]
    [[ "${realitySNI}" == "example.org" ]]
    scoreLine=$(scoreRealityTargetFromTlsPing $'Pinging with SNI\nTLS Post-Quantum key exchange: X25519MLKEM768\nTLS version: TLS 1.3\nCertificate chain total length: 4096')
    [[ "$(printf '%s\n' "${scoreLine}" | awk -F'\t' '{print $1}')" == "A" ]]
    showRealityTargetQuality "www.microsoft.com:443"
    [[ "$(realityTargetResultCount)" -ge "1" ]]
    cachedLine=$(awk -F'\t' '$1 == "www.microsoft.com:443" {print; found=1; exit} END {exit found ? 0 : 1}' "${PADM_REALITY_TARGET_RESULTS_FILE}")
    [[ "$(printf '%s\n' "${cachedLine}" | awk -F'\t' '{print $10}')" == "A" ]]
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

    uiStyle() { printf '%s' "$2"; }
    menuLine() { output+="$*"$'\n'; }
    menuMutedLine() { output+="$*"$'\n'; }
    menuSection() { :; }
    menuItem() { output+="$2 $3"$'\n'; }
    menuRecommendedItem() { output+="$2 $3"$'\n'; }
    menuDangerItem() { output+="$2 $3"$'\n'; }
    menuReturnItem() { output+="$2 $3"$'\n'; }
    statusCard() { recordMenuAction "statusCard:$1"; }
    successCard() { recordMenuAction "successCard:$1"; }
    runSubscriptionGroupSync() { recordMenuAction "runSubscriptionGroupSync:$*"; }
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

    if [[ "${isReleaseCommit}" == "true" ]]; then
        releaseVersion="${currentVersion}"
        needsBump=false
    else
        releaseVersion="v$(nextScriptVersionFromCommits "${latestTag}" "${commits}")"
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
}

runRealityConfigScannerRegression() {
    local scannerCandidatesFile="${TMP_DIR}/reality-config-scanner-candidates.txt"
    local oldCandidatesFile="${PADM_REALITY_TARGET_CANDIDATES_FILE:-}"
    local scannerLine batchLinesFile failedTargetsFile scannerSummary
    local scannerImported scannerSkipped scannerA scannerB scannerC scannerFail
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
    importRealityScannerResults "${TMP_DIR}/realitlscanner.csv" "AS64500" "ExampleNet" scannerSummary
    IFS=$'\t' read -r scannerImported scannerSkipped scannerA scannerB scannerC scannerFail <<<"${scannerSummary}"
    [[ "${scannerImported}" == "1" ]]
    [[ "${scannerSkipped}" == "7" ]]
    [[ "${scannerA}" == "1" ]]
    [[ "${scannerB}" == "0" ]]
    [[ "${scannerC}" == "0" ]]
    [[ "${scannerFail}" == "0" ]]
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
    printf '%s\n' "batch-old.example.com|batch-old.example.com|Batch Old|global|large_site|unknown|9|yes|batch candidate" >>"${scannerCandidatesFile}"
    removeRealityTargetsFromUnifiedLibrary "${failedTargetsFile}"
    ! grep -qF $'batch-old.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}"
    ! grep -qF 'batch-old.example.com|' "${scannerCandidatesFile}"

    rm -f "${PADM_REALITY_TARGET_SCAN_FILE}" "${REALITY_TLS_PING_ARGS_FILE}"
    realityTargetCandidateBlocked "images.apple.com"
    unset AUTO_REALITY_SERVER_NAME
    writeRealityTargetResultLine "local.example.com:443" "sni.local.example.com" "Local Example" "test" "no" "192.0.2.1" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "same ASN test target"
    writeRealityTargetResultLine "remote.example.com:443" "sni.remote.example.com" "Remote Example" "test" "no" "198.51.100.1" "AS64501" "RemoteNet" "different_network" "A" "yes" "8192" "yes" "1234567899" "longer cert but different network"
    [[ "$(realityTargetResultCount)" == "2" ]]
    scanLine=$(grep -F $'local.example.com:443\t' "${PADM_REALITY_TARGET_SCAN_FILE}")
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

runRealityUnifiedLibraryRollbackRegression() (
    local rootRel="${TMP_DIR}/reality-unified-library-rollback"
    local root resultsFile candidatesFile targetsFile
    local oldResultsFile="${PADM_REALITY_TARGET_RESULTS_FILE:-}"
    local oldScanFile="${PADM_REALITY_TARGET_SCAN_FILE:-}"
    local oldCandidatesFile="${PADM_REALITY_TARGET_CANDIDATES_FILE:-}"
    local rc

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    resultsFile="${root}/reality_targets_results.tsv"
    candidatesFile="${root}/reality_candidates.tsv"
    targetsFile="${root}/remove-targets.txt"
    export PADM_REALITY_TARGET_RESULTS_FILE="${resultsFile}"
    export PADM_REALITY_TARGET_SCAN_FILE="${resultsFile}"
    export PADM_REALITY_TARGET_CANDIDATES_FILE="${candidatesFile}"

    {
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "remove.example.com:443" "remove.example.com" "Remove Example" "scanner" "unknown" "192.0.2.10" "AS64500" "ExampleNet" "same_asn" "A" "yes" "4096" "yes" "1234567890" "remove line"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "keep.example.com:443" "keep.example.com" "Keep Example" "scanner" "unknown" "192.0.2.11" "AS64500" "ExampleNet" "same_asn" "B" "yes" "4096" "yes" "1234567891" "keep line"
    } >"${resultsFile}"
    {
        printf '%s\n' 'remove.example.com|remove.example.com|Remove Example|global|scanner|unknown|9|yes|remove candidate'
        printf '%s\n' 'keep.example.com|keep.example.com|Keep Example|global|scanner|unknown|10|yes|keep candidate'
    } >"${candidatesFile}"
    printf '%s\n' 'remove.example.com:443' >"${targetsFile}"

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${candidatesFile}" ]]; then
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    set +e
    removeRealityTargetsFromUnifiedLibrary "${targetsFile}" >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qF $'remove.example.com:443\t' "${resultsFile}"
    grep -qF $'keep.example.com:443\t' "${resultsFile}"
    grep -q '^remove.example.com|' "${candidatesFile}"
    grep -q '^keep.example.com|' "${candidatesFile}"
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
    applyLog=$(realityTargetTmpPath padm-reality-target-apply.log)
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
        if [[ "$1" == "-p" && "$2" == */xray/07_VLESS_vision_reality_inbounds.json && "$3" == "${root}/.xray-vision.json.restore."* ]]; then
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
        if [[ "$1" == "-p" && "$2" == */xray/07_VLESS_vision_reality_inbounds.json && "$3" == "${root}/.xray-vision.json.restore."* ]]; then
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
    runRegressionStep reality-config-blocked-transaction runRealityBlockedCandidateTransactionRegression
    runRegressionStep reality-config-unified-library-rollback runRealityUnifiedLibraryRollbackRegression
    runRegressionStep reality-config-apply runRealityConfigApplyRegression
    runRegressionStep reality-config-change-reload-failure runRealityConfigChangeReloadFailureRegression
    runRegressionStep reality-config-change-subscription-refresh-failure runRealityConfigChangeSubscriptionRefreshFailureRegression
    runRegressionStep reality-config-xhttp-download-settings runXHTTPDownloadSettingsRegression
    runRegressionStep reality-config-refresh-subscription runRealityConfigRefreshSubscriptionRegression
    runRegressionStep reality-config-import-skip runRealityConfigImportSkipRegression
}

runSubscriptionOutputProfileAndRealityRegression() {
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
assertCapturedSubscribeOutputs "user-a-main" "${expectedVisionLink}" "node.example.com" "www.microsoft.com" "tcp" "vless"
jq -e '.[0].flow == "xtls-rprx-vision" and .[0].tls.reality.public_key == "pubkey"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/user-a-main" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
defaultBase64Code vlessRealityGRPC 8443 user-a-grpc uuid-a "" ""
expectedGrpcLink=$(serializeVlessRealityGrpcLink "uuid-a" "node.example.com" "8443" "www.microsoft.com" "pubkey" "pqv" "user-a-grpc")
assertCapturedSubscribeOutputs "user-a-grpc" "${expectedGrpcLink}" "node.example.com" "www.microsoft.com" "grpc" "vless"
jq -e '.[0].transport.service_name == "grpc" and .[0].tls.reality.short_id == "6ba85179e30d4fc2"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/user-a-grpc" >/dev/null
grep -q 'pqv=pqv' "${SUBSCRIBE_CAPTURE_DIR}/screen.log"

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
grep -qxF "${expectedXHTTPLink}" "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp"
! grep -q 'flow=xtls-rprx-vision' "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp"
grep -qx "    server: cdn.example.com" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp"
grep -qx "    servername: www.microsoft.com" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp"
grep -qx "      path: /custom-xhttp" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp"
grep -qx "      host: front.example.com" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp"
grep -qx "      mode: packet-up" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp"
! grep -q 'flow: xtls-rprx-vision' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp"
! grep -q '&flow=xtls-rprx-vision' "${SUBSCRIBE_CAPTURE_DIR}/screen.log"
configPath="${oldConfigPath}"
}

runSubscriptionOutputPublishAccountsAndRemoteHintRegression() {
(
    local publishRoot="${TMP_DIR}/subscription-output-publish-accounts"
    local localBase="${publishRoot}/local"
    local mainCheckFile="${publishRoot}/main-check-count"
    local output
    mkdir -p "${localBase}/default"
    : >"${localBase}/default/local-keep"
    printf '0\n' >"${mainCheckFile}"

    subscriptionGroupsStateRead() {
        if [[ "$*" == "-r .active_group" ]]; then
            printf 'default\n'
            return 0
        fi
        if [[ "$*" == *'any(.sources[]?; .id == "main" and ((.enabled // true) == true))'* ]]; then
            printf '%s\n' "$(( $(<"${mainCheckFile}") + 1 ))" >"${mainCheckFile}"
            return 0
        fi
        return 1
    }
    subscriptionActiveGroupRead() {
        if [[ "$*" == *'any(.sources[]?; .id == "main" and ((.enabled // true) == true))'* ]]; then
            printf '%s\n' "$(( $(<"${mainCheckFile}") + 1 ))" >"${mainCheckFile}"
            return 0
        fi
        if [[ "$*" == *'--argjson enabledUsers '* && "$*" == *'.allows_main // false'* && "$*" == *'.has_remote // false'* && "$*" == *'@tsv'* ]]; then
            printf 'sub_team_a\ttrue\tfalse\nsub_team_b\ttrue\tfalse\n'
            return 0
        fi
        return 1
    }
    subscriptionActiveEnabledUsersJson() {
        printf '[{"id":"team-a","account":"sub_team_a","allowed_sources":["main"],"allows_main":true,"has_remote":false},{"id":"team-b","account":"sub_team_b","allowed_sources":["main"],"allows_main":true,"has_remote":false}]\n'
    }
    subscriptionSyncFindUserByAccountName() {
        return 99
    }

    output=$(subscriptionPublishAccounts "${localBase}")
    [[ "${output}" == $'local-keep\nsub_team_a\nsub_team_b' ]]
    [[ "$(<"${mainCheckFile}")" == "1" ]]
)

(
    local sourceLines
    local helperAccountFile="${TMP_DIR}/subscription-output-remote-hint-account.log"
    subscriptionSyncFindUserByAccountName() {
        printf '%s\n' "$1" >"${helperAccountFile}"
        printf '{"id":"team-a","account":"sub_team_a","allowed_sources":["edge"]}\n'
    }
    subscriptionActiveGroupRead() {
        if [[ "$*" == *'--argjson allowed ["edge"]'* && "$*" == *'.id as $sid | $allowed | index($sid)'* ]]; then
            printf 'example.com:443:edge:https\n'
            return 0
        fi
        return 1
    }
    sourceLines=$(subscriptionRemoteSubscribeSourcesForAccount sub_team_a)
    [[ "${sourceLines}" == "example.com:443:edge:https" ]]
    grep -qx 'sub_team_a' "${helperAccountFile}"

    subscriptionActiveGroupRead() {
        return 0
    }
    sourceLines=unexpected
    subscriptionRemoteSubscribeSourcesForAccount sub_team_a sourceLines
    [[ -z "${sourceLines}" ]]
)

(
    local renderRoot="${TMP_DIR}/subscription-render-remote-hint-batch"
    local localBase="${renderRoot}/local"
    local remoteChecksFile="${renderRoot}/remote-checks.log"
    local autoReadCalls=0
    local oldSubscribeSalt="${subscribeSalt:-}"
    local oldCurrentDefaultPort="${currentDefaultPort:-}"
    mkdir -p "${localBase}/default" "${renderRoot}"
    : >"${remoteChecksFile}"
    subscribeSalt=test-salt
    currentDefaultPort=443

    subscriptionActiveGroupRead() {
        if [[ "$*" == *'any(.sources[]?; .id == "main" and ((.enabled // true) == true))'* ]]; then
            return 1
        fi
        if [[ "$*" == *'--argjson enabledUsers '* && "$*" == *'.has_remote // false'* && "$*" == *'@tsv'* ]]; then
            printf 'sub_team_a\tfalse\ttrue\n'
            return 0
        fi
        return 1
    }
    subscriptionActiveEnabledUsersJson() {
        printf '[{"id":"team-a","account":"sub_team_a","allowed_sources":["edge"],"allows_main":false,"has_remote":true}]\n'
    }
    subscriptionPublishHasRemoteSources() {
        return 99
    }
    subscriptionRemoteSubscribeSourcesForAccount() {
        printf '%s\n' "$1" >>"${remoteChecksFile}"
        printf 'example.com:443:edge:https\n'
    }
    autoRead() {
        autoReadCalls=$((autoReadCalls + 1))
        printf -v "$3" 'y'
    }
    resolveSubscribePublicDomain() {
        printf 'example.com'
    }
    renderSubscribeUserOutputs() {
        [[ "$1" == "sub_team_a" && "$4" == "y" ]]
    }

    renderAllSubscribeUserOutputs "${localBase}" "" true "" true
    [[ "${autoReadCalls}" == "1" ]]
    [[ ! -s "${remoteChecksFile}" ]]

    if [[ -n "${oldSubscribeSalt}" ]]; then
        subscribeSalt="${oldSubscribeSalt}"
    else
        unset subscribeSalt
    fi
    if [[ -n "${oldCurrentDefaultPort}" ]]; then
        currentDefaultPort="${oldCurrentDefaultPort}"
    else
        unset currentDefaultPort
    fi
)

(
    local renderRoot="${TMP_DIR}/subscription-render-remote-hint-override"
    local localBase="${renderRoot}/local"
    local helperAccountsFile="${renderRoot}/helper-accounts.log"
    local unexpectedRemoteChecksFile="${renderRoot}/unexpected-remote-checks.log"
    local autoReadCalls=0
    local oldSubscribeSalt="${subscribeSalt:-}"
    local oldCurrentDefaultPort="${currentDefaultPort:-}"
    mkdir -p "${localBase}/default" "${renderRoot}"
    : >"${helperAccountsFile}"
    : >"${unexpectedRemoteChecksFile}"
    subscribeSalt=test-salt
    currentDefaultPort=443

    subscriptionPublishHasRemoteSources() {
        printf '%s\n' "$1" >"${helperAccountsFile}"
        return 0
    }
    subscriptionRemoteSubscribeSourcesForAccount() {
        printf '%s\n' "$1" >>"${unexpectedRemoteChecksFile}"
        printf 'example.com:443:edge:https\n'
    }
    autoRead() {
        autoReadCalls=$((autoReadCalls + 1))
        printf -v "$3" 'y'
    }
    resolveSubscribePublicDomain() {
        printf 'example.com'
    }
    renderSubscribeUserOutputs() {
        [[ "$1" == "sub_team_a" && "$4" == "y" ]]
    }

    renderAllSubscribeUserOutputs "${localBase}" "" true "sub_team_a" true
    [[ "${autoReadCalls}" == "1" ]]
    grep -qx 'sub_team_a' "${helperAccountsFile}"
    [[ ! -s "${unexpectedRemoteChecksFile}" ]]

    if [[ -n "${oldSubscribeSalt}" ]]; then
        subscribeSalt="${oldSubscribeSalt}"
    else
        unset subscribeSalt
    fi
    if [[ -n "${oldCurrentDefaultPort}" ]]; then
        currentDefaultPort="${oldCurrentDefaultPort}"
    else
        unset currentDefaultPort
    fi
)
}

runSubscriptionOutputTlsVlessVmessTrojanRegression() {
local quotedTlsUser='tls-"quoted-user'
rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
! defaultBase64Code vlesstcp 443 "${quotedTlsUser}" uuid-quoted "" "" >/dev/null 2>&1
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/sing-box/${quotedTlsUser}" ]]

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code vlesstcp 443 tls-user uuid-tls "" ""
assertCapturedSubscribeOutputs "tls-user" "vless://uuid-tls@tls.example.com:443?encryption=none&security=tls&type=tcp&host=tls.example.com&fp=chrome&headerType=none&sni=tls.example.com&flow=xtls-rprx-vision#tls-user" "tls.example.com" "tls.example.com" "tcp" "vless"
jq -e '.[0].flow == "xtls-rprx-vision" and (.[0].tls.reality | not)' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code vlessws 443 tls-ws-user uuid-ws "edge.example.com" "/ws-path"
assertCapturedSubscribeOutputs "tls-ws-user" "vless://uuid-ws@edge.example.com:443?encryption=none&security=tls&type=ws&host=tls.example.com&sni=tls.example.com&fp=chrome&path=/ws-path#tls-ws-user" "edge.example.com" "tls.example.com" "ws" "vless"
jq -e '.[0].transport.path == "/ws-path" and .[0].transport.headers.Host == "tls.example.com" and .[0].multiplex.enabled == false' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-ws-user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
currentPath="svc-"
defaultBase64Code vlessgrpc 443 tls-grpc-user uuid-grpc "edge.example.com" ""
assertCapturedSubscribeOutputs "tls-grpc-user" "vless://uuid-grpc@edge.example.com:443?encryption=none&security=tls&type=grpc&host=tls.example.com&path=svc-grpc&serviceName=svc-grpc&fp=chrome&alpn=h2&sni=tls.example.com#tls-grpc-user" "edge.example.com" "tls.example.com" "grpc" "vless"
jq -e '.[0].transport.service_name == "svc-grpc" and .[0].packet_encoding == "xudp"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-grpc-user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code vmessws 443 tls-vmess-user uuid-vmess "edge.example.com" "/vmess-ws"
vmessWsLink=$(sed -n '1p' "${SUBSCRIBE_CAPTURE_DIR}/default/tls-vmess-user")
[[ "${vmessWsLink}" == vmess://* ]]
assertCapturedSubscribeOutputs "tls-vmess-user" "${vmessWsLink}" "edge.example.com" "tls.example.com" "ws" "vmess"
jq -e '.[0].alter_id == 0 and .[0].transport.max_early_data == 2048 and .[0].packet_encoding == "packetaddr"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-vmess-user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code trojan 443 tls-trojan-user pass-trojan "" ""
assertCapturedSubscribeOutputs "tls-trojan-user" "trojan://pass-trojan@tls.example.com:443?peer=tls.example.com&fp=chrome&sni=tls.example.com&alpn=http/1.1#tls-trojan-user_Trojan" "tls.example.com" "tls.example.com" "tcp" "trojan"
jq -e '.[0].password == "pass-trojan" and .[0].tls.alpn[0] == "http/1.1"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-trojan-user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
currentPath="svc-"
defaultBase64Code trojangrpc 443 tls-trojan-grpc-user pass-trojan-grpc "edge.example.com" ""
assertCapturedSubscribeOutputs "tls-trojan-grpc-user" "trojan://pass-trojan-grpc@edge.example.com:443?encryption=none&peer=tls.example.com&security=tls&type=grpc&fp=chrome&sni=tls.example.com&alpn=h2&path=svc-trojangrpc&serviceName=svc-trojangrpc#tls-trojan-grpc-user" "edge.example.com" "tls.example.com" "grpc" "trojan"
jq -e '.[0].transport.service_name == "svc-trojangrpc" and (.[0].tls | has("insecure") | not) and .[0].multiplex.enabled == false' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-trojan-grpc-user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code vmessHTTPUpgrade 443 tls-httpupgrade-user uuid-http "edge.example.com" "/upgrade"
httpUpgradeLink=$(sed -n '1p' "${SUBSCRIBE_CAPTURE_DIR}/default/tls-httpupgrade-user")
[[ "${httpUpgradeLink}" == vmess://* ]]
[[ "${httpUpgradeLink}" != " "* ]]
assertCapturedSubscribeOutputs "tls-httpupgrade-user" "${httpUpgradeLink}" "edge.example.com" "tls.example.com" "httpupgrade" "vmess"
jq -e '.[0].security == "auto" and .[0].transport.path == "/upgrade" and .[0].packet_encoding == "packetaddr"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-httpupgrade-user" >/dev/null
}

runSubscriptionOutputTlsAnyHysteriaTuicNaiveRegression() {
rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
export REGRESSION_ECHO_LOG="${SUBSCRIBE_CAPTURE_DIR}/screen.log"
currentHost="tls.example.com"
singBoxAnyTLSPort=8443
defaultBase64Code anytls 443 tls-any-user pass-any "" ""
assertCapturedSubscribeOutputs "tls-any-user" "anytls://pass-any@tls.example.com:8443?peer=tls.example.com&insecure=0&sni=tls.example.com#tls-any-user" "tls.example.com" "tls.example.com" "tcp" "anytls"
jq -e '.[0].password == "pass-any" and .[0].server_port == 8443' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-any-user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
singBoxHysteria2Port=9443
hysteria2ClientUploadSpeed=100
hysteria2ClientDownloadSpeed=200
defaultBase64Code hysteria 8443 tls-hysteria-user pass-hysteria "" ""
assertCapturedSubscribeOutputs "tls-hysteria-user" "hysteria2://pass-hysteria@tls.example.com:9443?peer=tls.example.com&insecure=0&sni=tls.example.com&alpn=h3#tls-hysteria-user" "tls.example.com" "tls.example.com" "tcp" "hysteria2"
jq -e '.[0].password == "pass-hysteria" and .[0].up_mbps == 100 and .[0].down_mbps == 200 and .[0].tls.alpn[0] == "h3"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-hysteria-user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
singBoxHysteria2Port=9443
hysteria2ClientUploadSpeed=100
hysteria2ClientDownloadSpeed=200
defaultBase64Code hysteria "20000-20002" tls-hysteria-hop-user pass-hysteria-hop "" ""
grep -qxF "hysteria2://pass-hysteria-hop@tls.example.com:20000-20002?peer=tls.example.com&insecure=0&sni=tls.example.com&alpn=h3#tls-hysteria-hop-user" "${SUBSCRIBE_CAPTURE_DIR}/default/tls-hysteria-hop-user"
grep -qx "    ports: 20000-20002" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-hysteria-hop-user"
[[ -f "${SUBSCRIBE_CAPTURE_DIR}/screen.log" ]] || return 1
if grep -q 'mport' "${SUBSCRIBE_CAPTURE_DIR}/default/tls-hysteria-hop-user" "${SUBSCRIBE_CAPTURE_DIR}/screen.log"; then
    return 1
fi

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
tuicAlgorithm="bbr"
defaultBase64Code tuic 9443 tls-tuic-user uuid-tuic_pass-tuic "" ""
grep -qxF "tuic://uuid-tuic:pass-tuic@tls.example.com:9443?congestion_control=bbr&alpn=h3&sni=tls.example.com&udp_relay_mode=native&allow_insecure=0#tls-tuic-user" "${SUBSCRIBE_CAPTURE_DIR}/default/tls-tuic-user"
grep -qx "    server: tls.example.com" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-tuic-user"
grep -qx "    udp-relay-mode: native" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-tuic-user"
grep -qx "    disable-sni: false" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-tuic-user"
grep -qx "    reduce-rtt: false" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-tuic-user"
grep -qx "    sni: tls.example.com" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-tuic-user"
jq -e '.[0].type == "tuic" and .[0].server == "tls.example.com" and .[0].tls.server_name == "tls.example.com"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-tuic-user" >/dev/null
jq -e '.[0].uuid == "uuid-tuic" and .[0].password == "pass-tuic" and .[0].congestion_control == "bbr" and .[0].udp_relay_mode == "native" and .[0].zero_rtt_handshake == false and .[0].tls.alpn[0] == "h3"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-tuic-user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code naive 443 tls-naive-user pass-naive "" ""
grep -qxF "naive+https://tls-naive-user:pass-naive@tls.example.com:443?padding=true#tls-naive-user" "${SUBSCRIBE_CAPTURE_DIR}/default/tls-naive-user"
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-naive-user" ]]
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-naive-user" ]]
unset REGRESSION_ECHO_LOG
}

runSubscriptionOutputRegression() {
    runSubscriptionOutputProfileAndRealityRegression
    runSubscriptionOutputPublishAccountsAndRemoteHintRegression
    runSubscriptionOutputTlsVlessVmessTrojanRegression
    runSubscriptionOutputTlsAnyHysteriaTuicNaiveRegression
}

runRemoteSubscribeSourcesAvoidReverseDecodeRegression() (
    local sourceLines
    local helperAccountFile="${TMP_DIR}/subscription-remote-sources-account.log"

    subscriptionSyncAccountIdFromName() {
        return 97
    }
    subscriptionSyncFindUserByAccountName() {
        printf '%s\n' "$1" >"${helperAccountFile}"
        printf '{"id":"team-a","account":"sub_team_a","allowed_sources":["edge"]}\n'
    }
    subscriptionActiveEnabledUsersJson() {
        return 98
    }
    subscriptionActiveGroupRead() {
        if [[ "$*" == *'--argjson allowed ["edge"]'* && "$*" == *'.id as $sid | $allowed | index($sid)'* ]]; then
            printf 'example.com:443:edge:https\n'
            return 0
        fi
        return 1
    }

    sourceLines=$(subscriptionRemoteSubscribeSourcesForAccount sub_team_a)
    [[ "${sourceLines}" == "example.com:443:edge:https" ]]
    grep -qx 'sub_team_a' "${helperAccountFile}"
)

runSubscriptionSyncAccountFastPathRegression() (
    local root="${TMP_DIR}/subscription-sync-account-fast-path"
    local stateReadCalls=0

    mkdir -p "${root}"
    PADM_SUBSCRIPTION_GROUPS_DIR="${root}/groups"
    ensureSubscriptionGroupsState

    eval "$(declare -f subscriptionGroupsStateRead | sed '1s/^subscriptionGroupsStateRead/originalSubscriptionGroupsStateRead/')"
    subscriptionGroupsStateRead() {
        stateReadCalls=$((stateReadCalls + 1))
        originalSubscriptionGroupsStateRead "$@"
    }

    [[ "$(subscriptionSyncAccountIdFromName 'sub_team-a')" == "team-a" ]]
    [[ "${stateReadCalls}" == "0" ]]

    unset -f subscriptionGroupsStateRead
)

runSubscriptionSyncAppendLocalUserBatchRegression() (
    local root="${TMP_DIR}/subscription-sync-append-local-user-batch"
    local callLog="${root}/calls.log"
    local oldConfigPath="${configPath:-}"
    local oldSingBoxConfigPath="${singBoxConfigPath:-}"

    mkdir -p "${root}" "${root}/xray" "${root}/sing-box" "${root}/groups"
    configPath="${root}/xray/"
    singBoxConfigPath="${root}/sing-box/"
    export PADM_SUBSCRIPTION_GROUPS_DIR="${root}/groups"
    ensureSubscriptionGroupsState
    subscriptionGroupsStateWrite '.groups[0].user_groups += [{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"11111111-1111-1111-1111-111111111111"}]'

    subscriptionSyncAppendProtocolBatch() {
        printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"${callLog}"
        return 0
    }

    subscriptionSyncAppendLocalUser team-a

    [[ -f "${callLog}" ]] || return 1
    [[ "$(wc -l <"${callLog}" | tr -d ' ')" == "2" ]] || return 1
    grep -qx "${root}/xray/	11111111-1111-1111-1111-111111111111	sub_team_a	xray" "${callLog}" || return 1
    grep -qx "${root}/sing-box/	11111111-1111-1111-1111-111111111111	sub_team_a	singbox" "${callLog}" || return 1

    configPath="${oldConfigPath}"
    singBoxConfigPath="${oldSingBoxConfigPath}"
)

runRemoteSubscribeFetchRegression() {
    local remoteFetchPart="${1:-all}"
    local publicDir="${TMP_DIR}/remote-subscribe-public"
    local localDir="${TMP_DIR}/remote-subscribe-local"
    local email="sub_team"
    local emailMd5="hash-team"
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
    mkdir -p "$(dirname "$(subscriptionGroupsFile)")"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"r1","name":"Remote 1","role":"secondary","scheme":"https","transport":"https","host":"remote1.example","port":443,"enabled":true,"sync_status":"success"},{"id":"r2","name":"Remote 2","role":"secondary","scheme":"https","transport":"https","host":"remote2.example","port":443,"enabled":true,"sync_status":"success"},{"id":"r3","name":"Remote 3","role":"secondary","scheme":"https","transport":"https","host":"remote3.example","port":443,"enabled":true,"sync_status":"success"}],"user_groups":[{"id":"team","name":"Team","enabled":true,"allowed_sources":["r1","r2","r3"],"traffic_limit_gb":0,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    : >"${fetchTmpMarker}"
    : >"${stageTmpMarker}"

    remoteSubscribeFetchPartSelected() {
        [[ "${remoteFetchPart}" == "all" || "${remoteFetchPart}" == "$1" ]]
    }

    writeRemoteSubscribeOldOutputs() {
        printf 'old-default\n' >"${publicDir}/default/${emailMd5}"
        printf 'old-clash\n' >"${publicDir}/clashMeta/${emailMd5}"
        printf '[{"tag":"old-local"}]\n' >"${localDir}/sing-box/${email}"
    }

    eval "$(declare -f appendUniqueLines | sed '1s/^appendUniqueLines/originalAppendUniqueLines/')"
    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"

    if remoteSubscribeFetchPartSelected unique; then
        (
        local curlArgsLog="${TMP_DIR}/remote-subscribe-curl-args.log"
        curl() {
            printf '%s\n' "$*" >"${curlArgsLog}"
            return 23
        }
        if fetchRemoteSubscribeContent "https://remote.example/s/default/${emailMd5}" >/dev/null 2>&1; then
            return 1
        fi
        grep -q -- '--max-filesize 1048576' "${curlArgsLog}"
        )
        printf '%s\n' old same >"${uniqueFile}"
        appendUniqueLines $'same\nnew\nnew' "${uniqueFile}"
        cmp -s "${uniqueFile}" <(printf '%s\n' old same new)
    fi

    recordRemoteSubscribeTmpDirs() {
        find "${remoteTmpRoot}" -maxdepth 1 -type d -name 'padm-remote-subscribe-fetch.*' -print >>"${fetchTmpMarker}" 2>/dev/null || true
        find "${remoteTmpRoot}" -maxdepth 1 -type d -name 'padm-remote-subscribe-stage.*' -print >>"${stageTmpMarker}" 2>/dev/null || true
    }

    fetchRemoteSubscribeContent() {
        local url=$1
        recordRemoteSubscribeTmpDirs
        case "${url}" in
        *remote1.example*/s/clashMeta/*)
            printf '%s\n' 'proxies:' '- name: "sub_team"'
            ;;
        *remote1.example*/s/default/*)
            printf '%s' 'vless://uuid@remote1.example:443#sub_team' | base64
            ;;
        *remote1.example*/s/sing-box_profiles/*)
            printf '%s\n' '[{"tag":"sub_team"}]'
            ;;
        *remote2.example*/s/clashMeta/*)
            [[ "${PADM_FAKE_REMOTE_SUBSCRIBE_MODE:-partial}" != "fetch-failure" ]]
            ;;
        *remote2.example*/s/default/*)
            printf '%s' 'vless://bad@remote2.example:443#sub_team' | base64
            printf '@@'
            ;;
        *remote2.example*/s/sing-box_profiles/*)
            if [[ "${PADM_FAKE_REMOTE_SUBSCRIBE_MODE:-partial}" == "fail-singbox-merge" ]]; then
                printf '%s\n' '[{"tag":"sub_team_r2"}]'
            else
                printf '%s\n' '{bad json'
            fi
            ;;
        *remote3.example*/s/clashMeta/*)
            printf '%s\n' 'proxies:' '- name: "sub_team"'
            ;;
        *remote3.example*/s/default/*)
            printf '%s' 'trojan://pass@remote3.example:443#sub_team-extra' | base64
            ;;
        *remote3.example*/s/sing-box_profiles/*)
            printf '%s\n' '[{"tag":"sub_team-extra"}]'
            ;;
        *)
            return 1
            ;;
        esac
    }
    fetchRemoteControlledSubscribePayload() {
        return 97
    }

    if remoteSubscribeFetchPartSelected rollback; then
        writeRemoteSubscribeOldOutputs
        export PADM_FAKE_REMOTE_SUBSCRIBE_MODE=fetch-failure
        if updateRemoteSubscribe "${emailMd5}" "${email}" 2>/dev/null; then
            return 1
        fi
        [[ "$(<"${publicDir}/default/${emailMd5}")" == "old-default" ]]
        [[ "$(<"${publicDir}/clashMeta/${emailMd5}")" == "old-clash" ]]
        jq -e '.[0].tag == "old-local"' "${localDir}/sing-box/${email}" >/dev/null

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
        if regressionFindHasMatches "${remoteTmpRoot}" -mindepth 1 -maxdepth 1 -type d; then
            return 1
        fi
    fi

    if remoteSubscribeFetchPartSelected merge; then
        writeRemoteSubscribeOldOutputs
        unset PADM_FAKE_REMOTE_SUBSCRIBE_MODE
        updateRemoteSubscribe "${emailMd5}" "${email}"
        grep -qxF -- '- name: "sub_team_r1"' "${publicDir}/clashMeta/${emailMd5}"
        grep -qxF 'vless://uuid@remote1.example:443#sub_team_r1' "${publicDir}/default/${emailMd5}"
        if grep -qxF 'vless://bad@remote2.example:443#sub_team_r2' "${publicDir}/default/${emailMd5}"; then
            return 1
        fi
        grep -qxF 'trojan://pass@remote3.example:443#sub_team_r3-extra' "${publicDir}/default/${emailMd5}"
        jq -e '.[0].tag == "old-local" and .[1].tag == "sub_team_r1" and .[2].tag == "sub_team_r3-extra"' "${localDir}/sing-box/${email}" >/dev/null
        [[ ! -e "${publicDir}/default/${emailMd5}.tmp" ]]
        [[ ! -e "${publicDir}/clashMeta/${emailMd5}.tmp" ]]
        [[ ! -e "${localDir}/sing-box/${email}.tmp" ]]
    fi

    if remoteSubscribeFetchPartSelected disabled-source; then
        local disabledStateBackup="${TMP_DIR}/remote-subscribe-disabled-state.backup.json"
        writeRemoteSubscribeOldOutputs
        cp "$(subscriptionGroupsFile)" "${disabledStateBackup}"
        jq '
          .groups[0].user_groups = [] |
          .groups[0].sources |= map(if .id == "r2" or .id == "r3" then .enabled = false else . end)
        ' "$(subscriptionGroupsFile)" >"${TMP_DIR}/remote-subscribe-disabled-state.json"
        mv "${TMP_DIR}/remote-subscribe-disabled-state.json" "$(subscriptionGroupsFile)"
        updateRemoteSubscribe "${emailMd5}" "${email}"
        grep -qxF 'vless://uuid@remote1.example:443#sub_team_r1' "${publicDir}/default/${emailMd5}"
        if grep -q 'remote3.example' "${publicDir}/default/${emailMd5}"; then
            return 1
        fi
        jq -e 'length == 2 and .[0].tag == "old-local" and .[1].tag == "sub_team_r1"' "${localDir}/sing-box/${email}" >/dev/null
        cp "${disabledStateBackup}" "$(subscriptionGroupsFile)"
    fi

    if remoteSubscribeFetchPartSelected controlled; then
        (
        local controlledRoot="${TMP_DIR}/remote-controlled-fetch"
        local controlledState="${controlledRoot}/state"
        local controlledPublic="${controlledRoot}/public"
        local controlledLocal="${controlledRoot}/local"
        local controlledEmail="sub_team"
        local controlledEmailMd5="hash-team"
        local controlledRequestLog="${controlledRoot}/request.log"
        local oldSubscribeLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
        local oldSubscribeDir="${PADM_SUBSCRIBE_DIR:-}"
        local oldGroupsDir="${PADM_SUBSCRIPTION_GROUPS_DIR:-}"
        mkdir -p "${controlledState}" "${controlledPublic}/default" "${controlledPublic}/clashMeta" "${controlledLocal}/sing-box"
        export PADM_SUBSCRIPTION_GROUPS_DIR="${controlledState}"
        export PADM_SUBSCRIBE_LOCAL_DIR="${controlledLocal}"
        export PADM_SUBSCRIBE_DIR="${controlledPublic}"
        cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge-wg","name":"Edge WG","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"wg.example.com","port":443,"enabled":true,"sync_status":"success","control_token":"token-edge"}],"user_groups":[{"id":"team","name":"Team","enabled":true,"allowed_sources":["edge-wg"],"traffic_limit_gb":0,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
        printf 'old-default\n' >"${controlledPublic}/default/${controlledEmailMd5}"
        printf 'old-clash\n' >"${controlledPublic}/clashMeta/${controlledEmailMd5}"
        printf '[{"tag":"old-local"}]\n' >"${controlledLocal}/sing-box/${controlledEmail}"
        curl() {
            return 95
        }
        subscriptionRemoteControlRequest() {
            local sourceJson=$1
            local endpoint=$2
            local payload=$3
            [[ "${endpoint}" == "subscribe" ]]
            [[ "$(jq -r '.id' <<<"${sourceJson}")" == "edge-wg" ]]
            jq -e --arg account "${controlledEmail}" '.account == $account' <<<"${payload}" >/dev/null
            printf '%s\n' "${payload}" >"${controlledRequestLog}"
            printf '%s\n' '{"ok":true,"default":"dmxlc3M6Ly91dWlkQHdnLmV4YW1wbGUuY29tOjQ0MyNzdWJfdGVhbQ==","clash_meta":"proxies:\n- name: sub_team\n","sing_box":[{"tag":"sub_team"}]}'
        }
        updateRemoteSubscribe "${controlledEmailMd5}" "${controlledEmail}"
        jq -e --arg account "${controlledEmail}" '.account == $account' "${controlledRequestLog}" >/dev/null
        grep -qxF 'vless://uuid@wg.example.com:443#sub_team_edge-wg' "${controlledPublic}/default/${controlledEmailMd5}"
        grep -qxF -- '- name: sub_team_edge-wg' "${controlledPublic}/clashMeta/${controlledEmailMd5}"
        jq -e '.[0].tag == "old-local" and .[1].tag == "sub_team_edge-wg"' "${controlledLocal}/sing-box/${controlledEmail}" >/dev/null
        if [[ -n "${oldSubscribeLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${oldSubscribeLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
        if [[ -n "${oldSubscribeDir}" ]]; then export PADM_SUBSCRIBE_DIR="${oldSubscribeDir}"; else unset PADM_SUBSCRIBE_DIR; fi
        if [[ -n "${oldGroupsDir}" ]]; then export PADM_SUBSCRIPTION_GROUPS_DIR="${oldGroupsDir}"; else unset PADM_SUBSCRIPTION_GROUPS_DIR; fi
        )
    fi

    if remoteSubscribeFetchPartSelected append-failure; then
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
    fi

    if remoteSubscribeFetchPartSelected commit-failure; then
        writeRemoteSubscribeOldOutputs
        (
        local commitCalls=0
        commitGeneratedFile() {
            commitCalls=$((commitCalls + 1))
            if [[ "${commitCalls}" == "2" ]]; then
                return 1
            fi
            originalCommitGeneratedFile "$@"
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
        if regressionFindHasMatches "${remoteTmpRoot}" -mindepth 1 -maxdepth 1 -type d; then
            return 1
        fi
        )
    fi

    if remoteSubscribeFetchPartSelected idempotent; then
        writeRemoteSubscribeOldOutputs
        updateRemoteSubscribe "${emailMd5}" "${email}"
        updateRemoteSubscribe "${emailMd5}" "${email}"
        [[ "$(grep -cFx -- '- name: "sub_team_r1"' "${publicDir}/clashMeta/${emailMd5}")" == "1" ]]
        [[ "$(grep -cFx 'vless://uuid@remote1.example:443#sub_team_r1' "${publicDir}/default/${emailMd5}")" == "1" ]]
        [[ "$(grep -cFx 'trojan://pass@remote3.example:443#sub_team_r3-extra' "${publicDir}/default/${emailMd5}")" == "1" ]]
        jq -e 'length == 3 and .[0].tag == "old-local" and .[1].tag == "sub_team_r1" and .[2].tag == "sub_team_r3-extra"' "${localDir}/sing-box/${email}" >/dev/null
    fi

    if [[ -n "${oldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${oldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
    if [[ -n "${oldPublicDir}" ]]; then export PADM_SUBSCRIBE_DIR="${oldPublicDir}"; else unset PADM_SUBSCRIBE_DIR; fi
    if [[ -n "${oldFakeRemoteSubscribeMode}" ]]; then export PADM_FAKE_REMOTE_SUBSCRIBE_MODE="${oldFakeRemoteSubscribeMode}"; else unset PADM_FAKE_REMOTE_SUBSCRIBE_MODE; fi
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
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
    jq -e '. == ["admin","ops","sub_team_a","sub_team_b"]' <<<"${accounts}" >/dev/null

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
    local rootRel="${TMP_DIR}/check-log-backup-restore"
    local root
    local restoreBackupDir
    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P) || return 1
    printf 'old-policy\n' >"${root}/policy.json"

    checkLogBackupCreate restoreBackupDir "${root}/stats.json" "${root}/policy.json"
    printf 'new-stats\n' >"${root}/stats.json"
    printf 'new-policy\n' >"${root}/policy.json"

    checkLogBackupRestore "${restoreBackupDir}"
    [[ ! -e "${root}/stats.json" ]]
    [[ "$(<"${root}/policy.json")" == "old-policy" ]]
)

runManagedFileBackupManifestRegression() (
    local rootRel="${TMP_DIR}/managed-file-backup-manifest"
    local root
    local backupDir

    mkdir -p "${rootRel}/targets"
    root=$(cd -- "${rootRel}" && pwd -P) || return 1
    backupDir="${root}/backup"
    printf 'old-one\n' >"${root}/targets/one.json"

    padmWriteManagedFileBackupManifest "${backupDir}" \
        "xray/one.json" "${root}/targets/one.json" \
        "xray/two.json" "${root}/targets/two.json"
    [[ -f "${backupDir}/xray/one.json" ]]
    [[ -f "${backupDir}/manifest" ]]

    printf 'new-one\n' >"${root}/targets/one.json"
    printf 'new-two\n' >"${root}/targets/two.json"

    padmRestoreManagedFileBackupManifest "${backupDir}"
    [[ "$(<"${root}/targets/one.json")" == "old-one" ]]
    [[ ! -e "${root}/targets/two.json" ]]
)

runPadmBbrManagedCleanupRegression() (
    local root="${TMP_DIR}/padm-bbr-managed-cleanup"
    local repeatStatus="${root}/repeat.status"
    local repeatHelper="${root}/repeat.helper"
    local tempFailStatus="${root}/temp-fail.status"
    local tempFailHelper="${root}/temp-fail.helper"
    local applyFailStatus="${root}/apply-fail.status"
    local applyFailHelper="${root}/apply-fail.helper"
    local disableStatus="${root}/disable.status"
    local disableHelper="${root}/disable.helper"
    local thirdPartyStatus="${root}/third-party.status"
    local thirdPartyHelper="${root}/third-party.helper"
    local thirdPartyMarker="${root}/third-party.executed"
    local thirdPartyPathLog="${root}/third-party.path"
    local thirdPartyUrlLog="${root}/third-party.url"
    local thirdPartyHashLog="${root}/third-party.hash"
    mkdir -p "${root}"

    rm -f "${thirdPartyMarker}" "${thirdPartyPathLog}" "${thirdPartyUrlLog}" "${thirdPartyHashLog}"
    : >"${thirdPartyStatus}"
    : >"${thirdPartyHelper}"
    bash -c '
        set -e
        export TMPDIR="$1"
        source "$2/shell/core/runtime.sh"
        source "$2/shell/core/entry_helpers.sh"
        statusLog=$3
        helperLog=$4
        marker=$5
        pathLog=$6
        urlLog=$7
        hashLog=$8
        warnCard() { printf "warn:%s|%s|%s|%s\n" "$1" "$2" "$3" "$4" >>"${helperLog}"; }
        statusCard() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}" >>"${statusLog}"; }
        bbrInstall() { printf "menu\n" >>"${helperLog}"; }
        autoConfirm() { printf -v "$4" y; }
        curl() {
            local outputFile= url=
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -o)
                    outputFile=${2:-}
                    shift 2
                    ;;
                http://* | https://*)
                    url=$1
                    shift
                    ;;
                *) shift ;;
                esac
            done
            [[ -n "${outputFile}" && -n "${url}" ]] || return 1
            printf "%s\n" "${url}" >>"${urlLog}"
            case "${url}" in
            https://api.github.com/repos/ylx2016/Linux-NetSpeed/commits/master)
                printf "%s\n" "{" "  \"sha\": \"0123456789abcdef0123456789abcdef01234567\"" "}" >"${outputFile}"
                ;;
            https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/0123456789abcdef0123456789abcdef01234567/tcpx.sh)
                cat >"${outputFile}" <<SH
#!/usr/bin/env bash
printf executed >"${marker}"
printf "%s\n" "\$0" >"${pathLog}"
SH
                ;;
            *) return 1 ;;
            esac
        }
        sha256sum() {
            printf "sha256sum:%s\n" "$1" >>"${hashLog}"
            return 1
        }
        runThirdPartyTcpAccelerationScript
    ' _ "${root}" "${PROJECT_ROOT}" "${thirdPartyStatus}" "${thirdPartyHelper}" "${thirdPartyMarker}" "${thirdPartyPathLog}" "${thirdPartyUrlLog}" "${thirdPartyHashLog}"
    [[ -f "${thirdPartyMarker}" && "$(<"${thirdPartyMarker}")" == "executed" ]] || return 1
    grep -qxF 'https://api.github.com/repos/ylx2016/Linux-NetSpeed/commits/master' "${thirdPartyUrlLog}" || return 1
    grep -qxF 'https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/0123456789abcdef0123456789abcdef01234567/tcpx.sh' "${thirdPartyUrlLog}" || return 1
    ! grep -qxF 'https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcpx.sh' "${thirdPartyUrlLog}" || return 1
    [[ ! -s "${thirdPartyHashLog}" ]] || return 1
    local executedThirdPartyPath
    [[ -f "${thirdPartyPathLog}" ]] || return 1
    executedThirdPartyPath=$(<"${thirdPartyPathLog}")
    [[ "${executedThirdPartyPath}" == "${root}/padm-tcpx."*/tcpx.sh ]] || return 1
    [[ ! -e "${root}/padm-tcpx.sh" ]] || return 1
    [[ ! -e "$(dirname -- "${executedThirdPartyPath}")" ]] || return 1

    cat >"${root}/repeat-sysctl.conf" <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    cat >"${root}/repeat.state" <<'EOF'
previous_congestion=reno
previous_qdisc=cake
EOF
    : >"${repeatStatus}"
    : >"${repeatHelper}"
    bash -c '
        set -e
        export TMPDIR="$1"
        export PADM_BBR_SYSCTL_CONF="$1/repeat-sysctl.conf"
        export PADM_BBR_STATE_FILE="$1/repeat.state"
        source "$2/shell/core/runtime.sh"
        source "$2/shell/core/entry_helpers.sh"
        statusLog=$3
        helperLog=$4
        statusCard() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}" >>"${statusLog}"; }
        bbrInstall() { printf "menu\n" >>"${helperLog}"; }
        padmBbrAvailable() { return 0; }
        printNetworkOptimizationStatus() { printf "print-status\n" >>"${helperLog}"; }
        readSysctlValue() {
            case "$1" in
            net.ipv4.tcp_congestion_control) printf "bbr\n" ;;
            net.core.default_qdisc) printf "fq\n" ;;
            *) return 0 ;;
            esac
        }
        sysctl() { printf "sysctl:%s\n" "$*" >>"${helperLog}"; return 0; }
        commitGeneratedFile() { printf "unexpected-commit:%s\n" "$2" >>"${helperLog}"; return 1; }
        enableOfficialBbrFq
    ' _ "${root}" "${PROJECT_ROOT}" "${repeatStatus}" "${repeatHelper}"
    grep -qx "sysctl:-p ${root}/repeat-sysctl.conf" "${repeatHelper}"
    ! grep -q '^unexpected-commit:' "${repeatHelper}"
    grep -q 'BBR 已启用|沿用已有 padm 配置和首次启用前状态' "${repeatStatus}"
    grep -qx 'previous_congestion=reno' "${root}/repeat.state"
    grep -qx 'previous_qdisc=cake' "${root}/repeat.state"

    bash -c '
        set -e
        export TMPDIR="$1"
        export PADM_BBR_SYSCTL_CONF="$1/temp-fail-sysctl.conf"
        export PADM_BBR_STATE_FILE="$1/temp-fail.state"
        source "$2/shell/core/runtime.sh"
        source "$2/shell/core/entry_helpers.sh"
        statusLog=$3
        helperLog=$4
        createCount=0
        statusCard() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}" >>"${statusLog}"; }
        bbrInstall() { printf "menu\n" >>"${helperLog}"; }
        padmBbrAvailable() { return 0; }
        coreSetManualCheckMessage() {
            printf "manual-check:%s|%s\n" "$2" "$3" >>"${helperLog}"
            printf -v "$1" "%s，请手动检查%s" "$2" "$3"
        }
        readSysctlValue() {
            case "$1" in
            net.ipv4.tcp_congestion_control) printf "cubic\n" ;;
            net.core.default_qdisc) printf "fq_codel\n" ;;
            *) return 0 ;;
            esac
        }
        padmEnsureSafeDirectory() { printf "ensure-dir:%s\n" "$1" >>"${helperLog}"; return 0; }
        padmCreateTempPath() {
            local resultVar=$1
            createCount=$((createCount + 1))
            if [[ "${createCount}" -eq 1 ]]; then
                local path="$TMPDIR/state-stage"
                : >"${path}"
                printf -v "${resultVar}" "%s" "${path}"
                return 0
            fi
            return 1
        }
        commitGeneratedFile() { printf "commit:%s\n" "$2" >>"${helperLog}"; return 0; }
        removeManagedFileIfPresent() { printf "remove-file:%s\n" "$1" >>"${helperLog}"; return 0; }
        enableOfficialBbrFq
    ' _ "${root}" "${PROJECT_ROOT}" "${tempFailStatus}" "${tempFailHelper}"
    grep -q "remove-file:${root}/temp-fail.state" "${tempFailHelper}" || return 1
    grep -q 'BBR 启用失败|无法创建 sysctl 临时文件' "${tempFailStatus}" || return 1

    bash -c '
        set -e
        export TMPDIR="$1"
        export PADM_BBR_SYSCTL_CONF="$1/apply-fail-sysctl.conf"
        export PADM_BBR_STATE_FILE="$1/apply-fail.state"
        source "$2/shell/core/runtime.sh"
        source "$2/shell/core/entry_helpers.sh"
        statusLog=$3
        helperLog=$4
        createCount=0
        statusCard() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}" >>"${statusLog}"; }
        bbrInstall() { printf "menu\n" >>"${helperLog}"; }
        padmBbrAvailable() { return 0; }
        readSysctlValue() {
            case "$1" in
            net.ipv4.tcp_congestion_control) printf "cubic\n" ;;
            net.core.default_qdisc) printf "fq_codel\n" ;;
            *) return 0 ;;
            esac
        }
        padmEnsureSafeDirectory() { return 0; }
        padmCreateTempPath() {
            local resultVar=$1
            createCount=$((createCount + 1))
            local path="$TMPDIR/stage-${createCount}"
            : >"${path}"
            printf -v "${resultVar}" "%s" "${path}"
        }
        commitGeneratedFile() { printf "commit:%s\n" "$2" >>"${helperLog}"; return 0; }
        removeManagedFilesIfPresent() { printf "remove-files:%s|%s\n" "$1" "$2" >>"${helperLog}"; return 0; }
        restorePadmBbrRuntime() { printf "restore:%s:%s\n" "$1" "$2" >>"${helperLog}"; }
        sysctl() {
            if [[ "$1" == "-p" ]]; then
                return 1
            fi
            printf "sysctl:%s\n" "$*" >>"${helperLog}"
            return 0
        }
        enableOfficialBbrFq
    ' _ "${root}" "${PROJECT_ROOT}" "${applyFailStatus}" "${applyFailHelper}"
    grep -q "remove-files:${root}/apply-fail-sysctl.conf|${root}/apply-fail.state" "${applyFailHelper}" || return 1
    grep -q 'restore:cubic:fq_codel' "${applyFailHelper}" || return 1
    grep -q 'BBR 启用失败|sysctl 应用失败，已删除本次写入并尝试恢复原运行值' "${applyFailStatus}" || return 1

    bash -c '
        set -e
        export TMPDIR="$1"
        export PADM_BBR_SYSCTL_CONF="$1/apply-cleanup-fail-sysctl.conf"
        export PADM_BBR_STATE_FILE="$1/apply-cleanup-fail.state"
        source "$2/shell/core/runtime.sh"
        source "$2/shell/core/entry_helpers.sh"
        statusLog=$3
        helperLog=$4
        createCount=0
        statusCard() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}" >>"${statusLog}"; }
        bbrInstall() { printf "menu\n" >>"${helperLog}"; }
        padmBbrAvailable() { return 0; }
        coreSetManualCheckMessage() {
            printf "manual-check:%s|%s\n" "$2" "$3" >>"${helperLog}"
            printf -v "$1" "%s，请手动检查%s" "$2" "$3"
        }
        readSysctlValue() {
            case "$1" in
            net.ipv4.tcp_congestion_control) printf "cubic\n" ;;
            net.core.default_qdisc) printf "fq_codel\n" ;;
            *) return 0 ;;
            esac
        }
        padmEnsureSafeDirectory() { return 0; }
        padmCreateTempPath() {
            local resultVar=$1
            createCount=$((createCount + 1))
            local path="$TMPDIR/stage-${createCount}"
            : >"${path}"
            printf -v "${resultVar}" "%s" "${path}"
        }
        commitGeneratedFile() { printf "commit:%s\n" "$2" >>"${helperLog}"; return 0; }
        removeManagedFilesIfPresent() { printf "remove-files:%s|%s\n" "$1" "$2" >>"${helperLog}"; return 1; }
        restorePadmBbrRuntime() { printf "restore:%s:%s\n" "$1" "$2" >>"${helperLog}"; }
        sysctl() {
            if [[ "$1" == "-p" ]]; then
                return 1
            fi
            printf "sysctl:%s\n" "$*" >>"${helperLog}"
            return 0
        }
        enableOfficialBbrFq
    ' _ "${root}" "${PROJECT_ROOT}" "${applyFailStatus}" "${applyFailHelper}"
    grep -q "manual-check:sysctl 应用失败，且本次写入清理失败| ${root}/apply-cleanup-fail-sysctl.conf 和 ${root}/apply-cleanup-fail.state" "${applyFailHelper}" || return 1
    grep -q 'BBR 启用失败|sysctl 应用失败，且本次写入清理失败，请手动检查 '"${root}"'/apply-cleanup-fail-sysctl.conf 和 '"${root}"'/apply-cleanup-fail.state' "${applyFailStatus}" || return 1

    printf 'net.core.default_qdisc = fq\n' >"${root}/disable-sysctl.conf" || return 1
    printf 'previous_congestion=reno\nprintf sourced >"%s"\nprevious_qdisc=cake\n' "${root}/disable-sourced.marker" >"${root}/disable.state" || return 1
    bash -c '
        set -e
        export PADM_BBR_SYSCTL_CONF="$1/disable-sysctl.conf"
        export PADM_BBR_STATE_FILE="$1/disable.state"
        source "$2/shell/core/runtime.sh"
        source "$2/shell/core/entry_helpers.sh"
        statusLog=$3
        helperLog=$4
        statusCard() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}" >>"${statusLog}"; }
        bbrInstall() { printf "menu\n" >>"${helperLog}"; }
        printNetworkOptimizationStatus() { printf "print-status\n" >>"${helperLog}"; }
        removeManagedFilesIfPresent() { printf "remove-files:%s|%s\n" "$1" "$2" >>"${helperLog}"; return 0; }
        sysctl() { printf "sysctl:%s\n" "$*" >>"${helperLog}"; return 0; }
        disablePadmBbr
    ' _ "${root}" "${PROJECT_ROOT}" "${disableStatus}" "${disableHelper}"
    grep -q "remove-files:${root}/disable-sysctl.conf|${root}/disable.state" "${disableHelper}" || return 1
    grep -q 'sysctl:--system' "${disableHelper}" || return 1
    grep -q 'sysctl:-w net.ipv4.tcp_congestion_control=reno' "${disableHelper}" || return 1
    grep -q 'sysctl:-w net.core.default_qdisc=cake' "${disableHelper}" || return 1
    [[ ! -e "${root}/disable-sourced.marker" ]]
    grep -q 'padm BBR 已关闭|已删除 '"${root}"'/disable-sysctl.conf' "${disableStatus}" || return 1

    printf 'net.core.default_qdisc = fq\n' >"${root}/disable-cleanup-fail-sysctl.conf" || return 1
    printf 'previous_congestion=reno\nprevious_qdisc=cake\n' >"${root}/disable-cleanup-fail.state" || return 1
    bash -c '
        set -e
        export PADM_BBR_SYSCTL_CONF="$1/disable-cleanup-fail-sysctl.conf"
        export PADM_BBR_STATE_FILE="$1/disable-cleanup-fail.state"
        source "$2/shell/core/runtime.sh"
        source "$2/shell/core/entry_helpers.sh"
        statusLog=$3
        helperLog=$4
        statusCard() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}" >>"${statusLog}"; }
        bbrInstall() { printf "menu\n" >>"${helperLog}"; }
        printNetworkOptimizationStatus() { printf "print-status\n" >>"${helperLog}"; }
        removeManagedFilesIfPresent() { printf "remove-files:%s|%s\n" "$1" "$2" >>"${helperLog}"; return 1; }
        sysctl() { printf "sysctl:%s\n" "$*" >>"${helperLog}"; return 0; }
        disablePadmBbr
    ' _ "${root}" "${PROJECT_ROOT}" "${disableStatus}" "${disableHelper}"
    grep -q 'padm BBR 关闭失败|配置文件清理失败，请手动检查 '"${root}"'/disable-cleanup-fail-sysctl.conf 和 '"${root}"'/disable-cleanup-fail.state' "${disableStatus}" || return 1
)

runCheckLogBackupRejectsUnsafeTargetRegression() (
    local rootRel="${TMP_DIR}/check-log-backup-unsafe"
    local root
    local restoreDir
    local backupDir=
    local rc

    mkdir -p "${rootRel}/relative" "${rootRel}/restore"
    root=$(cd -- "${rootRel}" && pwd -P) || return 1
    restoreDir="${root}/restore"
    printf 'keep\n' >"${root}/relative/stats.json"
    cd "${root}"

    set +e
    checkLogBackupCreate backupDir "relative/stats.json" >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ -z "${backupDir}" ]]
    [[ "$(<"${root}/relative/stats.json")" == "keep" ]]

    cat >"${restoreDir}/manifest" <<'EOF'
-	relative/stats.json	missing
EOF
    set +e
    checkLogBackupRestore "${restoreDir}" >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${root}/relative/stats.json")" == "keep" ]]
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
    local wireGuardMenuPart="${1:-all}"
    local oldWireGuardDir="${PADM_WIREGUARD_CONTROL_DIR:-}"
    local oldCurrentHost="${currentHost:-}"
    local oldNginxConfigPath="${nginxConfigPath:-}"
    local oldPath="${PATH}"
    local controlledCredential updatedCredential failingCredential failingCredentialJson
    local mainPublicKey controlledPublicKey updatedPublicKey failingPublicKey
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

    mainPublicKey=$(printf '0123456789abcdefghijklmnopqrstuv' | base64 -w 0)
    controlledPublicKey=$(printf 'abcdefghijklmnopqrstuvwxyz123456' | base64 -w 0)
    updatedPublicKey=$(printf 'ABCDEFGHIJKLMNOPQRSTUVWXYZ123456' | base64 -w 0)
    failingPublicKey=$(printf '01234567890123456789012345678901' | base64 -w 0)
    controlledCredential=$(subscriptionWireGuardCredentialEncode controlled "$(jq -cn --arg publicKey "${controlledPublicKey}" '{address:"10.77.0.2/24",public_key:$publicKey,control_port:39778,token:"token-a"}')")
    updatedCredential=$(subscriptionWireGuardCredentialEncode controlled "$(jq -cn --arg publicKey "${updatedPublicKey}" '{address:"10.77.0.3/24",public_key:$publicKey,control_port:48779,token:"token-b"}')")
    failingCredential=$(subscriptionWireGuardCredentialEncode controlled "$(jq -cn --arg publicKey "${failingPublicKey}" '{address:"10.77.0.4/24",public_key:$publicKey,control_port:39778,token:"token-fail"}')")
    failingCredentialJson=$(subscriptionWireGuardCredentialDecode "${failingCredential}")

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
    menuSection() { return 0; }
    menuLine() { return 0; }
    menuItem() { return 0; }
    menuReturnItem() { return 0; }
    menuDangerItem() { return 0; }
    menuClose() { return 0; }
    statusCard() { recordMenuAction "statusCard:$1"; }
    errorCard() { recordMenuAction "errorCard:$1"; }
    successCard() { recordMenuAction "successCard:$1"; }
    runSubscriptionGroupSync() { recordMenuAction "runSubscriptionGroupSync:$*"; }

    PADM_WIREGUARD_CONTROL_DIR="${TMP_DIR}/menu-smoke-wireguard"
    currentHost="main.example.com"
    nginxConfigPath="${TMP_DIR}/menu-smoke-nginx/"
    subscriptionWireGuardConfigFile() { echo "${TMP_DIR}/menu-smoke-wireguard/wg-padm.conf"; }
    rm -rf "${PADM_WIREGUARD_CONTROL_DIR}" "${PADM_SUBSCRIPTION_GROUPS_DIR}"
    mkdir -p "${nginxConfigPath}"
    ensureSubscriptionGroupsState

    initSubscriptionWireGuardMain() {
        recordMenuAction initSubscriptionWireGuardMain
        local endpointHost=
        autoRead wg_main_endpoint_host "请输入主控公网地址或域名[用于被控连接 WireGuard]:" endpointHost
        subscriptionWireGuardWriteState --arg endpointHost "${endpointHost}" --arg publicKey "${mainPublicKey}" '.enabled = true | .role = "main" | .address = "10.77.0.1/24" | .endpoint_host = $endpointHost | .public_key = $publicKey | .listen_port = 51820 | .control_port = 39778'
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
    subscriptionWireGuardPublicKey() { printf '%s\n' "${validPublicKey:-MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=}"; }
    writeSubscriptionWireGuardConfig() {
        mkdir -p "$(dirname "$(subscriptionWireGuardConfigFile)")"
        printf 'Address = %s\n' "$(subscriptionWireGuardReadState | jq -r '.address')" >"$(subscriptionWireGuardConfigFile)"
    }
    applySubscriptionWireGuardService() {
        recordMenuAction applySubscriptionWireGuardService
        [[ "${wireGuardApplyShouldFail}" == "true" ]] && return 1
        writeSubscriptionWireGuardConfig
    }
    subscriptionWireGuardWaitForAddress() { return 0; }
    eval "$(declare -f subscriptionWireGuardWriteState | sed '1s/^subscriptionWireGuardWriteState/originalSubscriptionWireGuardWriteState/')"
    subscriptionWireGuardWriteState() {
        if [[ "${restoreStateWriteShouldFail}" == "true" && "${*: -1}" == '$previousState' ]]; then
            return 1
        fi
        if [[ "${disableStateWriteShouldFail}" == "true" && "${*: -1}" == ".enabled = false | .firewall_owned = false" ]]; then
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
        if [[ "${refreshWritesNewConfig}" == "true" ]]; then
            printf 'new-nginx-control\n' >"$(subscriptionWireGuardNginxConfigFile)"
        fi
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
    userJsonCard() { recordMenuAction "userJsonCard:$1"; }
    subscribe() { recordMenuAction subscribe; }

    wireGuardMenuPartSelected() {
        [[ "${wireGuardMenuPart}" == "all" || "${wireGuardMenuPart}" == "$1" ]]
    }

    wireGuardMenuResetFixture() {
        PATH="${oldPath}"
        wireGuardApplyShouldFail=
        installControlShouldFail=
        refreshControlShouldFail=
        refreshWritesNewConfig=
        serviceQueueShouldFail=
        addSourceShouldFail=
        setCredentialShouldFail=
        restoreStateWriteShouldFail=
        restoreGroupsWriteShouldFail=
        disableStateWriteShouldFail=
        stopShouldFail=
        stopAllowMissingBackend=
        actions=
        rm -rf "${PADM_WIREGUARD_CONTROL_DIR}" "${PADM_SUBSCRIPTION_GROUPS_DIR}"
        mkdir -p "${nginxConfigPath}"
        ensureSubscriptionGroupsState
    }

    wireGuardMenuInitializeMain() {
        wireGuardMenuResetFixture
        resetMenuActions
        manageSubscriptionRoleSelection <<<"1
main.example.com
3"
        assertMenuAction initSubscriptionWireGuardMain
        subscriptionWireGuardReadState | jq -e '.role == "main" and .enabled == true and .endpoint_host == "main.example.com" and .address == "10.77.0.1/24"' >/dev/null
        grep -q 'Address = 10.77.0.1/24' "$(subscriptionWireGuardConfigFile)"
        mainStateSnapshot=$(subscriptionWireGuardReadState)
    }

    wireGuardMenuAddEdgePeer() {
        local reservedCredentialJson
        local reservedCredential
        reservedCredentialJson=$(jq -n --arg publicKey "${updatedPublicKey}" '{address:"10.77.0.2/24",public_key:$publicKey,control_port:39778,token:"token-main",kind:"controlled"}')
        reservedCredential=$(subscriptionWireGuardCredentialEncode controlled "$(jq -c 'del(.kind)' <<<"${reservedCredentialJson}")")
        resetMenuActions
        if addOtherSubscribe <<<"${reservedCredential}
main"; then
            return 1
        fi
        assertMenuAction 'errorCard:main 是保留源 ID，不能作为被控服务器别名'
        if subscriptionWireGuardAddPeerFromCredential main "${reservedCredentialJson}" >/dev/null 2>&1; then
            return 1
        fi
        subscriptionWireGuardReadState | jq -e 'any(.peers[]?; .id == "main") | not' >/dev/null
        resetMenuActions
        manageSubscriptionMultiServer <<<"2
1
${controlledCredential}
edge-a
3
5"
        assertMenuAction 'runSubscriptionGroupSync:skip-subscribe-refresh'
        subscriptionWireGuardReadState | jq -e --arg publicKey "${controlledPublicKey}" '.peers[] | select(.id == "edge-a" and .address == "10.77.0.2/24" and .public_key == $publicKey)' >/dev/null
        subscriptionGroupsStateRead -e '.groups[0].sources[] | select(.id == "edge-a" and .scheme == "wireguard" and .transport == "wireguard" and .host == "10.77.0.2" and .port == 39778 and .control_token == "token-a")' >/dev/null
    }

    if wireGuardMenuPartSelected bootstrap; then
        wireGuardMenuInitializeMain

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
        ! regressionFindHasMatches "$(dirname "${nginxTarget}")" -maxdepth 1 \( -name '.padm-control-wg.conf.nginx.*' -o -name '.padm-control-wg.conf.backup.*' \)

        wireGuardMenuResetFixture
        refreshControlShouldFail=true
        resetMenuActions
        if initSubscriptionWireGuardControlled <<<"" >/dev/null 2>&1; then
            refreshControlShouldFail=
            return 1
        fi
        refreshControlShouldFail=
        assertMenuAction refreshSubscriptionWireGuardNginxControl
        if assertMenuAction installSubscriptionControlService; then
            return 1
        fi
        subscriptionWireGuardReadState | jq -e '.role == "uninitialized" and .enabled == false' >/dev/null
    fi

    if wireGuardMenuPartSelected peer-add-update; then
        wireGuardMenuInitializeMain
        wireGuardMenuAddEdgePeer

        resetMenuActions
        manageSubscriptionMultiServer <<<"3
${updatedCredential}
edge-a
5"
        assertMenuAction 'runSubscriptionGroupSync:skip-subscribe-refresh'
        subscriptionWireGuardReadState | jq -e --arg publicKey "${updatedPublicKey}" '.peers[] | select(.id == "edge-a" and .address == "10.77.0.3/24" and .public_key == $publicKey)' >/dev/null
        subscriptionGroupsStateRead -e '.groups[0].sources[] | select(.id == "edge-a" and .host == "10.77.0.3" and .port == 48779 and .control_token == "token-b")' >/dev/null
    fi

    if wireGuardMenuPartSelected peer-rollback-apply || wireGuardMenuPartSelected peer-rollback-apply-service; then
        wireGuardMenuInitializeMain
        wireGuardMenuAddEdgePeer

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
    fi

    if wireGuardMenuPartSelected peer-rollback-apply || wireGuardMenuPartSelected peer-rollback-apply-restore; then
        wireGuardMenuInitializeMain
        wireGuardMenuAddEdgePeer

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
    fi

    if wireGuardMenuPartSelected peer-rollback-source; then
        wireGuardMenuInitializeMain
        wireGuardMenuAddEdgePeer

        addSourceShouldFail=true
        if subscriptionWireGuardAddPeerFromCredential "edge-addfail" "${failingCredentialJson}" >/dev/null 2>&1; then
            addSourceShouldFail=
            return 1
        fi
        addSourceShouldFail=
        if subscriptionGroupsStateRead -e 'any(.groups[0].sources[]?; .id == "edge-addfail")' >/dev/null 2>&1; then
            return 1
        fi
    fi

    if wireGuardMenuPartSelected peer-rollback-credential || wireGuardMenuPartSelected peer-rollback-credential-write; then
        wireGuardMenuInitializeMain
        wireGuardMenuAddEdgePeer

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
    fi

    if wireGuardMenuPartSelected peer-rollback-credential || wireGuardMenuPartSelected peer-rollback-credential-groups-restore; then
        wireGuardMenuInitializeMain
        wireGuardMenuAddEdgePeer

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
    fi

    if wireGuardMenuPartSelected peer-source-control || wireGuardMenuPartSelected peer-source-control-toggle || wireGuardMenuPartSelected peer-source-control-clear-error || wireGuardMenuPartSelected peer-source-control-status; then
        wireGuardMenuInitializeMain
        wireGuardMenuAddEdgePeer

        if wireGuardMenuPartSelected peer-source-control || wireGuardMenuPartSelected peer-source-control-toggle; then
            resetMenuActions
            toggleSubscriptionSourceMenu() {
                subscriptionRequireMainRole || return 1
                recordMenuAction toggleSubscriptionSourceMenu
                local sourceId=
                local sourceAction=
                autoRead subscription_source_toggle_id "请输入被控服务器源ID:" sourceId
                autoRead subscription_source_action "请输入操作[enable/disable]:" sourceAction
                if [[ "${sourceAction}" == "enable" ]]; then
                    subscriptionGroupsStateWrite --arg groupId "$(activeSubscriptionGroupId)" --arg id "${sourceId}" --argjson enabled true '
                      .groups |= map(if .id == $groupId then
                        .sources |= map(if .id == $id and .role != "main" then .enabled = $enabled else . end)
                      else . end)'
                elif [[ "${sourceAction}" == "disable" ]]; then
                    subscriptionGroupsStateWrite --arg groupId "$(activeSubscriptionGroupId)" --arg id "${sourceId}" --argjson enabled false '
                      .groups |= map(if .id == $groupId then
                        .sources |= map(if .id == $id and .role != "main" then .enabled = $enabled else . end)
                      else . end)'
                else
                    return 1
                fi
            }
            resetMenuActions
            toggleSubscriptionSourceMenu <<<"edge-a
disable"
            subscriptionGroupsStateRead -e '.groups[0].sources[] | select(.id == "edge-a" and .enabled == false)' >/dev/null
            resetMenuActions
            toggleSubscriptionSourceMenu <<<"edge-a
enable"
            subscriptionGroupsStateRead -e '.groups[0].sources[] | select(.id == "edge-a" and .enabled == true)' >/dev/null
        fi

        if wireGuardMenuPartSelected peer-source-control || wireGuardMenuPartSelected peer-source-control-clear-error; then
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
        fi

        if wireGuardMenuPartSelected peer-source-control || wireGuardMenuPartSelected peer-source-control-status; then
            resetMenuActions
            local multiServerStatusOutput
            multiServerStatusOutput=
            manageSubscriptionMultiServer <<<"4
5"
            assertMenuAction 'statusCard:本机主控接入凭据'
        fi
    fi

    if wireGuardMenuPartSelected control-restore; then
        wireGuardMenuInitializeMain

        subscriptionWireGuardWriteState '.enabled = false'
        resetMenuActions
        restartSubscriptionWireGuardControl >/dev/null 2>&1
        subscriptionWireGuardReadState | jq -e '.enabled == true' >/dev/null
        assertMenuAction installSubscriptionControlService
        assertMenuAction applySubscriptionWireGuardService

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
        nginxTarget=$(subscriptionWireGuardNginxConfigFile)
        printf 'old-nginx-control\n' >"${nginxTarget}"
        refreshWritesNewConfig=true
        serviceQueueShouldFail=true
        if restartSubscriptionWireGuardControl >/dev/null 2>&1; then
            refreshWritesNewConfig=
            serviceQueueShouldFail=
            return 1
        fi
        refreshWritesNewConfig=
        serviceQueueShouldFail=
        grep -qxF 'old-nginx-control' "${nginxTarget}"

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
        nginxTarget=$(subscriptionWireGuardNginxConfigFile)
        printf 'keep-nginx-control\n' >"${nginxTarget}"
        subscriptionWireGuardRestoreStateAndConfig "${restoreStopState}" >/dev/null 2>&1 || {
            stopShouldFail=
            stopAllowMissingBackend=
            return 1
        }
        stopShouldFail=
        stopAllowMissingBackend=
        assertMenuAction 'stopSubscriptionWireGuardControlService:true'
        [[ ! -e "$(subscriptionWireGuardConfigFile)" ]]
        [[ ! -e "${nginxTarget}" ]]

        local disabledConfiguredState
        subscriptionWireGuardWriteState --argjson previousState "${mainStateSnapshot}" '$previousState | .enabled = false'
        disabledConfiguredState=$(subscriptionWireGuardReadState)
        subscriptionWireGuardWriteState '.enabled = true | .peers += [{id:"edge-b", address:"10.77.0.3/24", public_key:"peer-key", enabled:true}]'
        printf 'new-config\n' >"$(subscriptionWireGuardConfigFile)"
        nginxTarget=$(subscriptionWireGuardNginxConfigFile)
        printf 'keep-nginx-control\n' >"${nginxTarget}"
        resetMenuActions
        subscriptionWireGuardRestoreStateAndConfig "${disabledConfiguredState}"
        assertMenuAction 'stopSubscriptionWireGuardControlService:true'
        if assertMenuAction applySubscriptionWireGuardService; then
            return 1
        fi
        subscriptionWireGuardReadState | jq -e '.enabled == false and .role == "main" and .address == "10.77.0.1/24" and (.peers | length) == 0' >/dev/null
        grep -qx 'Address = 10.77.0.1/24' "$(subscriptionWireGuardConfigFile)"
        grep -qx 'keep-nginx-control' "${nginxTarget}"
    fi

    if [[ -n "${oldWireGuardDir}" ]]; then PADM_WIREGUARD_CONTROL_DIR="${oldWireGuardDir}"; else unset PADM_WIREGUARD_CONTROL_DIR; fi
    currentHost="${oldCurrentHost}"
    nginxConfigPath="${oldNginxConfigPath}"
)

runSubscriptionWireGuardMenuFlowBootstrapRegression() {
    local validPublicKey
    local peerPublicKey
    local newPeerPublicKey
    local duplicateAddressState
    local duplicateKeyState
    local outsideNetworkState
    local validState
    validPublicKey=$(printf '01234567890123456789012345678901' | base64 -w 0)
    peerPublicKey=$(printf 'abcdefghijklmnopqrstuvwxyz123456' | base64 -w 0)
    newPeerPublicKey=$(printf 'ABCDEFGHIJKLMNOPQRSTUVWXYZ123456' | base64 -w 0)
    subscriptionWireGuardValidPublicKeyValue "${validPublicKey}"
    ! subscriptionWireGuardValidPublicKeyValue 'not-a-wireguard-key'
    ! subscriptionWireGuardValidPublicKeyValue 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    validState=$(jq -n --arg publicKey "${validPublicKey}" --arg peerPublicKey "${peerPublicKey}" '{network:"10.77.0.0/24",address:"10.77.0.1/24",listen_port:51820,public_key:$publicKey,peers:[{id:"a",address:"10.77.0.2/24",public_key:$peerPublicKey,enabled:true}]}')
    subscriptionWireGuardValidateStateForConfig "${validState}" || return 1
    subscriptionWireGuardPeerIdentityAvailable "${validState}" "b" "10.77.0.3/24" "${newPeerPublicKey}" || return 1
    if subscriptionWireGuardPeerIdentityAvailable "${validState}" "b" "10.77.0.2/24" "${newPeerPublicKey}"; then
        return 1
    fi
    duplicateAddressState=$(jq -n --arg publicKey "${validPublicKey}" --arg peerPublicKey "${peerPublicKey}" --arg newPeerPublicKey "${newPeerPublicKey}" '{network:"10.77.0.0/24",address:"10.77.0.1/24",listen_port:51820,public_key:$publicKey,peers:[{id:"a",address:"10.77.0.2/24",public_key:$peerPublicKey,enabled:true},{id:"b",address:"10.77.0.2/32",public_key:$newPeerPublicKey,enabled:true}]}')
    if subscriptionWireGuardValidateStateForConfig "${duplicateAddressState}" >/dev/null 2>&1; then
        return 1
    fi
    duplicateKeyState=$(jq -n --arg publicKey "${validPublicKey}" --arg peerPublicKey "${peerPublicKey}" '{network:"10.77.0.0/24",address:"10.77.0.1/24",listen_port:51820,public_key:$publicKey,peers:[{id:"a",address:"10.77.0.2/24",public_key:$peerPublicKey,enabled:true},{id:"b",address:"10.77.0.3/24",public_key:$peerPublicKey,enabled:true}]}')
    if subscriptionWireGuardValidateStateForConfig "${duplicateKeyState}" >/dev/null 2>&1; then
        return 1
    fi
    outsideNetworkState=$(jq -n --arg publicKey "${validPublicKey}" --arg peerPublicKey "${peerPublicKey}" '{network:"10.77.0.0/24",address:"10.77.0.1/24",listen_port:51820,public_key:$publicKey,peers:[{id:"a",address:"10.78.0.2/24",public_key:$peerPublicKey,enabled:true}]}')
    if subscriptionWireGuardValidateStateForConfig "${outsideNetworkState}" >/dev/null 2>&1; then
        return 1
    fi
    runSubscriptionWireGuardMenuFlowRegression bootstrap
}

runSubscriptionWireGuardMenuFlowPeerAddUpdateRegression() {
    runSubscriptionWireGuardMenuFlowRegression peer-add-update
}

runSubscriptionWireGuardMenuFlowPeerRollbackSourceRegression() {
    runSubscriptionWireGuardMenuFlowRegression peer-rollback-source
}

runSubscriptionWireGuardMenuFlowPeerRollbackApplyServiceRegression() {
    runSubscriptionWireGuardMenuFlowRegression peer-rollback-apply-service
}

runSubscriptionWireGuardMenuFlowPeerRollbackApplyRestoreRegression() {
    runSubscriptionWireGuardMenuFlowRegression peer-rollback-apply-restore
}

runSubscriptionWireGuardMenuFlowPeerRollbackCredentialWriteRegression() {
    runSubscriptionWireGuardMenuFlowRegression peer-rollback-credential-write
}

runSubscriptionWireGuardMenuFlowPeerRollbackCredentialGroupsRestoreRegression() {
    runSubscriptionWireGuardMenuFlowRegression peer-rollback-credential-groups-restore
}

runSubscriptionWireGuardMenuFlowPeerSourceControlToggleRegression() {
    runSubscriptionWireGuardMenuFlowRegression peer-source-control-toggle
}

runSubscriptionWireGuardMenuFlowPeerSourceControlClearErrorRegression() {
    runSubscriptionWireGuardMenuFlowRegression peer-source-control-clear-error
}

runSubscriptionWireGuardMenuFlowPeerSourceControlStatusRegression() {
    runSubscriptionWireGuardMenuFlowRegression peer-source-control-status
}

runSubscriptionWireGuardMenuFlowControlRestoreRegression() {
    runSubscriptionWireGuardMenuFlowRegression control-restore
}

runSubscriptionWireGuardRestoreRunnerRegression() (
    local errorLog="${TMP_DIR}/subscription-wireguard-restore-runner-error.log"
    local helperLog="${TMP_DIR}/subscription-wireguard-restore-runner-helper.log"
    : >"${errorLog}"
    : >"${helperLog}"
    errorCard() { printf '%s\n' "$@" >>"${errorLog}"; }
    subscriptionWireGuardStateFile() { printf '%s\n' "/tmp/wg-state.json"; }
    subscriptionWireGuardConfigFile() { printf '%s\n' "/tmp/wg.conf"; }
    subscriptionGroupsFile() { printf '%s\n' "/tmp/groups.json"; }
    subscriptionWireGuardAppendManualCheckLine() {
        printf "manual-check:%s|%s\n" "$2" "$3" >>"${helperLog}"
        printf -v "$1" '%s' "${2}：${3}"
    }

    subscriptionWireGuardRestoreStateAndConfig() { return 1; }
    set +e
    subscriptionWireGuardRunRestoreSteps '{}' "" "WireGuard 主控服务启动失败"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -q '^WireGuard 主控服务启动失败，且旧状态恢复失败$' "${errorLog}"
    grep -q 'WireGuard 状态文件' "${errorLog}"
    grep -q 'WireGuard 配置文件' "${errorLog}"
    grep -q 'manual-check:请手动检查 WireGuard 状态文件|/tmp/wg-state.json' "${helperLog}"
    grep -q 'manual-check:请手动检查 WireGuard 配置文件|/tmp/wg.conf' "${helperLog}"

    : >"${errorLog}"
    : >"${helperLog}"
    subscriptionWireGuardRestoreStateAndConfig() { return 0; }
    subscriptionWireGuardRestoreGroupsState() { return 1; }
    set +e
    subscriptionWireGuardRunRestoreSteps '{}' '{}' "订阅来源凭据写入失败"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -q '^订阅来源凭据写入失败，且旧状态恢复失败$' "${errorLog}"
    grep -q '订阅组状态文件' "${errorLog}"
    grep -q 'manual-check:请手动检查订阅组状态文件|/tmp/groups.json' "${helperLog}"
)

runCoreInvalidInputRetryMenuRegression() (
    local actions=

    recordMenuAction() {
        actions+="$1"$'\n'
    }
    assertMenuAction() {
        grep -qxF "$1" <<<"${actions}"
    }
    errorCard() {
        recordMenuAction "errorCard:$1"
    }
    sampleMenu() {
        recordMenuAction "sampleMenu:$*"
    }

    declare -F coreInvalidInputRetryMenu >/dev/null
    coreInvalidInputRetryMenu sampleMenu alpha beta
    assertMenuAction 'errorCard:输入有误，请重新输入'
    assertMenuAction 'sampleMenu:alpha beta'

    [[ "$(grep -cF 'coreInvalidInputRetryMenu xrayVersionManageMenu' "${PROJECT_ROOT}/shell/core/cores.sh")" == "2" ]]
    [[ "$(grep -cF 'coreInvalidInputRetryMenu singBoxVersionManageMenu' "${PROJECT_ROOT}/shell/core/cores.sh")" == "2" ]]
    [[ "$(grep -cF 'coreInvalidInputRetryMenu coreServiceControlMenu "${core}"' "${PROJECT_ROOT}/shell/core/cores.sh")" == "1" ]]
    [[ "$(grep -cF 'coreInvalidInputRetryMenu coreConfigMaintenanceMenu' "${PROJECT_ROOT}/shell/core/cores.sh")" == "1" ]]
    [[ "$(grep -cF 'coreInvalidInputRetryMenu coreLogsMenu' "${PROJECT_ROOT}/shell/core/cores.sh")" == "1" ]]
    [[ "$(grep -cF 'coreInvalidInputRetryMenu coreAllServicesMenu' "${PROJECT_ROOT}/shell/core/cores.sh")" == "1" ]]
    [[ "$(grep -cF 'coreInvalidInputRetryMenu coreVersionManageMenu' "${PROJECT_ROOT}/shell/core/cores.sh")" == "1" ]]

    ! grep -qF 'coreInvalidInputErrorCard; xrayVersionManageMenu' "${PROJECT_ROOT}/shell/core/cores.sh"
    ! grep -qF 'coreInvalidInputErrorCard; singBoxVersionManageMenu' "${PROJECT_ROOT}/shell/core/cores.sh"
    ! grep -qF 'coreInvalidInputErrorCard; coreServiceControlMenu "${core}"' "${PROJECT_ROOT}/shell/core/cores.sh"
    ! grep -qF 'coreInvalidInputErrorCard; coreConfigMaintenanceMenu' "${PROJECT_ROOT}/shell/core/cores.sh"
    ! grep -qF 'coreInvalidInputErrorCard; coreLogsMenu' "${PROJECT_ROOT}/shell/core/cores.sh"
    ! grep -qF 'coreInvalidInputErrorCard; coreAllServicesMenu' "${PROJECT_ROOT}/shell/core/cores.sh"
    ! grep -qF 'coreInvalidInputErrorCard; coreVersionManageMenu' "${PROJECT_ROOT}/shell/core/cores.sh"
)

runCoreSelectionRetryActionRegression() (
    local actions=
    local -a expectedCounts=(
        'shell/core/menu.sh|7'
        'shell/core/cores.sh|1'
        'shell/core/routing_access_control.sh|3'
        'shell/core/manage.sh|18'
        'shell/core/fail2ban.sh|1'
        'shell/core/entry_helpers.sh|1'
        'shell/core/routing_socks.sh|4'
        'shell/core/routing_ipv6.sh|1'
    )
    local -a expectedPatterns=(
        'shell/core/menu.sh|coreSelectionRetryAction menu'
        'shell/core/cores.sh|coreSelectionRetryAction selectCoreInstall'
        'shell/core/routing_access_control.sh|coreSelectionRetryAction removeAccessControlMenu'
        'shell/core/manage.sh|coreSelectionRetryAction manageTraditionalTlsFallback "$@"'
        'shell/core/manage.sh|coreSelectionRetryAction checkBTPanel'
        'shell/core/manage.sh|coreSelectionRetryAction manageXHTTPPresets'
        'shell/core/manage.sh|coreSelectionRetryAction manageTuic'
        'shell/core/fail2ban.sh|coreSelectionRetryAction manageFail2ban'
        'shell/core/entry_helpers.sh|coreSelectionRetryAction bbrInstall'
        'shell/core/routing_socks.sh|coreSelectionRetryAction socks5Routing'
        'shell/core/routing_ipv6.sh|coreSelectionRetryAction ipv6Routing'
    )
    local -a removedPatterns=(
        'shell/core/menu.sh|coreSelectionErrorCard
        menu'
        'shell/core/cores.sh|coreSelectionErrorCard
        selectCoreInstall'
        'shell/core/routing_access_control.sh|coreSelectionErrorCard; removeAccessControlMenu; return'
        'shell/core/manage.sh|coreSelectionErrorCard
        manageTraditionalTlsFallback "$@"'
        'shell/core/manage.sh|coreSelectionErrorCard
        checkBTPanel'
        'shell/core/manage.sh|coreSelectionErrorCard; manageXHTTPPresets'
        'shell/core/manage.sh|coreSelectionErrorCard
        manageTuic'
        'shell/core/fail2ban.sh|coreSelectionErrorCard
        manageFail2ban'
        'shell/core/entry_helpers.sh|coreSelectionErrorCard
        bbrInstall'
        'shell/core/routing_socks.sh|coreSelectionErrorCard
        socks5Routing'
        'shell/core/routing_ipv6.sh|coreSelectionErrorCard
        ipv6Routing'
    )
    local entry file pattern expectedCount actualCount

    recordMenuAction() {
        actions+="$1"$'\n'
    }
    assertMenuAction() {
        grep -qxF "$1" <<<"${actions}"
    }
    errorCard() {
        recordMenuAction "errorCard:$1"
    }
    sampleAction() {
        recordMenuAction "sampleAction:$*"
    }

    declare -F coreSelectionRetryAction >/dev/null
    coreSelectionRetryAction sampleAction alpha beta
    assertMenuAction 'errorCard:选择错误，请重新选择'
    assertMenuAction 'sampleAction:alpha beta'

    for entry in "${expectedCounts[@]}"; do
        IFS='|' read -r file expectedCount <<<"${entry}"
        actualCount=$(grep -cF 'coreSelectionRetryAction ' "${PROJECT_ROOT}/${file}")
        [[ "${actualCount}" == "${expectedCount}" ]]
    done
    for entry in "${expectedPatterns[@]}"; do
        IFS='|' read -r file pattern <<<"${entry}"
        grep -qF "${pattern}" "${PROJECT_ROOT}/${file}"
    done
    for entry in "${removedPatterns[@]}"; do
        IFS='|' read -r file pattern <<<"${entry}"
        ! grep -qF "${pattern}" "${PROJECT_ROOT}/${file}"
    done
)

runSyncConfiguredManagedUsersHelperRegression() (
    local syncConfigRoot="${TMP_DIR}/sync-configured-managed-users-helper"
    local helperLog="${syncConfigRoot}/helper.log"
    local currentManaged
    local oldConfigPath="${configPath:-}"
    local oldSingBoxConfigPath="${singBoxConfigPath:-}"

    mkdir -p "${syncConfigRoot}/xray" "${syncConfigRoot}/sing-box"
    configPath="${syncConfigRoot}/xray/"
    singBoxConfigPath="${syncConfigRoot}/sing-box/"
    cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_team_a-main"},{"email":"admin-root"}]}}]}
JSON
    cat >"${singBoxConfigPath}06_hysteria2_inbounds.json" <<'JSON'
{"inbounds":[{"users":[{"name":"sub_team_b-main"},{"username":"ops"}]}]}
JSON

    subscriptionSyncConfiguredManagedUsers() {
        printf '%s\n' "$#" >"${helperLog}"
        printf '["sub_team_a-main","sub_team_b-main","ops"]\n'
    }

    currentManaged=$(subscriptionSyncCurrentManagedUsers \
        "${configPath}02_VLESS_TCP_inbounds.json" \
        "${singBoxConfigPath}06_hysteria2_inbounds.json")
    jq -e '. == ["sub_team_a-main","sub_team_b-main"]' <<<"${currentManaged}" >/dev/null
    [[ -f "${helperLog}" ]] || return 1
    grep -qx '2' "${helperLog}" || return 1

    unset -f subscriptionSyncConfiguredManagedUsers
    if [[ -n "${oldConfigPath}" ]]; then
        configPath="${oldConfigPath}"
    else
        unset configPath
    fi
    if [[ -n "${oldSingBoxConfigPath}" ]]; then
        singBoxConfigPath="${oldSingBoxConfigPath}"
    else
        unset singBoxConfigPath
    fi
)

runTrafficConfiguredAccountsHelperRegression() (
    local trafficRoot="${TMP_DIR}/traffic-configured-accounts-helper"
    local helperLog="${trafficRoot}/helper.log"
    local accounts
    local oldConfigPath="${configPath:-}"
    local oldSingBoxConfigPath="${singBoxConfigPath:-}"

    mkdir -p "${trafficRoot}/xray" "${trafficRoot}/sing-box"
    configPath="${trafficRoot}/xray/"
    singBoxConfigPath="${trafficRoot}/sing-box/"
    cat >"${configPath}01_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_team_a-vless"},{"email":"admin-root"}]}}]}
JSON
    cat >"${singBoxConfigPath}02_inbounds.json" <<'JSON'
{"inbounds":[{"users":[{"name":"sub_team_b-hysteria2"},{"username":"ops"}]}]}
JSON

    subscriptionSyncConfiguredAccountNamesJson() {
        printf '%s\n' "$#" >"${helperLog}"
        printf '["admin","ops","sub_team_a","sub_team_b"]\n'
    }

    accounts=$(collectLocalTrafficAccounts)
    jq -e '. == ["admin","ops","sub_team_a","sub_team_b"]' <<<"${accounts}" >/dev/null
    [[ -f "${helperLog}" ]] || return 1
    grep -qx '0' "${helperLog}" || return 1

    unset -f subscriptionSyncConfiguredAccountNamesJson
    if [[ -n "${oldConfigPath}" ]]; then
        configPath="${oldConfigPath}"
    else
        unset configPath
    fi
    if [[ -n "${oldSingBoxConfigPath}" ]]; then
        singBoxConfigPath="${oldSingBoxConfigPath}"
    else
        unset singBoxConfigPath
    fi
)

runTrafficAccountIdMapHelperRegression() (
    local trafficRoot="${TMP_DIR}/traffic-account-id-map-helper"
    local helperLog="${trafficRoot}/helper.log"
    local trafficSnapshot='{"ok":true,"items":[{"account":"sub_team_a","upload":1,"download":2},{"account":"sub_team_b","upload":3,"download":4}]}'

    mkdir -p "${trafficRoot}/groups"
    export PADM_SUBSCRIPTION_GROUPS_DIR="${trafficRoot}/groups"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"11111111-1111-1111-1111-111111111111"},{"id":"team-b","name":"Team B","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"22222222-2222-2222-2222-222222222222"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON

    subscriptionSyncAccountIdMapJsonFromIds() {
        cat >"${helperLog}"
        printf '{"sub_team_a":"team-a","sub_team_b":"team-b"}\n'
    }

    writeSubscriptionTrafficSnapshot "${trafficSnapshot}"
    jq -e '
      .groups[0].traffic.user_groups["team-a"].sources.main.counters.sub_team_a.upload == 1 and
      .groups[0].traffic.user_groups["team-a"].sources.main.counters.sub_team_a.download == 2 and
      .groups[0].traffic.user_groups["team-b"].sources.main.counters.sub_team_b.upload == 3 and
      .groups[0].traffic.user_groups["team-b"].sources.main.counters.sub_team_b.download == 4
    ' "$(subscriptionGroupsFile)" >/dev/null
    [[ -f "${helperLog}" ]] || return 1
    grep -qx 'team-a' "${helperLog}" || return 1
    grep -qx 'team-b' "${helperLog}" || return 1

    unset -f subscriptionSyncAccountIdMapJsonFromIds
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
    menu() { recordMenuAction menu; }
    menuLine() { output+="$*"$'\n'; }
    menuItem() { output+="$2 $3"$'\n'; }
    menuRecommendedItem() { output+="$2 $3"$'\n'; }
    menuReturnItem() { output+="$2 $3"$'\n'; }
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
    [[ "$(protocolMenuDescription 5)" == "推荐；sing-box / tcp / tls" ]]
    [[ "$(protocolMenuDescription 4)" == "推荐；sing-box / tcp / tls" ]]
    coreInstallType="${oldCoreInstallType}"
}

runMenuSmokeRegression() {
    local actions=
    local menuSmokePart="${1:-all}"
    local oldConfigPath="${configPath:-}"
    local oldCoreInstallType="${coreInstallType:-}"
    local oldRealityPageSize="${REALITY_TARGET_PAGE_SIZE:-}"
    local serviceQueueShouldFail=
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

    menuSmokePartSelected() {
        [[ "${menuSmokePart}" == "all" || "${menuSmokePart}" == "$1" ]]
    }
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
    if menuSmokePartSelected core; then
        coreSelectionErrorCard
        assertMenuAction 'errorCard:选择错误，请重新选择'
        resetMenuActions
        coreInvalidInputErrorCard
        assertMenuAction 'errorCard:输入有误，请重新输入'
        resetMenuActions
        coreCancelledStatusCard "操作未执行"
        assertMenuAction 'statusCard:已取消'
        resetMenuActions
        coreRuleExistsStatusCard "example.com 已存在，跳过"
        assertMenuAction 'statusCard:规则已存在'
        resetMenuActions
        corePortInputErrorCard
        assertMenuAction 'errorCard:端口输入错误'
        resetMenuActions
        aloneNginxConfigRecoveredErrorCard
        assertMenuAction 'errorCard:Nginx 配置检测失败，已恢复旧 alone.conf'
        resetMenuActions
        nginxStartFailureCard "请查看下方日志"
        assertMenuAction 'statusCard:Nginx 启动失败'
        resetMenuActions
        coreNotInstalledErrorCard
        assertMenuAction 'errorCard:未安装，请使用脚本安装'
        resetMenuActions
        coreDomainRequiredErrorCard
        assertMenuAction 'errorCard:域名不可为空'
        resetMenuActions
        coreIPRequiredErrorCard
        assertMenuAction 'errorCard:IP不可为空'
        resetMenuActions
        xrayConfigValidationFailureCard "已取消启动"
        assertMenuAction 'statusCard:Xray 配置校验失败'
        resetMenuActions
        xrayPrereleaseCompatibilityCard "通过"
        assertMenuAction 'statusCard:Xray 预发布兼容检查'
        resetMenuActions
        singBoxPrereleaseCompatibilityCard "通过"
        assertMenuAction 'statusCard:sing-box 预发布兼容检查'
        resetMenuActions
        xrayConfigValidationCard "通过"
        assertMenuAction 'statusCard:Xray 配置校验'
        resetMenuActions
        singBoxConfigValidationCard "通过"
        assertMenuAction 'statusCard:sing-box 配置校验'
        resetMenuActions
        skipTlsCertificateStatusCard "检测到宝塔面板/1Panel"
        assertMenuAction 'statusCard:跳过 TLS 证书'
        resetMenuActions
        protocolPortInputStatusCard "端口不合法"
        assertMenuAction 'statusCard:端口输入'
        resetMenuActions
        protocolPortHoppingRangeStatusCard "范围不合法"
        assertMenuAction 'statusCard:端口跳跃范围'
        resetMenuActions
        protocolPortHoppingStatusCard "删除成功"
        assertMenuAction 'statusCard:端口跳跃'
        resetMenuActions
        tuicAlgorithmStatusCard "cubic"
        assertMenuAction 'statusCard:Tuic 算法'
        resetMenuActions
        tlsCertificateCard "重新生成证书"
        assertMenuAction 'statusCard:TLS 证书'
        resetMenuActions
        tlsCertificateStatusCard "未检测到本机 TLS 证书"
        assertMenuAction 'statusCard:TLS 证书状态'
        resetMenuActions
    fi
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
    testSubscriptionWireGuardControl() { recordMenuAction testSubscriptionWireGuardControl; }
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
    toggleSubscriptionSourceMenu() {
        subscriptionRequireMainRole || return 1
        recordMenuAction toggleSubscriptionSourceMenu
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
    toggleSubscriptionEventSyncEnabled() { recordMenuAction toggleSubscriptionEventSyncEnabled; }
    subscriptionGroupSyncCronStatus() { recordMenuAction subscriptionGroupSyncCronStatus; }
    installUserCrontabContent() { return 0; }
    xrayInstalled() { return 0; }
    singBoxInstalled() { return 0; }
    getSingBoxCurrentVersion() { printf 'v1.0.0\n'; }
    xrayRunning() { return 0; }
    singBoxRunning() { return 1; }
    validateXrayConfigWithBinary() { return 0; }
    singBoxConfigInstalled() { return 1; }
    crontab() { return 1; }
    coreReleaseTags() { recordMenuAction "unexpected-network-version-fetch"; printf 'v1.2.3\n'; }
    downloadXrayReleaseBinaryToTemp() {
        local version=$1
        local outVar=$2
        local tmpDirVar=${3:-}
        local releaseDir="${TMP_DIR}/menu-smoke-xray-release-${version#v}"
        mkdir -p "${releaseDir}" || return 1
        printf '#!/usr/bin/env bash\nexit 0\n' >"${releaseDir}/xray"
        chmod +x "${releaseDir}/xray"
        printf -v "${outVar}" '%s' "${releaseDir}/xray"
        if [[ -n "${tmpDirVar}" ]]; then
            printf -v "${tmpDirVar}" '%s' "${releaseDir}"
        fi
    }
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
    printf 'geoip' >"${geoOverviewDir}/geoip.dat"
    printf 'geosite' >"${geoOverviewDir}/geosite.dat"
    printf 'v20260513' >"${geoOverviewDir}/geo.version"
    local output=
    if menuSmokePartSelected core; then
        PADM_XRAY_DIR="${geoOverviewDir}" PADM_XRAY_BINARY="${geoOverviewDir}/xray" PADM_SINGBOX_BINARY="${geoOverviewDir}/missing-sing-box" showCoreStatusOverview
        [[ "${output}" == *"Xray Geo:"*"版本 v20260513"* ]]
        customSingBoxInstall() { recordMenuAction "customSingBoxInstall:$*"; }
        installMenu <<<"7"
        assertMenuAction menu
        resetMenuActions
        installMenu <<<"4"
        assertMenuAction "customSingBoxInstall:5"
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
    fi

    if menuSmokePartSelected subscription-main-entry; then
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
    fi

    if menuSmokePartSelected subscription-main-publish-service; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
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
    fi

    if menuSmokePartSelected subscription-main-publish-user || menuSmokePartSelected subscription-main-publish-user-empty; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        resetMenuActions
        manageSubscriptionPublishSubscriptions <<<"4
7" || true
        subscriptionGroupsStateRead -e '.groups[] | select(.id == "default") | ((.user_groups // []) | length) == 0' >/dev/null
    fi

    if menuSmokePartSelected subscription-main-publish-user || menuSmokePartSelected subscription-main-publish-user-create; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        resetMenuActions
        manageSubscriptionPublishSubscriptions <<<"3
demo-user
Demo User
main
0
7"
        subscriptionGroupsStateRead -e '.groups[] | select(.id == "default") | any(.user_groups[]?; .id == "demo-user" and .name == "Demo User")' >/dev/null
    fi

    if menuSmokePartSelected subscription-main-publish-user || menuSmokePartSelected subscription-main-publish-user-inspect; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        if [[ "${menuSmokePart}" == "subscription-main-publish-user-inspect" ]]; then
            manageSubscriptionPublishSubscriptions <<<"3
demo-user
Demo User
main
0
7"
        fi
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
    fi

    if menuSmokePartSelected subscription-main-publish-sync || menuSmokePartSelected subscription-main-publish-sync-skip; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
        resetMenuActions
        subscriptionGroupsStateWrite --arg groupId "default" '.groups |= map(if .id == $groupId then .sync.enabled = false else . end)'
        manageSubscriptionPublishSubscriptions <<<"3
team-a
Team A
*
0
n
7"
        subscriptionGroupsStateRead -e '.groups[] | select(.id == "default") | any(.user_groups[]?; .id == "team-a" and .name == "Team A")' >/dev/null
        subscriptionGroupsStateRead -e '.groups[] | select(.id == "default") | .sync.enabled == false' >/dev/null
        assertMenuAction 'runSubscriptionGroupSync:skip-subscribe-refresh'
    fi

    if menuSmokePartSelected subscription-main-publish-sync || menuSmokePartSelected subscription-main-publish-sync-enable; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
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
    fi

    if menuSmokePartSelected subscription-main-maintenance; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
        setMenuSmokeRole main
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
12
9"
        grep -q "开启/关闭自动同步" <<<"${output}"
        grep -q "开启/关闭事件同步" <<<"${output}"
        grep -q "查看定时任务" <<<"${output}"
        resetMenuActions
        manageSubscriptionSyncSettings <<<"5
12"
        assertMenuAction 'runSubscriptionGroupSync:skip-subscribe-refresh'
        if assertMenuAction 'runSubscriptionGroupSync:'; then
            printf 'menu-smoke failed: sync settings immediate sync still triggers publish refresh path\n' >&2
            return 1
        fi
        resetMenuActions
        manageSubscriptionSyncSettings <<<"10
12"
        assertMenuAction toggleSubscriptionEventSyncEnabled
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
    fi

    if menuSmokePartSelected subscription-controlled; then
        configPath="${TMP_DIR}/menu-smoke-xray/"
        coreInstallType=1
        ensureSubscriptionGroupsState
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
        toggleSubscriptionSourceMenu <<<"" || true
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
        manageSubscriptionSyncSettings <<<"12" || true
        assertMenuAction 'errorCard:当前机器已初始化为被控'
        resetMenuActions
        setMenuSmokeRole uninitialized
        manageTrafficAndQuota <<<"8" || true
        assertMenuAction 'errorCard:当前机器还没完成角色初始化'
        resetMenuActions
        manageSubscriptionStateBackups <<<"6" || true
        assertMenuAction 'errorCard:当前机器还没完成角色初始化'
        resetMenuActions
        manageSubscriptionSyncSettings <<<"12" || true
        assertMenuAction 'errorCard:当前机器还没完成角色初始化'
    fi

    if menuSmokePartSelected core-maintenance; then
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
    fi

    configPath="${oldConfigPath}"
    coreInstallType="${oldCoreInstallType}"
    if [[ -n "${oldRealityPageSize}" ]]; then
        REALITY_TARGET_PAGE_SIZE="${oldRealityPageSize}"
    else
        unset REALITY_TARGET_PAGE_SIZE
    fi
}

runMenuSmokeFullCoreRegression() {
    runMenuSmokeRegression core
}

runMenuSmokeFullSubscriptionMainEntryRegression() {
    runMenuSmokeRegression subscription-main-entry
}

runMenuSmokeFullSubscriptionMainPublishServiceRegression() {
    runMenuSmokeRegression subscription-main-publish-service
}

runMenuSmokeFullSubscriptionMainPublishUserEmptyRegression() {
    runMenuSmokeRegression subscription-main-publish-user-empty
}

runMenuSmokeFullSubscriptionMainPublishUserCreateRegression() {
    runMenuSmokeRegression subscription-main-publish-user-create
}

runMenuSmokeFullSubscriptionMainPublishUserInspectRegression() {
    runMenuSmokeRegression subscription-main-publish-user-inspect
}

runMenuSmokeFullSubscriptionMainPublishSyncSkipRegression() {
    runMenuSmokeRegression subscription-main-publish-sync-skip
}

runMenuSmokeFullSubscriptionMainPublishSyncEnableRegression() {
    runMenuSmokeRegression subscription-main-publish-sync-enable
}

runMenuSmokeFullSubscriptionMainMaintenanceRegression() {
    runMenuSmokeRegression subscription-main-maintenance
}

runMenuSmokeFullSubscriptionControlledRegression() {
    runMenuSmokeRegression subscription-controlled
}

runMenuSmokeFullCoreMaintenanceRegression() {
    runMenuSmokeRegression core-maintenance
}

runInstallToolsCertificateDependencyRegression() {
    local oldHome="${HOME}"
    local oldSelect="${selectCustomInstallType:-}"
    local oldRealityDomain="${realityOnlyWithDomain:-}"
    local statusLog="${TMP_DIR}/install-tools-cert-status.log"
    local fakeHome="${TMP_DIR}/install-tools-cert-home"
    local oldStatusLog="${REGRESSION_STATUS_CARD_LOG:-}"
    local oldSuccessLog="${REGRESSION_SUCCESS_CARD_LOG:-}"
    local oldInstallLog="${PADM_INSTALL_LOG:-}"
    local nginxCommandLog="${TMP_DIR}/install-tools-nginx-command.log"
    mkdir -p "${fakeHome}/.acme.sh"
    printf '#!/usr/bin/env sh\n' >"${fakeHome}/.acme.sh/acme.sh"
    HOME="${fakeHome}"
    export REGRESSION_STATUS_CARD_LOG="${statusLog}"
    export REGRESSION_SUCCESS_CARD_LOG="${statusLog}"
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

    : >"${nginxCommandLog}"
    protocolSelectionSkipsNginx() { return 1; }
    nginx() {
        printf '%s\n' "$*" >>"${nginxCommandLog}"
        [[ "${1:-}" == "-v" ]] || return 1
        printf 'nginx version: nginx/1.26.0\n' >&2
    }
    installTools 1
    [[ -s "${nginxCommandLog}" ]]
    ! grep -vx -- '-v' "${nginxCommandLog}"
    ! grep -q 'unexpected-nginx' "${statusLog}"

    if [[ -n "${oldStatusLog}" ]]; then
        REGRESSION_STATUS_CARD_LOG="${oldStatusLog}"
    else
        unset REGRESSION_STATUS_CARD_LOG
    fi
    if [[ -n "${oldSuccessLog}" ]]; then
        REGRESSION_SUCCESS_CARD_LOG="${oldSuccessLog}"
    else
        unset REGRESSION_SUCCESS_CARD_LOG
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
        local acmeRunCommandLog="${TMP_DIR}/install-tools-acme-result-command.log"
        local installStatus

        rm -rf "${fakeHome}" "${tmpRoot}"
        rm -f "${acmeRunCommandLog}"
        mkdir -p "${fakeHome}" "${tmpRoot}"
        mkdir -p "${fakeHome}/.acme.sh"
        printf 'legacy-state\n' >"${fakeHome}/.acme.sh/account.conf"
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
        runWithTimeout() {
            if [[ "${2:-}" == *"acme.sh"* ]]; then
                printf '%s\n' "${2:-}" >"${acmeRunCommandLog}"
                mkdir -p "${fakeHome}/.acme.sh"
                printf 'partial-install\n' >"${fakeHome}/.acme.sh/partial.txt"
            fi
            return 0
        }
        runPackageCommandWithProgress() { return 0; }
        waitAptProcess() { return 0; }
        installBasePackages() { return 0; }
        installNginxTools() { return 0; }
        nginx() { return 0; }
        protocolSelectionSkipsNginx() { return 0; }
        protocolSelectionNeedsLocalCertificate() { return 0; }
        resolveGitHubCommitRef() { [[ "$1" == "acmesh-official/acme.sh" && "$2" == "master" ]] && printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'; }
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
        [[ -s "${acmeRunCommandLog}" ]]
        grep -q -- '--install' "${acmeRunCommandLog}"
        ! grep -qF "${tmpRoot}/padm-tls/acme.sh" "${acmeRunCommandLog}"
        grep -Eq "${tmpRoot}/padm-tls\\.[^/]+/acme\\.sh" "${acmeRunCommandLog}"
        [[ ! -d "${tmpRoot}/padm-tls" ]]
        [[ ! -e "${fakeHome}/.acme.sh/acme.sh" ]]
        [[ "$(<"${fakeHome}/.acme.sh/account.conf")" == "legacy-state" ]]
        [[ ! -e "${fakeHome}/.acme.sh/partial.txt" ]]
        if regressionFindHasMatches "${tmpRoot}" -maxdepth 1 -type d -name 'padm-package-managed-backup.*'; then
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
        unset -f command runWithTimeout runPackageCommandWithProgress waitAptProcess installBasePackages installNginxTools nginx protocolSelectionSkipsNginx protocolSelectionNeedsLocalCertificate resolveGitHubCommitRef curl tail
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
        runWithTimeout() {
            if [[ "${2:-}" == *"acme.sh"* ]]; then
                : >"${runMarker}"
            fi
            return 0
        }
        runPackageCommandWithProgress() { return 0; }
        waitAptProcess() { return 0; }
        installBasePackages() { return 0; }
        installNginxTools() { return 0; }
        nginx() { return 0; }
        protocolSelectionSkipsNginx() { return 0; }
        protocolSelectionNeedsLocalCertificate() { return 0; }
        resolveGitHubCommitRef() { [[ "$1" == "acmesh-official/acme.sh" && "$2" == "master" ]] && printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'; }
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
        [[ ! -d "${tmpRoot}/padm-tls" ]]
        if regressionFindHasMatches "${tmpRoot}" -type f -name 'acme.sh.download.*'; then
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
        unset -f command runWithTimeout runPackageCommandWithProgress waitAptProcess installBasePackages installNginxTools nginx protocolSelectionSkipsNginx protocolSelectionNeedsLocalCertificate resolveGitHubCommitRef curl mv
    )
}

runInstallToolsAcmeDownloadBoundsRegression() {
    (
        local oldHome="${HOME}"
        local oldSelect="${selectCustomInstallType:-}"
        local oldTmpDir="${TMPDIR:-}"
        local oldInstallLog="${PADM_INSTALL_LOG:-}"
        local fakeHome="${TMP_DIR}/install-tools-acme-download-bounds-home"
        local tmpRoot="${TMP_DIR}/install-tools-acme-download-bounds-tmp"
        local curlLog="${TMP_DIR}/install-tools-acme-download-bounds-curl.log"

        rm -rf "${fakeHome}" "${tmpRoot}"
        rm -f "${curlLog}"
        mkdir -p "${fakeHome}" "${tmpRoot}"
        HOME="${fakeHome}"
        TMPDIR="${tmpRoot}"
        release=debian
        rhelLike=false
        upgrade=true
        updateReleaseInfoChange=true
        packageManager=apt
        installType=true
        removeType=true
        PADM_INSTALL_LOG="${TMP_DIR}/install-tools-acme-download-bounds-install.log"
        selectCustomInstallType=",7,"
        command() {
            if [[ "$1" == "-v" && "$2" == "qrencode" ]]; then
                return 0
            fi
            builtin command "$@"
        }
        runWithTimeout() {
            if [[ "${2:-}" == *"acme.sh"* ]]; then
                mkdir -p "${fakeHome}/.acme.sh"
                printf '#!/usr/bin/env sh\n' >"${fakeHome}/.acme.sh/acme.sh"
            fi
            return 0
        }
        runPackageCommandWithProgress() { return 0; }
        waitAptProcess() { return 0; }
        installBasePackages() { return 0; }
        installNginxTools() { return 0; }
        nginx() { return 0; }
        protocolSelectionSkipsNginx() { return 0; }
        protocolSelectionNeedsLocalCertificate() { return 0; }
        resolveGitHubCommitRef() { [[ "$1" == "acmesh-official/acme.sh" && "$2" == "master" ]] && printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'; }
        curl() {
            local outputFile=
            printf '%s\n' "$*" >"${curlLog}"
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -o) outputFile=$2; shift 2 ;;
                *) shift ;;
                esac
            done
            [[ -n "${outputFile}" ]] || return 1
            printf '#!/usr/bin/env sh\nexit 0\n' >"${outputFile}"
        }

        installTools 1 >/dev/null 2>&1
        grep -q -- '--connect-timeout 10' "${curlLog}"
        grep -q -- '--max-time 120' "${curlLog}"
        grep -q -- '--max-filesize 1048576' "${curlLog}"
        grep -q 'raw.githubusercontent.com/acmesh-official/acme.sh/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/acme.sh' "${curlLog}"

        if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
        if [[ -n "${oldInstallLog}" ]]; then PADM_INSTALL_LOG="${oldInstallLog}"; else unset PADM_INSTALL_LOG; fi
        HOME="${oldHome}"
        selectCustomInstallType="${oldSelect}"
        unset -f command runWithTimeout runPackageCommandWithProgress waitAptProcess installBasePackages installNginxTools nginx protocolSelectionSkipsNginx protocolSelectionNeedsLocalCertificate resolveGitHubCommitRef curl
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

runInstallToolsUsesConfiguredInstallLogRegression() {
    (
        local oldHome="${HOME}"
        local oldSelect="${selectCustomInstallType:-}"
        local oldInstallLog="${PADM_INSTALL_LOG:-}"
        local oldStatusLog="${REGRESSION_STATUS_CARD_LOG:-}"
        local oldErrorLog="${REGRESSION_ERROR_CARD_LOG:-}"
        local oldBasePackageCalledFile="${PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE:-}"
        local fakeHome="${TMP_DIR}/install-tools-log-home"
        local logRoot="${TMP_DIR}/custom-log"
        local callLog="${TMP_DIR}/install-tools-log-calls.log"
        local statusLog="${TMP_DIR}/install-tools-log-status.log"
        local errorLog="${TMP_DIR}/install-tools-log-error.log"
        local installStatus
        local resolvedInstallLog

        rm -rf "${fakeHome}" "${logRoot}"
        mkdir -p "${fakeHome}"
        : >"${callLog}"
        : >"${statusLog}"
        : >"${errorLog}"
        HOME="${fakeHome}"
        PADM_INSTALL_LOG="${logRoot}/install.log"
        resolvedInstallLog=$(padmResolveManagedAbsolutePath "${PADM_INSTALL_LOG}")
        export REGRESSION_STATUS_CARD_LOG="${statusLog}"
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE=
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
        waitAptProcess() { return 0; }
        packageInstalled() { return 1; }
        installBasePackages() { installPackageTracked "基础工具" curl; }
        installNginxTools() { return 0; }
        nginx() { return 0; }
        protocolSelectionSkipsNginx() { return 0; }
        protocolSelectionNeedsLocalCertificate() { return 1; }
        runPackageCommandWithProgress() {
            printf '%s|%s\n' "$1" "$4" >>"${callLog}"
            return 0
        }

        set +e
        (
            installTools 1
        ) >/dev/null 2>&1
        installStatus=$?
        set -e
        [[ "${installStatus}" == "0" ]]
        [[ -f "${resolvedInstallLog}" ]]
        [[ "$(grep -cF "|${resolvedInstallLog}" "${callLog}")" == "2" ]]
        grep -q "^检查、安装更新|${resolvedInstallLog}\$" "${callLog}"
        grep -q "^安装基础工具|${resolvedInstallLog}\$" "${callLog}"

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
        if [[ -n "${oldBasePackageCalledFile}" ]]; then
            PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE="${oldBasePackageCalledFile}"
        else
            unset PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE
        fi
        HOME="${oldHome}"
        selectCustomInstallType="${oldSelect}"
        unset -f command runWithTimeout waitAptProcess packageInstalled installBasePackages installNginxTools nginx protocolSelectionSkipsNginx protocolSelectionNeedsLocalCertificate runPackageCommandWithProgress
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
        local keyRootRel="${TMP_DIR}/apt-key-commit-failure"
        local keyRoot keyringFile
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
            [[ "${1:-}" == "--dearmor" ]] || return 1
            cat
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
        grep -q "测试源 apt key 下载失败" "${errorLog}"
        grep -q "https://example.invalid/key.gpg" "${curlCalls}"
        grep -q -- '--connect-timeout 10 --max-time 120 --max-filesize 1048576' "${curlCalls}"
        ! compgen -G "${TMP_DIR}/.missing-keyring.gpg.aptkey.*" >/dev/null

        mkdir -p "${keyRootRel}"
        keyRoot=$(cd -- "${keyRootRel}" && pwd -P)
        keyringFile="${keyRoot}/existing-keyring.gpg"
        printf 'old-keyring\n' >"${keyringFile}"
        : >"${errorLog}"
        curl() {
            local outputFile=
            while [[ $# -gt 0 ]]; do
                if [[ "$1" == "-o" ]]; then
                    outputFile=$2
                    break
                fi
                shift
            done
            [[ -n "${outputFile}" ]] || return 1
            printf 'new-keyring\n' >"${outputFile}"
        }
        sha256sum() {
            printf '%064d  %s\n' 0 "$1"
        }

        set +e
        (
            installAptKeyringFromUrl https://nginx.org/keys/nginx_signing.key "${keyringFile}" Nginx "${PADM_NGINX_SIGNING_KEY_SHA256}"
        ) >/dev/null 2>&1
        keyStatus=$?
        set -e
        [[ "${keyStatus}" -ne 0 ]]
        [[ "$(<"${keyringFile}")" == "old-keyring" ]]
        grep -q "Nginx apt key sha256 校验失败" "${errorLog}"
        ! compgen -G "${keyRoot}/.existing-keyring.gpg.aptkey.*" >/dev/null

        : >"${errorLog}"
        eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
        commitGeneratedFile() {
            if [[ "$2" == "${keyringFile}" ]]; then
                return 1
            fi
            originalCommitGeneratedFile "$@"
        }

        set +e
        (
            installAptKeyringFromUrl https://example.invalid/key.gpg "${keyringFile}" "测试源"
        ) >/dev/null 2>&1
        keyStatus=$?
        set -e
        [[ "${keyStatus}" -ne 0 ]]
        [[ "$(<"${keyringFile}")" == "old-keyring" ]]
        grep -q "测试源 apt key 提交失败" "${errorLog}"
        ! compgen -G "${keyRoot}/.existing-keyring.gpg.aptkey.*" >/dev/null

        if [[ -n "${oldErrorLog}" ]]; then
            REGRESSION_ERROR_CARD_LOG="${oldErrorLog}"
        else
            unset REGRESSION_ERROR_CARD_LOG
        fi
        unset -f curl gpg sudo sha256sum commitGeneratedFile
    )
}

runNginxAptRepoRefreshRollbackRegression() {
    (
        local oldErrorLog="${REGRESSION_ERROR_CARD_LOG:-}"
        local errorLog="${TMP_DIR}/nginx-apt-refresh-error.log"
        local rootRel="${TMP_DIR}/nginx-apt-refresh-rollback"
        local root repoRoot keyringRoot curlCalls
        local keyringFile repoFile pinFile
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        : >"${errorLog}"
        curlCalls="${TMP_DIR}/nginx-apt-refresh-curl-calls.log"
        : >"${curlCalls}"
        mkdir -p "${rootRel}"
        root=$(cd -- "${rootRel}" && pwd -P)
        repoRoot="${root}/apt"
        keyringRoot="${root}/keyrings"
        keyringFile="${keyringRoot}/nginx-archive-keyring.gpg"
        repoFile="${repoRoot}/sources.list.d/nginx.list"
        pinFile="${repoRoot}/preferences.d/99nginx"
        mkdir -p "$(dirname "${repoFile}")" "$(dirname "${pinFile}")" "${keyringRoot}"
        printf 'old-key\n' >"${keyringFile}"
        printf 'old-repo\n' >"${repoFile}"
        printf 'old-pin\n' >"${pinFile}"
        release=debian
        packageManager=apt
        removeType=true
        PADM_NGINX_APT_KEYRING_FILE="${keyringFile}"
        PADM_NGINX_APT_REPO_FILE="${repoFile}"
        PADM_NGINX_APT_PIN_FILE="${pinFile}"
        installPackageTracked() { return 0; }
        nginxServiceInstalled() { return 0; }
        bootStartup() { return 0; }
        lsb_release() { [[ "$1" == "-cs" ]] && printf 'bookworm\n'; }
        curl() {
            local url=${!#}
            local outputFile=
            printf '%s\n' "$*" >>"${curlCalls}"
            case "${url}" in
            https://nginx.org/packages/mainline/debian/dists/bookworm/Release)
                return 0
                ;;
            https://nginx.org/keys/nginx_signing.key)
                while [[ $# -gt 0 ]]; do
                    if [[ "$1" == "-o" ]]; then
                        outputFile=$2
                        break
                    fi
                    shift
                done
                [[ -n "${outputFile}" ]] || return 1
                printf 'new-key\n' >"${outputFile}"
                return 0
                ;;
            *)
                return 1
                ;;
            esac
        }
        gpg() {
            [[ "${1:-}" == "--dearmor" ]] || return 1
            cat
        }
        sha256sum() { printf '%s  %s\n' "${PADM_NGINX_SIGNING_KEY_SHA256}" "$1"; }
        refreshAptAfterRepoChange() { return 1; }

        set +e
        (
            installNginxTools
        ) >/dev/null 2>&1
        local nginxStatus=$?
        set -e
        [[ "${nginxStatus}" -ne 0 ]]
        [[ "$(<"${keyringFile}")" == "old-key" ]]
        [[ "$(<"${repoFile}")" == "old-repo" ]]
        [[ "$(<"${pinFile}")" == "old-pin" ]]
        grep -q "Nginx apt 源刷新失败" "${errorLog}"
        grep -q -- '--connect-timeout 10 --max-time 30 --max-filesize 1048576 https://nginx.org/packages/mainline/debian/dists/bookworm/Release' "${curlCalls}"
        ! compgen -G "${keyringRoot}/.nginx-archive-keyring.gpg.aptkey.*" >/dev/null
        if regressionFindHasMatches "${root}" -type d -name 'padm-package-managed-backup.*'; then
            return 1
        fi

        if [[ -n "${oldErrorLog}" ]]; then
            REGRESSION_ERROR_CARD_LOG="${oldErrorLog}"
        else
            unset REGRESSION_ERROR_CARD_LOG
        fi
        unset PADM_NGINX_APT_KEYRING_FILE PADM_NGINX_APT_REPO_FILE PADM_NGINX_APT_PIN_FILE
        unset -f installPackageTracked nginxServiceInstalled bootStartup lsb_release curl gpg sha256sum refreshAptAfterRepoChange
    )
}

runNginxYumMainlineEnableFailureRegression() {
    (
        local oldErrorLog="${REGRESSION_ERROR_CARD_LOG:-}"
        local errorLog="${TMP_DIR}/nginx-yum-mainline-error.log"
        local rootRel="${TMP_DIR}/nginx-yum-mainline-rollback"
        local root repoDir rpmKeyFile
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        : >"${errorLog}"
        mkdir -p "${rootRel}"
        root=$(cd -- "${rootRel}" && pwd -P)
        repoDir="${root}/repos"
        rpmKeyFile="${root}/rpm-gpg/RPM-GPG-KEY-nginx"
        mkdir -p "${repoDir}"
        mkdir -p "$(dirname "${rpmKeyFile}")"
        printf 'old-yum-repo\n' >"${repoDir}/nginx.repo"
        printf 'old-rpm-key\n' >"${rpmKeyFile}"
        release=centos
        packageManager=yum
        removeType=true
        PADM_YUM_REPOS_DIR="${repoDir}"
        PADM_NGINX_RPM_KEY_FILE="${rpmKeyFile}"
        installPackageTracked() { return 0; }
        packageInstalled() { return 0; }
        nginxServiceInstalled() { return 0; }
        bootStartup() { return 0; }
        downloadUrlToFileBounded() { printf 'new-rpm-key\n' >"$2"; }
        sha256sum() { printf '%s  %s\n' "${PADM_NGINX_SIGNING_KEY_SHA256}" "$1"; }
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
        [[ "$(<"${repoDir}/nginx.repo")" == "old-yum-repo" ]]
        [[ "$(<"${rpmKeyFile}")" == "old-rpm-key" ]]
        if regressionFindHasMatches "${root}" -type d -name 'padm-package-managed-backup.*'; then
            return 1
        fi

        if [[ -n "${oldErrorLog}" ]]; then
            REGRESSION_ERROR_CARD_LOG="${oldErrorLog}"
        else
            unset REGRESSION_ERROR_CARD_LOG
        fi
        unset -f installPackageTracked packageInstalled nginxServiceInstalled bootStartup downloadUrlToFileBounded sha256sum sudo
        unset PADM_YUM_REPOS_DIR PADM_NGINX_RPM_KEY_FILE
    )
}

runNginxAlpineDefaultConfRollbackRegression() {
    (
        local oldErrorLog="${REGRESSION_ERROR_CARD_LOG:-}"
        local errorLog="${TMP_DIR}/nginx-alpine-default-conf-error.log"
        local rootRel="${TMP_DIR}/nginx-alpine-default-conf-rollback"
        local root defaultConf
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        : >"${errorLog}"
        mkdir -p "${rootRel}"
        root=$(cd -- "${rootRel}" && pwd -P)
        defaultConf="${root}/nginx/default.conf"
        mkdir -p "$(dirname "${defaultConf}")"
        printf 'old-default-conf\n' >"${defaultConf}"
        release=alpine
        packageManager=apk
        removeType=true
        nginxConfigFilePath() {
            [[ "$1" == "default.conf" ]] && printf '%s\n' "${defaultConf}"
        }
        installPackageTracked() { return 0; }
        nginxServiceInstalled() { return 0; }
        bootStartup() { return 1; }

        set +e
        (
            installNginxTools
        ) >/dev/null 2>&1
        local nginxStatus=$?
        set -e
        [[ "${nginxStatus}" -ne 0 ]]
        [[ "$(<"${defaultConf}")" == "old-default-conf" ]]
        grep -q "Nginx开机自启配置失败" "${errorLog}"
        if regressionFindHasMatches "${root}" -type d -name 'padm-package-managed-backup.*'; then
            return 1
        fi

        if [[ -n "${oldErrorLog}" ]]; then
            REGRESSION_ERROR_CARD_LOG="${oldErrorLog}"
        else
            unset REGRESSION_ERROR_CARD_LOG
        fi
        unset -f nginxConfigFilePath installPackageTracked nginxServiceInstalled bootStartup
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
        local errorLog="${TMP_DIR}/package-rollback-error.log"
        local helperLog="${TMP_DIR}/package-rollback-helper.log"
        local oldInstalled="${PADM_INSTALLED_PACKAGES:-}"
        local oldFailures="${PADM_PACKAGE_ROLLBACK_FAILURES:-}"
        local oldManagedFailures="${PADM_PACKAGE_MANAGED_ROLLBACK_FAILURES:-}"
        local oldRemoveType="${removeType:-}"
        local rc

        removePackageForRegression() {
            printf '%s\n' "$1" >>"${removedFile}"
            [[ "$1" != "bad-package" ]]
        }
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        coreSetManualCheckMessage() {
            printf "manual-check:%s|%s\n" "$2" "$3" >>"${helperLog}"
            printf -v "$1" "%s，请手动检查%s" "$2" "$3"
        }

        removeType=removePackageForRegression
        PADM_INSTALLED_PACKAGES="ok-package bad-package"
        : >"${errorLog}"
        : >"${helperLog}"
        if rollbackPackageInstallTransaction; then
            return 1
        fi
        grep -qxF "ok-package" "${removedFile}"
        grep -qxF "bad-package" "${removedFile}"
        [[ "${PADM_INSTALLED_PACKAGES}" == "" ]]
        [[ "${PADM_PACKAGE_ROLLBACK_FAILURES}" == "bad-package" ]]

        PADM_INSTALLED_PACKAGES="ok-package bad-package"
        PADM_PACKAGE_MANAGED_ROLLBACK_DIRS=()
        : >"${errorLog}"
        : >"${helperLog}"
        set +e
        (
            failPackageInstallTransaction "软件包安装失败" >/dev/null 2>&1
        )
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -q 'manual-check:回滚部分软件包失败|bad-package' "${helperLog}"
        grep -q '回滚部分软件包失败，请手动检查bad-package' "${errorLog}"

        adapterRollbackPackageManagedFiles() { return 0; }
        rollbackPackageInstallTransaction() {
            PADM_PACKAGE_ROLLBACK_FAILURES='bad-package'
            return 1
        }
        PADM_PACKAGE_MANAGED_ROLLBACK_DIRS=('/tmp/repo-backup')
        : >"${errorLog}"
        : >"${helperLog}"
        set +e
        (
            failPackageInstallTransaction "软件包安装失败" >/dev/null 2>&1
        )
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -q 'manual-check:已尝试回滚系统源改动，但部分软件包回滚失败|bad-package' "${helperLog}"
        grep -q '已尝试回滚系统源改动，但部分软件包回滚失败，请手动检查bad-package' "${errorLog}"

        adapterRollbackPackageManagedFiles() { return 1; }
        rollbackPackageInstallTransaction() { return 0; }
        PADM_PACKAGE_MANAGED_ROLLBACK_DIRS=('/tmp/repo-backup')
        PADM_PACKAGE_MANAGED_ROLLBACK_FAILURES='repo-backup-a repo-backup-b'
        : >"${errorLog}"
        : >"${helperLog}"
        set +e
        (
            failPackageInstallTransaction "系统软件源刷新失败" >/dev/null 2>&1
        )
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -q 'manual-check:已回滚本次新增软件包，但系统源改动恢复失败|repo-backup-a repo-backup-b' "${helperLog}"
        grep -q '已回滚本次新增软件包，但系统源改动恢复失败，请手动检查repo-backup-a repo-backup-b' "${errorLog}"

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
        if [[ -n "${oldManagedFailures}" ]]; then
            PADM_PACKAGE_MANAGED_ROLLBACK_FAILURES="${oldManagedFailures}"
        else
            unset PADM_PACKAGE_MANAGED_ROLLBACK_FAILURES
        fi
        removeType="${oldRemoveType}"
        unset -f removePackageForRegression
        unset -f adapterRollbackPackageManagedFiles
        unset -f errorCard
        unset -f coreSetManualCheckMessage
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
    local scannerDirRel="${TMP_DIR}/scanner-bin"
    local scannerDir=
    local scannerBin=
    local capturedRepo= capturedVersion= capturedAsset= capturedDir=

    mkdir -p "${scannerDirRel}"
    scannerDir="$(cd -- "${scannerDirRel}" && pwd -P)"
    scannerBin="${scannerDir}/RealiTLScanner"

    rm() {
        if [[ "$#" -eq 2 && "$1" == "-rf" && "$2" == "${scannerDir}" ]]; then
            return 0
        fi
        command rm "$@"
    }
    mkdir() {
        if [[ "$#" -eq 2 && "$1" == "-p" && "$2" == "${scannerDir}" ]]; then
            return 0
        fi
        command mkdir "$@"
    }
    downloadGitHubReleaseAsset() {
        capturedDir=$2
        capturedRepo=$3
        capturedVersion=$4
        capturedAsset=$5
        printf '#!/usr/bin/env bash\n' >"${capturedDir}/${capturedAsset}"
        return 0
    }
    ensureRealityScannerBinary "${scannerDir}" "${scannerBin}"
    [[ -x "${scannerBin}" ]]
    [[ "${capturedRepo}" == "XTLS/RealiTLScanner" ]]
    [[ "${capturedVersion}" == "latest" ]]
    [[ "${capturedAsset}" == "RealiTLScanner-linux-amd64" ]]
    unset -f rm mkdir downloadGitHubReleaseAsset
}

runRealityScannerDownloadFailureKeepsExistingDirRegression() {
    local root="${TMP_DIR}/scanner-download-failure"
    local scannerDir="${root}/scanner"
    local scannerBin="${scannerDir}/RealiTLScanner"
    local rmLog="${root}/rm.log"
    local rc

    padmIsSafeAbsolutePath() { return 0; }
    mkdir -p "${scannerDir}"
    printf 'keep\n' >"${scannerDir}/sentinel"
    : >"${rmLog}"

    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }
    downloadGitHubReleaseAsset() { return 1; }
    set +e
    ensureRealityScannerBinary "${scannerDir}" "${scannerBin}" >/dev/null 2>&1
    rc=$?
    set -e

    [[ "${rc}" == "1" ]]
    [[ "$(<"${scannerDir}/sentinel")" == "keep" ]]
    ! grep -qxF "rm:-rf ${scannerDir}" "${rmLog}"
    unset -f rm downloadGitHubReleaseAsset
}

runRealityScannerRejectsUnsafeDirRegression() (
    local rootRel="${TMP_DIR}/scanner-unsafe-dir"
    local root rmLog
    local rc

    mkdir -p "${rootRel}/relative-scanner"
    root=$(cd -- "${rootRel}" && pwd -P)
    rmLog="${root}/rm.log"
    printf 'keep\n' >"${root}/relative-scanner/sentinel"
    : >"${rmLog}"

    cd "${root}"
    realityScannerDir() { printf '%s\n' "relative-scanner"; }
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }
    curl() { return 1; }
    jq() { return 1; }

    set +e
    runRealityScannerRange "198.51.100.0/24" >/dev/null 2>&1
    rc=$?
    set -e

    [[ "${rc}" == "1" ]]
    [[ ! -s "${rmLog}" ]]
    [[ -d "${root}/relative-scanner" ]]
    [[ "$(<"${root}/relative-scanner/sentinel")" == "keep" ]]
)

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
    local restoreFailureDir restoreFailureErrorLog restoreFailureDownloadLog
    local replaceFailureDir replaceFailureErrorLog replaceFailureDownloadLog
    local stageFailureDir stageFailureErrorLog stageFailureDownloadLog
    successLog="${TMP_DIR}/update-padm-success.log"
    errorLog="${TMP_DIR}/update-padm-error.log"
    installDir="${TMP_DIR}/update-padm-install"
    updateTmpRoot="${TMP_DIR}/update-padm-tmp"
    downloadDirLog="${TMP_DIR}/update-padm-download-dirs.log"
    restoreFailureDir="${TMP_DIR}/update-padm-restore-failure"
    restoreFailureErrorLog="${TMP_DIR}/update-padm-restore-failure-error.log"
    restoreFailureDownloadLog="${TMP_DIR}/update-padm-restore-failure-download.log"
    replaceFailureDir="${TMP_DIR}/update-padm-replace-restore-failure"
    replaceFailureErrorLog="${TMP_DIR}/update-padm-replace-restore-failure-error.log"
    replaceFailureDownloadLog="${TMP_DIR}/update-padm-replace-restore-failure-download.log"
    stageFailureDir="${TMP_DIR}/update-padm-stage-failure"
    stageFailureErrorLog="${TMP_DIR}/update-padm-stage-failure-error.log"
    stageFailureDownloadLog="${TMP_DIR}/update-padm-stage-failure-download.log"
    oldTmpDir="${TMPDIR:-}"
    mkdir -p "${installDir}" "${updateTmpRoot}" "${restoreFailureDir}" "${replaceFailureDir}" "${stageFailureDir}"
    installDir=$(cd -- "${installDir}" && pwd -P)
    restoreFailureDir=$(cd -- "${restoreFailureDir}" && pwd -P)
    replaceFailureDir=$(cd -- "${replaceFailureDir}" && pwd -P)
    stageFailureDir=$(cd -- "${stageFailureDir}" && pwd -P)
    : >"${downloadDirLog}"
    : >"${successLog}"
    : >"${errorLog}"
    : >"${restoreFailureErrorLog}"
    : >"${restoreFailureDownloadLog}"
    : >"${replaceFailureErrorLog}"
    : >"${replaceFailureDownloadLog}"
    : >"${stageFailureErrorLog}"
    : >"${stageFailureDownloadLog}"
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
    grep -Eqx "${updateTmpRoot}/padm-update\\.[A-Za-z0-9][A-Za-z0-9]*/?" "${downloadDirLog}"
    if regressionFindHasMatches "${updateTmpRoot}" -mindepth 1 -maxdepth 1 -type d; then
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
    grep -Eqx "${updateTmpRoot}/padm-update\\.[A-Za-z0-9][A-Za-z0-9]*/?" "${downloadDirLog}"
    if regressionFindHasMatches "${updateTmpRoot}" -mindepth 1 -maxdepth 1 -type d; then
        return 1
    fi
    "${installDir}/install.sh" | grep -q 'old-entry'

    printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${restoreFailureDir}/install.sh"
    chmod 700 "${restoreFailureDir}/install.sh"
    (
        REGRESSION_ERROR_CARD_LOG="${restoreFailureErrorLog}"
        release=debian
        PADM_INSTALL_DIR="${restoreFailureDir}"

        downloadFile() {
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -P)
                    mkdir -p "$2"
                    printf '%s\n' "$2" >>"${restoreFailureDownloadLog}"
                    cat >"$2/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
printf 'new-entry\n'
exit 23
EOF
                    return 0
                    ;;
                esac
                shift
            done
            return 1
        }
        eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
        commitGeneratedFile() {
            if [[ "$1" == "${restoreFailureDir}/install.sh.bak" && "$2" == "${restoreFailureDir}/install.sh" ]]; then
                return 1
            fi
            originalCommitGeneratedFile "$@"
        }
        sudo() { "$@"; }

        updatePadm 1
    ) >"${TMP_DIR}/update-padm-restore-failure-run.log" 2>&1 && return 1
    grep -q "新版入口执行失败，旧入口恢复失败，请手动检查 ${restoreFailureDir}/install.sh 和 ${restoreFailureDir}/install.sh.bak" "${restoreFailureErrorLog}"
    grep -Eqx "${updateTmpRoot}/padm-update\\.[A-Za-z0-9][A-Za-z0-9]*/?" "${restoreFailureDownloadLog}"
    if regressionFindHasMatches "${updateTmpRoot}" -mindepth 1 -maxdepth 1 -type d; then
        return 1
    fi
    "${restoreFailureDir}/install.sh" | grep -q 'new-entry'
    "${restoreFailureDir}/install.sh.bak" | grep -q 'old-entry'

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
        eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
        commitGeneratedFile() {
            if [[ "$2" == "${replaceFailureDir}/install.sh" ]]; then
                return 1
            fi
            originalCommitGeneratedFile "$@"
        }

        updatePadm 1
    ) >"${TMP_DIR}/update-padm-replace-failure-run.log" 2>&1 && return 1
    grep -q '更新入口提交失败，已取消更新' "${replaceFailureErrorLog}"
    [[ ! -e "${replaceFailureDir}/install.sh.bak" ]]
    "${replaceFailureDir}/install.sh" | grep -q 'old-entry'
    ! compgen -G "${replaceFailureDir}/.install.sh.install.*" >/dev/null

    printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${stageFailureDir}/install.sh"
    chmod 700 "${stageFailureDir}/install.sh"
    (
        REGRESSION_ERROR_CARD_LOG="${stageFailureErrorLog}"
        release=debian
        PADM_INSTALL_DIR="${stageFailureDir}"

        downloadFile() {
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -P)
                    mkdir -p "$2"
                    printf '%s\n' "$2" >>"${stageFailureDownloadLog}"
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
        cp() {
            local targetPath="${@: -1}"
            case "${targetPath}" in
            "${stageFailureDir}"/.install.sh.install.*)
                return 1
                ;;
            esac
            command cp "$@"
        }

        updatePadm 1
    ) >"${TMP_DIR}/update-padm-stage-failure-run.log" 2>&1 && return 1
    grep -q '更新入口暂存失败，已取消更新' "${stageFailureErrorLog}"
    [[ ! -e "${stageFailureDir}/install.sh.bak" ]]
    "${stageFailureDir}/install.sh" | grep -q 'old-entry'
    ! compgen -G "${stageFailureDir}/.install.sh.install.*" >/dev/null
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
    mkdir -p "${fixtureDir}/shell" "${fixtureDir}/documents" "${fixtureDir}/assets" "${archiveRoot}/shell" "${archiveRoot}/documents" "${archiveRoot}/assets" "${refreshTmpRoot}"
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
        refreshScriptModules 7777777777777777777777777777777777777777
    ) >"${outputLog}" 2>&1
    grep -q '完整安装包替换失败，已恢复旧模块' "${outputLog}"
    [[ "$(<"${fixtureDir}/shell/marker")" == "old-shell" ]]
    [[ "$(<"${fixtureDir}/documents/marker")" == "old-doc" ]]
    [[ "$(<"${fixtureDir}/README.md")" == "old-readme" ]]
    [[ ! -e "${fixtureDir}/.padm-ref" ]]
    [[ ! -e "${fixtureDir}/.padm-update-backup" ]]
    if regressionFindHasMatches "${refreshTmpRoot}" -mindepth 1 -maxdepth 1 -type d; then
        return 1
    fi

    mkdir -p "${restoreFailureDir}/shell" "${restoreFailureDir}/documents" "${restoreFailureDir}/assets" "${restoreFailureArchiveRoot}/shell" "${restoreFailureArchiveRoot}/documents" "${restoreFailureArchiveRoot}/assets" "${restoreFailureTmpRoot}"
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
        refreshScriptModules 7777777777777777777777777777777777777777
    ) >"${restoreFailureOutputLog}" 2>&1
    grep -q '完整安装包替换失败，旧模块恢复失败，请手动检查备份目录' "${restoreFailureOutputLog}"
    grep -q "${restoreFailureDir}/.padm-update-backup" "${restoreFailureOutputLog}"
    [[ -d "${restoreFailureDir}/.padm-update-backup" ]]
    [[ "$(<"${restoreFailureDir}/shell/marker")" == "old-shell" ]]
    [[ -d "${restoreFailureDir}/.padm-update-backup/documents" ]]
    [[ "$(<"${restoreFailureDir}/.padm-update-backup/documents/marker")" == "old-doc" ]]
    [[ ! -e "${restoreFailureDir}/.padm-ref" ]]
    if regressionFindHasMatches "${restoreFailureTmpRoot}" -mindepth 1 -maxdepth 1 -type d; then
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

runAliasInstallModuleSyncFailureRegression() {
    local fixtureDir fixtureAbs sourceDir targetDir outputLog cpLog rcFile oldScriptDir oldPadmInstallDir oldHome rc
    fixtureDir="${TMP_DIR}/alias-install-sync-failure"
    outputLog="${fixtureDir}/output.log"
    cpLog="${fixtureDir}/cp.log"
    rcFile="${fixtureDir}/alias.rc"

    mkdir -p "${fixtureDir}/source/shell" "${fixtureDir}/source/documents" "${fixtureDir}/source/assets" \
        "${fixtureDir}/target/shell" "${fixtureDir}/target/documents" "${fixtureDir}/target/assets" "${fixtureDir}/home"
    fixtureAbs=$(cd -- "${fixtureDir}" && pwd -P)
    sourceDir="${fixtureAbs}/source"
    targetDir="${fixtureAbs}/target"
    cat >"${sourceDir}/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
EOF
    printf 'new-shell\n' >"${sourceDir}/shell/marker"
    printf 'new-doc\n' >"${sourceDir}/documents/marker"
    printf 'new-asset\n' >"${sourceDir}/assets/marker"
    printf 'old-shell\n' >"${targetDir}/shell/marker"
    printf 'old-doc\n' >"${targetDir}/documents/marker"
    printf 'old-asset\n' >"${targetDir}/assets/marker"

    oldScriptDir="${SCRIPT_DIR:-}"
    oldPadmInstallDir="${PADM_INSTALL_DIR:-}"
    oldHome="${HOME}"
    SCRIPT_DIR="${sourceDir}"
    PADM_INSTALL_DIR="${targetDir}"
    HOME="${fixtureDir}/home"
    printf 'old-install\n' >"${targetDir}/install.sh"

    (
        cp() {
            printf 'cp %s\n' "$*" >>"${cpLog}"
            if [[ "$1" == "-R" && "$2" == "${sourceDir}/shell" ]]; then
                return 1
            fi
            command cp "$@"
        }
        rm() { printf 'rm %s\n' "$*" >>"${cpLog}"; return 0; }
        chmod() { :; }
        ln() { :; }
        set +e
        aliasInstall
        printf '%s\n' "$?" >"${rcFile}"
    ) >"${outputLog}" 2>&1
    rc=$(<"${rcFile}")

    [[ "${rc}" == "1" ]]
    grep -q "cp -R ${sourceDir}/shell " "${cpLog}"
    ! grep -q "cp -R ${sourceDir}/documents " "${cpLog}"
    ! grep -q "cp -R ${sourceDir}/assets " "${cpLog}"
    [[ "$(<"${targetDir}/shell/marker")" == "old-shell" ]]
    [[ "$(<"${targetDir}/documents/marker")" == "old-doc" ]]
    [[ "$(<"${targetDir}/assets/marker")" == "old-asset" ]]
    [[ "$(<"${targetDir}/install.sh")" == "old-install" ]]

    SCRIPT_DIR="${oldScriptDir}"
    HOME="${oldHome}"
    if [[ -n "${oldPadmInstallDir}" ]]; then
        PADM_INSTALL_DIR="${oldPadmInstallDir}"
    else
        unset PADM_INSTALL_DIR
    fi
}

runSyncInstallDirectoryTreeRestoreFailureRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/sync-install-tree-restore-failure"
        local rootAbs sourceDir targetDir backupPath backupRoot
        mkdir -p "${root}/source" "${root}/target"
        rootAbs=$(cd -- "${root}" && pwd -P)
        sourceDir="${rootAbs}/source"
        targetDir="${rootAbs}/target"
        printf 'new\n' >"${sourceDir}/marker"
        printf 'old\n' >"${targetDir}/marker"

        mv() {
            if [[ "$1" == "${targetDir}" && "$2" == */.target.padm-backup.*/target ]]; then
                backupPath="$2"
                command mv "$@"
                return
            fi
            if [[ "$1" == */.target.padm-stage.*/target && "$2" == "${targetDir}" ]]; then
                return 1
            fi
            if [[ -n "${backupPath:-}" && "$1" == "${backupPath}" && "$2" == "${targetDir}" ]]; then
                return 1
            fi
            command mv "$@"
        }

        ! syncInstallDirectoryTree "${sourceDir}" "${targetDir}"
        [[ ! -e "${targetDir}" ]]
        backupRoot=$(find "${rootAbs}" -maxdepth 1 -type d -name '.target.padm-backup.*' -print -quit)
        [[ -n "${backupRoot}" ]]
        [[ "$(<"${backupRoot}/target/marker")" == "old" ]]
        if regressionFindHasMatches "${rootAbs}" -maxdepth 1 -type d -name '.target.padm-stage.*'; then
            return 1
        fi
    )
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

runTlsRenewalExistingCertificateRegression() (
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
)

runTlsRenewalFailurePropagationRegression() (
    local root="${TMP_DIR}/tls-renew-failure-propagation"
    local tlsDir="${root}/certs"
    local homeDir="${root}/home"
    local serviceLog="${root}/services.log"
    local commandLog="${root}/commands.log"
    local statusLog="${root}/status.log"
    local errorLog="${root}/error.log"
    local statusJson
    local mode rc tlsRegressionStatMode=
    local chmodLog="${TMP_DIR}/tls-renew-chmod.log"
    local nginxState xrayState singBoxState

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
    nginxRunning() { [[ "${nginxState}" == "true" ]]; }
    xrayRunning() { [[ "${xrayState}" == "true" ]]; }
    singBoxRunning() { [[ "${singBoxState}" == "true" ]]; }
    handleNginx() {
        if [[ "$1" == "stop" && "${nginxState}" != "true" ]] || [[ "$1" == "start" && "${nginxState}" == "true" ]]; then
            return 0
        fi
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ -n "${2:-}" ]] && printf 'nginx-mode:%s\n' "$*" >>"${serviceLog}"
        [[ "${mode}" == "nginx-stop-fail" && "$1" == "stop" ]] && return 1
        [[ "${mode}" == "nginx-start-fail" && "$1" == "start" ]] && return 1
        [[ "$1" == "start" ]] && nginxState=true || nginxState=false
        return 0
    }
    handleXray() {
        if [[ "$1" == "stop" && "${xrayState}" != "true" ]] || [[ "$1" == "start" && "${xrayState}" == "true" ]]; then
            return 0
        fi
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "xray-stop-fail" && "$1" == "stop" ]] && return 1
        [[ "${mode}" == "xray-start-fail" && "$1" == "start" ]] && return 1
        [[ "$1" == "start" ]] && xrayState=true || xrayState=false
        return 0
    }
    handleSingBox() {
        if [[ "$1" == "stop" && "${singBoxState}" != "true" ]] || [[ "$1" == "start" && "${singBoxState}" == "true" ]]; then
            return 0
        fi
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "$1" == "start" ]] && singBoxState=true || singBoxState=false
        return 0
    }
    reloadCore() {
        printf 'reload\n' >>"${serviceLog}"
        [[ "${mode}" == "reload-fail" ]] && return 1
        xrayState=true
        singBoxState=true
        return 0
    }
    stat() {
        if [[ "${tlsRegressionStatMode:-}" == "unsafe-acme" && "$1" == "--format=%a" ]]; then
            printf '777\n'
            return 0
        fi
        if [[ "$1" == "--format=%z" && "${2:-}" == *"/renew.example.com_ecc/renew.example.com.cer" ]]; then
            date -d '89 days ago' '+%F %T.000000000 %z'
            return 0
        fi
        command stat "$@"
    }
    sudo() {
        printf 'sudo:%s\n' "$*" >>"${commandLog}"
        [[ "${mode}" == "renew-fail" && "$*" == *" --cron "* ]] && return 1
        [[ "${mode}" == "install-fail" && "$*" == *" --installcert "* ]] && return 1
        return 0
    }
    chmod() {
        printf '%s\n' "$*" >>"${chmodLog}"
        command chmod "$@"
    }
    prepareRenewalFixture() {
        rm -rf "${tlsDir}" "${homeDir}/.acme.sh"
        mkdir -p "${tlsDir}" "${homeDir}/.acme.sh/renew.example.com_ecc"
        printf 'cert\n' >"${tlsDir}/renew.example.com.crt"
        printf 'key\n' >"${tlsDir}/renew.example.com.key"
        printf 'cert\n' >"${homeDir}/.acme.sh/renew.example.com_ecc/renew.example.com.cer"
        printf 'key\n' >"${homeDir}/.acme.sh/renew.example.com_ecc/renew.example.com.key"
        printf '#!/usr/bin/env sh\n' >"${homeDir}/.acme.sh/acme.sh"
        chmod 755 "${homeDir}/.acme.sh/acme.sh"
        : >"${serviceLog}"
        : >"${commandLog}"
        : >"${chmodLog}"
        : >"${statusLog}"
        : >"${errorLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        nginxState=true
        xrayState=true
        singBoxState=false
        if [[ "${mode}" == "stopped-services" ]]; then
            nginxState=false
            xrayState=false
        elif [[ "${mode}" == "dual-core-running" ]]; then
            singBoxState=true
        fi
    }
    runRenewalCase() {
        mode=$1
        prepareRenewalFixture
        set +e
        renewalTLS >/dev/null 2>&1
        rc=$?
        set -e
    }

    rm -rf "${tlsDir}" "${homeDir}/.acme.sh"
    mkdir -p "${tlsDir}" "${homeDir}"
    currentHost=../escape
    domain=
    tlsDomain=
    installedDNSAPIStatus=
    dnsTLSDomain=
    printf 'cert\n' >"${root}/escape.crt"
    printf 'key\n' >"${root}/escape.key"
    : >"${statusLog}"
    : >"${errorLog}"
    statusJson=$(tlsCertificateStatusJson)
    jq -e '.status == "missing"' <<<"${statusJson}" >/dev/null
    ! renewalTLS >/dev/null 2>&1
    grep -q "未安装本机 TLS 证书" "${errorLog}"
    ! grep -q "检测到使用自定义证书" "${statusLog}"
    rm -f "${root}/escape.crt" "${root}/escape.key"

    currentHost=
    printf 'cert\n' >"${tlsDir}/bad;name.crt"
    printf 'key\n' >"${tlsDir}/bad;name.key"
    : >"${statusLog}"
    : >"${errorLog}"
    statusJson=$(tlsCertificateStatusJson)
    jq -e '.status == "missing"' <<<"${statusJson}" >/dev/null
    ! renewalTLS >/dev/null 2>&1
    grep -q "未安装本机 TLS 证书" "${errorLog}"
    ! grep -q "检测到使用自定义证书" "${statusLog}"
    rm -f "${tlsDir}/bad;name.crt" "${tlsDir}/bad;name.key"
    currentHost=renew.example.com

    mode=unsafe-acme
    prepareRenewalFixture
    tlsRegressionStatMode=unsafe-acme
    chmod 777 "${homeDir}/.acme.sh"
    set +e
    renewalTLS >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ ! -s "${commandLog}" ]]
    [[ ! -s "${serviceLog}" ]]
    grep -q 'acme.sh 路径、所有者或权限异常' "${errorLog}"
    tlsRegressionStatMode=

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

    runRenewalCase renew-fail
    [[ "${rc}" == "1" ]]
    grep -q '^sudo:.*--cron --home ' "${commandLog}"
    ! grep -q '^sudo:.*--installcert ' "${commandLog}"
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    ! grep -qx 'reload' "${serviceLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    runRenewalCase install-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:stop:true' "${serviceLog}"
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    ! grep -qx 'reload' "${serviceLog}"
    grep -q '^sudo:.*--cron --home ' "${commandLog}"
    grep -q '^sudo:.*--installcert -d renew.example.com' "${commandLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    runRenewalCase xray-start-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    ! grep -qx 'reload' "${serviceLog}"
    grep -q '^sudo:.*--installcert -d renew.example.com' "${commandLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    runRenewalCase nginx-start-fail
    [[ "${rc}" == "1" ]]
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    ! grep -qx 'reload' "${serviceLog}"
    grep -q '^sudo:.*--installcert -d renew.example.com' "${commandLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    runRenewalCase stopped-services
    [[ "${rc}" == "0" ]]
    grep -F -q -- "600 -- ${tlsDir}/renew.example.com.key" "${chmodLog}"
    [[ ! -s "${serviceLog}" ]]
    [[ "${nginxState}" == "false" && "${xrayState}" == "false" && "${singBoxState}" == "false" ]]

    runRenewalCase dual-core-running
    [[ "${rc}" == "0" ]]
    grep -qx 'nginx:stop:true' "${serviceLog}"
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'sing-box:start:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}"
    ! grep -qx 'reload' "${serviceLog}"
    [[ "${nginxState}" == "true" && "${xrayState}" == "true" && "${singBoxState}" == "true" ]]

    eval "$(awk '/^handleScriptCommand\(\)/,/^}/ { print }' "${PROJECT_ROOT}/install.sh")"
    renewalTLS() { return 37; }
    cronName=RenewTLS
    set +e
    (handleScriptCommand)
    rc=$?
    set -e
    [[ "${rc}" == "37" ]]
)

runTlsRenewalInstallRollbackRegression() (
    local root="${TMP_DIR}/tls-renew-install-rollback"
    local tlsDir="${root}/certs"
    local homeDir="${root}/home"
    local serviceLog="${root}/services.log"
    local commandLog="${root}/commands.log"
    local statusLog="${root}/status.log"
    local errorLog="${root}/error.log"
    local oldHome="${HOME}"
    local oldTlsDir="${PADM_TLS_DIR:-}"
    local oldCurrentHost="${currentHost:-}"
    local oldDomain="${domain:-}"
    local oldTlsDomain="${tlsDomain:-}"
    local oldInstalledDNSAPIStatus="${installedDNSAPIStatus:-}"
    local oldSslRenewalDays="${sslRenewalDays:-}"
    local oldCoreInstallType="${coreInstallType:-}"
    local oldDnsTLSDomain="${dnsTLSDomain:-}"
    local rc

    mkdir -p "${tlsDir}" "${homeDir}/.acme.sh/renew.example.com_ecc"
    HOME="${homeDir}"
    PADM_TLS_DIR="${tlsDir}"
    currentHost=renew.example.com
    domain=
    tlsDomain=
    dnsTLSDomain=
    installedDNSAPIStatus=
    coreInstallType=1
    sslRenewalDays=90
    export REGRESSION_STATUS_CARD_LOG="${statusLog}"
    export REGRESSION_ERROR_CARD_LOG="${errorLog}"

    printf 'old-cert\n' >"${tlsDir}/renew.example.com.crt"
    printf 'old-key\n' >"${tlsDir}/renew.example.com.key"
    printf 'acme-cert\n' >"${homeDir}/.acme.sh/renew.example.com_ecc/renew.example.com.cer"
    printf 'acme-key\n' >"${homeDir}/.acme.sh/renew.example.com_ecc/renew.example.com.key"
    : >"${serviceLog}"
    : >"${commandLog}"
    : >"${statusLog}"
    : >"${errorLog}"

    statusCard() { printf '%s\n' "$*" >>"${statusLog}"; }
    successCard() { printf '%s\n' "$*" >>"${statusLog}"; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    handleNginx() { printf 'nginx:%s\n' "$1" >>"${serviceLog}"; return 0; }
    handleXray() { printf 'xray:%s\n' "$1" >>"${serviceLog}"; return 0; }
    handleSingBox() { printf 'sing-box:%s\n' "$1" >>"${serviceLog}"; return 0; }
    reloadCore() { printf 'reload\n' >>"${serviceLog}"; return 0; }
    stat() {
        if [[ "$1" == "--format=%z" && "${2:-}" == *"/renew.example.com_ecc/renew.example.com.cer" ]]; then
            date -d '89 days ago' '+%F %T.000000000 %z'
            return 0
        fi
        command stat "$@"
    }
    sudo() {
        printf 'sudo:%s\n' "$*" >>"${commandLog}"
        printf 'new-cert\n' >"${tlsDir}/renew.example.com.crt"
        printf 'new-key\n' >"${tlsDir}/renew.example.com.key"
        return 1
    }

    set +e
    renewalTLS >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "$(<"${tlsDir}/renew.example.com.crt")" == "old-cert" ]]
    [[ "$(<"${tlsDir}/renew.example.com.key")" == "old-key" ]]
    grep -q '^sudo:.*--installcert -d renew.example.com' "${commandLog}"
    grep -q 'TLS 证书安装失败，正在尝试恢复服务' "${errorLog}"
    grep -qx 'reload' "${serviceLog}"
    grep -qx 'nginx:start' "${serviceLog}"

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
)

runTlsRenewalBackupPreparationRestoresServicesRegression() (
    local root="${TMP_DIR}/tls-renew-backup-prepare-restore"
    local tlsDir="${root}/certs"
    local homeDir="${root}/home"
    local serviceLog="${root}/services.log"
    local errorLog="${root}/error.log"
    local oldHome="${HOME}"
    local oldTlsDir="${PADM_TLS_DIR:-}"
    local oldCurrentHost="${currentHost:-}"
    local oldDomain="${domain:-}"
    local oldTlsDomain="${tlsDomain:-}"
    local oldInstalledDNSAPIStatus="${installedDNSAPIStatus:-}"
    local oldSslRenewalDays="${sslRenewalDays:-}"
    local oldCoreInstallType="${coreInstallType:-}"
    local oldDnsTLSDomain="${dnsTLSDomain:-}"
    local rc

    mkdir -p "${tlsDir}" "${homeDir}/.acme.sh/renew.example.com_ecc"
    HOME="${homeDir}"
    PADM_TLS_DIR="${tlsDir}"
    currentHost=renew.example.com
    domain=
    tlsDomain=
    dnsTLSDomain=
    installedDNSAPIStatus=
    coreInstallType=1
    sslRenewalDays=90
    export REGRESSION_ERROR_CARD_LOG="${errorLog}"

    printf 'old-cert\n' >"${tlsDir}/renew.example.com.crt"
    printf 'old-key\n' >"${tlsDir}/renew.example.com.key"
    printf 'acme-cert\n' >"${homeDir}/.acme.sh/renew.example.com_ecc/renew.example.com.cer"
    printf 'acme-key\n' >"${homeDir}/.acme.sh/renew.example.com_ecc/renew.example.com.key"
    : >"${serviceLog}"
    : >"${errorLog}"

    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    handleNginx() { printf 'nginx:%s\n' "$1" >>"${serviceLog}"; return 0; }
    handleXray() { printf 'xray:%s\n' "$1" >>"${serviceLog}"; return 0; }
    handleSingBox() { printf 'sing-box:%s\n' "$1" >>"${serviceLog}"; return 0; }
    reloadCore() { printf 'reload\n' >>"${serviceLog}"; return 0; }
    stat() {
        if [[ "$1" == "--format=%z" && "${2:-}" == *"/renew.example.com_ecc/renew.example.com.cer" ]]; then
            date -d '89 days ago' '+%F %T.000000000 %z'
            return 0
        fi
        command stat "$@"
    }
    local originalPadmCreateTempPath
    originalPadmCreateTempPath=$(declare -f padmCreateTempPath)
    eval "${originalPadmCreateTempPath/padmCreateTempPath/originalPadmCreateTempPath}"
    padmCreateTempPath() {
        local __outVar=$1
        shift
        if [[ "$*" == *"padm-tls-renew."* ]]; then
            return 1
        fi
        originalPadmCreateTempPath "${__outVar}" "$@"
    }
    sudo() {
        printf 'sudo:%s\n' "$*" >>"${serviceLog}"
        return 0
    }

    set +e
    renewalTLS >/dev/null 2>&1
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qx 'nginx:stop' "${serviceLog}"
    grep -qx 'xray:stop' "${serviceLog}"
    grep -qx 'reload' "${serviceLog}"
    grep -qx 'nginx:start' "${serviceLog}"
    ! grep -q '^sudo:' "${serviceLog}"
    [[ "$(<"${tlsDir}/renew.example.com.crt")" == "old-cert" ]]
    [[ "$(<"${tlsDir}/renew.example.com.key")" == "old-key" ]]

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
)

runTlsReinstallRollbackRegression() (
    local root="${TMP_DIR}/tls-reinstall-rollback"
    local tlsDir="${root}/tls"
    local resolvedTlsDir
    local homeDir="${root}/home"
    local statusLog="${root}/status.log"
    local errorLog="${root}/error.log"
    local cleanLog="${root}/clean.log"
    local oldHome="${HOME}"
    local oldTlsDir="${PADM_TLS_DIR:-}"
    local oldCurrentHost="${currentHost:-}"
    local oldDomain="${domain:-}"
    local oldTlsDomain="${tlsDomain:-}"
    local oldInstalledDNSAPIStatus="${installedDNSAPIStatus:-}"
    local oldLastInstallationConfig="${lastInstallationConfig:-}"
    local oldInstallTLSCount="${installTLSCount:-}"
    local oldSslType="${sslType:-}"
    local oldDnsAPIType="${dnsAPIType:-}"
    local oldDnsAPIStatus="${dnsAPIStatus:-}"
    local shellRc

    mkdir -p "${tlsDir}" "${homeDir}/.acme.sh/reinstall.example.com_ecc"
    printf 'old-cert\n' >"${tlsDir}/reinstall.example.com.crt"
    printf 'old-key\n' >"${tlsDir}/reinstall.example.com.key"
    printf 'acme-cert\n' >"${homeDir}/.acme.sh/reinstall.example.com_ecc/reinstall.example.com.cer"
    printf 'acme-key\n' >"${homeDir}/.acme.sh/reinstall.example.com_ecc/reinstall.example.com.key"
    printf '#!/usr/bin/env sh\n' >"${homeDir}/.acme.sh/acme.sh"
    chmod 755 "${homeDir}/.acme.sh/acme.sh"
    : >"${statusLog}"
    : >"${errorLog}"
    : >"${cleanLog}"
    resolvedTlsDir=$(cd -- "${tlsDir}" && pwd -P) || return 1

    HOME="${homeDir}"
    PADM_TLS_DIR="${tlsDir}"
    currentHost=
    domain=reinstall.example.com
    tlsDomain=
    installedDNSAPIStatus=
    lastInstallationConfig=
    installTLSCount=
    sslType=letsencrypt
    dnsAPIType=
    dnsAPIStatus=
    export REGRESSION_STATUS_CARD_LOG="${statusLog}"
    export REGRESSION_ERROR_CARD_LOG="${errorLog}"

    statusCard() { printf '%s\n' "$*" >>"${statusLog}"; }
    successCard() { printf '%s\n' "$*" >>"${statusLog}"; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    autoRead() {
        case "$3" in
        reInstallStatus) printf -v "$3" 'y' ;;
        *) printf -v "$3" '' ;;
        esac
    }
    renewalTLS() { return 0; }
    allowPort() { return 0; }
    switchDNSAPI() { return 0; }
    switchSSLType() { return 0; }
    customSSLEmail() { return 0; }
    cleanDirectoryContent() {
        printf 'clean:%s\n' "$1" >>"${cleanLog}"
        mkdir -p "$1" || return 1
        find "$1" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || return 1
    }
    selectAcmeInstallSSL() { return 0; }
    sudo() {
        printf 'sudo:%s\n' "$*" >>"${cleanLog}"
        return 1
    }

    set +e
    (
        set +e
        installTLS 1 >/dev/null 2>&1
        printf '%s\n' "$?" >"${root}/install.rc"
    )
    shellRc=$?
    set -e
    [[ "${shellRc}" == "0" ]]
    [[ "$(<"${root}/install.rc")" == "1" ]]
    grep -qx "clean:${resolvedTlsDir}" "${cleanLog}"
    grep -q '^sudo:.*--installcert -d reinstall.example.com' "${cleanLog}"
    [[ "$(<"${tlsDir}/reinstall.example.com.crt")" == "old-cert" ]]
    [[ "$(<"${tlsDir}/reinstall.example.com.key")" == "old-key" ]]
    grep -q 'TLS安装失败' "${errorLog}"
    ! grep -q 'TLS生成成功' "${statusLog}"

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
    lastInstallationConfig="${oldLastInstallationConfig}"
    installTLSCount="${oldInstallTLSCount}"
    sslType="${oldSslType}"
    dnsAPIType="${oldDnsAPIType}"
    dnsAPIStatus="${oldDnsAPIStatus}"
)

runRemoteSubscribeFetchUniqueRegression() {
    runRemoteSubscribeFetchRegression unique
}

runRemoteSubscribeFetchRollbackRegression() {
    runRemoteSubscribeFetchRegression rollback
}

runRemoteSubscribeFetchMergeRegression() {
    runRemoteSubscribeFetchRegression merge
}

runRemoteSubscribeFetchDisabledSourceRegression() {
    runRemoteSubscribeFetchRegression disabled-source
}

runRemoteSubscribeFetchControlledRegression() {
    runRemoteSubscribeFetchRegression controlled
}

runRemoteSubscribeFetchAppendFailureRegression() {
    runRemoteSubscribeFetchRegression append-failure
}

runRemoteSubscribeFetchCommitFailureRegression() {
    runRemoteSubscribeFetchRegression commit-failure
}

runRemoteSubscribeFetchIdempotentRegression() {
    runRemoteSubscribeFetchRegression idempotent
}

listRegressionRealityStreamChildSelectors() {
    printf '%s\n' \
        reality-stream-enable \
        reality-stream-disable
}

listRegressionRealityCandidatesChildSelectors() {
    printf '%s\n' \
        reality-candidates-fast \
        reality-asn-scan-plan \
        reality-candidates-full
}

if [[ "${PADM_REGRESSION_SOURCE_ONLY:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

printf 'use shell/subscription_groups_regression.sh <selector>\n' >&2
exit 2
