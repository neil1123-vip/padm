#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-wireguard-management.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "wireguard-management-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]]
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_SKIP_CHOWN=0
export PADM_DOCKER_HEALTH_TIMEOUT=1 PYTHONDONTWRITEBYTECODE=1
root=${PADM_DOCKER_INSTALL_DIR}
LOG=${TEST_ROOT}/output.log
CALLS=${TEST_ROOT}/calls.log
CID=$(printf 'a%.0s' {1..64})
OTHER_CID=$(printf 'b%.0s' {1..64})
MODE=ok
checks=0
fail() { cat "${LOG}" >&2; printf 'wireguard-management-fail: %s\n' "$*" >&2; exit 1; }
# 规格、部署、编排和生产启停函数均实际执行，只替换发布与 Docker 边界。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/wireguard.sh"
dockerRealityTargetsValidate() { :; }
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
dockerConfigureReleaseReuseInstalled() { printf 'release-reuse\n' >>"${CALLS}"; }
dockerConfigureApply() {
    [[ "$#" == 1 && "$1" == "${root}/config/spec.json" ]] &&
        cmp -s -- "$1" "${TEST_ROOT}/base.json" || return 1
    printf 'apply-original-spec\n' >>"${CALLS}"
}
mkdir -p "${TEST_ROOT}/bundle/docker/contracts"
printf '%040d\n' 1 >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
cp -- "${PROJECT_ROOT}/docker/contracts/"{configure.schema.json,features.json} \
    "${TEST_ROOT}/bundle/docker/contracts/"
dockerInitializeStateRoot
mkdir -p "${root}/secrets/net/wireguard" "${root}/data/net/wireguard"
chmod 0700 "${root}/secrets/net/wireguard" "${root}/data/net/wireguard"
printf '%s\n' '[Interface]' 'PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' \
    'Address = 10.77.0.1/30' 'ListenPort = 51820' '[Peer]' \
    'PublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=' \
    'AllowedIPs = 10.77.0.2/32' >"${root}/secrets/net/wireguard/wg-padm.conf"
chmod 0600 "${root}/secrets/net/wireguard/wg-padm.conf"
jq -n '
  {schema_version:3,release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"fixture"},
   core:{type:"xray",secondary_type:null,protocols:[{id:1,core:"xray",listener_id:"entry-xray",
     server:"proxy.example.com",public_port:35441,address_families:["ipv4"],name:"Reality",
     uuid:"11111111-1111-4111-8111-111111111111",
     reality:{server_name:"www.debian.org",target_host:"www.debian.org",target_port:443,
       private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
       public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",short_id:"1234"}}]},
   tls:null,subscription:{enabled:false,token:"0123456789abcdef"},
   images:(["xray","sing-box","nginx","ops","net"] | map({key:.,value:
     ("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries),
   host_integrations:[{type:"wireguard",profile:"net-wireguard",firewall_rules:[],
     devices:["wg-padm"],schedules:[],settings:{config_file:"wg-padm.conf",interface:"wg-padm"}}]}
' >"${TEST_ROOT}/base.json"

writeState() {
    local state=$1
    jq --arg state "${state}" '
      .[0].State = {Status:$state,Running:($state == "running"),Restarting:false,
        Paused:false,Dead:false,OOMKilled:false,Error:"",ExitCode:0}
    ' "${TEST_ROOT}/inspect.json" >"${TEST_ROOT}/next.json"
    mv -- "${TEST_ROOT}/next.json" "${TEST_ROOT}/inspect.json"
    if [[ "${state}" == running ]]; then
        mkdir -p "${root}/data/net/wireguard/wireguard"
        chmod 0700 "${root}/data/net/wireguard/wireguard"
        cp -- "${root}/secrets/net/wireguard/wg-padm.conf" \
            "${root}/data/net/wireguard/wireguard/wg-padm.conf"
        chmod 0600 "${root}/data/net/wireguard/wireguard/wg-padm.conf"
        printf 'fixture-owner\n' >"${root}/data/net/wireguard/wireguard.state"
        chmod 0600 "${root}/data/net/wireguard/wireguard.state"
    else
        rm -f -- "${root}/data/net/wireguard/wireguard.state" \
            "${root}/data/net/wireguard/wireguard/wg-padm.conf"
        rmdir -- "${root}/data/net/wireguard/wireguard" 2>/dev/null || true
    fi
}
fixture() {
    local state=${1:-running}
    MODE=ok
    cp -- "${TEST_ROOT}/base.json" "${root}/config/spec.json"
    chmod 0600 "${root}/config/spec.json"
    render
    printf '%s\n' "${CID}" >"${TEST_ROOT}/ids"
    jq -n --arg root "${root}" --arg id "${CID}" \
        --slurpfile spec "${root}/config/spec.json" --slurpfile compose "${root}/compose.json" '
      $compose[0].services["net-wireguard"] as $s |
      [{Id:$id,Config:{Image:$spec[0].images.net,Cmd:$s.command,
        Entrypoint:["/usr/local/bin/padm-entrypoint"],User:"0:0",
        Healthcheck:{Test:$s.healthcheck.test},
        Labels:($s.labels + {"com.docker.compose.project":"padm-docker",
          "com.docker.compose.project.working_dir":$root,
          "com.docker.compose.project.config_files":($root + "/compose.json"),
          "com.docker.compose.service":"net-wireguard","com.docker.compose.oneoff":"False"})},
        HostConfig:{NetworkMode:"host",Init:$s.init,RestartPolicy:{Name:$s.restart},
          ReadonlyRootfs:$s.read_only,Privileged:false,PidsLimit:$s.pids_limit,
          PortBindings:{},Devices:[],CapAdd:$s.cap_add,CapDrop:$s.cap_drop,
          SecurityOpt:$s.security_opt,LogConfig:{Type:$s.logging.driver,Config:$s.logging.options},
          Tmpfs:($s.tmpfs | map(capture("^(?<key>[^:]+):(?<value>.+)$")) | from_entries)},
        Mounts:[$s.volumes[] | {Type:"bind",Source:(.source | sub("^\\$\\{PADM_NET_ROOT\\}"; $root)),
          Destination:.target,RW:(.read_only | not)}]}]
    ' >"${TEST_ROOT}/inspect.json"
    writeState "${state}"
    : >"${CALLS}"
}
render() {
    dockerConfigureSpecValidate "${root}/config/spec.json" >"${LOG}" 2>&1 ||
        fail "invalid fixture spec after ${checks} checks"
    dockerGenerateCompose "${root}/config/spec.json" "${root}/compose.json" "${root}"
    dockerGenerateDeployment "${root}/config/spec.json" "${root}/deployment.json"
    : >"${root}/images.env"
    dockerGenerateImagesEnv "${root}/config/spec.json" "${root}/images.env" "${root}"
}
mutate() {
    jq "$1" "${TEST_ROOT}/inspect.json" >"${TEST_ROOT}/next.json"
    mv -- "${TEST_ROOT}/next.json" "${TEST_ROOT}/inspect.json"
}
docker() {
    printf '%s\n' "$*" >>"${CALLS}"
    case "${1:-}" in
    ps)
        [[ "$*" == "ps -aq --no-trunc --filter label=com.docker.compose.project=padm-docker --filter label=com.docker.compose.service=net-wireguard --filter label=com.docker.compose.oneoff=False" ]] ||
            return 1
        cat "${TEST_ROOT}/ids"
        ;;
    container)
        [[ "$#" == 3 && "$2" == inspect && ( "$3" == "${CID}" || "$3" == "${OTHER_CID}" ) ]] || return 1
        cat "${TEST_ROOT}/inspect.json"
        ;;
    exec)
        [[ "$*" == "exec ${CID} /usr/local/bin/padm-entrypoint wireguard-health wg-padm" ]] || return 1
        [[ "${MODE}" != health-fail ]]
        ;;
    run)
        local image
        image=$(jq -r '.images.net' "${root}/config/spec.json")
        [[ "$#" == 18 && "$2" == --rm && "$3" == --network && "$4" == host &&
            "$5" == --read-only && "$6" == --cap-drop && "$7" == ALL &&
            "$8" == --security-opt && "$9" == no-new-privileges:true &&
            "${10}" == --pids-limit && "${11}" == 16 && "${12}" == --user && "${13}" == 0:0 &&
            "${14}" == --entrypoint && "${15}" == /bin/sh && "${16}" == "${image}" &&
            "${17}" == -ec && "${18}" == 'ip -o link show >/dev/null && ! ip link show dev wg-padm >/dev/null 2>&1' ]] ||
            return 1
        [[ "${MODE}" != link-present && "${MODE}" != link-fail ]]
        ;;
    start)
        [[ "$#" == 2 && "$2" == "${CID}" ]] || return 1
        [[ "${MODE}" != start-refused ]] || return 1
        writeState running
        case "${MODE}" in
        start-fail) return 1 ;;
        snapshot-missing) rm -f -- "${root}/data/net/wireguard/wireguard/wg-padm.conf" ;;
        owner-drift) mutate '.[0].Config.Cmd = ["foreign"]' ;;
        id-drift)
            printf '%s\n' "${OTHER_CID}" >"${TEST_ROOT}/ids"
            mutate '.[0].Id = ("b"*64)'
            ;;
        restarting) mutate '.[0].State.Restarting = true | .[0].State.Status = "restarting"' ;;
        interrupt-int) kill -INT "${BASHPID}" ;;
        interrupt-term) kill -TERM "${BASHPID}" ;;
        esac
        ;;
    stop)
        [[ "$*" == "stop -t 30 ${CID}" ]] || return 1
        [[ "${MODE}" != stop-fail ]] || return 1
        if [[ "${MODE}" == stop-state-retained ]]; then
            mutate '.[0].State.Running = false | .[0].State.Status = "exited"'
        else
            writeState exited
        fi
        ;;
    *) return 1 ;;
    esac
}
runService() {
    local expected=$1 status=0
    shift
    (dockerWireGuardService "$@") >"${LOG}" 2>&1 || status=$?
    [[ "${status}" == "${expected}" ]] || fail "$*: expected ${expected}, actual ${status}"
    checks=$((checks + 1))
}
assertNoWrite() {
    ! grep -Eq '^(start|stop|rm|apply-original-spec)( |$)' "${CALLS}" ||
        fail 'unexpected runtime write'
}
assertGateFails() {
    ! dockerWireGuardContainer "${1:-running}" >"${LOG}" 2>&1 || fail 'drift accepted'
    assertNoWrite
    checks=$((checks + 1))
}

fixture running
[[ "$(dockerWireGuardContainer running)" == "${CID}" ]]
runService 0 start
assertNoWrite
runService 0 stop
grep -Fxq "stop -t 30 ${CID}" "${CALLS}"
[[ "$(cat "${TEST_ROOT}/ids")" == "${CID}" ]]
! grep -q '^rm ' "${CALLS}"
: >"${CALLS}"
runService 0 stop
assertNoWrite
runService 0 start
grep -Fxq "start ${CID}" "${CALLS}"
[[ "$(dockerWireGuardContainer running)" == "${CID}" ]]

for mutation in \
    '.[0].Id = ("b"*64)' \
    '.[0].Config.Labels["com.docker.compose.project.working_dir"] = "/foreign"' \
    '.[0].Config.Image = "foreign:latest"' \
    '.[0].Config.Cmd = ["foreign"]' \
    '.[0].Config.Entrypoint = ["/bin/sh"]' \
    '.[0].Config.User = "10001:10001"' \
    '.[0].Config.Healthcheck.Test = ["CMD", "true"]' \
    '.[0].HostConfig.NetworkMode = "bridge"' \
    '.[0].HostConfig.Privileged = true' \
    '.[0].HostConfig.CapAdd += ["SYS_ADMIN"]' \
    '.[0].HostConfig.Tmpfs["/tmp"] = "rw"' \
    '.[0].Mounts[0].Source = "/foreign"' \
    '.[0].Mounts[0].RW = true' \
    '.[0].Mounts += [{Type:"bind",Source:"/foreign",Destination:"/foreign",RW:true}]' \
    '.[0].State.Restarting = true' \
    '.[0].State.OOMKilled = true'; do
    fixture running
    mutate "${mutation}"
    assertGateFails
    runService 15 stop
    assertNoWrite
done

fixture running
printf 'changed\n' >>"${root}/data/net/wireguard/wireguard/wg-padm.conf"
assertGateFails
runService 15 stop
assertNoWrite
fixture running
chmod 0644 "${root}/data/net/wireguard/wireguard/wg-padm.conf"
assertGateFails
fixture running
MODE=health-fail
assertGateFails
fixture running
printf '%s\n%s\n' "${CID}" "${OTHER_CID}" >"${TEST_ROOT}/ids"
assertGateFails
fixture running
jq '.services["net-wireguard"].command = ["foreign"]' "${root}/compose.json" >"${TEST_ROOT}/changed.json"
mv -- "${TEST_ROOT}/changed.json" "${root}/compose.json"
runService 15 stop
assertNoWrite
fixture running
jq '.host_integrations = []' "${root}/deployment.json" >"${TEST_ROOT}/changed.json"
mv -- "${TEST_ROOT}/changed.json" "${root}/deployment.json"
runService 15 stop
assertNoWrite

for dependency in control control_sync; do
    fixture running
    if [[ "${dependency}" == control ]]; then
        jq '.control = {schema_version:1,role:"main",
          node_id:"33333333-3333-4333-8333-333333333333",
          listen:{interface:"wg-padm",address:"10.77.0.1",port:18080},
          peer:{id:"44444444-4444-4444-8444-444444444444",address:"10.77.0.2",
            enabled:false,expires_at:1,token_sha256:("a"*64)},revision:0,last_digest:null}
        ' "${TEST_ROOT}/base.json" >"${root}/config/spec.json"
    else
        jq '.control_sync = {schema_version:1,role:"controlled",
          controller_id:"33333333-3333-4333-8333-333333333333",
          node_id:"44444444-4444-4444-8444-444444444444",listener_ids:["entry-xray"],
          last_revision:null,last_digest:null,managed_accounts:[],
          connection:{listen:{interface:"wg-padm",address:"10.77.0.1",port:18443},peer_address:"10.77.0.2"}}
        ' "${TEST_ROOT}/base.json" >"${root}/config/spec.json"
    fi
    chmod 0600 "${root}/config/spec.json"
    render
    runService 15 stop
    grep -q '控制角色或控制同步依赖 WireGuard' "${LOG}"
    assertNoWrite
done

for MODE_EXPECTED in 'health-fail 14' 'start-fail 14' 'snapshot-missing 14' \
    'restarting 14' 'interrupt-int 130' 'interrupt-term 143'; do
    fixture exited
    read -r MODE expected <<<"${MODE_EXPECTED}"
    runService "${expected}" start
    grep -Fxq "start ${CID}" "${CALLS}"
    [[ "$(grep -Fxc "stop -t 30 ${CID}" "${CALLS}")" == 1 ]]
    [[ "$(jq -r '.[0].State.Status' "${TEST_ROOT}/inspect.json")" == exited ]]
    [[ -f "${TEST_ROOT}/inspect.json" && ! -e "${root}/data/net/wireguard/wireguard.state" ]]
done
for MODE_EXPECTED in 'owner-drift 14' 'id-drift 14' 'start-refused 14'; do
    fixture exited
    read -r MODE expected <<<"${MODE_EXPECTED}"
    runService "${expected}" start
    ! grep -q '^stop ' "${CALLS}"
done

for MODE_EXPECTED in 'stop-fail 14' 'stop-state-retained 15'; do
    fixture running
    read -r MODE expected <<<"${MODE_EXPECTED}"
    runService "${expected}" stop
    [[ -e "${root}/data/net/wireguard/wireguard.state" ]]
done
for selectedMode in link-present link-fail; do
    fixture exited
    MODE=${selectedMode}
    assertGateFails exited
done
fixture exited
printf 'stale\n' >"${root}/data/net/wireguard/wireguard.state"
assertGateFails exited
fixture exited
mutate '.[0].State.ExitCode = 1'
assertGateFails exited
[[ "$(dockerWireGuardContainer exited 0)" == "${CID}" ]]
checks=$((checks + 1))
mutate '.[0].State.OOMKilled = true'
if dockerWireGuardContainer exited 0 >"${LOG}" 2>&1; then
    fail '恢复审计放行了 OOM 异常容器'
fi
checks=$((checks + 1))
fixture exited
: >"${TEST_ROOT}/ids"
runService 0 start
grep -Fxq release-reuse "${CALLS}"
grep -Fxq apply-original-spec "${CALLS}"
grep -q '完整恢复所有服务' "${LOG}"
! grep -Eq '^(start|stop|rm) ' "${CALLS}"
runService 15 stop

# 缺失容器走完整事务时，信号清理必须能读到该子 shell 内的候选和切换状态。
for MODE_EXPECTED in 'apply-fail 14' 'apply-interrupt-int 130' 'apply-interrupt-term 143'; do
    fixture exited
    : >"${TEST_ROOT}/ids"
    read -r MODE expected <<<"${MODE_EXPECTED}"
    (
        dockerConfigureApply() {
            [[ "$#" == 1 && "$1" == "${root}/config/spec.json" ]] || return 1
            DOCKER_CONFIG_CANDIDATE=${root}/.candidate.fixture
            DOCKER_CONFIG_SWITCHED=1
            case "${MODE}" in
            apply-interrupt-int) kill -INT "${BASHPID}" ;;
            apply-interrupt-term) kill -TERM "${BASHPID}" ;;
            esac
            return "${PADM_DOCKER_RC_COMPOSE}"
        }
        dockerRestoreConfiguration() {
            [[ "${DOCKER_CONFIG_SWITCHED}" == 1 &&
                "${DOCKER_CONFIG_CANDIDATE}" == "${root}/.candidate.fixture" ]] || return 1
            printf 'restore-service-transaction\n' >>"${CALLS}"
            DOCKER_CONFIG_SWITCHED=0
        }
        dockerCleanupConfigurationCandidate() {
            [[ "${DOCKER_CONFIG_SWITCHED}" == 0 &&
                "${DOCKER_CONFIG_CANDIDATE}" == "${root}/.candidate.fixture" ]] || return 1
            printf 'cleanup-service-transaction\n' >>"${CALLS}"
            DOCKER_CONFIG_CANDIDATE=
        }
        runService "${expected}" start
        grep -Fxq restore-service-transaction "${CALLS}"
        grep -Fxq cleanup-service-transaction "${CALLS}"
        ! grep -Eq '^(start|stop|rm) ' "${CALLS}"
    )
    checks=$((checks + 1))
done
printf 'wireguard-management: %s checks passed\n' "${checks}"
