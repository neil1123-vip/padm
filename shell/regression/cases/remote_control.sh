#!/usr/bin/env bash

remoteControlRegressionSourceId() {
    local source=$1
    local id=${source#*\"id\":\"}
    printf '%s\n' "${id%%\"*}"
}

runRemoteControlConcurrencyRegression() (
    local healthResult
    local planResult

    subscriptionRemoteControlSources() {
        cat <<'JSON'
[{"id":"src0","name":"Src0"},{"id":"src2","name":"Src2"},{"id":"src10","name":"Src10"}]
JSON
    }
    subscriptionRemoteControlPayload() {
        local dryRun=$2
        printf '{"dry_run":%s,"desired_users":[]}\n' "${dryRun}"
    }

    subscriptionRemoteControlHealth() {
        local source=$1
        local id
        id=$(remoteControlRegressionSourceId "${source}")
        [[ "${id}" == "src0" ]] && sleep 0.01
        printf '{"id":"%s","name":"%s","ok":true}\n' "${id}" "${id}"
    }

    subscriptionRemoteSyncPlanForSource() {
        local source=$1
        local sourceId
        sourceId=$(remoteControlRegressionSourceId "${source}")
        [[ "${sourceId}" == "src0" ]] && sleep 0.01
        printf '{"source_id":"%s","status":"success","dry_run":true,"request":{"source_id":"%s"},"response":{"ok":true,"dry_run":true,"changed":false,"plan":{"create":[],"remove":[]}}}\n' "${sourceId}" "${sourceId}"
    }

    healthResult=$(subscriptionRemoteControlHealthAll | jq -c .)
    [[ "${healthResult}" == *'"id":"src0"'*'"id":"src2"'*'"id":"src10"'* ]]

    planResult=$(subscriptionRemoteSyncPlan | jq -c .)
    [[ "${planResult}" == *'"source_id":"src0"'*'"source_id":"src2"'*'"source_id":"src10"'* ]]
    [[ "${planResult}" == *'"status":"success"'* ]]
)

runRemoteControlAggregationFailureRegression() (
    local healthResult
    local planResult

    subscriptionRemoteControlSources() {
        cat <<'JSON'
[{"id":"edge-a","name":"Edge A"},{"id":"edge-b","name":"Edge B"}]
JSON
    }
    subscriptionRemoteControlPayload() {
        local dryRun=$2
        printf '{"dry_run":%s,"desired_users":[]}\n' "${dryRun}"
    }

    subscriptionRemoteControlHealth() {
        local source=$1
        case "$(remoteControlRegressionSourceId "${source}")" in
        edge-a)
            printf '{"id":"edge-a","name":"Edge A","ok":true}\n'
            ;;
        edge-b)
            printf 'broken-health-json\n'
            ;;
        *)
            printf '{"id":"main","name":"Main","ok":true}\n'
            ;;
        esac
    }
    subscriptionRemoteSyncPlanForSource() {
        local source=$1
        case "$(remoteControlRegressionSourceId "${source}")" in
        edge-a)
            printf '{"source_id":"edge-a","status":"success","dry_run":true,"request":{"source_id":"edge-a"},"response":{"ok":true,"dry_run":true,"changed":false,"plan":{"create":[],"remove":[]}}}\n'
            ;;
        edge-b)
            printf 'broken-plan-json\n'
            ;;
        *)
            printf '{"source_id":"main","status":"success","dry_run":true,"request":{"source_id":"main"},"response":{"ok":true,"dry_run":true,"changed":false,"plan":{"create":[],"remove":[]}}}\n'
            ;;
        esac
    }

    healthResult=$(subscriptionRemoteControlHealthAll | jq -c .)
    [[ "${healthResult}" == *'"id":"edge-a"'*'"status":"internal_error"'*'"type":"internal_error"'* ]]

    planResult=$(subscriptionRemoteSyncPlan | jq -c .)
    [[ "${planResult}" == *'"source_id":"edge-a"'*'"status":"success"'* ]]
    [[ "${planResult}" == *'"status":"internal_error"'*'"type":"internal_error"'* ]]
)

runRemoteControlInlineAggregationHelpersRegression() (
    local healthResult
    local planResult

    subscriptionRemoteInternalErrorResult() {
        return 91
    }
    subscriptionRemoteWriteCheckedResult() {
        return 92
    }
    subscriptionRemoteCollectCheckedResults() {
        return 93
    }
    subscriptionRemoteControlSources() {
        cat <<'JSON'
[{"id":"edge-a","name":"Edge A"},{"id":"edge-b","name":"Edge B"}]
JSON
    }
    subscriptionRemoteControlHealth() {
        local source=$1
        case "$(remoteControlRegressionSourceId "${source}")" in
        edge-a)
            printf '{"id":"edge-a","name":"Edge A","ok":true}\n'
            ;;
        edge-b)
            printf 'broken-health-json\n'
            ;;
        *)
            return 1
            ;;
        esac
    }
    subscriptionRemoteSyncPlanForSource() {
        local source=$1
        case "$(remoteControlRegressionSourceId "${source}")" in
        edge-a)
            printf '{"source_id":"edge-a","status":"success","dry_run":true,"request":{"source_id":"edge-a"},"response":{"ok":true,"dry_run":true,"changed":false,"plan":{"create":[],"remove":[]}}}\n'
            ;;
        edge-b)
            printf 'broken-plan-json\n'
            ;;
        *)
            return 1
            ;;
        esac
    }

    healthResult=$(subscriptionRemoteControlHealthAll 2>/dev/null || true)
    [[ -n "${healthResult}" ]] || return 1
    healthResult=$(jq -c . <<<"${healthResult}") || return 1
    [[ "${healthResult}" == *'"id":"edge-a"'*'"status":"internal_error"'*'"type":"internal_error"'* ]] || return 1

    planResult=$(subscriptionRemoteSyncPlan 2>/dev/null || true)
    [[ -n "${planResult}" ]] || return 1
    planResult=$(jq -c . <<<"${planResult}") || return 1
    [[ "${planResult}" == *'"source_id":"edge-a"'*'"status":"success"'* ]] || return 1
    [[ "${planResult}" == *'"status":"internal_error"'*'"type":"internal_error"'* ]] || return 1
)

runRemoteControlSourcesParsedOnceRegression() (
    local parseCountFile="${TMP_DIR}/remote-control-sources-parse-count"
    local parseCount
    local result
    local sources='[{"id":"edge-a","name":"Edge A"},{"id":"edge-b","name":"Edge B"}]'

    : >"${parseCountFile}"
    jq() {
        if [[ "$#" -ge 2 && "$1" == "-c" && "$2" == ".[]" ]]; then
            printf 'x' >>"${parseCountFile}"
        fi
        command jq "$@"
    }
    remoteControlParseOnceWorker() {
        local source=$1
        local sourceId
        sourceId=$(remoteControlRegressionSourceId "${source}")
        printf '{"source_id":"%s","status":"success"}\n' "${sourceId}"
    }
    remoteControlParseOnceFallback() {
        local source=$1
        local sourceId
        sourceId=$(remoteControlRegressionSourceId "${source}")
        printf '{"source_id":"%s","status":"internal_error"}\n' "${sourceId}"
    }

    result=$(subscriptionRemoteCollectParallelResults "${sources}" padm-remote-parse-once.XXXXXX remoteControlParseOnceWorker remoteControlParseOnceFallback)
    jq -e 'length == 2 and .[0].source_id == "edge-a" and .[1].source_id == "edge-b"' <<<"${result}" >/dev/null
    parseCount=$(wc -c <"${parseCountFile}")
    ((parseCount == 1))
)

runRemoteControlHealthRegression() (
    local sourceMissing='{"id":"edge-missing","name":"Edge Missing","scheme":"wireguard","transport":"wireguard","host":"remote.example","port":443}'
    local sourceRemote='{"id":"edge-remote","name":"Edge Remote","control_token":"token","scheme":"wireguard","transport":"wireguard","host":"remote.example","port":443}'
    local sourceUnauthorized='{"id":"edge-auth","name":"Edge Auth","control_token":"token","scheme":"wireguard","transport":"wireguard","host":"remote.example","port":443}'
    local response

    curl() {
        case "${PADM_FAKE_REMOTE_HEALTH_MODE:-}" in
        unauthorized)
            printf '{"ok":false,"error":"unauthorized"}\n401'
            ;;
        remote_error)
            printf '{"ok":false,"error":"service_unavailable","error_detail":{"type":"service_unavailable","message":"服务暂时不可用"}}\n503'
            ;;
        success)
            printf '{"ok":true,"version":"test","capabilities":["health","sync","traffic"]}\n200'
            ;;
        *)
            printf '{"ok":false,"error":"unexpected"}\n500'
            ;;
        esac
    }

    response=$(subscriptionRemoteControlHealth "${sourceMissing}" | jq -c .)
    [[ "${response}" == *'"status":"missing_token"'* ]]
    [[ "${response}" == *'"type":"missing_token"'* ]]
    [[ "${response}" == *'未配置控制 token'* ]]

    response=$(PADM_FAKE_REMOTE_HEALTH_MODE=unauthorized subscriptionRemoteControlHealth "${sourceUnauthorized}" | jq -c .)
    [[ "${response}" == *'"status":"unauthorized"'* ]]
    [[ "${response}" == *'"status_code":"401"'* ]]
    [[ "${response}" == *'"type":"unauthorized"'* ]]
    [[ "${response}" == *'控制 token 验证失败'* ]]

    response=$(PADM_FAKE_REMOTE_HEALTH_MODE=remote_error subscriptionRemoteControlHealth "${sourceRemote}" | jq -c .)
    [[ "${response}" == *'"status":"remote_error"'* ]]
    [[ "${response}" == *'"status_code":"503"'* ]]
    [[ "${response}" == *'"type":"remote_error"'* ]]
    [[ "${response}" == *'服务暂时不可用'* ]]

    response=$(PADM_FAKE_REMOTE_HEALTH_MODE=success subscriptionRemoteControlHealth "${sourceRemote}" | jq -c .)
    [[ "${response}" == *'"ok":true'* ]]
    [[ "${response}" == *'"version":"test"'* ]]
    [[ "${response}" == *'"capabilities":["health","sync","traffic"]'* ]]
    [[ "${response}" == *'"id":"edge-remote"'* ]]
    [[ "${response}" == *'"name":"Edge Remote"'* ]]
)

runRemoteControlInlineRequestHelpersRegression() (
    local source='{"id":"edge-remote","name":"Edge Remote","control_token":"token","scheme":"wireguard","transport":"wireguard","host":"10.77.0.2","port":39778}'
    local legacySource='{"id":"edge-legacy","name":"Edge Legacy","control_token":"token","scheme":"https","transport":"https","host":"remote.example","port":443}'
    local requestResponse
    local healthResponse
    local curlArgsLog="${TMP_DIR}/remote-control-inline-request-curl-args.log"
    local curlHeaderFilesLog="${TMP_DIR}/remote-control-inline-request-curl-header-files.log"
    local curlChmodLog="${TMP_DIR}/remote-control-inline-request-curl-chmod.log"
    local curlPayloadLog="${TMP_DIR}/remote-control-inline-request-curl-payload.log"
    local retryLog="${TMP_DIR}/remote-control-inline-request-retry.log"
    local requestMode=success

    : >"${curlArgsLog}"
    : >"${curlHeaderFilesLog}"
    : >"${curlChmodLog}"
    : >"${curlPayloadLog}"
    : >"${retryLog}"

    [[ "$(subscriptionRemoteControlUrl "${source}" sync)" == "http://10.77.0.2:39778/s/control/sync" ]]
    ! subscriptionRemoteControlUrl "${legacySource}" sync >/dev/null 2>&1

    subscriptionRemoteControlUrl() {
        printf 'https://control.example/%s\n' "$2"
    }
    subscriptionRemoteControlToken() {
        return 98
    }
    subscriptionRemoteControlCurlOnce() {
        return 99
    }
    subscriptionWireGuardControlUrl() {
        printf 'https://control.example/%s\n' "$2"
    }
    subscriptionRemoteWireGuardWaitForPeerEndpointFromSource() {
        printf 'wait\n' >>"${retryLog}"
        SECONDS=$((SECONDS + 40))
    }
    chmod() {
        printf '%s\n' "$*" >>"${curlChmodLog}"
        command chmod "$@"
    }
    curl() {
        local expectHeader=false
        local arg
        local stdinPayload=
        printf '%s\n' "$*" >>"${curlArgsLog}"
        for arg in "$@"; do
            if [[ "${arg}" == "@-" ]]; then
                stdinPayload=$(cat)
                printf '%s\n' "${stdinPayload}" >>"${curlPayloadLog}"
            fi
            if [[ "${expectHeader}" == "true" ]]; then
                if [[ "${arg}" == @* ]]; then
                    local headerFile="${arg#@}"
                    printf '%s\n' "${headerFile}" >>"${curlHeaderFilesLog}"
                    [[ "$(<"${headerFile}")" == "Authorization: Bearer token" ]] || return 1
                fi
                expectHeader=false
                continue
            fi
            [[ "${arg}" == "-H" ]] && expectHeader=true
        done
        [[ "${requestMode}" == "success" ]] || return 1
        case "$*" in
        *'https://control.example/sync'*)
            printf '{"ok":true,"dry_run":false,"changed":false,"plan":{"create":[],"remove":[]}}\n200'
            ;;
        *'https://control.example/health'*)
            printf '{"ok":true,"version":"test","capabilities":["health","sync","traffic"]}\n200'
            ;;
        *)
            return 1
            ;;
        esac
    }

    requestResponse=$(subscriptionRemoteControlRequest "${source}" sync '{"desired_users":[],"dry_run":false}' 2>/dev/null || true)
    [[ -n "${requestResponse}" ]] || return 1
    requestResponse=$(jq -c . <<<"${requestResponse}") || return 1
    [[ "${requestResponse}" == *'"ok":true'* ]] || return 1
    [[ "${requestResponse}" == *'"changed":false'* ]] || return 1
    [[ "${requestResponse}" == *'"create":[]'*'"remove":[]'* ]] || return 1

    healthResponse=$(subscriptionRemoteControlHealth "${source}" 2>/dev/null || true)
    [[ -n "${healthResponse}" ]] || return 1
    healthResponse=$(jq -c . <<<"${healthResponse}") || return 1
    [[ "${healthResponse}" == *'"ok":true'* ]] || return 1
    [[ "${healthResponse}" == *'"version":"test"'* ]] || return 1
    [[ "${healthResponse}" == *'"capabilities":["health","sync","traffic"]'* ]] || return 1
    [[ "${healthResponse}" == *'"id":"edge-remote"'* ]] || return 1
    [[ "${healthResponse}" == *'"name":"Edge Remote"'* ]] || return 1
    [[ "$(grep -c -- '--max-filesize 1048576' "${curlArgsLog}")" == "2" ]] || return 1
    ! grep -qF 'Authorization: Bearer token' "${curlArgsLog}"
    [[ "$(wc -l <"${curlHeaderFilesLog}" | tr -d ' ')" == "2" ]] || return 1
    [[ "$(grep -c '^600 .*/padm-control-auth\.' "${curlChmodLog}")" == "2" ]] || return 1
    grep -q -- '--max-time 40' "${curlArgsLog}" || return 1
    grep -qF -- '--data-binary @-' "${curlArgsLog}" || return 1
    ! grep -qF 'desired_users' "${curlArgsLog}"
    grep -qxF '{"desired_users":[],"dry_run":false}' "${curlPayloadLog}" || return 1

    requestMode=budget-exhausted
    : >"${curlArgsLog}"
    ! subscriptionRemoteControlRequest "${source}" sync '{"desired_users":[],"dry_run":false}' >/dev/null 2>&1
    [[ "$(wc -l <"${curlArgsLog}" | tr -d ' ')" == "1" ]] || return 1
    [[ "$(wc -l <"${retryLog}" | tr -d ' ')" == "1" ]] || return 1
    while IFS= read -r headerFile; do
        [[ -n "${headerFile}" ]] || continue
        [[ ! -e "${headerFile}" ]] || return 1
    done <"${curlHeaderFilesLog}"
)

runRemoteControlInlineWireGuardPeerHelpersRegression() (
    local source='{"id":"edge-remote","name":"Edge Remote","control_token":"token","scheme":"wireguard","transport":"wireguard","host":"remote.example","port":443}'
    local requestResponse
    local healthResponse
    local endpointLog="${TMP_DIR}/remote-control-inline-wireguard-peer-endpoints.log"
    local handshakeLog="${TMP_DIR}/remote-control-inline-wireguard-peer-handshakes.log"
    local curlLog="${TMP_DIR}/remote-control-inline-wireguard-peer-curl.log"

    : >"${endpointLog}"
    : >"${handshakeLog}"
    : >"${curlLog}"

    subscriptionRemoteWireGuardPeerPublicKeyFromSource() {
        return 96
    }
    subscriptionRemoteWireGuardPeerEndpoint() {
        return 97
    }
    subscriptionRemoteWireGuardPeerLatestHandshake() {
        return 98
    }
    subscriptionRemoteWireGuardPeerReadyState() {
        return 99
    }
    subscriptionWireGuardReadState() {
        printf '{"peers":[{"id":"edge-remote","public_key":"pub-edge"}]}\n'
    }
    subscriptionWireGuardInterface() {
        printf 'wg-padm\n'
    }
    subscriptionWireGuardControlUrl() {
        printf 'https://control.example/%s\n' "$2"
    }
    wg() {
        [[ "$1" == "show" && "$2" == "wg-padm" ]] || return 1
        case "$3" in
        endpoints)
            printf '1\n' >>"${endpointLog}"
            if [[ "$(wc -l <"${endpointLog}")" == "1" ]]; then
                printf 'pub-edge (none)\n'
            else
                printf 'pub-edge 203.0.113.10:51820\n'
            fi
            ;;
        latest-handshakes)
            printf '1\n' >>"${handshakeLog}"
            if [[ "$(wc -l <"${handshakeLog}")" == "1" ]]; then
                printf 'pub-edge 0\n'
            else
                printf 'pub-edge 123\n'
            fi
            ;;
        *)
            return 1
            ;;
        esac
    }
    curl() {
        printf '1\n' >>"${curlLog}"
        if (( $(wc -l <"${endpointLog}") < 2 || $(wc -l <"${handshakeLog}") < 2 )); then
            return 1
        fi
        case "$*" in
        *'https://control.example/sync'*)
            printf '{"ok":true,"dry_run":false,"changed":false,"plan":{"create":[],"remove":[]}}\n200'
            ;;
        *'https://control.example/health'*)
            printf '{"ok":true,"version":"test","capabilities":["health","sync","traffic"]}\n200'
            ;;
        *)
            return 1
            ;;
        esac
    }

    requestResponse=$(subscriptionRemoteControlRequest "${source}" sync '{"desired_users":[],"dry_run":false}' 2>/dev/null || true)
    [[ -n "${requestResponse}" ]] || return 1
    requestResponse=$(jq -c . <<<"${requestResponse}") || return 1
    [[ "${requestResponse}" == *'"ok":true'* ]] || return 1
    [[ "${requestResponse}" == *'"changed":false'* ]] || return 1
    [[ "${requestResponse}" == *'"create":[]'*'"remove":[]'* ]] || return 1
    [[ "$(wc -l <"${endpointLog}")" == "2" ]] || return 1
    [[ "$(wc -l <"${handshakeLog}")" == "2" ]] || return 1
    [[ "$(wc -l <"${curlLog}")" == "2" ]] || return 1

    : >"${endpointLog}"
    : >"${handshakeLog}"
    : >"${curlLog}"

    healthResponse=$(subscriptionRemoteControlHealth "${source}" 2>/dev/null || true)
    [[ -n "${healthResponse}" ]] || return 1
    healthResponse=$(jq -c . <<<"${healthResponse}") || return 1
    [[ "${healthResponse}" == *'"ok":true'* ]] || return 1
    [[ "${healthResponse}" == *'"version":"test"'* ]] || return 1
    [[ "${healthResponse}" == *'"capabilities":["health","sync","traffic"]'* ]] || return 1
    [[ "${healthResponse}" == *'"id":"edge-remote"'* ]] || return 1
    [[ "${healthResponse}" == *'"name":"Edge Remote"'* ]] || return 1
    [[ "$(wc -l <"${endpointLog}")" == "2" ]] || return 1
    [[ "$(wc -l <"${handshakeLog}")" == "2" ]] || return 1
    [[ "$(wc -l <"${curlLog}")" == "2" ]] || return 1
)

runRemoteControlInlineTokenConsumersRegression() (
    local remoteSourceJson='{"id":"edge-remote","name":"Edge Remote","control_token":"token","scheme":"wireguard","transport":"wireguard","host":"10.77.0.2","port":10086}'
    local desiredUsersBySourceJson='{"edge-remote":[{"id":"team-a","name":"Team A","uuid":"11111111-1111-1111-1111-111111111111","traffic_limit_gb":1,"account":"sub_team_a"}]}'
    local requestPayloadLog="${TMP_DIR}/remote-control-inline-token-consumers.payloads"
    local statusLog="${TMP_DIR}/remote-control-inline-token-consumers.status"
    local healthLog="${TMP_DIR}/remote-control-inline-token-consumers.health"
    local planResponse
    local syncResult
    local responseMode=valid

    subscriptionRemoteControlToken() {
        return 96
    }
    subscriptionRemoteSourceSelfReference() {
        return 1
    }
    subscriptionRemoteControlHealth() {
        printf 'health\n' >>"${healthLog}"
        printf '{"ok":true}\n'
    }
    subscriptionRemoteControlSources() {
        printf '[%s]\n' "${remoteSourceJson}"
    }
    subscriptionRemoteDesiredUsersBySource() {
        printf '%s\n' "${desiredUsersBySourceJson}"
    }
    subscriptionRemoteControlRequest() {
        local sourceJson=$1
        local endpoint=$2
        local payload=$3
        [[ "${endpoint}" == "sync" ]]
        jq -e 'keys == ["desired_users", "dry_run"] and (.desired_users | length) == 1 and (.desired_users[0] | keys == ["id", "uuid"])' <<<"${payload}" >/dev/null
        printf '%s\n' "${payload}" >>"${requestPayloadLog}"
        printf '%s\t%s\n' "$(jq -r '.id' <<<"${sourceJson}")" "${endpoint}" >>"${statusLog}"
        case "${responseMode}" in
        missing-changed) jq -cn --argjson dryRun "$(jq -r '.dry_run' <<<"${payload}")" '{ok:true,dry_run:$dryRun,plan:{create:[],remove:[]}}' ;;
        missing-plan) jq -cn --argjson dryRun "$(jq -r '.dry_run' <<<"${payload}")" '{ok:true,dry_run:$dryRun,changed:false}' ;;
        wrong-dry-run) jq -cn --argjson dryRun "$(jq -r '.dry_run' <<<"${payload}")" '{ok:true,dry_run:($dryRun | not),changed:false,plan:{create:[],remove:[]}}' ;;
        *) jq -cn --argjson dryRun "$(jq -r '.dry_run' <<<"${payload}")" '{ok:true,dry_run:$dryRun,changed:false,plan:{create:[],remove:[]}}' ;;
        esac
    }
    setSubscriptionSourceSyncStatus() {
        printf 'status\t%s\t%s\n' "$1" "$2" >>"${statusLog}"
    }
    setSubscriptionSourceSyncFailure() {
        printf 'failure\t%s\t%s\t%s\n' "$1" "$2" "$3" >>"${statusLog}"
    }
    activeSubscriptionGroupId() {
        printf 'default\n'
    }

    planResponse=$(subscriptionRemoteSyncPlanForSource "${remoteSourceJson}" "${desiredUsersBySourceJson}" 2>/dev/null || true)
    [[ -n "${planResponse}" ]] || return 1
    planResponse=$(jq -c . <<<"${planResponse}") || return 1
    jq -e '.source_id == "edge-remote" and .status == "success" and .dry_run == true and .request.dry_run == true and (.request | has("source_id") | not) and .request.desired_users[0].id == "team-a" and .request.desired_users[0].uuid == "11111111-1111-1111-1111-111111111111" and (.request | has("include_subscriptions") | not) and .response.ok == true' <<<"${planResponse}" >/dev/null || return 1

    for responseMode in missing-changed missing-plan wrong-dry-run; do
        planResponse=$(subscriptionRemoteSyncPlanForSource "${remoteSourceJson}" "${desiredUsersBySourceJson}" 2>/dev/null || true)
        jq -e '.status == "remote_error" and .error_detail.type == "invalid_response"' <<<"${planResponse}" >/dev/null || return 1
    done
    responseMode=valid

    syncResult=$(runSubscriptionRemoteSync 2>/dev/null || true)
    [[ -n "${syncResult}" ]] || return 1
    syncResult=$(jq -c . <<<"${syncResult}") || return 1
    jq -e '.failures == ["远程服务器源 edge-remote 未返回完整订阅快照"] and .snapshots["edge-remote"] == null' <<<"${syncResult}" >/dev/null || return 1
    [[ -f "${requestPayloadLog}" ]] || return 1
    [[ -f "${statusLog}" ]] || return 1
    jq -s -e '
      length == 5 and
      .[0].dry_run == true and .[4].dry_run == false and
      all(.[];
        (. | has("source_id") | not) and
        (. | has("include_subscriptions") | not) and
        .desired_users[0].id == "team-a" and
        .desired_users[0].uuid == "11111111-1111-1111-1111-111111111111"
      )
    ' "${requestPayloadLog}" >/dev/null || return 1
    grep -qx $'edge-remote\tsync' "${statusLog}" || return 1
    grep -Fqx $'failure\tedge-remote\tinvalid_response\t未返回完整订阅快照' "${statusLog}" || return 1
    [[ ! -e "${healthLog}" ]] || return 1
    ! grep -q '^status	' "${statusLog}" || return 1
)

runRemoteControlTrafficContractRegression() (
    local source='{"id":"edge-remote","name":"Edge Remote","control_token":"token","scheme":"wireguard","transport":"wireguard","host":"10.77.0.2","port":39778}'
    local responseMode=valid
    local result

    subscriptionRemoteSourceSelfReference() { return 1; }
    subscriptionRemoteControlRequest() {
        [[ "$2" == "traffic" && "$3" == '{}' ]] || return 1
        case "${responseMode}" in
        valid) printf '%s\n' '{"ok":true,"items":[{"account":"admin","upload":1,"download":2},{"account":"sub_team_a","upload":3,"download":4}]}' ;;
        duplicate) printf '%s\n' '{"ok":true,"items":[{"account":"admin","upload":1,"download":2},{"account":"admin","upload":3,"download":4}]}' ;;
        legacy) printf '%s\n' '{"ok":false,"error":"unknown_endpoint","error_detail":{"type":"unknown_endpoint","message":"未知控制端点"}}' ;;
        esac
    }

    result=$(subscriptionRemoteTrafficForSource "${source}")
    jq -e '.source_id == "edge-remote" and .status == "success" and .response.items[1].account == "sub_team_a"' <<<"${result}" >/dev/null
    responseMode=duplicate
    result=$(subscriptionRemoteTrafficForSource "${source}")
    jq -e '.status == "remote_error" and .error_detail.type == "invalid_response"' <<<"${result}" >/dev/null
    responseMode=legacy
    result=$(subscriptionRemoteTrafficForSource "${source}")
    jq -e '.status == "remote_error" and .error_detail.type == "remote_error" and .error_detail.message == "未知控制端点"' <<<"${result}" >/dev/null
)

runRemoteControlInlineSyncRunnerRegression() (
    local remoteSourceJson='{"id":"edge-remote","name":"Edge Remote","control_token":"token","scheme":"wireguard","transport":"wireguard","host":"10.77.0.2","port":39778}'
    local desiredUsersBySourceJson='{"edge-remote":[{"id":"team-a","name":"Team A","uuid":"11111111-1111-1111-1111-111111111111","traffic_limit_gb":1,"account":"sub_team_a"}]}'
    local statusLog="${TMP_DIR}/remote-control-inline-sync-runner.status"
    local sourceResultLog="${TMP_DIR}/remote-control-inline-sync-runner.calls"
    local syncResult
    local snapshotMode=valid

    : >"${sourceResultLog}"

    subscriptionRemoteControlSources() {
        printf '[%s]\n' "${remoteSourceJson}"
    }
    subscriptionRemoteDesiredUsersBySource() {
        printf '%s\n' "${desiredUsersBySourceJson}"
    }
    subscriptionRemoteControlPayload() {
        return 96
    }
    subscriptionRemoteControlRequest() {
        return 97
    }
    subscriptionRemoteSyncPlanForSource() {
        local sourceJson=$1
        local desiredUsersBySource=$2
        local dryRun=${3:-true}
        printf '1\n' >>"${sourceResultLog}"
        [[ "$(jq -r '.id' <<<"${sourceJson}")" == "edge-remote" ]] || return 1
        [[ "${dryRun}" == "false" ]] || return 1
        jq -e '.["edge-remote"][0].account == "sub_team_a"' <<<"${desiredUsersBySource}" >/dev/null || return 1
        if [[ "${snapshotMode}" == "missing" ]]; then
            jq -n \
                --argjson request '{"source_id":"edge-remote","dry_run":false,"desired_users":[{"id":"team-a","account":"sub_team_a"}]}' \
                --argjson response '{"ok":true,"dry_run":false,"changed":false,"plan":{"create":[],"remove":[]},"subscriptions":{}}' \
                '{source_id:"edge-remote", status:"success", dry_run:false, request:$request, response:$response}'
        else
            jq -n \
                --argjson request '{"source_id":"edge-remote","dry_run":false,"desired_users":[{"id":"team-a","account":"sub_team_a"}]}' \
                --argjson response '{"ok":true,"dry_run":false,"changed":false,"plan":{"create":[],"remove":[]},"subscriptions":{"sub_team_a":{"default":"dmxlc3M6Ly9zbmFwc2hvdA==","clash_meta":"name: sub_team_a","sing_box":[]}}}' \
                '{source_id:"edge-remote", status:"success", dry_run:false, request:$request, response:$response}'
        fi
    }
    setSubscriptionSourceSyncStatus() {
        printf 'status\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"${statusLog}"
    }
    setSubscriptionSourceSyncFailure() {
        printf 'failure\t%s\t%s\t%s\n' "$1" "$2" "$3" >>"${statusLog}"
    }

    syncResult=$(runSubscriptionRemoteSync 2>/dev/null || true)
    [[ -n "${syncResult}" ]] || return 1
    syncResult=$(jq -c . <<<"${syncResult}") || return 1
    jq -e '.failures == [] and .snapshots["edge-remote"].sub_team_a.default == "dmxlc3M6Ly9zbmFwc2hvdA=="' <<<"${syncResult}" >/dev/null || return 1
    [[ "$(wc -l <"${sourceResultLog}")" == "1" ]] || return 1
    [[ -f "${statusLog}" ]] || return 1
    grep -Fqx $'status\tedge-remote\tsuccess\tfalse\t{"create":[],"remove":[]}' "${statusLog}" || return 1
    ! grep -q '^failure	' "${statusLog}" || return 1

    snapshotMode=missing
    : >"${statusLog}"
    syncResult=$(runSubscriptionRemoteSync 2>/dev/null || true)
    [[ -n "${syncResult}" ]] || return 1
    jq -e '.failures == ["远程服务器源 edge-remote 返回的订阅快照格式无效"] and .snapshots["edge-remote"] == null' <<<"${syncResult}" >/dev/null || return 1
    grep -Fqx $'failure\tedge-remote\tinvalid_response\t返回的订阅快照格式无效' "${statusLog}" || return 1
    ! grep -q '^status	' "${statusLog}" || return 1
    snapshotMode=valid

    setSubscriptionSourceSyncStatus() {
        return 71
    }
    syncResult=$(runSubscriptionRemoteSync 2>/dev/null) || return 1
    syncResult=$(jq -c . <<<"${syncResult}") || return 1
    jq -e '.failures == ["远程服务器源 edge-remote 同步状态写入失败"] and .snapshots["edge-remote"].sub_team_a.default == "dmxlc3M6Ly9zbmFwc2hvdA=="' <<<"${syncResult}" >/dev/null
)

runRemoteControlInlineSyncParallelRunnerRegression() (
    local remoteSourcesJson='[{"id":"edge-slow","name":"Edge Slow","control_token":"token"},{"id":"edge-broken","name":"Edge Broken","control_token":"token"}]'
    local desiredUsersBySourceJson='{"edge-slow":[],"edge-broken":[]}'
    local statusLog="${TMP_DIR}/remote-control-inline-sync-parallel-runner.status"
    local callLog="${TMP_DIR}/remote-control-inline-sync-parallel-runner.calls"
    local brokenStarted="${TMP_DIR}/remote-control-inline-sync-parallel-runner.broken-started"
    local syncResult

    : >"${callLog}"

    subscriptionRemoteControlSources() {
        printf '%s\n' "${remoteSourcesJson}"
    }
    subscriptionRemoteDesiredUsersBySource() {
        printf '%s\n' "${desiredUsersBySourceJson}"
    }
    subscriptionRemoteSyncPlanForSource() {
        local sourceJson=$1
        local sourceId
        sourceId=$(jq -r '.id' <<<"${sourceJson}") || return 1
        printf '%s-start\n' "${sourceId}" >>"${callLog}"
        case "${sourceId}" in
        edge-slow)
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${brokenStarted}" ]] && break
                sleep 0.01
            done
            [[ -f "${brokenStarted}" ]] || printf 'edge-broken-not-parallel\n' >>"${callLog}"
            jq -n \
                --argjson request '{"source_id":"edge-slow","dry_run":false,"desired_users":[]}' \
                --argjson response '{"ok":true,"dry_run":false,"changed":false,"plan":{"create":[],"remove":[]},"subscriptions":{}}' \
                '{source_id:"edge-slow", status:"success", dry_run:false, request:$request, response:$response}'
            ;;
        edge-broken)
            : >"${brokenStarted}"
            printf 'broken-sync-json\n'
            ;;
        esac
    }
    setSubscriptionSourceSyncStatus() {
        printf 'status\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"${statusLog}"
    }
    setSubscriptionSourceSyncFailure() {
        printf 'failure\t%s\t%s\t%s\n' "$1" "$2" "$3" >>"${statusLog}"
    }

    syncResult=$(runSubscriptionRemoteSync 2>/dev/null || true)
    [[ -n "${syncResult}" ]] || return 1
    syncResult=$(jq -c . <<<"${syncResult}") || return 1
    jq -e '.failures | length == 1 and (.[0] | contains("edge-broken"))' <<<"${syncResult}" >/dev/null || return 1
    jq -e '.snapshots == {"edge-slow":{},"edge-broken":null}' <<<"${syncResult}" >/dev/null || return 1
    grep -qx 'edge-slow-start' "${callLog}" || return 1
    grep -qx 'edge-broken-start' "${callLog}" || return 1
    ! grep -qx 'edge-broken-not-parallel' "${callLog}" || return 1
    grep -Fqx $'status\tedge-slow\tsuccess\tfalse\t{"create":[],"remove":[]}' "${statusLog}" || return 1
    grep -q $'^failure\tedge-broken\tinternal_error\t' "${statusLog}" || return 1
)

runRemoteControlHandleInlineHelpersRegression() (
    local controlRoot="${TMP_DIR}/remote-control-handle-inline-helpers"
    local configDir="${controlRoot}/config"
    local desiredBySource
    local credentialPlan
    local healthResponse
    local syncResponse
    local syncSnapshotResponse
    local emptySnapshotResponse
    local invalidPayload
    local invalidPayloadResponse
    local invalidPayloadStatus
    local invalidStateResponse
    local invalidStateStatus
    local syncSnapshotFailureStatus
    local subscribeResponse
    local subscribeStatus
    local syncLockMarker="${controlRoot}/sync-lock-observed"
    local snapshotLog="${controlRoot}/snapshot.log"
    local expectedDefault
    local expectedDefaultB

    mkdir -p "${controlRoot}/state"
    export PADM_SUBSCRIPTION_GROUPS_DIR="${controlRoot}/state"
    mkdir -p "$(dirname "$(subscriptionControlTokenFile)")"
    printf 'test-token\n' >"$(subscriptionControlTokenFile)"

    getScriptVersion() {
        printf 'test\n'
    }
    subscriptionControlAuthorized() {
        return 1
    }
    subscriptionControlValidateSyncPayload() {
        return 1
    }
    eval "$(declare -f subscriptionSyncPlanFromDesiredUsers | sed '1s/^subscriptionSyncPlanFromDesiredUsers/originalSubscriptionSyncPlanFromDesiredUsers/')"
    subscriptionSyncPlanFromDesiredUsers() {
        [[ "${SUBSCRIPTION_GROUPS_LOCK_HELD:-}" == "1" ]] && : >"${syncLockMarker}"
        printf '{"create":[],"remove":[]}'
    }
    healthResponse=$(handleSubscriptionControl health test-token | jq -c .)
    [[ "${healthResponse}" == *'"ok":true'*'"version":"test"'*'"capabilities":["health","sync","traffic"]'* ]]

    jq '.version = 1' "$(subscriptionGroupsFile)" >"$(subscriptionGroupsFile).tmp"
    mv "$(subscriptionGroupsFile).tmp" "$(subscriptionGroupsFile)"
    set +e
    invalidStateResponse=$(handleSubscriptionControl health test-token)
    invalidStateStatus=$?
    set -e
    [[ "${invalidStateStatus}" -ne 0 ]]
    jq -e '.ok == false and .error == "invalid_state" and .error_detail.type == "invalid_state"' <<<"${invalidStateResponse}" >/dev/null
    writeDefaultSubscriptionGroupsState "$(subscriptionGroupsFile)"

    showAccounts() {
        printf 'show\n' >>"${snapshotLog}"
        mkdir -p "${PADM_SUBSCRIBE_LOCAL_DIR}/default" "${PADM_SUBSCRIBE_LOCAL_DIR}/clashMeta" "${PADM_SUBSCRIBE_LOCAL_DIR}/sing-box"
        printf 'vless://snapshot\n' >"${PADM_SUBSCRIBE_LOCAL_DIR}/default/sub_team_a"
        printf 'name: sub_team_a\n' >"${PADM_SUBSCRIBE_LOCAL_DIR}/clashMeta/sub_team_a"
        printf '[{"tag":"sub_team_a"}]\n' >"${PADM_SUBSCRIBE_LOCAL_DIR}/sing-box/sub_team_a"
        printf 'trojan://snapshot-b\n' >"${PADM_SUBSCRIBE_LOCAL_DIR}/default/sub_team_b"
        printf 'name: sub_team_b\n' >"${PADM_SUBSCRIBE_LOCAL_DIR}/clashMeta/sub_team_b"
        printf '[{"tag":"sub_team_b"}]\n' >"${PADM_SUBSCRIBE_LOCAL_DIR}/sing-box/sub_team_b"
    }

    syncResponse=$(handleSubscriptionControl sync test-token '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}' | jq -c .)
    [[ "${syncResponse}" == *'"ok":true'*'"dry_run":false'*'"changed":true'* ]]
    [[ "${syncResponse}" == *'"create":[]'*'"remove":[]'* ]]
    jq -e '.ok == true and (.subscriptions | has("sub_team_a"))' <<<"${syncResponse}" >/dev/null
    [[ -e "${syncLockMarker}" ]]

    expectedDefault=$(printf 'vless://snapshot\n' | base64 | tr -d '\n')
    expectedDefaultB=$(printf 'trojan://snapshot-b\n' | base64 | tr -d '\n')
    syncSnapshotResponse=$(handleSubscriptionControl sync test-token '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"},{"id":"team-b","uuid":"22222222-2222-2222-2222-222222222222"}],"dry_run":false}' | jq -c .)
    jq -e --arg expectedDefault "${expectedDefault}" --arg expectedDefaultB "${expectedDefaultB}" '
      .ok == true and .dry_run == false and .changed == true and
      .subscriptions.sub_team_a.default == $expectedDefault and
      .subscriptions.sub_team_a.clash_meta == "name: sub_team_a" and
      .subscriptions.sub_team_a.sing_box == [{"tag":"sub_team_a"}] and
      .subscriptions.sub_team_b.default == $expectedDefaultB and
      .subscriptions.sub_team_b.clash_meta == "name: sub_team_b" and
      .subscriptions.sub_team_b.sing_box == [{"tag":"sub_team_b"}]
    ' <<<"${syncSnapshotResponse}" >/dev/null
    [[ "$(wc -l <"${snapshotLog}" | tr -d ' ')" == "2" ]]

    emptySnapshotResponse=$(handleSubscriptionControl sync test-token '{"desired_users":[],"dry_run":false}' | jq -c .)
    jq -e '.ok == true and .subscriptions == {}' <<<"${emptySnapshotResponse}" >/dev/null
    [[ "$(wc -l <"${snapshotLog}" | tr -d ' ')" == "2" ]]

    for invalidPayload in \
        '{"desired_users":[]}' \
        '{"desired_users":[],"dry_run":false,"include_subscriptions":true}' \
        '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111","name":"Team A"}],"dry_run":false}'; do
        set +e
        invalidPayloadResponse=$(handleSubscriptionControl sync test-token "${invalidPayload}")
        invalidPayloadStatus=$?
        set -e
        [[ "${invalidPayloadStatus}" -ne 0 ]]
        jq -e '.ok == false and .error == "invalid_payload"' <<<"${invalidPayloadResponse}" >/dev/null
    done

    set +e
    subscribeResponse=$(handleSubscriptionControl subscribe test-token '{"account":"team_a"}')
    subscribeStatus=$?
    set -e
    [[ "${subscribeStatus}" -ne 0 ]]
    jq -e '.ok == false and .error == "unknown_endpoint"' <<<"${subscribeResponse}" >/dev/null

    showAccounts() {
        printf 'vless://secret-credential\n'
        printf 'private diagnostic\n' >&2
        return 1
    }
    set +e
    syncSnapshotResponse=$(handleSubscriptionControl sync test-token '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}')
    syncSnapshotFailureStatus=$?
    set -e
    [[ "${syncSnapshotFailureStatus}" -ne 0 ]]
    jq -e '.ok == false and .changed == true and .error == "generation_failed" and .error_detail.type == "generation_failed" and has("subscriptions") == false' <<<"${syncSnapshotResponse}" >/dev/null
    [[ "${syncSnapshotResponse}" != *secret-credential* && "${syncSnapshotResponse}" != *'private diagnostic'* ]]

    mkdir -p "${configDir}"
    configPath="${configDir}/"
    singBoxConfigPath=
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge","name":"Edge","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"10.77.0.2","port":39778,"enabled":true,"sync_status":"pending"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["edge"],"traffic_limit_gb":0,"token":"","uuid":"22222222-2222-2222-2222-222222222222"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    desiredBySource=$(subscriptionRemoteDesiredUsersBySource '[{"id":"edge"}]')
    jq -e '.["edge"][0].uuid == "22222222-2222-2222-2222-222222222222"' <<<"${desiredBySource}" >/dev/null
    subscriptionActiveGroupRead -e '.user_groups[0].uuid == "22222222-2222-2222-2222-222222222222"' >/dev/null

    cat >"${configDir}/01_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_team_a-VLESS_WS","id":"33333333-3333-3333-3333-333333333333"}]}}]}
JSON
    credentialPlan=$(originalSubscriptionSyncPlanFromDesiredUsers '[{"id":"team-a","uuid":"22222222-2222-2222-2222-222222222222"}]')
    jq -e '.create == ["sub_team_a"] and .remove == ["sub_team_a"]' <<<"${credentialPlan}" >/dev/null
)

runRemoteControlServerRefreshRegression() (
    local refreshMode=${1:-full}
    local lightMode=${2:-all}
    local refreshTmpDir="${TMP_DIR}/remote-control-server-refresh-${refreshMode}-${lightMode}-${BASHPID:-$$}"
    local TMP_DIR="${refreshTmpDir}"
    local TMPDIR="${TMP_DIR}"
    local PADM_SUBSCRIPTION_GROUPS_DIR="${TMP_DIR}/subscribe_groups"
    local PADM_SUBSCRIBE_LOCAL_DIR="${TMP_DIR}/subscribe_local"
    local PADM_SUBSCRIBE_DIR="${TMP_DIR}/subscribe"
    local lightModeTag=${lightMode}
    local runLightSections=true
    local runDeepSections=true
    local subscribeCalls=0
    local subscribeArgs=
    local reconcileCalls=0
    local reloadCalls=0
    local responseFile="${TMP_DIR}/remote-control-server-refresh-${refreshMode}-${lightModeTag}.json"
    local oldConfigPath="${configPath:-}"
    local oldSingBoxConfigPath="${singBoxConfigPath:-}"
    local rollbackRoot="${TMP_DIR}/remote-control-rollback"
    local rollbackStateBefore
    local rollbackFirstBefore
    local rollbackSecondBefore
    local oldCoreInstallType="${coreInstallType:-}"
    local setUsersCalls=0
    local rollbackExpectedFile="${TMP_DIR}/remote-control-rollback-expected.json"
    local lightweightBackupRoot="${TMP_DIR}/remote-control-lightweight-backups-${refreshMode}-${lightModeTag}"
    local lightweightConfigIndex=0
    local lightweightOutputIndex=0
    local controlApplyCaptureFile="${TMP_DIR}/remote-control-apply-response-${refreshMode}-${lightModeTag}.json"

    mkdir -p "${TMP_DIR}" "${PADM_SUBSCRIPTION_GROUPS_DIR}" "${PADM_SUBSCRIBE_LOCAL_DIR}" "${PADM_SUBSCRIBE_DIR}"
    export TMPDIR PADM_SUBSCRIPTION_GROUPS_DIR PADM_SUBSCRIBE_LOCAL_DIR PADM_SUBSCRIBE_DIR

    remoteControlLightModeSelected() {
        local mode
        [[ "${refreshMode}" == "full" ]] && return 0
        [[ "${refreshMode}" == "light" ]] || return 1
        for mode; do
            [[ "${lightMode}" == "${mode}" ]] && return 0
        done
        return 1
    }

    case "${refreshMode}" in
    full)
        ;;
    deep)
        runLightSections=false
        ;;
    light)
        runDeepSections=false
        case "${lightMode}" in
        all | apply | apply-basic | apply-prepare | apply-failure | restore | reconcile)
            ;;
        *)
            printf 'unknown remote-control server refresh light mode: %s\n' "${lightMode}" >&2
            return 2
            ;;
        esac
        ;;
    *)
        printf 'unknown remote-control server refresh mode: %s\n' "${refreshMode}" >&2
        return 2
        ;;
    esac

    eval "$(declare -f subscriptionControlApplyAccountPlan | sed '1s/^subscriptionControlApplyAccountPlan/originalSubscriptionControlApplyAccountPlan/')"
    eval "$(declare -f subscriptionSyncSetUsersInFile | sed '1s/^subscriptionSyncSetUsersInFile/originalSubscriptionSyncSetUsersInFile/')"
    eval "$(declare -f subscriptionSyncPlanFromAccounts | sed '1s/^subscriptionSyncPlanFromAccounts/originalSubscriptionSyncPlanFromAccounts/')"
    eval "$(declare -f subscriptionSyncCreateConfigBackups | sed '1s/^subscriptionSyncCreateConfigBackups/originalSubscriptionSyncCreateConfigBackups/')"
    eval "$(declare -f subscriptionSyncCreateSubscribeOutputBackups | sed '1s/^subscriptionSyncCreateSubscribeOutputBackups/originalSubscriptionSyncCreateSubscribeOutputBackups/')"
    eval "$(declare -f subscriptionSyncRestoreConfigBackups | sed '1s/^subscriptionSyncRestoreConfigBackups/originalSubscriptionSyncRestoreConfigBackups/')"
    eval "$(declare -f subscriptionSyncRestoreSubscribeOutputBackups | sed '1s/^subscriptionSyncRestoreSubscribeOutputBackups/originalSubscriptionSyncRestoreSubscribeOutputBackups/')"
    eval "$(declare -f subscriptionGroupsStateRead | sed '1s/^subscriptionGroupsStateRead/originalSubscriptionGroupsStateRead/')"
    eval "$(declare -f subscriptionGroupsStateWrite | sed '1s/^subscriptionGroupsStateWrite/originalSubscriptionGroupsStateWrite/')"
    eval "$(declare -f subscribe | sed '1s/^subscribe/originalSubscribe/')"

    useLightweightSyncBackups() {
        subscriptionSyncCreateConfigBackups() {
            local resultVar=$1
            local backupDir
            printf -v backupDir '%s/config-%02d' "${lightweightBackupRoot}" "${lightweightConfigIndex}"
            lightweightConfigIndex=$((lightweightConfigIndex + 1))
            mkdir -p "${backupDir}" || return 1
            printf -v "${resultVar}" '%s' "${backupDir}"
        }
        subscriptionSyncCreateSubscribeOutputBackups() {
            local resultVar=$1
            local backupDir
            printf -v backupDir '%s/output-%02d' "${lightweightBackupRoot}" "${lightweightOutputIndex}"
            lightweightOutputIndex=$((lightweightOutputIndex + 1))
            mkdir -p "${backupDir}" || return 1
            printf -v "${resultVar}" '%s' "${backupDir}"
        }
        subscriptionSyncRestoreConfigBackups() {
            return 0
        }
        subscriptionSyncRestoreSubscribeOutputBackups() {
            return 0
        }
    }

    useRealSyncBackups() {
        subscriptionSyncCreateConfigBackups() {
            originalSubscriptionSyncCreateConfigBackups "$@"
        }
        subscriptionSyncCreateSubscribeOutputBackups() {
            originalSubscriptionSyncCreateSubscribeOutputBackups "$@"
        }
        subscriptionSyncRestoreConfigBackups() {
            originalSubscriptionSyncRestoreConfigBackups "$@"
        }
        subscriptionSyncRestoreSubscribeOutputBackups() {
            originalSubscriptionSyncRestoreSubscribeOutputBackups "$@"
        }
    }

    defaultRemoteControlGroupsStateJson() {
        cat <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    }

    setVirtualSubscriptionGroupsState() {
        virtualGroupsState=$1
    }

    virtualSubscriptionGroupsStateRead() {
        jq "$@" <<<"${virtualGroupsState}"
    }

    virtualSubscriptionGroupsStateWrite() {
        local nextState
        nextState=$(jq "$@" <<<"${virtualGroupsState}") || return 1
        virtualGroupsState=${nextState}
    }

    useVirtualSubscriptionGroupsState() {
        subscriptionGroupsStateRead() {
            virtualSubscriptionGroupsStateRead "$@"
        }
        subscriptionGroupsStateWrite() {
            virtualSubscriptionGroupsStateWrite "$@"
        }
    }

    useRealSubscriptionGroupsState() {
        subscriptionGroupsStateRead() {
            originalSubscriptionGroupsStateRead "$@"
        }
        subscriptionGroupsStateWrite() {
            originalSubscriptionGroupsStateWrite "$@"
        }
    }

    resetVirtualSubscriptionGroupsState() {
        setVirtualSubscriptionGroupsState "$(defaultRemoteControlGroupsStateJson)"
    }

    setupLightweightControlApplyFixtures() {
        subscriptionControlRenderSubscribeAccounts() {
            printf '{}\n'
        }
        subscriptionSyncPlanFromAccounts() {
            printf '{"create":["sub_team_a"],"remove":[]}'
        }
        subscriptionControlApplyAccountPlan() {
            return 0
        }
        subscribe() {
            subscribeCalls=$((subscribeCalls + 1))
            subscribeArgs="$*"
        }
        subscriptionSyncReconcileLocalServices() {
            reconcileCalls=$((reconcileCalls + 1))
        }
    }

    reloadCore() {
        reloadCalls=$((reloadCalls + 1))
    }

    mkdir -p "${lightweightBackupRoot}"
    useLightweightSyncBackups
    useVirtualSubscriptionGroupsState
    resetVirtualSubscriptionGroupsState

    if [[ "${runLightSections}" == "true" ]]; then
        setupLightweightControlApplyFixtures

        responseHasErrorType() {
            local response=$1
            local errorName=$2
            jq -e --arg errorName "${errorName}" '.error == $errorName and .error_detail.type == $errorName' <<<"${response}" >/dev/null
        }

        responseHasPlanCreateEntry() {
            local response=$1
            local expected=$2
            jq -e --arg expected "${expected}" '.plan.create == [$expected]' <<<"${response}" >/dev/null
        }

        responseHasPlanRemoveEmpty() {
            local response=$1
            jq -e '.plan.remove == []' <<<"${response}" >/dev/null
        }

        responseHasChangedAndDryRun() {
            local response=$1
            local changed=$2
            local dryRun=$3
            jq -e --argjson changed "${changed}" --argjson dryRun "${dryRun}" '.changed == $changed and .dry_run == $dryRun' <<<"${response}" >/dev/null
        }

        responseHasApplySuccess() {
            local response=$1
            local changed=$2
            local dryRun=$3
            jq -e --argjson changed "${changed}" --argjson dryRun "${dryRun}" '.ok == true and .changed == $changed and .dry_run == $dryRun' <<<"${response}" >/dev/null
        }

        runControlApplyCapture() {
            local responseVar=$1
            local statusVar=$2
            local applyMode=$3
            local payload=$4
            local response=
            local commandStatus

            : >"${controlApplyCaptureFile}" || return 1
            set +e
            case "${applyMode}" in
            server)
                PADM_CONTROL_SERVER=1 subscriptionControlApplySync "${payload}" >"${controlApplyCaptureFile}"
                ;;
            local)
                PADM_CONTROL_SERVER= subscriptionControlApplySync "${payload}" >"${controlApplyCaptureFile}"
                ;;
            *)
                printf 'unknown remote control apply mode: %s\n' "${applyMode}" >&2
                return 2
                ;;
            esac
            commandStatus=$?
            set -e
            response=$(<"${controlApplyCaptureFile}")
            printf -v "${responseVar}" '%s' "${response}"
            printf -v "${statusVar}" '%s' "${commandStatus}"
        }

        if remoteControlLightModeSelected all apply apply-basic apply-prepare apply-failure; then
            if remoteControlLightModeSelected all apply apply-basic; then
                local invalidEmptyIdResponse invalidDuplicateResponse invalidUuidMissingResponse invalidUuidEmptyResponse invalidUuidResponse invalidUuidStringResponse
                local invalidEmptyIdStatus invalidDuplicateStatus invalidUuidMissingStatus invalidUuidEmptyStatus invalidUuidStatus invalidUuidStringStatus
                runControlApplyCapture invalidEmptyIdResponse invalidEmptyIdStatus local '{"desired_users":[{"id":"","uuid":""}]}'
                runControlApplyCapture invalidDuplicateResponse invalidDuplicateStatus local '{"desired_users":[{"id":"team-a"},{"id":"team-a"}]}'
                runControlApplyCapture invalidUuidMissingResponse invalidUuidMissingStatus local '{"desired_users":[{"id":"team-a"}]}'
                runControlApplyCapture invalidUuidEmptyResponse invalidUuidEmptyStatus local '{"desired_users":[{"id":"team-a","uuid":""}]}'
                runControlApplyCapture invalidUuidResponse invalidUuidStatus local '{"desired_users":[{"id":"team-a","uuid":123}]}'
                runControlApplyCapture invalidUuidStringResponse invalidUuidStringStatus local '{"desired_users":[{"id":"team-a","uuid":"not-a-uuid"}]}'
                [[ "${invalidEmptyIdStatus}" -ne 0 ]]
                [[ "${invalidDuplicateStatus}" -ne 0 ]]
                [[ "${invalidUuidMissingStatus}" -ne 0 ]]
                [[ "${invalidUuidEmptyStatus}" -ne 0 ]]
                [[ "${invalidUuidStatus}" -ne 0 ]]
                [[ "${invalidUuidStringStatus}" -ne 0 ]]
                responseHasErrorType "${invalidEmptyIdResponse}" invalid_payload
                responseHasErrorType "${invalidDuplicateResponse}" invalid_payload
                responseHasErrorType "${invalidUuidMissingResponse}" invalid_payload
                responseHasErrorType "${invalidUuidEmptyResponse}" invalid_payload
                responseHasErrorType "${invalidUuidResponse}" invalid_payload
                responseHasErrorType "${invalidUuidStringResponse}" invalid_payload

                (
                    local controlledSkipResponse controlledSkipStatus
                    resetVirtualSubscriptionGroupsState
                    subscribeCalls=0
                    reloadCalls=0
                    subscribeArgs=
                    subscriptionControlRefreshPublishedSubscriptions() {
                        return 98
                    }
                    subscriptionWireGuardRole() {
                        printf 'controlled\n'
                    }
                    readNginxSubscribe() {
                        subscribePort=
                        subscribeDomain=main.example.com
                        subscribeType=https
                    }
                    subscribe() {
                        subscribeCalls=$((subscribeCalls + 1))
                        return 99
                    }
                    runControlApplyCapture controlledSkipResponse controlledSkipStatus server '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}'
                    [[ "${controlledSkipStatus}" -eq 0 ]]
                    responseHasApplySuccess "${controlledSkipResponse}" true false
                    [[ "${subscribeCalls}" == "0" ]]
                    [[ "${reloadCalls}" == "1" ]]
                )

                subscriptionSyncPlanFromAccounts() {
                    printf '{"create":["sub_team_a"],"remove":[]}'
                }
                local remoteSuccessResponse localSuccessResponse
                local remoteSuccessStatus localSuccessStatus
                reloadCalls=0
                runControlApplyCapture remoteSuccessResponse remoteSuccessStatus server '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}'
                [[ "${remoteSuccessStatus}" -eq 0 ]]
                responseHasApplySuccess "${remoteSuccessResponse}" true false
                [[ "${reloadCalls}" == "1" ]]
                [[ "${subscribeCalls}" == "0" ]]
                [[ "${reconcileCalls}" == "0" ]]

                runControlApplyCapture localSuccessResponse localSuccessStatus local '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}'
                [[ "${localSuccessStatus}" -eq 0 ]]
                responseHasApplySuccess "${localSuccessResponse}" true false
                [[ "${subscribeCalls}" == "0" ]]
                [[ "${reconcileCalls}" == "1" ]]

                (
                    setVirtualSubscriptionGroupsState '{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["main"],"traffic_limit_gb":5,"token":"","uuid":"11111111-1111-1111-1111-111111111111"},{"id":"local-only","name":"Local Only","enabled":true,"allowed_sources":["main"],"traffic_limit_gb":0,"token":"","uuid":"22222222-2222-2222-2222-222222222222"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{"team-a":{"upload":1,"download":2,"sources":{}},"local-only":{"upload":3,"download":4,"sources":{}}},"sources":{}}}]}'
                    subscriptionSyncApplyAccountPlanTransaction() { return 0; }
                    originalSubscriptionControlApplyAccountPlan '{"create":[],"remove":["sub_team_a"]}' '[]'
                    jq -e '
                      (.groups[0].user_groups | length) == 0 and
                      (.groups[0].traffic.user_groups | has("team-a") | not) and
                      (.groups[0].traffic.user_groups | has("local-only") | not)
                    ' <<<"${virtualGroupsState}" >/dev/null
                )

                (
                    setVirtualSubscriptionGroupsState '{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[{"id":"team-a","name":"Preserved Name","enabled":true,"allowed_sources":["main"],"traffic_limit_gb":5,"token":"","uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}'
                    subscriptionSyncApplyAccountPlanTransaction() { return 0; }
                    originalSubscriptionControlApplyAccountPlan \
                        '{"create":["sub_team_a"],"remove":["sub_team_a"]}' \
                        '[{"id":"team-a","uuid":"33333333-3333-3333-3333-333333333333"}]'
                    jq -e '
                      .groups[0].user_groups == [{
                        "id":"team-a",
                        "name":"Preserved Name",
                        "enabled":true,
                        "allowed_sources":["main"],
                        "traffic_limit_gb":5,
                        "token":"",
                        "uuid":"33333333-3333-3333-3333-333333333333"
                      }]
                    ' <<<"${virtualGroupsState}" >/dev/null
                )

                (
                    setVirtualSubscriptionGroupsState '{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[{"id":"team-a","name":"Preserved Name","enabled":false,"allowed_sources":["main"],"traffic_limit_gb":5,"token":"","uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}'
                    subscriptionSyncApplyAccountPlanTransaction() { return 0; }
                    originalSubscriptionControlApplyAccountPlan \
                        '{"create":[],"remove":[]}' \
                        '[{"id":"team-a","uuid":"33333333-3333-3333-3333-333333333333"}]'
                    jq -e '
                      .groups[0].user_groups == [{
                        "id":"team-a",
                        "name":"Preserved Name",
                        "enabled":true,
                        "allowed_sources":["main"],
                        "traffic_limit_gb":5,
                        "token":"",
                        "uuid":"33333333-3333-3333-3333-333333333333"
                      }]
                    ' <<<"${virtualGroupsState}" >/dev/null
                )
            fi

            if remoteControlLightModeSelected all apply apply-prepare; then
                (
                    local prepareResponse
                    local prepareStatus
                    resetVirtualSubscriptionGroupsState
                    subscriptionSyncCreateConfigBackups() {
                        return 1
                    }
                    runControlApplyCapture prepareResponse prepareStatus server '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}'
                    [[ "${prepareStatus}" -ne 0 ]]
                    responseHasErrorType "${prepareResponse}" prepare_failed
                    responseHasChangedAndDryRun "${prepareResponse}" false false
                    [[ "${prepareResponse}" == *'配置备份失败'* ]]
                    responseHasPlanCreateEntry "${prepareResponse}" sub_team_a
                    responseHasPlanRemoveEmpty "${prepareResponse}"
                )

                (
                    local prepareRoot="${TMP_DIR}/remote-control-prepare-output-failure"
                    local prepareResponse
                    local expectedBackupDir="${prepareRoot}/created-backup"
                    local prepareStatus
                    resetVirtualSubscriptionGroupsState
                    subscriptionControlPrepareSyncFailure() {
                        return 97
                    }
                    subscriptionSyncCreateConfigBackups() {
                        local resultVar=$1
                        local backupPath="${expectedBackupDir}"
                        mkdir -p "${backupPath}" || return 1
                        printf -v "${resultVar}" '%s' "${backupPath}"
                    }
                    subscriptionSyncCreateSubscribeOutputBackups() {
                        return 1
                    }
                    runControlApplyCapture prepareResponse prepareStatus server '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}'
                    [[ "${prepareStatus}" -ne 0 ]]
                    responseHasErrorType "${prepareResponse}" prepare_failed
                    responseHasChangedAndDryRun "${prepareResponse}" false false
                    [[ "${prepareResponse}" == *'订阅输出备份失败'* ]]
                    responseHasPlanCreateEntry "${prepareResponse}" sub_team_a
                    responseHasPlanRemoveEmpty "${prepareResponse}"
                    [[ ! -e "${expectedBackupDir}" ]]
                )
            fi

            if remoteControlLightModeSelected all apply apply-failure; then
                subscribe() {
                    subscribeCalls=$((subscribeCalls + 1))
                    subscribeArgs="$*"
                    return 1
                }
                local refreshFailureResponse applyFailureResponse
                local refreshStatus applyStatus
                runControlApplyCapture refreshFailureResponse refreshStatus server '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}'
                [[ "${refreshStatus}" -eq 0 ]]
                responseHasApplySuccess "${refreshFailureResponse}" true false
                [[ "${subscribeCalls}" == "0" ]]

                subscriptionControlApplyAccountPlan() {
                    return 1
                }
                runControlApplyCapture applyFailureResponse applyStatus server '{"desired_users":[{"id":"team-b","uuid":"22222222-2222-2222-2222-222222222222"}],"dry_run":false}'
                [[ "${applyStatus}" -ne 0 ]]
                responseHasErrorType "${applyFailureResponse}" apply_plan_failed
            fi
        fi

        if remoteControlLightModeSelected all restore; then
            (
                local restoreFailureStateWriteCalls=0
                local restoreFailureResponse
                local restoreFailureStatus
                setVirtualSubscriptionGroupsState '{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":false,"allowed_sources":["*"],"traffic_limit_gb":0,"token":"","uuid":"00000000-0000-0000-0000-000000000000"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}'
                subscriptionSyncPlanFromAccounts() {
                    printf '{"create":["sub_team_a"],"remove":[]}'
                }
                subscriptionControlApplyAccountPlan() {
                    originalSubscriptionControlApplyAccountPlan "$@"
                }
                subscriptionSyncApplyAccountPlanTransaction() {
                    return 1
                }
                subscriptionGroupsStateWrite() {
                    restoreFailureStateWriteCalls=$((restoreFailureStateWriteCalls + 1))
                    if [[ "${restoreFailureStateWriteCalls}" == "2" ]]; then
                        return 1
                    fi
                    virtualSubscriptionGroupsStateWrite "$@"
                }
                runControlApplyCapture restoreFailureResponse restoreFailureStatus server '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}'
                [[ "${restoreFailureStatus}" -ne 0 ]]
                responseHasErrorType "${restoreFailureResponse}" apply_plan_failed
                [[ "${restoreFailureResponse}" == *'订阅状态恢复失败'* ]]
                jq -e '.groups[0].user_groups[0].enabled == true and .groups[0].user_groups[0].uuid == "11111111-1111-1111-1111-111111111111"' <<<"${virtualGroupsState}" >/dev/null
            )

            (
                local restoreOrderLog="${TMP_DIR}/remote-control-restore-order.log"
                local restoreOrderConfig="${TMP_DIR}/remote-control-restore-config"
                local restoreOrderOutput="${TMP_DIR}/remote-control-restore-output"
                local helperCalls=0
                mkdir -p "${restoreOrderConfig}" "${restoreOrderOutput}"
                subscriptionGroupsStateWrite() {
                    printf 'state\n' >>"${restoreOrderLog}"
                    return 0
                }
                subscriptionSyncRestoreConfigBackups() {
                    printf 'config\n' >>"${restoreOrderLog}"
                    return 1
                }
                subscriptionSyncRestoreSubscribeOutputBackups() {
                    printf 'output\n' >>"${restoreOrderLog}"
                    return 0
                }
                subscriptionSyncSetRestoreFailureDetail() {
                    local location=${3:-}
                    helperCalls=$((helperCalls + 1))
                    if [[ -n "${location}" ]]; then
                        command printf -v "$1" '%s' "${2}恢复失败，请手动检查${location}"
                    else
                        command printf -v "$1" '%s' "${2}恢复失败"
                    fi
                    [[ "$2" == "配置" ]]
                    [[ "${location}" == "备份目录: ${restoreOrderConfig}" ]]
                    return 0
                }
                SUBSCRIPTION_CONTROL_RESTORE_ERROR=
                rm -f "${restoreOrderLog}"
                set +e
                subscriptionControlRestoreAppliedPlan '{"version":2,"groups":[]}' "${restoreOrderConfig}" "${restoreOrderOutput}"
                local restoreOrderStatus=$?
                set -e
                [[ "${restoreOrderStatus}" -eq 1 ]]
                [[ "${helperCalls}" == "1" ]] || return 1
                grep -qx 'state' "${restoreOrderLog}"
                grep -qx 'config' "${restoreOrderLog}"
                grep -qx 'output' "${restoreOrderLog}"
                [[ "${SUBSCRIPTION_CONTROL_RESTORE_ERROR}" == "控制面同步失败后配置恢复失败，请手动检查备份目录: ${restoreOrderConfig}" ]]
            )

            (
                local restoreOrderLog="${TMP_DIR}/remote-control-restore-order-state.log"
                local restoreOrderConfig="${TMP_DIR}/remote-control-restore-config-state"
                local restoreOrderOutput="${TMP_DIR}/remote-control-restore-output-state"
                local helperCalls=0
                mkdir -p "${restoreOrderConfig}" "${restoreOrderOutput}"
                subscriptionGroupsStateWrite() {
                    printf 'state\n' >>"${restoreOrderLog}"
                    return 1
                }
                subscriptionSyncRestoreConfigBackups() {
                    printf 'config\n' >>"${restoreOrderLog}"
                    return 0
                }
                subscriptionSyncRestoreSubscribeOutputBackups() {
                    printf 'output\n' >>"${restoreOrderLog}"
                    return 0
                }
                subscriptionSyncSetRestoreFailureDetail() {
                    local location=${3:-}
                    helperCalls=$((helperCalls + 1))
                    if [[ -n "${location}" ]]; then
                        command printf -v "$1" '%s' "${2}恢复失败，请手动检查${location}"
                    else
                        command printf -v "$1" '%s' "${2}恢复失败"
                    fi
                    [[ "$2" == "状态" ]]
                    [[ -z "${location}" ]]
                    return 0
                }
                SUBSCRIPTION_CONTROL_RESTORE_ERROR=
                rm -f "${restoreOrderLog}"
                set +e
                subscriptionControlRestoreAppliedPlan '{"version":2,"groups":[]}' "${restoreOrderConfig}" "${restoreOrderOutput}"
                local restoreOrderStatus=$?
                set -e
                [[ "${restoreOrderStatus}" -eq 1 ]]
                [[ "${helperCalls}" == "1" ]] || return 1
                grep -qx 'state' "${restoreOrderLog}"
                grep -qx 'config' "${restoreOrderLog}"
                grep -qx 'output' "${restoreOrderLog}"
                [[ "${SUBSCRIPTION_CONTROL_RESTORE_ERROR}" == *"状态恢复失败"* ]]
            )

            (
                local restoreOrderLog="${TMP_DIR}/remote-control-restore-order-output.log"
                local restoreOrderConfig="${TMP_DIR}/remote-control-restore-config-output"
                local restoreOrderOutput="${TMP_DIR}/remote-control-restore-output-output"
                local helperCalls=0
                mkdir -p "${restoreOrderConfig}" "${restoreOrderOutput}"
                subscriptionGroupsStateWrite() {
                    printf 'state\n' >>"${restoreOrderLog}"
                    return 0
                }
                subscriptionSyncRestoreConfigBackups() {
                    printf 'config\n' >>"${restoreOrderLog}"
                    return 0
                }
                subscriptionSyncRestoreSubscribeOutputBackups() {
                    printf 'output\n' >>"${restoreOrderLog}"
                    return 1
                }
                subscriptionSyncSetRestoreFailureDetail() {
                    local location=${3:-}
                    helperCalls=$((helperCalls + 1))
                    if [[ -n "${location}" ]]; then
                        command printf -v "$1" '%s' "${2}恢复失败，请手动检查${location}"
                    else
                        command printf -v "$1" '%s' "${2}恢复失败"
                    fi
                    [[ "$2" == "订阅输出" ]]
                    [[ "${location}" == "备份目录: ${restoreOrderOutput}" ]]
                    return 0
                }
                SUBSCRIPTION_CONTROL_RESTORE_ERROR=
                rm -f "${restoreOrderLog}"
                set +e
                subscriptionControlRestoreAppliedPlan '{"version":2,"groups":[]}' "${restoreOrderConfig}" "${restoreOrderOutput}"
                local restoreOrderStatus=$?
                set -e
                [[ "${restoreOrderStatus}" -eq 1 ]]
                [[ "${helperCalls}" == "1" ]] || return 1
                grep -qx 'state' "${restoreOrderLog}"
                grep -qx 'config' "${restoreOrderLog}"
                grep -qx 'output' "${restoreOrderLog}"
                [[ "${SUBSCRIPTION_CONTROL_RESTORE_ERROR}" == "控制面同步失败后订阅输出恢复失败，请手动检查备份目录: ${restoreOrderOutput}" ]]
            )
        fi
    fi

    if [[ "${runDeepSections}" == "true" ]]; then
        useRealSyncBackups
        useRealSubscriptionGroupsState
        mkdir -p "$(dirname "$(subscriptionGroupsFile)")"
        cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON

        mkdir -p "${rollbackRoot}/xray"
        configPath="${rollbackRoot}/xray/"
        singBoxConfigPath="${rollbackRoot}/xray/"
        cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[]}}]}
JSON
        cat >"${configPath}03_VLESS_WS_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[]}}]}
JSON
        cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
        coreInstallType=1
        subscriptionSyncPlanFromAccounts() {
            printf '{"create":["sub_rollback"],"remove":[]}'
        }
        rollbackStateBefore=$(jq -c . "$(subscriptionGroupsFile)")
        rollbackFirstBefore=$(<"${configPath}02_VLESS_TCP_inbounds.json")
        rollbackSecondBefore=$(<"${configPath}03_VLESS_WS_inbounds.json")
        subscriptionControlApplyAccountPlan() {
            originalSubscriptionControlApplyAccountPlan "$@"
        }
        subscriptionSyncSetUsersInFile() {
            setUsersCalls=$((setUsersCalls + 1))
            if [[ "${setUsersCalls}" -eq 2 ]]; then
                return 1
            fi
            originalSubscriptionSyncSetUsersInFile "$@"
        }
        set +e
        PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"rollback","uuid":"66666666-6666-6666-6666-666666666666"}],"dry_run":false}' >"${responseFile}.rollback"
        local rollbackStatus=$?
        set -e
        [[ "${rollbackStatus}" -ne 0 ]]
        jq -e '.ok == false and .error == "apply_plan_failed" and .error_detail.type == "apply_plan_failed"' "${responseFile}.rollback" >/dev/null
        printf '%s\n' "${rollbackStateBefore}" >"${rollbackExpectedFile}"
        jq -e --slurpfile expected "${rollbackExpectedFile}" '. == $expected[0]' "$(subscriptionGroupsFile)" >/dev/null
        [[ "$(<"${configPath}02_VLESS_TCP_inbounds.json")" == "${rollbackFirstBefore}" ]]
        [[ "$(<"${configPath}03_VLESS_WS_inbounds.json")" == "${rollbackSecondBefore}" ]]
        if regressionFindHasMatches "${rollbackRoot}" \( -name '*.sync.*' -o -name '*subscription-sync-backup*' \); then
            return 1
        fi
        configPath="${oldConfigPath}"
        singBoxConfigPath="${oldSingBoxConfigPath}"
        coreInstallType="${oldCoreInstallType}"
        subscriptionSyncSetUsersInFile() {
            originalSubscriptionSyncSetUsersInFile "$@"
        }

        local refreshRollbackRoot="${TMP_DIR}/remote-control-refresh-rollback"
        local refreshRollbackLocalDir="${refreshRollbackRoot}/subscribe_local"
        local refreshRollbackPublicDir="${refreshRollbackRoot}/subscribe"
        local refreshRollbackStateBefore
        local refreshRollbackFirstBefore
        local refreshRollbackOldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
        local refreshRollbackOldPublicDir="${PADM_SUBSCRIBE_DIR:-}"
        local refreshRollbackOldScriptDir="${SCRIPT_DIR}"
        local refreshRollbackPublicBefore
        local refreshRollbackLocalBefore
        local refreshRollbackExpectedFile="${TMP_DIR}/remote-control-refresh-rollback-expected.json"
        local refreshRollbackPublicExpected="${TMP_DIR}/remote-control-refresh-public-expected.txt"
        local refreshRollbackLocalExpected="${TMP_DIR}/remote-control-refresh-local-expected.txt"
        mkdir -p "${refreshRollbackRoot}/xray"
        configPath="${refreshRollbackRoot}/xray/"
        singBoxConfigPath="${refreshRollbackRoot}/xray/"
        cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[]}}]}
JSON
        mkdir -p "${refreshRollbackLocalDir}/default" "${refreshRollbackLocalDir}/clashMeta" "${refreshRollbackLocalDir}/sing-box" "${refreshRollbackPublicDir}/default" "${refreshRollbackPublicDir}/clashMeta"
        export PADM_SUBSCRIBE_LOCAL_DIR="${refreshRollbackLocalDir}"
        export PADM_SUBSCRIBE_DIR="${refreshRollbackPublicDir}"
        SCRIPT_DIR="${PROJECT_ROOT}"
        subscribeType=https
        subscribePort=39778
        currentHost=refresh.example.com
        printf 'old salt\n' >"${refreshRollbackLocalDir}/subscribeSalt"
        printf 'old local default\n' >"${refreshRollbackLocalDir}/default/existing"
        printf 'old public default\n' >"${refreshRollbackPublicDir}/default/existing-md5"
        cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
        coreInstallType=1
        subscriptionSyncPlanFromAccounts() {
            printf '{"create":["sub_publish"],"remove":[]}'
        }
        subscriptionControlApplyAccountPlan() {
            subscriptionGroupsStateWrite '.groups |= map(.user_groups += [{"id":"publish","name":"Publish","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":"","uuid":"77777777-7777-7777-7777-777777777777"}])'
            cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_publish-vless","id":"77777777-7777-7777-7777-777777777777"}]}}]}
JSON
        }
        showAccounts() {
            local id account
            while IFS= read -r id; do
                [[ -n "${id}" ]] || continue
                account=$(subscriptionSyncAccountName "${id}") || return 1
                printf 'vless://%s\n' "${account}" >"${PADM_SUBSCRIBE_LOCAL_DIR}/default/${account}"
                printf 'name: %s\n' "${account}" >"${PADM_SUBSCRIBE_LOCAL_DIR}/clashMeta/${account}"
                printf '[{"tag":"%s"}]\n' "${account}" >"${PADM_SUBSCRIBE_LOCAL_DIR}/sing-box/${account}"
            done < <(subscriptionGroupsStateRead -r '.groups[].user_groups[]? | select(.enabled == true) | .id')
        }
        refreshRollbackStateBefore=$(jq -c . "$(subscriptionGroupsFile)")
        refreshRollbackFirstBefore=$(<"${configPath}02_VLESS_TCP_inbounds.json")
        refreshRollbackLocalBefore=$(find "${refreshRollbackLocalDir}" -type f -printf '%P\t' -exec cat {} \; | sort)
        refreshRollbackPublicBefore=$(find "${refreshRollbackPublicDir}" -type f -printf '%P\t' -exec cat {} \; | sort)
        printf '%s\n' "${refreshRollbackLocalBefore}" >"${refreshRollbackLocalExpected}"
        printf '%s\n' "${refreshRollbackPublicBefore}" >"${refreshRollbackPublicExpected}"
        subscribe() {
            printf 'new salt\n' >"${refreshRollbackLocalDir}/subscribeSalt"
            printf 'new local default\n' >"${refreshRollbackLocalDir}/default/existing"
            printf 'new local created\n' >"${refreshRollbackLocalDir}/default/generated"
            printf 'new public default\n' >"${refreshRollbackPublicDir}/default/existing-md5"
            printf 'new public created\n' >"${refreshRollbackPublicDir}/default/generated-md5"
            return 1
        }
        set +e
        PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"publish","uuid":"77777777-7777-7777-7777-777777777777"}],"dry_run":false}' >"${responseFile}.refresh-rollback"
        local refreshRollbackStatus=$?
        set -e
        [[ "${refreshRollbackStatus}" -eq 0 ]]
        jq -e '.ok == true and .changed == true and (.subscriptions | has("sub_publish"))' "${responseFile}.refresh-rollback" >/dev/null
        jq -e 'any(.groups[0].user_groups[]; .id == "publish")' "$(subscriptionGroupsFile)" >/dev/null
        [[ "$(<"${configPath}02_VLESS_TCP_inbounds.json")" != "${refreshRollbackFirstBefore}" ]]
        diff -u "${refreshRollbackLocalExpected}" <(find "${refreshRollbackLocalDir}" -type f -printf '%P\t' -exec cat {} \; | sort)
        diff -u "${refreshRollbackPublicExpected}" <(find "${refreshRollbackPublicDir}" -type f -printf '%P\t' -exec cat {} \; | sort)
        if regressionFindHasMatches "${refreshRollbackRoot}" \( -name '*.sync.*' -o -name '*subscription-sync-backup*' -o -name '*subscription-output-backup*' \); then
            return 1
        fi
        configPath="${oldConfigPath}"
        singBoxConfigPath="${oldSingBoxConfigPath}"
        coreInstallType="${oldCoreInstallType}"
        SCRIPT_DIR="${refreshRollbackOldScriptDir}"
        if [[ -n "${refreshRollbackOldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${refreshRollbackOldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
        if [[ -n "${refreshRollbackOldPublicDir}" ]]; then export PADM_SUBSCRIBE_DIR="${refreshRollbackOldPublicDir}"; else unset PADM_SUBSCRIBE_DIR; fi
        subscribe() {
            originalSubscribe "$@"
        }

        local restoreFailureRoot="${TMP_DIR}/remote-control-restore-failure"
        local restoreFailureLocalDir="${restoreFailureRoot}/subscribe_local"
        local restoreFailurePublicDir="${restoreFailureRoot}/subscribe"
        local restoreFailureOldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
        local restoreFailureOldPublicDir="${PADM_SUBSCRIBE_DIR:-}"
        local restoreFailureOldScriptDir="${SCRIPT_DIR}"
        local restoreFailureOldTmpDir="${TMPDIR:-}"
        local restoreFailureBackupDirs=()
        mkdir -p "${restoreFailureRoot}/xray" "${restoreFailureLocalDir}/default" "${restoreFailurePublicDir}/default"
        configPath="${restoreFailureRoot}/xray/"
        singBoxConfigPath="${restoreFailureRoot}/xray/"
        TMPDIR="${restoreFailureRoot}"
        cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[]}}]}
JSON
        export PADM_SUBSCRIBE_LOCAL_DIR="${restoreFailureLocalDir}"
        export PADM_SUBSCRIBE_DIR="${restoreFailurePublicDir}"
        SCRIPT_DIR="${PROJECT_ROOT}"
        printf 'old local\n' >"${restoreFailureLocalDir}/default/existing"
        printf 'old public\n' >"${restoreFailurePublicDir}/default/existing-md5"
        cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
        coreInstallType=1
        subscriptionSyncPlanFromAccounts() {
            printf '{"create":["sub_restore_fail"],"remove":[]}'
        }
        subscriptionControlApplyAccountPlan() {
            subscriptionGroupsStateWrite '.groups |= map(.user_groups += [{"id":"restore-fail","name":"Restore Fail","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":"","uuid":"88888888-8888-8888-8888-888888888888"}])'
            cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_restore_fail-vless","id":"88888888-8888-8888-8888-888888888888"}]}}]}
JSON
        }
        subscribe() {
            printf 'new local\n' >"${restoreFailureLocalDir}/default/existing"
            printf 'new local created\n' >"${restoreFailureLocalDir}/default/generated"
            printf 'new public\n' >"${restoreFailurePublicDir}/default/existing-md5"
            printf 'new public created\n' >"${restoreFailurePublicDir}/default/generated-md5"
            return 1
        }
        cp() {
            if [[ "$1" == "-a" && "$2" == ${restoreFailureRoot}/padm-subscription-output-backup.*/local/. ]]; then
                return 1
            fi
            command cp "$@"
        }
        local restoreFailureReloadBefore=${reloadCalls:-0}
        set +e
        PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"restore-fail","uuid":"88888888-8888-8888-8888-888888888888"}],"dry_run":false}' >"${responseFile}.restore-failure"
        local restoreFailureStatus=$?
        set -e
        unset -f cp
        [[ "${restoreFailureStatus}" -eq 0 ]]
        [[ "${reloadCalls}" -eq $((restoreFailureReloadBefore + 1)) ]]
        jq -e '.ok == true and .changed == true and (.subscriptions | has("sub_restore_fail"))' "${responseFile}.restore-failure" >/dev/null
        mapfile -t restoreFailureBackupDirs < <(find "${restoreFailureRoot}" -maxdepth 1 -type d \( -name 'padm-subscription-output-backup.*' -o -name 'padm-subscription-sync-backup.*' \) -print)
        [[ "${#restoreFailureBackupDirs[@]}" == "0" ]]
        [[ "$(<"${restoreFailureLocalDir}/default/existing")" == "old local" ]]
        [[ "$(<"${restoreFailurePublicDir}/default/existing-md5")" == "old public" ]]
        if regressionFindHasMatches "${restoreFailureRoot}/xray" -name '*.sync.*'; then
            return 1
        fi
        if [[ -n "${restoreFailureOldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${restoreFailureOldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
        if [[ -n "${restoreFailureOldPublicDir}" ]]; then export PADM_SUBSCRIBE_DIR="${restoreFailureOldPublicDir}"; else unset PADM_SUBSCRIBE_DIR; fi
        configPath="${oldConfigPath}"
        singBoxConfigPath="${oldSingBoxConfigPath}"
        coreInstallType="${oldCoreInstallType}"
        SCRIPT_DIR="${restoreFailureOldScriptDir}"
        if [[ -n "${restoreFailureOldTmpDir}" ]]; then export TMPDIR="${restoreFailureOldTmpDir}"; else unset TMPDIR; fi
        subscribe() {
            originalSubscribe "$@"
        }
        subscriptionControlApplyAccountPlan() {
            originalSubscriptionControlApplyAccountPlan "$@"
        }
        subscriptionSyncPlanFromAccounts() {
            originalSubscriptionSyncPlanFromAccounts "$@"
        }
        useLightweightSyncBackups
        if [[ "${runLightSections}" == "true" ]]; then
            useVirtualSubscriptionGroupsState
            resetVirtualSubscriptionGroupsState
        fi
    fi

    if remoteControlLightModeSelected all reconcile; then
        subscriptionControlApplyAccountPlan() {
            return 0
        }
        useVirtualSubscriptionGroupsState
        resetVirtualSubscriptionGroupsState
        (
            local reconcileLog="${TMP_DIR}/remote-control-local-reconcile-retry.log"
            reconcileCalls=0
            : >"${reconcileLog}"
            subscriptionSyncReconcileLocalServices() {
                reconcileCalls=$((reconcileCalls + 1))
                printf '%s\n' "${1:-<empty>}" >>"${reconcileLog}"
                [[ -n "${1:-}" ]]
            }
            set +e
            PADM_CONTROL_SERVER= subscriptionControlApplySync '{"desired_users":[{"id":"team-c","uuid":"33333333-3333-3333-3333-333333333333"}],"dry_run":false}' >"${responseFile}"
            local reconcileStatus=$?
            set -e
            [[ "${reconcileStatus}" -ne 0 ]]
            [[ "${reconcileCalls}" == "2" ]]
            grep -qxm1 '^<empty>$' "${reconcileLog}"
            grep -qxm1 '^true$' "${reconcileLog}"
            jq -e '.ok == false and .error == "reconcile_failed" and .error_detail.type == "reconcile_failed" and (.error_detail.message | contains("已恢复旧配置")) and ((.error_detail.message | contains("恢复旧配置后服务重建仍失败")) | not)' "${responseFile}" >/dev/null
        )

        (
            local reconcileLog="${TMP_DIR}/remote-control-local-reconcile-retry-fail.log"
            reconcileCalls=0
            : >"${reconcileLog}"
            subscriptionSyncReconcileLocalServices() {
                reconcileCalls=$((reconcileCalls + 1))
                printf '%s\n' "${1:-<empty>}" >>"${reconcileLog}"
                return 1
            }
            set +e
            PADM_CONTROL_SERVER= subscriptionControlApplySync '{"desired_users":[{"id":"team-c","uuid":"33333333-3333-3333-3333-333333333333"}],"dry_run":false}' >"${responseFile}.reconcile-retry-fail"
            local reconcileStatus=$?
            set -e
            [[ "${reconcileStatus}" -ne 0 ]]
            [[ "${reconcileCalls}" == "2" ]]
            grep -qxm1 '^<empty>$' "${reconcileLog}"
            grep -qxm1 '^true$' "${reconcileLog}"
            jq -e '.ok == false and .error == "reconcile_failed" and .error_detail.type == "reconcile_failed" and (.error_detail.message | contains("恢复旧配置后服务重建仍失败"))' "${responseFile}.reconcile-retry-fail" >/dev/null
        )

        subscriptionSyncPlanFromAccounts() {
            printf '{"create":[null],"remove":[]}'
        }
        set +e
        PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"team-d","uuid":"44444444-4444-4444-4444-444444444444"}],"dry_run":true}' >"${responseFile}"
        local invalidPlanStatus=$?
        set -e
        [[ "${invalidPlanStatus}" -ne 0 ]]
        jq -e '.ok == false and .error == "plan_failed" and .error_detail.type == "plan_failed" and (.plan.create[0] == null)' "${responseFile}" >/dev/null

        subscriptionSyncPlanFromAccounts() {
            printf 'not-json\n'
        }
        set +e
        PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"team-e","uuid":"55555555-5555-5555-5555-555555555555"}],"dry_run":true}' >"${responseFile}"
        local badPlanStatus=$?
        set -e
        [[ "${badPlanStatus}" -ne 0 ]]
        jq -e '.ok == false and .error == "plan_failed" and .error_detail.type == "plan_failed" and has("plan") == false' "${responseFile}" >/dev/null
    fi
)

runSubscriptionControlTokenTransactionRegression() (
    local tokenRoot="${TMP_DIR}/remote-control-token-transaction"
    local fakeBin="${tokenRoot}/bin"
    local tokenFile
    local oldPath="${PATH}"
    local tokenStatus

    mkdir -p "${fakeBin}" "${tokenRoot}"
    cat >"${fakeBin}/openssl" <<'SH'
#!/usr/bin/env bash
printf 'partial-token'
exit 1
SH
    chmod +x "${fakeBin}/openssl"

    PATH="${fakeBin}:${oldPath}"
    PADM_SUBSCRIPTION_GROUPS_DIR="${tokenRoot}/groups"
    tokenFile=$(subscriptionControlTokenFile)

    regressionExpectStatus 1 subscriptionControlEnsureToken >/dev/null 2>&1
    [[ ! -e "${tokenFile}" ]]
    if regressionFindHasMatches "${tokenRoot}" -maxdepth 2 -type f -name '.control.token.token.*'; then
        return 1
    fi

    mkdir -p "$(dirname "${tokenFile}")"
    printf 'existing-token\n' >"${tokenFile}"
    command chmod 644 "${tokenFile}"
    chmod() {
        if [[ "$1" == "600" && "$2" == "${tokenFile}" ]]; then
            return 1
        fi
        command chmod "$@"
    }
    set +e
    subscriptionControlEnsureToken >/dev/null 2>&1
    tokenStatus=$?
    set -e
    unset -f chmod
    [[ "${tokenStatus}" == "1" ]]
    [[ "$(stat -c '%a' "${tokenFile}")" == "644" ]]
)

runSubscriptionControlServiceInstallRegression() (
    local installMode=${1:-all}
    local installModeTag=${installMode}
    local runSuccessSection=false
    local runSystemctlFailSection=false
    local runHealthFailSection=false
    local runHealthRollbackSection=false

    case "${installMode}" in
    all)
        runSuccessSection=true
        runSystemctlFailSection=true
        runHealthFailSection=true
        runHealthRollbackSection=true
        ;;
    success)
        runSuccessSection=true
        ;;
    systemctl-fail)
        runSystemctlFailSection=true
        ;;
    health-fail)
        runHealthFailSection=true
        ;;
    health-rollback)
        runHealthRollbackSection=true
        ;;
    *)
        printf 'unknown remote-control service install mode: %s\n' "${installMode}" >&2
        return 2
        ;;
    esac

    local controlRoot="${TMP_DIR}/remote-control-service-install-${installModeTag}"
    local actionsFile="${TMP_DIR}/remote-control-systemctl-actions-${installModeTag}.txt"
    local healthTokensFile="${TMP_DIR}/remote-control-health-tokens-${installModeTag}.txt"
    local knownToken="known-control-token"
    local installStatus
    local oldServerScript
    local oldServiceFile
    local successServiceFile
    local virtualBackupDir="${TMP_DIR}/remote-control-service-backup-${installModeTag}"
    local virtualBackupServerPath=
    local virtualBackupServicePath=
    local virtualBackupServerExists=false
    local virtualBackupServiceExists=false
    local virtualBackupServerContent=
    local virtualBackupServiceContent=

    mkdir -p "${controlRoot}"
    subscriptionControlHealthCheck() {
        printf '%s\n' "$1" >>"${PADM_FAKE_HEALTH_TOKENS}"
        [[ "${PADM_FAKE_HEALTH_FAIL:-}" != "true" ]]
    }
    writeSubscriptionControlServer() {
        local serverScript
        serverScript=$(subscriptionControlServerScript)
        mkdir -p "$(dirname "${serverScript}")" || return 1
        printf '#!/usr/bin/env bash\nexit 0\n' >"${serverScript}" || return 1
        chmod 755 "${serverScript}" || return 1
    }
    subscriptionControlEnsureToken() {
        return 0
    }
    subscriptionControlToken() {
        printf '%s\n' "${knownToken}"
    }
    subscriptionGroupsSecureStateFiles() {
        return 0
    }
    checkLogBackupCreate() {
        local resultVar=$1
        shift
        virtualBackupServerPath=${1:-}
        virtualBackupServicePath=${2:-}
        if [[ -n "${virtualBackupServerPath}" && -f "${virtualBackupServerPath}" ]]; then
            virtualBackupServerExists=true
            virtualBackupServerContent=$(<"${virtualBackupServerPath}")
        else
            virtualBackupServerExists=false
            virtualBackupServerContent=
        fi
        if [[ -n "${virtualBackupServicePath}" && -f "${virtualBackupServicePath}" ]]; then
            virtualBackupServiceExists=true
            virtualBackupServiceContent=$(<"${virtualBackupServicePath}")
        else
            virtualBackupServiceExists=false
            virtualBackupServiceContent=
        fi
        printf -v "${resultVar}" '%s' "${virtualBackupDir}"
    }
    restoreVirtualServiceInstallFile() {
        local filePath=$1
        local fileExists=$2
        local fileContent=$3
        [[ -n "${filePath}" ]] || return 0
        if [[ "${fileExists}" == "true" ]]; then
            mkdir -p "$(dirname "${filePath}")" || return 1
            printf '%s' "${fileContent}" >"${filePath}" || return 1
        else
            rm -f -- "${filePath}" >/dev/null 2>&1 || return 1
        fi
    }
    checkLogBackupRestore() {
        local backupDir=$1
        local status=0
        [[ "${backupDir}" == "${virtualBackupDir}" ]] || return 1
        restoreVirtualServiceInstallFile "${virtualBackupServerPath}" "${virtualBackupServerExists}" "${virtualBackupServerContent}" || status=1
        restoreVirtualServiceInstallFile "${virtualBackupServicePath}" "${virtualBackupServiceExists}" "${virtualBackupServiceContent}" || status=1
        return "${status}"
    }
    systemctl() {
        printf '%s\n' "$*" >>"${PADM_FAKE_SYSTEMCTL_ACTIONS}"
        case "$1" in
        daemon-reload)
            [[ "${PADM_FAKE_SYSTEMCTL_FAIL:-}" == "daemon-reload" ]] && return 1
            return 0
            ;;
        is-active)
            [[ "${PADM_FAKE_SYSTEMCTL_ACTIVE:-}" == "true" ]] && return 0
            return 3
            ;;
        is-enabled)
            [[ "${PADM_FAKE_SYSTEMCTL_ENABLED:-}" == "true" ]] && return 0
            return 1
            ;;
        restart)
            [[ "${PADM_FAKE_SYSTEMCTL_FAIL:-}" == "restart" ]] && return 1
            return 0
            ;;
        enable)
            [[ "${PADM_FAKE_SYSTEMCTL_FAIL:-}" == "enable" ]] && return 1
            return 0
            ;;
        *)
            return 0
            ;;
        esac
    }

    subscriptionControlServiceFile() {
        printf '%s\n' "${controlRoot}/systemd/padm-subscription-control.service"
    }
    export PADM_FAKE_SYSTEMCTL_ACTIONS="${actionsFile}"
    export PADM_FAKE_HEALTH_TOKENS="${healthTokensFile}"
    export PADM_CONTROL_HEALTH_RETRIES=1
    export PADM_CONTROL_HEALTH_RETRY_DELAY=0
    export PADM_CONTROL_HEALTH_TIMEOUT=0.05
    sleep() { return 0; }

    (
        command() {
            if [[ "$1" == "-v" && "$2" == "python3" ]]; then
                return 1
            fi
            builtin command "$@"
        }
        if installSubscriptionControlService >/dev/null 2>&1; then
            return 1
        fi
    )
    (
        command() {
            if [[ "$1" == "-v" && "$2" == "systemctl" ]]; then
                return 1
            fi
            builtin command "$@"
        }
        if installSubscriptionControlService >/dev/null 2>&1; then
            return 1
        fi
    )

    if [[ "${runSuccessSection}" == "true" || "${runSystemctlFailSection}" == "true" || "${runHealthFailSection}" == "true" ]]; then
        PADM_SUBSCRIPTION_GROUPS_DIR="${controlRoot}/success"
        mkdir -p "${PADM_SUBSCRIPTION_GROUPS_DIR}"
        : >"${actionsFile}"
        : >"${healthTokensFile}"
        installSubscriptionControlService
        [[ -x "$(subscriptionControlServerScript)" ]]
        grep -qxF "ExecStart=/usr/bin/env python3 \"$(subscriptionControlServerScript)\"" "$(subscriptionControlServiceFile)" || return 1
        grep -qxF 'enable --now padm-subscription-control.service' "${actionsFile}"
        grep -qxF "${knownToken}" "${healthTokensFile}"
        successServiceFile=$(<"$(subscriptionControlServiceFile)")
    fi

    if [[ "${runSystemctlFailSection}" == "true" ]]; then
        PADM_SUBSCRIPTION_GROUPS_DIR="${controlRoot}/systemctl-fail"
        mkdir -p "${PADM_SUBSCRIPTION_GROUPS_DIR}"
        export PADM_FAKE_SYSTEMCTL_FAIL=enable
        set +e
        installSubscriptionControlService
        installStatus=$?
        set -e
        PADM_FAKE_SYSTEMCTL_FAIL=
        [[ "${installStatus}" -ne 0 ]]
        [[ ! -e "$(subscriptionControlServerScript)" ]]
        [[ -f "$(subscriptionControlServiceFile)" ]]
        [[ "$(<"$(subscriptionControlServiceFile)")" == "${successServiceFile}" ]]
        [[ "${SUBSCRIPTION_CONTROL_INSTALL_ERROR}" == *"已恢复安装前状态"* ]]
    fi

    if [[ "${runHealthFailSection}" == "true" ]]; then
        PADM_SUBSCRIPTION_GROUPS_DIR="${controlRoot}/health-fail"
        mkdir -p "${PADM_SUBSCRIPTION_GROUPS_DIR}"
        : >"${actionsFile}"
        export PADM_FAKE_HEALTH_FAIL=true
        set +e
        installSubscriptionControlService
        installStatus=$?
        set -e
        PADM_FAKE_HEALTH_FAIL=
        [[ "${installStatus}" -ne 0 ]]
        [[ ! -e "$(subscriptionControlServerScript)" ]]
        [[ -f "$(subscriptionControlServiceFile)" ]]
        [[ "$(<"$(subscriptionControlServiceFile)")" == "${successServiceFile}" ]]
        [[ "${SUBSCRIPTION_CONTROL_INSTALL_ERROR}" == *"已恢复安装前状态"* ]]
    fi

    if [[ "${runHealthRollbackSection}" == "true" ]]; then
        PADM_SUBSCRIPTION_GROUPS_DIR="${controlRoot}/health-rollback"
        mkdir -p "${PADM_SUBSCRIPTION_GROUPS_DIR}" "$(dirname "$(subscriptionControlServerScript)")" "$(dirname "$(subscriptionControlServiceFile)")"
        printf 'old-server\n' >"$(subscriptionControlServerScript)"
        printf 'old-service\n' >"$(subscriptionControlServiceFile)"
        oldServerScript=$(subscriptionControlServerScript)
        oldServiceFile=$(subscriptionControlServiceFile)
        : >"${actionsFile}"
        export PADM_FAKE_SYSTEMCTL_ACTIVE=true
        export PADM_FAKE_SYSTEMCTL_ENABLED=true
        export PADM_FAKE_HEALTH_FAIL=true
        set +e
        installSubscriptionControlService
        installStatus=$?
        set -e
        PADM_FAKE_SYSTEMCTL_ACTIVE=
        PADM_FAKE_SYSTEMCTL_ENABLED=
        PADM_FAKE_HEALTH_FAIL=
        [[ "${installStatus}" -ne 0 ]]
        [[ "$(<"${oldServerScript}")" == "old-server" ]]
        [[ "$(<"${oldServiceFile}")" == "old-service" ]]
        [[ "$(grep -c '^daemon-reload$' "${actionsFile}")" == "2" ]]
        [[ "$(grep -c '^restart padm-subscription-control.service$' "${actionsFile}")" == "2" ]]
    fi
)

runSubscriptionControlServerResponseRegression() (
    command -v python3 >/dev/null 2>&1 || return 0

    local controlRoot="${TMP_DIR}/remote-control-server-response"
    local fakeInstall="${controlRoot}/install.sh"
    local modeFile="${controlRoot}/mode"
    local startedFile="${controlRoot}/sync.started"
    local descendantSurvivedFile="${controlRoot}/descendant.survived"
    local responseFile="${controlRoot}/response.txt"
    local serverLog="${controlRoot}/server.log"
    local serverScript
    local serverPid=
    local testPort
    local serverToken="test-token"
    local status
    local body
    local ready=
    local literal
    mkdir -p "${controlRoot}"
    literal=$(subscriptionControlPythonStringLiteral 'path "quoted" \ slash') || return 1
    PADM_TEST_PYTHON_LITERAL="${literal}" python3 <<'PY'
import ast
import os
assert ast.literal_eval(os.environ["PADM_TEST_PYTHON_LITERAL"]) == 'path "quoted" \\ slash'
PY
    [[ "$?" == "0" ]] || return 1
    testPort=$(python3 <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)
    getScriptVersion() {
        printf 'test\n'
    }
    cat >"${fakeInstall}" <<'SH'
#!/usr/bin/env bash
endpoint=${2:-}
mode=
if [[ -f "${PADM_FAKE_CONTROL_MODE_FILE}" ]]; then
    mode=$(<"${PADM_FAKE_CONTROL_MODE_FILE}")
fi
payload=
if [[ "${PADM_CONTROL_TOKEN:-}" != "${PADM_FAKE_SERVER_TOKEN:-}" ]]; then
    printf '{"ok":false,"error":"unauthorized","error_detail":{"type":"unauthorized","message":"控制 token 验证失败"}}\n'
    exit 1
fi
if [[ "${endpoint}" == "sync" ]]; then
    payload=$(cat)
    if [[ -z "${payload}" ]]; then
        printf '{"ok":false,"error":"empty_payload","error_detail":{"type":"empty_payload","message":"同步请求体为空"}}\n'
        exit 1
    fi
    if [[ "${payload}" == "not-json" ]]; then
        printf '{"ok":false,"error":"invalid_payload","error_detail":{"type":"invalid_payload","message":"同步请求体格式不正确"}}\n'
        exit 1
    fi
elif [[ "${endpoint}" == "traffic" ]]; then
    payload=$(cat)
    if [[ "${payload}" != "{}" ]]; then
        printf '{"ok":false,"error":"invalid_payload","error_detail":{"type":"invalid_payload","message":"流量请求体格式不正确"}}\n'
        exit 1
    fi
fi
case "${endpoint}:${mode}" in
health:*)
    printf '{"ok":false,"error":"health_should_not_execute"}\n'
    exit 9
    ;;
sync:noise)
    printf 'ui noise before sync\n'
    printf '{"ok":false,"error":"first_json"}\n'
    printf 'ui noise between json\n'
    printf '{"ok":true,"dry_run":false,"changed":true,"plan":{"create":[],"remove":[]}}\n'
    ;;
traffic:noise)
    printf 'ui noise before traffic\n'
    printf '{"ok":true,"items":[{"account":"admin","upload":7,"download":9}]}\n'
    ;;
sync:failed)
    printf 'ui noise before failed sync\n'
    printf '{"ok":true,"changed":true}\n'
    exit 7
    ;;
sync:timeout)
    : >"${PADM_FAKE_CONTROL_STARTED_FILE}"
    (
        /bin/sleep 1.2
        printf 'survived\n' >"${PADM_FAKE_CONTROL_DESCENDANT_FILE}"
    ) &
    wait
    printf '{"ok":true}\n'
    ;;
    sync:invalid)
        printf 'ui noise only\n'
        exit 0
        ;;
    *)
        printf '{"ok":false,"error":"unexpected"}\n'
        exit 1
        ;;
    esac
SH
    chmod +x "${fakeInstall}"

    subscriptionControlPort() {
        printf '%s\n' "${testPort}"
    }
    subscriptionGroupSyncInstallScript() {
        printf '%s\n' "${fakeInstall}"
    }
    PADM_SUBSCRIPTION_GROUPS_DIR="${controlRoot}/state"
    mkdir -p "$(dirname "$(subscriptionControlTokenFile)")"
    printf '%s\n' "${serverToken}" >"$(subscriptionControlTokenFile)"
    export PADM_FAKE_SERVER_TOKEN="${serverToken}"
    export PADM_FAKE_CONTROL_DESCENDANT_FILE="${descendantSurvivedFile}"
    writeSubscriptionControlServer
    serverScript=$(subscriptionControlServerScript)
    printf 'noise\n' >"${modeFile}"
    : >"${startedFile}"
    PADM_CONTROL_SCRIPT_TIMEOUT=1 PADM_CONTROL_REQUEST_TIMEOUT=0.2 PADM_FAKE_CONTROL_MODE_FILE="${modeFile}" PADM_FAKE_CONTROL_STARTED_FILE="${startedFile}" python3 "${serverScript}" >"${serverLog}" 2>&1 &
    serverPid=$!
    trap '[[ -n "${serverPid}" ]] && kill "${serverPid}" >/dev/null 2>&1 || true; [[ -n "${serverPid}" ]] && wait "${serverPid}" 2>/dev/null || true' EXIT
    export PADM_TEST_CONTROL_STARTED_FILE="${startedFile}"

    PADM_TEST_CONTROL_PORT="${testPort}" \
    PADM_TEST_CONTROL_MODE_FILE="${modeFile}" \
    PADM_TEST_CONTROL_TOKEN="${serverToken}" \
    python3 <<'PY' >"${responseFile}"
import json
import os
import socket
import threading
import time
import urllib.error
import urllib.request

port = os.environ["PADM_TEST_CONTROL_PORT"]
mode_file = os.environ["PADM_TEST_CONTROL_MODE_FILE"]
token = os.environ["PADM_TEST_CONTROL_TOKEN"]
base_url = f"http://127.0.0.1:{port}/s/control"

def set_mode(value):
    with open(mode_file, "w", encoding="utf-8") as handle:
        handle.write(value)

def request(method, endpoint, payload="", token_override=None):
    current_token = token_override if token_override is not None else token
    data = payload.encode("utf-8") if method == "POST" else None
    headers = {"Authorization": f"Bearer {current_token}"}
    if method == "POST":
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(
        f"{base_url}/{endpoint}",
        data=data,
        method=method,
        headers=headers,
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            status = response.status
            body_text = response.read().decode()
    except urllib.error.HTTPError as error:
        status = error.code
        body_text = error.read().decode()
    except Exception as error:
        return {"status": 0, "error": type(error).__name__, "body": None}
    try:
        body = json.loads(body_text) if body_text else None
    except json.JSONDecodeError:
        body = None
    return {"status": status, "body": body}

def raw_post(endpoint, content_length):
    payload = "{}"
    request_text = (
        f"POST /s/control/{endpoint} HTTP/1.1\r\n"
        "Host: 127.0.0.1\r\n"
        f"Authorization: Bearer {token}\r\n"
        "Content-Type: application/json\r\n"
        f"Content-Length: {content_length}\r\n"
        "Connection: close\r\n"
        "\r\n"
        f"{payload}"
    )
    try:
        with socket.create_connection(("127.0.0.1", int(port)), timeout=10) as sock:
            sock.sendall(request_text.encode("utf-8"))
            chunks = []
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
    except Exception as error:
        return {"status": 0, "error": type(error).__name__, "body": None}
    response = b"".join(chunks).decode("utf-8", errors="replace")
    head, _, body_text = response.partition("\r\n\r\n")
    try:
        status = int(head.split()[1])
    except Exception:
        return {"status": 0, "body": None}
    try:
        body = json.loads(body_text) if body_text else None
    except json.JSONDecodeError:
        body = None
    return {"status": status, "body": body}

def slow_post(endpoint):
    request_text = (
        f"POST /s/control/{endpoint} HTTP/1.1\r\n"
        "Host: 127.0.0.1\r\n"
        f"Authorization: Bearer {token}\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 10\r\n"
        "Connection: close\r\n"
        "\r\n"
        "{"
    )
    try:
        with socket.create_connection(("127.0.0.1", int(port)), timeout=10) as sock:
            sock.sendall(request_text.encode("utf-8"))
            time.sleep(0.4)
            chunks = []
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
    except Exception as error:
        return {"status": 0, "error": type(error).__name__, "body": None}
    response = b"".join(chunks).decode("utf-8", errors="replace")
    head, _, body_text = response.partition("\r\n\r\n")
    try:
        status = int(head.split()[1])
        body = json.loads(body_text) if body_text else None
    except Exception:
        return {"status": 0, "body": None}
    return {"status": status, "body": body}

results = {}
set_mode("noise")
for _ in range(80):
    results["health_ready"] = request("GET", "health")
    body = results["health_ready"].get("body") or {}
    if results["health_ready"]["status"] == 200 and body.get("ok") is True:
        break
    time.sleep(0.1)

set_mode("noise")
results["sync_success"] = request("POST", "sync", '{"desired_users":[],"dry_run":false}')
results["traffic_success"] = request("POST", "traffic", "{}")
results["subscribe_removed"] = request("POST", "subscribe", '{"account":"team_a"}')
results["health_unauthorized"] = request("GET", "health", token_override="wrong-token")
results["sync_empty_payload"] = request("POST", "sync", "")
results["sync_invalid_payload"] = request("POST", "sync", "not-json")
results["sync_bad_content_length"] = raw_post("sync", "abc")
results["sync_slow_body"] = slow_post("sync")

set_mode("failed")
results["sync_failed"] = request("POST", "sync", '{"desired_users":[],"dry_run":false}')
set_mode("timeout")
try:
    os.remove(os.environ["PADM_TEST_CONTROL_STARTED_FILE"])
except FileNotFoundError:
    pass
sync_holder = {}
def run_slow_sync():
    sync_holder["result"] = request("POST", "sync", '{"desired_users":[],"dry_run":false}')
sync_thread = threading.Thread(target=run_slow_sync)
sync_thread.start()
for _ in range(100):
    if os.path.exists(os.environ["PADM_TEST_CONTROL_STARTED_FILE"]):
        break
    time.sleep(0.02)
assert os.path.exists(os.environ["PADM_TEST_CONTROL_STARTED_FILE"])
results["health_during_sync"] = request("GET", "health")
results["sync_while_busy"] = request("POST", "sync", '{"desired_users":[],"dry_run":false}')
sync_thread.join(timeout=10)
assert not sync_thread.is_alive()
results["sync_timeout"] = sync_holder["result"]
time.sleep(0.8)
results["os_name"] = os.name
results["timeout_descendant_survived"] = os.path.exists(os.environ["PADM_FAKE_CONTROL_DESCENDANT_FILE"])
set_mode("invalid")
results["sync_invalid_response"] = request("POST", "sync", '{"desired_users":[],"dry_run":false}')

print(json.dumps(results, ensure_ascii=False))
PY

    jq -e '.health_ready.status == 200 and .health_ready.body.ok == true and .health_ready.body.version == "test" and .health_ready.body.capabilities == ["health","sync","traffic"]' "${responseFile}" >/dev/null
    jq -e '.sync_success.status == 200 and .sync_success.body.ok == true and .sync_success.body.changed == true and (.sync_success.body.plan.create | length) == 0' "${responseFile}" >/dev/null
    jq -e '.traffic_success.status == 200 and .traffic_success.body.ok == true and .traffic_success.body.items == [{account:"admin",upload:7,download:9}]' "${responseFile}" >/dev/null
    jq -e '.subscribe_removed.status == 404 and .subscribe_removed.body.error == "not_found"' "${responseFile}" >/dev/null
    jq -e '.health_unauthorized.status == 401' "${responseFile}" >/dev/null
    jq -e '.sync_empty_payload.status == 400' "${responseFile}" >/dev/null
    jq -e '.sync_invalid_payload.status == 400' "${responseFile}" >/dev/null
    jq -e '.sync_bad_content_length.status == 400 and .sync_bad_content_length.body.error == "invalid_payload"' "${responseFile}" >/dev/null
    jq -e '.sync_slow_body.status == 408 and .sync_slow_body.body.error == "request_timeout"' "${responseFile}" >/dev/null
    jq -e '.sync_failed.status == 503 and .sync_failed.body.error == "script_failed" and .sync_failed.body.error_detail.type == "script_failed" and .sync_failed.body.exit_code == 7' "${responseFile}" >/dev/null
    jq -e '.sync_timeout.status == 503 and .sync_timeout.body.error == "script_timeout" and .sync_timeout.body.error_detail.type == "script_timeout"' "${responseFile}" >/dev/null
    jq -e '.os_name != "posix" or .timeout_descendant_survived == false' "${responseFile}" >/dev/null
    jq -e '.health_during_sync.status == 200 and .health_during_sync.body.ok == true' "${responseFile}" >/dev/null
    jq -e '.sync_while_busy.status == 503 and .sync_while_busy.body.error == "busy" and .sync_while_busy.body.error_detail.type == "busy"' "${responseFile}" >/dev/null
    jq -e '.sync_invalid_response.status == 503 and .sync_invalid_response.body.error == "invalid_response" and .sync_invalid_response.body.error_detail.type == "invalid_response"' "${responseFile}" >/dev/null
)
