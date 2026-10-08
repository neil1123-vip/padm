#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-wireguard-runtime.XXXXXX")
RUN_PID=
cleanup() {
    if [[ -n "${RUN_PID}" ]]; then
        kill -TERM "${RUN_PID}" 2>/dev/null || true
        wait "${RUN_PID}" 2>/dev/null || true
    fi
    rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT
trap 'printf "docker-wireguard-runtime-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1

fail() { printf 'docker-wireguard-runtime-fail: %s\n' "$*" >&2; exit 1; }
export FAKE_WG_ROOT="${TEST_ROOT}/links" FAKE_WG_LOG="${TEST_ROOT}/commands.log"
export FAKE_WG_STATE="${TEST_ROOT}/state" FAKE_WG_MODE=ok
export FAKE_WG_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
export FAKE_WG_ALIAS=padm-wireguard-11111111111111111111111111111111
mkdir -p "${TEST_ROOT}/bin" "${TEST_ROOT}/config"
CONFIG="${TEST_ROOT}/config/wg-padm.conf"

# 提取生产函数，桩只替换系统命令，不给生产入口增加测试分支。
sed '/^case "${1:-idle}" in/,$d' "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" \
    >"${TEST_ROOT}/functions.sh"
cat >"${TEST_ROOT}/runner.sh" <<'SH'
#!/bin/sh
set -eu
. "$1"
STATE_ROOT=$FAKE_WG_STATE
shift
case "$1" in
wait-cancelled)
    start_signal=143
    sleep() { : >"$FAKE_WG_SLEEP_FLAG"; kill -TERM "$$"; exit 1; }
    wait_forever
    [ ! -e "$FAKE_WG_SLEEP_FLAG" ]
    ;;
run-once)
    wait_forever() { wireguard_health wg-padm; }
    wireguard_run "$2" wg-padm
    ;;
run-wait) wireguard_run "$2" wg-padm ;;
preflight) wireguard_preflight "$2" wg-padm "${3:-unowned}" "${4:-$STATE_ROOT}" ;;
cleanup) wireguard_cleanup wg-padm ;;
health) wireguard_health wg-padm ;;
owned) wireguard_owned wg-padm "${2:-$STATE_ROOT}" ;;
*) exit 99 ;;
esac
SH
cat >"${TEST_ROOT}/bin/ip" <<'SH'
#!/usr/bin/env bash
set -eu
printf 'ip %s\n' "$*" >>"${FAKE_WG_LOG}"
[[ "${1:-}" != -o ]] || shift
[[ "${1:-}" == link ]] || exit 2
action=$2
shift 2
[[ "${1:-}" != dev ]] || shift
interface=$1
file="${FAKE_WG_ROOT}/${interface}"
case "${action}" in
show)
    [[ -f "${file}" ]] || exit 1
    index=$(sed -n '1p' "${file}")
    alias=$(sed -n '3p' "${file}")
    printf '%s: %s: <POINTOPOINT,UP> mtu 1420 state UNKNOWN' "${index}" "${interface}"
    [[ -z "${alias}" ]] || printf ' alias %s' "${alias}"
    printf '\n'
    ;;
add)
    [[ ! -e "${file}" ]] || exit 1
    printf '21\n%s\n\n' "${FAKE_WG_KEY}" >"${file}"
    [[ "${FAKE_WG_MODE}" != preflight-term ]] || kill -TERM "${PPID}"
    ;;
delete) rm -f -- "${file}" ;;
set)
    [[ "${2:-}" == alias && -f "${file}" ]] || exit 2
    if [[ "${FAKE_WG_MODE}" == alias-fail-replaced ]]; then
        printf '77\nBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=\nexternal\n' >"${file}"
        exit 1
    fi
    [[ "${FAKE_WG_MODE}" != alias-fail ]] || exit 1
    printf '%s\n%s\n%s\n' "$(sed -n '1p' "${file}")" "$(sed -n '2p' "${file}")" "$3" >"${file}.new"
    mv -- "${file}.new" "${file}"
    [[ "${FAKE_WG_MODE}" != alias-term ]] || kill -TERM "${PPID}"
    ;;
*) exit 2 ;;
esac
SH
cat >"${TEST_ROOT}/bin/wg" <<'SH'
#!/usr/bin/env bash
set -eu
if [[ "${1:-}" == pubkey ]]; then
    read -r private_key
    [[ "${private_key}" == "${FAKE_WG_KEY}" ]] || exit 1
    printf '%s\n' "${FAKE_WG_KEY}"
    exit 0
fi
[[ "${1:-}" == show && -f "${FAKE_WG_ROOT}/${2:-}" ]] || exit 1
[[ "${3:-}" != public-key ]] || sed -n '2p' "${FAKE_WG_ROOT}/$2"
SH
cat >"${TEST_ROOT}/bin/wg-quick" <<'SH'
#!/usr/bin/env bash
set -eu
action=$1 config=$2
printf 'wg-quick %s %s\n' "${action}" "${config}" >>"${FAKE_WG_LOG}"
[[ -f "${config}" ]] || exit 1
interface=$(basename "${config}" .conf)
[[ "${interface}" == wg-padm ]] || exit 1
file="${FAKE_WG_ROOT}/${interface}"
case "${action}" in
strip) cat "${config}" ;;
up)
    printf '41\n%s\n\n' "${FAKE_WG_KEY}" >"${file}"
    case "${FAKE_WG_MODE}" in
    up-fail)
        rm -f -- "${file}"
        printf 'self-rollback\n' >>"${FAKE_WG_LOG}"
        exit 1
        ;;
    up-fail-replaced)
        printf '77\nBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=\nexternal\n' >"${file}"
        exit 1
        ;;
    up-block)
        trap 'rm -f -- "${file}"; printf "self-rollback\n" >>"${FAKE_WG_LOG}"; exit 143' TERM
        : >"${FAKE_WG_ROOT}/up-ready"
        while :; do sleep 0.05; done
        ;;
    esac
    ;;
down)
    printf 'down-config %s\n' "$(sha256sum "${config}" | cut -d ' ' -f 1)" >>"${FAKE_WG_LOG}"
    [[ "${FAKE_WG_MODE}" != down-fail ]] || exit 1
    rm -f -- "${file}"
    ;;
*) exit 2 ;;
esac
SH
cat >"${TEST_ROOT}/bin/mv" <<'SH'
#!/usr/bin/env bash
set -eu
target=${!#}
if [[ "${target}" == "${FAKE_WG_STATE}/wireguard.state" ]]; then
    [[ "${FAKE_WG_MODE}" != marker-fail ]] || exit 1
    command -p mv "$@"
    [[ "${FAKE_WG_MODE}" != marker-term ]] || kill -TERM "${PPID}"
else
    command -p mv "$@"
fi
SH
cat >"${TEST_ROOT}/bin/sleep" <<'SH'
#!/usr/bin/env bash
set -eu
if [[ "${1:-}" == 86400 && -n "${FAKE_WG_SLEEP_PIDS:-}" ]]; then
    printf '%s\n' "$$" >>"${FAKE_WG_SLEEP_PIDS}"
fi
exec "$(command -p -v sleep)" "$@"
SH
chmod 0755 "${TEST_ROOT}/bin/"* "${TEST_ROOT}/runner.sh"
export PATH="${TEST_ROOT}/bin:${PATH}"

call() { sh "${TEST_ROOT}/runner.sh" "${TEST_ROOT}/functions.sh" "$@"; }
accept() {
    if ! call "$@" >"${TEST_ROOT}/output.log" 2>&1; then
        cat "${TEST_ROOT}/output.log" >&2
        fail "unexpected rejection: $*"
    fi
}
reject() {
    if call "$@" >"${TEST_ROOT}/output.log" 2>&1; then
        fail "unexpected acceptance: $*"
    fi
}
reset() {
    rm -rf -- "${FAKE_WG_ROOT}" "${FAKE_WG_STATE}"
    mkdir -p "${FAKE_WG_ROOT}" "${FAKE_WG_STATE}"
    chmod 0700 "${FAKE_WG_STATE}"
    : >"${FAKE_WG_LOG}"
    printf '[Interface]\nPrivateKey = %s\nAddress = 10.23.0.1/24\n# original\n' \
        "${FAKE_WG_KEY}" >"${CONFIG}"
    chmod 0600 "${CONFIG}"
    export FAKE_WG_MODE=ok
}
seed_owned() {
    mkdir -m 0700 "${FAKE_WG_STATE}/wireguard"
    cp "${CONFIG}" "${FAKE_WG_STATE}/wireguard/wg-padm.conf"
    chmod 0600 "${FAKE_WG_STATE}/wireguard/wg-padm.conf"
    printf '41\n%s\n%s\n' "${FAKE_WG_KEY}" "${FAKE_WG_ALIAS}" >"${FAKE_WG_ROOT}/wg-padm"
    printf 'schema_version=2\ninterface=wg-padm\nifindex=41\npublic_key=%s\nalias=%s\n' \
        "${FAKE_WG_KEY}" "${FAKE_WG_ALIAS}" >"${FAKE_WG_STATE}/wireguard.state"
    chmod 0600 "${FAKE_WG_STATE}/wireguard.state"
}
no_down() {
    ! grep -q '^wg-quick down ' "${FAKE_WG_LOG}" || fail 'unverified interface was passed to down'
    ! grep -q '^ip link delete dev wg-padm$' "${FAKE_WG_LOG}" || fail 'unverified interface was deleted'
}
wait_file() {
    local path=$1
    for ((attempt=0; attempt<200; attempt++)); do
        [[ ! -f "${path}" ]] || return 0
        kill -0 "${RUN_PID}" 2>/dev/null || break
        sleep 0.025
    done
    cat "${TEST_ROOT}/output.log" >&2
    fail "startup did not reach ${path}"
}

reset
export FAKE_WG_SLEEP_FLAG="${TEST_ROOT}/unexpected-sleep"
accept wait-cancelled
[[ ! -e "${FAKE_WG_SLEEP_FLAG}" ]] || fail 'cancelled wait started sleep'

export FAKE_WG_SLEEP_PIDS="${TEST_ROOT}/sleep.pids"
sh "${TEST_ROOT}/runner.sh" "${TEST_ROOT}/functions.sh" run-wait "${CONFIG}" \
    >"${TEST_ROOT}/output.log" 2>&1 &
RUN_PID=$!
wait_file "${FAKE_WG_STATE}/wireguard.state"
wait_file "${FAKE_WG_SLEEP_PIDS}"
accept health
accept owned
[[ "$(stat -c '%u:%a' "${FAKE_WG_STATE}/wireguard.state")" == 0:600 ]] || fail 'state is not private'
[[ "$(stat -c '%u:%a' "${FAKE_WG_STATE}/wireguard")" == 0:700 ]] || fail 'snapshot directory is not private'
[[ "$(stat -c '%u:%a' "${FAKE_WG_STATE}/wireguard/wg-padm.conf")" == 0:600 ]] || fail 'snapshot is not private'
OLD_HASH=$(sha256sum "${CONFIG}" | cut -d ' ' -f 1)
printf '# changed candidate\n' >>"${CONFIG}"
kill -TERM "${RUN_PID}"
wait "${RUN_PID}" || fail 'TERM did not finish cleanly'
RUN_PID=
while IFS= read -r sleep_pid; do
    [[ -n "${sleep_pid}" ]] || continue
    if kill -0 "${sleep_pid}" 2>/dev/null; then
        kill -TERM "${sleep_pid}" 2>/dev/null || true
        fail "sleep child ${sleep_pid} survived TERM"
    fi
done <"${FAKE_WG_SLEEP_PIDS}"
unset FAKE_WG_SLEEP_PIDS
grep -qxF "down-config ${OLD_HASH}" "${FAKE_WG_LOG}" || fail 'cleanup used the changed candidate'
[[ ! -e "${FAKE_WG_ROOT}/wg-padm" && ! -e "${FAKE_WG_STATE}/wireguard.state" &&
    ! -e "${FAKE_WG_STATE}/wireguard" ]] || fail 'successful shutdown kept recovery state'

# 任何身份字段漂移都保留接口、归属和快照，不能猜测同名接口属于本次启动。
for field in index key alias; do
    reset
    seed_owned
    STATE_HASH=$(sha256sum "${FAKE_WG_STATE}/wireguard.state" | cut -d ' ' -f 1)
    case "${field}" in
    index) sed -i '1s/.*/77/' "${FAKE_WG_ROOT}/wg-padm" ;;
    key) sed -i '2s/.*/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=/' "${FAKE_WG_ROOT}/wg-padm" ;;
    alias) sed -i '3s/.*/padm-wireguard-22222222222222222222222222222222/' "${FAKE_WG_ROOT}/wg-padm" ;;
    esac
    reject owned
    reject health
    reject cleanup
    reject run-once "${CONFIG}"
    no_down
    [[ -f "${FAKE_WG_ROOT}/wg-padm" && -f "${FAKE_WG_STATE}/wireguard/wg-padm.conf" &&
        "$(sha256sum "${FAKE_WG_STATE}/wireguard.state" | cut -d ' ' -f 1)" == "${STATE_HASH}" ]] ||
        fail "${field} drift changed recovery state"
done

reset
seed_owned
printf 'interface=wg-padm\n' >"${FAKE_WG_STATE}/wireguard.state"
reject run-once "${CONFIG}"
reject cleanup
no_down
rm -f "${FAKE_WG_ROOT}/wg-padm"
accept cleanup
[[ ! -e "${FAKE_WG_STATE}/wireguard.state" ]] || fail 'inactive legacy marker was not cleared'
accept run-once "${CONFIG}"
[[ ! -e "${FAKE_WG_ROOT}/wg-padm" ]] || fail 'fresh start after stale state did not revoke'

reset
seed_owned
printf 'touch "%s"\n' "${TEST_ROOT}/marker-executed" >>"${FAKE_WG_STATE}/wireguard.state"
reject owned
reject cleanup
no_down
[[ ! -e "${TEST_ROOT}/marker-executed" ]] || fail 'ownership state was executed as shell code'

for unsafe in wide-state state-symlink config-symlink directory-symlink wide-directory; do
    reset
    seed_owned
    case "${unsafe}" in
    wide-state) chmod 0644 "${FAKE_WG_STATE}/wireguard.state" ;;
    state-symlink)
        mv "${FAKE_WG_STATE}/wireguard.state" "${TEST_ROOT}/outside.state"
        ln -s "${TEST_ROOT}/outside.state" "${FAKE_WG_STATE}/wireguard.state"
        ;;
    config-symlink)
        rm -f "${FAKE_WG_STATE}/wireguard/wg-padm.conf"
        ln -s "${CONFIG}" "${FAKE_WG_STATE}/wireguard/wg-padm.conf"
        ;;
    directory-symlink)
        mv "${FAKE_WG_STATE}/wireguard" "${TEST_ROOT}/outside-wireguard"
        ln -s "${TEST_ROOT}/outside-wireguard" "${FAKE_WG_STATE}/wireguard"
        ;;
    wide-directory) chmod 0755 "${FAKE_WG_STATE}/wireguard" ;;
    esac
    case "${unsafe}" in
    wide-state|state-symlink) reject owned; reject health ;;
    esac
    reject cleanup
    no_down
    [[ -f "${FAKE_WG_ROOT}/wg-padm" ]] || fail "${unsafe} removed an active interface"
done

for unsafe in hook dns save-config config-symlink wrong-name missing-key invalid-key; do
    reset
    BAD_CONFIG="${CONFIG}"
    case "${unsafe}" in
    hook) printf 'PostUp = touch /tmp/padm-wireguard-hook\n' >>"${CONFIG}" ;;
    dns) printf 'DNS = 10.23.0.1\n' >>"${CONFIG}" ;;
    save-config) printf 'SaveConfig = true\n' >>"${CONFIG}" ;;
    config-symlink)
        mkdir "${TEST_ROOT}/linked"
        BAD_CONFIG="${TEST_ROOT}/linked/wg-padm.conf"
        ln -s "${CONFIG}" "${BAD_CONFIG}"
        ;;
    wrong-name)
        BAD_CONFIG="${TEST_ROOT}/config/other.conf"
        cp "${CONFIG}" "${BAD_CONFIG}"
        ;;
    missing-key) sed -i '/^PrivateKey = /d' "${CONFIG}" ;;
    invalid-key) sed -i 's/^PrivateKey = .*/PrivateKey = invalid-private-key/' "${CONFIG}" ;;
    esac
    reject run-once "${BAD_CONFIG}"
    ! grep -q '^ip link add ' "${FAKE_WG_LOG}" || fail "${unsafe} created a preflight interface"
    no_down
done

reset
seed_owned
export FAKE_WG_MODE=down-fail
reject cleanup
[[ -f "${FAKE_WG_ROOT}/wg-padm" && -f "${FAKE_WG_STATE}/wireguard.state" &&
    -f "${FAKE_WG_STATE}/wireguard/wg-padm.conf" ]] || fail 'down failure discarded recovery state'
! grep -q '^ip link delete dev wg-padm$' "${FAKE_WG_LOG}" || fail 'down failure used an unsafe delete fallback'

for mode in up-fail up-fail-replaced alias-fail alias-fail-replaced marker-fail; do
    reset
    export FAKE_WG_MODE="${mode}"
    reject run-once "${CONFIG}"
    if [[ "${mode}" == *replaced ]]; then
        no_down
        [[ "$(sed -n '1p' "${FAKE_WG_ROOT}/wg-padm")" == 77 ]] || fail "${mode} removed replacement"
    elif [[ "${mode}" == up-fail ]]; then
        no_down
        grep -qx self-rollback "${FAKE_WG_LOG}" || fail 'up failure did not use wg-quick self-rollback'
        [[ ! -e "${FAKE_WG_ROOT}/wg-padm" ]] || fail 'up failure kept the partial interface'
    else
        grep -q '^wg-quick down ' "${FAKE_WG_LOG}" || fail "${mode} did not revoke its own startup"
        [[ ! -e "${FAKE_WG_ROOT}/wg-padm" ]] || fail "${mode} kept its own startup interface"
    fi
done

for mode in alias-term marker-term; do
    reset
    export FAKE_WG_MODE="${mode}"
    reject run-once "${CONFIG}"
    grep -q '^wg-quick down ' "${FAKE_WG_LOG}" || fail "${mode} did not revoke its own startup"
    [[ ! -e "${FAKE_WG_ROOT}/wg-padm" && ! -e "${FAKE_WG_STATE}/wireguard.state" ]] ||
        fail "${mode} retained a running interface or marker"
done

reset
export FAKE_WG_MODE=up-block
sh "${TEST_ROOT}/runner.sh" "${TEST_ROOT}/functions.sh" run-wait "${CONFIG}" \
    >"${TEST_ROOT}/output.log" 2>&1 &
RUN_PID=$!
wait_file "${FAKE_WG_ROOT}/up-ready"
kill -TERM "${RUN_PID}"
STATUS=0
wait "${RUN_PID}" || STATUS=$?
RUN_PID=
[[ "${STATUS}" == 143 ]] || fail "startup TERM returned ${STATUS}"
no_down
[[ ! -e "${FAKE_WG_ROOT}/wg-padm" && ! -e "${FAKE_WG_STATE}/wireguard.state" ]] ||
    fail 'startup TERM retained an interface or marker'

reset
export FAKE_WG_MODE=preflight-term
STATUS=0
call preflight "${CONFIG}" >"${TEST_ROOT}/output.log" 2>&1 || STATUS=$?
[[ "${STATUS}" == 130 ]] || fail "preflight TERM returned ${STATUS}"
[[ -z "$(find "${FAKE_WG_ROOT}" -type f -name 'pdw*' -print -quit)" ]] ||
    fail 'preflight TERM leaked its temporary interface'
STATUS=0
call run-once "${CONFIG}" >"${TEST_ROOT}/output.log" 2>&1 || STATUS=$?
[[ "${STATUS}" == 130 ]] || fail "runtime preflight TERM returned ${STATUS}"
[[ -z "$(find "${FAKE_WG_ROOT}" -type f -name 'pdw*' -print -quit)" ]] ||
    fail 'runtime preflight TERM leaked its temporary interface'
[[ ! -e "${FAKE_WG_ROOT}/wg-padm" && ! -e "${FAKE_WG_STATE}/wireguard.state" ]] ||
    fail 'runtime preflight TERM continued startup'

reset
seed_owned
export FAKE_WG_STATE="${TEST_ROOT}/candidate-state"
mkdir -m 0700 "${FAKE_WG_STATE}"
reject preflight "${CONFIG}" owned
accept preflight "${CONFIG}" owned "${TEST_ROOT}/state"
[[ -f "${TEST_ROOT}/state/wireguard.state" &&
    ! -e "${FAKE_WG_STATE}/wireguard.state" ]] || fail 'candidate preflight copied ownership'
export FAKE_WG_STATE="${TEST_ROOT}/state"
accept cleanup

printf 'docker-wireguard-runtime-regression-ok\n'
