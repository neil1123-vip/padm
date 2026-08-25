#!/usr/bin/env bash

restoreTrafficStatsConfigBackup() {
    local backupDir=$1
    checkLogBackupRestore "${backupDir}" >/dev/null 2>&1
}

failTrafficStatsConfigChange() {
    local backupDir=$1
    local reason=$2
    local retryReload=${3:-false}
    local restoreMessage
    local rollbackMessage

    if ! restoreTrafficStatsConfigBackup "${backupDir}"; then
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
    local statsChanged=false
    local policyChanged=false
    [[ "${coreInstallType}" == "1" && -d "${xrayConfigPath}" ]] || return 0
    padmCreateTempFileForTarget tmpFile "${statsConfig}" stats || {
        errorCard "Xray 流量统计 stats 临时文件创建失败"
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
        errorCard "Xray 流量统计 stats 配置生成失败"
        return 1
    fi
    padmCreateTempFileForTarget policyTmp "${policyConfig}" policy || {
        padmRemoveCleanupPath "${tmpFile}"
        errorCard "Xray 流量统计策略配置临时文件创建失败"
        return 1
    }
    if [[ -f "${policyConfig}" ]]; then
        if ! jq '
          .policy.levels["0"].statsUserUplink = true |
          .policy.levels["0"].statsUserDownlink = true
        ' "${policyConfig}" >"${policyTmp}"; then
            padmRemoveCleanupPath "${tmpFile}"
            padmRemoveCleanupPath "${policyTmp}"
            errorCard "Xray 流量统计策略配置生成失败"
            return 1
        fi
    else
        if ! jq -n '
          {policy:{levels:{"0":{}}, system:{}}} |
          .policy.levels["0"].statsUserUplink = true |
          .policy.levels["0"].statsUserDownlink = true
        ' >"${policyTmp}"; then
            padmRemoveCleanupPath "${tmpFile}"
            padmRemoveCleanupPath "${policyTmp}"
            errorCard "Xray 流量统计策略配置生成失败"
            return 1
        fi
    fi

    if [[ ! -f "${statsConfig}" ]] || ! cmp -s "${tmpFile}" "${statsConfig}"; then
        statsChanged=true
    fi
    if [[ ! -f "${policyConfig}" ]] || ! cmp -s "${policyTmp}" "${policyConfig}"; then
        policyChanged=true
    fi
    if [[ "${statsChanged}" != "true" && "${policyChanged}" != "true" ]]; then
        padmRemoveCleanupPath "${tmpFile}"
        padmRemoveCleanupPath "${policyTmp}"
        return 0
    fi

    checkLogBackupCreate trafficBackupDir "${statsConfig}" "${policyConfig}" || {
        padmRemoveCleanupPath "${tmpFile}"
        padmRemoveCleanupPath "${policyTmp}"
        errorCard "Xray 流量统计配置备份失败，已取消更新"
        return 1
    }
    if [[ "${statsChanged}" == "true" ]]; then
        commitGeneratedJsonFile "${tmpFile}" "${statsConfig}" || {
            padmRemoveCleanupPath "${tmpFile}"
            padmRemoveCleanupPath "${policyTmp}"
            failTrafficStatsConfigChange "${trafficBackupDir}" "Xray 流量统计 stats 配置写入失败"
            return 1
        }
    else
        padmRemoveCleanupPath "${tmpFile}"
    fi
    if [[ "${policyChanged}" == "true" ]]; then
        commitGeneratedJsonFile "${policyTmp}" "${policyConfig}" || {
            padmRemoveCleanupPath "${policyTmp}"
            failTrafficStatsConfigChange "${trafficBackupDir}" "Xray 流量统计策略配置写入失败"
            return 1
        }
    else
        padmRemoveCleanupPath "${policyTmp}"
    fi

    if [[ -n "${configPath:-}" ]]; then
        if ! reloadCore; then
            failTrafficStatsConfigChange "${trafficBackupDir}" "Xray 流量统计配置更新后核心重载失败" true
            return 1
        fi
    fi
    padmRemoveCleanupPath "${trafficBackupDir}"
}

trafficStatsAccountConfigFiles() {
    local resultVar=$1
    local core=$2
    local configDir=$3
    local -n resultRef=${resultVar}
    local fileName
    local registry
    resultRef=()
    registry=$(protocolCapabilityRegistry) || return 1
    while IFS= read -r fileName; do
        [[ -f "${configDir}${fileName}" ]] && resultRef+=("${configDir}${fileName}")
    done < <(awk -F'|' -v core="${core}" '$3 == "node" && index("," $6 ",", "," core ",") && $19 != "" { print $19 }' <<<"${registry}")
    return 0
}

collectSingBoxTrafficUsers() {
    local configDir=${1:-}
    local -a configFiles=()
    if [[ -z "${configDir}" ]]; then
        configDir=$(subscriptionSyncSafeSingBoxConfigDir) || return 1
    fi
    trafficStatsAccountConfigFiles configFiles sing-box "${configDir}" || return 1
    if ((${#configFiles[@]} == 0)); then
        printf '[]\n'
        return 0
    fi
    jq -cs '[.[] | .inbounds[]?.users[]? | (.name // .username // .email // "") | select(type == "string" and length > 0)] | unique' "${configFiles[@]}"
}

ensureSingBoxTrafficStatsConfig() {
    local configDir
    local statsConfig
    local mergedConfig
    local tmpFile
    local trafficBackupDir
    local users
    [[ -n "${singBoxConfigPath:-}" ]] || return 0
    configDir=$(subscriptionSyncSafeSingBoxConfigDir) || {
        errorCard "sing-box 流量统计配置目录不可用"
        return 1
    }
    [[ -d "${configDir}" ]] || return 0
    statsConfig=${configDir}14_stats_api.json
    mergedConfig=$(singBoxMergedConfigFile) || return 1
    users=$(collectSingBoxTrafficUsers "${configDir}") || {
        errorCard "sing-box 流量统计用户读取失败"
        return 1
    }
    padmCreateTempFileForTarget tmpFile "${statsConfig}" stats || {
        errorCard "sing-box 流量统计临时文件创建失败"
        return 1
    }
    if ! jq -n --argjson users "${users}" '{experimental:{v2ray_api:{listen:"127.0.0.1:10087",stats:{enabled:true,users:$users}}}}' >"${tmpFile}"; then
        padmRemoveCleanupPath "${tmpFile}"
        errorCard "sing-box 流量统计配置生成失败"
        return 1
    fi
    if [[ -f "${statsConfig}" ]] && cmp -s "${tmpFile}" "${statsConfig}" &&
        jq -e --argjson users "${users}" '
          .experimental.v2ray_api.listen == "127.0.0.1:10087" and
          .experimental.v2ray_api.stats.enabled == true and
          .experimental.v2ray_api.stats.users == $users
        ' "${mergedConfig}" >/dev/null 2>&1; then
        padmRemoveCleanupPath "${tmpFile}"
        return 0
    fi
    checkLogBackupCreate trafficBackupDir "${statsConfig}" "${mergedConfig}" || {
        padmRemoveCleanupPath "${tmpFile}"
        errorCard "sing-box 流量统计配置备份失败，已取消更新"
        return 1
    }
    commitGeneratedJsonFile "${tmpFile}" "${statsConfig}" || {
        padmRemoveCleanupPath "${tmpFile}"
        failTrafficStatsConfigChange "${trafficBackupDir}" "sing-box 流量统计配置写入失败"
        return 1
    }
    if ! singBoxMergeConfig; then
        failTrafficStatsConfigChange "${trafficBackupDir}" "sing-box 流量统计主配置合并失败"
        return 1
    fi
    if ! reloadCore; then
        failTrafficStatsConfigChange "${trafficBackupDir}" "sing-box 流量统计配置更新后核心重载失败" true
        return 1
    fi
    SUBSCRIPTION_TRAFFIC_STATS_RELOADED=true
    padmRemoveCleanupPath "${trafficBackupDir}"
}

ensureTrafficStatsConfig() {
    ensureXrayTrafficStatsConfig || return 1
    ensureSingBoxTrafficStatsConfig
}

reloadCoreWithTrafficStatsConfig() {
    local SUBSCRIPTION_TRAFFIC_STATS_RELOADED=false
    ensureSingBoxTrafficStatsConfig || return 1
    if [[ "${SUBSCRIPTION_TRAFFIC_STATS_RELOADED}" != "true" ]]; then
        reloadCore
    fi
}

collectLocalTrafficAccounts() {
    local configDir
    local -a configFiles=()
    local -a coreFiles=()
    if [[ "${coreInstallType:-}" == "1" ]]; then
        configDir=$(subscriptionSyncSafeConfigDir) || return 1
        trafficStatsAccountConfigFiles coreFiles xray "${configDir}" || return 1
        configFiles+=("${coreFiles[@]}")
    fi
    if [[ -n "${singBoxConfigPath:-}" ]]; then
        configDir=$(subscriptionSyncSafeSingBoxConfigDir) || return 1
        trafficStatsAccountConfigFiles coreFiles sing-box "${configDir}" || return 1
        configFiles+=("${coreFiles[@]}")
    fi
    if ((${#configFiles[@]} == 0)); then
        printf '[]\n'
        return 0
    fi
    subscriptionSyncConfiguredAccountNamesJson "${configFiles[@]}" 2>/dev/null
}

mapTrafficStatsJsonToAccounts() {
    local accounts=$1
    local suffixRegex
    suffixRegex=$(clientNameSuffixRegex) || return 1
    jq --argjson accounts "${accounts}" --arg suffixRegex "${suffixRegex}" '
      def accountName($name):
        ((($name | split(">>>"))[1] // "") | sub("-(" + $suffixRegex + ")$"; "")) as $account |
        if has($account) then $account
        else ($account | sub("-(uplink|downlink)$"; "")) as $legacyAccount |
          if has($legacyAccount) then $legacyAccount else "" end
        end;
      def direction($name): if ($name | endswith("downlink")) then "download" else "upload" end;
      def emptyTotals: reduce $accounts[] as $account ({}; .[$account] = {account:$account, upload:0, download:0});
      (reduce .stat[]? as $stat (emptyTotals;
        (accountName($stat.name // "")) as $account |
        if has($account) then
          .[$account][direction($stat.name // "")] += (($stat.value // 0) | tonumber? // 0)
        else
          .
        end)) as $totals |
      $accounts | map(. as $account | $totals[$account])
    '
}

collectXrayTrafficStatsSnapshot() {
    local accounts=$1
    local stats=
    local jsonItems=
    local suffixRegex
    local xrayBinary=${XRAY_STATS_BINARY:-/etc/padm/xray/xray}
    command -v timeout >/dev/null 2>&1 || return 1
    if [[ ! -x "${xrayBinary}" ]]; then
        return 1
    fi
    if ! stats=$(timeout 5 "${xrayBinary}" api statsquery --server=127.0.0.1:10085 -pattern user 2>/dev/null); then
        return 1
    fi
    if [[ -z "${stats}" ]]; then
        return 1
    fi
    if jsonItems=$(mapTrafficStatsJsonToAccounts "${accounts}" <<<"${stats}" 2>/dev/null); then
        printf '%s\n' "${jsonItems}"
        return 0
    fi
    suffixRegex=$(clientNameSuffixRegex) || return 1
    awk -v accounts="$(jq -r 'join(" ")' <<<"${accounts}")" -v suffixRegex="${suffixRegex}" '
          BEGIN {
            split(accounts, allowed, " ")
            for (i in allowed) wanted[allowed[i]] = 1
          }
          /name:/ {
            name = $0
            sub(/^.*user>>>/, "", name)
            sub(/".*$/, "", name)
            direction = (name ~ /(>>>traffic>>>|-)?downlink$/) ? "download" : "upload"
            sub(/>>>traffic>>>(uplink|downlink)$/, "", name)
            sub("-(" suffixRegex ")$", "", name)
            if (wanted[name]) account = name
            else {
              sub(/-(uplink|downlink)$/, "", name)
              account = wanted[name] ? name : ""
            }
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
              printf "{\"account\":\"%s\",\"upload\":%.0f,\"download\":%.0f}", account, totals[account SUBSEP "upload"] + 0, totals[account SUBSEP "download"] + 0
            }
            printf "]"
          }' <<<"${stats}"
}

singBoxGrpcResponseToStatsJson() {
    local responseFile=$1
    od -An -v -tu1 "${responseFile}" | awk '
      { for (i = 1; i <= NF; i++) bytes[++count] = $i }
      function readVarint(limit,    byte, shift, value) {
        shift = 0
        value = 0
        while (position <= limit && shift <= 63) {
          byte = bytes[position++]
          value += (byte % 128) * (2 ^ shift)
          if (byte < 128) { varintValue = value; return 1 }
          shift += 7
        }
        return 0
      }
      function skipField(wire, limit,    fieldLength) {
        if (wire == 0) return readVarint(limit)
        if (wire == 1) { position += 8; return position <= limit + 1 }
        if (wire == 2) {
          if (!readVarint(limit)) return 0
          fieldLength = varintValue
          position += fieldLength
          return position <= limit + 1
        }
        if (wire == 5) { position += 4; return position <= limit + 1 }
        return 0
      }
      function readStat(limit,    key, field, wire, fieldLength, fieldEnd, i, statName, statValue) {
        statName = ""
        statValue = 0
        while (position <= limit) {
          if (!readVarint(limit)) return 0
          key = varintValue
          field = int(key / 8)
          wire = key % 8
          if (field == 1 && wire == 2) {
            if (!readVarint(limit)) return 0
            fieldLength = varintValue
            fieldEnd = position + fieldLength - 1
            if (fieldEnd > limit) return 0
            for (i = position; i <= fieldEnd; i++) statName = statName sprintf("%c", bytes[i])
            position = fieldEnd + 1
          } else if (field == 2 && wire == 0) {
            if (!readVarint(limit)) return 0
            statValue = varintValue
          } else if (!skipField(wire, limit)) return 0
        }
        if (position != limit + 1 || statName == "") return 0
        print statName "\t" statValue
        return 1
      }
      END {
        if (count < 5 || bytes[1] != 0) exit 1
        frameLength = bytes[2] * 16777216 + bytes[3] * 65536 + bytes[4] * 256 + bytes[5]
        if (frameLength != count - 5) exit 1
        position = 6
        while (position <= count) {
          if (!readVarint(count)) exit 1
          key = varintValue
          field = int(key / 8)
          wire = key % 8
          if (field == 1 && wire == 2) {
            if (!readVarint(count)) exit 1
            fieldLength = varintValue
            fieldEnd = position + fieldLength - 1
            if (fieldEnd > count || !readStat(fieldEnd)) exit 1
          } else if (!skipField(wire, count)) exit 1
        }
      }
    ' | jq -Rsc '{stat:[split("\n")[] | select(length > 0) | split("\t") as $row | {name:$row[0],value:($row[1] | tonumber)}]}'
}

querySingBoxTrafficStatsGrpc() {
    local tmpDir
    local stats
    command -v curl >/dev/null 2>&1 || return 1
    padmCreateTmpRootPath tmpDir padm-sing-box-stats.XXXXXX -d || return 1
    printf '\000\000\000\000\006\032\004user' >"${tmpDir}/request.bin" || {
        padmRemoveCleanupPath "${tmpDir}"
        return 1
    }
    if ! curl -fsS --http2-prior-knowledge --noproxy '*' --connect-timeout 2 --max-time 5 \
        -D "${tmpDir}/headers" \
        -H 'Content-Type: application/grpc' \
        -H 'TE: trailers' \
        --data-binary "@${tmpDir}/request.bin" \
        --output "${tmpDir}/response.bin" \
        http://127.0.0.1:10087/v2ray.core.app.stats.command.StatsService/QueryStats; then
        padmRemoveCleanupPath "${tmpDir}"
        return 1
    fi
    if ! grep -Eq '^grpc-status:[[:space:]]*0[[:space:]]*$' "${tmpDir}/headers" ||
        ! stats=$(singBoxGrpcResponseToStatsJson "${tmpDir}/response.bin"); then
        padmRemoveCleanupPath "${tmpDir}"
        return 1
    fi
    padmRemoveCleanupPath "${tmpDir}"
    printf '%s\n' "${stats}"
}

collectSingBoxTrafficStatsSnapshot() {
    local accounts=$1
    local stats
    stats=$(querySingBoxTrafficStatsGrpc) || return 1
    mapTrafficStatsJsonToAccounts "${accounts}" <<<"${stats}"
}

collectLocalTrafficSnapshot() {
    local accounts
    local snapshot
    local xrayItems='[]'
    local singBoxItems='[]'
    if [[ "${coreInstallType:-}" != "1" && -z "${singBoxConfigPath:-}" ]]; then
        jq -n '{ok:false, items: []}'
        return 1
    fi
    if ! accounts=$(collectLocalTrafficAccounts); then
        jq -n '{ok:false, items: []}'
        return 1
    fi
    if [[ "${accounts}" == '[]' ]]; then
        jq -n '{ok:true, items: []}'
        return
    fi
    if [[ "${coreInstallType:-}" == "1" ]] && ! xrayItems=$(collectXrayTrafficStatsSnapshot "${accounts}"); then
        jq -n '{ok:false, items: []}'
        return 1
    fi
    if [[ -n "${singBoxConfigPath:-}" ]] && ! singBoxItems=$(collectSingBoxTrafficStatsSnapshot "${accounts}"); then
        jq -n '{ok:false, items: []}'
        return 1
    fi
    if ! snapshot=$(jq -cn --argjson accounts "${accounts}" --argjson xray "${xrayItems}" --argjson singBox "${singBoxItems}" '
      def indexed: map({key:.account, value:{upload:(.upload // 0), download:(.download // 0)}}) | from_entries;
      ($xray | indexed) as $xrayByAccount |
      ($singBox | indexed) as $singBoxByAccount |
      $accounts | map(. as $account |
        ({} +
          (if ($xray | length) > 0 then {xray:($xrayByAccount[$account] // {upload:0, download:0})} else {} end) +
          (if ($singBox | length) > 0 then {"sing-box":($singBoxByAccount[$account] // {upload:0, download:0})} else {} end)) as $cores |
        {
          account:$account,
          upload:([$cores[]?.upload] | add // 0),
          download:([$cores[]?.download] | add // 0),
          cores:$cores
        }) |
      {ok:true, items:.}
    '); then
        jq -n '{ok:false, items: []}'
        return 1
    fi
    printf '%s\n' "${snapshot}"
}

SUBSCRIPTION_TRAFFIC_ITEMS_VALIDATION_JQ='
      def count: type == "number" and . >= 0 and . == floor;
      def counter:
        type == "object" and keys == ["download", "upload"] and
        (.upload | count) and (.download | count);
      def cores:
        type == "object" and length > 0 and
        ((keys - ["sing-box", "xray"]) | length == 0) and
        all(to_entries[]?; .value | counter);
      def validItems:
        type == "array" and
        ([.[].account] | length) == ([.[].account] | unique | length) and
        all(.[]?;
          type == "object" and
          ((keys == ["account", "download", "upload"]) or
           (keys == ["account", "cores", "download", "upload"])) and
          (.account | type == "string" and length > 0 and . != "." and . != ".." and test("^[A-Za-z0-9._~@+=:-]+$")) and
          (.upload | count) and (.download | count) and
          ((has("cores") | not) or
            ((.cores | cores) and
             .upload == ([.cores[]?.upload] | add // 0) and
             .download == ([.cores[]?.download] | add // 0))));
'

subscriptionTrafficItemsValid() {
    local items=$1
    local remoteResults=${2:-[]}
    jq -e --argjson remoteResults "${remoteResults}" "${SUBSCRIPTION_TRAFFIC_ITEMS_VALIDATION_JQ}
      validItems and
      all(\$remoteResults[]? | select(.status == \"success\"); .response.items | validItems)
    " <<<"${items}" >/dev/null 2>&1
}

writeSubscriptionTrafficSnapshot() {
    local snapshot=$1
    local remoteResults=${2:-[]}
    local outputVar=${3:-}
    local items
    local remoteComplete
    SUBSCRIPTION_TRAFFIC_LOCAL_COMMITTED=false
    SUBSCRIPTION_TRAFFIC_COMPLETE=false
    SUBSCRIPTION_TRAFFIC_VALIDATION_FAILED=false
    if ! items=$(jq -ce 'select(.ok == true and (.items | type == "array")) | .items' <<<"${snapshot}" 2>/dev/null); then
        SUBSCRIPTION_TRAFFIC_VALIDATION_FAILED=true
        statusCard "流量统计" "采集失败，已保留上次统计"
        return 1
    fi
    if ! remoteComplete=$(subscriptionActiveGroupRead -er --argjson remoteResults "${remoteResults}" '
          ([.sources[]? | select(.role != "main" and .enabled == true) | .id]) as $expectedRemoteSourceIds |
          $remoteResults |
          select(
            type == "array" and
            ([.[].source_id] | length) == ([.[].source_id] | unique | length) and
            all(.[];
              . as $result |
              (.source_id | type == "string" and length > 0) and
              (($expectedRemoteSourceIds | index($result.source_id)) != null) and
              (.status | type == "string" and length > 0) and
              (if .status == "success" then (.response.items | type == "array") else true end))) |
          (((map(.source_id) | sort) == ($expectedRemoteSourceIds | sort) and
            all(.[]; .status == "success")) | tostring)
        ' 2>/dev/null); then
        statusCard "流量统计" "采集失败，已保留上次统计"
        return 1
    fi
    if ! subscriptionTrafficItemsValid "${items}" "${remoteResults}"; then
        SUBSCRIPTION_TRAFFIC_VALIDATION_FAILED=true
        statusCard "流量统计" "采集失败，已保留上次统计"
        return 1
    fi
    if ! subscriptionActiveGroupWrite --argjson snapshot "${snapshot}" --argjson remoteResults "${remoteResults}" '
      def counterTotal($counters):
        {upload:([$counters[]?.upload] | add // 0), download:([$counters[]?.download] | add // 0)};
      def resetDelta($old; $current; $known):
        (($current.upload // 0) - ($old.upload // 0)) as $upload |
        (($current.download // 0) - ($old.download // 0)) as $download |
        {
          upload:(if $known then (if $upload >= 0 then $upload else ($current.upload // 0) end) else ($current.upload // 0) end),
          download:(if $known then (if $download >= 0 then $download else ($current.download // 0) end) else ($current.download // 0) end)
        };
      def coreDelta($old; $current):
        reduce ($current | to_entries[]) as $entry ({upload:0, download:0};
          (resetDelta(($old[$entry.key] // {upload:0, download:0}); $entry.value; ($old | has($entry.key)))) as $delta |
          .upload += $delta.upload |
          .download += $delta.download);
      def itemCounters($item):
        if ($item | has("cores")) then $item.cores
        else {legacy:{upload:($item.upload // 0), download:($item.download // 0)}}
        end;
      def sourceTotal($prev; $current):
        ($prev // {upload:0, download:0, counters:{}}) as $old |
        if ($current | length) == 0 then $old
        else
          ($old.counters // {}) as $oldCounters |
          (reduce $current[] as $item ({upload:0, download:0, counters:{}};
            itemCounters($item) as $currentCounters |
            ($oldCounters[$item.account] // {}) as $accountCounters |
            (if (($accountCounters | has("legacy")) or ($currentCounters | has("legacy"))) then
               resetDelta(counterTotal($accountCounters); counterTotal($currentCounters); ($oldCounters | has($item.account)))
             else coreDelta($accountCounters; $currentCounters)
             end) as $counterDelta |
            .upload += $counterDelta.upload |
            .download += $counterDelta.download |
            .counters[$item.account] = $currentCounters)) as $delta |
          {upload: (($old.upload // 0) + $delta.upload), download: (($old.download // 0) + $delta.download), counters: $delta.counters, updated_at: (now | strftime("%F %T"))}
        end;
      def mapped($items; $accountIdMap): $items | map(. + {id: ($accountIdMap[.account] // .account)});
      def indexedById($items):
        reduce $items[] as $item ({}; .[$item.id] = ((.[$item.id] // []) + [$item]));
      def keepSources($map; $idSet):
        ($map // {}) | with_entries(. as $entry | select($idSet[$entry.key] == true));
      . as $group |
      ($group.sources | map({key:.id, value:true}) | from_entries) as $sourceIdSet |
      ($group.user_groups | map({key:(.id | '"${SUBSCRIPTION_SYNC_ACCOUNT_NAME_FROM_ID_JQ}"'), value:.id}) | from_entries) as $accountIdMap |
      (mapped($snapshot.items; $accountIdMap)) as $items |
      ($items | map(select(.account | startswith("sub_")))) as $userItems |
      (indexedById($userItems)) as $userItemsById |
      ($items | map(select((.account | startswith("sub_")) | not))) as $adminItems |
      (sourceTotal($group.traffic.sources.main; $items)) as $mainTraffic |
      (sourceTotal($group.traffic.admin.sources.main; $adminItems)) as $mainAdminTraffic |
      ($remoteResults | map(select(.status == "success") | . as $result |
        (mapped($result.response.items; $accountIdMap)) as $mappedItems |
        {source_id:$result.source_id, items:$mappedItems, user_items_by_id:indexedById($mappedItems | map(select(.account | startswith("sub_"))))})) as $remote |
      ($remote | map(. as $result | {key:$result.source_id, value:sourceTotal($group.traffic.sources[$result.source_id]; $result.items)}) | from_entries) as $remoteSourceTraffic |
      (keepSources($group.traffic.sources; $sourceIdSet) + {main:$mainTraffic} + $remoteSourceTraffic) as $sourceTraffic |
      ($remote | map(. as $result | {key:$result.source_id, value:sourceTotal($group.traffic.admin.sources[$result.source_id]; ($result.items | map(select(.account | startswith("sub_") | not))))}) | from_entries) as $remoteAdminSourceTraffic |
      (keepSources($group.traffic.admin.sources; $sourceIdSet) + {main:$mainAdminTraffic} + $remoteAdminSourceTraffic) as $adminSourceTraffic |
      ($group.user_groups | map(
        . as $user |
        (sourceTotal(($group.traffic.user_groups[$user.id].sources.main // {}); ($userItemsById[$user.id] // []))) as $mainUserTraffic |
        ($remote | map(. as $result | {key:$result.source_id, value:sourceTotal($group.traffic.user_groups[$user.id].sources[$result.source_id]; ($result.user_items_by_id[$user.id] // []))}) | from_entries) as $remoteUserSourceTraffic |
        (keepSources($group.traffic.user_groups[$user.id].sources; $sourceIdSet) + {main:$mainUserTraffic} + $remoteUserSourceTraffic) as $userSourceTraffic |
        {key:$user.id, value:{sources:$userSourceTraffic}}
      ) | from_entries) as $userTraffic |
      .traffic.admin = {sources:$adminSourceTraffic} |
      .traffic.user_groups = $userTraffic |
      .traffic.sources = $sourceTraffic
    '; then
        statusCard "流量统计" "统计写入失败，已保留上次统计"
        return 1
    fi
    if [[ -n "${outputVar}" ]]; then
        printf -v "${outputVar}" '%s' "${items}"
    fi
    SUBSCRIPTION_TRAFFIC_LOCAL_COMMITTED=true
    if [[ "${remoteComplete}" == "true" ]]; then
        SUBSCRIPTION_TRAFFIC_COMPLETE=true
        return 0
    fi
    statusCard "流量统计" "部分来源采集失败，本机和成功来源已更新，失败来源保留旧统计"
    return 1
}

subscriptionLocalTrafficBaselineExists() {
    subscriptionActiveGroupRead -e '
      [.traffic.sources.main?, .traffic.admin.sources.main?, .traffic.user_groups[]?.sources.main?] |
      any(.[]; (.counters? | type == "object" and length > 0))
    ' >/dev/null 2>&1
}

collectSubscriptionTrafficUnlocked() {
    local snapshot
    local remoteResults='[]'
    local remoteSources
    local role
    SUBSCRIPTION_TRAFFIC_LOCAL_COMMITTED=false
    SUBSCRIPTION_TRAFFIC_COMPLETE=false
    ensureSubscriptionGroupsState || return 1
    readInstallType
    readInstallProtocolType
    if ! ensureTrafficStatsConfig; then
        return 1
    fi
    if ! snapshot=$(collectLocalTrafficSnapshot); then
        statusCard "流量统计" "本机采集失败，已跳过远端请求并保留上次统计"
        return 1
    fi
    role=$(subscriptionCurrentRoleNormalized) || return 1
    if [[ "${role}" == "main" ]] &&
        remoteSources=$(subscriptionRemoteControlSources) &&
        [[ "${remoteSources}" != '[]' ]]; then
        statusCard "流量统计" "正在等待被控服务器流量响应" "单台请求最长 15 秒（含重试），多个服务器并行请求"
        remoteResults=$(subscriptionRemoteTrafficAll "${remoteSources}") || remoteResults='[]'
    fi
    if writeSubscriptionTrafficSnapshot "${snapshot}" "${remoteResults}"; then
        successCard "流量统计已更新"
    else
        return 1
    fi
}

collectSubscriptionTraffic() {
    subscriptionGroupsWithLock collectSubscriptionTrafficUnlocked
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
    local result
    local traffic
    local quotaStatus
    local jqProgram
    local quotaStatusJq
    quotaStatusJq=$(subscriptionUserQuotaStatusJq) || return 1
    jqProgram=$(printf '%s\n%s\n%s\n' "$(subscriptionTrafficTotalsJq)" "${quotaStatusJq}" '
      . as $group |
      (first($group.user_groups[]? | select(.id == $id))) as $userGroup |
      ($group.traffic.user_groups[$id] // {sources:{}}) as $traffic |
      (subscriptionTrafficTotal($traffic.sources)) as $trafficTotal |
      {
        quota_status:(if ($userGroup | type) == "object" then subscriptionUserQuotaStatus($userGroup; $trafficTotal; true) else "" end),
        traffic:$traffic
      }')
    result=$(subscriptionActiveGroupRead -c --arg id "${userSubscriptionId}" "${jqProgram}") || return 1
    quotaStatus=$(jq -r '.quota_status' <<<"${result}") || return 1
    traffic=$(jq -c '.traffic' <<<"${result}") || return 1
    userResultCard "用户订阅流量"
    menuLine "用户订阅：${userSubscriptionId}"
    menuLine "限额状态：${quotaStatus}"
    printf '%s\n' "${traffic}" | jq .
    menuClose
}

showSubscriptionTrafficOverview() {
    local output
    local jqProgram
    local quotaStatusJq
    quotaStatusJq=$(subscriptionUserQuotaStatusJq) || return 1
    jqProgram=$(printf '%s\n%s\n%s\n' "$(subscriptionTrafficTotalsJq)" "${quotaStatusJq}" '
      def mb($v): (((($v // 0) / 1024 / 1024) | floor) | tostring) + " MB";
      . as $group |
      (subscriptionTrafficTotal($group.traffic.sources)) as $globalTraffic |
      ($group.user_groups // []) as $users |
      (reduce ($users[]?) as $user ({total:0, enabled:0, over_limit:0, near_limit:0};
        (subscriptionUserQuotaStatus($user; subscriptionTrafficTotal(($group.traffic.user_groups[$user.id] // {}).sources); false)) as $status |
        .total += 1 |
        .enabled += (if $user.enabled == true then 1 else 0 end) |
        .over_limit += (if $status == "已超限" then 1 else 0 end) |
        .near_limit += (if $status == "接近上限" then 1 else 0 end))) as $userSummary |
      "全局累计：上传 " + mb($globalTraffic.upload) + " / 下载 " + mb($globalTraffic.download) + "\n" +
      "分享订阅：共 " + ($userSummary.total | tostring) + " 个，启用 " + ($userSummary.enabled | tostring) + " 个\n" +
      "限额状态：超限 " + ($userSummary.over_limit | tostring) + " 个，接近上限 " + ($userSummary.near_limit | tostring) + " 个\n" +
      "服务器源：共 " + (($group.sources | length) | tostring) + " 个，启用远端 " + (([$group.sources[]? | select(.role != "main" and .enabled == true)] | length) | tostring) + " 个\n" +
      "最近同步：状态 " + (($group.sync.last_status // "pending") | tostring) + "，时间 " + (($group.sync.last_run // "未运行") | tostring) + "\n" +
      "流量更新时间：" + (((($group.traffic.sources // {}) | to_entries | map(.value.updated_at // empty) | max) // "未知") | tostring)')
    output=$(subscriptionActiveGroupRead -r "${jqProgram}") || return 1
    userResultCard "流量与限额总览"
    while IFS= read -r line; do
        menuLine "${line}"
    done <<<"${output}"
    menuClose
}


manageTrafficDetails() {
    subscriptionRequireLocalPublisherRole || return 1
    local trafficDetailsStatus=
    while true; do
        echoContent title "\n┌─ 流量明细 ─────────────────────────────────────────"
        menuLine "按账号、分享订阅或服务器源查看累计流量。"
        menuItem 1 "查看我的流量" "查看自用账号在各服务器源的累计流量"
        menuItem 2 "查看分享订阅限额概览" "列出全部分享订阅、额度和状态"
        menuItem 3 "查看单个分享订阅流量" "选择订阅后显示流量和额度状态"
        menuItem 4 "查看服务器流量" "显示各服务器源累计流量"
        menuReturnItem 5 "返回流量与限额" "回到上级菜单"
        menuClose
        autoRead traffic_details_menu "请选择:" trafficDetailsStatus
        case "${trafficDetailsStatus}" in
        1) showAdminSubscriptionTraffic ;;
        2) showUserSubscriptions ;;
        3) selectUserSubscriptionTrafficMenu ;;
        4) showSubscriptionSourcesTraffic ;;
        5) return ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}

manageTrafficAndQuota() {
    subscriptionRequireLocalPublisherRole || return 1
    local quotaAutoApplyText
    while true; do
        subscriptionGroupQuotaAutoApplyEnabled && quotaAutoApplyText="开启" || quotaAutoApplyText="关闭"
        echoContent title "\n┌─ 流量与限额 ───────────────────────────────────────"
        menuLine "先刷新总览；明细、超限和自动处理按需进入。"
        menuLine "自动执行超限处理：${quotaAutoApplyText}"
        menuItem 1 "刷新并显示总览" "采集本机账号流量，写入 groups.json 后显示治理摘要"
        menuItem 2 "流量明细" "按账号、分享订阅或服务器源查看累计流量"
        menuDangerItem 3 "执行超限处理" "停用超额订阅并移除本机托管账号"
        menuItem 4 "开启/关闭自动执行超限处理" "切换同步前的自动限额事务"
        menuReturnItem 5 "返回订阅与用户" "回到上级菜单"
        menuClose
        autoRead traffic_quota_menu "请选择:" trafficQuotaStatus
        case "${trafficQuotaStatus}" in
        1) collectSubscriptionTraffic && showSubscriptionTrafficOverview ;;
        2) manageTrafficDetails ;;
        3) executeSubscriptionQuotaPlanMenu ;;
        4) toggleSubscriptionGroupQuotaAutoApplyEnabled && successCard "限额自动执行状态已切换" || errorCard "限额自动执行状态切换失败" ;;
        5) return ;;
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
