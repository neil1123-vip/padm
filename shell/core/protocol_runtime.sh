#!/usr/bin/env bash

realityKeyFile() {
    printf '%s\n' "${PADM_SINGBOX_REALITY_KEY_FILE:-${singBoxConfigPath:-${PADM_SINGBOX_CONFIG_DIR:-/etc/padm/sing-box/conf/config/}}reality_key}"
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

hysteria2ObfsConfigJson() {
    local type=${1:-} password=${2:-}
    if [[ -z "${type}" ]]; then
        printf '{}'
        return 0
    fi
    [[ "${type}" == "salamander" || "${type}" == "gecko" ]] || return 1
    [[ -n "${password}" ]] || return 1
    jq -nc --arg type "${type}" --arg password "${password}" \
        '{type:$type,password:$password}'
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

    local inputsOnly=${1:-false}
    local bandwidthMode existingBandwidthMode=${hysteria2BandwidthMode:-brutal}
    local defaultDownload=${hysteria2ClientDownloadSpeed:-100} defaultUpload=${hysteria2ClientUploadSpeed:-50}
    local parameterInput= existingMasquerade=${hysteria2Masquerade:-}

    if [[ ( -n "${lastInstallationConfig:-}" || "${PADM_INSTALL_HY2_INPUTS_PREPARED:-}" == true ) &&
        -n "${hysteria2BandwidthMode:-}" ]]; then
        case "${hysteria2BandwidthMode:-}" in
        brutal)
            if [[ ! "${hysteria2ClientDownloadSpeed:-}" =~ ^[0-9]{1,6}$ ]] ||
                [[ ! "${hysteria2ClientUploadSpeed:-}" =~ ^[0-9]{1,6}$ ]] ||
                ((10#${hysteria2ClientDownloadSpeed} <= 0 || 10#${hysteria2ClientUploadSpeed} <= 0)); then
                errorCard "上次 Hysteria2 带宽配置不合法"
                return 1
            fi
            ;;
        bbr)
            [[ "${inputsOnly}" == true ]] || hysteria2RequireSingBoxField ignore_client_bandwidth 1.11.0 || return 1
            ;;
        *)
            errorCard "上次 Hysteria2 拥塞模式不受支持"
            return 1
            ;;
        esac
        if [[ -n "${hysteria2ObfsType:-}" ]]; then
            [[ "${inputsOnly}" == true ]] || hysteria2RequireSingBoxField obfs 1.14.0 || return 1
            if [[ "${hysteria2ObfsType}" != salamander && "${hysteria2ObfsType}" != gecko ]] ||
                [[ -z "${hysteria2ObfsPassword:-}" ]]; then
                errorCard "上次 Hysteria2 混淆配置不合法"
                return 1
            fi
        fi
        [[ "${inputsOnly}" == true ]] || hysteria2RequireSingBoxField masquerade 1.11.0 || return 1
        if [[ -n "${hysteria2Masquerade:-}" && ! "${hysteria2Masquerade}" =~ ^(https?|file):// ]]; then
            errorCard "上次 Hysteria2 masquerade 配置不合法"
            return 1
        fi
        return 0
    fi

    while true; do
        menuLine "Brutal：适合客户端与服务端之间带宽较稳定的线路；需手填上下行，可从实测速率的 70%-80% 起步"
        menuLine "BBR：适合带宽波动、移动网络或多人共享出口；无需手填带宽，不确定时建议选 2"
        menuLine "此处 BBR 是 Hysteria2/QUIC 自适应拥塞控制，与系统 TCP BBR 设置无关"
        echoContent yellow "请选择 Hysteria2 拥塞模式：1 Brutal（固定带宽），2 BBR（自适应），回车保持 ${existingBandwidthMode}"
        menuReadChoice hysteria_bandwidth_mode "模式[1 Brutal/2 BBR，回车保持]:" bandwidthMode true || return 1
        bandwidthMode=${bandwidthMode:-${existingBandwidthMode}}
        case "${bandwidthMode}" in
        1|brutal)
            hysteria2BandwidthMode=brutal
            break
            ;;
        2|bbr)
            hysteria2BandwidthMode=bbr
            hysteria2ClientDownloadSpeed=
            hysteria2ClientUploadSpeed=
            statusCard "Hysteria2 拥塞模式" "BBR 自适应"
            break
            ;;
        *)
            statusCard "Hysteria2 拥塞模式" "模式不合法"
            [[ -z "${AUTO_INSTALL:-}" ]] || return 1
            ;;
        esac
    done

    if [[ "${hysteria2BandwidthMode}" == "brutal" ]]; then
        [[ "${defaultDownload}" =~ ^[0-9]{1,6}$ ]] && ((10#${defaultDownload} > 0)) || defaultDownload=100
        [[ "${defaultUpload}" =~ ^[0-9]{1,6}$ ]] && ((10#${defaultUpload} > 0)) || defaultUpload=50
        while true; do
            echoContent yellow "请输入客户端下行带宽峰值（服务端→客户端，回车保持 ${defaultDownload}，单位：Mbps）"
            menuReadChoice hysteria_download_speed "下行速度:" hysteria2ClientDownloadSpeed true || return 1
            hysteria2ClientDownloadSpeed=${hysteria2ClientDownloadSpeed:-${defaultDownload}}
            if [[ "${hysteria2ClientDownloadSpeed}" =~ ^[0-9]{1,6}$ ]] && ((10#${hysteria2ClientDownloadSpeed} > 0)); then
                statusCard "Hysteria2 客户端下行（服务端→客户端）" "${hysteria2ClientDownloadSpeed} Mbps"
                break
            fi
            statusCard "Hysteria2 带宽" "带宽不合法"
            [[ -z "${AUTO_INSTALL:-}" ]] || return 1
        done

        while true; do
            echoContent yellow "请输入客户端上行带宽峰值（客户端→服务端，回车保持 ${defaultUpload}，单位：Mbps）"
            menuReadChoice hysteria_upload_speed "上行速度:" hysteria2ClientUploadSpeed true || return 1
            hysteria2ClientUploadSpeed=${hysteria2ClientUploadSpeed:-${defaultUpload}}
            if [[ "${hysteria2ClientUploadSpeed}" =~ ^[0-9]{1,6}$ ]] && ((10#${hysteria2ClientUploadSpeed} > 0)); then
                statusCard "Hysteria2 客户端上行（客户端→服务端）" "${hysteria2ClientUploadSpeed} Mbps"
                break
            fi
            statusCard "Hysteria2 带宽" "带宽不合法"
            [[ -z "${AUTO_INSTALL:-}" ]] || return 1
        done
    fi

    local existingObfsType=${hysteria2ObfsType:-}
    local existingObfsPassword=${hysteria2ObfsPassword:-}
    if [[ -n "${existingObfsType}" && "${existingObfsType}" != salamander && "${existingObfsType}" != gecko ]]; then
        errorCard "上次 Hysteria2 混淆类型不合法，请重新输入"
        [[ -z "${AUTO_INSTALL:-}" ]] || return 1
        existingObfsType=
    fi
    while true; do
        echoContent yellow "请输入 Hysteria2 混淆类型[回车保持 ${existingObfsType:-关闭}，off 关闭，salamander/gecko]"
        menuReadChoice hysteria_obfs_type "混淆类型:" parameterInput true || return 1
        parameterInput=${parameterInput,,}
        parameterInput=${parameterInput:-${existingObfsType}}
        case "${parameterInput}" in
        off | none) parameterInput=; break ;;
        "" | salamander | gecko) break ;;
        esac
        errorCard "Hysteria2 混淆类型仅支持 salamander 或 gecko"
        [[ -z "${AUTO_INSTALL:-}" ]] || return 1
    done
    hysteria2ObfsType=${parameterInput}
    hysteria2ObfsPassword=
    if [[ -n "${hysteria2ObfsType}" ]]; then
        menuReadChoice hysteria_obfs_password "混淆密码:" hysteria2ObfsPassword true || return 1
        hysteria2ObfsPassword=${hysteria2ObfsPassword:-${existingObfsPassword}}
        if [[ -z "${hysteria2ObfsPassword}" ]]; then
            hysteria2ObfsPassword=$(generateRandomUuidValue) || {
                errorCard "Hysteria2 混淆密码生成失败"
                return 1
            }
        fi
        statusCard "Hysteria2 混淆" "${hysteria2ObfsType}"
    fi

    [[ "${inputsOnly}" == true ]] || hysteria2RequireSingBoxField masquerade 1.11.0 || return 1
    if [[ -n "${existingMasquerade}" && ! "${existingMasquerade}" =~ ^(https?|file):// ]]; then
        errorCard "上次 Hysteria2 masquerade 不合法，请重新输入"
        [[ -z "${AUTO_INSTALL:-}" ]] || return 1
        existingMasquerade=
    fi
    while true; do
        echoContent yellow "请输入 Hysteria2 认证失败伪装 URL[http/https/file，回车保持 ${existingMasquerade:-固定404响应}，off 恢复固定404响应]"
        menuReadChoice hysteria_masquerade "伪装URL:" parameterInput true || return 1
        parameterInput=${parameterInput:-${existingMasquerade}}
        [[ "${parameterInput}" != off && "${parameterInput}" != none ]] || parameterInput=
        if [[ -z "${parameterInput}" || "${parameterInput}" =~ ^(https?|file):// ]]; then
            hysteria2Masquerade=${parameterInput}
            break
        fi
        errorCard "Hysteria2 masquerade 仅支持 http://、https:// 或 file:// URL"
        [[ -z "${AUTO_INSTALL:-}" ]] || return 1
    done
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
        return 0
    fi
    if [[ "${rhelLike:-}" == "true" ]]; then
        if ! systemctl is-active --quiet firewalld 2>/dev/null; then
            protocolPortHoppingStatusCard "未启动 firewalld 防火墙，无法设置端口跳跃"
            return 1
        fi
    fi

    echoContent title "\n┌─ 端口跳跃配置 ─────────────────────────────────────"
    menuLine "仅支持 Hysteria2、Tuic"
    menuLine "端口跳跃用于 UDP 场景，当前脚本通过系统防火墙转发到实际协议端口"
    menuLine "Hysteria2 官方新版也支持服务端端口范围监听；当前方式仍是兼容的手动转发方案"
    menuLine "推荐范围：30000-40000 中选择约 1000 个端口，避免和其他端口跳跃范围重叠"
    menuClose

    echoContent yellow "请输入端口跳跃的范围，例如[30000-31000]"

    local portHoppingRange= portStart= portEnd=
    while true; do
        autoRead port_hopping_range "范围:" portHoppingRange || return 0
        if [[ -z "${portHoppingRange}" ]]; then
            protocolPortHoppingRangeStatusCard "范围不可为空"
            continue
        fi
        if [[ "${portHoppingRange}" != *-* ]]; then
            protocolPortHoppingRangeStatusCard "范围不合法"
            continue
        fi
        portStart=${portHoppingRange%%-*}
        portEnd=${portHoppingRange#*-}

        if [[ -z "${portStart}" || -z "${portEnd}" ]] ||
            ! validPortNumber "${portStart}" || ! validPortNumber "${portEnd}" ||
            ((10#${portStart} < 30000 || 10#${portStart} > 40000 || 10#${portEnd} < 30000 || 10#${portEnd} > 40000 || 10#${portEnd} < 10#${portStart})); then
            protocolPortHoppingRangeStatusCard "范围不合法"
            continue
        fi
        break
    done
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
                    return 1
                fi
                if ! ( allowPort "${portStart}:${portEnd}" udp ); then
                    [[ -z "${addedForwardPorts}" ]] || removeFirewalldForwardPortRange "${portStart}" "${portEnd}" "${targetPort}" "owned=${addedForwardPorts}" >/dev/null 2>&1 || true
                    if [[ "${addedMasquerade}" == "true" ]]; then
                        sudo firewall-cmd --zone=public --permanent --remove-masquerade >/dev/null 2>&1 || true
                    fi
                    sudo firewall-cmd --reload >/dev/null 2>&1 || true
                    protocolPortHoppingStatusCard "端口跳跃开放端口失败，已尝试回滚本次 firewalld 规则"
                    return 1
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
                    return 1
                fi
                if [[ "${addedMasquerade}" == "true" ]] && ! padmFirewallStateAdd masquerade:firewalld; then
                    [[ -z "${addedForwardPorts}" ]] || removeFirewalldForwardPortRange "${portStart}" "${portEnd}" "${targetPort}" "owned=${addedForwardPorts}" >/dev/null 2>&1 || true
                    denyPort "${portStart}:${portEnd}" udp >/dev/null 2>&1 || true
                    padmFirewallStateRemove "${forwardStateKey}" >/dev/null 2>&1 || true
                    sudo firewall-cmd --zone=public --permanent --remove-masquerade >/dev/null 2>&1 || true
                    sudo firewall-cmd --reload >/dev/null 2>&1 || true
                    protocolPortHoppingStatusCard "端口跳跃状态记录失败，已尝试回滚本次 firewalld 规则"
                    return 1
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
    else
        local iptablesRules
        if iptablesRules=$(iptables-save); then
            portHopping=$(awk -v marker="neil1123-vip_${type}_portHopping" '
            $0 ~ marker {
                for (i = 1; i <= NF; i++) {
                    if ($i == "--dport" && (i + 1) <= NF) {
                        print $(i + 1)
                        exit
                    }
                }
            }
            ' <<<"${iptablesRules}")
            portHoppingStart=${portHopping%%:*}
            portHoppingEnd=${portHopping#*:}
        fi
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
        return 1
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

    local selectPortHoppingStatus= actionStatus=0 rangeChanged=
    while true; do
        echoContent title "\n┌─ 端口跳跃 ─────────────────────────────────────────"
        menuItem 1 "添加端口跳跃" "配置 UDP 端口范围转发到当前服务端口"
        menuItem 2 "删除端口跳跃" "移除当前端口跳跃规则"
        menuItem 3 "查看端口跳跃" "显示当前端口跳跃范围"
        menuClose
        selectPortHoppingStatus=
        menuReadChoice port_hopping_menu "请选择:" selectPortHoppingStatus || return 0
        case "${selectPortHoppingStatus}" in
        1)
            addPortHopping "${type}" "${targetPort}" || actionStatus=$?
            break
            ;;
        2)
            if deletePortHoppingRules "${type}" "${portHoppingStart}" "${portHoppingEnd}" "${targetPort}"; then
                protocolPortHoppingStatusCard "删除成功"
            else
                actionStatus=$?
                protocolPortHoppingStatusCard "删除失败，请检查防火墙规则"
            fi
            break
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
    # 取消、重复添加或完整回滚不刷新；规则已变化时，即使后续清理失败也同步订阅。
    readPortHopping "${type}" "${targetPort}" || return 1
    if [[ "${type}" == "hysteria2" ]]; then
        [[ "${portHoppingStart}:${portHoppingEnd}" == "${hysteria2PortHoppingStart}:${hysteria2PortHoppingEnd}" ]] || rangeChanged=true
    elif [[ "${type}" == "tuic" ]]; then
        [[ "${portHoppingStart}:${portHoppingEnd}" == "${tuicPortHoppingStart}:${tuicPortHoppingEnd}" ]] || rangeChanged=true
    fi
    if [[ "${rangeChanged}" == "true" ]] && ! refreshManagedProtocolSubscriptions "${type} 端口跳跃"; then
        protocolPortHoppingStatusCard "端口跳跃规则已变化，但订阅刷新失败，请手动刷新订阅"
        return 1
    fi
    return "${actionStatus}"
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
    local defaultAlgorithm=${tuicAlgorithm:-cubic} selectedAlgorithm=
    case "${defaultAlgorithm}" in
    cubic | bbr | new_reno) ;;
    *)
        errorCard "上次 Tuic 拥塞算法不合法，请重新选择"
        [[ -z "${AUTO_INSTALL:-}" ]] || return 1
        defaultAlgorithm=cubic
        ;;
    esac
    if [[ -n "${tuicAlgorithm:-}" &&
        "${tuicAlgorithm}" == "${defaultAlgorithm}" &&
        ( -n "${lastInstallationConfig:-}" || "${PADM_INSTALL_TUIC_INPUTS_PREPARED:-}" == true ) ]]; then
        tuicAlgorithmStatusCard "${tuicAlgorithm}"
        return 0
    fi

    echoContent title "\n┌─ Tuic 拥塞控制算法 ─────────────────────────────────"
    menuRecommendedItem 1 "cubic" "sing-box 默认算法"
    menuItem 2 "bbr" "高带宽或长距离链路可尝试"
    menuItem 3 "new_reno" "兼容保守拥塞控制"
    menuClose
    while true; do
        menuReadChoice tuic_algorithm_menu "请选择[回车保持 ${defaultAlgorithm}]:" selectedAlgorithm true || return 1
        case "${selectedAlgorithm:-${defaultAlgorithm}}" in
        1 | cubic) tuicAlgorithm=cubic ;;
        2 | bbr) tuicAlgorithm=bbr ;;
        3 | new_reno) tuicAlgorithm=new_reno ;;
        *)
            errorCard "请选择 1、2 或 3"
            [[ -z "${AUTO_INSTALL:-}" ]] || return 1
            continue
            ;;
        esac
        tuicAlgorithmStatusCard "${tuicAlgorithm}"
        return 0
    done
}


# 初始化realityKey
initRealityKey() {
    echoContent title "\n┌─ Reality Key ─────────────────────────────────────"
    menuLine "生成 Reality key"
    menuClose
    if [[ -n "${currentRealityPublicKey}" && -z "${lastInstallationConfig}" ]]; then
        menuReadChoice reality_history_key "读取到上次安装记录，PublicKey为 [${currentRealityPublicKey}]，是否复用上次的PublicKey/PrivateKey？[y/n]:" historyKeyStatus true || return 1
        if [[ "${historyKeyStatus}" == "y" ]]; then
            realityPrivateKey=${currentRealityPrivateKey}
            realityPublicKey=${currentRealityPublicKey}
        fi
    elif [[ -n "${currentRealityPublicKey}" && -n "${lastInstallationConfig}" ]]; then
        realityPrivateKey=${currentRealityPrivateKey}
        realityPublicKey=${currentRealityPublicKey}
    fi
    if [[ -z "${realityPrivateKey}" ]]; then
        if [[ "${selectCoreType:-${coreInstallType:-}}" == "2" ]]; then
            local singBoxBinary="$(coreSingBoxBinaryPath)"
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
            menuReadChoice reality_private_key "请输入Private Key[回车自动生成]:" historyPrivateKey true || return 1
            if [[ -n "${historyPrivateKey}" ]]; then
                realityX25519Key=$("$(coreXrayBinaryPath)" x25519 -i "${historyPrivateKey}") || return 1
            else
                realityX25519Key=$("$(coreXrayBinaryPath)" x25519) || return 1
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
    if [[ "${selectCoreType:-${coreInstallType:-}}" == "2" ]]; then
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
    tlsPingResult=$("$(coreXrayBinaryPath)" tls ping "${target}" 2>/dev/null)
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
                realityMldsa65=$("$(coreXrayBinaryPath)" mldsa65)
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
    local entryHostFile storedEntry= strictDomain=false implicitEntry=false
    realityStrictDomainModeEnabled && strictDomain=true

    if [[ -n "${AUTO_ENTRY_HOST:-}" ]]; then
        realityEntryHost=${AUTO_ENTRY_HOST}
    elif [[ -n "${AUTO_DOMAIN:-}" ]]; then
        realityEntryHost=${AUTO_DOMAIN}
    elif [[ -n "${domain:-}" ]]; then
        realityEntryHost=${domain}
    else
        implicitEntry=true
        realityEntryHost=
        entryHostFile=$(realityEntryHostFile)
        if [[ "${PADM_INSTALL_RESET_HISTORY:-}" != "true" && -f "${entryHostFile}" ]]; then
            storedEntry=$(head -n 1 "${entryHostFile}")
        fi
        if [[ -n "${storedEntry}" ]]; then
            realityEntryHost=${storedEntry}
        elif [[ -n "${currentHost:-}" ]]; then
            realityEntryHost=${currentHost}
        elif [[ "${strictDomain}" != "true" ]]; then
            realityEntryHost=$(getPublicIP)
        fi
    fi

    if [[ "${strictDomain}" == "true" ]]; then
        while ! padmIsValidHostName "${realityEntryHost}" || [[ "${realityEntryHost}" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; do
            if [[ -n "${realityEntryHost}" ]]; then
                errorCard "Reality 入口域名不合法" "${realityEntryHost}"
            elif [[ -n "${AUTO_INSTALL:-}" ]]; then
                errorCard "严格域名 Reality 缺少入口域名，请传 --entry-host 或 --domain"
            fi
            [[ "${implicitEntry}" == "true" && -z "${AUTO_INSTALL:-}" ]] || return 1
            statusCard "Reality 入口域名" "请输入客户端实际连接的域名，回车取消"
            menuReadChoice entry_host "入口域名:" realityEntryHost || return 1
        done
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
        AUTO_REALITY_SERVER_NAME=${AUTO_REALITY_SERVER_NAME:-${realitySNI:-}} \
            parseRealityTargetInput "${realityTargetHost}:${realityTargetPort:-443}" || return 1
    elif [[ -n "${AUTO_INSTALL:-}" ]]; then
        selectionPolicy=auto
        selectAutoRecommendedRealityTarget || return 1
    else
        echoContent title "\n┌─ Reality 伪装目标 ─────────────────────────────────"
        menuLine "entry：客户端连接到你的服务器地址，已在订阅中作为 server/@host 使用"
        menuLine "target：REALITY 伪装访问的外部真实 HTTPS 站点，写入服务端握手配置"
        menuLine "SNI：REALITY 握手域名，默认等于 target host；除非明确知道原因，不要单独改"
        menuLine "候选列表仅展示 cdn_risk=no 的实测 A 级结果，不推荐 B/C 级备选"
        menuLine "PQC/ML-DSA-65 场景需要目标站支持 X25519MLKEM768 且证书链足够长"
        menuClose
        echoContent title "┌─ REALITY 目标站选择 ───────────────────────────────"
        menuItem 1 "检测候选后选择" "先检测全部候选，再从 A 级结果中选择"
        menuItem 2 "手动输入" "输入 host 或 host:port，端口默认 443"
        menuClose
        while true; do
            menuReadChoice reality_target_mode "请选择[默认1]:" selectRealityTargetMode true || return 1
            case "${selectRealityTargetMode:-1}" in
            1)
                selectRealityTargetCandidateInteractive detect-first || return 1
                ;;
            2)
                menuReadChoice reality_target "请输入REALITY伪装目标 host[:port]，默认端口443[回车取消]:" targetInput || return 1
                parseRealityTargetInput "${targetInput}" || return 1
                ;;
            *)
                errorCard "选择错误"
                continue
                ;;
            esac
            break
        done
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

realityInstallProfileKey() {
    printf '%q\n' "${realityTargetHost:-}" "${realityTargetPort:-443}" "${realitySNI:-}" "${realityEntryHost:-}" \
        "${AUTO_REALITY_TARGET:-}" "${AUTO_REALITY_SERVER_NAME:-}" "${AUTO_ENTRY_HOST:-}" \
        "${AUTO_DOMAIN:-}" "${AUTO_REALITY_DOMAIN:-}" "${domain:-}" "${realityOnlyWithDomain:-}" \
        "${selectCoreType:-}" "${coreInstallType:-}" "${selectCustomInstallType:-}"
}

# 初始化REALITY配置
initRealityProfile() {
    local profileKey
    if [[ -n "${PADM_INSTALL_REALITY_PROFILE_CACHE+x}" ]]; then
        profileKey=$(realityInstallProfileKey) || return 1
        # 仅本次完整安装复用成功检测，参数变化或失败后必须重新验证。
        [[ -z "${PADM_INSTALL_REALITY_PROFILE_CACHE}" || "${PADM_INSTALL_REALITY_PROFILE_CACHE}" != "${profileKey}" ]] || return 0
        PADM_INSTALL_REALITY_PROFILE_CACHE=
    fi
    collectRealityProfile || return 1
    if realityStrictDomainModeEnabled; then
        checkDNSIP "${realityEntryHost}" || return 1
    fi
    if [[ -n "${PADM_INSTALL_REALITY_PROFILE_CACHE+x}" ]]; then
        PADM_INSTALL_REALITY_PROFILE_CACHE=$(realityInstallProfileKey) || return 1
    fi
    return 0
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

# 本次 Xray 的公网 TCP 监听也不能与固定回落后端重叠。
xrayInstallPortAvailable() {
    declare -p xrayInstallListeners >/dev/null 2>&1 || return 0
    local port=$((10#$1))
    [[ -n "${xrayInstallListeners[${port}]:-}" ]] || return 0
    errorCard "${port}/tcp 已用于本次安装的 ${xrayInstallListeners[${port}]}，请选择不同端口"
    return 1
}

# 与模板顺序一致，只采集输入，不停止服务或开放防火墙。
prepareXrayInstallInputs() {
    local mode=custom entry protocolId portVar
    local -A xrayInstallListeners=()
    [[ -n "${selectCustomInstallType:-}" ]] || mode=all
    for entry in 1:45987 21:31297 22:31299 23:31306 24:31301 25:31304 29:31296; do
        protocolSelectionIncludes "${selectCustomInstallType:-}" "${entry%%:*}" "${mode}" || continue
        xrayInstallListeners[${entry#*:}]="协议 ${entry%%:*} 固定后端"
    done
    if [[ "${mode}" == all ]] || protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"; then
        xrayInstallListeners[31300]="Nginx 回落后端"
        xrayInstallListeners[31302]="Nginx HTTP/2 后端"
        readInstallTLSPort || return 1
        AUTO_PORT=${port}
        xrayInstallListeners[$((10#${port}))]="TLS 入口"
    fi
    for entry in 2:xHTTPort 1:realityPort 26:realityGrpcPort; do
        protocolId=${entry%%:*}
        portVar=${entry#*:}
        protocolSelectionIncludes "${selectCustomInstallType:-}" "${protocolId}" "${mode}" || continue
        case "${protocolId}" in
        2) initXrayXHTTPort true || return 1 ;;
        1) initXrayRealityPort true || return 1 ;;
        26) initXrayRealityGrpcPort true || return 1 ;;
        esac
        xrayInstallListeners[${!portVar}]="协议 ${protocolId} 入口"
    done
}

initXrayRealityProtocolPort() {
    local -n portRef=$1
    local historyPort=${2:-}
    local protocolId=$3
    local promptKey=$4
    local label=$5
    local transport=${6:-tcp}
    local streamProtocol=${7:-}
    local inputsOnly=${8:-false}
    local coexistStatus=1 singleProtocol=false
    local AUTO_PORT="${AUTO_PORT:-}"

    protocolSelectionIsExactly "${selectCustomInstallType:-}" "${protocolId}" && singleProtocol=true
    [[ "${singleProtocol}" == true ]] || AUTO_PORT=
    if [[ -n "${streamProtocol}" ]]; then
        if resolveRealityInstallCoexistPort portRef "${streamProtocol}" "${label}"; then
            coexistStatus=0
        else
            coexistStatus=$?
            [[ "${coexistStatus}" == "2" ]] && return 1
        fi
    fi

    if [[ -n "${historyPort}" && -z "${AUTO_INSTALL:-}" &&
        ( "${singleProtocol}" != true || -z "${AUTO_PORT:-}" ) ]] &&
        ! validPortNumber "${historyPort}"; then
        errorCard "${label} 上次端口不合法，请重新输入"
        [[ "${portRef}" != "${historyPort}" ]] || portRef=
        historyPort=
    fi
    if [[ "${coexistStatus}" != "0" && "${singleProtocol}" == "true" && -n "${AUTO_PORT:-}" ]]; then
        portRef=${AUTO_PORT}
    elif [[ "${coexistStatus}" != "0" && -z "${portRef}" && -n "${historyPort}" ]]; then
        if [[ -n "${lastInstallationConfig:-}" || ( "${singleProtocol}" == "true" && -n "${AUTO_INSTALL:-}" ) ]]; then
            portRef=${historyPort}
        fi
    fi
    if validPortNumber "${portRef}" && ! xrayInstallPortAvailable "${portRef}"; then
        [[ -z "${AUTO_INSTALL:-}" && "${coexistStatus}" != 0 &&
            ( "${singleProtocol}" != true || -z "${AUTO_PORT:-}" ) ]] || return 1
        portRef=
        historyPort=
    fi

    if [[ -z "${portRef}" ]]; then
        local defaultPort=${historyPort} prompt
        if [[ -n "${defaultPort}" ]]; then
            prompt="${label} 连接端口[回车保留 ${defaultPort}]:"
        elif [[ "${singleProtocol}" == "true" ]]; then
            defaultPort=443
            prompt="${label} 连接端口[回车默认 443]:"
        else
            prompt="${label} 连接端口[回车随机 10000-30000]:"
        fi
        [[ "${singleProtocol}" == "true" ]] || promptKey="${promptKey}_subport"
        while true; do
            menuReadChoice "${promptKey}" "${prompt}" portRef true || return 1
            portRef=${portRef:-${defaultPort:-$((RANDOM % 20001 + 10000))}}
            if validPortNumber "${portRef}"; then
                xrayInstallPortAvailable "${portRef}" && break
            else
                errorCard "${label} 端口输入错误"
            fi
            portRef=
            [[ -z "${AUTO_INSTALL:-}" ]] || return 1
        done
    fi

    if ! validPortNumber "${portRef}"; then
        errorCard "${label} 端口输入错误"
        return 1
    fi
    portRef=$((10#${portRef}))
    [[ "${inputsOnly}" != true ]] || return 0
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
    initXrayRealityProtocolPort realityPort "${xrayVLESSRealityPort:-}" 1 reality_port "Reality" tcp vision "${1:-false}"
}

initXrayRealityGrpcPort() {
    initXrayRealityProtocolPort realityGrpcPort "${xrayVLESSRealityGRPCPort:-}" 26 reality_port "Reality gRPC" tcp "" "${1:-false}"
}

initXrayXHTTPort() {
    initXrayRealityProtocolPort xHTTPort "${xrayVLESSRealityXHTTPort:-}" 2 xhttp_port "Reality XHTTP" tcp+udp xhttp "${1:-false}"
}
