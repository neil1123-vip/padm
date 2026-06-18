#!/usr/bin/env bash
set -euo pipefail

REGRESSION_ENTRY_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SUBSCRIPTION_STATE_SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")"
# shellcheck source=/dev/null
source "${REGRESSION_ENTRY_DIR}/regression/bootstrap.sh"

# PADM_SECTION_BEGIN: subscription-state-hot-regressions
writeSubscriptionStateDefaultFixture() {
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"remote-edge","name":"remote-edge","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"10.77.0.3","port":48779,"enabled":true,"sync_status":"pending","control_token":"token-def"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
}

writeSubscriptionStateLegacyEdgeGroupFixture() {
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{
  "version": 1,
  "active_group": "edge-group",
  "groups": [
    {
      "id": "edge-group",
      "name": "Edge Group",
      "sources": [
        {"id": "edge", "name": "Edge", "scheme": "https", "host": "example.com", "port": "443", "enabled": true, "sync_status": "failed", "last_sync_error": {"type": "unreachable", "message": "old"}}
      ],
      "user_groups": [
        {"id": "team-a", "name": "Team A", "enabled": true, "allowed_sources": ["edge"], "traffic_limit_gb": "1", "uuid": "11111111-1111-1111-1111-111111111111"}
      ],
      "sync": {"enabled": true},
      "traffic": {"user_groups": {"team-a": {"upload": 1, "download": 2, "sources": {"edge": {"upload": 1, "download": 2}}}}, "sources": {"edge": {"upload": 1, "download": 2}}, "admin": {"sources": {"edge": {"upload": 0, "download": 0}}}}
    }
  ]
}
JSON
}

writeSubscriptionStateMigratedEdgeGroupFixture() {
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"edge-group","groups":[{"id":"edge-group","name":"Edge Group","admin":{"id":"admin","name":"我的订阅","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"本机","role":"main","transport":"local","scheme":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge","name":"Edge","scheme":"https","host":"example.com","port":443,"enabled":true,"sync_status":"failed","last_sync_error":{"type":"unreachable","message":"old"}}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["edge"],"traffic_limit_gb":1,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{"edge":{"upload":0,"download":0}}},"user_groups":{"team-a":{"upload":1,"download":2,"sources":{"edge":{"upload":1,"download":2}}}},"sources":{"edge":{"upload":1,"download":2}}}}]}
JSON
}

writeSubscriptionStateSourceCredentialFixture() {
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"我的订阅","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"本机","role":"main","transport":"local","scheme":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"remote-edge","name":"remote-edge","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"10.77.0.2","port":39778,"enabled":true,"sync_status":"pending"}],"user_groups":[],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
}

writeSubscriptionStateSourceStatusFixture() {
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"我的订阅","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"本机","role":"main","transport":"local","scheme":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge","name":"Edge","role":"secondary","scheme":"https","transport":"wireguard","host":"example.com","port":443,"enabled":true,"sync_status":"failed","last_sync_error":{"type":"unreachable","message":"old"}}],"user_groups":[],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
}

writeSubscriptionStateSourceRemoveFixture() {
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"我的订阅","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"本机","role":"main","transport":"local","scheme":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge","name":"Edge","role":"secondary","scheme":"https","transport":"wireguard","host":"example.com","port":443,"enabled":true,"sync_status":"failed","last_sync_error":{"type":"unreachable","message":"old"}}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["edge"],"traffic_limit_gb":1,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{"team-a":{"upload":1,"download":2,"sources":{"edge":{"upload":1,"download":2}}}},"sources":{"edge":{"upload":1,"download":2}}}}]}
JSON
}

writeSubscriptionStateStructureFoundationFixture() {
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"remote_enabled":true,"quota_auto_apply":false},"traffic":{"admin":{"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
}

prepareSubscriptionStateQuotaUsageFixture() {
    mkdir -p "$(subscriptionGroupsDir)"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"remote-edge","name":"remote-edge","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"10.77.0.3","port":48779,"enabled":true,"sync_status":"pending","control_token":"token-def"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":1,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":2097152,"download":1048576,"sources":{"main":{"upload":2097152,"download":1048576,"updated_at":"2026-06-10 10:00:00"}}},"user_groups":{"team-a":{"upload":1073741824,"download":1,"sources":{"main":{"upload":1073741824,"download":1}}}},"sources":{"main":{"upload":2097152,"download":1048576,"updated_at":"2026-06-10 10:00:00"},"remote-edge":{"upload":1048576,"download":0,"updated_at":"2026-06-10 10:01:00"}}}}]}
JSON
}

runSubscriptionGroupStateStructureFoundationAddRemoveRegression() {
    mkdir -p "$(subscriptionGroupsDir)"
    writeSubscriptionStateStructureFoundationFixture
    jq -e '.version == 2 and .active_group == "default" and (.groups | length == 1)' "$(subscriptionGroupsFile)" >/dev/null

    addSubscriptionSourceState ip-edge "IP Edge" 203.0.113.10 39778
    jq -e '.groups[0].sources[] | select(.id == "ip-edge" and .scheme == "wireguard" and .transport == "wireguard" and .host == "203.0.113.10" and .port == 39778)' "$(subscriptionGroupsFile)" >/dev/null
    removeSubscriptionSourceState ip-edge
}

runSubscriptionGroupStateStructureFoundationCredentialRegression() {
    local credential decodedCredential invalidCredential
    credential=$(subscriptionWireGuardCredentialEncode controlled '{"address":"10.77.0.2/24","public_key":"pubkey-abc","control_port":39778,"token":"token-abc"}')
    decodedCredential=$(subscriptionWireGuardCredentialDecode "${credential}")
    jq -e '.kind == "controlled" and .address == "10.77.0.2/24" and .control_port == 39778 and .token == "token-abc"' <<<"${decodedCredential}" >/dev/null
    if subscriptionWireGuardCredentialDecode "remote.example.com:39778:token-abc" >/dev/null 2>&1; then
        return 1
    fi
    invalidCredential=$(subscriptionWireGuardCredentialEncode controlled '{"address":"10.77.0.2/24","public_key":"pubkey-abc","control_port":39778}')
    if subscriptionWireGuardCredentialDecode "${invalidCredential}" >/dev/null 2>&1; then
        return 1
    fi
    invalidCredential=$(subscriptionWireGuardCredentialEncode controlled '{"address":"10.77.999.2/24","public_key":"pubkey-abc","control_port":39778,"token":"token-abc"}')
    if subscriptionWireGuardCredentialDecode "${invalidCredential}" >/dev/null 2>&1; then
        return 1
    fi
    invalidCredential=$(subscriptionWireGuardCredentialEncode controlled '{"address":"10.77.0.2/24","public_key":"pubkey-abc","control_port":70000,"token":"token-abc"}')
    if subscriptionWireGuardCredentialDecode "${invalidCredential}" >/dev/null 2>&1; then
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
    [[ "$(subscriptionSyncAccountId "${accountDashUnderscore}")" == "team-a_b" ]]
    [[ "$(subscriptionSyncAccountId "${accountUnderscoreDash}")" == "team_a-b" ]]
    [[ "$(subscriptionSyncAccountId "${accountDashDash}")" == "team-a-b" ]]
}

runSubscriptionGroupStateStructureFoundationInitTransactionRegression() (
    local initRoot="${TMP_DIR}/subscription-state-init-transaction"
    local initGroupsDir="${initRoot}/groups"
    local initStateFile="${initGroupsDir}/groups.json"
    local oldGroupsDir="${PADM_SUBSCRIPTION_GROUPS_DIR:-}"
    local initStatus

    export PADM_SUBSCRIPTION_GROUPS_DIR="${initGroupsDir}"
    mkdir -p "${initRoot}"
    writeDefaultSubscriptionGroupsState() {
        printf '{bad-json\n' >"$1"
        return 1
    }

    set +e
    ensureSubscriptionGroupsState >/dev/null 2>&1
    initStatus=$?
    set -e

    [[ "${initStatus}" == "1" ]]
    [[ ! -e "${initStateFile}" ]]
    if regressionFindHasMatches "${initGroupsDir}" -maxdepth 1 -type f -name '.groups.json.init.*'; then
        return 1
    fi

    if [[ -n "${oldGroupsDir}" ]]; then export PADM_SUBSCRIPTION_GROUPS_DIR="${oldGroupsDir}"; else unset PADM_SUBSCRIPTION_GROUPS_DIR; fi
)

runSubscriptionGroupStateStructureFoundationSerialRegression() {
    runRegressionStep subscription-state-structure-foundation-add-remove runSubscriptionGroupStateStructureFoundationAddRemoveRegression &&
        runRegressionStep subscription-state-structure-foundation-credential runSubscriptionGroupStateStructureFoundationCredentialRegression &&
        runRegressionStep subscription-state-structure-foundation-normalize runSubscriptionGroupStateStructureFoundationNormalizeRegression &&
        runRegressionStep subscription-state-structure-foundation-init-transaction runSubscriptionGroupStateStructureFoundationInitTransactionRegression
}

runSubscriptionGroupStateStructureFoundationRegression() {
    runParallelSubscriptionStateModes \
        "${TMP_DIR}/subscription-state-structure-foundation" \
        add-remove subscription-state-structure-foundation-add-remove \
        credential subscription-state-structure-foundation-credential \
        normalize subscription-state-structure-foundation-normalize \
        init-transaction subscription-state-structure-foundation-init-transaction
}

runSubscriptionGroupStateStructureMigrationRegression() {
    mkdir -p "$(subscriptionGroupsDir)"
    writeSubscriptionStateLegacyEdgeGroupFixture
    ensureSubscriptionGroupsState
    jq -e '
      .version == 2 and
      .active_group == "edge-group" and
      (.groups[0].sync.remote_enabled == true) and
      (.groups[0].sync.quota_auto_apply == false) and
      any(.groups[0].sources[]; .id == "main" and .role == "main") and
      any(.groups[0].sources[]; .id == "edge" and .port == 443) and
      (.groups[0].user_groups[0].traffic_limit_gb == 1)
    ' "$(subscriptionGroupsFile)" >/dev/null

    (
        local summaryOutput
        menuLine() { printf 'menu:%s\n' "$*"; }
        summaryOutput=$(showSubscriptionGroupsStateSummary)
        [[ "${summaryOutput}" == *"当前组：Edge Group(edge-group)"* ]]
        [[ "${summaryOutput}" == *"分享订阅：1 个，启用 1 个"* ]]
        [[ "${summaryOutput}" == *"服务器源：2 个，启用远端 1 个"* ]]
    )

    (
        local resetRoot="${TMP_DIR}/subscription-groups-reset-failure"
        local resetGroupsDir="${resetRoot}/groups"
        local resetStateFile="${resetGroupsDir}/groups.json"
        local resetErrorLog="${resetRoot}/error.log"
        local resetCurrentBackup
        local resetBeforeSnapshot
        local resetStatus
        local oldGroupsDir="${PADM_SUBSCRIPTION_GROUPS_DIR:-}"
        local oldTmpDir="${TMPDIR:-}"

        export PADM_SUBSCRIPTION_GROUPS_DIR="${resetGroupsDir}"
        TMPDIR="${resetRoot}"
        REGRESSION_ERROR_CARD_LOG="${resetErrorLog}"
        mkdir -p "${resetGroupsDir}"
        cat >"${resetStateFile}" <<'JSON'
{"version":2,"active_group":"legacy","groups":[{"id":"legacy","name":"Legacy","admin":{"id":"admin","name":"我的订阅","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"本机","role":"main","transport":"local","scheme":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["main"],"traffic_limit_gb":0,"token":"","uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
        resetBeforeSnapshot=$(<"${resetStateFile}")
        resetCurrentBackup="${resetGroupsDir}/backups/groups-current.json"

        showSubscriptionGroupsStateSummary() { return 0; }
        autoRead() {
            local targetVar=$3
            printf -v "${targetVar}" '%s' "yes"
        }
        createSubscriptionGroupsBackup() {
            mkdir -p "${resetGroupsDir}/backups" || return 1
            cp "${resetStateFile}" "${resetCurrentBackup}" || return 1
            printf '%s\n' "${resetCurrentBackup}"
        }
        migrateSubscriptionGroupsState() {
            return 1
        }

        : >"${resetErrorLog}"
        set +e
        resetSubscriptionGroupsStateMenu >/dev/null 2>&1
        resetStatus=$?
        set -e
        unset -f showSubscriptionGroupsStateSummary
        unset -f statusCard
        unset -f successCard
        unset -f autoRead
        unset -f createSubscriptionGroupsBackup
        unset -f migrateSubscriptionGroupsState
        [[ "${resetStatus}" == "1" ]]
        [[ "$(<"${resetStateFile}")" == "${resetBeforeSnapshot}" ]]
        grep -q '订阅状态重建失败，已恢复旧状态' "${resetErrorLog}"
        [[ -f "${resetCurrentBackup}" ]]
        if regressionFindHasMatches "${resetGroupsDir}" -maxdepth 1 -type f -name '.groups.json.reset.*'; then
            return 1
        fi

        if [[ -n "${oldGroupsDir}" ]]; then export PADM_SUBSCRIPTION_GROUPS_DIR="${oldGroupsDir}"; else unset PADM_SUBSCRIPTION_GROUPS_DIR; fi
        if [[ -n "${oldTmpDir}" ]]; then TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    )
}

runSubscriptionGroupStateStructureSourceCredentialRegression() {
    mkdir -p "$(subscriptionGroupsDir)"
    writeSubscriptionStateSourceCredentialFixture
    subscriptionGroupsStateWrite --arg groupId "$(activeSubscriptionGroupId)" --arg id remote-edge --arg token "token-abc" '
      .groups |= map(if .id == $groupId then
        .sources |= map(if .id == $id and .role != "main" then .control_token = $token else . end)
      else . end)'
    jq -e '.groups[0].sources[] | select(.id == "remote-edge" and .scheme == "wireguard" and .transport == "wireguard" and .host == "10.77.0.2" and .port == 39778 and .control_token == "token-abc")' "$(subscriptionGroupsFile)" >/dev/null
    setSubscriptionSourceCredential remote-edge "10.77.0.3" 48779 "token-def"
    jq -e '.groups[0].sources[] | select(.id == "remote-edge" and .scheme == "wireguard" and .transport == "wireguard" and .host == "10.77.0.3" and .port == 48779 and .control_token == "token-def")' "$(subscriptionGroupsFile)" >/dev/null
}

runSubscriptionGroupStateStructureSourceStatusRegression() {
    mkdir -p "$(subscriptionGroupsDir)"
    writeSubscriptionStateSourceStatusFixture
    subscriptionGroupsStateWrite --arg groupId "$(activeSubscriptionGroupId)" --arg id edge --argjson enabled false '
      .groups |= map(if .id == $groupId then
        .sources |= map(if .id == $id and .role != "main" then .enabled = $enabled else . end)
      else . end)'
    jq -e '.groups[0].sources[] | select(.id == "edge" and .enabled == false)' "$(subscriptionGroupsFile)" >/dev/null
    subscriptionGroupsStateWrite --arg groupId "$(activeSubscriptionGroupId)" --arg id main --argjson enabled false '
      .groups |= map(if .id == $groupId then
        .sources |= map(if .id == $id and .role != "main" then .enabled = $enabled else . end)
      else . end)'
    jq -e '.groups[0].sources[] | select(.id == "main" and .enabled == true)' "$(subscriptionGroupsFile)" >/dev/null
    clearSubscriptionSourceSyncError edge
    jq -e '(.groups[0].sources[] | select(.id == "edge") | has("last_sync_error")) | not' "$(subscriptionGroupsFile)" >/dev/null
}

runSubscriptionGroupStateStructureSourceRemoveRegression() {
    mkdir -p "$(subscriptionGroupsDir)"
    writeSubscriptionStateSourceRemoveFixture
    removeSubscriptionSourceState edge
    jq -e '(.groups[0].sources | map(.id) | index("edge") | not) and (.groups[0].traffic.sources | has("edge") | not) and (.groups[0].traffic.user_groups["team-a"].sources | has("edge") | not)' "$(subscriptionGroupsFile)" >/dev/null
}

runSubscriptionGroupStateStructureSourceSerialRegression() {
    runRegressionStep subscription-state-structure-source-credential runSubscriptionGroupStateStructureSourceCredentialRegression &&
        runRegressionStep subscription-state-structure-source-status runSubscriptionGroupStateStructureSourceStatusRegression &&
        runRegressionStep subscription-state-structure-source-remove runSubscriptionGroupStateStructureSourceRemoveRegression
}

runSubscriptionGroupStateStructureSourceRegression() {
    runSubscriptionGroupStateStructureSourceSerialRegression
}

runSubscriptionGroupStateStructureSerialRegression() {
    runRegressionStep subscription-state-structure-foundation-serial runSubscriptionGroupStateStructureFoundationSerialRegression &&
        runRegressionStep subscription-state-structure-migration runSubscriptionGroupStateStructureMigrationRegression &&
        runRegressionStep subscription-state-structure-source-serial runSubscriptionGroupStateStructureSourceSerialRegression
}

runSubscriptionGroupStateStructureRegression() {
    runParallelSubscriptionStateModes \
        "${TMP_DIR}/subscription-state-structure" \
        foundation subscription-state-structure-foundation \
        migration subscription-state-structure-migration \
        source subscription-state-structure-source
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
    )
    subscriptionQuotaDryRunPlan | jq -e 'length == 1 and .[0].id == "team-a" and .[0].limit_gb == 1 and .[0].percent >= 100 and .[0].action == "disable-and-remove-local-account"' >/dev/null
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
    jq -e '.groups[0].user_groups[] | select(.id == "team-a" and .enabled == false)' "$(subscriptionGroupsFile)" >/dev/null
}

runSubscriptionGroupStateQuotaTrafficSerialRegression() {
    runRegressionStep subscription-state-quota-traffic-summary runSubscriptionGroupStateQuotaTrafficSummaryRegression &&
        runRegressionStep subscription-state-quota-traffic-invalid-input runSubscriptionGroupStateQuotaTrafficInvalidInputRegression &&
        runRegressionStep subscription-state-quota-traffic-apply runSubscriptionGroupStateQuotaTrafficApplyRegression
}

runSubscriptionGroupStateQuotaTrafficRegression() {
    runSubscriptionGroupStateQuotaTrafficSerialRegression
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
        mkdir -p "${quotaTxRoot}/groups"
        export PADM_SUBSCRIPTION_GROUPS_DIR="${quotaTxRoot}/groups"
        quotaTxStateFile=$(subscriptionGroupsFile)
        quotaTxBackupDir="$(subscriptionGroupsBackupDir)"
        cat >"${quotaTxStateFile}" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":1,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{"team-a":{"upload":1073741824,"download":1,"sources":{"main":{"upload":1073741824,"download":1}}}},"sources":{"main":{"upload":2097152,"download":1048576,"updated_at":"2026-06-10 10:00:00"}}}}]}
JSON
        quotaTxPlan=$(subscriptionQuotaDryRunPlan)
        createSubscriptionGroupsBackup() {
            local backupFile="${quotaTxBackupDir}/groups-current.json"
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
        set +e
        applySubscriptionQuotaPlanTransaction "${quotaTxPlan}"
        quotaTxStatus=$?
        set -e
        [[ "${quotaTxStatus}" == "1" ]]
        jq -e '.groups[0].user_groups[] | select(.id == "team-a" and .enabled == true)' "$(subscriptionGroupsFile)" >/dev/null
        [[ "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR}" == *"已恢复旧订阅状态"* ]]
        if regressionFindHasMatches "${quotaTxRoot}/groups/backups" -maxdepth 1 -type f -name 'groups-*.json'; then
            return 1
        fi
    )
}

runSubscriptionGroupStateQuotaMenuTransactionSerialRegression() {
    runRegressionStep subscription-state-quota-menu-preview-fail runSubscriptionGroupStateQuotaMenuPreviewFailureRegression &&
        runRegressionStep subscription-state-quota-menu-tx-rollback runSubscriptionGroupStateQuotaTransactionRollbackRegression
}

runSubscriptionGroupStateQuotaMenuTransactionRegression() {
    runSubscriptionGroupStateQuotaMenuTransactionSerialRegression
}

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
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":1,"uuid":"11111111-1111-1111-1111-111111111111"},{"id":"team-b","name":"Team B","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":1,"uuid":"22222222-2222-2222-2222-222222222222"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
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
            subscriptionGroupsStateWrite --arg groupId "default" --arg id "${id}" --argjson enabled "${enabled}" '.groups |= map(if .id == $groupId then .user_groups |= map(if .id == $id then .enabled = $enabled else . end) else . end)'
        }
        subscriptionSyncApplyAccountPlanTransaction() {
            printf 'called\n' >"${accountPhaseMarker}"
            return 0
        }
        set +e
        applySubscriptionQuotaPlanTransaction "${quotaPartialPlan}"
        quotaPartialStatus=$?
        set -e
        [[ "${quotaPartialStatus}" == "1" ]]
        jq -e '.groups[0].user_groups[] | select(.id == "team-a" and .enabled == true)' "$(subscriptionGroupsFile)" >/dev/null
        jq -e '.groups[0].user_groups[] | select(.id == "team-b" and .enabled == true)' "$(subscriptionGroupsFile)" >/dev/null
        [[ ! -e "${accountPhaseMarker}" ]]
        [[ "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR}" == *"停用超额分享订阅失败"* ]]
        if regressionFindHasMatches "${quotaPartialRoot}/groups/backups" -maxdepth 1 -type f -name 'groups-*.json'; then
            return 1
        fi
    )
}

runSubscriptionGroupStateQuotaPartialSyncPlanRegression() {
    (
        subscriptionSyncPlanFromAccounts() {
            jq -n '{create:[], remove:["sub_team_a"]}'
        }
        subscriptionSyncPlan | jq -e '.remove | index("sub_team_a")' >/dev/null
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
{"inbounds":[{"settings":{"clients":[{"email":"sub_team_a-VLESS_TCP/TLS_Vision"},{"email":"sub_team_b-VLESS_TCP/TLS_Vision"}]}}]}
JSON
    cat >"${singBoxConfigPath}06_hysteria2_inbounds.json" <<'JSON'
{"inbounds":[{"users":[{"name":"sub_team_a-singbox_hysteria2"},{"username":"sub_team_b-singbox_hysteria2"}]}]}
JSON
    subscriptionSyncConfiguredManagedUsers | jq -R -e -s 'split("\n") | map(select(length > 0)) | sort == ["sub_team_a-main", "sub_team_b-main"]' >/dev/null
    subscriptionSyncPlanFromAccounts $'sub_team_a-main' | jq -e '.create == [] and .remove == ["sub_team_b-main"]' >/dev/null
    printf '{bad-json' >"${configPath}99_broken_inbounds.json"
    set +e
    subscriptionSyncPlanFromAccounts $'sub_team_a' >/dev/null 2>&1
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
        grep -qx 'skip-subscribe-refresh' "${TMP_DIR}/subscription-group-sync-cron-args.log"
    )
}

runSubscriptionGroupStateQuotaPartialSyncSerialRegression() {
    runRegressionStep subscription-state-quota-partial-sync-apply-failure runSubscriptionGroupStateQuotaPartialSyncApplyFailureRegression &&
        runRegressionStep subscription-state-quota-partial-sync-plan runSubscriptionGroupStateQuotaPartialSyncPlanRegression &&
        runRegressionStep subscription-state-quota-partial-sync-config runSubscriptionGroupStateQuotaPartialSyncConfigRegression
}

runSubscriptionGroupStateQuotaPartialSyncRegression() {
    runSubscriptionGroupStateQuotaPartialSyncSerialRegression
}

runSubscriptionGroupStateQuotaSerialRegression() {
    runRegressionStep subscription-state-quota-traffic-serial runSubscriptionGroupStateQuotaTrafficSerialRegression &&
        runRegressionStep subscription-state-quota-menu-tx-serial runSubscriptionGroupStateQuotaMenuTransactionSerialRegression &&
        runRegressionStep subscription-state-quota-partial-sync-serial runSubscriptionGroupStateQuotaPartialSyncSerialRegression
}

runSubscriptionGroupStateQuotaRegression() {
    runParallelSubscriptionStateModes \
        "${TMP_DIR}/subscription-state-quota" \
        traffic subscription-state-quota-traffic \
        menu-tx subscription-state-quota-menu-tx \
        partial-sync subscription-state-quota-partial-sync
}

prepareSubscriptionRemoteRestoreSelfReferenceFixture() {
    currentHost="self.example.com"
    subscribeDomain="self.example.com"
    subscribePort=39778
    PADM_WIREGUARD_CONTROL_DIR="${TMP_DIR}/subscription-state-wireguard"
    mkdir -p "$(subscriptionWireGuardDir)"
    cat >"$(subscriptionWireGuardStateFile)" <<'JSON'
{"enabled":true,"role":"main","address":"10.77.0.1/24","peers":[]}
JSON
    mkdir -p "$(subscriptionGroupsDir)"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"remote-edge","name":"remote-edge","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"10.77.0.3","port":48779,"enabled":false,"sync_status":"pending","control_token":"token-def"},{"id":"self-ref","name":"SelfRef","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"10.77.0.1","port":39778,"enabled":true,"sync_status":"pending","control_token":"token"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["self-ref"],"traffic_limit_gb":0,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
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
    runSubscriptionRemoteSync | jq -e '.[] | contains("self-ref")' >/dev/null
    subscriptionGroupsStateRead -e '.groups[0].sources[] | select(.id == "self-ref" and .sync_status == "failed" and .last_sync_error.type == "self_reference")' >/dev/null
}

runSubscriptionGroupStateRemoteRestoreSelfReferenceSerialRegression() {
    runRegressionStep subscription-state-remote-restore-self-reference-plan runSubscriptionGroupStateRemoteRestoreSelfReferencePlanRegression &&
        runRegressionStep subscription-state-remote-restore-self-reference-sync runSubscriptionGroupStateRemoteRestoreSelfReferenceSyncRegression
}

runSubscriptionGroupStateRemoteRestoreSelfReferenceRegression() {
    runSubscriptionGroupStateRemoteRestoreSelfReferenceSerialRegression
}

runSubscriptionGroupStateRemoteRestoreStateWriteRegression() {
    mkdir -p "$(subscriptionGroupsDir)"
    writeSubscriptionStateDefaultFixture

    local stateSnapshot badBackup
    stateSnapshot=$(<"$(subscriptionGroupsFile)")
    if subscriptionGroupsStateWrite '.groups = "broken" | .dangling = ' 2>/dev/null; then
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
}

runSubscriptionGroupStateRemoteRestoreLegacyMenuRegression() {
    mkdir -p "$(subscriptionGroupsDir)"
    writeSubscriptionStateDefaultFixture

    local legacyBackup menuBackup
    legacyBackup="${TMP_DIR}/legacy-groups-backup.json"
    cat >"${legacyBackup}" <<'JSON'
{"version":1,"active_group":"legacy","groups":[{"id":"legacy","name":"Legacy","sources":[],"user_groups":[],"sync":{"enabled":true},"traffic":{}}]}
JSON
    restoreSubscriptionGroupsBackup "${legacyBackup}"
    jq -e '.version == 2 and .active_group == "legacy" and any(.groups[0].sources[]; .role == "main") and (.groups[0].sync.remote_enabled == true)' "$(subscriptionGroupsFile)" >/dev/null

    menuBackup="${TMP_DIR}/legacy-menu-backup.json"
    jq '.active_group = "legacy" | .groups[0].id = "legacy" | .groups[0].name = "Legacy"' "$(subscriptionGroupsFile)" >"${menuBackup}"
    jq empty "${menuBackup}" >/dev/null
    subscriptionGroupsStateWrite '.active_group = "changed" | .groups[0].id = "changed" | .groups[0].name = "Changed"'
    (
        local menuOutput
        listSubscriptionGroupsBackups() {
            printf '%s\n' "${menuBackup}"
        }
        createSubscriptionGroupsBackup() {
            cp "$(subscriptionGroupsFile)" "${TMP_DIR}/legacy-menu-current-backup.json" || return 1
            printf '%s\n' "${TMP_DIR}/legacy-menu-current-backup.json"
        }
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
    jq -e '.version == 2 and .active_group == "legacy" and .groups[0].id == "legacy"' "$(subscriptionGroupsFile)" >/dev/null
}

runSubscriptionGroupStateRemoteRestoreSerialRegression() {
    runRegressionStep subscription-state-remote-restore-self-reference runSubscriptionGroupStateRemoteRestoreSelfReferenceRegression &&
        runRegressionStep subscription-state-remote-restore-state-write runSubscriptionGroupStateRemoteRestoreStateWriteRegression &&
        runRegressionStep subscription-state-remote-restore-legacy-menu runSubscriptionGroupStateRemoteRestoreLegacyMenuRegression
}

runSubscriptionGroupStateRemoteRestoreRegression() {
    runParallelSubscriptionStateModes \
        "${TMP_DIR}/subscription-state-remote-restore" \
        self-reference subscription-state-remote-restore-self-reference \
        state-write subscription-state-remote-restore-state-write \
        legacy-menu subscription-state-remote-restore-legacy-menu
}

runSubscriptionGroupStateRegression() {
    runRegressionStep subscription-state-structure-serial runSubscriptionGroupStateStructureSerialRegression &&
        runRegressionStep subscription-state-quota-serial runSubscriptionGroupStateQuotaSerialRegression &&
        runRegressionStep subscription-state-remote-restore-serial runSubscriptionGroupStateRemoteRestoreSerialRegression
}
# PADM_SECTION_END: subscription-state-hot-regressions

runSubscriptionSyncTempDirRegression() (
    local oldTmpDir="${TMPDIR:-}"
    local oldConfigPath="${configPath:-}"
    local oldSingBoxConfigPath="${singBoxConfigPath:-}"
    local oldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
    local oldPublicDir="${PADM_SUBSCRIBE_DIR:-}"
    local tmpRoot="${TMP_DIR}/subscription-sync-tmp"
    local syncConfigRoot="${TMP_DIR}/subscription-sync-tempdir-config"
    local localDir="${TMP_DIR}/subscription-sync-tempdir-local"
    local publicDir="${TMP_DIR}/subscription-sync-tempdir-public"
    local backupDir
    local outputBackupDir

    mkdir -p "${tmpRoot}" "${syncConfigRoot}/xray" "${syncConfigRoot}/sing-box" "${localDir}/default" "${publicDir}/default"
    TMPDIR="${tmpRoot}"
    configPath="${syncConfigRoot}/xray/"
    singBoxConfigPath="${syncConfigRoot}/sing-box/"
    cat >"${configPath}01_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_team_a-main"}]}}]}
JSON

    backupDir=$(subscriptionSyncCreateConfigBackups)
    [[ "${backupDir}" == "${tmpRoot}"/padm-subscription-sync-backup.* ]]
    [[ -f "${backupDir}/manifest" ]]
    padmRemoveCleanupPath "${backupDir}"

    export PADM_SUBSCRIBE_LOCAL_DIR="${localDir}"
    export PADM_SUBSCRIBE_DIR="${publicDir}"
    printf 'local\n' >"${localDir}/default/user"
    printf 'public\n' >"${publicDir}/default/user"
    outputBackupDir=$(subscriptionSyncCreateSubscribeOutputBackups)
    [[ "${outputBackupDir}" == "${tmpRoot}"/padm-subscription-output-backup.* ]]
    [[ -f "${outputBackupDir}/local.exists" && -f "${outputBackupDir}/public.exists" ]]
    padmRemoveCleanupPath "${outputBackupDir}"

    if regressionFindHasMatches "${tmpRoot}" -mindepth 1 -maxdepth 1 -type d; then
        return 1
    fi
    configPath="${oldConfigPath}"
    singBoxConfigPath="${oldSingBoxConfigPath}"
    if [[ -n "${oldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${oldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
    if [[ -n "${oldPublicDir}" ]]; then export PADM_SUBSCRIBE_DIR="${oldPublicDir}"; else unset PADM_SUBSCRIBE_DIR; fi
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runSubscriptionSyncRestorePairFailureMessageRegression() (
    local message=
    local detail=
    local rc

    set +e
    subscriptionSyncSetRestorePairFailureMessage message \
        "本机同步失败" \
        true "配置" "备份目录: /tmp/config" \
        true "订阅输出" "备份目录: /tmp/output" \
        "备份目录: /tmp/config 和 /tmp/output"
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
    [[ -z "${message}" ]]

    set +e
    subscriptionSyncSetRestorePairFailureMessage message \
        "本机同步失败" \
        false "配置" "备份目录: /tmp/config" \
        true "订阅输出" "备份目录: /tmp/output" \
        "备份目录: /tmp/config 和 /tmp/output"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "本机同步失败，且配置恢复失败，请手动检查备份目录: /tmp/config" ]]

    set +e
    subscriptionSyncSetRestorePairFailureMessage message \
        "本机同步失败" \
        true "配置" "备份目录: /tmp/config" \
        false "订阅输出" "备份目录: /tmp/output" \
        "备份目录: /tmp/config 和 /tmp/output"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "本机同步失败，且订阅输出恢复失败，请手动检查备份目录: /tmp/output" ]]

    set +e
    subscriptionSyncSetRestorePairFailureMessage message \
        "本机同步失败" \
        false "配置" "备份目录: /tmp/config" \
        false "订阅输出" "备份目录: /tmp/output" \
        "备份目录: /tmp/config 和 /tmp/output"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "本机同步失败，且配置与订阅输出恢复失败，请手动检查备份目录: /tmp/config 和 /tmp/output" ]]

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
    local rc

    set +e
    subscriptionSyncSetSingleRestoreResultMessage message \
        "限额自动执行失败" \
        true \
        "已恢复旧订阅状态" \
        "订阅状态" \
        "备份文件: /tmp/groups.json"
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
    [[ "${message}" == "限额自动执行失败，已恢复旧订阅状态" ]]

    set +e
    subscriptionSyncSetSingleRestoreResultMessage message \
        "限额自动执行失败" \
        false \
        "已恢复旧订阅状态" \
        "订阅状态" \
        "备份文件: /tmp/groups.json"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "限额自动执行失败，且订阅状态恢复失败，请手动检查备份文件: /tmp/groups.json" ]]

    subscriptionSyncSetManualCheckMessage detail "订阅状态恢复失败" "备份文件: /tmp/groups.json"
    [[ "${detail}" == "订阅状态恢复失败，请手动检查备份文件: /tmp/groups.json" ]]

    set +e
    subscriptionSyncSetSingleRestoreResultMessage message \
        "控制面同步期望用户状态写入失败" \
        true \
        "" \
        "订阅状态" \
        "$(subscriptionGroupsFile)"
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
    [[ "${message}" == "控制面同步期望用户状态写入失败" ]]

    set +e
    subscriptionSyncSetSingleRestoreResultMessage message \
        "Xray 流量统计策略配置写入失败" \
        false \
        "已恢复旧配置" \
        "旧配置" \
        "备份目录: /tmp/stats-backup"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "Xray 流量统计策略配置写入失败，且旧配置恢复失败，请手动检查备份目录: /tmp/stats-backup" ]]

    set +e
    subscriptionSyncSetSingleRestoreResultMessage message \
        "订阅 Nginx 配置校验失败" \
        false \
        "已恢复旧配置" \
        "旧配置" \
        " /tmp/subscribe.conf 和 /tmp/.subscribe.conf.backup.123456"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "订阅 Nginx 配置校验失败，且旧配置恢复失败，请手动检查 /tmp/subscribe.conf 和 /tmp/.subscribe.conf.backup.123456" ]]

    set +e
    subscriptionSyncSetSingleRestoreResultMessage message \
        "订阅生成失败" \
        false \
        "已恢复旧订阅输出" \
        "旧订阅输出" \
        "备份目录: /tmp/subscribe-output-backup"
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "订阅生成失败，且旧订阅输出恢复失败，请手动检查备份目录: /tmp/subscribe-output-backup" ]]

    set +e
    subscriptionSyncSetSingleRestoreResultMessage message \
        "订阅生成失败" \
        true \
        "已恢复旧订阅输出" \
        "旧订阅输出" \
        "备份目录: /tmp/subscribe-output-backup"
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
    [[ "${message}" == "订阅生成失败，已恢复旧订阅输出" ]]

    set +e
    subscriptionSyncSetSingleRestoreResultMessage message \
        "WireGuard 主控服务启动失败" \
        false \
        "" \
        "旧状态" \
        "" \
        false
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    [[ "${message}" == "WireGuard 主控服务启动失败，且旧状态恢复失败" ]]
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

    set +e
    subscriptionSyncApplyAccountPlanTransaction '{"create":["sub_new"],"remove":[]}'
    rc=$?
    set -e
    unset -f cp subscriptionSyncApplyAccountPlan initXrayClients subscriptionSyncGenerateUUID

    [[ "${rc}" == "1" ]]
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
    set +e
    subscriptionSyncRestoreBackupPath "${restoreDirTarget}" "${restoreDirBackup}" local
    restoreStatus=$?
    set -e
    unset -f cp
    [[ "${restoreStatus}" == "1" ]]
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

    set +e
    applySubscriptionQuotaPlanAccounts '[{"id":"team-a","action":"disable-and-remove-local-account"}]'
    reloadStatus=$?
    set -e
    [[ "${reloadStatus}" == "1" ]]
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
    local originalConfig
    local syncStatus

    mkdir -p "${syncRoot}/xray" "${syncRoot}/subscribe_local/default" "${syncRoot}/subscribe/default" "${syncRoot}/groups" "${syncRoot}/tmp"
    configPath="${syncRoot}/xray/"
    singBoxConfigPath="${syncRoot}/xray/"
    export PADM_SUBSCRIPTION_GROUPS_DIR="${syncRoot}/groups"
    export PADM_SUBSCRIBE_LOCAL_DIR="${syncRoot}/subscribe_local"
    export PADM_SUBSCRIBE_DIR="${syncRoot}/subscribe"
    TMPDIR="${syncRoot}/tmp"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge-a","name":"Edge A","role":"secondary","scheme":"https","host":"edge.example.com","port":443,"enabled":true,"sync_status":"pending","control_token":"token-a"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    cat >"${syncConfigFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_old-main"}]}}]}
JSON
    printf 'old-local\n' >"${syncLocalFile}"
    printf 'old-public\n' >"${syncPublicFile}"
    originalConfig=$(<"${syncConfigFile}")

    subscriptionGroupQuotaAutoApplyEnabled() { return 1; }
    subscriptionGroupRemoteSyncEnabled() { return 0; }
    collectSubscriptionTraffic() { return 0; }
    readInstallType() { return 0; }
    readInstallProtocolType() { return 0; }
    readConfigHostPathUUID() { return 0; }
    subscriptionSyncPlan() {
        printf '{"create":["sub_team_a"],"remove":[]}'
    }
    subscriptionSyncApplyAccountPlanTransaction() {
        SUBSCRIPTION_SYNC_TRANSACTION_ERROR="本机同步计划应用失败"
        return 1
    }
    subscriptionSyncReconcileLocalServices() {
        printf 'reconcile\n' >>"${reconcileLog}"
        return 0
    }
    runSubscriptionRemoteSync() {
        printf 'remote\n' >>"${remoteLog}"
        printf '[]'
    }
    subscriptionSyncMarkResult() {
        printf '%s\n' "$1" >"${resultStatus}"
        printf '%s\n' "$2" >"${resultFailures}"
        return 0
    }
    successCard() { printf '%s\n' "$*" >"${statusLog}"; }
    statusCard() { printf '%s\n' "$*" >"${statusLog}"; }

    set +e
    runSubscriptionGroupSync
    syncStatus=$?
    set -e
    [[ "${syncStatus}" == "1" ]]
    [[ "$(<"${syncConfigFile}")" == "${originalConfig}" ]]
    [[ "$(<"${syncLocalFile}")" == "old-local" ]]
    [[ "$(<"${syncPublicFile}")" == "old-public" ]]
    [[ ! -e "${remoteLog}" ]]
    [[ ! -e "${reconcileLog}" ]]
    grep -q '本机同步计划应用失败' "${resultFailures}"
    grep -q '本机同步未完成，已跳过被控服务器同步' "${resultFailures}"
    grep -q '本机同步未完全完成' "${statusLog}"
    grep -qx 'partial' "${resultStatus}"
    if regressionFindHasMatches "${syncRoot}/tmp" -maxdepth 1 -type d \( -name 'padm-subscription-sync-backup.*' -o -name 'padm-subscription-output-backup.*' \); then
        return 1
    fi
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

    mkdir -p "${syncRoot}/xray" "${syncRoot}/subscribe_local/default" "${syncRoot}/subscribe/default" "${syncRoot}/groups" "${syncRoot}/tmp"
    configPath="${syncRoot}/xray/"
    singBoxConfigPath="${syncRoot}/xray/"
    export PADM_SUBSCRIPTION_GROUPS_DIR="${syncRoot}/groups"
    export PADM_SUBSCRIBE_LOCAL_DIR="${syncRoot}/subscribe_local"
    export PADM_SUBSCRIBE_DIR="${syncRoot}/subscribe"
    TMPDIR="${syncRoot}/tmp"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge-a","name":"Edge A","role":"secondary","scheme":"https","host":"edge.example.com","port":443,"enabled":true,"sync_status":"pending","control_token":"token-a"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    cat >"${syncConfigFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_old-main"}]}}]}
JSON
    printf 'old-local\n' >"${syncLocalFile}"
    printf 'old-public\n' >"${syncPublicFile}"
    originalConfig=$(<"${syncConfigFile}")

    subscriptionGroupQuotaAutoApplyEnabled() { return 1; }
    subscriptionGroupRemoteSyncEnabled() { return 0; }
    collectSubscriptionTraffic() { return 0; }
    readInstallType() { return 0; }
    readInstallProtocolType() { return 0; }
    readConfigHostPathUUID() { return 0; }
    subscriptionSyncPlan() {
        printf '{"create":["sub_team_a"],"remove":[]}'
    }
    subscriptionSyncApplyAccountPlanTransaction() {
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
        printf '[]'
    }
    subscriptionSyncMarkResult() {
        printf '%s\n' "$1" >"${resultStatus}"
        printf '%s\n' "$2" >"${resultFailures}"
        return 0
    }
    successCard() { printf '%s\n' "$*" >"${statusLog}"; }
    statusCard() { printf '%s\n' "$*" >"${statusLog}"; }

    set +e
    runSubscriptionGroupSync
    syncStatus=$?
    set -e
    [[ "${syncStatus}" == "1" ]]
    [[ "$(<"${syncConfigFile}")" == "${originalConfig}" ]]
    [[ "$(<"${syncLocalFile}")" == "old-local" ]]
    [[ "$(<"${syncPublicFile}")" == "old-public" ]]
    [[ ! -e "${remoteLog}" ]]
    [[ "$(wc -l <"${reconcileLog}" | tr -d ' ')" == "2" ]]
    grep -qx '<empty>' "${reconcileLog}"
    grep -qx 'true' "${reconcileLog}"
    grep -q '本机同步后服务重建失败，已恢复旧配置' "${resultFailures}"
    grep -q '本机同步未完成，已跳过被控服务器同步' "${resultFailures}"
    grep -q '本机同步未完全完成' "${statusLog}"
    grep -qx 'partial' "${resultStatus}"
    if regressionFindHasMatches "${syncRoot}/tmp" -maxdepth 1 -type d \( -name 'padm-subscription-sync-backup.*' -o -name 'padm-subscription-output-backup.*' \); then
        return 1
    fi
)

runSubscriptionGroupSyncRemoteFailureRegression() (
    local syncRoot="${TMP_DIR}/subscription-group-sync-remote-failure"
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

    mkdir -p "${syncRoot}/xray" "${syncRoot}/subscribe_local/default" "${syncRoot}/subscribe/default" "${syncRoot}/groups" "${syncRoot}/tmp"
    configPath="${syncRoot}/xray/"
    singBoxConfigPath="${syncRoot}/xray/"
    export PADM_SUBSCRIPTION_GROUPS_DIR="${syncRoot}/groups"
    export PADM_SUBSCRIBE_LOCAL_DIR="${syncRoot}/subscribe_local"
    export PADM_SUBSCRIBE_DIR="${syncRoot}/subscribe"
    TMPDIR="${syncRoot}/tmp"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge-a","name":"Edge A","role":"secondary","scheme":"https","host":"edge.example.com","port":443,"enabled":true,"sync_status":"pending","control_token":"token-a"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"11111111-1111-1111-1111-111111111111"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    cat >"${syncConfigFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_old-main"}]}}]}
JSON
    printf 'old-local\n' >"${syncLocalFile}"
    printf 'old-public\n' >"${syncPublicFile}"
    originalConfig=$(<"${syncConfigFile}")

    subscriptionGroupQuotaAutoApplyEnabled() { return 1; }
    subscriptionGroupRemoteSyncEnabled() { return 0; }
    collectSubscriptionTraffic() { return 0; }
    readInstallType() { return 0; }
    readInstallProtocolType() { return 0; }
    readConfigHostPathUUID() { return 0; }
    subscriptionSyncPlan() {
        printf '{"create":["sub_team_a"],"remove":[]}'
    }
    subscriptionSyncApplyAccountPlanTransaction() {
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
        fi
        return 0
    }
    runSubscriptionRemoteSync() {
        printf 'remote\n' >>"${remoteLog}"
        printf '["被控服务器同步失败"]'
    }
    subscriptionSyncMarkResult() {
        printf '%s\n' "$1" >"${resultStatus}"
        printf '%s\n' "$2" >"${resultFailures}"
        return 0
    }
    successCard() { printf '%s\n' "$*" >"${statusLog}"; }
    statusCard() { printf '%s\n' "$*" >"${statusLog}"; }

    set +e
    runSubscriptionGroupSync
    syncStatus=$?
    set -e
    [[ "${syncStatus}" == "1" ]]
    [[ "$(<"${syncConfigFile}")" != "${originalConfig}" ]]
    grep -q 'sub_new-main' "${syncConfigFile}"
    [[ "$(<"${syncLocalFile}")" == "new-local" ]]
    [[ "$(<"${syncPublicFile}")" == "new-public" ]]
    grep -qx 'remote' "${remoteLog}"
    grep -q '被控服务器同步失败' "${resultFailures}"
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

    mkdir -p "${syncRoot}/xray" "${syncRoot}/subscribe_local/default" "${syncRoot}/subscribe/default" "${syncRoot}/groups" "${syncRoot}/tmp"
    configPath="${syncRoot}/xray/"
    singBoxConfigPath="${syncRoot}/xray/"
    export PADM_SUBSCRIPTION_GROUPS_DIR="${syncRoot}/groups"
    export PADM_SUBSCRIBE_LOCAL_DIR="${syncRoot}/subscribe_local"
    export PADM_SUBSCRIBE_DIR="${syncRoot}/subscribe"
    TMPDIR="${syncRoot}/tmp"
    : >"${callLog}"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"},{"id":"edge-b","name":"Edge B","role":"secondary","scheme":"wireguard","transport":"wireguard","host":"10.77.0.2","port":39778,"enabled":true,"sync_status":"pending","control_token":"token-b"}],"user_groups":[{"id":"real-sync-6","name":"Real Sync 6","enabled":true,"allowed_sources":["edge-b"],"traffic_limit_gb":0,"uuid":"3004d897-c06d-45a1-aa64-3d3266ca63d5"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    cat >"${syncConfigFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[]}}]}
JSON

    subscriptionGroupQuotaAutoApplyEnabled() { return 1; }
    subscriptionGroupRemoteSyncEnabled() { return 0; }
    collectSubscriptionTraffic() { return 0; }
    readInstallType() { return 0; }
    readInstallProtocolType() { return 0; }
    readConfigHostPathUUID() { return 0; }
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
    ensureSubscriptionControlNginxLocation() {
        printf 'ensure-nginx-location\n' >>"${callLog}"
        return 1
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
    subscriptionSyncApplyAccountPlanTransaction() {
        printf 'apply-account-plan\n' >>"${callLog}"
        return 0
    }
    runSubscriptionRemoteSync() {
        printf 'remote-sync\n' >>"${callLog}"
        printf '[]'
    }
    subscribe() {
        printf 'refresh-publish:%s\n' "$*" >>"${callLog}"
        return 0
    }
    subscriptionSyncMarkResult() {
        printf '%s\n' "$1" >"${resultStatus}"
        printf '%s\n' "$2" >"${resultFailures}"
        return 0
    }
    successCard() { printf '%s\n' "$*" >"${statusLog}"; }
    statusCard() { printf '%s\n' "$*" >"${statusLog}"; }

    set +e
    runSubscriptionGroupSync
    syncStatus=$?
    set -e
    [[ "${syncStatus}" == "0" ]]
    grep -q '^apply-account-plan$' "${callLog}"
    grep -q '^remote-sync$' "${callLog}"
    grep -q '^refresh-publish:false false$' "${callLog}"
    python - <<'PY' "${callLog}"
import sys
lines = [line.strip() for line in open(sys.argv[1], encoding='utf-8') if line.strip()]
assert lines.index('remote-sync') < lines.index('refresh-publish:false false')
PY
    [[ "$(<"${resultFailures}")" == "[]" ]]
    grep -qx 'success' "${resultStatus}"
    grep -q '自动同步完成' "${statusLog}"
    if regressionFindHasMatches "${syncRoot}/tmp" -maxdepth 1 -type d \( -name 'padm-subscription-sync-backup.*' -o -name 'padm-subscription-output-backup.*' \); then
        return 1
    fi
)

runSubscriptionGroupSyncRollbackRegression() {
    runSubscriptionGroupSyncRollbackSerialRegression
}

runSubscriptionGroupSyncRollbackSerialRegression() {
    runRegressionStep subscription-group-sync-apply-failure runSubscriptionGroupSyncApplyFailureRegression &&
        runRegressionStep subscription-group-sync-reconcile-rollback runSubscriptionGroupSyncReconcileRollbackRegression &&
        runRegressionStep subscription-group-sync-remote-failure runSubscriptionGroupSyncRemoteFailureRegression &&
        runRegressionStep subscription-group-sync-remote-before-publish-refresh runSubscriptionGroupSyncRemoteBeforePublishRefreshRegression
}

runSubscriptionSyncRollbackFailureRegression() {
    runParallelSubscriptionStateModes \
        "${TMP_DIR}/subscription-sync-rollback-failure" \
        config-restore-fail subscription-sync-rollback-config-restore-failure \
        restore-dir-fail subscription-sync-restore-dir-failure \
        reload-rollback subscription-sync-reload-rollback \
        group-sync subscription-group-sync-rollback
}

runSubscriptionSyncRollbackFailureSerialRegression() {
    runRegressionStep subscription-sync-rollback-config-restore-failure runSubscriptionSyncRollbackConfigRestoreFailureRegression &&
        runRegressionStep subscription-sync-restore-dir-failure runSubscriptionSyncRollbackRestoreDirFailureRegression &&
        runRegressionStep subscription-sync-reload-rollback runSubscriptionSyncRollbackReloadRollbackRegression &&
        runRegressionStep subscription-group-sync-rollback-serial runSubscriptionGroupSyncRollbackSerialRegression
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
        ensureSubscriptionControlNginxLocation() {
            printf 'ensure\n' >>"${callLog}"
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
        set +e
        subscriptionSyncReconcileLocalServices
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -qx 'reload' "${callLog}"
        [[ "$(wc -l <"${callLog}" | tr -d ' ')" == "1" ]]
    )

    (
        : >"${callLog}"
        subscribePort=
        reloadCore() {
            printf 'reload\n' >>"${callLog}"
            return 0
        }
        readNginxSubscribe() {
            printf 'read\n' >>"${callLog}"
            subscribePort=39778
        }
        installSubscriptionControlService() {
            printf 'install\n' >>"${callLog}"
            return 1
        }
        ensureSubscriptionControlNginxLocation() {
            printf 'ensure\n' >>"${callLog}"
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
        set +e
        subscriptionSyncReconcileLocalServices
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -qx 'reload' "${callLog}"
        grep -qx 'read' "${callLog}"
        grep -qx 'install' "${callLog}"
        [[ "$(wc -l <"${callLog}" | tr -d ' ')" == "3" ]]
    )

    (
        : >"${callLog}"
        subscribePort=
        reloadCore() {
            printf 'reload\n' >>"${callLog}"
            return 0
        }
        readNginxSubscribe() {
            printf 'read\n' >>"${callLog}"
            subscribePort=39778
        }
        installSubscriptionControlService() {
            printf 'install\n' >>"${callLog}"
            return 0
        }
        ensureSubscriptionControlNginxLocation() {
            printf 'ensure\n' >>"${callLog}"
            return 0
        }
        serviceQueueRestart() {
            printf 'restart:%s\n' "$1" >>"${callLog}"
            return 0
        }
        serviceQueueApply() {
            printf 'apply\n' >>"${callLog}"
            return 1
        }
        subscribe() {
            printf 'subscribe:%s\n' "$*" >>"${callLog}"
            return 0
        }
        set +e
        subscriptionSyncReconcileLocalServices
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -qx 'reload' "${callLog}"
        grep -qx 'read' "${callLog}"
        grep -qx 'install' "${callLog}"
        grep -qx 'ensure' "${callLog}"
        grep -qx 'restart:nginx' "${callLog}"
        grep -qx 'apply' "${callLog}"
        [[ "$(wc -l <"${callLog}" | tr -d ' ')" == "6" ]]
    )
)

runSubscriptionGroupsRestoreFailureRegression() (
    local root="${TMP_DIR}/subscription-groups-restore-failure"
    local groupsDir="${root}/groups"
    local currentBackup="${root}/current-backup.json"
    local targetBackup="${root}/target-backup.json"
    local stateFile="${groupsDir}/groups.json"
    local oldGroupsDir="${PADM_SUBSCRIPTION_GROUPS_DIR:-}"
    local oldTmpDir="${TMPDIR:-}"
    local beforeSnapshot
    local rc

    export PADM_SUBSCRIPTION_GROUPS_DIR="${groupsDir}"
    TMPDIR="${root}"
    mkdir -p "${groupsDir}"
    cat >"${stateFile}" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"默认订阅组","admin":{"id":"admin","name":"我的订阅","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"本机","role":"main","transport":"local","scheme":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    beforeSnapshot=$(<"${stateFile}")
    cp "${stateFile}" "${currentBackup}"
    cat >"${targetBackup}" <<'JSON'
{"version":1,"active_group":"legacy","groups":[{"id":"legacy","name":"Legacy","sources":[],"user_groups":[],"sync":{"enabled":true},"traffic":{}}]}
JSON

    createSubscriptionGroupsBackup() {
        printf '%s\n' "${currentBackup}"
    }
    migrateSubscriptionGroupsState() {
        return 1
    }

    set +e
    restoreSubscriptionGroupsBackup "${targetBackup}" >/dev/null 2>&1
    rc=$?
    set -e
    unset -f createSubscriptionGroupsBackup
    unset -f migrateSubscriptionGroupsState
    [[ "${rc}" == "1" ]]
    [[ "$(<"${stateFile}")" == "${beforeSnapshot}" ]]
    [[ ! -e "${currentBackup}" ]]

    if [[ -n "${oldGroupsDir}" ]]; then export PADM_SUBSCRIPTION_GROUPS_DIR="${oldGroupsDir}"; else unset PADM_SUBSCRIPTION_GROUPS_DIR; fi
    if [[ -n "${oldTmpDir}" ]]; then TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runParallelSubscriptionStateModes() {
    local orchestrationRoot=$1
    shift
    local -a labels=()
    local -a modes=()
    local -a logs=()
    local -a pids=()
    local -a statuses=()
    local i

    mkdir -p "${orchestrationRoot}"
    while [[ $# -gt 0 ]]; do
        labels+=("$1")
        modes+=("$2")
        logs+=("${orchestrationRoot}/$1.log")
        shift 2
    done

    set +e
    for i in "${!modes[@]}"; do
        PADM_REGRESSION_SUPPRESS_DONE=1 bash "${SUBSCRIPTION_STATE_SCRIPT_PATH}" "${modes[$i]}" >"${logs[$i]}" 2>&1 &
        pids[$i]=$!
    done
    for i in "${!pids[@]}"; do
        wait "${pids[$i]}"
        statuses[$i]=$?
    done
    set -e

    for i in "${!logs[@]}"; do
        cat "${logs[$i]}"
    done
    for i in "${!statuses[@]}"; do
        [[ "${statuses[$i]}" -eq 0 ]]
    done
}

runRegressionSubscriptionStateStructure() {
    runRegressionStep subscription-state-structure runSubscriptionGroupStateStructureRegression
}

runRegressionSubscriptionStateStructureFoundation() {
    runRegressionStep subscription-state-structure-foundation runSubscriptionGroupStateStructureFoundationRegression
}

runRegressionSubscriptionStateStructureFoundationAddRemove() {
    runRegressionStep subscription-state-structure-foundation-add-remove runSubscriptionGroupStateStructureFoundationAddRemoveRegression
}

runRegressionSubscriptionStateStructureFoundationCredential() {
    runRegressionStep subscription-state-structure-foundation-credential runSubscriptionGroupStateStructureFoundationCredentialRegression
}

runRegressionSubscriptionStateStructureFoundationNormalize() {
    runRegressionStep subscription-state-structure-foundation-normalize runSubscriptionGroupStateStructureFoundationNormalizeRegression
}

runRegressionSubscriptionStateStructureFoundationInitTransaction() {
    runRegressionStep subscription-state-structure-foundation-init-transaction runSubscriptionGroupStateStructureFoundationInitTransactionRegression
}

runRegressionSubscriptionStateStructureFoundationSerial() {
    runRegressionStep subscription-state-structure-foundation-serial runSubscriptionGroupStateStructureFoundationSerialRegression
}

runRegressionSubscriptionStateStructureMigration() {
    runRegressionStep subscription-state-structure-migration runSubscriptionGroupStateStructureMigrationRegression
}

runRegressionSubscriptionStateStructureSource() {
    runRegressionStep subscription-state-structure-source runSubscriptionGroupStateStructureSourceRegression
}

runRegressionSubscriptionStateStructureSourceCredential() {
    runRegressionStep subscription-state-structure-source-credential runSubscriptionGroupStateStructureSourceCredentialRegression
}

runRegressionSubscriptionStateStructureSourceStatus() {
    runRegressionStep subscription-state-structure-source-status runSubscriptionGroupStateStructureSourceStatusRegression
}

runRegressionSubscriptionStateStructureSourceRemove() {
    runRegressionStep subscription-state-structure-source-remove runSubscriptionGroupStateStructureSourceRemoveRegression
}

runRegressionSubscriptionStateStructureSourceSerial() {
    runRegressionStep subscription-state-structure-source-serial runSubscriptionGroupStateStructureSourceSerialRegression
}

runRegressionSubscriptionStateStructureSerial() {
    runRegressionStep subscription-state-structure-serial runSubscriptionGroupStateStructureSerialRegression
}

runRegressionSubscriptionStateQuota() {
    runRegressionStep subscription-state-quota runSubscriptionGroupStateQuotaRegression
}

runRegressionSubscriptionStateQuotaTraffic() {
    runRegressionStep subscription-state-quota-traffic runSubscriptionGroupStateQuotaTrafficRegression
}

runRegressionSubscriptionStateQuotaTrafficSummary() {
    runRegressionStep subscription-state-quota-traffic-summary runSubscriptionGroupStateQuotaTrafficSummaryRegression
}

runRegressionSubscriptionStateQuotaTrafficInvalidInput() {
    runRegressionStep subscription-state-quota-traffic-invalid-input runSubscriptionGroupStateQuotaTrafficInvalidInputRegression
}

runRegressionSubscriptionStateQuotaTrafficApply() {
    runRegressionStep subscription-state-quota-traffic-apply runSubscriptionGroupStateQuotaTrafficApplyRegression
}

runRegressionSubscriptionStateQuotaTrafficSerial() {
    runRegressionStep subscription-state-quota-traffic-serial runSubscriptionGroupStateQuotaTrafficSerialRegression
}

runRegressionSubscriptionStateQuotaMenuPreviewFailure() {
    runRegressionStep subscription-state-quota-menu-preview-fail runSubscriptionGroupStateQuotaMenuPreviewFailureRegression
}

runRegressionSubscriptionStateQuotaTransactionRollback() {
    runRegressionStep subscription-state-quota-menu-tx-rollback runSubscriptionGroupStateQuotaTransactionRollbackRegression
}

runRegressionSubscriptionStateQuotaMenuTransaction() {
    runRegressionStep subscription-state-quota-menu-tx runSubscriptionGroupStateQuotaMenuTransactionRegression
}

runRegressionSubscriptionStateQuotaMenuTransactionSerial() {
    runRegressionStep subscription-state-quota-menu-tx-serial runSubscriptionGroupStateQuotaMenuTransactionSerialRegression
}

runRegressionSubscriptionStateQuotaPartialSyncApplyFailure() {
    runRegressionStep subscription-state-quota-partial-sync-apply-failure runSubscriptionGroupStateQuotaPartialSyncApplyFailureRegression
}

runRegressionSubscriptionStateQuotaPartialSyncPlan() {
    runRegressionStep subscription-state-quota-partial-sync-plan runSubscriptionGroupStateQuotaPartialSyncPlanRegression
}

runRegressionSubscriptionStateQuotaPartialSyncConfig() {
    runRegressionStep subscription-state-quota-partial-sync-config runSubscriptionGroupStateQuotaPartialSyncConfigRegression
}

runRegressionSubscriptionStateQuotaPartialSync() {
    runRegressionStep subscription-state-quota-partial-sync runSubscriptionGroupStateQuotaPartialSyncRegression
}

runRegressionSubscriptionStateQuotaPartialSyncSerial() {
    runRegressionStep subscription-state-quota-partial-sync-serial runSubscriptionGroupStateQuotaPartialSyncSerialRegression
}

runRegressionSubscriptionStateQuotaSerial() {
    runRegressionStep subscription-state-quota-serial runSubscriptionGroupStateQuotaSerialRegression
}

runRegressionSubscriptionStateRemoteRestore() {
    runRegressionStep subscription-state-remote-restore runSubscriptionGroupStateRemoteRestoreRegression
}

runRegressionSubscriptionStateRemoteRestoreSelfReference() {
    runRegressionStep subscription-state-remote-restore-self-reference runSubscriptionGroupStateRemoteRestoreSelfReferenceRegression
}

runRegressionSubscriptionStateRemoteRestoreSelfReferencePlan() {
    runRegressionStep subscription-state-remote-restore-self-reference-plan runSubscriptionGroupStateRemoteRestoreSelfReferencePlanRegression
}

runRegressionSubscriptionStateRemoteRestoreSelfReferenceSync() {
    runRegressionStep subscription-state-remote-restore-self-reference-sync runSubscriptionGroupStateRemoteRestoreSelfReferenceSyncRegression
}

runRegressionSubscriptionStateRemoteRestoreSelfReferenceSerial() {
    runRegressionStep subscription-state-remote-restore-self-reference-serial runSubscriptionGroupStateRemoteRestoreSelfReferenceSerialRegression
}

runRegressionSubscriptionStateRemoteRestoreStateWrite() {
    runRegressionStep subscription-state-remote-restore-state-write runSubscriptionGroupStateRemoteRestoreStateWriteRegression
}

runRegressionSubscriptionStateRemoteRestoreLegacyMenu() {
    runRegressionStep subscription-state-remote-restore-legacy-menu runSubscriptionGroupStateRemoteRestoreLegacyMenuRegression
}

runRegressionSubscriptionStateRemoteRestoreSerial() {
    runRegressionStep subscription-state-remote-restore-serial runSubscriptionGroupStateRemoteRestoreSerialRegression
}

runRegressionSubscriptionStateCore() {
    runParallelSubscriptionStateModes \
        "${TMP_DIR}/subscription-state-core" \
        structure subscription-state-structure \
        quota subscription-state-quota \
        remote-restore subscription-state-remote-restore
}

runRegressionSubscriptionStateSupport() {
    runRegressionStep subscription-sync-tempdir runSubscriptionSyncTempDirRegression &&
        runRegressionStep subscription-sync-restore-pair-failure-message runSubscriptionSyncRestorePairFailureMessageRegression &&
        runRegressionStep subscription-sync-append-restore-failure-detail runSubscriptionSyncAppendRestoreFailureDetailRegression &&
        runRegressionStep subscription-sync-single-restore-result-message runSubscriptionSyncSingleRestoreResultMessageRegression &&
        runRegressionStep subscription-sync-rollback-result-message runSubscriptionSyncRollbackResultMessageRegression &&
        runRegressionStep subscription-sync-reconcile-early-exit runSubscriptionSyncReconcileEarlyExitRegression &&
        runRegressionStep subscription-groups-restore-failure runSubscriptionGroupsRestoreFailureRegression
}

runRegressionSubscriptionSyncTempDir() {
    runRegressionStep subscription-sync-tempdir runSubscriptionSyncTempDirRegression
}

runRegressionSubscriptionSyncRestorePairFailureMessage() {
    runRegressionStep subscription-sync-restore-pair-failure-message runSubscriptionSyncRestorePairFailureMessageRegression
}

runRegressionSubscriptionSyncAppendRestoreFailureDetail() {
    runRegressionStep subscription-sync-append-restore-failure-detail runSubscriptionSyncAppendRestoreFailureDetailRegression
}

runRegressionSubscriptionSyncSingleRestoreResultMessage() {
    runRegressionStep subscription-sync-single-restore-result-message runSubscriptionSyncSingleRestoreResultMessageRegression
}

runRegressionSubscriptionSyncRollbackResultMessage() {
    runRegressionStep subscription-sync-rollback-result-message runSubscriptionSyncRollbackResultMessageRegression
}

runRegressionSubscriptionStateSyncRollback() {
    runRegressionStep subscription-sync-rollback-failure runSubscriptionSyncRollbackFailureRegression
}

runRegressionSubscriptionStateSyncRollbackSerial() {
    runRegressionStep subscription-sync-rollback-failure-serial runSubscriptionSyncRollbackFailureSerialRegression
}

runRegressionSubscriptionSyncRollbackConfigRestoreFailure() {
    runRegressionStep subscription-sync-rollback-config-restore-failure runSubscriptionSyncRollbackConfigRestoreFailureRegression
}

runRegressionSubscriptionSyncRollbackRestoreDirFailure() {
    runRegressionStep subscription-sync-restore-dir-failure runSubscriptionSyncRollbackRestoreDirFailureRegression
}

runRegressionSubscriptionSyncRollbackReloadRollback() {
    runRegressionStep subscription-sync-reload-rollback runSubscriptionSyncRollbackReloadRollbackRegression
}

runRegressionSubscriptionGroupSyncRollback() {
    runRegressionStep subscription-group-sync-rollback runSubscriptionGroupSyncRollbackRegression
}

runRegressionSubscriptionGroupSyncRollbackSerial() {
    runRegressionStep subscription-group-sync-rollback-serial runSubscriptionGroupSyncRollbackSerialRegression
}

runRegressionSubscriptionGroupSyncApplyFailure() {
    runRegressionStep subscription-group-sync-apply-failure runSubscriptionGroupSyncApplyFailureRegression
}

runRegressionSubscriptionGroupSyncReconcileRollback() {
    runRegressionStep subscription-group-sync-reconcile-rollback runSubscriptionGroupSyncReconcileRollbackRegression
}

runRegressionSubscriptionGroupSyncRemoteFailure() {
    runRegressionStep subscription-group-sync-remote-failure runSubscriptionGroupSyncRemoteFailureRegression
}

runRegressionSubscriptionSyncReconcileEarlyExit() {
    runRegressionStep subscription-sync-reconcile-early-exit runSubscriptionSyncReconcileEarlyExitRegression
}

runRegressionSubscriptionGroupsRestoreFailure() {
    runRegressionStep subscription-groups-restore-failure runSubscriptionGroupsRestoreFailureRegression
}

runRegressionSubscriptionStateSerial() {
    runRegressionStep subscription-state runSubscriptionGroupStateRegression &&
        runRegressionStep subscription-sync-tempdir runSubscriptionSyncTempDirRegression &&
        runRegressionStep subscription-sync-restore-pair-failure-message runSubscriptionSyncRestorePairFailureMessageRegression &&
        runRegressionStep subscription-sync-append-restore-failure-detail runSubscriptionSyncAppendRestoreFailureDetailRegression &&
        runRegressionStep subscription-sync-single-restore-result-message runSubscriptionSyncSingleRestoreResultMessageRegression &&
        runRegressionStep subscription-sync-rollback-result-message runSubscriptionSyncRollbackResultMessageRegression &&
        runRegressionStep subscription-sync-rollback-failure-serial runSubscriptionSyncRollbackFailureSerialRegression &&
        runRegressionStep subscription-sync-reconcile-early-exit runSubscriptionSyncReconcileEarlyExitRegression &&
        runRegressionStep subscription-groups-restore-failure runSubscriptionGroupsRestoreFailureRegression
}

runRegressionSubscriptionState() {
    runParallelSubscriptionStateModes \
        "${TMP_DIR}/subscription-state-default" \
        core subscription-state-core \
        support subscription-state-support \
        sync-rollback subscription-state-sync-rollback
}

regressionName=${1:-subscription-state}
case "${regressionName}" in
subscription-state)
    regressionRunner=runRegressionSubscriptionState
    ;;
subscription-state-serial)
    regressionRunner=runRegressionSubscriptionStateSerial
    ;;
subscription-state-core)
    regressionRunner=runRegressionSubscriptionStateCore
    ;;
subscription-state-structure)
    regressionRunner=runRegressionSubscriptionStateStructure
    ;;
subscription-state-structure-foundation)
    regressionRunner=runRegressionSubscriptionStateStructureFoundation
    ;;
subscription-state-structure-foundation-add-remove)
    regressionRunner=runRegressionSubscriptionStateStructureFoundationAddRemove
    ;;
subscription-state-structure-foundation-credential)
    regressionRunner=runRegressionSubscriptionStateStructureFoundationCredential
    ;;
subscription-state-structure-foundation-normalize)
    regressionRunner=runRegressionSubscriptionStateStructureFoundationNormalize
    ;;
subscription-state-structure-foundation-init-transaction)
    regressionRunner=runRegressionSubscriptionStateStructureFoundationInitTransaction
    ;;
subscription-state-structure-foundation-serial)
    regressionRunner=runRegressionSubscriptionStateStructureFoundationSerial
    ;;
subscription-state-structure-migration)
    regressionRunner=runRegressionSubscriptionStateStructureMigration
    ;;
subscription-state-structure-source)
    regressionRunner=runRegressionSubscriptionStateStructureSource
    ;;
subscription-state-structure-source-credential)
    regressionRunner=runRegressionSubscriptionStateStructureSourceCredential
    ;;
subscription-state-structure-source-status)
    regressionRunner=runRegressionSubscriptionStateStructureSourceStatus
    ;;
subscription-state-structure-source-remove)
    regressionRunner=runRegressionSubscriptionStateStructureSourceRemove
    ;;
subscription-state-structure-source-serial)
    regressionRunner=runRegressionSubscriptionStateStructureSourceSerial
    ;;
subscription-state-structure-serial)
    regressionRunner=runRegressionSubscriptionStateStructureSerial
    ;;
subscription-state-quota)
    regressionRunner=runRegressionSubscriptionStateQuota
    ;;
subscription-state-quota-traffic)
    regressionRunner=runRegressionSubscriptionStateQuotaTraffic
    ;;
subscription-state-quota-traffic-summary)
    regressionRunner=runRegressionSubscriptionStateQuotaTrafficSummary
    ;;
subscription-state-quota-traffic-invalid-input)
    regressionRunner=runRegressionSubscriptionStateQuotaTrafficInvalidInput
    ;;
subscription-state-quota-traffic-apply)
    regressionRunner=runRegressionSubscriptionStateQuotaTrafficApply
    ;;
subscription-state-quota-traffic-serial)
    regressionRunner=runRegressionSubscriptionStateQuotaTrafficSerial
    ;;
subscription-state-quota-menu-tx)
    regressionRunner=runRegressionSubscriptionStateQuotaMenuTransaction
    ;;
subscription-state-quota-menu-preview-fail)
    regressionRunner=runRegressionSubscriptionStateQuotaMenuPreviewFailure
    ;;
subscription-state-quota-menu-tx-rollback)
    regressionRunner=runRegressionSubscriptionStateQuotaTransactionRollback
    ;;
subscription-state-quota-menu-tx-serial)
    regressionRunner=runRegressionSubscriptionStateQuotaMenuTransactionSerial
    ;;
subscription-state-quota-partial-sync-apply-failure)
    regressionRunner=runRegressionSubscriptionStateQuotaPartialSyncApplyFailure
    ;;
subscription-state-quota-partial-sync-plan)
    regressionRunner=runRegressionSubscriptionStateQuotaPartialSyncPlan
    ;;
subscription-state-quota-partial-sync-config)
    regressionRunner=runRegressionSubscriptionStateQuotaPartialSyncConfig
    ;;
subscription-state-quota-partial-sync)
    regressionRunner=runRegressionSubscriptionStateQuotaPartialSync
    ;;
subscription-state-quota-partial-sync-serial)
    regressionRunner=runRegressionSubscriptionStateQuotaPartialSyncSerial
    ;;
subscription-state-quota-serial)
    regressionRunner=runRegressionSubscriptionStateQuotaSerial
    ;;
subscription-state-remote-restore)
    regressionRunner=runRegressionSubscriptionStateRemoteRestore
    ;;
subscription-state-remote-restore-self-reference)
    regressionRunner=runRegressionSubscriptionStateRemoteRestoreSelfReference
    ;;
subscription-state-remote-restore-self-reference-plan)
    regressionRunner=runRegressionSubscriptionStateRemoteRestoreSelfReferencePlan
    ;;
subscription-state-remote-restore-self-reference-sync)
    regressionRunner=runRegressionSubscriptionStateRemoteRestoreSelfReferenceSync
    ;;
subscription-state-remote-restore-self-reference-serial)
    regressionRunner=runRegressionSubscriptionStateRemoteRestoreSelfReferenceSerial
    ;;
subscription-state-remote-restore-state-write)
    regressionRunner=runRegressionSubscriptionStateRemoteRestoreStateWrite
    ;;
subscription-state-remote-restore-legacy-menu)
    regressionRunner=runRegressionSubscriptionStateRemoteRestoreLegacyMenu
    ;;
subscription-state-remote-restore-serial)
    regressionRunner=runRegressionSubscriptionStateRemoteRestoreSerial
    ;;
subscription-state-support)
    regressionRunner=runRegressionSubscriptionStateSupport
    ;;
subscription-state-sync-rollback)
    regressionRunner=runRegressionSubscriptionStateSyncRollback
    ;;
subscription-state-sync-rollback-serial)
    regressionRunner=runRegressionSubscriptionStateSyncRollbackSerial
    ;;
subscription-sync-tempdir)
    regressionRunner=runRegressionSubscriptionSyncTempDir
    ;;
subscription-sync-restore-pair-failure-message)
    regressionRunner=runRegressionSubscriptionSyncRestorePairFailureMessage
    ;;
subscription-sync-append-restore-failure-detail)
    regressionRunner=runRegressionSubscriptionSyncAppendRestoreFailureDetail
    ;;
subscription-sync-single-restore-result-message)
    regressionRunner=runRegressionSubscriptionSyncSingleRestoreResultMessage
    ;;
subscription-sync-rollback-result-message)
    regressionRunner=runRegressionSubscriptionSyncRollbackResultMessage
    ;;
subscription-sync-rollback-failure)
    regressionRunner=runRegressionSubscriptionStateSyncRollback
    ;;
subscription-sync-rollback-failure-serial)
    regressionRunner=runRegressionSubscriptionStateSyncRollbackSerial
    ;;
subscription-sync-rollback-config-restore-failure)
    regressionRunner=runRegressionSubscriptionSyncRollbackConfigRestoreFailure
    ;;
subscription-sync-restore-dir-failure)
    regressionRunner=runRegressionSubscriptionSyncRollbackRestoreDirFailure
    ;;
subscription-sync-reload-rollback)
    regressionRunner=runRegressionSubscriptionSyncRollbackReloadRollback
    ;;
subscription-group-sync-rollback)
    regressionRunner=runRegressionSubscriptionGroupSyncRollback
    ;;
subscription-group-sync-rollback-serial)
    regressionRunner=runRegressionSubscriptionGroupSyncRollbackSerial
    ;;
subscription-group-sync-apply-failure)
    regressionRunner=runRegressionSubscriptionGroupSyncApplyFailure
    ;;
subscription-group-sync-reconcile-rollback)
    regressionRunner=runRegressionSubscriptionGroupSyncReconcileRollback
    ;;
subscription-group-sync-remote-failure)
    regressionRunner=runRegressionSubscriptionGroupSyncRemoteFailure
    ;;
subscription-sync-reconcile-early-exit)
    regressionRunner=runRegressionSubscriptionSyncReconcileEarlyExit
    ;;
subscription-groups-restore-failure)
    regressionRunner=runRegressionSubscriptionGroupsRestoreFailure
    ;;
*)
    printf 'usage: %s [subscription-state|subscription-state-serial|subscription-state-core|subscription-state-structure|subscription-state-structure-foundation|subscription-state-structure-foundation-add-remove|subscription-state-structure-foundation-credential|subscription-state-structure-foundation-normalize|subscription-state-structure-foundation-serial|subscription-state-structure-source|subscription-state-structure-source-credential|subscription-state-structure-source-status|subscription-state-structure-source-remove|subscription-state-structure-source-serial|subscription-state-quota|subscription-state-quota-traffic|subscription-state-quota-traffic-summary|subscription-state-quota-traffic-invalid-input|subscription-state-quota-traffic-apply|subscription-state-quota-traffic-serial|subscription-state-quota-menu-tx|subscription-state-quota-menu-preview-fail|subscription-state-quota-menu-tx-rollback|subscription-state-quota-menu-tx-serial|subscription-state-quota-partial-sync|subscription-state-quota-partial-sync-apply-failure|subscription-state-quota-partial-sync-plan|subscription-state-quota-partial-sync-config|subscription-state-quota-partial-sync-serial|subscription-state-remote-restore|subscription-state-remote-restore-self-reference|subscription-state-remote-restore-self-reference-plan|subscription-state-remote-restore-self-reference-sync|subscription-state-remote-restore-self-reference-serial|subscription-state-remote-restore-state-write|subscription-state-remote-restore-legacy-menu|subscription-state-remote-restore-serial|subscription-state-support|subscription-state-sync-rollback|subscription-state-sync-rollback-serial|subscription-sync-tempdir|subscription-sync-restore-pair-failure-message|subscription-sync-append-restore-failure-detail|subscription-sync-single-restore-result-message|subscription-sync-rollback-result-message|subscription-sync-rollback-failure|subscription-sync-rollback-failure-serial|subscription-sync-rollback-config-restore-failure|subscription-sync-restore-dir-failure|subscription-sync-reload-rollback|subscription-group-sync-rollback|subscription-group-sync-rollback-serial|subscription-group-sync-apply-failure|subscription-group-sync-reconcile-rollback|subscription-group-sync-remote-failure|subscription-sync-reconcile-early-exit|subscription-groups-restore-failure]\n' "$0" >&2
    exit 2
    ;;
esac

runRegressionStep "total:${regressionName}" "${regressionRunner}"
if [[ "${PADM_REGRESSION_SUPPRESS_DONE:-}" != "1" ]]; then
    echo "subscription-groups-regression-ok:${regressionName}"
fi
