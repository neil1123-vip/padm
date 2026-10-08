#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-control-invite.XXXXXX")
OUTPUT_ROOT=$(mktemp -d /root/.padm-control-invite-test.XXXXXX)
trap 'rm -rf -- "${TEST_ROOT}" "${OUTPUT_ROOT}"' EXIT
trap 'printf "docker-control-invite-fail: line %s, rc=%s, callers=%s\n" "${LINENO}" "$?" "${BASH_LINENO[*]}" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
export PYTHONDONTWRITEBYTECODE=1
root=${PADM_DOCKER_INSTALL_DIR}
mkdir -p "${root}/config/control" "${root}/backups"
chmod 0700 "${root}" "${OUTPUT_ROOT}"
chmod 0755 "${root}/config"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

fail() { printf 'docker-control-invite-fail: %s\n' "$*" >&2; exit 1; }
reject() {
    local status=0
    "$@" >"${TEST_ROOT}/rejected.log" 2>&1 || status=$?
    [[ "${status}" -ne 0 ]] || fail "应拒绝: $*"
}
spec="${root}/config/spec.json"
jq -n '{
  schema_version:3,
  release:{version:"3.1.8", manifest_sha256:("1"*64), signature_identity:"fixture"},
  core:{type:"xray", secondary_type:null, protocols:[{
    id:1, core:"xray", server:"reality.example.com", public_port:443,
    address_families:["ipv4"], listener_id:"entry-reality", name:"main",
    uuid:"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    reality:{server_name:"reality.example.com", target_host:"reality.example.com",
      target_port:443, private_key:("A"*43), public_key:("B"*43), short_id:"1234abcd"}
  }]},
  tls:null, subscription:{enabled:false, token:"invite-subscription-secret"},
  images:(["xray","sing-box","nginx","ops","net"] |
    map({key:.,value:("ghcr.io/example/padm-" + . + ":test@sha256:" + ("1"*64))}) | from_entries),
  host_integrations:[{type:"wireguard",profile:"net-wireguard",firewall_rules:[],
    devices:["wg-padm"],schedules:[],settings:{config_file:"wg-padm.conf",interface:"wg-padm"}}],
  accounts:[{id:"11111111-1111-4111-8111-111111111111",name:"邀请账号",enabled:true,
    uuid:"22222222-2222-4222-8222-222222222222",password:"Invite.-~@+=:Secret",
    shadowsocks_password:null,listeners:["entry-reality"]}],
  control:{schema_version:1,role:"main",node_id:"33333333-3333-4333-8333-333333333333",
    listen:{interface:"wg-padm",address:"10.77.0.1",port:18080},
    peer:{id:"44444444-4444-4444-8444-444444444444",address:"10.77.0.2",
      enabled:false,expires_at:1,token_sha256:("a"*64)},revision:0,last_digest:null}
}' >"${TEST_ROOT}/initial.json"
chmod 0600 "${TEST_ROOT}/initial.json"
python3 "${PROJECT_ROOT}/docker/images/ops/control_state.py" --spec "${TEST_ROOT}/initial.json" >"${TEST_ROOT}/plan.json"
jq '.spec' "${TEST_ROOT}/plan.json" >"${spec}"
jq '.state' "${TEST_ROOT}/plan.json" >"${root}/config/control/state.json"
chmod 0600 "${spec}"
chmod 0750 "${root}/config/control"
chmod 0640 "${root}/config/control/state.json"
cp -- "${spec}" "${TEST_ROOT}/main.json"
jq -r '.images | to_entries[] |
  "PADM_" + (if .key == "sing-box" then "SINGBOX" else (.key | ascii_upcase) end) +
  "_IMAGE=" + .value' "${spec}" >"${root}/images.env"

# 网络和 Docker 调度使用桩；邀请交付、角色校验、摘要与生产规划器均实际执行。
dockerHostPreflight() { printf 'host\n' >>"${TEST_ROOT}/host.log"; }
dockerLockInstalledDeployment() {
    local number=0
    [[ ! -f "${TEST_ROOT}/lock-count" ]] || number=$(<"${TEST_ROOT}/lock-count")
    number=$((number + 1))
    printf '%s\n' "${number}" >"${TEST_ROOT}/lock-count"
    printf 'lock\n' >>"${TEST_ROOT}/host.log"
    if [[ "${number}" == 2 && -f "${TEST_ROOT}/change-role" ]]; then
        jq 'del(.control)' "${spec}" >"${TEST_ROOT}/changed-role.json"
        cp -- "${TEST_ROOT}/changed-role.json" "${spec}"
        chmod 0600 "${spec}"
    fi
}
dockerReleaseDeploymentLock() { printf 'unlock\n' >>"${TEST_ROOT}/host.log"; }
dockerConfigureReleaseReuseInstalled() { :; }
dockerManagedSpecMatchesDeployment() { [[ ! -f "${TEST_ROOT}/bad-deployment" ]]; }
dockerCurrentOwnsHostIntegration() { [[ "$1" == wireguard && ! -f "${TEST_ROOT}/unowned" ]]; }
dockerControlPeerCheck() { [[ "$1" == 10.77.0.2 && ! -f "${TEST_ROOT}/bad-peer" ]]; }
dockerComposeRun() {
    [[ "${DOCKER_COMPOSE_TIMEOUT:-}" == 10 && "$1" == exec && "$2" == -T ]] || return 1
    case "$3" in
    net-wireguard) [[ ! -f "${TEST_ROOT}/bad-health" ]] ;;
    control) : ;;
    *) return 1 ;;
    esac
}
dockerRealityProbeRun() {
    if [[ " $* " == *' /opt/padm/control_state.py '* ||
        " $* " == *'from control_state import published_state'* ]]; then
        local previous= directory= code=
        for argument in "$@"; do
            if [[ "${previous}" == --mount ]]; then
                directory=${argument#type=bind,src=}
                directory=${directory%,dst=/input,readonly}
            fi
            [[ "${previous}" != -c ]] || code=${argument}
            previous=${argument}
        done
        [[ -n "${directory}" && " $* " == *' --network none '* ]] || return 1
        if [[ -n "${code}" ]]; then
            PYTHONPATH="${PROJECT_ROOT}/docker/images/ops" python3 -c "${code}" \
                "${directory}/spec.json" "${directory}/state.json"
        else
            python3 "${PROJECT_ROOT}/docker/images/ops/control_state.py" --spec "${directory}/spec.json" \
                --check-state "${directory}/state.json"
        fi
    elif [[ " $* " == *' --entrypoint openssl '* ]]; then
        [[ "$1" == 10 ]] || return 1
        shift
        docker run --rm --read-only --cap-drop ALL --security-opt no-new-privileges "$@"
    else
        [[ "$1" == 10 && " $* " == *' --network host '* &&
            " $* " == *'from control_api import require_wireguard_address'* &&
            "${!#}" == 10.77.0.1 && ! -f "${TEST_ROOT}/bad-address" ]]
    fi
}
docker() {
    [[ "$1" == run && " $* " == *' --log-driver none '* &&
        " $* " == *' --network none '* && " $* " == *' --cap-drop ALL '* &&
        " $* " == *' --entrypoint openssl '* && "${!#}" == 24 ]] || return 1
    local number=0
    [[ ! -f "${TEST_ROOT}/token-count" ]] || number=$(<"${TEST_ROOT}/token-count")
    number=$((number + 1))
    printf '%s\n' "${number}" >"${TEST_ROOT}/token-count"
    [[ ! -f "${TEST_ROOT}/empty-token" ]] || return 0
    if [[ -f "${TEST_ROOT}/multiline-token" ]]; then
        printf '%048x\n%048x\n' "${number}" "${number}"
        return 0
    fi
    printf '%048x\n' "${number}"
}
dockerConfigureApply() {
    [[ "${DOCKER_CONTROL_TRANSACTION:-0}" == 1 &&
        "$(stat -c '%a:%u' "$1")" == 600:0 ]] || return 1
    printf 'apply\n' >>"${TEST_ROOT}/apply.log"
    if [[ -f "${TEST_ROOT}/failed-recovery" ]]; then
        DOCKER_CONFIG_CANDIDATE="${root}/.candidate.failed"
        mkdir -- "${DOCKER_CONFIG_CANDIDATE}"
        printf '{}\n' >"${DOCKER_CONFIG_CANDIDATE}/control-plan.json"
        DOCKER_CONFIG_SWITCHED=1
        DOCKER_CONFIG_BACKUP=
        return 17
    fi
    if [[ -f "${TEST_ROOT}/signal" ]]; then kill -s "$(<"${TEST_ROOT}/signal")" "${BASHPID}"; fi
    [[ ! -f "${TEST_ROOT}/fail-apply" ]] || return 17
    python3 "${PROJECT_ROOT}/docker/images/ops/control_state.py" --spec "$1" --previous "${spec}" \
        >"${TEST_ROOT}/plan.json" || return 1
    jq '.spec' "${TEST_ROOT}/plan.json" >"${spec}" &&
        jq '.state' "${TEST_ROOT}/plan.json" >"${root}/config/control/state.json" &&
        chmod 0600 "${spec}" && chmod 0640 "${root}/config/control/state.json"
}
reset_locks() { printf '0\n' >"${TEST_ROOT}/lock-count"; }
check_api() {
    cp -- "${root}/config/control/state.json" "${OUTPUT_ROOT}/api-state.json"
    chmod 0640 "${OUTPUT_ROOT}/api-state.json"
    python3 - "${PROJECT_ROOT}" "${OUTPUT_ROOT}/api-state.json" "$1" "${2:-}" <<'PY'
import http.client
import json
import sys
import threading
from pathlib import Path

sys.path.insert(0, sys.argv[1] + "/docker/images/ops")
import control_api as api

state_path = Path(sys.argv[2])
state = api.read_state(state_path)
invitation = json.loads(Path(sys.argv[3]).read_text())
old = json.loads(Path(sys.argv[4]).read_text()) if sys.argv[4] else None

class Handler(api.ControlHandler):
    def setup(self):
        super().setup()
        self.client_address = (state["peer"]["address"], self.client_address[1])

    def log_message(self, *_):
        pass

server = api.ControlServer(("127.0.0.1", 0), Handler)
server.state_path = state_path
server.listen = state["listen"]
thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.02})
thread.start()

def request(token):
    connection = http.client.HTTPConnection(*server.server_address, timeout=3)
    connection.request("GET", "/v1/health", headers={
        "Authorization": "Bearer " + token, "X-Padm-Control-Version": "1"})
    response = connection.getresponse()
    status, body = response.status, response.read()
    connection.close()
    assert token.encode() not in body
    return status, json.loads(body)

try:
    expected = 200 if state["peer"]["enabled"] else 401
    status, body = request(invitation["token"])
    assert status == expected, "已交付邀请须满足生产 API 鉴权合同"
    if expected == 200:
        assert body["controller_id"] == invitation["controller_id"]
        assert body["node_id"] == invitation["node_id"]
    if old:
        assert request(old["token"])[0] == 401, "轮换后旧邀请不得继续认证"
finally:
    server.shutdown()
    thread.join()
    server.server_close()
PY
    rm -- "${OUTPUT_ROOT}/api-state.json"
}
check_clean() {
    [[ -z "$(find "${root}" -maxdepth 1 \( -name '.control-invite.*' -o -name '.control-revoke.*' \) -print -quit)" &&
        -z "$(find "${OUTPUT_ROOT}" -maxdepth 1 -name '.padm-control-invite.*' -print -quit)" ]]
}
original=$(sha256sum "${spec}")
output="${OUTPUT_ROOT}/invite.json"
reject dockerControlCommand invite
reject dockerControlCommand invite --output relative.json --yes
reject dockerControlCommand invite --output "${root}/invite.json" --yes
reject dockerControlCommand invite --output "${root%/*}//${root##*/}/invite.json" --yes
reject dockerControlInviteOutputCheck "${OUTPUT_ROOT}/inside.json" "${OUTPUT_ROOT%/*}//${OUTPUT_ROOT##*/}"
reject dockerControlCommand invite --output "${output}" --expires-in 59 --yes
reject dockerControlCommand invite --output "${output}" --expires-in 604801 --yes
reject dockerControlCommand invite --output "${output}" --expires-in 060 --yes
reject dockerControlCommand invite --output "${output}" --expires-in 60 --expires-in 60 --yes
reject dockerControlCommand invite --output "${output}" --output "${output}" --yes
reject dockerControlCommand invite --output "${output}" --yes --yes
reject dockerControlCommand invite --output "${output}" --unknown --yes
reject dockerControlCommand invite --output "${output}"
reject dockerControlCommand revoke --yes --yes
reject dockerControlCommand revoke
[[ ! -f "${TEST_ROOT}/host.log" ]] || fail '参数失败触及宿主'
chmod 0770 "${OUTPUT_ROOT}"
reject dockerControlCommand invite --output "${output}" --yes
chmod 0700 "${OUTPUT_ROOT}"
ln -s "${OUTPUT_ROOT}" "${OUTPUT_ROOT}/link"
reject dockerControlCommand invite --output "${OUTPUT_ROOT}/link/invite.json" --yes
rm -- "${OUTPUT_ROOT}/link"
ln -s "${OUTPUT_ROOT}/missing" "${output}"
reject dockerControlCommand invite --output "${output}" --yes
rm -- "${output}"
for marker in bad-deployment unowned bad-peer bad-health bad-address; do
    touch "${TEST_ROOT}/${marker}"
    reject dockerControlCommand invite --output "${output}" --yes
    rm -- "${TEST_ROOT}/${marker}"
    [[ ! -e "${output}" && "$(sha256sum "${spec}")" == "${original}" ]]
    check_clean
done
# 角色冲突不能生成或启用邀请。
jq 'del(.control)' "${TEST_ROOT}/main.json" >"${spec}"
chmod 0600 "${spec}"
reject dockerControlCommand invite --output "${output}" --yes
reject dockerControlCommand revoke --yes
jq 'del(.control) | .control_sync = {
  schema_version:1,role:"controlled",node_id:"55555555-5555-4555-8555-555555555555",
  controller_id:"33333333-3333-4333-8333-333333333333",listener_ids:["entry-reality"],
  last_revision:null,last_digest:null,managed_accounts:[]
}' "${TEST_ROOT}/main.json" >"${spec}"
chmod 0600 "${spec}"
reject dockerControlCommand invite --output "${output}" --yes
reject dockerControlCommand revoke --yes
cp -- "${TEST_ROOT}/main.json" "${spec}"
chmod 0600 "${spec}"
for marker in empty-token multiline-token; do
    touch "${TEST_ROOT}/${marker}"
    reset_locks
    reject dockerControlCommand invite --output "${output}" --yes
    rm -- "${TEST_ROOT}/${marker}"
    [[ ! -e "${output}" && "$(sha256sum "${spec}")" == "${original}" ]]
    check_clean
done

reset_locks
dockerControlCommand invite --output "${output}" --expires-in 60 --yes >"${TEST_ROOT}/invite.log"
[[ "$(stat -c '%a:%u:%g' "${output}")" == 600:0:0 ]]
jq -e 'keys == ["controller_id","expires_at","format","listen","node_id","peer_address","schema_version","token"] and
  .format == "padm-docker-control-invite" and .schema_version == 1 and
  .controller_id == "33333333-3333-4333-8333-333333333333" and
  .node_id == "44444444-4444-4444-8444-444444444444" and
  .peer_address == "10.77.0.2" and (.token | test("^[a-f0-9]{48}$"))' "${output}" >/dev/null
token=$(jq -r '.token' "${output}")
digest=$(jq -jr '.token' "${output}" | sha256sum); digest=${digest%% *}
jq -e --arg digest "${digest}" --slurpfile invite "${output}" '
  .control.peer.enabled == true and .control.peer.token_sha256 == $digest and
  .control.peer.expires_at == $invite[0].expires_at and .control.revision == 0
' "${spec}" >/dev/null
[[ "$(jq '.expires_at' "${output}")" -ge "$(date +%s)" ]]
if grep -Fq -- "${token}" "${spec}" "${root}/config/control/state.json" "${TEST_ROOT}/invite.log"; then
    fail '原邀请 token 泄露到规格或日志'
fi
status=$(dockerControlCommand status --json)
jq -e '.authorization.enabled == true and .authorization.expires_at > 1 and
  (.authorization | keys) == ["enabled","expires_at"]' <<<"${status}" >/dev/null
[[ "${status}" != *"${token}"* && "${status}" != *"${digest}"* ]]
check_api "${output}"
copyDigest=$(sha256sum "${output}")
reject dockerControlCommand invite --output "${output}" --yes
[[ "$(sha256sum "${output}")" == "${copyDigest}" ]]
check_clean

rotated="${OUTPUT_ROOT}/rotated.json"
reset_locks
dockerControlCommand invite --output "${rotated}" --expires-in 604800 --yes >"${TEST_ROOT}/rotate.log"
rotatedToken=$(jq -r '.token' "${rotated}")
[[ "${rotatedToken}" != "${token}" && "$(sha256sum "${output}")" == "${copyDigest}" ]]
rotatedDigest=$(jq -jr '.token' "${rotated}" | sha256sum); rotatedDigest=${rotatedDigest%% *}
jq -e --arg digest "${rotatedDigest}" '.control.peer.token_sha256 == $digest and
  .control.peer.enabled == true and .control.revision == 0' "${spec}" >/dev/null
check_api "${rotated}" "${output}"
# 网络故障不应阻挡撤销，摘要保留且重复撤销不重部署。
applyCount=$(wc -l <"${TEST_ROOT}/apply.log")
touch "${TEST_ROOT}/bad-health" "${TEST_ROOT}/bad-address" "${TEST_ROOT}/fail-apply"
dockerControlCommand revoke --yes >"${TEST_ROOT}/revoke.log"
jq -e --arg digest "${rotatedDigest}" '.control.peer.token_sha256 == $digest and
  .control.peer.enabled == false and .control.peer.expires_at == 1 and .control.revision == 0' "${spec}" >/dev/null
check_api "${rotated}"
[[ "$(stat -c '%a:%u:%g' "${root}/config/control/state.json")" == 640:0:10001 &&
    "$(wc -l <"${TEST_ROOT}/apply.log")" == "${applyCount}" ]]
dockerControlCommand revoke --yes >/dev/null
[[ "$(wc -l <"${TEST_ROOT}/apply.log")" == "${applyCount}" ]]
rm -- "${TEST_ROOT}/bad-health" "${TEST_ROOT}/bad-address" "${TEST_ROOT}/fail-apply"
check_clean

# 原子替换前失败不改状态；状态成功后的失败或信号只允许补齐撤销。
reset_locks
dockerControlCommand invite --output "${OUTPUT_ROOT}/interrupted.json" --yes >/dev/null
mv() {
    if [[ "${!#}" == "${root}/config/control/state.json" &&
        -f "${TEST_ROOT}/fail-revoke-state" ]]; then return 1; fi
    if [[ "${!#}" == "${spec}" && -f "${TEST_ROOT}/fail-revoke-spec" ]]; then return 1; fi
    command mv "$@"
    if [[ "${!#}" == "${root}/config/control/state.json" &&
        -f "${TEST_ROOT}/revoke-signal" ]]; then
        kill -s "$(<"${TEST_ROOT}/revoke-signal")" "${BASHPID}"
    fi
}
beforeSpec=$(sha256sum "${spec}")
beforeState=$(sha256sum "${root}/config/control/state.json")
touch "${TEST_ROOT}/fail-revoke-state"
reject dockerControlCommand revoke --yes
[[ "$(sha256sum "${spec}")" == "${beforeSpec}" &&
    "$(sha256sum "${root}/config/control/state.json")" == "${beforeState}" ]]
check_api "${OUTPUT_ROOT}/interrupted.json"
rm -- "${TEST_ROOT}/fail-revoke-state"
touch "${TEST_ROOT}/fail-revoke-spec"
reject dockerControlCommand revoke --yes
jq -e '.control.peer.enabled == true' "${spec}" >/dev/null
check_api "${OUTPUT_ROOT}/interrupted.json"
reject dockerControlStateCheck "${root}"
cp -- "${root}/config/control/state.json" "${TEST_ROOT}/revoked-state.json"
jq '.revision += 1' "${TEST_ROOT}/revoked-state.json" >"${root}/config/control/state.json"
reject dockerControlCommand revoke --yes
cp -- "${TEST_ROOT}/revoked-state.json" "${root}/config/control/state.json"
chmod 0640 "${root}/config/control/state.json"
cp -- "${spec}" "${TEST_ROOT}/interrupted-spec.json"
sed 's/"revision": 0,/"revision": 1, "revision": 0,/' "${TEST_ROOT}/interrupted-spec.json" >"${spec}"
reject dockerControlCommand revoke --yes
cp -- "${TEST_ROOT}/interrupted-spec.json" "${spec}"
chmod 0600 "${spec}"
rm -- "${TEST_ROOT}/fail-revoke-spec"
dockerControlCommand revoke --yes >/dev/null
dockerControlStateCheck "${root}"
check_api "${OUTPUT_ROOT}/interrupted.json"
check_clean
for signal in INT TERM; do
    reset_locks
    invitation="${OUTPUT_ROOT}/revoke-${signal}.json"
    dockerControlCommand invite --output "${invitation}" --yes >/dev/null
    printf '%s\n' "${signal}" >"${TEST_ROOT}/revoke-signal"
    status=0
    dockerControlCommand revoke --yes >"${TEST_ROOT}/revoke-signal.log" 2>&1 || status=$?
    [[ "${signal}:${status}" == INT:130 || "${signal}:${status}" == TERM:143 ]]
    jq -e '.control.peer.enabled == true' "${spec}" >/dev/null
    check_api "${invitation}"
    rm -- "${TEST_ROOT}/revoke-signal"
    dockerControlCommand revoke --yes >/dev/null
    dockerControlStateCheck "${root}"
    check_api "${invitation}"
    check_clean
done
unset -f mv

# 交付后锁内重查失败仍保留文件，不能宣称它已生效。
reset_locks
touch "${TEST_ROOT}/change-role"
reject dockerControlCommand invite --output "${OUTPUT_ROOT}/changed-role.json" --yes
[[ -f "${OUTPUT_ROOT}/changed-role.json" ]]
grep -q '授权状态未确认，请查看 control status' "${TEST_ROOT}/rejected.log"
rm -- "${TEST_ROOT}/change-role"
cp -- "${TEST_ROOT}/main.json" "${spec}"
chmod 0600 "${spec}"
cp -- "${TEST_ROOT}/main.json" "${TEST_ROOT}/current.json"
python3 "${PROJECT_ROOT}/docker/images/ops/control_state.py" --spec "${spec}" >"${TEST_ROOT}/plan.json"
jq '.state' "${TEST_ROOT}/plan.json" >"${root}/config/control/state.json"
chmod 0640 "${root}/config/control/state.json"
for signal in INT TERM; do
    reset_locks
    printf '%s\n' "${signal}" >"${TEST_ROOT}/signal"
    status=0
    dockerControlCommand invite --output "${OUTPUT_ROOT}/${signal}.json" --yes \
        >"${TEST_ROOT}/signal.log" 2>&1 || status=$?
    [[ "${signal}:${status}" == INT:130 || "${signal}:${status}" == TERM:143 ]]
    [[ -f "${OUTPUT_ROOT}/${signal}.json" && "$(sha256sum "${spec}")" == "${original}" ]]
    grep -q '授权状态未确认，请查看 control status' "${TEST_ROOT}/signal.log"
    check_clean
done
rm -- "${TEST_ROOT}/signal"
reset_locks
touch "${TEST_ROOT}/fail-apply"
reject dockerControlCommand invite --output "${OUTPUT_ROOT}/failed.json" --yes
[[ -f "${OUTPUT_ROOT}/failed.json" && "$(sha256sum "${spec}")" == "${original}" ]]
rm -- "${TEST_ROOT}/fail-apply"
check_clean
reset_locks
touch "${TEST_ROOT}/failed-recovery"
reject dockerControlCommand invite --output "${OUTPUT_ROOT}/failed-recovery.json" --yes
[[ -f "${OUTPUT_ROOT}/failed-recovery.json" && -f "${root}/.candidate.failed/control-plan.json" ]]
rm -- "${TEST_ROOT}/failed-recovery"
dockerRemoveManagedTree "${root}" "${root}/.candidate.failed"
check_clean

# 原子交付遇到文件或目录竞争不覆盖，也不能启用未交付的授权。
ln() {
    local target=${!#}
    if [[ "${target}" == "${OUTPUT_ROOT}/race-file.json" ]]; then
        printf 'existing\n' >"${target}"
    elif [[ "${target}" == "${OUTPUT_ROOT}/race-directory.json" ]]; then
        mkdir -- "${target}"
    fi
    command ln "$@"
}
reset_locks
reject dockerControlCommand invite --output "${OUTPUT_ROOT}/race-file.json" --yes
[[ "$(<"${OUTPUT_ROOT}/race-file.json")" == existing && "$(sha256sum "${spec}")" == "${original}" ]]
reset_locks
reject dockerControlCommand invite --output "${OUTPUT_ROOT}/race-directory.json" --yes
[[ -d "${OUTPUT_ROOT}/race-directory.json" &&
    -z "$(find "${OUTPUT_ROOT}/race-directory.json" -mindepth 1 -print -quit)" ]]
unset -f ln
check_clean
printf 'docker-control-invite-regression-ok\n'
