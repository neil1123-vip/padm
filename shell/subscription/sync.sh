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
    local id
    local userJson
    if id=$(subscriptionSyncAccountIdFromName "${accountName}" 2>/dev/null); then
        userJson=$(subscriptionActiveGroupRead -c --arg id "${id}" '.user_groups[]? | select(.id == $id)') || return 1
        [[ -n "${userJson}" ]] || return 1
        printf '%s\n' "${userJson}"
        return 0
    fi
    while IFS= read -r id; do
        [[ -n "${id}" ]] || continue
        if [[ "$(subscriptionSyncAccountName "${id}")" == "${accountName}" ]]; then
            subscriptionActiveGroupRead -c --arg id "${id}" '.user_groups[]? | select(.id == $id)'
            return 0
        fi
    done < <(subscriptionActiveGroupRead -r '.user_groups[]?.id')
    return 1
}

subscriptionSyncAccountId() {
    local accountName=$1
    local userJson
    local id
    if id=$(subscriptionSyncAccountIdFromName "${accountName}" 2>/dev/null); then
        printf '%s\n' "${id}"
        return 0
    fi
    userJson=$(subscriptionSyncFindUserByAccountName "${accountName}" 2>/dev/null || true)
    if [[ -n "${userJson}" ]]; then
        jq -r '.id' <<<"${userJson}"
        return 0
    fi
    return 1
}

subscriptionSyncGenerateUUID() {
    if [[ "${coreInstallType}" == "1" && -x "${ctlPath}" ]]; then
        ${ctlPath} uuid
    elif [[ "${coreInstallType}" == "2" && -x "${ctlPath}" ]]; then
        ${ctlPath} generate uuid
    elif command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr 'A-Z' 'a-z'
    elif [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        printf '%04x%04x-%04x-%04x-%04x-%04x%04x%04x\n' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM"
    fi
}

ensureUserSubscriptionUUID() {
    local id=$1
    local userUUID
    userUUID=$(subscriptionActiveGroupRead -r --arg id "${id}" '.user_groups[]? | select(.id == $id) | .uuid // empty')
    if [[ -z "${userUUID}" ]]; then
        userUUID=$(subscriptionSyncGenerateUUID)
        subscriptionActiveGroupWrite --arg id "${id}" --arg uuid "${userUUID}" '.user_groups |= map(if .id == $id then .uuid = $uuid else . end)' || return 1
    fi
    echo "${userUUID}"
}

subscriptionSyncDesiredLocalUsers() {
    subscriptionActiveGroupRead -r '
      .user_groups[]?
      | select(.enabled == true)
      | select((.allowed_sources | index("main")) or (.allowed_sources | index("*")))
      | .id'
}

subscriptionSyncAccountNamesJsonFromIds() {
    jq -R -s '
      split("\n")
      | map(select(length > 0))
      | map(
          . as $id
          | "sub_" + (($id | gsub("_"; "\u0001") | gsub("-"; "_") | gsub("\u0001"; "-")))
        )
      | unique
    '
}

subscriptionSyncCurrentManagedUsers() {
    local file
    local validFiles=()
    for file in "$@"; do
        [[ -f "${file}" ]] && validFiles+=("${file}")
    done
    [[ "${#validFiles[@]}" -gt 0 ]] || {
        printf '[]\n'
        return 0
    }
    jq -c -s '
      [.[] | [(.inbounds[]?.settings.clients[]?), (.inbounds[]?.users[]?)][]
       | ((.email // .name // .username // "") | sub("-(VLESS_TCP/TLS_Vision|VLESS_WS|VLESS_Reality_XHTTP|Trojan_gRPC|VMess_WS|trojan_tcp|Trojan_TCP|vless_grpc|singbox_hysteria2|vless_reality_vision|vless_reality_grpc|VLESS_Reality_Vision|VLESS_Reality_gPRC|singbox_tuic|singbox_naive|VMess_HTTPUpgrade|anytls)$"; ""))
       | select(startswith("sub_"))]
      | unique' "${validFiles[@]}"
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
}

subscriptionSyncConfiguredManagedUsers() {
    local file
    local files=()
    subscriptionSyncRequireSafeConfigDirs || return 1
    while IFS= read -r file; do
        files+=("${file}")
    done < <(subscriptionSyncConfigFiles)
    subscriptionSyncCurrentManagedUsers "${files[@]}"
}

subscriptionSyncPlanFromAccounts() {
    local desiredAccountsJson=$1
    local currentAccounts
    currentAccounts=$(subscriptionSyncConfiguredManagedUsers) || return 1
    jq -n \
      --argjson desired "${desiredAccountsJson}" \
      --argjson current "${currentAccounts}" \
      '{create: ($desired - $current), remove: ($current - $desired)}'
}

subscriptionSyncPlan() {
    local desiredAccountsJson
    desiredAccountsJson=$(subscriptionSyncAccountNamesJsonFromIds < <(subscriptionSyncDesiredLocalUsers)) || return 1
    subscriptionSyncPlanFromAccounts "${desiredAccountsJson}"
}

subscriptionSyncRemoveAccountFromFile() {
    local file=$1
    local accountName=$2
    local tmpFile
    [[ -f "${file}" ]] || return 0
    if ! jq -e --arg accountName "${accountName}" '
      [(.inbounds[]?.settings.clients[]?), (.inbounds[]?.users[]?)][]
      | select(((.email // .name // .username // "") | sub("-(VLESS_TCP/TLS_Vision|VLESS_WS|VLESS_Reality_XHTTP|Trojan_gRPC|VMess_WS|trojan_tcp|Trojan_TCP|vless_grpc|singbox_hysteria2|vless_reality_vision|vless_reality_grpc|VLESS_Reality_Vision|VLESS_Reality_gPRC|singbox_tuic|singbox_naive|VMess_HTTPUpgrade|anytls)$"; "")) == $accountName)' "${file}" >/dev/null 2>&1; then
        return
    fi
    padmCreateTempFileForTarget tmpFile "${file}" sync || return 1
    if ! jq --arg accountName "${accountName}" '
      (.inbounds[]?.settings.clients? // empty) |= map(select(((.email // .name // .username // "") | sub("-(VLESS_TCP/TLS_Vision|VLESS_WS|VLESS_Reality_XHTTP|Trojan_gRPC|VMess_WS|trojan_tcp|Trojan_TCP|vless_grpc|singbox_hysteria2|vless_reality_vision|vless_reality_grpc|VLESS_Reality_Vision|VLESS_Reality_gPRC|singbox_tuic|singbox_naive|VMess_HTTPUpgrade|anytls)$"; "")) != $accountName)) |
      (.inbounds[]?.users? // empty) |= map(select(((.email // .name // .username // "") | sub("-(VLESS_TCP/TLS_Vision|VLESS_WS|VLESS_Reality_XHTTP|Trojan_gRPC|VMess_WS|trojan_tcp|Trojan_TCP|vless_grpc|singbox_hysteria2|vless_reality_vision|vless_reality_grpc|VLESS_Reality_Vision|VLESS_Reality_gPRC|singbox_tuic|singbox_naive|VMess_HTTPUpgrade|anytls)$"; "")) != $accountName))' "${file}" >"${tmpFile}"; then
        padmRemoveCleanupPath "${tmpFile}"
        return 1
    fi
    commitGeneratedJsonFile "${tmpFile}" "${file}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

subscriptionSyncRemoveAccount() {
    local accountName=$1
    local file
    local rc=0
    subscriptionSyncRequireSafeConfigDirs || return 1
    while IFS= read -r file; do
        if ! subscriptionSyncRemoveAccountFromFile "${file}" "${accountName}"; then
            rc=1
        fi
    done < <(subscriptionSyncConfigFiles)
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

subscriptionSyncUserPath() {
    local file=$1
    local preferredPath=$2
    if [[ -n "${preferredPath}" ]]; then
        echo "${preferredPath}"
    elif jq -e '.inbounds[1].settings.clients' "${file}" >/dev/null 2>&1; then
        echo '.inbounds[1].settings.clients'
    elif jq -e '.inbounds[0].settings.clients' "${file}" >/dev/null 2>&1; then
        echo '.inbounds[0].settings.clients'
    else
        echo '.inbounds[0].users'
    fi
}

subscriptionSyncAppendProtocolUser() {
    local protocolId=$1
    local file=$2
    local preferredPath=$3
    local uuid=$4
    local accountName=$5
    local clients=
    local userPath=
    local currentClients='[]'
    [[ -f "${file}" ]] || return 0
    userPath=$(subscriptionSyncUserPath "${file}" "${preferredPath}")
    if jq -e --arg accountName "${accountName}" "${userPath}[]? | select(((.email // .name // .username // \"\") | sub(\"-(VLESS_TCP/TLS_Vision|VLESS_WS|VLESS_Reality_XHTTP|Trojan_gRPC|VMess_WS|trojan_tcp|Trojan_TCP|vless_grpc|singbox_hysteria2|vless_reality_vision|vless_reality_grpc|VLESS_Reality_Vision|VLESS_Reality_gPRC|singbox_tuic|singbox_naive|VMess_HTTPUpgrade|anytls)$\"; \"\")) == \$accountName)" "${file}" >/dev/null 2>&1; then
        return
    fi
    currentClients=$(jq -c "${userPath} // []" "${file}") || return 1
    if [[ "${coreInstallType}" == "2" ]]; then
        clients=$(initSingBoxClients "${protocolId}" "${uuid}" "${accountName}")
    else
        clients=$(initXrayClients "${protocolId}" "${uuid}" "${accountName}")
    fi
    subscriptionSyncSetUsersInFile "${file}" "${userPath}" "${clients}"
}

subscriptionSyncAppendLocalUser() {
    local id=$1
    local accountName
    local uuid
    local xrayConfigDir
    local singBoxConfigDir=
    local rc=0
    accountName=$(subscriptionSyncAccountName "${id}")
    uuid=$(ensureUserSubscriptionUUID "${id}") || return 1

    xrayConfigDir=$(subscriptionSyncSafeConfigDir) || return 1
    if [[ -n "${singBoxConfigPath:-}" ]]; then
        singBoxConfigDir=$(subscriptionSyncSafeSingBoxConfigDir) || return 1
    fi

    subscriptionSyncAppendProtocolUser 0 "${xrayConfigDir}02_VLESS_TCP_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 1 "${xrayConfigDir}03_VLESS_WS_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 2 "${xrayConfigDir}04_trojan_gRPC_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 3 "${xrayConfigDir}05_VMess_WS_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 4 "${xrayConfigDir}04_trojan_TCP_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 5 "${xrayConfigDir}06_VLESS_gRPC_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 7 "${xrayConfigDir}07_VLESS_vision_reality_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 8 "${xrayConfigDir}08_VLESS_vision_gRPC_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 11 "${xrayConfigDir}11_VMess_HTTPUpgrade_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 12 "${xrayConfigDir}12_VLESS_XHTTP_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 13 "${xrayConfigDir}13_anytls_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    if [[ -n "${singBoxConfigDir}" && "${singBoxConfigDir}" != "${xrayConfigDir}" ]]; then
        subscriptionSyncAppendProtocolUser 6 "${singBoxConfigDir}06_hysteria2_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
        subscriptionSyncAppendProtocolUser 9 "${singBoxConfigDir}09_tuic_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
        subscriptionSyncAppendProtocolUser 10 "${singBoxConfigDir}10_naive_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    fi
    return "${rc}"
}

subscriptionSyncAppendLocalAccount() {
    local accountName=$1
    local accountId
    if ! accountId=$(subscriptionSyncAccountId "${accountName}"); then
        return 1
    fi
    subscriptionSyncAppendLocalUser "${accountId}"
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
        if ! subscriptionSyncAppendLocalAccount "${accountName}"; then
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
    local backupDir
    local file
    local backupIndex=0
    local -a backupArgs=()

    subscriptionSyncRequireSafeConfigDirs || return 1
    padmCreateTmpRootPath backupDir padm-subscription-sync-backup.XXXXXX -d || return 1
    while IFS= read -r file; do
        [[ -f "${file}" ]] || continue
        backupArgs+=("$(printf '%06d.json' "${backupIndex}")" "${file}")
        backupIndex=$((backupIndex + 1))
    done < <(subscriptionSyncConfigFiles)
    if ! padmWriteManagedFileBackupManifest "${backupDir}" "${backupArgs[@]}"; then
        padmRemoveCleanupPath "${backupDir}"
        return 1
    fi
    printf '%s\n' "${backupDir}"
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
    local backupDir
    local localBase
    local publicBase

    padmCreateTmpRootPath backupDir padm-subscription-output-backup.XXXXXX -d || return 1
    localBase=$(subscribeLocalBaseDir)
    publicBase=$(subscribePublicBaseDir)
    subscriptionSyncBackupPath "${localBase}" "${backupDir}" local || { padmRemoveCleanupPath "${backupDir}"; return 1; }
    subscriptionSyncBackupPath "${publicBase}" "${backupDir}" public || { padmRemoveCleanupPath "${backupDir}"; return 1; }
    printf '%s\n' "${backupDir}"
}

subscriptionSyncCreateLocalApplyBackups() {
    local configVar=$1
    local outputVar=$2
    local createdConfigBackupDir=
    local createdOutputBackupDir=

    SUBSCRIPTION_SYNC_LOCAL_APPLY_BACKUP_STAGE=
    createdConfigBackupDir=$(subscriptionSyncCreateConfigBackups) || return 1
    SUBSCRIPTION_SYNC_LOCAL_APPLY_BACKUP_STAGE=config
    createdOutputBackupDir=$(subscriptionSyncCreateSubscribeOutputBackups) || {
        padmRemoveCleanupPath "${createdConfigBackupDir}"
        return 1
    }
    SUBSCRIPTION_SYNC_LOCAL_APPLY_BACKUP_STAGE=ready
    printf -v "${configVar}" '%s' "${createdConfigBackupDir}"
    printf -v "${outputVar}" '%s' "${createdOutputBackupDir}"
}

subscriptionSyncReleaseLocalApplyBackups() {
    local mode=$1
    local configBackupDir=${2:-}
    local outputBackupDir=${3:-}

    [[ -n "${configBackupDir}" ]] || return 0
    [[ -n "${outputBackupDir}" ]] || return 0
    case "${mode}" in
    remove)
        padmRemoveCleanupPath "${configBackupDir}"
        padmRemoveCleanupPath "${outputBackupDir}"
        ;;
    forget)
        padmForgetCleanupPath "${configBackupDir}"
        padmForgetCleanupPath "${outputBackupDir}"
        ;;
    *)
        return 1
        ;;
    esac
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
    local configRestored=true
    local outputRestored=true

    SUBSCRIPTION_SYNC_TRANSACTION_ERROR=
    if ! subscriptionSyncRestoreConfigBackups "${configBackupDir}" >/dev/null 2>&1; then
        configRestored=false
    fi
    if ! subscriptionSyncRestoreSubscribeOutputBackups "${outputBackupDir}" >/dev/null 2>&1; then
        outputRestored=false
    fi

    subscriptionSyncSetRestorePairFailureMessage \
        SUBSCRIPTION_SYNC_TRANSACTION_ERROR \
        "${reason}" \
        "${configRestored}" "配置" "备份目录: ${configBackupDir}" \
        "${outputRestored}" "订阅输出" "备份目录: ${outputBackupDir}" \
        "备份目录: ${configBackupDir} 和 ${outputBackupDir}"
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
    local result="${failedLabel}恢复失败"

    if [[ -n "${failedLocation}" ]]; then
        subscriptionSyncSetManualCheckMessage result "${result}" "${failedLocation}"
    fi

    printf -v "${outputVar}" '%s' "${result}"
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
    local result=

    if [[ "${restored}" == "true" ]]; then
        if [[ -n "${restoredMessage}" ]]; then
            result="${reason}，${restoredMessage}"
        else
            result="${reason}"
        fi
        printf -v "${outputVar}" '%s' "${result}"
        return 0
    fi

    result="${reason}，且${failedLabel}恢复失败"
    if [[ "${includeManualCheck}" != "false" ]]; then
        subscriptionSyncSetManualCheckMessage result "${result}" "${failedLocation}"
    fi
    printf -v "${outputVar}" '%s' "${result}"
    return 1
}

subscriptionSyncSetRollbackResultMessage() {
    local outputVar=$1
    local reason=$2
    local restoredMessage=$3
    local retryFn=${4:-}
    local retryFailureMessage=${5:-}
    local result

    if [[ -n "${retryFn}" ]]; then
        shift 5
        if "${retryFn}" "$@"; then
            result="${reason}，${restoredMessage}"
        else
            result="${reason}，${restoredMessage}；${retryFailureMessage}"
        fi
    else
        result="${reason}，${restoredMessage}"
    fi

    printf -v "${outputVar}" '%s' "${result}"
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

subscriptionSyncApplyAccountPlanTransaction() {
    local syncPlan=$1
    local reloadFn=${2:-}
    local backupDir
    local applyStatus=0
    SUBSCRIPTION_SYNC_TRANSACTION_ERROR=
    subscriptionSyncValidateAccountPlan "${syncPlan}" || return 1
    backupDir=$(subscriptionSyncCreateConfigBackups) || return 1
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
    local skipSubscribeRefresh=${1:-}
    reloadCore || return 1
    readNginxSubscribe
    installSubscriptionControlService || return 1
    if ensureSubscriptionControlNginxLocation; then
        serviceQueueRestart nginx || return 1
        serviceQueueApply || return 1
    fi
    if [[ -n "${subscribePort}" && -z "${skipSubscribeRefresh}" ]]; then
        subscribe false || return 1
    fi
    return 0
}

subscriptionSyncRefreshPublishedSubscriptions() {
    subscribePort=
    subscribeType=
    subscribeDomain=
    readNginxSubscribe
    [[ -n "${subscribePort:-}" ]] || return 0
    subscribe false false >/dev/null 2>&1
}

subscriptionSyncMarkResult() {
    local status=$1
    local failures=$2
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')
    subscriptionActiveGroupWrite --arg now "${now}" --arg status "${status}" --argjson failures "${failures}" '.sync.last_run = $now | .sync.last_status = $status | .sync.failures = $failures'
}

subscriptionQuotaDryRunPlan() {
    ensureSubscriptionGroupsState
    subscriptionActiveGroupRead -r '
      . as $group |
      [($group.user_groups[]? |
        (.traffic_limit_gb // 0 | tonumber? // 0) as $limitGb |
        ($group.traffic.user_groups[.id] // {upload:0, download:0}) as $traffic |
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
        })]'
}

subscriptionQuotaValidatePlan() {
    local quotaPlan=$1
    jq -e '
      type == "array" and
      all(.[]?; type == "object" and (.id | type == "string" and length > 0) and .action == "disable-and-remove-local-account")
    ' <<<"${quotaPlan}" >/dev/null 2>&1
}

applySubscriptionQuotaPlan() {
    local quotaPlan=$1
    local id
    local planIds
    local rc=0
    subscriptionQuotaValidatePlan "${quotaPlan}" || return 1
    planIds=$(jq -r '.[].id' <<<"${quotaPlan}") || return 1
    while IFS= read -r id; do
        [[ -n "${id}" ]] || continue
        if ! userSubscriptionExists "${id}"; then
            rc=1
            continue
        fi
        if ! setUserSubscriptionEnabled "${id}" false; then
            rc=1
        fi
    done <<<"${planIds}"
    return "${rc}"
}

applySubscriptionQuotaPlanAccounts() {
    local quotaPlan=$1
    local accountPlan
    local id
    local rc=0
    subscriptionQuotaValidatePlan "${quotaPlan}" || return 1
    accountPlan=$(jq -n --argjson quotaPlan "${quotaPlan}" '
      def account_name($id):
        "sub_" + ((($id | tostring) | gsub("_"; "\u0001") | gsub("-"; "_") | gsub("\u0001"; "-")));
      {
        create: [],
        remove: [
          $quotaPlan[]?.id
          | select(type == "string" and length > 0)
          | account_name(.)
        ]
      }') || return 1
    if jq -e '.remove | length > 0' <<<"${accountPlan}" >/dev/null 2>&1; then
        if ! subscriptionSyncApplyAccountPlanTransaction "${accountPlan}" reloadCore; then
            rc=1
        fi
    fi
    return "${rc}"
}

applySubscriptionQuotaPlanTransaction() {
    local quotaPlan=$1
    local backupFile
    local quotaError=

    SUBSCRIPTION_SYNC_TRANSACTION_ERROR=
    backupFile=$(createSubscriptionGroupsBackup) || {
        SUBSCRIPTION_SYNC_TRANSACTION_ERROR="限额自动执行前订阅状态备份失败"
        return 1
    }
    if ! applySubscriptionQuotaPlan "${quotaPlan}"; then
        quotaError="限额自动执行时，停用超额分享订阅失败"
    else
        if ! applySubscriptionQuotaPlanAccounts "${quotaPlan}"; then
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

executeSubscriptionQuotaPlanMenu() {
    local quotaPlan
    local confirm=
    local rc=0
    quotaPlan=$(subscriptionQuotaDryRunPlan) || {
        errorCard "超限处理计划生成失败"
        return 1
    }
    showSubscriptionQuotaPlanJson "${quotaPlan}" || return 1
    if [[ "$(jq 'length' <<<"${quotaPlan}")" == "0" ]]; then
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

runSubscriptionGroupSync() {
    local skipSubscribeRefresh=${1:-}
    local id
    local accountName
    local failures='[]'
    local remoteFailures='[]'
    local syncPlan
    local quotaPlan='[]'
    local configBackupDir=
    local outputBackupDir=
    local localSyncReady=false
    local localSyncFailure=
    local remoteSyncEnabled=false
    local rc=0
    ensureSubscriptionGroupsState || return 1
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID

    if subscriptionGroupQuotaAutoApplyEnabled; then
        if collectSubscriptionTraffic; then
            if ! quotaPlan=$(subscriptionQuotaDryRunPlan); then
                failures=$(jq '. + ["限额自动执行计划生成失败"]' <<<"${failures}")
                rc=1
            elif ! subscriptionQuotaValidatePlan "${quotaPlan}"; then
                failures=$(jq '. + ["限额自动执行计划格式无效"]' <<<"${failures}")
                rc=1
            elif [[ "$(jq 'length' <<<"${quotaPlan}")" != "0" ]]; then
                if ! applySubscriptionQuotaPlanTransaction "${quotaPlan}"; then
                    failures=$(jq --arg message "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR:-限额自动执行失败}" '. + [$message]' <<<"${failures}")
                    rc=1
                fi
            fi
        else
            failures=$(jq '. + ["限额自动执行前流量统计刷新失败"]' <<<"${failures}")
            rc=1
        fi
    fi

    syncPlan=$(subscriptionSyncPlan) || {
        failures=$(jq '. + ["本机同步计划计算失败"]' <<<"${failures}")
        subscriptionSyncMarkResult partial "${failures}" || true
        return 1
    }
    subscriptionSyncCreateLocalApplyBackups configBackupDir outputBackupDir || {
        failures=$(jq '. + ["本机同步前配置备份失败"]' <<<"${failures}")
        if [[ "${SUBSCRIPTION_SYNC_LOCAL_APPLY_BACKUP_STAGE:-}" == "config" ]]; then
            failures=$(jq '. + ["本机同步前订阅输出备份失败"]' <<<"${failures}")
            configBackupDir=
            outputBackupDir=
        fi
        rc=1
    }
    if [[ -n "${configBackupDir}" && -n "${outputBackupDir}" ]]; then
        if ! subscriptionSyncApplyAccountPlanTransaction "${syncPlan}"; then
            failures=$(jq --arg message "${SUBSCRIPTION_SYNC_TRANSACTION_ERROR:-本机同步计划应用失败}" '. + [$message]' <<<"${failures}")
            subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}"
            configBackupDir=
            outputBackupDir=
            rc=1
        elif ! subscriptionSyncReconcileLocalServices "${skipSubscribeRefresh}"; then
            localSyncFailure="本机同步后服务重建失败"
            if subscriptionSyncRollbackLocalApply "${configBackupDir}" "${outputBackupDir}" "${localSyncFailure}"; then
                subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}"
                subscriptionSyncSetRollbackResultMessage \
                    localSyncFailure \
                    "${localSyncFailure}" \
                    "已恢复旧配置" \
                    subscriptionSyncReconcileLocalServices \
                    "恢复旧配置后服务重建仍失败，请检查核心服务日志" \
                    true
            else
                subscriptionSyncReleaseLocalApplyBackups forget "${configBackupDir}" "${outputBackupDir}"
                localSyncFailure="${SUBSCRIPTION_SYNC_TRANSACTION_ERROR:-${localSyncFailure}}"
            fi
            failures=$(jq --arg message "${localSyncFailure}" '. + [$message]' <<<"${failures}")
            configBackupDir=
            outputBackupDir=
            rc=1
        else
            subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}"
            configBackupDir=
            outputBackupDir=
            localSyncReady=true
        fi
    else
        rc=1
    fi

    if subscriptionGroupRemoteSyncEnabled; then
        remoteSyncEnabled=true
    fi

    if [[ "${localSyncReady}" != "true" && "${remoteSyncEnabled}" == "true" ]]; then
        failures=$(jq '. + ["本机同步未完成，已跳过被控服务器同步"]' <<<"${failures}")
        rc=1
    fi

    if [[ "${localSyncReady}" == "true" && "${remoteSyncEnabled}" == "true" ]]; then
        remoteFailures=$(runSubscriptionRemoteSync)
        failures=$(jq -n --argjson failures "${failures}" --argjson remoteFailures "${remoteFailures}" '$failures + $remoteFailures')
        if [[ "${remoteFailures}" != "[]" ]]; then
            rc=1
        fi
    fi

    if [[ "${localSyncReady}" == "true" ]]; then
        if ! subscriptionSyncRefreshPublishedSubscriptions; then
            failures=$(jq '. + ["同步完成后公网订阅刷新失败"]' <<<"${failures}")
            rc=1
        fi
    fi

    if [[ "${localSyncReady}" != "true" && -n "${configBackupDir}" ]]; then
        padmRemoveCleanupPath "${configBackupDir}"
    fi
    if [[ "${localSyncReady}" != "true" && -n "${outputBackupDir}" ]]; then
        padmRemoveCleanupPath "${outputBackupDir}"
    fi

    if ! collectSubscriptionTraffic; then
        failures=$(jq '. + ["同步完成后流量统计刷新失败"]' <<<"${failures}")
        rc=1
    fi

    if [[ "${failures}" == "[]" ]]; then
        if ! subscriptionSyncMarkResult success "${failures}"; then
            rc=1
        fi
        successCard "自动同步完成"
    else
        if ! subscriptionSyncMarkResult partial "${failures}"; then
            rc=1
        fi
        if [[ "${localSyncReady}" == "true" ]]; then
            if [[ "${remoteSyncEnabled}" == "true" && "${remoteFailures}" != "[]" ]]; then
                statusCard "订阅同步" "本机自动同步完成，但被控服务器同步失败，请查看失败列表"
            else
                statusCard "订阅同步" "本机自动同步完成，但部分步骤失败，请查看失败列表"
            fi
        else
            statusCard "订阅同步" "本机同步未完全完成，请先处理本机错误后再试被控服务器同步"
        fi
    fi
    return "${rc}"
}

runSubscriptionGroupSyncCron() {
    if [[ $# -eq 0 ]]; then
        runSubscriptionGroupSync skip-subscribe-refresh
    else
        runSubscriptionGroupSync "$@"
    fi
}
