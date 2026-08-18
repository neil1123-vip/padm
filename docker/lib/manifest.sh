#!/usr/bin/env bash

if [[ "${PADM_DOCKER_MANIFEST_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_MANIFEST_LOADED=1

readonly PADM_DOCKER_RELEASE_MANIFEST_URL_DEFAULT=https://github.com/neil1123-vip/padm/releases/latest/download/release-manifest.json
readonly PADM_DOCKER_COSIGN_IDENTITY_REGEX='^https://github\.com/neil1123-vip/padm/\.github/workflows/create_release\.yml@refs/heads/main$'
readonly PADM_DOCKER_COSIGN_OIDC_ISSUER=https://token.actions.githubusercontent.com
readonly PADM_DOCKER_MANIFEST_MAX_BYTES=2097152
readonly PADM_DOCKER_SIGNATURE_MAX_BYTES=1048576
readonly PADM_DOCKER_BUNDLE_MAX_BYTES=10485760
readonly PADM_DOCKER_CONTROL_BUNDLE_MAX_BYTES=52428800
readonly PADM_DOCKER_MANIFEST_IMAGE_NAMES=(xray sing-box nginx ops net)

PADM_DOCKER_MANIFEST_TEMP_DIR=
PADM_DOCKER_MANIFEST_FILE=
PADM_DOCKER_MANIFEST_SIGNATURE=
PADM_DOCKER_MANIFEST_BUNDLE=
PADM_DOCKER_CONTROL_BUNDLE=
PADM_DOCKER_MANIFEST_SHA256=
PADM_DOCKER_MANIFEST_SIGNATURE_IDENTITY=https://github.com/neil1123-vip/padm/.github/workflows/create_release.yml@refs/heads/main

dockerManifestCleanup() {
    local tempDir=${PADM_DOCKER_MANIFEST_TEMP_DIR:-}
    [[ -n "${tempDir}" ]] || return 0
    dockerManagedPathIsSafe "$(dockerInstallRoot)" "${tempDir}" 2>/dev/null || return 1
    rm -rf -- "${tempDir}"
    PADM_DOCKER_MANIFEST_TEMP_DIR=
    PADM_DOCKER_MANIFEST_FILE=
    PADM_DOCKER_MANIFEST_SIGNATURE=
    PADM_DOCKER_MANIFEST_BUNDLE=
    PADM_DOCKER_CONTROL_BUNDLE=
    PADM_DOCKER_MANIFEST_SHA256=
}

dockerManifestInputCopy() {
    local source=$1 target=$2 maxBytes=$3
    [[ -n "${source}" && -n "${target}" ]] || return 1
    if [[ -f "${source}" && ! -L "${source}" ]]; then
        [[ -O "${source}" ]] || return 1
        cp -- "${source}" "${target}" || return 1
        [[ "$(wc -c <"${target}" | tr -d '[:space:]')" -le "${maxBytes}" ]]
        return $?
    fi
    [[ "${source}" =~ ^https:// ]] || return 1
    declare -F dockerEntryDownloadFile >/dev/null 2>&1 || return 1
    dockerEntryDownloadFile "${source}" "${target}" "${maxBytes}"
}

dockerManifestValidate() {
    local manifest=$1
    [[ -f "${manifest}" && ! -L "${manifest}" ]] || return 1
    jq -e '
      def exact($keys): (keys_unsorted | sort) == ($keys | sort);
      def semver: type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$");
      def digest: type == "string" and test("^sha256:[0-9a-f]{64}$");
      def ref: type == "string" and test("^[a-z0-9][a-z0-9._/-]+:[A-Za-z0-9._-]+@sha256:[0-9a-f]{64}$");
      def image:
        . as $image |
        type == "object" and exact(["reference", "index_digest", "platforms"]) and
        (.reference | ref) and (.index_digest | digest) and
        ($image.reference | endswith("@" + $image.index_digest)) and
        (.platforms as $p |
          ($p | type == "object" and exact(["linux/amd64", "linux/arm64"])) and
          ($p["linux/amd64"] | digest) and ($p["linux/arm64"] | digest));
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
    ' "${manifest}" >/dev/null
}

dockerManifestVerifySignature() {
    local manifest=$1 signature=$2 bundle=$3
    dockerRequireCommand cosign || {
        dockerError '缺少 cosign，拒绝验证 Docker release manifest'
        return 1
    }
    cosign verify-blob --bundle "${bundle}" --signature "${signature}" \
        --certificate-identity-regexp "${PADM_DOCKER_COSIGN_IDENTITY_REGEX}" \
        --certificate-oidc-issuer "${PADM_DOCKER_COSIGN_OIDC_ISSUER}" \
        "${manifest}" >/dev/null 2>&1 || {
        dockerError 'release manifest Cosign 验签失败'
        return 1
    }
}

dockerManifestPrepare() {
    local source=${1:-${PADM_DOCKER_RELEASE_MANIFEST_URL_DEFAULT}}
    local signature=${2:-} bundle=${3:-} controlSource=${4:-}
    local root tempDir arch controlUrl controlSha expectedSha
    dockerManifestCleanup || return 1
    root=$(dockerInstallRoot) || return 1
    tempDir=$(mktemp -d "${root}/.manifest.XXXXXX") || return 1
    dockerManagedPathIsSafe "${root}" "${tempDir}" || {
        rm -rf -- "${tempDir}"
        return 1
    }
    PADM_DOCKER_MANIFEST_TEMP_DIR=${tempDir}
    PADM_DOCKER_MANIFEST_FILE=${tempDir}/release-manifest.json
    PADM_DOCKER_MANIFEST_SIGNATURE=${tempDir}/release-manifest.sig
    PADM_DOCKER_MANIFEST_BUNDLE=${tempDir}/release-manifest.sigstore.json
    PADM_DOCKER_CONTROL_BUNDLE=${tempDir}/padm-docker-bundle.tar.gz
    dockerManifestInputCopy "${source}" "${PADM_DOCKER_MANIFEST_FILE}" "${PADM_DOCKER_MANIFEST_MAX_BYTES}" || {
        dockerError '无法获取 release manifest'
        return 1
    }
    if [[ -z "${signature}" && "${source}" =~ /release-manifest[.]json$ ]]; then
        signature=${source%release-manifest.json}release-manifest.sig
    fi
    if [[ -z "${bundle}" && "${source}" =~ /release-manifest[.]json$ ]]; then
        bundle=${source%release-manifest.json}release-manifest.sigstore.json
    fi
    [[ -n "${signature}" && -n "${bundle}" ]] || {
        dockerError '本地 manifest 必须同时提供 signature 和 Sigstore bundle'
        return 1
    }
    dockerManifestInputCopy "${signature}" "${PADM_DOCKER_MANIFEST_SIGNATURE}" "${PADM_DOCKER_SIGNATURE_MAX_BYTES}" || {
        dockerError '无法获取 release manifest signature'
        return 1
    }
    dockerManifestInputCopy "${bundle}" "${PADM_DOCKER_MANIFEST_BUNDLE}" "${PADM_DOCKER_BUNDLE_MAX_BYTES}" || {
        dockerError '无法获取 release manifest Sigstore bundle'
        return 1
    }
    dockerManifestValidate "${PADM_DOCKER_MANIFEST_FILE}" || {
        dockerError 'release manifest 字段或 schema 无效'
        return 1
    }
    dockerManifestVerifySignature "${PADM_DOCKER_MANIFEST_FILE}" \
        "${PADM_DOCKER_MANIFEST_SIGNATURE}" "${PADM_DOCKER_MANIFEST_BUNDLE}" || return 1
    controlUrl=${controlSource}
    [[ -n "${controlUrl}" ]] || controlUrl=$(jq -er '.control.bundle_url' "${PADM_DOCKER_MANIFEST_FILE}") || return 1
    dockerManifestInputCopy "${controlUrl}" "${PADM_DOCKER_CONTROL_BUNDLE}" "${PADM_DOCKER_CONTROL_BUNDLE_MAX_BYTES}" || {
        dockerError '无法获取 release 控制 bundle'
        return 1
    }
    controlSha=$(sha256sum "${PADM_DOCKER_CONTROL_BUNDLE}" | cut -d ' ' -f 1) || return 1
    expectedSha=$(jq -er '.control.sha256' "${PADM_DOCKER_MANIFEST_FILE}") || return 1
    [[ "${controlSha}" == "${expectedSha}" ]] || {
        dockerError 'release 控制 bundle SHA-256 不匹配'
        return 1
    }
    arch=$(dockerNormalizeArchitecture "$(uname -m 2>/dev/null)") || return 1
    jq -e --arg arch "${arch}" '.compatibility.architectures | index($arch) != null' \
        "${PADM_DOCKER_MANIFEST_FILE}" >/dev/null || {
        dockerError "release manifest 不支持当前架构: ${arch}"
        return 1
    }
    PADM_DOCKER_MANIFEST_SHA256=$(sha256sum "${PADM_DOCKER_MANIFEST_FILE}" | cut -d ' ' -f 1) || return 1
    [[ "${PADM_DOCKER_MANIFEST_SHA256}" =~ ^[0-9a-f]{64}$ ]]
}

dockerManifestImageReference() {
    local name=$1
    [[ "${name}" =~ ^(xray|sing-box|nginx|ops|net)$ ]] || return 1
    [[ -n "${PADM_DOCKER_MANIFEST_FILE}" ]] || return 1
    jq -er --arg name "${name}" '.images[$name].reference' "${PADM_DOCKER_MANIFEST_FILE}"
}

dockerManifestImageDigest() {
    local name=$1
    [[ "${name}" =~ ^(xray|sing-box|nginx|ops|net)$ ]] || return 1
    [[ -n "${PADM_DOCKER_MANIFEST_FILE}" ]] || return 1
    jq -er --arg name "${name}" '.images[$name].index_digest' "${PADM_DOCKER_MANIFEST_FILE}"
}

dockerManifestReleaseVersion() {
    [[ -n "${PADM_DOCKER_MANIFEST_FILE}" ]] || return 1
    jq -er '.release.version' "${PADM_DOCKER_MANIFEST_FILE}"
}
