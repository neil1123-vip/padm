#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
test_root=$(mktemp -d "${project_root}/.tmp-preflight-test.XXXXXX")
trap 'rm -rf -- "${test_root}"' EXIT
fail() { printf 'preflight-test: %s\n' "$*" >&2; exit 1; }
mkdir -p "${test_root}/project/docker" "${test_root}/project/shell/core" "${test_root}/bin"
cp "${project_root}/docker/release.sh" "${test_root}/project/docker/release.sh"
cp "${project_root}/shell/core/version.sh" "${test_root}/project/shell/core/version.sh"
jq -n '{schemaVersion: 2, mediaType: "application/vnd.oci.image.index.v1+json", manifests: [
    {digest: ("sha256:" + ("a" * 64)), platform: {os: "linux", architecture: "amd64"}},
    {digest: ("sha256:" + ("b" * 64)), platform: {os: "linux", architecture: "arm64"}}]}' \
    >"${test_root}/index.json"
index_digest=$(sha256sum "${test_root}/index.json" | awk '{print $1}')
sed -E "s/@sha256:[0-9a-f]{64}$/@sha256:${index_digest}/" "${project_root}/versions.lock" \
    >"${test_root}/project/versions.lock"
cp "${test_root}/project/versions.lock" "${test_root}/lock.before"
cp "${test_root}/project/shell/core/version.sh" "${test_root}/version.before"

cat >"${test_root}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output= url=
while [[ "$#" -gt 0 ]]; do
    case "$1" in
    --output) output=$2; shift 2 ;;
    *) url=$1; shift ;;
    esac
done
printf '%s\n' "${url}" >>"${FIXTURE_ROOT}/calls"
case "${url}" in
https://auth.docker.io/token\?*)
    [[ "${SCENARIO}" != auth ]] || { printf '{}\n'; exit; }
    printf '{"token":"fixture-token"}\n'
    ;;
*/manifests/sha256:*)
    [[ -n "${output}" ]]
    [[ "${SCENARIO}" != network ]] || { printf 'simulated network failure\n' >&2; exit 22; }
    cp "${INDEX_FIXTURE}" "${output}"
    case "${SCENARIO}" in
    missing-amd64|missing-arm64)
        arch=${SCENARIO#missing-}
        jq --arg arch "${arch}" '.manifests |= map(select(.platform.architecture != $arch))' \
            "${output}" >"${output}.next"
        mv "${output}.next" "${output}" ;;
    duplicate-arch)
        jq '.manifests += [.manifests[0]]' "${output}" >"${output}.next"
        mv "${output}.next" "${output}" ;;
    invalid-digest)
        jq '.manifests[1].digest = "sha256:invalid"' "${output}" >"${output}.next"
        mv "${output}.next" "${output}" ;;
    invalid-index) printf '{}\n' >"${output}" ;;
    digest-mismatch) printf '\n' >>"${output}" ;;
    esac
    ;;
https://snapshot.debian.org/archive/*/InRelease)
    [[ -n "${output}" ]]
    suite=${url%/InRelease}
    suite=${suite##*/}
    [[ "${SCENARIO}" != snapshot-network ]] || exit 22
    {
        printf '%s\n' '-----BEGIN PGP SIGNED MESSAGE-----' 'Hash: SHA256' ''
        printf 'Codename: %s\nArchitectures: amd64 arm64\n' "${suite}"
        printf '%s\n' '-----BEGIN PGP SIGNATURE-----' fixture '-----END PGP SIGNATURE-----'
    } >"${output}"
    case "${SCENARIO}" in
    snapshot-suite) sed -i 's/Codename:.*/Codename: bookworm/' "${output}" ;;
    snapshot-arch) sed -i 's/Architectures:.*/Architectures: amd64/' "${output}" ;;
    snapshot-unsigned) sed -i '/BEGIN PGP SIGNATURE/d' "${output}" ;;
    esac
    ;;
*) exit 1 ;;
esac
EOF
chmod +x "${test_root}/bin/curl"

for scenario in available missing-amd64 missing-arm64 duplicate-arch invalid-digest invalid-index \
    digest-mismatch network auth snapshot-network snapshot-suite snapshot-arch snapshot-unsigned; do
    fixture_root=${test_root}/${scenario}
    mkdir -p "${fixture_root}"
    actual=success
    PATH="${test_root}/bin:${PATH}" FIXTURE_ROOT="${fixture_root}" SCENARIO="${scenario}" \
        INDEX_FIXTURE="${test_root}/index.json" \
        bash "${test_root}/project/docker/release.sh" preflight >"${fixture_root}/output" 2>&1 || actual=failure
    if [[ "${scenario}" == available ]]; then
        [[ "${actual}" == success ]] || { cat "${fixture_root}/output"; fail 'valid immutable inputs rejected'; }
        grep -Fxq 'release-preflight-ok' "${fixture_root}/output" || fail 'success not reported'
        [[ "$(grep -c '/manifests/sha256:' "${fixture_root}/calls")" -eq 4 ]] ||
            fail 'all four base indices were not checked'
        [[ "$(grep -c '/InRelease$' "${fixture_root}/calls")" -eq 3 ]] ||
            fail 'all Debian snapshot suites were not checked'
    else
        [[ "${actual}" == failure ]] || fail "${scenario} passed"
        case "${scenario}" in
        missing-*|duplicate-arch|invalid-digest) expected='lacks unique amd64/arm64 manifests' ;;
        invalid-index) expected='invalid base image index' ;;
        digest-mismatch) expected='base image index digest mismatch' ;;
        network) expected='failed to query base image' ;;
        auth) expected='failed to authenticate official' ;;
        snapshot-network) expected='is unavailable' ;;
        snapshot-*) expected='invalid Debian snapshot metadata' ;;
        esac
        grep -Fq "${expected}" "${fixture_root}/output" ||
            { cat "${fixture_root}/output"; fail "${scenario}: wrong failure"; }
    fi
    cmp -s "${test_root}/lock.before" "${test_root}/project/versions.lock" || fail "${scenario}: lock changed"
    cmp -s "${test_root}/version.before" "${test_root}/project/shell/core/version.sh" || fail "${scenario}: script version changed"
done

printf 'preflight-regression-ok\n'
