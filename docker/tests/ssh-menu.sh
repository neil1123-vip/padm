#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
SELF="${PROJECT_ROOT}/docker/tests/ssh-menu.sh"

if [[ "${1:-}" == fail2ban ]]; then
    [[ "${2:-}" == ssh ]] || exit 2
    case "${3:-}" in
    status) [[ "$#" == 3 ]] || exit 2 ;;
    unban) [[ "$#" == 4 ]] || exit 2 ;;
    disable)
        [[ "$#" == 5 && "$4" == --confirm && "$5" == PADM-DOCKER-EDIT ]] || exit 2
        ;;
    enable|settings)
        [[ "$#" == 11 && "${10}" == --confirm && "${11}" == PADM-DOCKER-EDIT ]] || exit 2
        ;;
    *) exit 2 ;;
    esac
    printf '%s\n' "$*" >>"${SSH_MENU_ACTIONS:?}"
    if [[ "${SSH_MENU_FOREGROUND:-0}" == 1 ]]; then
        IFS= read -r input || exit 21
        [[ "${input}" == foreground-input ]] || exit 22
        printf 'foreground %s %s\n' "$3" "${input}" >>"${SSH_MENU_ACTIONS}"
    fi
    [[ "$3" != status ]] || printf 'fixture-ssh-status\n'
    [[ "${SSH_MENU_FAIL_ALL:-0}" != 1 ]] || exit 17
    exit 0
fi

source "${PROJECT_ROOT}/docker/lib/setup.sh"
source "${PROJECT_ROOT}/docker/lib/menu.sh"
export PADM_DOCKER_RC_STATE=15
dockerError() { printf 'padm-docker: %s\n' "$*" >&2; }
# 只替换安装路径边界，菜单分发、输入、子进程和失败处理保留生产实现。
dockerMenuCli() { printf '%s\n' "${SELF}"; }

if [[ "${1:-}" == --foreground-driver ]]; then
    case "${2:-}" in
    disable) args=(fail2ban ssh disable --confirm PADM-DOCKER-EDIT) ;;
    enable|settings)
        args=(fail2ban ssh "$2" sshd-padm.service 198.51.100.10 22220 7 900 7200
            --confirm PADM-DOCKER-EDIT)
        ;;
    *) exit 2 ;;
    esac
    set -m
    dockerMenuRun "${args[@]}"
    [[ $- == *m* && -z "${DOCKER_MENU_CHILD_PID}" ]] || exit 23
    exit 0
fi

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-ssh-menu.XXXXXX")
CONTROL_LOG=
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
export SSH_MENU_ACTIONS="${TEST_ROOT}/actions"

fail() {
    [[ -z "${CONTROL_LOG}" || ! -f "${CONTROL_LOG}" ]] ||
        sed 's/^/  /' "${CONTROL_LOG}" >&2
    printf 'docker-ssh-menu-regression-fail: %s\n' "$*" >&2
    exit 1
}

runCase() {
    local name=$1 input=$2 expected=$3 status=0
    CONTROL_LOG="${TEST_ROOT}/${name}.log"
    : >"${SSH_MENU_ACTIONS}"
    dockerMenuFail2ban <<<"${input}" >"${CONTROL_LOG}" 2>&1 || status=$?
    [[ "${status}" == 0 ]] || fail "${name}: 菜单返回 ${status}"
    [[ "$(<"${SSH_MENU_ACTIONS}")" == "${expected}" ]] ||
        fail "${name}: 参数分发错误或取消后执行了操作"
}

runCase status $'15\n0\n' 'fail2ban ssh status'
grep -Fq fixture-ssh-status "${CONTROL_LOG}" || fail 'SSH 状态未显示 CLI 输出'
for label in '15. 查看 SSH 防护状态' '16. 解封 SSH 单个 IP' '17. 停用 SSH 防护' \
    '18. 启用专用 SSH service 防护' '19. 修改 SSH 防护参数'; do
    grep -Fq "${label}" "${CONTROL_LOG}" || fail "菜单缺少 ${label}"
done

runCase unban-v4 $'16\n203.0.113.9\ny\n15\n0\n' \
    $'fail2ban ssh unban 203.0.113.9\nfail2ban ssh status'
runCase unban-v6 $'16\n2001:db8::9\nYES\n0\n' 'fail2ban ssh unban 2001:db8::9'
runCase unban-cancel-address $'16\n0\n15\n0\n' 'fail2ban ssh status'
runCase unban-cancel-confirm $'16\n203.0.113.9\nn\n15\n0\n' 'fail2ban ssh status'
runCase unban-default-cancel $'16\n203.0.113.9\n\n15\n0\n' 'fail2ban ssh status'
runCase disable $'17\ny\n15\n0\n' \
    $'fail2ban ssh disable --confirm PADM-DOCKER-EDIT\nfail2ban ssh status'
runCase disable-cancel $'17\nn\n15\n0\n' 'fail2ban ssh status'
runCase disable-cancel-zero $'17\n0\n15\n0\n' 'fail2ban ssh status'

fields=(sshd-padm.service 198.51.100.10 22220 7 900 7200)
for choice in 18 19; do
    action=enable
    [[ "${choice}" != 19 ]] || action=settings
    printf -v input '%s\n' "${choice}" "${fields[@]}" y 15 0
    runCase "${action}" "${input}" \
        "fail2ban ssh ${action} ${fields[*]} --confirm PADM-DOCKER-EDIT"$'\nfail2ban ssh status'
    printf -v input '%s\n' "${choice}" "${fields[@]}" n 15 0
    runCase "${action}-cancel-confirm" "${input}" 'fail2ban ssh status'
    # 每个字段的 0 都只能取消本次操作，后续状态仍须可用。
    for ((field = 0; field < ${#fields[@]}; field++)); do
        printf -v input '%s\n' "${choice}" "${fields[@]:0:field}" 0 15 0
        runCase "${action}-cancel-${field}" "${input}" 'fail2ban ssh status'
    done
done
runCase enable-defaults $'18\nsshd-padm.service\n2001:db8::10\n22220\n\n\n\ny\n0\n' \
    'fail2ban ssh enable sshd-padm.service 2001:db8::10 22220 6 600 3600 --confirm PADM-DOCKER-EDIT'
runCase settings-empty-required $'19\nsshd-padm.service\n198.51.100.10\n22220\n\n15\n0\n' \
    'fail2ban ssh status'

export SSH_MENU_FAIL_ALL=1
printf -v input '%s\n' 15 16 203.0.113.9 y 17 y 18 "${fields[@]}" y 19 "${fields[@]}" y 15 0
runCase failed "${input}" \
    $'fail2ban ssh status\nfail2ban ssh unban 203.0.113.9\nfail2ban ssh disable --confirm PADM-DOCKER-EDIT\n'"fail2ban ssh enable ${fields[*]} --confirm PADM-DOCKER-EDIT"$'\n'"fail2ban ssh settings ${fields[*]} --confirm PADM-DOCKER-EDIT"$'\nfail2ban ssh status'
[[ "$(grep -Fc '操作失败，退出码: 17' "${CONTROL_LOG}")" == 6 ]] ||
    fail 'SSH 操作失败未保留退出码'
[[ "$(grep -Fc 'Docker Fail2ban 维护' "${CONTROL_LOG}")" == 7 ]] ||
    fail 'SSH 操作失败后退出了菜单'
unset SSH_MENU_FAIL_ALL

for tool in script timeout; do
    command -v "${tool}" >/dev/null 2>&1 || fail "missing tool: ${tool}"
done
export SSH_MENU_FOREGROUND=1
for action in enable settings disable; do
    : >"${SSH_MENU_ACTIONS}"
    CONTROL_LOG="${TEST_ROOT}/foreground-${action}.log"
    printf -v command '%q ' bash "${SELF}" --foreground-driver "${action}"
    status=0
    printf 'foreground-input\n' |
        timeout -k 2 10 script -qefc "${command}" /dev/null >"${CONTROL_LOG}" 2>&1 || status=$?
    [[ "${status}" == 0 ]] || fail "${action}: SSH CLI 前台输入失败，退出码 ${status}"
    grep -qxF "foreground ${action} foreground-input" "${SSH_MENU_ACTIONS}" ||
        fail "${action}: 后续输入没有到达前台 CLI"
done
unset SSH_MENU_FOREGROUND
printf 'docker-ssh-menu-regression-ok\n'
