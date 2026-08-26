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

is_newer_semver() {
    local current=$1 candidate=$2
    [[ "${current}" != "${candidate}" &&
        "$(printf '%s\n%s\n' "${current}" "${candidate}" | sort -V | tail -n 1)" == "${candidate}" ]]
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
    local expected=${1:-} variable scriptVersion singBoxVersion
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
    [[ "${PADM_LOCK_XRAY_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'invalid Xray version'
    [[ "${PADM_LOCK_XRAY_AMD64_ASSET}" == Xray-linux-64.zip &&
        "${PADM_LOCK_XRAY_ARM64_ASSET}" == Xray-linux-arm64-v8a.zip ]] || die 'invalid Xray assets'
    [[ "${PADM_LOCK_SING_BOX_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'invalid sing-box version'
    singBoxVersion=${PADM_LOCK_SING_BOX_VERSION#v}
    [[ "${PADM_LOCK_SING_BOX_AMD64_ASSET}" == "sing-box-${singBoxVersion}-linux-amd64.tar.gz" &&
        "${PADM_LOCK_SING_BOX_ARM64_ASSET}" == "sing-box-${singBoxVersion}-linux-arm64.tar.gz" ]] ||
        die 'invalid sing-box assets'
    [[ "${PADM_LOCK_ACME_SH_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'invalid acme.sh version'
    [[ "${PADM_LOCK_ACME_SH_URL}" == "https://codeload.github.com/acmesh-official/acme.sh/tar.gz/refs/tags/${PADM_LOCK_ACME_SH_VERSION}" ||
        "${PADM_LOCK_ACME_SH_URL}" == "https://codeload.github.com/acmesh-official/acme.sh/tar.gz/refs/tags/v${PADM_LOCK_ACME_SH_VERSION}" ]] ||
        die 'invalid acme.sh URL'
    for variable in \
        PADM_LOCK_XRAY_AMD64_SHA256 PADM_LOCK_XRAY_ARM64_SHA256 \
        PADM_LOCK_SING_BOX_AMD64_SHA256 PADM_LOCK_SING_BOX_ARM64_SHA256 \
        PADM_LOCK_ACME_SH_SHA256; do
        [[ "${!variable}" =~ ^[0-9a-f]{64}$ ]] || die "invalid checksum: ${variable}"
    done
    [[ "${PADM_LOCK_PATCHES}" == none ]] || die 'unreviewed build patches are not allowed'
}

latest_release_tag() {
    local repository=$1 release tag
    release=$(gh api "repos/${repository}/releases/latest") || die "failed to query ${repository} release"
    tag=$(jq -er 'select(.draft == false and .prerelease == false) | .tag_name | select(type == "string")' \
        <<<"${release}") || die "${repository} has no stable release"
    printf '%s\n' "${tag}"
}

download_sha256() {
    local url=$1 output=$2
    curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 300 \
        --max-filesize 134217728 --output "${output}" "${url}" || return 1
    [[ -s "${output}" ]] || return 1
    sha256sum "${output}" | awk '{print $1}'
}

refresh_upstreams() {
    local tool xrayTag singBoxTag singBoxVersion acmeTag acmeVersion tmpRoot changed=false
    local xrayVersion xrayAmd64Asset xrayAmd64Sha256 xrayArm64Asset xrayArm64Sha256
    local singBoxAmd64Asset singBoxAmd64Sha256 singBoxArm64Asset singBoxArm64Sha256 acmeUrl acmeSha256
    local updateXray=false updateSingBox=false updateAcme=false
    for tool in gh jq curl sha256sum sort tail awk; do
        command -v "${tool}" >/dev/null 2>&1 || die "missing upstream refresh tool: ${tool}"
    done
    validate_lock

    xrayTag=$(latest_release_tag XTLS/Xray-core)
    singBoxTag=$(latest_release_tag SagerNet/sing-box)
    acmeTag=$(latest_release_tag acmesh-official/acme.sh)
    [[ "${xrayTag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid Xray release tag: ${xrayTag}"
    [[ "${singBoxTag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid sing-box release tag: ${singBoxTag}"
    [[ "${acmeTag}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid acme.sh release tag: ${acmeTag}"
    singBoxVersion=${singBoxTag#v}
    acmeVersion=${acmeTag#v}

    if [[ "${xrayTag#v}" == "${PADM_LOCK_XRAY_VERSION#v}" ]]; then
        :
    elif is_newer_semver "${PADM_LOCK_XRAY_VERSION#v}" "${xrayTag#v}"; then
        updateXray=true
    else
        die "Xray latest release ${xrayTag} is older than lock ${PADM_LOCK_XRAY_VERSION}"
    fi
    if [[ "${singBoxVersion}" == "${PADM_LOCK_SING_BOX_VERSION#v}" ]]; then
        :
    elif is_newer_semver "${PADM_LOCK_SING_BOX_VERSION#v}" "${singBoxVersion}"; then
        updateSingBox=true
    else
        die "sing-box latest release ${singBoxTag} is older than lock ${PADM_LOCK_SING_BOX_VERSION}"
    fi
    if [[ "${acmeVersion}" == "${PADM_LOCK_ACME_SH_VERSION}" ]]; then
        :
    elif is_newer_semver "${PADM_LOCK_ACME_SH_VERSION}" "${acmeVersion}"; then
        updateAcme=true
    else
        die "acme.sh latest release ${acmeTag} is older than lock ${PADM_LOCK_ACME_SH_VERSION}"
    fi
    if [[ "${updateXray}" == false && "${updateSingBox}" == false && "${updateAcme}" == false ]]; then
        printf 'upstream-lock-current\n'
        return
    fi

    tmpRoot=$(mktemp -d "${TMPDIR:-/tmp}/padm-upstream-refresh.XXXXXX")
    trap 'rm -rf -- "${tmpRoot}"' RETURN
    xrayVersion=${PADM_LOCK_XRAY_VERSION}
    xrayAmd64Asset=${PADM_LOCK_XRAY_AMD64_ASSET}
    xrayAmd64Sha256=${PADM_LOCK_XRAY_AMD64_SHA256}
    xrayArm64Asset=${PADM_LOCK_XRAY_ARM64_ASSET}
    xrayArm64Sha256=${PADM_LOCK_XRAY_ARM64_SHA256}
    singBoxAmd64Asset=${PADM_LOCK_SING_BOX_AMD64_ASSET}
    singBoxAmd64Sha256=${PADM_LOCK_SING_BOX_AMD64_SHA256}
    singBoxArm64Asset=${PADM_LOCK_SING_BOX_ARM64_ASSET}
    singBoxArm64Sha256=${PADM_LOCK_SING_BOX_ARM64_SHA256}
    acmeUrl=${PADM_LOCK_ACME_SH_URL}
    acmeSha256=${PADM_LOCK_ACME_SH_SHA256}

    if [[ "${updateXray}" == true ]]; then
        xrayVersion=${xrayTag}
        xrayAmd64Asset=Xray-linux-64.zip
        xrayArm64Asset=Xray-linux-arm64-v8a.zip
        xrayAmd64Sha256=$(download_sha256 \
            "https://github.com/XTLS/Xray-core/releases/download/${xrayTag}/${xrayAmd64Asset}" \
            "${tmpRoot}/${xrayAmd64Asset}") || die 'failed to download Xray amd64 asset'
        xrayArm64Sha256=$(download_sha256 \
            "https://github.com/XTLS/Xray-core/releases/download/${xrayTag}/${xrayArm64Asset}" \
            "${tmpRoot}/${xrayArm64Asset}") || die 'failed to download Xray arm64 asset'
        changed=true
        printf 'Xray: %s -> %s\n' "${PADM_LOCK_XRAY_VERSION}" "${xrayTag}"
    fi
    if [[ "${updateSingBox}" == true ]]; then
        singBoxAmd64Asset="sing-box-${singBoxVersion}-linux-amd64.tar.gz"
        singBoxArm64Asset="sing-box-${singBoxVersion}-linux-arm64.tar.gz"
        singBoxAmd64Sha256=$(download_sha256 \
            "https://github.com/SagerNet/sing-box/releases/download/${singBoxTag}/${singBoxAmd64Asset}" \
            "${tmpRoot}/${singBoxAmd64Asset}") || die 'failed to download sing-box amd64 asset'
        singBoxArm64Sha256=$(download_sha256 \
            "https://github.com/SagerNet/sing-box/releases/download/${singBoxTag}/${singBoxArm64Asset}" \
            "${tmpRoot}/${singBoxArm64Asset}") || die 'failed to download sing-box arm64 asset'
        changed=true
        printf 'sing-box: %s -> %s\n' "${PADM_LOCK_SING_BOX_VERSION}" "${singBoxTag}"
    else
        singBoxTag=${PADM_LOCK_SING_BOX_VERSION}
    fi
    if [[ "${updateAcme}" == true ]]; then
        acmeUrl="https://codeload.github.com/acmesh-official/acme.sh/tar.gz/refs/tags/${acmeTag}"
        acmeSha256=$(download_sha256 "${acmeUrl}" "${tmpRoot}/acme.sh.tar.gz") ||
            die 'failed to download acme.sh archive'
        changed=true
        printf 'acme.sh: %s -> %s\n' "${PADM_LOCK_ACME_SH_VERSION}" "${acmeVersion}"
    else
        acmeVersion=${PADM_LOCK_ACME_SH_VERSION}
    fi

    [[ "${changed}" == true ]] || die 'upstream refresh did not produce an update'
    awk \
        -v xrayVersion="${xrayVersion}" \
        -v xrayAmd64Asset="${xrayAmd64Asset}" -v xrayAmd64Sha256="${xrayAmd64Sha256}" \
        -v xrayArm64Asset="${xrayArm64Asset}" -v xrayArm64Sha256="${xrayArm64Sha256}" \
        -v singBoxVersion="${singBoxTag}" \
        -v singBoxAmd64Asset="${singBoxAmd64Asset}" -v singBoxAmd64Sha256="${singBoxAmd64Sha256}" \
        -v singBoxArm64Asset="${singBoxArm64Asset}" -v singBoxArm64Sha256="${singBoxArm64Sha256}" \
        -v acmeVersion="${acmeVersion}" -v acmeUrl="${acmeUrl}" -v acmeSha256="${acmeSha256}" '
        BEGIN {
            value["PADM_LOCK_XRAY_VERSION"] = xrayVersion
            value["PADM_LOCK_XRAY_AMD64_ASSET"] = xrayAmd64Asset
            value["PADM_LOCK_XRAY_AMD64_SHA256"] = xrayAmd64Sha256
            value["PADM_LOCK_XRAY_ARM64_ASSET"] = xrayArm64Asset
            value["PADM_LOCK_XRAY_ARM64_SHA256"] = xrayArm64Sha256
            value["PADM_LOCK_SING_BOX_VERSION"] = singBoxVersion
            value["PADM_LOCK_SING_BOX_AMD64_ASSET"] = singBoxAmd64Asset
            value["PADM_LOCK_SING_BOX_AMD64_SHA256"] = singBoxAmd64Sha256
            value["PADM_LOCK_SING_BOX_ARM64_ASSET"] = singBoxArm64Asset
            value["PADM_LOCK_SING_BOX_ARM64_SHA256"] = singBoxArm64Sha256
            value["PADM_LOCK_ACME_SH_VERSION"] = acmeVersion
            value["PADM_LOCK_ACME_SH_URL"] = acmeUrl
            value["PADM_LOCK_ACME_SH_SHA256"] = acmeSha256
        }
        {
            key = $0
            sub(/=.*/, "", key)
            if (key in value) {
                print key "=" value[key]
                seen[key]++
                next
            }
            print
        }
        END {
            for (key in value) if (seen[key] != 1) exit 1
        }
    ' "${LOCK_FILE}" >"${tmpRoot}/versions.lock" || die 'failed to update upstream lock values'
    cp -- "${LOCK_FILE}" "${tmpRoot}/versions.lock.original"
    mv -- "${tmpRoot}/versions.lock" "${LOCK_FILE}"
    if ! (validate_lock); then
        mv -- "${tmpRoot}/versions.lock.original" "${LOCK_FILE}"
        die 'refreshed upstream lock is invalid'
    fi
    trap - RETURN
    rm -rf -- "${tmpRoot}"
    printf 'upstream-lock-updated\n'
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
  docker/release.sh refresh-upstreams
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
refresh-upstreams)
    [[ "$#" -eq 1 ]] || { usage; exit 2; }
    refresh_upstreams
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
