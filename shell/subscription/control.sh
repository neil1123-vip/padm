#!/usr/bin/env bash

subscriptionRemoteControlSources() {
    subscriptionActiveGroupRead '
      [.sources[]? | select(.role != "main" and .enabled == true)]'
}

subscriptionRemoteDesiredUsersBySource() {
    local sources=$1
    local state=${2:-}
    local enabledUsers
    if [[ -n "${state}" ]]; then
        enabledUsers=$(subscriptionEnabledUsersJsonFromState "${state}") || return 1
    else
        enabledUsers=$(subscriptionActiveEnabledUsersJson) || return 1
    fi
    jq -c -e -s '
      select(length == 2) |
      .[0] as $sources |
      .[1] as $users |
      select(($sources | type == "array") and
        ($users | type == "array" and all(.[]?; (.uuid // "") | test("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")))) |
      reduce ($sources[]?.id) as $sourceId ({};
        .[$sourceId] = [
          $users[]?
          | select((.allowed_sources | index($sourceId)) or (.allowed_sources | index("*")))
          | {id, uuid, account}
        ])
    ' < <(printf '%s\n%s\n' "${sources}" "${enabledUsers}") || return 1
}

subscriptionRemoteSourceSelfReference() {
    local source=$1
    local sourceHost
    local selfHost=${2-}
    sourceHost=$(jq -r '(.host // "") | ascii_downcase' <<<"${source}")
    if [[ $# -lt 2 ]]; then
        selfHost=$(subscriptionWireGuardReadState | jq -r '.address // empty') || return 1
    fi
    selfHost=$(subscriptionWireGuardAddressHost "${selfHost}")
    selfHost=${selfHost,,}
    [[ -n "${selfHost}" && "${sourceHost}" == "${selfHost}" ]]
}

subscriptionRemoteControlUrl() {
    local source=$1
    local endpoint=$2
    subscriptionWireGuardControlUrl "${source}" "${endpoint}"
}

subscriptionRemoteWireGuardPeerStateFromSource() {
    local source=$1
    local wireGuardState
    local sourceId
    local publicKey
    local interface
    local endpoint=
    local handshake=0
    local -a peerFields=()
    wireGuardState=$(subscriptionWireGuardReadState) || return 1
    mapfile -d '' -t peerFields < <(
        jq -j -s '
          .[0] as $source |
          .[1] as $state |
          [
            ($source.id // "" | tostring),
            (first(($state.peers[]? | select(.id == $source.id) | .public_key) // "") | tostring)
          ] | map(. , "\u0000") | .[]
        ' < <(printf '%s\n%s\n' "${source}" "${wireGuardState}")
    )
    [[ "${#peerFields[@]}" -eq 2 ]] || return 1
    sourceId=${peerFields[0]}
    publicKey=${peerFields[1]}
    [[ -n "${sourceId}" && -n "${publicKey}" ]] || return 1
    command -v wg >/dev/null 2>&1 || return 1
    interface=$(subscriptionWireGuardInterface 2>/dev/null) || return 1
    [[ -n "${interface}" ]] || return 1
    endpoint=$(wg show "${interface}" endpoints 2>/dev/null | awk -v publicKey="${publicKey}" '$1 == publicKey { print $2; exit }')
    handshake=$(wg show "${interface}" latest-handshakes 2>/dev/null | awk -v publicKey="${publicKey}" '$1 == publicKey { print $2; exit }')
    [[ "${handshake}" =~ ^[0-9]+$ ]] || handshake=0
    printf '%s\t%s\t%s\n' "${publicKey}" "${endpoint}" "${handshake}"
}

subscriptionRemoteWireGuardWaitForPeerEndpointFromSource() {
    local source=$1
    local attempts=${2:-${PADM_REMOTE_WG_ENDPOINT_RETRIES:-120}}
    local delay=${3:-${PADM_REMOTE_WG_ENDPOINT_DELAY:-0.25}}
    local baselineEndpoint=${4:-}
    local baselineHandshake=${5:-0}
    local deadline=${6:-}
    local peerState
    local publicKey=
    local endpoint=
    local handshake=0
    local tryIndex
    if [[ -n "${deadline}" ]] && ((SECONDS >= deadline)); then
        return 1
    fi
    peerState=$(subscriptionRemoteWireGuardPeerStateFromSource "${source}" 2>/dev/null || true)
    [[ -n "${peerState}" ]] || return 0
    [[ "${baselineHandshake}" =~ ^[0-9]+$ ]] || baselineHandshake=0
    IFS=$'\t' read -r publicKey endpoint handshake <<<"${peerState}"
    if [[ -n "${endpoint}" && "${endpoint}" != "(none)" ]]; then
        if [[ -z "${baselineEndpoint}" || "${baselineEndpoint}" == "(none)" || "${endpoint}" != "${baselineEndpoint}" ]]; then
            return 0
        fi
        if [[ "${handshake}" =~ ^[0-9]+$ ]] && ((handshake > baselineHandshake)); then
            return 0
        fi
    fi
    for ((tryIndex = 0; tryIndex < attempts; tryIndex++)); do
        if [[ -n "${deadline}" ]] && ((SECONDS >= deadline)); then
            return 1
        fi
        peerState=$(subscriptionRemoteWireGuardPeerStateFromSource "${source}" 2>/dev/null || true)
        if [[ -n "${peerState}" ]]; then
            IFS=$'\t' read -r publicKey endpoint handshake <<<"${peerState}"
            if [[ -n "${endpoint}" && "${endpoint}" != "(none)" ]]; then
                if [[ -z "${baselineEndpoint}" || "${baselineEndpoint}" == "(none)" || "${endpoint}" != "${baselineEndpoint}" ]]; then
                    return 0
                fi
                if [[ "${handshake}" =~ ^[0-9]+$ ]] && ((handshake > baselineHandshake)); then
                    return 0
                fi
            fi
        fi
        if [[ -n "${deadline}" ]]; then
            ((deadline > SECONDS)) || return 1
        fi
        sleep "${delay}"
    done
    return 1
}

subscriptionRemoteControlCurl() {
    local token=$1
    shift
    local headerFile
    local curlStatus
    [[ -n "${token}" ]] || return 1
    padmCreateTmpRootPath headerFile padm-control-auth.XXXXXX || return 1
    chmod 600 "${headerFile}" || { padmRemoveCleanupPath "${headerFile}"; return 1; }
    printf 'Authorization: Bearer %s\n' "${token}" >"${headerFile}" || { padmRemoveCleanupPath "${headerFile}"; return 1; }
    curl -H "@${headerFile}" "$@"
    curlStatus=$?
    padmRemoveCleanupPath "${headerFile}"
    return "${curlStatus}"
}

subscriptionRemoteControlRequest() {
    local source=$1
    local endpoint=$2
    local payload=$3
    local peerState=
    local peerPublicKey=
    local baselineEndpoint=
    local baselineHandshake=0
    local token
    local url
    local maxTime
    local connectTimeout=5
    local deadline
    local remainingTime
    local -a curlArgs=()
    local response
    local statusCode
    local body
    local requestStatus=1
    local retryDelay=1
    token=$(jq -r '.control_token // empty' <<<"${source}") || return 1
    [[ -n "${token}" ]] || return 2
    url=$(subscriptionRemoteControlUrl "${source}" "${endpoint}") || return 1
    if [[ "${endpoint}" == "sync" ]]; then
        maxTime=40
    elif [[ "${endpoint}" == "refresh" ]]; then
        maxTime=45
    else
        maxTime=15
    fi
    if [[ "${SUBSCRIPTION_SYNC_ROLLBACK:-false}" == "true" ]]; then
        connectTimeout=2
        maxTime=15
    fi
    deadline=$((SECONDS + maxTime))
    curlArgs=(
        -sS
        --connect-timeout "${connectTimeout}"
        --max-time "${maxTime}"
        --max-filesize 1048576
        -H "Content-Type: application/json"
        -X POST
        --data-binary @-
        -w '\n%{http_code}'
        "${url}"
    )
    peerState=$(subscriptionRemoteWireGuardPeerStateFromSource "${source}" 2>/dev/null || true)
    if [[ -n "${peerState}" ]]; then
        IFS=$'\t' read -r peerPublicKey baselineEndpoint baselineHandshake <<<"${peerState}"
    fi
    if response=$(subscriptionRemoteControlCurl "${token}" "${curlArgs[@]}" <<<"${payload}" 2>/dev/null); then
        :
    else
        requestStatus=$?
        [[ "${SUBSCRIPTION_SYNC_ROLLBACK:-false}" != "true" ]] || return "${requestStatus}"
        subscriptionRemoteWireGuardWaitForPeerEndpointFromSource "${source}" "" "" "${baselineEndpoint}" "${baselineHandshake}" "${deadline}" >/dev/null 2>&1 || true
        remainingTime=$((deadline - SECONDS))
        ((remainingTime > 0)) || return "${requestStatus}"
        curlArgs[4]="${remainingTime}"
        ((remainingTime > retryDelay)) && sleep "${retryDelay}"
        response=$(subscriptionRemoteControlCurl "${token}" "${curlArgs[@]}" <<<"${payload}" 2>/dev/null) || {
            requestStatus=$?
            return "${requestStatus}"
        }
    fi
    statusCode=${response##*$'\n'}
    body=${response%$'\n'*}
    if [[ "${SUBSCRIPTION_SYNC_ROLLBACK:-false}" != "true" && ( "${statusCode}" == "429" || "${statusCode}" == "503" ) ]]; then
        remainingTime=$((deadline - SECONDS))
        if ((remainingTime > retryDelay)); then
            sleep "${retryDelay}"
            remainingTime=$((deadline - SECONDS))
            ((remainingTime > 0)) || return 0
            curlArgs[4]="${remainingTime}"
            response=$(subscriptionRemoteControlCurl "${token}" "${curlArgs[@]}" <<<"${payload}" 2>/dev/null) || {
                requestStatus=$?
                return "${requestStatus}"
            }
            statusCode=${response##*$'\n'}
            body=${response%$'\n'*}
        fi
    fi
    if ! body=$(jq -c . <<<"${body}" 2>/dev/null); then
        jq -n --arg statusCode "${statusCode}" '{ok:false, error:"invalid_response", error_detail:{type:"invalid_response", message:"远端响应不是合法 JSON"}, http_status: ($statusCode | tonumber? // 0)}'
        return 0
    fi
    if [[ ! "${statusCode}" =~ ^2 ]]; then
        body=$(jq -c --arg statusCode "${statusCode}" '
          if .ok == true then
            .ok = false | .error = (.error // "http_error")
          else
            .
          end | . + {http_status: ($statusCode | tonumber? // 0)}
        ' <<<"${body}") || return 1
    fi
    printf '%s\n' "${body}"
}

subscriptionControlRefreshAuthorized() {
    local token=$1
    [[ -n "${token}" ]] || return 1
    [[ "$(subscriptionCurrentRoleNormalized 2>/dev/null || true)" == "main" ]] || return 1
    subscriptionActiveGroupRead -r --arg token "${token}" \
        'any(.sources[]?; .role != "main" and .enabled == true and (.control_token // "") == $token)'
}

subscriptionNotifyControllerRefresh() {
    declare -F subscriptionCurrentRoleNormalized >/dev/null 2>&1 || return 0
    [[ "$(subscriptionCurrentRoleNormalized 2>/dev/null || true)" == "controlled" ]] || return 0
    if ! declare -F subscriptionWireGuardReadState >/dev/null 2>&1 ||
        ! declare -F subscriptionControlToken >/dev/null 2>&1 ||
        ! declare -F subscriptionRemoteControlRequest >/dev/null 2>&1; then
        declare -F realityTargetStatusBlock >/dev/null 2>&1 &&
            realityTargetStatusBlock yellow "订阅同步" "被控端刷新依赖未完整加载，已跳过主控通知"
        return 0
    fi
    local controlledState mainAddress mainHost mainToken mainSource refreshResponse
    controlledState=$(subscriptionWireGuardReadState) || return 1
    mainAddress=$(jq -r 'first(.peers[]? | select(.id == "main" and .enabled == true) | .address) // empty' <<<"${controlledState}") || return 1
    mainHost=${mainAddress%%/*}
    mainToken=$(subscriptionControlToken) || return 1
    [[ -n "${mainHost}" && -n "${mainToken}" ]] || return 1
    mainSource=$(jq -cn --arg host "${mainHost}" --arg token "${mainToken}" \
        '{id:"main",transport:"wireguard",host:$host,port:39778,control_token:$token}') || return 1
    refreshResponse=$(subscriptionRemoteControlRequest "${mainSource}" refresh '{}') || return 1
    if jq -e '.ok == true and (.refreshed == true or .skipped == "automatic_sync_disabled")' <<<"${refreshResponse}" >/dev/null 2>&1; then
        if jq -e '.skipped == "automatic_sync_disabled"' <<<"${refreshResponse}" >/dev/null 2>&1; then
            declare -F realityTargetStatusBlock >/dev/null 2>&1 &&
                realityTargetStatusBlock yellow "订阅同步" "已通知主控，但主控自动同步已关闭" "请在主控执行立即完整同步"
        else
            declare -F realityTargetStatusBlock >/dev/null 2>&1 &&
                realityTargetStatusBlock green "订阅同步" "已通知主控刷新订阅"
        fi
        return 0
    fi
    declare -F realityTargetStatusBlock >/dev/null 2>&1 &&
        realityTargetStatusBlock yellow "订阅同步" "主控订阅刷新失败" "请在主控执行立即完整同步并检查被控来源状态"
    return 1
}

subscriptionRemoteControlPayload() {
    local source=$1
    local dryRun=$2
    local desiredUsersBySource=${3-}
    local sourceId=${4-}
    [[ -n "${sourceId}" ]] || sourceId=$(jq -r '.id' <<<"${source}")
    [[ -n "${desiredUsersBySource}" ]] || return 1
    jq -c --arg sourceId "${sourceId}" --argjson dryRun "${dryRun}" \
        '{dry_run:$dryRun, desired_users:[.[$sourceId][]? | {id, uuid}]}' <<<"${desiredUsersBySource}"
}

subscriptionRemoteResponseErrorMessage() {
    local response=$1
    local errorMessage
    errorMessage=$(jq -r '
      (.http_status // null) as $httpStatus |
      (if ((.error_detail.message // "") | length) > 0 then .error_detail.message else (.error // "unknown_error") end) as $message |
      if $httpStatus == null or (($httpStatus | tostring) | length) == 0 or (($httpStatus | tostring) == "null") then
        $message
      else
        ($message | tostring) + " (HTTP " + ($httpStatus | tostring) + ")"
      end
    ' <<<"${response}" 2>/dev/null || echo unknown_error)
    printf '%s\n' "${errorMessage}"
}

subscriptionRemoteResponseErrorType() {
    jq -r --arg statusCode "${2:-}" '
      (($statusCode | tonumber?) // (.http_status? | tonumber?) // 0) as $status |
      if $status >= 400 and $status < 500 then "http_4xx"
      elif $status >= 500 and $status < 600 then "http_5xx"
      else (.error_detail.type? | select(type == "string" and length > 0)) // "remote_error"
      end
    ' <<<"$1"
}

subscriptionRemoteTransportErrorDetail() {
    local source=$1
    local requestStatus=$2
    local errorType=unreachable
    local message="不可达或请求失败"
    local peerState handshake now
    case "${requestStatus}" in
    7) errorType=connection_refused; message="连接被拒绝（目标端口未监听或被防火墙拒绝）" ;;
    28) errorType=timeout; message="连接超时（服务器无响应）" ;;
    esac
    if [[ "${requestStatus}" == "7" || "${requestStatus}" == "28" ]]; then
        peerState=$(subscriptionRemoteWireGuardPeerStateFromSource "${source}" 2>/dev/null || true)
        handshake=${peerState##*$'\t'}
        # A curl failure alone does not establish a WireGuard handshake failure.
        if [[ -n "${peerState}" && "${handshake}" =~ ^[0-9]+$ ]]; then
            now=$(date +%s) || return 1
            if ((handshake == 0 || now - handshake > 180)); then
                errorType=wireguard_handshake_timeout
                message="WireGuard 握手未建立或已过期，请检查隧道连通性"
            fi
        fi
    fi
    jq -cn --arg type "${errorType}" --arg message "${message}" '{type:$type, message:$message}'
}

subscriptionRemoteControlHealth() {
    local source=$1
    local token
    local sourceMeta
    local url
    local peerState=
    local peerPublicKey=
    local baselineEndpoint=
    local baselineHandshake=0
    local -a curlArgs=()
    local response
    local statusCode
    local body
    local validatedBody
    local errorMessage
    local errorType errorDetail requestStatus
    local connectTimeout=5
    local deadline
    local remainingTime
    local -a sourceFields=()
    mapfile -d '' -t sourceFields < <(
        jq -j '
          [
            ({id: ((.id // "null") | tostring), name: ((.name // "null") | tostring)} | tojson),
            (.control_token // "")
          ] | map(. , "\u0000") | .[]
        ' <<<"${source}"
    )
    [[ "${#sourceFields[@]}" -eq 2 ]] || return 1
    sourceMeta=${sourceFields[0]}
    token=${sourceFields[1]}
    if [[ -z "${token}" ]]; then
        jq -n --argjson sourceMeta "${sourceMeta}" '{id:$sourceMeta.id, name:$sourceMeta.name, ok:false, status:"missing_token", error_detail:{type:"missing_token", message:"未配置控制 token"}}'
        return 0
    fi
    peerState=$(subscriptionRemoteWireGuardPeerStateFromSource "${source}" 2>/dev/null || true)
    if [[ -n "${peerState}" ]]; then
        IFS=$'\t' read -r peerPublicKey baselineEndpoint baselineHandshake <<<"${peerState}"
    fi
    url=$(subscriptionRemoteControlUrl "${source}" health) || return 1
    [[ "${SUBSCRIPTION_SYNC_ROLLBACK:-false}" != "true" ]] || connectTimeout=2
    deadline=$((SECONDS + 15))
    curlArgs=(
        -sS
        --connect-timeout "${connectTimeout}"
        --max-time 15
        --max-filesize 1048576
        -w '\n%{http_code}'
        "${url}"
    )
    response=$(subscriptionRemoteControlCurl "${token}" "${curlArgs[@]}" 2>/dev/null) || {
        requestStatus=$?
        remainingTime=0
        if [[ "${SUBSCRIPTION_SYNC_ROLLBACK:-false}" != "true" ]]; then
            subscriptionRemoteWireGuardWaitForPeerEndpointFromSource "${source}" "" "" "${baselineEndpoint}" "${baselineHandshake}" "${deadline}" >/dev/null 2>&1 || true
            remainingTime=$((deadline - SECONDS))
        fi
        if ((remainingTime <= 0)); then
            errorDetail=$(subscriptionRemoteTransportErrorDetail "${source}" "${requestStatus}") || return 1
            jq -n --argjson sourceMeta "${sourceMeta}" --argjson detail "${errorDetail}" '{id:$sourceMeta.id, name:$sourceMeta.name, ok:false, status:"unreachable", error_detail:$detail}'
            return 0
        fi
        curlArgs[4]="${remainingTime}"
        response=$(subscriptionRemoteControlCurl "${token}" "${curlArgs[@]}" 2>/dev/null) || {
            requestStatus=$?
            errorDetail=$(subscriptionRemoteTransportErrorDetail "${source}" "${requestStatus}") || return 1
            jq -n --argjson sourceMeta "${sourceMeta}" --argjson detail "${errorDetail}" '{id:$sourceMeta.id, name:$sourceMeta.name, ok:false, status:"unreachable", error_detail:$detail}'
            return 0
        }
    }
    statusCode=${response##*$'\n'}
    body=${response%$'\n'*}
    if [[ "${statusCode}" == "200" ]] &&
        validatedBody=$(jq -ce --argjson sourceMeta "${sourceMeta}" '
          select(.ok == true and (.capabilities | type == "array" and index("health") != null and index("sync") != null and index("traffic") != null)) |
          . + {id:$sourceMeta.id, name:$sourceMeta.name, ok:true}
        ' <<<"${body}" 2>/dev/null); then
        printf '%s\n' "${validatedBody}"
        return 0
    fi
    if [[ "${statusCode}" == "401" ]]; then
        jq -n --argjson sourceMeta "${sourceMeta}" --arg statusCode "${statusCode}" '{id:$sourceMeta.id, name:$sourceMeta.name, ok:false, status:"unauthorized", status_code:$statusCode, error_detail:{type:"unauthorized", message:"控制 token 验证失败"}}'
        return 0
    fi
    if jq -c . <<<"${body}" >/dev/null 2>&1; then
        errorMessage=$(subscriptionRemoteResponseErrorMessage "${body}")
        errorType=$(subscriptionRemoteResponseErrorType "${body}" "${statusCode}") || return 1
        [[ -n "${statusCode}" && "${statusCode}" != "null" ]] && errorMessage="${errorMessage} (HTTP ${statusCode})"
        jq -n --argjson sourceMeta "${sourceMeta}" --arg statusCode "${statusCode}" --arg errorMessage "${errorMessage}" --arg errorType "${errorType}" '{id:$sourceMeta.id, name:$sourceMeta.name, ok:false, status:"remote_error", status_code:$statusCode, error:$errorMessage, error_detail:{type:$errorType, message:$errorMessage}}'
        return 0
    fi
    errorType=$(subscriptionRemoteResponseErrorType '{"error_detail":{"type":"invalid_response"}}' "${statusCode}") || return 1
    jq -n --argjson sourceMeta "${sourceMeta}" --arg statusCode "${statusCode}" --arg errorType "${errorType}" '{id:$sourceMeta.id, name:$sourceMeta.name, ok:false, status:"remote_error", status_code:$statusCode, error_detail:{type:$errorType, message:("远端响应不是合法 JSON (HTTP " + $statusCode + ")")}}'
}

subscriptionRemoteHealthInternalErrorResult() {
    local source=$1
    jq -n \
        --arg id "$(jq -r '.id // "unknown"' <<<"${source}" 2>/dev/null || echo unknown)" \
        --arg name "$(jq -r '.name // .id // "unknown"' <<<"${source}" 2>/dev/null || echo unknown)" \
        '{id:$id, name:$name, ok:false, status:"internal_error", error_detail:{type:"internal_error", message:"健康检查结果生成失败"}}'
}

subscriptionRemoteTrafficForSource() {
    local source=$1
    local sourceId
    local response
    local responseStatus
    local requestStatus
    local errorType errorDetail
    sourceId=$(jq -r '.id // empty' <<<"${source}") || return 1
    [[ -n "${sourceId}" ]] || return 1
    if subscriptionRemoteSourceSelfReference "$@"; then
        jq -n --arg sourceId "${sourceId}" \
            '{source_id:$sourceId, status:"self_reference", error_detail:{type:"self_reference", message:"服务器源指向当前订阅服务，已跳过以避免递归采集"}}'
    elif response=$(subscriptionRemoteControlRequest "${source}" traffic '{}'); then
        if ! responseStatus=$(jq -ce "${SUBSCRIPTION_TRAFFIC_ITEMS_VALIDATION_JQ}
            if (type == \"object\" and keys == [\"items\", \"ok\"] and .ok == true and (.items | type == \"array\") and (.items | validItems)) then \"success\"
            elif (type == \"object\" and .ok == true) then \"invalid\"
            else \"remote\"
            end
        " <<<"${response}" 2>/dev/null); then
            responseStatus=remote
        fi
        responseStatus=${responseStatus//\"/}
        if [[ "${responseStatus}" == "success" ]]; then
            jq -n --arg sourceId "${sourceId}" --argjson response "${response}" \
                '{source_id:$sourceId, status:"success", response:$response}'
        elif [[ "${responseStatus}" == "invalid" ]]; then
            jq -n --arg sourceId "${sourceId}" --argjson response "${response}" \
                '{source_id:$sourceId, status:"remote_error", error_detail:{type:"invalid_response", message:"远端流量响应格式无效"}, response:$response}'
        else
            errorType=$(subscriptionRemoteResponseErrorType "${response}") || return 1
            jq -n --arg sourceId "${sourceId}" --arg message "$(subscriptionRemoteResponseErrorMessage "${response}")" --argjson response "${response}" --arg errorType "${errorType}" \
                '{source_id:$sourceId, status:"remote_error", error_detail:{type:$errorType, message:$message}, response:$response}'
        fi
    else
        requestStatus=$?
        if ((requestStatus == 2)); then
            jq -n --arg sourceId "${sourceId}" \
                '{source_id:$sourceId, status:"missing_token", error_detail:{type:"missing_token", message:"未配置控制 token"}}'
        else
            errorDetail=$(subscriptionRemoteTransportErrorDetail "${source}" "${requestStatus}") || return 1
            jq -n --arg sourceId "${sourceId}" --argjson detail "${errorDetail}" \
                '{source_id:$sourceId, status:"unreachable", error_detail:$detail}'
        fi
    fi
}

subscriptionRemoteTrafficInternalErrorResult() {
    local source=$1
    jq -n \
        --arg sourceId "$(jq -r '.id // "unknown"' <<<"${source}" 2>/dev/null || echo unknown)" \
        '{source_id:$sourceId, status:"internal_error", error_detail:{type:"internal_error", message:"远端流量结果生成失败"}}'
}

subscriptionRemoteTrafficAll() {
    local sources=${1:-}
    local selfAddress
    local -a workerArgs=()
    if [[ -z "${sources}" ]]; then
        sources=$(subscriptionRemoteControlSources) || return 1
    fi
    if [[ -n "${sources}" && "${sources}" != '[]' ]] &&
        selfAddress=$(subscriptionWireGuardReadState | jq -r '.address // empty'); then
        workerArgs=("${selfAddress}")
    fi
    subscriptionRemoteCollectParallelResults \
        "${sources}" \
        padm-remote-traffic.XXXXXX \
        subscriptionRemoteTrafficForSource \
        subscriptionRemoteTrafficInternalErrorResult \
        "${workerArgs[@]}"
}

subscriptionRemoteSyncPlanInternalErrorResult() {
    local source=$1
    jq -n \
        --arg sourceId "$(jq -r '.id // "unknown"' <<<"${source}" 2>/dev/null || echo unknown)" \
        '{source_id:$sourceId, status:"internal_error", dry_run:true, error_detail:{type:"internal_error", message:"远程同步计划生成失败"}}'
}

subscriptionRemoteCollectParallelResults() {
    local sources=$1
    local tmpPattern=$2
    local workerFn=$3
    local fallbackFn=$4
    shift 4
    local source
    local tmpDir
    local outputFile
    local result
    local aggregatedResults
    local index=0
    local -a sourceList=()
    local -a outputFiles=()
    local -a resultList=()
    local -a workerArgs=("$@")
    local pids=()
    local maxConcurrency=${PADM_REMOTE_SYNC_MAX_CONCURRENCY:-8}

    [[ "${maxConcurrency}" =~ ^[1-9][0-9]*$ ]] || maxConcurrency=8

    [[ "${sources}" == '[]' ]] && { printf '[]\n'; return 0; }
    padmCreateTmpRootPath tmpDir "${tmpPattern}" -d || return 1
    mapfile -t sourceList < <(jq -c '.[]' <<<"${sources}")
    for source in "${sourceList[@]}"; do
        printf -v outputFile '%s/%06d.json' "${tmpDir}" "${index}"
        outputFiles+=("${outputFile}")
        (
            local writeResult
            writeResult=$("${workerFn}" "${source}" "${workerArgs[@]}" 2>/dev/null) || writeResult=
            if [[ -n "${writeResult}" ]]; then
                printf '%s\n' "${writeResult}" >"${outputFile}"
            else
                "${fallbackFn}" "${source}" >"${outputFile}" 2>/dev/null || true
            fi
        ) &
        pids+=("$!")
        index=$((index + 1))
        if ((${#pids[@]} >= maxConcurrency)); then
            wait "${pids[0]}" 2>/dev/null || true
            pids=("${pids[@]:1}")
        fi
    done
    for pid in "${pids[@]}"; do
        wait "${pid}" 2>/dev/null || true
    done
    if [[ "${#sourceList[@]}" == "0" ]]; then
        aggregatedResults='[]'
    elif aggregatedResults=$(jq -es --argjson expectedCount "${#sourceList[@]}" \
        'select(length == $expectedCount and all(.[]; type == "object"))' "${outputFiles[@]}" 2>/dev/null); then
        :
    else
        for index in "${!sourceList[@]}"; do
            source=${sourceList[$index]}
            printf -v outputFile '%s/%06d.json' "${tmpDir}" "${index}"
            if [[ -f "${outputFile}" ]] && result=$(jq -ce 'select(type == "object")' "${outputFile}" 2>/dev/null); then
                resultList+=("${result}")
            else
                result=$("${fallbackFn}" "${source}") || {
                    padmRemoveCleanupPath "${tmpDir}"
                    return 1
                }
                resultList+=("${result}")
            fi
        done
        aggregatedResults=$(printf '%s\n' "${resultList[@]}" | jq -s '.') || { padmRemoveCleanupPath "${tmpDir}"; return 1; }
    fi
    padmRemoveCleanupPath "${tmpDir}"
    printf '%s\n' "${aggregatedResults}"
}

subscriptionRemoteControlHealthAll() {
    local sources
    sources=$(subscriptionRemoteControlSources) || return 1
    subscriptionRemoteCollectParallelResults \
        "${sources}" \
        padm-remote-health.XXXXXX \
        subscriptionRemoteControlHealth \
        subscriptionRemoteHealthInternalErrorResult
}

subscriptionRemoteSyncPlanForSource() {
    local source=$1
    local desiredUsersBySource=${2:-}
    local dryRun=${3:-true}
    local selfAddress=${4-}
    local sourceId
    local payload
    local response
    local responseFields
    local responseOk
    local responseDryRun
    local responseChanged
    local responsePlan
    local errorMessage
    local errorType errorDetail
    local requestStatus
    local -a selfReferenceArgs=()

    sourceId=$(jq -r '.id' <<<"${source}")
    payload=$(subscriptionRemoteControlPayload "${source}" "${dryRun}" "${desiredUsersBySource}" "${sourceId}") || return 1
    [[ $# -ge 4 ]] && selfReferenceArgs=("${selfAddress}")
    if subscriptionRemoteSourceSelfReference "${source}" "${selfReferenceArgs[@]}"; then
        jq -n --arg sourceId "${sourceId}" --argjson payload "${payload}" --argjson dryRun "${dryRun}" '{source_id:$sourceId, status:"self_reference", error_detail:{type:"self_reference", message:"服务器源指向当前订阅服务，已跳过以避免递归同步"}, dry_run:$dryRun, request:$payload}'
    else
        if response=$(subscriptionRemoteControlRequest "${source}" sync "${payload}" 2>/dev/null); then
            if responseFields=$(jq -r --argjson dryRun "${dryRun}" '
              [
                ((.ok == true) | tostring),
                ((.dry_run == $dryRun) | tostring),
                ((.changed | type == "boolean") | tostring),
                (if (.plan | type) == "object" then (.plan | tojson) else "" end)
              ] | @tsv
            ' <<<"${response}" 2>/dev/null); then
                IFS=$'\t' read -r responseOk responseDryRun responseChanged responsePlan <<<"${responseFields}"
            else
                responseOk=false
                responseDryRun=false
                responseChanged=false
                responsePlan=
            fi
            if [[ "${responseOk}" == "true" && "${responseDryRun}" == "true" && "${responseChanged}" == "true" ]] &&
                subscriptionSyncValidateAccountPlan "${responsePlan}"; then
                jq -n --arg sourceId "${sourceId}" --argjson payload "${payload}" --argjson response "${response}" --argjson dryRun "${dryRun}" '{source_id:$sourceId, status:"success", dry_run:$dryRun, request:$payload, response:$response}'
            elif [[ "${responseOk}" == "true" ]]; then
                errorMessage="远端同步响应格式无效"
                jq -n --arg sourceId "${sourceId}" --arg errorMessage "${errorMessage}" --argjson payload "${payload}" --argjson response "${response}" --argjson dryRun "${dryRun}" '{source_id:$sourceId, status:"remote_error", error:$errorMessage, error_detail:{type:"invalid_response", message:$errorMessage}, dry_run:$dryRun, request:$payload, response:$response}'
            else
                errorMessage=$(subscriptionRemoteResponseErrorMessage "${response}")
                errorType=$(subscriptionRemoteResponseErrorType "${response}") || return 1
                jq -n --arg sourceId "${sourceId}" --arg errorMessage "${errorMessage}" --argjson payload "${payload}" --argjson response "${response}" --argjson dryRun "${dryRun}" --arg errorType "${errorType}" '{source_id:$sourceId, status:"remote_error", error:$errorMessage, error_detail:{type:$errorType, message:$errorMessage}, dry_run:$dryRun, request:$payload, response:$response}'
            fi
        else
            requestStatus=$?
            if ((requestStatus == 2)); then
                jq -n --arg sourceId "${sourceId}" --argjson payload "${payload}" --argjson dryRun "${dryRun}" '{source_id:$sourceId, status:"missing_token", error_detail:{type:"missing_token", message:"未配置控制 token"}, dry_run:$dryRun, request:$payload}'
            else
                errorDetail=$(subscriptionRemoteTransportErrorDetail "${source}" "${requestStatus}") || return 1
                jq -n --arg sourceId "${sourceId}" --argjson payload "${payload}" --argjson dryRun "${dryRun}" --argjson detail "${errorDetail}" '{source_id:$sourceId, status:"unreachable", error_detail:$detail, dry_run:$dryRun, request:$payload}'
            fi
        fi
    fi
}

subscriptionRemoteApplyDesiredUsersForSource() {
    local source=$1
    local desiredUsersBySource=$2
    local sourceId
    local result
    local status
    local message
    SUBSCRIPTION_REMOTE_SOURCE_ERROR=
    sourceId=$(jq -r '.id // empty' <<<"${source}") || return 1
    [[ -n "${sourceId}" ]] || return 1
    jq -e --arg sourceId "${sourceId}" '
      type == "object" and
      has($sourceId) and
      (.[$sourceId] | type == "array")
    ' <<<"${desiredUsersBySource}" >/dev/null 2>&1 || return 1
    result=$(subscriptionRemoteSyncPlanForSource "${source}" "${desiredUsersBySource}" false) || {
        SUBSCRIPTION_REMOTE_SOURCE_ERROR="远程服务器源 ${sourceId} 用户同步请求失败"
        return 1
    }
    status=$(jq -r '.status // empty' <<<"${result}") || return 1
    if [[ "${status}" == "success" ]]; then
        return 0
    fi
    message=$(jq -r '.error_detail.message // .error // "未知错误"' <<<"${result}") || return 1
    SUBSCRIPTION_REMOTE_SOURCE_ERROR="远程服务器源 ${sourceId} 用户同步失败：${message}"
    return 1
}

subscriptionRemoteDrainSource() {
    local source=$1
    local outputVar=$2
    local state=${3:-}
    local sourceId
    local desiredUsers
    local emptyUsers
    sourceId=$(jq -r '.id // empty' <<<"${source}") || return 1
    [[ -n "${sourceId}" ]] || return 1
    desiredUsers=$(subscriptionRemoteDesiredUsersBySource "[${source}]" "${state}") || return 1
    emptyUsers=$(jq -cn --arg sourceId "${sourceId}" '{($sourceId):[]}') || return 1
    subscriptionRemoteApplyDesiredUsersForSource "${source}" "${emptyUsers}" || return 1
    printf -v "${outputVar}" '%s' "${desiredUsers}"
}

subscriptionRemoteRestoreSourceUsersIfEnabled() {
    local source=$1
    local desiredUsersBySource=$2
    jq -e '.enabled == true' <<<"${source}" >/dev/null 2>&1 || return 0
    subscriptionRemoteApplyDesiredUsersForSource "${source}" "${desiredUsersBySource}"
}

setSubscriptionRemoteSourceEnabledUnlocked() {
    local id=$1
    local enabled=$2
    local source
    local originalUsers=
    local restoreError
    SUBSCRIPTION_REMOTE_SOURCE_MUTATION_ERROR=
    source=$(subscriptionActiveGroupRead -ce --arg id "${id}" 'first(.sources[]? | select(.id == $id and .role != "main"))') || return 1
    if [[ "${enabled}" == "false" ]] && jq -e '.enabled == true' <<<"${source}" >/dev/null 2>&1; then
        if ! subscriptionRemoteDrainSource "${source}" originalUsers; then
            SUBSCRIPTION_REMOTE_SOURCE_MUTATION_ERROR="${SUBSCRIPTION_REMOTE_SOURCE_ERROR:-远端用户清理失败}"
            return 1
        fi
    fi
    if setSubscriptionSourceEnabled "${id}" "${enabled}"; then
        return 0
    fi
    if [[ -n "${originalUsers}" ]] && ! subscriptionRemoteRestoreSourceUsersIfEnabled "${source}" "${originalUsers}"; then
        restoreError="${SUBSCRIPTION_REMOTE_SOURCE_ERROR:-远端用户恢复失败}"
        SUBSCRIPTION_REMOTE_SOURCE_MUTATION_ERROR="被控服务器状态更新失败，且${restoreError}"
    else
        SUBSCRIPTION_REMOTE_SOURCE_MUTATION_ERROR="被控服务器状态更新失败"
    fi
    return 1
}

setSubscriptionRemoteSourceEnabled() {
    subscriptionGroupsWithLock setSubscriptionRemoteSourceEnabledUnlocked "$@"
}

subscriptionRemoteSyncPlan() {
    local sources
    local desiredUsersBySource='{}'
    local selfAddress
    local -a workerArgs=()
    sources=$(subscriptionRemoteControlSources) || return 1
    if [[ "${sources}" != '[]' ]]; then
        desiredUsersBySource=$(subscriptionRemoteDesiredUsersBySource "${sources}") || return 1
        if selfAddress=$(subscriptionWireGuardReadState | jq -r '.address // empty'); then
            workerArgs=("${selfAddress}")
        fi
    fi
    subscriptionRemoteCollectParallelResults \
        "${sources}" \
        padm-remote-plan.XXXXXX \
        subscriptionRemoteSyncPlanForSource \
        subscriptionRemoteSyncPlanInternalErrorResult \
        "${desiredUsersBySource}" \
        true \
        "${workerArgs[@]}"
}

runSubscriptionRemoteSync() {
    local sources=${1-}
    local desiredUsersBySource='{}'
    local sourceMetadataRows
    local sourceId
    local sourceResult
    local syncResults
    local status
    local errorMessage
    local errorType
    local changed
    local plan
    local stateWriteFailed
    local failures='[]'
    local snapshots='{}'
    local sourceSnapshots
    local expectedAccounts
    local snapshotInvalid
    local snapshotError
    local resultFields
    local hasSubscriptions
    local -a failureMessages=()
    local -a snapshotEntries=()
    local selfAddress
    local -a workerArgs=()
    local -A sourceIdSet=()
    local -A expectedAccountsBySource=()
    if [[ -z "${sources}" ]]; then
        sources=$(subscriptionRemoteControlSources) || return 1
    fi
    if [[ "${sources}" == '[]' ]]; then
        printf '%s\n' '{"failures":[],"snapshots":{}}'
        return 0
    fi
    desiredUsersBySource=$(subscriptionRemoteDesiredUsersBySource "${sources}") || return 1
    if selfAddress=$(subscriptionWireGuardReadState | jq -r '.address // empty'); then
        workerArgs=("${selfAddress}")
    fi
    sourceMetadataRows=$(jq -r -s '
      .[0] as $sources |
      .[1] as $desiredUsersBySource |
      $sources[] | [
        .id,
        (($desiredUsersBySource[.id] // []) | [.[].account] | sort | tojson)
      ] | @tsv
    ' < <(printf '%s\n%s\n' "${sources}" "${desiredUsersBySource}")) || return 1
    while IFS=$'\t' read -r sourceId expectedAccounts; do
        [[ -n "${sourceId}" ]] || continue
        sourceIdSet["${sourceId}"]=1
        expectedAccountsBySource["${sourceId}"]=${expectedAccounts}
    done <<<"${sourceMetadataRows}"
    syncResults=$(subscriptionRemoteCollectParallelResults \
        "${sources}" \
        padm-remote-sync.XXXXXX \
        subscriptionRemoteSyncPlanForSource \
        subscriptionRemoteSyncPlanInternalErrorResult \
        "${desiredUsersBySource}" \
        false \
        "${workerArgs[@]}") || return 1
    while IFS= read -r sourceResult; do
        resultFields=$(jq -r '
          [
            (.source_id // ""),
            (.status // ""),
            (.response.changed | tostring),
            (.response.plan | tojson),
            (if ((.response | type) == "object") then ((.response | has("subscriptions")) | tostring) else "false" end)
          ] | @tsv
        ' <<<"${sourceResult}") || return 1
        IFS=$'\t' read -r sourceId status changed plan hasSubscriptions <<<"${resultFields}"
        [[ -n "${sourceId}" ]] || return 1
        [[ -n "${sourceIdSet["${sourceId}"]+x}" ]] || return 1
        stateWriteFailed=false
        snapshotInvalid=false
        snapshotError=
        case "${status}" in
        self_reference)
            setSubscriptionSourceSyncFailure "${sourceId}" self_reference "服务器源指向当前订阅服务，已跳过以避免递归同步" || stateWriteFailed=true
            failureMessages+=("远程服务器源 ${sourceId} 指向当前订阅服务，已跳过")
            ;;
        missing_token)
            errorMessage=$(jq -r '.error_detail.message // "未配置控制 token"' <<<"${sourceResult}") || return 1
            setSubscriptionSourceSyncFailure "${sourceId}" missing_token "${errorMessage}" || stateWriteFailed=true
            failureMessages+=("远程服务器源 ${sourceId} 未配置控制 token")
            ;;
        success)
            if [[ "${hasSubscriptions}" == "true" ]]; then
                expectedAccounts=${expectedAccountsBySource["${sourceId}"]-[]}
                if sourceSnapshots=$(jq -ce --argjson expectedAccounts "${expectedAccounts}" '
                  .response.subscriptions as $subscriptions
                  | select(
                      ($subscriptions | type == "object") and
                      (($subscriptions | keys | sort) == $expectedAccounts) and
                      ($subscriptions | all(to_entries[]?;
                        (.key | type == "string" and test("^[A-Za-z0-9_-]+$")) and
                        (.value | type == "object") and
                        (.value.default | type == "string") and
                        (.value.clash_meta | type == "string") and
                        (.value.sing_box | type == "array") and
                        (.value.sing_box | all(.[]?; type == "object" and ((.tag // "") | type == "string")))
                      ))
                    )
                  | $subscriptions
                ' <<<"${sourceResult}"); then
                    snapshotEntries+=("${sourceId}"$'\t'"${sourceSnapshots}")
                else
                    snapshotEntries+=("${sourceId}"$'\t'null)
                    snapshotError="返回的订阅快照格式无效"
                    failureMessages+=("远程服务器源 ${sourceId} ${snapshotError}")
                    snapshotInvalid=true
                fi
            else
                snapshotEntries+=("${sourceId}"$'\t'null)
                snapshotError="未返回完整订阅快照"
                failureMessages+=("远程服务器源 ${sourceId} ${snapshotError}")
                snapshotInvalid=true
            fi
            if [[ "${snapshotInvalid}" == "true" ]]; then
                setSubscriptionSourceSyncFailure "${sourceId}" invalid_response "${snapshotError}" || stateWriteFailed=true
            else
                setSubscriptionSourceSyncStatus "${sourceId}" success "${changed}" "${plan}" || stateWriteFailed=true
            fi
            ;;
        remote_error)
            errorType=$(jq -r '.error_detail.type // "remote_error"' <<<"${sourceResult}") || return 1
            errorMessage=$(jq -r 'if ((.error_detail.message // "") | length) > 0 then .error_detail.message else (.error // "unknown_error") end' <<<"${sourceResult}") || return 1
            setSubscriptionSourceSyncFailure "${sourceId}" "${errorType}" "${errorMessage}" || stateWriteFailed=true
            failureMessages+=("远程服务器源 ${sourceId} 拒绝同步: ${errorMessage}")
            ;;
        unreachable)
            errorType=$(jq -r '.error_detail.type // "unreachable"' <<<"${sourceResult}") || return 1
            errorMessage=$(jq -r '.error_detail.message // "不可达或同步请求失败"' <<<"${sourceResult}") || return 1
            setSubscriptionSourceSyncFailure "${sourceId}" "${errorType}" "${errorMessage}" || stateWriteFailed=true
            failureMessages+=("远程服务器源 ${sourceId} 不可达或同步请求失败: ${errorMessage}")
            ;;
        internal_error)
            errorMessage=$(jq -r '.error_detail.message // "远程同步结果生成失败"' <<<"${sourceResult}") || return 1
            setSubscriptionSourceSyncFailure "${sourceId}" internal_error "${errorMessage}" || stateWriteFailed=true
            failureMessages+=("远程服务器源 ${sourceId} 同步结果生成失败: ${errorMessage}")
            ;;
        *)
            return 1
            ;;
        esac
        if [[ "${status}" != "success" ]]; then
            snapshotEntries+=("${sourceId}"$'\t'null)
        fi
        if [[ "${stateWriteFailed}" == "true" ]]; then
            failureMessages+=("远程服务器源 ${sourceId} 同步状态写入失败")
        fi
    done < <(jq -c '.[]' <<<"${syncResults}")
    if ((${#snapshotEntries[@]} > 0)); then
        snapshots=$(printf '%s\n' "${snapshotEntries[@]}" | jq -Rsc '
          split("\n") |
          map(select(length > 0) | split("\t") | {key:.[0], value:(.[1] | fromjson)}) |
          from_entries
        ') || return 1
    fi
    if ((${#failureMessages[@]} > 0)); then
        failures=$(jq -cn --args '$ARGS.positional' -- "${failureMessages[@]}") || return 1
    fi
    jq -n --argjson failures "${failures}" --argjson snapshots "${snapshots}" '{failures:$failures, snapshots:$snapshots}'
}

subscriptionGroupSyncInstallScript() {
    if [[ -f /etc/padm/install.sh ]]; then
        echo /etc/padm/install.sh
    else
        echo "${PROJECT_ROOT}/install.sh"
    fi
}


subscriptionControlPort() {
    echo 10086
}

subscriptionControlServerScript() {
    local groupsDir
    groupsDir=$(subscriptionGroupsSafeDir) || return 1
    printf '%s/control_server.py\n' "${groupsDir}"
}

subscriptionControlServiceFile() {
    echo /etc/systemd/system/padm-subscription-control.service
}

subscriptionControlPythonStringLiteral() {
    command -v python3 >/dev/null 2>&1 || return 1
    python3 -c 'import json, sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$1"
}

subscriptionControlSystemdQuotedArgument() {
    local value=$1
    [[ "${value}" != *$'\n'* ]] || return 1
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    printf '"%s"\n' "${value}"
}

writeSubscriptionControlServer() {
    local serverScript
    local sourceScript
    local scriptPath
    local tokenFile
    local scriptVersion
    local port
    local scriptPathLiteral
    local tokenFileLiteral
    local scriptVersionLiteral
    local tmpFile
    serverScript=$(subscriptionControlServerScript) || return 1
    sourceScript="${PROJECT_ROOT}/shell/subscription/control_server.py"
    [[ -f "${sourceScript}" ]] || return 1
    scriptPath=$(subscriptionGroupSyncInstallScript) || return 1
    tokenFile=$(subscriptionControlTokenFile) || return 1
    scriptVersion=$(getScriptVersion) || return 1
    port=$(subscriptionControlPort) || return 1
    [[ "${port}" =~ ^[0-9]+$ ]] || return 1
    scriptPathLiteral=$(subscriptionControlPythonStringLiteral "${scriptPath}") || return 1
    tokenFileLiteral=$(subscriptionControlPythonStringLiteral "${tokenFile}") || return 1
    scriptVersionLiteral=$(subscriptionControlPythonStringLiteral "${scriptVersion}") || return 1
    padmCreateTempFileForTarget tmpFile "${serverScript}" control-server || return 1
    {
        printf 'import os\n'
        printf 'os.environ.setdefault("PADM_CONTROL_SCRIPT_PATH", %s)\n' "${scriptPathLiteral}"
        printf 'os.environ.setdefault("PADM_CONTROL_TOKEN_FILE", %s)\n' "${tokenFileLiteral}"
        printf 'os.environ.setdefault("PADM_CONTROL_VERSION", %s)\n' "${scriptVersionLiteral}"
        printf 'os.environ.setdefault("PADM_CONTROL_PORT", "%s")\n' "${port}"
        cat "${sourceScript}"
    } >"${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    commitGeneratedFile "${tmpFile}" "${serverScript}" 755 || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

subscriptionControlHealthCheck() {
    local token=$1
    local port
    local timeout=${PADM_CONTROL_HEALTH_TIMEOUT:-1}
    port=$(subscriptionControlPort)
    [[ -n "${token}" && -n "${port}" ]] || return 1
    PADM_CONTROL_HEALTH_TOKEN="${token}" PADM_CONTROL_HEALTH_PORT="${port}" PADM_CONTROL_HEALTH_TIMEOUT="${timeout}" python3 <<'PY'
import json
import os
import sys
import urllib.request

token = os.environ.get("PADM_CONTROL_HEALTH_TOKEN", "")
port = os.environ.get("PADM_CONTROL_HEALTH_PORT", "")
try:
    timeout = float(os.environ.get("PADM_CONTROL_HEALTH_TIMEOUT", "1") or "1")
    if timeout <= 0:
        raise ValueError
except ValueError:
    timeout = 1.0
if not token or not port:
    sys.exit(1)
request = urllib.request.Request(
    f"http://127.0.0.1:{port}/s/control/health",
    headers={"Authorization": f"Bearer {token}"},
)
try:
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode() or "{}")
except Exception:
    sys.exit(1)
sys.exit(0 if payload.get("ok") is True else 1)
PY
}

subscriptionControlRestoreServiceInstall() {
    local backupDir=$1
    local serviceWasActive=${2:-false}
    local serviceWasEnabled=${3:-false}
    local serviceName="padm-subscription-control.service"
    local rollbackFailed=false

    subscriptionControlMarkRollbackFailure() {
        "$@" >/dev/null 2>&1 || rollbackFailed=true
    }

    subscriptionControlMarkRollbackFailure checkLogBackupRestore "${backupDir}"
    subscriptionControlMarkRollbackFailure systemctl daemon-reload
    if [[ "${serviceWasActive}" == "true" ]]; then
        subscriptionControlMarkRollbackFailure systemctl restart "${serviceName}"
    else
        if systemctl is-active --quiet "${serviceName}" >/dev/null 2>&1; then
            subscriptionControlMarkRollbackFailure systemctl stop "${serviceName}"
        fi
        if [[ "${serviceWasEnabled}" == "true" ]]; then
            subscriptionControlMarkRollbackFailure systemctl enable "${serviceName}"
        elif systemctl is-enabled --quiet "${serviceName}" >/dev/null 2>&1; then
            subscriptionControlMarkRollbackFailure systemctl disable "${serviceName}"
        fi
    fi
    [[ "${rollbackFailed}" != "true" ]]
}

subscriptionControlFailInstall() {
    local backupDir=$1
    local reason=$2
    local serviceWasActive=${3:-false}
    local serviceWasEnabled=${4:-false}

    SUBSCRIPTION_CONTROL_INSTALL_ERROR=
    if subscriptionControlRestoreServiceInstall "${backupDir}" "${serviceWasActive}" "${serviceWasEnabled}"; then
        padmRemoveCleanupPath "${backupDir}"
        subscriptionSyncSetSingleRestoreResultMessage \
            SUBSCRIPTION_CONTROL_INSTALL_ERROR \
            "${reason}" \
            true \
            "已恢复安装前状态" \
            "安装前状态" \
            "备份目录: ${backupDir}"
    else
        padmForgetCleanupPath "${backupDir}"
        subscriptionSyncSetSingleRestoreResultMessage \
            SUBSCRIPTION_CONTROL_INSTALL_ERROR \
            "${reason}" \
            false \
            "已恢复安装前状态" \
            "安装前状态" \
            "备份目录: ${backupDir}"
    fi
    return 1
}

installSubscriptionControlService() {
    local serviceFile
    local serverScript
    local serverScriptArg
    local scriptPath
    local scriptPathArg
    local tokenFile
    local tokenFileArg
    local scriptVersionArg
    local tmpFile
    local token
    local i
    local retryCount
    local retryDelay
    local serviceBackupDir=
    local serviceWasActive=false
    local serviceWasEnabled=false
    SUBSCRIPTION_CONTROL_INSTALL_ERROR=
    if ! command -v python3 >/dev/null 2>&1; then
        errorCard "订阅控制服务缺少 python3"
        return 1
    fi
    if ! command -v systemctl >/dev/null 2>&1; then
        errorCard "订阅控制服务需要 systemd"
        return 1
    fi
    subscriptionControlEnsureToken || return 1
    token=$(subscriptionControlToken) || return 1
    [[ -n "${token}" ]] || return 1
    subscriptionGroupsSecureStateFiles || return 1
    serverScript=$(subscriptionControlServerScript)
    serverScriptArg=$(subscriptionControlSystemdQuotedArgument "${serverScript}") || return 1
    scriptPath=$(subscriptionGroupSyncInstallScript) || return 1
    scriptPathArg=$(subscriptionControlSystemdQuotedArgument "${scriptPath}") || return 1
    tokenFile=$(subscriptionControlTokenFile) || return 1
    tokenFileArg=$(subscriptionControlSystemdQuotedArgument "${tokenFile}") || return 1
    scriptVersionArg=$(subscriptionControlSystemdQuotedArgument "$(getScriptVersion)") || return 1
    serviceFile=$(subscriptionControlServiceFile)
    if systemctl is-active --quiet padm-subscription-control.service; then
        serviceWasActive=true
    fi
    if systemctl is-enabled --quiet padm-subscription-control.service; then
        serviceWasEnabled=true
    fi
    checkLogBackupCreate serviceBackupDir "${serverScript}" "${serviceFile}" || return 1
    writeSubscriptionControlServer || {
        subscriptionControlFailInstall "${serviceBackupDir}" "订阅控制服务脚本写入失败" "${serviceWasActive}" "${serviceWasEnabled}"
        return 1
    }
    padmCreateTempFileForTarget tmpFile "${serviceFile}" service || {
        subscriptionControlFailInstall "${serviceBackupDir}" "订阅控制服务配置临时文件创建失败" "${serviceWasActive}" "${serviceWasEnabled}"
        return 1
    }
    if ! cat >"${tmpFile}" <<EOF
[Unit]
Description=padm subscription control
After=network.target

[Service]
Type=simple
Environment=PADM_CONTROL_SCRIPT_PATH=${scriptPathArg}
Environment=PADM_CONTROL_TOKEN_FILE=${tokenFileArg}
Environment=PADM_CONTROL_VERSION=${scriptVersionArg}
Environment=PADM_CONTROL_PORT=$(subscriptionControlPort)
ExecStart=/usr/bin/env python3 ${serverScriptArg}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    then
        padmRemoveCleanupPath "${tmpFile}"
        subscriptionControlFailInstall "${serviceBackupDir}" "订阅控制服务配置临时文件写入失败" "${serviceWasActive}" "${serviceWasEnabled}"
        return 1
    fi
    commitGeneratedFile "${tmpFile}" "${serviceFile}" 644 || {
        padmRemoveCleanupPath "${tmpFile}"
        subscriptionControlFailInstall "${serviceBackupDir}" "订阅控制服务配置写入失败" "${serviceWasActive}" "${serviceWasEnabled}"
        return 1
    }
    if ! systemctl daemon-reload; then
        subscriptionControlFailInstall "${serviceBackupDir}" "订阅控制服务 daemon-reload 失败" "${serviceWasActive}" "${serviceWasEnabled}"
        return 1
    fi
    if systemctl is-active --quiet padm-subscription-control.service; then
        if ! systemctl restart padm-subscription-control.service >/dev/null 2>&1; then
            subscriptionControlFailInstall "${serviceBackupDir}" "订阅控制服务重启失败" "${serviceWasActive}" "${serviceWasEnabled}"
            return 1
        fi
    else
        if ! systemctl enable --now padm-subscription-control.service >/dev/null 2>&1; then
            subscriptionControlFailInstall "${serviceBackupDir}" "订阅控制服务启动失败" "${serviceWasActive}" "${serviceWasEnabled}"
            return 1
        fi
    fi
    retryCount=${PADM_CONTROL_HEALTH_RETRIES:-20}
    retryDelay=${PADM_CONTROL_HEALTH_RETRY_DELAY:-0.25}
    for ((i = 0; i < retryCount; i++)); do
        if subscriptionControlHealthCheck "${token}" >/dev/null 2>&1; then
            padmRemoveCleanupPath "${serviceBackupDir}"
            return 0
        fi
        sleep "${retryDelay}"
    done
    subscriptionControlFailInstall "${serviceBackupDir}" "订阅控制服务健康检查失败" "${serviceWasActive}" "${serviceWasEnabled}"
    return 1
}

subscriptionControlTokenFile() {
    local groupsDir
    groupsDir=$(subscriptionGroupsSafeDir) || return 1
    printf '%s/control.token\n' "${groupsDir}"
}

subscriptionControlEnsureToken() {
    local tokenFile
    local tokenValue
    local tokenDir
    local tmpFile
    tokenFile=$(subscriptionControlTokenFile)
    tokenDir=$(dirname -- "${tokenFile}")
    padmEnsureSafeDirectory "${tokenDir}" || return 1
    chmod 700 "${tokenDir}" 2>/dev/null || return 1
    if [[ ! -s "${tokenFile}" ]]; then
        padmCreateTempFileForTarget tmpFile "${tokenFile}" token || return 1
        if command -v openssl >/dev/null 2>&1; then
            if ! openssl rand -hex 32 >"${tmpFile}"; then
                padmRemoveCleanupPath "${tmpFile}"
                return 1
            fi
        else
            tokenValue=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 64 || true)
            if [[ "${#tokenValue}" -lt 64 ]] || ! printf '%s\n' "${tokenValue}" >"${tmpFile}"; then
                padmRemoveCleanupPath "${tmpFile}"
                return 1
            fi
        fi
        if ! commitGeneratedFile "${tmpFile}" "${tokenFile}" 600; then
            padmRemoveCleanupPath "${tmpFile}"
            return 1
        fi
    fi
    [[ -s "${tokenFile}" ]] || return 1
    chmod 600 "${tokenFile}" 2>/dev/null || return 1
}

subscriptionGroupsSecureStateFiles() {
    local groupsDir
    local groupsFile
    local backupDir
    local backupFile
    local lockFile
    groupsDir=$(subscriptionGroupsSafeDir) || return 1
    groupsFile=$(subscriptionGroupsFile)
    backupDir=$(subscriptionGroupsBackupDir) || return 1
    lockFile=$(subscriptionGroupsLockFile) || return 1
    padmEnsureSafeDirectory "${groupsDir}" || return 1
    chmod 700 "${groupsDir}" 2>/dev/null || return 1
    if [[ -f "${groupsFile}" ]]; then
        chmod 600 "${groupsFile}" 2>/dev/null || return 1
    fi
    if [[ -f "${lockFile}" ]]; then
        chmod 600 "${lockFile}" 2>/dev/null || return 1
    fi
    if [[ -d "${backupDir}" ]]; then
        chmod 700 "${backupDir}" 2>/dev/null || return 1
        for backupFile in "${backupDir}"/groups-*.json; do
            if [[ -f "${backupFile}" ]]; then
                chmod 600 "${backupFile}" 2>/dev/null || return 1
            fi
        done
    fi
}

subscriptionControlToken() {
    local tokenFile
    tokenFile=$(subscriptionControlTokenFile)
    if [[ ! -f "${tokenFile}" ]]; then
        subscriptionControlEnsureToken
    fi
    tr -d '[:space:]' <"${tokenFile}"
}

subscriptionControlSetAccountPlanFailure() {
    local previousGroupsState=$1
    local applyError=$2
    local restored=false
    if subscriptionGroupsStateWrite --argjson previousGroupsState "${previousGroupsState}" '$previousGroupsState' >/dev/null 2>&1; then
        restored=true
    fi
    subscriptionSyncSetSingleRestoreResultMessage \
        SUBSCRIPTION_SYNC_TRANSACTION_ERROR \
        "${applyError}" \
        "${restored}" \
        "" \
        "订阅状态" \
        "$(subscriptionGroupsFile)"
}

subscriptionControlApplyAccountPlan() {
    local plan=$1
    local desiredUsers=$2
    local previousGroupsState=${3-}
    local accountName
    local accountId
    local removeAccounts
    local removeIds='[]'
    local desiredUserIds
    local applyError=
    SUBSCRIPTION_SYNC_TRANSACTION_ERROR=
    subscriptionSyncValidateAccountPlan "${plan}" || return 1
    if [[ -z "${previousGroupsState}" ]]; then
        previousGroupsState=$(subscriptionGroupsStateRead -c '.') || return 1
    fi
    desiredUserIds=$(jq -c '[.[].id]' <<<"${desiredUsers}") || return 1
    removeIds=$(jq -c --argjson desiredIds "${desiredUserIds}" '
      [.user_groups[]?.id | . as $id | select(($desiredIds | index($id)) == null) | $id]
    ' <<<"${previousGroupsState}") || return 1
    removeAccounts=$(jq -r '(.remove - .create)[]' <<<"${plan}") || return 1
    while IFS= read -r accountName; do
        [[ -n "${accountName}" ]] || continue
        accountId=$(subscriptionSyncAccountIdFromName "${accountName}") || return 1
        removeIds=$(jq -c --arg id "${accountId}" '. + [$id] | unique' <<<"${removeIds}") || return 1
    done <<<"${removeAccounts}"
    if ! subscriptionApplyUserGroupState "${desiredUsers}" "${removeIds}"; then
        applyError="控制面同步期望用户状态写入失败"
        subscriptionControlSetAccountPlanFailure "${previousGroupsState}" "${applyError}" || return 1
        return 1
    fi
    if jq -e '(.create | length > 0) or (.remove | length > 0)' <<<"${plan}" >/dev/null 2>&1 &&
        ! subscriptionSyncApplyAccountPlanTransaction "${plan}"; then
        applyError="${SUBSCRIPTION_SYNC_TRANSACTION_ERROR:-控制面同步计划应用失败}"
        subscriptionControlSetAccountPlanFailure "${previousGroupsState}" "${applyError}" || return 1
        return 1
    fi
}

subscriptionControlUserRegistryNeedsSync() {
    local desiredUsers=$1
    subscriptionActiveGroupRead -r --argjson desiredUsers "${desiredUsers}" '
      ([.user_groups[]? | {id, enabled, uuid:(.uuid // "")}] | sort_by(.id)) as $current |
      ([$desiredUsers[]? | {id, enabled:true, uuid}] | sort_by(.id)) as $desired |
      $current != $desired
    '
}

subscriptionControlRestoreAppliedPlan() {
    local previousGroupsState=$1
    local configBackupDir=$2
    local outputBackupDir=${3:-}
    local restoreError=
    local restoreDetail=
    SUBSCRIPTION_CONTROL_RESTORE_ERROR=
    SUBSCRIPTION_CONTROL_CONFIG_RESTORED=false
    if ! subscriptionGroupsStateWrite --argjson previousGroupsState "${previousGroupsState}" '$previousGroupsState' >/dev/null 2>&1; then
        subscriptionSyncSetRestoreFailureDetail restoreDetail "状态"
        subscriptionSyncAppendRestoreFailureDetail restoreError "控制面同步失败后" "${restoreDetail}"
    fi
    if [[ -n "${configBackupDir}" ]]; then
        if ! subscriptionSyncRestoreConfigBackups "${configBackupDir}" >/dev/null 2>&1; then
            subscriptionSyncSetRestoreFailureDetail restoreDetail "配置" "备份目录: ${configBackupDir}"
            subscriptionSyncAppendRestoreFailureDetail restoreError "控制面同步失败后" "${restoreDetail}"
        else
            SUBSCRIPTION_CONTROL_CONFIG_RESTORED=true
        fi
    fi
    if [[ -n "${outputBackupDir}" ]]; then
        if ! subscriptionSyncRestoreSubscribeOutputBackups "${outputBackupDir}" >/dev/null 2>&1; then
            subscriptionSyncSetRestoreFailureDetail restoreDetail "订阅输出" "备份目录: ${outputBackupDir}"
            subscriptionSyncAppendRestoreFailureDetail restoreError "控制面同步失败后" "${restoreDetail}"
        fi
    fi
    if [[ -n "${restoreError}" ]]; then
        SUBSCRIPTION_CONTROL_RESTORE_ERROR="${restoreError}"
        return 1
    fi
}

subscriptionControlSyncResponse() {
    local plan=$1
    local dryRun=$2
    local changed=$3
    local desiredUsers=$4
    local subscriptions

    if [[ "${dryRun}" != "true" ]]; then
        if subscriptions=$(subscriptionControlRenderSubscribeAccounts "${desiredUsers}"); then
            jq -n --argjson plan "${plan}" --argjson changed "${changed}" --argjson subscriptions "${subscriptions}" \
                '{ok:true, dry_run:false, changed:$changed, plan:$plan, subscriptions:$subscriptions}'
        else
            jq -n --argjson plan "${plan}" --argjson changed "${changed}" \
                '{ok:false, dry_run:false, changed:$changed, plan:$plan, error:"generation_failed", error_detail:{type:"generation_failed", message:"远端订阅快照生成失败"}}'
            return 1
        fi
    else
        jq -n --argjson plan "${plan}" --argjson dryRun "${dryRun}" --argjson changed "${changed}" \
            '{ok:true, dry_run:$dryRun, changed:$changed, plan:$plan}'
    fi
}

subscriptionControlTrafficResponseUnlocked() {
    local payload=$1
    local snapshot
    local trafficItems
    if ! jq -e 'type == "object" and keys == []' <<<"${payload}" >/dev/null 2>&1; then
        jq -n '{ok:false, error:"invalid_payload", error_detail:{type:"invalid_payload", message:"流量请求体格式不正确"}}'
        return 1
    fi
    readInstallType
    readInstallProtocolType
    if ! ensureSubscriptionGroupsState || ! ensureTrafficStatsConfig; then
        jq -n '{ok:false, error:"traffic_failed", error_detail:{type:"traffic_failed", message:"流量统计配置不可用"}}'
        return 1
    fi
    if ! snapshot=$(collectLocalTrafficSnapshot); then
        jq -n '{ok:false, error:"traffic_failed", error_detail:{type:"traffic_failed", message:"本机流量统计采集失败"}}'
        return 1
    fi
    if writeSubscriptionTrafficSnapshot "${snapshot}" '[]' trafficItems >/dev/null 2>&1; then
        :
    elif [[ "${SUBSCRIPTION_TRAFFIC_VALIDATION_FAILED:-false}" == "true" ]]; then
        jq -n '{ok:false, error:"traffic_failed", error_detail:{type:"traffic_failed", message:"本机流量统计采集失败"}}'
        return 1
    else
        jq -n '{ok:false, error:"traffic_failed", error_detail:{type:"traffic_failed", message:"本机流量统计写入失败"}}'
        return 1
    fi
    printf '{"ok":true,"items":%s}\n' "${trafficItems}"
}

subscriptionControlTrafficResponse() {
    subscriptionGroupsWithLock subscriptionControlTrafficResponseUnlocked "$@"
}

subscriptionControlApplySyncUnlocked() {
    local payload=$1
    local dryRun
    local desiredUsers
    local plan
    local previousGroupsState
    local configBackupDir=
    local outputBackupDir=
    local prepareFailureMessage=
    local registryNeedsSync
    local planHasCoreChanges=false
    local localTrafficBaseline=false
    local localTrafficReady=false
    local payloadFields
    if ! payloadFields=$(jq -er '
      def valid_id: type == "string" and length <= 64 and test("^[A-Za-z0-9_-]+$");
      def valid_uuid: type == "string" and test("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$");
      select(
        type == "object" and
        (keys == ["desired_users", "dry_run"]) and
        (.desired_users | type == "array") and
        (.dry_run | type == "boolean") and
        all(.desired_users[]?; type == "object" and
          (keys == ["id", "uuid"]) and
          (.id | valid_id) and
          (.uuid | valid_uuid)) and
        ([.desired_users[]?.id] | length) == ([.desired_users[]?.id] | unique | length) and
        ([.desired_users[]?.uuid | ascii_downcase] | length) == ([.desired_users[]?.uuid | ascii_downcase] | unique | length)
      ) |
      [(.dry_run | tostring), (.desired_users | map({id, uuid}) | tojson)] | @tsv
    ' <<<"${payload}" 2>/dev/null); then
        jq -n '{ok:false, error:"invalid_payload", error_detail:{type:"invalid_payload", message:"同步请求体格式不正确"}}'
        return 1
    fi
    IFS=$'\t' read -r dryRun desiredUsers <<<"${payloadFields}"
    if ! plan=$(subscriptionSyncPlanFromDesiredUsers "${desiredUsers}"); then
        jq -n '{ok:false, error:"plan_failed", error_detail:{type:"plan_failed", message:"同步计划生成失败"}}'
        return 1
    fi
    if ! subscriptionSyncValidateAccountPlan "${plan}"; then
        if jq -e . <<<"${plan}" >/dev/null 2>&1; then
            jq -n --argjson plan "${plan}" '{ok:false, error:"plan_failed", error_detail:{type:"plan_failed", message:"同步计划格式无效"}, plan:$plan}'
        else
            jq -n '{ok:false, error:"plan_failed", error_detail:{type:"plan_failed", message:"同步计划格式无效"}}'
        fi
        return 1
    fi
    if jq -e '(.create | length > 0) or (.remove | length > 0)' <<<"${plan}" >/dev/null 2>&1; then
        planHasCoreChanges=true
    fi
    registryNeedsSync=$(subscriptionControlUserRegistryNeedsSync "${desiredUsers}") || {
        jq -n '{ok:false, error:"plan_failed", error_detail:{type:"plan_failed", message:"本地用户状态读取失败"}}'
        return 1
    }
    if [[ "${registryNeedsSync}" != "true" && "${planHasCoreChanges}" != "true" ]]; then
        subscriptionControlSyncResponse "${plan}" "${dryRun}" false "${desiredUsers}"
        return
    fi
    if [[ "${dryRun}" == "true" ]]; then
        jq -n --argjson plan "${plan}" '{ok:true, dry_run:true, changed:true, plan:$plan}'
        return 0
    fi
    if [[ "${planHasCoreChanges}" == "true" ]]; then
        if subscriptionLocalTrafficBaselineExists; then
            localTrafficBaseline=true
        fi
        SUBSCRIPTION_TRAFFIC_LOCAL_COMMITTED=false
        if collectSubscriptionTraffic >/dev/null 2>&1 || [[ "${SUBSCRIPTION_TRAFFIC_LOCAL_COMMITTED:-false}" == "true" ]]; then
            localTrafficReady=true
        fi
        if [[ "${localTrafficBaseline}" == "true" && "${localTrafficReady}" != "true" ]]; then
            prepareFailureMessage="同步前本机流量采集失败，为避免丢失累计流量已取消核心变更"
        fi
    fi
    if [[ -z "${prepareFailureMessage}" ]]; then
        if ! previousGroupsState=$(subscriptionGroupsStateRead -c '.'); then
            prepareFailureMessage="同步前订阅状态读取失败"
        elif ! subscriptionSyncCreateLocalApplyBackups configBackupDir outputBackupDir; then
            prepareFailureMessage="同步前配置备份失败"
            if [[ "${SUBSCRIPTION_SYNC_LOCAL_APPLY_BACKUP_STAGE:-}" == "config" ]]; then
                prepareFailureMessage="同步前订阅输出备份失败"
                configBackupDir=
                outputBackupDir=
            fi
        fi
    fi
    if [[ -n "${prepareFailureMessage}" ]]; then
        jq -n --argjson plan "${plan}" --arg message "${prepareFailureMessage}" '{ok:false, changed:false, dry_run:false, error:"prepare_failed", error_detail:{type:"prepare_failed", message:$message}, plan:$plan}'
        return 1
    fi
    SUBSCRIPTION_CONTROL_RESTORE_ERROR=
    if ! subscriptionControlApplyAccountPlan "${plan}" "${desiredUsers}" "${previousGroupsState}"; then
        subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}"
        jq -n --argjson plan "${plan}" --arg message "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR:-同步计划应用失败}" '{ok:false, changed:true, dry_run:false, error:"apply_plan_failed", error_detail:{type:"apply_plan_failed", message:$message}, plan:$plan}'
        return 1
    fi
    if [[ "${planHasCoreChanges}" == "true" ]]; then
        if [[ "${PADM_CONTROL_SERVER:-}" != "1" ]]; then
            if ! subscriptionSyncReconcileLocalServices; then
                if subscriptionControlRestoreAppliedPlan "${previousGroupsState}" "${configBackupDir}" "${outputBackupDir}"; then
                    subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}"
                    subscriptionSyncSetRollbackRetryMessage SUBSCRIPTION_CONTROL_RESTORE_ERROR "本机服务重建失败" subscriptionSyncReconcileLocalServices "恢复旧配置后服务重建仍失败，请检查核心服务日志" true
                else
                    subscriptionSyncReleaseLocalApplyBackups forget "${configBackupDir}" "${outputBackupDir}"
                    subscriptionSyncRetryPartiallyRestoredConfig \
                        SUBSCRIPTION_CONTROL_RESTORE_ERROR \
                        "${SUBSCRIPTION_CONTROL_CONFIG_RESTORED:-false}" \
                        subscriptionSyncReconcileLocalServices \
                        "恢复旧配置后服务重建仍失败，请检查核心服务日志" \
                        true || true
                fi
                collectSubscriptionTraffic >/dev/null 2>&1 || true
                jq -n --argjson plan "${plan}" --arg message "${SUBSCRIPTION_CONTROL_RESTORE_ERROR:-本机服务重建失败}" '{ok:false, changed:true, dry_run:false, error:"reconcile_failed", error_detail:{type:"reconcile_failed", message:$message}, plan:$plan}'
                return 1
            fi
        else
            if ! reloadCoreWithTrafficStatsConfig; then
                if subscriptionControlRestoreAppliedPlan "${previousGroupsState}" "${configBackupDir}" "${outputBackupDir}"; then
                    subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}"
                    subscriptionSyncSetRollbackRetryMessage SUBSCRIPTION_CONTROL_RESTORE_ERROR "核心重载失败" reloadCoreWithTrafficStatsConfig "恢复旧配置后核心重载仍失败，请检查核心服务日志" true
                else
                    subscriptionSyncReleaseLocalApplyBackups forget "${configBackupDir}" "${outputBackupDir}"
                    subscriptionSyncRetryPartiallyRestoredConfig \
                        SUBSCRIPTION_CONTROL_RESTORE_ERROR \
                        "${SUBSCRIPTION_CONTROL_CONFIG_RESTORED:-false}" \
                        reloadCoreWithTrafficStatsConfig \
                        "恢复旧配置后核心重载仍失败，请检查核心服务日志" || true
                fi
                collectSubscriptionTraffic >/dev/null 2>&1 || true
                jq -n --argjson plan "${plan}" --arg message "${SUBSCRIPTION_CONTROL_RESTORE_ERROR:-核心重载失败}" '{ok:false, changed:true, dry_run:false, error:"reload_failed", error_detail:{type:"reload_failed", message:$message}, plan:$plan}'
                return 1
            fi
        fi
    fi
    subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}"
    if [[ "${planHasCoreChanges}" == "true" ]]; then
        collectSubscriptionTraffic >/dev/null 2>&1 || true
    fi
    subscriptionControlSyncResponse "${plan}" false true "${desiredUsers}"
}

subscriptionControlApplySync() {
    subscriptionGroupsWithLock subscriptionControlApplySyncUnlocked "$@"
}

handleSubscriptionControl() {
    local endpoint=${1:-}
    local token=${2:-${PADM_CONTROL_TOKEN:-}}
    local payload=${3:-}
    local currentToken=
    if [[ "${endpoint}" != "refresh" ]]; then
        currentToken=$(subscriptionControlToken 2>/dev/null || true)
        if [[ -z "${currentToken}" || "${token}" != "${currentToken}" ]]; then
            jq -n '{ok:false, error:"unauthorized", error_detail:{type:"unauthorized", message:"控制 token 验证失败"}}'
            return 1
        fi
    fi
    if ! ensureSubscriptionGroupsState; then
        jq -n '{ok:false, error:"invalid_state", error_detail:{type:"invalid_state", message:"订阅组状态版本或结构无效"}}'
        return 1
    fi
    if [[ "${endpoint}" == "refresh" ]]; then
        if ! subscriptionControlRefreshAuthorized "${token}"; then
            jq -n '{ok:false, error:"unauthorized", error_detail:{type:"unauthorized", message:"控制 token 验证失败"}}'
            return 1
        fi
        if [[ "$(subscriptionActiveGroupRead -r '.sync.enabled == true')" != "true" ]]; then
            jq -n '{ok:true, refreshed:false, skipped:"automatic_sync_disabled"}'
            return 0
        fi
        if runSubscriptionGroupSync >/dev/null 2>&1; then
            jq -n '{ok:true, refreshed:true}'
        else
            jq -n '{ok:false, error:"refresh_failed", error_detail:{type:"refresh_failed", message:"主控订阅刷新失败"}}'
            return 1
        fi
        return 0
    fi
    if [[ "${endpoint}" == "health" ]]; then
        jq -n --arg version "$(getScriptVersion)" '{ok:true, version:$version, capabilities:["health","sync","traffic"]}'
    elif [[ "${endpoint}" == "traffic" ]]; then
        if [[ -z "${payload}" ]]; then
            payload=$(cat)
        fi
        if [[ -z "${payload}" ]]; then
            jq -n '{ok:false, error:"empty_payload", error_detail:{type:"empty_payload", message:"流量请求体为空"}}'
            return 1
        fi
        subscriptionControlTrafficResponse "${payload}"
    elif [[ "${endpoint}" == "sync" ]]; then
        if [[ -z "${payload}" ]]; then
            payload=$(cat)
        fi
        if [[ -z "${payload}" ]]; then
            jq -n '{ok:false, error:"empty_payload", error_detail:{type:"empty_payload", message:"同步请求体为空"}}'
            return 1
        fi
        subscriptionControlApplySync "${payload}"
    else
        jq -n '{ok:false, error:"unknown_endpoint", error_detail:{type:"unknown_endpoint", message:"未知控制端点"}}'
        return 1
    fi
}

subscriptionControlRenderSubscribeAccounts() (
    local desiredUsers=$1
    local subscribeRoot=
    local localBase account id defaultContent clashContent singBoxContent entry subscriptions
    local -a entries=()

    desiredUsers=$(jq -ce 'select(type == "array" and all(.[]?; (.id | type == "string" and length > 0)))' <<<"${desiredUsers}") || return 1
    if [[ "${desiredUsers}" == '[]' ]]; then
        printf '{}\n'
        return 0
    fi
    padmCreateTmpRootPath subscribeRoot padm-control-subscriptions.XXXXXX -d || return 1
    export PADM_SUBSCRIBE_LOCAL_DIR="${subscribeRoot}/subscribe_local"
    export PADM_SUBSCRIBE_DIR="${subscribeRoot}/subscribe"
    mkdir -p "${PADM_SUBSCRIBE_LOCAL_DIR}/default" "${PADM_SUBSCRIBE_LOCAL_DIR}/clashMeta" "${PADM_SUBSCRIBE_LOCAL_DIR}/sing-box" || {
        padmRemoveCleanupPath "${subscribeRoot}"
        return 1
    }
    showAccounts >/dev/null 2>&1 || { padmRemoveCleanupPath "${subscribeRoot}"; return 1; }
    localBase=$(subscribeLocalBaseDir)
    while IFS= read -r id; do
        [[ -n "${id}" ]] || continue
        account=$(subscriptionSyncAccountName "${id}") || { padmRemoveCleanupPath "${subscribeRoot}"; return 1; }
        [[ -f "${localBase}/default/${account}" || -f "${localBase}/clashMeta/${account}" || -f "${localBase}/sing-box/${account}" ]] || {
            padmRemoveCleanupPath "${subscribeRoot}"
            return 1
        }
        defaultContent=
        clashContent=
        singBoxContent='[]'
        if [[ -f "${localBase}/default/${account}" ]]; then
            defaultContent=$(base64 <"${localBase}/default/${account}" | tr -d '\n') || { padmRemoveCleanupPath "${subscribeRoot}"; return 1; }
        fi
        [[ -f "${localBase}/clashMeta/${account}" ]] && clashContent=$(<"${localBase}/clashMeta/${account}")
        if [[ -f "${localBase}/sing-box/${account}" ]]; then
            singBoxContent=$(jq -c . "${localBase}/sing-box/${account}") || { padmRemoveCleanupPath "${subscribeRoot}"; return 1; }
        fi
        entry=$(jq -cn \
            --arg account "${account}" \
            --arg default "${defaultContent}" \
            --arg clashMeta "${clashContent}" \
            --argjson singBox "${singBoxContent}" \
            '{key:$account, value:{default:$default, clash_meta:$clashMeta, sing_box:$singBox}}') || { padmRemoveCleanupPath "${subscribeRoot}"; return 1; }
        entries+=("${entry}")
    done < <(jq -r '.[].id' <<<"${desiredUsers}")
    subscriptions=$(printf '%s\n' "${entries[@]}" | jq -cs 'from_entries') || { padmRemoveCleanupPath "${subscribeRoot}"; return 1; }
    (( $(printf '%s' "${subscriptions}" | wc -c) <= 900000 )) || { padmRemoveCleanupPath "${subscribeRoot}"; return 1; }
    padmRemoveCleanupPath "${subscribeRoot}"
    printf '%s\n' "${subscriptions}"
)
