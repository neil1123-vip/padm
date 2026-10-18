#!/usr/bin/env bash
set -euo pipefail

[[ "$(uname -s)/$(uname -m)" == Linux/x86_64 ]] || {
    echo 'Unsupported Actionlint runner architecture' >&2
    exit 1
}
directory=$(mktemp -d)
trap 'rm -rf -- "${directory}"' EXIT
archive="${directory}/actionlint.tar.gz"
curl -fLSs --retry 3 --connect-timeout 10 --max-time 120 \
    'https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz' \
    -o "${archive}"
printf '%s  %s\n' '8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8' "${archive}" |
    sha256sum --check
tar -xzf "${archive}" -C "${directory}" actionlint
"${directory}/actionlint" -color
