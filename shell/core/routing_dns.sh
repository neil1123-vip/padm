#!/usr/bin/env bash

DNS_ROUTING_ACTIVE_BACKUP_DIR=

# DNS/hosts 路由与覆盖
dnsRouting() {
    if [[ -z "${configPath}" ]]; then
        coreNotInstalledErrorCard
        return 1
    fi
    local selectType=
    while true; do
        echoContent title "\n┌─ DNS 分流 ─────────────────────────────────────────"
        menuLine "只改变核心内指定域名的 DNS 解析，不会修改系统 DNS"
        menuLine "适合少量域名定向解析；如果目标是固定后端 IP，优先用 DNS/hosts 覆盖"
        menuItem 1 "添加" "添加 DNS 分流配置"
        menuDangerItem 2 "卸载" "移除 DNS 分流配置"
        menuReturnItem 3 "返回分流工具" "回到上一级分流菜单"
        menuClose
        selectType=
        autoRead dns_routing_menu "请选择:" selectType || return 0

        case "${selectType}" in
        1) setUnlockDNS || true; continue ;;
        2) removeUnlockDNS || true; continue ;;
        3) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

# DNS/hosts 覆盖
sniRouting() {
    if [[ -z "${configPath}" ]]; then
        coreNotInstalledErrorCard
        return 1
    fi
    local selectType=
    while true; do
        echoContent title "\n┌─ DNS/hosts 覆盖 ───────────────────────────────────"
        menuLine "把指定域名在核心内解析到指定 IP；这不是 Nginx/TCP 反向代理"
        menuLine "Xray 支持 geosite/domain 规则；sing-box 使用 remote rule_set 与 domain_suffix"
        menuItem 1 "添加" "添加 DNS/hosts 覆盖规则"
        menuDangerItem 2 "卸载" "移除 DNS/hosts 覆盖配置"
        menuReturnItem 3 "返回分流工具" "回到上一级分流菜单"
        menuClose
        selectType=
        autoRead sni_routing_menu "请选择:" selectType || return 0

        case "${selectType}" in
        1) setUnlockSNI || true; continue ;;
        2) removeUnlockSNI || true; continue ;;
        3) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

dnsRoutingBackupCreate() {
    local backupDir
    local xrayConfigDir=
    local singBoxConfigDir=
    local singBoxFile
    local xrayManagedFile
    local singBoxManagedFile
    local createdBackupDir
    local -a backupArgs=()
    local -a backupTargets=()
    if [[ -n "${configPath:-}" ]]; then
        xrayConfigDir=$(dnsRoutingSafeXrayConfigDir) || return 1
    fi
    if [[ -n "${singBoxConfigPath:-}" ]]; then
        singBoxConfigDir=$(dnsRoutingSafeSingBoxConfigDir) || return 1
    fi
    if [[ -n "${xrayConfigDir}" ]]; then
        xrayManagedFile=$(padmManagedFilePath "${xrayConfigDir}" "11_dns.json") || return 1
        backupArgs+=("xray/11_dns.json" "${xrayManagedFile}")
        backupTargets+=("${xrayManagedFile}")
        xrayManagedFile=$(padmManagedFilePath "${xrayConfigDir}" "dns_routing.state") || return 1
        backupArgs+=("xray/dns_routing.state" "${xrayManagedFile}")
        backupTargets+=("${xrayManagedFile}")
    fi
    if [[ -n "${singBoxConfigDir}" ]]; then
        while IFS= read -r singBoxFile; do
            singBoxManagedFile=$(padmManagedFilePath "${singBoxConfigDir}" "${singBoxFile}") || return 1
            backupArgs+=("sing-box/${singBoxFile}" "${singBoxManagedFile}")
            backupTargets+=("${singBoxManagedFile}")
        done < <(dnsRoutingManagedSingBoxFiles)
    fi
    if [[ -n "${PADM_DNS_ROUTING_BACKUP_DIR:-}" ]]; then
        backupDir="${PADM_DNS_ROUTING_BACKUP_DIR%/}"
        padmIsSafeAbsolutePath "${backupDir}" || return 1
        removeManagedPathIfPresent "${backupDir}" || return 1
        padmWriteManagedFileBackupManifest "${backupDir}" "${backupArgs[@]}" || return 1
    else
        checkLogBackupCreate createdBackupDir "${backupTargets[@]}" || return 1
        backupDir="${createdBackupDir}"
    fi
    DNS_ROUTING_ACTIVE_BACKUP_DIR="${backupDir}"
}

dnsRoutingBackupRestore() {
    local backupDir
    local xrayConfigDir=
    local singBoxConfigDir=
    backupDir=$(dnsRoutingSafeBackupDir) || return 1
    [[ -d "${backupDir}" ]] || return 1
    if [[ -n "${configPath:-}" ]]; then
        xrayConfigDir=$(dnsRoutingSafeXrayConfigDir) || return 1
    fi
    if [[ -n "${singBoxConfigPath:-}" ]]; then
        singBoxConfigDir=$(dnsRoutingSafeSingBoxConfigDir) || return 1
    fi
    padmRestoreManagedFileBackupManifest "${backupDir}"
}

dnsRoutingBackupCleanup() {
    local backupDir
    backupDir=$(dnsRoutingSafeBackupDir) || return 1
    removeManagedPathIfPresent "${backupDir}" || return 1
    padmForgetCleanupPath "${backupDir}"
    DNS_ROUTING_ACTIVE_BACKUP_DIR=
}

dnsRoutingAbortChange() {
    local reason=$1
    local backupDir
    local restoreMessage
    backupDir=$(dnsRoutingSafeBackupDir) || return 1
    if dnsRoutingBackupRestore; then
        dnsRoutingBackupCleanup || errorCard "${reason}，旧配置已恢复，但备份目录清理失败: ${backupDir}"
    else
        padmForgetCleanupPath "${backupDir}"
        DNS_ROUTING_ACTIVE_BACKUP_DIR=
        coreSetSingleRestoreResultMessage restoreMessage "${reason}" false "已恢复旧配置" "旧配置" "备份目录: ${backupDir}" || true
        errorCard "${restoreMessage}"
    fi
    return 1
}

dnsRoutingReloadOrRollback() {
    local title=$1
    local backupDir
    local restoreMessage
    backupDir=$(dnsRoutingSafeBackupDir) || return 1
    if reloadCore; then
        dnsRoutingBackupCleanup || errorCard "${title}已应用，但备份目录清理失败: ${backupDir}"
        return 0
    fi
    if ! dnsRoutingBackupRestore; then
        padmForgetCleanupPath "${backupDir}"
        DNS_ROUTING_ACTIVE_BACKUP_DIR=
        coreSetSingleRestoreResultMessage restoreMessage "${title}核心重载失败" false "已恢复旧配置" "旧配置" "备份目录: ${backupDir}" || true
        errorCard "${restoreMessage}"
        return 1
    fi
    dnsRoutingBackupCleanup || true
    local rollbackMessage
    coreSetRollbackResultMessage rollbackMessage "${title}核心重载失败" "已回滚本次修改" reloadCore "恢复旧配置后重载仍失败，请检查核心服务日志"
    errorCard "${rollbackMessage}"
    return 1
}

dnsRoutingSafeBackupDir() {
    local backupDir
    if [[ -n "${DNS_ROUTING_ACTIVE_BACKUP_DIR:-}" ]]; then
        backupDir="${DNS_ROUTING_ACTIVE_BACKUP_DIR}"
    elif [[ -n "${PADM_DNS_ROUTING_BACKUP_DIR:-}" ]]; then
        backupDir="${PADM_DNS_ROUTING_BACKUP_DIR}"
    else
        return 1
    fi
    padmRequireSafeAbsolutePath "${backupDir%/}"
}

dnsRoutingSafeXrayConfigDir() {
    coreSafeConfigDir "${configPath:-}"
}

dnsRoutingSafeSingBoxConfigDir() {
    coreSafeConfigDir "${singBoxConfigPath:-}"
}

dnsRoutingXrayStateFile() {
    local configDir
    configDir=$(dnsRoutingSafeXrayConfigDir) || return 1
    if [[ -n "${PADM_XRAY_DNS_STATE_FILE:-}" ]]; then
        padmRequireSafeAbsolutePath "${PADM_XRAY_DNS_STATE_FILE}"
    else
        printf '%s\n' "${configDir}dns_routing.state"
    fi
}

dnsRoutingManagedSingBoxFiles() {
    printf '%s\n' "dns.json" "01_direct_outbound.json"
}

# 合并 Xray DNS 配置并记录 PADM 所有权。
updateXrayDNSRoutingConfig() {
    local operation=${1:-}
    local patch=${2:-'{}'}
    local configDir targetPath currentFile=/dev/null statePath stateFile=/dev/null result merged state changed
    configDir=$(dnsRoutingSafeXrayConfigDir) || return 1
    targetPath="${configDir}11_dns.json"
    [[ -f "${targetPath}" ]] && currentFile="${targetPath}"
    statePath=$(dnsRoutingXrayStateFile) || return 1
    [[ -f "${statePath}" ]] && stateFile="${statePath}"
    result=$(jq -s --slurpfile state "${stateFile}" --arg operation "${operation}" --argjson patch "${patch}" '
        def valid_state:
            type == "object" and .version == 1 and
            (.dns | type == "object") and (.sni | type == "object") and
            (.dns.servers | type == "array") and (.dns.hosts | type == "object") and
            (.sni.servers | type == "array") and (.sni.hosts | type == "object");
        def remove_servers($items; $remove):
            [$items[] as $item | select(any($remove[]?; . == $item) | not) | $item];
        def remove_hosts($items; $remove):
            reduce ($remove | keys[]) as $key ($items;
                if has($key) and .[$key] == $remove[$key] then del(.[$key]) else . end);
        if ($operation | IN("add-dns", "add-sni", "remove-dns", "remove-sni")) | not then
            error("invalid Xray DNS operation")
        else
            (if length == 1 then .[0] else {} end) as $config |
            if ($config | type) != "object" then error("Xray DNS config must be an object")
            elif ($config.dns? // {} | type) != "object" then error("Xray DNS section must be an object")
            elif (($config.dns.servers? // []) | type) != "array" then error("Xray DNS servers must be an array")
            elif (($config.dns.hosts? // {}) | type) != "object" then error("Xray DNS hosts must be an object")
            else
                ($state | if (length == 1 and (.[0] | valid_state)) then .[0] else null end) as $saved |
                if ($operation | startswith("remove-")) and $saved == null then
                    {config:$config, state:null, changed:false}
                else
                    ($saved // {version:1, dns:{servers:[],hosts:{}}, sni:{servers:[],hosts:{}}}) as $manifest |
                    (if $operation | endswith("dns") then "dns" else "sni" end) as $feature |
                    ($manifest[$feature]) as $old |
                    ($config.dns // {}) as $dns |
                    (remove_servers(($dns.servers // []); ($old.servers // []))) as $keptServers |
                    (remove_hosts(($dns.hosts // {}); ($old.hosts // {}))) as $keptHosts |
                    if $operation | startswith("remove-") then
                        ($manifest | .[$feature] = {servers:[],hosts:{}}) as $newManifest |
                        {config:($config | .dns.servers=$keptServers | .dns.hosts=$keptHosts), state:$newManifest, changed:true}
                    else
                        (reduce (($patch.servers // [])[]) as $item
                            ({servers:$keptServers, added:[]};
                                if any(.servers[]; . == $item) then .
                                else .servers += [$item] | .added += [$item] end)) as $serverResult |
                        (reduce (($patch.hosts // {}) | keys[]) as $key
                            ({hosts:$keptHosts, added:{}};
                                ($patch.hosts[$key]) as $value |
                                if (.hosts | has($key)) then
                                    if .hosts[$key] == $value then . else error("Xray DNS host conflicts with custom value") end
                                else .hosts[$key]=$value | .added[$key]=$value end)) as $hostResult |
                        ($manifest | .[$feature] = {servers:$serverResult.added, hosts:$hostResult.added}) as $newManifest |
                        {config:($config | .dns.servers=$serverResult.servers | .dns.hosts=$hostResult.hosts), state:$newManifest, changed:true}
                    end
                end
            end
        end
    ' "${currentFile}" </dev/null) || return 1
    changed=$(jq -r '.changed' <<<"${result}") || return 1
    [[ "${changed}" == true ]] || return 0
    merged=$(jq -c '.config' <<<"${result}") || return 1
    state=$(jq -c '.state | if (.dns.servers + (.dns.hosts | to_entries) + .sni.servers + (.sni.hosts | to_entries)) == [] then null else . end' <<<"${result}") || return 1
    writeRoutingJsonConfig "${targetPath}" <<<"${merged}" || return 1
    if [[ "${state}" == null ]]; then
        removeManagedFileIfPresent "${statePath}"
    else
        writeRoutingJsonConfig "${statePath}" <<<"${state}" || return 1
    fi
}

# DNS/hosts 配置写入
setUnlockSNI() {
    autoRead sni_routing_ip "请输入要覆盖到的 IP:" setSNIP || return 0
    if [[ -n ${setSNIP} ]]; then
        echoContent title "\n┌─ DNS/hosts 覆盖规则 ───────────────────────────────"
        menuLine "Xray 录入示例：netflix,disney,hulu"
        menuLine "sing-box 支持 geosite 名称和具体域名，具体域名按 domain_suffix 写入"
        menuClose

        dnsRoutingBackupCreate || { errorCard "DNS/hosts 覆盖配置备份失败，已取消修改"; return 1; }
        if [[ "${coreInstallType}" == 1 ]]; then
            autoRead sni_xray_domains "请按照上面示例录入域名:" xrayDomainList || return 0
            local hosts={}
            while read -r domain; do
                local matchedRuleValue
                matchedRuleValue=$(getDLCMatchedRuleValue "${domain}" "/etc/padm/xray")
                hosts=$(echo "${hosts}" | jq -r --arg key "${matchedRuleValue}" --arg value "${setSNIP}" '. + {($key):$value}')
            done < <(echo "${xrayDomainList}" | tr ',' '\n')
            local xrayPatch
            xrayPatch=$(jq -n --argjson hosts "${hosts}" '{servers:["8.8.8.8","1.1.1.1"],hosts:$hosts}') || return 1
            if ! updateXrayDNSRoutingConfig add-sni "${xrayPatch}"; then
                errorCard "DNS/hosts 覆盖配置写入失败，已保留旧配置"
                dnsRoutingAbortChange "DNS/hosts 覆盖配置写入失败"
                return 1
            fi
        fi
        if [[ -n "${singBoxConfigPath}" ]]; then
            echoContent yellow "录入示例:www.netflix.com,www.google.com"
            autoRead sni_singbox_domains "请按照上面示例录入域名:" singboxDomainList || return 0
            addSingBoxDNSConfig "${setSNIP}" "${singboxDomainList}" "predefined" || { dnsRoutingAbortChange "DNS/hosts 覆盖配置写入失败"; return 1; }
        fi
        dnsRoutingReloadOrRollback "DNS/hosts 覆盖" || return 1
        statusCard "DNS/hosts 覆盖" "规则写入成功"
    else
        coreIPRequiredErrorCard
    fi
    return 0
}

# 添加 Xray DNS 配置
dnsRoutingValidateDomainList() {
    local domainList=${1:-}
    if [[ ! "${domainList}" =~ [^[:space:],] ]]; then
        errorCard "DNS 域名规则不能为空"
        return 1
    fi
}

addXrayDNSConfig() {
    local ip=$1
    local domainList=$2
    dnsRoutingValidateDomainList "${domainList}" || return 1
    local domains=[]
    while read -r line; do
        local matchedRuleValue
        matchedRuleValue=$(getDLCMatchedRuleValue "${line}" "/etc/padm/xray")
        domains=$(echo "${domains}" | jq -r --arg rule "${matchedRuleValue}" '. += [$rule]')
    done < <(echo "${domainList}" | tr ',' '\n')

    if [[ "${coreInstallType}" == "1" ]]; then
        local xrayPatch
        xrayPatch=$(jq -n --arg ip "${ip}" --argjson domains "${domains}" '{servers:[{address:$ip,port:53,domains:$domains}],hosts:{}}') || return 1
        if ! updateXrayDNSRoutingConfig add-dns "${xrayPatch}"; then
            errorCard "DNS 分流配置写入失败，已保留旧配置"
            return 1
        fi
    fi
}

# 仅替换受管 DNS 内容，保留自定义配置与跨分片引用。
updateSingBoxDNSRoutingConfig() {
    local patch=${1:-'{}'}
    local configDir targetPath file currentFile=/dev/null merged
    local -a otherFiles=()
    configDir=$(dnsRoutingSafeSingBoxConfigDir) || return 1
    targetPath="${configDir}dns.json"
    if [[ -f "${targetPath}" ]]; then
        currentFile="${targetPath}"
    fi
    for file in "${configDir}"*.json; do
        [[ -f "${file}" && "${file}" != "${targetPath}" ]] && otherFiles+=("${file}")
    done
    merged=$(jq -s --slurpfile current "${currentFile}" --argjson patch "${patch}" '
        def managed_tag: . == "padm-hosts" or . == "padm-dnsRouting";
        def managed_rule: type == "object" and (.server? | managed_tag);
        def rule_refs:
            .. | objects | .rule_set? |
            if type == "string" then . elif type == "array" then .[] | strings else empty end;
        def server_refs:
            .. | objects |
            (.server?, .final?, .default_domain_resolver?,
             (.domain_resolver? | if type == "object" then .server? else . end)) |
            select(managed_tag);
        . as $shards |
        if ($current | length) > 1 then error("sing-box DNS config must contain one object")
        elif $current == [] then {} else $current[0] end |
        if type != "object" then error("sing-box DNS config must be an object") else . end |
        if any(.dns, .route; . != null and type != "object") then
            error("sing-box dns/route must be objects")
        else . end |
        if any(.dns.servers, .dns.rules, .route.rules, .route.rule_set; . != null and type != "array") then
            error("sing-box DNS servers/rules/rule_set must be arrays")
        else . end |
        [.dns.rules[]?, .route.rules[]? | select(managed_rule) | rule_refs] as $oldRuleTags |
        if .dns.rules != null then .dns.rules |= map(select(managed_rule | not)) else . end |
        if .route.rules != null then .route.rules |= map(select(managed_rule | not)) else . end |
        ($shards + [., $patch]) as $retained |
        [$retained[] | rule_refs] as $usedRuleTags |
        [$retained[] | server_refs] as $usedServerTags |
        [$patch.dns.servers[]?.tag] as $newServerTags |
        if any($shards[].dns.servers[]? | objects; .tag as $tag | $newServerTags | index($tag)) then
            error("managed DNS server tag already exists in another shard")
        else . end |
        if .dns.servers != null then
            .dns.servers |= map(select(
                if type == "object" and (.tag | managed_tag) then
                    .tag as $tag | ($newServerTags | index($tag) | not) and ($usedServerTags | index($tag))
                else true end
            ))
        else . end |
        if .route.rule_set != null then
            .route.rule_set |= map(select(.tag as $tag |
                (($oldRuleTags | index($tag)) and ($usedRuleTags | index($tag) | not) and
                 ($tag | startswith("geosite_") and endswith("_dns")) and
                 . == {tag:$tag, type:"remote", format:"binary", http_client:{detour:"01_direct_outbound"},
                       url:("https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-" +
                            ($tag | ltrimstr("geosite_") | rtrimstr("_dns")) + ".srs")}) | not
            )) |
            if .route.rule_set == [] then del(.route.rule_set) else . end
        else . end |
        [($shards + [.])[] | .route.rule_set[]?.tag] as $definedRuleTags |
        if ($patch.dns.servers // [] | length) > 0 then
            .dns.servers = ((.dns.servers // []) + $patch.dns.servers) |
            .dns.rules = ((.dns.rules // []) + $patch.dns.rules) |
            .route.rules = ((.route.rules // []) + $patch.route.rules) |
            ([$patch.route.rule_set[] | select(.tag as $tag | $definedRuleTags | index($tag) | not)]) as $newRuleSets |
            if $newRuleSets != [] then .route.rule_set = ((.route.rule_set // []) + $newRuleSets) else . end |
            if all(($shards + [.])[]; .route.default_domain_resolver == null) then
                .route.default_domain_resolver = "padm-local"
            else . end
        else . end
    ' "${otherFiles[@]}" </dev/null) || return 1
    writeRoutingJsonConfig "${targetPath}" <<<"${merged}"
}

# 添加 sing-box DNS 配置
addSingBoxDNSConfig() {
    local ip=$1
    local domainList=$2
    local actionType=${3:-}
    dnsRoutingValidateDomainList "${domainList}" || return 1

    local rules=
    rules=$(initSingBoxRules "${domainList}" "dns") || { errorCard "sing-box DNS 规则生成失败，已保留旧配置"; return 1; }
    local domainRules suffixRules ruleSet ruleSetTag
    splitSingBoxRules "${rules}" domainRules suffixRules ruleSet ruleSetTag || { errorCard "sing-box DNS 规则拆分失败，已保留旧配置"; return 1; }
    if [[ -n "${singBoxConfigPath}" ]]; then
        local patch
        patch=$(jq -n --arg ip "${ip}" --arg action "${actionType}" \
            --argjson domains "${domainRules}" --argjson suffixes "${suffixRules}" \
            --argjson ruleSets "${ruleSet}" --argjson ruleTags "${ruleSetTag}" '
            (if $action == "predefined" then "padm-hosts" else "padm-dnsRouting" end) as $tag |
            ({domain:$domains, domain_suffix:$suffixes, rule_set:$ruleTags} |
                with_entries(select(.value | length > 0))) as $match |
            {
                dns: {
                    servers: [(if $action == "predefined" then
                        {tag:$tag, type:"hosts", predefined:(($domains + $suffixes) | unique | map({key:., value:$ip}) | from_entries)}
                    else {tag:$tag, type:"udp", server:$ip} end)],
                    rules: [($match + {action:"route", server:$tag} | if $action == "predefined" then del(.rule_set) else . end)]
                },
                route: {rules: [($match + {action:"resolve", server:$tag})], rule_set:$ruleSets}
            }
        ') || return 1
        initSingBoxLocalDNSConfig || return 1
        if ! updateSingBoxDNSRoutingConfig "${patch}"; then
            errorCard "sing-box DNS/hosts 配置写入失败，已保留旧配置"
            return 1
        fi
    fi
}
# 设置 DNS 分流
setUnlockDNS() {
    autoRead dns_routing_server "请输入分流的DNS:" setDNS || return 0
    if [[ -n ${setDNS} ]]; then
        echoContent title "\n┌─ DNS 分流规则 ─────────────────────────────────────"
        menuLine "录入示例：netflix,disney,hulu"
        menuClose
        autoRead routing_domain_rules "请按照上面示例录入域名:" domainList || return 0

        dnsRoutingBackupCreate || { errorCard "DNS 分流配置备份失败，已取消修改"; return 1; }
        if ! addXrayDNSConfig "${setDNS}" "${domainList}"; then
            dnsRoutingAbortChange "DNS 分流配置写入失败"
            return 1
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            addSingBoxOutbound 01_direct_outbound || { errorCard "sing-box direct 出站写入失败，已保留旧配置"; dnsRoutingAbortChange "DNS 分流配置写入失败"; return 1; }
            if ! addSingBoxDNSConfig "${setDNS}" "${domainList}"; then
                dnsRoutingAbortChange "DNS 分流配置写入失败"
                return 1
            fi
        fi

        dnsRoutingReloadOrRollback "DNS 分流" || return 1

        echoContent title "\n┌─ DNS 分流排障建议 ─────────────────────────────────"
        menuLine "如仍无法观看，可先重启 VPS 后再测试客户端"
        menuLine "仍异常时，先卸载 DNS 解锁，再修改本地 /etc/resolv.conf"
        menuLine "修改后重启 VPS，使系统 DNS 与分流配置重新生效"
        menuClose
    else
        errorCard "dns不可为空"
    fi
    return 0
}

# 移除 DNS/hosts 配置
removeUnlockRoutingConfig() {
    local title=$1
    local checkXrayFile=${2:-}
    dnsRoutingBackupCreate || { errorCard "${title}配置备份失败，已取消移除"; return 1; }
    if [[ "${coreInstallType}" == 1 && ( -z "${checkXrayFile}" || -f "${configPath}11_dns.json" ) ]]; then
        local xrayOperation=remove-sni
        [[ -n "${checkXrayFile}" ]] && xrayOperation=remove-dns
        if ! updateXrayDNSRoutingConfig "${xrayOperation}"; then
            errorCard "${title}配置移除失败，已保留旧配置"
            dnsRoutingAbortChange "${title}配置移除失败"
            return 1
        fi
    fi

    if [[ -n "${singBoxConfigPath:-}" && -f "${singBoxConfigPath}dns.json" ]]; then
        if ! updateSingBoxDNSRoutingConfig ||
            ! initSingBoxLocalDNSConfig; then
            errorCard "sing-box ${title}配置移除失败，已保留旧配置"
            dnsRoutingAbortChange "${title}配置移除失败"
            return 1
        fi
    fi

    dnsRoutingReloadOrRollback "${title}" || return 1

    successCard "卸载成功"

    return 0
}

# 移除 DNS 分流
removeUnlockDNS() { removeUnlockRoutingConfig "DNS 分流" 1; }

# 移除 DNS/hosts 覆盖
removeUnlockSNI() { removeUnlockRoutingConfig "DNS/hosts 覆盖"; }
