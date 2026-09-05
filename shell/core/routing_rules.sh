#!/usr/bin/env bash

# 下载 dlc.dat_plain.yml 到核心目录
downloadDLCPlainYAML() {
    local corePath=$1
    local dlcFilePath tmpDir tmpFilePath

    if [[ -z "${corePath}" ]]; then
        return 1
    fi

    corePath=$(padmResolveManagedAbsolutePath "${corePath}") || return 1
    padmEnsureSafeDirectory "${corePath}" || return 1
    dlcFilePath="${corePath}/dlc.dat_plain.yml"
    if [[ -s "${dlcFilePath}" ]]; then
        return 0
    fi

    padmCreateTmpRootPath tmpDir padm-dlc.XXXXXX -d || return 1
    tmpFilePath="${tmpDir}/dlc.dat_plain.yml"
    if ! downloadGitHubReleaseAsset -P "${tmpDir}" v2fly/domain-list-community latest dlc.dat_plain.yml >/dev/null 2>&1 || [[ ! -s "${tmpFilePath}" ]]; then
        padmRemoveCleanupPath "${tmpDir}"
        return 1
    fi

    commitGeneratedFile "${tmpFilePath}" "${dlcFilePath}" 644 || { padmRemoveCleanupPath "${tmpDir}"; return 1; }
    padmRemoveCleanupPath "${tmpDir}"
}

isDomainFormat() {
    local target=$1
    [[ "${target}" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z0-9-]{2,63}$ ]]
}

# 根据输入域名匹配 dlc.dat_plain.yml 对应 geosite name
getDLCGeositeName() {
    local inputRule=$1
    local corePath=$2
    local dlcFilePath="${corePath}/dlc.dat_plain.yml"

    if [[ -z "${inputRule}" || -z "${corePath}" ]]; then
        echo ""
        return
    fi

    local normalizedInput
    normalizedInput=$(echo "${inputRule}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    normalizedInput=${normalizedInput#domain:}
    normalizedInput=${normalizedInput#full:}
    normalizedInput=${normalizedInput#keyword:}

    if [[ -z "${normalizedInput}" ]]; then
        echo ""
        return
    fi

    if isDomainFormat "${normalizedInput}"; then
        return
    fi

    if ! downloadDLCPlainYAML "${corePath}"; then
        echo ""
        return
    fi

    local escapedInput=
    # shellcheck disable=SC2016
    escapedInput=$(echo "${normalizedInput}" | sed -e 's/[.[\*^$()+?{|]/\\&/g')

    local matchedLine=
    matchedLine=$(grep -n -m1 -E "^[[:space:]]*-[[:space:]]*name:[[:space:]]*\"?${escapedInput}\"?[[:space:]]*$" "${dlcFilePath}")
    if [[ -n "${matchedLine}" ]]; then
        echo "${normalizedInput}"
    fi
}

# 获取规则匹配结果，优先 geosite，失败按显式前缀或 domain 匹配
getDLCMatchedRuleValue() {
    local inputRule=$1
    local corePath=$2
    local normalizedInput=
    normalizedInput=$(echo "${inputRule}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [[ -z "${normalizedInput}" ]]; then
        echo ""
        return
    fi

    if [[ "${normalizedInput}" == geosite:* ]]; then
        echo "geosite:${normalizedInput#geosite:}"
        return
    fi
    if [[ "${normalizedInput}" == domain:* ]]; then
        echo "domain:${normalizedInput#domain:}"
        return
    fi
    if [[ "${normalizedInput}" == full:* ]]; then
        echo "full:${normalizedInput#full:}"
        return
    fi
    if [[ "${normalizedInput}" == keyword:* ]]; then
        echo "keyword:${normalizedInput#keyword:}"
        return
    fi
    if isDomainFormat "${normalizedInput}"; then
        echo "domain:${normalizedInput}"
        return
    fi

    local matchedRuleName=
    matchedRuleName=$(getDLCGeositeName "${normalizedInput}" "${corePath}")
    if [[ -n "${matchedRuleName}" ]]; then
        echo "geosite:${matchedRuleName}"
    else
        echo "keyword:${normalizedInput}"
    fi
}

# 添加 routing 配置
addXrayRouting() {

    local tag=$1    # warp-socks
    local type=$2   # outboundTag/inboundTag
    local domain=$3 # 域名
    local rulePosition=${4:-}

    if [[ -z "${tag}" || -z "${type}" || -z "${domain}" ]]; then
        errorCard "参数错误"
        return 1
    fi

    local routingRule=
    if [[ ! -f "${configPath}09_routing.json" ]]; then
        writeRoutingJsonConfig "${configPath}09_routing.json" <<EOF || return 1
{
    "routing":{
        "type": "field",
        "rules": [
            {
                "type": "field",
                "domain": [
                ],
            "outboundTag": "${tag}"
          }
        ]
  }
}
EOF
    fi
    local routingRule=
    routingRule=$(jq -r ".routing.rules[]|select(.outboundTag==\"${tag}\" and (.protocol == null))" "${configPath}09_routing.json") || return 1

    if [[ -z "${routingRule}" ]]; then
        routingRule="{\"type\": \"field\",\"domain\": [],\"outboundTag\": \"${tag}\"}"
    fi

    local newRules=()
    while read -r line; do
        if echo "${routingRule}" | grep -q "${line}"; then
            coreRuleExistsStatusCard "${line} 已存在，跳过"
        else
            local matchedRuleValue
            matchedRuleValue=$(getDLCMatchedRuleValue "${line}" "/etc/padm/xray")
            newRules+=("${matchedRuleValue}")
        fi
    done < <(echo "${domain}" | tr ',' '\n')
    if [[ ${#newRules[@]} -gt 0 ]]; then
        local rulesJson
        rulesJson=$(printf '%s\n' "${newRules[@]}" | jq -R -s 'split("\n") | map(select(length > 0))') || return 1
        routingRule=$(jq -r --argjson rules "${rulesJson}" '.domain += $rules' <<<"${routingRule}") || return 1
    fi

    unInstallRouting "${tag}" "${type}" || return 1
    if ! grep -q "gstatic.com" "${configPath}09_routing.json" && [[ "${tag}" == "blackhole_out" ]]; then
        updateRoutingJsonConfig "${configPath}09_routing.json" '.routing.rules += [{"type": "field","domain": ["domain:gstatic.com"],"outboundTag": "allow_domain_direct_outbound"}]' || return 1
        addXrayOutbound allow_domain_direct_outbound || return 1
    fi

    if [[ "${rulePosition}" == "top" ]]; then
        updateRoutingJsonConfig "${configPath}09_routing.json" '.routing.rules = [$routingRule] + .routing.rules' --argjson routingRule "${routingRule}" || return 1
    else
        updateRoutingJsonConfig "${configPath}09_routing.json" '.routing.rules += [$routingRule]' --argjson routingRule "${routingRule}" || return 1
    fi
}

# 添加 Xray IP 屏蔽路由规则
# 支持 geoip:cn 与自定义 IPv4/IPv6/CIDR
addXrayIPRouting() {

    local tag=$1
    local type=$2
    local ipList=$3

    if [[ -z "${tag}" || -z "${type}" || -z "${ipList}" ]]; then
        errorCard "参数错误"
        return 1
    fi

    if [[ ! -f "${configPath}09_routing.json" ]]; then
        writeRoutingJsonConfig "${configPath}09_routing.json" <<EOF || return 1
{
    "routing":{
        "type": "field",
        "rules": []
    }
}
EOF
    fi

    local routingRule=
    routingRule=$(jq -r ".routing.rules[]|select(.outboundTag==\"${tag}\" and (.protocol == null) and (.ip != null))" "${configPath}09_routing.json") || return 1
    if [[ -z "${routingRule}" ]]; then
        routingRule="{\"type\": \"field\",\"ip\": [],\"outboundTag\": \"${tag}\"}"
    fi

    local newRules=()
    while read -r line; do
        line=$(echo "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -z "${line}" ]]; then
            continue
        fi

        local ipRuleValue=${line}
        if [[ "${line}" == "cn" ]]; then
            ipRuleValue="geoip:cn"
        fi

        if echo "${routingRule}" | grep -q "${ipRuleValue}"; then
            coreRuleExistsStatusCard "${ipRuleValue} 已存在，跳过"
        else
            newRules+=("${ipRuleValue}")
        fi
    done < <(echo "${ipList}" | tr ',' '\n')
    if [[ ${#newRules[@]} -gt 0 ]]; then
        local rulesJson
        rulesJson=$(printf '%s\n' "${newRules[@]}" | jq -R -s 'split("\n") | map(select(length > 0))') || return 1
        routingRule=$(jq -r --argjson rules "${rulesJson}" '.ip += $rules' <<<"${routingRule}") || return 1
    fi

    unInstallRouting "${tag}" "${type}" || return 1
    updateRoutingJsonConfig "${configPath}09_routing.json" '.routing.rules += [$routingRule]' --argjson routingRule "${routingRule}" || return 1
}

# 添加 sing-box IP 屏蔽路由规则
# 支持增量合并历史 ip_cidr
addSingBoxIPRouteRule() {
    local outboundTag=$1
    local ipList=$2
    local routingName=$3

    local historyIPs=
    if [[ -f "${singBoxConfigPath}${routingName}.json" ]]; then
        local historyIPLines
        historyIPLines=$(jq -r '.route.rules[0].ip_cidr[]?' "${singBoxConfigPath}${routingName}.json") || return 1
        historyIPs=$(printf '%s\n' "${historyIPLines}" | paste -sd ',')
    fi

    if [[ -n "${historyIPs}" ]]; then
        ipList="${ipList},${historyIPs}"
    fi

    local ipCIDR=[]
    ipCIDR=$(echo "${ipList}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^cn$/geoip:cn/' | grep -v '^$' | sort -n | uniq | jq -R -s 'split("\n") | map(select(length > 0))') || return 1

    local routeAction='"outbound": "'"${outboundTag}"'"'
    if [[ "${outboundTag}" == *block* ]]; then
        routeAction='"action": "reject"'
    fi
    writeRoutingJsonConfig "${singBoxConfigPath}${routingName}.json" <<EOF || return 1
{
  "route": {
    "rules": [
      {
        "ip_cidr": ${ipCIDR},
        ${routeAction}
      }
    ]
  }
}
EOF
}

# 添加 sing-box GeoIP 远程规则
# 用于大陆 IP 自动屏蔽场景
addSingBoxGeoIPRouteRule() {
    local outboundTag=$1
    local geoipCode=$2
    local routingName=$3

    local routeAction='"outbound": "'"${outboundTag}"'"'
    if [[ "${outboundTag}" == *block* ]]; then
        routeAction='"action": "reject"'
    fi
    writeRoutingJsonConfig "${singBoxConfigPath}${routingName}.json" <<EOF || return 1
{
  "route": {
    "rules": [
      {
        "rule_set": [
          "geoip_${geoipCode}_${routingName}"
        ],
        ${routeAction}
      }
    ],
    "rule_set": [
      {
        "tag": "geoip_${geoipCode}_${routingName}",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-${geoipCode}.srs",
        "http_client": {
          "detour": "01_direct_outbound"
        }
      }
    ]
  }
}
EOF
}
# 根据 tag 卸载 Routing
unInstallRouting() {
    local tag=$1
    local type=$2
    local protocol=${3:-}

    if [[ -f "${configPath}09_routing.json" ]]; then
        if [[ -n "${protocol}" ]]; then
            updateRoutingJsonConfig "${configPath}09_routing.json" 'del(.routing.rules[] | select(.[$type] == $tag and ((.protocol // []) | index($protocol))))' --arg type "${type}" --arg tag "${tag}" --arg protocol "${protocol}" || return 1
        else
            updateRoutingJsonConfig "${configPath}09_routing.json" 'del(.routing.rules[] | select(.[$type] == $tag and (.protocol == null)))' --arg type "${type}" --arg tag "${tag}" || return 1
        fi
    fi
}

routingConfigBackupCreate() {
    local resultVar=$1
    local includeInbounds=${2:-false}
    local includeWarpConfig=${3:-false}
    local createdBackupDir fileName targetPath inboundList warpDir
    local -a targets=()
    local -a xrayFiles=(
        09_routing.json IPv4_out.json IPv6_out.json z_direct_outbound.json
        blackhole_out.json wireguard_out_IPv4.json wireguard_out_IPv6.json socks5_outbound.json
    )
    local -a singBoxFiles=(
        01_direct_outbound.json IPv4_out.json IPv6_out.json IPv6_route.json bt_block_route.json dns.json
        socks5_02_inbound_route.json wireguard_endpoints_IPv4_route.json
        wireguard_endpoints_IPv6_route.json wireguard_endpoints_IPv4.json
        wireguard_endpoints_IPv6.json wireguard_outbound.json
    )

    if [[ -n "${configPath:-}" ]]; then
        for fileName in "${xrayFiles[@]}"; do
            targetPath=$(padmManagedFilePath "${configPath}" "${fileName}") || return 1
            targets+=("${targetPath}")
        done
        if [[ "${includeInbounds}" == "true" ]]; then
            inboundList=$(find "${configPath%/}" -type f -name '*inbounds.json' -print) || return 1
            while IFS= read -r targetPath; do
                [[ -n "${targetPath}" ]] && targets+=("${targetPath}")
            done <<<"${inboundList}"
        fi
    fi
    if [[ -n "${singBoxConfigPath:-}" ]]; then
        for fileName in "${singBoxFiles[@]}"; do
            targetPath=$(padmManagedFilePath "${singBoxConfigPath}" "${fileName}") || return 1
            targets+=("${targetPath}")
        done
    fi
    if [[ "${includeWarpConfig}" == "true" ]]; then
        warpDir=$(warpConfigSafeDir) || return 1
        targets+=("${warpDir}/config")
    fi
    [[ "${#targets[@]}" -gt 0 ]] || return 1
    checkLogBackupCreate createdBackupDir "${targets[@]}" || return 1
    printf -v "${resultVar}" '%s' "${createdBackupDir}"
}

routingConfigRollback() {
    local backupDir=$1
    local reason=$2
    local retryReload=${3:-false}

    if ! checkLogBackupRestore "${backupDir}"; then
        padmForgetCleanupPath "${backupDir}"
        errorCard "${reason}，且旧配置恢复失败" "请手动检查备份目录: ${backupDir}"
        return 1
    fi
    if [[ "${retryReload}" == "true" ]] && ! reloadCore; then
        padmForgetCleanupPath "${backupDir}"
        errorCard "${reason}，旧配置已恢复但核心重载失败" "请手动检查备份目录: ${backupDir}"
        return 1
    fi
    if ! padmRemoveCleanupPath "${backupDir}"; then
        errorCard "${reason}，旧配置已恢复但备份目录清理失败" "请手动检查备份目录: ${backupDir}"
        return 1
    fi
    errorCard "${reason}，已恢复旧配置"
    return 1
}

routingConfigApplyTransaction() {
    local failureTitle=$1
    local includeInbounds=$2
    local includeWarpConfig=$3
    local applyFn=$4
    local backupDir=
    shift 4

    routingConfigBackupCreate backupDir "${includeInbounds}" "${includeWarpConfig}" || {
        errorCard "${failureTitle}：配置备份失败，已取消修改"
        return 1
    }
    if ! "${applyFn}" "$@"; then
        routingConfigRollback "${backupDir}" "${failureTitle}" false
        return 1
    fi
    if ! reloadCore; then
        routingConfigRollback "${backupDir}" "${failureTitle}：核心重载失败" true
        return 1
    fi
    if ! padmRemoveCleanupPath "${backupDir}"; then
        errorCard "${failureTitle}：配置已生效，但备份目录清理失败" "请手动检查备份目录: ${backupDir}"
        return 1
    fi
}

# 安装嗅探配置
installSniffing() {
    local inbound
    readInstallType
    if [[ "${coreInstallType}" == "1" ]]; then
        while IFS= read -r inbound; do
            updateRoutingJsonConfig "${inbound}" '
                .inbounds[0].sniffing.enabled = true |
                .inbounds[0].sniffing.destOverride = ((.inbounds[0].sniffing.destOverride // []) + ["http", "tls", "quic"] | unique)
            ' || return 1
        done < <(find "${configPath}" -name "*inbounds.json")
    fi
}


# 初始化 sing-box rule_set 路由规则
initSingBoxRules() {
    local domainRuleLines=
    local ruleSetLines=
    local suffixRuleLines=
    local singBoxRulePath="${singBoxConfigPath:-/etc/padm/sing-box/conf/config/}"
    local line normalizedLine matchedRuleName tag url
    while read -r line; do
        normalizedLine=$(echo "${line}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [[ -z "${normalizedLine}" ]]; then
            continue
        fi

        if [[ "${normalizedLine}" == geosite:* ]]; then
            normalizedLine=${normalizedLine#geosite:}
            tag="geosite_${normalizedLine}_$2"
            url="https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-${normalizedLine}.srs"
            ruleSetLines+="${tag}"$'\t'"${url}"$'\n'
            continue
        fi
        if [[ "${normalizedLine}" == domain:* ]]; then
            suffixRuleLines+="${normalizedLine#domain:}"$'\n'
            continue
        fi
        if [[ "${normalizedLine}" == full:* ]]; then
            domainRuleLines+="${normalizedLine#full:}"$'\n'
            continue
        fi
        if [[ "${normalizedLine}" == keyword:* ]]; then
            suffixRuleLines+="${normalizedLine#keyword:}"$'\n'
            continue
        fi

        if isDomainFormat "${normalizedLine}"; then
            suffixRuleLines+="${normalizedLine}"$'\n'
        else
            matchedRuleName=$(getDLCGeositeName "${normalizedLine}" "${singBoxRulePath}")

            if [[ -n "${matchedRuleName}" ]]; then
                tag="geosite_${matchedRuleName}_$2"
                url="https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-${matchedRuleName}.srs"
                ruleSetLines+="${tag}"$'\t'"${url}"$'\n'
            else
                suffixRuleLines+="${normalizedLine}"$'\n'
            fi
        fi
    done < <(echo "$1" | tr ',' '\n' | grep -v '^$' | sort -u)

    jq -n \
        --arg domainRules "${domainRuleLines}" \
        --arg suffixRules "${suffixRuleLines}" \
        --arg ruleSet "${ruleSetLines}" '
        def lines($value): $value | split("\n") | map(select(length > 0));
        {
          domainRules: lines($domainRules),
          suffixRules: lines($suffixRules),
          ruleSet: ($ruleSet | split("\n") | map(select(length > 0) | split("\t") | {
            tag: .[0],
            type: "remote",
            format: "binary",
            url: .[1],
            http_client: {detour: "01_direct_outbound"}
          }))
        }'
}

splitSingBoxRules() {
    local rules=$1
    local -n domainRulesRef=$2
    local -n suffixRulesRef=$3
    local -n ruleSetRef=$4
    local -n ruleSetTagRef=$5
    local parsedOutput
    parsedOutput=$(jq -c '.domainRules, .suffixRules, .ruleSet, (.ruleSet | map(.tag))' <<<"${rules}") || return 1
    local -a parsedRules
    mapfile -t parsedRules <<<"${parsedOutput}"
    [[ ${#parsedRules[@]} -eq 4 ]] || return 1
    domainRulesRef=${parsedRules[0]:-[]}
    suffixRulesRef=${parsedRules[1]:-[]}
    ruleSetRef=${parsedRules[2]:-[]}
    ruleSetTagRef=${parsedRules[3]:-[]}
}


# 设置 sniff routing 规则
setSniffRouting() {
    local targetPath="${singBoxConfigPath:-/etc/padm/sing-box/conf/config/}sniff.json"
    initSingBoxLocalDNSConfig || return 1
    writeRoutingJsonConfig "${targetPath}" <<EOF || return 1
{
    "route":{
        "rules":[
          {
            "action": "sniff",
            "timeout": "1s"
          }
        ]
    }
}
EOF
}

# 设置 sniff routing 规则
setStrategyRouting() {
    local tag=$1
    local strategy=$2
    local targetPath="${singBoxConfigPath:-/etc/padm/sing-box/conf/config/}strategy_${strategy}_${tag}.json"
    writeRoutingJsonConfig "${targetPath}" <<EOF || return 1
{
    "route":{
        "rules":[
          {
            "inbound": "${tag}",
            "action": "resolve",
            "strategy": "${strategy}"
          }
        ]
    }
}
EOF
}

# DNS 分流管理
# 设置 DNS/hosts 覆盖
writeRoutingJsonConfig() {
    local targetPath=$1
    local tmpPath
    targetPath=$(padmRequireSafeAbsolutePath "${targetPath}") || return 1
    padmCreateTempFileForTarget tmpPath "${targetPath}" routing || return 1
    if ! cat >"${tmpPath}"; then
        padmRemoveCleanupPath "${tmpPath}"
        return 1
    fi
    commitGeneratedJsonFile "${tmpPath}" "${targetPath}" || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
}

updateRoutingJsonConfig() {
    local targetPath=$1
    local filter=$2
    local tmpPath
    shift 2
    targetPath=$(padmRequireSafeAbsolutePath "${targetPath}") || return 1
    padmCreateTempFileForTarget tmpPath "${targetPath}" routing || return 1
    if ! jq "$@" "${filter}" "${targetPath}" >"${tmpPath}"; then
        padmRemoveCleanupPath "${tmpPath}"
        return 1
    fi
    commitGeneratedJsonFile "${tmpPath}" "${targetPath}" || { padmRemoveCleanupPath "${tmpPath}"; return 1; }
}
