#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-phase2.XXXXXX")
LOCK_FILE="${PROJECT_ROOT}/versions.lock"
BAKE_FILE="${PROJECT_ROOT}/docker-bake.hcl"
COMPOSE_FILE="${PROJECT_ROOT}/docker/compose.yaml"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

fail() {
    printf 'docker-phase2-regression-fail: %s\n' "$*" >&2
    exit 1
}

for tool in jq grep find sort; do
    command -v "${tool}" >/dev/null 2>&1 || fail "missing tool: ${tool}"
done

[[ -f "${LOCK_FILE}" && ! -L "${LOCK_FILE}" ]] || fail 'versions.lock is missing or unsafe'
[[ -f "${BAKE_FILE}" && ! -L "${BAKE_FILE}" ]] || fail 'docker-bake.hcl is missing or unsafe'
[[ -f "${COMPOSE_FILE}" && ! -L "${COMPOSE_FILE}" ]] || fail 'compose.yaml is missing or unsafe'

invalidLockLine=$(grep -Env '^(#.*|[[:space:]]*|PADM_LOCK_[A-Z0-9_]+=[A-Za-z0-9._:/@,+-]+)$' "${LOCK_FILE}" || true)
[[ -z "${invalidLockLine}" ]] || fail "versions.lock contains unsafe syntax: ${invalidLockLine%%$'\n'*}"

set -a
# shellcheck disable=SC1090
. "${LOCK_FILE}"
set +a

requiredLockVariables=(
    PADM_LOCK_SCHEMA PADM_LOCK_PLATFORM_AMD64 PADM_LOCK_PLATFORM_ARM64
    PADM_LOCK_VERSION PADM_LOCK_SOURCE_URL PADM_LOCK_ALPINE_VERSION PADM_LOCK_ALPINE_BASE
    PADM_LOCK_CA_CERTIFICATES_VERSION PADM_LOCK_XRAY_VERSION PADM_LOCK_XRAY_AMD64_ASSET
    PADM_LOCK_XRAY_AMD64_SHA256 PADM_LOCK_XRAY_ARM64_ASSET PADM_LOCK_XRAY_ARM64_SHA256
    PADM_LOCK_UNZIP_VERSION PADM_LOCK_SING_BOX_VERSION PADM_LOCK_SING_BOX_AMD64_ASSET
    PADM_LOCK_SING_BOX_AMD64_SHA256 PADM_LOCK_SING_BOX_ARM64_ASSET PADM_LOCK_SING_BOX_ARM64_SHA256
    PADM_LOCK_NGINX_VERSION PADM_LOCK_NGINX_PACKAGE_VERSION PADM_LOCK_ACME_SH_VERSION
    PADM_LOCK_ACME_SH_URL PADM_LOCK_ACME_SH_SHA256 PADM_LOCK_PYTHON3_VERSION
    PADM_LOCK_OPENSSL_VERSION PADM_LOCK_SOCAT_VERSION PADM_LOCK_BASH_VERSION
    PADM_LOCK_IPROUTE2_VERSION PADM_LOCK_IPTABLES_VERSION PADM_LOCK_NFTABLES_VERSION
    PADM_LOCK_WIREGUARD_TOOLS_VERSION PADM_LOCK_FAIL2BAN_VERSION PADM_LOCK_PATCHES
)
for variableName in "${requiredLockVariables[@]}"; do
    [[ -n "${!variableName:-}" ]] || fail "missing lock variable: ${variableName}"
done

[[ "${PADM_LOCK_SCHEMA}" == 1 ]] || fail 'unsupported lock schema'
[[ "${PADM_LOCK_PLATFORM_AMD64}" == linux/amd64 ]] || fail 'amd64 platform drifted'
[[ "${PADM_LOCK_PLATFORM_ARM64}" == linux/arm64 ]] || fail 'arm64 platform drifted'
scriptVersion=$(sed -n 's/^SCRIPT_VERSION="\([^"]*\)"/\1/p' "${PROJECT_ROOT}/shell/core/version.sh")
[[ -n "${scriptVersion}" && "${PADM_LOCK_VERSION}" == "${scriptVersion}" ]] || fail 'padm version drifted from versions.lock'
[[ "${PADM_LOCK_ALPINE_BASE}" =~ ^alpine:[0-9]+[.][0-9]+[.][0-9]+@sha256:[0-9a-f]{64}$ ]] ||
    fail 'Alpine base is not pinned by tag and digest'
for variableName in \
    PADM_LOCK_XRAY_AMD64_SHA256 PADM_LOCK_XRAY_ARM64_SHA256 \
    PADM_LOCK_SING_BOX_AMD64_SHA256 PADM_LOCK_SING_BOX_ARM64_SHA256 \
    PADM_LOCK_ACME_SH_SHA256; do
    [[ "${!variableName}" =~ ^[0-9a-f]{64}$ ]] || fail "invalid checksum: ${variableName}"
done
[[ "${PADM_LOCK_PATCHES}" == none ]] || fail 'patch lock must name every applied patch or be none'

mapfile -t imageNames < <(find "${PROJECT_ROOT}/docker/images" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
[[ "${imageNames[*]}" == 'net nginx ops sing-box xray' ]] || fail "unexpected image set: ${imageNames[*]}"

for imageName in "${imageNames[@]}"; do
    dockerfile="${PROJECT_ROOT}/docker/images/${imageName}/Dockerfile"
    [[ -f "${dockerfile}" && ! -L "${dockerfile}" ]] || fail "missing Dockerfile: ${imageName}"
    grep -Fq 'FROM ${ALPINE_BASE}' "${dockerfile}" || fail "${imageName} does not use the locked base"
    grep -Fq 'org.opencontainers.image.source=' "${dockerfile}" || fail "${imageName} lacks OCI labels"
    grep -Fq "io.padm.image=\"${imageName}\"" "${dockerfile}" || fail "${imageName} identity label drifted"
    grep -Fq 'io.padm.architecture=' "${dockerfile}" || fail "${imageName} lacks architecture label"
    grep -Fq 'io.padm.run-as=' "${dockerfile}" || fail "${imageName} lacks user contract"
    grep -Fq 'io.padm.writable-paths=' "${dockerfile}" || fail "${imageName} lacks writable path contract"
    grep -Eq '^USER[[:space:]]+' "${dockerfile}" || fail "${imageName} lacks USER"
    grep -Eq '^ENTRYPOINT[[:space:]]+' "${dockerfile}" || fail "${imageName} lacks ENTRYPOINT"
    grep -Eq '^HEALTHCHECK[[:space:]]+' "${dockerfile}" || fail "${imageName} lacks HEALTHCHECK"
done

if grep -ERni 'fail2ban|wireguard|iptables|nftables|python3|acme[.]sh' \
    "${PROJECT_ROOT}/docker/images/xray" "${PROJECT_ROOT}/docker/images/sing-box" >/dev/null; then
    fail 'core images contain ops or net tooling'
fi
if grep -ERni 'docker[.]sock|privileged|SYS_ADMIN|:latest([^A-Za-z0-9_.-]|$)' \
    "${PROJECT_ROOT}/versions.lock" "${PROJECT_ROOT}/docker-bake.hcl" \
    "${PROJECT_ROOT}/docker/images" "${PROJECT_ROOT}/docker/compose.yaml" >/dev/null; then
    fail 'Docker source violates the fixed-image or privilege boundary'
fi

for entrypoint in "${PROJECT_ROOT}/docker/images/ops/entrypoint.sh" "${PROJECT_ROOT}/docker/images/net/entrypoint.sh"; do
    sh -n "${entrypoint}" || fail "invalid entrypoint syntax: ${entrypoint}"
done

DOCKER_BIN=${PADM_TEST_DOCKER_BIN:-}
if [[ -z "${DOCKER_BIN}" ]]; then
    DOCKER_BIN=$(command -v docker || true)
fi
[[ -n "${DOCKER_BIN}" && -x "${DOCKER_BIN}" ]] || fail 'Docker CLI is required for Bake and Compose config checks'
export DOCKER_CONFIG="${TEST_ROOT}/docker-config"
mkdir -p "${DOCKER_CONFIG}"

bakeJson="${TEST_ROOT}/bake.json"
(
    cd "${PROJECT_ROOT}"
    "${DOCKER_BIN}" buildx bake --print >"${bakeJson}"
) || fail 'docker buildx bake --print failed'
jq -e '
    (.group.default.targets | sort) == ["net", "nginx", "ops", "sing-box", "xray"] and
    all(.target[]; (.platforms | sort) == ["linux/amd64", "linux/arm64"]) and
    all(.target[]; .args.ALPINE_BASE == $base) and
    all(.target[]; (.tags | length) == 1 and (all(.tags[]; (contains(":latest") | not))))
' --arg base "${PADM_LOCK_ALPINE_BASE}" "${bakeJson}" >/dev/null || fail 'Bake output drifted from the lock contract'

digest=$(printf '1%.0s' {1..64})
imagesEnv="${TEST_ROOT}/images.env"
cat >"${imagesEnv}" <<EOF
PADM_XRAY_IMAGE=ghcr.io/neil1123-vip/padm-xray:test@sha256:${digest}
PADM_SINGBOX_IMAGE=ghcr.io/neil1123-vip/padm-sing-box:test@sha256:${digest}
PADM_NGINX_IMAGE=ghcr.io/neil1123-vip/padm-nginx:test@sha256:${digest}
PADM_OPS_IMAGE=ghcr.io/neil1123-vip/padm-ops:test@sha256:${digest}
PADM_NET_IMAGE=ghcr.io/neil1123-vip/padm-net:test@sha256:${digest}
PADM_DOCKER_ROOT=${TEST_ROOT}/state
EOF

composeJson="${TEST_ROOT}/compose.json"
"${DOCKER_BIN}" compose --project-name padm-docker --env-file "${imagesEnv}" \
    --file "${COMPOSE_FILE}" --profile '*' config --format json >"${composeJson}" ||
    fail 'docker compose config failed'

jq -e '
    .name == "padm-docker" and
    (.services | keys) == ["acme", "net-fail2ban", "net-transparent", "net-wireguard", "nginx", "sing-box", "subscription", "xray"] and
    all(.services[]; .read_only == true) and
    all(.services[]; (.cap_drop | index("ALL")) != null) and
    all(.services[]; .labels["io.padm.project"] == "padm-docker") and
    all(.services[]; .image | test("@sha256:[0-9a-f]{64}$")) and
    all(.services[].volumes[]? | select(.source | endswith("/secrets")); .read_only == true) and
    all(.services | to_entries[] | select(.key | startswith("net-") | not); (.value.cap_add // []) | length == 0) and
    all(.services | to_entries[] | select(.key | startswith("net-")); .value.cap_add == ["NET_ADMIN"] and .value.network_mode == "host") and
    .services["net-transparent"].devices[0].source == "/dev/net/tun" and
    .networks.default.name == "padm-docker" and
    .networks.default.labels["io.padm.project"] == "padm-docker"
' "${composeJson}" >/dev/null || fail 'Compose output violates the profile or privilege contract'

printf 'docker-phase2-regression-ok\n'
