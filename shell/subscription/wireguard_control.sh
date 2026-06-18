#!/usr/bin/env bash

subscriptionWireGuardDir() {
    echo "${PADM_WIREGUARD_CONTROL_DIR:-/etc/padm/wireguard}"
}

subscriptionWireGuardSafeDir() {
    local wireGuardDir
    wireGuardDir=$(subscriptionWireGuardDir)
    [[ -n "${wireGuardDir}" ]] || return 1
    [[ "${wireGuardDir}" == /* ]] || return 1
    padmIsSafeAbsolutePath "${wireGuardDir%/}" || return 1
    printf '%s\n' "${wireGuardDir%/}"
}

subscriptionWireGuardStateFile() {
    local wireGuardDir
    wireGuardDir=$(subscriptionWireGuardSafeDir) || return 1
    printf '%s/control.json\n' "${wireGuardDir}"
}

subscriptionWireGuardInterface() {
    echo "wg-padm"
}

subscriptionWireGuardConfigFile() {
    echo "/etc/wireguard/$(subscriptionWireGuardInterface).conf"
}

subscriptionWireGuardDefaultListenPort() {
    echo 51820
}

subscriptionWireGuardDefaultControlPort() {
    echo 39778
}

subscriptionWireGuardPrivateKeyFile() {
    local wireGuardDir
    wireGuardDir=$(subscriptionWireGuardSafeDir) || return 1
    printf '%s/private.key\n' "${wireGuardDir}"
}

subscriptionWireGuardPublicKeyFile() {
    local wireGuardDir
    wireGuardDir=$(subscriptionWireGuardSafeDir) || return 1
    printf '%s/public.key\n' "${wireGuardDir}"
}

subscriptionWireGuardAddressHost() {
    local address=$1
    echo "${address%%/*}"
}

subscriptionWireGuardValidIPv4Host() {
    local address=$1
    local host octet
    local -a octets
    [[ "${address}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -r -a octets <<<"${address}"
    for octet in "${octets[@]}"; do
        [[ "${octet}" =~ ^[0-9]+$ ]] && ((10#${octet} >= 0 && 10#${octet} <= 255)) || return 1
    done
}

subscriptionWireGuardValidHostname() {
    local host=$1
    [[ "${host}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]]
}

subscriptionWireGuardValidPort() {
    local port=$1
    [[ "${port}" =~ ^[0-9]+$ ]] && ((10#${port} >= 1 && 10#${port} <= 65535))
}

subscriptionWireGuardValidIPv4Cidr() {
    local address=$1
    local host cidr octet
    local -a octets
    [[ "${address}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || return 1
    host=${address%/*}
    cidr=${address#*/}
    ((10#${cidr} >= 0 && 10#${cidr} <= 32)) || return 1
    IFS=. read -r -a octets <<<"${host}"
    for octet in "${octets[@]}"; do
        [[ "${octet}" =~ ^[0-9]+$ ]] && ((10#${octet} >= 0 && 10#${octet} <= 255)) || return 1
    done
}

subscriptionWireGuardValidEndpointHost() {
    local host=$1
    [[ -n "${host}" && "${host}" != "null" && "${host}" != */* && "${host}" != *:* && ! "${host}" =~ [[:space:]] ]] &&
        (subscriptionWireGuardValidIPv4Host "${host}" || subscriptionWireGuardValidHostname "${host}")
}

subscriptionWireGuardValidTokenValue() {
    local value=$1
    [[ -n "${value}" && "${value}" != "null" && ! "${value}" =~ [[:space:]] ]]
}

subscriptionWireGuardValidPublicKeyValue() {
    local value=$1
    [[ -n "${value}" && "${value}" != "null" && ! "${value}" =~ [[:space:]] ]]
}

subscriptionWireGuardValidateMainCredentialJson() {
    local credentialJson=$1
    local endpointHost listenPort network address publicKey
    [[ "$(jq -r '.kind // empty' <<<"${credentialJson}")" == "main" ]] || return 1
    endpointHost=$(jq -r '.endpoint_host // empty' <<<"${credentialJson}")
    listenPort=$(jq -r '.listen_port // empty' <<<"${credentialJson}")
    network=$(jq -r '.network // empty' <<<"${credentialJson}")
    address=$(jq -r '.address // empty' <<<"${credentialJson}")
    publicKey=$(jq -r '.public_key // empty' <<<"${credentialJson}")
    subscriptionWireGuardValidEndpointHost "${endpointHost}" &&
        subscriptionWireGuardValidPort "${listenPort}" &&
        subscriptionWireGuardValidIPv4Cidr "${network}" &&
        subscriptionWireGuardValidIPv4Cidr "${address}" &&
        subscriptionWireGuardValidPublicKeyValue "${publicKey}"
}

subscriptionWireGuardValidateControlledCredentialJson() {
    local credentialJson=$1
    local address publicKey controlPort token
    [[ "$(jq -r '.kind // empty' <<<"${credentialJson}")" == "controlled" ]] || return 1
    address=$(jq -r '.address // empty' <<<"${credentialJson}")
    publicKey=$(jq -r '.public_key // empty' <<<"${credentialJson}")
    controlPort=$(jq -r '.control_port // empty' <<<"${credentialJson}")
    token=$(jq -r '.token // empty' <<<"${credentialJson}")
    subscriptionWireGuardValidIPv4Cidr "${address}" &&
        subscriptionWireGuardValidPublicKeyValue "${publicKey}" &&
        subscriptionWireGuardValidPort "${controlPort}" &&
        subscriptionWireGuardValidTokenValue "${token}"
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
          --arg network "10.77.0.0/24" \
          --argjson listenPort "$(subscriptionWireGuardDefaultListenPort)" \
          --argjson controlPort "$(subscriptionWireGuardDefaultControlPort)" \
          '{enabled:false, role:"uninitialized", interface:$interface, network:$network, listen_port:$listenPort, control_port:$controlPort, address:"", endpoint_host:"", public_key:"", peers:[]}'
        return 0
    fi
    jq -c \
      --arg interface "$(subscriptionWireGuardInterface)" \
      --arg network "10.77.0.0/24" \
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
    local stateDir
    local tmpFile
    local stateJson
    local filter
    local jqArgs=()
    stateFile=$(subscriptionWireGuardStateFile)
    [[ -n "${stateFile}" ]] || return 1
    stateDir=$(dirname "${stateFile}")
    padmEnsureSafeDirectory "${stateDir}" || return 1
    chmod 700 "${stateDir}" 2>/dev/null || true
    padmCreateTempFileForTarget tmpFile "${stateFile}" state || return 1
    while (($# > 1)); do
        jqArgs+=("$1")
        shift
    done
    filter=$1
    stateJson=$(subscriptionWireGuardReadState) || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    if ! jq "${jqArgs[@]}" "${filter}" <<<"${stateJson}" >"${tmpFile}" || ! jq empty "${tmpFile}" >/dev/null 2>&1; then
        padmRemoveCleanupPath "${tmpFile}"
        return 1
    fi
    commitGeneratedJsonFile "${tmpFile}" "${stateFile}" 600 || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

subscriptionWireGuardRestoreStateAndConfig() {
    local previousState=$1
    local previousAddress
    previousAddress=$(jq -r '.address // empty' <<<"${previousState}") || return 1
    subscriptionWireGuardWriteState --argjson previousState "${previousState}" '$previousState' >/dev/null 2>&1 || return 1
    if [[ -n "${previousAddress}" ]]; then
        applySubscriptionWireGuardService >/dev/null 2>&1 || return 1
    else
        stopSubscriptionWireGuardControlService true >/dev/null 2>&1 || return 1
        rm -f "$(subscriptionWireGuardConfigFile)" >/dev/null 2>&1 || return 1
    fi
}

subscriptionWireGuardRestoreGroupsState() {
    local previousGroupsState=$1
    subscriptionGroupsStateWrite --argjson previousGroupsState "${previousGroupsState}" '$previousGroupsState' >/dev/null 2>&1 || return 1
}

subscriptionWireGuardReportRestoreFailure() {
    local failureTitle=$1
    local groupsFile=
    if declare -F subscriptionGroupsFile >/dev/null 2>&1; then
        groupsFile=$(subscriptionGroupsFile)
    fi
    if [[ -n "${groupsFile}" ]]; then
        errorCard "${failureTitle}，且旧状态恢复失败" "请手动检查 WireGuard 状态文件：$(subscriptionWireGuardStateFile)" "请手动检查 WireGuard 配置文件：$(subscriptionWireGuardConfigFile)" "请手动检查订阅组状态文件：${groupsFile}"
    else
        errorCard "${failureTitle}，且旧状态恢复失败" "请手动检查 WireGuard 状态文件：$(subscriptionWireGuardStateFile)" "请手动检查 WireGuard 配置文件：$(subscriptionWireGuardConfigFile)"
    fi
}

subscriptionWireGuardRestoreStateOrReport() {
    local previousState=$1
    local failureTitle=$2
    if ! subscriptionWireGuardRestoreStateAndConfig "${previousState}" >/dev/null 2>&1; then
        subscriptionWireGuardReportRestoreFailure "${failureTitle}"
        return 1
    fi
}

subscriptionWireGuardRestoreStateAndGroupsOrReport() {
    local previousState=$1
    local previousGroupsState=$2
    local failureTitle=$3
    local restoreFailed=false
    subscriptionWireGuardRestoreStateAndConfig "${previousState}" >/dev/null 2>&1 || restoreFailed=true
    subscriptionWireGuardRestoreGroupsState "${previousGroupsState}" >/dev/null 2>&1 || restoreFailed=true
    if [[ "${restoreFailed}" == "true" ]]; then
        subscriptionWireGuardReportRestoreFailure "${failureTitle}"
        return 1
    fi
}

subscriptionWireGuardRole() {
    subscriptionWireGuardReadState | jq -r '.role'
}

installSubscriptionWireGuardTools() {
    command -v wg >/dev/null 2>&1 && command -v wg-quick >/dev/null 2>&1 && return 0
    if [[ "${packageManager:-}" == "apt" ]]; then
        installOptionalPackageTracked "WireGuard" wireguard-tools || return 1
    elif [[ "${packageManager:-}" == "yum" ]]; then
        installOptionalPackageTracked "WireGuard" wireguard-tools || installOptionalPackageTracked "WireGuard" kmod-wireguard wireguard-tools || return 1
    elif [[ "${packageManager:-}" == "apk" ]]; then
        installOptionalPackageTracked "WireGuard" wireguard-tools || return 1
    else
        return 1
    fi
    command -v wg >/dev/null 2>&1 && command -v wg-quick >/dev/null 2>&1
}

subscriptionWireGuardEnsureKeys() {
    local privateKeyFile
    local publicKeyFile
    local privateKey
    local privateDir
    local privateStage
    local publicStage
    local rollbackDir=
    local privateBackup=
    local publicBackup=
    local rollbackStatus=0
    local tmpBase="${TMPDIR:-/tmp}"
    privateKeyFile=$(subscriptionWireGuardPrivateKeyFile)
    publicKeyFile=$(subscriptionWireGuardPublicKeyFile)
    [[ -n "${privateKeyFile}" && -n "${publicKeyFile}" ]] || return 1
    privateDir=$(dirname "${privateKeyFile}")
    padmEnsureSafeDirectory "${privateDir}" || return 1
    chmod 700 "${privateDir}" 2>/dev/null || true
    if [[ ! -s "${privateKeyFile}" ]]; then
        privateKey=$(umask 077 && wg genkey) || return 1
        [[ -n "${privateKey}" ]] || return 1
        padmCreateTempFileForTarget privateStage "${privateKeyFile}" wireguard || return 1
        printf '%s\n' "${privateKey}" >"${privateStage}" || { padmRemoveCleanupPath "${privateStage}"; return 1; }
        padmCreateTempFileForTarget publicStage "${publicKeyFile}" wireguard || { padmRemoveCleanupPath "${privateStage}"; return 1; }
        if ! wg pubkey <"${privateStage}" | tr -d '[:space:]' >"${publicStage}"; then
            padmRemoveCleanupPath "${publicStage}"
            padmRemoveCleanupPath "${privateStage}"
            return 1
        fi
        [[ -s "${publicStage}" ]] || { padmRemoveCleanupPath "${publicStage}"; padmRemoveCleanupPath "${privateStage}"; return 1; }
        padmCreateTempPath rollbackDir -d "${tmpBase%/}/padm-wireguard-keys.XXXXXX" || {
            padmRemoveCleanupPath "${publicStage}"
            padmRemoveCleanupPath "${privateStage}"
            return 1
        }
        if [[ -f "${privateKeyFile}" ]]; then
            privateBackup="${rollbackDir}/private.key"
            backupManagedFileToPath "${privateKeyFile}" "${privateBackup}" 600 || {
                padmRemoveCleanupPath "${rollbackDir}"
                padmRemoveCleanupPath "${publicStage}"
                padmRemoveCleanupPath "${privateStage}"
                return 1
            }
        fi
        if [[ -f "${publicKeyFile}" ]]; then
            publicBackup="${rollbackDir}/public.key"
            backupManagedFileToPath "${publicKeyFile}" "${publicBackup}" 600 || {
                padmRemoveCleanupPath "${rollbackDir}"
                padmRemoveCleanupPath "${publicStage}"
                padmRemoveCleanupPath "${privateStage}"
                return 1
            }
        fi
        if ! commitGeneratedFile "${privateStage}" "${privateKeyFile}" 600; then
            padmRemoveCleanupPath "${privateStage}"
            padmRemoveCleanupPath "${publicStage}"
            padmRemoveCleanupPath "${rollbackDir}"
            return 1
        fi
        if ! commitGeneratedFile "${publicStage}" "${publicKeyFile}" 600; then
            padmRemoveCleanupPath "${publicStage}"
            if [[ -n "${privateBackup}" ]]; then
                restoreManagedFileFromBackup "${privateBackup}" "${privateKeyFile}" 600 || rollbackStatus=1
            else
                removeManagedFileIfPresent "${privateKeyFile}" || rollbackStatus=1
            fi
            if [[ -n "${publicBackup}" ]]; then
                restoreManagedFileFromBackup "${publicBackup}" "${publicKeyFile}" 600 || rollbackStatus=1
            else
                removeManagedFileIfPresent "${publicKeyFile}" || rollbackStatus=1
            fi
            padmRemoveCleanupPath "${rollbackDir}"
            [[ "${rollbackStatus}" == "0" ]] || return 1
            return 1
        fi
        padmRemoveCleanupPath "${rollbackDir}"
    else
        padmCreateTempFileForTarget publicStage "${publicKeyFile}" wireguard || return 1
        if ! wg pubkey <"${privateKeyFile}" | tr -d '[:space:]' >"${publicStage}"; then
            padmRemoveCleanupPath "${publicStage}"
            return 1
        fi
        [[ -s "${publicStage}" ]] || { padmRemoveCleanupPath "${publicStage}"; return 1; }
        commitGeneratedFile "${publicStage}" "${publicKeyFile}" 600 || { padmRemoveCleanupPath "${publicStage}"; return 1; }
    fi
    chmod 600 "${privateKeyFile}" "${publicKeyFile}" 2>/dev/null || true
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
    padmCreateTempFileForTarget tmpFile "${configFile}" wireguard || return 1
    listenPort=$(jq -r '.listen_port' <<<"${state}")
    address=$(jq -r '.address' <<<"${state}")
    [[ -n "${address}" && -s "${privateKeyFile}" ]] || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
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
    } >"${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    commitGeneratedFile "${tmpFile}" "${configFile}" 600 || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
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
    else
        return 1
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

subscriptionWireGuardWaitForAddress() {
    local address=$1
    local host
    local attempts=${2:-20}
    local delay=${3:-0.2}
    local tryIndex
    host=$(subscriptionWireGuardAddressHost "${address}")
    [[ -n "${host}" ]] || return 1
    for ((tryIndex = 0; tryIndex < attempts; tryIndex++)); do
        if ip -4 addr show 2>/dev/null | grep -qE "[[:space:]]${host}/"; then
            return 0
        fi
        sleep "${delay}"
    done
    return 1
}

stopSubscriptionWireGuardControlService() {
    local allowMissingBackend=${1:-false}
    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now "wg-quick@$(subscriptionWireGuardInterface)" >/dev/null 2>&1
    elif command -v wg-quick >/dev/null 2>&1; then
        wg-quick down "$(subscriptionWireGuardInterface)" >/dev/null 2>&1
    else
        [[ "${allowMissingBackend}" == "true" ]]
    fi
}

ensureSubscriptionWireGuardNginxConfig() {
    local state
    local listenHost
    local controlPort
    local targetPath
    local tmpPath
    local backupPath=
    state=$(subscriptionWireGuardReadState)
    listenHost=$(subscriptionWireGuardAddressHost "$(jq -r '.address' <<<"${state}")")
    controlPort=$(jq -r '.control_port' <<<"${state}")
    [[ -n "${listenHost}" && "${listenHost}" != "null" ]] || return 1
    targetPath=$(subscriptionWireGuardNginxConfigFile)
    padmCreateTempFileForTarget tmpPath "${targetPath}" nginx || return 1
    cat >"${tmpPath}" <<EOF || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
server {
    listen ${listenHost}:${controlPort};
    server_name _;
    root ${nginxStaticPath};

    location /s/control/ {
        access_log $(fail2banPadmControlLogFile);
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
        if [[ -f "${targetPath}" ]]; then
            padmCreateTempFileForTarget backupPath "${targetPath}" backup || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
            cp "${targetPath}" "${backupPath}" || { padmRemoveCleanupPath "${tmpPath}"; padmRemoveCleanupPath "${backupPath}"; return 1; }
        fi
        commitGeneratedFile "${tmpPath}" "${targetPath}" 644 || { padmRemoveCleanupPath "${tmpPath}"; [[ -n "${backupPath}" ]] && padmRemoveCleanupPath "${backupPath}"; return 1; }
        if ! nginx -t >/tmp/padm-wg-control-nginx-test.log 2>&1; then
            if [[ -n "${backupPath}" && -f "${backupPath}" ]]; then
                commitGeneratedFile "${backupPath}" "${targetPath}" 644 || padmRemoveCleanupPath "${backupPath}"
            else
                rm -f "${targetPath}"
            fi
            return 1
        fi
        [[ -n "${backupPath}" ]] && padmRemoveCleanupPath "${backupPath}"
    else
        commitGeneratedFile "${tmpPath}" "${targetPath}" 644 || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
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
    local kind
    credential=$(printf '%s' "${credential}" | tr -d '[:space:]')
    [[ "${credential}" == padmwg1:* ]] || return 1
    payload=${credential#padmwg1:}
    payload=$(subscriptionWireGuardBase64UrlDecode "${payload}") || return 1
    payload=$(jq -e -c 'select(.version == 1 and (.kind == "main" or .kind == "controlled"))' <<<"${payload}") || return 1
    kind=$(jq -r '.kind' <<<"${payload}")
    case "${kind}" in
    main)
        subscriptionWireGuardValidateMainCredentialJson "${payload}" || return 1
        ;;
    controlled)
        subscriptionWireGuardValidateControlledCredentialJson "${payload}" || return 1
        ;;
    *)
        return 1
        ;;
    esac
    printf '%s\n' "${payload}"
}

initSubscriptionWireGuardMain() {
    local endpointHost=
    local listenPort
    local controlPort
    local address
    local publicKey
    local previousState
    if [[ "$(subscriptionWireGuardRole)" == "controlled" ]]; then
        errorCard "当前机器已初始化为被控" "第一版只支持星型拓扑，被控不能再作为主控"
        return 1
    fi
    previousState=$(subscriptionWireGuardReadState) || {
        errorCard "WireGuard 状态读取失败"
        return 1
    }
    installSubscriptionWireGuardTools || { errorCard "WireGuard 安装失败"; return 1; }
    subscriptionWireGuardEnsureKeys || { errorCard "WireGuard 密钥生成失败"; return 1; }
    listenPort=$(subscriptionWireGuardDefaultListenPort)
    controlPort=$(subscriptionWireGuardDefaultControlPort)
    address="10.77.0.1/24"
    autoRead wg_main_endpoint_host "请输入主控公网地址或域名[用于被控连接 WireGuard]:" endpointHost
    [[ -n "${endpointHost}" ]] || endpointHost=${currentHost:-}
    if ! subscriptionWireGuardValidEndpointHost "${endpointHost}"; then
        errorCard "主控接入地址无效" "请填写被控能访问到的主控公网 IP 或域名，不要包含协议、路径或空格"
        return 1
    fi
    publicKey=$(subscriptionWireGuardPublicKey) || {
        errorCard "WireGuard 公钥读取失败"
        return 1
    }
    subscriptionWireGuardValidPublicKeyValue "${publicKey}" || {
        errorCard "WireGuard 公钥无效"
        return 1
    }
    subscriptionWireGuardWriteState \
      --arg endpointHost "${endpointHost}" \
      --arg address "${address}" \
      --arg publicKey "${publicKey}" \
      --argjson listenPort "${listenPort}" \
      --argjson controlPort "${controlPort}" \
      '.enabled = true | .role = "main" | .address = $address | .endpoint_host = $endpointHost | .public_key = $publicKey | .listen_port = $listenPort | .control_port = $controlPort' || {
        errorCard "WireGuard 主控状态写入失败"
        return 1
      }
    applySubscriptionWireGuardService || {
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard 主控服务启动失败" || return 1
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
    local publicKey
    local previousState
    if [[ "$(subscriptionWireGuardRole)" == "main" ]]; then
        errorCard "当前机器已初始化为主控" "第一版只支持星型拓扑，主控不能再作为被控"
        return 1
    fi
    previousState=$(subscriptionWireGuardReadState) || {
        errorCard "WireGuard 状态读取失败"
        return 1
    }
    installSubscriptionWireGuardTools || { errorCard "WireGuard 安装失败"; return 1; }
    subscriptionWireGuardEnsureKeys || { errorCard "WireGuard 密钥生成失败"; return 1; }
    controlPort=$(subscriptionWireGuardDefaultControlPort)
    autoRead wg_controlled_address "请输入本机 WireGuard 内网地址[默认 10.77.0.2/24]：" address
    [[ -n "${address}" ]] || address="10.77.0.2/24"
    if ! subscriptionWireGuardValidIPv4Cidr "${address}"; then
        errorCard "WireGuard 内网地址格式无效" "示例：10.77.0.2/24"
        return 1
    fi
    publicKey=$(subscriptionWireGuardPublicKey) || {
        errorCard "WireGuard 公钥读取失败"
        return 1
    }
    subscriptionWireGuardValidPublicKeyValue "${publicKey}" || {
        errorCard "WireGuard 公钥无效"
        return 1
    }
    subscriptionWireGuardWriteState \
      --arg address "${address}" \
      --arg publicKey "${publicKey}" \
      --argjson controlPort "${controlPort}" \
      '.enabled = true | .role = "controlled" | .address = $address | .public_key = $publicKey | .control_port = $controlPort' || {
        errorCard "WireGuard 被控状态写入失败"
        return 1
      }
    applySubscriptionWireGuardService || {
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard 被控服务启动失败" || return 1
        errorCard "WireGuard 被控服务启动失败"
        return 1
    }
    subscriptionWireGuardWaitForAddress "${address}" || {
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard 被控地址就绪失败" || return 1
        errorCard "WireGuard 被控地址就绪失败"
        return 1
    }
    installSubscriptionControlService || {
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "被控控制服务安装失败" || return 1
        errorCard "被控控制服务安装失败"
        return 1
    }
    refreshSubscriptionWireGuardNginxControl || {
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard Nginx 控制面配置失败" || return 1
        errorCard "WireGuard Nginx 控制面配置失败"
        return 1
    }
    serviceQueueApply || {
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard Nginx 控制面重载失败" || return 1
        errorCard "WireGuard Nginx 控制面重载失败"
        return 1
    }
    [[ -f "$(subscriptionWireGuardStateFile)" && -f "$(subscriptionWireGuardConfigFile)" ]] || {
        errorCard "WireGuard 被控配置未落地"
        return 1
    }
    successCard "WireGuard 被控已初始化" "接口：$(subscriptionWireGuardInterface)" "内网地址：${address}" "控制面：WireGuard 内网 ${controlPort} 端口" "无需安装公网订阅服务；把被控接入凭据交回主控即可"
}

showSubscriptionWireGuardMainCredential() {
    local state
    local payload
    local credentialJson
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
      '{endpoint_host:$endpointHost, listen_port:$listenPort, network:$network, address:$address, public_key:$publicKey}') || {
        errorCard "主控状态读取失败"
        return 1
      }
    credentialJson=$(jq -c '. + {version:1, kind:"main"}' <<<"${payload}") || {
        errorCard "主控状态读取失败"
        return 1
    }
    subscriptionWireGuardValidateMainCredentialJson "${credentialJson}" || {
        errorCard "主控状态不完整，无法导出接入凭据" "请先修复/重启 WireGuard 控制面"
        return 1
    }
    statusCard "本机主控接入凭据" "主控接入凭据：$(subscriptionWireGuardCredentialEncode main "${payload}")" "用途：复制到被控服务器导入" "凭据只包含 WireGuard 入网信息，不包含公网订阅地址"
}

importSubscriptionWireGuardMainCredential() {
    local credential=
    local credentialJson
    local endpoint
    local previousState
    autoRead wg_main_credential "请粘贴主控接入凭据:" credential
    credentialJson=$(subscriptionWireGuardCredentialDecode "${credential}") || { errorCard "主控接入凭据无效"; return 1; }
    if [[ "$(jq -r '.kind' <<<"${credentialJson}")" != "main" ]]; then
        errorCard "请粘贴主控接入凭据"
        return 1
    fi
    subscriptionWireGuardValidateMainCredentialJson "${credentialJson}" || {
        errorCard "主控接入凭据字段不完整或格式无效"
        return 1
    }
    if [[ "$(subscriptionWireGuardRole)" != "controlled" ]]; then
        errorCard "请先初始化本机为被控" "第一版星型拓扑要求被控导入主控凭据"
        return 1
    fi
    previousState=$(subscriptionWireGuardReadState) || {
        errorCard "当前 WireGuard 状态读取失败"
        return 1
    }
    endpoint="$(jq -r '.endpoint_host' <<<"${credentialJson}"):$(jq -r '.listen_port' <<<"${credentialJson}")"
    subscriptionWireGuardWriteState \
      --arg network "$(jq -r '.network' <<<"${credentialJson}")" \
      --arg mainAddress "$(jq -r '.address' <<<"${credentialJson}")" \
      --arg mainPublicKey "$(jq -r '.public_key' <<<"${credentialJson}")" \
      --arg endpoint "${endpoint}" \
      '.network = $network | .peers = [{id:"main", name:"主控", address:$mainAddress, public_key:$mainPublicKey, endpoint:$endpoint, enabled:true}]' || {
        errorCard "主控接入状态写入失败"
        return 1
      }
    applySubscriptionWireGuardService || {
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard 主控接入服务启动失败" || return 1
        errorCard "WireGuard 主控接入服务启动失败"
        return 1
    }
    successCard "主控接入凭据已导入" "主控端点：${endpoint}" "下一步：查看本机被控接入凭据，并复制回主控添加"
}

showSubscriptionWireGuardControlledCredential() {
    local state
    local payload
    local credentialJson
    local token
    state=$(subscriptionWireGuardReadState)
    if [[ "$(jq -r '.role' <<<"${state}")" != "controlled" ]]; then
        errorCard "本机还不是被控" "请先初始化本机为被控，并导入主控接入凭据"
        return 1
    fi
    subscriptionControlEnsureToken || {
        errorCard "控制 Token 生成失败"
        return 1
    }
    token=$(subscriptionControlToken)
    payload=$(jq -n \
      --arg address "$(jq -r '.address' <<<"${state}")" \
      --arg publicKey "$(jq -r '.public_key' <<<"${state}")" \
      --argjson controlPort "$(jq -r '.control_port' <<<"${state}")" \
      --arg token "${token}" \
      '{address:$address, public_key:$publicKey, control_port:$controlPort, token:$token}') || {
        errorCard "被控状态读取失败"
        return 1
      }
    credentialJson=$(jq -c '. + {version:1, kind:"controlled"}' <<<"${payload}") || {
        errorCard "被控状态读取失败"
        return 1
    }
    subscriptionWireGuardValidateControlledCredentialJson "${credentialJson}" || {
        errorCard "被控状态不完整，无法导出接入凭据" "请先修复/重启 WireGuard 控制面"
        return 1
    }
    statusCard "本机被控接入凭据" "被控接入凭据：$(subscriptionWireGuardCredentialEncode controlled "${payload}")" "用途：复制到主控服务器添加被控" "控制接口只通过 WireGuard 内网访问" "无需安装公网订阅服务"
}

subscriptionWireGuardAddPeerFromCredential() {
    local alias=$1
    local credentialJson=$2
    local address
    local host
    local publicKey
    local controlPort
    local token
    local previousState
    local previousGroupsState
    if [[ "$(subscriptionWireGuardRole)" != "main" ]]; then
        errorCard "只有主控可以添加被控服务器" "第一版只支持一台主控管理多台被控"
        return 1
    fi
    [[ -n "${alias}" && "${alias}" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
    [[ "$(jq -r '.kind' <<<"${credentialJson}")" == "controlled" ]] || return 1
    subscriptionWireGuardValidateControlledCredentialJson "${credentialJson}" || return 1
    address=$(jq -r '.address' <<<"${credentialJson}")
    host=$(subscriptionWireGuardAddressHost "${address}")
    publicKey=$(jq -r '.public_key' <<<"${credentialJson}")
    controlPort=$(jq -r '.control_port' <<<"${credentialJson}")
    token=$(jq -r '.token' <<<"${credentialJson}")
    previousState=$(subscriptionWireGuardReadState) || return 1
    previousGroupsState=$(subscriptionGroupsStateRead -c '.') || {
        errorCard "订阅组状态读取失败"
        return 1
    }
    subscriptionWireGuardWriteState \
      --arg id "${alias}" \
      --arg address "${address}" \
      --arg publicKey "${publicKey}" \
      'if any(.peers[]?; .id == $id) then .peers |= map(if .id == $id then .address = $address | .public_key = $publicKey | .enabled = true else . end) else .peers += [{id:$id, name:$id, address:$address, public_key:$publicKey, enabled:true}] end' || return 1
    if ! applySubscriptionWireGuardService; then
        subscriptionWireGuardRestoreStateAndGroupsOrReport "${previousState}" "${previousGroupsState}" "WireGuard 被控服务器服务应用失败" || return 1
        return 1
    fi
    if ! addSubscriptionSourceState "${alias}" "${alias}" "${host}" "${controlPort}"; then
        subscriptionWireGuardRestoreStateAndGroupsOrReport "${previousState}" "${previousGroupsState}" "订阅来源状态写入失败" || return 1
        return 1
    fi
    if ! setSubscriptionSourceCredential "${alias}" "${host}" "${controlPort}" "${token}"; then
        subscriptionWireGuardRestoreStateAndGroupsOrReport "${previousState}" "${previousGroupsState}" "订阅来源凭据写入失败" || return 1
        return 1
    fi
}

subscriptionWireGuardUpdatePeerFromCredential() {
    local id=$1
    local credentialJson=$2
    local address
    local publicKey
    [[ -n "${id}" ]] || return 1
    [[ "$(jq -r '.kind' <<<"${credentialJson}")" == "controlled" ]] || return 1
    subscriptionWireGuardValidateControlledCredentialJson "${credentialJson}" || return 1
    address=$(jq -r '.address' <<<"${credentialJson}")
    publicKey=$(jq -r '.public_key' <<<"${credentialJson}")
    subscriptionWireGuardWriteState \
      --arg id "${id}" \
      --arg address "${address}" \
      --arg publicKey "${publicKey}" \
      'if any(.peers[]?; .id == $id) then
         .peers |= map(if .id == $id then .address = $address | .public_key = $publicKey | .enabled = true else . end)
       else
         .peers += [{id:$id, name:$id, address:$address, public_key:$publicKey, enabled:true}]
       end'
}

subscriptionWireGuardRemovePeerAndSource() {
    local id=$1
    local previousState
    local previousGroupsState
    [[ -n "${id}" ]] || return 1
    if [[ "$(subscriptionWireGuardRole)" != "main" ]]; then
        errorCard "只有主控可以移除被控服务器" "第一版只支持一台主控管理多台被控"
        return 1
    fi
    previousState=$(subscriptionWireGuardReadState) || return 1
    previousGroupsState=$(subscriptionGroupsStateRead -c '.') || {
        errorCard "订阅组状态读取失败"
        return 1
    }
    subscriptionWireGuardWriteState \
      --arg id "${id}" \
      '.peers = ([.peers[]? | select(.id != $id)])' || return 1
    if ! applySubscriptionWireGuardService; then
        subscriptionWireGuardRestoreStateAndGroupsOrReport "${previousState}" "${previousGroupsState}" "WireGuard 被控服务器移除失败" || return 1
        return 1
    fi
    if ! removeSubscriptionSourceState "${id}"; then
        subscriptionWireGuardRestoreStateAndGroupsOrReport "${previousState}" "${previousGroupsState}" "被控服务器状态移除失败" || return 1
        return 1
    fi
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

restartSubscriptionWireGuardControl() {
    installSubscriptionControlService || {
        errorCard "订阅控制服务安装失败"
        return 1
    }
    applySubscriptionWireGuardService || {
        errorCard "WireGuard 服务重启失败"
        return 1
    }
    refreshSubscriptionWireGuardNginxControl || {
        errorCard "WireGuard Nginx 控制面配置失败"
        return 1
    }
    serviceQueueApply || {
        errorCard "WireGuard Nginx 控制面重载失败"
        return 1
    }
    successCard "WireGuard 控制面已修复/重启"
}

disableSubscriptionWireGuardControl() {
    local previousState
    previousState=$(subscriptionWireGuardReadState) || {
        errorCard "WireGuard 控制面状态读取失败"
        return 1
    }
    if ! stopSubscriptionWireGuardControlService; then
        errorCard "WireGuard 控制面停用失败"
        return 1
    fi
    subscriptionWireGuardWriteState '.enabled = false' || {
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard 控制面关闭状态写入失败" || return 1
        errorCard "WireGuard 控制面状态写入失败"
        return 1
    }
    successCard "WireGuard 控制面已关闭"
}
