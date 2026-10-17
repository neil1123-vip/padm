#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d /root/padm-wireguard-migration.XXXXXX)
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "wireguard-migration-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]]
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PYTHONDONTWRITEBYTECODE=1
LOG=${TEST_ROOT}/output.log
CALLS=${TEST_ROOT}/calls.log
MODE=ok
checks=0
# 运行生产候选、备份、安装和恢复；仅替换无关业务验证与 Docker 边界。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
for helper in dockerControlRecoveryCheck dockerConfigureSpecValidate dockerAcmeWebrootTransitionValidate \
    dockerControlSyncTransitionValidate dockerControlSyncScheduleSpecCheck dockerControlTransitionValidate \
    dockerRealityStreamDeploymentCheck dockerTrafficRuntimeCheck dockerTrafficBeforeChange \
    dockerConfigureReleaseValidate dockerRealityTargetsValidate dockerConfigurePortsAvailable \
    dockerValidateCandidate dockerFail2banSourceInputsPrepare dockerControlAccessLogEnsure \
    dockerEnsureRuntimeDataPermissions dockerTrafficScheduleInstall dockerRenewalScheduleInstall \
    dockerGeoScheduleInstall dockerControlLogScheduleInstall dockerControlSyncScheduleInstall \
    dockerValidateConfigurationBackup dockerSiteTreeValidate dockerControlStateCheck \
    dockerTProxyDisablePrepare dockerTunDisablePrepare dockerFail2banDisablePrepare \
    dockerControlFail2banDisablePrepare dockerSshFail2banDisablePrepare dockerTunTransitionPrepare \
    dockerRealityStreamTransitionPrepare dockerFail2banSourceInputsCheck dockerControlRestorePrepare \
    dockerTrafficPrepareCandidate; do
    eval "${helper}() { :; }"
done
dockerGenerateCandidate() {
    local source=$1 candidate=$2
    cp -- "${source}" "${candidate}/config/spec.json"
    printf '%s\n' '{}' >"${candidate}/compose.json"
    printf '%s\n' '{}' >"${candidate}/deployment.json"
    : >"${candidate}/images.runtime.env"
    dockerStageHostIntegrationFiles "${source}" "${candidate}"
}
dockerWireGuardContainer() {
    printf 'audit-%s\n' "$1" >>"${CALLS}"
    [[ "${MODE}" != owner-drift || "$1" != running ]] || return 1
    if [[ "${MODE}" == runtime-drift ]] &&
        cmp -s -- "${root}/secrets/net/wireguard/identity.json" "${input}/identity.json"; then
        return 1
    fi
    printf '%064d\n' 1
}
docker() {
    if [[ "$1" == ps ]]; then
        printf '%064d\n' 1
        return 0
    fi
    [[ "$1" != run ]] || return 0
    [[ "$1" == stop && "$2" == -t && "$3" == 30 && "$4" == "$(printf '%064d' 1)" ]] || return 1
    printf 'stop\n' >>"${CALLS}"
}
dockerComposeExecute() {
    [[ "$1" == down ]] || return 1
    printf 'down\n' >>"${CALLS}"
}
dockerComposeRun() {
    [[ "$1" == up ]] || return 1
    printf 'up\n' >>"${CALLS}"
    if cmp -s -- "${root}/secrets/net/wireguard/identity.json" "${input}/identity.json"; then
        case "${MODE}" in
        fail-up) return 1 ;;
        INT|TERM) kill -"${MODE}" "${BASHPID}"; return 1 ;;
        directory-drift)
            mv -- "${root}/secrets/net/wireguard" "${root}/foreign-original"
            mkdir -m 0700 -- "${root}/secrets/net/wireguard"
            cp -- "${input}/"* "${root}/secrets/net/wireguard/"
            return 1
            ;;
        runtime-drift) return 1 ;;
        esac
    fi
}
dockerWireGuardMigrate() (
    trap 'status=$?; trap - EXIT INT TERM; dockerConfigurationInterrupted; exit "${status}"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    dockerConfigureApply "${root}/config/spec.json" '' '' configure '' '' '' '' '' "${input}"
)
fixture() {
    root=$(mktemp -d "${TEST_ROOT}/case.XXXXXX")
    export PADM_DOCKER_INSTALL_DIR=${root}
    mkdir -m 0700 -- "${root}/config" "${root}/secrets" "${root}/data" "${root}/backups"
    mkdir -m 0700 -- "${root}/secrets/net" "${root}/data/traffic"
    input=$(mktemp -d "${root}/.wireguard.XXXXXX")/wireguard
    printf '%s\n' '{"schema_version":3,"core":{"type":"xray","secondary_type":null,"protocols":[]},
        "tls":null,"images":{"net":"fixture"},"host_integrations":[{"type":"wireguard"}]}' >"${root}/config/spec.json"
    printf '%s\n' '{}' >"${root}/deployment.json"
    printf '%s\n' '{}' >"${root}/compose.json"
    : >"${root}/images.env"
    printf '%s\n' '{"schema_version":1,"accounts":{}}' >"${root}/data/traffic/state.json"
    chmod 0600 "${root}/config/spec.json" "${root}/data/traffic/state.json"
    printf '%032d' 1 | base64 >"${root}/old-private"
    printf '%032d' 2 | base64 >"${root}/old-public"
    printf '%032d' 3 | base64 >"${root}/new-private"
    printf '%032d' 4 | base64 >"${root}/new-public"
    local file
    for file in "${root}/"*private "${root}/"*public; do chmod 0600 "${file}"; done
    python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" prepare \
        --directory "${root}/secrets/net/wireguard" --address 10.77.0.1 --listen-port 51820 \
        --private-key "${root}/old-private" --public-key "${root}/old-public" >/dev/null
    python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" peer \
        --directory "${root}/secrets/net/wireguard" --peer-address 10.77.0.2 \
        --peer-public-key "$(cat "${root}/new-public")" >/dev/null
    python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" prepare \
        --directory "${input}" --address 10.88.0.1 --listen-port 51821 \
        --private-key "${root}/new-private" --public-key "${root}/new-public" >/dev/null
    python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" peer \
        --directory "${input}" --peer-address 10.88.0.2 \
        --peer-public-key "$(cat "${root}/old-public")" --endpoint 192.0.2.1:51821 >/dev/null
    cp -a -- "${root}/secrets/net/wireguard" "${root}/expected"
    : >"${CALLS}"
    DOCKER_CONFIG_CANDIDATE=
    DOCKER_CONFIG_BACKUP=
    DOCKER_CONFIG_SWITCHED=0
    DOCKER_CONFIG_WIREGUARD_MIGRATION=0
    DOCKER_CONFIG_WIREGUARD_SOURCE=
    MODE=ok
}
assertOld() {
    diff -qr -- "${root}/expected" "${root}/secrets/net/wireguard"
    [[ "$(stat -c '%u:%a' "${root}/secrets/net/wireguard")" == 0:700 ]]
    jq -e '.accounts == {}' "${root}/data/traffic/state.json" >/dev/null
    checks=$((checks + 1))
}
runMigration() {
    local expected=$1 status=0
    dockerWireGuardMigrate >"${LOG}" 2>&1 || status=$?
    [[ "${status}" == "${expected}" ]] || { cat "${LOG}" >&2; return 1; }
    checks=$((checks + 1))
}

fixture
runMigration 0
diff -qr -- "${input}" "${root}/secrets/net/wireguard"
grep -qxF secrets/net/wireguard "${root}"/backups/configure.*/present
[[ "$(grep -c '^stop$' "${CALLS}")" == 1 ]]
checks=$((checks + 1))

for MODE_CASE in fail-up INT TERM; do
    fixture
    MODE=${MODE_CASE}
    expected=14
    [[ "${MODE}" != INT ]] || expected=130
    [[ "${MODE}" != TERM ]] || expected=143
    runMigration "${expected}"
    assertOld
    grep -qxF down "${CALLS}"
    grep -qxF secrets/net/wireguard "${root}"/backups/configure.*/present
done

fixture
MODE=owner-drift
runMigration 14
assertOld
! grep -qxF stop "${CALLS}"
checks=$((checks + 1))

fixture
MODE=directory-drift
runMigration 14
diff -qr -- "${input}" "${root}/secrets/net/wireguard"
! grep -qxF down "${CALLS}"
previous=$(find "${root}" -path '*/wireguard.previous/identity.json' -print)
[[ -n "${previous}" ]]
diff -qr -- "${root}/expected" "${previous%/identity.json}"
checks=$((checks + 1))

fixture
MODE=runtime-drift
runMigration 14
diff -qr -- "${input}" "${root}/secrets/net/wireguard"
! grep -qxF down "${CALLS}"
previous=$(find "${root}" -path '*/wireguard.previous/identity.json' -print)
[[ -n "${previous}" ]]
diff -qr -- "${root}/expected" "${previous%/identity.json}"
checks=$((checks + 1))

fixture
status=0
dockerConfigureApply "${root}/config/spec.json" '' '' configure '' '' '' '' '' "${input}" \
    >"${LOG}" 2>&1 || status=$?
[[ "${status}" == 15 && ! -s "${CALLS}" ]]
checks=$((checks + 1))
DOCKER_WIREGUARD_INPUT=${input} dockerConfigureApply "${root}/config/spec.json" >"${LOG}" 2>&1
assertOld
! grep -qxF stop "${CALLS}"
! grep -qxF secrets/net/wireguard "${root}"/backups/configure.*/present
checks=$((checks + 1))

fixture
DOCKER_WIREGUARD_INPUT=${input} dockerBackupConfiguration
cp -- "${input}/"* "${root}/secrets/net/wireguard/"
DOCKER_CONFIG_SWITCHED=1
status=0
dockerRestoreConfiguration >"${LOG}" 2>&1 || status=$?
[[ "${status}" != 0 && ! -s "${CALLS}" ]]
diff -qr -- "${input}" "${root}/secrets/net/wireguard"
checks=$((checks + 1))

fixture
DOCKER_WIREGUARD_INPUT=${input} dockerBackupConfiguration
before=$(stat -c '%d:%i' "${root}/secrets/net/wireguard")
DOCKER_CONFIG_SWITCHED=1
dockerRestoreConfiguration >"${LOG}" 2>&1
assertOld
[[ "$(stat -c '%d:%i' "${root}/secrets/net/wireguard")" == "${before}" ]]
checks=$((checks + 1))

printf 'docker-wireguard-migration-regression-ok: %s checks\n' "${checks}"
