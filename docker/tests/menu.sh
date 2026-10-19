#!/usr/bin/env bash
set -euo pipefail

MENU_SCOPE=${PADM_DOCKER_MENU_SCOPE:-full}
case "${MENU_SCOPE}" in
full|routing|port-alias|tun|block-ips-resolved|xhttp|control|maintenance) ;;
*) printf 'docker-menu-regression-fail: invalid scope: %s\n' "${MENU_SCOPE}" >&2; exit 1 ;;
esac
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-menu.XXXXXX")
MOCK_BIN="${TEST_ROOT}/bin"
DOCKER_LOG="${TEST_ROOT}/docker.log"
COMPOSE_LOG="${TEST_ROOT}/compose.log"
DOWNLOAD_MARKER="${TEST_ROOT}/download.called"
CONTROL_LOG=
MAIN_MENU_TITLE='padm 管理面板（Docker）'
mkdir -p "${MOCK_BIN}" "${TEST_ROOT}/native" "${TEST_ROOT}/systemd"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

fail() {
    if [[ -n "${CONTROL_LOG}" && -f "${CONTROL_LOG}" ]]; then
        sed 's/^/  /' "${CONTROL_LOG}" >&2
    fi
    printf 'docker-menu-regression-fail: %s\n' "$*" >&2
    exit 1
}

command -v script >/dev/null 2>&1 || fail 'util-linux script is required for real PTY checks'
command -v timeout >/dev/null 2>&1 || fail 'timeout is required for bounded PTY checks'
if [[ "${MENU_SCOPE}" == full ]]; then
    bash "${PROJECT_ROOT}/docker/tests/menu-signals.sh"
fi

cat >"${MOCK_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
-m) printf 'x86_64\n' ;;
*) printf 'Linux\n' ;;
esac
EOF
cat >"${MOCK_BIN}/id" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == -u ]] && printf '0\n'
EOF
cat >"${MOCK_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >>"${FAKE_DOCKER_LOG:?}"
case "${1:-}" in
info)
    if [[ "${2:-}" == --format ]]; then
        case "${3:-}" in
        '{{.OSType}}') printf 'linux\n' ;;
        '{{.Architecture}}') printf 'x86_64\n' ;;
        '{{json .SecurityOptions}}') printf '["name=seccomp,profile=builtin"]\n' ;;
        *) exit 1 ;;
        esac
    fi
    ;;
context) printf 'unix:///var/run/docker.sock\n' ;;
ps) ;;
compose)
    if [[ "${2:-}" == version ]]; then
        printf 'v2.29.1\n'
        exit 0
    fi
    printf '%s\n' "$*" >>"${FAKE_COMPOSE_LOG:?}"
    case " $* " in
    *' logs '*)
        if [[ "${FAKE_LOG_STREAM:-0}" == 1 ]]; then
            trap 'exit 130' INT
            trap 'exit 143' TERM
            printf '%s\n' "${BASHPID}" >"${FAKE_LOG_PID:?}"
            : >"${FAKE_LOG_READY:?}"
            printf 'mock-log-ready\n'
            while true; do sleep 1; done
        fi
        ;;
    *' restart '*)
        [[ "${FAKE_RESTART_FAIL:-0}" != 1 ]] || exit 1
        ;;
    esac
    ;;
*) exit 1 ;;
esac
EOF
cat >"${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
: >"${FAKE_DOWNLOAD_MARKER:?}"
exit 1
EOF
cp "${MOCK_BIN}/curl" "${MOCK_BIN}/wget"
printf '#!/usr/bin/env bash\nexit 0\n' >"${MOCK_BIN}/systemctl"
chmod 0755 "${MOCK_BIN}/"*

export PATH="${MOCK_BIN}:${PATH}" MSYS=winsymlinks:sys SHELL PADM_NO_COLOR=1
SHELL=$(command -v bash)
export DOCKER_HOST=
export PADM_NATIVE_INSTALL_DIR="${TEST_ROOT}/native"
export PADM_DOCKER_SYSTEMD_DIR="${TEST_ROOT}/systemd"
export PADM_DOCKER_LOCK_TIMEOUT=1
export FAKE_DOCKER_LOG="${DOCKER_LOG}" FAKE_COMPOSE_LOG="${COMPOSE_LOG}"
export FAKE_DOWNLOAD_MARKER="${DOWNLOAD_MARKER}" FAKE_LOG_READY="${TEST_ROOT}/logs.ready"
export FAKE_LOG_PID="${TEST_ROOT}/logs.pid"

runNonTty() {
    local expected=$1 name=$2 entry=$3 actual=0
    shift 3
    CONTROL_LOG="${TEST_ROOT}/${name}.log"
    bash -u "${entry}" "$@" </dev/null >"${CONTROL_LOG}" 2>&1 || actual=$?
    [[ "${actual}" -eq "${expected}" ]] || fail "${name}: expected rc=${expected}, got rc=${actual}"
}

waitForText() {
    local pattern=$1 file=$2 count=${3:-1} deadline=$((SECONDS + 15))
    [[ "${pattern}" != 'Docker 管理菜单' ]] || pattern=${MAIN_MENU_TITLE}
    while ((SECONDS < deadline)); do
        if [[ -f "${file}" ]] && [[ "$(grep -Fc "${pattern}" "${file}" || true)" -ge "${count}" ]]; then
            return 0
        fi
        sleep 0.01
    done
    return 1
}

assertNoLock() {
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] ||
        fail 'menu retained the deployment lock'
}

targetReplyRaw() {
    local prompt=$1 input=$2 count root=${TLS_WIZARD_ROOT:-${PADM_DOCKER_INSTALL_DIR}}
    count=$((${targetPrompts["${prompt}"]:-0} + 1))
    targetPrompts["${prompt}"]=${count}
    waitForText "${prompt}" "${CONTROL_LOG}" "${count}" || {
        printf 'PTY 等待提示超时: %s（第 %s 次）\n' "${prompt}" "${count}" >&2
        exit 31
    }
    assertNoLock
    [[ ! -e "${root}/locks/deployment.lock" ]] || exit 32
    printf '%s' "${input}" >&3
}

targetReply() {
    if [[ "$1" == 'Docker 管理菜单' ]]; then
        targetMainReply "$2"
    else
        targetReplyRaw "$@"
    fi
}

targetMainReply() {
    local input=$1 choice=${1%$'\n'} parent
    local -a path=()
    for parent in "${menuParents[@]}"; do
        targetReplyRaw "┌─ ${parent}" $'0\n'
    done
    menuParents=()
    # 旧编号仅是业务场景的动作键，实际握手使用新版菜单路径。
    case "${choice}" in
    1|3|4|5|6|7|13|14)
        path=('核心与服务')
        case "${choice}" in
        1) input=$'1\n' ;; 3) input=$'2\n' ;; 4) input=$'3\n' ;; 5) input=$'4\n' ;;
        6) input=$'5\n' ;; 7) input=$'9\n' ;; 13) input=$'7\n' ;; 14) input=$'8\n' ;;
        esac
        targetReplyRaw "${MAIN_MENU_TITLE}" $'6\n'
        ;;
    2) input=$'1\n' ;;
    8|16)
        path=('站点与证书')
        [[ "${choice}" != 8 ]] || input=$'2\n'
        [[ "${choice}" != 16 ]] || input=$'1\n'
        targetReplyRaw "${MAIN_MENU_TITLE}" $'4\n'
        ;;
    9)
        path=('协议与入口')
        input=$'9\n'
        targetReplyRaw "${MAIN_MENU_TITLE}" $'3\n'
        ;;
    10|11|12|15)
        path=('订阅与用户')
        case "${choice}" in
        10) input=$'1\n' ;; 11) input=$'2\n' ;; 12) input=$'5\n' ;; 15) input=$'4\n' ;;
        esac
        targetReplyRaw "${MAIN_MENU_TITLE}" $'2\n'
        ;;
    17)
        path=('分流工具' '路由与访问控制')
        input=$'9\n'
        targetReplyRaw "${MAIN_MENU_TITLE}" $'5\n'
        targetReplyRaw '┌─ 路由与访问控制' $'1\n'
        ;;
    18)
        path=('系统与脚本')
        input=$'1\n'
        targetReplyRaw "${MAIN_MENU_TITLE}" $'7\n'
        ;;
    esac
    if [[ "${#path[@]}" -eq 0 ]]; then
        targetReplyRaw "${MAIN_MENU_TITLE}" "${input}"
    else
        targetReplyRaw "┌─ ${path[0]}" "${input}"
        menuParents=("${path[@]}")
        [[ "${choice}" != 4 ]] ||
            targetReplyRaw '停止服务会中断连接，确认继续？' $'y\n'
    fi
}

runSubscriptionsDriver() {
    local scenario=$1
    local -A targetPrompts=()
    targetReply 'Docker 管理菜单' $'11\n'
    case "${scenario}" in
    flow)
        targetReply 'Docker 订阅管理' $'10\n'
        targetReply 'Docker 订阅管理' $'11\n'
        ;;
    cancel|eof)
        targetReply 'Docker 订阅管理' $'8\n'
        if [[ "${scenario}" == eof ]]; then
            targetReply '分享组 ID（0 返回）' $'\004'
        else
            targetReply '分享组 ID（0 返回）' $'0\n'
        fi
        ;;
    esac
    if [[ "${scenario}" == eof ]]; then
        targetReply 'Docker 订阅管理' $'\004'
    else
        targetReply 'Docker 订阅管理' $'0\n'
    fi
    targetReply 'Docker 管理菜单' $'0\n'
}

runTrafficDriver() {
    local scenario=$1 action value accountId=alpha
    local -A targetPrompts=()
    targetReply 'Docker 管理菜单' $'10\n'
    targetReply 'Docker 账号管理' $'9\n'
    case "${scenario}" in
    flow)
        targetReply 'Docker 流量与额度' $'1\n'
        targetReply 'Docker 流量与额度' $'2\n'
        for value in 0 0.5 000.500000; do
            targetReply 'Docker 流量与额度' $'3\n'
            targetReply '流量账号 ID（空输入/0 返回）' $'alpha\n'
            targetReply '额度 GiB（0 不限额，空输入/r 返回）' "${value}"$'\n'
            targetReply '确认设置账号' $'y\n'
        done
        targetReply 'Docker 流量与额度' $'4\n'
        targetReply '流量账号 ID（空输入/0 返回）' $'alpha\n'
        targetReply '确认清零账号' $'y\n'
        ;;
    cancel)
        for action in 3 4; do
            for value in 0 ''; do
                targetReply 'Docker 流量与额度' "${action}"$'\n'
                targetReply '流量账号 ID（空输入/0 返回）' "${value}"$'\n'
            done
        done
        for value in '' r R; do
            targetReply 'Docker 流量与额度' $'3\n'
            targetReply '流量账号 ID（空输入/0 返回）' $'alpha\n'
            targetReply '额度 GiB（0 不限额，空输入/r 返回）' "${value}"$'\n'
        done
        for action in 3 4; do
            for value in '' 0 n; do
                targetReply 'Docker 流量与额度' "${action}"$'\n'
                targetReply '流量账号 ID（空输入/0 返回）' $'alpha\n'
                if [[ "${action}" == 3 ]]; then
                    targetReply '额度 GiB（0 不限额，空输入/r 返回）' $'1\n'
                    targetReply '确认设置账号' "${value}"$'\n'
                else
                    targetReply '确认清零账号' "${value}"$'\n'
                fi
            done
        done
        ;;
    eof)
        for action in 3 4; do
            targetReply 'Docker 流量与额度' "${action}"$'\n'
            targetReply '流量账号 ID（空输入/0 返回）' $'\004'
        done
        targetReply 'Docker 流量与额度' $'3\n'
        targetReply '流量账号 ID（空输入/0 返回）' $'alpha\n'
        targetReply '额度 GiB（0 不限额，空输入/r 返回）' $'\004'
        for action in 3 4; do
            targetReply 'Docker 流量与额度' "${action}"$'\n'
            targetReply '流量账号 ID（空输入/0 返回）' $'alpha\n'
            if [[ "${action}" == 3 ]]; then
                targetReply '额度 GiB（0 不限额，空输入/r 返回）' $'1\n'
                targetReply '确认设置账号' $'\004'
            else
                targetReply '确认清零账号' $'\004'
            fi
        done
        ;;
    status-failed)
        targetReply 'Docker 流量与额度' $'3\n'
        targetReply 'Docker 流量与额度' $'4\n'
        ;;
    invalid|unknown|failed)
        [[ "${scenario}" != unknown ]] || accountId=missing-account
        [[ "${scenario}" != failed ]] || targetReply 'Docker 流量与额度' $'2\n'
        for action in 3 4; do
            [[ "${scenario}" != invalid || "${action}" == 3 ]] || continue
            targetReply 'Docker 流量与额度' "${action}"$'\n'
            targetReply '流量账号 ID（空输入/0 返回）' "${accountId}"$'\n'
            if [[ "${action}" == 3 ]]; then
                value=0.5
                [[ "${scenario}" != invalid ]] || value=not-a-limit
                targetReply '额度 GiB（0 不限额，空输入/r 返回）' "${value}"$'\n'
                targetReply '确认设置账号' $'y\n'
            else
                targetReply '确认清零账号' $'y\n'
            fi
        done
        ;;
    esac
    targetReply 'Docker 流量与额度' $'1\n'
    if [[ "${scenario}" == eof ]]; then
        targetReply 'Docker 流量与额度' $'\004'
    else
        targetReply 'Docker 流量与额度' $'0\n'
    fi
    targetReply 'Docker 账号管理' $'0\n'
    targetReply 'Docker 管理菜单' $'0\n'
}

runTargetsDriver() {
    local scenario=$1
    local -A targetPrompts=()
    targetReply 'Docker 管理菜单' $'9\n'
    targetReply 'Docker 协议与入口' $'5\n'
    case "${scenario}" in
    flow)
        targetReply 'Docker Reality 目标站' $'1\n'
        targetReply 'Reality 入口 ID（空输入检测全部，0 返回）' $'entry-fixture\n'
        targetReply 'Reality 目标站后续操作' $'1\n'
        targetReply '切换目标的 Reality 入口 ID（0 返回）' $'\n'
        targetReply 'fixture-target-input: select-target' $'selected\n'
        targetReply 'Docker Reality 目标站' $'2\n'
        targetReply '请选择刷新范围 [1]' $'\n'
        targetReply 'Docker Reality 目标站' $'2\n'
        targetReply '请选择刷新范围 [1]' $'2\n'
        targetReply 'Docker Reality 目标站' $'2\n'
        targetReply '请选择刷新范围 [1]' $'3\n'
        targetReply 'Docker Reality 目标站' $'3\n'
        targetReply 'fixture-target-input: scan-targets' $'scan\n'
        targetReply 'Docker Reality 目标站' $'4\n'
        targetReply 'fixture-target-input: scan-targets-asn' $'scan-asn\n'
        targetReply 'Docker Reality 目标站' $'5\n'
        targetReply '切换目标的 Reality 入口 ID（0 返回）' $'entry-secondary\n'
        targetReply 'fixture-target-input: select-target' $'selected-secondary\n'
        targetReply 'Docker Reality 目标站' $'6\n'
        targetReply 'Reality 入口 ID（0 返回）' $'entry-fixture\n'
        targetReply 'Reality 目标 host[:port]（0 返回）' $'target.example.com\n'
        targetReply 'Reality SNI [target.example.com]' $'\n'
        targetReply 'Docker Reality 目标站' $'6\n'
        targetReply 'Reality 入口 ID（0 返回）' $'entry-secondary\n'
        targetReply 'Reality 目标 host[:port]（0 返回）' $'alt.example.com:8443\n'
        targetReply 'Reality SNI [alt.example.com]' $'edge.example.net\n'
        targetReply 'Docker Reality 目标站' $'7\n'
        targetReply 'Docker Reality 目标站' $'1\n'
        targetReply 'Reality 入口 ID（空输入检测全部，0 返回）' $'\n'
        targetReply 'Reality 目标站后续操作' $'2\n'
        targetReply '加入黑名单的 Reality 入口 ID（0 返回）' $'entry-secondary\n'
        targetReply '确认将该入口当前目标加入黑名单？[y/N]' $'n\n'
        targetReply 'Docker Reality 目标站' $'1\n'
        targetReply 'Reality 入口 ID（空输入检测全部，0 返回）' $'entry-secondary\n'
        targetReply 'Reality 目标站后续操作' $'2\n'
        targetReply '加入黑名单的 Reality 入口 ID（0 返回）' $'\n'
        targetReply '确认将该入口当前目标加入黑名单？[y/N]' $'y\n'
        ;;
    cancel)
        targetReply 'Docker Reality 目标站' $'1\n'
        targetReply 'Reality 入口 ID（空输入检测全部，0 返回）' $'0\n'
        targetReply 'Docker Reality 目标站' $'5\n'
        targetReply '切换目标的 Reality 入口 ID（0 返回）' $'0\n'
        targetReply 'Docker Reality 目标站' $'6\n'
        targetReply 'Reality 入口 ID（0 返回）' $'0\n'
        targetReply 'Docker Reality 目标站' $'6\n'
        targetReply 'Reality 入口 ID（0 返回）' $'entry-fixture\n'
        targetReply 'Reality 目标 host[:port]（0 返回）' $'0\n'
        targetReply 'Docker Reality 目标站' $'6\n'
        targetReply 'Reality 入口 ID（0 返回）' $'entry-fixture\n'
        targetReply 'Reality 目标 host[:port]（0 返回）' $'target.example.com\n'
        targetReply 'Reality SNI [target.example.com]' $'0\n'
        targetReply 'Docker Reality 目标站' $'2\n'
        targetReply '请选择刷新范围 [1]' $'0\n'
        ;;
    eof)
        targetReply 'Docker Reality 目标站' $'6\n'
        targetReply 'Reality 入口 ID（0 返回）' $'entry-fixture\n'
        targetReply 'Reality 目标 host[:port]（0 返回）' $'target.example.com\n'
        targetReply 'Reality SNI [target.example.com]' $'\004'
        ;;
    failed)
        targetReply 'Docker Reality 目标站' $'1\n'
        targetReply 'Reality 入口 ID（空输入检测全部，0 返回）' $'entry-fixture\n'
        targetReply 'Reality 目标站后续操作' $'3\n'
        ;;
    int|term)
        targetReply 'Docker Reality 目标站' $'1\n'
        targetReply 'Reality 入口 ID（空输入检测全部，0 返回）' $'entry-fixture\n'
        waitForText 'fixture-target-check-ready' "${CONTROL_LOG}" || exit 33
        assertNoLock
        if [[ "${scenario}" == term ]]; then
            kill -TERM "$(<"${TEST_ROOT}/menu.pid")" || exit 34
            return 0
        fi
        printf '\003' >&3
        ;;
    esac
    targetReply 'Docker Reality 目标站' $'8\n'
    targetReply 'Docker 协议与入口' $'0\n'
    targetReply 'Docker 管理菜单' $'1\n'
    targetReply 'Docker 管理菜单' $'0\n'
}

runGeoDriver() {
    local scenario=$1
    local -A targetPrompts=()
    targetReply 'Docker 管理菜单' $'14\n'
    if [[ "${scenario}" == unsupported ]]; then
        targetReply 'Docker 管理菜单' $'0\n'
        return 0
    fi
    case "${scenario}" in
    flow)
        targetReply 'Docker Xray Geo 数据' $'1\n'
        targetReply 'Docker Xray Geo 数据' $'2\n'
        targetReply 'Geo 发布固定 tag' $'202610070140\n'
        targetReply '确认更新 Geo 数据并在运行时重建 Xray' $'y\n'
        targetReply 'Docker Xray Geo 数据' $'2\n'
        targetReply 'Geo 发布固定 tag' $'\n'
        targetReply '确认更新 Geo 数据并在运行时重建 Xray' $'y\n'
        targetReply 'Docker Xray Geo 数据' $'3\n'
        targetReply '确认启用每日 01:35 的 Xray Geo 更新' $'y\n'
        targetReply 'Docker Xray Geo 数据' $'4\n'
        targetReply 'Docker Xray Geo 数据' $'5\n'
        ;;
    cancel)
        targetReply 'Docker Xray Geo 数据' $'2\n'
        targetReply 'Geo 发布固定 tag' $'0\n'
        targetReply 'Docker Xray Geo 数据' $'2\n'
        targetReply 'Geo 发布固定 tag' $'\n'
        targetReply '确认更新 Geo 数据并在运行时重建 Xray' $'n\n'
        targetReply 'Docker Xray Geo 数据' $'3\n'
        targetReply '确认启用每日 01:35 的 Xray Geo 更新' $'0\n'
        targetReply 'Docker Xray Geo 数据' $'3\n'
        targetReply '确认启用每日 01:35 的 Xray Geo 更新' $'n\n'
        ;;
    version-eof)
        targetReply 'Docker Xray Geo 数据' $'2\n'
        targetReply 'Geo 发布固定 tag' $'\004'
        ;;
    update-eof|failed|int|term)
        targetReply 'Docker Xray Geo 数据' $'2\n'
        targetReply 'Geo 发布固定 tag' $'\n'
        if [[ "${scenario}" == update-eof ]]; then
            targetReply '确认更新 Geo 数据并在运行时重建 Xray' $'\004'
        else
            targetReply '确认更新 Geo 数据并在运行时重建 Xray' $'y\n'
            if [[ "${scenario}" == int || "${scenario}" == term ]]; then
                waitForText 'fixture-geo-update-ready' "${CONTROL_LOG}" || exit 35
                assertNoLock
                if [[ "${scenario}" == term ]]; then
                    kill -TERM "$(<"${TEST_ROOT}/menu.pid")" || exit 36
                    return 0
                fi
                printf '\003' >&3
            fi
        fi
        ;;
    enable-eof)
        targetReply 'Docker Xray Geo 数据' $'3\n'
        targetReply '确认启用每日 01:35 的 Xray Geo 更新' $'\004'
        ;;
    esac
    targetReply 'Docker Xray Geo 数据' $'0\n'
    targetReply 'Docker 管理菜单' $'0\n'
}

runPortAliasDriver() {
    local scenario=$1 field input
    local -A targetPrompts=()
    targetReply 'Docker 管理菜单' $'9\n'
    targetReply 'Docker 协议与入口' $'8\n'
    case "${scenario}" in
    flow)
        targetReply 'Docker 额外入口端口' $'1\n'
        targetReply 'Docker 额外入口端口' $'2\n'
        targetReply '入口 ID（0 返回）' $'entry-fixture\n'
        targetReply '额外端口（0 返回）' $'2053\n'
        targetReply 'Docker 额外入口端口' $'4\n'
        targetReply '入口 ID（0 返回）' $'entry-fixture\n'
        targetReply '默认分享端口（已有额外端口，0 返回）' $'2053\n'
        targetReply 'Docker 额外入口端口' $'5\n'
        targetReply '入口 ID（0 返回）' $'entry-fixture\n'
        targetReply 'Docker 额外入口端口' $'3\n'
        targetReply '入口 ID（0 返回）' $'entry-fixture\n'
        targetReply '额外端口（0 返回）' $'2053\n'
        ;;
    cancel)
        targetReply 'Docker 额外入口端口' $'99\n'
        targetReply 'Docker 额外入口端口' $'2\n'
        targetReply '入口 ID（0 返回）' $'0\n'
        targetReply 'Docker 额外入口端口' $'3\n'
        targetReply '入口 ID（0 返回）' $'entry-fixture\n'
        targetReply '额外端口（0 返回）' $'0\n'
        ;;
    eof|failed|invalid)
        targetReply 'Docker 额外入口端口' $'2\n'
        targetReply '入口 ID（0 返回）' $'entry-fixture\n'
        case "${scenario}" in
        eof) targetReply '额外端口（0 返回）' $'\004' ;;
        invalid) targetReply '额外端口（0 返回）' $'invalid\n' ;;
        failed) targetReply '额外端口（0 返回）' $'2053\n' ;;
        esac
        ;;
    default-cancel)
        targetReply 'Docker 额外入口端口' $'4\n'
        targetReply '入口 ID（0 返回）' $'0\n'
        targetReply 'Docker 额外入口端口' $'4\n'
        targetReply '入口 ID（0 返回）' $'entry-fixture\n'
        targetReply '默认分享端口（已有额外端口，0 返回）' $'0\n'
        targetReply 'Docker 额外入口端口' $'5\n'
        targetReply '入口 ID（0 返回）' $'0\n'
        ;;
    default-eof|default-invalid|default-failed)
        targetReply 'Docker 额外入口端口' $'4\n'
        targetReply '入口 ID（0 返回）' $'entry-fixture\n'
        case "${scenario}" in
        default-eof) targetReply '默认分享端口（已有额外端口，0 返回）' $'\004' ;;
        default-invalid) targetReply '默认分享端口（已有额外端口，0 返回）' $'invalid\n' ;;
        default-failed) targetReply '默认分享端口（已有额外端口，0 返回）' $'2053\n' ;;
        esac
        ;;
    base-eof)
        targetReply 'Docker 额外入口端口' $'5\n'
        targetReply '入口 ID（0 返回）' $'\004'
        ;;
    replace-flow|replace-failed)
        targetReply 'Docker 额外入口端口' $'6\n'
        targetReply '入口 ID（0 返回）' $'entry-fixture\n'
        targetReply '旧额外端口（0 返回）' $'2053\n'
        targetReply '新额外端口（0 返回）' $'2083\n'
        targetReply 'fixture-port-alias-replace-confirm [y/N]' $'y\n'
        targetReply 'Docker 额外入口端口' $'1\n'
        ;;
    replace-cancel|replace-eof)
        for field in listener old new; do
            for input in $'0\n' $'\n'; do
                [[ "${scenario}" != replace-eof ]] || input=$'\004'
                targetReply 'Docker 额外入口端口' $'6\n'
                if [[ "${field}" == listener ]]; then
                    targetReply '入口 ID（0 返回）' "${input}"
                else
                    targetReply '入口 ID（0 返回）' $'entry-fixture\n'
                    if [[ "${field}" == old ]]; then
                        targetReply '旧额外端口（0 返回）' "${input}"
                    else
                        targetReply '旧额外端口（0 返回）' $'2053\n'
                        targetReply '新额外端口（0 返回）' "${input}"
                    fi
                fi
                [[ "${scenario}" != replace-eof ]] || break
            done
        done
        targetReply 'Docker 额外入口端口' $'6\n'
        targetReply '入口 ID（0 返回）' $'entry-fixture\n'
        targetReply '旧额外端口（0 返回）' $'2053\n'
        targetReply '新额外端口（0 返回）' $'2083\n'
        input=$'n\n'
        [[ "${scenario}" != replace-eof ]] || input=$'\004'
        targetReply 'fixture-port-alias-replace-confirm [y/N]' "${input}"
        targetReply 'Docker 额外入口端口' $'1\n'
        ;;
    esac
    targetReply 'Docker 额外入口端口' $'0\n'
    targetReply 'Docker 协议与入口' $'0\n'
    targetReply 'Docker 管理菜单' $'0\n'
}

runCdnDriver() {
    local scenario=$1 choice answer
    local -A targetPrompts=()
    targetReply 'Docker 管理菜单' $'9\n'
    targetReply 'Docker 协议与入口' $'9\n'
    targetReply 'Docker CDN 连接地址' $'1\n'
    case "${scenario}" in
    flow|failed)
        targetReply 'Docker CDN 连接地址' $'2\n'
        targetReply '入口 ID（0 返回）' $'entry24\n'
        targetReply '连接地址（IP 或域名，多个用逗号分隔，0 返回）' $'203.0.113.24,cdn.example.com\n'
        targetReply 'Docker CDN 连接地址' $'3\n'
        targetReply '入口 ID（0 返回）' $'entry25\n'
        ;;
    cancel)
        for answer in $'0\n' $'\n' $'\004'; do
            for choice in 2 3; do
                targetReply 'Docker CDN 连接地址' "${choice}"$'\n'
                targetReply '入口 ID（0 返回）' "${answer}"
            done
            targetReply 'Docker CDN 连接地址' $'2\n'
            targetReply '入口 ID（0 返回）' $'entry24\n'
            targetReply '连接地址（IP 或域名，多个用逗号分隔，0 返回）' "${answer}"
        done
        ;;
    esac
    targetReply 'Docker CDN 连接地址' $'1\n'
    targetReply 'Docker CDN 连接地址' $'0\n'
    targetReply 'Docker 协议与入口' $'0\n'
    targetReply 'Docker 管理菜单' $'0\n'
}

runXhttpDriver() {
    local scenario=$1 choice answer field grpc sse post interval buffered seconds security
    local -A targetPrompts=()
    targetReply 'Docker 管理菜单' $'9\n'
    targetReply 'Docker 协议与入口' $'10\n'
    targetReply 'Docker XHTTP 管理' $'1\n'
    case "${scenario}" in
    flow)
        for choice in 2 3 4 5; do
            targetReply 'Docker XHTTP 管理' "${choice}"$'\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        done
        for answer in custom defaults; do
            targetReply 'Docker XHTTP 管理' $'6\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
            if [[ "${answer}" == custom ]]; then
                targetReply 'XMUX 最大并发（整数或 from-to）[16-32，0 返回]' $'8-16\n'
                targetReply 'XMUX 每连接请求数（0-0 表示零）[600-900，0 返回]' $'0-0\n'
                targetReply 'XMUX 连接复用秒数（0-0 表示零）[1800-3000，0 返回]' $'120-180\n'
            else
                targetReply 'XMUX 最大并发（整数或 from-to）[16-32，0 返回]' $'\n'
                targetReply 'XMUX 每连接请求数（0-0 表示零）[600-900，0 返回]' $'\n'
                targetReply 'XMUX 连接复用秒数（0-0 表示零）[1800-3000，0 返回]' $'\n'
            fi
        done
        targetReply 'Docker XHTTP 管理' $'7\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        for answer in $'64\n' $'128-256\n' $'\n'; do
            targetReply 'Docker XHTTP 管理' $'8\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
            targetReply 'Padding 字节数（1..4096 整数或 from-to）[100-1000，0 返回]' "${answer}"
        done
        targetReply 'Docker XHTTP 管理' $'9\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        for answer in 'true false' 'false true' 'false false' defaults; do
            targetReply 'Docker XHTTP 管理' $'10\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
            if [[ "${answer}" == defaults ]]; then
                grpc='' sse=''
            else
                read -r grpc sse <<<"${answer}"
            fi
            targetReply 'noGRPCHeader（true/false，0 返回）[false]' "${grpc}"$'\n'
            targetReply 'noSSEHeader（true/false，0 返回）[false]' "${sse}"$'\n'
        done
        targetReply 'Docker XHTTP 管理' $'11\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        for answer in custom defaults native-defaults; do
            targetReply 'Docker XHTTP 管理' $'12\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
            case "${answer}" in
            custom) post=16384 interval=5 buffered=16 seconds=1-2 ;;
            defaults) post='' interval='' buffered='' seconds='' ;;
            native-defaults) post=default interval=default buffered=default seconds=0-0 ;;
            esac
            targetReply 'packet-up 单个 POST 最大字节数（default=缺省，0 返回）[1000000]' "${post}"$'\n'
            targetReply 'packet-up POST 最小间隔毫秒（default=缺省，0 返回）[30]' "${interval}"$'\n'
            targetReply 'packet-up 最多缓存 POST 数（default=缺省，0 返回）[30]' "${buffered}"$'\n'
            targetReply 'stream-up 服务端保活秒数（整数或 from-to，0-0=缺省，0 返回）[20-80]' "${seconds}"$'\n'
        done
        targetReply 'Docker XHTTP 管理' $'13\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        targetReply 'Docker XHTTP 管理' $'18\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        targetReply 'XHTTP 请求首部 JSON 对象（0 返回，空值取消）' $'{"x-trace":"edge value","x-route":"v3"}\n'
        targetReply 'Docker XHTTP 管理' $'19\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        ;;
    headers-long)
        targetReply 'Docker XHTTP 管理' $'18\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        targetReply 'XHTTP 请求首部 JSON 对象（0 返回，空值取消）' "${XHTTP_LONG_HEADERS}"$'\n'
        ;;
    cancel)
        targetReply 'Docker XHTTP 管理' $'99\n'
        for answer in $'0\n' $'\n' $'\004' $'--invalid\n'; do
            for choice in 2 6 7 8 9 10 11 23 24; do
                targetReply 'Docker XHTTP 管理' "${choice}"$'\n'
                targetReply 'XHTTP 入口 ID（0 返回）' "${answer}"
            done
        done
        for answer in $'0\n' $'\004'; do
            for field in concurrency requests seconds; do
                targetReply 'Docker XHTTP 管理' $'6\n'
                targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
                if [[ "${field}" == concurrency ]]; then
                    targetReply 'XMUX 最大并发（整数或 from-to）[16-32，0 返回]' "${answer}"
                    continue
                fi
                targetReply 'XMUX 最大并发（整数或 from-to）[16-32，0 返回]' $'8-16\n'
                if [[ "${field}" == requests ]]; then
                    targetReply 'XMUX 每连接请求数（0-0 表示零）[600-900，0 返回]' "${answer}"
                    continue
                fi
                targetReply 'XMUX 每连接请求数（0-0 表示零）[600-900，0 返回]' $'50-100\n'
                targetReply 'XMUX 连接复用秒数（0-0 表示零）[1800-3000，0 返回]' "${answer}"
            done
            targetReply 'Docker XHTTP 管理' $'8\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
            targetReply 'Padding 字节数（1..4096 整数或 from-to）[100-1000，0 返回]' "${answer}"
            for field in grpc sse; do
                targetReply 'Docker XHTTP 管理' $'10\n'
                targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
                if [[ "${field}" == grpc ]]; then
                    targetReply 'noGRPCHeader（true/false，0 返回）[false]' "${answer}"
                    continue
                fi
                targetReply 'noGRPCHeader（true/false，0 返回）[false]' $'true\n'
                targetReply 'noSSEHeader（true/false，0 返回）[false]' "${answer}"
            done
        done
        for choice in 12 13; do
            targetReply 'Docker XHTTP 管理' "${choice}"$'\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'0\n'
        done
        targetReply 'Docker XHTTP 管理' $'12\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        targetReply 'packet-up 单个 POST 最大字节数（default=缺省，0 返回）[1000000]' $'16384\n'
        targetReply 'packet-up POST 最小间隔毫秒（default=缺省，0 返回）[30]' $'5\n'
        targetReply 'packet-up 最多缓存 POST 数（default=缺省，0 返回）[30]' $'16\n'
        targetReply 'stream-up 服务端保活秒数（整数或 from-to，0-0=缺省，0 返回）[20-80]' $'0\n'
        targetReply 'Docker XHTTP 管理' $'18\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'0\n'
        targetReply 'Docker XHTTP 管理' $'19\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'\004'
        for answer in $'0\n' $'\n' $'\004'; do
            targetReply 'Docker XHTTP 管理' $'18\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
            targetReply 'XHTTP 请求首部 JSON 对象（0 返回，空值取消）' "${answer}"
        done
        ;;
    failed|invalid)
        if [[ "${scenario}" == failed ]]; then
            targetReply 'Docker XHTTP 管理' $'2\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        fi
        targetReply 'Docker XHTTP 管理' $'6\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        if [[ "${scenario}" == invalid ]]; then
            targetReply 'XMUX 最大并发（整数或 from-to）[16-32，0 返回]' $'not-range\n'
        else
            targetReply 'XMUX 最大并发（整数或 from-to）[16-32，0 返回]' $'8-16\n'
        fi
        targetReply 'XMUX 每连接请求数（0-0 表示零）[600-900，0 返回]' $'50-100\n'
        targetReply 'XMUX 连接复用秒数（0-0 表示零）[1800-3000，0 返回]' $'120-180\n'
        if [[ "${scenario}" == failed ]]; then
            targetReply 'Docker XHTTP 管理' $'7\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        fi
        targetReply 'Docker XHTTP 管理' $'8\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        if [[ "${scenario}" == invalid ]]; then
            targetReply 'Padding 字节数（1..4096 整数或 from-to）[100-1000，0 返回]' $'not-range\n'
        else
            targetReply 'Padding 字节数（1..4096 整数或 from-to）[100-1000，0 返回]' $'128-256\n'
            targetReply 'Docker XHTTP 管理' $'9\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        fi
        if [[ "${scenario}" == invalid ]]; then
            for field in grpc sse; do
                targetReply 'Docker XHTTP 管理' $'10\n'
                targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
                grpc=false sse=false
                if [[ "${field}" == grpc ]]; then
                    grpc=not-bool
                else
                    sse=not-bool
                fi
                targetReply 'noGRPCHeader（true/false，0 返回）[false]' "${grpc}"$'\n'
                targetReply 'noSSEHeader（true/false，0 返回）[false]' "${sse}"$'\n'
            done
        else
            targetReply 'Docker XHTTP 管理' $'10\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
            targetReply 'noGRPCHeader（true/false，0 返回）[false]' $'true\n'
            targetReply 'noSSEHeader（true/false，0 返回）[false]' $'false\n'
            targetReply 'Docker XHTTP 管理' $'11\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        fi
        targetReply 'Docker XHTTP 管理' $'12\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        if [[ "${scenario}" == invalid ]]; then post=not-number; else post=16384; fi
        targetReply 'packet-up 单个 POST 最大字节数（default=缺省，0 返回）[1000000]' "${post}"$'\n'
        targetReply 'packet-up POST 最小间隔毫秒（default=缺省，0 返回）[30]' $'5\n'
        targetReply 'packet-up 最多缓存 POST 数（default=缺省，0 返回）[30]' $'16\n'
        targetReply 'stream-up 服务端保活秒数（整数或 from-to，0-0=缺省，0 返回）[20-80]' $'1-2\n'
        if [[ "${scenario}" == failed ]]; then
            targetReply 'Docker XHTTP 管理' $'13\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
            targetReply 'Docker XHTTP 管理' $'18\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
            targetReply 'XHTTP 请求首部 JSON 对象（0 返回，空值取消）' $'{"x-trace":"edge value"}\n'
            targetReply 'Docker XHTTP 管理' $'19\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        else
            targetReply 'Docker XHTTP 管理' $'18\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
            targetReply 'XHTTP 请求首部 JSON 对象（0 返回，空值取消）' $'not-json\n'
        fi
        ;;
    current)
        targetReply 'Docker XHTTP 管理' $'23\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-missing\n'
        targetReply 'Docker XHTTP 管理' $'6\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        targetReply 'XMUX 最大并发（整数或 from-to）[4-8，0 返回]' $'\n'
        targetReply 'XMUX 每连接请求数（0-0 表示零）[0-0，0 返回]' $'\n'
        targetReply 'XMUX 连接复用秒数（0-0 表示零）[0-0，0 返回]' $'\n'
        targetReply 'Docker XHTTP 管理' $'8\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        targetReply 'Padding 字节数（1..4096 整数或 from-to）[17-19，0 返回]' $'\n'
        targetReply 'Docker XHTTP 管理' $'10\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        targetReply 'noGRPCHeader（true/false，0 返回）[false]' $'\n'
        targetReply 'noSSEHeader（true/false，0 返回）[true]' $'\n'
        targetReply 'Docker XHTTP 管理' $'12\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        targetReply 'packet-up 单个 POST 最大字节数（default=缺省，0 返回）[8192]' $'\n'
        targetReply 'packet-up POST 最小间隔毫秒（default=缺省，0 返回）[5]' $'\n'
        targetReply 'packet-up 最多缓存 POST 数（default=缺省，0 返回）[7]' $'\n'
        targetReply 'stream-up 服务端保活秒数（整数或 from-to，0-0=缺省，0 返回）[10-15]' $'\n'
        targetReply 'Docker XHTTP 管理' $'14\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        targetReply 'XHTTP 模式（auto/packet-up/stream-up，0 返回）[stream-up]' $'\n'
        targetReply 'Docker XHTTP 管理' $'15\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        targetReply 'XHTTP 路径（以 / 开头，0 返回）[/current/path]' $'\n'
        targetReply 'XHTTP Host（非空域名，0 返回）[current.example.net]' $'\n'
        targetReply 'Docker XHTTP 管理' $'16\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        targetReply 'Padding 字节数（1..4096 整数或 from-to）[17-19，0 返回]' $'\n'
        targetReply 'packet-up 单个 POST 最大字节数（default=缺省，0 返回）[8192]' $'\n'
        targetReply 'packet-up POST 最小间隔毫秒（default=缺省，0 返回）[5]' $'\n'
        targetReply 'packet-up 最多缓存 POST 数（default=缺省，0 返回）[7]' $'\n'
        targetReply 'stream-up 服务端保活秒数（整数或 from-to，0-0=缺省，0 返回）[10-15]' $'\n'
        targetReply 'noGRPCHeader（true/false，0 返回）[false]' $'\n'
        targetReply 'noSSEHeader（true/false，0 返回）[true]' $'\n'
        ;;
    status-invalid|status-incomplete)
        targetReply 'Docker XHTTP 管理' $'23\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        ;;
    status-failed)
        for choice in 2 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24; do
            targetReply 'Docker XHTTP 管理' "${choice}"$'\n'
        done
        ;;
    esac
    # 新入口复用同一会话，取消只取首尾边界，不展开七字段组合矩阵。
    case "${scenario}" in
    flow|failed|invalid)
        if [[ "${scenario}" == flow ]]; then
            for answer in packet-up stream-up auto; do
                targetReply 'Docker XHTTP 管理' $'14\n'
                targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
                [[ "${answer}" != auto ]] || answer=
                targetReply 'XHTTP 模式（auto/packet-up/stream-up，0 返回）[auto]' "${answer}"$'\n'
            done
        else
            targetReply 'Docker XHTTP 管理' $'14\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
            answer=packet-up
            [[ "${scenario}" != invalid ]] || answer=stream-one
            targetReply 'XHTTP 模式（auto/packet-up/stream-up，0 返回）[auto]' "${answer}"$'\n'
        fi
        targetReply 'Docker XHTTP 管理' $'15\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        answer=/custom/path
        [[ "${scenario}" != invalid ]] || answer=no-leading-slash
        targetReply 'XHTTP 路径（以 / 开头，0 返回）' "${answer}"$'\n'
        targetReply 'XHTTP Host（非空域名，0 返回）' $'edge.example.net\n'
        targetReply 'Docker XHTTP 管理' $'16\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        answer=64-128
        [[ "${scenario}" != invalid ]] || answer=not-range
        targetReply 'Padding 字节数（1..4096 整数或 from-to）[100-1000，0 返回]' "${answer}"$'\n'
        targetReply 'packet-up 单个 POST 最大字节数（default=缺省，0 返回）[1000000]' $'16384\n'
        targetReply 'packet-up POST 最小间隔毫秒（default=缺省，0 返回）[30]' $'5\n'
        targetReply 'packet-up 最多缓存 POST 数（default=缺省，0 返回）[30]' $'16\n'
        targetReply 'stream-up 服务端保活秒数（整数或 from-to，0-0=缺省，0 返回）[20-80]' $'1-2\n'
        targetReply 'noGRPCHeader（true/false，0 返回）[false]' $'false\n'
        targetReply 'noSSEHeader（true/false，0 返回）[false]' $'true\n'
        if [[ "${scenario}" != invalid ]]; then
            targetReply 'Docker XHTTP 管理' $'17\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        fi
        ;;
    cancel)
        for answer in $'0\n' $'\004'; do
            targetReply 'Docker XHTTP 管理' $'14\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
            targetReply 'XHTTP 模式（auto/packet-up/stream-up，0 返回）[auto]' "${answer}"
        done
        targetReply 'Docker XHTTP 管理' $'15\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        targetReply 'XHTTP 路径（以 / 开头，0 返回）' $'0\n'
        targetReply 'Docker XHTTP 管理' $'15\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        targetReply 'XHTTP 路径（以 / 开头，0 返回）' $'/custom/path\n'
        targetReply 'XHTTP Host（非空域名，0 返回）' $'\004'
        targetReply 'Docker XHTTP 管理' $'15\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        targetReply 'XHTTP 路径（以 / 开头，0 返回）' $'/custom/path\n'
        targetReply 'XHTTP Host（非空域名，0 返回）' $'0\n'
        targetReply 'Docker XHTTP 管理' $'16\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        targetReply 'Padding 字节数（1..4096 整数或 from-to）[100-1000，0 返回]' $'0\n'
        targetReply 'Docker XHTTP 管理' $'16\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        targetReply 'Padding 字节数（1..4096 整数或 from-to）[100-1000，0 返回]' $'\n'
        targetReply 'packet-up 单个 POST 最大字节数（default=缺省，0 返回）[1000000]' $'\n'
        targetReply 'packet-up POST 最小间隔毫秒（default=缺省，0 返回）[30]' $'\n'
        targetReply 'packet-up 最多缓存 POST 数（default=缺省，0 返回）[30]' $'\n'
        targetReply 'stream-up 服务端保活秒数（整数或 from-to，0-0=缺省，0 返回）[20-80]' $'\n'
        targetReply 'noGRPCHeader（true/false，0 返回）[false]' $'\n'
        targetReply 'noSSEHeader（true/false，0 返回）[false]' $'\004'
        targetReply 'Docker XHTTP 管理' $'17\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'0\n'
        ;;
    esac
    case "${scenario}" in
    flow|failed|invalid)
        targetReply 'Docker XHTTP 管理' $'20\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        answer=9443
        [[ "${scenario}" != invalid ]] || answer=not-port
        targetReply '下行端口（已登记的额外非默认分享端口，0 返回，空值取消）' "${answer}"$'\n'
        if [[ "${scenario}" != invalid ]]; then
            targetReply 'Docker XHTTP 管理' $'21\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        fi
        ;;
    cancel)
        targetReply 'Docker XHTTP 管理' $'20\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'0\n'
        targetReply 'Docker XHTTP 管理' $'21\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'\004'
        for answer in $'0\n' $'\n' $'\004'; do
            targetReply 'Docker XHTTP 管理' $'20\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
            targetReply '下行端口（已登记的额外非默认分享端口，0 返回，空值取消）' "${answer}"
        done
        ;;
    esac
    case "${scenario}" in
    flow|failed|invalid)
        for security in tls reality; do
            [[ "${scenario}" == flow || "${security}" == tls ]] || continue
            targetReply 'Docker XHTTP 管理' $'22\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
            if [[ "${security}" == tls ]]; then
                targetReply '下行地址（0 返回，空值取消）' $'download.example.net\n'
                answer=
                [[ "${scenario}" != invalid ]] || answer=not-port
                targetReply '下行端口 [443，0 返回]' "${answer}"$'\n'
                targetReply '下行安全（tls/reality，0 返回）[tls]' $'\n'
                targetReply '下行 Server Name（0 返回，空值取消）' $'tls.example.net\n'
                targetReply '下行 Host（0 返回，空值取消）' $'relay.example.net\n'
                targetReply '下行路径（以 / 开头，0 返回，空值取消）' $'/down/path\n'
                targetReply '下行模式（auto/stream-one/packet-up/stream-up，0 返回）[auto]' $'\n'
                answer=
                [[ "${scenario}" != flow ]] || answer=h3
                targetReply '下行 ALPN（h2/h3，0 返回）[h2]' "${answer}"$'\n'
            else
                targetReply '下行地址（0 返回，空值取消）' $'192.0.2.10\n'
                targetReply '下行端口 [443，0 返回]' $'8443\n'
                targetReply '下行安全（tls/reality，0 返回）[tls]' $'reality\n'
                targetReply '下行 Server Name（0 返回，空值取消）' $'reality.example.net\n'
                targetReply '下行 Host（0 返回，空值取消）' $'reality-relay.example.net\n'
                targetReply '下行路径（以 / 开头，0 返回，空值取消）' $'/reality/down\n'
                targetReply '下行模式（auto/stream-one/packet-up/stream-up，0 返回）[auto]' $'stream-one\n'
                targetReply '下行 Reality public_key（0 返回，空值取消）' $'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n'
                targetReply '下行 Reality short_id（0 返回，空值取消）' $'0123456789abcdef\n'
            fi
        done
        ;;
    cancel)
        targetReply 'Docker XHTTP 管理' $'22\n'
        targetReply 'XHTTP 入口 ID（0 返回）' $'0\n'
        for answer in $'\n' $'\003'; do
            targetReply 'Docker XHTTP 管理' $'22\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
            targetReply '下行地址（0 返回，空值取消）' "${answer}"
        done
        for security in tls reality; do
            targetReply 'Docker XHTTP 管理' $'22\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
            targetReply '下行地址（0 返回，空值取消）' $'download.example.net\n'
            targetReply '下行端口 [443，0 返回]' $'\n'
            targetReply '下行安全（tls/reality，0 返回）[tls]' "${security}"$'\n'
            targetReply '下行 Server Name（0 返回，空值取消）' $'tls.example.net\n'
            targetReply '下行 Host（0 返回，空值取消）' $'relay.example.net\n'
            targetReply '下行路径（以 / 开头，0 返回，空值取消）' $'/down/path\n'
            targetReply '下行模式（auto/stream-one/packet-up/stream-up，0 返回）[auto]' $'\n'
            if [[ "${security}" == tls ]]; then
                targetReply '下行 ALPN（h2/h3，0 返回）[h2]' $'\004'
            else
                targetReply '下行 Reality public_key（0 返回，空值取消）' $'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n'
                targetReply '下行 Reality short_id（0 返回，空值取消）' $'0\n'
            fi
        done
        ;;
    esac
    if [[ "${scenario}" == flow || "${scenario}" == failed || "${scenario}" == current ]]; then
        for choice in 23 24; do
            targetReply 'Docker XHTTP 管理' "${choice}"$'\n'
            targetReply 'XHTTP 入口 ID（0 返回）' $'entry-xhttp\n'
        done
    fi
    targetReply 'Docker XHTTP 管理' $'1\n'
    targetReply 'Docker XHTTP 管理' $'0\n'
    targetReply 'Docker 协议与入口' $'0\n'
    targetReply 'Docker 管理菜单' $'0\n'
}

runUdpManagementDriver() {
    local kind=$1 scenario=$2 menu listener choice answer
    local -A targetPrompts=()
    if [[ "${kind}" == hy2 ]]; then
        menu='Docker Hysteria2 管理' listener='Hysteria2 入口 ID（0 返回）' choice=12
    else
        menu='Docker TUIC 管理' listener='TUIC 入口 ID（0 返回）' choice=13
    fi
    targetReply 'Docker 管理菜单' $'9\n'
    targetReply 'Docker 协议与入口' "${choice}"$'\n'
    targetReply "${menu}" $'1\n'
    if [[ "${scenario}" == cancel ]]; then
        targetReply "${menu}" $'2\n'
        targetReply "${listener}" $'0\n'
        if [[ "${kind}" == hy2 ]]; then
            targetReply "${menu}" $'3\n'
            targetReply "${listener}" $'entry-hy2\n'
            targetReply '服务端上行带宽 Mbps（服务端→客户端）[100]' $'\004'
            for choice in 4 5 6 8 9; do
                targetReply "${menu}" "${choice}"$'\n'
                targetReply "${listener}" $'0\n'
            done
            for answer in $'0\n' $'\004'; do
                targetReply "${menu}" $'7\n'
                targetReply "${listener}" $'entry-hy2\n'
                targetReply '伪装 HTTPS 地址（0 返回）' "${answer}"
            done
        else
            for answer in $'n\n' $'\004'; do
                targetReply "${menu}" $'6\n'
                targetReply "${listener}" $'entry-tuic\n'
                targetReply '确认启用 TUIC 0-RTT？[y/N]' "${answer}"
            done
        fi
    elif [[ "${kind}" == hy2 ]]; then
        targetReply "${menu}" $'2\n'
        targetReply "${listener}" $'entry-hy2\n'
        targetReply "${menu}" $'3\n'
        targetReply "${listener}" $'entry-hy2\n'
        targetReply '服务端上行带宽 Mbps（服务端→客户端）[100]' $'\n'
        targetReply '服务端下行带宽 Mbps（客户端→服务端）[50]' $'\n'
        for choice in 4 5 6 7 8 9; do
            targetReply "${menu}" "${choice}"$'\n'
            targetReply "${listener}" $'entry-hy2\n'
            [[ "${choice}" != 7 ]] ||
                targetReply '伪装 HTTPS 地址（0 返回）' $'https://www.example.com/path-1\n'
        done
    else
        for choice in 2 3 4 5 6 7 8; do
            targetReply "${menu}" "${choice}"$'\n'
            targetReply "${listener}" $'entry-tuic\n'
            if [[ "${choice}" == 5 ]]; then
                targetReply '认证超时 auth_timeout（正整数+ms/s/m/h）[3s]' $'\n'
                targetReply '心跳间隔 heartbeat（正整数+ms/s/m/h）[10s]' $'\n'
            elif [[ "${choice}" == 6 ]]; then
                targetReply '确认启用 TUIC 0-RTT？[y/N]' $'y\n'
            fi
        done
    fi
    targetReply "${menu}" $'1\n'
    targetReply "${menu}" $'0\n'
    targetReply 'Docker 协议与入口' $'0\n'
    targetReply 'Docker 管理菜单' $'0\n'
}

runMaintenanceDriver() {
    local scenario=$1 choice address answer=n action field previous prompt value
    local scope=ws statusChoice=1 unbanChoice=2 disableChoice=3 enableChoice=5 settingsChoice=6
    local jail=padm-nginx addressPrompt='待解封 IPv4/IPv6（0 返回）: '
    local disablePrompt='确认停用受管站点扫描防护？[y/N]: '
    local enablePrompt='确认启用受管 WS 站点扫描防护？[y/N]: '
    local settingsPrompt='确认更新受管 WS 站点扫描参数？[y/N]: '
    local -a unbanAddresses=(203.0.113.9 2001:db8::9)
    if [[ "${scenario}" == fail2ban-control-* ]]; then
        scenario="fail2ban-${scenario#fail2ban-control-}"
        scope=control statusChoice=7 unbanChoice=8 disableChoice=9 enableChoice=10 settingsChoice=11
        jail=padm-control addressPrompt='待解封控制面 IPv4（0 返回）: '
        disablePrompt='确认停用受管控制面防护？[y/N]: '
        enablePrompt='确认启用受管控制面防护？[y/N]: '
        settingsPrompt='确认更新受管控制面防护参数？[y/N]: '
        unbanAddresses=(203.0.113.9)
    fi
    local -A targetPrompts=()
    targetReply 'Docker 管理菜单' $'18\n'
    case "${scenario}" in
    flow|failed)
        [[ "${scenario}" != failed ]] || answer=y
        targetReply 'Docker 服务维护' $'1\n'
        targetReply 'Docker 服务维护' $'99\n'
        for choice in 2 3 4; do
            targetReply 'Docker 服务维护' "${choice}"$'\n'
            case "${choice}" in
            2) targetReply '确认更新镜像与控制脚本？[y/N]' "${answer}"$'\n' ;;
            4) targetReply '确认停止服务并卸载控制命令（保留状态、配置和数据）？[y/N]' "${answer}"$'\n' ;;
            esac
        done
        ;;
    cancel)
        targetReply 'Docker 服务维护' $'2\n'
        targetReply '确认更新镜像与控制脚本？[y/N]' $'0\n'
        targetReply 'Docker 服务维护' $'2\n'
        targetReply '确认更新镜像与控制脚本？[y/N]' $'\n'
        targetReply 'Docker 服务维护' $'4\n'
        targetReply '确认停止服务并卸载控制命令（保留状态、配置和数据）？[y/N]' $'n\n'
        ;;
    restore-flow|restore-failed|restore-cancel|restore-eof)
        targetReply 'Docker 服务维护' $'8\n'
        prompt='待预览恢复的灾备归档绝对路径（0 返回）'
        case "${scenario}" in
        restore-cancel)
            targetReply "${prompt}" $'0\n'
            targetReply 'Docker 服务维护' $'8\n'
            targetReply "${prompt}" $'\n'
            ;;
        restore-eof) targetReply "${prompt}" $'\004' ;;
        *)
            targetReply "${prompt}" $'/root/private recovery.tar\n'
            targetReply '恢复发布资产（1 默认发布，2 自备匹配资产，0 返回）' $'\n'
            ;;
        esac
        ;;
    restore-apply|restore-apply-failed|restore-apply-cancel|restore-apply-eof|restore-apply-path-eof)
        targetReply 'Docker 服务维护' $'9\n'
        prompt='待应用恢复的灾备归档绝对路径（0 返回）'
        if [[ "${scenario}" == restore-apply-path-eof ]]; then
            targetReply "${prompt}" $'\004'
        else
            targetReply "${prompt}" $'/root/private recovery.tar\n'
            targetReply '恢复发布资产（1 默认发布，2 自备匹配资产，0 返回）' $'1\n'
            case "${scenario}" in
            restore-apply-cancel) answer=n ;;
            restore-apply-eof) answer=$'\004' ;;
            *) answer=y ;;
            esac
            targetReply '确认向空目标应用灾备归档？[y/N]' "${answer}"$'\n'
        fi
        ;;
    restore-source-cancel)
        for choice in 8 9; do
            prompt='待预览恢复的灾备归档绝对路径（0 返回）'
            [[ "${choice}" != 9 ]] || prompt='待应用恢复的灾备归档绝对路径（0 返回）'
            for value in $'0\n' $'99\n' $'\004'; do
                targetReply 'Docker 服务维护' "${choice}"$'\n'
                targetReply "${prompt}" $'/root/private recovery.tar\n'
                targetReply '恢复发布资产（1 默认发布，2 自备匹配资产，0 返回）' "${value}"
            done
        done
        ;;
    restore-assets|restore-assets-failed|restore-assets-apply|restore-assets-apply-failed|restore-assets-cancel|restore-assets-apply-cancel|restore-assets-reset)
        local -a releasePrompts=('匹配归档的 manifest 绝对路径（0 返回）'
            '匹配归档的 Sigstore bundle 绝对路径（0 返回）' '匹配归档的 control-bundle 绝对路径（0 返回）')
        local -a releasePaths=('/root/historical release/release-manifest.json'
            '/root/historical release/release-manifest.sigstore.json' '/root/historical release/control-bundle.tar.gz')
        if [[ "${scenario}" == restore-assets-cancel ]]; then
            for choice in 8 9; do
                prompt='待预览恢复的灾备归档绝对路径（0 返回）'
                [[ "${choice}" != 9 ]] || prompt='待应用恢复的灾备归档绝对路径（0 返回）'
                for ((field = 0; field < ${#releasePrompts[@]}; field++)); do
                    for answer in $'0\n' $'\n' $'\004'; do
                        targetReply 'Docker 服务维护' "${choice}"$'\n'
                        targetReply "${prompt}" $'/root/private recovery.tar\n'
                        targetReply '恢复发布资产（1 默认发布，2 自备匹配资产，0 返回）' $'2\n'
                        for ((previous = 0; previous < field; previous++)); do
                            targetReply "${releasePrompts[previous]}" "${releasePaths[previous]}"$'\n'
                        done
                        targetReply "${releasePrompts[field]}" "${answer}"
                    done
                done
            done
        else
            choice=8
            prompt='待预览恢复的灾备归档绝对路径（0 返回）'
            if [[ "${scenario}" == restore-assets-apply* ]]; then
                choice=9
                prompt='待应用恢复的灾备归档绝对路径（0 返回）'
            fi
            targetReply 'Docker 服务维护' "${choice}"$'\n'
            targetReply "${prompt}" $'/root/private recovery.tar\n'
            targetReply '恢复发布资产（1 默认发布，2 自备匹配资产，0 返回）' $'2\n'
            for ((field = 0; field < ${#releasePrompts[@]}; field++)); do
                targetReply "${releasePrompts[field]}" "${releasePaths[field]}"$'\n'
            done
            if [[ "${choice}" == 9 ]]; then
                answer=y
                [[ "${scenario}" != restore-assets-apply-cancel ]] || answer=n
                targetReply '确认向空目标应用灾备归档？[y/N]' "${answer}"$'\n'
            fi
            if [[ "${scenario}" == restore-assets-reset ]]; then
                targetReply 'Docker 服务维护' $'8\n'
                targetReply "${prompt}" $'/root/private recovery.tar\n'
                targetReply '恢复发布资产（1 默认发布，2 自备匹配资产，0 返回）' $'1\n'
            fi
        fi
        ;;
    restore-recover|restore-recover-failed)
        targetReply 'Docker 服务维护' $'10\n'
        ;;
    restore-controller|restore-controller-apply|restore-controller-assets|restore-controller-cancel|restore-controller-eof|restore-controller-reset|restore-controller-failed)
        choice=11
        prompt='待预览恢复的灾备归档绝对路径（0 返回）'
        if [[ "${scenario}" == restore-controller-apply || "${scenario}" == restore-controller-cancel ||
            "${scenario}" == restore-controller-eof ]]; then
            choice=12
            prompt='待应用恢复的灾备归档绝对路径（0 返回）'
        fi
        targetReply 'Docker 服务维护' "${choice}"$'\n'
        targetReply "${prompt}" $'/root/private recovery.tar\n'
        answer=1
        [[ "${scenario}" != restore-controller-assets ]] || answer=2
        targetReply '恢复发布资产（1 默认发布，2 自备匹配资产，0 返回）' "${answer}"$'\n'
        if [[ "${answer}" == 2 ]]; then
            targetReply '匹配归档的 manifest 绝对路径（0 返回）' $'/root/historical release/release-manifest.json\n'
            targetReply '匹配归档的 Sigstore bundle 绝对路径（0 返回）' $'/root/historical release/release-manifest.sigstore.json\n'
            targetReply '匹配归档的 control-bundle 绝对路径（0 返回）' $'/root/historical release/control-bundle.tar.gz\n'
        fi
        if [[ "${choice}" == 12 ]]; then
            answer=y
            [[ "${scenario}" != restore-controller-cancel ]] || answer=n
            [[ "${scenario}" != restore-controller-eof ]] || answer=$'\004'
            targetReply '确认旧主控已停机隔离，并以新身份恢复到空目标？[y/N]' "${answer}"$'\n'
        fi
        if [[ "${scenario}" == restore-controller-reset ]]; then
            targetReply 'Docker 服务维护' $'8\n'
            targetReply "${prompt}" $'/root/private recovery.tar\n'
            targetReply '恢复发布资产（1 默认发布，2 自备匹配资产，0 返回）' $'1\n'
        fi
        ;;
    backup-flow|backup-failed|backup-cancel|backup-eof)
        for choice in 6 7; do
            if [[ "${choice}" == 6 ]]; then
                prompt='新灾备归档绝对路径（不覆盖已有文件，0 返回）'
            else
                prompt='待校验灾备归档绝对路径（0 返回）'
            fi
            if [[ "${scenario}" == backup-cancel ]]; then
                for value in 0 ''; do
                    targetReply 'Docker 服务维护' "${choice}"$'\n'
                    targetReply "${prompt}" "${value}"$'\n'
                done
            else
                targetReply 'Docker 服务维护' "${choice}"$'\n'
                if [[ "${scenario}" == backup-eof ]]; then
                    targetReply "${prompt}" $'\004'
                else
                    targetReply "${prompt}" $'/root/private recovery.tar\n'
                fi
            fi
        done
        ;;
    update|update-eof)
        targetReply 'Docker 服务维护' $'2\n'
        if [[ "${scenario}" == update ]]; then
            targetReply '确认更新镜像与控制脚本？[y/N]' $'y\n'
            return 0
        fi
        targetReply '确认更新镜像与控制脚本？[y/N]' $'\004'
        ;;
    rollback)
        targetReply 'Docker 服务维护' $'3\n'
        return 0
        ;;
    uninstall|uninstall-eof)
        targetReply 'Docker 服务维护' $'4\n'
        if [[ "${scenario}" == uninstall ]]; then
            targetReply '确认停止服务并卸载控制命令（保留状态、配置和数据）？[y/N]' $'y\n'
            return 0
        fi
        targetReply '确认停止服务并卸载控制命令（保留状态、配置和数据）？[y/N]' $'\004'
        ;;
    fail2ban-*)
        targetReply 'Docker 服务维护' $'5\n'
        case "${scenario}" in
        fail2ban-ssh-preflight|fail2ban-ssh-preflight-failed)
            targetReply 'Docker Fail2ban 维护' $'12\n'
            ;;
        fail2ban-ssh-source|fail2ban-ssh-source-failed|fail2ban-ssh-source-cancel)
            targetReply 'Docker Fail2ban 维护' $'13\n'
            targetReply '宿主 SSH 本机 IPv4/IPv6（0 返回）' $'198.51.100.10\n'
            targetReply '宿主 SSH 端口（0 返回）' $'2222\n'
            if [[ "${scenario}" == fail2ban-ssh-source-cancel ]]; then
                targetReply '外部 SSH 客户端 IPv4/IPv6（0 返回）' $'0\n'
            else
                targetReply '外部 SSH 客户端 IPv4/IPv6（0 返回）' $'203.0.113.9\n'
            fi
            ;;
        fail2ban-ssh-unit|fail2ban-ssh-unit-failed|fail2ban-ssh-unit-cancel-*)
            targetReply 'Docker Fail2ban 维护' $'14\n'
            for field in unit target port source; do
                case "${field}" in
                unit) prompt='宿主 SSH systemd service（0 返回）'; value=sshd.service ;;
                target) prompt='宿主 SSH 本机 IPv4/IPv6（0 返回）'; value=198.51.100.10 ;;
                port) prompt='宿主 SSH 端口（0 返回）'; value=2222 ;;
                source) prompt='外部 SSH 客户端 IPv4/IPv6（0 返回）'; value=203.0.113.9 ;;
                esac
                if [[ "${scenario}" == "fail2ban-ssh-unit-cancel-${field}" ]]; then
                    targetReply "${prompt}" $'0\n'
                    break
                fi
                targetReply "${prompt}" "${value}"$'\n'
            done
            ;;
        fail2ban-flow)
            targetReply 'Docker Fail2ban 维护' "${statusChoice}"$'\n'
            for address in "${unbanAddresses[@]}"; do
                targetReply 'Docker Fail2ban 维护' "${unbanChoice}"$'\n'
                targetReply "${addressPrompt}" "${address}"$'\n'
                targetReply "确认从 ${jail} 解封 ${address}？[y/N]: " $'y\n'
            done
            targetReply 'Docker Fail2ban 维护' $'99\n'
            ;;
        fail2ban-cancel)
            for answer in $'0\n' $'\n' $'\004'; do
                targetReply 'Docker Fail2ban 维护' "${unbanChoice}"$'\n'
                targetReply "${addressPrompt}" "${answer}"
            done
            for answer in $'n\n' $'\n' $'0\n' $'\004'; do
                targetReply 'Docker Fail2ban 维护' "${unbanChoice}"$'\n'
                targetReply "${addressPrompt}" $'203.0.113.9\n'
                targetReply "确认从 ${jail} 解封 203.0.113.9？[y/N]: " "${answer}"
            done
            for answer in $'n\n' $'\n' $'0\n' $'\004'; do
                targetReply 'Docker Fail2ban 维护' "${disableChoice}"$'\n'
                targetReply "${disablePrompt}" "${answer}"
            done
            ;;
        fail2ban-disable*)
            targetReply 'Docker Fail2ban 维护' "${disableChoice}"$'\n'
            targetReply "${disablePrompt}" $'y\n'
            if [[ "${scenario}" == fail2ban-disable-int || "${scenario}" == fail2ban-disable-term ]]; then
                waitForText 'fixture-fail2ban-ready' "${CONTROL_LOG}" || exit 35
                assertNoLock
                if [[ "${scenario}" == fail2ban-disable-term ]]; then
                    kill -TERM "$(<"${TEST_ROOT}/menu.pid")" || exit 36
                    return 0
                fi
                printf '\003' >&3
            fi
            ;;
        fail2ban-verify)
            for address in 203.0.113.9 2001:db8::9; do
                targetReply 'Docker Fail2ban 维护' $'4\n'
                targetReply 'WS 入口 ID（0 返回）: ' $'entry-fixture\n'
                targetReply '外部客户端 IPv4/IPv6（0 返回）: ' "${address}"$'\n'
            done
            ;;
        fail2ban-verify-cancel)
            for answer in $'0\n' $'\n' $'\004'; do
                targetReply 'Docker Fail2ban 维护' $'4\n'
                targetReply 'WS 入口 ID（0 返回）: ' "${answer}"
            done
            for answer in $'0\n' $'\n' $'\004'; do
                targetReply 'Docker Fail2ban 维护' $'4\n'
                targetReply 'WS 入口 ID（0 返回）: ' $'entry-fixture\n'
                targetReply '外部客户端 IPv4/IPv6（0 返回）: ' "${answer}"
            done
            ;;
        fail2ban-verify-list-failed)
            targetReply 'Docker Fail2ban 维护' $'4\n'
            ;;
        fail2ban-verify-*)
            targetReply 'Docker Fail2ban 维护' $'4\n'
            targetReply 'WS 入口 ID（0 返回）: ' $'entry-fixture\n'
            address=203.0.113.9
            [[ "${scenario}" != fail2ban-verify-invalid ]] || address=not-an-ip
            targetReply '外部客户端 IPv4/IPv6（0 返回）: ' "${address}"$'\n'
            if [[ "${scenario}" == fail2ban-verify-int || "${scenario}" == fail2ban-verify-term ]]; then
                waitForText 'fixture-fail2ban-ready' "${CONTROL_LOG}" || exit 35
                assertNoLock
                if [[ "${scenario}" == fail2ban-verify-term ]]; then
                    kill -TERM "$(<"${TEST_ROOT}/menu.pid")" || exit 36
                    return 0
                fi
                printf '\003' >&3
            fi
            ;;
        fail2ban-port-cancel)
            for field in listener port; do
                for answer in $'0\n' $'\n' $'\004'; do
                    targetReply 'Docker Fail2ban 维护' $'20\n'
                    [[ "${field}" != port ]] ||
                        targetReply '受保护 WS 入口 ID（0 返回）' $'entry-fixture\n'
                    if [[ "${field}" == listener ]]; then
                        targetReply '受保护 WS 入口 ID（0 返回）' "${answer}"
                    else
                        targetReply '新 WS 公开端口（0 返回）' "${answer}"
                    fi
                done
            done
            for answer in $'n\n' $'\n' $'0\n' $'\004'; do
                targetReply 'Docker Fail2ban 维护' $'20\n'
                targetReply '受保护 WS 入口 ID（0 返回）' $'entry-fixture\n'
                targetReply '新 WS 公开端口（0 返回）' $'25444\n'
                targetReply '确认修改单入口 WS 保护端口？[y/N]' "${answer}"
            done
            ;;
        fail2ban-port*)
            targetReply 'Docker Fail2ban 维护' $'20\n'
            if [[ "${scenario}" != fail2ban-port-list-failed ]]; then
                targetReply '受保护 WS 入口 ID（0 返回）' $'entry-fixture\n'
                port=25444
                [[ "${scenario}" != fail2ban-port-invalid ]] || port=not-a-port
                targetReply '新 WS 公开端口（0 返回）' "${port}"$'\n'
                targetReply '确认修改单入口 WS 保护端口？[y/N]' $'y\n'
            fi
            # 后端失败后仍能进行下一次只读操作。
            targetReply 'Docker Fail2ban 维护' $'1\n'
            ;;
        fail2ban-enable*|fail2ban-settings*)
            action=${scenario#fail2ban-}
            action=${action%%-*}
            choice=${enableChoice}
            [[ "${action}" != settings ]] || choice=${settingsChoice}
            local -a fields=('保护 WS 端口（逗号分隔，0 返回）' '失败阈值（1–20，0 返回）'
                '检测窗口秒（60–86400，0 返回）' '封禁秒数（60–604800，0 返回）')
            local -a values=(24444,24445 6 600 3600)
            if [[ "${scope}" == control ]]; then
                fields=("${fields[@]:1}")
                values=("${values[@]:1}")
            fi
            if [[ "${scenario}" == *-cancel ]]; then
                for ((field = 0; field < ${#fields[@]}; field++)); do
                    for answer in $'0\n' $'\004'; do
                        targetReply 'Docker Fail2ban 维护' "${choice}"$'\n'
                        for ((previous = 0; previous < field; previous++)); do
                            targetReply "${fields[previous]}" "${values[previous]}"$'\n'
                        done
                        targetReply "${fields[field]}" "${answer}"
                    done
                done
                for answer in $'n\n' $'\n' $'0\n' $'\004'; do
                    targetReply 'Docker Fail2ban 维护' "${choice}"$'\n'
                    for ((field = 0; field < ${#fields[@]}; field++)); do
                        targetReply "${fields[field]}" "${values[field]}"$'\n'
                    done
                    if [[ "${action}" == enable ]]; then
                        targetReply "${enablePrompt}" "${answer}"
                    else
                        targetReply "${settingsPrompt}" "${answer}"
                    fi
                done
            else
                targetReply 'Docker Fail2ban 维护' "${choice}"$'\n'
                if [[ "${scenario}" != *-list-failed ]]; then
                    for ((field = 0; field < ${#fields[@]}; field++)); do
                        answer=${values[field]}
                        [[ "${scenario}" != *-invalid || "${field}" -ne 0 ]] || answer=not-a-port
                        [[ "${scenario}" != fail2ban-enable ||
                            ( "${scope}" == ws && "${field}" -eq 0 ) ]] || answer=''
                        targetReply "${fields[field]}" "${answer}"$'\n'
                    done
                    if [[ "${action}" == enable ]]; then
                        targetReply "${enablePrompt}" $'y\n'
                    else
                        targetReply "${settingsPrompt}" $'y\n'
                    fi
                    if [[ "${scenario}" == *-int || "${scenario}" == *-term ]]; then
                        waitForText 'fixture-fail2ban-ready' "${CONTROL_LOG}" || exit 35
                        assertNoLock
                        if [[ "${scenario}" == *-term ]]; then
                            kill -TERM "$(<"${TEST_ROOT}/menu.pid")" || exit 36
                            return 0
                        fi
                        printf '\003' >&3
                    fi
                fi
            fi
            ;;
        fail2ban-menu-eof) ;;
        *)
            [[ "${scenario}" != fail2ban-failed ]] ||
                targetReply 'Docker Fail2ban 维护' "${statusChoice}"$'\n'
            targetReply 'Docker Fail2ban 维护' "${unbanChoice}"$'\n'
            address=203.0.113.9
            [[ "${scenario}" != fail2ban-invalid ]] || address=not-an-ip
            targetReply "${addressPrompt}" "${address}"$'\n'
            targetReply "确认从 ${jail} 解封 ${address}？[y/N]: " $'y\n'
            if [[ "${scenario}" == fail2ban-int || "${scenario}" == fail2ban-term ]]; then
                waitForText 'fixture-fail2ban-ready' "${CONTROL_LOG}" || exit 35
                assertNoLock
                if [[ "${scenario}" == fail2ban-term ]]; then
                    kill -TERM "$(<"${TEST_ROOT}/menu.pid")" || exit 36
                    return 0
                fi
                printf '\003' >&3
            fi
            ;;
        esac
        if [[ "${scenario}" == fail2ban-menu-eof ]]; then
            targetReply 'Docker Fail2ban 维护' $'\004'
        else
            targetReply 'Docker Fail2ban 维护' $'0\n'
        fi
        ;;
    esac
    targetReply 'Docker 服务维护' $'0\n'
    targetReply 'Docker 管理菜单' $'0\n'
}

runControlDriver() {
    local scenario=$1 listenerInput overLimit controlChoice controlPrompt controlInput
    local -A targetPrompts=()
    targetReply 'Docker 管理菜单' $'15\n'
    case "${scenario}" in
    peers|peers-cancel|peers-input-eof|peers-confirm-eof|peers-failed)
        if [[ "${scenario}" == peers-input-eof ]]; then
            targetReply 'Docker 控制连接' $'22\n'
            targetReply '已配置 WireGuard 的 Peer RFC1918 IPv4（0 返回）' $'\004'
        else
            if [[ "${scenario}" == peers-cancel ]]; then
                for controlChoice in 3 4 7 22 23; do
                    controlPrompt='Peer ID（v2 必填，v1 可留空，0 返回）'
                    [[ "${controlChoice}" != 22 ]] ||
                        controlPrompt='已配置 WireGuard 的 Peer RFC1918 IPv4（0 返回）'
                    [[ "${controlChoice}" != 23 ]] ||
                        controlPrompt='已撤销授权的 Peer ID（0 返回）'
                    targetReply 'Docker 控制连接' "${controlChoice}"$'\n'
                    targetReply "${controlPrompt}" $'0\n'
                done
            fi
            targetReply 'Docker 控制连接' $'20\n'
            case "${scenario}" in
            peers-cancel) targetReply 'fixture-control-confirm [y/N]' $'n\n' ;;
            peers-confirm-eof) targetReply 'fixture-control-confirm [y/N]' $'\004' ;;
            *) targetReply 'fixture-control-confirm [y/N]' $'y\n' ;;
            esac
            if [[ "${scenario}" == peers || "${scenario}" == peers-failed ]]; then
                targetReply 'Docker 控制连接' $'21\n'
                targetReply 'Docker 控制连接' $'22\n'
                targetReply '已配置 WireGuard 的 Peer RFC1918 IPv4（0 返回）' $'10.77.0.3\n'
                targetReply 'fixture-control-confirm [y/N]' $'y\n'
                targetReply 'Docker 控制连接' $'23\n'
                targetReply '已撤销授权的 Peer ID（0 返回）' $'55555555-5555-4555-8555-555555555555\n'
                targetReply 'fixture-control-confirm [y/N]' $'y\n'
                targetReply 'Docker 控制连接' $'3\n'
                targetReply 'Peer ID（v2 必填，v1 可留空，0 返回）' $'55555555-5555-4555-8555-555555555555\n'
                targetReply '邀请文件绝对路径（受管目录外，0 返回）' $'/root/padm-invite.json\n'
                targetReply '授权有效秒数 [86400，0 返回]' $'3600\n'
                targetReply 'fixture-control-confirm [y/N]' $'y\n'
                targetReply 'Docker 控制连接' $'4\n'
                targetReply 'Peer ID（v2 必填，v1 可留空，0 返回）' $'55555555-5555-4555-8555-555555555555\n'
                targetReply 'fixture-control-confirm [y/N]' $'y\n'
                targetReply 'Docker 控制连接' $'7\n'
                targetReply 'Peer ID（v2 必填，v1 可留空，0 返回）' $'55555555-5555-4555-8555-555555555555\n'
                targetReply 'Docker 控制连接' $'1\n'
            fi
        fi
        targetReply 'Docker 控制连接' $'0\n'
        targetReply 'Docker 管理菜单' $'0\n'
        return 0
        ;;
    endpoint|endpoint-input-cancel|endpoint-input-eof|endpoint-confirm-cancel|endpoint-confirm-eof|endpoint-failed)
        for controlChoice in 16 17 19; do
            controlPrompt='新主控 API 端口（1024–65535，0 返回）'
            controlInput=19443
            if [[ "${controlChoice}" != 16 ]]; then
                controlPrompt='私有邀请文件绝对路径（0 返回）'
                controlInput=/root/padm-invite.json
            fi
            targetReply 'Docker 控制连接' "${controlChoice}"$'\n'
            case "${scenario}" in
            endpoint-input-cancel)
                targetReply "${controlPrompt}" $'0\n'
                targetReply 'Docker 控制连接' "${controlChoice}"$'\n'
                targetReply "${controlPrompt}" $'\n'
                ;;
            endpoint-input-eof) targetReply "${controlPrompt}" $'\004' ;;
            *)
                targetReply "${controlPrompt}" "${controlInput}"$'\n'
                case "${scenario}" in
                endpoint-confirm-cancel) targetReply 'fixture-control-confirm [y/N]' $'n\n' ;;
                endpoint-confirm-eof) targetReply 'fixture-control-confirm [y/N]' $'\004' ;;
                *) targetReply 'fixture-control-confirm [y/N]' $'y\n' ;;
                esac
                ;;
            esac
        done
        if [[ "${scenario}" == endpoint || "${scenario}" == endpoint-failed ]]; then
            targetReply 'Docker 控制连接' $'1\n'
        fi
        targetReply 'Docker 控制连接' $'0\n'
        targetReply 'Docker 管理菜单' $'0\n'
        return 0
        ;;
    sync-schedule|sync-schedule-input-cancel|sync-schedule-input-eof|sync-schedule-confirm-cancel|sync-schedule-confirm-eof|sync-schedule-failed)
        if [[ "${scenario}" == sync-schedule-input-cancel ]]; then
            targetReply 'Docker 控制连接' $'13\n'
            targetReply '外部私有邀请文件绝对路径（0 返回）' $'0\n'
            targetReply 'Docker 控制连接' $'13\n'
            targetReply '外部私有邀请文件绝对路径（0 返回）' $'\n'
        elif [[ "${scenario}" == sync-schedule-input-eof ]]; then
            targetReply 'Docker 控制连接' $'13\n'
            targetReply '外部私有邀请文件绝对路径（0 返回）' $'\004'
        else
            if [[ "${scenario}" == sync-schedule || "${scenario}" == sync-schedule-failed ]]; then
                targetReply 'Docker 控制连接' $'12\n'
            fi
            targetReply 'Docker 控制连接' $'13\n'
            targetReply '外部私有邀请文件绝对路径（0 返回）' $'/root/padm-invite.json\n'
            case "${scenario}" in
            sync-schedule-confirm-cancel) targetReply 'fixture-control-sync-schedule-confirm [y/N]' $'n\n' ;;
            sync-schedule-confirm-eof) targetReply 'fixture-control-sync-schedule-confirm [y/N]' $'\004' ;;
            *) targetReply 'fixture-control-sync-schedule-confirm [y/N]' $'y\n' ;;
            esac
            if [[ "${scenario}" == sync-schedule ]]; then
                targetReply 'Docker 控制连接' $'13\n'
                targetReply '外部私有邀请文件绝对路径（0 返回）' $'/root/padm-rotated.json\n'
                targetReply 'fixture-control-sync-schedule-confirm [y/N]' $'y\n'
            fi
            targetReply 'Docker 控制连接' $'14\n'
            case "${scenario}" in
            sync-schedule-confirm-cancel) targetReply 'fixture-control-sync-schedule-confirm [y/N]' $'n\n' ;;
            sync-schedule-confirm-eof) targetReply 'fixture-control-sync-schedule-confirm [y/N]' $'\004' ;;
            *) targetReply 'fixture-control-sync-schedule-confirm [y/N]' $'y\n' ;;
            esac
            if [[ "${scenario}" == sync-schedule-failed ]]; then
                targetReply 'Docker 控制连接' $'1\n'
            else
                targetReply 'Docker 控制连接' $'12\n'
            fi
        fi
        targetReply 'Docker 控制连接' $'0\n'
        targetReply 'Docker 管理菜单' $'0\n'
        return 0
        ;;
    log-schedule|log-schedule-cancel|log-schedule-eof|log-schedule-failed)
        if [[ "${scenario}" == log-schedule || "${scenario}" == log-schedule-failed ]]; then
            targetReply 'Docker 控制连接' $'9\n'
        fi
        targetReply 'Docker 控制连接' $'10\n'
        case "${scenario}" in
        log-schedule-cancel) targetReply 'fixture-control-log-schedule-confirm [yes]' $'n\n' ;;
        log-schedule-eof) targetReply 'fixture-control-log-schedule-confirm [yes]' $'\004' ;;
        *) targetReply 'fixture-control-log-schedule-confirm [yes]' $'yes\n' ;;
        esac
        targetReply 'Docker 控制连接' $'11\n'
        case "${scenario}" in
        log-schedule-cancel) targetReply 'fixture-control-log-schedule-confirm [yes]' $'n\n' ;;
        log-schedule-eof) targetReply 'fixture-control-log-schedule-confirm [yes]' $'\004' ;;
        *) targetReply 'fixture-control-log-schedule-confirm [yes]' $'yes\n' ;;
        esac
        if [[ "${scenario}" == log-schedule-failed ]]; then
            targetReply 'Docker 控制连接' $'1\n'
        else
            targetReply 'Docker 控制连接' $'9\n'
        fi
        targetReply 'Docker 控制连接' $'0\n'
        targetReply 'Docker 管理菜单' $'0\n'
        return 0
        ;;
    diagnostics|diagnostics-failed|log-rotate-cancel|log-rotate-eof|source-menu-eof)
        if [[ "${scenario}" != log-rotate-* ]]; then
            targetReply 'Docker 控制连接' $'7\n'
            targetReply 'Peer ID（v2 必填，v1 可留空，0 返回）' $'\n'
        fi
        if [[ "${scenario}" == source-menu-eof ]]; then
            targetReply 'Docker 控制连接' $'\004'
        else
            targetReply 'Docker 控制连接' $'8\n'
            case "${scenario}" in
            log-rotate-cancel) targetReply 'fixture-control-rotate-confirm [yes]' $'n\n' ;;
            log-rotate-eof) targetReply 'fixture-control-rotate-confirm [yes]' $'\004' ;;
            *) targetReply 'fixture-control-rotate-confirm [yes]' $'yes\n' ;;
            esac
            if [[ "${scenario}" == diagnostics-failed ]]; then
                targetReply 'Docker 控制连接' $'1\n'
            fi
            targetReply 'Docker 控制连接' $'0\n'
        fi
        targetReply 'Docker 管理菜单' $'0\n'
        return 0
        ;;
    join-mapping-invalid|join-mapping-eof|remap-mapping-invalid|remap-mapping-eof)
        controlChoice=5
        [[ "${scenario}" != remap-* ]] || controlChoice=15
        if [[ "${scenario}" == *-mapping-invalid ]]; then
            printf -v overLimit 'entry-%s,' {1..17}
            overLimit=${overLimit%,}
            for listenerInput in ',entry-reality' 'entry-reality,' 'entry-reality,,entry-secondary' \
                'entry-reality,invalid' 'entry-reality, entry-secondary' "${overLimit}"; do
                targetReply 'Docker 控制连接' "${controlChoice}"$'\n'
                targetReply '私有邀请文件绝对路径（0 返回）' $'/root/padm-invite.json\n'
                targetReply '映射入口 ID（逗号分隔，最多 16 项，0 返回）' "${listenerInput}"$'\n'
            done
        else
            targetReply 'Docker 控制连接' "${controlChoice}"$'\n'
            targetReply '私有邀请文件绝对路径（0 返回）' $'/root/padm-invite.json\n'
            targetReply '映射入口 ID（逗号分隔，最多 16 项，0 返回）' $'\004'
        fi
        targetReply 'Docker 控制连接' $'0\n'
        targetReply 'Docker 管理菜单' $'0\n'
        return 0
        ;;
    join|join-multiple|join-cancel|join-eof|remap|remap-multiple|remap-cancel|remap-eof|remap-failed|sync|sync-cancel|sync-eof|sync-failed)
        if [[ "${scenario}" == join* || "${scenario}" == remap* ]]; then
            controlChoice=5
            [[ "${scenario}" != remap* ]] || controlChoice=15
            if [[ "${scenario}" == *-cancel ]]; then
                targetReply 'Docker 控制连接' "${controlChoice}"$'\n'
                targetReply '私有邀请文件绝对路径（0 返回）' $'0\n'
                for listenerInput in 0 ''; do
                    targetReply 'Docker 控制连接' "${controlChoice}"$'\n'
                    targetReply '私有邀请文件绝对路径（0 返回）' $'/root/padm-invite.json\n'
                    targetReply '映射入口 ID（逗号分隔，最多 16 项，0 返回）' "${listenerInput}"$'\n'
                done
            fi
            targetReply 'Docker 控制连接' "${controlChoice}"$'\n'
            targetReply '私有邀请文件绝对路径（0 返回）' $'/root/padm-invite.json\n'
            listenerInput=entry-reality
            [[ "${scenario}" != *-multiple ]] || listenerInput=entry-secondary,entry-reality
            targetReply '映射入口 ID（逗号分隔，最多 16 项，0 返回）' "${listenerInput}"$'\n'
            case "${scenario}" in
            *-cancel) targetReply 'fixture-control-confirm [y/N]' $'n\n' ;;
            *-eof) targetReply 'fixture-control-confirm [y/N]' $'\004' ;;
            *) targetReply 'fixture-control-confirm [y/N]' $'y\n' ;;
            esac
        else
            targetReply 'Docker 控制连接' $'6\n'
            case "${scenario}" in
            sync-cancel) targetReply '私有邀请文件绝对路径（0 返回）' $'0\n' ;;
            sync-eof) targetReply '私有邀请文件绝对路径（0 返回）' $'\004' ;;
            *) targetReply '私有邀请文件绝对路径（0 返回）' $'/root/padm-invite.json\n' ;;
            esac
        fi
        if [[ "${scenario}" == *-failed ]]; then
            targetReply 'Docker 控制连接' $'1\n'
        fi
        targetReply 'Docker 控制连接' $'0\n'
        targetReply 'Docker 管理菜单' $'0\n'
        return 0
        ;;
    invite|invite-cancel|invite-eof|revoke|revoke-cancel)
        if [[ "${scenario}" == invite* ]]; then
            if [[ "${scenario}" == invite-cancel ]]; then
                targetReply 'Docker 控制连接' $'3\n'
                targetReply 'Peer ID（v2 必填，v1 可留空，0 返回）' $'\n'
                targetReply '邀请文件绝对路径（受管目录外，0 返回）' $'0\n'
                targetReply 'Docker 控制连接' $'3\n'
                targetReply 'Peer ID（v2 必填，v1 可留空，0 返回）' $'\n'
                targetReply '邀请文件绝对路径（受管目录外，0 返回）' $'/root/padm-invite.json\n'
                targetReply '授权有效秒数 [86400，0 返回]' $'0\n'
            fi
            targetReply 'Docker 控制连接' $'3\n'
            targetReply 'Peer ID（v2 必填，v1 可留空，0 返回）' $'\n'
            targetReply '邀请文件绝对路径（受管目录外，0 返回）' $'/root/padm-invite.json\n'
            if [[ "${scenario}" == invite ]]; then
                targetReply '授权有效秒数 [86400，0 返回]' $'3600\n'
            else
                targetReply '授权有效秒数 [86400，0 返回]' $'\n'
            fi
        else
            targetReply 'Docker 控制连接' $'4\n'
            targetReply 'Peer ID（v2 必填，v1 可留空，0 返回）' $'\n'
        fi
        case "${scenario}" in
        *-cancel) targetReply 'fixture-control-confirm [y/N]' $'n\n' ;;
        *-eof) targetReply 'fixture-control-confirm [y/N]' $'\004' ;;
        *) targetReply 'fixture-control-confirm [y/N]' $'y\n' ;;
        esac
        targetReply 'Docker 控制连接' $'0\n'
        targetReply 'Docker 管理菜单' $'0\n'
        return 0
        ;;
    flow)
        targetReply 'Docker 控制连接' $'1\n'
        ;;
    cancel)
        targetReply 'Docker 控制连接' $'2\n'
        targetReply '主控 WireGuard IPv4（0 返回）' $'0\n'
        targetReply 'Docker 控制连接' $'2\n'
        targetReply '主控 WireGuard IPv4（0 返回）' $'10.77.0.1\n'
        targetReply '控制监听端口 [18443，0 返回]' $'0\n'
        targetReply 'Docker 控制连接' $'2\n'
        targetReply '主控 WireGuard IPv4（0 返回）' $'10.77.0.1\n'
        targetReply '控制监听端口 [18443，0 返回]' $'\n'
        targetReply '对端 WireGuard IPv4（0 返回）' $'0\n'
        ;;
    esac
    targetReply 'Docker 控制连接' $'2\n'
    targetReply '主控 WireGuard IPv4（0 返回）' $'10.77.0.1\n'
    if [[ "${scenario}" == flow ]]; then
        targetReply '控制监听端口 [18443，0 返回]' $'19443\n'
    else
        targetReply '控制监听端口 [18443，0 返回]' $'\n'
    fi
    if [[ "${scenario}" == input-eof ]]; then
        targetReply '对端 WireGuard IPv4（0 返回）' $'\004'
    else
        targetReply '对端 WireGuard IPv4（0 返回）' $'10.77.0.2\n'
        case "${scenario}" in
        cancel) targetReply 'fixture-control-confirm [y/N]' $'n\n' ;;
        confirm-eof) targetReply 'fixture-control-confirm [y/N]' $'\004' ;;
        *) targetReply 'fixture-control-confirm [y/N]' $'y\n' ;;
        esac
    fi
    if [[ "${scenario}" == failed ]]; then
        targetReply 'Docker 控制连接' $'1\n'
    fi
    targetReply 'Docker 控制连接' $'0\n'
    targetReply 'Docker 管理菜单' $'0\n'
}

runSitesDriver() {
    local scenario=$1 alpnOrder alpnAction themeChoice
    local -A targetPrompts=()
    targetReply 'Docker 管理菜单' $'16\n'
    : >"${TLS_WIZARD_ACTIONS}"
    case "${scenario}" in
    flow)
        targetReply 'Docker 站点管理' $'1\n'
        targetReply 'Docker 站点管理' $'2\n'
        targetReply '独立静态站点目录绝对路径（0 返回）' $'/root/public-site\n'
        targetReply 'Docker 站点管理' $'3\n'
        targetReply '302 HTTP/HTTPS 目标 URL（0 返回）' $'https://example.com/path?a=1&b=2\n'
        targetReply 'Docker 站点管理' $'4\n'
        targetReply 'Docker 站点管理' $'5\n'
        targetReply 'TLS fallback 入口 ID（空输入诊断全部，0 返回）' $'\n'
        targetReply 'Docker 站点管理' $'5\n'
        targetReply 'TLS fallback 入口 ID（空输入诊断全部，0 返回）' $'entry-tls\n'
        targetReply 'Docker 站点管理' $'6\n'
        targetReply 'TLS fallback 入口 ID（0 返回）' $'entry-tls\n'
        for alpnOrder in 1 2 3; do
            targetReply 'Docker 站点管理' $'7\n'
            targetReply 'TLS fallback 入口 ID（0 返回）' $'entry-tls\n'
            targetReply '请选择 ALPN 顺序（0 返回）' "${alpnOrder}"$'\n'
        done
        for themeChoice in 1 2 3; do
            targetReply 'Docker 站点管理' $'8\n'
            targetReply '请选择站点主题（0 返回）' "${themeChoice}"$'\n'
            targetReply '站名（2–60 个字符，空输入使用主题默认值，0 返回）' $'\n'
        done
        ;;
    title)
        targetReply 'Docker 站点管理' $'8\n'
        targetReply '请选择站点主题（0 返回）' $'1\n'
        targetReply '站名（2–60 个字符，空输入使用主题默认值，0 返回）' \
            $'中文 & <站点> "双引" \'单引\' | \\\n'
        ;;
    cancel)
        targetReply 'Docker 站点管理' $'2\n'
        targetReply '独立静态站点目录绝对路径（0 返回）' $'0\n'
        targetReply 'Docker 站点管理' $'3\n'
        targetReply '302 HTTP/HTTPS 目标 URL（0 返回）' $'0\n'
        targetReply 'Docker 站点管理' $'5\n'
        targetReply 'TLS fallback 入口 ID（空输入诊断全部，0 返回）' $'0\n'
        for alpnAction in 6 7; do
            targetReply 'Docker 站点管理' "${alpnAction}"$'\n'
            targetReply 'TLS fallback 入口 ID（0 返回）' $'0\n'
            targetReply 'Docker 站点管理' "${alpnAction}"$'\n'
            targetReply 'TLS fallback 入口 ID（0 返回）' $'\n'
        done
        targetReply 'Docker 站点管理' $'7\n'
        targetReply 'TLS fallback 入口 ID（0 返回）' $'entry-tls\n'
        targetReply '请选择 ALPN 顺序（0 返回）' $'0\n'
        targetReply 'Docker 站点管理' $'7\n'
        targetReply 'TLS fallback 入口 ID（0 返回）' $'entry-tls\n'
        targetReply '请选择 ALPN 顺序（0 返回）' $'invalid\n'
        for themeChoice in 0 invalid; do
            targetReply 'Docker 站点管理' $'8\n'
            targetReply '请选择站点主题（0 返回）' "${themeChoice}"$'\n'
        done
        targetReply 'Docker 站点管理' $'8\n'
        targetReply '请选择站点主题（0 返回）' $'1\n'
        targetReply '站名（2–60 个字符，空输入使用主题默认值，0 返回）' $'0\n'
        ;;
    template-eof)
        targetReply 'Docker 站点管理' $'8\n'
        targetReply '请选择站点主题（0 返回）' $'\004'
        ;;
    title-eof)
        targetReply 'Docker 站点管理' $'8\n'
        targetReply '请选择站点主题（0 返回）' $'1\n'
        targetReply '站名（2–60 个字符，空输入使用主题默认值，0 返回）' $'\004'
        ;;
    static-eof|redirect-eof)
        if [[ "${scenario}" == static-eof ]]; then
            targetReply 'Docker 站点管理' $'2\n'
            targetReply '独立静态站点目录绝对路径（0 返回）' $'\004'
        else
            targetReply 'Docker 站点管理' $'3\n'
            targetReply '302 HTTP/HTTPS 目标 URL（0 返回）' $'\004'
        fi
        ;;
    alpn-diagnose-eof|alpn-recommended-eof|alpn-manual-id-eof|alpn-manual-order-eof)
        case "${scenario}" in
        alpn-diagnose-eof)
            targetReply 'Docker 站点管理' $'5\n'
            targetReply 'TLS fallback 入口 ID（空输入诊断全部，0 返回）' $'\004'
            ;;
        alpn-recommended-eof)
            targetReply 'Docker 站点管理' $'6\n'
            targetReply 'TLS fallback 入口 ID（0 返回）' $'\004'
            ;;
        *)
            targetReply 'Docker 站点管理' $'7\n'
            if [[ "${scenario}" == alpn-manual-id-eof ]]; then
                targetReply 'TLS fallback 入口 ID（0 返回）' $'\004'
            else
                targetReply 'TLS fallback 入口 ID（0 返回）' $'entry-tls\n'
                targetReply '请选择 ALPN 顺序（0 返回）' $'\004'
            fi
            ;;
        esac
        ;;
    failed)
        targetReply 'Docker 站点管理' $'1\n'
        targetReply 'Docker 站点管理' $'5\n'
        targetReply 'TLS fallback 入口 ID（空输入诊断全部，0 返回）' $'entry-tls\n'
        targetReply 'Docker 站点管理' $'6\n'
        targetReply 'TLS fallback 入口 ID（0 返回）' $'entry-tls\n'
        targetReply 'Docker 站点管理' $'7\n'
        targetReply 'TLS fallback 入口 ID（0 返回）' $'entry-tls\n'
        targetReply '请选择 ALPN 顺序（0 返回）' $'2\n'
        targetReply 'Docker 站点管理' $'8\n'
        targetReply '请选择站点主题（0 返回）' $'1\n'
        targetReply '站名（2–60 个字符，空输入使用主题默认值，0 返回）' $'\n'
        targetReply 'Docker 站点管理' $'4\n'
        ;;
    esac
    targetReply 'Docker 站点管理' $'0\n'
    targetReply 'Docker 管理菜单' $'0\n'
}

runRoutingDriver() {
    local scenario=$1 choice input family variant oldRule newRule index
    local inputPrompt menuLabel familyLabel addChoice removeChoice statusChoice
    local replaceCase replaceKind oldPrompt newPrompt
    local -A targetPrompts=()
    local -a replaceVariants=(valid)
    local -a replaceFamilies=(dns direct block ipv6 warp region socks5)
    targetReply 'Docker 管理菜单' $'17\n'
    : >"${TLS_WIZARD_ACTIONS}"
    case "${scenario}" in
    csv-long)
        input=
        for ((index = 1; index <= 257; index++)); do
            printf -v newRule 'd%03d.example.com' "${index}"
            input+="${input:+,}${newRule}"
            [[ "${index}" -ge 256 ]] || continue
            targetReply 'Docker 路由与出站' $'10\n'
            targetReply '替换域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' "${input}"$'\n'
        done
        ;;
    flow|failed)
        targetReply 'Docker 路由与出站' $'invalid\n'
        targetReply 'Docker 路由与出站' $'1\n'
        [[ "${scenario}" == failed ]] ||
            targetReply 'fixture-socks5-input-confirm [y/N]' $'y\n'
        targetReply 'Docker 路由与出站' $'2\n'
        targetReply 'Docker 路由与出站' $'3\n'
        targetReply 'Docker 路由与出站' $'4\n'
        targetReply 'SOCKS5 域名规则（逗号分隔；domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET, full:Exact.Example.Com, geosite:cn\n'
        targetReply 'Docker 路由与出站' $'5\n'
        targetReply 'Docker 路由与出站' $'3\n'
        targetReply 'Docker 路由与出站' $'6\n'
        targetReply 'DNS 服务器 IPv4/IPv6（0 返回）' $'203.0.113.53\n'
        targetReply 'DNS 端口 [53，0 返回]' $'\n'
        targetReply 'DNS 域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\n'
        targetReply 'Docker 路由与出站' $'7\n'
        targetReply 'Docker 路由与出站' $'8\n'
        [[ "${scenario}" == failed ]] ||
            targetReply 'fixture-hosts-input-confirm [y/N]' $'y\n'
        targetReply 'Docker 路由与出站' $'9\n'
        targetReply 'Docker 路由与出站' $'10\n'
        targetReply '替换域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\n'
        targetReply 'Docker 路由与出站' $'11\n'
        targetReply 'Docker 路由与出站' $'12\n'
        targetReply '替换域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\n'
        targetReply 'Docker 路由与出站' $'13\n'
        targetReply 'Docker 路由与出站' $'14\n'
        targetReply 'IP/CIDR 规则 CSV（字面 IP/CIDR 或 geoip:cn，逗号分隔，0 返回）' $'192.0.2.10, 2001:DB8::10, geoip:cn\n'
        targetReply 'Docker 路由与出站' $'15\n'
        targetReply 'Docker 路由与出站' $'16\n'
        targetReply 'Docker 路由与出站' $'17\n'
        targetReply 'Docker 路由与出站' $'18\n'
        targetReply 'Docker 区域阻断策略' $'invalid\n'
        targetReply 'Docker 区域阻断策略' $'1\n'
        targetReply '替换自定义直连例外规则' $'Example.NET, full:Exact.Example.Com\n'
        targetReply 'Docker 区域阻断策略' $'2\n'
        targetReply '替换自定义直连例外规则' $'\n'
        targetReply 'Docker 区域阻断策略' $'3\n'
        targetReply '替换自定义直连例外规则' $'\n'
        targetReply 'Docker 区域阻断策略' $'5\n'
        targetReply '追加自定义直连例外 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\n'
        targetReply 'Docker 区域阻断策略' $'6\n'
        targetReply '删除自定义直连例外 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\n'
        targetReply 'Docker 区域阻断策略' $'4\n'
        targetReply 'Docker 区域阻断策略' $'0\n'
        targetReply 'Docker 路由与出站' $'19\n'
        targetReply 'Docker IPv6 域名出站' $'invalid\n'
        targetReply 'Docker IPv6 域名出站' $'1\n'
        targetReply 'IPv6 域名规则（逗号分隔；domain:/full:/keyword:/geosite:，0 返回）: ' $'Example.NET, full:Exact.Example.Com\n'
        targetReply 'Docker IPv6 域名出站' $'5\n'
        targetReply '追加 IPv6 域名规则 CSV' $'Example.NET, full:Exact.Example.Com\n'
        targetReply 'fixture-ipv6-daily-confirm [y/N]' $'y\n'
        targetReply 'Docker IPv6 域名出站' $'6\n'
        targetReply '精确删除 IPv6 域名规则 CSV' $'Example.NET, full:Exact.Example.Com\n'
        targetReply 'fixture-ipv6-daily-confirm [y/N]' $'y\n'
        targetReply 'Docker IPv6 域名出站' $'2\n'
        targetReply 'Docker IPv6 域名出站' $'3\n'
        targetReply 'Docker IPv6 域名出站' $'4\n'
        targetReply 'Docker IPv6 域名出站' $'0\n'
        targetReply 'Docker 路由与出站' $'20\n'
        targetReply 'Docker WARP 出站' $'invalid\n'
        targetReply 'Docker WARP 出站' $'1\n'
        [[ "${scenario}" == failed ]] ||
            targetReply 'fixture-warp-input-confirm [y/N]' $'y\n'
        targetReply 'Docker WARP 出站' $'2\n'
        targetReply 'Docker WARP 出站' $'3\n'
        targetReply 'Docker WARP 出站' $'4\n'
        targetReply 'WARP 域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\n'
        targetReply 'fixture-warp-daily-confirm [y/N]' $'y\n'
        targetReply 'Docker WARP 出站' $'8\n'
        targetReply '追加 WARP 域名规则 CSV' $'Example.NET, full:Exact.Example.Com\n'
        targetReply 'fixture-warp-daily-confirm [y/N]' $'y\n'
        targetReply 'Docker WARP 出站' $'9\n'
        targetReply '精确删除 WARP 域名规则 CSV' $'Example.NET, full:Exact.Example.Com\n'
        targetReply 'fixture-warp-daily-confirm [y/N]' $'y\n'
        for choice in 5 6 7; do
            targetReply 'Docker WARP 出站' "${choice}"$'\n'
            targetReply 'fixture-warp-daily-confirm [y/N]' $'y\n'
        done
        targetReply 'Docker WARP 出站' $'3\n'
        targetReply 'Docker WARP 出站' $'0\n'
        targetReply 'Docker 路由与出站' $'21\n'
        targetReply 'Docker HTTP 中继入站' $'invalid\n'
        targetReply 'Docker HTTP 中继入站' $'1\n'
        [[ "${scenario}" == failed ]] ||
            targetReply 'fixture-http-relay-input-confirm [y/N]' $'y\n'
        targetReply 'Docker HTTP 中继入站' $'2\n'
        targetReply 'Docker HTTP 中继入站' $'3\n'
        targetReply 'Docker HTTP 中继入站' $'0\n'
        for choice in 22 23; do
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            targetReply '追加域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\n'
        done
        for choice in 24 25; do
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            targetReply '精确删除域名规则 CSV（删空关闭；domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\n'
        done
        targetReply 'Docker 路由与出站' $'26\n'
        targetReply 'IP/CIDR 规则 CSV（字面 IP/CIDR 或 geoip:cn，逗号分隔，0 返回）' $'198.51.100.17/24, 2001:DB8::/64\n'
        targetReply 'Docker 路由与出站' $'27\n'
        targetReply 'IP/CIDR 规则 CSV（字面 IP/CIDR 或 geoip:cn，逗号分隔，0 返回）' $'192.0.2.10, 2001:DB8::10\n'
        targetReply 'Docker 路由与出站' $'3\n'
        targetReply 'Docker 路由与出站' $'28\n'
        targetReply '追加域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET, full:Exact.Example.Com\n'
        targetReply 'Docker 路由与出站' $'29\n'
        targetReply '精确删除域名规则 CSV（删空关闭；domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET, full:Exact.Example.Com\n'
        targetReply 'Docker 路由与出站' $'3\n'
        for choice in 34 35; do
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            [[ "${scenario}" != failed ]] || continue
            inputPrompt='追加 SOCKS5 域名规则 CSV'
            [[ "${choice}" != 35 ]] || inputPrompt='精确删除 SOCKS5 域名规则 CSV'
            targetReply "${inputPrompt}" $'Example.NET, full:Exact.Example.Com\n'
            targetReply 'fixture-socks5-daily-confirm [y/N]' $'y\n'
        done
        ;;
    cancel)
        for input in 0 '' n; do
            targetReply 'Docker 路由与出站' $'1\n'
            targetReply 'fixture-socks5-input-confirm [y/N]' "${input}"$'\n'
        done
        targetReply 'Docker 路由与出站' $'4\n'
        targetReply 'SOCKS5 域名规则（逗号分隔；domain:/full:/keyword:/geosite:，0 返回）' $'0\n'
        targetReply 'Docker 路由与出站' $'4\n'
        targetReply 'SOCKS5 域名规则（逗号分隔；domain:/full:/keyword:/geosite:，0 返回）' $'\n'
        for choice in 34 35; do
            inputPrompt='追加 SOCKS5 域名规则 CSV'
            [[ "${choice}" != 35 ]] || inputPrompt='精确删除 SOCKS5 域名规则 CSV'
            for input in 0 ''; do
                targetReply 'Docker 路由与出站' "${choice}"$'\n'
                targetReply "${inputPrompt}" "${input}"$'\n'
            done
        done
        targetReply 'Docker 路由与出站' $'6\n'
        targetReply 'DNS 服务器 IPv4/IPv6（0 返回）' $'0\n'
        targetReply 'Docker 路由与出站' $'6\n'
        targetReply 'DNS 服务器 IPv4/IPv6（0 返回）' $'\n'
        targetReply 'Docker 路由与出站' $'6\n'
        targetReply 'DNS 服务器 IPv4/IPv6（0 返回）' $'203.0.113.53\n'
        targetReply 'DNS 端口 [53，0 返回]' $'0\n'
        for input in 0 ''; do
            targetReply 'Docker 路由与出站' $'6\n'
            targetReply 'DNS 服务器 IPv4/IPv6（0 返回）' $'203.0.113.53\n'
            targetReply 'DNS 端口 [53，0 返回]' $'\n'
            targetReply 'DNS 域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' "${input}"$'\n'
        done
        for input in 0 '' n; do
            targetReply 'Docker 路由与出站' $'8\n'
            targetReply 'fixture-hosts-input-confirm [y/N]' "${input}"$'\n'
        done
        for choice in 10 12; do
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            targetReply '替换域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'0\n'
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            targetReply '替换域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'\n'
        done
        for choice in 14 26 27; do
            for input in 0 ''; do
                targetReply 'Docker 路由与出站' "${choice}"$'\n'
                targetReply 'IP/CIDR 规则 CSV（字面 IP/CIDR 或 geoip:cn，逗号分隔，0 返回）' "${input}"$'\n'
            done
        done
        targetReply 'Docker 路由与出站' $'18\n'
        targetReply 'Docker 区域阻断策略' $'1\n'
        targetReply '替换自定义直连例外规则' $'0\n'
        for input in 0 ''; do
            targetReply 'Docker 区域阻断策略' $'5\n'
            targetReply '追加自定义直连例外 CSV（domain:/full:/keyword:/geosite:，0 返回）' "${input}"$'\n'
            targetReply 'Docker 区域阻断策略' $'6\n'
            targetReply '删除自定义直连例外 CSV（domain:/full:/keyword:/geosite:，0 返回）' "${input}"$'\n'
        done
        targetReply 'Docker 区域阻断策略' $'0\n'
        targetReply 'Docker 路由与出站' $'19\n'
        targetReply 'Docker IPv6 域名出站' $'1\n'
        targetReply 'IPv6 域名规则（逗号分隔；domain:/full:/keyword:/geosite:，0 返回）: ' $'0\n'
        targetReply 'Docker IPv6 域名出站' $'1\n'
        targetReply 'IPv6 域名规则（逗号分隔；domain:/full:/keyword:/geosite:，0 返回）: ' $'\n'
        for input in 0 ''; do
            targetReply 'Docker IPv6 域名出站' $'5\n'
            targetReply '追加 IPv6 域名规则 CSV' "${input}"$'\n'
            targetReply 'Docker IPv6 域名出站' $'6\n'
            targetReply '精确删除 IPv6 域名规则 CSV' "${input}"$'\n'
        done
        targetReply 'Docker IPv6 域名出站' $'0\n'
        targetReply 'Docker 路由与出站' $'20\n'
        for input in 0 '' n; do
            targetReply 'Docker WARP 出站' $'1\n'
            targetReply 'fixture-warp-input-confirm [y/N]' "${input}"$'\n'
        done
        targetReply 'Docker WARP 出站' $'4\n'
        targetReply 'WARP 域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'0\n'
        targetReply 'Docker WARP 出站' $'4\n'
        targetReply 'WARP 域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'\n'
        for input in 0 ''; do
            targetReply 'Docker WARP 出站' $'8\n'
            targetReply '追加 WARP 域名规则 CSV' "${input}"$'\n'
            targetReply 'Docker WARP 出站' $'9\n'
            targetReply '精确删除 WARP 域名规则 CSV' "${input}"$'\n'
        done
        targetReply 'Docker WARP 出站' $'0\n'
        targetReply 'Docker 路由与出站' $'21\n'
        for input in 0 '' n; do
            targetReply 'Docker HTTP 中继入站' $'1\n'
            targetReply 'fixture-http-relay-input-confirm [y/N]' "${input}"$'\n'
        done
        targetReply 'Docker HTTP 中继入站' $'0\n'
        for choice in 22 23; do
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            targetReply '追加域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'0\n'
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            targetReply '追加域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'\n'
        done
        for choice in 24 25; do
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            targetReply '精确删除域名规则 CSV（删空关闭；domain:/full:/keyword:/geosite:，0 返回）' $'0\n'
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            targetReply '精确删除域名规则 CSV（删空关闭；domain:/full:/keyword:/geosite:，0 返回）' $'\n'
        done
        targetReply 'Docker 路由与出站' $'28\n'
        targetReply '追加域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'0\n'
        targetReply 'Docker 路由与出站' $'28\n'
        targetReply '追加域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'\n'
        targetReply 'Docker 路由与出站' $'29\n'
        targetReply '精确删除域名规则 CSV（删空关闭；domain:/full:/keyword:/geosite:，0 返回）' $'0\n'
        targetReply 'Docker 路由与出站' $'29\n'
        targetReply '精确删除域名规则 CSV（删空关闭；domain:/full:/keyword:/geosite:，0 返回）' $'\n'
        ;;
    socks5-input-eof|socks5-input-commit-failed)
        targetReply 'Docker 路由与出站' $'1\n'
        input=$'\004'
        [[ "${scenario}" != socks5-input-commit-failed ]] || input=$'y\n'
        targetReply 'fixture-socks5-input-confirm [y/N]' "${input}"
        targetReply 'Docker 路由与出站' $'3\n'
        ;;
    domains-eof)
        targetReply 'Docker 路由与出站' $'4\n'
        targetReply 'SOCKS5 域名规则（逗号分隔；domain:/full:/keyword:/geosite:，0 返回）' $'\004'
        ;;
    dns-server-eof)
        targetReply 'Docker 路由与出站' $'6\n'
        targetReply 'DNS 服务器 IPv4/IPv6（0 返回）' $'\004'
        ;;
    dns-port-eof|dns-domains-eof|dns-explicit-port|dns-invalid|dns-failed)
        targetReply 'Docker 路由与出站' $'6\n'
        targetReply 'DNS 服务器 IPv4/IPv6（0 返回）' $'203.0.113.53\n'
        if [[ "${scenario}" == dns-port-eof ]]; then
            targetReply 'DNS 端口 [53，0 返回]' $'\004'
        else
            case "${scenario}" in
            dns-explicit-port) targetReply 'DNS 端口 [53，0 返回]' $'5353\n' ;;
            dns-invalid) targetReply 'DNS 端口 [53，0 返回]' $'65536\n' ;;
            *) targetReply 'DNS 端口 [53，0 返回]' $'\n' ;;
            esac
            if [[ "${scenario}" == dns-domains-eof ]]; then
                targetReply 'DNS 域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'\004'
            elif [[ "${scenario}" != dns-invalid ]]; then
                targetReply 'DNS 域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET\n'
            fi
            if [[ "${scenario}" == dns-invalid ]]; then
                targetReply 'Docker 路由与出站' $'6\n'
                targetReply 'DNS 服务器 IPv4/IPv6（0 返回）' $'203.0.113.53\n'
                targetReply 'DNS 端口 [53，0 返回]' $'\n'
                targetReply 'DNS 域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'regexp:bad\n'
            fi
        fi
        ;;
    hosts-input-eof|hosts-input-status-failed|hosts-input-commit-failed)
        targetReply 'Docker 路由与出站' $'8\n'
        if [[ "${scenario}" != hosts-input-status-failed ]]; then
            input=$'\004'
            [[ "${scenario}" != hosts-input-commit-failed ]] || input=$'y\n'
            targetReply 'fixture-hosts-input-confirm [y/N]' "${input}"
        fi
        targetReply 'Docker 路由与出站' $'3\n'
        ;;
    direct-domains-eof|block-domains-eof)
        if [[ "${scenario}" == direct-domains-eof ]]; then
            targetReply 'Docker 路由与出站' $'10\n'
        else
            targetReply 'Docker 路由与出站' $'12\n'
        fi
        targetReply '替换域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'\004'
        ;;
    direct-block-invalid)
        for choice in 10 12; do
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            targetReply '替换域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'regexp:bad\n'
        done
        ;;
    direct-domains-add-eof|block-domains-add-eof)
        if [[ "${scenario}" == direct-domains-add-eof ]]; then
            targetReply 'Docker 路由与出站' $'22\n'
        else
            targetReply 'Docker 路由与出站' $'23\n'
        fi
        targetReply '追加域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'\004'
        ;;
    direct-block-add-invalid|direct-block-add-failed)
        for choice in 22 23; do
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            if [[ "${scenario}" == direct-block-add-invalid ]]; then
                targetReply '追加域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'regexp:bad\n'
            else
                targetReply '追加域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET\n'
            fi
        done
        ;;
    direct-domains-remove-eof|block-domains-remove-eof)
        if [[ "${scenario}" == direct-domains-remove-eof ]]; then
            targetReply 'Docker 路由与出站' $'24\n'
        else
            targetReply 'Docker 路由与出站' $'25\n'
        fi
        targetReply '精确删除域名规则 CSV（删空关闭；domain:/full:/keyword:/geosite:，0 返回）' $'\004'
        ;;
    direct-block-remove-invalid|direct-block-remove-failed)
        for choice in 24 25; do
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            if [[ "${scenario}" == direct-block-remove-invalid ]]; then
                targetReply '精确删除域名规则 CSV（删空关闭；domain:/full:/keyword:/geosite:，0 返回）' $'regexp:bad\n'
            else
                targetReply '精确删除域名规则 CSV（删空关闭；domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET\n'
            fi
        done
        ;;
    dns-domains-add-eof|dns-domains-remove-eof)
        if [[ "${scenario}" == dns-domains-add-eof ]]; then
            targetReply 'Docker 路由与出站' $'28\n'
            targetReply '追加域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'\004'
        else
            targetReply 'Docker 路由与出站' $'29\n'
            targetReply '精确删除域名规则 CSV（删空关闭；domain:/full:/keyword:/geosite:，0 返回）' $'\004'
        fi
        ;;
    dns-domains-change-invalid|dns-domains-change-failed)
        for choice in 28 29; do
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            if [[ "${choice}" == 28 ]]; then
                inputPrompt='追加域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）'
            else
                inputPrompt='精确删除域名规则 CSV（删空关闭；domain:/full:/keyword:/geosite:，0 返回）'
            fi
            if [[ "${scenario}" == dns-domains-change-invalid ]]; then
                targetReply "${inputPrompt}" $'regexp:bad\n'
            else
                targetReply "${inputPrompt}" $'Example.NET\n'
            fi
        done
        [[ "${scenario}" != dns-domains-change-failed ]] || \
            targetReply 'Docker 路由与出站' $'3\n'
        ;;
    block-ips-file-eof|block-ips-add-eof|block-ips-remove-eof)
        case "${scenario}" in
        block-ips-file-eof) choice=14 ;;
        block-ips-add-eof) choice=26 ;;
        block-ips-remove-eof) choice=27 ;;
        esac
        targetReply 'Docker 路由与出站' "${choice}"$'\n'
        targetReply 'IP/CIDR 规则 CSV（字面 IP/CIDR 或 geoip:cn，逗号分隔，0 返回）' $'\004'
        ;;
    block-ips-change-failed)
        targetReply 'Docker 路由与出站' $'14\n'
        targetReply 'IP/CIDR 规则 CSV（字面 IP/CIDR 或 geoip:cn，逗号分隔，0 返回）' $'192.0.2.10, geoip:cn\n'
        targetReply 'Docker 路由与出站' $'26\n'
        targetReply 'IP/CIDR 规则 CSV（字面 IP/CIDR 或 geoip:cn，逗号分隔，0 返回）' $'198.51.100.17/24, 2001:DB8::/64\n'
        targetReply 'Docker 路由与出站' $'27\n'
        targetReply 'IP/CIDR 规则 CSV（字面 IP/CIDR 或 geoip:cn，逗号分隔，0 返回）' $'192.0.2.10, 2001:DB8::10\n'
        targetReply 'Docker 路由与出站' $'3\n'
        ;;
    region-eof)
        targetReply 'Docker 路由与出站' $'18\n'
        targetReply 'Docker 区域阻断策略' $'1\n'
        targetReply '替换自定义直连例外规则' $'\004'
        targetReply 'Docker 区域阻断策略' $'5\n'
        targetReply '追加自定义直连例外 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'\004'
        targetReply 'Docker 区域阻断策略' $'6\n'
        targetReply '删除自定义直连例外 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'\004'
        targetReply 'Docker 区域阻断策略' $'0\n'
        ;;
    region-allow-invalid|region-allow-failed)
        targetReply 'Docker 路由与出站' $'18\n'
        input=Example.NET
        [[ "${scenario}" != region-allow-invalid ]] || input=regexp:bad
        targetReply 'Docker 区域阻断策略' $'5\n'
        targetReply '追加自定义直连例外 CSV（domain:/full:/keyword:/geosite:，0 返回）' "${input}"$'\n'
        targetReply 'Docker 区域阻断策略' $'6\n'
        targetReply '删除自定义直连例外 CSV（domain:/full:/keyword:/geosite:，0 返回）' "${input}"$'\n'
        targetReply 'Docker 区域阻断策略' $'0\n'
        ;;
    region-mode-flow|region-mode-cancel|region-mode-failed)
        targetReply 'Docker 路由与出站' $'18\n'
        if [[ "${scenario}" == region-mode-cancel ]]; then
            for input in 0 '' $'\004' invalid Both; do
                targetReply 'Docker 区域阻断策略' $'9\n'
                if [[ "${input}" == $'\004' ]]; then
                    targetReply '区域模式 [both/domain/ip，0 返回]' "${input}"
                else
                    targetReply '区域模式 [both/domain/ip，0 返回]' "${input}"$'\n'
                fi
            done
        else
            for input in both domain ip; do
                targetReply 'Docker 区域阻断策略' $'9\n'
                targetReply '区域模式 [both/domain/ip，0 返回]' "${input}"$'\n'
            done
        fi
        targetReply 'Docker 区域阻断策略' $'8\n'
        targetReply 'Docker 区域阻断策略' $'0\n'
        ;;
    access-control-flow|access-control-cancel|access-control-failed)
        if [[ "${scenario}" == access-control-cancel ]]; then
            for input in $'n\n' $'\004'; do
                targetReply 'Docker 路由与出站' $'40\n'
                targetReply 'fixture-access-control-confirm [y/N]' "${input}"
            done
        else
            targetReply 'Docker 路由与出站' $'40\n'
            targetReply 'fixture-access-control-confirm [y/N]' $'y\n'
        fi
        targetReply 'Docker 路由与出站' $'3\n'
        ;;
    upstream-flow|upstream-cancel|upstream-status-failed|upstream-commit-failed)
        for choice in 41 42; do
            if [[ "${scenario}" == upstream-cancel ]]; then
                for input in 0 '' $'\004'; do
                    targetReply 'Docker 路由与出站' "${choice}"$'\n'
                    inputPrompt='上游服务器 IPv4/IPv6（0 返回）'
                    # 两类上游分担六种取消输入，避免重复展开相同分支。
                    if [[ ( "${choice}" == 41 && -z "${input}" ) ||
                        ( "${choice}" == 42 && -n "${input}" ) ]]; then
                        targetReply "${inputPrompt}" $'203.0.113.53\n'
                        inputPrompt='上游端口（1–65535，0 返回）'
                    fi
                    [[ "${input}" == $'\004' ]] || input+=$'\n'
                    targetReply "${inputPrompt}" "${input}"
                done
                continue
            fi
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            [[ "${scenario}" != upstream-status-failed ]] || continue
            input=$'2001:0DB8::53\n'
            [[ "${choice}" != 42 ]] || input=$'203.0.113.108\n'
            targetReply '上游服务器 IPv4/IPv6（0 返回）' "${input}"
            input=$'5353\n'
            [[ "${choice}" != 42 ]] || input=$'1088\n'
            targetReply '上游端口（1–65535，0 返回）' "${input}"
            targetReply 'fixture-upstream-confirm [y/N]' $'y\n'
        done
        targetReply 'Docker 路由与出站' $'3\n'
        ;;
    ipv6-eof)
        targetReply 'Docker 路由与出站' $'19\n'
        targetReply 'Docker IPv6 域名出站' $'1\n'
        targetReply 'IPv6 域名规则（逗号分隔；domain:/full:/keyword:/geosite:，0 返回）: ' $'\004'
        targetReply 'Docker IPv6 域名出站' $'5\n'
        targetReply '追加 IPv6 域名规则 CSV' $'\004'
        targetReply 'Docker IPv6 域名出站' $'6\n'
        targetReply '精确删除 IPv6 域名规则 CSV' $'\004'
        targetReply 'Docker IPv6 域名出站' $'0\n'
        ;;
    warp-eof)
        targetReply 'Docker 路由与出站' $'20\n'
        targetReply 'Docker WARP 出站' $'1\n'
        targetReply 'fixture-warp-input-confirm [y/N]' $'\004'
        targetReply 'Docker WARP 出站' $'3\n'
        targetReply 'Docker WARP 出站' $'4\n'
        targetReply 'WARP 域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'\004'
        targetReply 'Docker WARP 出站' $'8\n'
        targetReply '追加 WARP 域名规则 CSV' $'\004'
        targetReply 'Docker WARP 出站' $'9\n'
        targetReply '精确删除 WARP 域名规则 CSV' $'\004'
        targetReply 'Docker WARP 出站' $'0\n'
        ;;
    warp-input-status-failed|warp-input-commit-failed)
        targetReply 'Docker 路由与出站' $'20\n'
        targetReply 'Docker WARP 出站' $'1\n'
        [[ "${scenario}" == warp-input-status-failed ]] ||
            targetReply 'fixture-warp-input-confirm [y/N]' $'y\n'
        targetReply 'Docker WARP 出站' $'3\n'
        targetReply 'Docker WARP 出站' $'0\n'
        ;;
    domain-replace-*|ip-replace-*|hosts-replace-*|hosts-manage-*)
        replaceCase=${scenario#*-replace-}
        replaceKind=domain oldPrompt='旧域名规则（单条；' newPrompt='新域名规则（单条；'
        if [[ "${scenario}" == ip-replace-* ]]; then
            replaceKind=ip oldPrompt='旧 IP/CIDR 规则（单条字面' newPrompt='新 IP/CIDR 规则（单条字面'
            replaceFamilies=(ips)
        elif [[ "${scenario}" == hosts-replace-* ]]; then
            replaceKind=hosts oldPrompt='已有 hosts 精确域名（0 返回）' newPrompt='新 hosts IPv4/IPv6（单个字面地址，0 返回）'
            replaceFamilies=(hosts)
        elif [[ "${scenario}" == hosts-manage-* ]]; then
            replaceCase=${scenario#hosts-manage-}
            newPrompt='新 hosts IPv4/IPv6（单个字面地址，0 返回）'
            replaceFamilies=(hosts-add hosts-remove)
        fi
        case "${replaceCase}" in
        cancel)
            replaceVariants=(old-zero old-empty old-eof new-zero new-empty new-eof)
            ;;
        invalid)
            replaceVariants=(old-invalid new-invalid old-csv new-csv same)
            ;;
        esac
        for family in "${replaceFamilies[@]}"; do
            menuLabel='Docker 路由与出站' statusChoice=3
            case "${family}" in
            dns) choice=30 ;;
            direct) choice=31 ;;
            block) choice=32 ;;
            ips) choice=33 ;;
            socks5) choice=36 ;;
            hosts) choice=37 ;;
            hosts-add)
                choice=38 replaceKind=hosts-add oldPrompt='新增 hosts 精确域名（0 返回）'
                [[ "${replaceCase}" != invalid ]] ||
                    replaceVariants=(old-invalid new-invalid old-csv new-csv)
                ;;
            hosts-remove)
                choice=39 replaceKind=hosts-remove oldPrompt='删除 hosts 精确域名（最后一项关闭 hosts，0 返回）'
                [[ "${replaceCase}" != cancel ]] ||
                    replaceVariants=(old-zero old-empty old-eof)
                [[ "${replaceCase}" != invalid ]] ||
                    replaceVariants=(old-invalid old-csv)
                ;;
            ipv6)
                targetReply 'Docker 路由与出站' $'19\n'
                menuLabel='Docker IPv6 域名出站' choice=7 statusChoice=4
                ;;
            warp)
                targetReply 'Docker 路由与出站' $'20\n'
                menuLabel='Docker WARP 出站' choice=10
                ;;
            region)
                targetReply 'Docker 路由与出站' $'18\n'
                menuLabel='Docker 区域阻断策略' choice=7 statusChoice=8
                ;;
            esac
            for variant in "${replaceVariants[@]}"; do
                oldRule=full:Exact.Example.Com newRule=full:Next.Example.NET
                [[ "${family}" != ips ]] || { oldRule=2001:0DB8::1/64; newRule=2001:db8::2/64; }
                [[ "${family}" != hosts* ]] || { oldRule=Exact.Example.Com; newRule=2001:0DB8::10; }
                case "${variant}" in
                old-zero) oldRule=0 ;;
                old-empty) oldRule= ;;
                old-eof) oldRule=$'\004' ;;
                new-zero) newRule=0 ;;
                new-empty) newRule= ;;
                new-eof) newRule=$'\004' ;;
                old-invalid) oldRule=regexp:bad ;;
                new-invalid) newRule=regexp:bad ;;
                old-csv) oldRule=full:Exact.Example.Com,full:Second.Example.Com ;;
                new-csv) newRule=full:Next.Example.NET,full:Second.Example.Com ;;
                same) newRule=${oldRule} ;;
                esac
                targetReply "${menuLabel}" "${choice}"$'\n'
                [[ "${replaceCase}" != status-failed ]] || continue
                input=${oldRule}$'\n'
                [[ "${variant}" != old-eof ]] || input=${oldRule}
                targetReply "${oldPrompt}" "${input}"
                [[ "${variant}" != old-* || "${replaceCase}" != cancel ]] || continue
                if [[ "${family}" != hosts-remove ]]; then
                    input=${newRule}$'\n'
                    [[ "${variant}" != new-eof ]] || input=${newRule}
                    targetReply "${newPrompt}" "${input}"
                fi
                case "${replaceCase}" in
                flow|commit-failed)
                    targetReply "fixture-${replaceKind}-replace-confirm [y/N]" $'y\n'
                    ;;
                confirm-cancel)
                    targetReply "fixture-${replaceKind}-replace-confirm [y/N]" $'n\n'
                    ;;
                confirm-eof)
                    targetReply "fixture-${replaceKind}-replace-confirm [y/N]" $'\004'
                    ;;
                esac
            done
            targetReply "${menuLabel}" "${statusChoice}"$'\n'
            [[ "${family}" != ipv6 && "${family}" != warp && "${family}" != region ]] ||
                targetReply "${menuLabel}" $'0\n'
        done
        ;;
    socks5-domains-eof|socks5-domains-status-failed)
        for choice in 34 35; do
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            [[ "${scenario}" != socks5-domains-status-failed ]] || continue
            inputPrompt='追加 SOCKS5 域名规则 CSV'
            [[ "${choice}" != 35 ]] || inputPrompt='精确删除 SOCKS5 域名规则 CSV'
            targetReply "${inputPrompt}" $'\004'
        done
        ;;
    selective-domains-invalid|selective-domains-state-failed|selective-domains-confirm-cancel|selective-domains-confirm-eof|selective-domains-commit-failed)
        for family in ipv6 warp socks5; do
            if [[ "${family}" == ipv6 ]]; then
                targetReply 'Docker 路由与出站' $'19\n'
                menuLabel='Docker IPv6 域名出站' familyLabel=IPv6
                addChoice=5 removeChoice=6 statusChoice=4
            elif [[ "${family}" == warp ]]; then
                targetReply 'Docker 路由与出站' $'20\n'
                menuLabel='Docker WARP 出站' familyLabel=WARP
                addChoice=8 removeChoice=9 statusChoice=3
            else
                menuLabel='Docker 路由与出站' familyLabel=SOCKS5
                addChoice=34 removeChoice=35 statusChoice=3
            fi
            for choice in "${addChoice}" "${removeChoice}"; do
                input=Example.NET
                [[ "${scenario}" != selective-domains-invalid ]] || input=regexp:bad
                inputPrompt="追加 ${familyLabel} 域名规则 CSV"
                [[ "${choice}" == "${addChoice}" ]] ||
                    inputPrompt="精确删除 ${familyLabel} 域名规则 CSV"
                targetReply "${menuLabel}" "${choice}"$'\n'
                targetReply "${inputPrompt}" "${input}"$'\n'
                case "${scenario}" in
                selective-domains-confirm-cancel)
                    targetReply "fixture-${family}-daily-confirm [y/N]" $'n\n'
                    ;;
                selective-domains-confirm-eof)
                    targetReply "fixture-${family}-daily-confirm [y/N]" $'\004'
                    ;;
                selective-domains-commit-failed)
                    targetReply "fixture-${family}-daily-confirm [y/N]" $'y\n'
                    ;;
                esac
            done
            targetReply "${menuLabel}" "${statusChoice}"$'\n'
            [[ "${family}" == socks5 ]] || targetReply "${menuLabel}" $'0\n'
        done
        ;;
    warp-confirm-cancel|warp-confirm-eof)
        targetReply 'Docker 路由与出站' $'20\n'
        for choice in 4 5 6; do
            targetReply 'Docker WARP 出站' "${choice}"$'\n'
            if [[ "${choice}" == 4 ]]; then
                targetReply 'WARP 域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET\n'
            fi
            if [[ "${scenario}" == warp-confirm-cancel ]]; then
                targetReply 'fixture-warp-daily-confirm [y/N]' $'n\n'
            else
                targetReply 'fixture-warp-daily-confirm [y/N]' $'\004'
            fi
        done
        targetReply 'Docker WARP 出站' $'3\n'
        targetReply 'Docker WARP 出站' $'0\n'
        ;;
    http-relay-flow|http-relay-cancel|http-relay-status-failed|http-relay-commit-failed)
        targetReply 'Docker 路由与出站' $'21\n'
        if [[ "${scenario}" == http-relay-cancel ]]; then
            for input in 0 '' n; do
                targetReply 'Docker HTTP 中继入站' $'1\n'
                targetReply 'fixture-http-relay-input-confirm [y/N]' "${input}"$'\n'
            done
        else
            targetReply 'Docker HTTP 中继入站' $'1\n'
            [[ "${scenario}" == http-relay-status-failed ]] ||
                targetReply 'fixture-http-relay-input-confirm [y/N]' $'y\n'
        fi
        for choice in 4 5 6 7; do
            inputPrompt='HTTP 中继来源 IP/CIDR CSV（精确字面规则，0 返回）'
            [[ "${choice}" != 4 ]] || inputPrompt='新 HTTP 中继端口（1–65535，0 返回）'
            if [[ "${scenario}" == http-relay-cancel ]]; then
                for input in $'0\n' $'\n' $'\004'; do
                    targetReply 'Docker HTTP 中继入站' "${choice}"$'\n'
                    targetReply "${inputPrompt}" "${input}"
                done
                continue
            fi
            targetReply 'Docker HTTP 中继入站' "${choice}"$'\n'
            [[ "${scenario}" != http-relay-status-failed ]] || continue
            input='192.0.2.11, 2001:0DB8::/64'
            [[ "${choice}" != 4 ]] || input=18888
            targetReply "${inputPrompt}" "${input}"$'\n'
            targetReply 'fixture-http-relay-confirm [y/N]' $'y\n'
        done
        if [[ "${scenario}" == http-relay-cancel ]]; then
            targetReply 'Docker HTTP 中继入站' $'4\n'
            targetReply '新 HTTP 中继端口（1–65535，0 返回）' $'18888\n'
            targetReply 'fixture-http-relay-confirm [y/N]' $'n\n'
            targetReply 'Docker HTTP 中继入站' $'5\n'
            targetReply 'HTTP 中继来源 IP/CIDR CSV（精确字面规则，0 返回）' $'192.0.2.11, 2001:0DB8::/64\n'
            targetReply 'fixture-http-relay-confirm [y/N]' $'\004'
        fi
        targetReply 'Docker HTTP 中继入站' $'3\n'
        targetReply 'Docker HTTP 中继入站' $'0\n'
        ;;
    http-relay-eof)
        targetReply 'Docker 路由与出站' $'21\n'
        targetReply 'Docker HTTP 中继入站' $'1\n'
        targetReply 'fixture-http-relay-input-confirm [y/N]' $'\004'
        targetReply 'Docker HTTP 中继入站' $'3\n'
        targetReply 'Docker HTTP 中继入站' $'0\n'
        ;;
    block-ips-mode-flow|block-ips-mode-failed)
        for choice in 45 46; do
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            targetReply 'fixture-block-ips-mode-confirm [y/N]' $'y\n'
        done
        targetReply 'Docker 路由与出站' $'3\n'
        ;;
    tun-flow|tun-cancel|tun-status-failed|tun-commit-failed)
        targetReply 'Docker 路由与出站' $'44\n'
        if [[ "${scenario}" == tun-status-failed ]]; then
            targetReply 'Docker TUN 管理' $'1\n'
        else
            targetReply 'Docker TUN 管理' $'1\n'
            for choice in 2 3; do
                if [[ "${scenario}" == tun-cancel ]]; then
                    for input in $'n\n' $'\004'; do
                        targetReply 'Docker TUN 管理' "${choice}"$'\n'
                        targetReply 'fixture-tun-confirm [y/N]' "${input}"
                    done
                else
                    targetReply 'Docker TUN 管理' "${choice}"$'\n'
                    targetReply 'fixture-tun-confirm [y/N]' $'y\n'
                fi
            done
            targetReply 'Docker TUN 管理' $'1\n'
        fi
        targetReply 'Docker TUN 管理' $'0\n'
        ;;
    tproxy-flow|tproxy-cancel|tproxy-status-failed|tproxy-commit-failed|tproxy-output-flow|tproxy-output-cancel|tproxy-output-failed)
        targetReply 'Docker 路由与出站' $'43\n'
        if [[ "${scenario}" == tproxy-output-* ]]; then
            if [[ "${scenario}" == tproxy-output-cancel ]]; then
                for input in $'\n' $'0\n' $'\004'; do
                    targetReply 'Docker TProxy 管理' $'5\n'
                    targetReply '本机转发 UID（1–2147483647，排除 10001；0 返回）' "${input}"
                done
            else
                targetReply 'Docker TProxy 管理' $'5\n'
                targetReply '本机转发 UID（1–2147483647，排除 10001；0 返回）' $'65534\n'
                targetReply 'fixture-tproxy-confirm [y/N]' $'y\n'
                targetReply 'Docker TProxy 管理' $'6\n'
                targetReply 'fixture-tproxy-confirm [y/N]' $'y\n'
            fi
        elif [[ "${scenario}" == tproxy-status-failed ]]; then
            for choice in 1 2 3 5 6 1; do
                targetReply 'Docker TProxy 管理' "${choice}"$'\n'
            done
        elif [[ "${scenario}" == tproxy-cancel ]]; then
            for choice in 2 3; do
                inputPrompt='TProxy 端口 [31298，0 返回]'
                newPrompt='TProxy mark [129，0 返回]'
                familyPrompt='TProxy 地址族 ipv4/ipv6/dual [ipv4，0 返回]'
                [[ "${choice}" != 3 ]] ||
                    { inputPrompt='TProxy 端口 [31399，0 返回]'; newPrompt='TProxy mark [257，0 返回]';
                      familyPrompt='TProxy 地址族 ipv4/ipv6/dual [dual，0 返回]'; }
                for input in $'0\n' $'\004'; do
                    targetReply 'Docker TProxy 管理' "${choice}"$'\n'
                    targetReply "${inputPrompt}" "${input}"
                done
                for input in $'0\n' $'\004'; do
                    targetReply 'Docker TProxy 管理' "${choice}"$'\n'
                    targetReply "${inputPrompt}" $'\n'
                    targetReply "${newPrompt}" "${input}"
                done
                for input in $'0\n' $'\004'; do
                    targetReply 'Docker TProxy 管理' "${choice}"$'\n'
                    targetReply "${inputPrompt}" $'\n'
                    targetReply "${newPrompt}" $'\n'
                    targetReply "${familyPrompt}" "${input}"
                done
            done
            for choice in 2 3; do
                targetReply 'Docker TProxy 管理' "${choice}"$'\n'
                inputPrompt='TProxy 端口 [31298，0 返回]'
                newPrompt='TProxy mark [129，0 返回]'
                familyPrompt='TProxy 地址族 ipv4/ipv6/dual [ipv4，0 返回]'
                [[ "${choice}" != 3 ]] ||
                    { inputPrompt='TProxy 端口 [31399，0 返回]'; newPrompt='TProxy mark [257，0 返回]';
                      familyPrompt='TProxy 地址族 ipv4/ipv6/dual [dual，0 返回]'; }
                targetReply "${inputPrompt}" $'\n'
                targetReply "${newPrompt}" $'\n'
                targetReply "${familyPrompt}" $'\n'
                input=$'n\n'
                [[ "${choice}" != 3 ]] || input=$'\004'
                targetReply 'fixture-tproxy-confirm [y/N]' "${input}"
            done
            for input in $'n\n' $'\004'; do
                targetReply 'Docker TProxy 管理' $'4\n'
                targetReply 'fixture-tproxy-confirm [y/N]' "${input}"
            done
            targetReply 'Docker TProxy 管理' $'1\n'
        else
            targetReply 'Docker TProxy 管理' $'1\n'
            targetReply 'Docker TProxy 管理' $'2\n'
            targetReply 'TProxy 端口 [31298，0 返回]' $'\n'
            targetReply 'TProxy mark [129，0 返回]' $'\n'
            targetReply 'TProxy 地址族 ipv4/ipv6/dual [ipv4，0 返回]' $'ipv6\n'
            targetReply 'fixture-tproxy-confirm [y/N]' $'y\n'
            for input in '' 32000; do
                targetReply 'Docker TProxy 管理' $'3\n'
                newRule=
                [[ -z "${input}" ]] || newRule=130
                targetReply 'TProxy 端口 [31399，0 返回]' "${input}"$'\n'
                targetReply 'TProxy mark [257，0 返回]' "${newRule}"$'\n'
                newFamily=
                [[ -z "${input}" ]] || newFamily=ipv4
                targetReply 'TProxy 地址族 ipv4/ipv6/dual [dual，0 返回]' "${newFamily}"$'\n'
                targetReply 'fixture-tproxy-confirm [y/N]' $'y\n'
            done
            targetReply 'Docker TProxy 管理' $'4\n'
            targetReply 'fixture-tproxy-confirm [y/N]' $'y\n'
            targetReply 'Docker TProxy 管理' $'1\n'
        fi
        targetReply 'Docker TProxy 管理' $'0\n'
        ;;
    esac
    targetReply 'Docker 路由与出站' $'0\n'
    targetReply 'Docker 管理菜单' $'0\n'
}

runProtocolManagementDriver() {
    local scenario=$1 action reply
    local -A targetPrompts=()
    targetReply 'Docker 管理菜单' $'9\n'
    if [[ "${scenario}" == flow ]]; then
        targetReply 'Docker 协议与入口' $'14\n'
        targetReply '源入口 ID（沿用账号、地址；0 返回）' $'0\n'
        targetReply 'Docker 协议与入口' $'14\n'
        targetReply '源入口 ID（沿用账号、地址；0 返回）' $'entry-fixture\n'
        targetReply '目标核心 [1=Xray，2=sing-box，空输入沿用源核心，0 返回]' $'0\n'
        targetReply 'Docker 协议与入口' $'14\n'
        targetReply '源入口 ID（沿用账号、地址；0 返回）' $'entry-fixture\n'
        targetReply '目标核心 [1=Xray，2=sing-box，空输入沿用源核心，0 返回]' $'\n'
        targetReply '目标协议 ID（0 返回）' $'0\n'
        targetReply 'Docker 协议与入口' $'14\n'
        targetReply '源入口 ID（沿用账号、地址；0 返回）' $'entry-fixture\n'
        targetReply '目标核心 [1=Xray，2=sing-box，空输入沿用源核心，0 返回]' $'\n'
        targetReply '目标协议 ID（0 返回）' $'31\n'
        targetReply '新公开端口（0 返回）' $'0\n'
        for action in 15 16 17; do
            targetReply 'Docker 协议与入口' "${action}"$'\n'
            targetReply '入口 ID（0 返回）' $'0\n'
        done
        for action in 0 eof; do
            reply=$'0\n'
            [[ "${action}" != eof ]] || reply=$'\004'
            targetReply 'Docker 协议与入口' $'17\n'
            targetReply '入口 ID（0 返回）' $'entry-fixture\n'
            targetReply '核心后端端口（0 返回）' "${reply}"
            targetReply 'Docker 协议与入口' $'17\n'
            targetReply '入口 ID（0 返回）' $'entry-fixture\n'
            targetReply '核心后端端口（0 返回）' $'31350\n'
            targetReply 'Nginx TLS 内部端口（0 返回）' "${reply}"
        done
        targetReply 'Docker 协议与入口' $'17\n'
        targetReply '入口 ID（0 返回）' $'\004'
    fi
    for action in 14 15 16 17; do
        targetReply 'Docker 协议与入口' "${action}"$'\n'
        [[ "${scenario}" != status-failed ]] || continue
        if [[ "${action}" == 14 ]]; then
            targetReply '源入口 ID（沿用账号、地址；0 返回）' $'entry-fixture\n'
            targetReply '目标核心 [1=Xray，2=sing-box，空输入沿用源核心，0 返回]' $'\n'
            targetReply '目标协议 ID（0 返回）' $'31\n'
            targetReply '新公开端口（0 返回）' $'30443\n'
        else
            targetReply '入口 ID（0 返回）' $'entry-fixture\n'
            if [[ "${action}" == 17 ]]; then
                targetReply '核心后端端口（0 返回）' $'31350\n'
                targetReply 'Nginx TLS 内部端口（0 返回）' $'8650\n'
            fi
        fi
    done
    if [[ "${scenario}" != status-failed ]]; then
        for action in 1 2; do
            targetReply 'Docker 协议与入口' $'14\n'
            targetReply '源入口 ID（沿用账号、地址；0 返回）' $'entry-fixture\n'
            targetReply '目标核心 [1=Xray，2=sing-box，空输入沿用源核心，0 返回]' "${action}"$'\n'
            targetReply '目标协议 ID（0 返回）' "$([[ "${action}" == 1 ]] && printf 28 || printf 30)"$'\n'
            targetReply '新公开端口（0 返回）' $'30443\n'
        done
    fi
    targetReply 'Docker 协议与入口' $'0\n'
    targetReply 'Docker 管理菜单' $'0\n'
}

runInstallDriver() {
    local scenario=$1
    local -A targetPrompts=()
    targetReply 'Docker 管理菜单' $'2\n'
    case "${scenario}" in
    eof) targetReply 'Docker 安装与重装' $'\004' ;;
    path-eof)
        targetReply 'Docker 安装与重装' $'3\n'
        targetReply '完整规格文件绝对路径（0 返回）' $'\004'
        targetReply 'Docker 安装与重装' $'0\n'
        ;;
    cancel) targetReply 'Docker 安装与重装' $'0\n' ;;
    *)
        targetReply 'Docker 安装与重装' $'3\n'
        targetReply '完整规格文件绝对路径（0 返回）' $'0\n'
        targetReply 'Docker 安装与重装' $'3\n'
        targetReply '完整规格文件绝对路径（0 返回）' "${REINSTALL_MENU_SPEC}"$'\n'
        targetReply 'Docker 安装与重装' $'2\n'
        targetReply 'Docker 安装与重装' $'1\n'
        targetReply 'Docker 安装与重装' $'0\n'
        ;;
    esac
    targetReply 'Docker 管理菜单' $'1\n'
    targetReply 'Docker 管理菜单' $'0\n'
}

runPty() {
    local name=$1 driver=$2 input=$3 entry=$4 actual=0 feederStatus=0 command pipe feeder
    local expected=0
    shift 4
    CONTROL_LOG="${TEST_ROOT}/${name}.log"
    pipe="${TEST_ROOT}/${name}.input"
    mkfifo "${pipe}"
    printf -v command '%q ' bash -u "${entry}" "$@"
    if [[ "${driver}" == term ||
        ( ( "${driver}" == targets || "${driver}" == geo ) && "${input}" == term ) ||
        ( "${driver}" == maintenance &&
          ( "${input}" == fail2ban-term || "${input}" == fail2ban-*-term ) ) ]]; then
        printf -v command 'printf "%%s\\n" "$$" >%q; exec %s' "${TEST_ROOT}/menu.pid" "${command}"
        expected=143
    fi
    (
        exec 3>"${pipe}"
        local -A targetPrompts=()
        local -a menuParents=()
        if [[ "${driver}" != plain ]]; then
            waitForText 'Docker 管理菜单' "${CONTROL_LOG}" || exit 1
            # 等待输入时现场检查，避免只验证退出后的清理。
            [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || exit 2
        fi
        if [[ "${driver}" == source-input ]]; then
            waitForText 'fixture-source-input: ' "${CONTROL_LOG}" || exit 11
            printf '%s\n' "${input}" >&3
        elif [[ "${driver}" == setup ]]; then
            targetMainReply $'2\n'
            waitForText 'Docker 安装与重装' "${CONTROL_LOG}" || exit 11
            printf '1\n' >&3
            waitForText '核心 [1=Xray, 2=sing-box, 3=Xray+sing-box, 4=sing-box+Xray, 0=取消]' "${CONTROL_LOG}" || exit 11
            printf '0\n' >&3
            waitForText 'Docker 安装与重装' "${CONTROL_LOG}" 2 || exit 12
            printf '0\n' >&3
            waitForText 'Docker 管理菜单' "${CONTROL_LOG}" 2 || exit 12
            printf '0\n' >&3
        elif [[ "${driver}" == install ]]; then
            runInstallDriver "${input}"
        elif [[ "${driver}" == tls ]]; then
            targetMainReply $'8\n'
            waitForText 'Docker 证书管理' "${CONTROL_LOG}" || exit 13
            [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || exit 14
            if [[ "${input}" == eof ]]; then
                printf '2\n\ncertificate.pem\n' >&3
                waitForText '私钥文件' "${CONTROL_LOG}" || exit 15
                printf '\004' >&3
            elif [[ "${input}" == renewal-eof ]]; then
                printf '6\n\nadmin@example.com\n1\ndns_cf\n' >&3
                waitForText 'DNS 凭据文件' "${CONTROL_LOG}" || exit 17
                printf '\004' >&3
            elif [[ "${input}" == standalone-eof || "${input}" == alpn-eof ]]; then
                method=2
                [[ "${input}" != alpn-eof ]] || method=4
                printf '3\n\nadmin@example.com\n%s\n' "${method}" >&3
                waitForText '确认执行证书操作？[y/N]' "${CONTROL_LOG}" || exit 17
                printf '\004' >&3
            elif [[ "${input}" == method-eof ]]; then
                printf '3\n\nadmin@example.com\n' >&3
                waitForText '验证方式 [1=DNS-01' "${CONTROL_LOG}" || exit 17
                printf '\004' >&3
            elif [[ "${input}" == offer-eof ]]; then
                printf '3\n\nadmin@example.com\n1\ndns_cf\ncredentials.env\ny\n' >&3
                waitForText '为该 ACME 证书启用自动续期？[y/N]' "${CONTROL_LOG}" || exit 17
                printf '\004' >&3
            elif [[ "${input}" == migrate-source-eof ]]; then
                printf '10\nother.example.com\n' >&3
                waitForText '证书 [1=已有受管' "${CONTROL_LOG}" || exit 17
                printf '\004' >&3
            elif [[ "${input}" == migrate-final-eof ]]; then
                printf '10\nother.example.com\n1\n' >&3
                waitForText 'fixture-tls-migrate-confirm [y/N]' "${CONTROL_LOG}" || exit 17
                printf '\004' >&3
            else
                printf '%s' "${input}" >&3
            fi
            targetMainReply $'0\n'
        elif [[ "${driver}" == protocols ]]; then
            targetMainReply $'9\n'
            waitForText 'Docker 协议与入口' "${CONTROL_LOG}" || exit 18
            [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || exit 19
            printf '2\n' >&3
            waitForText '入口 ID（空输入查看全部，0 返回）' "${CONTROL_LOG}" || exit 20
            if [[ "${input}" == cancel ]]; then
                printf '0\n' >&3
            else
                printf 'entry-fixture\n' >&3
            fi
            waitForText 'Docker 协议与入口' "${CONTROL_LOG}" 2 || exit 21
            if [[ "${input}" != cancel ]]; then
                printf '3\n' >&3
                waitForText 'Docker 协议与入口' "${CONTROL_LOG}" 3 || exit 22
            fi
            printf '4\n' >&3
            waitForText 'Reality 入口 ID（0 返回）' "${CONTROL_LOG}" || exit 24
            if [[ "${input}" == cancel ]]; then
                printf '0\n' >&3
            else
                printf 'entry-fixture\n' >&3
            fi
            waitForText 'Docker 协议与入口' "${CONTROL_LOG}" "$([[ "${input}" == cancel ]] && printf 3 || printf 4)" || exit 25
            [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || exit 23
            printf '0\n' >&3
            targetMainReply $'1\n'
            targetMainReply $'0\n'
        elif [[ "${driver}" == protocol-management ]]; then
            runProtocolManagementDriver "${input}"
        elif [[ "${driver}" == targets ]]; then
            runTargetsDriver "${input}"
        elif [[ "${driver}" == geo ]]; then
            runGeoDriver "${input}"
        elif [[ "${driver}" == port-alias ]]; then
            runPortAliasDriver "${input}"
        elif [[ "${driver}" == cdn ]]; then
            runCdnDriver "${input}"
        elif [[ "${driver}" == xhttp ]]; then
            runXhttpDriver "${input}"
        elif [[ "${driver}" == hy2 || "${driver}" == tuic ]]; then
            runUdpManagementDriver "${driver}" "${input}"
        elif [[ "${driver}" == maintenance ]]; then
            runMaintenanceDriver "${input}"
        elif [[ "${driver}" == control ]]; then
            runControlDriver "${input}"
        elif [[ "${driver}" == sites ]]; then
            runSitesDriver "${input}"
        elif [[ "${driver}" == routing ]]; then
            runRoutingDriver "${input}"
        elif [[ "${driver}" == traffic ]]; then
            runTrafficDriver "${input}"
        elif [[ "${driver}" == subscriptions ]]; then
            runSubscriptionsDriver "${input}"
        elif [[ "${driver}" == accounts ]]; then
            local accountMenuCount=1
            targetMainReply $'10\n'
            waitForText 'Docker 账号管理' "${CONTROL_LOG}" "${accountMenuCount}" || exit 26
            printf '1\n' >&3
            accountMenuCount=$((accountMenuCount + 1))
            waitForText 'Docker 账号管理' "${CONTROL_LOG}" "${accountMenuCount}" || exit 28
            printf '2\nBob\nentry-reality\nn\n' >&3
            accountMenuCount=$((accountMenuCount + 1))
            waitForText 'Docker 账号管理' "${CONTROL_LOG}" "${accountMenuCount}" || exit 28
            printf '3\n' >&3
            waitForText '账号 ID（0 返回）' "${CONTROL_LOG}" || exit 27
            printf 'alpha\nAlpha-Edited\nentry-reality\n' >&3
            accountMenuCount=$((accountMenuCount + 1))
            waitForText 'Docker 账号管理' "${CONTROL_LOG}" "${accountMenuCount}" || exit 28
            printf '4\n' >&3
            waitForText '账号 ID（0 返回）' "${CONTROL_LOG}" || exit 27
            printf 'alpha\nAlpha-Copy\n' >&3
            accountMenuCount=$((accountMenuCount + 1))
            waitForText 'Docker 账号管理' "${CONTROL_LOG}" "${accountMenuCount}" || exit 28
            for accountChoice in 5 6; do
                printf '%s\n' "${accountChoice}" >&3
                waitForText '账号 ID（0 返回）' "${CONTROL_LOG}" || exit 27
                printf 'alpha\n' >&3
                accountMenuCount=$((accountMenuCount + 1))
                waitForText 'Docker 账号管理' "${CONTROL_LOG}" "${accountMenuCount}" || exit 28
            done
            for accountChoice in 7 8; do
                printf '%s\n' "${accountChoice}" >&3
                waitForText '账号 ID（0 返回）' "${CONTROL_LOG}" || exit 27
                printf 'alpha\ny\n' >&3
                accountMenuCount=$((accountMenuCount + 1))
                waitForText 'Docker 账号管理' "${CONTROL_LOG}" "${accountMenuCount}" || exit 28
            done
            printf '0\n' >&3
            targetMainReply $'0\n'
        elif [[ "${driver}" == logs || "${driver}" == term ]]; then
            targetMainReply $'6\n'
            waitForText 'mock-log-ready' "${CONTROL_LOG}" || exit 3
            # 跟随日志期间也允许独立状态与定时采集争取部署锁。
            [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || exit 4
            if [[ "${driver}" == term ]]; then
                kill -TERM "$(<"${TEST_ROOT}/menu.pid")" || exit 9
                for ((attempt = 0; attempt < 100; attempt++)); do
                    kill -0 "$(<"${TEST_ROOT}/menu.pid")" 2>/dev/null || exit 0
                    sleep 0.05
                done
                exit 10
            fi
            timeout 60 bash -u "${entry}" status >"${TEST_ROOT}/logs-concurrent-status.log" 2>&1 || exit 5
            printf '\003' >&3
            [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || exit 7
            targetMainReply $'1\n'
            targetMainReply $'0\n'
        elif [[ "${driver}" != plain && "${input}" == $'\004' ]]; then
            printf '\004' >&3
        elif [[ "${driver}" != plain ]]; then
            local line
            while IFS= read -r line || [[ -n "${line}" ]]; do
                targetMainReply "${line}"$'\n'
                [[ "${line}" != 0 ]] || break
            done <<<"${input}"
        else
            printf '%s' "${input}" >&3
        fi
    ) &
    feeder=$!
    timeout 120 script -q -e -E never -f -c "${command}" "${CONTROL_LOG}" \
        <"${pipe}" >"${TEST_ROOT}/${name}.stdout" 2>&1 || actual=$?
    wait "${feeder}" || feederStatus=$?
    [[ "${feederStatus}" -eq 0 ]] || fail "${name}: PTY driver failed at checkpoint ${feederStatus}"
    [[ "${actual}" -eq "${expected}" ]] || fail "${name}: expected rc=${expected}, got rc=${actual}"
    ! grep -Fq 'unbound variable' "${CONTROL_LOG}" || fail "${name}: menu or fixture used an unset variable"
    assertNoLock
    if [[ "${driver}" == logs || "${driver}" == term ]]; then
        ! kill -0 "$(<"${FAKE_LOG_PID}")" 2>/dev/null || fail "${name}: log process survived the menu action"
    fi
}

assertMenu() {
    grep -Fq "${MAIN_MENU_TITLE}" "${CONTROL_LOG}" || fail 'PTY did not enter the menu'
}

assertHelpOnly() {
    grep -Fq '用法:' "${CONTROL_LOG}" || fail 'non-TTY invocation did not show usage'
    ! grep -Fq "${MAIN_MENU_TITLE}" "${CONTROL_LOG}" || fail 'non-TTY invocation entered the menu'
    [[ ! -e "${DOWNLOAD_MARKER}" ]] || fail 'help invocation attempted a module download'
    [[ ! -s "${DOCKER_LOG}" ]] || fail 'help invocation touched Docker'
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}" ]] || fail 'help invocation initialized deployment state'
}

export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/usr-local-bin"
if [[ "${MENU_SCOPE}" == full ]]; then
# 两个禁色开关分别生效，普通模式仍保留颜色。
(
    unset PADM_NO_COLOR NO_COLOR
    source "${PROJECT_ROOT}/docker/lib/menu.sh"
    [[ "$(uiStyle title marker)" == *$'\033['* ]] || fail '默认 UI 样式没有颜色'
    for colorFlag in PADM_NO_COLOR NO_COLOR; do
        export "${colorFlag}=1"
        [[ "$(uiStyle title marker)" == marker &&
            "$(echoContent title marker)" == 'marker ' ]] || fail "${colorFlag} 未关闭颜色"
        unset "${colorFlag}"
    done
)

# 仅替换 CLI 边界，直接用新编号核对首页、原生返回项与受限入口。
MENU_UI_CLI="${TEST_ROOT}/menu-ui.sh"
export MENU_UI_PROJECT_ROOT="${PROJECT_ROOT}" MENU_UI_ACTIONS="${TEST_ROOT}/menu-ui.actions"
cat >"${MENU_UI_CLI}" <<'EOF'
#!/usr/bin/env bash
set -u
source "${MENU_UI_PROJECT_ROOT}/docker/lib/setup.sh"
source "${MENU_UI_PROJECT_ROOT}/docker/lib/menu.sh"
dockerMenuCli() { printf '%s\n' "$0"; }
dockerMenuRun() { printf '%s\n' "$*" >>"${MENU_UI_ACTIONS}"; }
dockerError() { printf '%s\n' "$*" >&2; }
PADM_DOCKER_RC_USAGE=2
dockerMenu
EOF
: >"${MENU_UI_ACTIONS}"
runPty ui-categories plain $'1\n0\n2\n6\n3\n8\n4\n3\n5\n4\n6\n3\nn\n0\n7\n5\n8\n3\n0\n' "${MENU_UI_CLI}"
for menuLabel in '1. 安装与重装' '2. 订阅与用户' '3. 协议与入口' '4. 站点与证书' \
    '5. 路由与访问控制' '6. 核心与服务' '7. 系统与脚本' '8. 高级/危险操作'; do
    grep -Fq "${menuLabel}" "${CONTROL_LOG}" || fail "首页缺少原生分类: ${menuLabel}"
done
grep -Fq '┌─ ' "${CONTROL_LOG}" && grep -Fq '└─' "${CONTROL_LOG}" ||
    fail '菜单未使用共享边框'
! grep -q $'\033' "${CONTROL_LOG}" || fail 'PADM_NO_COLOR 仍输出终端转义'
[[ "$(grep -Fc "${MAIN_MENU_TITLE}" "${CONTROL_LOG}")" -eq 9 ]] ||
    fail '原生分类返回项未逐次返回首页'
[[ "$(<"${MENU_UI_ACTIONS}")" == "$(printf 'status\n%.0s' {1..9})" ]] ||
    fail '首页重绘未逐次更新状态，或分类返回触发了业务命令'

: >"${MENU_UI_ACTIONS}"
runPty ui-socks5-unavailable plain $'5\n1\n3\n2\n4\n6\n4\n0\n' "${MENU_UI_CLI}"
grep -Fq 'SOCKS5 入站' "${CONTROL_LOG}" && grep -Fq '不可用' "${CONTROL_LOG}" ||
    fail 'SOCKS5 入站未说明受限原因'
[[ "$(grep -Fc '┌─ Socks5 中继' "${CONTROL_LOG}")" -eq 2 ]] ||
    fail '受限项未返回 Socks5 中继菜单'
[[ "$(grep -Fc "${MAIN_MENU_TITLE}" "${CONTROL_LOG}")" -eq 2 ]] ||
    fail 'Socks5 中继未逐层返回首页'
[[ "$(<"${MENU_UI_ACTIONS}")" == $'status\nstatus' ]] ||
    fail '受限 SOCKS5 入站触发业务命令'

: >"${MENU_UI_ACTIONS}"
runPty ui-maintenance-exit plain $'7\n1\n2\ny\n' "${MENU_UI_CLI}"
[[ "$(<"${MENU_UI_ACTIONS}")" == $'status\nupdate' ]] ||
    fail '系统维护更新没有正确派发'
[[ "$(grep -Fc "${MAIN_MENU_TITLE}" "${CONTROL_LOG}")" -eq 1 &&
    "$(grep -Fc '┌─ Docker 服务维护' "${CONTROL_LOG}")" -eq 1 ]] ||
    fail '系统维护成功后未退出整个旧菜单会话'

: >"${MENU_UI_ACTIONS}"
CONTROL_LOG="${TEST_ROOT}/ui-routing-scope.log"
(
    source "${PROJECT_ROOT}/docker/lib/menu.sh"
    dockerMenuRun() { printf '%s\n' "$*" >>"${MENU_UI_ACTIONS}"; }
    dockerMenuRouting socks5 <<< $'16\n3\n0\n'
) >"${CONTROL_LOG}"
grep -Fq '1. 启用 SOCKS5 出站' "${CONTROL_LOG}" &&
    ! grep -Fq '16. 启用 BT 协议阻断' "${CONTROL_LOG}" ||
    fail 'SOCKS5 出站菜单未限制显示范围'
grep -Fq '无效选项' "${CONTROL_LOG}" &&
    [[ "$(<"${MENU_UI_ACTIONS}")" == 'protocol routing-status' ]] ||
    fail 'SOCKS5 隐藏选项仍可执行，或拒绝后无法继续查看状态'

# 单文件入口没有模块；帮助必须在下载和安装之前返回。
ISOLATED="${TEST_ROOT}/isolated"
mkdir -p "${ISOLATED}"
cp "${PROJECT_ROOT}/install-docker.sh" "${ISOLATED}/install-docker.sh"
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/isolated-state"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/isolated-bin"
runNonTty 0 isolated-no-args "${ISOLATED}/install-docker.sh"
assertHelpOnly
runNonTty 2 isolated-explicit-menu "${ISOLATED}/install-docker.sh" menu
assertHelpOnly

SOURCE_ROOT="${TEST_ROOT}/source"
mkdir -p "${SOURCE_ROOT}/shell/core" "${SOURCE_ROOT}/docker"
cp "${PROJECT_ROOT}/install-docker.sh" "${SOURCE_ROOT}/install-docker.sh"
cp -R "${PROJECT_ROOT}/docker/lib" "${SOURCE_ROOT}/docker/lib"
cp -R "${PROJECT_ROOT}/docker/contracts" "${SOURCE_ROOT}/docker/contracts"
cp "${PROJECT_ROOT}/shell/core/deployment_mode.sh" "${SOURCE_ROOT}/shell/core/deployment_mode.sh"
cp "${PROJECT_ROOT}/shell/core/stats_grpc.sh" "${SOURCE_ROOT}/shell/core/stats_grpc.sh"
cp "${PROJECT_ROOT}/shell/core/"{runtime.sh,reality_targets.sh,cores.sh,static_site_renderer.sh,locale.sh} "${SOURCE_ROOT}/shell/core/"
mkdir -p "${SOURCE_ROOT}/assets"
cp -R "${PROJECT_ROOT}/assets/static-sites" "${SOURCE_ROOT}/assets/"
TEST_REF=1111111111111111111111111111111111111111

export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/non-tty-state"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/non-tty-bin"
runNonTty 0 non-tty-install "${PROJECT_ROOT}/install-docker.sh" \
    install --source "${SOURCE_ROOT}" --ref "${TEST_REF}"
[[ -f "${PADM_DOCKER_INSTALL_DIR}/mode" ]] || fail 'non-TTY install did not initialize the state'
! grep -Fq "${MAIN_MENU_TITLE}" "${CONTROL_LOG}" || fail 'non-TTY install entered the menu'
assertNoLock

export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/no-menu-state"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/no-menu-bin"
runPty install-no-menu plain $'\004' "${PROJECT_ROOT}/install-docker.sh" \
    install --source "${SOURCE_ROOT}" --ref "${TEST_REF}" --no-menu
[[ -f "${PADM_DOCKER_INSTALL_DIR}/mode" ]] || fail '--no-menu install did not initialize the state'
! grep -Fq "${MAIN_MENU_TITLE}" "${CONTROL_LOG}" || fail '--no-menu install entered the menu'

export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/usr-local-bin"
runPty install-auto-menu menu $'0\n' "${PROJECT_ROOT}/install-docker.sh" \
    install --source "${SOURCE_ROOT}" --ref "${TEST_REF}"
assertMenu
grep -Fq 'configured=no' "${CONTROL_LOG}" || fail 'menu homepage did not run status'
CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
[[ -L "${CLI}" ]] || fail 'installed CLI link is missing'

: >"${DOCKER_LOG}"
runNonTty 0 installed-no-args "${CLI}"
grep -Fq '用法:' "${CONTROL_LOG}" || fail 'installed non-TTY no-args did not show help'
[[ ! -s "${DOCKER_LOG}" ]] || fail 'installed non-TTY no-args touched Docker'
runNonTty 2 installed-explicit-menu "${CLI}" menu
grep -Fq '用法:' "${CONTROL_LOG}" || fail 'installed non-TTY menu did not show help'
[[ ! -s "${DOCKER_LOG}" ]] || fail 'installed non-TTY menu touched Docker'
runNonTty 0 installed-help "${CLI}" help
grep -Fq 'padm-docker fail2ban verify-source <WS 入口 ID> <外部客户端 IPv4/IPv6>' "${CONTROL_LOG}" ||
    fail 'Fail2ban 真实来源诊断缺少命令帮助'
grep -Fq 'padm-docker fail2ban ssh verify-unit <systemd service> <本机 IPv4/IPv6> <SSH 端口> <外部客户端 IPv4/IPv6>' "${CONTROL_LOG}" ||
    fail 'SSH unit 来源核验缺少命令帮助'
[[ ! -s "${DOCKER_LOG}" ]] || fail 'installed help touched Docker'
assertNoLock

runPty installed-no-args-menu menu $'1\n1\n0\n' "${CLI}"
assertMenu
[[ "$(grep -Fc 'configured=no' "${CONTROL_LOG}")" -ge 3 ]] || fail 'repeated status did not complete'

snapshotBefore=$(find "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" \
    "${PADM_DOCKER_INSTALL_DIR}/secrets" "${PADM_DOCKER_INSTALL_DIR}/backups" -type f -print)
runPty first-config-cancel setup '' "${CLI}" menu
grep -Fq 'Docker 首次配置' "${CONTROL_LOG}" || fail 'first-config action did not enter the wizard'
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/deployment.json" ]] || fail 'cancelled first-config action wrote a deployment'
snapshotAfter=$(find "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" \
    "${PADM_DOCKER_INSTALL_DIR}/secrets" "${PADM_DOCKER_INSTALL_DIR}/backups" -type f -print)
[[ "${snapshotBefore}" == "${snapshotAfter}" ]] || fail 'cancelled first-config action changed persistent files'

runPty tls-unconfigured menu $'8\n0\n' "${CLI}" menu
grep -Fq '请先使用首次配置' "${CONTROL_LOG}" || fail 'unconfigured TLS action did not direct the user to first configuration'
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/deployment.json" ]] || fail 'unconfigured TLS action wrote a deployment'
runPty protocols-unconfigured protocols cancel "${CLI}" menu
grep -Fq 'Docker 协议与入口' "${CONTROL_LOG}" || fail 'protocol submenu was not reachable'
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/deployment.json" ]] || fail 'unconfigured protocol menu wrote a deployment'
fi

# 隔离业务命令，只用真实 PTY 检查生产菜单的确认门禁与参数分发。
TLS_WIZARD_ROOT="${TEST_ROOT}/tls-wizard"
TLS_WIZARD_CLI="${TEST_ROOT}/tls-wizard-cli.sh"
TLS_WIZARD_ACTIONS="${TEST_ROOT}/tls-wizard.actions"
mkdir -p "${TLS_WIZARD_ROOT}/config"
printf '{"tls":{"domain":"ws.example.com"}}\n' >"${TLS_WIZARD_ROOT}/config/spec.json"
printf '{}\n' >"${TLS_WIZARD_ROOT}/deployment.json"
printf 'PADM_OPS_IMAGE=fixture\n' >"${TLS_WIZARD_ROOT}/images.env"
export TLS_WIZARD_ROOT TLS_WIZARD_CLI TLS_WIZARD_ACTIONS PROJECT_ROOT
cat >"${TLS_WIZARD_CLI}" <<'EOF'
#!/usr/bin/env bash
set -u
DOCKER_BUNDLE_SOURCE_ROOT="${PROJECT_ROOT}"
source "${PROJECT_ROOT}/docker/lib/services.sh"
source "${PROJECT_ROOT}/docker/lib/setup.sh"
source "${PROJECT_ROOT}/shell/core/locale.sh"
dockerError() { printf '%s\n' "$*" >&2; }
dockerInstallRoot() { printf '%s\n' "${TLS_WIZARD_ROOT}"; }
dockerDomainIsValid() { [[ "$1" == ws.example.com || "$1" == other.example.com ]]; }
dockerEmailIsValid() { [[ "$1" == admin@example.com ]]; }
dockerConfigureSpecValidate() { return 0; }
dockerConfigureSchemaFile() { printf '%s\n' "${PROJECT_ROOT}/docker/contracts/configure.schema.json"; }
dockerManagedSpecMatchesDeployment() { return 0; }
dockerResolveOpsImage() { printf 'fixture\n'; }
recordAction() {
    printf '%s' "$1" >>"${TLS_WIZARD_ACTIONS}"
    shift
    [[ "$#" -eq 0 ]] || printf ' %s' "$@" >>"${TLS_WIZARD_ACTIONS}"
    printf '\n' >>"${TLS_WIZARD_ACTIONS}"
}
dockerTlsValidateCommand() { recordAction validate "$@"; }
dockerTlsInstallCommand() { recordAction install "$@"; }
dockerAcmeCommand() { recordAction acme "$@"; return "${TLS_ACME_STATUS:-0}"; }
dockerRenewalCommand() { recordAction schedule "$@"; }
dockerRenewalChange() { recordAction renewal "$@"; return "${TLS_RENEWAL_STATUS:-0}"; }
dockerEditCommand() {
    if [[ "${1:-}" == --tls-migrate ]]; then
        [[ "${2:-}" == other.example.com ]] || return 2
        case "${3:-}" in
        --tls-existing) [[ "$#" -eq 3 ]] || return 2 ;;
        --tls-import) [[ "$#" -eq 5 && "$4" == 'certificate file.pem' && "$5" == 'private key.pem' ]] || return 2 ;;
        --tls-dns) [[ "$#" -eq 6 && "$4" == admin@example.com && "$5" == dns_cf && "$6" == credentials.env ]] || return 2 ;;
        --tls-standalone|--tls-webroot|--tls-alpn) [[ "$#" -eq 4 && "$4" == admin@example.com ]] || return 2 ;;
        *) return 2 ;;
        esac
        printf 'fixture-tls-migrate-confirm [y/N]: '
    else
        printf 'fixture-http01-confirm [y/N]: '
    fi
    IFS= read -r confirmation || return 0
    [[ "${confirmation}" == y ]] || return 0
    recordAction edit "$@"
    [[ "${1:-}" != --tls-migrate ]] || return "${TLS_MIGRATE_STATUS:-0}"
}
PADM_DOCKER_RC_STATE=15
PADM_DOCKER_RC_USAGE=2
if [[ "${SOURCE_INPUT_CHECK:-0}" == 1 && "${1:-}" != source-input-menu ]]; then
    recordAction "$@"
    [[ -t 0 ]] || exit 19
    printf 'fixture-source-input: '
    IFS= read -r sourceInput || exit 19
    recordAction source-input "${sourceInput}"
    exit 0
fi
case "${1:-}" in
source-input-menu)
    source "${PROJECT_ROOT}/docker/lib/menu.sh"
    dockerMenuCli() { printf '%s\n' "${TLS_WIZARD_CLI}"; }
    printf 'padm 管理面板（Docker）\n'
    shift
    dockerMenuRun "$@"
    ;;
status)
    [[ "${SITE_MENU_RECORD_STATUS:-0}" != 1 ]] || recordAction status
    exit 0
    ;;
setup|reinstall)
    recordAction "$@"
    if [[ "$1" == setup ]]; then
        [[ "$#" -eq 1 ]] || exit 2
    else
        [[ "$#" -eq 1 || ( "$#" -eq 3 && "$2" == --spec && "$3" == "${REINSTALL_MENU_SPEC}" ) ]] || exit 2
    fi
    exit "${INSTALL_MENU_STATUS:-0}"
    ;;
protocol)
    recordAction "$@"
    case "${2:-}" in
    list) [[ "${FAIL2BAN_PROTOCOL_LIST_STATUS:-0}" -eq 0 ]] || exit "${FAIL2BAN_PROTOCOL_LIST_STATUS}" ;;
    select-target|scan-targets|scan-targets-asn)
        printf 'fixture-target-input: %s: ' "$2"
        IFS= read -r targetInput || exit 19
        recordAction target-input "$2" "${targetInput}"
        ;;
    check-target)
        if [[ "${TARGET_CHECK_WAIT:-0}" == 1 ]]; then
            trap 'exit 130' INT
            trap 'exit 143' TERM
            printf '%s\n' "${BASHPID}" >"${TARGET_CHECK_PID:?}"
            printf 'fixture-target-check-ready\n'
            while :; do sleep 1; done
        fi
        exit "${TARGET_CHECK_STATUS:-0}"
        ;;
    alpn-status) exit "${SITE_ALPN_STATUS:-0}" ;;
    routing-status) exit "${ROUTING_STATUS:-0}" ;;
    tproxy-status)
        [[ "${TPROXY_STATUS:-0}" -eq 0 ]] || exit "${TPROXY_STATUS}"
        printf '{"enabled":true,"port":31399,"mark":257,"family":"dual","hook":"PREROUTING"}\n'
        exit 0
        ;;
    tun-status)
        [[ "${TUN_STATUS:-0}" -eq 0 ]] || exit "${TUN_STATUS}"
        printf '{"enabled":true,"interface":"padm-tun","address":"198.18.0.1/30","family":"ipv4","scope":"global","ipv6":"reject"}\n'
        exit 0
        ;;
    xhttp-status)
        [[ "${XHTTP_STATUS:-0}" -eq 0 ]] || exit "${XHTTP_STATUS}"
        if [[ "${XHTTP_STATUS_FIXTURE:-default}" == invalid ]]; then
            printf 'fixture-invalid-xhttp-status\n'
        else
            jq -cn --arg fixture "${XHTTP_STATUS_FIXTURE:-default}" '
                {entries:[{listener_id:"entry-xhttp",
                  xmux:{maxConcurrency:"16-32",hMaxRequestTimes:"600-900",hMaxReusableSecs:"1800-3000"},
                  xPaddingBytes:"100-1000",noGRPCHeader:false,noSSEHeader:false,
                  limits:{scMaxEachPostBytes:1000000,scMinPostsIntervalMs:30,
                    scMaxBufferedPosts:30,scStreamUpServerSecs:"20-80"},
                  mode:"auto",path:"/padm/path-1",host:"www.example.com"}]} |
                if $fixture == "current" then
                  .entries[0] |= (. + {
                    xmux:{maxConcurrency:"4-8",hMaxRequestTimes:0,hMaxReusableSecs:0},
                    xPaddingBytes:"17-19",noSSEHeader:true,
                    limits:{scMaxEachPostBytes:8192,scMinPostsIntervalMs:5,
                      scMaxBufferedPosts:7,scStreamUpServerSecs:"10-15"},
                    mode:"stream-up",path:"/current/path",host:"current.example.net"})
                elif $fixture == "incomplete" then del(.entries[0].xmux)
                else . end'
        fi
        exit 0
        ;;
    hy2-status|tuic-status) exit "${UDP_PROTOCOL_STATUS:-0}" ;;
    esac
    printf 'fixture-protocol-output\n'
    ;;
edit)
    recordAction "$@"
    if [[ "${2:-}" == --site-template ]]; then
        [[ "$#" -eq 3 || ( "$#" -eq 5 && "$4" == --site-title &&
            "$5" == $'中文 & <站点> "双引" \'单引\' | \\' ) ]] || exit 2
    elif [[ "${2:-}" == --socks5-input || "${2:-}" == --http-relay-input ||
        "${2:-}" == --warp-input || "${2:-}" == --hosts-input ]]; then
        # 菜单只核对无凭据参数分发及取消；实际录入由对应路由合同覆盖。
        [[ "$#" -eq 2 ]] || exit 2
        family=${2#--}
        printf 'fixture-%s-confirm [y/N]: ' "${family}"
        if ! IFS= read -r confirmation; then
            recordAction "${family}-confirm" eof
            exit 0
        fi
        recordAction "${family}-confirm" "${confirmation}"
        [[ "${confirmation}" == y ]] || exit 0
        [[ "${SITE_EDIT_STATUS:-0}" -eq 0 ]] || exit "${SITE_EDIT_STATUS}"
        recordAction "${family}-commit"
    elif [[ "${2:-}" == --protocol-add ]]; then
        [[ "$3" == entry-fixture && "$5" == 30443 ]] || exit 2
        if [[ "$#" -eq 5 ]]; then
            [[ "$4" == 31 ]] || exit 2
        else
            [[ "$#" -eq 7 && "$6" == --protocol-core &&
                ( "$4:$7" == 28:xray || "$4:$7" == 30:sing-box ) ]] || exit 2
        fi
    elif [[ "${2:-}" == --protocol-remove || "${2:-}" == --protocol-rebuild ]]; then
        [[ "$#" -eq 3 && "$3" == entry-fixture ]] || exit 2
    elif [[ "${2:-}" == --internal-ports ]]; then
        [[ "$#" -eq 5 && "$3" == entry-fixture && "$4" == 31350 && "$5" == 8650 ]] || exit 2
    elif [[ "${2:-}" == --fail2ban-port ]]; then
        [[ "$#" -eq 6 && "$3" == entry-fixture && "$4" != not-a-port &&
            "$5" == --confirm && "$6" == PADM-DOCKER-EDIT ]] || exit 2
        exit "${FAIL2BAN_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --access-control-off ]]; then
        [[ "$#" -eq 2 ]] || exit 2
        printf 'fixture-access-control-confirm [y/N]: '
        if ! IFS= read -r confirmation; then
            recordAction access-control-confirm eof
            exit 2
        fi
        recordAction access-control-confirm "${confirmation}"
        [[ "${confirmation}" == y ]] || exit 2
        [[ "${SITE_EDIT_STATUS:-0}" -eq 0 ]] || exit "${SITE_EDIT_STATUS}"
        recordAction access-control-commit
    elif [[ "${2:-}" == --http-relay-port || "${2:-}" == --http-relay-sources ||
        "${2:-}" == --http-relay-sources-add || "${2:-}" == --http-relay-sources-remove ]]; then
        # 只验证单个字段原样分发；地址校验、名单变换和事务由中继合同覆盖。
        [[ "$#" -eq 3 ]] || exit 2
        if [[ "$2" == --http-relay-port ]]; then
            [[ "$3" == 18888 ]] || exit 2
        else
            [[ "$3" == '192.0.2.11, 2001:0DB8::/64' ]] || exit 2
        fi
        printf 'fixture-http-relay-confirm [y/N]: '
        if ! IFS= read -r confirmation; then
            recordAction http-relay-confirm "$2" eof
            exit 2
        fi
        recordAction http-relay-confirm "$2" "${confirmation}"
        [[ "${confirmation}" == y ]] || exit 2
        [[ "${SITE_EDIT_STATUS:-0}" -eq 0 ]] || exit "${SITE_EDIT_STATUS}"
        recordAction http-relay-commit "$2"
    elif [[ "${2:-}" == --block-ips-resolve || "${2:-}" == --block-ips-literal ]]; then
        [[ "$#" -eq 2 ]] || exit 2
        printf 'fixture-block-ips-mode-confirm [y/N]: '
        IFS= read -r confirmation || exit 2
        recordAction block-ips-mode-confirm "$2" "${confirmation}"
        [[ "${confirmation}" == y ]] || exit 2
        [[ "${SITE_EDIT_STATUS:-0}" -eq 0 ]] || exit "${SITE_EDIT_STATUS}"
        recordAction block-ips-mode-commit "$2"
    elif [[ "${2:-}" == --tun-enable || "${2:-}" == --tun-off ]]; then
        # 固定配置只核对原样分发与一次确认；归属和事务恢复由 TUN 合同覆盖。
        [[ "$#" -eq 2 ]] || exit 2
        printf 'fixture-tun-confirm [y/N]: '
        if ! IFS= read -r confirmation; then
            recordAction tun-confirm "$2" eof
            exit 2
        fi
        recordAction tun-confirm "$2" "${confirmation}"
        [[ "${confirmation}" == y ]] || exit 2
        [[ "${SITE_EDIT_STATUS:-0}" -eq 0 ]] || exit "${SITE_EDIT_STATUS}"
        recordAction tun-commit "$2"
    elif [[ "${2:-}" == --tproxy-enable || "${2:-}" == --tproxy-settings || "${2:-}" == --tproxy-off ]]; then
        # 参数只断言菜单默认值与原样分发；内核规则和恢复由 TProxy 合同覆盖。
        case "$2" in
        --tproxy-enable)
            [[ "$#" -eq 6 && "$3" == 31298 && "$4" == 129 && "$5" == --tproxy-family &&
                ( "$6" == ipv4 || "$6" == ipv6 ) ]] || exit 2
            ;;
        --tproxy-settings)
            [[ "$5" == --tproxy-family &&
                ( ( "$3" == 31399 && "$4" == 257 && "$6" == dual ) ||
                  ( "$3" == 32000 && "$4" == 130 && "$6" == ipv4 ) ) ]] || exit 2
            [[ "$#" -eq 6 ||
                ( "$#" -eq 8 && "$7" == --tproxy-output-uid && "$8" == 65534 ) ||
                ( "$#" -eq 7 && "$7" == --tproxy-output-off ) ]] || exit 2
            ;;
        --tproxy-off) [[ "$#" -eq 2 ]] || exit 2 ;;
        esac
        printf 'fixture-tproxy-confirm [y/N]: '
        if ! IFS= read -r confirmation; then
            recordAction tproxy-confirm "$2" eof
            exit 2
        fi
        recordAction tproxy-confirm "$2" "${confirmation}"
        [[ "${confirmation}" == y ]] || exit 2
        [[ "${SITE_EDIT_STATUS:-0}" -eq 0 ]] || exit "${SITE_EDIT_STATUS}"
        recordAction tproxy-commit "$2"
    elif [[ "${2:-}" == --dns-upstream || "${2:-}" == --socks5-upstream ]]; then
        [[ "$#" -eq 4 ]] || exit 2
        if [[ "$2" == --dns-upstream ]]; then
            [[ "$3" == 2001:0DB8::53 && "$4" == 5353 ]] || exit 2
        else
            [[ "$3" == 203.0.113.108 && "$4" == 1088 ]] || exit 2
        fi
        printf 'fixture-upstream-confirm [y/N]: '
        IFS= read -r confirmation || exit 2
        recordAction upstream-confirm "$2" "${confirmation}"
        [[ "${confirmation}" == y ]] || exit 2
        [[ "${SITE_EDIT_STATUS:-0}" -eq 0 ]] || exit "${SITE_EDIT_STATUS}"
        recordAction upstream-commit "$2"
    elif [[ "${2:-}" == --block-ips-replace ||
        "${2:-}" == --dns-domains-replace || "${2:-}" == --direct-domains-replace ||
        "${2:-}" == --block-domains-replace || "${2:-}" == --warp-domains-replace ||
        "${2:-}" == --ipv6-domains-replace || "${2:-}" == --region-allow-replace ||
        "${2:-}" == --socks5-domains-replace || "${2:-}" == --hosts-replace ||
        "${2:-}" == --hosts-add || "${2:-}" == --hosts-remove ]]; then
        replaceKind=domain
        if [[ "$2" == --block-ips-replace ]]; then
            # 此处只断言字面参数原样分发，完整 IP/CIDR 校验由路由合同覆盖。
            [[ "$#" -eq 4 && "$3" == 2001:0DB8::1/64 && "$4" == 2001:db8::2/64 ]] || exit 2
            replaceKind=ip
        elif [[ "$2" == --hosts-* ]]; then
            # 这里只断言字段原样分发，精确域名、地址与状态边界由路由合同覆盖。
            [[ "$3" == Exact.Example.Com ]] || exit 2
            if [[ "$2" == --hosts-remove ]]; then
                [[ "$#" -eq 3 ]] || exit 2
            else
                [[ "$#" -eq 4 && "$4" == 2001:0DB8::10 ]] || exit 2
            fi
            replaceKind=hosts
            [[ "$2" == --hosts-replace ]] || replaceKind=${2#--}
        else
            [[ "$#" -eq 4 && "$3" != *,* && "$4" != *,* ]] || exit 2
            oldRule=$(dockerSocks5DomainsNormalize "$3") || exit 2
            newRule=$(dockerSocks5DomainsNormalize "$4") || exit 2
            [[ "${oldRule}" != "${newRule}" ]] || exit 2
        fi
        [[ "${DOMAIN_REPLACE_PRECHECK_STATUS:-0}" -eq 0 ]] ||
            exit "${DOMAIN_REPLACE_PRECHECK_STATUS}"
        printf 'fixture-%s-replace-confirm [y/N]: ' "${replaceKind}"
        if ! IFS= read -r confirmation; then
            recordAction "${replaceKind}-replace-confirm" "$2" eof
            exit 2
        fi
        recordAction "${replaceKind}-replace-confirm" "$2" "${confirmation}"
        [[ "${confirmation}" == y ]] || exit 2
        [[ "${SITE_EDIT_STATUS:-0}" -eq 0 ]] || exit "${SITE_EDIT_STATUS}"
        recordAction "${replaceKind}-replace-commit" "$2"
    elif [[ "${2:-}" == --warp-domains-add || "${2:-}" == --warp-domains-remove ||
        "${2:-}" == --ipv6-domains-add || "${2:-}" == --ipv6-domains-remove ||
        "${2:-}" == --socks5-domains-add || "${2:-}" == --socks5-domains-remove ]]; then
        [[ "$#" -eq 3 ]] && dockerSocks5DomainsNormalize "$3" >/dev/null || exit 2
        [[ "${SELECTIVE_EDIT_PRECHECK_STATUS:-0}" -eq 0 ]] ||
            exit "${SELECTIVE_EDIT_PRECHECK_STATUS}"
        family=${2#--}
        family=${family%%-*}
        printf 'fixture-%s-daily-confirm [y/N]: ' "${family}"
        if ! IFS= read -r confirmation; then
            recordAction "${family}-daily-confirm" "$2" eof
            exit 2
        fi
        recordAction "${family}-daily-confirm" "$2" "${confirmation}"
        [[ "${confirmation}" == y ]] || exit 2
        [[ "${SITE_EDIT_STATUS:-0}" -eq 0 ]] || exit "${SITE_EDIT_STATUS}"
        recordAction "${family}-daily-commit" "$2"
    elif [[ "${2:-}" == --warp-domains || "${2:-}" == --warp-global ||
        "${2:-}" == --warp-family ]]; then
        case "$2" in
        --warp-domains)
            [[ "$#" -eq 3 ]] && dockerSocks5DomainsNormalize "$3" >/dev/null || exit 2
            ;;
        --warp-global) [[ "$#" -eq 2 ]] || exit 2 ;;
        --warp-family) [[ "$#" -eq 3 && ( "$3" == ipv4 || "$3" == ipv6 ) ]] || exit 2 ;;
        esac
        printf 'fixture-warp-daily-confirm [y/N]: '
        if ! IFS= read -r confirmation; then
            recordAction warp-daily-confirm "$2" eof
            exit 2
        fi
        recordAction warp-daily-confirm "$2" "${confirmation}"
        [[ "${confirmation}" == y ]] || exit 2
        [[ "${SITE_EDIT_STATUS:-0}" -eq 0 ]] || exit "${SITE_EDIT_STATUS}"
        recordAction warp-daily-commit "$2"
    elif [[ "${2:-}" == --port-alias-replace ]]; then
        [[ "$#" -eq 5 && "$3" == entry-fixture && "$4" == 2053 && "$5" == 2083 ]] || exit 2
        printf 'fixture-port-alias-replace-confirm [y/N]: '
        if ! IFS= read -r confirmation; then
            recordAction port-alias-replace-confirm eof
            exit 2
        fi
        recordAction port-alias-replace-confirm "${confirmation}"
        [[ "${confirmation}" == y ]] || exit 2
        [[ "${SITE_EDIT_STATUS:-0}" -eq 0 ]] || exit "${SITE_EDIT_STATUS}"
        recordAction port-alias-replace-commit
    elif [[ "${2:-}" == --port-alias || "${2:-}" == --port-alias-remove ||
        "${2:-}" == --port-alias-default ]]; then
        [[ "${2:-}" == --port-alias-default && "${4:-}" == base ]] ||
            [[ "${4:-}" =~ ^[0-9]{1,5}$ ]] || exit 2
    elif [[ "${2:-}" == --cdn-entry ]]; then
        [[ "$#" -eq 4 && "$3" == entry24 && -n "$4" ]] || exit 2
    elif [[ "${2:-}" == --cdn-entry-clear ]]; then
        [[ "$#" -eq 3 && "$3" == entry25 ]] || exit 2
    elif [[ "${2:-}" == --xhttp-preset ]]; then
        [[ "$#" -eq 4 && "$3" == entry-xhttp &&
            ( "$4" == daily || "$4" == compatible || "$4" == stream || "$4" == single ) ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-xmux ]]; then
        [[ "$#" -eq 6 && "$3" == entry-xhttp && -n "$4" && -n "$5" && -n "$6" ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-concurrency ]]; then
        [[ "$#" -eq 4 && "$3" == entry-xhttp && ( "$4" == 16-32 || "$4" == 1 ) ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-xmux-clear ]]; then
        [[ "$#" -eq 3 && "$3" == entry-xhttp ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-padding ]]; then
        [[ "$#" -eq 4 && "$3" == entry-xhttp && -n "$4" ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-padding-clear ]]; then
        [[ "$#" -eq 3 && "$3" == entry-xhttp ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-headers ]]; then
        [[ "$#" -eq 5 && "$3" == entry-xhttp && -n "$4" && -n "$5" ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-headers-clear ]]; then
        [[ "$#" -eq 3 && "$3" == entry-xhttp ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-request-headers ]]; then
        [[ "$#" -eq 4 && "$3" == entry-xhttp &&
            ( "$4" == '{"x-trace":"edge value","x-route":"v3"}' ||
              "$4" == '{"x-trace":"edge value"}' || "$4" == not-json ||
              "$4" == "${XHTTP_LONG_HEADERS:?}" ) ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-request-headers-clear ]]; then
        [[ "$#" -eq 3 && "$3" == entry-xhttp ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-download ]]; then
        [[ "$#" -eq 4 && "$3" == entry-xhttp && ( "$4" == 9443 || "$4" == not-port ) ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-download-clear ]]; then
        [[ "$#" -eq 3 && "$3" == entry-xhttp ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-download-settings ]]; then
        [[ "$#" -eq 4 && "$3" == entry-xhttp ]] || exit 2
        jq -e '
          if .security == "tls" then
            (.port == 443 or .port == "not-port") and
            (.alpn == ["h2"] or .alpn == ["h3"]) and
            (del(.port,.alpn) == {
              address:"download.example.net",security:"tls",server_name:"tls.example.net",
              host:"relay.example.net",path:"/down/path",mode:"auto"})
          else . == {
            address:"192.0.2.10",port:8443,security:"reality",server_name:"reality.example.net",
            host:"reality-relay.example.net",path:"/reality/down",mode:"stream-one",
            public_key:"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",short_id:"0123456789abcdef"}
          end' <<<"$4" >/dev/null || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-limits ]]; then
        [[ "$#" -eq 7 && "$3" == entry-xhttp && -n "$4" && -n "$5" && -n "$6" && -n "$7" ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-limits-clear ]]; then
        [[ "$#" -eq 3 && "$3" == entry-xhttp ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-mode ]]; then
        [[ "$#" -eq 4 && "$3" == entry-xhttp && -n "$4" ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-path-host ]]; then
        [[ "$#" -eq 5 && "$3" == entry-xhttp && -n "$4" && -n "$5" ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-advanced ]]; then
        [[ "$#" -eq 10 && "$3" == entry-xhttp ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --xhttp-defaults ]]; then
        [[ "$#" -eq 3 && "$3" == entry-xhttp ]] || exit 2
        exit "${XHTTP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --hy2-bandwidth ]]; then
        [[ "$3" == entry-hy2 && ( ( "$#" -eq 4 && "$4" == bbr ) ||
            ( "$#" -eq 6 && "$4" == brutal && "$5" == 100 && "$6" == 50 ) ) ]] || exit 2
        exit "${UDP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --hy2-obfs ]]; then
        [[ "$#" -eq 4 && "$3" == entry-hy2 &&
            ( "$4" == salamander || "$4" == gecko || "$4" == off ) ]] || exit 2
        exit "${UDP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --hy2-masquerade ]]; then
        [[ "$#" -eq 4 && "$3" == entry-hy2 &&
            ( "$4" == https://www.example.com/path-1 || "$4" == local || "$4" == off ) ]] || exit 2
        exit "${UDP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --tuic-congestion ]]; then
        [[ "$#" -eq 4 && "$3" == entry-tuic &&
            ( "$4" == cubic || "$4" == bbr || "$4" == new_reno ) ]] || exit 2
        exit "${UDP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --tuic-connection ]]; then
        [[ "$#" -eq 5 && "$3" == entry-tuic && "$4" == 3s && "$5" == 10s ]] || exit 2
        exit "${UDP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --tuic-zero-rtt ]]; then
        [[ "$#" -eq 4 && "$3" == entry-tuic && ( "$4" == true || "$4" == false ) ]] || exit 2
        exit "${UDP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --tuic-defaults ]]; then
        [[ "$#" -eq 3 && "$3" == entry-tuic ]] || exit 2
        exit "${UDP_EDIT_STATUS:-0}"
    elif [[ "${2:-}" == --region-mode ]]; then
        [[ "$#" -eq 3 && ( "$3" == both || "$3" == domain || "$3" == ip ) ]] || exit 2
    elif [[ "${2:-}" == --direct-domains || "${2:-}" == --block-domains ||
        "${2:-}" == --direct-domains-add || "${2:-}" == --block-domains-add ||
        "${2:-}" == --direct-domains-remove || "${2:-}" == --block-domains-remove ||
        "${2:-}" == --dns-domains-add || "${2:-}" == --dns-domains-remove ||
        "${2:-}" == --region-allow-add || "${2:-}" == --region-allow-remove ]]; then
        dockerSocks5DomainsNormalize "${3:-}" >/dev/null || exit 2
    elif [[ "${2:-}" == --block-ips-csv || "${2:-}" == --block-ips-add-csv ||
        "${2:-}" == --block-ips-remove-csv ]]; then
        # 带空白的 CSV 保持一个参数，完整校验与精确匹配由后端合同检查。
        [[ "$#" -eq 3 && -n "${3:-}" && "${3:-}" != --* ]] || exit 2
    elif [[ "${2:-}" == --dns-rules ]]; then
        [[ "$#" -eq 5 && -n "${3:-}" && "${3:-}" != --* &&
            "${4:-}" =~ ^[0-9]{1,5}$ ]] || exit 2
        [[ "$((10#$4))" -ge 1 && "$((10#$4))" -le 65535 ]] || exit 2
        dockerSocks5DomainsNormalize "$5" >/dev/null || exit 2
    fi
    exit "${SITE_EDIT_STATUS:-0}"
    ;;
account) recordAction "$@" ;;
subscription)
    recordAction "$@"
    [[ "$#" -eq 3 && "$3" == --base && ( "$2" == content || "$2" == links ) ]] || exit 2
    ;;
traffic)
    recordAction "$@"
    case "${2:-}" in
    show)
        [[ "$#" -eq 2 ]] || exit 2
        exit "${TRAFFIC_SHOW_STATUS:-0}"
        ;;
    collect)
        [[ "$#" -eq 2 ]] || exit 2
        ;;
    limit|reset)
        # 只验证菜单传参和退出码；实际采集、额度恢复由流量合同覆盖。
        if [[ "$2" == limit ]]; then
            [[ "$#" -eq 4 && "$4" =~ ^[0-9]+([.][0-9]{1,6})?$ ]] || exit 2
        else
            [[ "$#" -eq 3 ]] || exit 2
        fi
        [[ "$3" == alpha ]] || exit 1
        ;;
    *) exit 2 ;;
    esac
    exit "${TRAFFIC_ACTION_STATUS:-0}"
    ;;
assess) recordAction "$@" ;;
validate|update|rollback|uninstall)
    recordAction "$@"
    [[ "$1" != validate ]] || exit "${MAINTENANCE_VALIDATE_STATUS:-0}"
    exit "${MAINTENANCE_STATUS:-0}"
    ;;
backup)
    recordAction "$@"
    [[ "$#" -eq 3 && ( "$2" == export || "$2" == verify ) &&
        "$3" == '/root/private recovery.tar' ]] || exit 2
    exit "${BACKUP_STATUS:-0}"
    ;;
restore)
    recordAction "$@"
    case "${2:-}" in
    preview|apply)
        [[ "${3:-}" == '/root/private recovery.tar' ]] || exit 2
        restoreAction=$2
        shift 3
        if [[ "${1:-}" == --manifest ]]; then
            [[ "$#" -ge 6 && "$2" == '/root/historical release/release-manifest.json' &&
                "$3" == --bundle && "$4" == '/root/historical release/release-manifest.sigstore.json' &&
                "$5" == --control-bundle && "$6" == '/root/historical release/control-bundle.tar.gz' ]] || exit 2
            shift 6
        fi
        restoreConfirm=PADM-DOCKER-RESTORE
        if [[ "${1:-}" == --rebuild-controller ]]; then
            restoreConfirm=PADM-DOCKER-RESTORE-CONTROLLER-ISOLATED
            shift
        fi
        if [[ "${restoreAction}" == apply ]]; then
            [[ "$#" -eq 2 && "$1" == --confirm && "$2" == "${restoreConfirm}" ]] || exit 2
        else
            [[ "$#" -eq 0 ]] || exit 2
        fi
        ;;
    recover) [[ "$#" -eq 2 ]] || exit 2 ;;
    *) exit 2 ;;
    esac
    exit "${BACKUP_STATUS:-0}"
    ;;
fail2ban)
    recordAction "$@"
    if [[ "${2:-}" == ssh ]]; then
        if [[ "${3:-}" == preflight ]]; then
            [[ "$#" -eq 3 ]] || exit 2
            printf 'fixture-ssh-preflight: source_verified=false jail_ready=false\n'
        elif [[ "${3:-}" == verify-source ]]; then
            [[ "$#" -eq 6 && "$3" == verify-source && "$4" == 198.51.100.10 &&
                "$5" == 2222 && "$6" == 203.0.113.9 ]] || exit 2
            printf 'fixture-ssh-source: source_verified=true jail_ready=false\n'
        else
            [[ "$#" -eq 7 && "$3" == verify-unit && "$4" == sshd.service &&
                "$5" == 198.51.100.10 && "$6" == 2222 && "$7" == 203.0.113.9 ]] || exit 2
            printf 'fixture-ssh-unit: source_verified=true unit_verified=true jail_ready=false\n'
        fi
        exit "${FAIL2BAN_STATUS:-0}"
    fi
    if [[ "${2:-}" == control ]]; then
        shift
        if [[ "${2:-}" == enable || "${2:-}" == settings ]]; then
            [[ "$#" -eq 7 ]] || exit 2
            # 补固定占位以复用 WS 参数检查，不把端口传给控制面命令。
            set -- "$1" "$2" control-listener "${@:3}"
        fi
    fi
    case "${2:-}" in
    status) printf 'fixture-fail2ban-status\n'; exit "${FAIL2BAN_STATUS:-0}" ;;
    unban|disable|verify-source|enable|settings)
        # 字面 IP 语法矩阵由服务合同覆盖，此处只验证错误返回后仍留在菜单。
        [[ "${2:-}" != unban || "${3:-}" != not-an-ip ]] || exit 2
        if [[ "${2:-}" == verify-source ]]; then
            [[ "$#" -eq 4 && "$3" == entry-fixture && "$4" != not-an-ip ]] || exit 2
        fi
        if [[ "${2:-}" == enable || "${2:-}" == settings ]]; then
            [[ "$#" -eq 8 && "$3" != not-a-port && "$7" == --confirm &&
                "$8" == PADM-DOCKER-EDIT ]] || exit 2
        fi
        if [[ "${FAIL2BAN_WAIT:-0}" == 1 ]]; then
            trap 'exit 130' INT
            trap 'exit 143' TERM
            printf '%s\n' "${BASHPID}" >"${FAIL2BAN_PID:?}"
            printf 'fixture-fail2ban-ready\n'
            while :; do sleep 1; done
        fi
        if [[ "${2:-}" == disable ]]; then
            [[ "$#" -eq 4 && "$3" == --confirm && "$4" == PADM-DOCKER-EDIT ]] || exit 2
            exit "${FAIL2BAN_DISABLE_STATUS:-0}"
        fi
        if [[ "${2:-}" == verify-source ]]; then
            printf 'fixture-fail2ban-source-verified\n'
            exit "${FAIL2BAN_VERIFY_STATUS:-0}"
        fi
        if [[ "${2:-}" == enable || "${2:-}" == settings ]]; then
            exit "${FAIL2BAN_EDIT_STATUS:-0}"
        fi
        exit "${FAIL2BAN_UNBAN_STATUS:-0}"
        ;;
    *) exit 2 ;;
    esac
    ;;
control)
    recordAction "$@"
    case "${2:-}" in
    status) printf 'fixture-control-status\n' ;;
    source-check)
        printf 'fixture-control-source-probe\n'
        exit "${CONTROL_DIAGNOSTIC_STATUS:-0}"
        ;;
    log-rotate)
        printf 'fixture-control-rotate-confirm [yes]: '
        if ! IFS= read -r confirmation; then
            recordAction control-rotate-confirm eof
            exit 2
        fi
        recordAction control-rotate-confirm "${confirmation}"
        [[ "${confirmation}" == yes ]] || exit 2
        [[ "${CONTROL_DIAGNOSTIC_STATUS:-0}" -eq 0 ]] || exit "${CONTROL_DIAGNOSTIC_STATUS}"
        recordAction control-rotate-commit
        ;;
    log-schedule)
        [[ "$#" -eq 3 ]] || exit 2
        case "$3" in
        status)
            printf 'fixture-control-log-schedule-status\n'
            exit "${CONTROL_LOG_SCHEDULE_STATUS:-0}"
            ;;
        enable|disable)
            printf 'fixture-control-log-schedule-confirm [yes]: '
            if ! IFS= read -r confirmation; then
                recordAction control-log-schedule-confirm "$3" eof
                exit 2
            fi
            recordAction control-log-schedule-confirm "$3" "${confirmation}"
            [[ "${confirmation}" == yes ]] || exit 2
            [[ "${CONTROL_LOG_SCHEDULE_STATUS:-0}" -eq 0 ]] || exit "${CONTROL_LOG_SCHEDULE_STATUS}"
            recordAction control-log-schedule-commit "$3"
            ;;
        *) exit 2 ;;
        esac
        ;;
    sync-schedule)
        case "${3:-}" in
        status)
            [[ "$#" -eq 3 ]] || exit 2
            printf 'fixture-control-sync-schedule-status\n'
            exit "${CONTROL_SYNC_SCHEDULE_STATUS:-0}"
            ;;
        enable) [[ "$#" -eq 5 && "$4" == --invite && -n "$5" ]] || exit 2 ;;
        disable) [[ "$#" -eq 3 ]] || exit 2 ;;
        *) exit 2 ;;
        esac
        printf 'fixture-control-sync-schedule-confirm [y/N]: '
        if ! IFS= read -r confirmation; then
            recordAction control-sync-schedule-confirm "$3" eof
            exit 2
        fi
        recordAction control-sync-schedule-confirm "$3" "${confirmation}"
        [[ "${confirmation}" == y ]] || exit 2
        [[ "${CONTROL_SYNC_SCHEDULE_STATUS:-0}" -eq 0 ]] || exit "${CONTROL_SYNC_SCHEDULE_STATUS}"
        recordAction control-sync-schedule-commit "$3"
        ;;
    init|invite|revoke|join|remap|set-port|reconnect|rebind|upgrade|peers)
        if [[ "$2" == peers ]]; then
            case "${3:-}" in
            list) [[ "$#" -eq 3 ]] || exit 2; printf 'fixture-control-peers\n'; exit 0 ;;
            add) [[ "$#" -eq 5 && "$4" == --peer-address && "$5" == 10.77.0.3 ]] || exit 2 ;;
            remove)
                [[ "$#" -eq 5 && "$4" == --peer-id &&
                    "$5" == 55555555-5555-4555-8555-555555555555 ]] || exit 2 ;;
            *) exit 2 ;;
            esac
        fi
        if [[ "$2" == set-port ]]; then
            [[ "$#" -eq 4 && "$3" == --port && "$4" == 19443 ]] || exit 2
        elif [[ "$2" == reconnect || "$2" == rebind ]]; then
            [[ "$#" -eq 4 && "$3" == --invite && "$4" == /root/padm-invite.json ]] || exit 2
        fi
        if [[ "$2" == join || "$2" == remap ]]; then
            [[ "$3" == --invite && "$4" == /root/padm-invite.json && "$5" == --listener &&
                ( ( "$#" -eq 6 && "$6" == entry-reality ) ||
                  ( "$#" -eq 8 && "$6" == entry-secondary && "$7" == --listener && "$8" == entry-reality ) ) ]] ||
                exit 2
        fi
        printf 'fixture-control-confirm [y/N]: '
        if ! IFS= read -r confirmation; then
            recordAction control-confirm eof
            exit 2
        fi
        recordAction control-confirm "${confirmation}"
        [[ "${confirmation}" == y ]] || exit 2
        [[ "${CONTROL_INIT_STATUS:-0}" -eq 0 ]] || exit "${CONTROL_INIT_STATUS}"
        recordAction control-commit
        ;;
    sync)
        [[ "${CONTROL_INIT_STATUS:-0}" -eq 0 ]] || exit "${CONTROL_INIT_STATUS}"
        recordAction control-commit
        ;;
    *) exit 2 ;;
    esac
    ;;
geo)
    recordAction "$@"
    if [[ "${2:-}" == status ]]; then
        [[ "${GEO_STATUS:-0}" == 0 ]] || {
            printf '当前部署不包含 Xray，不能管理 Geo 数据。\n' >&2
            exit "${GEO_STATUS}"
        }
    elif [[ "${2:-}" == update ]]; then
        if [[ "${GEO_UPDATE_WAIT:-0}" == 1 ]]; then
            trap 'exit 130' INT
            trap 'exit 143' TERM
            printf '%s\n' "${BASHPID}" >"${GEO_UPDATE_PID:?}"
            printf 'fixture-geo-update-ready\n'
            while :; do sleep 1; done
        fi
        exit "${GEO_UPDATE_STATUS:-0}"
    fi
    ;;
tls) [[ "${2:-}" == manage ]] || exit 2; dockerTlsManageCommand ;;
menu)
    source "${PROJECT_ROOT}/docker/lib/menu.sh"
    dockerMenuCli() { printf '%s\n' "${TLS_WIZARD_CLI}"; }
    dockerMenu
    ;;
esac
EOF
if [[ "${MENU_SCOPE}" == full ]]; then
# 启动与恢复共用来源输入；直接验证生产动作分组，不重复业务菜单的导航矩阵。
export SOURCE_INPUT_CHECK=1
for sourceAction in up restart update rollback reinstall reinstall-spec fail2ban-disable fail2ban-enable fail2ban-settings fail2ban-port \
    fail2ban-control-disable fail2ban-control-enable fail2ban-control-settings business-restore \
    control-source-check control-log-rotate; do
    case "${sourceAction}" in
    fail2ban-disable) sourceCommand=(fail2ban disable --confirm PADM-DOCKER-EDIT) ;;
    fail2ban-enable) sourceCommand=(fail2ban enable 24444,24445 6 600 3600 --confirm PADM-DOCKER-EDIT) ;;
    fail2ban-settings) sourceCommand=(fail2ban settings 24444,24445 6 600 3600 --confirm PADM-DOCKER-EDIT) ;;
    fail2ban-port) sourceCommand=(edit --fail2ban-port entry-fixture 25444 --confirm PADM-DOCKER-EDIT) ;;
    fail2ban-control-disable) sourceCommand=(fail2ban control disable --confirm PADM-DOCKER-EDIT) ;;
    fail2ban-control-enable) sourceCommand=(fail2ban control enable 6 600 3600 --confirm PADM-DOCKER-EDIT) ;;
    fail2ban-control-settings) sourceCommand=(fail2ban control settings 6 600 3600 --confirm PADM-DOCKER-EDIT) ;;
    business-restore) sourceCommand=(business restore fixture.json --strategy replace --yes) ;;
    control-source-check) sourceCommand=(control source-check) ;;
    control-log-rotate) sourceCommand=(control log-rotate) ;;
    reinstall-spec) sourceCommand=(reinstall --spec '/root/private spec.json') ;;
    *) sourceCommand=("${sourceAction}") ;;
    esac
    : >"${TLS_WIZARD_ACTIONS}"
    runPty "source-input-${sourceAction}" source-input 203.0.113.9 \
        "${TLS_WIZARD_CLI}" source-input-menu "${sourceCommand[@]}"
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${sourceCommand[*]}"$'\nsource-input 203.0.113.9' ]] ||
        fail "${sourceAction}: 来源输入未到达前台 CLI 或参数分发错误"
done
unset SOURCE_INPUT_CHECK
export REINSTALL_MENU_SPEC='/root/private complete spec.json'
for installCase in flow cancel eof path-eof failed; do
    : >"${TLS_WIZARD_ACTIONS}"
    export INSTALL_MENU_STATUS=0
    [[ "${installCase}" != failed ]] || INSTALL_MENU_STATUS=17
    runPty "install-${installCase}" install "${installCase}" "${TLS_WIZARD_CLI}" menu
    if [[ "${installCase}" == flow || "${installCase}" == failed ]]; then
        [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "reinstall --spec ${REINSTALL_MENU_SPEC}"$'\nreinstall\nsetup' ]] ||
            fail '安装与重装菜单路径参数或动作分发错误'
        if [[ "${installCase}" == failed ]]; then
            [[ "$(grep -Fc '操作失败，退出码: 17' "${CONTROL_LOG}")" -eq 3 ]] ||
                fail '重装菜单失败后未继续其它动作或丢失退出码'
        fi
    else
        [[ ! -s "${TLS_WIZARD_ACTIONS}" ]] || fail '重装菜单取消或 EOF 仍调用业务命令'
    fi
done
unset INSTALL_MENU_STATUS REINSTALL_MENU_SPEC
printf '{"tls":null}\n' >"${TLS_WIZARD_ROOT}/config/spec.json"
: >"${TLS_WIZARD_ACTIONS}"
runPty tls-no-domain menu $'8\n0\n' "${TLS_WIZARD_CLI}" menu
grep -Fq '当前部署没有 TLS 域名' "${CONTROL_LOG}" || fail 'TLS menu accepted a deployment without a TLS domain'
[[ ! -s "${TLS_WIZARD_ACTIONS}" ]] || fail 'missing TLS domain reached a business command'
printf '{"tls":{"domain":"ws.example.com"}}\n' >"${TLS_WIZARD_ROOT}/config/spec.json"
: >"${TLS_WIZARD_ACTIONS}"
runPty core-assessment menu $'13\n0\n' "${TLS_WIZARD_CLI}" menu
[[ "$(<"${TLS_WIZARD_ACTIONS}")" == assess ]] || fail 'core assessment menu dispatched incorrect arguments'
fi

if [[ "${MENU_SCOPE}" == full || "${MENU_SCOPE}" == maintenance ]]; then
expectedReleaseAssets=' --manifest /root/historical release/release-manifest.json --bundle /root/historical release/release-manifest.sigstore.json --control-bundle /root/historical release/control-bundle.tar.gz'
for maintenanceCase in flow cancel update-eof uninstall-eof failed update rollback uninstall \
    backup-flow backup-cancel backup-eof backup-failed restore-flow restore-cancel restore-eof restore-failed \
    restore-apply restore-apply-failed restore-apply-cancel restore-apply-eof restore-apply-path-eof \
    restore-source-cancel restore-assets restore-assets-failed restore-assets-apply restore-assets-apply-failed \
    restore-assets-cancel restore-assets-apply-cancel restore-assets-reset \
    restore-controller restore-controller-apply restore-controller-assets restore-controller-cancel \
    restore-controller-eof restore-controller-reset restore-controller-failed \
    restore-recover restore-recover-failed; do
    : >"${TLS_WIZARD_ACTIONS}"
    export MAINTENANCE_STATUS=0 MAINTENANCE_VALIDATE_STATUS=0 BACKUP_STATUS=0
    [[ "${maintenanceCase}" != flow && "${maintenanceCase}" != failed ]] || MAINTENANCE_STATUS=17
    [[ "${maintenanceCase}" != failed ]] || MAINTENANCE_VALIDATE_STATUS=17
    case "${maintenanceCase}" in *-failed) BACKUP_STATUS=15 ;; esac
    runPty "maintenance-${maintenanceCase}" maintenance "${maintenanceCase}" "${TLS_WIZARD_CLI}" menu
    expectedMaintenance=
    case "${maintenanceCase}" in
    flow)
        expectedMaintenance=$'validate\nrollback'
        grep -Fq '无效选项' "${CONTROL_LOG}" || fail '维护菜单未保留无效输入后的操作'
        ;;
    failed)
        expectedMaintenance=$'validate\nupdate\nrollback\nuninstall'
        [[ "$(grep -Fc '操作失败，退出码: 17' "${CONTROL_LOG}")" -eq 4 ]] ||
            fail '维护失败未保留退出码或未继续执行菜单'
        ;;
    update|rollback|uninstall)
        expectedMaintenance=${maintenanceCase}
        [[ "$(grep -Fc "${MAIN_MENU_TITLE}" "${CONTROL_LOG}")" -eq 1 ]] ||
            fail "维护 ${maintenanceCase} 成功后仍使用旧菜单"
        [[ "$(grep -Fc '┌─ Docker 服务维护' "${CONTROL_LOG}")" -eq 1 ]] ||
            fail "维护 ${maintenanceCase} 成功后仍留在子菜单"
        ;;
    backup-flow|backup-failed)
        expectedMaintenance=$'backup export /root/private recovery.tar\nbackup verify /root/private recovery.tar'
        [[ "$(grep -Fc '┌─ Docker 服务维护' "${CONTROL_LOG}")" -eq 3 ]] ||
            fail '灾备操作结束了维护菜单会话'
        ! grep -Fq '[y/N]' "${CONTROL_LOG}" || fail '灾备菜单增加了重复确认'
        if [[ "${maintenanceCase}" == backup-failed ]]; then
            [[ "$(grep -Fc '操作失败，退出码: 15' "${CONTROL_LOG}")" -eq 2 ]] ||
                fail '灾备失败未保留退出码或继续菜单'
        else
            ! grep -Fq '操作失败，退出码:' "${CONTROL_LOG}" ||
                fail '灾备路径未保持为单个完整参数'
        fi
        ;;
    restore-flow|restore-failed|restore-assets|restore-assets-failed|restore-assets-reset)
        expectedMaintenance='restore preview /root/private recovery.tar'
        [[ "${maintenanceCase}" != restore-assets* ]] ||
            expectedMaintenance+="${expectedReleaseAssets}"
        expectedMaintenanceVisits=2
        if [[ "${maintenanceCase}" == restore-assets-reset ]]; then
            expectedMaintenance+=$'\nrestore preview /root/private recovery.tar'
            expectedMaintenanceVisits=3
        fi
        [[ "$(grep -Fc '┌─ Docker 服务维护' "${CONTROL_LOG}")" -eq "${expectedMaintenanceVisits}" ]] ||
            fail '恢复预览结束了维护菜单会话'
        ! grep -Fq '[y/N]' "${CONTROL_LOG}" || fail '恢复预览增加了重复确认'
        if [[ "${maintenanceCase}" == *-failed ]]; then
            grep -Fq '操作失败，退出码: 15' "${CONTROL_LOG}" || fail '恢复预览未保留失败退出码'
        else
            ! grep -Fq '操作失败，退出码:' "${CONTROL_LOG}" || fail '恢复预览归档或发布资产路径被拆分'
        fi
        ;;
    restore-apply|restore-apply-failed|restore-assets-apply|restore-assets-apply-failed|restore-recover|restore-recover-failed)
        expectedMaintenance='restore recover'
        if [[ "${maintenanceCase}" == *apply* ]]; then
            expectedMaintenance='restore apply /root/private recovery.tar'
            [[ "${maintenanceCase}" != restore-assets-* ]] ||
                expectedMaintenance+="${expectedReleaseAssets}"
            expectedMaintenance+=' --confirm PADM-DOCKER-RESTORE'
        fi
        [[ "$(grep -Fc '┌─ Docker 服务维护' "${CONTROL_LOG}")" -eq 2 ]] ||
            fail '灾备恢复动作结束了维护菜单会话'
        if [[ "${maintenanceCase}" == *-failed ]]; then
            grep -Fq '操作失败，退出码: 15' "${CONTROL_LOG}" || fail '灾备恢复未保留失败退出码'
        else
            ! grep -Fq '操作失败，退出码:' "${CONTROL_LOG}" || fail '灾备恢复参数错误'
        fi
        ;;
    restore-controller|restore-controller-assets|restore-controller-reset|restore-controller-failed|restore-controller-apply)
        expectedMaintenance='restore preview /root/private recovery.tar'
        [[ "${maintenanceCase}" != restore-controller-apply ]] ||
            expectedMaintenance='restore apply /root/private recovery.tar'
        [[ "${maintenanceCase}" != restore-controller-assets ]] ||
            expectedMaintenance+="${expectedReleaseAssets}"
        expectedMaintenance+=' --rebuild-controller'
        [[ "${maintenanceCase}" != restore-controller-apply ]] ||
            expectedMaintenance+=' --confirm PADM-DOCKER-RESTORE-CONTROLLER-ISOLATED'
        if [[ "${maintenanceCase}" == restore-controller-reset ]]; then
            expectedMaintenance+=$'\nrestore preview /root/private recovery.tar'
        fi
        grep -Fq '旧主控须先停机隔离' "${CONTROL_LOG}" || fail '主控恢复未说明旧节点隔离'
        if [[ "${maintenanceCase}" == *-failed ]]; then
            grep -Fq '操作失败，退出码: 15' "${CONTROL_LOG}" || fail '主控恢复未保留失败退出码'
        else
            ! grep -Fq '操作失败，退出码:' "${CONTROL_LOG}" || fail '主控恢复参数错误'
        fi
        ;;
    esac
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedMaintenance}" ]] ||
        fail "维护 ${maintenanceCase} 参数分发错误或取消后仍执行操作"
    for maintenanceLabel in '1. 更新、回滚与部署维护' 'Docker 服务维护' '1. 校验部署配置' \
        '2. 更新镜像与控制脚本' '3. 回滚最近更新' '4. 卸载服务与控制命令（保留数据）' '5. Fail2ban 维护' \
        '6. 导出灾备归档' '7. 只读校验灾备归档' '8. 预览灾备恢复（空目标）' \
        '9. 应用灾备恢复（空目标）' '10. 恢复中断的灾备事务' \
        '11. 预览主控灾备（新身份）' '12. 应用主控灾备（新身份）'; do
        grep -Fq "${maintenanceLabel}" "${CONTROL_LOG}" || fail "维护菜单缺少: ${maintenanceLabel}"
    done
done
unset MAINTENANCE_STATUS MAINTENANCE_VALIDATE_STATUS BACKUP_STATUS expectedReleaseAssets
fi
if [[ "${MENU_SCOPE}" == maintenance ]]; then
    printf 'docker-menu-maintenance-regression-ok\n'
    exit 0
fi

if [[ "${MENU_SCOPE}" == full ]]; then
for fail2banCase in flow cancel menu-eof invalid failed int term disable disable-failed disable-int disable-term \
    verify verify-cancel verify-list-failed verify-invalid verify-failed verify-int verify-term \
    enable enable-cancel enable-invalid enable-failed enable-list-failed enable-int enable-term \
    settings settings-cancel settings-invalid settings-failed settings-list-failed settings-int settings-term \
    port port-cancel port-invalid port-failed port-list-failed \
    ssh-preflight ssh-preflight-failed ssh-source ssh-source-failed ssh-source-cancel \
    ssh-unit ssh-unit-failed ssh-unit-cancel-unit ssh-unit-cancel-target \
    ssh-unit-cancel-port ssh-unit-cancel-source; do
    : >"${TLS_WIZARD_ACTIONS}"
    export FAIL2BAN_STATUS=0 FAIL2BAN_UNBAN_STATUS=0 FAIL2BAN_DISABLE_STATUS=0 \
        FAIL2BAN_VERIFY_STATUS=0 FAIL2BAN_EDIT_STATUS=0 FAIL2BAN_PROTOCOL_LIST_STATUS=0 FAIL2BAN_WAIT=0 \
        FAIL2BAN_PID="${TEST_ROOT}/fail2ban.pid"
    [[ "${fail2banCase}" != failed ]] || { FAIL2BAN_STATUS=17; FAIL2BAN_UNBAN_STATUS=17; }
    [[ "${fail2banCase}" != ssh-preflight-failed ]] || FAIL2BAN_STATUS=10
    case "${fail2banCase}" in ssh-source-failed|ssh-unit-failed) FAIL2BAN_STATUS=15 ;; esac
    [[ "${fail2banCase}" != disable-failed ]] || FAIL2BAN_DISABLE_STATUS=17
    [[ "${fail2banCase}" != verify-failed ]] || FAIL2BAN_VERIFY_STATUS=17
    [[ "${fail2banCase}" != verify-list-failed ]] || FAIL2BAN_PROTOCOL_LIST_STATUS=17
    case "${fail2banCase}" in enable-failed|settings-failed|port-failed) FAIL2BAN_EDIT_STATUS=17 ;; esac
    case "${fail2banCase}" in enable-list-failed|settings-list-failed|port-list-failed) FAIL2BAN_PROTOCOL_LIST_STATUS=17 ;; esac
    case "${fail2banCase}" in int|term|*-int|*-term) FAIL2BAN_WAIT=1 ;; esac
    runPty "fail2ban-${fail2banCase}" maintenance "fail2ban-${fail2banCase}" "${TLS_WIZARD_CLI}" menu
    expectedFail2ban=
    case "${fail2banCase}" in
    ssh-source|ssh-source-failed)
        expectedFail2ban='fail2ban ssh verify-source 198.51.100.10 2222 203.0.113.9'
        grep -Fq 'fixture-ssh-source: source_verified=true jail_ready=false' "${CONTROL_LOG}" ||
            fail 'SSH 来源命令未显示 jail 未就绪'
        if [[ "${fail2banCase}" == ssh-source-failed ]]; then
            grep -Fq '操作失败，退出码: 15' "${CONTROL_LOG}" || fail 'SSH 来源失败未保留退出码或留在菜单'
        fi
        ;;
    ssh-source-cancel) ;;
    ssh-unit|ssh-unit-failed)
        expectedFail2ban='fail2ban ssh verify-unit sshd.service 198.51.100.10 2222 203.0.113.9'
        grep -Fq 'fixture-ssh-unit: source_verified=true unit_verified=true jail_ready=false' "${CONTROL_LOG}" ||
            fail 'SSH unit 来源命令未显示 unit 已核验和 jail 未就绪'
        if [[ "${fail2banCase}" == ssh-unit-failed ]]; then
            grep -Fq '操作失败，退出码: 15' "${CONTROL_LOG}" ||
                fail 'SSH unit 来源失败未保留退出码或留在菜单'
        fi
        ;;
    ssh-unit-cancel-*) ;;
    ssh-preflight|ssh-preflight-failed)
        expectedFail2ban='fail2ban ssh preflight'
        grep -Fq 'fixture-ssh-preflight: source_verified=false jail_ready=false' "${CONTROL_LOG}" ||
            fail 'SSH 预检未显示未证明来源和 jail 未就绪'
        if [[ "${fail2banCase}" == ssh-preflight-failed ]]; then
            grep -Fq '操作失败，退出码: 10' "${CONTROL_LOG}" || fail 'SSH 预检失败未保留退出码或留在子菜单'
        fi
        ;;
    flow)
        expectedFail2ban=$'fail2ban status\nfail2ban unban 203.0.113.9\nfail2ban unban 2001:db8::9'
        grep -Fq 'fixture-fail2ban-status' "${CONTROL_LOG}" || fail 'Fail2ban 状态未显示后端输出'
        grep -Fq '无效选项' "${CONTROL_LOG}" || fail 'Fail2ban 无效选项后没有留在菜单'
        ;;
    invalid)
        expectedFail2ban='fail2ban unban not-an-ip'
        grep -Fq '操作失败，退出码: 2' "${CONTROL_LOG}" || fail 'Fail2ban 非法 IP 未显示用法错误'
        ;;
    failed)
        expectedFail2ban=$'fail2ban status\nfail2ban unban 203.0.113.9'
        [[ "$(grep -Fc '操作失败，退出码: 17' "${CONTROL_LOG}")" -eq 2 ]] ||
            fail 'Fail2ban 后端失败未保留退出码或留在子菜单'
        ;;
    int|term)
        expectedFail2ban='fail2ban unban 203.0.113.9'
        ! kill -0 "$(<"${FAIL2BAN_PID}")" 2>/dev/null ||
            fail "Fail2ban ${fail2banCase} 后 CLI 进程仍存活"
        ;;
    disable|disable-failed|disable-int|disable-term)
        expectedFail2ban='fail2ban disable --confirm PADM-DOCKER-EDIT'
        if [[ "${fail2banCase}" == disable-failed ]]; then
            grep -Fq '操作失败，退出码: 17' "${CONTROL_LOG}" || fail 'Fail2ban 停用失败未留在菜单'
        elif [[ "${fail2banCase}" == disable-int || "${fail2banCase}" == disable-term ]]; then
            ! kill -0 "$(<"${FAIL2BAN_PID}")" 2>/dev/null ||
                fail "Fail2ban ${fail2banCase} 后 CLI 进程仍存活"
        fi
        ;;
    verify)
        expectedFail2ban=$'protocol list\nfail2ban verify-source entry-fixture 203.0.113.9'
        expectedFail2ban+=$'\nprotocol list\nfail2ban verify-source entry-fixture 2001:db8::9'
        [[ "$(grep -Fc 'fixture-fail2ban-source-verified' "${CONTROL_LOG}")" -eq 2 ]] ||
            fail 'Fail2ban 双栈来源诊断未显示后端输出'
        ;;
    verify-cancel)
        expectedFail2ban=$'protocol list\nprotocol list\nprotocol list\nprotocol list\nprotocol list\nprotocol list'
        ;;
    verify-list-failed)
        expectedFail2ban='protocol list'
        grep -Fq '操作失败，退出码: 17' "${CONTROL_LOG}" || fail 'Fail2ban 入口列表失败未留在菜单'
        ! grep -Fq 'WS 入口 ID（0 返回）: ' "${CONTROL_LOG}" || fail 'Fail2ban 入口列表失败仍接受诊断输入'
        ;;
    verify-invalid|verify-failed|verify-int|verify-term)
        address=203.0.113.9
        [[ "${fail2banCase}" != verify-invalid ]] || address=not-an-ip
        expectedFail2ban=$'protocol list\nfail2ban verify-source entry-fixture '"${address}"
        if [[ "${fail2banCase}" == verify-invalid ]]; then
            grep -Fq '操作失败，退出码: 2' "${CONTROL_LOG}" || fail 'Fail2ban 来源诊断非法 IP 未显示用法错误'
        elif [[ "${fail2banCase}" == verify-failed ]]; then
            grep -Fq '操作失败，退出码: 17' "${CONTROL_LOG}" || fail 'Fail2ban 来源诊断失败未留在菜单'
        else
            ! kill -0 "$(<"${FAIL2BAN_PID}")" 2>/dev/null ||
                fail "Fail2ban ${fail2banCase} 后 CLI 进程仍存活"
        fi
        ;;
    port-cancel)
        expectedFail2ban=$(printf 'protocol list\n%.0s' {1..10})
        ;;
    port-list-failed)
        expectedFail2ban=$'protocol list\nfail2ban status'
        grep -Fq '操作失败，退出码: 17' "${CONTROL_LOG}" ||
            fail 'WS 端口入口列表失败未留在菜单'
        ! grep -Fq '受保护 WS 入口 ID（0 返回）' "${CONTROL_LOG}" ||
            fail 'WS 端口入口列表失败仍接受写操作输入'
        ;;
    port|port-invalid|port-failed)
        port=25444
        [[ "${fail2banCase}" != port-invalid ]] || port=not-a-port
        expectedFail2ban=$'protocol list\nedit --fail2ban-port entry-fixture '"${port}"$' --confirm PADM-DOCKER-EDIT\nfail2ban status'
        [[ "${fail2banCase}" != port-invalid ]] ||
            grep -Fq '操作失败，退出码: 2' "${CONTROL_LOG}" || fail 'WS 非法端口未保留用法错误'
        [[ "${fail2banCase}" != port-failed ]] ||
            grep -Fq '操作失败，退出码: 17' "${CONTROL_LOG}" || fail 'WS 端口变更失败未留在菜单'
        ;;
    enable*|settings*)
        action=${fail2banCase%%-*}
        case "${fail2banCase}" in
        *-cancel)
            expectedFail2ban=$(printf 'protocol list\n%.0s' {1..12})
            ;;
        *-list-failed)
            expectedFail2ban='protocol list'
            grep -Fq '操作失败，退出码: 17' "${CONTROL_LOG}" || fail 'Fail2ban 入口列表失败未留在菜单'
            ! grep -Fq '保护 WS 端口（逗号分隔，0 返回）' "${CONTROL_LOG}" || fail '列表失败仍接受写操作输入'
            ;;
        *)
            ports=24444,24445
            [[ "${fail2banCase}" != *-invalid ]] || ports=not-a-port
            expectedFail2ban=$'protocol list\nfail2ban '"${action} ${ports} 6 600 3600 --confirm PADM-DOCKER-EDIT"
            case "${fail2banCase}" in
            *-invalid) grep -Fq '操作失败，退出码: 2' "${CONTROL_LOG}" || fail 'Fail2ban 参数错误未保留退出码' ;;
            *-failed) grep -Fq '操作失败，退出码: 17' "${CONTROL_LOG}" || fail 'Fail2ban 编辑失败未留在菜单' ;;
            *-int|*-term)
                ! kill -0 "$(<"${FAIL2BAN_PID}")" 2>/dev/null || fail "Fail2ban ${fail2banCase} 后 CLI 仍存活"
                ;;
            esac
            ;;
        esac
        ;;
    esac
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedFail2ban}" ]] ||
        fail "Fail2ban ${fail2banCase} 参数分发错误或取消后仍执行操作"
    for fail2banLabel in '5. Fail2ban 维护' 'Docker Fail2ban 维护' '1. 查看 WS 状态' \
        '2. 解封 WS 单个 IP' '3. 停用 WS 站点扫描防护' '4. 核对 WS 真实来源' \
        '5. 启用 WS 站点扫描防护' '6. 修改 WS 站点扫描参数' '12. SSH 宿主只读预检' \
        '13. 核对 SSH 实时来源' '14. 核对 SSH unit 实时来源' '20. 修改单入口 WS 保护端口'; do
        grep -Fq "${fail2banLabel}" "${CONTROL_LOG}" || fail "Fail2ban 菜单缺少: ${fail2banLabel}"
    done
done
# 控制面复用 WS 驱动；只检查作用域差异，信号与孙进程清理在 menu-signals 中覆盖。
for fail2banCase in flow cancel menu-eof disable enable settings enable-cancel settings-cancel; do
    : >"${TLS_WIZARD_ACTIONS}"
    export FAIL2BAN_STATUS=0 FAIL2BAN_UNBAN_STATUS=0 FAIL2BAN_DISABLE_STATUS=0 \
        FAIL2BAN_EDIT_STATUS=0 FAIL2BAN_WAIT=0
    runPty "fail2ban-control-${fail2banCase}" maintenance "fail2ban-control-${fail2banCase}" \
        "${TLS_WIZARD_CLI}" menu
    expectedFail2ban=
    case "${fail2banCase}" in
    flow)
        expectedFail2ban=$'fail2ban control status\nfail2ban control unban 203.0.113.9'
        grep -Fq 'fixture-fail2ban-status' "${CONTROL_LOG}" || fail '控制面状态未显示后端输出'
        ;;
    disable) expectedFail2ban='fail2ban control disable --confirm PADM-DOCKER-EDIT' ;;
    enable|settings)
        expectedFail2ban=$'control status\nfail2ban control '"${fail2banCase} 6 600 3600 --confirm PADM-DOCKER-EDIT"
        ;;
    *-cancel) expectedFail2ban=$(printf 'control status\n%.0s' {1..10}) ;;
    esac
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedFail2ban}" ]] ||
        fail "控制面 ${fail2banCase} 参数分发错误或取消后仍执行操作"
    ! grep -Fq '保护 WS 端口（逗号分隔，0 返回）' "${CONTROL_LOG}" ||
        fail '控制面参数误要求 WS 端口'
    for fail2banLabel in '7. 查看控制面状态' '8. 解封控制面单个 IP' \
        '9. 停用控制面防护' '10. 启用控制面防护' '11. 修改控制面防护参数'; do
        grep -Fq "${fail2banLabel}" "${CONTROL_LOG}" || fail "控制面菜单缺少: ${fail2banLabel}"
    done
done
unset FAIL2BAN_STATUS FAIL2BAN_UNBAN_STATUS FAIL2BAN_DISABLE_STATUS \
    FAIL2BAN_VERIFY_STATUS FAIL2BAN_EDIT_STATUS FAIL2BAN_PROTOCOL_LIST_STATUS FAIL2BAN_WAIT FAIL2BAN_PID

export SITE_MENU_RECORD_STATUS=1
for siteCase in flow title cancel static-eof redirect-eof template-eof title-eof alpn-diagnose-eof alpn-recommended-eof \
    alpn-manual-id-eof alpn-manual-order-eof failed; do
    : >"${TLS_WIZARD_ACTIONS}"
    export SITE_EDIT_STATUS=0 SITE_ALPN_STATUS=0
    [[ "${siteCase}" != failed ]] || { SITE_EDIT_STATUS=15; SITE_ALPN_STATUS=17; }
    runPty "sites-${siteCase}" sites "${siteCase}" "${TLS_WIZARD_CLI}" menu
    expectedSite=
    case "${siteCase}" in
    flow)
        expectedSite=$'edit --site-default\nedit --site-static /root/public-site\nedit --site-redirect https://example.com/path?a=1&b=2\nstatus'
        expectedSite+=$'\nprotocol alpn-status\nprotocol alpn-status entry-tls\nedit --alpn entry-tls h2,http/1.1'
        expectedSite+=$'\nedit --alpn entry-tls h2,http/1.1\nedit --alpn entry-tls http/1.1,h2\nedit --alpn entry-tls http/1.1'
        expectedSite+=$'\nedit --site-template notes\nedit --site-template photos\nedit --site-template docs'
        for label in '1. 传统 TLS fallback 维护' '1. 默认页' '2. 发布静态目录' '3. 302 跳转' \
            '4. 查看站点模式' '5. ALPN 诊断' '6. 修复为推荐 ALPN' '7. 手动设置 ALPN' \
            '8. 内置静态站点' '1. 笔记（notes）' '2. 相册（photos）' '3. 文档（docs）' \
            '1. h2,http/1.1' '2. http/1.1,h2' '3. http/1.1' '0. 返回'; do
            grep -Fq "${label}" "${CONTROL_LOG}" || fail "站点菜单缺少: ${label}"
        done
        ;;
    title)
        expectedSite=$'edit --site-template notes --site-title 中文 & <站点> "双引" \'单引\' | \\'
        ! grep -Fq '操作失败，退出码:' "${CONTROL_LOG}" ||
            fail '自定义站名未保持为单个完整参数'
        ;;
    failed)
        expectedSite=$'edit --site-default\nprotocol alpn-status entry-tls\nedit --alpn entry-tls h2,http/1.1\nedit --alpn entry-tls http/1.1,h2\nedit --site-template notes\nstatus'
        grep -Fq '操作失败，退出码: 15' "${CONTROL_LOG}" || fail '站点提交失败未显示退出码'
        grep -Fq '操作失败，退出码: 17' "${CONTROL_LOG}" || fail 'ALPN 诊断失败未显示退出码'
        ;;
    esac
    expectedSite+="${expectedSite:+$'\n'}status"
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedSite}" ]] ||
        fail "站点 ${siteCase} 参数分发错误或取消后仍执行编辑"
    case "${siteCase}" in
    flow|title|cancel|template-eof|title-eof|failed)
        grep -Fq 'Hysteria2 发布后，在已有入口参数中关闭混淆并将伪装设置为 local。' \
            "${CONTROL_LOG}" || fail "站点 ${siteCase} 未说明 Hy2 local 的两步流程"
        ;;
    esac
done
unset SITE_MENU_RECORD_STATUS SITE_EDIT_STATUS SITE_ALPN_STATUS
fi

if [[ "${MENU_SCOPE}" != port-alias && "${MENU_SCOPE}" != xhttp && "${MENU_SCOPE}" != control ]]; then
for routingCase in flow csv-long cancel socks5-input-eof socks5-input-commit-failed domains-eof dns-server-eof dns-port-eof dns-domains-eof dns-explicit-port dns-invalid dns-failed hosts-input-eof hosts-input-status-failed hosts-input-commit-failed direct-domains-eof block-domains-eof direct-block-invalid direct-domains-add-eof block-domains-add-eof direct-block-add-invalid direct-block-add-failed direct-domains-remove-eof block-domains-remove-eof direct-block-remove-invalid direct-block-remove-failed block-ips-file-eof block-ips-add-eof block-ips-remove-eof block-ips-change-failed dns-domains-add-eof dns-domains-remove-eof dns-domains-change-invalid dns-domains-change-failed region-eof region-allow-invalid region-allow-failed region-mode-flow region-mode-cancel region-mode-failed ipv6-eof warp-eof \
    domain-replace-flow domain-replace-cancel domain-replace-invalid domain-replace-status-failed \
    domain-replace-state-failed domain-replace-confirm-cancel domain-replace-confirm-eof domain-replace-commit-failed \
    ip-replace-flow ip-replace-cancel ip-replace-status-failed ip-replace-state-failed \
    ip-replace-confirm-cancel ip-replace-confirm-eof ip-replace-commit-failed \
    hosts-replace-flow hosts-replace-cancel hosts-replace-invalid hosts-replace-status-failed hosts-replace-state-failed \
    hosts-replace-confirm-cancel hosts-replace-confirm-eof hosts-replace-commit-failed \
    hosts-manage-flow hosts-manage-cancel hosts-manage-invalid hosts-manage-status-failed hosts-manage-state-failed \
    hosts-manage-confirm-cancel hosts-manage-confirm-eof hosts-manage-commit-failed \
    selective-domains-invalid selective-domains-state-failed selective-domains-confirm-cancel selective-domains-confirm-eof selective-domains-commit-failed \
    socks5-domains-eof socks5-domains-status-failed warp-input-status-failed warp-input-commit-failed \
    access-control-flow access-control-cancel access-control-failed \
    upstream-flow upstream-cancel upstream-status-failed upstream-commit-failed \
    http-relay-flow http-relay-cancel http-relay-status-failed http-relay-commit-failed \
    tproxy-flow tproxy-cancel tproxy-status-failed tproxy-commit-failed \
    tproxy-output-flow tproxy-output-cancel tproxy-output-failed \
    tun-flow tun-cancel tun-status-failed tun-commit-failed \
    block-ips-mode-flow block-ips-mode-failed \
    warp-confirm-cancel warp-confirm-eof http-relay-eof failed return; do
    [[ "${MENU_SCOPE}" != tun || "${routingCase}" == tun-* ]] || continue
    [[ "${MENU_SCOPE}" != block-ips-resolved || "${routingCase}" == block-ips-mode-* ]] || continue
    : >"${TLS_WIZARD_ACTIONS}"
    export SITE_EDIT_STATUS=0 ROUTING_STATUS=0 TPROXY_STATUS=0 TUN_STATUS=0 SELECTIVE_EDIT_PRECHECK_STATUS=0 DOMAIN_REPLACE_PRECHECK_STATUS=0
    [[ "${routingCase}" != selective-domains-state-failed ]] || SELECTIVE_EDIT_PRECHECK_STATUS=15
    [[ "${routingCase}" != *-replace-state-failed && "${routingCase}" != hosts-manage-state-failed ]] ||
        DOMAIN_REPLACE_PRECHECK_STATUS=15
    [[ "${routingCase}" != *-replace-status-failed && "${routingCase}" != hosts-manage-status-failed ]] ||
        ROUTING_STATUS=17
    [[ "${routingCase}" != socks5-domains-status-failed ]] || ROUTING_STATUS=17
    [[ "${routingCase}" != upstream-status-failed ]] || ROUTING_STATUS=17
    [[ "${routingCase}" != http-relay-status-failed ]] || ROUTING_STATUS=17
    [[ "${routingCase}" != warp-input-status-failed ]] || ROUTING_STATUS=17
    [[ "${routingCase}" != hosts-input-status-failed ]] || ROUTING_STATUS=17
    [[ "${routingCase}" != tproxy-status-failed ]] || TPROXY_STATUS=17
    [[ "${routingCase}" != tun-status-failed ]] || TUN_STATUS=17
    [[ "${routingCase}" != failed ]] || { SITE_EDIT_STATUS=15; ROUTING_STATUS=17; }
    [[ "${routingCase}" != direct-block-add-failed && "${routingCase}" != direct-block-remove-failed &&
        "${routingCase}" != dns-failed && "${routingCase}" != region-allow-failed &&
        "${routingCase}" != region-mode-failed &&
        "${routingCase}" != block-ips-change-failed &&
        "${routingCase}" != dns-domains-change-failed &&
        "${routingCase}" != selective-domains-commit-failed &&
        "${routingCase}" != *-replace-commit-failed &&
        "${routingCase}" != socks5-input-commit-failed &&
        "${routingCase}" != warp-input-commit-failed &&
        "${routingCase}" != hosts-input-commit-failed &&
        "${routingCase}" != access-control-failed &&
        "${routingCase}" != upstream-commit-failed &&
        "${routingCase}" != http-relay-commit-failed &&
        "${routingCase}" != tproxy-commit-failed &&
        "${routingCase}" != tproxy-output-failed &&
        "${routingCase}" != tun-commit-failed &&
        "${routingCase}" != block-ips-mode-failed &&
        "${routingCase}" != hosts-manage-commit-failed ]] || SITE_EDIT_STATUS=15
    runPty "routing-${routingCase}" routing "${routingCase}" "${TLS_WIZARD_CLI}" menu
    expectedRouting=
    case "${routingCase}" in
    csv-long)
        longDomains=
        for ((domainIndex = 1; domainIndex <= 257; domainIndex++)); do
            printf -v domain 'd%03d.example.com' "${domainIndex}"
            longDomains+="${longDomains:+,}${domain}"
            [[ "${domainIndex}" -ge 256 ]] || continue
            expectedRouting+="${expectedRouting:+$'\n'}edit --direct-domains ${longDomains}"
        done
        [[ "$(grep -Fc '操作失败，退出码: 2' "${CONTROL_LOG}")" -eq 1 ]] ||
            fail '长 CSV 未完整接受 256 项或未拒绝 257 项'
        ;;
    flow|failed)
        expectedRouting='protocol routing-status'
        if [[ "${routingCase}" == flow ]]; then
            expectedRouting+=$'\nedit --socks5-input\nsocks5-input-confirm y\nsocks5-input-commit'
        else
            ! grep -Eq 'fixture-(socks5|http-relay|warp|hosts)-input-confirm' "${CONTROL_LOG}" ||
                fail '路由状态失败后仍进入直接录入'
        fi
        expectedRouting+=$'\nedit --socks5-off\nprotocol routing-status\nedit --socks5-domains Example.NET, full:Exact.Example.Com, geosite:cn\nedit --socks5-global\nprotocol routing-status\nedit --dns-rules 203.0.113.53 53 Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\nedit --dns-off\nprotocol routing-status'
        [[ "${routingCase}" != flow ]] ||
            expectedRouting+=$'\nedit --hosts-input\nhosts-input-confirm y\nhosts-input-commit'
        expectedRouting+=$'\nedit --hosts-off\nedit --direct-domains Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\nedit --direct-off\nedit --block-domains Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\nedit --block-off\nedit --block-ips-csv 192.0.2.10, 2001:DB8::10, geoip:cn\nedit --block-ips-off\nedit --block-bt\nedit --block-bt-off'
        expectedRouting+=$'\nedit --region both --region-allow Example.NET, full:Exact.Example.Com\nedit --region domain\nedit --region ip'
        expectedRouting+=$'\nedit --region-allow-add Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\nedit --region-allow-remove Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\nedit --region-off'
        expectedRouting+=$'\nedit --ipv6 selective --ipv6-domains Example.NET, full:Exact.Example.Com'
        for ipv6Action in --ipv6-domains-add --ipv6-domains-remove; do
            expectedRouting+=$'\nedit '"${ipv6Action}"' Example.NET, full:Exact.Example.Com'
            expectedRouting+=$'\nipv6-daily-confirm '"${ipv6Action}"' y'
            [[ "${routingCase}" != flow ]] || expectedRouting+=$'\nipv6-daily-commit '"${ipv6Action}"
        done
        expectedRouting+=$'\nedit --ipv6 global\nedit --ipv6-off\nprotocol routing-status'
        expectedRouting+=$'\nprotocol routing-status'
        [[ "${routingCase}" != flow ]] ||
            expectedRouting+=$'\nedit --warp-input\nwarp-input-confirm y\nwarp-input-commit'
        expectedRouting+=$'\nedit --warp-off\nprotocol routing-status'
        for warpAction in '--warp-domains Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN' \
            '--warp-domains-add Example.NET, full:Exact.Example.Com' \
            '--warp-domains-remove Example.NET, full:Exact.Example.Com' \
            '--warp-global' '--warp-family ipv4' '--warp-family ipv6'; do
            expectedRouting+=$'\nedit '"${warpAction}"
            expectedRouting+=$'\nwarp-daily-confirm '"${warpAction%% *}"' y'
            [[ "${routingCase}" != flow ]] || expectedRouting+=$'\nwarp-daily-commit '"${warpAction%% *}"
        done
        expectedRouting+=$'\nprotocol routing-status'
        expectedRouting+=$'\nprotocol routing-status'
        [[ "${routingCase}" != flow ]] ||
            expectedRouting+=$'\nedit --http-relay-input\nhttp-relay-input-confirm y\nhttp-relay-input-commit'
        expectedRouting+=$'\nedit --http-relay-off\nprotocol routing-status'
        expectedRouting+=$'\nedit --direct-domains-add Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\nedit --block-domains-add Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN'
        expectedRouting+=$'\nedit --direct-domains-remove Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\nedit --block-domains-remove Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN'
        expectedRouting+=$'\nedit --block-ips-add-csv 198.51.100.17/24, 2001:DB8::/64\nedit --block-ips-remove-csv 192.0.2.10, 2001:DB8::10\nprotocol routing-status'
        expectedRouting+=$'\nedit --dns-domains-add Example.NET, full:Exact.Example.Com\nedit --dns-domains-remove Example.NET, full:Exact.Example.Com\nprotocol routing-status'
        for socksAction in add remove; do
            expectedRouting+=$'\nprotocol routing-status'
            [[ "${routingCase}" != failed ]] || continue
            expectedRouting+=$'\nedit --socks5-domains-'"${socksAction}"' Example.NET, full:Exact.Example.Com'
            expectedRouting+=$'\nsocks5-daily-confirm --socks5-domains-'"${socksAction}"' y'
            [[ "${routingCase}" != flow ]] ||
                expectedRouting+=$'\nsocks5-daily-commit --socks5-domains-'"${socksAction}"
        done
        grep -Fq '无效选项' "${CONTROL_LOG}" || fail '路由菜单没有保留无效输入后的操作'
        [[ "$(grep -Fc 'fixture-warp-daily-confirm [y/N]' "${CONTROL_LOG}")" -eq 6 ]] ||
            fail 'WARP 日常编辑没有每次只确认一次'
        [[ "$(grep -Fc 'fixture-ipv6-daily-confirm [y/N]' "${CONTROL_LOG}")" -eq 2 ]] ||
            fail 'IPv6 域名增删没有每次只确认一次'
        [[ "${routingCase}" != flow ]] ||
            grep -Fq '精确删除 SOCKS5 域名规则 CSV（删空关闭，需重新启用；' "${CONTROL_LOG}" ||
            fail 'SOCKS5 域名删空后未提示重新启用'
        ;;
    cancel)
        for socksInput in 0 '' n; do
            [[ -z "${expectedRouting}" ]] || expectedRouting+=$'\n'
            expectedRouting+=$'protocol routing-status\nedit --socks5-input\nsocks5-input-confirm '"${socksInput}"
        done
        expectedRouting+=$'\nprotocol routing-status\nprotocol routing-status\nprotocol routing-status\nprotocol routing-status'
        for hostsInput in 0 '' n; do
            expectedRouting+=$'\nprotocol routing-status\nedit --hosts-input\nhosts-input-confirm '"${hostsInput}"
        done
        for warpInput in 0 '' n; do
            expectedRouting+=$'\nprotocol routing-status\nedit --warp-input\nwarp-input-confirm '"${warpInput}"
        done
        for httpRelayInput in 0 '' n; do
            expectedRouting+=$'\nprotocol routing-status\nedit --http-relay-input\nhttp-relay-input-confirm '"${httpRelayInput}"
        done
        ! grep -Fq '操作失败，退出码:' "${CONTROL_LOG}" ||
            fail '直接录入取消被误报为操作失败'
        ;;
    socks5-input-eof|socks5-input-commit-failed)
        # 空退出码匹配全部失败提示，取消时必须一条也没有。
        socksConfirmation=eof socksExit= socksFailureCount=0
        [[ "${routingCase}" != socks5-input-commit-failed ]] ||
            { socksConfirmation=y; socksExit=15; socksFailureCount=1; }
        expectedRouting=$'protocol routing-status\nedit --socks5-input\nsocks5-input-confirm '"${socksConfirmation}"$'\nprotocol routing-status'
        [[ "$(grep -Fc "操作失败，退出码: ${socksExit}" "${CONTROL_LOG}" || true)" -eq "${socksFailureCount}" ]] ||
            fail 'SOCKS5 输入取消被误报失败，或提交失败未显示退出码并继续诊断'
        ;;
    hosts-input-eof|hosts-input-status-failed|hosts-input-commit-failed)
        expectedRouting='protocol routing-status'
        hostsInputExit= hostsInputFailureCount=0
        if [[ "${routingCase}" == hosts-input-status-failed ]]; then
            hostsInputExit=17 hostsInputFailureCount=2
            ! grep -Fq 'fixture-hosts-input-confirm' "${CONTROL_LOG}" ||
                fail 'hosts 状态失败后仍进入整组录入'
        else
            hostsInputConfirmation=eof
            [[ "${routingCase}" != hosts-input-commit-failed ]] ||
                { hostsInputConfirmation=y; hostsInputExit=15; hostsInputFailureCount=1; }
            expectedRouting+=$'\nedit --hosts-input\nhosts-input-confirm '"${hostsInputConfirmation}"
        fi
        expectedRouting+=$'\nprotocol routing-status'
        [[ "$(grep -Fc "操作失败，退出码: ${hostsInputExit}" "${CONTROL_LOG}" || true)" -eq "${hostsInputFailureCount}" ]] ||
            fail 'hosts 整组录入取消被误报失败，或失败后未显示退出码并继续诊断'
        ;;
    warp-eof|warp-input-status-failed|warp-input-commit-failed)
        expectedRouting='protocol routing-status'
        warpInputExit= warpInputFailureCount=0
        if [[ "${routingCase}" == warp-input-status-failed ]]; then
            warpInputExit=17 warpInputFailureCount=2
            ! grep -Fq 'fixture-warp-input-confirm' "${CONTROL_LOG}" ||
                fail 'WARP 状态失败后仍进入 Peer 录入'
        else
            warpInputConfirmation=eof
            [[ "${routingCase}" != warp-input-commit-failed ]] ||
                { warpInputConfirmation=y; warpInputExit=15; warpInputFailureCount=1; }
            expectedRouting+=$'\nedit --warp-input\nwarp-input-confirm '"${warpInputConfirmation}"
        fi
        expectedRouting+=$'\nprotocol routing-status'
        [[ "$(grep -Fc "操作失败，退出码: ${warpInputExit}" "${CONTROL_LOG}" || true)" -eq "${warpInputFailureCount}" ]] ||
            fail 'WARP 录入取消被误报失败，或失败后未显示退出码并继续诊断'
        ;;
    socks5-domains-eof|socks5-domains-status-failed)
        expectedRouting=$'protocol routing-status\nprotocol routing-status'
        if [[ "${routingCase}" == socks5-domains-status-failed ]]; then
            ! grep -Fq 'SOCKS5 域名规则 CSV' "${CONTROL_LOG}" ||
                fail 'SOCKS5 状态失败仍读取域名增删输入'
            [[ "$(grep -Fc '操作失败，退出码: 17' "${CONTROL_LOG}")" -eq 2 ]] ||
                fail 'SOCKS5 增删状态失败未保留菜单'
        fi
        ;;
    domain-replace-*|ip-replace-*|hosts-replace-*|hosts-manage-*)
        replaceConfirmation= replaceExit=0 replaceFailureCount=0
        replaceCase=${routingCase#*-replace-} replaceKind=domain
        replaceVariants=(valid)
        replaceFamilies=(dns direct block ipv6 warp region socks5)
        if [[ "${routingCase}" == ip-replace-* ]]; then
            replaceKind=ip
            replaceFamilies=(ips)
        elif [[ "${routingCase}" == hosts-replace-* ]]; then
            replaceKind=hosts
            replaceFamilies=(hosts)
        elif [[ "${routingCase}" == hosts-manage-* ]]; then
            replaceCase=${routingCase#hosts-manage-}
            replaceFamilies=(hosts-add hosts-remove)
        fi
        case "${replaceCase}" in
        flow) replaceConfirmation=y ;;
        cancel)
            replaceVariants=(old-zero old-empty old-eof new-zero new-empty new-eof)
            ;;
        invalid)
            replaceVariants=(old-invalid new-invalid old-csv new-csv same)
            replaceExit=2
            ;;
        status-failed) replaceExit=17 replaceFailureCount=$((${#replaceFamilies[@]} * 2)) ;;
        state-failed) replaceExit=15 replaceFailureCount=${#replaceFamilies[@]} ;;
        confirm-cancel) replaceConfirmation=n replaceExit=2 replaceFailureCount=${#replaceFamilies[@]} ;;
        confirm-eof) replaceConfirmation=eof replaceExit=2 replaceFailureCount=${#replaceFamilies[@]} ;;
        commit-failed) replaceConfirmation=y replaceExit=15 replaceFailureCount=${#replaceFamilies[@]} ;;
        esac
        for replaceFamily in "${replaceFamilies[@]}"; do
            replaceFlag="--${replaceFamily}-domains-replace"
            [[ "${replaceFamily}" != ips ]] || replaceFlag=--block-ips-replace
            [[ "${replaceFamily}" != region ]] || replaceFlag=--region-allow-replace
            [[ "${replaceFamily}" != hosts ]] || replaceFlag=--hosts-replace
            if [[ "${replaceFamily}" == hosts-add ]]; then
                replaceFlag=--hosts-add replaceKind=hosts-add
                [[ "${replaceCase}" != invalid ]] ||
                    replaceVariants=(old-invalid new-invalid old-csv new-csv)
            elif [[ "${replaceFamily}" == hosts-remove ]]; then
                replaceFlag=--hosts-remove replaceKind=hosts-remove
                [[ "${replaceCase}" != cancel ]] ||
                    replaceVariants=(old-zero old-empty old-eof)
                [[ "${replaceCase}" != invalid ]] ||
                    replaceVariants=(old-invalid old-csv)
            fi
            for replaceVariant in "${replaceVariants[@]}"; do
                [[ -z "${expectedRouting}" ]] || expectedRouting+=$'\n'
                expectedRouting+='protocol routing-status'
                [[ "${replaceCase}" != cancel && "${replaceCase}" != status-failed ]] || continue
                replaceOld=full:Exact.Example.Com replaceNew=full:Next.Example.NET
                [[ "${replaceFamily}" != ips ]] ||
                    { replaceOld=2001:0DB8::1/64; replaceNew=2001:db8::2/64; }
                [[ "${replaceFamily}" != hosts* ]] ||
                    { replaceOld=Exact.Example.Com; replaceNew=2001:0DB8::10; }
                case "${replaceVariant}" in
                old-invalid) replaceOld=regexp:bad ;;
                new-invalid) replaceNew=regexp:bad ;;
                old-csv) replaceOld=full:Exact.Example.Com,full:Second.Example.Com ;;
                new-csv) replaceNew=full:Next.Example.NET,full:Second.Example.Com ;;
                same) replaceNew=${replaceOld} ;;
                esac
                expectedRouting+=$'\n'"edit ${replaceFlag} ${replaceOld}"
                [[ "${replaceFamily}" == hosts-remove ]] || expectedRouting+=" ${replaceNew}"
                [[ "${replaceCase}" != invalid ]] || replaceFailureCount=$((replaceFailureCount + 1))
                [[ -z "${replaceConfirmation}" ]] ||
                    expectedRouting+=$'\n'"${replaceKind}-replace-confirm ${replaceFlag} ${replaceConfirmation}"
                [[ "${replaceCase}" != flow ]] ||
                    expectedRouting+=$'\n'"${replaceKind}-replace-commit ${replaceFlag}"
            done
            expectedRouting+=$'\nprotocol routing-status'
        done
        replaceConfirmCount=0
        [[ -z "${replaceConfirmation}" ]] || replaceConfirmCount=${#replaceFamilies[@]}
        replaceConfirmPattern="fixture-${replaceKind}-replace-confirm \\[y/N\\]"
        [[ "${routingCase}" != hosts-manage-* ]] ||
            replaceConfirmPattern='fixture-hosts-(add|remove)-replace-confirm \[y/N\]'
        [[ "$(grep -Ec "${replaceConfirmPattern}" "${CONTROL_LOG}" || true)" -eq "${replaceConfirmCount}" ]] ||
            fail '规则单条替换未保持每次一个 CLI 确认'
        [[ "$(grep -Fc "操作失败，退出码: ${replaceExit}" "${CONTROL_LOG}" || true)" -eq "${replaceFailureCount}" ]] ||
            fail '规则单条替换失败未显示退出码并继续诊断'
        if [[ "${replaceCase}" == status-failed ]]; then
            replacePrompt='旧域名规则（单条；'
            [[ "${replaceKind}" != ip ]] || replacePrompt='旧 IP/CIDR 规则（单条字面'
            [[ "${replaceKind}" != hosts ]] || replacePrompt='已有 hosts 精确域名（0 返回）'
            [[ "${routingCase}" != hosts-manage-* ]] || replacePrompt='hosts 精确域名（'
            ! grep -Fq "${replacePrompt}" "${CONTROL_LOG}" ||
                fail '路由状态失败后仍然读取替换规则'
        fi
        if [[ "${routingCase}" == hosts-manage-* && "${replaceCase}" != status-failed ]]; then
            grep -Fq '最后一项关闭 hosts' "${CONTROL_LOG}" ||
                fail 'hosts 精确删除没有提示最后一项关闭 hosts'
        fi
        ;;
    selective-domains-invalid|selective-domains-state-failed|selective-domains-confirm-cancel|selective-domains-confirm-eof|selective-domains-commit-failed)
        selectiveInput=Example.NET selectiveExit=2 selectiveConfirmation=
        [[ "${routingCase}" != selective-domains-invalid ]] || selectiveInput=regexp:bad
        case "${routingCase}" in
        selective-domains-confirm-cancel) selectiveConfirmation=n ;;
        selective-domains-confirm-eof) selectiveConfirmation=eof ;;
        selective-domains-commit-failed) selectiveConfirmation=y selectiveExit=15 ;;
        selective-domains-state-failed) selectiveExit=15 ;;
        esac
        for selectiveFamily in ipv6 warp socks5; do
            for selectiveAction in add remove; do
                selectiveFlag="--${selectiveFamily}-domains-${selectiveAction}"
                [[ -z "${expectedRouting}" ]] || expectedRouting+=$'\n'
                [[ "${selectiveFamily}" != socks5 ]] || expectedRouting+='protocol routing-status'$'\n'
                expectedRouting+="edit ${selectiveFlag} ${selectiveInput}"
                [[ -z "${selectiveConfirmation}" ]] ||
                    expectedRouting+=$'\n'"${selectiveFamily}-daily-confirm ${selectiveFlag} ${selectiveConfirmation}"
            done
            expectedRouting+=$'\nprotocol routing-status'
            selectiveConfirmCount=0
            [[ -z "${selectiveConfirmation}" ]] || selectiveConfirmCount=2
            [[ "$(grep -Fc "fixture-${selectiveFamily}-daily-confirm [y/N]" "${CONTROL_LOG}" || true)" -eq "${selectiveConfirmCount}" ]] ||
                fail "${selectiveFamily} 域名增删确认次数错误"
        done
        [[ "$(grep -Fc "操作失败，退出码: ${selectiveExit}" "${CONTROL_LOG}")" -eq 6 ]] ||
            fail '选择性出站域名增删失败未显示退出码并继续诊断'
        ;;
    warp-confirm-cancel|warp-confirm-eof)
        warpConfirmation=n
        [[ "${routingCase}" != warp-confirm-eof ]] || warpConfirmation=eof
        expectedRouting="edit --warp-domains Example.NET"$'\n'"warp-daily-confirm --warp-domains ${warpConfirmation}"
        expectedRouting+=$'\nedit --warp-global\n'"warp-daily-confirm --warp-global ${warpConfirmation}"
        expectedRouting+=$'\nedit --warp-family ipv4\n'"warp-daily-confirm --warp-family ${warpConfirmation}"
        expectedRouting+=$'\nprotocol routing-status'
        [[ "$(grep -Fc 'fixture-warp-daily-confirm [y/N]' "${CONTROL_LOG}")" -eq 3 ]] ||
            fail 'WARP 确认取消或 EOF 后重复确认'
        ;;
    dns-explicit-port)
        expectedRouting='edit --dns-rules 203.0.113.53 5353 Example.NET'
        ;;
    dns-invalid)
        expectedRouting='edit --dns-rules 203.0.113.53 53 regexp:bad'
        [[ "$(grep -Fc 'DNS 端口必须为 1–65535，请重新选择。' "${CONTROL_LOG}")" -eq 1 &&
            "$(grep -Fc 'DNS 域名规则 CSV（' "${CONTROL_LOG}")" -eq 1 ]] ||
            fail 'DNS 非法端口未立即返回菜单，或仍追问域名规则'
        [[ "$(grep -Fc '操作失败，退出码: 2' "${CONTROL_LOG}")" -eq 1 ]] ||
            fail 'DNS 非法 CSV 未显示用法错误并保留菜单'
        ;;
    dns-failed)
        expectedRouting='edit --dns-rules 203.0.113.53 53 Example.NET'
        grep -Fq '操作失败，退出码: 15' "${CONTROL_LOG}" ||
            fail 'DNS 规则提交失败未显示状态错误并保留菜单'
        ;;
    direct-block-invalid)
        expectedRouting=$'edit --direct-domains regexp:bad\nedit --block-domains regexp:bad'
        [[ "$(grep -Fc '操作失败，退出码: 2' "${CONTROL_LOG}")" -eq 2 ]] ||
            fail 'Direct/Block 非法 CSV 未显示用法错误并保留菜单'
        ;;
    direct-block-add-invalid)
        expectedRouting=$'edit --direct-domains-add regexp:bad\nedit --block-domains-add regexp:bad'
        [[ "$(grep -Fc '操作失败，退出码: 2' "${CONTROL_LOG}")" -eq 2 ]] ||
            fail 'Direct/Block 追加非法 CSV 未显示用法错误并保留菜单'
        ;;
    direct-block-add-failed)
        expectedRouting=$'edit --direct-domains-add Example.NET\nedit --block-domains-add Example.NET'
        [[ "$(grep -Fc '操作失败，退出码: 15' "${CONTROL_LOG}")" -eq 2 ]] ||
            fail 'Direct/Block 追加失败未显示状态错误并保留菜单'
        ;;
    direct-block-remove-invalid)
        expectedRouting=$'edit --direct-domains-remove regexp:bad\nedit --block-domains-remove regexp:bad'
        [[ "$(grep -Fc '操作失败，退出码: 2' "${CONTROL_LOG}")" -eq 2 ]] ||
            fail 'Direct/Block 删除非法 CSV 未显示用法错误并保留菜单'
        ;;
    direct-block-remove-failed)
        expectedRouting=$'edit --direct-domains-remove Example.NET\nedit --block-domains-remove Example.NET'
        [[ "$(grep -Fc '操作失败，退出码: 15' "${CONTROL_LOG}")" -eq 2 ]] ||
            fail 'Direct/Block 删除缺项未显示状态错误并保留菜单'
        ;;
    block-ips-change-failed)
        expectedRouting=$'edit --block-ips-csv 192.0.2.10, geoip:cn\nedit --block-ips-add-csv 198.51.100.17/24, 2001:DB8::/64\nedit --block-ips-remove-csv 192.0.2.10, 2001:DB8::10\nprotocol routing-status'
        [[ "$(grep -Fc '操作失败，退出码: 15' "${CONTROL_LOG}")" -eq 3 ]] ||
            fail 'IP/CIDR 录入失败未显示状态错误并继续诊断'
        ;;
    dns-domains-change-invalid)
        expectedRouting=$'edit --dns-domains-add regexp:bad\nedit --dns-domains-remove regexp:bad'
        [[ "$(grep -Fc '操作失败，退出码: 2' "${CONTROL_LOG}")" -eq 2 ]] ||
            fail 'DNS 分流域名增删非法 CSV 未显示用法错误并保留菜单'
        ;;
    dns-domains-change-failed)
        expectedRouting=$'edit --dns-domains-add Example.NET\nedit --dns-domains-remove Example.NET\nprotocol routing-status'
        [[ "$(grep -Fc '操作失败，退出码: 15' "${CONTROL_LOG}")" -eq 2 ]] ||
            fail 'DNS 分流域名增删失败未显示状态错误并继续诊断'
        ;;
    region-allow-invalid)
        expectedRouting=$'edit --region-allow-add regexp:bad\nedit --region-allow-remove regexp:bad'
        [[ "$(grep -Fc '操作失败，退出码: 2' "${CONTROL_LOG}")" -eq 2 ]] ||
            fail '区域自定义例外非法 CSV 未显示用法错误并保留菜单'
        ;;
    region-allow-failed)
        expectedRouting=$'edit --region-allow-add Example.NET\nedit --region-allow-remove Example.NET'
        [[ "$(grep -Fc '操作失败，退出码: 15' "${CONTROL_LOG}")" -eq 2 ]] ||
            fail '区域自定义例外增删失败未显示状态错误并保留菜单'
        ;;
    region-mode-flow|region-mode-cancel|region-mode-failed)
        if [[ "${routingCase}" == region-mode-cancel ]]; then
            expectedRouting='protocol routing-status'
            [[ "$(grep -Fc '无效模式，请重新选择' "${CONTROL_LOG}")" -eq 2 ]] ||
                fail '区域非法模式未保留菜单'
        else
            expectedRouting=$'edit --region-mode both\nedit --region-mode domain\nedit --region-mode ip\nprotocol routing-status'
        fi
        if [[ "${routingCase}" == region-mode-failed ]]; then
            [[ "$(grep -Fc '操作失败，退出码: 15' "${CONTROL_LOG}")" -eq 3 ]] ||
                fail '区域模式切换失败未显示状态错误并继续诊断'
        fi
        ;;
    access-control-flow|access-control-cancel|access-control-failed)
        accessControlConfirmCount=1 accessControlFailureCount=0 accessControlExit=2
        if [[ "${routingCase}" == access-control-cancel ]]; then
            expectedRouting=$'edit --access-control-off\naccess-control-confirm n\nedit --access-control-off\naccess-control-confirm eof'
            accessControlConfirmCount=2 accessControlFailureCount=2
        else
            expectedRouting=$'edit --access-control-off\naccess-control-confirm y'
            if [[ "${routingCase}" == access-control-flow ]]; then
                expectedRouting+=$'\naccess-control-commit'
            else
                accessControlFailureCount=1 accessControlExit=15
            fi
        fi
        expectedRouting+=$'\nprotocol routing-status'
        [[ "$(grep -Fc 'fixture-access-control-confirm [y/N]' "${CONTROL_LOG}")" -eq "${accessControlConfirmCount}" ]] ||
            fail '移除全部访问控制没有每次只确认一次'
        [[ "$(grep -Fc "操作失败，退出码: ${accessControlExit}" "${CONTROL_LOG}" || true)" -eq "${accessControlFailureCount}" ]] ||
            fail '移除全部访问控制取消或提交失败后未显示退出码并继续诊断'
        ;;
    upstream-flow|upstream-cancel|upstream-status-failed|upstream-commit-failed)
        if [[ "${routingCase}" == upstream-cancel ]]; then
            expectedRouting=$(printf 'protocol routing-status\n%.0s' {1..7})
        elif [[ "${routingCase}" == upstream-status-failed ]]; then
            expectedRouting=$'protocol routing-status\nprotocol routing-status\nprotocol routing-status'
            ! grep -Fq '上游服务器 IPv4/IPv6（0 返回）' "${CONTROL_LOG}" ||
                fail '上游状态失败后仍然读取编辑输入'
            [[ "$(grep -Fc '操作失败，退出码: 17' "${CONTROL_LOG}")" -eq 3 ]] ||
                fail '上游状态失败未显示退出码并继续诊断'
        else
            for upstreamFamily in dns socks5; do
                upstreamServer=2001:0DB8::53 upstreamPort=5353
                [[ "${upstreamFamily}" != socks5 ]] ||
                    { upstreamServer=203.0.113.108; upstreamPort=1088; }
                [[ -z "${expectedRouting}" ]] || expectedRouting+=$'\n'
                expectedRouting+=$'protocol routing-status\n'"edit --${upstreamFamily}-upstream ${upstreamServer} ${upstreamPort}"
                expectedRouting+=$'\n'"upstream-confirm --${upstreamFamily}-upstream y"
                [[ "${routingCase}" != upstream-flow ]] ||
                    expectedRouting+=$'\n'"upstream-commit --${upstreamFamily}-upstream"
            done
            expectedRouting+=$'\nprotocol routing-status'
            [[ "$(grep -Fc 'fixture-upstream-confirm [y/N]' "${CONTROL_LOG}")" -eq 2 ]] ||
                fail '上游编辑没有每次只确认一次'
            if [[ "${routingCase}" == upstream-commit-failed ]]; then
                [[ "$(grep -Fc '操作失败，退出码: 15' "${CONTROL_LOG}")" -eq 2 ]] ||
                    fail '上游提交失败未显示退出码并继续诊断'
            fi
        fi
        ;;
    http-relay-flow|http-relay-cancel|http-relay-status-failed|http-relay-commit-failed)
        httpRelayConfirmCount=4 httpRelayFailureCount=0 httpRelayExit=15
        if [[ "${routingCase}" == http-relay-cancel ]]; then
            for httpRelayInput in 0 '' n; do
                [[ -z "${expectedRouting}" ]] || expectedRouting+=$'\n'
                expectedRouting+=$'protocol routing-status\nedit --http-relay-input\nhttp-relay-input-confirm '"${httpRelayInput}"
            done
            expectedRouting+=$'\n'"$(printf 'protocol routing-status\n%.0s' {1..12})"
            expectedRouting+=$'\nprotocol routing-status\nedit --http-relay-port 18888\nhttp-relay-confirm --http-relay-port n'
            expectedRouting+=$'\nprotocol routing-status\nedit --http-relay-sources 192.0.2.11, 2001:0DB8::/64\nhttp-relay-confirm --http-relay-sources eof'
            expectedRouting+=$'\nprotocol routing-status'
            httpRelayConfirmCount=2 httpRelayFailureCount=2 httpRelayExit=2
        elif [[ "${routingCase}" == http-relay-status-failed ]]; then
            expectedRouting=$(printf 'protocol routing-status\n%.0s' {1..6})
            httpRelayConfirmCount=0 httpRelayFailureCount=6 httpRelayExit=17
            ! grep -Eq 'fixture-http-relay-input-confirm|新 HTTP 中继端口|HTTP 中继来源 IP/CIDR CSV' "${CONTROL_LOG}" ||
                fail 'HTTP 中继状态失败后仍读取编辑输入'
        else
            expectedRouting=$'protocol routing-status\nedit --http-relay-input\nhttp-relay-input-confirm y'
            [[ "${routingCase}" != http-relay-flow ]] ||
                expectedRouting+=$'\nhttp-relay-input-commit'
            for httpRelayFlag in --http-relay-port --http-relay-sources --http-relay-sources-add --http-relay-sources-remove; do
                httpRelayInput='192.0.2.11, 2001:0DB8::/64'
                [[ "${httpRelayFlag}" != --http-relay-port ]] || httpRelayInput=18888
                [[ -z "${expectedRouting}" ]] || expectedRouting+=$'\n'
                expectedRouting+=$'protocol routing-status\n'"edit ${httpRelayFlag} ${httpRelayInput}"
                expectedRouting+=$'\n'"http-relay-confirm ${httpRelayFlag} y"
                [[ "${routingCase}" != http-relay-flow ]] ||
                    expectedRouting+=$'\n'"http-relay-commit ${httpRelayFlag}"
            done
            expectedRouting+=$'\nprotocol routing-status'
            [[ "${routingCase}" != http-relay-commit-failed ]] || httpRelayFailureCount=5
        fi
        [[ "$(grep -Fc 'fixture-http-relay-confirm [y/N]' "${CONTROL_LOG}" || true)" -eq "${httpRelayConfirmCount}" ]] ||
            fail 'HTTP 中继日常编辑没有每次只确认一次'
        [[ "$(grep -Fc "操作失败，退出码: ${httpRelayExit}" "${CONTROL_LOG}" || true)" -eq "${httpRelayFailureCount}" ]] ||
            fail 'HTTP 中继取消或编辑失败未显示退出码并继续诊断'
        for label in '1. 直接录入认证与来源规则' '4. 修改中继端口' '5. 替换来源允许名单' '6. 追加来源允许名单' \
            '7. 精确删除来源允许名单（删空拒绝）'; do
            grep -Fq "${label}" "${CONTROL_LOG}" || fail "HTTP 中继菜单缺少: ${label}"
        done
        ;;
    http-relay-eof)
        expectedRouting=$'protocol routing-status\nedit --http-relay-input\nhttp-relay-input-confirm eof\nprotocol routing-status'
        ! grep -Fq '操作失败，退出码:' "${CONTROL_LOG}" ||
            fail 'HTTP 中继输入 EOF 被误报为操作失败'
        ;;
    block-ips-mode-flow|block-ips-mode-failed)
        for flag in --block-ips-resolve --block-ips-literal; do
            expectedRouting+="${expectedRouting:+$'\n'}edit ${flag}"
            expectedRouting+=$'\nblock-ips-mode-confirm '"${flag} y"
            [[ "${routingCase}" != block-ips-mode-flow ]] ||
                expectedRouting+=$'\nblock-ips-mode-commit '"${flag}"
        done
        expectedRouting+=$'\nprotocol routing-status'
        if [[ "${routingCase}" == block-ips-mode-failed ]]; then
            [[ "$(grep -Fc '操作失败，退出码: 15' "${CONTROL_LOG}")" -eq 2 ]] ||
                fail 'IP 模式失败未报告退出码或没有返回菜单'
        fi
        for label in '45. IP 阻断加入域名解析结果（sing-box）' '46. IP 阻断仅匹配字面地址'; do
            grep -Fq "${label}" "${CONTROL_LOG}" || fail "IP 模式菜单缺少: ${label}"
        done
        ;;
    tun-flow|tun-cancel|tun-status-failed|tun-commit-failed)
        tunConfirmCount=2 tunFailureCount=0 tunExit=15
        expectedRouting='protocol tun-status'
        if [[ "${routingCase}" == tun-status-failed ]]; then
            tunConfirmCount=0 tunFailureCount=1 tunExit=17
        else
            for tunAction in --tun-enable --tun-off; do
                if [[ "${routingCase}" == tun-cancel ]]; then
                    expectedRouting+=$'\nedit '"${tunAction}"$'\ntun-confirm '"${tunAction}"' n'
                    expectedRouting+=$'\nedit '"${tunAction}"$'\ntun-confirm '"${tunAction}"' eof'
                else
                    expectedRouting+=$'\nedit '"${tunAction}"$'\ntun-confirm '"${tunAction}"' y'
                    [[ "${routingCase}" != tun-flow ]] ||
                        expectedRouting+=$'\ntun-commit '"${tunAction}"
                fi
            done
            expectedRouting+=$'\nprotocol tun-status'
            [[ "${routingCase}" != tun-cancel ]] ||
                { tunConfirmCount=4; tunFailureCount=4; tunExit=2; }
            [[ "${routingCase}" != tun-commit-failed ]] || tunFailureCount=2
            for warning in '宿主全局' IPv6 '拒绝'; do
                grep -Fq "${warning}" "${CONTROL_LOG}" || fail "TUN 启用未提示: ${warning}"
            done
        fi
        [[ "$(grep -Fc 'fixture-tun-confirm [y/N]' "${CONTROL_LOG}" || true)" -eq "${tunConfirmCount}" ]] ||
            fail 'TUN 操作没有每次只确认一次'
        [[ "$(grep -Fc "操作失败，退出码: ${tunExit}" "${CONTROL_LOG}" || true)" -eq "${tunFailureCount}" ]] ||
            fail 'TUN 取消或失败未显示退出码并继续菜单'
        for label in '44. TUN 管理' '1. 查看状态' '2. 启用 TUN' '3. 关闭 TUN'; do
            grep -Fq "${label}" "${CONTROL_LOG}" || fail "TUN 菜单缺少: ${label}"
        done
        ;;
    tproxy-output-flow|tproxy-output-cancel|tproxy-output-failed)
        expectedRouting=
        if [[ "${routingCase}" == tproxy-output-cancel ]]; then
            expectedRouting=$(printf 'protocol tproxy-status\n%.0s' {1..3})
        else
            for tproxyAction in '--tproxy-settings 31399 257 --tproxy-family dual --tproxy-output-uid 65534' \
                '--tproxy-settings 31399 257 --tproxy-family dual --tproxy-output-off'; do
                [[ -z "${expectedRouting}" ]] || expectedRouting+=$'\n'
                expectedRouting+='protocol tproxy-status'
                expectedRouting+=$'\nedit '"${tproxyAction}"$'\ntproxy-confirm --tproxy-settings y'
                [[ "${routingCase}" != tproxy-output-flow ]] ||
                    expectedRouting+=$'\ntproxy-commit --tproxy-settings'
            done
        fi
        if [[ "${routingCase}" == tproxy-output-failed ]]; then
            [[ "$(grep -Fc '操作失败，退出码: 15' "${CONTROL_LOG}" || true)" -eq 2 ]] ||
                fail 'TProxy OUTPUT 失败后没有继续菜单'
        fi
        for label in '5. 设置本机转发 UID' '6. 关闭本机转发（保留 PREROUTING）'; do
            grep -Fq "${label}" "${CONTROL_LOG}" || fail "TProxy 菜单缺少: ${label}"
        done
        ;;
    tproxy-flow|tproxy-cancel|tproxy-status-failed|tproxy-commit-failed)
        tproxyConfirmCount=4 tproxyFailureCount=0 tproxyExit=15
        if [[ "${routingCase}" == tproxy-status-failed ]]; then
            expectedRouting=$(printf 'protocol tproxy-status\n%.0s' {1..6})
            tproxyConfirmCount=0 tproxyFailureCount=6 tproxyExit=17
            ! grep -Eq 'TProxy (端口|mark|地址族 ipv4/ipv6/dual) \[|本机转发 UID（' "${CONTROL_LOG}" ||
                fail 'TProxy 状态失败后仍读取参数'
        elif [[ "${routingCase}" == tproxy-cancel ]]; then
            expectedRouting=$(printf 'protocol tproxy-status\n%.0s' {1..12})
            expectedRouting+=$'\nprotocol tproxy-status\nedit --tproxy-enable 31298 129 --tproxy-family ipv4\ntproxy-confirm --tproxy-enable n'
            expectedRouting+=$'\nprotocol tproxy-status\nedit --tproxy-settings 31399 257 --tproxy-family dual\ntproxy-confirm --tproxy-settings eof'
            expectedRouting+=$'\nedit --tproxy-off\ntproxy-confirm --tproxy-off n'
            expectedRouting+=$'\nedit --tproxy-off\ntproxy-confirm --tproxy-off eof\nprotocol tproxy-status'
            tproxyFailureCount=4 tproxyExit=2
        else
            expectedRouting='protocol tproxy-status'
            for tproxyAction in '--tproxy-enable 31298 129 --tproxy-family ipv6' \
                '--tproxy-settings 31399 257 --tproxy-family dual' \
                '--tproxy-settings 32000 130 --tproxy-family ipv4' '--tproxy-off'; do
                [[ "${tproxyAction}" == --tproxy-off ]] || expectedRouting+=$'\nprotocol tproxy-status'
                expectedRouting+=$'\nedit '"${tproxyAction}"
                expectedRouting+=$'\ntproxy-confirm '"${tproxyAction%% *}"' y'
                [[ "${routingCase}" != tproxy-flow ]] ||
                    expectedRouting+=$'\ntproxy-commit '"${tproxyAction%% *}"
            done
            expectedRouting+=$'\nprotocol tproxy-status'
            [[ "${routingCase}" != tproxy-commit-failed ]] || tproxyFailureCount=4
        fi
        [[ "$(grep -Fc 'fixture-tproxy-confirm [y/N]' "${CONTROL_LOG}" || true)" -eq "${tproxyConfirmCount}" ]] ||
            fail 'TProxy 操作没有每次只确认一次'
        [[ "$(grep -Fc "操作失败，退出码: ${tproxyExit}" "${CONTROL_LOG}" || true)" -eq "${tproxyFailureCount}" ]] ||
            fail 'TProxy 取消或失败未显示退出码并继续菜单'
        for label in '43. TProxy 管理' '1. 查看状态' '2. 启用 TProxy' '3. 修改 TProxy 参数' '4. 关闭 TProxy'; do
            grep -Fq "${label}" "${CONTROL_LOG}" || fail "TProxy 菜单缺少: ${label}"
        done
        ;;
    esac
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedRouting}" ]] ||
        fail "路由 ${routingCase} 参数分发错误或取消后执行操作"
    if [[ "${routingCase}" == flow ]]; then
        for label in '5. 路由与访问控制' '9. 完整路由维护' '┌─ Docker 路由与出站' \
            '1. 启用 SOCKS5 出站' '2. 关闭 SOCKS5 出站' \
            '3. 查看路由状态' '4. 替换 SOCKS5 域名规则' '5. 切换 SOCKS5 全局出站' \
            '6. 设置 DNS 分流' '7. 关闭 DNS 分流' '8. 直接录入 hosts（整组替换）' \
            '9. 关闭 hosts 覆盖' '10. 替换 Direct 直连例外' '11. 关闭 Direct 直连例外' \
            '12. 替换 Block 域名阻断' '13. 关闭 Block 域名阻断' '14. 设置 IP/CIDR 阻断' \
            '15. 关闭 IP/CIDR 阻断' '16. 启用 BT 协议阻断' '17. 关闭 BT 协议阻断' \
            '18. 区域阻断策略' '1. 屏蔽 geosite:cn + geoip:cn' '2. 仅屏蔽 geosite:cn' \
            '3. 仅屏蔽 geoip:cn' '4. 关闭区域策略' \
            '5. 追加自定义直连例外' '6. 删除自定义直连例外' \
            '7. 单条替换自定义直连例外' '8. 查看路由状态' \
            '9. 仅切换已有区域模式（保留自定义例外）' \
            '替换自定义直连例外规则（逗号分隔，留空清空，0 返回）' '19. IPv6 域名出站' \
            '1. 替换 IPv6 域名规则' '2. IPv6 默认出站' '3. 关闭 IPv6 出站策略' \
            '5. 追加 IPv6 域名规则' '6. 精确删除 IPv6 域名规则' \
            '精确删除 IPv6 域名规则 CSV（删空关闭；domain:/full:/keyword:/geosite:，0 返回）' \
            '7. 单条替换 IPv6 域名规则' \
            '1. 直接录入 WARP Peer' '2. 关闭 WARP 出站' '4. 替换 WARP 域名规则' \
            '5. 切换 WARP 全局出站' '6. 切换 WARP IPv4 隧道地址族' '7. 切换 WARP IPv6 隧道地址族' \
            '8. 追加 WARP 域名规则' '9. 精确删除 WARP 域名规则' \
            '精确删除 WARP 域名规则 CSV（删空关闭，需重新录入或导入 WARP；domain:/full:/keyword:/geosite:，0 返回）' \
            '10. 单条替换 WARP 域名规则' \
            '22. 追加 Direct 直连例外' '23. 追加 Block 域名阻断' \
            '24. 删除 Direct 直连例外' '25. 删除 Block 域名阻断' \
            '26. 追加 IP/CIDR 阻断' '27. 精确删除 IP/CIDR 阻断' \
            'IP/CIDR 规则 CSV（字面 IP/CIDR 或 geoip:cn，逗号分隔，0 返回）' \
            '精确删除按完整字符串匹配，删空关闭手工 IP 阻断。' \
            '28. 追加 DNS 分流域名' '29. 精确删除 DNS 分流域名' \
            '30. 单条替换 DNS 分流域名' '31. 单条替换 Direct 直连例外' \
            '32. 单条替换 Block 域名阻断' '33. 单条替换 IP/CIDR 阻断' \
            '34. 追加 SOCKS5 域名规则' '35. 精确删除 SOCKS5 域名规则' \
            '36. 单条替换 SOCKS5 域名规则' '37. 单项替换 hosts 地址' \
            '38. 新增 hosts 精确映射' '39. 精确删除 hosts 映射' \
            '40. 移除全部访问控制' '41. 修改已有 DNS 上游' '42. 修改已有 SOCKS5 上游' '0. 返回'; do
            grep -Fq "${label}" "${CONTROL_LOG}" || fail "路由菜单缺少: ${label}"
        done
    elif [[ "${routingCase}" == failed ]]; then
        grep -Fq '操作失败，退出码: 15' "${CONTROL_LOG}" || fail '路由提交失败未显示退出码'
        grep -Fq '操作失败，退出码: 17' "${CONTROL_LOG}" || fail '路由诊断失败后没有继续菜单'
    fi
done
unset SITE_EDIT_STATUS ROUTING_STATUS TPROXY_STATUS TUN_STATUS SELECTIVE_EDIT_PRECHECK_STATUS DOMAIN_REPLACE_PRECHECK_STATUS
fi

if [[ "${MENU_SCOPE}" == routing || "${MENU_SCOPE}" == tun || "${MENU_SCOPE}" == block-ips-resolved ]]; then
    printf 'docker-menu-%s-regression-ok\n' "${MENU_SCOPE}"
    exit 0
fi

if [[ "${MENU_SCOPE}" == full || "${MENU_SCOPE}" == control ]]; then
: >"${TLS_WIZARD_ACTIONS}"
runPty control-dispatch control flow "${TLS_WIZARD_CLI}" menu
for controlLabel in '4. 控制连接' '1. 查看角色状态' '2. 初始化主控' '3. 邀请或轮换凭据' \
    '4. 撤销授权' '5. 接入被控角色' '6. 同步受管账号' '7. 验证 Peer 来源' '8. 手动轮转认证日志' \
    '9. 查看自动轮转状态' '10. 启用每小时轮转检查' '11. 停用自动轮转' \
    '12. 查看自动同步状态' '13. 启用或更新自动同步' '14. 停用自动同步' \
    '15. 重映射受管账号入口（同连接）' '16. 更新主控 API 端口' \
    '17. 被控同身份重连' '19. 更换主控身份（同隧道）' '20. 升级多 Peer 主控' \
    '21. 查看控制 Peer' '22. 登记控制 Peer' '23. 移除控制 Peer' '0. 返回'; do
    grep -Fq "${controlLabel}" "${CONTROL_LOG}" || fail "missing control menu item: ${controlLabel}"
done
[[ "$(<"${TLS_WIZARD_ACTIONS}")" == $'control status\ncontrol init --address 10.77.0.1 --port 19443 --peer-address 10.77.0.2\ncontrol-confirm y\ncontrol-commit' ]] ||
    fail 'control menu dispatched incorrect arguments or bypassed the CLI confirmation'
[[ "$(grep -Fc 'fixture-control-confirm [y/N]' "${CONTROL_LOG}")" -eq 1 ]] ||
    fail 'control initialization did not confirm exactly once'
for controlCase in cancel input-eof confirm-eof failed; do
    : >"${TLS_WIZARD_ACTIONS}"
    export CONTROL_INIT_STATUS=0
    [[ "${controlCase}" != failed ]] || CONTROL_INIT_STATUS=17
    runPty "control-${controlCase}" control "${controlCase}" "${TLS_WIZARD_CLI}" menu
    expectedControl=
    case "${controlCase}" in
    cancel|confirm-eof|failed)
        expectedControl='control init --address 10.77.0.1 --port 18443 --peer-address 10.77.0.2'
        case "${controlCase}" in
        cancel) expectedControl+=$'\ncontrol-confirm n' ;;
        confirm-eof) expectedControl+=$'\ncontrol-confirm eof' ;;
        failed) expectedControl+=$'\ncontrol-confirm y\ncontrol status' ;;
        esac
        ;;
    esac
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedControl}" ]] ||
        fail "control ${controlCase} committed after cancellation or dispatched incorrect arguments"
    [[ "${controlCase}" != failed ]] ||
        grep -Fq '操作失败，退出码: 17' "${CONTROL_LOG}" || fail 'failed control initialization was not reported'
done
unset CONTROL_INIT_STATUS
for controlCase in peers peers-cancel peers-input-eof peers-confirm-eof peers-failed; do
    : >"${TLS_WIZARD_ACTIONS}"
    export CONTROL_INIT_STATUS=0 CONTROL_DIAGNOSTIC_STATUS=0
    if [[ "${controlCase}" == peers-failed ]]; then
        CONTROL_INIT_STATUS=17 CONTROL_DIAGNOSTIC_STATUS=17
    fi
    runPty "control-${controlCase}" control "${controlCase}" "${TLS_WIZARD_CLI}" menu
    expectedControl= expectedConfirmations=0
    case "${controlCase}" in
    peers|peers-failed)
        for controlAction in 'upgrade' 'peers list' 'peers add --peer-address 10.77.0.3' \
            'peers remove --peer-id 55555555-5555-4555-8555-555555555555' \
            'invite --output /root/padm-invite.json --expires-in 3600 --peer-id 55555555-5555-4555-8555-555555555555' \
            'revoke --peer-id 55555555-5555-4555-8555-555555555555' \
            'source-check --peer-id 55555555-5555-4555-8555-555555555555' 'status'; do
            [[ -z "${expectedControl}" ]] || expectedControl+=$'\n'
            expectedControl+="control ${controlAction}"
            case "${controlAction}" in
            'peers list'|source-check*|status) ;;
            *)
                expectedControl+=$'\ncontrol-confirm y'
                [[ "${controlCase}" != peers ]] || expectedControl+=$'\ncontrol-commit'
                expectedConfirmations=$((expectedConfirmations + 1))
                ;;
            esac
        done
        ;;
    peers-cancel) expectedControl=$'control upgrade\ncontrol-confirm n'; expectedConfirmations=1 ;;
    peers-confirm-eof) expectedControl=$'control upgrade\ncontrol-confirm eof'; expectedConfirmations=1 ;;
    esac
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedControl}" ]] ||
        fail "多 Peer 菜单 ${controlCase} 目标错误、重复执行或取消后提交"
    [[ "$(grep -Fc 'fixture-control-confirm [y/N]' "${CONTROL_LOG}" || true)" -eq "${expectedConfirmations}" ]] ||
        fail "多 Peer 菜单 ${controlCase} 未复用 CLI 单次确认"
    [[ "${controlCase}" != peers-failed ]] ||
        [[ "$(grep -Fc '操作失败，退出码: 17' "${CONTROL_LOG}")" -eq 6 ]] ||
        fail '多 Peer 操作失败后未报告并继续菜单'
done
unset CONTROL_INIT_STATUS CONTROL_DIAGNOSTIC_STATUS
for controlCase in endpoint endpoint-input-cancel endpoint-input-eof endpoint-confirm-cancel endpoint-confirm-eof endpoint-failed; do
    : >"${TLS_WIZARD_ACTIONS}"
    export CONTROL_INIT_STATUS=0
    [[ "${controlCase}" != endpoint-failed ]] || CONTROL_INIT_STATUS=17
    runPty "control-${controlCase}" control "${controlCase}" "${TLS_WIZARD_CLI}" menu
    expectedControl= expectedConfirmations=0
    if [[ "${controlCase}" != endpoint-input-* ]]; then
        for controlAction in 'set-port --port 19443' 'reconnect --invite /root/padm-invite.json' \
            'rebind --invite /root/padm-invite.json'; do
            [[ -z "${expectedControl}" ]] || expectedControl+=$'\n'
            expectedControl+="control ${controlAction}"
            case "${controlCase}" in
            endpoint-confirm-cancel) expectedControl+=$'\ncontrol-confirm n' ;;
            endpoint-confirm-eof) expectedControl+=$'\ncontrol-confirm eof' ;;
            endpoint-failed) expectedControl+=$'\ncontrol-confirm y' ;;
            *) expectedControl+=$'\ncontrol-confirm y\ncontrol-commit' ;;
            esac
        done
        expectedConfirmations=3
    fi
    [[ "${controlCase}" != endpoint ]] || expectedControl+=$'\ncontrol status'
    if [[ "${controlCase}" == endpoint-failed ]]; then
        expectedControl+=$'\ncontrol status'
        [[ "$(grep -Fc '操作失败，退出码: 17' "${CONTROL_LOG}" || true)" -eq 3 ]] ||
            fail '控制端口更新、重连或主控身份更换失败未报告退出码并返回菜单'
        grep -Fq 'fixture-control-status' "${CONTROL_LOG}" || fail '控制端点操作失败后菜单不可用'
    fi
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedControl}" ]] ||
        fail "控制端点 ${controlCase} 参数错误、重复执行或取消后提交"
    [[ "$(grep -Fc 'fixture-control-confirm [y/N]' "${CONTROL_LOG}" || true)" -eq "${expectedConfirmations}" ]] ||
        fail "控制端点 ${controlCase} 未复用 CLI 单次确认"
    for controlBoundary in '请先停用自动同步及控制日志调度，并禁用控制面 Fail2ban。' \
        '仅支持同身份、同 WireGuard 地址的 API 端口更新；'; do
        grep -Fq "${controlBoundary}" "${CONTROL_LOG}" || fail "控制端点菜单缺少边界: ${controlBoundary}"
    done
done
unset CONTROL_INIT_STATUS
for controlCase in invite invite-cancel invite-eof revoke revoke-cancel; do
    : >"${TLS_WIZARD_ACTIONS}"
    runPty "control-${controlCase}" control "${controlCase}" "${TLS_WIZARD_CLI}" menu
    case "${controlCase}" in
    invite*) expectedControl='control invite --output /root/padm-invite.json --expires-in ' ;;
    revoke*) expectedControl='control revoke' ;;
    esac
    case "${controlCase}" in
    invite) expectedControl+='3600' ;;
    invite-*) expectedControl+='86400' ;;
    esac
    case "${controlCase}" in
    *-cancel) expectedControl+=$'\ncontrol-confirm n' ;;
    *-eof) expectedControl+=$'\ncontrol-confirm eof' ;;
    *) expectedControl+=$'\ncontrol-confirm y\ncontrol-commit' ;;
    esac
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedControl}" ]] ||
        fail "control ${controlCase} dispatched incorrect arguments or bypassed confirmation"
    [[ "$(grep -Fc 'fixture-control-confirm [y/N]' "${CONTROL_LOG}")" -eq 1 ]] ||
        fail "control ${controlCase} did not confirm exactly once"
done

for controlCase in join join-multiple join-cancel join-eof join-mapping-invalid join-mapping-eof \
    remap remap-multiple remap-cancel remap-eof remap-mapping-invalid remap-mapping-eof remap-failed \
    sync sync-cancel sync-eof sync-failed; do
    : >"${TLS_WIZARD_ACTIONS}"
    export CONTROL_INIT_STATUS=0
    [[ "${controlCase}" != *-failed ]] || CONTROL_INIT_STATUS=17
    runPty "control-${controlCase}" control "${controlCase}" "${TLS_WIZARD_CLI}" menu
    expectedControl=
    case "${controlCase}" in
    join-mapping-*|remap-mapping-*)
        ! grep -Fq 'fixture-control-confirm [y/N]' "${CONTROL_LOG}" ||
            fail "control ${controlCase} dispatched a rejected mapping"
        [[ "${controlCase}" != *-mapping-invalid ]] ||
            [[ "$(grep -Ec '映射入口.*(无效|有效 ID)' "${CONTROL_LOG}")" -eq 6 ]] ||
            fail '无效映射未全部返回菜单'
        ;;
    join*|remap*)
        controlAction=join
        [[ "${controlCase}" != remap* ]] || controlAction=remap
        expectedControl="control ${controlAction} --invite /root/padm-invite.json --listener entry-reality"
        [[ "${controlCase}" != *-multiple ]] ||
            expectedControl="control ${controlAction} --invite /root/padm-invite.json --listener entry-secondary --listener entry-reality"
        case "${controlCase}" in
        *-cancel) expectedControl+=$'\ncontrol-confirm n' ;;
        *-eof) expectedControl+=$'\ncontrol-confirm eof' ;;
        *-failed) expectedControl+=$'\ncontrol-confirm y\ncontrol status' ;;
        *) expectedControl+=$'\ncontrol-confirm y\ncontrol-commit' ;;
        esac
        [[ "$(grep -Fc 'fixture-control-confirm [y/N]' "${CONTROL_LOG}")" -eq 1 ]] ||
            fail "control ${controlCase} did not confirm exactly once"
        ;;
    sync) expectedControl=$'control sync --invite /root/padm-invite.json\ncontrol-commit' ;;
    sync-failed)
        expectedControl=$'control sync --invite /root/padm-invite.json\ncontrol status'
        grep -Fq '操作失败，退出码: 17' "${CONTROL_LOG}" || fail 'failed control sync was not reported'
        ;;
    esac
    if [[ "${controlCase}" == remap* ]]; then
        remapLists=1
        case "${controlCase}" in
        remap-cancel) remapLists=4 ;;
        remap-mapping-invalid) remapLists=6 ;;
        esac
        [[ "$(grep -cxF 'protocol list' "${TLS_WIZARD_ACTIONS}")" -eq "${remapLists}" ]] ||
            fail "control ${controlCase} 未在录入前列出可用入口"
        grep -Fq '仅替换当前主控连接的入口映射；请先停用自动同步。' "${CONTROL_LOG}" ||
            fail '重映射菜单未说明连接和自动同步边界'
        expectedLists=
        for ((index=0; index<remapLists; index++)); do expectedLists+=$'protocol list\n'; done
        expectedControl="${expectedLists}${expectedControl}"
        expectedControl=${expectedControl%$'\n'}
    fi
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedControl}" ]] ||
        fail "control ${controlCase} dispatched incorrect arguments or committed after cancellation"
    if [[ "${controlCase}" == sync* ]]; then
        ! grep -Fq 'fixture-control-confirm [y/N]' "${CONTROL_LOG}" ||
            fail "control ${controlCase} added an unnecessary confirmation"
    fi
done
unset CONTROL_INIT_STATUS

for controlCase in diagnostics diagnostics-failed log-rotate-cancel log-rotate-eof source-menu-eof; do
    : >"${TLS_WIZARD_ACTIONS}"
    export CONTROL_DIAGNOSTIC_STATUS=0
    [[ "${controlCase}" != diagnostics-failed ]] || CONTROL_DIAGNOSTIC_STATUS=17
    runPty "control-${controlCase}" control "${controlCase}" "${TLS_WIZARD_CLI}" menu
    case "${controlCase}" in
    diagnostics)
        expectedControl=$'control source-check\ncontrol log-rotate\ncontrol-rotate-confirm yes\ncontrol-rotate-commit'
        ;;
    diagnostics-failed)
        expectedControl=$'control source-check\ncontrol log-rotate\ncontrol-rotate-confirm yes\ncontrol status'
        [[ "$(grep -Fc '操作失败，退出码: 17' "${CONTROL_LOG}")" -eq 2 ]] ||
            fail 'control diagnostics did not report both backend failures'
        ;;
    log-rotate-cancel) expectedControl=$'control log-rotate\ncontrol-rotate-confirm n' ;;
    log-rotate-eof) expectedControl=$'control log-rotate\ncontrol-rotate-confirm eof' ;;
    source-menu-eof) expectedControl='control source-check' ;;
    esac
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedControl}" ]] ||
        fail "control ${controlCase} repeated a backend action or bypassed cancellation"
    if [[ "${controlCase}" != source-menu-eof ]]; then
        [[ "$(grep -Fc 'fixture-control-rotate-confirm [yes]' "${CONTROL_LOG}")" -eq 1 ]] ||
            fail "control ${controlCase} did not confirm rotation exactly once"
    fi
done
unset CONTROL_DIAGNOSTIC_STATUS

for controlCase in log-schedule log-schedule-cancel log-schedule-eof log-schedule-failed; do
    : >"${TLS_WIZARD_ACTIONS}"
    export CONTROL_LOG_SCHEDULE_STATUS=0
    [[ "${controlCase}" != log-schedule-failed ]] || CONTROL_LOG_SCHEDULE_STATUS=17
    runPty "control-${controlCase}" control "${controlCase}" "${TLS_WIZARD_CLI}" menu
    expectedControl=
    case "${controlCase}" in
    log-schedule|log-schedule-failed) expectedControl='control log-schedule status' ;;
    esac
    for scheduleAction in enable disable; do
        [[ -z "${expectedControl}" ]] || expectedControl+=$'\n'
        expectedControl+="control log-schedule ${scheduleAction}"
        case "${controlCase}" in
        log-schedule-cancel) scheduleConfirmation=n ;;
        log-schedule-eof) scheduleConfirmation=eof ;;
        *) scheduleConfirmation=yes ;;
        esac
        expectedControl+=$'\n'"control-log-schedule-confirm ${scheduleAction} ${scheduleConfirmation}"
        [[ "${controlCase}" != log-schedule ]] ||
            expectedControl+=$'\n'"control-log-schedule-commit ${scheduleAction}"
    done
    if [[ "${controlCase}" == log-schedule-failed ]]; then
        expectedControl+=$'\ncontrol status'
        [[ "$(grep -Fc '操作失败，退出码: 17' "${CONTROL_LOG}")" -eq 3 ]] ||
            fail '自动轮转状态或启停失败未保留退出码'
        grep -Fq 'fixture-control-status' "${CONTROL_LOG}" || fail '自动轮转失败后未继续菜单'
    else
        expectedControl+=$'\ncontrol log-schedule status'
    fi
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedControl}" ]] ||
        fail "自动轮转 ${controlCase} 参数分发错误、重复执行或取消后提交"
    [[ "$(grep -Fc 'fixture-control-log-schedule-confirm [yes]' "${CONTROL_LOG}")" -eq 2 ]] ||
        fail "自动轮转 ${controlCase} 启停未各确认一次"
    grep -Fq 'fixture-control-log-schedule-status' "${CONTROL_LOG}" ||
        fail "自动轮转 ${controlCase} 未显示后端状态"
done
unset CONTROL_LOG_SCHEDULE_STATUS

for controlCase in sync-schedule sync-schedule-input-cancel sync-schedule-input-eof \
    sync-schedule-confirm-cancel sync-schedule-confirm-eof sync-schedule-failed; do
    : >"${TLS_WIZARD_ACTIONS}"
    export CONTROL_SYNC_SCHEDULE_STATUS=0
    [[ "${controlCase}" != sync-schedule-failed ]] || CONTROL_SYNC_SCHEDULE_STATUS=17
    runPty "control-${controlCase}" control "${controlCase}" "${TLS_WIZARD_CLI}" menu
    expectedControl= expectedConfirmations=0
    case "${controlCase}" in
    sync-schedule)
        expectedControl=$'control sync-schedule status\ncontrol sync-schedule enable --invite /root/padm-invite.json\ncontrol-sync-schedule-confirm enable y\ncontrol-sync-schedule-commit enable'
        expectedControl+=$'\ncontrol sync-schedule enable --invite /root/padm-rotated.json\ncontrol-sync-schedule-confirm enable y\ncontrol-sync-schedule-commit enable'
        expectedControl+=$'\ncontrol sync-schedule disable\ncontrol-sync-schedule-confirm disable y\ncontrol-sync-schedule-commit disable\ncontrol sync-schedule status'
        expectedConfirmations=3
        ;;
    sync-schedule-confirm-cancel|sync-schedule-confirm-eof|sync-schedule-failed)
        expectedConfirmations=2
        case "${controlCase}" in
        sync-schedule-confirm-cancel) scheduleConfirmation=n ;;
        sync-schedule-confirm-eof) scheduleConfirmation=eof ;;
        sync-schedule-failed)
            scheduleConfirmation=y
            expectedControl=$'control sync-schedule status\n'
            ;;
        esac
        expectedControl+='control sync-schedule enable --invite /root/padm-invite.json'
        expectedControl+=$'\n'"control-sync-schedule-confirm enable ${scheduleConfirmation}"
        expectedControl+=$'\ncontrol sync-schedule disable\n'"control-sync-schedule-confirm disable ${scheduleConfirmation}"
        if [[ "${controlCase}" == sync-schedule-failed ]]; then
            expectedControl+=$'\ncontrol status'
            [[ "$(grep -Fc '操作失败，退出码: 17' "${CONTROL_LOG}")" -eq 3 ]] ||
                fail '自动同步状态或启停失败未保留退出码'
            grep -Fq 'fixture-control-status' "${CONTROL_LOG}" || fail '自动同步失败后未继续菜单'
        else
            expectedControl+=$'\ncontrol sync-schedule status'
        fi
        ;;
    esac
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedControl}" ]] ||
        fail "自动同步 ${controlCase} 参数分发错误、重复执行或取消后提交"
    [[ "$(grep -Fc 'fixture-control-sync-schedule-confirm [y/N]' "${CONTROL_LOG}" || true)" -eq "${expectedConfirmations}" ]] ||
        fail "自动同步 ${controlCase} 确认次数错误"
    if [[ "${expectedConfirmations}" -gt 0 ]]; then
        grep -Fq 'fixture-control-sync-schedule-status' "${CONTROL_LOG}" ||
            fail "自动同步 ${controlCase} 未显示后端状态"
    fi
done
unset CONTROL_SYNC_SCHEDULE_STATUS

if [[ "${MENU_SCOPE}" == control ]]; then
    printf 'docker-menu-control-regression-ok\n'
    exit 0
fi

: >"${TLS_WIZARD_ACTIONS}"
runPty geo-dispatch geo flow "${TLS_WIZARD_CLI}" menu
[[ "$(<"${TLS_WIZARD_ACTIONS}")" == $'geo status\ngeo status\ngeo update --version 202610070140\ngeo update\ngeo schedule enable\ngeo schedule disable\ngeo schedule status' ]] ||
    fail 'Geo menu dispatched incorrect actions or version'
for geoCase in cancel version-eof update-eof enable-eof unsupported failed int term; do
    : >"${TLS_WIZARD_ACTIONS}"
    export GEO_STATUS=0 GEO_UPDATE_STATUS=0 GEO_UPDATE_WAIT=0 GEO_UPDATE_PID="${TEST_ROOT}/geo-update.pid"
    [[ "${geoCase}" != unsupported ]] || GEO_STATUS=15
    [[ "${geoCase}" != failed ]] || GEO_UPDATE_STATUS=17
    [[ "${geoCase}" != int && "${geoCase}" != term ]] || GEO_UPDATE_WAIT=1
    runPty "geo-${geoCase}" geo "${geoCase}" "${TLS_WIZARD_CLI}" menu
    expectedGeo='geo status'
    case "${geoCase}" in
    failed|int|term) expectedGeo+=$'\ngeo update' ;;
    esac
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedGeo}" ]] ||
        fail "Geo ${geoCase} bypassed confirmation or dispatched an action after cancellation"
    if [[ "${geoCase}" == unsupported ]]; then
        ! grep -Fq 'Docker Xray Geo 数据' "${CONTROL_LOG}" || fail 'Geo menu opened without an Xray deployment'
    elif [[ "${geoCase}" == failed ]]; then
        grep -Fq '操作失败，退出码: 17' "${CONTROL_LOG}" || fail 'failed Geo update was not reported'
    elif [[ "${geoCase}" == int || "${geoCase}" == term ]]; then
        ! kill -0 "$(<"${GEO_UPDATE_PID}")" 2>/dev/null || fail "Geo ${geoCase} left the updater alive"
    fi
done
unset GEO_STATUS GEO_UPDATE_STATUS GEO_UPDATE_WAIT GEO_UPDATE_PID

for tlsCase in cancel final-no eof validate install issue renew \
    offer-dns offer-standalone offer-webroot offer-alpn offer-cancel offer-eof offer-failed acme-failed \
    renewal-status renewal-enable renewal-disable renewal-final-no renewal-eof \
    standalone-issue standalone-renew standalone-enable standalone-final-no \
    standalone-renew-final-no standalone-enable-final-no standalone-eof method-cancel method-eof \
    alpn-issue alpn-renew alpn-enable alpn-final-no alpn-eof \
    webroot-issue webroot-renew webroot-enable webroot-final-no webroot-disabled webroot-other-domain \
    http01-enable http01-disable http01-enable-cancel http01-disable-cancel \
    migrate-existing migrate-import migrate-dns migrate-standalone migrate-webroot migrate-alpn migrate-domain-cancel \
    migrate-source-cancel migrate-source-eof migrate-final-no migrate-final-eof migrate-failed; do
    : >"${TLS_WIZARD_ACTIONS}"
    printf '{"tls":{"domain":"ws.example.com","http01":true}}\n' >"${TLS_WIZARD_ROOT}/config/spec.json"
    expectedAction=
    export TLS_MIGRATE_STATUS=0 TLS_RENEWAL_STATUS=0 TLS_ACME_STATUS=0
    case "${tlsCase}" in
    cancel) input=$'0\n' ;;
    final-no) input=$'3\n\nadmin@example.com\n1\ndns_cf\ncredentials.env\nn\n' ;;
    eof) input=eof ;;
    validate) input=$'1\n\ny\n'; expectedAction='validate --domain ws.example.com' ;;
    install)
        input=$'2\nother.example.com\ncertificate.pem\nprivate-key.pem\ny\n'
        expectedAction='install --domain other.example.com --cert certificate.pem --key private-key.pem'
        ;;
    issue|renew)
        if [[ "${tlsCase}" == issue ]]; then choice=3; else choice=4; fi
        printf -v input '%s\n\nadmin@example.com\n1\ndns_cf\ncredentials.env\ny\nn\n' "${choice}"
        expectedAction="acme ${tlsCase} --domain ws.example.com --email admin@example.com --dns dns_cf --credentials credentials.env"
        ;;
    offer-dns|offer-standalone|offer-webroot|offer-alpn|offer-cancel|offer-eof|offer-failed|acme-failed)
        input=$'3\n\nadmin@example.com\n1\ndns_cf\ncredentials.env\ny\n'
        expectedAction='acme issue --domain ws.example.com --email admin@example.com --dns dns_cf --credentials credentials.env'
        provider=dns_cf credentials=credentials.env
        case "${tlsCase}" in
        offer-standalone)
            input=$'3\n\nadmin@example.com\n2\ny\n'
            expectedAction='acme issue --domain ws.example.com --email admin@example.com --standalone'
            provider=standalone credentials= ;;
        offer-webroot)
            input=$'4\n\nadmin@example.com\n3\ny\n'
            expectedAction='acme renew --domain ws.example.com --email admin@example.com --webroot'
            provider=webroot credentials= ;;
        offer-alpn)
            input=$'3\n\nadmin@example.com\n4\ny\n'
            expectedAction='acme issue --domain ws.example.com --email admin@example.com --alpn'
            provider=alpn credentials= ;;
        offer-failed) TLS_RENEWAL_STATUS=17 ;;
        acme-failed) TLS_ACME_STATUS=17 ;;
        esac
        case "${tlsCase}" in
        offer-cancel) input+=$'0\n' ;;
        offer-eof) input=offer-eof ;;
        acme-failed) ;;
        *)
            input+=$'y\n'
            expectedAction+=$'\n'"renewal enable ws.example.com admin@example.com ${provider} ${credentials}"
            ;;
        esac
        ;;
    renewal-status) input=$'5\n'; expectedAction='schedule status' ;;
    renewal-enable)
        input=$'6\n\nadmin@example.com\n1\ndns_cf\ncredentials.env\ny\n'
        expectedAction='schedule enable --domain ws.example.com --email admin@example.com --dns dns_cf --credentials credentials.env'
        ;;
    renewal-disable) input=$'7\n\ny\n'; expectedAction='schedule disable --domain ws.example.com' ;;
    renewal-final-no) input=$'6\n\nadmin@example.com\n1\ndns_cf\ncredentials.env\nn\n' ;;
    renewal-eof) input=renewal-eof ;;
    standalone-issue|standalone-renew|standalone-enable|standalone-final-no|standalone-renew-final-no|standalone-enable-final-no|alpn-issue|alpn-renew|alpn-enable|alpn-final-no)
        choice=3
        action=issue method=2 provider=standalone
        [[ "${tlsCase}" != alpn-* ]] || { method=4; provider=alpn; }
        case "${tlsCase}" in
        *-renew*) choice=4; action=renew ;;
        *-enable*) choice=6; action=enable ;;
        esac
        answer=y
        [[ "${tlsCase}" != *final-no ]] || answer=n
        printf -v input '%s\n\nadmin@example.com\n%s\n%s\n' "${choice}" "${method}" "${answer}"
        if [[ "${answer}" == y ]]; then
            if [[ "${choice}" == 6 ]]; then
                expectedAction="schedule enable --domain ws.example.com --email admin@example.com --${provider}"
            else
                expectedAction="acme ${action} --domain ws.example.com --email admin@example.com --${provider}"
                input+=$'n\n'
            fi
        fi
        ;;
    standalone-eof|alpn-eof) input=${tlsCase} ;;
    method-cancel) input=$'3\n\nadmin@example.com\n0\n' ;;
    method-eof) input=method-eof ;;
    webroot-issue|webroot-renew|webroot-enable|webroot-final-no)
        choice=3 action=issue answer=y
        case "${tlsCase}" in
        webroot-renew) choice=4 action=renew ;;
        webroot-enable) choice=6 action=enable ;;
        webroot-final-no) answer=n ;;
        esac
        printf -v input '%s\n\nadmin@example.com\n3\n%s\n' "${choice}" "${answer}"
        if [[ "${answer}" == y ]]; then
            if [[ "${choice}" == 6 ]]; then
                expectedAction='schedule enable --domain ws.example.com --email admin@example.com --webroot'
            else
                expectedAction="acme ${action} --domain ws.example.com --email admin@example.com --webroot"
                input+=$'n\n'
            fi
        fi
        ;;
    webroot-disabled)
        printf '{"tls":{"domain":"ws.example.com"}}\n' >"${TLS_WIZARD_ROOT}/config/spec.json"
        input=$'3\n\nadmin@example.com\n3\n'
        ;;
    webroot-other-domain) input=$'3\nother.example.com\nadmin@example.com\n3\n' ;;
    http01-enable|http01-disable|http01-enable-cancel|http01-disable-cancel)
        choice=8 action=enable answer=y
        [[ "${tlsCase}" != http01-disable* ]] || { choice=9; action=disable; }
        [[ "${tlsCase}" != *cancel ]] || answer=n
        printf -v input '%s\n%s\n' "${choice}" "${answer}"
        [[ "${answer}" != y ]] || expectedAction="edit --http01 ${action}"
        ;;
    migrate-existing|migrate-import|migrate-dns|migrate-standalone|migrate-webroot|migrate-alpn|migrate-failed)
        input=$'10\nother.example.com\n1\ny\n'
        expectedAction='edit --tls-migrate other.example.com --tls-existing'
        case "${tlsCase}" in
        migrate-import)
            input=$'10\nother.example.com\n2\ncertificate file.pem\nprivate key.pem\ny\n'
            expectedAction='edit --tls-migrate other.example.com --tls-import certificate file.pem private key.pem'
            ;;
        migrate-dns)
            input=$'10\nother.example.com\n3\nadmin@example.com\ndns_cf\ncredentials.env\ny\n'
            expectedAction='edit --tls-migrate other.example.com --tls-dns admin@example.com dns_cf credentials.env'
            ;;
        migrate-standalone)
            input=$'10\nother.example.com\n4\nadmin@example.com\ny\n'
            expectedAction='edit --tls-migrate other.example.com --tls-standalone admin@example.com'
            ;;
        migrate-webroot)
            input=$'10\nother.example.com\n5\nadmin@example.com\ny\n'
            expectedAction='edit --tls-migrate other.example.com --tls-webroot admin@example.com'
            ;;
        migrate-alpn)
            input=$'10\nother.example.com\n6\nadmin@example.com\ny\n'
            expectedAction='edit --tls-migrate other.example.com --tls-alpn admin@example.com'
            ;;
        migrate-failed) TLS_MIGRATE_STATUS=17 ;;
        esac
        ;;
    migrate-domain-cancel) input=$'10\n0\n' ;;
    migrate-source-cancel) input=$'10\nother.example.com\n0\n' ;;
    migrate-source-eof) input=migrate-source-eof ;;
    migrate-final-no) input=$'10\nother.example.com\n1\nn\n' ;;
    migrate-final-eof) input=migrate-final-eof ;;
    esac
    runPty "tls-${tlsCase}" tls "${input}" "${TLS_WIZARD_CLI}" menu
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedAction}" ]] ||
        fail "TLS ${tlsCase} bypassed confirmation or dispatched incorrect arguments"
    if [[ "${tlsCase}" == renewal-status ]]; then
        ! grep -Fq '证书域名 [' "${CONTROL_LOG}" ||
            fail '自动续期状态不应询问证书域名'
        ! grep -Fq '确认执行证书操作？[y/N]' "${CONTROL_LOG}" ||
            fail '自动续期状态不应要求确认'
    fi
    if [[ "${tlsCase}" == offer-failed ]]; then
        grep -Fq '操作已完成，但自动续期登记失败；现有证书和配置已保留' "${CONTROL_LOG}" &&
            grep -Fq '操作失败，退出码: 15' "${CONTROL_LOG}" ||
            fail '续期登记失败未保留成功操作说明或退出码'
    elif [[ "${tlsCase}" == acme-failed ]]; then
        ! grep -Fq '为该 ACME 证书启用自动续期' "${CONTROL_LOG}" &&
            grep -Fq '操作失败，退出码: 17' "${CONTROL_LOG}" ||
            fail 'ACME 失败仍询问自动续期或丢失退出码'
    elif [[ "${tlsCase}" == offer-dns || "${tlsCase}" == offer-standalone || "${tlsCase}" == offer-webroot || "${tlsCase}" == offer-alpn ]]; then
        grep -Fq '自动续期已启用: ws.example.com' "${CONTROL_LOG}" || fail '续期登记成功未说明结果'
    fi
    if [[ "${tlsCase}" == migrate-* ]]; then
        grep -Fq '10. 迁移入口 TLS 域名' "${CONTROL_LOG}" || fail '证书菜单未开放 TLS 域名迁移'
        ! grep -Fq '确认执行证书操作？[y/N]' "${CONTROL_LOG}" || fail 'TLS 迁移在 edit 前重复确认'
        if [[ -n "${expectedAction}" || "${tlsCase}" == migrate-final-* ]]; then
            [[ "$(grep -Fc 'fixture-tls-migrate-confirm [y/N]' "${CONTROL_LOG}")" == 1 ]] ||
                fail 'TLS 迁移未仅由 edit 确认一次'
        fi
        [[ "${tlsCase}" != migrate-failed ]] ||
            grep -Fq '操作失败，退出码: 17' "${CONTROL_LOG}" || fail 'TLS 迁移失败后未返回主菜单或丢失退出码'
    fi
    if [[ "${tlsCase}" == standalone-* || "${tlsCase}" == alpn-* ]]; then
        challengeText='HTTP-01 需要公网 80 可达'
        [[ "${tlsCase}" != alpn-* ]] || challengeText='TLS-ALPN-01 需要公网 TCP 443 直达本机'
        grep -Fq "${challengeText}" "${CONTROL_LOG}" ||
            fail "${tlsCase}: 确认前没有说明公网挑战端口与短暂停机影响"
        [[ "$(grep -Fc '确认执行证书操作？[y/N]' "${CONTROL_LOG}")" == 1 ]] ||
            fail "${tlsCase}: 操作没有恰好确认一次"
        ! grep -Eq 'DNS provider|DNS 凭据文件' "${CONTROL_LOG}" ||
            fail "${tlsCase}: 仍要求 DNS 凭据"
    fi
    if [[ "${tlsCase}" == webroot-* ]]; then
        ! grep -Eq 'DNS provider|DNS 凭据文件' "${CONTROL_LOG}" || fail 'webroot 仍要求 DNS 凭据'
        if [[ "${tlsCase}" == webroot-disabled || "${tlsCase}" == webroot-other-domain ]]; then
            grep -Fq '请先显式启用 Nginx HTTP-01 入口' "${CONTROL_LOG}" ||
                fail 'webroot 未拒绝未启用入口或其它 TLS 域名'
        else
            grep -Fq '不暂停 Nginx 或其它 TLS 消费者' "${CONTROL_LOG}" ||
                fail 'webroot 确认前没有说明不停服'
        fi
    fi
done
unset TLS_MIGRATE_STATUS TLS_RENEWAL_STATUS TLS_ACME_STATUS

: >"${TLS_WIZARD_ACTIONS}"
runPty protocols-dispatch protocols read "${TLS_WIZARD_CLI}" menu
[[ "$(<"${TLS_WIZARD_ACTIONS}")" == $'protocol list\nprotocol links entry-fixture\nedit\nedit --regenerate-reality entry-fixture' ]] ||
    fail 'protocol menu did not dispatch list, selected links, editor and Reality regeneration'
: >"${TLS_WIZARD_ACTIONS}"
runPty protocols-links-cancel protocols cancel "${TLS_WIZARD_CLI}" menu
[[ "$(<"${TLS_WIZARD_ACTIONS}")" == 'protocol list' ]] ||
    fail 'cancelled protocol link selection dispatched a business command'

# 协议与内部端口入口共用真实 PTY，取消不下发写操作，失败后仍可继续选择。
for managementCase in flow failed status-failed; do
    : >"${TLS_WIZARD_ACTIONS}"
    export SITE_EDIT_STATUS=0 FAIL2BAN_PROTOCOL_LIST_STATUS=0
    [[ "${managementCase}" != failed ]] || SITE_EDIT_STATUS=15
    [[ "${managementCase}" != status-failed ]] || FAIL2BAN_PROTOCOL_LIST_STATUS=15
    runPty "protocol-management-${managementCase}" protocol-management "${managementCase}" "${TLS_WIZARD_CLI}" menu
    expectedManagement=$'edit --protocol-add entry-fixture 31 30443\nedit --protocol-remove entry-fixture\nedit --protocol-rebuild entry-fixture\nedit --internal-ports entry-fixture 31350 8650\nedit --protocol-add entry-fixture 28 30443 --protocol-core xray\nedit --protocol-add entry-fixture 30 30443 --protocol-core sing-box'
    [[ "${managementCase}" != status-failed ]] || expectedManagement=
    [[ "$(grep -v '^protocol list$' "${TLS_WIZARD_ACTIONS}" || true)" == "${expectedManagement}" ]] ||
        fail "协议管理 ${managementCase} 分发错误或取消后仍写入"
    [[ "${managementCase}" != flow ]] || grep -Fq '30 Shadowsocks2022' "${CONTROL_LOG}" ||
        fail '协议新增菜单没有 Shadowsocks2022 目标'
    [[ "${managementCase}" != flow ]] ||
        grep -Fq '11. 端口跳跃（双族 Hy2/TUIC；TUIC 仅范围转发）' "${CONTROL_LOG}" ||
        fail '协议菜单未明确 TUIC 仅范围转发边界'
    grep -Fq '17. 核心/Nginx 内部端口' "${CONTROL_LOG}" || fail '内部端口入口没有接入协议菜单'
    [[ "${managementCase}" == flow ]] ||
        [[ "$(grep -Fc '操作失败，退出码: 15' "${CONTROL_LOG}")" -ge 3 ]] ||
        fail "协议管理 ${managementCase} 未保留退出码或返回菜单"
done
unset SITE_EDIT_STATUS FAIL2BAN_PROTOCOL_LIST_STATUS
fi

if [[ "${MENU_SCOPE}" != xhttp ]]; then
# 额外入口菜单使用真实 PTY，取消与 EOF 不向 CLI 提交端口变更。
for aliasCase in flow cancel eof invalid failed default-cancel default-eof base-eof default-invalid default-failed \
    replace-flow replace-cancel replace-eof replace-failed; do
    : >"${TLS_WIZARD_ACTIONS}"
    export SITE_EDIT_STATUS=0
    [[ "${aliasCase}" != failed && "${aliasCase}" != default-failed && "${aliasCase}" != replace-failed ]] ||
        SITE_EDIT_STATUS=15
    runPty "port-alias-${aliasCase}" port-alias "${aliasCase}" "${TLS_WIZARD_CLI}" menu
    expectedAliases='protocol list'
    case "${aliasCase}" in
    flow)
        expectedAliases+=$'\nprotocol port-alias-status\nprotocol list\nedit --port-alias entry-fixture 2053'
        expectedAliases+=$'\nprotocol port-alias-status\nprotocol list\nedit --port-alias-default entry-fixture 2053'
        expectedAliases+=$'\nprotocol list\nedit --port-alias-default entry-fixture base\nprotocol list\nedit --port-alias-remove entry-fixture 2053'
        grep -Fq '8. 额外入口端口' "${CONTROL_LOG}" || fail '额外入口菜单未接入协议菜单'
        grep -Fq '4. 选择默认分享端口' "${CONTROL_LOG}" || fail '默认分享端口菜单未接入'
        grep -Fq '5. 恢复原入口' "${CONTROL_LOG}" || fail '原入口恢复菜单未接入'
        ;;
    cancel) expectedAliases+=$'\nprotocol list\nprotocol list' ;;
    eof) expectedAliases+=$'\nprotocol list' ;;
    invalid)
        expectedAliases+=$'\nprotocol list\nedit --port-alias entry-fixture invalid'
        grep -Fq '操作失败，退出码: 2' "${CONTROL_LOG}" || fail '非法别名端口未保留菜单'
        ;;
    failed)
        expectedAliases+=$'\nprotocol list\nedit --port-alias entry-fixture 2053'
        grep -Fq '操作失败，退出码: 15' "${CONTROL_LOG}" || fail '别名 CLI 失败未保留菜单'
        ;;
    default-cancel)
        expectedAliases+=$'\nprotocol port-alias-status\nprotocol list\nprotocol port-alias-status\nprotocol list\nprotocol list'
        ;;
    default-eof) expectedAliases+=$'\nprotocol port-alias-status\nprotocol list' ;;
    base-eof) expectedAliases+=$'\nprotocol list' ;;
    default-invalid)
        expectedAliases+=$'\nprotocol port-alias-status\nprotocol list\nedit --port-alias-default entry-fixture invalid'
        grep -Fq '操作失败，退出码: 2' "${CONTROL_LOG}" || fail '非法默认分享端口未保留菜单'
        ;;
    default-failed)
        expectedAliases+=$'\nprotocol port-alias-status\nprotocol list\nedit --port-alias-default entry-fixture 2053'
        grep -Fq '操作失败，退出码: 15' "${CONTROL_LOG}" || fail '默认分享端口 CLI 失败未保留菜单'
        ;;
    replace-flow|replace-cancel|replace-eof|replace-failed)
        aliasConfirmation=y aliasFailureCount=0 aliasExit=2
        case "${aliasCase}" in
        replace-cancel)
            for ((aliasStatus = 0; aliasStatus < 6; aliasStatus++)); do
                expectedAliases+=$'\nprotocol port-alias-status'
            done
            aliasConfirmation=n aliasFailureCount=1
            ;;
        replace-eof)
            for ((aliasStatus = 0; aliasStatus < 3; aliasStatus++)); do
                expectedAliases+=$'\nprotocol port-alias-status'
            done
            aliasConfirmation=eof aliasFailureCount=1
            ;;
        replace-failed) aliasFailureCount=1 aliasExit=15 ;;
        esac
        expectedAliases+=$'\nprotocol port-alias-status\nedit --port-alias-replace entry-fixture 2053 2083'
        expectedAliases+=$'\nport-alias-replace-confirm '"${aliasConfirmation}"
        [[ "${aliasCase}" != replace-flow ]] || expectedAliases+=$'\nport-alias-replace-commit'
        expectedAliases+=$'\nprotocol port-alias-status'
        [[ "$(grep -Fc 'fixture-port-alias-replace-confirm [y/N]' "${CONTROL_LOG}" || true)" -eq 1 ]] ||
            fail '额外端口替换没有仅由 CLI 确认一次'
        [[ "$(grep -Fc "操作失败，退出码: ${aliasExit}" "${CONTROL_LOG}" || true)" -eq "${aliasFailureCount}" ]] ||
            fail '额外端口替换取消或失败未显示退出码并继续状态'
        grep -Fq '6. 修改额外端口' "${CONTROL_LOG}" || fail '额外端口替换菜单未接入'
        ;;
    esac
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedAliases}" ]] ||
        fail "额外入口 ${aliasCase} 参数分发错误或取消后执行操作"
done
unset SITE_EDIT_STATUS

if [[ "${MENU_SCOPE}" == port-alias ]]; then
    printf 'docker-menu-port-alias-regression-ok\n'
    exit 0
fi

# 两种 gRPC TLS 入口共用菜单交互，取消和 EOF 只允许状态读取。
for cdnCase in flow cancel failed; do
    : >"${TLS_WIZARD_ACTIONS}"
    export SITE_EDIT_STATUS=0
    [[ "${cdnCase}" != failed ]] || SITE_EDIT_STATUS=15
    runPty "cdn-${cdnCase}" cdn "${cdnCase}" "${TLS_WIZARD_CLI}" menu
    expectedCdn=$'protocol list\nprotocol cdn-status'
    if [[ "${cdnCase}" == cancel ]]; then
        for ((cdnStatus = 0; cdnStatus < 9; cdnStatus++)); do
            expectedCdn+=$'\nprotocol cdn-status'
        done
    else
        expectedCdn+=$'\nprotocol cdn-status\nedit --cdn-entry entry24 203.0.113.24,cdn.example.com'
        expectedCdn+=$'\nprotocol cdn-status\nedit --cdn-entry-clear entry25'
    fi
    expectedCdn+=$'\nprotocol cdn-status'
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedCdn}" ]] ||
        fail "CDN ${cdnCase} 参数分发错误或取消后执行编辑"
    grep -Fq '2. 设置地址（Reality XHTTP/WS/HTTPUpgrade/gRPC TLS）' "${CONTROL_LOG}" ||
        fail 'CDN 菜单未显示 gRPC TLS 支持范围'
    if [[ "${cdnCase}" == failed ]]; then
        [[ "$(grep -Fc '操作失败，退出码: 15' "${CONTROL_LOG}")" -eq 2 ]] ||
            fail 'gRPC TLS CDN 编辑失败未显示状态错误并继续读取'
    fi
done
unset SITE_EDIT_STATUS
fi

# 转义后的合法首部超过终端 canonical 输入上限，先用真实合同证明夹具有效。
XHTTP_LONG_HEADERS=$(jq -cn '[range(1;9) | {
  key:("x-" + ("a" * 61) + tostring),value:("\"" * 256)}] | from_entries')
[[ "${#XHTTP_LONG_HEADERS}" -gt 4095 ]] || fail 'XHTTP 长首部夹具未覆盖终端输入上限'
(
    source "${PROJECT_ROOT}/install-docker.sh"
    DOCKER_BUNDLE_SOURCE_ROOT=${PROJECT_ROOT}
    jq --argjson headers "${XHTTP_LONG_HEADERS}" '
      .schema_version=3 | .core.secondary_type=null |
      .core.protocols[0] += {id:2,core:"xray",listener_id:"entry-xhttp",
        xhttp:{path:"/xhttp",host:"proxy.example.com",mode:"auto",headers:$headers}}' \
        "${PROJECT_ROOT}/docker/configure.example.json" >"${TEST_ROOT}/xhttp-long-headers.json"
    dockerConfigureSpecValidate "${TEST_ROOT}/xhttp-long-headers.json"
) || fail 'XHTTP 长首部夹具未通过真实规格合同'
export XHTTP_LONG_HEADERS

# 菜单只校验取消与参数分发；非法参数由 CLI 拒绝后必须能继续查看状态。
for xhttpCase in flow headers-long cancel failed invalid current status-failed status-invalid status-incomplete; do
    : >"${TLS_WIZARD_ACTIONS}"
    export XHTTP_EDIT_STATUS=0 XHTTP_STATUS=0 XHTTP_STATUS_FIXTURE=default
    case "${xhttpCase}" in
    failed) XHTTP_EDIT_STATUS=15 ;;
    invalid) XHTTP_EDIT_STATUS=2 ;;
    current) XHTTP_STATUS_FIXTURE=current ;;
    status-failed) XHTTP_STATUS=15 ;;
    status-invalid) XHTTP_STATUS_FIXTURE=invalid ;;
    status-incomplete) XHTTP_STATUS_FIXTURE=incomplete ;;
    esac
    runPty "xhttp-${xhttpCase}" xhttp "${xhttpCase}" "${TLS_WIZARD_CLI}" menu
    expectedXhttp=$'protocol list\nprotocol xhttp-status'
    case "${xhttpCase}" in
    flow)
        for xhttpPreset in daily compatible stream single; do
            expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-preset entry-xhttp '"${xhttpPreset}"
        done
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-xmux entry-xhttp 8-16 0-0 120-180'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-xmux entry-xhttp 16-32 600-900 1800-3000'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-xmux-clear entry-xhttp'
        for xhttpPadding in 64 128-256 100-1000; do
            expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-padding entry-xhttp '"${xhttpPadding}"
        done
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-padding-clear entry-xhttp'
        for xhttpHeaders in 'true false' 'false true' 'false false' 'false false'; do
            expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-headers entry-xhttp '"${xhttpHeaders}"
        done
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-headers-clear entry-xhttp'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-limits entry-xhttp 16384 5 16 1-2'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-limits entry-xhttp 1000000 30 30 20-80'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-limits entry-xhttp 0 0 0 0-0'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-limits-clear entry-xhttp'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-request-headers entry-xhttp {"x-trace":"edge value","x-route":"v3"}'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-request-headers-clear entry-xhttp'
        ;;
    headers-long)
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-request-headers entry-xhttp '"${XHTTP_LONG_HEADERS}"
        ! grep -Fq '操作失败' "${CONTROL_LOG}" || fail 'XHTTP 长首部未完整传递给 CLI'
        ;;
    cancel)
        for ((xhttpStatus = 0; xhttpStatus < 4 * 9 + 2 * (3 + 1 + 2) + 3 + 8 + 5 + 5 + 5; xhttpStatus++)); do
            expectedXhttp+=$'\nprotocol xhttp-status'
        done
        grep -Fq '无效选项，请重新选择。' "${CONTROL_LOG}" || fail 'XHTTP 无效选项未留在菜单'
        ;;
    failed)
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-preset entry-xhttp daily'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-xmux entry-xhttp 8-16 50-100 120-180'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-xmux-clear entry-xhttp'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-padding entry-xhttp 128-256'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-padding-clear entry-xhttp'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-headers entry-xhttp true false'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-headers-clear entry-xhttp'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-limits entry-xhttp 16384 5 16 1-2'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-limits-clear entry-xhttp'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-request-headers entry-xhttp {"x-trace":"edge value"}'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-request-headers-clear entry-xhttp'
        [[ "$(grep -Fc '操作失败，退出码: 15' "${CONTROL_LOG}")" -eq 20 ]] ||
            fail 'XHTTP 编辑失败未显示错误并继续读取'
        ;;
    invalid)
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-xmux entry-xhttp not-range 50-100 120-180'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-padding entry-xhttp not-range'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-headers entry-xhttp not-bool false'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-headers entry-xhttp false not-bool'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-limits entry-xhttp not-number 5 16 1-2'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-request-headers entry-xhttp not-json'
        [[ "$(grep -Fc '操作失败，退出码: 2' "${CONTROL_LOG}")" -eq 11 ]] ||
            fail 'XHTTP 非法参数未保留菜单'
        ;;
    status-failed)
        for ((xhttpStatus = 0; xhttpStatus < 18; xhttpStatus++)); do
            expectedXhttp+=$'\nprotocol xhttp-status'
        done
        [[ "$(grep -Fc '操作失败，退出码: 15' "${CONTROL_LOG}")" -eq 20 ]] ||
            fail 'XHTTP 状态失败仍提示变更或未恢复菜单'
        ! grep -Fq 'XHTTP 入口 ID（0 返回）' "${CONTROL_LOG}" ||
            fail 'XHTTP 状态失败仍读取变更入口'
        ;;
    current)
        expectedXhttp+=$'\nprotocol xhttp-status'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-xmux entry-xhttp 4-8 0-0 0-0'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-padding entry-xhttp 17-19'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-headers entry-xhttp false true'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-limits entry-xhttp 8192 5 7 10-15'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-mode entry-xhttp stream-up'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-path-host entry-xhttp /current/path current.example.net'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-advanced entry-xhttp 17-19 8192 5 7 10-15 false true'
        grep -Fq '无法读取该入口的 XHTTP 当前值' "${CONTROL_LOG}" ||
            fail 'XHTTP 未登记入口没有拒绝编辑'
        ;;
    status-invalid|status-incomplete)
        expectedXhttp+=$'\nprotocol xhttp-status'
        grep -Fq '无法读取该入口的 XHTTP 当前值' "${CONTROL_LOG}" ||
            fail 'XHTTP 非法或不完整状态没有拒绝编辑'
        ;;
    esac
    case "${xhttpCase}" in
    flow|failed|invalid)
        if [[ "${xhttpCase}" == flow ]]; then
            for mode in packet-up stream-up auto; do
                expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-mode entry-xhttp '"${mode}"
            done
        else
            mode=packet-up
            [[ "${xhttpCase}" != invalid ]] || mode=stream-one
            expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-mode entry-xhttp '"${mode}"
        fi
        path=/custom/path padding=64-128
        [[ "${xhttpCase}" != invalid ]] || { path=no-leading-slash; padding=not-range; }
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-path-host entry-xhttp '"${path}"' edge.example.net'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-advanced entry-xhttp '"${padding}"' 16384 5 16 1-2 false true'
        [[ "${xhttpCase}" == invalid ]] ||
            expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-defaults entry-xhttp'
        downloadPort=9443
        [[ "${xhttpCase}" != invalid ]] || downloadPort=not-port
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-download entry-xhttp '"${downloadPort}"
        [[ "${xhttpCase}" == invalid ]] ||
            expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-download-clear entry-xhttp'
        downloadPort=443 xhttpAlpn=h2
        [[ "${xhttpCase}" != invalid ]] || downloadPort='"not-port"'
        [[ "${xhttpCase}" != flow ]] || xhttpAlpn=h3
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-download-settings entry-xhttp {"address":"download.example.net","port":'"${downloadPort}"',"security":"tls","server_name":"tls.example.net","host":"relay.example.net","path":"/down/path","mode":"auto","alpn":["'"${xhttpAlpn}"'"]}'
        [[ "${xhttpCase}" != flow ]] ||
            expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-download-settings entry-xhttp {"address":"192.0.2.10","port":8443,"security":"reality","server_name":"reality.example.net","host":"reality-relay.example.net","path":"/reality/down","mode":"stream-one","public_key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","short_id":"0123456789abcdef"}'
        ;;
    esac
    if [[ "${xhttpCase}" == flow || "${xhttpCase}" == failed || "${xhttpCase}" == current ]]; then
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-concurrency entry-xhttp 16-32'
        expectedXhttp+=$'\nprotocol xhttp-status\nedit --xhttp-concurrency entry-xhttp 1'
    fi
    expectedXhttp+=$'\nprotocol xhttp-status'
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedXhttp}" ]] ||
        fail "XHTTP ${xhttpCase} 参数分发错误或取消后执行编辑"
    grep -Fq '10. XHTTP 管理' "${CONTROL_LOG}" || fail 'XHTTP 管理未接入协议菜单'
    grep -Fq '已有 Xray Reality 入口' "${CONTROL_LOG}" || fail 'XHTTP 菜单未显示支持范围'
    for label in 普通设置 高级设置 实验功能 '23. XMUX 日常并发' '24. XMUX 单并发'; do
        grep -Fq "${label}" "${CONTROL_LOG}" || fail "XHTTP 菜单缺少 ${label}"
    done
    grep -Fq '8. 设置 Padding' "${CONTROL_LOG}" &&
        grep -Fq '9. 恢复缺省 Padding' "${CONTROL_LOG}" || fail 'XHTTP Padding 菜单入口缺失'
    grep -Fq '10. 设置首部开关' "${CONTROL_LOG}" &&
        grep -Fq '11. 恢复缺省首部' "${CONTROL_LOG}" || fail 'XHTTP Header 菜单入口缺失'
    grep -Fq '12. 设置 packet/stream 参数' "${CONTROL_LOG}" &&
        grep -Fq '13. 恢复缺省 packet/stream' "${CONTROL_LOG}" || fail 'XHTTP packet/stream 菜单入口缺失'
    for label in '14. 设置模式' '15. 设置路径和 Host' '16. 统一高级参数' '17. 恢复推荐默认' \
        '18. 设置请求首部（JSON）' '19. 清除请求首部' \
        '20. 设置下行端口' '21. 关闭上下行分离' '22. 设置独立下行'; do
        grep -Fq "${label}" "${CONTROL_LOG}" || fail "XHTTP 菜单缺少 ${label}"
    done
    if [[ "${xhttpCase}" == flow || "${xhttpCase}" == cancel || "${xhttpCase}" == failed || "${xhttpCase}" == invalid ]]; then
        grep -Fq '已登记的额外非默认分享端口' "${CONTROL_LOG}" &&
            grep -Fq '同服务器的 Reality 后端' "${CONTROL_LOG}" || fail 'XHTTP 下行菜单未说明支持范围'
        grep -Fq '外部前置必须回到同一 XHTTP 会话后端' "${CONTROL_LOG}" &&
            grep -Fq '本菜单不自动部署 CDN' "${CONTROL_LOG}" || fail 'XHTTP 独立下行菜单未说明支持范围'
    fi
done
unset XHTTP_EDIT_STATUS XHTTP_STATUS XHTTP_STATUS_FIXTURE XHTTP_LONG_HEADERS

(
    source "${PROJECT_ROOT}/docker/lib/menu.sh"
    snapshot=previous
    mktemp() { return 1; }
    if dockerMenuReadProtocolStatus snapshot xhttp-status; then
        fail '状态副本创建失败仍返回成功'
    fi
    [[ -z "${snapshot}" ]] || fail '状态副本创建失败仍保留旧状态'
)

# TERM 退出不能留下状态副本；不另起整套 PTY 场景。
menuStatus=0
printf '%s\n' fixture-xhttp-status >"${TEST_ROOT}/xhttp-status.tmp"
(
    source "${PROJECT_ROOT}/docker/lib/menu.sh"
    DOCKER_MENU_STATUS_FILE="${TEST_ROOT}/xhttp-status.tmp"
    dockerMenuInterrupted 143
) || menuStatus=$?
[[ "${menuStatus}" -eq 143 && ! -e "${TEST_ROOT}/xhttp-status.tmp" ]] ||
    fail 'XHTTP TERM 退出遗留状态副本或退出码错误'

menuStatus=0
printf '%s\n' fixture-xhttp-status >"${TEST_ROOT}/xhttp-status.tmp"
(
    source "${PROJECT_ROOT}/docker/lib/menu.sh"
    DOCKER_MENU_STATUS_FILE="${TEST_ROOT}/xhttp-status.tmp"
    dockerMenuInterrupted 130
) || menuStatus=$?
[[ "${menuStatus}" -eq 0 && ! -e "${TEST_ROOT}/xhttp-status.tmp" ]] ||
    fail 'XHTTP INT 退出遗留状态副本或退出码错误'

if [[ "${MENU_SCOPE}" == xhttp ]]; then
    printf 'docker-menu-xhttp-regression-ok\n'
    exit 0
fi

# 仅覆盖参数分发和确认返回，真实事务由 Hy2/TUIC 合同验证。
for kind in hy2 tuic; do
    for udpCase in flow cancel failed; do
        : >"${TLS_WIZARD_ACTIONS}"
        export UDP_EDIT_STATUS=0 UDP_PROTOCOL_STATUS=0
        [[ "${udpCase}" != failed ]] || UDP_EDIT_STATUS=15
        runPty "${kind}-${udpCase}" "${kind}" "${udpCase}" "${TLS_WIZARD_CLI}" menu
        expectedUdp=$'protocol list\nprotocol '"${kind}"'-status'
        if [[ "${udpCase}" == cancel ]]; then
            readCount=9
            [[ "${kind}" != tuic ]] || readCount=3
            for ((udpRead = 0; udpRead < readCount; udpRead++)); do
                expectedUdp+=$'\nprotocol '"${kind}"'-status'
            done
        elif [[ "${kind}" == hy2 ]]; then
            expectedUdp+=$'\nprotocol hy2-status\nedit --hy2-bandwidth entry-hy2 bbr'
            expectedUdp+=$'\nprotocol hy2-status\nedit --hy2-bandwidth entry-hy2 brutal 100 50'
            for mode in salamander gecko off; do
                expectedUdp+=$'\nprotocol hy2-status\nedit --hy2-obfs entry-hy2 '"${mode}"
            done
            for mode in https://www.example.com/path-1 local off; do
                expectedUdp+=$'\nprotocol hy2-status\nedit --hy2-masquerade entry-hy2 '"${mode}"
            done
        else
            for algorithm in cubic bbr new_reno; do
                expectedUdp+=$'\nprotocol tuic-status\nedit --tuic-congestion entry-tuic '"${algorithm}"
            done
            expectedUdp+=$'\nprotocol tuic-status\nedit --tuic-connection entry-tuic 3s 10s'
            expectedUdp+=$'\nprotocol tuic-status\nedit --tuic-zero-rtt entry-tuic true'
            expectedUdp+=$'\nprotocol tuic-status\nedit --tuic-zero-rtt entry-tuic false'
            expectedUdp+=$'\nprotocol tuic-status\nedit --tuic-defaults entry-tuic'
        fi
        expectedUdp+=$'\nprotocol '"${kind}"'-status'
        [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedUdp}" ]] ||
            fail "${kind} ${udpCase} 菜单参数分发错误或取消仍执行编辑"
        if [[ "${udpCase}" == failed ]]; then
            failures=8
            [[ "${kind}" != tuic ]] || failures=7
            [[ "$(grep -Fc '操作失败，退出码: 15' "${CONTROL_LOG}")" -eq "${failures}" ]] ||
                fail "${kind} 后端失败没有返回菜单并继续读取状态"
        fi
        grep -Fq '12. Hysteria2 管理' "${CONTROL_LOG}" &&
            grep -Fq '13. TUIC 管理' "${CONTROL_LOG}" &&
            grep -Fq '已有 sing-box v3 入口' "${CONTROL_LOG}" || fail 'Hy2/TUIC 菜单缺少支持边界'
        [[ "${kind}" != tuic ]] || grep -Fq '重放攻击风险' "${CONTROL_LOG}" ||
            fail 'TUIC 开启 0-RTT 没有明确风险提示'
        [[ "${kind}" != hy2 ]] || {
            for label in '4. Salamander 混淆' '5. Gecko 混淆' '6. 关闭混淆' \
                '7. HTTPS 伪装' '8. 本地网页' '9. 关闭伪装'; do
                grep -Fq "${label}" "${CONTROL_LOG}" || fail "Hy2 菜单缺少 ${label}"
            done
            [[ "${udpCase}" == cancel ]] ||
                grep -Fq 'local 使用已发布的受管静态网页' "${CONTROL_LOG}" ||
                fail 'Hy2 local 菜单缺少受管网页前置提示'
        }
    done
done
unset UDP_EDIT_STATUS UDP_PROTOCOL_STATUS

# 按新版八项菜单现场握手，扫描和选择必须真实读取前台终端。
: >"${TLS_WIZARD_ACTIONS}"
runPty targets-dispatch targets flow "${TLS_WIZARD_CLI}" menu
for targetLabel in '1. 检测当前目标' '2. 刷新目标库' '3. 扫描指定网段' \
    '4. 同 ASN 抽样扫描' '5. 查看/切换 A 级目标' '6. 手动设置目标站' \
    '7. 查看目标站黑名单' '8. 返回'; do
    grep -Fq "${targetLabel}" "${CONTROL_LOG}" || fail "missing target menu item: ${targetLabel}"
done
expectedTargets=$'protocol list\nprotocol check-target entry-fixture\nprotocol select-target entry-fixture\ntarget-input select-target selected\nprotocol refresh-targets recommended\nprotocol refresh-targets recommended_only\nprotocol scan-targets\ntarget-input scan-targets scan\nprotocol scan-targets-asn\ntarget-input scan-targets-asn scan-asn\nprotocol select-target entry-secondary\ntarget-input select-target selected-secondary\nedit --reality-target entry-fixture target.example.com 443 target.example.com\nedit --reality-target entry-secondary alt.example.com 8443 edge.example.net\nprotocol blocked-targets\nprotocol check-target\nprotocol targets entry-secondary\nprotocol check-target entry-secondary\nprotocol targets entry-secondary\nprotocol block-current-target entry-secondary'
[[ "$(grep -v '^protocol target-status$' "${TLS_WIZARD_ACTIONS}")" == "${expectedTargets}" ]] ||
    fail 'target menu dispatched incorrect actions, listener, refresh scope or host/SNI'
for targetCase in cancel eof failed int term; do
    : >"${TLS_WIZARD_ACTIONS}"
    export TARGET_CHECK_STATUS=0 TARGET_CHECK_WAIT=0 TARGET_CHECK_PID="${TEST_ROOT}/target-check.pid"
    [[ "${targetCase}" != failed ]] || TARGET_CHECK_STATUS=17
    [[ "${targetCase}" != int && "${targetCase}" != term ]] || TARGET_CHECK_WAIT=1
    runPty "targets-${targetCase}" targets "${targetCase}" "${TLS_WIZARD_CLI}" menu
    expectedTargets='protocol list'
    case "${targetCase}" in
    failed|int|term) expectedTargets+=$'\nprotocol check-target entry-fixture' ;;
    esac
    [[ "$(grep -v '^protocol target-status$' "${TLS_WIZARD_ACTIONS}")" == "${expectedTargets}" ]] ||
        fail "target ${targetCase} dispatched an action after cancellation or interruption"
    if [[ "${targetCase}" == int || "${targetCase}" == term ]]; then
        ! grep -Fq 'Reality 目标站后续操作' "${CONTROL_LOG}" ||
            fail "target ${targetCase} entered post-check actions"
        ! kill -0 "$(<"${TARGET_CHECK_PID}")" 2>/dev/null ||
            fail "target ${targetCase} left the checker alive"
    elif [[ "${targetCase}" == failed ]]; then
        grep -Fq '操作失败，退出码: 17' "${CONTROL_LOG}" || fail 'failed target check was not reported'
    fi
done
unset TARGET_CHECK_STATUS TARGET_CHECK_WAIT TARGET_CHECK_PID

# 最小已配置夹具只覆盖调度和命令分发，不宣称真实容器可用。
cat >"${PADM_DOCKER_INSTALL_DIR}/deployment.json" <<'EOF'
{
  "schema_version": 1,
  "mode": "docker",
  "padm_version": "test",
  "core": {"type": "xray"},
  "host_integrations": [],
  "compose": {"project": "padm-docker", "profiles": ["core-xray"]}
}
EOF
cat >"${PADM_DOCKER_INSTALL_DIR}/images.env" <<EOF
PADM_XRAY_IMAGE=ghcr.io/example/padm-xray:test@sha256:$(printf '1%.0s' {1..64})
PADM_DOCKER_ROOT=${PADM_DOCKER_INSTALL_DIR}
EOF
printf '{"name":"padm-docker","services":{}}\n' >"${PADM_DOCKER_INSTALL_DIR}/compose.json"

: >"${TLS_WIZARD_ACTIONS}"
runPty accounts accounts '' "${TLS_WIZARD_CLI}" menu
[[ "$(<"${TLS_WIZARD_ACTIONS}")" == $'account list\naccount create --name Bob --listeners entry-reality --disabled\naccount edit alpha --name Alpha-Edited --listeners entry-reality\naccount copy alpha --name Alpha-Copy\naccount enable alpha\naccount disable alpha\naccount delete alpha --yes\naccount rotate alpha --yes' ]] ||
    fail 'account menu dispatched incorrect actions'

# 主订阅两项直接派发；分享组取消和 EOF 继续使用原菜单循环。
for subscriptionCase in flow cancel eof; do
    : >"${TLS_WIZARD_ACTIONS}"
    runPty "subscriptions-${subscriptionCase}" subscriptions "${subscriptionCase}" "${TLS_WIZARD_CLI}" menu
    expectedSubscriptions=''
    if [[ "${subscriptionCase}" == flow ]]; then
        expectedSubscriptions=$'subscription content --base\nsubscription links --base'
        ! grep -Fq '分享组 ID（0 返回）' "${CONTROL_LOG}" || fail '主订阅菜单仍要求分享组 ID'
    fi
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedSubscriptions}" ]] ||
        fail "subscriptions ${subscriptionCase} 参数分发错误或取消后仍执行操作"
    grep -Fq '10. 输出部署主订阅内容' "${CONTROL_LOG}" &&
        grep -Fq '11. 输出部署主订阅 HTTPS 链接' "${CONTROL_LOG}" || fail '主订阅菜单入口缺失'
done

# 七个 PTY 会话复用同一夹具，不重复流量后端或展开协议矩阵。
for trafficCase in flow cancel eof status-failed invalid unknown failed; do
    : >"${TLS_WIZARD_ACTIONS}"
    export TRAFFIC_SHOW_STATUS=0 TRAFFIC_ACTION_STATUS=0
    [[ "${trafficCase}" != status-failed ]] || TRAFFIC_SHOW_STATUS=17
    [[ "${trafficCase}" != failed ]] || TRAFFIC_ACTION_STATUS=17
    runPty "traffic-${trafficCase}" traffic "${trafficCase}" "${TLS_WIZARD_CLI}" menu
    limitConfirmations=0 resetConfirmations=0
    case "${trafficCase}" in
    flow)
        expectedTraffic=$'traffic show\ntraffic collect\ntraffic show\ntraffic limit alpha 0\ntraffic show\ntraffic limit alpha 0.5\ntraffic show\ntraffic limit alpha 000.500000\ntraffic show\ntraffic reset alpha\ntraffic show'
        limitConfirmations=3 resetConfirmations=1
        ;;
    cancel)
        expectedTraffic=$(printf 'traffic show\n%.0s' {1..14})
        limitConfirmations=3 resetConfirmations=3
        ;;
    eof)
        expectedTraffic=$(printf 'traffic show\n%.0s' {1..6})
        limitConfirmations=1 resetConfirmations=1
        ;;
    status-failed)
        expectedTraffic=$'traffic show\ntraffic show\ntraffic show'
        ! grep -Fq '流量账号 ID' "${CONTROL_LOG}" ||
            fail 'traffic 状态失败后仍读取账号 ID'
        ;;
    invalid)
        expectedTraffic=$'traffic show\ntraffic limit alpha not-a-limit\ntraffic show'
        limitConfirmations=1
        grep -Fq '操作失败，退出码: 2' "${CONTROL_LOG}" ||
            fail 'traffic 非法额度未保留 CLI 退出码'
        ;;
    unknown)
        expectedTraffic=$'traffic show\ntraffic limit missing-account 0.5\ntraffic show\ntraffic reset missing-account\ntraffic show'
        limitConfirmations=1 resetConfirmations=1
        [[ "$(grep -Fc '操作失败，退出码: 1' "${CONTROL_LOG}")" -eq 2 ]] ||
            fail 'traffic 未知账号失败未返回菜单'
        ;;
    failed)
        expectedTraffic=$'traffic collect\ntraffic show\ntraffic limit alpha 0.5\ntraffic show\ntraffic reset alpha\ntraffic show'
        limitConfirmations=1 resetConfirmations=1
        [[ "$(grep -Fc '操作失败，退出码: 17' "${CONTROL_LOG}")" -eq 3 ]] ||
            fail 'traffic 操作失败未保留退出码或不能继续诊断'
        ;;
    esac
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedTraffic}" ]] ||
        fail "traffic ${trafficCase} 参数分发错误或取消后仍执行操作"
    [[ "$(grep -Fc '确认设置账号' "${CONTROL_LOG}" || true)" -eq "${limitConfirmations}" &&
        "$(grep -Fc '确认清零账号' "${CONTROL_LOG}" || true)" -eq "${resetConfirmations}" ]] ||
        fail "traffic ${trafficCase} 确认次数不正确"
    grep -Fq '9. 流量与额度' "${CONTROL_LOG}" &&
        grep -Fq '1. 查看已存流量与额度' "${CONTROL_LOG}" &&
        grep -Fq '2. 立即采集并检查额度' "${CONTROL_LOG}" &&
        grep -Fq '3. 设置账号额度' "${CONTROL_LOG}" &&
        grep -Fq '4. 重置账号累计' "${CONTROL_LOG}" ||
        fail 'traffic 菜单入口缺失'
    [[ "${resetConfirmations}" -eq 0 ]] ||
        grep -Fq '上传和下载累计（保留额度）' "${CONTROL_LOG}" ||
        fail 'traffic 重置确认未说明保留额度'
done
unset TRAFFIC_SHOW_STATUS TRAFFIC_ACTION_STATUS

: >"${COMPOSE_LOG}"
runPty repeated-status-restart menu $'1\n1\n5\n1\n0\n' "${CLI}" menu
[[ "$(grep -Ec ' ps$' "${COMPOSE_LOG}")" -ge 4 ]] || fail 'repeated configured status did not complete'
[[ "$(grep -Ec ' restart$' "${COMPOSE_LOG}")" -eq 1 ]] || fail 'restart was not dispatched exactly once'

: >"${COMPOSE_LOG}"
runPty up-down menu $'3\n4\n0\n' "${CLI}" menu
grep -Eq ' up -d --remove-orphans$' "${COMPOSE_LOG}" || fail 'menu up was not dispatched'
grep -Eq ' down --remove-orphans$' "${COMPOSE_LOG}" || fail 'menu down was not dispatched'

export FAKE_RESTART_FAIL=1
runPty invalid-and-failed menu $'invalid\n5\n1\n0\n' "${CLI}" menu
grep -Fq '无效' "${CONTROL_LOG}" || fail 'invalid choice was not reported'
grep -Fq 'Docker Compose 操作失败' "${CONTROL_LOG}" || fail 'operation failure was not reported'
[[ "$(grep -Fc "${MAIN_MENU_TITLE}" "${CONTROL_LOG}")" -ge 4 ]] || fail 'failed operation did not remain in the menu'
unset FAKE_RESTART_FAIL

runPty menu-eof menu $'\004' "${CLI}" menu
assertMenu

: >"${COMPOSE_LOG}"
export FAKE_LOG_STREAM=1
runPty logs-interrupt logs '' "${CLI}" menu
grep -Eq ' logs --tail 100 --follow$' "${COMPOSE_LOG}" || fail 'menu logs did not forward bounded follow arguments'
[[ "$(grep -Ec ' ps$' "${COMPOSE_LOG}")" -ge 3 ]] || fail 'status did not work during and after interrupting logs'
grep -Fq 'configured=yes' "${TEST_ROOT}/logs-concurrent-status.log" ||
    fail 'status could not run while logs followed'
unset FAKE_LOG_STREAM

export FAKE_LOG_STREAM=1
runPty parent-term term '' "${CLI}" menu
unset FAKE_LOG_STREAM

printf 'docker-menu-regression-ok\n'
