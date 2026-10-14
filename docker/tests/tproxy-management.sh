#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-tproxy-management.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "tproxy-management-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]]
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_SKIP_CHOWN=0
export PADM_DOCKER_HEALTH_TIMEOUT=1 PADM_DOCKER_LOCK_TIMEOUT=1 PYTHONDONTWRITEBYTECODE=1
root=${PADM_DOCKER_INSTALL_DIR}
LOG=${TEST_ROOT}/command.log
CALLS=${TEST_ROOT}/calls.log
MODE=ok
UUID=11111111-1111-4111-8111-111111111111
fail() { cat "${LOG}" >&2; printf 'tproxy-management-fail: %s\n' "$*" >&2; exit 1; }
# 仅宿主、发布与容器边界替身；输入、候选、冻结、备份和恢复沿生产事务。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { :; }
dockerLockInstalledDeployment() { dockerAcquireDeploymentLock; }
dockerConfigureReleasePrepare() { :; }
dockerConfigureReleaseValidate() { :; }
dockerRealityTargetsValidate() { :; }
dockerConfigurePortsAvailable() { :; }
dockerSetupRealityPublicKey() {
    cat >/dev/null
    printf '%s\n' hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo
}
dockerTrafficRuntimeCheck() { :; }
dockerTrafficBeforeChange() { :; }
dockerTrafficScheduleInstall() { :; }
dockerRenewalScheduleInstall() { :; }
dockerGeoScheduleInstall() { :; }
dockerIPv6NetworkManage() { :; }
dockerManifestImageReference() { jq -er --arg image "$1" '.images[$image]' "${TEST_ROOT}/base.json"; }
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
dockerCandidateCompose() {
    [[ -d "$1" && -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]]
}
docker() {
    [[ "${1:-}" == ps ]] && return 0
    printf 'unexpected docker command: %s\n' "$*" >&2
    return 1
}
dockerComposeRun() {
    printf '%s\n' "$*" >>"${CALLS}"
    [[ -e "${root}/locks/deployment.lock" ]]
    if [[ "${1:-}" == up && "${MODE}" != ok && ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"
        [[ "${MODE}" != interrupt-int ]] || kill -INT "${BASHPID}"
        [[ "${MODE}" != interrupt-term ]] || kill -TERM "${BASHPID}"
        return 1
    fi
}
dockerComposeExecute() {
    [[ "${1:-}" == down || "${1:-}" == run ]] || return 1
    dockerComposeRun "$@"
}
mkdir -p "${TEST_ROOT}/bundle/docker/contracts"
printf '%040d\n' 1 >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
cp -- "${PROJECT_ROOT}/docker/contracts/"{configure.schema.json,features.json} \
    "${TEST_ROOT}/bundle/docker/contracts/"
dockerInitializeStateRoot
jq -n --arg uuid "${UUID}" '
  {schema_version:3,release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"fixture"},
   core:{type:"xray",secondary_type:null,protocols:[{id:1,core:"xray",listener_id:"entry-xray",
     server:"proxy.example.com",public_port:35441,address_families:["ipv4"],name:"Reality",uuid:$uuid,
     reality:{server_name:"www.debian.org",target_host:"www.debian.org",target_port:443,
       private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
       public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",short_id:"1234"}}]},
   tls:null,subscription:{enabled:false,token:"0123456789abcdef"},
   images:(["xray","sing-box","nginx","ops","net"] | map({key:.,value:
     ("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries),
   host_integrations:[]}
' >"${TEST_ROOT}/base.json"
snapshot() (
    cd "${root}"
    find config data secrets -type f -printf '%p %m %U %G %n\n' | LC_ALL=C sort
    find config data secrets -type f -print0 | sort -z | xargs -0 -r sha256sum
    for path in compose.json deployment.json deployment.previous.json images.env; do
        [[ ! -f "${path}" ]] || sha256sum "${path}"
    done
)
assertClean() {
    [[ ! -e "${root}/locks/deployment.lock" ]]
    [[ -z "$(find "${root}" -maxdepth 1 \( -name '.candidate.*' -o -name '.edit.*' -o -name '.protocol.*' \) -print -quit)" ]]
}
runEdit() {
    local expected=$1 actual=0
    shift
    (dockerMain edit "$@") >"${LOG}" 2>&1 || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "edit $*: expected ${expected}, actual ${actual}"
    assertClean
}
runStatus() {
    local enabled=$1 port=$2 mark=$3
    (dockerMain protocol tproxy-status) >"${LOG}" 2>&1 || fail 'status failed'
    jq -e --argjson enabled "${enabled}" --argjson port "${port}" --argjson mark "${mark}" '
      . == {enabled:$enabled,port:$port,mark:$mark,family:"ipv4",hook:"PREROUTING"}
    ' "${LOG}" >/dev/null
    assertClean
}
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/base.json" '' '' configure
) >"${LOG}" 2>&1 || fail 'initial fixture failed'
assertClean
jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{($uuid):{
  name:"business",upload:17,download:19,limit_bytes:0,baseline:{}}}}' | dockerTrafficWriteState
before=$(snapshot)
runStatus false null null
runEdit 15 --tproxy-off --preview
runEdit 15 --tproxy-settings 31298 129 --preview
for args in '0 129' '65536 129' '31298 0' '31298 253' '31298 254' '31298 255' \
    '31298 2147483648' '031298 129' '31298 0129'; do
    read -r port mark <<<"${args}"
    runEdit 2 --tproxy-enable "${port}" "${mark}" --preview
done
runEdit 2 --tproxy-enable 31298 129 --tproxy-off --preview
runEdit 2 --tproxy-enable 31298 129 --dns-off --preview
runEdit 2 --tproxy-enable 31298 129 --spec "${TEST_ROOT}/base.json" --preview
runEdit 15 --tproxy-enable 35441 129 --preview
runEdit 15 --tproxy-enable 10085 129 --preview
runEdit 0 --tproxy-enable 31298 129 --preview
[[ "$(snapshot)" == "${before}" ]] || fail 'preview or invalid input changed live state'
runEdit 0 --tproxy-enable 31298 129 --confirm PADM-DOCKER-EDIT
cp -- "${root}/config/spec.json" "${TEST_ROOT}/owner-spec.json"
runStatus true 31298 129
jq -e '.services.xray.network_mode == "host" and .services.xray.user == "0:0" and
  .services.xray.cap_add == ["NET_ADMIN"] and .services.xray.ports == null and
  .services["net-transparent"].command == ["tproxy","31298","129"]' "${root}/compose.json" >/dev/null
jq -e 'any(.inbounds[]; .tag == "tproxy-in" and .port == 31298 and
  .settings.followRedirect == true and .settings.network == "tcp,udp")' \
    "${root}/config/xray/config.json" >/dev/null
before=$(snapshot)
runEdit 15 --tproxy-enable 31299 131 --preview
runEdit 15 --tproxy-settings 31298 129 --preview
runEdit 0 --tproxy-settings 31299 131 --preview
[[ "$(snapshot)" == "${before}" ]] || fail 'settings preview changed live state'
runEdit 0 --tproxy-settings 31299 131 --confirm PADM-DOCKER-EDIT
runStatus true 31299 131
jq -e '.services["net-transparent"].command == ["tproxy","31299","131"]' "${root}/compose.json" >/dev/null
jq -e 'any(.inbounds[]; .tag == "tproxy-in" and .port == 31299)' "${root}/config/xray/config.json" >/dev/null
before=$(snapshot)
for MODE in health-fail interrupt-int interrupt-term; do
    rm -f -- "${TEST_ROOT}/failed-once"
    expected=14
    [[ "${MODE}" != interrupt-int ]] || expected=130
    [[ "${MODE}" != interrupt-term ]] || expected=143
    runEdit "${expected}" --tproxy-settings 31300 132 --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail "${MODE}: incomplete transaction recovery"
done
MODE=ok
cp -- "${root}/config/spec.json" "${TEST_ROOT}/enabled.json"
# 专项豁免仅覆盖 TProxy 字段；普通规格导入不能借机关闭或修改。
runEdit 15 --spec "${TEST_ROOT}/base.json" --confirm PADM-DOCKER-EDIT
jq '.host_integrations[0].settings.port = 31300' "${TEST_ROOT}/enabled.json" >"${TEST_ROOT}/changed.json"
runEdit 15 --spec "${TEST_ROOT}/changed.json" --confirm PADM-DOCKER-EDIT
(
    tproxyAction=settings
    jq '.core.protocols[0].uuid = "22222222-2222-4222-8222-222222222222"' \
        "${TEST_ROOT}/enabled.json" >"${TEST_ROOT}/tampered.json"
    ! dockerEditCompatibilityValidate "${TEST_ROOT}/enabled.json" "${TEST_ROOT}/tampered.json"
)
runEdit 0 --tproxy-off --preview
[[ "$(snapshot)" == "${before}" ]] || fail 'off preview changed live state'
MODE=health-fail
rm -f -- "${TEST_ROOT}/failed-once"
runEdit 14 --tproxy-off --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail 'off failure did not restore TProxy'
MODE=ok
runEdit 0 --tproxy-off --confirm PADM-DOCKER-EDIT
runStatus false null null
jq -en --slurpfile expected "${TEST_ROOT}/base.json" --slurpfile actual "${root}/config/spec.json" \
    '$expected == $actual' >/dev/null
jq -e '.accounts["11111111-1111-4111-8111-111111111111"].upload == 17 and
  .accounts["11111111-1111-4111-8111-111111111111"].download == 19' "${root}/data/traffic/state.json" >/dev/null
jq -e '.services["net-transparent"] == null and .services.xray.network_mode == null and
  .services.xray.ports == ["0.0.0.0:35441:35441/tcp"]' "${root}/compose.json" >/dev/null
jq -e 'all(.inbounds[]; .tag != "tproxy-in")' "${root}/config/xray/config.json" >/dev/null
# 实际管理事务之外，核对停止证明会拒绝归属漂移及不完整撤销。
runEdit 0 --tproxy-enable 31298 129 --confirm PADM-DOCKER-EDIT
(
    CID=$(printf 'b%.0s' {1..64})
    OTHER_CID=$(printf 'c%.0s' {1..64})
    OWNER_MODE=ok
    OWNER_LOG=${TEST_ROOT}/owner.log
    OWNER_JSON=${TEST_ROOT}/owner.json
    jq -n --arg root "${root}" --arg cid "${CID}" \
        --slurpfile spec "${root}/config/spec.json" --slurpfile compose "${root}/compose.json" '
      $compose[0].services["net-transparent"] as $s |
      [{Id:$cid,State:{Running:true,Restarting:false,Paused:false,Dead:false,OOMKilled:false,
          Status:"running",ExitCode:0,Error:""},
        Config:{Image:$spec[0].images.net,Cmd:$s.command,Entrypoint:["/usr/local/bin/padm-entrypoint"],
          User:"0:0",Healthcheck:{Test:$s.healthcheck.test},Labels:($s.labels + {
            "com.docker.compose.project":"padm-docker",
            "com.docker.compose.project.working_dir":$root,
            "com.docker.compose.project.config_files":($root+"/compose.json"),
            "com.docker.compose.service":"net-transparent","com.docker.compose.oneoff":"False"})},
        HostConfig:{NetworkMode:"host",Init:$s.init,RestartPolicy:{Name:$s.restart},
          ReadonlyRootfs:$s.read_only,Privileged:false,PidsLimit:$s.pids_limit,PortBindings:{},
          CapAdd:$s.cap_add,CapDrop:$s.cap_drop,SecurityOpt:$s.security_opt,
          LogConfig:{Type:$s.logging.driver,Config:$s.logging.options},
          Tmpfs:($s.tmpfs | map(split(":") | {key:.[0],value:.[1]}) | from_entries)},
        Mounts:[$s.volumes[] | {Type:"bind",Source:(.source | sub("^\\$\\{PADM_NET_ROOT\\}";$root)),
          Destination:.target,RW:(.read_only | not)}]}]
    ' >"${TEST_ROOT}/owner-base.json"
    resetOwner() {
        cp -- "${TEST_ROOT}/owner-base.json" "${OWNER_JSON}"
        printf '%s\n' fixture >"${root}/data/net/transparent/tproxy.state"
        : >"${OWNER_LOG}"
    }
    docker() {
        case "$1" in
        ps)
            [[ "${OWNER_MODE}" != absent ]] || return 0
            [[ "${OWNER_MODE}" != duplicate ]] || printf '%s\n' "${OTHER_CID}"
            jq -r '.[0].Id' "${OWNER_JSON}"
            ;;
        container) cat "${OWNER_JSON}" ;;
        exec) [[ "${OWNER_MODE}" != health-fail ]] ;;
        stop)
            printf 'stop %s\n' "$2" >>"${OWNER_LOG}"
            [[ "${OWNER_MODE}" != stop-fail ]] || return 1
            jq --arg mode "${OWNER_MODE}" --arg other "${OTHER_CID}" '
              .[0].State.Running=false | .[0].State.Status="exited" |
              if $mode=="bad-exit" then .[0].State.ExitCode=137
              elif $mode=="cid-drift" then .[0].Id=$other else . end
            ' "${OWNER_JSON}" >"${OWNER_JSON}.next"
            mv -- "${OWNER_JSON}.next" "${OWNER_JSON}"
            [[ "${OWNER_MODE}" == keep-state ]] || rm -f -- "${root}/data/net/transparent/tproxy.state"
            ;;
        rm)
            printf 'rm %s\n' "$2" >>"${OWNER_LOG}"
            [[ "$2" == "${CID}" ]]
            ;;
        *) fail "unexpected owner command: $*" ;;
        esac
    }
    dockerComposeExecute() {
        [[ "$*" == 'run --rm --no-deps net-transparent preflight tproxy 31298 129 unowned' ]] ||
            fail "unexpected cleanup command: $*"
        printf 'clean\n' >>"${OWNER_LOG}"
        [[ "${OWNER_MODE}" != clean-fail ]]
    }
    for OWNER_MODE in health-fail duplicate stop-fail bad-exit cid-drift keep-state clean-fail absent; do
        resetOwner
        ! dockerTProxyDisablePrepare "${root}/config/spec.json" || fail "accepted ${OWNER_MODE}"
        ! grep -q '^rm ' "${OWNER_LOG}" || fail "removed owner after ${OWNER_MODE}"
    done
    OWNER_MODE=ok
    for drift in '.Config.Cmd[1]="31299"' '.HostConfig.CapAdd=["SYS_ADMIN"]' \
        '.Mounts[0].Source="/tmp/foreign"' '.Config.Labels["io.padm.release"]="foreign"'; do
        resetOwner
        jq ".[0] |= (${drift})" "${OWNER_JSON}" >"${OWNER_JSON}.next"
        mv -- "${OWNER_JSON}.next" "${OWNER_JSON}"
        ! dockerTProxyDisablePrepare "${root}/config/spec.json" || fail "accepted drift ${drift}"
        [[ ! -s "${OWNER_LOG}" ]] || fail 'stopped a foreign container'
    done
    resetOwner
    dockerTProxyDisablePrepare "${root}/config/spec.json"
    [[ "$(cat "${OWNER_LOG}")" == "$(printf 'stop %s\nclean\nrm %s' "${CID}" "${CID}")" ]] ||
        fail 'stop, cleanup proof and removal order changed'
    [[ ! -e "${root}/data/net/transparent/tproxy.state" ]] || fail 'state survived successful stop'
    cp -- "${TEST_ROOT}/base.json" "${root}/config/spec.json"
    ! dockerTProxyDisablePrepare "${TEST_ROOT}/base.json" || fail 'accepted contradictory disabled spec'
    cp -- "${TEST_ROOT}/owner-spec.json" "${root}/config/spec.json"
)
(
    PADM_DOCKER_LIFECYCLE_LOADED=0
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/docker/lib/lifecycle.sh"
    LIFECYCLE_LOG=${TEST_ROOT}/lifecycle.log
    LIFECYCLE_MODE=ok
    dockerTProxyDisablePrepare() {
        printf 'prepare\n' >>"${LIFECYCLE_LOG}"
        [[ "${LIFECYCLE_MODE}" != stop-fail ]]
    }
    dockerTProxyContainer() { printf 'audit\n' >>"${LIFECYCLE_LOG}"; }
    dockerComposeExecute() { printf 'compose %s\n' "$*" >>"${LIFECYCLE_LOG}"; }
    checkLifecycle() {
        local expected=$1
        shift
        : >"${LIFECYCLE_LOG}"
        dockerComposeRun "$@"
        [[ "$(cat "${LIFECYCLE_LOG}")" == "${expected}" ]] ||
            fail "unexpected lifecycle order: $*"
    }
    recreate='compose up -d --wait --wait-timeout 1 net-transparent'
    checkLifecycle "$(printf 'prepare\ncompose restart\n%s\naudit' "${recreate}")" restart
    checkLifecycle "$(printf 'prepare\n%s\naudit' "${recreate}")" restart --no-deps net-transparent
    checkLifecycle "$(printf 'prepare\ncompose down')" down
    checkLifecycle "$(printf 'prepare\ncompose up -d --force-recreate --no-deps xray\n%s\naudit' "${recreate}")" \
        up -d --force-recreate --no-deps xray
    checkLifecycle 'compose up -d --no-deps acme' up -d --no-deps acme
    LIFECYCLE_MODE=stop-fail
    : >"${LIFECYCLE_LOG}"
    ! dockerComposeRun restart || fail 'restart ignored failed TProxy stop'
    [[ "$(cat "${LIFECYCLE_LOG}")" == prepare ]] || fail 'Compose ran after failed stop'
    (
        for path in config/spec.json deployment.json compose.json; do
            cp -p -- "${root}/${path}" "${TEST_ROOT}/mixed-${path##*/}"
        done
        trap 'for path in config/spec.json deployment.json compose.json; do cp -p -- "${TEST_ROOT}/mixed-${path##*/}" "${root}/${path}"; done' EXIT
        for path in config/spec.json deployment.json; do
            jq '.host_integrations += [{type:"fail2ban",profile:"net-fail2ban"}]' \
                "${root}/${path}" >"${root}/${path}.next"
            mv -- "${root}/${path}.next" "${root}/${path}"
        done
        jq '.services["net-fail2ban"] = {}' "${root}/compose.json" >"${root}/compose.json.next"
        mv -- "${root}/compose.json.next" "${root}/compose.json"
        dockerFail2banConfigurationCheck() { printf 'fail2ban-check\n' >>"${LIFECYCLE_LOG}"; }
        dockerFail2banSourceInputsCheck() { :; }
        dockerFail2banDisablePrepare() { printf 'fail2ban-prepare\n' >>"${LIFECYCLE_LOG}"; }
        dockerControlFail2banDisablePrepare() { :; }
        dockerSshFail2banDisablePrepare() { :; }
        dockerFail2banStartManagedVerified() { printf 'fail2ban-start\n' >>"${LIFECYCLE_LOG}"; }
        dockerComposeExecute() {
            printf 'compose %s\n' "$*" >>"${LIFECYCLE_LOG}"
            [[ "${LIFECYCLE_MODE}" != up-fail ]]
        }
        LIFECYCLE_MODE=ok
        checkLifecycle "$(printf 'prepare\nfail2ban-check\nfail2ban-prepare\nfail2ban-start\n%s\naudit' "${recreate}")" restart
        LIFECYCLE_MODE=up-fail
        : >"${LIFECYCLE_LOG}"
        ! dockerComposeRun restart || fail 'mixed restart ignored TProxy start failure'
        [[ "$(cat "${LIFECYCLE_LOG}")" == "$(printf 'prepare\nfail2ban-check\nfail2ban-prepare\nfail2ban-start\n%s' "${recreate}")" ]] ||
            fail 'mixed restart audited after failed TProxy start'
    )
)
before=$(snapshot)
(
    originalPrepare=$(declare -f dockerTProxyDisablePrepare)
    eval "${originalPrepare/dockerTProxyDisablePrepare/originalTProxyPrepare}"
    dockerTProxyDisablePrepare() {
        originalTProxyPrepare "$@" || return $?
        if [[ ! -e "${TEST_ROOT}/prepare-signal" ]]; then
            : >"${TEST_ROOT}/prepare-signal"
            kill -INT "${BASHPID}"
        fi
    }
    runEdit 130 --tproxy-settings 31300 132 --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail 'stop signal did not restore old TProxy'
)
printf 'docker-tproxy-management-ok\n'
