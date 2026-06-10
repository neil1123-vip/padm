#!/usr/bin/env bash

# DNS/hosts 路由与覆盖
dnsRouting() {

    if [[ -z "${configPath}" ]]; then
        errorCard "未安装，请使用脚本安装"
        menu
        exit 0
    fi
    echoContent title "\n┌─ DNS 分流 ─────────────────────────────────────────"
    menuLine "只改变核心内指定域名的 DNS 解析，不会修改系统 DNS"
    menuLine "适合少量域名定向解析；如果目标是固定后端 IP，优先用 DNS/hosts 覆盖"
    menuItem 1 "添加" "添加 DNS 分流配置"
    menuDangerItem 2 "卸载" "移除 DNS 分流配置"
    menuReturnItem 3 "返回分流工具" "回到上一级分流菜单"
    menuClose
    autoRead dns_routing_menu "请选择:" selectType

    case ${selectType} in
    1)
        setUnlockDNS
        ;;
    2)
        removeUnlockDNS
        ;;
    3)
        routingToolsMenu
        ;;
    *)
        errorCard "选择错误"
        dnsRouting "$1"
        ;;
    esac
}

# DNS/hosts 覆盖
sniRouting() {

    if [[ -z "${configPath}" ]]; then
        errorCard "未安装，请使用脚本安装"
        menu
        exit 0
    fi
    echoContent title "\n┌─ DNS/hosts 覆盖 ───────────────────────────────────"
    menuLine "把指定域名在核心内解析到指定 IP；这不是 Nginx/TCP 反向代理"
    menuLine "Xray 支持 geosite/domain 规则；sing-box 使用 remote rule_set 与 domain_suffix"
    menuItem 1 "添加" "添加 DNS/hosts 覆盖规则"
    menuDangerItem 2 "卸载" "移除 DNS/hosts 覆盖配置"
    menuReturnItem 3 "返回分流工具" "回到上一级分流菜单"
    menuClose
    autoRead sni_routing_menu "请选择:" selectType

    case ${selectType} in
    1)
        setUnlockSNI
        ;;
    2)
        removeUnlockSNI
        ;;
    3)
        routingToolsMenu
        ;;
    *)
        errorCard "选择错误"
        sniRouting "$1"
        ;;
    esac
}

# DNS/hosts 配置写入
setUnlockSNI() {
    autoRead sni_routing_ip "请输入要覆盖到的 IP:" setSNIP
    if [[ -n ${setSNIP} ]]; then
        echoContent title "\n┌─ DNS/hosts 覆盖规则 ───────────────────────────────"
        menuLine "Xray 录入示例：netflix,disney,hulu"
        menuLine "sing-box 支持 geosite 名称和具体域名，具体域名按 domain_suffix 写入"
        menuClose

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
                return 1
            fi
        fi
        if [[ -n "${singBoxConfigPath}" ]]; then
            echoContent yellow "录入示例:www.netflix.com,www.google.com"
            autoRead sni_singbox_domains "请按照上面示例录入域名:" singboxDomainList
            addSingBoxDNSConfig "${setSNIP}" "${singboxDomainList}" "predefined" || return 1
        fi
        reloadCore || return 1
        statusCard "DNS/hosts 覆盖" "规则写入成功"
    else
        errorCard "IP不可为空"
    fi
    exit 0
}

# 添加 Xray DNS 配置
addXrayDNSConfig() {
    local ip=$1
    local domainList=$2
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

    local rules=
    rules=$(initSingBoxRules "${domainList}" "dns") || { errorCard "sing-box DNS 规则生成失败，已保留旧配置"; return 1; }
    local domainRules suffixRules ruleSet ruleSetTag
    splitSingBoxRules "${rules}" domainRules suffixRules ruleSet ruleSetTag || { errorCard "sing-box DNS 规则拆分失败，已保留旧配置"; return 1; }
    if [[ -n "${singBoxConfigPath}" ]]; then
        if [[ "${actionType}" == "predefined" ]]; then
            local predefined={}
            while read -r line; do
                predefined=$(echo "${predefined}" | jq ".\"${line}\"=\"${ip}\"")
            done < <(echo "${domainList}" | tr ',' '\n' | grep -v '^$' | sort -n | uniq | paste -sd ',' | tr ',' '\n')

            if ! writeRoutingJsonConfig "${singBoxConfigPath}dns.json" <<EOF
{
  "dns": {
    "servers": [
        {
            "tag": "local",
            "type": "local"
        },
        {
            "tag": "hosts",
            "type": "hosts",
            "predefined": ${predefined}
        }
    ],
    "rules": [
        {
            "domain":${domainRules},
            "domain_suffix":${suffixRules},
            "server":"hosts"
        }
    ]
  }
}
EOF
            then
                errorCard "sing-box DNS/hosts 覆盖配置写入失败，已保留旧配置"
                return 1
            fi
            if ! updateRoutingJsonConfig "${singBoxConfigPath}dns.json" '(.dns.rules[] |= with_entries(select((.value | if type == "array" then length > 0 else true end))))'; then
                errorCard "sing-box DNS/hosts 覆盖配置整理失败，已保留旧配置"
                return 1
            fi
        else
            if ! writeRoutingJsonConfig "${singBoxConfigPath}dns.json" <<EOF
{
  "dns": {
    "servers": [
      {
        "tag": "local",
        "type": "local"
      },
      {
        "tag": "dnsRouting",
        "type": "udp",
        "server": "${ip}"
      }
    ],
    "rules": [
      {
        "rule_set": ${ruleSetTag},
        "domain": ${domainRules},
        "domain_suffix": ${suffixRules},
        "server":"dnsRouting"
      }
    ]
  },
  "route":{
    "rule_set":${ruleSet}
  }
}
EOF
            then
                errorCard "sing-box DNS 分流配置写入失败，已保留旧配置"
                return 1
            fi
            if ! updateRoutingJsonConfig "${singBoxConfigPath}dns.json" 'if .route.rule_set == [] then del(.route.rule_set) else . end | (.dns.rules[] |= with_entries(select((.value | if type == "array" then length > 0 else true end))))'; then
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

        if ! addXrayDNSConfig "${setDNS}" "${domainList}"; then
            return 1
        fi

        if [[ -n "${singBoxConfigPath}" ]]; then
            addSingBoxOutbound 01_direct_outbound || { errorCard "sing-box direct 出站写入失败，已保留旧配置"; return 1; }
            if ! addSingBoxDNSConfig "${setDNS}" "${domainList}"; then
                return 1
            fi
        fi

        reloadCore || return 1

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

# 移除 DNS 分流
removeUnlockDNS() {
    if [[ "${coreInstallType}" == "1" && -f "${configPath}11_dns.json" ]]; then
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
            errorCard "DNS 分流配置移除失败，已保留旧配置"
            return 1
        fi
    fi

    if [[ "${coreInstallType}" == "2" && -f "${singBoxConfigPath}dns.json" ]]; then
        if ! writeRoutingJsonConfig "${singBoxConfigPath}dns.json" <<EOF
{
    "dns": {
        "servers":[
            {
                "type":"local"
            }
        ]
    }
}
EOF
        then
            errorCard "sing-box DNS 分流配置移除失败，已保留旧配置"
            return 1
        fi
    fi

    reloadCore || return 1

    successCard "卸载成功"

    exit 0
}

# 移除 DNS/hosts 覆盖
removeUnlockSNI() {
    if [[ "${coreInstallType}" == 1 ]]; then
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
            errorCard "DNS/hosts 覆盖配置移除失败，已保留旧配置"
            return 1
        fi
    fi

    if [[ "${coreInstallType}" == "2" && -f "${singBoxConfigPath}dns.json" ]]; then
        if ! writeRoutingJsonConfig "${singBoxConfigPath}dns.json" <<EOF
{
    "dns": {
        "servers":[
            {
                "type":"local"
            }
        ]
    }
}
EOF
        then
            errorCard "sing-box DNS/hosts 覆盖配置移除失败，已保留旧配置"
            return 1
        fi
    fi

    reloadCore || return 1
    successCard "卸载成功"

    exit 0
}
