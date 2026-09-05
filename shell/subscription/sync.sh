#!/usr/bin/env bash

subscriptionSyncAccountEscapeId() {
    local id=$1
    local escaped=${id//_/$'\001'}
    escaped=${escaped//-/_}
    escaped=${escaped//$'\001'/-}
    printf '%s\n' "${escaped}"
}

subscriptionSyncAccountUnescapeId() {
    local escaped=$1
    local id=${escaped//-/$'\001'}
    id=${id//_/-}
    id=${id//$'\001'/_}
    printf '%s\n' "${id}"
}

SUBSCRIPTION_SYNC_MANAGED_ACCOUNT_JQ='((.email // .name // .username // "") | sub("-('"$(clientNameSuffixRegex)"')$"; ""))'
SUBSCRIPTION_SYNC_ACCOUNT_NAME_FROM_ID_JQ='"sub_" + (((. | tostring) | gsub("_"; "\u0001") | gsub("-"; "_") | gsub("\u0001"; "-")))'

subscriptionSyncAccountName() {
    local id=$1
    echo "sub_$(subscriptionSyncAccountEscapeId "${id}")"
}

subscriptionSyncAccountIdFromName() {
    local accountName=$1
    local prefix="sub_"
    local escapedId
    [[ "${accountName}" == "${prefix}"* ]] || return 1
    escapedId=${accountName#"${prefix}"}
    subscriptionSyncAccountUnescapeId "${escapedId}"
}

subscriptionSyncFindUserByAccountName() {
    local accountName=$1
    local enabledUsers
    enabledUsers=$(subscriptionActiveEnabledUsersJson) || return 1
    jq -ce --arg account "${accountName}" '[.[]? | select(.account == $account)][0] // empty' <<<"${enabledUsers}"
}

subscriptionSyncGenerateUUID() {
    if [[ "${coreInstallType}" == "1" && -x "${ctlPath}" ]]; then
        ${ctlPath} uuid
    elif [[ "${coreInstallType}" == "2" && -x "${ctlPath}" ]]; then
        ${ctlPath} generate uuid
    else
        generateRandomUuidValue
    fi
}

subscriptionSyncUUIDIsValid() {
    validUuidValue "$1"
}

subscriptionSyncEnsureEnabledUserUUIDs() {
    local id
    local uuid
    local -a generatedArgs=()
    local missingIds
    missingIds=$(subscriptionActiveGroupRead -r '
      .user_groups[]?
      | select(.enabled == true)
      | select(((.uuid // "") | type) != "string" or ((.uuid // "") | test("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$") | not))
      | .id
    ') || return 1
    while IFS= read -r id; do
        [[ -n "${id}" ]] || continue
        uuid=$(subscriptionSyncGenerateUUID) || return 1
        subscriptionSyncUUIDIsValid "${uuid}" || return 1
        generatedArgs+=("${id}" "${uuid}")
    done <<<"${missingIds}"
    if ((${#generatedArgs[@]} > 0)); then
        local generated
        generated=$(jq -cn --args '
          [range(0; ($ARGS.positional | length) / 2) as $i
           | {id:$ARGS.positional[$i * 2], uuid:$ARGS.positional[$i * 2 + 1]}]
        ' -- "${generatedArgs[@]}") || return 1
        subscriptionApplyUserGroupState "${generated}" '[]' || return 1
    fi
}

subscriptionSyncLoadValidConfigFiles() {
    local resultVar=$1
    shift
    local -n resultRef=${resultVar}
    local file
    local discoveredFiles
    resultRef=()
    if (($# > 0)); then
        for file; do [[ -f "${file}" ]] && resultRef+=("${file}"); done
    else
        discoveredFiles=$(subscriptionSyncConfigFiles) || return 1
        [[ -n "${discoveredFiles}" ]] || return 0
        while IFS= read -r file; do
            [[ -f "${file}" ]] && resultRef+=("${file}")
        done <<<"${discoveredFiles}"
    fi
    return 0
}

subscriptionSyncConfiguredAccountNamesJson() {
    local -a validFiles=()
    subscriptionSyncLoadValidConfigFiles validFiles "$@" || return 1
    [[ "${#validFiles[@]}" -gt 0 ]] || {
        printf '[]\n'
        return 0
    }
    jq -c -s '
      [.[] | [(.inbounds[]?.settings.clients[]?), (.inbounds[]?.users[]?)][]
       | '"${SUBSCRIPTION_SYNC_MANAGED_ACCOUNT_JQ}"'
       | select(length > 0)]
      | unique' "${validFiles[@]}"
}

subscriptionSyncConfiguredManagedUsers() {
    local accountsJson
    accountsJson=$(subscriptionSyncConfiguredAccountNamesJson "$@") || return 1
    jq -c '[.[]? | select(startswith("sub_"))] | unique' <<<"${accountsJson}"
}

subscriptionSyncConfiguredManagedCredentials() {
    local -a validFiles=()
    subscriptionSyncLoadValidConfigFiles validFiles "$@" || return 1
    [[ "${#validFiles[@]}" -gt 0 ]] || {
        printf '[]\n'
        return 0
    }
    jq -c -s '
      [.[] | [(.inbounds[]?.settings.clients[]?), (.inbounds[]?.users[]?)][]
       | {
           account: ('"${SUBSCRIPTION_SYNC_MANAGED_ACCOUNT_JQ}"'),
           credential: ((.id // .uuid // .password // "") | tostring)
         }
       | select(.account | startswith("sub_"))]
      | sort_by(.account)
      | group_by(.account)
      | map({
          account: .[0].account,
          uuids: ([.[].credential | select(test("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"))] | unique)
        })' "${validFiles[@]}"
}

subscriptionSyncCurrentManagedUsers() {
    subscriptionSyncConfiguredManagedUsers "$@"
}

subscriptionSyncResolveManagedConfigDir() {
    local rawPath=${1%/}
    local resolvedPath=

    [[ -n "${rawPath}" ]] || return 1
    if [[ "${rawPath}" == /* ]]; then
        padmIsSafeAbsolutePath "${rawPath}" || return 1
        resolvedPath="${rawPath}"
    else
        if [[ "${rawPath}" == "." || "${rawPath}" == ".." ||
            "${rawPath}" == */./* || "${rawPath}" == */. ||
            "${rawPath}" == */../* || "${rawPath}" == */.. ]]; then
            return 1
        fi
        resolvedPath=$(padmResolveCleanupPath "${rawPath}" 2>/dev/null || true)
        [[ -n "${resolvedPath}" ]] || return 1
        padmIsSafeAbsolutePath "${resolvedPath}" || return 1
    fi
    printf '%s/\n' "${resolvedPath%/}"
}

subscriptionSyncSafeConfigDir() {
    [[ -n "${configPath:-}" ]] || return 1
    subscriptionSyncResolveManagedConfigDir "${configPath}"
}

subscriptionSyncSafeSingBoxConfigDir() {
    [[ -n "${singBoxConfigPath:-}" ]] || return 1
    subscriptionSyncResolveManagedConfigDir "${singBoxConfigPath}"
}

subscriptionSyncRequireSafeConfigDirs() {
    subscriptionSyncSafeConfigDir >/dev/null || return 1
    if [[ -n "${singBoxConfigPath:-}" ]]; then
        subscriptionSyncSafeSingBoxConfigDir >/dev/null || return 1
    fi
}

subscriptionSyncManagedConfigTargetFile() {
    local targetFile=$1
    local targetDir
    local targetName
    local xrayConfigDir
    local singBoxConfigDir=

    padmIsSafeAbsolutePath "${targetFile}" || return 1
    targetDir="$(dirname -- "${targetFile}")/"
    targetName=$(basename -- "${targetFile}")
    [[ "${targetName}" == *inbounds.json ]] || return 1

    xrayConfigDir=$(subscriptionSyncSafeConfigDir) || return 1
    if [[ "${targetDir}" == "${xrayConfigDir}" ]]; then
        return 0
    fi

    if [[ -n "${singBoxConfigPath:-}" ]]; then
        singBoxConfigDir=$(subscriptionSyncSafeSingBoxConfigDir) || return 1
        [[ "${targetDir}" == "${singBoxConfigDir}" ]]
        return
    fi
    return 1
}

subscriptionSyncConfigFiles() {
    local file
    local xrayConfigDir
    local singBoxConfigDir=

    xrayConfigDir=$(subscriptionSyncSafeConfigDir) || return 1
    for file in "${xrayConfigDir}"*inbounds.json; do
        [[ -f "${file}" ]] && echo "${file}"
    done
    if [[ -n "${singBoxConfigPath:-}" ]]; then
        singBoxConfigDir=$(subscriptionSyncSafeSingBoxConfigDir) || return 1
        if [[ "${singBoxConfigDir}" == "${xrayConfigDir}" ]]; then
            return 0
        fi
        for file in "${singBoxConfigDir}"*inbounds.json; do
            [[ -f "${file}" ]] && echo "${file}"
        done
    fi
    return 0
}

subscriptionSyncAccountNamesJsonFromIds() {
    jq -R -s '
      split("\n")
      | map(select(length > 0))
      | map(
          . as $id
          | ($id | '"${SUBSCRIPTION_SYNC_ACCOUNT_NAME_FROM_ID_JQ}"')
        )
      | unique
    '
}

subscriptionSyncAccountPlanFromIds() {
    local mode=$1
    local currentAccounts=${2-}
    local desiredAccountsJson

    desiredAccountsJson=$(subscriptionSyncAccountNamesJsonFromIds) || return 1
    case "${mode}" in
    sync)
        subscriptionSyncPlanFromAccounts "${desiredAccountsJson}" "${currentAccounts}"
        ;;
    remove)
        jq -n --argjson remove "${desiredAccountsJson}" '{create:[], remove:$remove}'
        ;;
    *)
        return 1
        ;;
    esac
}

subscriptionSyncPlanFromAccounts() {
    local desiredAccountsJson=$1
    local currentAccounts=${2-}
    subscriptionSyncRequireSafeConfigDirs || return 1
    if [[ -z "${currentAccounts}" ]]; then
        currentAccounts=$(subscriptionSyncCurrentManagedUsers) || return 1
    fi
    jq -n \
      --argjson desired "${desiredAccountsJson}" \
      --argjson current "${currentAccounts}" \
      '{create: ($desired - $current), remove: ($current - $desired)}'
}

subscriptionSyncCredentialMismatchAccounts() {
    local desiredUsers=$1
    local currentCredentials=${2-}
    if [[ -z "${currentCredentials}" ]]; then
        currentCredentials=$(subscriptionSyncConfiguredManagedCredentials) || return 1
    fi
    jq -c -n \
      --argjson desiredUsers "${desiredUsers}" \
      --argjson currentCredentials "${currentCredentials}" '
      [$desiredUsers[]?
       | . as $user
       | ($user.id | '"${SUBSCRIPTION_SYNC_ACCOUNT_NAME_FROM_ID_JQ}"') as $account
       | select(any($currentCredentials[]?; .account == $account))
       | ([$currentCredentials[]? | select(.account == $account) | .uuids[]?] | unique) as $currentUuids
       | select($currentUuids != [$user.uuid])
       | $account]
      | unique'
}

subscriptionSyncPlanFromDesiredUsers() {
    local desiredUsers=$1
    local desiredIds
    local currentCredentials
    local currentAccounts
    local plan
    local credentialUpdates
    desiredIds=$(jq -r '.[].id' <<<"${desiredUsers}") || return 1
    currentCredentials=$(subscriptionSyncConfiguredManagedCredentials) || return 1
    currentAccounts=$(jq -c '[.[].account] | unique' <<<"${currentCredentials}") || return 1
    plan=$(subscriptionSyncAccountPlanFromIds sync "${currentAccounts}" <<<"${desiredIds}") || return 1
    subscriptionSyncValidateAccountPlan "${plan}" || return 1
    credentialUpdates=$(subscriptionSyncCredentialMismatchAccounts "${desiredUsers}" "${currentCredentials}") || return 1
    jq -c -n --argjson plan "${plan}" --argjson updates "${credentialUpdates}" '
      $plan
      | .create = ((.create + $updates) | unique)
      | .remove = ((.remove + $updates) | unique)'
}

subscriptionSyncPlan() {
    local enabledUsers
    local desiredUsers
    local plan
    enabledUsers=$(subscriptionActiveEnabledUsersJson) || return 1
    desiredUsers=$(jq -c '[.[]? | select((.allows_main // false) == true) | {id, uuid}]' <<<"${enabledUsers}") || return 1
    plan=$(subscriptionSyncPlanFromDesiredUsers "${desiredUsers}") || return 1
    printf '%s\n' "${plan}"
}

subscriptionSyncRemoveAccountFromFile() {
    local file=$1
    local accountName=$2
    local tmpFile
    local jqStatus
    [[ -f "${file}" ]] || return 0
    if jq -e --arg accountName "${accountName}" '
      any(
        [(.inbounds[]?.settings.clients[]?), (.inbounds[]?.users[]?)][]?;
        ('"${SUBSCRIPTION_SYNC_MANAGED_ACCOUNT_JQ}"') == $accountName
      )' "${file}" >/dev/null 2>&1; then
        :
    else
        jqStatus=$?
        [[ "${jqStatus}" -eq 1 ]] && return 0
        return 1
    fi
    padmCreateTempFileForTarget tmpFile "${file}" sync || return 1
    if ! jq --arg accountName "${accountName}" '
      (.inbounds[]?.settings.clients? // empty) |= map(select(('"${SUBSCRIPTION_SYNC_MANAGED_ACCOUNT_JQ}"') != $accountName)) |
      (.inbounds[]?.users? // empty) |= map(select(('"${SUBSCRIPTION_SYNC_MANAGED_ACCOUNT_JQ}"') != $accountName))' "${file}" >"${tmpFile}"; then
        padmRemoveCleanupPath "${tmpFile}"
        return 1
    fi
    commitGeneratedJsonFile "${tmpFile}" "${file}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

subscriptionSyncRemoveAccount() {
    local accountName=$1
    local file
    local rc=0
    local -a configFiles=()
    subscriptionSyncRequireSafeConfigDirs || return 1
    subscriptionSyncLoadValidConfigFiles configFiles || return 1
    for file in "${configFiles[@]}"; do
        if ! subscriptionSyncRemoveAccountFromFile "${file}" "${accountName}"; then
            rc=1
        fi
    done
    return "${rc}"
}

subscriptionSyncSetUsersInFile() {
    local file=$1
    local userPath=$2
    local users=$3
    local tmpFile
    [[ -f "${file}" ]] || return 0
    padmCreateTempFileForTarget tmpFile "${file}" sync || return 1
    if ! jq --argjson users "${users}" "${userPath} = \$users" "${file}" >"${tmpFile}"; then
        padmRemoveCleanupPath "${tmpFile}"
        return 1
    fi
    commitGeneratedJsonFile "${tmpFile}" "${file}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

subscriptionSyncAppendProtocolUser() {
    local protocolId=$1
    local file=$2
    local preferredPath=$3
    local uuid=$4
    local accountName=$5
    local clients=
    local userPath=
    # init*Clients reads this dynamically scoped value to preserve existing clients.
    local currentClients='[]'
    [[ -f "${file}" ]] || return 0
    if [[ -n "${preferredPath}" ]]; then
        userPath="${preferredPath}"
    else
        userPath=$(jq -r '
          if .inbounds[1].settings.clients then ".inbounds[1].settings.clients"
          elif .inbounds[0].settings.clients then ".inbounds[0].settings.clients"
          else ".inbounds[0].users"
          end
        ' "${file}") || return 1
    fi
    currentClients=$(jq -c --arg accountName "${accountName}" "${userPath} // [] | if any(.[]?; (${SUBSCRIPTION_SYNC_MANAGED_ACCOUNT_JQ}) == \$accountName) then null else . end" "${file}") || return 1
    if [[ "${currentClients}" == "null" ]]; then
        return 0
    fi
    if [[ "${coreInstallType}" == "2" ]]; then
        clients=$(initSingBoxClients "${protocolId}" "${uuid}" "${accountName}") || return 1
    else
        clients=$(initXrayClients "${protocolId}" "${uuid}" "${accountName}") || return 1
    fi
    subscriptionSyncSetUsersInFile "${file}" "${userPath}" "${clients}"
}

subscriptionSyncAppendProtocolBatch() {
    local configDir=$1
    local uuid=$2
    local accountName=$3
    local mode=$4
    local protocolId
    local fileName
    local registry
    local rc=0

    case "${mode}" in
    xray)
        registry=$(protocolCapabilityRegistry) || return 1
        registry=$(awk -F'|' '$3 == "node" && ("," $6 ",") ~ ",xray," && $19 != "" { print $1 "\t" $19 }' <<<"${registry}") || return 1
        ;;
    singbox)
        registry=$(protocolCapabilityRegistry) || return 1
        registry=$(awk -F'|' '$3 == "node" && ("," $6 ",") ~ ",sing-box," && $19 != "" { print $1 "\t" $19 }' <<<"${registry}") || return 1
        ;;
    *)
        return 1
        ;;
    esac
    while IFS=$'\t' read -r protocolId fileName; do
        [[ -n "${protocolId}" && -n "${fileName}" ]] || continue
        subscriptionSyncAppendProtocolUser "${protocolId}" "${configDir}${fileName}" '' "${uuid}" "${accountName}" || rc=1
    done <<<"${registry}"
    return "${rc}"
}

subscriptionSyncAppendLocalUser() {
    local id=$1
    local accountName
    local uuid
    local xrayConfigDir
    local singBoxConfigDir=
    local rc=0
    accountName=$(subscriptionSyncAccountName "${id}")
    uuid=$(subscriptionActiveGroupRead -r --arg id "${id}" '.user_groups[]? | select(.id == $id) | .uuid // empty') || return 1
    if [[ -z "${uuid}" ]]; then
        uuid=$(subscriptionSyncGenerateUUID) || return 1
        subscriptionSyncUUIDIsValid "${uuid}" || return 1
        subscriptionApplyUserGroupState "$(jq -cn --arg id "${id}" --arg uuid "${uuid}" '[{id:$id,uuid:$uuid}]')" '[]' || return 1
    fi
    subscriptionSyncUUIDIsValid "${uuid}" || return 1

    xrayConfigDir=$(subscriptionSyncSafeConfigDir) || return 1
    if [[ -n "${singBoxConfigPath:-}" ]]; then
        singBoxConfigDir=$(subscriptionSyncSafeSingBoxConfigDir) || return 1
    fi

    subscriptionSyncAppendProtocolBatch "${xrayConfigDir}" "${uuid}" "${accountName}" xray || rc=1
    if [[ -n "${singBoxConfigDir}" && "${singBoxConfigDir}" != "${xrayConfigDir}" ]]; then
        subscriptionSyncAppendProtocolBatch "${singBoxConfigDir}" "${uuid}" "${accountName}" singbox || rc=1
    fi
    return "${rc}"
}

subscriptionSyncValidateAccountPlan() {
    local syncPlan=$1
    jq -e '
      type == "object" and
      (.create | type == "array") and
      (.remove | type == "array") and
      all(.create[]?; type == "string" and length > 0) and
      all(.remove[]?; type == "string" and length > 0)
    ' <<<"${syncPlan}" >/dev/null 2>&1
}

subscriptionSyncApplyAccountPlan() {
    local syncPlan=$1
    local accountName
    local accountId
    local createAccounts
    local removeAccounts
    local rc=0
    subscriptionSyncValidateAccountPlan "${syncPlan}" || return 1
    removeAccounts=$(jq -r '.remove[]' <<<"${syncPlan}") || return 1
    createAccounts=$(jq -r '.create[]' <<<"${syncPlan}") || return 1
    while IFS= read -r accountName; do
        [[ -n "${accountName}" ]] || continue
        if ! subscriptionSyncRemoveAccount "${accountName}"; then
            rc=1
        fi
    done <<<"${removeAccounts}"

    while IFS= read -r accountName; do
        [[ -n "${accountName}" ]] || continue
        if ! accountId=$(subscriptionSyncAccountIdFromName "${accountName}"); then
            rc=1
            continue
        fi
        if ! subscriptionSyncAppendLocalUser "${accountId}"; then
            rc=1
        fi
    done <<<"${createAccounts}"
    return "${rc}"
}

subscriptionSyncRestoreConfigBackups() {
    local backupDir=$1
    subscriptionSyncRequireSafeConfigDirs || return 1
    padmRestoreManagedFileBackupManifest "${backupDir}" subscriptionSyncManagedConfigTargetFile
}

subscriptionSyncCreateConfigBackups() {
    local resultVar=$1
    local createdBackupDir
    local file
    local backupIndex=0
    local -a backupArgs=()
    local -a configFiles=()

    subscriptionSyncRequireSafeConfigDirs || return 1
    subscriptionSyncLoadValidConfigFiles configFiles || return 1
    padmCreateTmpRootPath createdBackupDir padm-subscription-sync-backup.XXXXXX -d || return 1
    for file in "${configFiles[@]}"; do
        backupArgs+=("$(printf '%06d.json' "${backupIndex}")" "${file}")
        backupIndex=$((backupIndex + 1))
    done
    if ! padmWriteManagedFileBackupManifest "${createdBackupDir}" "${backupArgs[@]}"; then
        padmRemoveCleanupPath "${createdBackupDir}"
        return 1
    fi
    printf -v "${resultVar}" '%s' "${createdBackupDir}"
}

subscriptionSyncBackupPath() {
    local sourcePath=$1
    local backupDir=$2
    local label=$3
    local targetBackup="${backupDir}/${label}"
    local marker="${backupDir}/${label}.exists"

    padmIsSafeAbsolutePath "${sourcePath}" || return 1
    if [[ -d "${sourcePath}" ]]; then
        printf 'dir\n' >"${marker}" || return 1
        mkdir -p "${targetBackup}" || return 1
        cp -a "${sourcePath}/." "${targetBackup}/" || return 1
    elif [[ -f "${sourcePath}" ]]; then
        printf 'file\n' >"${marker}" || return 1
        cp -p "${sourcePath}" "${targetBackup}" || return 1
    else
        printf 'missing\n' >"${marker}" || return 1
    fi
}

subscriptionSyncRestoreMissingOutputPath() {
    local targetPath=$1
    local label=$2

    case "${label}" in
    local)
        rm -rf -- "${targetPath}/default" "${targetPath}/clashMeta" "${targetPath}/sing-box" || return 1
        rm -f -- "${targetPath}/subscribeSalt" || return 1
        ;;
    public)
        rm -rf -- \
            "${targetPath}/default" \
            "${targetPath}/clashMeta" \
            "${targetPath}/clashMetaProfiles" \
            "${targetPath}/sing-box" \
            "${targetPath}/sing-box_profiles" || return 1
        ;;
    *)
        return 1
        ;;
    esac

    rmdir -- "${targetPath}" >/dev/null 2>&1 || true
}

subscriptionSyncRestoreBackupPath() {
    local targetPath=$1
    local backupDir=$2
    local label=$3
    local targetBackup="${backupDir}/${label}"
    local marker="${backupDir}/${label}.exists"
    local state
    local restoreStage
    local targetParent
    local rollbackDir
    local rollbackPath

    padmIsSafeAbsolutePath "${targetPath}" || return 1
    [[ -f "${marker}" ]] || return 1
    state=$(<"${marker}")
    case "${state}" in
    dir)
        targetParent=$(dirname "${targetPath}")
        mkdir -p "${targetParent}" || return 1
        padmCreateTempPath restoreStage -d "${targetParent%/}/.restore-${label}.XXXXXX" || return 1
        if ! cp -a "${targetBackup}/." "${restoreStage}/"; then
            padmRemoveCleanupPath "${restoreStage}"
            return 1
        fi
        if [[ -e "${targetPath}" ]]; then
            padmCreateTempPath rollbackDir -d "${targetParent%/}/.restore-old-${label}.XXXXXX" || {
                padmRemoveCleanupPath "${restoreStage}"
                return 1
            }
            rollbackPath="${rollbackDir}/$(basename "${targetPath}")"
            if ! mv "${targetPath}" "${rollbackPath}"; then
                padmRemoveCleanupPath "${restoreStage}"
                padmRemoveCleanupPath "${rollbackDir}"
                return 1
            fi
            if mv "${restoreStage}" "${targetPath}"; then
                padmForgetCleanupPath "${restoreStage}"
                padmRemoveCleanupPath "${rollbackDir}"
                return 0
            fi
            if ! mv "${rollbackPath}" "${targetPath}" >/dev/null 2>&1; then
                padmRemoveCleanupPath "${restoreStage}"
                padmForgetCleanupPath "${rollbackDir}"
                return 1
            fi
            padmRemoveCleanupPath "${restoreStage}"
            padmRemoveCleanupPath "${rollbackDir}"
            return 1
        fi
        mv "${restoreStage}" "${targetPath}" || { padmRemoveCleanupPath "${restoreStage}"; return 1; }
        padmForgetCleanupPath "${restoreStage}"
        return 0
        ;;
    file)
        targetParent=$(dirname "${targetPath}")
        mkdir -p "${targetParent}" || return 1
        padmCreateTempFileForTarget restoreStage "${targetPath}" restore || return 1
        if ! cp -p "${targetBackup}" "${restoreStage}"; then
            padmRemoveCleanupPath "${restoreStage}"
            return 1
        fi
        commitGeneratedFile "${restoreStage}" "${targetPath}" || { padmRemoveCleanupPath "${restoreStage}"; return 1; }
        ;;
    missing)
        subscriptionSyncRestoreMissingOutputPath "${targetPath}" "${label}" || return 1
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}

subscriptionSyncCreateSubscribeOutputBackups() {
    local resultVar=$1
    local createdBackupDir
    local localBase
    local publicBase

    padmCreateTmpRootPath createdBackupDir padm-subscription-output-backup.XXXXXX -d || return 1
    localBase=$(subscribeLocalBaseDir)
    publicBase=$(subscribePublicBaseDir)
    subscriptionSyncBackupPath "${localBase}" "${createdBackupDir}" local || { padmRemoveCleanupPath "${createdBackupDir}"; return 1; }
    subscriptionSyncBackupPath "${publicBase}" "${createdBackupDir}" public || { padmRemoveCleanupPath "${createdBackupDir}"; return 1; }
    printf -v "${resultVar}" '%s' "${createdBackupDir}"
}

subscriptionSyncCreateLocalApplyBackups() {
    local configVar=$1
    local outputVar=$2
    local groupsVar=${3:-}
    local createdConfigBackupDir=
    local createdOutputBackupDir=
    local createdGroupsBackupFile=

    SUBSCRIPTION_SYNC_LOCAL_APPLY_BACKUP_STAGE=
    if [[ -n "${groupsVar}" ]]; then
        createdGroupsBackupFile=$(createSubscriptionGroupsBackup) || return 1
        SUBSCRIPTION_SYNC_LOCAL_APPLY_BACKUP_STAGE=groups
    fi
    subscriptionSyncCreateConfigBackups createdConfigBackupDir || {
        [[ -n "${createdGroupsBackupFile}" ]] && padmRemoveCleanupPath "${createdGroupsBackupFile}"
        return 1
    }
    SUBSCRIPTION_SYNC_LOCAL_APPLY_BACKUP_STAGE=config
    subscriptionSyncCreateSubscribeOutputBackups createdOutputBackupDir || {
        padmRemoveCleanupPath "${createdConfigBackupDir}"
        [[ -n "${createdGroupsBackupFile}" ]] && padmRemoveCleanupPath "${createdGroupsBackupFile}"
        return 1
    }
    SUBSCRIPTION_SYNC_LOCAL_APPLY_BACKUP_STAGE=ready
    printf -v "${configVar}" '%s' "${createdConfigBackupDir}"
    printf -v "${outputVar}" '%s' "${createdOutputBackupDir}"
    if [[ -n "${groupsVar}" ]]; then
        printf -v "${groupsVar}" '%s' "${createdGroupsBackupFile}"
    fi
    return 0
}

subscriptionSyncReleaseLocalApplyBackups() {
    local mode=$1
    local configBackupDir=${2:-}
    local outputBackupDir=${3:-}
    local groupsBackupFile=${4:-}

    case "${mode}" in
    remove)
        if [[ -n "${configBackupDir}" ]]; then padmRemoveCleanupPath "${configBackupDir}"; fi
        if [[ -n "${outputBackupDir}" ]]; then padmRemoveCleanupPath "${outputBackupDir}"; fi
        if [[ -n "${groupsBackupFile}" ]]; then padmRemoveCleanupPath "${groupsBackupFile}"; fi
        ;;
    forget)
        if [[ -n "${configBackupDir}" ]]; then padmForgetCleanupPath "${configBackupDir}"; fi
        if [[ -n "${outputBackupDir}" ]]; then padmForgetCleanupPath "${outputBackupDir}"; fi
        if [[ -n "${groupsBackupFile}" ]]; then padmForgetCleanupPath "${groupsBackupFile}"; fi
        ;;
    *)
        return 1
        ;;
    esac
    return 0
}

subscriptionSyncRestoreSubscribeOutputBackups() {
    local backupDir=$1
    local localBase
    local publicBase

    localBase=$(subscribeLocalBaseDir)
    publicBase=$(subscribePublicBaseDir)
    subscriptionSyncRestoreBackupPath "${localBase}" "${backupDir}" local || return 1
    subscriptionSyncRestoreBackupPath "${publicBase}" "${backupDir}" public || return 1
}

subscriptionSyncRollbackLocalApply() {
    local configBackupDir=$1
    local outputBackupDir=$2
    local reason=$3
    local groupsBackupFile=${4:-}
    local configRestored=true
    local outputRestored=true
    local groupsRestored=true
    local restoreStatus=0
    local groupsRestoreMessage=

    SUBSCRIPTION_SYNC_TRANSACTION_ERROR=
    SUBSCRIPTION_SYNC_CONFIG_RESTORED=false
    if ! subscriptionSyncRestoreConfigBackups "${configBackupDir}" >/dev/null 2>&1; then
        configRestored=false
    else
        SUBSCRIPTION_SYNC_CONFIG_RESTORED=true
    fi
    if ! subscriptionSyncRestoreSubscribeOutputBackups "${outputBackupDir}" >/dev/null 2>&1; then
        outputRestored=false
    fi
    if [[ -n "${groupsBackupFile}" ]] && ! restoreSubscriptionGroupsBackup "${groupsBackupFile}" >/dev/null 2>&1; then
        groupsRestored=false
    fi

    subscriptionSyncSetRestorePairFailureMessage \
        SUBSCRIPTION_SYNC_TRANSACTION_ERROR \
        "${reason}" \
        "${configRestored}" "配置" "备份目录: ${configBackupDir}" \
        "${outputRestored}" "订阅输出" "备份目录: ${outputBackupDir}" \
        "备份目录: ${configBackupDir} 和 ${outputBackupDir}" || restoreStatus=1
    if [[ "${groupsRestored}" != "true" ]]; then
        subscriptionSyncSetManualCheckMessage groupsRestoreMessage "订阅状态恢复失败" " ${groupsBackupFile}"
        if [[ -n "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR}" ]]; then
            SUBSCRIPTION_SYNC_TRANSACTION_ERROR="${SUBSCRIPTION_SYNC_TRANSACTION_ERROR}；${groupsRestoreMessage}"
        else
            SUBSCRIPTION_SYNC_TRANSACTION_ERROR="${reason}，且${groupsRestoreMessage}"
        fi
        restoreStatus=1
    fi
    return "${restoreStatus}"
}

subscriptionSyncSetRestorePairFailureMessage() {
    local outputVar=$1
    local reason=$2
    local firstRestored=$3
    local firstLabel=$4
    local firstLocation=$5
    local secondRestored=$6
    local secondLabel=$7
    local secondLocation=$8
    local combinedLocation=$9
    local result=

    if [[ "${firstRestored}" == "true" && "${secondRestored}" == "true" ]]; then
        printf -v "${outputVar}" '%s' ''
        return 0
    fi

    if [[ "${firstRestored}" != "true" && "${secondRestored}" != "true" ]]; then
        subscriptionSyncSetManualCheckMessage result "${firstLabel}与${secondLabel}恢复失败" "${combinedLocation}"
    elif [[ "${firstRestored}" != "true" ]]; then
        subscriptionSyncSetManualCheckMessage result "${firstLabel}恢复失败" "${firstLocation}"
    else
        subscriptionSyncSetManualCheckMessage result "${secondLabel}恢复失败" "${secondLocation}"
    fi

    result="${reason}，且${result}"
    printf -v "${outputVar}" '%s' "${result}"
    return 1
}

subscriptionSyncAppendRestoreFailureDetail() {
    local outputVar=$1
    local prefix=$2
    local detail=$3
    local result=${!outputVar:-}

    if [[ -n "${result}" ]]; then
        result="${result}；${detail}"
    else
        result="${prefix}${detail}"
    fi

    printf -v "${outputVar}" '%s' "${result}"
}

subscriptionSyncSetRestoreFailureDetail() {
    local outputVar=$1
    local failedLabel=$2
    local failedLocation=${3:-}
    if [[ -n "${failedLocation}" ]]; then
        coreSetRestoreFailureDetail "${outputVar}" "${failedLabel}" "${failedLocation}"
        return 0
    fi
    printf -v "${outputVar}" '%s' "${failedLabel}恢复失败"
}

subscriptionSyncSetManualCheckMessage() {
    coreSetManualCheckMessage "$@"
}

subscriptionSyncSetSingleRestoreResultMessage() {
    local outputVar=$1
    local reason=$2
    local restored=$3
    local restoredMessage=$4
    local failedLabel=$5
    local failedLocation=$6
    local includeManualCheck=${7:-true}
    if [[ "${restored}" == "true" && -z "${restoredMessage}" ]]; then
        printf -v "${outputVar}" '%s' "${reason}"
        return 0
    fi

    if [[ "${includeManualCheck}" == "false" ]]; then
        printf -v "${outputVar}" '%s' "${reason}，且${failedLabel}恢复失败"
        return 1
    fi

    coreSetSingleRestoreResultMessage \
        "${outputVar}" \
        "${reason}" \
        "${restored}" \
        "${restoredMessage}" \
        "${failedLabel}" \
        "${failedLocation}"
}

subscriptionSyncSetRollbackResultMessage() {
    coreSetRollbackResultMessage "$@"
}

subscriptionSyncSetRollbackRetryMessage() {
    local outputVar=$1
    local reason=$2
    local retryFn=$3
    local retryFailureMessage=$4

    subscriptionSyncSetRollbackResultMessage \
        "${outputVar}" \
        "${reason}" \
        "已恢复旧配置" \
        "${retryFn}" \
        "${retryFailureMessage}" \
        "${@:5}"
}

subscriptionSyncRetryPartiallyRestoredConfig() {
    local outputVar=$1
    local configRestored=$2
    local retryFn=$3
    local retryFailureMessage=$4
    shift 4

    [[ "${configRestored}" == "true" ]] || return 0
    if "${retryFn}" "$@"; then
        return 0
    fi
    subscriptionSyncAppendRestoreFailureDetail "${outputVar}" "" "${retryFailureMessage}"
    return 1
}

subscriptionSyncApplyAccountPlanTransaction() {
    local syncPlan=$1
    local reloadFn=${2:-}
    local backupDir
    local applyStatus=0
    SUBSCRIPTION_SYNC_TRANSACTION_ERROR=
    subscriptionSyncValidateAccountPlan "${syncPlan}" || return 1
    subscriptionSyncCreateConfigBackups backupDir || return 1
    if ! subscriptionSyncApplyAccountPlan "${syncPlan}"; then
        applyStatus=1
    fi
    if [[ "${applyStatus}" -ne 0 ]]; then
        if ! subscriptionSyncRestoreConfigBackups "${backupDir}" >/dev/null 2>&1; then
            subscriptionSyncSetSingleRestoreResultMessage \
                SUBSCRIPTION_SYNC_TRANSACTION_ERROR \
                "本机同步计划应用失败" \
                false \
                "" \
                "配置" \
                "备份目录: ${backupDir}"
            padmForgetCleanupPath "${backupDir}"
            return 1
        fi
        padmRemoveCleanupPath "${backupDir}"
        return 1
    fi
    if [[ -n "${reloadFn}" ]]; then
        if ! "${reloadFn}"; then
            if ! subscriptionSyncRestoreConfigBackups "${backupDir}" >/dev/null 2>&1; then
                subscriptionSyncSetSingleRestoreResultMessage \
                    SUBSCRIPTION_SYNC_TRANSACTION_ERROR \
                    "本机同步计划应用后核心重载失败" \
                    false \
                    "" \
                    "配置" \
                    "备份目录: ${backupDir}"
                padmForgetCleanupPath "${backupDir}"
                return 1
            fi
            subscriptionSyncSetRollbackRetryMessage SUBSCRIPTION_SYNC_TRANSACTION_ERROR "本机同步计划应用后核心重载失败" "${reloadFn}" "恢复旧配置后核心重载仍失败，请检查核心服务日志"
            padmRemoveCleanupPath "${backupDir}"
            return 1
        fi
    fi
    padmRemoveCleanupPath "${backupDir}"
}

subscriptionSyncReconcileLocalServices() {
    reloadCoreWithTrafficStatsConfig || return 1
}

subscriptionSyncMarkResult() {
    local status=$1
    local failures=$2
    local failureDetails=${3:-[]}
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')
    subscriptionActiveGroupWrite --arg now "${now}" --arg status "${status}" --argjson failures "${failures}" --argjson failureDetails "${failureDetails}" '.sync.last_run = $now | .sync.last_status = $status | .sync.failures = $failures | .sync.failure_details = $failureDetails'
}

subscriptionQuotaDryRunPlan() {
    local jqProgram
    jqProgram=$(printf '%s\n%s\n' "$(subscriptionTrafficTotalsJq)" '
      . as $group |
      [($group.user_groups[]? |
        (.traffic_limit_gb // 0 | tonumber? // 0) as $limitGb |
        (subscriptionTrafficTotal(($group.traffic.user_groups[.id] // {}).sources)) as $traffic |
        (($traffic.upload // 0) + ($traffic.download // 0)) as $usedBytes |
        (($limitGb * 1024 * 1024 * 1024) | floor) as $limitBytes |
        select((if has("enabled") then .enabled else true end) == true and $limitGb > 0 and $usedBytes >= $limitBytes) |
        {
          id: .id,
          name: .name,
          used_bytes: $usedBytes,
          limit_gb: $limitGb,
          percent: (($usedBytes * 100 / $limitBytes) | floor),
          action: "disable-and-remove-local-account"
         })]')
    subscriptionActiveGroupRead -r "${jqProgram}"
}

subscriptionQuotaValidatePlan() {
    local quotaPlan=$1
    jq -e '
      type == "array" and
      all(.[]?; type == "object" and
        (.id | type == "string" and length <= 64 and test("^[A-Za-z0-9_-]+$")) and
        .action == "disable-and-remove-local-account") and
      ([.[].id] | length) == ([.[].id] | unique | length)
    ' <<<"${quotaPlan}" >/dev/null 2>&1
}

subscriptionQuotaPlanIds() {
    local quotaPlan=$1
    subscriptionQuotaValidatePlan "${quotaPlan}" || return 1
    jq -r '.[].id // empty' <<<"${quotaPlan}"
}

applySubscriptionQuotaPlan() {
    local quotaPlan=$1
    local planIds
    planIds=$(subscriptionQuotaPlanIds "${quotaPlan}") || return 1
    [[ -n "${planIds}" ]] || return 0
    subscriptionActiveGroupWrite --argjson plan "${quotaPlan}" '
      ($plan | map(.id)) as $ids |
      if (($ids - [.user_groups[]?.id]) | length) > 0 then
        error("user subscription not found")
      else
        .user_groups |= map(.id as $id |
          if ($ids | index($id)) != null then .enabled = false else . end)
      end
    '
}

applySubscriptionQuotaPlanAccounts() {
    local quotaPlan=$1
    local accountPlan
    local planIds
    local rc=0
    planIds=$(subscriptionQuotaPlanIds "${quotaPlan}") || return 1
    accountPlan=$(subscriptionSyncAccountPlanFromIds remove <<<"${planIds}") || return 1
    if jq -e '.remove | length > 0' <<<"${accountPlan}" >/dev/null 2>&1; then
        if ! subscriptionSyncApplyAccountPlanTransaction "${accountPlan}" reloadCoreWithTrafficStatsConfig; then
            rc=1
        fi
    fi
    return "${rc}"
}

applySubscriptionQuotaPlanTransactionUnlocked() {
    local quotaPlan=$1
    local requestedIds
    local currentPlan
    local effectivePlan
    local backupFile
    local quotaError=

    SUBSCRIPTION_SYNC_TRANSACTION_ERROR=
    ensureSubscriptionGroupsState || return 1
    subscriptionQuotaValidatePlan "${quotaPlan}" || return 1
    requestedIds=$(jq -c '[.[].id]' <<<"${quotaPlan}") || return 1
    currentPlan=$(subscriptionQuotaDryRunPlan) || {
        SUBSCRIPTION_SYNC_TRANSACTION_ERROR="限额自动执行时重新检查超额状态失败"
        return 1
    }
    subscriptionQuotaValidatePlan "${currentPlan}" || {
        SUBSCRIPTION_SYNC_TRANSACTION_ERROR="限额自动执行时重新检查计划格式失败"
        return 1
    }
    effectivePlan=$(jq -c --argjson requestedIds "${requestedIds}" '
      [.[]? | .id as $id | select(($requestedIds | index($id)) != null)]
    ' <<<"${currentPlan}") || {
        SUBSCRIPTION_SYNC_TRANSACTION_ERROR="限额自动执行时重新检查计划格式失败"
        return 1
    }
    [[ "${effectivePlan}" != '[]' ]] || return 0

    backupFile=$(createSubscriptionGroupsBackup) || {
        SUBSCRIPTION_SYNC_TRANSACTION_ERROR="限额自动执行前订阅状态备份失败"
        return 1
    }
    if ! applySubscriptionQuotaPlan "${effectivePlan}"; then
        quotaError="限额自动执行时，停用超额分享订阅失败"
    else
        if ! applySubscriptionQuotaPlanAccounts "${effectivePlan}"; then
            quotaError="${SUBSCRIPTION_SYNC_TRANSACTION_ERROR:-限额自动执行时，移除本机托管账号失败}"
        fi
    fi
    if [[ -z "${quotaError}" ]]; then
        padmRemoveCleanupPath "${backupFile}"
        return 0
    fi
    if ! restoreSubscriptionGroupsBackup "${backupFile}"; then
        subscriptionSyncSetSingleRestoreResultMessage \
            SUBSCRIPTION_SYNC_TRANSACTION_ERROR \
            "${quotaError}" \
            false \
            "已恢复旧订阅状态" \
            "订阅状态" \
            "备份文件: ${backupFile}"
        padmForgetCleanupPath "${backupFile}"
        return 1
    fi
    padmRemoveCleanupPath "${backupFile}"
    subscriptionSyncSetSingleRestoreResultMessage \
        SUBSCRIPTION_SYNC_TRANSACTION_ERROR \
        "${quotaError}" \
        true \
        "已恢复旧订阅状态" \
        "订阅状态" \
        "备份文件: ${backupFile}"
    return 1
}

applySubscriptionQuotaPlanTransaction() {
    subscriptionGroupsWithLock applySubscriptionQuotaPlanTransactionUnlocked "$@"
}

executeSubscriptionQuotaPlanMenu() {
    local quotaPlan
    local confirm=
    local rc=0
    if ! collectSubscriptionTraffic >/dev/null 2>&1; then
        errorCard "流量快照不完整，已取消超限处理"
        return 1
    fi
    quotaPlan=$(subscriptionQuotaDryRunPlan) || {
        errorCard "超限处理计划生成失败"
        return 1
    }
    showSubscriptionQuotaPlanJson "${quotaPlan}" || return 1
    if [[ "${quotaPlan}" == '[]' ]]; then
        statusCard "无需处理" "当前没有已超额且仍启用的分享订阅"
        return 0
    fi
    autoRead subscription_quota_apply_confirm "执行后会停用超额订阅并移除本机托管账号。确认请输入 yes:" confirm
    if [[ "${confirm}" != "yes" ]]; then
        coreCancelledStatusCard "超限处理未执行"
        return 0
    fi
    if ! applySubscriptionQuotaPlanTransaction "${quotaPlan}"; then
        rc=1
    fi
    if [[ "${rc}" -eq 0 ]]; then
        successCard "超限处理已执行" "已停用超额分享订阅，并移除本机托管账号" "如需同步被控服务器，请再执行同步"
    else
        errorCard "超限处理执行失败" "已尽力执行可完成的部分，请检查本机配置后重试"
    fi
    return "${rc}"
}

runSubscriptionGroupSyncUnlocked() {
    local failures='[]'
    local -a failureMessages=()
    local remoteFailures='[]'
    local remoteSyncResult='{"failures":[],"snapshots":{}}'
    local -a remoteResultFields=()
    local remoteSnapshots='{}'
    local syncPlan
    local quotaPlan='[]'
    local configBackupDir=
    local outputBackupDir=
    local groupsBackupFile=
    local localSyncReady=false
    local localSyncFailure=
    local role
    local enabledRemoteSources=false
    local remoteSyncRequired=false
    local sourceId
    local controlStateWriteFailed=false
    local trafficCollected=false
    local localTrafficBaseline=false
    local localTrafficReady=false
    local postSyncTrafficRequired=false
    local localSyncChanged=false
    local remoteSources='[]'
    local remotePublishReady=false
    local publishedWithRemoteFailures=false
    local localSyncPlanReady=false
    local localSyncWorkRequired=false
    local missingUserUUIDs
    local quotaAutoApply=false
    local failureDetails='[]'
    local rc=0
    ensureSubscriptionGroupsState || return 1
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID || {
        failureMessages+=("本机配置读取失败")
        failures=$(jq -cn --args '$ARGS.positional' -- "${failureMessages[@]}") || return 1
        subscriptionSyncMarkResult partial "${failures}" || true
        return 1
    }

    # Keep this preflight read-only so UUID initialization remains rollback-safe.
    if ! syncPlan=$(subscriptionSyncPlan) ||
        ! subscriptionSyncValidateAccountPlan "${syncPlan}" ||
        ! missingUserUUIDs=$(subscriptionActiveGroupRead -r 'any(.user_groups[]?; .enabled == true and (.uuid // "") == "")'); then
        failureMessages+=("本机同步计划计算失败")
        rc=1
    else
        localSyncPlanReady=true
        if [[ "${missingUserUUIDs}" == "true" ]] ||
            jq -e '(.create | length > 0) or (.remove | length > 0)' <<<"${syncPlan}" >/dev/null 2>&1; then
            localSyncWorkRequired=true
        fi
    fi
    if [[ "${SUBSCRIPTION_SYNC_ROLLBACK:-false}" != "true" ]] && subscriptionGroupQuotaAutoApplyEnabled; then
        quotaAutoApply=true
    fi

    if [[ "${localSyncWorkRequired}" == "true" || "${quotaAutoApply}" == "true" ]] && subscriptionLocalTrafficBaselineExists; then
        localTrafficBaseline=true
    fi
    SUBSCRIPTION_TRAFFIC_LOCAL_COMMITTED=false
    if [[ "${localSyncWorkRequired}" == "true" || "${quotaAutoApply}" == "true" ]]; then
        if collectSubscriptionTraffic; then
            trafficCollected=true
            localTrafficReady=true
        elif [[ "${SUBSCRIPTION_TRAFFIC_LOCAL_COMMITTED:-false}" == "true" ]]; then
            localTrafficReady=true
            statusCard "流量统计" "同步前部分来源采集失败，成功来源已更新，失败来源保留旧统计"
        else
            statusCard "流量统计" "同步前流量快照不完整，已保留旧统计"
        fi
    fi

    if [[ "${quotaAutoApply}" == "true" ]]; then
        if [[ "${trafficCollected}" == "true" ]]; then
            if ! quotaPlan=$(subscriptionQuotaDryRunPlan); then
                failureMessages+=("限额自动执行计划生成失败")
                rc=1
            elif ! subscriptionQuotaValidatePlan "${quotaPlan}"; then
                failureMessages+=("限额自动执行计划格式无效")
                rc=1
            elif [[ "${quotaPlan}" != '[]' ]]; then
                postSyncTrafficRequired=true
                if ! applySubscriptionQuotaPlanTransaction "${quotaPlan}"; then
                    failureMessages+=("${SUBSCRIPTION_SYNC_TRANSACTION_ERROR:-限额自动执行失败}")
                    rc=1
                fi
            fi
        else
            statusCard "限额自动执行" "流量快照不完整，已跳过额度判断并保留旧统计"
        fi
    fi

    if [[ "${localSyncPlanReady}" != "true" ]]; then
        :
    elif [[ "${localSyncWorkRequired}" != "true" && "${quotaAutoApply}" != "true" ]]; then
        localSyncReady=true
    elif ! subscriptionSyncCreateLocalApplyBackups configBackupDir outputBackupDir groupsBackupFile; then
        failureMessages+=("本机同步前配置备份失败")
        if [[ "${SUBSCRIPTION_SYNC_LOCAL_APPLY_BACKUP_STAGE:-}" == "config" ]]; then
            failureMessages+=("本机同步前订阅输出备份失败")
            configBackupDir=
            outputBackupDir=
            groupsBackupFile=
        fi
        rc=1
    fi
    if [[ -n "${configBackupDir}" && -n "${outputBackupDir}" && -n "${groupsBackupFile}" ]]; then
        if ! subscriptionSyncEnsureEnabledUserUUIDs; then
            localSyncFailure="本机同步 UUID 初始化失败"
        elif ! syncPlan=$(subscriptionSyncPlan); then
            localSyncFailure="本机同步计划计算失败"
        elif ! subscriptionSyncValidateAccountPlan "${syncPlan}"; then
            localSyncFailure="本机同步计划格式无效"
        elif jq -e '(.create | length > 0) or (.remove | length > 0)' <<<"${syncPlan}" >/dev/null 2>&1; then
            if [[ "${localTrafficBaseline}" == "true" && "${localTrafficReady}" != "true" ]]; then
                localSyncFailure="同步前本机流量采集失败，为避免丢失累计流量已取消核心变更"
            elif ! subscriptionSyncApplyAccountPlan "${syncPlan}"; then
                localSyncFailure="本机同步计划应用失败"
            else
                localSyncChanged=true
                postSyncTrafficRequired=true
            fi
        fi
        if [[ -n "${localSyncFailure}" ]]; then
            if subscriptionSyncRollbackLocalApply "${configBackupDir}" "${outputBackupDir}" "${localSyncFailure}" "${groupsBackupFile}"; then
                subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}" "${groupsBackupFile}"
            else
                subscriptionSyncReleaseLocalApplyBackups forget "${configBackupDir}" "${outputBackupDir}" "${groupsBackupFile}"
                localSyncFailure="${SUBSCRIPTION_SYNC_TRANSACTION_ERROR:-${localSyncFailure}}"
            fi
            failureMessages+=("${localSyncFailure}")
            configBackupDir=
            outputBackupDir=
            groupsBackupFile=
            rc=1
        elif [[ "${localSyncChanged}" == "true" ]] && ! subscriptionSyncReconcileLocalServices; then
            localSyncFailure="本机同步后服务重建失败"
            if subscriptionSyncRollbackLocalApply "${configBackupDir}" "${outputBackupDir}" "${localSyncFailure}" "${groupsBackupFile}"; then
                subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}" "${groupsBackupFile}"
                subscriptionSyncSetRollbackResultMessage \
                    localSyncFailure \
                    "${localSyncFailure}" \
                    "已恢复旧配置" \
                    subscriptionSyncReconcileLocalServices \
                    "恢复旧配置后服务重建仍失败，请检查核心服务日志" \
                    true
            else
                subscriptionSyncReleaseLocalApplyBackups forget "${configBackupDir}" "${outputBackupDir}" "${groupsBackupFile}"
                localSyncFailure="${SUBSCRIPTION_SYNC_TRANSACTION_ERROR:-${localSyncFailure}}"
                subscriptionSyncRetryPartiallyRestoredConfig \
                    localSyncFailure \
                    "${SUBSCRIPTION_SYNC_CONFIG_RESTORED:-false}" \
                    subscriptionSyncReconcileLocalServices \
                    "恢复旧配置后服务重建仍失败，请检查核心服务日志" \
                    true || true
            fi
            failureMessages+=("${localSyncFailure}")
            configBackupDir=
            outputBackupDir=
            groupsBackupFile=
            rc=1
        else
            subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}" "${groupsBackupFile}"
            configBackupDir=
            outputBackupDir=
            groupsBackupFile=
            localSyncReady=true
        fi
    elif [[ "${localSyncReady}" != "true" ]]; then
        rc=1
    fi

    role=$(subscriptionCurrentRoleNormalized) || {
        failureMessages+=("订阅服务器角色读取失败")
        failures=$(jq -cn --args '$ARGS.positional' -- "${failureMessages[@]}") || return 1
        subscriptionSyncMarkResult partial "${failures}" || true
        return 1
    }
    if [[ "${role}" == "main" ]] &&
        remoteSources=$(subscriptionRemoteControlSources) &&
        [[ -n "${remoteSources}" && "${remoteSources}" != '[]' ]]; then
        enabledRemoteSources=true
        if subscriptionRemoteScopeEnabled; then
            remoteSyncRequired=true
        else
            remoteFailures='["主控控制面已关闭，启用的被控服务器无法同步"]'
            while IFS= read -r sourceId; do
                [[ -n "${sourceId}" ]] || continue
                setSubscriptionSourceSyncFailure "${sourceId}" control_disabled "主控控制面已关闭" || controlStateWriteFailed=true
            done < <(jq -r '.[].id' <<<"${remoteSources}")
            if [[ "${controlStateWriteFailed}" == "true" ]]; then
                failureMessages+=("主控控制面关闭状态写入失败")
                remoteFailures=$(jq '. + ["主控控制面关闭状态写入失败"]' <<<"${remoteFailures}")
            fi
            rc=1
        fi
    fi

    if [[ "${localSyncReady}" != "true" && "${remoteSyncRequired}" == "true" ]]; then
        failureMessages+=("本机同步未完成，已跳过被控服务器同步")
        rc=1
    fi

    if [[ "${localSyncReady}" == "true" && "${remoteSyncRequired}" == "true" ]]; then
        postSyncTrafficRequired=true
        if [[ "${SUBSCRIPTION_SYNC_ROLLBACK:-false}" == "true" ]]; then
            statusCard "订阅同步" "正在执行回滚同步" "单台请求最长 15 秒，不重复等待 WireGuard 握手，多个服务器并行执行"
        else
            statusCard "订阅同步" "正在等待被控服务器同步响应" "单台请求最长 40 秒（含重试），多个服务器并行执行"
        fi
        remoteResultFields=()
        if ! remoteSyncResult=$(runSubscriptionRemoteSync "${remoteSources}") ||
            ! mapfile -d '' -t remoteResultFields < <(
                jq -j -e '
                  select(type == "object" and (.failures | type == "array") and (.snapshots | type == "object")) |
                  [(.failures | tojson), (.snapshots | tojson)] |
                  map(. , "\u0000") | .[]
                ' <<<"${remoteSyncResult}" 2>/dev/null
            ) ||
            [[ "${#remoteResultFields[@]}" -ne 2 ]]; then
            remoteFailures='["被控服务器同步结果生成失败"]'
            remoteSnapshots=null
        else
            remoteFailures=${remoteResultFields[0]}
            remoteSnapshots=${remoteResultFields[1]}
        fi
        if [[ "${remoteFailures}" != "[]" ]]; then
            rc=1
        fi
    fi

    if [[ "${remoteSyncRequired}" == "true" ]]; then
        if [[ "${remoteSnapshots}" != "null" ]] && jq -e 'type == "object"' <<<"${remoteSnapshots}" >/dev/null 2>&1; then
            remotePublishReady=true
        fi
    elif [[ "${enabledRemoteSources}" != "true" ]]; then
        remotePublishReady=true
    fi

    if [[ "${localSyncReady}" == "true" && "${remotePublishReady}" == "true" ]]; then
        subscribePort=
        subscribeType=
        subscribeDomain=
        if ! readNginxSubscribe; then
            failureMessages+=("订阅 Nginx 配置损坏，已跳过公网订阅刷新")
            rc=1
        elif [[ -n "${subscribePort:-}" ]]; then
            statusCard "订阅同步" "正在刷新并原子发布订阅节点，请稍候"
            if ! refreshPublishedSubscriptions "${remoteSnapshots}" >/dev/null 2>&1; then
                failureMessages+=("同步完成后公网订阅刷新失败")
                rc=1
            elif [[ "${remoteFailures}" != "[]" ]]; then
                publishedWithRemoteFailures=true
            fi
            local publishedAccountCount
            local remoteSourceCount
            local remoteFailureCount
            local remoteSuccessCount
            publishedAccountCount=$(printf '%s\n' "${SUBSCRIPTION_PUBLISH_ACCOUNTS:-}" | sed '/^$/d' | wc -l | tr -d ' ') || publishedAccountCount=0
            remoteSourceCount=$(jq 'length' <<<"${remoteSources}" 2>/dev/null || printf '0')
            remoteFailureCount=$(jq 'length' <<<"${remoteFailures}" 2>/dev/null || printf '0')
            remoteSuccessCount=$((remoteSourceCount - remoteFailureCount))
            ((remoteSuccessCount >= 0)) || remoteSuccessCount=0
            statusCard "订阅摘要" "成功来源 ${remoteSuccessCount} 个，失败来源 ${remoteFailureCount} 个，实际发布账号 ${publishedAccountCount} 个，失败来源沿用旧快照：$(if [[ "${remoteFailures}" != "[]" ]]; then printf '是'; else printf '否'; fi)"
        fi
    fi

    if [[ "${localSyncReady}" != "true" && -n "${configBackupDir}" ]]; then
        padmRemoveCleanupPath "${configBackupDir}"
    fi
    if [[ "${localSyncReady}" != "true" && -n "${outputBackupDir}" ]]; then
        padmRemoveCleanupPath "${outputBackupDir}"
    fi

    if [[ "${postSyncTrafficRequired}" == "true" ]] && ! collectSubscriptionTraffic; then
        if [[ "${SUBSCRIPTION_TRAFFIC_LOCAL_COMMITTED:-false}" == "true" ]]; then
            statusCard "流量统计" "同步已完成，本机和成功来源基线已更新，失败来源保留旧统计"
        else
            statusCard "流量统计" "同步已完成，但重载后的流量基线更新失败，已保留旧统计"
        fi
    fi

    failures=$(jq -cn --args '$ARGS.positional' -- "${failureMessages[@]}") || return 1
    if [[ "${remoteFailures}" != "[]" ]]; then
        failures=$(jq -n --argjson failures "${failures}" --argjson remoteFailures "${remoteFailures}" '$failures + $remoteFailures') || return 1
    fi
    if [[ "${failures}" != "[]" ]]; then
        if failureDetails=$(subscriptionActiveGroupRead -c '[.sources[]? | select(.last_sync_error? and (.last_sync_error.type // "") != "") | {source_id:.id, type:.last_sync_error.type, message:(.last_sync_error.message // "")}]' 2>/dev/null); then
            :
        else
            failureDetails='[]'
        fi
        failureDetails=$(jq -n --argjson details "${failureDetails}" --argjson failures "${failures}" '$details + [$failures[] | select(test("^远程服务器源 ") | not) | {type:"sync_failure", message:.}]') || return 1
    else
        failureDetails='[]'
    fi
    if [[ "${failures}" == "[]" ]]; then
        if subscriptionSyncMarkResult success "${failures}" "${failureDetails}"; then
            successCard "自动同步完成"
        else
            errorCard "自动同步已执行，但同步结果写入失败"
            return 1
        fi
    else
        if ! subscriptionSyncMarkResult partial "${failures}" "${failureDetails}"; then
            rc=1
        fi
        if [[ "${localSyncReady}" == "true" ]]; then
            if [[ "${enabledRemoteSources}" == "true" && "${remoteFailures}" != "[]" ]]; then
                if [[ "${publishedWithRemoteFailures}" == "true" ]]; then
                    statusCard "订阅同步" "本机自动同步完成，已按可用来源发布订阅；部分被控服务器同步失败，请查看失败列表"
                else
                    statusCard "订阅同步" "本机自动同步完成，但被控服务器同步失败，请查看失败列表"
                fi
            else
                statusCard "订阅同步" "本机自动同步完成，但部分步骤失败，请查看失败列表"
            fi
        elif [[ "${enabledRemoteSources}" == "true" ]]; then
            statusCard "订阅同步" "本机同步未完全完成，请先处理本机错误后再试被控服务器同步"
        else
            statusCard "订阅同步" "本机同步未完全完成，请先处理本机错误"
        fi
    fi
    return "${rc}"
}

runSubscriptionGroupSync() {
    subscriptionRequireLocalPublisherRole || return 1
    subscriptionGroupsWithLock runSubscriptionGroupSyncUnlocked
}

runSubscriptionGroupSyncCron() {
    local enabled
    local status
    local previousLockTimeout=${PADM_SUBSCRIPTION_GROUPS_LOCK_TIMEOUT-}
    local previousSkipBusy=${PADM_SUBSCRIPTION_GROUPS_LOCK_SKIP_BUSY-}
    SUBSCRIPTION_GROUPS_LOCK_SKIPPED=false
    subscriptionRequireLocalPublisherRole || return 1
    enabled=$(subscriptionActiveGroupRead -r '.sync.enabled == true') || return 1
    [[ "${enabled}" == "true" ]] || return 0
    PADM_SUBSCRIPTION_GROUPS_LOCK_TIMEOUT=0
    PADM_SUBSCRIPTION_GROUPS_LOCK_SKIP_BUSY=true
    if runSubscriptionGroupSync; then status=0; else status=$?; fi
    if [[ -n "${previousLockTimeout}" ]]; then PADM_SUBSCRIPTION_GROUPS_LOCK_TIMEOUT=${previousLockTimeout}; else unset PADM_SUBSCRIPTION_GROUPS_LOCK_TIMEOUT; fi
    if [[ -n "${previousSkipBusy}" ]]; then PADM_SUBSCRIPTION_GROUPS_LOCK_SKIP_BUSY=${previousSkipBusy}; else unset PADM_SUBSCRIPTION_GROUPS_LOCK_SKIP_BUSY; fi
    if [[ "${SUBSCRIPTION_GROUPS_LOCK_SKIPPED:-false}" == "true" ]]; then
        printf '[%s] SyncSubscriptionGroups skipped: previous run still holds the lock\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$(subscriptionGroupSyncCronFile)" 2>/dev/null || true
        return 0
    fi
    return "${status}"
}

subscriptionGroupSyncCronFile() {
    printf '/etc/padm/crontab_subscription_groups.log\n'
}

subscriptionGroupSyncCronCommand() {
    local interval
    local defaultInterval
    local failureCount
    local backoff
    defaultInterval=$(subscriptionGroupSyncDefaultInterval) || return 1
    interval=$(subscriptionActiveGroupRead --argjson defaultInterval "${defaultInterval}" -r '(.sync.interval_minutes // $defaultInterval) | tonumber? // $defaultInterval') || return 1
    subscriptionGroupSyncIntervalValid "${interval}" || interval=${defaultInterval}
    failureCount=$(subscriptionActiveGroupRead -r '(.sync.failures // []) | length' 2>/dev/null || printf '0')
    [[ "${failureCount}" =~ ^[0-9]+$ ]] || failureCount=0
    backoff=0
    for ((backoff = 0; backoff < failureCount && backoff < 6; backoff++)); do :; done
    interval=$((interval * (1 << backoff)))
    ((interval <= 59)) || interval=59
    printf '* * * * * padm_minute=$(( $(date +\\%%s) / 60 )); [ $((padm_minute / %s * %s)) -eq "$padm_minute" ] && /bin/bash /etc/padm/install.sh SyncSubscriptionGroups >> %s 2>&1\n' \
        "${interval}" \
        "${interval}" \
        "$(subscriptionGroupSyncCronFile)"
}

installSubscriptionGroupSyncCron() {
    local currentCrontab
    local syncCron

    ensureSubscriptionGroupsState || return 1
    currentCrontab=$(readUserCrontabContent) || return 1
    currentCrontab=$(sed '\|/etc/padm/install.sh SyncSubscriptionGroups|d' <<<"${currentCrontab}") || return 1
    syncCron=$(subscriptionGroupSyncCronCommand) || return 1
    installUserCrontabContent "${currentCrontab}
${syncCron}"
}
