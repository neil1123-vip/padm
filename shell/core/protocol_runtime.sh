#!/usr/bin/env bash

realityKeyFile() {
    printf '%s\n' "${PADM_SINGBOX_REALITY_KEY_FILE:-/etc/padm/sing-box/conf/config/reality_key}"
}

protocolPortInputStatusCard() {
    statusCard "端口输入" "$@"
}

protocolPortHoppingStatusCard() {
    statusCard "端口跳跃" "$@"
}

protocolPortHoppingRangeStatusCard() {
    statusCard "端口跳跃范围" "$@"
}

tuicAlgorithmStatusCard() {
    statusCard "Tuic 算法" "$@"
}

singBoxVersionAtLeast() {
    local current=$1
    local required=$2
    local currentBase requiredBase
    current=${current#v}
    required=${required#v}
    currentBase=${current%%-*}
    requiredBase=${required%%-*}
    [[ -n "${currentBase}" && -n "${requiredBase}" ]] || return 1
    [[ "$(printf '%s\n%s\n' "${requiredBase}" "${currentBase}" | sort -V | head -n 1)" == "${requiredBase}" ]]
}

hysteria2SingBoxFieldSupported() {
    local field=$1
    local version=${2:-}
    local required=1.11.0
    case "${field}" in
    masquerade|ignore_client_bandwidth)
        required=1.11.0
        ;;
    obfs|obfs_gecko|bbr_profile|realm)
        required=1.14.0
        ;;
    *)
        return 1
        ;;
    esac
    if [[ -z "${version}" ]]; then
        if declare -F getSingBoxCurrentVersion >/dev/null 2>&1; then
            version=$(getSingBoxCurrentVersion)
        else
            return 1
        fi
    fi
    singBoxVersionAtLeast "${version}" "${required}"
}

hysteria2RequireSingBoxField() {
    local field=$1
    local required=$2
    local version=
    if declare -F getSingBoxCurrentVersion >/dev/null 2>&1; then
        version=$(getSingBoxCurrentVersion)
    fi
    if [[ -n "${version}" && "${version}" != "未安装" ]] && ! hysteria2SingBoxFieldSupported "${field}" "${version}"; then
        errorCard "当前 sing-box ${version} 不支持 Hysteria2 ${field}，请升级到 ${required} 或更高版本"
        return 1
    fi
}

hysteria2MasqueradeJson() {
    local value=${1:-}
    if [[ -n "${value}" ]]; then
        jq -n --arg value "${value}" '$value'
        return
    fi
    jq -n '{type:"string",status_code:404,headers:{"content-type":["text/plain; charset=utf-8"]},content:"Not Found"}'
}
# 初始化 Hysteria2 端口
initHysteriaPort() {
    readSingBoxConfig
    if [[ -n "${hysteriaPort}" ]]; then
        autoRead hysteria_history_port "读取到上次安装时的Hysteria端口 [${hysteriaPort}]，是否使用？[y/n]:" historyHysteriaPortStatus
        if [[ "${historyHysteriaPortStatus}" == "y" ]]; then
            statusCard "Hysteria2 端口" "${hysteriaPort}"
        else
            hysteriaPort=
        fi
    fi

    if [[ -z "${hysteriaPort}" ]]; then
        echoContent yellow "请输入Hysteria端口[回车随机10000-30000]，不可与其他服务重复"
        autoRead hysteria_port "端口:" hysteriaPort
        if [[ -z "${hysteriaPort}" ]]; then
            hysteriaPort=$((RANDOM % 20001 + 10000))
        fi
    fi
    if [[ -z "${hysteriaPort}" ]]; then
        protocolPortInputStatusCard "端口不可为空"
        initHysteriaPort "${2:-}"
        return $?
    elif ! validPortNumber "${hysteriaPort}"; then
        protocolPortInputStatusCard "端口不合法"
        initHysteriaPort "${2:-}"
        return $?
    fi
    allowPortTcpAndUdp "${hysteriaPort}" || return 1
}


# 初始化 Hysteria2 网络信息
initHysteria2Network() {

    while true; do
        echoContent yellow "请输入本地带宽峰值的下行速度（默认：100，单位：Mbps）"
        autoRead hysteria_download_speed "下行速度:" hysteria2ClientDownloadSpeed
        hysteria2ClientDownloadSpeed=${hysteria2ClientDownloadSpeed:-100}
        if [[ "${hysteria2ClientDownloadSpeed}" =~ ^[0-9]{1,6}$ ]] && ((10#${hysteria2ClientDownloadSpeed} > 0)); then
            statusCard "Hysteria2 下行速度" "${hysteria2ClientDownloadSpeed} Mbps"
            break
        fi
        statusCard "Hysteria2 带宽" "带宽不合法"
    done

    while true; do
        echoContent yellow "请输入本地带宽峰值的上行速度（默认：50，单位：Mbps）"
        autoRead hysteria_upload_speed "上行速度:" hysteria2ClientUploadSpeed
        hysteria2ClientUploadSpeed=${hysteria2ClientUploadSpeed:-50}
        if [[ "${hysteria2ClientUploadSpeed}" =~ ^[0-9]{1,6}$ ]] && ((10#${hysteria2ClientUploadSpeed} > 0)); then
            statusCard "Hysteria2 上行速度" "${hysteria2ClientUploadSpeed} Mbps"
            break
        fi
        statusCard "Hysteria2 带宽" "带宽不合法"
    done

    hysteria2RequireSingBoxField masquerade 1.11.0 || return 1
    echoContent yellow "请输入 Hysteria2 认证失败伪装 URL[http/https/file，回车使用固定404响应]"
    autoRead hysteria_masquerade "伪装URL:" hysteria2Masquerade
    if [[ -n "${hysteria2Masquerade}" && ! "${hysteria2Masquerade}" =~ ^(https?|file):// ]]; then
        errorCard "Hysteria2 masquerade 仅支持 http://、https:// 或 file:// URL"
        return 1
    fi
    statusCard "Hysteria2 masquerade" "${hysteria2Masquerade:-固定404响应}"
}


# firewalld 端口跳跃规则
addFirewalldPortHopping() {

    local start=$1
    local end=$2
    local targetPort=$3
    local outputVar=${4:-}
    local port
    local rule
    local queryStatus
    local addedPorts=
    for port in $(seq "$start" "$end"); do
        rule="port=${port}:proto=udp:toport=${targetPort}"
        if sudo firewall-cmd --zone=public --permanent --query-forward-port="${rule}" >/dev/null 2>&1; then
            continue
        else
            queryStatus=$?
            if [[ "${queryStatus}" != "1" ]]; then
                [[ -z "${addedPorts}" ]] || removeFirewalldForwardPortRange "${start}" "${end}" "${targetPort}" "owned=${addedPorts}" >/dev/null 2>&1 || true
                return 1
            fi
        fi
        if sudo firewall-cmd --zone=public --permanent --add-forward-port="${rule}"; then
            addedPorts="${addedPorts:+${addedPorts},}${port}"
        else
            [[ -z "${addedPorts}" ]] || removeFirewalldForwardPortRange "${start}" "${end}" "${targetPort}" "owned=${addedPorts}" >/dev/null 2>&1 || true
            return 1
        fi
    done
    if ! sudo firewall-cmd --reload; then
        [[ -z "${addedPorts}" ]] || removeFirewalldForwardPortRange "${start}" "${end}" "${targetPort}" "owned=${addedPorts}" >/dev/null 2>&1 || true
        return 1
    fi
    if [[ -n "${outputVar}" ]]; then
        printf -v "${outputVar}" '%s' "${addedPorts}"
    fi
}

portHoppingPersistIptablesRules() {
    if command -v netfilter-persistent >/dev/null 2>&1; then
        sudo netfilter-persistent save >/dev/null 2>&1
        return $?
    fi
    return 2
}

rollbackPortHoppingIptablesRule() {
    local type=$1
    local start=$2
    local end=$3
    local targetPort=$4
    local persistStatus

    iptables -t nat -D PREROUTING -p udp --dport "${start}:${end}" -m comment --comment "neil1123-vip_${type}_portHopping" -j DNAT --to-destination ":${targetPort}" >/dev/null 2>&1 || return 1
    if portHoppingPersistIptablesRules; then
        return 0
    else
        persistStatus=$?
    fi
    [[ "${persistStatus}" == "2" ]]
}

portHoppingWarnIptablesNotPersistent() {
    statusCard "端口跳跃持久化" "未检测到 netfilter-persistent，当前规则仅在本次运行期生效" "如需开机保留，请安装 netfilter-persistent 后重新配置"
}


# 端口跳跃
addPortHopping() {
    local type=$1
    local targetPort=$2
    local currentPortHoppingStart=
    local currentPortHoppingEnd=
    if [[ "${type}" == "hysteria2" ]]; then
        currentPortHoppingStart=${hysteria2PortHoppingStart:-}
        currentPortHoppingEnd=${hysteria2PortHoppingEnd:-}
    elif [[ "${type}" == "tuic" ]]; then
        currentPortHoppingStart=${tuicPortHoppingStart:-}
        currentPortHoppingEnd=${tuicPortHoppingEnd:-}
    fi
    if [[ -n "${currentPortHoppingStart}" || -n "${currentPortHoppingEnd}" ]]; then
        protocolPortHoppingStatusCard "已添加不可重复添加，可删除后重新添加"
        exit 0
    fi
    if [[ "${rhelLike:-}" == "true" ]]; then
        if ! systemctl is-active --quiet firewalld 2>/dev/null; then
            protocolPortHoppingStatusCard "未启动 firewalld 防火墙，无法设置端口跳跃"
            exit 0
        fi
    fi

    echoContent title "\n┌─ 端口跳跃配置 ─────────────────────────────────────"
    menuLine "仅支持 Hysteria2、Tuic"
    menuLine "端口跳跃用于 UDP 场景，当前脚本通过系统防火墙转发到实际协议端口"
    menuLine "Hysteria2 官方新版也支持服务端端口范围监听；当前方式仍是兼容的手动转发方案"
    menuLine "推荐范围：30000-40000 中选择约 1000 个端口，避免和其他端口跳跃范围重叠"
    menuClose

    echoContent yellow "请输入端口跳跃的范围，例如[30000-31000]"

    autoRead port_hopping_range "范围:" portHoppingRange
    if [[ -z "${portHoppingRange}" ]]; then
        protocolPortHoppingRangeStatusCard "范围不可为空"
        addPortHopping "${type}" "${targetPort}"
    elif [[ "${portHoppingRange}" == *-* ]]; then

        local portStart=
        local portEnd=
        portStart=${portHoppingRange%%-*}
        portEnd=${portHoppingRange#*-}

        if [[ -z "${portStart}" || -z "${portEnd}" ]]; then
            protocolPortHoppingRangeStatusCard "范围不合法"
            addPortHopping "${type}" "${targetPort}"
        elif ! validPortNumber "${portStart}" || ! validPortNumber "${portEnd}" ||
            ((10#${portStart} < 30000 || 10#${portStart} > 40000 || 10#${portEnd} < 30000 || 10#${portEnd} > 40000 || 10#${portEnd} < 10#${portStart})); then
            protocolPortHoppingRangeStatusCard "范围不合法"
            addPortHopping "${type}" "${targetPort}"
        else
            protocolPortHoppingRangeStatusCard "${portHoppingRange}"
            if [[ "${rhelLike:-}" == "true" ]] && systemctl is-active --quiet firewalld; then
                local addedMasquerade=
                local addedForwardPorts=
                local forwardStateKey
                if ! sudo firewall-cmd --zone=public --permanent --query-masquerade >/dev/null 2>&1; then
                    addedMasquerade=true
                fi
                if ! sudo firewall-cmd --zone=public --permanent --add-masquerade || ! sudo firewall-cmd --reload || ! addFirewalldPortHopping "${portStart}" "${portEnd}" "${targetPort}" addedForwardPorts || ! sudo firewall-cmd --zone=public --list-forward-ports | grep -q "toport=${targetPort}"; then
                    [[ -z "${addedForwardPorts}" ]] || removeFirewalldForwardPortRange "${portStart}" "${portEnd}" "${targetPort}" "owned=${addedForwardPorts}" >/dev/null 2>&1 || true
                    if [[ "${addedMasquerade}" == "true" ]]; then
                        sudo firewall-cmd --zone=public --permanent --remove-masquerade >/dev/null 2>&1 || true
                    fi
                    sudo firewall-cmd --reload >/dev/null 2>&1 || true
                    protocolPortHoppingStatusCard "端口跳跃添加失败，已尝试回滚本次 firewalld 规则"
                    exit 1
                fi
                if ! ( allowPort "${portStart}:${portEnd}" udp ); then
                    [[ -z "${addedForwardPorts}" ]] || removeFirewalldForwardPortRange "${portStart}" "${portEnd}" "${targetPort}" "owned=${addedForwardPorts}" >/dev/null 2>&1 || true
                    if [[ "${addedMasquerade}" == "true" ]]; then
                        sudo firewall-cmd --zone=public --permanent --remove-masquerade >/dev/null 2>&1 || true
                    fi
                    sudo firewall-cmd --reload >/dev/null 2>&1 || true
                    protocolPortHoppingStatusCard "端口跳跃开放端口失败，已尝试回滚本次 firewalld 规则"
                    exit 1
                fi
                forwardStateKey=$(padmFirewalldForwardStateKey "${portStart}" "${portEnd}" "${targetPort}" "${addedForwardPorts}")
                if ! padmFirewallStateAdd "${forwardStateKey}"; then
                    [[ -z "${addedForwardPorts}" ]] || removeFirewalldForwardPortRange "${portStart}" "${portEnd}" "${targetPort}" "owned=${addedForwardPorts}" >/dev/null 2>&1 || true
                    denyPort "${portStart}:${portEnd}" udp >/dev/null 2>&1 || true
                    if [[ "${addedMasquerade}" == "true" ]]; then
                        sudo firewall-cmd --zone=public --permanent --remove-masquerade >/dev/null 2>&1 || true
                    fi
                    sudo firewall-cmd --reload >/dev/null 2>&1 || true
                    protocolPortHoppingStatusCard "端口跳跃状态记录失败，已尝试回滚本次 firewalld 规则"
                    exit 1
                fi
                if [[ "${addedMasquerade}" == "true" ]] && ! padmFirewallStateAdd masquerade:firewalld; then
                    [[ -z "${addedForwardPorts}" ]] || removeFirewalldForwardPortRange "${portStart}" "${portEnd}" "${targetPort}" "owned=${addedForwardPorts}" >/dev/null 2>&1 || true
                    denyPort "${portStart}:${portEnd}" udp >/dev/null 2>&1 || true
                    padmFirewallStateRemove "${forwardStateKey}" >/dev/null 2>&1 || true
                    sudo firewall-cmd --zone=public --permanent --remove-masquerade >/dev/null 2>&1 || true
                    sudo firewall-cmd --reload >/dev/null 2>&1 || true
                    protocolPortHoppingStatusCard "端口跳跃状态记录失败，已尝试回滚本次 firewalld 规则"
                    exit 1
                fi
            else
                if ! iptables -t nat -A PREROUTING -p udp --dport "${portStart}:${portEnd}" -m comment --comment "neil1123-vip_${type}_portHopping" -j DNAT --to-destination ":${targetPort}"; then
                    rollbackPortHoppingIptablesRule "${type}" "${portStart}" "${portEnd}" "${targetPort}" || true
                    protocolPortHoppingStatusCard "端口跳跃添加失败，已尝试回滚本次 iptables 规则"
                    return 1
                fi
                local persistStatus=0
                local savedRules
                if portHoppingPersistIptablesRules; then
                    persistStatus=0
                else
                    persistStatus=$?
                fi
                if [[ "${persistStatus}" == "1" ]]; then
                    rollbackPortHoppingIptablesRule "${type}" "${portStart}" "${portEnd}" "${targetPort}" || true
                    protocolPortHoppingStatusCard "端口跳跃添加失败，已尝试回滚本次 iptables 规则"
                    return 1
                fi
                if ! savedRules=$(iptables-save) || ! grep -q "neil1123-vip_${type}_portHopping" <<<"${savedRules}"; then
                    rollbackPortHoppingIptablesRule "${type}" "${portStart}" "${portEnd}" "${targetPort}" || true
                    protocolPortHoppingStatusCard "端口跳跃添加失败，已尝试回滚本次 iptables 规则"
                    return 1
                fi
                if ! allowPort "${portStart}:${portEnd}" udp; then
                    rollbackPortHoppingIptablesRule "${type}" "${portStart}" "${portEnd}" "${targetPort}" || true
                    protocolPortHoppingStatusCard "端口跳跃开放端口失败，已尝试回滚本次 iptables 规则"
                    return 1
                fi
                local forwardStateKey
                forwardStateKey=$(padmIptablesForwardStateKey "${type}" "${portStart}" "${portEnd}" "${targetPort}")
                if ! padmFirewallStateAdd "${forwardStateKey}"; then
                    rollbackPortHoppingIptablesRule "${type}" "${portStart}" "${portEnd}" "${targetPort}" || true
                    denyPort "${portStart}:${portEnd}" udp >/dev/null 2>&1 || true
                    protocolPortHoppingStatusCard "端口跳跃状态记录失败，已尝试回滚本次 iptables 规则"
                    return 1
                fi
                if [[ "${persistStatus}" == "2" ]]; then
                    portHoppingWarnIptablesNotPersistent
                fi
            fi
            protocolPortHoppingStatusCard "端口跳跃添加成功"
        fi
    else
        protocolPortHoppingRangeStatusCard "范围不合法"
        addPortHopping "${type}" "${targetPort}"
    fi
}


# 读取端口跳跃的配置
readPortHopping() {
    local type=$1
    local targetPort=$2
    local portHoppingStart=
    local portHoppingEnd=
    local portHopping=

    local forwardStateKey stateKind stateBackend stateType stateStart stateEnd stateTarget ownership extra
    if forwardStateKey=$(padmFirewalldForwardStateKeyForTarget "${targetPort}"); then
        IFS=: read -r stateKind stateBackend stateType stateStart stateEnd stateTarget ownership extra <<<"${forwardStateKey}"
        portHoppingStart=${stateStart}
        portHoppingEnd=${stateEnd}
    elif forwardStateKey=$(padmIptablesForwardStateKeyForTarget "${type}" "${targetPort}"); then
        IFS=: read -r stateKind stateBackend stateType stateStart stateEnd stateTarget <<<"${forwardStateKey}"
        portHoppingStart=${stateStart}
        portHoppingEnd=${stateEnd}
    elif [[ "${rhelLike:-}" == "true" ]] && systemctl is-active --quiet firewalld; then
        local forwardPorts
        forwardPorts=$(sudo firewall-cmd --zone=public --list-forward-ports | awk -F: -v targetPort="${targetPort}" '
            $3 == "toport=" targetPort {
                split($1, port, "=")
                print port[2]
            }
        ')
        portHoppingStart=$(head -1 <<<"${forwardPorts}")
        portHoppingEnd=$(tail -n 1 <<<"${forwardPorts}")
    elif iptables-save | grep -q "neil1123-vip_${type}_portHopping"; then
        portHopping=$(iptables-save | awk -v marker="neil1123-vip_${type}_portHopping" '
            $0 ~ marker {
                for (i = 1; i <= NF; i++) {
                    if ($i == "--dport" && (i + 1) <= NF) {
                        print $(i + 1)
                        exit
                    }
                }
            }
        ')

        portHoppingStart=$(echo "${portHopping}" | cut -d ":" -f 1)
        portHoppingEnd=$(echo "${portHopping}" | cut -d ":" -f 2)
    fi
    if [[ -n "${portHoppingStart}" && -n "${portHoppingEnd}" ]]; then
        portHopping="${portHoppingStart}-${portHoppingEnd}"
    else
        portHopping=
    fi
    if [[ "${type}" == "hysteria2" ]]; then
        hysteria2PortHoppingStart="${portHoppingStart}"
        hysteria2PortHoppingEnd=${portHoppingEnd}
        hysteria2PortHopping="${portHopping}"
    elif [[ "${type}" == "tuic" ]]; then
        tuicPortHoppingStart="${portHoppingStart}"
        tuicPortHoppingEnd="${portHoppingEnd}"
        tuicPortHopping="${portHopping}"
    fi
}

# 删除端口跳跃 iptables 规则
deletePortHoppingRules() {
    local type=$1
    local start=$2
    local end=$3
    local targetPort=$4
    local status=0
    local forwardStateKey stateKind stateBackend stateType stateStart stateEnd stateTarget ownership extra
    local selectedBackend=
    if forwardStateKey=$(padmFirewalldForwardStateKeyForTarget "${targetPort}"); then
        IFS=: read -r stateKind stateBackend stateType stateStart stateEnd stateTarget ownership extra <<<"${forwardStateKey}"
        start=${stateStart}
        end=${stateEnd}
        selectedBackend=firewalld
    elif forwardStateKey=$(padmIptablesForwardStateKeyForTarget "${type}" "${targetPort}"); then
        IFS=: read -r stateKind stateBackend stateType stateStart stateEnd stateTarget <<<"${forwardStateKey}"
        start=${stateStart}
        end=${stateEnd}
        selectedBackend=iptables
    elif [[ "${rhelLike:-}" == "true" ]] && systemctl is-active --quiet firewalld; then
        forwardStateKey=$(padmFirewalldForwardStateKey "${start}" "${end}" "${targetPort}")
        selectedBackend=firewalld
    else
        forwardStateKey=$(padmIptablesForwardStateKey "${type}" "${start}" "${end}" "${targetPort}")
        selectedBackend=iptables
    fi
    if [[ "${selectedBackend}" == "firewalld" ]]; then
        if removeFirewalldForwardPortRange "${start}" "${end}" "${targetPort}" "${ownership}"; then
            padmFirewallStateRemove "${forwardStateKey}" || status=1
        else
            status=1
        fi
    else
        if ! removeIptablesPortHoppingRules "${type}"; then
            status=1
        elif ! padmFirewallStateRemove "${forwardStateKey}"; then
            status=1
        fi
    fi
    if [[ "${status}" == "0" ]] && ! denyPort "${start}:${end}" udp; then
        status=1
    fi
    if [[ "${status}" == "0" && "${rhelLike:-}" == "true" ]] && padmFirewallStateHas masquerade:firewalld; then
        local remainingForwardPorts
        if ! remainingForwardPorts=$(sudo firewall-cmd --zone=public --permanent --list-forward-ports); then
            status=1
        elif [[ -z "${remainingForwardPorts//[[:space:]]/}" ]]; then
            if removeFirewalldMasqueradeRule; then
                padmFirewallStateRemove masquerade:firewalld || status=1
            else
                status=1
            fi
        fi
    fi
    return "${status}"
}


# 端口跳跃管理
portHoppingMenu() {
    local type=$1
    # 非 firewalld 后端需要 iptables
    if { [[ "${rhelLike:-}" != "true" ]] || ! systemctl is-active --quiet firewalld 2>/dev/null; } &&
        ! command -v iptables >/dev/null 2>&1; then
        protocolPortHoppingStatusCard "无法识别 iptables 工具，无法使用端口跳跃，退出安装"
        exit 0
    fi

    local targetPort=
    local portHoppingStart=
    local portHoppingEnd=

    if [[ "${type}" == "hysteria2" ]]; then
        readPortHopping "${type}" "${singBoxHysteria2Port}"
        targetPort=${singBoxHysteria2Port}
        portHoppingStart=${hysteria2PortHoppingStart}
        portHoppingEnd=${hysteria2PortHoppingEnd}
    elif [[ "${type}" == "tuic" ]]; then
        readPortHopping "${type}" "${singBoxTuicPort}"
        targetPort=${singBoxTuicPort}
        portHoppingStart=${tuicPortHoppingStart}
        portHoppingEnd=${tuicPortHoppingEnd}
    fi

    local selectPortHoppingStatus=
    while true; do
        echoContent title "\n┌─ 端口跳跃 ─────────────────────────────────────────"
        menuItem 1 "添加端口跳跃" "配置 UDP 端口范围转发到当前服务端口"
        menuItem 2 "删除端口跳跃" "移除当前端口跳跃规则"
        menuItem 3 "查看端口跳跃" "显示当前端口跳跃范围"
        menuClose
        selectPortHoppingStatus=
        autoRead port_hopping_menu "请选择:" selectPortHoppingStatus || return 0
        case "${selectPortHoppingStatus}" in
        1)
            addPortHopping "${type}" "${targetPort}" || return 1
            return 0
            ;;
        2)
            if deletePortHoppingRules "${type}" "${portHoppingStart}" "${portHoppingEnd}" "${targetPort}"; then
                protocolPortHoppingStatusCard "删除成功"
                return 0
            fi
            protocolPortHoppingStatusCard "删除失败，请检查防火墙规则"
            return 1
            ;;
        3)
            if [[ -n "${portHoppingStart}" && -n "${portHoppingEnd}" ]]; then
                protocolPortHoppingStatusCard "当前端口跳跃范围为: ${portHoppingStart}-${portHoppingEnd}"
            else
                protocolPortHoppingStatusCard "未设置端口跳跃"
            fi
            return 0
            ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}


# 初始化 TUIC 端口
initTuicPort() {
    readSingBoxConfig
    if [[ -n "${tuicPort}" ]]; then
        autoRead tuic_history_port "读取到上次安装时的Tuic端口 [${tuicPort}]，是否使用？[y/n]:" historyTuicPortStatus
        if [[ "${historyTuicPortStatus}" == "y" ]]; then
            statusCard "Tuic 端口" "${tuicPort}"
        else
            tuicPort=
        fi
    fi

    if [[ -z "${tuicPort}" ]]; then
        echoContent yellow "请输入Tuic端口[回车随机10000-30000]，不可与其他服务重复"
        autoRead tuic_port "端口:" tuicPort
        if [[ -z "${tuicPort}" ]]; then
            tuicPort=$((RANDOM % 20001 + 10000))
        fi
    fi
    if [[ -z "${tuicPort}" ]]; then
        protocolPortInputStatusCard "端口不可为空"
        initTuicPort "${2:-}"
        return $?
    elif ! validPortNumber "${tuicPort}"; then
        protocolPortInputStatusCard "端口不合法"
        initTuicPort "${2:-}"
        return $?
    fi
    statusCard "Tuic 端口" "${tuicPort}"
    allowPortTcpAndUdp "${tuicPort}" || return 1
}


# 初始化 TUIC 协议参数
initTuicProtocol() {
    if [[ -n "${tuicAlgorithm}" && -z "${lastInstallationConfig}" ]]; then
        autoRead tuic_history_algorithm "读取到上次使用的算法 [${tuicAlgorithm}]，是否使用？[y/n]:" historyTuicAlgorithm
        if [[ "${historyTuicAlgorithm}" != "y" ]]; then
            tuicAlgorithm=
        else
            tuicAlgorithmStatusCard "${tuicAlgorithm}"
        fi
    elif [[ -n "${tuicAlgorithm}" && -n "${lastInstallationConfig}" ]]; then
        tuicAlgorithmStatusCard "${tuicAlgorithm}"
    fi

    if [[ -z "${tuicAlgorithm}" ]]; then

        echoContent title "\n┌─ Tuic 拥塞控制算法 ─────────────────────────────────"
        menuRecommendedItem 1 "cubic" "sing-box 默认算法"
        menuItem 2 "bbr" "高带宽或长距离链路可尝试"
        menuItem 3 "new_reno" "兼容保守拥塞控制"
        menuClose
        autoRead tuic_algorithm_menu "请选择:" selectTuicAlgorithm
        case ${selectTuicAlgorithm} in
        2)
            tuicAlgorithm="bbr"
            ;;
        3)
            tuicAlgorithm="new_reno"
            ;;
        *)
            tuicAlgorithm="cubic"
            ;;
        esac
        tuicAlgorithmStatusCard "${tuicAlgorithm}"
    fi
}


# 初始化realityKey
initRealityKey() {
    echoContent title "\n┌─ Reality Key ─────────────────────────────────────"
    menuLine "生成 Reality key"
    menuClose
    if [[ -n "${currentRealityPublicKey}" && -z "${lastInstallationConfig}" ]]; then
        autoRead reality_history_key "读取到上次安装记录，PublicKey为 [${currentRealityPublicKey}]，是否复用上次的PublicKey/PrivateKey？[y/n]:" historyKeyStatus
        if [[ "${historyKeyStatus}" == "y" ]]; then
            realityPrivateKey=${currentRealityPrivateKey}
            realityPublicKey=${currentRealityPublicKey}
        fi
    elif [[ -n "${currentRealityPublicKey}" && -n "${lastInstallationConfig}" ]]; then
        realityPrivateKey=${currentRealityPrivateKey}
        realityPublicKey=${currentRealityPublicKey}
    fi
    if [[ -z "${realityPrivateKey}" ]]; then
        if [[ "${selectCoreType}" == "2" || "${coreInstallType}" == "2" ]]; then
            local singBoxBinary="${PADM_SINGBOX_BINARY:-/etc/padm/sing-box/sing-box}"
            if ! realityX25519Key=$("${singBoxBinary}" generate reality-keypair); then
                errorCard "Reality Key 生成失败"
                return 1
            fi
            realityPrivateKey=$(printf '%s\n' "${realityX25519Key}" | awk '$1 ~ /^PrivateKey:?$/ { print $2; exit }')
            realityPublicKey=$(printf '%s\n' "${realityX25519Key}" | awk '$1 ~ /^PublicKey:?$/ { print $2; exit }')
            if [[ -z "${realityPrivateKey}" || -z "${realityPublicKey}" ]]; then
                errorCard "Reality Key 生成结果不完整"
                return 1
            fi
        else
            autoRead reality_private_key "请输入Private Key[回车自动生成]:" historyPrivateKey
            if [[ -n "${historyPrivateKey}" ]]; then
                realityX25519Key=$(/etc/padm/xray/xray x25519 -i "${historyPrivateKey}") || return 1
            else
                realityX25519Key=$(/etc/padm/xray/xray x25519) || return 1
            fi
            realityPrivateKey=$(echo "${realityX25519Key}" | grep "PrivateKey" | awk '{print $2}')
            realityPublicKey=$(echo "${realityX25519Key}" | grep "Password" | awk '{print $3}')
            if [[ -z "${realityPrivateKey}" || -z "${realityPublicKey}" ]]; then
                errorCard "Reality Key 生成结果不完整"
                return 1
            fi
            statusCard "Reality Key" "publicKey:${realityPublicKey}"
        fi
    fi
    if [[ "${selectCoreType}" == "2" || "${coreInstallType}" == "2" ]]; then
        local realityKeyPath realityKeyStage
        realityKeyPath=$(realityKeyFile) || return 1
        padmCreateTempFileForTarget realityKeyStage "${realityKeyPath}" reality || return 1
        printf 'publicKey:%s\n' "${realityPublicKey}" >"${realityKeyStage}" || { padmRemoveCleanupPath "${realityKeyStage}"; return 1; }
        commitGeneratedFile "${realityKeyStage}" "${realityKeyPath}" 600 || { padmRemoveCleanupPath "${realityKeyStage}"; return 1; }
    fi
    [[ -n "${realityPrivateKey}" && -n "${realityPublicKey}" ]]
}

# 初始化 mldsa65Seed
initRealityMldsa65() {
    echoContent title "\n┌─ Reality ML-DSA-65 ───────────────────────────────"
    menuLine "生成 Reality ML-DSA-65"
    menuClose
    local tlsPingResult=
    local length=
    local target="${realityTargetHost}:${realityTargetPort}"
    tlsPingResult=$(/etc/padm/xray/xray tls ping "${target}" 2>/dev/null)
    if echo "${tlsPingResult}" | awk '/Pinging with SNI/{inSni=1; next} inSni && /TLS Post-Quantum key exchange:.*X25519MLKEM768/{found=1} END{exit found ? 0 : 1}'; then
        length=$(echo "${tlsPingResult}" | awk '/Pinging with SNI/{inSni=1; next} inSni && /Certificate chain/{print $5; exit}')

        if [[ "${length}" =~ ^[0-9]+$ ]] && [ "${length}" -gt 3500 ]; then
            if [[ -n "${currentRealityMldsa65Seed}" && -z "${lastInstallationConfig}" ]]; then
                autoRead reality_history_mldsa65 "读取到上次安装记录，Seed为 [${currentRealityMldsa65Seed}]，Verify为 [${currentRealityMldsa65Verify}]，是否复用？[y/n]:" historyMldsa65Status
                if [[ "${historyMldsa65Status}" == "y" ]]; then
                    realityMldsa65Seed=${currentRealityMldsa65Seed}
                    realityMldsa65Verify=${currentRealityMldsa65Verify}
                fi
            elif [[ -n "${currentRealityMldsa65Seed}" && -n "${lastInstallationConfig}" ]]; then
                realityMldsa65Seed=${currentRealityMldsa65Seed}
                realityMldsa65Verify=${currentRealityMldsa65Verify}
            fi
            if [[ -z "${realityMldsa65Seed}" ]]; then
                realityMldsa65=$(/etc/padm/xray/xray mldsa65)
                realityMldsa65Seed=$(echo "${realityMldsa65}" | head -1 | awk '{print $2}')
                realityMldsa65Verify=$(echo "${realityMldsa65}" | tail -n 1 | awk '{print $2}')
            fi
        else
            statusCard "Reality ML-DSA-65" "目标域名支持 X25519MLKEM768，但是证书长度不足，忽略 ML-DSA-65"
        fi
    else
        statusCard "Reality ML-DSA-65" "目标域名不支持 X25519MLKEM768，忽略 ML-DSA-65"
    fi
}

parseHostPort() {
    local input=$1
    local defaultPort=${2:-443}
    local host port
    host=${input%:*}
    port=${input##*:}
    if [[ "${host}" == "${input}" || -z "${port}" ]]; then
        port=${defaultPort}
    fi
    printf '%s:%s\n' "${host}" "${port}"
}

validateRealityTarget() {
    local targetHost=$1
    local targetPort=$2
    padmIsValidHostName "${targetHost}" && validPortNumber "${targetPort}"
}

collectTLSProfile() {
    tlsEnabled=true
    if [[ -n "${domain:-}" ]]; then
        tlsCertDomain=${domain%%:*}
    elif [[ -n "${currentHost:-}" ]]; then
        tlsCertDomain=${currentHost}
    elif declare -F resolveInstalledTLSDomain >/dev/null 2>&1; then
        tlsCertDomain=$(resolveInstalledTLSDomain 2>/dev/null || true)
    else
        tlsCertDomain=
    fi
    tlsSNI=${tlsCertDomain}
    tlsCertFile="/etc/padm/tls/${tlsCertDomain}.crt"
    tlsKeyFile="/etc/padm/tls/${tlsCertDomain}.key"
}

collectEntryProfile() {
    local entryHostFile storedEntry= strictDomain=false
    realityStrictDomainModeEnabled && strictDomain=true

    if [[ -n "${AUTO_ENTRY_HOST:-}" ]]; then
        realityEntryHost=${AUTO_ENTRY_HOST}
    elif [[ -n "${AUTO_DOMAIN:-}" ]]; then
        realityEntryHost=${AUTO_DOMAIN}
    elif [[ -n "${domain:-}" ]]; then
        realityEntryHost=${domain}
    else
        entryHostFile=$(realityEntryHostFile)
        if [[ -f "${entryHostFile}" ]]; then
            storedEntry=$(head -n 1 "${entryHostFile}")
        fi
        if [[ -n "${storedEntry}" ]]; then
            realityEntryHost=${storedEntry}
        elif [[ -n "${currentHost:-}" ]]; then
            realityEntryHost=${currentHost}
        elif [[ "${strictDomain}" == "true" ]]; then
            if [[ "${AUTO_INSTALL:-}" == "true" ]]; then
                errorCard "严格域名 Reality 缺少入口域名，请传 --entry-host 或 --domain"
                return 1
            fi
            statusCard "Reality 入口域名" "请输入客户端实际连接的域名"
            autoRead entry_host "入口域名:" realityEntryHost
        else
            realityEntryHost=$(getPublicIP)
        fi
    fi

    if [[ "${strictDomain}" == "true" ]]; then
        if ! padmIsValidHostName "${realityEntryHost}" || [[ "${realityEntryHost}" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
            errorCard "Reality 入口域名不合法" "${realityEntryHost}"
            return 1
        fi
    elif ! padmIsValidConnectAddress "${realityEntryHost}"; then
        errorCard "Reality 客户端入口不合法" "${realityEntryHost}"
        return 1
    fi
}

realityEntryHostFile() {
    printf '%s\n' "${PADM_REALITY_ENTRY_HOST_FILE:-/etc/padm/reality_entry_host}"
}

printRealityTargetProfile() {
    statusCard "Reality 客户端入口" "${realityEntryHost:-未知}" "Reality 伪装目标: ${realityTargetHost}:${realityTargetPort:-443}" "Reality SNI: ${realitySNI:-${realityTargetHost}}"
}

collectRealityProfile() {
    local targetInput=
    local selectRealityTargetMode=
    local selectionPolicy=manual
    local selectedTarget

    [[ -n "${realityEntryHost:-}" ]] || collectEntryProfile || return 1

    if [[ -n "${AUTO_REALITY_TARGET:-}" ]]; then
        parseRealityTargetInput "${AUTO_REALITY_TARGET}" || return 1
    elif [[ -n "${realityTargetHost:-}" ]]; then
        parseRealityTargetInput "${realityTargetHost}:${realityTargetPort:-443}" || return 1
    else
        echoContent title "\n┌─ Reality 伪装目标 ─────────────────────────────────"
        menuLine "entry：客户端连接到你的服务器地址，已在订阅中作为 server/@host 使用"
        menuLine "target：REALITY 伪装访问的外部真实 HTTPS 站点，写入服务端握手配置"
        menuLine "SNI：REALITY 握手域名，默认等于 target host；除非明确知道原因，不要单独改"
        menuLine "自动推荐优先使用 cdn_risk=no 的 A 级结果；全新 sing-box 无 Xray 时可回退到 OpenSSL 验证的 C 级"
        menuLine "PQC/ML-DSA-65 场景需要目标站支持 X25519MLKEM768 且证书链足够长"
        menuClose
        echoContent title "┌─ REALITY 目标站选择 ───────────────────────────────"
        menuRecommendedItem 1 "自动推荐" "优先 A 级；sing-box 无 Xray 时仅回退到安全 C 级"
        menuItem 2 "候选列表" "选择后实时检测全部 A/AAAA"
        menuItem 3 "手动输入" "输入 host 或 host:port，端口默认 443"
        menuClose
        autoRead reality_target_mode "请选择[默认1]:" selectRealityTargetMode
        selectRealityTargetMode=${selectRealityTargetMode:-1}

        case "${selectRealityTargetMode}" in
        2)
            selectRealityTargetCandidateInteractive || return 1
            ;;
        3)
            autoRead reality_target "请输入REALITY伪装目标域名，默认端口443:" targetInput
            if [[ -z "${targetInput}" ]]; then
                selectionPolicy=auto
                selectDefaultRealityTarget || return 1
            else
                parseRealityTargetInput "${targetInput}" || return 1
            fi
            ;;
        *)
            selectionPolicy=auto
            selectDefaultRealityTarget || return 1
            ;;
        esac
    fi

    if ! validateRealityTarget "${realityTargetHost}" "${realityTargetPort:-443}"; then
        realityTargetStatusBlock red "REALITY 目标站" "伪装目标不合法: ${realityTargetHost}:${realityTargetPort:-443}"
        return 1
    fi
    if ! padmIsValidHostName "${realitySNI:-${realityTargetHost}}"; then
        realityTargetStatusBlock red "Reality SNI" "SNI 不合法: ${realitySNI:-${realityTargetHost}}"
        return 1
    fi
    if [[ "${realityTargetHost}" =~ ^[0-9.]+$ && -z "${AUTO_REALITY_SERVER_NAME:-}" ]]; then
        statusCard "Reality SNI 提醒" "目标站是 IP" "建议在高级场景手动指定 --reality-server-name" "或确认客户端 SNI 行为"
    fi
    selectedTarget=$(formatRealityTarget "${realityTargetHost}" "${realityTargetPort:-443}")
    validateRealityTargetSelection "${selectionPolicy}" "${selectedTarget}" "${realitySNI:-${realityTargetHost}}" || return 1
    printRealityTargetProfile
}

persistRealityEntryProfile() {
    local entryHostFile tmpFile
    [[ -n "${realityEntryHost:-}" ]] || return 0
    entryHostFile=$(realityEntryHostFile)
    padmCreateTempFileForTarget tmpFile "${entryHostFile}" reality-entry || return 1
    printf '%s\n' "${realityEntryHost}" >"${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    commitGeneratedFile "${tmpFile}" "${entryHostFile}" 600 || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

# 初始化REALITY配置
initRealityProfile() {
    collectRealityProfile || return 1
    if realityStrictDomainModeEnabled; then
        checkDNSIP "${realityEntryHost}" || return 1
    fi
}


# 已启用 443 共存时，安装只能继续使用记录的内部端口。
resolveRealityInstallCoexistPort() {
    local -n resultRef=$1
    local protocol=$2
    local label=$3
    local internalPort publicPort

    declare -F realityStreamSplitEnabled >/dev/null 2>&1 && realityStreamSplitEnabled || return 1
    internalPort=$(realityStreamInternalPortForProtocol "${protocol}")
    [[ -n "${internalPort}" ]] || return 1
    publicPort=$(realityStreamPublicPortForProtocol "${protocol}")
    publicPort=${publicPort:-443}
    if [[ -n "${AUTO_PORT:-}" && "${AUTO_PORT}" != "${publicPort}" ]]; then
        errorCard "${label} 已启用 443 共存；端口只能省略或传 ${publicPort}，更换端口请先关闭共存"
        return 2
    fi
    resultRef=${internalPort}
}

initXrayRealityProtocolPort() {
    local -n portRef=$1
    local historyPort=${2:-}
    local protocolId=$3
    local promptKey=$4
    local historyKey=$5
    local label=$6
    local transport=${7:-tcp}
    local streamProtocol=${8:-}
    local historyPortStatus= coexistStatus=1 singleProtocol=false

    protocolSelectionIsExactly "${selectCustomInstallType:-}" "${protocolId}" && singleProtocol=true
    if [[ -n "${streamProtocol}" ]]; then
        if resolveRealityInstallCoexistPort portRef "${streamProtocol}" "${label}"; then
            coexistStatus=0
        else
            coexistStatus=$?
            [[ "${coexistStatus}" == "2" ]] && return 1
        fi
    fi

    if [[ "${coexistStatus}" != "0" && "${singleProtocol}" == "true" && -n "${AUTO_PORT:-}" ]]; then
        portRef=${AUTO_PORT}
    elif [[ "${coexistStatus}" != "0" && -z "${portRef}" && -n "${historyPort}" ]]; then
        if [[ -n "${lastInstallationConfig:-}" || ( "${singleProtocol}" == "true" && "${AUTO_INSTALL:-}" == "true" ) ]]; then
            portRef=${historyPort}
        else
            autoRead "${historyKey}" "读取到上次安装记录，${label}端口为 [${historyPort}]，是否使用？[y/n]:" historyPortStatus
            [[ "${historyPortStatus}" == "y" ]] && portRef=${historyPort}
        fi
    fi

    if [[ -z "${portRef}" ]]; then
        if [[ "${singleProtocol}" == "true" ]]; then
            echoContent yellow "请输入 ${label} 连接端口[回车默认 443]"
            autoRead "${promptKey}" "${label} 连接端口:" portRef
            portRef=${portRef:-443}
        else
            echoContent yellow "请输入 ${label} 连接端口[回车随机 10000-30000]"
            autoRead "${promptKey}_subport" "${label} 连接端口:" portRef
            portRef=${portRef:-$((RANDOM % 20001 + 10000))}
        fi
    fi

    if ! validPortNumber "${portRef}"; then
        errorCard "${label} 端口输入错误"
        return 1
    fi
    checkPort "${portRef}" || return 1
    if [[ "${transport}" == "tcp+udp" ]]; then
        allowPortTcpAndUdp "${portRef}" || return 1
    else
        allowPort "${portRef}" || return 1
    fi
    if [[ "${coexistStatus}" == "0" ]]; then
        statusCard "${label} 共存内部端口" "${portRef}"
    else
        statusCard "${label} 客户端连接端口" "${portRef}"
    fi
}

initXrayRealityPort() {
    initXrayRealityProtocolPort realityPort "${xrayVLESSRealityPort:-}" 1 reality_port reality_history_port "Reality" tcp vision
}

initXrayRealityGrpcPort() {
    initXrayRealityProtocolPort realityGrpcPort "${xrayVLESSRealityGRPCPort:-}" 26 reality_port reality_grpc_history_port "Reality gRPC"
}

initXrayXHTTPort() {
    initXrayRealityProtocolPort xHTTPort "${xrayVLESSRealityXHTTPort:-}" 2 xhttp_port xhttp_history_port "Reality XHTTP" tcp+udp xhttp
}
