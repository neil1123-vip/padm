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
        ( "${1:-}" == tls && "${2:-}" == manage ) ]]; then
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
        *) printf '无效选项，请重新选择。\n' ;;
        esac
    done
    trap - INT TERM
    return 0
}
