#!/usr/bin/env bash

subscriptionGroupsDir() {
    echo "${PADM_SUBSCRIPTION_GROUPS_DIR:-/etc/padm/subscribe_groups}"
}

subscriptionGroupsSafeDir() {
    local groupsDir
    groupsDir=$(subscriptionGroupsDir)
    groupsDir=$(padmRequireSafeAbsolutePath "${groupsDir%/}") || return 1
    printf '%s\n' "${groupsDir}"
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
    echo 6
}

subscriptionStateIdValid() {
    local id=${1:-}
    [[ "${id}" =~ ^[A-Za-z0-9_-]+$ ]] && ((${#id} <= 64))
}

subscriptionTrafficTotalsJq() {
    cat <<'EOF'
def subscriptionTrafficTotal($sources):
  ($sources // {}) as $map |
  {upload: ([$map[]?.upload] | add // 0), download: ([$map[]?.download] | add // 0)};
EOF
}

writeDefaultSubscriptionGroupsState() {
    cat <<EOF >"$1"
{
  "version": $(subscriptionGroupsSchemaVersion),
  "id": "default",
  "name": "默认订阅组",
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
    "admin": {"sources": {}},
    "user_groups": {},
    "sources": {}
  }
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
      def state_id: type == "string" and length <= 64 and test("^[A-Za-z0-9_-]+$");
      def count: type == "number" and . == floor and . >= 0;
      def allowed_sources:
        type == "array" and length > 0 and all(.[]; . == "*" or state_id) and
        (length == (unique | length)) and ((index("*") == null) or . == ["*"]);
      def principal($optional):
        exact(["id", "name", "enabled", "allowed_sources", "traffic_limit_gb"]; $optional) and
        (.id | state_id) and (.name | nonempty_string) and
        (.enabled | type == "boolean") and (.allowed_sources | allowed_sources) and
        (.traffic_limit_gb | count) and
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
          (.id | state_id) and (.name | nonempty_string) and (.host | nonempty_string) and
          (.port | type == "number" and . == floor and . >= 1 and . <= 65535) and
          (.enabled | type == "boolean") and
          (.sync_status == "pending" or .sync_status == "success" or .sync_status == "failed") and
          ((has("control_token") | not) or (.control_token | nonempty_string)) and
          ((has("last_sync_changed") | not) or (.last_sync_changed | type == "boolean")) and
          ((has("last_sync_plan") | not) or (.last_sync_plan | sync_plan)) and
          ((has("last_sync_error") | not) or (.last_sync_error | sync_error))
        end;
      def source_traffic:
        exact(["upload", "download"]; ["counters", "updated_at"]) and
        (.upload | count) and (.download | count) and
        ((has("counters") | not) or
          (.counters | type == "object" and all(to_entries[]?;
            (.key | nonempty_string) and
            (.value |
              type == "object" and length > 0 and
              ((keys - ["legacy", "sing-box", "xray"]) | length == 0) and
              ((has("legacy") | not) or keys == ["legacy"]) and
              all(to_entries[]?;
                .value | exact(["upload", "download"]; []) and
                (.upload | count) and (.download | count)))))) and
        ((has("updated_at") | not) or (.updated_at | type == "string"));
      def source_traffic_map:
        type == "object" and all(to_entries[]?; (.key | nonempty_string) and (.value | source_traffic));
      def scoped_traffic:
        exact(["sources"]; []) and (.sources | source_traffic_map);
      def ids_subset($map; $ids):
        ($map | keys | all(.[]; . as $id | ($ids | index($id)) != null));
      exact(["version", "id", "name", "sources", "user_groups", "sync", "traffic"]; []) and .version == $schemaVersion and
      (.id | state_id) and (.name | nonempty_string) and
      ([.sources[]?.id] | length) == ([.sources[]?.id] | unique | length) and
      (.sources | type == "array" and length > 0 and all(.[]; source) and ([.[] | select(.role == "main")] | length == 1)) and
      (.user_groups | type == "array" and all(.[]; principal(["uuid"]))) and
      ([.user_groups[]?.id] | length) == ([.user_groups[]?.id] | unique | length) and
      ([.user_groups[]? | select(has("uuid")) | .uuid | ascii_downcase] | length) ==
        ([.user_groups[]? | select(has("uuid")) | .uuid | ascii_downcase] | unique | length) and
      (all(.user_groups[]?.id; state_id)) and
      ([.sources[]?.id] as $sourceIds | all(.user_groups[]?.allowed_sources[]?; . as $sourceId | $sourceId == "*" or ($sourceIds | index($sourceId)) != null)) and
      (.sync |
        exact(["enabled", "interval_minutes", "last_run", "last_status", "failures", "quota_auto_apply"]; []) and
        (.enabled | type == "boolean") and
        (.interval_minutes | type == "number" and . == floor and . >= 1 and . <= 59) and
        (.last_run | type == "string") and
        (.last_status == "pending" or .last_status == "success" or .last_status == "partial") and
        (.failures | type == "array" and all(.[]; type == "string")) and
        (.quota_auto_apply | type == "boolean")) and
      (.traffic |
        exact(["admin", "user_groups", "sources"]; []) and
        (.admin | scoped_traffic) and
        (.user_groups | type == "object" and all(to_entries[]?; (.key | state_id) and (.value | scoped_traffic))) and
        (.sources | source_traffic_map)) and
      ([.sources[]?.id] as $sourceIds |
        [.user_groups[]?.id] as $userIds |
        ids_subset(.traffic.sources; $sourceIds) and
        ids_subset(.traffic.admin.sources; $sourceIds) and
        ids_subset(.traffic.user_groups; $userIds) and
        (all(.traffic.user_groups[]?; (.sources | keys | all(.[]; . as $id | ($sourceIds | index($id)) != null)))))
    ' "${stateFile}" >/dev/null 2>&1
}

backupSubscriptionGroupsStateForMigration() {
    local stateFile=$1
    local targetVersion=${2:-6}
    local backupDir
    local backupFile
    backupDir=$(subscriptionGroupsBackupDir) || return 1
    padmEnsureSafeDirectory "${backupDir}" || return 1
    chmod 700 "${backupDir}" 2>/dev/null || return 1
    backupFile="${backupDir}/groups-pre-v${targetVersion}-migration-$(date '+%Y%m%d%H%M%S')-${BASHPID:-$$}-${RANDOM}.json"
    while [[ -e "${backupFile}" ]]; do
        backupFile="${backupDir}/groups-pre-v${targetVersion}-migration-$(date '+%Y%m%d%H%M%S')-${BASHPID:-$$}-${RANDOM}.json"
    done
    backupManagedFileToPath "${stateFile}" "${backupFile}" 600 || return 1
    printf '%s\n' "${backupFile}"
}

migrateSubscriptionGroupsState() {
    local stateFile=$1
    local outputFile=${2:-}
    local fromVersion
    local backupVersion
    local stageFile
    local ownsStage=true
    fromVersion=$(jq -r '.version // empty' "${stateFile}" 2>/dev/null) || return 1
    [[ "${fromVersion}" == "2" || "${fromVersion}" == "3" || "${fromVersion}" == "4" || "${fromVersion}" == "5" ]] || return 1
    backupVersion=6
    [[ "${fromVersion}" == "2" ]] && backupVersion=3
    [[ "${fromVersion}" == "3" ]] && backupVersion=4
    [[ "${fromVersion}" == "4" ]] && backupVersion=5
    if [[ -n "${outputFile}" ]]; then
        stageFile=${outputFile}
        ownsStage=false
    else
        padmCreateTempFileForTarget stageFile "${stateFile}" v6-migration || return 1
    fi
    if ! jq -e '
      def valid_id: type == "string" and length <= 64 and test("^[A-Za-z0-9_-]+$");
      def valid_count: type == "number" and . == floor and . >= 0;
      def count_or_zero($object; $key; $message):
        if ($object | has($key) | not) then 0
        elif ($object[$key] | valid_count) then $object[$key]
        else error($message)
        end;
      def object_field($object; $key; $message):
        if ($object | has($key) | not) then {}
        elif (($object[$key] | type) != "object") then error($message)
        else $object[$key]
        end;
      def normalize_traffic($value):
        if (($value | type) != "object") then error("invalid traffic value")
        else
          {upload:count_or_zero($value; "upload"; "invalid traffic total"),
           download:count_or_zero($value; "download"; "invalid traffic total")} +
          (if ($value | has("counters")) then
             if ($value.counters | type) != "object" then error("invalid traffic counters")
              else {counters:(reduce ($value.counters | to_entries[]?) as $entry ({};
               if (($entry.value | type) != "object" ) then
                 error("invalid traffic counter")
               else .[$entry.key] = {legacy:{
                 upload:count_or_zero($entry.value; "upload"; "invalid traffic counter"),
                 download:count_or_zero($entry.value; "download"; "invalid traffic counter")
               }}
               end))}
             end
           else {} end) +
          (if ($value | has("updated_at")) then
             if ($value.updated_at | type) == "string" then {updated_at:$value.updated_at}
             else error("invalid traffic timestamp") end
           else {} end)
        end;
      def source_map($value; $source_ids):
        if (($value | type) != "object") then error("invalid traffic source map")
        else reduce ($value | to_entries[]? | . as $entry |
          select(($source_ids | index($entry.key)) != null)) as $entry ({};
            .[$entry.key] = normalize_traffic($entry.value))
        end;
      def scoped_map($value; $source_ids):
        if (($value | type) != "object") then error("invalid scoped traffic")
        else {sources: source_map(object_field($value; "sources"; "invalid traffic source map"); $source_ids)} end;
      def normalize_group:
        if ((.id | valid_id) | not) then error("unsafe subscription group id") else . end |
        if ((.sources | type) != "array") or (all(.sources[]?.id; valid_id) | not) then
          error("unsafe subscription source id")
        else . end |
        if ((.user_groups | type) != "array") or (all(.user_groups[]?.id; valid_id) | not) then
          error("unsafe user subscription id")
        else . end |
        (.sources | map(.id)) as $source_ids |
        (.user_groups | map(.id)) as $user_ids |
        .user_groups |= map(
          del(.token) |
          if ((.allowed_sources | type) != "array") then error("invalid allowed sources")
          elif (.allowed_sources | index("*")) != null then .allowed_sources = ["*"]
        else .allowed_sources = ([.allowed_sources[]? | . as $source_id |
            select(($source_ids | index($source_id)) != null)] | unique | if length == 0 then ["main"] else . end)
          end) |
        (if has("traffic") then .traffic else {} end) as $traffic |
        if (($traffic | type) != "object") then error("invalid traffic root") else . end |
        .traffic = {
          admin: scoped_map(object_field($traffic; "admin"; "invalid admin traffic"); $source_ids),
          user_groups: (object_field($traffic; "user_groups"; "invalid user traffic map") as $user_traffic |
            reduce ($user_traffic | to_entries[]? | . as $entry |
              select(($user_ids | index($entry.key)) != null)) as $entry ({};
                .[$entry.key] = scoped_map($entry.value; $source_ids))
            ),
          sources: source_map(object_field($traffic; "sources"; "invalid traffic source map"); $source_ids)
        } |
        {version:6, id:.id, name:.name, sources:.sources, user_groups:.user_groups,
         sync: {
           enabled: .sync.enabled,
           interval_minutes: .sync.interval_minutes,
           last_run: .sync.last_run,
           last_status: .sync.last_status,
           failures: .sync.failures,
           quota_auto_apply: .sync.quota_auto_apply
         },
         traffic:.traffic};
      if .version == 5 then
        normalize_group
      elif ((.version == 2 or .version == 3 or .version == 4) and
          (.groups | type == "array") and (.groups | length == 1) and
          (.active_group == .groups[0].id)) then
        .groups[0] | normalize_group
      else error("single subscription group required")
      end
    ' "${stateFile}" >"${stageFile}" || ! validateSubscriptionGroupsState "${stageFile}"; then
        [[ "${ownsStage}" == true ]] && padmRemoveCleanupPath "${stageFile}"
        return 1
    fi
    [[ "${ownsStage}" == true ]] || return 0
    if ! backupSubscriptionGroupsStateForMigration "${stateFile}" "${backupVersion}" >/dev/null; then
        padmRemoveCleanupPath "${stageFile}"
        return 1
    fi
    if ! commitGeneratedFile "${stageFile}" "${stateFile}" 600; then
        padmRemoveCleanupPath "${stageFile}"
        return 1
    fi
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
    elif [[ ! -f "${stateFile}" ]]; then
        return 1
    elif ! validateSubscriptionGroupsState "${stateFile}"; then
        migrateSubscriptionGroupsState "${stateFile}" || return 1
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
    local normalizedFile=
    local sourceVersion
    local tmpFile
    [[ -f "${sourceFile}" ]] || return 1
    if ! validateSubscriptionGroupsState "${sourceFile}"; then
        sourceVersion=$(jq -r '.version // empty' "${sourceFile}" 2>/dev/null) || return 1
        [[ "${sourceVersion}" == "2" || "${sourceVersion}" == "3" || "${sourceVersion}" == "4" || "${sourceVersion}" == "5" ]] || return 1
        padmCreateTempFileForTarget normalizedFile "${targetFile}" restore-migration || return 1
        if ! migrateSubscriptionGroupsState "${sourceFile}" "${normalizedFile}"; then
            padmRemoveCleanupPath "${normalizedFile}"
            return 1
        fi
        sourceFile=${normalizedFile}
    fi
    padmCreateTempFileForTarget tmpFile "${targetFile}" state || return 1
    if ! cp "${sourceFile}" "${tmpFile}"; then
        padmRemoveCleanupPath "${tmpFile}"
        [[ -n "${normalizedFile}" ]] && padmRemoveCleanupPath "${normalizedFile}"
        return 1
    fi
    if ! validateSubscriptionGroupsState "${tmpFile}"; then
        padmRemoveCleanupPath "${tmpFile}"
        [[ -n "${normalizedFile}" ]] && padmRemoveCleanupPath "${normalizedFile}"
        return 1
    fi
    if ! commitGeneratedJsonFile "${tmpFile}" "${targetFile}" 600; then
        padmRemoveCleanupPath "${tmpFile}"
        [[ -n "${normalizedFile}" ]] && padmRemoveCleanupPath "${normalizedFile}"
        return 1
    fi
    if [[ -n "${normalizedFile}" ]]; then
        padmRemoveCleanupPath "${normalizedFile}"
    fi
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
    local backupFile
    backupDir=$(subscriptionGroupsBackupDir) || return 1
    [[ -d "${backupDir}" ]] || return 0
    for backupFile in "${backupDir}"/groups-*.json; do
        [[ -f "${backupFile}" ]] && echo "${backupFile}"
    done
}

restoreSubscriptionGroupsBackupUnlocked() {
    local backupFile=$1
    local stateFile
    stateFile=$(subscriptionGroupsFile)
    subscriptionGroupsStateReplace "${backupFile}" "${stateFile}"
}

restoreSubscriptionGroupsBackup() {
    subscriptionGroupsWithLock restoreSubscriptionGroupsBackupUnlocked "$@"
}

subscriptionActiveGroupRead() {
    local query
    local argCount=0
    local -a jqArgs=()
    query=${!#}
    if (($# > 1)); then
        argCount=$(($# - 1))
        jqArgs=("${@:1:${argCount}}")
    fi
    subscriptionGroupsStateRead "${jqArgs[@]}" "${query}"
}

subscriptionActiveGroupWrite() {
    local update
    local argCount=0
    local -a jqArgs=()
    update=${!#}
    if (($# > 1)); then
        argCount=$(($# - 1))
        jqArgs=("${@:1:${argCount}}")
    fi
    subscriptionGroupsStateWrite "${jqArgs[@]}" "${update}"
}

subscriptionActiveGroupSetById() {
    local collection=$1
    local id=$2
    local missingMessage=$3
    local update
    local argCount=0
    local -a jqArgs=()
    subscriptionStateIdValid "${id}" || return 1
    shift 3
    update=${!#}
    if (($# > 1)); then
        argCount=$(($# - 1))
        jqArgs=("${@:1:${argCount}}")
    fi
    local query="
      if any(.[\$collection][]?; .id == \$id) then
        .[\$collection] |= map(if .id == \$id then ${update} else . end)
      else
        error(\$missingMessage)
      end
    "
    subscriptionActiveGroupWrite "${jqArgs[@]}" \
        --arg collection "${collection}" \
        --arg id "${id}" \
        --arg missingMessage "${missingMessage}" \
        "${query}"
}

subscriptionEnabledUsersJsonFromState() {
    local state=$1
    jq -c '
      if has("groups") then
        .active_group as $active | first(.groups[]? | select(.id == $active))
      else
        .
      end |
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
         }]
    ' <<<"${state}"
}

subscriptionActiveEnabledUsersJson() {
    local groupState
    groupState=$(subscriptionActiveGroupRead -c '.') || return 1
    subscriptionEnabledUsersJsonFromState "${groupState}"
}

addUserSubscriptionState() {
    local id=$1
    local name=$2
    local sources=${3:-'["main"]'}
    local limit=${4:-0}
    subscriptionStateIdValid "${id}" || return 1
    subscriptionActiveGroupWrite --arg id "${id}" --arg name "${name}" --argjson sources "${sources}" --argjson limit "${limit}" '
        if any(.user_groups[]?; .id == $id) then error("user subscription already exists") else
          .user_groups += [{"id": $id, "name": $name, "enabled": true, "allowed_sources": $sources, "traffic_limit_gb": $limit}]
        end
    '
}

subscriptionApplyUserGroupState() {
    local desiredUsers=${1:-'[]'}
    local removeIds=${2:-'[]'}
    jq -e -n --argjson users "${desiredUsers}" --argjson removeIds "${removeIds}" '
      ($users | type == "array" and all(.[]?; type == "object" and
        (.id | type == "string" and length <= 64 and test("^[A-Za-z0-9_-]+$")) and
        (.uuid | type == "string" and test("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")))) and
      ($removeIds | type == "array" and all(.[]?; type == "string" and length <= 64 and test("^[A-Za-z0-9_-]+$"))) and
      ([$users[]?.id] | length) == ([$users[]?.id] | unique | length) and
      ([$users[]?.uuid | ascii_downcase] | length) == ([$users[]?.uuid | ascii_downcase] | unique | length)
    ' >/dev/null 2>&1 || return 1
    subscriptionActiveGroupWrite --argjson users "${desiredUsers}" --argjson removeIds "${removeIds}" '
      .user_groups = [.user_groups[]? | select(.id as $id | ($removeIds | index($id) | not))] |
      .traffic.user_groups = (reduce $removeIds[] as $id ((.traffic.user_groups // {}); del(.[$id]))) |
      reduce $users[] as $user (.;
        if any(.user_groups[]?; .id == $user.id) then
          .user_groups |= map(if .id == $user.id then .enabled = true | .uuid = $user.uuid else . end)
        else
          .user_groups += [{id:$user.id, name:$user.id, enabled:true, allowed_sources:["main"], traffic_limit_gb:0, uuid:$user.uuid}]
        end)
    '
}

removeUserSubscriptionState() {
    local id=$1
    subscriptionStateIdValid "${id}" || return 1
    subscriptionActiveGroupWrite --arg id "${id}" '
        if any(.user_groups[]?; .id == $id) then
          .user_groups = ([.user_groups[]? | select(.id != $id)]) |
          .traffic.user_groups |= (del(.[$id]) // {})
        else
          error("user subscription not found")
        end
    '
}

toggleUserSubscriptionState() {
    local id=$1
    subscriptionActiveGroupSetById user_groups "${id}" "user subscription not found" '.enabled = (.enabled | not)'
}

setUserSubscriptionSources() {
    local id=$1
    local sources=$2
    subscriptionStateIdValid "${id}" || return 1
    subscriptionActiveGroupSetById user_groups "${id}" "user subscription not found" \
        --argjson sources "${sources}" '.allowed_sources = $sources'
}

setUserSubscriptionTrafficLimit() {
    local id=$1
    local limit=$2
    subscriptionStateIdValid "${id}" || return 1
    subscriptionActiveGroupSetById user_groups "${id}" "user subscription not found" \
        --argjson limit "${limit}" '.traffic_limit_gb = $limit'
}

setUserSubscriptionEnabled() {
    local id=$1
    local enabled=$2
    subscriptionStateIdValid "${id}" || return 1
    subscriptionActiveGroupSetById user_groups "${id}" "user subscription not found" \
        --argjson enabled "${enabled}" '.enabled = $enabled'
}

userSubscriptionExists() {
    local id=$1
    subscriptionStateIdValid "${id}" || return 1
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
    subscriptionStateIdValid "${id}" || return 1
    subscriptionActiveGroupWrite --arg id "${id}" --arg name "${name}" --arg host "${host}" --argjson port "${port}" '
        if any(.sources[]?; .id == $id) then . else
          .sources += [{"id": $id, "name": $name, "role": "secondary", "scheme": "wireguard", "transport": "wireguard", "host": $host, "port": $port, "enabled": true, "sync_status": "pending"}]
        end
    '
}

subscriptionSourceRemovalAllowed() {
    local id=$1
    subscriptionStateIdValid "${id}" || return 1
    subscriptionActiveGroupRead -e --arg id "${id}" '
        any(.sources[]?; .id == $id and .role != "main") and
        all(.user_groups[]?.allowed_sources[]?; . != "*" and . != $id)
    ' >/dev/null 2>&1
}

removeSubscriptionSourceState() {
    local id=$1
    local autoDetach=${2:-false}
    local autoDetachJson=false
    subscriptionStateIdValid "${id}" || return 1
    if [[ "${autoDetach}" == "true" ]]; then
        autoDetachJson=true
    else
        subscriptionSourceRemovalAllowed "${id}" || return 1
    fi
    subscriptionActiveGroupWrite --arg id "${id}" --argjson autoDetach "${autoDetachJson}" '
        if any(.sources[]?; .id == $id and .role == "main") then
          error("main subscription source cannot be removed")
        elif (any(.sources[]?; .id == $id) | not) then
          error("subscription source not found")
        elif ($autoDetach | not) and any(.user_groups[]?.allowed_sources[]?; . == "*" or . == $id) then
          error("subscription source is still referenced by a user")
        else
          (if $autoDetach then
             .user_groups |= map(
               .allowed_sources |= (
                 if index($id) == null then .
                 else ([.[] | select(. != $id)] | if length == 0 then ["main"] else . end)
                 end)
             )
           else . end) |
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
    subscriptionStateIdValid "${id}" && [[ "${id}" != "main" ]] || return 1
    subscriptionActiveGroupSetById sources "${id}" "remote subscription source not found" \
        --arg host "${host}" --argjson port "${port}" --arg token "${token}" \
        '.transport = "wireguard" | .scheme = "wireguard" | .host = $host | .port = $port | .control_token = $token'
}

setSubscriptionSourceEnabled() {
    local id=$1
    local enabled=$2
    subscriptionStateIdValid "${id}" || return 1
    [[ "${enabled}" == "true" || "${enabled}" == "false" ]] || return 1
    [[ "${id}" != "main" ]] || return 1
    subscriptionActiveGroupSetById sources "${id}" "remote subscription source not found" \
        --argjson enabled "${enabled}" '.enabled = $enabled'
}

setSubscriptionSourceSyncStatus() {
    local id=$1
    local status=$2
    local changed=${3:-}
    local plan=${4:-}
    subscriptionStateIdValid "${id}" || return 1
    if [[ -n "${plan}" ]]; then
        subscriptionActiveGroupSetById sources "${id}" "subscription source not found" \
            --arg status "${status}" --argjson changed "${changed}" --argjson plan "${plan}" \
            '.sync_status = $status | .last_sync_changed = $changed | .last_sync_plan = $plan | del(.last_sync_error)'
    elif [[ -n "${changed}" ]]; then
        subscriptionActiveGroupSetById sources "${id}" "subscription source not found" \
            --arg status "${status}" --argjson changed "${changed}" \
            '.sync_status = $status | .last_sync_changed = $changed | del(.last_sync_error)'
    else
        subscriptionActiveGroupSetById sources "${id}" "subscription source not found" \
            --arg status "${status}" '.sync_status = $status'
    fi
}

setSubscriptionSourceSyncFailure() {
    local id=$1
    local errorType=$2
    local errorMessage=$3
    subscriptionStateIdValid "${id}" || return 1
    subscriptionActiveGroupSetById sources "${id}" "subscription source not found" \
        --arg errorType "${errorType}" --arg errorMessage "${errorMessage}" \
        '.sync_status = "failed" | .last_sync_changed = false | .last_sync_error = {type:$errorType, message:$errorMessage} | del(.last_sync_plan)'
}

subscriptionSourceExists() {
    local id=$1
    subscriptionStateIdValid "${id}" || return 1
    subscriptionActiveGroupRead -e --arg id "${id}" 'any(.sources[]?; .id == $id)' >/dev/null 2>&1
}

subscriptionSourceIsMain() {
    local id=$1
    subscriptionStateIdValid "${id}" || return 1
    subscriptionActiveGroupRead -e --arg id "${id}" 'any(.sources[]?; .id == $id and .role == "main")' >/dev/null 2>&1
}

subscriptionHasEnabledRemoteSources() {
    subscriptionActiveGroupRead -e 'any(.sources[]?; .role != "main" and .enabled == true)' >/dev/null 2>&1
}
