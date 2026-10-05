#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-menu-signals.XXXXXX")
export SIGNAL_PROJECT_ROOT="${PROJECT_ROOT}" SIGNAL_TEST_ROOT="${TEST_ROOT}"
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
status) exit 0 ;;
setup|edit)
    printf '%s\n' "${BASHPID}" >"${SIGNAL_TEST_ROOT}/setup.pid"
    trap 'printf "setup-cleaned\n"; exit 143' TERM
    source "${SIGNAL_PROJECT_ROOT}/docker/lib/setup.sh"
    printf 'setup-ready\n'
    if [[ "${SIGNAL_MODE}" == input ]]; then
        dockerSetupRead answer 'setup-input: '
    else
        # 耗时命令与孙进程均实际运行，不能仅终止 CLI 伪造清理完成。
        workerOutput=$(
            bash -c '
                printf "%s\n" "${BASHPID}" >"${SIGNAL_TEST_ROOT}/worker.pid"
                exec sleep 120
            '
            printf 'worker-finished\n'
        )
        printf '%s\n' "${workerOutput}"
    fi
    ;;
menu)
    printf '%s\n' "${BASHPID}" >"${SIGNAL_TEST_ROOT}/menu.pid"
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
    local attempt
    for ((attempt = 0; attempt < 200; attempt++)); do
        grep -Fq "$1" "${TEST_ROOT}/control.log" 2>/dev/null && return 0
        sleep 0.05
    done
    return 1
}
for mode in input worker edit-input edit-worker; do
    export SIGNAL_MODE="${mode#edit-}"
    # Linux /proc 的后代终止另行实测；MSYS2 只覆盖真实 PTY 输入。
    [[ "${SIGNAL_MODE}" != worker || "$(uname -s)" == Linux ]] || continue
    rm -f -- "${TEST_ROOT}/menu.pid" "${TEST_ROOT}/setup.pid" "${TEST_ROOT}/worker.pid" \
        "${TEST_ROOT}/input" "${TEST_ROOT}/control.log"
    mkfifo "${TEST_ROOT}/input"
    (
        exec 3>"${TEST_ROOT}/input"
        waitText 'Docker 管理菜单' || exit 11
        if [[ "${mode}" == edit-* ]]; then printf '7\n' >&3; else printf '2\n' >&3; fi
        waitText 'setup-ready' || exit 12
        if [[ "${SIGNAL_MODE}" == worker ]]; then
            for ((attempt = 0; attempt < 200; attempt++)); do
                [[ ! -f "${TEST_ROOT}/worker.pid" ]] || break
                sleep 0.05
            done
            [[ -f "${TEST_ROOT}/worker.pid" ]] || exit 13
        else
            waitText 'setup-input: ' || exit 14
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
    [[ "${rc}" -eq 143 ]] || fail "${mode}: expected 143, got ${rc}"
    grep -Fq setup-cleaned "${TEST_ROOT}/control.log" || fail "${mode}: CLI did not clean up"
    ! kill -0 "$(<"${TEST_ROOT}/setup.pid")" 2>/dev/null || fail "${mode}: CLI survived"
    if [[ "${SIGNAL_MODE}" == worker ]]; then
        ! kill -0 "$(<"${TEST_ROOT}/worker.pid")" 2>/dev/null || fail 'worker survived'
    fi
done
printf 'docker-menu-signals-regression-ok\n'
