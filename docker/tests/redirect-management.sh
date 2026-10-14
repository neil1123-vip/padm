#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-redirect-management.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "redirect-management-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]]
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_SKIP_CHOWN=0
export PADM_DOCKER_HEALTH_TIMEOUT=1 PADM_DOCKER_LOCK_TIMEOUT=1 PYTHONDONTWRITEBYTECODE=1
root=${PADM_DOCKER_INSTALL_DIR}
LOG=${TEST_ROOT}/command.log
MODE=ok
BUNDLE_PATH=${TEST_ROOT}/bundle
UUID=11111111-1111-4111-8111-111111111111
fail() { cat "${LOG}" >&2; printf 'redirect-management-fail: %s\n' "$*" >&2; exit 1; }
# 仅替代容器和发布边界；候选、字段冻结、备份及失败恢复走生产事务。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { :; }
dockerLockInstalledDeployment() { dockerAcquireDeploymentLock; }
dockerConfigureReleasePrepare() { :; }
dockerConfigureReleaseValidate() { dockerBundleSupportsSpec "$(dockerCurrentBundlePath)" "$1"; }
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
dockerCurrentBundlePath() { printf '%s\n' "${BUNDLE_PATH}"; }
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
    [[ -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]]
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
mkdir -p "${TEST_ROOT}/old-bundle/docker/contracts"
jq 'del(."x-padm-redirect")' "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json" \
    >"${TEST_ROOT}/old-bundle/docker/contracts/configure.schema.json"
cp -- "${TEST_ROOT}/bundle/docker/contracts/features.json" \
    "${TEST_ROOT}/old-bundle/docker/contracts/features.json"
cp -- "${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}" "${TEST_ROOT}/old-bundle/"
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
    cd "${PADM_DOCKER_INSTALL_DIR}"
    find config data secrets -type f -printf '%p %m %U %G %n\n' | LC_ALL=C sort
    find config data secrets -type f -print0 | sort -z | xargs -0 -r sha256sum
    for path in compose.json deployment.json deployment.previous.json images.env; do
        [[ ! -f "${path}" ]] || sha256sum "${path}"
    done
)
assertClean() {
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]]
    [[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 \( -name '.candidate.*' -o -name '.edit.*' -o -name '.protocol.*' \) -print -quit)" ]]
}
runEdit() {
    local expected=$1 actual=0
    shift
    (dockerMain edit "$@") >"${LOG}" 2>&1 || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "edit $*: expected ${expected}, actual ${actual}"
    assertClean
}
runStatus() {
    local enabled=$1 port=$2 family=${3:-ipv4} outputUid=${4:-null}
    (dockerMain protocol redirect-status) >"${LOG}" 2>&1 || fail 'status failed'
    jq -e --argjson enabled "${enabled}" --argjson port "${port}" \
      --arg family "${family}" --argjson uid "${outputUid}" '
      .enabled == $enabled and .port == $port and .family == $family and
      .hook == "PREROUTING" and (.output_uid // null) == $uid and
      (if $uid == null then (.hooks // ["PREROUTING"]) == ["PREROUTING"]
       else .hooks == ["PREROUTING","OUTPUT"] end)
    ' "${LOG}" >/dev/null || fail 'status does not match the selected Redirect scope'
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
runStatus false null
runEdit 15 --redirect-off --preview
runEdit 15 --redirect-settings 31298 --preview
for port in 0 65536 031298 invalid; do
    runEdit 2 --redirect-enable "${port}" --preview
done
runEdit 2 --redirect-enable 31298 --redirect-off --preview
runEdit 2 --redirect-enable 31298 --dns-off --preview
runEdit 2 --redirect-enable 31298 --tproxy-enable 31299 129 --preview
runEdit 2 --redirect-family dual --tproxy-enable 31299 129 --preview
runEdit 2 --tproxy-family dual --redirect-enable 31298 --preview
runEdit 2 --redirect-enable 31298 --tproxy-output-uid 65534 --preview
runEdit 2 --tproxy-output-uid 65534 --redirect-enable 31298 --preview
runEdit 2 --redirect-enable 31298 --tun-enable --preview
runEdit 2 --redirect-enable 31298 --spec "${TEST_ROOT}/base.json" --preview
runEdit 2 --redirect-enable 31298 --redirect-family invalid --preview
runEdit 2 --redirect-family dual --preview
runEdit 2 --redirect-off --redirect-family dual --preview
for uid in 0 10001 -1 2147483648 065534 invalid; do
    runEdit 2 --redirect-enable 31298 --redirect-output-uid "${uid}" --preview
done
runEdit 2 --redirect-output-uid 65534 --preview
runEdit 2 --redirect-enable 31298 --redirect-output-off --preview
runEdit 2 --redirect-settings 31298 --redirect-output-off --redirect-output-uid 65534 --preview
runEdit 15 --redirect-enable 35441 --preview
runEdit 15 --redirect-enable 10085 --preview
runEdit 0 --redirect-enable 31298 --preview
runEdit 2 --redirect-enable 31298 --confirm wrong
[[ "$(snapshot)" == "${before}" ]] || fail 'preview, cancellation or invalid input changed live state'
# 没有新标记的旧包仍兼容普通规格，但不能安装或复用 Redirect 规格。
dockerBundleSupportsSpec "${TEST_ROOT}/old-bundle" "${TEST_ROOT}/base.json" ||
    fail 'old bundle rejected ordinary specification'
BUNDLE_PATH=${TEST_ROOT}/old-bundle
runEdit "${PADM_DOCKER_RC_MANIFEST}" --redirect-enable 31298 --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail 'old bundle rejection changed live state'
BUNDLE_PATH=${TEST_ROOT}/bundle
runEdit 0 --redirect-enable 31298 --confirm PADM-DOCKER-EDIT
runStatus true 31298
! dockerBundleSupportsSpec "${TEST_ROOT}/old-bundle" "${root}/config/spec.json" ||
    fail 'old bundle accepted a Redirect compatibility or recovery specification'
BUNDLE_PATH=${TEST_ROOT}/old-bundle
before=$(snapshot)
runEdit "${PADM_DOCKER_RC_MANIFEST}" --redirect-settings 31299 --preview
[[ "$(snapshot)" == "${before}" ]] || fail 'old bundle reuse rejection changed live state'
BUNDLE_PATH=${TEST_ROOT}/bundle
jq -e '.services.xray.network_mode == "host" and .services.xray.user == "0:0" and
  .services.xray.ports == null and
  .services["net-transparent"].command == ["redirect","31298"]' "${root}/compose.json" >/dev/null
jq -e 'any(.inbounds[]; .tag == "redirect-in" and .port == 31298 and
  .settings.followRedirect == true and .settings.network == "tcp" and
  .streamSettings.sockopt.tproxy == "redirect")' "${root}/config/xray/config.json" >/dev/null
before=$(snapshot)
runEdit 15 --redirect-enable 31299 --preview
runEdit 15 --redirect-settings 31298 --preview
runEdit 0 --redirect-settings 31299 --redirect-family dual --redirect-output-uid 65534 --preview
[[ "$(snapshot)" == "${before}" ]] || fail 'settings preview changed live state'
runEdit 0 --redirect-settings 31299 --redirect-family dual --redirect-output-uid 65534 \
    --confirm PADM-DOCKER-EDIT
runStatus true 31299 dual 65534
jq -e '.services["net-transparent"].command == ["redirect","31299","dual","--output-uid","65534"] and
  .services["net-transparent"].healthcheck.test ==
    ["CMD","/usr/local/bin/padm-entrypoint","redirect-health","31299","dual","--output-uid","65534"]' \
    "${root}/compose.json" >/dev/null
grep -Fq "run --rm --no-deps --volume ${root}/data/net/transparent:/run/padm-redirect-owner:ro net-transparent preflight redirect 31299 dual --output-uid 65534 owned /run/padm-redirect-owner" \
    "${TEST_ROOT}/candidate-calls.log" || fail 'candidate preflight lost family or UID'
before=$(snapshot)
for MODE in health-fail interrupt-int interrupt-term; do
    rm -f -- "${TEST_ROOT}/failed-once"
    expected=14
    [[ "${MODE}" != interrupt-int ]] || expected=130
    [[ "${MODE}" != interrupt-term ]] || expected=143
    runEdit "${expected}" --redirect-settings 31300 --redirect-output-uid 65535 --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail "${MODE}: incomplete transaction recovery"
done
MODE=ok
cp -- "${root}/config/spec.json" "${TEST_ROOT}/enabled.json"
# Redirect 专项只允许改其字段，不能借普通规格导入或专项参数改账号。
runEdit 15 --spec "${TEST_ROOT}/base.json" --confirm PADM-DOCKER-EDIT
jq '.host_integrations[0].settings.port = 31300' "${TEST_ROOT}/enabled.json" >"${TEST_ROOT}/changed.json"
runEdit 15 --spec "${TEST_ROOT}/changed.json" --confirm PADM-DOCKER-EDIT
(
    tproxyAction=settings tproxyKind=redirect
    jq '.core.protocols[0].uuid = "22222222-2222-4222-8222-222222222222"' \
        "${TEST_ROOT}/enabled.json" >"${TEST_ROOT}/tampered.json"
    ! dockerEditCompatibilityValidate "${TEST_ROOT}/enabled.json" "${TEST_ROOT}/tampered.json"
)
runEdit 0 --redirect-settings 31300 --confirm PADM-DOCKER-EDIT
runStatus true 31300 dual 65534
runEdit 0 --redirect-settings 31300 --redirect-output-off --confirm PADM-DOCKER-EDIT
runStatus true 31300 dual
runEdit 15 --redirect-settings 31300 --redirect-output-off --preview
before=$(snapshot)
runEdit 0 --redirect-off --preview
[[ "$(snapshot)" == "${before}" ]] || fail 'off preview changed live state'
MODE=health-fail
rm -f -- "${TEST_ROOT}/failed-once"
runEdit 14 --redirect-off --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail 'off failure did not restore Redirect'
MODE=ok
runEdit 0 --redirect-off --confirm PADM-DOCKER-EDIT
runStatus false null
jq -en --slurpfile expected "${TEST_ROOT}/base.json" --slurpfile actual "${root}/config/spec.json" \
    '$expected == $actual' >/dev/null
jq -e '.accounts["11111111-1111-4111-8111-111111111111"].upload == 17 and
  .accounts["11111111-1111-4111-8111-111111111111"].download == 19' "${root}/data/traffic/state.json" >/dev/null
jq -e '.services["net-transparent"] == null and .services.xray.network_mode == null and
  .services.xray.ports == ["0.0.0.0:35441:35441/tcp"]' "${root}/compose.json" >/dev/null
jq -e 'all(.inbounds[]; .tag != "redirect-in")' "${root}/config/xray/config.json" >/dev/null
printf 'docker-redirect-management-ok\n'
