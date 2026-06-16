#!/usr/bin/env bash

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
    if [[ -z ${hysteriaPort} ]]; then
        statusCard "端口输入" "端口不可为空"
        initHysteriaPort "$2"
    elif ((hysteriaPort < 1 || hysteriaPort > 65535)); then
        statusCard "端口输入" "端口不合法"
        initHysteriaPort "$2"
    fi
    allowPort "${hysteriaPort}" || return 1
    allowPort "${hysteriaPort}" "udp" || return 1
}


# 初始化 Hysteria2 网络信息
initHysteria2Network() {

    echoContent yellow "请输入本地带宽峰值的下行速度（默认：100，单位：Mbps）"
    autoRead hysteria_download_speed "下行速度:" hysteria2ClientDownloadSpeed
    if [[ -z "${hysteria2ClientDownloadSpeed}" ]]; then
        hysteria2ClientDownloadSpeed=100
        statusCard "Hysteria2 下行速度" "${hysteria2ClientDownloadSpeed} Mbps"
    fi

    echoContent yellow "请输入本地带宽峰值的上行速度（默认：50，单位：Mbps）"
    autoRead hysteria_upload_speed "上行速度:" hysteria2ClientUploadSpeed
    if [[ -z "${hysteria2ClientUploadSpeed}" ]]; then
        hysteria2ClientUploadSpeed=50
        statusCard "Hysteria2 上行速度" "${hysteria2ClientUploadSpeed} Mbps"
    fi
}


# firewalld 端口跳跃规则
addFirewalldPortHopping() {

    local start=$1
    local end=$2
    local targetPort=$3
    local port
    local addedPorts=
    for port in $(seq "$start" "$end"); do
        if sudo firewall-cmd --permanent --add-forward-port=port="${port}":proto=udp:toport="${targetPort}"; then
            addedPorts="${addedPorts} ${port}"
        else
            for port in ${addedPorts}; do
                sudo firewall-cmd --permanent --remove-forward-port=port="${port}":proto=udp:toport="${targetPort}" >/dev/null 2>&1 || true
            done
            sudo firewall-cmd --reload >/dev/null 2>&1 || true
            return 1
        fi
    done
    if ! sudo firewall-cmd --reload; then
        for port in ${addedPorts}; do
            sudo firewall-cmd --permanent --remove-forward-port=port="${port}":proto=udp:toport="${targetPort}" >/dev/null 2>&1 || true
        done
        sudo firewall-cmd --reload >/dev/null 2>&1 || true
        return 1
    fi
}

portHoppingPersistIptablesRules() {
    if command -v netfilter-persistent >/dev/null 2>&1; then
        sudo netfilter-persistent save >/dev/null 2>&1
        return $?
    fi
    return 2
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
        statusCard "端口跳跃" "已添加不可重复添加，可删除后重新添加"
        exit 0
    fi
    if [[ "${rhelLike:-}" == "true" ]]; then
        if ! systemctl status firewalld 2>/dev/null | grep -q "active (running)"; then
            statusCard "端口跳跃" "未启动 firewalld 防火墙，无法设置端口跳跃"
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
        statusCard "端口跳跃范围" "范围不可为空"
        addPortHopping "${type}" "${targetPort}"
    elif [[ "${portHoppingRange}" == *-* ]]; then

        local portStart=
        local portEnd=
        portStart=${portHoppingRange%%-*}
        portEnd=${portHoppingRange#*-}

        if [[ -z "${portStart}" || -z "${portEnd}" ]]; then
            statusCard "端口跳跃范围" "范围不合法"
            addPortHopping "${type}" "${targetPort}"
        elif ((portStart < 30000 || portStart > 40000 || portEnd < 30000 || portEnd > 40000 || portEnd < portStart)); then
            statusCard "端口跳跃范围" "范围不合法"
            addPortHopping "${type}" "${targetPort}"
        else
            statusCard "端口跳跃范围" "${portHoppingRange}"
            if [[ "${rhelLike:-}" == "true" ]] && systemctl is-active --quiet firewalld; then
                local addedMasquerade=
                if ! sudo firewall-cmd --query-masquerade --permanent >/dev/null 2>&1; then
                    addedMasquerade=true
                fi
                if ! sudo firewall-cmd --permanent --add-masquerade || ! sudo firewall-cmd --reload || ! addFirewalldPortHopping "${portStart}" "${portEnd}" "${targetPort}" || ! sudo firewall-cmd --list-forward-ports | grep -q "toport=${targetPort}"; then
                    for port in $(seq "${portStart}" "${portEnd}"); do
                        sudo firewall-cmd --permanent --remove-forward-port=port="${port}":proto=udp:toport="${targetPort}" >/dev/null 2>&1 || true
                    done
                    if [[ "${addedMasquerade}" == "true" ]]; then
                        sudo firewall-cmd --permanent --remove-masquerade >/dev/null 2>&1 || true
                    fi
                    sudo firewall-cmd --reload >/dev/null 2>&1 || true
                    statusCard "端口跳跃" "端口跳跃添加失败，已尝试回滚本次 firewalld 规则"
                    exit 1
                fi
                if ! ( allowPort "${portStart}:${portEnd}" udp ); then
                    for port in $(seq "${portStart}" "${portEnd}"); do
                        sudo firewall-cmd --permanent --remove-forward-port=port="${port}":proto=udp:toport="${targetPort}" >/dev/null 2>&1 || true
                    done
                    if [[ "${addedMasquerade}" == "true" ]]; then
                        sudo firewall-cmd --permanent --remove-masquerade >/dev/null 2>&1 || true
                    fi
                    sudo firewall-cmd --reload >/dev/null 2>&1 || true
                    statusCard "端口跳跃" "端口跳跃开放端口失败，已尝试回滚本次 firewalld 规则"
                    exit 1
                fi
            else
                if ! iptables -t nat -A PREROUTING -p udp --dport "${portStart}:${portEnd}" -m comment --comment "neil1123-vip_${type}_portHopping" -j DNAT --to-destination ":${targetPort}"; then
                    iptables -t nat -D PREROUTING -p udp --dport "${portStart}:${portEnd}" -m comment --comment "neil1123-vip_${type}_portHopping" -j DNAT --to-destination ":${targetPort}" >/dev/null 2>&1 || true
                    statusCard "端口跳跃" "端口跳跃添加失败，已尝试回滚本次 iptables 规则"
                    exit 1
                fi
                local persistStatus=0
                if portHoppingPersistIptablesRules; then
                    persistStatus=0
                else
                    persistStatus=$?
                fi
                if [[ "${persistStatus}" == "1" ]]; then
                    iptables -t nat -D PREROUTING -p udp --dport "${portStart}:${portEnd}" -m comment --comment "neil1123-vip_${type}_portHopping" -j DNAT --to-destination ":${targetPort}" >/dev/null 2>&1 || true
                    portHoppingPersistIptablesRules >/dev/null 2>&1 || true
                    statusCard "端口跳跃" "端口跳跃添加失败，已尝试回滚本次 iptables 规则"
                    exit 1
                fi
                if ! iptables-save | grep -q "neil1123-vip_${type}_portHopping"; then
                    statusCard "端口跳跃" "端口跳跃添加失败"
                    exit 0
                fi
                allowPort "${portStart}:${portEnd}" udp || return 1
                if [[ "${persistStatus}" == "2" ]]; then
                    portHoppingWarnIptablesNotPersistent
                fi
            fi
            statusCard "端口跳跃" "端口跳跃添加成功"
        fi
    fi
}


# 读取端口跳跃的配置
readPortHopping() {
    local type=$1
    local targetPort=$2
    local portHoppingStart=
    local portHoppingEnd=
    local portHopping=

    if [[ "${rhelLike:-}" == "true" ]] && systemctl is-active --quiet firewalld; then
        portHoppingStart=$(sudo firewall-cmd --list-forward-ports | grep "toport=${targetPort}" | head -1 | cut -d ":" -f 1 | cut -d "=" -f 2)
        portHoppingEnd=$(sudo firewall-cmd --list-forward-ports | grep "toport=${targetPort}" | tail -n 1 | cut -d ":" -f 1 | cut -d "=" -f 2)
    else
        if iptables-save | grep -q "neil1123-vip_${type}_portHopping"; then
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

    if [[ "${rhelLike:-}" == "true" ]] && systemctl is-active --quiet firewalld; then
        for port in $(seq "${start}" "${end}"); do
            sudo firewall-cmd --permanent --remove-forward-port=port="${port}":proto=udp:toport="${targetPort}"
        done
        sudo firewall-cmd --reload
    else
        local -a ruleLines=()
        mapfile -t ruleLines < <(iptables -t nat -L PREROUTING --line-numbers | awk -v marker="neil1123-vip_${type}_portHopping" '$0 ~ marker { print $1 }' | sort -rn)
        for line in "${ruleLines[@]}"; do
            [[ -n "${line}" ]] || continue
            iptables -t nat -D PREROUTING "${line}"
        done
        portHoppingPersistIptablesRules >/dev/null 2>&1 || true
    fi
}


# 端口跳跃管理
portHoppingMenu() {
    local type=$1
    # 判断iptables是否存在
    if ! find /usr/bin /usr/sbin | grep -q -w iptables; then
        statusCard "端口跳跃" "无法识别 iptables 工具，无法使用端口跳跃，退出安装"
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

    echoContent title "\n┌─ 端口跳跃 ─────────────────────────────────────────"
    menuItem 1 "添加端口跳跃" "配置 UDP 端口范围转发到当前服务端口"
    menuItem 2 "删除端口跳跃" "移除当前端口跳跃规则"
    menuItem 3 "查看端口跳跃" "显示当前端口跳跃范围"
    menuClose
    autoRead port_hopping_menu "请选择:" selectPortHoppingStatus
    if [[ "${selectPortHoppingStatus}" == "1" ]]; then
        addPortHopping "${type}" "${targetPort}"
    elif [[ "${selectPortHoppingStatus}" == "2" ]]; then
        deletePortHoppingRules "${type}" "${portHoppingStart}" "${portHoppingEnd}" "${targetPort}"
        statusCard "端口跳跃" "删除成功"
    elif [[ "${selectPortHoppingStatus}" == "3" ]]; then
        if [[ -n "${portHoppingStart}" && -n "${portHoppingEnd}" ]]; then
            statusCard "端口跳跃" "当前端口跳跃范围为: ${portHoppingStart}-${portHoppingEnd}"
        else
            statusCard "端口跳跃" "未设置端口跳跃"
        fi
    else
        portHoppingMenu
    fi
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
    if [[ -z ${tuicPort} ]]; then
        statusCard "端口输入" "端口不可为空"
        initTuicPort "$2"
    elif ((tuicPort < 1 || tuicPort > 65535)); then
        statusCard "端口输入" "端口不合法"
        initTuicPort "$2"
    fi
    statusCard "Tuic 端口" "${tuicPort}"
    allowPort "${tuicPort}" || return 1
    allowPort "${tuicPort}" "udp" || return 1
}


# 初始化 TUIC 协议参数
initTuicProtocol() {
    if [[ -n "${tuicAlgorithm}" && -z "${lastInstallationConfig}" ]]; then
        autoRead tuic_history_algorithm "读取到上次使用的算法 [${tuicAlgorithm}]，是否使用？[y/n]:" historyTuicAlgorithm
        if [[ "${historyTuicAlgorithm}" != "y" ]]; then
            tuicAlgorithm=
        else
            statusCard "Tuic 算法" "${tuicAlgorithm}"
        fi
    elif [[ -n "${tuicAlgorithm}" && -n "${lastInstallationConfig}" ]]; then
        statusCard "Tuic 算法" "${tuicAlgorithm}"
    fi

    if [[ -z "${tuicAlgorithm}" ]]; then

        echoContent title "\n┌─ Tuic 拥塞控制算法 ─────────────────────────────────"
        menuRecommendedItem 1 "cubic" "sing-box 默认算法"
        menuItem 2 "bbr" "高带宽或长距离链路可尝试"
        menuItem 3 "new_reno" "兼容保守拥塞控制"
        menuClose
        autoRead tuic_algorithm_menu "请选择:" selectTuicAlgorithm
        case ${selectTuicAlgorithm} in
        1)
            tuicAlgorithm="cubic"
            ;;
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
        statusCard "Tuic 算法" "${tuicAlgorithm}"
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
            realityX25519Key=$(/etc/padm/sing-box/sing-box generate reality-keypair)
            realityPrivateKey=$(echo "${realityX25519Key}" | head -1 | awk '{print $2}')
            realityPublicKey=$(echo "${realityX25519Key}" | tail -n 1 | awk '{print $2}')
            echo "publicKey:${realityPublicKey}" >/etc/padm/sing-box/conf/config/reality_key
        else
            autoRead reality_private_key "请输入Private Key[回车自动生成]:" historyPrivateKey
            if [[ -n "${historyPrivateKey}" ]]; then
                realityX25519Key=$(/etc/padm/xray/xray x25519 -i "${historyPrivateKey}")
            else
                realityX25519Key=$(/etc/padm/xray/xray x25519)
            fi
            realityPrivateKey=$(echo "${realityX25519Key}" | grep "PrivateKey" | awk '{print $2}')
            realityPublicKey=$(echo "${realityX25519Key}" | grep "Password" | awk '{print $3}')
            if [[ -z "${realityPrivateKey}" ]]; then
                statusCard "Reality Key" "输入的 Private Key 不合法"
                initRealityKey
            else
                statusCard "Reality Key" "privateKey:${realityPrivateKey}" "publicKey:${realityPublicKey}"
            fi
        fi
    fi
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

# 检查reality域名是否符合
checkRealityDest() {
    local traceResult=
    traceResult=$(curl -s "https://$(echo "${realityDestDomain}" | cut -d ':' -f 1)/cdn-cgi/trace" | grep "visit_scheme=https")
    if [[ -n "${traceResult}" ]]; then
        statusCard "Reality 目标站风险" "检测到目标域名托管在 Cloudflare 且已开启代理" "使用此类型域名可能导致 VPS 流量被其他人使用" "不建议继续使用该目标站"
        autoRead reality_cloudflare_target_confirm "是否继续？[y/n]" setRealityDestStatus
        if [[ "${setRealityDestStatus}" != 'y' ]]; then
            exit 0
        fi
        statusCard "Reality 目标站风险确认" "已忽略风险，继续使用"
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
    [[ -n "${targetHost}" && "${targetPort}" =~ ^[0-9]+$ && ${targetPort} -ge 1 && ${targetPort} -le 65535 ]]
}

collectTLSProfile() {
    tlsEnabled=true
    if [[ -n "${domain:-}" ]]; then
        tlsCertDomain=${domain%%:*}
    elif [[ -n "${currentHost:-}" ]]; then
        tlsCertDomain=${currentHost}
    else
        tlsCertDomain=
    fi
    tlsSNI=${tlsCertDomain}
    tlsCertFile="/etc/padm/tls/${tlsCertDomain}.crt"
    tlsKeyFile="/etc/padm/tls/${tlsCertDomain}.key"
}

collectEntryProfile() {
    if [[ -n "${AUTO_ENTRY_HOST:-}" ]]; then
        realityEntryHost=${AUTO_ENTRY_HOST}
    elif [[ -n "${domain:-}" ]]; then
        realityEntryHost=${domain%%:*}
    elif [[ -n "${currentHost:-}" ]]; then
        realityEntryHost=${currentHost}
    else
        realityEntryHost=$(getPublicIP)
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

    collectEntryProfile

    if [[ -n "${AUTO_REALITY_TARGET:-}" ]]; then
        parseRealityTargetInput "${AUTO_REALITY_TARGET}" || return 1
        printRealityTargetProfile
        return 0
    elif [[ -n "${realityTargetHost:-}" ]]; then
        parseRealityTargetInput "${realityTargetHost}:${realityTargetPort:-443}" || return 1
        printRealityTargetProfile
        return 0
    fi

    echoContent title "\n┌─ Reality 伪装目标 ─────────────────────────────────"
    menuLine "entry：客户端连接到你的服务器地址，已在订阅中作为 server/@host 使用"
    menuLine "target：REALITY 伪装访问的外部真实 HTTPS 站点，写入服务端握手配置"
    menuLine "SNI：REALITY 握手域名，默认等于 target host；除非明确知道原因，不要单独改"
    menuLine "自动推荐会优先使用实测结果，无结果时回退 www.ibm.com:443"
    menuLine "PQC/ML-DSA-65 场景需要目标站支持 X25519MLKEM768 且证书链足够长"
    menuClose
    echoContent title "┌─ REALITY 目标站选择 ───────────────────────────────"
    menuRecommendedItem 1 "自动推荐" "优先使用实测结果；无结果则 www.ibm.com:443"
    menuItem 2 "候选列表" "从内置结构化候选池选择"
    menuItem 3 "手动输入" "输入 host 或 host:port，端口默认 443"
    menuItem 4 "随机候选" "从内置候选池随机选择一个目标"
    menuClose
    autoRead reality_target_mode "请选择[默认1]:" selectRealityTargetMode
    selectRealityTargetMode=${selectRealityTargetMode:-1}

    case "${selectRealityTargetMode}" in
    1)
        selectDefaultRealityTarget
        ;;
    2)
        if ! selectRealityTargetFromCandidates; then
            statusCard "Reality 目标站" "候选编号无效，改用默认目标 www.ibm.com:443"
            selectDefaultRealityTarget
        fi
        ;;
    3)
        autoRead reality_target "请输入REALITY伪装目标域名，默认端口443:" targetInput
        if [[ -z "${targetInput}" ]]; then
            selectDefaultRealityTarget
        else
            parseRealityTargetInput "${targetInput}" || return 1
        fi
        ;;
    4)
        selectRandomRealityTargetCandidate
        ;;
    *)
        selectDefaultRealityTarget
        ;;
    esac

    if [[ "${realityTargetHost}" =~ ^[0-9.]+$ && -z "${AUTO_REALITY_SERVER_NAME:-}" ]]; then
        statusCard "Reality SNI 提醒" "目标站是 IP" "建议在高级场景手动指定 --reality-server-name" "或确认客户端 SNI 行为"
    fi
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
    persistRealityEntryProfile || return 1
}


# 初始化reality端口
initXrayRealityPort() {
    if [[ -n "${xrayVLESSRealityPort}" && -z "${lastInstallationConfig}" ]]; then
        autoRead reality_history_port "读取到上次安装记录，Reality端口为 [${xrayVLESSRealityPort}]，是否使用？[y/n]:" historyRealityPortStatus
        if [[ "${historyRealityPortStatus}" == "y" ]]; then
            realityPort=${xrayVLESSRealityPort}
        fi
    elif [[ -n "${xrayVLESSRealityPort}" && -n "${lastInstallationConfig}" ]]; then
        realityPort=${xrayVLESSRealityPort}
    fi

    if [[ -z "${realityPort}" ]]; then
        echoContent yellow "请输入端口[回车随机10000-30000]"

        autoRead reality_port "端口:" realityPort
        if [[ -z "${realityPort}" ]]; then
            realityPort=$((RANDOM % 20001 + 10000))
        fi
        if ! validPortNumber "${realityPort}"; then
            errorCard "Reality 端口输入错误"
            return 1
        fi
        if [[ -n "${realityPort}" && "${xrayVLESSRealityPort}" == "${realityPort}" ]]; then
            if ! runCoreServiceActionAllowFailure handleXray stop; then
                errorCard "Xray 服务停止失败，无法复用当前 Reality 端口"
                return 1
            fi
        else
            checkPort "${realityPort}" || return 1
        fi
    fi
    if [[ -z "${realityPort}" ]]; then
        initXrayRealityPort || return 1
    else
        if ! validPortNumber "${realityPort}"; then
            errorCard "Reality 端口输入错误"
            return 1
        fi
        allowPort "${realityPort}" || return 1
        statusCard "Reality 端口" "${realityPort}"
    fi

}

# 初始化XHTTP端口
initXrayXHTTPort() {
    if [[ -n "${xrayVLESSRealityXHTTPort}" && -z "${lastInstallationConfig}" ]]; then
        autoRead xhttp_history_port "读取到上次安装记录，Reality XHTTP端口为 [${xrayVLESSRealityXHTTPort}]，是否使用？[y/n]:" historyXHTTPortStatus
        if [[ "${historyXHTTPortStatus}" == "y" ]]; then
            xHTTPort=${xrayVLESSRealityXHTTPort}
        fi
    elif [[ -n "${xrayVLESSRealityXHTTPort}" && -n "${lastInstallationConfig}" ]]; then
        xHTTPort=${xrayVLESSRealityXHTTPort}
    fi

    if [[ -z "${xHTTPort}" ]]; then

        echoContent yellow "请输入端口[回车随机10000-30000]"
        autoRead xhttp_port "端口:" xHTTPort
        if [[ -z "${xHTTPort}" ]]; then
            xHTTPort=$((RANDOM % 20001 + 10000))
        fi
        if ! validPortNumber "${xHTTPort}"; then
            errorCard "Reality XHTTP 端口输入错误"
            return 1
        fi
        if [[ -n "${xHTTPort}" && "${xrayVLESSRealityXHTTPort}" == "${xHTTPort}" ]]; then
            if ! runCoreServiceActionAllowFailure handleXray stop; then
                errorCard "Xray 服务停止失败，无法复用当前 Reality XHTTP 端口"
                return 1
            fi
        else
            checkPort "${xHTTPort}" || return 1
        fi
    fi
    if [[ -z "${xHTTPort}" ]]; then
        initXrayXHTTPort || return 1
    else
        if ! validPortNumber "${xHTTPort}"; then
            errorCard "Reality XHTTP 端口输入错误"
            return 1
        fi
        allowPort "${xHTTPort}" || return 1
        allowPort "${xHTTPort}" "udp" || return 1
        statusCard "Reality XHTTP 端口" "${xHTTPort}"
    fi
}


# 初始化TCP Brutal
initTCPBrutal() {
    echoContent title "\n┌─ 初始化 TCP Brutal ────────────────────────────────"
    menuLine "进度 $2/${totalProgress}"
    menuClose
    autoRead tcp_brutal_enable "是否使用TCP_Brutal？[y/n]:" tcpBrutalStatus
    if [[ "${tcpBrutalStatus}" == "y" ]]; then
        autoRead tcp_brutal_download_speed "请输入本地带宽峰值的下行速度（默认：100，单位：Mbps）:" tcpBrutalClientDownloadSpeed
        if [[ -z "${tcpBrutalClientDownloadSpeed}" ]]; then
            tcpBrutalClientDownloadSpeed=100
        fi

        autoRead tcp_brutal_upload_speed "请输入本地带宽峰值的上行速度（默认：50，单位：Mbps）:" tcpBrutalClientUploadSpeed
        if [[ -z "${tcpBrutalClientUploadSpeed}" ]]; then
            tcpBrutalClientUploadSpeed=50
        fi
    fi
}
