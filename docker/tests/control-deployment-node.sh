#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ "$#" -eq 1 && "$(id -u)" == 0 && -f /.dockerenv ]] || exit 2
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
NODE_ROOT=$(cd -- "$1" && pwd -P)
[[ "${PADM_DOCKER_INSTALL_DIR:-}" == "${NODE_ROOT}/deployment" &&
    "${PADM_DOCKER_BIN_DIR:-}" == "${NODE_ROOT}/bin" &&
    "${DOCKER_HOST:-}" == "unix://${NODE_ROOT}/docker.sock" &&
    "${PADM_DOCKER_SKIP_CHOWN:-0}" == 0 &&
    -f "${NODE_ROOT}/spec.json" && ! -L "${NODE_ROOT}/spec.json" &&
    -d "${NODE_ROOT}/secrets" && ! -L "${NODE_ROOT}/secrets" &&
    -z "$(find "${NODE_ROOT}/secrets" -type l -print -quit)" &&
    ! -e "${PADM_DOCKER_INSTALL_DIR}" && ! -L "${PADM_DOCKER_INSTALL_DIR}" ]] || exit 2

exec 3>&1 4>&2
exec >"${NODE_ROOT}/seed-private.log" 2>&1
STAGE=load
SUCCESS=0

finish() {
    local status=$? cleanup=0
    trap - EXIT
    set +e
    if declare -F dockerCleanupConfigurationCandidate >/dev/null; then
        dockerCleanupConfigurationCandidate || cleanup=1
        dockerCleanupStagedBundle || cleanup=1
        dockerReleaseDeploymentLock || cleanup=1
    fi
    if [[ "${status}" == 0 && "${cleanup}" == 0 && "${SUCCESS}" == 1 ]]; then
        printf 'docker-control-deployment-node-ok\n' >&3
        printf 'seed_scope=local-test-only-not-release-verified\n' >&3
    else
        [[ "${status}" != 0 ]] || status=1
        printf 'docker-control-deployment-node-failed: stage=%s status=%s cleanup=%s\n' \
            "${STAGE}" "${status}" "${cleanup}" >&4
        printf 'private_diagnostic=%s/seed-private.log\n' "${NODE_ROOT}" >&4
    fi
    exit "${status}"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 初装仅播种本地验收数据，不绕过后续生产 CLI 的发布输入一致性校验。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
[[ -z "${DOCKER_CONFIG_RELEASE_INPUTS}" ]]
SPEC="${NODE_ROOT}/spec.json"
ROOT=$(dockerInstallRoot)
jq -e '.release.signature_identity == "local-test-only-not-release-verified"' "${SPEC}" >/dev/null

STAGE=preflight
dockerHostPreflight
dockerAssertInstallAllowed
dockerAcquireDeploymentLock
dockerInitializeStateRoot
dockerInstallBundle "${PROJECT_ROOT}"
dockerInstallCli
dockerRequireInstalledBundle
dockerConfigureSpecValidate "${SPEC}"
dockerTrafficRuntimeCheck "$(jq -r '[.core.type, .core.secondary_type] | .[] | select(. != null)' "${SPEC}")"

STAGE=inputs
cp -a -- "${NODE_ROOT}/secrets/." "${ROOT}/secrets/"
chmod 0700 "${ROOT}/secrets/net" "${ROOT}/secrets/net/wireguard"
chmod 0600 "${ROOT}/secrets/net/wireguard/wg-padm.conf"
dockerHostIntegrationInputsValidate "${SPEC}"
dockerConfigurePortsAvailable "${SPEC}"

STAGE=candidate
dockerCreateConfigurationCandidate
CANDIDATE=${DOCKER_CONFIG_CANDIDATE}
dockerGenerateCandidate "${SPEC}" "${CANDIDATE}"
dockerValidateCandidate "${CANDIDATE}/config/spec.json" "${CANDIDATE}"
dockerBackupConfiguration
STAGE=install
dockerInstallCandidate "${CANDIDATE}" "${DOCKER_CONFIG_BACKUP}"
dockerEnsureRuntimeDataPermissions
dockerComposeRun up -d --force-recreate --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}"
dockerTrafficScheduleInstall
dockerRenewalScheduleInstall
dockerGeoScheduleInstall
DOCKER_CONFIG_SWITCHED=0

STAGE=assert
dockerManagedSpecMatchesDeployment "${ROOT}/config/spec.json" "${ROOT}/deployment.json" "${ROOT}/images.env"
dockerControlStateCheck "${ROOT}"
[[ -L "${PADM_DOCKER_BIN_DIR}/padm-docker" &&
    "$(readlink "${PADM_DOCKER_BIN_DIR}/padm-docker")" == "${ROOT}/bundle/install-docker.sh" ]]
dockerCleanupConfigurationCandidate
dockerReleaseDeploymentLock
[[ ! -e "${ROOT}/locks/deployment.lock" &&
    -z "$(find "${ROOT}" -maxdepth 1 -name '.candidate.*' -print -quit)" ]]
SUCCESS=1
