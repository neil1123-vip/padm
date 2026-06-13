#!/usr/bin/env bash

showSubscriptionServerRoleSummary() {
    local state
    local role
    local roleText
    local enabledText
    local address
    local peerCount
    state=$(subscriptionWireGuardReadState)
    role=$(jq -r '.role' <<<"${state}")
    case "${role}" in
    main) roleText="主控" ;;
    controlled) roleText="被控" ;;
    *) roleText="未配置主控/被控" ;;
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

manageSubscriptionQuickStart() {
    while true; do
        echoContent title "\n┌─ 快速开始 ─────────────────────────────────────────"
        menuLine "这里提供最常用的订阅任务入口。"
        menuLine "建议先按自己用、给别人用、查看用量与限额或接入多服务器选择路径。"
        menuItem 1 "我自己用" "安装/更新订阅服务，再刷新并查看我的订阅链接"
        menuItem 2 "给别人用" "新建分享订阅、同步发布并查看可发送的链接"
        menuItem 3 "查看用量与限额" "刷新流量、查看总览并预览超限处理"
        menuItem 4 "接入多服务器" "按主控或被控角色完成 WireGuard 协同接入"
        menuReturnItem 5 "返回订阅与用户" "回到上级菜单"
        menuClose
        autoRead subscription_quick_start_menu "请选择:" quickStartStatus
        case "${quickStartStatus}" in
        1) installSubscribe && showSubscriptionServiceStatus && subscribe ;;
        2) showSubscriptionServiceStatus; createAndSyncUserSubscriptionWizard ;;
        3) collectSubscriptionTraffic && showSubscriptionTrafficOverview; showSubscriptionQuotaPlan ;;
        4) manageSubscriptionMultiServerQuickStart ;;
        5) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

manageSubscriptionMultiServerQuickStart() {
    while true; do
        echoContent title "\n┌─ 多服务器快速开始 ─────────────────────────────────"
        menuLine "这里按服务器角色引导多服务器接入。"
        menuLine "建议先确认这台机器是主控还是被控，再进入对应向导。"
        showSubscriptionServerRoleSummary
        menuItem 1 "这台作为主控" "初始化主控、复制主控凭据、添加被控并检查健康"
        menuItem 2 "这台作为被控" "初始化被控、导入主控凭据、输出被控凭据"
        menuReturnItem 3 "返回快速开始" "回到上级菜单"
        menuClose
        autoRead subscription_multi_quick_start "请选择:" multiQuickStartStatus
        case "${multiQuickStartStatus}" in
        1) runSubscriptionMainControllerWizard ;;
        2) runSubscriptionControlledWizard ;;
        3) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

runSubscriptionMainControllerWizard() {
    initSubscriptionWireGuardMain || return 1
    showSubscriptionWireGuardMainCredential
    addSubscribeMenu
    showSubscriptionRemoteHealthPlan
    showSubscriptionRemoteSyncPlan
}

runSubscriptionControlledWizard() {
    initSubscriptionWireGuardControlled || return 1
    importSubscriptionWireGuardMainCredential || return 1
    showSubscriptionWireGuardControlledCredential
    showSubscriptionWireGuardStatus
}

subscriptionServiceConfigured() {
    subscribePort=
    subscribeDomain=
    subscribeType=
    readNginxSubscribe
    [[ -n "${subscribePort:-}" ]]
}

ensureSubscriptionServiceForSharedLinks() {
    local confirm=
    if subscriptionServiceConfigured; then
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

syncAndShowUserSubscriptionLinks() {
    local userSubscriptionId=$1
    runSubscriptionGroupSync skip-subscribe-refresh || return 1
    showUserSubscriptionLinks "${userSubscriptionId}"
}

showUserSubscriptionLinksMenu() {
    local userSubscriptionId
    userSubscriptionId=$(selectUserSubscriptionId) || return 1
    showUserSubscriptionLinks "${userSubscriptionId}"
}

showSubscriptionCurrentRoleCredential() {
    local state
    local role
    state=$(subscriptionWireGuardReadState)
    role=$(jq -r '.role' <<<"${state}")
    case "${role}" in
    main)
        showSubscriptionWireGuardMainCredential
        ;;
    controlled)
        showSubscriptionWireGuardControlledCredential
        ;;
    *)
        statusCard "当前还没有可显示的接入凭据" "请先执行 主控建链向导 或 被控加入向导" "完成角色初始化后，这里会根据本机角色显示对应凭据"
        return 1
        ;;
    esac
}

showSubscriptionControlPlaneDetails() {
    showSubscriptionWireGuardStatus
    showSubscriptionSourceControlUrls
}

manageSubscriptionMultiServerAdvanced() {
    while true; do
        echoContent title "\n┌─ 多服务器细项 ─────────────────────────────────────"
        showSubscriptionServerRoleSummary
        menuLine "这里处理多服务器协同的低频维护。"
        menuLine "建议先在上一级完成接入和协同，再到这里查看控制面细节或进入主控/被控细项。"
        menuItem 1 "主控细项" "进入主控专用细项菜单，处理控制面和被控维护"
        menuItem 2 "被控细项" "进入被控专用细项菜单，处理导入、修复和停用"
        menuItem 3 "查看控制面细节" "连续查看控制面状态和 WireGuard 内网 health/sync 地址"
        menuItem 4 "兼容 WireGuard 控制面" "进入旧版主控/被控混合控制面入口"
        menuReturnItem 5 "返回多服务器协同" "回到上级菜单"
        menuClose
        autoRead subscription_multi_server_advanced_menu "请选择:" multiServerAdvancedStatus
        case "${multiServerAdvancedStatus}" in
        1) manageMainControllerSubscriptions ;;
        2) manageControlledSubscription ;;
        3) showSubscriptionControlPlaneDetails ;;
        4) manageSubscriptionWireGuardControlMenu ;;
        5) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

showSubscriptionMultiServerStatus() {
    showSubscriptionCurrentRoleCredential || true
    showSubscriptionSources
    showSubscriptionRemoteHealthPlan
    showSubscriptionSourceSyncResults
}

manageSubscriptionMultiServer() {
    while true; do
        echoContent title "\n┌─ 多服务器协同 ─────────────────────────────────────"
        showSubscriptionServerRoleSummary
        menuLine "这里处理多服务器协同的高频动作。"
        menuLine "建议先完成角色接入，再添加被控并查看协同状态。"
        menuItem 1 "主控建链向导" "初始化主控、复制主控凭据、添加被控并检查健康"
        menuItem 2 "被控加入向导" "初始化被控、导入主控凭据并输出本机接入凭据"
        menuItem 3 "添加/移除被控服务器" "主控粘贴被控凭据添加，或移除已有被控"
        menuItem 4 "更新被控服务器凭据" "被控重建后粘贴新凭据更新 Token 和内网地址"
        menuItem 5 "查看协同状态" "连续查看本机接入凭据、服务器源、健康检查和最近同步结果"
        menuItem 6 "多服务器细项" "进入主控/被控细项、控制面细节和兼容入口"
        menuReturnItem 7 "返回订阅与用户" "回到上级菜单"
        menuClose
        autoRead subscription_multi_server_menu "请选择:" multiServerStatus
        case "${multiServerStatus}" in
        1) runSubscriptionMainControllerWizard ;;
        2) runSubscriptionControlledWizard ;;
        3) addSubscribeMenu ;;
        4) setSubscriptionSourceControlTokenMenu ;;
        5) showSubscriptionMultiServerStatus ;;
        6) manageSubscriptionMultiServerAdvanced ;;
        7) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

manageSubscriptionOperationsAdvanced() {
    while true; do
        echoContent title "\n┌─ 运行维护细项 ─────────────────────────────────────"
        menuLine "这里处理运行与维护的低频设置。"
        menuLine "建议先在上一级查看总览和运行状态，再到这里处理用量、备份和自动同步。"
        menuItem 1 "用量与限额" "进入用量治理细项，查看单项流量和执行超限处理"
        menuItem 2 "状态备份与恢复" "创建、查看、恢复或显式重建 groups.json"
        menuItem 3 "自动同步设置" "配置定时同步、远程同步和自动执行超限处理"
        menuReturnItem 4 "返回运行与维护" "回到上级菜单"
        menuClose
        autoRead subscription_operations_advanced_menu "请选择:" operationsAdvancedStatus
        case "${operationsAdvancedStatus}" in
        1) manageTrafficAndQuota ;;
        2) manageSubscriptionStateBackups ;;
        3) manageSubscriptionSyncSettings ;;
        4) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

showSubscriptionOperationsStatus() {
    showSubscriptionGroupsStateSummary
    showSubscriptionLocalSyncPlan
    showSubscriptionRemoteSyncPlan
    showSubscriptionSourceSyncResults
}

manageSubscriptionOperations() {
    while true; do
        echoContent title "\n┌─ 运行与维护 ───────────────────────────────────────"
        menuLine "这里处理订阅运行后的高频维护。"
        menuLine "建议先刷新总览，再执行同步或查看运行状态。"
        menuItem 1 "刷新并查看运行总览" "采集流量后显示订阅用户、服务器源、同步和限额摘要"
        menuItem 2 "立即执行同步" "立即应用本机和远端同步计划"
        menuItem 3 "查看运行状态" "连续查看状态摘要、本机/远端同步计划和最近同步结果"
        menuItem 4 "运行维护细项" "进入用量治理、状态备份恢复和自动同步设置"
        menuReturnItem 5 "返回订阅与用户" "回到上级菜单"
        menuClose
        autoRead subscription_operations_menu "请选择:" operationsStatus
        case "${operationsStatus}" in
        1) collectSubscriptionTraffic && showSubscriptionTrafficOverview ;;
        2) runSubscriptionGroupSync || true ;;
        3) showSubscriptionOperationsStatus ;;
        4) manageSubscriptionOperationsAdvanced ;;
        5) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

# 订阅与用户入口
manageSubscription() {
    progressCard "1" "订阅与用户"
    if [[ -z "${configPath}" ]]; then
        errorCard "未安装"
        exit 0
    fi

    while true; do
        echoContent title "\n┌─ 订阅与用户 ───────────────────────────────────────"
        showSubscriptionServerRoleSummary
        menuLine "这里按任务分组提供订阅与用户相关操作。"
        menuLine "建议按 快速开始 / 我自己用 / 给别人用 / 多服务器协同 / 运行与维护 / 高级诊断 选择入口；只作为被控时可先跳过公网订阅服务。"
        menuItem 1 "快速开始" "按任务闭环走：自己用、给别人用、用量治理或多服务器接入"
        menuItem 2 "我自己用" "安装/更新订阅服务，刷新并查看我的链接、可用服务器和流量"
        menuItem 3 "给别人用" "新建分享订阅，或处理已有订阅的链接、范围、额度和启停"
        menuItem 4 "多服务器协同" "主控/被控接入、添加被控，以及查看协同状态"
        menuItem 5 "运行与维护" "刷新总览、执行同步、查看运行状态，以及处理备份和自动任务"
        menuItem 6 "高级诊断" "查看诊断状态、定时任务、同步错误和兼容入口"
        menuReturnItem 7 "返回主菜单" "回到 padm 管理面板"
        menuClose
        autoRead subscription_menu "请选择:" manageSubscriptionStatus
        case "${manageSubscriptionStatus}" in
        1) manageSubscriptionQuickStart ;;
        2) manageLocalSubscription ;;
        3) manageSharedSubscriptions ;;
        4) manageSubscriptionMultiServer ;;
        5) manageSubscriptionOperations ;;
        6) manageSubscriptionDiagnostics ;;
        7) menu; return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

manageLocalSubscription() {
    while true; do
        echoContent title "\n┌─ 我自己用 ─────────────────────────────────────────"
        menuLine "这里处理当前服务器自己的订阅。"
        menuLine "建议先安装订阅发布服务，再刷新并查看自用链接、可用服务器和本机流量；只作为被控时可先跳过公网订阅服务。"
        menuItem 1 "安装/更新订阅服务" "安装或刷新 Nginx 订阅发布配置"
        menuItem 2 "刷新并查看我的订阅链接" "重新生成并显示当前自用订阅"
        menuItem 3 "查看订阅服务状态" "显示当前订阅发布端口和域名"
        menuItem 4 "查看我的可用服务器" "查看本机和已添加被控服务器源"
        menuItem 5 "查看我的流量" "查看自用账号流量统计"
        menuReturnItem 6 "返回订阅与用户" "回到上级菜单"
        menuClose
        autoRead local_subscription_menu "请选择:" localSubscriptionStatus
        case "${localSubscriptionStatus}" in
        1) installSubscribe && showSubscriptionServiceStatus ;;
        2) subscribe ;;
        3) showSubscriptionServiceStatus ;;
        4) showSubscriptionSources ;;
        5) showAdminSubscriptionTraffic ;;
        6) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

showSubscriptionServiceStatus() {
    readNginxSubscribe
    if [[ -n "${subscribePort}" ]]; then
        statusCard "订阅服务" "状态：已配置" "协议：${subscribeType:-https}" "域名：${subscribeDomain:-${currentHost:-未读取}}" "端口：${subscribePort}"
    else
        statusCard "订阅服务" "状态：未检测到可用订阅发布配置" "如需本机向客户端发布订阅，请进入 我自己用 -> 安装/更新订阅服务" "仅作为被控加入主控时，不需要安装公网订阅服务"
    fi
}

manageAdminSubscription() {
    manageLocalSubscription
}

manageSharedSubscriptions() {
    ensureSubscriptionGroupsState
    while true; do
        echoContent title "\n┌─ 给别人用 ─────────────────────────────────────────"
        menuLine "这里处理分享订阅的创建和后续维护。"
        menuLine "建议先新建并发布订阅，再通过已有订阅入口刷新链接、调整范围和额度；超限处理在 运行与维护 -> 运行维护细项 -> 用量与限额 中执行。"
        menuItem 1 "新建并发布订阅" "填写 ID/名称、节点范围和额度，然后同步并拿到可发送的链接"
        menuItem 2 "查看并处理已有订阅" "先查看现有订阅列表，再选择一个刷新链接、改范围、改额度、启停或删除"
        menuItem 3 "同步订阅变更" "把已有订阅变更应用到本机和被控服务器"
        menuItem 4 "预览同步变更" "查看将创建/删除哪些 sub_ 托管账号"
        menuReturnItem 5 "返回订阅与用户" "回到上级菜单"
        menuClose
        autoRead shared_subscription_menu "请选择:" sharedSubscriptionStatus
        case "${sharedSubscriptionStatus}" in
        1) createAndSyncUserSubscriptionWizard ;;
        2) manageUserSubscriptionItem ;;
        3) runSubscriptionGroupSync || true ;;
        4) showSubscriptionLocalSyncPlan ;;
        5) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

manageUserSubscription() {
    manageSharedSubscriptions
}

userResultCard() {
    local title=$1
    echoContent title "\n┌─ ${title} ─────────────────────────────────────────"
}

userJsonCard() {
    local title=$1
    local json=$2
    userResultCard "${title}"
    printf '%s\n' "${json}" | jq .
    menuClose
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

showSubscriptionQuotaPlan() {
    local plan
    plan=$(subscriptionQuotaDryRunPlan) || {
        errorCard "超限处理计划生成失败"
        return 1
    }
    showSubscriptionQuotaPlanJson "${plan}"
}

showUserSubscriptions() {
    local groupId
    local output
    groupId=$(activeSubscriptionGroupId)
    ensureSubscriptionGroupsState
    output=$(subscriptionGroupsStateRead -r --arg groupId "${groupId}" '
      def quotaStatus($userGroup; $traffic):
        if ($userGroup.traffic_limit_gb // 0) <= 0 then
          "不限额"
        else
          ((($userGroup.traffic_limit_gb * 1024 * 1024 * 1024) | floor) as $limitBytes |
           (((($traffic.upload // 0) + ($traffic.download // 0)) * 100 / $limitBytes) | floor) as $percent |
           if $percent >= 100 then "已超限(" + ($percent | tostring) + "%)"
           elif $percent >= 80 then "接近上限(" + ($percent | tostring) + "%)"
           else "正常(" + ($percent | tostring) + "%)" end)
        end;
      .groups[] | select(.id == $groupId) |
      . as $group |
      .user_groups[]? |
      "\(.id):\(.name):\(.enabled):\(.allowed_sources | join(",")):\(.traffic_limit_gb):\(quotaStatus(.; $group.traffic.user_groups[.id] // {upload:0, download:0}))"')
    if [[ -z "${output}" ]]; then
        statusCard "用户订阅" "暂无用户订阅"
        return
    fi
    userResultCard "用户订阅列表"
    while IFS=: read -r id name enabled sources limit quota; do
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

createUserSubscription() {
    local id=
    local name=
    autoRead user_subscription_id "请输入分享订阅ID[只用于管理，例 team-a]:" id
    autoRead user_subscription_name "请输入显示名称[例 家人A/团队A]:" name
    if [[ -z "${id}" || -z "${name}" ]] || ! echo "${id}" | grep -qE '^[a-zA-Z0-9_-]+$'; then
        errorCard "输入有误，ID 只能包含英文、数字、下划线或短横线，名称不能为空"
        return 1
    fi
    addUserSubscriptionState "${id}" "${name}"
    successCard "用户订阅已创建"
}

createAndSyncUserSubscriptionWizard() {
    local id=
    local name=
    local sourceIds=main
    local sourceJson=
    local limit=0
    local confirm=
    local enableSync=
    local canShowLinks=true
    autoRead user_subscription_id "请输入分享订阅ID[只用于管理，例 team-a]:" id
    autoRead user_subscription_name "请输入显示名称[例 家人A/团队A]:" name
    if [[ -z "${id}" || -z "${name}" ]] || ! echo "${id}" | grep -qE '^[a-zA-Z0-9_-]+$'; then
        errorCard "输入有误，ID 只能包含英文、数字、下划线或短横线，名称不能为空"
        return 1
    fi

    if ! ensureSubscriptionServiceForSharedLinks; then
        if [[ "$?" == "2" ]]; then
            return 1
        fi
        canShowLinks=false
    fi

    userResultCard "这个订阅可使用的服务器"
    menuLine "这里设置这个订阅的服务器范围。"
    menuLine "建议先确保远端服务器已接入，再输入 main、远端服务器 ID 或 *；多个服务器用英文逗号分隔，例如 main,remote-a。"
    listSubscriptionSources
    menuClose
    autoRead user_subscription_sources "请输入服务器范围[回车默认 main]:" sourceIds
    sourceIds=${sourceIds:-main}
    sourceJson=$(printf '%s' "${sourceIds}" | jq -R 'split(",") | map(gsub("^ +| +$"; "")) | map(select(length > 0))')
    if [[ "$(jq 'length' <<<"${sourceJson}")" == "0" ]]; then
        errorCard "服务器范围不能为空；直接回车使用本机 main"
        return 1
    fi

    autoRead user_subscription_traffic_limit "请输入订阅额度GB[回车/0为不限；这里只设置额度，超限处理在 运行与维护 -> 运行维护细项 -> 用量与限额 中执行]:" limit
    limit=${limit:-0}
    if ! echo "${limit}" | grep -qE '^[0-9]+$'; then
        errorCard "订阅额度必须是数字"
        return 1
    fi

    addUserSubscriptionState "${id}" "${name}"
    setUserSubscriptionSources "${id}" "${sourceJson}"
    setUserSubscriptionTrafficLimit "${id}" "${limit}"
    statusCard "分享订阅已创建" "订阅ID：${id}" "显示名称：${name}" "实际托管账号：$(subscriptionSyncAccountName "${id}")" "服务器范围：${sourceIds}" "订阅额度GB：${limit}" "超限停用和批量处理请到 运行与维护 -> 运行维护细项 -> 用量与限额 执行"

    if ! subscriptionGroupSyncEnabled; then
        autoRead user_subscription_enable_auto_sync "是否开启后续自动同步？[yes/no，默认 yes]：" enableSync
        enableSync=${enableSync:-yes}
        if [[ "${enableSync}" == "yes" || "${enableSync}" == "y" ]]; then
            subscriptionGroupsStateWrite --arg groupId "$(activeSubscriptionGroupId)" '.groups |= map(if .id == $groupId then .sync.enabled = true else . end)'
            refreshSubscriptionGroupSyncCron
            successCard "自动同步已开启" "后续会按当前间隔自动同步；可在 运行与维护 -> 运行维护细项 -> 自动同步设置 中调整间隔"
        else
            statusCard "自动同步未开启" "本次仍可立即同步一次；后续变更需手动同步，或到 运行与维护 -> 运行维护细项 -> 自动同步设置 中开启"
        fi
    fi

    autoRead user_subscription_sync_now "现在同步并发布这个订阅？[yes/no，默认 yes]:" confirm
    confirm=${confirm:-yes}
    if [[ "${confirm}" == "yes" || "${confirm}" == "y" ]]; then
        runSubscriptionGroupSync skip-subscribe-refresh || return 1
        if [[ "${canShowLinks}" == "true" ]]; then
            showUserSubscriptionLinks "${id}"
        else
            statusCard "同步完成，但暂时还不能查看链接" "订阅对象和托管账号已生成" "等安装好订阅服务后，到 给别人用 -> 查看并处理已有订阅 中再刷新并查看链接"
        fi
    else
        statusCard "稍后同步" "该订阅已保存；之后可在 给别人用 -> 同步订阅变更 中生成托管账号，再到 查看并处理已有订阅 中刷新并查看链接"
    fi
}

selectUserSubscriptionId() {
    local id=
    local subscriptions=
    ensureSubscriptionGroupsState
    subscriptions=$(listUserSubscriptions)
    if [[ -z "${subscriptions}" ]]; then
        statusCard "用户订阅" "暂无用户订阅" "先到 给别人用 -> 新建并发布订阅 创建一个"
        return 1
    fi
    showUserSubscriptions
    autoRead select_user_subscription_id "请输入用户订阅ID:" id
    if [[ -z "${id}" ]] || ! userSubscriptionExists "${id}"; then
        errorCard "用户订阅 ID 无效，请按上面的列表重新输入"
        return 1
    fi
    echo "${id}"
}

showUserSubscriptionLinks() {
    local userSubscriptionId=$1
    local accountName
    accountName=$(subscriptionSyncAccountName "${userSubscriptionId}")
    if ! ensureSubscriptionServiceForSharedLinks; then
        return 1
    fi
    if ! subscribe false; then
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

    if [[ "${stateRestored}" != "true" && "${configRestored}" != "true" ]]; then
        errorCard "${reason}，且订阅状态与托管账号配置恢复失败，请手动检查 $(subscriptionGroupsFile) 和备份目录: ${configBackupDir}"
        return 1
    fi
    if [[ "${stateRestored}" != "true" ]]; then
        errorCard "${reason}，且订阅状态恢复失败，请手动检查 $(subscriptionGroupsFile)"
        return 1
    fi
    if [[ "${configRestored}" != "true" ]]; then
        errorCard "${reason}，且托管账号配置恢复失败，请手动检查备份目录: ${configBackupDir}"
        return 1
    fi
}

removeUserSubscriptionMenu() {
    local userSubscriptionId=$1
    local confirm=
    local previousGroupsState
    local configBackupDir
    local accountName
    autoRead remove_user_subscription_confirm "删除订阅 ${userSubscriptionId} 会移除状态；同步后会删除对应 sub_ 托管账号。确认请输入 yes：" confirm
    if [[ "${confirm}" != "yes" ]]; then
        statusCard "已取消" "操作未执行"
        return 1
    fi
    previousGroupsState=$(subscriptionGroupsStateRead -c '.') || {
        errorCard "读取当前订阅状态失败，请手动检查 $(subscriptionGroupsFile)"
        return 1
    }
    configBackupDir=$(subscriptionSyncCreateConfigBackups) || {
        errorCard "删除订阅前托管账号配置备份失败，请手动检查本机配置"
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
        errorCard "托管账号配置移除失败，已恢复旧配置"
        return 1
    fi
    if ! reloadCore; then
        if ! removeUserSubscriptionRollback "${previousGroupsState}" "${configBackupDir}" "核心重载失败"; then
            return 1
        fi
        if reloadCore; then
            errorCard "核心重载失败，已恢复旧配置"
        else
            errorCard "核心重载失败，已恢复旧配置；恢复旧配置后核心重载仍失败，请检查核心服务日志"
        fi
        return 1
    fi
    padmRemoveCleanupPath "${configBackupDir}"
    successCard "用户订阅已删除"
}

manageUserSubscriptionItem() {
    local userSubscriptionId
    userSubscriptionId=$(selectUserSubscriptionId) || return
    while true; do
        echoContent title "\n┌─ 处理已有订阅 ─────────────────────────────────────"
        menuLine "当前订阅：${userSubscriptionId}"
        menuLine "这里处理一个已有订阅的日常维护。"
        menuLine "建议先刷新并查看链接，再调整范围和额度；批量同步与超限处理在 运行与维护 中处理。"
        menuItem 1 "同步并刷新链接" "先应用订阅变更，再重新生成当前链接"
        menuItem 2 "刷新并查看当前链接" "重新生成订阅输出并显示该订阅当前链接"
        menuItem 3 "查看当前用量" "只读查看累计用量和额度状态"
        menuItem 4 "设置节点范围" "选择 main、被控服务器 ID 或 *"
        menuItem 5 "设置订阅额度" "0 表示不限；这里只设置额度，不执行超限处理"
        menuItem 6 "启用/停用当前订阅" "停用后同步会移除对应托管账号"
        menuItem 7 "预览同步变更" "查看将创建/删除哪些 sub_ 托管账号"
        menuDangerItem 8 "删除订阅" "删除记录；同步后移除对应托管账号"
        menuReturnItem 9 "返回给别人用" "回到上级菜单"
        menuClose
        autoRead user_subscription_item_menu "请选择:" userSubscriptionItemStatus
        case "${userSubscriptionItemStatus}" in
        1) syncAndShowUserSubscriptionLinks "${userSubscriptionId}" ;;
        2) showUserSubscriptionLinks "${userSubscriptionId}" ;;
        3) showUserSubscriptionTraffic "${userSubscriptionId}" ;;
        4) setUserSubscriptionSourcesMenu "${userSubscriptionId}" ;;
        5) setUserSubscriptionTrafficLimitMenu "${userSubscriptionId}" ;;
        6)
            if toggleUserSubscriptionState "${userSubscriptionId}"; then
                successCard "用户订阅状态已切换"
            else
                errorCard "用户订阅状态切换失败"
            fi
            ;;
        7) showSubscriptionLocalSyncPlan ;;
        8) removeUserSubscriptionMenu "${userSubscriptionId}" && return ;;
        9) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

setUserSubscriptionSourcesMenu() {
    local userSubscriptionId=$1
    local sourceIds=
    local sourceJson=
    local line=

    userResultCard "这个订阅可使用的服务器"
    menuLine "这里设置这个订阅的服务器范围。"
    menuLine "建议先确保远端服务器已添加凭据，再输入 main、远端服务器 ID 或 *；多个服务器用英文逗号分隔，例如 main,remote-a。"
    while IFS= read -r line; do
        menuLine "${line}"
    done < <(listSubscriptionSources)
    menuClose
    autoRead user_subscription_sources "请输入服务器范围，多个用逗号分隔:" sourceIds
    if [[ -z "${sourceIds}" ]]; then
        errorCard "服务器范围不能为空；直接回车使用本机 main"
        return 1
    fi
    if ! sourceJson=$(printf '%s' "${sourceIds}" | jq -R 'split(",") | map(gsub("^ +| +$"; "")) | map(select(length > 0))'); then
        errorCard "服务器范围解析失败"
        return 1
    fi
    if ! setUserSubscriptionSources "${userSubscriptionId}" "${sourceJson}"; then
        errorCard "节点范围更新失败"
        return 1
    fi
    successCard "节点范围已更新"
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
    successCard "订阅额度已更新" "超限停用和批量处理请到 运行与维护 -> 运行维护细项 -> 用量与限额 执行"
}



# 服务器源管理
normalizeSubscriptionSourceInput() {
    return 1
}

remoteSubscribeFile() {
    subscriptionGroupsFile
}

listRemoteSubscribeSources() {
    listSubscriptionSources | awk -F ':' '$3 != "main" {print $5":"$6":"$2":"$4}'
}

# 添加服务器源
addSubscribeMenu() {
    local addSubscribeStatus=
    local sourceId=
    while true; do
        echoContent title "\n┌─ 服务器源管理 ─────────────────────────────────────"
        menuLine "这里管理主控上的被控服务器源。"
        menuLine "建议先在被控执行被控加入向导，再回到这里添加或移除被控服务器。"
        menuItem 1 "添加被控服务器" "粘贴被控凭据，新增 WireGuard Peer 和服务器源"
        menuItem 2 "移除被控服务器" "删除已有被控来源"
        menuReturnItem 3 "返回主控菜单" "回到上级菜单"
        menuClose
        autoRead server_source_menu "请选择:" addSubscribeStatus
        case "${addSubscribeStatus}" in
        1) addOtherSubscribe ;;
        2)
            sourceId=
            echoContent title "\n┌─ 移除被控服务器 ───────────────────────────────────"
            menuLine "这里列出当前可移除的被控服务器。"
            listSubscriptionSources | awk -F ':' '$3 != "main" {print "│ " NR ". " $0}'
            menuClose
            autoRead delete_subscription_source "请输入要删除的被控服务器源ID:" sourceId
            if [[ -z "${sourceId}" ]]; then
                errorCard "被控服务器源 ID 不可以为空"
                continue
            fi
            if ! subscriptionSourceExists "${sourceId}" || subscriptionSourceIsMain "${sourceId}"; then
                errorCard "被控服务器源 ID 无效"
                continue
            fi
            removeSubscriptionSourceState "${sourceId}"
            successCard "被控服务器删除成功" "如需应用订阅变更，请到 运行与维护 -> 立即执行同步"
            ;;
        3) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

# 添加被控服务器
addOtherSubscribe() {
    local credential=
    local credentialJson=
    local host=
    local port=
    local alias=
    echoContent title "\n┌─ 添加被控服务器 ───────────────────────────────────"
    menuLine "这里添加一个被控服务器。"
    menuLine "建议先在被控执行被控加入向导，再把本机被控接入凭据粘贴到这里；系统会自动解析地址、端口、Token 和公钥。"
    menuClose
    autoRead subscription_control_credential "请粘贴被控接入凭据:" credential
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
    autoRead subscription_source_alias "请输入被控服务器别名[英文/数字/短横线，例 hk-1]:" alias
    if [[ -z "${alias}" ]] || ! echo "${alias}" | grep -qE '^[a-zA-Z0-9_-]+$'; then
        errorCard "别名只能使用英文、数字、短横线或下划线"
        return 1
    fi
    if subscriptionRemoteSourceSelfReference "$(jq -n --arg host "${host}" '{host:$host}')"; then
        errorCard "被控服务器指向当前主控 WireGuard 地址，已拒绝添加，避免递归同步"
        return 1
    fi
    if ! subscriptionWireGuardAddPeerFromCredential "${alias}" "${credentialJson}"; then
        errorCard "被控服务器添加失败"
        return 1
    fi
    successCard "被控服务器已添加" "WireGuard 内网地址：${host}:${port}" "别名：${alias}" "已保存 Token 和 Peer，可继续测试被控连接或执行同步"
}






showSubscriptionSources() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" '
      .groups[] | select(.id == $groupId) | .sources[]? |
      "ID:\(.id)\n名称:\(.name)\n角色:\(.role)\n地址:\(.scheme)://\(.host):\(.port)\n启用:\(.enabled)\n同步状态:\(.sync_status)" +
      (if has("last_sync_changed") then "\n上次同步变更:" + (if .last_sync_changed then "是" else "否" end) else "" end) +
      (if .last_sync_plan? then "\n上次同步计划: 创建\((.last_sync_plan.create // []) | length)，删除\((.last_sync_plan.remove // []) | length)" else "" end) +
      (if .last_sync_error? then "\n上次同步错误:\(.last_sync_error.type) \(.last_sync_error.message)" else "" end) +
      "\n---"'
}

showSubscriptionSourceControlUrls() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" '
      .groups[] | select(.id == $groupId) | .sources[]? | select(.role != "main") |
      "ID:\(.id)\n名称:\(.name)\n控制面:WireGuard\n内网地址:\(.host):\(.port)\nHealth:http://\(.host):\(.port)/s/control/health\nSync:http://\(.host):\(.port)/s/control/sync\n---"'
}

showSubscriptionSourceSyncResults() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateRead -r --arg groupId "${groupId}" '
      .groups[] | select(.id == $groupId) | .sources[]? |
      "ID:\(.id)\n名称:\(.name)\n同步状态:\(.sync_status)" +
      (if has("last_sync_changed") then "\n上次同步变更:" + (if .last_sync_changed then "是" else "否" end) else "" end) +
      (if .last_sync_plan? then "\n上次同步计划: 创建\((.last_sync_plan.create // []) | length)，删除\((.last_sync_plan.remove // []) | length)" else "" end) +
      (if .last_sync_error? then "\n上次同步错误:\(.last_sync_error.type) \(.last_sync_error.message)" else "" end) +
      "\n---"'
}

manageMainControllerSubscriptions() {
    while true; do
        echoContent title "\n┌─ 多服务器：主控 ───────────────────────────────────"
        menuLine "这里处理主控侧的协同维护。"
        menuLine "建议先添加被控，再测试连接，最后查看同步结果。"
        menuItem 1 "主控建链向导" "初始化主控、输出凭据、添加被控、检查健康并预览同步"
        menuItem 2 "添加/移除被控服务器" "粘贴被控接入凭据添加，或删除已有被控"
        menuItem 3 "测试被控连接" "请求所有被控健康检查"
        menuItem 4 "查看同步结果" "显示最近同步计划和错误"
        menuItem 5 "更新被控服务器凭据" "被控重建后粘贴新凭据更新 Token/内网地址"
        menuItem 6 "查看服务器源" "列出本机和已添加被控服务器"
        menuItem 7 "主控控制面细项" "查看主控凭据、Peer 和状态，必要时重写配置并重启"
        menuItem 8 "查看控制面地址" "显示 WireGuard 内网 health/sync 地址"
        menuItem 9 "启用/停用被控服务器" "切换被控服务器源状态"
        menuItem 10 "清除同步错误" "清理最近同步错误"
        menuReturnItem 11 "返回订阅与用户" "回到上级菜单"
        menuClose
        autoRead main_controller_subscription_menu "请选择:" mainControllerSubscriptionStatus
        case "${mainControllerSubscriptionStatus}" in
        1) runSubscriptionMainControllerWizard ;;
        2) addSubscribeMenu ;;
        3) showSubscriptionRemoteHealthPlan ;;
        4) showSubscriptionSourceSyncResults ;;
        5) setSubscriptionSourceControlTokenMenu ;;
        6) showSubscriptionSources ;;
        7) manageSubscriptionMainControlMenu ;;
        8) showSubscriptionSourceControlUrls ;;
        9) toggleSubscriptionSourceMenu ;;
        10) clearSubscriptionSourceSyncErrorMenu ;;
        11) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

manageControlledSubscription() {
    while true; do
        echoContent title "\n┌─ 多服务器：被控 ───────────────────────────────────"
        menuLine "这里处理被控侧的接入和维护。"
        menuLine "建议先加入主控，再把本机接入凭据交回主控。"
        menuItem 1 "被控加入向导" "初始化被控、导入主控凭据并输出被控接入凭据"
        menuItem 2 "初始化本机为被控" "安装 WireGuard 内网控制面，不安装公网订阅服务"
        menuItem 3 "导入主控接入凭据" "加入主控 WireGuard 网络"
        menuItem 4 "查看本机被控接入凭据" "复制回主控添加被控"
        menuItem 5 "查看被控控制面状态" "显示角色、接口、内网地址和端口"
        menuItem 6 "重写配置并重启被控控制面" "重写配置并重启 WireGuard 和控制服务"
        menuDangerItem 7 "关闭被控控制面" "停止本机 WireGuard 控制面"
        menuReturnItem 8 "返回订阅与用户" "回到上级菜单"
        menuClose
        autoRead controlled_subscription_menu "请选择:" controlledSubscriptionStatus
        case "${controlledSubscriptionStatus}" in
        1) runSubscriptionControlledWizard ;;
        2) initSubscriptionWireGuardControlled ;;
        3) importSubscriptionWireGuardMainCredential ;;
        4) showSubscriptionWireGuardControlledCredential ;;
        5) showSubscriptionWireGuardStatus ;;
        6) restartSubscriptionWireGuardControl ;;
        7) disableSubscriptionWireGuardControl ;;
        8) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

manageSubscriptionMainControlMenu() {
    while true; do
        echoContent title "\n┌─ 主控控制面 ───────────────────────────────────────"
        menuLine "这里处理主控控制面的状态和维护。"
        menuLine "建议先查看凭据和连接状态，再决定是否重启或关闭。"
        showSubscriptionWireGuardStatus
        menuItem 1 "查看本机主控接入凭据" "复制到被控服务器导入"
        menuItem 2 "查看 Peer 和连接状态" "查看 WireGuard peer 和被控列表"
        menuItem 3 "测试被控连接" "请求所有被控健康检查"
        menuItem 4 "初始化本机为主控" "生成主控 WireGuard 控制面"
        menuItem 5 "重写配置并重启主控控制面" "重写配置并重启控制服务"
        menuDangerItem 6 "关闭主控控制面" "停止本机 WireGuard 控制面"
        menuReturnItem 7 "返回多服务器：主控" "回到上级菜单"
        menuClose
        autoRead main_control_menu "请选择:" mainControlMenuStatus
        case "${mainControlMenuStatus}" in
        1) showSubscriptionWireGuardMainCredential ;;
        2) showSubscriptionWireGuardPeers ;;
        3) testSubscriptionWireGuardControl ;;
        4) initSubscriptionWireGuardMain ;;
        5) restartSubscriptionWireGuardControl ;;
        6) disableSubscriptionWireGuardControl ;;
        7) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

manageSubscriptionWireGuardControlMenu() {
    while true; do
        echoContent title "\n┌─ WireGuard 控制面 ─────────────────────────────────"
        menuLine "这里提供 WireGuard 控制面的兼容入口。"
        menuLine "建议优先从 多服务器协同 进入主控或被控专用流程。"
        showSubscriptionWireGuardStatus
        menuItem 1 "初始化本机为主控" "生成主控 WireGuard 控制面"
        menuItem 2 "初始化本机为被控" "生成被控 WireGuard 控制面"
        menuItem 3 "查看本机主控接入凭据" "复制到被控服务器导入"
        menuItem 4 "导入主控接入凭据" "仅被控使用，用于加入主控"
        menuItem 5 "查看本机被控接入凭据" "复制回主控服务器添加被控"
        menuItem 6 "查看 Peer 和连接状态" "查看 WireGuard peer 和被控列表"
        menuItem 7 "测试控制面连接" "请求所有被控健康检查"
        menuItem 8 "重写配置并重启 WireGuard 控制面" "重写配置并重启控制服务"
        menuDangerItem 9 "关闭 WireGuard 控制面" "停止本机 WireGuard 控制面"
        menuReturnItem 10 "返回多服务器入口" "回到上级菜单"
        menuClose
        autoRead subscription_wireguard_menu "请选择:" subscriptionWireGuardMenuStatus
        case "${subscriptionWireGuardMenuStatus}" in
        1) initSubscriptionWireGuardMain ;;
        2) initSubscriptionWireGuardControlled ;;
        3) showSubscriptionWireGuardMainCredential ;;
        4) importSubscriptionWireGuardMainCredential ;;
        5) showSubscriptionWireGuardControlledCredential ;;
        6) showSubscriptionWireGuardPeers ;;
        7) testSubscriptionWireGuardControl ;;
        8) restartSubscriptionWireGuardControl ;;
        9) disableSubscriptionWireGuardControl ;;
        10) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

setSubscriptionSourceControlTokenMenu() {
    local credential=
    local credentialJson=
    local host=
    local port=
    local sourceId=
    local token=
    local matches=
    echoContent title "\n┌─ 更新被控服务器凭据 ───────────────────────────────"
    menuLine "这里更新一个被控服务器的接入凭据。"
    menuLine "建议先在被控执行被控加入向导，再把新的本机被控接入凭据粘贴到这里；系统会自动更新地址、端口和 Token。"
    menuClose
    autoRead subscription_control_credential "请粘贴被控接入凭据:" credential
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
    token=$(jq -r '.token' <<<"${credentialJson}")
    matches=$(listSubscriptionSources | awk -F ':' -v host="${host}" -v port="${port}" '$3 != "main" && $5 == host && $6 == port {print $1}')
    if [[ -n "${matches}" ]] && [[ "$(printf '%s\n' "${matches}" | wc -l | tr -d ' ')" == "1" ]]; then
        sourceId=${matches}
    else
        listSubscriptionSources | awk -F ':' '$3 != "main" {print $1":"$2":"$4":"$5":"$6":"$8}'
        autoRead subscription_source_id "请输入要更新的被控服务器别名:" sourceId
    fi
    if [[ -z "${sourceId}" ]] || ! subscriptionSourceExists "${sourceId}" || subscriptionSourceIsMain "${sourceId}"; then
        errorCard "被控服务器别名无效"
        return 1
    fi
    setSubscriptionSourceCredential "${sourceId}" "${host}" "${port}" "${token}" || {
        errorCard "被控服务器凭据更新失败"
        return 1
    }
    successCard "被控服务器凭据已更新" "内网地址：${host}:${port}" "别名：${sourceId}" "Token 已保存，可继续测试被控连接"
}

toggleSubscriptionSourceMenu() {
    local sourceId=
    local sourceAction=
    listSubscriptionSources | awk -F ':' '$3 != "main" {print $1":"$2":启用="$7}'
    autoRead subscription_source_toggle_id "请输入被控服务器源ID:" sourceId
    if [[ -z "${sourceId}" ]] || ! subscriptionSourceExists "${sourceId}" || subscriptionSourceIsMain "${sourceId}"; then
        errorCard "服务器源 ID 无效"
        return 1
    fi
    autoRead subscription_source_action "请输入操作[enable/disable]:" sourceAction
    if [[ "${sourceAction}" == "enable" ]]; then
        setSubscriptionSourceEnabled "${sourceId}" true
        successCard "被控服务器已启用"
    elif [[ "${sourceAction}" == "disable" ]]; then
        setSubscriptionSourceEnabled "${sourceId}" false
        successCard "被控服务器已停用"
    else
        errorCard "操作无效"
        return 1
    fi
}

clearSubscriptionSourceSyncErrorMenu() {
    local sourceId=
    showSubscriptionSourceSyncResults
    autoRead subscription_clear_error_source "请输入要清除错误的被控服务器源ID:" sourceId
    if [[ -z "${sourceId}" ]] || ! subscriptionSourceExists "${sourceId}"; then
        errorCard "服务器源 ID 无效"
        return 1
    fi
    clearSubscriptionSourceSyncError "${sourceId}"
    successCard "同步错误已清除"
}

showSubscriptionDiagnosticsOverview() {
    showSubscriptionServiceStatus
    showSubscriptionWireGuardStatus
    showSubscriptionGroupsStateSummary
    showSubscriptionRemoteHealthPlan
    showSubscriptionSourceSyncResults
}

manageSubscriptionDiagnostics() {
    while true; do
        echoContent title "\n┌─ 高级诊断 ─────────────────────────────────────────"
        menuLine "这里集中处理订阅相关故障排查。"
        menuLine "建议先查看诊断状态，再按需查看定时任务、清除同步错误或进入兼容入口。"
        menuItem 1 "查看诊断状态" "连续查看订阅服务、WireGuard、状态摘要、远端健康和最近同步错误"
        menuItem 2 "查看定时任务" "显示当前 cron 配置"
        menuItem 3 "清除同步错误" "清理指定服务器源最近同步错误"
        menuItem 4 "兼容 WireGuard 控制面" "进入旧版主控/被控混合控制面入口"
        menuReturnItem 5 "返回订阅与用户" "回到上级菜单"
        menuClose
        autoRead subscription_diagnostics_menu "请选择:" diagnosticsStatus
        case "${diagnosticsStatus}" in
        1) showSubscriptionDiagnosticsOverview ;;
        2) subscriptionGroupSyncCronStatus ;;
        3) clearSubscriptionSourceSyncErrorMenu ;;
        4) manageSubscriptionWireGuardControlMenu ;;
        5) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}

removeSubscriptionGroupSyncCron() {
    local cronFile
    local currentCron
    cronFile=$(subscriptionGroupSyncCronFile)
    mkdir -p "$(dirname "${cronFile}")"
    currentCron=$(crontab -l 2>/dev/null | sed '/SyncSubscriptionGroups/d' || true)
    installUserCrontabContent "${currentCron}"
}

refreshSubscriptionGroupSyncCron() {
    ensureSubscriptionGroupsState
    if subscriptionGroupSyncEnabled; then
        installSubscriptionGroupSyncCron
    else
        removeSubscriptionGroupSyncCron
    fi
}

subscriptionGroupSyncCronStatus() {
    crontab -l 2>/dev/null | grep 'SyncSubscriptionGroups' || true
}

manageSubscriptionSyncSettings() {
    local groupId
    local syncStatus
    while true; do
        groupId=$(activeSubscriptionGroupId)
        syncStatus=$(subscriptionGroupsStateRead -r --arg groupId "${groupId}" '.groups[] | select(.id == $groupId) | .sync')
        echoContent title "\n┌─ 自动同步 ─────────────────────────────────────────"
        menuLine "这里处理自动同步和超限策略。"
        menuLine "建议先查看同步计划，再决定是否开启自动同步、调整间隔或执行超限处理。"
        userJsonCard "自动同步当前状态" "${syncStatus}"
        echoContent title "\n┌─ 自动同步操作 ─────────────────────────────────────"
        menuItem 1 "开启/关闭自动同步" "切换定时同步状态"
        menuItem 2 "设置自动同步间隔" "设置 1-59 分钟间隔"
        menuItem 3 "查看本机同步计划" "预览本机 create/remove"
        menuItem 4 "查看远程同步计划" "预览远端同步计划"
        menuItem 5 "立即执行同步" "立即应用同步计划"
        menuItem 6 "查看超限处理计划" "预览超额用户处理"
        menuDangerItem 7 "执行超限处理" "停用超额用户并等待同步移除账号"
        menuItem 8 "开启/关闭远程同步" "切换远端同步状态"
        menuItem 9 "开启/关闭自动执行超限处理" "切换超限处理自动执行状态"
        menuItem 10 "查看定时任务" "显示当前 cron 配置"
        menuReturnItem 11 "返回运行维护细项" "回到上级菜单"
        menuClose
        autoRead sync_settings_menu "请选择:" syncSettingsStatus
        case "${syncSettingsStatus}" in
        1)
            subscriptionGroupsStateWrite --arg groupId "${groupId}" '.groups |= map(if .id == $groupId then .sync.enabled = (.sync.enabled | not) else . end)'
            refreshSubscriptionGroupSyncCron
            successCard "自动同步状态已切换"
            ;;
        2)
            local interval=
            autoRead sync_interval_minutes "请输入同步间隔分钟:" interval
            if ! subscriptionGroupSyncIntervalValid "${interval}"; then
                errorCard "输入有误，同步间隔需为 1-59 分钟"
                continue
            fi
            subscriptionGroupsStateWrite --arg groupId "${groupId}" --argjson interval "${interval}" '.groups |= map(if .id == $groupId then .sync.interval_minutes = $interval else . end)'
            refreshSubscriptionGroupSyncCron
            successCard "自动同步间隔已更新"
            ;;
        3) showSubscriptionLocalSyncPlan ;;
        4) showSubscriptionRemoteSyncPlan ;;
        5) runSubscriptionGroupSync || true ;;
        6) showSubscriptionQuotaPlan ;;
        7) executeSubscriptionQuotaPlanMenu ;;
        8)
            subscriptionGroupsStateWrite --arg groupId "${groupId}" '.groups |= map(if .id == $groupId then .sync.remote_enabled = ((.sync.remote_enabled // true) | not) else . end)'
            successCard "远程同步状态已切换"
            ;;
        9)
            subscriptionGroupsStateWrite --arg groupId "${groupId}" '.groups |= map(if .id == $groupId then .sync.quota_auto_apply = ((.sync.quota_auto_apply // false) | not) else . end)'
            successCard "限额自动执行状态已切换"
            ;;
        10) subscriptionGroupSyncCronStatus ;;
        11) return ;;
        *) errorCard "选择错误，请重新选择" ;;
        esac
    done
}
