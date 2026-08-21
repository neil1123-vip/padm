#!/usr/bin/env bash

showSubscriptionServerRoleSummary() {
    local state
    local role
    local roleText
    local enabledText
    local address
    local peerCount
    state=$(subscriptionWireGuardReadState) || {
        errorCard "WireGuard 控制面状态损坏或不可读" "请先修复 $(subscriptionWireGuardStateFile)"
        return 1
    }
    role=$(jq -r '.role' <<<"${state}")
    case "${role}" in
    main) roleText="主控" ;;
    controlled) roleText="被控" ;;
    uninitialized)
        menuLine "多服务器角色：$(uiStyle value "未启用")；可直接使用本机订阅"
        return 0
        ;;
    *) return 1 ;;
    esac
    if [[ "$(jq -r '.enabled' <<<"${state}")" == "true" ]]; then
        enabledText="已启用"
    else
        enabledText="未启用"
    fi
    address=$(jq -r 'if (.address // "") == "" then "未配置" else .address end' <<<"${state}")
    peerCount=$(jq -r '.peers | length' <<<"${state}")
    menuLine "当前服务器角色：$(uiStyle value "${roleText}")；WireGuard 控制面：$(uiStyle value "${enabledText}")；内网地址：$(uiStyle value "${address}")；Peer：$(uiStyle value "${peerCount}")"
}

subscriptionCurrentRoleNormalized() {
    local role
    role=$(subscriptionWireGuardRole) || return 1
    case "${role}" in
    uninitialized | main | controlled) printf '%s' "${role}" ;;
    *) return 1 ;;
    esac
}

subscriptionRemoteScopeEnabled() {
    local state
    state=$(subscriptionWireGuardReadState) || return 1
    jq -e '.role == "main" and .enabled == true' <<<"${state}" >/dev/null 2>&1
}

subscriptionRequireLocalPublisherRole() {
    local role
    role=$(subscriptionCurrentRoleNormalized) || {
        errorCard "WireGuard 控制面状态损坏或不可读" "请先修复 $(subscriptionWireGuardStateFile)"
        return 1
    }
    case "${role}" in
    uninitialized | main) return 0 ;;
    controlled)
        errorCard "当前机器已初始化为被控" "被控不能安装公网订阅服务、执行本机同步或修改本机订阅状态"
        return 1
        ;;
    esac
}

runSubscriptionMainControllerWizard() {
    local createInvite=
    initSubscriptionWireGuardMain || return 1
    statusCard "主控建链已完成" "WireGuard 使用 UDP 隧道，控制 API 只在隧道内使用 HTTP" "此步骤不申请 TLS 证书；公网发布订阅时再单独配置 HTTPS"
    autoConfirm subscription_create_first_invite "现在创建第一个被控邀请？" n createInvite
    if [[ "${createInvite}" == "y" ]]; then
        createSubscriptionWireGuardInviteMenu
    else
        statusCard "已跳过创建邀请" "稍后可从 主控首页 -> 服务器与协同 创建"
    fi
}

runSubscriptionControlledWizard() {
    local credential= credentialJson state existingInviteId replaceConfirmed=false confirmReplace=
    subscriptionWireGuardReadSecret credential "请粘贴主控邀请:" || return 1
    credentialJson=$(subscriptionWireGuardCredentialDecode "${credential}") || { errorCard "主控邀请无效"; return 1; }
    if [[ "$(jq -r '.kind' <<<"${credentialJson}")" != "invite" ]]; then
        errorCard "请粘贴主控邀请"
        return 1
    fi
    state=$(subscriptionWireGuardReadState) || { errorCard "WireGuard 状态读取失败"; return 1; }
    if [[ "$(jq -r '.role' <<<"${state}")" == "controlled" ]]; then
        existingInviteId=$(jq -r '.join_invite_id // empty' <<<"${state}") || return 1
        if [[ "${existingInviteId}" != "$(jq -r '.invite_id' <<<"${credentialJson}")" ]]; then
            warnCard "当前被控已接入其他主控" "替换会重写本机 WireGuard 主控 Peer；失败时恢复旧状态"
            autoConfirm subscription_replace_controller "确认替换现有主控？" n confirmReplace
            [[ "${confirmReplace}" == "y" ]] || { statusCard "已取消替换主控"; return 1; }
            replaceConfirmed=true
        fi
    fi
    subscriptionWireGuardJoinInvite "${credentialJson}" "${replaceConfirmed}" || return 1
    successCard "被控已按邀请完成初始化" "内网地址由主控预留，无需手工填写" "控制 API 只在 WireGuard 隧道内使用 HTTP，不需要 TLS 证书"
    showSubscriptionWireGuardJoinReceipt
    showSubscriptionWireGuardStatus
}

ensureSubscriptionServiceForSharedLinks() {
    local confirm=
    subscribePort=
    subscribeDomain=
    subscribeType=
    if ! readNginxSubscribe; then
        errorCard "订阅 Nginx 配置损坏" "请先修复受管 subscribe.conf，再生成分享链接"
        return 2
    fi
    if [[ -n "${subscribePort:-}" ]]; then
        return 0
    fi

    statusCard "当前还不能直接发分享链接" "未检测到可用的公网订阅发布服务" "如果要把订阅链接发给客户端，请先安装/更新订阅服务" "仅作为被控接入主控时，可以先跳过这一步"
    autoRead shared_subscription_install_service "现在先安装/更新订阅服务？[yes/no，默认 yes]:" confirm
    confirm=${confirm:-yes}
    if [[ "${confirm}" == "yes" || "${confirm}" == "y" ]]; then
        if ! installSubscribe; then
            errorCard "订阅服务安装或更新失败，暂时不能生成分享链接"
            return 2
        fi
        showSubscriptionServiceStatus
        return 0
    fi

    statusCard "已跳过订阅服务安装" "本次仍可保存订阅对象和执行同步" "等之后安装好订阅服务，再来刷新并查看链接"
    return 1
}

runSubscriptionSyncAfterMutation() {
    local reason=${1:-subscription-change}
    if ! subscriptionGroupSyncEnabled; then
        statusCard "订阅变更已保存" "自动同步已关闭，等待手动完整同步（${reason}）"
        return 0
    fi
    statusCard "订阅变更已保存" "正在执行完整同步（${reason}）"
    if runSubscriptionGroupSync; then
        return 0
    fi
    warnCard "变更已保存，但后置完整同步失败" "请到 订阅同步 -> 状态与排障 查看失败原因，修复后手动重试"
    return 1
}

subscriptionRequireRole() {
    local expectedRole=$1
    local otherRole=$2
    local otherMessage=$3
    local otherHint=$4
    local role
    role=$(subscriptionCurrentRoleNormalized) || {
        errorCard "WireGuard 控制面状态损坏或不可读" "请先修复 $(subscriptionWireGuardStateFile)"
        return 1
    }
    case "${role}" in
    "${expectedRole}") return 0 ;;
    "${otherRole}")
        errorCard "${otherMessage}" "${otherHint}"
        return 1
        ;;
    *)
        errorCard "当前机器还没完成角色初始化" "请从本机订阅首页启用主控协同或接入主控"
        return 1
        ;;
    esac
}

subscriptionRequireMainRole() {
    subscriptionRequireRole main controlled \
        "当前机器已初始化为被控" "请进入 被控首页 -> 接入主控 / 查看本机状态 / 控制面与 Peer 细节"
}

subscriptionRequireControlledRole() {
    subscriptionRequireRole controlled main \
        "当前机器已初始化为主控" "请进入主控首页管理订阅、同步或控制面"
}

manageSubscriptionLocalHome() {
    subscriptionRequireLocalPublisherRole || return 1
    while true; do
        echoContent title "\n┌─ 本机订阅首页 ─────────────────────────────────────"
        showSubscriptionServerRoleSummary
        menuItem 1 "安装/更新订阅服务" "安装或刷新 Nginx 订阅发布配置"
        menuItem 2 "刷新并查看我的订阅链接" "重新生成并显示当前自用订阅"
        menuItem 3 "新建并发布订阅" "填写 ID、节点范围和额度，然后同步并拿到可发送的链接"
        menuItem 4 "查看并处理已有订阅" "刷新链接、改范围、改额度、启停或删除"
        menuItem 5 "订阅同步" "立即同步、自动同步、用量限额和状态排障"
        menuItem 6 "状态备份与恢复" "创建、恢复或重建 groups.json"
        menuItem 7 "启用主控协同" "将本机初始化为主控，保留现有订阅状态和服务"
        menuItem 8 "接入主控" "粘贴主控邀请，将本机初始化为被控"
        menuReturnItem 9 "返回主菜单" "回到 padm 管理面板"
        menuClose
        autoRead subscription_local_home_menu "请选择:" localHomeStatus
        case "${localHomeStatus}" in
        1) installSubscribe && showSubscriptionServiceStatus ;;
        2) subscribe ;;
        3) createAndSyncUserSubscriptionWizard ;;
        4) manageUserSubscriptionItem ;;
        5) manageSubscriptionSyncSettings ;;
        6) manageSubscriptionStateBackups ;;
        7) runSubscriptionMainControllerWizard; return ;;
        8) runSubscriptionControlledWizard; return ;;
        9) menu; return ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}

manageSubscriptionMainHome() {
    subscriptionRequireMainRole || return 1
    while true; do
        echoContent title "\n┌─ 主控首页 ─────────────────────────────────────────"
        showSubscriptionServerRoleSummary
        menuItem 1 "安装/更新订阅服务" "安装或刷新 Nginx 订阅发布配置"
        menuItem 2 "刷新并查看我的订阅链接" "重新生成并显示当前自用订阅"
        menuItem 3 "新建并发布订阅" "填写 ID、节点范围和额度，然后同步并拿到可发送的链接"
        menuItem 4 "查看并处理已有订阅" "刷新链接、改范围、改额度、启停或删除"
        menuItem 5 "订阅同步" "立即同步、自动同步、用量限额和状态排障"
        menuItem 6 "状态备份与恢复" "创建、恢复或重建 groups.json"
        menuItem 7 "服务器与协同" "查看来源，管理邀请、凭据、健康和服务器状态"
        menuItem 8 "控制面与连接" "查看凭据、Peer、地址，并处理重启或关闭"
        menuReturnItem 9 "返回主菜单" "回到 padm 管理面板"
        menuClose
        autoRead subscription_main_home_menu "请选择:" mainHomeStatus
        case "${mainHomeStatus}" in
        1) installSubscribe && showSubscriptionServiceStatus ;;
        2) subscribe ;;
        3) createAndSyncUserSubscriptionWizard ;;
        4) manageUserSubscriptionItem ;;
        5) manageSubscriptionSyncSettings ;;
        6) manageSubscriptionStateBackups ;;
        7) manageSubscriptionServers ;;
        8) manageSubscriptionMainControlDetails ;;
        9) menu; return ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}

manageSubscriptionControlledHome() {
    subscriptionRequireControlledRole || return 1
    while true; do
        echoContent title "\n┌─ 被控首页 ─────────────────────────────────────────"
        showSubscriptionServerRoleSummary
        menuItem 1 "接入主控" "粘贴主控邀请，完成接入并生成对应回执"
        menuItem 2 "查看本机状态" "查看角色、地址、Peer 和 WireGuard 状态"
        menuItem 3 "导入/更新主控接入凭据" "仅更新已有连接的主控端点或身份"
        menuItem 4 "显示接入回执/旧版被控凭据" "显式显示包含长期控制 Token 的接入秘密"
        menuItem 5 "查看控制面与 Peer 细节" "显示 WireGuard 状态以及与主控的 Peer 连接细节"
        menuItem 6 "重写配置并重启被控控制面" "重写配置并重启 WireGuard 和控制服务"
        menuDangerItem 7 "关闭被控控制面" "停止本机 WireGuard 控制面"
        menuReturnItem 8 "返回主菜单" "回到 padm 管理面板"
        menuClose
        autoRead subscription_controlled_home_menu "请选择:" controlledHomeStatus
        case "${controlledHomeStatus}" in
        1) runSubscriptionControlledWizard ;;
        2)
            echoContent title "\n┌─ 本机状态 ─────────────────────────────────────────"
            showSubscriptionServerRoleSummary
            showSubscriptionWireGuardStatus
            ;;
        3) importSubscriptionWireGuardMainCredential ;;
        4) showSubscriptionWireGuardControlledAccessCredential ;;
        5)
            echoContent title "\n┌─ 控制面与 Peer 细节 ───────────────────────────────"
            showSubscriptionWireGuardStatus
            showSubscriptionWireGuardPeers
            ;;
        6) restartSubscriptionWireGuardControl ;;
        7) disableSubscriptionWireGuardControl ;;
        8) menu; return ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}

manageSubscriptionMainControlDetails() {
    subscriptionRequireMainRole || return 1
    while true; do
        echoContent title "\n┌─ 控制面与连接细节 ─────────────────────────────────"
        menuLine "这里处理主控控制面的状态、连接和恢复动作。"
        menuLine "建议先查看凭据、Peer 和连接状态，再决定是否重启或关闭控制面。"
        showSubscriptionWireGuardStatus
        menuItem 1 "显示主控维护凭据" "仅用于维护已有连接，不用于首次接入"
        menuItem 2 "查看 Peer 和连接状态" "查看 WireGuard peer 和被控列表"
        menuItem 3 "查看控制面地址" "显示 WireGuard 内网 health/sync 地址"
        menuItem 4 "重写配置并重启主控控制面" "重写配置并重启控制服务"
        menuDangerItem 5 "关闭主控控制面" "停止本机 WireGuard 控制面"
        menuReturnItem 6 "返回主控首页" "回到上级菜单"
        menuClose
        autoRead subscription_main_control_details_menu "请选择:" mainControlDetailsStatus
        case "${mainControlDetailsStatus}" in
        1) showSubscriptionWireGuardMainCredential ;;
        2) showSubscriptionWireGuardPeers ;;
        3) showSubscriptionSourceControlUrls ;;
        4) restartSubscriptionWireGuardControl ;;
        5) disableSubscriptionWireGuardControl ;;
        6) return ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}


showSubscriptionWireGuardControlledAccessCredential() {
    local state
    state=$(subscriptionWireGuardReadState) || { errorCard "WireGuard 状态读取失败"; return 1; }
    warnCard "即将显示接入秘密" "接入回执和旧版被控凭据都包含长期控制 Token，请只通过可信通道传递"
    if [[ -n "$(jq -r '.join_invite_id // empty' <<<"${state}")" ]]; then
        showSubscriptionWireGuardJoinReceipt
    else
        showSubscriptionWireGuardControlledCredential
    fi
}

# 订阅与用户入口
manageSubscription() {
    local role
    if [[ -z "${configPath}" ]]; then
        errorCard "未安装"
        exit 0
    fi

    while true; do
        role=$(subscriptionCurrentRoleNormalized) || {
            errorCard "WireGuard 控制面状态损坏或不可读" "请先修复 $(subscriptionWireGuardStateFile)，本机模式不会绕过损坏状态"
            return 1
        }
        case "${role}" in
        uninitialized)
            manageSubscriptionLocalHome
            return
            ;;
        main)
            manageSubscriptionMainHome
            return
            ;;
        controlled)
            manageSubscriptionControlledHome
            return
            ;;
        esac
    done
}

showSubscriptionServiceStatus() {
    if ! readNginxSubscribe; then
        statusCard "订阅服务" "状态：配置损坏" "请修复受管 subscribe.conf；不会按未安装状态覆盖"
        return 1
    fi
    if [[ -n "${subscribePort}" ]]; then
        statusCard "订阅服务" "状态：已配置" "协议：${subscribeType:-https}" "域名：${subscribeDomain}" "端口：${subscribePort}"
    else
        statusCard "订阅服务" "状态：未检测到可用订阅发布配置" "如需本机向客户端发布订阅，请进入 订阅与用户首页 -> 安装/更新订阅服务" "仅作为被控加入主控时，不需要安装公网订阅服务"
    fi
}

userResultCard() {
    local title=$1
    echoContent title "\n┌─ ${title} ─────────────────────────────────────────"
}

showSubscriptionJsonWithSummary() {
    local title=$1
    local json=$2
    local summary=$3
    userResultCard "${title}"
    while IFS= read -r line; do
        [[ -n "${line}" ]] && menuLine "${line}"
    done <<<"${summary}"
    printf '%s\n' "${json}" | jq .
    menuClose
}

showSubscriptionLocalSyncPlan() {
    local plan
    local summary
    readInstallType
    readInstallProtocolType
    plan=$(subscriptionSyncPlan) || {
        errorCard "本机同步计划生成失败"
        return 1
    }
    summary=$(jq -r '"创建账号：" + ((.create // []) | length | tostring) + "\n移除账号：" + ((.remove // []) | length | tostring)' <<<"${plan}") || return 1
    showSubscriptionJsonWithSummary "本机同步计划" "${plan}" "${summary}"
}

showSubscriptionRemoteHealthPlan() {
    local health
    local summary
    health=$(subscriptionRemoteControlHealthAll) || {
        errorCard "被控服务器健康检查失败"
        return 1
    }
    summary=$(jq -r '
      "服务器数：" + (length | tostring) + "\n" +
      "健康：" + ([.[]? | select(.ok == true)] | length | tostring) + "\n" +
      "异常：" + ([.[]? | select(.ok != true)] | length | tostring)
    ' <<<"${health}") || return 1
    showSubscriptionJsonWithSummary "被控服务器健康检查" "${health}" "${summary}"
}

showSubscriptionRemoteSyncPlan() {
    local plan
    local summary
    plan=$(subscriptionRemoteSyncPlan) || {
        errorCard "远程同步计划生成失败"
        return 1
    }
    summary=$(jq -r '
      "服务器数：" + (length | tostring) + "\n" +
      "可同步：" + ([.[]? | select(.status == "success")] | length | tostring) + "\n" +
      "异常：" + ([.[]? | select(.status != "success")] | length | tostring) + "\n" +
      "预计创建：" + ([.[]?.response.plan.create[]?] | length | tostring) + "\n" +
      "预计移除：" + ([.[]?.response.plan.remove[]?] | length | tostring)
    ' <<<"${plan}") || return 1
    showSubscriptionJsonWithSummary "远程同步计划" "${plan}" "${summary}"
}

showSubscriptionQuotaPlanJson() {
    local plan=$1
    local summary
    subscriptionQuotaValidatePlan "${plan}" || {
        errorCard "超限处理计划格式无效"
        return 1
    }
    summary=$(jq -r '
      "待处理订阅：" + (length | tostring) + "\n" +
      "动作：停用超额订阅并移除本机托管账号"
    ' <<<"${plan}") || return 1
    showSubscriptionJsonWithSummary "超限处理计划" "${plan}" "${summary}"
}

showUserSubscriptions() {
    local output
    local id
    local name
    local enabled
    local sources
    local limit
    local quota
    local jqProgram
    local quotaStatusJq
    quotaStatusJq=$(subscriptionUserQuotaStatusJq) || return 1
    jqProgram=$(printf '%s\n%s\n%s\n' "$(subscriptionTrafficTotalsJq)" "${quotaStatusJq}" '
      . as $group |
      .user_groups[]? |
      "\(.id)\u001f\(.name)\u001f\(.enabled)\u001f\(.allowed_sources | join(","))\u001f\(.traffic_limit_gb)\u001f\(subscriptionUserQuotaStatus(.; subscriptionTrafficTotal(($group.traffic.user_groups[.id] // {}).sources); true))"')
    output=$(subscriptionActiveGroupRead -r "${jqProgram}") || {
        errorCard "用户订阅读取失败"
        return 1
    }
    if [[ -z "${output}" ]]; then
        statusCard "用户订阅" "暂无用户订阅"
        return
    fi
    userResultCard "用户订阅列表"
    while IFS=$'\037' read -r id name enabled sources limit quota; do
        menuLine "ID：$(uiStyle value "${id}")"
        menuLine "名称：$(uiStyle value "${name}")"
        if [[ "${enabled}" == "true" ]]; then
            menuLine "状态：$(uiStyle ok "${enabled}")"
        else
            menuLine "状态：$(uiStyle warn "${enabled}")"
        fi
        menuLine "可用服务器：$(uiStyle value "${sources}")"
        menuLine "订阅额度GB：$(uiStyle value "${limit}")"
        case "${quota}" in
        已超限*) menuLine "限额状态：$(uiStyle danger "${quota}")" ;;
        接近上限*) menuLine "限额状态：$(uiStyle warn "${quota}")" ;;
        正常*) menuLine "限额状态：$(uiStyle ok "${quota}")" ;;
        *) menuLine "限额状态：$(uiStyle muted "${quota}")" ;;
        esac
    done <<<"${output}"
    menuClose
}

parseUserSubscriptionSources() {
    local sourceIds=$1
    printf '%s' "${sourceIds}" | jq -R -e -c 'split(",") | map(gsub("^ +| +$"; "")) | map(select(length > 0)) | unique | if index("*") then ["*"] else . end | select(length > 0)'
}

validateUserSubscriptionSourcesJson() {
    local sourceJson=$1
    local knownSources
    knownSources=$(subscriptionActiveGroupRead -r '.sources[]?.id' | jq -R -s -c 'split("\n") | map(select(length > 0))') || return 1
    jq -n -e --argjson sources "${sourceJson}" --argjson knownSources "${knownSources}" \
        'all($sources[]; . as $source | $source == "*" or ($knownSources | index($source)))' >/dev/null
}

createAndSyncUserSubscriptionWizard() {
    local id=
    local sourceIds=main
    local sourceJson=
    local limit=0
    local enableSync=
    local canShowLinks=true
    local syncWillRun=false
    local subscriptionServiceStatus=0
    local sourceOutput
    autoRead user_subscription_id "请输入分享订阅ID[只用于管理，例 team-a]:" id
    if ! subscriptionStateIdValid "${id}"; then
        errorCard "输入有误，ID 最多 64 个字符，且只能包含英文、数字、下划线或短横线"
        return 1
    fi

    if ensureSubscriptionServiceForSharedLinks; then
        :
    else
        subscriptionServiceStatus=$?
        if [[ "${subscriptionServiceStatus}" == "2" ]]; then
            return 1
        fi
        canShowLinks=false
    fi

    userResultCard "这个订阅可使用的服务器"
    menuLine "这里设置这个订阅的服务器范围。"
    menuLine "建议先确保远端服务器已接入，再输入 main、远端服务器 ID 或 *；多个服务器用英文逗号分隔，例如 main,remote-a。"
    sourceOutput=$(subscriptionActiveGroupRead -r '.sources[] | "\(.id):\(.name):\(.role):\(.scheme):\(.host):\(.port):\(.enabled):\(.sync_status)"') || return 1
    printf '%s\n' "${sourceOutput}"
    menuClose
    autoRead user_subscription_sources "请输入服务器范围[回车默认 main]:" sourceIds
    sourceIds=${sourceIds:-main}
    if ! sourceJson=$(parseUserSubscriptionSources "${sourceIds}"); then
        errorCard "服务器范围不能为空；直接回车使用本机 main"
        return 1
    fi
    if ! validateUserSubscriptionSourcesJson "${sourceJson}"; then
        errorCard "服务器范围包含不存在的服务器源"
        return 1
    fi

    autoRead user_subscription_traffic_limit "请输入订阅额度GB[回车/0为不限；这里只设置额度，超限处理在 订阅同步 -> 用量与限额 中执行]:" limit
    limit=${limit:-0}
    if ! echo "${limit}" | grep -qE '^[0-9]+$'; then
        errorCard "订阅额度必须是数字"
        return 1
    fi

    if ! addUserSubscriptionState "${id}" "${id}" "${sourceJson}" "${limit}"; then
        errorCard "分享订阅创建失败，订阅 ID 可能已存在或状态写入失败"
        return 1
    fi
    statusCard "分享订阅已创建" "订阅ID：${id}" "实际托管账号：$(subscriptionSyncAccountName "${id}")" "服务器范围：${sourceIds}" "订阅额度GB：${limit}" "超限停用和批量处理请到 订阅同步 -> 用量与限额 执行"

    if ! subscriptionGroupSyncEnabled; then
        autoRead user_subscription_enable_auto_sync "是否开启后续自动同步？[yes/no，默认 yes]：" enableSync
        enableSync=${enableSync:-yes}
        if [[ "${enableSync}" == "yes" || "${enableSync}" == "y" ]]; then
            if setSubscriptionGroupSyncEnabledWithCron true; then
                successCard "自动同步已开启" "后续会按当前间隔同步；可在 订阅同步 中调整间隔"
            else
                errorCard "自动同步开启失败"
                return 1
            fi
        else
            statusCard "自动同步未开启" "本次变更已保存，需稍后手动执行完整同步"
        fi
    fi

    if subscriptionGroupSyncEnabled; then
        syncWillRun=true
    fi
    runSubscriptionSyncAfterMutation "用户订阅创建" || return 1
    if [[ "${syncWillRun}" == "true" ]]; then
        if [[ "${canShowLinks}" == "true" ]]; then
            showUserSubscriptionLinks "${id}"
        else
            statusCard "同步完成，但暂时还不能查看链接" "订阅对象和托管账号已生成" "等安装好订阅服务后，到 订阅与用户首页 -> 查看并处理已有订阅中再刷新并查看链接"
        fi
    fi
}

selectUserSubscriptionId() {
    local id=
    selectedUserSubscriptionId=
    local hasUsers
    hasUsers=$(subscriptionActiveGroupRead -r 'any(.user_groups[]?; true)') || {
        errorCard "用户订阅读取失败"
        return 1
    }
    if [[ "${hasUsers}" != "true" ]]; then
        statusCard "用户订阅" "暂无用户订阅" "先到 订阅与用户首页 -> 新建并发布订阅创建一个"
        return 1
    fi
    showUserSubscriptions || return 1
    autoRead select_user_subscription_id "请输入用户订阅ID:" id
    if [[ -z "${id}" ]] || ! userSubscriptionExists "${id}"; then
        errorCard "用户订阅 ID 无效，请按上面的列表重新输入"
        return 1
    fi
    selectedUserSubscriptionId=${id}
}

showUserSubscriptionLinks() {
    local userSubscriptionId=$1
    local accountName
    accountName=$(subscriptionSyncAccountName "${userSubscriptionId}")
    if ! ensureSubscriptionServiceForSharedLinks; then
        return 1
    fi
    if ! subscribe false "" "${accountName}" true; then
        errorCard "订阅输出刷新失败，请检查订阅配置"
        return 1
    fi
    statusCard "用户订阅链接" "已刷新 ${accountName} 的订阅输出，请把上方该账号的链接发给对方" "如果上方没有该账号，先执行同步生成托管账号"
}

removeUserSubscriptionRollback() {
    local previousGroupsState=$1
    local configBackupDir=$2
    local reason=$3
    local stateRestored=true
    local configRestored=true
    local rollbackMessage

    if ! subscriptionGroupsStateWrite --argjson previousGroupsState "${previousGroupsState}" '$previousGroupsState' >/dev/null 2>&1; then
        stateRestored=false
    fi
    if ! subscriptionSyncRestoreConfigBackups "${configBackupDir}" >/dev/null 2>&1; then
        configRestored=false
    fi

    if [[ "${configRestored}" == "true" ]]; then
        padmRemoveCleanupPath "${configBackupDir}"
    else
        padmForgetCleanupPath "${configBackupDir}"
    fi

    if ! subscriptionSyncSetRestorePairFailureMessage \
        rollbackMessage \
        "${reason}" \
        "${stateRestored}" "订阅状态" "$(subscriptionGroupsFile)" \
        "${configRestored}" "托管账号配置" "备份目录: ${configBackupDir}" \
        "$(subscriptionGroupsFile) 和备份目录: ${configBackupDir}"; then
        errorCard "${rollbackMessage}"
        return 1
    fi
}

removeUserSubscriptionTransactionUnlocked() {
    local userSubscriptionId=$1
    local previousGroupsState
    local configBackupDir
    local accountName
    local manualCheckMessage
    previousGroupsState=$(subscriptionGroupsStateRead -c '.') || {
        subscriptionSyncSetManualCheckMessage manualCheckMessage "读取当前订阅状态失败" " $(subscriptionGroupsFile)"
        errorCard "${manualCheckMessage}"
        return 1
    }
    subscriptionSyncCreateConfigBackups configBackupDir || {
        subscriptionSyncSetManualCheckMessage manualCheckMessage "删除订阅前托管账号配置备份失败" "本机配置"
        errorCard "${manualCheckMessage}"
        return 1
    }
    accountName=$(subscriptionSyncAccountName "${userSubscriptionId}")
    if ! removeUserSubscriptionState "${userSubscriptionId}"; then
        padmRemoveCleanupPath "${configBackupDir}"
        errorCard "用户订阅状态删除失败"
        return 1
    fi
    if ! subscriptionSyncRemoveAccount "${accountName}"; then
        if ! removeUserSubscriptionRollback "${previousGroupsState}" "${configBackupDir}" "托管账号配置移除失败"; then
            return 1
        fi
        local rollbackMessage
        subscriptionSyncSetRollbackResultMessage rollbackMessage "托管账号配置移除失败" "已恢复旧配置"
        errorCard "${rollbackMessage}"
        return 1
    fi
    if ! reloadCore; then
        if ! removeUserSubscriptionRollback "${previousGroupsState}" "${configBackupDir}" "核心重载失败"; then
            return 1
        fi
        local rollbackMessage
        subscriptionSyncSetRollbackRetryMessage rollbackMessage "核心重载失败" reloadCore "恢复旧配置后核心重载仍失败，请检查核心服务日志"
        errorCard "${rollbackMessage}"
        return 1
    fi
    padmRemoveCleanupPath "${configBackupDir}"
}

removeUserSubscriptionMenu() {
    local userSubscriptionId=$1
    local confirm=
    autoRead remove_user_subscription_confirm "删除订阅 ${userSubscriptionId} 会移除状态；同步后会删除对应托管账号。确认请输入 yes：" confirm
    if [[ "${confirm}" != "yes" ]]; then
        coreCancelledStatusCard "操作未执行"
        return 1
    fi
    subscriptionGroupsWithLock removeUserSubscriptionTransactionUnlocked "${userSubscriptionId}" || return 1
    successCard "用户订阅已删除"
    runSubscriptionSyncAfterMutation "用户订阅删除" || true
    return 0
}

manageUserSubscriptionItem() {
    local userSubscriptionId
    selectUserSubscriptionId || return
    userSubscriptionId=${selectedUserSubscriptionId}
    while true; do
        echoContent title "\n┌─ 处理已有订阅 ─────────────────────────────────────"
        menuLine "当前订阅：${userSubscriptionId}"
        menuLine "这里处理一个已有订阅的日常维护。"
        menuLine "批量同步与超限处理在订阅同步中处理。"
        menuItem 1 "刷新并查看当前链接" "重新生成订阅输出并显示该订阅当前链接"
        menuItem 2 "查看当前用量" "只读查看累计用量和额度状态"
        menuItem 3 "设置节点范围" "选择 main、被控服务器 ID 或 *"
        menuItem 4 "设置订阅额度" "0 表示不限；这里只设置额度，不执行超限处理"
        menuItem 5 "启用/停用当前订阅" "停用后同步会移除对应托管账号"
        menuDangerItem 6 "删除订阅" "删除记录；同步后移除对应托管账号"
        menuReturnItem 7 "返回上级" "回到订阅首页"
        menuClose
        autoRead user_subscription_item_menu "请选择:" userSubscriptionItemStatus
        case "${userSubscriptionItemStatus}" in
        1) showUserSubscriptionLinks "${userSubscriptionId}" ;;
        2) showUserSubscriptionTraffic "${userSubscriptionId}" ;;
        3) setUserSubscriptionSourcesMenu "${userSubscriptionId}" ;;
        4) setUserSubscriptionTrafficLimitMenu "${userSubscriptionId}" ;;
        5)
            if toggleUserSubscriptionState "${userSubscriptionId}"; then
                successCard "用户订阅状态已切换"
                runSubscriptionSyncAfterMutation "用户订阅状态切换" || return 1
            else
                errorCard "用户订阅状态切换失败"
            fi
            ;;
        6) removeUserSubscriptionMenu "${userSubscriptionId}" && return ;;
        7) return ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}

setUserSubscriptionSourcesMenu() {
    local userSubscriptionId=$1
    local sourceIds=
    local sourceJson=
    local line=
    local sourceOutput

    userResultCard "这个订阅可使用的服务器"
    menuLine "这里设置这个订阅的服务器范围。"
    menuLine "建议先确保远端服务器已添加凭据，再输入 main、远端服务器 ID 或 *；多个服务器用英文逗号分隔，例如 main,remote-a。"
    sourceOutput=$(subscriptionActiveGroupRead -r '.sources[] | "\(.id):\(.name):\(.role):\(.scheme):\(.host):\(.port):\(.enabled):\(.sync_status)"') || return 1
    while IFS= read -r line; do
        menuLine "${line}"
    done <<<"${sourceOutput}"
    menuClose
    autoRead user_subscription_sources "请输入服务器范围，多个用逗号分隔:" sourceIds
    if ! sourceJson=$(parseUserSubscriptionSources "${sourceIds}"); then
        errorCard "服务器范围不能为空；直接回车使用本机 main"
        return 1
    fi
    if ! validateUserSubscriptionSourcesJson "${sourceJson}"; then
        errorCard "服务器范围包含不存在的服务器源"
        return 1
    fi
    if ! setUserSubscriptionSources "${userSubscriptionId}" "${sourceJson}"; then
        errorCard "节点范围更新失败"
        return 1
    fi
    successCard "节点范围已更新"
    runSubscriptionSyncAfterMutation "用户订阅节点范围更新"
}

setUserSubscriptionTrafficLimitMenu() {
    local userSubscriptionId=$1
    local limit=
    autoRead user_subscription_traffic_limit "请输入订阅额度GB[0为不限；这里只设置额度，不执行超限处理]:" limit
    if [[ -z "${limit}" ]] || ! echo "${limit}" | grep -qE '^[0-9]+$'; then
        errorCard "订阅额度必须是数字"
        return 1
    fi
    if ! setUserSubscriptionTrafficLimit "${userSubscriptionId}" "${limit}"; then
        errorCard "订阅额度更新失败"
        return 1
    fi
    successCard "订阅额度已更新" "超限停用和批量处理请到 订阅同步 -> 用量与限额 执行"
}
# 添加服务器源
createSubscriptionWireGuardInviteMenu() {
    local alias= inviteCredential=
    echoContent title "\n┌─ 创建被控邀请 ─────────────────────────────────────"
    menuLine "主控将自动预留别名和 WireGuard 地址；邀请只在本次结果中显示。"
    menuClose
    autoRead subscription_invite_alias "请输入被控服务器别名[英文/数字/短横线，例 hk-1]:" alias
    subscriptionWireGuardCreateInvite "${alias}" inviteCredential || return 1
    statusCard "被控邀请已创建" "被控别名：${alias}" "被控邀请：${inviteCredential}" "邀请有效期 24 小时，请通过可信通道传递；丢失时取消并重建" "WireGuard 使用 UDP，控制 API 只在隧道内使用 HTTP；此步骤不需要 TLS 证书"
}

subscriptionWireGuardInviteLocalTime() {
    date -d "@$1" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || printf '%s' "$1"
}

subscriptionWireGuardInviteRemainingText() {
    local seconds=$1
    if ((seconds <= 0)); then
        printf '已过期'
    elif ((seconds >= 86400)); then
        printf '%d天%d小时' "$((seconds / 86400))" "$(((seconds % 86400) / 3600))"
    elif ((seconds >= 3600)); then
        printf '%d小时%d分钟' "$((seconds / 3600))" "$(((seconds % 3600) / 60))"
    else
        printf '%d分钟' "$(((seconds + 59) / 60))"
    fi
}

manageSubscriptionPendingInvites() {
    local pendingJson invite alias= confirmCancel= statusText remainingSeconds
    pendingJson=$(subscriptionWireGuardListPendingInvites) || return 1
    echoContent title "\n┌─ 待完成邀请 ───────────────────────────────────────"
    if [[ "$(jq -r 'length' <<<"${pendingJson}")" == "0" ]]; then
        menuLine "当前没有待完成邀请。"
        menuClose
        return 0
    fi
    while IFS= read -r invite; do
        statusText="待接入"
        [[ "$(jq -r '.status' <<<"${invite}")" == "incomplete" ]] && statusText="接入未完成"
        remainingSeconds=$(jq -r '.remaining_seconds' <<<"${invite}") || return 1
        ((remainingSeconds <= 0)) && statusText="接入未完成且已过期"
        menuLine "别名：$(jq -r '.alias' <<<"${invite}")；地址：$(jq -r '.address' <<<"${invite}")；过期：$(subscriptionWireGuardInviteLocalTime "$(jq -r '.expires_at' <<<"${invite}")")；剩余：$(subscriptionWireGuardInviteRemainingText "${remainingSeconds}")；状态：${statusText}"
    done < <(jq -c '.[]' <<<"${pendingJson}")
    menuClose
    autoRead subscription_cancel_invite_alias "输入要取消的唯一别名[直接回车返回]:" alias
    [[ -n "${alias}" ]] || return 0
    jq -e --arg alias "${alias}" 'any(.[]; .alias == $alias)' <<<"${pendingJson}" >/dev/null 2>&1 || { errorCard "待完成邀请别名无效"; return 1; }
    warnCard "取消邀请" "若接入曾中断，将同时清理该别名的部分 Peer、来源和凭据"
    autoConfirm subscription_cancel_invite_confirm "确认取消 ${alias}？" n confirmCancel
    [[ "${confirmCancel}" == "y" ]] || { statusCard "已保留待完成邀请"; return 0; }
    subscriptionWireGuardCancelInvite "${alias}" || return 1
    successCard "待完成邀请已取消" "已释放别名和预留地址：${alias}"
}

removeSubscriptionControlledServerMenu() {
    local sourceId=
    local sourceOutput
    echoContent title "\n┌─ 移除被控服务器 ───────────────────────────────────"
    menuLine "这里列出当前可移除的被控服务器。"
    sourceOutput=$(subscriptionActiveGroupRead -r '
      [.sources[]? | select(.role != "main")] |
      to_entries[] |
      "│ \(.key + 1). \(.value.id):\(.value.name):\(.value.role):\(.value.scheme):\(.value.host):\(.value.port):\(.value.enabled):\(.value.sync_status)"') || return 1
    printf '%s\n' "${sourceOutput}"
    menuClose
    autoRead delete_subscription_source "请输入要删除的被控服务器源ID:" sourceId
    if [[ -z "${sourceId}" ]] || ! subscriptionSourceExists "${sourceId}" || subscriptionSourceIsMain "${sourceId}"; then
        errorCard "被控服务器源 ID 无效"
        return 1
    fi
    subscriptionWireGuardRemovePeerAndSource "${sourceId}" || { errorCard "被控服务器删除失败"; return 1; }
    successCard "被控服务器删除成功" "服务器源和 WireGuard Peer 已移除"
    runSubscriptionSyncAfterMutation "被控服务器删除"
}

changeSubscriptionSourceEnabledMenu() {
    subscriptionRequireMainRole || return 1
    local sourceId=
    local source=
    local enabled=
    local targetEnabled=
    local actionText=
    local confirm=
    local sourceOutput

    userResultCard "被控服务器启用状态"
    sourceOutput=$(subscriptionActiveGroupRead -r '
      .sources[]? | select(.role != "main") |
      "ID:\(.id)  名称:\(.name)  当前状态:" + (if .enabled == true then "启用" else "停用" end)') || return 1
    printf '%s\n' "${sourceOutput}"
    menuClose
    autoRead subscription_source_enabled_id "请输入要启用或停用的被控服务器 ID:" sourceId
    if [[ -z "${sourceId}" ]] || ! subscriptionSourceExists "${sourceId}" || subscriptionSourceIsMain "${sourceId}"; then
        errorCard "被控服务器源 ID 无效"
        return 1
    fi
    source=$(subscriptionActiveGroupRead -c --arg id "${sourceId}" 'first(.sources[]? | select(.id == $id and .role != "main"))') || return 1
    enabled=$(jq -r '.enabled == true' <<<"${source}") || return 1
    if [[ "${enabled}" == "true" ]]; then
        targetEnabled=false
        actionText="停用"
    else
        targetEnabled=true
        actionText="启用"
    fi
    warnCard "${actionText}被控服务器" "目标：${sourceId}（$(jq -r '.name' <<<"${source}")）" "停用只影响后续同步和公网发布，不删除 Peer、Token 或历史状态"
    autoConfirm subscription_source_enabled_confirm "确认${actionText} ${sourceId}？" n confirm
    [[ "${confirm}" == "y" ]] || { coreCancelledStatusCard "服务器源状态未修改"; return 0; }
    if ! setSubscriptionSourceEnabled "${sourceId}" "${targetEnabled}"; then
        errorCard "被控服务器状态更新失败"
        return 1
    fi
    successCard "被控服务器已${actionText}" "来源：${sourceId}"
    runSubscriptionSyncAfterMutation "被控服务器${actionText}" || true
}

manageSubscriptionServers() {
    subscriptionRequireMainRole || return 1
    local serverStatus=
    while true; do
        echoContent title "\n┌─ 服务器与协同 ─────────────────────────────────────"
        menuLine "推荐按 创建邀请 -> 被控导入 -> 完成接入 的顺序操作。"
        menuItem 1 "查看来源与同步状态" "查看本机和被控来源的地址、启用状态及最近同步结果"
        menuItem 2 "创建被控邀请" "输入一次别名，自动预留 WireGuard 地址"
        menuItem 3 "完成被控接入" "粘贴接入回执，自动使用预留别名和地址"
        menuItem 4 "查看/取消待完成邀请" "按别名查看状态或释放预留地址"
        menuItem 5 "更新被控服务器凭据" "更新内网地址、公钥、控制端口和 Token"
        menuItem 6 "启用/停用被控服务器" "保留凭据，只调整该来源是否参加同步和发布"
        menuItem 7 "检查被控服务器健康" "请求所有启用的被控服务器健康检查"
        menuDangerItem 8 "移除被控服务器" "删除已有被控来源和 WireGuard Peer"
        menuReturnItem 9 "返回主控首页" "回到上级菜单"
        menuClose
        autoRead server_source_menu "请选择:" serverStatus
        case "${serverStatus}" in
        1) showSubscriptionSources ;;
        2) createSubscriptionWireGuardInviteMenu ;;
        3) addOtherSubscribe ;;
        4) manageSubscriptionPendingInvites ;;
        5) setSubscriptionSourceControlTokenMenu ;;
        6) changeSubscriptionSourceEnabledMenu ;;
        7) showSubscriptionRemoteHealthPlan ;;
        8) removeSubscriptionControlledServerMenu ;;
        9) return ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}

# 添加被控服务器
addOtherSubscribe() {
    local credential=
    local credentialJson=
    local completedAlias= source= health=
    echoContent title "\n┌─ 完成被控接入 ─────────────────────────────────────"
    menuLine "粘贴接入回执，自动使用创建邀请时预留的别名和地址。"
    menuClose
    subscriptionWireGuardReadSecret credential "请粘贴接入回执:" || return 1
    if [[ -z "${credential}" ]]; then
        errorCard "接入回执不可为空"
        return 1
    fi
    credentialJson=$(subscriptionWireGuardCredentialDecode "${credential}") || {
        errorCard "接入回执无效，请复制被控端完整输出"
        return 1
    }
    if [[ "$(jq -r '.kind' <<<"${credentialJson}")" != "receipt" ]]; then
        errorCard "请粘贴接入回执"
        return 1
    fi
    subscriptionWireGuardCompleteInvite "${credentialJson}" completedAlias || return 1
    source=$(subscriptionActiveGroupRead -c --arg id "${completedAlias}" 'first(.sources[]? | select(.id == $id)) // empty') || true
    if [[ -n "${source}" ]]; then
        health=$(subscriptionRemoteControlHealth "${source}" 2>/dev/null || true)
    fi
    if [[ -n "${health}" ]] && jq -e '.ok == true' <<<"${health}" >/dev/null 2>&1; then
        successCard "被控接入已完成" "别名：${completedAlias}" "WireGuard 与控制服务健康检查通过"
    else
        warnCard "接入已保存，但暂不可达" "别名：${completedAlias}" "Peer、服务器源和 Token 已保留；可稍后从 服务器与协同 重试健康检查"
    fi
    runSubscriptionSyncAfterMutation "被控服务器接入" || true
}






subscriptionSourceSyncSummaryJq() {
    cat <<'EOF'
(if has("last_sync_changed") then "\n上次同步变更:" + (if .last_sync_changed then "是" else "否" end) else "" end) +
(if .last_sync_plan? then "\n上次同步计划: 创建\((.last_sync_plan.create // []) | length)，删除\((.last_sync_plan.remove // []) | length)" else "" end) +
(if .last_sync_error? then "\n上次同步错误:\(.last_sync_error.type) \(.last_sync_error.message)" else "" end)
EOF
}

showSubscriptionSources() {
    local syncSummary
    local role
    local output
    local sourceFilter='.'
    role=$(subscriptionCurrentRoleNormalized) || return 1
    [[ "${role}" == "uninitialized" ]] && sourceFilter='select(.role == "main")'
    syncSummary=$(subscriptionSourceSyncSummaryJq) || return 1
    output=$(subscriptionActiveGroupRead -r "
      .sources[]? |
      ${sourceFilter} |
      \"ID:\\(.id)\\n名称:\\(.name)\\n角色:\\(.role)\\n地址:\\(.scheme)://\\(.host):\\(.port)\\n启用:\\(.enabled)\\n同步状态:\\(.sync_status)\" +
      ${syncSummary} +
      \"\\n---\"") || return 1
    printf '%s\n' "${output}"
}

showSubscriptionSourceControlUrls() {
    local output
    output=$(subscriptionActiveGroupRead -r '
      .sources[]? | select(.role != "main") |
      "ID:\(.id)\n名称:\(.name)\n控制面:WireGuard\n内网地址:\(.host):\(.port)\nHealth:http://\(.host):\(.port)/s/control/health\nSync:http://\(.host):\(.port)/s/control/sync\n---"'
    ) || return 1
    printf '%s\n' "${output}"
}

setSubscriptionSourceControlTokenMenu() {
    subscriptionRequireMainRole || return 1
    local credential=
    local credentialJson=
    local host=
    local port=
    local sourceId=
    local matches=
    echoContent title "\n┌─ 更新被控服务器凭据 ───────────────────────────────"
    menuLine "这里更新一个被控服务器的接入凭据。"
    menuLine "仅用于更新已有被控连接；首次接入请使用邀请和回执。系统会更新地址、端口和 Token。"
    menuClose
    subscriptionWireGuardReadSecret credential "请粘贴被控接入凭据:" || return 1
    if [[ -z "${credential}" ]]; then
        errorCard "被控接入凭据不可为空"
        return 1
    fi
    credentialJson=$(subscriptionWireGuardCredentialDecode "${credential}") || {
        errorCard "被控接入凭据无效，请复制被控端完整输出"
        return 1
    }
    if [[ "$(jq -r '.kind' <<<"${credentialJson}")" != "controlled" ]]; then
        errorCard "请粘贴被控接入凭据"
        return 1
    fi
    subscriptionWireGuardValidateControlledCredentialJson "${credentialJson}" || {
        errorCard "被控接入凭据字段不完整或格式无效"
        return 1
    }
    host=$(subscriptionWireGuardAddressHost "$(jq -r '.address' <<<"${credentialJson}")")
    port=$(jq -r '.control_port' <<<"${credentialJson}")
    matches=$(subscriptionActiveGroupRead -r --arg host "${host}" --argjson port "${port}" '
      .sources[]?
      | select(.role != "main" and .host == $host and .port == $port)
      | .id') || return 1
    if [[ -n "${matches}" ]] && [[ "$(printf '%s\n' "${matches}" | wc -l | tr -d ' ')" == "1" ]]; then
        sourceId=${matches}
    else
        subscriptionActiveGroupRead -r '
          .sources[]?
          | select(.role != "main")
          | "\(.id):\(.name):\(.scheme):\(.host):\(.port):\(.sync_status)"' || return 1
        autoRead subscription_source_id "请输入要更新的被控服务器别名:" sourceId
    fi
    if [[ -z "${sourceId}" ]] || ! subscriptionSourceExists "${sourceId}" || subscriptionSourceIsMain "${sourceId}"; then
        errorCard "被控服务器别名无效"
        return 1
    fi
    subscriptionWireGuardUpdatePeerAndCredential "${sourceId}" "${credentialJson}" || {
        errorCard "被控服务器凭据更新失败"
        return 1
    }
    successCard "被控服务器凭据已更新" "内网地址：${host}:${port}" "别名：${sourceId}" "Peer 公钥和 Token 已保存，可继续测试被控连接"
    runSubscriptionSyncAfterMutation "被控服务器凭据更新"
}

refreshSubscriptionGroupSyncCron() {
    ensureSubscriptionGroupsState || return 1
    if subscriptionGroupSyncEnabled; then
        installSubscriptionGroupSyncCron
    else
        local cronFile
        local currentCron
        cronFile=$(subscriptionGroupSyncCronFile)
        mkdir -p "$(dirname "${cronFile}")" || return 1
        currentCron=$(readUserCrontabContent) || return 1
        currentCron=$(sed '\|/etc/padm/install.sh SyncSubscriptionGroups|d' <<<"${currentCron}") || return 1
        installUserCrontabContent "${currentCron}"
    fi
}

setSubscriptionGroupSyncValueWithCron() {
    local value=$1 query=$2 setterFn=$3 valueRestoreError=$4 cronRestoreError=$5
    local previousValue
    previousValue=$(subscriptionActiveGroupRead -r "${query}") || return 1
    "${setterFn}" "${value}" || return 1
    if refreshSubscriptionGroupSyncCron; then
        return 0
    fi
    "${setterFn}" "${previousValue}" || {
        errorCard "${valueRestoreError}"
        return 1
    }
    refreshSubscriptionGroupSyncCron || {
        errorCard "${cronRestoreError}"
        return 1
    }
    return 1
}

setSubscriptionGroupSyncEnabledWithCron() {
    setSubscriptionGroupSyncValueWithCron "$1" '.sync.enabled == true' setSubscriptionGroupSyncEnabled \
        "自动同步定时任务更新失败，且原状态恢复失败" "自动同步状态已恢复，但原定时任务恢复失败"
}

setSubscriptionGroupSyncIntervalWithCron() {
    setSubscriptionGroupSyncValueWithCron "$1" '.sync.interval_minutes' setSubscriptionGroupSyncInterval \
        "自动同步定时任务更新失败，且原间隔恢复失败" "自动同步间隔已恢复，但原定时任务恢复失败"
}

manageSubscriptionSyncDiagnostics() {
    local role
    local diagnosticStatus=
    role=$(subscriptionCurrentRoleNormalized) || return 1
    [[ "${role}" == "main" || "${role}" == "uninitialized" ]] || return 1
    while true; do
        echoContent title "\n┌─ 同步状态与排障 ───────────────────────────────────"
        menuItem 1 "查看最近同步结果与失败列表" "显示组状态和各来源最近同步结果"
        menuItem 2 "检查本机服务与发布状态" "显示服务器角色和公网订阅服务状态"
        if [[ "${role}" == "main" ]]; then
            menuItem 3 "查看本机同步计划" "预览本机 create/remove"
            menuItem 4 "查看远端同步计划" "对启用来源执行 dry-run"
            menuItem 5 "查看自动同步定时任务" "显示当前 SyncSubscriptionGroups cron"
            menuReturnItem 6 "返回订阅同步" "回到上级菜单"
        else
            menuItem 3 "查看本机同步计划" "预览本机 create/remove"
            menuItem 4 "查看自动同步定时任务" "显示当前 SyncSubscriptionGroups cron"
            menuReturnItem 5 "返回订阅同步" "回到上级菜单"
        fi
        menuClose
        autoRead subscription_sync_diagnostics_menu "请选择:" diagnosticStatus
        if [[ "${role}" == "main" ]]; then
            case "${diagnosticStatus}" in
            1) showSubscriptionGroupsStateSummary; showSubscriptionSources ;;
            2) showSubscriptionServerRoleSummary; showSubscriptionServiceStatus ;;
            3) showSubscriptionLocalSyncPlan ;;
            4) showSubscriptionRemoteSyncPlan ;;
            5) crontab -l 2>/dev/null | grep 'SyncSubscriptionGroups' || true ;;
            6) return ;;
            *) coreSelectionErrorCard ;;
            esac
        else
            case "${diagnosticStatus}" in
            1) showSubscriptionGroupsStateSummary; showSubscriptionSources ;;
            2) showSubscriptionServerRoleSummary; showSubscriptionServiceStatus ;;
            3) showSubscriptionLocalSyncPlan ;;
            4) crontab -l 2>/dev/null | grep 'SyncSubscriptionGroups' || true ;;
            5) return ;;
            *) coreSelectionErrorCard ;;
            esac
        fi
    done
}

manageSubscriptionSyncSettings() {
    local role
    local syncStatus
    local enabledText
    local returnText
    local syncSettingsStatus=
    local targetSyncEnabled
    local interval=
    role=$(subscriptionCurrentRoleNormalized) || {
        subscriptionRequireLocalPublisherRole
        return 1
    }
    [[ "${role}" == "main" || "${role}" == "uninitialized" ]] || {
        subscriptionRequireLocalPublisherRole
        return 1
    }
    [[ "${role}" == "main" ]] && returnText="返回主控首页" || returnText="返回本机订阅首页"
    while true; do
        syncStatus=$(subscriptionActiveGroupRead -c '{enabled:(.sync.enabled == true), interval_minutes:(.sync.interval_minutes // 10), last_run:(.sync.last_run // ""), last_status:(.sync.last_status // "pending"), failure_count:((.sync.failures // []) | length)}') || return 1
        [[ "$(jq -r '.enabled' <<<"${syncStatus}")" == "true" ]] && enabledText="开启" || enabledText="关闭"
        echoContent title "\n┌─ 订阅同步 ─────────────────────────────────────────"
        menuLine "自动同步：${enabledText}"
        menuLine "同步间隔：$(jq -r '.interval_minutes' <<<"${syncStatus}") 分钟"
        menuLine "最近结果：$(jq -r '.last_status' <<<"${syncStatus}") / $(jq -r 'if .last_run == "" then "未运行" else .last_run end' <<<"${syncStatus}")"
        menuLine "失败数量：$(jq -r '.failure_count' <<<"${syncStatus}")"
        menuItem 1 "立即完整同步" "同步本机和所有启用来源，成功后发布完整订阅"
        menuItem 2 "开启/关闭自动同步" "同时控制菜单变更后的即时同步和 cron"
        menuItem 3 "设置同步间隔" "设置 1-59 分钟间隔，不隐式开启自动同步"
        menuItem 4 "状态与排障" "查看失败、健康、计划和定时任务"
        menuItem 5 "用量与限额" "查看用量并处理超限订阅"
        menuReturnItem 6 "${returnText}" "回到上级菜单"
        menuClose
        autoRead sync_settings_menu "请选择:" syncSettingsStatus
        case "${syncSettingsStatus}" in
        1) runSubscriptionGroupSync || true ;;
        2)
            targetSyncEnabled=true
            subscriptionGroupSyncEnabled && targetSyncEnabled=false
            if setSubscriptionGroupSyncEnabledWithCron "${targetSyncEnabled}"; then
                successCard "自动同步状态已更新" "当前状态：$(if [[ "${targetSyncEnabled}" == "true" ]]; then printf '开启'; else printf '关闭'; fi)"
            else
                errorCard "自动同步状态切换失败"
            fi
            ;;
        3)
            autoRead sync_interval_minutes "请输入同步间隔分钟:" interval
            if subscriptionGroupSyncIntervalValid "${interval}" && setSubscriptionGroupSyncIntervalWithCron "${interval}"; then
                successCard "自动同步间隔已更新"
            else
                errorCard "自动同步间隔更新失败，间隔需为 1-59 分钟"
            fi
            ;;
        4) manageSubscriptionSyncDiagnostics ;;
        5) manageTrafficAndQuota ;;
        6) return ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}
