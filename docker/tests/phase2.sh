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

for tool in jq grep find sort python3; do
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
    PADM_LOCK_VERSION PADM_LOCK_SOURCE_URL PADM_LOCK_DEBIAN_BASE PADM_LOCK_DEBIAN_SNAPSHOT
    PADM_LOCK_DISTROLESS_STATIC_BASE PADM_LOCK_PYTHON_BASE PADM_LOCK_NGINX_BASE
    PADM_LOCK_XRAY_VERSION PADM_LOCK_XRAY_AMD64_ASSET
    PADM_LOCK_XRAY_AMD64_SHA256 PADM_LOCK_XRAY_ARM64_ASSET PADM_LOCK_XRAY_ARM64_SHA256
    PADM_LOCK_SING_BOX_VERSION PADM_LOCK_SING_BOX_AMD64_ASSET
    PADM_LOCK_SING_BOX_AMD64_SHA256 PADM_LOCK_SING_BOX_ARM64_ASSET PADM_LOCK_SING_BOX_ARM64_SHA256
    PADM_LOCK_SING_BOX_AMD64_UPSTREAM_SHA256 PADM_LOCK_SING_BOX_ARM64_UPSTREAM_SHA256
    PADM_LOCK_NGINX_VERSION PADM_LOCK_ACME_SH_VERSION
    PADM_LOCK_ACME_SH_URL PADM_LOCK_ACME_SH_SHA256 PADM_LOCK_PYTHON3_VERSION
    PADM_LOCK_PATCHES
)
for variableName in "${requiredLockVariables[@]}"; do
    [[ -n "${!variableName:-}" ]] || fail "missing lock variable: ${variableName}"
done

[[ "${PADM_LOCK_SCHEMA}" == 1 ]] || fail 'unsupported lock schema'
[[ "${PADM_LOCK_PLATFORM_AMD64}" == linux/amd64 ]] || fail 'amd64 platform drifted'
[[ "${PADM_LOCK_PLATFORM_ARM64}" == linux/arm64 ]] || fail 'arm64 platform drifted'
scriptVersion=$(sed -n 's/^SCRIPT_VERSION="\([^"]*\)"/\1/p' "${PROJECT_ROOT}/shell/core/version.sh")
[[ -n "${scriptVersion}" && "${PADM_LOCK_VERSION}" == "${scriptVersion}" ]] || fail 'padm version drifted from versions.lock'
bash "${PROJECT_ROOT}/docker/release.sh" validate-lock >/dev/null || fail 'base image locks are invalid'
python3 "${PROJECT_ROOT}/docker/tests/runtime-export.py" || fail 'runtime export contract failed'
for variableName in \
    PADM_LOCK_XRAY_AMD64_SHA256 PADM_LOCK_XRAY_ARM64_SHA256 \
    PADM_LOCK_SING_BOX_AMD64_SHA256 PADM_LOCK_SING_BOX_ARM64_SHA256 \
    PADM_LOCK_SING_BOX_AMD64_UPSTREAM_SHA256 PADM_LOCK_SING_BOX_ARM64_UPSTREAM_SHA256 \
    PADM_LOCK_ACME_SH_SHA256; do
    [[ "${!variableName}" =~ ^[0-9a-f]{64}$ ]] || fail "invalid checksum: ${variableName}"
done
[[ "${PADM_LOCK_PATCHES}" == none ]] || fail 'patch lock must name every applied patch or be none'

mapfile -t imageNames < <(find "${PROJECT_ROOT}/docker/images" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
[[ "${imageNames[*]}" == 'net nginx ops sing-box xray' ]] || fail "unexpected image set: ${imageNames[*]}"

for imageName in "${imageNames[@]}"; do
    dockerfile="${PROJECT_ROOT}/docker/images/${imageName}/Dockerfile"
    [[ -f "${dockerfile}" && ! -L "${dockerfile}" ]] || fail "missing Dockerfile: ${imageName}"
    finalFrom=$(awk '/^FROM / {line = $0} END {print line}' "${dockerfile}")
    [[ "${finalFrom}" == 'FROM ${DISTROLESS_STATIC_BASE}' ]] || fail "${imageName} does not use the locked distroless runtime"
    grep -Fq 'org.opencontainers.image.source=' "${dockerfile}" || fail "${imageName} lacks OCI labels"
    grep -Fq "io.padm.image=\"${imageName}\"" "${dockerfile}" || fail "${imageName} identity label drifted"
    grep -Fq 'io.padm.architecture=' "${dockerfile}" || fail "${imageName} lacks architecture label"
    grep -Fq 'io.padm.run-as=' "${dockerfile}" || fail "${imageName} lacks user contract"
    grep -Fq 'io.padm.writable-paths=' "${dockerfile}" || fail "${imageName} lacks writable path contract"
    grep -Eq '^USER[[:space:]]+' "${dockerfile}" || fail "${imageName} lacks USER"
    grep -Eq '^ENTRYPOINT[[:space:]]+' "${dockerfile}" || fail "${imageName} lacks ENTRYPOINT"
    grep -Eq '^HEALTHCHECK[[:space:]]+' "${dockerfile}" || fail "${imageName} lacks HEALTHCHECK"
done

grep -Fxq 'ENTRYPOINT ["/usr/sbin/nginx", "-e", "/dev/stderr"]' \
    "${PROJECT_ROOT}/docker/images/nginx/Dockerfile" || fail 'Nginx 初始错误日志未接入 stderr'
grep -Fq -- '--with-stream' "${PROJECT_ROOT}/docker/images/nginx/Dockerfile" ||
    fail 'Nginx 未校验静态编入的 stream 支持'
grep -Fxq 'include /etc/nginx/stream.d/*.conf;' \
    "${PROJECT_ROOT}/docker/images/nginx/nginx.conf" || fail 'Nginx 缺少独立 stream 配置入口'
grep -Fq 'DEBIAN_SNAPSHOT' "${PROJECT_ROOT}/docker/images/ops/Dockerfile" ||
    fail 'ops 的 ACME 和日期工具未固定 Debian 快照'

for imageName in xray sing-box; do
    if awk '/^FROM / {runtime = ""} {runtime = runtime $0 ORS} END {printf "%s", runtime}' \
        "${PROJECT_ROOT}/docker/images/${imageName}/Dockerfile" |
        grep -Ei 'fail2ban|wireguard|iptables|nftables|python3|acme[.]sh' >/dev/null; then
        fail 'core runtime images contain ops or net tooling'
    fi
done
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
    all(.target[]; .args.DEBIAN_BASE == $base and .args.DEBIAN_SNAPSHOT == $snapshot and
        .contexts.runtime == "docker/runtime") and
    all(.target[]; .args.DISTROLESS_STATIC_BASE == $static) and
    all(.target[]; .output == [{
        type: "image", compression: "gzip", "compression-level": "9", "force-compression": "true"
    }]) and
    .target["sing-box"].args.SING_BOX_VERSION == $singBoxVersion and
    .target["sing-box"].args.SING_BOX_AMD64_ASSET == $singBoxAmd64Asset and
    .target["sing-box"].args.SING_BOX_ARM64_ASSET == $singBoxArm64Asset and
    .target["sing-box"].args.SING_BOX_AMD64_SHA256 == $singBoxAmd64 and
    .target["sing-box"].args.SING_BOX_ARM64_SHA256 == $singBoxArm64 and
    .target.ops.args.PYTHON_BASE == $python and
    .target.nginx.args.NGINX_BASE == $nginx and
    all(.target[]; (.tags | length) == 1 and (all(.tags[]; (contains(":latest") | not))))
' --arg base "${PADM_LOCK_DEBIAN_BASE}" \
    --arg snapshot "${PADM_LOCK_DEBIAN_SNAPSHOT}" \
    --arg static "${PADM_LOCK_DISTROLESS_STATIC_BASE}" \
    --arg singBoxVersion "${PADM_LOCK_SING_BOX_VERSION}" \
    --arg singBoxAmd64Asset "${PADM_LOCK_SING_BOX_AMD64_ASSET}" \
    --arg singBoxArm64Asset "${PADM_LOCK_SING_BOX_ARM64_ASSET}" \
    --arg singBoxAmd64 "${PADM_LOCK_SING_BOX_AMD64_SHA256}" \
    --arg singBoxArm64 "${PADM_LOCK_SING_BOX_ARM64_SHA256}" \
    --arg python "${PADM_LOCK_PYTHON_BASE}" \
    --arg nginx "${PADM_LOCK_NGINX_BASE}" \
    "${bakeJson}" >/dev/null || fail 'Bake output drifted from the lock contract'

# CI 会整体替换 output；同时检查发布和显式加载，防止覆盖时丢失压缩参数。
for exporter in image docker; do
    output="type=${exporter}"
    flags=(--print)
    if [[ "${exporter}" == image ]]; then
        output+=',push-by-digest=true,name-canonical=true,push=true'
    else
        flags+=(--load)
    fi
    output+=',compression=gzip,compression-level=9,force-compression=true'
    grep -Fq "'${output}'" "${PROJECT_ROOT}/.github/workflows/build-images.yml" ||
        fail "CI ${exporter} exporter lost the compression contract"
    (
        cd "${PROJECT_ROOT}"
        "${DOCKER_BIN}" buildx bake "${flags[@]}" --set "*.output=${output}" >"${bakeJson}"
    ) || fail "Bake ${exporter} export parsing failed"
    jq -e --arg type "${exporter}" '
        all(.target[]; (.output | length) == 1 and all(.output[];
            .type == $type and .compression == "gzip" and
            .["compression-level"] == "9" and .["force-compression"] == "true" and
            (if $type == "image" then
                .push == "true" and .["push-by-digest"] == "true" and .["name-canonical"] == "true"
             else true end)))
    ' "${bakeJson}" >/dev/null || fail "Bake ${exporter} exporter lost the compression contract"
done

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
