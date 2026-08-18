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

for tool in bash jq grep sha256sum; do
    command -v "${tool}" >/dev/null 2>&1 || fail "missing tool: ${tool}"
done

RELEASE_SCRIPT=${PROJECT_ROOT}/docker/release.sh
SCHEMA_FILE=${PROJECT_ROOT}/docker/contracts/release-manifest.schema.json
BUILD_WORKFLOW=${PROJECT_ROOT}/.github/workflows/build-images.yml
PR_WORKFLOW=${PROJECT_ROOT}/.github/workflows/docker-ci.yml
RELEASE_WORKFLOW=${PROJECT_ROOT}/.github/workflows/create_release.yml
FAST_CASES=${PROJECT_ROOT}/shell/regression/cases/fast.sh
FAST_SUITE=${PROJECT_ROOT}/shell/regression/suites/fast.sh
for file in "${RELEASE_SCRIPT}" "${SCHEMA_FILE}" "${BUILD_WORKFLOW}" "${PR_WORKFLOW}" "${RELEASE_WORKFLOW}" \
    "${PROJECT_ROOT}/docker/tests/image-smoke.sh"; do
    [[ -f "${file}" && ! -L "${file}" ]] || fail "required phase 5 file is missing: ${file}"
done

bash -n "${RELEASE_SCRIPT}" "${PROJECT_ROOT}/docker/tests/image-smoke.sh" || fail 'phase 5 shell syntax is invalid'
jq empty "${SCHEMA_FILE}" || fail 'release manifest schema is invalid JSON'
bash "${RELEASE_SCRIPT}" validate-lock | grep -qx 'release-lock-ok' || fail 'release lock validation failed'

for name in xray sing-box nginx ops net; do
    jq -n --arg name "${name}" --arg digest "sha256:${IMAGE_DIGEST}" \
        --arg platform "sha256:${PLATFORM_DIGEST}" \
        --arg reference "ghcr.io/neil1123-vip/padm-${name}:${CURRENT_VERSION}@sha256:${IMAGE_DIGEST}" \
        '{name: $name, reference: $reference, index_digest: $digest,
          platforms: {"linux/amd64": $platform, "linux/arm64": $platform}}' \
        >"${RESULTS_DIR}/${name}.json"
done

bash "${RELEASE_SCRIPT}" manifest \
    --version "${CURRENT_VERSION}" \
    --commit "${COMMIT}" \
    --created-at 2026-08-18T00:00:00Z \
    --registry ghcr.io/neil1123-vip \
    --bundle-url "https://github.com/neil1123-vip/padm/releases/download/v${CURRENT_VERSION}/padm-docker-bundle.tar.gz" \
    --bundle-sha256 "${IMAGE_DIGEST}" \
    --results-dir "${RESULTS_DIR}" \
    --output "${MANIFEST}" || fail 'manifest generation failed'
bash "${RELEASE_SCRIPT}" validate-manifest "${MANIFEST}" | grep -qx 'release-manifest-ok' ||
    fail 'generated manifest does not validate'
jq -e --arg version "${CURRENT_VERSION}" '
  .schema_version == 1 and .release.version == $version and
  (.images | keys | sort) == ["net", "nginx", "ops", "sing-box", "xray"] and
  .compatibility.architectures == ["amd64", "arm64"] and
  .migrations == []
' "${MANIFEST}" >/dev/null || fail 'generated manifest fields are wrong'

jq '.unexpected = true' "${MANIFEST}" >"${MANIFEST}.bad"
if bash "${RELEASE_SCRIPT}" validate-manifest "${MANIFEST}.bad" >/dev/null 2>&1; then
    fail 'manifest validator accepted an unknown field'
fi

grep -Fq 'workflow_call:' "${BUILD_WORKFLOW}" || fail 'build workflow is not reusable'
grep -Fq 'docker/setup-qemu-action' "${BUILD_WORKFLOW}" || fail 'build workflow lacks multi-arch emulation'
grep -Fq 'linux/amd64' "${BUILD_WORKFLOW}" || fail 'build workflow lacks amd64'
grep -Fq 'linux/arm64' "${BUILD_WORKFLOW}" || fail 'build workflow lacks arm64'
grep -Fq -- '--provenance=mode=max' "${BUILD_WORKFLOW}" || fail 'provenance attestation is not enabled'
grep -Fq -- '--sbom=true' "${BUILD_WORKFLOW}" || fail 'SBOM attestation is not enabled'
grep -Fq 'cosign sign' "${BUILD_WORKFLOW}" || fail 'image signing is not enabled'
grep -Fq 'packages: write' "${BUILD_WORKFLOW}" || fail 'package write permission is missing'
grep -Fq 'id-token: write' "${BUILD_WORKFLOW}" || fail 'OIDC permission is missing'
grep -Fq 'packages: write' "${RELEASE_WORKFLOW}" || fail 'Release caller lacks package write permission'
grep -Fq 'id-token: write' "${RELEASE_WORKFLOW}" || fail 'Release caller lacks OIDC permission'
grep -Fq 'release-manifest.json' "${BUILD_WORKFLOW}" || fail 'release manifest is not an artifact'
grep -Fq 'uses: ./.github/workflows/build-images.yml' "${RELEASE_WORKFLOW}" ||
    fail 'Release workflow does not call reusable image workflow'
grep -Fq 'needs: [prepare, images]' "${RELEASE_WORKFLOW}" || fail 'Release workflow lacks image gate'
grep -Fq 'concurrency:' "${RELEASE_WORKFLOW}" || fail 'Release workflow lacks concurrency'
grep -Fq 'is_release_commit' "${RELEASE_WORKFLOW}" || fail 'Release workflow lacks release commit guard'
grep -Fq 'docker/release.sh set-version' "${RELEASE_WORKFLOW}" || fail 'lock/version bump is not unified'
grep -Fq 'uses: ./.github/workflows/build-images.yml' "${PR_WORKFLOW}" ||
    fail 'PR workflow does not reuse image workflow'
grep -Fq 'runDockerPhase5Regression' "${FAST_CASES}" || fail 'phase 5 is not in fast regression cases'
grep -Fq 'docker-phase5' "${FAST_SUITE}" || fail 'phase 5 is not registered in fast suite'
if grep -ERn ':[[:space:]]*latest([[:space:]]|$)' "${BUILD_WORKFLOW}" "${PR_WORKFLOW}" "${RELEASE_WORKFLOW}" >/dev/null; then
    fail 'phase 5 workflow contains latest image tags'
fi

printf 'docker-phase5-regression-ok\n'
