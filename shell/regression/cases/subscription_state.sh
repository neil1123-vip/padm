#!/usr/bin/env bash

writeSubscriptionStateDefaultFixture() {
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"remote-edge","name":"remote-edge","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"10.77.0.3","port":48779,"enabled":true,"sync_status":"pending","control_token":"token-def"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":"","uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
}

writeSubscriptionStateSourceCredentialFixture() {
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"我的订阅","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"本机","role":"main","transport":"local","scheme":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"remote-edge","name":"remote-edge","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"10.77.0.2","port":39778,"enabled":true,"sync_status":"pending"}],"user_groups":[],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
}

writeSubscriptionStateSourceStatusFixture() {
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"我的订阅","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"本机","role":"main","transport":"local","scheme":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge","name":"Edge","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"example.com","port":443,"enabled":true,"sync_status":"failed","last_sync_error":{"type":"unreachable","message":"old"}}],"user_groups":[],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
}

writeSubscriptionStateSourceRemoveFixture() {
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"我的订阅","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"本机","role":"main","transport":"local","scheme":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge","name":"Edge","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"example.com","port":443,"enabled":true,"sync_status":"failed","last_sync_error":{"type":"unreachable","message":"old"}}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["edge"],"traffic_limit_gb":1,"token":"","uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{"team-a":{"upload":1,"download":2,"sources":{"edge":{"upload":1,"download":2}}}},"sources":{"edge":{"upload":1,"download":2}}}}]}
JSON
}

writeSubscriptionStateStructureFoundationFixture() {
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
}

prepareSubscriptionStateQuotaUsageFixture() {
    mkdir -p "$(subscriptionGroupsDir)"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"remote-edge","name":"remote-edge","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"10.77.0.3","port":48779,"enabled":true,"sync_status":"pending","control_token":"token-def"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":1,"token":"","uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":2097152,"download":1048576,"sources":{"main":{"upload":2097152,"download":1048576,"updated_at":"2026-06-10 10:00:00"}}},"user_groups":{"team-a":{"upload":1073741824,"download":1,"sources":{"main":{"upload":1073741824,"download":1}}}},"sources":{"main":{"upload":2097152,"download":1048576,"updated_at":"2026-06-10 10:00:00"},"remote-edge":{"upload":1048576,"download":0,"updated_at":"2026-06-10 10:01:00"}}}}]}
JSON
}

prepareSubscriptionGroupSyncFixture() {
    local syncRoot=$1
    local clientEmail=${2:-sub_old-main}

    mkdir -p "${syncRoot}/xray" "${syncRoot}/subscribe_local/default" \
        "${syncRoot}/subscribe/default" "${syncRoot}/groups" "${syncRoot}/tmp"
    configPath="${syncRoot}/xray/"
    singBoxConfigPath="${syncRoot}/xray/"
    export PADM_SUBSCRIPTION_GROUPS_DIR="${syncRoot}/groups"
    export PADM_SUBSCRIBE_LOCAL_DIR="${syncRoot}/subscribe_local"
    export PADM_SUBSCRIBE_DIR="${syncRoot}/subscribe"
    TMPDIR="${syncRoot}/tmp"
    cat >"$(subscriptionGroupsFile)"
    if [[ -n "${clientEmail}" ]]; then
        printf '{"inbounds":[{"settings":{"clients":[{"email":"%s"}]}}]}\n' \
            "${clientEmail}" >"${syncRoot}/xray/02_VLESS_TCP_inbounds.json"
    else
        printf '%s\n' '{"inbounds":[{"settings":{"clients":[]}}]}' >"${syncRoot}/xray/02_VLESS_TCP_inbounds.json"
    fi
    printf 'old-local\n' >"${syncRoot}/subscribe_local/default/user"
    printf 'old-public\n' >"${syncRoot}/subscribe/default/user"
    prepareSubscriptionGroupSyncStubs
}

prepareSubscriptionGroupSyncStubs() {
    subscriptionGroupQuotaAutoApplyEnabled() { return 1; }
    collectSubscriptionTraffic() { return 0; }
    readInstallType() { return 0; }
    readInstallProtocolType() { return 0; }
    readConfigHostPathUUID() { return 0; }
    subscriptionSyncMarkResult() {
        printf '%s\n' "$1" >"${resultStatus}"
        printf '%s\n' "$2" >"${resultFailures}"
        return 0
    }
    successCard() { printf '%s\n' "$*" >"${statusLog}"; }
    statusCard() { printf '%s\n' "$*" >"${statusLog}"; }
}

runSubscriptionGroupStateStructureFoundationAddRemoveRegression() {
    local longId
    mkdir -p "$(subscriptionGroupsDir)"
    writeSubscriptionStateStructureFoundationFixture
    ensureSubscriptionGroupsState
    jq -e '.version == 5 and (.groups | not) and (.active_group | not) and (has("admin") | not)' "$(subscriptionGroupsFile)" >/dev/null
    if ! regressionFindHasMatches "$(subscriptionGroupsBackupDir)" -maxdepth 1 -type f -name 'groups-pre-v3-migration-*.json'; then
        return 1
    fi

    addSubscriptionSourceState ip-edge "IP Edge" 203.0.113.10 39778
    jq -e '.sources[] | select(.id == "ip-edge" and .scheme == "wireguard" and .transport == "wireguard" and .host == "203.0.113.10" and .port == 39778)' "$(subscriptionGroupsFile)" >/dev/null
    removeSubscriptionSourceState ip-edge

    addUserSubscriptionState team-a "Team A" '["main"]' 7
    jq -e '.user_groups == [{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["main"],"traffic_limit_gb":7}]' "$(subscriptionGroupsFile)" >/dev/null
    if addUserSubscriptionState team-a Replacement '["*"]' 99 >/dev/null 2>&1; then
        return 1
    fi
    jq -e '.user_groups == [{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["main"],"traffic_limit_gb":7}]' "$(subscriptionGroupsFile)" >/dev/null
    if toggleUserSubscriptionState missing >/dev/null 2>&1 ||
        setUserSubscriptionSources missing '["main"]' >/dev/null 2>&1 ||
        setUserSubscriptionTrafficLimit missing 1 >/dev/null 2>&1 ||
        setUserSubscriptionEnabled missing false >/dev/null 2>&1 ||
        removeUserSubscriptionState missing >/dev/null 2>&1; then
        return 1
    fi
    longId=$(printf 'a%.0s' {1..65})
    subscriptionStateIdValid "${longId%a}"
    regressionExpectStatus 1 subscriptionStateIdValid "${longId}" >/dev/null 2>&1
    regressionExpectStatus 1 subscriptionApplyUserGroupState \
        '[{"id":"team-a","uuid":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"},{"id":"team-b","uuid":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}]' '[]' >/dev/null 2>&1
}

runSubscriptionGroupStateStructureFoundationCredentialRegression() {
    local credential decodedCredential invalidCredential encodedPayload payload
    local publicKey='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
    local inviteId='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    local receiptToken='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789AB'
    credential=$(subscriptionWireGuardCredentialEncode controlled '{"address":"10.77.0.2/24","public_key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","control_port":39778,"token":"token-abc"}')
    decodedCredential=$(subscriptionWireGuardCredentialDecode "${credential}")
    jq -e '.kind == "controlled" and .address == "10.77.0.2/24" and .control_port == 39778 and .token == "token-abc"' <<<"${decodedCredential}" >/dev/null
    if subscriptionWireGuardCredentialDecode "remote.example.com:39778:token-abc" >/dev/null 2>&1; then
        return 1
    fi
    for payload in \
        '{"address":"10.77.0.2/24","public_key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","control_port":39778}' \
        '{"address":"10.77.999.2/24","public_key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","control_port":39778,"token":"token-abc"}' \
        '{"address":"10.77.0.2/24","public_key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","control_port":70000,"token":"token-abc"}'; do
        invalidCredential=$(subscriptionWireGuardCredentialEncode controlled "${payload}")
        regressionExpectFailure subscriptionWireGuardCredentialDecode "${invalidCredential}" >/dev/null 2>&1
    done

    credential=$(subscriptionWireGuardCredentialEncode main "$(jq -cn --arg publicKey "${publicKey}" '{endpoint_host:"main.example.com",listen_port:51820,network:"10.77.0.0/24",address:"10.77.0.1/24",public_key:$publicKey}')")
    subscriptionWireGuardCredentialDecode "${credential}" | jq -e '.kind == "main" and .address == "10.77.0.1/24"' >/dev/null
    credential=$(subscriptionWireGuardCredentialEncode invite "$(jq -cn --arg inviteId "${inviteId}" --arg publicKey "${publicKey}" '{invite_id:$inviteId,alias:"hk-1",address:"10.77.0.2/24",network:"10.77.0.0/24",main_address:"10.77.0.1/24",endpoint_host:"main.example.com",listen_port:51820,main_public_key:$publicKey,expires_at:1780000000}')")
    subscriptionWireGuardCredentialDecode "${credential}" | jq -e '.kind == "invite" and .invite_id == $inviteId and .alias == "hk-1"' --arg inviteId "${inviteId}" >/dev/null
    credential=$(subscriptionWireGuardCredentialEncode receipt "$(jq -cn --arg inviteId "${inviteId}" --arg publicKey "${publicKey}" --arg token "${receiptToken}" '{invite_id:$inviteId,public_key:$publicKey,control_port:39778,token:$token}')")
    subscriptionWireGuardCredentialDecode "${credential}" | jq -e '.kind == "receipt" and .token == $token' --arg token "${receiptToken}" >/dev/null

    invalidCredential=$(subscriptionWireGuardCredentialEncode receipt "$(jq -cn --arg inviteId "${inviteId}" --arg publicKey "${publicKey}" '{invite_id:$inviteId,public_key:$publicKey,control_port:39778,token:"token-abc"}')")
    if subscriptionWireGuardCredentialDecode "${invalidCredential}" >/dev/null 2>&1; then
        return 1
    fi
    invalidCredential=$(subscriptionWireGuardCredentialEncode controlled "$(jq -cn --arg publicKey "${publicKey}" '{address:"10.77.0.2/24",public_key:$publicKey,control_port:39778,token:"token-abc",extra:true}')")
    if subscriptionWireGuardCredentialDecode "${invalidCredential}" >/dev/null 2>&1; then
        return 1
    fi
    for invalidCredential in "padmwg1:abc=" " padmwg1:abc" "padmwg1:$(printf 'A%.0s' {1..4090})"; do
        regressionExpectFailure subscriptionWireGuardCredentialDecode "${invalidCredential}" >/dev/null 2>&1
    done
    for payload in '{}{}' '[]'; do
        encodedPayload=$(printf '%s' "${payload}" | subscriptionWireGuardBase64UrlEncode)
        regressionExpectFailure subscriptionWireGuardCredentialDecode "padmwg1:${encodedPayload}" >/dev/null 2>&1
    done
    invalidCredential=$(subscriptionWireGuardCredentialEncode unknown '{}')
    if subscriptionWireGuardCredentialDecode "${invalidCredential}" >/dev/null 2>&1; then
        return 1
    fi

    local mainState controlledState invalidState
    mainState=$(jq -cn --arg publicKey "${publicKey}" --arg inviteId "${inviteId}" '{enabled:true,role:"main",interface:"wg-padm",network:"10.77.0.0/24",listen_port:51820,control_port:39778,firewall_owned:false,address:"10.77.0.1/24",endpoint_host:"main.example.com",public_key:$publicKey,peers:[],pending_invites:[{invite_id:$inviteId,alias:"hk-1",address:"10.77.0.2/24",expires_at:1780000000}]}')
    subscriptionWireGuardValidateState "${mainState}"
    controlledState=$(jq -cn --arg publicKey "${publicKey}" --arg inviteId "${inviteId}" '{enabled:true,role:"controlled",interface:"wg-padm",network:"10.77.0.0/24",listen_port:51820,control_port:39778,firewall_owned:false,address:"10.77.0.2/24",endpoint_host:"",public_key:$publicKey,peers:[],join_invite_id:$inviteId}')
    subscriptionWireGuardValidateState "${controlledState}"
    invalidState=$(jq '.role = "controlled"' <<<"${mainState}")
    if subscriptionWireGuardValidateState "${invalidState}" >/dev/null 2>&1; then
        return 1
    fi
    invalidState=$(jq '.pending_invites += [.pending_invites[0]]' <<<"${mainState}")
    if subscriptionWireGuardValidateState "${invalidState}" >/dev/null 2>&1; then
        return 1
    fi
    invalidState=$(jq '.pending_invites[0].alias = "main"' <<<"${mainState}")
    if subscriptionWireGuardValidateState "${invalidState}" >/dev/null 2>&1; then
        return 1
    fi
    invalidState=$(jq '.join_invite_id = "bad"' <<<"${controlledState}")
    if subscriptionWireGuardValidateState "${invalidState}" >/dev/null 2>&1; then
        return 1
    fi
}

runSubscriptionGroupStateStructureFoundationNormalizeRegression() {
    local accountDashUnderscore
    local accountUnderscoreDash
    local accountDashDash
    if normalizeSubscriptionSourceInput 'remote.example.com:443:edge' >/dev/null 2>&1; then
        return 1
    fi
    if normalizeSubscriptionSourceInput '203.0.113.10:39778:vps1' >/dev/null 2>&1; then
        return 1
    fi
    accountDashUnderscore=$(subscriptionSyncAccountName 'team-a_b')
    accountUnderscoreDash=$(subscriptionSyncAccountName 'team_a-b')
    accountDashDash=$(subscriptionSyncAccountName 'team-a-b')
    [[ "${accountDashUnderscore}" != "${accountUnderscoreDash}" ]]
    [[ "${accountDashUnderscore}" != "${accountDashDash}" ]]
    [[ "${accountUnderscoreDash}" != "${accountDashDash}" ]]
    [[ "$(subscriptionSyncAccountIdFromName "${accountDashUnderscore}")" == "team-a_b" ]]
    [[ "$(subscriptionSyncAccountIdFromName "${accountUnderscoreDash}")" == "team_a-b" ]]
    [[ "$(subscriptionSyncAccountIdFromName "${accountDashDash}")" == "team-a-b" ]]
}

runSubscriptionGroupStateStructureFoundationInitTransactionRegression() (
    local initRoot="${TMP_DIR}/subscription-state-init-transaction"
    local initGroupsDir="${initRoot}/groups"
    local initStateFile="${initGroupsDir}/groups.json"
    local initWireGuardDir="${initRoot}/wireguard"
    local initWireGuardStateFile="${initWireGuardDir}/control.json"
    local initStatus

    export PADM_SUBSCRIPTION_GROUPS_DIR="${initGroupsDir}"
    mkdir -p "${initRoot}"

    mkdir -p "${initGroupsDir}"
    printf '{existing-bad-json\n' >"${initStateFile}"
    regressionExpectStatus 1 ensureSubscriptionGroupsState >/dev/null 2>&1
    grep -qxF '{existing-bad-json' "${initStateFile}"
    rm -rf "${initGroupsDir}"

    export PADM_WIREGUARD_CONTROL_DIR="${initWireGuardDir}"
    mkdir -p "${initWireGuardDir}"
    printf '{existing-bad-json\n' >"${initWireGuardStateFile}"
    regressionExpectStatus 1 subscriptionWireGuardReadState >/dev/null 2>&1
    regressionExpectStatus 1 subscriptionWireGuardWriteState '.enabled = true' >/dev/null 2>&1
    grep -qxF '{existing-bad-json' "${initWireGuardStateFile}"

    writeDefaultSubscriptionGroupsState() {
        printf '{bad-json\n' >"$1"
        return 1
    }

    regressionExpectStatus 1 ensureSubscriptionGroupsState >/dev/null 2>&1
    [[ ! -e "${initStateFile}" ]]
    if regressionFindHasMatches "${initGroupsDir}" -maxdepth 1 -type f -name '.groups.json.init.*'; then
        return 1
    fi

)

runSubscriptionGroupStateStructureValidationRegression() {
    local beforeSnapshot
    local invalidFilter
    local invalidSnapshot
    local migrationSnapshot
    local stateFile
    mkdir -p "$(subscriptionGroupsDir)"
    stateFile=$(subscriptionGroupsFile)
    writeDefaultSubscriptionGroupsState "${stateFile}"
    ensureSubscriptionGroupsState

    for invalidFilter in '.sources[0] |= del(.transport)' '.version = 1'; do
        writeDefaultSubscriptionGroupsState "${stateFile}"
        invalidSnapshot=$(jq "${invalidFilter}" "${stateFile}")
        printf '%s\n' "${invalidSnapshot}" >"${stateFile}"
        regressionExpectFailure ensureSubscriptionGroupsState >/dev/null 2>&1
        [[ "$(<"${stateFile}")" == "${invalidSnapshot}" ]]
    done

    for invalidFilter in \
        '.unexpected = true' \
        '.user_groups += [{"id":"bad","name":"Bad","enabled":true,"allowed_sources":["main"],"traffic_limit_gb":0,"token":""}]' \
        '.user_groups += [{"id":"bad","name":"Bad","enabled":true,"allowed_sources":["missing-source"],"traffic_limit_gb":0,"token":""}]' \
        '.user_groups += [{"id":"dup","name":"Dup","enabled":true,"allowed_sources":["main"],"traffic_limit_gb":0,"uuid":"11111111-1111-1111-1111-111111111111"},{"id":"dup","name":"Dup 2","enabled":true,"allowed_sources":["main"],"traffic_limit_gb":0,"uuid":"22222222-2222-2222-2222-222222222222"}]' \
        '.user_groups += [{"id":"uuid-a","name":"UUID A","enabled":true,"allowed_sources":["main"],"traffic_limit_gb":0,"uuid":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"},{"id":"uuid-b","name":"UUID B","enabled":true,"allowed_sources":["main"],"traffic_limit_gb":0,"uuid":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}]' \
        '.sources += [{"id":"main","name":"Duplicate Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}]' \
        'del(.sources[0].transport)' \
        '.sync.remote_enabled = true'; do
        writeDefaultSubscriptionGroupsState "${stateFile}"
        beforeSnapshot=$(<"${stateFile}")
        if subscriptionGroupsStateWrite "${invalidFilter}" >/dev/null 2>&1; then
            return 1
        fi
        [[ "$(<"${stateFile}")" == "${beforeSnapshot}" ]]
    done

    if subscriptionGroupsStateWrite '.sync.interval_minutes = 60' >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(<"${stateFile}")" == "${beforeSnapshot}" ]]

    jq '
      . as $state |
      .version = 3 |
      .active_group = $state.id |
      .groups = [{
        id: $state.id,
        name: $state.name,
        sources: $state.sources,
        user_groups: [{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*","main","ghost"],"traffic_limit_gb":0}],
        sync: $state.sync,
        traffic: {
          global:{upload:999,download:999},
          admin:{upload:999,download:999,sources:{main:{upload:3,download:4},ghost:{upload:90,download:91}}},
          user_groups:{"team-a":{upload:999,download:999,sources:{main:{upload:5,download:6},ghost:{upload:70,download:71}}},ghost:{upload:1,download:1,sources:{}}},
          sources:{main:{upload:8,download:10},ghost:{upload:80,download:81}}
        }
      }] |
      del(.id, .name, .sources, .user_groups, .sync, .traffic)
    ' "${stateFile}" >"${stateFile}.v3"
    mv "${stateFile}.v3" "${stateFile}"
    ensureSubscriptionGroupsState
    jq -e '
      .version == 5 and
      .user_groups[0].allowed_sources == ["*"] and
      (.traffic | has("global") | not) and
      (.traffic.admin | has("upload") | not) and
      (.traffic.user_groups["team-a"] | has("upload") | not) and
      .traffic.sources.main == {upload:8,download:10} and
      .traffic.admin.sources.main == {upload:3,download:4} and
      .traffic.user_groups["team-a"].sources.main == {upload:5,download:6} and
      (.traffic.sources | has("ghost") | not) and
      (.traffic.user_groups | has("ghost") | not)
    ' "${stateFile}" >/dev/null
    regressionFindHasMatches "$(subscriptionGroupsBackupDir)" -maxdepth 1 -type f -name 'groups-pre-v4-migration-*.json'

    jq '
      . as $state |
      .version = 3 |
      .active_group = $state.id |
      .groups = [($state | {id, name, sources, user_groups, sync, traffic:"broken"})] |
      del(.id, .name, .sources, .user_groups, .sync, .traffic)
    ' "${stateFile}" >"${stateFile}.invalid-traffic"
    mv "${stateFile}.invalid-traffic" "${stateFile}"
    migrationSnapshot=$(<"${stateFile}")
    regressionExpectFailure ensureSubscriptionGroupsState >/dev/null 2>&1
    [[ "$(<"${stateFile}")" == "${migrationSnapshot}" ]]

    jq '.groups[0].user_groups[0].id = "unsafe/id"' "${stateFile}" >"${stateFile}.invalid"
    mv "${stateFile}.invalid" "${stateFile}"
    migrationSnapshot=$(<"${stateFile}")
    regressionExpectFailure ensureSubscriptionGroupsState >/dev/null 2>&1
    [[ "$(<"${stateFile}")" == "${migrationSnapshot}" ]]
}

runSubscriptionGroupStateStructureSourceCredentialRegression() {
    mkdir -p "$(subscriptionGroupsDir)"
    writeSubscriptionStateSourceCredentialFixture
    subscriptionActiveGroupWrite --arg id remote-edge --arg token "token-abc" '
      .sources |= map(if .id == $id and .role != "main" then .control_token = $token else . end)'
    jq -e '.sources[] | select(.id == "remote-edge" and .scheme == "wireguard" and .transport == "wireguard" and .host == "10.77.0.2" and .port == 39778 and .control_token == "token-abc")' "$(subscriptionGroupsFile)" >/dev/null
    setSubscriptionSourceCredential remote-edge "10.77.0.3" 48779 "token-def"
    jq -e '.sources[] | select(.id == "remote-edge" and .scheme == "wireguard" and .transport == "wireguard" and .host == "10.77.0.3" and .port == 48779 and .control_token == "token-def")' "$(subscriptionGroupsFile)" >/dev/null
    if setSubscriptionSourceCredential missing "10.77.0.4" 48779 token >/dev/null 2>&1; then
        return 1
    fi
}

runSubscriptionGroupStateStructureSourceStatusRegression() {
    mkdir -p "$(subscriptionGroupsDir)"
    writeSubscriptionStateSourceStatusFixture
    subscriptionHasEnabledRemoteSources
    setSubscriptionSourceEnabled edge false
    jq -e '.sources[] | select(.id == "edge" and .enabled == false)' "$(subscriptionGroupsFile)" >/dev/null
    if subscriptionHasEnabledRemoteSources; then
        return 1
    fi
    if setSubscriptionSourceEnabled main false >/dev/null 2>&1 || setSubscriptionSourceEnabled missing true >/dev/null 2>&1; then
        return 1
    fi
    jq -e '.sources[] | select(.id == "main" and .enabled == true)' "$(subscriptionGroupsFile)" >/dev/null
    setSubscriptionSourceEnabled edge true
    subscriptionHasEnabledRemoteSources
    if setSubscriptionSourceSyncStatus missing success >/dev/null 2>&1 ||
        setSubscriptionSourceSyncFailure missing unreachable error >/dev/null 2>&1; then
        return 1
    fi
}

runSubscriptionGroupStateStructureSyncCronRegression() {
    mkdir -p "$(subscriptionGroupsDir)"
    writeSubscriptionStateSourceStatusFixture
    setSubscriptionGroupSyncInterval 17
    (
        local crontabLog="${TMP_DIR}/subscription-sync-crontab.txt"
        local crontabReadMode=default
        local crontabInstallShouldFail=false
        local syncCalls=0
        crontab() {
            case "${1:-}" in
            -l)
                case "${crontabReadMode}" in
                no-crontab)
                    printf 'no crontab for root\n' >&2
                    return 1
                    ;;
                busybox-no-crontab)
                    printf "crontab: can't open 'root': No such file or directory\n" >&2
                    return 1
                    ;;
                failure)
                    printf 'crontab read failed\n' >&2
                    return 2
                    ;;
                tls-mixed)
                    printf '45 2 * * * /bin/bash /etc/padm/install.sh RenewTLS old\n'
                    printf '35 1 * * * /bin/bash /etc/padm/install.sh UpdateGeo\n'
                    printf '*/10 * * * * /bin/bash /etc/padm/install.sh SyncSubscriptionGroups\n'
                    printf '0 0 * * * /root/.acme.sh/acme.sh --cron\n'
                    printf '5 5 * * * /usr/local/bin/keep\n'
                    ;;
                *)
                    printf '5 0 * * * /bin/bash /etc/padm/install.sh RenewTLS\n'
                    printf '10 0 * * * /bin/bash /etc/padm/install.sh SyncSubscriptionGroups old\n'
                    ;;
                esac
                ;;
            *)
                [[ "${crontabInstallShouldFail}" != "true" ]] || return 1
                cat "$1" >"${crontabLog}"
                ;;
            esac
        }
        installSubscriptionGroupSyncCron
        grep -qx '5 0 \* \* \* /bin/bash /etc/padm/install.sh RenewTLS' "${crontabLog}" || return 1
        grep -qxF '* * * * * padm_minute=$(( $(date +\%s) / 60 )); [ $((padm_minute / 17 * 17)) -eq "$padm_minute" ] && /bin/bash /etc/padm/install.sh SyncSubscriptionGroups >> /etc/padm/crontab_subscription_groups.log 2>&1' "${crontabLog}" || return 1
        [[ "$(grep -c 'SyncSubscriptionGroups' "${crontabLog}")" == "1" ]] || return 1

        setSubscriptionGroupSyncInterval 59
        [[ "$(subscriptionGroupSyncCronCommand)" == '* * * * * padm_minute=$(( $(date +\%s) / 60 )); [ $((padm_minute / 59 * 59)) -eq "$padm_minute" ] && /bin/bash /etc/padm/install.sh SyncSubscriptionGroups >> /etc/padm/crontab_subscription_groups.log 2>&1' ]]
        setSubscriptionGroupSyncInterval 17

        setSubscriptionGroupSyncEnabled false
        refreshSubscriptionGroupSyncCron
        grep -qx '5 0 \* \* \* /bin/bash /etc/padm/install.sh RenewTLS' "${crontabLog}" || return 1
        ! grep -q 'SyncSubscriptionGroups' "${crontabLog}" || return 1

        for crontabReadMode in no-crontab busybox-no-crontab; do
            [[ -z "$(readUserCrontabContent)" ]]
        done
        crontabReadMode=failure
        if readUserCrontabContent >/dev/null 2>&1; then
            return 1
        fi

        crontabReadMode=default
        crontabInstallShouldFail=true
        if setSubscriptionGroupSyncEnabledWithCron true >/dev/null 2>&1; then
            return 1
        fi
        subscriptionActiveGroupRead -e '.sync.enabled == false' >/dev/null

        runSubscriptionGroupSync() { syncCalls=$((syncCalls + 1)); }
        runSubscriptionGroupSyncCron
        [[ "${syncCalls}" == "0" ]]

        crontabInstallShouldFail=false
        crontabReadMode=tls-mixed
        btDomain=
        installCronTLS 1 >/dev/null
        grep -qx '35 1 \* \* \* /bin/bash /etc/padm/install.sh UpdateGeo' "${crontabLog}"
        grep -qx '\*/10 \* \* \* \* /bin/bash /etc/padm/install.sh SyncSubscriptionGroups' "${crontabLog}"
        grep -qx '0 0 \* \* \* /root/.acme.sh/acme.sh --cron' "${crontabLog}"
        grep -qx '5 5 \* \* \* /usr/local/bin/keep' "${crontabLog}"
        [[ "$(grep -c '/etc/padm/install.sh RenewTLS' "${crontabLog}")" == "1" ]]
        ! grep -q 'RenewTLS old' "${crontabLog}"
    )
}

runSubscriptionGroupStateStructureSourceRemoveRegression() {
    mkdir -p "$(subscriptionGroupsDir)"
    writeSubscriptionStateSourceRemoveFixture
    if removeSubscriptionSourceState edge >/dev/null 2>&1; then
        return 1
    fi
    jq -e '.sources | map(.id) | index("edge")' "$(subscriptionGroupsFile)" >/dev/null
    setUserSubscriptionSources team-a '["*"]'
    if removeSubscriptionSourceState edge >/dev/null 2>&1; then
        return 1
    fi
    jq -e '.sources | map(.id) | index("edge")' "$(subscriptionGroupsFile)" >/dev/null
    setUserSubscriptionSources team-a '["main"]'
    removeSubscriptionSourceState edge
    jq -e '
      (.sources | map(.id) | index("edge") | not) and
      (.traffic.sources | has("edge") | not) and
      (.traffic.user_groups["team-a"].sources | has("edge") | not) and
      (.traffic | has("global") | not) and
      .traffic.user_groups["team-a"] == {sources:{}}
    ' "$(subscriptionGroupsFile)" >/dev/null
}

runSubscriptionGroupStateQuotaTrafficSummaryRegression() {
    prepareSubscriptionStateQuotaUsageFixture
    (
        local trafficOutput
        menuLine() { printf 'menu:%s\n' "$*"; }
        trafficOutput=$(showAdminSubscriptionTraffic)
        [[ "${trafficOutput}" == *"总上传：2 MB"* ]]
        [[ "${trafficOutput}" == *"总下载：1 MB"* ]]
        [[ "${trafficOutput}" == *"来源数：1"* ]]
        trafficOutput=$(showSubscriptionSourcesTraffic)
        [[ "${trafficOutput}" == *"服务器数：2"* ]]
        [[ "${trafficOutput}" == *"总上传：3 MB"* ]]
        [[ "${trafficOutput}" == *"总下载：1 MB"* ]]
        [[ "${trafficOutput}" == *"最近更新：2026-06-10 10:01:00"* ]]
        trafficOutput=$(showSubscriptionTrafficOverview)
        [[ "${trafficOutput}" == *"流量更新时间：2026-06-10 10:01:00"* ]]
        subscriptionGroupsStateSummaryJson | jq -e '.traffic_updated_at == "2026-06-10 10:01:00"' >/dev/null
    )
    subscriptionQuotaDryRunPlan | jq -e 'length == 1 and .[0].id == "team-a" and .[0].limit_gb == 1 and .[0].percent >= 100 and .[0].action == "disable-and-remove-local-account"' >/dev/null
}

runSubscriptionGroupStateQuotaTrafficRemoteRegression() {
    local localSnapshot
    local remoteResults
    local stateBefore
    local mainBefore
    prepareSubscriptionStateQuotaUsageFixture
    subscriptionActiveGroupWrite '
      .sources += [{id:"edge-2",name:"edge-2",role:"secondary",scheme:"wireguard",transport:"wireguard",host:"10.77.0.4",port:48780,enabled:true,sync_status:"pending",control_token:"token-ghi"}] |
      .traffic = {admin:{sources:{}},user_groups:{},sources:{}}
    '
    localSnapshot='{"ok":true,"items":[{"account":"admin","upload":10,"download":20},{"account":"sub_team_a","upload":30,"download":40}]}'
    remoteResults='[{"source_id":"remote-edge","status":"success","response":{"items":[{"account":"admin","upload":5,"download":6},{"account":"sub_team_a","upload":7,"download":8}]}},{"source_id":"edge-2","status":"success","response":{"items":[{"account":"admin","upload":2,"download":3},{"account":"sub_team_a","upload":4,"download":5}]}}]'
    writeSubscriptionTrafficSnapshot "${localSnapshot}" "${remoteResults}"
    jq -e '
      (.traffic.sources | length) == 3 and
      .traffic.admin.sources["remote-edge"].upload == 5 and
      .traffic.user_groups["team-a"].sources["remote-edge"].upload == 7 and
      .traffic.sources["edge-2"].upload == 6 and
      .traffic.sources["edge-2"].counters.sub_team_a.upload == 4 and
      (.traffic | has("global") | not) and
      (.traffic.admin | has("upload") | not) and
      (.traffic.user_groups["team-a"] | has("upload") | not)
    ' "$(subscriptionGroupsFile)" >/dev/null

    localSnapshot='{"ok":true,"items":[{"account":"admin","upload":3,"download":4},{"account":"sub_team_a","upload":1,"download":2}]}'
    remoteResults='[{"source_id":"remote-edge","status":"success","response":{"items":[{"account":"admin","upload":1,"download":1},{"account":"sub_team_a","upload":2,"download":1}]}},{"source_id":"edge-2","status":"success","response":{"items":[{"account":"admin","upload":3,"download":1},{"account":"sub_team_a","upload":1,"download":2}]}}]'
    writeSubscriptionTrafficSnapshot "${localSnapshot}" "${remoteResults}"
    jq -e '
      .traffic.sources.main.upload == 44 and
      .traffic.admin.sources.main.upload == 13 and
      .traffic.user_groups["team-a"].sources.main.upload == 31 and
      (.traffic | has("global") | not) and
      (.traffic.admin | has("upload") | not) and
      (.traffic.user_groups["team-a"] | has("upload") | not)
    ' "$(subscriptionGroupsFile)" >/dev/null

    stateBefore=$(jq -c '.traffic' "$(subscriptionGroupsFile)")
    remoteResults='[{"source_id":"remote-edge","status":"unreachable"},{"source_id":"edge-2","status":"success","response":{"items":[{"account":"admin","upload":4,"download":2},{"account":"sub_team_a","upload":2,"download":3}]}}]'
    if writeSubscriptionTrafficSnapshot '{"ok":true,"items":[{"account":"admin","upload":4,"download":5},{"account":"sub_team_a","upload":2,"download":3}]}' "${remoteResults}" >/dev/null 2>&1; then
        return 1
    fi
    jq -e --argjson stateBefore "${stateBefore}" '.traffic == $stateBefore' "$(subscriptionGroupsFile)" >/dev/null

    stateBefore=$(jq -c '.traffic' "$(subscriptionGroupsFile)")
    remoteResults='[{"source_id":"remote-edge","status":"success","response":{"items":[]}}]'
    if writeSubscriptionTrafficSnapshot '{"ok":true,"items":[]}' "${remoteResults}" >/dev/null 2>&1; then
        return 1
    fi
    jq -e --argjson stateBefore "${stateBefore}" '.traffic == $stateBefore' "$(subscriptionGroupsFile)" >/dev/null

    setSubscriptionSourceEnabled remote-edge false
    setSubscriptionSourceEnabled edge-2 false
    mainBefore=$(jq -r '.traffic.sources.main.upload' "$(subscriptionGroupsFile)")
    writeSubscriptionTrafficSnapshot '{"ok":true,"items":[]}' '[]'
    writeSubscriptionTrafficSnapshot '{"ok":true,"items":[{"account":"admin","upload":5,"download":5},{"account":"sub_team_a","upload":3,"download":3}]}' '[]'
    jq -e --argjson mainBefore "${mainBefore}" '.traffic.sources.main.upload == ($mainBefore + 4)' "$(subscriptionGroupsFile)" >/dev/null

    setUserSubscriptionSources team-a '["main"]'
    removeSubscriptionSourceState edge-2
    stateBefore=$(jq -c '.traffic' "$(subscriptionGroupsFile)")
    remoteResults='[{"source_id":"edge-2","status":"success","response":{"items":[{"account":"admin","upload":99,"download":99}]}}]'
    if writeSubscriptionTrafficSnapshot '{"ok":true,"items":[{"account":"admin","upload":3,"download":4},{"account":"sub_team_a","upload":1,"download":2}]}' "${remoteResults}" >/dev/null 2>&1; then
        return 1
    fi
    jq -e '
      (.traffic.sources | has("edge-2") | not) and
      (.traffic.admin.sources | has("edge-2") | not) and
      (.traffic.user_groups["team-a"].sources | has("edge-2") | not)
    ' "$(subscriptionGroupsFile)" >/dev/null
    jq -e --argjson stateBefore "${stateBefore}" '.traffic == $stateBefore' "$(subscriptionGroupsFile)" >/dev/null
}

runSubscriptionGroupStateQuotaTrafficInvalidInputRegression() {
    prepareSubscriptionStateQuotaUsageFixture
    if applySubscriptionQuotaPlan '{bad-json' 2>/dev/null; then
        return 1
    fi
    if applySubscriptionQuotaPlan '[{"id":"","action":"disable-and-remove-local-account"}]' 2>/dev/null; then
        return 1
    fi
    if applySubscriptionQuotaPlan '[{"id":"missing","action":"disable-and-remove-local-account"}]' 2>/dev/null; then
        return 1
    fi
    if subscriptionSyncApplyAccountPlan '{bad-json' 2>/dev/null; then
        return 1
    fi
    if subscriptionSyncApplyAccountPlan '{"create":["sub_team_a"],"remove":[null]}' 2>/dev/null; then
        return 1
    fi
}

runSubscriptionGroupStateQuotaTrafficApplyRegression() {
    prepareSubscriptionStateQuotaUsageFixture
    applySubscriptionQuotaPlan "$(subscriptionQuotaDryRunPlan)"
    jq -e '.user_groups[] | select(.id == "team-a" and .enabled == false)' "$(subscriptionGroupsFile)" >/dev/null
}

runSubscriptionGroupStateQuotaMenuPreviewFailureRegression() {
    prepareSubscriptionStateQuotaUsageFixture
    (
        local quotaMenuOutput
        local quotaMenuStatus
        menuLine() { printf 'menu:%s\n' "$*"; }
        subscriptionSyncApplyAccountPlanTransaction() {
            return 42
        }
        reloadCore() {
            return 0
        }
        set +e
        quotaMenuOutput=$(executeSubscriptionQuotaPlanMenu <<<"yes" 2>/dev/null)
        quotaMenuStatus=$?
        set -e
        if [[ "${quotaMenuStatus}" -eq 0 ]]; then
            return 1
        fi
        [[ "${quotaMenuOutput}" == *"待处理订阅：1"* ]]
        [[ "${quotaMenuOutput}" == *"动作：停用超额订阅并移除本机托管账号"* ]]
    )
}

runSubscriptionGroupStateQuotaTransactionRollbackRegression() {
    (
        local quotaTxRoot="${TMP_DIR}/subscription-quota-transaction"
        local quotaTxPlan
        local quotaTxStatus
        local quotaTxStateFile
        local quotaTxBackupDir
        local quotaTxLockMarker="${quotaTxRoot}/lock-observed"
        mkdir -p "${quotaTxRoot}/groups"
        export PADM_SUBSCRIPTION_GROUPS_DIR="${quotaTxRoot}/groups"
        quotaTxStateFile=$(subscriptionGroupsFile)
        quotaTxBackupDir="$(subscriptionGroupsBackupDir)"
        cat >"${quotaTxStateFile}" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":1,"token":"","uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{"team-a":{"upload":1073741824,"download":1,"sources":{"main":{"upload":1073741824,"download":1}}}},"sources":{"main":{"upload":2097152,"download":1048576,"updated_at":"2026-06-10 10:00:00"}}}}]}
JSON
        quotaTxPlan=$(subscriptionQuotaDryRunPlan)
        createSubscriptionGroupsBackup() {
            local backupFile="${quotaTxBackupDir}/groups-current.json"
            [[ "${SUBSCRIPTION_GROUPS_LOCK_HELD:-}" == "1" ]] && : >"${quotaTxLockMarker}"
            mkdir -p "${quotaTxBackupDir}" || return 1
            cp "${quotaTxStateFile}" "${backupFile}" || return 1
            printf '%s\n' "${backupFile}"
        }
        restoreSubscriptionGroupsBackup() {
            local backupFile=$1
            [[ -f "${backupFile}" ]] || return 1
            cp "${backupFile}" "${quotaTxStateFile}" || return 1
        }
        subscriptionSyncApplyAccountPlanTransaction() {
            return 1
        }
        regressionExpectStatus 1 applySubscriptionQuotaPlanTransaction "${quotaTxPlan}"
        [[ -e "${quotaTxLockMarker}" ]]
        jq -e '.user_groups[] | select(.id == "team-a" and .enabled == true)' "$(subscriptionGroupsFile)" >/dev/null
        [[ "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR}" == *"已恢复旧订阅状态"* ]]
        if regressionFindHasMatches "${quotaTxRoot}/groups/backups" -maxdepth 1 -type f -name 'groups-[0-9]*.json'; then
            return 1
        fi
    )
}

runSubscriptionGroupStateQuotaTransactionRecheckRegression() (
    local confirmedPlan='[{"id":"team-a","action":"disable-and-remove-local-account"}]'
    local mutationMarker="${TMP_DIR}/subscription-quota-recheck-mutated"

    subscriptionQuotaDryRunPlan() {
        printf '%s\n' '[{"id":"team-b","action":"disable-and-remove-local-account"}]'
    }
    createSubscriptionGroupsBackup() {
        : >"${mutationMarker}"
        return 1
    }
    setUserSubscriptionEnabled() {
        : >"${mutationMarker}"
        return 1
    }

    regressionExpectStatus 0 applySubscriptionQuotaPlanTransaction "${confirmedPlan}"
    [[ ! -e "${mutationMarker}" ]]
)

runSubscriptionGroupStateQuotaPartialSyncApplyFailureRegression() {
    (
        local quotaPartialRoot="${TMP_DIR}/subscription-quota-partial-state-failure"
        local quotaPartialPlan='[{"id":"team-a","action":"disable-and-remove-local-account"},{"id":"team-b","action":"disable-and-remove-local-account"}]'
        local quotaPartialStatus
        local accountPhaseMarker="${quotaPartialRoot}/account-phase-called"
        local quotaPartialStateFile
        local quotaPartialBackupDir
        mkdir -p "${quotaPartialRoot}/groups"
        export PADM_SUBSCRIPTION_GROUPS_DIR="${quotaPartialRoot}/groups"
        quotaPartialStateFile=$(subscriptionGroupsFile)
        quotaPartialBackupDir=$(subscriptionGroupsBackupDir)
        cat >"${quotaPartialStateFile}" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":1,"token":"","uuid":"11111111-1111-1111-1111-111111111111"},{"id":"team-b","name":"Team B","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":1,"token":"","uuid":"22222222-2222-2222-2222-222222222222"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
        createSubscriptionGroupsBackup() {
            local backupFile="${quotaPartialBackupDir}/groups-current.json"
            mkdir -p "${quotaPartialBackupDir}" || return 1
            cp "${quotaPartialStateFile}" "${backupFile}" || return 1
            printf '%s\n' "${backupFile}"
        }
        restoreSubscriptionGroupsBackup() {
            local backupFile=$1
            [[ -f "${backupFile}" ]] || return 1
            cp "${backupFile}" "${quotaPartialStateFile}" || return 1
        }
        setUserSubscriptionEnabled() {
            local id=$1
            local enabled=$2
            if [[ "${id}" == "team-b" ]]; then
                return 1
            fi
            subscriptionGroupsStateWrite --arg id "${id}" --argjson enabled "${enabled}" '.user_groups |= map(if .id == $id then .enabled = $enabled else . end)'
        }
        subscriptionSyncApplyAccountPlanTransaction() {
            printf 'called\n' >"${accountPhaseMarker}"
            return 0
        }
        subscriptionQuotaDryRunPlan() {
            printf '%s\n' "${quotaPartialPlan}"
        }
        regressionExpectStatus 1 applySubscriptionQuotaPlanTransaction "${quotaPartialPlan}"
        jq -e '.user_groups[] | select(.id == "team-a" and .enabled == true)' "$(subscriptionGroupsFile)" >/dev/null
        jq -e '.user_groups[] | select(.id == "team-b" and .enabled == true)' "$(subscriptionGroupsFile)" >/dev/null
        [[ ! -e "${accountPhaseMarker}" ]]
        [[ "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR}" == *"停用超额分享订阅失败"* ]]
        if regressionFindHasMatches "${quotaPartialRoot}/groups/backups" -maxdepth 1 -type f -name 'groups-[0-9]*.json'; then
            return 1
        fi
    )
}

runSubscriptionGroupStateQuotaPartialSyncPlanRegression() {
    (
        local capturedSyncPlanIds="${TMP_DIR}/subscription-state-quota-partial-sync-plan-ids.txt"
        local capturedSyncPlanMode="${TMP_DIR}/subscription-state-quota-partial-sync-plan-mode.txt"
        subscriptionSyncDesiredLocalUsers() {
            return 96
        }
        subscriptionActiveEnabledUsersJson() {
            printf '[{"id":"team-a","allowed_sources":["main"],"allows_main":true}]\n'
        }
        subscriptionSyncAccountPlanFromIds() {
            printf '%s\n' "$1" >"${capturedSyncPlanMode}"
            cat >"${capturedSyncPlanIds}"
            printf '{"create":[],"remove":["sub_team_a"]}\n'
        }
        subscriptionSyncPlan | jq -e '.remove | index("sub_team_a")' >/dev/null
        grep -qx 'sync' "${capturedSyncPlanMode}"
        grep -qx 'team-a' "${capturedSyncPlanIds}"
    )
}

runSubscriptionGroupStateQuotaPartialSyncConfigRegression() {
    local oldConfigPath="${configPath:-}"
    local oldSingBoxConfigPath="${singBoxConfigPath:-}"
    local syncConfigRoot="${TMP_DIR}/subscription-sync-config"
    configPath="${syncConfigRoot}/xray/"
    singBoxConfigPath="${syncConfigRoot}/sing-box/"
    mkdir -p "${configPath}" "${singBoxConfigPath}"
    cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_team_a-main"},{"email":"sub_team_b-main"},{"email":"sub_team_c-Trojan_TCP_direct"}]}}]}
JSON
    cat >"${singBoxConfigPath}06_hysteria2_inbounds.json" <<'JSON'
{"inbounds":[{"users":[{"name":"sub_team_a-main"},{"username":"sub_team_b-main"},{"name":"sub_team_c-shadowsocks"}]}]}
JSON
    (
        local capturedConfiguredAccountArgc="${TMP_DIR}/subscription-sync-configured-account-argc.txt"
        subscriptionSyncConfiguredManagedUsers() {
            printf '%s\n' "$#" >"${capturedConfiguredAccountArgc}"
            printf '["sub_team_a-main","sub_team_b-main"]\n'
        }
        subscriptionSyncPlanFromAccounts '["sub_team_a-main"]' | jq -e '.create == [] and .remove == ["sub_team_b-main"]' >/dev/null
        grep -qx '0' "${capturedConfiguredAccountArgc}"
    )
    subscriptionSyncCurrentManagedUsers \
        "${configPath}02_VLESS_TCP_inbounds.json" \
        "${singBoxConfigPath}06_hysteria2_inbounds.json" |
        jq -e '. == ["sub_team_a-main", "sub_team_b-main", "sub_team_c"]' >/dev/null
    subscriptionSyncPlanFromAccounts '["sub_team_a-main"]' | jq -e '.create == [] and .remove == ["sub_team_b-main", "sub_team_c"]' >/dev/null
    printf '{bad-json' >"${configPath}99_broken_inbounds.json"
    set +e
    subscriptionSyncPlanFromAccounts '["sub_team_a"]' >/dev/null 2>&1
    local brokenPlanStatus=$?
    set -e
    [[ "${brokenPlanStatus}" -ne 0 ]]
    rm -f "${configPath}99_broken_inbounds.json"
    configPath="${oldConfigPath}"
    singBoxConfigPath="${oldSingBoxConfigPath}"
    (
        runSubscriptionGroupSync() {
            printf '%s\n' "$*" >"${TMP_DIR}/subscription-group-sync-cron-args.log"
            return 23
        }
        set +e
        runSubscriptionGroupSyncCron
        local cronStatus=$?
        set -e
        [[ "${cronStatus}" -eq 23 ]]
        [[ -f "${TMP_DIR}/subscription-group-sync-cron-args.log" ]]
        [[ "$(<"${TMP_DIR}/subscription-group-sync-cron-args.log")" == "" ]]
    )
}

prepareSubscriptionRemoteRestoreSelfReferenceFixture() {
    currentHost="self.example.com"
    subscribeDomain="self.example.com"
    subscribePort=39778
    PADM_WIREGUARD_CONTROL_DIR="${TMP_DIR}/subscription-state-wireguard"
    mkdir -p "$(subscriptionWireGuardDir)"
    cat >"$(subscriptionWireGuardStateFile)" <<'JSON'
{"enabled":true,"role":"main","interface":"wg-padm","network":"10.77.0.0/24","listen_port":51820,"control_port":39778,"firewall_owned":false,"address":"10.77.0.1/24","endpoint_host":"self.example.com","public_key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","peers":[]}
JSON
    mkdir -p "$(subscriptionGroupsDir)"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"remote-edge","name":"remote-edge","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"10.77.0.3","port":48779,"enabled":false,"sync_status":"pending","control_token":"token-def"},{"id":"self-ref","name":"SelfRef","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"10.77.0.1","port":39778,"enabled":true,"sync_status":"pending","control_token":"token"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["self-ref"],"traffic_limit_gb":0,"token":"","uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
}

runSubscriptionGroupStateRemoteRestoreSelfReferencePlanRegression() {
    prepareSubscriptionRemoteRestoreSelfReferenceFixture
    subscriptionRemoteControlRequest() {
        return 19
    }
    subscriptionRemoteSyncPlan | jq -e '.[] | select(.source_id == "self-ref" and .status == "self_reference" and .error_detail.type == "self_reference")' >/dev/null
}

runSubscriptionGroupStateRemoteRestoreSelfReferenceSyncRegression() {
    prepareSubscriptionRemoteRestoreSelfReferenceFixture
    subscriptionRemoteControlRequest() {
        return 19
    }
    runSubscriptionRemoteSync | jq -e '.failures[] | contains("self-ref")' >/dev/null
    subscriptionGroupsStateRead -e '.sources[] | select(.id == "self-ref" and .sync_status == "failed" and .last_sync_error.type == "self_reference")' >/dev/null
}

runSubscriptionGroupStateRemoteRestoreStateWriteRegression() {
    mkdir -p "$(subscriptionGroupsDir)"
    writeSubscriptionStateDefaultFixture
    ensureSubscriptionGroupsState

    local stateSnapshot badBackup firstBackup secondBackup pid worker
    local workerCount=40
    local -a pids=()
    stateSnapshot=$(<"$(subscriptionGroupsFile)")
    if subscriptionGroupsStateWrite '.user_groups = "broken" | .dangling = ' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"$(subscriptionGroupsFile)")" == "${stateSnapshot}" ]]
    [[ ! -e "$(subscriptionGroupsFile).tmp" ]]
    [[ ! -e "$(subscriptionGroupsFile).tmp.commit" ]]

    badBackup="${TMP_DIR}/bad-groups-backup.json"
    printf '{bad json\n' >"${badBackup}"
    if restoreSubscriptionGroupsBackup "${badBackup}" 2>/dev/null; then
        return 1
    fi
    [[ "$(<"$(subscriptionGroupsFile)")" == "${stateSnapshot}" ]]
    [[ ! -e "$(subscriptionGroupsFile).restore.tmp" ]]

    case "${OSTYPE:-}" in
    msys* | cygwin* | win32*) workerCount=2 ;;
    esac
    for ((worker = 0; worker < workerCount; worker++)); do
        (
            trap - EXIT INT TERM
            PADM_CLEANUP_PATHS=()
            subscriptionGroupsStateWrite '
              .traffic.sources.main = ((.traffic.sources.main // {upload:0,download:0}) | .upload += 1)'
        ) &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do
        wait "${pid}"
    done
    subscriptionGroupsStateRead -e --argjson workerCount "${workerCount}" '
      (.traffic | has("global") | not) and
      .traffic.sources.main.upload == $workerCount' >/dev/null

    date() {
        if [[ "${1:-}" == "+%Y%m%d%H%M%S" ]]; then
            printf '20260715000000\n'
        else
            command date "$@"
        fi
    }
    firstBackup=$(createSubscriptionGroupsBackup)
    secondBackup=$(createSubscriptionGroupsBackup)
    unset -f date
    [[ "${firstBackup}" != "${secondBackup}" ]]
    [[ -f "${firstBackup}" && -f "${secondBackup}" ]]
}

runSubscriptionGroupStateRemoteRestoreLegacyMenuRegression() {
    mkdir -p "$(subscriptionGroupsDir)"
    writeSubscriptionStateDefaultFixture
    ensureSubscriptionGroupsState

    local beforeSnapshot legacyBackup menuBackup
    legacyBackup="${TMP_DIR}/legacy-groups-backup.json"
    cat >"${legacyBackup}" <<'JSON'
{"version":1,"active_group":"legacy","groups":[{"id":"legacy","name":"Legacy","sources":[],"user_groups":[],"sync":{"enabled":true},"traffic":{}}]}
JSON
    beforeSnapshot=$(<"$(subscriptionGroupsFile)")
    if restoreSubscriptionGroupsBackup "${legacyBackup}" >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(<"$(subscriptionGroupsFile)")" == "${beforeSnapshot}" ]]

    menuBackup="${TMP_DIR}/legacy-menu-backup.json"
    jq '.id = "legacy" | .name = "Legacy"' "$(subscriptionGroupsFile)" >"${menuBackup}"
    jq empty "${menuBackup}" >/dev/null
    subscriptionGroupsStateWrite '.id = "changed" | .name = "Changed"'
    (
        local menuOutput
        listSubscriptionGroupsBackups() {
            printf '%s\n' "${menuBackup}"
        }
        createSubscriptionGroupsBackup() {
            cp "$(subscriptionGroupsFile)" "${TMP_DIR}/legacy-menu-current-backup.json" || return 1
            printf '%s\n' "${TMP_DIR}/legacy-menu-current-backup.json"
        }
        readUserCrontabContent() { printf 'old-cron\n'; }
        installUserCrontabContent() { printf '%s\n' "$1" >"${TMP_DIR}/legacy-menu-cron.txt"; }
        subscriptionSyncCreateLocalApplyBackups() {
            printf -v "$1" '%s' "${TMP_DIR}/legacy-menu-config-backup"
            printf -v "$2" '%s' "${TMP_DIR}/legacy-menu-output-backup"
            mkdir -p "${!1}" "${!2}"
        }
        subscriptionSyncReleaseLocalApplyBackups() { :; }
        runSubscriptionGroupSync() { return 0; }
        refreshSubscriptionGroupSyncCron() { return 0; }
        autoRead() {
            local targetVar=$3
            local input=
            IFS= read -r input || input=
            printf -v "${targetVar}" '%s' "${input}"
        }
        menuLine() { printf 'menu:%s\n' "$*"; }
        menuClose() { printf 'menu:close\n'; }
        menuOutput=$(printf '1\nyes\n' | restoreSubscriptionGroupsBackupMenu)
        [[ "${menuOutput}" == *"menu:"* ]]
    )
    jq -e '.version == 5 and (.groups | not) and (.active_group | not) and .id == "legacy"' "$(subscriptionGroupsFile)" >/dev/null
}

runSubscriptionSyncTempDirRegression() (
    local tmpRoot="${TMP_DIR}/subscription-sync-tmp"
    local syncConfigRoot="${TMP_DIR}/subscription-sync-tempdir-config"
    local localDir="${TMP_DIR}/subscription-sync-tempdir-local"
    local publicDir="${TMP_DIR}/subscription-sync-tempdir-public"
    local backupDir
    local outputBackupDir
    local backupRegistered
    local cleanupPath

    mkdir -p "${tmpRoot}" "${syncConfigRoot}/xray" "${syncConfigRoot}/sing-box" "${localDir}/default" "${publicDir}/default"
    TMPDIR="${tmpRoot}"
    configPath="${syncConfigRoot}/xray/"
    singBoxConfigPath="${syncConfigRoot}/sing-box/"
    cat >"${configPath}01_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_team_a-main"}]}}]}
JSON

    subscriptionSyncCreateConfigBackups backupDir
    [[ "${backupDir}" == "${tmpRoot}"/padm-subscription-sync-backup.* ]]
    [[ -f "${backupDir}/manifest" ]]
    backupRegistered=
    for cleanupPath in "${PADM_CLEANUP_PATHS[@]}"; do
        [[ "${cleanupPath}" == "${backupDir}" ]] && backupRegistered=true
    done
    [[ "${backupRegistered}" == "true" ]]
    padmRemoveCleanupPath "${backupDir}"

    export PADM_SUBSCRIBE_LOCAL_DIR="${localDir}"
    export PADM_SUBSCRIBE_DIR="${publicDir}"
    printf 'local\n' >"${localDir}/default/user"
    printf 'public\n' >"${publicDir}/default/user"
    subscriptionSyncCreateSubscribeOutputBackups outputBackupDir
    [[ "${outputBackupDir}" == "${tmpRoot}"/padm-subscription-output-backup.* ]]
    [[ -f "${outputBackupDir}/local.exists" && -f "${outputBackupDir}/public.exists" ]]
    padmRemoveCleanupPath "${outputBackupDir}"

    if regressionFindHasMatches "${tmpRoot}" -mindepth 1 -maxdepth 1 -type d; then
        return 1
    fi
)

runSubscriptionSyncProcessSubstitutionFailureRegression() {
    local accountPlanCalled=false
    subscriptionSyncAccountPlanFromIds() {
        accountPlanCalled=true
        cat >/dev/null
        printf '{"create":[],"remove":[]}'
    }
    subscriptionSyncCredentialMismatchAccounts() { printf '[]\n'; }
    if subscriptionSyncPlanFromDesiredUsers '{bad-json' >/dev/null 2>&1; then
        return 1
    fi
    [[ "${accountPlanCalled}" == "false" ]]

    accountPlanCalled=false
    subscriptionQuotaPlanIds() { return 7; }
    if applySubscriptionQuotaPlanAccounts '[{"id":"team-a","action":"disable-and-remove-local-account"}]' >/dev/null 2>&1; then
        return 1
    fi
    [[ "${accountPlanCalled}" == "false" ]]

    subscriptionSyncConfigFiles() { return 7; }
    regressionExpectStatus 1 subscriptionSyncConfiguredAccountNamesJson >/dev/null 2>&1
    regressionExpectStatus 1 subscriptionSyncConfiguredManagedCredentials >/dev/null 2>&1

    protocolCapabilityRegistry() { return 7; }
    regressionExpectStatus 1 subscriptionSyncAppendProtocolBatch test-uuid test-account "${TMP_DIR}/" xray >/dev/null 2>&1
    regressionExpectStatus 1 subscriptionSyncAppendProtocolBatch test-uuid test-account "${TMP_DIR}/" unsupported >/dev/null 2>&1

    subscriptionSyncConfiguredAccountNamesJson "${TMP_DIR}/missing-inbounds.json" | jq -e '. == []' >/dev/null

    (
        local errors=
        errorCard() { errors+="$1"$'\n'; }
        userResultCard() { :; }
        menuLine() { :; }
        menuClose() { :; }
        autoRead() { return 99; }

        subscriptionGroupsBackupDir() { return 7; }
        regressionExpectStatus 1 listSubscriptionGroupsBackups >/dev/null 2>&1

        listSubscriptionGroupsBackups() { return 7; }
        regressionExpectStatus 1 selectSubscriptionGroupsBackupFile >/dev/null 2>&1
        [[ "$(grep -c '^状态备份列表读取失败$' <<<"${errors}")" == "1" ]]
    )
}

runSubscriptionUserRemovalTransactionLockRegression() (
    local logFile="${TMP_DIR}/subscription-user-removal-lock.log"
    : >"${logFile}"
    autoRead() { printf -v "$3" '%s' yes; }
    subscriptionGroupsWithLock() {
        printf '%s\n' lock-start >>"${logFile}"
        "$@"
        local status=$?
        printf '%s\n' lock-end >>"${logFile}"
        return "${status}"
    }
    subscriptionGroupsStateRead() { printf '%s\n' '{}'; }
    subscriptionSyncCreateConfigBackups() { printf -v "$1" '%s' "${TMP_DIR}/user-removal-config"; mkdir -p "${!1}"; }
    subscriptionSyncAccountName() { printf 'sub_%s\n' "$1"; }
    removeUserSubscriptionState() { printf '%s\n' remove-state >>"${logFile}"; }
    subscriptionSyncRemoveAccount() { printf '%s\n' remove-account >>"${logFile}"; }
    reloadCore() { printf '%s\n' reload >>"${logFile}"; }
    subscriptionSyncReleaseLocalApplyBackups() { :; }
    padmRemoveCleanupPath() { :; }
    successCard() { :; }
    runSubscriptionSyncAfterMutation() { printf '%s\n' post-sync >>"${logFile}"; }

    removeUserSubscriptionMenu team-a
    [[ "$(<"${logFile}")" == $'lock-start\nremove-state\nremove-account\nreload\npost-sync\nlock-end' ]]
)

runSubscriptionStateMaintenanceRollbackRegression() (
    local root="${TMP_DIR}/subscription-state-maintenance-rollback"
    local stateFile="${root}/groups.json"
    local targetFile="${root}/target.json"
    local maintCurrentBackup="${root}/current-backup.json"
    local logFile="${root}/calls.log"
    mkdir -p "${root}"
    printf 'old-state\n' >"${stateFile}"
    printf '{"sources":[]}' >"${targetFile}"
    : >"${logFile}"

    subscriptionGroupsFile() { printf '%s\n' "${stateFile}"; }
    readUserCrontabContent() { printf 'old-cron\n'; }
    createSubscriptionGroupsBackup() { cp "${stateFile}" "${maintCurrentBackup}"; printf '%s\n' "${maintCurrentBackup}"; }
    subscriptionSyncCreateLocalApplyBackups() {
        printf -v "$1" '%s' "${root}/config-backup"
        printf -v "$2" '%s' "${root}/output-backup"
        mkdir -p "${!1}" "${!2}"
    }
    subscriptionGroupsStateReplace() { cp "$1" "$2"; printf '%s\n' replace >>"${logFile}"; }
    subscriptionWireGuardCleanupRemovedSources() { return 0; }
    runSubscriptionGroupSync() { printf '%s\n' sync >>"${logFile}"; return 1; }
    subscriptionSyncRollbackLocalApply() {
        cp "${maintCurrentBackup}" "${stateFile}"
        SUBSCRIPTION_SYNC_CONFIG_RESTORED=true
        printf '%s\n' rollback >>"${logFile}"
        return 0
    }
    subscriptionSyncReconcileLocalServices() { printf '%s\n' reconcile >>"${logFile}"; }
    installUserCrontabContent() { printf '%s\n' cron >>"${logFile}"; }
    subscriptionSyncReleaseLocalApplyBackups() { printf '%s:%s\n' release "$1" >>"${logFile}"; }

    regressionExpectStatus 1 applySubscriptionGroupsStateMaintenanceUnlocked "${targetFile}" "恢复"
    [[ "$(<"${stateFile}")" == 'old-state' ]]
    head -n 5 "${logFile}" | cmp -s - <(printf '%s\n' replace sync rollback reconcile cron)
    tail -n 1 "${logFile}" | grep -qx 'release:remove'
)

runSubscriptionStateMaintenanceRemovedSourceCleanupRegression() (
    local logFile="${TMP_DIR}/subscription-state-maintenance-removed-source.log"
    local previousGroupsState='{"sources":[{"id":"main","role":"main"},{"id":"edge-old","role":"secondary","enabled":true}],"user_groups":[]}'
    local targetGroupsState='{"sources":[{"id":"main","role":"main"}],"user_groups":[]}'
    TEST_WIREGUARD_TRANSITION_STATE='{"enabled":true,"role":"main","address":"10.77.0.1/24","peers":[{"id":"edge-old","address":"10.77.0.2/24","public_key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","endpoint":"","enabled":true}]}'
    : >"${logFile}"

    subscriptionWireGuardReadState() { printf '%s\n' "${TEST_WIREGUARD_TRANSITION_STATE}"; }
    subscriptionRemoteDrainSource() {
        printf 'drain:%s:%s\n' "$(jq -r '.id' <<<"$1")" "$3" >>"${logFile}"
        printf -v "$2" '%s' '{"edge-old":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111","account":"sub_team_a"}]}'
    }
    subscriptionWireGuardWriteState() {
        local state= filter=
        while (($# > 1)); do
            if [[ "$1" == "--argjson" && "$2" == "state" ]]; then
                state=$3
                shift 3
            else
                shift
            fi
        done
        filter=${1:-}
        [[ -n "${state}" && -n "${filter}" ]] || return 1
        TEST_WIREGUARD_TRANSITION_STATE=${state}
    }
    applySubscriptionWireGuardService() { printf 'apply\n' >>"${logFile}"; }
    subscriptionWireGuardRestoreStateAndConfig() {
        TEST_WIREGUARD_TRANSITION_STATE=$1
        printf 'restore-state\n' >>"${logFile}"
    }
    subscriptionRemoteApplyDesiredUsersForSource() {
        printf 'restore-remote:%s\n' "$(jq -r '.id' <<<"$1")" >>"${logFile}"
    }

    subscriptionWireGuardCleanupRemovedSourcesUnlocked "${previousGroupsState}" "${targetGroupsState}"
    [[ "${SUBSCRIPTION_WIREGUARD_GROUPS_TRANSITION_ACTIVE}" == "true" ]]
    jq -e '.peers | length == 0' <<<"${TEST_WIREGUARD_TRANSITION_STATE}" >/dev/null
    grep -q '^drain:edge-old:' "${logFile}"

    subscriptionWireGuardRollbackGroupsTransition
    jq -e '.peers[0].id == "edge-old"' <<<"${TEST_WIREGUARD_TRANSITION_STATE}" >/dev/null
    grep -qx 'restore-state' "${logFile}"
    grep -qx 'restore-remote:edge-old' "${logFile}"
)

runSubscriptionSourceRemovalPreflightRegression() (
    local logFile="${TMP_DIR}/subscription-source-removal-preflight.log"
    TEST_SOURCE_GROUPS='{"sources":[{"id":"main","role":"main"},{"id":"edge","role":"secondary"}],"user_groups":[{"id":"team-a","allowed_sources":["*"]}]}'
    TEST_SOURCE_WIREGUARD='{"role":"main","peers":[]}'
    : >"${logFile}"

    subscriptionWireGuardRole() { printf 'main\n'; }
    subscriptionWireGuardReadPreviousStateAndGroups() {
        printf -v "$1" '%s' "${TEST_SOURCE_WIREGUARD}"
        printf -v "$2" '%s' "${TEST_SOURCE_GROUPS}"
    }
    subscriptionActiveGroupRead() { jq "$@" <<<"${TEST_SOURCE_GROUPS}"; }
    subscriptionSourceExists() { [[ "$1" == "edge" ]]; }
    subscriptionSourceIsMain() { [[ "$1" == "main" ]]; }
    subscriptionRemoteDrainSource() { printf 'remote\n' >>"${logFile}"; return 1; }
    subscriptionWireGuardWriteState() { printf 'wireguard\n' >>"${logFile}"; return 1; }

    if subscriptionWireGuardRemovePeerAndSourceUnlocked edge >/dev/null 2>&1; then
        return 1
    fi
    [[ ! -s "${logFile}" ]]
)

runSubscriptionMutationSyncRollbackRegression() (
    TEST_SYNC_CALLS=0
    TEST_SYNC_STATE_RESTORED=false
    subscriptionGroupSyncEnabled() { return 0; }
    runSubscriptionGroupSync() {
        TEST_SYNC_CALLS=$((TEST_SYNC_CALLS + 1))
        [[ "${TEST_SYNC_CALLS}" -gt 1 ]]
    }
    subscriptionGroupsStateWrite() { TEST_SYNC_STATE_RESTORED=true; }
    statusCard() { :; }
    warnCard() { :; }

    if runSubscriptionSyncAfterMutation "测试用户收权" '{"old":true}'; then
        return 1
    fi
    [[ "${TEST_SYNC_CALLS}" == "2" ]]
    [[ "${TEST_SYNC_STATE_RESTORED}" == "true" ]]
)

runSubscriptionMutationSyncRollbackLocalRestoreRegression() (
    local configFile="${TMP_DIR}/mutation-config.json"
    local outputFile="${TMP_DIR}/mutation-output.txt"
    local testConfigBackupDir="${TMP_DIR}/mutation-config-backup"
    local testOutputBackupDir="${TMP_DIR}/mutation-output-backup"
    local releaseMode=
    printf 'old-config\n' >"${configFile}"
    printf 'old-output\n' >"${outputFile}"
    TEST_SYNC_CALLS=0
    TEST_SYNC_STATE_RESTORED=false
    TEST_CONFIG_RESTORED=false
    TEST_OUTPUT_RESTORED=false
    TEST_SERVICES_RECONCILED=false
    subscriptionGroupSyncEnabled() { return 0; }
    runSubscriptionGroupSync() {
        TEST_SYNC_CALLS=$((TEST_SYNC_CALLS + 1))
        printf 'new-config\n' >"${configFile}"
        printf 'new-output\n' >"${outputFile}"
        return 1
    }
    subscriptionSyncCreateLocalApplyBackups() {
        mkdir -p "${testConfigBackupDir}" "${testOutputBackupDir}"
        cp "${configFile}" "${testConfigBackupDir}/config"
        cp "${outputFile}" "${testOutputBackupDir}/output"
        printf -v "$1" '%s' "${testConfigBackupDir}"
        printf -v "$2" '%s' "${testOutputBackupDir}"
    }
    subscriptionGroupsStateWrite() { TEST_SYNC_STATE_RESTORED=true; }
    subscriptionSyncRestoreConfigBackups() { cp "${testConfigBackupDir}/config" "${configFile}"; TEST_CONFIG_RESTORED=true; }
    subscriptionSyncRestoreSubscribeOutputBackups() { cp "${testOutputBackupDir}/output" "${outputFile}"; TEST_OUTPUT_RESTORED=true; }
    subscriptionSyncReconcileLocalServices() { TEST_SERVICES_RECONCILED=true; }
    subscriptionSyncReleaseLocalApplyBackups() { releaseMode=$1; }
    statusCard() { :; }
    warnCard() { :; }

    if runSubscriptionSyncAfterMutation "测试用户收权" '{"old":true}'; then
        return 1
    fi
    [[ "${TEST_SYNC_CALLS}" == "2" ]]
    [[ "${TEST_SYNC_STATE_RESTORED}" == "true" ]]
    [[ "${TEST_CONFIG_RESTORED}" == "true" ]]
    [[ "${TEST_OUTPUT_RESTORED}" == "true" ]]
    [[ "${TEST_SERVICES_RECONCILED}" == "true" ]]
    [[ "${releaseMode}" == "remove" ]]
    [[ "$(<"${configFile}")" == "old-config" ]]
    [[ "$(<"${outputFile}")" == "old-output" ]]
)

runSubscriptionMutationSyncStateRestoreFailureRegression() (
    local configFile="${TMP_DIR}/mutation-state-failure-config.json"
    local outputFile="${TMP_DIR}/mutation-state-failure-output.txt"
    local testConfigBackupDir="${TMP_DIR}/mutation-state-failure-config-backup"
    local testOutputBackupDir="${TMP_DIR}/mutation-state-failure-output-backup"
    local releaseMode=
    printf 'old-config\n' >"${configFile}"
    printf 'old-output\n' >"${outputFile}"
    TEST_SYNC_CALLS=0
    TEST_STATE_WRITE_CALLS=0
    TEST_CONFIG_RESTORED=false
    TEST_OUTPUT_RESTORED=false
    TEST_SERVICES_RECONCILED=false
    subscriptionGroupSyncEnabled() { return 0; }
    runSubscriptionGroupSync() {
        TEST_SYNC_CALLS=$((TEST_SYNC_CALLS + 1))
        printf 'new-config\n' >"${configFile}"
        printf 'new-output\n' >"${outputFile}"
        return 1
    }
    subscriptionSyncCreateLocalApplyBackups() {
        mkdir -p "${testConfigBackupDir}" "${testOutputBackupDir}"
        cp "${configFile}" "${testConfigBackupDir}/config"
        cp "${outputFile}" "${testOutputBackupDir}/output"
        printf -v "$1" '%s' "${testConfigBackupDir}"
        printf -v "$2" '%s' "${testOutputBackupDir}"
    }
    subscriptionGroupsStateWrite() {
        TEST_STATE_WRITE_CALLS=$((TEST_STATE_WRITE_CALLS + 1))
        return 1
    }
    subscriptionSyncRestoreConfigBackups() { cp "${testConfigBackupDir}/config" "${configFile}"; TEST_CONFIG_RESTORED=true; }
    subscriptionSyncRestoreSubscribeOutputBackups() { cp "${testOutputBackupDir}/output" "${outputFile}"; TEST_OUTPUT_RESTORED=true; }
    subscriptionSyncReconcileLocalServices() { TEST_SERVICES_RECONCILED=true; }
    subscriptionSyncReleaseLocalApplyBackups() { releaseMode=$1; }
    statusCard() { :; }
    warnCard() { :; }

    if runSubscriptionSyncAfterMutation "测试状态恢复失败" '{"old":true}'; then
        return 1
    fi
    [[ "${TEST_SYNC_CALLS}" == "1" ]]
    [[ "${TEST_STATE_WRITE_CALLS}" == "1" ]]
    [[ "${TEST_CONFIG_RESTORED}" == "true" ]]
    [[ "${TEST_OUTPUT_RESTORED}" == "true" ]]
    [[ "${TEST_SERVICES_RECONCILED}" == "true" ]]
    [[ "${releaseMode}" == "forget" ]]
    [[ "$(<"${configFile}")" == "old-config" ]]
    [[ "$(<"${outputFile}")" == "old-output" ]]
)

runSubscriptionSyncRestorePairFailureMessageRegression() (
    local message=
    local detail=
    local spec configRestored outputRestored expectedStatus expectedMessage

    for spec in \
        'true|true|0|' \
        'false|true|1|本机同步失败，且配置恢复失败，请手动检查备份目录: /tmp/config' \
        'true|false|1|本机同步失败，且订阅输出恢复失败，请手动检查备份目录: /tmp/output' \
        'false|false|1|本机同步失败，且配置与订阅输出恢复失败，请手动检查备份目录: /tmp/config 和 /tmp/output'; do
        IFS='|' read -r configRestored outputRestored expectedStatus expectedMessage <<<"${spec}"
        regressionExpectStatus "${expectedStatus}" subscriptionSyncSetRestorePairFailureMessage message \
            "本机同步失败" \
            "${configRestored}" "配置" "备份目录: /tmp/config" \
            "${outputRestored}" "订阅输出" "备份目录: /tmp/output" \
            "备份目录: /tmp/config 和 /tmp/output"
        [[ "${message}" == "${expectedMessage}" ]]
    done

    subscriptionSyncSetManualCheckMessage detail "配置与订阅输出恢复失败" "备份目录: /tmp/config 和 /tmp/output"
    [[ "${detail}" == "配置与订阅输出恢复失败，请手动检查备份目录: /tmp/config 和 /tmp/output" ]]
)

runSubscriptionSyncAppendRestoreFailureDetailRegression() (
    local message=
    local detail=

    subscriptionSyncAppendRestoreFailureDetail message "控制面同步失败后" "状态恢复失败"
    [[ "${message}" == "控制面同步失败后状态恢复失败" ]]

    subscriptionSyncSetRestoreFailureDetail detail "配置" "备份目录: /tmp/config"
    subscriptionSyncAppendRestoreFailureDetail message "控制面同步失败后" "${detail}"
    [[ "${message}" == "控制面同步失败后状态恢复失败；配置恢复失败，请手动检查备份目录: /tmp/config" ]]

    message=
    subscriptionSyncSetRestoreFailureDetail detail "订阅输出" "备份目录: /tmp/output"
    subscriptionSyncAppendRestoreFailureDetail message "控制面同步失败后" "${detail}"
    [[ "${message}" == "控制面同步失败后订阅输出恢复失败，请手动检查备份目录: /tmp/output" ]]
)

runSubscriptionSyncSingleRestoreResultMessageRegression() (
    local message=
    local detail=
    local spec expectedStatus failure restored successMessage restoreName manualDetail appendDetail expectedMessage

    for spec in \
        '0|限额自动执行失败|true|已恢复旧订阅状态|订阅状态|备份文件: /tmp/groups.json|true|限额自动执行失败，已恢复旧订阅状态' \
        '1|限额自动执行失败|false|已恢复旧订阅状态|订阅状态|备份文件: /tmp/groups.json|true|限额自动执行失败，且订阅状态恢复失败，请手动检查备份文件: /tmp/groups.json' \
        "0|控制面同步期望用户状态写入失败|true||订阅状态|$(subscriptionGroupsFile)|true|控制面同步期望用户状态写入失败" \
        '1|Xray 流量统计策略配置写入失败|false|已恢复旧配置|旧配置|备份目录: /tmp/stats-backup|true|Xray 流量统计策略配置写入失败，且旧配置恢复失败，请手动检查备份目录: /tmp/stats-backup' \
        '1|订阅 Nginx 配置校验失败|false|已恢复旧配置|旧配置| /tmp/subscribe.conf 和 /tmp/.subscribe.conf.backup.123456|true|订阅 Nginx 配置校验失败，且旧配置恢复失败，请手动检查 /tmp/subscribe.conf 和 /tmp/.subscribe.conf.backup.123456' \
        '1|订阅生成失败|false|已恢复旧订阅输出|旧订阅输出|备份目录: /tmp/subscribe-output-backup|true|订阅生成失败，且旧订阅输出恢复失败，请手动检查备份目录: /tmp/subscribe-output-backup' \
        '0|订阅生成失败|true|已恢复旧订阅输出|旧订阅输出|备份目录: /tmp/subscribe-output-backup|true|订阅生成失败，已恢复旧订阅输出' \
        '1|WireGuard 主控服务启动失败|false||旧状态||false|WireGuard 主控服务启动失败，且旧状态恢复失败'; do
        IFS='|' read -r expectedStatus failure restored successMessage restoreName manualDetail appendDetail expectedMessage <<<"${spec}"
        regressionExpectStatus "${expectedStatus}" subscriptionSyncSetSingleRestoreResultMessage message \
            "${failure}" "${restored}" "${successMessage}" "${restoreName}" "${manualDetail}" "${appendDetail}"
        [[ "${message}" == "${expectedMessage}" ]]
    done

    subscriptionSyncSetManualCheckMessage detail "订阅状态恢复失败" "备份文件: /tmp/groups.json"
    [[ "${detail}" == "订阅状态恢复失败，请手动检查备份文件: /tmp/groups.json" ]]
)

runSubscriptionSyncRollbackResultMessageRegression() (
    local message=
    local retryLog="${TMP_DIR}/subscription-sync-rollback-result.log"

    subscriptionSyncSetRollbackResultMessage message \
        "托管账号配置移除失败" \
        "已恢复旧配置"
    [[ "${message}" == "托管账号配置移除失败，已恢复旧配置" ]]

    subscriptionSyncSetRollbackResultMessage message \
        "订阅状态重建失败" \
        "已恢复旧状态"
    [[ "${message}" == "订阅状态重建失败，已恢复旧状态" ]]

    : >"${retryLog}"
    rollbackRetrySuccess() {
        printf '%s\n' "$*" >>"${retryLog}"
        return 0
    }
    subscriptionSyncSetRollbackResultMessage message \
        "核心重载失败" \
        "已回滚流量统计配置" \
        rollbackRetrySuccess \
        "恢复旧配置后核心重载仍失败，请检查核心服务日志" \
        stats
    [[ "${message}" == "核心重载失败，已回滚流量统计配置" ]]
    grep -q '^stats$' "${retryLog}"

    : >"${retryLog}"
    rollbackRetryFail() {
        printf '%s\n' "$*" >>"${retryLog}"
        return 1
    }
    subscriptionSyncSetRollbackResultMessage message \
        "本机同步后服务重建失败" \
        "已恢复旧配置" \
        rollbackRetryFail \
        "恢复旧配置后服务重建仍失败，请检查核心服务日志" \
        true
    [[ "${message}" == "本机同步后服务重建失败，已恢复旧配置；恢复旧配置后服务重建仍失败，请检查核心服务日志" ]]
    grep -q '^true$' "${retryLog}"
)

runSubscriptionSyncFindUserEnabledProjectionRegression() (
    local result

    subscriptionActiveEnabledUsersJson() {
        jq -n '[{id:"team-a", name:"Team A", account:"sub_team_a", allowed_sources:["main"], allows_main:true, has_remote:false}]'
    }
    subscriptionActiveGroupRead() {
        return 99
    }

    result=$(subscriptionSyncFindUserByAccountName sub_team_a)
    jq -e '.id == "team-a" and .account == "sub_team_a" and .allows_main == true and .has_remote == false' <<<"${result}" >/dev/null
)

runSubscriptionSyncRollbackConfigRestoreFailureRegression() (
    local rootRel="${TMP_DIR}/subscription-sync-rollback-failure"
    local root
    local targetFile
    local rc backupDirs=()

    mkdir -p "${rootRel}/xray" "${rootRel}/tmp"
    root=$(cd -- "${rootRel}" && pwd -P)
    targetFile="${root}/xray/02_VLESS_TCP_inbounds.json"
    configPath="${root}/xray/"
    singBoxConfigPath="${root}/xray/"
    TMPDIR="${root}/tmp"
    coreInstallType=1
    ctlPath=
    cat >"${targetFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_old-main"}]}}]}
JSON
    eval "$(declare -f subscriptionSyncApplyAccountPlan | sed '1s/^subscriptionSyncApplyAccountPlan/originalSubscriptionSyncApplyAccountPlan/')"

    initXrayClients() {
        jq -n --arg email "$3-main" '[{email:$email}]'
    }
    subscriptionSyncGenerateUUID() {
        printf '99999999-9999-9999-9999-999999999999\n'
    }
    subscriptionSyncApplyAccountPlan() {
        originalSubscriptionSyncApplyAccountPlan "$@"
        return 1
    }
    cp() {
        if [[ "$1" == "-p" && "$2" == "${root}/tmp"/padm-subscription-sync-backup.*/*.json && "$3" == "${root}/xray"/.02_VLESS_TCP_inbounds.json.restore.* ]]; then
            return 1
        fi
        command cp "$@"
    }

    regressionExpectStatus 1 subscriptionSyncApplyAccountPlanTransaction '{"create":["sub_new"],"remove":[]}'
    jq -e '.inbounds[0].settings.clients[0].email == "sub_new-main"' "${targetFile}" >/dev/null
    [[ "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR}" == *"配置恢复失败"* ]]
    [[ "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR}" == *"备份目录:"* ]]
    mapfile -t backupDirs < <(find "${root}/tmp" -maxdepth 1 -type d -name 'padm-subscription-sync-backup.*' -print)
    [[ "${#backupDirs[@]}" == "1" ]]
    [[ -f "${backupDirs[0]}/manifest" ]]
    grep -q "${targetFile}" "${backupDirs[0]}/manifest"
    if regressionFindHasMatches "${root}/xray" -name '*.sync.*'; then
        return 1
    fi
)

runSubscriptionSyncRollbackRestoreDirFailureRegression() (
    local restoreDirRoot="${TMP_DIR}/subscription-sync-restore-dir-failure"
    local restoreDirTarget="${restoreDirRoot}/subscribe_local"
    local restoreDirBackup="${restoreDirRoot}/backup"
    local restoreStatus

    mkdir -p "${restoreDirTarget}/default" "${restoreDirTarget}/clashMeta" "${restoreDirBackup}/local/default" "${restoreDirBackup}/local/clashMeta"
    printf 'current default\n' >"${restoreDirTarget}/default/existing"
    printf 'current clash\n' >"${restoreDirTarget}/clashMeta/existing"
    printf 'backup default\n' >"${restoreDirBackup}/local/default/existing"
    printf 'backup clash\n' >"${restoreDirBackup}/local/clashMeta/existing"
    printf 'dir\n' >"${restoreDirBackup}/local.exists"
    cp() {
        if [[ "$1" == "-a" && "$2" == "${restoreDirBackup}/local/." && "$3" == "${restoreDirRoot}"/.restore-local.*"/" ]]; then
            return 1
        fi
        command cp "$@"
    }
    regressionExpectStatus 1 subscriptionSyncRestoreBackupPath "${restoreDirTarget}" "${restoreDirBackup}" local
    [[ "$(<"${restoreDirTarget}/default/existing")" == "current default" ]]
    [[ "$(<"${restoreDirTarget}/clashMeta/existing")" == "current clash" ]]
    if regressionFindHasMatches "${restoreDirRoot}" -maxdepth 1 -type d \( -name '.restore-local.*' -o -name '.restore-old-local.*' \); then
        return 1
    fi
)

runSubscriptionSyncRollbackReloadRollbackRegression() (
    local reloadRoot="${TMP_DIR}/subscription-sync-reload-rollback"
    local reloadTargetFile="${reloadRoot}/xray/02_VLESS_TCP_inbounds.json"
    local reloadLog="${reloadRoot}/reload.log"
    local reloadOriginalContent
    local reloadStatus

    mkdir -p "${reloadRoot}/xray" "${reloadRoot}/tmp"
    configPath="${reloadRoot}/xray/"
    singBoxConfigPath="${reloadRoot}/xray/"
    TMPDIR="${reloadRoot}/tmp"
    coreInstallType=1
    cat >"${reloadTargetFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_old-main"}]}}]}
JSON
    reloadOriginalContent=$(<"${reloadTargetFile}")

    eval "$(declare -f subscriptionSyncApplyAccountPlan | sed '1s/^subscriptionSyncApplyAccountPlan/originalSubscriptionSyncApplyAccountPlan/')"
    subscriptionSyncApplyAccountPlan() {
        originalSubscriptionSyncApplyAccountPlan "$@"
    }
    reloadCore() {
        printf 'reload\n' >>"${reloadLog}"
        return 1
    }

    regressionExpectStatus 1 applySubscriptionQuotaPlanAccounts '[{"id":"team-a","action":"disable-and-remove-local-account"}]'
    [[ "$(<"${reloadTargetFile}")" == "${reloadOriginalContent}" ]]
    [[ "$(wc -l <"${reloadLog}" | tr -d ' ')" == "2" ]]
    [[ "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR}" == *"核心重载失败"* ]]
    [[ "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR}" == *"恢复旧配置后核心重载仍失败"* ]]
    if regressionFindHasMatches "${reloadRoot}/tmp" -maxdepth 1 -type d -name 'padm-subscription-sync-backup.*'; then
        return 1
    fi
)

runSubscriptionGroupSyncApplyFailureRegression() (
    local syncRoot="${TMP_DIR}/subscription-group-sync-apply-failure"
    local syncConfigFile="${syncRoot}/xray/02_VLESS_TCP_inbounds.json"
    local syncLocalFile="${syncRoot}/subscribe_local/default/user"
    local syncPublicFile="${syncRoot}/subscribe/default/user"
    local remoteLog="${syncRoot}/remote.log"
    local reconcileLog="${syncRoot}/reconcile.log"
    local statusLog="${syncRoot}/status.log"
    local resultStatus="${syncRoot}/mark-status.log"
    local resultFailures="${syncRoot}/mark-failures.log"
    local generatedUuidLog="${syncRoot}/generated-uuid.log"
    local originalConfig
    local syncStatus

    prepareSubscriptionGroupSyncFixture "${syncRoot}" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge-a","name":"Edge A","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"edge.example.com","port":443,"enabled":true,"sync_status":"pending","control_token":"token-a"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    originalConfig=$(<"${syncConfigFile}")

    subscriptionSyncGenerateUUID() {
        printf '99999999-9999-4999-8999-999999999999\n'
    }
    subscriptionSyncPlan() {
        printf '{"create":["sub_team_a"],"remove":[]}'
    }
    subscriptionSyncApplyAccountPlan() {
        jq -r '.user_groups[0].uuid // empty' "$(subscriptionGroupsFile)" >"${generatedUuidLog}"
        SUBSCRIPTION_SYNC_TRANSACTION_ERROR="本机同步计划应用失败"
        return 1
    }
    subscriptionSyncReconcileLocalServices() {
        printf 'reconcile\n' >>"${reconcileLog}"
        return 0
    }
    runSubscriptionRemoteSync() {
        printf 'remote\n' >>"${remoteLog}"
        printf '{"failures":[],"snapshots":{}}'
    }

    regressionExpectStatus 1 runSubscriptionGroupSync
    [[ "$(<"${syncConfigFile}")" == "${originalConfig}" ]]
    [[ "$(<"${syncLocalFile}")" == "old-local" ]]
    [[ "$(<"${syncPublicFile}")" == "old-public" ]]
    grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' "${generatedUuidLog}"
    jq -e '(.user_groups[0] | has("uuid")) | not' "$(subscriptionGroupsFile)" >/dev/null
    [[ ! -e "${remoteLog}" ]]
    [[ ! -e "${reconcileLog}" ]]
    grep -q '本机同步计划应用失败' "${resultFailures}"
    ! grep -q '已跳过被控服务器同步' "${resultFailures}"
    grep -q '本机同步未完全完成' "${statusLog}"
    ! grep -q '被控服务器' "${statusLog}"
    grep -qx 'partial' "${resultStatus}"
    if regressionFindHasMatches "${syncRoot}/tmp" -maxdepth 1 -type d \( -name 'padm-subscription-sync-backup.*' -o -name 'padm-subscription-output-backup.*' \); then
        return 1
    fi

    cat >"${syncConfigFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_old-main"}]}}]}
JSON
    printf 'old-local\n' >"${syncLocalFile}"
    printf 'old-public\n' >"${syncPublicFile}"
    : >"${reconcileLog}"
    subscriptionSyncRestoreSubscribeOutputBackups() { return 1; }

    regressionExpectStatus 1 runSubscriptionGroupSync
    [[ "$(<"${syncConfigFile}")" == "${originalConfig}" ]]
    [[ ! -s "${reconcileLog}" ]]
    grep -q '订阅输出恢复失败' "${resultFailures}"
)

runSubscriptionGroupSyncReconcileRollbackRegression() (
    local syncRoot="${TMP_DIR}/subscription-group-sync-reconcile-rollback"
    local syncConfigFile="${syncRoot}/xray/02_VLESS_TCP_inbounds.json"
    local syncLocalFile="${syncRoot}/subscribe_local/default/user"
    local syncPublicFile="${syncRoot}/subscribe/default/user"
    local remoteLog="${syncRoot}/remote.log"
    local reconcileLog="${syncRoot}/reconcile.log"
    local statusLog="${syncRoot}/status.log"
    local resultStatus="${syncRoot}/mark-status.log"
    local resultFailures="${syncRoot}/mark-failures.log"
    local originalConfig
    local syncStatus

    prepareSubscriptionGroupSyncFixture "${syncRoot}" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge-a","name":"Edge A","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"edge.example.com","port":443,"enabled":true,"sync_status":"pending","control_token":"token-a"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":"","uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    originalConfig=$(<"${syncConfigFile}")

    subscriptionSyncPlan() {
        printf '{"create":["sub_team_a"],"remove":[]}'
    }
    subscriptionSyncApplyAccountPlan() {
        cat >"${syncConfigFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_new-main"}]}}]}
JSON
        return 0
    }
    subscriptionSyncReconcileLocalServices() {
        printf '%s\n' "${1:-<empty>}" >>"${reconcileLog}"
        if [[ -z "${1:-}" ]]; then
            printf 'new-local\n' >"${syncLocalFile}"
            printf 'new-public\n' >"${syncPublicFile}"
            return 1
        fi
        return 0
    }
    runSubscriptionRemoteSync() {
        printf 'remote\n' >>"${remoteLog}"
        printf '{"failures":[],"snapshots":{}}'
    }

    regressionExpectStatus 1 runSubscriptionGroupSync
    [[ "$(<"${syncConfigFile}")" == "${originalConfig}" ]]
    [[ "$(<"${syncLocalFile}")" == "old-local" ]]
    [[ "$(<"${syncPublicFile}")" == "old-public" ]]
    [[ ! -e "${remoteLog}" ]]
    [[ "$(wc -l <"${reconcileLog}" | tr -d ' ')" == "2" ]]
    grep -qx '<empty>' "${reconcileLog}"
    grep -qx 'true' "${reconcileLog}"
    grep -q '本机同步后服务重建失败，已恢复旧配置' "${resultFailures}"
    ! grep -q '已跳过被控服务器同步' "${resultFailures}"
    grep -q '本机同步未完全完成' "${statusLog}"
    ! grep -q '被控服务器' "${statusLog}"
    grep -qx 'partial' "${resultStatus}"
    if regressionFindHasMatches "${syncRoot}/tmp" -maxdepth 1 -type d \( -name 'padm-subscription-sync-backup.*' -o -name 'padm-subscription-output-backup.*' \); then
        return 1
    fi
)

runSubscriptionGroupSyncRemoteFailureRegression() (
    local remoteFailureMode=${1:-remote-failure}
    local syncRoot="${TMP_DIR}/subscription-group-sync-${remoteFailureMode}"
    local syncConfigFile="${syncRoot}/xray/02_VLESS_TCP_inbounds.json"
    local syncLocalFile="${syncRoot}/subscribe_local/default/user"
    local syncPublicFile="${syncRoot}/subscribe/default/user"
    local remoteLog="${syncRoot}/remote.log"
    local reconcileLog="${syncRoot}/reconcile.log"
    local statusLog="${syncRoot}/status.log"
    local resultStatus="${syncRoot}/mark-status.log"
    local resultFailures="${syncRoot}/mark-failures.log"
    local refreshLog="${syncRoot}/refresh.log"
    local originalConfig
    local syncStatus

    prepareSubscriptionGroupSyncFixture "${syncRoot}" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge-a","name":"Edge A","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"edge.example.com","port":443,"enabled":true,"sync_status":"pending","control_token":"token-a"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":"","uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    originalConfig=$(<"${syncConfigFile}")

    subscriptionCurrentRoleNormalized() { printf 'main\n'; }
    subscriptionRemoteScopeEnabled() { [[ "${remoteFailureMode}" != "control-disabled" ]]; }
    subscriptionSyncPlan() {
        printf '{"create":["sub_team_a"],"remove":[]}'
    }
    subscriptionSyncApplyAccountPlan() {
        cat >"${syncConfigFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_new-main"}]}}]}
JSON
        return 0
    }
    subscriptionSyncReconcileLocalServices() {
        printf '%s\n' "${1:-<empty>}" >>"${reconcileLog}"
        return 0
    }
    runSubscriptionRemoteSync() {
        printf 'remote\n' >>"${remoteLog}"
        printf '{"failures":["被控服务器同步失败"],"snapshots":{"edge-a":null}}'
    }
    refreshPublishedSubscriptions() {
        printf 'refresh\n' >>"${refreshLog}"
        return 0
    }

    regressionExpectStatus 1 runSubscriptionGroupSync
    [[ "$(<"${syncConfigFile}")" != "${originalConfig}" ]]
    grep -q 'sub_new-main' "${syncConfigFile}"
    [[ "$(<"${syncLocalFile}")" == "old-local" ]]
    [[ "$(<"${syncPublicFile}")" == "old-public" ]]
    [[ ! -e "${refreshLog}" ]]
    if [[ "${remoteFailureMode}" == "control-disabled" ]]; then
        [[ ! -e "${remoteLog}" ]]
        grep -q '主控控制面已关闭，启用的被控服务器无法同步' "${resultFailures}"
        jq -e '.sources[] | select(.id == "edge-a" and .last_sync_error.type == "control_disabled")' "$(subscriptionGroupsFile)" >/dev/null
    else
        grep -qx 'remote' "${remoteLog}"
        grep -q '被控服务器同步失败' "${resultFailures}"
    fi
    grep -q '本机自动同步完成，但被控服务器同步失败，请查看失败列表' "${statusLog}"
    grep -qx 'partial' "${resultStatus}"
    if regressionFindHasMatches "${syncRoot}/tmp" -maxdepth 1 -type d \( -name 'padm-subscription-sync-backup.*' -o -name 'padm-subscription-output-backup.*' \); then
        return 1
    fi
)

runSubscriptionGroupSyncRemoteBeforePublishRefreshRegression() (
    local syncRoot="${TMP_DIR}/subscription-group-sync-remote-before-publish-refresh"
    local syncConfigFile="${syncRoot}/xray/02_VLESS_TCP_inbounds.json"
    local callLog="${syncRoot}/calls.log"
    local resultStatus="${syncRoot}/mark-status.log"
    local resultFailures="${syncRoot}/mark-failures.log"
    local statusLog="${syncRoot}/status.log"
    local syncStatus

    prepareSubscriptionGroupSyncFixture "${syncRoot}" "" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge-b","name":"Edge B","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"10.77.0.2","port":39778,"enabled":true,"sync_status":"pending","control_token":"token-b"}],"user_groups":[{"id":"real-sync-6","name":"Real Sync 6","enabled":true,"allowed_sources":["edge-b"],"traffic_limit_gb":0,"token":"","uuid":"3004d897-c06d-45a1-aa64-3d3266ca63d5"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    : >"${callLog}"

    subscriptionCurrentRoleNormalized() { printf 'main\n'; }
    subscriptionRemoteScopeEnabled() { return 0; }
    reloadCore() {
        printf 'reload\n' >>"${callLog}"
        return 0
    }
    readNginxSubscribe() {
        printf 'read-subscribe\n' >>"${callLog}"
        subscribePort=39778
        subscribeType=https
        subscribeDomain=self.example.com
    }
    installSubscriptionControlService() {
        printf 'install-control\n' >>"${callLog}"
        return 0
    }
    serviceQueueRestart() {
        printf 'restart:%s\n' "$*" >>"${callLog}"
        return 0
    }
    serviceQueueApply() {
        printf 'apply-services\n' >>"${callLog}"
        return 0
    }
    subscriptionSyncPlan() {
        printf '{"create":["sub_real_sync_6"],"remove":[]}'
    }
    subscriptionSyncApplyAccountPlan() {
        printf 'apply-account-plan\n' >>"${callLog}"
        return 0
    }
    runSubscriptionRemoteSync() {
        printf 'remote-sync\n' >>"${callLog}"
        printf '{"failures":[],"snapshots":{}}'
    }
    refreshPublishedSubscriptions() {
        printf 'refresh-publish:%s\n' "$1" >>"${callLog}"
        return 0
    }

    regressionExpectStatus 0 runSubscriptionGroupSync
    grep -q '^apply-account-plan$' "${callLog}"
    grep -q '^remote-sync$' "${callLog}"
    grep -q '^refresh-publish:{}$' "${callLog}"
    python - <<'PY' "${callLog}"
import sys
lines = [line.strip() for line in open(sys.argv[1], encoding='utf-8') if line.strip()]
assert lines.index('remote-sync') < lines.index('refresh-publish:{}')
PY
    [[ "$(<"${resultFailures}")" == "[]" ]]
    grep -qx 'success' "${resultStatus}"
    grep -q '自动同步完成' "${statusLog}"
    if regressionFindHasMatches "${syncRoot}/tmp" -maxdepth 1 -type d \( -name 'padm-subscription-sync-backup.*' -o -name 'padm-subscription-output-backup.*' \); then
        return 1
    fi
)

runSubscriptionGroupSyncPublishRefreshInlineRegression() (
    local syncRoot="${TMP_DIR}/subscription-group-sync-publish-refresh-inline"
    local syncConfigFile="${syncRoot}/xray/02_VLESS_TCP_inbounds.json"
    local callLog="${syncRoot}/calls.log"
    local resultStatus="${syncRoot}/mark-status.log"
    local resultFailures="${syncRoot}/mark-failures.log"
    local statusLog="${syncRoot}/status.log"
    local syncStatus

    prepareSubscriptionGroupSyncFixture "${syncRoot}" "" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge-disabled","name":"Edge Disabled","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"edge.example.com","port":443,"enabled":false,"sync_status":"pending","control_token":"token-disabled"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":"","uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    : >"${callLog}"

    subscriptionCurrentRoleNormalized() { printf 'main\n'; }
    subscriptionRemoteScopeEnabled() { return 0; }
    subscriptionSyncPlan() {
        printf '{"create":["sub_team_a"],"remove":[]}'
    }
    subscriptionSyncApplyAccountPlan() {
        printf 'apply\n' >>"${callLog}"
        return 0
    }
    subscriptionSyncReconcileLocalServices() {
        printf 'reconcile:%s\n' "${1:-<empty>}" >>"${callLog}"
        return 0
    }
    runSubscriptionRemoteSync() {
        printf 'remote\n' >>"${callLog}"
        printf '{"failures":[],"snapshots":{}}'
    }
    subscriptionSyncRefreshPublishedSubscriptions() {
        return 98
    }
    readNginxSubscribe() {
        printf 'read-subscribe\n' >>"${callLog}"
        subscribePort=39778
        subscribeType=https
        subscribeDomain=main.example.com
    }
    refreshPublishedSubscriptions() {
        printf 'refresh-publish\n' >>"${callLog}"
        return 0
    }

    regressionExpectStatus 0 runSubscriptionGroupSync
    [[ ! -e "${resultFailures}" || "$(<"${resultFailures}")" == "[]" ]]
    grep -q '同步完成后公网订阅刷新失败' "${resultFailures}" && return 1
    grep -qx 'success' "${resultStatus}"
    grep -qx 'apply' "${callLog}"
    grep -qx 'reconcile:<empty>' "${callLog}"
    ! grep -qx 'remote' "${callLog}"
    grep -qx 'read-subscribe' "${callLog}"
    grep -qx 'refresh-publish' "${callLog}"
)

runSubscriptionGroupSyncSingleConfigBackupRegression() (
    local syncRoot="${TMP_DIR}/subscription-group-sync-single-config-backup"
    local syncConfigFile="${syncRoot}/xray/02_VLESS_TCP_inbounds.json"
    local backupCountLog="${syncRoot}/backup-count.log"
    local resultStatus="${syncRoot}/mark-status.log"
    local resultFailures="${syncRoot}/mark-failures.log"
    local statusLog="${syncRoot}/status.log"
    local quotaPlanMarker="${syncRoot}/quota-plan-called"
    local successMarker="${syncRoot}/unexpected-success"
    local errorMarker="${syncRoot}/mark-result-error"
    local syncStatus

    prepareSubscriptionGroupSyncFixture "${syncRoot}" "" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["main"],"traffic_limit_gb":0,"token":"","uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON

    eval "$(declare -f subscriptionSyncCreateConfigBackups | sed '1s/^subscriptionSyncCreateConfigBackups/originalSubscriptionSyncCreateConfigBackups/')"
    subscriptionSyncCreateConfigBackups() {
        printf 'backup\n' >>"${backupCountLog}"
        originalSubscriptionSyncCreateConfigBackups "$@"
    }
    readInstallType() { coreInstallType=1; }
    protocolCapabilityRegistry() {
        printf '1|unused|node|unused|unused|xray|unused|unused|unused|unused|unused|unused|unused|unused|unused|unused|unused|unused|02_VLESS_TCP_inbounds.json\n'
    }
    initXrayClients() {
        jq -n --arg email "$3-main" '[{email:$email}]'
    }
    subscriptionGroupQuotaAutoApplyEnabled() { return 0; }
    collectSubscriptionTraffic() { return 1; }
    subscriptionQuotaDryRunPlan() { : >"${quotaPlanMarker}"; printf '[]\n'; }
    subscriptionSyncReconcileLocalServices() { return 0; }
    readNginxSubscribe() { subscribePort=; }

    set +e
    runSubscriptionGroupSync
    syncStatus=$?
    set -e

    [[ "${syncStatus}" == "0" ]]
    [[ ! -e "${quotaPlanMarker}" ]]
    [[ "$(grep -c '^backup$' "${backupCountLog}")" == "1" ]]
    jq -e '.inbounds[0].settings.clients[0].email == "sub_team_a-main"' "${syncConfigFile}" >/dev/null
    [[ "$(<"${resultFailures}")" == "[]" ]]
    grep -qx 'success' "${resultStatus}"
    grep -q '自动同步完成' "${statusLog}"

    subscriptionSyncMarkResult() { return 1; }
    successCard() { : >"${successMarker}"; }
    errorCard() { : >"${errorMarker}"; }
    regressionExpectStatus 1 runSubscriptionGroupSync >/dev/null 2>&1
    [[ ! -e "${successMarker}" && -e "${errorMarker}" ]]
    unset -f subscriptionSyncCreateConfigBackups originalSubscriptionSyncCreateConfigBackups protocolCapabilityRegistry initXrayClients
)

runSubscriptionGroupSyncRollbackSerialRegression() {
    runRegressionStep subscription-group-sync-apply-failure runSubscriptionGroupSyncApplyFailureRegression
    runRegressionStep subscription-group-sync-reconcile-rollback runSubscriptionGroupSyncReconcileRollbackRegression
    runRegressionStep subscription-group-sync-remote-failure runSubscriptionGroupSyncRemoteFailureRegression
    runRegressionStep subscription-group-sync-control-disabled runSubscriptionGroupSyncRemoteFailureRegression control-disabled
    runRegressionStep subscription-group-sync-remote-before-publish-refresh runSubscriptionGroupSyncRemoteBeforePublishRefreshRegression
}

runSubscriptionSyncReconcileEarlyExitRegression() (
    local root="${TMP_DIR}/subscription-sync-reconcile-early-exit"
    local callLog="${root}/calls.log"
    local rc

    mkdir -p "${root}"

    (
        : >"${callLog}"
        subscribePort=
        reloadCore() {
            printf 'reload\n' >>"${callLog}"
            return 1
        }
        readNginxSubscribe() {
            printf 'read\n' >>"${callLog}"
            subscribePort=39778
        }
        installSubscriptionControlService() {
            printf 'install\n' >>"${callLog}"
            return 0
        }
        serviceQueueRestart() {
            printf 'restart:%s\n' "$1" >>"${callLog}"
            return 0
        }
        serviceQueueApply() {
            printf 'apply\n' >>"${callLog}"
            return 0
        }
        subscribe() {
            printf 'subscribe:%s\n' "$*" >>"${callLog}"
            return 0
        }
        regressionExpectStatus 1 subscriptionSyncReconcileLocalServices
        grep -qx 'reload' "${callLog}"
        [[ "$(wc -l <"${callLog}" | tr -d ' ')" == "1" ]]
    )

    : >"${callLog}"
    reloadCore() {
        printf 'reload\n' >>"${callLog}"
        return 0
    }
    subscriptionSyncReconcileLocalServices
    grep -qx 'reload' "${callLog}"
    [[ "$(wc -l <"${callLog}" | tr -d ' ')" == "1" ]]
)

runSubscriptionGroupsRestoreFailureRegression() (
    local root="${TMP_DIR}/subscription-groups-restore-failure"
    local groupsDir="${root}/groups"
    local currentBackup="${root}/current-backup.json"
    local targetBackup="${root}/target-backup.json"
    local stateFile="${groupsDir}/groups.json"
    local beforeSnapshot
    local rc

    export PADM_SUBSCRIPTION_GROUPS_DIR="${groupsDir}"
    TMPDIR="${root}"
    mkdir -p "${groupsDir}"
    cat >"${stateFile}" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"默认订阅组","admin":{"id":"admin","name":"我的订阅","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"本机","role":"main","transport":"local","scheme":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    beforeSnapshot=$(<"${stateFile}")
    cp "${stateFile}" "${currentBackup}"
    cat >"${targetBackup}" <<'JSON'
{"version":1,"active_group":"legacy","groups":[{"id":"legacy","name":"Legacy","sources":[],"user_groups":[],"sync":{"enabled":true},"traffic":{}}]}
JSON

    createSubscriptionGroupsBackup() {
        printf '%s\n' "${currentBackup}"
    }

    regressionExpectStatus 1 restoreSubscriptionGroupsBackup "${targetBackup}" >/dev/null 2>&1
    [[ "$(<"${stateFile}")" == "${beforeSnapshot}" ]]
    [[ -f "${currentBackup}" ]]

)

runSubscriptionGroupSyncUsesStateLockRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/subscription-group-sync-state-lock.log"

    subscriptionGroupsWithLock() {
        printf 'lock:%s\n' "$*" >>"${callLog}"
        "$@"
    }
    runSubscriptionGroupSyncUnlocked() {
        printf 'sync:%s\n' "$*" >>"${callLog}"
        return 17
    }

    set +e
    runSubscriptionGroupSync
    local status=$?
    set -e

    [[ "${status}" == "17" ]]
    grep -qx 'lock:runSubscriptionGroupSyncUnlocked' "${callLog}"
    grep -qx 'sync:' "${callLog}"
)
