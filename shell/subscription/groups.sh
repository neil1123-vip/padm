#!/usr/bin/env bash

subscriptionGroupsDir() {
    echo "${PADM_SUBSCRIPTION_GROUPS_DIR:-/etc/padm/subscribe_groups}"
}

subscriptionGroupsFile() {
    echo "$(subscriptionGroupsDir)/groups.json"
}

subscriptionGroupsBackupDir() {
    echo "$(subscriptionGroupsDir)/backups"
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
    mkdir -p "${backupDir}"
    backupFile="${backupDir}/groups-pre-migrate-$(date '+%Y%m%d%H%M%S').json"
    cp "${stateFile}" "${backupFile}"
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
          sync: ({enabled:true, interval_minutes:10, last_run:"", last_status:"pending", failures:[], remote_enabled:true, quota_auto_apply:false} + ($group.sync // {})),
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
    stateFile=$(subscriptionGroupsFile)
    tmpFile="${stateFile}.migrate.tmp"
    schemaVersion=$(subscriptionGroupsSchemaVersion)
    currentVersion=$(jq -r '.version // 0' "${stateFile}" 2>/dev/null || echo 0)
    if [[ "${currentVersion}" == "${schemaVersion}" ]] && jq -e '
      type == "object" and (.groups | type == "array") and (.groups | length > 0) and
      all(.groups[]; (.id // "") != "" and (.sources | type == "array") and any(.sources[]?; .role == "main") and (.user_groups | type == "array") and (.sync | type == "object") and (.sync | has("remote_enabled")) and (.sync | has("quota_auto_apply")) and (.traffic | type == "object"))
    ' "${stateFile}" >/dev/null 2>&1; then
        return 0
    fi
    backupSubscriptionGroupsStateForMigration
    if normalizeSubscriptionGroupsState <"${stateFile}" >"${tmpFile}"; then
        mv "${tmpFile}" "${stateFile}"
    else
        rm -f "${tmpFile}"
        return 1
    fi
}

ensureSubscriptionGroupsState() {
    local stateDir
    local stateFile
    stateDir=$(subscriptionGroupsDir)
    stateFile=$(subscriptionGroupsFile)
    mkdir -p "${stateDir}"
    if [[ ! -f "${stateFile}" ]] || ! jq empty "${stateFile}" >/dev/null 2>&1; then
        writeDefaultSubscriptionGroupsState "${stateFile}"
    fi
    migrateSubscriptionGroupsState
    subscriptionGroupsSecureStateFiles 2>/dev/null || true
}

subscriptionGroupsStateRead() {
    ensureSubscriptionGroupsState
    jq "$@" "$(subscriptionGroupsFile)"
}

subscriptionGroupsStateReplace() {
    local sourceFile=$1
    local targetFile=$2
    local tmpFile=$3
    [[ -f "${sourceFile}" ]] || return 1
    jq empty "${sourceFile}" >/dev/null 2>&1 || return 1
    mkdir -p "$(dirname "${targetFile}")"
    cp "${sourceFile}" "${tmpFile}" || return 1
    if ! jq empty "${tmpFile}" >/dev/null 2>&1; then
        rm -f "${tmpFile}"
        return 1
    fi
    mv "${tmpFile}" "${targetFile}"
}

subscriptionGroupsStateWrite() {
    local stateFile
    local tmpFile
    stateFile=$(subscriptionGroupsFile)
    tmpFile="${stateFile}.tmp"
    ensureSubscriptionGroupsState
    if ! jq "$@" "${stateFile}" >"${tmpFile}" || ! subscriptionGroupsStateReplace "${tmpFile}" "${stateFile}" "${tmpFile}.commit"; then
        rm -f "${tmpFile}" "${tmpFile}.commit"
        return 1
    fi
    migrateSubscriptionGroupsState
    subscriptionGroupsSecureStateFiles 2>/dev/null || true
}

createSubscriptionGroupsBackup() {
    local backupDir
    local backupFile
    backupDir=$(subscriptionGroupsBackupDir)
    ensureSubscriptionGroupsState
    mkdir -p "${backupDir}"
    backupFile="${backupDir}/groups-$(date '+%Y%m%d%H%M%S').json"
    cp "$(subscriptionGroupsFile)" "${backupFile}"
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
    stateFile=$(subscriptionGroupsFile)
    if ! subscriptionGroupsStateReplace "${backupFile}" "${stateFile}" "${stateFile}.restore.tmp"; then
        return 1
    fi
    migrateSubscriptionGroupsState
}

activeSubscriptionGroupId() {
    subscriptionGroupsStateRead -r '.active_group'
}

listSubscriptionSources() {
    local groupId
    groupId=${1:-$(activeSubscriptionGroupId)}
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" '.groups[] | select(.id == $groupId) | .sources[] | "\(.id):\(.name):\(.role):\(.scheme):\(.host):\(.port):\(.enabled):\(.sync_status)"'
}

listUserSubscriptions() {
    local groupId
    groupId=${1:-$(activeSubscriptionGroupId)}
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" '.groups[] | select(.id == $groupId) | .user_groups[]? | "\(.id):\(.name):\(.enabled):\(.allowed_sources | join(",")):\(.traffic_limit_gb)"'
}

addUserSubscriptionState() {
    local id=$1
    local name=$2
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg id "${id}" --arg name "${name}" '
      .groups |= map(if .id == $groupId then
        if any(.user_groups[]?; .id == $id) then . else
          .user_groups += [{"id": $id, "name": $name, "enabled": true, "allowed_sources": ["main"], "traffic_limit_gb": 0, "token": ""}]
        end
      else . end)'
}

removeUserSubscriptionState() {
    local id=$1
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg id "${id}" '
      .groups |= map(if .id == $groupId then
        .user_groups = ([.user_groups[]? | select(.id != $id)]) |
        .traffic.user_groups |= (del(.[$id]) // {})
      else . end)'
}

toggleUserSubscriptionState() {
    local id=$1
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg id "${id}" '.groups |= map(if .id == $groupId then .user_groups |= map(if .id == $id then .enabled = (.enabled | not) else . end) else . end)'
}

setUserSubscriptionSources() {
    local id=$1
    local sources=$2
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg id "${id}" --argjson sources "${sources}" '.groups |= map(if .id == $groupId then .user_groups |= map(if .id == $id then .allowed_sources = $sources else . end) else . end)'
}

setUserSubscriptionTrafficLimit() {
    local id=$1
    local limit=$2
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg id "${id}" --argjson limit "${limit}" '.groups |= map(if .id == $groupId then .user_groups |= map(if .id == $id then .traffic_limit_gb = $limit else . end) else . end)'
}

setSubscriptionSources() {
    local sources=$1
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --argjson sources "${sources}" '.groups |= map(if .id == $groupId then .sources = $sources else . end)'
}

addSubscriptionSourceState() {
    local id=$1
    local name=$2
    local host=$3
    local port=$4
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg id "${id}" --arg name "${name}" --arg host "${host}" --argjson port "${port}" '
      .groups |= map(if .id == $groupId then
        if any(.sources[]?; .id == $id) then . else
          .sources += [{"id": $id, "name": $name, "role": "secondary", "scheme": "wireguard", "transport": "wireguard", "host": $host, "port": $port, "enabled": true, "sync_status": "pending"}]
        end
      else . end)'
}

removeSubscriptionSourceState() {
    local id=$1
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg id "${id}" '
      .groups |= map(if .id == $groupId then
        if any(.sources[]?; .id == $id and .role == "main") then . else
          .sources = ([.sources[]? | select(.id != $id)]) |
          .traffic.sources |= (del(.[$id]) // {}) |
          .traffic.admin.sources |= (del(.[$id]) // {}) |
          .traffic.user_groups |= with_entries(.value.sources |= (del(.[$id]) // {}))
        end
      else . end)'
}

setSubscriptionSourceControlToken() {
    local id=$1
    local token=$2
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg id "${id}" --arg token "${token}" '
      .groups |= map(if .id == $groupId then
        .sources |= map(if .id == $id and .role != "main" then .control_token = $token else . end)
      else . end)'
}

setSubscriptionSourceCredential() {
    local id=$1
    local host=$2
    local port=$3
    local token=$4
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg id "${id}" --arg host "${host}" --argjson port "${port}" --arg token "${token}" '
      .groups |= map(if .id == $groupId then
        .sources |= map(if .id == $id and .role != "main" then .transport = "wireguard" | .scheme = "wireguard" | .host = $host | .port = $port | .control_token = $token else . end)
      else . end)'
}

setSubscriptionSourceSyncStatus() {
    local id=$1
    local status=$2
    local changed=${3:-}
    local plan=${4:-}
    local groupId
    groupId=$(activeSubscriptionGroupId)
    if [[ -n "${plan}" ]]; then
        subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg id "${id}" --arg status "${status}" --argjson changed "${changed}" --argjson plan "${plan}" '
          .groups |= map(if .id == $groupId then
            .sources |= map(if .id == $id then .sync_status = $status | .last_sync_changed = $changed | .last_sync_plan = $plan | del(.last_sync_error) else . end)
          else . end)'
    elif [[ -n "${changed}" ]]; then
        subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg id "${id}" --arg status "${status}" --argjson changed "${changed}" '
          .groups |= map(if .id == $groupId then
            .sources |= map(if .id == $id then .sync_status = $status | .last_sync_changed = $changed | del(.last_sync_error) else . end)
          else . end)'
    else
        subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg id "${id}" --arg status "${status}" '
          .groups |= map(if .id == $groupId then
            .sources |= map(if .id == $id then .sync_status = $status else . end)
          else . end)'
    fi
}

setSubscriptionSourceSyncFailure() {
    local id=$1
    local errorType=$2
    local errorMessage=$3
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg id "${id}" --arg errorType "${errorType}" --arg errorMessage "${errorMessage}" '
      .groups |= map(if .id == $groupId then
        .sources |= map(if .id == $id then .sync_status = "failed" | .last_sync_changed = false | .last_sync_error = {type:$errorType, message:$errorMessage} | del(.last_sync_plan) else . end)
      else . end)'
}

setSubscriptionSourceEnabled() {
    local id=$1
    local enabled=$2
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg id "${id}" --argjson enabled "${enabled}" '
      .groups |= map(if .id == $groupId then
        .sources |= map(if .id == $id and .role != "main" then .enabled = $enabled else . end)
      else . end)'
}

subscriptionSourceExists() {
    local id=$1
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateRead -e --arg groupId "${groupId}" --arg id "${id}" '.groups[] | select(.id == $groupId) | any(.sources[]?; .id == $id)' >/dev/null 2>&1
}

subscriptionSourceIsMain() {
    local id=$1
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateRead -e --arg groupId "${groupId}" --arg id "${id}" '.groups[] | select(.id == $groupId) | any(.sources[]?; .id == $id and .role == "main")' >/dev/null 2>&1
}

clearSubscriptionSourceSyncError() {
    local id=$1
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg id "${id}" '
      .groups |= map(if .id == $groupId then
        .sources |= map(if .id == $id then del(.last_sync_error) else . end)
      else . end)'
}
