#!/usr/bin/env bash

# 初始化 sing-box订阅配置
subscribeLocalOutputFilePath() {
    local category=$1
    local user=$2
    printf '%s/%s/%s\n' "$(subscribeLocalBaseDir)" "${category}" "${user}"
}

subscribeLocalOutputCategoryDir() {
    local category=$1
    printf '%s/%s\n' "$(subscribeLocalBaseDir)" "${category}"
}

subscribeLocalOutputSafeCategoryDir() {
    local category=$1
    local targetDir
    targetDir=$(subscribeLocalOutputCategoryDir "${category}")
    targetDir=$(padmResolveManagedAbsolutePath "${targetDir}") || return 1
    padmEnsureSafeDirectory "${targetDir}" || return 1
    printf '%s\n' "${targetDir}"
}

subscribeLocalOutputAppendLine() {
    local targetPath=$1
    local line=$2
    local tmpPath

    padmCreateTempFileForTarget tmpPath "${targetPath}" subscribe || return 1
    if [[ -f "${targetPath}" ]]; then
        cp -p "${targetPath}" "${tmpPath}" || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
    fi
    printf '%s\n' "${line}" >>"${tmpPath}" || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
    commitGeneratedFile "${tmpPath}" "${targetPath}" 644 || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
}

ensureSubscribeLocalSingBoxConfig() {
    local targetPath=$1
    local tmpPath

    [[ -f "${targetPath}" ]] && return 0
    padmCreateTempFileForTarget tmpPath "${targetPath}" subscribe-init || return 1
    printf '[]\n' >"${tmpPath}" || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
    commitGeneratedJsonFile "${tmpPath}" "${targetPath}" || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
}

initSubscribeLocalConfig() {
    cleanDirectoryContent "$(subscribeLocalBaseDir)/default"
    cleanDirectoryContent "$(subscribeLocalBaseDir)/clashMeta"
    cleanDirectoryContent "$(subscribeLocalBaseDir)/sing-box"
}

appendDefaultSubscribeLine() {
    local user=$1
    local line=$2
    local defaultDir
    defaultDir=$(subscribeLocalOutputSafeCategoryDir default) || return 1
    subscribeLocalOutputAppendLine "${defaultDir}/${user}" "${line}"
}

appendClashMetaSubscribeBlock() {
    local user=$1
    local block=$2
    local clashDir
    clashDir=$(subscribeLocalOutputSafeCategoryDir clashMeta) || return 1
    subscribeLocalOutputAppendLine "${clashDir}/${user}" "${block}"
}

appendClashMetaSubscribeLines() {
    local user=$1
    local clashDir
    local tmpPath
    local targetPath

    clashDir=$(subscribeLocalOutputSafeCategoryDir clashMeta) || return 1
    targetPath="${clashDir}/${user}"
    padmCreateTempFileForTarget tmpPath "${targetPath}" subscribe || return 1
    if [[ -f "${targetPath}" ]]; then
        cp -p "${targetPath}" "${tmpPath}" || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
    fi
    cat >>"${tmpPath}" || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
    commitGeneratedFile "${tmpPath}" "${targetPath}" 644 || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
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

xrayRealityXHTTPSetting() {
    local key=$1
    local fallback=$2
    local configFile value
    configFile="${configPath:-/etc/padm/xray/conf/}12_VLESS_XHTTP_inbounds.json"
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
    local singBoxDir
    local targetPath
    local tmpPath

    singBoxDir=$(subscribeLocalOutputSafeCategoryDir sing-box) || return 1
    targetPath="${singBoxDir}/${user}"
    ensureSubscribeLocalSingBoxConfig "${targetPath}" || return 1
    padmCreateTempFileForTarget tmpPath "${targetPath}" subscribe || return 1
    if ! jq -r "${jqFilter}" "${targetPath}" | jq . >"${tmpPath}"; then
        padmRemoveCleanupPath "${tmpPath}"
        return 1
    fi
    commitGeneratedJsonFile "${tmpPath}" "${targetPath}" || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
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
    local add=${5:-}
    local path=${6:-}
    local user=
    local defaultDir clashDir singBoxDir
    user=$(stripClientNameSuffix "${email}")
    defaultDir=$(subscribeLocalOutputSafeCategoryDir default) || return 1
    clashDir=$(subscribeLocalOutputSafeCategoryDir clashMeta) || return 1
    singBoxDir=$(subscribeLocalOutputSafeCategoryDir sing-box) || return 1

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
