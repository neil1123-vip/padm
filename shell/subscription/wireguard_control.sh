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

subscriptionWireGuardNginxTestLog() {
    padmFallbackTmpFilePath padm-wg-control-nginx-test.log
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

subscriptionWireGuardIPv4HostValue() {
    local host=$1
    local a b c d
    local IFS=.
    read -r a b c d <<<"${host}"
    printf '%u\n' "$(( (10#${a} << 24) + (10#${b} << 16) + (10#${c} << 8) + 10#${d} ))"
}

subscriptionWireGuardIPv4CidrContains() {
    local network=$1
    local address=$2
    local networkHost=${network%/*}
    local prefix=${network#*/}
    local networkValue addressValue mask

    subscriptionWireGuardValidIPv4Cidr "${network}" || return 1
    subscriptionWireGuardValidIPv4Cidr "${address}" || return 1
    networkValue=$(subscriptionWireGuardIPv4HostValue "${networkHost}") || return 1
    addressValue=$(subscriptionWireGuardIPv4HostValue "${address%%/*}") || return 1
    ((10#${prefix} == 0)) && return 0
    mask=$(( (0xffffffff << (32 - 10#${prefix})) & 0xffffffff ))
    (( (networkValue & mask) == (addressValue & mask) ))
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
    [[ "${value}" =~ ^[A-Za-z0-9+/]{43}=$ ]] && printf '%s' "${value}" | base64 -d >/dev/null 2>&1
}

subscriptionWireGuardValidEndpointValue() {
    local endpoint=$1
    local host port
    [[ -n "${endpoint}" && "${endpoint}" != "null" && "${endpoint}" == *:* && ! "${endpoint}" =~ [[:space:]] ]] || return 1
    host=${endpoint%:*}
    port=${endpoint##*:}
    [[ "${host}" != "${endpoint}" && -n "${host}" && -n "${port}" ]] || return 1
    subscriptionWireGuardValidEndpointHost "${host}" &&
        subscriptionWireGuardValidPort "${port}"
}

subscriptionWireGuardValidateStateForConfig() {
    local state=$1
    local address network listenPort peer peerAddress peerPublicKey peerEndpoint peerHost publicKey
    local -A seenAddresses=()
    local -A seenPublicKeys=()
    jq -e '
      type == "object" and
      (.network | type == "string") and
      (.address | type == "string") and
      (.listen_port | type == "number") and
      (.public_key | type == "string") and
      (.peers | type == "array") and
      all(.peers[]?;
        type == "object" and
        (.id | type == "string" and length > 0) and
        (.name | type == "string") and
        (.address | type == "string") and
        (.public_key | type == "string") and
        (.endpoint | type == "string") and
        (.enabled | type == "boolean"))
    ' <<<"${state}" >/dev/null 2>&1 || return 1
    address=$(jq -r '.address // empty' <<<"${state}") || return 1
    network=$(jq -r '.network // empty' <<<"${state}") || return 1
    listenPort=$(jq -r '.listen_port // empty' <<<"${state}") || return 1
    subscriptionWireGuardValidIPv4Cidr "${network}" &&
        subscriptionWireGuardValidIPv4Cidr "${address}" &&
        subscriptionWireGuardIPv4CidrContains "${network}" "${address}" &&
        subscriptionWireGuardValidPort "${listenPort}" || return 1
    peerHost=$(subscriptionWireGuardAddressHost "${address}")
    seenAddresses["${peerHost}"]=1
    publicKey=$(jq -r '.public_key // empty' <<<"${state}") || return 1
    if [[ -n "${publicKey}" ]]; then
        seenPublicKeys["${publicKey}"]=1
    fi
    while IFS= read -r peer; do
        [[ -n "${peer}" ]] || continue
        peerAddress=$(jq -r '.address // empty' <<<"${peer}") || return 1
        peerPublicKey=$(jq -r '.public_key // empty' <<<"${peer}") || return 1
        peerEndpoint=$(jq -r '.endpoint // empty' <<<"${peer}") || return 1
        subscriptionWireGuardValidIPv4Cidr "${peerAddress}" &&
            subscriptionWireGuardIPv4CidrContains "${network}" "${peerAddress}" &&
            subscriptionWireGuardValidPublicKeyValue "${peerPublicKey}" || return 1
        peerHost=$(subscriptionWireGuardAddressHost "${peerAddress}")
        [[ -z "${seenAddresses[${peerHost}]+x}" && -z "${seenPublicKeys[${peerPublicKey}]+x}" ]] || return 1
        seenAddresses["${peerHost}"]=1
        seenPublicKeys["${peerPublicKey}"]=1
        [[ -z "${peerEndpoint}" || "${peerEndpoint}" == "null" ]] ||
            subscriptionWireGuardValidEndpointValue "${peerEndpoint}" || return 1
    done < <(jq -c '.peers[]?' <<<"${state}")
}

subscriptionWireGuardValidateState() {
    local state=$1
    local role enabled endpointHost publicKey
    jq -e --arg interface "$(subscriptionWireGuardInterface)" '
      type == "object" and
      (.enabled | type == "boolean") and
      (.role | type == "string" and (. == "uninitialized" or . == "main" or . == "controlled")) and
      (.interface | type == "string" and . == $interface) and
      (.network | type == "string") and
      (.listen_port | type == "number") and
      (.control_port | type == "number") and
      (.firewall_owned | type == "boolean") and
      (.address | type == "string") and
      (.endpoint_host | type == "string") and
      (.public_key | type == "string") and
      (.peers | type == "array")
    ' <<<"${state}" >/dev/null 2>&1 || return 1

    role=$(jq -r '.role' <<<"${state}") || return 1
    enabled=$(jq -r '.enabled' <<<"${state}") || return 1
    endpointHost=$(jq -r '.endpoint_host' <<<"${state}") || return 1
    publicKey=$(jq -r '.public_key' <<<"${state}") || return 1
    subscriptionWireGuardValidIPv4Cidr "$(jq -r '.network' <<<"${state}")" &&
        subscriptionWireGuardValidPort "$(jq -r '.listen_port' <<<"${state}")" &&
        subscriptionWireGuardValidPort "$(jq -r '.control_port' <<<"${state}")" || return 1

    case "${role}" in
    uninitialized)
        [[ "${enabled}" == "false" &&
            -z "$(jq -r '.address' <<<"${state}")" &&
            -z "${endpointHost}" &&
            -z "${publicKey}" &&
            "$(jq -r '.peers | length' <<<"${state}")" == "0" &&
            "$(jq -r '.firewall_owned' <<<"${state}")" == "false" ]]
        ;;
    main)
        subscriptionWireGuardValidEndpointHost "${endpointHost}" &&
            subscriptionWireGuardValidPublicKeyValue "${publicKey}" &&
            subscriptionWireGuardValidateStateForConfig "${state}"
        ;;
    controlled)
        [[ -z "${endpointHost}" ]] &&
            subscriptionWireGuardValidPublicKeyValue "${publicKey}" &&
            subscriptionWireGuardValidateStateForConfig "${state}"
        ;;
    esac
}

subscriptionWireGuardPeerIdentityAvailable() {
    local state=$1
    local id=$2
    local address=$3
    local publicKey=$4
    local network localAddress localPublicKey peer peerId peerAddress peerPublicKey
    network=$(jq -r '.network // empty' <<<"${state}") || return 1
    localAddress=$(jq -r '.address // empty' <<<"${state}") || return 1
    localPublicKey=$(jq -r '.public_key // empty' <<<"${state}") || return 1
    subscriptionWireGuardIPv4CidrContains "${network}" "${address}" || return 1
    [[ "$(subscriptionWireGuardAddressHost "${address}")" != "$(subscriptionWireGuardAddressHost "${localAddress}")" ]] || return 1
    [[ -z "${localPublicKey}" || "${publicKey}" != "${localPublicKey}" ]] || return 1
    while IFS= read -r peer; do
        [[ -n "${peer}" ]] || continue
        peerId=$(jq -r '.id // empty' <<<"${peer}") || return 1
        [[ "${peerId}" == "${id}" ]] && continue
        peerAddress=$(jq -r '.address // empty' <<<"${peer}") || return 1
        peerPublicKey=$(jq -r '.public_key // empty' <<<"${peer}") || return 1
        [[ "$(subscriptionWireGuardAddressHost "${address}")" != "$(subscriptionWireGuardAddressHost "${peerAddress}")" &&
            "${publicKey}" != "${peerPublicKey}" ]] || return 1
    done < <(jq -c '.peers[]?' <<<"${state}")
}

subscriptionWireGuardValidNginxLogPath() {
    local path=$1
    [[ -n "${path}" && "${path}" == /* && "${path}" != *$'\n'* && "${path}" != *$'\r'* ]] &&
        padmIsSafeAbsolutePath "${path}"
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
    local stateFile state
    stateFile=$(subscriptionWireGuardStateFile)
    if [[ ! -e "${stateFile}" && ! -L "${stateFile}" ]]; then
        jq -n \
          --arg interface "$(subscriptionWireGuardInterface)" \
          --arg network "10.77.0.0/24" \
          --argjson listenPort "$(subscriptionWireGuardDefaultListenPort)" \
          --argjson controlPort "$(subscriptionWireGuardDefaultControlPort)" \
          '{enabled:false, role:"uninitialized", interface:$interface, network:$network, listen_port:$listenPort, control_port:$controlPort, firewall_owned:false, address:"", endpoint_host:"", public_key:"", peers:[]}'
        return 0
    fi
    if [[ ! -f "${stateFile}" ]] || ! state=$(jq -e -c '.' "${stateFile}" 2>/dev/null); then
        return 1
    fi
    subscriptionWireGuardValidateState "${state}" || return 1
    printf '%s\n' "${state}"
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
    chmod 700 "${stateDir}" 2>/dev/null || return 1
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
    local nginxBackupDir=${2:-}
    local nginxWasRunning=${3:-}
    local previousAddress
    local previousEnabled
    local restoreFailed=false
    if ! previousAddress=$(jq -r '.address // empty' <<<"${previousState}") ||
        ! previousEnabled=$(jq -r '.enabled == true' <<<"${previousState}") ||
        ! subscriptionWireGuardWriteState --argjson previousState "${previousState}" '$previousState' >/dev/null 2>&1; then
        restoreFailed=true
    elif [[ "${previousEnabled}" == "true" && -n "${previousAddress}" ]]; then
        applySubscriptionWireGuardService >/dev/null 2>&1 || restoreFailed=true
    elif [[ -n "${previousAddress}" ]]; then
        if stopSubscriptionWireGuardControlService true >/dev/null 2>&1; then
            writeSubscriptionWireGuardConfig >/dev/null 2>&1 || restoreFailed=true
        else
            restoreFailed=true
        fi
    else
        if stopSubscriptionWireGuardControlService true >/dev/null 2>&1; then
            removeSubscriptionWireGuardNginxConfig >/dev/null 2>&1 || restoreFailed=true
            rm -f "$(subscriptionWireGuardConfigFile)" >/dev/null 2>&1 || restoreFailed=true
        else
            restoreFailed=true
        fi
    fi
    if [[ -n "${nginxBackupDir}" ]]; then
        checkLogBackupRestore "${nginxBackupDir}" >/dev/null 2>&1 || restoreFailed=true
        if [[ "${nginxWasRunning}" == "true" ]]; then
            if nginxRunning && ! runCoreServiceActionAllowFailure handleNginx stop; then
                restoreFailed=true
            fi
            if ! nginxRunning && ! runCoreServiceActionAllowFailure handleNginx start restore; then
                restoreFailed=true
            fi
        elif nginxRunning; then
            runCoreServiceActionAllowFailure handleNginx stop || restoreFailed=true
        fi
        if [[ "${restoreFailed}" == "true" ]]; then
            padmForgetCleanupPath "${nginxBackupDir}"
        else
            padmRemoveCleanupPath "${nginxBackupDir}"
        fi
    fi
    [[ "${restoreFailed}" != "true" ]]
}

subscriptionWireGuardRestoreGroupsState() {
    local previousGroupsState=$1
    subscriptionGroupsStateWrite --argjson previousGroupsState "${previousGroupsState}" '$previousGroupsState' >/dev/null 2>&1 || return 1
}

subscriptionWireGuardReportRestoreFailure() {
    local failureTitle=$1
    local nginxBackupDir=${2:-}
    local restoreMessage
    local groupsFile=
    local stateCheckLine
    local configCheckLine
    local groupsCheckLine
    local -a checkLines=()
    subscriptionSyncSetSingleRestoreResultMessage restoreMessage "${failureTitle}" false "" "旧状态" "" false || true
    subscriptionWireGuardAppendManualCheckLine stateCheckLine "请手动检查 WireGuard 状态文件" "$(subscriptionWireGuardStateFile)"
    subscriptionWireGuardAppendManualCheckLine configCheckLine "请手动检查 WireGuard 配置文件" "$(subscriptionWireGuardConfigFile)"
    checkLines+=("${stateCheckLine}" "${configCheckLine}")
    if declare -F subscriptionGroupsFile >/dev/null 2>&1; then
        groupsFile=$(subscriptionGroupsFile)
    fi
    if [[ -n "${groupsFile}" ]]; then
        subscriptionWireGuardAppendManualCheckLine groupsCheckLine "请手动检查订阅组状态文件" "${groupsFile}"
        checkLines+=("${groupsCheckLine}")
    fi
    [[ -n "${nginxBackupDir}" ]] && checkLines+=("请手动检查 Nginx 备份目录：${nginxBackupDir}")
    errorCard "${restoreMessage}" "${checkLines[@]}"
}

subscriptionWireGuardAppendManualCheckLine() {
    local outputVar=$1
    local label=$2
    local path=$3
    printf -v "${outputVar}" '%s：%s' "${label}" "${path}"
}

subscriptionWireGuardRunRestoreSteps() {
    local previousState=$1
    local previousGroupsState=${2:-}
    local failureTitle=$3
    local nginxBackupDir=${4:-}
    local nginxWasRunning=${5:-}
    local restoreFailed=false

    subscriptionWireGuardRestoreStateAndConfig "${previousState}" "${nginxBackupDir}" "${nginxWasRunning}" >/dev/null 2>&1 || restoreFailed=true
    if [[ -n "${previousGroupsState}" ]]; then
        subscriptionWireGuardRestoreGroupsState "${previousGroupsState}" >/dev/null 2>&1 || restoreFailed=true
    fi
    if [[ "${restoreFailed}" == "true" ]]; then
        subscriptionWireGuardReportRestoreFailure "${failureTitle}" "${nginxBackupDir}"
        return 1
    fi
}

subscriptionWireGuardRestoreStateOrReport() {
    local previousState=$1
    local failureTitle=$2
    local nginxBackupDir=${3:-}
    local nginxWasRunning=${4:-}
    subscriptionWireGuardRunRestoreSteps "${previousState}" "" "${failureTitle}" "${nginxBackupDir}" "${nginxWasRunning}"
}

subscriptionWireGuardRestoreStateAndGroupsOrReport() {
    local previousState=$1
    local previousGroupsState=$2
    local failureTitle=$3
    subscriptionWireGuardRunRestoreSteps "${previousState}" "${previousGroupsState}" "${failureTitle}"
}

subscriptionWireGuardReadPreviousState() {
    local outputVar=$1
    local errorMessage=${2:-}
    local __padmWireGuardPreviousState
    __padmWireGuardPreviousState=$(subscriptionWireGuardReadState) || {
        [[ -n "${errorMessage}" ]] && errorCard "${errorMessage}"
        return 1
    }
    printf -v "${outputVar}" '%s' "${__padmWireGuardPreviousState}"
}

subscriptionWireGuardReadPreviousStateAndGroups() {
    local stateVar=$1
    local groupsVar=$2
    local stateErrorMessage=${3:-}
    local groupsErrorMessage=${4:-}
    local __padmWireGuardPreviousStateValue
    local __padmWireGuardPreviousGroupsStateValue

    __padmWireGuardPreviousStateValue=$(subscriptionWireGuardReadState) || {
        [[ -n "${stateErrorMessage}" ]] && errorCard "${stateErrorMessage}"
        return 1
    }
    __padmWireGuardPreviousGroupsStateValue=$(subscriptionGroupsStateRead -c '.') || {
        [[ -n "${groupsErrorMessage}" ]] && errorCard "${groupsErrorMessage}"
        return 1
    }
    printf -v "${stateVar}" '%s' "${__padmWireGuardPreviousStateValue}"
    printf -v "${groupsVar}" '%s' "${__padmWireGuardPreviousGroupsStateValue}"
}

subscriptionWireGuardRole() {
    subscriptionWireGuardReadState | jq -r '.role'
}

subscriptionManagedGroupSyncCronActive() {
    readUserCrontabContent 2>/dev/null | grep -q '/etc/padm/install.sh SyncSubscriptionGroups'
}

subscriptionControlledTransitionPreflight() {
    subscribePort=
    subscribeDomain=
    subscribeType=
    subscribeConfigState=
    if ! readNginxSubscribe; then
        errorCard "订阅 Nginx 配置损坏，不能切换为被控" "请先修复或移除受管 subscribe.conf"
        return 1
    fi
    if [[ "${subscribeConfigState:-}" == "valid" || -n "${subscribePort:-}" ]]; then
        errorCard "检测到活动公网订阅发布服务，不能切换为被控" "请先在本机模式中停用订阅发布服务"
        return 1
    fi
    if subscriptionManagedGroupSyncCronActive; then
        errorCard "检测到受管订阅同步定时任务，不能切换为被控" "请先在本机模式中关闭自动同步"
        return 1
    fi
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
    privateKeyFile=$(subscriptionWireGuardPrivateKeyFile)
    publicKeyFile=$(subscriptionWireGuardPublicKeyFile)
    [[ -n "${privateKeyFile}" && -n "${publicKeyFile}" ]] || return 1
    privateDir=$(dirname "${privateKeyFile}")
    padmEnsureSafeDirectory "${privateDir}" || return 1
    chmod 700 "${privateDir}" 2>/dev/null || return 1
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
        padmCreateTmpRootPath rollbackDir padm-wireguard-keys.XXXXXX -d || {
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
    chmod 600 "${privateKeyFile}" "${publicKeyFile}" 2>/dev/null || return 1
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
    listenPort=$(jq -r '.listen_port' <<<"${state}")
    address=$(jq -r '.address' <<<"${state}")
    [[ -n "${address}" && -s "${privateKeyFile}" ]] || return 1
    subscriptionWireGuardValidateStateForConfig "${state}" || return 1
    padmCreateTempFileForTarget tmpFile "${configFile}" wireguard || return 1
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
    local targetPath="${nginxConfigPath:-/etc/nginx/conf.d/}padm-control-wg.conf"
    padmIsSafeAbsolutePath "${targetPath}" || return 1
    printf '%s\n' "${targetPath}"
}

removeSubscriptionWireGuardNginxConfig() {
    local targetPath
    targetPath=$(subscriptionWireGuardNginxConfigFile) || return 1
    removeManagedFileIfPresent "${targetPath}"
}

ensureSubscriptionWireGuardNginx() {
    if command -v nginx >/dev/null 2>&1; then
        return 0
    fi
    (installNginxTools) || return 1
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
    local subscribePublicBase
    local controlLog
    state=$(subscriptionWireGuardReadState)
    listenHost=$(subscriptionWireGuardAddressHost "$(jq -r '.address' <<<"${state}")")
    controlPort=$(jq -r '.control_port' <<<"${state}")
    controlLog=$(fail2banPadmControlLogFile)
    subscriptionWireGuardValidIPv4Host "${listenHost}" || return 1
    subscriptionWireGuardValidPort "${controlPort}" || return 1
    subscriptionWireGuardValidNginxLogPath "${controlLog}" || return 1
    subscribePublicBase=$(padmResolveManagedAbsolutePath "$(subscribePublicBaseDir)") || return 1
    subscribePublicBase="${subscribePublicBase%/}"
    targetPath=$(subscriptionWireGuardNginxConfigFile) || return 1
    padmCommitTargetIsFileLike "${targetPath}" || return 1
    padmCreateTempFileForTarget tmpPath "${targetPath}" nginx || return 1
    cat >"${tmpPath}" <<EOF || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
server {
    listen ${listenHost}:${controlPort};
    server_name _;
    root ${nginxStaticPath};

    location /s/control/ {
        access_log ${controlLog};
        client_max_body_size 256k;
        proxy_connect_timeout 5s;
        proxy_send_timeout 180s;
        proxy_read_timeout 195s;
        proxy_pass http://127.0.0.1:$(subscriptionControlPort);
        proxy_set_header Authorization \$http_authorization;
        proxy_set_header Content-Type \$content_type;
    }

    location ~ "^/s/(clashMeta|default|clashMetaProfiles|sing-box|sing-box_profiles)/([A-Fa-f0-9]{32})$" {
        access_log off;
        default_type 'text/plain; charset=utf-8';
        alias ${subscribePublicBase}/\$1/\$2;
    }
}
EOF
    if command -v nginx >/dev/null 2>&1; then
        if [[ -f "${targetPath}" ]]; then
            padmCreateTempFileForTarget backupPath "${targetPath}" backup || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
            backupManagedFileToPath "${targetPath}" "${backupPath}" 644 || {
                padmRemoveCleanupPath "${tmpPath}"
                padmRemoveCleanupPath "${backupPath}"
                return 1
            }
        fi
        commitGeneratedFile "${tmpPath}" "${targetPath}" 644 || { padmRemoveCleanupPath "${tmpPath}"; [[ -n "${backupPath}" ]] && padmRemoveCleanupPath "${backupPath}"; return 1; }
        if ! nginx -t >"$(subscriptionWireGuardNginxTestLog)" 2>&1; then
            if [[ -n "${backupPath}" && -f "${backupPath}" ]]; then
                commitGeneratedFile "${backupPath}" "${targetPath}" 644 || padmForgetCleanupPath "${backupPath}"
            else
                removeManagedFileIfPresent "${targetPath}" || return 1
            fi
            return 1
        fi
        [[ -n "${backupPath}" ]] && padmRemoveCleanupPath "${backupPath}"
        return 0
    else
        commitGeneratedFile "${tmpPath}" "${targetPath}" 644 || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
    fi
}

subscriptionWireGuardInstallControlPlane() {
    local previousState=$1
    local roleLabel=$2
    local nginxTarget
    local nginxBackupDir=
    local nginxWasRunning=false
    local previousServiceActions

    nginxTarget=$(subscriptionWireGuardNginxConfigFile) || {
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard Nginx 控制面配置路径异常" || return 1
        errorCard "WireGuard Nginx 控制面配置路径异常"
        return 1
    }
    checkLogBackupCreate nginxBackupDir "${nginxTarget}" || {
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard Nginx 控制面配置备份失败" || return 1
        errorCard "WireGuard Nginx 控制面配置备份失败"
        return 1
    }
    nginxRunning && nginxWasRunning=true
    previousServiceActions="${SERVICE_ACTIONS:-}"
    refreshSubscriptionWireGuardNginxControl || {
        SERVICE_ACTIONS="${previousServiceActions}"
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard Nginx 控制面配置失败" "${nginxBackupDir}" "${nginxWasRunning}" || return 1
        errorCard "WireGuard Nginx 控制面配置失败"
        return 1
    }
    serviceQueueApply || {
        SERVICE_ACTIONS="${previousServiceActions}"
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard Nginx 控制面重载失败" "${nginxBackupDir}" "${nginxWasRunning}" || return 1
        errorCard "WireGuard Nginx 控制面重载失败"
        return 1
    }
    installSubscriptionControlService || {
        SERVICE_ACTIONS="${previousServiceActions}"
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "${roleLabel}控制服务安装失败" "${nginxBackupDir}" "${nginxWasRunning}" || return 1
        errorCard "${roleLabel}控制服务安装失败"
        return 1
    }
    padmRemoveCleanupPath "${nginxBackupDir}"
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

initSubscriptionWireGuardMainApply() {
    local endpointHost=
    local listenPort
    local controlPort
    local address
    local publicKey
    local previousState
    local firewallOwned=false
    subscriptionWireGuardReadPreviousState previousState "WireGuard 状态读取失败" || return 1
    if [[ "$(jq -r '.role' <<<"${previousState}")" == "controlled" ]]; then
        errorCard "当前机器已初始化为被控" "第一版只支持星型拓扑，被控不能再作为主控"
        return 1
    fi
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
    firewallOwned=$(jq -r '.firewall_owned == true' <<<"${previousState}") || return 1
    allowPort "${listenPort}" udp || {
        errorCard "WireGuard 公网监听端口开放失败"
        return 1
    }
    if [[ "${PADM_LAST_ALLOW_PORT_ADDED:-false}" == "true" ]]; then
        firewallOwned=true
    fi
    subscriptionWireGuardWriteState \
      --arg endpointHost "${endpointHost}" \
      --arg address "${address}" \
      --arg publicKey "${publicKey}" \
      --argjson listenPort "${listenPort}" \
      --argjson controlPort "${controlPort}" \
      --argjson firewallOwned "${firewallOwned}" \
      '.enabled = true | .role = "main" | .address = $address | .endpoint_host = $endpointHost | .public_key = $publicKey | .listen_port = $listenPort | .control_port = $controlPort | .firewall_owned = $firewallOwned' || {
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
    subscriptionWireGuardWaitForAddress "${address}" || {
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard 主控地址就绪失败" || return 1
        errorCard "WireGuard 主控地址就绪失败"
        return 1
    }
    subscriptionWireGuardInstallControlPlane "${previousState}" "主控" || return 1
    successCard "WireGuard 主控已初始化" "接口：$(subscriptionWireGuardInterface)" "内网地址：${address}" "监听端口：${listenPort}/udp" "控制服务已通过 WireGuard 内网启用"
}

initSubscriptionWireGuardMain() {
    padmRunPortAllowTransaction initSubscriptionWireGuardMainApply "$@"
}

initSubscriptionWireGuardControlled() {
    local address=
    local controlPort
    local publicKey
    local previousState
    local role
    subscriptionWireGuardReadPreviousState previousState "WireGuard 状态读取失败" || return 1
    role=$(jq -r '.role' <<<"${previousState}") || return 1
    if [[ "${role}" == "main" ]]; then
        errorCard "当前机器已初始化为主控" "第一版只支持星型拓扑，主控不能再作为被控"
        return 1
    fi
    if [[ "${role}" == "uninitialized" ]]; then
        subscriptionControlledTransitionPreflight || return 1
    fi
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
    [[ -f "$(subscriptionWireGuardStateFile)" && -f "$(subscriptionWireGuardConfigFile)" ]] || {
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard 被控配置未落地" || return 1
        errorCard "WireGuard 被控配置未落地"
        return 1
    }
    subscriptionWireGuardInstallControlPlane "${previousState}" "被控" || return 1
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
    subscriptionWireGuardReadPreviousState previousState "当前 WireGuard 状态读取失败" || return 1
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
    [[ "${alias,,}" != "main" ]] || {
        errorCard "main 是保留源 ID，不能作为被控服务器别名"
        return 1
    }
    [[ "$(jq -r '.kind' <<<"${credentialJson}")" == "controlled" ]] || return 1
    subscriptionWireGuardValidateControlledCredentialJson "${credentialJson}" || return 1
    address=$(jq -r '.address' <<<"${credentialJson}")
    host=$(subscriptionWireGuardAddressHost "${address}")
    publicKey=$(jq -r '.public_key' <<<"${credentialJson}")
    controlPort=$(jq -r '.control_port' <<<"${credentialJson}")
    token=$(jq -r '.token' <<<"${credentialJson}")
    subscriptionWireGuardReadPreviousStateAndGroups previousState previousGroupsState "" "订阅组状态读取失败" || return 1
    subscriptionWireGuardPeerIdentityAvailable "${previousState}" "${alias}" "${address}" "${publicKey}" || {
        errorCard "WireGuard 被控地址或公钥与现有 Peer 冲突"
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
    local previousState
    [[ -n "${id}" ]] || return 1
    [[ "$(jq -r '.kind' <<<"${credentialJson}")" == "controlled" ]] || return 1
    subscriptionWireGuardValidateControlledCredentialJson "${credentialJson}" || return 1
    address=$(jq -r '.address' <<<"${credentialJson}")
    publicKey=$(jq -r '.public_key' <<<"${credentialJson}")
    previousState=$(subscriptionWireGuardReadState) || return 1
    subscriptionWireGuardPeerIdentityAvailable "${previousState}" "${id}" "${address}" "${publicKey}" || return 1
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
    subscriptionWireGuardReadPreviousStateAndGroups previousState previousGroupsState "" "订阅组状态读取失败" || return 1
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

restartSubscriptionWireGuardControlApply() {
    local previousState
    local role
    local listenPort
    local firewallOwned=false
    local nginxTarget
    local nginxBackupDir=
    local nginxWasRunning=false
    local previousServiceActions

    subscriptionWireGuardReadPreviousState previousState "WireGuard 控制面状态读取失败" || return 1
    role=$(jq -r '.role' <<<"${previousState}") || return 1
    firewallOwned=$(jq -r '.firewall_owned == true' <<<"${previousState}") || return 1
    if [[ "${role}" == "main" ]]; then
        listenPort=$(jq -r '.listen_port' <<<"${previousState}")
        subscriptionWireGuardValidPort "${listenPort}" || return 1
        allowPort "${listenPort}" udp || {
            errorCard "WireGuard 公网监听端口开放失败"
            return 1
        }
        if [[ "${PADM_LAST_ALLOW_PORT_ADDED:-false}" == "true" ]]; then
            firewallOwned=true
        fi
    fi
    nginxTarget=$(subscriptionWireGuardNginxConfigFile) || {
        errorCard "WireGuard Nginx 控制面配置路径异常"
        return 1
    }
    checkLogBackupCreate nginxBackupDir "${nginxTarget}" || {
        errorCard "WireGuard Nginx 控制面配置备份失败"
        return 1
    }
    nginxRunning && nginxWasRunning=true
    previousServiceActions="${SERVICE_ACTIONS:-}"

    subscriptionWireGuardWriteState --argjson firewallOwned "${firewallOwned}" '.enabled = true | .firewall_owned = $firewallOwned' || {
        padmRemoveCleanupPath "${nginxBackupDir}"
        errorCard "WireGuard 控制面启用状态写入失败"
        return 1
    }

    applySubscriptionWireGuardService || {
        SERVICE_ACTIONS="${previousServiceActions}"
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard 服务重启失败" "${nginxBackupDir}" "${nginxWasRunning}" || return 1
        errorCard "WireGuard 服务重启失败"
        return 1
    }
    refreshSubscriptionWireGuardNginxControl || {
        SERVICE_ACTIONS="${previousServiceActions}"
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard Nginx 控制面配置失败" "${nginxBackupDir}" "${nginxWasRunning}" || return 1
        errorCard "WireGuard Nginx 控制面配置失败"
        return 1
    }
    serviceQueueApply || {
        SERVICE_ACTIONS="${previousServiceActions}"
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard Nginx 控制面重载失败" "${nginxBackupDir}" "${nginxWasRunning}" || return 1
        errorCard "WireGuard Nginx 控制面重载失败"
        return 1
    }
    installSubscriptionControlService || {
        SERVICE_ACTIONS="${previousServiceActions}"
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "订阅控制服务安装失败" "${nginxBackupDir}" "${nginxWasRunning}" || return 1
        errorCard "订阅控制服务安装失败"
        return 1
    }

    padmRemoveCleanupPath "${nginxBackupDir}"
    successCard "WireGuard 控制面已修复/重启"
}

restartSubscriptionWireGuardControl() {
    padmRunPortAllowTransaction restartSubscriptionWireGuardControlApply "$@"
}

disableSubscriptionWireGuardControl() {
    local previousState
    local role
    local listenPort
    local firewallOwned=false
    local nginxTarget
    local nginxBackupDir=
    local nginxWasRunning=false
    local previousServiceActions
    subscriptionWireGuardReadPreviousState previousState "WireGuard 控制面状态读取失败" || return 1
    role=$(jq -r '.role' <<<"${previousState}") || return 1
    firewallOwned=$(jq -r '.firewall_owned == true' <<<"${previousState}") || return 1
    if [[ "${role}" == "main" ]]; then
        listenPort=$(jq -r '.listen_port' <<<"${previousState}")
        subscriptionWireGuardValidPort "${listenPort}" || return 1
    fi
    nginxTarget=$(subscriptionWireGuardNginxConfigFile) || {
        errorCard "WireGuard Nginx 控制面配置路径异常"
        return 1
    }
    if [[ -e "${nginxTarget}" || -L "${nginxTarget}" ]]; then
        checkLogBackupCreate nginxBackupDir "${nginxTarget}" || {
            errorCard "WireGuard Nginx 控制面配置备份失败"
            return 1
        }
        nginxRunning && nginxWasRunning=true
    fi
    previousServiceActions="${SERVICE_ACTIONS:-}"
    if ! stopSubscriptionWireGuardControlService; then
        [[ -n "${nginxBackupDir}" ]] && padmRemoveCleanupPath "${nginxBackupDir}"
        errorCard "WireGuard 控制面停用失败"
        return 1
    fi
    subscriptionWireGuardWriteState '.enabled = false | .firewall_owned = false' || {
        SERVICE_ACTIONS="${previousServiceActions}"
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard 控制面关闭状态写入失败" "${nginxBackupDir}" "${nginxWasRunning}" || return 1
        errorCard "WireGuard 控制面状态写入失败"
        return 1
    }
    if [[ -n "${nginxBackupDir}" ]]; then
        removeSubscriptionWireGuardNginxConfig || {
            SERVICE_ACTIONS="${previousServiceActions}"
            subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard Nginx 控制面配置移除失败" "${nginxBackupDir}" "${nginxWasRunning}" || return 1
            errorCard "WireGuard Nginx 控制面配置移除失败"
            return 1
        }
        if [[ "${nginxWasRunning}" == "true" ]]; then
            serviceQueueRestart nginx
            serviceQueueApply || {
                SERVICE_ACTIONS="${previousServiceActions}"
                subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard Nginx 控制面重载失败" "${nginxBackupDir}" "${nginxWasRunning}" || return 1
                errorCard "WireGuard Nginx 控制面重载失败"
                return 1
            }
        fi
    fi
    if [[ "${role}" == "main" && "${firewallOwned}" == "true" ]] &&
        ! denyPort "${listenPort}" udp; then
        SERVICE_ACTIONS="${previousServiceActions}"
        subscriptionWireGuardRestoreStateOrReport "${previousState}" "WireGuard 公网监听端口回收失败" "${nginxBackupDir}" "${nginxWasRunning}" || return 1
        errorCard "WireGuard 公网监听端口回收失败"
        return 1
    fi
    [[ -n "${nginxBackupDir}" ]] && padmRemoveCleanupPath "${nginxBackupDir}"
    successCard "WireGuard 控制面已关闭"
}
