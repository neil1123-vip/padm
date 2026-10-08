#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-release.XXXXXX")
MOCK_BIN="${TEST_ROOT}/bin"
STATE_ROOT="${TEST_ROOT}/state"
SOURCE_ROOT="${TEST_ROOT}/source"
CONTROL_ROOT="${TEST_ROOT}/control"
MANIFEST="${TEST_ROOT}/release-manifest.json"
SIGNATURE="${TEST_ROOT}/release-manifest.sigstore.json"
CONTROL_BUNDLE="${TEST_ROOT}/control.tar.gz"
OUT="${TEST_ROOT}/stdout"
ERR="${TEST_ROOT}/stderr"
PULL_LOG="${TEST_ROOT}/pull.log"
VERIFY_LOG="${TEST_ROOT}/verify.log"
DOWNLOAD_LOG="${TEST_ROOT}/download.log"
IDENTITY=https://github.com/neil1123-vip/padm/.github/workflows/create_release.yml@refs/heads/main
ISSUER=https://token.actions.githubusercontent.com
mkdir -p "${MOCK_BIN}" "${TEST_ROOT}/native"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

fail() {
    [[ ! -f "${ERR}" ]] || sed 's/^/  /' "${ERR}" >&2
    printf 'docker-release-regression-fail: %s\n' "$*" >&2
    exit 1
}

cat >"${MOCK_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
-m) printf '%s\n' "${FAKE_ARCH:-x86_64}" ;;
*) printf 'Linux\n' ;;
esac
EOF
cat >"${MOCK_BIN}/id" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == -u ]] && printf '0\n'
EOF
cat >"${MOCK_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -u
case "${1:-}" in
info)
    if [[ "${2:-}" == --format ]]; then
        case "${3:-}" in
        '{{.OSType}}') printf 'linux\n' ;;
        '{{.Architecture}}') printf '%s\n' "${FAKE_ARCH:-x86_64}" ;;
        '{{json .SecurityOptions}}') printf '["name=seccomp,profile=builtin"]\n' ;;
        *) exit 1 ;;
        esac
    fi
    ;;
context) printf 'unix:///var/run/docker.sock\n' ;;
ps) ;;
compose) [[ "${2:-}" == version ]] && printf 'v2.29.1\n' ;;
pull)
    printf '%s\n' "$2" >>"${FAKE_PULL_LOG:?}"
    printf 'mock-pull: %s\n' "$2"
    [[ "${FAKE_PULL_FAIL:-0}" != 1 ]] || exit 1
    ;;
*) exit 1 ;;
esac
EOF
cat >"${MOCK_BIN}/cosign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${FAKE_VERIFY_LOG:?}"
[[ "$#" -eq 8 && "$1" == verify-blob && "$2" == --bundle &&
    "$4" == --certificate-identity-regexp &&
    "$5" == '^https://github\.com/neil1123-vip/padm/\.github/workflows/create_release\.yml@refs/heads/main$' &&
    "$6" == --certificate-oidc-issuer && "$7" == https://token.actions.githubusercontent.com ]] || exit 1
manifestSha=$(sha256sum "$8" | cut -d ' ' -f 1)
# 假验证器仍检查固定信任边界和签名绑定，不能无条件接受任意输入。
jq -e --arg sha "${manifestSha}" '
    .signature == "fixture-valid" and .manifest_sha256 == $sha and
    .identity == "https://github.com/neil1123-vip/padm/.github/workflows/create_release.yml@refs/heads/main" and
    .issuer == "https://token.actions.githubusercontent.com"
' "$3" >/dev/null
EOF
cat >"${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target= url=
while [[ "$#" -gt 0 ]]; do
    case "$1" in
    -o) target=$2; shift 2 ;;
    --connect-timeout|--max-time|--max-filesize) shift 2 ;;
    -*) shift ;;
    *) url=$1; shift ;;
    esac
done
printf '%s\n' "${url}" >>"${FAKE_DOWNLOAD_LOG:?}"
[[ "${FAKE_DOWNLOAD_FAIL:-0}" != 1 ]] || exit 1
case "${url}" in
https://example.invalid/release-manifest.json) source=${FAKE_MANIFEST:?} ;;
https://example.invalid/release-manifest.sigstore.json) source=${FAKE_SIGNATURE:?} ;;
https://example.invalid/control.tar.gz) source=${FAKE_CONTROL_BUNDLE:?} ;;
*) exit 1 ;;
esac
cp -- "${source}" "${target}"
EOF
cat >"${MOCK_BIN}/wget" <<'EOF'
#!/usr/bin/env bash
printf 'wget-fallback\n' >>"${FAKE_DOWNLOAD_LOG:?}"
exit 1
EOF
chmod 0755 "${MOCK_BIN}/"*

export PATH="${MOCK_BIN}:${PATH}" MSYS=winsymlinks:sys DOCKER_HOST=
export PADM_NATIVE_INSTALL_DIR="${TEST_ROOT}/native"
export PADM_DOCKER_INSTALL_DIR="${STATE_ROOT}" PADM_DOCKER_BIN_DIR="${TEST_ROOT}/installed-bin"
export PADM_DOCKER_LOCK_TIMEOUT=1
export FAKE_PULL_LOG="${PULL_LOG}" FAKE_VERIFY_LOG="${VERIFY_LOG}" FAKE_DOWNLOAD_LOG="${DOWNLOAD_LOG}"
export FAKE_MANIFEST="${MANIFEST}" FAKE_SIGNATURE="${SIGNATURE}" FAKE_CONTROL_BUNDLE="${CONTROL_BUNDLE}"

copyControl() {
    local target=$1 relative
    for relative in \
        install-docker.sh docker/lib/bootstrap.sh docker/lib/bundle.sh docker/lib/manifest.sh \
        docker/lib/services.sh docker/lib/traffic.sh docker/lib/renewal.sh docker/lib/lifecycle.sh docker/lib/setup.sh docker/lib/accounts.sh docker/lib/subscriptions.sh docker/lib/business.sh docker/lib/menu.sh docker/lib/reality-targets.sh \
        docker/contracts/configure.schema.json docker/contracts/deployment.schema.json \
        docker/contracts/features.json shell/core/deployment_mode.sh shell/core/stats_grpc.sh shell/core/runtime.sh shell/core/reality_targets.sh shell/core/cores.sh; do
        mkdir -p "${target}/$(dirname -- "${relative}")"
        cp "${PROJECT_ROOT}/${relative}" "${target}/${relative}"
    done
}

copyControl "${SOURCE_ROOT}"
copyControl "${CONTROL_ROOT}"
printf 'candidate-only\n' >"${CONTROL_ROOT}/docker/release-sentinel"
tar -czf "${CONTROL_BUNDLE}" -C "${CONTROL_ROOT}" install-docker.sh docker shell
CONTROL_SHA=$(sha256sum "${CONTROL_BUNDLE}" | cut -d ' ' -f 1)
jq -n --arg sha "${CONTROL_SHA}" '
    def image($name): {
        reference: ("ghcr.io/example/padm-" + $name + ":3.2.0@sha256:" + ("2" * 64)),
        index_digest: ("sha256:" + ("2" * 64)),
        platforms: {"linux/amd64": ("sha256:" + ("4" * 64)), "linux/arm64": ("sha256:" + ("5" * 64))}
    };
    {schema_version: 1, release: {version: "3.2.0", commit: ("a" * 40), created_at: "2026-10-05T00:00:00Z"},
     control: {bundle_url: "https://example.invalid/control.tar.gz", sha256: $sha, min_version: "3.2.0"},
     images: {xray: image("xray"), "sing-box": image("sing-box"), nginx: image("nginx"), ops: image("ops"), net: image("net")},
     upstream: {alpine: "3", xray: "1", sing_box: "1", nginx: "1", acme_sh: "1"},
     formats: {compose: 1, config: 1, data: 1},
     compatibility: {host: ["linux", "rootful-docker", "compose-v2"], architectures: ["amd64", "arm64"], profiles: ["core-xray"], features_version: 1},
     migrations: []}
' >"${MANIFEST}"

signFixture() {
    local manifest=$1 signature=$2
    jq -n --arg sha "$(sha256sum "${manifest}" | cut -d ' ' -f 1)" \
        --arg identity "${IDENTITY}" --arg issuer "${ISSUER}" \
        '{signature:"fixture-valid",manifest_sha256:$sha,identity:$identity,issuer:$issuer}' >"${signature}"
}
signFixture "${MANIFEST}" "${SIGNATURE}"

CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
bash -u "${PROJECT_ROOT}/install-docker.sh" install --no-menu --source "${SOURCE_ROOT}" \
    --ref ffffffffffffffffffffffffffffffffffffffff >"${OUT}" 2>"${ERR}" || fail 'initial install failed'
printf 'keep-config\n' >"${STATE_ROOT}/config/sentinel"
printf 'keep-data\n' >"${STATE_ROOT}/data/sentinel"
printf 'keep-secret\n' >"${STATE_ROOT}/secrets/sentinel"
printf '{"keep":"deployment"}\n' >"${STATE_ROOT}/deployment.json"

snapshotState() {
    local path
    find "${STATE_ROOT}" -printf '%P %y %l\n' | LC_ALL=C sort
    while IFS= read -r path; do sha256sum "${path}"; done \
        < <(find "${STATE_ROOT}" -type f -print | LC_ALL=C sort)
}
BASELINE=$(snapshotState)

runRelease() {
    local expected=$1 name=$2 actual=0
    shift 2
    : >"${PULL_LOG}"; : >"${VERIFY_LOG}"; : >"${DOWNLOAD_LOG}"
    bash -u "${CLI}" release "$@" >"${OUT}" 2>"${ERR}" || actual=$?
    [[ "${actual}" -eq "${expected}" ]] || fail "${name}: expected rc=${expected}, got rc=${actual}"
    [[ "$(snapshotState)" == "${BASELINE}" ]] || fail "${name}: changed deployment, bundle, locks or temporary state"
    if [[ "${expected}" -ne 0 ]]; then
        [[ ! -s "${OUT}" ]] || fail "${name}: emitted trusted output after failure"
    fi
}

assertSuccess() {
    local expectedSha
    expectedSha=$(sha256sum "${MANIFEST}" | cut -d ' ' -f 1)
    jq -e --arg sha "${expectedSha}" --arg identity "${IDENTITY}" '
        (keys | sort) == ["images","release"] and
        .release == {version:"3.2.0",manifest_sha256:$sha,signature_identity:$identity} and
        (.images | keys | sort) == ["net","nginx","ops","sing-box","xray"] and
        all(.images[]; type == "string" and test("^ghcr.io/example/padm-[a-z-]+:3[.]2[.]0@sha256:[2]{64}$"))
    ' "${OUT}" >/dev/null || fail 'successful output was not the exact release/images contract'
    [[ "$(jq -s length "${OUT}")" -eq 1 ]] || fail 'stdout contained more than one JSON result'
    [[ "$(wc -l <"${VERIFY_LOG}")" -eq 1 ]] || fail 'signature was not verified exactly once'
    [[ "$(wc -l <"${PULL_LOG}")" -eq 5 ]] || fail 'did not pull exactly five images'
    cmp -s <(jq -r '.images | .xray.reference, ."sing-box".reference, .nginx.reference, .ops.reference, .net.reference' "${MANIFEST}") \
        "${PULL_LOG}" || fail 'pulled images did not match the verified manifest'
    grep -Fq 'mock-pull:' "${ERR}" || fail 'pull progress was not routed to stderr'
}

runRelease 0 local-amd64 --manifest "${MANIFEST}" --bundle "${SIGNATURE}" --control-bundle "${CONTROL_BUNDLE}"
assertSuccess
[[ ! -s "${DOWNLOAD_LOG}" ]] || fail 'local assets caused a download'

export FAKE_ARCH=aarch64
runRelease 0 https-arm64 --manifest https://example.invalid/release-manifest.json
assertSuccess
[[ "$(wc -l <"${DOWNLOAD_LOG}")" -eq 3 ]] || fail 'HTTPS assets were not all fetched'
unset FAKE_ARCH

for fault in signature identity issuer; do
    jq --arg fault "${fault}" '.[ $fault ] = "untrusted"' "${SIGNATURE}" >"${TEST_ROOT}/bad-signature.json"
    runRelease 16 "bad-${fault}" --manifest "${MANIFEST}" --bundle "${TEST_ROOT}/bad-signature.json" \
        --control-bundle "${CONTROL_BUNDLE}"
    [[ ! -s "${PULL_LOG}" ]] || fail "bad-${fault}: pulled untrusted images"
    grep -Fq 'Cosign 验签失败' "${ERR}" || fail "bad-${fault}: missing verification error"
done

for fault in schema digest format; do
    case "${fault}" in
    schema) jq '.unexpected = true' "${MANIFEST}" >"${TEST_ROOT}/bad-manifest.json" ;;
    digest) jq '.images.xray.index_digest = ("sha256:" + ("3" * 64))' "${MANIFEST}" >"${TEST_ROOT}/bad-manifest.json" ;;
    format) jq '.formats.config = 2' "${MANIFEST}" >"${TEST_ROOT}/bad-manifest.json" ;;
    esac
    signFixture "${TEST_ROOT}/bad-manifest.json" "${TEST_ROOT}/bad-manifest.sigstore.json"
    runRelease 16 "bad-${fault}" --manifest "${TEST_ROOT}/bad-manifest.json" \
        --bundle "${TEST_ROOT}/bad-manifest.sigstore.json" --control-bundle "${CONTROL_BUNDLE}"
    [[ ! -s "${PULL_LOG}" && ! -s "${VERIFY_LOG}" ]] || fail "bad-${fault}: schema gate did not reject before signature and pulls"
done

for flag in --manifest --bundle --control-bundle --unknown; do
    runRelease 2 "invalid-argument-${flag}" "${flag}"
    [[ ! -s "${PULL_LOG}" && ! -s "${VERIFY_LOG}" && ! -s "${DOWNLOAD_LOG}" ]] ||
        fail "invalid-argument-${flag}: reached release asset processing"
done

export FAKE_ARCH=riscv64
runRelease 10 unsupported-host --manifest "${MANIFEST}" --bundle "${SIGNATURE}" \
    --control-bundle "${CONTROL_BUNDLE}"
[[ ! -s "${PULL_LOG}" && ! -s "${VERIFY_LOG}" && ! -s "${DOWNLOAD_LOG}" ]] ||
    fail 'unsupported architecture reached release asset processing'
unset FAKE_ARCH

printf 'wrong-control\n' >"${TEST_ROOT}/wrong-control.tar.gz"
runRelease 16 wrong-control-digest --manifest "${MANIFEST}" --bundle "${SIGNATURE}" \
    --control-bundle "${TEST_ROOT}/wrong-control.tar.gz"
[[ ! -s "${PULL_LOG}" ]] || fail 'control digest failure pulled images'

# 摘要正确也不能接受非归档、越界路径或不完整控制脚本。
mkdir "${TEST_ROOT}/incomplete"
printf 'incomplete\n' >"${TEST_ROOT}/incomplete/install-docker.sh"
tar -czf "${TEST_ROOT}/incomplete-control.tar.gz" -C "${TEST_ROOT}/incomplete" install-docker.sh
tar -czf "${TEST_ROOT}/unsafe-control.tar.gz" --transform='s|^install-docker.sh$|../outside-control|' \
    -C "${CONTROL_ROOT}" install-docker.sh
for fault in wrong incomplete unsafe; do
    badControl="${TEST_ROOT}/${fault}-control.tar.gz"
    jq --arg sha "$(sha256sum "${badControl}" | cut -d ' ' -f 1)" \
        '.control.sha256 = $sha' "${MANIFEST}" >"${TEST_ROOT}/bad-control-manifest.json"
    signFixture "${TEST_ROOT}/bad-control-manifest.json" "${TEST_ROOT}/bad-control-manifest.sigstore.json"
    runRelease 13 "${fault}-control" --manifest "${TEST_ROOT}/bad-control-manifest.json" \
        --bundle "${TEST_ROOT}/bad-control-manifest.sigstore.json" --control-bundle "${badControl}"
    [[ ! -s "${PULL_LOG}" ]] || fail "${fault}-control: pulled images before bundle validation"
done

export FAKE_PULL_FAIL=1
runRelease 14 pull-failure --manifest "${MANIFEST}" --bundle "${SIGNATURE}" --control-bundle "${CONTROL_BUNDLE}"
[[ "$(wc -l <"${PULL_LOG}")" -eq 1 ]] || fail 'pull failure did not stop at the failing image'
unset FAKE_PULL_FAIL

export FAKE_DOWNLOAD_FAIL=1
runRelease 16 download-failure --manifest https://example.invalid/release-manifest.json
[[ ! -s "${VERIFY_LOG}" && ! -s "${PULL_LOG}" ]] || fail 'download failure reached signature or image pull'
unset FAKE_DOWNLOAD_FAIL

# 独立 PATH 排除真实宿主 cosign，不能依赖 CI 恰好没有安装验证器。
NO_COSIGN_BIN="${TEST_ROOT}/no-cosign-bin"
mkdir "${NO_COSIGN_BIN}"
for tool in bash uname id docker curl wget jq sha256sum tar readlink dirname basename \
    mkdir chmod find sort cp awk cut mktemp rm rmdir cat date stat sleep cmp wc head uniq tr sed env; do
    ln -s "$(command -v "${tool}")" "${NO_COSIGN_BIN}/${tool}"
done
PATH="${NO_COSIGN_BIN}" runRelease 16 missing-cosign --manifest "${MANIFEST}" \
    --bundle "${SIGNATURE}" --control-bundle "${CONTROL_BUNDLE}"
[[ ! -s "${PULL_LOG}" && ! -s "${DOWNLOAD_LOG}" ]] || fail 'missing cosign reached pull or download'
grep -Fq cosign "${ERR}" && grep -Eq '受信|核验|独立' "${ERR}" ||
    fail 'missing cosign did not explain trusted installation'

printf 'docker-release-regression-ok\n'
