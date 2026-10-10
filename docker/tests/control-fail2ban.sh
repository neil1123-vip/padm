#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-control-fail2ban.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

spec="${TEST_ROOT}/spec.json"
candidate="${TEST_ROOT}/candidate"
mkdir -p "${candidate}/logs/control"
printf 'receipt remains\n' >"${candidate}/logs/control/source.receipt"
before=$(sha256sum "${candidate}/logs/control/source.receipt")
jq -n '{control:{role:"main",listen:{interface:"wg-padm",address:"10.77.0.1",port:18080}}}' >"${spec}"
dockerGenerateControlFail2banConfig "${spec}" "${candidate}" 3 600 3600
directory="${candidate}/config/net/control-fail2ban"
[[ "$(find "${directory}" -type f | wc -l)" == 4 &&
    ! -e "${candidate}/logs/control/auth.log" &&
    "$(sha256sum "${candidate}/logs/control/source.receipt")" == "${before}" ]]
grep -qxF 'failregex = ^ control-request status=401 source=<HOST> target=10\.77\.0\.1 port=18080$' \
    "${directory}/padm-control.conf"
grep -qxF 'datepattern = {^LN-BEG}%%Y-%%m-%%dT%%H:%%M:%%S.%%fZ' "${directory}/padm-control.conf"
grep -qxF 'logpath = /var/log/padm/control/auth.log' "${directory}/padm.local"
grep -qxF 'maxretry = 3' "${directory}/padm.local"
grep -qxF 'allowipv6 = no' "${directory}/fail2ban.local"
grep -qxF 'dbfile = /var/lib/padm/net/control-fail2ban.sqlite3' "${directory}/fail2ban.local"
[[ "$(grep -c '^enabled = true$' "${directory}/padm.local")" == 1 ]]
grep -qF 'fail2ban-control-action' "${directory}/padm-control-input.conf"
grep -qxF 'actionstart_on_demand = false' "${directory}/padm-control-input.conf"
grep -qF '$PADM_FAIL2BAN_CONTROL_TOKEN' "${directory}/padm-control-input.conf"
! grep -RqE 'DOCKER-USER|PADM_FAIL2BAN_TOKEN|source.receipt|padm-nginx' "${directory}"

# 生成前拒绝不可信目标和参数，不留下半份可加载配置。
reject() {
    local status=0
    dockerGenerateControlFail2banConfig "$1" "${TEST_ROOT}/rejected" "$2" "$3" "$4" >/dev/null 2>&1 || status=$?
    [[ "${status}" -ne 0 && ! -e "${TEST_ROOT}/rejected" ]]
}
for expression in \
    '.control.role = "controlled"' \
    '.control.listen.interface = "eth0"' \
    '.control.listen.address = "127.0.0.1"' \
    '.control.listen.address = "10.077.0.1"' \
    '.control.listen.address = "10.77.0.1\n[sshd]"' \
    '.control.listen.port = 1023' \
    '.control.listen.port = 65536' \
    '.control.listen.port = "18080"' \
    '.control.listen.port = 18080.5' \
    'del(.control)'; do
    jq "${expression}" "${spec}" >"${TEST_ROOT}/bad.json"
    reject "${TEST_ROOT}/bad.json" 3 600 3600
done
for retry in 0 21 03 '3;id'; do reject "${spec}" "${retry}" 600 3600; done
for window in 59 86401 060; do reject "${spec}" 3 "${window}" 3600; done
for duration in 59 604801 060; do reject "${spec}" 3 600 "${duration}"; done
printf 'docker-control-fail2ban-config-regression-ok\n'
