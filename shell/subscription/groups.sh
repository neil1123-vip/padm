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

subscriptionGroupsLockFile() {
    local groupsDir
    groupsDir=$(subscriptionGroupsSafeDir) || return 1
    printf '%s/groups.lock\n' "${groupsDir}"
}

subscriptionGroupsWithDirectoryLock() {
    local lockTimeout=$1
    local lockDir=$2
    shift 2
    local deadline=$((SECONDS + lockTimeout))
    local lockMtime
    local now
    local ownerPid
    local status

    while ! mkdir -- "${lockDir}" 2>/dev/null; do
        ownerPid=$(cat "${lockDir}/pid" 2>/dev/null || true)
        if [[ "${ownerPid}" =~ ^[0-9]+$ ]] && ! kill -0 "${ownerPid}" 2>/dev/null; then
            rm -f -- "${lockDir}/pid" 2>/dev/null || true
            rmdir -- "${lockDir}" 2>/dev/null || true
            continue
        fi
        if [[ -z "${ownerPid}" ]]; then
            now=$(date +%s)
            lockMtime=$(stat --format=%Y -- "${lockDir}" 2>/dev/null || printf '%s\n' "${now}")
            if ((now - lockMtime > 5)); then
                rmdir -- "${lockDir}" 2>/dev/null || true
                continue
            fi
        fi
        ((SECONDS < deadline)) || return 1
        sleep 0.1
    done
    printf '%s\n' "${BASHPID:-$$}" >"${lockDir}/pid" || { rmdir -- "${lockDir}" 2>/dev/null || true; return 1; }

    local SUBSCRIPTION_GROUPS_LOCK_HELD=1
    if "$@"; then
        status=0
    else
        status=$?
    fi
    rm -f -- "${lockDir}/pid" 2>/dev/null || true
    rmdir -- "${lockDir}" 2>/dev/null || true
    return "${status}"
}

subscriptionGroupsWithLock() {
    if [[ "${SUBSCRIPTION_GROUPS_LOCK_HELD:-}" == "1" ]]; then
        "$@"
        return $?
    fi

    local groupsDir
    local lockFile
    local lockTimeout=${PADM_SUBSCRIPTION_GROUPS_LOCK_TIMEOUT:-30}
    local lockFd
    local status
    [[ "${lockTimeout}" =~ ^[0-9]+$ ]] || lockTimeout=30
    groupsDir=$(subscriptionGroupsSafeDir) || return 1
    padmEnsureSafeDirectory "${groupsDir}" || return 1
    lockFile=$(subscriptionGroupsLockFile) || return 1
    # ponytail: one state lock; split only if subscription write throughput becomes material.
    if ! command -v flock >/dev/null 2>&1; then
        subscriptionGroupsWithDirectoryLock "${lockTimeout}" "${lockFile}.d" "$@"
        return $?
    fi
    exec {lockFd}>"${lockFile}" || return 1
    chmod 600 "${lockFile}" 2>/dev/null || { exec {lockFd}>&-; return 1; }
    if ! flock -w "${lockTimeout}" "${lockFd}"; then
        exec {lockFd}>&-
        return 1
    fi

    local SUBSCRIPTION_GROUPS_LOCK_HELD=1
    if "$@"; then
        status=0
    else
        status=$?
    fi
    flock -u "${lockFd}" >/dev/null 2>&1 || true
    exec {lockFd}>&-
    return "${status}"
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
          "transport": "local",
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

validateSubscriptionGroupsState() {
    local stateFile=$1
    local schemaVersion
    schemaVersion=$(subscriptionGroupsSchemaVersion)
    jq -e --argjson schemaVersion "${schemaVersion}" '
      def exact($required; $optional):
        type == "object" and
        ((keys - ($required + $optional)) | length == 0) and
        (. as $object | all($required[]; . as $key | $object | has($key)));
      def nonempty_string: type == "string" and length > 0;
      def count: type == "number" and . == floor and . >= 0;
      def allowed_sources:
        type == "array" and length > 0 and all(.[]; nonempty_string);
      def principal($optional):
        exact(["id", "name", "enabled", "allowed_sources", "traffic_limit_gb", "token"]; $optional) and
        (.id | nonempty_string) and (.name | nonempty_string) and
        (.enabled | type == "boolean") and (.allowed_sources | allowed_sources) and
        (.traffic_limit_gb | count) and (.token | type == "string") and
        ((has("uuid") | not) or (.uuid | type == "string" and test("^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$")));
      def sync_plan:
        exact(["create", "remove"]; []) and
        (.create | type == "array" and all(.[]?; nonempty_string)) and
        (.remove | type == "array" and all(.[]?; nonempty_string));
      def sync_error:
        exact(["type", "message"]; []) and
        (.type | nonempty_string) and (.message | nonempty_string);
      def source:
        if .role == "main" then
          exact(["id", "name", "role", "scheme", "transport", "host", "port", "enabled", "sync_status"]; []) and
          .id == "main" and .scheme == "local" and .transport == "local" and
          (.name | nonempty_string) and (.host | nonempty_string) and
          .port == 0 and .enabled == true and .sync_status == "local"
        else
          exact(["id", "name", "role", "scheme", "transport", "host", "port", "enabled", "sync_status"];
            ["control_token", "last_sync_changed", "last_sync_plan", "last_sync_error"]) and
          .role == "secondary" and .scheme == "wireguard" and .transport == "wireguard" and
          (.id | nonempty_string) and (.name | nonempty_string) and (.host | nonempty_string) and
          (.port | type == "number" and . == floor and . >= 1 and . <= 65535) and
          (.enabled | type == "boolean") and
          (.sync_status == "pending" or .sync_status == "success" or .sync_status == "failed") and
          ((has("control_token") | not) or (.control_token | nonempty_string)) and
          ((has("last_sync_changed") | not) or (.last_sync_changed | type == "boolean")) and
          ((has("last_sync_plan") | not) or (.last_sync_plan | sync_plan)) and
          ((has("last_sync_error") | not) or (.last_sync_error | sync_error))
        end;
      def traffic_total:
        exact(["upload", "download"]; []) and (.upload | count) and (.download | count);
      def source_traffic:
        exact(["upload", "download"]; ["counters", "updated_at"]) and
        (.upload | count) and (.download | count) and
        ((has("counters") | not) or
          (.counters | type == "object" and all(to_entries[]?; (.key | nonempty_string) and (.value | traffic_total)))) and
        ((has("updated_at") | not) or (.updated_at | type == "string"));
      def source_traffic_map:
        type == "object" and all(to_entries[]?; (.key | nonempty_string) and (.value | source_traffic));
      def scoped_traffic:
        exact(["upload", "download", "sources"]; []) and
        (.upload | count) and (.download | count) and (.sources | source_traffic_map);

      exact(["version", "active_group", "groups"]; []) and .version == $schemaVersion and
      (.groups | type == "array" and length > 0) and
      (.active_group | type == "string" and length > 0) and (.active_group as $active | any(.groups[]?; .id == $active)) and
      all(.groups[];
        exact(["id", "name", "admin", "sources", "user_groups", "sync", "traffic"]; []) and
        (.id | nonempty_string) and (.name | nonempty_string) and
        (.admin | principal([])) and
        (.sources | type == "array" and length > 0 and all(.[]; source) and ([.[] | select(.role == "main")] | length == 1)) and
        (.user_groups | type == "array" and all(.[]; principal(["uuid"]))) and
        (.sync |
          exact(["enabled", "interval_minutes", "last_run", "last_status", "failures", "quota_auto_apply"]; []) and
          (.enabled | type == "boolean") and
          (.interval_minutes | type == "number" and . == floor and . >= 1 and . <= 59) and
          (.last_run | type == "string") and
          (.last_status == "pending" or .last_status == "success" or .last_status == "partial") and
          (.failures | type == "array" and all(.[]; type == "string")) and
          (.quota_auto_apply | type == "boolean")) and
        (.traffic |
          exact(["global", "admin", "user_groups", "sources"]; []) and
          (.global | traffic_total) and (.admin | scoped_traffic) and
          (.user_groups | type == "object" and all(to_entries[]?; (.key | nonempty_string) and (.value | scoped_traffic))) and
          (.sources | source_traffic_map)))
    ' "${stateFile}" >/dev/null 2>&1
}

ensureSubscriptionGroupsStateUnlocked() {
    local stateDir
    local stateFile
    local stageFile
    stateDir=$(subscriptionGroupsSafeDir) || return 1
    stateFile=$(subscriptionGroupsFile)
    padmEnsureSafeDirectory "${stateDir}" || return 1
    if [[ ! -e "${stateFile}" && ! -L "${stateFile}" ]]; then
        padmCreateTempFileForTarget stageFile "${stateFile}" init || return 1
        if ! writeDefaultSubscriptionGroupsState "${stageFile}" ||
            ! subscriptionGroupsStateReplace "${stageFile}" "${stateFile}"; then
            padmRemoveCleanupPath "${stageFile}"
            return 1
        fi
        padmRemoveCleanupPath "${stageFile}"
    elif [[ ! -f "${stateFile}" ]] || ! validateSubscriptionGroupsState "${stateFile}"; then
        return 1
    fi
    if declare -F subscriptionGroupsSecureStateFiles >/dev/null 2>&1; then
        subscriptionGroupsSecureStateFiles 2>/dev/null || return 1
    fi
}


ensureSubscriptionGroupsState() {
    subscriptionGroupsWithLock ensureSubscriptionGroupsStateUnlocked "$@"
}

subscriptionGroupsStateRead() {
    ensureSubscriptionGroupsState || return 1
    jq "$@" "$(subscriptionGroupsFile)"
}

subscriptionGroupsStateReplaceUnlocked() {
    local sourceFile=$1
    local targetFile=$2
    local tmpFile
    [[ -f "${sourceFile}" ]] || return 1
    validateSubscriptionGroupsState "${sourceFile}" || return 1
    padmCreateTempFileForTarget tmpFile "${targetFile}" state || return 1
    cp "${sourceFile}" "${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    if ! validateSubscriptionGroupsState "${tmpFile}"; then
        padmRemoveCleanupPath "${tmpFile}"
        return 1
    fi
    commitGeneratedJsonFile "${tmpFile}" "${targetFile}" 600 || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

subscriptionGroupsStateReplace() {
    subscriptionGroupsWithLock subscriptionGroupsStateReplaceUnlocked "$@"
}

subscriptionGroupsStateWriteUnlocked() {
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
    if declare -F subscriptionGroupsSecureStateFiles >/dev/null 2>&1; then
        subscriptionGroupsSecureStateFiles 2>/dev/null || return 1
    fi
}

subscriptionGroupsStateWrite() {
    subscriptionGroupsWithLock subscriptionGroupsStateWriteUnlocked "$@"
}

createSubscriptionGroupsBackupUnlocked() {
    local backupDir
    local backupFile
    backupDir=$(subscriptionGroupsBackupDir)
    ensureSubscriptionGroupsState || return 1
    padmEnsureSafeDirectory "${backupDir}" || return 1
    chmod 700 "${backupDir}" 2>/dev/null || return 1
    backupFile="${backupDir}/groups-$(date '+%Y%m%d%H%M%S')-${BASHPID:-$$}-${RANDOM}.json"
    while [[ -e "${backupFile}" ]]; do
        backupFile="${backupDir}/groups-$(date '+%Y%m%d%H%M%S')-${BASHPID:-$$}-${RANDOM}.json"
    done
    if ! backupManagedFileToPath "$(subscriptionGroupsFile)" "${backupFile}" 600; then
        removeManagedFilesIfPresentIgnoreFailure "${backupFile}"
        return 1
    fi
    echo "${backupFile}"
}

createSubscriptionGroupsBackup() {
    subscriptionGroupsWithLock createSubscriptionGroupsBackupUnlocked "$@"
}

listSubscriptionGroupsBackups() {
    local backupDir
    backupDir=$(subscriptionGroupsBackupDir)
    [[ -d "${backupDir}" ]] || return 0
    for backupFile in "${backupDir}"/groups-*.json; do
        [[ -f "${backupFile}" ]] && echo "${backupFile}"
    done
}

restoreSubscriptionGroupsBackupUnlocked() {
    local backupFile=$1
    local stateFile
    local restoreBackupFile
    stateFile=$(subscriptionGroupsFile)
    restoreBackupFile=$(createSubscriptionGroupsBackup) || return 1
    if ! subscriptionGroupsStateReplace "${backupFile}" "${stateFile}"; then
        padmRemoveCleanupPath "${restoreBackupFile}"
        return 1
    fi
    padmRemoveCleanupPath "${restoreBackupFile}"
}

restoreSubscriptionGroupsBackup() {
    subscriptionGroupsWithLock restoreSubscriptionGroupsBackupUnlocked "$@"
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
    subscriptionGroupsStateRead "${jqArgs[@]}" --arg groupId "${groupId}" ".groups | map(select(.id == \$groupId)) | if length > 0 then .[0] | ${query} else error(\"subscription group not found\") end"
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
    local sources=${3:-'["main"]'}
    local limit=${4:-0}
    subscriptionActiveGroupWrite --arg id "${id}" --arg name "${name}" --argjson sources "${sources}" --argjson limit "${limit}" '
        if any(.user_groups[]?; .id == $id) then error("user subscription already exists") else
          .user_groups += [{"id": $id, "name": $name, "enabled": true, "allowed_sources": $sources, "traffic_limit_gb": $limit, "token": ""}]
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
    [[ "${interval}" =~ ^[0-9]{1,2}$ ]] && ((10#${interval} >= 1 && 10#${interval} <= 59))
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

setSubscriptionSourceEnabled() {
    local id=$1
    local enabled=$2
    [[ "${enabled}" == "true" || "${enabled}" == "false" ]] || return 1
    subscriptionActiveGroupWrite --arg id "${id}" --argjson enabled "${enabled}" '
      if any(.sources[]?; .id == $id and .role != "main") then
        .sources |= map(if .id == $id and .role != "main" then .enabled = $enabled else . end)
      else
        error("remote subscription source not found")
      end
    '
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

subscriptionHasEnabledRemoteSources() {
    subscriptionActiveGroupRead -e 'any(.sources[]?; .role != "main" and .enabled == true)' >/dev/null 2>&1
}

clearSubscriptionSourceSyncError() {
    local id=$1
    subscriptionActiveGroupWrite --arg id "${id}" '.sources |= map(if .id == $id then del(.last_sync_error) else . end)'
}
