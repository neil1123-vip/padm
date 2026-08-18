#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
LOCK_FILE=${PROJECT_ROOT}/versions.lock
VERSION_FILE=${PROJECT_ROOT}/shell/core/version.sh
MANIFEST_SCHEMA=${PROJECT_ROOT}/docker/contracts/release-manifest.schema.json
IMAGE_NAMES=(xray sing-box nginx ops net)

die() {
    printf 'padm-release: %s\n' "$*" >&2
    exit 1
}

is_semver() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

is_digest() {
    [[ "$1" =~ ^sha256:[0-9a-f]{64}$ ]]
}

load_lock() {
    [[ -f "${LOCK_FILE}" && ! -L "${LOCK_FILE}" ]] || die 'versions.lock is missing or unsafe'
    set -a
    # shellcheck disable=SC1090
    . "${LOCK_FILE}"
    set +a
}

script_version() {
    sed -n 's/^SCRIPT_VERSION="\([^"]*\)"$/\1/p' "${VERSION_FILE}" | head -n 1
}

validate_lock() {
    local expected=${1:-} variable scriptVersion
    [[ -f "${VERSION_FILE}" && ! -L "${VERSION_FILE}" ]] || die 'version file is missing or unsafe'
    grep -Env '^(#.*|[[:space:]]*|PADM_LOCK_[A-Z0-9_]+=[A-Za-z0-9._:/@,+-]+)$' \
        "${LOCK_FILE}" >/dev/null && die 'versions.lock contains unsafe syntax' || true
    load_lock
    for variable in \
        PADM_LOCK_SCHEMA PADM_LOCK_PLATFORM_AMD64 PADM_LOCK_PLATFORM_ARM64 \
        PADM_LOCK_VERSION PADM_LOCK_SOURCE_URL PADM_LOCK_ALPINE_VERSION PADM_LOCK_ALPINE_BASE \
        PADM_LOCK_CA_CERTIFICATES_VERSION PADM_LOCK_GCOMPAT_VERSION PADM_LOCK_XRAY_VERSION PADM_LOCK_XRAY_AMD64_ASSET \
        PADM_LOCK_XRAY_AMD64_SHA256 PADM_LOCK_XRAY_ARM64_ASSET PADM_LOCK_XRAY_ARM64_SHA256 \
        PADM_LOCK_UNZIP_VERSION PADM_LOCK_SING_BOX_VERSION PADM_LOCK_SING_BOX_AMD64_ASSET \
        PADM_LOCK_SING_BOX_AMD64_SHA256 PADM_LOCK_SING_BOX_ARM64_ASSET PADM_LOCK_SING_BOX_ARM64_SHA256 \
        PADM_LOCK_NGINX_VERSION PADM_LOCK_NGINX_PACKAGE_VERSION PADM_LOCK_ACME_SH_VERSION \
        PADM_LOCK_ACME_SH_URL PADM_LOCK_ACME_SH_SHA256 PADM_LOCK_PYTHON3_VERSION \
        PADM_LOCK_OPENSSL_VERSION PADM_LOCK_SOCAT_VERSION PADM_LOCK_BASH_VERSION \
        PADM_LOCK_IPROUTE2_VERSION PADM_LOCK_IPTABLES_VERSION PADM_LOCK_NFTABLES_VERSION \
        PADM_LOCK_WIREGUARD_TOOLS_VERSION PADM_LOCK_FAIL2BAN_VERSION PADM_LOCK_PATCHES; do
        [[ -n "${!variable:-}" ]] || die "missing lock variable: ${variable}"
    done
    [[ "${PADM_LOCK_SCHEMA}" == 1 ]] || die 'unsupported lock schema'
    [[ "${PADM_LOCK_PLATFORM_AMD64}" == linux/amd64 &&
        "${PADM_LOCK_PLATFORM_ARM64}" == linux/arm64 ]] || die 'platform lock drifted'
    scriptVersion=$(script_version)
    is_semver "${scriptVersion}" || die 'script version is not semver'
    [[ "${PADM_LOCK_VERSION}" == "${scriptVersion}" ]] || die 'lock version differs from script version'
    if [[ -n "${expected}" ]]; then
        is_semver "${expected}" || die 'requested version is not semver'
        [[ "${expected}" == "${scriptVersion}" ]] || die 'requested version differs from source'
    fi
    [[ "${PADM_LOCK_ALPINE_BASE}" =~ ^alpine:[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}$ ]] ||
        die 'Alpine base is not pinned by digest'
    for variable in \
        PADM_LOCK_XRAY_AMD64_SHA256 PADM_LOCK_XRAY_ARM64_SHA256 \
        PADM_LOCK_SING_BOX_AMD64_SHA256 PADM_LOCK_SING_BOX_ARM64_SHA256 \
        PADM_LOCK_ACME_SH_SHA256; do
        [[ "${!variable}" =~ ^[0-9a-f]{64}$ ]] || die "invalid checksum: ${variable}"
    done
    [[ "${PADM_LOCK_PATCHES}" == none ]] || die 'unreviewed build patches are not allowed'
}

set_version() {
    local version=$1 tmpRoot
    is_semver "${version}" || die 'version must be X.Y.Z'
    validate_lock
    tmpRoot=$(mktemp -d "${TMPDIR:-/tmp}/padm-release-version.XXXXXX")
    trap 'rm -rf -- "${tmpRoot}"' RETURN
    awk -v version="${version}" '
        BEGIN { replaced = 0 }
        /^SCRIPT_VERSION=/ {
            print "SCRIPT_VERSION=\"" version "\""
            replaced = 1
            next
        }
        { print }
        END { if (!replaced) exit 1 }
    ' "${VERSION_FILE}" >"${tmpRoot}/version.sh" || die 'failed to update script version'
    awk -v version="${version}" '
        BEGIN { replaced = 0 }
        /^PADM_LOCK_VERSION=/ {
            print "PADM_LOCK_VERSION=" version
            replaced = 1
            next
        }
        { print }
        END { if (!replaced) exit 1 }
    ' "${LOCK_FILE}" >"${tmpRoot}/versions.lock" || die 'failed to update lock version'
    mv -- "${tmpRoot}/version.sh" "${VERSION_FILE}"
    mv -- "${tmpRoot}/versions.lock" "${LOCK_FILE}"
    trap - RETURN
    rm -rf -- "${tmpRoot}"
    validate_lock "${version}"
}

manifest_validate() {
    local manifest=$1
    [[ -f "${manifest}" && ! -L "${manifest}" ]] || die 'manifest is missing or unsafe'
    jq -e '
      def exact($keys): (keys_unsorted | sort) == ($keys | sort);
      def semver: type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$");
      def digest: type == "string" and test("^sha256:[0-9a-f]{64}$");
      def ref: type == "string" and test("^[a-z0-9][a-z0-9._/-]+:[A-Za-z0-9._-]+@sha256:[0-9a-f]{64}$");
      def image:
        type == "object" and exact(["reference", "index_digest", "platforms"]) and
        (.reference | ref) and (.index_digest | digest) and
        (.platforms as $p |
          ($p | type == "object" and exact(["linux/amd64", "linux/arm64"])) and
          ($p["linux/amd64"] | digest) and ($p["linux/arm64"] | digest));
      . as $m |
      type == "object" and
      exact(["schema_version", "release", "control", "images", "upstream", "formats", "compatibility", "migrations"]) and
      .schema_version == 1 and
      (.release | type == "object" and exact(["version", "commit", "created_at"]) and
        (.version | semver) and (.commit | type == "string" and test("^[0-9a-f]{40}$")) and
        (.created_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))) and
      (.control | type == "object" and exact(["bundle_url", "sha256", "min_version"]) and
        (.bundle_url | type == "string" and test("^https://")) and
        (.sha256 | type == "string" and test("^[0-9a-f]{64}$")) and (.min_version | semver)) and
      (.images | type == "object" and exact(["xray", "sing-box", "nginx", "ops", "net"]) and
        (.xray | image) and (."sing-box" | image) and (.nginx | image) and (.ops | image) and (.net | image)) and
      (.upstream | type == "object" and exact(["alpine", "xray", "sing_box", "nginx", "acme_sh"]) and
        all(.[]; type == "string" and length > 0)) and
      (.formats | type == "object" and exact(["compose", "config", "data"]) and
        all(.[]; type == "number" and floor == . and . == 1)) and
      (.compatibility | type == "object" and exact(["host", "architectures", "profiles", "features_version"]) and
        .host == ["linux", "rootful-docker", "compose-v2"] and
        .architectures == ["amd64", "arm64"] and
        (.profiles | type == "array" and length > 0 and all(.[]; type == "string")) and
        .features_version == 1) and
      (.migrations | type == "array" and all(.[];
        type == "object" and exact(["id", "direction", "reversible"]) and
        (.id | type == "string" and test("^[a-z0-9][a-z0-9._-]*$")) and
        (.direction == "forward" or .direction == "none") and (.reversible | type == "boolean")))
    ' "${manifest}" >/dev/null || die 'release manifest does not satisfy schema contract'
    jq -ne --slurpfile schema "${MANIFEST_SCHEMA}" \
        '($schema[0] | type == "object" and ((."$id" // "") | type == "string" and length > 0))' \
        >/dev/null ||
        die 'release manifest schema file is invalid'
}

manifest_generate() {
    local version= commit= createdAt= registry= bundleUrl= bundleSha256= resultsDir= output=
    local name resultFile tmpRoot
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --version) version=${2:-}; shift 2 ;;
        --commit) commit=${2:-}; shift 2 ;;
        --created-at) createdAt=${2:-}; shift 2 ;;
        --registry) registry=${2:-}; shift 2 ;;
        --bundle-url) bundleUrl=${2:-}; shift 2 ;;
        --bundle-sha256) bundleSha256=${2:-}; shift 2 ;;
        --results-dir) resultsDir=${2:-}; shift 2 ;;
        --output) output=${2:-}; shift 2 ;;
        *) die "unknown manifest option: $1" ;;
        esac
    done
    is_semver "${version}" || die 'manifest version must be X.Y.Z'
    [[ "${commit}" =~ ^[0-9a-f]{40}$ ]] || die 'manifest commit must be a full SHA'
    [[ "${createdAt}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] ||
        die 'manifest created-at must be UTC RFC3339'
    [[ "${registry}" =~ ^[a-z0-9][a-z0-9._/-]*$ ]] || die 'manifest registry is invalid'
    [[ "${bundleUrl}" =~ ^https:// ]] || die 'manifest bundle URL must use HTTPS'
    [[ "${bundleSha256}" =~ ^[0-9a-f]{64}$ ]] || die 'manifest bundle SHA-256 is invalid'
    [[ -d "${resultsDir}" && -n "${output}" ]] || die 'manifest results directory and output are required'
    load_lock
    [[ "${version}" == "${PADM_LOCK_VERSION}" ]] || die 'manifest version differs from versions.lock'
    for name in "${IMAGE_NAMES[@]}"; do
        resultFile=${resultsDir}/${name}.json
        [[ -f "${resultFile}" && ! -L "${resultFile}" ]] || die "missing image result: ${name}"
        jq -e --arg name "${name}" --arg registry "${registry}" --arg version "${version}" '
          type == "object" and
          (keys_unsorted | sort) == ["index_digest", "name", "platforms", "reference"] and
          .name == $name and (.reference | type == "string" and
            startswith($registry + "/padm-" + $name + ":" + $version + "@sha256:") and
            test("^[a-z0-9][a-z0-9._/-]+:[A-Za-z0-9._-]+@sha256:[0-9a-f]{64}$")) and
          (.index_digest | test("^sha256:[0-9a-f]{64}$")) and
          (.platforms | type == "object" and (keys_unsorted | sort) == ["linux/amd64", "linux/arm64"] and
            all(.[]; test("^sha256:[0-9a-f]{64}$")))
        ' "${resultFile}" >/dev/null || die "invalid image result: ${name}"
    done
    tmpRoot=$(mktemp -d "${TMPDIR:-/tmp}/padm-release-manifest.XXXXXX")
    trap 'rm -rf -- "${tmpRoot}"' RETURN
    jq -n \
        --arg version "${version}" \
        --arg commit "${commit}" \
        --arg createdAt "${createdAt}" \
        --arg bundleUrl "${bundleUrl}" \
        --arg bundleSha256 "${bundleSha256}" \
        --slurpfile xray "${resultsDir}/xray.json" \
        --slurpfile singBox "${resultsDir}/sing-box.json" \
        --slurpfile nginx "${resultsDir}/nginx.json" \
        --slurpfile ops "${resultsDir}/ops.json" \
        --slurpfile net "${resultsDir}/net.json" \
        --arg alpine "${PADM_LOCK_ALPINE_VERSION}" \
        --arg xrayVersion "${PADM_LOCK_XRAY_VERSION}" \
        --arg singBoxVersion "${PADM_LOCK_SING_BOX_VERSION}" \
        --arg nginxVersion "${PADM_LOCK_NGINX_VERSION}" \
        --arg acmeVersion "${PADM_LOCK_ACME_SH_VERSION}" \
        ' {
          schema_version: 1,
          release: {version: $version, commit: $commit, created_at: $createdAt},
          control: {bundle_url: $bundleUrl, sha256: $bundleSha256, min_version: $version},
          images: {
            xray: ($xray[0] | {reference, index_digest, platforms}),
            "sing-box": ($singBox[0] | {reference, index_digest, platforms}),
            nginx: ($nginx[0] | {reference, index_digest, platforms}),
            ops: ($ops[0] | {reference, index_digest, platforms}),
            net: ($net[0] | {reference, index_digest, platforms})
          },
          upstream: {alpine: $alpine, xray: $xrayVersion, sing_box: $singBoxVersion,
            nginx: $nginxVersion, acme_sh: $acmeVersion},
          formats: {compose: 1, config: 1, data: 1},
          compatibility: {
            host: ["linux", "rootful-docker", "compose-v2"],
            architectures: ["amd64", "arm64"],
            profiles: ["core-xray", "core-sing-box", "nginx", "subscription", "acme",
              "net-wireguard", "net-fail2ban", "net-transparent"],
            features_version: 1
          },
          migrations: []
        }' >"${tmpRoot}/manifest.json"
    manifest_validate "${tmpRoot}/manifest.json"
    mkdir -p -- "$(dirname -- "${output}")"
    mv -- "${tmpRoot}/manifest.json" "${output}"
    trap - RETURN
    rm -rf -- "${tmpRoot}"
}

usage() {
    cat >&2 <<'EOF'
usage:
  docker/release.sh validate-lock [VERSION]
  docker/release.sh set-version VERSION
  docker/release.sh validate-manifest FILE
  docker/release.sh manifest --version VERSION --commit SHA --created-at UTC \
    --registry REGISTRY --bundle-url URL --bundle-sha256 SHA256 \
    --results-dir DIR --output FILE
EOF
}

case "${1:-}" in
validate-lock)
    shift
    [[ "$#" -le 1 ]] || { usage; exit 2; }
    validate_lock "${1:-}"
    printf 'release-lock-ok\n'
    ;;
set-version)
    [[ "$#" -eq 2 ]] || { usage; exit 2; }
    set_version "$2"
    ;;
validate-manifest)
    [[ "$#" -eq 2 ]] || { usage; exit 2; }
    manifest_validate "$2"
    printf 'release-manifest-ok\n'
    ;;
manifest)
    shift
    manifest_generate "$@"
    ;;
*)
    usage
    exit 2
    ;;
esac
