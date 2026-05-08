#!/usr/bin/env bash

subscribeLocalBaseDir() {
    printf '%s' "${PADM_SUBSCRIBE_LOCAL_DIR:-/etc/padm/subscribe_local}"
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

appendSingBoxSubscribeLocalConfig() {
    local user=$1
    local jqFilter=$2
    local targetPath="$(subscribeLocalBaseDir)/sing-box/${user}"
    local singBoxSubscribeLocalConfig=

    singBoxSubscribeLocalConfig=$(jq -r "${jqFilter}" "${targetPath}")
    echo "${singBoxSubscribeLocalConfig}" | jq . >"${targetPath}"
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
    user=$(echo "${email}" | awk -F "[-]" '{print $1}')
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

        echoContent yellow " ---> 通用格式(VLESS+TCP+TLS_Vision)"
        echoContent green "    vless://${id}@${currentHost}:${port}?encryption=none&security=tls&fp=chrome&type=tcp&host=${currentHost}&headerType=none&sni=${currentHost}&flow=xtls-rprx-vision#${email}\n"

        echoContent yellow " ---> 格式化明文(VLESS+TCP+TLS_Vision)"
        echoContent green "协议类型:VLESS，地址:${currentHost}，端口:${port}，用户ID:${id}，安全:tls，client-fingerprint: chrome，传输方式:tcp，flow:xtls-rprx-vision，账户名:${email}\n"
        appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

        echoContent yellow " ---> 二维码 VLESS(VLESS+TCP+TLS_Vision)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${currentHost}%3A${port}%3Fencryption%3Dnone%26fp%3Dchrome%26security%3Dtls%26type%3Dtcp%26${currentHost}%3D${currentHost}%26headerType%3Dnone%26sni%3D${currentHost}%26flow%3Dxtls-rprx-vision%23${email}\n"

    elif [[ "${type}" == "vmessws" ]]; then
        qrCodeBase64Default=$(echo -n "{\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"ws\",\"add\":\"${add}\",\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}" | base64 -w 0)
        qrCodeBase64Default="${qrCodeBase64Default// /}"

        echoContent yellow " ---> 通用json(VMess+WS+TLS)"
        echoContent green "    {\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"ws\",\"add\":\"${add}\",\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}\n"
        echoContent yellow " ---> 通用vmess(VMess+WS+TLS)链接"
        echoContent green "    vmess://${qrCodeBase64Default}\n"
        echoContent yellow " ---> 二维码 vmess(VMess+WS+TLS)"

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

        echoContent yellow " ---> 通用格式(VLESS+WS+TLS)"
        echoContent green "    ${defaultLink}\n"

        echoContent yellow " ---> 格式化明文(VLESS+WS+TLS)"
        echoContent green "    协议类型:VLESS，地址:${add}，TLS域名/SNI:${currentHost}，端口:${port}，client-fingerprint: chrome,用户ID:${id}，安全:tls，传输方式:ws，路径:${path}，账户名:${email}\n"
        appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

        echoContent yellow " ---> 二维码 VLESS(VLESS+WS+TLS)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${add}%3A${port}%3Fencryption%3Dnone%26security%3Dtls%26type%3Dws%26host%3D${currentHost}%26fp%3Dchrome%26sni%3D${currentHost}%26path%3D${path}%23${email}"

    elif [[ "${type}" == "vlessXHTTP" ]]; then

        echoContent yellow " ---> 通用格式(VLESS+reality+XHTTP)"
        echoContent green "    vless://${id}@${add}:${port}?encryption=none&security=reality&type=xhttp&sni=${xrayVLESSRealityXHTTPSNI}&host=${xrayVLESSRealityXHTTPSNI}&fp=chrome&path=${path}&pbk=${currentRealityXHTTPPublicKey}&sid=6ba85179e30d4fc2#${email}\n"

        echoContent yellow " ---> 格式化明文(VLESS+reality+XHTTP)"
        echoContent green "协议类型:VLESS reality，地址:${add}，publicKey:${currentRealityXHTTPPublicKey}，shortId: 6ba85179e30d4fc2,serverNames：${xrayVLESSRealityXHTTPSNI}，端口:${port}，路径：${path}，SNI:${xrayVLESSRealityXHTTPSNI}，Reality目标域名:${xrayVLESSRealityXHTTPSNI}，用户ID:${id}，传输方式:xhttp，账户名:${email}\n"
        cat <<EOF >>"$(subscribeLocalBaseDir)/default/${user}"
vless://${id}@${add}:${port}?encryption=none&security=reality&type=xhttp&sni=${xrayVLESSRealityXHTTPSNI}&fp=chrome&path=${path}&pbk=${currentRealityXHTTPPublicKey}&sid=6ba85179e30d4fc2#${email}
EOF

        cat <<EOF >>"$(subscribeLocalBaseDir)/clashMeta/${user}"
  - name: "${email}"
    type: vless
    server: ${add}
    port: ${port}
    uuid: ${id}
    udp: true
    tls: true
    network: xhttp
    client-fingerprint: chrome
    alpn:
      - h2
    servername: ${xrayVLESSRealityXHTTPSNI}
    xhttp-opts:
      path: ${path}
      host: ${xrayVLESSRealityXHTTPSNI}
    reality-opts:
      public-key: ${currentRealityXHTTPPublicKey}
      short-id: 6ba85179e30d4fc2
EOF

        echoContent yellow " ---> 二维码 VLESS(VLESS+reality+XHTTP)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${add}%3A${port}%3Fencryption%3Dnone%26security%3Dreality%26type%3Dxhttp%26sni%3D${xrayVLESSRealityXHTTPSNI}%26fp%3Dchrome%26path%3D${path}%26host%3D${xrayVLESSRealityXHTTPSNI}%26pbk%3D${currentRealityXHTTPPublicKey}%26sid%3D6ba85179e30d4fc2%23${email}\n"

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

        echoContent yellow " ---> 通用格式(VLESS+gRPC+TLS)"
        echoContent green "    vless://${id}@${add}:${port}?encryption=none&security=tls&type=grpc&host=${currentHost}&path=${currentPath}grpc&fp=chrome&serviceName=${currentPath}grpc&alpn=h2&sni=${currentHost}#${email}\n"

        echoContent yellow " ---> 格式化明文(VLESS+gRPC+TLS)"
        echoContent green "    协议类型:VLESS，地址:${add}，TLS域名/SNI:${currentHost}，端口:${port}，用户ID:${id}，安全:tls，传输方式:gRPC，alpn:h2，client-fingerprint: chrome,serviceName:${currentPath}grpc，账户名:${email}\n"
        appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

        echoContent yellow " ---> 二维码 VLESS(VLESS+gRPC+TLS)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${add}%3A${port}%3Fencryption%3Dnone%26security%3Dtls%26type%3Dgrpc%26host%3D${currentHost}%26serviceName%3D${currentPath}grpc%26fp%3Dchrome%26path%3D${currentPath}grpc%26sni%3D${currentHost}%26alpn%3Dh2%23${email}"

    elif [[ "${type}" == "trojan" ]]; then
        # URLEncode
        echoContent yellow " ---> Trojan(TLS)"
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

        echoContent yellow " ---> 二维码 Trojan(TLS)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=trojan%3a%2f%2f${id}%40${currentHost}%3a${port}%3fpeer%3d${currentHost}%26fp%3Dchrome%26sni%3d${currentHost}%26alpn%3Dhttp/1.1%23${email}\n"

    elif [[ "${type}" == "trojangrpc" ]]; then
        # URLEncode

        echoContent yellow " ---> Trojan gRPC(TLS)"
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
        singBoxFilter=". += [{\"tag\":\"${email}\",\"type\":\"trojan\",\"server\":\"${add}\",\"server_port\":${port},\"password\":\"${id}\",\"tls\":{\"enabled\":true,\"server_name\":\"${currentHost}\",\"insecure\":true,\"utls\":{\"enabled\":true,\"fingerprint\":\"chrome\"}},\"transport\":{\"type\":\"grpc\",\"service_name\":\"${currentPath}trojangrpc\",\"idle_timeout\":\"15s\",\"ping_timeout\":\"15s\",\"permit_without_stream\":false},\"multiplex\":{\"enabled\":false,\"protocol\":\"smux\",\"max_streams\":32}}]"
        appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

        echoContent yellow " ---> 二维码 Trojan gRPC(TLS)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=trojan%3a%2f%2f${id}%40${add}%3a${port}%3Fencryption%3Dnone%26fp%3Dchrome%26security%3Dtls%26peer%3d${currentHost}%26type%3Dgrpc%26sni%3d${currentHost}%26path%3D${currentPath}trojangrpc%26alpn%3Dh2%26serviceName%3D${currentPath}trojangrpc%23${email}\n"

    elif [[ "${type}" == "hysteria" ]]; then
        echoContent yellow " ---> Hysteria(TLS)"
        local clashMetaPortContent="port: ${port}"
        local multiPort=
        local multiPortEncode=
        if echo "${port}" | grep -q "-"; then
            clashMetaPortContent="ports: ${port}"
            multiPort="mport=${port}&"
            multiPortEncode="mport%3D${port}%26"
        fi

        local defaultLink
        local clashMetaBlock
        local singBoxFilter
        defaultLink="hysteria2://${id}@${currentHost}:${singBoxHysteria2Port}?${multiPort}peer=${currentHost}&insecure=0&sni=${currentHost}&alpn=h3#${email}"
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
        echoContent yellow " ---> v2rayN(hysteria+TLS)"
        echo "{\"server\": \"${currentHost}:${port}\",\"socks5\": { \"listen\": \"127.0.0.1:7798\", \"timeout\": 300},\"auth\":\"${id}\",\"tls\":{\"sni\":\"${currentHost}\"}}" | jq

        echoContent yellow " ---> 二维码 Hysteria2(TLS)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=hysteria2%3A%2F%2F${id}%40${currentHost}%3A${singBoxHysteria2Port}%3F${multiPortEncode}peer%3D${currentHost}%26insecure%3D0%26sni%3D${currentHost}%26alpn%3Dh3%23${email}\n"

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
        echoContent yellow " ---> 通用格式(VLESS+reality+uTLS+Vision)"
        echoContent green "    ${defaultLink}\n"

        echoContent yellow " ---> 格式化明文(VLESS+reality+uTLS+Vision)"
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

        echoContent yellow " ---> 二维码 VLESS(VLESS+reality+uTLS+Vision)"
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
        echoContent yellow " ---> 通用格式(VLESS+reality+uTLS+gRPC)"
        echoContent green "    ${defaultLink}\n"

        echoContent yellow " ---> 格式化明文(VLESS+reality+uTLS+gRPC)"
        echoContent green "协议类型:VLESS reality，serviceName:grpc，地址:${entryHost}，publicKey:${publicKey}，shortId: 6ba85179e30d4fc2，Reality目标SNI：${realitySNI}，端口:${port}，用户ID:${id}，传输方式:gRPC，client-fingerprint：chrome，账户名:${email}\n"
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

        echoContent yellow " ---> 二维码 VLESS(VLESS+reality+uTLS+gRPC)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${entryHost}%3A${port}%3Fencryption%3Dnone%26security%3Dreality%26type%3Dgrpc%26sni%3D${realitySNI}%26fp%3Dchrome%26pbk%3D${publicKey}%26sid%3D6ba85179e30d4fc2%26path%3Dgrpc%26serviceName%3Dgrpc%23${email}\n"
    elif [[ "${type}" == "tuic" ]]; then
        local tuicUUID=
        tuicUUID=$(echo "${id}" | awk -F "[_]" '{print $1}')

        local tuicPassword=
        tuicPassword=$(echo "${id}" | awk -F "[_]" '{print $2}')

        if [[ -z "${email}" ]]; then
            echoContent red " ---> 读取配置失败，请重新安装"
            exit 0
        fi

        echoContent yellow " ---> 格式化明文(Tuic+TLS)"
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
    reduce-rtt: true
    sni: ${currentHost}
EOF
)
        singBoxFilter=". += [{\"tag\":\"${email}\",\"type\": \"tuic\",\"server\": \"${currentHost}\",\"server_port\": ${port},\"uuid\": \"${tuicUUID}\",\"password\": \"${tuicPassword}\",\"congestion_control\": \"${tuicAlgorithm}\",\"tls\": {\"enabled\": true,\"server_name\": \"${currentHost}\",\"alpn\": [\"h3\"]}}]"

        appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"
        echoContent yellow " ---> v2rayN(Tuic+TLS)"
        echo "{\"relay\": {\"server\": \"${currentHost}:${port}\",\"uuid\": \"${tuicUUID}\",\"password\": \"${tuicPassword}\",\"ip\": \"${currentHost}\",\"congestion_control\": \"${tuicAlgorithm}\",\"alpn\": [\"h3\"]},\"local\": {\"server\": \"127.0.0.1:7798\"},\"log_level\": \"warn\"}" | jq

        echoContent yellow "\n ---> 二维码 Tuic"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=tuic%3A%2F%2F${tuicUUID}%3A${tuicPassword}%40${currentHost}%3A${port}%3Fcongestion_control%3D${tuicAlgorithm}%26alpn%3Dh3%26sni%3D${currentHost}%26udp_relay_mode%3Dnative%26allow_insecure%3D0%23${email}\n"
    elif [[ "${type}" == "naive" ]]; then
        echoContent yellow " ---> Naive(TLS)"

        local defaultLink
        defaultLink="naive+https://${email}:${id}@${currentHost}:${port}?padding=true#${email}"

        echoContent green "    ${defaultLink}\n"
        appendDefaultSubscribeLine "${user}" "${defaultLink}"
        echoContent yellow " ---> 二维码 Naive(TLS)"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=naive%2Bhttps%3A%2F%2F${email}%3A${id}%40${currentHost}%3A${port}%3Fpadding%3Dtrue%23${email}\n"
    elif [[ "${type}" == "vmessHTTPUpgrade" ]]; then
        qrCodeBase64Default=$(echo -n "{\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"httpupgrade\",\"add\":\"${add}\",\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}" | base64 -w 0)
        qrCodeBase64Default="${qrCodeBase64Default// /}"

        echoContent yellow " ---> 通用json(VMess+HTTPUpgrade+TLS)"
        echoContent green "    {\"port\":${port},\"ps\":\"${email}\",\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${currentHost}\",\"type\":\"none\",\"path\":\"${path}\",\"net\":\"httpupgrade\",\"add\":\"${add}\",\"method\":\"none\",\"peer\":\"${currentHost}\",\"sni\":\"${currentHost}\"}\n"
        echoContent yellow " ---> 通用vmess(VMess+HTTPUpgrade+TLS)链接"
        echoContent green "    vmess://${qrCodeBase64Default}\n"
        echoContent yellow " ---> 二维码 vmess(VMess+HTTPUpgrade+TLS)"

        local defaultLink
        local clashMetaBlock
        local singBoxFilter
        defaultLink="   vmess://${qrCodeBase64Default}"
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
        echoContent yellow " ---> AnyTLS"

        echoContent yellow " ---> 格式化明文(AnyTLS)"
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

        echoContent yellow " ---> 二维码 AnyTLS"
        echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=anytls%3A%2F%2F${id}%40${currentHost}%3A${singBoxAnyTLSPort}%3Fpeer%3D${currentHost}%26insecure%3D0%26sni%3D${currentHost}%23${email}\n"
    fi

}


# 服务器源
normalizeSubscriptionSourceInput() {
    local line=$1
    local host port alias type

    line=$(echo "${line}" | xargs)
    if [[ -z "${line}" ]]; then
        return 1
    fi

    IFS=':' read -r host port alias type _ <<<"${line}"
    if [[ -z "${host}" || -z "${port}" || -z "${alias}" ]]; then
        return 1
    fi
    if ! echo "${port}" | grep -qE '^[0-9]+$' || ((port < 1 || port > 65535)); then
        return 1
    fi
    if [[ -z "${type}" ]]; then
        type=https
    fi
    if [[ "${type}" != "http" && "${type}" != "https" ]]; then
        return 1
    fi

    printf '%s:%s:%s:%s\n' "${host}" "${port}" "${alias}" "${type}"
}

remoteSubscribeFile() {
    subscriptionGroupsFile
}

listRemoteSubscribeSources() {
    listSubscriptionSources | awk -F ':' '$3 != "main" {print $5":"$6":"$2":"$4}'
}

# 添加订阅
addSubscribeMenu() {
    echoContent skyBlue "\n===================== 服务器源管理 ======================="
    echoContent yellow "说明：服务器源用于多服务器订阅聚合和远程同步，不是普通客户端节点导入入口"
    echoContent yellow "添加前请先在对端安装订阅服务；如需远程同步，还要在对端配置控制 Token"
    echoContent yellow "1.添加服务器源"
    echoContent yellow "2.移除服务器源"
    echoContent red "=============================================================="
    read -r -p "请选择:" addSubscribeStatus
    if [[ "${addSubscribeStatus}" == "1" ]]; then
        addOtherSubscribe
    elif [[ "${addSubscribeStatus}" == "2" ]]; then
        local sourceId=
        listSubscriptionSources | awk -F ':' '$3 != "main" {print NR":"$0}'
        read -r -p "请选择要删除的服务器源ID:" sourceId
        if [[ -z "${sourceId}" ]]; then
            echoContent green " ---> 不可以为空"
            exit 0
        fi
        removeSubscriptionSourceState "${sourceId}"
        echoContent green " ---> 服务器源删除成功"
        subscribe
    fi
}

# 添加其他机器clashMeta订阅
addOtherSubscribe() {
    local sourceInput=
    local normalizedSourceInput=
    local host=
    local port=
    local alias=
    local scheme=
    echoContent yellow "#填写说明:"
    echoContent yellow "服务器源格式: 域名:订阅端口:别名[:http|https]，默认 https"
    echoContent yellow "别名建议使用英文、数字或短横线，例如 hk-1；不要填写当前服务器自己的订阅地址"
    echoContent yellow "添加后可到 订阅管理 -> 服务器 设置控制Token、测试连接、查看同步结果"
    echoContent skyBlue "录入示例：www.example.com:443:vps1 或 www.example.com:39778:vps1:https\n"
    read -r -p "请输入域名 端口 机器别名:" sourceInput
    if [[ -z "${sourceInput}" ]]; then
        echoContent red " ---> 不可为空"
        addOtherSubscribe
    fi

    echo
    read -r -p "是否是HTTP订阅？[y/n]" httpSubscribeStatus
    if [[ "${httpSubscribeStatus}" == "y" ]]; then
        sourceInput="${sourceInput}:http"
    fi

    normalizedSourceInput=$(normalizeSubscriptionSourceInput "${sourceInput}")
    if [[ -z "${normalizedSourceInput}" ]]; then
        echoContent red " ---> 规则不合法"
        exit 0
    fi

    host=$(echo "${normalizedSourceInput}" | awk -F ':' '{print $1}')
    port=$(echo "${normalizedSourceInput}" | awk -F ':' '{print $2}')
    alias=$(echo "${normalizedSourceInput}" | awk -F ':' '{print $3}')
    scheme=$(echo "${normalizedSourceInput}" | awk -F ':' '{print $4}')
    if subscriptionRemoteSourceSelfReference "$(jq -n --arg host "${host}" --argjson port "${port}" --arg scheme "${scheme}" '{host:$host, port:$port, scheme:$scheme}')"; then
        echoContent red " ---> 服务器源指向当前订阅服务，已拒绝添加，避免递归同步"
        exit 0
    fi
    addSubscriptionSourceState "${alias}" "${alias}" "${scheme}" "${host}" "${port}"
    echoContent green " ---> 服务器源已添加"
    subscribe
}



ensureSubscriptionControlNginxLocation() {
    local subscribeConfig="${nginxConfigPath}subscribe.conf"
    local tmpConfig="${subscribeConfig}.tmp"
    [[ -f "${subscribeConfig}" ]] || return 1
    grep -q 'location /s/control/' "${subscribeConfig}" && return 1
    awk -v port="$(subscriptionControlPort)" '
      BEGIN { inserted = 0 }
      !inserted && $0 == "    location / {" {
        print "    location /s/control/ {"
        print "        client_max_body_size 256k;"
        print "        proxy_pass http://127.0.0.1:" port ";"
        print "        proxy_set_header Authorization $http_authorization;"
        print "        proxy_set_header Content-Type $content_type;"
        print "    }"
        inserted = 1
      }
      { print }
      END { if (!inserted) exit 1 }
    ' "${subscribeConfig}" >"${tmpConfig}" && mv "${tmpConfig}" "${subscribeConfig}"
}


# 安装订阅
installSubscribe() {
    readNginxSubscribe
    local nginxSubscribeListen=
    local nginxSubscribeSSL=
    local serverName=
    local SSLType=
    local listenIPv6=
    if [[ -n "${AUTO_SUBSCRIBE_PORT}" && "${subscribePort}" != "${AUTO_SUBSCRIBE_PORT}" ]]; then
        subscribePort=
    fi
    if [[ -z "${subscribePort}" ]]; then

        nginxVersion=$(nginx -v 2>&1)

        if echo "${nginxVersion}" | grep -q "not found" || [[ -z "${nginxVersion}" ]]; then
            echoContent yellow "未检测到nginx，无法使用订阅服务\n"
            autoRead install_nginx "是否安装[y/n]？" installNginxStatus
            if [[ "${installNginxStatus}" == "y" ]]; then
                installNginxTools
            else
                echoContent red " ---> 放弃安装nginx\n"
                exit 0
            fi
        fi
        echoContent yellow "开始配置订阅，请输入订阅的端口\n"

        mapfile -t result < <(initSingBoxPort "${AUTO_SUBSCRIBE_PORT:-${subscribePort}}" false)
        echo
        echoContent yellow " ---> 开始配置订阅静态页面\n"
        nginxBlog
        echo
        local httpSubscribeStatus=

        if ! protocolSelectionNeedsTLS "${selectCustomInstallType}" && ! protocolSelectionNeedsTLS "${currentInstallProtocolType}" && [[ -z "${domain}" ]]; then
            httpSubscribeStatus=true
        fi

        if [[ "${httpSubscribeStatus}" == "true" ]]; then

            echoContent red " ---> 未发现 TLS 证书，HTTP 订阅不会加密传输"
            echoContent yellow " ---> 订阅链接、用户标识和控制路径可能被中间人或网络侧观察到"
            echoContent yellow " ---> 仅建议在临时验收、内网或已确认风险的环境使用；长期使用请配置 TLS 订阅"
            echo
            autoRead http_subscribe "确认承担上述风险并启用 HTTP 订阅[y/n]？" addNginxSubscribeStatus
            echo
            if [[ "${addNginxSubscribeStatus}" != "y" ]]; then
                echoContent yellow " ---> 退出安装"
                exit
            fi
        else
            local subscribeServerName=
            if [[ -n "${currentHost}" ]]; then
                subscribeServerName="${currentHost}"
            else
                subscribeServerName="${domain}"
            fi

            SSLType="ssl"
            serverName="server_name ${subscribeServerName};"
            nginxSubscribeSSL="ssl_certificate /etc/padm/tls/${subscribeServerName}.crt;ssl_certificate_key /etc/padm/tls/${subscribeServerName}.key;"
        fi
        if hasIPv6Connectivity; then
            listenIPv6="listen [::]:${result[-1]} ${SSLType};"
        fi
        if echo "${nginxVersion}" | grep -q "1.25" && [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $3}') -gt 0 ]] || [[ $(echo "${nginxVersion}" | awk -F "[.]" '{print $2}') -gt 25 ]]; then
            nginxSubscribeListen="listen ${result[-1]} ${SSLType} so_keepalive=on;http2 on;${listenIPv6}"
        else
            nginxSubscribeListen="listen ${result[-1]} ${SSLType} so_keepalive=on;${listenIPv6}"
        fi

        cat <<EOF >${nginxConfigPath}subscribe.conf
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
    location /s/control/ {
        client_max_body_size 256k;
        proxy_pass http://127.0.0.1:$(subscriptionControlPort);
        proxy_set_header Authorization \$http_authorization;
        proxy_set_header Content-Type \$content_type;
    }
    location / {
    }
}
EOF
        installSubscriptionControlService
        bootStartup nginx
        handleNginx stop
        handleNginx start
    fi
    if [[ -z $(pgrep -f "nginx") ]]; then
        handleNginx start
    fi
}

# 卸载订阅
unInstallSubscribe() {
    rm -rf ${nginxConfigPath}subscribe.conf >/dev/null 2>&1
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
        if [[ -n "${line}" ]] && ! grep -Fxq "${line}" "${targetPath}"; then
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
    jq -s '.[0] as $local | .[1] as $remote | $local + ($remote | map(select(.tag as $tag | ($local | map(.tag) | index($tag) | not))))' "${targetPath}" "${remoteTmpPath}" >"${tmpPath}" && mv "${tmpPath}" "${targetPath}"
    rm -f "${remoteTmpPath}" "${tmpPath}" >/dev/null 2>&1
}

# 更新远程订阅
updateRemoteSubscribe() {
    local emailMD5=$1
    local email=$2
    local line=
    local normalizedLine=

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

        subscribeType=$(echo "${line}" | awk -F ":" '{print $4}')
        serverAlias=$(echo "${line}" | awk -F ":" '{print $3}')
        remoteUrl=$(echo "${line}" | awk -F ":" '{print $1":"$2}')

        clashMetaProxies=$(fetchRemoteSubscribeContent "${subscribeType}://${remoteUrl}/s/clashMeta/${emailMD5}" | sed '/proxies:/d' | sed "s/\"${email}/\"${email}_${serverAlias}/g")
        if ! echo "${clashMetaProxies}" | grep -q "nginx" && [[ -n "${clashMetaProxies}" ]]; then
            appendUniqueLines "${clashMetaProxies}" "/etc/padm/subscribe/clashMeta/${emailMD5}"
            echoContent green " ---> clashMeta订阅 ${remoteUrl}:${email} 更新成功"
        else
            echoContent red " ---> clashMeta订阅 ${remoteUrl}:${email} 拉取失败或不存在"
        fi

        default=$(fetchRemoteSubscribeContent "${subscribeType}://${remoteUrl}/s/default/${emailMD5}")
        if ! echo "${default}" | grep -q "nginx" && [[ -n "${default}" ]]; then
            default=$(echo "${default}" | base64 -d 2>/dev/null | sed "s/#${email}/#${email}_${serverAlias}/g")
            if [[ -n "${default}" ]]; then
                appendUniqueLines "${default}" "/etc/padm/subscribe/default/${emailMD5}"
                echoContent green " ---> 通用订阅 ${remoteUrl}:${email} 更新成功"
            else
                echoContent red " ---> 通用订阅 ${remoteUrl}:${email} 解码失败"
            fi
        else
            echoContent red " ---> 通用订阅 ${remoteUrl}:${email} 拉取失败或不存在"
        fi

        singBoxSubscribe=$(fetchRemoteSubscribeContent "${subscribeType}://${remoteUrl}/s/sing-box_profiles/${emailMD5}")
        if ! echo "${singBoxSubscribe}" | grep -q "nginx" && [[ -n "${singBoxSubscribe}" ]] && echo "${singBoxSubscribe}" | jq empty >/dev/null 2>&1; then
            singBoxSubscribe=${singBoxSubscribe//tag\": \"${email}/tag\": \"${email}_${serverAlias}}
            mergeSingBoxSubscribeOutbounds "$(subscribeLocalBaseDir)/sing-box/${email}" "${singBoxSubscribe}"
            echoContent green " ---> sing-box订阅 ${remoteUrl}:${email} 更新成功"
        else
            echoContent red " ---> sing-box订阅 ${remoteUrl}:${email} 拉取失败或不存在"
        fi
    done < <(listRemoteSubscribeSources)
}


# 账号
showAccounts() {
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    readSingBoxConfig

    echo
    echoContent skyBlue "\n进度 $1/${totalProgress} : 账号"

    initSubscribeLocalConfig
    # VLESS TCP
    if currentProtocolHas 0; then

        echoContent skyBlue "============================= VLESS TCP TLS Vision [传统 TLS 兼容方案] ==============================\n"
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}02_VLESS_TCP_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            echoContent skyBlue "\n ---> 账号:${email}"
            echo
            defaultBase64Code vlesstcp "${currentDefaultPort}${singBoxVLESSVisionPort}" "${email}" "$(echo "${user}" | jq -r .id//.uuid)"
        done
    fi

    # VLESS WS
    if currentProtocolHas 1; then
        echoContent skyBlue "\n================================ VLESS WS TLS [兼容旧客户端，不作为新手推荐] ================================\n"

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
                echoContent skyBlue "\n ---> 账号:${email}${count}"
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
        echoContent skyBlue "\n================================  Trojan gRPC TLS [兼容旧客户端，不作为新手推荐]  ================================\n"
        jq .inbounds[0].settings.clients ${configPath}04_trojan_gRPC_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email)
            local count=
            while read -r line; do
                echoContent skyBlue "\n ---> 账号:${email}${count}"
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
        echoContent skyBlue "\n================================ VMess WS TLS [兼容旧客户端，不作为新手推荐]  ================================\n"
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
                echoContent skyBlue "\n ---> 账号:${email}${count}"
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
        echoContent skyBlue "\n==================================  Trojan TLS [不推荐] ==================================\n"
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}04_trojan_TCP_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)
            echoContent skyBlue "\n ---> 账号:${email}"

            defaultBase64Code trojan "${currentDefaultPort}${singBoxTrojanPort}" "${email}" "$(echo "${user}" | jq -r .password)"
        done
    fi
    # VLESS grpc
    if currentProtocolHas 5; then
        echoContent skyBlue "\n=============================== VLESS gRPC TLS [兼容旧客户端，不作为新手推荐]  ===============================\n"
        jq .inbounds[0].settings.clients ${configPath}06_VLESS_gRPC_inbounds.json | jq -c '.[]' | while read -r user; do

            local email=
            email=$(echo "${user}" | jq -r .email)

            local count=
            while read -r line; do
                echoContent skyBlue "\n ---> 账号:${email}${count}"
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
        echoContent skyBlue "\n================================  Hysteria2 TLS [UDP/移动网络可选] ================================\n"
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
            echoContent skyBlue "\n ---> 账号:$(echo "${user}" | jq -r .name)"
            echo
            defaultBase64Code hysteria "${hysteria2DefaultPort}" "$(echo "${user}" | jq -r .name)" "$(echo "${user}" | jq -r .password)"
        done

    fi

    # VLESS reality vision
    if currentProtocolHas 7; then
        echoContent skyBlue "============================= VLESS reality_vision [推荐]  ==============================\n"
        jq .inbounds[1].settings.clients//.inbounds[0].users ${configPath}07_VLESS_vision_reality_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            echoContent skyBlue "\n ---> 账号:${email}"
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
    # VLESS reality gRPC
    if currentProtocolHas 8; then
        echoContent skyBlue "============================== VLESS reality_gRPC [推荐] ===============================\n"
        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}08_VLESS_vision_gRPC_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)

            echoContent skyBlue "\n ---> 账号:${email}"
            echo
            local realityGRPCPort="${singBoxVLESSRealityGRPCPort:-${xrayVLESSRealityPort}}"
            defaultBase64Code vlessRealityGRPC "${realityGRPCPort}" "${email}" "$(echo "${user}" | jq -r .id//.uuid)"
        done
    fi
    # tuic
    if currentProtocolHas 9 || [[ -n "${tuicPort}" ]]; then
        echoContent skyBlue "\n================================  Tuic TLS [UDP/移动网络可选]  ================================\n"
        local path="${configPath}"
        if [[ "${coreInstallType}" == "1" ]]; then
            path="${singBoxConfigPath}"
        fi
        jq -r -c '.inbounds[].users[]' "${path}09_tuic_inbounds.json" | while read -r user; do
            echoContent skyBlue "\n ---> 账号:$(echo "${user}" | jq -r .name)"
            echo
            defaultBase64Code tuic "${singBoxTuicPort}" "$(echo "${user}" | jq -r .name)" "$(echo "${user}" | jq -r .uuid)_$(echo "${user}" | jq -r .password)"
        done

    fi
    # naive
    if currentProtocolHas 10 || [[ -n "${singBoxNaivePort}" ]]; then
        echoContent skyBlue "\n================================  naive TLS [推荐，不支持ClashMeta]  ================================\n"

        jq -r -c '.inbounds[]|.users[]' "${configPath}10_naive_inbounds.json" | while read -r user; do
            echoContent skyBlue "\n ---> 账号:$(echo "${user}" | jq -r .username)"
            echo
            defaultBase64Code naive "${singBoxNaivePort}" "$(echo "${user}" | jq -r .username)" "$(echo "${user}" | jq -r .password)"
        done

    fi
    # VMess HTTPUpgrade
    if currentProtocolHas 11; then
        echoContent skyBlue "\n================================ VMess HTTPUpgrade TLS [兼容旧客户端，不作为新手推荐]  ================================\n"
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
                echoContent skyBlue "\n ---> 账号:${email}${count}"
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
        echoContent skyBlue "\n================================ VLESS Reality XHTTP [CDN推荐] ================================\n"

        jq .inbounds[0].settings.clients//.inbounds[0].users ${configPath}12_VLESS_XHTTP_inbounds.json | jq -c '.[]' | while read -r user; do
            local email=
            email=$(echo "${user}" | jq -r .email//.name)
            echo
            local path="${currentPath}xHTTP"

            local count=
            while read -r line; do
                echoContent skyBlue "\n ---> 账号:${email}${count}"
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
        echoContent skyBlue "\n================================  AnyTLS ================================\n"

        jq -r -c '.inbounds[]|.users[]' "${configPath}13_anytls_inbounds.json" | while read -r user; do
            echoContent skyBlue "\n ---> 账号:$(echo "${user}" | jq -r .name)"
            echo
            defaultBase64Code anytls "${singBoxAnyTLSPort}" "$(echo "${user}" | jq -r .name)" "$(echo "${user}" | jq -r .password)"
        done

    fi
}
