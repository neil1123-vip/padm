#!/usr/bin/env bash

restoreXrayTrafficStatsConfigBackup() {
    local backupDir=$1
    checkLogBackupRestore "${backupDir}" >/dev/null 2>&1
}

failXrayTrafficStatsConfigChange() {
    local backupDir=$1
    local reason=$2
    local retryReload=${3:-false}

    if ! restoreXrayTrafficStatsConfigBackup "${backupDir}"; then
        padmForgetCleanupPath "${backupDir}"
        errorCard "${reason}，且旧配置恢复失败，请手动检查备份目录: ${backupDir}"
        return 1
    fi
    padmRemoveCleanupPath "${backupDir}"
    if [[ "${retryReload}" == "true" ]]; then
        if reloadCore; then
            errorCard "${reason}，已回滚流量统计配置"
        else
            errorCard "${reason}，已回滚流量统计配置；恢复旧配置后核心重载仍失败，请检查核心服务日志"
        fi
        return 1
    fi
    errorCard "${reason}，已回滚流量统计配置"
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
    local file
    local files=()
    while IFS= read -r file; do
        [[ -f "${file}" ]] && files+=("${file}")
    done < <(subscriptionSyncConfigFiles)
    [[ "${#files[@]}" -gt 0 ]] || return 0
    jq -r -s '
      [.[] | [.inbounds[]?.settings.clients[]?, .inbounds[]?.users[]?][]?
       | (.email // .name // .username // empty | split("-")[0])
       | select(length > 0)]
      | unique[]' "${files[@]}" 2>/dev/null
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
          def accountName($name): (($name | split(">>>"))[1] // "" | split("-")[0]);
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
            sub(/-.*/, "", name)
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
    local accountLines
    local items
    if ! accountLines=$(collectLocalTrafficAccounts); then
        jq -n '{ok:false, items: []}'
        return
    fi
    accounts=$(jq -R -s 'split("\n") | map(select(length > 0))' <<<"${accountLines}") || {
        jq -n '{ok:false, items: []}'
        return
    }
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
    local groupId
    if ! jq -e '.ok == true' <<<"${snapshot}" >/dev/null 2>&1; then
        statusCard "流量统计" "采集失败，已保留上次统计"
        return 1
    fi
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateWrite --arg groupId "${groupId}" --argjson snapshot "${snapshot}" '
      def addTraffic($items): reduce $items[] as $item ({upload:0, download:0}; .upload += ($item.upload // 0) | .download += ($item.download // 0));
      def sourceTotal($prev; $current):
        ($prev // {upload:0, download:0, counters:{}}) as $old |
        ($old.counters // {}) as $oldCounters |
        (reduce $current[] as $item ({upload:0, download:0, counters:{}};
          ($oldCounters[$item.account] // {upload:0, download:0}) as $counter |
          (($item.upload // 0) - ($counter.upload // 0)) as $uploadDelta |
          (($item.download // 0) - ($counter.download // 0)) as $downloadDelta |
          .upload += (if ($oldCounters | has($item.account)) and $uploadDelta > 0 then $uploadDelta else 0 end) |
          .download += (if ($oldCounters | has($item.account)) and $downloadDelta > 0 then $downloadDelta else 0 end) |
          .counters[$item.account] = {upload: ($item.upload // 0), download: ($item.download // 0)})) as $delta |
        {upload: (($old.upload // 0) + $delta.upload), download: (($old.download // 0) + $delta.download), counters: $delta.counters, updated_at: (now | strftime("%F %T"))};
      .groups |= map(if .id == $groupId then
        . as $group |
        ($snapshot.items | map(. + {id: ((.account | sub("^sub_"; "") | gsub("_"; "-")))})) as $items |
        ($items | map(select(.account | startswith("sub_")))) as $userItems |
        ($items | map(select((.account | startswith("sub_")) | not))) as $adminItems |
        (sourceTotal($group.traffic.sources.main; $items)) as $mainTraffic |
        (sourceTotal($group.traffic.admin.sources.main; $adminItems)) as $adminTraffic |
        (($group.traffic.sources // {}) | to_entries | map(select(.key != "main") | .value) | addTraffic(.)) as $remoteTraffic |
        .traffic.global = {upload: (($mainTraffic.upload // 0) + ($remoteTraffic.upload // 0)), download: (($mainTraffic.download // 0) + ($remoteTraffic.download // 0))} |
        .traffic.admin = (($group.traffic.admin // {}) + {upload: ($adminTraffic.upload // 0), download: ($adminTraffic.download // 0), sources: ((($group.traffic.admin.sources // {}) + {main: $adminTraffic}))}) |
        .traffic.user_groups = (reduce $group.user_groups[]? as $userGroup ({};
          ($userItems | map(select(.id == $userGroup.id))) as $groupItems |
          sourceTotal(($group.traffic.user_groups[$userGroup.id].sources.main // {}); $groupItems) as $groupTraffic |
          .[$userGroup.id] = (($group.traffic.user_groups[$userGroup.id] // {}) + {upload: ($groupTraffic.upload // 0), download: ($groupTraffic.download // 0), sources: ((($group.traffic.user_groups[$userGroup.id].sources // {}) + {main: $groupTraffic}))}))) |
        .traffic.sources = (($group.traffic.sources // {}) + {main: $mainTraffic})
      else . end)'
}

collectSubscriptionTraffic() {
    local snapshot
    ensureSubscriptionGroupsState
    readInstallType
    readInstallProtocolType
    if ! ensureXrayTrafficStatsConfig; then
        return 1
    fi
    snapshot=$(collectLocalTrafficSnapshot)
    if writeSubscriptionTrafficSnapshot "${snapshot}"; then
        successCard "流量统计已更新"
    else
        return 1
    fi
}

showUserSubscriptionQuotaStatus() {
    local userSubscriptionId=$1
    local groupId
    groupId=$(activeSubscriptionGroupId)
    ensureSubscriptionGroupsState
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" --arg id "${userSubscriptionId}" '
      .groups[] | select(.id == $groupId) |
      (.user_groups[]? | select(.id == $id)) as $userGroup |
      (.traffic.user_groups[$id] // {upload:0, download:0}) as $traffic |
      if ($userGroup.traffic_limit_gb // 0) <= 0 then
        "不限额"
      else
        ((($userGroup.traffic_limit_gb * 1024 * 1024 * 1024) | floor) as $limitBytes |
         (((($traffic.upload // 0) + ($traffic.download // 0)) * 100 / $limitBytes) | floor) as $percent |
         if $percent >= 100 then "已超限(" + ($percent | tostring) + "%)"
         elif $percent >= 80 then "接近上限(" + ($percent | tostring) + "%)"
         else "正常(" + ($percent | tostring) + "%)" end)
      end'
}

showUserSubscriptionQuota() {
    local userSubscriptionId=$1
    local groupId
    groupId=$(activeSubscriptionGroupId)
    ensureSubscriptionGroupsState
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" --arg id "${userSubscriptionId}" '
      .groups[] | select(.id == $groupId) |
      (.user_groups[]? | select(.id == $id)) as $userGroup |
      (.traffic.user_groups[$id] // {upload:0, download:0, sources:{}}) as $traffic |
      (((($traffic.upload // 0) + ($traffic.download // 0)) / 1024 / 1024) | floor) as $usedMb |
      "ID: \($userGroup.id)\n名称: \($userGroup.name)\n已用: \($usedMb) MB\n上限: \(if ($userGroup.traffic_limit_gb // 0) <= 0 then "不限" else (($userGroup.traffic_limit_gb | tostring) + " GB") end)\n状态: " +
      (if ($userGroup.traffic_limit_gb // 0) <= 0 then
        "不限额"
      else
        ((($userGroup.traffic_limit_gb * 1024 * 1024 * 1024) | floor) as $limitBytes |
         (((($traffic.upload // 0) + ($traffic.download // 0)) * 100 / $limitBytes) | floor) as $percent |
         if $percent >= 100 then "已超限(" + ($percent | tostring) + "%)"
         elif $percent >= 80 then "接近上限(" + ($percent | tostring) + "%)"
         else "正常(" + ($percent | tostring) + "%)" end)
      end)'
}

showAdminSubscriptionTraffic() {
    local groupId
    local traffic
    local summary
    groupId=$(activeSubscriptionGroupId)
    traffic=$(subscriptionGroupsStateRead -r --arg groupId "${groupId}" '.groups[] | select(.id == $groupId) | .traffic.admin')
    summary=$(jq -r '
      def mb($v): (((($v // 0) / 1024 / 1024) | floor) | tostring) + " MB";
      "总上传：" + mb(.upload) + "\n" +
      "总下载：" + mb(.download) + "\n" +
      "来源数：" + (((.sources // {}) | length) | tostring) + "\n" +
      "最近更新：" + (((.sources // {}) | to_entries | map(.value.updated_at // empty) | max) // (.updated_at // "未知") | tostring)
    ' <<<"${traffic}") || return 1
    showSubscriptionJsonWithSummary "我的流量" "${traffic}" "${summary}"
}

showUserSubscriptionTraffic() {
    local userSubscriptionId=$1
    local groupId
    local traffic
    groupId=$(activeSubscriptionGroupId)
    ensureSubscriptionGroupsState
    userResultCard "用户订阅流量"
    menuLine "用户订阅：${userSubscriptionId}"
    menuLine "限额状态：$(showUserSubscriptionQuotaStatus "${userSubscriptionId}")"
    traffic=$(subscriptionGroupsStateRead -r --arg groupId "${groupId}" --arg id "${userSubscriptionId}" '.groups[] | select(.id == $groupId) | .traffic.user_groups[$id] // {upload:0, download:0, sources:{}}')
    printf '%s\n' "${traffic}" | jq .
    menuClose
}

showSubscriptionTrafficOverview() {
    local groupId
    local output
    groupId=$(activeSubscriptionGroupId)
    ensureSubscriptionGroupsState
    output=$(subscriptionGroupsStateRead -r --arg groupId "${groupId}" '
      def mb($v): (((($v // 0) / 1024 / 1024) | floor) | tostring) + " MB";
      def used($traffic): (($traffic.upload // 0) + ($traffic.download // 0));
      def quota_status($user; $traffic):
        (($user.traffic_limit_gb // 0) | tonumber? // 0) as $limitGb |
        if $limitGb <= 0 then "不限额"
        else
          (($limitGb * 1024 * 1024 * 1024) | floor) as $limitBytes |
          ((used($traffic) * 100 / $limitBytes) | floor) as $percent |
          if $percent >= 100 then "已超限"
          elif $percent >= 80 then "接近上限"
          else "正常" end
        end;
      .groups[] | select(.id == $groupId) |
      . as $group |
      ($group.user_groups // []) as $users |
      [($users[]? | select(.enabled == true))] as $enabledUsers |
      [($users[]? | select(quota_status(.; $group.traffic.user_groups[.id] // {}) == "已超限"))] as $overLimit |
      [($users[]? | select(quota_status(.; $group.traffic.user_groups[.id] // {}) == "接近上限"))] as $nearLimit |
      "全局累计：上传 " + mb($group.traffic.global.upload) + " / 下载 " + mb($group.traffic.global.download) + "\n" +
      "分享订阅：共 " + (($users | length) | tostring) + " 个，启用 " + (($enabledUsers | length) | tostring) + " 个\n" +
      "限额状态：超限 " + (($overLimit | length) | tostring) + " 个，接近上限 " + (($nearLimit | length) | tostring) + " 个\n" +
      "服务器源：共 " + (($group.sources | length) | tostring) + " 个，启用远端 " + (([$group.sources[]? | select(.role != "main" and .enabled == true)] | length) | tostring) + " 个\n" +
      "最近同步：状态 " + (($group.sync.last_status // "pending") | tostring) + "，时间 " + (($group.sync.last_run // "未运行") | tostring) + "\n" +
      "流量更新时间：" + (($group.traffic.sources.main.updated_at // $group.traffic.admin.sources.main.updated_at // "未知") | tostring)')
    userResultCard "用量与限额总览"
    while IFS= read -r line; do
        menuLine "${line}"
    done <<<"${output}"
    menuClose
}


manageTrafficAndQuota() {
    while true; do
        echoContent title "\n┌─ 流量与限额 ───────────────────────────────────────"
        menuLine "这里是用量治理台：先刷新统计，再看总览、预览并执行超限处理"
        menuLine "订阅额度在 给别人开订阅 中设置；这里不编辑订阅对象，只处理运行状态"
        menuItem 1 "刷新并显示总览" "采集本机账号流量，写入 groups.json 后显示治理摘要"
        menuItem 2 "查看用量总览" "显示全局、分享订阅、服务器源和最近同步摘要"
        menuItem 3 "查看分享订阅限额概览" "列出全部分享订阅、额度和状态"
        menuItem 4 "查看单个分享订阅用量" "选择订阅后显示用量和额度状态"
        menuItem 5 "查看服务器流量" "显示各服务器源累计流量"
        menuItem 6 "预览超限处理" "查看将因超额而停用的分享订阅"
        menuDangerItem 7 "执行超限处理" "停用超额订阅并移除本机托管账号"
        menuReturnItem 8 "返回订阅与用户" "回到上级菜单"
        menuClose
        autoRead traffic_quota_menu "请选择:" trafficQuotaStatus
        case "${trafficQuotaStatus}" in
        1) collectSubscriptionTraffic && showSubscriptionTrafficOverview ;;
        2) showSubscriptionTrafficOverview ;;
        3) showUserSubscriptions ;;
        4) selectUserSubscriptionTrafficMenu ;;
        5) showSubscriptionSourcesTraffic ;;
        6) showSubscriptionQuotaPlan ;;
        7) executeSubscriptionQuotaPlanMenu ;;
        8) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

selectUserSubscriptionTrafficMenu() {
    local userSubscriptionId=
    showUserSubscriptions
    autoRead user_subscription_traffic_id "请输入用户订阅 ID:" userSubscriptionId
    if [[ -z "${userSubscriptionId}" ]] || ! userSubscriptionExists "${userSubscriptionId}"; then
        errorCard "用户订阅 ID 无效"
        return 1
    fi
    showUserSubscriptionTraffic "${userSubscriptionId}"
}

showSubscriptionSourcesTraffic() {
    local groupId
    local traffic
    local summary
    groupId=$(activeSubscriptionGroupId)
    traffic=$(subscriptionGroupsStateRead -r --arg groupId "${groupId}" '.groups[] | select(.id == $groupId) | .traffic.sources')
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
