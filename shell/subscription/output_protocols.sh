#!/usr/bin/env bash

singBoxSubscribeAppendFilter() {
    local objectFilter=$1
    shift
    jq -nr "$@" "${objectFilter} | \". += [\" + (. | tojson) + \"]\""
}

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
    singBoxFilter=$(singBoxSubscribeAppendFilter '{tag:$tag,type:"vless",server:$server,server_port:$port,uuid:$uuid,flow:"xtls-rprx-vision",tls:{enabled:true,server_name:$sni,utls:{enabled:true,fingerprint:"chrome"}},packet_encoding:"xudp"}' --arg tag "${email}" --arg server "${currentHost}" --argjson port "${port}" --arg uuid "${id}" --arg sni "${currentHost}") || return 1

    subscribeOutputTitle "通用格式：VLESS TCP TLS Vision"
    echoContent green "    vless://${id}@${currentHost}:${port}?encryption=none&security=tls&fp=chrome&type=tcp&host=${currentHost}&headerType=none&sni=${currentHost}&flow=xtls-rprx-vision#${email}\n"

    subscribeOutputTitle "格式化明文：VLESS TCP TLS Vision"
    echoContent green "协议类型:VLESS，地址:${currentHost}，端口:${port}，用户ID:${id}，安全:tls，client-fingerprint: chrome（兼容模拟，不作为抗封锁保证），传输方式:tcp，flow:xtls-rprx-vision，账户名:${email}\n"
    appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

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
    singBoxFilter=$(singBoxSubscribeAppendFilter '{tag:$tag,type:"vmess",server:$server,server_port:$port,uuid:$uuid,alter_id:0,tls:{enabled:true,server_name:$sni,utls:{enabled:true,fingerprint:"chrome"}},packet_encoding:"packetaddr",transport:{type:"ws",path:$path,max_early_data:2048,early_data_header_name:"Sec-WebSocket-Protocol"}}' --arg tag "${email}" --arg server "${add}" --argjson port "${port}" --arg uuid "${id}" --arg sni "${currentHost}" --arg path "${path}") || return 1
    appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

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
    singBoxFilter=$(singBoxSubscribeAppendFilter '{tag:$tag,type:"vless",server:$server,server_port:$port,uuid:$uuid,tls:{enabled:true,server_name:$sni,utls:{enabled:true,fingerprint:"chrome"}},multiplex:{enabled:false,protocol:"smux",max_streams:32},packet_encoding:"xudp",transport:{type:"ws",path:$path,headers:{Host:$host}}}' --arg tag "${email}" --arg server "${add}" --argjson port "${port}" --arg uuid "${id}" --arg sni "${currentHost}" --arg path "${path}" --arg host "${currentHost}") || return 1

    subscribeOutputTitle "通用格式：VLESS WS TLS"
    echoContent green "    ${defaultLink}\n"

    subscribeOutputTitle "格式化明文：VLESS WS TLS"
    echoContent green "    协议类型:VLESS，地址:${add}，TLS域名/SNI:${currentHost}，端口:${port}，client-fingerprint: chrome（兼容模拟，不作为抗封锁保证）,用户ID:${id}，安全:tls，传输方式:ws，路径:${path}，账户名:${email}\n"
    appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

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
    appendDefaultSubscribeLine "${user}" "${defaultLink}" || return 1

    appendClashMetaSubscribeLines "${user}" <<EOF || return 1
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
    singBoxFilter=$(singBoxSubscribeAppendFilter '{tag:$tag,type:"vless",server:$server,server_port:$port,uuid:$uuid,tls:{enabled:true,server_name:$sni,utls:{enabled:true,fingerprint:"chrome"}},packet_encoding:"xudp",transport:{type:"grpc",service_name:$service}}' --arg tag "${email}" --arg server "${add}" --argjson port "${port}" --arg uuid "${id}" --arg sni "${currentHost}" --arg service "${currentPath}grpc") || return 1

    subscribeOutputTitle "通用格式：VLESS gRPC TLS"
    echoContent green "    vless://${id}@${add}:${port}?encryption=none&security=tls&type=grpc&host=${currentHost}&path=${currentPath}grpc&fp=chrome&serviceName=${currentPath}grpc&alpn=h2&sni=${currentHost}#${email}\n"

    subscribeOutputTitle "格式化明文：VLESS gRPC TLS"
    echoContent green "    协议类型:VLESS，地址:${add}，TLS域名/SNI:${currentHost}，端口:${port}，用户ID:${id}，安全:tls，传输方式:gRPC，alpn:h2，client-fingerprint: chrome（兼容模拟，不作为抗封锁保证）,serviceName:${currentPath}grpc，账户名:${email}\n"
    appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

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
    singBoxFilter=$(singBoxSubscribeAppendFilter '{tag:$tag,type:"trojan",server:$server,server_port:$port,password:$password,tls:{alpn:["http/1.1"],enabled:true,server_name:$sni,utls:{enabled:true,fingerprint:"chrome"}}}' --arg tag "${email}" --arg server "${currentHost}" --argjson port "${port}" --arg password "${id}" --arg sni "${currentHost}") || return 1
    appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

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
    singBoxFilter=$(singBoxSubscribeAppendFilter '{tag:$tag,type:"trojan",server:$server,server_port:$port,password:$password,tls:{enabled:true,server_name:$sni,utls:{enabled:true,fingerprint:"chrome"}},transport:{type:"grpc",service_name:$service,idle_timeout:"15s",ping_timeout:"15s",permit_without_stream:false},multiplex:{enabled:false,protocol:"smux",max_streams:32}}' --arg tag "${email}" --arg server "${add}" --argjson port "${port}" --arg password "${id}" --arg sni "${currentHost}" --arg service "${currentPath}trojangrpc") || return 1
    appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

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
    singBoxFilter=$(singBoxSubscribeAppendFilter '{tag:$tag,type:"hysteria2",server:$server,server_port:$port,up_mbps:$up,down_mbps:$down,password:$password,tls:{enabled:true,server_name:$sni,alpn:["h3"]}}' --arg tag "${email}" --arg server "${currentHost}" --argjson port "${singBoxHysteria2Port}" --argjson up "${hysteria2ClientUploadSpeed}" --argjson down "${hysteria2ClientDownloadSpeed}" --arg password "${id}" --arg sni "${currentHost}") || return 1

    echoContent green "    ${defaultLink}\n"
    appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"
    subscribeOutputTitle "v2rayN：Hysteria2 TLS"
    echo "{\"server\": \"${currentHost}:${port}\",\"socks5\": { \"listen\": \"127.0.0.1:7798\", \"timeout\": 300},\"auth\":\"${id}\",\"tls\":{\"sni\":\"${currentHost}\"}}" | jq

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
    appendDefaultSubscribeLine "${user}" "${defaultLink}" || return 1
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
    client-fingerprint: chrome" || return 1

    local singBoxFilter
    singBoxFilter=$(singBoxSubscribeAppendFilter '{tag:$tag,type:"vless",server:$server,server_port:$port,uuid:$uuid,flow:"xtls-rprx-vision",tls:{enabled:true,server_name:$sni,utls:{enabled:true,fingerprint:"chrome"},reality:{enabled:true,public_key:$public_key,short_id:"6ba85179e30d4fc2"}},packet_encoding:"xudp"}' --arg tag "${email}" --arg server "${entryHost}" --argjson port "${port}" --arg uuid "${id}" --arg sni "${realitySNI}" --arg public_key "${publicKey}") || return 1
    appendSingBoxSubscribeLocalConfig "${user}" "${singBoxFilter}" || return 1

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
    appendDefaultSubscribeLine "${user}" "${defaultLink}" || return 1
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
    client-fingerprint: chrome" || return 1

    local singBoxFilter
    singBoxFilter=$(singBoxSubscribeAppendFilter '{tag:$tag,type:"vless",server:$server,server_port:$port,uuid:$uuid,tls:{enabled:true,server_name:$sni,utls:{enabled:true,fingerprint:"chrome"},reality:{enabled:true,public_key:$public_key,short_id:"6ba85179e30d4fc2"}},packet_encoding:"xudp",transport:{type:"grpc",service_name:"grpc"}}' --arg tag "${email}" --arg server "${entryHost}" --argjson port "${port}" --arg uuid "${id}" --arg sni "${realitySNI}" --arg public_key "${publicKey}") || return 1
    appendSingBoxSubscribeLocalConfig "${user}" "${singBoxFilter}" || return 1

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
    singBoxFilter=$(singBoxSubscribeAppendFilter '{tag:$tag,type:"tuic",server:$server,server_port:$port,uuid:$uuid,password:$password,congestion_control:$congestion,udp_relay_mode:"native",zero_rtt_handshake:false,tls:{enabled:true,server_name:$sni,alpn:["h3"]}}' --arg tag "${email}" --arg server "${currentHost}" --argjson port "${singBoxServerPort}" --arg uuid "${tuicUUID}" --arg password "${tuicPassword}" --arg congestion "${tuicAlgorithm}" --arg sni "${currentHost}") || return 1

    appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"
    subscribeOutputTitle "v2rayN：Tuic TLS"
    echo "{\"relay\": {\"server\": \"${currentHost}:${port}\",\"uuid\": \"${tuicUUID}\",\"password\": \"${tuicPassword}\",\"ip\": \"${currentHost}\",\"congestion_control\": \"${tuicAlgorithm}\",\"alpn\": [\"h3\"]},\"local\": {\"server\": \"127.0.0.1:7798\"},\"log_level\": \"warn\"}" | jq

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
    singBoxFilter=$(singBoxSubscribeAppendFilter '{tag:$tag,type:"shadowsocks",server:$server,server_port:$port,method:$method,password:$password}' --arg tag "${email}" --arg server "${currentHost}" --argjson port "${port}" --arg method "${method}" --arg password "${id}") || return 1

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
    singBoxFilter=$(singBoxSubscribeAppendFilter '{tag:$tag,type:"vmess",server:$server,server_port:$port,uuid:$uuid,security:"auto",alter_id:0,tls:{enabled:true,server_name:$sni,utls:{enabled:true,fingerprint:"chrome"}},packet_encoding:"packetaddr",transport:{type:"httpupgrade",path:$path}}' --arg tag "${email}" --arg server "${add}" --argjson port "${port}" --arg uuid "${id}" --arg sni "${currentHost}" --arg path "${path}") || return 1
    appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

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
    singBoxFilter=$(singBoxSubscribeAppendFilter '{tag:$tag,type:"anytls",server:$server,server_port:$port,password:$password,tls:{enabled:true,server_name:$sni}}' --arg tag "${email}" --arg server "${currentHost}" --argjson port "${singBoxAnyTLSPort}" --arg password "${id}" --arg sni "${currentHost}") || return 1

    echoContent green "    ${defaultLink}\n"
    appendStandardTLSSubscribeOutputs "${user}" "${defaultLink}" "${clashMetaBlock}" "${singBoxFilter}"

}
