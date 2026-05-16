#!/usr/bin/env bash

subscribeLocalBaseDir() {
    printf '%s' "${PADM_SUBSCRIBE_LOCAL_DIR:-/etc/padm/subscribe_local}"
}

subscribePublicBaseDir() {
    printf '%s' "${PADM_SUBSCRIBE_DIR:-/etc/padm/subscribe}"
}

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
    if [[ "${type}" == "vlesstcp" ]]; then
        local defaultLink
        local clashMetaBlock
        local singBoxFilter

        defaultLink="vless://${id}@${currentHost}:${port}?encryption=none&security=tls&type=tcp&host=${currentHost}&fp=chrome&headerType=none&sni=${currentHost}&flow=xtls-rprx-vision#${email}"
        clashMetaBlock=$(cat <<EOF
  - name: "${email}"
    type: vless
    server: ${currentHost}
    port: ${port}
    uuid: ${id}
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    client-fingerprint: chrome
EOF
)
        singBoxFilter=". += [{\"tag\":\"${email}\",\"type\":\"vless\",\"server\":\"${currentHost}\",\"server_port\":${port},\"uuid\":\"${id}\",\"flow\":\"xtls-rprx-vision\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"packet_encoding\":\"xudp\"}]"

        subscribeOutputTitle "通用格式：VLESS TCP TLS Vision"
        echoContent green "    vless://${id}@${currentHost}:${port}?encryption=none&security=tls&fp=chrome&type=tcp&host=${currentHost}&headerType=none&sni=${currentHost}&flow=xtls-rprx-vision#${email}\n"

        subscribeOutputTitle "格式化明文：VLESS TCP TLS Vision"
        echoContent green "协议类型:VLESS，地址:${currentHost}，端口:${port}，用户ID:${id}，安全:tls，client-fingerprint: chrome（兼容模拟，不作为抗封锁保证），传输方式:tcp，flow:xtls-rprx-vision，账户名:${email}\n"
        appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

        subscribeOutputTitle "二维码：VLESS TCP TLS Vision"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${currentHost}%3A${port}%3Fencryption%3Dnone%26fp%3Dchrome%26security%3Dtls%26type%3Dtcp%26${currentHost}%3D${currentHost}%26headerType%3Dnone%26sni%3D${currentHost}%26flow%3Dxtls-rprx-vision%23${email}\n"

    elif [[ "${type}" == "vmessws" ]]; then
        qrCodeBase64Default=$(echo -n "{\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"ws\",\"add\":\"${add}\",\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}" | base64 -w 0)
        qrCodeBase64Default="${qrCodeBase64Default// /}"

        subscribeOutputTitle "通用 JSON：VMess WS TLS"
        echoContent green "    {\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"ws\",\"add\":\"${add}\",\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}\n"
        subscribeOutputTitle "通用链接：VMess WS TLS"
        echoContent green "    vmess://${qrCodeBase64Default}\n"
        subscribeOutputTitle "二维码：VMess WS TLS"

        local defaultLink
        local clashMetaBlock
        local singBoxFilter
        defaultLink="vmess://${qrCodeBase64Default}"
        clashMetaBlock=$(cat <<EOF
  - name: "${email}"
    type: vmess
    server: ${add}
    port: ${port}
    uuid: ${id}
    alterId: 0
    cipher: none
    udp: true
    tls: true
    client-fingerprint: chrome
    servername: ${currentHost}
    network: ws
    ws-opts:
      path: ${path}
      headers:
        Host: ${currentHost}
EOF
)
        singBoxFilter=". += [{\"tag\":\"${email}\",\"type\":\"vmess\",\"server\":\"${add}\",\"server_port\":${port},\"uuid\":\"${id}\",\"alter_id\":0,\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"packet_encoding\":\"packetaddr\",\"transport\":{\"type\":\"ws\",\"path\":\"${path}\",\"max_early_data\":2048,\"early_data_header_name\":\"Sec-WebSocket-Protocol\"}}]"
        appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vmess://${qrCodeBase64Default}\n"

    elif [[ "${type}" == "vlessws" ]]; then
        local defaultLink
        local clashMetaBlock
        local singBoxFilter

        defaultLink="vless://${id}@${add}:${port}?encryption=none&security=tls&type=ws&host=${currentHost}&sni=${currentHost}&fp=chrome&path=${path}#${email}"
        clashMetaBlock=$(cat <<EOF
  - name: "${email}"
    type: vless
    server: ${add}
    port: ${port}
    uuid: ${id}
    udp: true
    tls: true
    network: ws
    client-fingerprint: chrome
    servername: ${currentHost}
    ws-opts:
      path: ${path}
      headers:
        Host: ${currentHost}
EOF
)
        singBoxFilter=". += [{\"tag\":\"${email}\",\"type\":\"vless\",\"server\":\"${add}\",\"server_port\":${port},\"uuid\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"multiplex\":{\"enabled\":false,\"protocol\":\"smux\",\"max_streams\":32},\"packet_encoding\":\"xudp\",\"transport\":{\"type\":\"ws\",\"path\":\"${path}\",\"headers\":{\"Host\":\"${currentHost}\"}}}]"

        subscribeOutputTitle "通用格式：VLESS WS TLS"
        echoContent green "    ${defaultLink}\n"

        subscribeOutputTitle "格式化明文：VLESS WS TLS"
        echoContent green "    协议类型:VLESS，地址:${add}，TLS域名/SNI:${currentHost}，端口:${port}，client-fingerprint: chrome（兼容模拟，不作为抗封锁保证）,用户ID:${id}，安全:tls，传输方式:ws，路径:${path}，账户名:${email}\n"
        appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

        subscribeOutputTitle "二维码：VLESS WS TLS"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${add}%3A${port}%3Fencryption%3Dnone%26security%3Dtls%26type%3Dws%26host%3D${currentHost}%26fp%3Dchrome%26sni%3D${currentHost}%26path%3D${path}%23${email}"

    elif [[ "${type}" == "vlessXHTTP" ]]; then
        local vlessEncryption=none
        local vlessEncryptionStateFile=${PADM_VLESS_ENCRYPTION_STATE_FILE:-/etc/padm/xray/vless_encryption.json}
        local defaultLink xhttpHost xhttpMode
        if [[ "${coreInstallType}" == "1" && -f "${vlessEncryptionStateFile}" ]]; then
            vlessEncryption=$(jq -r '.encryption // "none"' "${vlessEncryptionStateFile}" 2>/dev/null)
        fi
        if [[ -z "${vlessEncryption}" || "${vlessEncryption}" == "null" ]]; then
            vlessEncryption=none
        fi
        path=$(xrayRealityXHTTPSetting path "${path}")
        xhttpHost=$(xrayRealityXHTTPSetting host "${xrayVLESSRealityXHTTPSNI}")
        xhttpMode=$(xrayRealityXHTTPSetting mode auto)
        defaultLink=$(serializeVlessRealityXHTTPLink "${id}" "${add}" "${port}" "${xrayVLESSRealityXHTTPSNI}" "${path}" "${currentRealityXHTTPPublicKey}" "${email}" "${vlessEncryption}" "${xhttpHost}" "${xhttpMode}")

        subscribeOutputTitle "通用格式：VLESS Reality XHTTP Vision XMUX"
        echoContent green "    ${defaultLink}\n"

        subscribeOutputTitle "格式化明文：VLESS Reality XHTTP Vision XMUX"
        echoContent green "协议类型:VLESS reality，入口地址:${add}，publicKey:${currentRealityXHTTPPublicKey}，shortId: 6ba85179e30d4fc2,serverNames：${xrayVLESSRealityXHTTPSNI}，端口:${port}，XHTTP host:${xhttpHost}，路径：${path}，mode:${xhttpMode}，Reality SNI:${xrayVLESSRealityXHTTPSNI}，用户ID:${id}，传输方式:xhttp，flow:xtls-rprx-vision，账户名:${email}\n"
        appendDefaultSubscribeLine "${user}" "${defaultLink}"

        cat <<EOF >>"$(subscribeLocalBaseDir)/clashMeta/${user}"
  - name: "${email}"
    type: vless
    server: ${add}
    port: ${port}
    uuid: ${id}
    udp: true
    tls: true
    network: xhttp
    flow: xtls-rprx-vision
    client-fingerprint: chrome
    alpn:
      - h2
    servername: ${xrayVLESSRealityXHTTPSNI}
    xhttp-opts:
      path: ${path}
      host: ${xhttpHost}
      mode: ${xhttpMode}
    reality-opts:
      public-key: ${currentRealityXHTTPPublicKey}
      short-id: 6ba85179e30d4fc2
EOF

        subscribeOutputTitle "二维码：VLESS Reality XHTTP Vision XMUX"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${add}%3A${port}%3Fencryption%3D${vlessEncryption}%26security%3Dreality%26type%3Dxhttp%26sni%3D${xrayVLESSRealityXHTTPSNI}%26fp%3Dchrome%26path%3D${path}%26mode%3D${xhttpMode}%26host%3D${xhttpHost}%26pbk%3D${currentRealityXHTTPPublicKey}%26sid%3D6ba85179e30d4fc2%26flow%3Dxtls-rprx-vision%23${email}\n"

    elif
        [[ "${type}" == "vlessgrpc" ]]
    then
        local defaultLink
        local clashMetaBlock
        local singBoxFilter

        defaultLink="vless://${id}@${add}:${port}?encryption=none&security=tls&type=grpc&host=${currentHost}&path=${currentPath}grpc&serviceName=${currentPath}grpc&fp=chrome&alpn=h2&sni=${currentHost}#${email}"
        clashMetaBlock=$(cat <<EOF
  - name: "${email}"
    type: vless
    server: ${add}
    port: ${port}
    uuid: ${id}
    udp: true
    tls: true
    network: grpc
    client-fingerprint: chrome
    servername: ${currentHost}
    grpc-opts:
      grpc-service-name: ${currentPath}grpc
EOF
)
        singBoxFilter=". += [{\"tag\":\"${email}\",\"type\": \"vless\",\"server\": \"${add}\",\"server_port\": ${port},\"uuid\": \"${id}\",\"tls\": {  \"enabled\": true,  \"server_name\": \"${currentHost}\",  \"utls\": {    \"enabled\": true,    \"fingerprint\": \"chrome\"  }},\"packet_encoding\": \"xudp\",\"transport\": {  \"type\": \"grpc\",  \"service_name\": \"${currentPath}grpc\"}}]"

        subscribeOutputTitle "通用格式：VLESS gRPC TLS"
        echoContent green "    vless://${id}@${add}:${port}?encryption=none&security=tls&type=grpc&host=${currentHost}&path=${currentPath}grpc&fp=chrome&serviceName=${currentPath}grpc&alpn=h2&sni=${currentHost}#${email}\n"

        subscribeOutputTitle "格式化明文：VLESS gRPC TLS"
        echoContent green "    协议类型:VLESS，地址:${add}，TLS域名/SNI:${currentHost}，端口:${port}，用户ID:${id}，安全:tls，传输方式:gRPC，alpn:h2，client-fingerprint: chrome（兼容模拟，不作为抗封锁保证）,serviceName:${currentPath}grpc，账户名:${email}\n"
        appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

        subscribeOutputTitle "二维码：VLESS gRPC TLS"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${add}%3A${port}%3Fencryption%3Dnone%26security%3Dtls%26type%3Dgrpc%26host%3D${currentHost}%26serviceName%3D${currentPath}grpc%26fp%3Dchrome%26path%3D${currentPath}grpc%26sni%3D${currentHost}%26alpn%3Dh2%23${email}"

    elif [[ "${type}" == "trojan" ]]; then
        # URLEncode
        subscribeOutputTitle "通用链接：Trojan TLS"
        echoContent green "    trojan://${id}@${currentHost}:${port}?peer=${currentHost}&fp=chrome&sni=${currentHost}&alpn=http/1.1#${currentHost}_Trojan\n"

        local defaultLink
        local clashMetaBlock
        local singBoxFilter
        defaultLink="trojan://${id}@${currentHost}:${port}?peer=${currentHost}&fp=chrome&sni=${currentHost}&alpn=http/1.1#${email}_Trojan"
        clashMetaBlock=$(cat <<EOF
  - name: "${email}"
    type: trojan
    server: ${currentHost}
    port: ${port}
    password: ${id}
    client-fingerprint: chrome
    udp: true
    sni: ${currentHost}
EOF
)
        singBoxFilter=". += [{\"tag\":\"${email}\",\"type\":\"trojan\",\"server\":\"${currentHost}\",\"server_port\":${port},\"password\":\"${id}\",\"tls\":{\"alpn\":[\"http/1.1\"],\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}}}]"
        appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

        subscribeOutputTitle "二维码：Trojan TLS"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=trojan%3a%2f%2f${id}%40${currentHost}%3a${port}%3fpeer%3d${currentHost}%26fp%3Dchrome%26sni%3d${currentHost}%26alpn%3Dhttp/1.1%23${email}\n"

    elif [[ "${type}" == "trojangrpc" ]]; then
        # URLEncode

        subscribeOutputTitle "通用链接：Trojan gRPC TLS"
        echoContent green "    trojan://${id}@${add}:${port}?encryption=none&peer=${currentHost}&fp=chrome&security=tls&type=grpc&sni=${currentHost}&alpn=h2&path=${currentPath}trojangrpc&serviceName=${currentPath}trojangrpc#${email}\n"
        local defaultLink
        local clashMetaBlock
        local singBoxFilter
        defaultLink="trojan://${id}@${add}:${port}?encryption=none&peer=${currentHost}&security=tls&type=grpc&fp=chrome&sni=${currentHost}&alpn=h2&path=${currentPath}trojangrpc&serviceName=${currentPath}trojangrpc#${email}"
        clashMetaBlock=$(cat <<EOF
  - name: "${email}"
    server: ${add}
    port: ${port}
    type: trojan
    password: ${id}
    network: grpc
    sni: ${currentHost}
    udp: true
    grpc-opts:
      grpc-service-name: ${currentPath}trojangrpc
EOF
)
        singBoxFilter=". += [{\"tag\":\"${email}\",\"type\":\"trojan\",\"server\":\"${add}\",\"server_port\":${port},\"password\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"transport\":{\"type\":\"grpc\",\"service_name\":\"${currentPath}trojangrpc\",\"idle_timeout\":\"15s\",\"ping_timeout\":\"15s\",\"permit_without_stream\":false},\"multiplex\":{\"enabled\":false,\"protocol\":\"smux\",\"max_streams\":32}}]"
        appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

        subscribeOutputTitle "二维码：Trojan gRPC TLS"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=trojan%3a%2f%2f${id}%40${add}%3a${port}%3Fencryption%3Dnone%26fp%3Dchrome%26security%3Dtls%26peer%3d${currentHost}%26type%3Dgrpc%26sni%3d${currentHost}%26path%3D${currentPath}trojangrpc%26alpn%3Dh2%26serviceName%3D${currentPath}trojangrpc%23${email}\n"

    elif [[ "${type}" == "hysteria" ]]; then
        subscribeOutputTitle "通用链接：Hysteria2 TLS"
        local clashMetaPortContent="port: ${port}"
        local uriPort=${singBoxHysteria2Port}
        local uriPortEncode=${singBoxHysteria2Port}
        if [[ "${port}" == *-* ]]; then
            clashMetaPortContent="ports: ${port}"
            uriPort=${port}
            uriPortEncode=${port//,/%2C}
        fi

        local defaultLink
        local clashMetaBlock
        local singBoxFilter
        defaultLink="hysteria2://${id}@${currentHost}:${uriPort}?peer=${currentHost}&insecure=0&sni=${currentHost}&alpn=h3#${email}"
        clashMetaBlock=$(cat <<EOF
  - name: "${email}"
    type: hysteria2
    server: ${currentHost}
    ${clashMetaPortContent}
    password: ${id}
    alpn:
        - h3
    sni: ${currentHost}
    up: "${hysteria2ClientUploadSpeed} Mbps"
    down: "${hysteria2ClientDownloadSpeed} Mbps"
EOF
)
        singBoxFilter=". += [{\"tag\":\"${email}\",\"type\":\"hysteria2\",\"server\":\"${currentHost}\",\"server_port\":${singBoxHysteria2Port},\"up_mbps\":${hysteria2ClientUploadSpeed},\"down_mbps\":${hysteria2ClientDownloadSpeed},\"password\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"alpn\":[\"h3\"]}}]"

        echoContent green "    ${defaultLink}\n"
        appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"
        subscribeOutputTitle "v2rayN：Hysteria2 TLS"
        echo "{\"server\": \"${currentHost}:${port}\",\"socks5\": { \"listen\": \"127.0.0.1:7798\", \"timeout\": 300},\"auth\":\"${id}\",\"tls\":{\"sni\":\"${currentHost}\"}}" | jq

        subscribeOutputTitle "二维码：Hysteria2 TLS"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=hysteria2%3A%2F%2F${id}%40${currentHost}%3A${uriPortEncode}%3Fpeer%3D${currentHost}%26insecure%3D0%26sni%3D${currentHost}%26alpn%3Dh3%23${email}\n"

    elif [[ "${type}" == "vlessReality" ]]; then
        local entryHost
        entryHost=$(realityEntryHost)

        local realitySNI=${xrayVLESSRealitySNI}
        local publicKey=${currentRealityPublicKey}
        local realityMldsa65Verify=${currentRealityMldsa65Verify}
        local vlessEncryption=none
        local vlessEncryptionStateFile=${PADM_VLESS_ENCRYPTION_STATE_FILE:-/etc/padm/xray/vless_encryption.json}
        if [[ "${coreInstallType}" == "1" && -f "${vlessEncryptionStateFile}" ]]; then
            vlessEncryption=$(jq -r '.encryption // "none"' "${vlessEncryptionStateFile}" 2>/dev/null)
        fi
        if [[ -z "${vlessEncryption}" || "${vlessEncryption}" == "null" ]]; then
            vlessEncryption=none
        fi

        if [[ "${coreInstallType}" == "2" ]]; then
            realitySNI=${singBoxVLESSRealityVisionSNI}
            publicKey=${singBoxVLESSRealityPublicKey}
        fi
        local defaultLink
        defaultLink=$(serializeVlessRealityVisionLink "${id}" "${entryHost}" "${port}" "${realitySNI}" "${publicKey}" "${realityMldsa65Verify}" "${email}" "${vlessEncryption}")
        subscribeOutputTitle "通用格式：VLESS Reality Vision"
        echoContent green "    ${defaultLink}\n"

        subscribeOutputTitle "格式化明文：VLESS Reality Vision"
        echoContent green "协议类型:VLESS reality，地址:${entryHost}，publicKey:${publicKey}，shortId: 6ba85179e30d4fc2，pqv=${realityMldsa65Verify}，Reality目标SNI：${realitySNI}，端口:${port}，用户ID:${id}，传输方式:tcp，账户名:${email}\n"
        appendDefaultSubscribeLine "${user}" "${defaultLink}"
        appendClashMetaSubscribeBlock "${user}" "  - name: \"${email}\"
    type: vless
    server: ${entryHost}
    port: ${port}
    uuid: ${id}
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: ${realitySNI}
    reality-opts:
      public-key: ${publicKey}
      short-id: 6ba85179e30d4fc2
    client-fingerprint: chrome"

        appendSingBoxSubscribeLocalConfig "${user}" ". += [{\"tag\":\"${email}\",\"type\":\"vless\",\"server\":\"${entryHost}\",\"server_port\":${port},\"uuid\":\"${id}\",\"flow\":\"xtls-rprx-vision\",\"tls\":{\"enabled\":true,\"server_name\":\"${realitySNI}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"},\"reality\":{\"enabled\":true,\"public_key\":\"${publicKey}\",\"short_id\":\"6ba85179e30d4fc2\"}},\"packet_encoding\":\"xudp\"}]"

        subscribeOutputTitle "二维码：VLESS Reality Vision"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${entryHost}%3A${port}%3Fencryption%3D${vlessEncryption}%26security%3Dreality%26type%3Dtcp%26sni%3D${realitySNI}%26fp%3Dchrome%26pbk%3D${publicKey}%26sid%3D6ba85179e30d4fc2%26flow%3Dxtls-rprx-vision%23${email}\n"

    elif [[ "${type}" == "vlessRealityGRPC" ]]; then
        local entryHost
        entryHost=$(realityEntryHost)
        local realitySNI=${xrayVLESSRealitySNI}
        local publicKey=${currentRealityPublicKey}
        local realityMldsa65Verify=${currentRealityMldsa65Verify}

        if [[ "${coreInstallType}" == "2" ]]; then
            realitySNI=${singBoxVLESSRealityGRPCSNI}
            publicKey=${singBoxVLESSRealityPublicKey}
        fi

        local defaultLink
        defaultLink=$(serializeVlessRealityGrpcLink "${id}" "${entryHost}" "${port}" "${realitySNI}" "${publicKey}" "${realityMldsa65Verify}" "${email}")
        subscribeOutputTitle "通用格式：VLESS Reality gRPC"
        echoContent green "    ${defaultLink}\n"

        subscribeOutputTitle "格式化明文：VLESS Reality gRPC"
        echoContent green "协议类型:VLESS reality，serviceName:grpc，地址:${entryHost}，publicKey:${publicKey}，shortId: 6ba85179e30d4fc2，Reality目标SNI：${realitySNI}，端口:${port}，用户ID:${id}，传输方式:gRPC，client-fingerprint：chrome（兼容模拟，Reality 伪装不依赖该项），账户名:${email}\n"
        appendDefaultSubscribeLine "${user}" "${defaultLink}"
        appendClashMetaSubscribeBlock "${user}" "  - name: \"${email}\"
    type: vless
    server: ${entryHost}
    port: ${port}
    uuid: ${id}
    network: grpc
    tls: true
    udp: true
    servername: ${realitySNI}
    reality-opts:
      public-key: ${publicKey}
      short-id: 6ba85179e30d4fc2
    grpc-opts:
      grpc-service-name: \"grpc\"
    client-fingerprint: chrome"

        appendSingBoxSubscribeLocalConfig "${user}" ". += [{\"tag\":\"${email}\",\"type\":\"vless\",\"server\":\"${entryHost}\",\"server_port\":${port},\"uuid\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${realitySNI}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"},\"reality\":{\"enabled\":true,\"public_key\":\"${publicKey}\",\"short_id\":\"6ba85179e30d4fc2\"}},\"packet_encoding\":\"xudp\",\"transport\":{\"type\":\"grpc\",\"service_name\":\"grpc\"}}]"

        subscribeOutputTitle "二维码：VLESS Reality gRPC"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${entryHost}%3A${port}%3Fencryption%3Dnone%26security%3Dreality%26pqv%3D${realityMldsa65Verify}%26type%3Dgrpc%26sni%3D${realitySNI}%26fp%3Dchrome%26pbk%3D${publicKey}%26sid%3D6ba85179e30d4fc2%26path%3Dgrpc%26serviceName%3Dgrpc%23${email}\n"
    elif [[ "${type}" == "tuic" ]]; then
        local tuicUUID=
        tuicUUID=${id%%_*}

        local tuicPassword=
        tuicPassword=${id#*_}

        if [[ -z "${email}" ]]; then
            errorCard "读取配置失败，请重新安装"
            exit 0
        fi

        subscribeOutputTitle "格式化明文：Tuic TLS"
        echoContent green "    协议类型:Tuic，地址:${currentHost}，端口：${port}，uuid：${tuicUUID}，password：${tuicPassword}，congestion-controller:${tuicAlgorithm}，alpn: h3，账户名:${email}\n"

        local defaultLink
        local clashMetaBlock
        local singBoxFilter
        defaultLink="tuic://${tuicUUID}:${tuicPassword}@${currentHost}:${port}?congestion_control=${tuicAlgorithm}&alpn=h3&sni=${currentHost}&udp_relay_mode=native&allow_insecure=0#${email}"
        clashMetaBlock=$(cat <<EOF
  - name: "${email}"
    server: ${currentHost}
    type: tuic
    port: ${port}
    uuid: ${tuicUUID}
    password: ${tuicPassword}
    alpn:
     - h3
    congestion-controller: ${tuicAlgorithm}
    udp-relay-mode: native
    disable-sni: false
    reduce-rtt: false
    sni: ${currentHost}
EOF
)
        singBoxFilter=". += [{\"tag\":\"${email}\",\"type\": \"tuic\",\"server\": \"${currentHost}\",\"server_port\": ${port},\"uuid\": \"${tuicUUID}\",\"password\": \"${tuicPassword}\",\"congestion_control\": \"${tuicAlgorithm}\",\"udp_relay_mode\": \"native\",\"zero_rtt_handshake\": false,\"tls\": {\"enabled\": true,\"server_name\": \"${currentHost}\",\"alpn\": [\"h3\"]}}]"

        appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"
        subscribeOutputTitle "v2rayN：Tuic TLS"
        echo "{\"relay\": {\"server\": \"${currentHost}:${port}\",\"uuid\": \"${tuicUUID}\",\"password\": \"${tuicPassword}\",\"ip\": \"${currentHost}\",\"congestion_control\": \"${tuicAlgorithm}\",\"alpn\": [\"h3\"]},\"local\": {\"server\": \"127.0.0.1:7798\"},\"log_level\": \"warn\"}" | jq

        subscribeOutputTitle "二维码：Tuic TLS"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=tuic%3A%2F%2F${tuicUUID}%3A${tuicPassword}%40${currentHost}%3A${port}%3Fcongestion_control%3D${tuicAlgorithm}%26alpn%3Dh3%26sni%3D${currentHost}%26udp_relay_mode%3Dnative%26allow_insecure%3D0%23${email}\n"
    elif [[ "${type}" == "naive" ]]; then
        subscribeOutputTitle "通用链接：Naive TLS"
        echoContent green "    NaiveProxy 适合需要 TLS 指纹抗性的场景；需要真实域名和可信证书，不是无域名 Reality 替代。\n"

        local defaultLink
        defaultLink="naive+https://${email}:${id}@${currentHost}:${port}?padding=true#${email}"

        echoContent green "    ${defaultLink}\n"
        appendDefaultSubscribeLine "${user}" "${defaultLink}"
        subscribeOutputTitle "二维码：Naive TLS"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=naive%2Bhttps%3A%2F%2F${email}%3A${id}%40${currentHost}%3A${port}%3Fpadding%3Dtrue%23${email}\n"
    elif [[ "${type}" == "vmessHTTPUpgrade" ]]; then
        qrCodeBase64Default=$(echo -n "{\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"httpupgrade\",\"add\":\"${add}\",\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}" | base64 -w 0)
        qrCodeBase64Default="${qrCodeBase64Default// /}"

        subscribeOutputTitle "通用 JSON：VMess HTTPUpgrade TLS"
        echoContent green "    {\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"httpupgrade\",\"add\":\"${add}\",\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}\n"
        subscribeOutputTitle "通用链接：VMess HTTPUpgrade TLS"
        echoContent green "    vmess://${qrCodeBase64Default}\n"
        subscribeOutputTitle "二维码：VMess HTTPUpgrade TLS"

        local defaultLink
        local clashMetaBlock
        local singBoxFilter
        defaultLink="vmess://${qrCodeBase64Default}"
        clashMetaBlock=$(cat <<EOF
  - name: "${email}"
    type: vmess
    server: ${add}
    port: ${port}
    uuid: ${id}
    alterId: 0
    cipher: auto
    udp: true
    tls: true
    client-fingerprint: chrome
    servername: ${currentHost}
    network: ws
    ws-opts:
     path: ${path}
     headers:
       Host: ${currentHost}
     v2ray-http-upgrade: true
EOF
)
        singBoxFilter=". += [{\"tag\":\"${email}\",\"type\":\"vmess\",\"server\":\"${add}\",\"server_port\":${port},\"uuid\":\"${id}\",\"security\":\"auto\",\"alter_id\":0,\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"packet_encoding\":\"packetaddr\",\"transport\":{\"type\":\"httpupgrade\",\"path\":\"${path}\"}}]"
        appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vmess://${qrCodeBase64Default}\n"

    elif [[ "${type}" == "anytls" ]]; then
        subscribeOutputTitle "通用链接：AnyTLS"

        subscribeOutputTitle "格式化明文：AnyTLS"
        echoContent green "协议类型:anytls，地址:${currentHost}，端口:${singBoxAnyTLSPort}，用户ID:${id}，传输方式:tcp，账户名:${email}\n"

        local defaultLink
        local clashMetaBlock
        local singBoxFilter
        defaultLink="anytls://${id}@${currentHost}:${singBoxAnyTLSPort}?peer=${currentHost}&insecure=0&sni=${currentHost}#${email}"
        clashMetaBlock=$(cat <<EOF
  - name: "${email}"
    type: anytls
    port: ${singBoxAnyTLSPort}
    server: ${currentHost}
    password: ${id}
    client-fingerprint: chrome
    udp: true
    sni: ${currentHost}
    alpn:
      - h2
      - http/1.1
EOF
)
        singBoxFilter=". += [{\"tag\":\"${email}\",\"type\":\"anytls\",\"server\":\"${currentHost}\",\"server_port\":${singBoxAnyTLSPort},\"password\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\"}}]"

        echoContent green "    ${defaultLink}\n"
        appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

        subscribeOutputTitle "二维码：AnyTLS"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=anytls%3A%2F%2F${id}%40${currentHost}%3A${singBoxAnyTLSPort}%3Fpeer%3D${currentHost}%26insecure%3D0%26sni%3D${currentHost}%23${email}\n"
    fi

}


# 服务器源管理
normalizeSubscriptionSourceInput() {
    return 1
}

remoteSubscribeFile() {
    subscriptionGroupsFile
}

listRemoteSubscribeSources() {
    listSubscriptionSources | awk -F ':' '$3 != "main" {print $5":"$6":"$2":"$4}'
}

# 添加服务器源
addSubscribeMenu() {
    echoContent title "\n┌─ 服务器源管理 ─────────────────────────────────────"
    menuLine "主控端管理被控服务器：粘贴被控接入凭据添加，或删除已有被控"
    menuLine "被控不需要安装公网订阅服务；只需在 多服务器：被控 生成接入凭据"
    menuItem 1 "添加被控服务器" "粘贴被控凭据，新增 WireGuard Peer 和服务器源"
    menuItem 2 "移除被控服务器" "删除已有被控来源"
    menuReturnItem 3 "返回主控菜单" "回到上级菜单"
    menuClose
    autoRead server_source_menu "请选择:" addSubscribeStatus
    if [[ "${addSubscribeStatus}" == "1" ]]; then
        addOtherSubscribe
    elif [[ "${addSubscribeStatus}" == "2" ]]; then
        local sourceId=
        echoContent title "\n┌─ 移除被控服务器 ───────────────────────────────────"
        menuLine "当前可移除被控服务器："
        listSubscriptionSources | awk -F ':' '$3 != "main" {print "│ " NR ". " $0}'
        menuClose
        autoRead delete_subscription_source "请选择要删除的被控服务器源ID:" sourceId
        if [[ -z "${sourceId}" ]]; then
            errorCard "被控服务器源 ID 不可以为空"
            addSubscribeMenu
            return
        fi
        removeSubscriptionSourceState "${sourceId}"
        successCard "被控服务器删除成功"
        subscribe
    elif [[ "${addSubscribeStatus}" == "3" ]]; then
        subscribe
    else
        errorCard "选择错误，请重新选择"
        addSubscribeMenu
    fi
}

# 添加被控服务器
addOtherSubscribe() {
    local credential=
    local credentialJson=
    local host=
    local port=
    local alias=
    echoContent title "\n┌─ 添加被控服务器 ───────────────────────────────────"
    menuLine "在被控服务器进入 多服务器：被控 -> 查看本机被控接入凭据"
    menuLine "被控无需安装公网订阅服务；初始化被控会启用 WireGuard 内网控制面"
    menuLine "主控端只需要粘贴被控接入凭据，再设置一个本地别名"
    menuLine "被控接入凭据已包含 WireGuard 内网地址、控制端口、Token 和公钥"
    menuClose
    autoRead subscription_control_credential "请粘贴被控接入凭据:" credential
    if [[ -z "${credential}" ]]; then
        errorCard "被控接入凭据不可为空"
        addOtherSubscribe
        return
    fi
    credentialJson=$(subscriptionWireGuardCredentialDecode "${credential}") || {
        errorCard "被控接入凭据无效，请复制被控端完整输出"
        addOtherSubscribe
        return
    }
    if [[ "$(jq -r '.kind' <<<"${credentialJson}")" != "controlled" ]]; then
        errorCard "请粘贴被控接入凭据"
        addOtherSubscribe
        return
    fi
    host=$(subscriptionWireGuardAddressHost "$(jq -r '.address' <<<"${credentialJson}")")
    port=$(jq -r '.control_port' <<<"${credentialJson}")
    autoRead subscription_source_alias "请输入被控服务器别名[英文/数字/短横线，例 hk-1]:" alias
    if [[ -z "${alias}" ]] || ! echo "${alias}" | grep -qE '^[a-zA-Z0-9_-]+$'; then
        errorCard "别名只能使用英文、数字、短横线或下划线"
        addOtherSubscribe
        return
    fi
    if subscriptionRemoteSourceSelfReference "$(jq -n --arg host "${host}" '{host:$host}')"; then
        errorCard "被控服务器指向当前主控 WireGuard 地址，已拒绝添加，避免递归同步"
        addOtherSubscribe
        return
    fi
    if ! subscriptionWireGuardAddPeerFromCredential "${alias}" "${credentialJson}"; then
        errorCard "被控服务器添加失败"
        addOtherSubscribe
        return
    fi
    successCard "被控服务器已添加" "WireGuard 内网地址：${host}:${port}" "别名：${alias}" "已保存 Token 和 Peer，可继续测试被控连接"
    subscribe
}




ensureSubscriptionControlNginxLocation() {
    return 1
}


writeSubscribeNginxConfig() {
    local targetPath="${nginxConfigPath}subscribe.conf"
    local tmpPath="${targetPath}.tmp"
    mkdir -p "$(dirname "${targetPath}")"
    cat >"${tmpPath}"
    if command -v nginx >/dev/null 2>&1; then
        local backupPath="${targetPath}.bak"
        [[ -f "${targetPath}" ]] && cp "${targetPath}" "${backupPath}"
        mv "${tmpPath}" "${targetPath}"
        if ! nginx -t >/tmp/padm-subscribe-nginx-test.log 2>&1; then
            if [[ -f "${backupPath}" ]]; then
                mv "${backupPath}" "${targetPath}"
            else
                rm -f "${targetPath}"
            fi
            return 1
        fi
        rm -f "${backupPath}"
    else
        mv "${tmpPath}" "${targetPath}"
    fi
}

availableSubscribeCertificateDomain() {
    local certDir="${PADM_TLS_DIR:-/etc/padm/tls}"
    local certFile domainName
    for certFile in "${certDir}"/*.crt; do
        [[ -s "${certFile}" ]] || continue
        domainName=$(basename "${certFile}" .crt)
        [[ -s "${certDir}/${domainName}.key" ]] || continue
        printf '%s\n' "${domainName}"
        return 0
    done
    return 1
}

resolveSubscribeServerName() {
    if [[ -n "${currentHost:-}" ]]; then
        printf '%s\n' "${currentHost}"
        return 0
    fi
    if [[ -n "${domain:-}" ]]; then
        printf '%s\n' "${domain}"
        return 0
    fi
    availableSubscribeCertificateDomain
}

# 安装订阅服务
installSubscribe() {
    readNginxSubscribe
    local nginxSubscribeListen=
    local nginxSubscribeSSL=
    local serverName=
    local SSLType=
    local listenIPv6=
    local subscribeServerName=
    if [[ -n "${AUTO_SUBSCRIBE_PORT}" && "${subscribePort}" != "${AUTO_SUBSCRIBE_PORT}" ]]; then
        subscribePort=
    fi
    if [[ -z "${subscribePort}" ]]; then

        nginxVersion=$(nginx -v 2>&1)

        if echo "${nginxVersion}" | grep -q "not found" || [[ -z "${nginxVersion}" ]]; then
            menuLine "$(uiStyle warn "未检测到 nginx，无法使用订阅服务")"
            autoConfirm install_nginx "未检测到 nginx，是否安装？" n installNginxStatus
            if [[ "${installNginxStatus}" == "y" ]]; then
                installNginxTools
            else
                errorCard "放弃安装nginx\n"
                exit 0
            fi
        fi
        echoContent title "开始配置订阅，请输入订阅的端口"

        mapfile -t result < <(initSingBoxPort "${AUTO_SUBSCRIBE_PORT:-${subscribePort}}" false)
        PADM_NGINX_BLOG_REINSTALL_PROMPT=false nginxBlog
        echo
        subscribeServerName=$(resolveSubscribeServerName || true)
        if [[ -z "${subscribeServerName}" ]]; then
            errorCard "订阅服务需要 HTTPS 域名" "未发现可用于订阅服务的 TLS 域名或证书" "请先在 站点与证书 中配置域名证书，或安装时提供 --domain"
            return 1
        fi

        SSLType="ssl"
        serverName="server_name ${subscribeServerName};"
        nginxSubscribeSSL="ssl_certificate ${PADM_TLS_DIR:-/etc/padm/tls}/${subscribeServerName}.crt;ssl_certificate_key ${PADM_TLS_DIR:-/etc/padm/tls}/${subscribeServerName}.key;"
        if hasIPv6Connectivity; then
            listenIPv6="listen [::]:${result[-1]} ${SSLType};"
        fi
        if echo "${nginxVersion}" | grep -q "1.25" && [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $3}') -gt 0 ]] || [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $2}') -gt 25 ]]; then
            nginxSubscribeListen="listen ${result[-1]} ${SSLType} so_keepalive=on;http2 on;${listenIPv6}"
        else
            nginxSubscribeListen="listen ${result[-1]} ${SSLType} so_keepalive=on;${listenIPv6}"
        fi

        if ! writeSubscribeNginxConfig <<EOF
server {
    ${nginxSubscribeListen}
    ${serverName}
    ${nginxSubscribeSSL}
    ssl_protocols              TLSv1.2 TLSv1.3;
    ssl_ciphers                TLS13_AES_128_GCM_SHA256:TLS13_AES_256_GCM_SHA384:TLS13_CHACHA20_POLY1305_SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers  on;

    resolver                   1.1.1.1 valid=60s;
    resolver_timeout           2s;
    client_max_body_size 100m;
    root ${nginxStaticPath};
    location ~ ^/s/(clashMeta|default|clashMetaProfiles|sing-box|sing-box_profiles)/(.*) {
        default_type 'text/plain; charset=utf-8';
        alias /etc/padm/subscribe/\$1/\$2;
    }
    location / {
    }
}
EOF
        then
            errorCard "订阅 Nginx 配置校验失败，已回滚"
            return 1
        fi
        installSubscriptionControlService
        bootStartup nginx
        handleNginx stop
        handleNginx start
    fi
    if [[ -z $(pgrep -f "nginx") ]]; then
        handleNginx start
    fi
}

# 卸载订阅服务
unInstallSubscribe() {
    if [[ ! -e "${nginxConfigPath}subscribe.conf" && ! -L "${nginxConfigPath}subscribe.conf" ]]; then
        return 0
    fi
    rm -rf "${nginxConfigPath}subscribe.conf" >/dev/null 2>&1
}


fetchRemoteSubscribeContent() {
    local url=$1
    curl -fsSL --connect-timeout 5 --max-time 15 "${url}" 2>/dev/null
}

appendUniqueLines() {
    local content=$1
    local targetPath=$2
    local line

    touch "${targetPath}"
    while IFS= read -r line; do
        if [[ -n "${line}" ]] && ! grep -Fxq -- "${line}" "${targetPath}"; then
            echo "${line}" >>"${targetPath}"
        fi
    done <<<"${content}"
}

mergeSingBoxSubscribeOutbounds() {
    local targetPath=$1
    local remoteContent=$2
    local tmpPath="${targetPath}.tmp"
    local remoteTmpPath="${targetPath}.remote.tmp"

    echo "${remoteContent}" >"${remoteTmpPath}"
    if ! jq -s '.[0] as $local | .[1] as $remote | $local + ($remote | map(select(.tag as $tag | ($local | map(.tag) | index($tag) | not))))' "${targetPath}" "${remoteTmpPath}" >"${tmpPath}"; then
        rm -f "${remoteTmpPath}" "${tmpPath}" >/dev/null 2>&1
        return 1
    fi
    mv "${tmpPath}" "${targetPath}"
    rm -f "${remoteTmpPath}" >/dev/null 2>&1
}

# 更新远程订阅源
updateRemoteSubscribe() {
    local emailMD5=$1
    local email=$2
    local line=
    local tmpDir stageDir publicBase localBase defaultTarget clashTarget singBoxTarget

    padmCreateTempPath tmpDir -d /tmp/padm-remote-subscribe-fetch.XXXXXX || return 1
    padmCreateTempPath stageDir -d /tmp/padm-remote-subscribe-stage.XXXXXX || { padmRemoveCleanupPath "${tmpDir}"; return 1; }
    publicBase=$(subscribePublicBaseDir)
    localBase=$(subscribeLocalBaseDir)
    mkdir -p "${stageDir}/default" "${stageDir}/clashMeta" "${stageDir}/sing-box"
    defaultTarget="${stageDir}/default/${emailMD5}"
    clashTarget="${stageDir}/clashMeta/${emailMD5}"
    singBoxTarget="${stageDir}/sing-box/${email}"
    [[ -f "${publicBase}/default/${emailMD5}" ]] && cp "${publicBase}/default/${emailMD5}" "${defaultTarget}" || : >"${defaultTarget}"
    [[ -f "${publicBase}/clashMeta/${emailMD5}" ]] && cp "${publicBase}/clashMeta/${emailMD5}" "${clashTarget}" || : >"${clashTarget}"
    [[ -f "${localBase}/sing-box/${email}" ]] && cp "${localBase}/sing-box/${email}" "${singBoxTarget}" || printf '[]\n' >"${singBoxTarget}"

    while IFS= read -r line; do
        if [[ -z "${line}" ]]; then
            continue
        fi
        local subscribeType=
        local serverAlias=
        local remoteUrl=
        local clashMetaProxies=
        local default=
        local singBoxSubscribe=
        local clashFile="${tmpDir}/clash"
        local defaultFile="${tmpDir}/default"
        local singBoxFile="${tmpDir}/sing-box"
        local clashPid defaultPid singBoxPid

        IFS=':' read -r remoteHost remotePort serverAlias subscribeType <<<"${line}"
        remoteUrl="${remoteHost}:${remotePort}"

        fetchRemoteSubscribeContent "${subscribeType}://${remoteUrl}/s/clashMeta/${emailMD5}" >"${clashFile}" & clashPid=$!
        fetchRemoteSubscribeContent "${subscribeType}://${remoteUrl}/s/default/${emailMD5}" >"${defaultFile}" & defaultPid=$!
        fetchRemoteSubscribeContent "${subscribeType}://${remoteUrl}/s/sing-box_profiles/${emailMD5}" >"${singBoxFile}" & singBoxPid=$!
        wait "${clashPid}" 2>/dev/null || true
        wait "${defaultPid}" 2>/dev/null || true
        wait "${singBoxPid}" 2>/dev/null || true

        clashMetaProxies=$(sed '/proxies:/d' "${clashFile}" | sed "s/\"${email}/\"${email}_${serverAlias}/g")
        if [[ -n "${clashMetaProxies}" && "${clashMetaProxies}" != *nginx* ]]; then
            appendUniqueLines "${clashMetaProxies}" "${clashTarget}"
            successCard "clashMeta订阅 ${remoteUrl}:${email} 更新成功"
        else
            errorCard "clashMeta订阅 ${remoteUrl}:${email} 拉取失败或不存在"
        fi

        default=$(<"${defaultFile}")
        if [[ -n "${default}" && "${default}" != *nginx* ]]; then
            default=$(echo "${default}" | { base64 -d 2>/dev/null || true; } | sed "s/#${email}/#${email}_${serverAlias}/g")
            if [[ -n "${default}" ]]; then
                appendUniqueLines "${default}" "${defaultTarget}"
                successCard "通用订阅 ${remoteUrl}:${email} 更新成功"
            else
                errorCard "通用订阅 ${remoteUrl}:${email} 解码失败"
            fi
        else
            errorCard "通用订阅 ${remoteUrl}:${email} 拉取失败或不存在"
        fi

        singBoxSubscribe=$(<"${singBoxFile}")
        if [[ -n "${singBoxSubscribe}" && "${singBoxSubscribe}" != *nginx* ]] && echo "${singBoxSubscribe}" | jq empty >/dev/null 2>&1; then
            if ! singBoxSubscribe=$(jq --arg email "${email}" --arg alias "${serverAlias}" 'map(if ((.tag // "") | startswith($email)) then .tag = ($email + "_" + $alias + (.tag[($email | length):])) else . end)' <<<"${singBoxSubscribe}"); then
                padmRemoveCleanupPath "${tmpDir}"
                padmRemoveCleanupPath "${stageDir}"
                return 1
            fi
            if ! mergeSingBoxSubscribeOutbounds "${singBoxTarget}" "${singBoxSubscribe}"; then
                padmRemoveCleanupPath "${tmpDir}"
                padmRemoveCleanupPath "${stageDir}"
                return 1
            fi
            successCard "sing-box订阅 ${remoteUrl}:${email} 更新成功"
        else
            errorCard "sing-box订阅 ${remoteUrl}:${email} 拉取失败或不存在"
        fi
        rm -f "${clashFile}" "${defaultFile}" "${singBoxFile}"
    done < <(listRemoteSubscribeSources)

    mkdir -p "${publicBase}/default" "${publicBase}/clashMeta" "${localBase}/sing-box"
    mv "${defaultTarget}" "${publicBase}/default/${emailMD5}"
    mv "${clashTarget}" "${publicBase}/clashMeta/${emailMD5}"
    mv "${singBoxTarget}" "${localBase}/sing-box/${email}"
    padmRemoveCleanupPath "${tmpDir}"
    padmRemoveCleanupPath "${stageDir}"
}

subscribeSectionTitle() {
    echoContent title "\n┌─ $1 ─────────────────────────────────────"
    [[ -n "${2:-}" ]] && menuLine "$2"
    menuClose
}

subscribeAccountTitle() {
    echoContent title "\n┌─ 订阅账号 ─────────────────────────────────────────"
    menuLine "账号：$1"
    menuClose
}

# 订阅账号展示
showAccounts() {
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    readSingBoxConfig

    echo
    progressCard "$1" "账号"

    initSubscribeLocalConfig
    # VLESS TCP
    if currentProtocolHas 0; then

        subscribeSectionTitle "VLESS TCP TLS Vision" "传统 TLS 兼容方案"
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}02_VLESS_TCP_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            subscribeAccountTitle "${email}"
            echo
            defaultBase64Code vlesstcp "${currentDefaultPort}${singBoxVLESSVisionPort}" "${email}" "$(echo "${user}" | jq -r .id//.uuid)"
        done
    fi

    # VLESS WS
    if currentProtocolHas 1; then
        subscribeSectionTitle "VLESS WS TLS" "兼容旧客户端，不作为新手推荐"

        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}03_VLESS_WS_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            local vlessWSPort=${currentDefaultPort}
            if [[ "${coreInstallType}" == "2" ]]; then
                vlessWSPort="${singBoxVLESSWSPort}"
            fi
            echo
            local path="${currentPath}ws"

            if [[ ${coreInstallType} == "1" ]]; then
                path="/${currentPath}ws"
            elif [[ "${coreInstallType}" == "2" ]]; then
                path="${singBoxVLESSWSPath}"
            fi

            local count=
            while read -r line; do
                subscribeAccountTitle "${email}${count}"
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vlessws "${vlessWSPort}" "${email}${count}" "$(echo "${user}" | jq -r .id//.uuid)" "${line}" "${path}"
                    count=$((count + 1))
                    echo
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')
        done
    fi
    # trojan grpc
    if currentProtocolHas 2; then
        subscribeSectionTitle "Trojan gRPC TLS" "兼容旧客户端，不作为新手推荐"
        jq .inbounds[0].settings.clients ${configPath}04_trojan_gRPC_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email)
            local count=
            while read -r line; do
                subscribeAccountTitle "${email}${count}"
                echo
                if [[ -n "${line}" ]]; then
                    defaultBase64Code trojangrpc "${currentDefaultPort}" "${email}${count}" "$(echo "${user}" | jq -r .password)" "${line}"
                    count=$((count + 1))
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')

        done
    fi
    # VMess WS
    if currentProtocolHas 3; then
        subscribeSectionTitle "VMess WS TLS" "兼容旧客户端，不作为新手推荐"
        local path="${currentPath}vws"
        if [[ ${coreInstallType} == "1" ]]; then
            path="/${currentPath}vws"
        elif [[ "${coreInstallType}" == "2" ]]; then
            path="${singBoxVMessWSPath}"
        fi
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}05_VMess_WS_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            local vmessPort=${currentDefaultPort}
            if [[ "${coreInstallType}" == "2" ]]; then
                vmessPort="${singBoxVMessWSPort}"
            fi

            local count=
            while read -r line; do
                subscribeAccountTitle "${email}${count}"
                echo
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vmessws "${vmessPort}" "${email}${count}" "$(echo "${user}" | jq -r .id//.uuid)" "${line}" "${path}"
                    count=$((count + 1))
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')
        done
    fi

    # trojan tcp
    if currentProtocolHas 4; then
        subscribeSectionTitle "Trojan TLS" "不推荐"
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}04_trojan_TCP_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)
            subscribeAccountTitle "${email}"

            defaultBase64Code trojan "${currentDefaultPort}${singBoxTrojanPort}" "${email}" "$(echo "${user}" | jq -r .password)"
        done
    fi
    # VLESS grpc
    if currentProtocolHas 5; then
        subscribeSectionTitle "VLESS gRPC TLS" "兼容旧客户端，不作为新手推荐"
        jq .inbounds[0].settings.clients ${configPath}06_VLESS_gRPC_inbounds.json | jq -c '.[]' | while read -r user; do

            local email=
            email=$(echo "${user}" | jq -r .email)

            local count=
            while read -r line; do
                subscribeAccountTitle "${email}${count}"
                echo
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vlessgrpc "${currentDefaultPort}" "${email}${count}" "$(echo "${user}" | jq -r .id)" "${line}"
                    count=$((count + 1))
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')

        done
    fi
    # hysteria2
    if currentProtocolHas 6 || [[ -n "${hysteriaPort}" ]]; then
        readPortHopping "hysteria2" "${singBoxHysteria2Port}"
        subscribeSectionTitle "Hysteria2 TLS" "UDP/移动网络可选"
        local path="${configPath}"
        if [[ "${coreInstallType}" == "1" ]]; then
            path="${singBoxConfigPath}"
        fi
        local hysteria2DefaultPort=
        if [[ -n "${hysteria2PortHoppingStart}" && -n "${hysteria2PortHoppingEnd}" ]]; then
            hysteria2DefaultPort="${hysteria2PortHopping}"
        else
            hysteria2DefaultPort=${singBoxHysteria2Port}
        fi

        jq -r -c '.inbounds[]|.users[]' "${path}06_hysteria2_inbounds.json" | while read -r user; do
            subscribeAccountTitle "$(echo "${user}" | jq -r .name)"
            echo
            defaultBase64Code hysteria "${hysteria2DefaultPort}" "$(echo "${user}" | jq -r .name)" "$(echo "${user}" | jq -r .password)"
        done

    fi

    # VLESS Reality Vision
    if currentProtocolHas 7; then
        subscribeSectionTitle "VLESS reality_vision" "推荐"
        jq .inbounds[1].settings.clients//.inbounds[0].users ${configPath}07_VLESS_vision_reality_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            subscribeAccountTitle "${email}"
            echo
            local realityVisionPort="${singBoxVLESSRealityVisionPort:-${xrayVLESSRealityPort}}"
            local streamPublicPort
            streamPublicPort=$(realityStreamPublicPortForProtocol vision)
            if [[ "${coreInstallType}" == "1" && -n "${streamPublicPort}" ]]; then
                realityVisionPort=${streamPublicPort}
            fi
            defaultBase64Code vlessReality "${realityVisionPort}" "${email}" "$(echo "${user}" | jq -r .id//.uuid)"
        done
    fi
    # VLESS Reality gRPC
    if currentProtocolHas 8; then
        subscribeSectionTitle "VLESS reality_gRPC" "推荐"
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}08_VLESS_vision_gRPC_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            subscribeAccountTitle "${email}"
            echo
            local realityGRPCPort="${singBoxVLESSRealityGRPCPort:-${xrayVLESSRealityPort}}"
            defaultBase64Code vlessRealityGRPC "${realityGRPCPort}" "${email}" "$(echo "${user}" | jq -r .id//.uuid)"
        done
    fi
    # TUIC
    if currentProtocolHas 9 || [[ -n "${tuicPort}" ]]; then
        subscribeSectionTitle "Tuic TLS" "UDP/移动网络可选"
        local path="${configPath}"
        if [[ "${coreInstallType}" == "1" ]]; then
            path="${singBoxConfigPath}"
        fi
        jq -r -c '.inbounds[].users[]' "${path}09_tuic_inbounds.json" | while read -r user; do
            subscribeAccountTitle "$(echo "${user}" | jq -r .name)"
            echo
            defaultBase64Code tuic "${singBoxTuicPort}" "$(echo "${user}" | jq -r .name)" "$(echo "${user}" | jq -r .uuid)_$(echo "${user}" | jq -r .password)"
        done

    fi
    # Naive
    if currentProtocolHas 10 || [[ -n "${singBoxNaivePort}" ]]; then
        subscribeSectionTitle "naive TLS" "推荐，不支持ClashMeta"

        jq -r -c '.inbounds[]|.users[]' "${configPath}10_naive_inbounds.json" | while read -r user; do
            subscribeAccountTitle "$(echo "${user}" | jq -r .username)"
            echo
            defaultBase64Code naive "${singBoxNaivePort}" "$(echo "${user}" | jq -r .username)" "$(echo "${user}" | jq -r .password)"
        done

    fi
    # VMess HTTPUpgrade
    if currentProtocolHas 11; then
        subscribeSectionTitle "VMess HTTPUpgrade TLS" "兼容旧客户端，不作为新手推荐"
        local path="${currentPath}vws"
        if [[ ${coreInstallType} == "1" ]]; then
            path="/${currentPath}vws"
        elif [[ "${coreInstallType}" == "2" ]]; then
            path="${singBoxVMessHTTPUpgradePath}"
        fi
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}11_VMess_HTTPUpgrade_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            local vmessHTTPUpgradePort=${currentDefaultPort}
            if [[ "${coreInstallType}" == "2" ]]; then
                vmessHTTPUpgradePort="${singBoxVMessHTTPUpgradePort}"
            fi

            local count=
            while read -r line; do
                subscribeAccountTitle "${email}${count}"
                echo
                if [[ -n "${line}" ]]; then
                    defaultBase64Code vmessHTTPUpgrade "${vmessHTTPUpgradePort}" "${email}${count}" "$(echo "${user}" | jq -r .id//.uuid)" "${line}" "${path}"
                    count=$((count + 1))
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')
        done
    fi
    # VLESS Reality XHTTP
    if currentProtocolHas 12; then
        subscribeSectionTitle "VLESS Reality XHTTP" "CDN推荐"

        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}12_VLESS_XHTTP_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)
            echo
            local path
            path=$(xrayRealityXHTTPSetting path "/${currentPath}xHTTP")

            local count=
            while read -r line; do
                subscribeAccountTitle "${email}${count}"
                if [[ -z "${line}" ]]; then
                    line=$(realityEntryHost)
                fi
                if [[ -n "${line}" ]]; then
                    local xhttpPort="${xrayVLESSRealityXHTTPort}"
                    local streamPublicPort
                    streamPublicPort=$(realityStreamPublicPortForProtocol xhttp)
                    if [[ -n "${streamPublicPort}" ]]; then
                        xhttpPort=${streamPublicPort}
                    fi
                    defaultBase64Code vlessXHTTP "${xhttpPort}" "${email}${count}" "$(echo "${user}" | jq -r .id//.uuid)" "${line}" "${path}"
                    count=$((count + 1))
                    echo
                fi
            done < <(echo "${currentCDNAddress}" | tr ',' '\n')
        done
    fi
    # AnyTLS
    if currentProtocolHas 13; then
        subscribeSectionTitle "AnyTLS" "TLS 兼容协议"

        jq -r -c '.inbounds[]|.users[]' "${configPath}13_anytls_inbounds.json" | while read -r user; do
            subscribeAccountTitle "$(echo "${user}" | jq -r .name)"
            echo
            defaultBase64Code anytls "${singBoxAnyTLSPort}" "$(echo "${user}" | jq -r .name)" "$(echo "${user}" | jq -r .password)"
        done

    fi
}
