#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-menu-signals.XXXXXX")
export SIGNAL_PROJECT_ROOT="${PROJECT_ROOT}" SIGNAL_TEST_ROOT="${TEST_ROOT}"
export TMPDIR="${TEST_ROOT}/tmp" PADM_NO_COLOR=1
mkdir -p "${TEST_ROOT}/config" "${TMPDIR}"
printf '{"tls":{"domain":"ws.example.com"}}\n' >"${TEST_ROOT}/config/spec.json"
printf '{}\n' >"${TEST_ROOT}/deployment.json"
printf 'PADM_OPS_IMAGE=fixture\n' >"${TEST_ROOT}/images.env"
cleanup() {
    local file pid
    for file in "${TEST_ROOT}/menu.pid" "${TEST_ROOT}/setup.pid" "${TEST_ROOT}/worker.pid"; do
        [[ -f "${file}" ]] || continue
        pid=$(<"${file}")
        kill -TERM "${pid}" 2>/dev/null || true
    done
    rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT
fail() {
    [[ ! -f "${TEST_ROOT}/control.log" ]] || sed -n '1,100p' "${TEST_ROOT}/control.log" >&2
    printf 'docker-menu-signals-regression-fail: %s\n' "$*" >&2
    exit 1
}
for tool in script timeout; do command -v "${tool}" >/dev/null || fail "missing ${tool}"; done
export SHELL
SHELL=$(command -v bash)
cat >"${TEST_ROOT}/cli.sh" <<'EOF'
#!/usr/bin/env bash
set -u
case "${1:-}" in
status|setup|edit|tls|control|fail2ban|protocol)
    [[ "${1:-}" != status || "${SIGNAL_STATUS_WAIT:-0}" == 1 ]] || exit 0
    [[ "${1:-}" != control || "${2:-}" != status ]] || exit 0
    printf '%s\n' "${BASHPID}" >"${SIGNAL_TEST_ROOT}/setup.pid"
    trap 'printf "setup-cleaned\n" >"${SIGNAL_TEST_ROOT}/setup.cleaned"; printf "setup-cleaned\n"; exit 143' TERM
    source "${SIGNAL_PROJECT_ROOT}/docker/lib/setup.sh"
    source "${SIGNAL_PROJECT_ROOT}/shell/core/locale.sh"
    printf 'setup-ready\n'
    waitWorker() {
        # 耗时命令与孙进程均实际运行，不能仅终止 CLI 伪造清理完成。
        workerOutput=$(
            bash -c '
                printf "%s\n" "${BASHPID}" >"${SIGNAL_TEST_ROOT}/worker.pid"
                exec sleep 120
            '
            printf 'worker-finished\n'
        )
        printf '%s\n' "${workerOutput}"
    }
    if [[ "${1:-}" == status ]]; then
        printf '%s\n' status >>"${SIGNAL_TEST_ROOT}/control.calls"
        waitWorker
    elif [[ "${1:-}" == protocol ]]; then
        [[ "$#" -eq 2 && ( "$2" == tproxy-status || "$2" == redirect-status || "$2" == xhttp-status ) ]] || exit 2
        printf '%s\n' "$*" >>"${SIGNAL_TEST_ROOT}/control.calls"
        waitWorker
    elif [[ "${1:-}" == fail2ban ]]; then
        [[ "${2:-}" == control ]] || exit 2
        case "${3:-}" in
        disable) [[ "$#" -eq 5 && "$4" == --confirm && "$5" == PADM-DOCKER-EDIT ]] || exit 2 ;;
        enable|settings)
            [[ "$#" -eq 8 && "$4 $5 $6" == '6 600 3600' &&
                "$7" == --confirm && "$8" == PADM-DOCKER-EDIT ]] || exit 2
            ;;
        *) exit 2 ;;
        esac
        printf '%s\n' "$*" >>"${SIGNAL_TEST_ROOT}/control.calls"
        waitWorker
    elif [[ "${1:-}" == control ]]; then
        [[ "$#" -eq 2 && ( "$2" == source-check || "$2" == log-rotate ) ]] || exit 2
        printf '%s\n' "$*" >>"${SIGNAL_TEST_ROOT}/control.calls"
        waitWorker
    elif [[ "${1:-}" == tls ]]; then
        [[ "${2:-}" == manage ]] || exit 2
        dockerInstallRoot() { printf '%s\n' "${SIGNAL_TEST_ROOT}"; }
        dockerError() { printf '%s\n' "$*" >&2; }
        dockerDomainIsValid() { [[ "$1" == ws.example.com ]]; }
        dockerConfigureSpecValidate() { return 0; }
        dockerManagedSpecMatchesDeployment() { return 0; }
        dockerResolveOpsImage() { printf 'fixture\n'; }
        dockerTlsValidateCommand() { waitWorker; }
        PADM_DOCKER_RC_STATE=1
        PADM_DOCKER_RC_USAGE=2
        dockerTlsManageCommand
    elif [[ "${SIGNAL_MODE}" == input ]]; then
        dockerSetupRead answer 'setup-input: '
    else
        waitWorker
    fi
    ;;
menu)
    printf '%s\n' "${BASHPID}" >"${SIGNAL_TEST_ROOT}/menu.pid"
    source "${SIGNAL_PROJECT_ROOT}/docker/lib/setup.sh"
    source "${SIGNAL_PROJECT_ROOT}/docker/lib/menu.sh"
    dockerMenuCli() { printf '%s\n' "${SIGNAL_TEST_ROOT}/cli.sh"; }
    dockerError() { printf '%s\n' "$*" >&2; }
    PADM_DOCKER_RC_STATE=1
    PADM_DOCKER_RC_USAGE=2
    # 首配必须主动关闭调用方已开启的 monitor，退出动作后恢复。
    set -m
    dockerMenu
    ;;
esac
EOF
waitText() {
    local attempt count=${2:-1}
    for ((attempt = 0; attempt < 200; attempt++)); do
        [[ "$(grep -Fc "$1" "${TEST_ROOT}/control.log" 2>/dev/null || true)" -ge "${count}" ]] && return 0
        sleep 0.05
    done
    return 1
}
for mode in input worker edit-input edit-worker tls-input tls-worker \
    status-int status-term \
    control-source-int control-source-term control-rotate-int control-rotate-term \
    fail2ban-disable-int fail2ban-disable-term fail2ban-enable-int fail2ban-enable-term \
    fail2ban-settings-int fail2ban-settings-term \
    {tproxy,redirect}-{2,5}-{term,int} xhttp-2-{term,int}; do
    export SIGNAL_MODE="${mode##*-}" SIGNAL_STATUS_WAIT=0
    case "${mode}" in control-*|fail2ban-*|tproxy-*|redirect-*|xhttp-*|status-*) SIGNAL_MODE=worker ;; esac
    [[ "${mode}" != status-* ]] || SIGNAL_STATUS_WAIT=1
    # Linux /proc 的后代终止另行实测；MSYS2 只覆盖真实 PTY 输入。
    [[ "${SIGNAL_MODE}" != worker || "$(uname -s)" == Linux ]] || continue
    rm -f -- "${TEST_ROOT}/menu.pid" "${TEST_ROOT}/setup.pid" "${TEST_ROOT}/worker.pid" \
        "${TEST_ROOT}/input" "${TEST_ROOT}/control.log" "${TEST_ROOT}/control.calls" "${TEST_ROOT}/setup.cleaned"
    mkfifo "${TEST_ROOT}/input"
    (
        exec 3>"${TEST_ROOT}/input"
        waitText 'padm 管理面板（Docker）' || exit 11
        case "${mode}" in
        status-*) ;;
        xhttp-*)
            printf '3\n' >&3
            waitText '┌─ 协议与入口' || exit 36
            printf '9\n' >&3
            waitText 'Docker 协议与入口' || exit 32
            printf '10\n' >&3
            waitText 'Docker XHTTP 管理' || exit 33
            printf '2\n' >&3
            ;;
        tproxy-*|redirect-*)
            printf '5\n' >&3
            waitText '┌─ 路由与访问控制' || exit 37
            printf '1\n' >&3
            waitText '┌─ 分流工具' || exit 38
            printf '9\n' >&3
            waitText 'Docker 路由与出站' || exit 28
            title=TProxy
            routeChoice=43
            [[ "${mode}" != redirect-* ]] || { title=Redirect; routeChoice=47; }
            printf '%s\n' "${routeChoice}" >&3
            waitText "Docker ${title} 管理" || exit 29
            action=${mode#*-}
            printf '%s\n' "${action%-*}" >&3
            ;;
        fail2ban-*)
            printf '7\n' >&3
            waitText '┌─ 系统与脚本' || exit 39
            printf '1\n' >&3
            waitText 'Docker 服务维护' || exit 21
            printf '5\n' >&3
            waitText 'Docker Fail2ban 维护' || exit 22
            case "${mode}" in
            fail2ban-disable-*) printf '9\ny\n' >&3 ;;
            *)
                if [[ "${mode}" == fail2ban-enable-* ]]; then printf '10\n' >&3; else printf '11\n' >&3; fi
                waitText '失败阈值（1–20，0 返回）' || exit 23
                printf '6\n600\n3600\ny\n' >&3
                ;;
            esac
            ;;
        control-*)
            printf '2\n' >&3
            waitText '┌─ 订阅与用户' || exit 40
            printf '4\n' >&3
            waitText 'Docker 控制连接' || exit 18
            if [[ "${mode}" == control-source-* ]]; then
                printf '7\n' >&3
                waitText 'Peer ID（v2 必填，v1 可留空，0 返回）' || exit 27
                printf '\n' >&3
            else
                printf '8\n' >&3
            fi
            ;;
        edit-*)
            printf '6\n' >&3
            waitText '┌─ 核心与服务' || exit 41
            printf '9\n' >&3
            ;;
        tls-*)
            printf '4\n' >&3
            waitText '┌─ 站点与证书' || exit 42
            printf '2\n' >&3
            ;;
        *)
            printf '1\n' >&3
            waitText 'Docker 安装与重装' || exit 26
            printf '1\n' >&3
            ;;
        esac
        case "${mode}" in tproxy-*|redirect-*|xhttp-*|status-*) ;; *) waitText 'setup-ready' || exit 12 ;; esac
        if [[ "${mode}" == tls-* ]]; then
            waitText '证书操作: ' || exit 17
            if [[ "${SIGNAL_MODE}" == worker ]]; then printf '1\n\ny\n' >&3; fi
        fi
        if [[ "${SIGNAL_MODE}" == worker ]]; then
            for ((attempt = 0; attempt < 200; attempt++)); do
                [[ ! -f "${TEST_ROOT}/worker.pid" ]] || break
                sleep 0.05
            done
            [[ -f "${TEST_ROOT}/worker.pid" ]] || exit 13
        else
            if [[ "${mode}" != tls-* ]]; then waitText 'setup-input: ' || exit 14; fi
        fi
        if [[ "${mode}" == status-int ]]; then
            printf '\003' >&3
            waitText '请选择: ' || exit 48
            # 自动状态读取被中断后，真正的 EOF 必须结束会话，不能再次读取状态。
            printf '\004' >&3
            for ((attempt = 0; attempt < 100; attempt++)); do
                kill -0 "$(<"${TEST_ROOT}/menu.pid")" 2>/dev/null || exit 0
                sleep 0.05
            done
            exit 49
        elif [[ "${mode}" == *-int ]]; then
            printf '\003' >&3
            if [[ "${mode}" == xhttp-* ]]; then
                waitText 'Docker XHTTP 管理' 2 || exit 34
                printf '0\n' >&3
                waitText 'Docker 协议与入口' 2 || exit 35
                printf '0\n' >&3
                waitText '┌─ 协议与入口' 2 || exit 43
            elif [[ "${mode}" == tproxy-* || "${mode}" == redirect-* ]]; then
                waitText "Docker ${title} 管理" 2 || exit 30
                printf '0\n' >&3
                waitText 'Docker 路由与出站' 2 || exit 31
                printf '0\n' >&3
                waitText '┌─ 分流工具' 2 || exit 44
                printf '0\n' >&3
                waitText '┌─ 路由与访问控制' 2 || exit 45
            elif [[ "${mode}" == fail2ban-* ]]; then
                waitText 'Docker Fail2ban 维护' 2 || exit 24
                printf '0\n' >&3
                waitText 'Docker 服务维护' 2 || exit 25
                printf '0\n' >&3
                waitText '┌─ 系统与脚本' 2 || exit 46
            else
                waitText 'Docker 控制连接' 2 || exit 19
                printf '0\n' >&3
                waitText '┌─ 订阅与用户' 2 || exit 47
            fi
            printf '0\n' >&3
            waitText 'padm 管理面板（Docker）' 2 || exit 20
            printf '0\n' >&3
            exit 0
        fi
        kill -TERM "$(<"${TEST_ROOT}/menu.pid")" || exit 15
        for ((attempt = 0; attempt < 100; attempt++)); do
            kill -0 "$(<"${TEST_ROOT}/menu.pid")" 2>/dev/null || exit 0
            sleep 0.05
        done
        exit 16
    ) &
    feeder=$!
    commandArgs=
    printf -v commandArgs '%q ' bash "${TEST_ROOT}/cli.sh" menu
    commandArgs="exec ${commandArgs}"
    rc=0
    timeout --signal=TERM --kill-after=2 20 script -q -e -E never -f \
        -c "${commandArgs}" "${TEST_ROOT}/control.log" <"${TEST_ROOT}/input" \
        >"${TEST_ROOT}/stdout.log" 2>&1 || rc=$?
    wait "${feeder}" || fail "${mode}: driver failed at checkpoint $?"
    expected=143
    [[ "${mode}" != *-int ]] || expected=0
    [[ "${rc}" -eq "${expected}" ]] || fail "${mode}: expected ${expected}, got ${rc}"
    [[ -f "${TEST_ROOT}/setup.cleaned" ]] || fail "${mode}: CLI did not clean up"
    ! kill -0 "$(<"${TEST_ROOT}/setup.pid")" 2>/dev/null || fail "${mode}: CLI survived"
    if [[ "${SIGNAL_MODE}" == worker ]]; then
        ! kill -0 "$(<"${TEST_ROOT}/worker.pid")" 2>/dev/null || fail 'worker survived'
    fi
    if [[ "${mode}" == status-* ]]; then
        [[ "$(<"${TEST_ROOT}/control.calls")" == status ]] ||
            fail "${mode}: interrupted homepage repeated the status backend"
        ! compgen -G "${TMPDIR:-/tmp}/padm-menu-status.*" >/dev/null ||
            fail "${mode}: homepage status snapshot survived"
    fi
    if [[ "${mode}" == tproxy-* || "${mode}" == redirect-* || "${mode}" == xhttp-* ]]; then
        [[ "$(<"${TEST_ROOT}/control.calls")" == "protocol ${mode%%-*}-status" ]] ||
            fail "${mode}: protocol status backend was repeated or dispatched incorrectly"
        ! compgen -G "${TMPDIR:-/tmp}/padm-${mode%%-*}-menu.*" >/dev/null ||
            fail "${mode}: status snapshot survived"
    fi
    if [[ "${mode}" == control-* ]]; then
        action=source-check
        [[ "${mode}" != control-rotate-* ]] || action=log-rotate
        [[ "$(<"${TEST_ROOT}/control.calls")" == "control ${action}" ]] ||
            fail "${mode}: control backend was repeated or dispatched incorrectly"
    elif [[ "${mode}" == fail2ban-* ]]; then
        action=${mode#fail2ban-}
        action=${action%-*}
        expectedCall="fail2ban control ${action}"
        [[ "${action}" == disable ]] || expectedCall+=' 6 600 3600'
        expectedCall+=' --confirm PADM-DOCKER-EDIT'
        [[ "$(<"${TEST_ROOT}/control.calls")" == "${expectedCall}" ]] ||
            fail "${mode}: control Fail2ban backend was repeated or dispatched incorrectly"
    fi
done
printf 'docker-menu-signals-regression-ok\n'
