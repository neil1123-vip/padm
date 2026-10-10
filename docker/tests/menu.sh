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

runPortAliasDriver() {
    local scenario=$1
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
    esac
    targetReply 'Docker 额外入口端口' $'0\n'
    targetReply 'Docker 协议与入口' $'0\n'
    targetReply 'Docker 管理菜单' $'0\n'
}

runMaintenanceDriver() {
    local scenario=$1 choice address answer=n
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
        fail2ban-flow)
            targetReply 'Docker Fail2ban 维护' $'1\n'
            for address in 203.0.113.9 2001:db8::9; do
                targetReply 'Docker Fail2ban 维护' $'2\n'
                targetReply '待解封 IPv4/IPv6（0 返回）: ' "${address}"$'\n'
                targetReply "确认从 padm-nginx 解封 ${address}？[y/N]: " $'y\n'
            done
            targetReply 'Docker Fail2ban 维护' $'99\n'
            ;;
        fail2ban-cancel)
            for answer in $'0\n' $'\n' $'\004'; do
                targetReply 'Docker Fail2ban 维护' $'2\n'
                targetReply '待解封 IPv4/IPv6（0 返回）: ' "${answer}"
            done
            for answer in $'n\n' $'\n' $'0\n' $'\004'; do
                targetReply 'Docker Fail2ban 维护' $'2\n'
                targetReply '待解封 IPv4/IPv6（0 返回）: ' $'203.0.113.9\n'
                targetReply '确认从 padm-nginx 解封 203.0.113.9？[y/N]: ' "${answer}"
            done
            for answer in $'n\n' $'\n' $'0\n' $'\004'; do
                targetReply 'Docker Fail2ban 维护' $'3\n'
                targetReply '确认停用受管站点扫描防护？[y/N]: ' "${answer}"
            done
            ;;
        fail2ban-disable*)
            targetReply 'Docker Fail2ban 维护' $'3\n'
            targetReply '确认停用受管站点扫描防护？[y/N]: ' $'y\n'
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
        fail2ban-menu-eof) ;;
        *)
            [[ "${scenario}" != fail2ban-failed ]] ||
                targetReply 'Docker Fail2ban 维护' $'1\n'
            targetReply 'Docker Fail2ban 维护' $'2\n'
            address=203.0.113.9
            [[ "${scenario}" != fail2ban-invalid ]] || address=not-an-ip
            targetReply '待解封 IPv4/IPv6（0 返回）: ' "${address}"$'\n'
            targetReply "确认从 padm-nginx 解封 ${address}？[y/N]: " $'y\n'
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

runSitesDriver() {
    local scenario=$1 alpnOrder alpnAction
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
        targetReply 'Docker 站点管理' $'4\n'
        ;;
    esac
    targetReply 'Docker 站点管理' $'0\n'
    targetReply 'Docker 管理菜单' $'0\n'
}

runRoutingDriver() {
    local scenario=$1 choice input
    local -A targetPrompts=()
    targetReply 'Docker 管理菜单' $'17\n'
    : >"${TLS_WIZARD_ACTIONS}"
    case "${scenario}" in
    flow|failed)
        targetReply 'Docker 路由与出站' $'invalid\n'
        targetReply 'Docker 路由与出站' $'1\n'
        targetReply 'root 私有 SOCKS5 JSON 文件绝对路径（0 返回）' $'/root/padm-socks5.json\n'
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
        targetReply 'root 私有 hosts JSON 文件绝对路径（0 返回）' $'/root/padm-hosts.json\n'
        targetReply 'Docker 路由与出站' $'9\n'
        targetReply 'Docker 路由与出站' $'10\n'
        targetReply '替换域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\n'
        targetReply 'Docker 路由与出站' $'11\n'
        targetReply 'Docker 路由与出站' $'12\n'
        targetReply '替换域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\n'
        targetReply 'Docker 路由与出站' $'13\n'
        targetReply 'Docker 路由与出站' $'14\n'
        targetReply 'root 私有 IP/CIDR 规则 JSON 文件绝对路径（0 返回）' $'/root/padm-block-ips.json\n'
        targetReply 'Docker 路由与出站' $'15\n'
        targetReply 'Docker 路由与出站' $'16\n'
        targetReply 'Docker 路由与出站' $'17\n'
        targetReply 'Docker 路由与出站' $'18\n'
        targetReply 'Docker 区域阻断策略' $'invalid\n'
        targetReply 'Docker 区域阻断策略' $'1\n'
        targetReply '追加直连例外规则' $'Example.NET, full:Exact.Example.Com\n'
        targetReply 'Docker 区域阻断策略' $'2\n'
        targetReply '追加直连例外规则' $'\n'
        targetReply 'Docker 区域阻断策略' $'3\n'
        targetReply '追加直连例外规则' $'\n'
        targetReply 'Docker 区域阻断策略' $'4\n'
        targetReply 'Docker 区域阻断策略' $'0\n'
        targetReply 'Docker 路由与出站' $'19\n'
        targetReply 'Docker IPv6 域名出站' $'invalid\n'
        targetReply 'Docker IPv6 域名出站' $'1\n'
        targetReply 'IPv6 域名规则' $'Example.NET, full:Exact.Example.Com\n'
        targetReply 'Docker IPv6 域名出站' $'2\n'
        targetReply 'Docker IPv6 域名出站' $'3\n'
        targetReply 'Docker IPv6 域名出站' $'4\n'
        targetReply 'Docker IPv6 域名出站' $'0\n'
        targetReply 'Docker 路由与出站' $'20\n'
        targetReply 'Docker WARP 出站' $'invalid\n'
        targetReply 'Docker WARP 出站' $'1\n'
        targetReply 'root 私有 WARP JSON 文件绝对路径（0 返回）' $'/root/padm-warp.json\n'
        targetReply 'Docker WARP 出站' $'2\n'
        targetReply 'Docker WARP 出站' $'3\n'
        targetReply 'Docker WARP 出站' $'0\n'
        targetReply 'Docker 路由与出站' $'21\n'
        targetReply 'Docker HTTP 中继入站' $'invalid\n'
        targetReply 'Docker HTTP 中继入站' $'1\n'
        targetReply 'root 私有 HTTP 中继 JSON 文件绝对路径（0 返回）' $'/root/padm-http-relay.json\n'
        targetReply 'Docker HTTP 中继入站' $'2\n'
        targetReply 'Docker HTTP 中继入站' $'3\n'
        targetReply 'Docker HTTP 中继入站' $'0\n'
        for choice in 22 23; do
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            targetReply '追加域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\n'
        done
        ;;
    cancel)
        targetReply 'Docker 路由与出站' $'1\n'
        targetReply 'root 私有 SOCKS5 JSON 文件绝对路径（0 返回）' $'0\n'
        targetReply 'Docker 路由与出站' $'1\n'
        targetReply 'root 私有 SOCKS5 JSON 文件绝对路径（0 返回）' $'\n'
        targetReply 'Docker 路由与出站' $'4\n'
        targetReply 'SOCKS5 域名规则（逗号分隔；domain:/full:/keyword:/geosite:，0 返回）' $'0\n'
        targetReply 'Docker 路由与出站' $'4\n'
        targetReply 'SOCKS5 域名规则（逗号分隔；domain:/full:/keyword:/geosite:，0 返回）' $'\n'
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
        targetReply 'Docker 路由与出站' $'8\n'
        targetReply 'root 私有 hosts JSON 文件绝对路径（0 返回）' $'0\n'
        targetReply 'Docker 路由与出站' $'8\n'
        targetReply 'root 私有 hosts JSON 文件绝对路径（0 返回）' $'\n'
        for choice in 10 12; do
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            targetReply '替换域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'0\n'
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            targetReply '替换域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'\n'
        done
        targetReply 'Docker 路由与出站' $'14\n'
        targetReply 'root 私有 IP/CIDR 规则 JSON 文件绝对路径（0 返回）' $'0\n'
        targetReply 'Docker 路由与出站' $'14\n'
        targetReply 'root 私有 IP/CIDR 规则 JSON 文件绝对路径（0 返回）' $'\n'
        targetReply 'Docker 路由与出站' $'18\n'
        targetReply 'Docker 区域阻断策略' $'1\n'
        targetReply '追加直连例外规则' $'0\n'
        targetReply 'Docker 区域阻断策略' $'0\n'
        targetReply 'Docker 路由与出站' $'19\n'
        targetReply 'Docker IPv6 域名出站' $'1\n'
        targetReply 'IPv6 域名规则' $'0\n'
        targetReply 'Docker IPv6 域名出站' $'1\n'
        targetReply 'IPv6 域名规则' $'\n'
        targetReply 'Docker IPv6 域名出站' $'0\n'
        targetReply 'Docker 路由与出站' $'20\n'
        targetReply 'Docker WARP 出站' $'1\n'
        targetReply 'root 私有 WARP JSON 文件绝对路径（0 返回）' $'0\n'
        targetReply 'Docker WARP 出站' $'1\n'
        targetReply 'root 私有 WARP JSON 文件绝对路径（0 返回）' $'\n'
        targetReply 'Docker WARP 出站' $'0\n'
        targetReply 'Docker 路由与出站' $'21\n'
        targetReply 'Docker HTTP 中继入站' $'1\n'
        targetReply 'root 私有 HTTP 中继 JSON 文件绝对路径（0 返回）' $'0\n'
        targetReply 'Docker HTTP 中继入站' $'1\n'
        targetReply 'root 私有 HTTP 中继 JSON 文件绝对路径（0 返回）' $'\n'
        targetReply 'Docker HTTP 中继入站' $'0\n'
        for choice in 22 23; do
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            targetReply '追加域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'0\n'
            targetReply 'Docker 路由与出站' "${choice}"$'\n'
            targetReply '追加域名规则 CSV（domain:/full:/keyword:/geosite:，0 返回）' $'\n'
        done
        ;;
    file-eof)
        targetReply 'Docker 路由与出站' $'1\n'
        targetReply 'root 私有 SOCKS5 JSON 文件绝对路径（0 返回）' $'\004'
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
            else
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
    hosts-file-eof)
        targetReply 'Docker 路由与出站' $'8\n'
        targetReply 'root 私有 hosts JSON 文件绝对路径（0 返回）' $'\004'
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
    block-ips-file-eof)
        targetReply 'Docker 路由与出站' $'14\n'
        targetReply 'root 私有 IP/CIDR 规则 JSON 文件绝对路径（0 返回）' $'\004'
        ;;
    region-eof)
        targetReply 'Docker 路由与出站' $'18\n'
        targetReply 'Docker 区域阻断策略' $'1\n'
        targetReply '追加直连例外规则' $'\004'
        targetReply 'Docker 区域阻断策略' $'0\n'
        ;;
    ipv6-eof)
        targetReply 'Docker 路由与出站' $'19\n'
        targetReply 'Docker IPv6 域名出站' $'1\n'
        targetReply 'IPv6 域名规则' $'\004'
        targetReply 'Docker IPv6 域名出站' $'0\n'
        ;;
    warp-eof)
        targetReply 'Docker 路由与出站' $'20\n'
        targetReply 'Docker WARP 出站' $'1\n'
        targetReply 'root 私有 WARP JSON 文件绝对路径（0 返回）' $'\004'
        targetReply 'Docker WARP 出站' $'0\n'
        ;;
    http-relay-eof)
        targetReply 'Docker 路由与出站' $'21\n'
        targetReply 'Docker HTTP 中继入站' $'1\n'
        targetReply 'root 私有 HTTP 中继 JSON 文件绝对路径（0 返回）' $'\004'
        targetReply 'Docker HTTP 中继入站' $'0\n'
        ;;
    esac
    targetReply 'Docker 路由与出站' $'0\n'
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
        ( "${driver}" == maintenance && ( "${input}" == fail2ban-term ||
          "${input}" == fail2ban-disable-term || "${input}" == fail2ban-verify-term ) ) ]]; then
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
        if [[ "${driver}" == source-input ]]; then
            waitForText 'fixture-source-input: ' "${CONTROL_LOG}" || exit 11
            printf '%s\n' "${input}" >&3
        elif [[ "${driver}" == setup ]]; then
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
                printf '6\n\nadmin@example.com\n1\ndns_cf\n' >&3
                waitForText 'DNS 凭据文件' "${CONTROL_LOG}" || exit 17
                printf '\004' >&3
            elif [[ "${input}" == standalone-eof ]]; then
                printf '3\n\nadmin@example.com\n2\n' >&3
                waitForText '确认执行证书操作？[y/N]' "${CONTROL_LOG}" || exit 17
                printf '\004' >&3
            elif [[ "${input}" == method-eof ]]; then
                printf '3\n\nadmin@example.com\n' >&3
                waitForText '验证方式 [1=DNS-01' "${CONTROL_LOG}" || exit 17
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
        elif [[ "${driver}" == port-alias ]]; then
            runPortAliasDriver "${input}"
        elif [[ "${driver}" == maintenance ]]; then
            runMaintenanceDriver "${input}"
        elif [[ "${driver}" == control ]]; then
            runControlDriver "${input}"
        elif [[ "${driver}" == sites ]]; then
            runSitesDriver "${input}"
        elif [[ "${driver}" == routing ]]; then
            runRoutingDriver "${input}"
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
runNonTty 0 installed-help "${CLI}" help
grep -Fq 'padm-docker fail2ban verify-source <WS 入口 ID> <外部客户端 IPv4/IPv6>' "${CONTROL_LOG}" ||
    fail 'Fail2ban 真实来源诊断缺少命令帮助'
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
dockerAcmeCommand() { recordAction acme "$@"; }
dockerRenewalCommand() { recordAction schedule "$@"; }
dockerEditCommand() {
    printf 'fixture-http01-confirm [y/N]: '
    IFS= read -r confirmation || return 0
    [[ "${confirmation}" == y ]] || return 0
    recordAction edit "$@"
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
    printf 'Docker 管理菜单\n'
    shift
    dockerMenuRun "$@"
    ;;
status)
    [[ "${SITE_MENU_RECORD_STATUS:-0}" != 1 ]] || recordAction status
    exit 0
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
    esac
    printf 'fixture-protocol-output\n'
    ;;
edit)
    recordAction "$@"
    if [[ "${2:-}" == --port-alias || "${2:-}" == --port-alias-remove ||
        "${2:-}" == --port-alias-default ]]; then
        [[ "${2:-}" == --port-alias-default && "${4:-}" == base ]] ||
            [[ "${4:-}" =~ ^[0-9]{1,5}$ ]] || exit 2
    elif [[ "${2:-}" == --direct-domains || "${2:-}" == --block-domains ||
        "${2:-}" == --direct-domains-add || "${2:-}" == --block-domains-add ]]; then
        dockerSocks5DomainsNormalize "${3:-}" >/dev/null || exit 2
    elif [[ "${2:-}" == --dns-rules ]]; then
        [[ "$#" -eq 5 && -n "${3:-}" && "${3:-}" != --* &&
            "${4:-}" =~ ^[0-9]{1,5}$ ]] || exit 2
        [[ "$((10#$4))" -ge 1 && "$((10#$4))" -le 65535 ]] || exit 2
        dockerSocks5DomainsNormalize "$5" >/dev/null || exit 2
    fi
    exit "${SITE_EDIT_STATUS:-0}"
    ;;
account) recordAction "$@" ;;
assess) recordAction "$@" ;;
validate|update|rollback|uninstall)
    recordAction "$@"
    [[ "$1" != validate ]] || exit "${MAINTENANCE_VALIDATE_STATUS:-0}"
    exit "${MAINTENANCE_STATUS:-0}"
    ;;
fail2ban)
    recordAction "$@"
    case "${2:-}" in
    status) printf 'fixture-fail2ban-status\n'; exit "${FAIL2BAN_STATUS:-0}" ;;
    unban|disable|verify-source)
        # 字面 IP 语法矩阵由服务合同覆盖，此处只验证错误返回后仍留在菜单。
        [[ "${2:-}" != unban || "${3:-}" != not-an-ip ]] || exit 2
        if [[ "${2:-}" == verify-source ]]; then
            [[ "$#" -eq 4 && "$3" == entry-fixture && "$4" != not-an-ip ]] || exit 2
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
        exit "${FAIL2BAN_UNBAN_STATUS:-0}"
        ;;
    *) exit 2 ;;
    esac
    ;;
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
# 启动与恢复共用来源输入；直接验证生产动作分组，不重复业务菜单的导航矩阵。
export SOURCE_INPUT_CHECK=1
for sourceAction in up restart update rollback fail2ban-disable business-restore; do
    case "${sourceAction}" in
    fail2ban-disable) sourceCommand=(fail2ban disable --confirm PADM-DOCKER-EDIT) ;;
    business-restore) sourceCommand=(business restore fixture.json --strategy replace --yes) ;;
    *) sourceCommand=("${sourceAction}") ;;
    esac
    : >"${TLS_WIZARD_ACTIONS}"
    runPty "source-input-${sourceAction}" source-input 203.0.113.9 \
        "${TLS_WIZARD_CLI}" source-input-menu "${sourceCommand[@]}"
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${sourceCommand[*]}"$'\nsource-input 203.0.113.9' ]] ||
        fail "${sourceAction}: 来源输入未到达前台 CLI 或参数分发错误"
done
unset SOURCE_INPUT_CHECK
printf '{"tls":null}\n' >"${TLS_WIZARD_ROOT}/config/spec.json"
: >"${TLS_WIZARD_ACTIONS}"
runPty tls-no-domain menu $'8\n0\n' "${TLS_WIZARD_CLI}" menu
grep -Fq '当前部署没有 TLS 域名' "${CONTROL_LOG}" || fail 'TLS menu accepted a deployment without a TLS domain'
[[ ! -s "${TLS_WIZARD_ACTIONS}" ]] || fail 'missing TLS domain reached a business command'
printf '{"tls":{"domain":"ws.example.com"}}\n' >"${TLS_WIZARD_ROOT}/config/spec.json"
: >"${TLS_WIZARD_ACTIONS}"
runPty core-assessment menu $'13\n0\n' "${TLS_WIZARD_CLI}" menu
[[ "$(<"${TLS_WIZARD_ACTIONS}")" == assess ]] || fail 'core assessment menu dispatched incorrect arguments'

for maintenanceCase in flow cancel update-eof uninstall-eof failed update rollback uninstall; do
    : >"${TLS_WIZARD_ACTIONS}"
    export MAINTENANCE_STATUS=0 MAINTENANCE_VALIDATE_STATUS=0
    [[ "${maintenanceCase}" != flow && "${maintenanceCase}" != failed ]] || MAINTENANCE_STATUS=17
    [[ "${maintenanceCase}" != failed ]] || MAINTENANCE_VALIDATE_STATUS=17
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
        [[ "$(grep -Fc 'Docker 管理菜单' "${CONTROL_LOG}")" -eq 1 ]] ||
            fail "维护 ${maintenanceCase} 成功后仍使用旧菜单"
        [[ "$(grep -Fc 'Docker 服务维护' "${CONTROL_LOG}")" -eq 1 ]] ||
            fail "维护 ${maintenanceCase} 成功后仍留在子菜单"
        ;;
    esac
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedMaintenance}" ]] ||
        fail "维护 ${maintenanceCase} 参数分发错误或取消后仍执行操作"
    for maintenanceLabel in '18. 服务维护' 'Docker 服务维护' '1. 校验部署配置' \
        '2. 更新镜像与控制脚本' '3. 回滚最近更新' '4. 卸载服务与控制命令（保留数据）' '5. Fail2ban 维护'; do
        grep -Fq "${maintenanceLabel}" "${CONTROL_LOG}" || fail "维护菜单缺少: ${maintenanceLabel}"
    done
done
unset MAINTENANCE_STATUS MAINTENANCE_VALIDATE_STATUS

for fail2banCase in flow cancel menu-eof invalid failed int term disable disable-failed disable-int disable-term \
    verify verify-cancel verify-list-failed verify-invalid verify-failed verify-int verify-term; do
    : >"${TLS_WIZARD_ACTIONS}"
    export FAIL2BAN_STATUS=0 FAIL2BAN_UNBAN_STATUS=0 FAIL2BAN_DISABLE_STATUS=0 \
        FAIL2BAN_VERIFY_STATUS=0 FAIL2BAN_PROTOCOL_LIST_STATUS=0 FAIL2BAN_WAIT=0 \
        FAIL2BAN_PID="${TEST_ROOT}/fail2ban.pid"
    [[ "${fail2banCase}" != failed ]] || { FAIL2BAN_STATUS=17; FAIL2BAN_UNBAN_STATUS=17; }
    [[ "${fail2banCase}" != disable-failed ]] || FAIL2BAN_DISABLE_STATUS=17
    [[ "${fail2banCase}" != verify-failed ]] || FAIL2BAN_VERIFY_STATUS=17
    [[ "${fail2banCase}" != verify-list-failed ]] || FAIL2BAN_PROTOCOL_LIST_STATUS=17
    case "${fail2banCase}" in int|term|disable-int|disable-term|verify-int|verify-term) FAIL2BAN_WAIT=1 ;; esac
    runPty "fail2ban-${fail2banCase}" maintenance "fail2ban-${fail2banCase}" "${TLS_WIZARD_CLI}" menu
    expectedFail2ban=
    case "${fail2banCase}" in
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
    esac
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedFail2ban}" ]] ||
        fail "Fail2ban ${fail2banCase} 参数分发错误或取消后仍执行操作"
    for fail2banLabel in '5. Fail2ban 维护' 'Docker Fail2ban 维护' '1. 查看状态' \
        '2. 解封单个 IP' '3. 停用站点扫描防护' '4. 核对 WS 真实来源'; do
        grep -Fq "${fail2banLabel}" "${CONTROL_LOG}" || fail "Fail2ban 菜单缺少: ${fail2banLabel}"
    done
done
unset FAIL2BAN_STATUS FAIL2BAN_UNBAN_STATUS FAIL2BAN_DISABLE_STATUS \
    FAIL2BAN_VERIFY_STATUS FAIL2BAN_PROTOCOL_LIST_STATUS FAIL2BAN_WAIT FAIL2BAN_PID

export SITE_MENU_RECORD_STATUS=1
for siteCase in flow cancel static-eof redirect-eof alpn-diagnose-eof alpn-recommended-eof \
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
        for label in '16. 站点管理' '1. 默认页' '2. 发布静态目录' '3. 302 跳转' \
            '4. 查看站点模式' '5. ALPN 诊断' '6. 修复为推荐 ALPN' '7. 手动设置 ALPN' \
            '1. h2,http/1.1' '2. http/1.1,h2' '3. http/1.1' '0. 返回'; do
            grep -Fq "${label}" "${CONTROL_LOG}" || fail "站点菜单缺少: ${label}"
        done
        ;;
    failed)
        expectedSite=$'edit --site-default\nprotocol alpn-status entry-tls\nedit --alpn entry-tls h2,http/1.1\nedit --alpn entry-tls http/1.1,h2\nstatus'
        grep -Fq '操作失败，退出码: 15' "${CONTROL_LOG}" || fail '站点提交失败未显示退出码'
        grep -Fq '操作失败，退出码: 17' "${CONTROL_LOG}" || fail 'ALPN 诊断失败未显示退出码'
        ;;
    esac
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedSite}" ]] ||
        fail "站点 ${siteCase} 参数分发错误或取消后仍执行编辑"
done
unset SITE_MENU_RECORD_STATUS SITE_EDIT_STATUS SITE_ALPN_STATUS

for routingCase in flow cancel file-eof domains-eof dns-server-eof dns-port-eof dns-domains-eof dns-explicit-port dns-invalid dns-failed hosts-file-eof direct-domains-eof block-domains-eof direct-block-invalid direct-domains-add-eof block-domains-add-eof direct-block-add-invalid direct-block-add-failed block-ips-file-eof region-eof ipv6-eof warp-eof http-relay-eof failed return; do
    : >"${TLS_WIZARD_ACTIONS}"
    export SITE_EDIT_STATUS=0 ROUTING_STATUS=0
    [[ "${routingCase}" != failed ]] || { SITE_EDIT_STATUS=15; ROUTING_STATUS=17; }
    [[ "${routingCase}" != direct-block-add-failed && "${routingCase}" != dns-failed ]] || SITE_EDIT_STATUS=15
    runPty "routing-${routingCase}" routing "${routingCase}" "${TLS_WIZARD_CLI}" menu
    expectedRouting=
    case "${routingCase}" in
    flow|failed)
        expectedRouting=$'edit --socks5 /root/padm-socks5.json\nedit --socks5-off\nprotocol routing-status\nedit --socks5-domains Example.NET, full:Exact.Example.Com, geosite:cn\nedit --socks5-global\nprotocol routing-status\nedit --dns-rules 203.0.113.53 53 Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\nedit --dns-off\nedit --hosts /root/padm-hosts.json\nedit --hosts-off\nedit --direct-domains Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\nedit --direct-off\nedit --block-domains Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\nedit --block-off\nedit --block-ips /root/padm-block-ips.json\nedit --block-ips-off\nedit --block-bt\nedit --block-bt-off'
        expectedRouting+=$'\nedit --region both --region-allow Example.NET, full:Exact.Example.Com\nedit --region domain\nedit --region ip\nedit --region-off'
        expectedRouting+=$'\nedit --ipv6 selective --ipv6-domains Example.NET, full:Exact.Example.Com\nedit --ipv6 global\nedit --ipv6-off\nprotocol routing-status'
        expectedRouting+=$'\nedit --warp /root/padm-warp.json\nedit --warp-off\nprotocol routing-status'
        expectedRouting+=$'\nedit --http-relay /root/padm-http-relay.json\nedit --http-relay-off\nprotocol routing-status'
        expectedRouting+=$'\nedit --direct-domains-add Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN\nedit --block-domains-add Example.NET, full:Exact.Example.Com, keyword:Ads, geosite:CN'
        grep -Fq '无效选项' "${CONTROL_LOG}" || fail '路由菜单没有保留无效输入后的操作'
        ;;
    dns-explicit-port)
        expectedRouting='edit --dns-rules 203.0.113.53 5353 Example.NET'
        ;;
    dns-invalid)
        expectedRouting=$'edit --dns-rules 203.0.113.53 65536 Example.NET\nedit --dns-rules 203.0.113.53 53 regexp:bad'
        [[ "$(grep -Fc '操作失败，退出码: 2' "${CONTROL_LOG}")" -eq 2 ]] ||
            fail 'DNS 非法端口或 CSV 未显示用法错误并保留菜单'
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
    esac
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedRouting}" ]] ||
        fail "路由 ${routingCase} 参数分发错误或取消后执行操作"
    if [[ "${routingCase}" == flow ]]; then
        for label in '17. 路由与出站' '1. 启用 SOCKS5 出站' '2. 关闭 SOCKS5 出站' \
            '3. 查看路由状态' '4. 替换 SOCKS5 域名规则' '5. 切换 SOCKS5 全局出站' \
            '6. 设置 DNS 分流' '7. 关闭 DNS 分流' '8. 设置 DNS/hosts 覆盖' \
            '9. 关闭 DNS/hosts 覆盖' '10. 替换 Direct 直连例外' '11. 关闭 Direct 直连例外' \
            '12. 替换 Block 域名阻断' '13. 关闭 Block 域名阻断' '14. 设置 IP/CIDR 阻断' \
            '15. 关闭 IP/CIDR 阻断' '16. 启用 BT 协议阻断' '17. 关闭 BT 协议阻断' \
            '18. 区域阻断策略' '1. 屏蔽 geosite:cn + geoip:cn' '2. 仅屏蔽 geosite:cn' \
            '3. 仅屏蔽 geoip:cn' '4. 关闭区域策略' '19. IPv6 域名出站' \
            '1. 替换 IPv6 域名规则' '2. IPv6 默认出站' '3. 关闭 IPv6 出站策略' \
            '22. 追加 Direct 直连例外' '23. 追加 Block 域名阻断' '0. 返回'; do
            grep -Fq "${label}" "${CONTROL_LOG}" || fail "路由菜单缺少: ${label}"
        done
    elif [[ "${routingCase}" == failed ]]; then
        grep -Fq '操作失败，退出码: 15' "${CONTROL_LOG}" || fail '路由提交失败未显示退出码'
        grep -Fq '操作失败，退出码: 17' "${CONTROL_LOG}" || fail '路由诊断失败后没有继续菜单'
    fi
done
unset SITE_EDIT_STATUS ROUTING_STATUS

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
    renewal-status renewal-enable renewal-disable renewal-final-no renewal-eof \
    standalone-issue standalone-renew standalone-enable standalone-final-no \
    standalone-renew-final-no standalone-enable-final-no standalone-eof method-cancel method-eof \
    webroot-issue webroot-renew webroot-enable webroot-final-no webroot-disabled webroot-other-domain \
    http01-enable http01-disable http01-enable-cancel http01-disable-cancel; do
    : >"${TLS_WIZARD_ACTIONS}"
    printf '{"tls":{"domain":"ws.example.com","http01":true}}\n' >"${TLS_WIZARD_ROOT}/config/spec.json"
    expectedAction=
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
        printf -v input '%s\n\nadmin@example.com\n1\ndns_cf\ncredentials.env\ny\n' "${choice}"
        expectedAction="acme ${tlsCase} --domain ws.example.com --email admin@example.com --dns dns_cf --credentials credentials.env"
        ;;
    renewal-status) input=$'5\n\ny\n'; expectedAction='schedule status' ;;
    renewal-enable)
        input=$'6\n\nadmin@example.com\n1\ndns_cf\ncredentials.env\ny\n'
        expectedAction='schedule enable --domain ws.example.com --email admin@example.com --dns dns_cf --credentials credentials.env'
        ;;
    renewal-disable) input=$'7\n\ny\n'; expectedAction='schedule disable --domain ws.example.com' ;;
    renewal-final-no) input=$'6\n\nadmin@example.com\n1\ndns_cf\ncredentials.env\nn\n' ;;
    renewal-eof) input=renewal-eof ;;
    standalone-issue|standalone-renew|standalone-enable|standalone-final-no|standalone-renew-final-no|standalone-enable-final-no)
        choice=3
        action=issue
        case "${tlsCase}" in
        standalone-renew*) choice=4; action=renew ;;
        standalone-enable*) choice=6; action=enable ;;
        esac
        answer=y
        [[ "${tlsCase}" != *final-no ]] || answer=n
        printf -v input '%s\n\nadmin@example.com\n2\n%s\n' "${choice}" "${answer}"
        if [[ "${answer}" == y ]]; then
            if [[ "${choice}" == 6 ]]; then
                expectedAction='schedule enable --domain ws.example.com --email admin@example.com --standalone'
            else
                expectedAction="acme ${action} --domain ws.example.com --email admin@example.com --standalone"
            fi
        fi
        ;;
    standalone-eof) input=standalone-eof ;;
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
    esac
    runPty "tls-${tlsCase}" tls "${input}" "${TLS_WIZARD_CLI}" menu
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedAction}" ]] ||
        fail "TLS ${tlsCase} bypassed confirmation or dispatched incorrect arguments"
    if [[ "${tlsCase}" == standalone-* ]]; then
        grep -Fq 'HTTP-01 需要公网 80 可达' "${CONTROL_LOG}" ||
            fail 'standalone 确认前没有说明公网 80 与短暂停机影响'
        [[ "$(grep -Fc '确认执行证书操作？[y/N]' "${CONTROL_LOG}")" == 1 ]] ||
            fail 'standalone 操作没有恰好确认一次'
        ! grep -Eq 'DNS provider|DNS 凭据文件' "${CONTROL_LOG}" ||
            fail 'standalone 仍要求 DNS 凭据'
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

: >"${TLS_WIZARD_ACTIONS}"
runPty protocols-dispatch protocols read "${TLS_WIZARD_CLI}" menu
[[ "$(<"${TLS_WIZARD_ACTIONS}")" == $'protocol list\nprotocol links entry-fixture\nedit\nedit --regenerate-reality entry-fixture' ]] ||
    fail 'protocol menu did not dispatch list, selected links, editor and Reality regeneration'
: >"${TLS_WIZARD_ACTIONS}"
runPty protocols-links-cancel protocols cancel "${TLS_WIZARD_CLI}" menu
[[ "$(<"${TLS_WIZARD_ACTIONS}")" == 'protocol list' ]] ||
    fail 'cancelled protocol link selection dispatched a business command'

# 额外入口菜单使用真实 PTY，取消与 EOF 不向 CLI 提交端口变更。
for aliasCase in flow cancel eof invalid failed default-cancel default-eof base-eof default-invalid default-failed; do
    : >"${TLS_WIZARD_ACTIONS}"
    export SITE_EDIT_STATUS=0
    [[ "${aliasCase}" != failed && "${aliasCase}" != default-failed ]] || SITE_EDIT_STATUS=15
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
    esac
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedAliases}" ]] ||
        fail "额外入口 ${aliasCase} 参数分发错误或取消后执行操作"
done
unset SITE_EDIT_STATUS

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
