#!/usr/bin/env bash
set -Eeuo pipefail
trap 'printf "docker-recovery-apply-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
export PYTHONDONTWRITEBYTECODE=1 PADM_DOCKER_SKIP_CHOWN=0 PADM_DOCKER_LOCK_TIMEOUT=1
if [[ "${1:-}" != --child ]]; then
    TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-recovery-apply.XXXXXX")
    export TEST_ROOT
    trap 'rm -rf -- "${TEST_ROOT}"' EXIT
fi
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
for tool in jq python3 stat chmod chown find cmp sha256sum; do
    command -v "${tool}" >/dev/null || exit 1
done
ALICE=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
HISTORY=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb
DOMAIN=ws.example.com
MODE=ok
LOG=${TEST_ROOT}/command.log
CASES=0

fail() {
    [[ ! -f "${LOG}" ]] || sed 's/^/  /' "${LOG}" >&2
    [[ ! -f "${MOCK_BACKEND:-}/events" ]] || sed 's/^/  backend: /' "${MOCK_BACKEND}/events" >&2
    printf 'docker-recovery-apply-fail: %s\n' "$*" >&2
    exit 1
}

# 归档、规格、候选安装和事务均使用生产实现，只隔离宿主及容器后端。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { :; }
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
dockerTrafficRuntimeCheck() { :; }
dockerConfigurePortsAvailable() { :; }
dockerTlsValidateCandidate() { :; }
dockerRealityTargetsValidate() { :; }
dockerIPv6NetworkManage() { :; }
dockerConfigureReleasePrepare() {
    DOCKER_STAGED_BUNDLE_PATH="${TEST_ROOT}/bundle"
    DOCKER_CONFIG_RELEASE_INPUTS=$(jq -c '{release,images}' "${TEST_ROOT}/base.json")
}
dockerCandidateCompose() {
    local candidate=$1
    [[ -d "${candidate}" && -d "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] ||
        fail '候选校验未持有部署锁'
    jq -e '.services.xray != null and .services.evil == null' \
        "${candidate}/compose.json" >/dev/null || fail '候选没有重新生成 Compose'
}
dockerComposeRun() {
    [[ "$1" == up ]] || fail "非预期在线动作: $*"
    DOCKER_TEST_OWNER=${BASHPID}
    printf 'up\n' >>"${MOCK_BACKEND}/events"
    : >"${MOCK_BACKEND}/compose-container"
    : >"${MOCK_BACKEND}/padm-container"
    case "${MODE}" in
    health) return 1 ;;
    int) kill -INT "${BASHPID}" ;;
    term) kill -TERM "${BASHPID}" ;;
    killed) kill -KILL "${BASHPID}" ;;
    esac
}
dockerRenewalScheduleInstall() { :; }
dockerGeoScheduleInstall() { :; }
dockerControlLogScheduleInstall() { :; }
dockerControlSyncScheduleInstall() { :; }
dockerRestoreConfiguration() { fail '恢复应用调用了普通配置回滚'; }
systemctl() {
    [[ "${MOCK_SCHEDULER}" == systemd ]] || return 1
    printf 'systemctl:%s\n' "$*" >>"${MOCK_BACKEND}/events"
    case "$1" in
    show-environment|daemon-reload|stop) return 0 ;;
    show)
        [[ "$2" != --property=DropInPaths ]] || return 0
        [[ "$2" == --property=FragmentPath ]] || return 1
        [[ ! -f "${PADM_DOCKER_SYSTEMD_DIR}/${!#}" ]] ||
            printf '%s\n' "${PADM_DOCKER_SYSTEMD_DIR}/${!#}"
        return 0 ;;
    is-enabled) [[ -e "${MOCK_BACKEND}/enabled" ]]; return $? ;;
    is-active) [[ -e "${MOCK_BACKEND}/active" ]]; return $? ;;
    enable)
        : >"${MOCK_BACKEND}/enabled"
        [[ "$*" != *--now* ]] || : >"${MOCK_BACKEND}/active"
        if [[ "${MODE}" == scheduler || "${MODE}" == scheduler-killed ]]; then
            : >"${MOCK_BACKEND}/fault"
            [[ "${MODE}" != scheduler-killed ]] || {
                kill -KILL "${DOCKER_TEST_OWNER}"
                exit 137
            }
            return 1
        fi ;;
    disable)
        rm -f -- "${MOCK_BACKEND}/enabled"
        [[ "$*" != *--now* ]] || rm -f -- "${MOCK_BACKEND}/active" ;;
    start) : >"${MOCK_BACKEND}/active" ;;
    *) return 1 ;;
    esac
}
pgrep() { [[ "${MOCK_SCHEDULER}" == cron && "$*" == '-x cron' ]]; }
crontab() {
    case "$1" in
    -l) cat -- "${MOCK_BACKEND}/crontab" ;;
    -)
        cat >"${MOCK_BACKEND}/crontab"
        if [[ ( "${MODE}" == scheduler || "${MODE}" == scheduler-killed ) &&
            ! -e "${MOCK_BACKEND}/fault" ]]; then
            : >"${MOCK_BACKEND}/fault"
            [[ "${MODE}" != scheduler-killed ]] || {
                kill -KILL "${DOCKER_TEST_OWNER}"
                exit 137
            }
            return 1
        fi ;;
    *) return 1 ;;
    esac
}
mv() {
    local last=${!#} argument
    if [[ "${MODE}" == first-write && "${last}" == "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json" ]]; then
        : >"${MOCK_BACKEND}/fault"
        return 1
    fi
    if [[ "${MODE}" == partial-move && "${last}" == "${PADM_DOCKER_INSTALL_DIR}/config/" ]]; then
        for argument in "$@"; do
            if [[ "${argument}" == "${PADM_DOCKER_INSTALL_DIR}/.candidate."*/config/xray ]]; then
                command mv -- "${argument}" "${last}" || return 1
                : >"${MOCK_BACKEND}/fault"
                return 1
            fi
        done
    fi
    command mv "$@"
}
python3() {
    if [[ "${MODE}" == committed && "$*" == *'recovery.py transaction-clean '* ]] &&
        command python3 -B "${DOCKER_LIB_DIR}/recovery.py" transaction-check \
            --root "${PADM_DOCKER_INSTALL_DIR}" --project "${PADM_DOCKER_PROJECT}" |
            jq -e '.state == "committed"' >/dev/null; then
        kill -KILL "${BASHPID}"
    fi
    command python3 "$@"
}

if [[ "${1:-}" == --child ]]; then
    action=$2 MODE=$3
    export PADM_DOCKER_INSTALL_DIR=$4
    export MOCK_BACKEND="${TEST_ROOT}/backend-${4##*/}" MOCK_MODE="${MODE}"
    export PADM_DOCKER_SYSTEMD_DIR="${MOCK_BACKEND}/units" PADM_DOCKER_BIN_DIR="${MOCK_BACKEND}/bin"
    export PATH="${TEST_ROOT}/bin:${PATH}"
    case "${action}" in
    apply)
        dockerMain restore apply "${TEST_ROOT}/private recovery archive.tar" \
            --confirm PADM-DOCKER-RESTORE ;;
    unconfirmed) dockerMain restore apply "${TEST_ROOT}/private recovery archive.tar" ;;
    bad-confirm)
        dockerMain restore apply "${TEST_ROOT}/private recovery archive.tar" --confirm wrong ;;
    recover) dockerMain restore recover ;;
    lock) dockerAcquireDeploymentLock ;;
    *) exit 1 ;;
    esac
    exit $?
fi

mkdir -p -- "${TEST_ROOT}/bundle/docker/contracts" "${TEST_ROOT}/bin"
printf '%s\n' "$(printf 'a%.0s' {1..40})" >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
cp -- "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
cp -- "${PROJECT_ROOT}/docker/contracts/features.json" \
    "${TEST_ROOT}/bundle/docker/contracts/features.json"
# env 直接执行此后端，确保恢复使用登记内编排，而不是已移动的在线文件。
cat >"${TEST_ROOT}/bin/docker" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${MOCK_MODE}" != offline ]] || exit 1
if [[ "${1:-}" == ps && "${2:-}" == -aq && "$#" == 8 &&
    "$3" == --filter && "$4" == label=com.docker.compose.project=padm-docker &&
    "$5" == --filter && "$7" == --filter && "$8" == label=com.docker.compose.oneoff=False ]]; then
    case "$6" in
    label=com.docker.compose.service=net-transparent | \
        label=com.docker.compose.service=net-fail2ban | \
        label=com.docker.compose.service=net-fail2ban-control | \
        label=com.docker.compose.service=net-fail2ban-ssh) exit 0 ;;
    esac
fi
if [[ "${1:-}" == ps && "${2:-}" == -aq && "${3:-}" == --filter && "$#" == 4 ]]; then
    printf 'ps:%s\n' "$4" >>"${MOCK_BACKEND}/events"
    case "$4" in
    label=com.docker.compose.project=*)
        [[ ! -e "${MOCK_BACKEND}/compose-container" ]] || printf '0123456789ab\n' ;;
    label=io.padm.project=*)
        [[ ! -e "${MOCK_BACKEND}/padm-container" ]] || printf 'abcdef012345\n' ;;
    *) exit 1 ;;
    esac
    exit 0
fi
if [[ "${1:-}" == compose ]]; then
    compose= action=
    while [[ "$#" -gt 0 ]]; do
        if [[ "$1" == --file ]]; then compose=$2; shift; fi
        case "$1" in down) action=down ;; up|stop|restart|rm) exit 1 ;; esac
        shift
    done
    [[ "${compose}" == "${PADM_DOCKER_INSTALL_DIR}/.restore-pending/compose.json" &&
        -f "${compose}" && "${action}" == down ]] || exit 1
    jq -e '.services.xray != null and .services.evil == null' "${compose}" >/dev/null
    [[ "${MOCK_MODE}" != down-failure ]] || exit 1
    printf 'down\n' >>"${MOCK_BACKEND}/events"
    rm -f -- "${MOCK_BACKEND}/compose-container" "${MOCK_BACKEND}/padm-container"
    exit 0
fi
printf 'unsupported:%s\n' "$*" >>"${MOCK_BACKEND}/events"
exit 1
SH
chmod 0700 "${TEST_ROOT}/bin/docker"
export PATH="${TEST_ROOT}/bin:${PATH}"
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/source"
root=${PADM_DOCKER_INSTALL_DIR}
dockerInitializeStateRoot
mkdir -p -- "${root}/secrets/tls" "${root}/data/static" "${root}/data/traffic"
printf 'fixture-cert\n' >"${root}/secrets/tls/${DOMAIN}.crt"
printf 'fixture-key\n' >"${root}/secrets/tls/${DOMAIN}.key"
printf '<!doctype html><title>Recovery fixture</title>\n' >"${root}/data/static/index.html"
dockerTlsRuntimePermissions "${root}/secrets/tls"
jq -n --arg domain "${DOMAIN}" --arg alice "${ALICE}" '
  {schema_version:3,release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"fixture"},
   core:{type:"xray",secondary_type:null,protocols:[{
     id:21,core:"xray",listener_id:"entry-site",server:"proxy.example.com",public_port:24443,
     address_families:["ipv4","ipv6"],name:"Recovery",uuid:"11111111-1111-4111-8111-111111111111",
     websocket:{domain:$domain,path:"abcdefgh",backend_port:31297,tls_port:8443}}]},
   tls:{domain:$domain},site:{mode:"static"},
   subscription:{enabled:true,token:"0123456789abcdef0123456789abcdef"},
   images:(["xray","sing-box","nginx","ops","net"] |
     map({key:.,value:("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries),
   host_integrations:[],accounts:[{
     id:$alice,name:"Alice",enabled:true,uuid:"44444444-4444-4444-8444-444444444444",
     password:"Alice.-~@+=:Secret",shadowsocks_password:null,listeners:["entry-site"]}]}
' >"${TEST_ROOT}/base.json"
chmod 0600 "${TEST_ROOT}/base.json"
jq -n --arg alice "${ALICE}" '
  {schema_version:1,groups:[{id:"share-cccccccccccccccc",name:"Recovery-Team",enabled:true,
    token:"recovery-group-token",account_ids:[$alice],listener_ids:["entry-site"]}]}
' >"${root}/config/share-groups.json"
jq -n --arg alice "${ALICE}" --arg history "${HISTORY}" '
  def old: {xray:{upload:{generation:"old-core",value:17},download:{generation:"old-core",value:19}}};
  {schema_version:1,accounts:{
    ($alice):{name:"Alice",upload:17,download:19,limit_bytes:30,baseline:old},
    ($history):{name:"Historical",upload:41,download:43,limit_bytes:1000,baseline:old}}}
' >"${root}/data/traffic/state.json"
chmod 0600 "${root}/config/share-groups.json" "${root}/data/traffic/state.json"
dockerConfigureSpecValidate "${TEST_ROOT}/base.json" || fail '源规格无效'
dockerCreateConfigurationCandidate || fail '源候选创建失败'
SOURCE=${DOCKER_CONFIG_CANDIDATE}
dockerGenerateCandidate "${TEST_ROOT}/base.json" "${SOURCE}" || fail '源候选生成失败'
printf 'docker\n' >"${SOURCE}/mode"
mkdir -p -- "${SOURCE}/data/traffic"
cp -- "${root}/data/traffic/state.json" "${SOURCE}/data/traffic/state.json"
chmod 0600 "${SOURCE}/mode" "${SOURCE}/data/traffic/state.json"
printf '{"services":{"evil":{"image":"untrusted.invalid/evil"}}}\n' >"${SOURCE}/compose.json"
chmod 0640 "${SOURCE}/compose.json"
python3 -B "${DOCKER_LIB_DIR}/recovery.py" export --root "${SOURCE}" \
    --output "${TEST_ROOT}/private recovery archive.tar" >/dev/null || fail '归档导出失败'
DOCKER_CONFIG_CANDIDATE=

snapshot() {
    python3 -B - "${root}" "${1:-all}" <<'PY'
import hashlib
import json
import os
import pathlib
import stat
import sys
root = pathlib.Path(sys.argv[1])
entries = []
for path in sorted([root] + list(root.rglob("*"))):
    relative = path.relative_to(root).as_posix()
    if relative == "locks" or relative.startswith("locks/"):
        continue
    if sys.argv[2] == "deployment" and relative.split("/", 1)[0].startswith(
            (".restore-pending", ".restore-cleaning", ".candidate.", ".recovery.")):
        continue
    info = path.lstat()
    payload = os.readlink(path) if path.is_symlink() else (
        hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None)
    entries.append((relative, stat.S_IMODE(info.st_mode), info.st_uid, info.st_gid, payload))
print(json.dumps(entries, separators=(",", ":")))
PY
}
schedule_snapshot() {
    find "${PADM_DOCKER_SYSTEMD_DIR}" -type f -print0 | sort -z | xargs -0 -r sha256sum
    cat -- "${MOCK_BACKEND}/crontab"
    for state in enabled active; do
        [[ ! -e "${MOCK_BACKEND}/${state}" ]] || printf '%s\n' "${state}"
    done
    return 0
}
prepare_target() {
    root="${TEST_ROOT}/target-$1"
    export PADM_DOCKER_INSTALL_DIR="${root}"
    export MOCK_BACKEND="${TEST_ROOT}/backend-${root##*/}" MOCK_MODE=ok MOCK_SCHEDULER=${2:-systemd}
    export PADM_DOCKER_SYSTEMD_DIR="${MOCK_BACKEND}/units" PADM_DOCKER_BIN_DIR="${MOCK_BACKEND}/bin"
    mkdir -m 0700 -- "${MOCK_BACKEND}"
    mkdir -m 0755 -- "${PADM_DOCKER_SYSTEMD_DIR}" "${PADM_DOCKER_BIN_DIR}"
    printf '# unrelated job\n17 3 * * * another-renewal # padm-docker TLS renewal root=/elsewhere\n' >"${MOCK_BACKEND}/crontab"
    : >"${MOCK_BACKEND}/events"
    dockerInitializeStateRoot
    snapshot >"${MOCK_BACKEND}/before"
    schedule_snapshot >"${MOCK_BACKEND}/schedule-before"
}
run_child() {
    local action=$1 mode=$2 expected=$3 status=0
    bash "${BASH_SOURCE[0]}" --child "${action}" "${mode}" "${root}" >"${LOG}" 2>&1 || status=$?
    if [[ "${expected}" == failure ]]; then
        [[ "${status}" != 0 ]] || fail "${action}/${mode}: 意外成功"
    else
        [[ "${status}" == "${expected}" ]] || fail "${action}/${mode}: 退出码 ${status}，预期 ${expected}"
    fi
    CASES=$((CASES + 1))
}
assert_empty() {
    snapshot >"${MOCK_BACKEND}/after"
    cmp -- "${MOCK_BACKEND}/before" "${MOCK_BACKEND}/after" ||
        fail '回滚未恢复空部署的目录、内容或权限'
    schedule_snapshot >"${MOCK_BACKEND}/schedule-after"
    cmp -- "${MOCK_BACKEND}/schedule-before" "${MOCK_BACKEND}/schedule-after" ||
        fail '回滚未恢复宿主调度与 timer 状态'
    [[ ! -e "${MOCK_BACKEND}/compose-container" && ! -e "${MOCK_BACKEND}/padm-container" &&
        -z "$(find "${root}/locks" -mindepth 1 -print -quit)" ]] ||
        fail '回滚残留容器或锁'
}
assert_deployed() {
    jq -en --slurpfile expected "${TEST_ROOT}/base.json" --slurpfile actual "${root}/config/spec.json" '
      $actual[0].core == $expected[0].core and $actual[0].accounts == $expected[0].accounts and
      $actual[0].subscription == $expected[0].subscription' >/dev/null ||
        fail '恢复改变了入口、账号凭据或订阅身份'
    cmp -- "${SOURCE}/config/share-groups.json" "${root}/config/share-groups.json" ||
        fail '恢复改变了分享组'
    jq -e --slurpfile expected "${SOURCE}/data/traffic/state.json" '
      .schema_version == $expected[0].schema_version and
      .accounts == ($expected[0].accounts | map_values(.baseline = {}))
    ' "${root}/data/traffic/state.json" >/dev/null || fail '累计、限额、历史账号或 baseline 错误'
    jq -e --arg alice "${ALICE}" '
      any(.inbounds[]?.settings.clients[]?; .padm_account == $alice and
        .id == "44444444-4444-4444-8444-444444444444")
    ' "${root}/config/xray/users.base" >/dev/null || fail '超额账号的基础凭据丢失'
    jq -e 'all(.inbounds[]?.settings.clients[]?;
      .id != "44444444-4444-4444-8444-444444444444")' \
        "${root}/config/xray/config.json" >/dev/null || fail '超额账号仍在运行配置'
    cmp -- "${SOURCE}/secrets/tls/${DOMAIN}.key" "${root}/secrets/tls/${DOMAIN}.key" &&
        cmp -- "${SOURCE}/data/static/index.html" "${root}/data/static/index.html" ||
        fail 'TLS 或静态站恢复错误'
    [[ "$(stat -c %a "${root}/config/spec.json")" == 600 &&
        "$(stat -c %a "${root}/config/xray/users.base")" == 600 &&
        -e "${MOCK_BACKEND}/compose-container" && -e "${MOCK_BACKEND}/padm-container" ]] ||
        fail '私密权限或已启动服务错误'
    if [[ "${MOCK_SCHEDULER}" == systemd ]]; then
        [[ -f "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-traffic.service" &&
            -f "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-traffic.timer" &&
            -e "${MOCK_BACKEND}/enabled" && -e "${MOCK_BACKEND}/active" ]] ||
            fail '恢复没有安装并启动流量 timer'
    else
        grep -q '# padm-docker-traffic' "${MOCK_BACKEND}/crontab" ||
            fail '恢复没有安装流量 cron'
    fi
}

for action in unconfirmed bad-confirm; do
    prepare_target "${action}"
    run_child "${action}" ok "${PADM_DOCKER_RC_USAGE}"
    assert_empty
done

for backend in systemd cron; do
    prepare_target "success-${backend}" "${backend}"
    run_child apply ok 0
    assert_deployed
    [[ ! -e "${root}/.restore-pending" && ! -e "${root}/locks/deployment.lock" ]] ||
        fail '成功事务没有清理登记或锁'
done

for mode in first-write partial-move health int term; do
    prepare_target "${mode}"
    expected=failure
    [[ "${mode}" != int ]] || expected=130
    [[ "${mode}" != term ]] || expected=143
    run_child apply "${mode}" "${expected}"
    assert_empty
    if [[ "${mode}" == first-write || "${mode}" == partial-move ]]; then
        [[ -e "${MOCK_BACKEND}/fault" ]] || fail "${mode}: 故障未注入"
    fi
done

for backend in systemd cron; do
    prepare_target "scheduler-${backend}" "${backend}"
    run_child apply scheduler failure
    [[ -e "${MOCK_BACKEND}/fault" ]] || fail "${backend}: 调度故障未注入"
    assert_empty
    prepare_target "scheduler-killed-${backend}" "${backend}"
    run_child apply scheduler-killed 137
    [[ -e "${MOCK_BACKEND}/fault" && -d "${root}/.restore-pending/traffic-schedule" ]] ||
        fail "${backend}: SIGKILL 没有持久保留原调度"
    if [[ "${backend}" == systemd ]]; then
        current_schedule="${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-traffic.service"
    else
        current_schedule="${MOCK_BACKEND}/crontab"
    fi
    cp -- "${current_schedule}" "${MOCK_BACKEND}/schedule-expected"
    printf '\n# external schedule change\n' >>"${current_schedule}"
    snapshot >"${MOCK_BACKEND}/pending-before"
    schedule_snapshot >"${MOCK_BACKEND}/schedule-pending-before"
    run_child recover ok failure
    snapshot >"${MOCK_BACKEND}/pending-after"
    schedule_snapshot >"${MOCK_BACKEND}/schedule-pending-after"
    cmp -- "${MOCK_BACKEND}/pending-before" "${MOCK_BACKEND}/pending-after" &&
        cmp -- "${MOCK_BACKEND}/schedule-pending-before" "${MOCK_BACKEND}/schedule-pending-after" ||
        fail "${backend}: 拒绝外部调度改写时改变了文件或登记"
    cp -- "${MOCK_BACKEND}/schedule-expected" "${current_schedule}"
    if [[ "${backend}" == systemd ]]; then
        dropin="${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-traffic.service.d"
        mkdir -- "${dropin}"
        printf '[Service]\nEnvironment=EXTERNAL=1\n' >"${dropin}/override.conf"
        snapshot >"${MOCK_BACKEND}/pending-before"
        schedule_snapshot >"${MOCK_BACKEND}/schedule-pending-before"
        run_child recover ok failure
        snapshot >"${MOCK_BACKEND}/pending-after"
        schedule_snapshot >"${MOCK_BACKEND}/schedule-pending-after"
        cmp -- "${MOCK_BACKEND}/pending-before" "${MOCK_BACKEND}/pending-after" &&
            cmp -- "${MOCK_BACKEND}/schedule-pending-before" "${MOCK_BACKEND}/schedule-pending-after" ||
            fail '拒绝新增 drop-in 时改变了文件或登记'
        rm -f -- "${dropin}/override.conf"
        rmdir -- "${dropin}"
    fi
    run_child recover ok 0
    assert_empty
done

prepare_target killed
run_child apply killed 137
[[ -d "${root}/.restore-pending" && -e "${MOCK_BACKEND}/compose-container" ]] ||
    fail 'SIGKILL 没有留下恢复登记与运行现场'
run_child lock ok failure
snapshot >"${MOCK_BACKEND}/pending-before"
run_child recover offline failure
snapshot >"${MOCK_BACKEND}/pending-after"
cmp -- "${MOCK_BACKEND}/pending-before" "${MOCK_BACKEND}/pending-after" ||
    fail 'Docker 不可用时改变了恢复现场'
run_child recover down-failure failure
snapshot >"${MOCK_BACKEND}/pending-after"
cmp -- "${MOCK_BACKEND}/pending-before" "${MOCK_BACKEND}/pending-after" ||
    fail 'Compose 停机失败时改变了恢复现场'
[[ -e "${MOCK_BACKEND}/compose-container" && -e "${MOCK_BACKEND}/padm-container" ]] ||
    fail 'Compose 停机失败后丢失运行现场'
# 活着的其它 owner 持锁时，专属恢复入口仍须互斥。
rm -f -- "${root}/locks/deployment.lock/pid"
[[ ! -d "${root}/locks/deployment.lock" ]] || rmdir -- "${root}/locks/deployment.lock"
mkdir -- "${root}/locks/deployment.lock"
printf '%s\n' "${BASHPID}" >"${root}/locks/deployment.lock/pid"
run_child recover ok "${PADM_DOCKER_RC_LOCK}"
rm -f -- "${root}/locks/deployment.lock/pid"
rmdir -- "${root}/locks/deployment.lock"
run_child recover ok 0
assert_empty

prepare_target tampered
run_child apply killed 137
printf '{}\n' >"${root}/.restore-pending/metadata.json"
snapshot >"${MOCK_BACKEND}/pending-before"
run_child recover ok failure
snapshot >"${MOCK_BACKEND}/pending-after"
cmp -- "${MOCK_BACKEND}/pending-before" "${MOCK_BACKEND}/pending-after" ||
    fail '登记篡改后改变了现场'
[[ -e "${MOCK_BACKEND}/compose-container" ]] || fail '登记篡改后停止了服务'

prepare_target committed
run_child apply committed 137
assert_deployed
snapshot deployment >"${MOCK_BACKEND}/committed-before"
run_child recover ok 0
snapshot deployment >"${MOCK_BACKEND}/committed-after"
cmp -- "${MOCK_BACKEND}/committed-before" "${MOCK_BACKEND}/committed-after" ||
    fail 'committed 恢复修改了成功部署'
[[ ! -e "${root}/.restore-pending" ]] || fail 'committed 恢复没有清理登记'
[[ "$(grep -c '^down$' "${MOCK_BACKEND}/events" || true)" == 0 ]] ||
    fail 'committed 恢复停止了成功部署'

prepare_target cleaning
run_child apply committed 137
assert_deployed
command mv -- "${root}/.restore-pending" "${root}/.restore-cleaning"
# 模拟逐文件清理中断后已没有完整 metadata 的现场。
rm -f -- "${root}/.restore-cleaning/metadata.json"
snapshot deployment >"${MOCK_BACKEND}/committed-before"
run_child lock ok failure
run_child recover ok 0
snapshot deployment >"${MOCK_BACKEND}/committed-after"
cmp -- "${MOCK_BACKEND}/committed-before" "${MOCK_BACKEND}/committed-after" ||
    fail 'cleaning 恢复修改了成功部署'
[[ ! -e "${root}/.restore-cleaning" && ! -e "${root}/locks/deployment.lock" ]] ||
    fail 'cleaning 恢复没有清理登记或锁'
[[ "$(grep -c '^down$' "${MOCK_BACKEND}/events" || true)" == 0 ]] ||
    fail 'cleaning 恢复停止了成功部署'
printf 'docker-recovery-apply-ok: %s cases\n' "${CASES}"
