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
    printf '%s\n' "$*" >>"${TEST_ROOT}/candidate-calls.log"
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
    local enabled=$1 port=$2 mark=$3 family=${4:-ipv4} outputUid=${5:-null} outputAll=${6:-false}
    (dockerMain protocol tproxy-status) >"${LOG}" 2>&1 || fail 'status failed'
    jq -e --argjson enabled "${enabled}" --argjson port "${port}" --argjson mark "${mark}" \
        --arg family "${family}" --argjson outputUid "${outputUid}" --argjson outputAll "${outputAll}" '
      . == ({enabled:$enabled,port:$port,mark:$mark,family:$family,hook:"PREROUTING"} +
        if $outputAll then {output_all:true,hooks:["PREROUTING","OUTPUT"],bypass_gid:10001}
        elif $outputUid == null then {} else {output_uid:$outputUid,hooks:["PREROUTING","OUTPUT"]} end)
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
for family in invalid IPv4 ''; do
    runEdit 2 --tproxy-enable 31298 129 --tproxy-family "${family}" --preview
done
runEdit 2 --tproxy-family dual --preview
runEdit 2 --tproxy-off --tproxy-family dual --preview
runEdit 2 --tproxy-enable 31298 129 --tproxy-family dual --tproxy-family ipv6 --preview
for uid in 0 10001 -1 2147483648 065534 invalid ''; do
    runEdit 2 --tproxy-enable 31298 129 --tproxy-output-uid "${uid}" --preview
done
runEdit 2 --tproxy-output-uid 65534 --preview
runEdit 2 --tproxy-off --tproxy-output-uid 65534 --preview
runEdit 2 --tproxy-enable 31298 129 --tproxy-output-off --preview
runEdit 2 --tproxy-enable 31298 129 --tproxy-output-uid 65534 --tproxy-output-uid 65535 --preview
runEdit 2 --tproxy-settings 31298 129 --tproxy-output-off --tproxy-output-uid 65534 --preview
runEdit 2 --tproxy-output-all --preview
runEdit 2 --tproxy-off --tproxy-output-all --preview
runEdit 2 --tproxy-enable 31298 129 --tproxy-output-all --tproxy-output-all --preview
runEdit 2 --tproxy-enable 31298 129 --tproxy-output-all --tproxy-output-uid 65534 --preview
runEdit 2 --tproxy-settings 31298 129 --tproxy-output-off --tproxy-output-all --preview
runEdit 2 --tproxy-enable 31298 129 --redirect-output-all --preview
runEdit 15 --tproxy-enable 35441 129 --preview
runEdit 15 --tproxy-enable 10085 129 --preview
runEdit 0 --tproxy-enable 31298 129 --preview
[[ "$(snapshot)" == "${before}" ]] || fail 'preview or invalid input changed live state'
runEdit 0 --tproxy-enable 31298 129 --confirm PADM-DOCKER-EDIT
cp -- "${root}/config/spec.json" "${TEST_ROOT}/owner-spec.json"
runStatus true 31298 129
jq -e '.services.xray.network_mode == "host" and .services.xray.user == "0:0" and
  .services.xray.cap_add == ["NET_ADMIN"] and .services.xray.ports == null and
  .services["net-transparent"].restart == "no" and
  .services["net-transparent"].command == ["tproxy","31298","129"]' "${root}/compose.json" >/dev/null
jq -e '.host_integrations[0].settings | has("family") | not' "${root}/config/spec.json" >/dev/null
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
# 三种地址族共用生成路径，旧 IPv4 输入及无 marker 的发布包继续兼容。
mkdir -- "${TEST_ROOT}/old-bundle" "${TEST_ROOT}/old-bundle/docker" "${TEST_ROOT}/old-bundle/docker/contracts"
jq 'del(."x-padm-tproxy-ipv6")' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${TEST_ROOT}/old-bundle/docker/contracts/configure.schema.json"
cp -- "${PROJECT_ROOT}/docker/contracts/features.json" "${TEST_ROOT}/old-bundle/docker/contracts/features.json"
for core in xray sing-box; do
    for family in ipv4 ipv6 dual; do
        jq --arg core "${core}" --arg family "${family}" '
          .core.type = $core | .core.protocols[0].core = $core |
          .host_integrations = [{type:"tproxy",profile:"net-transparent",firewall_rules:["padm-tproxy"],
            devices:[],schedules:[],settings:{port:31298,mark:129,family:$family}}]
        ' "${TEST_ROOT}/base.json" >"${TEST_ROOT}/family.json"
        dockerConfigureSpecValidate "${TEST_ROOT}/family.json" || fail "invalid ${core}/${family} spec"
        if [[ "${core}" == xray ]]; then
            dockerGenerateXrayConfig "${TEST_ROOT}/family.json" "${TEST_ROOT}/family.config.json"
            jq -e --arg family "${family}" 'any(.inbounds[]; .tag == "tproxy-in" and
              .listen == (if $family == "ipv4" then "0.0.0.0" else "::" end))' \
                "${TEST_ROOT}/family.config.json" >/dev/null
        else
            dockerGenerateSingBoxConfig "${TEST_ROOT}/family.json" "${TEST_ROOT}/family.config.json"
            jq -e --arg family "${family}" 'any(.inbounds[]; .tag == "tproxy-in" and
              .listen == (if $family == "ipv4" then "0.0.0.0" else "::" end))' \
                "${TEST_ROOT}/family.config.json" >/dev/null
        fi
        dockerGenerateDeployment "${TEST_ROOT}/family.json" "${TEST_ROOT}/family.deployment.json"
        jq -e --arg family "${family}" 'all(.listeners[] | select(.listener_id | startswith("host-tproxy-"));
          .address_families == (if $family == "dual" then ["ipv4","ipv6"] else [$family] end))' \
            "${TEST_ROOT}/family.deployment.json" >/dev/null
        if [[ "${family}" == ipv4 ]]; then
            dockerBundleSupportsSpec "${TEST_ROOT}/old-bundle" "${TEST_ROOT}/family.json" ||
                fail 'old IPv4 bundle rejected'
        else
            ! dockerBundleSupportsSpec "${TEST_ROOT}/old-bundle" "${TEST_ROOT}/family.json" ||
                fail 'old bundle accepted IPv6 TProxy'
        fi
    done
done
runEdit 0 --tproxy-family dual --tproxy-enable 31298 129 --confirm PADM-DOCKER-EDIT
runStatus true 31298 129 dual
jq -e '.services["net-transparent"].command == ["tproxy","31298","129","dual"] and
  .services["net-transparent"].healthcheck.test ==
    ["CMD","/usr/local/bin/padm-entrypoint","tproxy-health","31298","129","dual"]' "${root}/compose.json" >/dev/null
grep -Fq 'net-transparent preflight tproxy 31298 129 dual unowned' "${TEST_ROOT}/candidate-calls.log" ||
    fail 'dual preflight family missing'
runEdit 0 --tproxy-settings 31299 131 --confirm PADM-DOCKER-EDIT
runStatus true 31299 131 dual
runEdit 0 --tproxy-settings 31299 131 --tproxy-family ipv6 --confirm PADM-DOCKER-EDIT
runStatus true 31299 131 ipv6
runEdit 0 --tproxy-off --confirm PADM-DOCKER-EDIT
# 指定 UID 的 OUTPUT 沿同一事务，缺省旧规格/状态/编排不追加新字段。
runEdit 0 --tproxy-enable 31298 129 --tproxy-family dual --tproxy-output-uid 65534 --preview
before=$(snapshot)
runEdit 0 --tproxy-enable 31298 129 --tproxy-family dual --tproxy-output-uid 65534 --confirm PADM-DOCKER-EDIT
runStatus true 31298 129 dual 65534
grep -Fq 'net-transparent preflight tproxy 31298 129 dual --output-uid 65534 unowned' \
    "${TEST_ROOT}/candidate-calls.log" || fail 'OUTPUT preflight UID missing'
jq -e '.services["net-transparent"].command == ["tproxy","31298","129","dual","--output-uid","65534"] and
  .services["net-transparent"].healthcheck.test ==
    ["CMD","/usr/local/bin/padm-entrypoint","tproxy-health","31298","129","dual","--output-uid","65534"]' \
    "${root}/compose.json" >/dev/null
! dockerBundleSupportsSpec "${TEST_ROOT}/old-bundle" "${root}/config/spec.json" ||
    fail 'old bundle accepted OUTPUT'
jq 'del(."x-padm-tproxy-output-uid")' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${TEST_ROOT}/old-bundle/docker/contracts/configure.schema.json"
! dockerBundleSupportsSpec "${TEST_ROOT}/old-bundle" "${root}/config/spec.json" ||
    fail 'IPv6 bundle without OUTPUT marker accepted OUTPUT'
before=$(snapshot)
runEdit 15 --tproxy-settings 31298 129 --tproxy-output-uid 65534 --preview
runEdit 0 --tproxy-settings 31298 129 --tproxy-output-uid 65535 --preview
[[ "$(snapshot)" == "${before}" ]] || fail 'OUTPUT preview changed live state'
for MODE in health-fail interrupt-int interrupt-term; do
    rm -f -- "${TEST_ROOT}/failed-once"
    expected=14
    [[ "${MODE}" != interrupt-int ]] || expected=130
    [[ "${MODE}" != interrupt-term ]] || expected=143
    runEdit "${expected}" --tproxy-settings 31298 129 --tproxy-output-uid 65535 --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail "${MODE}: OUTPUT recovery changed state"
done
MODE=ok
runEdit 0 --tproxy-settings 31299 131 --confirm PADM-DOCKER-EDIT
runStatus true 31299 131 dual 65534
runEdit 0 --tproxy-settings 31299 131 --tproxy-output-off --confirm PADM-DOCKER-EDIT
runStatus true 31299 131 dual
jq -e '.host_integrations[0].settings | has("output_uid") | not' "${root}/config/spec.json" >/dev/null
runEdit 15 --tproxy-settings 31299 131 --tproxy-output-off --preview
runEdit 0 --tproxy-settings 31299 131 --tproxy-output-all --preview
runEdit 0 --tproxy-settings 31299 131 --tproxy-output-all --confirm PADM-DOCKER-EDIT
runStatus true 31299 131 dual null true
jq -e '.host_integrations[0].settings.output_all == true and
  (.host_integrations[0].settings | has("output_uid") | not)' "${root}/config/spec.json" >/dev/null
jq -e '.services.xray.user == "0:10001" and
  .services["net-transparent"].command == ["tproxy","31299","131","dual","--output-all"] and
  .services["net-transparent"].healthcheck.test ==
    ["CMD","/usr/local/bin/padm-entrypoint","tproxy-health","31299","131","dual","--output-all"]' \
    "${root}/compose.json" >/dev/null
grep -Fq 'net-transparent preflight tproxy 31299 131 dual --output-all owned' \
    "${TEST_ROOT}/candidate-calls.log" || fail 'global OUTPUT preflight missing'
jq 'del(."x-padm-transparent-output-all")' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${TEST_ROOT}/old-bundle/docker/contracts/configure.schema.json"
! dockerBundleSupportsSpec "${TEST_ROOT}/old-bundle" "${root}/config/spec.json" ||
    fail 'old bundle accepted global OUTPUT'
runEdit 15 --tproxy-settings 31299 131 --tproxy-output-all --preview
before=$(snapshot)
for MODE in health-fail interrupt-int interrupt-term; do
    rm -f -- "${TEST_ROOT}/failed-once"
    expected=14
    [[ "${MODE}" != interrupt-int ]] || expected=130
    [[ "${MODE}" != interrupt-term ]] || expected=143
    runEdit "${expected}" --tproxy-settings 31299 131 --tproxy-output-uid 65534 --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail "${MODE}: global OUTPUT recovery changed state"
done
MODE=ok
runEdit 0 --tproxy-settings 31300 132 --confirm PADM-DOCKER-EDIT
runStatus true 31300 132 dual null true
runEdit 0 --tproxy-settings 31300 132 --tproxy-output-uid 65534 --confirm PADM-DOCKER-EDIT
runStatus true 31300 132 dual 65534
dockerBundleSupportsSpec "${TEST_ROOT}/old-bundle" "${root}/config/spec.json" ||
    fail 'bundle without global OUTPUT marker rejected UID'
jq -e '.services.xray.user == "0:0"' "${root}/compose.json" >/dev/null
runEdit 0 --tproxy-settings 31300 132 --tproxy-output-all --confirm PADM-DOCKER-EDIT
runEdit 0 --tproxy-settings 31300 132 --tproxy-output-off --confirm PADM-DOCKER-EDIT
runStatus true 31300 132 dual
jq -e '.host_integrations[0].settings | has("output_all") or has("output_uid") | not' \
    "${root}/config/spec.json" >/dev/null
runEdit 0 --tproxy-off --confirm PADM-DOCKER-EDIT
# 实际管理事务之外，核对停止证明会拒绝归属漂移及不完整撤销。
runEdit 0 --tproxy-enable 31298 129 --confirm PADM-DOCKER-EDIT
(
    CID=$(printf 'b%.0s' {1..64})
    OTHER_CID=$(printf 'c%.0s' {1..64})
    OWNER_MODE=ok
    OWNER_LOG=${TEST_ROOT}/owner.log
    OWNER_JSON=${TEST_ROOT}/owner.json
    OWNER_KIND=tproxy
    CLEANUP_COMMAND='run --rm --no-deps net-transparent preflight tproxy 31298 129 unowned'
    writeOwnerBase() {
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
    }
    writeOwnerBase
    resetOwner() {
        cp -- "${TEST_ROOT}/owner-base.json" "${OWNER_JSON}"
        printf '%s\n' fixture >"${root}/data/net/transparent/${OWNER_KIND}.state"
        : >"${OWNER_LOG}"
    }
    docker() {
        case "$1" in
        ps)
            if [[ "$2" == -q ]]; then
                printf '%s\n' "${CORE_CID}"
                return
            fi
            [[ "${OWNER_MODE}" != absent ]] || return 0
            [[ "${OWNER_MODE}" != duplicate ]] || printf '%s\n' "${OTHER_CID}"
            jq -r '.[0].Id' "${OWNER_JSON}"
            ;;
        container)
            if [[ "$3" == "${CORE_CID:-}" ]]; then cat "${CORE_JSON}"
            else cat "${OWNER_JSON}"; fi
            ;;
        exec)
            if [[ "$2" == "${CORE_CID:-}" ]]; then
                [[ "$3" == sh && "$4" == -ec && "$#" == 7 ]]
                # 只替换 proc 根目录，身份列和唯一进程判定执行生产传入的脚本。
                local script=${5//\/proc\//"${CORE_PROC}/"}
                sh -ec "${script}" sh "$7"
            else
                [[ "${OWNER_MODE}" != health-fail ]]
            fi
            ;;
        stop)
            printf 'stop %s\n' "$2" >>"${OWNER_LOG}"
            [[ "${OWNER_MODE}" != stop-fail ]] || return 1
            jq --arg mode "${OWNER_MODE}" --arg other "${OTHER_CID}" '
              .[0].State.Running=false | .[0].State.Status="exited" |
              if $mode=="bad-exit" then .[0].State.ExitCode=137
              elif $mode=="cid-drift" then .[0].Id=$other else . end
            ' "${OWNER_JSON}" >"${OWNER_JSON}.next"
            mv -- "${OWNER_JSON}.next" "${OWNER_JSON}"
            [[ "${OWNER_MODE}" == keep-state ]] || rm -f -- "${root}/data/net/transparent/${OWNER_KIND}.state"
            ;;
        rm)
            printf 'rm %s\n' "$2" >>"${OWNER_LOG}"
            [[ "$2" == "${CID}" ]]
            ;;
        *) fail "unexpected owner command: $*" ;;
        esac
    }
    dockerComposeExecute() {
        [[ "$*" == "${CLEANUP_COMMAND}" ]] ||
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
    (
        for path in config/spec.json deployment.json compose.json; do
            cp -p -- "${root}/${path}" "${TEST_ROOT}/restart-${path##*/}"
        done
        trap 'for path in config/spec.json deployment.json compose.json; do cp -p -- "${TEST_ROOT}/restart-${path##*/}" "${root}/${path}"; done' EXIT
        for OWNER_KIND in tproxy redirect; do
            jq --arg kind "${OWNER_KIND}" '
              .host_integrations[0].type=$kind |
              .host_integrations[0].firewall_rules=["padm-"+$kind] |
              if $kind == "redirect" then del(.host_integrations[0].settings.mark) else . end
            ' "${TEST_ROOT}/owner-spec.json" >"${root}/config/spec.json"
            dockerGenerateDeployment "${root}/config/spec.json" "${root}/deployment.json"
            dockerGenerateCompose "${root}/config/spec.json" /dev/stdout "${root}" |
                jq '.services["net-transparent"].restart="unless-stopped"' >"${root}/compose.json"
            ! dockerTProxyConfigurationCheck || fail "${OWNER_KIND}: accepted legacy startup policy"
            dockerTProxyConfigurationCheck owner || fail "${OWNER_KIND}: rejected legacy cleanup policy"
            writeOwnerBase
            CLEANUP_COMMAND="run --rm --no-deps net-transparent preflight ${OWNER_KIND} 31298"
            [[ "${OWNER_KIND}" != tproxy ]] || CLEANUP_COMMAND+=" 129"
            CLEANUP_COMMAND+=" unowned"
            for policy in unless-stopped no always; do
                resetOwner
                jq --arg policy "${policy}" '.[0].HostConfig.RestartPolicy.Name=$policy' \
                    "${OWNER_JSON}" >"${OWNER_JSON}.next"
                mv -- "${OWNER_JSON}.next" "${OWNER_JSON}"
                ! dockerTProxyContainer || fail "${OWNER_KIND}: legacy container passed current audit"
                if [[ "${policy}" == always ]]; then
                    ! dockerTProxyDisablePrepare "${root}/config/spec.json" ||
                        fail "${OWNER_KIND}: accepted foreign restart policy"
                    [[ ! -s "${OWNER_LOG}" ]] || fail 'restart drift stopped a foreign owner'
                else
                    dockerTProxyDisablePrepare "${root}/config/spec.json"
                    [[ "$(cat "${OWNER_LOG}")" == "$(printf 'stop %s\nclean\nrm %s' "${CID}" "${CID}")" ]] ||
                        fail "${OWNER_KIND}: legacy cleanup order changed"
                fi
            done
            rm -f -- "${root}/data/net/transparent/${OWNER_KIND}.state"
            jq '.services["net-transparent"].command[1]="31399"' \
                "${root}/compose.json" >"${root}/compose.json.next"
            mv -- "${root}/compose.json.next" "${root}/compose.json"
            ! dockerTProxyConfigurationCheck owner || fail "${OWNER_KIND}: legacy mode ignored command drift"
        done
    )
    writeOwnerBase
    cp -- "${TEST_ROOT}/base.json" "${root}/config/spec.json"
    ! dockerTProxyDisablePrepare "${TEST_ROOT}/base.json" || fail 'accepted contradictory disabled spec'
    cp -- "${TEST_ROOT}/owner-spec.json" "${root}/config/spec.json"
    (
        for path in config/spec.json deployment.json compose.json; do
            cp -p -- "${root}/${path}" "${TEST_ROOT}/global-${path##*/}"
        done
        trap 'for path in config/spec.json deployment.json compose.json; do cp -p -- "${TEST_ROOT}/global-${path##*/}" "${root}/${path}"; done' EXIT
        CORE_CID=$(printf 'd%.0s' {1..64})
        CORE_JSON=${TEST_ROOT}/core-owner.json
        CORE_PROC=${TEST_ROOT}/core-proc
        for OWNER_KIND in tproxy redirect; do
            core=xray
            [[ "${OWNER_KIND}" != redirect ]] || core=sing-box
            jq --arg core "${core}" --arg kind "${OWNER_KIND}" '
              .core.type=$core | .core.protocols[0].core=$core |
              .host_integrations[0].type=$kind |
              .host_integrations[0].firewall_rules=["padm-"+$kind] |
              .host_integrations[0].settings.output_all=true |
              if $kind == "redirect" then del(.host_integrations[0].settings.mark) else . end
            ' "${TEST_ROOT}/owner-spec.json" >"${root}/config/spec.json"
            dockerGenerateCompose "${root}/config/spec.json" "${root}/compose.json" "${root}"
            dockerGenerateDeployment "${root}/config/spec.json" "${root}/deployment.json"
            writeOwnerBase
            jq -n --arg root "${root}" --arg cid "${CORE_CID}" --arg core "${core}" \
                --slurpfile spec "${root}/config/spec.json" --slurpfile compose "${root}/compose.json" '
              $compose[0].services[$core] as $s |
              [{Id:$cid,State:{Running:true,Restarting:false,Paused:false},
                Config:{User:"0:10001",Image:$spec[0].images[$core],
                  Entrypoint:["/usr/local/bin/"+$core],
                  Cmd:(if $core == "xray" then ["run","-confdir","/etc/padm/xray"]
                    else ["run","-D","/var/lib/padm/sing-box","-c","/etc/padm/sing-box/config.json"] end),
                  Labels:($s.labels + {
                    "com.docker.compose.project.working_dir":$root,
                    "com.docker.compose.project.config_files":($root+"/compose.json")})},
                HostConfig:{NetworkMode:"host"}}]
            ' >"${TEST_ROOT}/core-owner-base.json"
            command=$(jq -r '.services["net-transparent"].command | join(" ")' "${root}/compose.json")
            CLEANUP_COMMAND="run --rm --no-deps net-transparent preflight ${command} unowned"
            for drift in none config-user runtime-uid runtime-gid duplicate missing; do
                resetOwner
                cp -- "${TEST_ROOT}/core-owner-base.json" "${CORE_JSON}"
                rm -rf -- "${CORE_PROC}"
                mkdir -p "${CORE_PROC}/123"
                printf 'Name:\t%s\nUid:\t0\t0\t0\t0\nGid:\t10001\t10001\t10001\t10001\n' \
                    "${core}" >"${CORE_PROC}/123/status"
                case "${drift}" in
                config-user)
                    jq '.[0].Config.User="0:0"' "${CORE_JSON}" >"${CORE_JSON}.next"
                    mv -- "${CORE_JSON}.next" "${CORE_JSON}"
                    ;;
                runtime-uid) sed -i 's/^Uid:.*/Uid: 0 1 0 0/' "${CORE_PROC}/123/status" ;;
                runtime-gid) sed -i 's/^Gid:.*/Gid: 10001 0 10001 10001/' "${CORE_PROC}/123/status" ;;
                duplicate) mkdir "${CORE_PROC}/124"; cp "${CORE_PROC}/123/status" "${CORE_PROC}/124/status" ;;
                missing) sed -i 's/^Name:.*/Name: other/' "${CORE_PROC}/123/status" ;;
                esac
                if [[ "${drift}" == none ]]; then
                    [[ "$(dockerTProxyContainer)" == "${CID}" ]] || fail "${OWNER_KIND}: rejected global owner"
                    dockerTProxyDisablePrepare <(printf '{"host_integrations":[]}')
                    [[ "$(cat "${OWNER_LOG}")" == "$(printf 'stop %s\nclean\nrm %s' "${CID}" "${CID}")" ]] ||
                        fail "${OWNER_KIND}: global owner stop order changed"
                else
                    ! dockerTProxyDisablePrepare <(printf '{"host_integrations":[]}') ||
                        fail "${OWNER_KIND}: accepted global core ${drift}"
                    [[ ! -s "${OWNER_LOG}" &&
                        -e "${root}/data/net/transparent/${OWNER_KIND}.state" ]] ||
                        fail "${OWNER_KIND}: core drift modified owner"
                fi
            done
            rm -f -- "${root}/data/net/transparent/${OWNER_KIND}.state"
        done
    )
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
    (
        cp -p -- "${root}/compose.json" "${TEST_ROOT}/lifecycle-compose.json"
        trap 'cp -p -- "${TEST_ROOT}/lifecycle-compose.json" "${root}/compose.json"' EXIT
        jq '.services["net-transparent"].restart="unless-stopped"' \
            "${root}/compose.json" >"${root}/compose.json.next"
        mv -- "${root}/compose.json.next" "${root}/compose.json"
        for operation in up restart; do
            : >"${LIFECYCLE_LOG}"
            ! dockerComposeRun "${operation}" || fail "${operation} accepted legacy restart policy"
            [[ ! -s "${LIFECYCLE_LOG}" ]] || fail 'legacy startup stopped the existing owner'
        done
        checkLifecycle 'compose up -d --no-deps acme' up -d --no-deps acme
        checkLifecycle "$(printf 'prepare\ncompose down')" down
    )
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
