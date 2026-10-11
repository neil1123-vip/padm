#!/usr/bin/env bash

buildSingBoxStatsBinary() (
    set -euo pipefail
    local version=$1 arch=$2 sourceDir=$3 binary=$4 file
    [[ "${version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ]] || return 1
    [[ "${arch}" == amd64 || "${arch}" == arm64 ]] || return 1
    for file in go.mod go.sum release/DEFAULT_BUILD_TAGS release/LDFLAGS; do
        [[ -s "${sourceDir}/${file}" && ! -L "${sourceDir}/${file}" ]] || return 1
    done
    local buildTags ldflags
    buildTags="$(<"${sourceDir}/release/DEFAULT_BUILD_TAGS"),with_purego,with_v2ray_api"
    ldflags="-X github.com/sagernet/sing-box/constant.Version=${version#v} $(<"${sourceDir}/release/LDFLAGS") -s -w -buildid="
    cd -- "${sourceDir}" || return 1
    GOTOOLCHAIN=local CGO_ENABLED=0 GOOS=linux GOARCH="${arch}" \
        go build -mod=readonly -trimpath -buildvcs=false -tags "${buildTags}" \
        -ldflags "${ldflags}" -o "${binary}" ./cmd/sing-box
)
