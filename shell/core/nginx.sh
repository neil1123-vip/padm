#!/usr/bin/env bash

# 清理本脚本管理的nginx配置
cleanAgentNginxConf() {
    rm -f "${nginxConfigPath}alone.conf" "${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf" "${nginxConfigPath}subscribe.conf" "${nginxConfigPath}checkPortOpen.conf" >/dev/null 2>&1
    rm -f "$(realityStreamSplitConfFile)" "$(realityStreamSplitStateFile)" >/dev/null 2>&1
    removeRealityStreamNginxInclude
}


# Reality 443 共存分流配置
realityStreamSplitStateFile() {
    echo "/etc/padm/reality_stream_split.json"
}

realityStreamSplitConfFile() {
    echo "/etc/nginx/stream.d/padm-reality.conf"
}

realityStreamSplitNginxConf() {
    if [[ -f "/etc/nginx/nginx.conf" ]]; then
        echo "/etc/nginx/nginx.conf"
    fi
}

realityStreamXrayBinary() {
    echo "/etc/padm/xray/xray"
}

realityStreamXrayConfDir() {
    echo "/etc/padm/xray/conf"
}

realityStreamVisionConfigFile() {
    echo "${configPath}07_VLESS_vision_reality_inbounds.json"
}

realityStreamXHTTPConfigFile() {
    echo "${configPath}12_VLESS_XHTTP_inbounds.json"
}

realityStreamNginxSupportsStream() {
    nginx -V 2>&1 | grep -q -- "--with-stream" && return 0
    nginx -T 2>/dev/null | grep -q "ngx_stream_module" && return 0
    [[ -f /usr/lib/nginx/modules/ngx_stream_module.so || -f /usr/share/nginx/modules/ngx_stream_module.so ]]
}

realityStreamPortListener() {
    local port=$1
    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 {print $1" "$2" "$9}' | head -n 3
        return 0
    fi
    if command -v ss >/dev/null 2>&1; then
        ss -ltnp 2>/dev/null | awk -v port=":${port}" '$4 ~ port"$" {print $0}' | head -n 3
    fi
}

realityStreamWarnPublic443Status() {
    local listener
    listener=$(realityStreamPortListener 443)
    if [[ -z "${listener}" ]]; then
        echoContent yellow " ---> 未检测到本机 443 监听；如果只是使用 Reality，直接让 Reality 使用 443 更简单"
    else
        echoContent yellow " ---> 检测到本机 443 已被占用，配置分流会由 Nginx stream 接管公网 443"
        echoContent yellow "${listener}"
    fi
}

realityStreamDomainRecords() {
    local domain=$1
    local records= aaaaRecords=
    if command -v dig >/dev/null 2>&1; then
        records=$(dig @1.1.1.1 +time=2 +short A "${domain}" 2>/dev/null | grep -E '^[0-9.]+$')
        if [[ -z "${records}" ]]; then
            records=$(dig @8.8.8.8 +time=2 +short A "${domain}" 2>/dev/null | grep -E '^[0-9.]+$')
        fi
        aaaaRecords=$(dig @1.1.1.1 +time=2 +short AAAA "${domain}" 2>/dev/null | grep ':')
    elif command -v getent >/dev/null 2>&1; then
        records=$(getent ahosts "${domain}" | awk '{print $1}' | awk '!seen[$0]++')
    fi
    printf '%s\n%s\n' "${records}" "${aaaaRecords}"
}

realityStreamWarnWebsiteDomainResolve() {
    local domains=$1
    local publicIPv4 publicIPv6 domain records
    publicIPv4=$(getPublicIP 4)
    publicIPv6=$(getPublicIP 6)
    while read -r domain; do
        [[ -n "${domain}" ]] || continue
        records=$(realityStreamDomainRecords "${domain}" | awk 'NF' | awk '!seen[$0]++')
        if [[ -z "${records}" ]]; then
            echoContent yellow " ---> 未解析到真实网站域名 ${domain} 的 A/AAAA 记录，请确认 DNS 已生效"
            continue
        fi
        if { [[ -n "${publicIPv4}" ]] && echo "${records}" | grep -Fxq "${publicIPv4}"; } || { [[ -n "${publicIPv6}" ]] && echo "${records}" | grep -Fxq "${publicIPv6}"; }; then
            echoContent green " ---> 真实网站域名 ${domain} 解析到本机"
        else
            echoContent yellow " ---> 真实网站域名 ${domain} 当前未解析到本机，访问该域名可能不会进入本机 443"
            echoContent yellow " ---> 本机IP: ${publicIPv4:-未获取}${publicIPv6:+ / ${publicIPv6}}"
            echoContent yellow " ---> DNS记录: $(echo "${records}" | tr '\n' ' ')"
        fi
    done <<<"${domains}"
}

realityStreamLocalPortListening() {
    local port=$1
    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | awk -v port=":${port}" '$4 ~ port"$" {print $4}' | grep -Eq "(^|:)(127\.0\.0\.1|0\.0\.0\.0|\[::\]|::1):?${port}$|:${port}$" && return 0
    fi
    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 {print $9}' | grep -Eq "127\.0\.0\.1:${port}|0\.0\.0\.0:${port}|\*:${port}|\[::1\]:${port}" && return 0
    fi
    return 1
}

realityStreamWarnWebsiteBackend() {
    local port=$1
    if realityStreamLocalPortListening "${port}"; then
        echoContent green " ---> 检测到网站后端端口 127.0.0.1:${port} 已监听"
    else
        echoContent yellow " ---> 未检测到网站后端 127.0.0.1:${port} 监听"
        echoContent yellow " ---> 继续配置后，真实网站域名会被转发到该端口；请先准备网站后端或改用正确端口"
    fi
}

backupRealityStreamFile() {
    local file=$1
    local backup=$2
    if [[ -f "${file}" ]]; then
        cp "${file}" "${backup}"
    else
        rm -f "${backup}" >/dev/null 2>&1
    fi
}

restoreRealityStreamFile() {
    local file=$1
    local backup=$2
    if [[ -f "${backup}" ]]; then
        cp "${backup}" "${file}"
    else
        rm -f "${file}" >/dev/null 2>&1
    fi
}

realityStreamRollback() {
    local tmpDir=$1
    [[ -n "${tmpDir}" && -d "${tmpDir}" ]] || return 0
    restoreRealityStreamFile "$(realityStreamVisionConfigFile)" "${tmpDir}/vision.json"
    restoreRealityStreamFile "$(realityStreamXHTTPConfigFile)" "${tmpDir}/xhttp.json"
    restoreRealityStreamFile "$(realityStreamSplitConfFile)" "${tmpDir}/stream.conf"
    restoreRealityStreamFile "$(realityStreamSplitStateFile)" "${tmpDir}/state.json"
    restoreRealityStreamFile "$(realityStreamSplitNginxConf)" "${tmpDir}/nginx.conf"
}

removeRealityStreamBackup() {
    local tmpDir=$1
    [[ -n "${tmpDir}" && -d "${tmpDir}" ]] && rm -rf "${tmpDir}"
}

ensureRealityStreamNginxInclude() {
    local nginxMainConf
    nginxMainConf=$(realityStreamSplitNginxConf)
    [[ -n "${nginxMainConf}" && -f "${nginxMainConf}" ]] || return 1

    mkdir -p /etc/nginx/stream.d
    if ! grep -q "padm stream include start" "${nginxMainConf}"; then
        cat <<'EOF' >>"${nginxMainConf}"

# padm stream include start
include /etc/nginx/stream.d/*.conf;
# padm stream include end
EOF
    fi
}

removeRealityStreamNginxInclude() {
    local nginxMainConf tmpFile
    nginxMainConf=$(realityStreamSplitNginxConf)
    [[ -n "${nginxMainConf}" && -f "${nginxMainConf}" ]] || return 0
    tmpFile=$(mktemp /tmp/padm-nginx.XXXXXX) || return 1
    awk '
        /# padm stream include start/ {skip=1; next}
        /# padm stream include end/ {skip=0; next}
        skip != 1 {print}
    ' "${nginxMainConf}" >"${tmpFile}" && mv "${tmpFile}" "${nginxMainConf}"
}

normalizeRealityStreamDomains() {
    echo "$1" | tr ',，' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -E '^[A-Za-z0-9.-]+$' | awk '!seen[$0]++'
}

realityStreamSplitEnabled() {
    local stateFile
    stateFile=$(realityStreamSplitStateFile)
    [[ -f "${stateFile}" ]] && jq -e '.enabled == true' "${stateFile}" >/dev/null 2>&1
}

realityStreamPublicPortForProtocol() {
    local protocol=$1
    local stateFile defaultProtocol
    stateFile=$(realityStreamSplitStateFile)
    [[ -f "${stateFile}" ]] || return 0
    defaultProtocol=$(jq -r '.default_protocol // empty' "${stateFile}" 2>/dev/null)
    [[ "${defaultProtocol}" == "${protocol}" ]] || return 0
    jq -r --arg protocol "${protocol}" '.protocols[$protocol].public_port // empty' "${stateFile}" 2>/dev/null
}

realityStreamStoredPublicPortForProtocol() {
    local protocol=$1
    local stateFile
    stateFile=$(realityStreamSplitStateFile)
    [[ -f "${stateFile}" ]] || return 0
    jq -r --arg protocol "${protocol}" '.protocols[$protocol].restore_port // .protocols[$protocol].public_port // empty' "${stateFile}" 2>/dev/null
}

realityStreamInternalPortForProtocol() {
    local protocol=$1
    local stateFile
    stateFile=$(realityStreamSplitStateFile)
    [[ -f "${stateFile}" ]] || return 0
    jq -r --arg protocol "${protocol}" '.protocols[$protocol].internal_port // empty' "${stateFile}" 2>/dev/null
}

realityStreamPatchXrayConfig() {
    local protocol=$1
    local internalPort=$2
    local configFile=$3
    [[ -f "${configFile}" ]] || return 0

    local filter
    if [[ "${protocol}" == "vision" ]]; then
        filter='.inbounds[0].listen = "127.0.0.1" | .inbounds[0].port = ($port | tonumber)'
    else
        filter='.inbounds[0].listen = "127.0.0.1" | .inbounds[0].port = ($port | tonumber)'
    fi
    jq --arg port "${internalPort}" "${filter}" "${configFile}" >"${configFile}.tmp" && mv "${configFile}.tmp" "${configFile}"
}

realityStreamRestoreXrayConfig() {
    local protocol=$1
    local publicPort=$2
    local configFile=$3
    [[ -f "${configFile}" ]] || return 0

    local filter
    if [[ "${protocol}" == "vision" ]]; then
        filter='del(.inbounds[0].listen) | .inbounds[0].port = ($port | tonumber)'
    else
        filter='.inbounds[0].listen = "0.0.0.0" | .inbounds[0].port = ($port | tonumber)'
    fi
    jq --arg port "${publicPort}" "${filter}" "${configFile}" >"${configFile}.tmp" && mv "${configFile}.tmp" "${configFile}"
}

realityStreamRefreshSubscribeIfInstalled() {
    readNginxSubscribe
    if [[ -n "${subscribePort}" ]]; then
        subscribe false true
    fi
}

renderRealityStreamSplitNginxConf() {
    local domains=$1
    local websitePort=$2
    local realityPort=$3
    local confFile
    confFile=$(realityStreamSplitConfFile)
    mkdir -p "$(dirname "${confFile}")"

    {
        echo "stream {"
        echo "    map \$ssl_preread_server_name \$padm_reality_backend {"
        while read -r domain; do
            [[ -n "${domain}" ]] || continue
            echo "        ${domain} padm_website;"
        done <<<"${domains}"
        echo "        default padm_reality;"
        echo "    }"
        echo
        echo "    upstream padm_website {"
        echo "        server 127.0.0.1:${websitePort};"
        echo "    }"
        echo
        echo "    upstream padm_reality {"
        echo "        server 127.0.0.1:${realityPort};"
        echo "    }"
        echo
        echo "    server {"
        echo "        listen 443 reuseport;"
        echo "        listen [::]:443 reuseport;"
        echo "        ssl_preread on;"
        echo "        proxy_pass \$padm_reality_backend;"
        echo "    }"
        echo "}"
    } >"${confFile}"
}

showRealityStreamSplitStatus() {
    local stateFile confFile nginxMainConf defaultProtocol internalPort publicPort configFile listenValue portValue
    stateFile=$(realityStreamSplitStateFile)
    confFile=$(realityStreamSplitConfFile)
    nginxMainConf=$(realityStreamSplitNginxConf)
    echoContent skyBlue "\n================ Reality 443 共存分流状态 ================\n"
    if ! realityStreamSplitEnabled; then
        echoContent yellow "当前未启用 Reality 443 共存分流"
        [[ -f "${stateFile}" ]] && echoContent yellow "检测到状态文件残留: ${stateFile}"
        [[ -f "${confFile}" ]] && echoContent yellow "检测到 Nginx stream 配置残留: ${confFile}"
        return
    fi
    echoContent green "当前已启用 Reality 443 共存分流"
    jq -r '
        "公网入口端口: " + ((.public_port // 443) | tostring),
        "网站后端端口: " + ((.website_backend_port // "") | tostring),
        "网站域名: " + ((.website_domains // []) | join(", ")),
        "默认 Reality 后端: " + (.default_protocol // "vision"),
        "Reality Vision 后端端口: " + ((.protocols.vision.internal_port // "未启用") | tostring),
        "Reality XHTTP 后端端口: " + ((.protocols.xhttp.internal_port // "未启用") | tostring)
    ' "${stateFile}" 2>/dev/null | while read -r line; do
        echoContent yellow "${line}"
    done

    [[ -f "${confFile}" ]] && echoContent green "Nginx stream配置存在: ${confFile}" || echoContent red "Nginx stream配置缺失: ${confFile}"
    if [[ -n "${nginxMainConf}" ]] && grep -q "padm stream include start" "${nginxMainConf}"; then
        echoContent green "Nginx主配置已包含 padm stream include"
    else
        echoContent red "Nginx主配置缺少 padm stream include"
    fi

    defaultProtocol=$(jq -r '.default_protocol // empty' "${stateFile}" 2>/dev/null)
    internalPort=$(realityStreamInternalPortForProtocol "${defaultProtocol}")
    publicPort=$(realityStreamPublicPortForProtocol "${defaultProtocol}")
    if [[ "${defaultProtocol}" == "xhttp" ]]; then
        configFile=$(realityStreamXHTTPConfigFile)
    else
        configFile=$(realityStreamVisionConfigFile)
    fi
    if [[ -f "${configFile}" ]]; then
        listenValue=$(jq -r '.inbounds[0].listen // ""' "${configFile}" 2>/dev/null)
        portValue=$(jq -r '.inbounds[0].port // ""' "${configFile}" 2>/dev/null)
        if [[ "${listenValue}" == "127.0.0.1" && "${portValue}" == "${internalPort}" ]]; then
            echoContent green "默认 Reality 后端监听正常: 127.0.0.1:${internalPort}"
        else
            echoContent red "默认 Reality 后端监听异常: listen=${listenValue:-0.0.0.0}, port=${portValue}, 期望 127.0.0.1:${internalPort}"
        fi
    else
        echoContent red "默认 Reality 后端配置缺失: ${configFile}"
    fi
    [[ -n "${publicPort}" ]] && echoContent yellow "订阅应输出公网端口: ${publicPort}"
}


configureRealityStreamSplit() {
    if [[ "${coreInstallType}" != "1" ]]; then
        echoContent red " ---> 443 共存分流当前仅支持 Xray Reality Vision/XHTTP"
        exit 0
    fi
    if ! currentProtocolHasAny 7 12; then
        echoContent red " ---> 未检测到 Xray Reality Vision 或 Reality XHTTP"
        exit 0
    fi
    if ! command -v nginx >/dev/null 2>&1; then
        echoContent yellow "未检测到 Nginx，443 共存分流需要 Nginx stream"
        read -r -p "是否安装 Nginx？[y/n]:" installNginxStatus
        if [[ "${installNginxStatus}" == "y" ]]; then
            installNginxTools
        else
            echoContent red " ---> 已取消配置"
            exit 0
        fi
    fi
    if ! realityStreamNginxSupportsStream; then
        echoContent red " ---> 当前 Nginx 未检测到 stream 模块，无法配置 SNI 分流"
        echoContent yellow " ---> 可选方案：改用 Reality 8443/高位端口，或安装带 stream 模块的 Nginx"
        exit 0
    fi

    echoContent skyBlue "\n================ 配置 Reality 443 共存分流 ================\n"
    echoContent yellow "Reality 不需要本机伪装站点；该功能仅用于同机 443 真实网站共存。"
    echoContent yellow "只需要填写真实网站域名，其他 SNI 默认转给 Reality。"
    echoContent yellow "Reality 的 entry 仍输出公网 443，Reality SNI 仍保持外部伪装目标站。"
    realityStreamWarnPublic443Status
    read -r -p "是否确实要在本机 443 同时提供真实网站？[y/n]:" enableRealityStreamSplit
    if [[ "${enableRealityStreamSplit}" != "y" ]]; then
        echoContent yellow " ---> 已取消配置；仅使用 Reality 时建议直接让 Reality 使用 443"
        exit 0
    fi
    read -r -p "请输入真实网站域名，多个用逗号分隔:" websiteDomainsInput
    local websiteDomains
    websiteDomains=$(normalizeRealityStreamDomains "${websiteDomainsInput}")
    if [[ -z "${websiteDomains}" ]]; then
        echoContent red " ---> 未填写合法网站域名"
        exit 0
    fi

    local websitePort visionInternalPort xhttpInternalPort currentVisionPort currentXHTTPPort stateFile publicPort defaultProtocol defaultInternalPort backupDir
    publicPort=443
    currentVisionPort=$(jq -r '.inbounds[0].port // empty' "$(realityStreamVisionConfigFile)" 2>/dev/null)
    currentXHTTPPort=$(jq -r '.inbounds[0].port // empty' "$(realityStreamXHTTPConfigFile)" 2>/dev/null)
    backupDir=$(mktemp -d /tmp/padm-reality-stream.XXXXXX) || exit 0
    backupRealityStreamFile "$(realityStreamVisionConfigFile)" "${backupDir}/vision.json"
    backupRealityStreamFile "$(realityStreamXHTTPConfigFile)" "${backupDir}/xhttp.json"
    backupRealityStreamFile "$(realityStreamSplitConfFile)" "${backupDir}/stream.conf"
    backupRealityStreamFile "$(realityStreamSplitStateFile)" "${backupDir}/state.json"
    backupRealityStreamFile "$(realityStreamSplitNginxConf)" "${backupDir}/nginx.conf"

    if currentProtocolHas 7 && currentProtocolHas 12; then
        echoContent yellow "检测到同时安装了 Reality Vision 与 Reality XHTTP。"
        echoContent yellow "SNI stream 的 default 只能转给一个 Reality 后端，请选择公网 443 默认转发目标。"
        echoContent yellow "1.Reality Vision"
        echoContent yellow "2.Reality XHTTP"
        read -r -p "请选择:" selectDefaultRealityProtocol
        if [[ "${selectDefaultRealityProtocol}" == "2" ]]; then
            defaultProtocol=xhttp
        else
            defaultProtocol=vision
        fi
    elif currentProtocolHas 12; then
        defaultProtocol=xhttp
    else
        defaultProtocol=vision
    fi

    read -r -p "请输入网站后端端口，[回车]默认8443:" websitePort
    websitePort=${websitePort:-8443}
    if [[ ! "${websitePort}" =~ ^[0-9]+$ || "${websitePort}" -lt 1 || "${websitePort}" -gt 65535 ]]; then
        echoContent red " ---> 网站后端端口不合法"
        exit 0
    fi
    realityStreamWarnWebsiteDomainResolve "${websiteDomains}"
    realityStreamWarnWebsiteBackend "${websitePort}"

    if [[ "${defaultProtocol}" == "vision" ]]; then
        read -r -p "请输入 Reality Vision 后端端口，[回车]默认2443:" visionInternalPort
        visionInternalPort=${visionInternalPort:-2443}
        if [[ ! "${visionInternalPort}" =~ ^[0-9]+$ || "${visionInternalPort}" -lt 1 || "${visionInternalPort}" -gt 65535 ]]; then
            echoContent red " ---> Reality Vision 后端端口不合法"
            exit 0
        fi
        realityStreamPatchXrayConfig vision "${visionInternalPort}" "$(realityStreamVisionConfigFile)"
        defaultInternalPort=${visionInternalPort}
    fi

    if [[ "${defaultProtocol}" == "xhttp" ]]; then
        read -r -p "请输入 Reality XHTTP 后端端口，[回车]默认2444:" xhttpInternalPort
        xhttpInternalPort=${xhttpInternalPort:-2444}
        if [[ ! "${xhttpInternalPort}" =~ ^[0-9]+$ || "${xhttpInternalPort}" -lt 1 || "${xhttpInternalPort}" -gt 65535 ]]; then
            echoContent red " ---> Reality XHTTP 后端端口不合法"
            exit 0
        fi
        realityStreamPatchXrayConfig xhttp "${xhttpInternalPort}" "$(realityStreamXHTTPConfigFile)"
        defaultInternalPort=${xhttpInternalPort}
    fi

    if [[ -z "${defaultInternalPort}" ]]; then
        echoContent red " ---> 未找到 Reality 默认后端端口"
        exit 0
    fi

    ensureRealityStreamNginxInclude || {
        echoContent red " ---> 无法写入 Nginx stream include"
        exit 0
    }
    renderRealityStreamSplitNginxConf "${websiteDomains}" "${websitePort}" "${defaultInternalPort}"

    stateFile=$(realityStreamSplitStateFile)
    jq -n \
        --argjson enabled true \
        --arg publicPort "${publicPort}" \
        --arg websitePort "${websitePort}" \
        --arg defaultProtocol "${defaultProtocol}" \
        --arg visionRestorePort "${currentVisionPort:-443}" \
        --arg visionInternalPort "${visionInternalPort}" \
        --arg xhttpRestorePort "${currentXHTTPPort:-443}" \
        --arg xhttpInternalPort "${xhttpInternalPort}" \
        --arg domains "${websiteDomains}" '
        {
            enabled: $enabled,
            public_port: ($publicPort | tonumber),
            website_backend_port: ($websitePort | tonumber),
            default_protocol: $defaultProtocol,
            website_domains: ($domains | split("\n") | map(select(length > 0))),
            protocols: {}
        }
        | if $visionInternalPort != "" then .protocols.vision = {public_port: ($publicPort | tonumber), restore_port: ($visionRestorePort | tonumber), internal_port: ($visionInternalPort | tonumber)} else . end
        | if $xhttpInternalPort != "" then .protocols.xhttp = {public_port: ($publicPort | tonumber), restore_port: ($xhttpRestorePort | tonumber), internal_port: ($xhttpInternalPort | tonumber)} else . end
    ' >"${stateFile}"

    if ! nginx -t; then
        echoContent red " ---> Nginx配置检测失败，已自动恢复本次修改"
        realityStreamRollback "${backupDir}"
        removeRealityStreamBackup "${backupDir}"
        exit 0
    fi
    if ! "$(realityStreamXrayBinary)" -test -confdir "$(realityStreamXrayConfDir)"; then
        echoContent red " ---> Xray配置检测失败，已自动恢复本次修改"
        realityStreamRollback "${backupDir}"
        removeRealityStreamBackup "${backupDir}"
        exit 0
    fi
    removeRealityStreamBackup "${backupDir}"
    reloadCore
    serviceQueueRestart nginx
    serviceQueueApply
    realityStreamRefreshSubscribeIfInstalled
    echoContent green " ---> Reality 443 共存分流配置完成"
}

disableRealityStreamSplit() {
    local stateFile confFile visionPublicPort xhttpPublicPort
    stateFile=$(realityStreamSplitStateFile)
    confFile=$(realityStreamSplitConfFile)
    if ! realityStreamSplitEnabled; then
        echoContent yellow " ---> Reality 443 共存分流未启用"
        return
    fi

    visionPublicPort=$(realityStreamStoredPublicPortForProtocol vision)
    xhttpPublicPort=$(realityStreamStoredPublicPortForProtocol xhttp)
    [[ -n "${visionPublicPort}" ]] && realityStreamRestoreXrayConfig vision "${visionPublicPort}" "$(realityStreamVisionConfigFile)"
    [[ -n "${xhttpPublicPort}" ]] && realityStreamRestoreXrayConfig xhttp "${xhttpPublicPort}" "$(realityStreamXHTTPConfigFile)"

    rm -f "${confFile}" "${stateFile}" >/dev/null 2>&1
    removeRealityStreamNginxInclude
    if command -v nginx >/dev/null 2>&1; then
        nginx -t || exit 0
    fi
    "$(realityStreamXrayBinary)" -test -confdir "$(realityStreamXrayConfDir)" || exit 0
    reloadCore
    serviceQueueRestart nginx
    serviceQueueApply
    realityStreamRefreshSubscribeIfInstalled
    echoContent green " ---> 已关闭 Reality 443 共存分流"
}

# 删除nginx默认的配置
removeNginxDefaultConf() {
    if [[ -f ${nginxConfigPath}default.conf ]]; then
        if [[ "$(grep -c "server_name" <${nginxConfigPath}default.conf)" == "1" ]] && [[ "$(grep -c "server_name  localhost;" <${nginxConfigPath}default.conf)" == "1" ]]; then
            echoContent green " ---> 删除Nginx默认配置"
            rm -rf ${nginxConfigPath}default.conf >/dev/null 2>&1
        fi
    fi
}

# 修改nginx重定向配置
updateRedirectNginxConf() {
    local redirectDomain=
    redirectDomain=${domain}:${port}

    local nginxH2Conf=
    nginxH2Conf="listen 127.0.0.1:31302 http2 so_keepalive=on proxy_protocol;"
    nginxVersion=$(nginx -v 2>&1)

    if echo "${nginxVersion}" | grep -q "1.25" && [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $3}') -gt 0 ]] || [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $2}') -gt 25 ]]; then
        nginxH2Conf="listen 127.0.0.1:31302 so_keepalive=on proxy_protocol;http2 on;"
    fi

    cat <<EOF >${nginxConfigPath}alone.conf
    server {
    		listen 127.0.0.1:31300;
    		server_name _;
    		return 403;
    }
EOF

    if protocolSelectionHasAll "${selectCustomInstallType}" 2 5 || [[ -z "${selectCustomInstallType}" ]]; then

        cat <<EOF >>${nginxConfigPath}alone.conf
server {
	${nginxH2Conf}
	server_name ${domain};
	root ${nginxStaticPath};

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

	client_header_timeout 1071906480m;
    keepalive_timeout 1071906480m;

    location /${currentPath}grpc {
    	if (\$content_type !~ "application/grpc") {
    		return 404;
    	}
 		client_max_body_size 0;
		grpc_set_header X-Real-IP \$proxy_add_x_forwarded_for;
		client_body_timeout 1071906480m;
		grpc_read_timeout 1071906480m;
		grpc_pass grpc://127.0.0.1:31301;
	}

	location /${currentPath}trojangrpc {
		if (\$content_type !~ "application/grpc") {
            		return 404;
		}
 		client_max_body_size 0;
		grpc_set_header X-Real-IP \$proxy_add_x_forwarded_for;
		client_body_timeout 1071906480m;
		grpc_read_timeout 1071906480m;
		grpc_pass grpc://127.0.0.1:31304;
	}
	location / {
    }
}
EOF
    elif protocolSelectionHasAny "${selectCustomInstallType}" 5 || [[ -z "${selectCustomInstallType}" ]]; then
        cat <<EOF >>${nginxConfigPath}alone.conf
server {
	${nginxH2Conf}

	set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

	server_name ${domain};
	root ${nginxStaticPath};

	location /${currentPath}grpc {
		client_max_body_size 0;
		keepalive_requests 4294967296;
		client_body_timeout 1071906480m;
 		send_timeout 1071906480m;
 		lingering_close always;
 		grpc_read_timeout 1071906480m;
 		grpc_send_timeout 1071906480m;
		grpc_pass grpc://127.0.0.1:31301;
	}
	location / {
    }
}
EOF

    elif protocolSelectionHasAny "${selectCustomInstallType}" 2 || [[ -z "${selectCustomInstallType}" ]]; then
        cat <<EOF >>${nginxConfigPath}alone.conf
server {
	${nginxH2Conf}

	set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    server_name ${domain};
	root ${nginxStaticPath};

	location /${currentPath}trojangrpc {
		client_max_body_size 0;
		# keepalive_time 1071906480m;
		keepalive_requests 4294967296;
		client_body_timeout 1071906480m;
 		send_timeout 1071906480m;
 		lingering_close always;
 		grpc_read_timeout 1071906480m;
 		grpc_send_timeout 1071906480m;
		grpc_pass grpc://127.0.0.1:31301;
	}
	location / {
    }
}
EOF
    else

        cat <<EOF >>${nginxConfigPath}alone.conf
server {
	${nginxH2Conf}

	set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

	server_name ${domain};
	root ${nginxStaticPath};

	location / {
	}
}
EOF
    fi

    cat <<EOF >>${nginxConfigPath}alone.conf
server {
	listen 127.0.0.1:31300 proxy_protocol;
	server_name ${domain};

	set_real_ip_from 127.0.0.1;
	real_ip_header proxy_protocol;

	root ${nginxStaticPath};
	location / {
	}
}
EOF
    handleNginx stop
}

# 移除nginx302配置
removeNginx302() {
    local count=
    grep -n "return 302" <"${nginxConfigPath}alone.conf" | while read -r line; do

        if ! echo "${line}" | grep -q "request_uri"; then
            local removeIndex=
            removeIndex=$(echo "${line}" | awk -F "[:]" '{print $1}')
            removeIndex=$((removeIndex + count))
            sed -i "${removeIndex}d" ${nginxConfigPath}alone.conf
            count=$((count - 1))
        fi
    done
}


# 检查302是否成功
checkNginx302() {
    local domain302Status=
    domain302Status=$(curl -s "https://${currentHost}:${currentPort}")
    if echo "${domain302Status}" | grep -q "302"; then
        #        local domain302Result=
        #        domain302Result=$(curl -L -s "https://${currentHost}:${currentPort}")
        #        if [[ -n "${domain302Result}" ]]; then
        echoContent green " ---> 302重定向设置完毕"
        exit 0
        #        fi
    fi
    echoContent red " ---> 302重定向设置失败，请仔细检查是否和示例相同"
    backupNginxConfig restoreBackup
}


# 备份恢复nginx文件
backupNginxConfig() {
    if [[ "$1" == "backup" ]]; then
        cp ${nginxConfigPath}alone.conf /etc/padm/alone_backup.conf
        echoContent green " ---> nginx配置文件备份成功"
    fi

    if [[ "$1" == "restoreBackup" ]] && [[ -f "/etc/padm/alone_backup.conf" ]]; then
        cp /etc/padm/alone_backup.conf ${nginxConfigPath}alone.conf
        echoContent green " ---> nginx配置文件恢复备份成功"
        rm /etc/padm/alone_backup.conf
    fi

}
