#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
SELF="${PROJECT_ROOT}/docker/tests/wireguard-menu.sh"
PUBLIC=YmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmI=

if [[ "${1:-}" == wireguard || "${1:-}" == control ]]; then
    if [[ "$1" == control ]]; then
        [[ "$#" == 2 && "$2" == status ]] || exit 2
    else
        case "${2:-}" in
        status|start|stop) [[ "$#" == 2 ]] || exit 2 ;;
        prepare)
            [[ "$#" == 6 && "$3" == --address && "$5" == --listen-port ]] || exit 2 ;;
        peer)
            [[ ( "$#" == 6 || "$#" == 8 ) && "$3" == --peer-address &&
                "$5" == --peer-public-key ]] || exit 2
            [[ "$#" == 6 || "$7" == --endpoint ]] || exit 2 ;;
        *) exit 2 ;;
        esac
    fi
    printf '%s\n' "$*" >>"${WIREGUARD_MENU_ACTIONS:?}"
    if [[ "$1" == wireguard && "$2" != status ]]; then
        [[ "${WIREGUARD_MENU_FOREGROUND:-0}" != 1 || ( -t 0 && -t 1 ) ]] || exit 21
        printf 'fixture-wireguard-confirm %s: ' "$2"
        IFS= read -r reply || exit 22
        printf 'confirm %s %s\n' "$2" "${reply}" >>"${WIREGUARD_MENU_ACTIONS}"
        [[ "${reply}" == y ]] || exit 2
    fi
    [[ "$2" != status ]] || printf 'fixture-public-status\n'
    [[ "${WIREGUARD_MENU_FAIL_ALL:-0}" != 1 ]] || exit 17
    exit 0
fi

# 只替换安装路径，菜单输入、选项分发、子进程和失败处理均使用生产实现。
source "${PROJECT_ROOT}/docker/lib/setup.sh"
source "${PROJECT_ROOT}/docker/lib/menu.sh"
export PADM_DOCKER_RC_STATE=15
dockerError() { printf 'padm-docker: %s\n' "$*" >&2; }
dockerMenuCli() { printf '%s\n' "${SELF}"; }

if [[ "${1:-}" == --foreground-driver ]]; then
    case "${2:-}" in
    prepare) args=(wireguard prepare --address 10.90.0.1 --listen-port 51820) ;;
    peer) args=(wireguard peer --peer-address 10.90.0.2 --peer-public-key "${PUBLIC}") ;;
    start|stop) args=(wireguard "$2") ;;
    *) exit 2 ;;
    esac
    set -m
    status=0
    dockerMenuRun "${args[@]}" || status=$?
    [[ $- == *m* && -z "${DOCKER_MENU_CHILD_PID}" ]] || exit 23
    exit "${status}"
fi

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-wireguard-menu.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
export WIREGUARD_MENU_ACTIONS="${TEST_ROOT}/actions"
CONTROL_LOG=
CASES=0
fail() {
    [[ -z "${CONTROL_LOG}" || ! -f "${CONTROL_LOG}" ]] ||
        sed 's/^/  /' "${CONTROL_LOG}" >&2
    printf 'docker-wireguard-menu-regression-fail: %s\n' "$*" >&2
    exit 1
}
runCase() {
    local name=$1 input=$2 expected=$3 menu=${4:-dockerMenuWireGuard} status=0
    CONTROL_LOG="${TEST_ROOT}/${name}.log"
    : >"${WIREGUARD_MENU_ACTIONS}"
    printf '%s' "${input}" | "${menu}" >"${CONTROL_LOG}" 2>&1 || status=$?
    [[ "${status}" == 0 ]] || fail "${name}: 菜单返回 ${status}"
    [[ "$(<"${WIREGUARD_MENU_ACTIONS}")" == "${expected}" ]] ||
        fail "${name}: 参数分发错误或取消后执行了操作"
    CASES=$((CASES + 1))
}

runCase status $'1\n0\n' 'wireguard status'
grep -Fq fixture-public-status "${CONTROL_LOG}" || fail '状态没有显示 CLI 公开输出'
for label in '1. 查看准备状态和公钥' '2. 准备本机密钥' '3. 设置对端' \
    '4. 确认启用或启动' '5. 临时停止'; do
    grep -Fq "${label}" "${CONTROL_LOG}" || fail "缺少菜单 ${label}"
done
runCase prepare $'2\n10.90.0.1\n51821\ny\n1\n0\n' \
    $'wireguard prepare --address 10.90.0.1 --listen-port 51821\nconfirm prepare y\nwireguard status'
runCase prepare-default $'2\n10.90.0.1\n\ny\n0\n' \
    $'wireguard prepare --address 10.90.0.1 --listen-port 51820\nconfirm prepare y'
runCase peer "3"$'\n10.90.0.2\n'"${PUBLIC}"$'\n198.18.0.2:51821\ny\n1\n0\n' \
    "wireguard peer --peer-address 10.90.0.2 --peer-public-key ${PUBLIC} --endpoint 198.18.0.2:51821"$'\nconfirm peer y\nwireguard status'
runCase peer-no-endpoint "3"$'\n10.90.0.2\n'"${PUBLIC}"$'\n\ny\n0\n' \
    "wireguard peer --peer-address 10.90.0.2 --peer-public-key ${PUBLIC}"$'\nconfirm peer y'
runCase start $'4\ny\n1\n0\n' $'wireguard start\nconfirm start y\nwireguard status'
runCase stop $'5\ny\n1\n0\n' $'wireguard stop\nconfirm stop y\nwireguard status'
runCase invalid $'99\n1\n0\n' 'wireguard status'
runCase empty-address $'2\n\n1\n0\n' 'wireguard status'
runCase empty-peer $'3\n\n1\n0\n' 'wireguard status'
runCase empty-public "3"$'\n10.90.0.2\n\n1\n0\n' 'wireguard status'

for choice in 2 3; do
    fields=(10.90.0.1 51820)
    [[ "${choice}" != 3 ]] || fields=(10.90.0.2 "${PUBLIC}" 198.18.0.2:51821)
    # 每个字段的 0 和 EOF 都只能取消本次操作，不能启动子 CLI。
    for ((field = 0; field < ${#fields[@]}; field++)); do
        printf -v input '%s\n' "${choice}" "${fields[@]:0:field}" 0 1 0
        runCase "cancel-zero-${choice}-${field}" "${input}" 'wireguard status'
        printf -v input '%s\n' "${choice}" "${fields[@]:0:field}"
        runCase "cancel-eof-${choice}-${field}" "${input}" ''
    done
done
runCase empty-eof '' ''
for action in prepare peer start stop; do
    case "${action}" in
    prepare)
        input=$'2\n10.90.0.1\n51820\nn\n1\n0\n'
        expected='wireguard prepare --address 10.90.0.1 --listen-port 51820' ;;
    peer)
        input="3"$'\n10.90.0.2\n'"${PUBLIC}"$'\n\nn\n1\n0\n'
        expected="wireguard peer --peer-address 10.90.0.2 --peer-public-key ${PUBLIC}" ;;
    start) input=$'4\nn\n1\n0\n'; expected='wireguard start' ;;
    stop) input=$'5\nn\n1\n0\n'; expected='wireguard stop' ;;
    esac
    runCase "cli-cancel-${action}" "${input}" "${expected}"$'\n'"confirm ${action} n"$'\nwireguard status'
done

export WIREGUARD_MENU_FAIL_ALL=1
runCase failures "1"$'\n2\n10.90.0.1\n51820\ny\n3\n10.90.0.2\n'"${PUBLIC}"$'\n\ny\n4\ny\n5\ny\n1\n0\n' \
    $'wireguard status\nwireguard prepare --address 10.90.0.1 --listen-port 51820\nconfirm prepare y\n'"wireguard peer --peer-address 10.90.0.2 --peer-public-key ${PUBLIC}"$'\nconfirm peer y\nwireguard start\nconfirm start y\nwireguard stop\nconfirm stop y\nwireguard status'
[[ "$(grep -Fc '操作失败，退出码: 17' "${CONTROL_LOG}")" == 6 &&
    "$(grep -Fc 'Docker WireGuard 单 Peer' "${CONTROL_LOG}")" == 7 ]] ||
    fail 'CLI 失败后没有保留退出码并返回菜单'
unset WIREGUARD_MENU_FAIL_ALL

runCase control-entry $'18\n1\n0\n1\n0\n' $'wireguard status\ncontrol status' dockerMenuControl
for label in '1. 查看角色状态' '13. 启用或更新自动同步' '14. 停用自动同步' \
    '15. 重映射受管账号入口（同连接）' '16. 更新主控 API 端口' \
    '17. 被控同身份重连' '18. WireGuard 建链与维护'; do
    grep -Fq "${label}" "${CONTROL_LOG}" || fail "控制菜单编号改变或缺少 ${label}"
done

for tool in script timeout; do
    command -v "${tool}" >/dev/null 2>&1 || fail "missing tool: ${tool}"
done
export WIREGUARD_MENU_FOREGROUND=1
for action in prepare peer start stop; do
    for answer in y n; do
        : >"${WIREGUARD_MENU_ACTIONS}"
        CONTROL_LOG="${TEST_ROOT}/foreground-${action}-${answer}.log"
        printf -v command '%q ' bash "${SELF}" --foreground-driver "${action}"
        expected=0
        [[ "${answer}" != n ]] || expected=2
        status=0
        printf '%s\n' "${answer}" |
            timeout -k 2 10 script -qefc "${command}" /dev/null >"${CONTROL_LOG}" 2>&1 || status=$?
        [[ "${status}" == "${expected}" ]] ||
            fail "${action}/${answer}: 前台确认输入失败，退出码 ${status}"
        grep -qxF "confirm ${action} ${answer}" "${WIREGUARD_MENU_ACTIONS}" ||
            fail "${action}/${answer}: 输入没有到达前台 CLI"
        CASES=$((CASES + 1))
    done
done
unset WIREGUARD_MENU_FOREGROUND
printf 'docker-wireguard-menu-regression-ok: %s cases\n' "${CASES}"
