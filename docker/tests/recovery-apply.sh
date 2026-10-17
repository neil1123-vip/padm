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
dockerRealityProbeRun() {
    local directory probe
    [[ "$#" == 13 && "$1 $2 $3 $4 $5 $6" == \
        '60 --network none --env XRAY_LOCATION_ASSET=/etc/padm/xray/geo --volume' &&
        "$7" == */config/xray/geo:/etc/padm/xray/geo:ro && "$8" == --volume &&
        "$9" == */geo-probe.json:/probe.json:ro &&
        "${10}" == "$(jq -r '.images.xray' "${TEST_ROOT}/base.json")" &&
        "${11} ${12} ${13}" == '-test -config /probe.json' ]] || fail '恢复 Geo 探针参数错误'
    directory=${7%:/etc/padm/xray/geo:ro}
    probe=${9%:/probe.json:ro}
    [[ -s "${directory}/geoip.dat" && -s "${directory}/geosite.dat" ]] || fail 'Geo 双库缺失'
    jq -e '[.routing.rules[].domain[]?,.routing.rules[].ip[]?] == ["geosite:cn","geoip:cn"]' \
        "${probe}" >/dev/null || fail 'Geo 探针未强制加载双库'
    printf 'geo-probe\n' >>"${MOCK_BACKEND}/events"
    [[ "${MODE}" != geo-probe-fail ]]
}
dockerCandidateCompose() {
    local candidate=$1
    shift
    [[ -d "${candidate}" && -d "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] ||
        fail '候选校验未持有部署锁'
    jq -e '(.services.xray != null or .services["sing-box"] != null) and .services.evil == null' \
        "${candidate}/compose.json" >/dev/null || fail '候选没有重新生成 Compose'
    [[ ! -e "${candidate}/geo-probe.json" ]] || fail 'Geo 探针配置未清理'
    case "$*" in
    'config --format json') printf 'candidate-compose\n' >>"${MOCK_BACKEND}/events" ;;
    'run --rm --no-deps xray -test -confdir /etc/padm/xray')
        printf 'candidate-xray\n' >>"${MOCK_BACKEND}/events" ;;
    'run --rm --no-deps sing-box check -D /var/lib/padm/sing-box -c /etc/padm/sing-box/config.json')
        printf 'candidate-sing-box\n' >>"${MOCK_BACKEND}/events"
        [[ "${MODE}" != sing-box-fail ]] || return 1 ;;
    "--file ${candidate}/compose.nginx-check.json run --rm --no-deps nginx -t")
        jq -e '.services.nginx.extra_hosts | index("xray:127.0.0.1") != null and
          index("subscription:127.0.0.1") != null' "${candidate}/compose.nginx-check.json" >/dev/null ||
            fail 'Nginx 离线校验缺少核心或订阅临时解析'
        printf 'candidate-nginx\n' >>"${MOCK_BACKEND}/events"
        [[ "${MODE}" != nginx-fail ]] || return 1 ;;
    'run --rm --no-deps subscription subscription --check')
        printf 'candidate-subscription\n' >>"${MOCK_BACKEND}/events"
        if [[ "${MODE}" == preparing-validated ]]; then
            DOCKER_TEST_OWNER=${BASHPID}
            kill_restore_owner
        fi ;;
    *) fail "非预期候选校验: $*" ;;
    esac
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
dockerRenewalScheduleInstall() { fail '恢复不应安装或启用续期调度'; }
dockerControlLogScheduleInstall() { :; }
dockerControlSyncScheduleInstall() { :; }
dockerRestoreConfiguration() { fail '恢复应用调用了普通配置回滚'; }
systemctl() {
    local prefix= timer=${!#}
    [[ "${timer}" != padm-docker-geo.timer ]] || prefix=geo-
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
    is-enabled) [[ -e "${MOCK_BACKEND}/${prefix}enabled" ]]; return $? ;;
    is-active) [[ -e "${MOCK_BACKEND}/${prefix}active" ]]; return $? ;;
    enable)
        : >"${MOCK_BACKEND}/${prefix}enabled"
        [[ "$*" != *--now* ]] || : >"${MOCK_BACKEND}/${prefix}active"
        if [[ "${timer}" == padm-docker-geo.timer && "${MODE}" == geo-* &&
            ! -e "${MOCK_BACKEND}/fault" ]]; then
            case "${MODE}" in
            geo-scheduler) : >"${MOCK_BACKEND}/fault"; return 1 ;;
            geo-killed) kill_restore_owner ;;
            geo-int) : >"${MOCK_BACKEND}/fault"; kill -INT "${DOCKER_TEST_OWNER}"; return 1 ;;
            geo-term) : >"${MOCK_BACKEND}/fault"; kill -TERM "${DOCKER_TEST_OWNER}"; return 1 ;;
            esac
        fi
        if [[ "${MODE}" == scheduler || "${MODE}" == scheduler-killed ]]; then
            : >"${MOCK_BACKEND}/fault"
            [[ "${MODE}" != scheduler-killed ]] || {
                kill -KILL "${DOCKER_TEST_OWNER}"
                exit 137
            }
            return 1
        fi ;;
    disable)
        rm -f -- "${MOCK_BACKEND}/${prefix}enabled"
        [[ "$*" != *--now* ]] || rm -f -- "${MOCK_BACKEND}/${prefix}active" ;;
    start) : >"${MOCK_BACKEND}/${prefix}active" ;;
    *) return 1 ;;
    esac
}
pgrep() { [[ "${MOCK_SCHEDULER}" == cron && "$*" == '-x cron' ]]; }
crontab() {
    case "$1" in
    -l) cat -- "${MOCK_BACKEND}/crontab" ;;
    -)
        cat >"${MOCK_BACKEND}/crontab"
        if [[ "${MODE}" == geo-recover-killed && ! -e "${MOCK_BACKEND}/recover-fault" ]] &&
            grep -q 'traffic collect' "${MOCK_BACKEND}/crontab" &&
            ! grep -q 'geo auto-update' "${MOCK_BACKEND}/crontab"; then
            : >"${MOCK_BACKEND}/recover-fault"
            DOCKER_TEST_OWNER=$(<"${DOCKER_DEPLOYMENT_LOCK_DIR}/pid")
            kill_restore_owner
        fi
        if [[ "${MODE}" == geo-* && ! -e "${MOCK_BACKEND}/fault" ]] &&
            grep -q 'geo auto-update' "${MOCK_BACKEND}/crontab"; then
            case "${MODE}" in
            geo-scheduler) : >"${MOCK_BACKEND}/fault"; return 1 ;;
            geo-killed) kill_restore_owner ;;
            geo-int) : >"${MOCK_BACKEND}/fault"; kill -INT "${DOCKER_TEST_OWNER}"; return 1 ;;
            geo-term) : >"${MOCK_BACKEND}/fault"; kill -TERM "${DOCKER_TEST_OWNER}"; return 1 ;;
            esac
        fi
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
kill_restore_owner() {
    : >"${MOCK_BACKEND}/fault"
    kill -KILL "${DOCKER_TEST_OWNER}"
    exit 137
}
schedule_snapshot() {
    find "${PADM_DOCKER_SYSTEMD_DIR}" -type f -print0 | sort -z | xargs -0 -r sha256sum
    cat -- "${MOCK_BACKEND}/crontab"
    [[ "${1:-}" != content ]] || return 0
    for state in enabled active geo-enabled geo-active; do
        [[ ! -e "${MOCK_BACKEND}/${state}" ]] || printf '%s\n' "${state}"
    done
    return 0
}
mkdir() {
    # Geo 原始快照之前已重装 traffic，按此刻的完整调度核对快照阶段无写入。
    if [[ "${MODE}" == geo-source-* &&
        "${!#}" == "${PADM_DOCKER_INSTALL_DIR}/.restore-pending/geo-source" ]]; then
        schedule_snapshot content >"${MOCK_BACKEND}/schedule-content-before" || return 1
    fi
    command mkdir "$@" || return $?
    if [[ "${MODE}" == preparing-stage &&
        "${!#}" == "${PADM_DOCKER_INSTALL_DIR}/.recovery."* ]]; then
        DOCKER_TEST_OWNER=${BASHPID}
        kill_restore_owner
    fi
    if [[ "${MODE}" == source-mkdir &&
        "${!#}" == "${PADM_DOCKER_INSTALL_DIR}/.restore-pending/traffic-source" ]]; then
        kill_restore_owner
    fi
    if [[ "${MODE}" == geo-source-mkdir &&
        "${!#}" == "${PADM_DOCKER_INSTALL_DIR}/.restore-pending/geo-source" ]]; then
        kill_restore_owner
    fi
}
cp() {
    command cp "$@" || return $?
    if [[ "${MODE}" == preparing-candidate &&
        "${!#}" == "${PADM_DOCKER_INSTALL_DIR}/.candidate."*/request.json ]]; then
        DOCKER_TEST_OWNER=${BASHPID}
        kill_restore_owner
    fi
}
cat() {
    local line
    if [[ "${MODE}" == source-unit && ! -e "${MOCK_BACKEND}/fault" &&
        "$#" == 2 && "$1" == -- &&
        "$2" == "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-traffic.service" &&
        -d "${PADM_DOCKER_INSTALL_DIR}/.restore-pending/traffic-source" ]]; then
        IFS= read -r line <"$2" || return 1
        builtin printf '%s\n' "${line}"
        kill_restore_owner
    fi
    if [[ "${MODE}" == geo-source-unit && ! -e "${MOCK_BACKEND}/fault" &&
        "$#" == 2 && "$1" == -- &&
        "$2" == "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-geo.service" &&
        -d "${PADM_DOCKER_INSTALL_DIR}/.restore-pending/geo-source" ]]; then
        IFS= read -r line <"$2" || return 1
        builtin printf '%s\n' "${line}"
        kill_restore_owner
    fi
    if [[ "${MODE}" == source-template && ! -e "${MOCK_BACKEND}/fault" && "$#" == 0 &&
        -d "${PADM_DOCKER_INSTALL_DIR}/.restore-pending/traffic-schedule" ]]; then
        IFS= read -r line || return 1
        builtin printf '%s\n' "${line}"
        kill_restore_owner
    fi
    if [[ "${MODE}" == geo-source-template && ! -e "${MOCK_BACKEND}/fault" && "$#" == 0 &&
        -d "${PADM_DOCKER_INSTALL_DIR}/.restore-pending/geo-schedule" ]]; then
        IFS= read -r line || return 1
        builtin printf '%s\n' "${line}"
        kill_restore_owner
    fi
    command cat "$@"
}
printf() {
    if [[ "${MODE}" == source-cron && ! -e "${MOCK_BACKEND}/fault" &&
        -f "${PADM_DOCKER_INSTALL_DIR}/.restore-pending/traffic-source/crontab" ]]; then
        builtin printf '%s' '# partial cron snapshot'
        kill_restore_owner
    fi
    if [[ "${MODE}" == geo-source-cron && ! -e "${MOCK_BACKEND}/fault" &&
        -f "${PADM_DOCKER_INSTALL_DIR}/.restore-pending/geo-source/crontab" ]]; then
        builtin printf '%s' '# partial Geo cron snapshot'
        kill_restore_owner
    fi
    builtin printf "$@"
}
mv() {
    local last=${!#} argument
    if [[ "${MODE}" == first-write && "${last}" == "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json" ]]; then
        : >"${MOCK_BACKEND}/fault"
        return 1
    fi
    if [[ "${MODE}" == partial-move && "${last}" == "${PADM_DOCKER_INSTALL_DIR}/config/" ]]; then
        for argument in "$@"; do
            if [[ "${argument}" == "${PADM_DOCKER_INSTALL_DIR}/.candidate."*/config/xray ||
                "${argument}" == "${PADM_DOCKER_INSTALL_DIR}/.candidate."*/config/sing-box ]]; then
                command mv -- "${argument}" "${last}" || return 1
                : >"${MOCK_BACKEND}/fault"
                return 1
            fi
        done
    fi
    command mv "$@"
}
python3() {
    if [[ "${MODE}" == unit-* && "$*" == *'recovery.py transaction-unit-publish '* ]]; then
        local owner
        owner=$(<"${DOCKER_DEPLOYMENT_LOCK_DIR}/pid")
        [[ "${owner}" =~ ^[1-9][0-9]*$ ]] || fail 'unit 硬杀缺少恢复进程 PID'
        command python3 -B - "${MODE}" "${owner}" "$@" <<'PY'
import importlib.util
import os
import signal
import sys
from pathlib import Path

_, operation, job, kind, moment = sys.argv[1].split("-")
owner = int(sys.argv[2])
arguments = sys.argv[3:]
spec = importlib.util.spec_from_file_location("recovery", arguments[1])
recovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recovery)
replace = recovery.os.replace
matched = (("--restore" in arguments) == (operation == "restore")
           and arguments[arguments.index("--job") + 1] == job
           and arguments[arguments.index("--kind") + 1] == kind)

def kill():
    Path(os.environ["MOCK_BACKEND"], "unit-fault").touch()
    os.kill(owner, signal.SIGKILL)
    os.kill(os.getpid(), signal.SIGKILL)

def interrupted_replace(source, target, **kwargs):
    if matched and target == "padm-docker-" + job + "." + kind and moment == "before":
        kill()
    replace(source, target, **kwargs)
    if matched and target == "padm-docker-" + job + "." + kind and moment == "after":
        kill()

recovery.os.replace = interrupted_replace
sys.argv = arguments[1:]
status = recovery.main()
if matched:
    raise AssertionError("unit 原子替换硬杀未命中")
sys.exit(status)
PY
        return $?
    fi
    if [[ ( "${MODE}" == preparing-begin && "$*" == *'recovery.py transaction-begin '* ) ||
        ( "${MODE}" == preparing-extract && "$*" == *'recovery.py extract '* ) ]]; then
        # begin 位于命令替换内，部署锁记录的才是外层恢复进程。
        local owner
        owner=$(<"${DOCKER_DEPLOYMENT_LOCK_DIR}/pid")
        [[ "${owner}" =~ ^[1-9][0-9]*$ ]] || fail '准备期硬杀缺少恢复进程 PID'
        command python3 -B - "${MODE}" "${owner}" "$@" <<'PY'
import importlib.util
import os
import signal
import sys
from pathlib import Path

mode, owner = sys.argv[1:3]
arguments = sys.argv[3:]
spec = importlib.util.spec_from_file_location("recovery", arguments[1])
recovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recovery)
write = recovery.transaction_write
payload = recovery.read_payload

def kill():
    Path(os.environ["MOCK_BACKEND"], "fault").touch()
    os.kill(int(owner), signal.SIGKILL)
    os.kill(os.getpid(), signal.SIGKILL)

def interrupted_write(parent, name, data):
    write(parent, name, data[:len(data) // 2])
    kill()

def interrupted_payload(source, size, digest=None, target=None):
    if target is not None and size:
        target.write(source.read(max(1, size // 2)))
        target.flush()
        kill()
    return payload(source, size, digest, target)

if mode == "preparing-begin":
    recovery.transaction_write = interrupted_write
else:
    recovery.read_payload = interrupted_payload
sys.argv = arguments[1:]
recovery.main()
raise AssertionError("准备期硬杀未命中")
PY
        return $?
    fi
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
    archive=${5:-${TEST_ROOT}/private recovery archive.tar}
    export PADM_DOCKER_INSTALL_DIR=$4
    export MOCK_BACKEND="${TEST_ROOT}/backend-${4##*/}" MOCK_MODE="${MODE}"
    export PADM_DOCKER_SYSTEMD_DIR="${MOCK_BACKEND}/units" PADM_DOCKER_BIN_DIR="${MOCK_BACKEND}/bin"
    export PATH="${TEST_ROOT}/bin:${PATH}"
    case "${action}" in
    apply)
        dockerMain restore apply "${archive}" \
            --confirm PADM-DOCKER-RESTORE ;;
    preview) dockerMain restore preview "${archive}" ;;
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
    jq -e '(.services.xray != null or .services["sing-box"] != null) and .services.evil == null' \
        "${compose}" >/dev/null
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
     websocket:{domain:$domain,path:"abcdefgh",backend_port:31297,tls_port:8443}},
    {id:1,core:"xray",listener_id:"entry-reality",server:"proxy.example.com",public_port:24444,
     address_families:["ipv4","ipv6"],name:"Reality",uuid:"11111111-1111-4111-8111-111111111111",
     reality:{server_name:"reality.example.com",target_host:"reality.example.com",target_port:443,
       public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",
       private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",short_id:"6ba85179e30d4fc2"}},
    {id:26,core:"xray",listener_id:"entry-other",server:"proxy.example.com",public_port:24445,
     address_families:["ipv4","ipv6"],name:"Other-gRPC",uuid:"11111111-1111-4111-8111-111111111111",
     grpc:{service_name:"other"},reality:{server_name:"reality.example.com",target_host:"reality.example.com",
       target_port:443,public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",
       private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",short_id:"6ba85179e30d4fc2"}}]},
   reality_stream:{listener_id:"entry-reality",website_listener_id:"entry-site"},
   tls:{domain:$domain},site:{mode:"static"},
   subscription:{enabled:true,token:"0123456789abcdef0123456789abcdef"},
   images:(["xray","sing-box","nginx","ops","net"] |
     map({key:.,value:("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries),
   host_integrations:[],accounts:[{
     id:$alice,name:"Alice",enabled:true,uuid:"44444444-4444-4444-8444-444444444444",
     password:"Alice.-~@+=:Secret",shadowsocks_password:null,
     listeners:["entry-site","entry-reality","entry-other"]}]}
' >"${TEST_ROOT}/base.json"
chmod 0600 "${TEST_ROOT}/base.json"
jq -n --arg alice "${ALICE}" '
  {schema_version:1,groups:[{id:"share-cccccccccccccccc",name:"Recovery-Team",enabled:true,
    token:"recovery-group-token",account_ids:[$alice],listener_ids:["entry-other","entry-reality","entry-site"]}]}
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
mkdir -m 0700 -- "${SOURCE}/data/reality-targets"
printf 'Example.COM:00443\tExample.COM\t\tcustom\tno\tunknown\tunknown\t\tunknown\tA\tunknown\tunknown\tunknown\t0\t\t\n' \
    >"${SOURCE}/data/reality-targets/results.tsv"
printf 'blocked.example||custom-reason|custom description\n' >"${SOURCE}/data/reality-targets/blocked.tsv"
chmod 0600 "${SOURCE}/data/reality-targets/"*.tsv
mkdir -m 0750 -- "${SOURCE}/config/xray/geo"
printf 'fixture-ip\000\377\n' >"${SOURCE}/config/xray/geo/geoip.dat"
printf 'fixture-site\000\376\n' >"${SOURCE}/config/xray/geo/geosite.dat"
jq -n --arg ip "$(sha256sum "${SOURCE}/config/xray/geo/geoip.dat" | cut -d ' ' -f 1)" \
    --arg site "$(sha256sum "${SOURCE}/config/xray/geo/geosite.dat" | cut -d ' ' -f 1)" \
    '{schema_version:1,version:"202610170001",enabled:false,
      sha256:{"geoip.dat":$ip,"geosite.dat":$site}}' >"${SOURCE}/config/xray/geo/state.json"
chmod 0640 "${SOURCE}/config/xray/geo/"*
mkdir -m 0700 -- "${SOURCE}/secrets/renewal"
for provider in dns_cf standalone webroot alpn; do
    domain="${provider//_/-}.example.com"
    version=1
    [[ "${provider}" != standalone ]] || version=2
    [[ "${provider}" != webroot ]] || version=3
    [[ "${provider}" != alpn ]] || version=4
    mkdir -m 0700 -- "${SOURCE}/secrets/renewal/${domain}"
    jq -n --arg domain "${domain}" --arg provider "${provider}" --argjson version "${version}" \
        '{schema_version:$version,domain:$domain,email:"admin@example.com",provider:$provider,enabled:false}' \
        >"${SOURCE}/secrets/renewal/${domain}/request.json"
    chmod 0600 "${SOURCE}/secrets/renewal/${domain}/request.json"
done
printf '# DNS provider\r\nDNS_Token=private-value\r\n' \
    >"${SOURCE}/secrets/renewal/dns-cf.example.com/credentials.env"
chmod 0600 "${SOURCE}/secrets/renewal/dns-cf.example.com/credentials.env"
printf 'untrusted archived stream;\n' >"${SOURCE}/config/nginx/stream/reality.conf"
printf '{"services":{"evil":{"image":"untrusted.invalid/evil"}}}\n' >"${SOURCE}/compose.json"
chmod 0640 "${SOURCE}/compose.json"
python3 -B "${DOCKER_LIB_DIR}/recovery.py" export --root "${SOURCE}" \
    --output "${TEST_ROOT}/private recovery archive.tar" >/dev/null || fail '归档导出失败'
DOCKER_CONFIG_CANDIDATE=

GEO_ENABLED_SOURCE="${TEST_ROOT}/source-geo-enabled"
cp -a -- "${SOURCE}" "${GEO_ENABLED_SOURCE}"
jq '.enabled = true' "${SOURCE}/config/xray/geo/state.json" \
    >"${GEO_ENABLED_SOURCE}/config/xray/geo/state.json"
python3 -B "${DOCKER_LIB_DIR}/recovery.py" export --root "${GEO_ENABLED_SOURCE}" \
    --output "${TEST_ROOT}/geo-enabled.tar" >/dev/null || fail '启用 Geo 归档导出失败'
NO_GEO_SOURCE="${TEST_ROOT}/source-no-geo"
cp -a -- "${SOURCE}" "${NO_GEO_SOURCE}"
rm -rf -- "${NO_GEO_SOURCE}/config/xray/geo"
python3 -B "${DOCKER_LIB_DIR}/recovery.py" export --root "${NO_GEO_SOURCE}" \
    --output "${TEST_ROOT}/no-geo.tar" >/dev/null || fail '无 Geo 归档导出失败'

HOST_SOURCE="${TEST_ROOT}/source-host"
cp -a -- "${SOURCE}" "${HOST_SOURCE}"
jq '.reality_stream = {listener_id:"entry-reality",host_website:{
  domains:["host.example.com"],address:"host.docker.internal",port:8443}}' \
    "${SOURCE}/config/spec.json" >"${HOST_SOURCE}/config/spec.json"
dockerConfigureSpecValidate "${HOST_SOURCE}/config/spec.json" || fail '桥接宿主网站夹具无效'
dockerGenerateDeployment "${HOST_SOURCE}/config/spec.json" "${HOST_SOURCE}/deployment.json"
python3 -B "${DOCKER_LIB_DIR}/recovery.py" export --root "${HOST_SOURCE}" \
    --output "${TEST_ROOT}/host.tar" >/dev/null || fail '宿主共存归档导出失败'

HTTP01_SOURCE="${TEST_ROOT}/source-http01"
cp -a -- "${SOURCE}" "${HTTP01_SOURCE}"
jq '.tls.http01 = true' "${SOURCE}/config/spec.json" >"${HTTP01_SOURCE}/config/spec.json"
dockerConfigureSpecValidate "${HTTP01_SOURCE}/config/spec.json" || fail 'HTTP-01 夹具无效'
dockerGenerateDeployment "${HTTP01_SOURCE}/config/spec.json" "${HTTP01_SOURCE}/deployment.json"
printf 'untrusted archived HTTP-01 config;\n' >"${HTTP01_SOURCE}/config/nginx/default.conf"
python3 -B "${DOCKER_LIB_DIR}/recovery.py" export --root "${HTTP01_SOURCE}" \
    --output "${TEST_ROOT}/http01.tar" >/dev/null || fail 'HTTP-01 归档导出失败'

for protocol in hy2 tuic; do
    variant="${TEST_ROOT}/source-hopping-${protocol}"
    cp -a -- "${SOURCE}" "${variant}"
    jq '
      .core.type = "sing-box" | .core.secondary_type = null |
      .core.protocols = [(.core.protocols[0] | del(.websocket) |
        .id = 3 | .core = "sing-box" | .public_port = 35442 |
        .hy2 = {domain:"ws.example.com",bandwidth_mode:"bbr",up_mbps:100,down_mbps:100,
          obfs:null,masquerade:""})] |
      .accounts[].listeners = ["entry-site"] |
      .subscription.enabled = false | del(.site,.reality_stream) |
      .port_hopping = {listener_id:"entry-site",range_start:36000,range_end:36002,
        ipv4:"198.18.1.1",ipv6:"2001:db8:1::1"}
    ' "${SOURCE}/config/spec.json" >"${variant}/config/spec.json"
    if [[ "${protocol}" == tuic ]]; then
        jq '.core.protocols[0] |= (del(.hy2) | .id = 31 |
          .tuic = {domain:"ws.example.com",congestion_control:"cubic",
            auth_timeout:"3s",heartbeat:"10s",zero_rtt_handshake:false})' \
            "${variant}/config/spec.json" >"${TEST_ROOT}/hopping.json"
        cat -- "${TEST_ROOT}/hopping.json" >"${variant}/config/spec.json"
    fi
    jq -c '.groups[].listener_ids = ["entry-site"]' "${SOURCE}/config/share-groups.json" \
        >"${variant}/config/share-groups.json"
    rm -rf -- "${variant}/config/xray" "${variant}/config/nginx" \
        "${variant}/data/static" "${variant}/data/subscription"
    dockerConfigureSpecValidate "${variant}/config/spec.json" || fail "${protocol} 跳跃夹具无效"
    dockerGenerateDeployment "${variant}/config/spec.json" "${variant}/deployment.json"
    python3 -B "${DOCKER_LIB_DIR}/recovery.py" export --root "${variant}" \
        --output "${TEST_ROOT}/hopping-${protocol}.tar" >/dev/null || fail "${protocol} 跳跃归档失败"
done

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
prepare_target() {
    root="${TEST_ROOT}/target-$1"
    RECOVERY_ARCHIVE="${TEST_ROOT}/private recovery archive.tar"
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
    bash "${BASH_SOURCE[0]}" --child "${action}" "${mode}" "${root}" "${RECOVERY_ARCHIVE}" \
        >"${LOG}" 2>&1 || status=$?
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
assert_units_complete() {
    local job kind file mode
    for job in traffic geo; do
        for kind in service timer; do
            file="${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-${job}.${kind}"
            [[ -f "${file}" && ! -L "${file}" &&
                "$(stat -c '%u:%g:%h' "${file}")" == 0:0:1 ]] ||
                fail 'unit 原子替换产生了不安全的文件'
            mode=$(stat -c %a -- "${file}") || return 1
            [[ "${mode}" == 600 || "${mode}" == 644 ]] ||
                fail 'unit 原子替换产生了错误权限'
            cmp -s -- "${file}" "${MOCK_BACKEND}/${job}.${kind}.old" ||
                cmp -s -- "${file}" "${MOCK_BACKEND}/${job}.${kind}.new" ||
                fail 'unit 硬杀留下空文件或半写内容'
        done
    done
    [[ "$(find "${PADM_DOCKER_SYSTEMD_DIR}" -mindepth 1 | wc -l)" == 4 &&
        -z "$(find "${root}/.restore-pending" -type f ! -perm 0600 -print -quit)" &&
        -z "$(find "${root}/.restore-pending" -type d ! -perm 0700 -print -quit)" &&
        -z "$(find "${root}/.restore-pending" \( ! -user root -o ! -group root -o -type l -o -type f -links +1 \) -print -quit)" ]] ||
        fail 'unit 硬杀留下未登记文件或非私密暂存'
}
assert_deployed() {
    local source=${1:-${SOURCE}} file relative
    [[ "$(find "${root}/secrets/renewal" -type f | wc -l)" == 5 &&
        -z "$(find "${root}/secrets/renewal" -type d ! -perm 0700 -print -quit)" &&
        -z "$(find "${root}/secrets/renewal" -type f ! -perm 0600 -print -quit)" &&
        -z "$(find "${root}/secrets/renewal" \( ! -user root -o ! -group root \) -print -quit)" ]] ||
        fail '停用续期登记的数量、所有者或权限错误'
    while IFS= read -r file; do
        relative=${file#"${source}/secrets/renewal/"}
        cmp -- "${file}" "${root}/secrets/renewal/${relative}" || fail '续期登记没有保持原字节'
    done < <(find "${source}/secrets/renewal" -type f)
    cmp -- "${root}/config/nginx/stream/reality.conf" \
        <(dockerGenerateRealityStreamConfig "${source}/config/spec.json" /dev/stdout) ||
        fail '恢复照搬了归档 stream，没有按规格重新生成'
    jq -e --slurpfile spec "${source}/config/spec.json" '
      .services.xray.ports == ["0.0.0.0:24445:24445/tcp","[::]:24445:24445/tcp"] and
      .services.nginx.ports ==
        (if $spec[0].reality_stream.host_website != null then
          ["0.0.0.0:24443:8443/tcp","[::]:24443:8443/tcp"] else [] end +
          ["0.0.0.0:443:15443/tcp","[::]:443:15443/tcp"] +
          if $spec[0].tls.http01 == true then
            ["0.0.0.0:80:8088/tcp","[::]:80:8088/tcp"] else [] end) and
      (if $spec[0].reality_stream.host_website != null then
        .services.nginx.extra_hosts == ["host.docker.internal:host-gateway"]
       else true end) and
      any(.services.nginx.volumes[]; .target == "/etc/nginx/stream.d" and .read_only == true)
    ' "${root}/compose.json" >/dev/null || fail '恢复共存 Compose 映射错误'
    jq -e --slurpfile spec "${source}/config/spec.json" '
      [.listeners[] | select(.listener_id == "entry-site" or .listener_id == "entry-reality")] |
      length == 2 and all(.[]; .service == "nginx" and
        if $spec[0].reality_stream.host_website != null and .listener_id == "entry-site" then
          .public_port == 24443 and .container_port == 8443
        else .public_port == 443 and .container_port == 15443 end)
    ' "${root}/deployment.json" >/dev/null || fail '恢复共存部署有效公网端口错误'
    grep -q '@proxy.example.com:443?' "${root}/data/subscription/0123456789abcdef0123456789abcdef" &&
        grep -q '@proxy.example.com:24445?' "${root}/data/subscription/0123456789abcdef0123456789abcdef" ||
        fail '恢复共存订阅有效公网端口或未绑定入口错误'
    if jq -e '.reality_stream.host_website != null' "${source}/config/spec.json" >/dev/null; then
        grep -q '@proxy.example.com:24443?' "${root}/data/subscription/0123456789abcdef0123456789abcdef" ||
            fail '宿主共存改变了独立受管网站入口的订阅端口'
    fi
    [[ "$(grep -E '^candidate-|^geo-probe$|^up$' "${MOCK_BACKEND}/events")" == \
        $'candidate-compose\ngeo-probe\ncandidate-xray\ncandidate-nginx\ncandidate-subscription\nup' ]] ||
        fail '恢复未按 Compose、Geo、Xray、Nginx、订阅校验后再启动'
    [[ ! -e "${root}/compose.nginx-check.json" ]] || fail '恢复残留 Nginx 临时校验配置'
    for file in state.json geoip.dat geosite.dat; do
        cmp -- "${source}/config/xray/geo/${file}" "${root}/config/xray/geo/${file}" ||
            fail '恢复 Geo 未保持原字节'
        [[ "$(stat -c '%u:%g:%a' "${root}/config/xray/geo/${file}")" == \
            "0:${PADM_DOCKER_CONTAINER_GID}:640" ]] || fail 'Geo 文件运行权限错误'
    done
    [[ "$(stat -c '%u:%g:%a' "${root}/config/xray/geo")" == "0:${PADM_DOCKER_CONTAINER_GID}:750" ]] ||
        fail 'Geo 目录运行权限错误'
    jq -e '.services.xray.environment.XRAY_LOCATION_ASSET == "/etc/padm/xray/geo"' \
        "${root}/compose.json" >/dev/null || fail 'Geo Compose 读取路径错误'
    [[ "$(grep -c '^geo-probe$' "${MOCK_BACKEND}/events")" == 1 ]] || fail '恢复未执行唯一 Geo 探针'
    for file in results.tsv blocked.tsv; do
        cmp -- "${source}/data/reality-targets/${file}" "${root}/data/reality-targets/${file}" ||
            fail '目标库未按原字节恢复'
        [[ "$(stat -c '%u:%g:%a' "${root}/data/reality-targets/${file}")" == 0:0:600 ]] ||
            fail '目标库文件权限不私密'
    done
    [[ "$(stat -c '%u:%g:%a' "${root}/data/reality-targets")" == 0:0:700 ]] ||
        fail '目标库目录权限不私密'
    jq -en --slurpfile expected "${source}/config/spec.json" --slurpfile actual "${root}/config/spec.json" '
      $actual[0].core == $expected[0].core and $actual[0].accounts == $expected[0].accounts and
      $actual[0].subscription == $expected[0].subscription and
      $actual[0].tls == $expected[0].tls and
      $actual[0].reality_stream == $expected[0].reality_stream' >/dev/null ||
        fail '恢复改变了入口、账号凭据或订阅身份'
    cmp -- "${source}/config/share-groups.json" "${root}/config/share-groups.json" ||
        fail '恢复改变了分享组'
    jq -e --slurpfile expected "${source}/data/traffic/state.json" '
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
    cmp -- "${source}/secrets/tls/${DOMAIN}.crt" "${root}/secrets/tls/${DOMAIN}.crt" &&
        cmp -- "${source}/secrets/tls/${DOMAIN}.key" "${root}/secrets/tls/${DOMAIN}.key" &&
        cmp -- "${source}/data/static/index.html" "${root}/data/static/index.html" ||
        fail 'TLS 或静态站恢复错误'
    if jq -e '.tls.http01 == true' "${source}/config/spec.json" >/dev/null; then
        [[ -d "${root}/data/acme-webroot" &&
            -z "$(find "${root}/data/acme-webroot" -mindepth 1 -print -quit)" &&
            "$(stat -c '%u:%g:%a' "${root}/data/acme-webroot")" == \
                "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}:750" ]] ||
            fail 'HTTP-01 挑战根没有以运行权限重建为空目录'
        cmp -- "${root}/config/nginx/default.conf" \
            <(dockerGenerateNginxConfig "${source}/config/spec.json" /dev/stdout) ||
            fail 'HTTP-01 Nginx 没有按规格重新生成'
        jq -e 'any(.services.nginx.volumes[];
          .source == "${PADM_DOCKER_ROOT}/data/acme-webroot" and
          .target == "/srv/padm-acme" and .read_only == true)' \
            "${root}/compose.json" >/dev/null || fail 'HTTP-01 挑战根挂载错误'
    else
        [[ ! -e "${root}/data/acme-webroot" ]] || fail '未启用 HTTP-01 却生成了挑战根'
    fi
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
assert_hopping_deployed() {
    local protocol=$1 source="${TEST_ROOT}/source-hopping-${1}" file status
    jq -en --slurpfile expected "${source}/config/spec.json" \
        --slurpfile actual "${root}/config/spec.json" \
        --slurpfile deployment "${root}/deployment.json" \
        --slurpfile compose "${root}/compose.json" '
      $expected[0].port_hopping as $saved |
      $actual[0].core == $expected[0].core and $actual[0].accounts == $expected[0].accounts and
      $actual[0].subscription == $expected[0].subscription and
      $actual[0].port_hopping == $saved and $deployment[0].port_hopping == $saved and
      $compose[0]["x-padm-port-hopping"] == $saved and
      ($compose[0].services | keys) == ["acme","sing-box"]
    ' >/dev/null || fail "${protocol}: 跳跃 tuple、身份或服务集合错误"
    cmp -- "${source}/config/share-groups.json" "${root}/config/share-groups.json" ||
        fail "${protocol}: 恢复改变了分享组"
    jq -e --slurpfile expected "${source}/data/traffic/state.json" '
      .schema_version == $expected[0].schema_version and
      .accounts == ($expected[0].accounts | map_values(.baseline = {}))
    ' "${root}/data/traffic/state.json" >/dev/null || fail "${protocol}: 累计或 baseline 错误"
    jq -e --arg alice "${ALICE}" '
      any(.inbounds[]?.users[]?; .padm_account == $alice and .password == "Alice.-~@+=:Secret")
    ' "${root}/config/sing-box/users.base" >/dev/null || fail "${protocol}: 基础凭据丢失"
    jq -e 'all(.inbounds[]?.users[]?; .password != "Alice.-~@+=:Secret")' \
        "${root}/config/sing-box/config.json" >/dev/null || fail "${protocol}: 超额账号仍在运行配置"
    for file in results.tsv blocked.tsv; do
        cmp -- "${source}/data/reality-targets/${file}" "${root}/data/reality-targets/${file}" ||
            fail "${protocol}: 目标库未按原字节恢复"
    done
    cmp -- "${source}/secrets/tls/${DOMAIN}.crt" "${root}/secrets/tls/${DOMAIN}.crt" &&
        cmp -- "${source}/secrets/tls/${DOMAIN}.key" "${root}/secrets/tls/${DOMAIN}.key" ||
        fail "${protocol}: TLS 恢复错误"
    [[ "$(stat -c %a "${root}/config/spec.json")" == 600 &&
        "$(stat -c %a "${root}/config/share-groups.json")" == 600 &&
        "$(stat -c %a "${root}/config/sing-box/users.base")" == 600 &&
        "$(stat -c %a "${root}/data/traffic/state.json")" == 600 &&
        -e "${MOCK_BACKEND}/compose-container" && -e "${MOCK_BACKEND}/padm-container" ]] ||
        fail "${protocol}: 私密权限或已启动服务错误"
    [[ "$(grep -E '^candidate-|^geo-probe$|^up$' "${MOCK_BACKEND}/events")" == \
        $'candidate-compose\ncandidate-sing-box\nup' ]] ||
        fail "${protocol}: 未按 Compose、sing-box 校验后再启动"
    [[ -f "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-traffic.timer" &&
        -e "${MOCK_BACKEND}/enabled" && -e "${MOCK_BACKEND}/active" &&
        ! -e "${root}/data/net/.hopping-supervisor" &&
        ! -e "${root}/data/net/port-hopping.state" ]] ||
        fail "${protocol}: 流量调度缺失或意外启动了跳跃"
    status=$(dockerMain port-hopping status) || fail "${protocol}: 跳跃状态查询失败"
    jq -e --slurpfile expected "${source}/config/spec.json" '
      . == {state:"stopped",saved:$expected[0].port_hopping}
    ' <<<"${status}" >/dev/null || fail "${protocol}: 跳跃没有保持 stopped 及保存的 tuple"
}

for action in unconfirmed bad-confirm; do
    prepare_target "${action}"
    run_child "${action}" ok "${PADM_DOCKER_RC_USAGE}"
    assert_empty
done

# 准备期没有可信停服编排；真实硬杀后只能回收登记中的暂存。
for mode in preparing-begin preparing-stage preparing-extract preparing-candidate preparing-validated; do
    prepare_target "${mode}"
    run_child apply "${mode}" 137
    [[ -d "${root}/.restore-pending" && -e "${MOCK_BACKEND}/fault" ]] ||
        fail "${mode}: 没有在持久登记内命中硬杀"
    run_child lock ok failure
    run_child recover ok 0
    assert_empty
    ! grep -Eq '^up$|^down$|^systemctl:' "${MOCK_BACKEND}/events" ||
        fail "${mode}: 准备期恢复触碰了容器或外部调度"
    run_child recover ok 0
    assert_empty
done
prepare_target preparing-preview
run_child preview preparing-extract 137
[[ -d "${root}/.restore-pending" && -e "${MOCK_BACKEND}/fault" ]] ||
    fail '预览准备期未在持久登记内命中硬杀'
run_child recover ok 0
assert_empty
! grep -Eq '^up$|^down$|^systemctl:' "${MOCK_BACKEND}/events" ||
    fail '预览准备期恢复触碰了容器或外部调度'

for backend in systemd cron; do
    prepare_target "success-${backend}" "${backend}"
    run_child apply ok 0
    assert_deployed
    [[ ! -e "${root}/.restore-pending" && ! -e "${root}/locks/deployment.lock" ]] ||
        fail '成功事务没有清理登记或锁'
done

# 两项调度共享 crontab，Geo 后写入必须保留流量采集和无关任务。
for backend in systemd cron; do
    prepare_target "geo-success-${backend}" "${backend}"
    RECOVERY_ARCHIVE="${TEST_ROOT}/geo-enabled.tar"
    run_child apply ok 0
    assert_deployed "${GEO_ENABLED_SOURCE}"
    if [[ "${backend}" == systemd ]]; then
        [[ -f "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-traffic.service" &&
            -f "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-geo.service" &&
            -e "${MOCK_BACKEND}/geo-enabled" && -e "${MOCK_BACKEND}/geo-active" ]] ||
            fail '启用 Geo 恢复没有安装并启用两项调度'
        grep -qx 'ExecStart=.* geo auto-update' "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-geo.service" &&
            grep -qx 'OnCalendar=\*-\*-\* 01:35:00' "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-geo.timer" ||
            fail 'Geo 恢复没有使用受管命令或固定时间'
    else
        [[ "$(grep -c 'traffic collect' "${MOCK_BACKEND}/crontab")" == 1 &&
            "$(grep -c 'geo auto-update' "${MOCK_BACKEND}/crontab")" == 1 ]] ||
            fail 'Geo 恢复覆盖了流量采集或生成重复 cron'
        grep -qx '17 3 \* \* \* another-renewal # padm-docker TLS renewal root=/elsewhere' \
            "${MOCK_BACKEND}/crontab" || fail 'Geo 恢复覆盖了其它部署任务'
    fi
    [[ ! -e "${root}/.restore-pending" ]] || fail 'Geo 成功恢复残留登记'
done

# 停用或缺失 Geo 输入不接管宿主上既有的 Geo 任务。
for input in disabled absent; do
    prepare_target "geo-preserved-${input}" cron
    [[ "${input}" != absent ]] || RECOVERY_ARCHIVE="${TEST_ROOT}/no-geo.tar"
    printf 'external geo unit\n' >"${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-geo.service"
    printf '9 2 * * * external # padm-docker Geo 自动更新 root=/elsewhere\n' >>"${MOCK_BACKEND}/crontab"
    cp -- "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-geo.service" "${MOCK_BACKEND}/geo-before"
    run_child apply ok 0
    cmp -- "${MOCK_BACKEND}/geo-before" "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-geo.service" ||
        fail "${input}: 恢复接管了外部 Geo unit"
    grep -qx '9 2 \* \* \* external # padm-docker Geo 自动更新 root=/elsewhere' \
        "${MOCK_BACKEND}/crontab" || fail "${input}: 恢复接管了外部 Geo cron"
done

for backend in systemd cron; do
    for mode in geo-scheduler geo-killed; do
        prepare_target "${mode}-${backend}" "${backend}"
        RECOVERY_ARCHIVE="${TEST_ROOT}/geo-enabled.tar"
        expected=failure
        [[ "${mode}" != geo-killed ]] || expected=137
        run_child apply "${mode}" "${expected}"
        [[ -e "${MOCK_BACKEND}/fault" ]] || fail "${mode}/${backend}: Geo 故障未命中"
        if [[ "${mode}" == geo-scheduler ]]; then
            assert_empty
            continue
        fi
        [[ -d "${root}/.restore-pending/traffic-schedule" &&
            -d "${root}/.restore-pending/geo-schedule" ]] || fail 'Geo 硬杀未保存两项撤销登记'
        if [[ "${backend}" == systemd ]]; then
            current_schedule="${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-geo.service"
        else
            current_schedule="${MOCK_BACKEND}/crontab"
        fi
        cp -- "${current_schedule}" "${MOCK_BACKEND}/geo-expected"
        printf '\n# external Geo schedule change\n' >>"${current_schedule}"
        snapshot >"${MOCK_BACKEND}/pending-before"
        schedule_snapshot >"${MOCK_BACKEND}/schedule-pending-before"
        run_child recover ok failure
        snapshot >"${MOCK_BACKEND}/pending-after"
        schedule_snapshot >"${MOCK_BACKEND}/schedule-pending-after"
        cmp -- "${MOCK_BACKEND}/pending-before" "${MOCK_BACKEND}/pending-after" &&
            cmp -- "${MOCK_BACKEND}/schedule-pending-before" "${MOCK_BACKEND}/schedule-pending-after" ||
            fail 'Geo 漂移拒绝时改变了 traffic、部署或登记'
        cp -- "${MOCK_BACKEND}/geo-expected" "${current_schedule}"
        if [[ "${backend}" == systemd ]]; then
            dropin="${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-geo.service.d"
            mkdir -- "${dropin}"
            printf '[Service]\nEnvironment=EXTERNAL=1\n' >"${dropin}/override.conf"
            snapshot >"${MOCK_BACKEND}/pending-before"
            schedule_snapshot >"${MOCK_BACKEND}/schedule-pending-before"
            run_child recover ok failure
            snapshot >"${MOCK_BACKEND}/pending-after"
            schedule_snapshot >"${MOCK_BACKEND}/schedule-pending-after"
            cmp -- "${MOCK_BACKEND}/pending-before" "${MOCK_BACKEND}/pending-after" &&
                cmp -- "${MOCK_BACKEND}/schedule-pending-before" "${MOCK_BACKEND}/schedule-pending-after" ||
                fail 'Geo drop-in 拒绝时改变了 traffic、部署或登记'
            rm -f -- "${dropin}/override.conf"
            rmdir -- "${dropin}"
        else
            # Geo 已撤销、traffic 尚未撤销时再次硬杀，新进程仍须完整恢复。
            run_child recover geo-recover-killed 137
            [[ -e "${MOCK_BACKEND}/recover-fault" ]] || fail 'Geo 撤销后重试硬杀未命中'
        fi
        run_child recover ok 0
        assert_empty
        run_child recover ok 0
        assert_empty
    done
done
for mode in geo-int geo-term; do
    prepare_target "${mode}" systemd
    RECOVERY_ARCHIVE="${TEST_ROOT}/geo-enabled.tar"
    expected=130
    [[ "${mode}" != geo-term ]] || expected=143
    run_child apply "${mode}" "${expected}"
    [[ -e "${MOCK_BACKEND}/fault" ]] || fail "${mode}: Geo 信号故障未命中"
    assert_empty
done

for mode in geo-probe-fail nginx-fail first-write partial-move health int term; do
    prepare_target "${mode}"
    expected=failure
    [[ "${mode}" != int ]] || expected=130
    [[ "${mode}" != term ]] || expected=143
    run_child apply "${mode}" "${expected}"
    assert_empty
    if [[ "${mode}" == geo-probe-fail || "${mode}" == nginx-fail ]]; then
        ! grep -q '^up$' "${MOCK_BACKEND}/events" || fail "${mode}: 候选校验失败后启动了服务"
    fi
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

# 创建或复制原始快照时硬杀，恢复不得遗留锁下随机目录或触碰旧调度。
for mode in source-mkdir source-unit source-cron source-template \
    geo-source-mkdir geo-source-unit geo-source-cron geo-source-template; do
    backend=systemd
    [[ "${mode}" != *-cron ]] || backend=cron
    prepare_target "${mode}" "${backend}"
    dockerTrafficScheduleInstall || fail "${mode}: 旧调度准备失败"
    job=traffic
    if [[ "${mode}" == geo-* ]]; then
        job=geo
        RECOVERY_ARCHIVE="${TEST_ROOT}/geo-enabled.tar"
        dockerGeoScheduleApply install || fail "${mode}: 旧 Geo 调度准备失败"
    fi
    snapshot >"${MOCK_BACKEND}/before"
    schedule_snapshot >"${MOCK_BACKEND}/schedule-before"
    schedule_snapshot content >"${MOCK_BACKEND}/schedule-content-before"
    run_child apply "${mode}" 137
    source_snapshot="${root}/.restore-pending/${job}-source"
    [[ -e "${MOCK_BACKEND}/fault" && -d "${source_snapshot}" &&
        "$(stat -c '%u:%g:%a' "${source_snapshot}")" == 0:0:700 &&
        -z "$(find "${source_snapshot}" -type f ! -perm 0600 -print -quit)" ]] ||
        fail "${mode}: 硬杀未命中私密原始快照"
    if [[ "${mode}" == *-template ]]; then
        [[ -s "${source_snapshot}/new.service" ]] &&
            jq -e --arg source "${job}-source" '.snapshot == $source' \
                "${root}/.restore-pending/${job}-schedule/metadata.json" >/dev/null ||
            fail '模板首写前没有持久保存旧调度'
    else
        [[ ! -e "${root}/.restore-pending/${job}-schedule" ]] ||
            fail "${mode}: 没有在快照保存前硬杀"
    fi
    schedule_snapshot content >"${MOCK_BACKEND}/schedule-after-kill"
    cmp -- "${MOCK_BACKEND}/schedule-content-before" "${MOCK_BACKEND}/schedule-after-kill" ||
        fail "${mode}: 快照复制或模板暂存改变了外部调度"
    run_child recover ok 0
    assert_empty
done

# 安装与撤销的每个在线替换点硬杀，原始调度和新模板必须始终保持完整。
for operation in publish restore; do
    for job in traffic geo; do
        for kind in service timer; do
            for moment in before after; do
                mode="unit-${operation}-${job}-${kind}-${moment}"
                prepare_target "${mode}" systemd
                RECOVERY_ARCHIVE="${TEST_ROOT}/geo-enabled.tar"
                dockerTrafficScheduleInstall && dockerGeoScheduleApply install ||
                    fail "${mode}: 旧调度准备失败"
                for old_job in traffic geo; do
                    for old_kind in service timer; do
                        unit="${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-${old_job}.${old_kind}"
                        cp -- "${unit}" "${MOCK_BACKEND}/${old_job}.${old_kind}.new"
                        printf '\n# 原始调度注释\n' >>"${unit}"
                        cp -- "${unit}" "${MOCK_BACKEND}/${old_job}.${old_kind}.old"
                    done
                done
                snapshot >"${MOCK_BACKEND}/before"
                schedule_snapshot >"${MOCK_BACKEND}/schedule-before"
                action=apply
                if [[ "${operation}" == restore ]]; then
                    run_child apply geo-killed 137
                    if [[ "${job}" == traffic && "${kind}" == service && "${moment}" == before ]]; then
                        # 旧登记引用随机锁目录，回写仍须使用新的固定私密暂存。
                        legacy="${root}/locks/traffic-schedule.legacy"
                        mkdir -m 0700 -- "${legacy}"
                        cp -- "${root}/.restore-pending/traffic-schedule/padm-docker-traffic.service" \
                            "${root}/.restore-pending/traffic-schedule/padm-docker-traffic.timer" "${legacy}/"
                        metadata="${root}/.restore-pending/traffic-schedule/metadata.json"
                        jq '.snapshot = "traffic-schedule.legacy"' "${metadata}" >"${MOCK_BACKEND}/legacy-metadata"
                        cat -- "${MOCK_BACKEND}/legacy-metadata" >"${metadata}"
                    fi
                    action=recover
                fi
                run_child "${action}" "${mode}" 137
                [[ -e "${MOCK_BACKEND}/unit-fault" ]] || fail "${mode}: 原子替换硬杀未命中"
                assert_units_complete
                run_child recover ok 0
                assert_empty
                [[ -z "$(find "${PADM_DOCKER_SYSTEMD_DIR}" -type f ! -perm 0644 -print -quit)" ]] ||
                    fail "${mode}: 完成撤销后没有恢复 unit 权限"
                run_child recover ok 0
                assert_empty
            done
        done
    done
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

prepare_target geo-committed cron
RECOVERY_ARCHIVE="${TEST_ROOT}/geo-enabled.tar"
run_child apply committed 137
assert_deployed "${GEO_ENABLED_SOURCE}"
snapshot deployment >"${MOCK_BACKEND}/committed-before"
schedule_snapshot >"${MOCK_BACKEND}/schedule-committed-before"
run_child recover ok 0
snapshot deployment >"${MOCK_BACKEND}/committed-after"
schedule_snapshot >"${MOCK_BACKEND}/schedule-committed-after"
cmp -- "${MOCK_BACKEND}/committed-before" "${MOCK_BACKEND}/committed-after" &&
    cmp -- "${MOCK_BACKEND}/schedule-committed-before" "${MOCK_BACKEND}/schedule-committed-after" ||
    fail 'Geo committed 恢复修改了成功部署或共享 crontab'
[[ ! -e "${root}/.restore-pending" &&
    "$(grep -c '^down$' "${MOCK_BACKEND}/events" || true)" == 0 ]] ||
    fail 'Geo committed 恢复没有只清理登记'

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

prepare_target host-success
RECOVERY_ARCHIVE="${TEST_ROOT}/host.tar"
run_child apply ok 0
assert_deployed "${HOST_SOURCE}"
[[ ! -e "${root}/.restore-pending" && ! -e "${root}/locks/deployment.lock" ]] ||
    fail '宿主共存成功事务没有清理登记或锁'

for mode in nginx-fail partial-move health term; do
    prepare_target "host-${mode}"
    RECOVERY_ARCHIVE="${TEST_ROOT}/host.tar"
    expected=failure
    [[ "${mode}" != term ]] || expected=143
    run_child apply "${mode}" "${expected}"
    assert_empty
    if [[ "${mode}" == nginx-fail ]]; then
        ! grep -q '^up$' "${MOCK_BACKEND}/events" || fail '宿主共存 Nginx 失败后启动了服务'
    elif [[ "${mode}" == partial-move ]]; then
        [[ -e "${MOCK_BACKEND}/fault" ]] || fail '宿主共存部分写入故障未注入'
    fi
done
prepare_target host-killed
RECOVERY_ARCHIVE="${TEST_ROOT}/host.tar"
run_child apply killed 137
[[ -d "${root}/.restore-pending" && -e "${MOCK_BACKEND}/compose-container" ]] ||
    fail '宿主共存硬杀未保留恢复登记与运行现场'
run_child recover ok 0
assert_empty

prepare_target http01-success
RECOVERY_ARCHIVE="${TEST_ROOT}/http01.tar"
run_child apply ok 0
assert_deployed "${HTTP01_SOURCE}"
[[ ! -e "${root}/.restore-pending" && ! -e "${root}/locks/deployment.lock" ]] ||
    fail 'HTTP-01 成功事务没有清理登记或锁'

# 复用既有故障点，确认新建挑战根与部署一起撤销。
for mode in nginx-fail partial-move health int term; do
    prepare_target "http01-${mode}"
    RECOVERY_ARCHIVE="${TEST_ROOT}/http01.tar"
    expected=failure
    [[ "${mode}" != int ]] || expected=130
    [[ "${mode}" != term ]] || expected=143
    run_child apply "${mode}" "${expected}"
    assert_empty
    if [[ "${mode}" == nginx-fail ]]; then
        ! grep -q '^up$' "${MOCK_BACKEND}/events" || fail 'HTTP-01 Nginx 失败后启动了服务'
    elif [[ "${mode}" == partial-move ]]; then
        [[ -e "${MOCK_BACKEND}/fault" ]] || fail 'HTTP-01 部分写入故障未注入'
    fi
done
prepare_target http01-killed
RECOVERY_ARCHIVE="${TEST_ROOT}/http01.tar"
run_child apply killed 137
[[ -d "${root}/.restore-pending" && -d "${root}/data/acme-webroot" &&
    -e "${MOCK_BACKEND}/compose-container" ]] || fail 'HTTP-01 硬杀未保留挑战根与恢复现场'
run_child recover ok 0
assert_empty

for protocol in hy2 tuic; do
    prepare_target "hopping-${protocol}"
    RECOVERY_ARCHIVE="${TEST_ROOT}/hopping-${protocol}.tar"
    run_child apply ok 0
    assert_hopping_deployed "${protocol}"
    [[ ! -e "${root}/.restore-pending" && ! -e "${root}/locks/deployment.lock" ]] ||
        fail "${protocol}: 成功事务没有清理登记或锁"
done

# 代表协议复用事务故障点，不重复真实跳跃数据面验收。
for mode in sing-box-fail first-write partial-move health int term; do
    prepare_target "hopping-${mode}"
    RECOVERY_ARCHIVE="${TEST_ROOT}/hopping-tuic.tar"
    expected=failure
    [[ "${mode}" != int ]] || expected=130
    [[ "${mode}" != term ]] || expected=143
    run_child apply "${mode}" "${expected}"
    assert_empty
    if [[ "${mode}" == sing-box-fail ]]; then
        ! grep -q '^up$' "${MOCK_BACKEND}/events" || fail 'sing-box 校验失败后启动了服务'
    fi
    if [[ "${mode}" == first-write || "${mode}" == partial-move ]]; then
        [[ -e "${MOCK_BACKEND}/fault" ]] || fail "${mode}: 跳跃恢复故障未注入"
    fi
done
prepare_target hopping-killed
RECOVERY_ARCHIVE="${TEST_ROOT}/hopping-tuic.tar"
run_child apply killed 137
[[ -d "${root}/.restore-pending" && -e "${MOCK_BACKEND}/compose-container" &&
    ! -e "${root}/data/net/.hopping-supervisor" && ! -e "${root}/data/net/port-hopping.state" ]] ||
    fail '跳跃恢复硬杀未保留登记，或意外恢复了运行态'
run_child recover ok 0
assert_empty
printf 'docker-recovery-apply-ok: %s cases\n' "${CASES}"
