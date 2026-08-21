#!/usr/bin/env bash

restoreXrayTrafficStatsConfigBackup() {
    local backupDir=$1
    checkLogBackupRestore "${backupDir}" >/dev/null 2>&1
}

failXrayTrafficStatsConfigChange() {
    local backupDir=$1
    local reason=$2
    local retryReload=${3:-false}
    local restoreMessage
    local rollbackMessage

    if ! restoreXrayTrafficStatsConfigBackup "${backupDir}"; then
        padmForgetCleanupPath "${backupDir}"
        subscriptionSyncSetSingleRestoreResultMessage restoreMessage "${reason}" false "已恢复旧配置" "旧配置" "备份目录: ${backupDir}" || true
        errorCard "${restoreMessage}"
        return 1
    fi
    padmRemoveCleanupPath "${backupDir}"
    if [[ "${retryReload}" == "true" ]]; then
        subscriptionSyncSetRollbackResultMessage rollbackMessage "${reason}" "已回滚流量统计配置" reloadCore "恢复旧配置后核心重载仍失败，请检查核心服务日志"
        errorCard "${rollbackMessage}"
        return 1
    fi
    subscriptionSyncSetRollbackResultMessage rollbackMessage "${reason}" "已回滚流量统计配置"
    errorCard "${rollbackMessage}"
    return 1
}

ensureXrayTrafficStatsConfig() {
    local xrayConfigPath=${configPath:-/etc/padm/xray/conf/}
    local statsConfig=${xrayConfigPath}13_stats_api.json
    local policyConfig=${xrayConfigPath}12_policy.json
    local tmpFile
    local policyTmp
    local trafficBackupDir
    local changed=
    [[ "${coreInstallType}" == "1" && -d "${xrayConfigPath}" ]] || return 0
    checkLogBackupCreate trafficBackupDir "${statsConfig}" "${policyConfig}" || {
        errorCard "Xray 流量统计配置备份失败，已取消更新"
        return 1
    }
    padmCreateTempFileForTarget tmpFile "${statsConfig}" stats || {
        failXrayTrafficStatsConfigChange "${trafficBackupDir}" "Xray 流量统计 stats 临时文件创建失败"
        return 1
    }
    if ! cat <<EOF >"${tmpFile}"
{
  "stats": {},
  "api": {
    "tag": "api",
    "services": [
      "StatsService"
    ]
  },
  "inbounds": [
    {
      "tag": "api",
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      }
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": [
          "api"
        ],
        "outboundTag": "api"
      }
    ]
  }
}
EOF
    then
        padmRemoveCleanupPath "${tmpFile}"
        failXrayTrafficStatsConfigChange "${trafficBackupDir}" "Xray 流量统计 stats 配置生成失败"
        return 1
    fi
    if [[ -f "${statsConfig}" ]] && cmp -s "${tmpFile}" "${statsConfig}"; then
        padmRemoveCleanupPath "${tmpFile}"
    else
        commitGeneratedJsonFile "${tmpFile}" "${statsConfig}" || {
            padmRemoveCleanupPath "${tmpFile}"
            failXrayTrafficStatsConfigChange "${trafficBackupDir}" "Xray 流量统计 stats 配置写入失败"
            return 1
        }
        changed=true
    fi

    if [[ ! -f "${policyConfig}" ]]; then
        padmCreateTempFileForTarget policyTmp "${policyConfig}" policy || {
            failXrayTrafficStatsConfigChange "${trafficBackupDir}" "Xray 流量统计策略默认配置临时文件创建失败"
            return 1
        }
        if ! cat <<EOF >"${policyTmp}"
{
  "policy": {
    "levels": {
      "0": {}
    },
    "system": {}
  }
}
EOF
        then
            padmRemoveCleanupPath "${policyTmp}"
            failXrayTrafficStatsConfigChange "${trafficBackupDir}" "Xray 流量统计策略默认配置生成失败"
            return 1
        fi
        commitGeneratedJsonFile "${policyTmp}" "${policyConfig}" || {
            padmRemoveCleanupPath "${policyTmp}"
            failXrayTrafficStatsConfigChange "${trafficBackupDir}" "Xray 流量统计策略默认配置写入失败"
            return 1
        }
        changed=true
    fi
    padmCreateTempFileForTarget policyTmp "${policyConfig}" policy || {
        failXrayTrafficStatsConfigChange "${trafficBackupDir}" "Xray 流量统计策略配置临时文件创建失败"
        return 1
    }
    if ! jq '
      .policy.levels["0"].statsUserUplink = true |
      .policy.levels["0"].statsUserDownlink = true |
      .policy.system.statsInboundUplink = true |
      .policy.system.statsInboundDownlink = true |
      .policy.system.statsOutboundUplink = true |
      .policy.system.statsOutboundDownlink = true
    ' "${policyConfig}" >"${policyTmp}"; then
        padmRemoveCleanupPath "${policyTmp}"
        failXrayTrafficStatsConfigChange "${trafficBackupDir}" "Xray 流量统计策略配置生成失败"
        return 1
    fi
    if cmp -s "${policyTmp}" "${policyConfig}"; then
        padmRemoveCleanupPath "${policyTmp}"
    else
        commitGeneratedJsonFile "${policyTmp}" "${policyConfig}" || {
            padmRemoveCleanupPath "${policyTmp}"
            failXrayTrafficStatsConfigChange "${trafficBackupDir}" "Xray 流量统计策略配置写入失败"
            return 1
        }
        changed=true
    fi

    if [[ -n "${changed}" && -n "${configPath}" ]]; then
        if ! reloadCore; then
            failXrayTrafficStatsConfigChange "${trafficBackupDir}" "Xray 流量统计配置更新后核心重载失败" true
            return 1
        fi
    fi
    padmRemoveCleanupPath "${trafficBackupDir}"
}

collectLocalTrafficAccounts() {
    subscriptionSyncConfiguredAccountNamesJson 2>/dev/null
}

collectXrayTrafficStatsSnapshot() {
    local accounts=$1
    local stats=
    local xrayBinary=${XRAY_STATS_BINARY:-/etc/padm/xray/xray}
    if [[ ! -x "${xrayBinary}" ]]; then
        return 1
    fi
    if ! stats=$("${xrayBinary}" api statsquery --server=127.0.0.1:10085 -pattern user 2>/dev/null); then
        return 1
    fi
    if [[ -z "${stats}" ]]; then
        return 1
    fi
    if jq empty <<<"${stats}" >/dev/null 2>&1; then
        jq --argjson accounts "${accounts}" '
          def accountName($name): (($name | split(">>>"))[1] // "" | sub("-(uplink|downlink)$"; ""));
          def direction($name): if ($name | contains("downlink")) then "download" else "upload" end;
          def emptyTotals: reduce $accounts[] as $account ({}; .[$account] = {account:$account, upload:0, download:0});
          (reduce .stat[]? as $stat (emptyTotals;
            (accountName($stat.name // "")) as $account |
            if has($account) then
              .[$account][direction($stat.name // "")] += (($stat.value // 0) | tonumber? // 0)
            else
              .
            end)) as $totals |
          $accounts | map(. as $account | $totals[$account])
        ' <<<"${stats}"
    else
        awk -v accounts="$(jq -r 'join(" ")' <<<"${accounts}")" '
          BEGIN {
            split(accounts, allowed, " ")
            for (i in allowed) wanted[allowed[i]] = 1
          }
          /name:/ {
            name = $0
            sub(/^.*user>>>/, "", name)
            sub(/-(uplink|downlink)$/, "", name)
            account = name
            direction = ($0 ~ /downlink/) ? "download" : "upload"
          }
          /value: / {
            if (wanted[account]) totals[account SUBSEP direction] += $2
          }
          END {
            printf "["
            first = 1
            for (i in allowed) {
              account = allowed[i]
              if (account == "") continue
              if (!first) printf ","
              first = 0
              printf "{\"account\":\"%s\",\"upload\":%d,\"download\":%d}", account, totals[account SUBSEP "upload"] + 0, totals[account SUBSEP "download"] + 0
            }
            printf "]"
          }' <<<"${stats}"
    fi
}

collectLocalTrafficSnapshot() {
    local accounts
    local items
    if ! accounts=$(collectLocalTrafficAccounts); then
        jq -n '{ok:false, items: []}'
        return
    fi
    if [[ "$(jq 'length' <<<"${accounts}")" == "0" ]]; then
        jq -n '{ok:true, items: []}'
        return
    fi
    if items=$(collectXrayTrafficStatsSnapshot "${accounts}"); then
        jq -n --argjson items "${items}" '{ok:true, items:$items}'
    else
        jq -n '{ok:false, items: []}'
    fi
}

writeSubscriptionTrafficSnapshot() {
    local snapshot=$1
    local remoteResults=${2:-[]}
    if ! jq -e '.ok == true and (.items | type == "array")' <<<"${snapshot}" >/dev/null 2>&1 ||
        ! jq -e '
          type == "array" and
          ([.[].source_id] | length) == ([.[].source_id] | unique | length) and
          all(.[];
            (.source_id | type == "string" and length > 0) and
            (.status | type == "string" and length > 0) and
            (if .status == "success" then (.response.items | type == "array") else true end))
        ' <<<"${remoteResults}" >/dev/null 2>&1; then
        statusCard "流量统计" "采集失败，已保留上次统计"
        return 1
    fi
    subscriptionActiveGroupWrite --argjson snapshot "${snapshot}" --argjson remoteResults "${remoteResults}" '
      def sourceTotal($prev; $current):
        ($prev // {upload:0, download:0, counters:{}}) as $old |
        if ($current | length) == 0 then $old
        else
          ($old.counters // {}) as $oldCounters |
          (reduce $current[] as $item ({upload:0, download:0, counters:{}};
            ($oldCounters[$item.account] // {upload:0, download:0}) as $counter |
            (($item.upload // 0) - ($counter.upload // 0)) as $uploadDelta |
            (($item.download // 0) - ($counter.download // 0)) as $downloadDelta |
            .upload += (if ($oldCounters | has($item.account)) then (if $uploadDelta >= 0 then $uploadDelta else ($item.upload // 0) end) else ($item.upload // 0) end) |
            .download += (if ($oldCounters | has($item.account)) then (if $downloadDelta >= 0 then $downloadDelta else ($item.download // 0) end) else ($item.download // 0) end) |
            .counters[$item.account] = {upload: ($item.upload // 0), download: ($item.download // 0)})) as $delta |
          {upload: (($old.upload // 0) + $delta.upload), download: (($old.download // 0) + $delta.download), counters: $delta.counters, updated_at: (now | strftime("%F %T"))}
        end;
      def mapped($items; $accountIdMap): $items | map(. + {id: ($accountIdMap[.account] // .account)});
      def keepSources($map; $ids):
        ($map // {}) | with_entries(. as $entry | select(($ids | index($entry.key)) != null));
      . as $group |
      ($group.sources | map(.id)) as $sourceIds |
      ($group.user_groups | map({key:(.id | '"${SUBSCRIPTION_SYNC_ACCOUNT_NAME_FROM_ID_JQ}"'), value:.id}) | from_entries) as $accountIdMap |
      (mapped($snapshot.items; $accountIdMap)) as $items |
      ($items | map(select(.account | startswith("sub_")))) as $userItems |
      ($items | map(select((.account | startswith("sub_")) | not))) as $adminItems |
      (sourceTotal($group.traffic.sources.main; $items)) as $mainTraffic |
      (sourceTotal($group.traffic.admin.sources.main; $adminItems)) as $mainAdminTraffic |
      ($remoteResults | map(select(.status == "success") | . as $result | select(($sourceIds | index($result.source_id)) != null) | {source_id:$result.source_id, items:mapped($result.response.items; $accountIdMap)})) as $remote |
      ($remote | map(. as $result | {key:$result.source_id, value:sourceTotal($group.traffic.sources[$result.source_id]; $result.items)}) | from_entries) as $remoteSourceTraffic |
      (keepSources($group.traffic.sources; $sourceIds) + {main:$mainTraffic} + $remoteSourceTraffic) as $sourceTraffic |
      ($remote | map(. as $result | {key:$result.source_id, value:sourceTotal($group.traffic.admin.sources[$result.source_id]; ($result.items | map(select(.account | startswith("sub_") | not))))}) | from_entries) as $remoteAdminSourceTraffic |
      (keepSources($group.traffic.admin.sources; $sourceIds) + {main:$mainAdminTraffic} + $remoteAdminSourceTraffic) as $adminSourceTraffic |
      ($group.user_groups | map(
        . as $user |
        (sourceTotal(($group.traffic.user_groups[$user.id].sources.main // {}); ($userItems | map(select(.id == $user.id))))) as $mainUserTraffic |
        ($remote | map(. as $result | {key:$result.source_id, value:sourceTotal($group.traffic.user_groups[$user.id].sources[$result.source_id]; ($result.items | map(select(.id == $user.id))))}) | from_entries) as $remoteUserSourceTraffic |
        (keepSources($group.traffic.user_groups[$user.id].sources; $sourceIds) + {main:$mainUserTraffic} + $remoteUserSourceTraffic) as $userSourceTraffic |
        {key:$user.id, value:{sources:$userSourceTraffic}}
      ) | from_entries) as $userTraffic |
      .traffic.admin = {sources:$adminSourceTraffic} |
      .traffic.user_groups = $userTraffic |
      .traffic.sources = $sourceTraffic
    '
}

collectSubscriptionTraffic() {
    local snapshot
    local remoteResults='[]'
    local role
    ensureSubscriptionGroupsState || return 1
    readInstallType
    readInstallProtocolType
    if ! ensureXrayTrafficStatsConfig; then
        return 1
    fi
    snapshot=$(collectLocalTrafficSnapshot)
    role=$(subscriptionCurrentRoleNormalized) || return 1
    if [[ "${role}" == "main" ]] && subscriptionHasEnabledRemoteSources; then
        remoteResults=$(subscriptionRemoteTrafficAll) || return 1
    fi
    if writeSubscriptionTrafficSnapshot "${snapshot}" "${remoteResults}"; then
        successCard "流量统计已更新"
    else
        return 1
    fi
}

subscriptionUserQuotaStatusJq() {
    cat <<'EOF'
def subscriptionUserQuotaStatus($user; $traffic; $showPercent):
  (($user.traffic_limit_gb // 0) | tonumber? // 0) as $limitGb |
  if $limitGb <= 0 then "不限额"
  else
    (($limitGb * 1024 * 1024 * 1024) | floor) as $limitBytes |
    (((($traffic.upload // 0) + ($traffic.download // 0)) * 100 / $limitBytes) | floor) as $percent |
    if $percent >= 100 then "已超限"
    elif $percent >= 80 then "接近上限"
    else "正常" end
    + (if $showPercent then "(" + ($percent | tostring) + "%)" else "" end)
  end;
EOF
}

showAdminSubscriptionTraffic() {
    local traffic
    local summary
    traffic=$(subscriptionActiveGroupRead -r '.traffic.admin') || return 1
    summary=$(jq -r '
      def mb($v): (((($v // 0) / 1024 / 1024) | floor) | tostring) + " MB";
      (.sources // {}) as $sources |
      "总上传：" + mb([$sources[]?.upload] | add // 0) + "\n" +
      "总下载：" + mb([$sources[]?.download] | add // 0) + "\n" +
      "来源数：" + (((.sources // {}) | length) | tostring) + "\n" +
      "最近更新：" + (((.sources // {}) | to_entries | map(.value.updated_at // empty) | max) // (.updated_at // "未知") | tostring)
    ' <<<"${traffic}") || return 1
    showSubscriptionJsonWithSummary "我的流量" "${traffic}" "${summary}"
}

showUserSubscriptionTraffic() {
    local userSubscriptionId=$1
    local traffic
    local quotaStatus
    local jqProgram
    local quotaStatusJq
    ensureSubscriptionGroupsState || return 1
    quotaStatusJq=$(subscriptionUserQuotaStatusJq) || return 1
    jqProgram=$(printf '%s\n%s\n%s\n' "$(subscriptionTrafficTotalsJq)" "${quotaStatusJq}" '
      (.user_groups[]? | select(.id == $id)) as $userGroup |
      (subscriptionTrafficTotal((.traffic.user_groups[$id] // {}).sources)) as $traffic |
      subscriptionUserQuotaStatus($userGroup; $traffic; true)')
    quotaStatus=$(subscriptionActiveGroupRead -r --arg id "${userSubscriptionId}" "${jqProgram}") || return 1
    userResultCard "用户订阅流量"
    menuLine "用户订阅：${userSubscriptionId}"
    menuLine "限额状态：${quotaStatus}"
    traffic=$(subscriptionActiveGroupRead -r --arg id "${userSubscriptionId}" '.traffic.user_groups[$id] // {sources:{}}')
    printf '%s\n' "${traffic}" | jq .
    menuClose
}

showSubscriptionTrafficOverview() {
    local output
    local jqProgram
    local quotaStatusJq
    quotaStatusJq=$(subscriptionUserQuotaStatusJq) || return 1
    ensureSubscriptionGroupsState || return 1
    jqProgram=$(printf '%s\n%s\n%s\n' "$(subscriptionTrafficTotalsJq)" "${quotaStatusJq}" '
      def mb($v): (((($v // 0) / 1024 / 1024) | floor) | tostring) + " MB";
      . as $group |
      (subscriptionTrafficTotal($group.traffic.sources)) as $globalTraffic |
      ($group.user_groups // []) as $users |
      [($users[]? | select(.enabled == true))] as $enabledUsers |
      [($users[]? | select(subscriptionUserQuotaStatus(.; subscriptionTrafficTotal(($group.traffic.user_groups[.id] // {}).sources); false) == "已超限"))] as $overLimit |
      [($users[]? | select(subscriptionUserQuotaStatus(.; subscriptionTrafficTotal(($group.traffic.user_groups[.id] // {}).sources); false) == "接近上限"))] as $nearLimit |
      "全局累计：上传 " + mb($globalTraffic.upload) + " / 下载 " + mb($globalTraffic.download) + "\n" +
      "分享订阅：共 " + (($users | length) | tostring) + " 个，启用 " + (($enabledUsers | length) | tostring) + " 个\n" +
      "限额状态：超限 " + (($overLimit | length) | tostring) + " 个，接近上限 " + (($nearLimit | length) | tostring) + " 个\n" +
      "服务器源：共 " + (($group.sources | length) | tostring) + " 个，启用远端 " + (([$group.sources[]? | select(.role != "main" and .enabled == true)] | length) | tostring) + " 个\n" +
      "最近同步：状态 " + (($group.sync.last_status // "pending") | tostring) + "，时间 " + (($group.sync.last_run // "未运行") | tostring) + "\n" +
      "流量更新时间：" + (((($group.traffic.sources // {}) | to_entries | map(.value.updated_at // empty) | max) // "未知") | tostring)')
    output=$(subscriptionActiveGroupRead -r "${jqProgram}") || return 1
    userResultCard "用量与限额总览"
    while IFS= read -r line; do
        menuLine "${line}"
    done <<<"${output}"
    menuClose
}


manageTrafficAndQuota() {
    subscriptionRequireLocalPublisherRole || return 1
    local role
    local returnText
    local quotaAutoApplyText
    role=$(subscriptionCurrentRoleNormalized) || return 1
    [[ "${role}" == "main" ]] && returnText="返回主控订阅同步" || returnText="返回本机订阅同步"
    while true; do
        subscriptionGroupQuotaAutoApplyEnabled && quotaAutoApplyText="开启" || quotaAutoApplyText="关闭"
        echoContent title "\n┌─ 流量与限额 ───────────────────────────────────────"
        menuLine "这里是用量治理台：先刷新统计，再查看用量或执行超限处理"
        menuLine "订阅额度在新建或已有订阅中设置；这里不编辑订阅对象，只处理运行状态"
        menuLine "自动执行超限处理：${quotaAutoApplyText}"
        menuItem 1 "刷新并显示总览" "采集本机账号流量，写入 groups.json 后显示治理摘要"
        menuItem 2 "查看用量总览" "显示全局、分享订阅、服务器源和最近同步摘要"
        menuItem 3 "查看我的流量" "查看自用账号在各服务器源的累计流量"
        menuItem 4 "查看分享订阅限额概览" "列出全部分享订阅、额度和状态"
        menuItem 5 "查看单个分享订阅用量" "选择订阅后显示用量和额度状态"
        menuItem 6 "查看服务器流量" "显示各服务器源累计流量"
        menuDangerItem 7 "执行超限处理" "停用超额订阅并移除本机托管账号"
        menuItem 8 "开启/关闭自动执行超限处理" "切换同步前的自动限额事务"
        menuReturnItem 9 "${returnText}" "回到上级菜单"
        menuClose
        autoRead traffic_quota_menu "请选择:" trafficQuotaStatus
        case "${trafficQuotaStatus}" in
        1) collectSubscriptionTraffic && showSubscriptionTrafficOverview ;;
        2) showSubscriptionTrafficOverview ;;
        3) showAdminSubscriptionTraffic ;;
        4) showUserSubscriptions ;;
        5) selectUserSubscriptionTrafficMenu ;;
        6) showSubscriptionSourcesTraffic ;;
        7) executeSubscriptionQuotaPlanMenu ;;
        8) toggleSubscriptionGroupQuotaAutoApplyEnabled && successCard "限额自动执行状态已切换" || errorCard "限额自动执行状态切换失败" ;;
        9) return ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}

selectUserSubscriptionTrafficMenu() {
    local userSubscriptionId=
    showUserSubscriptions || return 1
    autoRead user_subscription_traffic_id "请输入用户订阅 ID:" userSubscriptionId
    if [[ -z "${userSubscriptionId}" ]] || ! userSubscriptionExists "${userSubscriptionId}"; then
        errorCard "用户订阅 ID 无效"
        return 1
    fi
    showUserSubscriptionTraffic "${userSubscriptionId}"
}

showSubscriptionSourcesTraffic() {
    local traffic
    local summary
    traffic=$(subscriptionActiveGroupRead -r '.traffic.sources') || return 1
    summary=$(jq -r '
      def mb($v): (((($v // 0) / 1024 / 1024) | floor) | tostring) + " MB";
      def total($items): reduce $items[] as $item ({upload:0, download:0}; .upload += ($item.upload // 0) | .download += ($item.download // 0));
      (. // {}) as $sources |
      (total($sources | to_entries | map(.value))) as $total |
      "服务器数：" + (($sources | length) | tostring) + "\n" +
      "总上传：" + mb($total.upload) + "\n" +
      "总下载：" + mb($total.download) + "\n" +
      "最近更新：" + (($sources | to_entries | map(.value.updated_at // empty) | max) // "未知" | tostring)
    ' <<<"${traffic}") || return 1
    showSubscriptionJsonWithSummary "服务器流量" "${traffic}" "${summary}"
}
