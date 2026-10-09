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
        ( ( "${1:-}" == subscription || "${1:-}" == share ) &&
          "${2:-}" != list && "${2:-}" != content && "${2:-}" != links ) ||
        ( "${1:-}" == tls && "${2:-}" == manage ) ||
        ( "${1:-}" == control && "${2:-}" != status ) ||
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
        printf '%s\n' '1. 查看入口' '2. 查看分享链接' '3. 编辑参数/复制或删除入口' '4. 重生成 Reality 参数' '5. Reality 目标站管理' '6. Reality 443 共存' '7. 分享订阅管理' '0. 返回'
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

dockerMenuSubscriptions() {
    local choice groupId name accounts listeners enabled answer
    local -a action=()
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 分享订阅管理\n'
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
    local choice address port peer output expiry invitation listener
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 控制连接\n'
        printf '%s\n' '1. 查看角色状态' '2. 初始化主控' '3. 邀请或轮换凭据' '4. 撤销授权' \
            '5. 接入被控角色' '6. 同步受管账号' '0. 返回'
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
                dockerSetupRead listener '映射入口 ID（0 返回）: ' &&
                [[ -n "${listener}" ]] || continue
            dockerMenuRun control join --invite "${invitation}" --listener "${listener}" || true
            ;;
        6)
            dockerSetupRead invitation '私有邀请文件绝对路径（0 返回）: ' &&
                [[ -n "${invitation}" ]] || continue
            dockerMenuRun control sync --invite "${invitation}" || true
            ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuSites() {
    local choice directory url listener alpnChoice
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 站点管理\n'
        printf '%s\n' '1. 默认页' '2. 发布静态目录' '3. 302 跳转' '4. 查看站点模式' \
            '5. ALPN 诊断' '6. 修复为推荐 ALPN' '7. 手动设置 ALPN' '0. 返回'
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
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuRegion() {
    local choice mode extra
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 区域阻断策略\n'
        printf '%s\n' '1. 屏蔽 geosite:cn + geoip:cn' '2. 仅屏蔽 geosite:cn' \
            '3. 仅屏蔽 geoip:cn' '4. 关闭区域策略' '0. 返回'
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
            dockerSetupRead extra '追加直连例外规则（逗号分隔，留空无追加，0 返回）: ' || continue
            if [[ -n "${extra}" ]]; then
                dockerMenuRun edit --region "${mode}" --region-allow "${extra}" || true
            else
                dockerMenuRun edit --region "${mode}" || true
            fi
            ;;
        4) dockerMenuRun edit --region-off || true ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuIPv6() {
    local choice domains
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker IPv6 域名出站\n'
        printf '%s\n' '1. 替换 IPv6 域名规则' '2. IPv6 默认出站' \
            '3. 关闭 IPv6 出站策略' '4. 查看路由状态' '0. 返回'
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
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuRouting() {
    local choice input
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker 路由与出站\n'
        printf '%s\n' '1. 启用 SOCKS5 出站' '2. 关闭 SOCKS5 出站' '3. 查看路由状态' \
            '4. 替换 SOCKS5 域名规则' '5. 切换 SOCKS5 全局出站' \
            '6. 设置 DNS 分流' '7. 关闭 DNS 分流' '8. 设置 DNS/hosts 覆盖' \
            '9. 关闭 DNS/hosts 覆盖' '10. 设置 Direct 直连例外' \
            '11. 关闭 Direct 直连例外' '12. 设置 Block 域名阻断' \
            '13. 关闭 Block 域名阻断' '14. 设置 IP/CIDR 阻断' \
            '15. 关闭 IP/CIDR 阻断' '16. 启用 BT 协议阻断' \
            '17. 关闭 BT 协议阻断' '18. 区域阻断策略' '19. IPv6 域名出站' '20. WARP 出站' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1)
            dockerSetupRead input 'root 私有 SOCKS5 JSON 文件绝对路径（0 返回）: ' &&
                [[ -n "${input}" ]] || continue
            dockerMenuRun edit --socks5 "${input}" || true
            ;;
        2) dockerMenuRun edit --socks5-off || true ;;
        3) dockerMenuRun protocol routing-status || true ;;
        4)
            dockerSetupRead input 'SOCKS5 域名规则（逗号分隔；domain:/full:/keyword:/geosite:）：' &&
                [[ -n "${input}" ]] || continue
            dockerMenuRun edit --socks5-domains "${input}" || true
            ;;
        5) dockerMenuRun edit --socks5-global || true ;;
        6)
            dockerSetupRead input 'root 私有 DNS JSON 文件绝对路径（0 返回）: ' &&
                [[ -n "${input}" ]] || continue
            dockerMenuRun edit --dns "${input}" || true
            ;;
        7) dockerMenuRun edit --dns-off || true ;;
        8)
            dockerSetupRead input 'root 私有 hosts JSON 文件绝对路径（0 返回）: ' &&
                [[ -n "${input}" ]] || continue
            dockerMenuRun edit --hosts "${input}" || true
            ;;
        9) dockerMenuRun edit --hosts-off || true ;;
        10|12)
            dockerSetupRead input 'root 私有域名规则 JSON 文件绝对路径（0 返回）: ' &&
                [[ -n "${input}" ]] || continue
            if [[ "${choice}" == 10 ]]; then
                dockerMenuRun edit --direct "${input}" || true
            else
                dockerMenuRun edit --block "${input}" || true
            fi
            ;;
        11) dockerMenuRun edit --direct-off || true ;;
        13) dockerMenuRun edit --block-off || true ;;
        14)
            dockerSetupRead input 'root 私有 IP/CIDR 规则 JSON 文件绝对路径（0 返回）: ' &&
                [[ -n "${input}" ]] || continue
            dockerMenuRun edit --block-ips "${input}" || true
            ;;
        15) dockerMenuRun edit --block-ips-off || true ;;
        16) dockerMenuRun edit --block-bt || true ;;
        17) dockerMenuRun edit --block-bt-off || true ;;
        18) dockerMenuRegion ;;
        19) dockerMenuIPv6 ;;
        20) dockerMenuWarp ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
}

dockerMenuWarp() {
    local choice input
    while :; do
        DOCKER_MENU_SIGNAL=0
        printf '\nDocker WARP 出站\n'
        printf '%s\n' '1. 导入 WARP 配置' '2. 关闭 WARP 出站' '3. 查看路由状态' '0. 返回'
        printf '请选择: '
        if ! IFS= read -r choice; then
            [[ "${DOCKER_MENU_SIGNAL}" -ne 130 ]] || continue
            return 0
        fi
        case "${choice}" in
        0) return 0 ;;
        1)
            dockerSetupRead input 'root 私有 WARP JSON 文件绝对路径（0 返回）: ' &&
                [[ -n "${input}" ]] || continue
            dockerMenuRun edit --warp "${input}" || true
            ;;
        2) dockerMenuRun edit --warp-off || true ;;
        3) dockerMenuRun protocol routing-status || true ;;
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
            '11. 分享订阅管理' \
            '12. 业务备份恢复' \
            '13. 核心升级评估' \
            '14. Xray Geo 数据' \
            '15. 控制连接' \
            '16. 站点管理' \
            '17. 路由与出站' \
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
        11) dockerMenuSubscriptions ;;
        12) dockerMenuBusiness ;;
        13) dockerMenuRun assess || true ;;
        14) dockerMenuGeo ;;
        15) dockerMenuControl ;;
        16) dockerMenuSites ;;
        17) dockerMenuRouting ;;
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
    trap - INT TERM
    return 0
}
