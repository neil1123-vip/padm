#!/usr/bin/env bash
set -euo pipefail

image=${1:?image reference required}
name=${2:?image name required}

case "${name}" in
xray)
    docker run --rm --pull=never "${image}" version >/dev/null
    ;;
sing-box)
    docker run --rm --pull=never "${image}" version >/dev/null
    ;;
nginx)
    docker run --rm --pull=never "${image}" -t >/dev/null
    ;;
ops|net)
    docker run --rm --pull=never "${image}" health >/dev/null
    ;;
*)
    printf 'unknown image: %s\n' "${name}" >&2
    exit 2
    ;;
esac

printf 'docker-image-smoke-ok: %s\n' "${name}"
