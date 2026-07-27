#!/usr/bin/env bash

subscriptionGroupsStateSummaryJson() {
    local localOnly=false
    [[ "$(subscriptionCurrentRoleNormalized)" == "uninitialized" ]] && localOnly=true
    ensureSubscriptionGroupsState
    subscriptionActiveGroupRead --argjson localOnly "${localOnly}" '
      {
        group_id: .id,
        group_name: .name,
        subscription_users: (.user_groups | length),
        enabled_users: ([.user_groups[]? | select(.enabled == true)] | length),
        sources: ([.sources[]? | select(($localOnly | not) or .role == "main")] | length),
        enabled_remote_sources: (if $localOnly then 0 else ([.sources[]? | select(.role != "main" and .enabled == true)] | length) end),
        sync: .sync,
        traffic_updated_at: ((.traffic.sources.main.updated_at // .traffic.admin.sources.main.updated_at // "") | if . == "" then "unknown" else . end)
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

printSubscriptionGroupsBackups() {
    local index=1
    local backupFile
    local found=
    while IFS= read -r backupFile; do
        [[ -n "${backupFile}" ]] || continue
        found=true
        menuLine "${index}. ${backupFile}"
        index=$((index + 1))
    done < <(listSubscriptionGroupsBackups | sort)
    [[ -n "${found}" ]]
}

showSubscriptionGroupsBackups() {
    userResultCard "订阅状态备份"
    if ! printSubscriptionGroupsBackups; then
        menuLine "暂无备份"
    fi
    menuClose
}

selectSubscriptionGroupsBackupFile() {
    local backupChoice=
    local backupFile=
    local backups=()
    local index
    selectedSubscriptionGroupsBackupFile=
    mapfile -t backups < <(listSubscriptionGroupsBackups | sort)
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

restoreSubscriptionGroupsBackupMenu() {
    local backupFile
    local currentBackup
    local confirm=
    selectSubscriptionGroupsBackupFile || return 1
    backupFile=${selectedSubscriptionGroupsBackupFile}
    currentBackup=$(createSubscriptionGroupsBackup) || {
        errorCard "恢复前备份当前状态失败，已取消恢复"
        return 1
    }
    statusCard "即将恢复订阅状态" "目标备份：${backupFile}" "当前状态已先备份到：${currentBackup}"
    autoRead subscription_restore_confirm "恢复会覆盖当前 groups.json。确认请输入 yes:" confirm
    if [[ "${confirm}" != "yes" ]]; then
        coreCancelledStatusCard "状态恢复未执行"
        return 1
    fi
    restoreSubscriptionGroupsBackup "${backupFile}" || {
        errorCard "状态恢复失败" "当前状态备份：${currentBackup}"
        return 1
    }
    successCard "状态恢复完成" "恢复来源：${backupFile}" "恢复前备份：${currentBackup}"
}

resetSubscriptionGroupsStateMenu() {
    local stateFile
    local stageFile
    local currentBackup
    local rollbackFailed=false
    local confirm=
    ensureSubscriptionGroupsState
    showSubscriptionGroupsStateSummary
    currentBackup=$(createSubscriptionGroupsBackup) || {
        errorCard "重建前备份当前状态失败，已取消重建"
        return 1
    }
    statusCard "即将重建订阅状态" "这会把 groups.json 重置为默认空状态" "当前状态已先备份到：${currentBackup}" "升级或打开菜单不会自动执行此操作"
    autoRead subscription_reset_confirm "确认重建请输入 yes:" confirm
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
    if ! subscriptionGroupsStateReplace "${stageFile}" "${stateFile}"; then
        padmRemoveCleanupPath "${stageFile}"
        errorCard "订阅状态重建失败" "当前状态备份：${currentBackup}"
        return 1
    fi
    padmRemoveCleanupPath "${stageFile}"
    if ! migrateSubscriptionGroupsState; then
        local restoreMessage
        if ! subscriptionGroupsStateReplace "${currentBackup}" "${stateFile}"; then
            rollbackFailed=true
        fi
        if [[ "${rollbackFailed}" == "true" ]]; then
            subscriptionSyncSetSingleRestoreResultMessage restoreMessage "订阅状态重建失败" false "" "旧状态" "" false || true
            errorCard "${restoreMessage}" "当前状态备份：${currentBackup}"
            return 1
        fi
        local rollbackMessage
        subscriptionSyncSetRollbackResultMessage rollbackMessage "订阅状态重建失败" "已恢复旧状态"
        errorCard "${rollbackMessage}" "当前状态备份：${currentBackup}"
        return 1
    fi
    if declare -F subscriptionGroupsSecureStateFiles >/dev/null 2>&1; then
        subscriptionGroupsSecureStateFiles 2>/dev/null || return 1
    fi
    successCard "订阅状态已重建" "重建前备份：${currentBackup}"
}

manageSubscriptionStateBackups() {
    subscriptionRequireLocalPublisherRole || return 1
    while true; do
        echoContent title "\n┌─ 状态备份与恢复 ───────────────────────────────────"
        menuLine "这里只管理 groups.json 状态；恢复和重建都会先自动备份当前状态"
        menuItem 1 "查看当前状态摘要" "显示订阅用户、服务器源、同步状态和流量更新时间"
        menuItem 2 "创建状态备份" "保存当前 groups.json 到 backups 目录"
        menuItem 3 "查看已有备份" "列出可恢复的备份文件"
        menuItem 4 "恢复状态备份" "先备份当前状态，再用选定备份覆盖"
        menuDangerItem 5 "重建订阅状态" "先备份当前状态，再重置为空的默认订阅组"
        menuReturnItem 6 "返回主控维护与排障" "回到上级菜单"
        menuClose
        autoRead subscription_state_backup_menu "请选择:" subscriptionStateBackupStatus
        case "${subscriptionStateBackupStatus}" in
        1) showSubscriptionGroupsStateSummary ;;
        2) createSubscriptionGroupsBackupMenu ;;
        3) showSubscriptionGroupsBackups ;;
        4) restoreSubscriptionGroupsBackupMenu ;;
        5) resetSubscriptionGroupsStateMenu ;;
        6) return ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}
