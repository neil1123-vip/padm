#!/usr/bin/env bash

emitVlessTcpSubscribeOutput() {
    local port=$1
    local email=$2
    local id=$3
    local add=$4
    local path=$5
    local user=$6
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

}

emitVmessWsSubscribeOutput() {
    local port=$1
    local email=$2
    local id=$3
    local add=$4
    local path=$5
    local user=$6
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

}

emitVlessWsSubscribeOutput() {
    local port=$1
    local email=$2
    local id=$3
    local add=$4
    local path=$5
    local user=$6
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

}

emitVlessXHTTPSubscribeOutput() {
    local port=$1
    local email=$2
    local id=$3
    local add=$4
    local path=$5
    local user=$6
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
    echoContent green "协议类型:VLESS reality，入口地址:${add}，publicKey:${currentRealityXHTTPPublicKey}，shortId: 6ba85179e30d4fc2,serverNames：${xrayVLESSRealityXHTTPSNI}，端口:${port}，XHTTP host:${xhttpHost}，路径：${path}，mode:${xhttpMode}，Reality SNI:${xrayVLESSRealityXHTTPSNI}，用户ID:${id}，传输方式:xhttp，账户名:${email}\n"
    appendDefaultSubscribeLine "${user}" "${defaultLink}"

    appendClashMetaSubscribeLines "${user}" <<EOF
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
      host: ${xhttpHost}
      mode: ${xhttpMode}
    reality-opts:
      public-key: ${currentRealityXHTTPPublicKey}
      short-id: 6ba85179e30d4fc2
EOF

    subscribeOutputTitle "二维码：VLESS Reality XHTTP Vision XMUX"
    echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless%3A%2F%2F${id}%40${add}%3A${port}%3Fencryption%3D${vlessEncryption}%26security%3Dreality%26type%3Dxhttp%26sni%3D${xrayVLESSRealityXHTTPSNI}%26fp%3Dchrome%26path%3D${path}%26mode%3D${xhttpMode}%26host%3D${xhttpHost}%26pbk%3D${currentRealityXHTTPPublicKey}%26sid%3D6ba85179e30d4fc2%23${email}\n"

}

emitVlessGrpcSubscribeOutput() {
    local port=$1
    local email=$2
    local id=$3
    local add=$4
    local path=$5
    local user=$6
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

}

emitTrojanSubscribeOutput() {
    local port=$1
    local email=$2
    local id=$3
    local add=$4
    local path=$5
    local user=$6
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

}

emitTrojanGrpcSubscribeOutput() {
    local port=$1
    local email=$2
    local id=$3
    local add=$4
    local path=$5
    local user=$6
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

}

emitHysteriaSubscribeOutput() {
    local port=$1
    local email=$2
    local id=$3
    local add=$4
    local path=$5
    local user=$6
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

}

emitVlessRealitySubscribeOutput() {
    local port=$1
    local email=$2
    local id=$3
    local add=$4
    local path=$5
    local user=$6
    local entryHost
    entryHost=$(realityEntryHost)

    local realitySNI=${xrayVLESSRealitySNI}
    local publicKey=${currentRealityPublicKey:-}
    local realityMldsa65Verify=${currentRealityMldsa65Verify:-}
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

}

emitVlessRealityGrpcSubscribeOutput() {
    local port=$1
    local email=$2
    local id=$3
    local add=$4
    local path=$5
    local user=$6
    local entryHost
    entryHost=$(realityEntryHost)
    local realitySNI=${xrayVLESSRealitySNI}
    local publicKey=${currentRealityPublicKey:-}
    local realityMldsa65Verify=${currentRealityMldsa65Verify:-}

    if [[ -n "${singBoxVLESSRealityGRPCSNI:-}" ]]; then
        realitySNI=${singBoxVLESSRealityGRPCSNI}
    fi
    if [[ -n "${singBoxVLESSRealityPublicKey:-}" ]]; then
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
}

emitTuicSubscribeOutput() {
    local port=$1
    local email=$2
    local id=$3
    local add=$4
    local path=$5
    local user=$6
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
    local singBoxServerPort=${singBoxTuicPort:-${port}}
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
    singBoxFilter=". += [{\"tag\":\"${email}\",\"type\": \"tuic\",\"server\": \"${currentHost}\",\"server_port\": ${singBoxServerPort},\"uuid\": \"${tuicUUID}\",\"password\": \"${tuicPassword}\",\"congestion_control\": \"${tuicAlgorithm}\",\"udp_relay_mode\": \"native\",\"zero_rtt_handshake\": false,\"tls\": {\"enabled\": true,\"server_name\": \"${currentHost}\",\"alpn\": [\"h3\"]}}]"

    appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"
    subscribeOutputTitle "v2rayN：Tuic TLS"
    echo "{\"relay\": {\"server\": \"${currentHost}:${port}\",\"uuid\": \"${tuicUUID}\",\"password\": \"${tuicPassword}\",\"ip\": \"${currentHost}\",\"congestion_control\": \"${tuicAlgorithm}\",\"alpn\": [\"h3\"]},\"local\": {\"server\": \"127.0.0.1:7798\"},\"log_level\": \"warn\"}" | jq

    subscribeOutputTitle "二维码：Tuic TLS"
    echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=tuic%3A%2F%2F${tuicUUID}%3A${tuicPassword}%40${currentHost}%3A${port}%3Fcongestion_control%3D${tuicAlgorithm}%26alpn%3Dh3%26sni%3D${currentHost}%26udp_relay_mode%3Dnative%26allow_insecure%3D0%23${email}\n"
}

emitShadowsocksSubscribeOutput() {
    local port=$1
    local email=$2
    local id=$3
    local add=$4
    local path=$5
    local user=$6
    local method="2022-blake3-aes-128-gcm"
    local defaultUserInfo
    local defaultLink
    local clashMetaBlock
    local singBoxFilter

    defaultUserInfo=$(printf '%s' "${method}:${id}" | base64 -w 0)
    defaultLink="ss://${defaultUserInfo}@${currentHost}:${port}#${email}"
    clashMetaBlock=$(cat <<EOF
  - name: "${email}"
    type: ss
    server: ${currentHost}
    port: ${port}
    cipher: ${method}
    password: "${id}"
EOF
)
    singBoxFilter=". += [{\"tag\":\"${email}\",\"type\":\"shadowsocks\",\"server\":\"${currentHost}\",\"server_port\":${port},\"method\":\"${method}\",\"password\":\"${id}\"}]"

    subscribeOutputTitle "通用链接：Shadowsocks"
    echoContent green "    ${defaultLink}\n"

    subscribeOutputTitle "格式化明文：Shadowsocks"
    echoContent green "协议类型:Shadowsocks，地址:${currentHost}，端口:${port}，method:${method}，账户名:${email}\n"

    appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"
}

emitNaiveSubscribeOutput() {
    local port=$1
    local email=$2
    local id=$3
    local add=$4
    local path=$5
    local user=$6
    subscribeOutputTitle "通用链接：Naive TLS"
    echoContent green "    NaiveProxy 适合需要 TLS 指纹抗性的场景；需要真实域名和可信证书，不是无域名 Reality 替代。\n"

    local defaultLink
    defaultLink="naive+https://${email}:${id}@${currentHost}:${port}?padding=true#${email}"

    echoContent green "    ${defaultLink}\n"
    appendDefaultSubscribeLine "${user}" "${defaultLink}"
    subscribeOutputTitle "二维码：Naive TLS"
    echoContent green "    https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=naive%2Bhttps%3A%2F%2F${email}%3A${id}%40${currentHost}%3A${port}%3Fpadding%3Dtrue%23${email}\n"
}

emitVmessHTTPUpgradeSubscribeOutput() {
    local port=$1
    local email=$2
    local id=$3
    local add=$4
    local path=$5
    local user=$6
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

}

emitAnyTlsSubscribeOutput() {
    local port=$1
    local email=$2
    local id=$3
    local add=$4
    local path=$5
    local user=$6
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
}
