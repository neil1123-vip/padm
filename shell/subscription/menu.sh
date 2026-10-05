#!/usr/bin/env bash

showSubscriptionServerRoleSummary() {
    local state
    local summary
    local role
    local roleText
    local enabledText
    local address
    local peerCount
    state=$(subscriptionWireGuardReadState) || {
        errorCard "WireGuard 控制面状态损坏或不可读" "请先修复 $(subscriptionWireGuardStateFile)"
        return 1
    }
    summary=$(jq -r '[.role, (if .enabled == true then "已启用" else "未启用" end), (if (.address // "") == "" then "未配置" else .address end), (.peers | length | tostring)] | @tsv' <<<"${state}") || return 1
    IFS=$'\t' read -r role enabledText address peerCount <<<"${summary}"
    case "${role}" in
    main) roleText="主控" ;;
    controlled) roleText="被控" ;;
    uninitialized)
        menuLine "多服务器角色：$(uiStyle value "未启用")；可直接使用本机订阅"
        return 0
        ;;
    *) return 1 ;;
    esac
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
        statusCard "已跳过创建邀请" "稍后可从 主控首页 -> 管理被控服务器 -> 创建被控邀请"
    fi
}

runSubscriptionControlledWizard() {
    local credentialJson state existingInviteId replaceConfirmed=false confirmReplace=
    subscriptionWireGuardReadCredential invite "主控邀请" credentialJson || return 1
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

restoreUserSubscriptionMutationState() {
    local previousState=$1
    # 回滚配置而非流量：保留同步期间已入账的累计值和计数器基线。
    subscriptionGroupsStateWrite --argjson previousState "${previousState}" '
      .traffic as $latest |
      $previousState |
      (.sources | map(.id)) as $sourceIds |
      (.user_groups | map(.id)) as $userIds |
      def keepSources: with_entries(.key as $id | select(($sourceIds | index($id)) != null));
      .traffic.admin.sources = ((.traffic.admin.sources + ($latest.admin.sources // {})) | keepSources) |
      .traffic.sources = ((.traffic.sources + ($latest.sources // {})) | keepSources) |
      .traffic.user_groups |= with_entries(
        .key as $id |
        .value.sources = ((.value.sources + ($latest.user_groups[$id].sources // {})) | keepSources)) |
      reduce $userIds[] as $id (.;
        if (.traffic.user_groups | has($id) | not) and ($latest.user_groups | has($id)) then
          .traffic.user_groups[$id] = {sources:($latest.user_groups[$id].sources | keepSources)}
        else . end)
    '
}

runSubscriptionSyncAfterMutation() {
    local reason=${1:-subscription-change}
    local previousState=${2:-}
    local forceSync=${3:-false}
    local configBackupDir=
    local outputBackupDir=
    local restoreState=true
    local rollbackStateRestored=true
    local configRestored=true
    local outputRestored=true
    local servicesRestored=true
    local restoreMessage=
    local restoreDetail=
    if [[ "${forceSync}" != "true" ]] && ! subscriptionGroupSyncEnabled; then
        statusCard "订阅变更已保存" "自动同步已关闭，等待手动完整同步（${reason}）"
        return 0
    fi
    if [[ -n "${previousState}" ]]; then
        subscriptionSyncCreateLocalApplyBackups configBackupDir outputBackupDir || {
            if restoreUserSubscriptionMutationState "${previousState}" >/dev/null 2>&1; then
                warnCard "变更未完成" "无法创建回滚用的本机配置和订阅输出备份，已恢复变更前状态（${reason}）"
            else
                warnCard "变更未完成" "无法创建回滚用的本机配置和订阅输出备份，且变更前状态恢复失败（${reason}）"
            fi
            return 1
        }
    fi
    statusCard "订阅变更已保存" "正在执行完整同步（${reason}）"
    if runSubscriptionGroupSync; then
        subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}"
        return 0
    fi
    if [[ -n "${previousState}" ]]; then
        if ! restoreUserSubscriptionMutationState "${previousState}" >/dev/null 2>&1; then
            restoreState=false
        fi
        if [[ "${restoreState}" == "true" ]]; then
            if SUBSCRIPTION_SYNC_ROLLBACK=true runSubscriptionGroupSync; then
                subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}"
                warnCard "变更未完成" "后置完整同步失败，已恢复变更前状态并完成回滚同步（${reason}）"
            else
                if ! restoreUserSubscriptionMutationState "${previousState}" >/dev/null 2>&1; then
                    rollbackStateRestored=false
                fi
                if ! subscriptionSyncRestoreConfigBackups "${configBackupDir}" >/dev/null 2>&1; then
                    configRestored=false
                fi
                if ! subscriptionSyncRestoreSubscribeOutputBackups "${outputBackupDir}" >/dev/null 2>&1; then
                    outputRestored=false
                fi
                if [[ "${configRestored}" == "true" ]]; then
                    subscriptionSyncReconcileLocalServices >/dev/null 2>&1 || servicesRestored=false
                fi
                if [[ "${rollbackStateRestored}" == "true" && "${configRestored}" == "true" && "${outputRestored}" == "true" && "${servicesRestored}" == "true" ]]; then
                    subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}"
                    subscriptionSyncMarkResult partial '["回滚同步失败，远程服务器可能仍未恢复"]' >/dev/null 2>&1 || true
                    warnCard "变更未完成" "后置完整同步失败，已恢复变更前状态、本机配置和订阅输出，但回滚同步仍失败（${reason}）"
                else
                    subscriptionSyncReleaseLocalApplyBackups forget "${configBackupDir}" "${outputBackupDir}"
                    subscriptionSyncMarkResult partial '["回滚同步失败，变更前状态或本机恢复未完全确认"]' >/dev/null 2>&1 || true
                    restoreMessage="${reason}后回滚同步失败"
                    if [[ "${rollbackStateRestored}" != "true" ]]; then
                        subscriptionSyncSetManualCheckMessage restoreDetail "订阅状态恢复失败" "$(subscriptionGroupsFile)"
                        restoreMessage+="，且${restoreDetail}"
                    fi
                    if [[ "${configRestored}" != "true" ]]; then
                        subscriptionSyncSetManualCheckMessage restoreDetail "本机配置恢复失败" "备份目录: ${configBackupDir}"
                        restoreMessage+="；${restoreDetail}"
                    fi
                    if [[ "${outputRestored}" != "true" ]]; then
                        subscriptionSyncSetManualCheckMessage restoreDetail "订阅输出恢复失败" "备份目录: ${outputBackupDir}"
                        restoreMessage+="；${restoreDetail}"
                    fi
                    if [[ "${servicesRestored}" != "true" ]]; then
                        restoreMessage+="；恢复旧配置后核心重载失败，请检查核心服务日志"
                    fi
                    warnCard "变更未完成" "${restoreMessage:-后置完整同步失败，变更前状态已恢复，但本机配置或订阅输出恢复失败，请检查备份目录}"
                fi
            fi
        else
            if ! subscriptionSyncRestoreConfigBackups "${configBackupDir}" >/dev/null 2>&1; then
                configRestored=false
            fi
            if ! subscriptionSyncRestoreSubscribeOutputBackups "${outputBackupDir}" >/dev/null 2>&1; then
                outputRestored=false
            fi
            if [[ "${configRestored}" == "true" ]]; then
                subscriptionSyncReconcileLocalServices >/dev/null 2>&1 || servicesRestored=false
            fi
            subscriptionSyncReleaseLocalApplyBackups forget "${configBackupDir}" "${outputBackupDir}"
            restoreMessage="${reason}后变更前状态恢复失败"
            if [[ "${configRestored}" != "true" ]]; then
                subscriptionSyncSetManualCheckMessage restoreDetail "本机配置恢复失败" "备份目录: ${configBackupDir}"
                restoreMessage+="；${restoreDetail}"
            fi
            if [[ "${outputRestored}" != "true" ]]; then
                subscriptionSyncSetManualCheckMessage restoreDetail "订阅输出恢复失败" "备份目录: ${outputBackupDir}"
                restoreMessage+="；${restoreDetail}"
            fi
            if [[ "${servicesRestored}" != "true" ]]; then
                restoreMessage+="；恢复旧配置后核心重载失败，请检查核心服务日志"
            fi
            warnCard "变更未完成" "${restoreMessage}；备份已保留，请检查状态文件和备份目录（${reason}）"
        fi
        return 1
    fi
    subscriptionSyncReleaseLocalApplyBackups remove "${configBackupDir}" "${outputBackupDir}"
    warnCard "变更已保存，但后置完整同步失败" "请到 订阅同步 -> 状态与排障 查看失败原因，修复后手动重试"
    return 1
}

SUBSCRIPTION_USER_MUTATION_PREVIOUS_STATE_OVERRIDE=

runUserSubscriptionMutationAndSyncUnlocked() {
    local reason=$1
    local mutationError=${2:-}
    shift 2
    local previousState
    local rollbackState
    SUBSCRIPTION_USER_MUTATION_PREVIOUS_STATE_OVERRIDE=
    previousState=$(subscriptionGroupsStateRead -c '.') || {
        errorCard "用户订阅状态读取失败"
        return 1
    }
    if ! "$@"; then
        [[ -n "${mutationError}" ]] && errorCard "${mutationError}"
        return 1
    fi
    rollbackState=${SUBSCRIPTION_USER_MUTATION_PREVIOUS_STATE_OVERRIDE:-${previousState}}
    runSubscriptionSyncAfterMutation \
        "${reason}" \
        "${rollbackState}" \
        true
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
    manageSubscriptionCatalog uninitialized
}

manageSubscriptionMainHome() {
    subscriptionRequireMainRole || return 1
    manageSubscriptionCatalog main
}

manageSubscriptionControlledHome() {
    subscriptionRequireControlledRole || return 1
    local controlledHomeStatus=
    while true; do
        echoContent title "\n┌─ 被控首页 ─────────────────────────────────────────"
        showSubscriptionServerRoleSummary
        menuItem 1 "接入主控" "粘贴主控邀请，完成接入并生成对应回执"
        menuItem 2 "查看本机状态" "查看角色、地址、Peer 和 WireGuard 状态"
        menuItem 3 "导入/更新主控接入凭据" "仅更新已有连接的主控端点或身份"
        menuItem 4 "显示被控更新凭据" "生成给主控更新地址、公钥、控制端口和 Token 的凭据"
        menuItem 5 "查看控制面与 Peer 细节" "显示 WireGuard 状态以及与主控的 Peer 连接细节"
        menuItem 6 "重写配置并重启被控控制面" "重写配置并重启 WireGuard 和控制服务"
        menuDangerItem 7 "关闭被控控制面" "停止本机 WireGuard 控制面"
        menuReturnItem 8 "返回主菜单" "回到 padm 管理面板"
        menuClose
        menuReadChoice subscription_controlled_home_menu "请选择:" controlledHomeStatus || return 0
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
        8) return 0 ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}

manageSubscriptionMainControlDetails() {
    subscriptionRequireMainRole || return 1
    local mainControlDetailsStatus=
    while true; do
        echoContent title "\n┌─ 本机控制面 ───────────────────────────────────────"
        menuLine "这里处理主控控制面的状态、连接和恢复动作。"
        menuLine "建议先查看凭据、Peer 和连接状态，再决定是否重启或关闭控制面。"
        showSubscriptionWireGuardStatus
        menuItem 1 "显示主控维护凭据" "仅用于维护已有连接，不用于首次接入"
        menuItem 2 "查看连接详情" "一次查看 WireGuard Peer、Health 和 Sync 地址"
        menuItem 3 "重写配置并重启主控控制面" "重写配置并重启控制服务"
        menuDangerItem 4 "关闭主控控制面" "停止本机 WireGuard 控制面"
        menuReturnItem 5 "返回主控首页" "回到上级菜单"
        menuClose
        menuReadChoice subscription_main_control_details_menu "请选择:" mainControlDetailsStatus || return 0
        case "${mainControlDetailsStatus}" in
        1) showSubscriptionWireGuardMainCredential ;;
        2) showSubscriptionWireGuardPeers; showSubscriptionSourceControlUrls ;;
        3) restartSubscriptionWireGuardControl ;;
        4) disableSubscriptionWireGuardControl ;;
        5) return ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}


showSubscriptionWireGuardControlledAccessCredential() {
    subscriptionWireGuardReadState >/dev/null || { errorCard "WireGuard 状态读取失败"; return 1; }
    warnCard "即将显示被控更新凭据" "该凭据包含长期控制 Token，请只通过可信通道传递；首次接入回执会在接入主控后自动显示"
    showSubscriptionWireGuardControlledCredential
}

# 订阅与用户入口
manageSubscription() {
    local role nextRole homeStatus
    if [[ -z "${configPath}" ]]; then
        errorCard "未安装"
        return 0
    fi

    role=$(subscriptionCurrentRoleNormalized) || {
        errorCard "WireGuard 控制面状态损坏或不可读" "请先修复 $(subscriptionWireGuardStateFile)，本机模式不会绕过损坏状态"
        return 1
    }
    while true; do
        homeStatus=0
        case "${role}" in
        uninitialized) manageSubscriptionLocalHome || homeStatus=$? ;;
        main) manageSubscriptionMainHome || homeStatus=$? ;;
        controlled) manageSubscriptionControlledHome || homeStatus=$? ;;
        esac
        nextRole=$(subscriptionCurrentRoleNormalized) || {
            errorCard "WireGuard 控制面状态损坏或不可读" "请先修复 $(subscriptionWireGuardStateFile)，本机模式不会绕过损坏状态"
            return 1
        }
        [[ "${nextRole}" != "${role}" ]] || return "${homeStatus}"
        role=${nextRole}
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
        statusCard "订阅服务" "状态：未检测到可用订阅发布配置" "如需发布订阅，请进入 订阅与用户 -> 安装/更新发布服务" "仅作为被控加入主控时，不需要安装公网订阅服务"
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
    statusCard "被控服务器健康检查" "正在等待启用的被控服务器响应" "单台请求最长 15 秒（含重试），多个服务器并行检查"
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
    statusCard "远程同步计划" "正在等待被控服务器响应" "单台请求最长 40 秒（含重试），多个服务器并行请求"
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

manageSharedSubscriptions() {
    subscriptionRequireLocalPublisherRole || return 1
    while true; do
        selectUserSubscriptionId true true || return 0
        if [[ "${selectedUserSubscriptionId}" == "+" ]]; then
            createAndSyncUserSubscriptionWizard || true
            if [[ -n "${createdUserSubscriptionId:-}" ]]; then
                manageUserSubscriptionItem "${createdUserSubscriptionId}"
            elif [[ "${createdUserSubscriptionIds:-'[]'}" != '[]' ]]; then
                manageUserSubscriptionsMenu "${createdUserSubscriptionIds}" || true
            fi
        elif [[ -n "${selectedUserSubscriptionIds:-}" && "${selectedUserSubscriptionIds}" != '[]' ]]; then
            manageUserSubscriptionsMenu "${selectedUserSubscriptionIds}" || true
        else
            manageUserSubscriptionItem "${selectedUserSubscriptionId}"
        fi
    done
}

manageSubscriptionCatalog() {
    subscriptionRequireLocalPublisherRole || return 1
    local subscriptionCatalogStatus=
    local role=${1:-} currentRole
    local homeTitle menuKey
    local returnChoice publishServiceChoice
    [[ -n "${role}" ]] || role=$(subscriptionCurrentRoleNormalized) || return 1
    if [[ "${role}" == "main" ]]; then
        homeTitle="主控首页"
        menuKey=subscription_main_home_menu
        returnChoice=4
        publishServiceChoice=5
    else
        homeTitle="本机订阅首页"
        menuKey=subscription_local_home_menu
        returnChoice=5
        publishServiceChoice=10
    fi
    while true; do
        echoContent title "\n┌─ ${homeTitle} ─────────────────────────────────────"
        showSubscriptionServerRoleSummary
        menuLine "本机自用订阅来自协议配置；这里统一处理发布、分享订阅和流量。"
        menuItem 1 "查看当前订阅链接" "只读查看已发布的本机自用和分享订阅"
        menuItem 2 "分享订阅" "新建或维护已有分享订阅"
        menuItem 3 "流量与限额" "查看流量明细，并处理超限和自动限额"
        menuItem 6 "立即完整同步" "同步账号及启用来源；已配置发布服务时更新并显示链接"
        menuItem 7 "订阅同步" "自动同步、同步间隔、状态排障和状态备份"
        menuItem "${publishServiceChoice}" "安装/更新发布服务" "配置公网发布入口"
        if [[ "${role}" == "main" ]]; then
            menuItem 8 "管理被控服务器" "创建/完成接入，管理邀请、凭据、启停和移除"
            menuItem 9 "维护本机控制面" "查看 WireGuard 状态、凭据、地址和 Peer，或重启/关闭"
        else
            menuItem 8 "启用主控协同" "将本机初始化为主控，保留现有订阅状态和服务"
            menuItem 9 "接入主控" "粘贴主控邀请，将本机初始化为被控"
        fi
        menuReturnItem "${returnChoice}" "返回主菜单" "回到 padm 管理面板"
        menuClose
        menuReadChoice "${menuKey}" "请选择:" subscriptionCatalogStatus || return 0
        [[ "${subscriptionCatalogStatus}" != "${returnChoice}" ]] || return 0
        if [[ "${subscriptionCatalogStatus}" == "${publishServiceChoice}" ]]; then
            installSubscribe && showSubscriptionServiceStatus
            continue
        fi
        case "${subscriptionCatalogStatus}" in
        1) showPublishedSubscriptionLinks ;;
        2) manageSharedSubscriptions ;;
        3) manageTrafficAndQuota ;;
        4) return ;;
        6) syncAndShowSubscriptionLinks ;;
        7) manageSubscriptionSyncSettings ;;
        8)
            if [[ "${role}" == "main" ]]; then
                manageSubscriptionServers
            else
                runSubscriptionMainControllerWizard || true
                currentRole=$(subscriptionCurrentRoleNormalized 2>/dev/null) || return
                [[ "${currentRole}" != "${role}" ]] && return
            fi
            ;;
        9)
            if [[ "${role}" == "uninitialized" ]]; then
                runSubscriptionControlledWizard || true
                currentRole=$(subscriptionCurrentRoleNormalized 2>/dev/null) || return
                [[ "${currentRole}" != "${role}" ]] && return
            elif [[ "${role}" == "main" ]]; then
                manageSubscriptionMainControlDetails
            else
                coreSelectionErrorCard
            fi
            ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}

showUserSubscriptions() {
    local output
    local id
    local name
    local enabled
    local sources
    local limit
    local quota
    local enabledText
    local limitText
    local sourceText
    local quotaText
    local jqProgram
    local quotaStatusJq
    local itemIndex=0
    quotaStatusJq=$(subscriptionUserQuotaStatusJq) || return 1
    jqProgram=$(printf '%s\n%s\n%s\n' "$(subscriptionTrafficTotalsJq)" "${quotaStatusJq}" '
      . as $group |
      .user_groups[]? |
      "\(.id)\u001f\(.name)\u001f\(.enabled)\u001f\(.allowed_sources | join(","))\u001f\(.traffic_limit_gb)\u001f\(subscriptionUserQuotaStatus(.; subscriptionTrafficTotal(($group.traffic.user_groups[.id] // {}).sources); true))"')
    output=$(PADM_SUBSCRIPTION_GROUPS_LOCK_TIMEOUT=0 \
        subscriptionActiveGroupRead -r "${jqProgram}") || {
        errorCard "用户订阅读取失败"
        return 1
    }
    if [[ -z "${output}" ]]; then
        statusCard "用户订阅" "暂无用户订阅"
        return
    fi
    userResultCard "用户订阅列表"
    while IFS=$'\037' read -r id name enabled sources limit quota; do
        itemIndex=$((itemIndex + 1))
        if [[ "${name}" == "${id}" ]]; then
            menuLine "订阅 ${itemIndex}：$(uiStyle value "${id}")"
        else
            menuLine "订阅 ${itemIndex}：$(uiStyle value "${name}")（${id}）"
        fi
        if [[ "${enabled}" == "true" ]]; then
            enabledText=$(uiStyle ok "已启用")
        else
            enabledText=$(uiStyle warn "已停用")
        fi
        if [[ "${limit}" == "0" ]]; then
            limitText="不限额"
        else
            limitText="${limit} GB"
        fi
        case "${quota}" in
        已超限*) quotaText=$(uiStyle danger "${quota}") ;;
        接近上限*) quotaText=$(uiStyle warn "${quota}") ;;
        正常*) quotaText=$(uiStyle ok "${quota}") ;;
        *) quotaText=$(uiStyle muted "${quota}") ;;
        esac
        sourceText=${sources//,/、}
        [[ "${sourceText}" == "*" ]] && sourceText="全部"
        menuLine "状态：${enabledText} / 额度：$(uiStyle value "${limitText}") / 限额：${quotaText}"
        menuLine "服务器：$(uiStyle value "${sourceText}")"
    done <<<"${output}"
    menuClose
}

selectSubscriptionSourceId() {
    local sourcesJson=$1
    local prompt=$2
    local resultVar=$3
    local menuKey=${4:-subscription_source_select}
    local sourceRows
    local rowSourceId
    local sourceName
    local sourceHost
    local sourcePort
    local sourceEnabled
    local sourceStatus
    local sourceIndex=0
    local choice=
    local selected=
    local sourceCount

    [[ -n "${resultVar}" ]] || return 2
    printf -v "${resultVar}" '%s' ""
    sourceCount=$(jq 'length' <<<"${sourcesJson}") || return 1
    if [[ "${sourceCount}" == "0" ]]; then
        statusCard "暂无可选被控服务器"
        return 1
    fi

    sourceRows=$(jq -r '.[] | [.id, .name, .role, .host, (.port | tostring), (if .enabled == true then "启用" else "停用" end), (.sync_status // "pending")] | @tsv' <<<"${sourcesJson}") || return 1
    while IFS=$'\t' read -r rowSourceId sourceName _sourceRole sourceHost sourcePort sourceEnabled sourceStatus; do
        [[ -n "${rowSourceId}" ]] || continue
        sourceIndex=$((sourceIndex + 1))
        menuItem "${sourceIndex}" "${sourceName}（${rowSourceId}）" "${sourceHost}:${sourcePort} / ${sourceEnabled} / 同步：${sourceStatus}"
    done <<<"${sourceRows}"
    menuLine "输入编号或服务器 ID；纯数字 ID 使用 id:ID；直接回车返回"
    menuClose
    while true; do
        menuReadChoice "${menuKey}" "${prompt}" choice || return 1
        selected=$(jq -r --arg choice "${choice}" '
          if $choice | test("^[0-9]+$") then
            ($choice | tonumber) as $index |
            if $index >= 1 and $index <= length then .[$index - 1].id else empty end
          else first(.[]? | select(.id == ($choice | sub("^id:"; "")))).id // empty end
        ' <<<"${sourcesJson}") || return 1
        if [[ -n "${selected}" ]]; then
            printf -v "${resultVar}" '%s' "${selected}"
            return 0
        fi
        errorCard "服务器源选择无效，请输入列表编号或完整 ID"
    done
}

selectUserSubscriptionSources() {
    local menuKey=$1
    local prompt=$2
    local resultVar=$3
    local currentSources=${4:-'["main"]'}
    local currentLabel=${5:-}
    local changedVar=${6:-}
    local sourcesJson sourceRows sourceId sourceName sourceEnabled
    local sourceIndex=0
    local sourceChoice= resolvedSources=
    printf -v "${resultVar}" '%s' ""
    [[ -z "${changedVar}" ]] || printf -v "${changedVar}" '%s' false
    sourcesJson=$(subscriptionActiveGroupRead -c '.sources') || return 1
    sourceRows=$(jq -r '.[] | [.id, .name, (if .enabled then "启用" else "停用" end)] | @tsv' <<<"${sourcesJson}") || return 1
    userResultCard "选择节点范围"
    if [[ -n "${currentLabel}" ]]; then
        menuLine "当前范围：${currentLabel}"
    else
        menuLine "当前范围：$(jq -r 'join("、")' <<<"${currentSources}")"
    fi
    while IFS=$'\t' read -r sourceId sourceName sourceEnabled; do
        [[ -n "${sourceId}" ]] || continue
        sourceIndex=$((sourceIndex + 1))
        menuItem "${sourceIndex}" "${sourceName}（${sourceId}）" "${sourceEnabled}"
    done <<<"${sourceRows}"
    menuLine "*：全部服务器；可用逗号多选编号或 ID；纯数字 ID 使用 id:ID"
    menuClose
    while true; do
        menuReadChoice "${menuKey}" "${prompt}" sourceChoice true || return 1
        if [[ -z "${sourceChoice}" ]]; then
            printf -v "${resultVar}" '%s' "${currentSources}"
            [[ -z "${changedVar}" ]] || printf -v "${changedVar}" '%s' false
            return 0
        fi
        if resolvedSources=$(jq -cen --arg choice "${sourceChoice}" --argjson sources "${sourcesJson}" '
          $choice | split(",") | map(gsub("^\\s+|\\s+$"; "")) |
          map(. as $item |
            if . == "*" then .
            elif test("^[0-9]+$") then
              tonumber as $index |
              if $index >= 1 and $index <= ($sources | length) then $sources[$index - 1].id else null end
            else sub("^id:"; "") as $id |
              first($sources[] | select(.id == $id)).id // null end) |
          select(length > 0 and all(.[]; . != null)) |
          unique | if index("*") then ["*"] else . end
        '); then
            printf -v "${resultVar}" '%s' "${resolvedSources}"
            [[ -z "${changedVar}" ]] || printf -v "${changedVar}" '%s' true
            return 0
        fi
        errorCard "节点范围无效，请选择列表编号、服务器 ID 或 *"
    done
}

createAndSyncUserSubscriptionWizard() {
    local templateId=${1:-}
    local templateJson
    local id=
    local idsJson usersJson existingIds
    local sourceJson=
    local limit=0
    local syncResult=0
    local -a linkArgs=()
    createdUserSubscriptionId=
    createdUserSubscriptionIds='[]'
    while true; do
        menuReadChoice user_subscription_id "请输入分享订阅 ID[逗号分隔可批量新建，回车取消]:" id || return 1
        idsJson=$(jq -ecn --arg value "${id}" '
          $value | split(",") | map(gsub("^\\s+|\\s+$"; "")) |
          select(length > 0 and all(.[]; length <= 64 and test("^[A-Za-z0-9_-]+$"))) |
          select(length == (unique | length))
        ') || {
            errorCard "ID 不可为空或重复，每个 ID 最多 64 个字符，且只能包含英文、数字、下划线或短横线"
            continue
        }
        existingIds=$(subscriptionActiveGroupRead -c '[.user_groups[].id]') || {
            errorCard "用户订阅读取失败"
            return 1
        }
        if jq -e --argjson ids "${idsJson}" 'any(.[]; . as $id | ($ids | index($id)) != null)' <<<"${existingIds}" >/dev/null; then
            errorCard "分享订阅 ID 已存在，请使用其他 ID"
        else
            break
        fi
    done
    if [[ -n "${templateId}" ]]; then
        templateJson=$(subscriptionActiveGroupRead -ec --arg id "${templateId}" \
            'first(.user_groups[]? | select(.id == $id)) | select(. != null)') || {
            errorCard "复制模板订阅失败：原订阅不存在"
            return 1
        }
        sourceJson=$(jq -c '.allowed_sources' <<<"${templateJson}") || return 1
        limit=$(jq -r '.traffic_limit_gb' <<<"${templateJson}") || return 1
    else
        selectUserSubscriptionSources user_subscription_sources "请选择节点范围[回车默认 main]:" sourceJson || return 1
        while true; do
            menuReadChoice user_subscription_traffic_limit "请输入订阅额度 GB[回车/0 为不限]:" limit true || return 1
            limit=${limit:-0}
            [[ "${limit}" =~ ^[0-9]+$ ]] && break
            errorCard "订阅额度必须是数字"
        done
        limit=$(jq -nr --arg value "${limit}" '$value | tonumber') || return 1
    fi

    usersJson=$(jq -c 'map({id:.,name:.})' <<<"${idsJson}") || return 1
    if ! addUserSubscriptionsState "${usersJson}" "${sourceJson}" "${limit}"; then
        errorCard "分享订阅创建失败，订阅 ID 可能已存在或状态写入失败"
        return 1
    fi
    createdUserSubscriptionIds=${idsJson}
    id=$(jq -r 'join("、")' <<<"${idsJson}") || return 1
    if [[ "$(jq 'length' <<<"${idsJson}")" == "1" ]]; then
        createdUserSubscriptionId=$(jq -r '.[0]' <<<"${idsJson}") || return 1
        linkArgs=("${createdUserSubscriptionId}")
    else
        linkArgs=("" "${idsJson}")
    fi
    statusCard "分享订阅已创建" "订阅 ID：${id}" "服务器范围：$(jq -r 'join("、")' <<<"${sourceJson}")" "订阅额度 GB：${limit}" "正在立即同步；不改变后续自动同步设置"
    SUBSCRIPTION_SYNC_PUBLISHED=false
    if ! runSubscriptionGroupSync; then
        syncResult=1
        if [[ "${SUBSCRIPTION_SYNC_PUBLISHED:-false}" == "true" ]]; then
            warnCard "订阅已保存，首次同步部分失败但链接已发布" "可在该订阅详情查看已发布链接，无需重新创建"
        else
            warnCard "订阅已保存，但首次同步失败" "可在该订阅详情中重试同步并获取链接，无需重新创建"
        fi
    fi
    if [[ "${SUBSCRIPTION_SYNC_PUBLISHED:-false}" == "true" ]]; then
        showPublishedSubscriptionLinks "${linkArgs[@]}" || true
    elif [[ "${syncResult}" == "0" ]]; then
        statusCard "账号同步已完成，未发布订阅链接" "订阅已保存；请从订阅首页安装/更新发布服务后同步，无需重新创建"
    fi
    return "${syncResult}"
}

selectUserSubscriptionId() {
    local allowCreate=${1:-false}
    local allowMultiple=${2:-false}
    local id
    local name
    local enabled
    local limit
    local usage quota
    local displayJq
    local userRows
    local choice=
    local selected=
    local itemIndex=0
    local usersJson
    selectedUserSubscriptionId=
    selectedUserSubscriptionIds='[]'
    displayJq=$(printf '%s\n%s\n%s\n' "$(subscriptionTrafficTotalsJq)" \
        "$(subscriptionTrafficDisplayJq)" "$(subscriptionUserQuotaStatusJq)")
    usersJson=$(PADM_SUBSCRIPTION_GROUPS_LOCK_TIMEOUT=0 subscriptionActiveGroupRead -c "${displayJq}"'
      . as $group | .user_groups | map(
        . as $user |
        subscriptionTrafficTotal(($group.traffic.user_groups[.id] // {}).sources) as $traffic |
        . + {usage:subscriptionTrafficSize($traffic.upload + $traffic.download),
          quota_status:subscriptionUserQuotaStatus($user; $traffic; true)})
    ') || {
        errorCard "用户订阅读取失败"
        return 1
    }
    userRows=$(jq -r '.[]? | [.id, (.name // .id), (if .enabled == true then "启用" else "停用" end),
      (.traffic_limit_gb // 0 | tostring), .usage, .quota_status] | @tsv' <<<"${usersJson}") || return 1
    userResultCard "分享订阅"
    if [[ -z "${userRows}" ]]; then
        menuLine "暂无分享订阅"
        [[ "${allowCreate}" == "true" ]] || { menuClose; return 1; }
    fi
    while IFS=$'\t' read -r id name enabled limit usage quota; do
        [[ -n "${id}" ]] || continue
        itemIndex=$((itemIndex + 1))
        if [[ "${limit}" == "0" ]]; then
            limit="不限额"
        else
            limit="${limit} GB"
        fi
        menuItem "${itemIndex}" "${name}（${id}）" "状态：${enabled} / 已保存用量：${usage} / 额度：${limit} / ${quota}"
    done <<<"${userRows}"
    [[ "${allowCreate}" == "true" ]] && menuItem "+" "新建分享订阅" "创建后立即同步并进入详情"
    if [[ "${allowMultiple}" == "true" ]]; then
        menuLine "输入编号或订阅 ID；逗号分隔可多选，* 选择全部；纯数字 ID 使用 id:ID；直接回车返回"
    else
        menuLine "输入编号或订阅 ID；纯数字 ID 使用 id:ID；直接回车返回"
    fi
    menuClose
    while true; do
        menuReadChoice select_user_subscription_id "请选择订阅:" choice || return 1
        if [[ "${allowCreate}" == "true" && "${choice}" == "+" ]]; then
            selectedUserSubscriptionId=+
            selectedUserSubscriptionIds='[]'
            return 0
        fi
        if [[ "${allowMultiple}" == "true" && "${choice}" == "*" ]]; then
            selectedUserSubscriptionIds=$(jq -c '[.[].id]' <<<"${usersJson}") || return 1
            if [[ "${selectedUserSubscriptionIds}" == '[]' ]]; then
                errorCard "暂无可选分享订阅，请先新建"
                continue
            fi
            if [[ "$(jq 'length' <<<"${selectedUserSubscriptionIds}")" == "1" ]]; then
                selectedUserSubscriptionId=$(jq -r '.[0]' <<<"${selectedUserSubscriptionIds}")
                selectedUserSubscriptionIds='[]'
            fi
            return 0
        fi
        if [[ "${allowMultiple}" == "true" && "${choice}" == *","* ]]; then
            selectedUserSubscriptionIds=$(jq -c --arg choice "${choice}" '
              ($choice | split(",") | map(gsub("^\\s+|\\s+$"; ""))) as $items |
              if ($items | length) == 0 or any($items[]; . == "") then error("empty") else . end |
              [$items[] as $item |
                if $item | test("^[0-9]+$") then
                  ($item | tonumber) as $index |
                  if $index >= 1 and $index <= length then .[$index - 1].id else error("index") end
                else
                  ($item | sub("^id:"; "")) as $id |
                  first(.[]? | select(.id == $id)).id // error("id")
                end] | unique
            ' <<<"${usersJson}" 2>/dev/null) || {
                errorCard "用户订阅选择无效，请输入列表编号、完整 ID 或逗号多选"
                continue
            }
            if [[ "$(jq 'length' <<<"${selectedUserSubscriptionIds}")" == "1" ]]; then
                selectedUserSubscriptionId=$(jq -r '.[0]' <<<"${selectedUserSubscriptionIds}")
                selectedUserSubscriptionIds='[]'
            fi
            return 0
        fi
        selected=$(jq -r --arg choice "${choice}" '
          if $choice | test("^[0-9]+$") then
            ($choice | tonumber) as $index |
            if $index >= 1 and $index <= length then .[$index - 1].id else empty end
          else first(.[]? | select(.id == ($choice | sub("^id:"; "")))).id // empty end
        ' <<<"${usersJson}") || return 1
        if [[ -n "${selected}" ]]; then
            selectedUserSubscriptionId=${selected}
            selectedUserSubscriptionIds='[]'
            return 0
        fi
        errorCard "用户订阅选择无效，请输入列表编号或完整 ID"
    done
}

syncAndShowSubscriptionLinks() {
    local userSubscriptionId=${1:-}
    local idsJson=${2:-}
    local enabled
    if [[ -n "${idsJson}" ]]; then
        enabled=$(subscriptionActiveGroupRead -r --argjson ids "${idsJson}" '
          any(.user_groups[]?; .enabled == true and (.id as $id | $ids | index($id)) != null)
        ') || return 1
        if [[ "${enabled}" != "true" ]]; then
            warnCard "所选订阅均已停用或不存在" "启用后再同步获取链接"
            return 1
        fi
    elif [[ -n "${userSubscriptionId}" ]]; then
        enabled=$(subscriptionActiveGroupRead -r --arg id "${userSubscriptionId}" 'first(.user_groups[]? | select(.id == $id)).enabled // false') || return 1
        if [[ "${enabled}" != "true" ]]; then
            warnCard "该订阅已停用或不存在" "启用后再同步获取链接"
            return 1
        fi
    fi
    SUBSCRIPTION_SYNC_PUBLISHED=false
    if ! runSubscriptionGroupSync; then
        if [[ "${SUBSCRIPTION_SYNC_PUBLISHED:-false}" == "true" ]]; then
            warnCard "订阅同步部分失败，但本机已发布可用链接" "失败来源沿用旧快照；请到 订阅同步 -> 状态与排障 查看详情"
        else
            errorCard "订阅同步失败，未生成新的订阅链接" "修复同步问题后重试，或只读查看现有链接"
            return 1
        fi
    fi
    if [[ "${SUBSCRIPTION_SYNC_PUBLISHED:-false}" != "true" ]]; then
        statusCard "账号同步已完成，未发布订阅链接" "如需分享链接，请从订阅首页安装/更新发布服务，再执行立即完整同步"
        return 0
    fi
    if [[ -n "${idsJson}" ]]; then
        showPublishedSubscriptionLinks "" "${idsJson}"
    else
        showPublishedSubscriptionLinks "${userSubscriptionId}"
    fi
}

showPublishedSubscriptionLinks() {
    local userSubscriptionId=${1:-}
    local idsJson=${2:-}
    local enabled accountName salt accountHash domain publicBase format title
    local accounts= enabledUsers defaultFile
    local shown=false
    if [[ "${SUBSCRIPTION_GROUPS_LOCK_HELD:-}" != "1" ]]; then
        local SUBSCRIPTION_GROUPS_LOCK_SKIPPED=false
        local readStatus=0
        PADM_SUBSCRIPTION_GROUPS_LOCK_TIMEOUT=0 PADM_SUBSCRIPTION_GROUPS_LOCK_SKIP_BUSY=true \
            subscriptionGroupsWithLock showPublishedSubscriptionLinks "${userSubscriptionId}" "${idsJson}" || readStatus=$?
        if [[ "${SUBSCRIPTION_GROUPS_LOCK_SKIPPED}" == "true" ]]; then
            statusCard "订阅正在同步或修改" "请稍后重试查看已发布链接"
            return 1
        fi
        return "${readStatus}"
    fi
    if [[ -n "${idsJson}" ]]; then
        enabledUsers=$(subscriptionActiveEnabledUsersJson) || return 1
        accounts=$(jq -r --argjson ids "${idsJson}" '
          .[] | select(.id as $id | ($ids | index($id)) != null) | .account
        ' <<<"${enabledUsers}") || return 1
    elif [[ -n "${userSubscriptionId}" ]]; then
        # 同步中的额度处理可能停用订阅，统一在读取链接时复核。
        enabled=$(subscriptionActiveGroupRead -r --arg id "${userSubscriptionId}" \
            'first(.user_groups[]? | select(.id == $id)).enabled') || return 1
        if [[ "${enabled}" != "true" ]]; then
            warnCard "该订阅已停用或不存在" "检查流量和额度，启用后再同步获取链接"
            return 1
        fi
        accounts=$(subscriptionSyncAccountName "${userSubscriptionId}") || return 1
    else
        enabledUsers=$(subscriptionActiveEnabledUsersJson) || return 1
        # 本地旧输出可能仍有已停用或已删除的托管账号，不展示这些链接。
        for defaultFile in "$(subscribeLocalBaseDir)"/default/*; do
            [[ -f "${defaultFile}" ]] || continue
            accountName=${defaultFile##*/}
            [[ "${accountName}" == sub_* ]] && continue
            accounts+="${accountName}"$'\n'
        done
        accounts+=$(jq -r '.[].account' <<<"${enabledUsers}") || return 1
    fi
    subscribePort= subscribeDomain= subscribeType=
    readNginxSubscribe || { errorCard "订阅服务配置读取失败"; return 1; }
    domain=$(resolveSubscribePublicDomain)
    salt=$(readSubscribeSalt "$(subscribeLocalBaseDir)/subscribeSalt")
    if [[ -z "${domain}" || -z "${subscribeType}" || -z "${salt}" ]]; then
        statusCard "当前没有可用的已发布链接" "未配置发布服务时，请先从订阅首页安装/更新发布服务；已配置时，请执行立即完整同步"
        return 1
    fi
    if [[ -n "${subscribePort}" ]]; then
        domain+=":${subscribePort}"
    elif [[ -n "${currentDefaultPort:-}" && "${currentDefaultPort}" != "443" ]]; then
        domain+=":${currentDefaultPort}"
    fi
    publicBase=$(subscribePublicBaseDir)
    while IFS= read -r accountName; do
        [[ -n "${accountName}" ]] || continue
        accountHash=$(printf '%s\n' "${accountName}${salt}" | md5sum | awk '{print $1}') || return 1
        for format in default clashMetaProfiles sing-box; do
            [[ -s "${publicBase}/${format}/${accountHash}" ]] || continue
            case "${format}" in
            default) title="默认订阅" ;;
            clashMetaProfiles) title="Clash Meta 订阅" ;;
            sing-box) title="sing-box 订阅" ;;
            esac
            showSubscriptionUrlCard "${title}" "${accountName}" "${subscribeType}://${domain}/s/${format}/${accountHash}"
            shown=true
        done
    done <<<"${accounts}"
    [[ "${shown}" == "true" ]] && return 0
    statusCard "当前没有可用的已发布链接" "未配置发布服务时，请先从订阅首页安装/更新发布服务；已配置时，请执行立即完整同步"
    return 1
}

removeUserSubscriptionTransactionUnlocked() {
    local userSubscriptionId=$1
    local idsJson=${2:-}
    local expectedJson=${3:-}
    local previousGroupsState
    local manualCheckMessage
    local localTrafficBaseline=false
    local localTrafficReady=false
    if subscriptionLocalTrafficBaselineExists; then
        localTrafficBaseline=true
    fi
    SUBSCRIPTION_TRAFFIC_LOCAL_COMMITTED=false
    if collectSubscriptionTraffic >/dev/null 2>&1 || [[ "${SUBSCRIPTION_TRAFFIC_LOCAL_COMMITTED:-false}" == "true" ]]; then
        localTrafficReady=true
    fi
    if [[ "${localTrafficBaseline}" == "true" && "${localTrafficReady}" != "true" ]]; then
        errorCard "删除前本机流量采集失败，为避免丢失累计流量已取消删除"
        return 1
    fi
    previousGroupsState=$(subscriptionGroupsStateRead -c '.') || {
        subscriptionSyncSetManualCheckMessage manualCheckMessage "读取当前订阅状态失败" " $(subscriptionGroupsFile)"
        errorCard "${manualCheckMessage}"
        return 1
    }
    # 删除前采集流量可能更新状态，后置同步失败时必须回滚到这份最新快照。
    SUBSCRIPTION_USER_MUTATION_PREVIOUS_STATE_OVERRIDE=${previousGroupsState}
    if [[ -n "${idsJson}" ]]; then
        removeUserSubscriptionsState "${idsJson}" "${expectedJson}" || {
            errorCard "用户订阅状态删除失败"
            return 1
        }
    elif ! removeUserSubscriptionState "${userSubscriptionId}" "${expectedJson}"; then
        errorCard "用户订阅状态删除失败"
        return 1
    fi
}

removeUserSubscriptionMenu() {
    local userSubscriptionId=$1
    local idsJson=${2:-}
    local expectedJson=${3:-}
    local selectedLabel=${userSubscriptionId}
    local confirm=
    if [[ -n "${idsJson}" ]]; then
        selectedLabel=$(jq -r 'join("、")' <<<"${idsJson}") || return 1
    fi
    menuReadChoice remove_user_subscription_confirm "删除订阅 ${selectedLabel} 会移除状态；同步后会删除对应托管账号。确认请输入 yes：" confirm || return 1
    if [[ "${confirm}" != "yes" ]]; then
        coreCancelledStatusCard "操作未执行"
        return 1
    fi
    if subscriptionGroupsWithLock runUserSubscriptionMutationAndSyncUnlocked \
        "用户订阅删除" "" \
        removeUserSubscriptionTransactionUnlocked "${userSubscriptionId}" "${idsJson}" "${expectedJson}"; then
        successCard "用户订阅已删除"
        return 0
    fi
    return 1
}

editUserSubscriptionsMenu() {
    local idsJson=${1:-'[]'}
    local expectedJson
    local patchJson='{}'
    local effectiveJson
    local choice=
    local fieldChoices=
    local -a selectedFields=()
    local value=
    local currentSources
    local currentSourcesLabel
    local sourcesChanged=false
    local currentName
    local selectedCount
    local reload=
    local pendingFields
    local conflictingFields
    local editPrompt
    local prunePatchJq='
      def normalized($key): if $key == "allowed_sources" then sort else . end;
      with_entries(. as $field |
        select(any($expected[]; (.[$field.key] | normalized($field.key)) !=
          ($field.value | normalized($field.key)))))
    '
    local fieldLabelsJq='
      map(
        if . == "name" then "名称"
        elif . == "allowed_sources" then "节点范围"
        elif . == "traffic_limit_gb" then "订阅额度"
        elif . == "enabled" then "启用状态"
        else empty end
      ) | join("、")
    '
    selectedCount=$(jq -r 'length' <<<"${idsJson}" 2>/dev/null) || return 1
    [[ "${selectedCount}" -gt 0 ]] || return 1
    expectedJson=$(subscriptionActiveGroupRead -c --argjson ids "${idsJson}" '
      [.user_groups[]? | select(.id as $id | ($ids | index($id)) != null) |
        {id, uuid, name, enabled, allowed_sources, traffic_limit_gb}]
    ') || return 1
    [[ "$(jq 'length' <<<"${expectedJson}")" == "${selectedCount}" ]] || {
        errorCard "所选订阅已不存在，请重新选择"
        return 1
    }
    while true; do
        patchJson=$(jq -c --argjson expected "${expectedJson}" "${prunePatchJq}" <<<"${patchJson}") || return 1
        effectiveJson=$(jq -c --argjson patch "${patchJson}" 'map(. + $patch)' <<<"${expectedJson}") || return 1
        pendingFields=$(jq -r "keys | ${fieldLabelsJq}" <<<"${patchJson}") || return 1
        echoContent title "\n┌─ 编辑分享订阅 ─────────────────────────────────────"
        menuLine "已选订阅：${selectedCount} 个；修改会先保留为草稿，保存时一次性同步"
        if [[ -n "${pendingFields}" ]]; then
            menuLine "待保存字段：${pendingFields}"
        else
            menuLine "待保存字段：无"
        fi
        if [[ "${selectedCount}" == "1" ]]; then
            currentName=$(jq -r '.[0].name' <<<"${effectiveJson}")
            menuLine "当前名称：${currentName}"
            menuItem 1 "设置名称" "当前：${currentName}"
        else
            menuLine "批量编辑不会修改订阅名称"
        fi
        currentSources=$(jq -c '.[0].allowed_sources' <<<"${effectiveJson}") || return 1
        if [[ "$(jq -r 'map(.allowed_sources | tojson) | unique | length' <<<"${effectiveJson}")" == "1" ]]; then
            currentSourcesLabel="固定：$(jq -r '.[0].allowed_sources | join("、")' <<<"${effectiveJson}")"
        else
            currentSourcesLabel="多个值（回车保留各自设置）"
        fi
        menuLine "当前节点范围：${currentSourcesLabel}"
        menuLine "当前启用状态：$(jq -r 'map(.enabled) | unique |
          if length > 1 then "多个值" elif .[0] then "启用" else "停用" end' <<<"${effectiveJson}")"
        if [[ "$(jq -r 'map(.traffic_limit_gb) | unique | length' <<<"${effectiveJson}")" == "1" ]]; then
            menuLine "当前订阅额度：$(jq -r '.[0].traffic_limit_gb' <<<"${effectiveJson}") GB（0 表示不限）"
        else
            menuLine "当前订阅额度：多个值（回车保留各自设置）"
        fi
        menuItem 2 "设置节点范围" "批量订阅使用相同节点范围"
        menuItem 3 "设置订阅额度" "0 表示不限"
        menuItem 4 "启用所选订阅" "额度超限时会拒绝启用"
        menuItem 5 "停用所选订阅" "保存后同步移除对应托管账号"
        menuItem 6 "保存并立即同步" "不改变自动同步设置"
        menuReturnItem 7 "取消并丢弃草稿" "返回分享订阅"
        menuItem 8 "重新读取并丢弃草稿" "放弃当前草稿，读取最新状态"
        menuItem 9 "刷新并保留草稿" "读取最新状态；身份或草稿字段冲突时拒绝刷新"
        menuLine "字段可用逗号连续选择（例 2,3）；末尾加 6 填写后直接保存（例 2,3,6）；取消和重新读取单独选择"
        menuClose
        if [[ -n "${pendingFields}" ]]; then
            editPrompt="请选择[回车保存并立即同步]:"
        else
            editPrompt="请选择[回车返回]:"
        fi
        menuReadChoice edit_user_subscription_menu "${editPrompt}" choice true || return 1
        if [[ -z "${choice}" ]]; then
            [[ -n "${pendingFields}" ]] || return 0
            choice=6
        fi
        fieldChoices=$(jq -ern --arg choice "${choice}" --argjson count "${selectedCount}" '
          $choice | split(",") | map(gsub("^\\s+|\\s+$"; "")) |
          select(all(.[]; test("^[1-9]$"))) | map(tonumber) |
          select(length == (unique | length)) |
          select(length == 1 or all(.[]; . <= 5) or
            (.[-1] == 6 and all(.[:-1][]; . <= 5))) |
          select($count == 1 or index(1) == null) |
          select(index(4) == null or index(5) == null) | .[]
        ') || { coreSelectionErrorCard; continue; }
        mapfile -t selectedFields <<<"${fieldChoices}"
        for choice in "${selectedFields[@]}"; do
            case "${choice}" in
            1)
                value=
                menuReadChoice edit_user_subscription_name "请输入新名称[回车保留]:" value true || return 1
                [[ -n "${value}" ]] || continue
                patchJson=$(jq -c --arg value "${value}" '. + {name:$value}' <<<"${patchJson}") || return 1
                ;;
            2)
                value=
                sourcesChanged=false
                selectUserSubscriptionSources \
                    edit_user_subscription_sources \
                    "请选择节点范围[回车保留各自设置]:" \
                    value \
                    "${currentSources}" \
                    "${currentSourcesLabel}" \
                    sourcesChanged || return 1
                if [[ "${sourcesChanged}" == "true" ]]; then
                    patchJson=$(jq -c --argjson value "${value}" '. + {allowed_sources:$value}' <<<"${patchJson}") || return 1
                fi
                ;;
            3)
                while true; do
                    value=
                    menuReadChoice edit_user_subscription_limit "请输入订阅额度 GB[回车保留各自设置，0 为不限]:" value true || return 1
                    [[ -z "${value}" || "${value}" =~ ^[0-9]+$ ]] && break
                    errorCard "订阅额度必须是数字"
                done
                [[ -n "${value}" ]] || continue
                patchJson=$(jq -c --arg value "${value}" '. + {traffic_limit_gb:($value | tonumber)}' <<<"${patchJson}") || return 1
                ;;
            4)
                patchJson=$(jq -c '. + {enabled:true}' <<<"${patchJson}") || return 1
                ;;
            5)
                patchJson=$(jq -c '. + {enabled:false}' <<<"${patchJson}") || return 1
                ;;
            6)
                patchJson=$(jq -c --argjson expected "${expectedJson}" "${prunePatchJq}" <<<"${patchJson}") || return 1
                if [[ "${patchJson}" == '{}' ]]; then
                    statusCard "没有待保存的订阅变更"
                    return 0
                fi
                if subscriptionGroupsWithLock runUserSubscriptionMutationAndSyncUnlocked \
                    "分享订阅批量编辑" "分享订阅编辑失败" \
                    setUserSubscriptionsFields "${idsJson}" "${patchJson}" "${expectedJson}"; then
                    if jq -e '.enabled == true' <<<"${patchJson}" >/dev/null &&
                        ! subscriptionActiveGroupRead -e --argjson ids "${idsJson}" \
                            'all(.user_groups[] | select(.id as $id | ($ids | index($id)) != null); .enabled == true)' >/dev/null; then
                        warnCard "订阅已保存并同步，部分订阅被额度策略停用" "请提高额度或重置流量后再启用"
                    else
                        successCard "分享订阅已保存并同步"
                    fi
                    return 0
                fi
                warnCard "订阅编辑未完成" "草稿仍保留，可修正后重试；无关字段变化可选 9 刷新并保留草稿，同字段冲突请选 8 重读"
                ;;
            7)
                coreCancelledStatusCard "操作未执行"
                return 1
                ;;
            8 | 9)
                reload=$(subscriptionActiveGroupRead -c --argjson ids "${idsJson}" '
                  [.user_groups[]? | select(.id as $id | ($ids | index($id)) != null) |
                    {id, uuid, name, enabled, allowed_sources, traffic_limit_gb}]
                ') || continue
                [[ "$(jq 'length' <<<"${reload}")" == "${selectedCount}" ]] || {
                    errorCard "所选订阅已不存在，请重新选择"
                    return 1
                }
                if [[ "${choice}" == "9" ]]; then
                    jq -e --argjson expected "${expectedJson}" '
                      (map({id,uuid}) | sort_by(.id)) == ($expected | map({id,uuid}) | sort_by(.id))
                    ' <<<"${reload}" >/dev/null || {
                        errorCard "所选订阅身份已变化，无法保留草稿" "请选 8 重新读取并丢弃草稿"
                        continue
                    }
                    conflictingFields=$(jq -r --argjson expected "${expectedJson}" --argjson patch "${patchJson}" '
                      def normalized($key): if $key == "allowed_sources" then sort else . end;
                      . as $current |
                      [$patch | keys[] as $key |
                        select(any($expected[]; . as $before |
                          first($current[] | select(.id == $before.id)) as $after |
                          ($before[$key] | normalized($key)) != ($after[$key] | normalized($key)))) |
                        $key] | '"${fieldLabelsJq}" <<<"${reload}") || return 1
                    if [[ -n "${conflictingFields}" ]]; then
                        errorCard "草稿字段已被其他操作修改，未刷新" "冲突字段：${conflictingFields}" "请选 8 重新读取并丢弃草稿"
                        continue
                    fi
                    expectedJson=${reload}
                    statusCard "已刷新订阅状态，草稿仍保留" "请确认当前配置后保存"
                    continue
                fi
                expectedJson=${reload}
                patchJson='{}'
                statusCard "已重新读取订阅状态，草稿已丢弃"
                ;;
            *) coreSelectionErrorCard ;;
            esac
        done
    done
}

manageUserSubscriptionItem() {
    local userSubscriptionId=${1:-}
    local idsJson
    if [[ -z "${userSubscriptionId}" ]]; then
        selectUserSubscriptionId || return 0
        userSubscriptionId=${selectedUserSubscriptionId}
    fi
    idsJson=$(jq -cn --arg id "${userSubscriptionId}" '[$id]') || return 1
    manageUserSubscriptionsMenu "${idsJson}"
}

manageUserSubscriptionsMenu() {
    local idsJson=${1:-'[]'}
    local userSubscriptionItemStatus=
    local userSubscriptionId= usersJson summary line enabled targetEnabled selectedCount
    local selectedIds id hasChanges batchScope menuKey expectedFields
    local displayJq displayJson
    local -a linkArgs=()
    selectedCount=$(jq -er 'select(type == "array" and length > 0) | length' <<<"${idsJson}") || return 1
    displayJq=$(printf '%s\n%s\n%s\n' "$(subscriptionTrafficTotalsJq)" \
        "$(subscriptionTrafficDisplayJq)" "$(subscriptionUserQuotaStatusJq)")
    while true; do
        displayJson=$(PADM_SUBSCRIPTION_GROUPS_LOCK_TIMEOUT=0 subscriptionActiveGroupRead -c --argjson ids "${idsJson}" "${displayJq}"'
          . as $group |
          [.user_groups[]? | select(.id as $id | ($ids | index($id)) != null) |
            . as $user |
            subscriptionTrafficTotal(($group.traffic.user_groups[.id] // {}).sources) as $traffic |
            {id, uuid, name, enabled, allowed_sources, traffic_limit_gb,
              usage:subscriptionTrafficSize($traffic.upload + $traffic.download),
              quota_status:subscriptionUserQuotaStatus($user; $traffic; true)}]
        ') || { errorCard "当前订阅读取失败或已被删除"; return 1; }
        usersJson=$(jq -c 'map(del(.usage, .quota_status))' <<<"${displayJson}") || return 1
        [[ "$(jq 'length' <<<"${usersJson}")" == "${selectedCount}" ]] || {
            errorCard "所选订阅已不存在，请重新选择"
            return 1
        }
        selectedIds=$(jq -r '.[].id' <<<"${usersJson}") || return 1
        if [[ "${selectedCount}" == "1" ]]; then
            userSubscriptionId=${selectedIds}
            batchScope=
            menuKey=user_subscription_item_menu
            linkArgs=("${userSubscriptionId}")
        else
            userSubscriptionId=
            batchScope=${idsJson}
            menuKey=user_subscription_batch_menu
            linkArgs=("" "${idsJson}")
        fi
        summary=$(jq -r '
          .[] | "名称：\(.name // .id)（\(.id)） / 状态：\(if .enabled then "启用" else "停用" end)\n节点：\(.allowed_sources | join("、")) / 已保存用量：\(.usage) / 额度：\(if .traffic_limit_gb == 0 then "不限" else "\(.traffic_limit_gb) GB" end) / \(.quota_status)"
        ' <<<"${displayJson}") || return 1
        enabled=$(jq -r 'all(.[]; .enabled == true)' <<<"${usersJson}") || return 1
        [[ "${enabled}" == "true" ]] && targetEnabled=false || targetEnabled=true
        echoContent title "\n┌─ 管理分享订阅 ─────────────────────────────────────"
        if [[ "${selectedCount}" == "1" ]]; then
            menuLine "当前订阅：${userSubscriptionId}"
        else
            menuLine "已选订阅：${selectedCount} 个"
        fi
        while IFS= read -r line; do menuLine "${line}"; done <<<"${summary}"
        menuItem 1 "查看当前已发布链接" "只读查看，不等待同步或重建订阅"
        menuItem 2 "查看当前流量" "只读查看累计流量和额度状态"
        menuItem 3 "编辑订阅配置" "名称、节点范围、额度和启停一次保存并同步"
        menuItem 4 "立即同步并更新链接" "同步后查看当前链接，不改变自动同步设置"
        if [[ "${selectedCount}" != "1" ]]; then
            menuItem 5 "启用所选订阅" "整批启用并同步，任一订阅超限则不写入"
            menuItem 10 "停用所选订阅" "整批停用并同步移除对应托管账号"
        elif [[ "${targetEnabled}" == "true" ]]; then
            menuItem 5 "启用当前订阅" "启用后立即同步，额度超限时会拒绝启用"
        else
            menuItem 5 "停用当前订阅" "停用后立即同步并移除对应托管账号"
        fi
        menuDangerItem 6 "删除订阅" "删除记录；同步后移除对应托管账号"
        menuReturnItem 7 "返回订阅列表" "回到分享订阅"
        menuItem 8 "切换订阅" "选择另一订阅继续管理"
        if [[ "${selectedCount}" == "1" ]]; then
            menuItem 9 "按当前配置新建订阅" "复制节点范围和额度，不复制身份、流量和令牌"
        fi
        menuClose
        menuReadChoice "${menuKey}" "请选择:" userSubscriptionItemStatus || return 0
        case "${userSubscriptionItemStatus}" in
        1) showPublishedSubscriptionLinks "${linkArgs[@]}" ;;
        2)
            while IFS= read -r id; do showUserSubscriptionTraffic "${id}"; done <<<"${selectedIds}"
            ;;
        3) editUserSubscriptionsMenu "${idsJson}" || true ;;
        4) syncAndShowSubscriptionLinks "${linkArgs[@]}" ;;
        5 | 10)
            if [[ "${selectedCount}" != "1" ]]; then
                [[ "${userSubscriptionItemStatus}" == "5" ]] && targetEnabled=true || targetEnabled=false
            elif [[ "${userSubscriptionItemStatus}" == "10" ]]; then
                coreSelectionErrorCard
                continue
            fi
            hasChanges=$(jq -r --argjson target "${targetEnabled}" 'any(.[]; .enabled != $target)' <<<"${usersJson}") || continue
            if [[ "${hasChanges}" != "true" ]]; then
                statusCard "所选订阅状态未变化"
                continue
            fi
            expectedFields=${usersJson}
            if subscriptionGroupsWithLock runUserSubscriptionMutationAndSyncUnlocked \
                "用户订阅状态更新" "用户订阅状态更新失败" \
                setUserSubscriptionsFields "${idsJson}" "{\"enabled\":${targetEnabled}}" "${expectedFields}"; then
                enabled=$(subscriptionActiveGroupRead -r --argjson ids "${idsJson}" '
                  [.user_groups[] | select(.id as $id | ($ids | index($id)) != null)] |
                  length == ($ids | length) and all(.[]; .enabled == true)
                ') || continue
                if [[ "${targetEnabled}" == "true" && "${enabled}" == "true" ]]; then
                    successCard "用户订阅已启用"
                elif [[ "${targetEnabled}" == "false" ]]; then
                    statusCard "用户订阅当前已停用"
                else
                    statusCard "用户订阅当前已停用" "如刚执行启用，请检查自动额度策略和当前累计流量"
                fi
            fi
            ;;
        6)
            removeUserSubscriptionMenu "${userSubscriptionId}" "${batchScope}" "${usersJson}" && return
            ;;
        7) return ;;
        8)
            if selectUserSubscriptionId false true; then
                idsJson=${selectedUserSubscriptionIds}
                if [[ "${idsJson}" == '[]' ]]; then
                    idsJson=$(jq -cn --arg id "${selectedUserSubscriptionId}" '[$id]') || return 1
                fi
                selectedCount=$(jq 'length' <<<"${idsJson}") || return 1
            fi
            ;;
        9)
            if [[ "${selectedCount}" != "1" ]]; then
                coreSelectionErrorCard
                continue
            fi
            createAndSyncUserSubscriptionWizard "${userSubscriptionId}" || true
            if [[ "${createdUserSubscriptionIds:-'[]'}" != '[]' ]]; then
                idsJson=${createdUserSubscriptionIds}
                selectedCount=$(jq 'length' <<<"${idsJson}") || return 1
            fi
            ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}

# 添加服务器源
createSubscriptionWireGuardInviteMenu() {
    local alias= inviteCredential=
    echoContent title "\n┌─ 创建被控邀请 ─────────────────────────────────────"
    menuLine "主控将自动预留别名和 WireGuard 地址；邀请只在本次结果中显示。"
    menuClose
    autoRead subscription_invite_alias "请输入被控服务器别名[英文/数字/短横线，例 hk-1，回车取消]:" alias || return 1
    [[ -n "${alias}" ]] || return 1
    statusCard "正在创建被控邀请" "正在检查别名并预留地址；若有同步任务运行，将等待它完成"
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
    local pendingJson inviteRows alias address expiresAt remainingSeconds statusText inviteId confirmCancel=
    while true; do
        pendingJson=$(subscriptionWireGuardListPendingInvites true) || return 1
        echoContent title "\n┌─ 待完成邀请 ───────────────────────────────────────"
        inviteRows=$(jq -r '
          .[] |
          [
            .alias,
            .address,
            (.expires_at | tostring),
            (.remaining_seconds | tonumber),
            (if (.remaining_seconds | tonumber) <= 0 then "接入未完成且已过期"
             elif .status == "incomplete" then "接入未完成"
             else "待接入" end)
          ] | @tsv
        ' <<<"${pendingJson}") || return 1
        if [[ -z "${inviteRows}" ]]; then
            menuLine "当前没有待完成邀请。"
            menuClose
            return 0
        fi
        while IFS=$'\t' read -r alias address expiresAt remainingSeconds statusText; do
            menuLine "别名：${alias}；地址：${address}；过期：$(subscriptionWireGuardInviteLocalTime "${expiresAt}")；剩余：$(subscriptionWireGuardInviteRemainingText "${remainingSeconds}")；状态：${statusText}"
        done <<<"${inviteRows}"
        menuClose
        while true; do
            autoRead subscription_cancel_invite_alias "输入要取消的唯一别名[直接回车返回]:" alias || return 0
            [[ -n "${alias}" ]] || return 0
            inviteId=$(jq -r --arg alias "${alias}" 'first(.[]? | select(.alias == $alias)).invite_id // empty' <<<"${pendingJson}") || return 1
            [[ -z "${inviteId}" ]] || break
            errorCard "待完成邀请别名无效，请重新输入"
        done
        warnCard "取消邀请" "若接入曾中断，将同时清理该别名的部分 Peer、来源和凭据"
        menuReadChoice subscription_cancel_invite_confirm "确认取消 ${alias}？[y/N]:" confirmCancel true || return 0
        [[ "$(normalizeYesNo "${confirmCancel}")" == "y" ]] || { statusCard "已保留待完成邀请"; continue; }
        subscriptionWireGuardCancelInvite "${alias}" "${inviteId}" || return 1
        successCard "待完成邀请已取消" "已释放别名和预留地址：${alias}"
    done
}

removeSubscriptionControlledServerMenu() {
    subscriptionRequireMainRole || return 1
    local sourceId=${1:-}
    local expectedSource=${2:-} expectedPeer=${3:-}
    local sourcesJson source confirm=
    local localOnlyConfirm=
    echoContent title "\n┌─ 移除被控服务器 ───────────────────────────────────"
    menuLine "删除前会自动清理用户订阅中的该来源；使用 * 的订阅范围会保留。"
    sourcesJson=$(subscriptionActiveGroupRead -c '[.sources[]? | select(.role != "main")]') || return 1
    if [[ -z "${sourceId}" ]]; then
        selectSubscriptionSourceId "${sourcesJson}" "请选择要删除的被控服务器:" sourceId delete_subscription_source || return 1
    fi
    source=$(jq -ce --arg id "${sourceId}" 'first(.[]? | select(.id == $id))' <<<"${sourcesJson}") || {
        errorCard "被控服务器源已不存在，请刷新后重试"
        return 1
    }
    expectedSource=${expectedSource:-${source}}
    menuReadChoice delete_subscription_source_confirm \
        "确认移除 ${sourceId} 及对应 WireGuard Peer？请输入 yes:" confirm true || return 1
    [[ "${confirm}" == "yes" ]] || { coreCancelledStatusCard "服务器源未移除"; return 0; }
    if ! subscriptionWireGuardRemovePeerAndSource "${sourceId}" "${expectedSource}" "${expectedPeer}"; then
        if [[ "${SUBSCRIPTION_WIREGUARD_SOURCE_REMOVE_ERROR:-}" == "remote" ]]; then
            warnCard "远端服务器不可达或清理失败" "仅本地移除会删除本机来源和 WireGuard Peer，但不会删除远端账号；请在远端手工清理后再确认"
            menuReadChoice subscription_source_local_remove_confirm \
                "确认仅本地移除 ${sourceId}？[y/N]:" localOnlyConfirm true || return 1
            if [[ "$(normalizeYesNo "${localOnlyConfirm}")" == "y" ]]; then
                if subscriptionWireGuardRemovePeerAndSourceLocalOnly "${sourceId}" "${expectedSource}" "${expectedPeer}"; then
                    if runSubscriptionSyncAfterMutation "被控服务器仅本地移除" "" true; then
                        successCard "被控服务器已仅本地移除" "本机来源和 WireGuard Peer 已移除" "远端账号未清理，请手工处理"
                        return 0
                    fi
                    return 1
                fi
                errorCard "被控服务器仅本地移除失败"
                return 1
            fi
        fi
        errorCard "被控服务器删除失败"
        return 1
    fi
    if runSubscriptionSyncAfterMutation "被控服务器删除" "" true; then
        successCard "被控服务器删除成功" "服务器源和 WireGuard Peer 已移除"
        return 0
    fi
    return 1
}

changeSubscriptionSourceEnabledMenu() {
    subscriptionRequireMainRole || return 1
    local sourceId=${1:-}
    local expectedSource=${2:-}
    local source=
    local enabled=
    local targetEnabled=${3:-}
    local actionText=
    local effectText=
    local confirm=
    local sourcesJson sourceName

    userResultCard "被控服务器启用状态"
    sourcesJson=$(subscriptionActiveGroupRead -c '[.sources[]? | select(.role != "main")]') || return 1
    if [[ -z "${sourceId}" ]]; then
        selectSubscriptionSourceId "${sourcesJson}" "请选择要启用或停用的被控服务器:" sourceId subscription_source_enabled_id || return 1
    fi
    source=$(jq -c --arg id "${sourceId}" 'first(.[]? | select(.id == $id))' <<<"${sourcesJson}") || return 1
    if [[ -z "${source}" || "${source}" == "null" ]]; then
        errorCard "被控服务器源已不存在，请刷新后重试"
        return 1
    fi
    expectedSource=${expectedSource:-${source}}
    enabled=$(jq -r '.enabled == true' <<<"${expectedSource}") || return 1
    sourceName=$(jq -r '.name' <<<"${source}") || return 1
    if [[ -z "${targetEnabled}" ]]; then
        [[ "${enabled}" == "true" ]] && targetEnabled=false || targetEnabled=true
    fi
    [[ "${targetEnabled}" == "true" || "${targetEnabled}" == "false" ]] || return 1
    if [[ "${targetEnabled}" == "${enabled}" ]]; then
        statusCard "被控服务器状态未变化"
        return 0
    fi
    if [[ "${targetEnabled}" == "false" ]]; then
        actionText="停用"
        effectText="清理远端托管账号后停用并立即同步；保留 Peer、Token 和历史状态"
    else
        actionText="启用"
        effectText="启用后立即同步并更新公网发布；保留 Peer、Token 和历史状态"
    fi
    warnCard "${actionText}被控服务器" "目标：${sourceId}（${sourceName}）" "${effectText}"
    menuReadChoice subscription_source_enabled_confirm "确认${actionText} ${sourceId}？[y/N]:" confirm true || return 1
    [[ "$(normalizeYesNo "${confirm}")" == "y" ]] || { coreCancelledStatusCard "服务器源状态未修改"; return 0; }
    if ! setSubscriptionRemoteSourceEnabled "${sourceId}" "${targetEnabled}" "${expectedSource}"; then
        errorCard "${SUBSCRIPTION_REMOTE_SOURCE_MUTATION_ERROR:-被控服务器状态更新失败}"
        return 1
    fi
    successCard "被控服务器已${actionText}" "来源：${sourceId}"
    runSubscriptionSyncAfterMutation "被控服务器${actionText}" "" true
}

manageSubscriptionServers() {
    subscriptionRequireMainRole || return 1
    local serverStatus= completedSourceId=
    while true; do
        echoContent title "\n┌─ 被控服务器 ───────────────────────────────────────"
        menuLine "待接入服务器使用邀请和回执；已有服务器选择一次即可连续维护。"
        menuItem 1 "创建被控邀请" "输入一次别名，自动预留 WireGuard 地址"
        menuItem 2 "完成被控接入" "粘贴接入回执，自动使用预留别名和地址"
        menuItem 3 "查看/取消待完成邀请" "按别名查看状态或释放预留地址"
        menuItem 4 "管理已有被控服务器" "状态、凭据、启停、连接检查和移除"
        menuItem 8 "查看服务器总览" "只读查看所有来源的状态"
        menuReturnItem 7 "返回主控首页" "回到上级菜单"
        menuClose
        menuReadChoice server_source_menu "请选择:" serverStatus || return 0
        case "${serverStatus}" in
        1) createSubscriptionWireGuardInviteMenu ;;
        2)
            addOtherSubscribe completedSourceId || true
            [[ -z "${completedSourceId}" ]] || manageSubscriptionServerItem "${completedSourceId}"
            ;;
        3) manageSubscriptionPendingInvites ;;
        4) manageSubscriptionServerItem ;;
        # 保留旧动作编号，已有输入仍经过目标选择和确认。
        5) changeSubscriptionSourceEnabledMenu ;;
        6) removeSubscriptionControlledServerMenu ;;
        7) return ;;
        8) showSubscriptionSources ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}

manageSubscriptionServerItem() {
    subscriptionRequireMainRole || return 1
    local sourceId=${1:-}
    local sourcesJson source peerState expectedPeer summary targetEnabled line health healthStatus healthCode
    local choice= idExists chosenId=
    if [[ -z "${sourceId}" ]]; then
        sourcesJson=$(subscriptionActiveGroupRead -c '[.sources[]? | select(.role != "main")]') || return 1
        selectSubscriptionSourceId "${sourcesJson}" "请选择要管理的被控服务器:" sourceId || return 0
    fi
    while true; do
        source=$(PADM_SUBSCRIPTION_GROUPS_LOCK_TIMEOUT=0 subscriptionActiveGroupRead -ce --arg id "${sourceId}" \
            'first(.sources[]? | select(.id == $id and .role != "main"))') || {
            errorCard "被控服务器读取失败或已被移除"
            return 1
        }
        peerState=$(subscriptionWireGuardReadState) || return 1
        expectedPeer=$(jq -c --arg id "${sourceId}" \
            'first(.peers[]? | select(.id == $id) | {id,address,public_key}) // null' <<<"${peerState}") || return 1
        summary=$(jq -r '
          "名称：\(.name)（\(.id)） / 状态：\(if .enabled then "启用" else "停用" end)\n地址：\(.host):\(.port) / 同步：\(.sync_status // "pending")"
        ' <<<"${source}") || return 1
        targetEnabled=$(jq -r '.enabled != true' <<<"${source}") || return 1
        echoContent title "\n┌─ 管理被控服务器 ───────────────────────────────────"
        while IFS= read -r line; do menuLine "${line}"; done <<<"${summary}"
        menuItem 1 "更新当前服务器凭据" "更新地址、公钥、控制端口和 Token"
        if [[ "${targetEnabled}" == "true" ]]; then
            menuItem 2 "启用当前服务器并同步" "保留现有凭据"
        else
            menuItem 2 "停用当前服务器并同步" "清理远端托管账号，保留 Peer、Token 和历史状态"
        fi
        menuItem 3 "检查当前服务器连接" "只请求当前服务器的 Health"
        menuItem 4 "立即完整同步" "更新本机、所有启用来源和已配置的订阅发布"
        menuItem 5 "刷新当前状态" "重新读取已保存的服务器状态"
        menuDangerItem 6 "移除当前服务器" "清理远端托管账号并移除来源和 Peer"
        menuReturnItem 7 "返回服务器列表" "回到被控服务器"
        menuItem 8 "切换服务器" "选择另一服务器继续维护"
        menuClose
        menuReadChoice subscription_server_item_menu "请选择:" choice || return 0
        case "${choice}" in
        1) setSubscriptionSourceControlTokenMenu "${sourceId}" "${source}" "${expectedPeer}" || true ;;
        2) changeSubscriptionSourceEnabledMenu "${sourceId}" "${source}" "${targetEnabled}" || true ;;
        3)
            statusCard "被控服务器连接检查" "正在检查 ${sourceId}，最长等待 15 秒"
            if health=$(subscriptionRemoteControlHealth "${source}"); then
                if jq -e '.ok == true' <<<"${health}" >/dev/null 2>&1; then
                    successCard "被控服务器连接正常" "来源：${sourceId}"
                else
                    healthStatus=$(jq -r '.status // .error_detail.type // "unknown"' <<<"${health}" 2>/dev/null) || healthStatus=unknown
                    healthCode=$(jq -r '(.status_code // "" | tostring) as $code |
                      if ($code | test("^[1-5][0-9]{2}$")) then "HTTP " + $code else empty end' <<<"${health}" 2>/dev/null) || healthCode=
                    case "${healthStatus}" in
                    missing_token) healthStatus="未配置控制 Token" ;;
                    unauthorized) healthStatus="控制 Token 验证失败" ;;
                    unreachable) healthStatus="远端服务器不可达" ;;
                    remote_error) healthStatus="远端控制接口返回错误" ;;
                    invalid_response) healthStatus="远端响应格式无效" ;;
                    *) healthStatus="连接检查未通过" ;;
                    esac
                    errorCard "被控服务器连接检查失败" "来源：${sourceId}" "原因：${healthStatus}${healthCode:+（${healthCode}）}"
                fi
            else
                errorCard "被控服务器连接检查失败" "来源：${sourceId}"
            fi
            ;;
        4) runSubscriptionGroupSync || true ;;
        5) continue ;;
        6)
            removeSubscriptionControlledServerMenu "${sourceId}" "${source}" "${expectedPeer}" || true
            idExists=$(subscriptionActiveGroupRead -r --arg id "${sourceId}" \
                'any(.sources[]?; .id == $id and .role != "main")') || return 1
            [[ "${idExists}" == "true" ]] || return 0
            ;;
        7) return 0 ;;
        8)
            sourcesJson=$(subscriptionActiveGroupRead -c '[.sources[]? | select(.role != "main")]') || continue
            if selectSubscriptionSourceId "${sourcesJson}" "请选择要管理的被控服务器:" chosenId; then
                sourceId=${chosenId}
            fi
            ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}

# 添加被控服务器
addOtherSubscribe() {
    local resultVar=${1:-}
    local credentialJson=
    local completedAlias=
    [[ -z "${resultVar}" ]] || printf -v "${resultVar}" '%s' ""
    echoContent title "\n┌─ 完成被控接入 ─────────────────────────────────────"
    menuLine "粘贴接入回执，自动使用创建邀请时预留的别名和地址。"
    menuClose
    subscriptionWireGuardReadCredential receipt "接入回执" credentialJson || return 1
    subscriptionWireGuardCompleteInvite "${credentialJson}" completedAlias || return 1
    [[ -z "${resultVar}" ]] || printf -v "${resultVar}" '%s' "${completedAlias}"
    successCard "被控接入已完成" "别名：${completedAlias}" "Peer、服务器源和 Token 已保存；可在该服务器详情检查连接和重试同步"
    runSubscriptionSyncAfterMutation "被控服务器接入" "" true
}






subscriptionSourceSyncSummaryJq() {
    cat <<'EOF'
(if has("last_sync_changed") then "\n上次同步变更:" + (if .last_sync_changed then "是" else "否" end) else "" end) +
(if .last_sync_plan? then "\n上次同步计划: 创建\((.last_sync_plan.create // []) | length)，删除\((.last_sync_plan.remove // []) | length)" else "" end) +
(if .last_sync_error? then "\n上次同步错误:\(.last_sync_error.type) \(.last_sync_error.message)" else "" end) +
(if ((.sync_failure_count // 0) | tonumber? // 0) > 0 then
    "\n连续失败次数:\(((.sync_failure_count // 0) | tonumber? // 0))"
  else "" end) +
(((.sync_circuit_open_until // 0) | tonumber? // 0) as $cooldownUntil |
  if $cooldownUntil > (now | floor) then
    "\n冷却状态:冷却中（剩余 \($cooldownUntil - (now | floor)) 秒）"
  elif $cooldownUntil > 0 then
    "\n冷却状态:可重试"
  else "" end)
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
    output=$(PADM_SUBSCRIPTION_GROUPS_LOCK_TIMEOUT=0 \
        subscriptionActiveGroupRead -r "
      .sources[]? |
      ${sourceFilter} |
      \"ID:\\(.id)\\n名称:\\(.name)\\n角色:\\(.role)\\n地址:\\(.scheme)://\\(.host):\\(.port)\\n启用:\\(.enabled)\\n同步状态:\\(.sync_status)\" +
      ${syncSummary} +
      \"\\n---\"") || return 1
    printf '%s\n' "${output}"
}

showSubscriptionSourceControlUrls() {
    local output
    output=$(PADM_SUBSCRIPTION_GROUPS_LOCK_TIMEOUT=0 \
        subscriptionActiveGroupRead -r '
      .sources[]? | select(.role != "main") |
      "ID:\(.id)\n名称:\(.name)\n控制面:WireGuard\n内网地址:\(.host):\(.port)\nHealth:http://\(.host):\(.port)/s/control/health\nSync:http://\(.host):\(.port)/s/control/sync\n---"'
    ) || return 1
    printf '%s\n' "${output}"
}

setSubscriptionSourceControlTokenMenu() {
    subscriptionRequireMainRole || return 1
    local sourceId=${1:-}
    local expectedSource=${2:-} expectedPeer=${3:-}
    local credentialJson=
    local host=
    local port=
    local matchCount=0
    local sourcesJson=
    local sourceOutput=
    local source=
    echoContent title "\n┌─ 更新被控服务器凭据 ───────────────────────────────"
    menuLine "这里更新一个被控服务器的接入凭据。"
    menuLine "仅用于更新已有被控连接；首次接入请使用邀请和回执。系统会更新地址、端口和 Token。"
    [[ -z "${sourceId}" ]] || menuLine "当前目标：${sourceId}"
    menuClose
    subscriptionWireGuardReadCredential controlled "被控接入凭据" credentialJson || return 1
    subscriptionWireGuardValidateControlledCredentialJson "${credentialJson}" || {
        errorCard "被控接入凭据字段不完整或格式无效"
        return 1
    }
    host=$(subscriptionWireGuardAddressHost "$(jq -r '.address' <<<"${credentialJson}")")
    port=$(jq -r '.control_port' <<<"${credentialJson}")
    sourcesJson=$(subscriptionActiveGroupRead -c '[.sources[]? | select(.role != "main")]') || return 1
    if [[ -z "${sourceId}" ]]; then
        matchCount=$(jq -r --arg host "${host}" --argjson port "${port}" \
            '[.[]? | select(.host == $host and .port == $port)] | length' <<<"${sourcesJson}") || return 1
        if [[ "${matchCount}" == "1" ]]; then
            sourceId=$(jq -r --arg host "${host}" --argjson port "${port}" \
                'first(.[]? | select(.host == $host and .port == $port)).id' <<<"${sourcesJson}") || return 1
        else
            selectSubscriptionSourceId "${sourcesJson}" "请选择要更新凭据的被控服务器:" sourceId subscription_source_id || return 1
        fi
    fi
    source=$(jq -c --arg id "${sourceId}" 'first(.[]? | select(.id == $id))' <<<"${sourcesJson}") || return 1
    if [[ -z "${source}" || "${source}" == "null" ]]; then
        errorCard "被控服务器源已不存在，请刷新后重试"
        return 1
    fi
    expectedSource=${expectedSource:-${source}}
    subscriptionWireGuardUpdatePeerAndCredential "${sourceId}" "${credentialJson}" "${expectedSource}" "${expectedPeer}" || {
        errorCard "被控服务器凭据更新失败"
        return 1
    }
    successCard "被控服务器凭据已更新" "内网地址：${host}:${port}" "别名：${sourceId}" "Peer 公钥和 Token 已保存，可继续测试被控连接"
    runSubscriptionSyncAfterMutation "被控服务器凭据更新" "" true
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
    if [[ "${SUBSCRIPTION_GROUPS_LOCK_HELD:-}" != "1" ]]; then
        subscriptionGroupsWithLock setSubscriptionGroupSyncValueWithCron "$@"
        return $?
    fi
    local value=$1 query=$2 setterFn=$3 valueRestoreError=$4 cronRestoreError=$5
    local expectedValue=${6:-}
    local previousValue
    previousValue=$(subscriptionActiveGroupRead -r "${query}") || return 1
    if [[ -n "${expectedValue}" ]]; then
        if [[ "${previousValue}" != "${expectedValue}" ]]; then
            errorCard "同步设置已变化，请重新读取后重试"
            return 2
        fi
        [[ "${value}" != "${previousValue}" ]] || return 0
    fi
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
        "自动同步定时任务更新失败，且原状态恢复失败" "自动同步状态已恢复，但原定时任务恢复失败" "${2:-}"
}

setSubscriptionGroupSyncIntervalWithCron() {
    setSubscriptionGroupSyncValueWithCron "$1" '.sync.interval_minutes' setSubscriptionGroupSyncInterval \
        "自动同步定时任务更新失败，且原间隔恢复失败" "自动同步间隔已恢复，但原定时任务恢复失败" "${2:-}"
}

manageSubscriptionSyncDiagnostics() {
    local role
    local diagnosticStatus=
    local returnChoice=5
    local roleAction=cron
    role=$(subscriptionCurrentRoleNormalized) || return 1
    [[ "${role}" == "main" || "${role}" == "uninitialized" ]] || return 1
    if [[ "${role}" == "main" ]]; then
        returnChoice=8
        roleAction=remote
    fi
    while true; do
        echoContent title "\n┌─ 同步状态与排障 ───────────────────────────────────"
        menuItem 1 "查看最近同步结果与失败列表" "显示组状态和各来源最近同步结果"
        menuItem 2 "检查本机服务与发布状态" "显示服务器角色和公网订阅服务状态"
        menuItem 3 "查看本机同步计划" "预览本机 create/remove"
        if [[ "${roleAction}" == "remote" ]]; then
            menuItem 4 "查看远端同步计划" "对启用来源执行 dry-run"
            menuItem 5 "检查被控服务器健康" "请求所有启用的被控服务器健康检查"
            menuItem 6 "查看自动同步定时任务" "显示当前 SyncSubscriptionGroups cron"
            menuItem 7 "强制立即重试" "临时跳过来源冷却并完整同步，不修改失败计数"
        else
            menuItem 4 "查看自动同步定时任务" "显示当前 SyncSubscriptionGroups cron"
        fi
        menuReturnItem "${returnChoice}" "返回订阅同步" "回到上级菜单"
        menuClose
        menuReadChoice subscription_sync_diagnostics_menu "请选择:" diagnosticStatus || return 0
        case "${diagnosticStatus}" in
        1) showSubscriptionGroupsStateSummary; showSubscriptionSources ;;
        2) showSubscriptionServerRoleSummary; showSubscriptionServiceStatus ;;
        3) showSubscriptionLocalSyncPlan ;;
        4)
            if [[ "${roleAction}" == "remote" ]]; then
                showSubscriptionRemoteSyncPlan
            else
                crontab -l 2>/dev/null | grep 'SyncSubscriptionGroups' || true
            fi
            ;;
        "${returnChoice}") return ;;
        5)
            if [[ "${roleAction}" == "remote" ]]; then
                showSubscriptionRemoteHealthPlan
            else
                crontab -l 2>/dev/null | grep 'SyncSubscriptionGroups' || true
            fi
            ;;
        6) crontab -l 2>/dev/null | grep 'SyncSubscriptionGroups' || true ;;
        7) runSubscriptionGroupSyncForceRetry || true ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}

manageSubscriptionSyncSettings() {
    local role
    local syncStatus
    local enabledText
    local returnText
    local syncSettingsStatus=
    local targetSyncEnabled
    local expectedSyncEnabled
    local expectedInterval
    local interval=
    local defaultInterval
    local lastStatus lastRun failureCount summary
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
        defaultInterval=$(subscriptionGroupSyncDefaultInterval) || return 1
        syncStatus=$(subscriptionActiveGroupRead --argjson defaultInterval "${defaultInterval}" -c '{enabled:(.sync.enabled == true), interval_minutes:(.sync.interval_minutes // $defaultInterval), last_run:(.sync.last_run // ""), last_status:(.sync.last_status // "pending"), failure_count:((.sync.failures // []) | length)}') || return 1
        summary=$(jq -r '[if .enabled then "开启" else "关闭" end, (.interval_minutes | tostring), .last_status, (if .last_run == "" then "未运行" else .last_run end), (.failure_count | tostring)] | @tsv' <<<"${syncStatus}") || return 1
        IFS=$'\t' read -r enabledText interval lastStatus lastRun failureCount <<<"${summary}"
        echoContent title "\n┌─ 订阅同步 ─────────────────────────────────────────"
        menuLine "自动同步：${enabledText}"
        menuLine "同步间隔：${interval} 分钟"
        menuLine "最近结果：${lastStatus} / ${lastRun}"
        menuLine "失败数量：${failureCount}"
        menuItem 2 "开启/关闭自动同步" "控制后台定时同步及节点配置变更通知；手动管理动作仍立即同步"
        menuItem 3 "设置同步间隔" "设置 1-59 分钟间隔，不隐式开启自动同步"
        menuItem 4 "状态与排障" "查看失败、健康、计划和定时任务"
        menuItem 5 "状态备份与恢复" "查看、备份、恢复或重建 groups.json"
        menuReturnItem 6 "${returnText}" "回到上级菜单"
        menuClose
        menuReadChoice sync_settings_menu "请选择:" syncSettingsStatus || return 0
        case "${syncSettingsStatus}" in
        1) syncAndShowSubscriptionLinks || true ;;
        2)
            expectedSyncEnabled=$(jq -r '.enabled' <<<"${syncStatus}") || return 1
            targetSyncEnabled=true
            [[ "${expectedSyncEnabled}" != "true" ]] || targetSyncEnabled=false
            if setSubscriptionGroupSyncEnabledWithCron "${targetSyncEnabled}" "${expectedSyncEnabled}"; then
                successCard "自动同步状态已更新" "当前状态：$(if [[ "${targetSyncEnabled}" == "true" ]]; then printf '开启'; else printf '关闭'; fi)"
            elif [[ "$?" -ne 2 ]]; then
                errorCard "自动同步状态切换失败"
            fi
            ;;
        3)
            expectedInterval=${interval}
            while true; do
                menuReadChoice sync_interval_minutes \
                    "请输入同步间隔分钟[回车保留 ${expectedInterval} 分钟]:" interval true || return 0
                [[ -n "${interval}" ]] || break
                subscriptionGroupSyncIntervalValid "${interval}" || {
                    errorCard "同步间隔需为 1-59 分钟"
                    continue
                }
                interval=$((10#${interval}))
                if [[ "${interval}" == "${expectedInterval}" ]]; then
                    statusCard "同步间隔未变化"
                    break
                fi
                if setSubscriptionGroupSyncIntervalWithCron "${interval}" "${expectedInterval}"; then
                    successCard "自动同步间隔已更新"
                elif [[ "$?" -ne 2 ]]; then
                    errorCard "自动同步间隔更新失败"
                fi
                break
            done
            ;;
        4) manageSubscriptionSyncDiagnostics ;;
        5) manageSubscriptionStateBackups sync ;;
        6) return ;;
        *) coreSelectionErrorCard ;;
        esac
    done
}
