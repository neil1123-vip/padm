#!/usr/bin/env bash

subscriptionWireGuardDir() {
    echo "${PADM_WIREGUARD_CONTROL_DIR:-/etc/padm/wireguard}"
}

subscriptionWireGuardStateFile() {
    echo "$(subscriptionWireGuardDir)/control.json"
}

subscriptionWireGuardInterface() {
    echo "wg-padm"
}

subscriptionWireGuardConfigFile() {
    echo "/etc/wireguard/$(subscriptionWireGuardInterface).conf"
}

subscriptionWireGuardDefaultNetwork() {
    echo "10.77.0.0/24"
}

subscriptionWireGuardDefaultMainAddress() {
    echo "10.77.0.1/24"
}

subscriptionWireGuardDefaultListenPort() {
    echo 51820
}

subscriptionWireGuardDefaultControlPort() {
    echo 39778
}

subscriptionWireGuardPrivateKeyFile() {
    echo "$(subscriptionWireGuardDir)/private.key"
}

subscriptionWireGuardPublicKeyFile() {
    echo "$(subscriptionWireGuardDir)/public.key"
}

subscriptionWireGuardAddressHost() {
    local address=$1
    echo "${address%%/*}"
}

subscriptionWireGuardBase64UrlEncode() {
    base64 -w 0 | tr '+/' '-_' | tr -d '='
}

subscriptionWireGuardBase64UrlDecode() {
    local payload=$1
    local padding
    payload=$(printf '%s' "${payload}" | tr '_-' '/+')
    padding=$(( (4 - ${#payload} % 4) % 4 ))
    payload="${payload}$(printf '%*s' "${padding}" '' | tr ' ' '=')"
    printf '%s' "${payload}" | base64 -d 2>/dev/null
}

subscriptionWireGuardReadState() {
    local stateFile
    stateFile=$(subscriptionWireGuardStateFile)
    if [[ ! -f "${stateFile}" ]] || ! jq empty "${stateFile}" >/dev/null 2>&1; then
        jq -n \
          --arg interface "$(subscriptionWireGuardInterface)" \
          --arg network "$(subscriptionWireGuardDefaultNetwork)" \
          --argjson listenPort "$(subscriptionWireGuardDefaultListenPort)" \
          --argjson controlPort "$(subscriptionWireGuardDefaultControlPort)" \
          '{enabled:false, role:"uninitialized", interface:$interface, network:$network, listen_port:$listenPort, control_port:$controlPort, address:"", endpoint_host:"", public_key:"", peers:[]}'
        return 0
    fi
    jq -c \
      --arg interface "$(subscriptionWireGuardInterface)" \
      --arg network "$(subscriptionWireGuardDefaultNetwork)" \
      --argjson listenPort "$(subscriptionWireGuardDefaultListenPort)" \
      --argjson controlPort "$(subscriptionWireGuardDefaultControlPort)" \
      '({enabled:false, role:"uninitialized", interface:$interface, network:$network, listen_port:$listenPort, control_port:$controlPort, address:"", endpoint_host:"", public_key:"", peers:[]} + .) |
       .peers = ((.peers // []) | map({id:(.id // ""), name:(.name // .id // ""), address:(.address // ""), public_key:(.public_key // ""), endpoint:(.endpoint // ""), enabled:(if .enabled == false then false else true end)}) | map(select(.id != "" and .address != "" and .public_key != "")))' \
      "${stateFile}"
}

subscriptionWireGuardControlEnabled() {
    [[ "$(subscriptionWireGuardReadState | jq -r '.enabled')" == "true" ]]
}

subscriptionWireGuardWriteState() {
    local stateFile
    local tmpFile
    local stateJson
    local filter
    local jqArgs=()
    stateFile=$(subscriptionWireGuardStateFile)
    tmpFile="${stateFile}.tmp"
    mkdir -p "$(dirname "${stateFile}")"
    chmod 700 "$(dirname "${stateFile}")" 2>/dev/null || true
    while (($# > 1)); do
        jqArgs+=("$1")
        shift
    done
    filter=$1
    stateJson=$(subscriptionWireGuardReadState) || return 1
    if ! jq "${jqArgs[@]}" "${filter}" <<<"${stateJson}" >"${tmpFile}" || ! jq empty "${tmpFile}" >/dev/null 2>&1; then
        rm -f "${tmpFile}"
        return 1
    fi
    chmod 600 "${tmpFile}" 2>/dev/null || true
    mv "${tmpFile}" "${stateFile}"
}

subscriptionWireGuardRole() {
    subscriptionWireGuardReadState | jq -r '.role'
}

subscriptionWireGuardInstalled() {
    command -v wg >/dev/null 2>&1 && command -v wg-quick >/dev/null 2>&1
}

installSubscriptionWireGuardTools() {
    subscriptionWireGuardInstalled && return 0
    if [[ "${packageManager:-}" == "apt" ]]; then
        installOptionalPackageTracked "WireGuard" wireguard-tools || return 1
    elif [[ "${packageManager:-}" == "yum" ]]; then
        installOptionalPackageTracked "WireGuard" wireguard-tools || installOptionalPackageTracked "WireGuard" kmod-wireguard wireguard-tools || return 1
    elif [[ "${packageManager:-}" == "apk" ]]; then
        installOptionalPackageTracked "WireGuard" wireguard-tools || return 1
    else
        return 1
    fi
    subscriptionWireGuardInstalled
}

subscriptionWireGuardEnsureKeys() {
    local privateKeyFile
    local publicKeyFile
    local privateKey
    privateKeyFile=$(subscriptionWireGuardPrivateKeyFile)
    publicKeyFile=$(subscriptionWireGuardPublicKeyFile)
    mkdir -p "$(dirname "${privateKeyFile}")"
    chmod 700 "$(dirname "${privateKeyFile}")" 2>/dev/null || true
    if [[ ! -s "${privateKeyFile}" ]]; then
        privateKey=$(umask 077 && wg genkey) || return 1
        printf '%s\n' "${privateKey}" >"${privateKeyFile}"
        chmod 600 "${privateKeyFile}" 2>/dev/null || true
    fi
    wg pubkey <"${privateKeyFile}" | tr -d '[:space:]' >"${publicKeyFile}" || return 1
    chmod 600 "${publicKeyFile}" 2>/dev/null || true
}

subscriptionWireGuardPublicKey() {
    local publicKeyFile
    publicKeyFile=$(subscriptionWireGuardPublicKeyFile)
    if [[ ! -s "${publicKeyFile}" ]]; then
        subscriptionWireGuardEnsureKeys || return 1
    fi
    tr -d '[:space:]' <"${publicKeyFile}"
}

writeSubscriptionWireGuardConfig() {
    local state
    local privateKeyFile
    local configFile
    local tmpFile
    local listenPort
    local address
    local peer
    state=$(subscriptionWireGuardReadState)
    privateKeyFile=$(subscriptionWireGuardPrivateKeyFile)
    configFile=$(subscriptionWireGuardConfigFile)
    tmpFile="${configFile}.tmp"
    mkdir -p "$(dirname "${configFile}")"
    listenPort=$(jq -r '.listen_port' <<<"${state}")
    address=$(jq -r '.address' <<<"${state}")
    [[ -n "${address}" && -s "${privateKeyFile}" ]] || return 1
    {
        printf '[Interface]\n'
        printf 'Address = %s\n' "${address}"
        printf 'PrivateKey = %s\n' "$(tr -d '[:space:]' <"${privateKeyFile}")"
        printf 'ListenPort = %s\n' "${listenPort}"
        printf '\n'
        while IFS= read -r peer; do
            [[ -n "${peer}" ]] || continue
            printf '[Peer]\n'
            printf 'PublicKey = %s\n' "$(jq -r '.public_key' <<<"${peer}")"
            printf 'AllowedIPs = %s/32\n' "$(subscriptionWireGuardAddressHost "$(jq -r '.address' <<<"${peer}")")"
            if [[ -n "$(jq -r '.endpoint // empty' <<<"${peer}")" ]]; then
                printf 'Endpoint = %s\n' "$(jq -r '.endpoint' <<<"${peer}")"
                printf 'PersistentKeepalive = 25\n'
            fi
            printf '\n'
        done < <(jq -c '.peers[]? | select(.enabled == true)' <<<"${state}")
    } >"${tmpFile}"
    chmod 600 "${tmpFile}" 2>/dev/null || true
    mv "${tmpFile}" "${configFile}"
}

applySubscriptionWireGuardService() {
    local interface
    interface=$(subscriptionWireGuardInterface)
    writeSubscriptionWireGuardConfig || return 1
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet "wg-quick@${interface}"; then
            systemctl restart "wg-quick@${interface}" >/dev/null 2>&1 || return 1
        else
            systemctl enable --now "wg-quick@${interface}" >/dev/null 2>&1 || return 1
        fi
    elif command -v wg-quick >/dev/null 2>&1; then
        wg-quick down "${interface}" >/dev/null 2>&1 || true
        wg-quick up "${interface}" >/dev/null 2>&1 || return 1
    fi
}

subscriptionWireGuardNginxConfigFile() {
    echo "${nginxConfigPath:-/etc/nginx/conf.d/}padm-control-wg.conf"
}

ensureSubscriptionWireGuardNginx() {
    if command -v nginx >/dev/null 2>&1; then
        return 0
    fi
    installNginxTools || return 1
}

refreshSubscriptionWireGuardNginxControl() {
    ensureSubscriptionWireGuardNginx && ensureSubscriptionWireGuardNginxConfig && serviceQueueRestart nginx
}

stopSubscriptionWireGuardControlService() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now "wg-quick@$(subscriptionWireGuardInterface)" >/dev/null 2>&1 || true
    elif command -v wg-quick >/dev/null 2>&1; then
        wg-quick down "$(subscriptionWireGuardInterface)" >/dev/null 2>&1 || true
    fi
}

ensureSubscriptionWireGuardNginxConfig() {
    local state
    local listenHost
    local controlPort
    local targetPath
    local tmpPath
    state=$(subscriptionWireGuardReadState)
    listenHost=$(subscriptionWireGuardAddressHost "$(jq -r '.address' <<<"${state}")")
    controlPort=$(jq -r '.control_port' <<<"${state}")
    [[ -n "${listenHost}" && "${listenHost}" != "null" ]] || return 1
    targetPath=$(subscriptionWireGuardNginxConfigFile)
    tmpPath="${targetPath}.tmp"
    mkdir -p "$(dirname "${targetPath}")"
    cat >"${tmpPath}" <<EOF
server {
    listen ${listenHost}:${controlPort};
    server_name _;
    root ${nginxStaticPath};

    location /s/control/ {
        client_max_body_size 256k;
        proxy_pass http://127.0.0.1:$(subscriptionControlPort);
        proxy_set_header Authorization \$http_authorization;
        proxy_set_header Content-Type \$content_type;
    }

    location ~ ^/s/(clashMeta|default|clashMetaProfiles|sing-box|sing-box_profiles)/(.*) {
        default_type 'text/plain; charset=utf-8';
        alias /etc/padm/subscribe/\$1/\$2;
    }
}
EOF
    if command -v nginx >/dev/null 2>&1; then
        local backupPath="${targetPath}.bak"
        [[ -f "${targetPath}" ]] && cp "${targetPath}" "${backupPath}"
        mv "${tmpPath}" "${targetPath}"
        if ! nginx -t >/tmp/padm-wg-control-nginx-test.log 2>&1; then
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

subscriptionWireGuardControlUrl() {
    local source=$1
    local endpoint=$2
    jq -er --arg endpoint "${endpoint}" 'select(.transport == "wireguard") | "http://" + .host + ":" + (.port | tostring) + "/s/control/" + $endpoint' <<<"${source}"
}

subscriptionWireGuardCredentialEncode() {
    local kind=$1
    local payload=$2
    printf '%s' "padmwg1:"
    jq -c --arg kind "${kind}" '. + {version:1, kind:$kind}' <<<"${payload}" | subscriptionWireGuardBase64UrlEncode
}

subscriptionWireGuardCredentialDecode() {
    local credential=$1
    local payload
    credential=$(printf '%s' "${credential}" | tr -d '[:space:]')
    [[ "${credential}" == padmwg1:* ]] || return 1
    payload=${credential#padmwg1:}
    payload=$(subscriptionWireGuardBase64UrlDecode "${payload}") || return 1
    jq -e -c 'select(.version == 1 and (.kind == "main" or .kind == "controlled"))' <<<"${payload}"
}

initSubscriptionWireGuardMain() {
    local endpointHost=
    local listenPort
    local controlPort
    local address
    if [[ "$(subscriptionWireGuardRole)" == "controlled" ]]; then
        errorCard "当前机器已初始化为被控" "第一版只支持星型拓扑，被控不能再作为主控"
        return 1
    fi
    installSubscriptionWireGuardTools || { errorCard "WireGuard 安装失败"; return 1; }
    subscriptionWireGuardEnsureKeys || { errorCard "WireGuard 密钥生成失败"; return 1; }
    listenPort=$(subscriptionWireGuardDefaultListenPort)
    controlPort=$(subscriptionWireGuardDefaultControlPort)
    address=$(subscriptionWireGuardDefaultMainAddress)
    autoRead wg_main_endpoint_host "请输入主控公网地址或域名[用于被控连接 WireGuard]:" endpointHost
    [[ -n "${endpointHost}" ]] || endpointHost=${currentHost:-}
    if [[ -z "${endpointHost}" ]]; then
        errorCard "主控接入地址不可为空" "请填写被控能访问到的主控公网 IP 或域名"
        return 1
    fi
    subscriptionWireGuardWriteState \
      --arg endpointHost "${endpointHost}" \
      --arg address "${address}" \
      --arg publicKey "$(subscriptionWireGuardPublicKey)" \
      --argjson listenPort "${listenPort}" \
      --argjson controlPort "${controlPort}" \
      '.enabled = true | .role = "main" | .address = $address | .endpoint_host = $endpointHost | .public_key = $publicKey | .listen_port = $listenPort | .control_port = $controlPort' || {
        errorCard "WireGuard 主控状态写入失败"
        return 1
      }
    applySubscriptionWireGuardService || {
        errorCard "WireGuard 主控服务启动失败"
        return 1
    }
    [[ -f "$(subscriptionWireGuardStateFile)" && -f "$(subscriptionWireGuardConfigFile)" ]] || {
        errorCard "WireGuard 主控配置未落地"
        return 1
    }
    successCard "WireGuard 主控已初始化" "接口：$(subscriptionWireGuardInterface)" "内网地址：${address}" "监听端口：${listenPort}/udp"
}

initSubscriptionWireGuardControlled() {
    local address=
    local controlPort
    if [[ "$(subscriptionWireGuardRole)" == "main" ]]; then
        errorCard "当前机器已初始化为主控" "第一版只支持星型拓扑，主控不能再作为被控"
        return 1
    fi
    installSubscriptionWireGuardTools || { errorCard "WireGuard 安装失败"; return 1; }
    subscriptionWireGuardEnsureKeys || { errorCard "WireGuard 密钥生成失败"; return 1; }
    controlPort=$(subscriptionWireGuardDefaultControlPort)
    autoRead wg_controlled_address "请输入本机 WireGuard 内网地址[默认 10.77.0.2/24]：" address
    [[ -n "${address}" ]] || address="10.77.0.2/24"
    if ! grep -qE '^[0-9.]+/[0-9]+$' <<<"${address}"; then
        errorCard "WireGuard 内网地址格式无效" "示例：10.77.0.2/24"
        return 1
    fi
    subscriptionWireGuardWriteState \
      --arg address "${address}" \
      --arg publicKey "$(subscriptionWireGuardPublicKey)" \
      --argjson controlPort "${controlPort}" \
      '.enabled = true | .role = "controlled" | .address = $address | .public_key = $publicKey | .control_port = $controlPort' || {
        errorCard "WireGuard 被控状态写入失败"
        return 1
      }
    applySubscriptionWireGuardService || {
        errorCard "WireGuard 被控服务启动失败"
        return 1
    }
    installSubscriptionControlService
    refreshSubscriptionWireGuardNginxControl && serviceQueueApply
    [[ -f "$(subscriptionWireGuardStateFile)" && -f "$(subscriptionWireGuardConfigFile)" ]] || {
        errorCard "WireGuard 被控配置未落地"
        return 1
    }
    successCard "WireGuard 被控已初始化" "接口：$(subscriptionWireGuardInterface)" "内网地址：${address}" "控制面：WireGuard 内网 ${controlPort} 端口"
}

showSubscriptionWireGuardMainCredential() {
    local state
    local payload
    state=$(subscriptionWireGuardReadState)
    if [[ "$(jq -r '.role' <<<"${state}")" != "main" ]]; then
        errorCard "本机还不是主控" "请先初始化本机为主控"
        return 1
    fi
    payload=$(jq -n \
      --arg endpointHost "$(jq -r '.endpoint_host' <<<"${state}")" \
      --argjson listenPort "$(jq -r '.listen_port' <<<"${state}")" \
      --arg network "$(jq -r '.network' <<<"${state}")" \
      --arg address "$(jq -r '.address' <<<"${state}")" \
      --arg publicKey "$(jq -r '.public_key' <<<"${state}")" \
      '{endpoint_host:$endpointHost, listen_port:$listenPort, network:$network, address:$address, public_key:$publicKey}')
    statusCard "本机主控接入凭据" "主控接入凭据：$(subscriptionWireGuardCredentialEncode main "${payload}")" "用途：复制到被控服务器导入" "凭据只包含 WireGuard 入网信息，不包含公网订阅地址"
}

importSubscriptionWireGuardMainCredential() {
    local credential=
    local credentialJson
    local endpoint
    autoRead wg_main_credential "请粘贴主控接入凭据:" credential
    credentialJson=$(subscriptionWireGuardCredentialDecode "${credential}") || { errorCard "主控接入凭据无效"; return 1; }
    if [[ "$(jq -r '.kind' <<<"${credentialJson}")" != "main" ]]; then
        errorCard "请粘贴主控接入凭据"
        return 1
    fi
    if [[ "$(subscriptionWireGuardRole)" != "controlled" ]]; then
        errorCard "请先初始化本机为被控" "第一版星型拓扑要求被控导入主控凭据"
        return 1
    fi
    endpoint="$(jq -r '.endpoint_host' <<<"${credentialJson}"):$(jq -r '.listen_port' <<<"${credentialJson}")"
    subscriptionWireGuardWriteState \
      --arg network "$(jq -r '.network' <<<"${credentialJson}")" \
      --arg mainAddress "$(jq -r '.address' <<<"${credentialJson}")" \
      --arg mainPublicKey "$(jq -r '.public_key' <<<"${credentialJson}")" \
      --arg endpoint "${endpoint}" \
      '.network = $network | .peers = [{id:"main", name:"主控", address:$mainAddress, public_key:$mainPublicKey, endpoint:$endpoint, enabled:true}]'
    applySubscriptionWireGuardService
    successCard "主控接入凭据已导入" "主控端点：${endpoint}" "下一步：查看本机被控接入凭据，并复制回主控添加"
}

showSubscriptionWireGuardControlledCredential() {
    local state
    local payload
    state=$(subscriptionWireGuardReadState)
    if [[ "$(jq -r '.role' <<<"${state}")" != "controlled" ]]; then
        errorCard "本机还不是被控" "请先初始化本机为被控，并导入主控接入凭据"
        return 1
    fi
    subscriptionControlEnsureToken
    payload=$(jq -n \
      --arg address "$(jq -r '.address' <<<"${state}")" \
      --arg publicKey "$(jq -r '.public_key' <<<"${state}")" \
      --argjson controlPort "$(jq -r '.control_port' <<<"${state}")" \
      --arg token "$(subscriptionControlToken)" \
      '{address:$address, public_key:$publicKey, control_port:$controlPort, token:$token}')
    statusCard "本机被控接入凭据" "被控接入凭据：$(subscriptionWireGuardCredentialEncode controlled "${payload}")" "用途：复制到主控服务器添加被控" "控制接口只通过 WireGuard 内网访问"
}

subscriptionWireGuardAddPeerFromCredential() {
    local alias=$1
    local credentialJson=$2
    local address
    local host
    local publicKey
    local controlPort
    local token
    if [[ "$(subscriptionWireGuardRole)" != "main" ]]; then
        errorCard "只有主控可以添加被控服务器" "第一版只支持一台主控管理多台被控"
        return 1
    fi
    [[ "$(jq -r '.kind' <<<"${credentialJson}")" == "controlled" ]] || return 1
    address=$(jq -r '.address' <<<"${credentialJson}")
    host=$(subscriptionWireGuardAddressHost "${address}")
    publicKey=$(jq -r '.public_key' <<<"${credentialJson}")
    controlPort=$(jq -r '.control_port' <<<"${credentialJson}")
    token=$(jq -r '.token' <<<"${credentialJson}")
    subscriptionWireGuardWriteState \
      --arg id "${alias}" \
      --arg address "${address}" \
      --arg publicKey "${publicKey}" \
      'if any(.peers[]?; .id == $id) then .peers |= map(if .id == $id then .address = $address | .public_key = $publicKey | .enabled = true else . end) else .peers += [{id:$id, name:$id, address:$address, public_key:$publicKey, enabled:true}] end'
    applySubscriptionWireGuardService
    addSubscriptionSourceState "${alias}" "${alias}" "${host}" "${controlPort}"
    setSubscriptionSourceCredential "${alias}" "${host}" "${controlPort}" "${token}"
}

showSubscriptionWireGuardStatus() {
    local state
    local roleText
    state=$(subscriptionWireGuardReadState)
    case "$(jq -r '.role' <<<"${state}")" in
    main) roleText="主控" ;;
    controlled) roleText="被控" ;;
    *) roleText="未初始化" ;;
    esac
    statusCard "WireGuard 控制面" "当前模式：${roleText}" "接口：$(jq -r '.interface' <<<"${state}")" "内网：$(jq -r '.network' <<<"${state}")" "本机内网地址：$(jq -r 'if (.address // "") == "" then "未配置" else .address end' <<<"${state}")" "控制端口：$(jq -r '.control_port' <<<"${state}")"
}

showSubscriptionWireGuardPeers() {
    subscriptionWireGuardReadState | jq -r '.peers[]? | "ID:\(.id)\n名称:\(.name)\n内网地址:\(.address)\n启用:\(.enabled)\n---"'
}

testSubscriptionWireGuardControl() {
    userJsonCard "WireGuard 控制面健康检查" "$(subscriptionRemoteControlHealthAll)"
}

restartSubscriptionWireGuardControl() {
    installSubscriptionControlService
    applySubscriptionWireGuardService
    refreshSubscriptionWireGuardNginxControl && serviceQueueApply
    successCard "WireGuard 控制面已修复/重启"
}

disableSubscriptionWireGuardControl() {
    stopSubscriptionWireGuardControlService
    subscriptionWireGuardWriteState '.enabled = false'
    successCard "WireGuard 控制面已关闭"
}
