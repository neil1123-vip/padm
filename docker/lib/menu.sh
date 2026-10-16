#!/usr/bin/env bash

if [[ "${PADM_DOCKER_MENU_LOADED:-}" == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_MENU_LOADED=1
DOCKER_MENU_CHILD_PID=
DOCKER_MENU_SIGNAL=0

dockerMenuTerminateTree() {
    local pid=$1 task child
    local -a children=() taskChildren=()
    # 首配与菜单共用前台组，只终止该 CLI 的后代，避免误杀菜单所在组。
    for task in /proc/"${pid}"/task/*; do
        [[ -r "${task}/children" ]] || continue
        taskChildren=()
        IFS=' ' read -r -a taskChildren <"${task}/children" 2>/dev/null || true
        children+=("${taskChildren[@]}")
    done
    kill -TERM "${pid}" 2>/dev/null || true
    for child in "${children[@]}"; do
        [[ "${child}" =~ ^[0-9]+$ ]] || continue
        dockerMenuTerminateTree "${child}"
    done
}

dockerMenuInterrupted() {
    DOCKER_MENU_SIGNAL=$1
    if [[ -n "${DOCKER_MENU_CHILD_PID}" ]]; then
        if ! kill -TERM -- "-${DOCKER_MENU_CHILD_PID}" 2>/dev/null &&
            kill -0 "${DOCKER_MENU_CHILD_PID}" 2>/dev/null; then
            dockerMenuTerminateTree "${DOCKER_MENU_CHILD_PID}"
        fi
        wait "${DOCKER_MENU_CHILD_PID}" 2>/dev/null || true
    fi
    [[ -z "${DOCKER_MENU_STATUS_FILE:-}" ]] || rm -f -- "${DOCKER_MENU_STATUS_FILE}"
    if [[ "$1" -eq 143 ]]; then
        exit 143
    fi
    printf '\n'
}

dockerMenuCli() {
    local root cli
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerRequireInstalledBundle || return "${PADM_DOCKER_RC_STATE}"
    cli="${PADM_DOCKER_BIN_DIR:-/usr/local/bin}/padm-docker"
    dockerPathIsSafeAbsolute "${cli}" &&
        [[ -L "${cli}" && -f "${cli}" && -O "${cli}" &&
            "$(readlink -- "${cli}")" == "${root}/bundle/install-docker.sh" ]] || {
        dockerError 'padm-docker 命令链接缺失或不属于当前部署，请重新安装控制命令'
        return "${PADM_DOCKER_RC_STATE}"
    }
    printf '%s\n' "${cli}"
}

dockerMenuRun() {
    local cli status=0 monitorEnabled=0 setupMode=0
    cli=$(dockerMenuCli) || return $?
    # 子进程从已安装 bundle 读取合同，不继承菜单中的锁和候选配置。
    # 独立进程组便于中断整个动作，包括 CLI 正在等待的 Docker 命令。
    [[ $- != *m* ]] || monitorEnabled=1
    if [[ "${1:-}" == setup || "${1:-}" == reinstall || "${1:-}" == edit ||
        "${1:-}" == up || "${1:-}" == restart || "${1:-}" == update || "${1:-}" == rollback ||
        ( "${1:-}" == fail2ban && ( "${2:-}" == disable ||
          "${2:-}" == enable || "${2:-}" == settings ||
          ( ( "${2:-}" == control || "${2:-}" == ssh ) && ( "${3:-}" == disable ||
            "${3:-}" == enable || "${3:-}" == settings ) ) ) ) ||
        ( "${1:-}" == business && "${2:-}" == restore ) ||
        ( "${1:-}" == account && "${2:-}" != list ) ||
        ( ( "${1:-}" == subscription || "${1:-}" == share ) &&
          "${2:-}" != list && "${2:-}" != content && "${2:-}" != links ) ||
        ( "${1:-}" == tls && "${2:-}" == manage ) ||
        ( "${1:-}" == control && "${2:-}" != status ) ||
        ( "${1:-}" == protocol && ( "${2:-}" == select-target ||
          "${2:-}" == scan-targets || "${2:-}" == scan-targets-asn ) ) ]]; then
        # 配置与启动来源输入必须共用前台进程组，否则后台 read 会收到 SIGTTIN。
        setupMode=1
        set +m
    else
        set -m
    fi
    DOCKER_MENU_SIGNAL=0
    bash "${cli}" "$@" <&0 &
    DOCKER_MENU_CHILD_PID=$!
    if [[ "${setupMode}" -eq 0 && "$(jobs -p %+)" != "${DOCKER_MENU_CHILD_PID}" ]]; then
        dockerError '无法建立菜单动作独立进程组'
        kill -TERM "${DOCKER_MENU_CHILD_PID}" 2>/dev/null || true
        wait "${DOCKER_MENU_CHILD_PID}" 2>/dev/null || true
        DOCKER_MENU_CHILD_PID=
        [[ "${monitorEnabled}" -eq 1 ]] || set +m
        return "${PADM_DOCKER_RC_STATE}"
    fi
    wait "${DOCKER_MENU_CHILD_PID}" || status=$?
    if [[ "${monitorEnabled}" -eq 1 ]]; then
        set -m
    else
        set +m
    fi
    if [[ "${DOCKER_MENU_SIGNAL}" -ne 0 ]]; then
        wait "${DOCKER_MENU_CHILD_PID}" 2>/dev/null || true
        status=${DOCKER_MENU_SIGNAL}
    fi
    DOCKER_MENU_CHILD_PID=
    if [[ "${status}" -ne 0 && "${status}" -ne 130 ]]; then
        dockerError "操作失败，退出码: ${status}"
    fi
    return "${status}"
}

dockerMenuInstall() {
    local choice specFile
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 安装与重装\n'
        printf '%s\n' '1. 首次配置' '2. 重新选择核心与协议' '3. 从完整规格重装' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun setup || true ;;
        2) dockerMenuRun reinstall || true ;;
        3)
            dockerSetupRead specFile '完整规格文件绝对路径（0 返回）: ' &&
                [[ -n "${specFile}" ]] || continue
            dockerMenuRun reinstall --spec "${specFile}" || true
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuProtocols() {
    local choice listener protocol port core backend tls
    local -a coreArgs
    dockerMenuRun protocol list || true
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 协议与入口\n'
        printf '%s\n' '1. 查看入口' '2. 查看分享链接' '3. 编辑参数/复制或删除入口' '4. 重生成 Reality 参数' '5. Reality 目标站管理' '6. Reality 443 共存' '7. 分享订阅管理' '8. 额外入口端口' '9. CDN 连接地址' '10. XHTTP 管理' '11. 端口跳跃（双族 Hy2/TUIC；TUIC 仅范围转发）' '12. Hysteria2 管理' '13. TUIC 管理' '14. 增量安装协议入口' '15. 删除协议入口' '16. 保留参数重建' '17. 核心/Nginx 内部端口' '18. VLESS Encryption 实验' '19. 轮换 Shadowsocks 自用用户密钥' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun protocol list || true ;;
        2)
            printf '入口 ID（空输入查看全部，0 返回）: '
            if ! IFS= read -r listener; then
                [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
                return 0
            fi
            [[ "${listener}" != 0 ]] || continue
            if [[ -n "${listener}" ]]; then
                dockerMenuRun protocol links "${listener}" || true
            else
                dockerMenuRun protocol links || true
            fi
            ;;
        3) dockerMenuRun edit || true ;;
        4)
            printf 'Reality 入口 ID（0 返回）: '
            if ! IFS= read -r listener; then
                [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
                return 0
            fi
            [[ -n "${listener}" && "${listener}" != 0 ]] || continue
            dockerMenuRun edit --regenerate-reality "${listener}" || true
            ;;
        5) dockerMenuRealityTargets ;;
        6) dockerMenuRealityStream ;;
        7) dockerMenuSubscriptions ;;
        8) dockerMenuPortAliases ;;
        9) dockerMenuCdnEntries ;;
        10) dockerMenuXhttp ;;
        11) dockerMenuPortHopping ;;
        12) dockerMenuHysteria2 ;;
        13) dockerMenuTuic ;;
        14)
            dockerMenuRun protocol list || continue
            dockerSetupRead listener '源入口 ID（沿用账号、地址；0 返回）: ' &&
                [[ -n "${listener}" && "${listener}" != --* ]] || continue
            dockerSetupRead core '目标核心 [1=Xray，2=sing-box，空输入沿用源核心，0 返回]: ' || continue
            coreArgs=()
            case "${core}" in
            '') ;;
            1) coreArgs=(--protocol-core xray) ;;
            2) coreArgs=(--protocol-core sing-box) ;;
            *) printf '无效核心，请重新选择。\n'; continue ;;
            esac
            printf '%s\n' '1 Reality Vision / 2 Reality XHTTP / 26 Reality gRPC' \
                '3 Hy2 / 4 AnyTLS / 5 NaiveProxy / 30 Shadowsocks2022 / 31 TUIC / 28 Trojan direct' \
                '21 VLESS WS / 22 VMess WS / 23 VMess HTTPUpgrade / 24 VLESS gRPC TLS / 25 Trojan gRPC TLS' \
                '27 VLESS TLS Vision / 29 Trojan TLS fallback'
            dockerSetupRead protocol '目标协议 ID（0 返回）: ' &&
                [[ -n "${protocol}" ]] || continue
            dockerSetupRead port '新公开端口（0 返回）: ' &&
                [[ -n "${port}" ]] || continue
            dockerMenuRun edit --protocol-add "${listener}" "${protocol}" "${port}" "${coreArgs[@]}" || true
            ;;
        15|16)
            dockerMenuRun protocol list || continue
            dockerSetupRead listener '入口 ID（0 返回）: ' &&
                [[ -n "${listener}" && "${listener}" != --* ]] || continue
            if [[ "${choice}" == 15 ]]; then
                dockerMenuRun edit --protocol-remove "${listener}" || true
            else
                dockerMenuRun edit --protocol-rebuild "${listener}" || true
            fi
            ;;
        17)
            dockerMenuRun protocol list || continue
            dockerSetupRead listener '入口 ID（0 返回）: ' &&
                [[ -n "${listener}" && "${listener}" != --* ]] || continue
            dockerSetupRead backend '核心后端端口（0 返回）: ' &&
                [[ -n "${backend}" ]] || continue
            dockerSetupRead tls 'Nginx TLS 内部端口（0 返回）: ' &&
                [[ -n "${tls}" ]] || continue
            dockerMenuRun edit --internal-ports "${listener}" "${backend}" "${tls}" || true
            ;;
        18) dockerMenuVlessEncryption ;;
        19)
            dockerMenuRun protocol list || continue
            dockerSetupRead listener 'Shadowsocks2022 入口 ID（0 返回）: ' &&
                [[ -n "${listener}" && "${listener}" != --* ]] || continue
            dockerMenuRun edit --rotate-ss-user "${listener}" || true
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuVlessEncryption() {
    local choice listener action
    while :; do
        printf '\nDocker VLESS Encryption 实验\n'
        printf '%s\n' '仅支持 schema 3 的 Xray Reality Vision/XHTTP，已验范围仅固定 Xray/Mihomo 组合。' \
            '启用或关闭后须重新导入分享 URI。' \
            '1. 查看状态' '2. 启用并生成新参数' '3. 关闭' '0. 返回'
        dockerSetupRead choice '请选择: ' || return 0
        case "${choice}" in
        1) dockerMenuRun protocol encryption-status || true ;;
        2|3)
            dockerMenuRun protocol encryption-status || continue
            dockerSetupRead listener 'Xray Vision/XHTTP 入口 ID（0 返回）: ' &&
                [[ -n "${listener}" && "${listener}" != --* ]] || continue
            action=enable
            [[ "${choice}" != 3 ]] || action=disable
            dockerMenuRun edit --vless-encryption "${listener}" "${action}" || true
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuPortHopping() {
    local choice listener start end ipv4 ipv6 answer port
    while :; do
        printf '\nDocker 端口跳跃（单个双族 Hy2/TUIC；TUIC 仅范围转发）\n'
        printf '%s\n' '1. 查看状态' '2. 保存配置' '3. 启用已保存配置' \
            '4. 停止跳跃' '5. 清除保存配置' \
            '6. 输出活动分享链接（Hy2 范围/TUIC 首端口）' '7. 输出指定活动端口链接' \
            '8. 核验并清理残留会话' '0. 返回'
        dockerSetupRead choice '请选择: ' || return 0
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun port-hopping status || true ;;
        2)
            dockerSetupRead listener 'Hy2/TUIC 入口 ID（0 返回）: ' || continue
            [[ -n "${listener}" && "${listener}" != 0 ]] || continue
            dockerSetupRead start '起始端口（0 返回）: ' || continue
            [[ -n "${start}" && "${start}" != 0 ]] || continue
            dockerSetupRead end '结束端口（0 返回）: ' || continue
            [[ -n "${end}" && "${end}" != 0 ]] || continue
            dockerSetupRead ipv4 '本机 IPv4（0 返回）: ' || continue
            [[ -n "${ipv4}" && "${ipv4}" != 0 ]] || continue
            dockerSetupRead ipv6 '本机 IPv6（0 返回）: ' || continue
            [[ -n "${ipv6}" && "${ipv6}" != 0 ]] || continue
            dockerMenuRun edit --port-hopping "${listener}" "${start}" "${end}" "${ipv4}" "${ipv6}" || true
            ;;
        3)
            dockerSetupRead answer '确认启用已保存的跳跃范围？[y/N]: ' n || continue
            case "${answer}" in
            y|Y|yes|YES) dockerMenuRun port-hopping start || true ;;
            esac
            ;;
        4) dockerMenuRun port-hopping stop || true ;;
        5) dockerMenuRun edit --port-hopping-clear || true ;;
        6) dockerMenuRun port-hopping share || true ;;
        7)
            dockerSetupRead port '活动范围内的端口（0 返回）: ' &&
                [[ -n "${port}" && "${port}" != 0 ]] || continue
            dockerMenuRun port-hopping share "${port}" || true
            ;;
        8)
            dockerMenuRun port-hopping recover --preview || continue
            dockerSetupRead answer '确认清理已核验的退出会话并保留保存配置？[y/N]: ' n || continue
            case "${answer}" in
            y|Y|yes|YES)
                dockerMenuRun port-hopping recover --confirm PADM-DOCKER-HOPPING-RECOVER || true
                ;;
            esac
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuXhttp() {
    local choice listener preset concurrency requests seconds padding noGrpc noSse post interval buffered mode path host headers downloadPort
    local downloadAddress downloadSecurity downloadServerName downloadAlpn downloadPublicKey downloadShortId downloadSettings
    local DOCKER_MENU_STATUS_FILE= status snapshot currentValues currentConcurrency currentRequests currentSeconds currentPadding
    local currentNoGrpc currentNoSse currentPost currentInterval currentBuffered currentKeepalive currentMode currentPath currentHost
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker XHTTP 管理（已有 Xray Reality 入口）\n'
        printf '%s\n' '普通设置' '1. 查看状态' '2. 日常预设' '3. 兼容预设' '4. 流式预设' \
            '5. 单并发预设' '14. 设置模式' \
            '高级设置' '23. XMUX 日常并发' '24. XMUX 单并发' '6. 自定义 XMUX' '7. 恢复缺省 XMUX' \
            '15. 设置路径和 Host' \
            '8. 设置 Padding' '9. 恢复缺省 Padding' \
            '10. 设置首部开关' '11. 恢复缺省首部' \
            '12. 设置 packet/stream 参数' '13. 恢复缺省 packet/stream' \
            '16. 统一高级参数' '17. 恢复推荐默认' \
            '18. 设置请求首部（JSON）' '19. 清除请求首部' \
            '实验功能' \
            '20. 设置下行端口' '21. 关闭上下行分离' '22. 设置独立下行' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun protocol xhttp-status || true ;;
        2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|17|18|19|20|21|22|23|24)
            # 在当前进程运行 CLI，保留中断处理；状态副本读完立即删除。
            DOCKER_MENU_STATUS_FILE=$(mktemp "${TMPDIR:-/tmp}/padm-xhttp-menu.XXXXXX") || continue
            status=0
            dockerMenuRun protocol xhttp-status >"${DOCKER_MENU_STATUS_FILE}" || status=$?
            snapshot=$(<"${DOCKER_MENU_STATUS_FILE}")
            rm -f -- "${DOCKER_MENU_STATUS_FILE}"
            DOCKER_MENU_STATUS_FILE=
            printf '%s\n' "${snapshot}"
            [[ "${status}" -eq 0 ]] || continue
            dockerSetupRead listener 'XHTTP 入口 ID（0 返回）: ' &&
                [[ -n "${listener}" && "${listener}" != --* ]] || continue
            currentValues=$(jq -er --arg listener "${listener}" '
                [.entries[] | select(.listener_id == $listener)] |
                if length != 1 then error("入口不支持 XHTTP 管理") else .[0] end |
                [.xmux.maxConcurrency, .xmux.hMaxRequestTimes, .xmux.hMaxReusableSecs,
                 .xPaddingBytes, .noGRPCHeader, .noSSEHeader, .limits.scMaxEachPostBytes,
                 .limits.scMinPostsIntervalMs, .limits.scMaxBufferedPosts, .limits.scStreamUpServerSecs,
                 .mode, .path, .host] |
                if any(.[]; . == null) then error("XHTTP 状态不完整") else . end |
                map(tostring) | @tsv
            ' <<<"${snapshot}" 2>/dev/null) || {
                dockerError '无法读取该入口的 XHTTP 当前值，请重新查看状态'
                continue
            }
            IFS=$'\t' read -r currentConcurrency currentRequests currentSeconds currentPadding \
                currentNoGrpc currentNoSse currentPost currentInterval currentBuffered currentKeepalive \
                currentMode currentPath currentHost <<<"${currentValues}"
            [[ "${currentRequests}" != 0 ]] || currentRequests=0-0
            [[ "${currentSeconds}" != 0 ]] || currentSeconds=0-0
            [[ "${currentKeepalive}" != 0 ]] || currentKeepalive=0-0
            if [[ "${choice}" == 6 ]]; then
                # 0 保留为返回键；需要零值时使用范围 0-0，数值边界交给 CLI。
                dockerSetupRead concurrency "XMUX 最大并发（整数或 from-to）[${currentConcurrency}，0 返回]: " "${currentConcurrency}" &&
                    dockerSetupRead requests "XMUX 每连接请求数（0-0 表示零）[${currentRequests}，0 返回]: " "${currentRequests}" &&
                    dockerSetupRead seconds "XMUX 连接复用秒数（0-0 表示零）[${currentSeconds}，0 返回]: " "${currentSeconds}" || continue
                dockerMenuRun edit --xhttp-xmux "${listener}" "${concurrency}" "${requests}" "${seconds}" || true
            elif [[ "${choice}" == 23 || "${choice}" == 24 ]]; then
                concurrency=16-32
                [[ "${choice}" != 24 ]] || concurrency=1
                dockerMenuRun edit --xhttp-concurrency "${listener}" "${concurrency}" || true
            elif [[ "${choice}" == 7 ]]; then
                dockerMenuRun edit --xhttp-xmux-clear "${listener}" || true
            elif [[ "${choice}" == 8 ]]; then
                dockerSetupRead padding "Padding 字节数（1..4096 整数或 from-to）[${currentPadding}，0 返回]: " "${currentPadding}" || continue
                dockerMenuRun edit --xhttp-padding "${listener}" "${padding}" || true
            elif [[ "${choice}" == 9 ]]; then
                dockerMenuRun edit --xhttp-padding-clear "${listener}" || true
            elif [[ "${choice}" == 10 ]]; then
                dockerSetupRead noGrpc "noGRPCHeader（true/false，0 返回）[${currentNoGrpc}]: " "${currentNoGrpc}" &&
                    dockerSetupRead noSse "noSSEHeader（true/false，0 返回）[${currentNoSse}]: " "${currentNoSse}" || continue
                dockerMenuRun edit --xhttp-headers "${listener}" "${noGrpc}" "${noSse}" || true
            elif [[ "${choice}" == 11 ]]; then
                dockerMenuRun edit --xhttp-headers-clear "${listener}" || true
            elif [[ "${choice}" == 12 ]]; then
                # 0 保留为返回键，前三项用 default 表示核心零值。
                dockerSetupRead post "packet-up 单个 POST 最大字节数（default=缺省，0 返回）[${currentPost}]: " "${currentPost}" &&
                    dockerSetupRead interval "packet-up POST 最小间隔毫秒（default=缺省，0 返回）[${currentInterval}]: " "${currentInterval}" &&
                    dockerSetupRead buffered "packet-up 最多缓存 POST 数（default=缺省，0 返回）[${currentBuffered}]: " "${currentBuffered}" &&
                    dockerSetupRead seconds "stream-up 服务端保活秒数（整数或 from-to，0-0=缺省，0 返回）[${currentKeepalive}]: " "${currentKeepalive}" || continue
                [[ "${post}" != default ]] || post=0
                [[ "${interval}" != default ]] || interval=0
                [[ "${buffered}" != default ]] || buffered=0
                dockerMenuRun edit --xhttp-limits "${listener}" "${post}" "${interval}" "${buffered}" "${seconds}" || true
            elif [[ "${choice}" == 13 ]]; then
                dockerMenuRun edit --xhttp-limits-clear "${listener}" || true
            elif [[ "${choice}" == 14 ]]; then
                dockerSetupRead mode "XHTTP 模式（auto/packet-up/stream-up，0 返回）[${currentMode}]: " "${currentMode}" || continue
                dockerMenuRun edit --xhttp-mode "${listener}" "${mode}" || true
            elif [[ "${choice}" == 15 ]]; then
                dockerSetupRead path "XHTTP 路径（以 / 开头，0 返回）[${currentPath}]: " "${currentPath}" &&
                    [[ -n "${path}" ]] &&
                    dockerSetupRead host "XHTTP Host（非空域名，0 返回）[${currentHost}]: " "${currentHost}" &&
                    [[ -n "${host}" ]] || continue
                dockerMenuRun edit --xhttp-path-host "${listener}" "${path}" "${host}" || true
            elif [[ "${choice}" == 16 ]]; then
                dockerSetupRead padding "Padding 字节数（1..4096 整数或 from-to）[${currentPadding}，0 返回]: " "${currentPadding}" &&
                    dockerSetupRead post "packet-up 单个 POST 最大字节数（default=缺省，0 返回）[${currentPost}]: " "${currentPost}" &&
                    dockerSetupRead interval "packet-up POST 最小间隔毫秒（default=缺省，0 返回）[${currentInterval}]: " "${currentInterval}" &&
                    dockerSetupRead buffered "packet-up 最多缓存 POST 数（default=缺省，0 返回）[${currentBuffered}]: " "${currentBuffered}" &&
                    dockerSetupRead seconds "stream-up 服务端保活秒数（整数或 from-to，0-0=缺省，0 返回）[${currentKeepalive}]: " "${currentKeepalive}" &&
                    dockerSetupRead noGrpc "noGRPCHeader（true/false，0 返回）[${currentNoGrpc}]: " "${currentNoGrpc}" &&
                    dockerSetupRead noSse "noSSEHeader（true/false，0 返回）[${currentNoSse}]: " "${currentNoSse}" || continue
                [[ "${post}" != default ]] || post=0
                [[ "${interval}" != default ]] || interval=0
                [[ "${buffered}" != default ]] || buffered=0
                dockerMenuRun edit --xhttp-advanced "${listener}" "${padding}" "${post}" "${interval}" \
                    "${buffered}" "${seconds}" "${noGrpc}" "${noSse}" || true
            elif [[ "${choice}" == 17 ]]; then
                dockerMenuRun edit --xhttp-defaults "${listener}" || true
            elif [[ "${choice}" == 18 ]]; then
                # JSON 作为单个参数原样交给 CLI，键值边界由后端合同校验。
                dockerSetupRead headers 'XHTTP 请求首部 JSON 对象（0 返回，空值取消）: ' &&
                    [[ -n "${headers}" ]] || continue
                dockerMenuRun edit --xhttp-request-headers "${listener}" "${headers}" || true
            elif [[ "${choice}" == 19 ]]; then
                dockerMenuRun edit --xhttp-request-headers-clear "${listener}" || true
            elif [[ "${choice}" == 20 ]]; then
                printf '下行沿用本入口同服务器的 Reality 后端、身份、路径和 Host。\n'
                dockerSetupRead downloadPort '下行端口（已登记的额外非默认分享端口，0 返回，空值取消）: ' &&
                    [[ -n "${downloadPort}" ]] || continue
                dockerMenuRun edit --xhttp-download "${listener}" "${downloadPort}" || true
            elif [[ "${choice}" == 21 ]]; then
                dockerMenuRun edit --xhttp-download-clear "${listener}" || true
            elif [[ "${choice}" == 22 ]]; then
                printf '外部前置必须回到同一 XHTTP 会话后端；不能连接任意独立后端，本菜单不自动部署 CDN。\n'
                dockerSetupRead downloadAddress '下行地址（0 返回，空值取消）: ' &&
                    [[ -n "${downloadAddress}" ]] &&
                    dockerSetupRead downloadPort '下行端口 [443，0 返回]: ' 443 &&
                    dockerSetupRead downloadSecurity '下行安全（tls/reality，0 返回）[tls]: ' tls &&
                    dockerSetupRead downloadServerName '下行 Server Name（0 返回，空值取消）: ' &&
                    [[ -n "${downloadServerName}" ]] &&
                    dockerSetupRead host '下行 Host（0 返回，空值取消）: ' &&
                    [[ -n "${host}" ]] &&
                    dockerSetupRead path '下行路径（以 / 开头，0 返回，空值取消）: ' &&
                    [[ -n "${path}" ]] &&
                    dockerSetupRead mode '下行模式（auto/stream-one/packet-up/stream-up，0 返回）[auto]: ' auto || continue
                downloadAlpn= downloadPublicKey= downloadShortId=
                if [[ "${downloadSecurity}" == tls ]]; then
                    dockerSetupRead downloadAlpn '下行 ALPN（h2/h3，0 返回）[h2]: ' h2 || continue
                elif [[ "${downloadSecurity}" == reality ]]; then
                    dockerSetupRead downloadPublicKey '下行 Reality public_key（0 返回，空值取消）: ' &&
                        [[ -n "${downloadPublicKey}" ]] &&
                        dockerSetupRead downloadShortId '下行 Reality short_id（0 返回，空值取消）: ' &&
                        [[ -n "${downloadShortId}" ]] || continue
                fi
                # 非法端口保留原值，交给 CLI 统一校验并显示错误。
                downloadSettings=$(jq -cn --arg address "${downloadAddress}" --arg port "${downloadPort}" \
                    --arg security "${downloadSecurity}" --arg server_name "${downloadServerName}" \
                    --arg host "${host}" --arg path "${path}" --arg mode "${mode}" \
                    --arg alpn "${downloadAlpn}" --arg public_key "${downloadPublicKey}" --arg short_id "${downloadShortId}" '
                    {address:$address,port:($port | try tonumber catch $port),security:$security,
                     server_name:$server_name,host:$host,path:$path,mode:$mode} +
                    if $security == "tls" then {alpn:[$alpn]}
                    elif $security == "reality" then {public_key:$public_key,short_id:$short_id}
                    else {} end') || continue
                dockerMenuRun edit --xhttp-download-settings "${listener}" "${downloadSettings}" || true
            else
                case "${choice}" in
                2) preset=daily ;;
                3) preset=compatible ;;
                4) preset=stream ;;
                5) preset=single ;;
                esac
                dockerMenuRun edit --xhttp-preset "${listener}" "${preset}" || true
            fi
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuHysteria2() {
    local choice listener up down obfs masquerade
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker Hysteria2 管理（已有 sing-box v3 入口）\n'
        printf '%s\n' '1. 查看状态' '2. BBR 自适应' '3. Brutal 固定带宽' \
            '4. Salamander 混淆' '5. Gecko 混淆' '6. 关闭混淆' \
            '7. HTTPS 伪装' '8. 本地网页' '9. 关闭伪装' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun protocol hy2-status || true ;;
        2|3|4|5|6|7|8|9)
            dockerMenuRun protocol hy2-status || continue
            dockerSetupRead listener 'Hysteria2 入口 ID（0 返回）: ' &&
                [[ -n "${listener}" && "${listener}" != --* ]] || continue
            case "${choice}" in
            2)
                dockerMenuRun edit --hy2-bandwidth "${listener}" bbr || true
                ;;
            3)
                dockerSetupRead up '服务端上行带宽 Mbps（服务端→客户端）[100]: ' 100 &&
                    dockerSetupRead down '服务端下行带宽 Mbps（客户端→服务端）[50]: ' 50 || continue
                dockerMenuRun edit --hy2-bandwidth "${listener}" brutal "${up}" "${down}" || true
                ;;
            4|5|6)
                case "${choice}" in
                4) obfs=salamander ;;
                5) obfs=gecko ;;
                6) obfs=off ;;
                esac
                dockerMenuRun edit --hy2-obfs "${listener}" "${obfs}" || true
                ;;
            7|8|9)
                case "${choice}" in
                7)
                    dockerSetupRead masquerade '伪装 HTTPS 地址（0 返回）: ' &&
                        [[ -n "${masquerade}" ]] || continue
                    ;;
                8)
                    printf 'local 使用已发布的受管静态网页；请先在站点菜单发布目录或内置主题，并关闭混淆。\n'
                    masquerade=local
                    ;;
                9) masquerade=off ;;
                esac
                dockerMenuRun edit --hy2-masquerade "${listener}" "${masquerade}" || true
                ;;
            esac
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuTuic() {
    local choice listener algorithm authTimeout heartbeat answer
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker TUIC 管理（已有 sing-box v3 入口）\n'
        printf '%s\n' '1. 查看状态' '2. cubic' '3. bbr' '4. new_reno' \
            '5. 连接参数' '6. 开启 0-RTT' '7. 关闭 0-RTT' '8. 恢复推荐默认' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun protocol tuic-status || true ;;
        2|3|4|5|6|7|8)
            dockerMenuRun protocol tuic-status || continue
            dockerSetupRead listener 'TUIC 入口 ID（0 返回）: ' &&
                [[ -n "${listener}" && "${listener}" != --* ]] || continue
            case "${choice}" in
            2|3|4)
                case "${choice}" in
                2) algorithm=cubic ;;
                3) algorithm=bbr ;;
                4) algorithm=new_reno ;;
                esac
                dockerMenuRun edit --tuic-congestion "${listener}" "${algorithm}" || true
                ;;
            5)
                dockerSetupRead authTimeout '认证超时 auth_timeout（正整数+ms/s/m/h）[3s]: ' 3s &&
                    dockerSetupRead heartbeat '心跳间隔 heartbeat（正整数+ms/s/m/h）[10s]: ' 10s || continue
                dockerMenuRun edit --tuic-connection "${listener}" "${authTimeout}" "${heartbeat}" || true
                ;;
            6)
                printf '启用 0-RTT 会增加重放攻击风险，默认关闭。\n'
                dockerSetupRead answer '确认启用 TUIC 0-RTT？[y/N]: ' n || continue
                case "${answer}" in
                y|Y|yes|YES) dockerMenuRun edit --tuic-zero-rtt "${listener}" true || true ;;
                esac
                ;;
            7) dockerMenuRun edit --tuic-zero-rtt "${listener}" false || true ;;
            8) dockerMenuRun edit --tuic-defaults "${listener}" || true ;;
            esac
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuCdnEntries() {
    local choice listener addresses
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker CDN 连接地址\n'
        printf '%s\n' '1. 查看状态' '2. 设置地址（Reality XHTTP/WS/HTTPUpgrade/gRPC TLS）' '3. 清除覆盖' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun protocol cdn-status || true ;;
        2|3)
            dockerMenuRun protocol cdn-status || continue
            dockerSetupRead listener '入口 ID（0 返回）: ' &&
                [[ -n "${listener}" ]] || continue
            if [[ "${choice}" == 2 ]]; then
                dockerSetupRead addresses '连接地址（IP 或域名，多个用逗号分隔，0 返回）: ' &&
                    [[ -n "${addresses}" ]] || continue
                dockerMenuRun edit --cdn-entry "${listener}" "${addresses}" || true
            else
                dockerMenuRun edit --cdn-entry-clear "${listener}" || true
            fi
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuPortAliases() {
    local choice listener port oldPort
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 额外入口端口\n'
        printf '%s\n' '1. 查看额外端口' '2. 添加端口' '3. 删除端口' \
            '4. 选择默认分享端口' '5. 恢复原入口' '6. 修改额外端口' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun protocol port-alias-status || true ;;
        2|3)
            dockerMenuRun protocol list || continue
            dockerSetupRead listener '入口 ID（0 返回）: ' &&
                [[ -n "${listener}" ]] &&
                dockerSetupRead port '额外端口（0 返回）: ' &&
                [[ -n "${port}" ]] || continue
            if [[ "${choice}" == 2 ]]; then
                dockerMenuRun edit --port-alias "${listener}" "${port}" || true
            else
                dockerMenuRun edit --port-alias-remove "${listener}" "${port}" || true
            fi
            ;;
        4)
            dockerMenuRun protocol port-alias-status || continue
            dockerMenuRun protocol list || continue
            dockerSetupRead listener '入口 ID（0 返回）: ' &&
                [[ -n "${listener}" ]] &&
                dockerSetupRead port '默认分享端口（已有额外端口，0 返回）: ' &&
                [[ -n "${port}" ]] || continue
            dockerMenuRun edit --port-alias-default "${listener}" "${port}" || true
            ;;
        5)
            dockerMenuRun protocol list || continue
            dockerSetupRead listener '入口 ID（0 返回）: ' &&
                [[ -n "${listener}" ]] || continue
            dockerMenuRun edit --port-alias-default "${listener}" base || true
            ;;
        6)
            dockerMenuRun protocol port-alias-status || continue
            dockerSetupRead listener '入口 ID（0 返回）: ' &&
                [[ -n "${listener}" ]] &&
                dockerSetupRead oldPort '旧额外端口（0 返回）: ' &&
                [[ -n "${oldPort}" ]] &&
                dockerSetupRead port '新额外端口（0 返回）: ' &&
                [[ -n "${port}" ]] || continue
            dockerMenuRun edit --port-alias-replace "${listener}" "${oldPort}" "${port}" || true
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuRealityStream() {
    local choice listener website domains address port
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker Reality 443 共存\n'
        printf '%s\n' '1. 查看状态' '2. 受管 TLS 网站开启或更换默认 Reality' '3. 关闭共存' \
            '4. 宿主网站开启或更换默认 Reality' '5. 宿主回环网站（host 网络）' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun protocol stream-status || true ;;
        2)
            dockerMenuRun protocol list || continue
            dockerSetupRead listener '默认 Xray Reality Vision/XHTTP 入口 ID（0 返回）: ' &&
                [[ -n "${listener}" ]] &&
                dockerSetupRead website '网站 TLS 入口 ID（0 返回）: ' &&
                [[ -n "${website}" ]] || continue
            dockerMenuRun edit --reality-stream "${listener}" "${website}" || true
            ;;
        3) dockerMenuRun edit --reality-stream off || true ;;
        4)
            dockerMenuRun protocol list || continue
            dockerSetupRead listener '默认 Xray Reality Vision/XHTTP 入口 ID（0 返回）: ' &&
                [[ -n "${listener}" ]] &&
                dockerSetupRead domains '宿主网站域名（多个用逗号分隔，0 返回）: ' &&
                [[ -n "${domains}" ]] &&
                dockerSetupRead address '容器可达宿主地址（不支持 loopback）[host.docker.internal，0 返回]: ' host.docker.internal &&
                dockerSetupRead port '宿主网站 TLS 端口 [8443，0 返回]: ' 8443 || continue
            dockerMenuRun edit --reality-stream-host "${listener}" "${domains}" "${address}" "${port}" || true
            ;;
        5)
            dockerMenuRun protocol list || continue
            dockerSetupRead listener '默认 Xray Reality Vision/XHTTP 入口 ID（0 返回）: ' &&
                [[ -n "${listener}" ]] &&
                dockerSetupRead domains '宿主网站域名（多个用逗号分隔，0 返回）: ' &&
                [[ -n "${domains}" ]] &&
                dockerSetupRead address '宿主回环地址 [127.0.0.1，::1 为 IPv6，0 返回]: ' 127.0.0.1 &&
                dockerSetupRead port '宿主网站 TLS 端口 [8443，0 返回]: ' 8443 || continue
            dockerMenuRun edit --reality-stream-loopback "${listener}" "${domains}" "${address}" "${port}" || true
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuRealityTargets() {
    local choice listener host port sni scope
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker Reality 目标站\n'
        dockerMenuRun protocol target-status || true
        printf '%s\n' '1. 检测当前目标' '2. 刷新目标库' '3. 扫描指定网段' \
            '4. 同 ASN 抽样扫描' '5. 查看/切换 A 级目标' '6. 手动设置目标站' \
            '7. 查看目标站黑名单' '8. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0|8|9|10) return 0 ;;
        1)
            dockerSetupRead listener 'Reality 入口 ID（空输入检测全部，0 返回）: ' || continue
            if [[ -n "${listener}" ]]; then
                dockerMenuRun protocol check-target "${listener}" || true
            else
                dockerMenuRun protocol check-target || true
            fi
            [[ "${DOCKER_MENU_SIGNAL}" -eq 0 ]] || continue
            dockerMenuRealityTargetActions "${listener}"
            ;;
        2)
            printf '\nReality 刷新范围\n'
            printf '%s\n' '1. 目标库 + 推荐候选' '2. 推荐候选' '3. 返回'
            dockerSetupRead scope '请选择刷新范围 [1]: ' 1 || continue
            case "${scope}" in
            1) dockerMenuRun protocol refresh-targets recommended || true ;;
            2) dockerMenuRun protocol refresh-targets recommended_only || true ;;
            3|r|R) ;;
            *) printf '无效选项，请重新选择。\n' ;;
            esac
            ;;
        3) dockerMenuRun protocol scan-targets || true ;;
        4) dockerMenuRun protocol scan-targets-asn || true ;;
        5) dockerMenuRealityTargetSelect ;;
        6)
            dockerSetupRead listener 'Reality 入口 ID（0 返回）: ' &&
                [[ -n "${listener}" ]] &&
                dockerSetupRead host 'Reality 目标 host[:port]（0 返回）: ' || continue
            port=443
            if [[ "${host}" == *:* ]]; then
                port=${host##*:}
                host=${host%:*}
            fi
            dockerSetupRead sni "Reality SNI [${host}]: " "${host}" || continue
            dockerMenuRun edit --reality-target "${listener}" "${host}" "${port}" "${sni}" || true
            ;;
        7) dockerMenuRun protocol blocked-targets || true ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuRealityTargetSelect() {
    local listener
    dockerSetupRead listener '切换目标的 Reality 入口 ID（0 返回）: ' "${1:-}" &&
        [[ -n "${listener}" ]] || return 0
    dockerMenuRun protocol select-target "${listener}" || true
}

dockerMenuRealityTargetActions() {
    local choice listener=${1:-} answer
    printf '\nReality 目标站后续操作\n'
    printf '%s\n' '1. 查看/切换 A 级目标' '2. 加入目标站黑名单' '3. 返回'
    dockerSetupRead choice '请选择 [3]: ' 3 || return 0
    case "${choice}" in
    1) dockerMenuRealityTargetSelect "${listener}" ;;
    2)
        dockerSetupRead listener '加入黑名单的 Reality 入口 ID（0 返回）: ' "${listener}" &&
            [[ -n "${listener}" ]] || return 0
        dockerMenuRun protocol targets "${listener}" || return 0
        dockerSetupRead answer '确认将该入口当前目标加入黑名单？[y/N]: ' n || return 0
        case "${answer}" in
        y|Y|yes|YES) dockerMenuRun protocol block-current-target "${listener}" || true ;;
        esac
        ;;
    3|r|R) ;;
    *) printf '无效选项，请重新选择。\n' ;;
    esac
}

dockerMenuAccounts() {
    local choice accountId name listeners enabled answer
    local -a action=()
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 账号管理\n'
        printf '%s\n' \
            '1. 查看账号' \
            '2. 新建账号' \
            '3. 编辑账号' \
            '4. 复制账号' \
            '5. 启用账号' \
            '6. 停用账号' \
            '7. 删除账号' \
            '8. 轮换凭据' \
            '9. 流量与额度' \
            '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun account list || true ;;
        2)
            action=(account create)
            dockerSetupRead name '账号名称（空输入自动生成，0 返回）: ' || continue
            [[ -z "${name}" ]] || action+=(--name "${name}")
            dockerSetupRead listeners '入口 ID（逗号分隔，空输入使用全部入口，0 返回）: ' || continue
            [[ -z "${listeners}" ]] || action+=(--listeners "${listeners}")
            dockerSetupRead enabled '是否启用账号 [Y/n]: ' y || continue
            case "${enabled}" in
            y|Y|yes|YES) ;;
            n|N|no|NO) action+=(--disabled) ;;
            *) printf '请输入 y 或 n。\n'; continue ;;
            esac
            dockerMenuRun "${action[@]}" || true
            ;;
        3)
            dockerSetupRead accountId '账号 ID（0 返回）: ' || continue
            action=(account edit "${accountId}")
            dockerSetupRead name '新名称（空输入保持不变，0 返回）: ' || continue
            [[ -z "${name}" ]] || action+=(--name "${name}")
            dockerSetupRead listeners '新入口 ID（空输入保持不变，0 返回）: ' || continue
            [[ -z "${listeners}" ]] || action+=(--listeners "${listeners}")
            [[ "${#action[@]}" -gt 3 ]] ||
                { printf '至少修改名称或入口。\n'; continue; }
            dockerMenuRun "${action[@]}" || true
            ;;
        4)
            dockerSetupRead accountId '账号 ID（0 返回）: ' || continue
            action=(account copy "${accountId}")
            dockerSetupRead name '新名称（空输入自动生成，0 返回）: ' || continue
            [[ -z "${name}" ]] || action+=(--name "${name}")
            dockerMenuRun "${action[@]}" || true
            ;;
        5|6)
            dockerSetupRead accountId '账号 ID（0 返回）: ' || continue
            if [[ "${choice}" == 5 ]]; then
                dockerMenuRun account enable "${accountId}" || true
            else
                dockerMenuRun account disable "${accountId}" || true
            fi
            ;;
        7|8)
            dockerSetupRead accountId '账号 ID（0 返回）: ' || continue
            dockerSetupRead answer '确认操作？[y/N]: ' n || continue
            case "${answer}" in
            y|Y|yes|YES)
                if [[ "${choice}" == 7 ]]; then
                    dockerMenuRun account delete "${accountId}" --yes || true
                else
                    dockerMenuRun account rotate "${accountId}" --yes || true
                fi
                ;;
            n|N|no|NO) ;;
            *) printf '请输入 y 或 n。\n' ;;
            esac
            ;;
        9) dockerMenuTraffic ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuTraffic() {
    local choice accountId limit answer confirmation
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 流量与额度\n'
        printf '%s\n' '1. 查看已存流量与额度' '2. 立即采集并检查额度' \
            '3. 设置账号额度' '4. 重置账号累计' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun traffic show || true ;;
        2) dockerMenuRun traffic collect || true ;;
        3|4)
            dockerMenuRun traffic show || continue
            dockerSetupRead accountId '流量账号 ID（空输入/0 返回）: ' &&
                [[ -n "${accountId}" ]] || continue
            if [[ "${choice}" == 3 ]]; then
                # 额度 0 表示不限额，不能使用把 0 当返回键的共用输入函数。
                printf '额度 GiB（0 不限额，空输入/r 返回）: '
                IFS= read -r limit || continue
                case "${limit}" in ''|r|R) continue ;; esac
                confirmation="确认设置账号 ${accountId} 的额度为 ${limit} GiB（0 不限额）？[y/N]: "
            else
                confirmation="确认清零账号 ${accountId} 的上传和下载累计（保留额度）？[y/N]: "
            fi
            dockerSetupRead answer "${confirmation}" n || continue
            case "${answer}" in y|Y|yes|YES) ;; *) continue ;; esac
            if [[ "${choice}" == 3 ]]; then
                dockerMenuRun traffic limit "${accountId}" "${limit}" || true
            else
                dockerMenuRun traffic reset "${accountId}" || true
            fi
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuSubscriptions() {
    local choice groupId name accounts listeners enabled answer
    local -a action=()
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 订阅管理\n'
        printf '%s\n' \
            '1. 查看分享组' \
            '2. 新建分享组' \
            '3. 编辑分享组' \
            '4. 启用分享组' \
            '5. 停用分享组' \
            '6. 删除分享组' \
            '7. 轮换分享 token' \
            '8. 输出纯订阅内容' \
            '9. 输出 HTTPS 链接' \
            '10. 输出部署主订阅内容' \
            '11. 输出部署主订阅 HTTPS 链接' \
            '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun subscription list || true ;;
        2)
            action=(subscription create)
            dockerSetupRead name '分享组名称（空输入自动生成，0 返回）: ' || continue
            [[ -z "${name}" ]] || action+=(--name "${name}")
            dockerSetupRead accounts '账号 ID（逗号分隔，空输入使用全部账号，0 返回）: ' || continue
            [[ -z "${accounts}" ]] || action+=(--accounts "${accounts}")
            dockerSetupRead listeners '入口 ID（逗号分隔，空输入使用全部入口，0 返回）: ' || continue
            [[ -z "${listeners}" ]] || action+=(--listeners "${listeners}")
            dockerSetupRead enabled '是否启用分享组 [Y/n]: ' y || continue
            case "${enabled}" in
            y|Y|yes|YES) ;;
            n|N|no|NO) action+=(--disabled) ;;
            *) printf '请输入 y 或 n。\n'; continue ;;
            esac
            dockerMenuRun "${action[@]}" || true
            ;;
        3)
            dockerSetupRead groupId '分享组 ID（0 返回）: ' || continue
            action=(subscription edit "${groupId}")
            dockerSetupRead name '新名称（空输入保持不变，0 返回）: ' || continue
            [[ -z "${name}" ]] || action+=(--name "${name}")
            dockerSetupRead accounts '新账号 ID（空输入保持不变，0 返回）: ' || continue
            [[ -z "${accounts}" ]] || action+=(--accounts "${accounts}")
            dockerSetupRead listeners '新入口 ID（空输入保持不变，0 返回）: ' || continue
            [[ -z "${listeners}" ]] || action+=(--listeners "${listeners}")
            [[ "${#action[@]}" -gt 3 ]] ||
                { printf '至少修改名称、账号或入口。\n'; continue; }
            dockerMenuRun "${action[@]}" || true
            ;;
        4|5)
            dockerSetupRead groupId '分享组 ID（0 返回）: ' || continue
            if [[ "${choice}" == 4 ]]; then
                dockerMenuRun subscription enable "${groupId}" || true
            else
                dockerMenuRun subscription disable "${groupId}" || true
            fi
            ;;
        6|7)
            dockerSetupRead groupId '分享组 ID（0 返回）: ' || continue
            dockerSetupRead answer '确认操作？[y/N]: ' n || continue
            case "${answer}" in
            y|Y|yes|YES)
                if [[ "${choice}" == 6 ]]; then
                    dockerMenuRun subscription delete "${groupId}" --yes || true
                else
                    dockerMenuRun subscription rotate "${groupId}" --yes || true
                fi
                ;;
            n|N|no|NO) ;;
            *) printf '请输入 y 或 n。\n' ;;
            esac
            ;;
        8|9)
            dockerSetupRead groupId '分享组 ID（0 返回）: ' || continue
            if [[ "${choice}" == 8 ]]; then
                dockerMenuRun subscription content "${groupId}" || true
            else
                dockerMenuRun subscription links "${groupId}" || true
            fi
            ;;
        10) dockerMenuRun subscription content --base || true ;;
        11) dockerMenuRun subscription links --base || true ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuBusiness() {
    local choice file strategy answer
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 业务备份恢复\n'
        printf '%s\n' '1. 创建业务备份' '2. 预览业务恢复' '3. 恢复业务备份' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1)
            dockerSetupRead file '备份保存绝对路径（0 返回）: ' || continue
            dockerMenuRun business backup "${file}" || true
            ;;
        2|3)
            dockerSetupRead file '备份 JSON 绝对路径（0 返回）: ' || continue
            dockerSetupRead strategy '恢复策略 [merge 保留新增 / replace 删除新增]（0 返回）: ' || continue
            case "${strategy}" in merge|replace) ;; *) printf '请输入 merge 或 replace。\n'; continue ;; esac
            dockerMenuRun business preview "${file}" --strategy "${strategy}" || continue
            [[ "${choice}" == 3 ]] || continue
            dockerSetupRead answer '确认按上述策略恢复业务？[y/N]: ' n || continue
            case "${answer}" in
            y|Y|yes|YES) dockerMenuRun business restore "${file}" --strategy "${strategy}" --yes || true ;;
            esac
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuGeo() {
    local choice version answer
    local -a action=()
    dockerMenuRun geo status || return 0
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker Xray Geo 数据\n'
        printf '%s\n' '1. 查看状态' '2. 立即更新' '3. 启用每日更新' \
            '4. 停用每日更新' '5. 查看调度状态' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun geo status || true ;;
        2)
            dockerSetupRead version 'Geo 发布固定 tag（空输入使用最新发布，0 返回）: ' || continue
            action=(geo update)
            [[ -z "${version}" ]] || action+=(--version "${version}")
            dockerSetupRead answer '确认更新 Geo 数据并在运行时重建 Xray？[y/N]: ' n || continue
            case "${answer}" in
            y|Y|yes|YES) dockerMenuRun "${action[@]}" || true ;;
            esac
            ;;
        3)
            dockerSetupRead answer '确认启用每日 01:35 的 Xray Geo 更新？[y/N]: ' n || continue
            case "${answer}" in
            y|Y|yes|YES) dockerMenuRun geo schedule enable || true ;;
            esac
            ;;
        4) dockerMenuRun geo schedule disable || true ;;
        5) dockerMenuRun geo schedule status || true ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuControl() {
    local choice address port peer output expiry invitation listeners listener
    local -a listenerIds=() action=()
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 控制连接\n'
        printf '%s\n' '1. 查看角色状态' '2. 初始化主控' '3. 邀请或轮换凭据' '4. 撤销授权' \
            '5. 接入被控角色' '6. 同步受管账号' '7. 验证 Peer 来源' '8. 手动轮转认证日志' \
            '9. 查看自动轮转状态' '10. 启用每小时轮转检查' '11. 停用自动轮转' \
            '12. 查看自动同步状态' '13. 启用或更新自动同步' '14. 停用自动同步' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun control status || true ;;
        2)
            dockerSetupRead address '主控 WireGuard IPv4（0 返回）: ' &&
                [[ -n "${address}" ]] &&
                dockerSetupRead port '控制监听端口 [18443，0 返回]: ' 18443 &&
                dockerSetupRead peer '对端 WireGuard IPv4（0 返回）: ' &&
                [[ -n "${peer}" ]] || continue
            dockerMenuRun control init --address "${address}" --port "${port}" --peer-address "${peer}" || true
            ;;
        3)
            dockerSetupRead output '邀请文件绝对路径（受管目录外，0 返回）: ' &&
                [[ -n "${output}" ]] &&
                dockerSetupRead expiry '授权有效秒数 [86400，0 返回]: ' 86400 || continue
            dockerMenuRun control invite --output "${output}" --expires-in "${expiry}" || true
            ;;
        4) dockerMenuRun control revoke || true ;;
        5)
            dockerSetupRead invitation '私有邀请文件绝对路径（0 返回）: ' &&
                [[ -n "${invitation}" ]] &&
                dockerSetupRead listeners '映射入口 ID（逗号分隔，最多 16 项，0 返回）: ' &&
                [[ -n "${listeners}" ]] || continue
            IFS=',' read -r -a listenerIds <<<"${listeners}"
            if [[ "${listeners}" == *, || "${#listenerIds[@]}" -gt 16 ]]; then
                printf '映射入口须为 1–16 个有效 ID，不能含空项。\n'
                continue
            fi
            action=(control join --invite "${invitation}")
            for listener in "${listenerIds[@]}"; do
                [[ "${listener}" =~ ^(entry-[a-z0-9][a-z0-9-]{0,47}|vless-reality|vless-ws)$ ]] || {
                    printf '映射入口 ID 无效或含空项。\n'
                    continue 2
                }
                action+=(--listener "${listener}")
            done
            dockerMenuRun "${action[@]}" || true
            ;;
        6)
            dockerSetupRead invitation '私有邀请文件绝对路径（0 返回）: ' &&
                [[ -n "${invitation}" ]] || continue
            dockerMenuRun control sync --invite "${invitation}" || true
            ;;
        7) dockerMenuRun control source-check || true ;;
        8) dockerMenuRun control log-rotate || true ;;
        9) dockerMenuRun control log-schedule status || true ;;
        10) dockerMenuRun control log-schedule enable || true ;;
        11) dockerMenuRun control log-schedule disable || true ;;
        12) dockerMenuRun control sync-schedule status || true ;;
        13)
            dockerSetupRead invitation '外部私有邀请文件绝对路径（0 返回）: ' &&
                [[ -n "${invitation}" ]] || continue
            dockerMenuRun control sync-schedule enable --invite "${invitation}" || true
            ;;
        14) dockerMenuRun control sync-schedule disable || true ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuSites() {
    local choice directory url listener alpnChoice templateChoice siteTemplate siteTitle
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 站点管理\n'
        printf '%s\n' '1. 默认页' '2. 发布静态目录' '3. 302 跳转' '4. 查看站点模式' \
            '5. ALPN 诊断' '6. 修复为推荐 ALPN' '7. 手动设置 ALPN' '8. 内置静态站点' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun edit --site-default || true ;;
        2)
            dockerSetupRead directory '独立静态站点目录绝对路径（0 返回）: ' &&
                [[ -n "${directory}" ]] || continue
            dockerMenuRun edit --site-static "${directory}" || true
            ;;
        3)
            dockerSetupRead url '302 HTTP/HTTPS 目标 URL（0 返回）: ' &&
                [[ -n "${url}" ]] || continue
            dockerMenuRun edit --site-redirect "${url}" || true
            ;;
        4) dockerMenuRun status || true ;;
        5)
            dockerSetupRead listener 'TLS fallback 入口 ID（空输入诊断全部，0 返回）: ' || continue
            if [[ -n "${listener}" ]]; then
                dockerMenuRun protocol alpn-status "${listener}" || true
            else
                dockerMenuRun protocol alpn-status || true
            fi
            ;;
        6|7)
            dockerSetupRead listener 'TLS fallback 入口 ID（0 返回）: ' &&
                [[ -n "${listener}" ]] || continue
            if [[ "${choice}" == 6 ]]; then
                dockerMenuRun edit --alpn "${listener}" h2,http/1.1 || true
                continue
            fi
            printf '\nDocker 手动设置 ALPN\n'
            printf '%s\n' '1. h2,http/1.1' '2. http/1.1,h2' '3. http/1.1' '0. 返回'
            dockerSetupRead alpnChoice '请选择 ALPN 顺序（0 返回）: ' || continue
            case "${alpnChoice}" in
            1) dockerMenuRun edit --alpn "${listener}" h2,http/1.1 || true ;;
            2) dockerMenuRun edit --alpn "${listener}" http/1.1,h2 || true ;;
            3) dockerMenuRun edit --alpn "${listener}" http/1.1 || true ;;
            *) printf '无效选项，请重新选择。\n' ;;
            esac
            ;;
        8)
            printf '\nDocker 内置静态站点\n'
            printf 'Hysteria2 发布后，在已有入口参数中关闭混淆并将伪装设置为 local。\n'
            printf '%s\n' '1. 笔记（notes）' '2. 相册（photos）' '3. 文档（docs）' '0. 返回'
            dockerSetupRead templateChoice '请选择站点主题（0 返回）: ' || continue
            case "${templateChoice}" in
            1) siteTemplate=notes ;;
            2) siteTemplate=photos ;;
            3) siteTemplate=docs ;;
            *) printf '无效选项，请重新选择。\n'; continue ;;
            esac
            dockerSetupRead siteTitle '站名（2–60 个字符，空输入使用主题默认值，0 返回）: ' || continue
            if [[ -n "${siteTitle}" ]]; then
                dockerMenuRun edit --site-template "${siteTemplate}" --site-title "${siteTitle}" || true
            else
                dockerMenuRun edit --site-template "${siteTemplate}" || true
            fi
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuRegion() {
    local choice mode extra action oldRule newRule
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 区域阻断策略\n'
        printf '%s\n' '1. 屏蔽 geosite:cn + geoip:cn' '2. 仅屏蔽 geosite:cn' \
            '3. 仅屏蔽 geoip:cn' '4. 关闭区域策略' \
            '5. 追加自定义直连例外' '6. 删除自定义直连例外' \
            '7. 单条替换自定义直连例外' '8. 查看路由状态' \
            '9. 仅切换已有区域模式（保留自定义例外）' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1|2|3)
            case "${choice}" in 1) mode=both ;; 2) mode=domain ;; 3) mode=ip ;; esac
            printf '默认直连例外: %s\n' "$(jq -r 'map(ltrimstr("domain:")) | join(",")' \
                <<<"${PADM_DOCKER_REGION_DEFAULT_DOMAINS}")"
            printf '区域阻断可能影响客户端连接；直连例外优先于其它阻断和 SOCKS5。\n'
            dockerSetupRead extra '替换自定义直连例外规则（逗号分隔，留空清空，0 返回）: ' || continue
            if [[ -n "${extra}" ]]; then
                dockerMenuRun edit --region "${mode}" --region-allow "${extra}" || true
            else
                dockerMenuRun edit --region "${mode}" || true
            fi
            ;;
        4) dockerMenuRun edit --region-off || true ;;
        5|6)
            if [[ "${choice}" == 5 ]]; then
                action=--region-allow-add
                dockerSetupRead extra '追加自定义直连例外 CSV（domain:/full:/keyword:/geosite:，0 返回）: ' &&
                    [[ -n "${extra}" ]] || continue
            else
                action=--region-allow-remove
                dockerSetupRead extra '删除自定义直连例外 CSV（domain:/full:/keyword:/geosite:，0 返回）: ' &&
                    [[ -n "${extra}" ]] || continue
            fi
            dockerMenuRun edit "${action}" "${extra}" || true
            ;;
        7)
            dockerMenuRun protocol routing-status || continue
            dockerSetupRead oldRule '旧域名规则（单条；domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${oldRule}" ]] &&
                dockerSetupRead newRule '新域名规则（单条；domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${newRule}" ]] || continue
            dockerMenuRun edit --region-allow-replace "${oldRule}" "${newRule}" || true
            ;;
        8) dockerMenuRun protocol routing-status || true ;;
        9)
            dockerSetupRead mode '区域模式 [both/domain/ip，0 返回]: ' &&
                [[ -n "${mode}" ]] || continue
            case "${mode}" in
            both|domain|ip) dockerMenuRun edit --region-mode "${mode}" || true ;;
            *) printf '无效模式，请重新选择。\n' ;;
            esac
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuIPv6() {
    local choice domains oldRule newRule
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker IPv6 域名出站\n'
        printf '%s\n' '1. 替换 IPv6 域名规则' '2. IPv6 默认出站' \
            '3. 关闭 IPv6 出站策略' '4. 查看路由状态' \
            '5. 追加 IPv6 域名规则' '6. 精确删除 IPv6 域名规则' \
            '7. 单条替换 IPv6 域名规则' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1)
            dockerSetupRead domains 'IPv6 域名规则（逗号分隔；domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${domains}" ]] || continue
            dockerMenuRun edit --ipv6 selective --ipv6-domains "${domains}" || true
            ;;
        2) dockerMenuRun edit --ipv6 global || true ;;
        3) dockerMenuRun edit --ipv6-off || true ;;
        4) dockerMenuRun protocol routing-status || true ;;
        5)
            dockerSetupRead domains '追加 IPv6 域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${domains}" ]] || continue
            dockerMenuRun edit --ipv6-domains-add "${domains}" || true
            ;;
        6)
            dockerSetupRead domains '精确删除 IPv6 域名规则 CSV（删空关闭；domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${domains}" ]] || continue
            dockerMenuRun edit --ipv6-domains-remove "${domains}" || true
            ;;
        7)
            dockerMenuRun protocol routing-status || continue
            dockerSetupRead oldRule '旧域名规则（单条；domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${oldRule}" ]] &&
                dockerSetupRead newRule '新域名规则（单条；domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${newRule}" ]] || continue
            dockerMenuRun edit --ipv6-domains-replace "${oldRule}" "${newRule}" || true
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuTProxy() {
    local kind=${1:-tproxy} title=TProxy choice action port mark family state defaultPort defaultMark defaultFamily outputUid
    local -a editArgs=()
    [[ "${kind}" != redirect ]] || title=Redirect
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker %s 管理\n' "${title}"
        [[ "${kind}" != redirect ]] || printf '仅捕获 TCP；UDP 保持原路由。\n'
        printf '%s\n' '1. 查看状态' "2. 启用 ${title}" "3. 修改 ${title} 参数" "4. 关闭 ${title}" \
            '5. 设置本机转发 UID' '6. 关闭本机转发（保留 PREROUTING）' \
            '7. 全主机本机转发（绕过核心专用 GID 10001）' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun protocol "${kind}-status" || true ;;
        2|3)
            if ! state=$(dockerMenuRun protocol "${kind}-status"); then
                printf '%s\n' "${state}"
                continue
            fi
            printf '%s\n' "${state}"
            defaultPort=31298 defaultMark=129 defaultFamily=ipv4 action=--${kind}-enable
            if [[ "${choice}" == 3 ]]; then
                defaultPort=$(jq -er 'select(.enabled == true) | .port' <<<"${state}") &&
                    defaultFamily=$(jq -er 'select(.enabled == true) | .family // "ipv4"' <<<"${state}") || continue
                [[ "${kind}" != tproxy ]] ||
                    defaultMark=$(jq -er 'select(.enabled == true) | .mark' <<<"${state}") || continue
                action=--${kind}-settings
            fi
            dockerSetupRead port "${title} 端口 [${defaultPort}，0 返回]: " "${defaultPort}" || continue
            editArgs=("${action}" "${port}")
            if [[ "${kind}" == tproxy ]]; then
                dockerSetupRead mark "TProxy mark [${defaultMark}，0 返回]: " "${defaultMark}" || continue
                editArgs+=("${mark}")
            fi
            dockerSetupRead family "${title} 地址族 ipv4/ipv6/dual [${defaultFamily}，0 返回]: " "${defaultFamily}" || continue
            dockerMenuRun edit "${editArgs[@]}" "--${kind}-family" "${family}" || true
            ;;
        4) dockerMenuRun edit "--${kind}-off" || true ;;
        5|6|7)
            if ! state=$(dockerMenuRun protocol "${kind}-status"); then
                printf '%s\n' "${state}"
                continue
            fi
            printf '%s\n' "${state}"
            port=$(jq -er 'select(.enabled == true) | .port' <<<"${state}") &&
                family=$(jq -er 'select(.enabled == true) | .family // "ipv4"' <<<"${state}") || continue
            editArgs=("--${kind}-settings" "${port}")
            if [[ "${kind}" == tproxy ]]; then
                mark=$(jq -er 'select(.enabled == true) | .mark' <<<"${state}") || continue
                editArgs+=("${mark}")
            fi
            editArgs+=("--${kind}-family" "${family}")
            if [[ "${choice}" == 5 ]]; then
                dockerSetupRead outputUid '本机转发 UID（1–2147483647，排除 10001；0 返回）: ' &&
                    [[ -n "${outputUid}" ]] || continue
                dockerMenuRun edit "${editArgs[@]}" "--${kind}-output-uid" "${outputUid}" || true
            elif [[ "${choice}" == 7 ]]; then
                dockerMenuRun edit "${editArgs[@]}" "--${kind}-output-all" || true
            else
                dockerMenuRun edit "${editArgs[@]}" "--${kind}-output-off" || true
            fi
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuTun() {
    local choice
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker TUN 管理\n'
        printf '%s\n' '1. 查看状态' '2. 启用 TUN' '3. 关闭 TUN' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun protocol tun-status || true ;;
        2)
            printf '%s\n' 'TUN 将接管宿主全局流量；当前 IPv4 模式会拒绝 IPv6 流量。'
            dockerMenuRun edit --tun-enable || true
            ;;
        3) dockerMenuRun edit --tun-off || true ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuRouting() {
    local choice input server port oldRule newRule action
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 路由与出站\n'
        printf '%s\n' '1. 启用 SOCKS5 出站' '2. 关闭 SOCKS5 出站' '3. 查看路由状态' \
            '4. 替换 SOCKS5 域名规则' '5. 切换 SOCKS5 全局出站' \
            '6. 设置 DNS 分流' '7. 关闭 DNS 分流' '8. 直接录入 hosts（整组替换）' \
            '9. 关闭 hosts 覆盖' '10. 替换 Direct 直连例外' \
            '11. 关闭 Direct 直连例外' '12. 替换 Block 域名阻断' \
            '13. 关闭 Block 域名阻断' '14. 设置 IP/CIDR 阻断' \
            '15. 关闭 IP/CIDR 阻断' '16. 启用 BT 协议阻断' \
            '17. 关闭 BT 协议阻断' '18. 区域阻断策略' '19. IPv6 域名出站' '20. WARP 出站' \
            '21. HTTP 中继入站' '22. 追加 Direct 直连例外' \
            '23. 追加 Block 域名阻断' '24. 删除 Direct 直连例外' \
            '25. 删除 Block 域名阻断' '26. 追加 IP/CIDR 阻断' \
            '27. 精确删除 IP/CIDR 阻断' '28. 追加 DNS 分流域名' \
            '29. 精确删除 DNS 分流域名' '30. 单条替换 DNS 分流域名' \
            '31. 单条替换 Direct 直连例外' '32. 单条替换 Block 域名阻断' \
            '33. 单条替换 IP/CIDR 阻断' '34. 追加 SOCKS5 域名规则' \
            '35. 精确删除 SOCKS5 域名规则' '36. 单条替换 SOCKS5 域名规则' \
            '37. 单项替换 hosts 地址' '38. 新增 hosts 精确映射' \
            '39. 精确删除 hosts 映射' '40. 移除全部访问控制' \
            '41. 修改已有 DNS 上游' '42. 修改已有 SOCKS5 上游' '43. TProxy 管理' '44. TUN 管理' \
            '45. IP 阻断加入域名解析结果（sing-box）' '46. IP 阻断仅匹配字面地址' '47. Redirect TCP 管理' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1)
            dockerMenuRun protocol routing-status || continue
            dockerMenuRun edit --socks5-input || true
            ;;
        2) dockerMenuRun edit --socks5-off || true ;;
        3) dockerMenuRun protocol routing-status || true ;;
        45) dockerMenuRun edit --block-ips-resolve || true ;;
        46) dockerMenuRun edit --block-ips-literal || true ;;
        41|42)
            dockerMenuRun protocol routing-status || continue
            dockerSetupRead server '上游服务器 IPv4/IPv6（0 返回）: ' &&
                [[ -n "${server}" ]] &&
                dockerSetupRead port '上游端口（1–65535，0 返回）: ' &&
                [[ -n "${port}" ]] || continue
            action=--dns-upstream
            [[ "${choice}" != 42 ]] || action=--socks5-upstream
            dockerMenuRun edit "${action}" "${server}" "${port}" || true
            ;;
        4)
            dockerSetupRead input 'SOCKS5 域名规则（逗号分隔；domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${input}" ]] || continue
            dockerMenuRun edit --socks5-domains "${input}" || true
            ;;
        5) dockerMenuRun edit --socks5-global || true ;;
        6)
            dockerSetupRead server 'DNS 服务器 IPv4/IPv6（0 返回）: ' &&
                [[ -n "${server}" ]] &&
                dockerSetupRead port 'DNS 端口 [53，0 返回]: ' 53 || continue
            if [[ ! "${port}" =~ ^[0-9]{1,5}$ ]] || ((10#${port} < 1 || 10#${port} > 65535)); then
                printf 'DNS 端口必须为 1–65535，请重新选择。\n'
                continue
            fi
            dockerSetupRead input 'DNS 域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${input}" ]] || continue
            dockerMenuRun edit --dns-rules "${server}" "${port}" "${input}" || true
            ;;
        7) dockerMenuRun edit --dns-off || true ;;
        8)
            dockerMenuRun protocol routing-status || continue
            dockerMenuRun edit --hosts-input || true
            ;;
        9) dockerMenuRun edit --hosts-off || true ;;
        10|12)
            dockerSetupRead input '替换域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${input}" ]] || continue
            if [[ "${choice}" == 10 ]]; then
                dockerMenuRun edit --direct-domains "${input}" || true
            else
                dockerMenuRun edit --block-domains "${input}" || true
            fi
            ;;
        11) dockerMenuRun edit --direct-off || true ;;
        13) dockerMenuRun edit --block-off || true ;;
        14|26|27)
            [[ "${choice}" != 27 ]] ||
                printf '精确删除按完整字符串匹配，删空关闭手工 IP 阻断。\n'
            dockerSetupRead input 'IP/CIDR 规则 CSV（字面 IP/CIDR 或 geoip:cn，逗号分隔，0 返回）: ' &&
                [[ -n "${input}" ]] || continue
            case "${choice}" in
            14) dockerMenuRun edit --block-ips-csv "${input}" || true ;;
            26) dockerMenuRun edit --block-ips-add-csv "${input}" || true ;;
            27) dockerMenuRun edit --block-ips-remove-csv "${input}" || true ;;
            esac
            ;;
        15) dockerMenuRun edit --block-ips-off || true ;;
        16) dockerMenuRun edit --block-bt || true ;;
        17) dockerMenuRun edit --block-bt-off || true ;;
        18) dockerMenuRegion ;;
        19) dockerMenuIPv6 ;;
        20) dockerMenuWarp ;;
        21) dockerMenuHttpRelay ;;
        43) dockerMenuTProxy ;;
        47) dockerMenuTProxy redirect ;;
        44) dockerMenuTun ;;
        22|23)
            dockerSetupRead input '追加域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${input}" ]] || continue
            if [[ "${choice}" == 22 ]]; then
                dockerMenuRun edit --direct-domains-add "${input}" || true
            else
                dockerMenuRun edit --block-domains-add "${input}" || true
            fi
            ;;
        24|25)
            dockerSetupRead input '精确删除域名规则 CSV（删空关闭；domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${input}" ]] || continue
            if [[ "${choice}" == 24 ]]; then
                dockerMenuRun edit --direct-domains-remove "${input}" || true
            else
                dockerMenuRun edit --block-domains-remove "${input}" || true
            fi
            ;;
        28|29)
            if [[ "${choice}" == 28 ]]; then
                dockerSetupRead input '追加域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）: ' &&
                    [[ -n "${input}" ]] || continue
                dockerMenuRun edit --dns-domains-add "${input}" || true
            else
                dockerSetupRead input '精确删除域名规则 CSV（删空关闭；domain:/full:/keyword:/geosite:，0 返回）: ' &&
                    [[ -n "${input}" ]] || continue
                dockerMenuRun edit --dns-domains-remove "${input}" || true
            fi
            ;;
        30|31|32|36)
            dockerMenuRun protocol routing-status || continue
            dockerSetupRead oldRule '旧域名规则（单条；domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${oldRule}" ]] &&
                dockerSetupRead newRule '新域名规则（单条；domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${newRule}" ]] || continue
            case "${choice}" in
            30) dockerMenuRun edit --dns-domains-replace "${oldRule}" "${newRule}" || true ;;
            31) dockerMenuRun edit --direct-domains-replace "${oldRule}" "${newRule}" || true ;;
            32) dockerMenuRun edit --block-domains-replace "${oldRule}" "${newRule}" || true ;;
            36) dockerMenuRun edit --socks5-domains-replace "${oldRule}" "${newRule}" || true ;;
            esac
            ;;
        33)
            dockerMenuRun protocol routing-status || continue
            dockerSetupRead oldRule '旧 IP/CIDR 规则（单条字面 IP/CIDR，0 返回）: ' &&
                [[ -n "${oldRule}" ]] &&
                dockerSetupRead newRule '新 IP/CIDR 规则（单条字面 IP/CIDR，0 返回）: ' &&
                [[ -n "${newRule}" ]] || continue
            dockerMenuRun edit --block-ips-replace "${oldRule}" "${newRule}" || true
            ;;
        34|35)
            dockerMenuRun protocol routing-status || continue
            if [[ "${choice}" == 34 ]]; then
                dockerSetupRead input '追加 SOCKS5 域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）: ' &&
                    [[ -n "${input}" ]] || continue
                dockerMenuRun edit --socks5-domains-add "${input}" || true
            else
                dockerSetupRead input '精确删除 SOCKS5 域名规则 CSV（删空关闭，需重新启用；domain:/full:/keyword:/geosite:，0 返回）: ' &&
                    [[ -n "${input}" ]] || continue
                dockerMenuRun edit --socks5-domains-remove "${input}" || true
            fi
            ;;
        37)
            dockerMenuRun protocol routing-status || continue
            dockerSetupRead oldRule '已有 hosts 精确域名（0 返回）: ' &&
                [[ -n "${oldRule}" ]] &&
                dockerSetupRead newRule '新 hosts IPv4/IPv6（单个字面地址，0 返回）: ' &&
                [[ -n "${newRule}" ]] || continue
            dockerMenuRun edit --hosts-replace "${oldRule}" "${newRule}" || true
            ;;
        38)
            dockerMenuRun protocol routing-status || continue
            dockerSetupRead oldRule '新增 hosts 精确域名（0 返回）: ' &&
                [[ -n "${oldRule}" ]] &&
                dockerSetupRead newRule '新 hosts IPv4/IPv6（单个字面地址，0 返回）: ' &&
                [[ -n "${newRule}" ]] || continue
            dockerMenuRun edit --hosts-add "${oldRule}" "${newRule}" || true
            ;;
        39)
            dockerMenuRun protocol routing-status || continue
            dockerSetupRead oldRule '删除 hosts 精确域名（最后一项关闭 hosts，0 返回）: ' &&
                [[ -n "${oldRule}" ]] || continue
            dockerMenuRun edit --hosts-remove "${oldRule}" || true
            ;;
        40)
            printf '移除手工 Direct、域名/IP 阻断和区域预设；保留 BT、DNS/hosts 与出站配置。\n'
            dockerMenuRun edit --access-control-off || true
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuHttpRelay() {
    local choice input
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker HTTP 中继入站\n'
        printf '%s\n' '1. 直接录入认证与来源规则' '2. 关闭 HTTP 中继' '3. 查看路由状态' \
            '4. 修改中继端口' '5. 替换来源允许名单' '6. 追加来源允许名单' \
            '7. 精确删除来源允许名单（删空拒绝）' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1)
            dockerMenuRun protocol routing-status || continue
            printf 'HTTP 中继只接受已有受管 Xray；sing-box 的代理头来源覆盖不满足来源限制。\n'
            dockerMenuRun edit --http-relay-input || true
            ;;
        2) dockerMenuRun edit --http-relay-off || true ;;
        3) dockerMenuRun protocol routing-status || true ;;
        4|5|6|7)
            dockerMenuRun protocol routing-status || continue
            if [[ "${choice}" == 4 ]]; then
                dockerSetupRead input '新 HTTP 中继端口（1–65535，0 返回）: ' &&
                    [[ -n "${input}" ]] || continue
                dockerMenuRun edit --http-relay-port "${input}" || true
            else
                dockerSetupRead input 'HTTP 中继来源 IP/CIDR CSV（精确字面规则，0 返回）: ' &&
                    [[ -n "${input}" ]] || continue
                case "${choice}" in
                5) dockerMenuRun edit --http-relay-sources "${input}" || true ;;
                6) dockerMenuRun edit --http-relay-sources-add "${input}" || true ;;
                7) dockerMenuRun edit --http-relay-sources-remove "${input}" || true ;;
                esac
            fi
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuWarp() {
    local choice input oldRule newRule
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker WARP 出站\n'
        printf '%s\n' '1. 直接录入 WARP Peer' '2. 关闭 WARP 出站' '3. 查看路由状态' \
            '4. 替换 WARP 域名规则' '5. 切换 WARP 全局出站' \
            '6. 切换 WARP IPv4 隧道地址族' '7. 切换 WARP IPv6 隧道地址族' \
            '8. 追加 WARP 域名规则' '9. 精确删除 WARP 域名规则' \
            '10. 单条替换 WARP 域名规则' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1)
            dockerMenuRun protocol routing-status || continue
            dockerMenuRun edit --warp-input || true
            ;;
        2) dockerMenuRun edit --warp-off || true ;;
        3) dockerMenuRun protocol routing-status || true ;;
        4)
            dockerSetupRead input 'WARP 域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${input}" ]] || continue
            dockerMenuRun edit --warp-domains "${input}" || true
            ;;
        5) dockerMenuRun edit --warp-global || true ;;
        6) dockerMenuRun edit --warp-family ipv4 || true ;;
        7) dockerMenuRun edit --warp-family ipv6 || true ;;
        8)
            dockerSetupRead input '追加 WARP 域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${input}" ]] || continue
            dockerMenuRun edit --warp-domains-add "${input}" || true
            ;;
        9)
            dockerSetupRead input '精确删除 WARP 域名规则 CSV（删空关闭，需重新录入或导入 WARP；domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${input}" ]] || continue
            dockerMenuRun edit --warp-domains-remove "${input}" || true
            ;;
        10)
            dockerMenuRun protocol routing-status || continue
            dockerSetupRead oldRule '旧域名规则（单条；domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${oldRule}" ]] &&
                dockerSetupRead newRule '新域名规则（单条；domain:/full:/keyword:/geosite:，0 返回）: ' &&
                [[ -n "${newRule}" ]] || continue
            dockerMenuRun edit --warp-domains-replace "${oldRule}" "${newRule}" || true
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuFail2ban() {
    local choice address answer listener target port unit
    local action ports maxRetry findTime banTime defaultRetry defaultFind defaultBan confirmation
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker Fail2ban 维护\n'
        printf '%s\n' '1. 查看 WS 状态' '2. 解封 WS 单个 IP' '3. 停用 WS 站点扫描防护' \
            '4. 核对 WS 真实来源' '5. 启用 WS 站点扫描防护' '6. 修改 WS 站点扫描参数' \
            '7. 查看控制面状态' '8. 解封控制面单个 IP' '9. 停用控制面防护' \
            '10. 启用控制面防护' '11. 修改控制面防护参数' '12. SSH 宿主只读预检' \
            '13. 核对 SSH 实时来源' '14. 核对 SSH unit 实时来源' \
            '15. 查看 SSH 防护状态' '16. 解封 SSH 单个 IP' '17. 停用 SSH 防护' \
            '18. 启用专用 SSH service 防护' '19. 修改 SSH 防护参数' \
            '20. 修改单入口 WS 保护端口' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun fail2ban status || true ;;
        7) dockerMenuRun fail2ban control status || true ;;
        15) dockerMenuRun fail2ban ssh status || true ;;
        12) dockerMenuRun fail2ban ssh preflight || true ;;
        13|14)
            local -a witnessArgs=()
            action=verify-source
            if [[ "${choice}" == 14 ]]; then
                dockerSetupRead unit '宿主 SSH systemd service（0 返回）: ' &&
                    [[ -n "${unit}" ]] || continue
                action=verify-unit witnessArgs=("${unit}")
            fi
            dockerSetupRead target '宿主 SSH 本机 IPv4/IPv6（0 返回）: ' &&
                [[ -n "${target}" ]] &&
                dockerSetupRead port '宿主 SSH 端口（0 返回）: ' &&
                [[ -n "${port}" ]] &&
                dockerSetupRead address '外部 SSH 客户端 IPv4/IPv6（0 返回）: ' &&
                [[ -n "${address}" ]] || continue
            dockerMenuRun fail2ban ssh "${action}" "${witnessArgs[@]}" \
                "${target}" "${port}" "${address}" || true
            ;;
        2|8|16)
            local jail=padm-nginx
            local -a scopeArgs=()
            [[ "${choice}" != 8 ]] || { jail=padm-control; scopeArgs=(control); }
            [[ "${choice}" != 16 ]] || { jail=padm-sshd; scopeArgs=(ssh); }
            local addressPrompt='待解封 IPv4/IPv6（0 返回）: '
            [[ "${choice}" != 8 ]] || addressPrompt='待解封控制面 IPv4（0 返回）: '
            dockerSetupRead address "${addressPrompt}" &&
                [[ -n "${address}" ]] || continue
            dockerSetupRead answer "确认从 ${jail} 解封 ${address}？[y/N]: " n || continue
            case "${answer}" in y|Y|yes|YES) ;; *) continue ;; esac
            dockerMenuRun fail2ban "${scopeArgs[@]}" unban "${address}" || true
            ;;
        3|9|17)
            local -a scopeArgs=()
            [[ "${choice}" != 9 ]] || scopeArgs=(control)
            [[ "${choice}" != 17 ]] || scopeArgs=(ssh)
            confirmation='确认停用受管站点扫描防护？[y/N]: '
            [[ "${choice}" != 9 ]] || confirmation='确认停用受管控制面防护？[y/N]: '
            [[ "${choice}" != 17 ]] || confirmation='确认停用受管 SSH 防护？[y/N]: '
            dockerSetupRead answer "${confirmation}" n || continue
            case "${answer}" in y|Y|yes|YES) ;; *) continue ;; esac
            dockerMenuRun fail2ban "${scopeArgs[@]}" disable --confirm PADM-DOCKER-EDIT || true
            ;;
        4)
            dockerMenuRun protocol list || continue
            dockerSetupRead listener 'WS 入口 ID（0 返回）: ' &&
                [[ -n "${listener}" ]] &&
                dockerSetupRead address '外部客户端 IPv4/IPv6（0 返回）: ' &&
                [[ -n "${address}" ]] || continue
            dockerMenuRun fail2ban verify-source "${listener}" "${address}" || true
            ;;
        20)
            dockerMenuRun protocol list || continue
            dockerSetupRead listener '受保护 WS 入口 ID（0 返回）: ' &&
                [[ -n "${listener}" ]] &&
                dockerSetupRead port '新 WS 公开端口（0 返回）: ' &&
                [[ -n "${port}" ]] || continue
            dockerSetupRead answer '确认修改单入口 WS 保护端口？[y/N]: ' n || continue
            case "${answer}" in y|Y|yes|YES) ;; *) continue ;; esac
            dockerMenuRun edit --fail2ban-port "${listener}" "${port}" --confirm PADM-DOCKER-EDIT || true
            ;;
        5|6|10|11|18|19)
            local -a scopeArgs=() portArgs=()
            if [[ "${choice}" == 10 || "${choice}" == 11 ]]; then
                scopeArgs=(control)
                dockerMenuRun control status || continue
            elif [[ "${choice}" == 18 || "${choice}" == 19 ]]; then
                scopeArgs=(ssh)
                printf '%s\n' '仅支持无存量会话、禁止 reload 的专用 systemd SSH service；请从控制台或其它管理通道启用。'
            else
                dockerMenuRun protocol list || continue
            fi
            if [[ "${choice}" == 5 || "${choice}" == 10 || "${choice}" == 18 ]]; then
                action=enable defaultRetry=6 defaultFind=600 defaultBan=3600
                confirmation='确认启用受管 WS 站点扫描防护？[y/N]: '
                [[ "${choice}" != 10 ]] || confirmation='确认启用受管控制面防护？[y/N]: '
                [[ "${choice}" != 18 ]] || confirmation='确认启用受管专用 SSH service 防护？[y/N]: '
            else
                action=settings defaultRetry= defaultFind= defaultBan=
                confirmation='确认更新受管 WS 站点扫描参数？[y/N]: '
                [[ "${choice}" != 11 ]] || confirmation='确认更新受管控制面防护参数？[y/N]: '
                [[ "${choice}" != 19 ]] || confirmation='确认更新受管 SSH 防护参数？[y/N]: '
            fi
            if [[ "${#scopeArgs[@]}" == 0 ]]; then
                dockerSetupRead ports '保护 WS 端口（逗号分隔，0 返回）: ' &&
                    [[ -n "${ports}" ]] || continue
                portArgs=("${ports}")
            elif [[ "${scopeArgs[0]}" == ssh ]]; then
                dockerSetupRead unit '专用 SSH systemd service（0 返回）: ' &&
                    [[ -n "${unit}" ]] &&
                    dockerSetupRead target '宿主 SSH 本机 IPv4/IPv6（0 返回）: ' &&
                    [[ -n "${target}" ]] &&
                    dockerSetupRead port '宿主 SSH 端口（0 返回）: ' &&
                    [[ -n "${port}" ]] || continue
                portArgs=("${unit}" "${target}" "${port}")
            fi
            dockerSetupRead maxRetry "失败阈值（1–20，0 返回）${defaultRetry:+ [${defaultRetry}]}: " "${defaultRetry}" &&
                [[ -n "${maxRetry}" ]] &&
                dockerSetupRead findTime "检测窗口秒（60–86400，0 返回）${defaultFind:+ [${defaultFind}]}: " "${defaultFind}" &&
                [[ -n "${findTime}" ]] &&
                dockerSetupRead banTime "封禁秒数（60–604800，0 返回）${defaultBan:+ [${defaultBan}]}: " "${defaultBan}" &&
                [[ -n "${banTime}" ]] || continue
            dockerSetupRead answer "${confirmation}" n || continue
            case "${answer}" in y|Y|yes|YES) ;; *) continue ;; esac
            dockerMenuRun fail2ban "${scopeArgs[@]}" "${action}" "${portArgs[@]}" "${maxRetry}" \
                "${findTime}" "${banTime}" --confirm PADM-DOCKER-EDIT || true
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuMaintenance() {
    local choice answer action path
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 服务维护\n'
        printf '%s\n' '1. 校验部署配置' '2. 更新镜像与控制脚本' '3. 回滚最近更新' '4. 卸载服务与控制命令（保留数据）' \
            '5. Fail2ban 维护' '6. 导出灾备归档' '7. 只读校验灾备归档' '8. 预览灾备恢复（空目标）' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1) dockerMenuRun validate || true; continue ;;
        2)
            dockerSetupRead answer '确认更新镜像与控制脚本？[y/N]: ' n || continue
            case "${answer}" in y|Y|yes|YES) ;; *) continue ;; esac
            action=update
            ;;
        3) action=rollback ;;
        4)
            dockerSetupRead answer '确认停止服务并卸载控制命令（保留状态、配置和数据）？[y/N]: ' n || continue
            case "${answer}" in y|Y|yes|YES) ;; *) continue ;; esac
            action=uninstall
            ;;
        5) dockerMenuFail2ban; continue ;;
        6|7)
            if [[ "${choice}" == 6 ]]; then
                action=export
                dockerSetupRead path '新灾备归档绝对路径（不覆盖已有文件，0 返回）: ' || continue
            else
                action=verify
                dockerSetupRead path '待校验灾备归档绝对路径（0 返回）: ' || continue
            fi
            [[ -n "${path}" ]] || continue
            dockerMenuRun backup "${action}" "${path}" || true
            continue
            ;;
        8)
            dockerSetupRead path '待预览恢复的灾备归档绝对路径（0 返回）: ' || continue
            [[ -n "${path}" ]] || continue
            dockerMenuRun restore preview "${path}" || true
            continue
            ;;
        *) printf '无效选项，请重新选择。\n'; continue ;;
        esac
        if dockerMenuRun "${action}"; then
            [[ "${action}" == uninstall ]] ||
                printf '控制版本已切换，请重新打开 padm-docker 菜单。\n'
            # 非零返回仅通知主菜单结束旧会话，不把动作失败当作退出。
            return 1
        fi
    done
}

dockerMenu() {
    local choice
    if [[ "$#" -ne 0 || ! -t 0 || ! -t 1 ]]; then
        dockerUsage
        return "${PADM_DOCKER_RC_USAGE}"
    fi
    dockerMenuCli >/dev/null || return $?
    # Bash 会在信号处理后继续表单 read，显式返回才能立即取消当前字段。
    trap 'dockerMenuInterrupted 130; [[ "${FUNCNAME[0]:-}" != dockerSetupRead ]] || return 130' INT
    trap 'dockerMenuInterrupted 143' TERM
    dockerMenuRun status || true
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 管理菜单\n'
        printf '%s\n' \
            '1. 查看状态' \
            '2. 安装与重装' \
            '3. 启动服务' \
            '4. 停止服务' \
            '5. 重启服务' \
            '6. 查看日志' \
            '7. 编辑配置/导入原始规格' \
            '8. 证书管理' \
            '9. 协议与入口' \
            '10. 账号管理' \
            '11. 订阅管理' \
            '12. 业务备份恢复' \
            '13. 核心升级评估' \
            '14. Xray Geo 数据' \
            '15. 控制连接' \
            '16. 站点管理' \
            '17. 路由与出站' \
            '18. 服务维护' \
            '0. 退出'
        printf '请选择: '
        if ! IFS= read -r choice; then
            if [[ "${DOCKER_MENU_SIGNAL}" -eq 130 ]]; then
                continue
            fi
            break
        fi
        case "${choice}" in
        0) break ;;
        1) dockerMenuRun status || true ;;
        2) dockerMenuInstall ;;
        3) dockerMenuRun up || true ;;
        4) dockerMenuRun down || true ;;
        5) dockerMenuRun restart || true ;;
        6) dockerMenuRun logs --tail 100 --follow || true ;;
        7) dockerMenuRun edit || true ;;
        8) dockerMenuRun tls manage || true ;;
        9) dockerMenuProtocols ;;
        10) dockerMenuAccounts ;;
        11) dockerMenuSubscriptions ;;
        12) dockerMenuBusiness ;;
        13) dockerMenuRun assess || true ;;
        14) dockerMenuGeo ;;
        15) dockerMenuControl ;;
        16) dockerMenuSites ;;
        17) dockerMenuRouting ;;
        18) dockerMenuMaintenance || break ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
    trap - INT TERM
    return 0
}
