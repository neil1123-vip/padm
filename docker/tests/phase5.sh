#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-phase5.XXXXXX")
RESULTS_DIR=${TEST_ROOT}/results
MANIFEST=${TEST_ROOT}/release-manifest.json
IMAGE_DIGEST=$(printf '1%.0s' {1..64})
PLATFORM_DIGEST=$(printf '2%.0s' {1..64})
COMMIT=$(printf 'a%.0s' {1..40})
CURRENT_VERSION=$(sed -n 's/^SCRIPT_VERSION="\([^"]*\)"$/\1/p' "${PROJECT_ROOT}/shell/core/version.sh")
mkdir -p "${RESULTS_DIR}"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

fail() {
    printf 'docker-phase5-regression-fail: %s\n' "$*" >&2
    exit 1
}

for tool in bash cmp git jq grep sha256sum; do
    command -v "${tool}" >/dev/null 2>&1 || fail "missing tool: ${tool}"
done

RELEASE_SCRIPT=${PROJECT_ROOT}/docker/release.sh
SCHEMA_FILE=${PROJECT_ROOT}/docker/contracts/release-manifest.schema.json
BUILD_WORKFLOW=${PROJECT_ROOT}/.github/workflows/build-images.yml
PR_WORKFLOW=${PROJECT_ROOT}/.github/workflows/docker-ci.yml
RELEASE_WORKFLOW=${PROJECT_ROOT}/.github/workflows/create_release.yml
UPSTREAM_WORKFLOW=${PROJECT_ROOT}/.github/workflows/refresh-upstreams.yml
FAST_CASES=${PROJECT_ROOT}/shell/regression/cases/fast.sh
FAST_SUITE=${PROJECT_ROOT}/shell/regression/suites/fast.sh
for file in "${RELEASE_SCRIPT}" "${SCHEMA_FILE}" "${BUILD_WORKFLOW}" "${PR_WORKFLOW}" "${RELEASE_WORKFLOW}" \
    "${UPSTREAM_WORKFLOW}" \
    "${PROJECT_ROOT}/docker/tests/image-smoke.sh"; do
    [[ -f "${file}" && ! -L "${file}" ]] || fail "required phase 5 file is missing: ${file}"
done

bash -n "${RELEASE_SCRIPT}" "${PROJECT_ROOT}/docker/tests/image-smoke.sh" || fail 'phase 5 shell syntax is invalid'
jq empty "${SCHEMA_FILE}" || fail 'release manifest schema is invalid JSON'
bash "${RELEASE_SCRIPT}" validate-lock | grep -qx 'release-lock-ok' || fail 'release lock validation failed'

INPUT_ROOT=${TEST_ROOT}/image-inputs
mkdir -p "${INPUT_ROOT}/docker/tests" "${INPUT_ROOT}/.github/workflows" "${INPUT_ROOT}/shell"
cp "${RELEASE_SCRIPT}" "${INPUT_ROOT}/docker/release.sh"
cp "${PROJECT_ROOT}/versions.lock" "${PROJECT_ROOT}/docker-bake.hcl" "${INPUT_ROOT}/"
cp -R "${PROJECT_ROOT}/docker/images" "${INPUT_ROOT}/docker/images"
cp "${BUILD_WORKFLOW}" "${INPUT_ROOT}/.github/workflows/build-images.yml"
cp "${PROJECT_ROOT}/docker/tests/image-smoke.sh" "${INPUT_ROOT}/docker/tests/image-smoke.sh"
git -C "${INPUT_ROOT}" init -q
git -C "${INPUT_ROOT}" config core.autocrlf false
git -C "${INPUT_ROOT}" config user.name 'padm phase5'
git -C "${INPUT_ROOT}" config user.email 'padm-phase5@example.invalid'
input_commit() {
    git -C "${INPUT_ROOT}" add --all
    git -C "${INPUT_ROOT}" -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm fixture
    git -C "${INPUT_ROOT}" rev-parse HEAD
}
assert_image_impact() {
    local base=$1 head=$2 affected=$3 image actual expected
    for image in xray sing-box nginx ops net; do
        expected=unchanged
        [[ "${affected}" != all && "${affected}" != "${image}" ]] || expected=changed
        if bash "${INPUT_ROOT}/docker/release.sh" image-inputs-unchanged "${base}" "${head}" "${image}"; then
            actual=unchanged
        else
            actual=changed
        fi
        [[ "${actual}" == "${expected}" ]] || fail "${affected} input reported ${image} as ${actual}"
    done
}
inputBase=$(input_commit)
sed 's/^PADM_LOCK_VERSION=.*/PADM_LOCK_VERSION=99.0.0/' "${INPUT_ROOT}/versions.lock" >"${INPUT_ROOT}/lock.next"
mv "${INPUT_ROOT}/lock.next" "${INPUT_ROOT}/versions.lock"
printf ':\n' >"${INPUT_ROOT}/shell/control.sh"
inputHead=$(input_commit)
assert_image_impact "${inputBase}" "${inputHead}" none
inputBase=${inputHead}
printf '\n# 补充运行验证\n' >>"${INPUT_ROOT}/docker/tests/image-smoke.sh"
inputHead=$(input_commit)
assert_image_impact "${inputBase}" "${inputHead}" none

# 按实际 Bake 参数覆盖每个镜像的独立依赖，避免把上游升级放大为全量构建。
for dependency in xray:PADM_LOCK_UNZIP_VERSION sing-box:PADM_LOCK_GCOMPAT_VERSION \
    nginx:PADM_LOCK_NGINX_PACKAGE_VERSION ops:PADM_LOCK_ACME_SH_SHA256 net:PADM_LOCK_FAIL2BAN_VERSION; do
    inputBase=${inputHead}
    inputKey=${dependency#*:}
    awk -v key="${inputKey}" 'index($0, key "=") == 1 {$0 = key "=changed"} {print}' \
        "${INPUT_ROOT}/versions.lock" >"${INPUT_ROOT}/lock.next"
    mv "${INPUT_ROOT}/lock.next" "${INPUT_ROOT}/versions.lock"
    inputHead=$(input_commit)
    assert_image_impact "${inputBase}" "${inputHead}" "${dependency%%:*}"
done
inputBase=${inputHead}
printf '\n# 订阅容器变更\n' >>"${INPUT_ROOT}/docker/images/ops/control_server.py"
inputHead=$(input_commit)
assert_image_impact "${inputBase}" "${inputHead}" ops

inputBase=${inputHead}
sed 's/^PADM_LOCK_CA_CERTIFICATES_VERSION=.*/PADM_LOCK_CA_CERTIFICATES_VERSION=changed/' \
    "${INPUT_ROOT}/versions.lock" >"${INPUT_ROOT}/lock.next"
mv "${INPUT_ROOT}/lock.next" "${INPUT_ROOT}/versions.lock"
inputHead=$(input_commit)
assert_image_impact "${inputBase}" "${inputHead}" all
inputBase=${inputHead}
printf '\nPADM_LOCK_FUTURE_DEPENDENCY=1\n' >>"${INPUT_ROOT}/versions.lock"
inputHead=$(input_commit)
assert_image_impact "${inputBase}" "${inputHead}" all
inputBase=${inputHead}
printf '\n# 构建输入变更\n' >>"${INPUT_ROOT}/.github/workflows/build-images.yml"
inputHead=$(input_commit)
assert_image_impact "${inputBase}" "${inputHead}" all

# 无法证明祖先关系时，不能根据相同文件内容认定已有镜像可复用。
if bash "${INPUT_ROOT}/docker/release.sh" image-inputs-unchanged missing-ref "${inputHead}" xray ||
    bash "${INPUT_ROOT}/docker/release.sh" image-inputs-unchanged "${inputHead}" "${inputBase}" xray; then
    fail 'image reuse accepted an unknown or non-ancestor baseline'
fi

UPDATER_ROOT=${TEST_ROOT}/updater
MOCK_BIN=${TEST_ROOT}/mock-bin
mkdir -p "${UPDATER_ROOT}/docker" "${UPDATER_ROOT}/shell/core" "${MOCK_BIN}"
cp "${RELEASE_SCRIPT}" "${UPDATER_ROOT}/docker/release.sh"
cp "${PROJECT_ROOT}/versions.lock" "${UPDATER_ROOT}/versions.lock"
cp "${UPDATER_ROOT}/versions.lock" "${UPDATER_ROOT}/versions.lock.original"
cp "${PROJECT_ROOT}/shell/core/version.sh" "${UPDATER_ROOT}/shell/core/version.sh"
cat >"${MOCK_BIN}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
*repos/XTLS/Xray-core/releases/latest*) printf '%s\n' '{"tag_name":"v99.1.2","draft":false,"prerelease":false}' ;;
*'repos/neil1123-vip/padm/releases?per_page=100 --paginate --slurp'*)
    if [[ "${PADM_TEST_STATS_FAILURE:-}" == no-stable ]]; then
        printf '%s\n' '[[{"tag_name":"sing-box-v9.8.7","draft":true,"prerelease":false}]]'
    else
        printf '%s\n' '[[{"tag_name":"v99.0.0","draft":false,"prerelease":false},
          {"tag_name":"sing-box-v9.7.0","draft":false,"prerelease":false},
          {"tag_name":"sing-box-v99.0.0","draft":true,"prerelease":false},
          {"tag_name":"sing-box-v98.0.0","draft":false,"prerelease":true},
          {"tag_name":"sing-box-v97.0.0-alpha.1","draft":false,"prerelease":false}],
          [{"tag_name":"sing-box-v9.8.7","draft":false,"prerelease":false}]]'
    fi ;;
*repos/neil1123-vip/padm/releases/tags/sing-box-v9.8.7*|*repos/SagerNet/sing-box/releases/tags/v9.8.7*)
    prefix=sing-box
    tag=sing-box-v9.8.7
    if [[ "$*" == *repos/SagerNet/* ]]; then
        prefix=upstream
        tag=v9.8.7
    fi
    jq -n --arg tag "${tag}" --arg failure "${PADM_TEST_STATS_FAILURE:-}" \
        --arg amd64 "$(printf '%s' "${prefix}-amd64" | sha256sum | awk '{print $1}')" \
        --arg arm64 "$(printf '%s' "${prefix}-arm64" | sha256sum | awk '{print $1}')" '
      {tag_name: $tag, draft: false, prerelease: false, assets: [
        {name: "sing-box-9.8.7-linux-amd64.tar.gz", size: 100, digest: ("sha256:" + $amd64)},
        {name: "sing-box-9.8.7-linux-arm64.tar.gz", size: 100, digest: ("sha256:" + $arm64)},
        {name: "sing-box-9.8.7-source.tar.gz", size: 100, digest: ("sha256:" + $amd64)},
        {name: "SHA256SUMS", size: 100, digest: ("sha256:" + $amd64)}]} |
      if $failure == "missing-asset" then .assets |= map(select(.name != "SHA256SUMS"))
      elif $failure == "missing-digest" then .assets[1].digest = null
      elif $failure == "duplicate-asset" then .assets += [.assets[0]]
      else . end' ;;
*repos/acmesh-official/acme.sh/releases/latest*) printf '%s\n' '{"tag_name":"v8.7.6","draft":false,"prerelease":false}' ;;
*) exit 1 ;;
esac
EOF
cat >"${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=
url=
while [[ "$#" -gt 0 ]]; do
    case "$1" in
    --output | -o) output=${2:-}; shift 2 ;;
    *) url=$1; shift ;;
    esac
done
[[ -n "${output}" && -n "${url}" ]] || exit 1
case "${url}" in
*Xray-linux-64.zip) printf '%s' xray-amd64 >"${output}" ;;
*Xray-linux-arm64-v8a.zip) printf '%s' xray-arm64 >"${output}" ;;
https://github.com/neil1123-vip/padm/releases/download/sing-box-v9.8.7/sing-box-9.8.7-linux-amd64.tar.gz)
    printf '%s' sing-box-amd64 >"${output}" ;;
https://github.com/neil1123-vip/padm/releases/download/sing-box-v9.8.7/sing-box-9.8.7-linux-arm64.tar.gz)
    [[ "${PADM_TEST_STATS_FAILURE:-}" != download ]] || exit 22
    printf '%s' sing-box-arm64 >"${output}"
    [[ "${PADM_TEST_STATS_FAILURE:-}" != checksum ]] || printf '%s' corrupt >>"${output}" ;;
*acmesh-official/acme.sh/tar.gz/refs/tags/v8.7.6) printf '%s' acme-sh >"${output}" ;;
*) exit 1 ;;
esac
EOF
chmod +x "${MOCK_BIN}/gh" "${MOCK_BIN}/curl"
PATH="${MOCK_BIN}:${PATH}" bash "${UPDATER_ROOT}/docker/release.sh" refresh-upstreams >/dev/null ||
    fail 'upstream lock refresh failed'
(
    set -a
    # shellcheck disable=SC1091
    . "${UPDATER_ROOT}/versions.lock"
    set +a
    [[ "${PADM_LOCK_XRAY_VERSION}" == v99.1.2 ]]
    [[ "${PADM_LOCK_XRAY_AMD64_SHA256}" == "$(printf '%s' xray-amd64 | sha256sum | awk '{print $1}')" ]]
    [[ "${PADM_LOCK_XRAY_ARM64_SHA256}" == "$(printf '%s' xray-arm64 | sha256sum | awk '{print $1}')" ]]
    [[ "${PADM_LOCK_SING_BOX_VERSION}" == v9.8.7 ]]
    [[ "${PADM_LOCK_SING_BOX_AMD64_ASSET}" == sing-box-9.8.7-linux-amd64.tar.gz ]]
    [[ "${PADM_LOCK_SING_BOX_ARM64_ASSET}" == sing-box-9.8.7-linux-arm64.tar.gz ]]
    [[ "${PADM_LOCK_SING_BOX_AMD64_SHA256}" == "$(printf '%s' sing-box-amd64 | sha256sum | awk '{print $1}')" ]]
    [[ "${PADM_LOCK_SING_BOX_ARM64_SHA256}" == "$(printf '%s' sing-box-arm64 | sha256sum | awk '{print $1}')" ]]
    [[ "${PADM_LOCK_SING_BOX_AMD64_UPSTREAM_SHA256}" == "$(printf '%s' upstream-amd64 | sha256sum | awk '{print $1}')" ]]
    [[ "${PADM_LOCK_SING_BOX_ARM64_UPSTREAM_SHA256}" == "$(printf '%s' upstream-arm64 | sha256sum | awk '{print $1}')" ]]
    [[ "${PADM_LOCK_ACME_SH_VERSION}" == 8.7.6 ]]
    [[ "${PADM_LOCK_ACME_SH_URL}" == */refs/tags/v8.7.6 ]]
) || fail 'upstream lock refresh produced wrong values'
cp "${UPDATER_ROOT}/versions.lock" "${UPDATER_ROOT}/versions.lock.once"
PATH="${MOCK_BIN}:${PATH}" bash "${UPDATER_ROOT}/docker/release.sh" refresh-upstreams >/dev/null ||
    fail 'idempotent upstream lock refresh failed'
cmp -s "${UPDATER_ROOT}/versions.lock.once" "${UPDATER_ROOT}/versions.lock" ||
    fail 'current upstream lock was rewritten'

# 发布不完整或下载失败时，任何核心的锁值都必须保持原样。
for failure in no-stable missing-asset missing-digest duplicate-asset download checksum; do
    cp "${UPDATER_ROOT}/versions.lock.original" "${UPDATER_ROOT}/versions.lock"
    if PATH="${MOCK_BIN}:${PATH}" PADM_TEST_STATS_FAILURE="${failure}" \
        bash "${UPDATER_ROOT}/docker/release.sh" refresh-upstreams >"${TEST_ROOT}/refresh-failure.log" 2>&1; then
        fail "upstream refresh accepted ${failure}"
    fi
    cmp -s "${UPDATER_ROOT}/versions.lock.original" "${UPDATER_ROOT}/versions.lock" ||
        fail "upstream refresh changed the lock after ${failure}"
done

for name in xray sing-box nginx ops net; do
    jq -n --arg name "${name}" --arg digest "sha256:${IMAGE_DIGEST}" \
        --arg platform "sha256:${PLATFORM_DIGEST}" \
        --arg reference "ghcr.io/neil1123-vip/padm-${name}:${CURRENT_VERSION}@sha256:${IMAGE_DIGEST}" \
        '{name: $name, reference: $reference, index_digest: $digest,
          platforms: {"linux/amd64": $platform, "linux/arm64": $platform}}' \
        >"${RESULTS_DIR}/${name}.json"
done

generate_manifest() {
    bash "${RELEASE_SCRIPT}" manifest \
        --version "${CURRENT_VERSION}" \
        --commit "${COMMIT}" \
        --created-at 2026-08-18T00:00:00Z \
        --registry ghcr.io/neil1123-vip \
        --bundle-url "https://github.com/neil1123-vip/padm/releases/download/v${CURRENT_VERSION}/padm-docker-bundle.tar.gz" \
        --bundle-sha256 "${IMAGE_DIGEST}" \
        --results-dir "${RESULTS_DIR}" \
        --output "${MANIFEST}"
}
generate_manifest || fail 'manifest generation failed'
bash "${RELEASE_SCRIPT}" validate-manifest "${MANIFEST}" | grep -qx 'release-manifest-ok' ||
    fail 'generated manifest does not validate'
jq -e --arg version "${CURRENT_VERSION}" '
  .schema_version == 1 and .release.version == $version and
  (.images | keys | sort) == ["net", "nginx", "ops", "sing-box", "xray"] and
  .compatibility.architectures == ["amd64", "arm64"] and
  .migrations == []
' "${MANIFEST}" >/dev/null || fail 'generated manifest fields are wrong'

cp "${RESULTS_DIR}/xray.json" "${TEST_ROOT}/xray.original.json"
reusedReference="ghcr.io/neil1123-vip/padm-xray:0.0.1@sha256:${IMAGE_DIGEST}"
jq --arg reference "${reusedReference}" '.reference = $reference' \
    "${TEST_ROOT}/xray.original.json" >"${RESULTS_DIR}/xray.json"
generate_manifest || fail 'manifest rejected a reused image version'
jq -e --arg version "${CURRENT_VERSION}" --arg reference "${reusedReference}" \
    '.release.version == $version and .images.xray.reference == $reference' "${MANIFEST}" >/dev/null ||
    fail 'manifest changed the reused image reference'

for invalidReference in \
    "ghcr.io/other/padm-xray:0.0.1@sha256:${IMAGE_DIGEST}" \
    "ghcr.io/neil1123-vip/padm-sing-box:0.0.1@sha256:${IMAGE_DIGEST}" \
    "ghcr.io/neil1123-vip/padm-xray:latest@sha256:${IMAGE_DIGEST}" \
    "ghcr.io/neil1123-vip/padm-xray:0.0.1@sha256:${PLATFORM_DIGEST}"; do
    jq --arg reference "${invalidReference}" '.reference = $reference' \
        "${TEST_ROOT}/xray.original.json" >"${RESULTS_DIR}/xray.json"
    if generate_manifest >"${TEST_ROOT}/manifest-error.log" 2>&1; then
        fail "manifest accepted an invalid image reference: ${invalidReference}"
    fi
done
cp "${TEST_ROOT}/xray.original.json" "${RESULTS_DIR}/xray.json"
jq --arg digest "sha256:${PLATFORM_DIGEST}" '.images.xray.index_digest = $digest' \
    "${MANIFEST}" >"${MANIFEST}.bad"
if bash "${RELEASE_SCRIPT}" validate-manifest "${MANIFEST}.bad" >/dev/null 2>&1; then
    fail 'manifest validator accepted an inconsistent image digest'
fi

jq '.unexpected = true' "${MANIFEST}" >"${MANIFEST}.bad"
if bash "${RELEASE_SCRIPT}" validate-manifest "${MANIFEST}.bad" >/dev/null 2>&1; then
    fail 'manifest validator accepted an unknown field'
fi

grep -Fq 'workflow_call:' "${BUILD_WORKFLOW}" || fail 'build workflow is not reusable'
grep -Fq 'docker/setup-qemu-action' "${BUILD_WORKFLOW}" || fail 'build workflow lacks multi-arch emulation'
grep -Fq 'linux/amd64' "${BUILD_WORKFLOW}" || fail 'build workflow lacks amd64'
grep -Fq 'linux/arm64' "${BUILD_WORKFLOW}" || fail 'build workflow lacks arm64'
grep -Eq '^[[:space:]]+provenance:.*mode=max' "${BUILD_WORKFLOW}" || fail 'provenance attestation is not enabled'
grep -Eq '^[[:space:]]+sbom:.*inputs[.]push' "${BUILD_WORKFLOW}" || fail 'SBOM attestation is not enabled'
grep -Fq 'cosign sign' "${BUILD_WORKFLOW}" || fail 'image signing is not enabled'
grep -Fq 'packages: write' "${RELEASE_WORKFLOW}" || fail 'Release caller lacks package write permission'
grep -Fq 'id-token: write' "${RELEASE_WORKFLOW}" || fail 'Release caller lacks OIDC permission'
grep -Fq 'release-manifest.json' "${BUILD_WORKFLOW}" || fail 'release manifest is not an artifact'
grep -Fq -- '--new-bundle-format=true' "${RELEASE_WORKFLOW}" || fail 'Release does not request the new Cosign bundle format'
grep -Fq 'application/vnd.dev.sigstore.bundle.v0.3+json' "${RELEASE_WORKFLOW}" ||
    fail 'Release does not validate the Sigstore v0.3 bundle media type'
grep -Fq 'cosign verify-blob --bundle' "${RELEASE_WORKFLOW}" || fail 'Release does not verify the bundle directly'
grep -Fq 'cosign verify-blob --bundle' "${PROJECT_ROOT}/docker/lib/manifest.sh" ||
    fail 'runtime does not verify the manifest bundle directly'
if grep -Fq -- '--output-signature' "${RELEASE_WORKFLOW}" ||
    grep -Fq -- '--signature' "${RELEASE_WORKFLOW}" ||
    grep -Fq -- '--signature' "${PROJECT_ROOT}/docker/lib/manifest.sh" "${PROJECT_ROOT}/docker/lib/lifecycle.sh"; then
    fail 'Release still depends on a detached manifest signature'
fi
grep -Fq 'uses: ./.github/workflows/build-images.yml' "${RELEASE_WORKFLOW}" ||
    fail 'Release workflow does not call reusable image workflow'
grep -Fq 'needs: [prepare, images]' "${RELEASE_WORKFLOW}" || fail 'Release workflow lacks image gate'
grep -Fq 'concurrency:' "${RELEASE_WORKFLOW}" || fail 'Release workflow lacks concurrency'
grep -Fq 'is_release_commit' "${RELEASE_WORKFLOW}" || fail 'Release workflow lacks release commit guard'
grep -Fq 'docker/release.sh set-version' "${RELEASE_WORKFLOW}" || fail 'lock/version bump is not unified'
grep -Fq "cron: '17 3 * * 1'" "${UPSTREAM_WORKFLOW}" || fail 'upstream refresh is not scheduled weekly'
grep -Fq 'docker/release.sh refresh-upstreams' "${UPSTREAM_WORKFLOW}" ||
    fail 'upstream workflow does not refresh the lock'
grep -Fq 'pull-requests: write' "${UPSTREAM_WORKFLOW}" || fail 'upstream workflow cannot create PRs'
grep -Fq 'actions: write' "${UPSTREAM_WORKFLOW}" || fail 'upstream workflow cannot dispatch Docker CI'
grep -Fq 'checks: read' "${UPSTREAM_WORKFLOW}" || fail 'upstream workflow cannot read Docker CI status'
grep -Fq 'gh workflow run docker-ci.yml' "${UPSTREAM_WORKFLOW}" ||
    fail 'upstream workflow does not dispatch Docker CI'
grep -Fq 'gh run watch' "${UPSTREAM_WORKFLOW}" || fail 'upstream workflow does not wait for Docker CI'
grep -Fq 'uses: ./.github/workflows/build-images.yml' "${PR_WORKFLOW}" ||
    fail 'PR workflow does not reuse image workflow'
grep -Fq 'runDockerPhase5Regression' "${FAST_CASES}" || fail 'phase 5 is not in fast regression cases'
grep -Fq 'docker-phase5' "${FAST_SUITE}" || fail 'phase 5 is not registered in fast suite'
if grep -ERn ':[[:space:]]*latest([[:space:]]|$)' \
    "${BUILD_WORKFLOW}" "${PR_WORKFLOW}" "${RELEASE_WORKFLOW}" "${UPSTREAM_WORKFLOW}" >/dev/null; then
    fail 'phase 5 workflow contains latest image tags'
fi

printf 'docker-phase5-regression-ok\n'
