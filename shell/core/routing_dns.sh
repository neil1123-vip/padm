#!/usr/bin/env bash

DNS_ROUTING_ACTIVE_BACKUP_DIR=

# DNS/hosts 路由与覆盖
dnsRouting() {
    if [[ -z "${configPath}" ]]; then
        coreNotInstalledErrorCard
        menu
        exit 0
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
        1) setUnlockDNS; return $? ;;
        2) removeUnlockDNS; return $? ;;
        3) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

# DNS/hosts 覆盖
sniRouting() {
    if [[ -z "${configPath}" ]]; then
        coreNotInstalledErrorCard
        menu
        exit 0
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
        1) setUnlockSNI; return $? ;;
        2) removeUnlockSNI; return $? ;;
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

dnsRoutingManagedSingBoxFiles() {
    printf '%s\n' "dns.json" "01_direct_outbound.json"
}

# DNS/hosts 配置写入
setUnlockSNI() {
    autoRead sni_routing_ip "请输入要覆盖到的 IP:" setSNIP
    if [[ -n ${setSNIP} ]]; then
        echoContent title "\n┌─ DNS/hosts 覆盖规则 ───────────────────────────────"
        menuLine "Xray 录入示例：netflix,disney,hulu"
        menuLine "sing-box 支持 geosite 名称和具体域名，具体域名按 domain_suffix 写入"
        menuClose

        dnsRoutingBackupCreate || { errorCard "DNS/hosts 覆盖配置备份失败，已取消修改"; return 1; }
        if [[ "${coreInstallType}" == 1 ]]; then
            autoRead sni_xray_domains "请按照上面示例录入域名:" xrayDomainList
            local hosts={}
            while read -r domain; do
                local matchedRuleValue
                matchedRuleValue=$(getDLCMatchedRuleValue "${domain}" "/etc/padm/xray")
                hosts=$(echo "${hosts}" | jq -r --arg key "${matchedRuleValue}" --arg value "${setSNIP}" '. + {($key):$value}')
            done < <(echo "${xrayDomainList}" | tr ',' '\n')
            if ! writeRoutingJsonConfig "${configPath}11_dns.json" <<EOF
{
    "dns": {
        "hosts":${hosts},
        "servers": [
            "8.8.8.8",
            "1.1.1.1"
        ]
    }
}
EOF
            then
                errorCard "DNS/hosts 覆盖配置写入失败，已保留旧配置"
                dnsRoutingAbortChange "DNS/hosts 覆盖配置写入失败"
                return 1
            fi
        fi
        if [[ -n "${singBoxConfigPath}" ]]; then
            echoContent yellow "录入示例:www.netflix.com,www.google.com"
            autoRead sni_singbox_domains "请按照上面示例录入域名:" singboxDomainList
            addSingBoxDNSConfig "${setSNIP}" "${singboxDomainList}" "predefined" || { dnsRoutingAbortChange "DNS/hosts 覆盖配置写入失败"; return 1; }
        fi
        dnsRoutingReloadOrRollback "DNS/hosts 覆盖" || return 1
        statusCard "DNS/hosts 覆盖" "规则写入成功"
    else
        coreIPRequiredErrorCard
    fi
    exit 0
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

        if ! writeRoutingJsonConfig "${configPath}11_dns.json" <<EOF
{
    "dns": {
        "servers": [
            {
                "address": "${ip}",
                "port": 53,
                "domains": ${domains}
            },
        "localhost"
        ]
    }
}
EOF
        then
            errorCard "DNS 分流配置写入失败，已保留旧配置"
            return 1
        fi
    fi
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
        local localTag hostsTag routingTag
        localTag="padm-local"
        hostsTag="padm-hosts"
        routingTag="padm-dnsRouting"
        if [[ "${actionType}" == "predefined" ]]; then
            local predefined={}
            while read -r line; do
                predefined=$(jq --arg key "${line}" --arg value "${ip}" '. + {($key): $value}' <<<"${predefined}") || return 1
            done < <({ jq -r '.[]' <<<"${domainRules}"; jq -r '.[]' <<<"${suffixRules}"; } | grep -v '^$' | sort -u)

            if ! writeRoutingJsonConfig "${singBoxConfigPath}dns.json" <<EOF
{
  "dns": {
    "servers": [
      {
        "tag": "${localTag}",
        "type": "local"
      },
      {
        "tag": "${hostsTag}",
        "type": "hosts",
        "predefined": ${predefined}
      }
    ],
    "rules": [
      {
        "domain":${domainRules},
        "domain_suffix":${suffixRules},
        "server":"${hostsTag}"
      }
    ]
  },
  "route": {
    "rule_set": ${ruleSet},
    "rules": [
      {
        "rule_set": ${ruleSetTag},
        "domain": ${domainRules},
        "domain_suffix": ${suffixRules},
        "action": "resolve",
        "server": "${hostsTag}"
      }
    ],
    "default_domain_resolver": "${localTag}"
  }
}
EOF
            then
                errorCard "sing-box DNS/hosts 覆盖配置写入失败，已保留旧配置"
                return 1
            fi
            if ! updateRoutingJsonConfig "${singBoxConfigPath}dns.json" '
                if .route.rule_set == [] then del(.route.rule_set) else . end |
                (.dns.rules[] |= with_entries(select((.value | if type == "array" then length > 0 else true end)))) |
                (.route.rules[] |= with_entries(select((.value | if type == "array" then length > 0 else true end))))
            '; then
                errorCard "sing-box DNS/hosts 覆盖配置整理失败，已保留旧配置"
                return 1
            fi
        else
            if ! writeRoutingJsonConfig "${singBoxConfigPath}dns.json" <<EOF
{
  "dns": {
    "servers": [
      {
        "tag": "${localTag}",
        "type": "local"
      },
      {
        "tag": "${routingTag}",
        "type": "udp",
        "server": "${ip}"
      }
    ],
    "rules": [
      {
        "rule_set": ${ruleSetTag},
        "domain": ${domainRules},
        "domain_suffix": ${suffixRules},
        "server":"${routingTag}"
      }
    ]
  },
  "route":{
    "rule_set":${ruleSet},
    "rules": [
      {
        "rule_set": ${ruleSetTag},
        "domain": ${domainRules},
        "domain_suffix": ${suffixRules},
        "action": "resolve",
        "server": "${routingTag}"
      }
    ],
    "default_domain_resolver": "${localTag}"
  }
}
EOF
            then
                errorCard "sing-box DNS 分流配置写入失败，已保留旧配置"
                return 1
            fi
            if ! updateRoutingJsonConfig "${singBoxConfigPath}dns.json" '
                if .route.rule_set == [] then del(.route.rule_set) else . end |
                (.dns.rules[] |= with_entries(select((.value | if type == "array" then length > 0 else true end)))) |
                (.route.rules[] |= with_entries(select((.value | if type == "array" then length > 0 else true end))))
            '; then
                errorCard "sing-box DNS 分流配置整理失败，已保留旧配置"
                return 1
            fi
        fi
    fi
}
# 设置 DNS 分流
setUnlockDNS() {
    autoRead dns_routing_server "请输入分流的DNS:" setDNS
    if [[ -n ${setDNS} ]]; then
        echoContent title "\n┌─ DNS 分流规则 ─────────────────────────────────────"
        menuLine "录入示例：netflix,disney,hulu"
        menuClose
        autoRead routing_domain_rules "请按照上面示例录入域名:" domainList

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
    exit 0
}

# 移除 DNS/hosts 配置
removeUnlockRoutingConfig() {
    local title=$1
    local checkXrayFile=${2:-}
    dnsRoutingBackupCreate || { errorCard "${title}配置备份失败，已取消移除"; return 1; }
    if [[ "${coreInstallType}" == 1 && ( -z "${checkXrayFile}" || -f "${configPath}11_dns.json" ) ]]; then
        if ! writeRoutingJsonConfig "${configPath}11_dns.json" <<EOF
{
	"dns": {
		"servers": [
			"localhost"
		]
	}
}
EOF
        then
            errorCard "${title}配置移除失败，已保留旧配置"
            dnsRoutingAbortChange "${title}配置移除失败"
            return 1
        fi
    fi

    if [[ -n "${singBoxConfigPath:-}" && -f "${singBoxConfigPath}dns.json" ]]; then
        local localTag
        localTag="padm-local"
        if ! writeRoutingJsonConfig "${singBoxConfigPath}dns.json" <<EOF
{
    "dns": {
        "servers":[
            {
                "tag":"${localTag}",
                "type":"local"
            }
        ]
    }
}
EOF
        then
            errorCard "sing-box ${title}配置移除失败，已保留旧配置"
            dnsRoutingAbortChange "${title}配置移除失败"
            return 1
        fi
    fi

    dnsRoutingReloadOrRollback "${title}" || return 1

    successCard "卸载成功"

    exit 0
}

# 移除 DNS 分流
removeUnlockDNS() { removeUnlockRoutingConfig "DNS 分流" 1; }

# 移除 DNS/hosts 覆盖
removeUnlockSNI() { removeUnlockRoutingConfig "DNS/hosts 覆盖"; }
