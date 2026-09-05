#!/usr/bin/env bash

subscriptionGroupsStateSummaryJson() {
    local localOnly=false
    local defaultInterval
    [[ "$(subscriptionCurrentRoleNormalized)" == "uninitialized" ]] && localOnly=true
    defaultInterval=$(subscriptionGroupSyncDefaultInterval) || return 1
    PADM_SUBSCRIPTION_GROUPS_LOCK_TIMEOUT=0 subscriptionActiveGroupRead --argjson localOnly "${localOnly}" --argjson defaultInterval "${defaultInterval}" '
      {
        group_id: .id,
        group_name: .name,
        subscription_users: (.user_groups | length),
        enabled_users: ([.user_groups[]? | select(.enabled == true)] | length),
        sources: ([.sources[]? | select(($localOnly | not) or .role == "main")] | length),
        enabled_remote_sources: (if $localOnly then 0 else ([.sources[]? | select(.role != "main" and .enabled == true)] | length) end),
        sync: {
          enabled: (.sync.enabled == true),
          interval_minutes: (.sync.interval_minutes // $defaultInterval),
          quota_auto_apply: (.sync.quota_auto_apply // false),
          last_run: (.sync.last_run // ""),
          last_status: (.sync.last_status // "pending"),
          failures: (.sync.failures // [])
        },
        traffic_updated_at: (((.traffic.sources // {}) | to_entries | map(.value.updated_at // empty) | max) // "unknown")
      }'
}

showSubscriptionGroupsStateSummary() {
    local summaryJson
    local summary
    summaryJson=$(subscriptionGroupsStateSummaryJson) || {
        errorCard "订阅状态摘要读取失败"
        return 1
    }
    summary=$(jq -r '
      "当前组：" + ((.group_name // .group_id // "未知") | tostring) + "(" + ((.group_id // "unknown") | tostring) + ")\n" +
      "分享订阅：" + ((.subscription_users // 0) | tostring) + " 个，启用 " + ((.enabled_users // 0) | tostring) + " 个\n" +
      "服务器源：" + ((.sources // 0) | tostring) + " 个，启用远端 " + ((.enabled_remote_sources // 0) | tostring) + " 个\n" +
      "同步状态：" + ((.sync.last_status // "pending") | tostring) + "，最近运行 " + ((.sync.last_run // "未运行") | tostring) + "\n" +
      "流量更新时间：" + ((.traffic_updated_at // "unknown") | tostring)
    ' <<<"${summaryJson}") || return 1
    showSubscriptionJsonWithSummary "订阅状态摘要" "${summaryJson}" "${summary}"
}

createSubscriptionGroupsBackupMenu() {
    local backupFile
    backupFile=$(createSubscriptionGroupsBackup) || {
        errorCard "状态备份失败"
        return 1
    }
    successCard "状态备份已创建" "备份文件：${backupFile}"
}

selectSubscriptionGroupsBackupFile() {
    local backupChoice=
    local backupFile=
    local backupsOutput
    local backups=()
    local index
    selectedSubscriptionGroupsBackupFile=
    backupsOutput=$(listSubscriptionGroupsBackups) || {
        errorCard "状态备份列表读取失败"
        return 1
    }
    [[ -z "${backupsOutput}" ]] || mapfile -t backups <<<"${backupsOutput}"
    if [[ "${#backups[@]}" -eq 0 ]]; then
        errorCard "暂无可恢复的状态备份"
        return 1
    fi
    userResultCard "选择状态备份"
    for index in "${!backups[@]}"; do
        menuLine "$((index + 1)). ${backups[${index}]}"
    done
    menuClose
    autoRead subscription_backup_choice "请输入备份编号或完整路径:" backupChoice
    if [[ "${backupChoice}" =~ ^[0-9]+$ ]] && [[ "${backupChoice}" -ge 1 && "${backupChoice}" -le "${#backups[@]}" ]]; then
        backupFile=${backups[$((backupChoice - 1))]}
    else
        backupFile=${backupChoice}
    fi
    if [[ -z "${backupFile}" || ! -f "${backupFile}" ]] || ! jq empty "${backupFile}" >/dev/null 2>&1; then
        errorCard "备份文件无效" "请确认文件存在且是合法 JSON"
        return 1
    fi
    selectedSubscriptionGroupsBackupFile=${backupFile}
}

applySubscriptionGroupsStateMaintenanceUnlocked() {
    local targetStateFile=$1
    local actionName=$2
    local currentBackup=
    local configBackupDir=
    local outputBackupDir=
    local previousCrontab=
    local previousGroupsState=
    local targetGroupsState=
    local failure=
    local rollbackStatus=0
    local wireGuardTransitionActive=false

    SUBSCRIPTION_STATE_MAINTENANCE_BACKUP=
    SUBSCRIPTION_STATE_MAINTENANCE_ERROR=
    previousCrontab=$(readUserCrontabContent) || {
        SUBSCRIPTION_STATE_MAINTENANCE_ERROR="${actionName}前读取定时任务失败，未执行${actionName}"
        return 1
    }
    currentBackup=$(createSubscriptionGroupsBackup) || {
        SUBSCRIPTION_STATE_MAINTENANCE_ERROR="${actionName}前备份当前状态失败，未执行${actionName}"
        return 1
    }
    SUBSCRIPTION_STATE_MAINTENANCE_BACKUP=${currentBackup}
    previousGroupsState=$(<"${currentBackup}") || {
        SUBSCRIPTION_STATE_MAINTENANCE_ERROR="${actionName}前读取当前状态备份失败，未执行${actionName}"
        return 1
    }
    if ! subscriptionSyncCreateLocalApplyBackups configBackupDir outputBackupDir; then
        SUBSCRIPTION_STATE_MAINTENANCE_ERROR="${actionName}前备份本机配置或订阅输出失败，未执行${actionName}"
        return 1
    fi
    if ! subscriptionGroupsStateReplace "${targetStateFile}" "$(subscriptionGroupsFile)"; then
        subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}"
        SUBSCRIPTION_STATE_MAINTENANCE_ERROR="订阅状态${actionName}失败，当前状态未变"
        return 1
    fi
    if declare -F subscriptionWireGuardCleanupRemovedSources >/dev/null 2>&1; then
        if ! targetGroupsState=$(jq -c '.' "$(subscriptionGroupsFile)" 2>/dev/null); then
            failure="订阅状态${actionName}后的目标状态读取失败"
        elif ! subscriptionWireGuardCleanupRemovedSources "${previousGroupsState}" "${targetGroupsState}"; then
            failure="订阅状态${actionName}后的旧来源清理失败"
        elif [[ "${SUBSCRIPTION_WIREGUARD_GROUPS_TRANSITION_ACTIVE:-false}" == "true" ]]; then
            wireGuardTransitionActive=true
        fi
    fi
    if [[ -z "${failure}" ]] && ! runSubscriptionGroupSync; then
        failure="订阅状态${actionName}后的完整同步失败"
    elif [[ -z "${failure}" ]] && ! refreshSubscriptionGroupSyncCron; then
        failure="订阅状态${actionName}后的定时任务刷新失败"
    fi
    if [[ -z "${failure}" ]]; then
        if declare -F subscriptionWireGuardResetGroupsTransition >/dev/null 2>&1; then
            subscriptionWireGuardResetGroupsTransition
        fi
        subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}"
        return 0
    fi

    if subscriptionSyncRollbackLocalApply "${configBackupDir}" "${outputBackupDir}" "${failure}" "${currentBackup}"; then
        SUBSCRIPTION_STATE_MAINTENANCE_ERROR="${failure}，已恢复旧状态、配置和订阅输出"
    else
        SUBSCRIPTION_STATE_MAINTENANCE_ERROR=${SUBSCRIPTION_SYNC_TRANSACTION_ERROR:-"${failure}，且本地数据恢复失败"}
        rollbackStatus=1
    fi
    if [[ "${wireGuardTransitionActive}" == "true" ]] ||
        [[ "${SUBSCRIPTION_WIREGUARD_GROUPS_TRANSITION_ACTIVE:-false}" == "true" ]]; then
        if ! subscriptionWireGuardRollbackGroupsTransition; then
            SUBSCRIPTION_STATE_MAINTENANCE_ERROR="${SUBSCRIPTION_STATE_MAINTENANCE_ERROR}；${SUBSCRIPTION_WIREGUARD_GROUPS_TRANSITION_ERROR:-旧来源恢复失败}"
            rollbackStatus=1
        fi
    fi
    if [[ "${SUBSCRIPTION_SYNC_CONFIG_RESTORED:-false}" == "true" ]] && ! subscriptionSyncReconcileLocalServices; then
        SUBSCRIPTION_STATE_MAINTENANCE_ERROR="${SUBSCRIPTION_STATE_MAINTENANCE_ERROR}；恢复旧配置后服务重建失败，请检查核心服务日志"
        rollbackStatus=1
    fi
    if ! cmp -s -- "${currentBackup}" "$(subscriptionGroupsFile)"; then
        SUBSCRIPTION_STATE_MAINTENANCE_ERROR="${SUBSCRIPTION_STATE_MAINTENANCE_ERROR}；旧状态恢复结果未通过校验"
        rollbackStatus=1
    fi
    if ! installUserCrontabContent "${previousCrontab}"; then
        SUBSCRIPTION_STATE_MAINTENANCE_ERROR="${SUBSCRIPTION_STATE_MAINTENANCE_ERROR}；旧定时任务恢复失败"
        rollbackStatus=1
    fi
    if ((rollbackStatus == 0)); then
        subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}"
    else
        subscriptionSyncReleaseLocalApplyBackups forget "${configBackupDir}" "${outputBackupDir}"
    fi
    return 1
}

restoreSubscriptionGroupsBackupMenu() {
    local backupFile
    local confirm=
    selectSubscriptionGroupsBackupFile || return 1
    backupFile=${selectedSubscriptionGroupsBackupFile}
    statusCard "即将恢复订阅状态" "目标备份：${backupFile}" "确认后会先备份当前状态、配置和订阅输出，再执行完整同步"
    autoRead subscription_restore_confirm "恢复会覆盖当前状态并重新同步。确认请输入 yes:" confirm
    if [[ "${confirm}" != "yes" ]]; then
        coreCancelledStatusCard "状态恢复未执行"
        return 1
    fi
    if ! subscriptionGroupsWithLock applySubscriptionGroupsStateMaintenanceUnlocked "${backupFile}" "恢复"; then
        errorCard "${SUBSCRIPTION_STATE_MAINTENANCE_ERROR:-状态恢复失败}" "恢复前状态备份：${SUBSCRIPTION_STATE_MAINTENANCE_BACKUP:-未创建}"
        return 1
    fi
    successCard "状态恢复完成" "恢复来源：${backupFile}" "恢复前状态备份：${SUBSCRIPTION_STATE_MAINTENANCE_BACKUP}"
}

resetSubscriptionGroupsStateMenu() {
    local stateFile
    local stageFile
    local confirm=
    ensureSubscriptionGroupsState || return 1
    showSubscriptionGroupsStateSummary || return 1
    statusCard "即将重建订阅状态" "这会把 groups.json 重置为默认空状态" "确认后会先备份当前状态、配置和订阅输出，再执行完整同步"
    autoRead subscription_reset_confirm "确认重建并重新同步请输入 yes:" confirm
    if [[ "${confirm}" != "yes" ]]; then
        coreCancelledStatusCard "订阅状态未重建"
        return 1
    fi
    stateFile=$(subscriptionGroupsFile)
    padmCreateTempFileForTarget stageFile "${stateFile}" reset || {
        errorCard "默认状态临时文件创建失败"
        return 1
    }
    writeDefaultSubscriptionGroupsState "${stageFile}" || {
        padmRemoveCleanupPath "${stageFile}"
        errorCard "默认状态生成失败"
        return 1
    }
    if ! subscriptionGroupsWithLock applySubscriptionGroupsStateMaintenanceUnlocked "${stageFile}" "重建"; then
        padmRemoveCleanupPath "${stageFile}"
        errorCard "${SUBSCRIPTION_STATE_MAINTENANCE_ERROR:-订阅状态重建失败}" "重建前状态备份：${SUBSCRIPTION_STATE_MAINTENANCE_BACKUP:-未创建}"
        return 1
    fi
    padmRemoveCleanupPath "${stageFile}"
    successCard "订阅状态已重建" "重建前状态备份：${SUBSCRIPTION_STATE_MAINTENANCE_BACKUP}"
}

manageSubscriptionStateBackups() {
    subscriptionRequireLocalPublisherRole || return 1
    local role returnText returnMenu=${1:-home}
    role=$(subscriptionCurrentRoleNormalized) || return 1
    if [[ "${returnMenu}" == "sync" ]]; then
        returnText="返回订阅同步"
    else
        [[ "${role}" == "main" ]] && returnText="返回主控首页" || returnText="返回本机订阅首页"
    fi
    while true; do
        echoContent title "\n┌─ 状态备份与恢复 ───────────────────────────────────"
        menuLine "这里只管理 groups.json 状态；恢复和重建都会先自动备份当前状态"
        menuItem 1 "查看当前状态摘要" "显示订阅用户、服务器源、同步状态和流量更新时间"
        menuItem 2 "创建状态备份" "保存当前 groups.json 到 backups 目录"
        menuItem 3 "恢复状态备份" "选择备份，确认后先备份当前状态再覆盖"
        menuDangerItem 4 "重建订阅状态" "确认后先备份当前状态，再重置为空的默认订阅组"
        menuReturnItem 5 "${returnText}" "回到上级菜单"
        menuClose
        autoRead subscription_state_backup_menu "请选择:" subscriptionStateBackupStatus
        case "${subscriptionStateBackupStatus}" in
        1) showSubscriptionGroupsStateSummary ;;
        2) createSubscriptionGroupsBackupMenu ;;
        3) restoreSubscriptionGroupsBackupMenu ;;
        4) resetSubscriptionGroupsStateMenu ;;
        5) return ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}
