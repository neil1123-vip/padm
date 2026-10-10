#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-ssh-preflight.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-ssh-preflight-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

fail() { printf 'docker-ssh-preflight: %s\n' "$*" >&2; exit 1; }
expectStatus() {
    local expected=$1 actual=0
    shift
    "$@" >"${TEST_ROOT}/output" 2>"${TEST_ROOT}/error" || actual=$?
    [[ "${actual}" -eq "${expected}" ]] || fail "期望 ${expected}，实际 ${actual}: $*"
    ! grep -Eq 'private-account|192\.0\.2\.99|private-stderr' \
        "${TEST_ROOT}/output" "${TEST_ROOT}/error" || fail '预检泄露日志或系统命令正文'
}
forbidden() { printf '%s\n' "$*" >>"${TEST_ROOT}/forbidden"; return 99; }
docker() { forbidden docker "$@"; }
dockerLockInstalledDeployment() { forbidden deployment-lock "$@"; }
dockerInstallRoot() { forbidden install-root "$@"; }
dockerEditCommand() { forbidden edit "$@"; }
iptables() { forbidden iptables "$@"; }
ip6tables() { forbidden ip6tables "$@"; }

HOST_STATUS=0 MISSING_TOOL= SSHD_STATUS=0 SS_STATUS=0 JOURNAL_STATUS=0
CONFIG=$'port 2222\nport 22\nport 022\nusepam yes'
LISTENERS=$'LISTEN 0 128 0.0.0.0:2222 0.0.0.0:* users:(("sshd",pid=123,fd=3))\nLISTEN 0 128 [::]:22 [::]:* users:(("sshd",pid=124,fd=4))'
JOURNAL='{"_COMM":"sshd","MESSAGE":"private-account from 192.0.2.99"}'
FILE_AUTH= FILE_SECURE=
dockerHostPreflight() { printf 'host\n' >>"${TEST_ROOT}/calls"; return "${HOST_STATUS}"; }
dockerRequireCommand() {
    [[ "$1" != "${MISSING_TOOL}" ]] && command -v "$1" >/dev/null 2>&1
}
sshd() {
    [[ "$*" == -T ]] || forbidden sshd "$@"
    printf '%s\n' "${CONFIG}"
    printf 'private-stderr\n' >&2
    return "${SSHD_STATUS}"
}
ss() {
    [[ "$*" == '-H -ltnp' ]] || forbidden ss "$@"
    printf '%s\n' "${LISTENERS}"
    printf 'private-stderr\n' >&2
    return "${SS_STATUS}"
}
journalctl() {
    [[ "$*" == '--quiet --no-pager --boot --output=json --lines=1 _COMM=sshd' ]] ||
        forbidden journalctl "$@"
    printf '%s\n' "${JOURNAL}"
    printf 'private-stderr\n' >&2
    return "${JOURNAL_STATUS}"
}

# 固定路径发现单独核对；其它用临时普通文件覆盖生产安全检查，不改系统日志。
(
    dockerSshLogFileReadable() { printf '%s\n' "$1" >>"${TEST_ROOT}/fixed-paths"; return 1; }
    dockerSshFixedLogCandidates >"${TEST_ROOT}/fixed-candidates"
)
[[ "$(<"${TEST_ROOT}/fixed-paths")" == $'/var/log/auth.log\n/var/log/secure' ]] ||
    fail '日志发现使用了非固定路径'
jq -e '. == {auth_log:false,secure:false}' "${TEST_ROOT}/fixed-candidates" >/dev/null
dockerSshFixedLogCandidates() {
    local auth=false secure=false
    [[ -z "${FILE_AUTH}" ]] || { dockerSshLogFileReadable "${FILE_AUTH}" && auth=true; }
    [[ -z "${FILE_SECURE}" ]] || { dockerSshLogFileReadable "${FILE_SECURE}" && secure=true; }
    jq -cn --argjson auth "${auth}" --argjson secure "${secure}" \
        '{auth_log:$auth,secure:$secure}'
}

expectStatus 0 dockerFail2banCommand ssh preflight --json
jq -e '.scope == "host-preflight-only" and .configured_default_ports == [22,2222] and
  .observed_sshd_ports == [22,2222] and .log_candidates == {auth_log:false,secure:false,systemd:true} and
  .candidate_backends == ["systemd"] and .source_verified == false and
  .runtime_configuration_verified == false and .jail_ready == false' "${TEST_ROOT}/output" >/dev/null
expectStatus 0 dockerFail2banCommand ssh preflight
grep -qF '本次预检不启用 SSH 防护' "${TEST_ROOT}/output"
grep -qF '实时来源未证明' "${TEST_ROOT}/output"

# 真实 CLI 清理路径在空事务下不能访问安装状态或修改既有文件。
mkdir -p "${TEST_ROOT}/state/config" "${TEST_ROOT}/state/logs"
printf 'unchanged-config\n' >"${TEST_ROOT}/state/config/spec.json"
printf 'unchanged-log\n' >"${TEST_ROOT}/state/logs/existing.log"
stateDigest=$(find "${TEST_ROOT}/state" -type f -exec sha256sum {} + | sort)
(
    export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
    expectStatus 0 dockerMain fail2ban ssh preflight --json
    set +o pipefail
    CONFIG='' LISTENERS='' expectStatus 10 dockerMain fail2ban ssh preflight --json
    CONFIG=$'port 22\nport invalid' expectStatus 10 dockerMain fail2ban ssh preflight --json
    LISTENERS='LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("nginx",pid=123,fd=3))' \
        expectStatus 10 dockerMain fail2ban ssh preflight --json
)
[[ "$(find "${TEST_ROOT}/state" -type f -exec sha256sum {} + | sort)" == "${stateDigest}" ]] ||
    fail '真实 CLI 清理改写安装状态'

beforeCalls=$(wc -l <"${TEST_ROOT}/calls")
for action in status enable disable settings unban verify-source '' --json; do
    expectStatus 2 dockerFail2banCommand ssh "${action}"
done
expectStatus 2 dockerFail2banCommand ssh preflight --preview
expectStatus 2 dockerFail2banCommand ssh preflight --json extra
expectStatus 2 dockerFail2banCommand ssh preflight --json --json
expectStatus 2 dockerSshPreflight --preview
[[ "$(wc -l <"${TEST_ROOT}/calls")" == "${beforeCalls}" ]] || fail '非法参数触及宿主预检'
HOST_STATUS=1 expectStatus 10 dockerFail2banCommand ssh preflight --json
for tool in sshd ss awk stat; do
    MISSING_TOOL=${tool} expectStatus 10 dockerFail2banCommand ssh preflight --json
done
SSHD_STATUS=1 expectStatus 10 dockerFail2banCommand ssh preflight --json
SS_STATUS=1 expectStatus 10 dockerFail2banCommand ssh preflight --json

for bad in '' 'usepam yes' 'port 0' 'port 65536' 'port ssh' 'port 22 extra' 'port -22' 'port 22.0'; do
    CONFIG=${bad} expectStatus 10 dockerFail2banCommand ssh preflight --json
done
for bad in \
    'LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("nginx",pid=123,fd=3))' \
    'LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("fake-sshd",pid=123,fd=3))' \
    'LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",fd=3))' \
    'LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=0,fd=3))' \
    'LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=123,fd=3))' \
    'LISTEN 0 128 0.0.0.0:65536 0.0.0.0:* users:(("sshd",pid=123,fd=3))' \
    'LISTEN 0 128 0.0.0.0:ssh 0.0.0.0:* users:(("sshd",pid=123,fd=3))'; do
    LISTENERS=${bad} expectStatus 10 dockerFail2banCommand ssh preflight --json
done
LISTENERS="${LISTENERS}"$'\nLISTEN 0 128 [::]:2200 [::]:* users:(("sshd",pid=125,fd=5))' \
    expectStatus 10 dockerFail2banCommand ssh preflight --json
LISTENERS="${LISTENERS}"$'\nLISTEN 0 128 127.0.0.1:22 0.0.0.0:* users:(("nginx",pid=125,fd=5))' \
    expectStatus 10 dockerFail2banCommand ssh preflight --json
LISTENERS='LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=123,fd=3),("nginx",pid=125,fd=5))' \
    expectStatus 10 dockerFail2banCommand ssh preflight --json
for journal in '' broken '{}' '[]' '{"_COMM":"nginx","MESSAGE":"private-account"}'; do
    JOURNAL=${journal} expectStatus 10 dockerFail2banCommand ssh preflight --json
done
JOURNAL_STATUS=1 expectStatus 10 dockerFail2banCommand ssh preflight --json

printf 'private-account from 192.0.2.99\n' >"${TEST_ROOT}/auth.log"
chmod 0640 "${TEST_ROOT}/auth.log"
dockerSshLogFileReadable "${TEST_ROOT}/auth.log" || fail '安全候选文件被拒绝'
fileDigest=$(sha256sum "${TEST_ROOT}/auth.log")
FILE_AUTH="${TEST_ROOT}/auth.log" JOURNAL='' expectStatus 0 dockerFail2banCommand ssh preflight --json
jq -e '.log_candidates == {auth_log:true,secure:false,systemd:false} and
  .candidate_backends == ["polling"]' "${TEST_ROOT}/output" >/dev/null
FILE_SECURE="${TEST_ROOT}/auth.log" JOURNAL_STATUS=1 \
    expectStatus 0 dockerFail2banCommand ssh preflight --json
jq -e '.log_candidates.secure == true and .log_candidates.systemd == false' "${TEST_ROOT}/output" >/dev/null
[[ "$(sha256sum "${TEST_ROOT}/auth.log")" == "${fileDigest}" ]] || fail '预检改写日志'
ln -s "${TEST_ROOT}/auth.log" "${TEST_ROOT}/log-link"
FILE_AUTH="${TEST_ROOT}/log-link" JOURNAL='' \
    expectStatus 10 dockerFail2banCommand ssh preflight --json
ln -s "${TEST_ROOT}" "${TEST_ROOT}/directory-link"
if dockerSshLogFileReadable "${TEST_ROOT}/directory-link/auth.log"; then fail '父目录软链被接受'; fi
chmod 0660 "${TEST_ROOT}/auth.log"
if dockerSshLogFileReadable "${TEST_ROOT}/auth.log"; then fail '可被组写入的日志被接受'; fi
chmod 0640 "${TEST_ROOT}/auth.log"
chown 10001:10001 "${TEST_ROOT}/auth.log"
if dockerSshLogFileReadable "${TEST_ROOT}/auth.log"; then fail '非 root 日志被接受'; fi
chown 0:0 "${TEST_ROOT}/auth.log"
if dockerSshLogFileReadable "${TEST_ROOT}" || dockerSshLogFileReadable "${TEST_ROOT}/missing"; then
    fail '非普通候选日志被接受'
fi
[[ ! -e "${TEST_ROOT}/forbidden" ]] || fail '只读预检触发写入、部署锁或容器动作'
printf 'docker-ssh-preflight-regression-ok\n'
