#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-menu.XXXXXX")
MOCK_BIN="${TEST_ROOT}/bin"
DOCKER_LOG="${TEST_ROOT}/docker.log"
COMPOSE_LOG="${TEST_ROOT}/compose.log"
DOWNLOAD_MARKER="${TEST_ROOT}/download.called"
CONTROL_LOG=
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
bash "${PROJECT_ROOT}/docker/tests/menu-signals.sh"

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

export PATH="${MOCK_BIN}:${PATH}" MSYS=winsymlinks:sys SHELL
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
    local pattern=$1 file=$2 count=${3:-1} attempt
    for ((attempt = 0; attempt < 1800; attempt++)); do
        if [[ -f "${file}" ]] && [[ "$(grep -Fc "${pattern}" "${file}" || true)" -ge "${count}" ]]; then
            return 0
        fi
        sleep 0.05
    done
    return 1
}

assertNoLock() {
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] ||
        fail 'menu retained the deployment lock'
}

targetReply() {
    local prompt=$1 input=$2 count
    count=$((${targetPrompts["${prompt}"]:-0} + 1))
    targetPrompts["${prompt}"]=${count}
    waitForText "${prompt}" "${CONTROL_LOG}" "${count}" || exit 31
    assertNoLock
    [[ ! -e "${TLS_WIZARD_ROOT}/locks/deployment.lock" ]] || exit 32
    printf '%s' "${input}" >&3
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

runControlDriver() {
    local scenario=$1
    local -A targetPrompts=()
    targetReply 'Docker 管理菜单' $'15\n'
    case "${scenario}" in
    join|join-cancel|join-eof|sync|sync-cancel|sync-eof|sync-failed)
        if [[ "${scenario}" == join* ]]; then
            if [[ "${scenario}" == join-cancel ]]; then
                targetReply 'Docker 控制连接' $'5\n'
                targetReply '私有邀请文件绝对路径（0 返回）' $'0\n'
                targetReply 'Docker 控制连接' $'5\n'
                targetReply '私有邀请文件绝对路径（0 返回）' $'/root/padm-invite.json\n'
                targetReply '映射入口 ID（0 返回）' $'0\n'
            fi
            targetReply 'Docker 控制连接' $'5\n'
            targetReply '私有邀请文件绝对路径（0 返回）' $'/root/padm-invite.json\n'
            targetReply '映射入口 ID（0 返回）' $'entry-reality\n'
            case "${scenario}" in
            join-cancel) targetReply 'fixture-control-confirm [y/N]' $'n\n' ;;
            join-eof) targetReply 'fixture-control-confirm [y/N]' $'\004' ;;
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
        if [[ "${scenario}" == sync-failed ]]; then
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
                targetReply '邀请文件绝对路径（受管目录外，0 返回）' $'0\n'
                targetReply 'Docker 控制连接' $'3\n'
                targetReply '邀请文件绝对路径（受管目录外，0 返回）' $'/root/padm-invite.json\n'
                targetReply '授权有效秒数 [86400，0 返回]' $'0\n'
            fi
            targetReply 'Docker 控制连接' $'3\n'
            targetReply '邀请文件绝对路径（受管目录外，0 返回）' $'/root/padm-invite.json\n'
            if [[ "${scenario}" == invite ]]; then
                targetReply '授权有效秒数 [86400，0 返回]' $'3600\n'
            else
                targetReply '授权有效秒数 [86400，0 返回]' $'\n'
            fi
        else
            targetReply 'Docker 控制连接' $'4\n'
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

runPty() {
    local name=$1 driver=$2 input=$3 entry=$4 actual=0 feederStatus=0 command pipe feeder
    local expected=0
    shift 4
    CONTROL_LOG="${TEST_ROOT}/${name}.log"
    pipe="${TEST_ROOT}/${name}.input"
    mkfifo "${pipe}"
    printf -v command '%q ' bash -u "${entry}" "$@"
    if [[ "${driver}" == term ||
        ( ( "${driver}" == targets || "${driver}" == geo ) && "${input}" == term ) ]]; then
        printf -v command 'printf "%%s\\n" "$$" >%q; exec %s' "${TEST_ROOT}/menu.pid" "${command}"
        expected=143
    fi
    (
        exec 3>"${pipe}"
        if [[ "${driver}" != plain ]]; then
            waitForText 'Docker 管理菜单' "${CONTROL_LOG}" || exit 1
            # 等待输入时现场检查，避免只验证退出后的清理。
            [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || exit 2
        fi
        if [[ "${driver}" == setup ]]; then
            printf '2\n' >&3
            waitForText '核心 [1=Xray, 2=sing-box, 3=Xray+sing-box, 4=sing-box+Xray, 0=取消]' "${CONTROL_LOG}" || exit 11
            printf '0\n' >&3
            waitForText 'Docker 管理菜单' "${CONTROL_LOG}" 2 || exit 12
            printf '0\n' >&3
        elif [[ "${driver}" == tls ]]; then
            printf '8\n' >&3
            waitForText 'Docker 证书管理' "${CONTROL_LOG}" || exit 13
            [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || exit 14
            if [[ "${input}" == eof ]]; then
                printf '2\n\ncertificate.pem\n' >&3
                waitForText '私钥文件' "${CONTROL_LOG}" || exit 15
                printf '\004' >&3
            elif [[ "${input}" == renewal-eof ]]; then
                printf '6\n\nadmin@example.com\ndns_cf\n' >&3
                waitForText 'DNS 凭据文件' "${CONTROL_LOG}" || exit 17
                printf '\004' >&3
            else
                printf '%s' "${input}" >&3
            fi
            waitForText 'Docker 管理菜单' "${CONTROL_LOG}" 2 || exit 16
            printf '0\n' >&3
        elif [[ "${driver}" == protocols ]]; then
            printf '9\n' >&3
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
            waitForText 'Docker 管理菜单' "${CONTROL_LOG}" 2 || exit 24
            printf '1\n' >&3
            waitForText 'Docker 管理菜单' "${CONTROL_LOG}" 3 || exit 25
            printf '0\n' >&3
        elif [[ "${driver}" == targets ]]; then
            runTargetsDriver "${input}"
        elif [[ "${driver}" == geo ]]; then
            runGeoDriver "${input}"
        elif [[ "${driver}" == control ]]; then
            runControlDriver "${input}"
        elif [[ "${driver}" == accounts ]]; then
            local accountMenuCount=1
            printf '10\n' >&3
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
            waitForText 'Docker 管理菜单' "${CONTROL_LOG}" 2 || exit 29
            printf '0\n' >&3
        elif [[ "${driver}" == logs || "${driver}" == term ]]; then
            printf '6\n' >&3
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
            waitForText 'Docker 管理菜单' "${CONTROL_LOG}" 2 || exit 6
            [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || exit 7
            printf '1\n' >&3
            waitForText 'Docker 管理菜单' "${CONTROL_LOG}" 3 || exit 8
            printf '0\n' >&3
        elif [[ "${driver}" != plain && "${input}" == $'\004' ]]; then
            printf '\004' >&3
        elif [[ "${driver}" != plain ]]; then
            local menuCount=1 line
            while IFS= read -r line || [[ -n "${line}" ]]; do
                printf '%s\n' "${line}" >&3
                menuCount=$((menuCount + 1))
                [[ "${line}" != 0 ]] || break
                waitForText 'Docker 管理菜单' "${CONTROL_LOG}" "${menuCount}" || exit 8
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
    assertNoLock
    if [[ "${driver}" == logs || "${driver}" == term ]]; then
        ! kill -0 "$(<"${FAKE_LOG_PID}")" 2>/dev/null || fail "${name}: log process survived the menu action"
    fi
}

assertMenu() {
    grep -Fq 'Docker 管理菜单' "${CONTROL_LOG}" || fail 'PTY did not enter the menu'
}

assertHelpOnly() {
    grep -Fq '用法:' "${CONTROL_LOG}" || fail 'non-TTY invocation did not show usage'
    ! grep -Fq 'Docker 管理菜单' "${CONTROL_LOG}" || fail 'non-TTY invocation entered the menu'
    [[ ! -e "${DOWNLOAD_MARKER}" ]] || fail 'help invocation attempted a module download'
    [[ ! -s "${DOCKER_LOG}" ]] || fail 'help invocation touched Docker'
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}" ]] || fail 'help invocation initialized deployment state'
}

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
cp "${PROJECT_ROOT}/shell/core/"{runtime.sh,reality_targets.sh,cores.sh} "${SOURCE_ROOT}/shell/core/"
TEST_REF=1111111111111111111111111111111111111111

export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/non-tty-state"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/non-tty-bin"
runNonTty 0 non-tty-install "${PROJECT_ROOT}/install-docker.sh" \
    install --source "${SOURCE_ROOT}" --ref "${TEST_REF}"
[[ -f "${PADM_DOCKER_INSTALL_DIR}/mode" ]] || fail 'non-TTY install did not initialize the state'
! grep -Fq 'Docker 管理菜单' "${CONTROL_LOG}" || fail 'non-TTY install entered the menu'
assertNoLock

export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/no-menu-state"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/no-menu-bin"
runPty install-no-menu plain $'\004' "${PROJECT_ROOT}/install-docker.sh" \
    install --source "${SOURCE_ROOT}" --ref "${TEST_REF}" --no-menu
[[ -f "${PADM_DOCKER_INSTALL_DIR}/mode" ]] || fail '--no-menu install did not initialize the state'
! grep -Fq 'Docker 管理菜单' "${CONTROL_LOG}" || fail '--no-menu install entered the menu'

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
source "${PROJECT_ROOT}/docker/lib/setup.sh"
dockerError() { printf '%s\n' "$*" >&2; }
dockerInstallRoot() { printf '%s\n' "${TLS_WIZARD_ROOT}"; }
dockerDomainIsValid() { [[ "$1" == ws.example.com || "$1" == other.example.com ]]; }
dockerEmailIsValid() { [[ "$1" == admin@example.com ]]; }
dockerConfigureSpecValidate() { return 0; }
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
dockerAcmeCommand() { recordAction acme "$@"; }
dockerRenewalCommand() { recordAction schedule "$@"; }
PADM_DOCKER_RC_STATE=15
PADM_DOCKER_RC_USAGE=2
case "${1:-}" in
status) exit 0 ;;
protocol)
    recordAction "$@"
    case "${2:-}" in
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
    esac
    printf 'fixture-protocol-output\n'
    ;;
edit) recordAction "$@" ;;
account) recordAction "$@" ;;
assess) recordAction "$@" ;;
control)
    recordAction "$@"
    case "${2:-}" in
    status) printf 'fixture-control-status\n' ;;
    init|invite|revoke|join)
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
printf '{"tls":null}\n' >"${TLS_WIZARD_ROOT}/config/spec.json"
: >"${TLS_WIZARD_ACTIONS}"
runPty tls-no-domain menu $'8\n0\n' "${TLS_WIZARD_CLI}" menu
grep -Fq '当前部署没有 TLS 域名' "${CONTROL_LOG}" || fail 'TLS menu accepted a deployment without a TLS domain'
[[ ! -s "${TLS_WIZARD_ACTIONS}" ]] || fail 'missing TLS domain reached a business command'
printf '{"tls":{"domain":"ws.example.com"}}\n' >"${TLS_WIZARD_ROOT}/config/spec.json"
: >"${TLS_WIZARD_ACTIONS}"
runPty core-assessment menu $'13\n0\n' "${TLS_WIZARD_CLI}" menu
[[ "$(<"${TLS_WIZARD_ACTIONS}")" == assess ]] || fail 'core assessment menu dispatched incorrect arguments'

: >"${TLS_WIZARD_ACTIONS}"
runPty control-dispatch control flow "${TLS_WIZARD_CLI}" menu
for controlLabel in '15. 控制连接' '1. 查看角色状态' '2. 初始化主控' '3. 邀请或轮换凭据' \
    '4. 撤销授权' '5. 接入被控角色' '6. 同步受管账号' '0. 返回'; do
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

for controlCase in join join-cancel join-eof sync sync-cancel sync-eof sync-failed; do
    : >"${TLS_WIZARD_ACTIONS}"
    export CONTROL_INIT_STATUS=0
    [[ "${controlCase}" != sync-failed ]] || CONTROL_INIT_STATUS=17
    runPty "control-${controlCase}" control "${controlCase}" "${TLS_WIZARD_CLI}" menu
    expectedControl=
    case "${controlCase}" in
    join*)
        expectedControl='control join --invite /root/padm-invite.json --listener entry-reality'
        case "${controlCase}" in
        join-cancel) expectedControl+=$'\ncontrol-confirm n' ;;
        join-eof) expectedControl+=$'\ncontrol-confirm eof' ;;
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
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedControl}" ]] ||
        fail "control ${controlCase} dispatched incorrect arguments or committed after cancellation"
    if [[ "${controlCase}" == sync* ]]; then
        ! grep -Fq 'fixture-control-confirm [y/N]' "${CONTROL_LOG}" ||
            fail "control ${controlCase} added an unnecessary confirmation"
    fi
done
unset CONTROL_INIT_STATUS

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
    renewal-status renewal-enable renewal-disable renewal-final-no renewal-eof; do
    : >"${TLS_WIZARD_ACTIONS}"
    expectedAction=
    case "${tlsCase}" in
    cancel) input=$'0\n' ;;
    final-no) input=$'3\n\nadmin@example.com\ndns_cf\ncredentials.env\nn\n' ;;
    eof) input=eof ;;
    validate) input=$'1\n\ny\n'; expectedAction='validate --domain ws.example.com' ;;
    install)
        input=$'2\nother.example.com\ncertificate.pem\nprivate-key.pem\ny\n'
        expectedAction='install --domain other.example.com --cert certificate.pem --key private-key.pem'
        ;;
    issue|renew)
        if [[ "${tlsCase}" == issue ]]; then choice=3; else choice=4; fi
        printf -v input '%s\n\nadmin@example.com\ndns_cf\ncredentials.env\ny\n' "${choice}"
        expectedAction="acme ${tlsCase} --domain ws.example.com --email admin@example.com --dns dns_cf --credentials credentials.env"
        ;;
    renewal-status) input=$'5\n\ny\n'; expectedAction='schedule status' ;;
    renewal-enable)
        input=$'6\n\nadmin@example.com\ndns_cf\ncredentials.env\ny\n'
        expectedAction='schedule enable --domain ws.example.com --email admin@example.com --dns dns_cf --credentials credentials.env'
        ;;
    renewal-disable) input=$'7\n\ny\n'; expectedAction='schedule disable --domain ws.example.com' ;;
    renewal-final-no) input=$'6\n\nadmin@example.com\ndns_cf\ncredentials.env\nn\n' ;;
    renewal-eof) input=renewal-eof ;;
    esac
    runPty "tls-${tlsCase}" tls "${input}" "${TLS_WIZARD_CLI}" menu
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedAction}" ]] ||
        fail "TLS ${tlsCase} bypassed confirmation or dispatched incorrect arguments"
done

: >"${TLS_WIZARD_ACTIONS}"
runPty protocols-dispatch protocols read "${TLS_WIZARD_CLI}" menu
[[ "$(<"${TLS_WIZARD_ACTIONS}")" == $'protocol list\nprotocol links entry-fixture\nedit\nedit --regenerate-reality entry-fixture' ]] ||
    fail 'protocol menu did not dispatch list, selected links, editor and Reality regeneration'
: >"${TLS_WIZARD_ACTIONS}"
runPty protocols-links-cancel protocols cancel "${TLS_WIZARD_CLI}" menu
[[ "$(<"${TLS_WIZARD_ACTIONS}")" == 'protocol list' ]] ||
    fail 'cancelled protocol link selection dispatched a business command'

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
[[ "$(grep -Fc 'Docker 管理菜单' "${CONTROL_LOG}")" -ge 4 ]] || fail 'failed operation did not remain in the menu'
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
