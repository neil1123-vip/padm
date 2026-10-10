#!/usr/bin/env bash
set -uo pipefail
umask 077

[[ "$#" -ge 2 && "$(id -u)" == 0 && -f /.dockerenv ]] || exit 2
NODE_ROOT=$(cd -- "$1" && pwd -P) || exit 2
shift
[[ "${PADM_DOCKER_INSTALL_DIR:-}" == "${NODE_ROOT}/deployment" &&
    "${PADM_DOCKER_BIN_DIR:-}" == "${NODE_ROOT}/bin" &&
    "${DOCKER_HOST:-}" == "unix://${NODE_ROOT}/docker.sock" &&
    "${PADM_DOCKER_SKIP_CHOWN:-0}" == 0 &&
    -L "${NODE_ROOT}/bin/padm-docker" ]] || exit 2

# 本地播种数据没有发布签名；仅替换输入准备，生产校验仍核对镜像、版本和 bundle 能力。
# shellcheck source=/dev/null
source "${NODE_ROOT}/bin/padm-docker" || exit 2
TEST_STAGE=command
dockerConfigureReleasePrepare() {
    local root
    TEST_STAGE=release-inputs
    root=$(dockerInstallRoot) || return 1
    jq -e '.release.signature_identity == "local-test-only-not-release-verified"' \
        "${root}/config/spec.json" >/dev/null || return 1
    dockerConfigureReleaseReuseInstalled || return $?
    TEST_STAGE=prepared
}

dockerManifestImageReference() {
    local root
    [[ "$#" == 1 && "$1" == ops && -n "${DOCKER_CONFIG_RELEASE_INPUTS:-}" ]] || return 1
    root=$(dockerInstallRoot) || return 1
    jq -er --argjson trusted "${DOCKER_CONFIG_RELEASE_INPUTS}" '
      select(.release == $trusted.release and .images == $trusted.images) |
      .images.ops | select(type == "string" and length > 0)
    ' "${root}/config/spec.json"
}

printf 'fail2ban_scope=local-test-only-not-release-verified\n'
dockerMain "$@"
STATUS=$?
printf 'fail2ban_deployment_stage=%s rc=%s\n' "${TEST_STAGE}" "${STATUS}" >&2
exit "${STATUS}"
