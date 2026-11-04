#!/usr/bin/env bash

singBoxUpstreamVersion() {
    local version=$1
    [[ "${version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ||
        "${version}" == v1.14.4-padm.1 ]] || return 1
    printf '%s\n' "${version%-padm.1}"
}

singBoxBuildVersion() {
    singBoxUpstreamVersion "$1" >/dev/null || return 1
    case "$1" in
    v1.14.4) printf 'v1.14.4-padm.1\n' ;;
    *) printf '%s\n' "$1" ;;
    esac
}

prepareSingBoxRealitySource() {
    local sourceFile=$1 outputFile=$2 digest
    [[ -s "${sourceFile}" && ! -L "${sourceFile}" ]] || return 1
    digest=$(sha256sum -- "${sourceFile}") || return 1
    [[ "${digest%% *}" == 38a5d553fffd108afca51bde0b0888512d2f4633daa608e03767838b8fdcdbc0 ]] || {
        printf 'sing-box Reality source does not match v1.14.4; refusing patch.\n' >&2
        return 1
    }
    # 固定输入和输出摘要，避免行号补丁误用于其它源码；保留上游认证与证书校验。
    # shortcut: 当前只验证 Chrome 双 share，扩展指纹前须验证私钥选择。
    sed '33d;149,164d' "${sourceFile}" >"${outputFile}" || return 1
    digest=$(sha256sum -- "${outputFile}") || return 1
    [[ "${digest%% *}" == 48f79ad8caa53ace78c54d61e57d1f9e57dfd4bae384081e3ff65654c8fca2de ]]
}

buildSingBoxStatsBinary() (
    set -euo pipefail
    local version arch=$2 sourceDir=$3 binary=$4 file overlayDir=
    version=$(singBoxBuildVersion "$1") || return 1
    [[ "${arch}" == amd64 || "${arch}" == arm64 ]] || return 1
    for file in go.mod go.sum release/DEFAULT_BUILD_TAGS release/LDFLAGS; do
        [[ -s "${sourceDir}/${file}" && ! -L "${sourceDir}/${file}" ]] || return 1
    done
    local -a overlayArgs=()
    if [[ "${version}" == v1.14.4-padm.1 ]]; then
        sourceDir=$(realpath -- "${sourceDir}") || return 1
        overlayDir=$(mktemp -d "${TMPDIR:-/tmp}/padm-sing-box-overlay.XXXXXX") || return 1
        trap 'rm -rf -- "${overlayDir}"' EXIT
        prepareSingBoxRealitySource "${sourceDir}/common/tls/reality_client.go" "${overlayDir}/reality_client.go" || return 1
        jq -n --arg source "${sourceDir}/common/tls/reality_client.go" --arg patched "${overlayDir}/reality_client.go" \
            '{Replace: {($source): $patched}}' >"${overlayDir}/overlay.json" || return 1
        overlayArgs=("-overlay=${overlayDir}/overlay.json")
    fi
    local buildTags ldflags
    buildTags="$(<"${sourceDir}/release/DEFAULT_BUILD_TAGS"),with_purego,with_v2ray_api"
    ldflags="-X github.com/sagernet/sing-box/constant.Version=${version#v} $(<"${sourceDir}/release/LDFLAGS") -s -w -buildid="
    cd -- "${sourceDir}" || return 1
    GOTOOLCHAIN=local CGO_ENABLED=0 GOOS=linux GOARCH="${arch}" \
        go build "${overlayArgs[@]}" -mod=readonly -trimpath -buildvcs=false -tags "${buildTags}" \
        -ldflags "${ldflags}" -o "${binary}" ./cmd/sing-box
)
