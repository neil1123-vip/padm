#!/usr/bin/env bash

subscriptionGroupsDir() {
    echo "${PADM_SUBSCRIPTION_GROUPS_DIR:-/etc/padm/subscribe_groups}"
}

subscriptionGroupsSafeDir() {
    local groupsDir
    groupsDir=$(subscriptionGroupsDir)
    [[ -n "${groupsDir}" ]] || return 1
    [[ "${groupsDir}" == /* ]] || return 1
    padmIsSafeAbsolutePath "${groupsDir%/}" || return 1
    printf '%s\n' "${groupsDir%/}"
}

subscriptionGroupsFile() {
    local groupsDir
    groupsDir=$(subscriptionGroupsSafeDir) || return 1
    printf '%s/groups.json\n' "${groupsDir}"
}

subscriptionGroupsBackupDir() {
    local groupsDir
    groupsDir=$(subscriptionGroupsSafeDir) || return 1
    printf '%s/backups\n' "${groupsDir}"
}

subscriptionGroupsSchemaVersion() {
    echo 2
}

writeDefaultSubscriptionGroupsState() {
    cat <<EOF >"$1"
{
  "version": $(subscriptionGroupsSchemaVersion),
  "active_group": "default",
  "groups": [
    {
      "id": "default",
      "name": "默认订阅组",
      "admin": {
        "id": "admin",
        "name": "我的订阅",
        "enabled": true,
        "allowed_sources": ["*"],
        "traffic_limit_gb": 0,
        "token": ""
      },
      "sources": [
        {
          "id": "main",
          "name": "本机",
          "role": "main",
          "scheme": "local",
          "host": "127.0.0.1",
          "port": 0,
          "enabled": true,
          "sync_status": "local"
        }
      ],
      "user_groups": [],
      "sync": {
        "enabled": true,
        "interval_minutes": 10,
        "last_run": "",
        "last_status": "pending",
        "failures": [],
        "remote_enabled": true,
        "event_enabled": true,
        "quota_auto_apply": false
      },
      "traffic": {
        "global": {"upload": 0, "download": 0},
        "admin": {"upload": 0, "download": 0, "sources": {}},
        "user_groups": {},
        "sources": {}
      }
    }
  ]
}
EOF
}

backupSubscriptionGroupsStateForMigration() {
    local backupDir
    local backupFile
    local stateFile
    backupDir=$(subscriptionGroupsBackupDir)
    stateFile=$(subscriptionGroupsFile)
    [[ -f "${stateFile}" ]] || return 0
    padmEnsureSafeDirectory "${backupDir}" || return 1
    backupFile="${backupDir}/groups-pre-migrate-$(date '+%Y%m%d%H%M%S').json"
    if ! cp "${stateFile}" "${backupFile}"; then
        removeManagedFilesIfPresentIgnoreFailure "${backupFile}"
        return 1
    fi
    printf '%s\n' "${backupFile}"
}

normalizeSubscriptionGroupsState() {
    local schemaVersion
    schemaVersion=$(subscriptionGroupsSchemaVersion)
    jq --argjson schemaVersion "${schemaVersion}" '
      def source_default:
        {
          id: "main",
          name: "本机",
          role: "main",
          scheme: "local",
          transport: "local",
          host: "127.0.0.1",
          port: 0,
          enabled: true,
          sync_status: "local"
        };
      def normalize_source:
        . as $source |
        source_default + ($source // {}) |
        .id = (($source.id // "") | tostring) |
        .name = (($source.name // $source.id // "") | tostring) |
        .role = (if ($source.role // "") == "main" then "main" else "secondary" end) |
        .transport = (if .role == "main" then "local" else "wireguard" end) |
        .scheme = (if .role == "main" then "local" else "wireguard" end) |
        .host = (($source.host // "") | tostring) |
        .port = (($source.port // 0) | tonumber? // 0) |
        .enabled = (if $source.enabled == false then false else true end) |
        .sync_status = (($source.sync_status // (if (($source.role // "") == "main") then "local" else "pending" end)) | tostring);
      def normalize_user_group:
        . as $user |
        {
          id: (($user.id // "") | tostring),
          name: (($user.name // $user.id // "") | tostring),
          enabled: (if $user.enabled == false then false else true end),
          allowed_sources: (if ($user.allowed_sources? | type) == "array" then $user.allowed_sources else ["main"] end),
          traffic_limit_gb: (($user.traffic_limit_gb // 0) | tonumber? // 0),
          token: (($user.token // "") | tostring)
        } + (if (($user.uuid // "") | tostring) != "" then {uuid: ($user.uuid | tostring)} else {} end);
      def normalize_traffic:
        . as $traffic |
        {
          global: (($traffic.global // {}) + {upload: (($traffic.global.upload // 0) | tonumber? // 0), download: (($traffic.global.download // 0) | tonumber? // 0)}),
          admin: (($traffic.admin // {}) + {upload: (($traffic.admin.upload // 0) | tonumber? // 0), download: (($traffic.admin.download // 0) | tonumber? // 0), sources: (($traffic.admin.sources // {}) | objects // {})}),
          user_groups: (($traffic.user_groups // {}) | objects // {}),
          sources: (($traffic.sources // {}) | objects // {})
        };
      def normalize_group:
        . as $group |
        {
          id: (($group.id // "default") | tostring),
          name: (($group.name // "默认订阅组") | tostring),
          admin: ({id:"admin", name:"我的订阅", enabled:true, allowed_sources:["*"], traffic_limit_gb:0, token:""} + ($group.admin // {})),
          sources: ([($group.sources // [])[]? | normalize_source | select(.id != "")] as $sources |
            if any($sources[]?; .role == "main") then $sources else [source_default] + $sources end),
          user_groups: [($group.user_groups // [])[]? | normalize_user_group | select(.id != "")],
          sync: ({enabled:true, interval_minutes:10, last_run:"", last_status:"pending", failures:[], remote_enabled:true, event_enabled:true, quota_auto_apply:false} + ($group.sync // {})),
          traffic: (($group.traffic // {}) | normalize_traffic)
        };
      . as $state |
      {
        version: $schemaVersion,
        active_group: (($state.active_group // "default") | tostring),
        groups: (if (($state.groups // []) | length) > 0 then [$state.groups[]? | normalize_group] else [({} | normalize_group)] end)
      } |
      . as $normalized |
      if any($normalized.groups[]?; .id == $normalized.active_group) then $normalized else ($normalized | .active_group = (.groups[0].id // "default")) end
    '
}

migrateSubscriptionGroupsState() {
    local stateFile
    local tmpFile
    local currentVersion
    local schemaVersion
    local backupFile
    stateFile=$(subscriptionGroupsFile)
    schemaVersion=$(subscriptionGroupsSchemaVersion)
    currentVersion=$(jq -r '.version // 0' "${stateFile}" 2>/dev/null || echo 0)
    if [[ "${currentVersion}" == "${schemaVersion}" ]] && jq -e '
      type == "object" and (.groups | type == "array") and (.groups | length > 0) and
      all(.groups[]; (.id // "") != "" and (.sources | type == "array") and any(.sources[]?; .role == "main") and (.user_groups | type == "array") and (.sync | type == "object") and (.sync | has("remote_enabled")) and (.sync | has("event_enabled")) and (.sync | has("quota_auto_apply")) and (.traffic | type == "object"))
    ' "${stateFile}" >/dev/null 2>&1; then
        return 0
    fi
    backupFile=$(backupSubscriptionGroupsStateForMigration) || return 1
    padmCreateTempFileForTarget tmpFile "${stateFile}" migrate || return 1
    if normalizeSubscriptionGroupsState <"${stateFile}" >"${tmpFile}"; then
        commitGeneratedJsonFile "${tmpFile}" "${stateFile}" 600 || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    else
        padmRemoveCleanupPath "${tmpFile}"
        return 1
    fi
    padmRemoveCleanupPath "${backupFile}"
}

ensureSubscriptionGroupsState() {
    local stateDir
    local stateFile
    local stageFile
    stateDir=$(subscriptionGroupsSafeDir) || return 1
    stateFile=$(subscriptionGroupsFile)
    padmEnsureSafeDirectory "${stateDir}" || return 1
    if [[ ! -f "${stateFile}" ]] || ! jq empty "${stateFile}" >/dev/null 2>&1; then
        padmCreateTempFileForTarget stageFile "${stateFile}" init || return 1
        if ! writeDefaultSubscriptionGroupsState "${stageFile}" ||
            ! subscriptionGroupsStateReplace "${stageFile}" "${stateFile}"; then
            padmRemoveCleanupPath "${stageFile}"
            return 1
        fi
        padmRemoveCleanupPath "${stageFile}"
    fi
    migrateSubscriptionGroupsState || return 1
    subscriptionGroupsSecureStateFiles 2>/dev/null || true
}

subscriptionGroupsStateRead() {
    ensureSubscriptionGroupsState || return 1
    jq "$@" "$(subscriptionGroupsFile)"
}

subscriptionGroupsStateReplace() {
    local sourceFile=$1
    local targetFile=$2
    local tmpFile
    [[ -f "${sourceFile}" ]] || return 1
    jq empty "${sourceFile}" >/dev/null 2>&1 || return 1
    padmCreateTempFileForTarget tmpFile "${targetFile}" state || return 1
    cp "${sourceFile}" "${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    if ! jq empty "${tmpFile}" >/dev/null 2>&1; then
        padmRemoveCleanupPath "${tmpFile}"
        return 1
    fi
    commitGeneratedJsonFile "${tmpFile}" "${targetFile}" 600 || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

subscriptionGroupsStateWrite() {
    local stateFile
    local tmpFile
    stateFile=$(subscriptionGroupsFile)
    ensureSubscriptionGroupsState || return 1
    padmCreateTempFileForTarget tmpFile "${stateFile}" update || return 1
    if ! jq "$@" "${stateFile}" >"${tmpFile}" || ! subscriptionGroupsStateReplace "${tmpFile}" "${stateFile}"; then
        padmRemoveCleanupPath "${tmpFile}"
        return 1
    fi
    padmRemoveCleanupPath "${tmpFile}"
    migrateSubscriptionGroupsState || return 1
    subscriptionGroupsSecureStateFiles 2>/dev/null || true
}

createSubscriptionGroupsBackup() {
    local backupDir
    local backupFile
    backupDir=$(subscriptionGroupsBackupDir)
    ensureSubscriptionGroupsState || return 1
    padmEnsureSafeDirectory "${backupDir}" || return 1
    backupFile="${backupDir}/groups-$(date '+%Y%m%d%H%M%S').json"
    if ! cp "$(subscriptionGroupsFile)" "${backupFile}"; then
        removeManagedFilesIfPresentIgnoreFailure "${backupFile}"
        return 1
    fi
    echo "${backupFile}"
}

listSubscriptionGroupsBackups() {
    local backupDir
    backupDir=$(subscriptionGroupsBackupDir)
    [[ -d "${backupDir}" ]] || return 0
    for backupFile in "${backupDir}"/groups-*.json; do
        [[ -f "${backupFile}" ]] && echo "${backupFile}"
    done
}

restoreSubscriptionGroupsBackup() {
    local backupFile=$1
    local stateFile
    local restoreBackupFile
    stateFile=$(subscriptionGroupsFile)
    restoreBackupFile=$(createSubscriptionGroupsBackup) || return 1
    if ! subscriptionGroupsStateReplace "${backupFile}" "${stateFile}"; then
        padmRemoveCleanupPath "${restoreBackupFile}"
        return 1
    fi
    if ! migrateSubscriptionGroupsState; then
        if ! subscriptionGroupsStateReplace "${restoreBackupFile}" "${stateFile}"; then
            padmForgetCleanupPath "${restoreBackupFile}"
            return 1
        fi
        padmRemoveCleanupPath "${restoreBackupFile}"
        return 1
    fi
    padmRemoveCleanupPath "${restoreBackupFile}"
}

activeSubscriptionGroupId() {
    subscriptionGroupsStateRead -r '.active_group'
}

subscriptionGroupRead() {
    local groupId=$1
    shift
    local query
    local argCount=0
    local -a jqArgs=()
    query=${!#}
    if (($# > 1)); then
        argCount=$(($# - 1))
        jqArgs=("${@:1:${argCount}}")
    fi
    subscriptionGroupsStateRead "${jqArgs[@]}" --arg groupId "${groupId}" ".groups[] | select(.id == \$groupId) | ${query}"
}

subscriptionGroupWrite() {
    local groupId=$1
    shift
    local update
    local argCount=0
    local -a jqArgs=()
    update=${!#}
    if (($# > 1)); then
        argCount=$(($# - 1))
        jqArgs=("${@:1:${argCount}}")
    fi
    subscriptionGroupsStateWrite "${jqArgs[@]}" --arg groupId "${groupId}" ".groups |= map(if .id == \$groupId then ${update} else . end)"
}

subscriptionActiveGroupRead() {
    subscriptionGroupRead "$(activeSubscriptionGroupId)" "$@"
}

subscriptionActiveGroupWrite() {
    subscriptionGroupWrite "$(activeSubscriptionGroupId)" "$@"
}

subscriptionActiveEnabledUsersJson() {
    subscriptionActiveGroupRead -c '
      . as $group |
      [.user_groups[]?
       | select(.enabled == true)
       | (.allowed_sources // []) as $allowed
       | {
           id,
           name,
           uuid: (.uuid // ""),
           traffic_limit_gb: (.traffic_limit_gb // 0),
           account: (.id | '"${SUBSCRIPTION_SYNC_ACCOUNT_NAME_FROM_ID_JQ}"'),
           allowed_sources: $allowed,
           allows_main: (if ($allowed | index("*") or index("main")) then true else false end),
           has_remote: (if ($allowed | length) == 0 then
               false
             elif ($allowed | index("*")) then
               any($group.sources[]?; .role != "main" and .enabled == true)
             else
               any($group.sources[]?; .role != "main" and .enabled == true and (.id as $sid | $allowed | index($sid)))
             end)
         }]'
}

addUserSubscriptionState() {
    local id=$1
    local name=$2
    subscriptionActiveGroupWrite --arg id "${id}" --arg name "${name}" '
        if any(.user_groups[]?; .id == $id) then . else
          .user_groups += [{"id": $id, "name": $name, "enabled": true, "allowed_sources": ["main"], "traffic_limit_gb": 0, "token": ""}]
        end
    '
}

removeUserSubscriptionState() {
    local id=$1
    subscriptionActiveGroupWrite --arg id "${id}" '
        .user_groups = ([.user_groups[]? | select(.id != $id)]) |
        .traffic.user_groups |= (del(.[$id]) // {})
    '
}

toggleUserSubscriptionState() {
    local id=$1
    subscriptionActiveGroupWrite --arg id "${id}" '.user_groups |= map(if .id == $id then .enabled = (.enabled | not) else . end)'
}

setUserSubscriptionSources() {
    local id=$1
    local sources=$2
    subscriptionActiveGroupWrite --arg id "${id}" --argjson sources "${sources}" '.user_groups |= map(if .id == $id then .allowed_sources = $sources else . end)'
}

setUserSubscriptionTrafficLimit() {
    local id=$1
    local limit=$2
    subscriptionActiveGroupWrite --arg id "${id}" --argjson limit "${limit}" '.user_groups |= map(if .id == $id then .traffic_limit_gb = $limit else . end)'
}

setUserSubscriptionEnabled() {
    local id=$1
    local enabled=$2
    subscriptionActiveGroupWrite --arg id "${id}" --argjson enabled "${enabled}" '.user_groups |= map(if .id == $id then .enabled = $enabled else . end)'
}

userSubscriptionExists() {
    local id=$1
    subscriptionActiveGroupRead -e --arg id "${id}" 'any(.user_groups[]?; .id == $id)' >/dev/null 2>&1
}

subscriptionGroupSyncEnabled() {
    subscriptionActiveGroupRead -e '.sync.enabled == true' >/dev/null 2>&1
}

setSubscriptionGroupSyncEnabled() {
    local enabled=$1
    subscriptionActiveGroupWrite --argjson enabled "${enabled}" '.sync.enabled = $enabled'
}

toggleSubscriptionGroupSyncEnabled() {
    if subscriptionGroupSyncEnabled; then
        setSubscriptionGroupSyncEnabled false
    else
        setSubscriptionGroupSyncEnabled true
    fi
}

subscriptionGroupRemoteSyncEnabled() {
    subscriptionActiveGroupRead -e '(if .sync | has("remote_enabled") then .sync.remote_enabled else true end) == true' >/dev/null 2>&1
}

toggleSubscriptionGroupRemoteSyncEnabled() {
    subscriptionActiveGroupWrite '.sync.remote_enabled = (if .sync | has("remote_enabled") then (.sync.remote_enabled | not) else false end)'
}

subscriptionEventSyncEnabled() {
    subscriptionActiveGroupRead -e '(if .sync | has("event_enabled") then .sync.event_enabled else true end) == true' >/dev/null 2>&1
}

toggleSubscriptionEventSyncEnabled() {
    subscriptionActiveGroupWrite '.sync.event_enabled = (if .sync | has("event_enabled") then (.sync.event_enabled | not) else false end)'
}

subscriptionGroupQuotaAutoApplyEnabled() {
    subscriptionActiveGroupRead -e '(.sync.quota_auto_apply // false) == true' >/dev/null 2>&1
}

toggleSubscriptionGroupQuotaAutoApplyEnabled() {
    subscriptionActiveGroupWrite '.sync.quota_auto_apply = ((.sync.quota_auto_apply // false) | not)'
}

setSubscriptionGroupSyncInterval() {
    local interval=$1
    subscriptionActiveGroupWrite --argjson interval "${interval}" '.sync.interval_minutes = $interval'
}

subscriptionGroupSyncIntervalValid() {
    local interval=$1
    [[ "${interval}" =~ ^[0-9]+$ ]] && [[ "${interval}" -ge 1 ]] && [[ "${interval}" -le 59 ]]
}

addSubscriptionSourceState() {
    local id=$1
    local name=$2
    local host=$3
    local port=$4
    subscriptionActiveGroupWrite --arg id "${id}" --arg name "${name}" --arg host "${host}" --argjson port "${port}" '
        if any(.sources[]?; .id == $id) then . else
          .sources += [{"id": $id, "name": $name, "role": "secondary", "scheme": "wireguard", "transport": "wireguard", "host": $host, "port": $port, "enabled": true, "sync_status": "pending"}]
        end
    '
}

removeSubscriptionSourceState() {
    local id=$1
    subscriptionActiveGroupWrite --arg id "${id}" '
        if any(.sources[]?; .id == $id and .role == "main") then . else
          .sources = ([.sources[]? | select(.id != $id)]) |
          .traffic.sources |= (del(.[$id]) // {}) |
          .traffic.admin.sources |= (del(.[$id]) // {}) |
          .traffic.user_groups |= with_entries(.value.sources |= (del(.[$id]) // {}))
        end
    '
}

setSubscriptionSourceCredential() {
    local id=$1
    local host=$2
    local port=$3
    local token=$4
    subscriptionActiveGroupWrite --arg id "${id}" --arg host "${host}" --argjson port "${port}" --arg token "${token}" '.sources |= map(if .id == $id and .role != "main" then .transport = "wireguard" | .scheme = "wireguard" | .host = $host | .port = $port | .control_token = $token else . end)'
}

setSubscriptionSourceSyncStatus() {
    local id=$1
    local status=$2
    local changed=${3:-}
    local plan=${4:-}
    if [[ -n "${plan}" ]]; then
        subscriptionActiveGroupWrite --arg id "${id}" --arg status "${status}" --argjson changed "${changed}" --argjson plan "${plan}" '.sources |= map(if .id == $id then .sync_status = $status | .last_sync_changed = $changed | .last_sync_plan = $plan | del(.last_sync_error) else . end)'
    elif [[ -n "${changed}" ]]; then
        subscriptionActiveGroupWrite --arg id "${id}" --arg status "${status}" --argjson changed "${changed}" '.sources |= map(if .id == $id then .sync_status = $status | .last_sync_changed = $changed | del(.last_sync_error) else . end)'
    else
        subscriptionActiveGroupWrite --arg id "${id}" --arg status "${status}" '.sources |= map(if .id == $id then .sync_status = $status else . end)'
    fi
}

setSubscriptionSourceSyncFailure() {
    local id=$1
    local errorType=$2
    local errorMessage=$3
    subscriptionActiveGroupWrite --arg id "${id}" --arg errorType "${errorType}" --arg errorMessage "${errorMessage}" '.sources |= map(if .id == $id then .sync_status = "failed" | .last_sync_changed = false | .last_sync_error = {type:$errorType, message:$errorMessage} | del(.last_sync_plan) else . end)'
}

subscriptionSourceExists() {
    local id=$1
    subscriptionActiveGroupRead -e --arg id "${id}" 'any(.sources[]?; .id == $id)' >/dev/null 2>&1
}

subscriptionSourceIsMain() {
    local id=$1
    subscriptionActiveGroupRead -e --arg id "${id}" 'any(.sources[]?; .id == $id and .role == "main")' >/dev/null 2>&1
}

clearSubscriptionSourceSyncError() {
    local id=$1
    subscriptionActiveGroupWrite --arg id "${id}" '.sources |= map(if .id == $id then del(.last_sync_error) else . end)'
}
