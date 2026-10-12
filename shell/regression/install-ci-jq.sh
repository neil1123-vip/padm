#!/usr/bin/env bash
set -euo pipefail

case "$(uname -m)" in
x86_64)
    asset=jq-linux-amd64
    checksum=b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f
    ;;
aarch64)
    asset=jq-linux-arm64
    checksum=8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309
    ;;
*) echo 'Unsupported jq runner architecture' >&2; exit 1 ;;
esac

binary=$(mktemp)
trap 'rm -f "${binary}"' EXIT
curl -fLSs --retry 3 --connect-timeout 10 --max-time 120 \
    "https://github.com/jqlang/jq/releases/download/jq-1.8.2/${asset}" -o "${binary}"
printf '%s  %s\n' "${checksum}" "${binary}" | sha256sum --check
install -m 0755 "${binary}" /usr/local/bin/jq
[[ "$(jq --version)" == jq-1.8.2 ]]
jq --version
