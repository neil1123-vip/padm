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
(dockerMain protocol tun-diagnose) >"${LOG}" 2>&1 || fail 'disabled diagnosis failed'
jq -e '.enabled == false and .runtime == "not_applicable" and
  .ping_group_allowed == null and .socket_probe == "not_tested"' "${LOG}" >/dev/null
assertClean
[[ "$(snapshot)" == "${before}" && ! -s "${CALLS}" ]] ||
    fail 'disabled diagnosis touched live state'
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
(
    diagnosticBefore=$(snapshot)
    CID=$(printf 'a%.0s' {1..64})
    DIAG_MODE=ok
    dockerTunContainer() {
        [[ "$*" == 'running metadata' ]] || return 1
        if [[ "${DIAG_MODE}" == missing ]]; then
            printf 'fixture core metadata drift\n' >&2
            return 1
        fi
        printf '%s\n' "${CID}"
    }
    docker() {
        if [[ "$#" -eq 5 && "$1" == container && "$2" == inspect &&
            "$3" == --format && "$4" == '{{.State.StartedAt}}' && "$5" == "${CID}" ]]; then
            if [[ "${DIAG_MODE}" == start-fail ]]; then
                printf 'fixture container inspect denied\n' >&2
                return 1
            fi
            if [[ "${DIAG_MODE}" == restarted &&
                -e "${TEST_ROOT}/diagnostic-started-once" ]]; then
                printf '2026-10-26T00:00:01Z\n'
            else
                : >"${TEST_ROOT}/diagnostic-started-once"
                printf '2026-10-26T00:00:00Z\n'
            fi
            return
        fi
        [[ "$#" -eq 7 && "$1" == exec && "$2" == --env && "$3" == LD_PRELOAD= &&
            "$4" == "${CID}" && "$5" == sh && "$6" == -ec ]] || return 1
        if [[ "${DIAG_MODE}" == ok ]]; then
            # 直接执行生产采样脚本中的识别函数，避免固定元数据桩掩盖加载器差异。
            recognitionScript=${7%%$'\n      core='*}
            [[ "${recognitionScript}" != "$7" ]] || fail 'missing core process matcher'
            checkCoreProcess() {
                local expected=$1 executable=$2 actual=0
                shift 2
                printf '%s\0' "$@" |
                    sh -ec "${recognitionScript}"$'\ncore_process "$1"' sh "${executable}" || actual=$?
                [[ "${actual}" == "${expected}" ]] ||
                    fail "core process matcher: ${executable}, expected ${expected}, actual ${actual}"
            }
            checkCoreProcess 0 /usr/local/bin/sing-box /usr/local/bin/sing-box run -c /dev/stdin
            checkCoreProcess 1 /usr/local/bin/sing-box /usr/local/bin/sing-box check -c /dev/stdin
            for architecture in x86_64 aarch64; do
                loader=ld-linux-aarch64.so.1
                [[ "${architecture}" != x86_64 ]] || loader=ld-linux-x86-64.so.2
                prefix=("${loader}" --argv0 /usr/local/bin/sing-box --preload
                    "/lib/libgcompat.so.0 /usr/local/lib/libcronet.so" -- /usr/local/bin/sing-box)
                checkCoreProcess 0 "/lib/ld-musl-${architecture}.so.1" "${prefix[@]}" run -c /dev/stdin
                checkCoreProcess 1 "/lib/ld-musl-${architecture}.so.1" "${prefix[@]}" check -c /dev/stdin
                checkCoreProcess 1 "/lib/ld-musl-${architecture}.so.1" "${loader}" \
                    --argv0 /usr/local/bin/sing-box --preload /lib/libgcompat.so.0 \
                    /usr/local/lib/libcronet.so -- /usr/local/bin/sing-box run -c /dev/stdin
                prefix[1]=--unexpected
                checkCoreProcess 1 "/lib/ld-musl-${architecture}.so.1" "${prefix[@]}" run -c /dev/stdin
            done
            checkCoreProcess 1 /lib/ld-musl-unknown.so.1 /usr/local/bin/sing-box run
        fi
        if [[ "${DIAG_MODE}" == unreadable ]]; then
            printf 'fixture proc access denied\n' >&2
            return 1
        fi
        printf 'Pid: 42\nUid: 0 10001 0 0\nGid: 0 10001 0 0\nGroups: 7 10001\n'
        printf 'CapEff: %s\nCapBnd: 0000000000001402\nNoNewPrivs: 1\nSeccomp: 2\n' \
            "$(if [[ "${DIAG_MODE}" == raw ]]; then printf 0000000000003402; else printf 0000000000001402; fi)"
        printf 'StartTime: 1234\nNetNS: net:[42]\n'
        if [[ "${DIAG_MODE}" == denied ]]; then
            printf 'PingGroupRange: 8 8\n'
        elif [[ "${DIAG_MODE}" == malformed ]]; then
            printf 'PingGroupRange: invalid\n'
        else
            printf 'PingGroupRange: 7 7\n'
        fi
    }
    for DIAG_MODE in ok denied raw missing unreadable malformed start-fail restarted; do
        rm -f -- "${TEST_ROOT}/diagnostic-started-once"
        (dockerMain protocol tun-diagnose) >"${LOG}" 2>&1 ||
            fail "${DIAG_MODE}: diagnosis failed"
        if [[ "${DIAG_MODE}" == missing || "${DIAG_MODE}" == unreadable ||
            "${DIAG_MODE}" == malformed || "${DIAG_MODE}" == start-fail ||
            "${DIAG_MODE}" == restarted ]]; then
            jq -e '.enabled and .runtime == "unknown" and
              .ping_group_allowed == null and .net_raw_effective == null and
              (.detail | length > 0)' "${LOG}" >/dev/null
            [[ "${DIAG_MODE}" != missing ]] ||
                grep -q 'fixture core metadata drift' "${LOG}"
            [[ "${DIAG_MODE}" != unreadable ]] ||
                grep -q 'fixture proc access denied' "${LOG}"
            [[ "${DIAG_MODE}" != start-fail ]] ||
                grep -q 'fixture container inspect denied' "${LOG}"
            [[ "${DIAG_MODE}" != restarted ]] ||
                jq -e '.reason == "core_changed_during_diagnosis"' "${LOG}" >/dev/null
        else
            jq -e --arg mode "${DIAG_MODE}" '
              .enabled and .runtime == "observed" and .uid == 10001 and .gid == 10001 and
              .groups == [7,10001] and .ping_group_allowed == ($mode != "denied") and
              .net_raw_effective == ($mode == "raw") and .capture == "not_verified" and
              .socket_probe == "not_tested" and .echo_roundtrip == "not_tested"
            ' "${LOG}" >/dev/null
        fi
        assertClean
        [[ "$(snapshot)" == "${diagnosticBefore}" ]] ||
            fail "${DIAG_MODE}: diagnosis changed live state"
    done
    if (dockerMain protocol tun-diagnose unexpected) >"${LOG}" 2>&1; then
        fail 'diagnosis accepted an unexpected argument'
    fi
)
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
checkUpdateCandidate() (
    # 候选生成也用于只读评估，必须重生成 TUN 权限且不能改动在线编排。
    candidateBefore=$(snapshot)
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
    for path in config.json users.base; do
        cmp -s -- "${root}/config/sing-box/${path}" \
            "${DOCKER_CONFIG_CANDIDATE}/config/sing-box/${path}" ||
            fail "update candidate changed core configuration: ${path}"
    done
    [[ "${legacy}" == "$(sha256sum "${root}/compose.json")" ]]
    dockerCleanupConfigurationCandidate
    cp -- "${TEST_ROOT}/current-compose.json" "${root}/compose.json"
    [[ "$(snapshot)" == "${candidateBefore}" ]] || fail 'update assessment changed live state'
)
checkUpdateCandidate
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
# 旧 TUN 模板没有 rules 字段，仍须允许诊断与关闭，且不能借兼容放行其他漂移。
for path in config.json users.base; do
    jq -e '.route.rules == [
      {inbound:["tun-in"],network:"icmp",action:"route",outbound:"direct"}
    ]' "${root}/config/sing-box/${path}" >/dev/null
    jq 'del(.route.rules)' "${root}/config/sing-box/${path}" >"${TEST_ROOT}/legacy-tun.json"
    cp -- "${TEST_ROOT}/legacy-tun.json" "${root}/config/sing-box/${path}"
done
before=$(snapshot)
: >"${CALLS}"
runStatus true
(
    dockerTunContainer() { printf 'fixture core unavailable\n' >&2; return 1; }
    dockerMain protocol tun-diagnose
) >"${LOG}" 2>&1 || fail 'legacy TUN diagnosis failed'
jq -e '.enabled and .policy == "policy_dependent" and .runtime == "unknown"' "${LOG}" >/dev/null
assertClean
(
    cp -- "${root}/config/sing-box/config.json" "${TEST_ROOT}/legacy-config.json"
    jq '.log.level = "debug"' "${TEST_ROOT}/legacy-config.json" >"${TEST_ROOT}/legacy-drift.json"
    cp -- "${TEST_ROOT}/legacy-drift.json" "${root}/config/sing-box/config.json"
    runEdit 15 --tun-off --preview
    cp -- "${TEST_ROOT}/legacy-config.json" "${root}/config/sing-box/config.json"
)
[[ "$(snapshot)" == "${before}" && ! -s "${CALLS}" ]] ||
    fail 'legacy TUN read-only checks changed live state'
checkUpdateCandidate
MODE=health-fail
rm -f -- "${TEST_ROOT}/failed-once"
runEdit 14 --spec "${TEST_ROOT}/enabled.json" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail 'regeneration failure did not restore legacy TUN'
MODE=ok
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/enabled.json" '' '' configure
    for path in config.json users.base; do
        jq -e '.route.rules == [
          {inbound:["tun-in"],network:"icmp",action:"route",outbound:"direct"}
        ]' "${root}/config/sing-box/${path}" >/dev/null
    done
    # 成功重生成后再走生产恢复，确认旧快照不会被新模板悄悄改写。
    DOCKER_CONFIG_SWITCHED=1
    dockerRestoreConfiguration
) >"${LOG}" 2>&1 || fail 'legacy TUN regeneration/restore failed'
assertClean
[[ "$(snapshot)" == "${before}" ]] || fail 'restore did not preserve legacy TUN snapshot'
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
