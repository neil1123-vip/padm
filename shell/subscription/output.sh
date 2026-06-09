#!/usr/bin/env bash

# 初始化 sing-box订阅配置
initSubscribeLocalConfig() {
    cleanDirectoryContent "$(subscribeLocalBaseDir)/sing-box"
}

appendDefaultSubscribeLine() {
    local user=$1
    local line=$2
    printf '%s\n' "${line}" >>"$(subscribeLocalBaseDir)/default/${user}"
}

appendClashMetaSubscribeBlock() {
    local user=$1
    local block=$2
    printf '%s\n' "${block}" >>"$(subscribeLocalBaseDir)/clashMeta/${user}"
}

serializeVlessRealityVisionLink() {
    local id=$1
    local entryHost=$2
    local port=$3
    local sni=$4
    local publicKey=$5
    local pqv=$6
    local email=$7
    local encryption=${8:-none}
    printf 'vless://%s@%s:%s?encryption=%s&security=reality&pqv=%s&type=tcp&sni=%s&fp=chrome&pbk=%s&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#%s' "${id}" "${entryHost}" "${port}" "${encryption}" "${pqv}" "${sni}" "${publicKey}" "${email}"
}

serializeVlessRealityGrpcLink() {
    local id=$1
    local entryHost=$2
    local port=$3
    local sni=$4
    local publicKey=$5
    local pqv=$6
    local email=$7
    printf 'vless://%s@%s:%s?encryption=none&security=reality&pqv=%s&type=grpc&sni=%s&fp=chrome&pbk=%s&sid=6ba85179e30d4fc2&path=grpc&serviceName=grpc#%s' "${id}" "${entryHost}" "${port}" "${pqv}" "${sni}" "${publicKey}" "${email}"
}

xrayRealityXHTTPConfigFile() {
    printf '%s12_VLESS_XHTTP_inbounds.json' "${configPath:-/etc/padm/xray/conf/}"
}

xrayRealityXHTTPSetting() {
    local key=$1
    local fallback=$2
    local configFile value
    configFile=$(xrayRealityXHTTPConfigFile)
    if [[ -f "${configFile}" ]]; then
        value=$(jq -r ".inbounds[0].streamSettings.xhttpSettings.${key} // empty" "${configFile}" 2>/dev/null)
    fi
    printf '%s' "${value:-${fallback}}"
}

serializeVlessRealityXHTTPLink() {
    local id=$1
    local add=$2
    local port=$3
    local sni=$4
    local path=$5
    local publicKey=$6
    local email=$7
    local encryption=${8:-none}
    local host=${9:-${sni}}
    local mode=${10:-}
    local modeParam=
    [[ -n "${mode}" ]] && modeParam="&mode=${mode}"
    printf 'vless://%s@%s:%s?encryption=%s&security=reality&type=xhttp&sni=%s&host=%s&fp=chrome&path=%s%s&pbk=%s&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#%s' "${id}" "${add}" "${port}" "${encryption}" "${sni}" "${host}" "${path}" "${modeParam}" "${publicKey}" "${email}"
}

appendSingBoxSubscribeLocalConfig() {
    local user=$1
    local jqFilter=$2
    local targetPath="$(subscribeLocalBaseDir)/sing-box/${user}"
    local tmpPath="${targetPath}.tmp"

    if ! jq -r "${jqFilter}" "${targetPath}" | jq . >"${tmpPath}"; then
        rm -f "${tmpPath}"
        return 1
    fi
    mv "${tmpPath}" "${targetPath}"
}

appendStandardTLSSubscribeOutputs() {
    local user=$1
    local defaultLink=$2
    local clashMetaBlock=$3
    local singBoxFilter=$4

    appendDefaultSubscribeLine "${user}" "${defaultLink}"
    appendClashMetaSubscribeBlock "${user}" "${clashMetaBlock}"
    appendSingBoxSubscribeLocalConfig "${user}" "${singBoxFilter}"
}

subscribeOutputTitle() {
    local title=$1
    echoContent title "\n┌─ ${title} ─────────────────────────────────────────"
    menuClose
}

realityEntryHost() {
    if [[ -n "${realityEntryHost:-}" ]]; then
        printf '%s' "${realityEntryHost}"
    elif [[ -n "${currentHost:-}" ]]; then
        printf '%s' "${currentHost}"
    elif [[ -n "${domain:-}" ]]; then
        printf '%s' "${domain%%:*}"
    else
        getPublicIP
    fi
}

# 通用
defaultBase64Code() {
    local type=$1
    local port=$2
    local email=$3
    local id=$4
    local add=$5
    local path=$6
    local user=
    user=${email%%-*}
    mkdir -p "$(subscribeLocalBaseDir)/default" "$(subscribeLocalBaseDir)/clashMeta" "$(subscribeLocalBaseDir)/sing-box"
    if [[ ! -f "$(subscribeLocalBaseDir)/sing-box/${user}" ]]; then
        echo [] >"$(subscribeLocalBaseDir)/sing-box/${user}"
    fi

    case "${type}" in
    vlesstcp)
        emitVlessTcpSubscribeOutput "${port}" "${email}" "${id}" "${add}" "${path}" "${user}"
        ;;
    vmessws)
        emitVmessWsSubscribeOutput "${port}" "${email}" "${id}" "${add}" "${path}" "${user}"
        ;;
    vlessws)
        emitVlessWsSubscribeOutput "${port}" "${email}" "${id}" "${add}" "${path}" "${user}"
        ;;
    vlessXHTTP)
        emitVlessXHTTPSubscribeOutput "${port}" "${email}" "${id}" "${add}" "${path}" "${user}"
        ;;
    vlessgrpc)
        emitVlessGrpcSubscribeOutput "${port}" "${email}" "${id}" "${add}" "${path}" "${user}"
        ;;
    trojan)
        emitTrojanSubscribeOutput "${port}" "${email}" "${id}" "${add}" "${path}" "${user}"
        ;;
    trojangrpc)
        emitTrojanGrpcSubscribeOutput "${port}" "${email}" "${id}" "${add}" "${path}" "${user}"
        ;;
    hysteria)
        emitHysteriaSubscribeOutput "${port}" "${email}" "${id}" "${add}" "${path}" "${user}"
        ;;
    vlessReality)
        emitVlessRealitySubscribeOutput "${port}" "${email}" "${id}" "${add}" "${path}" "${user}"
        ;;
    vlessRealityGRPC)
        emitVlessRealityGrpcSubscribeOutput "${port}" "${email}" "${id}" "${add}" "${path}" "${user}"
        ;;
    tuic)
        emitTuicSubscribeOutput "${port}" "${email}" "${id}" "${add}" "${path}" "${user}"
        ;;
    naive)
        emitNaiveSubscribeOutput "${port}" "${email}" "${id}" "${add}" "${path}" "${user}"
        ;;
    vmessHTTPUpgrade)
        emitVmessHTTPUpgradeSubscribeOutput "${port}" "${email}" "${id}" "${add}" "${path}" "${user}"
        ;;
    anytls)
        emitAnyTlsSubscribeOutput "${port}" "${email}" "${id}" "${add}" "${path}" "${user}"
        ;;
    esac
}
