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
    [[ "$1" -ne 143 ]] || exit 143
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
    if [[ "${1:-}" == setup || "${1:-}" == edit ||
        ( "${1:-}" == account && "${2:-}" != list ) ||
        ( "${1:-}" == tls && "${2:-}" == manage ) ||
        ( "${1:-}" == protocol && ( "${2:-}" == select-target ||
          "${2:-}" == scan-targets || "${2:-}" == scan-targets-asn ) ) ]]; then
        # 交互配置必须与菜单共用前台进程组，否则后台 read 会收到 SIGTTIN。
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

dockerMenuProtocols() {
    local choice listener
    dockerMenuRun protocol list || true
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 协议与入口\n'
        printf '%s\n' '1. 查看入口' '2. 查看分享链接' '3. 编辑参数/复制或删除入口' '4. 重生成 Reality 参数' '5. Reality 目标站管理' '6. Reality 443 共存' '0. 返回'
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
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenu() {
    local choice
    if [[ "$#" -ne 0 || ! -t 0 || ! -t 1 ]]; then
        dockerUsage
        return "${PADM_DOCKER_RC_USAGE}"
    fi
    dockerMenuCli >/dev/null || return $?
    trap 'dockerMenuInterrupted 130' INT
    trap 'dockerMenuInterrupted 143' TERM
    dockerMenuRun status || true
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 管理菜单\n'
        printf '%s\n' \
            '1. 查看状态' \
            '2. 首次配置' \
            '3. 启动服务' \
            '4. 停止服务' \
            '5. 重启服务' \
            '6. 查看日志' \
            '7. 编辑配置/导入原始规格' \
            '8. 证书管理' \
            '9. 协议与入口' \
            '10. 账号管理' \
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
        2) dockerMenuRun setup || true ;;
        3) dockerMenuRun up || true ;;
        4) dockerMenuRun down || true ;;
        5) dockerMenuRun restart || true ;;
        6) dockerMenuRun logs --tail 100 --follow || true ;;
        7) dockerMenuRun edit || true ;;
        8) dockerMenuRun tls manage || true ;;
        9) dockerMenuProtocols ;;
        10) dockerMenuAccounts ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
    trap - INT TERM
    return 0
}
