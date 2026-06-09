#!/usr/bin/env bash

# 订阅组本机账号同步
subscriptionSyncAccountName() {
    local id=$1
    id=${id//-/_}
    echo "sub_${id}"
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
    local groupId
    local userUUID
    groupId=$(activeSubscriptionGroupId)
    userUUID=$(subscriptionGroupsStateRead -r --arg groupId "${groupId}" --arg id "${id}" '.groups[] | select(.id == $groupId) | .user_groups[]? | select(.id == $id) | .uuid // empty')
    if [[ -z "${userUUID}" ]]; then
        userUUID=$(subscriptionSyncGenerateUUID)
        subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg id "${id}" --arg uuid "${userUUID}" '.groups |= map(if .id == $groupId then .user_groups |= map(if .id == $id then .uuid = $uuid else . end) else . end)' || return 1
    fi
    echo "${userUUID}"
}

subscriptionSyncDesiredLocalUsers() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" '
      .groups[] | select(.id == $groupId) | .user_groups[]?
      | select(.enabled == true)
      | select((.allowed_sources | index("main")) or (.allowed_sources | index("*")))
      | .id'
}

subscriptionSyncCurrentManagedUsers() {
    local file=$1
    [[ -f "${file}" ]] || return
    jq -r '
      [(.inbounds[]?.settings.clients[]?), (.inbounds[]?.users[]?)][]
      | ((.email // .name // .username // "") | split("-")[0])
      | select(startswith("sub_"))' "${file}" 2>/dev/null | sort -u
}

subscriptionSyncConfigFiles() {
    local file
    for file in "${configPath}"*inbounds.json; do
        [[ -f "${file}" ]] && echo "${file}"
    done
    if [[ -n "${singBoxConfigPath}" && "${singBoxConfigPath}" != "${configPath}" ]]; then
        for file in "${singBoxConfigPath}"*inbounds.json; do
            [[ -f "${file}" ]] && echo "${file}"
        done
    fi
}

subscriptionSyncConfiguredManagedUsers() {
    local file
    while IFS= read -r file; do
        subscriptionSyncCurrentManagedUsers "${file}"
    done < <(subscriptionSyncConfigFiles) | sort -u
}

subscriptionSyncPlanFromAccounts() {
    local desiredAccounts=$1
    local currentAccounts
    currentAccounts=$(subscriptionSyncConfiguredManagedUsers)
    jq -n \
      --argjson desired "$(printf '%s\n' "${desiredAccounts}" | jq -R -s 'split("\n") | map(select(length > 0))')" \
      --argjson current "$(printf '%s\n' "${currentAccounts}" | jq -R -s 'split("\n") | map(select(length > 0))')" \
      '{create: ($desired - $current), remove: ($current - $desired)}'
}

subscriptionSyncPlan() {
    local desiredAccounts
    desiredAccounts=$(while IFS= read -r id; do subscriptionSyncAccountName "${id}"; done < <(subscriptionSyncDesiredLocalUsers) | sort -u)
    subscriptionSyncPlanFromAccounts "${desiredAccounts}"
}

subscriptionSyncRemoveAccountFromFile() {
    local file=$1
    local accountName=$2
    local tmpFile
    [[ -f "${file}" ]] || return 0
    if ! jq -e --arg accountName "${accountName}" '
      [(.inbounds[]?.settings.clients[]?), (.inbounds[]?.users[]?)][]
      | select(((.email // .name // .username // "") | split("-")[0]) == $accountName)' "${file}" >/dev/null 2>&1; then
        return
    fi
    padmCreateTempFileForTarget tmpFile "${file}" sync || return 1
    if ! jq --arg accountName "${accountName}" '
      (.inbounds[]?.settings.clients? // empty) |= map(select(((.email // .name // .username // "") | split("-")[0]) != $accountName)) |
      (.inbounds[]?.users? // empty) |= map(select(((.email // .name // .username // "") | split("-")[0]) != $accountName))' "${file}" >"${tmpFile}"; then
        padmRemoveCleanupPath "${tmpFile}"
        return 1
    fi
    commitGeneratedJsonFile "${tmpFile}" "${file}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

subscriptionSyncRemoveAccount() {
    local accountName=$1
    local file
    local rc=0
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
    [[ -f "${file}" ]] || return 0
    userPath=$(subscriptionSyncUserPath "${file}" "${preferredPath}")
    if jq -e --arg accountName "${accountName}" "${userPath}[]? | select(((.email // .name // .username // \"\") | split(\"-\")[0]) == \$accountName)" "${file}" >/dev/null 2>&1; then
        return
    fi
    currentClients=$(jq -r "${userPath} // []" "${file}")
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
    local rc=0
    accountName=$(subscriptionSyncAccountName "${id}")
    uuid=$(ensureUserSubscriptionUUID "${id}") || return 1

    subscriptionSyncAppendProtocolUser 0 "${configPath}02_VLESS_TCP_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 1 "${configPath}03_VLESS_WS_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 2 "${configPath}04_trojan_gRPC_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 3 "${configPath}05_VMess_WS_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 4 "${configPath}04_trojan_TCP_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 5 "${configPath}06_VLESS_gRPC_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 7 "${configPath}07_VLESS_vision_reality_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 8 "${configPath}08_VLESS_vision_gRPC_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 11 "${configPath}11_VMess_HTTPUpgrade_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 12 "${configPath}12_VLESS_XHTTP_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    subscriptionSyncAppendProtocolUser 13 "${configPath}13_anytls_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    if [[ "${singBoxConfigPath}" != "${configPath}" ]]; then
        subscriptionSyncAppendProtocolUser 6 "${singBoxConfigPath}06_hysteria2_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
        subscriptionSyncAppendProtocolUser 9 "${singBoxConfigPath}09_tuic_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
        subscriptionSyncAppendProtocolUser 10 "${singBoxConfigPath}10_naive_inbounds.json" '' "${uuid}" "${accountName}" || rc=1
    fi
    return "${rc}"
}

subscriptionSyncAccountId() {
    local accountName=$1
    accountName=${accountName#sub_}
    echo "${accountName//_/-}"
}

subscriptionSyncAppendLocalAccount() {
    local accountName=$1
    subscriptionSyncAppendLocalUser "$(subscriptionSyncAccountId "${accountName}")"
}

subscriptionSyncApplyAccountPlan() {
    local syncPlan=$1
    local accountName
    local rc=0
    while IFS= read -r accountName; do
        if ! subscriptionSyncRemoveAccount "${accountName}"; then
            rc=1
        fi
    done < <(echo "${syncPlan}" | jq -r '.remove[]?')

    while IFS= read -r accountName; do
        if ! subscriptionSyncAppendLocalAccount "${accountName}"; then
            rc=1
        fi
    done < <(echo "${syncPlan}" | jq -r '.create[]?')
    return "${rc}"
}

subscriptionSyncReconcileLocalServices() {
    local skipSubscribeRefresh=${1:-}
    local rc=0
    reloadCore || rc=1
    readNginxSubscribe
    if ! installSubscriptionControlService; then
        rc=1
    fi
    if ensureSubscriptionControlNginxLocation; then
        if ! serviceQueueRestart nginx; then
            rc=1
        fi
        if ! serviceQueueApply; then
            rc=1
        fi
    fi
    if [[ -n "${subscribePort}" && -z "${skipSubscribeRefresh}" ]]; then
        subscribe false || rc=1
    fi
    return "${rc}"
}

subscriptionSyncMarkResult() {
    local status=$1
    local failures=$2
    local groupId
    local now
    groupId=$(activeSubscriptionGroupId)
    now=$(date '+%Y-%m-%d %H:%M:%S')
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --arg now "${now}" --arg status "${status}" --argjson failures "${failures}" '.groups |= map(if .id == $groupId then .sync.last_run = $now | .sync.last_status = $status | .sync.failures = $failures else . end)'
}

subscriptionQuotaDryRunPlan() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    ensureSubscriptionGroupsState
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" '
      .groups[] | select(.id == $groupId) |
      . as $group |
      [($group.user_groups[]? |
        (.traffic_limit_gb // 0 | tonumber? // 0) as $limitGb |
        ($group.traffic.user_groups[.id] // {upload:0, download:0}) as $traffic |
        (($traffic.upload // 0) + ($traffic.download // 0)) as $usedBytes |
        (($limitGb * 1024 * 1024 * 1024) | floor) as $limitBytes |
        select((.enabled // true) == true and $limitGb > 0 and $usedBytes >= $limitBytes) |
        {
          id: .id,
          name: .name,
          used_bytes: $usedBytes,
          limit_gb: $limitGb,
          percent: (($usedBytes * 100 / $limitBytes) | floor),
          action: "disable-and-remove-local-account"
        })]'
}

applySubscriptionQuotaPlan() {
    local quotaPlan=$1
    local id
    local rc=0
    while IFS= read -r id; do
        [[ -n "${id}" ]] || continue
        if ! setUserSubscriptionEnabled "${id}" false; then
            rc=1
        fi
    done < <(jq -r '.[].id' <<<"${quotaPlan}")
    return "${rc}"
}

applySubscriptionQuotaPlanAccounts() {
    local quotaPlan=$1
    local accountPlan
    local rc=0
    accountPlan=$(jq '[.[].id | "sub_" + gsub("-"; "_")] | {create: [], remove: .}' <<<"${quotaPlan}")
    if [[ "$(jq '.remove | length' <<<"${accountPlan}")" != "0" ]]; then
        if ! subscriptionSyncApplyAccountPlan "${accountPlan}"; then
            rc=1
        fi
        if ! reloadCore; then
            rc=1
        fi
    fi
    return "${rc}"
}

executeSubscriptionQuotaPlanMenu() {
    local quotaPlan
    local confirm=
    local rc=0
    quotaPlan=$(subscriptionQuotaDryRunPlan)
    userJsonCard "超限处理计划" "${quotaPlan}"
    if [[ "$(jq 'length' <<<"${quotaPlan}")" == "0" ]]; then
        statusCard "无需处理" "当前没有已超额且仍启用的分享订阅"
        return 0
    fi
    autoRead subscription_quota_apply_confirm "执行后会停用超额订阅并移除本机托管账号。确认请输入 yes:" confirm
    if [[ "${confirm}" != "yes" ]]; then
        statusCard "已取消" "超限处理未执行"
        return 0
    fi
    if ! applySubscriptionQuotaPlan "${quotaPlan}"; then
        rc=1
    fi
    if ! applySubscriptionQuotaPlanAccounts "${quotaPlan}"; then
        rc=1
    fi
    if [[ "${rc}" -eq 0 ]]; then
        successCard "超限处理已执行" "已停用超额分享订阅，并移除本机 sub_<ID> 托管账号" "如需同步被控服务器，请再执行同步"
    else
        errorCard "超限处理执行失败" "已尽力执行可完成的部分，请检查本机配置后重试"
    fi
    return 0
}

runSubscriptionGroupSync() {
    local skipSubscribeRefresh=${1:-}
    local id
    local accountName
    local failures='[]'
    local remoteFailures='[]'
    local syncPlan
    local quotaPlan='[]'
    local rc=0
    ensureSubscriptionGroupsState || return 1
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID

    if subscriptionGroupQuotaAutoApplyEnabled; then
        if collectSubscriptionTraffic; then
            quotaPlan=$(subscriptionQuotaDryRunPlan)
            if [[ "$(jq 'length' <<<"${quotaPlan}")" != "0" ]]; then
                if ! applySubscriptionQuotaPlan "${quotaPlan}"; then
                    failures=$(jq '. + ["限额自动执行时，停用超额分享订阅失败"]' <<<"${failures}")
                    rc=1
                fi
                if ! applySubscriptionQuotaPlanAccounts "${quotaPlan}"; then
                    failures=$(jq '. + ["限额自动执行时，移除本机托管账号失败"]' <<<"${failures}")
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
    if ! subscriptionSyncApplyAccountPlan "${syncPlan}"; then
        failures=$(jq '. + ["本机同步计划应用失败"]' <<<"${failures}")
        rc=1
    fi

    if subscriptionGroupRemoteSyncEnabled; then
        remoteFailures=$(runSubscriptionRemoteSync)
        failures=$(jq -n --argjson failures "${failures}" --argjson remoteFailures "${remoteFailures}" '$failures + $remoteFailures')
        if [[ "${remoteFailures}" != "[]" ]]; then
            rc=1
        fi
    fi

    if ! subscriptionSyncReconcileLocalServices "${skipSubscribeRefresh}"; then
        failures=$(jq '. + ["本机同步后服务重建失败"]' <<<"${failures}")
        rc=1
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
        statusCard "订阅同步" "本机自动同步完成，被控服务器待后续通道同步"
    fi
    return "${rc}"
}

runSubscriptionGroupSyncCron() {
    runSubscriptionGroupSync "$@"
}
