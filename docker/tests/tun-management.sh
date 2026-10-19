#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-tun-management.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "tun-management-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]]
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_SKIP_CHOWN=0
export PADM_DOCKER_HEALTH_TIMEOUT=1 PADM_DOCKER_LOCK_TIMEOUT=1 PYTHONDONTWRITEBYTECODE=1
root=${PADM_DOCKER_INSTALL_DIR}
LOG=${TEST_ROOT}/command.log
CALLS=${TEST_ROOT}/calls.log
MODE=ok
TARGET_MODE=ok
UUID=11111111-1111-4111-8111-111111111111
fail() { cat "${LOG}" >&2; printf 'tun-management-fail: %s\n' "$*" >&2; exit 1; }
# 只替换宿主和容器边界；输入、候选、备份及恢复沿生产编辑事务。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
TUN_DISABLE_PREPARE=$(declare -f dockerTunDisablePrepare)
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { :; }
dockerLockInstalledDeployment() { dockerAcquireDeploymentLock; }
dockerConfigureReleasePrepare() { :; }
dockerConfigureReleaseValidate() { :; }
dockerRealityTargetsValidate() {
    printf '%s\n' "$1" >>"${TEST_ROOT}/target-calls.log"
    [[ "${TARGET_MODE}" == ok ]]
}
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
dockerTunDisablePrepare() { printf 'tun-stop\n' >>"${CALLS}"; }
dockerTunStartPrepare() { printf 'tun-capture\n' >>"${CALLS}"; }
dockerTunStartVerify() { printf 'tun-bind\n' >>"${CALLS}"; }
dockerTunContainer() { :; }
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
   core:{type:"sing-box",secondary_type:null,protocols:[{id:1,core:"sing-box",listener_id:"entry-singbox",
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
    local enabled=$1
    (dockerMain protocol tun-status) >"${LOG}" 2>&1 || fail 'status failed'
    jq -e --argjson enabled "${enabled}" '
      . == {enabled:$enabled,interface:(if $enabled then "padm-tun" else null end),
        address:(if $enabled then "198.18.0.1/30" else null end),
        family:"ipv4",scope:"global",ipv6:"reject"}
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
: >"${CALLS}"
runStatus false
runEdit 15 --tun-off --preview
runEdit 2 --tun-enable --tun-off --preview
runEdit 2 --tun-enable --dns-off --preview
runEdit 2 --tun-enable --spec "${TEST_ROOT}/base.json" --preview
runEdit 2 --tun-enable unexpected --preview
TARGET_MODE=fail
targetCalls=$(wc -l <"${TEST_ROOT}/target-calls.log")
runEdit 15 --tun-enable --preview
[[ "$(wc -l <"${TEST_ROOT}/target-calls.log")" == "$((targetCalls + 1))" ]]
TARGET_MODE=ok
runEdit 0 --tun-enable --preview
[[ "$(snapshot)" == "${before}" && ! -s "${CALLS}" ]] ||
    fail 'preview or invalid input stopped services or changed state'
for MODE in health-fail interrupt-int interrupt-term; do
    rm -f -- "${TEST_ROOT}/failed-once"
    expected=14
    [[ "${MODE}" != interrupt-int ]] || expected=130
    [[ "${MODE}" != interrupt-term ]] || expected=143
    runEdit "${expected}" --tun-enable --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail "${MODE}: enable recovery changed live state"
done
MODE=ok
runEdit 0 --tun-enable --confirm PADM-DOCKER-EDIT
cp -- "${root}/config/spec.json" "${TEST_ROOT}/enabled.json"
runStatus true
jq -e '.services["sing-box"].network_mode == "host" and .services["sing-box"].user == "0:0" and
  .services["sing-box"].cap_add == ["NET_ADMIN","NET_BIND_SERVICE","DAC_OVERRIDE"] and .services["sing-box"].ports == null and
  .services["sing-box"].restart == "no" and
  .services["net-tun-check"].network_mode == "host" and
  any(.services["net-tun-check"].volumes[];
    .target == "/var/lib/padm/net" and .source == "${PADM_NET_ROOT}/data/net/transparent" and .read_only == false)
' "${root}/compose.json" >/dev/null
jq -e '[.inbounds[] | select(.tag == "tun-in")] == [{
  type:"tun",tag:"tun-in",interface_name:"padm-tun",address:["198.18.0.1/30"],
  dns_mode:"disabled",auto_route:true,auto_redirect:true,strict_route:true,stack:"system"}]
' "${root}/config/sing-box/config.json" >/dev/null
(
    # 候选生成也用于只读评估，必须重生成 TUN 权限且不能改动在线编排。
    PADM_DOCKER_MANIFEST_FILE="${TEST_ROOT}/update-manifest.json"
    jq --arg commit "$(printf b%.0s {1..40})" '
      {release:{version:.release.version,commit:$commit},
       images:(.images | with_entries(.value={
         reference:.value,index_digest:(.value | split("@")[1])}))}
    ' "${root}/config/spec.json" >"${PADM_DOCKER_MANIFEST_FILE}"
    PADM_DOCKER_MANIFEST_SHA256=$(sha256sum "${PADM_DOCKER_MANIFEST_FILE}" | cut -d ' ' -f 1)
    PADM_DOCKER_MANIFEST_SIGNATURE_IDENTITY=fixture
    cp -- "${root}/compose.json" "${TEST_ROOT}/current-compose.json"
    jq '.services["sing-box"].cap_add=["NET_ADMIN","DAC_OVERRIDE"]' \
        "${TEST_ROOT}/current-compose.json" >"${root}/compose.json"
    legacy=$(sha256sum "${root}/compose.json")
    dockerCreateUpdateCandidate
    jq -e '.services["sing-box"].cap_add == ["NET_ADMIN","NET_BIND_SERVICE","DAC_OVERRIDE"]' \
        "${DOCKER_CONFIG_CANDIDATE}/compose.json" >/dev/null
    [[ "${legacy}" == "$(sha256sum "${root}/compose.json")" ]]
    dockerCleanupConfigurationCandidate
    cp -- "${TEST_ROOT}/current-compose.json" "${root}/compose.json"
)
# 支持范围只保留单 sing-box、单 IPv4 Reality；合同直接命中生产规格校验。
for mutation in '.core.type="xray" | .core.protocols[0].core="xray"' \
    '.core.protocols[0].address_families=["ipv4","ipv6"]' \
    '.core.secondary_type="xray"' \
    '.core.protocols += [(.core.protocols[0] | .listener_id="entry-second" | .public_port=35442)]'; do
    jq "${mutation}" "${TEST_ROOT}/enabled.json" >"${TEST_ROOT}/unsupported.json"
    ! dockerConfigureSpecValidate "${TEST_ROOT}/unsupported.json" ||
        fail "accepted unsupported TUN scope: ${mutation}"
done
(
    PADM_DOCKER_LIFECYCLE_LOADED=0
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/docker/lib/lifecycle.sh"
    LIFECYCLE_MODE=ok
    dockerTunDisablePrepare() {
        printf 'stop\n' >>"${CALLS}"
        [[ "${LIFECYCLE_MODE}" != stop-fail ]]
    }
    dockerTunStartPrepare() {
        printf 'capture\n' >>"${CALLS}"
        [[ "${LIFECYCLE_MODE}" != capture-fail ]]
    }
    dockerTunStartVerify() {
        printf 'bind\n' >>"${CALLS}"
        [[ "${LIFECYCLE_MODE}" != bind-fail ]]
    }
    dockerTunStartAbort() { printf 'abort\n' >>"${CALLS}"; }
    dockerComposeExecute() {
        printf 'compose %s\n' "$*" >>"${CALLS}"
        [[ "${LIFECYCLE_MODE}" != up-fail ]]
    }
    checkLifecycle() {
        local expected=$1
        shift
        : >"${CALLS}"
        dockerComposeRun "$@"
        [[ "$(cat "${CALLS}")" == "${expected}" ]] || fail "unexpected TUN lifecycle order: $*"
    }
    restart=$(printf 'stop\ncapture\ncompose up -d --wait --wait-timeout 1\nbind')
    checkLifecycle "${restart}" restart
    checkLifecycle "${restart}" up
    checkLifecycle "$(printf 'stop\ncompose down')" down
    checkLifecycle 'compose up -d --no-deps acme' up -d --no-deps acme
    LIFECYCLE_MODE=stop-fail
    : >"${CALLS}"
    ! dockerComposeRun restart || fail 'restart ignored failed TUN stop'
    [[ "$(cat "${CALLS}")" == stop ]] || fail 'Compose ran after failed TUN stop'
    for LIFECYCLE_MODE in capture-fail bind-fail up-fail; do
        : >"${CALLS}"
        ! dockerComposeRun restart || fail "restart ignored ${LIFECYCLE_MODE}"
        case "${LIFECYCLE_MODE}" in
        capture-fail) expected=$(printf 'stop\ncapture') ;;
        bind-fail) expected=${restart} ;;
        up-fail) expected=$(printf 'stop\ncapture\ncompose up -d --wait --wait-timeout 1\nabort') ;;
        esac
        [[ "$(cat "${CALLS}")" == "${expected}" ]] || fail "${LIFECYCLE_MODE}: wrong TUN lifecycle recovery"
    done
)
before=$(snapshot)
: >"${CALLS}"
runEdit 15 --tun-enable --preview
TARGET_MODE=fail
targetCalls=$(wc -l <"${TEST_ROOT}/target-calls.log")
runEdit 0 --tun-off --preview
[[ "$(snapshot)" == "${before}" && ! -s "${CALLS}" ]] || fail 'off preview stopped TUN or changed state'
# 专项豁免只允许 TUN 项增删；普通规格导入不能关闭，UUID 也不能借此改动。
runEdit 15 --spec "${TEST_ROOT}/base.json" --confirm PADM-DOCKER-EDIT
(
    tunAction=off
    jq '.host_integrations=[] | .core.protocols[0].uuid="22222222-2222-4222-8222-222222222222"' \
        "${TEST_ROOT}/enabled.json" >"${TEST_ROOT}/tampered.json"
    ! dockerEditCompatibilityValidate "${TEST_ROOT}/enabled.json" "${TEST_ROOT}/tampered.json"
)
(
    dockerConfigureReleaseValidate() {
        if [[ "${FUNCNAME[1]:-}" == dockerConfigureApply ]]; then
            jq '.core.protocols[0].uuid = "22222222-2222-4222-8222-222222222222"' "$1" \
                >"${TEST_ROOT}/apply-drift.json"
            cp -- "${TEST_ROOT}/apply-drift.json" "$1"
        fi
    }
    runEdit 15 --tun-off --confirm PADM-DOCKER-EDIT
)
[[ "$(snapshot)" == "${before}" && ! -s "${CALLS}" ]] ||
    fail 'TUN off with account drift changed live state'
for MODE in health-fail interrupt-int interrupt-term; do
    rm -f -- "${TEST_ROOT}/failed-once"
    expected=14
    [[ "${MODE}" != interrupt-int ]] || expected=130
    [[ "${MODE}" != interrupt-term ]] || expected=143
    runEdit "${expected}" --tun-off --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail "${MODE}: off recovery did not restore TUN"
done
MODE=ok
runEdit 0 --tun-off --confirm PADM-DOCKER-EDIT
[[ "$(wc -l <"${TEST_ROOT}/target-calls.log")" == "${targetCalls}" ]] ||
    fail 'TUN off probed unchanged Reality target'
TARGET_MODE=ok
runStatus false
runEdit 15 --tun-off --preview
jq -en --slurpfile expected "${TEST_ROOT}/base.json" --slurpfile actual "${root}/config/spec.json" \
    '$expected == $actual' >/dev/null
jq -e '.accounts["11111111-1111-4111-8111-111111111111"].upload == 17 and
  .accounts["11111111-1111-4111-8111-111111111111"].download == 19' "${root}/data/traffic/state.json" >/dev/null
jq -e '.services["net-tun-check"] == null and .services["sing-box"].network_mode == null and
  .services["sing-box"].restart == "unless-stopped" and
  .services["sing-box"].ports == ["0.0.0.0:35441:35441/tcp"]' "${root}/compose.json" >/dev/null
jq -e 'all(.inbounds[]; .tag != "tun-in")' "${root}/config/sing-box/config.json" >/dev/null
(
    # 服务边界沿生产门禁；只替换容器信息及内核 helper 调用。
    eval "${TUN_DISABLE_PREPARE}"
    SERVICE_ROOT=${TEST_ROOT}/service-state
    mkdir -p "${SERVICE_ROOT}/config" "${SERVICE_ROOT}/data/net/transparent"
    cp -- "${TEST_ROOT}/enabled.json" "${SERVICE_ROOT}/config/spec.json"
    cp -- "${TEST_ROOT}/enabled.json" "${SERVICE_ROOT}/deployment.json"
    printf '{"services":{"net-tun-check":{}}}\n' >"${SERVICE_ROOT}/compose.json"
    : >"${SERVICE_ROOT}/data/net/transparent/tun.state"
    CID=$(printf 'a%.0s' {1..64})
    TOKEN=$(printf 'b%.0s' {1..32})
    STARTED=2026-10-14T03:00:00.000000000Z
    CONTAINER_IDS=
    INSPECT_STARTED=${STARTED}
    SERVICE_MODE=ok
    dockerInstallRoot() { printf '%s\n' "${SERVICE_ROOT}"; }
    dockerTrafficSafePath() { :; }
    dockerTunConfigurationCheck() { :; }
    dockerCurrentOwnsHostIntegration() { [[ "$1" == tun ]]; }
    dockerTunContainer() {
        [[ "${SERVICE_MODE}" != metadata-fail && "${SERVICE_MODE}" != running-fail ]] || return 1
        printf '%s\n' "${CID}"
    }
    docker() {
        case "$1" in
        ps) [[ "${SERVICE_MODE}" != ps-fail ]] && printf '%s\n' "${CONTAINER_IDS}" ;;
        container)
            if [[ "${3:-}" == --format ]]; then
                printf '%s\n' "${INSPECT_STARTED}"
            else
                jq -cn --arg started "${STARTED}" '[{State:{Running:false,StartedAt:$started}}]'
            fi ;;
        rm) printf 'rm %s\n' "$2" >>"${CALLS}" ;;
        *) return 1 ;;
        esac
    }
    dockerComposeExecute() {
        printf '%s\n' "$*" >>"${CALLS}"
        [[ "${SERVICE_MODE}" != abort-fail ]]
    }
    dockerCandidateCompose() { printf 'candidate %s\n' "$*" >>"${CALLS}"; }
    for SERVICE_MODE in ok ps-fail; do
        CONTAINER_IDS=${CID}
        DOCKER_TUN_START_TOKEN=${TOKEN}
        : >"${CALLS}"
        ! dockerTunStartAbort || fail 'intent abort accepted a remaining core or failed inventory'
        [[ "${DOCKER_TUN_START_TOKEN}" == "${TOKEN}" && ! -s "${CALLS}" ]] ||
            fail 'rejected intent abort changed ownership'
    done
    SERVICE_MODE=ok
    CONTAINER_IDS=
    DOCKER_TUN_START_TOKEN=${TOKEN}
    : >"${CALLS}"
    dockerTunStartAbort
    [[ -z "${DOCKER_TUN_START_TOKEN}" &&
        "$(cat "${CALLS}")" == "run --rm --no-deps net-tun-check tun-resources abort ${TOKEN}" ]] ||
        fail 'clean intent abort did not clear the token'
    CONTAINER_IDS=${CID}
    for SERVICE_MODE in ok abort-fail metadata-fail started-drift; do
        DOCKER_TUN_START_TOKEN=${TOKEN}
        INSPECT_STARTED=${STARTED}
        [[ "${SERVICE_MODE}" != started-drift ]] || INSPECT_STARTED=2026-10-14T03:00:01Z
        : >"${CALLS}"
        if [[ "${SERVICE_MODE}" == ok ]]; then
            dockerTunDisablePrepare "${TEST_ROOT}/base.json" restore || {
                cat "${CALLS}" >&2
                fail 'failed start restore unexpectedly rejected a matching exited core'
            }
            [[ -z "${DOCKER_TUN_START_TOKEN}" &&
                "$(cat "${CALLS}")" == "$(printf 'run --rm --no-deps net-tun-check tun-resources abort %s\nrm %s' "${TOKEN}" "${CID}")" ]] ||
                fail 'failed start restore did not abort before removing its core'
        else
            ! dockerTunDisablePrepare "${TEST_ROOT}/base.json" restore ||
                fail "failed start restore accepted ${SERVICE_MODE}"
            [[ "${DOCKER_TUN_START_TOKEN}" == "${TOKEN}" ]] &&
                ! grep -q '^rm ' "${CALLS}" || fail 'rejected restore removed the core or token'
        fi
    done
    SERVICE_MODE=ok
    INSPECT_STARTED=${STARTED}
    DOCKER_TUN_START_TOKEN=
    : >"${CALLS}"
    dockerTunDisablePrepare "${TEST_ROOT}/base.json"
    [[ "$(cat "${CALLS}")" == "$(printf 'run --rm --no-deps net-tun-check tun-resources clean %s %s\nrm %s' "${CID}" "${STARTED}" "${CID}")" ]] ||
        fail 'ordinary exited core cleanup bypassed ownership clean'
    SERVICE_MODE=running-fail
    : >"${CALLS}"
    ! dockerValidateHostIntegrations "${TEST_ROOT}/enabled.json" "${TEST_ROOT}/candidate" ||
        fail 'candidate accepted owned state without a running core audit'
    [[ ! -s "${CALLS}" ]] || fail 'candidate preflight ran after failed ownership audit'
    SERVICE_MODE=ok
    dockerValidateHostIntegrations "${TEST_ROOT}/enabled.json" "${TEST_ROOT}/candidate"
    [[ "$(cat "${CALLS}")" == "candidate ${TEST_ROOT}/candidate run --rm --no-deps --volume ${SERVICE_ROOT}/data/net/transparent:/var/lib/padm/net:ro net-tun-check tun-resources preflight" ]] ||
        fail 'candidate did not audit the existing owner state read-only'
)
printf 'docker-tun-management-ok\n'
