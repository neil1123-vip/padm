#!/usr/bin/env bash

ACCESS_CONTROL_ACTIVE_BACKUP_DIR=

accessControlMenu() {
    if [[ -z "${configPath}" ]]; then
        coreNotInstalledErrorCard
        return 1
    fi
    local accessControlStatus=
    while true; do
        echoContent title "\n┌─ 访问控制 ─────────────────────────────────────────"
        menuLine "管理域名/IP 阻断、直连例外和区域阻断规则"
        menuLine "这是服务端出站与访问限制，不会修改客户端订阅入口"
        menuLine "Xray 使用 routing + blackhole/direct；sing-box 使用 rule_set/domain_suffix/ip_cidr"
        menuItem 1 "查看当前访问控制" "显示 Xray / sing-box 当前阻断与例外"
        menuItem 2 "添加域名阻断" "添加 geosite 或自定义域名阻断"
        menuItem 3 "添加 IP/CIDR 阻断" "添加自定义 IP、CIDR 或 geoip 规则"
        menuItem 4 "添加直连例外" "添加优先直连域名规则"
        menuDangerItem 5 "区域阻断策略" "屏蔽 geosite:cn / geoip:cn 等高风险策略"
        menuItem 6 "移除访问控制" "按类型移除阻断或例外规则"
        menuReturnItem 7 "返回路由与访问控制" "回到上级菜单"
        menuClose

        accessControlStatus=
        autoRead access_control_menu "请选择:" accessControlStatus || return 0
        case "${accessControlStatus}" in
        1) showAccessControlStatus || true; continue ;;
        2) addBlockedDomains || true; continue ;;
        3) addBlockedIPs || true; continue ;;
        4) addDirectAllowDomains || true; continue ;;
        5) manageRegionalBlockPolicy || true; continue ;;
        6) removeAccessControlMenu || true; continue ;;
        7) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}

showAccessControlStatus() {
    echoContent title "\n┌─ 当前访问控制 ─────────────────────────────────────"
    if [[ "${coreInstallType}" == "1" && -f "${configPath}09_routing.json" ]]; then
        menuLine "Xray 域名阻断："
        jq -r '.routing.rules[]? | select(.outboundTag=="blackhole_out" and (.domain != null)) | .domain[]?' "${configPath}09_routing.json" | sed 's/^/  /' || true
        menuLine "Xray IP/CIDR 阻断："
        jq -r '.routing.rules[]? | select(.outboundTag=="blackhole_ip_out" and (.ip != null)) | .ip[]?' "${configPath}09_routing.json" | sed 's/^/  /' || true
        menuLine "Xray 直连例外："
        jq -r '.routing.rules[]? | select(.outboundTag=="allow_domain_direct_outbound" and (.domain != null)) | .domain[]?' "${configPath}09_routing.json" | sed 's/^/  /' || true
    else
        menuLine "Xray：未检测到访问控制路由"
    fi

    if [[ -n "${singBoxConfigPath}" ]]; then
        menuLine "sing-box 域名阻断："
        showSingBoxAccessRuleFile "block_domain_route"
        showSingBoxAccessRuleFile "cn_block_route"
        menuLine "sing-box IP/CIDR 阻断："
        showSingBoxAccessRuleFile "block_ip_route"
        showSingBoxAccessRuleFile "cn_block_ip_route"
        menuLine "sing-box 直连例外："
        showSingBoxAccessRuleFile "00_allow_domain_route"
    else
        menuLine "sing-box：未检测到配置"
    fi
    menuClose
}

showSingBoxAccessRuleFile() {
    local name=$1
    local file="${singBoxConfigPath}${name}.json"
    [[ -f "${file}" ]] || return 0
    menuLine "  ${name}:"
    jq -r '
        .route.rules[]? as $rule |
        ($rule.rule_set[]? // empty),
        ($rule.domain[]? // empty),
        ($rule.domain_suffix[]? // empty),
        ($rule.ip_cidr[]? // empty)
    ' "${file}" | sed 's/^/    /' || true
    jq -r '.route.rule_set[]?.url? // empty' "${file}" | sed 's/^/    /' || true
}

accessControlAbortChange() {
    local backupDir
    local rollbackMessage
    backupDir=$(accessControlBackupDir) || return 1
    if accessControlBackupRestore; then
        accessControlBackupCleanup || errorCard "访问控制修改失败，旧配置已恢复，但备份目录清理失败: $(accessControlBackupDir)"
    else
        padmForgetCleanupPath "${backupDir}"
        ACCESS_CONTROL_ACTIVE_BACKUP_DIR=
        coreSetRollbackFailureMessage rollbackMessage "访问控制修改失败" "${backupDir}"
        errorCard "${rollbackMessage}"
    fi
    return 1
}

addBlockedDomains() {
    local domainList
    echoContent title "\n┌─ 添加域名阻断 ─────────────────────────────────────"
    menuLine "示例：openai,geosite:category-ads-all,domain:example.com,full:api.example.com,keyword:tracker"
    menuLine "具体域名会按 domain/domain_suffix 匹配，不再生成宽泛 regexp"
    menuLine "添加规则为增量配置，不会删除之前设置的内容"
    menuClose
    autoRead access_block_domains "请录入要阻断的域名或规则:" domainList
    if [[ -z "${domainList}" ]]; then
        coreDomainRequiredErrorCard
        return 1
    fi

    accessControlBackupCreate || return 1
    if [[ "${coreInstallType}" == "1" ]]; then
        addXrayRouting blackhole_out outboundTag "${domainList}" || { accessControlAbortChange; return 1; }
        addXrayOutbound blackhole_out || { accessControlAbortChange; return 1; }
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        addSingBoxRouteRule "block_domain_outbound" "${domainList}" "block_domain_route" || { accessControlAbortChange; return 1; }
        addSingBoxOutbound "01_direct_outbound" || { accessControlAbortChange; return 1; }
    fi
    applyAccessControlConfigChange || return 1
    successCard "域名阻断规则已添加"
}

addBlockedIPs() {
    local ipList normalizedIPs
    echoContent title "\n┌─ 添加 IP/CIDR 阻断 ────────────────────────────────"
    menuLine "录入示例：1.1.1.1,8.8.8.8,1.1.1.0/24,2400:3200::/32,cn"
    menuClose
    autoRead access_block_ips "请录入 IP/CIDR:" ipList
    normalizedIPs=$(validateAccessIPList "${ipList}") || { errorCard "IP/CIDR 格式错误"; return 1; }
    if [[ -z "${normalizedIPs}" ]]; then
        errorCard "IP/CIDR 不可为空"
        return 1
    fi

    accessControlBackupCreate || return 1
    if [[ "${coreInstallType}" == "1" ]]; then
        addXrayIPRouting blackhole_ip_out outboundTag "${normalizedIPs}" || { accessControlAbortChange; return 1; }
        addXrayOutbound blackhole_ip_out || { accessControlAbortChange; return 1; }
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        addSingBoxIPRouteRule "block_ip_outbound" "${normalizedIPs}" "block_ip_route" || { accessControlAbortChange; return 1; }
    fi
    applyAccessControlConfigChange || return 1
    successCard "IP/CIDR 阻断规则已添加"
}

addDirectAllowDomains() {
    local allowDomainList
    echoContent title "\n┌─ 添加直连例外 ─────────────────────────────────────"
    menuLine "直连例外会优先于阻断规则，适合系统更新、证书签发或必要服务"
    menuLine "录入示例：dl.google.com,apple.com,domain:example.com,full:api.example.com"
    menuClose
    autoRead access_allow_domains "请录入直连例外域名:" allowDomainList
    if [[ -z "${allowDomainList}" ]]; then
        coreDomainRequiredErrorCard
        return 1
    fi

    accessControlBackupCreate || return 1
    if [[ "${coreInstallType}" == "1" ]]; then
        addXrayRouting allow_domain_direct_outbound outboundTag "${allowDomainList}" "top" || { accessControlAbortChange; return 1; }
        addXrayOutbound allow_domain_direct_outbound || { accessControlAbortChange; return 1; }
    fi
    if [[ -n "${singBoxConfigPath}" ]]; then
        addSingBoxRouteRule "01_direct_outbound" "${allowDomainList}" "00_allow_domain_route" || { accessControlAbortChange; return 1; }
        addSingBoxOutbound "01_direct_outbound" || { accessControlAbortChange; return 1; }
    fi
    applyAccessControlConfigChange || return 1
    successCard "直连例外已添加"
}

manageRegionalBlockPolicy() {
    local policyStatus allowDomainList extraAllowDomainList
    while true; do
        allowDomainList="dl.google.com,apple.com,bing.com,microsoft.com,gstatic,xn--ngstr-lra8j.com,googleapis.com,googleapis.cn"
        extraAllowDomainList=
        echoContent title "\n┌─ 区域阻断策略 ─────────────────────────────────────"
        menuLine "危险操作：可能影响系统更新、证书签发、应用连接和客户端服务"
        menuLine "默认直连例外：${allowDomainList}"
        menuDangerItem 1 "屏蔽 geosite:cn + geoip:cn" "同时阻断大陆域名和大陆 IP"
        menuDangerItem 2 "仅屏蔽 geosite:cn" "只按域名规则阻断"
        menuDangerItem 3 "仅屏蔽 geoip:cn" "只按 IP 规则阻断"
        menuReturnItem 4 "返回" "回到访问控制"
        menuClose
        policyStatus=
        autoRead access_region_policy "请选择:" policyStatus || return 0
        case "${policyStatus}" in
        4) return 0 ;;
        1 | 2 | 3) ;;
        *) coreSelectionErrorCard "选择错误"; continue ;;
        esac
        autoRead access_region_extra_allow "追加直连例外域名[可留空，多个用英文逗号]:" extraAllowDomainList || return 0
        if [[ -n "${extraAllowDomainList}" ]]; then
            allowDomainList="${allowDomainList},${extraAllowDomainList}"
        fi

        accessControlBackupCreate || return 1
        if [[ "${coreInstallType}" == "1" ]]; then
            if [[ "${policyStatus}" == "1" || "${policyStatus}" == "2" ]]; then
                addXrayRouting blackhole_out outboundTag "cn" || { accessControlAbortChange; return 1; }
                addXrayOutbound blackhole_out || { accessControlAbortChange; return 1; }
            fi
            if [[ "${policyStatus}" == "1" || "${policyStatus}" == "3" ]]; then
                addXrayIPRouting blackhole_ip_out outboundTag "cn" || { accessControlAbortChange; return 1; }
                addXrayOutbound blackhole_ip_out || { accessControlAbortChange; return 1; }
            fi
            addXrayRouting allow_domain_direct_outbound outboundTag "${allowDomainList}" "top" || { accessControlAbortChange; return 1; }
            addXrayOutbound allow_domain_direct_outbound || { accessControlAbortChange; return 1; }
        fi
        if [[ -n "${singBoxConfigPath}" ]]; then
            if [[ "${policyStatus}" == "1" || "${policyStatus}" == "2" ]]; then
                addSingBoxRouteRule "cn_block_outbound" "cn" "cn_block_route" || { accessControlAbortChange; return 1; }
            fi
            if [[ "${policyStatus}" == "1" || "${policyStatus}" == "3" ]]; then
                addSingBoxGeoIPRouteRule "block_ip_outbound" "cn" "cn_block_ip_route" || { accessControlAbortChange; return 1; }
            fi
            addSingBoxRouteRule "01_direct_outbound" "${allowDomainList}" "00_allow_domain_route" || { accessControlAbortChange; return 1; }
            addSingBoxOutbound "01_direct_outbound" || { accessControlAbortChange; return 1; }
        fi
        applyAccessControlConfigChange || return 1
        successCard "区域阻断策略已应用"
        return $?
    done
}

removeAccessControlMenu() {
    local removeStatus=
    while true; do
        echoContent title "\n┌─ 移除访问控制 ─────────────────────────────────────"
        menuItem 1 "只移除域名阻断" "保留 IP 阻断和直连例外"
        menuItem 2 "只移除 IP/CIDR 阻断" "保留域名阻断和直连例外"
        menuItem 3 "只移除直连例外" "保留阻断规则"
        menuItem 4 "只移除区域阻断" "移除 cn 域名/IP 区域策略"
        menuDangerItem 5 "移除全部访问控制" "移除域名/IP 阻断、区域阻断和直连例外"
        menuReturnItem 6 "返回" "回到访问控制"
        menuClose
        removeStatus=
        autoRead access_remove_menu "请选择:" removeStatus || return 0
        case "${removeStatus}" in
        1|2|3|4|5) ;;
        6) return 0 ;;
        *) coreSelectionErrorCard "选择错误"; continue ;;
        esac
        accessControlBackupCreate || return 1
        case "${removeStatus}" in
        1) removeAccessControlByKind domain || { accessControlAbortChange; return 1; } ;;
        2) removeAccessControlByKind ip || { accessControlAbortChange; return 1; } ;;
        3) removeAccessControlByKind allow || { accessControlAbortChange; return 1; } ;;
        4) removeAccessControlByKind region || { accessControlAbortChange; return 1; } ;;
        5) removeAccessControlByKind all || { accessControlAbortChange; return 1; } ;;
        esac
        applyAccessControlConfigChange || return 1
        successCard "访问控制规则已移除"
        return $?
    done
}

removeAccessControlByKind() {
    local kind=$1
    if [[ "${coreInstallType}" == "1" ]]; then
        case "${kind}" in
        domain)
            unInstallRouting blackhole_out outboundTag || return 1
            removeXrayOutbound blackhole_out || return 1
            ;;
        ip)
            unInstallRouting blackhole_ip_out outboundTag || return 1
            removeXrayOutbound blackhole_ip_out || return 1
            ;;
        allow)
            unInstallRouting allow_domain_direct_outbound outboundTag || return 1
            removeXrayOutbound allow_domain_direct_outbound || return 1
            ;;
        region)
            removeXrayRegionalRules || return 1
            ;;
        all)
            unInstallRouting blackhole_out outboundTag || return 1
            unInstallRouting blackhole_ip_out outboundTag || return 1
            unInstallRouting allow_domain_direct_outbound outboundTag || return 1
            removeXrayOutbound blackhole_out || return 1
            removeXrayOutbound blackhole_ip_out || return 1
            removeXrayOutbound allow_domain_direct_outbound || return 1
            ;;
        esac
    fi

    if [[ -n "${singBoxConfigPath}" ]]; then
        case "${kind}" in
        domain)
            removeSingBoxConfig "block_domain_route" || return 1
            removeSingBoxConfig "block_domain_outbound" || return 1
            ;;
        ip)
            removeSingBoxConfig "block_ip_route" || return 1
            removeSingBoxConfig "block_ip_outbound" || return 1
            ;;
        allow)
            removeSingBoxConfig "00_allow_domain_route" || return 1
            ;;
        region)
            removeSingBoxConfig "cn_block_route" || return 1
            removeSingBoxConfig "cn_block_outbound" || return 1
            removeSingBoxConfig "cn_block_ip_route" || return 1
            ;;
        all)
            removeSingBoxConfig "block_domain_route" || return 1
            removeSingBoxConfig "block_domain_outbound" || return 1
            removeSingBoxConfig "block_ip_route" || return 1
            removeSingBoxConfig "block_ip_outbound" || return 1
            removeSingBoxConfig "cn_block_route" || return 1
            removeSingBoxConfig "cn_block_outbound" || return 1
            removeSingBoxConfig "cn_block_ip_route" || return 1
            removeSingBoxConfig "00_allow_domain_route" || return 1
            ;;
        esac
    fi
}

removeXrayRegionalRules() {
    if [[ -f "${configPath}09_routing.json" ]]; then
        updateRoutingJsonConfig "${configPath}09_routing.json" '
            .routing.rules |= map(
                if .outboundTag == "blackhole_out" and ((.domain // []) | index("geosite:cn")) != null then
                    .domain -= ["geosite:cn"] |
                    if (.domain | length) == 0 then empty else . end
                elif .outboundTag == "blackhole_ip_out" and ((.ip // []) | index("geoip:cn")) != null then
                    .ip -= ["geoip:cn"] |
                    if (.ip | length) == 0 then empty else . end
                else . end
            )
        ' || return 1
    fi
}

validateAccessIPList() {
    local input=$1
    local item output= seen=,
    while read -r item; do
        item=$(echo "${item}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "${item}" ]] && continue
        if [[ "${item}" != "cn" && ! "${item}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$ && ! "${item}" =~ ^[0-9a-f:]+(/[0-9]{1,3})?$ ]]; then
            return 1
        fi
        if [[ "${seen}" != *",${item},"* ]]; then
            seen="${seen}${item},"
            output="${output}${output:+,}${item}"
        fi
    done < <(echo "${input}" | tr ',' '\n')
    echo "${output}"
}

accessControlBackupDir() {
    if [[ -n "${ACCESS_CONTROL_ACTIVE_BACKUP_DIR:-}" ]]; then
        printf '%s\n' "${ACCESS_CONTROL_ACTIVE_BACKUP_DIR}"
        return 0
    fi
    if [[ -n "${PADM_ACCESS_CONTROL_BACKUP_DIR:-}" ]]; then
        printf '%s\n' "${PADM_ACCESS_CONTROL_BACKUP_DIR}"
        return 0
    fi
    return 1
}

accessControlSafeBackupDir() {
    local backupDir
    backupDir=$(accessControlBackupDir)
    padmRequireSafeAbsolutePath "${backupDir%/}"
}

accessControlSafeXrayConfigDir() {
    coreSafeConfigDir "${configPath:-}"
}

accessControlSafeSingBoxConfigDir() {
    coreSafeConfigDir "${singBoxConfigPath:-}"
}

accessControlManagedXrayFiles() {
    printf '%s\n' "09_routing.json" "blackhole_out.json" "blackhole_ip_out.json" "allow_domain_direct_outbound.json"
}

accessControlManagedSingBoxFiles() {
    printf '%s\n' "block_domain_route.json" "block_domain_outbound.json" "block_ip_route.json" "block_ip_outbound.json" "cn_block_route.json" "cn_block_outbound.json" "cn_block_ip_route.json" "00_allow_domain_route.json" "01_direct_outbound.json"
}

accessControlManagedXrayFile() {
    padmManagedFilePath "$(accessControlSafeXrayConfigDir)" "$1"
}

accessControlManagedSingBoxFile() {
    padmManagedFilePath "$(accessControlSafeSingBoxConfigDir)" "$1"
}

accessControlXrayTestLog() {
    padmTmpFilePath padm-access-xray-test.log
}

accessControlSingBoxTestLog() {
    padmTmpFilePath padm-access-sing-box-test.log
}

accessControlBackupCreate() {
    local backupDir
    local xrayConfigDir=
    local singBoxConfigDir=
    local file
    local managedFile
    local createdBackupDir
    local -a backupArgs=()
    local -a backupTargets=()
    [[ -n "${configPath:-}" ]] && xrayConfigDir=$(accessControlSafeXrayConfigDir) || true
    [[ -n "${singBoxConfigPath:-}" ]] && singBoxConfigDir=$(accessControlSafeSingBoxConfigDir) || true
    if [[ -n "${configPath:-}" && -z "${xrayConfigDir}" ]]; then
        return 1
    fi
    if [[ -n "${singBoxConfigPath:-}" && -z "${singBoxConfigDir}" ]]; then
        return 1
    fi
    if [[ -n "${xrayConfigDir}" ]]; then
        while IFS= read -r file; do
            managedFile=$(accessControlManagedXrayFile "${file}") || return 1
            backupArgs+=("xray/${file}" "${managedFile}")
            backupTargets+=("${managedFile}")
        done < <(accessControlManagedXrayFiles)
    fi
    if [[ -n "${singBoxConfigDir}" ]]; then
        while IFS= read -r file; do
            managedFile=$(accessControlManagedSingBoxFile "${file}") || return 1
            backupArgs+=("sing-box/${file}" "${managedFile}")
            backupTargets+=("${managedFile}")
        done < <(accessControlManagedSingBoxFiles)
    fi
    if [[ -n "${PADM_ACCESS_CONTROL_BACKUP_DIR:-}" ]]; then
        backupDir="${PADM_ACCESS_CONTROL_BACKUP_DIR%/}"
        padmIsSafeAbsolutePath "${backupDir}" || return 1
        removeManagedPathIfPresent "${backupDir}" || return 1
        padmWriteManagedFileBackupManifest "${backupDir}" "${backupArgs[@]}" || return 1
    else
        checkLogBackupCreate createdBackupDir "${backupTargets[@]}" || return 1
        backupDir="${createdBackupDir}"
    fi
    ACCESS_CONTROL_ACTIVE_BACKUP_DIR="${backupDir}"
}

accessControlBackupRestore() {
    local backupDir
    local xrayConfigDir=
    local singBoxConfigDir=
    backupDir=$(accessControlSafeBackupDir) || return 1
    [[ -d "${backupDir}" ]] || return 1
    [[ -n "${configPath:-}" ]] && xrayConfigDir=$(accessControlSafeXrayConfigDir) || true
    [[ -n "${singBoxConfigPath:-}" ]] && singBoxConfigDir=$(accessControlSafeSingBoxConfigDir) || true
    if [[ -n "${configPath:-}" && -z "${xrayConfigDir}" ]]; then
        return 1
    fi
    if [[ -n "${singBoxConfigPath:-}" && -z "${singBoxConfigDir}" ]]; then
        return 1
    fi
    padmRestoreManagedFileBackupManifest "${backupDir}"
}

accessControlBackupCleanup() {
    local backupDir
    backupDir=$(accessControlSafeBackupDir) || return 1
    removeManagedPathIfPresent "${backupDir}" || return 1
    padmForgetCleanupPath "${backupDir}"
    ACCESS_CONTROL_ACTIVE_BACKUP_DIR=
}

reportAccessControlApplyFailure() {
    local title=$1
    local message=$2
    local logFile=${3:-}
    echoContent title "\n┌─ ${title} ─────────────────────────────────"
    menuLine "${message}"
    [[ -n "${logFile}" ]] && menuLine "排查日志：${logFile}"
    menuClose
}

validateAccessControlConfig() {
    local logFile
    ACCESS_CONTROL_FAILURE_TITLE=
    ACCESS_CONTROL_FAILURE_LOG=
    if [[ "${coreInstallType}" == "1" && -x /etc/padm/xray/xray ]]; then
        logFile=$(accessControlXrayTestLog)
        if ! /etc/padm/xray/xray -test -confdir /etc/padm/xray/conf >"${logFile}" 2>&1; then
            ACCESS_CONTROL_FAILURE_TITLE="$(xrayConfigValidationFailureTitle)"
            ACCESS_CONTROL_FAILURE_LOG="${logFile}"
            return 1
        fi
    fi
    if [[ -n "${singBoxConfigPath}" && -x /etc/padm/sing-box/sing-box ]]; then
        logFile=$(accessControlSingBoxTestLog)
        if ! singBoxMergeConfigForValidation /etc/padm/sing-box/sing-box "${logFile}"; then
            ACCESS_CONTROL_FAILURE_TITLE="sing-box 配置校验失败"
            ACCESS_CONTROL_FAILURE_LOG="${logFile}"
            return 1
        fi
    fi
}

applyAccessControlConfigChange() {
    local backupDir
    local rollbackMessage
    backupDir=$(accessControlBackupDir)
    if ! validateAccessControlConfig; then
        if accessControlBackupRestore; then
            accessControlBackupCleanup || true
            reportAccessControlApplyFailure "${ACCESS_CONTROL_FAILURE_TITLE:-访问控制配置校验失败}" "访问控制配置未通过校验，已回滚本次修改" "${ACCESS_CONTROL_FAILURE_LOG:-}"
        else
            padmForgetCleanupPath "${backupDir}"
            ACCESS_CONTROL_ACTIVE_BACKUP_DIR=
            coreSetRollbackFailureMessage rollbackMessage "访问控制配置未通过校验" "${backupDir}"
            reportAccessControlApplyFailure "${ACCESS_CONTROL_FAILURE_TITLE:-访问控制配置校验失败}" "${rollbackMessage}" "${ACCESS_CONTROL_FAILURE_LOG:-}"
        fi
        return 1
    fi
    if ! reloadCore; then
        if ! accessControlBackupRestore; then
            padmForgetCleanupPath "${backupDir}"
            ACCESS_CONTROL_ACTIVE_BACKUP_DIR=
            coreSetRollbackFailureMessage rollbackMessage "核心重载失败" "${backupDir}"
            reportAccessControlApplyFailure "访问控制重载失败" "${rollbackMessage}"
            return 1
        fi
        accessControlBackupCleanup || true
        local rollbackMessage
        coreSetRollbackResultMessage rollbackMessage "核心重载失败" "已回滚本次修改" reloadCore "恢复旧配置后重载仍失败，请检查核心服务日志"
        reportAccessControlApplyFailure "访问控制重载失败" "${rollbackMessage}"
        return 1
    fi
    if ! accessControlBackupCleanup; then
        errorCard "访问控制已应用，但备份目录清理失败: ${backupDir}"
        return 1
    fi
    return 0
}
