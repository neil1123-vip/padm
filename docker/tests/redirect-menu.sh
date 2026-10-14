#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-redirect-menu.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
# 共用菜单只替代 CLI 边界，校验派发、返回、EOF 和失败后继续查看状态。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
dockerMenuRun() {
    printf '%s\n' "$*" >>"${TEST_ROOT}/calls"
    if [[ "$1" == protocol ]]; then
        [[ "${STATUS_FAIL:-0}" == 0 ]] || return 17
        printf '%s\n' '{"enabled":true,"port":31298,"family":"dual","output_uid":65534}'
    else
        return 17
    fi
}
runMenu() {
    : >"${TEST_ROOT}/calls"
    dockerMenuTProxy redirect <<<"$1" >"${TEST_ROOT}/output"
    [[ "$(cat "${TEST_ROOT}/calls")" == "$2" ]]
    grep -q '仅捕获 TCP' "${TEST_ROOT}/output"
}
runMenu $'1\n2\n31301\nipv6\n3\n31302\nipv4\n5\n65533\n6\n4\n1\n0' \
    $'protocol redirect-status\nprotocol redirect-status\nedit --redirect-enable 31301 --redirect-family ipv6\nprotocol redirect-status\nedit --redirect-settings 31302 --redirect-family ipv4\nprotocol redirect-status\nedit --redirect-settings 31298 --redirect-family dual --redirect-output-uid 65533\nprotocol redirect-status\nedit --redirect-settings 31298 --redirect-family dual --redirect-output-off\nedit --redirect-off\nprotocol redirect-status'
runMenu $'2\n0\n3\n0\n5\n0\n0' \
    $'protocol redirect-status\nprotocol redirect-status\nprotocol redirect-status'
runMenu $'2\n' 'protocol redirect-status'
STATUS_FAIL=1 runMenu $'2\n3\n5\n6\n1\n0' \
    $'protocol redirect-status\nprotocol redirect-status\nprotocol redirect-status\nprotocol redirect-status\nprotocol redirect-status'
# 路由菜单的公开编号必须通向同一受测子菜单。
: >"${TEST_ROOT}/calls"
dockerMenuRouting <<< $'47\n1\n0\n0' >"${TEST_ROOT}/output"
[[ "$(cat "${TEST_ROOT}/calls")" == 'protocol redirect-status' ]]
printf 'docker-redirect-menu-ok\n'
