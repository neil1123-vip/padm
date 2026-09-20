#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
test_root=$(mktemp -d "${project_root}/.tmp-preflight-test.XXXXXX")
trap 'rm -rf -- "${test_root}"' EXIT
fail() { printf 'preflight-test: %s\n' "$*" >&2; exit 1; }
mkdir -p "${test_root}/project/docker" "${test_root}/project/shell/core" "${test_root}/bin"
cp "${project_root}/docker/release.sh" "${test_root}/project/docker/release.sh"
cp "${project_root}/versions.lock" "${test_root}/project/versions.lock"
cp "${project_root}/shell/core/version.sh" "${test_root}/project/shell/core/version.sh"
cp "${test_root}/project/versions.lock" "${test_root}/lock.before"
cp "${test_root}/project/shell/core/version.sh" "${test_root}/version.before"
    # shellcheck source=/dev/null
. "${test_root}/project/versions.lock"

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
[[ -n "${output}" && "${url}" == "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_MINOR}/"* ]]
printf '%s\n' "${url}" >>"${FIXTURE_ROOT}/calls"
repo=$(case "${url}" in */main/*) printf main ;; */community/*) printf community ;; *) exit 1 ;; esac)
arch=$(case "${url}" in */x86_64/*) printf x86_64 ;; */aarch64/*) printf aarch64 ;; *) exit 1 ;; esac)
if [[ "${SCENARIO}" == network && "${arch}:${repo}" == aarch64:main ]]; then
    printf 'simulated network failure\n' >&2
    exit 22
fi
cp "${FIXTURE_ROOT}/${repo}-${arch}.tar.gz" "${output}"
EOF
chmod +x "${test_root}/bin/curl"

for scenario in available missing-amd64 missing-arm64 wrong-version corrupt invalid-index network; do
    fixture_root=${test_root}/${scenario}
    mkdir -p "${fixture_root}"
    for arch in x86_64 aarch64; do
        for repo in main community; do
            mkdir -p "${fixture_root}/${repo}-${arch}"
            index=${fixture_root}/${repo}-${arch}/APKINDEX
            : >"${index}"
            for package in ca-certificates gcompat libgcc unzip nginx python3 openssl socat bash iproute2 iptables nftables wireguard-tools fail2ban; do
                # community 独有包与可用的旧版本均须接受，不能只检查 main 或最新版本。
                [[ ( "${package}" == fail2ban && "${repo}" == community ) ||
                    ( "${package}" != fail2ban && "${repo}" == main ) ]] || continue
                key=${package^^}
                key=PADM_LOCK_${key//-/_}_VERSION
                [[ "${package}" != nginx ]] || key=PADM_LOCK_NGINX_PACKAGE_VERSION
                expected=${!key}
                if [[ "${package}" == ca-certificates &&
                    ( "${scenario}:${arch}" == missing-amd64:x86_64 || "${scenario}:${arch}" == missing-arm64:aarch64 ) ]]; then
                    continue
                fi
                if [[ "${package}:${scenario}:${arch}" == ca-certificates:wrong-version:aarch64 ]]; then
                    expected=19990101-r0
                fi
                printf 'P:%s\nV:%s\n\nP:%s\nV:9999.0-r0\n\n' "${package}" "${expected}" "${package}" >>"${index}"
            done
            if [[ "${scenario}:${repo}:${arch}" == invalid-index:community:aarch64 ]]; then
                printf 'P:broken-without-version\n\n' >>"${index}"
            fi
            tar -czf "${fixture_root}/${repo}-${arch}.tar.gz" -C "${fixture_root}/${repo}-${arch}" APKINDEX
        done
    done
    [[ "${scenario}" != corrupt ]] || printf 'invalid tar archive\n' >"${fixture_root}/community-aarch64.tar.gz"
    actual=success
    PATH="${test_root}/bin:${PATH}" FIXTURE_ROOT="${fixture_root}" SCENARIO="${scenario}" \
        ALPINE_MINOR="${PADM_LOCK_ALPINE_VERSION%.*}" \
        bash "${test_root}/project/docker/release.sh" preflight >"${fixture_root}/output" 2>&1 || actual=failure
    if [[ "${scenario}" == available ]]; then
        [[ "${actual}" == success ]] || { cat "${fixture_root}/output"; fail 'available locked APKs rejected'; }
        grep -Fxq 'release-preflight-ok' "${fixture_root}/output" || fail 'success not reported'
        [[ "$(wc -l <"${fixture_root}/calls")" -eq 4 ]] || fail 'both architectures and repositories were not checked'
    else
        [[ "${actual}" == failure ]] || fail "${scenario} passed"
        grep -Fq 'Refresh Upstream Versions' "${fixture_root}/output" || fail "${scenario}: missing recovery hint"
        case "${scenario}" in
        missing-amd64) grep -Fq "x86_64 locked APK ca-certificates=${PADM_LOCK_CA_CERTIFICATES_VERSION} is unavailable" "${fixture_root}/output" ;;
        missing-arm64|wrong-version) grep -Fq "aarch64 locked APK ca-certificates=${PADM_LOCK_CA_CERTIFICATES_VERSION} is unavailable" "${fixture_root}/output" ;;
        corrupt|invalid-index) grep -Fq 'community/aarch64 APK index' "${fixture_root}/output" ;;
        network) grep -Fq 'failed to download Alpine' "${fixture_root}/output" && grep -Fq 'simulated network failure' "${fixture_root}/output" ;;
        esac || { cat "${fixture_root}/output"; fail "${scenario}: wrong failure"; }
    fi
    cmp -s "${test_root}/lock.before" "${test_root}/project/versions.lock" || fail "${scenario}: lock changed"
    cmp -s "${test_root}/version.before" "${test_root}/project/shell/core/version.sh" || fail "${scenario}: script version changed"
done

printf 'preflight-regression-ok\n'
