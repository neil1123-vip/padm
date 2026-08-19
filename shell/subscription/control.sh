#!/usr/bin/env bash

subscriptionRemoteControlSources() {
    subscriptionActiveGroupRead '
      [.sources[]? | select(.role != "main" and .enabled == true)]'
}

subscriptionRemoteDesiredUsersBySource() {
    local sources=$1
    local sourceIds
    local enabledUsers
    sourceIds=$(jq -c '[.[].id]' <<<"${sources}") || return 1
    enabledUsers=$(subscriptionActiveEnabledUsersJson) || return 1
    jq -e 'all(.[]?; (.uuid // "") | test("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"))' <<<"${enabledUsers}" >/dev/null 2>&1 || return 1
    jq -c -n --argjson sourceIds "${sourceIds}" --argjson users "${enabledUsers}" '
      reduce $sourceIds[]? as $sourceId ({};
        .[$sourceId] = [
          $users[]?
          | select((.allowed_sources | index($sourceId)) or (.allowed_sources | index("*")))
          | {id, name, uuid, traffic_limit_gb, account}
        ])
    ' || return 1
}

subscriptionRemoteSourceSelfReference() {
    local source=$1
    local sourceHost
    local selfHost
    sourceHost=$(jq -r '(.host // "") | ascii_downcase' <<<"${source}")
    selfHost=$(subscriptionWireGuardReadState | jq -r '.address // empty' | head -n 1)
    selfHost=$(subscriptionWireGuardAddressHost "${selfHost}")
    selfHost=$(tr 'A-Z' 'a-z' <<<"${selfHost}")
    [[ -n "${selfHost}" && "${sourceHost}" == "${selfHost}" ]]
}

subscriptionRemoteControlUrl() {
    local source=$1
    local endpoint=$2
    subscriptionWireGuardControlUrl "${source}" "${endpoint}"
}

subscriptionRemoteWireGuardPeerStateFromSource() {
    local source=$1
    local sourceId
    local publicKey
    local interface
    local endpoint=
    local handshake=0
    sourceId=$(jq -r '.id // empty' <<<"${source}") || return 1
    [[ -n "${sourceId}" ]] || return 1
    publicKey=$(subscriptionWireGuardReadState | jq -r --arg id "${sourceId}" '.peers[]? | select(.id == $id) | .public_key // empty' | head -n 1)
    [[ -n "${publicKey}" ]] || return 1
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
    local peerState
    local publicKey=
    local endpoint=
    local handshake=0
    local tryIndex
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
    local deadline
    local remainingTime
    local -a curlArgs=()
    local response
    local statusCode
    local body
    token=$(jq -r '.control_token // empty' <<<"${source}") || return 1
    [[ -n "${token}" ]] || return 2
    url=$(subscriptionRemoteControlUrl "${source}" "${endpoint}") || return 1
    if [[ "${endpoint}" == "sync" ]]; then
        maxTime=40
    else
        maxTime=15
    fi
    deadline=$((SECONDS + maxTime))
    curlArgs=(
        -sS
        --connect-timeout 5
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
    if ! response=$(subscriptionRemoteControlCurl "${token}" "${curlArgs[@]}" <<<"${payload}" 2>/dev/null); then
        subscriptionRemoteWireGuardWaitForPeerEndpointFromSource "${source}" "" "" "${baselineEndpoint}" "${baselineHandshake}" >/dev/null 2>&1 || true
        remainingTime=$((deadline - SECONDS))
        ((remainingTime > 0)) || return 1
        curlArgs[4]="${remainingTime}"
        response=$(subscriptionRemoteControlCurl "${token}" "${curlArgs[@]}" <<<"${payload}" 2>/dev/null) || return 1
    fi
    statusCode=${response##*$'\n'}
    body=${response%$'\n'*}
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

subscriptionRemoteControlPayload() {
    local source=$1
    local dryRun=$2
    local desiredUsersBySource=${3-}
    local sourceId
    local users
    sourceId=$(jq -r '.id' <<<"${source}")
    [[ -n "${desiredUsersBySource}" ]] || return 1
    users=$(jq -c --arg sourceId "${sourceId}" '[.[$sourceId][]? | {id, uuid}]' <<<"${desiredUsersBySource}") || return 1
    jq -n --argjson dryRun "${dryRun}" --argjson users "${users}" \
        '{dry_run:$dryRun, desired_users:$users}'
}

subscriptionRemoteResponseErrorMessage() {
    local response=$1
    local errorMessage
    local httpStatus
    errorMessage=$(jq -r 'if ((.error_detail.message // "") | length) > 0 then .error_detail.message else (.error // "unknown_error") end' <<<"${response}" 2>/dev/null || echo unknown_error)
    httpStatus=$(jq -r '.http_status // empty' <<<"${response}" 2>/dev/null || true)
    if [[ -n "${httpStatus}" && "${httpStatus}" != "null" ]]; then
        errorMessage="${errorMessage} (HTTP ${httpStatus})"
    fi
    printf '%s\n' "${errorMessage}"
}

subscriptionRemoteControlHealth() {
    local source=$1
    local token
    local url
    local peerState=
    local peerPublicKey=
    local baselineEndpoint=
    local baselineHandshake=0
    local -a curlArgs=()
    local response
    local statusCode
    local body
    local errorMessage
    token=$(jq -r '.control_token // empty' <<<"${source}") || return 1
    if [[ -z "${token}" ]]; then
        jq -n --arg id "$(jq -r '.id' <<<"${source}")" --arg name "$(jq -r '.name' <<<"${source}")" '{id:$id, name:$name, ok:false, status:"missing_token", error_detail:{type:"missing_token", message:"未配置控制 token"}}'
        return 0
    fi
    peerState=$(subscriptionRemoteWireGuardPeerStateFromSource "${source}" 2>/dev/null || true)
    if [[ -n "${peerState}" ]]; then
        IFS=$'\t' read -r peerPublicKey baselineEndpoint baselineHandshake <<<"${peerState}"
    fi
    url=$(subscriptionRemoteControlUrl "${source}" health) || return 1
    curlArgs=(
        -sS
        --connect-timeout 5
        --max-time 15
        --max-filesize 1048576
        -w '\n%{http_code}'
        "${url}"
    )
    response=$(subscriptionRemoteControlCurl "${token}" "${curlArgs[@]}" 2>/dev/null) || {
        subscriptionRemoteWireGuardWaitForPeerEndpointFromSource "${source}" "" "" "${baselineEndpoint}" "${baselineHandshake}" >/dev/null 2>&1 || true
        response=$(subscriptionRemoteControlCurl "${token}" "${curlArgs[@]}" 2>/dev/null) || {
            jq -n --arg id "$(jq -r '.id' <<<"${source}")" --arg name "$(jq -r '.name' <<<"${source}")" '{id:$id, name:$name, ok:false, status:"unreachable", error_detail:{type:"unreachable", message:"不可达或健康检查失败"}}'
            return 0
        }
    }
    statusCode=${response##*$'\n'}
    body=${response%$'\n'*}
    if [[ "${statusCode}" == "200" ]] && jq -e '.ok == true and (.capabilities | type == "array" and index("health") != null and index("sync") != null and index("traffic") != null)' <<<"${body}" >/dev/null 2>&1; then
        jq -c --arg id "$(jq -r '.id' <<<"${source}")" --arg name "$(jq -r '.name' <<<"${source}")" '. + {id:$id, name:$name, ok:true}' <<<"${body}"
        return 0
    fi
    if [[ "${statusCode}" == "401" ]]; then
        jq -n --arg id "$(jq -r '.id' <<<"${source}")" --arg name "$(jq -r '.name' <<<"${source}")" --arg statusCode "${statusCode}" '{id:$id, name:$name, ok:false, status:"unauthorized", status_code:$statusCode, error_detail:{type:"unauthorized", message:"控制 token 验证失败"}}'
        return 0
    fi
    if jq -c . <<<"${body}" >/dev/null 2>&1; then
        errorMessage=$(subscriptionRemoteResponseErrorMessage "${body}")
        [[ -n "${statusCode}" && "${statusCode}" != "null" ]] && errorMessage="${errorMessage} (HTTP ${statusCode})"
        jq -n --arg id "$(jq -r '.id' <<<"${source}")" --arg name "$(jq -r '.name' <<<"${source}")" --arg statusCode "${statusCode}" --arg errorMessage "${errorMessage}" '{id:$id, name:$name, ok:false, status:"remote_error", status_code:$statusCode, error:$errorMessage, error_detail:{type:"remote_error", message:$errorMessage}}'
        return 0
    fi
    jq -n --arg id "$(jq -r '.id' <<<"${source}")" --arg name "$(jq -r '.name' <<<"${source}")" --arg statusCode "${statusCode}" '{id:$id, name:$name, ok:false, status:"remote_error", status_code:$statusCode}'
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
    sourceId=$(jq -r '.id // empty' <<<"${source}") || return 1
    [[ -n "${sourceId}" ]] || return 1
    if subscriptionRemoteSourceSelfReference "${source}"; then
        jq -n --arg sourceId "${sourceId}" \
            '{source_id:$sourceId, status:"self_reference", error_detail:{type:"self_reference", message:"服务器源指向当前订阅服务，已跳过以避免递归采集"}}'
    elif [[ -z "$(jq -r '.control_token // empty' <<<"${source}")" ]]; then
        jq -n --arg sourceId "${sourceId}" \
            '{source_id:$sourceId, status:"missing_token", error_detail:{type:"missing_token", message:"未配置控制 token"}}'
    elif response=$(subscriptionRemoteControlRequest "${source}" traffic '{}'); then
        if jq -e '.ok == true' <<<"${response}" >/dev/null 2>&1 && jq -e '
          keys == ["items", "ok"] and
          (.items | type == "array") and
          ([.items[].account] | length) == ([.items[].account] | unique | length) and
          all(.items[]?;
            type == "object" and
            keys == ["account", "download", "upload"] and
            (.account | type == "string" and length > 0 and test("^[A-Za-z0-9_-]+$")) and
            (.upload | type == "number" and . >= 0 and . == floor) and
            (.download | type == "number" and . >= 0 and . == floor))
        ' <<<"${response}" >/dev/null 2>&1; then
            jq -n --arg sourceId "${sourceId}" --argjson response "${response}" \
                '{source_id:$sourceId, status:"success", response:$response}'
        elif jq -e '.ok == true' <<<"${response}" >/dev/null 2>&1; then
            jq -n --arg sourceId "${sourceId}" --argjson response "${response}" \
                '{source_id:$sourceId, status:"remote_error", error_detail:{type:"invalid_response", message:"远端流量响应格式无效"}, response:$response}'
        else
            jq -n --arg sourceId "${sourceId}" --arg message "$(subscriptionRemoteResponseErrorMessage "${response}")" --argjson response "${response}" \
                '{source_id:$sourceId, status:"remote_error", error_detail:{type:"remote_error", message:$message}, response:$response}'
        fi
    else
        jq -n --arg sourceId "${sourceId}" \
            '{source_id:$sourceId, status:"unreachable", error_detail:{type:"unreachable", message:"不可达或流量请求失败"}}'
    fi
}

subscriptionRemoteTrafficInternalErrorResult() {
    local source=$1
    jq -n \
        --arg sourceId "$(jq -r '.id // "unknown"' <<<"${source}" 2>/dev/null || echo unknown)" \
        '{source_id:$sourceId, status:"internal_error", error_detail:{type:"internal_error", message:"远端流量结果生成失败"}}'
}

subscriptionRemoteTrafficAll() {
    local sources
    sources=$(subscriptionRemoteControlSources) || return 1
    subscriptionRemoteCollectParallelResults \
        "${sources}" \
        padm-remote-traffic.XXXXXX \
        subscriptionRemoteTrafficForSource \
        subscriptionRemoteTrafficInternalErrorResult
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
    local -a resultList=()
    local -a workerArgs=("$@")
    local pids=()

    padmCreateTmpRootPath tmpDir "${tmpPattern}" -d || return 1
    mapfile -t sourceList < <(jq -c '.[]' <<<"${sources}")
    for source in "${sourceList[@]}"; do
        printf -v outputFile '%s/%06d.json' "${tmpDir}" "${index}"
        (
            local writeResult
            writeResult=$("${workerFn}" "${source}" "${workerArgs[@]}" 2>/dev/null) || writeResult=
            if [[ -n "${writeResult}" ]] && jq -e . <<<"${writeResult}" >/dev/null 2>&1; then
                printf '%s\n' "${writeResult}" >"${outputFile}"
            else
                "${fallbackFn}" "${source}" >"${outputFile}" 2>/dev/null || true
            fi
        ) &
        pids+=("$!")
        index=$((index + 1))
    done
    for pid in "${pids[@]}"; do
        wait "${pid}" 2>/dev/null || true
    done
    if [[ "${#sourceList[@]}" == "0" ]]; then
        aggregatedResults=$(jq -n '[]') || { padmRemoveCleanupPath "${tmpDir}"; return 1; }
    else
        for index in "${!sourceList[@]}"; do
            source=${sourceList[$index]}
            printf -v outputFile '%s/%06d.json' "${tmpDir}" "${index}"
            if [[ -f "${outputFile}" ]] && result=$(jq -c . "${outputFile}" 2>/dev/null); then
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
    local sourceId
    local payload
    local response
    local responsePlan
    local errorMessage

    sourceId=$(jq -r '.id' <<<"${source}")
    payload=$(subscriptionRemoteControlPayload "${source}" "${dryRun}" "${desiredUsersBySource}") || return 1
    if subscriptionRemoteSourceSelfReference "${source}"; then
        jq -n --arg sourceId "${sourceId}" --argjson payload "${payload}" --argjson dryRun "${dryRun}" '{source_id:$sourceId, status:"self_reference", error_detail:{type:"self_reference", message:"服务器源指向当前订阅服务，已跳过以避免递归同步"}, dry_run:$dryRun, request:$payload}'
    elif [[ -z "$(jq -r '.control_token // empty' <<<"${source}")" ]]; then
        jq -n --arg sourceId "${sourceId}" --argjson payload "${payload}" --argjson dryRun "${dryRun}" '{source_id:$sourceId, status:"missing_token", error_detail:{type:"missing_token", message:"未配置控制 token"}, dry_run:$dryRun, request:$payload}'
    else
        if response=$(subscriptionRemoteControlRequest "${source}" sync "${payload}" 2>/dev/null); then
            if jq -e '.ok == true' <<<"${response}" >/dev/null 2>&1; then
                responsePlan=$(jq -c '.plan' <<<"${response}") || return 1
                if jq -e --argjson dryRun "${dryRun}" '
                  (.dry_run == $dryRun) and
                  (.changed | type == "boolean") and
                  (.plan | type == "object")
                ' <<<"${response}" >/dev/null 2>&1 && subscriptionSyncValidateAccountPlan "${responsePlan}"; then
                    jq -n --arg sourceId "${sourceId}" --argjson payload "${payload}" --argjson response "${response}" --argjson dryRun "${dryRun}" '{source_id:$sourceId, status:"success", dry_run:$dryRun, request:$payload, response:$response}'
                else
                    errorMessage="远端同步响应格式无效"
                    jq -n --arg sourceId "${sourceId}" --arg errorMessage "${errorMessage}" --argjson payload "${payload}" --argjson response "${response}" --argjson dryRun "${dryRun}" '{source_id:$sourceId, status:"remote_error", error:$errorMessage, error_detail:{type:"invalid_response", message:$errorMessage}, dry_run:$dryRun, request:$payload, response:$response}'
                fi
            else
                errorMessage=$(subscriptionRemoteResponseErrorMessage "${response}")
                jq -n --arg sourceId "${sourceId}" --arg errorMessage "${errorMessage}" --argjson payload "${payload}" --argjson response "${response}" --argjson dryRun "${dryRun}" '{source_id:$sourceId, status:"remote_error", error:$errorMessage, error_detail:{type:"remote_error", message:$errorMessage}, dry_run:$dryRun, request:$payload, response:$response}'
            fi
        else
            jq -n --arg sourceId "${sourceId}" --argjson payload "${payload}" --argjson dryRun "${dryRun}" '{source_id:$sourceId, status:"unreachable", error_detail:{type:"unreachable", message:"不可达或同步请求失败"}, dry_run:$dryRun, request:$payload}'
        fi
    fi
}

subscriptionRemoteSyncPlan() {
    local sources
    local desiredUsersBySource='{}'
    sources=$(subscriptionRemoteControlSources) || return 1
    if jq -e 'length > 0' <<<"${sources}" >/dev/null 2>&1; then
        desiredUsersBySource=$(subscriptionRemoteDesiredUsersBySource "${sources}") || return 1
    fi
    subscriptionRemoteCollectParallelResults \
        "${sources}" \
        padm-remote-plan.XXXXXX \
        subscriptionRemoteSyncPlanForSource \
        subscriptionRemoteSyncPlanInternalErrorResult \
        "${desiredUsersBySource}"
}

runSubscriptionRemoteSync() {
    local sources
    local desiredUsersBySource='{}'
    local sourceId
    local source
    local sourceResult
    local syncResults
    local status
    local errorMessage
    local changed
    local plan
    local stateWriteFailed
    local failures='[]'
    local snapshots='{}'
    local sourceSnapshots
    local expectedAccounts
    local snapshotInvalid
    local snapshotError
    sources=$(subscriptionRemoteControlSources) || return 1
    if jq -e 'length > 0' <<<"${sources}" >/dev/null 2>&1; then
        desiredUsersBySource=$(subscriptionRemoteDesiredUsersBySource "${sources}") || return 1
    fi
    syncResults=$(subscriptionRemoteCollectParallelResults \
        "${sources}" \
        padm-remote-sync.XXXXXX \
        subscriptionRemoteSyncPlanForSource \
        subscriptionRemoteSyncPlanInternalErrorResult \
        "${desiredUsersBySource}" \
        false) || return 1
    while IFS= read -r sourceResult; do
        sourceId=$(jq -r '.source_id // empty' <<<"${sourceResult}") || return 1
        [[ -n "${sourceId}" ]] || return 1
        source=$(jq -ce --arg sourceId "${sourceId}" '.[] | select(.id == $sourceId)' <<<"${sources}") || return 1
        status=$(jq -r '.status // empty' <<<"${sourceResult}") || return 1
        stateWriteFailed=false
        snapshotInvalid=false
        snapshotError=
        case "${status}" in
        self_reference)
            errorMessage=$(jq -r '.error_detail.message // "服务器源指向当前订阅服务，已跳过以避免递归同步"' <<<"${sourceResult}") || return 1
            setSubscriptionSourceSyncFailure "${sourceId}" self_reference "服务器源指向当前订阅服务，已跳过以避免递归同步" || stateWriteFailed=true
            failures=$(jq --arg sourceId "${sourceId}" '. + ["远程服务器源 " + $sourceId + " 指向当前订阅服务，已跳过"]' <<<"${failures}")
            ;;
        missing_token)
            errorMessage=$(jq -r '.error_detail.message // "未配置控制 token"' <<<"${sourceResult}") || return 1
            setSubscriptionSourceSyncFailure "${sourceId}" missing_token "${errorMessage}" || stateWriteFailed=true
            failures=$(jq --arg sourceId "${sourceId}" '. + ["远程服务器源 " + $sourceId + " 未配置控制 token"]' <<<"${failures}")
            ;;
        success)
            changed=$(jq -r '.response.changed' <<<"${sourceResult}") || return 1
            plan=$(jq -c '.response.plan' <<<"${sourceResult}") || return 1
            if jq -e '.response | has("subscriptions")' <<<"${sourceResult}" >/dev/null 2>&1; then
                expectedAccounts=$(jq -c --arg sourceId "${sourceId}" '[.[$sourceId][]?.account] | sort' <<<"${desiredUsersBySource}") || return 1
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
                    snapshots=$(jq -c --arg sourceId "${sourceId}" --argjson sourceSnapshots "${sourceSnapshots}" '. + {($sourceId):$sourceSnapshots}' <<<"${snapshots}") || return 1
                else
                    snapshots=$(jq -c --arg sourceId "${sourceId}" '. + {($sourceId):null}' <<<"${snapshots}") || return 1
                    snapshotError="返回的订阅快照格式无效"
                    failures=$(jq --arg sourceId "${sourceId}" --arg errorMessage "${snapshotError}" '. + ["远程服务器源 " + $sourceId + " " + $errorMessage]' <<<"${failures}") || return 1
                    snapshotInvalid=true
                fi
            else
                snapshots=$(jq -c --arg sourceId "${sourceId}" '. + {($sourceId):null}' <<<"${snapshots}") || return 1
                snapshotError="未返回完整订阅快照"
                failures=$(jq --arg sourceId "${sourceId}" --arg errorMessage "${snapshotError}" '. + ["远程服务器源 " + $sourceId + " " + $errorMessage]' <<<"${failures}") || return 1
                snapshotInvalid=true
            fi
            if [[ "${snapshotInvalid}" == "true" ]]; then
                setSubscriptionSourceSyncFailure "${sourceId}" invalid_response "${snapshotError}" || stateWriteFailed=true
            else
                setSubscriptionSourceSyncStatus "${sourceId}" success "${changed}" "${plan}" || stateWriteFailed=true
            fi
            ;;
        remote_error)
            errorMessage=$(jq -r 'if ((.error_detail.message // "") | length) > 0 then .error_detail.message else (.error // "unknown_error") end' <<<"${sourceResult}") || return 1
            setSubscriptionSourceSyncFailure "${sourceId}" remote_error "${errorMessage}" || stateWriteFailed=true
            failures=$(jq --arg sourceId "${sourceId}" --arg errorMessage "${errorMessage}" '. + ["远程服务器源 " + $sourceId + " 拒绝同步: " + $errorMessage]' <<<"${failures}")
            ;;
        unreachable)
            errorMessage=$(jq -r '.error_detail.message // "不可达或同步请求失败"' <<<"${sourceResult}") || return 1
            setSubscriptionSourceSyncFailure "${sourceId}" unreachable "${errorMessage}" || stateWriteFailed=true
            failures=$(jq --arg sourceId "${sourceId}" '. + ["远程服务器源 " + $sourceId + " 不可达或同步请求失败"]' <<<"${failures}")
            ;;
        internal_error)
            errorMessage=$(jq -r '.error_detail.message // "远程同步结果生成失败"' <<<"${sourceResult}") || return 1
            setSubscriptionSourceSyncFailure "${sourceId}" internal_error "${errorMessage}" || stateWriteFailed=true
            failures=$(jq --arg sourceId "${sourceId}" --arg errorMessage "${errorMessage}" '. + ["远程服务器源 " + $sourceId + " 同步结果生成失败: " + $errorMessage]' <<<"${failures}")
            ;;
        *)
            return 1
            ;;
        esac
        if [[ "${status}" != "success" ]]; then
            snapshots=$(jq -c --arg sourceId "${sourceId}" '. + {($sourceId):null}' <<<"${snapshots}") || return 1
        fi
        if [[ "${stateWriteFailed}" == "true" ]]; then
            failures=$(jq --arg sourceId "${sourceId}" '. + ["远程服务器源 " + $sourceId + " 同步状态写入失败"]' <<<"${failures}") || return 1
        fi
    done < <(jq -c '.[]' <<<"${syncResults}")
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
    local scriptPath
    local scriptPathLiteral
    local scriptVersion
    local scriptVersionLiteral
    local tokenFile
    local tokenFileLiteral
    local tmpFile
    serverScript=$(subscriptionControlServerScript)
    scriptPath=$(subscriptionGroupSyncInstallScript)
    scriptVersion=$(getScriptVersion)
    tokenFile=$(subscriptionControlTokenFile)
    if command -v cygpath >/dev/null 2>&1; then
        scriptPath=$(cygpath -m "${scriptPath}")
        tokenFile=$(cygpath -m "${tokenFile}")
    fi
    scriptPathLiteral=$(subscriptionControlPythonStringLiteral "${scriptPath}") || return 1
    tokenFileLiteral=$(subscriptionControlPythonStringLiteral "${tokenFile}") || return 1
    scriptVersionLiteral=$(subscriptionControlPythonStringLiteral "${scriptVersion}") || return 1
    padmCreateTempFileForTarget tmpFile "${serverScript}" control-server || return 1
    cat >"${tmpFile}" <<EOF || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
#!/usr/bin/env python3
import json
import os
import signal
import shutil
import socket
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Lock

SCRIPT_PATH = ${scriptPathLiteral}
TOKEN_FILE = ${tokenFileLiteral}
VERSION = ${scriptVersionLiteral}
CAPABILITIES = ["health", "sync", "traffic"]
PORT = $(subscriptionControlPort)
MAX_BODY_SIZE = 256 * 1024
CONTROL_REQUEST_LOCK = Lock()
try:
    SCRIPT_TIMEOUT = max(0.1, float(os.environ.get("PADM_CONTROL_SCRIPT_TIMEOUT", "20") or "20"))
except ValueError:
    SCRIPT_TIMEOUT = 20
try:
    REQUEST_READ_TIMEOUT = max(0.1, float(os.environ.get("PADM_CONTROL_REQUEST_TIMEOUT", "10") or "10"))
except ValueError:
    REQUEST_READ_TIMEOUT = 10

class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(REQUEST_READ_TIMEOUT)

    def log_message(self, *_):
        return

    def respond(self, code, payload):
        data = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except OSError:
            pass

    def token(self):
        auth = self.headers.get("Authorization", "")
        if auth.startswith("Bearer "):
            return auth[7:]
        return ""

    def expected_token(self):
        try:
            with open(TOKEN_FILE, encoding="utf-8") as handle:
                return handle.read().strip()
        except OSError:
            return ""

    def authorized(self):
        expected = self.expected_token()
        return bool(expected) and self.token() == expected

    def endpoint(self):
        prefix = "/s/control/"
        if not self.path.startswith(prefix):
            return ""
        return self.path[len(prefix):].split("?", 1)[0]

    def parse_script_response(self, stdout, returncode):
        output = (stdout or "").strip()
        parsed = []
        decoder = json.JSONDecoder()
        if output:
            for index, char in enumerate(output):
                if char != "{":
                    continue
                try:
                    value, _ = decoder.raw_decode(output[index:])
                except json.JSONDecodeError:
                    continue
                if isinstance(value, dict):
                    parsed.append(value)
        body = None
        for candidate in reversed(parsed):
            if "ok" in candidate:
                body = candidate
                break
        if body is None and parsed:
            body = parsed[-1]
        if isinstance(body, dict):
            if returncode != 0:
                body = dict(body)
                body.setdefault("exit_code", returncode)
                if body.get("ok") is not False:
                    body["ok"] = False
                    body.setdefault("error", "script_failed")
                body.setdefault("error_detail", {"type": "script_failed", "message": f"脚本退出码 {returncode}"})
            return body
        if returncode != 0:
            return {"ok": False, "error": "script_failed", "exit_code": returncode, "error_detail": {"type": "script_failed", "message": f"脚本退出码 {returncode}"}}
        return {"ok": False, "error": "invalid_response", "error_detail": {"type": "invalid_response", "message": "脚本输出不是合法 JSON"}}

    def response_status(self, endpoint, body):
        if not isinstance(body, dict):
            return 500
        if body.get("ok") is True:
            return 200
        error = body.get("error", "")
        if error == "unauthorized":
            return 401
        if endpoint in ("sync", "traffic") and error in ("invalid_payload", "empty_payload"):
            return 400
        if endpoint == "health":
            return 503
        if error in ("script_timeout", "script_failed", "script_exec_failed", "invalid_response"):
            return 503
        if endpoint in ("sync", "traffic"):
            return 503
        return 500

    def call_script(self, endpoint, payload=""):
        bash_bin = shutil.which("bash.exe") or shutil.which("bash") or "/bin/bash"
        cmd = [bash_bin, SCRIPT_PATH, "SubscriptionControl", endpoint]
        env = dict(os.environ)
        env["PADM_CONTROL_SERVER"] = "1"
        env["PADM_CONTROL_TOKEN"] = self.token()
        env["PADM_SKIP_REMOTE_REF_CHECK"] = "1"
        popen_options = {"start_new_session": True} if os.name == "posix" else {
            "creationflags": getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
        }
        try:
            process = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
                encoding="utf-8",
                errors="replace",
                **popen_options,
            )
            stdout, _ = process.communicate(payload, timeout=SCRIPT_TIMEOUT)
        except subprocess.TimeoutExpired:
            if os.name == "posix":
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            else:
                taskkill = shutil.which("taskkill.exe") or shutil.which("taskkill")
                if taskkill:
                    subprocess.run(
                        [taskkill, "/PID", str(process.pid), "/T", "/F"],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        check=False,
                    )
                if process.poll() is None:
                    process.kill()
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()
            return {"ok": False, "error": "script_timeout", "error_detail": {"type": "script_timeout", "message": "脚本执行超时"}}
        except OSError:
            return {"ok": False, "error": "script_exec_failed", "error_detail": {"type": "script_exec_failed", "message": "脚本无法执行"}}
        return self.parse_script_response(stdout, process.returncode)

    def read_body(self, length):
        deadline = time.monotonic() + REQUEST_READ_TIMEOUT
        chunks = []
        remaining = length
        while remaining > 0:
            timeout = deadline - time.monotonic()
            if timeout <= 0:
                raise TimeoutError
            self.connection.settimeout(timeout)
            chunk = self.rfile.read(min(65536, remaining))
            if not chunk:
                raise ValueError
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)

    def do_GET(self):
        endpoint = self.endpoint()
        if endpoint != "health":
            self.respond(404, {"ok": False, "error": "not_found"})
            return
        if not self.authorized():
            self.respond(401, {"ok": False, "error": "unauthorized", "error_detail": {"type": "unauthorized", "message": "控制 token 验证失败"}})
            return
        self.respond(200, {"ok": True, "version": VERSION, "capabilities": CAPABILITIES})

    def do_POST(self):
        endpoint = self.endpoint()
        if endpoint not in ("sync", "traffic"):
            self.respond(404, {"ok": False, "error": "not_found"})
            return
        if not self.authorized():
            self.respond(401, {"ok": False, "error": "unauthorized", "error_detail": {"type": "unauthorized", "message": "控制 token 验证失败"}})
            return
        try:
            length = int(self.headers.get("Content-Length", "0") or "0")
        except ValueError:
            self.respond(400, {"ok": False, "error": "invalid_payload", "error_detail": {"type": "invalid_payload", "message": "Content-Length 无效"}})
            return
        if length < 0:
            self.respond(400, {"ok": False, "error": "invalid_payload", "error_detail": {"type": "invalid_payload", "message": "Content-Length 无效"}})
            return
        if length > MAX_BODY_SIZE:
            self.respond(413, {"ok": False, "error": "payload_too_large"})
            return
        try:
            payload = self.read_body(length).decode("utf-8", errors="replace") if length > 0 else ""
        except (socket.timeout, TimeoutError):
            self.respond(408, {"ok": False, "error": "request_timeout", "error_detail": {"type": "request_timeout", "message": "请求体读取超时"}})
            return
        except ValueError:
            self.respond(400, {"ok": False, "error": "invalid_payload", "error_detail": {"type": "invalid_payload", "message": "请求体不完整"}})
            return
        if not CONTROL_REQUEST_LOCK.acquire(blocking=False):
            self.respond(503, {"ok": False, "error": "busy", "error_detail": {"type": "busy", "message": "控制服务正在处理其他变更请求"}})
            return
        try:
            body = self.call_script(endpoint, payload)
        finally:
            CONTROL_REQUEST_LOCK.release()
        self.respond(self.response_status(endpoint, body), body)

ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
EOF
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

subscriptionControlCreateUsersFromPlan() {
    local desiredUsers=$1
    local createAccounts=$2
    jq -c -n \
      --argjson desiredUsers "${desiredUsers}" \
      --argjson createAccounts "${createAccounts}" '
      [ $desiredUsers[]?
        | select((.id // "") != "")
        | . as $user
        | ($user.id | '"${SUBSCRIPTION_SYNC_ACCOUNT_NAME_FROM_ID_JQ}"') as $account
        | select(any($createAccounts[]?; . == $account))
        | ($user.uuid // "") as $uuid
        | select($uuid != "")
        | {id: $user.id, uuid: $uuid}
      ]'
}

subscriptionControlApplyAccountPlan() {
    local plan=$1
    local desiredUsers=$2
    local accountName
    local accountId
    local createAccounts
    local createUsers
    local removeAccounts
    local removeIds='[]'
    local previousGroupsState
    local applyError=
    SUBSCRIPTION_SYNC_TRANSACTION_ERROR=
    subscriptionSyncValidateAccountPlan "${plan}" || return 1
    previousGroupsState=$(subscriptionGroupsStateRead -c '.') || return 1
    createAccounts=$(jq -c '.create' <<<"${plan}") || return 1
    createUsers=$(subscriptionControlCreateUsersFromPlan "${desiredUsers}" "${createAccounts}") || return 1
    removeAccounts=$(jq -r '(.remove - .create)[]' <<<"${plan}") || return 1
    while IFS= read -r accountName; do
        [[ -n "${accountName}" ]] || continue
        accountId=$(subscriptionSyncAccountIdFromName "${accountName}") || return 1
        removeIds=$(jq -c --arg id "${accountId}" '. + [$id] | unique' <<<"${removeIds}") || return 1
    done <<<"${removeAccounts}"
    if jq -e 'length > 0' <<<"${createUsers}" >/dev/null 2>&1 || jq -e 'length > 0' <<<"${removeIds}" >/dev/null 2>&1; then
        if ! subscriptionActiveGroupWrite --argjson users "${createUsers}" --argjson removeIds "${removeIds}" '
          .user_groups = [.user_groups[]? | select(.id as $id | ($removeIds | index($id) | not))] |
          .traffic.user_groups = (reduce $removeIds[] as $id ((.traffic.user_groups // {}); del(.[$id]))) |
          reduce $users[] as $user (.;
            if any(.user_groups[]?; .id == $user.id) then
              .user_groups |= map(if .id == $user.id then .uuid = $user.uuid else . end)
            else
              .user_groups += [{id:$user.id, name:$user.id, enabled:true, allowed_sources:["main"], traffic_limit_gb:0, token:"", uuid:$user.uuid}]
            end)
        '; then
            applyError="控制面同步期望用户状态写入失败"
            if ! subscriptionGroupsStateWrite --argjson previousGroupsState "${previousGroupsState}" '$previousGroupsState' >/dev/null 2>&1; then
                subscriptionSyncSetSingleRestoreResultMessage \
                    SUBSCRIPTION_SYNC_TRANSACTION_ERROR \
                    "${applyError}" \
                    false \
                    "" \
                    "订阅状态" \
                    "$(subscriptionGroupsFile)"
                return 1
            fi
            subscriptionSyncSetSingleRestoreResultMessage \
                SUBSCRIPTION_SYNC_TRANSACTION_ERROR \
                "${applyError}" \
                true \
                "" \
                "订阅状态" \
                "$(subscriptionGroupsFile)"
            return 1
        fi
    fi
    if ! subscriptionSyncApplyAccountPlanTransaction "${plan}"; then
        applyError="${SUBSCRIPTION_SYNC_TRANSACTION_ERROR:-控制面同步计划应用失败}"
        if ! subscriptionGroupsStateWrite --argjson previousGroupsState "${previousGroupsState}" '$previousGroupsState' >/dev/null 2>&1; then
            subscriptionSyncSetSingleRestoreResultMessage \
                SUBSCRIPTION_SYNC_TRANSACTION_ERROR \
                "${applyError}" \
                false \
                "" \
                "订阅状态" \
                "$(subscriptionGroupsFile)"
            return 1
        fi
        subscriptionSyncSetSingleRestoreResultMessage \
            SUBSCRIPTION_SYNC_TRANSACTION_ERROR \
            "${applyError}" \
            true \
            "" \
            "订阅状态" \
            "$(subscriptionGroupsFile)"
        return 1
    fi
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

subscriptionControlTrafficResponse() {
    local payload=$1
    local snapshot
    if ! jq -e 'type == "object" and keys == []' <<<"${payload}" >/dev/null 2>&1; then
        jq -n '{ok:false, error:"invalid_payload", error_detail:{type:"invalid_payload", message:"流量请求体格式不正确"}}'
        return 1
    fi
    readInstallType
    readInstallProtocolType
    if ! ensureSubscriptionGroupsState || ! ensureXrayTrafficStatsConfig; then
        jq -n '{ok:false, error:"traffic_failed", error_detail:{type:"traffic_failed", message:"流量统计配置不可用"}}'
        return 1
    fi
    snapshot=$(collectLocalTrafficSnapshot)
    if ! jq -e '
      .ok == true and
      (.items | type == "array") and
      ([.items[].account] | length) == ([.items[].account] | unique | length) and
      all(.items[]?;
        type == "object" and
        keys == ["account", "download", "upload"] and
        (.account | type == "string" and length > 0 and test("^[A-Za-z0-9_-]+$")) and
        (.upload | type == "number" and . >= 0 and . == floor) and
        (.download | type == "number" and . >= 0 and . == floor))
    ' <<<"${snapshot}" >/dev/null 2>&1; then
        jq -n '{ok:false, error:"traffic_failed", error_detail:{type:"traffic_failed", message:"本机流量统计采集失败"}}'
        return 1
    fi
    writeSubscriptionTrafficSnapshot "${snapshot}" >/dev/null 2>&1 || {
        jq -n '{ok:false, error:"traffic_failed", error_detail:{type:"traffic_failed", message:"本机流量统计写入失败"}}'
        return 1
    }
    jq -c '{ok:true, items:.items}' <<<"${snapshot}"
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
    if ! jq -e '
      def valid_id: type == "string" and length > 0 and test("^[A-Za-z0-9_-]+$");
      def valid_uuid: type == "string" and test("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$");
      type == "object" and
      (keys == ["desired_users", "dry_run"]) and
      (.desired_users | type == "array") and
      (.dry_run | type == "boolean") and
      all(.desired_users[]?; type == "object" and
        (keys == ["id", "uuid"]) and
        (.id | valid_id) and
        (.uuid | valid_uuid)) and
      ([.desired_users[]?.id] | length) == ([.desired_users[]?.id] | unique | length)
    ' <<<"${payload}" >/dev/null 2>&1; then
        jq -n '{ok:false, error:"invalid_payload", error_detail:{type:"invalid_payload", message:"同步请求体格式不正确"}}'
        return 1
    fi
    dryRun=$(jq -r '.dry_run' <<<"${payload}")
    desiredUsers=$(jq '[.desired_users[]? | {id, uuid}]' <<<"${payload}") || {
        jq -n '{ok:false, error:"invalid_payload", error_detail:{type:"invalid_payload", message:"同步请求体格式不正确"}}'
        return 1
    }
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
    if jq -e '(.create | length == 0) and (.remove | length == 0)' <<<"${plan}" >/dev/null 2>&1; then
        subscriptionControlSyncResponse "${plan}" "${dryRun}" false "${desiredUsers}"
        return
    fi
    if [[ "${dryRun}" == "true" ]]; then
        jq -n --argjson plan "${plan}" '{ok:true, dry_run:true, changed:true, plan:$plan}'
        return 0
    fi
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
    if [[ -n "${prepareFailureMessage}" ]]; then
        jq -n --argjson plan "${plan}" --arg message "${prepareFailureMessage}" '{ok:false, changed:false, dry_run:false, error:"prepare_failed", error_detail:{type:"prepare_failed", message:$message}, plan:$plan}'
        return 1
    fi
    SUBSCRIPTION_CONTROL_RESTORE_ERROR=
    if ! subscriptionControlApplyAccountPlan "${plan}" "${desiredUsers}"; then
        subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}"
        jq -n --argjson plan "${plan}" --arg message "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR:-同步计划应用失败}" '{ok:false, changed:true, dry_run:false, error:"apply_plan_failed", error_detail:{type:"apply_plan_failed", message:$message}, plan:$plan}'
        return 1
    fi
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
            jq -n --argjson plan "${plan}" --arg message "${SUBSCRIPTION_CONTROL_RESTORE_ERROR:-本机服务重建失败}" '{ok:false, changed:true, dry_run:false, error:"reconcile_failed", error_detail:{type:"reconcile_failed", message:$message}, plan:$plan}'
            return 1
        fi
    else
        if ! reloadCore; then
            if subscriptionControlRestoreAppliedPlan "${previousGroupsState}" "${configBackupDir}" "${outputBackupDir}"; then
                subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}"
                subscriptionSyncSetRollbackRetryMessage SUBSCRIPTION_CONTROL_RESTORE_ERROR "核心重载失败" reloadCore "恢复旧配置后核心重载仍失败，请检查核心服务日志" true
            else
                subscriptionSyncReleaseLocalApplyBackups forget "${configBackupDir}" "${outputBackupDir}"
                subscriptionSyncRetryPartiallyRestoredConfig \
                    SUBSCRIPTION_CONTROL_RESTORE_ERROR \
                    "${SUBSCRIPTION_CONTROL_CONFIG_RESTORED:-false}" \
                    reloadCore \
                    "恢复旧配置后核心重载仍失败，请检查核心服务日志" || true
            fi
            jq -n --argjson plan "${plan}" --arg message "${SUBSCRIPTION_CONTROL_RESTORE_ERROR:-核心重载失败}" '{ok:false, changed:true, dry_run:false, error:"reload_failed", error_detail:{type:"reload_failed", message:$message}, plan:$plan}'
            return 1
        fi
    fi
    subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}"
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
    currentToken=$(subscriptionControlToken 2>/dev/null || true)
    if [[ -z "${currentToken}" || "${token}" != "${currentToken}" ]]; then
        jq -n '{ok:false, error:"unauthorized", error_detail:{type:"unauthorized", message:"控制 token 验证失败"}}'
        return 1
    fi
    if ! ensureSubscriptionGroupsState; then
        jq -n '{ok:false, error:"invalid_state", error_detail:{type:"invalid_state", message:"订阅组状态版本或结构无效"}}'
        return 1
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
    local localBase account id defaultContent clashContent singBoxContent subscriptions='{}' snapshot

    jq -e 'type == "array" and all(.[]?; (.id | type == "string" and length > 0))' <<<"${desiredUsers}" >/dev/null 2>&1 || return 1
    if jq -e 'length == 0' <<<"${desiredUsers}" >/dev/null 2>&1; then
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
        snapshot=$(jq -n \
            --arg default "${defaultContent}" \
            --arg clashMeta "${clashContent}" \
            --argjson singBox "${singBoxContent}" \
            '{default:$default, clash_meta:$clashMeta, sing_box:$singBox}') || { padmRemoveCleanupPath "${subscribeRoot}"; return 1; }
        subscriptions=$(jq -c --arg account "${account}" --argjson snapshot "${snapshot}" '. + {($account):$snapshot}' <<<"${subscriptions}") || {
            padmRemoveCleanupPath "${subscribeRoot}"
            return 1
        }
    done < <(jq -r '.[].id' <<<"${desiredUsers}")
    (( $(printf '%s' "${subscriptions}" | wc -c) <= 900000 )) || { padmRemoveCleanupPath "${subscribeRoot}"; return 1; }
    padmRemoveCleanupPath "${subscribeRoot}"
    printf '%s\n' "${subscriptions}"
)
